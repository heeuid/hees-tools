<#
.SYNOPSIS
  Neovim 설치·업데이트·버전 교체 (Windows).

.DESCRIPTION
  버전은 이 폴더의 versions\<이름>\ 에 나란히 설치되고, versions\current 정션이 사용 중인 버전을 가리킵니다.
  bin\nvk.cmd 가 versions\current\bin\nvim.exe 를 실행합니다. 시스템에 설치된 Neovim은 건드리지 않습니다.

  install <stable|nightly|vX.Y.Z>   공식 릴리스 받기
  install -Build <git ref>          소스에서 빌드 (git, cmake, C 컴파일러 필요. MSVC면 Developer PowerShell에서)
  install -From <URL|파일|폴더>     다른 곳에서 빌드된 것 가져오기 (.zip/.tar.gz 또는 bin\nvim.exe 가 있는 폴더)
  use <이름>                        사용할 버전 바꾸기
  list [-Remote]                    설치된 버전 (-Remote: GitHub 릴리스 목록)
  update                            최신 안정판을 설치하고 그 버전으로 바꾸기
  remove <이름>                     버전 삭제 (사용 중이면 -Force 필요)
  current                           사용 중인 버전

  -Name 은 설치 이름을 직접 정하고, -Use 는 설치 후 바로 그 버전으로 바꿉니다. -Force 는 같은 이름을 덮어씁니다.

.EXAMPLE
  .\nvim-version.ps1 install stable
  .\nvim-version.ps1 install -Build master -Use
  .\nvim-version.ps1 install -From \\server\share\nvim-win64.zip -Name team-build
  .\nvim-version.ps1 use v0.12.6
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][ValidateSet('install', 'use', 'list', 'update', 'remove', 'current', 'help')][string]$Command = 'help',
  [Parameter(Position = 1)][string]$Target,
  [string]$Build,
  [string]$From,
  [string]$Name,
  [string]$Generator,
  [switch]$Remote,
  [switch]$Use,
  [switch]$Force
)

. (Join-Path $PSScriptRoot 'tools\common.ps1')
$Tag = 'nvim-version'
$Repo = 'neovim/neovim'
$Current = Join-Path $Versions 'current'
$Tmp = Join-Path $Versions '.tmp'

function Get-Asset {
  if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return 'nvim-win-arm64.zip' }
  return 'nvim-win64.zip'
}

function New-TempDir {
  $dir = Join-Path $Tmp ([guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return $dir
}

function Save-Url([string]$Url, [string]$Dest) {
  Say $Tag "다운로드 $Url"
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    & $curl.Source -fL --retry 2 --progress-bar -o $Dest $Url
    if ($LASTEXITCODE -ne 0) { throw "다운로드 실패: $Url" }
  } else {
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
  }
}

function Expand-Any([string]$Archive, [string]$Dest) {
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  if ($Archive -match '\.zip$') {
    Expand-Archive -LiteralPath $Archive -DestinationPath $Dest -Force
  } elseif ($Archive -match '\.(tar\.gz|tgz|tar\.xz|tar\.zst|tar)$') {
    & tar.exe -xf $Archive -C $Dest | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "압축 해제 실패: $Archive" }
  } else {
    throw "모르는 압축 형식입니다: $Archive (.zip, .tar.gz 지원)"
  }
}

# The folder holding bin\nvim.exe inside an extracted archive or build output.
function Find-NvimRoot([string]$Dir) {
  $exe = Get-ChildItem -LiteralPath $Dir -Recurse -Filter nvim.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -eq 'bin' } | Select-Object -First 1
  if ($exe) { return $exe.Directory.Parent.FullName }
  return $null
}

function Get-VersionLabel([string]$Root) {
  $line = (& (Join-Path $Root 'bin\nvim.exe') --version | Select-Object -First 1)
  if ($line -match '^NVIM (\S+)') { return $Matches[1] }
  throw "$Root 에서 버전을 읽지 못했습니다"
}

function Get-CurrentName {
  if (-not (Test-Path -LiteralPath $Current)) { return $null }
  $target = (Get-Item -LiteralPath $Current).Target
  if ($target -is [array]) { $target = $target[0] }
  if (-not $target) { return $null }
  return Split-Path -Leaf $target
}

