# Dotfiles Repo Restructure — Design Spec

**Date:** 2026-08-18
**Status:** Approved in discussion; pending spec review
**Scope:** Repository shape only. No behavior change: every file must deploy to the same target with the same content and mode as before.

## 1. Problem

The repo root interleaves three unrelated concerns:

1. **Deployable state** (`dot_*`, `private_*`, `.chezmoi.toml.tmpl`) — mirrors `~`
2. **Executable pipeline** (9 `run_once_*` / `run_onchange_*` scripts) — flat, mixed platforms, two naming schemes (`install-packages-linux` vs `10-install-runtime-managers`)
3. **Project scaffolding** (`README.md`, `CLAUDE.md`, `docs/`) — must be *excluded* from deployment via `.chezmoiignore`

Because the source root doubles as the deploy root, every non-deployable file is a bug waiting to happen: the repo's own `CLAUDE.md` deployed to `~/CLAUDE.md` until 2026-08-18 (commit history: fixed by adding an ignore entry). Shared logic is copy-pasted — the nvm-sourcing preamble appears 4×, backup-before-overwrite logic 2×. There is no CI; a template-key mismatch broke `chezmoi apply` silently from 2026-02 to 2026-08.

## 2. Goals / Non-Goals

**Goals**

- One unambiguous deploy boundary: nothing outside it can ever reach `~`.
- Scripts grouped by platform, ordered by numbered phase, one naming scheme.
- Shared template fragments extracted; no duplicated preamble logic.
- CI that renders every template (pinned *and* latest modes), syntax-checks and shellchecks the output, and scans for secrets.
- Byte-identical deployment before/after (provable via `chezmoi diff`).

**Non-Goals**

- No changes to what is managed, prompted, or installed.
- No per-machine/role data flags (`is_work`, `has_gui`) — YAGNI until a second machine profile exists.
- No secret-manager integration (tokens stay as local-only prompted values).
- No new platform support.

## 3. Target Layout

```
dotfiles/
├── README.md                        # user-facing: what + quick start
├── CLAUDE.md                        # repo dev docs (never deploys — outside home/)
├── docs/                            # platform guides (human-facing only)
│   └── superpowers/specs/           #   design specs (this file)
├── .github/workflows/ci.yml         # render + lint + secret-scan
├── .chezmoiroot                     # one line: "home"
└── home/                            # THE deploy boundary — mirrors ~
    ├── .chezmoi.toml.tmpl           # prompts: identity, versions_mode, wsl, tokens
    ├── .chezmoiignore               # OS gating only (bashrc/zshrc)
    ├── .chezmoidata/
    │   ├── versions.toml            # all pins (unchanged)
    │   └── packages.toml            # apt packages + VS Code extensions (data, not docs)
    ├── .chezmoitemplates/
    │   └── nvm-source.sh            # NVM_DIR export + source nvm.sh (used 4×)
    ├── .chezmoiscripts/
    │   ├── linux/
    │   │   ├── run_once_before_00-packages.sh.tmpl
    │   │   ├── run_once_after_10-runtime-managers.sh.tmpl
    │   │   ├── run_onchange_after_20-runtimes.sh.tmpl
    │   │   ├── run_onchange_after_30-global-tools.sh.tmpl
    │   │   └── run_onchange_after_40-tmux-plugins.sh.tmpl
    │   ├── darwin/
    │   │   ├── run_once_before_00-packages.sh.tmpl
    │   │   └── run_onchange_after_10-terminal-font.sh.tmpl
    │   └── wsl/
    │       ├── run_once_before_00-packages-windows.sh.tmpl
    │       ├── run_onchange_after_10-deploy-windows-configs.sh.tmpl
    │       └── run_onchange_after_20-cursor-terminal-font.sh.tmpl
    ├── private_dot_bashrc.tmpl
    ├── dot_zshrc.tmpl
    ├── dot_gitconfig.tmpl
    ├── dot_gitconfig-personal.tmpl
    ├── dot_claude/
    │   ├── CLAUDE.md
    │   └── private_settings.json
    ├── dot_codex/
    │   ├── AGENTS.md
    │   ├── private_config.toml.tmpl
    │   └── private_hooks.json
    └── dot_config/
        ├── oh-my-posh/catppuccin_mocha.omp.json
        └── tmux/tmux.conf
```

### Design principles

1. **Configs group by target path, not category.** `home/` is a 1:1 mirror of `~`; source location is derived mechanically from deploy location. Categorical folders (`shell/`, `ai-tools/`) are rejected: they break the mirror and add a mental mapping layer.
2. **Platform grouping lives only where platforms diverge in *action*:** `.chezmoiscripts/{linux,darwin,wsl}/`. `wsl/` is a repo convention, not a chezmoi OS (chezmoi reports `linux`); each wsl script keeps its template guard `(.chezmoi.kernel.osrelease | lower | contains "microsoft")`.
3. **Cross-OS mechanisms, each in its one right place:**
   - same file, different content → template conditionals in the file
   - file exists on one OS only → `.chezmoiignore` conditionals
   - different actions → platform script directories
4. **Script naming:** `run_{once|onchange}_{before|after}_NN-<verb-noun>.sh.tmpl`. `NN` orders within a directory; chezmoi orders scripts by path, so per-platform ordering is deterministic.

## 4. Migration Mapping

