<#
.SYNOPSIS
  pathbin -- bootstrap a Windows dev environment from manifest.json.
.PARAMETER Manifest
  Local path or URL to manifest.json. Defaults to sibling file when running
  from a clone, otherwise pulls from $script:RemoteManifest.
.PARAMETER Categories
  Optional filter -- only install tools whose category is in this list.
.EXAMPLE
  irm https://raw.githubusercontent.com/shubhampaithankar/pathbin/main/install.ps1 | iex
.EXAMPLE
  .\install.ps1 -Categories runtime,cli
#>
[CmdletBinding()]
param(
  [string]   $Manifest       = '',
  [string[]] $Categories     = @(),
  [switch]   $SkipConfigure
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$script:RemoteManifest  = 'https://raw.githubusercontent.com/shubhampaithankar/pathbin/main/manifest.json'

function Info ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok  $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  !!  $m" -ForegroundColor Yellow }
function Err  ($m) { Write-Host "  XX  $m" -ForegroundColor Red }
function Test-Cmd ($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Update-Path { $env:Path = [System.Environment]::GetEnvironmentVariable('Path','User') + ';' + [System.Environment]::GetEnvironmentVariable('Path','Machine') }
function Test-Admin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }

function Install-Bun {
  if (Test-Cmd 'bun') {
    $bunPath = (Get-Command bun).Source
    if ($bunPath -like "$env:USERPROFILE\.bun\*") { Ok "bun already official ($bunPath)"; return }
    Warn "bun present at $bunPath -- installing official bun.exe alongside"
  }
  Info 'installing bun (official PowerShell installer)'
  Invoke-RestMethod 'https://bun.sh/install.ps1' | Invoke-Expression
}

function Install-Rustup {
  if (Test-Cmd 'rustup') { Ok 'rustup already installed'; return }
  Info 'installing rustup'
  $tmp = Join-Path $env:TEMP 'rustup-init.exe'
  Invoke-WebRequest 'https://win.rustup.rs/x86_64' -OutFile $tmp
  & $tmp -y --default-toolchain stable --profile default
  Remove-Item $tmp -Force
}

function Install-NodeViaNvm {
  if (-not (Test-Cmd 'nvm')) { Warn 'nvm not on PATH yet -- open a new shell and re-run'; return }
  Info 'installing latest LTS Node via nvm'
  & nvm install lts
  & nvm use   lts
}

function Install-Httpie {
  if (Test-Cmd 'http') { Ok 'httpie already installed'; return }
  if (-not (Test-Cmd 'pipx')) { Warn 'pipx required for httpie -- install runtime category first'; return }
  Info 'installing httpie via pipx'
  & pipx install httpie
}

function Install-Dog {
  if (Test-Cmd 'dog') { Ok 'dog already installed'; return }
  if (-not (Test-Cmd 'cargo')) { Warn 'cargo required for dog -- install runtime category first'; return }
  Info 'installing dog via cargo (dogdns)'
  & cargo install dogdns
}

function Install-NerdFontJBM {
  $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
  if (Test-Path (Join-Path $fontDir 'JetBrainsMonoNerdFont-Regular.ttf')) { Ok 'JetBrainsMono NF already installed'; return }
  Info 'installing JetBrainsMono Nerd Font (user-scope)'
  $tmp   = Join-Path $env:TEMP 'JetBrainsMono-NF.zip'
  $stage = Join-Path $env:TEMP 'jbm-nf-stage'
  Invoke-WebRequest 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip' -OutFile $tmp -UseBasicParsing
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  Expand-Archive -Path $tmp -DestinationPath $stage -Force
  New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
  $regKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
  if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }   # absent on a fresh user profile
  Get-ChildItem -Path $stage -Filter '*.ttf' | ForEach-Object {
    $target = Join-Path $fontDir $_.Name
    Copy-Item $_.FullName $target -Force
    Set-ItemProperty -Path $regKey -Name "$($_.BaseName) (TrueType)" -Value $target
  }
  Remove-Item $tmp, $stage -Recurse -Force -ErrorAction SilentlyContinue
  Ok 'JetBrainsMono NF installed'
}

function Install-Pipx {
  if (Test-Cmd 'pipx') { Ok 'pipx already installed'; return }
  if (-not (Test-Cmd 'python')) { Warn 'python required for pipx -- install runtime category first'; return }
  Info 'installing pipx via pip (--user)'
  & python -m pip install --user --upgrade pipx
  & python -m pipx ensurepath | Out-Null
  Update-Path
}

