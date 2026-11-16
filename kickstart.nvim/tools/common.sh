# Shared helpers for the Linux/macOS scripts. Source it: . "$HERE/tools/common.sh"
# Needs bash; uses only coreutils, curl or wget, tar and git.

set -euo pipefail

HERE=${HERE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
VERSIONS=${HEES_NVIM_VERSIONS:-$HERE/versions}
APPNAME_FILE=$HERE/.appname

# Everything a script prints is also saved to logs/<time>-<script>.log next to the scripts. A script
# called by another (install.sh → kickstart.sh …) writes into the log the outermost one opened.
if [ -z "${HEES_LOG:-}" ]; then
  mkdir -p "$HERE/logs"
  HEES_LOG=$HERE/logs/$(date +%Y%m%d-%H%M%S)-$(basename "$0" .sh).log
  export HEES_LOG
  exec > >(tee -a "$HEES_LOG") 2>&1
  trap 'printf "[log] 출력 기록: %s\n" "$HEES_LOG"' EXIT
fi

say() { printf '[%s] %s\n' "$TAG" "$*"; }
warn() { printf '\033[33m[%s] %s\033[0m\n' "$TAG" "$*" >&2; }
fail() {
  printf '\033[31m[%s] 오류: %s\033[0m\n' "$TAG" "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }
fetch() { if have curl; then curl -fsSL -o "$2" "$1"; else wget -qO "$2" "$1"; fi; } # url dest

# Tools installed per user (tree-sitter, the nvim link) live in ~/.local/bin; cargo installs to
# ~/.cargo/bin. Put both on PATH for these scripts and the headless Neovim they start, and remember
# the original PATH to tell whether the user's own shell will find them.
USER_PATH=$PATH
for dir in "$HOME/.cargo/bin" "$HOME/.local/bin"; do
  case ":$PATH:" in *":$dir:"*) ;; *) PATH=$dir:$PATH ;; esac
done
export PATH

# Warn when a directory isn't on the PATH the user's shell had.
check_user_path() { # dir
  case ":$USER_PATH:" in
  *":$1:"*) ;;
  *)
    warn "$1 이 셸 PATH 에 없습니다. 셸 설정(~/.bashrc 등)에 다음 줄을 넣고 새 셸을 여세요:"
    warn "  export PATH=\"$1:\$PATH\""
    ;;
  esac
}

# nvim-treesitter (kickstart) compiles parsers with `tree-sitter build`; it needs tree-sitter-cli
# 0.26.1 or newer (TREE_SITTER_MIN_VER in its health check). Older ones (apt, old npm) fail with
# "The subcommand 'build' wasn't recognized".
TS_MIN=0.26.1

ts_version() { "$1" --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1; } # exe
ts_new_enough() { # exe
  local v
  v=$(ts_version "$1")
  [ -n "$v" ] && [ "$(printf '%s\n%s\n' "$TS_MIN" "$v" | sort -V | head -n1)" = "$TS_MIN" ]
}

# After installing a new tree-sitter, make sure the user's own shell will pick it, not an old one.
check_user_tree_sitter() { # installed exe
  local first
  first=$(PATH=$USER_PATH command -v tree-sitter 2>/dev/null || true)
  if [ -z "$first" ]; then
    check_user_path "$(dirname "$1")"
  elif [ "$first" != "$1" ] && ! ts_new_enough "$first"; then
    warn "셸에서는 오래된 $first ($(ts_version "$first")) 가 먼저 잡힙니다. Neovim 이 그걸 쓰면 파서 설치가 실패합니다."
    warn "  지우기: sudo apt remove tree-sitter-cli  또는  npm uninstall -g tree-sitter-cli  (설치한 방법에 맞게)"
    warn "  또는 셸 설정에서 $(dirname "$1") 를 PATH 맨 앞에: export PATH=\"$(dirname "$1"):\$PATH\""
  fi
}

