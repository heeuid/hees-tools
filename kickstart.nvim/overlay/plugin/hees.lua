-- hees-tools overlay for kickstart.nvim. Neovim sources plugin/*.lua from the config folder right
-- after init.lua, so this runs once kickstart's plugins are set up, whether or not init.lua requires
-- custom.plugins. The modules depend on each other, so they are required in a fixed order here.
-- Copied in by plugins.ps1 / plugins.sh; edits here are overwritten by update.ps1 / update.sh,
-- put your own plugins in lua/custom/plugins/ instead.

if vim.g.loaded_hees then return end
vim.g.loaded_hees = true

require 'hees.colors' -- Catppuccin Latte, replacing kickstart's tokyonight
require 'hees.ui' -- clickable buffer tabs and gutter, overlay highlights
require 'hees.window_picker' -- explorer `w`: open a file in the window you pick
require 'hees.explorer' -- explorer: row highlight instead of a cursor, h/l collapse/expand/open
require 'hees.outline' -- code structure sidebar (aerial.nvim), <leader>o
require 'hees.lsp_root' -- language servers never take the home folder as their workspace root
require('hees.ai').setup() -- Claude / Codex / Gemini: next edit suggestions, code analysis with LSP, request log
require('hees.context').setup() -- right-click (and <leader>m / Shift+F10) context menus
