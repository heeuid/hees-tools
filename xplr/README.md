# xplr

## init.lua location

~/.config/xplr/init.lua

## bash_function - linux/bash

```bash
function xp() {
    res=$(xplr "$@")
    if [ -d "$res" ]; then
        cd "$res"
    elif [ -f "$res" ]; then
        nvim "$res"
        xp "$(dirname "$res")"
    else
        echo "$res"
    fi
}
```
