#!/usr/bin/env bash
# Render the entire chezmoi source tree for one (machine_role, versions_mode)
# pair into a throwaway destination, lint every script, and assert that no
# work-only or machine-specific content leaks. Used by CI on Linux and macOS
# and locally: scripts/render-check.sh personal pinned
#
# A third argument of "wsl" instead fakes a WSL host: the scratch config gets
# is_wsl = true plus the sizing answers that only a real WSL host would prompt
# for, and only the init and script-lint stages run. Apply and the leak checks
# are skipped because they assume the host really is the machine being checked.
set -euo pipefail

usage='usage: render-check.sh <personal|work|both> <pinned|latest> [wsl]'
role=${1:?$usage}
mode=${2:?$usage}
extra=${3:-}
if [ -n "$extra" ] && [ "$extra" != wsl ]; then echo "$usage" >&2; exit 2; fi
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
# scratch-init.sh puts its config in a directory of its own, so remove the
# directory rather than leaking one mktemp -d per run.
config_dir=
trap 'rm -rf "$tmp" "${config_dir:-}"' EXIT
dest="$tmp/home"
mkdir -p "$dest"
fail=0

echo "==> [$role/$mode] init: every prompt must be answerable non-interactively"
config=$("$repo/scripts/scratch-init.sh" "$role" "$mode")
config_dir=$(dirname "$config")
if [ "$extra" = wsl ]; then
    # The WSL sizing prompts only fire on a real WSL host, so answer them here.
    sed -i.bak 's/^\( *\)is_wsl = false$/\1is_wsl = true/' "$config" && rm -f "$config.bak"
    cat >> "$config" <<'WSLDATA'
    wsl_memory = "8GB"
    wsl_processors = 4
    wsl_swap = "2GB"
    restart_wsl_path = "Desktop/RestartWSL"
WSLDATA
    grep -q 'is_wsl = true' "$config" || { echo "WSL FAIL: could not force is_wsl in $config"; exit 1; }
fi
chez=(chezmoi --config "$config" --source "$repo" --destination "$dest")

if [ "$extra" != wsl ]; then
    echo "==> [$role/$mode] apply into $dest (scripts rendered, never run)"
    "${chez[@]}" apply --exclude scripts
fi

echo "==> [$role/$mode] lint scripts"
while IFS= read -r -d '' script; do
    out="$tmp/rendered.sh"
    if ! "${chez[@]}" execute-template < "$script" > "$out"; then
        echo "RENDER FAIL: $script"; fail=1; continue
    fi
    if [ -s "$out" ]; then
        echo "    linting ${script#"$repo"/}"
        bash -n "$out" || { echo "SYNTAX FAIL: $script"; fail=1; }
        shellcheck -S warning "$out" || { echo "SHELLCHECK FAIL: $script"; fail=1; }
    fi
done < <(find "$repo/home/.chezmoiscripts" -name '*.sh.tmpl' -print0 \
    ; [ "$extra" = wsl ] && printf '%s\0' "$repo/home/dot_local/bin/executable_win-browser.tmpl")

if [ "$extra" = wsl ]; then
    if [ "$fail" -ne 0 ]; then echo "FAILED [$role/$mode/wsl-lint]"; exit 1; fi
    echo "OK [$role/$mode/wsl-lint]"
    exit 0
fi

echo "==> [$role/$mode] leak checks"
if grep -rIln -e '/home/sabossedgh' -e '/Users/sawmonabo' "$repo/home"; then
    echo "LEAK: hardcoded home directory in a source template"; fail=1
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
if grep -rIil -e 'cursor' -e 'agent-brain' -e 'ab-claude' "$dest"; then
    echo "LEAK: Cursor or agent-brain content rendered"; fail=1
fi

echo "==> [$role/$mode] claude code status line"
python3 -m py_compile "$dest/.claude/scripts/statusline.py" || { echo "STATUSLINE FAIL: statusline.py does not compile"; fail=1; }
grep -q 'python3 ~/.claude/scripts/statusline.py' "$dest/.claude/settings.json" || { echo "STATUSLINE FAIL: settings.json does not point at statusline.py"; fail=1; }
grep -q 'statusline-command' "$dest/.claude/settings.json" && { echo "STATUSLINE FAIL: settings.json still references statusline-command.sh"; fail=1; }

if [ "$fail" -ne 0 ]; then echo "FAILED [$role/$mode]"; exit 1; fi
echo "OK [$role/$mode]"
