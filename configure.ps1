<#
.SYNOPSIS
  pathbin -- apply user-level git configuration.

.DESCRIPTION
  Copies configs/git/gitconfig to ~/.config/pathbin/git/gitconfig and
  configs/git/gitignore_global to ~/.gitignore_global, then wires both
  into ~/.gitconfig via include.path / core.excludesfile.

  Personal data (user.name, user.email) is resolved from env vars first,
  then falls back to whatever's already in your git config, then prompts.
  Skip the prompt with -NonInteractive (will warn and continue).

.PARAMETER NonInteractive
  Don't prompt for missing user.name / user.email; warn and continue.
#>
[CmdletBinding()]
param(
  [switch] $NonInteractive
)
$ErrorActionPreference = 'Stop'

function Info ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok  $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  !!  $m" -ForegroundColor Yellow }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Warn 'git not on PATH -- skipping git configuration. Install git first (run install.ps1).'
  return
}

$repoConfigs = Join-Path $PSScriptRoot 'configs/git'
if (-not (Test-Path $repoConfigs)) {
  Warn "configs/git not found at $repoConfigs -- run from a repo clone, not via irm | iex"
  return
}

# 1. Copy config files to stable user-scope locations
$cfgDir = Join-Path $env:USERPROFILE '.config\pathbin\git'
New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
Copy-Item (Join-Path $repoConfigs 'gitconfig')        (Join-Path $cfgDir 'gitconfig') -Force
Copy-Item (Join-Path $repoConfigs 'gitignore_global') (Join-Path $env:USERPROFILE '.gitignore_global') -Force
Ok "copied gitconfig + gitignore_global"

# 2. Resolve identity
function Resolve-GitIdentity ($key, $envVar, $prompt) {
  $val = [Environment]::GetEnvironmentVariable($envVar)
  if ($val) { return $val }
  $existing = & git config --global --get $key 2>$null
  if ($existing) { return $existing.Trim() }
  if ($NonInteractive) { Warn "$key not set and no $envVar; skipping (set later with: git config --global $key '...')"; return $null }
  return (Read-Host -Prompt $prompt)
}

$name  = Resolve-GitIdentity 'user.name'  'PATHBIN_GIT_NAME'  'Git user.name'
$email = Resolve-GitIdentity 'user.email' 'PATHBIN_GIT_EMAIL' 'Git user.email'
if ($name)  { & git config --global user.name  $name;  Ok "user.name  = $name" }
if ($email) { & git config --global user.email $email; Ok "user.email = $email" }

# 3. Wire includes (idempotent)
$includePath = (Join-Path $cfgDir 'gitconfig').Replace('\','/')
$existing = (& git config --global --get-all include.path 2>$null) | ForEach-Object { $_.Trim() }
if ($existing -notcontains $includePath) {
  & git config --global --add include.path $includePath
  Ok "include.path += $includePath"
} else { Ok "include.path already set" }

$excludes = (Join-Path $env:USERPROFILE '.gitignore_global').Replace('\','/')
& git config --global core.excludesfile $excludes
Ok "core.excludesfile = $excludes"

Write-Host "`n==> git configured. Inspect with: git config --global --list --show-origin" -ForegroundColor Cyan
