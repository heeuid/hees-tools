<#
.SYNOPSIS
  한 번에 설치 (Windows): Neovim → kickstart.nvim → 이 저장소의 플러그인. 끝나면 그냥 `nvim` 으로 실행합니다.

.DESCRIPTION
  각 단계는 따로 실행할 수도 있습니다.
    .\nvim-version.ps1 install stable     Neovim (versions\ 아래 + 시스템 PATH 맨 앞, 다른 Neovim 파일은 그대로)
    .\kickstart.ps1 install               kickstart.nvim (%LOCALAPPDATA%\nvim, 기존 설정은 *.bak-<시각> 으로 백업)
    .\plugins.ps1 install                 우클릭 메뉴, 클릭 가능한 탭/거터, NES

  -AppName <이름> 은 기본 경로 대신 %LOCALAPPDATA%\<이름> 에 나란히 설치합니다 (NVIM_APPNAME=<이름> 으로 실행).
  -NoPath 는 시스템 PATH 를 건드리지 않습니다 (그러면 nvim 은 PATH 에 먼저 있는 다른 Neovim 이 실행됩니다).

.EXAMPLE
  .\install.ps1 -NerdFont -Yes
#>
[CmdletBinding()]
param(
  [string]$AppName,
  [switch]$NerdFont,
  [switch]$Yes,
  [switch]$SkipDeps,
  [switch]$NoPath,
  [switch]$Force
)

. (Join-Path $PSScriptRoot 'tools\common.ps1')
$Tag = 'install'

$common = @{}
if ($AppName) { $common.AppName = $AppName }

Say $Tag '1/3 Neovim'
$selected = Join-Path $Versions 'current\bin\nvim.exe'
if (-not (Test-Path -LiteralPath $selected) -or (Get-NvimVersion $selected) -lt [version]'0.12.0') {
  & (Join-Path $Here 'nvim-version.ps1') install stable -Use -NoPath:$NoPath
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
} else {
  Say $Tag "이미 있음: $selected"
  if (-not $NoPath) { & (Join-Path $Here 'nvim-version.ps1') path }
}

Say $Tag '2/3 kickstart.nvim'
$ks = @{ NoSync = $true; NerdFont = $NerdFont; Yes = $Yes; SkipDeps = $SkipDeps; Force = $Force }
if ($AppName) { $ks.AppName = $AppName }
& (Join-Path $Here 'kickstart.ps1') install @ks
if ($LASTEXITCODE) { exit $LASTEXITCODE }

Say $Tag '3/3 플러그인 (overlay)'
& (Join-Path $Here 'plugins.ps1') install @common
if ($LASTEXITCODE) { exit $LASTEXITCODE }

if (-not $AppName -or $AppName -eq 'nvim') { Say $Tag '끝. 새 터미널에서 nvim 으로 실행하세요.' } else { Say $Tag "끝. NVIM_APPNAME=$AppName 으로 nvim 을 실행하세요." }

Stop-Log
exit 0
