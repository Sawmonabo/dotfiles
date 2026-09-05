# --- Bitwarden CLI (bw): persistent unlock ---
# `bw unlock` unlocks once (master password) and caches the session key in a
# 0600 file that every new shell reads, so bw commands just work afterwards.
# `bw lock` locks the vault and wipes that cache. Everything else is passed to
# the real binary untouched (`command bw ...` bypasses the wrapper entirely).
# Trade-off: while cached, anyone with this user account can read the vault —
# same class as ~/.aws/credentials. `bw lock` when you are done for the day.
export BW_SESSION_FILE="$HOME/.config/Bitwarden CLI/session"
if [ -r "$BW_SESSION_FILE" ]; then
    BW_SESSION="$(cat "$BW_SESSION_FILE")"; export BW_SESSION
fi
bw() {
    case "$1" in
        unlock)
            command -v bw >/dev/null 2>&1 || { echo "bw not installed (https://bitwarden.com/download/?app=cli&platform=linux)"; return 1; }
            case "$(command bw status 2>/dev/null)" in
                *'"status":"unlocked"'*) echo "vault already unlocked"; return 0 ;;
                *'"status":"unauthenticated"'*) command bw login || return 1 ;;
            esac
            local s
            s="$(command bw unlock --raw)" || return 1
            mkdir -p "$(dirname "$BW_SESSION_FILE")"
            (umask 077; printf '%s' "$s" >"$BW_SESSION_FILE")
            BW_SESSION="$s"; export BW_SESSION
            command bw sync >/dev/null 2>&1
            echo "vault unlocked and synced; session cached for new shells (bw lock to end it)"
            ;;
        lock)
            command bw lock >/dev/null 2>&1
            rm -f "$BW_SESSION_FILE"
            unset BW_SESSION
            echo "vault locked; cached session removed"
            ;;
        *) command bw "$@" ;;
    esac
}
