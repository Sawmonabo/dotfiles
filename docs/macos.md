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

`run_once_before_00-packages` installs Homebrew if it is missing (detecting the
Apple Silicon `/opt/homebrew` vs Intel `/usr/local` prefix), writes a temporary
Brewfile from the package data, and runs `brew bundle install --no-upgrade` on
it — missing formulae and casks are installed, anything already present is left
at the version it has. It then clones TPM into `~/.tmux/plugins/tpm`, installs
bitwarden-cli on work machines (`machine_role` work or both), and installs every
VS Code extension that `code --list-extensions` does not already report.

See [packages.toml](../home/.chezmoidata/packages.toml) under `[packages.darwin]`
for the exact formula and cask set; runtime managers and global tools follow the
same `versions.toml` pins as Linux.

Three scripts run after the files are deployed:

| Script | What it does |
|--------|--------------|
| `run_once_after_10-runtime-managers` | nvm and rustup via their upstream installers; uv, bun and Go come from Homebrew and are only verified here |
| `run_onchange_after_20-runtimes` | Node versions + default alias (nvm), Pythons (uv), Rust toolchain (rustup) |
| `run_onchange_after_30-global-tools` | codex, claude, corepack pnpm/yarn, uv tools, cargo tools, go tools; checks that the docker CLI is on PATH |

Each of the three puts Homebrew on PATH itself, because chezmoi runs scripts in
a non-login shell that has not sourced `.zshrc`.

## Shell: zsh

macOS uses zsh as the default shell. The `.zshrc` includes:

- Oh My Posh with Catppuccin Mocha theme
- Aliases (`ls`, `cat`→bat, etc.)
- PATH setup for Homebrew, cargo, nvm, bun
- Completion via `compinit`
- `~/.zshrc.local` is sourced last and is not managed by chezmoi; put machine-specific aliases and installer blocks there

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

### A cask refuses to install over an app you installed by hand

`brew bundle` fails with `It seems there is already an App at /Applications/...`
when a cask's app was installed outside Homebrew. Adopt it once, then re-run:

```bash
brew install --cask --adopt <name>
chezmoi apply -v
```

### chezmoi not found

Ensure `~/.local/bin` is in PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```
