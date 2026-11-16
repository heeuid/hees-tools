-- AI request log viewer: a tab with every request (next edits and analysis, newest first) on the
-- left and the full record of the one under the cursor on the right: command, working
-- directory, the prompt sent on stdin, the reply, stderr, exit code and timing. Running requests
-- appear at once and update when they finish.
--
-- `g` switches to conversations: one row per explain/review/ask/debug conversation (follow-up
-- questions grouped), with its questions and answers on the right; `c` continues the selected
-- conversation with a follow-up question (in either view).
--
-- List keys: j/k or click to move, <CR>/l to jump into the record, g requests/conversations,
-- c follow-up question, r refresh, y yank the command, Y yank the reply, o open the raw JSONL
-- file, q close.

local conversation = require 'hees.ai.conversation'
local log = require 'hees.ai.log'

local M = {}

M.days = 7 -- how many days of log files to show

local view ---@type { tab: integer, list_win: integer, list_buf: integer, detail_win: integer, detail_buf: integer, entries: table[], shown: string?, conversations: boolean? }?
local ns = vim.api.nvim_create_namespace 'hees.ai.viewer'

local STATUS = {
  running = { '…', 'DiagnosticInfo' },
  ok = { '✓', 'DiagnosticOk' },
  cancelled = { '–', 'Comment' },
}
local FAILED = { '✗', 'DiagnosticError' }

local function valid() return view and vim.api.nvim_tabpage_is_valid(view.tab) and vim.api.nvim_buf_is_valid(view.list_buf) end

local function quote(arg)
  if arg == '' then return '""' end
  if arg:find '[%s"\']' then return '"' .. arg:gsub('"', '\\"') .. '"' end
  return arg
end

local function command_line(e) return table.concat(vim.tbl_map(quote, e.argv or {}), ' ') end

local function fence(text, lang)
  text = text or ''
  local ticks = text:find('```', 1, true) and '````' or '```'
  return vim.list_extend({ ticks .. (lang or '') }, vim.list_extend(vim.split((text:gsub('\n$', '')), '\n', { plain = true }), { ticks }))
end

local function detail_lines(e)
  local lines = {
    '# ' .. (e.title or e.kind or 'request'),
    '',
    ('- **status**: %s%s'):format(e.status or '?', e.outcome and e.outcome ~= e.status and (' — ' .. e.outcome) or ''),
  }
  if e.reason then table.insert(lines, '- **reason**: ' .. e.reason) end
  vim.list_extend(lines, {
    ('- **task**: %s · **backend**: %s · **model**: %s'):format(e.task or e.kind or '?', e.backend or '?', e.model or 'CLI default'),
    ('- **time**: %s · **elapsed**: %s · **exit**: %s'):format(os.date('%Y-%m-%d %H:%M:%S', e.time or 0), e.elapsed and ('%.2fs'):format(e.elapsed) or 'running', tostring(e.code)),
    '- **cwd**: ' .. (e.cwd or '?'),
  })
  if e.file then table.insert(lines, ('- **file**: %s%s'):format(e.file, e.range and (':%d-%d'):format(e.range[1], e.range[2]) or '')) end
  vim.list_extend(lines, { '', '## Command' })
  vim.list_extend(lines, fence(command_line(e), 'sh'))
  vim.list_extend(lines, { '', ('## Input — stdin (%d lines)'):format(select(2, (e.prompt or ''):gsub('\n', '')) + 1) })
  vim.list_extend(lines, fence(e.prompt, 'text'))
  if e.answer then
    vim.list_extend(lines, { '', '## Reply (answer file)' })
    vim.list_extend(lines, fence(e.answer, 'text'))
  end
  vim.list_extend(lines, { '', e.answer and '## stdout' or '## Reply (stdout)' })
  vim.list_extend(lines, fence(e.status == 'running' and '(running…)' or e.stdout, 'text'))
  if e.stderr and e.stderr ~= '' then
    vim.list_extend(lines, { '', '## stderr' })
    vim.list_extend(lines, fence(e.stderr, 'text'))
  end
  return lines
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function selected()
  if not valid() then return nil end
  local row = vim.api.nvim_win_get_cursor(view.list_win)[1]
  return view.entries[row - 1] -- row 1 is the header
end

local function show_selected(force)
  local e = selected()
  if not e then return end
  local key = view.conversations and (e.id .. e.count .. e.answered) or (e.uid .. (e.status or ''))
  if not force and view.shown == key then return end
  view.shown = key
  set_lines(view.detail_buf, view.conversations and conversation.transcript(e.id) or detail_lines(e))
  pcall(vim.api.nvim_win_set_cursor, view.detail_win, { 1, 0 })
end

