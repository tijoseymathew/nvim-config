-- Run from the repository root:
-- nvim --headless -u NONE -l tests/buffer_sidebar.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
pcall(vim.cmd, "packadd netrw")
vim.cmd("runtime plugin/netrwPlugin.vim")
vim.o.hidden = true
vim.o.swapfile = false
vim.o.columns = 120
vim.o.lines = 40
vim.g.netrw_dirhistmax = 0

local root = vim.fn.tempname() .. "-buffer-sidebar"
vim.fn.mkdir(root, "p")
local jobs = {}
local checks = 0

local function run()
  for _, name in ipairs({ "first.txt", "second.txt" }) do
    vim.fn.writefile({ name }, root .. "/" .. name)
  end
  vim.cmd("cd " .. vim.fn.fnameescape(root))
  vim.cmd("edit first.txt")
  local first = vim.api.nvim_get_current_buf()
  local second = vim.fn.bufadd(root .. "/second.txt")
  vim.bo[second].buflisted = true

  local sidebar = require("buffer_sidebar")
  sidebar.setup()
  local state = sidebar._state
  local ns = vim.api.nvim_get_namespaces().buffer_sidebar

  local function settle()
    vim.wait(10, function() return false end)
  end

  local function expect_active(expected, context)
    settle()
    local actual = {}
    local entries = require("buffer_sidebar.netrw").parse_tree(state.sidebar_buf, root)
    local files_by_row = {}
    for _, entry in ipairs(entries) do
      files_by_row[entry.lnum - 1] = vim.fn.bufnr(entry.fullpath)
    end
    local _, terminal_entries = require("buffer_sidebar.buffers").classify(
      require("buffer_sidebar.buffers").collect(state.sidebar_buf), {})
    for _, buf in ipairs({ state.sidebar_buf, state.terminal_buf }) do
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        if mark[4].line_hl_group then
          assert(mark[4].line_hl_group == "Visual", context .. ": wrong highlight")
          local target
          if buf == state.sidebar_buf then
            target = files_by_row[mark[2]]
          else
            local terminal = terminal_entries[mark[2] - 1]
            target = terminal and terminal.bufnr
          end
          assert(target, context .. ": highlight does not match a buffer row")
          actual[#actual + 1] = target
        end
      end
    end
    assert(vim.deep_equal(actual, expected and { expected } or {}),
      context .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
    checks = checks + 1
  end

  vim.cmd("BufferSidebar show")
  expect_active(first, "opening sidebar retains initial file")
  local listing = vim.api.nvim_buf_get_lines(state.sidebar_buf, 0, -1, false)
  assert(#vim.fn.sign_getplaced(state.sidebar_buf, { group = "buffer_sidebar_labels" })[1].signs == 2)

  vim.api.nvim_set_current_win(state.main_win)
  vim.api.nvim_win_set_buf(state.main_win, second)
  expect_active(second, "switching file in same window")
  vim.api.nvim_set_current_win(state.terminal_win)
  expect_active(second, "focusing terminal list retains file")
  vim.api.nvim_set_current_win(state.sidebar_win)
  expect_active(second, "focusing Explore retains file")
  assert(vim.deep_equal(listing, vim.api.nvim_buf_get_lines(state.sidebar_buf, 0, -1, false)))

  vim.api.nvim_set_current_win(state.main_win)
  vim.cmd("leftabove split")
  local other_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(other_win, first)
  expect_active(first, "other editing window")
  vim.api.nvim_set_current_win(state.main_win)
  expect_active(second, "window switch with both files visible")
  vim.api.nvim_set_current_win(other_win)
  vim.api.nvim_set_current_win(state.terminal_win)
  vim.api.nvim_set_current_win(state.sidebar_win)
  expect_active(first, "same-tick focus and alternate-window guard")
  vim.api.nvim_win_close(other_win, true)

  local function terminal(name)
    vim.api.nvim_set_current_win(state.main_win)
    vim.cmd("enew")
    local buf = vim.api.nvim_get_current_buf()
    jobs[#jobs + 1] = vim.fn.jobstart({ "cat" }, { term = true })
    vim.api.nvim_buf_set_name(buf, name)
    return buf
  end
  local term1 = terminal("shell-one")
  expect_active(term1, "new renamed terminal")
  local term2 = terminal("term://test/shell-two")
  expect_active(term2, "new unrenamed terminal")

  local terminal_label = vim.api.nvim_buf_get_lines(state.terminal_buf, 2, 3, false)[1]:sub(1, 1)
  vim.fn.maparg("g" .. terminal_label, "n", false, true).callback()
  expect_active(term1, "label navigation to terminal")
  vim.api.nvim_set_current_win(state.terminal_win)
  expect_active(term1, "terminal list retains active terminal")
  vim.api.nvim_win_set_cursor(state.terminal_win, { 4, 0 })
  vim.fn.maparg("<CR>", "n", false, true).callback()
  expect_active(term2, "terminal list Enter navigation")

  require("buffer_sidebar.navigation").jump_to_buffer(first)
  expect_active(first, "terminal to file clears terminal highlight")
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
  expect_active(nil, "buffer without a sidebar row clears stale highlight")

  require("buffer_sidebar.navigation").jump_to_buffer(term2)
  vim.api.nvim_buf_delete(term2, { force = true })
  expect_active(vim.api.nvim_get_current_buf() == term1 and term1 or nil,
    "deleting active terminal clears its row")

  require("buffer_sidebar.navigation").jump_to_buffer(second)
  vim.cmd("BufferSidebar hide")
  vim.api.nvim_set_current_buf(first)
  vim.cmd("BufferSidebar show")
  expect_active(first, "hide and reopen after changing buffers")

  vim.cmd("BufferSidebar hide")
  sidebar.setup({ tree_style = false })
  vim.g.netrw_liststyle = 0
  vim.cmd("BufferSidebar show")
  expect_active(first, "flat netrw listing")

  vim.api.nvim_set_current_win(state.main_win)
  vim.api.nvim_buf_delete(first, { force = true })
  local replacement = vim.api.nvim_get_current_buf()
  expect_active((replacement == second or replacement == term1) and replacement or nil,
    "deleting active file clears its row")
  print(("PASS: %d active-buffer scenarios"):format(checks))
end

local ok, err = xpcall(run, debug.traceback)
for _, job in ipairs(jobs) do pcall(vim.fn.jobstop, job) end
vim.fn.delete(root, "rf")
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
