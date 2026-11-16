-- AI conversations: each code or debug analysis starts a conversation with its own answer
-- buffer, and follow-up questions continue it. A follow-up resends the first request (code, LSP
-- or debugger context, verbatim) with the questions and answers so far and the new question, so
-- it works the same on every backend and the request log shows exactly what was sent. When that
-- gets long, the oldest answers are left out (and the log records how many). Conversations of
-- earlier sessions are rebuilt from the request log. Next-edit suggestions are not conversations.

local log = require 'hees.ai.log'
local run = require 'hees.ai.run'
local settings = require 'hees.ai.settings'
local util = require 'hees.util'

local M = {}

M.config = {
  max_chars = 60000, -- longest follow-up prompt before the oldest answers are left out
  days = 30, -- how far back the request log is searched for conversations
}

local convs = {} ---@type table<string, table> id -> conversation
local order = {} ---@type string[] this session's conversation ids, oldest first
local seq = 0
local answer_win ---@type integer?
local pending_buf ---@type integer? shown while a request is being prepared
local timer
local current ---@type { conv: table, entry: table }?

local function language() return require('hees.ai.analyze').config.language end

-- [[ Answer window ]]

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

--- Show `buf` in the answer window on the right (created in the current tab when needed).
local function show_buf(buf)
  if answer_win and vim.api.nvim_win_is_valid(answer_win) and vim.api.nvim_win_get_tabpage(answer_win) == vim.api.nvim_get_current_tabpage() then
    vim.api.nvim_win_set_buf(answer_win, buf)
  else
    local from = vim.api.nvim_get_current_win()
    vim.cmd('botright vertical ' .. math.max(60, math.floor(vim.o.columns * 0.4)) .. 'split')
    answer_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(answer_win, buf)
    vim.wo[answer_win].wrap = true
    vim.wo[answer_win].linebreak = true
    vim.wo[answer_win].number = false
    if vim.api.nvim_win_is_valid(from) then vim.api.nvim_set_current_win(from) end
  end
  return answer_win
end

local function scratch(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].bufhidden = 'hide'
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.keymap.set('n', 'q', '<Cmd>close<CR>', { buffer = buf, desc = 'Close the AI answer window' })
  return buf
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Show a status message in the answer window before a request starts.
---@param lines string[]
function M.status(lines)
  if not (pending_buf and vim.api.nvim_buf_is_valid(pending_buf)) then pending_buf = scratch 'AI' end
  set_lines(pending_buf, lines)
  show_buf(pending_buf)
  vim.cmd 'redraw'
end

local function conv_buffer(conv)
  if conv.buf and vim.api.nvim_buf_is_valid(conv.buf) then return conv.buf end
  conv.buf = scratch(('AI #%s · %s'):format(conv.id:match '(%d+)$' or conv.id, conv.title))
  vim.b[conv.buf].hees_ai_conv = conv.id
  vim.keymap.set('n', 'a', function() M.follow_up(conv.id) end, { buffer = conv.buf, desc = 'Ask a follow-up question in this conversation' })
  return conv.buf
end

--- Draw a conversation: header, then each question and its answer (or progress).
local function render(conv, progress)
  local lines = vim.deepcopy(conv.header)
  table.insert(lines, ('_%s · %s%s · 질문 %d개 · 후속 질문: 여기서 `a`, 코드에서 %s · 기록 %s_'):format(
    settings.labels[conv.task] or conv.task,
    conv.backend,
    conv.model and (' (' .. conv.model .. ')') or '',
    #conv.turns,
    util.key_hint '<leader>af',
    util.key_hint '<leader>al'
  ))
  local last_heading = 1
  for i, t in ipairs(conv.turns) do
    table.insert(lines, '')
    last_heading = #lines + 1
    local q = t.question and t.question:gsub('\n', ' ') or (settings.labels[conv.task] or conv.task)
    table.insert(lines, ('## Q%d: %s'):format(i, q))
    table.insert(lines, '')
    if t.answer then
      vim.list_extend(lines, vim.split(t.answer, '\n', { plain = true }))
      if t.elapsed then table.insert(lines, ('_— %.1fs_'):format(t.elapsed)) end
    elseif t.status and t.status ~= 'running' then
      table.insert(lines, ('**%s** — %s'):format(t.status, t.reason or ''))
      table.insert(lines, ('요청 기록에서 명령과 출력을 확인하세요: %s'):format(util.key_hint '<leader>al'))
    else
      table.insert(lines, progress or '…')
    end
  end
  local buf = conv_buffer(conv)
  set_lines(buf, lines)
  local win = show_buf(buf)
  pcall(vim.api.nvim_win_set_cursor, win, { last_heading, 0 })
