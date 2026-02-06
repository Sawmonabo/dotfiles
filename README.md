# Dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/). Supports macOS (zsh), Linux/Ubuntu (bash), and WSL (bash + Windows integration).

## Quick Start

One command on any machine:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" && chezmoi init --apply Sawmonabo/dotfiles
```

Chezmoi will prompt for your name, email, and preferred editor, then automatically:
1. Detect your OS
2. Run the platform bootstrap (install bat, oh-my-posh, Nerd Font, etc.)
3. Deploy all config files

## What's Managed

| Config | macOS | Linux | WSL | Windows (from WSL) |
|--------|:-----:|:-----:|:---:|:------------------:|
| `.bashrc` | | x | x | |
| `.zshrc` | x | | | |
| `.gitconfig` | x | x | x | |
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

## Customization

### Chezmoi data

Re-run `chezmoi init` to update your name, email, or editor:

```bash
chezmoi init
```

### Adding new managed files

```bash
chezmoi add ~/.some-config    # Add a file to chezmoi management
chezmoi edit ~/.some-config   # Edit the source template
chezmoi apply                 # Apply changes
```

### Local aliases

`~/.bash_aliases` is sourced by `.bashrc` but **not managed** by chezmoi — use it for machine-specific aliases.

## Platform Docs

- [macOS setup](docs/macos.md)
- [Linux setup](docs/linux.md)
- [WSL + Windows integration](docs/wsl.md)
- [Windows Terminal reference](docs/windows-terminal.md)
