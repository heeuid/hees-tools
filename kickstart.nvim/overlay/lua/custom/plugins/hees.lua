-- hees-tools overlay for kickstart.nvim, loaded by `require 'custom.plugins'` in init.lua.
-- The modules depend on each other, so they are required in a fixed order here.
-- Copied in by install.ps1 / install.sh; edits here are overwritten by update.ps1 / update.sh,
-- put your own plugins in other files in this directory instead.

require 'hees.ui' -- clickable buffer tabs and gutter, overlay highlights
require('hees.nes').setup() -- next edit suggestions via the Claude / Codex / Gemini CLI
require('hees.context').setup() -- right-click (and <leader>m / Shift+F10) context menus
