-- Live NES check against the real CLIs (costs a few small requests). Run against an installed config:
--   NVIM_APPNAME=<app> nvim --headless -c "luafile tests/nes-live.lua"            all backends
--   HEES_LIVE_BACKENDS=claude NVIM_APPNAME=<app> nvim --headless -c "luafile …"   selected ones
-- For each backend: make a rename in one place, request a suggestion, print what came back.

vim.env.HEES_NVIM_DATA = vim.env.HEES_NVIM_DATA or vim.fn.tempname()
local nes = require 'hees.nes'
local backends = require 'hees.nes.backends'
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
    nes._capture(buf)
    -- The developer starts renaming `width` to `w` in the first function.
    vim.api.nvim_buf_set_lines(buf, 0, 2, false, { 'def area(w, height):', '    return width * height' })
    vim.api.nvim_win_set_cursor(0, { 1, 9 })
    nes.set_backend(name)
    local t0 = vim.uv.hrtime()
    nes.request()
    vim.wait(150000, function() return not nes.is_busy() end, 200)
    local secs = (vim.uv.hrtime() - t0) / 1e9
    if nes.has_suggestions() then
      nes.accept(true)
      out(('ok    %s (%.1fs): line 2 after apply = %q'):format(name, secs, vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]))
      nes.dismiss()
    else
      failed = failed + 1
      out(('FAIL  %s (%.1fs): no suggestion shown — see log'):format(name, secs))
    end
    vim.cmd 'bwipeout!'
  end
end
local logs = vim.fn.glob(vim.fs.joinpath(vim.env.HEES_NVIM_DATA, 'nes', 'logs', '*.log'), false, true)
out('log: ' .. (logs[1] or '(none)'))
vim.cmd(failed == 0 and 'qa!' or 'cq!')
