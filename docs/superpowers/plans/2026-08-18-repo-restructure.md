# Dotfiles Repo Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the chezmoi source state into a `home/` deploy boundary (`.chezmoiroot`), group scripts by platform under `.chezmoiscripts/`, extract the duplicated nvm preamble, convert the package/extension lists to data, and add CI — with provably unchanged deployment.

**Architecture:** Pure re-shaping of an existing chezmoi repo. `git mv` everything deployable into `home/`; chezmoi behavior is pinned by snapshot comparison (`chezmoi managed` + rendered content of every file target) taken before and after. Scripts change path (allowed; `run_onchange` re-run is accepted) but every *file* target must render byte-identically.

**Tech Stack:** chezmoi 2.70+, bash, git, GitHub Actions, shellcheck, gitleaks.

**Spec:** `docs/superpowers/specs/2026-08-18-repo-restructure-design.md`

## Global Constraints

- Repo: `/home/sabossedgh/dev/dotfiles` (public GitHub: `Sawmonabo/dotfiles`). All commands run from this directory unless stated.
- **NEVER run `chezmoi apply` on this machine** (frozen migration source). Only `status`, `diff`, `managed`, `cat`, `execute-template`.
- Every move uses `git mv` (history preservation).
- No real secrets may enter the repo: before every commit in this plan, `grep -rE 'ATATT|glpat-' --exclude-dir=.git .` must output nothing.
- Work on branch `restructure`; merge to `main` only after Task 7's gate passes.
- Snapshot dir for verification artifacts: `/tmp/restructure-check/` (not committed).

---

### Task 1: Branch and baseline snapshots

**Files:**
- Create: `/tmp/restructure-check/before.managed`, `/tmp/restructure-check/before.files` (not committed)

**Interfaces:**
- Produces: baseline snapshots consumed by Tasks 2, 3, and 7. `before.managed` = sorted list of managed target paths. `before.files` = concatenated rendered content of every managed *file* target, delimited by `=== <path> ===` headers.

- [ ] **Step 1: Create branch**

```bash
cd /home/sabossedgh/dev/dotfiles
git checkout -b restructure
```

- [ ] **Step 2: Snapshot the managed set**

```bash
mkdir -p /tmp/restructure-check
chezmoi managed | LC_ALL=C sort > /tmp/restructure-check/before.managed
wc -l /tmp/restructure-check/before.managed
```
Expected: ~20 lines (dirs + files), no error output.

- [ ] **Step 3: Snapshot rendered content of every file target**

```bash
chezmoi managed --include=files | LC_ALL=C sort | while IFS= read -r t; do
  printf '=== %s ===\n' "$t"
  chezmoi cat "$HOME/$t"
done > /tmp/restructure-check/before.files
wc -l /tmp/restructure-check/before.files
```
Expected: several hundred lines; exit 0. If `chezmoi cat` errors on any target, STOP — the working tree is broken; fix before restructuring.

- [ ] **Step 4: Verify baseline is reproducible (run Step 3 again, compare)**

```bash
chezmoi managed --include=files | LC_ALL=C sort | while IFS= read -r t; do
  printf '=== %s ===\n' "$t"
  chezmoi cat "$HOME/$t"
done > /tmp/restructure-check/before.files.2
diff /tmp/restructure-check/before.files /tmp/restructure-check/before.files.2 && echo REPRODUCIBLE
```
Expected: `REPRODUCIBLE`.

---

### Task 2: Introduce `.chezmoiroot` and move deployable state into `home/`

**Files:**
- Create: `.chezmoiroot`
- Move (git mv, same basename, new dir `home/`): `.chezmoi.toml.tmpl`, `.chezmoiignore`, `.chezmoidata/`, `private_dot_bashrc.tmpl`, `dot_zshrc.tmpl`, `dot_gitconfig.tmpl`, `dot_gitconfig-personal.tmpl`, `dot_claude/`, `dot_codex/`, `dot_config/`
- Modify: `home/.chezmoiignore` (delete the `CLAUDE.md`, `README.md`, `docs/` lines)

**Interfaces:**
- Consumes: Task 1 snapshots.
- Produces: `home/` as the chezmoi source root. All later tasks place source files under `home/`.

