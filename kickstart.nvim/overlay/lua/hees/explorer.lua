-- Explorer (kickstart's neo-tree) behavior on top of its own setup:
--   * In the tree the cursor is hidden in normal mode; the highlighted row (neo-tree's
--     cursorline) shows where you are. Command-line and input prompts still show the cursor.
--   * l / → : directory: expand it, or step into it if already expanded; file: open it.
--     h / ← : collapse the directory, or the parent one from a file (neo-tree's close_node).
-- neo-tree sets its buffer mappings itself (`l` is focus_preview there), so ours are added
-- each time a tree buffer is entered, after neo-tree is done.

local group = vim.api.nvim_create_augroup('hees-explorer', { clear = true })

-- [[ Hidden cursor ]]

local saved_guicursor

local function hide_cursor()
  if saved_guicursor then return end
  saved_guicursor = vim.o.guicursor
  vim.o.guicursor = saved_guicursor .. ',n:HeesHiddenCursor'
end

local function show_cursor()
  if not saved_guicursor then return end
  vim.o.guicursor = saved_guicursor
  saved_guicursor = nil
end

local function sync_cursor()
  if vim.bo.filetype == 'neo-tree' and vim.api.nvim_win_get_config(0).relative == '' then
    hide_cursor()
  else
    show_cursor()
  end
end

vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter', 'FileType' }, { group = group, callback = sync_cursor })
vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = show_cursor })

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
