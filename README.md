# pathbin

Reproducible dev-tool bootstrap for Windows + Linux/WSL. One manifest, two install scripts, every machine identical.

## What gets installed

Driven by [`manifest.json`](./manifest.json). Edit that file to add/remove tools.

| Category | Tools |
|---|---|
| **VCS** | git, git-lfs, gh |
| **Shell** | pwsh 7 (Win), Windows Terminal (Win), starship |
| **Runtimes** | Node (via nvm), Bun (official), Python 3.13, uv, pipx, Rust (rustup), JDK 21 (Temurin), Maven, Gradle, Go |
| **C/C++** | MinGW-w64 + CMake + Ninja (Win); build-essential + clang + cmake + ninja (Linux) |
| **CLI** | ripgrep, fd, fzf, bat, eza, jq, curl, wget, httpie, dog |
| **Cloud** | AWS CLI |
| **Editors** | Neovim, Zed |
| **Fonts** | JetBrainsMono Nerd Font |

Windows uses **scoop** as the primary package manager (auto-bootstrapped). Linux uses **apt** with extra repos for Adoptium / GitHub CLI / eza added on demand.

## Bootstrap on a fresh machine

> Replace `shubhampaithankar` in the URLs below (and in the two scripts) with your GitHub username after pushing this repo.

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/shubhampaithankar/pathbin/main/install.ps1 | iex
```

### Linux / WSL (bash)

```bash
curl -fsSL https://raw.githubusercontent.com/shubhampaithankar/pathbin/main/install.sh | bash
```

Both scripts are idempotent — re-running skips anything already installed.

## Local usage (after cloning)

```powershell
# Windows
.\install.ps1                              # full install
.\install.ps1 -Categories runtime,cli      # subset only
.\install.ps1 -Manifest .\manifest.json    # explicit manifest

# Linux / WSL
./install.sh
./install.sh --categories runtime,cli
./install.sh --manifest ./manifest.json
```

## Editing the manifest

Each tool row:

```json
{
  "name":   "ripgrep",
  "category": "cli",
  "win":   { "via": "scoop", "pkg": "main/ripgrep" },
  "linux": { "via": "apt",   "pkg": "ripgrep" },
  "verify": "rg --version"
}
```

`via` accepts:
- `scoop` — `scoop install <pkg>` (Windows)
- `winget` — `winget install --id <pkg>` (Windows)
- `apt` — `sudo apt-get install -y <pkg>` (Linux); add `"repo": "<id>"` to require a repo from `apt_repos`
- `custom` — dispatches to a named handler in the script (Bun, rustup, nvm, etc.)

Set `"win": null` or `"linux": null` to skip that platform.

## Adding a custom installer

Add the entry to `manifest.json` with `"via": "custom", "handler": "<name>"`, then implement the handler in the script:

- **PowerShell** (`install.ps1`): add an `Install-<Name>` function and a case in the `switch ($win.handler)` block.
- **Bash** (`install.sh`): add an `install_<name>()` function and a case in `dispatch_custom()`.

## What the scripts touch

- **PATH**: scoop / cargo / rustup / bun / nvm install into user-scope dirs and update PATH themselves. The scripts also patch:
  - Windows: `$PROFILE` — prepends `~/.bun/bin`, `~/.cargo/bin`, `~/.local/bin`; inits starship.
  - Linux: `~/.bashrc` and `~/.zshrc` — same idea, plus loads `nvm`.
- **No system-wide changes** beyond what apt requires (sudo for installs and `/etc/apt/keyrings/*`).

## Known gaps / not handled

- macOS (would need a `darwin` block + brew). Easy to add — open an issue.
- Non-apt Linux (Fedora, Arch). Same.
- WSL2 itself — install via `wsl --install Ubuntu` from elevated PowerShell first, then run `install.sh` inside WSL.
- Docker Desktop, kubectl, terraform, Azure CLI — not in current manifest. Add to `manifest.json` if you want them.

## License

MIT.
