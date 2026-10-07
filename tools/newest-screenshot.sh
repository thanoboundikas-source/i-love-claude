#!/bin/bash
# Prints the newest F2 screenshot path(s). Usage: tools/newest-screenshot.sh [count]
PROFILE_DIR="${SOLSTICE_PROFILE:-$HOME/.lunarclient/profiles/fullbright-4}"
N="${1:-1}"
ls -t "$PROFILE_DIR"/screenshots/*.png 2>/dev/null | head -n "$N"
