# Linux Setup

## Prerequisites

The following should be available (most are pre-installed on Ubuntu):
- `curl`
- `unzip`
- `git`
- `cargo` / `rustup` (installed automatically if missing when bat is needed)

## What the Bootstrap Installs

| Tool | Method | Notes |
|------|--------|-------|
| bat | `cargo install bat` | apt version is outdated, cargo gets latest |
| oh-my-posh | curl install script → `~/.local/bin/` | Not in apt repos |
| oh-my-posh themes | GitHub release zip → `~/.cache/oh-my-posh/themes/` | Bundled theme collection |
| JetBrains Mono Nerd Font | GitHub release → `~/.local/share/fonts/` | Required for prompt icons |

If `cargo` is not found, the bootstrap installs `rustup` first.

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
```
font_family JetBrainsMono Nerd Font
```

## Oh My Posh Theme

The Catppuccin Mocha theme is deployed to `~/.config/oh-my-posh/catppuccin_mocha.omp.json`.

The full theme collection is also downloaded to `~/.cache/oh-my-posh/themes/` for reference.

To switch themes:
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
