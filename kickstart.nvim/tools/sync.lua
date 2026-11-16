-- Run inside the configured Neovim to finish (or update) everything the config installs:
--   nvim --headless -c "luafile tools/sync.lua"            install mode: wait for first-run installs
--   HEES_SYNC=update nvim --headless -c "luafile …"        update mode: also update plugins, tools, parsers
--
-- vim.pack installs plugins synchronously during startup, but mason (LSP servers, formatters,
-- debug adapters) and nvim-treesitter (parsers) work asynchronously; quitting early aborts them.
-- Optional HEES_SYNC_PLUGINS="name1,name2" limits `vim.pack.update` to those plugins.

local mode = vim.env.HEES_SYNC or 'install'
local timeout = 20 * 60 * 1000

local function say(msg) io.stdout:write('[sync] ' .. msg .. '\n') end

local function mason_busy()
  local ok, registry = pcall(require, 'mason-registry')
  if not ok then return false end
  for _, pkg in ipairs(registry.get_all_packages()) do
    if pkg:is_installing() then return true end
  end
  return false
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

  -- Give deferred installers (mason-tool-installer, mason-nvim-dap) a moment to start, then wait.
  vim.wait(3000)
  if mason_busy() then say 'waiting for mason installs…' end
  if not vim.wait(timeout, function() return not mason_busy() end, 1000) then say 'mason is still busy after 20 minutes; giving up' end
  report()
  say 'done'
  vim.cmd 'qa!'
end

-- `-c` runs before VimEnter, but some installers (mason-tool-installer) start on VimEnter.
if vim.v.vim_did_enter == 1 then
  main()
else
  vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function() vim.schedule(main) end })
end