- [ ] **Step 1: Create `.chezmoiroot`**

```bash
printf 'home\n' > .chezmoiroot
```

- [ ] **Step 2: Move state (scripts move in Task 3, not here)**

```bash
mkdir -p home
git mv .chezmoi.toml.tmpl .chezmoiignore .chezmoidata home/
git mv private_dot_bashrc.tmpl dot_zshrc.tmpl dot_gitconfig.tmpl dot_gitconfig-personal.tmpl home/
git mv dot_claude dot_codex dot_config home/
git mv run_once_before_install-packages-linux.sh.tmpl home/ 2>/dev/null || true
git mv run_once_before_install-packages-darwin.sh.tmpl home/
git mv run_once_before_install-packages-windows.sh.tmpl home/
git mv run_once_after_10-install-runtime-managers.sh.tmpl home/
git mv run_onchange_after_20-install-runtimes.sh.tmpl home/
git mv run_onchange_after_30-install-global-tools.sh.tmpl home/
git mv run_onchange_install-tmux-plugins.sh.tmpl home/
git mv run_onchange_deploy-wsl-windows-configs.sh.tmpl home/
git mv run_onchange_configure-cursor-terminal-font.sh.tmpl home/
git mv run_onchange_configure-terminal-font-darwin.sh.tmpl home/
```
(The scripts move into `home/` now so the source stays valid between Tasks 2 and 3; Task 3 relocates them within `home/`. The first mv has `|| true` only because a re-run of this step after partial completion must not abort.)

- [ ] **Step 3: Prune now-redundant ignore entries**

Edit `home/.chezmoiignore` to exactly:

```
{{ if ne .chezmoi.os "linux" }}
.bashrc
{{ end }}

{{ if ne .chezmoi.os "darwin" }}
.zshrc
{{ end }}
```

- [ ] **Step 4: Verify the managed set is unchanged**

```bash
chezmoi managed | LC_ALL=C sort > /tmp/restructure-check/after-task2.managed
diff /tmp/restructure-check/before.managed /tmp/restructure-check/after-task2.managed && echo MANAGED-IDENTICAL
```
Expected: `MANAGED-IDENTICAL`. If `CLAUDE.md`, `README.md`, or `docs` appear as additions, the ignore prune in Step 3 is wrong — those files now live OUTSIDE `home/` and must not be listed as managed at all; investigate before continuing.

- [ ] **Step 5: Verify all file targets render byte-identically**

```bash
chezmoi managed --include=files | LC_ALL=C sort | while IFS= read -r t; do
  printf '=== %s ===\n' "$t"
  chezmoi cat "$HOME/$t"
done > /tmp/restructure-check/after-task2.files
diff /tmp/restructure-check/before.files /tmp/restructure-check/after-task2.files && echo CONTENT-IDENTICAL
```
Expected: `CONTENT-IDENTICAL`.

- [ ] **Step 6: Commit**

```bash
grep -rE 'ATATT|glpat-' --exclude-dir=.git . || git commit -am "refactor: move chezmoi source state under home/ via .chezmoiroot"
```

---

### Task 3: Relocate scripts into `.chezmoiscripts/<platform>/` with phase-numbered names

**Files (git mv, exact old → new):**

| From (`home/`) | To (`home/.chezmoiscripts/`) |
|---|---|
| `run_once_before_install-packages-linux.sh.tmpl` | `linux/run_once_before_00-packages.sh.tmpl` |
| `run_once_after_10-install-runtime-managers.sh.tmpl` | `linux/run_once_after_10-runtime-managers.sh.tmpl` |
| `run_onchange_after_20-install-runtimes.sh.tmpl` | `linux/run_onchange_after_20-runtimes.sh.tmpl` |
| `run_onchange_after_30-install-global-tools.sh.tmpl` | `linux/run_onchange_after_30-global-tools.sh.tmpl` |
| `run_onchange_install-tmux-plugins.sh.tmpl` | `linux/run_onchange_after_40-tmux-plugins.sh.tmpl` |
| `run_once_before_install-packages-darwin.sh.tmpl` | `darwin/run_once_before_00-packages.sh.tmpl` |
| `run_onchange_configure-terminal-font-darwin.sh.tmpl` | `darwin/run_onchange_after_10-terminal-font.sh.tmpl` |
| `run_once_before_install-packages-windows.sh.tmpl` | `wsl/run_once_before_00-packages-windows.sh.tmpl` |
| `run_onchange_deploy-wsl-windows-configs.sh.tmpl` | `wsl/run_onchange_after_10-deploy-windows-configs.sh.tmpl` |
| `run_onchange_configure-cursor-terminal-font.sh.tmpl` | `wsl/run_onchange_after_20-cursor-terminal-font.sh.tmpl` |

