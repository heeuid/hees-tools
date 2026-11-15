-- NES (Next Edit Suggestion) backed by the Claude, Codex or Gemini CLI.
--
-- Recent edits (as diffs) and the code around the cursor go to the selected CLI, which answers
-- with JSON line-range replacements. Suggestions are shown inline as a diff; <leader>aa jumps to
-- the next one and, when the cursor is already on it, applies it (no Neovim default key is remapped).
-- Every request is logged verbatim (`:Nes log`) and shown while it runs.

local backends = require 'hees.nes.backends'
local log = require 'hees.nes.log'
local util = require 'hees.util'

local M = {}

M.config = {
  context_lines = 40, -- lines sent above and below the cursor
  max_history = 6, -- recent edit diffs kept per buffer
  max_history_chars = 6000,
  max_edits = 3,
  timeout_ms = 90000,
  auto_delay_ms = 1500,
}

local ns_anchor = vim.api.nvim_create_namespace 'hees.nes.anchor'
local ns_view = vim.api.nvim_create_namespace 'hees.nes.view'
local ns_busy = vim.api.nvim_create_namespace 'hees.nes.busy'
local group = vim.api.nvim_create_augroup('hees-nes', { clear = true })

-- [[ Persistent settings ]]

local settings
local function state_path() return vim.fs.joinpath(util.data_dir 'nes', 'state.json') end

local function load_settings()
  settings = util.read_json(state_path(), { backend = 'claude', models = vim.empty_dict(), auto = false })
  if not vim.tbl_contains(backends.names, settings.backend) then settings.backend = 'claude' end
end

local function save_settings() util.write_json(state_path(), settings) end

function M.settings() return settings end

local function model_for(backend)
  local m = settings.models[backend]
  if m == nil or m == '' then return backends.default_models[backend] end
  return m
end

-- [[ Recent edit tracking ]]

---@type table<integer, { snapshot: string, history: string[] }>
local tracked = {}

