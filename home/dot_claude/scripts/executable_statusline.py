#!/usr/bin/env python3
"""Claude Code status line: lualine-style filled segments, full width.

Claude Code renders statusline text through Ink with ``dimColor`` forced
on, and strips any SGR dim-off.  Only bold escapes the dim, and background
fills are unaffected.  So accent colour lives in segment *fills*, text that
must read at full strength is bold, and the context gradient is a fill.
Width comes from ``COLUMNS`` (injected at spawn).  Resize does not re-run
the command; ``refreshInterval`` in settings closes that gap.
"""
import json
import os
import re
import subprocess
import sys
import time
from urllib.parse import quote

THEME = "oxocarbon"

# The footer Box that hosts the status line has paddingX 2 (4 columns).
# ellipsis (too wide) or a gap on the right (too narrow).
RIGHT_INSET = 4

# name: (a_bg, a_fg, b_bg, b_fg, c_bg, c_fg, ok, warn, danger, edge)
# edge: the second dark-text fill (path block + worktree block).
THEMES = {
    "codedark":     ("#608b4e", "#1e1e1e", "#3c3c3c", "#d4d4d4", "#262626", "#9d9d9d", "#608b4e", "#d7ba7d", "#f44747", "#555555"),
    "moonfly":      ("#80a0ff", "#080808", "#323437", "#b2b2b2", "#1c1c1c", "#8c8c8c", "#8cc85f", "#e3c78a", "#ff5454", "#4e5054"),
    "oxocarbon":    ("#78a9ff", "#161616", "#393939", "#dde1e6", "#262626", "#8d8d8d", "#42be65", "#f1c21b", "#ee5396", "#525252"),
    "tokyonight":   ("#7aa2f7", "#1d202f", "#3b4261", "#a9b1d6", "#1f2335", "#7982a9", "#9ece6a", "#e0af68", "#f7768e", "#565f89"),
    "catppuccin":   ("#89b4fa", "#1e1e2e", "#45475a", "#cdd6f4", "#313244", "#9399b2", "#a6e3a1", "#f9e2af", "#f38ba8", "#585b70"),
    "slate_indigo": ("#818cf8", "#0f172a", "#334155", "#e2e8f0", "#1e293b", "#94a3b8", "#4ade80", "#facc15", "#f87171", "#475569"),
    "nord":         ("#88c0d0", "#2e3440", "#4c566a", "#eceff4", "#3b4252", "#a3aab8", "#a3be8c", "#ebcb8b", "#bf616a", "#5e6a80"),
    "onedark":      ("#61afef", "#282c34", "#3e4452", "#abb2bf", "#2c323c", "#8b93a2", "#98c379", "#e5c07b", "#e06c75", "#5c6370"),
}

RESET = "\033[0m"
BOLD = "\033[1m"


def rgb(h: str) -> tuple[int, int, int]:
    return int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)


def fg(h: str) -> str:
    return "\033[38;2;%d;%d;%dm" % rgb(h)


def bg(h: str) -> str:
    return "\033[48;2;%d;%d;%dm" % rgb(h)


def lerp(a: str, b: str, t: float) -> str:
    ra, ga, ba = rgb(a)
    rb, gb, bb = rgb(b)
    return "#%02x%02x%02x" % (
        round(ra + (rb - ra) * t), round(ga + (gb - ga) * t), round(ba + (bb - ba) * t))


def usage_color(pct: float, ok: str, warn: str, danger: str) -> str:
    """ok at 0, warn at the 60% pivot, danger at 100; interpolated."""
    pct = max(0.0, min(100.0, pct))
    if pct <= 60:
        return lerp(ok, warn, pct / 60)
    return lerp(warn, danger, (pct - 60) / 40)


def shorten_path(p: str) -> str:
    home = os.path.expanduser("~")
    if p.startswith(home):
        p = "~" + p[len(home):]
    parts = p.split("/")
    return "…/" + "/".join(parts[-4:]) if len(parts) > 5 else p


def git(cwd: str, *args: str) -> str:
    try:
        return subprocess.run(("git", "-C", cwd, *args), capture_output=True,
                              text=True, timeout=1).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def git_branch(cwd: str) -> str:
    return git(cwd, "branch", "--show-current") or git(cwd, "rev-parse", "--short", "HEAD")


def on_origin(cwd: str, branch: str) -> bool:
    """Whether ``branch`` has been pushed to origin (so its web URL exists)."""
    return bool(git(cwd, "rev-parse", "--verify", "--quiet", f"refs/remotes/origin/{branch}"))


def branch_url(cwd: str, branch: str) -> str:
    """Web URL of ``branch`` on the origin remote, or "" if not derivable."""
    remote = git(cwd, "remote", "get-url", "origin")
    if not (m := re.fullmatch(r"(?:git@([^:]+):|https://([^/]+)/)(.+?)(?:\.git)?/?", remote)):
        return ""
    return f"https://{m[1] or m[2]}/{m[3]}/tree/{quote(branch, safe='/')}"


