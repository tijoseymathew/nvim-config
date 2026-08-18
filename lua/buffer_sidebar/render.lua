-- lua/buffer_sidebar/render.lua
--
-- All visual overlay logic lives here. Netrw's own buffer text is never
-- modified -- everything below is virtual text/lines and signs layered
-- on top, so netrw's line-based bookkeeping (bookmarks, history, gx,
-- marks) stays intact.

local M = {}

local ns = vim.api.nvim_create_namespace("buffer_sidebar")
local SIGN_GROUP = "buffer_sidebar_labels"

local function header_line(text)
  return {
    { text, "Title" },
  }
end

local function rule_line()
  return {
    { string.rep("─", 15), "Comment" },
  }
end

local function entry_line(label, display)
  return {
    { label .. "  ", "Function" },
    { display, "Normal" },
  }
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

--- Render the full overlay onto the sidebar's netrw buffer.
-- @param bufnr       sidebar netrw buffer
-- @param elsewhere   list of { label, item = { bufnr, display } }
-- @param in_tree     list of { label, item = { bufnr, entry } }
-- @param terminals   list of { label, item = { bufnr, display } }
function M.render(bufnr, elsewhere, in_tree, terminals)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })

  -- "Open Elsewhere": virtual lines above netrw's first line.
  if #elsewhere > 0 then
    local virt_lines = { header_line("Open Elsewhere"), rule_line() }
    for _, labelled in ipairs(elsewhere) do
      virt_lines[#virt_lines + 1] = entry_line(labelled.label, labelled.item.display)
    end
    vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
      virt_lines = virt_lines,
      virt_lines_above = true,
    })
  end

  -- In-tree labels: a sign-column marker next to netrw's own line for
  -- that file. The listing text itself is never touched.
  for _, labelled in ipairs(in_tree) do
    local sign = define_sign(labelled.label)
    vim.fn.sign_place(0, SIGN_GROUP, sign, bufnr, {
      lnum = labelled.item.entry.lnum,
      priority = 20,
    })
  end

  -- "Terminals": virtual lines below netrw's last line.
  local last = vim.api.nvim_buf_line_count(bufnr)
  if #terminals > 0 and last > 0 then
    local virt_lines = { header_line("Terminals"), rule_line() }
    for _, labelled in ipairs(terminals) do
      virt_lines[#virt_lines + 1] = entry_line(labelled.label, labelled.item.display)
    end
    vim.api.nvim_buf_set_extmark(bufnr, ns, last - 1, 0, {
      virt_lines = virt_lines,
      virt_lines_above = false,
    })
  end
end

return M
