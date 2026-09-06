# Machine Role (personal / work / both) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dotfiles deployable on a personal-only, work-only, or mixed machine without leaking employer configuration, and fix the template bugs that currently abort `chezmoi apply` on macOS.

**Architecture:** One new prompt, `machine_role`, is answered once per machine and stored in the local `chezmoi.toml`. The config template derives three booleans from it and the OS (`has_work`, `has_personal`, `is_wsl`) so every other template gates on a plain boolean instead of re-deriving platform facts. Work-only files are excluded through `.chezmoiignore`; mixed files (Codex config, git identity, shell rc) are templates with `{{ if .has_work }}` sections. Every hardcoded `/home/sabossedgh` becomes `{{ .chezmoi.homeDir }}`. A single `scripts/render-check.sh` renders the whole tree into a temp directory for one role and is what CI runs on both Linux and macOS.

**Tech Stack:** chezmoi v2.70+ (Go templates, sprig), bash, shellcheck, GitHub Actions.

**Spec:** This plan is derived from the audit in the conversation of 2026-09-03 (no separate spec file). Findings it resolves:

1. `home/dot_local/bin/executable_win-browser.tmpl` reads `.chezmoi.kernel.osrelease`, which is an empty map on macOS, so every `chezmoi apply`/`diff`/`status` aborts on a Mac.
2. `home/dot_codex/private_config.toml.tmpl` requires `jira_api_token` and `gitlab_token` unconditionally.
3. Codex `config.toml`, `AGENTS.md`, `hooks.json` and `.bashrc` embed work-only servers, CodeRabbit, and `/home/sabossedgh/...` paths.
4. Codex trusts twenty-plus individual repositories instead of the `~/dev` and `~/repos` roots.
5. `home/.chezmoiscripts/linux/run_onchange_after_40-tmux-plugins.sh.tmpl` has no OS guard and runs on macOS.
6. Both rc files duplicate the Bitwarden wrapper. `.zshrc` defines `claude` as a function while `.bashrc` carries it inside an agent-brain installer block; the user wants one plain alias everywhere and no agent-brain tooling.
7. `versions_mode` has no default. The Mac's local config still says `editor = "cursor"`, but the user now uses VS Code only, so `code` must always be plain VS Code (no Cursor routing anywhere).
8. CI renders only on Linux, so macOS template failures are invisible.
9. The Claude Code status line must be the one in this repo (`home/dot_claude/scripts/executable_statusline.py`), not the `statusline-command.sh` the Mac currently reaches through a `~/.claude/scripts` symlink into `~/dev/ai-sidekicks`.

## Global Constraints

- chezmoi source root stays `home/` (`.chezmoiroot`); nothing outside `home/` is deployable.
- Script naming stays `run_{once|onchange}_{before|after}_NN-<verb-noun>.sh.tmpl`, grouped by platform directory. A new `shared/` directory holds scripts that run on every platform.
- Secrets never enter the repo. Tokens live only in the local `chezmoi.toml`. Placeholder values in CI and tests are `ci-placeholder`.
- No hardcoded home directory anywhere under `home/`. Use `{{ .chezmoi.homeDir }}` or `$HOME`.
- VS Code is the only editor. No Cursor references, no `code()` wrapper, no IDE-detection logic anywhere under `home/`. `editor` choices are exactly `code` and `vim`.
- No agent-brain tooling (no `>>> agent-brain >>>` markers, no `ab-claude` references). The `claude` wrapper is exactly `claude() { command claude --verbose --allow-dangerously-skip-permissions "$@"; }` in both rc files. A function, not an alias: verified on 2026-09-03 that both pass extra arguments and quoting identically, but the function also works where alias expansion is off (bash non-interactive shells, `setopt no_aliases`) and inside other functions.
- Data keys available to every template after Task 1: `machine_role` (string), `has_work` (bool), `has_personal` (bool), `is_wsl` (bool), `name`, `email`, `editor`, `versions_mode`. Only when `machine_role == "both"`: `personal_email`, `work_email`. Only when `has_work`: `jira_api_token`, `gitlab_token`.
- Commit after every task with a message in the repo style `<area>: <what changed>`. Work on branch `feat/machine-role` off `main`.
- **Never run `chezmoi apply` against the real home directory during Tasks 1 to 9.** All verification goes through `scripts/render-check.sh`, which uses a temp config and temp destination. Task 10 is the only task that touches `~`, and it stops for user approval before applying.

---

### Task 0: Branch

**Files:** none

- [ ] **Step 1: Create the branch**

```bash
cd ~/dev/dotfiles
git switch -c feat/machine-role main
```

Expected: `Switched to a new branch 'feat/machine-role'`

---

### Task 1: Render-check harness

Everything after this task is verified with this script, so it comes first. It intentionally fails today (the Mac render bug) and turns green as later tasks land.

**Files:**
- Create: `scripts/scratch-init.sh`
- Create: `scripts/render-check.sh`

**Interfaces:**
- Produces: `scripts/scratch-init.sh <personal|work|both> <pinned|latest>` prints the path of a freshly generated throwaway `chezmoi.toml` with every prompt answered. Later tasks use it for their verification steps.
- Produces: `scripts/render-check.sh <personal|work|both> <pinned|latest>`; exit 0 on success, non-zero with `RENDER FAIL` / `SYNTAX FAIL` / `SHELLCHECK FAIL` / `LEAK` / `STATUSLINE FAIL` lines on failure. Renders into a temp directory and never touches `~`.

**Important chezmoi behaviour:** `--promptChoice`, `--promptString`, and `--promptInt` are keyed on the prompt *text* shown to the user, not on the data field name. `--promptChoice "Machine role=personal"` works; `--promptChoice "machine_role=personal"` is ignored and chezmoi tries to open a TTY. The values are parsed as comma-separated `key=value` pairs, so no prompt text may contain a comma. Task 2 keeps every prompt text comma-free and `scratch-init.sh` must match those strings exactly.

- [ ] **Step 1: Write `scripts/scratch-init.sh`**

```bash
#!/usr/bin/env bash
# Generate a throwaway chezmoi config for one (machine_role, versions_mode)
# pair with every prompt answered non-interactively, and print its path.
# Never touches ~/.config/chezmoi.
#
# chezmoi keys --prompt* flags on the prompt TEXT shown to the user, not on the
# data field name, so the strings below must match home/.chezmoi.toml.tmpl
# exactly. The WSL sizing prompts embed host numbers and only appear on a WSL
# host, where a TTY is available, so they are not answered here.
set -euo pipefail

role=${1:?usage: scratch-init.sh <personal|work|both> <pinned|latest>}
mode=${2:?usage: scratch-init.sh <personal|work|both> <pinned|latest>}
repo=$(cd "$(dirname "$0")/.." && pwd)
config="$(mktemp -d)/chezmoi.toml"

chezmoi --config "$config" --source "$repo" init \
    --promptChoice "Machine role=$role" \
    --promptChoice "Preferred editor=code" \
    --promptChoice "Install pinned or latest tool versions=$mode" \
    --promptString "Git user name=CI User" \
    --promptString "Git default email (every repo without an override)=ci@example.invalid" \
    --promptString "Git personal email (repos under ~/dev/)=ci-personal@example.invalid" \
    --promptString "Git work email (repos under ~/repos/)=ci-work@example.invalid" \
    --promptString "Jira API token (for Codex MCP; stored locally only)=ci-placeholder" \
    --promptString "GitLab token (for Codex MCP; stored locally only)=ci-placeholder" \
    >/dev/null

echo "$config"
```

- [ ] **Step 2: Write `scripts/render-check.sh`**

