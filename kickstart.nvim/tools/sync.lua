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
  say 'done'
  vim.cmd 'qa!'
end

-- `-c` runs before VimEnter, but some installers (mason-tool-installer) start on VimEnter.
if vim.v.vim_did_enter == 1 then
  main()
else
  vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function() vim.schedule(main) end })
end
