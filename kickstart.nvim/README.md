# kickstart.nvim + 마우스 메뉴 + NES

[nvim-lua/kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)을 그대로 설치하고, kickstart에 없는 기능만 플러그인으로 더합니다.

- kickstart가 가진 기능은 kickstart 것을 씁니다: 탐색기(`kickstart.plugins.neo-tree`), 디버거(`kickstart.plugins.debug`), LSP/검색/git 키.
- 더하는 것: 우클릭 메뉴, 클릭 가능한 버퍼 탭·거터, NES(Claude / Codex / Gemini), Catppuccin Latte 색상 테마.
- LSP는 C/C++, Rust, Python, Lua, Markdown, TOML, JSON, YAML, Bash가 켜집니다(kickstart의 서버 목록을 켜는 방식).
- 설치가 끝나면 그냥 `nvim`으로 실행합니다. 설정은 Neovim 기본 경로에, 실행 파일은 PATH 맨 앞에 들어갑니다.
- 기존 설정(예: LazyVim)은 덮어쓰지 않고 `*.bak-<시각>`으로 옮겨 둡니다. 다른 곳에 설치된 Neovim 파일은 건드리지 않습니다.

kickstart 최신판은 플러그인 관리자로 `vim.pack`을 쓰므로 **Neovim 0.12 이상**이 필요합니다.

## 스크립트

모든 스크립트는 Windows(`.ps1`)용과 Linux/macOS(`.sh`)용이 따로 있고 기능이 같습니다.

| 대상 | Windows | Linux/macOS | 하는 일 |
|---|---|---|---|
| Neovim | `nvim-version.ps1` | `nvim-version.sh` | 설치·업데이트·버전 교체 |
| kickstart.nvim | `kickstart.ps1` | `kickstart.sh` | 설치·업데이트·상태 |
| 이 저장소의 플러그인 | `plugins.ps1` | `plugins.sh` | 설치·업데이트·제거·상태 |
| 전체 | `install.ps1` / `update.ps1` | `install.sh` / `update.sh` | 위 셋을 차례로 |
| (선택) 실행 | `bin\nvk.cmd` | `bin/nvk` | `-AppName`/`--app`으로 나란히 설치했을 때만 필요 |

### 처음 설치

```powershell
# Windows
.\install.ps1 -NerdFont -Yes   # -Yes: 없는 도구를 winget으로 설치
nvim                           # 새 터미널에서
```

```bash
# Linux/macOS
./install.sh --nerd-font --yes   # --yes: apt/dnf/pacman/brew로 설치
nvim
```

- **tree-sitter CLI**: kickstart의 nvim-treesitter가 문법 파서를 컴파일할 때 씁니다(없으면 문법 색칠이 동작하지 않음). C 컴파일러도 필요합니다.
  없으면 설치 스크립트가 옵션과 상관없이 직접 설치합니다. sudo나 패키지 매니저는 쓰지 않습니다.
  1. GitHub 공식 실행 파일(Linux/macOS `~/.local/bin`, Windows `%LOCALAPPDATA%\Programs\tree-sitter` + 사용자 PATH). 실제로 실행될 때만 씁니다.
     Linux 실행 파일은 glibc 2.39 이상(Ubuntu 24.04+)이 필요합니다.
  2. 그게 안 되면 `cargo install --locked tree-sitter-cli`(소스 빌드, 어느 배포판이든 동작, 몇 분).
  apt 패키지는 없거나 오래된 배포판이 많고, npm 패키지는 1번과 같은 실행 파일이라 쓰지 않습니다.
- **설정 위치**: Neovim 기본 경로 Windows `%LOCALAPPDATA%\nvim`, Linux `~/.config/nvim`.
  그 자리에 있던 설정·데이터는 `nvim.bak-<시각>`, `nvim-data.bak-<시각>`(Linux는 `~/.local/share`, `~/.local/state`, `~/.cache`의 `nvim`도)으로 옮겨 둡니다.
  되돌리려면 새 폴더를 지우고 `.bak-` 폴더 이름을 원래대로 바꾸면 됩니다.
