<#
.SYNOPSIS
  한 번에 설치 (Windows): Neovim → kickstart.nvim → 이 저장소의 플러그인.

.DESCRIPTION
  각 단계는 따로 실행할 수도 있습니다.
    .\nvim-version.ps1 install stable     Neovim (versions\ 아래, 시스템 Neovim 은 그대로)
    .\kickstart.ps1 install               kickstart.nvim (기본 NVIM_APPNAME=kickstart)
    .\plugins.ps1 install                 우클릭 메뉴, 클릭 가능한 탭/거터, NES

.EXAMPLE
  .\install.ps1 -NerdFont -Yes -AddToPath
#>
[CmdletBinding()]
param(
  [string]$AppName,
  [switch]$Default,
  [switch]$NerdFont,
  [switch]$Yes,
  [switch]$SkipDeps,
  [switch]$AddToPath,
  [switch]$Force
)

. (Join-Path $PSScriptRoot 'tools\common.ps1')
$Tag = 'install'

$common = @{}
if ($AppName) { $common.AppName = $AppName }
if ($Default) { $common.AppName = 'nvim' }

Say $Tag '1/3 Neovim'
if (-not (Get-Nvim) -or (Get-NvimVersion (Get-Nvim)) -lt [version]'0.12.0') {
  & (Join-Path $Here 'nvim-version.ps1') install stable -Use
} else {
  Say $Tag "이미 있음: $(Get-Nvim)"
}

Say $Tag '2/3 kickstart.nvim'
$ks = @{ NoSync = $true; NerdFont = $NerdFont; Yes = $Yes; SkipDeps = $SkipDeps; AddToPath = $AddToPath; Force = $Force; Default = $Default }
if ($AppName) { $ks.AppName = $AppName }
& (Join-Path $Here 'kickstart.ps1') install @ks
if ($LASTEXITCODE) { exit $LASTEXITCODE }

Say $Tag '3/3 플러그인 (overlay)'
& (Join-Path $Here 'plugins.ps1') install @common
if ($LASTEXITCODE) { exit $LASTEXITCODE }

Say $Tag "끝. 실행: $(Join-Path $Here 'bin\nvk.cmd')"

exit 0
