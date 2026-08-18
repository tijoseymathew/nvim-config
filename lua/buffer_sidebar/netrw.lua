-- lua/buffer_sidebar/netrw.lua
--
-- Thin integration layer over netrw. This module never renders a
-- directory tree of its own; it only reads netrw's own buffer state
-- (b:netrw_curdir, the listing text netrw already produced) and nudges
-- netrw's window/buffer lifecycle. All actual filesystem browsing stays
-- inside netrw.

local M = {}

--- Open (or re-open) netrw Explore in the given window.
function M.explore_in_win(winid, dir)
  vim.api.nvim_set_current_win(winid)
  if dir and dir ~= "" and vim.fn.isdirectory(dir) == 1 then
    vim.cmd("Explore " .. vim.fn.fnameescape(dir))
  else
    vim.cmd("Explore")
  end
end

--- The directory netrw is currently listing in `bufnr`, if any.
function M.curdir(bufnr)
  local ok, dir = pcall(function()
    return vim.b[bufnr].netrw_curdir
  end)
  if ok and dir and dir ~= "" then
    return dir
  end
  return nil
end

--- Parse the on-screen netrw tree listing into a flat list of entries:
--   { lnum, indent, name, is_dir, fullpath }
--
-- This mirrors netrw's own tree-mode indentation (2 spaces per depth,
-- "▾"/"▸" glyphs on expanded/collapsed directories) purely so we can
-- match currently-open buffers against the lines netrw already drew.
-- It is a display-matching heuristic, not a second filesystem model:
-- entries that aren't currently visible (e.g. inside a collapsed
-- directory) simply won't match, and those buffers fall back to the
-- "Open Elsewhere" section, which is the documented behaviour.
function M.parse_tree(bufnr, curdir)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local stack = {}
  local entries = {}

  for lnum, line in ipairs(lines) do
    if line:match("%S") then
      local indent = #(line:match("^(%s*)"))
      local rest = line:sub(indent + 1)
      local is_dir = false
      local name = rest

      local glyph = rest:sub(1, 3) -- "▾" / "▸" are 3-byte UTF-8 sequences
      if glyph == "\226\150\190" or glyph == "\226\150\184" then
        is_dir = true
        name = rest:sub(5) -- glyph + following space
      elseif rest:sub(-1) == "/" then
        is_dir = true
      end
      name = name:gsub("/$", "")

      while #stack > 0 and stack[#stack].indent >= indent do
        table.remove(stack)
      end
      local parent = stack[#stack]
      local base = parent and parent.fullpath or curdir
      local fullpath = (base and (base:gsub("/$", "")) or "") .. "/" .. name

      entries[#entries + 1] = {
        lnum = lnum,
        indent = indent,
        name = name,
        is_dir = is_dir,
        fullpath = fullpath,
      }
      if is_dir then
        stack[#stack + 1] = { indent = indent, fullpath = fullpath }
      end
    end
  end

  return entries
end

--- Best-effort "word under cursor" in a netrw listing line -- i.e. the
-- filename netrw itself would act on for <CR>/gx.
function M.cursor_word()
  local ok, word = pcall(vim.fn.expand, "<cfile>")
  if ok and word and word ~= "" then
    return word
  end
  return nil
end

--- Capture netrw's own buffer-local normal-mode <CR> mapping so we can
-- defer to it for anything we don't special-case (directories, files
-- that aren't already open anywhere). Best-effort: netrw's mapping
-- internals aren't a documented public API and can vary across Neovim
-- versions, but capturing-and-replaying the existing mapping (rather
-- than reimplementing NetrwBrowseX) keeps us from duplicating netrw's
-- own open logic.
function M.capture_default_cr(bufnr)
  local map = vim.fn.maparg("<CR>", "n", false, true)
  if map and map.buffer == 1 then
    return map
  end
  return nil
end

--- Replay a previously-captured default <CR> mapping.
function M.run_default_cr(map)
  if not map then return end
  if map.callback then
    map.callback()
  elseif map.rhs and map.rhs ~= "" then
    local keys = vim.api.nvim_replace_termcodes(map.rhs, true, false, true)
    vim.api.nvim_feedkeys(keys, "n", false)
  end
end

return M
