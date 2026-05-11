#!/usr/bin/env bash
# pathbin -- bootstrap a Linux/WSL dev environment from manifest.json.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/shubhampaithankar/pathbin/main/install.sh | bash
#   ./install.sh                       # uses sibling manifest.json
#   ./install.sh --categories runtime,cli
#
# Currently supports Debian/Ubuntu/WSL (apt). PRs welcome for dnf/pacman/brew.

set -euo pipefail

REMOTE_MANIFEST='https://raw.githubusercontent.com/shubhampaithankar/pathbin/main/manifest.json'
MANIFEST=""
CATEGORIES=""
SKIP_CONFIGURE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)        MANIFEST="$2"; shift 2 ;;
    --categories)      CATEGORIES="$2"; shift 2 ;;
    --skip-configure)  SKIP_CONFIGURE=1; shift ;;
    -h|--help)         sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

c_info() { printf '\033[36m==> %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[32m  ok  %s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m  !!  %s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m  XX  %s\033[0m\n' "$*"; }
have()   { command -v "$1" >/dev/null 2>&1; }

ensure_apt_base() {
  c_info "apt update + base deps"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends \
    curl wget ca-certificates gnupg jq unzip software-properties-common apt-transport-https lsb-release
  sudo install -d -m 0755 /etc/apt/keyrings
}

if [[ -z "$MANIFEST" ]]; then
  here_manifest="$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")/manifest.json"
  if [[ -f "$here_manifest" ]]; then MANIFEST="$here_manifest"; else MANIFEST="$REMOTE_MANIFEST"; fi
fi
c_info "manifest: $MANIFEST"

ensure_apt_base

if [[ "$MANIFEST" =~ ^https?:// ]]; then
  MANIFEST_JSON="$(curl -fsSL "$MANIFEST")"
else
  MANIFEST_JSON="$(cat "$MANIFEST")"
fi

add_apt_repo() {
  local id="$1" key_url="$2" list_line="$3"
  local keyring="/etc/apt/keyrings/${id}.gpg"
  local list="/etc/apt/sources.list.d/${id}.list"
  if [[ -f "$list" ]]; then c_ok "repo $id present"; return; fi
  c_info "adding apt repo: $id"
  curl -fsSL "$key_url" | sudo gpg --dearmor -o "$keyring"
  sudo chmod 0644 "$keyring"
  local codename arch
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  arch="$(dpkg --print-architecture)"
  echo "${list_line//\{CODENAME\}/$codename}" | sed "s|{ARCH}|$arch|g" | sudo tee "$list" >/dev/null
}

declare -A REPO_ADDED
ensure_repo() {
  local id="$1"
  [[ -n "${REPO_ADDED[$id]:-}" ]] && return
  local row
  row="$(jq -r --arg id "$id" '.apt_repos[] | select(.id==$id) | "\(.key_url)\t\(.list_line)"' <<<"$MANIFEST_JSON")"
  [[ -z "$row" ]] && { c_warn "no repo def for $id"; return; }
  IFS=$'\t' read -r k l <<<"$row"
  add_apt_repo "$id" "$k" "$l"
  REPO_ADDED[$id]=1
  sudo apt-get update -y
}

install_bun()   { have bun || curl -fsSL https://bun.sh/install | bash; }
install_uv()    { have uv  || curl -LsSf https://astral.sh/uv/install.sh | sh; }
install_rustup(){ have rustup || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default; }
install_nvm()   {
  if [[ -d "$HOME/.nvm" ]]; then c_ok "nvm present"; return; fi
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
}
install_node_via_nvm() {
  export NVM_DIR="$HOME/.nvm"; [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  if ! have nvm; then c_warn "nvm not loaded -- restart shell and re-run"; return; fi
  nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
}
install_zed()     { have zed      || curl -fsSL https://zed.dev/install.sh | sh; }
install_awscli()  {
  have aws && { c_ok "aws present"; return; }
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$tmp/awscli.zip"
  ( cd "$tmp" && unzip -q awscli.zip && sudo ./aws/install --update )
  rm -rf "$tmp"
}
install_httpie() {
  have http && { c_ok "httpie present"; return; }
  if have pipx; then pipx install httpie
  else c_warn "httpie: install pipx first or skip"; fi
}
install_dog()     {
  have dog && { c_ok "dog present"; return; }
  if have cargo; then cargo install dogdns; else c_warn "dog: install rustup first or skip"; fi
}
install_terax() {
  have terax && { c_ok "terax present"; return; }
  local arch url tmp
  arch="$(dpkg --print-architecture)"
  if [[ "$arch" != "amd64" ]]; then
    c_warn "terax: no .deb for arch $arch (only amd64 published upstream)"
    return
  fi
  url="$(curl -fsSL https://api.github.com/repos/crynta/terax-ai/releases/latest \
    | jq -r '.assets[] | select(.name | test("_amd64\\.deb$")) | .browser_download_url' \
    | head -n1)"
  if [[ -z "$url" ]]; then c_warn "terax: no .deb asset in latest release"; return; fi
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/terax.deb"
  sudo apt-get install -y "$tmp/terax.deb"
  rm -rf "$tmp"
}

install_nerdfont_jbm() {
  local dir="$HOME/.local/share/fonts"
  if [[ -f "$dir/JetBrainsMonoNerdFont-Regular.ttf" ]]; then c_ok "JetBrainsMono NF present"; return; fi
  mkdir -p "$dir"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -o "$tmp/jbm.zip"
  unzip -q "$tmp/jbm.zip" -d "$dir"
  fc-cache -f >/dev/null 2>&1 || true
  rm -rf "$tmp"
}

dispatch_custom() {
  case "$1" in
    bun) install_bun ;;
    uv)  install_uv ;;
    rustup) install_rustup ;;
    nvm) install_nvm ;;
    node-via-nvm) install_node_via_nvm ;;
    zed) install_zed ;;
    awscli) install_awscli ;;
    httpie) install_httpie ;;
    dog) install_dog ;;
    nerdfont-jbm) install_nerdfont_jbm ;;
    terax) install_terax ;;
    *) c_err "no handler for custom/$1" ;;
  esac
}