function Install-GitFilterRepo {
  if (Test-Cmd 'git-filter-repo') { Ok 'git-filter-repo already installed'; return }
  if (-not (Test-Cmd 'pipx')) { Warn 'pipx required for git-filter-repo -- install runtime category first'; return }
  Info 'installing git-filter-repo via pipx'
  & pipx install git-filter-repo
  Update-Path
}

function Install-ZipTool ($name, $url, $innerDir, $destName, $probe) {
  $dest = Join-Path $env:LOCALAPPDATA "Programs\$destName"
  $bin  = Join-Path $dest 'bin'
  if (Test-Path (Join-Path $bin $probe)) {
    Ok "$name already installed ($dest)"
    if (-not ($env:Path -split ';' -contains $bin)) { $env:Path = "$bin;$env:Path" }
    return
  }
  Info "installing $name"
  $tmp    = Join-Path $env:TEMP "$destName-dl.zip"
  $stage  = Join-Path $env:TEMP "$destName-stage"
  $staged = "$dest.new"
  Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  Expand-Archive -Path $tmp -DestinationPath $stage -Force
  $src = if ($innerDir) { Join-Path $stage $innerDir } else { $stage }
  New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
  # Stage the new payload beside $dest first; only then delete + rename, so a
  # failed install never leaves the machine with the old tool already gone.
  if (Test-Path $staged) { Remove-Item $staged -Recurse -Force }
  Move-Item $src $staged
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  Move-Item $staged $dest
  Remove-Item $tmp, $stage -Recurse -Force -ErrorAction SilentlyContinue
  if (-not ($env:Path -split ';' -contains $bin)) { $env:Path = "$bin;$env:Path" }
}

function Install-Maven {
  if (Test-Cmd 'mvn') { Ok 'maven already installed'; return }
  $ver = '3.9.9'   # Apache publishes no 'latest' endpoint; bump this pin manually
  Install-ZipTool -Name 'maven' -Url "https://dlcdn.apache.org/maven/maven-3/$ver/binaries/apache-maven-$ver-bin.zip" -InnerDir "apache-maven-$ver" -DestName 'maven' -Probe 'mvn.cmd'
}

function Install-Gradle {
  if (Test-Cmd 'gradle') { Ok 'gradle already installed'; return }
  $cur = Invoke-RestMethod 'https://services.gradle.org/versions/current'
  Install-ZipTool -Name "gradle $($cur.version)" -Url $cur.downloadUrl -InnerDir "gradle-$($cur.version)" -DestName 'gradle' -Probe 'gradle.bat'
}

function Install-Mingw {
  if (Test-Cmd 'gcc') { Ok 'mingw/gcc already installed'; return }
  Info 'resolving latest mingw-w64 (winlibs) release'
  $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/brechtsanders/winlibs_mingw/releases/latest' -Headers @{ 'User-Agent' = 'pathbin' }
  $asset = $rel.assets | Where-Object { $_.name -match 'x86_64.*posix.*ucrt.*\.zip$' -and $_.name -notmatch 'llvm' } | Select-Object -First 1
  if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -match 'x86_64.*\.zip$' } | Select-Object -First 1 }
  if (-not $asset) { Err 'no winlibs x86_64 zip asset in latest release'; return }
  Install-ZipTool -Name 'mingw-w64' -Url $asset.browser_download_url -InnerDir 'mingw64' -DestName 'mingw64' -Probe 'gcc.exe'
}

