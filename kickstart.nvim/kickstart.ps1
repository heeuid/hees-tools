<#
.SYNOPSIS
  kickstart.nvim 설치·업데이트 (Windows).

.DESCRIPTION
  install   필요 도구 점검 → kickstart.nvim clone → kickstart 자체 기능 켜기 → 헤드리스로 플러그인 설치
  update    kickstart.nvim 을 upstream 최신으로 pull → 다시 켜기 → 플러그인/LSP/파서 업데이트
  status    설치 위치, 버전, 로컬 수정 여부

  켜는 kickstart 기능 (tools\patch-kickstart.lua):
    init.lua 끝의 kickstart.plugins.debug, kickstart.plugins.neo-tree, custom.plugins
    debug.lua 의 중단점 아이콘 블록, DAP 어댑터 codelldb(C/C++/Rust)·python(debugpy) 추가
    -NerdFont 면 vim.g.have_nerd_font = true

  기본 설치 위치는 NVIM_APPNAME=kickstart (%LOCALAPPDATA%\kickstart) 로, 기존 %LOCALAPPDATA%\nvim 설정과 나란히 둡니다.
  -Default 를 주면 %LOCALAPPDATA%\nvim 에 설치하되 기존 nvim, nvim-data 를 *.bak-<시각> 으로 옮겨 둡니다.

.EXAMPLE
  .\kickstart.ps1 install -NerdFont -Yes
  .\kickstart.ps1 update
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][ValidateSet('install', 'update', 'status', 'help')][string]$Command = 'help',
  [string]$AppName,
  [switch]$Default,
  [switch]$NerdFont,
  [string]$Repo = 'https://github.com/nvim-lua/kickstart.nvim.git',
  [switch]$Yes,
  [switch]$SkipDeps,
  [switch]$AddToPath,
  [switch]$NoSync,
  [switch]$Force
)

. (Join-Path $PSScriptRoot 'tools\common.ps1')
$Tag = 'kickstart'
$Patch = Join-Path $Here 'tools\patch-kickstart.lua'
$PatchedFiles = @('init.lua', 'lua/kickstart/plugins/debug.lua')

if ($Default) { $AppName = 'nvim' }
$App = Get-AppName $AppName
$Cfg = Get-ConfigDir $App

# name, command(s) that satisfy it, winget id
$Deps = @(
  @{ Name = 'git'; Cmds = @('git'); Id = 'Git.Git'; Required = $true },
  @{ Name = 'make'; Cmds = @('make'); Id = 'ezwinports.make' },
  @{ Name = 'C compiler'; Cmds = @('gcc', 'clang', 'cl', 'zig'); Id = 'BrechtSanders.WinLibs.POSIX.UCRT' },
  @{ Name = 'ripgrep'; Cmds = @('rg'); Id = 'BurntSushi.ripgrep.MSVC' },
  @{ Name = 'fd'; Cmds = @('fd'); Id = 'sharkdp.fd' },
  @{ Name = 'tree-sitter CLI'; Cmds = @('tree-sitter'); Id = 'tree-sitter.tree-sitter-cli' }
)

function Test-Deps {
  $missing = @()
  foreach ($d in $Deps) {
    $found = $d.Cmds | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if ($found) { Say $Tag ("  ok      {0} ({1})" -f $d.Name, $found) } else { Warn $Tag ("  없음    {0}  → winget install --id {1}" -f $d.Name, $d.Id); $missing += $d }
  }
  if ($missing.Count -eq 0) { return }
  if ($Yes) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Fail $Tag 'winget 이 없어 자동 설치할 수 없습니다. 위 도구를 직접 설치하세요.' }
    foreach ($d in $missing) {
      Say $Tag "winget install $($d.Id)"
      & winget install --id $d.Id --exact --accept-package-agreements --accept-source-agreements | Out-Host
    }
    Warn $Tag '새로 설치한 도구는 새 터미널에서 PATH 에 잡힐 수 있습니다.'
  } elseif ($missing | Where-Object { $_.Required }) {
    Fail $Tag 'git 이 필요합니다. -Yes 로 자동 설치하거나 직접 설치하세요.'
  } else {
    Warn $Tag '없는 도구는 -Yes 로 자동 설치할 수 있습니다. 없어도 설치는 계속합니다.'
  }
}

function Test-KickstartClone([string]$Dir) {
  if (-not (Test-Path -LiteralPath (Join-Path $Dir '.git'))) { return $false }
  $url = (& git -C $Dir remote get-url origin 2>$null)
  return ($url -match 'kickstart')
}

