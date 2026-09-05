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
    --promptString "Git work email (repos under ~/repos/ and ~/work/)=ci-work@example.invalid" \
    --promptString "Jira API token (for Codex MCP; stored locally only)=ci-placeholder" \
    --promptString "GitLab token (for Codex MCP; stored locally only)=ci-placeholder" \
    >/dev/null

echo "$config"
