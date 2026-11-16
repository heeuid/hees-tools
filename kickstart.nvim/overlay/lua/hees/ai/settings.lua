-- AI settings: a default backend, and per task (next edit, explain, review, ask, debug) an
-- optional backend and a model per backend. What a task leaves unset falls back:
--   backend: task backend → default backend
--   model:   task model for that backend → built-in default (claude next edits: haiku) → CLI default
-- Saved in <config>/data/ai/state.json (taken over from data/nes/state.json the first time).

local backends = require 'hees.ai.backends'
local util = require 'hees.util'

local M = {}

M.tasks = { 'nes', 'explain', 'review', 'ask', 'debug' }
M.labels = { nes = 'Next edit', explain = 'Explain', review = 'Review', ask = 'Ask', debug = 'Debug state' }

--- Models offered in the picker; any other name can be typed. Only names the CLI is known to
--- accept are listed (Claude Code's aliases); codex and gemini models are typed or left default.
M.known_models = { claude = { 'haiku', 'sonnet', 'opus' } }

local state

local function path() return vim.fs.joinpath(util.data_dir 'ai', 'state.json') end

local function kind(task) return task == 'nes' and 'nes' or 'analyze' end

local function load()
  if state then return state end
  local file = path()
  if vim.fn.filereadable(file) == 0 then
    local old = vim.fs.joinpath(util.data_dir 'nes', 'state.json')
    if vim.fn.filereadable(old) == 1 then file = old end
  end
  state = util.read_json(file, { backend = 'claude', tasks = vim.empty_dict(), auto = false })
  if not vim.tbl_contains(backends.names, state.backend) then state.backend = 'claude' end
  -- Earlier versions kept one model table for next edits and one for analysis: move them to tasks.
  local function move(legacy, tasks)
    for backend, model in pairs(legacy or {}) do
      for _, task in ipairs(tasks) do
        state.tasks[task] = state.tasks[task] or { models = {} }
        state.tasks[task].models = state.tasks[task].models or {}
        if state.tasks[task].models[backend] == nil then state.tasks[task].models[backend] = model end
      end
    end
  end
  move(state.models, { 'nes' })
  move(state.analyze_models, { 'explain', 'review', 'ask', 'debug' })
  state.models, state.analyze_models = nil, nil
  return state
end

local function save() util.write_json(path(), load()) end

local function task_state(task)
  local s = load()
  s.tasks[task] = s.tasks[task] or { models = {} }
  s.tasks[task].models = s.tasks[task].models or {}
  return s.tasks[task]
end

--- Default backend (used by every task that doesn't set its own).
function M.backend() return load().backend end

--- Backend and model a task runs with, plus whether each is the task's own setting.
---@param task string
---@return string backend, string? model, boolean own_backend, boolean own_model
function M.resolve(task)
  local t = task_state(task)
  local backend = t.backend or load().backend
  local model = t.models[backend]
  local own_model = model ~= nil and model ~= ''
  if not own_model then model = backends.default_models[kind(task)][backend] end
  return backend, model, t.backend ~= nil, own_model
end

--- "codex / gpt-x" style summary of a task's setting for menus and messages.
function M.describe(task)
  local backend, model, own_backend, own_model = M.resolve(task)
  return ('%s%s / %s%s'):format(backend, own_backend and '' or ' (default)', model or 'CLI default', own_model and '' or (model and ' (default)' or ''))
end

function M.set_backend(name)
  if not vim.tbl_contains(backends.names, name) then return vim.notify('AI: unknown backend ' .. tostring(name), vim.log.levels.ERROR) end
  if not backends.available(name) then vim.notify('AI: ' .. name .. ' CLI is not on PATH', vim.log.levels.WARN) end
  load().backend = name
  save()
  vim.notify('AI: default backend = ' .. name)
end

function M.select_backend()
  vim.ui.select(backends.names, {
    prompt = 'AI default backend',
    format_item = function(name)
      local mark = name == load().backend and '● ' or '  '
      return mark .. name .. (backends.available(name) and '' or '  (not installed)')
    end,
  }, function(choice)
    if choice then M.set_backend(choice) end
  end)
end

--- Set a task's backend; nil = follow the default backend.
function M.set_task_backend(task, name)
  if name and not vim.tbl_contains(backends.names, name) then return vim.notify('AI: unknown backend ' .. tostring(name), vim.log.levels.ERROR) end
  if name and not backends.available(name) then vim.notify('AI: ' .. name .. ' CLI is not on PATH', vim.log.levels.WARN) end
  task_state(task).backend = name
  save()
  vim.notify(('AI: %s → %s'):format(M.labels[task], M.describe(task)))
end

--- Set a task's model for the backend it runs with. nil asks (picker); '' = default.
function M.set_task_model(task, model)
  local backend = M.resolve(task)
  if model == nil then
    local default = backends.default_models[kind(task)][backend] or 'CLI default'
    local choices = vim.list_extend({ '(default: ' .. default .. ')' }, vim.deepcopy(M.known_models[backend] or {}))
    table.insert(choices, 'Other…')
    return vim.ui.select(choices, { prompt = ('%s model (%s)'):format(M.labels[task], backend) }, function(choice, idx)
      if not choice then return end
      if idx == 1 then return M.set_task_model(task, '') end
      if choice == 'Other…' then
        return vim.ui.input({ prompt = ('%s model name for %s: '):format(M.labels[task], backend), default = task_state(task).models[backend] or '' }, function(input)
          if input ~= nil then M.set_task_model(task, input) end
        end)
      end
      M.set_task_model(task, choice)
    end)
  end
  task_state(task).models[backend] = model ~= '' and model or nil
  save()
  vim.notify(('AI: %s → %s'):format(M.labels[task], M.describe(task)))
end

--- Forget a task's own backend and models.
function M.reset_task(task)
  load().tasks[task] = { models = {} }
  save()
  vim.notify(('AI: %s → %s'):format(M.labels[task], M.describe(task)))
end

function M.auto() return load().auto end

function M.set_auto(on)
  local s = load()
  if on == nil then on = not s.auto end
  s.auto = on
  save()
  vim.notify('AI: auto next-edit suggest ' .. (on and 'on' or 'off'))
end

--- Drop the cached state (tests switch HEES_NVIM_DATA).
function M._reload() state = nil end

return M
