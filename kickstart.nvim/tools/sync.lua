-- Run inside the configured Neovim to finish (or update) everything the config installs:
--   nvim --headless --cmd "luafile tools/sync.lua"            install mode: wait for first-run installs
--   HEES_SYNC=update nvim --headless --cmd "luafile …"        update mode: also update plugins, tools, parsers
--
-- vim.pack installs plugins synchronously during startup, but mason (LSP servers, formatters,
-- debug adapters) and nvim-treesitter (parsers) work asynchronously; quitting early aborts them.
-- Optional HEES_SYNC_PLUGINS="name1,name2" limits `vim.pack.update` to those plugins.
--
-- Loaded with --cmd (before init.lua) so that messages printed while the config loads go through
-- the line-based output below; headless Neovim would otherwise run them together on one line.

local mode = vim.env.HEES_SYNC or 'install'
local timeout = 20 * 60 * 1000

local function say(msg) io.stdout:write('[sync] ' .. msg .. '\n') end

-- One line per message: notifications (mason, mason-tool-installer, mason-nvim-dap) and
-- echo/progress messages (vim.pack, nvim-treesitter). Headless Neovim's own output is replaced,
-- not added to, so nothing is printed twice.
local last_line
local function line(text)
  text = text:gsub('\n+$', '')
  if text == '' or text == last_line then return end
  last_line = text
  io.stdout:write(text .. '\n')
end
vim.notify = function(msg) line(tostring(msg)) end
vim.api.nvim_echo = function(chunks, _, opts)
  local text = table.concat(vim.tbl_map(function(c) return c[1] end, chunks))
  if opts and opts.kind == 'progress' then
    text = (opts.title and (opts.title .. ': ') or '') .. (opts.percent and ('%3d%% '):format(opts.percent) or '') .. text
  end
  line(text)
  return -1
end

--- Names of mason packages that are installing right now.
local function mason_installing()
  local ok, registry = pcall(require, 'mason-registry')
  if not ok then return {} end
  local names = {}
  for _, pkg in ipairs(registry.get_all_packages()) do
    if pkg:is_installing() then table.insert(names, pkg.name) end
  end
  table.sort(names)
  return names
end

--- The parsers kickstart installs (`local parsers = { ... }` in its init.lua).
local function kickstart_parsers()
  local f = io.open(vim.fs.joinpath(vim.fn.stdpath 'config', 'init.lua'), 'r')
  if not f then return {} end
  local list = f:read('*a'):match 'local parsers = (%b{})'
  f:close()
  local names = {}
  for name in (list or ''):gmatch "'([%w_]+)'" do
    table.insert(names, name)
  end
  return names
end

local function have_c_compiler()
  for _, cc in ipairs { 'cc', 'gcc', 'clang', 'cl', 'zig' } do
    if vim.fn.executable(cc) == 1 then return true end
  end
  return false
end

--- Wait for kickstart's parser installs to finish (they run asynchronously at startup).
local function wait_parsers()
  local ok, ts = pcall(require, 'nvim-treesitter')
  local parsers = kickstart_parsers()
  if not ok or #parsers == 0 then return end
  if vim.fn.executable 'tree-sitter' == 0 then
    say 'tree-sitter CLI 가 없어 treesitter 파서를 설치할 수 없습니다 (설치 스크립트가 설치합니다).'
    return
  end
  if not have_c_compiler() then
    say 'C 컴파일러(gcc/clang)가 없어 treesitter 파서를 컴파일할 수 없습니다. Linux: sudo apt install build-essential'
    return
  end
  say('treesitter 파서 설치 확인: ' .. table.concat(parsers, ', '))
  pcall(function() ts.install(parsers):wait(timeout) end)
end

