_G.version = '0.21.9'

local home = os.getenv("HOME")
local xpm_path = home .. "/.local/share/xplr/dtomvan/xpm.xplr"
local xpm_url = "https://github.com/dtomvan/xpm.xplr"

package.path = package.path
    .. ";"
    .. xpm_path
    .. "/?.lua;"
    .. xpm_path
    .. "/?/init.lua"

os.execute(
  string.format(
    "[ -e '%s' ] || git clone '%s' '%s'",
    xpm_path,
    xpm_url,
    xpm_path
  )
)

require'xpm'.setup({
  { name = "dtomvan/xpm.xplr" },
  { name = 'sayanarijit/fzf.xplr' },
  { name = 'dy-sh/dysh-style.xplr' },
  -- { name = 'prncss-xyz/icons.xplr' },
  -- { name = 'gitlab:hartan/web-devicons.xplr' },
  -- { name = 'dtomvan/extra-icons.xplr',
  --     after = function()
  --         xplr.config.general.table.row.cols[2] = { format = "custom.icons_dtomvan_col_1" }
  --     end
  -- },
  -- auto_install = true,
  -- auto_cleanup = true,
})

-- require'icons'.setup()

xplr.config.modes.builtin.default.key_bindings.on_key.x = {
  help = "xpm",
  messages = {
    "PopMode",
    { SwitchModeCustom = "xpm" },
  },
}

xplr.config.node_types.extension["lua"].meta.icon = xplr.util.paint("",
  { fg = { Indexed = 74 } }
)

xplr.config.modes.builtin.default.key_bindings.on_key["o"] = {
  help = "open in gui",
  messages = {
    {
      BashExec0 = [===[
        file_path=$(realpath "${XPLR_FOCUS_PATH}")
        if [ -n "$file_path" ]; then
          xdg-open "$file_path" > /dev/null 2>&1
        fi
      ]===],
    },
    "PopMode",
  },
}

xplr.config.modes.builtin.default.key_bindings.on_key["O"] = {
  help = "open cur-dir in gui",
  messages = {
    {
      BashExec0 = [===[
        current_dir=$(dirname $(realpath "${XPLR_FOCUS_PATH}"))
        if [ -n "$current_dir" ]; then
          xdg-open "$current_dir" > /dev/null 2>&1
        fi
      ]===],
    },
    "PopMode",
  },
}
