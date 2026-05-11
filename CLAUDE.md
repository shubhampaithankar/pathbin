# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Strictly follow global rules at @~/.claude/CLAUDE.md.** This file only adds project-specific facts and overrides — it never relaxes a global rule.

## What this repo is

`pathbin` is a single-source-of-truth dev-environment bootstrap. One JSON manifest declares every tool; two install scripts (PowerShell for Windows, bash for Linux/WSL) consume the manifest and provision a fresh machine. Re-running is idempotent. Distribution model: clone or `irm | iex` / `curl | bash` from a public GitHub repo.

## Stack
- Manifest: JSON (`manifest.json`) — schema is informal but stable; see "Manifest schema" below
- Windows installer: PowerShell 5.1+ compatible (must work with the OS-default `powershell.exe`, not just `pwsh` 7)
- Linux installer: bash 4+, targets Debian/Ubuntu/WSL via `apt` only (other distros not yet supported)
- Package managers driven: `scoop` (primary, Win), `winget` (fallback, Win), `apt` (Linux), plus per-tool official installers

## Commands

```powershell
# Validate before commit
jq -e '.tools | length' manifest.json                    # parse + count tools
bash -n install.sh                                        # bash syntax check
$errs = $null; [void][System.Management.Automation.Language.Parser]::ParseFile('install.ps1', [ref]$null, [ref]$errs); if ($errs) { $errs } else { 'ps1 OK' }   # PS parse check

# Run locally (against sibling manifest)
.\install.ps1                              # full install, all categories
.\install.ps1 -Categories runtime,cli      # subset
.\install.ps1 -Manifest .\manifest.json    # explicit manifest path
./install.sh                               # Linux equivalents
./install.sh --categories runtime,cli

# Re-sync git config after pulling new commits (idempotent)
.\configure.ps1                            # Windows; -NonInteractive to skip prompts
./configure.sh                             # Linux; --non-interactive to skip prompts
```

There are no unit tests, no build step, no lint config. Validation = the three syntax checks above.

## Manifest schema

Each `tools[]` row:
```json
{ "name": "<id>", "category": "<group>",
  "win":   { "via": "scoop|winget|custom", "pkg": "<bucket/name>" | "handler": "<name>", "repo": "<id>?" },
  "linux": { "via": "apt|custom",          "pkg": "<package>"      | "handler": "<name>", "repo": "<id>?" },
  "verify": "<cmd that prints version>" }
```
- `win` or `linux` may be `null` to skip that platform.
- `via: custom` requires a matching handler in BOTH scripts (`switch ($win.handler)` block in `install.ps1`, `dispatch_custom()` in `install.sh`).
- `via: apt` with `repo:` requires a matching entry in top-level `apt_repos[]`. Repo `list_line` supports `{CODENAME}` and `{ARCH}` placeholders.
- `verify` first token is used to test PATH presence; full string is run for output. `verify: null` skips verification entirely (use for tools with no CLI: redistributables, fonts, GUI editors).

## Conventions
- **Manifest is source of truth.** New tool → edit `manifest.json` only. Never hardcode a tool list inside the scripts.
- **Both scripts must stay in sync.** Any custom handler added on one platform should have an equivalent (or explicit `null` skip) on the other.
- **Idempotency is non-negotiable.** Every install path must short-circuit when the tool is already present. Use `Test-Cmd` (PS) / `have` (bash) before installing.
- **PATH changes go through profile shims**, not `setx /m` or `/etc/profile`. User-scope only — no admin required beyond apt.
- **Repo URL placeholder:** `<YOUR-USER>` appears in `install.ps1`, `install.sh`, and `README.md`. Search-and-replace before the first push.
- **CI invariants enforced by `validate.yml`:** every `via: custom` handler has a function defined in both scripts; every `repo:` reference resolves to an `apt_repos[]` entry; both scripts parse; shellcheck + PSScriptAnalyzer clean. A change that breaks any of these will fail CI — verify locally before pushing.

## Key Files
- `manifest.json` — declarative tool list + scoop buckets + apt repos. Edit this 95% of the time.
- `install.ps1` / `install.sh` — platform dispatchers. Custom handlers live as `Install-*` (PS) / `install_*` (bash); dispatch happens in `switch ($win.via)` / case statements. Both end by invoking the configure step (skippable via `-SkipConfigure` / `--skip-configure`).
- `configure.ps1` / `configure.sh` — apply user-level git config from `configs/git/`. Idempotent; safe to re-run after `git pull`. Identity resolution: `PATHBIN_GIT_NAME` / `PATHBIN_GIT_EMAIL` env > existing `git config` > prompt.
- `configs/git/gitconfig` — included into `~/.gitconfig` via `include.path`; no personal data.
- `configs/git/gitignore_global` — copied to `~/.gitignore_global`; wired via `core.excludesfile`.
- `.github/workflows/validate.yml` — CI: manifest schema, custom-handler cross-ref, repo cross-ref, bash + PowerShell parsers, shellcheck, PSScriptAnalyzer.
- `README.md` — user-facing bootstrap docs and one-liner curl/irm commands.

## Do NOT
- Use `npm install -g bun`. Bun must come from the official installer (`https://bun.sh/install.ps1` or `https://bun.sh/install`). See memory `feedback_bun_install_method.md`.
- Emit `.ps1` files containing em-dashes (`—`), en-dashes (`–`), or smart quotes. Windows PowerShell 5.1 reads no-BOM UTF-8 as ANSI and the lexer corrupts. Either keep ASCII-only or save with UTF-8-BOM. See memory `feedback_powershell_5_encoding.md`.
- Bake tool-specific install commands into the scripts. If it doesn't fit the manifest schema, add a `custom` handler and reference it from the manifest.
- Add a tool to one platform without considering the other — pick `null` deliberately, not by omission.
- Introduce a build step, package.json, or test framework. This repo is two scripts and a JSON file; keep it that way.

## On Compaction, Preserve
- Current `manifest.json` tool list and any in-flight schema changes
- Any custom handler additions not yet present in BOTH scripts
- Outstanding `<YOUR-USER>` placeholder replacements