**Interfaces:**
- Consumes: `home/` layout from Task 2.
- Produces: final script paths; Task 4 modifies `linux/run_onchange_after_20-runtimes.sh.tmpl` and `linux/run_onchange_after_30-global-tools.sh.tmpl` at these locations.

- [ ] **Step 1: Move and rename**

```bash
cd /home/sabossedgh/dev/dotfiles/home
mkdir -p .chezmoiscripts/linux .chezmoiscripts/darwin .chezmoiscripts/wsl
git mv run_once_before_install-packages-linux.sh.tmpl        .chezmoiscripts/linux/run_once_before_00-packages.sh.tmpl
git mv run_once_after_10-install-runtime-managers.sh.tmpl    .chezmoiscripts/linux/run_once_after_10-runtime-managers.sh.tmpl
git mv run_onchange_after_20-install-runtimes.sh.tmpl        .chezmoiscripts/linux/run_onchange_after_20-runtimes.sh.tmpl
git mv run_onchange_after_30-install-global-tools.sh.tmpl    .chezmoiscripts/linux/run_onchange_after_30-global-tools.sh.tmpl
git mv run_onchange_install-tmux-plugins.sh.tmpl             .chezmoiscripts/linux/run_onchange_after_40-tmux-plugins.sh.tmpl
git mv run_once_before_install-packages-darwin.sh.tmpl       .chezmoiscripts/darwin/run_once_before_00-packages.sh.tmpl
git mv run_onchange_configure-terminal-font-darwin.sh.tmpl   .chezmoiscripts/darwin/run_onchange_after_10-terminal-font.sh.tmpl
git mv run_once_before_install-packages-windows.sh.tmpl      .chezmoiscripts/wsl/run_once_before_00-packages-windows.sh.tmpl
git mv run_onchange_deploy-wsl-windows-configs.sh.tmpl       .chezmoiscripts/wsl/run_onchange_after_10-deploy-windows-configs.sh.tmpl
git mv run_onchange_configure-cursor-terminal-font.sh.tmpl   .chezmoiscripts/wsl/run_onchange_after_20-cursor-terminal-font.sh.tmpl
cd ..
```

- [ ] **Step 2: Verify file targets still render identically and scripts are queued**

```bash
chezmoi managed --include=files | LC_ALL=C sort | while IFS= read -r t; do
  printf '=== %s ===\n' "$t"
  chezmoi cat "$HOME/$t"
done > /tmp/restructure-check/after-task3.files
diff /tmp/restructure-check/before.files /tmp/restructure-check/after-task3.files && echo CONTENT-IDENTICAL
chezmoi status | awk '$1=="R"{print $2}'
```
Expected: `CONTENT-IDENTICAL`, and the R-list shows the ten NEW script names (e.g. `00-packages.sh`, `10-runtime-managers.sh`) with no old names. `run_onchange` scripts re-running under new names is the accepted trade-off (spec §7); do NOT run them.

- [ ] **Step 3: Verify every script still renders and lints**

```bash
for f in home/.chezmoiscripts/*/*.tmpl; do
  out="/tmp/restructure-check/$(basename "${f%.tmpl}")"
  chezmoi execute-template < "$f" > "$out"
  [ -s "$out" ] || { echo "  (empty render — other-OS script) $f"; continue; }
  bash -n "$out" && shellcheck -S warning "$out" && echo "OK: $f"
done
```
Expected: `OK:` for every linux + wsl script; darwin scripts report empty render (this machine is linux/WSL, so darwin templates render empty — that is correct).

- [ ] **Step 4: Commit**

```bash
grep -rE 'ATATT|glpat-' --exclude-dir=.git . || git commit -am "refactor: platform-grouped, phase-numbered scripts in .chezmoiscripts/"
```