```bash
#!/usr/bin/env bash
# Render the entire chezmoi source tree for one (machine_role, versions_mode)
# pair into a throwaway destination, lint every script, and assert that no
# work-only or machine-specific content leaks. Used by CI on Linux and macOS
# and locally: scripts/render-check.sh personal pinned
set -euo pipefail

role=${1:?usage: render-check.sh <personal|work|both> <pinned|latest>}
mode=${2:?usage: render-check.sh <personal|work|both> <pinned|latest>}
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp" "${config:-}"' EXIT
dest="$tmp/home"
mkdir -p "$dest"
fail=0

echo "==> [$role/$mode] init: every prompt must be answerable non-interactively"
config=$("$repo/scripts/scratch-init.sh" "$role" "$mode")
chez=(chezmoi --config "$config" --source "$repo" --destination "$dest")

echo "==> [$role/$mode] apply into $dest (scripts rendered, never run)"
"${chez[@]}" apply --exclude scripts

echo "==> [$role/$mode] lint scripts"
while IFS= read -r -d '' script; do
    out="$tmp/rendered.sh"
    if ! "${chez[@]}" execute-template < "$script" > "$out"; then
        echo "RENDER FAIL: $script"; fail=1; continue
    fi
    if [ -s "$out" ]; then
        bash -n "$out" || { echo "SYNTAX FAIL: $script"; fail=1; }
        shellcheck -S warning "$out" || { echo "SHELLCHECK FAIL: $script"; fail=1; }
    fi
done < <(find "$repo/home/.chezmoiscripts" -name '*.sh.tmpl' -print0)

echo "==> [$role/$mode] leak checks"
if grep -rIl -F '/home/sabossedgh' "$dest"; then
    echo "LEAK: hardcoded home directory in rendered output"; fail=1
fi
if [ "$role" = personal ]; then
    if grep -rIl -e fortressinfosec -e dispatch-atlassian -e dispatch-gitlab -e coderabbit -e promptctl "$dest"; then
        echo "LEAK: work-only content rendered for machine_role=personal"; fail=1
    fi
    [ -e "$dest/.codex/hooks.json" ] && { echo "LEAK: .codex/hooks.json deployed on personal"; fail=1; }
    [ -e "$dest/.gitconfig-work" ] && { echo "LEAK: .gitconfig-work deployed on personal"; fail=1; }
fi
if [ "$role" != both ]; then
    [ -e "$dest/.gitconfig-personal" ] && { echo "LEAK: .gitconfig-personal deployed on single-role machine"; fail=1; }
fi
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    [ -e "$dest/.local/bin/win-browser" ] && { echo "LEAK: win-browser deployed on non-WSL host"; fail=1; }
fi
if grep -rIl -e '\.cursor' -e 'agent-brain' -e 'ab-claude' "$dest"; then
    echo "LEAK: Cursor or agent-brain content rendered"; fail=1
fi

echo "==> [$role/$mode] claude code status line"
python3 -m py_compile "$dest/.claude/scripts/statusline.py" || { echo "STATUSLINE FAIL: statusline.py does not compile"; fail=1; }
grep -q 'python3 ~/.claude/scripts/statusline.py' "$dest/.claude/settings.json" || { echo "STATUSLINE FAIL: settings.json does not point at statusline.py"; fail=1; }
grep -q 'statusline-command' "$dest/.claude/settings.json" && { echo "STATUSLINE FAIL: settings.json still references statusline-command.sh"; fail=1; }

if [ "$fail" -ne 0 ]; then echo "FAILED [$role/$mode]"; exit 1; fi
echo "OK [$role/$mode]"
```

- [ ] **Step 3: Make both executable and run the harness to confirm it fails today**

```bash
chmod +x scripts/scratch-init.sh scripts/render-check.sh
scripts/render-check.sh personal pinned
```

Expected on this Mac: FAIL. `init` errors because the current config template still asks for prompts that `scratch-init.sh` does not answer (for example `could not open a new TTY` on the old `personal_email` prompt text). That is the correct baseline; Task 2 makes init pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/scratch-init.sh scripts/render-check.sh
git commit -m "ci: add render-check harness that renders one machine role into a temp dir"
```

---

### Task 2: `machine_role` prompt and derived flags in the config template

**Files:**
- Modify: `home/.chezmoi.toml.tmpl` (whole file)

**Interfaces:**
- Produces data keys listed in Global Constraints. `is_wsl` replaces every inline `.chezmoi.kernel.osrelease` check in later tasks.

- [ ] **Step 1: Replace the file with this content**

```toml
{{- /*
Machine role decides which identity, secrets, and tool configuration deploy.
  personal: home projects only (~/dev). No employer tooling, no work tokens.
  work:     employer projects only (~/repos). Work MCP servers and hooks.
  both:     one machine for both; git identity switches per directory.
Answers persist in the local chezmoi.toml, never in the repo.
*/ -}}
{{- $role := promptChoiceOnce . "machine_role" "Machine role" (list "personal" "work" "both") "personal" -}}
{{- $hasWork := or (eq $role "work") (eq $role "both") -}}
{{- $hasPersonal := or (eq $role "personal") (eq $role "both") -}}
{{- /* WSL detection. .chezmoi.kernel is an empty map on macOS, so guard the key. */ -}}
{{- $isWsl := false -}}
{{- if eq .chezmoi.os "linux" -}}
{{-   if hasKey .chezmoi.kernel "osrelease" -}}
{{-     if .chezmoi.kernel.osrelease | lower | contains "microsoft" -}}
{{-       $isWsl = true -}}
{{-     end -}}
{{-   end -}}
{{- end -}}
sourceDir = "{{ .chezmoi.homeDir }}/dev/dotfiles"

[data]
    machine_role = "{{ $role }}"
    has_work = {{ $hasWork }}
    has_personal = {{ $hasPersonal }}
    is_wsl = {{ $isWsl }}
    name = "{{ promptStringOnce . "name" "Git user name" }}"
    email = "{{ promptStringOnce . "email" "Git default email (every repo without an override)" }}"
{{- if eq $role "both" }}
    personal_email = "{{ promptStringOnce . "personal_email" "Git personal email (repos under ~/dev/)" }}"
    work_email = "{{ promptStringOnce . "work_email" "Git work email (repos under ~/repos/)" }}"
{{- end }}
    editor = "{{ promptChoiceOnce . "editor" "Preferred editor" (list "code" "vim") "code" }}"
    versions_mode = "{{ promptChoiceOnce . "versions_mode" "Install pinned or latest tool versions" (list "pinned" "latest") "pinned" }}"
{{- if $hasWork }}
    # Secrets: stored only in the local chezmoi.toml on this machine, never in the repo
    jira_api_token = "{{ promptStringOnce . "jira_api_token" "Jira API token (for Codex MCP; stored locally only)" }}"
    gitlab_token = "{{ promptStringOnce . "gitlab_token" "GitLab token (for Codex MCP; stored locally only)" }}"
{{- end }}
{{- if $isWsl }}
{{/*
    WSL VM sizing defaults are derived from the *Windows host* (inside WSL,
    nproc and /proc/meminfo only report the VM's current cap, not the laptop).
    Rules: memory = 75% of host RAM, vCPUs = 2/3 of host logical CPUs,
    swap = memory/6. Each is a prompt-once with that default, so a machine can
    still override (answers persist in the local chezmoi.toml, never the repo).
*/}}
{{-   $hostGB := 0 }}
{{-   $hostCPU := 0 }}
{{-   if lookPath "powershell.exe" }}
{{-     $hostGB = output "powershell.exe" "-NoProfile" "-Command" "[int][math]::Ceiling((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)" | trim | int }}
{{-     $hostCPU = output "powershell.exe" "-NoProfile" "-Command" "(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors" | trim | int }}
{{-   end }}
{{-   $memGB := 8 }}
{{-   $cpus := 4 }}
{{-   if gt $hostGB 0 }}{{ $memGB = div (mul $hostGB 3) 4 }}{{ end }}
{{-   if gt $hostCPU 0 }}{{ $cpus = max 2 (div (mul $hostCPU 2) 3) }}{{ end }}
{{-   $swapGB := max 2 (div $memGB 6) }}
    wsl_memory = "{{ promptStringOnce . "wsl_memory" (printf "WSL memory limit (host has %dGB; default 75%%)" $hostGB) (printf "%dGB" $memGB) }}"
    wsl_processors = {{ promptIntOnce . "wsl_processors" (printf "WSL vCPUs (host has %d; default 2/3)" $hostCPU) $cpus }}
    wsl_swap = "{{ promptStringOnce . "wsl_swap" "WSL swap size (default memory/6)" (printf "%dGB" $swapGB) }}"
    restart_wsl_path = {{ promptStringOnce . "restart_wsl_path" "RestartWSL scripts path (relative to Windows home or a full path e.g. Desktop/RestartWSL)" | quote }}
{{- end }}
```

- [ ] **Step 2: Render the config for each role with a throwaway config so existing local answers do not interfere**

Prompt texts must stay comma-free (see Task 1). Check, then render:

```bash
grep -n 'prompt[A-Za-z]*Once' home/.chezmoi.toml.tmpl | grep -E '"[^"]*,[^"]*"' && echo "COMMA IN PROMPT TEXT" || echo "prompt texts ok"
for role in personal work both; do
  echo "--- $role"
  cat "$(scripts/scratch-init.sh "$role" pinned)"
done
```

Expected:
- `prompt texts ok`.
- `personal`: `has_work = false`, `has_personal = true`, `is_wsl = false`, no `personal_email`, `work_email`, or token lines.
- `work`: `has_work = true`, `has_personal = false`, token lines with `ci-placeholder`, no email override lines.
- `both`: both booleans true, `personal_email` and `work_email` present, token lines present.
- All three: `name = "CI User"`, `editor = "code"`, `versions_mode = "pinned"`.

- [ ] **Step 3: Run the harness**

```bash
scripts/render-check.sh personal pinned
```

Expected: `init` now succeeds. `apply` still fails at `.local/bin/win-browser` with `map has no entry for key "osrelease"` (fixed in Task 3).

- [ ] **Step 4: Commit**

```bash
git add home/.chezmoi.toml.tmpl
git commit -m "chezmoi: add machine_role prompt with derived has_work/has_personal/is_wsl flags, default versions_mode"
```

---

### Task 3: Platform and role gating in `.chezmoiignore`; fix the WSL guards

**Files:**
- Modify: `home/.chezmoiignore` (whole file)
- Modify: `home/dot_local/bin/executable_win-browser.tmpl:1`
- Modify: `home/.chezmoiscripts/wsl/run_once_before_00-packages-windows.sh.tmpl:1-2`
- Modify: `home/.chezmoiscripts/wsl/run_onchange_after_10-deploy-windows-configs.sh.tmpl:1-2`
- Modify: `home/.chezmoiscripts/wsl/run_onchange_after_20-sysctl.sh.tmpl:1-2`

**Interfaces:**
- Consumes: `.is_wsl`, `.has_work`, `.machine_role` from Task 2.

- [ ] **Step 1: Replace `.chezmoiignore`**

```
{{- /* Platform gating */ -}}
{{ if ne .chezmoi.os "linux" }}
.bashrc
{{ end }}
{{ if ne .chezmoi.os "darwin" }}
.zshrc
{{ end }}
{{ if not .is_wsl }}
.local/bin/win-browser
{{ end }}

