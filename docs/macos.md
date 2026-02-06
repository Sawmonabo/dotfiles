# macOS Setup

## Table of Contents

- [Installation](#installation)
- [What the Bootstrap Installs](#what-the-bootstrap-installs)
- [Shell: zsh](#shell-zsh)
- [Font Setup](#font-setup)
- [Daily Usage](#daily-usage)
- [Adding New Configs](#adding-new-configs)
- [Updating](#updating)
- [Oh My Posh Theme](#oh-my-posh-theme)
- [Troubleshooting](#troubleshooting)

## Installation

### Prerequisites

- **Xcode CLI Tools**: `xcode-select --install`
- Homebrew is installed automatically by the bootstrap if missing

### Fresh install (one command)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" && chezmoi init --apply Sawmonabo/dotfiles
```

### Step-by-step install

```bash
# 1. Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin

# 2. Init (prompts for name, email, editor — does NOT modify files yet)
chezmoi init Sawmonabo/dotfiles

# 3. Preview what will change
chezmoi diff

# 4. Apply
chezmoi apply -v
```

### Verify

```bash
chezmoi verify && echo "All good"
```

## What the Bootstrap Installs

| Tool | Method | Notes |
|------|--------|-------|
| Homebrew | Official install script | Detects ARM vs Intel path |
| bat | `brew install bat` | cat replacement with syntax highlighting |
| oh-my-posh | `brew install jandedobbeleer/oh-my-posh/oh-my-posh` | Prompt theme engine |
| JetBrains Mono Nerd Font | `brew install --cask font-jetbrains-mono-nerd-font` | Required for prompt icons |
| gh (GitHub CLI) | `brew install gh` | GitHub operations from terminal |

## Shell: zsh

macOS uses zsh as the default shell. The `.zshrc` includes:

- Oh My Posh with Catppuccin Mocha theme
- Aliases (`ls`, `cat`→bat, etc.)
- PATH setup for Homebrew, cargo, nvm, bun
- Completion via `compinit`
- Smart `code()` function (detects Cursor vs VS Code)

### `.zprofile` vs `.zshrc`

- `.zprofile` runs for **login shells** (new terminal windows)
- `.zshrc` runs for **interactive shells** (every new tab/pane)
- Homebrew's `shellenv` goes in `.zshrc` to ensure it's always available

## Font Setup

After the bootstrap installs JetBrains Mono Nerd Font, set it in your terminal:

### iTerm2

Preferences → Profiles → Text → Font → "JetBrainsMono Nerd Font"

### Terminal.app

Preferences → Profiles → Font → Change → "JetBrainsMono Nerd Font"

### Ghostty

Add to `~/.config/ghostty/config`:

```ini
font-family = JetBrainsMono Nerd Font
```

### Alacritty

Add to `~/.config/alacritty/alacritty.toml`:

```toml
[font.normal]
family = "JetBrainsMono Nerd Font"
```

## Daily Usage

### Pull and apply latest changes

```bash
chezmoi update -v
```

### Edit a config

```bash
chezmoi edit ~/.zshrc      # opens source template in $EDITOR
chezmoi diff               # preview the change
chezmoi apply              # deploy it
```

### Check for drift

```bash
chezmoi verify             # exit code 0 = everything matches
chezmoi diff               # see what differs
```

### Re-run setup prompts

```bash
chezmoi init               # re-prompts for name, email, editor
```

## Adding New Configs

### Add an existing file

```bash
chezmoi add ~/.some-config                # plain file
chezmoi add --template ~/.some-config     # template (uses chezmoi variables)
```

### Add a macOS-only file

1. Add the file: `chezmoi add ~/.macos-specific-config`
2. Edit `.chezmoiignore` to exclude it on other platforms:

```text
{{ if ne .chezmoi.os "darwin" }}
.macos-specific-config
{{ end }}
```

### Commit and push changes

```bash
chezmoi cd                 # enter source directory
git add -A && git commit -m "Add new config"
git push
```

## Updating

### Update chezmoi itself

```bash
chezmoi upgrade
```

### Re-run bootstrap (install new tools)

Bootstrap scripts use `run_once_before_` prefix — they only run once. To force a re-run:

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

## Oh My Posh Theme

The Catppuccin Mocha theme is deployed to `~/.config/oh-my-posh/catppuccin_mocha.omp.json`.

To customize:

```bash
chezmoi edit ~/.config/oh-my-posh/catppuccin_mocha.omp.json
chezmoi apply
source ~/.zshrc
```

## Troubleshooting

### Homebrew ARM vs Intel path

- **Apple Silicon** (M1+): `/opt/homebrew/bin/brew`
- **Intel**: `/usr/local/bin/brew`

The `.zshrc` detects both automatically.

### Font not rendering icons

Clear the font cache:

```bash
sudo atsutil databases -remove
atsutil server -shutdown
atsutil server -ping
```

### oh-my-posh not found after install

Ensure Homebrew's bin is in PATH:

```bash
which oh-my-posh
brew --prefix
```

### chezmoi not found

Ensure `~/.local/bin` is in PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```
