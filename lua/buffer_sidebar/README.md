# buffer_sidebar

A persistent right-hand sidebar that extends normal netrw `:Explore`
with awareness of currently open buffers and terminals, reachable in
two keystrokes.

> Explore remains Explore; the sidebar simply makes the current working
> set visible and directly navigable.

## Install & setup

Drop `lua/buffer_sidebar/` on your runtimepath (e.g. as a local plugin
with lazy.nvim: `{ dir = "~/path/to/buffer_sidebar" }`), then:

```lua
require("buffer_sidebar").setup({
  width = 30,                          -- sidebar width in columns
  labels = { "a","s","d","f","h","j","k","l",";",
             "q","w","e","r","t","y","u","i","o","p",
             "z","x","c","v","b","n","m" },
  tree_style = true,                    -- sets g:netrw_liststyle = 3 if unset
})

vim.keymap.set("n", "<leader>e", "<cmd>BufferSidebar<CR>")
```

## Usage

- `:BufferSidebar` / `:BufferSidebar toggle` — toggle the sidebar
- `:BufferSidebar show` / `:BufferSidebar hide` — explicit open/close
- Inside the sidebar: normal netrw navigation and `<CR>` work as usual.
  If the file under the cursor already has an open buffer, `<CR>` jumps
  to that buffer instead of opening a duplicate. Everything else (entering
  directories, going up, `gh`, marks, etc.) is untouched netrw behaviour.
- From **anywhere** in the editor: `g<label>` (e.g. `ga`, `gs`) jumps
  directly to the file or terminal currently shown with that label in
  the sidebar. Labels are reassigned deterministically whenever the set
  of open buffers/terminals changes, so they're always a fresh, stable
  two-keystroke shortcut to "what's currently open."

## How it fits together

```
lua/buffer_sidebar/
├── init.lua        -- setup(), sidebar window lifecycle, orchestration
├── netrw.lua        -- reads netrw's own state; never re-implements it
├── buffers.lua       -- collects + classifies open buffers/terminals
├── labels.lua        -- deterministic label assignment
├── render.lua        -- virtual-line/sign overlays on netrw's buffer
├── navigation.lua     -- g<label> mappings + "reuse existing buffer" <CR>
└── autocmds.lua       -- refresh triggers
```

The sidebar window runs a completely normal netrw `Explore` buffer.
`buffer_sidebar` never draws its own directory tree or maintains a
second filesystem model — it reads netrw's `b:netrw_curdir` and the text
netrw already rendered, and layers three things on top *without editing
netrw's buffer text*:

- an **"Open Elsewhere"** block, drawn as virtual lines above netrw's
  first line, for open buffers outside the current Explore tree
- a **label sign** in the sign column next to any netrw listing line
  whose file already has an open buffer
- a **"Terminals"** block, drawn as virtual lines below netrw's last
  line

Because none of this touches netrw's actual buffer content, netrw's own
line-based bookkeeping (history, bookmarks, marks, `gx`, etc.) is
unaffected, and normal `:Explore` keeps working exactly as it always
has, in and out of the sidebar.

Refreshing reuses netrw's own lifecycle: netrw sets `filetype=netrw`
every time it (re)lists a directory, so that `FileType netrw` event is
what drives "the Explore directory changed" refreshes, rather than
`buffer_sidebar` tracking netrw's navigation itself. Buffer/terminal/cwd
churn (`BufAdd`, `BufDelete`, `TermOpen`, `TermClose`, `DirChanged`,
...) triggers a lighter debounced refresh of just the overlay.

## Known limitations

- **Tree-line matching is a display heuristic.** `netrw.parse_tree`
  reconstructs paths from netrw's on-screen indentation/glyphs to figure
  out which listing line corresponds to which open buffer. It matches
  what's *currently visible*; a file inside a collapsed subdirectory
  won't be matched and will show up under "Open Elsewhere" instead,
  which is consistent with not maintaining a second filesystem model.
- **The `<CR>` fallback replays netrw's captured mapping**, since netrw's
  internal open/browse functions aren't documented public API. This is
  a best-effort shim, not a reimplementation of `NetrwBrowseX`, and its
  exact mechanics (`maparg` shape) can vary slightly across Neovim
  versions.
- **`tree_style = true`** sets the *global* `g:netrw_liststyle` (only if
  unset), since netrw's tree glyphs are what make nested directories
  visually distinguishable per the spec's examples. Set it to `false` if
  you manage `netrw_liststyle` yourself.
