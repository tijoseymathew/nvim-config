--------------------------------------------------------------------------------
-- buffer_sidebar
--
-- A small, dependency-free Neovim module that keeps a persistent sidebar
-- window listing open buffers (files and terminals, grouped separately) and
-- lets you jump to any of them with a two-keystroke shortcut: `g` followed
-- by the buffer's current label (e.g. `ga`).
--
-- Usage:
--   require("buffer_sidebar").setup()
--
-- The module is organised into clearly separated sections:
--   1. Configuration
--   2. State
--   3. Buffer collection
--   4. Label assignment
--   5. Sidebar rendering
--   6. Navigation
--   7. Autocommands
--   8. Public API (setup)
--------------------------------------------------------------------------------

local M = {}

--------------------------------------------------------------------------------
-- 1. Configuration
--------------------------------------------------------------------------------

-- Default configuration. Passed-in options from setup() are merged on top of
-- this table, so users only need to override what they care about.
local default_config = {
  -- Width (in columns) of the sidebar window.
  width = 28,

  -- Ordered label priority list. Labels are handed out to buffers in this
  -- order, so the first entries should be the most comfortable to type.
  -- Avoid letters that would create a conflict with a builtin motion when
  -- combined with `prefix` below (the classic example being `g` + `g`).
  labels = {
    "a", "s", "d", "f", "h", "j", "k", "l", ";",
    "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
    "z", "x", "c", "v", "b", "n", "m",
  },

  -- Key pressed before a label to trigger navigation, e.g. "g" -> "ga".
  -- Mapped globally in normal mode. Note that this necessarily shadows any
  -- builtin `<prefix><label>` mapping that happens to collide with one of
  -- the configured labels (e.g. "g" + "f" would shadow the builtin `gf`
  -- unless "f" is removed from `labels` or `prefix` is changed).
  prefix = "g",

  -- Section headers, in display order.
  section_titles = {
    files = "Files",
    terminals = "Terminals",
  },
}

--------------------------------------------------------------------------------
-- 2. State
--------------------------------------------------------------------------------

-- All mutable module state lives here so it's easy to see what the plugin
-- is tracking at a glance.
local state = {
  config = nil,          -- resolved config (defaults + user overrides)
  sidebar_buf = nil,      -- bufnr of the sidebar buffer
  sidebar_win = nil,      -- winid of the sidebar window
  label_to_buf = {},      -- { [label] = bufnr }
  buf_to_label = {},      -- { [bufnr] = label }
  keymaps_set = false,    -- guards against registering navigation keymaps twice
}

--------------------------------------------------------------------------------
-- 3. Buffer collection
--------------------------------------------------------------------------------

-- Returns a human-friendly display name for a buffer.
-- Files: the tail of the file path (what `:t` on the full path would give).
-- Terminals: the buffer name if it has been renamed via `:file`, otherwise
-- a cleaned-up version of the `term://...` name (just the command).
local function display_name(bufnr, buftype)
  local name = vim.api.nvim_buf_get_name(bufnr)

  if name == "" then
    return "[No Name]"
  end

  if buftype == "terminal" then
    -- Default terminal names look like: term://~/project//12345:/bin/zsh
    -- If the user has renamed the buffer with `:file`, `name` will no
    -- longer match this pattern and we just show its tail as-is.
    local command = name:match("^term://.-//%d+:(.*)$")
    if command then
      return vim.fn.fnamemodify(command, ":t")
    end
    return vim.fn.fnamemodify(name, ":t")
  end

  return vim.fn.fnamemodify(name, ":t")
end

-- Decides whether a buffer should be shown in the sidebar at all, and if
-- so, which group ("files" or "terminals") it belongs to.
-- Returns nil for buffers that should be excluded entirely.
local function classify_buffer(bufnr)
  if bufnr == state.sidebar_buf then
    return nil
  end

  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end

  if not vim.api.nvim_buf_get_option(bufnr, "buflisted") then
    return nil
  end

  local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")

  if buftype == "terminal" then
    return "terminals"
  elseif buftype == "" then
    return "files"
  end

  -- Excludes: nofile (scratch), help, quickfix, prompt, acwrite, etc.
  return nil
end

