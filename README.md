# Dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/). Supports macOS (zsh), Linux/Ubuntu (bash), and WSL (bash + Windows integration).

## Table of Contents

- [Quick Start](#quick-start)
- [What's Managed](#whats-managed)
- [What Gets Installed](#what-gets-installed)
- [Daily Usage](#daily-usage)
- [How Syncing Works](#how-syncing-works)
- [Customization](#customization)
- [Repo Structure](#repo-structure)
- [Platform Docs](#platform-docs)

## Quick Start

### Fresh machine (one command)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" && chezmoi init --apply Sawmonabo/dotfiles
```

Chezmoi will prompt for your name, emails, preferred editor, and whether to
install **pinned** or **latest** tool versions, then automatically:

1. Detect your OS
2. Run the platform bootstrap (install bat, oh-my-posh, Nerd Font, etc.)
3. Deploy all config files

### Existing machine (safe approach)

```bash
# 1. Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin

# 2. Init without applying (prompts for name, email, editor)
chezmoi init Sawmonabo/dotfiles

# 3. Preview what would change
chezmoi diff

# 4. Apply after reviewing
chezmoi apply -v
```

## What's Managed

| Config | macOS | Linux | WSL | Windows (from WSL) |
|--------|:-----:|:-----:|:---:|:------------------:|
| `.bashrc` | | x | x | |
| `.zshrc` | x | | | |
| `.gitconfig` | x | x | x | |
| `.gitconfig-personal` | x | x | x | |
| `.claude/settings.json` | x | x | x | |
| Oh My Posh theme | x | x | x | x |
| Windows Terminal settings | | | | x |
| PowerShell profile | | | | x |

## What Gets Installed

### macOS

- [bat](https://github.com/sharkdp/bat) (via Homebrew)
- [oh-my-posh](https://ohmyposh.dev/) (via Homebrew tap)
- [JetBrains Mono Nerd Font](https://www.nerdfonts.com/) (via Homebrew cask)
- [gh](https://cli.github.com/) (via Homebrew)

### Linux / WSL

- bat (via cargo)
- oh-my-posh (via install script)
- JetBrains Mono Nerd Font (via GitHub release)

**Runtime managers** (`run_once_after_10`): nvm, uv, rustup, bun, Go — versions
from `home/.chezmoidata/versions.toml`.

**Runtimes** (`run_onchange_after_20`): pinned Node versions + default alias,
uv-managed Pythons, Rust toolchain. Re-runs automatically when the pins change.

**Global tools** (`run_onchange_after_30`): codex, claude,
corepack pnpm/yarn, uv tools, cargo tools, go tools, and podman (via apt).

The `versions_mode` prompt at `chezmoi init` chooses **pinned** (exact recorded
versions) or **latest** (newest in each recorded line). Re-run `chezmoi init`
to change your answer. Reference lists that stay manual: `home/.chezmoidata/packages.toml` holds the
recorded apt package names (need sudo + per-release availability review) and
VS Code extension IDs (need the Windows `code` command).

### Windows (from WSL)

- oh-my-posh.exe + themes
- JetBrains Mono Nerd Font (user fonts + registry)
- Windows Terminal settings (Catppuccin Mocha, keybindings, profiles)
- PowerShell profile (Oh My Posh init)

## Daily Usage

### Pull and apply updates

```bash
chezmoi update -v          # git pull + apply in one step
```

Or step by step:

```bash
chezmoi git pull -- --rebase
chezmoi diff               # preview changes
chezmoi apply -v           # apply
```

### Edit a managed file

```bash
chezmoi edit ~/.bashrc     # opens source template in $EDITOR
chezmoi apply              # deploy the change
```

### Add a new file to chezmoi

```bash
chezmoi add ~/.some-config           # add as plain file
chezmoi add --template ~/.some-config # add as template (for chezmoi variables)
```

### Check for drift

```bash
chezmoi diff               # show what differs from desired state
chezmoi verify             # exit code 0 = no drift
```

### Re-run init (change name/email/editor)

```bash
chezmoi init
```

## How Syncing Works

Chezmoi does **not** auto-sync. Every step is manual and deliberate:

```text
1. Edit config       chezmoi edit ~/.bashrc
2. Deploy locally    chezmoi apply
3. Commit & push     cd ~/dev/dotfiles && git add -A && git commit -m "..." && git push
4. Pull elsewhere    chezmoi update -v   (on your other machine)
```

- **Changes to live files are not tracked.** If you edit `~/.bashrc` directly, chezmoi doesn't know. Use `chezmoi edit` or `chezmoi add` to update the source.
- **Nothing is committed or pushed automatically.** You decide when to snapshot and share.
- **Other machines don't auto-update.** Run `chezmoi update -v` to pull and apply.

This keeps you in control — no half-finished changes get pushed, and no unexpected overwrites happen on other machines.

## Customization

### Git identity per directory

`.gitconfig` uses your default email (`.email`) globally. Repos under `~/dev/` automatically switch to your personal email via Git's `includeIf` and `.gitconfig-personal`.

To change either email, re-run `chezmoi init` or edit the source:

```bash
chezmoi edit ~/.gitconfig-personal
chezmoi apply
```

### Local aliases

`~/.bash_aliases` is sourced by `.bashrc` but **not managed** by chezmoi — use it for machine-specific aliases.

### Oh My Posh theme

```bash
chezmoi edit ~/.config/oh-my-posh/catppuccin_mocha.omp.json
chezmoi apply
```

## Repo Structure

```text
~/dev/dotfiles/
├── README.md                                              # This file
├── CLAUDE.md                                               # Repo dev docs (never deploys)
├── .chezmoiroot                                            # One line: "home" — the deploy boundary
├── .github/workflows/ci.yml                                # Render + lint + secret-scan
├── docs/                                                    # Platform documentation
└── home/                                                    # Mirrors ~ — everything here can deploy
    ├── .chezmoi.toml.tmpl                                   # Interactive setup prompts
    ├── .chezmoiignore                                       # OS-conditional ignores
    ├── .chezmoidata/
    │   ├── versions.toml                                    # Pinned tool/runtime versions
    │   └── packages.toml                                    # apt package names + VS Code extension IDs
    ├── .chezmoitemplates/
    │   └── nvm-load.sh                                      # Shared nvm guard+source fragment
    ├── .chezmoiscripts/
    │   ├── linux/                                           # run_once_before_00-packages.sh.tmpl, etc.
    │   ├── darwin/                                          # run_once_before_00-packages.sh.tmpl, etc.
    │   └── wsl/                                             # run_once_before_00-packages-windows.sh.tmpl, etc.
    ├── private_dot_bashrc.tmpl                              # → ~/.bashrc (Linux/WSL)
    ├── dot_zshrc.tmpl                                       # → ~/.zshrc (macOS)
    ├── dot_gitconfig.tmpl                                   # → ~/.gitconfig (all)
    ├── dot_gitconfig-personal.tmpl                          # → ~/.gitconfig-personal (all)
    ├── dot_claude/                                          # → ~/.claude/
    ├── dot_codex/                                           # → ~/.codex/
    └── dot_config/oh-my-posh/catppuccin_mocha.omp.json      # → ~/.config/oh-my-posh/
```

> **Note on `dot_`/`private_` prefixes**: chezmoi convention — `dot_bashrc` deploys as `~/.bashrc`,
> `private_dot_bashrc` deploys as `~/.bashrc` with restricted permissions.
> The `run_once_before_` prefix means the script runs once, before file deployment; `run_onchange_after_`
> means it re-runs whenever its content changes, after file deployment.

## Platform Docs

- [macOS setup](docs/macos.md)
- [Linux setup](docs/linux.md)
- [WSL + Windows integration](docs/wsl.md)
- [Windows Terminal reference](docs/windows-terminal.md)
- [Chezmoi local overrides reference](docs/chezmoi-local-overrides.md)
