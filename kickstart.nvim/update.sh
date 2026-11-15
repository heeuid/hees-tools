#!/usr/bin/env bash
# 한 번에 최신으로 (Linux/macOS): Neovim 최신 안정판 → kickstart.nvim upstream → 이 저장소의 플러그인 → 플러그인/LSP/파서.
#
# 각 단계는 따로 실행할 수도 있습니다.
#   ./nvim-version.sh update      Neovim 최신 안정판 설치 후 전환
#   ./kickstart.sh update         kickstart.nvim pull + 플러그인/LSP/파서 업데이트
#   ./plugins.sh update           overlay 파일 갱신 + 그 플러그인 업데이트
#
# 옵션: --app <이름>, --skip-nvim (nightly 나 직접 빌드한 버전을 계속 쓸 때), --force (kickstart 파일의 직접 수정을 버림)

TAG=update
. "$(dirname "${BASH_SOURCE[0]}")/tools/common.sh"

opt_app= skip_nvim= force=
while [ $# -gt 0 ]; do
  case "$1" in
  --app) opt_app=$2; shift ;;
  --skip-nvim) skip_nvim=1 ;;
  --force) force=--force ;;
  *) fail "모르는 옵션: $1" ;;
  esac
  shift
done
APP=$(app_name "$opt_app")

if [ -n "$skip_nvim" ]; then
  say "1/4 Neovim: 건너뜀"
else
  say "1/4 Neovim"
  "$HERE/nvim-version.sh" update
fi

say "2/4 kickstart.nvim"
"$HERE/kickstart.sh" update --app "$APP" --no-sync $force

say "3/4 플러그인 (overlay)"
"$HERE/plugins.sh" update --app "$APP" --no-sync

say "4/4 플러그인/LSP/파서 업데이트"
run_sync "$APP" update
say "끝"
