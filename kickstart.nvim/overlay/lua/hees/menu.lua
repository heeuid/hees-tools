-- A small cascading popup menu that works the same with the mouse and the keyboard.
--
-- Item fields:
--   label    string            text shown in the menu
--   hint     string?           right-aligned key hint (e.g. 'grd', '<leader>sf')
--   action   string|function?  keys to feed (with remap) or a function to call
--   items    table|function?   submenu items (a function is evaluated when the submenu opens)
--   enabled  boolean|function? false greys the item out; it can't be selected
--   checked  boolean?          shows a check mark in front of the label
--   sep      boolean?          a separator line
--
-- Mouse: hover highlights and opens submenus, click runs, click outside closes (and is replayed).
-- Keys:  j/k/↑/↓/Tab move, Enter/l/→/Space run or open, h/←/BS go back, Esc/q close.

local util = require 'hees.util'

local M = {}

local ns = vim.api.nvim_create_namespace 'hees.menu'
local group = vim.api.nvim_create_augroup('hees-menu', { clear = true })

---@class hees.MenuLevel
---@field win integer
---@field buf integer
---@field items table[]
---@field row integer outer top row of the float (editor grid, 0-based)
---@field col integer outer left column
---@field width integer content width
---@field child_of integer? index of the parent item this level hangs off

---@type { levels: hees.MenuLevel[], origin: table? }
local state = { levels = {} }

local function is_enabled(item)
  if item.sep then return false end
  local e = item.enabled
  if type(e) == 'function' then
    local ok, v = pcall(e)
    return ok and v ~= false
  end
  return e ~= false
end

