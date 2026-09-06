# Dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/). Supports macOS (zsh), Linux/Ubuntu (bash), and WSL (bash + Windows integration).

## Architecture

The repo root is project scaffolding (`README.md`, `CLAUDE.md`, `docs/`, `.github/`) plus one deploy boundary: `.chezmoiroot` points chezmoi at `home/`, so only files under `home/` can ever reach `~`. Nothing outside `home/` is deployable, and nothing under `home/` is documentation.

Within `home/`, chezmoi templates deploy to `~` on each platform using chezmoi's naming convention: `private_dot_bashrc.tmpl` deploys as `~/.bashrc`, scripts under `.chezmoiscripts/<platform>/` run once/on-change before or after file deployment per their phase number.

### Key files

| Source file | Deploys to | Notes |
|---|---|---|
| `home/.chezmoi.toml.tmpl` | `~/.config/chezmoi/chezmoi.toml` | Interactive prompts for name, email, machine role, editor, versions mode; personal/work emails only for `both`; API tokens only when `has_work`; WSL sizing on WSL |
| `home/private_dot_bashrc.tmpl` | `~/.bashrc` | Linux/WSL only (ignored on macOS) |
| `home/dot_zshrc.tmpl` | `~/.zshrc` | macOS only (ignored on Linux); includes uv shell completions |
| `home/dot_gitconfig.tmpl` | `~/.gitconfig` | All platforms; emits `includeIf` only when `machine_role=both` |
| `home/dot_gitconfig-personal.tmpl` | `~/.gitconfig-personal` | Personal email for repos under `~/dev/`; only when `machine_role=both` |
| `home/dot_gitconfig-work.tmpl` | `~/.gitconfig-work` | Work email for repos under `~/repos/`; only when `machine_role=both` |
| `home/dot_claude/` | `~/.claude/` | `CLAUDE.md` and `private_settings.json` |
| `home/dot_codex/` | `~/.codex/` | `AGENTS.md.tmpl`, `modify_private_config.toml.tmpl`, `private_hooks.json.tmpl` (hooks only when `has_work`). The config is a chezmoi `modify_` template: it renders to a Python script that merges the managed body with the Codex-owned tables read from the existing `~/.codex/config.toml`, so Codex's own runtime state survives an apply. |
| `home/dot_config/` | `~/.config/` | `oh-my-posh/catppuccin_mocha.omp.json` (theme, all platforms) and `tmux/tmux.conf` |
| `home/.chezmoiscripts/linux/run_once_before_00-packages.sh.tmpl` | (run script) | Linux/WSL bootstrap: build-essential, bat, fd (apt `fd-find`, symlinked `fdfind`→`fd` in ~/.local/bin), oh-my-posh + themes, Nerd Font, gh (upstream static binary to ~/.local/bin, no sudo), tmux, TPM; bitwarden-cli (static binary to ~/.local/bin) only when `has_work` |
| `home/.chezmoiscripts/linux/run_once_after_10-runtime-managers.sh.tmpl` | (run script) | Installs nvm, uv, rustup, bun, Go managers |
| `home/.chezmoiscripts/linux/run_onchange_after_20-runtimes.sh.tmpl` | (run script) | Pinned Node versions + default alias, uv Pythons, Rust toolchain; re-runs when pins change |
| `home/.chezmoiscripts/linux/run_onchange_after_30-global-tools.sh.tmpl` | (run script) | codex, claude, corepack pnpm/yarn, uv tools, cargo tools, go tools, podman |
| `home/.chezmoiscripts/shared/run_onchange_after_40-tmux-plugins.sh.tmpl` | (run script) | Every platform; installs tmux plugins via TPM when tmux.conf changes |
| `home/.chezmoiscripts/darwin/run_once_before_00-packages.sh.tmpl` | (run script) | macOS bootstrap: Homebrew, then every formula and cask under `[packages.darwin]` in `packages.toml` via `brew bundle install --no-upgrade` (a temp Brewfile, removed on exit), TPM, and the `packages.vscode_extensions` set via `code --install-extension`; bitwarden-cli only when `has_work` |
| `home/.chezmoiscripts/darwin/run_once_after_10-runtime-managers.sh.tmpl` | (run script) | nvm and rustup via their upstream installers; uv, bun and Go come from Homebrew and are only verified here. This and the two darwin scripts below put Homebrew on PATH themselves — chezmoi runs scripts in a non-login shell |
| `home/.chezmoiscripts/darwin/run_onchange_after_45-terminal-font.sh.tmpl` | (run script) | Instructions for Terminal.app font setup (macOS only) |
| `home/.chezmoiscripts/darwin/run_onchange_after_20-runtimes.sh.tmpl` | (run script) | Mirrors the linux 20-runtimes script: pinned Node versions + default alias, uv Pythons, Rust toolchain; re-runs when pins change |
| `home/.chezmoiscripts/darwin/run_onchange_after_30-global-tools.sh.tmpl` | (run script) | codex, claude, corepack pnpm/yarn, uv tools, cargo tools, go tools; checks for the docker CLI (Homebrew formula + Docker Desktop) instead of installing podman |
| `home/.chezmoiscripts/wsl/run_once_before_00-packages-windows.sh.tmpl` | (run script) | WSL only; installs oh-my-posh.exe, fonts, Windows Terminal settings, PowerShell profile |
| `home/.chezmoiscripts/wsl/run_onchange_after_10-deploy-windows-configs.sh.tmpl` | (run script) | WSL only; merges `.wslconfig` (memory/processors/swap from chezmoi data, mirrored networking, vmIdleTimeout, autoMemoryReclaim, sparseVhd) and deploys RestartWSL scripts to Windows |
| `home/.chezmoiscripts/wsl/run_onchange_after_20-sysctl.sh.tmpl` | (run script) | WSL only; writes `/etc/sysctl.d/99-dev.conf` (`vm.swappiness=10`); needs sudo, skips gracefully without a tty |
| `home/.chezmoitemplates/nvm-load.sh` | (template fragment) | Shared NVM_DIR export + `source nvm.sh` guard block, included via `{{ template "nvm-load.sh" }}` |
| `home/.chezmoitemplates/bw-wrapper.sh` | (template fragment) | Bitwarden `bw unlock`/`bw lock` wrapper, included by `.bashrc` and `.zshrc` only when `has_work` |
| `home/.chezmoidata/versions.toml` | (data) | Pinned tool/runtime versions used by `versions_mode=pinned` |
| `home/.chezmoidata/packages.toml` | (data) | `[packages.darwin]` brew/cask lists installed by the macOS bootstrap; `vscode_extensions` is the canonical set for every platform; the apt list is still a manual reference, not scripted |
| `scripts/scratch-init.sh` | (dev tool) | Generates a throwaway `chezmoi.toml` for one role with every prompt answered; prompt-text keys must match `.chezmoi.toml.tmpl` |
| `scripts/render-check.sh` | (dev tool) | Renders the whole tree for one role into a temp dir, lints scripts, checks for work/home-path leaks and the status line; what CI runs. Optional third arg `wsl` fakes a WSL host and lints only, so the `wsl/` scripts get syntax coverage |
| `.github/workflows/ci.yml` | (CI) | Renders every template (pinned and latest modes), syntax-checks and shellchecks the output, scans for secrets |

