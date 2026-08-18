-- lua/buffer_sidebar/init.lua
--
-- Public API:
--   require("buffer_sidebar").setup({ ... })
--
-- Persistent right-hand sidebar that extends netrw's normal :Explore
-- view with open-buffer and terminal awareness. See README.md for the
-- full design writeup.

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
  -- Tree-mode listing makes the "in current directory hierarchy" nesting
  -- in the spec's examples actually show up; flat listing still works,
  -- it's just one flat level. Set to false to leave netrw's global
  -- liststyle untouched.
  tree_style = true,
}

local state = {
  sidebar_win = nil,
  sidebar_buf = nil,
  main_win = nil,
  curdir = nil,
}

local function is_sidebar_open()
  return state.sidebar_win ~= nil and vim.api.nvim_win_is_valid(state.sidebar_win)
end

--- Recompute buffer classification, labels, and overlays. Does NOT touch
-- netrw's own listing -- only the extra visual layer.
local function refresh_overlays()
  if not (state.sidebar_buf and vim.api.nvim_buf_is_valid(state.sidebar_buf)) then
    return
  end

  local curdir = netrw_mod.curdir(state.sidebar_buf) or state.curdir
  local tree_entries = netrw_mod.parse_tree(state.sidebar_buf, curdir)

  local bufnrs = buffers_mod.collect(state.sidebar_buf)
  local in_tree, elsewhere, terminals = buffers_mod.classify(bufnrs, tree_entries)

  -- Single shared label namespace, assigned in visual top-to-bottom
  -- order: Open Elsewhere, then in-tree files, then Terminals.
  local combined = {}
  for _, it in ipairs(elsewhere) do combined[#combined + 1] = { kind = "elsewhere", v = it } end
  for _, it in ipairs(in_tree) do combined[#combined + 1] = { kind = "in_tree", v = it } end
  for _, it in ipairs(terminals) do combined[#combined + 1] = { kind = "terminal", v = it } end

  local labelled, by_label = labels_mod.assign(combined, config.labels)

  local elsewhere_l, in_tree_l, terminals_l = {}, {}, {}
  local nav_by_label = {}
  for _, entry in ipairs(labelled) do
    local wrapped = { label = entry.label, item = entry.item.v }
    if entry.item.kind == "elsewhere" then
      elsewhere_l[#elsewhere_l + 1] = wrapped
    elseif entry.item.kind == "in_tree" then
      in_tree_l[#in_tree_l + 1] = wrapped
    else
      terminals_l[#terminals_l + 1] = wrapped
    end
    nav_by_label[entry.label] = { bufnr = entry.item.v.bufnr }
  end

  render_mod.render(state.sidebar_buf, elsewhere_l, in_tree_l, terminals_l)
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

  navigation_mod.install_smart_cr(bufnr)
  refresh_overlays()
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

  vim.cmd(("botright vertical %d split"):format(config.width))
  state.sidebar_win = vim.api.nvim_get_current_win()

  if config.tree_style and vim.g.netrw_liststyle == nil then
    vim.g.netrw_liststyle = 3
  end

  netrw_mod.explore_in_win(state.sidebar_win, state.curdir or vim.fn.getcwd())
  -- The FileType netrw autocmd (on_netrw_filetype) takes it from here.
end

local function close_sidebar()
  if not is_sidebar_open() then return end
  if state.sidebar_buf and vim.api.nvim_buf_is_valid(state.sidebar_buf) then
    state.curdir = netrw_mod.curdir(state.sidebar_buf) or state.curdir
  end
  vim.api.nvim_win_close(state.sidebar_win, true)
  state.sidebar_win = nil
  state.sidebar_buf = nil
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