function Backup-Dir([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir)) { return }
  $dest = "$Dir.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  Move-Item -LiteralPath $Dir -Destination $dest
  Say $Tag "백업: $Dir → $dest"
}

function Invoke-Patch([string[]]$Extra) {
  $exe = Assert-Nvim $Tag
  & $exe -l $Patch $Cfg @Extra | Out-Host
  return $LASTEXITCODE
}

function Add-UserPath([string]$Dir) {
  $path = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (($path -split ';') -contains $Dir) { Say $Tag "PATH 에 이미 있습니다: $Dir"; return }
  [Environment]::SetEnvironmentVariable('Path', ($path.TrimEnd(';') + ";$Dir"), 'User')
  Say $Tag "사용자 PATH 에 추가: $Dir (새 터미널부터 nvk 사용 가능)"
}

function Install-Kickstart {
  Say $Tag "설치 위치: $Cfg (NVIM_APPNAME=$App)"
  if (-not $SkipDeps) { Say $Tag '필요 도구 점검'; Test-Deps }
  if (-not (Get-Nvim)) {
    Say $Tag 'Neovim 이 없어 최신 안정판을 설치합니다'
    & (Join-Path $Here 'nvim-version.ps1') install stable
  }
  Assert-Nvim $Tag | Out-Null

  if (Test-KickstartClone $Cfg) {
    Say $Tag '이미 kickstart.nvim 이 있습니다 — clone 은 건너뛰고 설정만 다시 적용합니다 (최신으로는 update)'
  } else {
    if ($App -eq 'nvim') {
      Backup-Dir $Cfg
      Backup-Dir (Get-DataDir $App)
    } elseif (Test-Path -LiteralPath $Cfg) {
      if (-not $Force) { Fail $Tag "$Cfg 가 이미 있고 kickstart.nvim clone 이 아닙니다. 다른 -AppName 을 쓰거나 -Force 로 백업 후 설치하세요." }
      Backup-Dir $Cfg
    }
    Invoke-Git $Tag @('clone', $Repo, $Cfg)
  }

  Set-Content -LiteralPath $AppNameFile -Value $App -Encoding ASCII
  $extra = @()
  if ($NerdFont) { $extra += '--nerd-font' }
  Invoke-Patch $extra | Out-Null
  if ($AddToPath) { Add-UserPath (Join-Path $Here 'bin') }
  if (-not $NoSync) { Invoke-Sync $Tag $App 'install' '' }
  Say $Tag "완료. 실행: $(Join-Path $Here 'bin\nvk.cmd')"
}

function Update-Kickstart {
  if (-not (Test-KickstartClone $Cfg)) { Fail $Tag "$Cfg 에 kickstart.nvim 이 없습니다. 먼저 install 하세요." }
  Assert-Nvim $Tag | Out-Null
  if ((Invoke-Patch @('--check')) -ne 0 -and -not $Force) {
    Fail $Tag "위 파일에 직접 고친 내용이 있습니다. 커밋하거나 옮긴 뒤 다시 실행하세요 (-Force 는 그 수정을 버립니다)."
  }
  $nerd = Select-String -LiteralPath (Join-Path $Cfg 'init.lua') -SimpleMatch 'vim.g.have_nerd_font = true' -Quiet
  Invoke-Git $Tag (@('-C', $Cfg, 'checkout', '--') + $PatchedFiles)
  Invoke-Git $Tag @('-C', $Cfg, 'pull', '--ff-only')
  $extra = @()
  if ($nerd -or $NerdFont) { $extra += '--nerd-font' }
  Invoke-Patch $extra | Out-Null
  if (-not $NoSync) { Invoke-Sync $Tag $App 'update' '' }
  Say $Tag '업데이트 완료'
}

function Show-Status {
  Say $Tag "NVIM_APPNAME: $App"
  Say $Tag "설정: $Cfg"
  $exe = Get-Nvim
  if ($exe) { Say $Tag "Neovim: $exe ($((& $exe --version | Select-Object -First 1)))" } else { Warn $Tag 'Neovim: 없음' }
  if (Test-KickstartClone $Cfg) {
    Say $Tag "kickstart: $((& git -C $Cfg log -1 --format='%h %cs %s'))"
    if ((Invoke-Patch @('--check')) -eq 0) { Say $Tag '로컬 수정: 없음 (이 설정의 패치만 있음)' }
  } else {
    Warn $Tag 'kickstart: 설치되지 않음'
  }
}

switch ($Command) {
  'install' { Install-Kickstart }
  'update' { Update-Kickstart }
  'status' { Show-Status }
  default { Get-Help $PSCommandPath -Detailed }
}

exit 0