- **`nvim` 실행 파일**: Windows는 `versions\current\bin`을 시스템 PATH 맨 앞에 넣습니다(관리자 확인 창 한 번).
  Windows는 시스템 PATH를 사용자 PATH보다 먼저 찾기 때문에, 시스템 PATH에 다른 Neovim이 있으면 이렇게 해야 새 버전이 실행됩니다.
  Linux는 `~/.local/bin/nvim` 링크를 만듭니다. 이 경로는 버전을 바꿔도 같으므로 한 번만 등록됩니다.
  `-NoPath`/`--no-path`로 끌 수 있고, 나중에 `nvim-version path` / `unpath`로 넣거나 뺄 수 있습니다.
- **나란히 설치**: `-AppName <이름>`/`--app <이름>`을 주면 기본 경로 대신 `<이름>` 폴더에 설치하고 기존 설정은 그대로 둡니다.
  이때는 `NVIM_APPNAME=<이름>`으로 실행하거나 `bin\nvk.cmd`/`bin/nvk`를 씁니다.
- `-NerdFont`/`--nerd-font`는 kickstart의 `vim.g.have_nerd_font = true`를 켭니다. Nerd Font가 아닌 글꼴에서는 켜지 마세요.
  꺼져 있으면 아이콘은 일반 유니코드 도형(▸ ✓ ● ◆)으로 표시합니다.

### 최신으로

```powershell
.\update.ps1              # Neovim 최신 안정판 + kickstart pull + 플러그인 + LSP/파서
.\update.ps1 -SkipNvim    # nightly나 직접 빌드한 Neovim을 계속 쓸 때
```

```bash
./update.sh
./update.sh --skip-nvim
```

`init.lua`나 `lua/kickstart/plugins/debug.lua`를 직접 고쳤으면 kickstart 업데이트는 멈추고 알려 줍니다.
내 설정은 `lua/custom/plugins/`에 새 파일로 두면 kickstart 업데이트와 충돌하지 않습니다.

### Neovim 버전

```powershell
.\nvim-version.ps1 install stable                 # 공식 릴리스 (stable | nightly | v0.12.6)
.\nvim-version.ps1 install -Build master -Use     # 소스에서 빌드 (git ref: 태그, 브랜치, 커밋)
.\nvim-version.ps1 install -From <URL|파일|폴더>  # 다른 곳에서 빌드한 것 (.zip/.tar.gz 또는 bin\nvim.exe 가 있는 폴더)
.\nvim-version.ps1 list -Remote                   # 설치된 버전(* 사용 중) + GitHub 릴리스
.\nvim-version.ps1 use v0.12.6
.\nvim-version.ps1 update                         # 최신 안정판 설치 후 전환
.\nvim-version.ps1 remove v0.12.5
```

Linux/macOS는 같은 명령을 `./nvim-version.sh install --build master --use`처럼 `--옵션` 형태로 씁니다.

- 설치 이름은 `nvim --version`의 버전입니다. 빌드는 `-build`, 가져온 것은 `-custom`이 붙습니다. `-Name`/`--name`으로 직접 정할 수 있습니다.
- 소스 빌드에 필요한 것: git, cmake, C 컴파일러(Windows는 Visual Studio Build Tools의 C++ 도구를 권장, Developer PowerShell에서 실행), Linux는 `gettext`, `ninja-build`도.
  ninja가 있으면 Ninja 생성기를 씁니다. `-Generator`/`--generator`로 바꿀 수 있습니다.
- 버전 폴더 위치는 환경 변수 `HEES_NVIM_VERSIONS`로 바꿀 수 있습니다.

### 플러그인만 (kickstart가 이미 깔려 있을 때)

```powershell
.\plugins.ps1 install | update | remove [-Purge] | status
```

