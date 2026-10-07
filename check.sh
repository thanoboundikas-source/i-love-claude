#!/bin/bash
# Offline typo catcher for Solstice. Run after every change: ./check.sh
# Needs glslang (brew install glslang). Not proof — the game log is the real test.
cd "$(dirname "$0")" || exit 1
python3 tools/check.py "$@"; rc=$?
case " $* " in *" --no-iris "*) exit $rc ;; esac
# Stage 3: Iris's real patcher + Apple GL link for every Iris draw type.
tools/iris_check.sh || rc=1
exit $rc
