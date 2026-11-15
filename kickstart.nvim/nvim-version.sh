#!/usr/bin/env bash
# Neovim 설치·업데이트·버전 교체 (Linux/macOS).
#
# 버전은 이 폴더의 versions/<이름>/ 에 나란히 설치되고, versions/current 심볼릭 링크가 사용 중인 버전을 가리킵니다.
# 버전을 고를 때 ~/.local/bin/nvim → versions/current/bin/nvim 링크를 만들어 그냥 `nvim` 으로 실행되게 합니다.
# 시스템에 설치된 Neovim 은 건드리지 않습니다.
#
#   install <stable|nightly|vX.Y.Z>    공식 릴리스 받기
#   install --build <git ref>          소스에서 빌드 (git, cmake, C 컴파일러, gettext 필요)
#   install --from <URL|파일|폴더>     다른 곳에서 빌드된 것 가져오기 (.tar.gz/.zip 또는 bin/nvim 이 있는 폴더)
#   use <이름>                         사용할 버전 바꾸기
#   list [--remote]                    설치된 버전 (--remote: GitHub 릴리스 목록)
#   update                             최신 안정판을 설치하고 그 버전으로 바꾸기
#   remove <이름> [--force]            버전 삭제
#   current                            사용 중인 버전
#   path / unpath                      ~/.local/bin/nvim 링크 만들기 / 지우기
#
# 옵션: --name <이름> 설치 이름 지정, --use 설치 후 전환, --force 같은 이름 덮어쓰기, --generator <cmake 생성기>,
#       --no-path ~/.local/bin/nvim 링크를 만들지 않음
#
#   ./nvim-version.sh install stable
#   ./nvim-version.sh install --build master --use
#   ./nvim-version.sh install --from https://example.com/nvim-linux-x86_64.tar.gz --name team-build

TAG=nvim-version
. "$(dirname "${BASH_SOURCE[0]}")/tools/common.sh"

REPO=neovim/neovim
CURRENT=$VERSIONS/current
TMP=$VERSIONS/.tmp

LINK=$HOME/.local/bin/nvim

usage() { sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ~/.local/bin/nvim → versions/current/bin/nvim. The link target never changes, so switching versions keeps it valid.
link_path() {
  local target=$CURRENT/bin/nvim
  if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
    warn "$LINK 가 링크가 아닌 파일이라 건드리지 않습니다. 직접 옮긴 뒤 ./nvim-version.sh path 를 실행하세요."
    return
  fi
  mkdir -p "$(dirname "$LINK")"
  ln -sfn "$target" "$LINK"
  say "링크: $LINK → $target"
  hash -r
  local found
  found=$(command -v nvim || true)
  if [ "$found" != "$LINK" ]; then
    warn "PATH 에서 ${found:-다른 nvim} 이 먼저 잡힙니다. 셸 설정(~/.bashrc 등)에 다음 줄을 넣고 새 셸을 여세요:"
    warn '  export PATH="$HOME/.local/bin:$PATH"'
  fi
}

unlink_path() {
  if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$CURRENT/bin/nvim" ]; then
    rm -f "$LINK"
    say "삭제: $LINK"
  else
    say "$LINK 는 이 스크립트가 만든 링크가 아닙니다"
  fi
}

asset_name() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  case "$os/$arch" in
  Linux/x86_64) echo nvim-linux-x86_64.tar.gz ;;
  Linux/aarch64 | Linux/arm64) echo nvim-linux-arm64.tar.gz ;;
  Darwin/arm64) echo nvim-macos-arm64.tar.gz ;;
  Darwin/x86_64) echo nvim-macos-x86_64.tar.gz ;;
  *) fail "이 플랫폼용 공식 릴리스가 없습니다 ($os/$arch). --build 나 --from 을 쓰세요." ;;
  esac
}

# Releases before 0.10.4 used nvim-linux64.tar.gz.
legacy_asset_name() { [ "$(uname -s)/$(uname -m)" = Linux/x86_64 ] && echo nvim-linux64.tar.gz; }

download() { # url dest
  say "다운로드 $1"
  if have curl; then
    curl -fL --retry 2 --progress-bar -o "$2" "$1"
  elif have wget; then
    wget -q --show-progress -O "$2" "$1"
  else
    fail "curl 이나 wget 이 필요합니다"
  fi
}

github_api() { # path
  if have curl; then curl -fsSL "https://api.github.com/repos/$REPO/$1"; else wget -qO- "https://api.github.com/repos/$REPO/$1"; fi
}