{{- /* Role gating: work-only files never reach a personal machine */ -}}
{{ if not .has_work }}
.codex/hooks.json
{{ end }}
{{ if ne .machine_role "both" }}
.gitconfig-personal
.gitconfig-work
{{ end }}
```

- [ ] **Step 2: Change line 1 of `executable_win-browser.tmpl`**

From:
```
{{ if (.chezmoi.kernel.osrelease | lower | contains "microsoft") -}}
```
To:
```
{{ if .is_wsl -}}
```

- [ ] **Step 3: Change the guard in each of the three `wsl/` scripts**

Each file opens with a two-line nested guard and closes with two `{{ end -}}` lines. The outer line is always `{{ if eq .chezmoi.os "linux" -}}`; the inner line is `{{ if (.chezmoi.kernel.osrelease | lower | contains "microsoft") -}}` in `10-deploy-windows-configs` and `20-sysctl`, and `{{ if env "WSL_DISTRO_NAME" -}}` in `00-packages-windows`. In all three, replace the two guard lines with the single line

```
{{ if .is_wsl -}}
```

and delete one of the two trailing `{{ end -}}` lines. Confirm:

```bash
head -1 home/.chezmoiscripts/wsl/*.tmpl | grep -c 'if .is_wsl'
grep -c '{{ end' home/.chezmoiscripts/wsl/*.tmpl
```
Expected: `3`, then `1` for each of the three files.

- [ ] **Step 4: Run the harness on this Mac**

```bash
scripts/render-check.sh personal pinned
```

Expected: `apply` gets past `win-browser` and now fails at `.codex/config.toml` (`map has no entry for key "jira_api_token"` is gone because personal has none, but the template still references it unconditionally). That is fixed in Task 5.

- [ ] **Step 5: Commit**

```bash
git add home/.chezmoiignore home/dot_local/bin/executable_win-browser.tmpl home/.chezmoiscripts/wsl/
git commit -m "chezmoi: gate win-browser, hooks.json and gitconfig overrides by is_wsl and machine_role"
```

---

### Task 4: Git identity per role

**Files:**
- Modify: `home/dot_gitconfig.tmpl:10-14`
- Create: `home/dot_gitconfig-work.tmpl`
- Keep: `home/dot_gitconfig-personal.tmpl` (unchanged; now only deployed when role is `both`)

- [ ] **Step 1: Replace the includeIf block in `dot_gitconfig.tmpl`**

From:
```
# Directory-based identity overrides
# Repos under ~/dev/ use personal email
[includeIf "gitdir:~/dev/"]
    path = ~/.gitconfig-personal
```
To:
```
{{- if eq .machine_role "both" }}

# Directory-based identity overrides (machine_role = both).
# ~/dev/ is personal, ~/repos/ is work. Single-role machines
# use [user] email everywhere and deploy neither override file.
[includeIf "gitdir:~/dev/"]
    path = ~/.gitconfig-personal
[includeIf "gitdir:~/repos/"]
    path = ~/.gitconfig-work
{{- end }}
```

- [ ] **Step 2: Create `dot_gitconfig-work.tmpl`**

```
# Work git overrides
# Applied automatically for repos under ~/repos/ via includeIf
[user]
    email = {{ .work_email }}
```

- [ ] **Step 3: Verify rendering for each role**

```bash
for role in personal work both; do
  echo "--- $role"
  c=(chezmoi --config "$(scripts/scratch-init.sh "$role" pinned)" --source "$PWD" --destination "$(mktemp -d)")
  "${c[@]}" cat ~/.gitconfig | grep -A1 includeIf || echo "(no includeIf)"
  "${c[@]}" managed | grep gitconfig
done
```

Expected: `personal` and `work` print `(no includeIf)` and list only `.gitconfig`. `both` prints two includeIf entries and lists `.gitconfig`, `.gitconfig-personal`, `.gitconfig-work`.

- [ ] **Step 4: Commit**

```bash
git add home/dot_gitconfig.tmpl home/dot_gitconfig-work.tmpl
git commit -m "git: per-directory identity only on machine_role=both, add work override file"
```

---

### Task 5: Codex configuration per role

This is the largest change. The Codex config becomes a template gated on `has_personal` / `has_work`, trusts the `~/dev` and `~/repos` roots instead of individual repositories, and drops Codex-owned runtime state (`model_availability_nux`, `model_migrations`, `marketplaces`) that Codex rewrites itself and that only causes perpetual `chezmoi diff` noise.

**Files:**
- Modify: `home/dot_codex/private_config.toml.tmpl` (whole file)
- Rename + modify: `home/dot_codex/AGENTS.md` → `home/dot_codex/AGENTS.md.tmpl`
- Rename + modify: `home/dot_codex/private_hooks.json` → `home/dot_codex/private_hooks.json.tmpl`

**Interfaces:**
- Consumes: `.has_work`, `.has_personal`, `.machine_role`, `.email`, `.work_email`, `.jira_api_token`, `.gitlab_token`, `.versions.node_default` (from `home/.chezmoidata/versions.toml`), `.chezmoi.homeDir`.

**Decision recorded (revised 2026-09-06):** Codex runs with `sandbox_mode = "danger-full-access"` and `approval_policy = "never"` on every machine role, by user decision, so full permission never has to be set by hand. The `[sandbox_workspace_write]` block is therefore omitted. The Mac's `[agents]` block and `multi_agent = true` are adopted into the shared config since they are role-neutral.

- [ ] **Step 1: Replace `private_config.toml.tmpl`**

```toml
# :schema https://developers.openai.com/codex/config-schema.json
# Managed by chezmoi. Rendered for machine_role = {{ .machine_role }}.
# Codex rewrites some sections itself (model_availability_nux, marketplaces,
# model_migrations); those are intentionally not managed here.

model = "gpt-5.6-sol"
model_reasoning_effort = "xhigh"
plan_mode_reasoning_effort = "max"
sandbox_mode = "danger-full-access"
approval_policy = "never"
approvals_reviewer = "user"
web_search = "live"
project_doc_max_bytes = 65536
service_tier = "default"
personality = "pragmatic"

[features]
shell_tool = true
multi_agent = true
prevent_idle_sleep = true
terminal_resize_reflow = true
memories = true

[agents]
max_depth = 2
max_threads = 20
job_max_runtime_seconds = 3600

# Trust is granted per root, not per repository:
# everything under ~/dev is personal, everything under ~/repos is work.
{{- if .has_personal }}

[projects."{{ .chezmoi.homeDir }}/dev"]
trust_level = "trusted"
{{- end }}
{{- if .has_work }}

[projects."{{ .chezmoi.homeDir }}/repos"]
trust_level = "trusted"
{{- end }}

[notice]
hide_full_access_warning = true
hide_rate_limit_model_nudge = true

[tools]
web_search = { context_size = "high" }

[tui]
status_line = ["context-remaining", "model-with-reasoning", "current-dir", "git-branch", "five-hour-limit", "weekly-limit", "used-tokens"]
pet = "disabled"
status_line_use_colors = true

[mcp_servers.openaiDeveloperDocs]
url = "https://developers.openai.com/mcp"

[mcp_servers.openaiDeveloperDocs.tools.search_openai_docs]
approval_mode = "approve"

[mcp_servers.openaiDeveloperDocs.tools.fetch_openai_doc]
approval_mode = "approve"

[plugins."github@openai-curated"]
enabled = true

[plugins."gmail@openai-curated"]
enabled = true

[plugins."superpowers@openai-curated"]
enabled = true

[profiles.sidekick_implementation]
approvals_reviewer = "user"

[profiles.sidekick_implementation.features]
js_repl = false
guardian_approval = false
prevent_idle_sleep = true
{{- if .has_work }}

# ---------------------------------------------------------------------------
# Work only: employer MCP servers, review tooling, and the prompt-prefix hook.
# ---------------------------------------------------------------------------

[plugins."coderabbit@openai-curated"]
enabled = true

[mcp_servers.dispatch-atlassian]
enabled = false
command = "{{ .chezmoi.homeDir }}/.nvm/versions/node/v{{ .versions.node_default }}/bin/node"
args = ["{{ .chezmoi.homeDir }}/repos/ai-devtools/dispatch-atlassian/dist/index.js"]

[mcp_servers.dispatch-atlassian.env]
JIRA_BASE_URL = "https://fortressinfosec.atlassian.net"
JIRA_EMAIL = "{{ if eq .machine_role "both" }}{{ .work_email }}{{ else }}{{ .email }}{{ end }}"
JIRA_API_TOKEN = "{{ .jira_api_token }}"
{{ range list "fetch_attachments" "fetch_changelog" "fetch_comments" "fetch_confluence_page" "fetch_epic_context" "fetch_ticket" "gather_full_context" "search_confluence" "search_tickets" }}
[mcp_servers.dispatch-atlassian.tools.{{ . }}]
approval_mode = "approve"
{{ end }}
[mcp_servers.dispatch-gitlab]
enabled = false
command = "{{ .chezmoi.homeDir }}/.nvm/versions/node/v{{ .versions.node_default }}/bin/node"
args = ["{{ .chezmoi.homeDir }}/repos/ai-devtools/dispatch-gitlab/dist/index.js"]

[mcp_servers.dispatch-gitlab.env]
GITLAB_URL = "https://gitlab.com/fortressinfosec"
GITLAB_TOKEN = "{{ .gitlab_token }}"

[mcp_servers.dispatch-gitlab.tools.get_linked_mrs]
approval_mode = "approve"
{{- end }}
```

- [ ] **Step 2: Rename and template `AGENTS.md`**

```bash
git mv home/dot_codex/AGENTS.md home/dot_codex/AGENTS.md.tmpl
```

Replace the `## Path-scoped tool policy` section (from that heading to end of file) with:

```
{{- if eq .machine_role "both" }}

## Path-scoped tool policy

For any task whose effective working directory, repository, or write scope is
under `{{ .chezmoi.homeDir }}/dev/`:

- Never invoke CodeRabbit or any CodeRabbit-backed skill, tool, review, autofix,
  or autonomous review workflow.
- Do not invoke `dispatch-atlassian`, `dispatch-gitlab`, Atlassian, Jira, or
  GitLab MCP tools.

This prohibition is scoped to `{{ .chezmoi.homeDir }}/dev/` and its descendants.
It does not prohibit those tools for work under `{{ .chezmoi.homeDir }}/repos/`.
{{- end }}
```

- [ ] **Step 3: Rename and template `hooks.json`**

```bash
git mv home/dot_codex/private_hooks.json home/dot_codex/private_hooks.json.tmpl
```

Replace the file content with:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "{{ .chezmoi.homeDir }}/.promptctl/bin/codex-prefix-hook"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Verify each role**

```bash
for role in personal work both; do
  echo "--- $role"
  c=(chezmoi --config "$(scripts/scratch-init.sh "$role" pinned)" --source "$PWD" --destination "$(mktemp -d)")
  "${c[@]}" cat ~/.codex/config.toml | grep -E '^\[projects|writable_roots|^\[mcp_servers\.dispatch|coderabbit|JIRA_EMAIL' 
  "${c[@]}" cat ~/.codex/config.toml | python3 -c "import sys,tomllib; tomllib.loads(sys.stdin.read()); print('toml ok')"
  "${c[@]}" managed | grep -E 'hooks.json|AGENTS.md'
done
```

Expected:
- `personal`: one `[projects."<home>/dev"]`, `writable_roots` with `dev` only, no dispatch, no coderabbit; managed lists `AGENTS.md` but not `hooks.json`.
- `work`: one `[projects."<home>/repos"]`, dispatch servers present, `JIRA_EMAIL = "ci@example.invalid"`, `hooks.json` managed.
- `both`: both project roots, both writable roots, `JIRA_EMAIL = "ci-work@example.invalid"`.
- `toml ok` for all three.

- [ ] **Step 5: Run the harness**

```bash
scripts/render-check.sh personal pinned && scripts/render-check.sh both pinned
```

Expected: both reach the leak checks. `both` may still report `LEAK: hardcoded home directory` from `.bashrc` on Linux hosts only; on this Mac `.bashrc` is ignored so both should print `OK`.

- [ ] **Step 6: Commit**

```bash
git add home/dot_codex/
git commit -m "codex: template config/AGENTS/hooks by machine_role, trust ~/dev and ~/repos roots"
```

---

### Task 6: Shell rc files: shared Bitwarden fragment, one `claude` alias, work gating, local override hook

**Files:**
- Create: `home/.chezmoitemplates/bw-wrapper.sh`
- Modify: `home/dot_zshrc.tmpl:57` (the `claude()` function line) and `home/dot_zshrc.tmpl:63-108` (editor line through end of file)
- Modify: `home/private_dot_bashrc.tmpl:37-40` (aliases block) and `home/private_dot_bashrc.tmpl:71-134` (from the `create-spec` alias through end of file)

**Interfaces:**
- Produces: `{{ template "bw-wrapper.sh" . }}` fragment included by both rc templates.
- Produces: the line `claude() { command claude --verbose --allow-dangerously-skip-permissions "$@"; }` in both rc files. VS Code is the only editor; there is no `code()` wrapper and no Cursor detection.

- [ ] **Step 1: Create `home/.chezmoitemplates/bw-wrapper.sh`**

Move the Bitwarden block verbatim out of `dot_zshrc.tmpl` (from the `# --- Bitwarden CLI (bw): persistent unlock ---` comment through the closing `}` of the `bw()` function). The fragment must be identical in both rc files today; confirm before deleting:

```bash
diff <(sed -n '/^# --- Bitwarden CLI/,/^}/p' home/dot_zshrc.tmpl) <(sed -n '/^# --- Bitwarden CLI/,/^}/p' home/private_dot_bashrc.tmpl) && echo identical
```

Expected: `identical`. Then write that block as the full content of `home/.chezmoitemplates/bw-wrapper.sh`.

- [ ] **Step 2: Keep the `claude` function in `dot_zshrc.tmpl`**

The `# --- Aliases ---` block already contains the correct line; leave it exactly as is:

```
claude() { command claude --verbose --allow-dangerously-skip-permissions "$@"; }
```

- [ ] **Step 3: Rewrite the tail of `dot_zshrc.tmpl`**

Replace everything from `# --- Editor ---` to end of file with:

```
# --- Editor ---
export EDITOR="{{ .editor }} --wait"

{{ template "bw-wrapper.sh" . }}

# --- Local overrides (not managed by chezmoi) ---
# Machine-specific aliases and installer blocks belong here so chezmoi apply
# never removes them.
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
```

- [ ] **Step 4: Add the `claude` function to `private_dot_bashrc.tmpl` and rewrite its tail**

In the `# --- Aliases ---` block, directly after `alias cat='bat --paging=never'`, add the same line the zsh template uses:

```
claude() { command claude --verbose --allow-dangerously-skip-permissions "$@"; }
```

Then replace everything from the `alias create-spec=...` line to end of file with:

```
{{- if .has_work }}

# --- Work tooling ---
alias create-spec='source "$HOME/repos/ai-devtools/.venv/bin/activate" && python "$HOME/repos/ai-devtools/.claude/tmp/sessions/2026-02-10/artifacts/create_spec_only.py"'
# promptctl
[ -f "$HOME/.promptctl/shell/aliases.sh" ] && source "$HOME/.promptctl/shell/aliases.sh"
{{- end }}
{{- if .is_wsl }}

# WSL: hand the VM's file cache back to Windows on demand. Linux keeps
# everything it reads cached (shows up as vmmemWSL in Task Manager); this is
# reclaimable and autoMemoryReclaim trims it when idle, but after big image
# pulls / clones you may want it back immediately.
alias clear-cache="sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches' && free -h"

# WSL: route browser opens (bw login SSO/Duo, gh auth, xdg-open) to Windows
# via ~/.local/bin/win-browser (Chrome -> wslview -> Windows default). A
# wrapper rather than chrome.exe directly because some tools (gh) split
# $BROWSER on spaces, and wslview alone is unavailable on Ubuntu 26.04 —
# an unresolvable BROWSER makes CLIs hang silently waiting for a callback.
if [ -x "$HOME/.local/bin/win-browser" ]; then
    export BROWSER="$HOME/.local/bin/win-browser"
fi
{{- end }}

# Added by remote-dev-workstation install
export PATH="$HOME/bin:$PATH"

{{ template "bw-wrapper.sh" . }}
```

This drops the whole `>>> agent-brain >>>` block and the comment near the top of that region that says the `claude` alias lives in `~/.bash_aliases`. The alias now lives in the Aliases block from this step. Also delete the now-duplicated original WSL `clear-cache` and `BROWSER` blocks that sat between the `create-spec` alias and the `remote-dev-workstation` line (they are reproduced above inside the `is_wsl` guard).

- [ ] **Step 5: Syntax-check both rendered rc files**

```bash
tmp=$(mktemp -d)
c=(chezmoi --config "$(scripts/scratch-init.sh both pinned)" --source "$PWD" --destination "$tmp")
"${c[@]}" execute-template < home/dot_zshrc.tmpl > "$tmp/zshrc" && zsh -n "$tmp/zshrc" && echo "zsh ok"
"${c[@]}" execute-template < home/private_dot_bashrc.tmpl > "$tmp/bashrc" && bash -n "$tmp/bashrc" && echo "bash ok"
grep -c 'bw()' "$tmp/zshrc" "$tmp/bashrc"
grep -c '^claude() { command claude --verbose --allow-dangerously-skip-permissions "\$@"; }$' "$tmp/zshrc" "$tmp/bashrc"
grep -c 'alias claude=' "$tmp/zshrc" "$tmp/bashrc" || true
PATH="$tmp/fakebin:$PATH"; mkdir -p "$tmp/fakebin"; printf '#!/bin/sh\nprintf "[%%s] " "$@"; echo\n' > "$tmp/fakebin/claude"; chmod +x "$tmp/fakebin/claude"
zsh -c "source $tmp/zshrc >/dev/null 2>&1; claude --model opus -p 'two words'"
bash -c "source $tmp/bashrc >/dev/null 2>&1; claude --model opus -p 'two words'"
grep -E -e 'cursor' -e 'code\(\)' -e 'agent-brain' -e 'ab-claude' -e '/home/sabossedgh' "$tmp/zshrc" "$tmp/bashrc" || echo "clean"
```

Expected: `zsh ok`, `bash ok`, `bw()` count `1` in each, `claude()` count `1` in each, `alias claude=` count `0` in each, `clean`, and both of the last two commands print `[--verbose] [--allow-dangerously-skip-permissions] [--model] [opus] [-p] [two words]` proving extra arguments and quoting pass through.

- [ ] **Step 6: Run the harness for every role**

```bash
for r in personal work both; do scripts/render-check.sh "$r" pinned; done
```

Expected: `OK [personal/pinned]`, `OK [work/pinned]`, `OK [both/pinned]`.

- [ ] **Step 7: Commit**

```bash
git add home/.chezmoitemplates/ home/dot_zshrc.tmpl home/private_dot_bashrc.tmpl
git commit -m "shell: share bw wrapper, claude() in bash too, drop agent-brain block, gate work tooling, source ~/.zshrc.local"
```

---

### Task 7: Scripts: shared tmux-plugins, Bitwarden CLI on macOS

**Files:**
- Rename: `home/.chezmoiscripts/linux/run_onchange_after_40-tmux-plugins.sh.tmpl` → `home/.chezmoiscripts/shared/run_onchange_after_40-tmux-plugins.sh.tmpl`
- Modify: `home/.chezmoiscripts/darwin/run_once_before_00-packages.sh.tmpl:2` and before the final `echo "==> macOS bootstrap complete."`

- [ ] **Step 1: Move the tmux plugin script**

```bash
mkdir -p home/.chezmoiscripts/shared
git mv home/.chezmoiscripts/linux/run_onchange_after_40-tmux-plugins.sh.tmpl home/.chezmoiscripts/shared/run_onchange_after_40-tmux-plugins.sh.tmpl
```

Edit its second line comment to read:
```
# Install tmux plugins via TPM whenever tmux.conf changes (every platform; TPM is installed by each platform's 00-packages bootstrap)
```

- [ ] **Step 2: Add Bitwarden CLI to the macOS bootstrap**

Change line 2 to:
```
# Bootstrap script for macOS — installs Homebrew, bat, fd, oh-my-posh, JetBrains Mono Nerd Font, tmux, TPM, gh (bitwarden-cli on work machines)
```

Insert before `echo "==> macOS bootstrap complete."`:
```bash
{{- if .has_work }}
# --- Bitwarden CLI (the bw wrapper in .zshrc expects it; work machines only) ---
if ! command -v bw &>/dev/null; then
    echo "==> Installing Bitwarden CLI..."
    brew install bitwarden-cli
    echo "    bitwarden-cli installed."
else
    echo "==> Bitwarden CLI already installed, skipping."
fi
{{- end }}
```

- [ ] **Step 3: Verify**

```bash
scripts/render-check.sh personal pinned
chezmoi --source "$PWD" --config "$(mktemp -d)/none.toml" execute-template < home/.chezmoiscripts/shared/run_onchange_after_40-tmux-plugins.sh.tmpl | head -3
```

Expected: `OK [personal/pinned]`; the shared script renders with its shebang and hash comment.

- [ ] **Step 4: Commit**

```bash
git add home/.chezmoiscripts/
git commit -m "scripts: move tmux-plugins to shared/, install bitwarden-cli on macOS work machines"
```

---

### Task 8: CI on Linux and macOS for every role

**Files:**
- Modify: `.github/workflows/ci.yml` (replace the `render-and-lint` job)

- [ ] **Step 1: Replace the `render-and-lint` job**

```yaml
  render-and-lint:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
        machine_role: [personal, work, both]
        versions_mode: [pinned, latest]
        exclude:
          # versions_mode only affects the Linux runtime scripts
          - os: macos-latest
            versions_mode: latest
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Install chezmoi and shellcheck
        run: |
          if [ "$RUNNER_OS" = Linux ]; then
            sudo apt-get update -q && sudo apt-get install -y shellcheck
          else
            brew install shellcheck
          fi
          sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"
      - name: Render, lint, and leak-check
        run: scripts/render-check.sh "${{ matrix.machine_role }}" "${{ matrix.versions_mode }}"
```

Leave the `secret-scan` job unchanged.

- [ ] **Step 2: Validate the workflow file locally**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('yaml ok')" 2>/dev/null || ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml"); puts "yaml ok"'
```

Expected: `yaml ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: matrix over os x machine_role, run render-check on macOS too"
```

---

### Task 9: Documentation

**Files:**
- Modify: `CLAUDE.md` (Key files table, Template variables, Platform gating, Testing changes)
- Modify: `README.md` (prompt list near line 24 and 37; add a "Machine role" section after "How Syncing Works")
- Modify: `docs/macos.md:68` and `docs/linux.md:75`

- [ ] **Step 1: CLAUDE.md**

Add these rows to the Key files table:

```
| `home/dot_gitconfig-work.tmpl` | `~/.gitconfig-work` | Work email for repos under `~/repos/`; only when `machine_role=both` |
| `home/.chezmoiscripts/shared/run_onchange_after_40-tmux-plugins.sh.tmpl` | (run script) | Every platform; installs tmux plugins via TPM when tmux.conf changes |
| `home/.chezmoitemplates/bw-wrapper.sh` | (template fragment) | Bitwarden `bw unlock`/`bw lock` wrapper shared by `.bashrc` and `.zshrc` |
| `scripts/scratch-init.sh` | (dev tool) | Generates a throwaway `chezmoi.toml` for one role with every prompt answered; prompt-text keys must match `.chezmoi.toml.tmpl` |
| `scripts/render-check.sh` | (dev tool) | Renders the whole tree for one role into a temp dir, lints scripts, checks for work/home-path leaks and the status line; what CI runs |
```

Change the `linux/run_onchange_after_40-tmux-plugins` row to point at `shared/`, and change the `dot_codex/` row to read: `` `AGENTS.md.tmpl`, `private_config.toml.tmpl`, `private_hooks.json.tmpl` (hooks only when `has_work`) ``.

Under Template variables add:

```
- `.machine_role` — `personal`, `work`, or `both` (default `personal`). Derived booleans stored alongside it: `.has_work`, `.has_personal`, `.is_wsl`. Gate templates on the booleans, never re-derive them.
- `.work_email` — Git work email for `~/repos/` (only prompted when `machine_role=both`)
```
Change `.personal_email` to say it is only prompted when `machine_role=both`, and the token lines to say "only prompted when `has_work`". Leave `.editor` as `code`/`vim`.

Under Conventions add: `- **Editor**: VS Code only. No Cursor references or IDE-routing wrappers. **Claude wrapper**: both rc files define the function ` `claude() { command claude --verbose --allow-dangerously-skip-permissions "$@"; }` ` (a function, not an alias, so it works with alias expansion off and inside other functions) and nothing else manages it.`

Under Platform gating replace the `wsl/` sentence with: `` `wsl/` is a repo convention, not a chezmoi OS — those scripts guard with `{{ if .is_wsl }}`. `.chezmoi.kernel` is empty on macOS, so never read `.chezmoi.kernel.osrelease` directly in a template. ``

Under Testing changes add: `` Run `scripts/render-check.sh <role> <mode>` locally before pushing; it is exactly what CI runs and never touches `~`. After pulling a change to `home/.chezmoi.toml.tmpl`, run `chezmoi init` (no apply) to answer any new prompt before `chezmoi diff`. ``

- [ ] **Step 2: README.md**

Update the prompt sentence at line 24 to: "Chezmoi will prompt for your name, git email, machine role (personal, work, or both), preferred editor, and pinned or latest tool versions. A machine role of `both` also asks for the personal and work emails; any role that includes work asks for the Jira and GitLab tokens."

Add after the "How Syncing Works" section:

```markdown
## Machine Role

`chezmoi init` asks once whether a machine is `personal`, `work`, or `both`.

| Role | Git identity | Codex trust roots | Work MCP servers, CodeRabbit, prompt hook |
|---|---|---|---|
| `personal` | `.email` everywhere | `~/dev` | not deployed |
| `work` | `.email` everywhere | `~/repos` | deployed |
| `both` | `~/dev/` personal, `~/repos/` work | `~/dev` and `~/repos` | deployed |

Change it later with `chezmoi init` after editing `~/.config/chezmoi/chezmoi.toml`, or delete the `machine_role` line to be prompted again.
```

- [ ] **Step 3: docs/macos.md and docs/linux.md**

In `docs/macos.md` delete the bullet `` - `code()` wrapper with workspace routing (VS Code) `` (line 68) and add in its place: `` - `~/.zshrc.local` is sourced last and is not managed by chezmoi; put machine-specific aliases and installer blocks there ``.

In `docs/linux.md` delete the bullet `` - `code()` wrapper with workspace routing (VS Code) `` (line 75) and add: `` - Work-only aliases (`create-spec`, promptctl) render only when `machine_role` is `work` or `both` ``.

Confirm no stray references remain:
```bash
grep -rniE 'cursor|agent-brain|ab-claude|code\(\)' README.md CLAUDE.md docs/*.md home/ || echo "docs clean"
```
Expected: `docs clean`.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md docs/macos.md docs/linux.md
git commit -m "docs: document machine_role, shared fragments, and render-check"
```

---

### Task 10: Roll out on this Mac (stops for approval before apply)

**Files:** none in the repo. Touches `~/.config/chezmoi/chezmoi.toml` only until approval.

- [ ] **Step 1: Full harness pass on the branch**

```bash
for r in personal work both; do scripts/render-check.sh "$r" pinned || exit 1; done; echo ALL OK
```

Expected: `ALL OK`.

- [ ] **Step 2: Back up the files apply will rewrite**

```bash
stamp=$(date +%Y%m%d-%H%M%S)
for f in ~/.zshrc ~/.gitconfig ~/.claude/settings.json ~/.codex/config.toml ~/.codex/AGENTS.md ~/.config/tmux/tmux.conf; do cp -p "$f" "$f.bak-$stamp"; done
ls -la ~/.claude/scripts   # note: this is a symlink into ~/dev/ai-sidekicks; apply replaces it with a real directory
```

- [ ] **Step 3: Regenerate the local config (writes only `~/.config/chezmoi/chezmoi.toml`)**

The local config still says `editor = "cursor"`, and `promptChoiceOnce` keeps any existing answer, so switch it to VS Code first and then re-init:

```bash
sed -i '' 's/^\(\s*editor = \)"cursor"/\1"code"/' ~/.config/chezmoi/chezmoi.toml
chezmoi init
```

Answer `personal` for machine role. Existing answers (`name`, `email`, `editor = code`) are kept automatically. No token prompts should appear.

```bash
grep -E 'machine_role|has_work|is_wsl|editor|work_email' ~/.config/chezmoi/chezmoi.toml
```

Expected: `machine_role = "personal"`, `has_work = false`, `is_wsl = false`, `editor = "code"`. The stale `work_email` line is gone because `chezmoi init` rewrites the file from the template.

- [ ] **Step 4: Preview**

```bash
chezmoi status
chezmoi diff --no-pager
```

Expected differences on this Mac, and nothing else:
- `.codex/config.toml`: trust collapses to `[projects."/Users/sawmonabo/dev"]`, sandbox stays `danger-full-access` / `never`, `deep-research@sidekick-skills` plugin kept, `[marketplaces.sidekick-skills]` keeps its static `source_type`/`source`/`ref` keys while Codex-owned `last_updated`/`last_revision` are dropped (Codex re-adds them on its next refresh; expect that two-line diff afterwards), no dispatch or Fortress content, no `/home/sabossedgh` anywhere.
- `.claude/settings.json`: global plugins become exactly superpowers, deep-research, memory-audit, claude-md-management, skill-creator, code-review, code-simplifier, codex, context7, post-mortem (measured from 90 days of transcripts on 2026-09-06); language servers and domain packs are per-repo.
- `.codex/AGENTS.md`: personal instructions without the path-scoped policy.
- `.codex/hooks.json`: not created.
- `.gitconfig`: `core.editor` becomes `code --wait`, no includeIf lines, gh credential helper added. `~/.gitconfig-work` is left untouched but unused (delete it by hand if desired).
- `.zshrc`: `EDITOR` becomes `code --wait`, the `code()` Cursor launcher and the agent-brain block (with its duplicate `alias claude=`) are removed, the `claude()` function is unchanged and present exactly once, Bitwarden wrapper added, `~/.zshrc.local` sourced.
- `.claude/scripts`: the symlink into `~/dev/ai-sidekicks` is deleted and replaced by a real directory containing `statusline.py`. `.claude/settings.json` switches `statusLine.command` to `python3 ~/.claude/scripts/statusline.py`.
- `.claude/CLAUDE.md`, `.local/bin/claude-costs` as in the original audit.
- Scripts to run: `darwin/00-packages.sh` (installs `fd` only; bitwarden-cli is work-only), `darwin/10-terminal-font.sh`, `shared/40-tmux-plugins.sh`.

- [ ] **Step 5: STOP. Show the diff to the user and wait for explicit approval.**

Do not run `chezmoi apply` in this task without the user saying so. When approved:

```bash
chezmoi apply -v
exec zsh -l
```

Then confirm Codex still resolves the deep-research plugin (marketplace registration survived the managed file):

```bash
grep -A3 '^\[marketplaces.sidekick-skills\]' ~/.codex/config.toml
codex --version && ls ~/.codex/plugins/cache/sidekick-skills
```

Expected: the block shows `source_type = "git"`, the sidekick-skills source URL, and `ref = "marketplace"`; the plugin cache directory still exists.

Then verify the status line is the repo's, not the old symlinked script:

```bash
test ! -L ~/.claude/scripts && test -d ~/.claude/scripts && echo "scripts is a real directory"
test -x ~/.claude/scripts/statusline.py && echo "statusline.py present"
cmp ~/.claude/scripts/statusline.py ~/dev/dotfiles/home/dot_claude/scripts/executable_statusline.py && echo "statusline.py matches repo"
grep -n 'statusLine' -A3 ~/.claude/settings.json
echo '{"model":{"display_name":"Fable"},"workspace":{"current_dir":"'"$HOME"'/dev/dotfiles"},"context_window":{"used_percentage":12}}' | COLUMNS=120 python3 ~/.claude/scripts/statusline.py | cat -v | head -2
type claude; echo "$EDITOR"; type code
```

Expected: the three `echo` confirmations print, `settings.json` shows `"command": "python3 ~/.claude/scripts/statusline.py"` with `refreshInterval: 2`, the status line prints one line of coloured segments containing `Fable` and `ctx 12%`, `claude` is reported as an alias, `EDITOR` is `code --wait`, and `code` resolves to the VS Code binary rather than a shell function. Open a new Claude Code session and confirm the lualine-style bar renders.

Then check Codex trust:

```bash
codex --version && cd ~/dev/dotfiles && codex exec "print the working directory" 2>&1 | head -5
```

This checks that Codex treats a subdirectory of the trusted `~/dev` root as trusted without prompting. If it prompts, Codex is matching exact paths only; record that in the plan follow-ups and add `[projects."<repo>"]` entries back for the repositories actually in use.

- [ ] **Step 6: Merge**

```bash
git switch main && git merge --ff-only feat/machine-role && git push
```

---

## Part 2: macOS package parity

Tasks 11 to 13 are independent of the machine-role work and land on their own branch after Task 10 is merged. They bring the Mac bootstrap up to the Linux side: a data-driven Homebrew install, the same runtime managers, and the same global tools read from `versions.toml`. Scope was agreed on 2026-09-05 from an inventory of this Mac; deliberately excluded: ffmpeg, poppler, wireguard-tools, WireGuard, Syncthing, Discord, WhatsApp, Zoom, ChatGPT, pyenv, rbenv, eas-cli, yarn, axoniq, cargo-fuzz, watchman, cocoapods.

**Global constraints for Part 2**
- Branch `feat/darwin-packages` off `main` after `feat/machine-role` is merged.
- Package names in data files never carry versions (`postgresql`, not `postgresql@15`). Version policy stays in `versions.toml` and the `versions_mode` prompt.
- The macOS scripts mirror the Linux ones section for section so the two stay reviewable side by side. Where a Linux step is apt-specific, the Mac step uses Homebrew.
- Every task is verified with `scripts/render-check.sh` on this Mac. No script is executed against the machine until the user approves in Task 13.

---

### Task 11: Data-driven Homebrew bootstrap

**Files:**
- Modify: `home/.chezmoidata/packages.toml` (add `[packages.darwin]`, merge VS Code extensions)
- Modify: `home/.chezmoiscripts/darwin/run_once_before_00-packages.sh.tmpl` (whole file)
- Modify: `scripts/render-check.sh` (one extra leak check)

**Interfaces:**
- Produces data: `.packages.darwin.brew` (list), `.packages.darwin.cask` (list), `.packages.vscode_extensions` (list, now the single canonical set for every platform).

- [ ] **Step 1: Add the darwin section and merge the extension list in `packages.toml`**

Insert after the closing `]` of the `apt` list and before `vscode_extensions`:

```toml

# Homebrew (macOS). Installed by .chezmoiscripts/darwin/00-packages.
# Names only; no versions. bat, fd, oh-my-posh, tmux, gh, and the Nerd Font are
# listed here too so the bootstrap has one source of truth.
[packages.darwin]
brew = [
  "age",
  "bat",
  "bats-core",
  "bun",
  "chezmoi",
  "docker",
  "fd",
  "gh",
  "git-filter-repo",
  "gitleaks",
  "go",
  "gofumpt",
  "golangci-lint",
  "goreleaser",
  "htop",
  "jandedobbeleer/oh-my-posh/oh-my-posh",
  "jq",
  "lefthook",
  "pnpm",
  "postgresql",
  "ripgrep",
  "shellcheck",
  "tmux",
  "tree",
  "uv",
]
cask = [
  "claude",
  "dbeaver-community",
  "docker-desktop",
  "font-jetbrains-mono-nerd-font",
  "google-chrome",
  "obsidian",
  "ollama-app",
  "visual-studio-code",
]
```

Then add these IDs to `vscode_extensions`, keeping the list sorted:

```
  "docker.docker",
  "donjayamanne.python-environment-manager",
  "dsznajder.es7-react-js-snippets",
  "dustypomerleau.rust-syntax",
  "jasonn-porch.gitlab-mr",
  "kevinrose.vsc-python-indent",
  "matangover.mypy",
  "ms-vscode-remote.remote-ssh",
  "ms-vscode-remote.remote-ssh-edit",
  "ms-vscode.remote-explorer",
  "rust-lang.rust-analyzer",
  "sidthesloth.html5-boilerplate",
  "stephanvs.dot",
  "tomoki1207.pdf",
  "vscode-icons-team.vscode-icons",
  "xabikos.javascriptsnippets",
```

Update the file's header comment to: `# Package data consumed by the platform bootstrap scripts (darwin) or kept as a manual reference (apt, pending a scripted install). vscode_extensions is the canonical set for every platform.`

- [ ] **Step 2: Rewrite `darwin/run_once_before_00-packages.sh.tmpl`**

```bash
{{ if eq .chezmoi.os "darwin" -}}
#!/usr/bin/env bash
# macOS bootstrap: Homebrew, then every formula and cask listed under
# [packages.darwin] in .chezmoidata/packages.toml, then TPM and VS Code
# extensions. Idempotent: brew skips anything already installed.
set -euo pipefail

echo "==> macOS bootstrap starting..."

# --- Homebrew ---
if ! command -v brew &>/dev/null; then
    echo "==> Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# --- Formulae ---
formulae=(
{{- range .packages.darwin.brew }}
    "{{ . }}"
{{- end }}
)
missing=()
for formula in "${formulae[@]}"; do
    brew list --formula "${formula##*/}" &>/dev/null || missing+=("$formula")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "==> Installing formulae: ${missing[*]}"
    brew install "${missing[@]}"