--- Evaluate dynamic parts once per open so rendering and navigation agree.
local function resolve(items)
  local out = {}
  for _, it in ipairs(type(items) == 'function' and items() or items) do
    if it ~= false and it ~= nil then
      local copy = vim.tbl_extend('force', {}, it)
      copy._enabled = is_enabled(it)
      table.insert(out, copy)
    end
  end
  -- Drop leading, trailing and doubled separators left over from conditional items.
  local clean = {}
  for _, it in ipairs(out) do
    if not (it.sep and (#clean == 0 or clean[#clean].sep)) then table.insert(clean, it) end
  end
  while #clean > 0 and clean[#clean].sep do
    table.remove(clean)
  end
  return clean
end

local function level_of_win(win)
  for i, level in ipairs(state.levels) do
    if level.win == win then return i end
  end
end

local function render(items)
  local icons = util.icons()
  local label_w, hint_w = 0, 0
  for _, it in ipairs(items) do
    if not it.sep then
      label_w = math.max(label_w, vim.fn.strdisplaywidth(it.label))
      local right = it.items and icons.submenu or util.key_hint(it.hint) or ''
      hint_w = math.max(hint_w, vim.fn.strdisplaywidth(right))
    end
  end
  local width = 2 + 2 + label_w + (hint_w > 0 and 3 + hint_w or 0) + 1
  local lines, marks = {}, {}
  for i, it in ipairs(items) do
    if it.sep then
      lines[i] = string.rep('─', width)
      table.insert(marks, { i - 1, 0, #lines[i], 'HeesMenuSep' })
    else
      local check = it.checked and icons.check or ' '
      local right = it.items and icons.submenu or util.key_hint(it.hint) or ''
      local left = ' ' .. check .. ' ' .. it.label
      local pad = width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right) - 1
      lines[i] = left .. string.rep(' ', pad) .. right .. ' '
      if not it._enabled then
        table.insert(marks, { i - 1, 0, #lines[i], 'HeesMenuDisabled' })
      else
        if it.checked then table.insert(marks, { i - 1, 1, 1 + #check, 'HeesMenuCheck' }) end
        if right ~= '' then
          local start = #lines[i] - #right - 1
          table.insert(marks, { i - 1, start, start + #right, 'HeesMenuHint' })
        end
      end
    end
  end
  return lines, marks, width
end

local function first_enabled(items, from, step)
  local n = #items
  local i = from
  for _ = 1, n do
    if i < 1 then i = n end
    if i > n then i = 1 end
    if items[i]._enabled then return i end
    i = i + step
  end
end

local function hide_cursor() util.hide_cursor('menu', 'a') end

local function restore_cursor() util.show_cursor 'menu' end

--- Close levels deeper than `depth` (0 closes everything).
local function close_from(depth)
  -- Detach the levels first: closing a window fires WinEnter, which may call back into here.
  local doomed = {}
  for i = #state.levels, depth + 1, -1 do
    table.insert(doomed, table.remove(state.levels, i))
  end
  for _, level in ipairs(doomed) do
    pcall(vim.api.nvim_win_close, level.win, true)
    pcall(vim.api.nvim_buf_delete, level.buf, { force = true })
  end
end

function M.close()
  if #state.levels == 0 then return end
  close_from(0)
  restore_cursor()
  local origin = state.origin
  if origin and vim.api.nvim_win_is_valid(origin.win) then vim.api.nvim_set_current_win(origin.win) end
end

function M.is_open() return #state.levels > 0 end

local map_keys -- forward declaration

---@param items table[] resolved items
---@param row integer desired outer top row
---@param col integer desired outer left col
---@param opts { enter: boolean, flip_col: integer? }
local function open_level(items, row, col, opts)
  local lines, marks, width = render(items)
  local height = #lines
  local max_row = vim.o.lines - vim.o.cmdheight - 1
  if row + height + 2 > max_row then row = math.max(0, max_row - height - 2) end
  if col + width + 2 > vim.o.columns then col = opts.flip_col and math.max(0, opts.flip_col - width - 2) or math.max(0, vim.o.columns - width - 2) end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4], priority = 200 })
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'hees-menu'

  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    zindex = 200 + #state.levels,
    noautocmd = true,
  })
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = 'Normal:HeesMenu,NormalFloat:HeesMenu,FloatBorder:HeesMenuBorder,CursorLine:HeesMenuSel'
  vim.wo[win].scrolloff = 0

  local level = { win = win, buf = buf, items = items, row = row, col = col, width = width }
  table.insert(state.levels, level)
  local first = first_enabled(items, 1, 1) or 1
  vim.api.nvim_win_set_cursor(win, { first, 0 })
  map_keys(buf)
  if opts.enter then vim.api.nvim_set_current_win(win) end
  return level
end

--- Open the submenu of item `idx` in level `depth`.
local function open_sub(depth, idx, enter)
  local level = state.levels[depth]
  local item = level.items[idx]
  if state.levels[depth + 1] and state.levels[depth + 1].child_of == idx then
    if enter then vim.api.nvim_set_current_win(state.levels[depth + 1].win) end
    return
  end
  close_from(depth)
  local items = resolve(item.items)
  if #items == 0 then return end
  local sub = open_level(items, level.row + idx - 1, level.col + level.width + 2, { enter = enter, flip_col = level.col })
  sub.child_of = idx
end

--- Run (or open) item `idx` of level `depth`.
local function activate(depth, idx)
  local level = state.levels[depth]
  local item = level and level.items[idx]
  if not item or not item._enabled then return end
  if item.items then return open_sub(depth, idx, true) end
  local origin = state.origin
  M.close()
  local action = item.action
  if not action then return end
  vim.schedule(function()
    if origin.visual then vim.cmd 'normal! gv' end
    if type(action) == 'string' then
      vim.api.nvim_feedkeys(vim.keycode(action), 'm', false)
    else
      local ok, err = pcall(action, origin)
      if not ok then vim.notify('menu: ' .. tostring(err), vim.log.levels.ERROR) end
    end
  end)
end

local function current()
  local depth = level_of_win(vim.api.nvim_get_current_win()) or #state.levels
  local level = state.levels[depth]
  return depth, level, vim.api.nvim_win_get_cursor(level.win)[1]
end

local function move(step)
  local depth, level, line = current()
  local next_line = first_enabled(level.items, line + step, step)
  if next_line then vim.api.nvim_win_set_cursor(level.win, { next_line, 0 }) end
  close_from(depth)
end

local function back()
  local depth = current()
  if depth <= 1 then return M.close() end
  close_from(depth - 1)
  vim.api.nvim_set_current_win(state.levels[depth - 1].win)
end

--- Replay a click that landed outside the menu so it still does what the user meant.
local function replay(button, mp)
  M.close()
  if mp.screenrow < 1 then return end
  vim.schedule(function() vim.api.nvim_input_mouse(button, 'press', '', 0, mp.screenrow - 1, mp.screencol - 1) end)
end

local function on_click(button)
  local mp = vim.fn.getmousepos()
  local depth = level_of_win(mp.winid)
  if not depth then return replay(button, mp) end
  if mp.line < 1 then return end
  vim.api.nvim_win_set_cursor(mp.winid, { mp.line, 0 })
  activate(depth, mp.line)
end

local function on_hover()
  local mp = vim.fn.getmousepos()
  local depth = level_of_win(mp.winid)
  if not depth or mp.line < 1 then return end
  local level = state.levels[depth]
  local item = level.items[mp.line]
  if not item or not item._enabled then return end
  vim.api.nvim_win_set_cursor(level.win, { mp.line, 0 })
  if item.items then
    open_sub(depth, mp.line, false)
  else
    close_from(depth)
  end
end

map_keys = function(buf)
  local function map(lhs, fn)
    for _, key in ipairs(type(lhs) == 'table' and lhs or { lhs }) do
      vim.keymap.set('n', key, fn, { buffer = buf, nowait = true, silent = true })
    end
  end
  map({ 'j', '<Down>', '<Tab>', '<C-n>', '<ScrollWheelDown>' }, function() move(1) end)
  map({ 'k', '<Up>', '<S-Tab>', '<C-p>', '<ScrollWheelUp>' }, function() move(-1) end)
  map({ '<CR>', 'l', '<Right>', '<Space>' }, function()
    local depth, _, line = current()
    activate(depth, line)
  end)
  map({ 'h', '<Left>', '<BS>' }, back)
  map({ '<Esc>', 'q', '<C-c>' }, M.close)
  map({ '<LeftMouse>', '<2-LeftMouse>' }, function() on_click 'left' end)
  map('<RightMouse>', function() on_click 'right' end)
  map('<MiddleMouse>', function() on_click 'middle' end)
  map({ '<LeftRelease>', '<RightRelease>', '<MiddleRelease>', '<LeftDrag>', '<RightDrag>' }, '<Nop>')
  map('<MouseMove>', on_hover)
end

-- Focus moving to a non-menu window (e.g. <C-w>w) closes the menu.
vim.api.nvim_create_autocmd('WinEnter', {
  group = group,
  callback = function()
    if #state.levels > 0 and not level_of_win(vim.api.nvim_get_current_win()) then
      close_from(0)
      restore_cursor()
    end
  end,
})

--- Open a menu.
---@param items table[]|function
---@param opts { row: integer, col: integer, visual: boolean?, ctx: table? }? position is the 0-based editor cell of the pointer/cursor; defaults to the mouse
function M.open(items, opts)
  M.close()
  opts = opts or {}
  if not opts.row then
    local mp = vim.fn.getmousepos()
    opts.row, opts.col = mp.screenrow - 1, mp.screencol - 1
  end
  local resolved = resolve(items)
  if #resolved == 0 then return end
  state.origin = vim.tbl_extend('force', opts.ctx or {}, { win = vim.api.nvim_get_current_win(), visual = opts.visual })
  -- The float's border sits on the pointer row, so the first item lands just below it.
  open_level(resolved, opts.row, opts.col, { enter = true })
  hide_cursor()
end

--- Screen position just below the cursor, for opening a menu from the keyboard.
---@return integer row, integer col
function M.cursor_anchor()
  local pos = vim.fn.screenpos(0, vim.fn.line '.', vim.fn.col '.')
  if pos.row == 0 then return 1, 0 end
  return pos.row, pos.col - 1
end

return M
