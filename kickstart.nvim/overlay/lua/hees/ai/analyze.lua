-- Ask the AI backend about code, with what the language servers know about it: explain, review
-- for bugs, or a free question. The code is the visual selection, else the function or class
-- around the cursor (from LSP document symbols), else the lines around the cursor. The answer
-- opens in a Markdown window on the right; the request is in the log viewer like every other.

local lsp_context = require 'hees.ai.lsp_context'
local run = require 'hees.ai.run'
local settings = require 'hees.ai.settings'
local util = require 'hees.util'

local M = {}

M.config = {
  language = 'Korean', -- language of the answers
  context_lines = 30, -- lines around the cursor when no function encloses it
  max_lines = 400, -- longest code excerpt sent
}

M.tasks = {
  explain = { title = 'Explain', ask = 'Explain what this code does and how it works: its purpose, inputs and outputs, control flow, and how it relates to the symbols and types the language server reports. Point out anything surprising.' },
  review = {
    title = 'Review',
    ask = 'Review this code for bugs, unhandled edge cases, error handling gaps, resource leaks and risky patterns. Take the LSP diagnostics into account. For each issue give the line number, what goes wrong and a concrete fix. If you find nothing significant, say so plainly.',
  },
  ask = { title = 'Ask' },
}

local function fence(lines, lang)
  local body = table.concat(lines, '\n')
  local ticks = body:find('```', 1, true) and '````' or '```'
  return ticks .. (lang or '') .. '\n' .. body .. '\n' .. ticks
end

M.fence = fence

