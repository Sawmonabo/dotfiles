# Dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/). Supports macOS (zsh), Linux/Ubuntu (bash), and WSL (bash + Windows integration).

## Architecture

The repo root is project scaffolding (`README.md`, `CLAUDE.md`, `docs/`, `.github/`) plus one deploy boundary: `.chezmoiroot` points chezmoi at `home/`, so only files under `home/` can ever reach `~`. Nothing outside `home/` is deployable, and nothing under `home/` is documentation.

Within `home/`, chezmoi templates deploy to `~` on each platform using chezmoi's naming convention: `private_dot_bashrc.tmpl` deploys as `~/.bashrc`, scripts under `.chezmoiscripts/<platform>/` run once/on-change before or after file deployment per their phase number.

### Key files

| Source file | Deploys to | Notes |
|---|---|---|
| `home/.chezmoi.toml.tmpl` | `~/.config/chezmoi/chezmoi.toml` | Interactive prompts for name, emails, editor, versions mode; WSL memory/paths and API tokens |
| `home/private_dot_bashrc.tmpl` | `~/.bashrc` | Linux/WSL only (ignored on macOS) |
| `home/dot_zshrc.tmpl` | `~/.zshrc` | macOS only (ignored on Linux); includes uv shell completions |
| `home/dot_gitconfig.tmpl` | `~/.gitconfig` | All platforms; uses `includeIf` for personal email |
| `home/dot_gitconfig-personal.tmpl` | `~/.gitconfig-personal` | Personal email for repos under `~/dev/` |
| `home/dot_claude/` | `~/.claude/` | `CLAUDE.md` and `private_settings.json` |
| `home/dot_codex/` | `~/.codex/` | `AGENTS.md`, `private_config.toml.tmpl`, `private_hooks.json` |
| `home/dot_config/` | `~/.config/` | `oh-my-posh/catppuccin_mocha.omp.json` (theme, all platforms) and `tmux/tmux.conf` |
| `home/.chezmoiscripts/linux/run_once_before_00-packages.sh.tmpl` | (run script) | Linux/WSL bootstrap: installs bat, oh-my-posh, Nerd Font, gh |
| `home/.chezmoiscripts/linux/run_once_after_10-runtime-managers.sh.tmpl` | (run script) | Installs nvm, uv, rustup, bun, Go managers |
| `home/.chezmoiscripts/linux/run_onchange_after_20-runtimes.sh.tmpl` | (run script) | Pinned Node versions + default alias, uv Pythons, Rust toolchain; re-runs when pins change |
| `home/.chezmoiscripts/linux/run_onchange_after_30-global-tools.sh.tmpl` | (run script) | codex, claude, corepack pnpm/yarn, uv tools, cargo tools, go tools, podman |
| `home/.chezmoiscripts/linux/run_onchange_after_40-tmux-plugins.sh.tmpl` | (run script) | tmux plugin manager + plugins |
| `home/.chezmoiscripts/darwin/run_once_before_00-packages.sh.tmpl` | (run script) | macOS bootstrap: Homebrew, bat, oh-my-posh, Nerd Font, gh |
| `home/.chezmoiscripts/darwin/run_onchange_after_10-terminal-font.sh.tmpl` | (run script) | Instructions for Terminal.app font setup (macOS only) |
| `home/.chezmoiscripts/wsl/run_once_before_00-packages-windows.sh.tmpl` | (run script) | WSL only; installs oh-my-posh.exe, fonts, Windows Terminal settings, PowerShell profile |
| `home/.chezmoiscripts/wsl/run_onchange_after_10-deploy-windows-configs.sh.tmpl` | (run script) | WSL only; merges `.wslconfig` and deploys RestartWSL scripts to Windows |
| `home/.chezmoiscripts/wsl/run_onchange_after_20-cursor-terminal-font.sh.tmpl` | (run script) | Configures Cursor terminal to use Nerd Font (WSL only) |
| `home/.chezmoitemplates/nvm-load.sh` | (template fragment) | Shared NVM_DIR export + `source nvm.sh` guard block, included via `{{ template "nvm-load.sh" }}` |
| `home/.chezmoidata/versions.toml` | (data) | Pinned tool/runtime versions used by `versions_mode=pinned` |
| `home/.chezmoidata/packages.toml` | (data) | Recorded apt package names and VS Code extension IDs (manual reference, not scripted) |
| `.github/workflows/ci.yml` | (CI) | Renders every template (pinned and latest modes), syntax-checks and shellchecks the output, scans for secrets |

### Template variables

Defined in `home/.chezmoi.toml.tmpl` via `promptStringOnce`/`promptChoiceOnce`:
- `.name` — Git user name
- `.email` — Git default email (all repos unless overridden)
- `.personal_email` — Git personal email (for `~/dev/` repos)
- `.editor` — Preferred editor (`cursor`/`code`/`vim`)
- `.versions_mode` — `pinned` or `latest` tool versions
- `.wsl_memory` — WSL memory limit, e.g. `8GB` (WSL only)
- `.restart_wsl_path` — RestartWSL scripts location, relative to Windows home or full path (WSL only)
- `.jira_api_token` — Jira API token for Codex MCP (secret; stored only in the local `chezmoi.toml` on that machine, never in the repo)
- `.gitlab_token` — GitLab token for Codex MCP (secret; same local-only storage)

### Platform gating

- `home/.chezmoiignore` conditionally excludes files per OS (`ne .chezmoi.os "linux"`, etc.)
- `.chezmoiscripts/` scripts are grouped by platform directory (`linux/`, `darwin/`, `wsl/`); `wsl/` is a repo convention, not a chezmoi OS — those scripts still guard with `(.chezmoi.kernel.osrelease | lower | contains "microsoft")`

## Conventions

- **Template syntax**: Go templates with chezmoi data (e.g., `{{ .name }}`, `{{ .chezmoi.os }}`)
- **File naming**: Follow chezmoi conventions (`dot_`, `private_`, `.tmpl`, `run_once_before_`, `run_onchange_after_`)
- **Script naming**: `run_{once|onchange}_{before|after}_NN-<verb-noun>.sh.tmpl`, one platform directory per script; `NN` orders scripts within a directory
- **Local overrides**: `~/.bash_aliases` is sourced by `.bashrc` but not managed by chezmoi

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