else
    echo "==> All formulae already installed."
fi

# --- Casks ---
casks=(
{{- range .packages.darwin.cask }}
    "{{ . }}"
{{- end }}
)
missing=()
for cask in "${casks[@]}"; do
    brew list --cask "$cask" &>/dev/null || missing+=("$cask")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "==> Installing casks: ${missing[*]}"
    brew install --cask "${missing[@]}"
else
    echo "==> All casks already installed."
fi

# --- Oh My Posh config directory ---
mkdir -p "$HOME/.config/oh-my-posh"

# --- TPM (Tmux Plugin Manager) ---
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "==> Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi

# --- VS Code extensions ---
if command -v code &>/dev/null; then
    installed=$(code --list-extensions | tr '[:upper:]' '[:lower:]')
    for extension in \
{{- range .packages.vscode_extensions }}
        "{{ . }}" \
{{- end }}
    ; do
        # tr rather than ${extension,,}: macOS ships bash 3.2, which lacks case expansion
        grep -qx "$(tr '[:upper:]' '[:lower:]' <<<"$extension")" <<<"$installed" || code --install-extension "$extension" --force
    done
else
    echo "    code CLI not on PATH; skipping VS Code extensions."
fi

echo "==> macOS bootstrap complete."
{{ end -}}
```

- [ ] **Step 3: Extend the harness**

In `scripts/render-check.sh`, inside the leak-checks block, add:

```bash
if grep -rIn -E '"[a-z0-9-]+@[0-9.]+"' "$repo/home/.chezmoidata/packages.toml"; then
    echo "LEAK: versioned package name in packages.toml"; fail=1
