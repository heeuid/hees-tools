-- Ask the AI about a paused debug session (nvim-dap): why it stopped, which values look wrong,
-- the likely cause and what to check next. Sent with what only the debugger knows: the stop
-- reason and exception, the call stack, the variables of the current frame (one level into
-- structured values), the source around the current line and that file's LSP diagnostics.

local analyze = require 'hees.ai.analyze'

local M = {}

M.timeout_ms = 3000 -- per debug-adapter request
M.max_frames = 25
M.max_scopes = 4
M.max_variables = 60 -- per scope
M.max_children = 15 -- per expanded structured variable
M.max_expand = 10 -- structured variables expanded per scope
M.max_value = 200 -- characters of a value
M.source_lines = 25 -- above and below the current line

local last_stop = {} ---@type table<integer, table> session id -> body of its last 'stopped' event

local function rel(path) return path and vim.fn.fnamemodify(path, ':~:.') or '?' end

local function clip(value)
  value = tostring(value or ''):gsub('\n', ' ')
  if #value > M.max_value then value = value:sub(1, M.max_value) .. '…' end
  return value
end

--- One debug-adapter request, waited for synchronously.
local function request(session, command, args)
  local done, result
  local ok = pcall(session.request, session, command, args, function(err, res)
    result = not err and res or nil
    done = true
  end)
  if not ok then return nil end
  vim.wait(M.timeout_ms, function() return done end, 10)
  return result
end

local function variable_line(v, indent)
  return ('%s%s%s = %s'):format(indent, v.name, v.type and v.type ~= '' and (': ' .. v.type) or '', clip(v.value))
end

---@class hees.ai.DebugContext
---@field program string
---@field reason string
---@field path string?
---@field line integer
---@field frame string
---@field stack string[]
---@field scopes { name: string, lines: string[] }[]
---@field exception string[]
---@field source string[]
---@field filetype string?
---@field diagnostics string[]

--- Collect the state of a stopped session; nil and a message when there is nothing to analyze.
---@return hees.ai.DebugContext?, string?
function M.collect(session)
  if not session then return nil, '디버그 세션이 없습니다. 먼저 디버깅을 시작하세요 (F5).' end
  local frame = session.current_frame
  local tid = session.stopped_thread_id
  if not tid or not frame then return nil, '프로그램이 멈춰 있지 않습니다. 중단점에서 멈춘 뒤 다시 실행하세요.' end
  local stop = last_stop[session.id] or {}
  local config = session.config or {}
  local path = frame.source and frame.source.path
  local ctx = {
    program = ('%s (%s)'):format(config.name or '?', config.type or session.adapter and session.adapter.type or '?'),
    reason = (stop.reason or 'unknown') .. (stop.description and (' — ' .. stop.description) or '') .. (stop.text and (' — ' .. stop.text) or ''),
    path = path,
    line = frame.line or 0,
    frame = frame.name or '?',
    stack = {},
    scopes = {},
    exception = {},
    source = {},
    diagnostics = {},
  }

  local thread = session.threads and session.threads[tid]
  for i, f in ipairs(thread and thread.frames or {}) do
    if i > M.max_frames then break end
    local src = f.source and (f.source.path or f.source.name)
    table.insert(ctx.stack, ('#%d %s  %s:%d%s'):format(i - 1, f.name or '?', rel(src), f.line or 0, f.id == frame.id and '   ← current' or ''))
  end

  local scopes = request(session, 'scopes', { frameId = frame.id })
  for si, scope in ipairs(scopes and scopes.scopes or {}) do
    if si > M.max_scopes then break end
    local lines, expanded = {}, 0
    local vars = request(session, 'variables', { variablesReference = scope.variablesReference })
    for vi, v in ipairs(vars and vars.variables or {}) do
      if vi > M.max_variables then
        table.insert(lines, ('… %d more'):format(#vars.variables - M.max_variables))
        break
      end
      table.insert(lines, variable_line(v, ''))
      if (v.variablesReference or 0) > 0 and expanded < M.max_expand and not scope.expensive then
        expanded = expanded + 1
        local children = request(session, 'variables', { variablesReference = v.variablesReference })
        for ci, c in ipairs(children and children.variables or {}) do
          if ci > M.max_children then
            table.insert(lines, '    …')
            break
          end
          table.insert(lines, variable_line(c, '    '))
        end
      end
    end
    table.insert(ctx.scopes, { name = scope.name .. (scope.expensive and ' (expensive, not expanded)' or ''), lines = lines })
  end

  if stop.reason == 'exception' and session.capabilities and session.capabilities.supportsExceptionInfoRequest then
    local info = request(session, 'exceptionInfo', { threadId = tid })
    if info then
      table.insert(ctx.exception, ('%s: %s'):format(info.exceptionId or '?', info.description or ''))
      if info.details and info.details.stackTrace then vim.list_extend(ctx.exception, vim.split(info.details.stackTrace, '\n', { plain = true })) end
    end
  end

  if path and vim.fn.filereadable(path) == 1 then
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    ctx.filetype = vim.bo[buf].filetype
    local first = math.max(1, ctx.line - M.source_lines)
    for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, first - 1, ctx.line + M.source_lines, false)) do
      local n = first + i - 1
      table.insert(ctx.source, ('%s%d| %s'):format(n == ctx.line and '>' or ' ', n, l))
    end
    for _, d in ipairs(vim.diagnostic.get(buf)) do
      if math.abs(d.lnum + 1 - ctx.line) <= M.source_lines then
        table.insert(ctx.diagnostics, ('L%d %s'):format(d.lnum + 1, (d.message:gsub('\n', ' '))))
      end
    end
  end
  return ctx
