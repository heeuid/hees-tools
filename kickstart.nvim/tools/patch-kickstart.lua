-- Turn on the kickstart.nvim options this setup relies on. Shared by install.ps1/install.sh and
-- update.ps1/update.sh so both platforms patch the same way.
--
--   nvim -l patch-kickstart.lua <config-dir> [--nerd-font]   apply (idempotent)
--   nvim -l patch-kickstart.lua <config-dir> --check         exit 0 if the patched files differ from
--                                                            upstream HEAD only by these patches
--
-- Only kickstart's own features are switched on; nothing is rewritten:
--   init.lua                    require kickstart.plugins.debug / .neo-tree and custom.plugins,
--                               optionally vim.g.have_nerd_font = true
--   lua/kickstart/plugins/debug.lua
--                               add codelldb (C/C++/Rust) and python (debugpy) to ensure_installed,
--                               uncomment the breakpoint icon block

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

---@type table<string, fun(text: string): string>
local patches = {
  ['init.lua'] = function(text)
    for _, line in ipairs { "require 'kickstart.plugins.debug'", "require 'kickstart.plugins.neo-tree'", "require 'custom.plugins'" } do
      text = uncomment_line(text, line)
    end
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
os.exit(status)
