#!/usr/bin/env python3
"""
Solstice preview renderer: renders test scenes with the pack's own lib/ code
on Apple's OpenGL 4.1 driver, offscreen, and writes a PNG contact sheet.
Lets looks (sky palette, sunsets, clouds, fog, tonemap) be judged without
launching Minecraft. It is NOT the game: no terrain, no Iris.

Usage: python3 tools/preview.py SCENE [OUT.png]
  SCENE: sky | clouds | scene
Output defaults to /tmp-ish scratch: previews/<scene>.png inside the repo
(ignored by git).
"""
import math
import os
import struct
import subprocess
import sys
import tempfile
import zlib

import numpy as np

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import check  # noqa: E402  (reuses include expansion + core conversion)

BIN = os.path.join(TOOLS, ".preview")
SRC = os.path.join(TOOLS, "preview.c")
VANILLA_JAR = os.path.expanduser("~/.lunarclient/shared/versions/26.1.2/26.1.2.jar")


# ------------------------------------------------------------------ PNG io
def write_png(path, rgba):
    h, w, _ = rgba.shape
    raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def read_png_gray1(data):
    """Decodes the vanilla clouds.png (1-bit greyscale) to an RGBA8 array."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, w = 8, b"", 0
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos + 4])[0]
        t = data[pos + 4:pos + 8]
        d = data[pos + 8:pos + 8 + n]
        if t == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", d[:10])
            assert bd == 1 and ct == 0, (bd, ct)
        elif t == b"IDAT":
            idat += d
        pos += 12 + n
    raw = zlib.decompress(idat)
    stride = (w + 7) // 8
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - 1] if i else 0
            b = prev[i]
            c = prev[i - 1] if i else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(np.unpackbits(np.frombuffer(bytes(line), np.uint8))[:w])
        prev = line
    g = (np.array(rows, np.uint8) * 255)
    return np.stack([g, g, g, np.full_like(g, 255)], -1)


def vanilla_clouds_raw(tmp):
    import zipfile
    with zipfile.ZipFile(VANILLA_JAR) as z:
        data = z.read("assets/minecraft/textures/environment/clouds.png")
    rgba = read_png_gray1(data)
    p = os.path.join(tmp, "clouds.raw")
    # GL's first row is the bottom row; Iris uploads textures top row first
    # with v=0 at the top, so keep the file order.
    open(p, "wb").write(rgba.tobytes())
    return p, rgba.shape[1], rgba.shape[0]


# ------------------------------------------------------------- math helpers
def celestial_sun_dir(sun_angle, path_rot_deg):
    """Inverse of lib/sky.glsl toCelestial applied to +Z (direction to the sun)."""
    sky = (sun_angle - 0.25) % 1.0
    a = -sky * 2 * math.pi
    r = math.radians(path_rot_deg)
    v = np.array([0.0, 0.0, 1.0])
    v = np.array([v[0], v[2], -v[1]])                                   # inv RotX(90)
    ca, sa = math.cos(a), math.sin(a)
    v = np.array([ca * v[0] + sa * v[1], -sa * v[0] + ca * v[1], v[2]])  # inv RotZ(a)
    cr, sr = math.cos(r), math.sin(r)
    v = np.array([v[0], cr * v[1] + sr * v[2], -sr * v[1] + cr * v[2]])  # inv RotX(r)
    return v / np.linalg.norm(v)


def look_matrices(forward):
    f = forward / np.linalg.norm(forward)
    up = np.array([0.0, 1.0, 0.0])
    r = np.cross(f, up); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    mv = np.identity(4)
    mv[0, :3], mv[1, :3], mv[2, :3] = r, u, -f
    return mv, mv.T.copy()


def perspective(fov_deg, aspect, near=0.05, far=1024.0):
    t = 1.0 / math.tan(math.radians(fov_deg) / 2)
    p = np.zeros((4, 4))
    p[0, 0], p[1, 1] = t / aspect, t
    p[2, 2] = -(far + near) / (far - near)
    p[2, 3] = -2 * far * near / (far - near)
    p[3, 2] = -1
    return p


def m4(name, m):
    return f"m4 {name} " + " ".join(f"{x:.8f}" for x in m.T.flatten())


# --------------------------------------------------------------- rendering
def build_bin():
    if not os.path.exists(BIN) or os.path.getmtime(BIN) < os.path.getmtime(SRC):
        subprocess.check_call(["clang", "-O1", "-Wno-deprecated-declarations", "-framework", "OpenGL", SRC, "-o", BIN])


def shader_from_template(body, tmp):
    path = os.path.join(tmp, "preview_body.fsh")
    open(path, "w").write(body)
    lines = check.expand(path, {})
    lines = check.inject_macros(lines, [])
    core = check.to_core(lines, "frag")
    out = os.path.join(tmp, "preview.frag")
    open(out, "w").write("\n".join(t for t, _ in core) + "\n")
    return out


def render(frag, w, h, uniforms, tmp):
    uf = os.path.join(tmp, "u.txt")
    open(uf, "w").write("\n".join(uniforms) + "\n")
    out = os.path.join(tmp, "out.raw")
    r = subprocess.run([BIN, frag, str(w), str(h), out, uf], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr)
        sys.exit(1)
    img = np.frombuffer(open(out, "rb").read(), np.uint8).reshape(h, w, 4)
    return img[::-1].copy()


def base_uniforms(sun_angle, forward, w, h, rain=0.0, thunder=0.0, moon_phase=0, t=100.0, cam_y=80.0, fov=70.0):
    sun = celestial_sun_dir(sun_angle, -30.0)
    mv, mvi = look_matrices(np.array(forward, float))
    proj = perspective(fov, w / h)
    sun_view = (mv[:3, :3] @ sun) * 100
    moon_view = (mv[:3, :3] @ -sun) * 100
    return [
        f"f viewWidth {w}", f"f viewHeight {h}", f"f aspectRatio {w / h}", "f near 0.05", "f far 256.0",
        f"f sunAngle {sun_angle}", f"i moonPhase {moon_phase}", f"f rainStrength {rain}", f"f wetness {rain}",
        f"f thunderStrength {thunder}", f"f frameTimeCounter {t}", "i frameCounter 0", "i worldDay 3",
        f"f cloudHeight 192.33", f"v3 cameraPosition 0 {cam_y} 0", f"f eyeAltitude {cam_y}",
        "f nightVision 0", "i isEyeInWater 0", "v2 eyeBrightnessSmooth 0 240",
        f"v3 sunPosition {sun_view[0]} {sun_view[1]} {sun_view[2]}",
        f"v3 moonPosition {moon_view[0]} {moon_view[1]} {moon_view[2]}",
        m4("gbufferModelView", mv), m4("gbufferModelViewInverse", mvi),
        m4("gbufferProjection", proj), m4("gbufferProjectionInverse", np.linalg.inv(proj)),
    ]


def azimuth_forward(sun_angle, toward=True, pitch_deg=8.0):
    sun = celestial_sun_dir(sun_angle, -30.0)
    flat = np.array([sun[0], 0.0, sun[2]])
    if np.linalg.norm(flat) < 1e-3:
        flat = np.array([1.0, 0.0, 0.0])
    flat /= np.linalg.norm(flat)
    if not toward:
        flat = -flat
    p = math.radians(pitch_deg)
    return flat * math.cos(p) + np.array([0, math.sin(p), 0])


SKY_BODY = r'''#version 330 compatibility
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/spaces.glsl"
#include "/lib/sky.glsl"
#include "/lib/tonemap.glsl"
#include "/lib/clouds.glsl"
PREVIEW_EXTRA
in vec2 texcoord;
layout(location = 0) out vec4 outColor;
void main() {
    initSky();
    vec3 viewPos = screenToView(texcoord, 1.0);
    vec3 dir = normalize(viewDirToWorld(viewPos));
    vec3 c = PREVIEW_COLOR;
    c = tonemapSolstice(c);
    outColor = vec4(linearToSrgb(c), 1.0);
}
'''

PRESETS = [
    ("noon", 0.25, 0.0, 0.0),
    ("morning", 0.06, 0.0, 0.0),
    ("sunrise", 0.005, 0.0, 0.0),
    ("sunset", 0.495, 0.0, 0.0),
    ("dusk", 0.53, 0.0, 0.0),
    ("night", 0.75, 0.0, 0.0),
    ("rain noon", 0.25, 1.0, 0.0),
    ("thunder", 0.25, 1.0, 1.0),
]


CLOUD_EXTRA = r'''
vec3 previewClouds(vec3 dir) {
    vec3 col = skyColorFull(dir);
    vec3 origin = cameraPosition;
    float hd;
#ifdef PREVIEW_FLAT
    vec4 c = flatClouds(origin, dir, 1e6, hd);
#else
    vec4 c = traceClouds(origin, dir, 1e6, hd);
#endif
    c = fadeClouds(c, dir, hd);
    return col * (1.0 - c.a) + c.rgb;
}
'''


def contact_sheet(body_color, extra, name, w=480, h=270, presets=PRESETS, textures=(), pitch=8.0, cam_y=80.0, fov=70.0):
    build_bin()
    tmp = tempfile.mkdtemp(prefix="solstice-preview-")
    body = SKY_BODY.replace("PREVIEW_COLOR", body_color).replace("PREVIEW_EXTRA", extra)
    frag = shader_from_template(body, tmp)
    tex_lines = []
    for tname, unit in textures:
        if tname == "cloudTex":
            p, tw, th = vanilla_clouds_raw(tmp)
            tex_lines.append(f"t cloudTex {unit} {tw} {th} {p}")
    rows = []
    for label, angle, rain, thunder in presets:
        row = []
        for toward in (True, False):
            fwd = azimuth_forward(angle, toward, pitch)
            u = base_uniforms(angle, fwd, w, h, rain, thunder, cam_y=cam_y, fov=fov) + tex_lines
            row.append(render(frag, w, h, u, tmp))
        rows.append(np.concatenate(row, 1))
        print(f"  rendered {label}")
    sheet = np.concatenate(rows, 0)
    outdir = os.path.join(ROOT, "previews")
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, f"{name}.png")
    write_png(out, sheet)
    print("wrote", out, "rows:", ", ".join(p[0] for p in presets), "| left = toward sun, right = away")
    return out


if __name__ == "__main__":
    scene = sys.argv[1] if len(sys.argv) > 1 else "sky"
    cloud_presets = [p for p in PRESETS if p[0] in ("noon", "morning", "sunset", "dusk", "night", "rain noon")]
    if scene == "sky":
        contact_sheet("skyColorFull(dir)", "", "sky")
    elif scene == "clouds":
        contact_sheet("previewClouds(dir)", CLOUD_EXTRA, "clouds", presets=cloud_presets,
                      textures=[("cloudTex", 0)], pitch=18.0, cam_y=90.0)
    elif scene == "clouds_above":
        contact_sheet("previewClouds(dir)", CLOUD_EXTRA, "clouds_above", presets=cloud_presets,
                      textures=[("cloudTex", 0)], pitch=-12.0, cam_y=225.0)
    elif scene == "clouds_flat":
        contact_sheet("previewClouds(dir)", "#define PREVIEW_FLAT 1\n" + CLOUD_EXTRA, "clouds_flat",
                      presets=cloud_presets, textures=[("cloudTex", 0)], pitch=18.0, cam_y=90.0)
    else:
        print("unknown scene", scene)
