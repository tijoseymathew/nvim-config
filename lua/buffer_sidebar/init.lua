-- lua/buffer_sidebar/init.lua
--
-- Public API:
--   require("buffer_sidebar").setup({ ... })
--
-- Persistent right-hand sidebar that extends netrw's normal :Explore
-- view with open-buffer and terminal awareness. See README.md for the
-- full design writeup.
--
-- The sidebar column is TWO stacked windows, not one:
--   - a netrw window on top (the real, scrollable Explore view)
--   - a small dedicated "Terminals" window pinned to the bottom
-- Keeping Terminals in its own window (rather than tacked onto netrw's
-- buffer as virtual lines) is what lets it stay visible and fixed-size
-- regardless of how long the Explore listing gets, and lets its labels
-- be plain, real text instead of something that has to coexist with
-- netrw's own buffer content.

local labels_mod = require("buffer_sidebar.labels")
local netrw_mod = require("buffer_sidebar.netrw")
local buffers_mod = require("buffer_sidebar.buffers")
local render_mod = require("buffer_sidebar.render")
local navigation_mod = require("buffer_sidebar.navigation")
local autocmds_mod = require("buffer_sidebar.autocmds")

local M = {}

local config = {
  width = 30,
  labels = labels_mod.default_priority,
  -- Fraction of the sidebar column's height reserved for the Terminals
  -- window at the bottom; netrw gets the rest, capped at that remainder
  -- (it scrolls internally rather than growing).
  terminal_fraction = 1 / 3,
  terminal_min_height = 3,
  -- Tree-mode listing makes the "in current directory hierarchy" nesting
  -- in the spec's examples actually show up; flat listing still works,
  -- it's just one flat level. Set to false to leave netrw's global
  -- liststyle untouched.
  tree_style = true,
}

local state = {
  sidebar_win = nil,   -- netrw window
  sidebar_buf = nil,   -- netrw buffer
  terminal_win = nil,  -- pinned Terminals window
  terminal_buf = nil,  -- its dedicated scratch buffer (persists across hide/show)
  main_win = nil,
  curdir = nil,
}

local function is_sidebar_open()
  return state.sidebar_win ~= nil and vim.api.nvim_win_is_valid(state.sidebar_win)
end