function Remove-Junction([string]$Path) {
  # Delete only the link, never what it points to.
  if (Test-Path -LiteralPath $Path) { [System.IO.Directory]::Delete($Path, $false) }
}

function Set-Current([string]$VersionName) {
  $dir = Join-Path $Versions $VersionName
  if (-not (Test-Path -LiteralPath (Join-Path $dir 'bin\nvim.exe'))) { Fail $Tag "설치되지 않은 버전입니다: $VersionName (list 로 확인)" }
  Remove-Junction $Current
  New-Item -ItemType Junction -Path $Current -Target $dir | Out-Null
  Say $Tag "사용 버전 → $VersionName"
}

# Move a staged Neovim into versions\<name>; returns the name.
function Add-Version([string]$Staged, [string]$Suffix) {
  $root = Find-NvimRoot $Staged
  if (-not $root) { throw "$Staged 안에 bin\nvim.exe 가 없습니다" }
  $label = Get-VersionLabel $root
  $versionName = if ($Name) { $Name } else { "$label$Suffix" }
  $versionName = $versionName -replace '[\\/:*?"<>|]', '_'
  $dest = Join-Path $Versions $versionName
  if (Test-Path -LiteralPath $dest) {
    if (-not $Force) {
      Say $Tag "$versionName 은 이미 설치되어 있습니다 (덮어쓰려면 -Force)"
      return $versionName
    }
    if ((Get-CurrentName) -eq $versionName) { Remove-Junction $Current }
    Remove-Item -LiteralPath $dest -Recurse -Force
  }
  Move-Item -LiteralPath $root -Destination $dest
  Say $Tag "설치 완료: $versionName ($label) → $dest"
  return $versionName
}

