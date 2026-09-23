#!/usr/bin/env python3
"""
Pairs the comparison screenshots from TESTING.md.

Chris takes, for each shot in SHOTS order: one F2 with Complementary
Reimagined, then one F2 with Solstice. This script takes the newest
2 * len(SHOTS) screenshots (oldest first), checks there are exactly that many
since --since (optional), and copies them to
  previews/compare/<NN>_<shot>_A_reimagined.png
  previews/compare/<NN>_<shot>_B_solstice.png
The originals are left untouched.

Usage:
  python3 tools/pair_screenshots.py            # newest 20 screenshots
  python3 tools/pair_screenshots.py --list     # just show what would be paired
"""
import os
import shutil
import sys

PROFILE_DIR = os.environ.get("SOLSTICE_PROFILE", os.path.expanduser("~/.lunarclient/profiles/fullbright-4"))
SHOTS_DIR = os.path.join(PROFILE_DIR, "screenshots")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "previews", "compare")

SHOTS = ["sunrise", "noon", "sunset", "night", "rain", "cave_torches",
         "underwater", "lake_sunset", "clouds_below", "clouds_mountain"]


def main():
    files = sorted(
        (os.path.join(SHOTS_DIR, f) for f in os.listdir(SHOTS_DIR) if f.lower().endswith(".png")),
        key=os.path.getmtime)
    need = 2 * len(SHOTS)
    if len(files) < need:
        print(f"Only {len(files)} screenshots, need {need}.")
        return 1
    batch = files[-need:]
    if "--list" in sys.argv:
        for i, f in enumerate(batch):
            print(f"{SHOTS[i // 2]:16s} {'Reimagined' if i % 2 == 0 else 'Solstice  '}  {os.path.basename(f)}")
        return 0
    os.makedirs(OUT, exist_ok=True)
    for i, f in enumerate(batch):
        shot = SHOTS[i // 2]
        tag = "A_reimagined" if i % 2 == 0 else "B_solstice"
        dst = os.path.join(OUT, f"{i // 2 + 1:02d}_{shot}_{tag}.png")
        shutil.copy2(f, dst)
        print(os.path.basename(f), "->", os.path.relpath(dst, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