-- Walks all buffers and returns two ordered lists:
--   files      = { { bufnr = ..., name = ... }, ... }
--   terminals  = { { bufnr = ..., name = ... }, ... }
-- Ordered by bufnr ascending, which keeps label assignment stable between
-- refreshes as long as the underlying buffer set doesn't change.
local function collect_buffers()
  local files, terminals = {}, {}

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local group = classify_buffer(bufnr)
    if group then
      local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
      local entry = { bufnr = bufnr, name = display_name(bufnr, buftype) }
      if group == "files" then
        table.insert(files, entry)
      else
        table.insert(terminals, entry)
      end
    end
  end

  table.sort(files, function(a, b) return a.bufnr < b.bufnr end)
  table.sort(terminals, function(a, b) return a.bufnr < b.bufnr end)

  return files, terminals
end

--------------------------------------------------------------------------------
-- 4. Label assignment
--------------------------------------------------------------------------------

-- Assigns labels to every buffer in `files` followed by `terminals`, in
-- that order, from the configured label pool. Files and terminals share a
-- single label namespace, as required.
-- Mutates state.label_to_buf / state.buf_to_label.
local function assign_labels(files, terminals)
  state.label_to_buf = {}
  state.buf_to_label = {}

  local pool = state.config.labels
  local index = 1

  local function assign_all(list)
    for _, entry in ipairs(list) do
      local label = pool[index]
      if not label then
        -- Ran out of labels; remaining buffers simply won't be reachable
        -- via a shortcut (still visible in the sidebar, unlabeled).
        break
      end
      state.label_to_buf[label] = entry.bufnr
      state.buf_to_label[entry.bufnr] = label
      entry.label = label
      index = index + 1
    end
  end

  assign_all(files)
  assign_all(terminals)
end

--------------------------------------------------------------------------------
-- 5. Sidebar rendering
--------------------------------------------------------------------------------

local function build_lines(files, terminals)
  local lines = {}

  local function add_section(title, entries)
    table.insert(lines, title)
    table.insert(lines, string.rep("─", #title))
    if #entries == 0 then
      table.insert(lines, "(none)")
    else
      for _, entry in ipairs(entries) do
        local label = entry.label or " "
        table.insert(lines, string.format("%s  %s", label, entry.name))
      end
    end
  end

  add_section(state.config.section_titles.files, files)
  table.insert(lines, "")
  add_section(state.config.section_titles.terminals, terminals)

  return lines
end

local function ensure_sidebar_buf()
  if state.sidebar_buf and vim.api.nvim_buf_is_valid(state.sidebar_buf) then
    return state.sidebar_buf
  end

  local bufnr = vim.api.nvim_create_buf(false, true) -- unlisted, scratch
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "buffer_sidebar")
  vim.api.nvim_buf_set_name(bufnr, "[Buffer Sidebar]")

  state.sidebar_buf = bufnr
  return bufnr
end

local function ensure_sidebar_win()
  if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
    return state.sidebar_win
  end

  local bufnr = ensure_sidebar_buf()
  local current_win = vim.api.nvim_get_current_win()

  vim.cmd("botright vertical " .. state.config.width .. "split")
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)

  vim.api.nvim_win_set_option(winid, "number", false)
  vim.api.nvim_win_set_option(winid, "relativenumber", false)
  vim.api.nvim_win_set_option(winid, "signcolumn", "no")
  vim.api.nvim_win_set_option(winid, "wrap", false)
  vim.api.nvim_win_set_option(winid, "cursorline", true)
  vim.api.nvim_win_set_option(winid, "winfixwidth", true)

  state.sidebar_win = winid

  -- Restore focus to whatever window was active before we opened the
  -- sidebar, so opening it doesn't steal focus from the user's work.
  if vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end

  return winid
end

-- Recomputes the buffer list, reassigns labels, and redraws the sidebar
-- buffer contents. Safe to call frequently; it's cheap and idempotent.
function M.refresh()
  if not state.sidebar_buf or not vim.api.nvim_buf_is_valid(state.sidebar_buf) then
    return
  end

  local files, terminals = collect_buffers()
  assign_labels(files, terminals)
  local lines = build_lines(files, terminals)

  vim.api.nvim_buf_set_option(state.sidebar_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.sidebar_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.sidebar_buf, "modifiable", false)
end

--------------------------------------------------------------------------------
-- 6. Navigation
--------------------------------------------------------------------------------