---

### Task 4: Extract the `nvm-load.sh` fragment

**Files:**
- Create: `home/.chezmoitemplates/nvm-load.sh`
- Modify: `home/.chezmoiscripts/linux/run_onchange_after_20-runtimes.sh.tmpl`
- Modify: `home/.chezmoiscripts/linux/run_onchange_after_30-global-tools.sh.tmpl`
- Modify: `docs/superpowers/specs/2026-08-18-repo-restructure-design.md` (fragment section correction)

**Interfaces:**
- Consumes: script paths from Task 3.
- Produces: `{{ template "nvm-load.sh" }}` emitting exactly three lines (below). Any future Node-dependent script uses the same include.

Both scripts contain this exact three-line run (script 20 at its line 11, script 30 at its line 13, verified 2026-08-18):

```bash
if [ -r "$NVM_DIR/nvm.sh" ]; then
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
```

The fragment reproduces those bytes exactly, so rendered output cannot change. The spec's second fragment (`backup-file.sh`) is dropped: the two backup blocks differ in indentation and an echo line, so extraction would change rendered bytes and break the Task 7 gate for a two-use "DRY" win. Spec is amended in Step 4.

- [ ] **Step 1: Create the fragment (exact content, no trailing newline issues — use printf)**

```bash
printf '%s\n%s\n%s' \
  'if [ -r "$NVM_DIR/nvm.sh" ]; then' \
  '    # shellcheck source=/dev/null' \
  '    source "$NVM_DIR/nvm.sh"' \
  > home/.chezmoitemplates/nvm-load.sh
```
(Create the directory first: `mkdir -p home/.chezmoitemplates`.)

- [ ] **Step 2: Replace the three lines in both consumers**

In each of `run_onchange_after_20-runtimes.sh.tmpl` and `run_onchange_after_30-global-tools.sh.tmpl`, replace the three lines shown above with the single line:

```
{{ template "nvm-load.sh" }}
```

```bash
python3 - <<'PY'
import re
block = ('if [ -r "$NVM_DIR/nvm.sh" ]; then\n'
         '    # shellcheck source=/dev/null\n'
         '    source "$NVM_DIR/nvm.sh"\n')
for p in ['home/.chezmoiscripts/linux/run_onchange_after_20-runtimes.sh.tmpl',
          'home/.chezmoiscripts/linux/run_onchange_after_30-global-tools.sh.tmpl']:
    s = open(p).read()
    assert s.count(block) == 1, (p, s.count(block))
    open(p, 'w').write(s.replace(block, '{{ template "nvm-load.sh" }}\n'))
print("replaced in both")
PY
```
Expected: `replaced in both`. An assertion error means the block drifted — STOP and re-read the file rather than forcing the replace.

- [ ] **Step 3: Verify renders are byte-identical to the Task 3 snapshots**

```bash
for n in 20-runtimes 30-global-tools; do
  f="home/.chezmoiscripts/linux/run_onchange_after_${n}.sh.tmpl"
  chezmoi execute-template < "$f" > "/tmp/restructure-check/frag-${n}"
  diff "/tmp/restructure-check/run_onchange_after_${n}.sh" "/tmp/restructure-check/frag-${n}" \
    && echo "BYTE-IDENTICAL: $n"
done
```
Expected: `BYTE-IDENTICAL` twice. (The Task 3 Step 3 loop left renders named `run_onchange_after_20-runtimes.sh` etc. in `/tmp/restructure-check/`.)

- [ ] **Step 4: Amend the spec's fragment section**

In `docs/superpowers/specs/2026-08-18-repo-restructure-design.md`, replace the two-bullet "Fragment extraction" list with:

```markdown
- `nvm-load.sh`: the exact three-line nvm guard+source block shared by the
  runtimes and global-tools scripts, consumed via `{{ template "nvm-load.sh" }}`.
- `backup-file.sh` (originally planned) is dropped: the two backup blocks
  differ in indentation and messaging, so extraction would change rendered
  bytes; duplication of two nearly-identical guards is cheaper than a
  parameterized template.
```
Also delete the `backup-file.sh` line from the §3 layout tree.

- [ ] **Step 5: Commit**

