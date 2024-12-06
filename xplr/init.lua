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
  -- auto_install = true,
  -- auto_cleanup = true,
})

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
