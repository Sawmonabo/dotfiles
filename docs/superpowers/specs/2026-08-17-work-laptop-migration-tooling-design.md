# Work Laptop Migration Tooling Design

**Date:** 2026-08-17  
**Status:** Approved for implementation planning  
**Target:** Ubuntu 22.04.5 WSL source to Ubuntu 26.04 WSL destination

## Goal

Create a repeatable, reviewable migration toolkit that inventories the old WSL system and global development environment, then cleanly reinstalls compatible equivalents on Ubuntu 26.04. Project-specific dependencies and build outputs remain deferred until each project is next used.

## Delivery Layout

The tested source will live in the existing dotfiles repository:

```text
/home/sabossedgh/dev/dotfiles/work-laptop-migration/
├── README.md
├── inventory-global-environment.sh
├── reinstall-global-environment.sh
├── lib/
│   └── common.sh
└── tests/
    ├── run-tests.sh
    ├── test-inventory.sh
    └── test-reinstall.sh
```

A release copy will be published for the user under:

```text
C:\Users\SAbossedgh\Desktop\work-laptop-migration\
├── work-laptop-migration-runbook.md
└── tooling\
    ├── README.md
    ├── inventory-global-environment.sh
    ├── reinstall-global-environment.sh
    └── lib\common.sh
```

The existing Desktop runbook will be moved into this folder without changing its filename. The Desktop tooling copy is a release artifact; the dotfiles repository remains the canonical source for scripts and tests.

## Architecture

### Old-laptop inventory

`inventory-global-environment.sh` performs read-only discovery and writes non-secret manifests under:

```text
/home/sabossedgh/migration-audit/environment-inventory/
```

It records:

- Ubuntu release, architecture, user identity, and WSL information.
- Manually installed apt package names and old versions for reference.
- NVM Node versions, default Node version, and per-version global npm packages.
- Corepack, pnpm, Yarn, and Bun versions plus discoverable global packages.
- uv version, installed Python lines, uv-managed tools, and user-level Python packages.
- Go version and reconstructable `~/go/bin` module/version pairs.
- rustup toolchains, components, targets, and Cargo-installed tools.
- Docker, Podman, Nerdctl, Kubectl, and related client versions.
- GitHub CLI, Codex, Claude, chezmoi, and known standalone CLI versions.
- VS Code extensions.
- Enabled user systemd units and user crontab presence without copying secret contents into logs.
- Unresolved executables whose installation source cannot be proven.

The inventory never reads or records token, credential, private-key, `.env`, or application-password contents.

### New-laptop reinstall

`reinstall-global-environment.sh` consumes the copied inventory and executes idempotent phases:

1. Validate Ubuntu 26.04, user `sabossedgh`, UID `1000`, network availability, and required inventory files.
2. Install Ubuntu 26.04-compatible apt packages whose names exist in the destination repositories.
3. Install or refresh NVM, uv, rustup, Go, and Bun using approved upstream installation methods.
4. Install recorded runtime lines.
5. Reinstall global npm, uv, Cargo, and Go tools from their recorded package/module identities.
6. Reinstall standalone CLIs using explicit provider-specific installers or destination packages.
7. Restore VS Code extensions when the Windows `code` command is available.
8. Re-enable only user services that were recorded as enabled and whose executables validate successfully.
9. Produce a command/version comparison plus unresolved and failed-item reports.

Project repositories are never traversed for installation or build execution. The script does not run `npm install`, `pnpm install`, `uv sync`, `pip install -r`, `go mod download`, `cargo build`, Maven, Gradle, or .NET restore inside projects.

## Version Policy

The installer accepts:

```text
--versions pinned
--versions latest
```

`--versions pinned` is the default.

- Node: exact recorded versions in pinned mode; latest patch in each recorded major line in latest mode.
- Python: highest recorded patch in each required minor line in pinned mode; latest available patch in each recorded minor line in latest mode.
- Go: recorded version in pinned mode; latest stable version in latest mode.
- Rust: recorded toolchain in pinned mode; current stable toolchain in latest mode.
- Global package-manager tools: recorded package versions in pinned mode; newest available releases in latest mode.
- Standalone CLIs: recorded versions when the provider supports versioned installation; otherwise the limitation is written to the unresolved report rather than silently installing an unverified version.
- Apt: both modes install Ubuntu 26.04-compatible repository versions. Ubuntu 22.04 binary package versions are never forced onto Ubuntu 26.04.

The selected constants are written to a readable `versions.env` inventory file. Raw discovered versions remain in separate manifests for auditability.

## Command Interface

Inventory:

```bash
./inventory-global-environment.sh
./inventory-global-environment.sh --output /absolute/path
```

Reinstall:

```bash
./reinstall-global-environment.sh --versions pinned
./reinstall-global-environment.sh --versions latest
./reinstall-global-environment.sh --versions pinned --dry-run
./reinstall-global-environment.sh --versions pinned --phase base
./reinstall-global-environment.sh --versions pinned --phase runtimes
./reinstall-global-environment.sh --versions pinned --phase globals
./reinstall-global-environment.sh --versions pinned --phase editors
./reinstall-global-environment.sh --versions pinned --phase verify
```

The default phase is `all`. Every phase is rerunnable. `--dry-run` prints commands and makes no changes.

## Safety and Failure Handling

- No `rm -rf`, distro unregister, project cleanup, container pruning, or old-machine deletion.
- No copying of virtual environments, `node_modules`, build outputs, native caches, container volumes, or local databases.
- No secret values in manifests, output, or logs.
- Apt packages unavailable on Ubuntu 26.04 are skipped and reported.
- One tool failure does not erase prior successes; it is recorded and later phases continue when safe.
- A failed prerequisite blocks only dependent phases.
- Logs and reports are written under `/home/sabossedgh/migration-audit/environment-reinstall/`.
- The script exits nonzero when required tools remain unresolved, while retaining a complete report.

## Testing

Tests use a temporary fake home and a stubbed command path so they never install software or alter the live machine. They verify:

- Secret paths and values are excluded from inventory output.
- Version constants are selected deterministically.
- Pinned and latest modes generate different expected commands.
- Apt availability filtering skips missing package names.
- Dry-run performs no writes outside its report directory and invokes no installers.
- Project package managers are never invoked.
- Failed tools are reported without hiding successful work.
- Rerunning completed phases remains safe.

Additional checks:

```bash
bash -n work-laptop-migration/*.sh work-laptop-migration/lib/*.sh
shellcheck work-laptop-migration/*.sh work-laptop-migration/lib/*.sh
work-laptop-migration/tests/run-tests.sh
```

## Runbook Integration

The runbook will be updated to:

1. Run the inventory script on the old WSL before the initial transfer.
2. Confirm the generated inventory is included in the direct `rsync` transfer.
3. Run the new-laptop installer only after the final copy-verification gate.
4. Default to `--versions pinned` for migration acceptance.
5. Offer `--versions latest` as an intentional post-migration choice.
6. Require an empty critical-failure report before returning the old laptop.
7. State explicitly that project environments and builds are recreated only when those projects are next used.

## Acceptance Criteria

- The old-laptop inventory completes without exposing secrets.
- The inventory captures every currently identified system/global ecosystem or lists it as unresolved.
- Pinned and latest modes behave according to the version policy.
- No project dependency or build command is executed.
- The installer is safe to rerun and supports dry-run and phased execution.
- The verification report distinguishes installed, skipped, failed, and unresolved items.
- The Desktop folder contains the updated runbook and verified tooling release.
- The Desktop release scripts match the tested canonical scripts by SHA-256.
