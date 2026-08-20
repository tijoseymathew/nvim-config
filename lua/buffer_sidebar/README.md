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
  width = 30,                          -- sidebar column width in columns
  terminal_fraction = 1 / 3,           -- Terminals window's share of the column height
  terminal_min_height = 3,
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
- The sidebar column is two stacked windows: a normal, scrollable netrw
  Explore view on top, and a small **Terminals** window pinned to the
  bottom.
- In the Explore window: normal netrw navigation works as usual. Files
  that already have an open buffer show a label in the sign column.
  `<CR>` opens the selected file in whatever window you were in before
  you focused the sidebar (netrw's own `b:netrw_browse_split = 4`
  behaviour, the same thing its `P` mapping does) rather than in place
  in the sidebar -- and since opening a path that's already got a
  buffer never creates a second buffer, this also means you land on the
  existing buffer instead of a duplicate, for free. `<CR>` on a
  directory is untouched netrw behaviour.
- In the Terminals window: `<CR>` on a line jumps to that terminal.
- From **anywhere**: `g<label>` (e.g. `ga`, `gs`) jumps directly to the
  file or terminal currently shown with that label. Labels are
  reassigned deterministically whenever the set of open buffers/
  terminals changes.

## How it fits together

```
lua/buffer_sidebar/
├── init.lua        -- setup(), the two-window sidebar lifecycle, orchestration
├── netrw.lua        -- reads netrw's own state; never re-implements it
├── buffers.lua       -- collects + classifies open buffers/terminals
├── labels.lua        -- deterministic label assignment
├── render.lua        -- sign-based file labels + the Terminals buffer's content
├── navigation.lua     -- g<label> mappings + Terminals-window <CR>
└── autocmds.lua       -- refresh triggers
```

The **Explore window** runs a completely normal netrw `Explore` buffer.
`buffer_sidebar` never draws its own directory tree, maintains a second
filesystem model, or reimplements netrw's file-opening -- it reads
netrw's `b:netrw_curdir` and the text netrw already rendered
(`netrw.parse_tree`) purely to figure out which listing line belongs to
which open buffer, and layers file labels on top as **signs**, which
sit in a fixed gutter and never touch netrw's real buffer text. Opening
a file is left entirely to netrw itself via `b:netrw_browse_split = 4`
(set on the sidebar buffer only), so netrw resolves its own paths --
correctly, for nested tree entries and after directory changes, by
construction -- and there's no custom `<CR>` mapping to get wrong. That
also keeps netrw's own line-based bookkeeping (history, bookmarks,
marks, `gx`, etc.) completely unaffected, in flat or tree listing style
alike.

The **Terminals window** is a separate, dedicated scratch buffer that
`buffer_sidebar` fully owns, pinned to the bottom of the sidebar column
(`winfixheight`, sized as a fraction of the column at open time). Since
it's not sharing space or a scrollback with netrw's buffer, it stays
visible and fixed-size no matter how long the Explore listing gets, and
its labels are just plain leading text in real buffer lines.

Refreshing reuses netrw's own lifecycle where possible: netrw sets
`filetype=netrw` every time it (re)lists a directory, so that
`FileType netrw` event is what drives "the Explore directory changed"
refreshes. Buffer/terminal/cwd churn (`BufAdd`, `BufDelete`,
`TermOpen`, `TermClose`, `DirChanged`, ...) triggers a lighter debounced
refresh of both windows' content.

## Known limitations

- **Tree-line matching is a display heuristic.** `netrw.parse_tree`
  reconstructs paths from netrw's on-screen indentation/guide characters
  to figure out which listing line corresponds to which open buffer. It
  matches what's *currently visible*; a file inside a collapsed
  subdirectory won't be matched, and simply won't have a label -- there's
  no "Open Elsewhere" fallback section.
- **`netrw_browse_split = 4` opens files in the "previously-focused"
  window**, which is Vim's own alternate-window concept. In the very
  common case (main window <-> Explore window) this is exactly the main
  window. If you instead focus the Terminals window and then jump
  straight into Explore without passing through the main window first,
  the "previous window" netrw uses could technically be the Terminals
  window. This is an edge case in normal usage and not specifically
  guarded against, in the interest of keeping this thin.
- **`g<label>` mappings are global**, not scoped to any one window,
  since the point is a two-keystroke jump from wherever you're currently
  editing. They're fully torn down and reinstalled every relabel, so a
  letter is only ever shadowed while it's actively pointing at an open
  buffer/terminal -- but a currently-assigned label does take priority
  over whatever `g<letter>` normally does (e.g. `gj`/`gk`/`gh`/`g;` are
  real motions). Pass a `labels` list without those letters in `setup()`
  if you'd rather avoid the overlap entirely.
- **`tree_style = true`** sets the *global* `g:netrw_liststyle` (only if
  unset), since netrw's tree glyphs/guides are what make nested
  directories visible in the first place. Set it to `false` if you
  manage `netrw_liststyle` yourself.
