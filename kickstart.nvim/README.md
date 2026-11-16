# kickstart.nvim + 마우스 메뉴 + NES

[nvim-lua/kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)을 그대로 설치하고, kickstart에 없는 기능만 플러그인으로 더합니다.

- kickstart가 가진 기능은 kickstart 것을 씁니다: 탐색기(`kickstart.plugins.neo-tree`), 디버거(`kickstart.plugins.debug`), LSP/검색/git 키.
- 더하는 것: 우클릭 메뉴, 클릭 가능한 버퍼 탭·거터, AI(Claude / Codex / Gemini: 다음 편집 제안, LSP 정보를 곁들인 코드 분석, 요청 기록 뷰어), Catppuccin Latte 색상 테마.
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

### 코드 구조 보기 (outline, 호출·타입 계층)

- **Outline 사이드바** (`<Space>o`, 우클릭 **LSP ▸ Structure ▸ Outline sidebar** 또는 **File ▸ Code outline**):
  [aerial.nvim](https://github.com/stevearc/aerial.nvim)으로 지금 파일의 클래스·메서드·함수·필드·변수·상수를 오른쪽 창에 트리로 보여 줍니다.
  커서를 따라 지금 있는 위치가 강조되고, `Enter`나 더블클릭으로 그 코드로 이동합니다. LSP가 없으면 treesitter로 읽습니다.
  kickstart의 `gO`(telescope로 한 번 띄우는 심볼 목록)는 그대로입니다.
- **호출 계층** (우클릭 **LSP ▸ Structure ▸ Call hierarchy ▸**): Incoming(이 함수를 부르는 곳) / Outgoing(이 함수가 부르는 것). 결과는 quickfix 목록.
- **타입 계층** (**LSP ▸ Structure ▸ Type hierarchy ▸**): Supertypes / Subtypes.
- 호출·타입 계층은 Neovim 내장 LSP 기능이라 서버가 지원해야 합니다(지원하지 않으면 메뉴가 흐리게 표시). clangd, rust-analyzer, pyright는 호출 계층을 지원합니다.
- 실행 중의 호출 스택은 디버거 기능입니다: 디버깅 중 dap-ui의 Stacks 창, 또는 AI 디버그 분석(`<Space>ag`).

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

마우스 옆 버튼(뒤로/앞으로)은 이동 기록을 따라 갑니다: 정의로 간 뒤(`grd`) **뒤로** 버튼이 `<C-o>`, **앞으로**가 `<C-i>`.

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
  Go back        C-o             Go to        ▸   Toggle breakpoint Space b
  Go forward     C-i             Structure    ▸   Breakpoints    ▸
  ─────────                      Diagnostics  ▸   ─────
  LSP            ▸               ─────            Toggle debug UI  F7
  Debug          ▸               Inlay hints      Toggle REPL
  AI             ▸               Restart LSP
  Git            ▸               LSP health
  Search         ▸
  ─────────
  Window         ▸
  File           ▸
```

**Go back / Go forward**는 Neovim 이동 기록(jump list)의 `<C-o>` / `<C-i>`입니다. 정의로 가기, 참조·검색 결과로 가기, `G`·`%` 같은
큰 이동이 기록되고, 돌아갈 곳이 없으면 흐리게 표시됩니다.

**Window ▸** 로 편집 창을 마우스로 나누고 정리합니다. 항목마다 Neovim 기본 창 명령을 그대로 실행합니다.

| 항목 | 같은 키 | |
|---|---|---|
| Split right / Split below | `<C-w>v` / `<C-w>s` | 세로 / 가로로 나누기 |
| Open in new tab | `:tab split` | 이 버퍼를 새 탭에서도 열기 |
| Move to new tab | `<C-w>T` | 이 창을 새 탭으로 옮기기 |
| Equalize sizes | `<C-w>=` | 창 크기 똑같이 |
| Close window / Close other windows | `<C-w>c` / `<C-w>o` | 이 창 / 나머지 창 닫기 |

창이 하나뿐이면 옮기기·크기 맞추기·닫기 항목은 흐리게 표시됩니다. 파일을 분할로 여는 것은 탐색기 우클릭
(**Open in ▸**)과 버퍼 탭 우클릭 메뉴에 있습니다.

## AI (Claude / Codex / Gemini)

설치된 AI CLI(GPT는 `codex`)를 다음 편집 제안, 코드 분석, 디버그 상태 분석에 씁니다. 작업마다 다른 백엔드·모델을 쓸 수 있습니다. 모든 요청은 무엇을 실행했고 무엇을 주고받았는지 그대로 기록되고, 요청 기록 창에서 볼 수 있습니다.
우클릭 메뉴의 **AI ▸**에 모두 있습니다.

### 다음 편집 제안 (NES)

최근 편집(diff)과 커서 주변 코드를 보내 다음 편집을 제안받습니다. 제안은 화면에 diff로 표시되고(지울 줄은 빨강, 넣을 줄은 초록), 고르기 전까지 파일은 바뀌지 않습니다.

| 키 | 메뉴 (AI ▸) | 하는 일 |
|---|---|---|
| `<Space>an` | Suggest next edit | 제안 요청 (비주얼 모드: 선택 영역 기준) |
| `<Space>aa` | Jump to / apply suggestion | 제안 위치로 이동, 이미 그 위치면 적용 |
| `<Space>ad` | Dismiss suggestions | 제안 지우기 |
| `<Space>at` | Auto next-edit suggest | 편집 후 잠시 멈추면 자동 요청 (기본 꺼짐) |

- 요청 중에는 커서 줄 끝에 백엔드·모델·경과 시간이 돌아가며 표시됩니다.
- 적용 직전에 대상 줄이 그사이 바뀌었으면 적용하지 않고 알려 줍니다. 버퍼를 고치면 제안은 사라집니다.

### 코드 분석 (LSP 정보와 함께)

| 키 | 메뉴 (AI ▸) | 하는 일 |
|---|---|---|
| `<Space>ax` | Explain … | 코드가 무엇을 하고 어떻게 동작하는지 설명 |
| `<Space>ar` | Review … for bugs | 버그, 놓친 경우, 오류 처리, 위험한 패턴을 줄 번호와 고칠 방법으로 |
| `<Space>aq` | Ask about …… | 질문을 입력해 물어보기 |
| `<Space>ac` | Cancel running request | 진행 중인 요청(NES 포함) 취소 |

- **대상**: 비주얼 모드면 선택 영역, 아니면 LSP 문서 심볼로 찾은 **커서가 있는 함수(없으면 클래스)**, 그것도 없으면 커서 주변 ±30줄.
- **함께 보내는 LSP 정보**: 붙어 있는 서버, 그 범위의 진단(오류·경고), 커서 위치의 hover(타입·문서), 커서 아래 심볼의 정의 위치와 그 소스,
  참조 위치, 파일의 심볼 개요. 각 요청은 1.5초 안에 답이 없으면 빼고 보냅니다.
- **답**: 오른쪽 Markdown 창에 표시됩니다(`q`로 닫기). 기본으로 한국어로 답하게 합니다. 요청마다 새 대화(새 버퍼)가 되고, 이전 대화는 지워지지 않습니다.
- `:Ai explain` / `:Ai review` / `:Ai ask 질문` (범위를 주면 `:10,30Ai review`처럼 그 줄들).

### 디버그 상태 분석 (`<Space>ag`)

디버거(nvim-dap)가 중단점이나 예외에서 멈췄을 때, 디버거만 아는 정보를 모아 AI에 묻습니다.

- **보내는 것**: 멈춘 이유(중단점, 예외, step 등)와 예외 정보, 현재 위치와 주변 소스(현재 줄 표시), 호출 스택(최대 25단계),
  현재 프레임의 변수(scope별, 구조체·리스트 같은 값은 한 단계 펼침), 그 파일의 LSP 진단.
- **묻는 것**: 왜 여기서 멈췄는지, 이상해 보이는 값, 버그의 원인 후보, 다음에 확인할 것. 원하면 질문을 직접 입력할 수 있습니다.
- 키 `<Space>ag`, 우클릭 **AI ▸ Debug state ▸** 또는 **Debug ▸ Ask AI ▸**, `:Ai debug [질문]`. 멈춘 상태가 아니면 메뉴가 흐리게 표시됩니다.
- 답은 코드 분석과 같은 오른쪽 창에 나옵니다.

### 이어서 질문하기 (후속 질문)

분석·디버그 답은 **대화**가 되어, 같은 맥락에서 계속 물을 수 있습니다.

| 어디서 | 키 | 어느 대화로 |
|---|---|---|
| 답 창 | `a` | 그 창의 대화 |
| 코드 창 | `<Space>af` (AI ▸ Follow-up question…) | **가장 최근** 대화. 입력칸에 `후속 질문 → [Review cart.py:10-42 · codex]`처럼 어느 대화인지 나옵니다 |
| 어디서나 | `<Space>aF` (AI ▸ Conversations) | 이어 갈 수 있는 대화 목록에서 골라 `c` |
| 요청 기록 | `c` | 고른 요청이 속한 대화 |

- 답 창에는 질문마다 `## Q1: Review`, `## Q2: 질문…`이 쌓입니다. 맨 위에 작업·백엔드·모델·질문 수가 보입니다.
- 후속 질문은 그 대화를 시작한 **작업·백엔드·모델 그대로** 갑니다(Review로 시작했으면 Review 설정).
- **보내는 것**: 첫 요청(코드·LSP·디버거 정보) 그대로 + 지금까지의 질문과 답 + 새 질문. CLI의 세션 기능을 쓰지 않아 claude·codex·gemini가 똑같이 동작하고,
  실제로 보낸 내용이 요청 기록에 그대로 남습니다. 60,000자를 넘으면 오래된 답부터 빼고 보내며(`dropped_turns`로 기록), 첫 요청과 질문들은 늘 보냅니다.
- 지난 세션의 대화도 요청 기록(30일)에서 다시 만들어 이어 갈 수 있습니다.
- 다음 편집 제안(NES)은 대화가 아닙니다.
- `:Ai follow [질문]`, `:Ai conversations`.

### 작업별 백엔드와 모델

작업마다 백엔드와 모델을 따로 정할 수 있습니다. 비워 둔 것은 기본값을 따릅니다.

| 작업 | 쓰이는 곳 |
|---|---|
| Next edit (`nes`) | 다음 편집 제안 |
| Explain / Review / Ask | 코드 분석 |
| Debug state (`debug`) | 디버그 상태 분석 |

- **백엔드**: 작업 설정 → 전체 기본 백엔드.
- **모델**: 작업 설정(백엔드마다 따로 저장) → 기본값(claude 다음 편집은 `haiku`, 나머지는 CLI 기본 모델).

| 키 | 하는 일 |
|---|---|
| `<Space>ab` | 작업 고르기(전체 기본 / Next edit / Explain / Review / Ask / Debug state) → 백엔드 고르기(기본 따르기 / claude / codex / gemini) |
| `<Space>am` | 작업 고르기 → 모델 고르기(claude는 `haiku`·`sonnet`·`opus`, `직접 입력…`, `(기본값)`) |
| `<Space>as` | 커서 위치에 설정 메뉴: 작업마다 지금 값 → Backend / Model / Reset (`j`/`k`, `Enter`, `h`, `Esc`) |

- 목록에는 지금 값이 함께 보이고(`Explain: codex / CLI 기본`), 고른 값에는 `●`가 붙습니다.
- 우클릭 **AI ▸ Backends & models ▸** 도 같은 메뉴입니다.
- codex·gemini 모델은 그 CLI가 받는 이름을 `직접 입력…`으로 넣습니다.
- **명령**: `:Ai task review backend codex`, `:Ai task review model <이름>`(`default`면 기본값), `:Ai task review reset`, `:Ai status`(전체 보기).
- 설정은 `<설정 폴더>/data/ai/state.json`. 예전 "다음 편집 모델 / 분석 모델" 설정은 처음 불러올 때 작업별 설정으로 옮겨집니다.

### 요청 기록 (`<Space>al`, AI ▸ Request log)

새 탭에 왼쪽은 요청 목록(최근 것부터, 7일), 오른쪽은 고른 요청의 전체 기록이 나옵니다.
`g`를 누르면 **대화 목록**(분석·디버그 대화만, 대화 하나에 한 줄, 오른쪽은 질문과 답)으로 바뀌고, 다시 `g`면 요청 목록으로 돌아옵니다.
`<Space>aF`는 이 창을 대화 목록으로 엽니다.

- **목록**: 상태(`…` 실행 중, `✓` 성공, `✗` 실패), 시각, 작업(nes/explain/review/ask/debug), 백엔드/모델, 걸린 시간, 제목. 실행 중인 요청도 바로 나타나고 끝나면 갱신됩니다.
- **기록**: 실행한 **명령**, 작업 폴더, stdin으로 보낸 **입력(프롬프트) 전체**, 받은 **출력(답) 전체**, stderr, 종료 코드, 결과(예: `2 edits shown`, `parse error …`).
- 키: `j`/`k`나 클릭으로 이동하면 오른쪽이 바뀜, `<CR>`/`l` 기록으로, `h` 목록으로, `g` 요청/대화 목록 전환, `c` 그 대화에 후속 질문, `y` 명령 복사, `Y` 답 복사, `o` 원본 파일 열기, `r` 새로고침, `q` 닫기.
- 원본: `<설정 폴더>/data/ai/logs/<날짜>.jsonl` — 요청 하나가 한 줄(JSON)이고, 위 내용을 가공하지 않고 그대로 남깁니다. 위치는 `HEES_NVIM_DATA`로 바꿀 수 있습니다.

### 실행 방식

- CLI는 도구를 끄고 읽기 전용으로 실행해 파일을 건드리지 않습니다. 프롬프트는 stdin으로 보냅니다.
  - claude: `claude -p --output-format text --tools "" --no-session-persistence --model <모델>`
  - codex: `codex exec --skip-git-repo-check --ephemeral -s read-only --color never -o <파일> -`
  - gemini: `gemini -p <짧은 지시> -o text --approval-mode plan`
- CLI가 로그인되어 있지 않으면 바로 멈추고 알려 줍니다. 터미널에서 `claude` / `codex` / `gemini`를 한 번 실행해 로그인하세요.
- Windows의 npm 래퍼(`claude.cmd`, `gemini.cmd`)는 `cmd /c` 인용 문제를 피하려고 래퍼가 가리키는 프로그램을 직접 실행합니다.
- `:Nes …` 명령(request, accept, dismiss, …)도 그대로 씁니다.

## 추가되는 키

kickstart 키와 Neovim 기본 키는 바꾸지 않습니다. 이 설정이 새로 쓰는 키는 아래가 전부입니다.

| 키 | 모드 | 동작 |
|---|---|---|
| 오른쪽 클릭 | 노멀/비주얼/입력 | 컨텍스트 메뉴 (기본 PopUp 메뉴 대신) |
| `<Space>m`, `Shift+F10` | 노멀/비주얼 | 컨텍스트 메뉴 |
| 마우스 옆 버튼 (뒤로/앞으로) | 노멀 | 이동 기록 뒤로 `<C-o>` / 앞으로 `<C-i>` |
| `<Space>o` | 노멀 | 코드 구조(outline) 사이드바 열기·닫기 |
| `<Space>a…` | 노멀/비주얼 | AI: 다음 편집, 코드·디버그 분석, 후속 질문(`af`, `aF`), 작업별 백엔드/모델, 요청 기록 (위 표) |
| `a` | AI 답 창 안 | 그 대화에 후속 질문 |

kickstart의 키는 그대로입니다: 탐색기 `\`, 디버그 `F5` `F1` `F2` `F3` `F7` `<Space>b` `<Space>B`, LSP `grd` `grr` `gri` `grt` `grD` `grn` `gra` `gO` `gW`, 검색 `<Space>s…`, git `<Space>h…`.

## 테스트

```powershell
nvim --headless -c "luafile tests/smoke.lua"      # 메뉴, 탐색기, NES, AI 실행·기록·뷰어, LSP 정보 수집, 분석 (실제 AI 호출 없음)
nvim --headless -c "luafile tests/nes-live.lua"   # 실제 CLI로 다음 편집과 분석을 한 번씩 (HEES_LIVE_BACKENDS=claude,codex 로 고르기)
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
│  └─ lua/hees/ (colors, ui, window_picker, explorer, outline, menu, context, util, nes/, ai/)
├─ logs/                          (git 제외) 스크립트 출력 기록
├─ tools/
│  ├─ patch-kickstart.lua         kickstart 자체 기능 켜기 (두 OS 공통, nvim -l 로 실행)
│  ├─ sync.lua                    헤드리스로 플러그인/mason/파서 설치·업데이트 대기
│  └─ common.ps1  common.sh
├─ tests/smoke.lua  tests/nes-live.lua
└─ versions/                      (git 제외) 설치된 Neovim
```
