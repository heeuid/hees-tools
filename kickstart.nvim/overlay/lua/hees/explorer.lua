-- Explorer (kickstart's neo-tree) behavior on top of its own setup:
--   * In the tree the cursor is hidden in normal mode; the highlighted row (neo-tree's
--     cursorline, colored from the scheme's selection color) shows where you are. Command-line
--     and input prompts still show the cursor. When focus leaves the tree (mouse or keys) the
--     row turns pale, and strong again when focus comes back.
--   * l / → : directory: expand it, or step into it if already expanded; file: open it.
--     h / ← : collapse the directory, or the parent one from a file (neo-tree's close_node).
-- neo-tree sets its buffer mappings itself (`l` is focus_preview there), so ours are added
-- each time a tree buffer is entered, after neo-tree is done.

local group = vim.api.nvim_create_augroup('hees-explorer', { clear = true })

-- [[ Hidden cursor ]]
-- Hidden only while the current window is a neo-tree tree (not its popups); everywhere else the
-- cursor is shown. Rechecked on window/buffer changes and whenever Neovim goes idle (SafeState),
-- which also covers neo-tree switching windows with autocommands turned off. While the
-- right-click menu is focused it owns the cursor (hees.util tracks both reasons).

local util = require 'hees.util'

local function sync_cursor()
  local ft = vim.bo.filetype
  if ft == 'hees-menu' then return end
  if ft == 'neo-tree' and vim.api.nvim_win_get_config(0).relative == '' then
    util.hide_cursor('explorer', 'n')
  else
    util.show_cursor 'explorer'
  end
end

vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter', 'FileType', 'SafeState' }, { group = group, callback = sync_cursor })
vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = function() util.show_cursor 'explorer' end })

-- [[ Row highlight ]]
-- With the cursor hidden, the row highlight is the only position marker, and many colorschemes
-- keep CursorLine (which neo-tree's NeoTreeCursorLine links to) nearly invisible on purpose.
-- Use the scheme's own selection color instead: every scheme makes Visual readable on its
-- background. Schemes that select with `reverse` start from Normal's background with 18% of its
-- text color mixed in. If the row is still too close to the background (luminance contrast under
-- 1.5, e.g. pale yellow on white), more text color is mixed in, as long as the text on it keeps a
-- contrast of 4.5. Recomputed on every colorscheme change.

local function hl(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end

local function mix(a, b, t)
  local out = 0
  for shift = 16, 0, -8 do
    local ca, cb = math.floor(a / 2 ^ shift) % 256, math.floor(b / 2 ^ shift) % 256
    out = out * 256 + math.floor(ca + (cb - ca) * t + 0.5)
  end
  return out
end

-- WCAG relative luminance and contrast ratio of 0xRRGGBB colors.
local function luminance(c)
  local sum = 0
  for i, weight in ipairs { 0.2126, 0.7152, 0.0722 } do
    local v = (math.floor(c / 2 ^ (24 - 8 * i)) % 256) / 255
    sum = sum + weight * (v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4)
  end
  return sum
end

local function contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

local function set_row_highlight()
  local visual, normal = hl 'Visual', hl 'Normal'
  local light = vim.o.background == 'light'
  local base = normal.bg or (light and 0xffffff or 0x000000)
  local text = normal.fg or (light and 0x000000 or 0xffffff)
  local bg = (visual.bg and not visual.reverse) and visual.bg or mix(base, text, 0.18)
  local t = 0
  while contrast(bg, base) < 1.5 and t < 0.5 do
    t = t + 0.05
    local next_bg = mix(bg, text, t)
    if contrast(next_bg, text) < 4.5 then break end
    bg = next_bg
  end
  vim.api.nvim_set_hl(0, 'NeoTreeCursorLine', { bg = bg, bold = true })
  -- Unfocused tree: 40% of the way from the background, at least a contrast of 1.15 so it stays visible.
  local dim, k = mix(base, bg, 0.4), 0.4
  while contrast(dim, base) < 1.15 and k < 1 do
    k = k + 0.1
    dim = mix(base, bg, k)
  end
  vim.api.nvim_set_hl(0, 'NeoTreeCursorLineNC', { bg = dim })
end

set_row_highlight()
-- Scheduled so it runs after neo-tree re-creates its own groups for the new scheme.
vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = function() vim.schedule(set_row_highlight) end })

-- [[ Dim when unfocused ]]
-- neo-tree maps CursorLine:NeoTreeCursorLine in its windows' 'winhighlight'. Tree windows other
-- than the current one get NeoTreeCursorLineNC instead, so only the focused list shows the strong
-- row. Checked on the same events as the cursor (SafeState covers mouse clicks and neo-tree's
-- noautocmd window switches). While the right-click menu is open nothing changes, so a tree
-- right-clicked keeps its strong row.

local ACTIVE, INACTIVE = 'CursorLine:NeoTreeCursorLine', 'CursorLine:NeoTreeCursorLineNC'

local function sync_focus()
  local cur = vim.api.nvim_get_current_win()
  if vim.bo[vim.api.nvim_win_get_buf(cur)].filetype == 'hees-menu' then return end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == 'neo-tree' and vim.api.nvim_win_get_config(win).relative == '' then
      local whl = vim.wo[win].winhighlight
      local from, to = INACTIVE, ACTIVE
      if win ~= cur then from, to = ACTIVE, INACTIVE end
      local entries = vim.split(whl, ',', { plain = true })
      for i, e in ipairs(entries) do
        if e == from then entries[i] = to end
      end
      local want = table.concat(entries, ',')
      if want ~= whl then vim.wo[win].winhighlight = want end
    end
  end
end

vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter', 'SafeState' }, { group = group, callback = sync_focus })

-- [[ h / l ]]

local function tree_state()
  local ok, manager = pcall(require, 'neo-tree.sources.manager')
  if not ok then return nil end
  local state = manager.get_state_for_window()
  if not state or not state.tree then return nil end
  return state
end

local function commands(state) return require('neo-tree.sources.' .. state.name .. '.commands') end

local function expand_or_open()
  local state = tree_state()
  local node = state and state.tree:get_node()
  if not node then return end
  if node.type == 'directory' and node:is_expanded() then
    if #node:get_child_ids() > 0 then vim.cmd 'normal! j' end
  elseif node.type == 'directory' or node.type == 'file' then
    commands(state).open(state)
  end
end

local function collapse()
  local state = tree_state()
  if state then pcall(commands(state).close_node, state) end
end

local function map_keys(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'neo-tree' then return end
  local function map(lhs, fn, desc) vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc }) end
  map('l', expand_or_open, 'Explorer: expand directory / open file')
  map('<Right>', expand_or_open, 'Explorer: expand directory / open file')
  map('h', collapse, 'Explorer: collapse directory / go to parent')
  map('<Left>', collapse, 'Explorer: collapse directory / go to parent')
end

local ok, events = pcall(require, 'neo-tree.events')
if ok then
  events.subscribe {
    event = events.NEO_TREE_BUFFER_ENTER,
    id = 'hees-explorer-keys',
    handler = function()
      local buf = vim.api.nvim_get_current_buf()
      vim.schedule(function() map_keys(buf) end)
    end,
  }
end
