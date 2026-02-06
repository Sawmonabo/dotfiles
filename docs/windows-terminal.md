# Windows Terminal Configuration

## Table of Contents

- [Color Scheme: Catppuccin Mocha](#color-scheme-catppuccin-mocha)
- [Keybindings](#keybindings)
- [Profile Tab Colors](#profile-tab-colors)
- [Default Profile Settings](#default-profile-settings)
- [Experimental Features](#experimental-features)
- [Customizing](#customizing)
- [PowerShell Profile](#powershell-profile)

## Color Scheme: Catppuccin Mocha

| Color | Hex |
|-------|-----|
| Background | `#1E1E2E` |
| Foreground | `#CDD6F4` |
| Cursor | `#F5E0DC` |
| Selection | `#585B70` |
| Black | `#45475A` |
| Red | `#F38BA8` |
| Green | `#A6E3A1` |
| Yellow | `#F9E2AF` |
| Blue | `#89B4FA` |
| Purple | `#F5C2E7` |
| Cyan | `#94E2D5` |
| White | `#BAC2DE` |

Bright variants use the same hues. See the [Catppuccin palette](https://github.com/catppuccin/catppuccin) for details.

## Keybindings

### Clipboard

| Action | Shortcut |
|--------|----------|
| Copy | `Ctrl+C` |
| Paste | `Ctrl+V` |

### Tabs

| Action | Shortcut |
|--------|----------|
| New tab | `Ctrl+Shift+T` |
| Switch to tab 1-9 | `Ctrl+Alt+1` through `Ctrl+Alt+9` |

### Panes

| Action | Shortcut |
|--------|----------|
| Split down | `Ctrl+Shift+D` |
| Split right | `Ctrl+Shift+E` |
| Close pane | `Ctrl+Shift+W` |
| Focus up | `Ctrl+Shift+K` |
| Focus down | `Ctrl+Shift+J` |
| Focus left | `Ctrl+Shift+H` |
| Focus right | `Ctrl+Shift+L` |
| Zoom pane | `Ctrl+Shift+Z` |
| Resize left | `Ctrl+Shift+Left` |
| Resize right | `Ctrl+Shift+Right` |
| Resize up | `Ctrl+Shift+Up` |
| Resize down | `Ctrl+Shift+Down` |

### Navigation

| Action | Shortcut |
|--------|----------|
| Scroll to previous mark | `Ctrl+Alt+Up` |
| Scroll to next mark | `Ctrl+Alt+Down` |
| Toggle fullscreen | `Alt+Enter` |

## Profile Tab Colors

| Profile | Color | Hex |
|---------|-------|-----|
| Ubuntu (WSL) | Peach | `#FAB387` |
| PowerShell | Lavender | `#B4BEFE` |
| Command Prompt | Overlay0 | `#6C7086` |
| Azure Cloud Shell | Sapphire | `#74C7EC` |

All colors are from the Catppuccin Mocha palette.

## Default Profile Settings

| Setting | Value |
|---------|-------|
| Color scheme | Catppuccin Mocha |
| Font | JetBrainsMono Nerd Font, 12pt, medium weight |
| Font ligatures | Enabled (`calt`, `liga`) |
| Anti-aliasing | ClearType |
| Padding | 8px |
| Scrollbar | Hidden |
| Opacity | 100% |
| Intense text | Bold |
| Auto-mark prompts | Enabled |
| Show marks on scrollbar | Enabled |
| Cursor reposition with mouse | Enabled (experimental) |
| Path translation | WSL style |

## Experimental Features

- **`repositionCursorWithMouse`**: Click to reposition cursor in supported applications
- **`autoMarkPrompts`**: Automatically mark prompt boundaries for Ctrl+Alt+Up/Down navigation
- **`showMarksOnScrollbar`**: Visual indicators on the scrollbar for marked positions

## Customizing

### Modifying settings

The Windows Terminal `settings.json` is embedded in the WSL bootstrap script. To change it:

1. Open the chezmoi source directory: `chezmoi cd`
1. Edit `run_once_before_install-packages-windows.sh.tmpl` — find the `WTSETTINGS` heredoc
1. Force re-run and apply:

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

1. Restart Windows Terminal

### Adding a new profile

Add to the `profiles.list` array inside the `WTSETTINGS` heredoc:

```json
{
    "guid": "{generate-a-new-guid}",
    "name": "My Profile",
    "commandline": "/path/to/shell",
    "tabColor": "#F38BA8",
    "hidden": false
}
```

Generate a GUID in PowerShell: `[guid]::NewGuid().ToString()`

### Adding a keybinding

Add to the `keybindings` array:

```json
{ "id": "Terminal.SomeAction", "keys": "ctrl+shift+x" }
```

For custom actions, also add an entry to the `actions` array.

## PowerShell Profile

The PowerShell profile at `Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` runs Oh My Posh with the same Catppuccin Mocha theme:

```powershell
& "$env:LOCALAPPDATA\Programs\oh-my-posh\bin\oh-my-posh.exe" init pwsh --config "$env:LOCALAPPDATA\Programs\oh-my-posh\themes\catppuccin_mocha.omp.json" | Invoke-Expression
```

To modify the PowerShell profile, edit the `PSPROFILE` heredoc in `run_once_before_install-packages-windows.sh.tmpl`.
