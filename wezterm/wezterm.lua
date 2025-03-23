local wezterm = require("wezterm")
local act = wezterm.action
local config = {}

-- config

config = wezterm.config_builder()

config.front_end = "OpenGL"
config.animation_fps = 60

-- config.default_prog = { "C:\\Program Files\\PowerShell-7.3.5-win-x64\\pwsh.exe" }
-- config.default_prog = { "/bin/bash" }

local custom_catppuccin = wezterm.color.get_builtin_schemes()["Catppuccin Latte"]
-- local custom_catppuccin      = wezterm.color.get_builtin_schemes()["Catppuccin Macchiato"]
-- custom_catppuccin.background = '#293643'
config.color_schemes = { ["Custom_Catpuccin"] = custom_catppuccin }
config.color_scheme = "Custom_Catpuccin"

config.font = wezterm.font("Hack Nerd Font", {
	weight = "Regular",
	italic = false,
})

config.window_padding = {
	left = 1,
	right = 1,
	top = 1,
	bottom = 1,
}

-- config.leader = { key = "e", mods = "ALT" }

config.keys = {
	-- PANE
	-- create & delete
	{ key = "_", mods = "ALT|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "|", mods = "ALT|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "q", mods = "ALT", action = act.CloseCurrentPane({ confirm = false }) },
	-- navigate among panes
	{ key = "h", mods = "ALT", action = act.ActivatePaneDirection("Left") },
	{ key = "LeftArrow", mods = "ALT", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "ALT", action = act.ActivatePaneDirection("Down") },
	{ key = "DownArrow", mods = "ALT", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "ALT", action = act.ActivatePaneDirection("Up") },
	{ key = "UpArrow", mods = "ALT", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "ALT", action = act.ActivatePaneDirection("Right") },
	{ key = "RightArrow", mods = "ALT", action = act.ActivatePaneDirection("Right") },
	-- resize pane
	{ key = "h", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
	{ key = "LeftArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
	{ key = "j", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
	{ key = "DownArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
	{ key = "k", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
	{ key = "UpArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
	{ key = "l", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
	{ key = "RightArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
	-- swap pane
	{ key = "s", mods = "ALT", action = act.PaneSelect({ mode = "SwapWithActive" }) },

	-- WINDOW & TAB
	{ key = "c", mods = "ALT", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "t", mods = "ALT", action = act.SpawnWindow },
	{ key = "x", mods = "ALT", action = act.CloseCurrentTab({ confirm = false }) },
	{ key = "n", mods = "ALT", action = act.ActivateTabRelative(1) },
	{ key = "p", mods = "ALT", action = act.ActivateTabRelative(-1) },

	-- SCROLL
	{ key = "u", mods = "ALT", action = act.ScrollByLine(-5) },
	{ key = "d", mods = "ALT", action = act.ScrollByLine(5) },
	{ key = "u", mods = "ALT|SHIFT", action = act.ScrollByPage(-0.5) },
	{ key = "d", mods = "ALT|SHIFT", action = act.ScrollByPage(0.5) },
	{ key = "u", mods = "CTRL|ALT", action = act.ScrollToTop },
	{ key = "d", mods = "CTRL|ALT", action = act.ScrollToBottom },

	-- ETC
	{ key = "c", mods = "CTRL|ALT", action = act.ActivateCopyMode },
	{ key = "f", mods = "ALT", action = act.Search("CurrentSelectionOrEmptyString") },
	{ key = "z", mods = "ALT", action = act.TogglePaneZoomState },
	{ key = "z", mods = "CTRL|ALT", action = act.ToggleFullScreen },
} -- configs.keys

-- TAB
for i = 1, 9 do
	-- CTRL+ALT + number to activate that tab
	table.insert(config.keys, {
		key = tostring(i),
		mods = "ALT",
		action = act.ActivateTab(i - 1),
	})
end

-- status

wezterm.on("update-right-status", function(window, pane)
	-- Each element holds the text for a cell in a "powerline" style << fade
	local cells = {}

	-- Figure out the cwd and host of the current pane.
	-- This will pick up the hostname for the remote host if your
	-- shell is using OSC 7 on the remote host.
	local cwd_uri = pane:get_current_working_dir()
	if cwd_uri then
		local cwd = ""
		local hostname = ""

		if type(cwd_uri) == "userdata" then
			-- Running on a newer version of wezterm and we have
			-- a URL object here, making this simple!

			cwd = cwd_uri.file_path
			hostname = cwd_uri.host or wezterm.hostname()
		else
			-- an older version of wezterm, 20230712-072601-f4abf8fd or earlier,
			-- which doesn't have the Url object
			cwd_uri = cwd_uri:sub(8)
			local slash = cwd_uri:find("/")
			if slash then
				hostname = cwd_uri:sub(1, slash - 1)
				-- and extract the cwd from the uri, decoding %-encoding
				cwd = cwd_uri:sub(slash):gsub("%%(%x%x)", function(hex)
					return string.char(tonumber(hex, 16))
				end)
			end
		end

		-- Remove the domain name portion of the hostname
		local dot = hostname:find("[.]")
		if dot then
			hostname = hostname:sub(1, dot - 1)
		end
		if hostname == "" then
			hostname = wezterm.hostname()
		end

		table.insert(cells, cwd)
		table.insert(cells, hostname)
	end

	-- I like my date/time in this style: "Wed Mar 3 08:14"
	local date = wezterm.strftime("%a %b %-d %H:%M")
	table.insert(cells, date)

	-- An entry for each battery (typically 0 or 1 battery)
	for _, b in ipairs(wezterm.battery_info()) do
		table.insert(cells, string.format("%.0f%%", b.state_of_charge * 100))
	end

	-- The powerline < symbol
	local LEFT_ARROW = utf8.char(0xe0b3)
	-- The filled in variant of the < symbol
	local SOLID_LEFT_ARROW = utf8.char(0xe0b2)

	-- Color palette for the backgrounds of each cell
	local colors = {
		"#3c1361",
		"#52307c",
		"#663a82",
		"#7c5295",
		"#b491c8",
	}

	-- Foreground color for the text across the fade
	local text_fg = "#c0c0c0"

	-- The elements to be formatted
	local elements = {}
	-- How many cells have been formatted
	local num_cells = 0

	-- Translate a cell into elements
	function push(text, is_last)
		local cell_no = num_cells + 1
		table.insert(elements, { Foreground = { Color = text_fg } })
		table.insert(elements, { Background = { Color = colors[cell_no] } })
		table.insert(elements, { Text = " " .. text .. " " })
		if not is_last then
			table.insert(elements, { Foreground = { Color = colors[cell_no + 1] } })
			table.insert(elements, { Text = SOLID_LEFT_ARROW })
		end
		num_cells = num_cells + 1
	end

	while #cells > 0 do
		local cell = table.remove(cells, 1)
		push(cell, #cells == 0)
	end

	window:set_right_status(wezterm.format(elements))
end)

return config
