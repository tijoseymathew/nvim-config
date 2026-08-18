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

--- (Re)install g<label> mappings on the sidebar buffer for the current
-- label -> {bufnr} map. Always clears previously-mapped labels first.
function M.apply_labels(sidebar_bufnr, by_label)
  for _, label in ipairs(mapped_labels) do
    pcall(vim.keymap.del, "n", "g" .. label, { buffer = sidebar_bufnr })
  end
  mapped_labels = {}

  for label, target in pairs(by_label) do
    local bufnr = target.bufnr
    vim.keymap.set("n", "g" .. label, function()
      M.jump_to_buffer(bufnr)
    end, {
      buffer = sidebar_bufnr,
      nowait = true,
      silent = true,
      desc = "buffer_sidebar: jump to " .. label,
    })
    mapped_labels[#mapped_labels + 1] = label
  end
end

--- Install the "open existing buffer instead of duplicating" <CR>
-- override. Falls back to netrw's own default <CR> for directories and
-- for files that aren't already open anywhere -- normal Explore
-- behaviour for those is unchanged.
function M.install_smart_cr(sidebar_bufnr)
  local netrw = require("buffer_sidebar.netrw")
  local default_cr = netrw.capture_default_cr(sidebar_bufnr)

  vim.keymap.set("n", "<CR>", function()
    local word = netrw.cursor_word()
    local curdir = netrw.curdir(sidebar_bufnr)

    if not (word and curdir) then
      return netrw.run_default_cr(default_cr)
    end
    if word:sub(-1) == "/" or vim.fn.isdirectory(word) == 1 then
      return netrw.run_default_cr(default_cr)
    end

    local full = vim.fn.fnamemodify(word, ":p")
    local existing = vim.fn.bufnr(full)
    if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then
      M.jump_to_buffer(existing)
    else
      netrw.run_default_cr(default_cr)
    end
  end, {
    buffer = sidebar_bufnr,
    silent = true,
    desc = "buffer_sidebar: open (reuse existing buffer if any)",
  })
end

return M