function M.refresh()
  if not valid() then return end
  local keep = selected()
  local lines
  if view.conversations then
    view.entries = conversation.list()
    lines = { ('AI conversations — %d   c 후속 질문 · g 요청 목록 · <CR> 보기 · r refresh · q close'):format(#view.entries) }
    for _, c in ipairs(view.entries) do
      c.status = c.answered > 0 and 'ok' or 'failed'
      table.insert(lines, ('%s %s  %-7s %-24s %2d Q  %s'):format(
        (STATUS[c.status] or FAILED)[1],
        os.date('%m-%d %H:%M:%S', c.time or 0),
        c.task or '?',
        (c.backend or '?') .. (c.model and ('/' .. c.model) or ''),
        c.count,
        c.title or ''
      ))
    end
  else
    view.entries = log.all(M.days)
    lines = { ('AI requests — %d (last %d days)   <CR> open · g conversations · c follow-up · r refresh · y command · Y reply · o file · q close'):format(#view.entries, M.days) }
    for _, e in ipairs(view.entries) do
      local mark = STATUS[e.status] or FAILED
      table.insert(lines, ('%s %s  %-7s %-24s %7s  %s'):format(
        mark[1],
        os.date('%m-%d %H:%M:%S', e.time or 0),
        e.task or e.kind or '?',
        (e.backend or '?') .. (e.model and ('/' .. e.model) or ''),
        e.elapsed and ('%.1fs'):format(e.elapsed) or '',
        e.title or ''
      ))
    end
  end
  set_lines(view.list_buf, lines)
  vim.api.nvim_buf_clear_namespace(view.list_buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(view.list_buf, ns, 0, 0, { end_col = #lines[1], hl_group = 'Title' })
  for i, e in ipairs(view.entries) do
    local mark = STATUS[e.status] or FAILED
    vim.api.nvim_buf_set_extmark(view.list_buf, ns, i, 0, { end_col = #mark[1], hl_group = mark[2] })
  end
  local row = 2
  if keep then
    for i, e in ipairs(view.entries) do
      if (e.uid and e.uid == keep.uid) or (e.id and e.id == keep.id) then row = i + 1 end
    end
  end
  pcall(vim.api.nvim_win_set_cursor, view.list_win, { math.min(row, #lines), 0 })
  show_selected(true)
end

local function close()
  if valid() then pcall(vim.cmd.tabclose, vim.api.nvim_tabpage_get_number(view.tab)) end
  view = nil
end

local function yank(text, what)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify('AI log: copied ' .. what)
end

--- Open the viewer (or go to it).
---@param opts { conversations: boolean? }? start in the conversations view
function M.open(opts)
  opts = opts or {}
  if valid() then
    vim.api.nvim_set_current_tabpage(view.tab)
    if opts.conversations ~= nil then view.conversations = opts.conversations end
    return M.refresh()
  end
  vim.cmd 'tabnew'
  local tab = vim.api.nvim_get_current_tabpage()
  local detail_win = vim.api.nvim_get_current_win()
  local detail_buf = vim.api.nvim_get_current_buf()
  vim.bo[detail_buf].buftype = 'nofile'
  vim.bo[detail_buf].bufhidden = 'wipe'
  vim.bo[detail_buf].filetype = 'markdown'
  pcall(vim.api.nvim_buf_set_name, detail_buf, 'AI request')
  vim.wo[detail_win].wrap = true
  vim.wo[detail_win].linebreak = true

  vim.cmd('topleft vertical ' .. math.min(90, math.floor(vim.o.columns * 0.45)) .. 'new')
  local list_win = vim.api.nvim_get_current_win()
  local list_buf = vim.api.nvim_get_current_buf()
  vim.bo[list_buf].buftype = 'nofile'
  vim.bo[list_buf].bufhidden = 'wipe'
  vim.bo[list_buf].filetype = 'hees-ai-log'
  pcall(vim.api.nvim_buf_set_name, list_buf, 'AI requests')
  vim.wo[list_win].wrap = false
  vim.wo[list_win].cursorline = true
  vim.wo[list_win].number = false

  view = { tab = tab, list_win = list_win, list_buf = list_buf, detail_win = detail_win, detail_buf = detail_buf, entries = {}, conversations = opts.conversations }

  local function map(buf, lhs, fn) vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true }) end
  for _, buf in ipairs { list_buf, detail_buf } do
    map(buf, 'q', close)
  end
  map(list_buf, 'r', M.refresh)
  map(list_buf, 'g', function()
    view.conversations = not view.conversations
    view.shown = nil
    M.refresh()
  end)
  map(list_buf, 'c', function()
    local e = selected()
    local id = e and (view.conversations and e.id or e.conv)
    if not id then return vim.notify('AI: 이 요청은 대화가 아닙니다 (다음 편집 제안 등)', vim.log.levels.WARN) end
    close()
    conversation.follow_up(id)
  end)
  map(list_buf, '<CR>', function() vim.api.nvim_set_current_win(view.detail_win) end)
  map(list_buf, 'l', function() vim.api.nvim_set_current_win(view.detail_win) end)
  map(detail_buf, 'h', function() vim.api.nvim_set_current_win(view.list_win) end)
  map(list_buf, 'y', function()
    local e = selected()
    if e then yank(command_line(e), 'command') end
  end)
  map(list_buf, 'Y', function()
    local e = selected()
    if e then yank(e.answer or e.stdout or '', 'reply') end
  end)
  map(list_buf, 'o', function()
    local e = selected()
    if e then vim.cmd('tabedit ' .. vim.fn.fnameescape(log.file_for(e.time))) end
  end)
  vim.api.nvim_create_autocmd('CursorMoved', { buffer = list_buf, callback = function() show_selected(false) end })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = list_buf,
    callback = function()
      if view and view.list_buf == list_buf then view = nil end
    end,
  })
  M.refresh()
end

-- Keep an open viewer current while requests start and finish.
log.subscribe(function()
  if valid() then vim.schedule(M.refresh) end
end)

-- Exposed for tests.
M._detail_lines = detail_lines
function M._view() return view end

return M
