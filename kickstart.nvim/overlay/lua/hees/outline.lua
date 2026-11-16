-- Code structure sidebar (aerial.nvim): the classes, methods, functions, fields, variables, … of
-- the current file in a window on the right that follows the cursor. Symbols come from the
-- language server, or treesitter when no server is attached. <CR> or double-click jumps.
-- kickstart's gO (one-off telescope symbol list) stays as it is.

vim.pack.add { { src = 'https://github.com/stevearc/aerial.nvim', version = vim.version.range '4.*' } }

require('aerial').setup {
  backends = { 'lsp', 'treesitter', 'markdown', 'man' },
  layout = { default_direction = 'prefer_right', min_width = 28, max_width = { 45, 0.25 } },
  filter_kind = false, -- every kind of symbol, variables and fields included
  show_guides = true,
  highlight_on_hover = true,
  nerd_font = vim.g.have_nerd_font and true or false,
}

vim.keymap.set('n', '<leader>o', '<Cmd>AerialToggle<CR>', { desc = 'Code [O]utline (toggle)' })