extract() { # archive dest
  mkdir -p "$2"
  case "$1" in
  *.tar.gz | *.tgz | *.tar.xz | *.tar.zst | *.tar) tar -xf "$1" -C "$2" ;;
  *.zip)
    have unzip || fail "unzip 이 필요합니다"
    unzip -q "$1" -d "$2"
    ;;
  *) fail "모르는 압축 형식입니다: $1 (.tar.gz, .zip 지원)" ;;
  esac
}

# The folder holding bin/nvim inside an extracted archive or build output.
find_root() {
  local exe
  exe=$(find "$1" -type f -path '*/bin/nvim' -perm -u+x 2>/dev/null | head -n1)
  [ -n "$exe" ] && dirname "$(dirname "$exe")"
}

version_label() { "$1/bin/nvim" --version | head -n1 | awk '{print $2}'; }

current_name() { [ -L "$CURRENT" ] && basename "$(readlink "$CURRENT")"; }

set_current() {
  local dir=$VERSIONS/$1
  [ -x "$dir/bin/nvim" ] || fail "설치되지 않은 버전입니다: $1 (list 로 확인)"
  ln -sfn "$1" "$CURRENT"
  say "사용 버전 → $1"
  [ -n "$OPT_NO_PATH" ] || link_path
}

new_tmp() {
  mkdir -p "$TMP"
  mktemp -d "$TMP/XXXXXXXX"
}

# Move a staged Neovim into versions/<name>; prints the name on stdout (messages go to stderr).
add_version() { # staged suffix
  local root label name dest
  root=$(find_root "$1") || true
  [ -n "$root" ] || fail "$1 안에 bin/nvim 이 없습니다"
  label=$(version_label "$root")
  name=${OPT_NAME:-$label$2}
  name=${name//\//_}
  dest=$VERSIONS/$name
  if [ -e "$dest" ]; then
    if [ -z "$OPT_FORCE" ]; then
      say "$name 은 이미 설치되어 있습니다 (덮어쓰려면 --force)" >&2
      printf '%s' "$name"
      return
    fi
    [ "$(current_name)" = "$name" ] && rm -f "$CURRENT"
    rm -rf "$dest"
  fi
  mv "$root" "$dest"
  say "설치 완료: $name ($label) → $dest" >&2
  printf '%s' "$name"
}

resolve_tag() {
  case "${1:-stable}" in
  stable | latest | '')
    github_api releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1 | grep . ||
      { warn "GitHub API에 접근하지 못해 stable 태그로 받습니다"; echo stable; }
    ;;
  nightly) echo nightly ;;
  [0-9]*) echo "v$1" ;;
  *) echo "$1" ;;
  esac
}

install_release() {
  local tag work asset legacy
  tag=$(resolve_tag "${1:-}")
  if [[ $tag == v[0-9]* ]] && [ -z "$OPT_NAME" ] && [ -z "$OPT_FORCE" ] && [ -x "$VERSIONS/$tag/bin/nvim" ]; then
    say "$tag 은 이미 설치되어 있습니다" >&2
    printf '%s' "$tag"
    return
  fi
  work=$(new_tmp)
  trap 'rm -rf "$work"' RETURN
  asset=$(asset_name)
  if ! download "https://github.com/$REPO/releases/download/$tag/$asset" "$work/$asset" >&2; then
    legacy=$(legacy_asset_name) || true
    [ -n "$legacy" ] || fail "다운로드 실패: $tag/$asset"
    asset=$legacy
    download "https://github.com/$REPO/releases/download/$tag/$asset" "$work/$asset" >&2
  fi
  extract "$work/$asset" "$work/x"
  add_version "$work/x" ''
}

