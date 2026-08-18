-- lua/buffer_sidebar/labels.lua
--
-- Deterministic label assignment for the buffer sidebar. Files and
-- terminals share one namespace, drawn from a single ordered priority
-- list, and are (re)assigned from scratch every time the underlying
-- item list changes.

local M = {}

-- Home-row-first, avoids the most common single-letter Vim motions
-- landing on a bare "g<letter>" that users would expect to still work
-- as a count/register prefix, etc. Easy to override via setup({labels = {...}}).
M.default_priority = {
  "a", "s", "d", "f", "h", "j", "k", "l", ";",
  "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
  "z", "x", "c", "v", "b", "n", "m",
}

--- Assign labels to a list of items, in order.
-- @param items  list of arbitrary items; list order determines label order
-- @param priority  optional list of single-char label strings
-- @return labelled  list of {label = <string>, item = <item>}, same order as items
-- @return by_label  map label -> item
function M.assign(items, priority)
  priority = priority or M.default_priority

  local labelled = {}
  local by_label = {}

  for i, item in ipairs(items) do
    local label = priority[i]
    if not label then
      -- Ran out of labels. Remaining items simply stay unlabelled/
      -- unreachable via g<label>; they're still shown in the sidebar.
      break
    end
    labelled[#labelled + 1] = { label = label, item = item }
    by_label[label] = item
  end

  return labelled, by_label
end

return M