--- Recompute buffer classification, labels, and the two rendering
-- targets (netrw's sign-based file labels, the Terminals buffer's
-- content). Does NOT touch netrw's own listing.
local function refresh_overlays()
  if not (state.sidebar_buf and vim.api.nvim_buf_is_valid(state.sidebar_buf)) then
    return
  end

  local curdir = netrw_mod.curdir(state.sidebar_buf) or state.curdir
  local tree_entries = netrw_mod.parse_tree(state.sidebar_buf, curdir)

  local bufnrs = buffers_mod.collect(state.sidebar_buf)
  local in_tree, terminals = buffers_mod.classify(bufnrs, tree_entries)

  -- Single shared label namespace, assigned in visual top-to-bottom
  -- order: in-tree files, then Terminals.
  local combined = {}
  for _, it in ipairs(in_tree) do combined[#combined + 1] = { kind = "in_tree", v = it } end
  for _, it in ipairs(terminals) do combined[#combined + 1] = { kind = "terminal", v = it } end

  local labelled, by_label = labels_mod.assign(combined, config.labels)

  local in_tree_l, terminals_l = {}, {}
  local nav_by_label = {}
  for _, entry in ipairs(labelled) do
    local wrapped = { label = entry.label, item = entry.item.v }
    if entry.item.kind == "in_tree" then
      in_tree_l[#in_tree_l + 1] = wrapped
    else
      terminals_l[#terminals_l + 1] = wrapped
    end
    nav_by_label[entry.label] = { bufnr = entry.item.v.bufnr }
  end

  render_mod.render(state.sidebar_buf, in_tree_l)

  if state.terminal_buf and vim.api.nvim_buf_is_valid(state.terminal_buf) then
    local line_map = render_mod.render_terminals(state.terminal_buf, terminals_l)
    navigation_mod.set_terminal_line_map(state.terminal_buf, line_map)
  end

  navigation_mod.apply_labels(nav_by_label)
end

local function on_netrw_filetype(bufnr)
  if not is_sidebar_open() then return end
  -- Only react to netrw buffers actually shown in our sidebar window --
  -- the user may well have other, unrelated netrw windows open.
  if vim.api.nvim_get_current_win() ~= state.sidebar_win then return end
  if vim.api.nvim_win_get_buf(state.sidebar_win) ~= bufnr then return end

  state.sidebar_buf = bufnr
  vim.b[bufnr].buffer_sidebar = true
  state.curdir = netrw_mod.curdir(bufnr) or state.curdir

  -- Let netrw open selected files itself, in the previously-focused
  -- window, instead of in place in the sidebar -- this is netrw's own
  -- "P"-style behaviour (see :help netrw-browse-split), set buffer-
  -- local so it only affects this sidebar buffer. Cheap to reassign on
  -- every relist.
  vim.b[bufnr].netrw_browse_split = 4

  refresh_overlays()
end

--- Create (or reuse) the dedicated scratch buffer backing the Terminals
-- window.
local function ensure_terminal_buf()
  if state.terminal_buf and vim.api.nvim_buf_is_valid(state.terminal_buf) then
    return state.terminal_buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "buffer_sidebar_terminals"
  state.terminal_buf = buf
  return buf
end

local function open_sidebar()
  if is_sidebar_open() then
    vim.api.nvim_set_current_win(state.sidebar_win)
    return
  end

  local cur = vim.api.nvim_get_current_win()
  if vim.bo[vim.api.nvim_win_get_buf(cur)].filetype ~= "netrw" then
    state.main_win = cur
  end

  if config.tree_style and vim.g.netrw_liststyle == nil then
    vim.g.netrw_liststyle = 3
  end

  -- Outer vertical split becomes the netrw window.
  vim.cmd(("botright vertical %d split"):format(config.width))
  state.sidebar_win = vim.api.nvim_get_current_win()

  -- Force the sign gutter on for this window specifically, so in-tree
  -- file labels are visible regardless of the user's global/filetype
  -- 'signcolumn' setting (netrw or an ftplugin may otherwise turn it off).
  vim.wo[state.sidebar_win].signcolumn = "yes"
  vim.wo[state.sidebar_win].winfixheight = true

  -- Pinned Terminals window, split off the bottom of the same column.
  local total_h = vim.api.nvim_win_get_height(state.sidebar_win)
  local term_h = math.max(config.terminal_min_height,
    math.floor(total_h * config.terminal_fraction))
  vim.cmd(("belowright %d split"):format(term_h))
  state.terminal_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.terminal_win, ensure_terminal_buf())
  vim.wo[state.terminal_win].winfixheight = true
  vim.wo[state.terminal_win].signcolumn = "no"
  vim.wo[state.terminal_win].number = false
  vim.wo[state.terminal_win].relativenumber = false
  navigation_mod.install_terminal_cr(state.terminal_buf)

  netrw_mod.explore_in_win(state.sidebar_win, state.curdir or vim.fn.getcwd())
  -- The FileType netrw autocmd (on_netrw_filetype) takes it from here.
end

local function close_sidebar()
  if not is_sidebar_open() then return end
  if state.sidebar_buf and vim.api.nvim_buf_is_valid(state.sidebar_buf) then
    state.curdir = netrw_mod.curdir(state.sidebar_buf) or state.curdir
  end
  if state.terminal_win and vim.api.nvim_win_is_valid(state.terminal_win) then
    vim.api.nvim_win_close(state.terminal_win, true)
  end
  vim.api.nvim_win_close(state.sidebar_win, true)
  state.sidebar_win = nil
  state.sidebar_buf = nil
  state.terminal_win = nil
end

local function toggle_sidebar()
  if is_sidebar_open() then
    close_sidebar()
  else
    open_sidebar()
  end
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  navigation_mod.set_main_win_getter(function()
    return state.main_win
  end)

  autocmds_mod.setup({
    on_netrw_filetype = on_netrw_filetype,
    on_state_changed = refresh_overlays,
  })

  vim.api.nvim_create_user_command("BufferSidebar", function(cmd_opts)
    local arg = cmd_opts.args
    if arg == "show" then
      open_sidebar()
    elseif arg == "hide" then
      close_sidebar()
    else
      toggle_sidebar()
    end
  end, {
    nargs = "?",
    complete = function()
      return { "show", "hide", "toggle" }
    end,
    desc = "Show/hide/toggle the persistent Explore sidebar",
  })
end

-- Exposed for tests / advanced use; not part of the documented surface.
M._state = state
M._refresh_overlays = refresh_overlays

return M
