-- lua/buffer_sidebar/navigation.lua
--
-- Two-keystroke navigation (g<label>) and "jump to the existing buffer
-- instead of duplicating it" behaviour for <CR> inside the sidebar.
--
-- Only the labels currently in use get a g<label> mapping, and they're
-- torn down and reinstalled on every relabel -- so this never claims a
-- key netrw (or Neovim) wasn't already using for that exact two-key
-- sequence, and it never permanently shadows a `g` motion that isn't
-- currently assigned to a buffer.

local M = {}

local mapped_labels = {}
local main_win_getter -- fun(): winid|nil, injected by init.lua

function M.set_main_win_getter(fn)
  main_win_getter = fn
end

--- Show `bufnr` in the "main" editing window (not the sidebar), reusing
-- a window that already displays it if one exists.
function M.jump_to_buffer(bufnr)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then return end

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == bufnr then
      vim.api.nvim_set_current_win(winid)
      return
    end
  end

  local target = main_win_getter and main_win_getter()
  if not (target and vim.api.nvim_win_is_valid(target)) then
    target = nil
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(winid)].filetype ~= "netrw" then
        target = winid
        break
      end
    end
  end
  if not target then return end

  vim.api.nvim_set_current_win(target)
  vim.api.nvim_win_set_buf(target, bufnr)
end

--- (Re)install g<label> mappings for the current label -> {bufnr} map.
-- These are deliberately GLOBAL (not buffer-local to the sidebar): the
-- point is a two-keystroke jump "from anywhere", not only while focus
-- happens to already be in the sidebar. Only the labels currently in
-- use get a mapping, and they're fully torn down and reinstalled on
-- every relabel, so this never permanently claims a `g` sequence that
-- isn't actively pointing at something.
function M.apply_labels(by_label)
  for _, label in ipairs(mapped_labels) do
    pcall(vim.keymap.del, "n", "g" .. label)
  end
  mapped_labels = {}

  for label, target in pairs(by_label) do
    local bufnr = target.bufnr
    vim.keymap.set("n", "g" .. label, function()
      M.jump_to_buffer(bufnr)
    end, {
      nowait = true,
      silent = true,
      desc = "buffer_sidebar: jump to " .. label,
    })
    mapped_labels[#mapped_labels + 1] = label
  end
end

--- Resolve the window that opened files/buffers should land in: prefer
-- the remembered "main" window, else any currently non-netrw window.
local function resolve_main_window()
  local target = main_win_getter and main_win_getter()
  if target and vim.api.nvim_win_is_valid(target) then
    return target
  end
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(winid)].filetype ~= "netrw" then
      return winid
    end
  end
  return nil
end

--- Open a filesystem path (no buffer for it yet) in the main window.
function M.open_path_in_main(path)
  local target = resolve_main_window()
  if not target then return end
  vim.api.nvim_set_current_win(target)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

--- Install the "open in the main window, reusing an existing buffer
-- instead of duplicating it" <CR> override. Falls back to netrw's own
-- default <CR> only for directories, whose normal expand/descend-in-
-- place behaviour inside the sidebar is left untouched.
function M.install_smart_cr(sidebar_bufnr)
  local netrw = require("buffer_sidebar.netrw")
  local default_cr = netrw.capture_default_cr(sidebar_bufnr)

  vim.keymap.set("n", "<CR>", function()
    local word = netrw.cursor_word()
    local curdir = netrw.curdir(sidebar_bufnr)

    if not (word and curdir) then
      return netrw.run_default_cr(default_cr)
    end

    local is_dir = word:sub(-1) == "/"
    local clean = (word:gsub("/$", ""))
    -- Resolve against netrw's OWN listing directory, not Neovim's
    -- process cwd -- those two are frequently different, which is why
    -- the existing-buffer lookup below needs this to be right.
    local full = word:match("^/")
      and vim.fn.fnamemodify(word, ":p")
      or (curdir:gsub("/$", "") .. "/" .. clean)

    if is_dir or vim.fn.isdirectory(full) == 1 then
      return netrw.run_default_cr(default_cr)
    end

    local existing = vim.fn.bufnr(full)
    if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then
      M.jump_to_buffer(existing)
    else
      M.open_path_in_main(full)
    end
  end, {
    buffer = sidebar_bufnr,
    silent = true,
    desc = "buffer_sidebar: open in main window (reuse existing buffer if any)",
  })
end

return M
