-- How to run each AI CLI non-interactively with the prompt on stdin, with tools disabled
-- and nothing persisted, so a suggestion request can't touch the workspace.

local util = require 'hees.util'

local M = {}

M.names = { 'claude', 'codex', 'gemini' }

--- Model used when none is set with `:Nes model`. NES has to be fast, so Claude defaults to
--- its small model; the others use their CLI default.
M.default_models = { claude = 'haiku' }

--- Output that means the CLI is waiting for an interactive sign-in (seen from gemini when logged out).
M.login_prompt_pattern = '[Aa]uthentication page'

--- On Windows, npm installs `.cmd` wrappers. Running them needs `cmd /c`, whose quoting differs
--- from what libuv produces, so read the wrapper and run the program it points at instead.
---@param exe string
---@return string[]? argv prefix
local function unwrap_cmd_shim(exe)
  local f = io.open(exe, 'r')
  if not f then return nil end
  local text = f:read '*a'
  f:close()
  local dir = vim.fs.dirname(exe)
  local target
  for path in text:gmatch '"%%dp0%%\\([^"]+)"' do
    if path:match '%.exe$' or path:match '%.[cm]?js$' then target = path end
  end
  if not target then return nil end
  target = vim.fs.joinpath(dir, (target:gsub('\\', '/')))
  if target:match '%.exe$' then return { target } end
  local node = vim.fn.filereadable(vim.fs.joinpath(dir, 'node.exe')) == 1 and vim.fs.joinpath(dir, 'node.exe') or vim.fn.exepath 'node'
  if node == '' then return nil end
  return { node, target }
end

--- Resolve the argv prefix that starts `name`, or nil if it isn't installed.
---@param name string
---@return string[]?
function M.resolve(name)
  if util.is_win then
    -- npm also drops an extensionless sh script next to the .cmd; exepath(name) may return that.
    for _, ext in ipairs { '.exe', '.cmd', '.bat' } do
      local exe = vim.fn.exepath(name .. ext)
      if exe ~= '' then
        if ext == '.exe' then return { exe } end
        return unwrap_cmd_shim(exe) or { 'cmd.exe', '/d', '/c', exe }
      end
    end
    return nil
  end
  local exe = vim.fn.exepath(name)
  if exe == '' then return nil end
  return { exe }
end

function M.available(name) return M.resolve(name) ~= nil end

---@class hees.nes.Invocation
---@field argv string[]
---@field stdin string
---@field output_file string? where the answer is written instead of stdout

--- Build the command for one request.
---@param name string backend name
---@param model string? model override
---@param prompt string full prompt
---@return hees.nes.Invocation? invocation, string? error
function M.build(name, model, prompt)
  local prefix = M.resolve(name)
  if not prefix then return nil, name .. ' CLI not found on PATH' end
  local argv = vim.deepcopy(prefix)
  local inv = { argv = argv, stdin = prompt }
  if name == 'claude' then
    vim.list_extend(argv, { '-p', '--output-format', 'text', '--tools', '', '--no-session-persistence' })
    if model then vim.list_extend(argv, { '--model', model }) end
  elseif name == 'codex' then
    inv.output_file = vim.fn.tempname() .. '-codex.txt'
    vim.list_extend(argv, { 'exec', '--skip-git-repo-check', '--ephemeral', '-s', 'read-only', '--color', 'never', '-o', inv.output_file })
    if model then vim.list_extend(argv, { '-m', model }) end
    table.insert(argv, '-')
  elseif name == 'gemini' then
    -- Gemini puts stdin in front of the -p text, so the instructions go on stdin and -p only asks for the answer.
    vim.list_extend(argv, { '-p', 'Answer with the JSON object only.', '-o', 'text', '--approval-mode', 'plan' })
    if model then vim.list_extend(argv, { '-m', model }) end
  else
    return nil, 'unknown backend: ' .. name
  end
  return inv
end

return M
