#!/usr/bin/env python3
"""
Regenerates the thin per-program stub files in shaders/ (and the dimension
folders). Each stub is just: #version, an optional variant #define, and an
#include of the shared program body in shaders/program/.

Edit PROGRAMS below, then run: python3 tools/gen_stubs.py
Stubs are generated files; put real code in shaders/program/.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADERS = os.path.join(ROOT, "shaders")

# (folder, program name, vertex body, fragment body, variant define or None)
OVERWORLD = [
    ("shadow", "shadow", "shadow", None),
    ("gbuffers_terrain", "gbuffers_solid", "gbuffers_solid", "GB_TERRAIN"),
    ("gbuffers_block", "gbuffers_solid", "gbuffers_solid", "GB_BLOCK"),
    ("gbuffers_entities", "gbuffers_solid", "gbuffers_solid", "GB_ENTITY"),
    ("gbuffers_hand", "gbuffers_solid", "gbuffers_solid", "GB_HAND"),
    ("gbuffers_damagedblock", "gbuffers_solid", "gbuffers_solid", "GB_DAMAGE"),
    ("gbuffers_spidereyes", "gbuffers_solid", "gbuffers_solid", "GB_GLOW"),
    ("gbuffers_lightning", "gbuffers_solid", "gbuffers_solid", "GB_GLOW"),
    ("gbuffers_entities_translucent", "gbuffers_forward", "gbuffers_forward", "FW_LIT"),
    ("gbuffers_block_translucent", "gbuffers_forward", "gbuffers_forward", "FW_LIT"),
    ("gbuffers_particles", "gbuffers_forward", "gbuffers_forward", "FW_LIT"),
    ("gbuffers_particles_translucent", "gbuffers_forward", "gbuffers_forward", "FW_LIT"),
    ("gbuffers_textured_lit", "gbuffers_forward", "gbuffers_forward", "FW_LIT"),
    ("gbuffers_hand_water", "gbuffers_forward", "gbuffers_forward", "FW_LIT"),
    ("gbuffers_textured", "gbuffers_forward", "gbuffers_forward", "FW_UNLIT"),
    ("gbuffers_weather", "gbuffers_forward", "gbuffers_forward", "FW_WEATHER"),
    ("gbuffers_armor_glint", "gbuffers_forward", "gbuffers_forward", "FW_ADDITIVE"),
    ("gbuffers_beaconbeam", "gbuffers_forward", "gbuffers_forward", "FW_GLOW"),
    ("gbuffers_basic", "gbuffers_forward", "gbuffers_forward", "FW_BASIC"),
    ("gbuffers_line", "gbuffers_forward", "gbuffers_forward", "FW_BASIC"),
    ("gbuffers_water", "gbuffers_water", "gbuffers_water", None),
    ("gbuffers_skybasic", "gbuffers_sky", "gbuffers_sky", None),
    ("gbuffers_skytextured", "gbuffers_sky", "gbuffers_sky", None),
    ("deferred", "fullscreen", "deferred_clouds", None),
    ("deferred1", "fullscreen", "deferred_lighting", None),
    ("final", "fullscreen", "final", None),
]

FOLDERS = {
    "": OVERWORLD,
}


def write_stub(path, body, define):
    lines = ["#version 330 compatibility", ""]
    if define:
        lines.append(f"#define {define} 1")
    lines.append(f'#include "/program/{body}"')
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    count = 0
    for folder, programs in FOLDERS.items():
        d = os.path.join(SHADERS, folder)
        os.makedirs(d, exist_ok=True)
        for name, vbody, fbody, define in programs:
            write_stub(os.path.join(d, name + ".vsh"), vbody + ".vsh", define)
            write_stub(os.path.join(d, name + ".fsh"), fbody + ".fsh", define)
            count += 1
    print(f"wrote {count} program stubs")


if __name__ == "__main__":
    main()
