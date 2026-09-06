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

The install is split in two on purpose. The **before-phase** runs before a
single file is deployed, so anything that fails there blocks the whole apply; it
is therefore kept to what the rc files and the later scripts actually need, and
it is strict. The **after-phase** runs once the files are in place, so its
failures are reports rather than blocks, and the parts that routinely collide
with software you installed by hand live there and are best-effort.

`run_once_before_00-packages` (strict) installs Homebrew if it is missing
(detecting the Apple Silicon `/opt/homebrew` vs Intel `/usr/local` prefix, and
downloading the installer to a file before running it), writes a temporary
Brewfile of the `[packages.darwin].brew` formulae — plus `bitwarden-cli` on work
machines (`machine_role` work or both) — and runs `brew bundle install
--no-upgrade` on it: missing formulae are installed, anything already present is
left at the version it has. It then creates `~/.config/oh-my-posh` and clones
TPM into `~/.tmux/plugins/tpm`. The TPM clone is best-effort, because
`shared/40-tmux-plugins` already skips gracefully when TPM is absent.

Four scripts run after the files are deployed:

| Script | What it does |
|--------|--------------|
| `run_once_after_10-runtime-managers` | nvm and rustup via their upstream installers; uv, bun and Go come from Homebrew and are only verified here |
| `run_onchange_after_20-runtimes` | Node versions + default alias (nvm), Pythons (uv), Rust toolchain (rustup) |
| `run_onchange_after_30-global-tools` | codex, claude, corepack pnpm/yarn, uv tools, cargo tools, go tools; checks that the docker CLI is on PATH |
| `run_onchange_after_50-apps-and-extensions` | The `[packages.darwin].cask` GUI apps and the `vscode_extensions` set, in one `brew bundle install --no-upgrade` using its native `cask` and `vscode` entries. Best-effort: it warns and re-runs whenever `packages.toml` changes. `jasonn-porch.gitlab-mr` is added here only on work machines |

(`run_onchange_after_45-terminal-font` also runs, but it only prints Terminal.app
font instructions.)

Each of the runtime scripts puts Homebrew on PATH itself: a fresh Mac has no
Homebrew on PATH until `.zshrc` deploys, so the scripts source `brew shellenv`
rather than assume it.

See [packages.toml](../home/.chezmoidata/packages.toml) for the exact formula,
cask and extension set. Every list there is role-neutral; the work-only
`bitwarden-cli` and `jasonn-porch.gitlab-mr` entries are gated in the scripts.

### Which versions macOS actually pins

`versions.toml` governs Node (nvm), Python (uv), Rust (rustup) and the global
tools on macOS. It does **not** govern `uv`, `bun` or `go`: those come from
Homebrew at whatever version it ships, and `10-runtime-managers` only verifies
they are present. The `versions.go`, `versions.uv` and `versions.bun` pins apply
on Linux only.

A fresh Mac also ends up with chezmoi twice: once from `get.chezmoi.io` into
`~/.local/bin` (the install command above) and once as the `chezmoi` formula.
`~/.local/bin` comes first in the `.zshrc` PATH, so that copy wins. Either is
fine; there is nothing to clean up.

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

### A cask or extension did not install

Formulae are strict: if `run_once_before_00-packages` fails, the apply stops and
you fix the formula, then re-run `chezmoi apply`.

Casks and VS Code extensions are not. `run_onchange_after_50-apps-and-extensions`
runs after the files are deployed and prints:

```
    WARNING: one or more casks or extensions did not install (see above).
    An app already in /Applications at a different version cannot be adopted.
```

The usual cause is an app you installed by hand: `brew bundle` reports
`It seems there is already an App at /Applications/...`. Homebrew can adopt such
an app in place only when its version matches the cask exactly; otherwise you
have to replace it. **Quit the app first** — `--force` will overwrite a running
app, and Docker Desktop in particular should be quit before you do this.

```bash
brew install --cask --adopt <name>      # same version: adopt in place
brew install --cask --force <name>      # replace with the cask version
```

That is the install, so there is nothing to re-apply afterwards. To make the
script itself run again — after fixing something it warned about, say — either
edit `home/.chezmoidata/packages.toml` (its hash is baked into the script, so
any change re-runs it) or clear the recorded state:

```bash
chezmoi state delete-bucket --bucket=entryState
chezmoi apply -v
```

### chezmoi not found

Ensure `~/.local/bin` is in PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```
