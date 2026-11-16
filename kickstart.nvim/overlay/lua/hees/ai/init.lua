-- AI features on one backend (Claude / Codex / Gemini CLI): next-edit suggestions (hees.nes),
-- code analysis with LSP context (hees.ai.analyze), and a viewer for every request they made
-- (hees.ai.viewer). This module wires the commands, keys and the right-click submenu.

local analyze = require 'hees.ai.analyze'
local backends = require 'hees.ai.backends'
local nes = require 'hees.nes'
local settings = require 'hees.ai.settings'
local viewer = require 'hees.ai.viewer'

local M = {}

--- Cancel whatever AI request is running.
function M.cancel()
  nes.cancel()
  analyze.cancel()
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
  local backend_items = {}
  for _, name in ipairs(backends.names) do
    local available = backends.available(name)
    table.insert(backend_items, {
      label = name .. (available and '' or '  (not installed)'),
      checked = name == settings.backend(),
      enabled = available,
      action = function() settings.set_backend(name) end,
    })
  end
  local scope = visual and 'selection' or 'function at cursor'
  local items = vim.list_extend(nes.menu_items(visual), {
    { sep = true },
    { label = 'Explain ' .. scope, hint = '<leader>ax', action = task 'explain' },
    { label = 'Review ' .. scope .. ' for bugs', hint = '<leader>ar', action = task 'review' },
    { label = 'Ask about ' .. scope .. '…', hint = '<leader>aq', action = task 'ask' },
    { label = 'Cancel running request', hint = '<leader>ac', action = M.cancel, enabled = function() return nes.is_busy() or analyze.is_busy() end },
    { sep = true },
    { label = 'Backend: ' .. settings.backend(), hint = '<leader>ab', items = backend_items },
    {
      label = 'Models',
      items = {
        { label = 'Next edit: ' .. (settings.model 'nes' or 'CLI default') .. '…', hint = '<leader>am', action = function() settings.set_model 'nes' end },
        { label = 'Analysis: ' .. (settings.model 'analyze' or 'CLI default') .. '…', action = function() settings.set_model 'analyze' end },
      },
    },
    { label = 'Auto next-edit suggest', hint = '<leader>at', checked = settings.auto(), action = function() settings.set_auto() end },
    { label = 'Request log', hint = '<leader>al', action = viewer.open },
  })
  return items
end

local subcommands = {
  explain = function() analyze.run 'explain' end,
  review = function() analyze.run 'review' end,
  ask = function(rest) analyze.run('ask', { question = rest ~= '' and rest or nil }) end,
  cancel = M.cancel,
  log = viewer.open,
  backend = function(arg)
    if arg ~= '' then return settings.set_backend(arg) end
    settings.select_backend()
  end,
  model = function(arg)
    local kind, model = arg:match '^(%S+)%s*(.*)$'
    if kind ~= 'nes' and kind ~= 'analyze' then return vim.notify('Usage: :Ai model {nes|analyze} [name]', vim.log.levels.WARN) end
    settings.set_model(kind, model ~= '' and model or nil)
  end,
  status = function()
    vim.notify(('AI: backend=%s  next-edit model=%s  analysis model=%s  auto=%s\nlog: %s'):format(
      settings.backend(),
      settings.model 'nes' or 'CLI default',
      settings.model 'analyze' or 'CLI default',
      tostring(settings.auto()),
      require('hees.ai.log').dir()
    ))
  end,
}

function M.setup(opts)
  opts = opts or {}
  nes.setup(opts.nes)
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
    desc = 'AI: explain / review / ask about code with LSP context, request log, backend and models',
    complete = function(_, line)
      local args = vim.split(line, '%s+')
      if #args <= 2 then return vim.tbl_keys(subcommands) end
      if args[2] == 'backend' then return backends.names end
      if args[2] == 'model' and #args == 3 then return { 'nes', 'analyze' } end
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
  vim.keymap.set('n', '<leader>ac', M.cancel, { desc = 'AI: [C]ancel request' })
  vim.keymap.set('n', '<leader>ab', settings.select_backend, { desc = 'AI: choose [B]ackend' })
  vim.keymap.set('n', '<leader>am', function() settings.set_model 'nes' end, { desc = 'AI: next-edit [M]odel' })
  vim.keymap.set('n', '<leader>at', function() settings.set_auto() end, { desc = 'AI: [T]oggle auto suggest' })
  vim.keymap.set('n', '<leader>al', viewer.open, { desc = 'AI: request [L]og' })
  local has_wk, wk = pcall(require, 'which-key')
  if has_wk then wk.add { { '<leader>a', group = '[A]I', mode = { 'n', 'x' } } } end
end

return M