-- Switches the current window to the buffer currently assigned to `label`,
-- if any. Silently does nothing for an unknown/unassigned label.
function M.go_to_label(label)
  local bufnr = state.label_to_buf[label]
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- If we're inside the sidebar itself, jump out to the nearest other
  -- window first so the buffer opens somewhere useful.
  local current_win = vim.api.nvim_get_current_win()
  if current_win == state.sidebar_win then
    vim.cmd("wincmd p")
    if vim.api.nvim_get_current_win() == state.sidebar_win then
      -- No other window existed; open a split to the left of the sidebar.
      vim.cmd("leftabove vsplit")
    end
  end

  vim.api.nvim_set_current_buf(bufnr)
end

-- Registers the `<prefix><label>` normal-mode keymaps, e.g. "ga", "gs", ...
-- Called once from setup(); guarded so repeated setup() calls don't stack
-- duplicate mappings.
local function setup_keymaps()
  if state.keymaps_set then
    return
  end

  for _, label in ipairs(state.config.labels) do
    local lhs = state.config.prefix .. label
    vim.keymap.set("n", lhs, function()
      M.go_to_label(label)
    end, { desc = "buffer_sidebar: go to buffer '" .. label .. "'", silent = true })
  end

  state.keymaps_set = true
end

--------------------------------------------------------------------------------
-- 7. Autocommands
--------------------------------------------------------------------------------

-- Events that mean "the set of open buffers or their names may have
-- changed" and therefore the sidebar should be redrawn.
local REFRESH_EVENTS = {
  "BufAdd",
  "BufDelete",
  "BufWipeout",
  "BufFilePost",  -- fires on `:file` renames, including terminal renames
  "TermOpen",
  "TermClose",
  "BufEnter",     -- cheap safety net for stray cases (e.g. buflisted toggles)
}

-- `:bdelete` (and similar) close the window that displayed the deleted
-- buffer whenever another window exists to fall back to. If the sidebar is
-- the only other window around, it becomes the last window left in the
-- tabpage, and Neovim expands the last remaining window to fill the whole
-- screen -- exactly like closing any other split down to one. This guards
-- against that: whenever a window closes and leaves the sidebar as the
-- sole window in its tabpage, we immediately open a fresh empty buffer
-- next to it so the sidebar keeps its fixed width instead of taking over.
local function prevent_sidebar_takeover()
  if not (state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win)) then
    return
  end

  local wins = vim.api.nvim_tabpage_list_wins(0)
  if #wins == 1 and wins[1] == state.sidebar_win then
    -- Splitting from inside the sidebar divides *its own* space in half;
    -- restore its configured width afterwards so it stays a fixed-width
    -- sidebar rather than a second half-screen pane.
    vim.cmd("leftabove vsplit")
    vim.cmd("enew")
    vim.api.nvim_win_set_width(state.sidebar_win, state.config.width)
  end
end

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("BufferSidebar", { clear = true })

  vim.api.nvim_create_autocmd(REFRESH_EVENTS, {
    group = group,
    callback = function()
      -- Defer so the triggering operation (buffer creation/deletion/rename)
      -- has fully completed before we re-scan the buffer list.
      vim.schedule(M.refresh)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function()
      vim.schedule(function()
        prevent_sidebar_takeover()
        M.refresh()
      end)
    end,
  })

  -- Keep the sidebar's window options intact if some other plugin/command
  -- messes with global window layout (e.g. after `:only` in another split).
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
        vim.api.nvim_win_set_width(state.sidebar_win, state.config.width)
      end
    end,
  })
end

--------------------------------------------------------------------------------
-- 8. Public API
--------------------------------------------------------------------------------

-- Opens (or focuses) the sidebar window if it isn't already open.
function M.open()
  ensure_sidebar_win()
  M.refresh()
end

-- Closes the sidebar window (buffer and labels are kept around so it can
-- be reopened cheaply).
function M.close()
  if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
    vim.api.nvim_win_close(state.sidebar_win, true)
  end
  state.sidebar_win = nil
end

function M.toggle()
  if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
    M.close()
  else
    M.open()
  end
end

-- Entry point. Merges user config over the defaults, opens the sidebar,
-- registers autocommands, and sets up the `g<label>` navigation keymaps.
function M.setup(opts)
  state.config = vim.tbl_deep_extend("force", {}, default_config, opts or {})

  setup_autocmds()
  setup_keymaps()
  M.open()
end

return M
