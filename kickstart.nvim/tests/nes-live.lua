-- Live AI check against the real CLIs (costs a few small requests). Run against an installed config:
--   NVIM_APPNAME=<app> nvim --headless -c "luafile tests/nes-live.lua"            all backends
--   HEES_LIVE_BACKENDS=claude NVIM_APPNAME=<app> nvim --headless -c "luafile …"   selected ones
-- For each backend: make a rename in one place and ask for the next edit, then ask for an
-- explanation of the function; print what came back and what the request log recorded.

vim.env.HEES_NVIM_DATA = vim.env.HEES_NVIM_DATA or vim.fn.tempname()
local analyze = require 'hees.ai.analyze'
local backends = require 'hees.ai.backends'
local log = require 'hees.ai.log'
local nes = require 'hees.nes'
local settings = require 'hees.ai.settings'
local names = vim.env.HEES_LIVE_BACKENDS and vim.split(vim.env.HEES_LIVE_BACKENDS, ',', { trimempty = true }) or backends.names

local function out(s) io.stdout:write(s .. '\n') end

local failed = 0
for _, name in ipairs(names) do
  if not backends.available(name) then
    out(('skip  %s: not installed'):format(name))
  else
    local file = vim.fn.tempname() .. '.py'
    vim.fn.writefile({
      'def area(width, height):',
      '    return width * height',
      '',
      'def describe(width, height):',
      '    a = area(width, height)',
      "    return f'{width}x{height} = {a}'",
    }, file)
    vim.cmd('edit! ' .. vim.fn.fnameescape(file))
    local buf = vim.api.nvim_get_current_buf()
    settings.set_backend(name)

    -- Next edit: the developer starts renaming `width` to `w` in the first function.
    nes._capture(buf)
    vim.api.nvim_buf_set_lines(buf, 0, 2, false, { 'def area(w, height):', '    return width * height' })
    vim.api.nvim_win_set_cursor(0, { 1, 9 })
    local t0 = vim.uv.hrtime()
    nes.request()
    vim.wait(150000, function() return not nes.is_busy() end, 200)
    local secs = (vim.uv.hrtime() - t0) / 1e9
    if nes.has_suggestions() then
      nes.accept(true)
      out(('ok    %s next edit (%.1fs): line 2 after apply = %q'):format(name, secs, vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]))
      nes.dismiss()
    else
      failed = failed + 1
      out(('FAIL  %s next edit (%.1fs): no suggestion shown — see the request log'):format(name, secs))
    end

    -- Analysis: explain the function under the cursor.
    vim.api.nvim_win_set_cursor(0, { 5, 4 })
    t0 = vim.uv.hrtime()
    analyze.run 'explain'
    vim.wait(180000, function() return not analyze.is_busy() end, 200)
    secs = (vim.uv.hrtime() - t0) / 1e9
    local last = log.all(1)[1]
    if last and last.kind == 'analyze' and last.status == 'ok' and (last.text or last.stdout or last.answer or '') ~= '' then
      local reply = vim.trim(last.answer or last.stdout or ''):gsub('%s+', ' ')
      out(('ok    %s explain (%.1fs): %s…'):format(name, secs, reply:sub(1, 120)))
    else
      failed = failed + 1
      out(('FAIL  %s explain (%.1fs): %s'):format(name, secs, last and (last.status .. ' ' .. (last.reason or '')) or 'no log entry'))
    end
    vim.cmd 'only'
    vim.cmd 'bwipeout!'
  end
end
local entries = log.all(1)
out(('log: %d entries in %s'):format(#entries, log.dir()))
for _, e in ipairs(entries) do
  out(('  %-9s %-7s %-20s %5.1fs  %s'):format(e.status, e.kind, e.backend .. (e.model and ('/' .. e.model) or ''), e.elapsed or 0, e.title or ''))
end
vim.cmd(failed == 0 and 'qa!' or 'cq!')
