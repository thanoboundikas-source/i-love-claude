#!/bin/bash
# Prints shader-related problems from the newest Minecraft (Lunar) game log.
#   tools/gamelog.sh         errors + warnings from shader loading
#   tools/gamelog.sh --all   every Iris/shader line with context
#   tools/gamelog.sh FILE    read a specific log (plain or .gz)
PROFILE_DIR="${SOLSTICE_PROFILE:-$HOME/.lunarclient/profiles/fullbright-4}"
LOG="$PROFILE_DIR/logs/latest.log"
MODE=errors
for a in "$@"; do
  case "$a" in
    --all) MODE=all ;;
    *) LOG="$a" ;;
  esac
done
[ -f "$LOG" ] || { echo "No log at $LOG"; exit 1; }
cat_log() { case "$LOG" in *.gz) gzcat "$LOG" ;; *) cat "$LOG" ;; esac; }

echo "== $LOG  (modified $(stat -f '%Sm' "$LOG"))"
if [ "$MODE" = all ]; then
  cat_log | grep -n -i -E -A3 "iris|shader|glsl|\.fsh|\.vsh|program link|solstice" | cut -c1-400
  exit 0
fi

# Hard failures: print the exception block that follows.
cat_log | awk '
  /Failed to create shader rendering pipeline|Shader compilation failed|Failed to load the shaderpack|ShaderCompileException|Failed to compile|Error loading shaders.properties|Properties pre-processing failed|Unable to parse|Pass sizes must match/ { show = 25 }
  /^ERROR: [0-9]+:[0-9]+/ { print NR": "$0; next }
  show > 0 { print NR": "$0; show--; next }
' | cut -c1-400

echo "-- link warnings (usually harmless unless they mention an output we need):"
cat_log | grep -n -A8 "Program link log for" | grep -v "Could not find vertex shader attribute" | cut -c1-300 | head -80
echo "-- other render-thread errors:"
cat_log | grep -n "\[Render thread/ERROR\]" | grep -v -i "ping\|packet\|fishing hook" | cut -c1-300 | tail -20
