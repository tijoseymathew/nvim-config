-- lua/buffer_sidebar/buffers.lua
--
-- Buffer collection & classification: which listed buffers exist, and
-- whether each is a normal file, a terminal, and whether it lives inside
-- the directory netrw is currently displaying.

local M = {}

--- List candidate buffers: listed, normal-or-terminal buftype, excluding
-- the sidebar's own netrw buffer. The sidebar is deliberately excluded
-- from buffer collection so it never lists itself.
function M.collect(sidebar_bufnr)
  local result = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= sidebar_bufnr
        and vim.api.nvim_buf_is_valid(bufnr)
        and vim.bo[bufnr].buflisted then
      local buftype = vim.bo[bufnr].buftype
      if buftype == "" or buftype == "terminal" then
        result[#result + 1] = bufnr
      end
    end
  end
  table.sort(result) -- deterministic ascending-bufnr order
  return result
end

local function is_terminal(bufnr)
  return vim.bo[bufnr].buftype == "terminal"
end

local function terminal_name(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or name:match("^term://") then
    -- Unrenamed terminal (or no name at all): simple, stable fallback.
    return "[terminal]"
  end
  -- User ran :file to rename it -- use that name as-is.
  return vim.fn.fnamemodify(name, ":t")
end

--- Normalize a path for comparison: absolute, no trailing slash.
local function norm(path)
  if not path or path == "" then return nil end
  local full = vim.fn.fnamemodify(path, ":p")
  return (full:gsub("/$", ""))
end

--- Classify buffers into three groups relative to what netrw is
-- currently showing (`tree_entries`, from netrw.parse_tree):
--   in_tree    { bufnr, entry }        -- entry is the matching tree line
--   elsewhere  { bufnr, display }      -- display is a relative path
--   terminals  { bufnr, display }
function M.classify(bufnrs, tree_entries)
  local by_path = {}
  for _, e in ipairs(tree_entries) do
    if not e.is_dir then
      by_path[norm(e.fullpath)] = e
    end
  end

  local in_tree, elsewhere, terminals = {}, {}, {}

  for _, bufnr in ipairs(bufnrs) do
    if is_terminal(bufnr) then
      terminals[#terminals + 1] = { bufnr = bufnr, display = terminal_name(bufnr) }
    else
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        local p = norm(name)
        local entry = p and by_path[p]
        if entry then
          in_tree[#in_tree + 1] = { bufnr = bufnr, entry = entry }
        else
          -- Relative to cwd where possible, else ~-relative, else full path.
          local rel = vim.fn.fnamemodify(name, ":~:.")
          elsewhere[#elsewhere + 1] = { bufnr = bufnr, display = rel }
        end
      end
    end
  end

  return in_tree, elsewhere, terminals
end

return M