--- Build the prompt. Exposed for tests.
---@param req { task: string, question: string?, path: string, filetype: string, first: integer, last: integer, line_count: integer, lines: string[], cursor: integer[], scope: string, ctx: hees.ai.LspContext }
function M.build_prompt(req)
  local task = M.tasks[req.task]
  local numbered = {}
  for i, l in ipairs(req.lines) do
    numbered[i] = ('%d| %s'):format(req.first + i - 1, l)
  end
  local ctx = req.ctx
  local parts = {
    'You are an expert software engineer helping a developer inside their code editor (Neovim).',
    req.task == 'ask' and ('Answer the developer\'s question about the code below:\n' .. req.question) or task.ask,
    ('Base the answer on the code and the language-server (LSP) information below. Be concrete and cite line numbers. Use Markdown. Answer in %s. Do not modify any files.'):format(M.config.language),
    '',
    ('File: %s (filetype: %s), lines %d-%d of %d — %s'):format(req.path, req.filetype, req.first, req.last, req.line_count, req.scope),
    ('Cursor: line %d, column %d'):format(req.cursor[1], req.cursor[2] + 1),
    'Language servers: ' .. (#ctx.clients > 0 and table.concat(ctx.clients, ', ') or 'none attached'),
    '',
    '## Code (format "N| text")',
    fence(numbered, req.filetype),
  }
  local function section(title, lines)
    if lines and #lines > 0 then vim.list_extend(parts, { '', '## ' .. title, table.concat(lines, '\n') }) end
  end
  section('LSP diagnostics in this code', ctx.diagnostics)
  section('LSP hover at the cursor', ctx.hover)
  if ctx.definition then
    vim.list_extend(parts, { '', ('## Definition of the symbol under the cursor (%s:%d)'):format(ctx.definition.path, ctx.definition.line), fence(ctx.definition.lines, ctx.definition.filetype) })
  end
  if ctx.reference_count > 0 then
    section(('References to the symbol under the cursor (%d%s)'):format(ctx.reference_count, ctx.reference_count > #ctx.references and (', first ' .. #ctx.references) or ''), ctx.references)
  end
  section('Document outline (LSP symbols)', ctx.outline)
  return table.concat(parts, '\n') .. '\n'
end

-- [[ Answer window ]]

local result = { buf = nil, timer = nil }

local function result_window()
  if not (result.buf and vim.api.nvim_buf_is_valid(result.buf)) then
    result.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[result.buf].filetype = 'markdown'
    vim.bo[result.buf].bufhidden = 'hide'
    pcall(vim.api.nvim_buf_set_name, result.buf, 'AI analysis')
    vim.keymap.set('n', 'q', '<Cmd>close<CR>', { buffer = result.buf, desc = 'Close AI analysis' })
  end
  local win = vim.fn.bufwinid(result.buf)
  if win == -1 then
    local from = vim.api.nvim_get_current_win()
    vim.cmd('botright vertical ' .. math.max(60, math.floor(vim.o.columns * 0.4)) .. 'split')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, result.buf)
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].number = false
    vim.api.nvim_set_current_win(from)
  end
  return win
end

local function show(lines)
  local win = result_window()
  vim.bo[result.buf].modifiable = true
  vim.api.nvim_buf_set_lines(result.buf, 0, -1, false, lines)
  vim.bo[result.buf].modifiable = false
  pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
end

local function stop_timer()
  if result.timer then
    result.timer:stop()
    result.timer:close()
    result.timer = nil
  end
end

-- [[ Requests ]]

local current ---@type table? running entry

function M.is_busy() return current ~= nil end

function M.cancel()
  if current and current.cancel then current.cancel() end
end

--- Send a prompt for `task` with the task's backend and model, show progress and then the answer
--- in the answer window. Used by code analysis and by debug-state analysis (hees.ai.debug).
---@param task string 'explain' | 'review' | 'ask' | 'debug'
---@param spec { title: string, header: string[], prompt: string, meta: table? }
function M.ask_ai(task, spec)
  if current then M.cancel() end
  local backend, model = settings.resolve(task)
  local header = vim.deepcopy(spec.header)
  table.insert(header, 2, ('%s · %s%s'):format(settings.labels[task], backend, model and (' (' .. model .. ')') or ''))

  local entry, err = run.start({
    kind = 'analyze',
    title = spec.title,
    backend = backend,
    model = model,
    prompt = spec.prompt,
    instruction = 'Answer the request above.',
    meta = vim.tbl_extend('force', spec.meta or {}, { task = task }),
  }, function(e)
    if current == e then current = nil end
    stop_timer()
    local lines = vim.list_extend(vim.deepcopy(header), { '' })
    if e.status == 'ok' then
      table.insert(lines, ('_%.1fs · 요청 기록: %s_'):format(e.elapsed, util.key_hint '<leader>al'))
      table.insert(lines, '')
      vim.list_extend(lines, vim.split(vim.trim(e.text or ''), '\n', { plain = true }))
      e.outcome = 'answered'
    else
      table.insert(lines, ('**%s** — %s'):format(e.status, e.reason or ''))
      table.insert(lines, ('요청 기록에서 명령과 출력을 확인하세요: %s'):format(util.key_hint '<leader>al'))
      e.outcome = e.status
    end
    show(lines)
  end)
  if not entry then
    show(vim.list_extend(header, { '', '**error** — ' .. tostring(err) }))
    return
  end
  if entry.status ~= 'running' then return end
  current = entry

  local frames, i, started = util.icons().spinner, 0, vim.uv.hrtime()
  stop_timer()
  result.timer = vim.uv.new_timer()
  result.timer:start(
    0,
    150,
    vim.schedule_wrap(function()
      if current ~= entry then return end
      i = i % #frames + 1
      show(vim.list_extend(vim.deepcopy(header), { '', ('%s %s 에 요청 중… %.1fs  (취소: %s)'):format(frames[i], backend, (vim.uv.hrtime() - started) / 1e9, util.key_hint '<leader>ac') }))
    end)
  )
end

--- Show a status line in the answer window before a request starts (e.g. while collecting context).
---@param lines string[]
function M.show_status(lines)
  show(lines)
  vim.cmd 'redraw'
end

--- Analyze code. `opts.range` = { first, last } for a selection; `opts.question` for task 'ask'.
---@param task string 'explain' | 'review' | 'ask'
---@param opts { range: integer[]?, question: string? }?
function M.run(task, opts)
  opts = opts or {}
  if task == 'ask' and not opts.question then
    return vim.ui.input({ prompt = 'Ask the AI about this code: ' }, function(q)
      if q and vim.trim(q) ~= '' then M.run('ask', vim.tbl_extend('force', opts, { question = q })) end
    end)
  end

  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local n = vim.api.nvim_buf_line_count(buf)
  local path = vim.api.nvim_buf_get_name(buf) ~= '' and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':~:.') or '[No Name]'

  M.show_status { ('# %s · %s'):format(M.tasks[task].title, path), '', '_LSP 정보 수집 중…_' }

  local first, last, scope
  if opts.range then
    first, last = math.min(opts.range[1], opts.range[2]), math.max(opts.range[1], opts.range[2])
    scope = 'the developer\'s selection'
  end
  -- Diagnostics are collected for the whole file first, then cut to the chosen range.
  local ctx = lsp_context.collect(buf, win, 1, n)
  if not first and ctx.enclosing then
    first, last = ctx.enclosing.first, ctx.enclosing.last
    scope = ('%s %s enclosing the cursor'):format(ctx.enclosing.kind, ctx.enclosing.name)
  end
  if not first then
    first, last = math.max(1, cursor[1] - M.config.context_lines), math.min(n, cursor[1] + M.config.context_lines)
    scope = 'lines around the cursor'
  end
  if last - first + 1 > M.config.max_lines then
    first = math.max(first, cursor[1] - math.floor(M.config.max_lines / 2))
    last = math.min(last, first + M.config.max_lines - 1)
    scope = scope .. ' (shortened)'
  end
  ctx.diagnostics = vim.tbl_filter(function(d)
    local line = tonumber(d:match '^L(%d+)')
    return line and line >= first and line <= last
  end, ctx.diagnostics)

  local req = {
    task = task,
    question = opts.question,
    path = path,
    filetype = vim.bo[buf].filetype,
    first = first,
    last = last,
    line_count = n,
    lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false),
    cursor = cursor,
    scope = scope,
    ctx = ctx,
  }
  local header = {
    ('# %s · %s:%d-%d'):format(M.tasks[task].title, path, first, last),
    ('%s · LSP: %s'):format(scope, #ctx.clients > 0 and table.concat(ctx.clients, ', ') or '없음'),
  }
  if opts.question then table.insert(header, '> ' .. opts.question) end
  M.ask_ai(task, {
    title = ('%s %s:%d-%d'):format(M.tasks[task].title, path, first, last),
    header = header,
    prompt = M.build_prompt(req),
    meta = { file = path, range = { first, last } },
  })
end

return M