end

-- [[ Requests ]]

function M.is_busy() return current ~= nil end

function M.cancel()
  if current and current.entry.cancel then current.entry.cancel() end
end

--- Prompt of a follow-up: the first request, the conversation so far, the new question.
---@return string prompt, integer dropped number of earlier answers left out
local function followup_prompt(conv, question)
  local previous = {}
  for i = 1, #conv.turns - 1 do
    local t = conv.turns[i]
    previous[i] = {
      q = t.question or ('(first request: ' .. (settings.labels[conv.task] or conv.task) .. ')'),
      a = t.answer or ('(no answer: ' .. (t.status or '?') .. ')'),
    }
  end
  local function build(drop)
    local parts = { conv.base_prompt, '', '## Conversation so far' }
    for i, p in ipairs(previous) do
      vim.list_extend(parts, { '', ('### Q%d: %s'):format(i, p.q), i <= drop and '(earlier answer left out to keep the request short)' or p.a })
    end
    vim.list_extend(parts, {
      '',
      '## Follow-up question',
      question,
      '',
      ('Answer the follow-up question using the code, the context and the conversation above. Use Markdown. Answer in %s. Do not modify any files.'):format(language()),
    })
    return table.concat(parts, '\n') .. '\n'
  end
  local drop, text = 0, build(0)
  while #text > M.config.max_chars and drop < #previous - 1 do
    drop = drop + 1
    text = build(drop)
  end
  return text, drop
end

--- Send the next question of a conversation (nil for the first request without a question).
local function send(conv, question)
  if current then M.cancel() end
  local turn = { question = question, status = 'running' }
  table.insert(conv.turns, turn)
  local n = #conv.turns
  local prompt, dropped = conv.base_prompt, 0
  if n > 1 then prompt, dropped = followup_prompt(conv, question) end

  local entry, err = run.start({
    kind = 'analyze',
    title = conv.title .. (n > 1 and (' · Q' .. n) or ''),
    backend = conv.backend,
    model = conv.model,
    prompt = prompt,
    instruction = 'Answer the request above.',
    meta = vim.tbl_extend('force', conv.meta or {}, { task = conv.task, conv = conv.id, turn = n, question = question, dropped_turns = dropped > 0 and dropped or nil }),
  }, function(e)
    if current and current.entry == e then
      current = nil
      stop_timer()
    end
    turn.status, turn.reason, turn.elapsed = e.status, e.reason, e.elapsed
    if e.status == 'ok' then
      turn.answer = vim.trim(e.text or '')
      e.outcome = 'answered'
    else
      e.outcome = e.status
    end
    render(conv)
  end)
  if not entry then
    turn.status, turn.reason = 'error', tostring(err)
    return render(conv)
  end
  if entry.status ~= 'running' then return end
  current = { conv = conv, entry = entry }

  local frames, i, started = util.icons().spinner, 0, vim.uv.hrtime()
  stop_timer()
  timer = vim.uv.new_timer()
  timer:start(
    0,
    150,
    vim.schedule_wrap(function()
      if not current or current.entry ~= entry then return end
      i = i % #frames + 1
      render(conv, ('%s %s 에 요청 중… %.1fs  (취소: %s)'):format(frames[i], conv.backend, (vim.uv.hrtime() - started) / 1e9, util.key_hint '<leader>ac'))
    end)
  )
end

--- Start a conversation for `task` with its backend and model.
---@param task string 'explain' | 'review' | 'ask' | 'debug'
---@param spec { title: string, header: string[], prompt: string, question: string?, meta: table? }
function M.start(task, spec)
  local backend, model = settings.resolve(task)
  seq = seq + 1
  local conv = {
    id = ('%d-%d-c%d'):format(os.time(), vim.fn.getpid(), seq),
    task = task,
    title = spec.title,
    header = vim.deepcopy(spec.header),
    backend = backend,
    model = model,
    base_prompt = spec.prompt,
    meta = spec.meta,
    turns = {},
  }
  convs[conv.id] = conv
  table.insert(order, conv.id)
  send(conv, spec.question)
  return conv