```bash
grep -rE 'ATATT|glpat-' --exclude-dir=.git . || git commit -am "refactor: extract shared nvm-load template fragment (byte-identical renders)"
```

---

### Task 5: Convert package/extension lists to data

**Files:**
- Create: `home/.chezmoidata/packages.toml`
- Delete (git rm): `docs/apt-packages.txt`, `docs/vscode-extensions.txt`
- Modify: `README.md` (the paragraph referencing the two docs files)

**Interfaces:**
- Consumes: the two existing docs lists (79 apt names, 54 extension IDs).
- Produces: chezmoi data keys `.packages.apt` (list of strings) and `.packages.vscode_extensions` (list of strings), available to any future template.

- [ ] **Step 1: Generate packages.toml from the existing lists**

```bash
python3 - <<'PY'
apt = [l.strip() for l in open('docs/apt-packages.txt') if l.strip()]
ext = [l.strip() for l in open('docs/vscode-extensions.txt') if l.strip()]
with open('home/.chezmoidata/packages.toml', 'w') as f:
    f.write('# Manually-consumed reference data (see README): apt packages recorded on\n')
    f.write('# the 2026-08-17 inventory, and VS Code extension IDs. Scriptable later.\n')
    f.write('[packages]\n')
    f.write('apt = [\n' + ''.join(f'  "{p}",\n' for p in apt) + ']\n')
    f.write('vscode_extensions = [\n' + ''.join(f'  "{e}",\n' for e in ext) + ']\n')
print(len(apt), len(ext))
PY
```
Expected output: `79 54`.

- [ ] **Step 2: Verify chezmoi parses the data**

```bash
chezmoi execute-template '{{ len .packages.apt }} {{ len .packages.vscode_extensions }}'
```
Expected: `79 54`. A TOML syntax error here fails loudly — fix before continuing.

- [ ] **Step 3: Remove the docs copies and update README**

```bash
git rm -q docs/apt-packages.txt docs/vscode-extensions.txt
```

In `README.md`, replace the sentence that references `docs/apt-packages.txt` and `docs/vscode-extensions.txt` with:

```markdown
Reference lists that stay manual: `home/.chezmoidata/packages.toml` holds the
recorded apt package names (need sudo + per-release availability review) and
VS Code extension IDs (need the Windows `code` command).
```

- [ ] **Step 4: Commit**

```bash
grep -rE 'ATATT|glpat-' --exclude-dir=.git . || git commit -am "refactor: package/extension lists as chezmoi data (packages.toml)"
```

---

### Task 6: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the `home/` layout; renders templates with synthetic prompt data for both `versions_mode` values.
- Produces: a required green check for Task 7's gate.

- [ ] **Step 1: Write the workflow**

```yaml
name: ci
on:
  push: {branches: [main, restructure]}
  pull_request:
permissions:
  contents: read
jobs:
  render-and-lint:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        versions_mode: [pinned, latest]
    steps:
      - uses: actions/checkout@v4
      - name: Install chezmoi and shellcheck
        run: |
          sudo apt-get update -q && sudo apt-get install -y shellcheck
          sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"
      - name: Synthetic chezmoi config (no prompts, no secrets)
        run: |
          mkdir -p "$HOME/.config/chezmoi"
          cat > "$HOME/.config/chezmoi/chezmoi.toml" <<EOF
          [data]
              name = "CI User"
              email = "ci@example.invalid"
              personal_email = "ci-personal@example.invalid"
              editor = "code"
              versions_mode = "${{ matrix.versions_mode }}"
              wsl_memory = "8GB"
              restart_wsl_path = "Desktop/RestartWSL"
              jira_api_token = "ci-placeholder"
              gitlab_token = "ci-placeholder"
          EOF
      - name: Render every template, lint every non-empty script
        run: |
          set -euo pipefail
          fail=0
          while IFS= read -r -d '' f; do
            out=$(mktemp)
            if ! chezmoi --source "$PWD" execute-template < "$f" > "$out"; then
              echo "RENDER FAIL: $f"; fail=1; continue
            fi
            case "$f" in
              *.sh.tmpl)
                if [ -s "$out" ]; then
                  bash -n "$out" || { echo "SYNTAX FAIL: $f"; fail=1; }
                  shellcheck -S warning "$out" || { echo "SHELLCHECK FAIL: $f"; fail=1; }
                fi ;;
            esac
          done < <(find home -name '*.tmpl' -print0)
          exit "$fail"
  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: {fetch-depth: 0}
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Notes for the implementer:
- The CI runner's kernel is not Microsoft, so `wsl/` script templates render empty and are skipped by the `[ -s "$out" ]` check — per spec §5/§7.
- `chezmoi --source "$PWD"` honors `.chezmoiroot`, so `home/` resolves automatically.
- `darwin/` scripts also render empty on ubuntu; same skip applies.

- [ ] **Step 2: Reproduce the render job locally before pushing**

```bash
bash -n <(sed -n '/Render every template/,/exit "\$fail"/p' .github/workflows/ci.yml | sed '1,2d')  # sanity only
while IFS= read -r -d '' f; do
  out=$(mktemp)
  chezmoi --source "$PWD" execute-template < "$f" > "$out" || { echo "RENDER FAIL: $f"; }
  case "$f" in *.sh.tmpl) [ -s "$out" ] && { bash -n "$out" && shellcheck -S warning "$out" || echo "LINT FAIL: $f"; } ;; esac
