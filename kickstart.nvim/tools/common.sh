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
