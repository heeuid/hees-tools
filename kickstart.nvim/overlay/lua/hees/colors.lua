-- Colorscheme: Catppuccin Latte (light). kickstart's init.lua still sets up tokyonight; this runs
-- after it and switches the scheme, so init.lua stays untouched.

vim.pack.add { { src = 'https://github.com/catppuccin/nvim', name = 'catppuccin', version = vim.version.range '2.*' } }

require('catppuccin').setup {
  flavour = 'latte',
  -- auto_integrations picks up the installed plugins (neo-tree, telescope, gitsigns, which-key, mini, blink.cmp, dap, ...).
  auto_integrations = true,
}

vim.cmd.colorscheme 'catppuccin-latte'
