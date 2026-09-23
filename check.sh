#!/bin/bash
# Offline typo catcher for Solstice. Run after every change: ./check.sh
# Needs glslang (brew install glslang). Not proof — the game log is the real test.
cd "$(dirname "$0")" && exec python3 tools/check.py "$@"
