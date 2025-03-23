local wezterm = require 'wezterm'
local act = wezterm.action
local config = {}

config = wezterm.config_builder()

config.front_end = "OpenGL"
config.animation_fps = 60

config.default_prog = { "C:\\Program Files\\PowerShell-7.3.5-win-x64\\pwsh.exe" }
--config.default_prog = { "/bin/bash" }

local custom_catppuccin      = wezterm.color.get_builtin_schemes()["Catppuccin Latte"]
--local custom_catppuccin      = wezterm.color.get_builtin_schemes()["Catppuccin Macchiato"]
-- custom_catppuccin.background = '#293643'
config.color_schemes         = { ['Custom_Catpuccin'] = custom_catppuccin }
config.color_scheme          = 'Custom_Catpuccin'

config.font = wezterm.font(
  'Hack Nerd Font',
  {
    weight = 'Regular',
    italic = false
  }
)

config.window_padding = {
  left = 1, right = 1, top = 1, bottom = 1
}

config.leader = { key = "e", mods = "ALT" }

config.keys = {
  -- PANE
  -- create & delete
  { key = '_', mods = 'ALT|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' }, },
  { key = "|", mods = "ALT|SHIFT", action = act.SplitHorizontal { domain = 'CurrentPaneDomain' }, },
  { key = "q", mods = "ALT", action = act.CloseCurrentPane { confirm = false }, },
  -- navigate among panes
  { key = 'h', mods = 'ALT', action = act.ActivatePaneDirection 'Left', },
  { key = 'LeftArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Left', },
  { key = 'j', mods = 'ALT', action = act.ActivatePaneDirection 'Down', },
  { key = 'DownArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Down', },
  { key = 'k', mods = 'ALT', action = act.ActivatePaneDirection 'Up', },
  { key = 'UpArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Up', },
  { key = 'l', mods = 'ALT', action = act.ActivatePaneDirection 'Right', },
  { key = 'RightArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Right', },
  -- resize pane
  { key = 'h', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Left', 5 }, },
  { key = 'LeftArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Left', 5 }, },
  { key = 'j', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Down', 5 }, },
  { key = 'DownArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Down', 5 }, },
  { key = 'k', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Up', 5 }, },
  { key = 'UpArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Up', 5 }, },
  { key = 'l', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Right', 5 }, },
  { key = 'RightArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Right', 5 }, },
  -- swap pane
  { key = 's', mods = 'ALT', action = act.PaneSelect { mode = 'SwapWithActive' } },

  -- WINDOW & TAB
  { key = "c", mods = "ALT", action = act.SpawnTab 'CurrentPaneDomain', },
  { key = "t", mods = "ALT", action = act.SpawnWindow, },
  { key = "x", mods = "ALT", action = act.CloseCurrentTab { confirm = false }, },
  { key = "n", mods = "ALT", action = act.ActivateTabRelative(1), },
  { key = "p", mods = "ALT", action = act.ActivateTabRelative(-1), },

  -- SCROLL
  { key = 'u', mods = 'ALT', action = act.ScrollByLine(-5) },
  { key = 'd', mods = 'ALT', action = act.ScrollByLine(5) },
  { key = 'u', mods = 'ALT|SHIFT', action = act.ScrollByPage(-0.5) },
  { key = 'd', mods = 'ALT|SHIFT', action = act.ScrollByPage(0.5) },
  { key = 'u', mods = 'CTRL|ALT', action = act.ScrollToTop },
  { key = 'd', mods = 'CTRL|ALT', action = act.ScrollToBottom },

  -- ETC
  { key = "c", mods = "CTRL|ALT", action = act.ActivateCopyMode, },
  { key = "f", mods = "ALT", action = act.Search('CurrentSelectionOrEmptyString'), },
  { key = "z", mods = "ALT", action = act.TogglePaneZoomState, },
  { key = "z", mods = "CTRL|ALT", action = act.ToggleFullScreen, },
}  -- configs.keys

-- TAB
for i = 1, 9 do
  -- CTRL+ALT + number to activate that tab
  table.insert(config.keys, {
    key = tostring(i),
    mods = 'ALT',
    action = act.ActivateTab(i - 1),
  })
end

return config
