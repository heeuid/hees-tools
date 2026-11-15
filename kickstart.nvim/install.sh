#!/usr/bin/env bash
# 한 번에 설치 (Linux/macOS): Neovim → kickstart.nvim → 이 저장소의 플러그인.
#
# 각 단계는 따로 실행할 수도 있습니다.
#   ./nvim-version.sh install stable     Neovim (versions/ 아래, 시스템 Neovim 은 그대로)
#   ./kickstart.sh install               kickstart.nvim (기본 NVIM_APPNAME=kickstart)
#   ./plugins.sh install                 우클릭 메뉴, 클릭 가능한 탭/거터, NES
#
# 옵션은 kickstart.sh install 로 그대로 넘어갑니다: --app --default --nerd-font --yes --skip-deps --link-bin --force
#
#   ./install.sh --nerd-font --yes --link-bin

TAG=install
. "$(dirname "${BASH_SOURCE[0]}")/tools/common.sh"

app=
prev=
for a in "$@"; do
  [ "$prev" = --app ] && app=$a
  [ "$a" = --default ] && app=nvim
  prev=$a
done

say "1/3 Neovim"
exe=$(find_nvim)
if [ -z "$exe" ] || [ "$(nvim_version "$exe" | awk '{print ($1 > 0 || $2 >= 12)}')" != 1 ]; then
  "$HERE/nvim-version.sh" install stable --use
else
  say "이미 있음: $exe"
fi

say "2/3 kickstart.nvim"
"$HERE/kickstart.sh" install --no-sync "$@"

say "3/3 플러그인 (overlay)"
"$HERE/plugins.sh" install ${app:+--app "$app"}

say "끝. 실행: $HERE/bin/nvk"