def countdown(resets_at: float) -> str:
    """Compact time until ``resets_at`` (epoch seconds): 3d, 1d4h, 2h13m, 42m."""
    left = max(0, int(resets_at - time.time()))
    d, rem = divmod(left, 86400)
    h, rem = divmod(rem, 3600)
    m = rem // 60
    if d:
        return f"{d}d{h}h" if h else f"{d}d"
    if h:
        return f"{h}h{m}m" if m else f"{h}h"
    return f"{m}m" if m else "<1m"


def link(url: str, text: str) -> str:
    """OSC 8 hyperlink; zero visible width, Ctrl/Cmd+click in terminals."""
    return f"\033]8;;{url}\a{text}\033]8;;\a" if url else text


class Segment:
    """One filled block: ``' text '`` on a background."""

    def __init__(self, bg_hex: str, fg_hex: str, text: str, bold: bool = False, href: str = ""):
        self.bg_hex = bg_hex
        self.width = len(text) + 2
        self.ansi = f"{bg(bg_hex)}{fg(fg_hex)}{BOLD if bold else ''} {link(href, text)} {RESET}"


def dividers(segs: list[Segment]) -> int:
    """Number of neighbouring pairs that share a fill (each gets a 1-col divider)."""
    return sum(a.bg_hex == b.bg_hex for a, b in zip(segs, segs[1:]))


def joined(segs: list[Segment], divider_fg: str) -> str:
    """Concatenate segments, dividing neighbours that share a fill."""
    out = ""
    for prev, cur in zip([None, *segs], segs):
        if prev is not None and prev.bg_hex == cur.bg_hex:
            out += f"{bg(cur.bg_hex)}{fg(divider_fg)}│{RESET}"
        out += cur.ansi
    return out


def main() -> None:
    data = json.load(sys.stdin)
    a_bg, a_fg, b_bg, b_fg, c_bg, c_fg, ok, warn, danger, edge = THEMES[THEME]

    model = data.get("model", {}).get("display_name") or "Claude"
    style = data.get("output_style", {}).get("name") or ""
    workspace = data.get("workspace", {})
    cwd = workspace.get("current_dir") or data.get("cwd") or ""
    project = workspace.get("project_dir") or cwd
    worktree = workspace.get("git_worktree") or ""
    used = data.get("context_window", {}).get("used_percentage")
    rl = data.get("rate_limits", {})
    five_h = rl.get("five_hour", {})
    seven_d = rl.get("seven_day", {})
    cost = data.get("cost", {}).get("total_cost_usd")

    # Left edge group (dark text on fills): model on the accent, path on the
    # edge grey.  A linked worktree gets its own mid-bar block, light text,
    # anchored on the project root instead of spelling out .worktrees/<name>.
    head = model if not style or style == "default" else f"{model} · {style.lower()}"
    left = [Segment(a_bg, a_fg, head, bold=True)]
    if cwd:
        left.append(Segment(edge, a_fg, shorten_path(project if worktree else cwd), bold=True))
    if worktree:
        left.append(Segment(edge, b_fg, f"⌥ {worktree}", bold=True))
    branch = git_branch(cwd) if cwd else ""
    href = branch_url(cwd, branch) if branch and on_origin(cwd, branch) else ""
    tail_seg = Segment(c_bg, c_fg, f"\ue0a0 {branch}", href=href) if branch else None

    right = []
    bits, plain = [], []
    for label, window in (("5h", five_h), ("wk", seven_d)):
        if (val := window.get("used_percentage")) is None:
            continue
        n = f"{round(val)}%"
        reset = f" {countdown(window['resets_at'])}" if "resets_at" in window else ""
        bits.append(f"{label} {fg(usage_color(val, ok, warn, danger))}{n}{fg(c_fg)}{reset}{fg(b_fg)}")
        plain.append(f"{label} {n}{reset}")
    if plain:
        seg = Segment(b_bg, b_fg, "  ".join(plain), bold=True)
        seg.ansi = f"{bg(b_bg)}{fg(b_fg)}{BOLD} {'  '.join(bits)} {RESET}"
        right.append(seg)
    # Right edge group: cost on the accent, ctx on the usage gradient.
    if cost is not None:
        right.append(Segment(a_bg, a_fg, f"${cost:.2f}", bold=True))
    if used is not None:
        right.append(Segment(usage_color(used, ok, warn, danger), a_fg, f"ctx {round(used)}%", bold=True))

    cols = int(os.environ.get("COLUMNS") or 0)
    if not cols:
        line = joined(left + ([tail_seg] if tail_seg else []), c_fg)
        print(line + "  " + joined(right, c_fg))
        return

    avail = cols - RIGHT_INSET
    fixed = sum(s.width for s in left + right) + dividers(left) + dividers(right)
    # Degrade gracefully on narrow terminals: drop the branch, then the limits.
    # The cost and ctx segments always stay.
    if tail_seg and fixed + tail_seg.width > avail:
        tail_seg = None
    if fixed > avail and len(right) > 1:
        right = right[1:]
        fixed = sum(s.width for s in left + right) + dividers(left) + dividers(right)
    gap = max(0, avail - fixed - (tail_seg.width if tail_seg else 0))
    middle = (tail_seg.ansi if tail_seg else "") + f"{bg(c_bg)}{' ' * gap}{RESET}"
    print(joined(left, c_fg) + middle + joined(right, c_fg))


if __name__ == "__main__":
    main()