local function eligible(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == ''
    and vim.bo[buf].modifiable
    and vim.api.nvim_buf_get_name(buf) ~= ''
    and vim.api.nvim_buf_line_count(buf) <= 20000
end

local function buf_text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n' end

--- Record what changed since the last snapshot as a unified diff.
local function capture(buf)
  if not eligible(buf) then return end
  local text = buf_text(buf)
  local t = tracked[buf]
  if not t then
    tracked[buf] = { snapshot = text, history = {} }
    return
  end
  if t.snapshot == text then return end
  local diff = vim.text.diff(t.snapshot, text, { ctxlen = 2 })
  t.snapshot = text
  if type(diff) ~= 'string' or diff == '' then return end
  table.insert(t.history, diff)
  local total = 0
  for _, d in ipairs(t.history) do
    total = total + #d
  end
  while #t.history > 1 and (#t.history > M.config.max_history or total > M.config.max_history_chars) do
    total = total - #table.remove(t.history, 1)
  end
end

-- [[ Prompt ]]

local function build_prompt(req)
  local numbered = {}
  for i, line in ipairs(req.lines) do
    numbered[i] = ('%d| %s'):format(req.first + i - 1, line)
  end
  local history = tracked[req.buf] and tracked[req.buf].history or {}
  local parts = {
    'You are the "next edit suggestion" engine of a code editor.',
    'Predict the edit the developer will most likely make next, based on their recent edits and the code around the cursor.',
    '',
    'Rules:',
    '- Only suggest edits clearly implied by the recent edits or the code (continue a pattern, propagate a rename,',
    '  update related lines, finish an obvious follow-up, fix an obvious mistake). If nothing is clearly implied, return no edits.',
    ('- Edits must stay inside the shown lines %d-%d. Line numbers are 1-based and refer to the code exactly as shown.'):format(req.first, req.last),
    '- Each edit replaces lines start_line..end_line (inclusive) with `replacement` (lines joined with \\n; empty string deletes).',
    '  To insert without replacing, use end_line = start_line - 1; the text is inserted before start_line.',
    '- `replacement` must not contain the "N| " line-number prefixes. Keep the file\'s indentation style.',
    ('- At most %d edits, none overlapping, ordered by start_line.'):format(M.config.max_edits),
    '- Output ONLY one JSON object, no prose and no code fences:',
    '  {"edits":[{"start_line":N,"end_line":M,"replacement":"..."}],"reason":"one short sentence"}',
    '',
    ('File: %s (filetype: %s)'):format(req.path, req.filetype),
    ('Cursor: line %d, column %d'):format(req.cursor[1], req.cursor[2] + 1),
  }
  if req.range then
    table.insert(parts, ('The developer selected lines %d-%d and wants an edit there.'):format(req.range[1], req.range[2]))
  end
  table.insert(parts, '')
  if #history > 0 then
    table.insert(parts, 'Recent edits in this file (unified diffs, oldest first):')
    vim.list_extend(parts, history)
  else
    table.insert(parts, 'Recent edits: none recorded yet.')
  end
  table.insert(parts, '')
  table.insert(parts, ('Current code, lines %d-%d of %d (format "N| text"):'):format(req.first, req.last, req.line_count))
  vim.list_extend(parts, numbered)
  return table.concat(parts, '\n') .. '\n'
end

-- [[ Answer parsing ]]

--- Extract and validate edits from the CLI answer.
---@return table[]? edits, string? error
function M.parse(text, req)
  local s = text:find('{', 1, true)
  local e = text:match '.*()}'
  if not s or not e or e < s then return nil, 'no JSON object in the answer' end
  local ok, obj = pcall(vim.json.decode, text:sub(s, e), { luanil = { object = true, array = true } })
  if not ok or type(obj) ~= 'table' then return nil, 'answer is not valid JSON' end
  if type(obj.edits) ~= 'table' then return nil, 'answer has no "edits" list' end
  local edits = {}
  for _, raw in ipairs(obj.edits) do
    local first, last, repl = tonumber(raw.start_line), tonumber(raw.end_line), raw.replacement
    if first and last and type(repl) == 'string' then
      first, last = math.floor(first), math.floor(last)
      local insert = last == first - 1
      local in_window = first >= req.first and first <= req.last + 1 and (insert or (last >= first and last <= req.last))
      if in_window then
        local orig = {}
        for l = first, last do
          table.insert(orig, req.lines[l - req.first + 1])
        end
        local new = repl == '' and {} or vim.split(repl:gsub('\r\n', '\n'), '\n', { plain = true })
        if #new > 0 and new[#new] == '' and repl:sub(-1) == '\n' then table.remove(new) end
        local prev = edits[#edits]
        local overlaps = prev and first <= prev.last
        if not vim.deep_equal(orig, new) and not (insert and #new == 0) and not overlaps then
          table.insert(edits, { first = first, last = last, insert = insert, orig = orig, new = new })
        end
      end
    end
    if #edits >= M.config.max_edits then break end
  end
  return edits, nil, obj.reason
end

-- [[ Suggestion display ]]

---@type { buf: integer, edits: table[], idx: integer, tick: integer }?
local active

local function edit_rows(buf, edit)
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns_anchor, edit.mark, { details = true })
  if #pos == 0 then return nil end
  local row = pos[1]
  if edit.insert then return row, row end
  return row, pos[3].end_row or row
end

local function render()
  if not active then return end
  local buf = active.buf
  vim.api.nvim_buf_clear_namespace(buf, ns_view, 0, -1)
  local icons = util.icons()
  local win = vim.fn.bufwinid(buf)
  local width = win ~= -1 and (vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff) or 80
  local tab = string.rep(' ', vim.bo[buf].tabstop)
  for i, edit in ipairs(active.edits) do
    local r0, r1 = edit_rows(buf, edit)
    if r0 then
      local virt = {}
      for _, line in ipairs(edit.new) do
        local text = line:gsub('\t', tab)
        table.insert(virt, { { text .. string.rep(' ', math.max(0, width - vim.fn.strdisplaywidth(text))), 'HeesNesAdd' } })
      end
      local after_last = edit.insert and edit.after_last
      if not edit.insert then
        for r = r0, r1 do
          vim.api.nvim_buf_set_extmark(buf, ns_view, r, 0, { line_hl_group = 'HeesNesDelete', priority = 300 })
        end
      end
      if #virt > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns_view, edit.insert and r0 or r1, 0, {
          virt_lines = virt,
          virt_lines_above = edit.insert and not after_last,
        })
      end
      local hint = i == active.idx and (' %s %s: jump/apply  %d/%d '):format(icons.ai, util.key_hint '<leader>aa', i, #active.edits) or (' %s %d/%d '):format(icons.ai, i, #active.edits)
      vim.api.nvim_buf_set_extmark(buf, ns_view, r0, 0, { virt_text = { { hint, 'HeesNesHint' } }, virt_text_pos = 'eol' })
    end
  end
end

function M.dismiss()
  if not active then return end
  local buf = active.buf
  active = nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns_view, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf, ns_anchor, 0, -1)
  end