end

--- Build the prompt. Exposed for tests.
---@param ctx hees.ai.DebugContext
---@param question string?
function M.build_prompt(ctx, question)
  local parts = {
    'You are an expert debugger helping a developer whose program is paused in a debugger (Neovim, nvim-dap).',
    question and ('Answer the developer\'s question about this paused state:\n' .. question)
      or 'Explain why the program stopped here and what state it is in. Point out values that look wrong or suspicious, the likely cause of the bug, and what to check or change next.',
    ('Base the answer on the debugger state below. Cite variable names, stack frames and line numbers. Use Markdown. Answer in %s. Do not modify any files.'):format(analyze.config.language),
    '',
    'Program: ' .. ctx.program,
    'Stopped: ' .. ctx.reason,
    ('Location: %s:%d in %s'):format(rel(ctx.path), ctx.line, ctx.frame),
  }
  local function section(title, lines, lang)
    if lines and #lines > 0 then vim.list_extend(parts, { '', '## ' .. title, lang and analyze.fence(lines, lang) or table.concat(lines, '\n') }) end
  end
  section('Source around the current line (">" marks it)', ctx.source, ctx.filetype or '')
  section('Call stack (innermost first)', ctx.stack)
  for _, scope in ipairs(ctx.scopes) do
    section('Variables — ' .. scope.name, scope.lines)
  end
  section('Exception', ctx.exception)
  section('LSP diagnostics near the current line', ctx.diagnostics)
  return table.concat(parts, '\n') .. '\n'
end

--- Analyze the paused session. `opts.question` asks something specific; `opts.ask` prompts for it.
---@param opts { question: string?, ask: boolean? }?
function M.run(opts)
  opts = opts or {}
  if opts.ask and not opts.question then
    return vim.ui.input({ prompt = 'Ask the AI about this debug state: ' }, function(q)
      if q and vim.trim(q) ~= '' then M.run { question = q } end
    end)
  end
  local ok, dap = pcall(require, 'dap')
  local session = ok and dap.session() or nil
  local ctx, err = M.collect(session)
  if not ctx then return vim.notify('AI debug: ' .. err, vim.log.levels.WARN) end
  local where = ('%s:%d'):format(rel(ctx.path), ctx.line)
  analyze.show_status { '# Debug state · ' .. where, '', '_디버거 상태 수집 완료, 요청 준비 중…_' }
  analyze.ask_ai('debug', {
    title = 'Debug ' .. where,
    header = { '# Debug state · ' .. where, ('stopped: %s · in %s · %d frames'):format(ctx.reason, ctx.frame, #ctx.stack) },
    prompt = M.build_prompt(ctx, opts.question),
    question = opts.question,
    meta = { file = rel(ctx.path), range = { ctx.line, ctx.line } },
  })
end

function M.is_stopped()
  local ok, dap = pcall(require, 'dap')
  local s = ok and dap.session() or nil
  return s ~= nil and s.stopped_thread_id ~= nil
end

--- Remember why each session stopped (nvim-dap keeps the frame, not the stop reason).
function M.setup()
  local ok, dap = pcall(require, 'dap')
  if not ok then return end
  dap.listeners.after.event_stopped['hees-ai'] = function(session, body) last_stop[session.id] = body end
  dap.listeners.after.event_terminated['hees-ai'] = function(session) last_stop[session.id] = nil end
end

return M
