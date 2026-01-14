# Alacritty

## Config path

- Ubuntu: $HOME/.config/alacritty/alacritty.toml
- Windows: %APPDATA%\alacritty\alacritty.toml

## Theme

1. Copy `themes/`
from [alacritty-theme repository](https://github.com/alacritty/alacritty-theme)
to **Config directory path**.
2. Delete Color settings in `alacritty.toml`
3. Import theme toml file

    ```toml
    [general]
    import = [
        # e.g., "~/AppData/Roaming/alacritty/alacritty-theme/themes/catppuccin_latte.toml"
        "{Config directory path}/{theme-path}"
    ]
    ```
