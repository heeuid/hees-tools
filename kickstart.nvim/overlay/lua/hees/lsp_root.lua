-- Never use the home folder as a language server's workspace root.
--
-- Servers pick their root from marker files (root_markers). A stray marker in the home folder,
-- e.g. ~/.luarc.json written by lua_ls's "Increase upper limit" prompt, wins over a project's
-- .git (lua_ls looks for .luarc.json first), and the server then indexes the whole home folder:
-- slow, memory hungry, and lua_ls stops at its 10000-file preload limit with a prompt.
--
-- For every enabled server that finds its root by markers, the root is still found the same way;
-- only when that comes out as the home folder, the markers are searched again up to (not
-- including) home, level by level in the server's own priority order. With no marker below
-- home, the file's own folder is the root; a file directly in home gets no server.

local M = {}

local function key(path)
  if not path then return nil end
  path = vim.fs.normalize(path)
  return vim.fn.has 'win32' == 1 and path:lower() or path
end

function M.home() return vim.fs.normalize(vim.uv.os_homedir()) end

--- root_dir function for a server with these root_markers.
---@param markers (string|string[])[]
function M.guard(markers)
  -- Nested lists are priority levels; a flat list is one level.
  local nested = vim.iter(markers):any(function(m) return type(m) == 'table' end)
  local levels = nested and vim.tbl_map(function(m) return type(m) == 'table' and m or { m } end, markers) or { markers }
  return function(bufnr, on_dir)
    local home = M.home()
    local root = vim.fs.root(bufnr, markers)
    if key(root) ~= key(home) then return on_dir(root) end
    local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
    if key(dir) == key(home) then return end -- a file directly in home: no server
    for _, level in ipairs(levels) do
      local hit = vim.fs.find(level, { upward = true, path = dir, stop = home, limit = 1 })[1]
      if hit then return on_dir(vim.fs.dirname(hit)) end
    end
    on_dir(dir)
  end
end

--- Guard every enabled server that has root_markers and no root_dir of its own.
---@return string[] names of the guarded servers
function M.setup()
  local guarded = {}
  for _, config in ipairs(vim.lsp.get_configs { enabled = true }) do
    if config.name and config.root_markers and not config.root_dir then
      vim.lsp.config(config.name, { root_dir = M.guard(config.root_markers) })
      table.insert(guarded, config.name)
    end
  end
  return guarded
end

M.setup()

return M
