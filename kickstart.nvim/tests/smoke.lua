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
  for _, mod in ipairs { 'hees.colors', 'hees.ui', 'hees.nes', 'hees.ai', 'hees.ai.analyze', 'hees.ai.viewer', 'hees.context', 'hees.menu', 'catppuccin', 'bufferline', 'statuscol', 'neo-tree', 'dap', 'window-picker', 'aerial', 'hees.outline' } do
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
  check('colorscheme is catppuccin-latte', vim.g.colors_name == 'catppuccin-latte', vim.g.colors_name)
  check('background is light', vim.o.background == 'light')
  for _, server in ipairs { 'lua_ls', 'clangd', 'rust_analyzer', 'pyright', 'marksman', 'taplo', 'jsonls', 'yamlls', 'bashls' } do
    check('LSP enabled: ' .. server, vim.lsp.is_enabled(server))
  end

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
  check('buffer menu has LSP/Debug/AI/Git/Search groups', vim.tbl_contains(labels, 'LSP') and vim.tbl_contains(labels, 'Debug') and vim.tbl_contains(labels, 'AI'), table.concat(labels, ', '))
  check('buffer menu top level is short (<= 17 rows)', #top <= 17, #top)
  ctx.open_at_cursor(false)
  check('context menu opens from keyboard', menu.is_open())
  local rendered = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  menu.close()
  check('context menu rendered rows', #rendered == #top, #rendered .. ' vs ' .. #top)
  local vis = ctx._buffer_items(true)
  check('visual menu starts with Cut/Copy', vis[1].label == 'Cut' and vis[2].label == 'Copy')
  local tab = ctx._tab_items(buf)
  check('tab menu has Close others', tab[2].label == 'Close others')

  -- Window submenu: split from the menu, then close the others again.
  check('buffer menu has Window group', vim.tbl_contains(labels, 'Window'), table.concat(labels, ', '))
  local function editor_wins() return #vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == '' end, vim.api.nvim_tabpage_list_wins(0)) end
  local single = ctx._window_items()
  check('window menu: close items disabled with one window', single[7].enabled == false and single[8].enabled == false)
  local before = editor_wins()
  menu.open(ctx._window_items, { row = 2, col = 2 })
  feed '<CR>' -- Split right
  vim.wait(500, function() return editor_wins() == before + 1 end)
  check('window menu: Split right splits the window', editor_wins() == before + 1, editor_wins())
  menu.open(ctx._window_items, { row = 2, col = 2 })
  feed 'j'
  feed '<CR>' -- Split below
  vim.wait(500, function() return editor_wins() == before + 2 end)
  check('window menu: Split below splits the window', editor_wins() == before + 2, editor_wins())
  check('window menu: close items enabled with several windows', ctx._window_items()[8].enabled == true)
  menu.open(ctx._window_items, { row = 2, col = 2 })
  for _ = 1, 6 do
    feed 'j'
  end
  feed '<CR>' -- Close other windows
  vim.wait(500, function() return editor_wins() == 1 end)
  check('window menu: Close other windows leaves one', editor_wins() == 1, editor_wins())
  vim.api.nvim_set_current_buf(buf)

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
    local pick = vim.tbl_filter(function(it) return it.label == 'Open in' end, ex)[1]
    pick = pick and vim.tbl_filter(function(it) return it.label == 'Pick window…' end, pick.items)[1]
    check('explorer menu has Open in > Pick window (w)', pick ~= nil and pick.hint == 'w' and pick.enabled)
    local w_map = require('neo-tree').config.window.mappings['w']
    check('neo-tree w maps to open_with_window_picker', w_map == 'open_with_window_picker', vim.inspect(w_map))
    vim.cmd 'Neotree close'
  end
  vim.api.nvim_set_current_buf(buf)

  -- Explorer: hidden cursor in the tree, h/l collapse/expand/open.
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/sub', 'p')
    vim.fn.writefile({ 'hello' }, root .. '/sub/a.txt')
    local cwd = vim.fn.getcwd()
    vim.cmd.cd(root)
    vim.cmd 'Neotree show dir=. reveal=false'
    local tree
    vim.wait(3000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'neo-tree' then tree = w end
      end
      return tree ~= nil and vim.fn.search('sub', 'nw') > 0
    end)
    vim.api.nvim_set_current_win(tree)
    local tbuf = vim.api.nvim_get_current_buf()
    vim.wait(2000, function() return vim.fn.maparg('l', 'n', false, true).desc == 'Explorer: expand directory / open file' end)
    check('explorer: l/h mapped in the tree', vim.fn.maparg('l', 'n', false, true).desc == 'Explorer: expand directory / open file' and vim.fn.maparg('h', 'n', false, true).desc ~= nil)
    check('explorer: cursor hidden in the tree', vim.o.guicursor:find('n:HeesHiddenCursor', 1, true) ~= nil, vim.o.guicursor)
    local state = require('neo-tree.sources.manager').get_state_for_window()
    local function node() return state.tree:get_node() end
    vim.fn.search 'sub'
    check('explorer: on the sub directory', node() and node().name == 'sub', node() and node().name)
    feed 'l'
    vim.wait(2000, function() return node():is_expanded() end)
    check('explorer: l expands a directory', node():is_expanded())
    feed 'l'
    vim.wait(1000, function() return node().name == 'a.txt' end)
    check('explorer: l on an expanded directory steps into it', node().name == 'a.txt', node().name)
    feed 'h'
    vim.wait(2000, function() return node().name == 'sub' and not node():is_expanded() end)
    check('explorer: h on a file collapses the parent and moves to it', node().name == 'sub' and not node():is_expanded(), node().name)
    feed 'l'
    vim.wait(2000, function() return node():is_expanded() end)
    feed 'l'
    vim.wait(1000, function() return node().name == 'a.txt' end)
    feed 'l'
    vim.wait(2000, function() return vim.api.nvim_buf_get_name(0):find('a.txt', 1, true) ~= nil end)
    check('explorer: l on a file opens it in an editor window', vim.api.nvim_buf_get_name(0):find('a.txt', 1, true) ~= nil and vim.bo.filetype ~= 'neo-tree')
    check('explorer: cursor shown again outside the tree', vim.o.guicursor:find('HeesHiddenCursor', 1, true) == nil, vim.o.guicursor)
    -- Using the right-click menu inside the tree must not leave the cursor hidden everywhere.
    local editor_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(tree)
    ctx.open_at_cursor(false)
    feed '<Esc>'
    check('explorer: back in the tree after the menu, cursor hidden', vim.bo.filetype == 'neo-tree' and vim.o.guicursor:find('n:HeesHiddenCursor', 1, true) ~= nil, vim.o.guicursor)
    vim.api.nvim_set_current_win(editor_win)
    pcall(vim.api.nvim_exec_autocmds, 'SafeState', {})
    check('explorer: cursor shown in the editor after using the menu in the tree', vim.o.guicursor:find('HeesHiddenCursor', 1, true) == nil, vim.o.guicursor)
    if vim.api.nvim_buf_is_valid(tbuf) then vim.cmd 'Neotree close' end
    vim.cmd.cd(cwd)
    vim.api.nvim_set_current_buf(buf)
  end

  -- window-picker: with two other editor windows, a typed hint letter picks one of them.
  local here = vim.api.nvim_get_current_win()
  vim.cmd 'vsplit | split'
  vim.api.nvim_set_current_win(here)
  vim.api.nvim_feedkeys('F', 't', false)
  local picked = require('window-picker').pick_window()
  check('window-picker picks another window by letter', picked ~= nil and picked ~= here and vim.api.nvim_win_is_valid(picked), tostring(picked))
  vim.cmd 'only'

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
  shown(vim.tbl_extend('force', req, { backend = 'test', started = vim.uv.hrtime() }), {
    status = 'ok',
    elapsed = 0,
    text = '{"edits":[{"start_line":3,"end_line":2,"replacement":"  -- sum"},{"start_line":5,"end_line":5,"replacement":"print(total)"}]}',
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
  shown(vim.tbl_extend('force', req, { backend = 'test', started = vim.uv.hrtime() }), {
    status = 'ok',
    elapsed = 0,
    text = '{"edits":[{"start_line":1,"end_line":1,"replacement":"local total = 2"}]}',
  })
  vim.api.nvim_buf_set_text(buf, 0, 0, 0, 0, { '-- ' })
  check('editing the buffer dismisses suggestions', (function()
    vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })
    return not nes.has_suggestions()
  end)())

  -- [[ AI runner, request log, viewer ]]
  -- A stand-in "AI": Neovim running a script that echoes what it got on stdin.
  local echo_script = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ "local input = io.stdin:read('*a')", "io.stdout:write('ECHO ' .. #input .. ' bytes\\n' .. input:sub(1, 40))" }, echo_script)
  local echo_argv = { vim.v.progpath, '-l', echo_script }
  local ai_run, ai_log, viewer = require 'hees.ai.run', require 'hees.ai.log', require 'hees.ai.viewer'
  local finished
  local entry = ai_run.start({ kind = 'analyze', title = 'echo test', backend = 'test', prompt = 'hello prompt', argv = echo_argv }, function(e)
    finished = e
    e.outcome = 'echoed'
  end)
  check('ai run: entry is running while the command runs', entry and entry.status == 'running')
  vim.wait(10000, function() return finished ~= nil end)
  check('ai run: finishes with stdout and status ok', finished and finished.status == 'ok' and finished.text:find('ECHO 12 bytes', 1, true) ~= nil, finished and finished.text)
  local day = ai_log.file_for(os.time())
  local logged = vim.fn.filereadable(day) == 1 and vim.fn.readfile(day) or {}
  local record = #logged > 0 and vim.json.decode(logged[#logged]) or {}
  check('ai log: JSONL record has command, input, output, outcome', record.prompt == 'hello prompt' and record.argv and record.argv[1] == vim.v.progpath and record.stdout:find('ECHO', 1, true) and record.outcome == 'echoed', vim.inspect(record))
  check('ai log: all() lists it newest first', ai_log.all(1)[1].uid == record.uid)
  local detail = table.concat(viewer._detail_lines(record), '\n')
  check('viewer: record shows command, stdin and reply', detail:find('## Command', 1, true) and detail:find('hello prompt', 1, true) and detail:find('ECHO 12 bytes', 1, true), detail)
  viewer.open()
  local v = viewer._view()
  check('viewer: opens a tab with list and record', v and vim.api.nvim_get_current_tabpage() == v.tab and vim.api.nvim_buf_get_lines(v.list_buf, 1, 2, false)[1]:find('echo test', 1, true) ~= nil)
  local before_count = #v.entries
  local live_done
  ai_run.start({ kind = 'nes', title = 'live entry', backend = 'test', prompt = 'x', argv = echo_argv }, function() live_done = true end)
  vim.wait(300)
  check('viewer: a started request appears at once', #viewer._view().entries == before_count + 1 and vim.api.nvim_buf_get_lines(v.list_buf, 1, 2, false)[1]:find('live entry', 1, true) ~= nil)
  vim.wait(10000, function() return live_done end)
  vim.wait(300)
  check('viewer: it updates when the request finishes', vim.api.nvim_buf_get_lines(v.list_buf, 1, 2, false)[1]:find('✓', 1, true) ~= nil, vim.api.nvim_buf_get_lines(v.list_buf, 1, 2, false)[1])
  vim.cmd 'tabclose'
  check('viewer: closed with its tab', viewer._view() == nil or not vim.api.nvim_tabpage_is_valid(viewer._view().tab))

  -- [[ Analysis with LSP context ]]
  local lua_file = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({
    'local M = {}',
    '',
    '--- Sum of two numbers.',
    'local function add(a, b)',
    '  return a + b',
    'end',
    '',
    'function M.total(list)',
    '  local sum = 0',
    '  for _, n in ipairs(list) do',
    '    sum = add(sum, n)',
    '  end',
    '  return sum',
    'end',
    '',
    'return M',
  }, lua_file)
  vim.cmd('edit ' .. vim.fn.fnameescape(lua_file))
  local lbuf = vim.api.nvim_get_current_buf()
  vim.wait(20000, function() return #vim.lsp.get_clients { bufnr = lbuf, name = 'lua_ls' } > 0 end)
  check('lsp: lua_ls attached to a Lua file', #vim.lsp.get_clients { bufnr = lbuf, name = 'lua_ls' } > 0)
  -- lua_ls indexes the workspace first; wait until it answers document symbols.
  vim.wait(120000, function()
    local r = vim.lsp.buf_request_sync(lbuf, 'textDocument/documentSymbol', { textDocument = vim.lsp.util.make_text_document_params(lbuf) }, 2000) or {}
    for _, resp in pairs(r) do
      if resp.result and #resp.result > 0 then return true end
    end
    return false
  end, 500)
  vim.api.nvim_win_set_cursor(0, { 11, 12 }) -- on `add` inside M.total
  local lctx = require('hees.ai.lsp_context').collect(lbuf, 0, 1, 16)
  check('lsp context: server names', vim.tbl_contains(lctx.clients, 'lua_ls'), vim.inspect(lctx.clients))
  check('lsp context: enclosing function found', lctx.enclosing and lctx.enclosing.first == 8 and lctx.enclosing.last == 14, vim.inspect(lctx.enclosing))
  check('lsp context: definition of the symbol under the cursor', lctx.definition and lctx.definition.line == 4, vim.inspect(lctx.definition))
  check('lsp context: hover text', #lctx.hover > 0, vim.inspect(lctx.hover))
  check('lsp context: document outline', #lctx.outline >= 2, vim.inspect(lctx.outline))

  -- Outline sidebar (aerial) on the same file.
  local code_win = vim.api.nvim_get_current_win()
  require('aerial').open { focus = false }
  local aerial_buf
  vim.wait(5000, function()
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].filetype == 'aerial' and table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), '\n'):find('total', 1, true) then aerial_buf = b end
    end
    return aerial_buf ~= nil
  end, 100)
  local outline_text = aerial_buf and table.concat(vim.api.nvim_buf_get_lines(aerial_buf, 0, -1, false), '\n') or ''
  check('outline: aerial window lists functions and variables', outline_text:find('add', 1, true) and outline_text:find('total', 1, true) and outline_text:find('M', 1, true), outline_text)
  check('outline: <leader>o mapped', vim.fn.maparg('<Space>o', 'n') ~= '')
  require('aerial').close()
  vim.api.nvim_set_current_win(code_win)
  local structure = vim.tbl_filter(function(it) return it.label == 'Structure' end, ctx._buffer_items and (function()
    local lsp = vim.tbl_filter(function(it) return it.label == 'LSP' end, ctx._buffer_items(false))[1]
    return type(lsp.items) == 'function' and lsp.items() or lsp.items
  end)() or {})[1]
  local structure_labels = structure and vim.tbl_map(function(it) return it.label or '---' end, structure.items) or {}
  local items_now = vim.tbl_map(function(it) return it.label or '---' end, ctx._buffer_items(false))
  check('right double clicks open the same menu (not the built-in PopUp)', vim.fn.maparg('<2-RightMouse>', 'n') ~= '' and vim.fn.maparg('<2-RightMouse>', 'x') ~= '' and vim.fn.maparg('<3-RightMouse>', 'i') ~= '')
  check('editor menu: Go back / Go forward under Go to definition', vim.tbl_contains(items_now, 'Back from definition') and vim.tbl_contains(items_now, 'Go back') and vim.tbl_contains(items_now, 'Go forward') and vim.fn.maparg('<X1Mouse>', 'n') ~= '', table.concat(items_now, ' | '))
  check('LSP menu: Structure has outline, call and type hierarchy', vim.tbl_contains(structure_labels, 'Outline sidebar') and vim.tbl_contains(structure_labels, 'Call hierarchy') and vim.tbl_contains(structure_labels, 'Type hierarchy'), table.concat(structure_labels, ' | '))

  local analyze = require 'hees.ai.analyze'
  local real_build = require('hees.ai.backends').build
  require('hees.ai.backends').build = function(_, _, p) return { argv = echo_argv, stdin = p } end
  analyze.run 'review'
  vim.wait(15000, function() return not analyze.is_busy() end)
  require('hees.ai.backends').build = real_build
  local last = ai_log.all(1)[1]
  check('analyze: request logged as analyze with range of M.total', last.kind == 'analyze' and last.range and last.range[1] == 8 and last.range[2] == 14, vim.inspect(last.range))
  check('analyze: prompt has task, code and LSP sections', last.prompt:find('Review this code', 1, true) and last.prompt:find('11|     sum = add(sum, n)', 1, true) and last.prompt:find('## LSP hover at the cursor', 1, true) and last.prompt:find('## Definition of the symbol under the cursor', 1, true) and last.prompt:find('Answer in Korean', 1, true), last.prompt)
  local answer_buf
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.b[vim.api.nvim_win_get_buf(w)].hees_ai_conv then answer_buf = vim.api.nvim_win_get_buf(w) end
  end
  local answer_text = answer_buf and table.concat(vim.api.nvim_buf_get_lines(answer_buf, 0, -1, false), '\n') or ''
  check('analyze: answer window shows the reply', answer_text:find('ECHO', 1, true) ~= nil and answer_text:find('# Review', 1, true) ~= nil, answer_text)

  -- [[ Follow-up questions ]]
  local conversation = require 'hees.ai.conversation'
  check('follow-up: first request belongs to a conversation (turn 1)', last.conv ~= nil and last.turn == 1, vim.inspect { last.conv, last.turn })
  require('hees.ai.backends').build = function(_, _, p) return { argv = echo_argv, stdin = p } end
  conversation.follow_up(nil, 'total 이 빈 테이블이면?')
  vim.wait(15000, function() return not analyze.is_busy() end)
  local fu = ai_log.all(1)[1]
  check('follow-up: same conversation, turn 2, same task', fu.conv == last.conv and fu.turn == 2 and fu.task == 'review' and fu.question == 'total 이 빈 테이블이면?', vim.inspect { fu.conv, fu.turn, fu.task })
  check('follow-up: prompt resends code, answer so far and the question', fu.prompt:find('11|     sum = add(sum, n)', 1, true) and fu.prompt:find('## Conversation so far', 1, true) and fu.prompt:find('ECHO', 1, true) and fu.prompt:find('## Follow-up question\ntotal 이 빈 테이블이면?', 1, true), fu.prompt)
  answer_text = table.concat(vim.api.nvim_buf_get_lines(answer_buf, 0, -1, false), '\n')
  check('follow-up: answer window keeps Q1 and adds Q2', answer_text:find('## Q1: Review', 1, true) and answer_text:find('## Q2: total 이 빈 테이블이면?', 1, true), answer_text)
  check('follow-up: a in the answer window, <leader>af and <leader>aF mapped', #vim.tbl_filter(function(m) return m.lhs == 'a' end, vim.api.nvim_buf_get_keymap(answer_buf, 'n')) == 1 and vim.fn.maparg('<Space>af', 'n') ~= '' and vim.fn.maparg('<Space>aF', 'n') ~= '')
  -- Long conversations leave out the oldest answers.
  local conv_obj = conversation._get(last.conv)
  local keep_max = conversation.config.max_chars
  conversation.config.max_chars = #conv_obj.base_prompt + 20
  table.insert(conv_obj.turns, { question = 'x', status = 'running' })
  local short_prompt, dropped = conversation._followup_prompt(conv_obj, 'x')
  table.remove(conv_obj.turns)
  conversation.config.max_chars = keep_max
  check('follow-up: oldest answers left out when the prompt gets long', dropped >= 1 and short_prompt:find('earlier answer left out', 1, true) ~= nil, tostring(dropped))
  -- Rebuilt from the log (as in a later session).
  conversation._forget()
  check('follow-up: conversation rebuilt from the log', #conversation._get(last.conv).turns == 2 and conversation.last_id() == last.conv)
  local listed = vim.tbl_filter(function(c) return c.id == last.conv end, conversation.list())[1]
  check('conversations: listed once with 2 questions', listed and listed.count == 2 and listed.task == 'review', vim.inspect(listed))
  local viewer = require 'hees.ai.viewer'
  viewer.open { conversations = true }
  local vlines = vim.api.nvim_buf_get_lines(viewer._view().list_buf, 0, -1, false)
  check('conversations view: one row per conversation, transcript on the right', vlines[1]:find('AI conversations', 1, true) and table.concat(vim.api.nvim_buf_get_lines(viewer._view().detail_buf, 0, -1, false), '\n'):find('## Q2: total', 1, true), table.concat(vlines, '\n'))
  vim.api.nvim_feedkeys('g', 'x', false)
  check('log viewer: g switches back to requests', vim.api.nvim_buf_get_lines(viewer._view().list_buf, 0, 1, false)[1]:find('AI requests', 1, true) ~= nil)
  vim.cmd 'tabclose'
  require('hees.ai.backends').build = real_build
  vim.cmd 'only'
  local ai_items = require('hees.ai').menu_items(false)
  local ai_labels = vim.tbl_map(function(it) return it.label or '---' end, ai_items)
  check('AI menu has next edit, analysis, backend, models, log', vim.tbl_contains(ai_labels, 'Suggest next edit') and vim.tbl_contains(ai_labels, 'Explain function at cursor') and vim.tbl_contains(ai_labels, 'Request log') and vim.tbl_contains(ai_labels, 'Follow-up question…') and #ai_items <= 18, table.concat(ai_labels, ' | '))
  vim.api.nvim_set_current_buf(buf)

  -- [[ Per-task backends and models ]]
  local settings = require 'hees.ai.settings'
  local data_before = vim.env.HEES_NVIM_DATA
  vim.env.HEES_NVIM_DATA = vim.fn.tempname()
  vim.fn.mkdir(vim.env.HEES_NVIM_DATA .. '/nes', 'p')
  vim.fn.writefile({ vim.json.encode { backend = 'claude', models = { claude = 'sonnet' }, analyze_models = { codex = 'old-codex-model' }, auto = false } }, vim.env.HEES_NVIM_DATA .. '/nes/state.json')
  settings._reload()
  local b, m = settings.resolve 'nes'
  check('settings: old next-edit model moved to the nes task', b == 'claude' and m == 'sonnet', b .. '/' .. tostring(m))
  b, m = settings.resolve 'review'
  check('settings: unset task follows default backend and built-in default', b == 'claude' and m == nil, b .. '/' .. tostring(m))
  settings.set_task_backend('review', 'codex')
  b, m = settings.resolve 'review'
  check('settings: task backend, old analysis model moved with it', b == 'codex' and m == 'old-codex-model', b .. '/' .. tostring(m))
  check('settings: other tasks unaffected', (settings.resolve 'explain') == 'claude')
  settings.set_task_model('review', 'some-model')
  check('settings: task model for its backend', select(2, settings.resolve 'review') == 'some-model' and settings.describe('review'):find('codex / some-model', 1, true) ~= nil, settings.describe 'review')
  settings._reload()
  check('settings: saved and read back', select(2, settings.resolve 'review') == 'some-model')
  settings.reset_task 'review'
  check('settings: reset follows defaults again', (settings.resolve 'review') == 'claude')
  vim.env.HEES_NVIM_DATA = data_before
  settings._reload()

  -- [[ Debug state analysis (nvim-dap + debugpy) ]]
  local dap = require 'dap'
  local py_config
  for _, c in ipairs(dap.configurations.python or {}) do
    if c.request == 'launch' then py_config = c end
  end
  if not py_config then
    io.stdout:write 'skip  debug: no python launch configuration (debugpy not installed)\n'
  else
    local py = vim.fn.tempname() .. '.py'
    vim.fn.writefile({ 'def double(x):', '    y = x * 2', '    return y', '', 'print(double(21))' }, py)
    vim.cmd('edit ' .. vim.fn.fnameescape(py))
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    dap.set_breakpoint()
    dap.run(vim.tbl_extend('force', py_config, { program = py, console = 'internalConsole' }))
    vim.wait(60000, function()
      local s = dap.session()
      return s ~= nil and s.stopped_thread_id ~= nil and s.current_frame ~= nil
    end, 200)
    local ai_debug = require 'hees.ai.debug'
    if not ai_debug.is_stopped() then
      -- The adapter may not start in this environment; the fake-session checks below still cover the logic.
      io.stdout:write 'skip  debug: debugpy session did not stop at the breakpoint (adapter did not start here)\n'
      pcall(dap.terminate)
      pcall(function() require('dapui').close() end)
      vim.cmd 'silent! only'
      vim.api.nvim_set_current_buf(buf)
      goto debug_done
    end
    check('debug: stopped at the breakpoint', ai_debug.is_stopped())
    local dctx = ai_debug.collect(dap.session())
    check('debug: location and frame', dctx and dctx.line == 3 and dctx.frame:find('double', 1, true) ~= nil, dctx and (dctx.frame .. ':' .. dctx.line))
    check('debug: stop reason recorded', dctx and dctx.reason:find('breakpoint', 1, true) ~= nil, dctx and dctx.reason)
    check('debug: call stack has the caller', dctx and #dctx.stack >= 2 and dctx.stack[1]:find('double', 1, true) ~= nil, dctx and vim.inspect(dctx.stack))
    local locals = dctx and dctx.scopes[1] and table.concat(dctx.scopes[1].lines, '\n') or ''
    check('debug: local variables with values', locals:find('x: int = 21', 1, true) ~= nil and locals:find('y: int = 42', 1, true) ~= nil, locals)
    check('debug: source with the current line marked', dctx and vim.tbl_contains(dctx.source, '>3|     return y'), dctx and vim.inspect(dctx.source))
    local dprompt = dctx and ai_debug.build_prompt(dctx) or ''
    check('debug: prompt has stack, variables and source', dprompt:find('## Call stack', 1, true) and dprompt:find('## Variables', 1, true) and dprompt:find('>3|', 1, true), dprompt)
    local real = require('hees.ai.backends').build
    require('hees.ai.backends').build = function(_, _, p) return { argv = echo_argv, stdin = p } end
    ai_debug.run()
    vim.wait(15000, function() return not analyze.is_busy() end)
    require('hees.ai.backends').build = real
    local dlast = ai_log.all(1)[1]
    check('debug: request logged under the debug task', dlast.task == 'debug' and dlast.title:find('Debug', 1, true) ~= nil, vim.inspect { dlast.task, dlast.title })
    dap.terminate()
    vim.wait(5000, function() return dap.session() == nil end)
    pcall(function() require('dapui').close() end)
    vim.cmd 'only'
    vim.api.nvim_set_current_buf(buf)
  end
  ::debug_done::

  -- Debug state collection against a fake nvim-dap session (no adapter needed).
  do
    local py = vim.fn.tempname() .. '.py'
    vim.fn.writefile({ 'def double(x):', '    y = x * 2', '    return y', '', 'print(double(21))' }, py)
    local frames = {
      { id = 1, name = 'double', line = 3, source = { path = py } },
      { id = 2, name = '<module>', line = 5, source = { path = py } },
    }
    local replies = {
      scopes = { scopes = { { name = 'Locals', variablesReference = 10 } } },
      variables = {
        [10] = { variables = { { name = 'x', type = 'int', value = '21', variablesReference = 0 }, { name = 'items', type = 'list', value = '[1, 2]', variablesReference = 11 } } },
        [11] = { variables = { { name = '0', type = 'int', value = '1', variablesReference = 0 } } },
      },
    }
    local fake = {
      id = 999,
      config = { name = 'Python: Launch file', type = 'python' },
      stopped_thread_id = 1,
      current_frame = frames[1],
      threads = { [1] = { frames = frames } },
      capabilities = {},
      request = function(_, command, args, cb)
        if command == 'variables' then return cb(nil, replies.variables[args.variablesReference]) end
        cb(nil, replies[command])
      end,
    }
    local ai_debug = require 'hees.ai.debug'
    local fctx = ai_debug.collect(fake)
    check('debug (fake session): location and frame', fctx and fctx.line == 3 and fctx.frame == 'double', fctx and (fctx.frame .. ':' .. fctx.line))
    check('debug (fake session): call stack', fctx and #fctx.stack == 2 and fctx.stack[1]:find('#0 double', 1, true) ~= nil and fctx.stack[1]:find('current', 1, true) ~= nil, fctx and vim.inspect(fctx.stack))
    local flocals = fctx and table.concat(fctx.scopes[1].lines, '\n') or ''
    check('debug (fake session): variables, structured value expanded', flocals:find('x: int = 21', 1, true) and flocals:find('items: list = [1, 2]', 1, true) and flocals:find('    0: int = 1', 1, true), flocals)
    check('debug (fake session): source with current line marked', fctx and vim.tbl_contains(fctx.source, '>3|     return y'), fctx and vim.inspect(fctx.source))
    local fprompt = fctx and ai_debug.build_prompt(fctx, 'why is y 42?') or ''
    check('debug (fake session): prompt has question, stack, variables, source', fprompt:find('why is y 42?', 1, true) and fprompt:find('## Call stack', 1, true) and fprompt:find('## Variables — Locals', 1, true) and fprompt:find('>3|', 1, true), fprompt)
    check('debug: not stopped is reported', select(2, ai_debug.collect(nil)) ~= nil)
  end

  -- [[ Backends ]]
  local backends = require 'hees.ai.backends'
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
