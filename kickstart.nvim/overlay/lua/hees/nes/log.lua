-- Verbatim record of every NES request: command, prompt, raw output, exit code, timing.
-- One plain-text file per day in <config>/data/nes/logs/.

local util = require 'hees.util'

local M = {}

function M.dir() return util.data_dir('nes', 'logs') end

function M.today() return vim.fs.joinpath(M.dir(), os.date '%Y-%m-%d' .. '.log') end

---@param entry { id: integer, backend: string, model: string?, cwd: string, argv: string[], prompt: string, stdout: string?, stderr: string?, answer: string?, code: integer?, elapsed: number?, outcome: string }
function M.write(entry)
  local parts = {
    ('==== %s  request #%d  backend=%s  model=%s ===='):format(os.date '%Y-%m-%d %H:%M:%S', entry.id, entry.backend, entry.model or '(default)'),
    'cwd:  ' .. entry.cwd,
    'argv: ' .. vim.inspect(entry.argv, { newline = ' ', indent = '' }),
    '---- prompt (stdin) ----',
    entry.prompt,
    '---- stdout ----',
    entry.stdout or '',
    '---- stderr ----',
    entry.stderr or '',
  }
  if entry.answer then vim.list_extend(parts, { '---- answer file ----', entry.answer }) end
  vim.list_extend(parts, {
    ('---- result: exit=%s elapsed=%.2fs %s ----'):format(tostring(entry.code), entry.elapsed or 0, entry.outcome),
    '',
    '',
  })
  local f = io.open(M.today(), 'a')
  if not f then return end
  f:write(table.concat(parts, '\n'))
  f:close()
end

--- Open the most recent log at its end.
function M.open()
  local files = vim.fn.glob(vim.fs.joinpath(M.dir(), '*.log'), false, true)
  table.sort(files)
  local path = files[#files]
  if not path then return vim.notify('NES: no log yet (' .. M.dir() .. ')') end
  vim.cmd('botright split ' .. vim.fn.fnameescape(path))
  vim.bo.readonly = true
  vim.bo.autoread = true
  vim.cmd 'normal! G'
end

return M
