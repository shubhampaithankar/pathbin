#!/usr/bin/env bash
# pathbin -- apply user-level git configuration.
#
# Copies configs/git/gitconfig to ~/.config/pathbin/git/gitconfig and
# configs/git/gitignore_global to ~/.gitignore_global, then wires both
# into ~/.gitconfig via include.path / core.excludesfile.
#
# Personal data resolution: env var > existing git config > prompt
#   PATHBIN_GIT_NAME, PATHBIN_GIT_EMAIL
#
# Usage:
#   ./configure.sh                  # interactive if needed
#   ./configure.sh --non-interactive

set -euo pipefail

NON_INTERACTIVE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    -h|--help)         sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

c_info() { printf '\033[36m==> %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[32m  ok  %s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m  !!  %s\033[0m\n' "$*"; }
have()   { command -v "$1" >/dev/null 2>&1; }

if ! have git; then
  c_warn "git not on PATH -- skipping. Install git first (run install.sh)."
  exit 0
fi

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")"
repo_configs="$here/configs/git"
if [[ ! -d "$repo_configs" ]]; then
  c_warn "configs/git not found at $repo_configs -- run from a repo clone, not via curl|bash"
  exit 0
fi

# 1. Copy config files
cfg_dir="$HOME/.config/pathbin/git"
mkdir -p "$cfg_dir"
cp -f "$repo_configs/gitconfig"        "$cfg_dir/gitconfig"
cp -f "$repo_configs/gitignore_global" "$HOME/.gitignore_global"
c_ok "copied gitconfig + gitignore_global"

# 2. Identity (env > existing git config > prompt)
resolve_identity() {
  local key="$1" env_var="$2" prompt="$3" val=""
  val="${!env_var:-}"
  if [[ -n "$val" ]]; then echo "$val"; return; fi
  val="$(git config --global --get "$key" 2>/dev/null || true)"
  if [[ -n "$val" ]]; then echo "$val"; return; fi
  if [[ "$NON_INTERACTIVE" == 1 ]]; then
    c_warn "$key not set and no $env_var; skipping (set later with: git config --global $key '...')" >&2
    echo ""
    return
  fi
  read -r -p "$prompt: " val
  echo "$val"
}
name="$(resolve_identity user.name PATHBIN_GIT_NAME 'Git user.name')"
email="$(resolve_identity user.email PATHBIN_GIT_EMAIL 'Git user.email')"
[[ -n "$name"  ]] && { git config --global user.name  "$name";  c_ok "user.name  = $name";  }
[[ -n "$email" ]] && { git config --global user.email "$email"; c_ok "user.email = $email"; }

# 3. Wire includes (idempotent)
include_path="$cfg_dir/gitconfig"
if ! git config --global --get-all include.path 2>/dev/null | grep -Fxq "$include_path"; then
  git config --global --add include.path "$include_path"
  c_ok "include.path += $include_path"
else
  c_ok "include.path already set"
fi
git config --global core.excludesfile "$HOME/.gitignore_global"
c_ok "core.excludesfile = $HOME/.gitignore_global"

c_info "git configured. Inspect with: git config --global --list --show-origin"
