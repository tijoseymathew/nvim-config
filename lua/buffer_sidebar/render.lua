-- lua/buffer_sidebar/render.lua
--
-- Two independent rendering targets:
--   render()           -- in-tree file labels, as signs on netrw's own
--                          buffer. Netrw's buffer text is never modified.
--   render_terminals() -- the dedicated Terminals buffer's content. This
--                          buffer is entirely ours (a plain scratch
--                          buffer, not netrw), so it's built from real
--                          lines rather than virtual overlays -- which
--                          is what lets it live in its own pinned
--                          window, independent of netrw's scrolling.

local M = {}

local ns = vim.api.nvim_create_namespace("buffer_sidebar")
local SIGN_GROUP = "buffer_sidebar_labels"

local function highlight_active(bufnr, row)
  vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
    line_hl_group = "Visual",
    priority = 200,
  })
end

local defined_signs = {}
local function define_sign(label)
  local name = "BufSidebar_" .. label
  if not defined_signs[label] then
    vim.fn.sign_define(name, { text = label .. " ", texthl = "Function" })
    defined_signs[label] = true
  end
  return name
end

--- Render in-tree file labels as signs on netrw's own buffer. Signs sit
-- in a fixed gutter and never touch the line's real text, so they're
-- indifferent to netrw's listing style (flat vs tree, ASCII vs Unicode
-- guides) -- the label lines up the same way regardless. Visibility is
-- guaranteed by forcing 'signcolumn' on for the sidebar window (see
-- init.lua) rather than relying on the user's global setting.
-- @param bufnr    sidebar netrw buffer
-- @param in_tree  list of { label, item = { bufnr, entry } }
-- @param active_buf  buffer currently shown outside the sidebar
function M.render(bufnr, in_tree, active_buf)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, labelled in ipairs(in_tree) do
    local lnum = labelled.item.entry.lnum
    if lnum >= 1 and lnum <= line_count then
      local sign = define_sign(labelled.label)
      vim.fn.sign_place(0, SIGN_GROUP, sign, bufnr, {
        lnum = lnum,
        priority = 20,
      })
      if labelled.item.bufnr == active_buf then
        highlight_active(bufnr, lnum - 1)
      end
    end
  end
end

--- Rebuild the Terminals window's buffer content as plain text lines:
--   Terminals
--   ─────────
--   j  dev-server
--   k  python
--
-- Returns a line-number -> bufnr map (for <CR> in that window; see
-- navigation.install_terminal_cr).
-- @param bufnr      the dedicated Terminals scratch buffer
-- @param terminals  list of { label, item = { bufnr, display } }
-- @param active_buf  buffer currently shown outside the sidebar
function M.render_terminals(bufnr, terminals, active_buf)
  if not vim.api.nvim_buf_is_valid(bufnr) then return {} end

  local lines = { "Terminals", string.rep("─", 15) }
  local label_lens = {} -- lnum -> length of the "label  " prefix, for highlight
  local line_map = {}

  if #terminals == 0 then
    lines[#lines + 1] = "(none)"
  else
    for _, labelled in ipairs(terminals) do
      local prefix = labelled.label .. "  "
      lines[#lines + 1] = prefix .. labelled.item.display
      label_lens[#lines] = #prefix
      line_map[#lines] = labelled.item.bufnr
    end
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", 1, 0, -1)
  for lnum, len in pairs(label_lens) do
    vim.api.nvim_buf_add_highlight(bufnr, ns, "Function", lnum - 1, 0, len)
    if line_map[lnum] == active_buf then
      highlight_active(bufnr, lnum - 1)
    end
  end

  return line_map
end

return M
