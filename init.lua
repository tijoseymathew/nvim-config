-- ============================================================================
-- Neovim configuration
-- ============================================================================
--
-- This file is intentionally kept minimal.
--
-- Principle:
--   1. Use Neovim's built-in features where possible.
--   2. Add a plugin only when it solves a problem we actually have.
--   3. Prefer simple configuration that we can understand and maintain.
--
-- Leader key:
--   <leader> is a special key used as a prefix for our custom shortcuts.
--   We use SPACE because it is easy to reach and is commonly used in
--   modern Neovim configurations.
-- ============================================================================

vim.g.mapleader = " "


-- ============================================================================
-- Appearance / basic editor behaviour
-- ============================================================================

-- Show the current line number.
vim.opt.number = true

-- Show relative line numbers for other lines.
--
-- Example:
--      3  some code
--      2  some code
--      1  current line
--      0  current line
--      1  some code
--      2  some code
--
-- This makes commands such as "3j" / "3k" convenient.
vim.opt.relativenumber = true

-- Highlight the line containing the cursor.
vim.opt.cursorline = true

-- Keep search results highlighted after searching.
vim.opt.hlsearch = true

-- ============================================================================
-- Clipboard
-- ============================================================================

-- Use the system clipboard for normal yank and paste operations.
vim.opt.clipboard = "unnamedplus"

-- Use OSC 52 for copying to the local Mac clipboard over SSH.
-- Do not query the terminal for clipboard contents when pasting.
local osc52 = require("vim.ui.clipboard.osc52")

vim.g.clipboard = {
  name = "OSC 52 (copy only)",
  copy = {
    ["+"] = osc52.copy("+"),
    ["*"] = osc52.copy("*"),
  },
  paste = nil,
}

-- ============================================================================
-- Command-line completion
-- ============================================================================

-- Show a menu when completing commands.
--
-- For example, typing:
--
--     :e ~/.config/n
--
-- allows Neovim to offer matching paths.
vim.opt.wildmenu = true

-- How Neovim should behave while completing commands:
--
--   longest = complete the unambiguous portion first
--   list    = show the available matches
vim.opt.wildmode = { "longest", "list" }


-- ============================================================================
-- Terminal
-- ============================================================================

-- Leave Terminal-mode with Esc.
-- Ctrl-\ Ctrl-N remains available when we need to send Esc to a program
-- running inside the terminal.
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", {
  desc = "Exit terminal mode",
})

-- Send a literal Escape key to the program running inside the terminal.
--
-- We use <Esc> to leave Terminal-mode, which means programs running inside
-- the terminal (vim, fzf, less, lazygit, etc.) never receive an Escape key.
--
-- Pressing Ctrl-] instead sends a real Escape character (ASCII 27) directly
-- to the terminal application.
vim.keymap.set("t", "<C-]>", function()
  if vim.b.terminal_job_id then
    vim.api.nvim_chan_send(vim.b.terminal_job_id, "\27")
  end
end, {
  desc = "Send Escape to terminal",
})

-- Open a new terminal in the current window.
vim.keymap.set("n", "<leader>t", function()
  vim.cmd.terminal()
end, {
  desc = "Open terminal",
})


-- ============================================================================
-- Windows
-- ============================================================================

-- Open an empty buffer in a horizontal split.
vim.keymap.set("n", "<leader>sh", function()
  vim.cmd.new()
end, {
  desc = "Horizontal split",
})

-- Open an empty buffer in a vertical split.
vim.keymap.set("n", "<leader>sv", function()
  vim.cmd.vnew()
end, {
  desc = "Vertical split",
})


-- ============================================================================
-- Buffers
-- ============================================================================

-- Delete the current buffer.
vim.keymap.set("n", "<leader>bd", function()
  vim.cmd.bdelete()
end, {
  desc = "Delete buffer",
})

-- Open the current buffer in a new tabpage (simulating zoom).
vim.keymap.set("n", "<leader>bz", function()
  vim.cmd.tabedit("%")
end, {
  desc = "Open buffer in new tab",
})

-- Go to the previous buffer.
vim.keymap.set("n", "<leader><Tab>", "<C-^>", {
  desc = "Previous buffer",
})


-- ============================================================================
-- Plugins
-- ============================================================================

-- Telescope and its dependency are installed by Neovim's built-in plugin
-- manager, but are not loaded until we actually use them.
vim.pack.add({
  "https://github.com/nvim-lua/plenary.nvim",
  "https://github.com/nvim-telescope/telescope.nvim",
})


-- ============================================================================
-- Telescope
-- ============================================================================

-- Load Telescope and its dependency only when we actually need Telescope.
local function load_telescope()
  vim.cmd.packadd("plenary.nvim")
  vim.cmd.packadd("telescope.nvim")
end

-- Find files with <leader>ff.
vim.keymap.set("n", "<leader>ff", function()
  load_telescope()
  require("telescope.builtin").find_files()
end, {
  desc = "Find files",
})

-- Search for text across files with <leader>fg.
vim.keymap.set("n", "<leader>fg", function()
  load_telescope()
  require("telescope.builtin").live_grep()
end, {
  desc = "Search text",
})

-- Switch between open buffers with <leader>fb.
vim.keymap.set("n", "<leader>fb", function()
  load_telescope()
  require("telescope.builtin").buffers()
end, {
  desc = "Find buffers",
})
require("buffer_sidebar").setup()
