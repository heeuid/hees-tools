-- Context menus: what the right mouse button (or <leader>m / Shift+F10) shows depends on where
-- it was clicked — an editor buffer, a neo-tree node, or a buffer tab.

local menu = require 'hees.menu'
local util = require 'hees.util'

local M = {}

local sep = { sep = true }

local function lsp_supports(method)
  return function()
    for _, client in ipairs(vim.lsp.get_clients { bufnr = 0 }) do
      if client:supports_method(method, 0) then return true end
    end
    return false
  end
end

local function has_lsp() return #vim.lsp.get_clients { bufnr = 0 } > 0 end
local function has_git() return vim.b.gitsigns_status_dict ~= nil end
local function dap() return package.loaded['dap'] end
local function dap_session() return dap() ~= nil and dap().session() ~= nil end
local function has_telescope() return package.loaded['telescope'] ~= nil end

local function copy_path(path)
  vim.fn.setreg('+', path)
  vim.fn.setreg('"', path)
  vim.notify('Copied: ' .. path)
end

--- Open the OS file manager with `path` selected (Windows) or its folder shown (Linux/macOS).
local function reveal_in_os(path)
  local cmd
  if util.is_win then
    cmd = { 'explorer.exe', '/select,' .. vim.fs.normalize(path):gsub('/', '\\') }
  elseif vim.fn.has 'mac' == 1 then
    cmd = { 'open', '-R', path }
  else
    cmd = { 'xdg-open', vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path) }
  end
  vim.system(cmd, { detach = true })
end

local function lsp_items(visual)
  if visual then
    return {
      { label = 'Code action', hint = 'gra', action = 'gra', enabled = lsp_supports 'textDocument/codeAction' },
      { label = 'Format selection', hint = '<leader>f', action = '<leader>f', enabled = has_lsp },
    }
  end
  return {
    { label = 'Rename symbol', hint = 'grn', action = 'grn', enabled = lsp_supports 'textDocument/rename' },
    { label = 'Code action', hint = 'gra', action = 'gra', enabled = lsp_supports 'textDocument/codeAction' },
    { label = 'Format buffer', hint = '<leader>f', action = '<leader>f' },
    { label = 'Hover documentation', hint = 'K', action = 'K', enabled = lsp_supports 'textDocument/hover' },
    { label = 'Signature help', action = vim.lsp.buf.signature_help, enabled = lsp_supports 'textDocument/signatureHelp' },
    sep,
    {
      label = 'Go to',
      items = {
        { label = 'Definition', hint = 'grd', action = 'grd', enabled = lsp_supports 'textDocument/definition' },
        { label = 'Implementation', hint = 'gri', action = 'gri', enabled = lsp_supports 'textDocument/implementation' },
        { label = 'Type definition', hint = 'grt', action = 'grt', enabled = lsp_supports 'textDocument/typeDefinition' },
        { label = 'Declaration', hint = 'grD', action = 'grD', enabled = lsp_supports 'textDocument/declaration' },
        { label = 'References', hint = 'grr', action = 'grr', enabled = lsp_supports 'textDocument/references' },
      },
    },
    {
      label = 'Structure',
      items = {
        { label = 'Outline sidebar', hint = '<leader>o', action = function() vim.cmd 'AerialToggle' end },
        { label = 'Document symbols', hint = 'gO', action = 'gO', enabled = lsp_supports 'textDocument/documentSymbol' },
        { label = 'Workspace symbols', hint = 'gW', action = 'gW', enabled = lsp_supports 'workspace/symbol' },
        sep,
        {
          label = 'Call hierarchy',
          enabled = lsp_supports 'textDocument/prepareCallHierarchy',
          items = {
            { label = 'Incoming calls (who calls this)', action = function() vim.lsp.buf.incoming_calls() end },
            { label = 'Outgoing calls (what this calls)', action = function() vim.lsp.buf.outgoing_calls() end },
          },
        },
        {
          label = 'Type hierarchy',
          enabled = lsp_supports 'textDocument/prepareTypeHierarchy',
          items = {
            { label = 'Supertypes', action = function() vim.lsp.buf.typehierarchy 'supertypes' end },
            { label = 'Subtypes', action = function() vim.lsp.buf.typehierarchy 'subtypes' end },
          },
        },
      },
    },
    {
      label = 'Diagnostics',
      items = {
        { label = 'Show line diagnostics', action = vim.diagnostic.open_float },
        { label = 'Next diagnostic', hint = ']d', action = ']d' },
        { label = 'Previous diagnostic', hint = '[d', action = '[d' },
        { label = 'Diagnostics list', hint = '<leader>q', action = '<leader>q' },
      },
    },
    sep,
    {
      label = 'Inlay hints',
      hint = '<leader>th',
      action = '<leader>th',
      enabled = lsp_supports 'textDocument/inlayHint',
      checked = vim.lsp.inlay_hint.is_enabled { bufnr = 0 },
    },
    { label = 'Restart LSP', action = function() vim.cmd 'lsp restart' end, enabled = has_lsp },
    { label = 'LSP health', action = function() vim.cmd 'checkhealth vim.lsp' end },
  }
