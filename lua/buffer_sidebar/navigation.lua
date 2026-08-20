-- lua/buffer_sidebar/navigation.lua
--
-- Two-keystroke navigation (g<label>) and the Terminals window's <CR>.
--
-- Opening files from inside Explore is NOT handled here: init.lua sets
-- b:netrw_browse_split = 4 on the sidebar buffer, which tells netrw's
-- own <CR> to open the selected file in the previously-focused window
-- rather than in place -- the same thing netrw's own `P` mapping does.
-- That means no custom <CR> override, no replaying of netrw's captured
-- default mapping, and no reimplementing netrw's own path resolution:
-- letting netrw resolve its own paths is what makes this correct for
-- nested/tree-mode entries by construction, rather than something we
-- have to get right ourselves. And opening a path Vim already has a
-- buffer for never creates a second buffer, so "don't duplicate an
-- already-open buffer" falls out for free.
--
-- Only the labels currently in use get a g<label> mapping, and they're
-- torn down and reinstalled on every relabel -- so this never claims a
-- key netrw (or Neovim) wasn't already using for that exact two-key
-- sequence, and it never permanently shadows a `g` motion that isn't
-- currently assigned to a buffer.

local M = {}

local mapped_labels = {}
local main_win_getter -- fun(): winid|nil, injected by init.lua
local sidebar_windows_getter -- fun(): {[winid]=true, ...}|nil, injected by init.lua

function M.set_main_win_getter(fn)
  main_win_getter = fn
end

--- init.lua injects a getter for "the set of windows that belong to the
-- sidebar" (Explore + Terminals), so the fallback below can exclude
-- them explicitly rather than guessing from filetype -- filetype alone
-- can't tell the Terminals window apart from a real editing window,
-- since it isn't filetype "netrw" either.
function M.set_sidebar_windows_getter(fn)
  sidebar_windows_getter = fn
end

--- Resolve the window that "jump to this buffer" should land in: prefer
-- the remembered "main" window, else any currently open window that
-- isn't part of the sidebar itself. Used by g<label> and the Terminals
-- <CR>.
local function resolve_main_window()
  local target = main_win_getter and main_win_getter()
  if target and vim.api.nvim_win_is_valid(target) then
    return target
  end
  local excluded = (sidebar_windows_getter and sidebar_windows_getter()) or {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if not excluded[winid] then
      return winid
    end
  end
  return nil
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

  local target = resolve_main_window()
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

-- Per-buffer line -> terminal bufnr map, refreshed alongside the
-- Terminals window's content (see render.render_terminals). Kept here
-- rather than as a buffer-local var since vim.b can't cleanly round-trip
-- a sparse Lua table (non-contiguous integer keys).
local terminal_line_maps = {}

function M.set_terminal_line_map(term_bufnr, line_map)
  terminal_line_maps[term_bufnr] = line_map
end

--- Install <CR> in the Terminals window: jump to the terminal buffer
-- listed on the current line, if any. Idempotent -- only needs to be
-- set up once, since (unlike netrw) nothing else touches this buffer's
-- mappings.
function M.install_terminal_cr(term_bufnr)
  if vim.b[term_bufnr].buffer_sidebar_term_cr_installed then return end
  vim.b[term_bufnr].buffer_sidebar_term_cr_installed = true

  vim.keymap.set("n", "<CR>", function()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local line_map = terminal_line_maps[term_bufnr]
    local bufnr = line_map and line_map[lnum]
    if bufnr then
      M.jump_to_buffer(bufnr)
    end
  end, {
    buffer = term_bufnr,
    silent = true,
    desc = "buffer_sidebar: open terminal under cursor",
  })
end

return M
