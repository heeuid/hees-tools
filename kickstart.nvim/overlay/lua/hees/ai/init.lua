-- AI features (Claude / Codex / Gemini CLI): next-edit suggestions (hees.nes), code analysis with
-- LSP context (hees.ai.analyze), analysis of a paused debug session (hees.ai.debug), and a viewer
-- for every request they made (hees.ai.viewer). Each task can use its own backend and model
-- (hees.ai.settings). This module wires the commands, keys and the right-click submenu.

local analyze = require 'hees.ai.analyze'
local backends = require 'hees.ai.backends'
local ai_debug = require 'hees.ai.debug'
local nes = require 'hees.nes'
local settings = require 'hees.ai.settings'
local viewer = require 'hees.ai.viewer'

local M = {}

--- Cancel whatever AI request is running.
function M.cancel()
  nes.cancel()
  analyze.cancel()
end

--- Submenu of one task: its backend, model, reset.
local function task_items(task)
  return function()
    local backend, _, own_backend = settings.resolve(task)
    local backend_items = {
      { label = '기본 따르기 (' .. settings.backend() .. ')', checked = not own_backend, action = function() settings.set_task_backend(task, nil) end },
    }
    for _, name in ipairs(backends.names) do
      local available = backends.available(name)
      table.insert(backend_items, {
        label = name .. (available and '' or '  (not installed)'),
        checked = own_backend and name == backend,
        enabled = available,
        action = function() settings.set_task_backend(task, name) end,
      })
    end
    return {
      { label = 'Backend', items = backend_items },
      { label = 'Model for ' .. backend .. '…', action = function() settings.set_task_model(task, nil) end },
      { label = 'Reset to defaults', action = function() settings.reset_task(task) end },
    }
  end
end

--- Default backend, and every task with what it runs on.
local function settings_items()
  local default_items = {}
  for _, name in ipairs(backends.names) do
    local available = backends.available(name)
    table.insert(default_items, {
      label = name .. (available and '' or '  (not installed)'),
      checked = name == settings.backend(),
      enabled = available,
      action = function() settings.set_backend(name) end,
    })
  end
  local items = { { label = '전체 기본 백엔드: ' .. settings.backend(), hint = '<leader>ab', items = default_items }, { sep = true } }
  for _, task in ipairs(settings.tasks) do
    table.insert(items, { label = ('%s: %s'):format(settings.labels[task], settings.describe(task)), items = task_items(task) })
  end
  return items
end

-- [[ Keyboard pickers: task first, then its backend or model ]]

local function pick_task(prompt, with_default, on_choice)
  local choices = with_default and { 'default' } or {}
  vim.list_extend(choices, settings.tasks)
  vim.ui.select(choices, {
    prompt = prompt,
    format_item = function(task)
      if task == 'default' then return '전체 기본 백엔드: ' .. settings.backend() end
      return ('%s: %s'):format(settings.labels[task], settings.describe(task))
    end,
  }, function(task)
    if task then on_choice(task) end
  end)
end

--- <leader>ab: choose a task (or the default), then its backend.
function M.pick_backend()
  pick_task('백엔드를 바꿀 작업', true, function(task)
    if task == 'default' then return settings.select_backend() end
    local current, _, own = settings.resolve(task)
    local choices = vim.list_extend({ 'default' }, vim.deepcopy(backends.names))
    vim.ui.select(choices, {
      prompt = settings.labels[task] .. ' 백엔드',
      format_item = function(name)
        if name == 'default' then return (not own and '● ' or '  ') .. '기본 따르기 (' .. settings.backend() .. ')' end
        return ((own and name == current) and '● ' or '  ') .. name .. (backends.available(name) and '' or '  (설치 안 됨)')
      end,
    }, function(name)
      if name then settings.set_task_backend(task, name ~= 'default' and name or nil) end
    end)
  end)
end

--- <leader>am: choose a task, then its model (for the backend it runs with).
function M.pick_model()
  pick_task('모델을 바꿀 작업', false, function(task) settings.set_task_model(task, nil) end)
end

--- <leader>as: the backends & models menu at the cursor (keyboard: j/k, Enter, h, Esc).
function M.open_settings()
  local menu = require 'hees.menu'
  local row, col = menu.cursor_anchor()
  menu.open(settings_items, { row = row, col = col })
end

--- The AI submenu of the right-click menu.
function M.menu_items(visual)
  local function range()
    vim.cmd 'normal! \27'
    return { vim.fn.line "'<", vim.fn.line "'>" }
  end
  local function task(name)
    return function()
      if visual then return analyze.run(name, { range = range() }) end
      analyze.run(name)
    end
  end
  local scope = visual and 'selection' or 'function at cursor'
  return vim.list_extend(nes.menu_items(visual), {
    { sep = true },
    { label = 'Explain ' .. scope, hint = '<leader>ax', action = task 'explain' },
    { label = 'Review ' .. scope .. ' for bugs', hint = '<leader>ar', action = task 'review' },
    { label = 'Ask about ' .. scope .. '…', hint = '<leader>aq', action = task 'ask' },
    { label = 'Debug state', hint = '<leader>ag', items = M.debug_items, enabled = ai_debug.is_stopped },
    { label = 'Cancel running request', hint = '<leader>ac', action = M.cancel, enabled = function() return nes.is_busy() or analyze.is_busy() end },
    { sep = true },
    { label = 'Backends & models', hint = '<leader>as', items = settings_items },
    { label = 'Auto next-edit suggest', hint = '<leader>at', checked = settings.auto(), action = function() settings.set_auto() end },
    { label = 'Request log', hint = '<leader>al', action = viewer.open },
  })
