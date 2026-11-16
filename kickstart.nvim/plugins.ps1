<#
.SYNOPSIS
  이 저장소의 Neovim 플러그인(overlay) 설치·업데이트·제거 (Windows).

.DESCRIPTION
  overlay\ 의 파일을 kickstart.nvim 설정 폴더에 복사합니다. init.lua 는 건드리지 않으므로 kickstart 를
  어떻게 설치했든(require 'custom.plugins' 줄이 없어도) 동작하고, kickstart 를 업데이트해도 충돌하지 않습니다.
    plugin\hees.lua               진입점 (Neovim 이 init.lua 다음에 자동으로 불러옴)
    lua\hees\colors.lua           색상 테마 Catppuccin Latte
    lua\hees\ui.lua               bufferline(탭 클릭/가운데 클릭 닫기/우클릭 메뉴), statuscol(줄 번호 클릭 중단점)
    lua\hees\menu.lua             마우스·키보드 겸용 다단계 메뉴
    lua\hees\context.lua          우클릭 메뉴 내용 (편집기 / 탐색기 / 버퍼 탭)
    lua\hees\nes\                 NES: Claude / Codex / Gemini CLI 로 다음 편집 제안
    lua\hees\ai\                  AI 공통: 백엔드·모델, 요청 실행·기록·뷰어, LSP 정보를 곁들인 코드 분석

  install   파일 복사 + 필요한 플러그인(catppuccin, bufferline, statuscol, window-picker) 설치
  update    파일 다시 복사(이전 파일은 지움) + 그 플러그인들만 업데이트
  remove    파일과 플러그인 제거 (NES 기록·설정이 있는 data\ 는 -Purge 일 때만 삭제)
  status    설치 여부와 overlay 와의 차이

.EXAMPLE
  .\plugins.ps1 install
  .\plugins.ps1 update
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][ValidateSet('install', 'update', 'remove', 'status', 'help')][string]$Command = 'help',
  [string]$AppName,
  [switch]$NoSync,
  [switch]$Purge
)

. (Join-Path $PSScriptRoot 'tools\common.ps1')
$Tag = 'plugins'
$App = Get-AppName $AppName
$Cfg = Get-ConfigDir $App
$Overlay = Join-Path $Here 'overlay'
# Plugins the overlay adds with vim.pack (kept in sync with overlay\lua\hees\colors.lua, ui.lua, window_picker.lua).
$PackPlugins = @('catppuccin', 'bufferline.nvim', 'statuscol.nvim', 'nvim-window-picker')
# Paths the overlay owns inside the config, relative to it. lua/custom/plugins/hees.lua is the old
# entry point; it is listed so updates delete it and the overlay isn't loaded twice.
$Owned = @('plugin/hees.lua', 'lua/hees', 'lua/custom/plugins/hees.lua')
$Excluded = $Owned + @('data/')

function Assert-Kickstart {
  if (-not (Test-Path -LiteralPath (Join-Path $Cfg 'init.lua'))) {
    Fail $Tag "$Cfg 에 kickstart.nvim 이 없습니다. 먼저 .\kickstart.ps1 install 을 실행하세요."
  }
}

function Remove-Owned {
  foreach ($rel in $Owned) {
    $p = Join-Path $Cfg $rel
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
  }
}

# Keep overlay files out of `git status` in the kickstart clone so kickstart updates stay clean.
function Set-GitExclude {
  $exclude = Join-Path $Cfg '.git\info\exclude'
  if (-not (Test-Path -LiteralPath (Split-Path $exclude))) { return }
  $lines = @()
  if (Test-Path -LiteralPath $exclude) { $lines = @(Get-Content -LiteralPath $exclude) }
  $add = $Excluded | Where-Object { $lines -notcontains $_ }
  if ($add) { Add-Content -LiteralPath $exclude -Value $add -Encoding ASCII }
}

function Copy-Overlay {
  Remove-Owned
  Copy-Item -Path (Join-Path $Overlay '*') -Destination $Cfg -Recurse -Force
  Set-GitExclude
  $count = (Get-ChildItem -LiteralPath $Overlay -Recurse -File).Count
  Say $Tag "overlay 파일 $count 개 복사 → $Cfg"
}

function Show-Status {
  Say $Tag "설정: $Cfg"
  $differ = 0
  $missing = 0
  foreach ($f in Get-ChildItem -LiteralPath $Overlay -Recurse -File) {
    $rel = $f.FullName.Substring($Overlay.Length + 1)
    $dest = Join-Path $Cfg $rel
    if (-not (Test-Path -LiteralPath $dest)) { $missing++; Warn $Tag "  없음   $rel" }
    elseif ((Get-FileHash -LiteralPath $dest).Hash -ne (Get-FileHash -LiteralPath $f.FullName).Hash) { $differ++; Warn $Tag "  다름   $rel" }
  }
  if ($missing -eq 0 -and $differ -eq 0) { Say $Tag '설치된 파일이 overlay 와 같습니다' }
  $pack = Join-Path (Get-DataDir $App) 'site\pack\core\opt'
  foreach ($p in $PackPlugins) {
    $state = if (Test-Path -LiteralPath (Join-Path $pack $p)) { '설치됨' } else { '없음' }
    Say $Tag "  플러그인 $p : $state"
  }
}

switch ($Command) {
  'install' {
    Assert-Kickstart
    Copy-Overlay
    Install-TreeSitter $Tag | Out-Null
    if (-not $NoSync) { Invoke-Sync $Tag $App 'install' '' }
    Say $Tag '완료. 우클릭 또는 <Space>m 으로 메뉴, <Space>a 로 NES 를 쓸 수 있습니다.'
  }
  'update' {
    Assert-Kickstart
    Copy-Overlay
    Install-TreeSitter $Tag | Out-Null
    if (-not $NoSync) { Invoke-Sync $Tag $App 'update' ($PackPlugins -join ',') }
    Say $Tag '업데이트 완료'
  }
  'remove' {
    Assert-Kickstart
    Remove-Owned
    Say $Tag 'overlay 파일 삭제'
    $exe = Assert-Nvim $Tag
    $old = $env:NVIM_APPNAME
    try {
      $env:NVIM_APPNAME = $App
      $names = ($PackPlugins | ForEach-Object { "'$_'" }) -join ','
      & $exe --headless -c "lua pcall(vim.pack.del, { $names })" -c 'qa!' | Out-Host
    } finally { $env:NVIM_APPNAME = $old }
    Say $Tag "플러그인 삭제: $($PackPlugins -join ', ')"
    if ($Purge) {
      $data = Join-Path $Cfg 'data'
      if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force; Say $Tag "삭제: $data" }
    }
  }
  'status' { Show-Status }
  default { Get-Help $PSCommandPath -Detailed }
}

Stop-Log
exit 0
