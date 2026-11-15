-- Headless smoke test for the overlay. Run against an installed config:
--   NVIM_APPNAME=<app> nvim --headless -c "luafile tests/smoke.lua"
-- Prints one line per check and exits non-zero if any failed. Uses a temporary data dir.

vim.env.HEES_NVIM_DATA = vim.fn.tempname()

local failures, count = 0, 0
local function check(name, cond, detail)
  count = count + 1
  if cond then
    io.stdout:write('ok    ' .. name .. '\n')
  else
    failures = failures + 1
    io.stdout:write('FAIL  ' .. name .. (detail and ('  -- ' .. tostring(detail)) or '') .. '\n')
  end
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'x', false)
end

local function run()
  -- [[ Loading and keymaps ]]
  for _, mod in ipairs { 'hees.ui', 'hees.nes', 'hees.context', 'hees.menu', 'bufferline', 'statuscol', 'neo-tree', 'dap' } do
    check('module loaded: ' .. mod, package.loaded[mod] ~= nil)
  end
  local function has_map(mode, lhs) return vim.fn.maparg(lhs, mode) ~= '' end
  check('map n <RightMouse>', has_map('n', '<RightMouse>'))
  check('map x <RightMouse>', has_map('x', '<RightMouse>'))
  check('map n <leader>m', has_map('n', '<Space>m'))
  check('map n <leader>an', has_map('n', '<Space>an'))
  check('map n <leader>aa', has_map('n', '<Space>aa'))
  check('no global <Tab> map', not has_map('n', '<Tab>'))
  check('kickstart <leader>b kept', vim.fn.maparg('<Space>b', 'n', false, true).desc == 'Debug: Toggle Breakpoint')
  check('kickstart \\ (neo-tree) kept', vim.fn.maparg('\\', 'n', false, true).desc == 'NeoTree reveal')
  check(':Nes command', vim.fn.exists ':Nes' == 2)

  -- [[ Menu engine ]]
  local menu = require 'hees.menu'
  local hit
  local items = {
    { label = 'Alpha', action = function() hit = 'alpha' end },
    { label = 'Sub', items = { { label = 'Deep', items = { { label = 'Leaf', action = function() hit = 'leaf' end } } } } },
    { label = 'Off', enabled = false, action = function() hit = 'off' end },
    { sep = true },
    { label = 'Keys', action = 'ix<Esc>' },
  }
  local origin = vim.api.nvim_get_current_win()
  menu.open(items, { row = 2, col = 2 })
  check('menu opens and takes focus', menu.is_open() and vim.api.nvim_get_current_win() ~= origin)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  check('menu renders 5 lines', #lines == 5, #lines)
  check('submenu arrow shown', lines[2]:find(require('hees.util').icons().submenu, 1, true) ~= nil, lines[2])
  feed 'j'
  check('j moves to Sub', vim.api.nvim_win_get_cursor(0)[1] == 2)
  feed 'j'
  check('j skips disabled item and separator', vim.api.nvim_win_get_cursor(0)[1] == 5, vim.api.nvim_win_get_cursor(0)[1])
  feed 'k'
  feed '<CR>'
  feed '<CR>'
  local depth3 = #vim.tbl_filter(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'hees-menu' end, vim.api.nvim_list_wins())
  check('Enter opens nested submenus (3 levels)', depth3 == 3, depth3)
  feed 'h'
  local depth2 = #vim.tbl_filter(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'hees-menu' end, vim.api.nvim_list_wins())
  check('h closes one level', depth2 == 2, depth2)
  feed 'l'
  feed '<CR>'
  vim.wait(200, function() return hit ~= nil end)
  check('leaf action runs and menu closes', hit == 'leaf' and not menu.is_open(), hit)
  check('focus returns to origin window', vim.api.nvim_get_current_win() == origin)
  menu.open(items, { row = 2, col = 2 })
  feed '<Esc>'
  check('Esc closes menu', not menu.is_open())

  -- [[ Context menus ]]
  local file = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ 'local count = 1', 'local function add(a, b)', '  return a + b', 'end', 'print(count)' }, file)
  vim.cmd('edit ' .. vim.fn.fnameescape(file))
  local buf = vim.api.nvim_get_current_buf()
  local ctx = require 'hees.context'
  local top = ctx._buffer_items(false)
  local labels = vim.tbl_map(function(it) return it.label or '---' end, top)
  check('buffer menu has LSP/Debug/AI/Git/Search groups', vim.tbl_contains(labels, 'LSP') and vim.tbl_contains(labels, 'Debug') and vim.tbl_contains(labels, 'AI next edit'), table.concat(labels, ', '))
  check('buffer menu top level is short (<= 14 rows)', #top <= 14, #top)
  ctx.open_at_cursor(false)
  check('context menu opens from keyboard', menu.is_open())
  local rendered = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  menu.close()
  check('context menu rendered rows', #rendered == #top, #rendered .. ' vs ' .. #top)
  local vis = ctx._buffer_items(true)
  check('visual menu starts with Cut/Copy', vis[1].label == 'Cut' and vis[2].label == 'Copy')
  local tab = ctx._tab_items(buf)
  check('tab menu has Close others', tab[2].label == 'Close others')

  vim.cmd 'Neotree show'
  vim.wait(1500, function() return #vim.tbl_filter(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'neo-tree' end, vim.api.nvim_list_wins()) > 0 end)
  local tree_win
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'neo-tree' then tree_win = w end
  end
  check('neo-tree window open', tree_win ~= nil)
  if tree_win then
    vim.wait(3000, function() return ctx._neo_tree_state(tree_win) ~= nil end)
    vim.api.nvim_set_current_win(tree_win)
    local st = ctx._neo_tree_state(tree_win)
    check('neo-tree state found for window', st ~= nil)
    local ex = st and ctx._explorer_items(st) or {}
    check('explorer menu built for node', #ex > 5, #ex)
    local fs = require 'neo-tree.sources.filesystem.commands'
    local missing = {}
    for _, name in ipairs { 'open', 'open_vsplit', 'open_split', 'open_tabnew', 'add', 'add_directory', 'rename', 'delete', 'copy_to_clipboard', 'cut_to_clipboard', 'paste_from_clipboard', 'toggle_hidden', 'refresh' } do
      if type(fs[name]) ~= 'function' then table.insert(missing, name) end
    end
    check('neo-tree commands used by the menu exist', #missing == 0, table.concat(missing, ','))
    vim.cmd 'Neotree close'
  end
  vim.api.nvim_set_current_buf(buf)

  -- [[ NES ]]
  local nes = require 'hees.nes'
  nes._capture(buf)
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'local total = 1' })
  nes._capture(buf)
  check('edit history recorded', #nes._tracked[buf].history == 1)
  local req = { buf = buf, first = 1, last = 5, line_count = 5, lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false), cursor = { 1, 0 }, path = 'x.lua', filetype = 'lua' }
  local prompt = nes._build_prompt(req)
  check('prompt has numbered code and diff', prompt:find('5| print(count)', 1, true) and prompt:find('+local total = 1', 1, true), prompt)
  local edits, err = nes.parse('```json\n{"edits":[{"start_line":5,"end_line":5,"replacement":"print(total)"},{"start_line":3,"end_line":2,"replacement":"  -- sum"}],"reason":"rename"}\n```', req)
  check('parse: fenced JSON accepted, out-of-order edit dropped', edits and #edits == 1, err or (edits and #edits))
  edits = nes.parse('{"edits":[{"start_line":3,"end_line":2,"replacement":"  -- sum"},{"start_line":5,"end_line":5,"replacement":"print(total)"}]}', req)
  check('parse: insert + replace', edits and #edits == 2 and edits[1].insert and not edits[2].insert)
  check('parse: rejects out-of-window', #nes.parse('{"edits":[{"start_line":9,"end_line":9,"replacement":"x"}]}', req) == 0)
  check('parse: rejects no-op', #nes.parse('{"edits":[{"start_line":5,"end_line":5,"replacement":"print(count)"}]}', req) == 0)
  check('parse: error on prose', select(2, nes.parse('no edits here', req)) ~= nil)

  -- Display + apply through the same path a real answer takes.
  local show_edits = nes.parse('{"edits":[{"start_line":3,"end_line":2,"replacement":"  -- sum"},{"start_line":5,"end_line":5,"replacement":"print(total)"}]}', req)
  -- Feed a fake CLI result through the same completion path a real request takes.
  local shown = nes._finish
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  shown(vim.tbl_extend('force', req, { id = 1, backend = 'test', cwd = '.', argv = { 'test' }, prompt = 'p', started = vim.uv.hrtime() }), {
    code = 0,
    signal = 0,
    stdout = '{"edits":[{"start_line":3,"end_line":2,"replacement":"  -- sum"},{"start_line":5,"end_line":5,"replacement":"print(total)"}]}',
    stderr = '',
  })
  check('suggestions shown', nes.has_suggestions())
  check('suggestion count', show_edits and #show_edits == 2)
  local view_ns = vim.api.nvim_get_namespaces()['hees.nes.view']
  check('inline diff extmarks drawn', #vim.api.nvim_buf_get_extmarks(buf, view_ns, 0, -1, {}) > 0)
  nes.accept()
  check('first accept jumps to suggestion', vim.api.nvim_win_get_cursor(0)[1] == 3, vim.api.nvim_win_get_cursor(0)[1])
  nes.accept()
  local after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  check('second accept inserts line', after[3] == '  -- sum', vim.inspect(after))
  nes.accept()
  nes.accept()
  after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  check('next suggestion applied at shifted position', after[6] == 'print(total)', vim.inspect(after))
  check('no suggestions left', not nes.has_suggestions())

  -- Changed target lines are refused.
  req.lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  req.last, req.line_count = #req.lines, #req.lines
  shown(vim.tbl_extend('force', req, { id = 2, backend = 'test', cwd = '.', argv = { 'test' }, prompt = 'p', started = vim.uv.hrtime() }), {
    code = 0,
    signal = 0,
    stdout = '{"edits":[{"start_line":1,"end_line":1,"replacement":"local total = 2"}]}',
    stderr = '',
  })
  vim.api.nvim_buf_set_text(buf, 0, 0, 0, 0, { '-- ' })
  check('editing the buffer dismisses suggestions', (function()
    vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })
    return not nes.has_suggestions()
  end)())
  local logs = vim.fn.glob(vim.fs.joinpath(vim.env.HEES_NVIM_DATA, 'nes', 'logs', '*.log'), false, true)
  check('requests logged to data dir', #logs == 1, vim.inspect(logs))

  -- [[ Backends ]]
  local backends = require 'hees.nes.backends'
  for _, name in ipairs(backends.names) do
    local inv, berr = backends.build(name, nil, 'prompt')
    if inv then
      local runnable = vim.fn.executable(inv.argv[1]) == 1
      if vim.fn.has 'win32' == 1 then runnable = runnable and inv.argv[1]:lower():match '%.exe$' ~= nil end
      check('backend ' .. name .. ' resolves to a runnable program', runnable, inv.argv[1])
      io.stdout:write('      ' .. table.concat(inv.argv, ' ') .. '\n')
    else
      io.stdout:write('skip  backend ' .. name .. ': ' .. tostring(berr) .. '\n')
    end
  end
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  failures = failures + 1
  io.stdout:write('FAIL  error: ' .. err .. '\n')
end
io.stdout:write(('%d checks, %d failed\n'):format(count, failures))
vim.cmd(failures == 0 and 'qa!' or 'cq!')