fi
```

- [ ] **Step 4: Verify**

```bash
scripts/render-check.sh personal pinned
c=(chezmoi --config "$(scripts/scratch-init.sh personal pinned)" --source "$PWD" --destination "$(mktemp -d)")
"${c[@]}" execute-template < home/.chezmoiscripts/darwin/run_once_before_00-packages.sh.tmpl > /tmp/darwin-00.sh
bash -n /tmp/darwin-00.sh && shellcheck -S warning /tmp/darwin-00.sh && echo "lint ok"
grep -c '^    "' /tmp/darwin-00.sh
python3 -c "import tomllib; d=tomllib.load(open('home/.chezmoidata/packages.toml','rb'))['packages']; print(len(d['darwin']['brew']), len(d['darwin']['cask']), len(d['vscode_extensions']))"
```

Expected: `OK [personal/pinned]`, `lint ok`, quoted-line count equals formulae + casks + extensions, and the python line prints `25 8 71`. Keep Task 7's `{{- if .has_work }}` bitwarden-cli block in the rewritten script, after the casks section; it must never appear in the data list because the list is role-neutral.

- [ ] **Step 5: Commit**

```bash
git add home/.chezmoidata/packages.toml home/.chezmoiscripts/darwin/run_once_before_00-packages.sh.tmpl scripts/render-check.sh
git commit -m "darwin: data-driven brew bootstrap from packages.toml, merge VS Code extension list"
```

---

### Task 12: macOS runtime managers and global tools

Mirrors `linux/10-runtime-managers` and `linux/30-global-tools`. nvm and rustup use the same upstream installers; uv, bun, and Go are already installed by Homebrew in Task 11 so those sections become presence checks. Node and Python runtime installs (`linux/20-runtimes`) are also mirrored since nothing in them is Linux-specific.

**Files:**
- Create: `home/.chezmoiscripts/darwin/run_once_after_10-runtime-managers.sh.tmpl`
- Create: `home/.chezmoiscripts/darwin/run_onchange_after_20-runtimes.sh.tmpl`
- Create: `home/.chezmoiscripts/darwin/run_onchange_after_30-global-tools.sh.tmpl`
- Modify: `home/.chezmoidata/versions.toml` (`[cargo_tools]` and `[uv_tools]` entries)

**Interfaces:**
- Consumes: `.versions.*`, `.corepack_globals`, `.uv_tools`, `.cargo_tools`, `.go_tools`, `.versions_mode`, and the `nvm-load.sh` template fragment.

- [ ] **Step 1: Add the agreed tools to `versions.toml`**

Under `[uv_tools]` add `"pyclean"` if not already present (it is). Under `[cargo_tools]`, which is empty, add:

```toml
"cargo-audit" = "0.22.2"
"cargo-deny" = "0.20.2"
"just" = "1.57.0"
```

These are the versions `cargo install --list` reported on this Mac on 2026-09-05. The pins apply to Linux too, which is intended.

- [ ] **Step 2: Create `darwin/run_once_after_10-runtime-managers.sh.tmpl`**

```bash
{{ if eq .chezmoi.os "darwin" -}}
#!/usr/bin/env bash
# Install runtime MANAGERS on macOS: nvm and rustup via their upstream
# installers; uv, bun, and Go come from Homebrew (00-packages) and are only
# checked here. Mirrors linux/10-runtime-managers.
set -euo pipefail

