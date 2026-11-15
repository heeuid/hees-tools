#!/usr/bin/env bash
# 한 번에 설치 (Linux/macOS): Neovim → kickstart.nvim → 이 저장소의 플러그인. 끝나면 그냥 `nvim` 으로 실행합니다.
#
# 각 단계는 따로 실행할 수도 있습니다.
#   ./nvim-version.sh install stable     Neovim (versions/ 아래 + ~/.local/bin/nvim 링크, 시스템 Neovim 은 그대로)
#   ./kickstart.sh install               kickstart.nvim (~/.config/nvim, 기존 설정은 *.bak-<시각> 으로 백업)
#   ./plugins.sh install                 우클릭 메뉴, 클릭 가능한 탭/거터, NES
#
# 옵션은 kickstart.sh install 로 그대로 넘어갑니다: --app <이름> --nerd-font --yes --skip-deps --force
# --no-path 는 ~/.local/bin/nvim 링크를 만들지 않습니다.
#
#   ./install.sh --nerd-font --yes

TAG=install
. "$(dirname "${BASH_SOURCE[0]}")/tools/common.sh"

app= prev= no_path= pass=()
for a in "$@"; do
  [ "$prev" = --app ] && app=$a
  prev=$a
  if [ "$a" = --no-path ]; then no_path=--no-path; else pass+=("$a"); fi
done

say "1/3 Neovim"
selected=$VERSIONS/current/bin/nvim
if [ ! -x "$selected" ] || [ "$(nvim_version "$selected" | awk '{print ($1 > 0 || $2 >= 12)}')" != 1 ]; then
  "$HERE/nvim-version.sh" install stable --use $no_path
else
  say "이미 있음: $selected"
  [ -n "$no_path" ] || "$HERE/nvim-version.sh" path
fi

say "2/3 kickstart.nvim"
"$HERE/kickstart.sh" install --no-sync "${pass[@]}"

say "3/3 플러그인 (overlay)"
"$HERE/plugins.sh" install ${app:+--app "$app"}

if [ -z "$app" ] || [ "$app" = nvim ]; then say "끝. 실행: nvim"; else say "끝. 실행: NVIM_APPNAME=$app nvim"; fi
