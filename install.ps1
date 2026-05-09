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

function Install-Scoop {
  if (Test-Cmd 'scoop') { Ok 'scoop already installed'; return }
  Info 'installing scoop'
  try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop }
  catch { Warn "Set-ExecutionPolicy skipped: $($_.Exception.Message.Split([char]10)[0])" }
  Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
}

function Add-Buckets ($buckets) {
  $existing = (& scoop bucket list 2>$null | Out-String)
  foreach ($b in $buckets) {
    if ($existing -match "(?m)^\s*$b\s") { Ok "bucket $b" }
    else { Info "adding bucket $b"; & scoop bucket add $b }
  }
}

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

function Install-NerdFontJBM { Ok 'JetBrainsMono-NF handled by scoop bucket nerd-fonts (already queued)' }

function Install-Tool ($tool) {
  $win = $tool.win
  if ($null -eq $win) { return }
  switch ($win.via) {
    'scoop'  { & scoop install $win.pkg; Update-Path }
    'winget' { & winget install --id $win.pkg --accept-source-agreements --accept-package-agreements -e -h }
    'custom' {
      switch ($win.handler) {
        'bun'           { Install-Bun }
        'rustup'        { Install-Rustup }
        'node-via-nvm'  { Install-NodeViaNvm }
        'httpie'        { Install-Httpie }
        'dog'           { Install-Dog }
        'nerdfont-jbm'  { Install-NerdFontJBM }
        default         { Err "no handler for custom/$($win.handler)" }
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

Install-Scoop
Add-Buckets $raw.scoop_buckets

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
$extra = @("$env:USERPROFILE\.bun\bin", "$env:USERPROFILE\.cargo\bin", "$env:USERPROFILE\.local\bin") | Where-Object { Test-Path $_ }
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
