-- Run one AI request through a backend CLI and record it in hees.ai.log. Shared by next-edit
-- suggestions and code analysis, so both are logged and shown the same way.

local backends = require 'hees.ai.backends'
local log = require 'hees.ai.log'

local M = {}

M.timeout_ms = 180000

---@class hees.ai.Spec
---@field kind string 'nes' | 'analyze'
---@field title string short description shown in the log viewer
---@field backend string
---@field model string?
---@field prompt string sent on stdin
---@field instruction string? closing instruction for backends that take one (gemini -p)
---@field cwd string?
---@field timeout_ms integer?
---@field argv string[]? run this instead of a backend CLI (tests, custom commands)
---@field meta table? extra fields stored with the entry (file, range, …)

--- Start a request. `on_done(entry)` runs on the main loop when it ends; the entry then has
--- stdout, stderr, answer, text (the model's reply), code, signal, elapsed, status
--- ('ok' | 'error' | 'timeout' | 'login' | 'cancelled') and reason. The callback may set
--- entry.outcome before the entry is written to the log.
---@param spec hees.ai.Spec
---@param on_done fun(entry: table)
---@return table? entry with entry.cancel(), string? error
function M.start(spec, on_done)
  local inv, err
  if spec.argv then
    inv = { argv = spec.argv, stdin = spec.prompt }
  else
    inv, err = backends.build(spec.backend, spec.model, spec.prompt, spec.instruction)
    if not inv then return nil, err end
  end
  local entry = log.begin(vim.tbl_extend('force', spec.meta or {}, {
    kind = spec.kind,
    title = spec.title,
    backend = spec.backend,
    model = spec.model,
    cwd = spec.cwd or vim.fn.getcwd(),
    argv = inv.argv,
    prompt = spec.prompt,
  }))
  local started = vim.uv.hrtime()
  local out, errs, login = {}, {}, false
  local handle

  -- Output is collected while it streams so an interactive login prompt (CLI not signed in) stops
  -- the request at once instead of waiting for the timeout.
  local function collect(chunks)
    return function(_, data)
      if not data then return end
      table.insert(chunks, data)
      if not login and data:find(backends.login_prompt_pattern) then
        login = true
        vim.schedule(function() pcall(function() handle:kill 'sigterm' end) end)
      end
    end
  end

  local function done(res)
    entry.stdout, entry.stderr = table.concat(out), table.concat(errs)
    if inv.output_file then
      local f = io.open(inv.output_file, 'r')
      if f then
        entry.answer = f:read '*a'
        f:close()
      end
      os.remove(inv.output_file)
    end
    entry.code, entry.signal = res.code, res.signal
    entry.elapsed = (vim.uv.hrtime() - started) / 1e9
    entry.text = entry.answer or entry.stdout
    if entry.cancelled then
      entry.status = 'cancelled'
    elseif login then
      entry.status = 'login'
      entry.reason = ('the %s CLI is not signed in — run `%s` once in a terminal and log in'):format(spec.backend, spec.backend)
    elseif res.spawn_error then
      entry.status = 'error'
      entry.reason = 'failed to start: ' .. res.spawn_error
    elseif res.code ~= 0 then
      entry.status = res.signal ~= 0 and 'timeout' or 'error'
      entry.reason = res.signal ~= 0 and ('stopped (signal %d, timeout %ds?)'):format(res.signal, (spec.timeout_ms or M.timeout_ms) / 1000)
        or ('exit %d: %s'):format(res.code, vim.trim(entry.stderr):match '[^\n]*$' or '')
    else
      entry.status = 'ok'
    end
    entry.cancel = nil
    local ok, cb_err = pcall(on_done, entry)
    if not ok then entry.outcome = 'callback error: ' .. tostring(cb_err) end
    log.finish(entry)
  end

  local ok, h = pcall(vim.system, inv.argv, {
    stdin = inv.stdin,
    text = true,
    cwd = entry.cwd,
    timeout = spec.timeout_ms or M.timeout_ms,
    stdout = collect(out),
    stderr = collect(errs),
  }, function(res)
    vim.schedule(function() done(res) end)
  end)
  if not ok then
    table.insert(errs, tostring(h))
    done { code = -1, signal = 0, spawn_error = tostring(h) }
    return entry
  end
  handle = h
  entry.cancel = function()
    entry.cancelled = true
    pcall(function() handle:kill 'sigterm' end)
  end
  return entry
end

return M