end

function M.has_suggestions() return active ~= nil end

local function remove_edit(i)
  local edit = table.remove(active.edits, i)
  pcall(vim.api.nvim_buf_del_extmark, active.buf, ns_anchor, edit.mark)
  if #active.edits == 0 then return M.dismiss() end
  active.idx = math.min(i, #active.edits)
  render()
end

--- Apply the current suggestion if the cursor is on it, otherwise jump to it.
---@param force boolean? apply without jumping first
function M.accept(force)
  if not active then return end
  local buf = active.buf
  if vim.api.nvim_get_current_buf() ~= buf then return end
  local edit = active.edits[active.idx]
  local r0, r1 = edit_rows(buf, edit)
  if not r0 then return remove_edit(active.idx) end
  local cur = vim.api.nvim_win_get_cursor(0)[1] - 1
  if not force and (cur < r0 or cur > r1) then
    vim.api.nvim_win_set_cursor(0, { r0 + 1, 0 })
    vim.cmd 'normal! ^'
    return
  end
  if not edit.insert then
    local now = vim.api.nvim_buf_get_lines(buf, r0, r1 + 1, false)
    if not vim.deep_equal(now, edit.orig) then
      vim.notify('NES: the target lines changed since the suggestion was made; skipped it', vim.log.levels.WARN)
      return remove_edit(active.idx)
    end
    vim.api.nvim_buf_set_lines(buf, r0, r1 + 1, false, edit.new)
  else
    local at = edit.after_last and r0 + 1 or r0
    vim.api.nvim_buf_set_lines(buf, at, at, false, edit.new)
    r0 = at
  end
  if #edit.new > 0 then vim.api.nvim_win_set_cursor(0, { r0 + #edit.new, 0 }) end
  active.tick = vim.b[buf].changedtick
  capture(buf)
  remove_edit(active.idx)
end

function M.accept_all()
  while active do
    M.accept(true)
  end
end

local function show(req, edits)
  local buf = req.buf
  if not vim.api.nvim_buf_is_valid(buf) then return 0 end
  local n = vim.api.nvim_buf_line_count(buf)
  local kept = {}
  for _, edit in ipairs(edits) do
    -- The buffer may have changed while the CLI was thinking; keep only edits whose lines are intact.
    local intact = edit.insert or vim.deep_equal(vim.api.nvim_buf_get_lines(buf, edit.first - 1, edit.last, false), edit.orig)
    if intact and edit.first <= n + 1 then
      if edit.insert then
        edit.after_last = edit.first > n
        local row = edit.after_last and n - 1 or edit.first - 1
        edit.mark = vim.api.nvim_buf_set_extmark(buf, ns_anchor, row, 0, {})
      else
        local last_line = vim.api.nvim_buf_get_lines(buf, edit.last - 1, edit.last, false)[1] or ''
        edit.mark = vim.api.nvim_buf_set_extmark(buf, ns_anchor, edit.first - 1, 0, { end_row = edit.last - 1, end_col = #last_line })
      end
      table.insert(kept, edit)
    end
  end
  if #kept == 0 then return 0 end
  active = { buf = buf, edits = kept, idx = 1, tick = vim.b[buf].changedtick }
  render()
  return #kept
end

-- [[ Requests ]]

local busy ---@type table?
local request_id = 0

local function stop_spinner(req)
  if req.timer then
    req.timer:stop()
    req.timer:close()
    req.timer = nil
  end
  if vim.api.nvim_buf_is_valid(req.buf) then vim.api.nvim_buf_clear_namespace(req.buf, ns_busy, 0, -1) end
end

local function start_spinner(req)
  local frames = util.icons().spinner
  local i = 0
  req.timer = vim.uv.new_timer()
  req.timer:start(
    0,
    120,
    vim.schedule_wrap(function()
      if not req.timer or not vim.api.nvim_buf_is_valid(req.buf) then return end
      i = i % #frames + 1
      local text = (' %s NES · %s%s  %.1fs '):format(frames[i], req.backend, req.model and ('/' .. req.model) or '', (vim.uv.hrtime() - req.started) / 1e9)
      local row = math.min(req.cursor[1], vim.api.nvim_buf_line_count(req.buf)) - 1
      req.busy_mark = vim.api.nvim_buf_set_extmark(req.buf, ns_busy, row, 0, { id = req.busy_mark, virt_text = { { text, 'HeesNesBusy' } }, virt_text_pos = 'eol' })
    end)
  )
end

function M.is_busy() return busy ~= nil end

function M.cancel()
  if not busy then return end
  local req = busy
  busy = nil
  req.cancelled = true
  stop_spinner(req)
  pcall(function() req.handle:kill 'sigterm' end)
  vim.notify 'NES: request cancelled'
end

local function finish(req, res)
  local cancelled = req.cancelled
  if not cancelled then
    if busy == req then busy = nil end
    stop_spinner(req)
  end
  local elapsed = (vim.uv.hrtime() - req.started) / 1e9
  local answer
  if req.output_file then
    local f = io.open(req.output_file, 'r')
    if f then
      answer = f:read '*a'
      f:close()
    end
    os.remove(req.output_file)
  end
  local entry = {
    id = req.id,
    backend = req.backend,
    model = req.model,
    cwd = req.cwd,
    argv = req.argv,
    prompt = req.prompt,
    stdout = res.stdout,
    stderr = res.stderr,
    answer = answer,
    code = res.code,
    elapsed = elapsed,
  }
  local function done(outcome, msg, level)
    entry.outcome = outcome
    log.write(entry)
    if msg then vim.notify(('NES · %s: %s (%.1fs)'):format(req.backend, msg, elapsed), level) end
  end

  if cancelled then return done 'cancelled' end
  if req.login_prompt then
    return done(
      'login required',
      ('the %s CLI is not signed in — run `%s` once in a terminal and log in'):format(req.backend, req.backend),
      vim.log.levels.ERROR
    )
  end
  if res.code ~= 0 then
    local reason = res.signal ~= 0 and ('stopped (signal %d, timeout %ds?)'):format(res.signal, M.config.timeout_ms / 1000)
      or ('exit %d: %s'):format(res.code, vim.trim(res.stderr or ''):match '[^\n]*$' or '')
    return done('error', reason .. ' — see :Nes log', vim.log.levels.ERROR)
  end
  local edits, err, reason = M.parse(answer or res.stdout or '', req)
  if not edits then return done('parse error: ' .. err, err .. ' — see :Nes log', vim.log.levels.WARN) end
  if vim.api.nvim_get_current_buf() ~= req.buf then return done(('%d edits, buffer left'):format(#edits)) end
  local shown = show(req, edits)
  if shown == 0 then return done('no edits', not req.auto and 'no suggestion' or nil) end
  done(('%d edits shown'):format(shown), ('%d suggestion%s — %s to jump/apply%s'):format(shown, shown > 1 and 's' or '', util.key_hint '<leader>aa', reason and ('  (' .. reason .. ')') or ''))
end

--- Ask the selected backend for the next edit.
---@param opts { range: integer[]?, auto: boolean? }?
function M.request(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  if not eligible(buf) then
    if not opts.auto then vim.notify('NES: this buffer is not a file that can be edited', vim.log.levels.WARN) end
    return
  end
  if busy then M.cancel() end
  M.dismiss()
  capture(buf)

  local n = vim.api.nvim_buf_line_count(buf)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lo, hi = cursor[1], cursor[1]
  if opts.range then
    lo, hi = math.min(opts.range[1], opts.range[2]), math.max(opts.range[1], opts.range[2])
  end
  local first = math.max(1, lo - M.config.context_lines)
  local last = math.min(n, hi + M.config.context_lines)
  local backend = settings.backend
  local req = {
    id = 0,
    buf = buf,
    auto = opts.auto,
    range = opts.range and { lo, hi } or nil,
    first = first,
    last = last,
    line_count = n,
    lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false),
    cursor = cursor,
    path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':~:.'),
    filetype = vim.bo[buf].filetype,
    backend = backend,
    model = model_for(backend),
    cwd = vim.fn.getcwd(),
  }
  req.prompt = build_prompt(req)
  local inv, err = backends.build(backend, req.model, req.prompt)
  if not inv then return vim.notify('NES: ' .. err, vim.log.levels.ERROR) end
  request_id = request_id + 1
  req.id = request_id
  req.argv = inv.argv
  req.output_file = inv.output_file
  req.started = vim.uv.hrtime()

  -- Output is collected while it streams so an interactive login prompt (CLI not signed in) stops
  -- the request at once instead of waiting for the timeout.
  req.stdout, req.stderr = {}, {}
  local function collect(chunks)
    return function(_, data)
      if not data then return end
      table.insert(chunks, data)
      if not req.login_prompt and data:find(backends.login_prompt_pattern) then
        req.login_prompt = true
        vim.schedule(function() pcall(function() req.handle:kill 'sigterm' end) end)
      end
    end
  end
  local ok, handle = pcall(vim.system, inv.argv, {
    stdin = inv.stdin,
    text = true,
    cwd = req.cwd,
    timeout = M.config.timeout_ms,
    stdout = collect(req.stdout),
    stderr = collect(req.stderr),
  }, function(res)
    res.stdout, res.stderr = table.concat(req.stdout), table.concat(req.stderr)
    vim.schedule(function() finish(req, res) end)
  end)
  if not ok then
    log.write(vim.tbl_extend('force', req, { code = -1, stderr = tostring(handle), outcome = 'spawn failed' }))
    return vim.notify('NES: failed to start ' .. backend .. ': ' .. tostring(handle), vim.log.levels.ERROR)
  end
  req.handle = handle
  busy = req
  start_spinner(req)
end

-- [[ Settings commands ]]

function M.set_backend(name)
  if not vim.tbl_contains(backends.names, name) then return vim.notify('NES: unknown backend ' .. tostring(name), vim.log.levels.ERROR) end
  if not backends.available(name) then vim.notify('NES: ' .. name .. ' CLI is not on PATH', vim.log.levels.WARN) end
  settings.backend = name
  save_settings()
  vim.notify(('NES: backend = %s (model: %s)'):format(name, model_for(name) or 'CLI default'))
end

function M.select_backend()
  vim.ui.select(backends.names, {
    prompt = 'NES backend',
    format_item = function(name)
      local mark = name == settings.backend and '● ' or '  '
      return mark .. name .. (backends.available(name) and '' or '  (not installed)')
    end,
  }, function(choice)
    if choice then M.set_backend(choice) end
  end)
end

--- Set the model for the current backend; empty means the default.
---@param model string?
function M.set_model(model)
  local backend = settings.backend
  if model == nil then
    return vim.ui.input({ prompt = ('Model for %s (empty = %s): '):format(backend, backends.default_models[backend] or 'CLI default'), default = settings.models[backend] or '' }, function(input)
      if input ~= nil then M.set_model(input) end
    end)
  end
  settings.models[backend] = model ~= '' and model or nil
  save_settings()
  vim.notify(('NES: %s model = %s'):format(backend, model_for(backend) or 'CLI default'))
end

function M.set_auto(on)
  if on == nil then on = not settings.auto end
  settings.auto = on
  save_settings()
  vim.notify('NES: auto suggest ' .. (on and 'on' or 'off'))
end

-- [[ Menu ]]

function M.menu_items(visual)
  local has = function() return active ~= nil and active.buf == vim.api.nvim_get_current_buf() end
  local backend_items = {}
  for _, name in ipairs(backends.names) do
    local available = backends.available(name)
    table.insert(backend_items, {
      label = name .. (available and '' or '  (not installed)'),
      checked = name == settings.backend,
      enabled = available,
      action = function() M.set_backend(name) end,
    })
  end
  local model = model_for(settings.backend)
  return {
    visual and {
      label = 'Suggest edit for selection',
      hint = '<leader>an',
      action = function()
        vim.cmd 'normal! \27'
        M.request { range = { vim.fn.line "'<", vim.fn.line "'>" } }
      end,
    } or { label = 'Suggest next edit', hint = '<leader>an', action = function() M.request() end },
    { label = 'Jump to / apply suggestion', hint = '<leader>aa', action = function() M.accept() end, enabled = has },
    { label = 'Apply all suggestions', action = M.accept_all, enabled = has },
    { label = 'Dismiss suggestions', hint = '<leader>ad', action = M.dismiss, enabled = has },
    { label = 'Cancel running request', action = M.cancel, enabled = busy ~= nil },
    { sep = true },
    { label = 'Backend: ' .. settings.backend, items = backend_items },
    { label = 'Model: ' .. (model or 'CLI default') .. '…', hint = '<leader>am', action = function() M.set_model() end },
    { label = 'Auto suggest', hint = '<leader>at', checked = settings.auto, action = function() M.set_auto() end },
    { label = 'Open request log', hint = '<leader>al', action = log.open },
  }
end

-- [[ Setup ]]

local auto_timer

local function schedule_auto(buf)
  if not settings.auto or busy or active then return end
  auto_timer = auto_timer or vim.uv.new_timer()
  auto_timer:stop()
  auto_timer:start(
    M.config.auto_delay_ms,
    0,
    vim.schedule_wrap(function()
      if vim.api.nvim_get_current_buf() == buf and vim.fn.mode() == 'n' and not busy and not active then M.request { auto = true } end
    end)
  )
end

local subcommands = {
  request = function() M.request() end,
  accept = function() M.accept() end,
  accept_all = M.accept_all,
  dismiss = M.dismiss,
  cancel = M.cancel,
  backend = function(arg)
    if arg then return M.set_backend(arg) end
    M.select_backend()
  end,
  model = function(arg) M.set_model(arg) end,
  auto = function(arg)
    if arg == 'on' then return M.set_auto(true) end
    if arg == 'off' then return M.set_auto(false) end
    M.set_auto()
  end,
  log = log.open,
  status = function()
    vim.notify(
      ('NES: backend=%s model=%s auto=%s busy=%s suggestions=%d\nlog: %s'):format(
        settings.backend,
        model_for(settings.backend) or 'CLI default',
        tostring(settings.auto),
        tostring(busy ~= nil),
        active and #active.edits or 0,
        log.today()
      )
    )
  end,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  load_settings()

  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter' }, {
    group = group,
    callback = function(ev)
      if not tracked[ev.buf] then capture(ev.buf) end
    end,
  })
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'TextChanged' }, {
    group = group,
    callback = function(ev)
      if active and active.buf == ev.buf and vim.b[ev.buf].changedtick == active.tick then return end
      M.dismiss()
      capture(ev.buf)
      schedule_auto(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd('TextChangedI', {
    group = group,
    callback = function(ev)
      if active and active.buf == ev.buf then M.dismiss() end
    end,
  })
  vim.api.nvim_create_autocmd('BufLeave', { group = group, callback = function() M.dismiss() end })
  vim.api.nvim_create_autocmd('BufWipeout', { group = group, callback = function(ev) tracked[ev.buf] = nil end })

  vim.api.nvim_create_user_command('Nes', function(cmd)
    local sub = subcommands[cmd.fargs[1] or 'request']
    if not sub then return vim.notify('Nes: unknown subcommand ' .. cmd.fargs[1], vim.log.levels.ERROR) end
    sub(cmd.fargs[2])
  end, {
    nargs = '*',
    desc = 'Next edit suggestion (Claude / Codex / Gemini)',
    complete = function(_, line)
      local args = vim.split(line, '%s+')
      if #args <= 2 then return vim.tbl_keys(subcommands) end
      if args[2] == 'backend' then return backends.names end
      if args[2] == 'auto' then return { 'on', 'off' } end
      return {}
    end,
  })

  local map = vim.keymap.set
  map('n', '<leader>an', function() M.request() end, { desc = 'AI: suggest [N]ext edit' })
  map('x', '<leader>an', function()
    vim.cmd 'normal! \27'
    M.request { range = { vim.fn.line "'<", vim.fn.line "'>" } }
  end, { desc = 'AI: suggest edit for selection' })
  map('n', '<leader>aa', function() M.accept() end, { desc = 'AI: jump to / [A]pply suggestion' })
  map('n', '<leader>ad', M.dismiss, { desc = 'AI: [D]ismiss suggestions' })
  map('n', '<leader>ac', M.cancel, { desc = 'AI: [C]ancel request' })
  map('n', '<leader>ab', M.select_backend, { desc = 'AI: choose [B]ackend' })
  map('n', '<leader>am', function() M.set_model() end, { desc = 'AI: set [M]odel' })
  map('n', '<leader>at', function() M.set_auto() end, { desc = 'AI: [T]oggle auto suggest' })
  map('n', '<leader>al', log.open, { desc = 'AI: open request [L]og' })
  local has_wk, wk = pcall(require, 'which-key')
  if has_wk then wk.add { { '<leader>a', group = '[A]I next edit', mode = { 'n', 'x' } } } end
end

-- Exposed for tests.
M._build_prompt = build_prompt
M._capture = capture
M._finish = finish
M._tracked = tracked

return M
