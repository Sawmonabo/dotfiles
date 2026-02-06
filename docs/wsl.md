# WSL + Windows Integration

## Table of Contents

- [Installation](#installation)
- [How It Works](#how-it-works)
- [Dual Oh My Posh Installs](#dual-oh-my-posh-installs)
- [What Gets Written to Windows](#what-gets-written-to-windows)
- [Daily Usage](#daily-usage)
- [Adding New Configs](#adding-new-configs)
- [Updating](#updating)
- [Starting Directory](#starting-directory)
- [Path Translation](#path-translation)
- [Windows Username Detection](#windows-username-detection)
- [Troubleshooting](#troubleshooting)

## Installation

WSL installation uses the same commands as Linux — the bootstrap automatically detects WSL and configures both sides.

### Fresh install (one command)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" && chezmoi init --apply Sawmonabo/dotfiles
```

This runs **three** bootstrap scripts on WSL:

1. `install-packages-linux.sh` — bat, oh-my-posh, fonts for Linux
2. `install-packages-windows.sh` — oh-my-posh.exe, fonts, Windows Terminal settings, PowerShell profile

### Step-by-step install

```bash
# 1. Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin

# 2. Init (prompts for name, email, editor — does NOT modify files yet)
chezmoi init Sawmonabo/dotfiles

# 3. Preview what will change (including Windows-side scripts)
chezmoi diff

# 4. Apply
chezmoi apply -v
```

### Verify

```bash
# Linux side
chezmoi verify && echo "All good"
source ~/.bashrc

# Windows side — restart Windows Terminal to see changes
```

## How It Works

WSL runs Linux inside Windows. This dotfiles setup manages **both sides**:

1. **Linux side** (`run_once_before_install-packages-linux.sh.tmpl`): Installs bat, oh-my-posh, fonts for the Linux environment
2. **Windows side** (`run_once_before_install-packages-windows.sh.tmpl`): Writes Windows Terminal settings, PowerShell profile, installs oh-my-posh.exe and fonts for the Windows environment

Both scripts run automatically when WSL is detected (via `$WSL_DISTRO_NAME`).

## Dual Oh My Posh Installs

- **Linux**: `oh-my-posh` binary at `~/.local/bin/oh-my-posh` — used by bash in WSL
- **Windows**: `oh-my-posh.exe` at `%LOCALAPPDATA%\Programs\oh-my-posh\bin\` — used by PowerShell

Both use the same Catppuccin Mocha theme, but from different paths:

| Side | Theme Path |
|------|-----------|
| Linux | `~/.config/oh-my-posh/catppuccin_mocha.omp.json` |
| Windows | `%LOCALAPPDATA%\Programs\oh-my-posh\themes\catppuccin_mocha.omp.json` |

## What Gets Written to Windows

| File | Windows Path | Purpose |
|------|-------------|---------|
| Windows Terminal settings | `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_...\LocalState\settings.json` | Theme, keybindings, profiles |
| PowerShell profile | `%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` | Oh My Posh init |
| oh-my-posh.exe | `%LOCALAPPDATA%\Programs\oh-my-posh\bin\` | Prompt engine for PowerShell |
| oh-my-posh themes | `%LOCALAPPDATA%\Programs\oh-my-posh\themes\` | Theme files |
| Nerd Font files | `%LOCALAPPDATA%\Microsoft\Windows\Fonts\` | User-installed fonts |

## Daily Usage

### Pull and apply latest changes

```bash
chezmoi update -v
```

This updates both Linux configs and re-runs any changed Windows-side scripts.

### Edit a Linux config

```bash
chezmoi edit ~/.bashrc     # opens source template in $EDITOR
chezmoi diff               # preview the change
chezmoi apply              # deploy it
source ~/.bashrc           # reload in current shell
```

### Edit Windows Terminal settings

The Windows Terminal settings are embedded in the bootstrap script. To modify:

1. Edit the source: `chezmoi cd` then edit `run_once_before_install-packages-windows.sh.tmpl`
1. Force the script to re-run:

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

1. Restart Windows Terminal

### Check for drift

```bash
chezmoi verify             # exit code 0 = everything matches
chezmoi diff               # see what differs
```

## Adding New Configs

### Add a WSL-specific file

Use chezmoi template conditionals to detect WSL:

```text
{{ if and (eq .chezmoi.os "linux") (env "WSL_DISTRO_NAME") }}
# WSL-specific content
{{ end }}
```

### Add a Linux config

```bash
chezmoi add ~/.some-config
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

### Re-run bootstrap scripts

Bootstrap scripts use `run_once_before_` prefix — they only run once. To force a re-run (e.g., after modifying the Windows Terminal settings in the script):

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

### Re-run setup prompts

```bash
chezmoi init               # re-prompts for name, email, editor
```

## Starting Directory

WSL profiles in Windows Terminal are configured to start in:

```text
//wsl.localhost/Ubuntu-22.04/home/sabossedgh/repos
```

The PowerShell profile also sets its location to this UNC path so all terminals open in the same working area.

## Path Translation

Windows Terminal is configured with `pathTranslationStyle: "wsl"` which translates Windows paths to WSL paths when dragging files into the terminal.

## Windows Username Detection

The bootstrap detects the Windows username via:

```bash
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
```

This is used to resolve paths like `/mnt/c/Users/$WIN_USER/AppData/...`.

## Troubleshooting

### Font not found after install

Fonts are installed to the **user** font directory (not system). You must restart Windows Terminal for the font registry to take effect. If still not working, check:

```powershell
Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" | Select-String "JetBrains"
```

### Windows Terminal settings not updating

The settings file path depends on how Windows Terminal was installed:

- **Microsoft Store** (default): `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\`
- **Scoop/Manual**: Different path — check your installation

### PowerShell profile not loading

Check the profile path:

```powershell
echo $PROFILE
```

It should point to `Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`. If PowerShell Core (pwsh.exe) is used, the path is `Documents\PowerShell\`.

### oh-my-posh.exe not found in PowerShell

Add the install path to Windows PATH:

1. Search "environment variables" in Windows
2. Add `%LOCALAPPDATA%\Programs\oh-my-posh\bin` to user PATH
3. Restart terminal

### Bootstrap script didn't run

If the Windows-side script didn't execute, verify WSL is detected:

```bash
echo $WSL_DISTRO_NAME
```

If empty, you're not running in WSL — the Windows bootstrap only runs when this variable is set.