echo "==> Runtime managers ({{ .versions_mode }} mode)..."

# --- nvm ---
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ ! -r "$NVM_DIR/nvm.sh" ]; then
{{- if eq .versions_mode "pinned" }}
    PROFILE=/dev/null bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/{{ .versions.nvm }}/install.sh | PROFILE=/dev/null bash"
{{- else }}
    latest_nvm=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -om1 '"tag_name": *"[^"]*"' | cut -d'"' -f4)
    PROFILE=/dev/null bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${latest_nvm}/install.sh | PROFILE=/dev/null bash"
{{- end }}
else
    echo "    nvm already present; keeping it."
fi

# --- rustup ---
if ! command -v rustup &>/dev/null && [ ! -x "$HOME/.cargo/bin/rustup" ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
else
    echo "    rustup already present."
fi

# --- uv, bun, Go (Homebrew) ---
for tool in uv bun go; do
    if command -v "$tool" &>/dev/null; then
        echo "    $tool present: $("$tool" --version 2>/dev/null | head -n1)"
    else
        echo "    WARNING: $tool missing; 00-packages should have installed it via Homebrew." >&2
    fi
done

echo "==> Runtime managers done."
{{ end -}}
```

- [ ] **Step 3: Create `darwin/run_onchange_after_20-runtimes.sh.tmpl`**

Copy `home/.chezmoiscripts/linux/run_onchange_after_20-runtimes.sh.tmpl` verbatim and change only line 1 from `{{ if eq .chezmoi.os "linux" -}}` to `{{ if eq .chezmoi.os "darwin" -}}` and line 2 to `#!/usr/bin/env bash`. Every step inside (nvm install, uv python install, rustup toolchain install) is platform-neutral.

- [ ] **Step 4: Create `darwin/run_onchange_after_30-global-tools.sh.tmpl`**

Copy `home/.chezmoiscripts/linux/run_onchange_after_30-global-tools.sh.tmpl` verbatim, then make exactly these edits:
1. Line 1: `{{ if eq .chezmoi.os "darwin" -}}`; line 2: `#!/usr/bin/env bash`.
2. Replace the whole `# --- podman (Ubuntu repository package) ---` block (from that comment through its closing `fi`) with:

```bash
# --- Docker Desktop provides the daemon on macOS; the docker CLI comes from Homebrew ---
if command -v docker &>/dev/null; then
    echo "    docker CLI present: $(docker --version)"
else
    failed+=(docker-missing)
fi
```

- [ ] **Step 5: Verify**

```bash
scripts/render-check.sh personal pinned && scripts/render-check.sh personal latest
c=(chezmoi --config "$(scripts/scratch-init.sh personal pinned)" --source "$PWD" --destination "$(mktemp -d)")
for s in 10-runtime-managers 20-runtimes 30-global-tools; do
  "${c[@]}" execute-template < "home/.chezmoiscripts/darwin/run_on*_after_${s}.sh.tmpl" > "/tmp/darwin-$s.sh"
  bash -n "/tmp/darwin-$s.sh" && shellcheck -S warning "/tmp/darwin-$s.sh" && echo "$s lint ok"
done
grep -c 'cargo install --locked' /tmp/darwin-30-global-tools.sh
diff <(sed '1,2d' home/.chezmoiscripts/linux/run_onchange_after_20-runtimes.sh.tmpl) <(sed '1,2d' home/.chezmoiscripts/darwin/run_onchange_after_20-runtimes.sh.tmpl) && echo "20-runtimes identical below the guard"
"${c[@]}" managed | grep -c '^.chezmoiscripts/darwin/'
```

Expected: both `OK` lines, three `lint ok` lines, cargo count `3`, `20-runtimes identical below the guard`, and darwin script count `5` (00, 10, 20, 30, plus 10-terminal-font).

- [ ] **Step 6: Commit**

```bash
git add home/.chezmoiscripts/darwin/ home/.chezmoidata/versions.toml
git commit -m "darwin: runtime managers, runtimes, and global tools mirroring the linux scripts"
```

---

### Task 13: Docs and macOS rollout (stops for approval before apply)

**Files:**
- Modify: `CLAUDE.md` (Key files table rows for the three new darwin scripts and the packages.toml row)
- Modify: `README.md` (package data paragraph near line 86, tree near line 195)
- Modify: `docs/macos.md` (what the bootstrap installs)

- [ ] **Step 1: CLAUDE.md**

Replace the `darwin/run_once_before_00-packages.sh.tmpl` row's notes with: `macOS bootstrap: Homebrew, then every formula and cask in packages.toml [packages.darwin], TPM, VS Code extensions`. Add rows:

```
| `home/.chezmoiscripts/darwin/run_once_after_10-runtime-managers.sh.tmpl` | (run script) | nvm and rustup via upstream installers; verifies uv, bun, Go from Homebrew |
| `home/.chezmoiscripts/darwin/run_onchange_after_20-runtimes.sh.tmpl` | (run script) | Identical to the linux script below the OS guard: pinned Node, uv Pythons, Rust toolchain |
| `home/.chezmoiscripts/darwin/run_onchange_after_30-global-tools.sh.tmpl` | (run script) | codex, claude, corepack pnpm/yarn, uv tools, cargo tools, go tools; docker CLI check instead of podman |
```

Change the `packages.toml` row to: `[packages.darwin] brew/cask lists installed by the macOS bootstrap; apt list is still manual reference; vscode_extensions is the canonical set for every platform`.

- [ ] **Step 2: README.md**

Replace the sentence starting `Reference lists that stay manual:` with: `` `home/.chezmoidata/packages.toml` drives the macOS Homebrew install and holds the canonical VS Code extension list; its apt list is still a manual reference pending a scripted Linux install. `` Update the tree comment for `packages.toml` to `# brew/cask lists (darwin), apt reference, VS Code extension IDs`.

- [ ] **Step 3: docs/macos.md**

Replace the list of what the bootstrap installs with a pointer: `See [packages.toml](../home/.chezmoidata/packages.toml) under [packages.darwin] for the exact formula and cask set; runtime managers and global tools follow the same versions.toml pins as Linux.`

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md docs/macos.md
git commit -m "docs: describe the data-driven macOS bootstrap and runtime scripts"
```

- [ ] **Step 5: Preview on this Mac**

```bash
for r in personal work both; do scripts/render-check.sh "$r" pinned || exit 1; done; echo ALL OK
chezmoi status
chezmoi diff --no-pager --include=scripts | grep '^diff --git'
```

Expected: `ALL OK`. Four darwin scripts show as pending (00 changed, 10/20/30 new). No file targets change, since Part 1 already applied them.

Dry-run what 00-packages would actually install on this machine without running it:

```bash
chezmoi cat ~/.chezmoiscripts/darwin/00-packages.sh 2>/dev/null || chezmoi execute-template < home/.chezmoiscripts/darwin/run_once_before_00-packages.sh.tmpl > /tmp/d00.sh
for f in $(grep -oE '^    "[^"]+"' /tmp/d00.sh | tr -d ' "' | grep -v '\.'); do brew list --formula "${f##*/}" &>/dev/null || brew list --cask "$f" &>/dev/null || echo "would install: $f"; done
```

Expected on this Mac, based on the 2026-09-05 inventory: `would install:` lines for `fd`, `bun`, `docker-desktop`, `claude`, `dbeaver-community`, `google-chrome`, `obsidian`, `ollama-app`, `visual-studio-code`. Casks for apps already installed outside Homebrew (VS Code, Docker Desktop, DBeaver, Chrome, Obsidian, Claude, Ollama) will make brew adopt or refuse them; if brew refuses with `already an App at /Applications/...`, run once by hand with `brew install --cask --adopt <name>` for those, then re-run apply.

- [ ] **Step 6: STOP. Show the pending script list and the would-install list to the user and wait for approval.**

When approved:

```bash
chezmoi apply -v
exec zsh -l
for t in bat fd jq rg tree htop shellcheck gitleaks lefthook uv bun go docker claude codex gopls just cargo-audit cargo-deny pyclean; do printf '%-12s %s\n' "$t" "$(command -v "$t" || echo MISSING)"; done
code --list-extensions | wc -l
```

Expected: no `MISSING`, extension count at least 71.

- [ ] **Step 7: Merge**

```bash
git switch main && git merge --ff-only feat/darwin-packages && git push
```

---

## Self-review

**Part 2 coverage.** The 2026-09-05 agreed package set: brew formulae and casks in Task 11 (installed by the rewritten bootstrap), runtime managers and global tools in Task 12 (three darwin siblings of the linux scripts, cargo pins added to versions.toml), VS Code extension merge in Task 11, docs and gated rollout in Task 13. Excluded items are listed in the Part 2 header so they are not re-added by accident.

**Spec coverage.** Finding 1 (osrelease crash): Tasks 2 and 3. Finding 2 (unconditional tokens): Tasks 2 and 5. Finding 3 (work content and hardcoded paths): Tasks 3, 5, 6, with the leak check in Task 1 enforcing it. Finding 4 (trust roots): Task 5. Finding 5 (tmux script guard): Task 7. Finding 6 (duplicated bw wrapper, one plain `claude` alias, no agent-brain): Task 6, enforced by the leak check in Task 1. Finding 7 (VS Code only, versions default): Tasks 2 and 6, plus the local config fix in Task 10 Step 3. Finding 8 (CI on macOS): Tasks 1 and 8. Finding 9 (repo status line is the active one): Task 1 harness checks plus Task 10 Step 5 verification. Docs: Task 9. Safe rollout: Task 10.

**Known assumptions.**
- Codex trust for a parent directory applies to repositories beneath it. Task 10 Step 5 verifies this and records the fallback.
- The Codex `trusted_hash` for the prompt hook is only guaranteed valid on the original work Linux machine where the rendered path is unchanged; other work machines may be asked once to trust the hook.
- Codex full access (`danger-full-access`, `approval_policy = "never"`) is the managed default on every role as of 2026-09-06.
- `chezmoi init` with no repository argument only regenerates the config file; it never applies.
- `--promptChoice` / `--promptString` / `--promptInt` are keyed on prompt text and split on commas. Verified against chezmoi v2.70.3 on 2026-09-03: keying on the data field name silently falls through to a TTY prompt. Any change to a prompt string in `.chezmoi.toml.tmpl` must be mirrored in `scripts/scratch-init.sh`.

**Simulation of the finished plan.** On 2026-09-03 the plan's template changes were applied to a scratch copy of `home/` and `chezmoi diff` was run from that copy against the real Mac home directory with `machine_role=personal`. Status rendered without errors, no work, Cursor, agent-brain, or `/home/sabossedgh` content appeared in any rendered target, and the resulting per-file diff is recorded in the conversation of that date. The expected-diff list in Task 10 Step 4 matches that simulation.
