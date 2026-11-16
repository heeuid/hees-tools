-- Turn on the kickstart.nvim options this setup relies on. Shared by install.ps1/install.sh and
-- update.ps1/update.sh so both platforms patch the same way.
--
--   nvim -l patch-kickstart.lua <config-dir> [--nerd-font]   apply (idempotent)
--   nvim -l patch-kickstart.lua <config-dir> --check         exit 0 if the patched files differ from
--                                                            upstream HEAD only by these patches
--
-- Only kickstart's own features are switched on; nothing is rewritten:
--   init.lua                    require kickstart.plugins.debug / .neo-tree and custom.plugins,
--                               LSP servers in kickstart's `servers` table (see LSP below),
--                               optionally vim.g.have_nerd_font = true
--   lua/kickstart/plugins/debug.lua
--                               add codelldb (C/C++/Rust) and python (debugpy) to ensure_installed,
--                               uncomment the breakpoint icon block
-- After applying, it prints what is turned on.

-- Language servers turned on in kickstart's `servers` table; mason installs them on first start.
-- kickstart ships clangd, pyright and rust_analyzer as commented examples (uncommented here); the
-- others are added to the same table. lua_ls is already on in kickstart.
local LSP = {
  { 'clangd', 'C/C++' },
  { 'rust_analyzer', 'Rust' },
  { 'pyright', 'Python' },
  { 'marksman', 'Markdown' },
  { 'taplo', 'TOML' },
  { 'jsonls', 'JSON' },
  { 'yamlls', 'YAML' },
  { 'bashls', 'Bash/sh' },
}

local args = _G.arg
local dir = args[1]
if not dir or dir == '' then
  io.stderr:write 'usage: nvim -l patch-kickstart.lua <config-dir> [--nerd-font|--check]\n'
  os.exit(2)
end
local opts = {}
for i = 2, #args do
  opts[args[i]:gsub('^%-%-', '')] = true
end

local function uncomment_line(text, line)
  local commented = '%-%- ' .. vim.pesc(line)
  return (text:gsub('\n(%s*)' .. commented .. '\n', function(indent) return '\n' .. indent .. line .. '\n' end))
end

--- Uncomment `-- name = {},` in the servers table, or add `name = {},` right after `local servers = {`.
local function enable_servers(text)
  local _, open = text:find '\n%s*local servers = {\n'
  if not open then return text end
  local close = text:find('\n  }\n', open, true) or #text
  local at = open -- added lines go in LSP order, right after `local servers = {`
  for _, server in ipairs(LSP) do
    local name, lang = server[1], server[2]
    local commented = '\n(%s*)%-%- ' .. name .. ' = {},'
    local body = text:sub(open, close)
    if body:find(commented) then
      text = text:sub(1, open - 1) .. body:gsub(commented, '\n%1' .. name .. ' = {},', 1) .. text:sub(close + 1)
    elseif not body:find('\n%s*' .. name .. ' = {') then
      local line = ('    %s = {}, -- %s (hees-tools)\n'):format(name, lang)
      text = text:sub(1, at) .. line .. text:sub(at + 1)
      at = at + #line
      close = close + #line
    end
  end
  return text
end

---@type table<string, fun(text: string): string>
local patches = {
  ['init.lua'] = function(text)
    for _, line in ipairs { "require 'kickstart.plugins.debug'", "require 'kickstart.plugins.neo-tree'", "require 'custom.plugins'" } do
      text = uncomment_line(text, line)
    end
    text = enable_servers(text)
    if opts['nerd-font'] then text = text:gsub('vim%.g%.have_nerd_font = false', 'vim.g.have_nerd_font = true', 1) end
    return text
  end,
  ['lua/kickstart/plugins/debug.lua'] = function(text)
    if not text:find("'codelldb'", 1, true) then
      text = text:gsub("\n(%s*)'delve',\n", function(indent) return ("\n%s'delve',\n%s'codelldb',\n%s'python',\n"):format(indent, indent, indent) end, 1)
    end
    -- Uncomment the block that starts at "-- Change breakpoint icons" and runs to the next blank line.
    text = text:gsub('(%-%- Change breakpoint icons\n)(.-)\n\n', function(head, block)
      local lines = vim.split(block, '\n', { plain = true })
      for i, l in ipairs(lines) do
        lines[i] = l:gsub('^%-%- ?', '', 1)
      end
      return head .. table.concat(lines, '\n') .. '\n\n'
    end, 1)
    return text
  end,
}

local function read(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local s = f:read '*a'
  f:close()
  return s
end

local function check_markers(rel, text)
  -- Report upstream changes that make a patch silently do nothing.
  local expect = {
    ['init.lua'] = { "\n  require 'kickstart.plugins.debug'", "\n  require 'kickstart.plugins.neo-tree'", "\n  require 'custom.plugins'" },
    ['lua/kickstart/plugins/debug.lua'] = { "'codelldb'", '\nfor type, icon in pairs(breakpoint_icons) do' },
  }
  for _, server in ipairs(LSP) do
    table.insert(expect['init.lua'], '\n    ' .. server[1] .. ' = {},')
  end
  for _, needle in ipairs(expect[rel]) do
    if not text:find(needle, 1, true) then io.stderr:write(('warning: %s: patch did not apply (%s); upstream may have changed\n'):format(rel, vim.trim(needle))) end
  end
end

local status = 0
for rel, patch in pairs(patches) do
  local path = vim.fs.joinpath(dir, rel)
  local current = read(path)
  if not current then
    io.stderr:write('missing ' .. path .. '\n')
    os.exit(1)
  end
  if opts.check then
    local res = vim.system({ 'git', '-C', dir, 'show', 'HEAD:' .. rel }, { text = false }):wait()
    if res.code ~= 0 then
      io.stderr:write('git show failed for ' .. rel .. '\n')
      os.exit(1)
    end
    local upstream = res.stdout
    -- Either nerd-font setting is acceptable as "ours".
    local ok = current == upstream or current == patch(upstream)
    if not ok then
      opts['nerd-font'] = not opts['nerd-font']
      ok = current == patch(upstream)
      opts['nerd-font'] = not opts['nerd-font']
    end
    if not ok then
      io.stdout:write(rel .. ' has local changes beyond this setup\'s patches\n')
      status = 1
    end
  else
    local patched = patch(current)
    check_markers(rel, patched)
    if patched ~= current then
      local f = assert(io.open(path, 'wb'))
      f:write(patched)
      f:close()
      io.stdout:write('patched ' .. rel .. '\n')
    end
  end
end

if not opts.check then
  local langs = {}
  for _, server in ipairs(LSP) do
    table.insert(langs, ('%s(%s)'):format(server[2], server[1]))
  end
  local init = read(vim.fs.joinpath(dir, 'init.lua')) or ''
  local summary = {
    '켠 kickstart 기능:',
    '  탐색기       kickstart.plugins.neo-tree (\\ 키)',
    '  디버거       kickstart.plugins.debug + DAP 어댑터 delve(Go), codelldb(C/C++/Rust), debugpy(Python), 중단점 아이콘',
    '  내 설정 폴더 custom.plugins (lua/custom/plugins/*.lua)',
    '  LSP          Lua(lua_ls, kickstart 기본), ' .. table.concat(langs, ', '),
    '  Nerd Font    ' .. (init:find('vim.g.have_nerd_font = true', 1, true) and '켬' or '끔 (-NerdFont / --nerd-font 로 켬)'),
    'LSP 서버와 디버거는 처음 실행할 때 mason 이 설치합니다.',
  }
  io.stdout:write(table.concat(summary, '\n') .. '\n')
end
os.exit(status)