done < <(find home -name '*.tmpl' -print0); echo LOCAL-CI-DONE
```
Expected: `LOCAL-CI-DONE` with no `FAIL` lines. (Local run uses the real local config — that is fine; CI proves the synthetic-data path.)

- [ ] **Step 3: Commit and push the branch**

```bash
grep -rE 'ATATT|glpat-' --exclude-dir=.git . || git commit -am "ci: render + lint templates in both version modes; gitleaks secret scan"
git push -u origin restructure
```

- [ ] **Step 4: Confirm CI is green**

```bash
gh run watch --repo Sawmonabo/dotfiles $(gh run list --repo Sawmonabo/dotfiles --branch restructure --limit 1 --json databaseId -q '.[0].databaseId') --exit-status && echo CI-GREEN
```
Expected: `CI-GREEN`. If gitleaks flags anything, treat it as real until proven otherwise — do NOT merge with a red scan.

---

### Task 7: Final gate and merge

**Files:** none (verification + merge only)

**Interfaces:**
- Consumes: Task 1 baseline, all prior commits, green CI.

- [ ] **Step 1: Full managed-set and content comparison against the Task 1 baseline**

```bash
chezmoi managed | LC_ALL=C sort > /tmp/restructure-check/final.managed
diff /tmp/restructure-check/before.managed /tmp/restructure-check/final.managed && echo MANAGED-IDENTICAL
chezmoi managed --include=files | LC_ALL=C sort | while IFS= read -r t; do
  printf '=== %s ===\n' "$t"
  chezmoi cat "$HOME/$t"
done > /tmp/restructure-check/final.files
diff /tmp/restructure-check/before.files /tmp/restructure-check/final.files && echo CONTENT-IDENTICAL
```
Expected: both `MANAGED-IDENTICAL` and `CONTENT-IDENTICAL`. Any diff is a gate failure: find the task that introduced it and fix there. Do not rationalize a diff as acceptable — file targets have zero tolerance (spec §6).

- [ ] **Step 2: Confirm `chezmoi status` is error-free and R-list contains only expected scripts**

```bash
chezmoi status; echo "exit=$?"
```
Expected: exit=0; rows are only ` R` script entries (new names) plus the same `M`/`A` rows present before the restructure (`.gitconfig` coderabbit strip, tmux `A` — unchanged carryovers), nothing new.

- [ ] **Step 3: Merge and push**

```bash
git checkout main
git merge --no-ff restructure -m "refactor: restructure repo — home/ deploy boundary, platform scripts, data lists, CI"
git push origin main
git branch -d restructure
git push origin --delete restructure
```

- [ ] **Step 4: Confirm main CI green and post-merge sanity**

```bash
gh run watch --repo Sawmonabo/dotfiles $(gh run list --repo Sawmonabo/dotfiles --branch main --limit 1 --json databaseId -q '.[0].databaseId') --exit-status && echo MAIN-CI-GREEN
chezmoi status >/dev/null && echo CHEZMOI-OK
```
Expected: `MAIN-CI-GREEN`, `CHEZMOI-OK`.
