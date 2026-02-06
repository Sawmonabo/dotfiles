# Dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/). Supports macOS (zsh), Linux/Ubuntu (bash), and WSL (bash + Windows integration).

## Architecture

chezmoi templates in this repo deploy to `~/` on each platform. The naming convention is chezmoi's: `dot_bashrc.tmpl` deploys as `~/.bashrc`, `run_once_before_*` scripts execute once before file deployment.

### Key files

| Source file | Deploys to | Notes |
|---|---|---|
| `.chezmoi.toml.tmpl` | `~/.config/chezmoi/chezmoi.toml` | Interactive prompts for name, emails, editor |
| `dot_bashrc.tmpl` | `~/.bashrc` | Linux/WSL only (ignored on macOS) |
| `dot_zshrc.tmpl` | `~/.zshrc` | macOS only (ignored on Linux) |
| `dot_gitconfig.tmpl` | `~/.gitconfig` | All platforms; uses `includeIf` for personal email |
| `dot_gitconfig-personal.tmpl` | `~/.gitconfig-personal` | Personal email for `~/dev/` repos |
| `dot_config/oh-my-posh/` | `~/.config/oh-my-posh/` | Catppuccin Mocha theme (all platforms) |
| `run_once_before_install-packages-*.sh.tmpl` | (run scripts) | Platform bootstrap: installs bat, oh-my-posh, Nerd Font, gh |

### Template variables

Defined in `.chezmoi.toml.tmpl` via `promptStringOnce`:
- `.name` — Git user name
- `.email` — Work email (global default)
- `.personal_email` — Personal email (for `~/dev/` repos)
- `.editor` — Preferred editor (`cursor`/`code`/`vim`)

### Platform gating

- `.chezmoiignore` conditionally excludes files per OS (`ne .chezmoi.os "linux"`, etc.)
- `run_once_before_` scripts use chezmoi template guards for OS detection

## Conventions

- **Template syntax**: Go templates with chezmoi data (e.g., `{{ .name }}`, `{{ .chezmoi.os }}`)
- **File naming**: Follow chezmoi conventions (`dot_`, `.tmpl`, `run_once_before_`)
- **Platform scripts**: One `run_once_before_install-packages-{platform}.sh.tmpl` per platform
- **Local overrides**: `~/.bash_aliases` is sourced by `.bashrc` but not managed by chezmoi

## Development workflow

```bash
# Preview changes before applying
chezmoi diff

# Apply changes
chezmoi apply -v

# Edit a managed file
chezmoi edit ~/.bashrc
chezmoi apply
```

## Testing changes

Always run `chezmoi diff` before `chezmoi apply` to preview what will change. Be cautious with `run_once_before_` scripts — they execute once per machine and install system packages.