| Current (root) | Target |
|---|---|
| `.chezmoi.toml.tmpl`, `.chezmoiignore`, `.chezmoidata/` | `home/` (unchanged content, except ignore entries for `README.md`, `docs/`, `CLAUDE.md` are deleted — no longer needed) |
| `private_dot_bashrc.tmpl`, `dot_zshrc.tmpl`, `dot_gitconfig*.tmpl`, `dot_claude/`, `dot_codex/`, `dot_config/` | `home/<same name>` |
| `run_once_before_install-packages-linux.sh.tmpl` | `home/.chezmoiscripts/linux/run_once_before_00-packages.sh.tmpl` |
| `run_once_after_10-install-runtime-managers.sh.tmpl` | `home/.chezmoiscripts/linux/run_once_after_10-runtime-managers.sh.tmpl` |
| `run_onchange_after_20-install-runtimes.sh.tmpl` | `home/.chezmoiscripts/linux/run_onchange_after_20-runtimes.sh.tmpl` |
| `run_onchange_after_30-install-global-tools.sh.tmpl` | `home/.chezmoiscripts/linux/run_onchange_after_30-global-tools.sh.tmpl` |
| `run_onchange_install-tmux-plugins.sh.tmpl` | `home/.chezmoiscripts/linux/run_onchange_after_40-tmux-plugins.sh.tmpl` |
| `run_once_before_install-packages-darwin.sh.tmpl` | `home/.chezmoiscripts/darwin/run_once_before_00-packages.sh.tmpl` |
| `run_onchange_configure-terminal-font-darwin.sh.tmpl` | `home/.chezmoiscripts/darwin/run_onchange_after_10-terminal-font.sh.tmpl` |
| `run_once_before_install-packages-windows.sh.tmpl` | `home/.chezmoiscripts/wsl/run_once_before_00-packages-windows.sh.tmpl` |
| `run_onchange_deploy-wsl-windows-configs.sh.tmpl` | `home/.chezmoiscripts/wsl/run_onchange_after_10-deploy-windows-configs.sh.tmpl` |
| `run_onchange_configure-cursor-terminal-font.sh.tmpl` | `home/.chezmoiscripts/wsl/run_onchange_after_20-cursor-terminal-font.sh.tmpl` |
| `README.md`, `CLAUDE.md`, `docs/` | stay at repo root (now outside the deploy boundary by construction) |
| `docs/apt-packages.txt`, `docs/vscode-extensions.txt` | merged into `home/.chezmoidata/packages.toml` — they are input data, not documentation; README documents how to use them |
| — (new) | `.chezmoiroot`, `home/.chezmoitemplates/*`, `.github/workflows/ci.yml` |

All moves use `git mv` to preserve history.

### Fragment extraction

- `nvm-load.sh`: the exact three-line nvm guard+source block shared by the
  runtimes and global-tools scripts, consumed via `{{ template "nvm-load.sh" }}`.
- `backup-file.sh` (originally planned) is dropped: the two backup blocks
  differ in indentation and messaging, so extraction would change rendered
  bytes; duplication of two nearly-identical guards is cheaper than a
  parameterized template.

Fragments are extracted only where the code is duplicated today; no speculative fragments.

## 5. CI (`.github/workflows/ci.yml`)

Runs on push and pull request, ubuntu-latest:

1. **Render check:** install chezmoi; for each of `versions_mode = pinned` and `latest`, run `chezmoi init --dry-run` style rendering (`chezmoi execute-template` with a synthetic data file supplying all prompt values) over every `*.tmpl`. A template that fails to render fails the build. This catches the class of bug that broke apply from 2026-02 to 2026-08 (config/template key mismatch).
2. **Lint:** `bash -n` and `shellcheck -S warning` on every rendered script.
3. **Secret scan:** gitleaks with default rules over the full tree; fails on any real token pattern. (Template placeholders like `{{ .jira_api_token }}` do not match token patterns.)

CI renders with synthetic prompt values (e.g. `jira_api_token = "ci-placeholder"`); no real secrets exist in CI.

## 6. Verification Gate (must pass before merge)

On this machine, on the restructure branch:

1. `chezmoi status` and `chezmoi diff` run without error.
2. `chezmoi diff` output is **identical** before vs after the restructure (captured to files and compared), excluding only the script-path renames in the pending-scripts list.
3. `chezmoi managed` lists exactly the same targets before and after.
4. Full CI passes.

`chezmoi apply` is **not** run on this machine (frozen source for the laptop migration, runbook rule).

## 7. Trade-offs Accepted

- **`run_onchange` scripts re-run on rename** (state key includes target name). Acceptable: all are idempotent installers, and the next apply happens on the new laptop where they must run anyway. `run_once` state is content-hash keyed and unaffected by renames.
- **One-time migration cost** (~1–2 h) inside the laptop-migration window, mitigated by the empty-diff gate.
- **Deeper browse paths** (`home/dot_config/…`) — the price of a hard deploy boundary.
- **`wsl/` is convention, not enforcement** — a wsl script without its template guard would run on plain Linux. Mitigated by keeping guards in the scripts (unchanged from today) and CI rendering under a non-WSL kernel string, where wsl scripts must render empty.

## 8. Alternative Considered

**Minimal cleanup in place** — keep the flat root; add only CI and `.chezmoitemplates/`. Zero migration risk; chezmoi is indifferent to flat layouts. Rejected because the repo has changed character (from 16 passive configs to a data-driven install system), the flat root already produced a real bug (`~/CLAUDE.md` deploy), and the ignore-file-as-boundary pattern fails open: forgetting an entry deploys the file. `.chezmoiroot` fails closed.

## 9. Implementation Order

1. Branch `restructure`.
2. Capture baseline: `chezmoi diff > /tmp/before.diff`, `chezmoi managed > /tmp/before.managed`.
3. Add `.chezmoiroot`; `git mv` deployable state into `home/`; `git mv` scripts into `.chezmoiscripts/<platform>/` with new names; delete now-redundant ignore entries.
4. Extract the two fragments; update the consuming scripts.
5. Capture after-state; compare per §6.
6. Add CI workflow; push branch; confirm CI green.
7. Merge to `main`, push.
