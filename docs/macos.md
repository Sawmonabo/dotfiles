# macOS Setup

## Prerequisites

- **Xcode CLI Tools**: `xcode-select --install`
- Homebrew is installed automatically by the bootstrap if missing

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
```
font-family = JetBrainsMono Nerd Font
```

### Alacritty
Add to `~/.config/alacritty/alacritty.toml`:
```toml
[font.normal]
family = "JetBrainsMono Nerd Font"
```

## Oh My Posh Theme

The Catppuccin Mocha theme is deployed to `~/.config/oh-my-posh/catppuccin_mocha.omp.json`.

To customize, edit the source:
```bash
chezmoi edit ~/.config/oh-my-posh/catppuccin_mocha.omp.json
chezmoi apply
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
Ensure Homebrew's bin is in PATH. Check with:
```bash
which oh-my-posh
brew --prefix
```