# Install the tree-sitter CLI when it is missing or older than $TS_MIN: the official release binary
# into ~/.local/bin if it runs here (it needs a recent glibc), otherwise `cargo install`.
# Returns 1 if neither worked.
ensure_tree_sitter() {
  if have tree-sitter; then
    local found
    found=$(command -v tree-sitter)
    if ts_new_enough "$found"; then
      say "tree-sitter CLI: $found ($(ts_version "$found"))"
      check_user_tree_sitter "$found"
      return 0
    fi
    warn "tree-sitter CLI 가 너무 오래됐습니다: $found ($(ts_version "$found" || true)), $TS_MIN 이상이 필요합니다. 새 버전을 설치합니다."
  fi
  local asset= dest=$HOME/.local/bin tmp
  case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) asset=tree-sitter-linux-x64.gz ;;
  Linux/aarch64 | Linux/arm64) asset=tree-sitter-linux-arm64.gz ;;
  Darwin/arm64) asset=tree-sitter-macos-arm64.gz ;;
  Darwin/x86_64) asset=tree-sitter-macos-x64.gz ;;
  esac
  if [ -n "$asset" ]; then
    say "tree-sitter CLI 설치: 공식 릴리스 $asset → $dest/tree-sitter"
    mkdir -p "$dest"
    tmp=$(mktemp)
    if fetch "https://github.com/tree-sitter/tree-sitter/releases/latest/download/$asset" "$tmp" &&
      gunzip -c "$tmp" >"$dest/tree-sitter" && chmod +x "$dest/tree-sitter" && ts_new_enough "$dest/tree-sitter"; then
      rm -f "$tmp"
      say "tree-sitter CLI: $dest/tree-sitter ($(ts_version "$dest/tree-sitter"))"
      check_user_tree_sitter "$dest/tree-sitter"
      return 0
    fi
    rm -f "$tmp" "$dest/tree-sitter"
    warn "공식 실행 파일이 이 시스템에서 실행되지 않습니다 (glibc 2.39 이상 필요). cargo 로 빌드를 시도합니다."
  fi
  if have cargo; then
    say "tree-sitter CLI 설치: cargo install --locked tree-sitter-cli (소스 빌드, 몇 분 걸립니다)"
    if cargo install --locked tree-sitter-cli && ts_new_enough "$HOME/.cargo/bin/tree-sitter"; then
      say "tree-sitter CLI: $HOME/.cargo/bin/tree-sitter ($(ts_version "$HOME/.cargo/bin/tree-sitter"))"
      check_user_tree_sitter "$HOME/.cargo/bin/tree-sitter"
      return 0
    fi
  fi
  warn "tree-sitter CLI 를 설치하지 못했습니다. 이대로면 문법 색칠(treesitter 파서)이 동작하지 않습니다."
  warn "Rust 를 설치한 뒤(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh) 이 스크립트를 다시 실행하세요."
  return 1
}

# Config name (NVIM_APPNAME): --app, else what kickstart.sh recorded, else 'nvim' — Neovim's default
# location, so plain `nvim` uses it.
app_name() {
  if [ -n "${1:-}" ]; then
    printf '%s' "$1"
  elif [ -s "$APPNAME_FILE" ]; then
    head -n1 "$APPNAME_FILE"
  else
    printf 'nvim'
  fi
}

config_dir() { printf '%s/%s' "${XDG_CONFIG_HOME:-$HOME/.config}" "$1"; }
data_dir() { printf '%s/%s' "${XDG_DATA_HOME:-$HOME/.local/share}" "$1"; }
state_dir() { printf '%s/%s' "${XDG_STATE_HOME:-$HOME/.local/state}" "$1"; }
cache_dir() { printf '%s/%s' "${XDG_CACHE_HOME:-$HOME/.cache}" "$1"; }

# The Neovim selected with nvim-version.sh, or one on PATH when none is selected.
find_nvim() {
  if [ -x "$VERSIONS/current/bin/nvim" ]; then
    printf '%s' "$VERSIONS/current/bin/nvim"
  elif have nvim; then
    command -v nvim
  fi
}

# Prints "major minor patch" of a Neovim binary.
nvim_version() { "$1" --version | head -n1 | sed -E 's/^NVIM v?([0-9]+)\.([0-9]+)\.([0-9]+).*/\1 \2 \3/'; }

# Neovim >= 0.12 (vim.pack) or stop with instructions. Prints the path.
require_nvim() {
  local exe major minor _
  exe=$(find_nvim)
  [ -n "$exe" ] || fail "Neovim이 없습니다. 먼저 ./nvim-version.sh install stable 을 실행하세요."
  read -r major minor _ <<<"$(nvim_version "$exe")"
  if [ "$major" -eq 0 ] && [ "$minor" -lt 12 ]; then
    fail "kickstart.nvim은 Neovim 0.12 이상이 필요합니다 ($exe 은 $major.$minor). ./nvim-version.sh install stable 로 설치하세요."
  fi
  printf '%s' "$exe"
}

# Run the config headless to finish async installs (install) or update everything (update).
run_sync() { # app mode [plugins]
  local exe sync
  exe=$(require_nvim)
  # :luafile takes a file name, so spaces in the path must be escaped.
  sync=$HERE/tools/sync.lua
  sync=${sync// /\\ }
  say "Neovim 헤드리스 동기화 ($2) — 플러그인/LSP/디버거 설치를 기다립니다"
  if ! NVIM_APPNAME=$1 HEES_SYNC=$2 HEES_SYNC_PLUGINS=${3:-} "$exe" --headless --cmd "luafile $sync"; then
    warn "동기화가 실패로 끝났습니다. nvk 를 실행해 메시지를 확인하세요."
  fi
  echo
}
