# Shared helpers for the Windows scripts. Dot-source it: . "$PSScriptRoot\tools\common.ps1"
# Works on Windows PowerShell 5.1 and PowerShell 7.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# $PSScriptRoot is this file's folder (tools\) even when dot-sourced.
$script:Here = Split-Path -Parent $PSScriptRoot
$script:Versions = if ($env:HEES_NVIM_VERSIONS) { $env:HEES_NVIM_VERSIONS } else { Join-Path $script:Here 'versions' }
$script:AppNameFile = Join-Path $script:Here '.appname'

# [[ Log ]]
# Everything a script prints is also saved to logs\<time>-<script>.log next to the scripts. A script
# called by another (install.ps1 → kickstart.ps1 …) writes into the log the outermost one opened.
$script:OwnsLog = $false
if (-not $env:HEES_LOG) {
  $logs = Join-Path $script:Here 'logs'
  New-Item -ItemType Directory -Force -Path $logs | Out-Null
  $caller = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.PSCommandPath)
  $env:HEES_LOG = Join-Path $logs ('{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $caller)
  Start-Transcript -LiteralPath $env:HEES_LOG -Append | Out-Null
  $script:OwnsLog = $true
}

function Stop-Log {
  if (-not $script:OwnsLog) { return }
  $path = $env:HEES_LOG
  $script:OwnsLog = $false
  $env:HEES_LOG = $null
  Stop-Transcript | Out-Null
  Write-Host "[log] 출력 기록: $path"
}

# An uncaught error still closes the log.
trap { Stop-Log; break }

function Say([string]$Tag, [string]$Message) { Write-Host "[$Tag] $Message" }
function Warn([string]$Tag, [string]$Message) { Write-Host "[$Tag] $Message" -ForegroundColor Yellow }
function Fail([string]$Tag, [string]$Message) {
  Write-Host "[$Tag] 오류: $Message" -ForegroundColor Red
  Stop-Log
  exit 1
}

# Config name (NVIM_APPNAME): -AppName, else what kickstart.ps1 recorded, else 'nvim' — Neovim's default
# location, so plain `nvim` uses it.
function Get-AppName([string]$Requested) {
  if ($Requested) { return $Requested }
  if (Test-Path -LiteralPath $script:AppNameFile) {
    $name = (Get-Content -LiteralPath $script:AppNameFile -TotalCount 1).Trim()
    if ($name) { return $name }
  }
  return 'nvim'
}

function Get-ConfigDir([string]$App) { Join-Path $env:LOCALAPPDATA $App }
function Get-DataDir([string]$App) { Join-Path $env:LOCALAPPDATA "$App-data" }

# The Neovim selected with nvim-version.ps1, or one on PATH when none is selected.
function Get-Nvim {
  $selected = Join-Path $script:Versions 'current\bin\nvim.exe'
  if (Test-Path -LiteralPath $selected) { return $selected }
  $onPath = Get-Command nvim.exe -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }
  return $null
}

function Get-NvimVersion([string]$Exe) {
  $line = (& $Exe --version | Select-Object -First 1)
  if ($line -match '^NVIM v?(\d+)\.(\d+)\.(\d+)') { return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" }
  return $null
}

# Neovim >= 0.12 (vim.pack) or stop with instructions.
function Assert-Nvim([string]$Tag) {
  $exe = Get-Nvim
  if (-not $exe) { Fail $Tag 'Neovim이 없습니다. 먼저 .\nvim-version.ps1 install stable 을 실행하세요.' }
  $ver = Get-NvimVersion $exe
  if (-not $ver -or $ver -lt [version]'0.12.0') {
    Fail $Tag "kickstart.nvim은 Neovim 0.12 이상이 필요합니다 ($exe 은 $ver). .\nvim-version.ps1 install stable 로 설치하세요."
  }
  return $exe
}

# Run the config headless to finish async installs (mode 'install') or update everything (mode 'update').
function Invoke-Sync([string]$Tag, [string]$App, [string]$Mode, [string]$Plugins) {
  $exe = Assert-Nvim $Tag
  # :luafile takes a file name, so spaces in the path must be escaped.
  $sync = (Join-Path $script:Here 'tools\sync.lua') -replace ' ', '\ '
  Say $Tag "Neovim 헤드리스 동기화 ($Mode) — 플러그인/LSP/디버거 설치를 기다립니다"
  $old = @{ app = $env:NVIM_APPNAME; mode = $env:HEES_SYNC; plugins = $env:HEES_SYNC_PLUGINS }
  try {
    $env:NVIM_APPNAME = $App
    $env:HEES_SYNC = $Mode
    $env:HEES_SYNC_PLUGINS = $Plugins
    & $exe --headless --cmd "luafile $sync" | Out-Host
    Write-Host ''
    if ($LASTEXITCODE -ne 0) { Warn $Tag "동기화가 코드 $LASTEXITCODE 로 끝났습니다. nvk 를 실행해 메시지를 확인하세요." }
  } finally {
    $env:NVIM_APPNAME = $old.app
    $env:HEES_SYNC = $old.mode
    $env:HEES_SYNC_PLUGINS = $old.plugins
  }
}

function Invoke-Git([string]$Tag, [string[]]$GitArgs) {
  # Out-Host keeps git's output out of the calling function's return value.
  & git @GitArgs | Out-Host
  if ($LASTEXITCODE -ne 0) { Fail $Tag "git $($GitArgs -join ' ') 실패" }
}
