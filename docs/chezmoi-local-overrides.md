# Chezmoi: Managing Local Configuration Overrides

Research findings on how chezmoi handles machine-specific configurations,
existing file conflicts, and safe first-time application workflows.

## Table of Contents

- [1. .gitconfig Email Per-Context](#1-gitconfig-email-per-context)
- [2. Existing File Conflicts](#2-existing-file-conflicts)
- [3. Machine-Specific Overrides](#3-machine-specific-overrides)
- [4. Safe Apply Workflow (First-Time on Existing Machine)](#4-safe-apply-workflow-first-time-on-existing-machine)
- [Summary: Decision Matrix](#summary-decision-matrix)

---

## 1. `.gitconfig` Email Per-Context

### The Problem

You want a single chezmoi-managed `.gitconfig` that uses your personal email by
default but automatically switches to a work email for repositories under your
work directory (e.g., `~/work/`).

### Approach A: Git's `includeIf` Directive (Recommended)

Git natively supports conditional includes based on the repository directory.
This is the cleanest solution because it works at the Git level, independent of
chezmoi.

**How it works:** Git's `[includeIf "gitdir:..."]` directive loads additional
config files based on which directory a repository is in. The condition is
evaluated at runtime by Git itself.

**chezmoi-managed `dot_gitconfig.tmpl`:**

```ini
[user]
    name = {{ .name | quote }}
    email = {{ .email | quote }}

[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work

[includeIf "gitdir:~/personal/"]
    path = ~/.gitconfig-personal
```

**chezmoi-managed `dot_gitconfig-work`:**

```ini
[user]
    email = sam@company.com
    signingKey = WORK_GPG_KEY_ID
```

**chezmoi-managed `dot_gitconfig-personal`:**

```ini
[user]
    email = sam@personal.com
```

**Important rules for `includeIf`:**
- The `gitdir:` path MUST end with a trailing `/` to match all subdirectories
- On Windows, use forward slashes (not backslashes)
- Place `includeIf` blocks at the END of `.gitconfig` so they override earlier
  settings
- `gitdir:~/work/` automatically becomes `gitdir:~/work/**` (recursive match)

**Sources:**
- [Git Conditional Includes](https://www.edwardthomson.com/blog/git_conditional_includes)
- [Using includeIf to manage git identities](https://medium.com/@mrjink/using-includeif-to-manage-your-git-identities-bcc99447b04b)
- [Managing Multiple Git Identities with Conditional Includes](https://kothar.net/blog/2025/directory-targeted-git-config)

### Approach B: chezmoi Template Conditionals

Use chezmoi's template system to generate different `.gitconfig` content based
on the hostname, a custom variable, or OS.

**`.chezmoi.toml.tmpl` (in source state root):**

```toml
{{- $email := promptStringOnce . "email" "Git email address" -}}
{{- $name := promptStringOnce . "name" "Git user name" -}}
{{- $isWork := promptBoolOnce . "isWork" "Is this a work machine" -}}

[data]
    email = {{ $email | quote }}
    name = {{ $name | quote }}
    isWork = {{ $isWork }}
```

**`dot_gitconfig.tmpl`:**

```ini
[user]
{{- if .isWork }}
    email = "sam@company.com"
{{- else }}
    email = {{ .email | quote }}
{{- end }}
    name = {{ .name | quote }}
```

**Hostname-based alternative (no prompts):**

```ini
[user]
{{- if eq .chezmoi.hostname "work-laptop" }}
    email = "sam@company.com"
{{- else }}
    email = "sam@personal.com"
{{- end }}
    name = "Sam Bossedgh"
```

**Sources:**
- [chezmoi Manage Machine-to-Machine Differences](https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/)
- [Managing machine-specific gitconfig with chezmoi (JP, Medium)](https://jpcaparas.medium.com/dotfiles-managing-machine-specific-gitconfig-with-chezmoi-user-defined-template-variables-400071f663c0)
- [chezmoi Templating Guide](https://www.chezmoi.io/user-guide/templating/)

### Approach C: Hybrid (Best of Both)

The best real-world approach combines both: use chezmoi templates to set the
default email per-machine, AND include `includeIf` for directory-based overrides
within the same machine.

**`dot_gitconfig.tmpl`:**

```ini
[user]
    name = {{ .name | quote }}
    email = {{ .email | quote }}

# Directory-based overrides (works on any machine)
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work

[includeIf "gitdir:~/personal/"]
    path = ~/.gitconfig-personal

[core]
    editor = nvim
    autocrlf = input
```

This way:
- chezmoi sets the default email based on machine context
- Git's `includeIf` handles repo-by-directory overrides on ANY machine
- You can have work repos on your personal machine and they still get the
  correct email

### Should chezmoi Manage `.gitconfig` at All?

**Yes, but with nuance:**

| Aspect | Recommendation |
|--------|---------------|
| Core settings (aliases, core, diff, merge) | Manage with chezmoi |
| User identity (name, email) | Manage with chezmoi templates + `includeIf` |
| Machine-specific paths (credential helpers) | Use chezmoi OS/hostname conditionals |
| Signing keys | Use chezmoi templates with per-machine data |
| Secrets/tokens | NEVER commit; use 1Password/Bitwarden template functions |

**Source:**
- [abrauner/dotfiles - work/personal separation with chezmoi](https://github.com/abrauner/dotfiles)

---

## 2. Existing File Conflicts

### How chezmoi Handles Overwrites

chezmoi tracks the desired state in its source directory and computes a diff
against your actual files. When you run `chezmoi apply`:

1. If the target file matches the desired state, nothing happens
2. If the target file differs from the desired state, chezmoi checks whether
   it has changed since chezmoi last wrote it
3. If it has changed (external modification), **chezmoi prompts interactively**
   with options: `[diff,overwrite,all-overwrite,skip,quit]`

### The Diff-First Workflow

**Always preview before applying:**

```bash
# See what would change (dry run + verbose)
chezmoi diff

# Or equivalently
chezmoi apply --dry-run --verbose

# Apply only after reviewing
chezmoi apply -v
```

The `-n` (dry run) flag prevents actual changes; `-v` (verbose) prints exactly
what would happen. Combining them (`-nv`) is the safest way to preview.

**Sources:**
- [chezmoi Command Overview](https://www.chezmoi.io/user-guide/command-overview/)
- [chezmoi apply reference](https://www.chezmoi.io/reference/commands/apply/)
- [chezmoi Diff tool](https://www.chezmoi.io/user-guide/tools/diff/)

### Three-Way Merge with `chezmoi merge`

When files conflict, `chezmoi merge` opens a three-way merge tool with:

| Variable | Meaning |
|----------|---------|
| `.Destination` | The file as it currently exists on disk |
| `.Source` | The file as chezmoi's source state defines it |
| `.Target` | The desired target state (source after template execution) |

**Configure your merge tool in `chezmoi.toml`:**

```toml
[merge]
    command = "nvim"
    args = ["-d", "{{ .Destination }}", "{{ .Source }}", "{{ .Target }}"]
```

**For VSCode:**

```toml
[merge]
    command = "code"
    args = ["--wait", "--merge", "{{ .Destination }}", "{{ .Source }}", "{{ .Target }}", "{{ .Destination }}"]
```

**Source:**
- [chezmoi Merge documentation](https://www.chezmoi.io/user-guide/tools/merge/)

### Partial File Management

chezmoi manages whole files by default. For managing only parts of a file, there
are three approaches:

#### Option 1: `modify_` Scripts

Create a file prefixed with `modify_` in the source directory. It receives the
current file contents on stdin and writes the modified version to stdout.

**Example: `modify_dot_bashrc` (bash script):**

```bash
#!/bin/bash

# Read current file into a temp file
tmpfile=$(mktemp)
trap "rm -f ${tmpfile}" EXIT
cat > "${tmpfile}"

# Output the original content
cat "${tmpfile}"

# Add managed section if not present
if ! grep -q "# MANAGED BY CHEZMOI" "${tmpfile}"; then
    echo ""
    echo "# MANAGED BY CHEZMOI - START"
    echo "export EDITOR=nvim"
    echo "export PATH=\$HOME/.local/bin:\$PATH"
    echo "# MANAGED BY CHEZMOI - END"
fi
```

#### Option 2: Modify Templates (`chezmoi:modify-template`)

For structured data manipulation without a separate script. The file must NOT
have a `.tmpl` extension.

**Example: `modify_dot_config/settings.json`:**

```text
{{- /* chezmoi:modify-template */ -}}
{{- $config := .chezmoi.stdin | fromJson -}}
{{- $_ := set $config "editor.fontSize" 14 -}}
{{- $_ := set $config "terminal.integrated.shell.linux" "/bin/zsh" -}}
{{- $config | toPrettyJson }}
```

**For INI-style files, use `setValueAtPath`:**

```text
{{- /* chezmoi:modify-template */ -}}
{{- .chezmoi.stdin | replaceAllRegex "old-value" "new-value" }}
```

#### Option 3: chezmoi_modify_manager (Third-Party)

For complex INI files (like KDE settings) that mix managed settings with
application state, [chezmoi_modify_manager](https://vorpalblade.github.io/chezmoi_modify_manager/)
provides fine-grained control over which sections/keys to manage.

**Sources:**
- [chezmoi Manage Different Types of File](https://www.chezmoi.io/user-guide/manage-different-types-of-file/)
- [Full examples of modifying part of a file (GitHub Discussion #3996)](https://github.com/twpayne/chezmoi/discussions/3996)
- [Examples of modifying part of a file (GitHub Discussion #1746)](https://github.com/twpayne/chezmoi/discussions/1746)
- [chezmoi_modify_manager](https://vorpalblade.github.io/chezmoi_modify_manager/)

---

## 3. Machine-Specific Overrides

### Built-in Template Variables

chezmoi provides extensive built-in variables for conditional logic:

| Variable | Type | Example Value |
|----------|------|---------------|
| `.chezmoi.hostname` | string | `work-laptop` |
| `.chezmoi.fqdnHostname` | string | `work-laptop.corp.com` |
| `.chezmoi.os` | string | `linux`, `darwin`, `windows` |
| `.chezmoi.arch` | string | `amd64`, `arm64` |
| `.chezmoi.username` | string | `sam` |
| `.chezmoi.osRelease.id` | string | `ubuntu`, `fedora` |
| `.chezmoi.osRelease.versionID` | string | `22.04` |
| `.chezmoi.kernel.osrelease` | string | `6.6.87-microsoft-WSL2` |

**OS-based conditional example:**

```text
{{- if eq .chezmoi.os "darwin" }}
# macOS-specific configuration
eval "$(/opt/homebrew/bin/brew shellenv)"
{{- else if eq .chezmoi.os "linux" }}
# Linux-specific configuration
export PATH="$HOME/.local/bin:$PATH"
{{- end }}
```

**Detecting WSL:**

```text
{{- if (and (eq .chezmoi.os "linux") (contains "microsoft" .chezmoi.kernel.osrelease)) }}
# WSL-specific configuration
export BROWSER=wslview
{{- end }}
```

**Source:**
- [chezmoi Template Variables](https://www.chezmoi.io/reference/templates/variables/)

### Custom Data Variables

Define custom variables in multiple ways:

**In `chezmoi.toml` (per-machine, not version-controlled):**

```toml
[data]
    email = "sam@personal.com"
    name = "Sam Bossedgh"
    isWork = false
    gpgKeyId = "ABC123"
```

**In `.chezmoidata.toml` (in source state, version-controlled):**

```toml
# Default values shared across all machines
editor = "nvim"
defaultShell = "zsh"
```

**In `.chezmoidata/$FORMAT` files (multiple files merged alphabetically):**

```text
.chezmoidata/
  defaults.toml      # loaded first (alphabetical)
  work-overrides.toml # loaded second, overrides defaults
```

**Interactive prompts during `chezmoi init`:**

```toml
# .chezmoi.toml.tmpl
{{- $email := promptStringOnce . "email" "Email address" -}}
{{- $isWork := promptBoolOnce . "isWork" "Is this a work machine" -}}

[data]
    email = {{ $email | quote }}
    isWork = {{ $isWork }}
```

The `promptStringOnce` / `promptBoolOnce` functions only ask on first run and
cache the answers in the local config file.

**Source:**
- [chezmoi Setup Guide](https://www.chezmoi.io/user-guide/setup/)
- [chezmoi.toml.tmpl reference](https://www.chezmoi.io/reference/special-files/chezmoi-format-tmpl/)

### `.chezmoiexternal` for External Dependencies

Pull in files or repos from external sources during `chezmoi apply`:

**`.chezmoiexternal.toml`:**

```toml
# Download a single file
[".local/bin/starship"]
    type = "file"
    url = "https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz"
    refreshPeriod = "168h"  # re-check weekly

# Clone a git repo
[".oh-my-zsh"]
    type = "git-repo"
    url = "https://github.com/ohmyzsh/ohmyzsh.git"
    refreshPeriod = "168h"
    [".oh-my-zsh".pull]
        args = ["--ff-only"]

# Extract an archive
[".local/share/fonts"]
    type = "archive"
    url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz"
    refreshPeriod = "720h"
```

**Performance warning:** Do not use externals for large files. chezmoi validates
exact contents on every `diff`/`apply`/`verify`. For large downloads, use a
`run_onchange_` script instead.

**Source:**
- [chezmoi Include Files from Elsewhere](https://www.chezmoi.io/user-guide/include-files-from-elsewhere/)
- [.chezmoiexternal reference](https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/)
- [Managing External Dependencies with Chezmoi (stoeps.de)](https://stoeps.de/posts/2025/managing_external_dependencies_with_chezmoi/)

### Local Unmanaged Files

For files that should never be managed by chezmoi (like machine-local
`.bash_aliases` or `.env` files):

1. **Don't add them** to chezmoi at all
1. **Source them conditionally** from a chezmoi-managed file:

```bash
# In dot_bashrc.tmpl (managed by chezmoi)
# Source local aliases if they exist (not managed by chezmoi)
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Source local environment overrides
if [ -f ~/.env.local ]; then
    . ~/.env.local
fi
```

1. **Add them to `.chezmoiignore`** if they exist in the home directory and
   chezmoi might try to manage them:

```text
# .chezmoiignore
.bash_aliases
.env.local
.config/local-only/
```

### The `modify_` Script Prefix

As described in Section 2, `modify_` scripts let you modify existing files
rather than replacing them entirely. This is particularly useful for:

- Files that other programs also modify (e.g., `.bashrc` appended to by
  installers)
- Config files where you only want to manage specific sections
- Files that contain both managed settings and application state

**Source:**
- [chezmoi Manage Different Types of File](https://www.chezmoi.io/user-guide/manage-different-types-of-file/)

---

## 4. Safe Apply Workflow (First-Time on Existing Machine)

### Recommended Step-by-Step Process

#### Step 1: Manual Backup (Before Anything Else)

chezmoi does NOT automatically back up files it overwrites. Create your own
backup first:

```bash
# Backup current dotfiles before touching anything
tar czf ~/dotfiles-backup-$(date +%Y%m%d).tar.gz \
    ~/.bashrc ~/.zshrc ~/.gitconfig ~/.config/ \
    ~/.ssh/config ~/.tmux.conf 2>/dev/null

# Or use a dedicated backup directory
mkdir -p ~/dotfiles-backup
for f in .bashrc .zshrc .gitconfig .tmux.conf .vimrc; do
    [ -f ~/$f ] && cp ~/$f ~/dotfiles-backup/$f.bak
done
```

#### Step 2: Initialize Without Applying

```bash
# Clone your dotfiles repo into chezmoi's source directory
# This does NOT modify any files in your home directory
chezmoi init https://github.com/youruser/dotfiles.git

# If using SSH
chezmoi init git@github.com:youruser/dotfiles.git
```

If your repo has a `.chezmoi.toml.tmpl`, chezmoi will prompt for values
(email, hostname flags, etc.) during init.

#### Step 3: Review the Full Diff

```bash
# See every change chezmoi would make
chezmoi diff

# For a more detailed view with file operations listed
chezmoi apply --dry-run --verbose
```

Review the output carefully. Look for:
- Files that would be overwritten with different content
- Files that would be created for the first time
- Symlinks that would be created or modified
- Scripts that would be executed

#### Step 4: Apply File by File (Conservative Approach)

```bash
# Apply individual files you're confident about
chezmoi apply ~/.gitconfig
chezmoi apply ~/.tmux.conf

# For files with conflicts, use merge
chezmoi merge ~/.bashrc
```

#### Step 5: Or Apply Everything (After Reviewing Diff)

```bash
# Apply all changes (chezmoi prompts for modified files)
chezmoi apply -v

# chezmoi will show: [diff,overwrite,all-overwrite,skip,quit]
# for any file that has changed since chezmoi last wrote it
```

#### Step 6: Verify

```bash
# Confirm everything matches desired state
chezmoi verify

# If any files don't match, this exits with a non-zero code
```

### Handling the Initial Transition

When transitioning from unmanaged dotfiles to chezmoi-managed ones:

**Strategy 1: Add Existing Files First**

If you're creating a new chezmoi repo from your current machine's dotfiles:

```bash
chezmoi init
chezmoi add ~/.bashrc
chezmoi add ~/.gitconfig
chezmoi add --template ~/.gitconfig  # adds as template
chezmoi cd  # enter source directory
git add -A && git commit -m "Initial dotfiles"
git remote add origin git@github.com:user/dotfiles.git
git push -u origin main
```

**Strategy 2: Clone Existing Repo to New Machine**

```bash
# 1. Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)"

# 2. Init from repo (does NOT apply)
chezmoi init https://github.com/user/dotfiles.git

# 3. Preview
chezmoi diff

# 4. Merge conflicts
chezmoi merge ~/.bashrc
chezmoi merge ~/.gitconfig

# 5. Apply
chezmoi apply -v
```

**Strategy 3: One-Shot for Fresh Machines**

For brand new machines with no existing config worth preserving:

```bash
# Install, init, and apply in one command
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply user

# For temporary environments (removes chezmoi afterward)
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --one-shot user
```

### Ongoing Safe Workflow

After initial setup, the daily workflow is:

```bash
# Pull latest changes from dotfiles repo
chezmoi git pull -- --autostash --rebase

# Preview what changed
chezmoi diff

# Apply if satisfied
chezmoi apply -v

# Or combine pull + diff in one step
chezmoi update --dry-run --verbose
```

**For auto-sync (optional):**

```toml
# chezmoi.toml
[git]
    autoCommit = true
    autoPush = true
```

**Sources:**
- [chezmoi Quick Start](https://www.chezmoi.io/quick-start/)
- [chezmoi Setup Guide](https://www.chezmoi.io/user-guide/setup/)
- [chezmoi Daily Operations](https://www.chezmoi.io/user-guide/daily-operations/)
- [chezmoi apply reference](https://www.chezmoi.io/reference/commands/apply/)
- [Why use chezmoi?](https://www.chezmoi.io/why-use-chezmoi/)

---

## Summary: Decision Matrix

| Scenario | Recommended Approach |
|----------|---------------------|
| Different email per repo directory | Git `includeIf` (managed by chezmoi template) |
| Different email per machine | chezmoi template with `promptStringOnce` or hostname conditional |
| OS-specific config blocks | chezmoi template with `.chezmoi.os` conditional |
| Entirely different file per OS | `include` function with OS-specific source files |
| Modify part of a file | `modify_` script or `chezmoi:modify-template` |
| File managed by another tool too | `modify_` script (append/ensure sections) |
| Complex INI with app state | `chezmoi_modify_manager` (third-party) |
| Machine-local files (never shared) | Don't add to chezmoi; source from managed files |
| External tools/fonts/plugins | `.chezmoiexternal.toml` |
| First-time apply on existing machine | `chezmoi init` then `chezmoi diff` then `chezmoi apply -v` |
| Sensitive values | 1Password/Bitwarden template functions, never plaintext |