function Resolve-Tag([string]$Wanted) {
  if (-not $Wanted -or $Wanted -eq 'stable' -or $Wanted -eq 'latest') {
    try { return (Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$Repo/releases/latest").tag_name }
    catch { Warn $Tag 'GitHub API에 접근하지 못해 stable 태그로 받습니다'; return 'stable' }
  }
  if ($Wanted -eq 'nightly') { return 'nightly' }
  if ($Wanted -match '^\d') { return "v$Wanted" }
  return $Wanted
}

function Install-Release([string]$Wanted) {
  $releaseTag = Resolve-Tag $Wanted
  if ($releaseTag -match '^v\d' -and -not $Name -and -not $Force -and (Test-Path -LiteralPath (Join-Path $Versions "$releaseTag\bin\nvim.exe"))) {
    Say $Tag "$releaseTag 은 이미 설치되어 있습니다"
    return $releaseTag
  }
  $work = New-TempDir
  try {
    $asset = Get-Asset
    $file = Join-Path $work $asset
    Save-Url "https://github.com/$Repo/releases/download/$releaseTag/$asset" $file
    Expand-Any $file (Join-Path $work 'x')
    return Add-Version (Join-Path $work 'x') ''
  } finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Install-From([string]$Source) {
  $work = New-TempDir
  try {
    $staged = Join-Path $work 'x'
    if ($Source -match '^https?://') {
      $leaf = [System.IO.Path]::GetFileName(([uri]$Source).AbsolutePath)
      if (-not $leaf) { $leaf = 'nvim.zip' }
      $file = Join-Path $work $leaf
      Save-Url $Source $file
      Expand-Any $file $staged
    } elseif (Test-Path -LiteralPath $Source -PathType Container) {
      Say $Tag "폴더 복사 $Source"
      Copy-Item -LiteralPath $Source -Destination $staged -Recurse
    } elseif (Test-Path -LiteralPath $Source -PathType Leaf) {
      Expand-Any (Resolve-Path -LiteralPath $Source).Path $staged
    } else {
      throw "찾을 수 없습니다: $Source"
    }
    return Add-Version $staged '-custom'
  } finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Install-Build([string]$Ref) {
  foreach ($tool in 'git', 'cmake') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail $Tag "$tool 이 필요합니다 (winget install Kitware.CMake / Git.Git)" }
  }
  $src = Join-Path $Versions '.src\neovim'
  if (-not (Test-Path -LiteralPath (Join-Path $src '.git'))) {
    Say $Tag 'neovim 소스 받는 중'
    Invoke-Git $Tag @('clone', '--filter=blob:none', "https://github.com/$Repo.git", $src)
  } else {
    Invoke-Git $Tag @('-C', $src, 'fetch', '--tags', '--force', 'origin')
  }
  # A branch name builds the remote branch head; tags and commits are used as given.
  & git -C $src rev-parse --verify --quiet "origin/$Ref" | Out-Null
  $rev = if ($LASTEXITCODE -eq 0) { "origin/$Ref" } else { $Ref }
  Invoke-Git $Tag @('-C', $src, 'checkout', '--force', '--detach', $rev)

  $gen = $Generator
  if (-not $gen -and (Get-Command ninja -ErrorAction SilentlyContinue)) { $gen = 'Ninja' }
  $genArgs = @()
  if ($gen) { $genArgs = @('-G', $gen) }
  $work = New-TempDir
  Push-Location $src
  try {
    foreach ($dir in '.deps', 'build') { if (Test-Path $dir) { Remove-Item $dir -Recurse -Force } }
    $steps = New-Object System.Collections.ArrayList
    [void]$steps.Add((@('-S', 'cmake.deps', '-B', '.deps') + $genArgs + @('-D', 'CMAKE_BUILD_TYPE=Release')))
    [void]$steps.Add(@('--build', '.deps', '--config', 'Release'))
    [void]$steps.Add((@('-B', 'build') + $genArgs + @('-D', 'CMAKE_BUILD_TYPE=Release')))
    [void]$steps.Add(@('--build', 'build', '--config', 'Release'))
    [void]$steps.Add(@('--install', 'build', '--config', 'Release', '--prefix', (Join-Path $work 'x')))
    foreach ($step in $steps) {
      Say $Tag "cmake $($step -join ' ')"
      & cmake @step | Out-Host
      if ($LASTEXITCODE -ne 0) { throw "cmake 실패: $($step -join ' ')" }
    }
    return Add-Version (Join-Path $work 'x') '-build'
  } finally {
    Pop-Location
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Show-List {
  $cur = Get-CurrentName
  $dirs = @(Get-ChildItem -LiteralPath $Versions -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notin 'current', '.tmp', '.src' })
  if ($dirs.Count -eq 0) { Say $Tag '설치된 버전이 없습니다. install stable 로 설치하세요.' }
  foreach ($d in $dirs) {
    $mark = if ($d.Name -eq $cur) { '*' } else { ' ' }
    Write-Host ("{0} {1}" -f $mark, $d.Name)
  }
  if ($Remote) {
    Write-Host ''
    Say $Tag 'GitHub 릴리스:'
    $releases = Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$Repo/releases?per_page=15"
    foreach ($r in $releases) { Write-Host ("  {0,-10} {1}" -f $r.tag_name, ([datetime]$r.published_at).ToString('yyyy-MM-dd')) }
  }
}

New-Item -ItemType Directory -Force -Path $Versions | Out-Null

switch ($Command) {
  'install' {
    $installed = if ($Build) { Install-Build $Build } elseif ($From) { Install-From $From } else { Install-Release $Target }
    if ($Use -or -not (Get-CurrentName)) { Set-Current $installed }
  }
  'use' {
    if (-not $Target) { Fail $Tag 'use <이름> — 이름은 list 로 확인하세요' }
    Set-Current $Target
  }
  'update' {
    $installed = Install-Release 'stable'
    if ((Get-CurrentName) -eq $installed) { Say $Tag "이미 최신 안정판입니다 ($installed)" } else { Set-Current $installed }
  }
  'remove' {
    if (-not $Target) { Fail $Tag 'remove <이름>' }
    $dir = Join-Path $Versions $Target
    if (-not (Test-Path -LiteralPath $dir) -or $Target -in 'current', '.tmp', '.src') { Fail $Tag "없는 버전입니다: $Target" }
    if ((Get-CurrentName) -eq $Target) {
      if (-not $Force) { Fail $Tag "$Target 은 사용 중입니다. 다른 버전으로 use 하거나 -Force 를 주세요." }
      Remove-Junction $Current
    }
    Remove-Item -LiteralPath $dir -Recurse -Force
    Say $Tag "삭제: $Target"
  }
  'list' { Show-List }
  'current' {
    $cur = Get-CurrentName
    if ($cur) { Write-Host $cur } else { Say $Tag '선택된 버전이 없습니다' }
  }
  default { Get-Help $PSCommandPath -Detailed }
}

exit 0
