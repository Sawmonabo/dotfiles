#!/usr/bin/env bash
# Claude Code status line entry point; the implementation is statusline.py.
exec python3 "${BASH_SOURCE[0]%/*}/statusline.py"