end

--- Debug-state items (also used by the Debug submenu of the right-click menu).
function M.debug_items()
  return {
    { label = 'Ask AI why it stopped here', hint = '<leader>ag', action = function() ai_debug.run() end, enabled = ai_debug.is_stopped },
    { label = 'Ask AI about this state…', action = function() ai_debug.run { ask = true } end, enabled = ai_debug.is_stopped },
  }
end

local function task_command(rest)
  local name, what, value = rest:match '^(%S+)%s*(%S*)%s*(.*)$'
  if not name or not settings.labels[name] then return vim.notify('Usage: :Ai task {' .. table.concat(settings.tasks, '|') .. '} {backend|model|reset} [value|default]', vim.log.levels.WARN) end
  if what == 'reset' then return settings.reset_task(name) end
  if what == 'backend' then return settings.set_task_backend(name, value ~= '' and value ~= 'default' and value or nil) end
  if what == 'model' then
    if value == '' then return settings.set_task_model(name, nil) end
    return settings.set_task_model(name, value ~= 'default' and value or '')
  end
  vim.notify(('AI: %s → %s'):format(settings.labels[name], settings.describe(name)))
end

local subcommands = {
  explain = function() analyze.run 'explain' end,
  review = function() analyze.run 'review' end,
  ask = function(rest) analyze.run('ask', { question = rest ~= '' and rest or nil }) end,
  debug = function(rest) ai_debug.run { question = rest ~= '' and rest or nil } end,
  cancel = M.cancel,
  log = viewer.open,
  task = task_command,
  backend = function(arg)
    if arg ~= '' then return settings.set_backend(arg) end
    settings.select_backend()
  end,
  status = function()
    local lines = { 'AI default backend: ' .. settings.backend() }
    for _, t in ipairs(settings.tasks) do
      table.insert(lines, ('  %-12s %s'):format(settings.labels[t], settings.describe(t)))
    end
    table.insert(lines, 'auto next-edit: ' .. tostring(settings.auto()) .. '   log: ' .. require('hees.ai.log').dir())
    vim.notify(table.concat(lines, '\n'))
  end,
}

function M.setup(opts)
  opts = opts or {}
  nes.setup(opts.nes)
  ai_debug.setup()
  analyze.config = vim.tbl_deep_extend('force', analyze.config, opts.analyze or {})

  vim.api.nvim_create_user_command('Ai', function(cmd)
    local name, rest = cmd.args:match '^(%S*)%s*(.*)$'
    local sub = subcommands[name ~= '' and name or 'status']
    if not sub then return vim.notify('Ai: unknown subcommand ' .. name, vim.log.levels.ERROR) end
    if cmd.range > 0 and (name == 'explain' or name == 'review' or name == 'ask') then
      return analyze.run(name, { range = { cmd.line1, cmd.line2 }, question = rest ~= '' and rest or nil })
    end
    sub(rest)
  end, {
    nargs = '*',
    range = true,
    desc = 'AI: explain / review / ask / debug with LSP and debugger context, per-task backends and models, request log',
    complete = function(_, line)
      local args = vim.split(line, '%s+')
      if #args <= 2 then return vim.tbl_keys(subcommands) end
      if args[2] == 'backend' then return backends.names end
      if args[2] == 'task' then
        if #args == 3 then return settings.tasks end
        if #args == 4 then return { 'backend', 'model', 'reset' } end
        if #args == 5 and args[4] == 'backend' then return vim.list_extend({ 'default' }, vim.deepcopy(backends.names)) end
        if #args == 5 and args[4] == 'model' then
          local backend = settings.resolve(args[3])
          return vim.list_extend({ 'default' }, vim.deepcopy(settings.known_models[backend] or {}))
        end
      end
      return {}
    end,
  })

  local function both(lhs, name, desc)
    vim.keymap.set('n', lhs, function() analyze.run(name) end, { desc = desc })
    vim.keymap.set('x', lhs, function()
      vim.cmd 'normal! \27'
      analyze.run(name, { range = { vim.fn.line "'<", vim.fn.line "'>" } })
    end, { desc = desc .. ' (selection)' })
  end
  both('<leader>ax', 'explain', 'AI: e[X]plain code')
  both('<leader>ar', 'review', 'AI: [R]eview code for bugs')
  both('<leader>aq', 'ask', 'AI: ask a [Q]uestion about code')
  vim.keymap.set('n', '<leader>ag', function() ai_debug.run() end, { desc = 'AI: explain the paused debu[G] state' })
  vim.keymap.set('n', '<leader>ac', M.cancel, { desc = 'AI: [C]ancel request' })
  vim.keymap.set('n', '<leader>ab', M.pick_backend, { desc = 'AI: [B]ackend of a task' })
  vim.keymap.set('n', '<leader>am', M.pick_model, { desc = 'AI: [M]odel of a task' })
  vim.keymap.set('n', '<leader>as', M.open_settings, { desc = 'AI: backends & models [S]ettings menu' })
  vim.keymap.set('n', '<leader>at', function() settings.set_auto() end, { desc = 'AI: [T]oggle auto suggest' })
  vim.keymap.set('n', '<leader>al', viewer.open, { desc = 'AI: request [L]og' })
  local has_wk, wk = pcall(require, 'which-key')
  if has_wk then wk.add { { '<leader>a', group = '[A]I', mode = { 'n', 'x' } } } end
end

return M
