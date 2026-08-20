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
-- This mirrors netrw's own tree-mode rendering purely so we can match
-- currently-open buffers against the lines netrw already drew. It is a
-- display-matching heuristic, not a second filesystem model: entries
-- that aren't currently visible (e.g. inside a collapsed directory)
-- simply won't match, and those buffers fall back to the "Open
-- Elsewhere" section, which is the documented behaviour.
--
-- Two things netrw's tree mode does that this has to account for:
--   1. It draws guide characters for nesting, not just spaces -- in
--      environments without the Unicode glyphs available it falls back
--      to ASCII, e.g. "|  " per depth level instead of "▾ "/two spaces.
--      Depth is therefore measured by the length of the stripped guide
--      prefix, not by counting literal whitespace.
--   2. The very first real entry (right after "../") is a directory
--      node representing the currently-listed directory ITSELF, not a
--      child of it -- its own name matches curdir's basename. Treating
--      it like a normal child would double up every path underneath
--      it (".../nvim-screen/nvim-screen/LICENSE" instead of
--      ".../nvim-screen/LICENSE").
function M.parse_tree(bufnr, curdir)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local stack = {}
  local entries = {}
  local root_basename = curdir and vim.fn.fnamemodify((curdir:gsub("/$", "")), ":t") or nil
  local seen_root = false

  for lnum, line in ipairs(lines) do
    -- Skip blank lines, netrw's banner/comment lines (g:netrw_banner),
    -- and the "../" parent-directory entry -- none of those are real
    -- files we'd ever need to match an open buffer against.
    if line:match("%S") and not line:match('^%s*"') and not line:match("^%.%./?$") then
      -- Strip the tree-guide prefix: any run of whitespace and/or "|"
      -- guide characters. Its *length* (not a level count) is used as
      -- a monotonic depth key for the stack below -- deeper nesting
      -- always produces a longer prefix than shallower nesting, which
      -- is all the push/pop logic actually needs.
      local guide, rest = line:match("^([%s|]*)(.*)$")
      local depth_key = #guide

      local is_dir = false
      local name = rest

      local glyph = rest:sub(1, 3) -- "▾" / "▸" are 3-byte UTF-8 sequences
      if glyph == "\226\150\190" or glyph == "\226\150\184" then
        is_dir = true
        name = rest:sub(5) -- glyph + following space
      end

      -- netrw's trailing decorations: "/" for directories, and
      -- ls -F-style "*"/"@"/"=" for executable/symlink/socket files.
      local last = name:sub(-1)
      if last == "/" then
        is_dir = true
        name = name:sub(1, -2)
      elseif last == "*" or last == "@" or last == "=" then
        name = name:sub(1, -2)
      end

      local fullpath, is_root_wrapper
      if not seen_root and is_dir and depth_key == 0 and root_basename and name == root_basename then
        -- This line represents curdir itself, not a child of it.
        fullpath = curdir
        is_root_wrapper = true
      else
        while #stack > 0 and stack[#stack].depth_key >= depth_key do
          table.remove(stack)
        end
        local parent = stack[#stack]
        local base = parent and parent.fullpath or curdir
        fullpath = (base and (base:gsub("/$", "")) or "") .. "/" .. name
      end
      seen_root = true

      entries[#entries + 1] = {
        lnum = lnum,
        indent = depth_key,
        name = name,
        is_dir = is_dir,
        fullpath = fullpath,
      }
      if is_dir then
        stack[#stack + 1] = { depth_key = depth_key, fullpath = fullpath }
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
