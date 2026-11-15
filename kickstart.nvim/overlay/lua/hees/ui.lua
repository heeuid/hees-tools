-- Mouse-friendly UI: clickable buffer tabs (bufferline) and a clickable gutter (statuscol).

-- Deliver <MouseMove> events so menus can highlight the item under the pointer.
vim.o.mousemoveevent = true

vim.pack.add {
  { src = 'https://github.com/akinsho/bufferline.nvim', version = vim.version.range '4.*' },
  'https://github.com/luukvbaal/statuscol.nvim',
}

-- [[ Buffer tabs ]]
-- Left click switches, middle click closes, right click opens the tab menu.
local function close_buffer(bufnr) require('mini.bufremove').delete(bufnr, false) end

require('bufferline').setup {
  options = {
    close_command = close_buffer,
    middle_mouse_command = close_buffer,
    right_mouse_command = function(bufnr) require('hees.context').open_tab_menu(bufnr) end,
    left_mouse_command = 'buffer %d',
    diagnostics = 'nvim_lsp',
    show_buffer_icons = vim.g.have_nerd_font,
    buffer_close_icon = vim.g.have_nerd_font and '\u{f00d}' or '×', -- shows: 
    close_icon = vim.g.have_nerd_font and '\u{f00d}' or '×', -- shows: 
    modified_icon = '●',
    left_trunc_marker = vim.g.have_nerd_font and '\u{f0d9}' or '◂', -- shows: 
    right_trunc_marker = vim.g.have_nerd_font and '\u{f0da}' or '▸', -- shows: 
    separator_style = 'thin',
    offsets = {
      { filetype = 'neo-tree', text = 'Explorer', highlight = 'Directory', text_align = 'left', separator = true },
    },
  },
}

-- [[ Clickable gutter ]]
-- Click a line number to toggle a breakpoint (Ctrl+click: conditional), click a git sign to
-- preview the hunk, click a diagnostic sign to see the message, click a fold marker to fold.
local builtin = require 'statuscol.builtin'
require('statuscol').setup {
  relculright = true,
  segments = {
    { sign = { namespace = { 'diagnostic' }, maxwidth = 1, colwidth = 2, auto = true }, click = 'v:lua.ScSa' },
    { sign = { name = { 'Dap' }, maxwidth = 1, colwidth = 2, auto = true }, click = 'v:lua.ScSa' },
    { text = { builtin.lnumfunc, ' ' }, click = 'v:lua.ScLa' },
    { sign = { namespace = { 'gitsigns' }, maxwidth = 1, colwidth = 1, auto = false, wrap = true }, click = 'v:lua.ScSa' },
    { text = { builtin.foldfunc, ' ' }, click = 'v:lua.ScFa' },
  },
}

-- A shared highlight set for the overlay, re-applied when the colorscheme changes.
local function set_highlights()
  local hl = function(name, opts) vim.api.nvim_set_hl(0, name, vim.tbl_extend('keep', opts, { default = true })) end
  hl('HeesMenu', { link = 'Pmenu' })
  hl('HeesMenuBorder', { link = 'FloatBorder' })
  hl('HeesMenuSel', { link = 'PmenuSel' })
  hl('HeesMenuHint', { link = 'Comment' })
  hl('HeesMenuDisabled', { link = 'NonText' })
  hl('HeesMenuSep', { link = 'FloatBorder' })
  hl('HeesMenuCheck', { link = 'DiagnosticOk' })
  hl('HeesHiddenCursor', { blend = 100, nocombine = true })
  hl('HeesNesDelete', { link = 'DiffDelete' })
  hl('HeesNesAdd', { link = 'DiffAdd' })
  hl('HeesNesHint', { link = 'DiagnosticVirtualTextHint' })
  hl('HeesNesBusy', { link = 'DiagnosticVirtualTextInfo' })
end
set_highlights()
vim.api.nvim_create_autocmd('ColorScheme', { group = vim.api.nvim_create_augroup('hees-ui-hl', { clear = true }), callback = set_highlights })