`overlay/`의 파일을 kickstart 설정의 `plugin/hees.lua`, `lua/hees/`에 복사합니다. Neovim은 설정 폴더의
`plugin/*.lua`를 `init.lua` 다음에 자동으로 불러오므로, `init.lua`는 건드리지 않습니다. kickstart를 어떻게 설치했든
(`require 'custom.plugins'` 줄이 주석이든 없든) 동작합니다. 이 파일들은 kickstart clone의 `.git/info/exclude`에 들어가
kickstart의 `git status`에 나타나지 않습니다.

### 색상 테마와 LSP

- **색상**: [Catppuccin](https://github.com/catppuccin/nvim) Latte(밝은 테마). kickstart의 tokyonight 설정은 그대로 두고,
  이 플러그인이 그 다음에 `catppuccin-latte`로 바꿉니다. neo-tree, telescope, gitsigns, which-key, bufferline 색도 맞춥니다.
- **LSP**: kickstart `init.lua`의 `servers` 목록에서 켭니다. 서버는 처음 실행할 때 mason이 설치합니다.

  | 언어 | 서버 | |
  |---|---|---|
  | Lua | `lua_ls` | kickstart 기본 |
  | C/C++ | `clangd` | kickstart 예시 주석 해제 |
  | Rust | `rust_analyzer` | kickstart 예시 주석 해제 |
  | Python | `pyright` | kickstart 예시 주석 해제 |
  | Markdown | `marksman` | 추가 |
  | TOML / JSON / YAML / Bash | `taplo` / `jsonls` / `yamlls` / `bashls` | 추가 |

  목록은 `tools/patch-kickstart.lua`의 `LSP` 표에서 바꿉니다.

### 출력 기록

스크립트가 화면에 낸 모든 출력은 `logs/<시각>-<스크립트>.log`에도 남습니다(`install`이 부른 다른 스크립트 출력도 같은 파일에).
설치·업데이트가 끝나면 Neovim을 직접 띄워 확인한 결과를 요약합니다: 색상 테마, 내 플러그인 로드 여부, 플러그인 목록,
켜진 LSP별 담당 파일 형식과 설치 여부, mason 도구 목록.

## 마우스

| 위치 | 왼쪽 클릭 | 가운데 클릭 | 오른쪽 클릭 |
|---|---|---|---|
| 편집기 | 커서 이동 | — | 컨텍스트 메뉴 |
| 선택 영역 | — | — | 선택 영역 메뉴 (잘라내기/복사, 코드 액션, 선택 영역 NES, git stage) |
| 버퍼 탭 | 전환, ×로 닫기 | 닫기 | 탭 메뉴 (다른 탭 닫기, 고정, 분할로 열기…) |
| 줄 번호 | 중단점 토글 (Ctrl+클릭: 조건부) | 줄 복사 | 붙여넣기 (두 번: 줄 잘라내기) |
| git 표시 | hunk 미리보기 | hunk 되돌리기 | hunk stage |
| 진단 표시 | 메시지 보기 | 코드 액션 | — |
| 접기 열 | 접기/펴기 | — | — |
| 탐색기 | 열기 (더블클릭) | — | 파일 메뉴 (Open in ▸ 창 골라서/세로 분할/가로 분할/새 탭, 새 파일/폴더, 이름 변경, 삭제, 복사/잘라내기/붙여넣기, 경로, 시스템 탐색기) |
| 디버그 UI | 제어 버튼 (dap-ui) | — | — |

거터(줄 번호·git·진단·접기 열) 클릭은 [statuscol.nvim](https://github.com/luukvbaal/statuscol.nvim)의 기본 동작입니다.

### 탐색기에서 원하는 창에 열기

탐색기 안에서는 커서를 숨기고 줄 강조만으로 위치를 보여 줍니다(`:` 명령줄과 입력창에서는 커서가 보입니다).
줄 강조 색은 색상 테마의 선택(Visual) 색을 쓰고, 배경과 차이가 작으면(밝기 대비 1.5 미만) 글자 색을 섞어 더 진하게 합니다.
글자가 읽히는 범위(대비 4.5) 안에서만 바꾸고, 색상 테마를 바꾸면 다시 계산합니다. 어떤 테마에서도 위치가 잘 보이도록 하기 위함입니다.

| 키 | 우클릭 메뉴 | 동작 |
|---|---|---|
| `l`, `→` | — | 디렉토리: 펼치기 (이미 펼쳐져 있으면 첫 항목으로) / 파일: 열기 |
| `h`, `←` | — | 펼쳐진 디렉토리: 접기 / 파일이나 닫힌 디렉토리: 상위 디렉토리를 접고 그리로 이동 |
| `Enter`, 더블클릭 | Open | 마지막으로 있던 편집 창에 열기 (원하는 창을 먼저 클릭해 두면 그 창) |
| `w` | Open in ▸ Pick window… | 창마다 큰 글자가 뜸 → 글자를 누르거나 **그 창을 클릭** (`Esc` 취소). 편집 창이 하나면 바로 엶 |
| `s` / `S` | Open in ▸ Vertical / Horizontal split | 세로 / 가로로 나눠서 열기 |
| `t` | Open in ▸ New tab | 새 탭에 열기 |

`w`는 kickstart의 neo-tree에 원래 있는 키이고, 이 설정은 그 키에 필요한
[nvim-window-picker](https://github.com/s1n7ax/nvim-window-picker)만 설치합니다.
`h`/`l`은 탐색기 창 안에서만 바뀝니다(neo-tree 기본값의 `l` 미리보기 창 이동은 대신 쓰지 않습니다).

메뉴는 키보드로도 똑같이 씁니다. `<Space>m` 또는 `Shift+F10`으로 열고, `j`/`k`/방향키로 움직이고, `Enter`/`l`로
실행하거나 하위 메뉴를 열고, `h`로 한 단계 뒤로, `Esc`로 닫습니다. 마우스를 올리면 하위 메뉴가 열립니다.
쓸 수 없는 항목(LSP 미연결, 디버그 세션 없음 등)은 흐리게 표시되고 선택되지 않습니다. 항목 오른쪽에는 같은 일을 하는 키가 나옵니다.

```
편집기 메뉴                     LSP ▸            Debug ▸
  Paste            P             Rename symbol    Start debugging  F5
  Edit           ▸               Code action      Run to cursor
  ─────────                      Format buffer    Terminate
  Go to definition grd           Hover            Step           ▸
  Find references  grr           ─────            ─────
  ─────────                      Go to        ▸   Toggle breakpoint Space b
  LSP            ▸               Symbols      ▸   Breakpoints    ▸
  Debug          ▸               Diagnostics  ▸   ─────
  AI next edit   ▸               ─────            Toggle debug UI  F7
  Git            ▸               Inlay hints      Toggle REPL
  Search         ▸               Restart LSP
  ─────────                      LSP health
  File           ▸
```

## NES (Next Edit Suggestion)

최근 편집(diff)과 커서 주변 코드를 Claude, Codex, Gemini CLI 중 하나에 보내 다음 편집을 제안받습니다.
제안은 화면에 diff로 표시되고(지울 줄은 빨강, 넣을 줄은 초록), 고르기 전까지 파일은 바뀌지 않습니다.

| 키 | 메뉴 (AI next edit ▸) | 하는 일 |
|---|---|---|
| `<Space>an` | Suggest next edit | 제안 요청 (비주얼 모드: 선택 영역 기준) |
| `<Space>aa` | Jump to / apply suggestion | 제안 위치로 이동, 이미 그 위치면 적용 |
| `<Space>ad` | Dismiss suggestions | 제안 지우기 |
| `<Space>ac` | Cancel running request | 요청 취소 |
| `<Space>ab` | Backend ▸ | claude / codex / gemini 선택 (설치 안 된 것은 흐리게) |
| `<Space>am` | Model… | 백엔드별 모델 (비우면 기본값: claude는 `haiku`, 나머지는 CLI 기본) |
| `<Space>at` | Auto suggest | 편집 후 잠시 멈추면 자동 요청 (기본 꺼짐) |
| `<Space>al` | Open request log | 요청 기록 열기 |

`:Nes request|accept|accept_all|dismiss|cancel|backend [이름]|model [이름]|auto [on|off]|log|status`로도 쓸 수 있습니다.

- 요청 중에는 커서 줄 끝에 백엔드·모델·경과 시간이 돌아가며 표시됩니다.
- 모든 요청은 실행한 명령, 보낸 프롬프트, 받은 출력, 종료 코드, 걸린 시간 그대로
  `<설정 폴더>/data/nes/logs/<날짜>.log`에 남습니다 (`<Space>al`). 백엔드·모델·자동 실행 설정은 `data/nes/state.json`.
  위치는 `HEES_NVIM_DATA`로 바꿀 수 있습니다.
- CLI는 도구를 끄고 읽기 전용으로 실행해 파일을 건드리지 않습니다.
  - claude: `claude -p --output-format text --tools "" --no-session-persistence --model <모델>`
  - codex: `codex exec --skip-git-repo-check --ephemeral -s read-only --color never -o <파일> -`
  - gemini: `gemini -p … -o text --approval-mode plan`
- 적용 직전에 대상 줄이 그사이 바뀌었으면 적용하지 않고 알려 줍니다. 버퍼를 고치면 제안은 사라집니다.
- CLI가 로그인되어 있지 않으면 바로 멈추고 알려 줍니다. 터미널에서 `claude` / `codex` / `gemini`를 한 번 실행해 로그인하세요.
- Windows의 npm 래퍼(`claude.cmd`, `gemini.cmd`)는 `cmd /c` 인용 문제를 피하려고 래퍼가 가리키는 프로그램을 직접 실행합니다.

## 추가되는 키

kickstart 키와 Neovim 기본 키는 바꾸지 않습니다. 이 설정이 새로 쓰는 키는 아래가 전부입니다.

| 키 | 모드 | 동작 |
|---|---|---|
| 오른쪽 클릭 | 노멀/비주얼/입력 | 컨텍스트 메뉴 (기본 PopUp 메뉴 대신) |
| `<Space>m`, `Shift+F10` | 노멀/비주얼 | 컨텍스트 메뉴 |
| `<Space>a…` | 노멀/비주얼 | NES (위 표) |

kickstart의 키는 그대로입니다: 탐색기 `\`, 디버그 `F5` `F1` `F2` `F3` `F7` `<Space>b` `<Space>B`, LSP `grd` `grr` `gri` `grt` `grD` `grn` `gra` `gO` `gW`, 검색 `<Space>s…`, git `<Space>h…`.

## 테스트

```powershell
nvim --headless -c "luafile tests/smoke.lua"      # 메뉴, 컨텍스트 메뉴, NES 파싱/표시/적용, 백엔드 명령 (CLI 호출 없음)
nvim --headless -c "luafile tests/nes-live.lua"   # 실제 CLI로 NES 한 번씩 (HEES_LIVE_BACKENDS=claude,codex 로 고르기)
```

## 파일

```
kickstart.nvim/
├─ install.ps1  install.sh        전체 설치
├─ update.ps1   update.sh         전체 업데이트
├─ nvim-version.ps1 / .sh         Neovim 버전 관리
├─ kickstart.ps1 / .sh            kickstart.nvim 설치·업데이트
├─ plugins.ps1 / .sh              overlay 설치·업데이트·제거
├─ bin/nvk.cmd  bin/nvk           (선택) -AppName 으로 나란히 설치했을 때의 실행기
├─ overlay/                       kickstart 설정에 복사되는 플러그인
│  ├─ plugin/hees.lua             진입점 (init.lua 다음에 자동 로드)
│  └─ lua/hees/ (colors, ui, window_picker, explorer, menu, context, util, nes/)
├─ logs/                          (git 제외) 스크립트 출력 기록
├─ tools/
│  ├─ patch-kickstart.lua         kickstart 자체 기능 켜기 (두 OS 공통, nvim -l 로 실행)
│  ├─ sync.lua                    헤드리스로 플러그인/mason/파서 설치·업데이트 대기
│  └─ common.ps1  common.sh
├─ tests/smoke.lua  tests/nes-live.lua
└─ versions/                      (git 제외) 설치된 Neovim
```
