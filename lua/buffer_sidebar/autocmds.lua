-- lua/buffer_sidebar/autocmds.lua
--
-- Wires refresh into netrw's own lifecycle plus ordinary buffer/terminal/
-- cwd churn. Directory-change detection reuses `FileType netrw`, which
-- netrw itself fires every time it (re)lists a directory in a window --
-- so we don't need to invent our own directory-change tracking.

local M = {}

local group = vim.api.nvim_create_augroup("BufferSidebar", { clear = true })

--- @param opts table with:
--   on_netrw_filetype  fun(bufnr)  -- netrw (re)listed a directory
--   on_state_changed   fun()       -- buffer/terminal/cwd set changed
function M.setup(opts)
  vim.api.nvim_clear_autocmds({ group = group })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "netrw",
    callback = function(args)
      opts.on_netrw_filetype(args.buf)
    end,
    desc = "buffer_sidebar: netrw (re)listed a directory",
  })

  -- Coalesce bursts of buffer events (e.g. closing several buffers at
  -- once) into a single refresh on the next event-loop tick.
  local pending = false
  local function debounced()
    if pending then return end
    pending = true
    vim.schedule(function()
      pending = false
      opts.on_state_changed()
    end)
  end

  vim.api.nvim_create_autocmd({
    "BufAdd", "BufDelete", "BufWipeout", "BufFilePost",
    "TermOpen", "TermClose", "DirChanged",
  }, {
    group = group,
    callback = debounced,
    desc = "buffer_sidebar: buffer/terminal/cwd set changed",
  })
end

return M
