#!/usr/bin/env bash
# 이 저장소의 Neovim 플러그인(overlay) 설치·업데이트·제거 (Linux/macOS).
#
# overlay/ 의 파일을 kickstart.nvim 설정 폴더에 복사합니다. init.lua 는 건드리지 않으므로 kickstart 를
# 어떻게 설치했든(require 'custom.plugins' 줄이 없어도) 동작하고, kickstart 를 업데이트해도 충돌하지 않습니다.
#   plugin/hees.lua               진입점 (Neovim 이 init.lua 다음에 자동으로 불러옴)
#   lua/hees/colors.lua           색상 테마 Catppuccin Latte
#   lua/hees/ui.lua               bufferline(탭 클릭/가운데 클릭 닫기/우클릭 메뉴), statuscol(줄 번호 클릭 중단점)
#   lua/hees/menu.lua             마우스·키보드 겸용 다단계 메뉴
#   lua/hees/context.lua          우클릭 메뉴 내용 (편집기 / 탐색기 / 버퍼 탭)
#   lua/hees/nes/                 NES: Claude / Codex / Gemini CLI 로 다음 편집 제안
#
#   install   파일 복사 + 필요한 플러그인(catppuccin, bufferline, statuscol, window-picker) 설치
#   update    파일 다시 복사(이전 파일은 지움) + 그 플러그인들만 업데이트
#   remove    파일과 플러그인 제거 (NES 기록·설정이 있는 data/ 는 --purge 일 때만 삭제)
#   status    설치 여부와 overlay 와의 차이
#
# 옵션: --app <이름> --no-sync --purge

TAG=plugins
. "$(dirname "${BASH_SOURCE[0]}")/tools/common.sh"

OVERLAY=$HERE/overlay
# Plugins the overlay adds with vim.pack (kept in sync with overlay/lua/hees/colors.lua, ui.lua, window_picker.lua).
PACK_PLUGINS=(catppuccin bufferline.nvim statuscol.nvim nvim-window-picker)
# Paths the overlay owns inside the config. lua/custom/plugins/hees.lua is the old entry point;
# it is listed so updates delete it and the overlay isn't loaded twice.
OWNED=(plugin/hees.lua lua/hees lua/custom/plugins/hees.lua)
EXCLUDED=("${OWNED[@]}" data/)

usage() { sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

CMD=${1:-help}
[ $# -gt 0 ] && shift
OPT_APP= OPT_NO_SYNC= OPT_PURGE=
while [ $# -gt 0 ]; do
  case "$1" in
  --app) OPT_APP=$2; shift ;;
  --no-sync) OPT_NO_SYNC=1 ;;
  --purge) OPT_PURGE=1 ;;
  -h | --help) CMD=help ;;
  *) fail "모르는 옵션: $1" ;;
  esac
  shift
done
APP=$(app_name "$OPT_APP")
CFG=$(config_dir "$APP")

require_kickstart() { [ -f "$CFG/init.lua" ] || fail "$CFG 에 kickstart.nvim 이 없습니다. 먼저 ./kickstart.sh install 을 실행하세요."; }

remove_owned() {
  local rel
  for rel in "${OWNED[@]}"; do rm -rf "${CFG:?}/$rel"; done
}

# Keep overlay files out of `git status` in the kickstart clone so kickstart updates stay clean.
set_git_exclude() {
  local exclude=$CFG/.git/info/exclude p
  [ -d "$(dirname "$exclude")" ] || return 0
  touch "$exclude"
  for p in "${EXCLUDED[@]}"; do grep -qxF "$p" "$exclude" || printf '%s\n' "$p" >>"$exclude"; done
}

copy_overlay() {
  remove_owned
  cp -R "$OVERLAY/." "$CFG/"
  set_git_exclude
  say "overlay 파일 $(find "$OVERLAY" -type f | wc -l | tr -d ' ') 개 복사 → $CFG"
}

show_status() {
  local f rel missing=0 differ=0 p pack
  say "설정: $CFG"
  while IFS= read -r f; do
    rel=${f#"$OVERLAY"/}
    if [ ! -f "$CFG/$rel" ]; then
      missing=$((missing + 1)); warn "  없음   $rel"
    elif ! cmp -s "$f" "$CFG/$rel"; then
      differ=$((differ + 1)); warn "  다름   $rel"
    fi
  done < <(find "$OVERLAY" -type f)
  [ $missing -eq 0 ] && [ $differ -eq 0 ] && say "설치된 파일이 overlay 와 같습니다"
  pack=$(data_dir "$APP")/site/pack/core/opt
  for p in "${PACK_PLUGINS[@]}"; do
    if [ -d "$pack/$p" ]; then say "  플러그인 $p : 설치됨"; else say "  플러그인 $p : 없음"; fi
  done
}

case "$CMD" in
install)
  require_kickstart
  copy_overlay
  [ -n "$OPT_NO_SYNC" ] || run_sync "$APP" install
  say "완료. 우클릭 또는 <Space>m 으로 메뉴, <Space>a 로 NES 를 쓸 수 있습니다."
  ;;
update)
  require_kickstart
  copy_overlay
  [ -n "$OPT_NO_SYNC" ] || run_sync "$APP" update "$(IFS=,; echo "${PACK_PLUGINS[*]}")"
  say "업데이트 완료"
  ;;
remove)
  require_kickstart
  remove_owned
  say "overlay 파일 삭제"
  names=$(printf "'%s'," "${PACK_PLUGINS[@]}")
  NVIM_APPNAME=$APP "$(require_nvim)" --headless -c "lua pcall(vim.pack.del, { ${names%,} })" -c 'qa!'
  say "플러그인 삭제: ${PACK_PLUGINS[*]}"
  if [ -n "$OPT_PURGE" ] && [ -d "$CFG/data" ]; then
    rm -rf "${CFG:?}/data"
    say "삭제: $CFG/data"
  fi
  ;;
status) show_status ;;
*) usage ;;
esac
