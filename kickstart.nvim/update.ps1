<#
.SYNOPSIS
  한 번에 최신으로 (Windows): Neovim 최신 안정판 → kickstart.nvim upstream → 이 저장소의 플러그인 → 플러그인/LSP/파서.

.DESCRIPTION
  각 단계는 따로 실행할 수도 있습니다.
    .\nvim-version.ps1 update      Neovim 최신 안정판 설치 후 전환
    .\kickstart.ps1 update         kickstart.nvim pull + 플러그인/LSP/파서 업데이트
    .\plugins.ps1 update           overlay 파일 갱신 + 그 플러그인 업데이트

  -SkipNvim 은 Neovim 버전을 그대로 둡니다 (nightly 나 직접 빌드한 버전을 쓰는 경우).

.EXAMPLE
  .\update.ps1
  .\update.ps1 -SkipNvim
#>
[CmdletBinding()]
param(
  [string]$AppName,
  [switch]$SkipNvim,
  [switch]$Force
)

. (Join-Path $PSScriptRoot 'tools\common.ps1')
$Tag = 'update'
$App = Get-AppName $AppName

if ($SkipNvim) {
  Say $Tag '1/4 Neovim: 건너뜀'
} else {
  Say $Tag '1/4 Neovim'
  & (Join-Path $Here 'nvim-version.ps1') update
}

Say $Tag '2/4 kickstart.nvim'
& (Join-Path $Here 'kickstart.ps1') update -AppName $App -NoSync -Force:$Force
if ($LASTEXITCODE) { exit $LASTEXITCODE }

Say $Tag '3/4 플러그인 (overlay)'
& (Join-Path $Here 'plugins.ps1') update -AppName $App -NoSync
if ($LASTEXITCODE) { exit $LASTEXITCODE }

Say $Tag '4/4 플러그인/LSP/파서 업데이트'
Invoke-Sync $Tag $App 'update' ''
Say $Tag '끝'

Stop-Log
exit 0
