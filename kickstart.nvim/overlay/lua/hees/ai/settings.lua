-- AI settings shared by next-edit suggestions and code analysis: one backend for both, a model
-- per backend for each kind of request, and NES auto-suggest. Saved in <config>/data/ai/state.json
-- (taken over from data/nes/state.json the first time).

local backends = require 'hees.ai.backends'
local util = require 'hees.util'

local M = {}

local KINDS = { nes = 'next edit', analyze = 'analysis' }
local state

local function path() return vim.fs.joinpath(util.data_dir 'ai', 'state.json') end

local function load()
  if state then return state end
  local defaults = { backend = 'claude', models = vim.empty_dict(), analyze_models = vim.empty_dict(), auto = false }
  local file = path()
  if vim.fn.filereadable(file) == 0 then
    local old = vim.fs.joinpath(util.data_dir 'nes', 'state.json')
    if vim.fn.filereadable(old) == 1 then file = old end
  end
  state = util.read_json(file, defaults)
  if not vim.tbl_contains(backends.names, state.backend) then state.backend = 'claude' end
  return state
end

local function save() util.write_json(path(), load()) end

function M.get() return load() end

function M.backend() return load().backend end

--- Model for a kind ('nes' or 'analyze') on a backend; nil means the CLI default.
---@param kind string
---@param backend string?
---@return string?
function M.model(kind, backend)
  local s = load()
  backend = backend or s.backend
  local m = (kind == 'nes' and s.models or s.analyze_models)[backend]
  if m == nil or m == '' then return backends.default_models[kind][backend] end
  return m
end

function M.set_backend(name)
  if not vim.tbl_contains(backends.names, name) then return vim.notify('AI: unknown backend ' .. tostring(name), vim.log.levels.ERROR) end
  if not backends.available(name) then vim.notify('AI: ' .. name .. ' CLI is not on PATH', vim.log.levels.WARN) end
  load().backend = name
  save()
  vim.notify(('AI: backend = %s (next edit: %s, analysis: %s)'):format(name, M.model('nes') or 'CLI default', M.model('analyze') or 'CLI default'))
end

function M.select_backend()
  vim.ui.select(backends.names, {
    prompt = 'AI backend',
    format_item = function(name)
      local mark = name == load().backend and '● ' or '  '
      return mark .. name .. (backends.available(name) and '' or '  (not installed)')
    end,
  }, function(choice)
    if choice then M.set_backend(choice) end
  end)
end

--- Set the model of a kind for the current backend; nil asks, empty means the default.
---@param kind string 'nes' | 'analyze'
---@param model string?
function M.set_model(kind, model)
  local s = load()
  local backend = s.backend
  local tbl = kind == 'nes' and s.models or s.analyze_models
  if model == nil then
    local default = backends.default_models[kind][backend] or 'CLI default'
    return vim.ui.input({ prompt = ('%s model for %s (empty = %s): '):format(KINDS[kind], backend, default), default = tbl[backend] or '' }, function(input)
      if input ~= nil then M.set_model(kind, input) end
    end)
  end
  tbl[backend] = model ~= '' and model or nil
  save()
  vim.notify(('AI: %s %s model = %s'):format(backend, KINDS[kind], M.model(kind) or 'CLI default'))
end

function M.auto() return load().auto end

function M.set_auto(on)
  local s = load()
  if on == nil then on = not s.auto end
  s.auto = on
  save()
  vim.notify('AI: auto next-edit suggest ' .. (on and 'on' or 'off'))
end

return M
