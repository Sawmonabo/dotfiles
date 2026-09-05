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