end

local function debug_items()
  return {
    { label = dap_session() and 'Continue' or 'Start debugging', hint = '<F5>', action = '<F5>' },
    { label = 'Run to cursor', action = function() dap().run_to_cursor() end },
    { label = 'Terminate', action = function() dap().terminate() end, enabled = dap_session },
    {
      label = 'Step',
      enabled = dap_session,
      items = {
        { label = 'Step over', hint = '<F2>', action = '<F2>' },
        { label = 'Step into', hint = '<F1>', action = '<F1>' },
        { label = 'Step out', hint = '<F3>', action = '<F3>' },
      },
    },
    sep,
    { label = 'Toggle breakpoint', hint = '<leader>b', action = '<leader>b' },
    {
      label = 'Breakpoints',
      items = {
        { label = 'Conditional breakpoint…', hint = '<leader>B', action = '<leader>B' },
        { label = 'Log point…', action = function() dap().set_breakpoint(nil, nil, vim.fn.input 'Log message: ') end },
        { label = 'List breakpoints', action = function() dap().list_breakpoints(true) end },
        { label = 'Clear all breakpoints', action = function() dap().clear_breakpoints() end },
      },
    },
    sep,
    { label = 'Toggle debug UI', hint = '<F7>', action = '<F7>' },
    { label = 'Toggle REPL', action = function() dap().repl.toggle() end },
    sep,
    { label = 'Ask AI', items = function() return require('hees.ai').debug_items() end, enabled = function() return require('hees.ai.debug').is_stopped() end },
  }
end

local function git_items(visual)
  if visual then
    return {
      { label = 'Stage selected lines', hint = '<leader>hs', action = '<leader>hs' },
      { label = 'Reset selected lines', hint = '<leader>hr', action = '<leader>hr' },
    }
  end
  return {
    { label = 'Preview hunk', hint = '<leader>hp', action = '<leader>hp' },
    { label = 'Preview hunk inline', hint = '<leader>hi', action = '<leader>hi' },
    { label = 'Next hunk', hint = ']c', action = ']c' },
    { label = 'Previous hunk', hint = '[c', action = '[c' },
    sep,
    { label = 'Stage hunk', hint = '<leader>hs', action = '<leader>hs' },
    { label = 'Reset hunk', hint = '<leader>hr', action = '<leader>hr' },
    { label = 'Stage buffer', hint = '<leader>hS', action = '<leader>hS' },
    sep,
    { label = 'Blame line', hint = '<leader>hb', action = '<leader>hb' },
    { label = 'Diff against index', hint = '<leader>hd', action = '<leader>hd' },
    { label = 'Diff against last commit', hint = '<leader>hD', action = '<leader>hD' },
  }
end