install_from() {
  local src=$1 work leaf
  work=$(new_tmp)
  trap 'rm -rf "$work"' RETURN
  if [[ $src =~ ^https?:// ]]; then
    leaf=$(basename "${src%%\?*}")
    download "$src" "$work/$leaf" >&2
    extract "$work/$leaf" "$work/x"
  elif [ -d "$src" ]; then
    say "폴더 복사 $src" >&2
    cp -a "$src" "$work/x"
  elif [ -f "$src" ]; then
    extract "$src" "$work/x"
  else
    fail "찾을 수 없습니다: $src"
  fi
  add_version "$work/x" -custom
}

install_build() {
  local ref=$1 src=$VERSIONS/.src/neovim work rev gen=()
  have git || fail "git 이 필요합니다"
  have cmake || fail "cmake 가 필요합니다 (예: sudo apt install cmake ninja-build gettext build-essential)"
  if [ ! -d "$src/.git" ]; then
    say "neovim 소스 받는 중" >&2
    git clone --filter=blob:none "https://github.com/$REPO.git" "$src" >&2
  else
    git -C "$src" fetch --tags --force origin >&2
  fi
  # A branch name builds the remote branch head; tags and commits are used as given.
  if git -C "$src" rev-parse --verify --quiet "origin/$ref" >/dev/null; then rev=origin/$ref; else rev=$ref; fi
  git -C "$src" checkout --force --detach "$rev" >&2
  if [ -n "$OPT_GENERATOR" ]; then gen=(-G "$OPT_GENERATOR"); elif have ninja; then gen=(-G Ninja); fi
  work=$(new_tmp)
  trap 'rm -rf "$work"' RETURN
  (
    cd "$src"
    rm -rf .deps build
    set -x
    cmake -S cmake.deps -B .deps "${gen[@]}" -D CMAKE_BUILD_TYPE=Release
    cmake --build .deps
    cmake -B build "${gen[@]}" -D CMAKE_BUILD_TYPE=Release
    cmake --build build
    cmake --install build --prefix "$work/x"
  ) >&2 || fail "빌드 실패"
  add_version "$work/x" -build
}

list_versions() {
  local cur d mark any=
  cur=$(current_name || true)
  mkdir -p "$VERSIONS"
  for d in "$VERSIONS"/*/; do
    [ -d "$d" ] || continue
    d=$(basename "$d")
    [ "$d" = current ] && continue
    any=1
    mark=' '
    [ "$d" = "$cur" ] && mark='*'
    echo "$mark $d"
  done
  [ -n "$any" ] || say "설치된 버전이 없습니다. install stable 로 설치하세요."
  if [ -n "$OPT_REMOTE" ]; then
    echo
    say "GitHub 릴리스:"
    github_api 'releases?per_page=15' | sed -n 's/.*"tag_name": *"\([^"]*\)".*/  \1/p'
  fi
}

CMD=${1:-help}
[ $# -gt 0 ] && shift
TARGET= OPT_BUILD= OPT_FROM= OPT_NAME= OPT_GENERATOR= OPT_REMOTE= OPT_USE= OPT_FORCE= OPT_NO_PATH=
while [ $# -gt 0 ]; do
  case "$1" in
  --no-path) OPT_NO_PATH=1 ;;
  --build) OPT_BUILD=$2; shift ;;
  --from) OPT_FROM=$2; shift ;;
  --name) OPT_NAME=$2; shift ;;
  --generator) OPT_GENERATOR=$2; shift ;;
  --remote) OPT_REMOTE=1 ;;
  --use) OPT_USE=1 ;;
  --force) OPT_FORCE=1 ;;
  -h | --help) CMD=help ;;
  -*) fail "모르는 옵션: $1" ;;
  *) TARGET=$1 ;;
  esac
  shift
done

mkdir -p "$VERSIONS"
case "$CMD" in
install)
  if [ -n "$OPT_BUILD" ]; then
    name=$(install_build "$OPT_BUILD")
  elif [ -n "$OPT_FROM" ]; then
    name=$(install_from "$OPT_FROM")
  else
    name=$(install_release "$TARGET")
  fi
  if [ -n "$OPT_USE" ] || [ -z "$(current_name || true)" ]; then set_current "$name"; fi
  ;;
use)
  [ -n "$TARGET" ] || fail "use <이름> — 이름은 list 로 확인하세요"
  set_current "$TARGET"
  ;;
update)
  name=$(install_release stable)
  if [ "$(current_name || true)" = "$name" ]; then say "이미 최신 안정판입니다 ($name)"; else set_current "$name"; fi
  ;;
remove)
  [ -n "$TARGET" ] || fail "remove <이름>"
  case "$TARGET" in current | .tmp | .src | */* | '') fail "없는 버전입니다: $TARGET" ;; esac
  [ -d "$VERSIONS/$TARGET" ] || fail "없는 버전입니다: $TARGET"
  if [ "$(current_name || true)" = "$TARGET" ]; then
    [ -n "$OPT_FORCE" ] || fail "$TARGET 은 사용 중입니다. 다른 버전으로 use 하거나 --force 를 주세요."
    rm -f "$CURRENT"
  fi
  rm -rf "${VERSIONS:?}/$TARGET"
  say "삭제: $TARGET"
  ;;
list) list_versions ;;
path) link_path ;;
unpath) unlink_path ;;
current) current_name || say "선택된 버전이 없습니다" ;;
*) usage ;;
esac
