#!/usr/bin/env bash
# kickstart.nvim 설치·업데이트 (Linux/macOS).
#
#   install   필요 도구 점검 → kickstart.nvim clone → kickstart 자체 기능 켜기 → 헤드리스로 플러그인 설치
#   update    kickstart.nvim 을 upstream 최신으로 pull → 다시 켜기 → 플러그인/LSP/파서 업데이트
#   status    설치 위치, 버전, 로컬 수정 여부
#
# 켜는 kickstart 기능 (tools/patch-kickstart.lua):
#   init.lua 끝의 kickstart.plugins.debug, kickstart.plugins.neo-tree, custom.plugins
#   debug.lua 의 중단점 아이콘 블록, DAP 어댑터 codelldb(C/C++/Rust)·python(debugpy) 추가
#   --nerd-font 면 vim.g.have_nerd_font = true
#
# 기본 위치는 NVIM_APPNAME=kickstart (~/.config/kickstart) 로 기존 ~/.config/nvim 과 나란히 둡니다.
# --default 를 주면 ~/.config/nvim 에 설치하되 기존 nvim 설정/데이터/상태/캐시를 *.bak-<시각> 으로 옮겨 둡니다.
#
# 옵션: --app <이름> --default --nerd-font --repo <url> --yes(없는 도구 자동 설치) --skip-deps
#       --link-bin(~/.local/bin/nvk 링크) --no-sync --force
#
#   ./kickstart.sh install --nerd-font --yes
#   ./kickstart.sh update

TAG=kickstart
. "$(dirname "${BASH_SOURCE[0]}")/tools/common.sh"

PATCH=$HERE/tools/patch-kickstart.lua
PATCHED_FILES=(init.lua lua/kickstart/plugins/debug.lua)

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

CMD=${1:-help}
[ $# -gt 0 ] && shift
OPT_APP= OPT_DEFAULT= OPT_NERD= OPT_YES= OPT_SKIP_DEPS= OPT_LINK= OPT_NO_SYNC= OPT_FORCE=
REPO=https://github.com/nvim-lua/kickstart.nvim.git
while [ $# -gt 0 ]; do
  case "$1" in
  --app) OPT_APP=$2; shift ;;
  --default) OPT_DEFAULT=1 ;;
  --nerd-font) OPT_NERD=1 ;;
  --repo) REPO=$2; shift ;;
  --yes) OPT_YES=1 ;;
  --skip-deps) OPT_SKIP_DEPS=1 ;;
  --link-bin) OPT_LINK=1 ;;
  --no-sync) OPT_NO_SYNC=1 ;;
  --force) OPT_FORCE=1 ;;
  -h | --help) CMD=help ;;
  *) fail "모르는 옵션: $1" ;;
  esac
  shift
done
[ -n "$OPT_DEFAULT" ] && OPT_APP=nvim
APP=$(app_name "$OPT_APP")
CFG=$(config_dir "$APP")

# command(s) that satisfy each tool | apt | dnf | pacman | brew package
DEPS=(
  "git|git|git|git|git"
  "make|make|make|make|make"
  "gcc cc clang|build-essential|gcc|gcc|gcc"
  "unzip|unzip|unzip|unzip|unzip"
  "rg|ripgrep|ripgrep|ripgrep|ripgrep"
  "fd fdfind|fd-find|fd-find|fd|fd"
  "tree-sitter|tree-sitter-cli|tree-sitter-cli|tree-sitter-cli|tree-sitter-cli"
)

pkg_manager() {
  for pm in apt-get dnf pacman brew; do have "$pm" && { echo "$pm"; return; }; done
}

check_deps() {
  local pm col entry cmds found c pkgs=() missing=0 missing_git=
  pm=$(pkg_manager || true)
  case "$pm" in apt-get) col=2 ;; dnf) col=3 ;; pacman) col=4 ;; brew) col=5 ;; *) col= ;; esac
  for entry in "${DEPS[@]}"; do
    cmds=$(cut -d'|' -f1 <<<"$entry")
    found=
    for c in $cmds; do have "$c" && { found=$c; break; }; done
    if [ -n "$found" ]; then
      say "  ok      $found"
    else
      warn "  없음    $cmds"
      missing=$((missing + 1))
      [ "$cmds" = git ] && missing_git=1
      [ -n "$col" ] && pkgs+=("$(cut -d'|' -f"$col" <<<"$entry")")
    fi
  done
  [ "$missing" -eq 0 ] && return
  if [ -n "$OPT_YES" ] && [ -n "$pm" ]; then
    say "$pm 로 설치: ${pkgs[*]}"
    case "$pm" in
    apt-get) sudo apt-get update && sudo apt-get install -y "${pkgs[@]}" ;;
    dnf) sudo dnf install -y "${pkgs[@]}" ;;
    pacman) sudo pacman -S --needed --noconfirm "${pkgs[@]}" ;;
    brew) brew install "${pkgs[@]}" ;;
    esac || warn "일부 패키지를 설치하지 못했습니다 (배포판에 tree-sitter-cli 가 없으면 npm i -g tree-sitter-cli 또는 cargo install tree-sitter-cli)"
  elif [ -n "$missing_git" ]; then
    fail "git 이 필요합니다. --yes 로 자동 설치하거나 직접 설치하세요."
  else
    warn "없는 도구는 --yes 로 자동 설치할 수 있습니다${pm:+ ($pm: ${pkgs[*]})}. 없어도 설치는 계속합니다."
  fi
}