local function search_items(visual)
  if visual then return { { label = 'Search selection', hint = '<leader>sw', action = '<leader>sw' } } end
  return {
    { label = 'Find files', hint = '<leader>sf', action = '<leader>sf' },
    { label = 'Grep', hint = '<leader>sg', action = '<leader>sg' },
    { label = 'Search word under cursor', hint = '<leader>sw', action = '<leader>sw' },
    { label = 'Search in buffer', hint = '<leader>/', action = '<leader>/' },
    { label = 'Recent files', hint = '<leader>s.', action = '<leader>s.' },
    { label = 'Diagnostics', hint = '<leader>sd', action = '<leader>sd' },
    { label = 'Keymaps', hint = '<leader>sk', action = '<leader>sk' },
    { label = 'Help', hint = '<leader>sh', action = '<leader>sh' },
  }
end

--- Split and arrange editor windows. Each item runs the :wincmd behind Neovim's own <C-w> key
--- (shown as the hint) directly, so it works the same however <C-w> is mapped.
local function window_items()
  local editor_wins = #vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == '' end, vim.api.nvim_tabpage_list_wins(0))
  local several = editor_wins > 1
  local function wincmd(c)
    return function() vim.cmd.wincmd(c) end
  end
  return {
    { label = 'Split right', hint = '<C-w>v', action = wincmd 'v' },
    { label = 'Split below', hint = '<C-w>s', action = wincmd 's' },
    { label = 'Open in new tab', hint = ':tab split', action = function() vim.cmd 'tab split' end },
    { label = 'Move to new tab', hint = '<C-w>T', action = wincmd 'T', enabled = several },
    sep,
    { label = 'Equalize sizes', hint = '<C-w>=', action = wincmd '=', enabled = several },
    { label = 'Close window', hint = '<C-w>c', action = wincmd 'c', enabled = several or #vim.api.nvim_list_tabpages() > 1 },
    { label = 'Close other windows', hint = '<C-w>o', action = wincmd 'o', enabled = several },
    sep,
    { label = 'Quit Neovim', hint = ':qa', action = function() M.quit() end },
  }
end

--- Run an Ex command, showing its error (e.g. E37, E141, E948) instead of a stack trace.
local function try(cmd)
  local ok, err = pcall(vim.cmd, cmd)
  if not ok then vim.notify(tostring(err):gsub('^.-:%d+: ', ''), vim.log.levels.ERROR) end
end

--- Quit Neovim. With unsaved changes, asks in a menu (save all / discard / cancel) instead of
--- :confirm's keyboard prompt, so it can be done with the mouse alone.
function M.quit()
  local unsaved = vim.tbl_filter(function(b) return vim.bo[b].modified and vim.bo[b].buflisted end, vim.api.nvim_list_bufs())
  if #unsaved == 0 then return try 'qa' end
  local names = vim.tbl_map(function(b)
    local name = vim.api.nvim_buf_get_name(b)
    return name == '' and '[No Name]' or vim.fn.fnamemodify(name, ':t')
  end, unsaved)
  local anchor = {}
  if vim.fn.getmousepos().screenrow == 0 then anchor.row, anchor.col = menu.cursor_anchor() end
  menu.open({
    { label = ('%d unsaved: %s'):format(#unsaved, table.concat(names, ', ', 1, math.min(#names, 3)) .. (#names > 3 and ', …' or '')), enabled = false },
    sep,
    { label = 'Save all and quit', hint = ':wqa', action = function() try 'wqa' end },
    { label = 'Quit without saving', hint = ':qa!', action = function() try 'qa!' end },
    { label = 'Cancel', hint = '<Esc>', action = function() end },
  }, anchor)
end

--- The current buffer: switch, save, close (the window stays, like the buffer tab's Close).
local function current_buffer_items()
  local listed = #vim.fn.getbufinfo { buflisted = 1 }
  local modified = vim.bo.modified
  local any_modified = #vim.tbl_filter(function(b) return b.changed == 1 end, vim.fn.getbufinfo { buflisted = 1 }) > 0
  return {
    { label = 'Next buffer', hint = ']b', action = function() try 'bnext' end, enabled = listed > 1 },
    { label = 'Previous buffer', hint = '[b', action = function() try 'bprevious' end, enabled = listed > 1 },
    { label = 'Find buffer…', hint = '<leader><leader>', action = '<leader><leader>', enabled = has_telescope },
    sep,
    { label = 'Save', hint = ':w', action = function() try 'write' end, enabled = modified and vim.bo.buftype == '' },
    { label = 'Save all', hint = ':wa', action = function() try 'wall' end, enabled = any_modified },
    sep,
    { label = 'Close buffer', action = function() require('mini.bufremove').delete(0, false) end },
    { label = 'Close other buffers', action = function() try 'BufferLineCloseOthers' end, enabled = listed > 1 },
  }
end

--- Tab pages (each holds its own window layout).
local function tabpage_items()
  local several = #vim.api.nvim_list_tabpages() > 1
  return {
    { label = 'New tab', hint = ':tabnew', action = function() vim.cmd 'tabnew' end },
    { label = 'Next tab', hint = 'gt', action = function() vim.cmd 'tabnext' end, enabled = several },
    { label = 'Previous tab', hint = 'gT', action = function() vim.cmd 'tabprevious' end, enabled = several },
    sep,
    { label = 'Close tab', hint = ':tabclose', action = function() try 'tabclose' end, enabled = several },
    { label = 'Close other tabs', hint = ':tabonly', action = function() try 'tabonly' end, enabled = several },
  }
end

-- Two ways back: "Back from definition" pops the tag stack (<C-t>), which Go to definition pushes,
-- straight to where the jump started; Go back / Go forward walk the jump list (<C-o> / <C-i>),
-- which also holds searches, G, % and other jumps made since.

--- Whether the jump list has an older (-1) or newer (1) position than the current one.
local function can_jump(dir)
  local list, idx = unpack(vim.fn.getjumplist())
  if dir < 0 then return idx > 0 end
  return idx < #list - 1
end

--- <C-o> / <C-i> without depending on how the terminal sends <C-i> (it is <Tab> in most).
local function jump(dir) vim.cmd.execute(dir < 0 and [["normal! \<C-o>"]] or [["normal! \<C-i>"]]) end

local function buffer_items(visual)
  local file = vim.api.nvim_buf_get_name(0)
  local editable = vim.bo.modifiable
  local file_items = {
    { label = 'Code outline', hint = '<leader>o', action = function() vim.cmd 'AerialToggle' end },
    { label = 'Reveal in explorer', hint = '\\', action = '\\' },
    { label = 'Copy file path', action = function() copy_path(file) end },
    { label = 'Open containing folder', action = function() reveal_in_os(file) end },
  }
  local groups = {
    { label = 'LSP', items = function() return lsp_items(visual) end, enabled = has_lsp },
    { label = 'Debug', items = debug_items, enabled = function() return not visual and dap() ~= nil end },
    { label = 'AI', items = function() return require('hees.ai').menu_items(visual) end },
    { label = 'Git', items = function() return git_items(visual) end, enabled = has_git },
    { label = 'Search', items = function() return search_items(visual) end, enabled = has_telescope },
    sep,
    { label = 'Window', items = window_items },
    { label = 'Buffer', items = current_buffer_items },
    { label = 'Tab', items = tabpage_items },
    { label = 'File', items = file_items, enabled = file ~= '' },
  }
  if visual then
    return vim.list_extend({
      { label = 'Cut', hint = 'd', action = 'd', enabled = editable },
      { label = 'Copy', hint = 'y', action = 'y' },
      { label = 'Paste over selection', hint = 'p', action = 'p', enabled = editable },
      sep,
    }, groups)
  end
  return vim.list_extend({
    { label = 'Paste', hint = 'P', action = 'P', enabled = editable },
    {
      label = 'Edit',
      items = {
        { label = 'Undo', hint = 'u', action = 'u', enabled = editable },
        { label = 'Redo', hint = '<C-r>', action = '<C-r>', enabled = editable },
        { label = 'Select all', hint = 'ggVG', action = 'ggVG' },
      },
    },
    sep,
    { label = 'Go to definition', hint = 'grd', action = 'grd', enabled = lsp_supports 'textDocument/definition' },
    { label = 'Find references', hint = 'grr', action = 'grr', enabled = lsp_supports 'textDocument/references' },
    { label = 'Back from definition', hint = '<C-t>', action = function() vim.cmd.pop() end, enabled = vim.fn.gettagstack().curidx > 1 },
    { label = 'Go back', hint = '<C-o>', action = function() jump(-1) end, enabled = can_jump(-1) },
    { label = 'Go forward', hint = '<C-i>', action = function() jump(1) end, enabled = can_jump(1) },
    sep,
  }, groups)
end

--- Menu for a neo-tree node. `state` is neo-tree's filesystem state for that window.
local function explorer_items(state)
  local node = state.tree and state.tree:get_node()
  if not node or not node.path then return {} end
  local fs = require 'neo-tree.sources.filesystem.commands'
  local run = function(name)
    return function() fs[name](state) end
  end
  local is_file = node.type == 'file'
  local has_clip = state.clipboard ~= nil and next(state.clipboard) ~= nil
  local cwd = vim.fn.getcwd()
  return {
    { label = is_file and 'Open' or 'Expand / collapse', hint = '<CR>', action = run 'open' },
    {
      label = 'Open in',
      enabled = is_file,
      items = {
        { label = 'Pick window…', hint = 'w', action = run 'open_with_window_picker', enabled = package.loaded['window-picker'] ~= nil },
        { label = 'Vertical split', hint = 's', action = run 'open_vsplit' },
        { label = 'Horizontal split', hint = 'S', action = run 'open_split' },
        { label = 'New tab', hint = 't', action = run 'open_tabnew' },
      },
    },
    sep,
    { label = 'New file…', hint = 'a', action = run 'add' },
    { label = 'New folder…', hint = 'A', action = run 'add_directory' },
    { label = 'Rename…', hint = 'r', action = run 'rename' },
    { label = 'Delete', hint = 'd', action = run 'delete' },
    sep,
    { label = 'Copy', hint = 'y', action = run 'copy_to_clipboard' },
    { label = 'Cut', hint = 'x', action = run 'cut_to_clipboard' },
    { label = 'Paste', hint = 'p', action = run 'paste_from_clipboard', enabled = has_clip },
    sep,
    {
      label = 'Path',
      items = {
        { label = 'Copy absolute path', action = function() copy_path(node.path) end },
        { label = 'Copy relative path', action = function() copy_path(vim.fs.relpath(cwd, node.path) or node.path) end },
        { label = 'Show in system file manager', action = function() reveal_in_os(node.path) end },
      },
    },
    {
      label = 'View',
      items = {
        { label = 'Toggle hidden files', hint = 'H', action = run 'toggle_hidden' },
        { label = 'Refresh', hint = 'R', action = run 'refresh' },
        { label = 'Close explorer', hint = '\\', action = function() vim.cmd 'Neotree close' end },
      },
    },
  }
end

local function tab_items(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  local function on_buf(cmd)
    return function()
      vim.api.nvim_set_current_buf(bufnr)
      vim.cmd(cmd)
    end
  end
  return {
    { label = 'Close', action = function() require('mini.bufremove').delete(bufnr, false) end },
    { label = 'Close others', action = on_buf 'BufferLineCloseOthers' },
    { label = 'Close to the right', action = on_buf 'BufferLineCloseRight' },
    { label = 'Close to the left', action = on_buf 'BufferLineCloseLeft' },
    sep,
    { label = 'Pin / unpin', action = on_buf 'BufferLineTogglePin' },
    { label = 'Open in vertical split', action = function() vim.cmd('vertical sbuffer ' .. bufnr) end },
    { label = 'Open in horizontal split', action = function() vim.cmd('sbuffer ' .. bufnr) end },
    sep,
    { label = 'Copy file path', action = function() copy_path(file) end, enabled = file ~= '' },
    { label = 'Reveal in explorer', action = on_buf 'Neotree reveal', enabled = file ~= '' },
  }
end

function M.open_tab_menu(bufnr) menu.open(tab_items(bufnr)) end

local function neo_tree_state(win)
  local ok, manager = pcall(require, 'neo-tree.sources.manager')
  if not ok then return nil end
  -- The sidebar's state belongs to the tab; a window-keyed state only exists for
  -- "current window" (netrw-style) trees.
  local state = manager.get_state 'filesystem'
  if state.winid == win and state.tree then return state end
  state = manager.get_state('filesystem', nil, win)
  if state.tree then return state end
  return nil
end

--- Open the menu for whatever is under the mouse pointer.
---@param visual boolean? the click happened in visual mode (keep the selection)
function M.open_at_mouse(visual)
  local mp = vim.fn.getmousepos()
  local win = mp.winid
  local info = win ~= 0 and vim.fn.getwininfo(win)[1]
  -- Tabline, statusline, gutter, and other plugins' floats keep their own right-click behavior.
  local in_text = info and mp.line > 0 and mp.wincol > info.textoff and vim.api.nvim_win_get_config(win).relative == ''
  if not in_text then return vim.api.nvim_feedkeys(vim.keycode '<RightMouse>', 'n', false) end

  if not visual then
    vim.api.nvim_set_current_win(win)
    pcall(vim.api.nvim_win_set_cursor, win, { mp.line, math.max(mp.column - 1, 0) })
  end
  local anchor = { row = mp.screenrow - 1, col = mp.screencol - 1, visual = visual }
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'neo-tree' then
    local state = neo_tree_state(win)
    if state then return menu.open(explorer_items(state), anchor) end
  end
  menu.open(buffer_items(visual), anchor)
end

--- Open the menu at the cursor (keyboard entry point).
---@param visual boolean?
function M.open_at_cursor(visual)
  local row, col = menu.cursor_anchor()
  local anchor = { row = row, col = col, visual = visual }
  if vim.bo.filetype == 'neo-tree' then
    local state = neo_tree_state(vim.api.nvim_get_current_win())
    if state then return menu.open(explorer_items(state), anchor) end
  end
  menu.open(buffer_items(visual), anchor)
end

--- Leave visual mode first so the '< and '> marks are set; actions restore it with `gv`.
local function from_visual(fn)
  return function()
    vim.cmd 'normal! \27'
    fn(true)
  end
end

function M.setup()
  -- Fast repeated right clicks arrive as <2-RightMouse> …; they open the same menu, otherwise
  -- Neovim's built-in PopUp menu would show.
  for _, lhs in ipairs { '<RightMouse>', '<2-RightMouse>', '<3-RightMouse>', '<4-RightMouse>' } do
    vim.keymap.set('n', lhs, function() M.open_at_mouse(false) end, { desc = 'Context menu' })
    vim.keymap.set('x', lhs, from_visual(M.open_at_mouse), { desc = 'Context menu' })
    vim.keymap.set('i', lhs, function()
      vim.cmd.stopinsert()
      vim.schedule(function() M.open_at_mouse(false) end)
    end, { desc = 'Context menu' })
  end
  -- Mouse back/forward side buttons walk the jump list, like a browser (no default in Neovim).
  vim.keymap.set('n', '<X1Mouse>', function() jump(-1) end, { desc = 'Go back (jump list)' })
  vim.keymap.set('n', '<X2Mouse>', function() jump(1) end, { desc = 'Go forward (jump list)' })
  for _, lhs in ipairs { '<leader>m', '<S-F10>' } do
    vim.keymap.set('n', lhs, function() M.open_at_cursor(false) end, { desc = 'Context [M]enu' })
    vim.keymap.set('x', lhs, from_visual(M.open_at_cursor), { desc = 'Context [M]enu' })
  end
end

-- Exposed for tests.
M._buffer_items = buffer_items
M._window_items = window_items
M._explorer_items = explorer_items
M._tab_items = tab_items
M._neo_tree_state = neo_tree_state

return M
