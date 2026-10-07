#!/bin/bash
# Stage 3 of check.sh: runs Iris's REAL shader patcher (from the iris jar in
# the Lunar profile's mods folder) on every program, for every Iris draw type
# (ShaderKey) with its real vertex format and Iris's program fallback rules,
# then compiles + links the patched output with Apple's GL driver.
# This is what caught the gbuffers_line failure that glslang and the plain
# Apple stage could not see. Harness lives in ~/.solstice-dev/iris-harness.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$HOME/.solstice-dev/iris-harness"
JAVA=/opt/homebrew/opt/openjdk/bin/java
if [ ! -x "$JAVA" ] || [ ! -f "$H/Keys.class" ] || [ ! -f "$H/Harness.class" ]; then
  echo "Iris patcher check skipped (needs brew openjdk and $H)"; exit 0
fi
CP="$H/stub:$(cat "$H/cp.txt"):$H"
SRC="$H/src"; OUT="$H/check_out"
rm -rf "$SRC" "$OUT"; mkdir -p "$SRC" "$OUT"
python3 - "$ROOT" "$SRC" <<'EOF'
import sys, os
root, out = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, "tools")); import check
for key, st in sorted(check.programs().items()):
    for ext in (".vsh", ".fsh"):
        lines = check.inject_macros(check.expand(st[ext], {}), [])
        open(os.path.join(out, key.replace("/", "__") + ext), "w").write("\n".join(t for t, _ in lines) + "\n")
EOF
cd "$H"
FAIL=0
for pre in "" nether__ end__; do
  "$JAVA" -cp "$CP" Keys "$SRC" "$pre" "$OUT" 2>&1 | grep "TRANSFORM-FAIL" && FAIL=1 || true
done
# Sodium terrain/translucent, Sodium shadow, and composite-style passes.
for f in "$SRC"/*.vsh; do
  p=$(basename "$f" .vsh)
  case $p in
    *gbuffers_terrain|*gbuffers_water) modes="sodium";;
    shadow) modes="shadow";;
    *gbuffers_*) modes="";;
    *) modes="composite";;
  esac
  for m in $modes; do
    "$JAVA" -cp "$CP" Harness $m "$p" "$SRC/$p.vsh" "$SRC/$p.fsh" "$OUT" 2>&1 | grep "FAIL" && FAIL=1 || true
  done
done
: > list.txt
for v in "$OUT"/*.vertex; do n=$(basename "$v" .vertex); [ -f "$OUT/$n.fragment" ] && printf '%s\t%s\t%s\n' "$n" "$v" "$OUT/$n.fragment" >> list.txt; done
"$ROOT/tools/.applegl" list.txt > apple.txt 2>&1 || FAIL=1
grep -A4 "### FAIL" apple.txt || true
echo "Iris patcher stage: $(tail -1 apple.txt | sed 's/### //')"
exit $FAIL