end

-- [[ Conversations from the log ]]

--- Requests of one conversation in the log, in order.
local function log_turns(id)
  local turns = vim.tbl_filter(function(e) return e.conv == id end, log.all(M.config.days))
  table.sort(turns, function(a, b) return (a.turn or 0) < (b.turn or 0) end)
  return turns
end

--- Rebuild a conversation of an earlier session from the request log.
local function load(id)
  local entries = log_turns(id)
  local first = entries[1]
  if not first or first.turn ~= 1 then return nil end
  local conv = {
    id = id,
    task = first.task,
    title = first.title,
    header = { '# ' .. first.title },
    backend = first.backend,
    model = first.model,
    base_prompt = first.prompt,
    meta = { file = first.file, range = first.range },
    turns = {},
  }
  for _, e in ipairs(entries) do
    local ok = e.status == 'ok'
    table.insert(conv.turns, {
      question = e.question,
      answer = ok and vim.trim(e.answer or e.stdout or '') or nil,
      status = e.status,
      reason = e.reason,
      elapsed = e.elapsed,
    })
  end
  convs[id] = conv
  return conv
end

local function get(id) return convs[id] or load(id) end

--- Id of the most recent conversation (this session first, then the log).
function M.last_id()
  if #order > 0 then return order[#order] end
  for _, e in ipairs(log.all(M.config.days)) do
    if e.conv then return e.conv end
  end
end

--- Conversations in the log (this session included), newest first.
---@return { id: string, title: string, task: string, backend: string, model: string?, count: integer, time: integer, answered: integer }[]
function M.list()
  local by_id, list = {}, {}
  for _, e in ipairs(log.all(M.config.days)) do
    if e.conv then
      local c = by_id[e.conv]
      if not c then
        c = { id = e.conv, count = 0, answered = 0, time = e.time }
        by_id[e.conv] = c
        table.insert(list, c)
      end
      c.count = c.count + 1
      if e.status == 'ok' then c.answered = c.answered + 1 end
      if e.turn == 1 then
        c.title, c.task, c.backend, c.model = e.title, e.task, e.backend, e.model
      end
    end
  end
  return vim.tbl_filter(function(c) return c.title ~= nil end, list)
end

--- Question/answer transcript of a conversation for the log viewer.
---@return string[]
function M.transcript(id)
  local conv = get(id)
  if not conv then return { '(이 대화의 첫 요청을 기록에서 찾지 못했습니다)' } end
  local lines = { '# ' .. conv.title, ('_%s · %s%s · 질문 %d개_'):format(settings.labels[conv.task] or conv.task, conv.backend, conv.model and (' (' .. conv.model .. ')') or '', #conv.turns) }
  for i, t in ipairs(conv.turns) do
    vim.list_extend(lines, { '', ('## Q%d: %s'):format(i, t.question and t.question:gsub('\n', ' ') or (settings.labels[conv.task] or conv.task)), '' })
    vim.list_extend(lines, t.answer and vim.split(t.answer, '\n', { plain = true }) or { ('**%s** — %s'):format(t.status or '?', t.reason or '') })
  end
  return lines
end

--- Show a conversation in the answer window.
function M.open(id)
  local conv = get(id)
  if not conv then return vim.notify('AI: 이 대화를 기록에서 찾지 못했습니다', vim.log.levels.WARN) end
  render(conv)
end

--- Ask a follow-up question in a conversation (default: the most recent one). Without
--- `question`, asks for it, showing which conversation it continues.
---@param id string?
---@param question string?
function M.follow_up(id, question)
  id = id or M.last_id()
  local conv = id and get(id)
  if not conv then return vim.notify('AI: 이어 갈 대화가 없습니다. 먼저 분석(' .. util.key_hint '<leader>ax' .. ' 등)을 하세요.', vim.log.levels.WARN) end
  render(conv)
  if not question then
    return vim.ui.input({ prompt = ('후속 질문 → [%s · %s] : '):format(conv.title, conv.backend) }, function(q)
      if q and vim.trim(q) ~= '' then M.follow_up(conv.id, q) end
    end)
  end
  send(conv, question)
end

-- Exposed for tests.
function M._forget()
  convs, order = {}, {}
end
M._followup_prompt = followup_prompt
M._get = get

return M