--- What is actually on in this config, read from the running Neovim.
local function report()
  say '─── 결과 ───'
  say('색상 테마      ' .. (vim.g.colors_name or '(기본)'))
  say('내 플러그인    ' .. (vim.g.loaded_hees and '켜짐 (우클릭 메뉴, 클릭 탭/거터, NES)' or '없음'))
  local plugins = vim.tbl_map(function(p) return p.spec.name end, vim.pack.get(nil, { info = false }))
  table.sort(plugins)
  say(('플러그인 %d개  %s'):format(#plugins, table.concat(plugins, ', ')))

  local configs = vim.lsp.get_configs { enabled = true }
  table.sort(configs, function(a, b) return a.name < b.name end)
  say(('LSP %d개 켜짐'):format(#configs))
  local missing = 0
  for _, c in ipairs(configs) do
    local cmd = type(c.cmd) == 'table' and c.cmd[1] or nil
    local ok = cmd == nil or vim.fn.executable(cmd) == 1
    if not ok then missing = missing + 1 end
    say(('  %-15s %-34s %s'):format(c.name, table.concat(c.filetypes or {}, ','), ok and '설치됨' or '설치 안 됨'))
  end
  local has_registry, registry = pcall(require, 'mason-registry')
  if has_registry then
    local names = registry.get_installed_package_names()
    table.sort(names)
    say(('mason 도구 %d개  %s'):format(#names, table.concat(names, ', ')))
  end
  if missing > 0 then say(('설치 안 된 LSP %d개: 네트워크를 확인하고 다시 실행하거나 :Mason 에서 확인하세요'):format(missing)) end

  local has_ts, ts = pcall(require, 'nvim-treesitter')
  local wanted = kickstart_parsers()
  if has_ts and #wanted > 0 then
    local installed = {}
    for _, name in ipairs(ts.get_installed 'parsers') do
      installed[name] = true
    end
    local absent = vim.tbl_filter(function(name) return not installed[name] end, wanted)
    say(('treesitter 파서 %d/%d개 설치됨%s'):format(#wanted - #absent, #wanted, #absent > 0 and ('  없음: ' .. table.concat(absent, ', ')) or ''))
    local cli = vim.fn.exepath 'tree-sitter'
    say('tree-sitter CLI  ' .. (cli ~= '' and cli or '없음 — 파서를 설치할 수 없어 문법 색칠이 동작하지 않습니다'))
  end
end

local function main()
  if mode == 'update' then
    local names
    if vim.env.HEES_SYNC_PLUGINS and vim.env.HEES_SYNC_PLUGINS ~= '' then names = vim.split(vim.env.HEES_SYNC_PLUGINS, ',', { trimempty = true }) end
    say('updating plugins: ' .. (names and table.concat(names, ', ') or 'all'))
    vim.pack.update(names, { force = true })
    if not names then
      local ok, ts = pcall(require, 'nvim-treesitter')
      if ok then
        say 'updating treesitter parsers'
        pcall(function() ts.update():wait(timeout) end)
      end
      if vim.fn.exists ':MasonToolsUpdateSync' == 2 then
        say 'updating mason tools'
        vim.cmd 'MasonToolsUpdateSync'
      end
    end
  end

  -- Give deferred installers (mason-tool-installer, mason-nvim-dap) a moment to start, then wait,
  -- saying every 15 s what is still being downloaded so a long install doesn't look stuck.
  vim.wait(3000)
  local started, last = vim.uv.now(), nil
  local finished = vim.wait(timeout, function()
    local busy = mason_installing()
    if #busy == 0 then return true end
    local now = vim.uv.now()
    if not last or now - last >= 15000 then
      last = now
      say(('설치 중 %d개 (%d초 경과): %s'):format(#busy, (now - started) / 1000, table.concat(busy, ', ')))
    end
    return false
  end, 1000)
  if not finished then say '20분이 지나도 mason 설치가 끝나지 않아 중단합니다. 다시 실행하면 이어서 설치합니다.' end
  wait_parsers()
  report()
  say 'done'
  vim.cmd 'qa!'
end

-- --cmd runs before the config and VimEnter; some installers (mason-tool-installer) start on VimEnter.
if vim.v.vim_did_enter == 1 then
  main()
else
  vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function() vim.schedule(main) end })
end
