# Linux Setup

## Table of Contents

- [Installation](#installation)
- [What the Bootstrap Installs](#what-the-bootstrap-installs)
- [Shell: bash](#shell-bash)
- [Font Installation](#font-installation)
- [Daily Usage](#daily-usage)
- [Adding New Configs](#adding-new-configs)
- [Updating](#updating)
- [Oh My Posh Theme](#oh-my-posh-theme)
- [Troubleshooting](#troubleshooting)

## Installation

### Prerequisites

The following should be available (most are pre-installed on Ubuntu):

- `curl`
- `unzip`
- `git`
- `cargo` / `rustup` (installed automatically if missing when bat is needed)

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
source ~/.bashrc
```

## What the Bootstrap Installs

| Tool | Method | Notes |
|------|--------|-------|
| bat | `cargo install bat` | apt version is outdated, cargo gets latest |
| oh-my-posh | curl install script → `~/.local/bin/` | Not in apt repos |
| oh-my-posh themes | GitHub release zip → `~/.cache/oh-my-posh/themes/` | Bundled theme collection |
| JetBrains Mono Nerd Font | GitHub release → `~/.local/share/fonts/` | Required for prompt icons |

If `cargo` is not found, the bootstrap installs `rustup` first.

## Shell: bash

The `.bashrc` includes:

- Oh My Posh with Catppuccin Mocha theme
- Aliases (`ls --color`, `cat`→bat, `ll`, `la`, `l`)
- Color support via `dircolors`
- PATH setup for `~/.local/bin`, cargo, nvm, bun
- Bash completion
- Smart `code()` function (detects Cursor vs VS Code)
- Sources `~/.bash_aliases` if it exists (not managed by chezmoi)

## Font Installation

Fonts are installed to `~/.local/share/fonts/` and registered via `fc-cache -fv`.

### Setting the font in terminal emulators

#### GNOME Terminal

Right-click → Preferences → Profile → Custom font → "JetBrainsMono Nerd Font"

#### Alacritty

Add to `~/.config/alacritty/alacritty.toml`:

```toml
[font.normal]
family = "JetBrainsMono Nerd Font"
```

#### Kitty

Add to `~/.config/kitty/kitty.conf`:

```ini
font_family JetBrainsMono Nerd Font
```

## Daily Usage

### Pull and apply latest changes

```bash
chezmoi update -v
```

### Edit a config

```bash
chezmoi edit ~/.bashrc     # opens source template in $EDITOR
chezmoi diff               # preview the change
chezmoi apply              # deploy it
source ~/.bashrc           # reload in current shell
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

### Add a Linux-only file

1. Add the file: `chezmoi add ~/.linux-specific-config`
2. Edit `.chezmoiignore` to exclude it on other platforms:

```text
{{ if ne .chezmoi.os "linux" }}
.linux-specific-config
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

The full theme collection is also downloaded to `~/.cache/oh-my-posh/themes/` for reference.

To customize:

```bash
chezmoi edit ~/.config/oh-my-posh/catppuccin_mocha.omp.json
chezmoi apply
source ~/.bashrc
```

## Troubleshooting

### `cargo: command not found`

Install rustup:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

### Font glyphs not rendering

Rebuild the font cache:

```bash
fc-cache -fv
```

Then restart your terminal.

### `oh-my-posh: command not found`

Ensure `~/.local/bin` is in your PATH:

```bash
echo $PATH | tr ':' '\n' | grep local
```

### `chezmoi: command not found`

Ensure `~/.local/bin` is in PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```
