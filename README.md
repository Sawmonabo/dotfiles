# Dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/). Supports macOS (zsh), Linux/Ubuntu (bash), and WSL (bash + Windows integration).

## Table of Contents

- [Quick Start](#quick-start)
- [What's Managed](#whats-managed)
- [What Gets Installed](#what-gets-installed)
- [Daily Usage](#daily-usage)
- [Customization](#customization)
- [Repo Structure](#repo-structure)
- [Platform Docs](#platform-docs)

## Quick Start

### Fresh machine (one command)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" && chezmoi init --apply Sawmonabo/dotfiles
```

Chezmoi will prompt for your name, emails, and preferred editor, then automatically:

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

## Customization

### Git identity per directory

`.gitconfig` uses your work email as the default. Repos under `~/dev/` automatically switch to your personal email via Git's `includeIf` and `.gitconfig-personal`.

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
├── .chezmoi.toml.tmpl                                  # Interactive setup prompts
├── .chezmoiignore                                      # OS-conditional ignores
├── dot_bashrc.tmpl                                     # → ~/.bashrc (Linux/WSL)
├── dot_zshrc.tmpl                                      # → ~/.zshrc (macOS)
├── dot_gitconfig.tmpl                                  # → ~/.gitconfig (all)
├── dot_gitconfig-personal.tmpl                         # → ~/.gitconfig-personal (all)
├── dot_config/oh-my-posh/catppuccin_mocha.omp.json     # → ~/.config/oh-my-posh/
├── run_once_before_install-packages-linux.sh.tmpl       # Linux/WSL bootstrap
├── run_once_before_install-packages-darwin.sh.tmpl      # macOS bootstrap
├── run_once_before_install-packages-windows.sh.tmpl     # WSL → Windows config
└── docs/                                                # Platform documentation
```

> **Note on `dot_` prefix**: chezmoi convention — `dot_bashrc` deploys as `~/.bashrc`.
> The `run_once_before_` prefix means the script runs once, before file deployment.

## Platform Docs

- [macOS setup](docs/macos.md)
- [Linux setup](docs/linux.md)
- [WSL + Windows integration](docs/wsl.md)
- [Windows Terminal reference](docs/windows-terminal.md)
- [Chezmoi local overrides reference](docs/chezmoi-local-overrides.md)