function Install-Terax {
  $installed = @(
    (Join-Path $env:LOCALAPPDATA 'Terax\Terax.exe'),
    (Join-Path ${env:ProgramFiles} 'Terax\Terax.exe')
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($installed) { Ok "terax already installed ($installed)"; return }
  Info 'installing terax (latest GitHub release)'
  $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/crynta/terax-ai/releases/latest' -Headers @{ 'User-Agent' = 'pathbin' }
  $asset = $rel.assets | Where-Object { $_.name -match '_x64-setup\.exe$' } | Select-Object -First 1
  if (-not $asset) { Err 'no Windows .exe setup asset in latest terax release'; return }
  $tmp = Join-Path $env:TEMP $asset.name
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing
  Start-Process -FilePath $tmp -ArgumentList '/S' -Wait
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

function Install-Tool ($tool) {
  $win = $tool.win
  if ($null -eq $win) { return }
  switch ($win.via) {
    'winget' { & winget install --id $win.pkg --accept-source-agreements --accept-package-agreements -e -h; Update-Path }
    'custom' {
      switch ($win.handler) {
        'bun'             { Install-Bun }
        'rustup'          { Install-Rustup }
        'node-via-nvm'    { Install-NodeViaNvm }
        'httpie'          { Install-Httpie }
        'dog'             { Install-Dog }
        'nerdfont-jbm'    { Install-NerdFontJBM }
        'terax'           { Install-Terax }
        'pipx'            { Install-Pipx }
        'git-filter-repo' { Install-GitFilterRepo }
        'maven'           { Install-Maven }
        'gradle'          { Install-Gradle }
        'mingw'           { Install-Mingw }
        default           { Err "no handler for custom/$($win.handler)" }
      }
    }
    default  { Err "unknown via '$($win.via)' for $($tool.name)" }
  }
}

function Verify-Tool ($tool) {
  if (-not $tool.verify) { return }
  $name = ($tool.verify -split '\s+')[0]
  if (-not (Test-Cmd $name)) { Warn "$($tool.name): '$name' not on PATH (open a new shell?)"; return }
  try {
    $out = (& cmd /c "$($tool.verify) 2>&1" | Select-Object -First 1)
    Ok "$($tool.name): $out"
  } catch { Warn "$($tool.name): verify failed -- $_" }
}

Info 'pathbin Windows bootstrap'
if (-not (Test-Admin)) { Warn 'not running elevated; nvm-windows needs admin to switch Node versions later (re-launch as admin to use `nvm use lts` after install)' }

if (-not $Manifest) {
  $local = Join-Path $PSScriptRoot 'manifest.json'
  if (Test-Path $local) { $Manifest = $local } else { $Manifest = $script:RemoteManifest }
}
Info "manifest: $Manifest"
$raw = if ($Manifest -match '^https?://') { Invoke-RestMethod $Manifest } else { Get-Content $Manifest -Raw | ConvertFrom-Json }

if (-not (Test-Cmd 'winget')) {
  Err 'winget not found -- install "App Installer" from the Microsoft Store (or update Windows), then re-run'
  exit 1
}

$tools = $raw.tools
if ($Categories.Count -gt 0) { $tools = $tools | Where-Object { $_.category -eq 'prereq' -or $Categories -contains $_.category } }

$pass1 = $tools | Where-Object { $_.win -and $_.win.handler -ne 'node-via-nvm' }
$pass2 = $tools | Where-Object { $_.win -and $_.win.handler -eq 'node-via-nvm' }

foreach ($t in $pass1) { Info "[$($t.category)] $($t.name)"; try { Install-Tool $t } catch { Err "$($t.name): $_" } }
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','User') + ';' + [System.Environment]::GetEnvironmentVariable('Path','Machine')
foreach ($t in $pass2) { Info "[$($t.category)] $($t.name)"; try { Install-Tool $t } catch { Err "$($t.name): $_" } }

$profileDir = Split-Path $PROFILE
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
$shim = @'
# pathbin: ensure user-scope tool dirs are on PATH
$extra = @(
  "$env:USERPROFILE\.bun\bin", "$env:USERPROFILE\.cargo\bin", "$env:USERPROFILE\.local\bin",
  "$env:LOCALAPPDATA\Programs\maven\bin", "$env:LOCALAPPDATA\Programs\gradle\bin", "$env:LOCALAPPDATA\Programs\mingw64\bin"
) | Where-Object { Test-Path $_ }
foreach ($d in $extra) { if (-not ($env:Path -split ';' -contains $d)) { $env:Path = "$d;$env:Path" } }
'@
if (-not (Test-Path $PROFILE) -or -not (Select-String -Path $PROFILE -Pattern '# pathbin:' -Quiet)) {
  Add-Content -Path $PROFILE -Value "`n$shim`n"
  Ok "patched $PROFILE"
} else { Ok "$PROFILE already patched" }

Write-Host "`n==> verification" -ForegroundColor Cyan
foreach ($t in $tools) { Verify-Tool $t }
$cfg = Join-Path $PSScriptRoot 'configure.ps1'
if (-not $SkipConfigure -and (Test-Path $cfg)) {
  Write-Host "`n==> applying git configuration (use -SkipConfigure to skip)" -ForegroundColor Cyan
  & $cfg -NonInteractive
} elseif ($SkipConfigure) { Ok 'configure step skipped (-SkipConfigure)' }
elseif (-not (Test-Path $cfg)) { Warn 'configure.ps1 not found beside install.ps1 -- skipping git config' }

Write-Host "`n==> done. Open a new shell to pick up PATH changes." -ForegroundColor Cyan