### Template variables

Defined in `home/.chezmoi.toml.tmpl` via `promptStringOnce`/`promptChoiceOnce`:
- `.name` — Git user name
- `.email` — Git default email (all repos unless overridden)
- `.machine_role` — `personal`, `work`, or `both` (default `personal`). Derived booleans stored alongside it: `.has_work`, `.has_personal`, `.is_wsl`. Gate templates on the booleans, never re-derive them.
- `.personal_email` — Git personal email for `~/dev/` repos (only prompted when `machine_role=both`)
- `.work_email` — Git work email for `~/repos/` (only prompted when `machine_role=both`)
- `.editor` — Preferred editor (`code`/`vim`, default `code`)
- `.versions_mode` — `pinned` or `latest` tool versions
- `.wsl_memory` — WSL memory limit (WSL only). Default derived from the Windows host via `powershell.exe`: 75% of physical RAM
- `.wsl_processors` — WSL vCPUs (WSL only). Default: 2/3 of the host's logical CPUs
- `.wsl_swap` — WSL swap size (WSL only). Default: memory/6
- `.restart_wsl_path` — RestartWSL scripts location, relative to Windows home or full path (WSL only)
- `.jira_api_token` — Jira API token for Codex MCP (only prompted when `has_work`; secret, stored only in the local `chezmoi.toml` on that machine, never in the repo)
- `.gitlab_token` — GitLab token for Codex MCP (only prompted when `has_work`; secret, same local-only storage)

### Platform gating

- `home/.chezmoiignore` conditionally excludes files per OS (`ne .chezmoi.os "linux"`, etc.)
- `.chezmoiscripts/` scripts are grouped by platform directory (`linux/`, `darwin/`, `wsl/`, `shared/`); `wsl/` is a repo convention, not a chezmoi OS — those scripts guard with `{{ if .is_wsl }}`. `.chezmoi.kernel` is empty on macOS, so never read `.chezmoi.kernel.osrelease` directly in a template.

## Conventions

- **Template syntax**: Go templates with chezmoi data (e.g., `{{ .name }}`, `{{ .chezmoi.os }}`)
- **File naming**: Follow chezmoi conventions (`dot_`, `private_`, `.tmpl`, `run_once_before_`, `run_onchange_after_`)
- **Script naming**: `run_{once|onchange}_{before|after}_NN-<verb-noun>.sh.tmpl`, one platform directory per script; `NN` orders scripts within a directory
- **Local overrides**: `~/.bash_aliases` is sourced by `.bashrc` but not managed by chezmoi
- **Output style**: `outputStyle` is the built-in `Concise` (Claude Code ≥ 2.1.260); never add a custom style with that name.
- **Editor**: VS Code only. No other-IDE references or IDE-routing shell wrappers. **Claude wrapper**: both rc files define the function `claude() { command claude --verbose --allow-dangerously-skip-permissions "$@"; }` (a function, not an alias, so it works with alias expansion off and inside other functions) and nothing else manages it.

## Development workflow

```bash
# Preview changes before applying
chezmoi diff

# Apply changes
chezmoi apply -v

# Edit a managed file
chezmoi edit ~/.bashrc
chezmoi apply
```

## Testing changes

Always run `chezmoi diff` before `chezmoi apply` to preview what will change. Be cautious with `run_once_before_` scripts — they execute once per machine and install system packages. CI (`.github/workflows/ci.yml`) renders every template in both `versions_mode` variants and lints the rendered scripts on every push and pull request, but does not apply anything.

Run `scripts/render-check.sh <role> <mode>` (and `scripts/render-check.sh work pinned wsl` when touching `wsl/`) locally before pushing; it is exactly what CI runs and never touches `~`. After pulling a change to `home/.chezmoi.toml.tmpl`, run `chezmoi init` (no apply) to answer any new prompt before `chezmoi diff`.
