# WSL + Windows Integration

## How It Works

WSL runs Linux inside Windows. This dotfiles setup manages **both sides**:

1. **Linux side** (`run_once_before_install-packages-linux.sh.tmpl`): Installs bat, oh-my-posh, fonts for the Linux environment
2. **Windows side** (`run_once_before_install-packages-windows.sh.tmpl`): Writes Windows Terminal settings, PowerShell profile, installs oh-my-posh.exe and fonts for the Windows environment

Both scripts run automatically when WSL is detected (via `$WSL_DISTRO_NAME`).

## Dual Oh My Posh Installs

- **Linux**: `oh-my-posh` binary at `~/.local/bin/oh-my-posh` — used by bash in WSL
- **Windows**: `oh-my-posh.exe` at `%LOCALAPPDATA%\Programs\oh-my-posh\bin\` — used by PowerShell

Both use the same Catppuccin Mocha theme, but from different paths:
- Linux: `~/.config/oh-my-posh/catppuccin_mocha.omp.json`
- Windows: `%LOCALAPPDATA%\Programs\oh-my-posh\themes\catppuccin_mocha.omp.json`

## Windows Username Detection

The bootstrap detects the Windows username via:
```bash
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
```

This is used to resolve paths like `/mnt/c/Users/$WIN_USER/AppData/...`.

## What Gets Written to Windows

| File | Windows Path | Purpose |
|------|-------------|---------|
| Windows Terminal settings | `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_...\LocalState\settings.json` | Theme, keybindings, profiles |
| PowerShell profile | `%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` | Oh My Posh init |
| oh-my-posh.exe | `%LOCALAPPDATA%\Programs\oh-my-posh\bin\` | Prompt engine for PowerShell |
| oh-my-posh themes | `%LOCALAPPDATA%\Programs\oh-my-posh\themes\` | Theme files |
| Nerd Font files | `%LOCALAPPDATA%\Microsoft\Windows\Fonts\` | User-installed fonts |

## Starting Directory

WSL profiles in Windows Terminal are configured to start in:
```
//wsl.localhost/Ubuntu-22.04/home/sabossedgh/repos
```

The PowerShell profile also sets its location to this UNC path so all terminals open in the same working area.

## Path Translation

Windows Terminal is configured with `pathTranslationStyle: "wsl"` which translates Windows paths to WSL paths when dragging files into the terminal.

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