is_kickstart_clone() { [ -d "$1/.git" ] && git -C "$1" remote get-url origin 2>/dev/null | grep -q kickstart; }

backup() {
  [ -e "$1" ] || return 0
  local dest
  dest=$1.bak-$(date +%Y%m%d-%H%M%S)
  mv "$1" "$dest"
  say "백업: $1 → $dest"
}

patch() { "$(require_nvim)" -l "$PATCH" "$CFG" "$@"; }

do_install() {
  say "설치 위치: $CFG (NVIM_APPNAME=$APP)"
  if [ -z "$OPT_SKIP_DEPS" ]; then
    say "필요 도구 점검"
    check_deps
  fi
  if [ -z "$(find_nvim)" ]; then
    say "Neovim 이 없어 최신 안정판을 설치합니다"
    "$HERE/nvim-version.sh" install stable
  fi
  require_nvim >/dev/null

  if is_kickstart_clone "$CFG"; then
    say "이미 kickstart.nvim 이 있습니다 — clone 은 건너뛰고 설정만 다시 적용합니다 (최신으로는 update)"
  else
    if [ "$APP" = nvim ]; then
      backup "$CFG"
      backup "$(data_dir nvim)"
      backup "$(state_dir nvim)"
      backup "$(cache_dir nvim)"
    elif [ -e "$CFG" ]; then
      [ -n "$OPT_FORCE" ] || fail "$CFG 가 이미 있고 kickstart.nvim clone 이 아닙니다. 다른 --app 을 쓰거나 --force 로 백업 후 설치하세요."
      backup "$CFG"
    fi
    git clone "$REPO" "$CFG"
  fi

  printf '%s\n' "$APP" >"$APPNAME_FILE"
  if [ -n "$OPT_NERD" ]; then patch --nerd-font; else patch; fi
  if [ -n "$OPT_LINK" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$HERE/bin/nvk" "$HOME/.local/bin/nvk"
    say "링크: ~/.local/bin/nvk → $HERE/bin/nvk"
  fi
  [ -n "$OPT_NO_SYNC" ] || run_sync "$APP" install
  say "완료. 실행: $HERE/bin/nvk"
}

do_update() {
  is_kickstart_clone "$CFG" || fail "$CFG 에 kickstart.nvim 이 없습니다. 먼저 install 하세요."
  require_nvim >/dev/null
  if ! patch --check && [ -z "$OPT_FORCE" ]; then
    fail "위 파일에 직접 고친 내용이 있습니다. 커밋하거나 옮긴 뒤 다시 실행하세요 (--force 는 그 수정을 버립니다)."
  fi
  local nerd=
  grep -q 'vim.g.have_nerd_font = true' "$CFG/init.lua" && nerd=1
  git -C "$CFG" checkout -- "${PATCHED_FILES[@]}"
  git -C "$CFG" pull --ff-only
  if [ -n "$nerd$OPT_NERD" ]; then patch --nerd-font; else patch; fi
  [ -n "$OPT_NO_SYNC" ] || run_sync "$APP" update
  say "업데이트 완료"
}

do_status() {
  local exe
  say "NVIM_APPNAME: $APP"
  say "설정: $CFG"
  exe=$(find_nvim)
  if [ -n "$exe" ]; then say "Neovim: $exe ($("$exe" --version | head -n1))"; else warn "Neovim: 없음"; fi
  if is_kickstart_clone "$CFG"; then
    say "kickstart: $(git -C "$CFG" log -1 --format='%h %cs %s')"
    patch --check && say "로컬 수정: 없음 (이 설정의 패치만 있음)"
  else
    warn "kickstart: 설치되지 않음"
  fi
  return 0
}

case "$CMD" in
install) do_install ;;
update) do_update ;;
status) do_status ;;
*) usage ;;
esac