filter_jq='.tools[] | select(.linux != null)'
if [[ -n "$CATEGORIES" ]]; then
  IFS=',' read -ra cats <<<"$CATEGORIES"
  cat_filter=$(printf '"%s",' "${cats[@]}"); cat_filter="[${cat_filter%,}]"
  filter_jq=".tools[] | select(.linux != null) | select(.category as \$c | $cat_filter | index(\$c))"
fi

mapfile -t tool_rows < <(jq -rc "$filter_jq" <<<"$MANIFEST_JSON")

for row in "${tool_rows[@]}"; do
  name=$(jq -r '.name' <<<"$row")
  cat=$(jq -r '.category' <<<"$row")
  via=$(jq -r '.linux.via' <<<"$row")
  pkg=$(jq -r '.linux.pkg // empty' <<<"$row")
  handler=$(jq -r '.linux.handler // empty' <<<"$row")
  repo=$(jq -r '.linux.repo // empty' <<<"$row")
  [[ "$handler" == "node-via-nvm" ]] && continue
  c_info "[$cat] $name"
  case "$via" in
    apt)
      [[ -n "$repo" ]] && ensure_repo "$repo"
      sudo apt-get install -y $pkg || c_err "$name failed"
      ;;
    custom) dispatch_custom "$handler" ;;
    *) c_warn "unsupported via: $via for $name" ;;
  esac
done

for row in "${tool_rows[@]}"; do
  handler=$(jq -r '.linux.handler // empty' <<<"$row")
  [[ "$handler" != "node-via-nvm" ]] && continue
  c_info "[runtime] node (via nvm)"
  install_node_via_nvm
done

if have fdfind && ! have fd; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  c_ok "linked fdfind -> fd"
fi
if have batcat && ! have bat; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
  c_ok "linked batcat -> bat"
fi

SHIM_TAG='# pathbin: tool dirs + nvm + starship'
SHIM=$(cat <<'EOF'
# pathbin: tool dirs + nvm + starship
for d in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin"; do
  [[ -d "$d" && ":$PATH:" != *":$d:"* ]] && PATH="$d:$PATH"
done
export PATH
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"
EOF
)
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$rc" ]] || continue
  if grep -qF "$SHIM_TAG" "$rc"; then
    c_ok "$rc already patched"
  else
    printf '\n%s\n' "$SHIM" >> "$rc"
    c_ok "patched $rc"
  fi
done

c_info "verification"
for row in "${tool_rows[@]}"; do
  name=$(jq -r '.name' <<<"$row")
  v=$(jq -r '.verify // empty' <<<"$row")
  [[ -z "$v" ]] && continue
  cmd=${v%% *}
  if have "$cmd"; then
    out=$(eval "$v 2>&1" | head -n1 || true)
    c_ok "$name: $out"
  else
    c_warn "$name: $cmd not on PATH (open a new shell?)"
  fi
done

cfg="$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")/configure.sh"
if [[ "$SKIP_CONFIGURE" == 0 && -f "$cfg" ]]; then
  c_info "applying git configuration (use --skip-configure to skip)"
  bash "$cfg" --non-interactive
elif [[ "$SKIP_CONFIGURE" == 1 ]]; then
  c_ok "configure step skipped (--skip-configure)"
elif [[ ! -f "$cfg" ]]; then
  c_warn "configure.sh not found beside install.sh -- skipping git config"
fi

c_info "done. Open a new shell or 'source ~/.bashrc' to pick up PATH changes."
