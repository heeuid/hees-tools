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

# Append a folder to the user PATH (HKCU). The raw value is kept unexpanded and written back as
# REG_EXPAND_SZ so entries like %USERPROFILE%\bin keep working; the current session sees it too.
function Add-UserPathEntry([string]$Dir) {
  if (-not (($env:Path -split ';') -contains $Dir)) { $env:Path = "$Dir;$env:Path" }
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
  try {
    $raw = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $entries = @($raw -split ';' | Where-Object { $_ })
    if ($entries | Where-Object { $_.TrimEnd('\') -ieq $Dir.TrimEnd('\') }) { return }
    $key.SetValue('Path', (($entries + $Dir) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
  } finally { $key.Close() }
  if (-not ('Hees.Env' -as [type])) {
    Add-Type -Namespace Hees -Name Env -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
  }
  $result = [UIntPtr]::Zero
  [void][Hees.Env]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
}

# nvim-treesitter (kickstart) compiles parsers with the tree-sitter CLI; without it there is no syntax
# highlighting. Install it when missing: the official release exe into
# %LOCALAPPDATA%\Programs\tree-sitter (added to the user PATH), else `cargo install`. Returns $false
# if neither worked.
#
# nvim-treesitter needs tree-sitter-cli 0.26.1 or newer (TREE_SITTER_MIN_VER in its health check);
# older ones fail with "The subcommand 'build' wasn't recognized", so they are replaced too.
$script:TreeSitterMin = [version]'0.26.1'

function Get-TreeSitterVersion([string]$Exe) {
  $line = & $Exe --version 2>$null | Select-Object -First 1
  if ($line -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
  return $null
}

function Install-TreeSitter([string]$Tag) {
  $found = Get-Command tree-sitter -ErrorAction SilentlyContinue
  if ($found) {
    $ver = Get-TreeSitterVersion $found.Source
    if ($ver -and $ver -ge $script:TreeSitterMin) {
      Say $Tag "tree-sitter CLI: $($found.Source) ($ver)"
      return $true
    }
    Warn $Tag "tree-sitter CLI 가 너무 오래됐습니다: $($found.Source) ($ver), $($script:TreeSitterMin) 이상이 필요합니다. 새 버전을 설치합니다."
  }
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
  $dir = Join-Path $env:LOCALAPPDATA 'Programs\tree-sitter'
  $exe = Join-Path $dir 'tree-sitter.exe'
  $url = "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-windows-$arch.gz"
  Say $Tag "tree-sitter CLI 설치: 공식 릴리스 → $exe"
  try {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $gz = Join-Path $dir 'tree-sitter.gz'
    Invoke-WebRequest -Uri $url -OutFile $gz -UseBasicParsing
    $in = [System.IO.File]::OpenRead($gz)
    $out = [System.IO.File]::Create($exe)
    try {
      $unzip = New-Object System.IO.Compression.GZipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
      $unzip.CopyTo($out)
    } finally {
      $out.Dispose()
      $in.Dispose()
    }
    Remove-Item -LiteralPath $gz
    $version = Get-TreeSitterVersion $exe
    if (-not $version -or $version -lt $script:TreeSitterMin) { throw "$exe 실행 실패 또는 버전 $version" }
    Add-UserPathEntry $dir
    Say $Tag "tree-sitter CLI: $exe ($version, 사용자 PATH 에 $dir 추가)"
    # The machine PATH is searched before the user PATH: an old one there would still win.
    if ($found -and -not ($found.Source -like "$dir*")) {
      Warn $Tag "오래된 $($found.Source) 가 PATH 에서 먼저 잡힐 수 있습니다. 그 프로그램을 지우거나 PATH 에서 빼세요."
    }
    return $true
  } catch {
    Warn $Tag "공식 실행 파일을 설치하지 못했습니다: $_"
  }
  if (Get-Command cargo -ErrorAction SilentlyContinue) {
    Say $Tag 'tree-sitter CLI 설치: cargo install --locked tree-sitter-cli (소스 빌드, 몇 분 걸립니다)'
    & cargo install --locked tree-sitter-cli | Out-Host
    $cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\tree-sitter.exe'
    if ($LASTEXITCODE -eq 0 -and (Get-TreeSitterVersion $cargoExe) -ge $script:TreeSitterMin) { return $true }
  }
  Warn $Tag 'tree-sitter CLI 를 설치하지 못했습니다. 이대로면 문법 색칠(treesitter 파서)이 동작하지 않습니다.'
  Warn $Tag 'winget install --id tree-sitter.tree-sitter-cli 로 설치한 뒤 이 스크립트를 다시 실행하세요.'
  return $false
}

function Invoke-Git([string]$Tag, [string[]]$GitArgs) {
  # Out-Host keeps git's output out of the calling function's return value.
  & git @GitArgs | Out-Host
  if ($LASTEXITCODE -ne 0) { Fail $Tag "git $($GitArgs -join ' ') 실패" }
}
