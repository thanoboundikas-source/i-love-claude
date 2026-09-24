#!/usr/bin/env python3
"""
Solstice preview renderer: renders test scenes with the pack's own lib/ code
on Apple's OpenGL 4.1 driver, offscreen, and writes a PNG contact sheet.
Lets looks (sky palette, sunsets, clouds, fog, tonemap) be judged without
launching Minecraft. It is NOT the game: no real terrain, no Iris, no TAA.

Usage: python3 tools/preview.py SCENE [options]
  SCENE: sky | clouds | clouds_above | clouds_flat | world | hut | lake | snow | pbr
  (snow = the world scene with snow-white ground and stone, a bloom test:
  sunlit snow must not bloom or lift the shade around it)
Output: previews/<SCENE>.png inside the repo (ignored by git), or --name.

world / hut / lake use the game's HDR chain (two passes):
  1. the scene shader writes linear HDR colour (fog and godrays included,
     no tonemap) into a float texture in colortex2's format from
     lib/buffers.glsl, which is then mipmapped like Iris does;
  2. the pack's REAL final.fsh (sharpen + bloom + tonemap + dither) runs on it.
  Godrays: the same march as composite's godrayAmount() (GODRAY_SAMPLES
  points to min(distance, 48), ign jitter) with the voxel tracer standing in
  for shadowtex1, then godrayLight() from lib/godrays.glsl, exactly where
  composite1 adds it. Each tile is rendered at the game's framebuffer size
  (--ss 4: 1920x1080, Chris' F2 screenshots) and box-averaged down to
  480x270, because bloom radius is in pixels: a 480x270 render would show
  bloom 4x too wide. The average also stands in for TAA converging the
  per-pixel godray jitter.

Options:
  --profile NAME   apply a shaders.properties profile (POTATO/REGULAR/INSANE)
  --game           apply the options Iris saved for Chris (shaderpacks/Solstice.txt)
  --set K=V        override one option (repeatable), e.g. --set BLOOM=false
  --ss N           supersample factor for HDR scenes (default 4; 1 = fast draft)
  --legacy         old single pass (tonemap in the scene shader, no bloom,
                   godrays or sharpen), the path previews/baseline_*.png came from
  --post           also use the HDR chain for sky / clouds scenes
  --hdr-format F   rgba16f | r11g11b10f (default: colortex2Format)
  --name NAME      output file name (previews/NAME.png)
"""
import math
import os
import re
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


def read_png_rgba(data):
    """General 8-bit PNG decoder (grey, RGB, palette, grey+alpha, RGBA)."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, pal, trns = 8, b"", None, None
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos + 4])[0]
        t = data[pos + 4:pos + 8]
        d = data[pos + 8:pos + 8 + n]
        if t == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", d[:10])
        elif t == b"PLTE":
            pal = np.frombuffer(d, np.uint8).reshape(-1, 3)
        elif t == b"tRNS":
            trns = np.frombuffer(d, np.uint8)
        elif t == b"IDAT":
            idat += d
        pos += 12 + n
    if bd not in (1, 2, 4, 8):
        raise ValueError(f"bit depth {bd} not supported")
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    raw = zlib.decompress(idat)
    stride = (w * ch * bd + 7) // 8
    bpp = max(1, ch * bd // 8)
    rows = []
    prev = [0] * stride
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = list(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        cur = [0] * stride
        for i in range(stride):
            a = cur[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            x = line[i]
            if f == 1: x += a
            elif f == 2: x += b
            elif f == 3: x += (a + b) // 2
            elif f == 4:
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                x += a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            cur[i] = x & 255
        rows.append(cur)
        prev = cur
    arr = np.array(rows, np.uint8)
    if bd < 8:
        bits = np.unpackbits(arr, axis=1).reshape(h, -1, bd)
        vals = np.zeros(bits.shape[:2], np.uint8)
        for k in range(bd):
            vals = (vals << 1) | bits[..., k]
        px = vals[:, :w * ch].reshape(h, w, ch)
        if ct == 0:
            px = (px.astype(np.int32) * 255 // ((1 << bd) - 1)).astype(np.uint8)
    else:
        px = arr.reshape(h, w, ch)
    if ct == 3:
        rgb = pal[px[..., 0]]
        alpha = np.full((h, w), 255, np.uint8)
        if trns is not None:
            ta = np.full(256, 255, np.uint8); ta[:len(trns)] = trns
            alpha = ta[px[..., 0]]
        return np.dstack([rgb, alpha])
    if ct == 0: return np.dstack([px[..., 0]] * 3 + [np.full((h, w), 255, np.uint8)])
    if ct == 4: return np.dstack([px[..., 0]] * 3 + [px[..., 1]])
    if ct == 2: return np.dstack([px, np.full((h, w), 255, np.uint8)])
    return px


def vanilla_texture_raw(tmp, name):
    import zipfile
    with zipfile.ZipFile(VANILLA_JAR) as z:
        data = z.read(f"assets/minecraft/textures/block/{name}.png")
    rgba = read_png_rgba(data)[:16]          # first animation frame
    p = os.path.join(tmp, f"{name}.raw")
    open(p, "wb").write(np.ascontiguousarray(rgba).tobytes())
    return p, rgba.shape[1], rgba.shape[0]


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


# Option overrides for lib/settings.glsl (profile / game options / --set),
# applied through check.py's include expansion so the pack is never touched.
SETTINGS_OVERRIDES = {}
GAME_OPTIONS = os.path.join(os.path.dirname(ROOT), os.path.basename(ROOT) + ".txt")


def settings_overrides(profile=None, game=False, sets=()):
    text = open(os.path.join(check.SHADERS, check.SETTINGS_REL), encoding="utf-8").read()
    bools, values, consts = check.parse_options(text)
    cfg_b, cfg_v = {}, {}

    def put(k, v, where):
        if k in bools:
            if v.lower() not in ("true", "false", "on", "off", "1", "0"):
                sys.exit(f"{where}: {k} is a toggle, use true/false (got {v})")
            cfg_b[k] = v.lower() in ("true", "on", "1")
        elif k in values or k in consts:
            cfg_v[k] = v
        elif where == GAME_OPTIONS:
            print(f"  note: {where}: skipping {k} (no longer an option)")
        else:
            sys.exit(f"{where}: unknown option {k}")

    if profile:
        props = check.read_properties_lines(os.path.join(check.SHADERS, "shaders.properties"))
        profiles = check.parse_profiles(props)
        if profile not in profiles:
            sys.exit(f"unknown profile {profile} (have: {', '.join(profiles)})")
        b, v = check.resolve_profile(profile, profiles)
        cfg_b.update(b)
        cfg_v.update(v)
    if game:
        if not os.path.exists(GAME_OPTIONS):
            sys.exit(f"--game: {GAME_OPTIONS} not found (Iris writes it once an option is changed)")
        for line in open(GAME_OPTIONS, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                put(k.strip(), v.strip(), GAME_OPTIONS)
    for kv in sets:
        if "=" not in kv:
            sys.exit(f"--set wants NAME=VALUE, got {kv}")
        k, v = kv.split("=", 1)
        put(k.strip(), v.strip(), "--set")
    if not cfg_b and not cfg_v:
        return {}
    return {check.SETTINGS_REL: check.apply_config(text, cfg_b, cfg_v)}


def game_hdr_format():
    """colortex2's format from lib/buffers.glsl, as the preview.c format name."""
    try:
        text = open(os.path.join(check.SHADERS, "lib", "buffers.glsl"), encoding="utf-8").read()
        m = re.search(r"colortex2Format\s*=\s*(\w+)", text)
        if m and m.group(1) == "R11F_G11F_B10F":
            return "r11g11b10f"
    except OSError:
        pass
    return "rgba16f"


def glsl_to_core(path, tmp, out_name):
    lines = check.expand(path, SETTINGS_OVERRIDES)
    lines = check.inject_macros(lines, [])
    core = check.to_core(lines, "frag")
    out = os.path.join(tmp, out_name)
    open(out, "w").write("\n".join(t for t, _ in core) + "\n")
    return out


def shader_from_template(body, tmp):
    path = os.path.join(tmp, "preview_body.fsh")
    open(path, "w").write(body)
    return glsl_to_core(path, tmp, "preview.frag")


def final_post_shader(tmp):
    """The pack's real final program (stub shaders/final.fsh -> program/final.fsh)."""
    return glsl_to_core(os.path.join(check.SHADERS, "final.fsh"), tmp, "final.frag")


def render(frag, w, h, uniforms, tmp, post=None, hdr_format="rgba16f"):
    uf = os.path.join(tmp, "u.txt")
    open(uf, "w").write("\n".join(uniforms) + "\n")
    out = os.path.join(tmp, "out.raw")
    cmd = [BIN, frag, str(w), str(h), out, uf]
    if post:
        cmd += [post, hdr_format]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr)
        sys.exit(1)
    if r.stderr.strip():
        print("  preview:", r.stderr.strip())
    img = np.frombuffer(open(out, "rb").read(), np.uint8).reshape(h, w, 4)
    return img[::-1].copy()


_SRGB_DECODE = np.array([c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
                         for c in np.arange(256) / 255.0], np.float32)


def downsample(img, ss):
    """Box-average ss x ss blocks in linear light (what the eye sees when the
    game frame is shown smaller; also averages out per-pixel jitter noise)."""
    if ss == 1:
        return img
    h, w = img.shape[0] // ss, img.shape[1] // ss
    lin = _SRGB_DECODE[img[..., :3]].reshape(h, ss, w, ss, 3).mean((1, 3))
    enc = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(np.maximum(lin, 0.0031308), 1 / 2.4) - 0.055)
    rgb = np.clip(np.round(enc * 255.0), 0, 255).astype(np.uint8)
    return np.dstack([rgb, np.full((h, w), 255, np.uint8)])


def base_uniforms(sun_angle, forward, w, h, rain=0.0, thunder=0.0, moon_phase=0, t=100.0, cam_y=80.0, fov=70.0,
                  cam_xz=(0.0, 0.0)):
    sun = celestial_sun_dir(sun_angle, -30.0)
    mv, mvi = look_matrices(np.array(forward, float))
    proj = perspective(fov, w / h)
    sun_view = (mv[:3, :3] @ sun) * 100
    moon_view = (mv[:3, :3] @ -sun) * 100
    return [
        f"f viewWidth {w}", f"f viewHeight {h}", f"f aspectRatio {w / h}", "f near 0.05", "f far 256.0",
        f"f sunAngle {sun_angle}", f"i moonPhase {moon_phase}", f"f rainStrength {rain}", f"f wetness {rain}", "f blindness 0", "f darknessFactor 0",
        f"f thunderStrength {thunder}", f"f frameTimeCounter {t}", "i frameCounter 0", "i worldDay 3",
        f"f cloudHeight 192.33", f"v3 cameraPosition {cam_xz[0]} {cam_y} {cam_xz[1]}", f"f eyeAltitude {cam_y}",
        f"v3 shadowLightPosition {(sun_view if sun[1] > -0.001 else moon_view)[0]} {(sun_view if sun[1] > -0.001 else moon_view)[1]} {(sun_view if sun[1] > -0.001 else moon_view)[2]}",
        "f nightVision 0", "i isEyeInWater 0", "i2 eyeBrightnessSmooth 0 240", "i biome_precipitation 1",
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
    PREVIEW_OUTPUT
}
'''

# Single pass (legacy / non-HDR scenes): tonemap in the scene shader.
LDR_OUTPUT = """c = tonemapSolstice(c, nightF);
    outColor = vec4(linearToSrgb(c), 1.0);"""
# HDR chain: linear scene colour for final.fsh (colortex2 in the game).
HDR_OUTPUT = "outColor = vec4(c, 1.0);"
# World scenes in the HDR chain: godrays added to the fogged scene, as
# composite1 (program/composite_water.fsh) does, before final.
GODRAY_ADD = """#ifdef GODRAYS_ACTIVE
    c += godrayLight(previewGodrayAmount(dir, previewHitDist, ignAnimated(gl_FragCoord.xy, frameCounter)), dir);
    #endif
    """

PRESETS = [
    ("noon", 0.25, 0.0, 0.0),
    ("morning", 0.06, 0.0, 0.0),
    ("sunrise", 0.005, 0.0, 0.0),
    ("sunset", 0.495, 0.0, 0.0),
    ("dusk", 0.53, 0.0, 0.0),
    ("night", 0.75, 0.0, 0.0),
    ("rain noon", 0.25, 1.0, 0.0),
    ("thunder", 0.25, 1.0, 1.0),
    # Real golden hour (sun ~6 degrees up with sunPathRotation -30). Kept at
    # the end so row indices of older sheets stay the same.
    ("golden am", 0.02, 0.0, 0.0),
    ("golden pm", 0.48, 0.0, 0.0),
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



WORLD_EXTRA = r"""
#include "/lib/encoding.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/shadows.glsl"
PREVIEW_FOG_INCLUDE
#include "/lib/godrays.glsl"
// ---- tiny voxel test world (preview only) ----
int blockAt(ivec3 b) {
    if (abs(b.x) > 40 || abs(b.z) > 40 || b.y < 50 || b.y > 90) return 0;
    int h = 64 + int(floor(1.6 * sin(float(b.x) * 0.21) + 1.4 * cos(float(b.z) * 0.17)));
    if (b.x >= 2 && b.x <= 15 && b.z >= -2 && b.z <= 14) h = 64;
    float lakeR = length(vec2(b.xz) - vec2(-18.0, 16.0));
    if (lakeR < 16.0) h = min(h, 64 - int(floor(6.0 * (1.0 - lakeR / 16.0) + 0.5)));
    // hut 6..11 x, 6..11 z, walls 3 high, roof, open doorway
    if (b.x >= 6 && b.x <= 11 && b.z >= 6 && b.z <= 11 && b.y > 64 && b.y <= 68) {
        bool wall = b.x == 6 || b.x == 11 || b.z == 6 || b.z == 11;
        bool roof = b.y == 68;
        bool door = b.z == 6 && b.x == 8 && b.y <= 66;
        if (roof) return 6;
        if (wall && !door) return 6;
        if (b.x == 9 && b.z == 9 && b.y == 65) return 7; // glowstone
        return 0;
    }
    // tree at (-6, -4)
    if (b.x == -6 && b.z == -4 && b.y > h && b.y <= h + 5) return 4;
    if (b.y >= h + 4 && b.y <= h + 7) {
        vec3 d = vec3(b - ivec3(-6, h + 5, -4));
        if (dot(d, d) < 7.5) return 5;
    }
    // stone wall
    if (b.z == 14 && b.x >= -12 && b.x <= 2 && b.y > h && b.y <= h + 3) return 3;
    if (b.y == h) return 1;
    if (b.y < h && b.y >= h - 3) return 2;
    if (b.y < h - 3) return 3;
    return 0;
}

vec3 blockAlbedo(int id, vec3 n, vec2 uv, ivec3 b) {
    ivec2 tx = ivec2(floor(uv * 16.0));
    float r = hash12(vec2(tx) + vec2(b.xz) * 17.0 + float(b.y) * 3.0);
    vec3 c = vec3(0.5);
    if (id == 1) c = n.y > 0.5 ? vec3(0.36, 0.60, 0.22) : (uv.y > 0.8 ? vec3(0.36, 0.60, 0.22) : vec3(0.52, 0.37, 0.26));
    if (id == 2) c = vec3(0.52, 0.37, 0.26);
    if (id == 3) c = vec3(0.50);
    if (id == 4) c = n.y > 0.5 ? vec3(0.62, 0.50, 0.30) : vec3(0.40, 0.30, 0.18);
    if (id == 5) c = vec3(0.23, 0.46, 0.14);
    if (id == 6) c = vec3(0.66, 0.52, 0.32);
    if (id == 7) c = vec3(0.95, 0.80, 0.45);
#ifdef PREVIEW_SNOW
    // Snow-covered ground and white-concrete-like stone (bloom test).
    if (id == 1 || id == 2) c = n.y > 0.5 || id == 1 ? vec3(0.97, 0.98, 1.0) : c;
    if (id == 3) c = vec3(0.81, 0.82, 0.82);
    return c * (0.94 + 0.06 * r);
#endif
    return c * (0.82 + 0.3 * r);
}

bool traceVoxels(vec3 ro, vec3 rd, int steps, out ivec3 hitB, out vec3 hitN, out float hitT) {
    ivec3 b = ivec3(floor(ro));
    ivec3 st = ivec3(sign(rd));
    vec3 inv = 1.0 / max(abs(rd), vec3(1e-6));
    vec3 tMax = (vec3(b) + max(vec3(st), 0.0) - ro) / rd;
    tMax = abs(tMax);
    vec3 tDelta = inv;
    hitN = vec3(0.0);
    hitT = 0.0;
    for (int i = 0; i < 160; i++) {
        if (i >= steps) break;
        if (blockAt(b) != 0) { hitB = b; return true; }
        if (tMax.x < tMax.y && tMax.x < tMax.z) { b.x += st.x; hitT = tMax.x; tMax.x += tDelta.x; hitN = vec3(-float(st.x), 0.0, 0.0); }
        else if (tMax.y < tMax.z) { b.y += st.y; hitT = tMax.y; tMax.y += tDelta.y; hitN = vec3(0.0, -float(st.y), 0.0); }
        else { b.z += st.z; hitT = tMax.z; tMax.z += tDelta.z; hitN = vec3(0.0, 0.0, -float(st.z)); }
    }
    return false;
}

// Distance to the first surface along the primary view ray (depthtex0 in
// the game, so the water surface for water): the godray march length.
float previewHitDist = 1e4;

float aoOcc(ivec3 c) { return blockAt(c) != 0 ? 0.2 : 1.0; }
// Vanilla-style smooth-lighting AO (4 samples per vertex, bilinear across the face).
float previewAO(ivec3 hb, vec3 n, vec3 p) {
    ivec3 ni = ivec3(round(n));
    ivec3 f = hb + ni;
    ivec3 t1 = abs(n.x) > 0.5 ? ivec3(0, 1, 0) : ivec3(1, 0, 0);
    ivec3 t2 = abs(n.z) > 0.5 ? ivec3(0, 1, 0) : ivec3(0, 0, 1);
    vec3 fr = clamp(p - vec3(hb), 0.0, 1.0);
    float u = dot(fr, vec3(t1)), v = dot(fr, vec3(t2));
    float c[4];
    for (int k = 0; k < 4; k++) {
        int su = (k & 1) == 0 ? -1 : 1;
        int sv = (k & 2) == 0 ? -1 : 1;
        float a = aoOcc(f + t1 * su);
        float b = aoOcc(f + t2 * sv);
        float d = (a < 0.5 && b < 0.5) ? 0.2 : aoOcc(f + t1 * su + t2 * sv);
        c[k] = (1.0 + a + b + d) * 0.25;
    }
    return mix(mix(c[0], c[1], u), mix(c[2], c[3], u), v);
}

vec3 shadeHit(vec3 ro, vec3 dir, out float hitDist);
vec3 previewWorld(vec3 dir) {
    float hd;
    vec3 c = shadeHit(cameraPosition, dir, hd);
    previewHitDist = hd;
    return c;
}

#ifdef GODRAYS_ACTIVE
// Stand-in for composite's godrayAmount() (lib/godrays.glsl): the same march,
// shaft weight and falloff, but light visibility at each point comes from the voxel
// tracer instead of shadowtex1.
float previewGodrayAmount(vec3 dir, float hitDist, float jitter) {
    float dist = min(hitDist, 48.0);
    float stepLen = dist / float(GODRAY_SAMPLES);
    float vis = 0.0;
    for (int i = 0; i < GODRAY_SAMPLES; i++) {
        vec3 p = cameraPosition + dir * (stepLen * (float(i) + jitter));
        ivec3 b; vec3 n; float t;
        vis += traceVoxels(p, lightDir, 96, b, n, t) ? 0.0 : 1.0;
    }
    vis /= float(GODRAY_SAMPLES);
    return godrayShaftWeight(vis) * (1.0 - exp(-dist * 0.012));
}
#endif

const float WATER_Y = 63.9;
bool isLake(vec3 p) { return length(p.xz - vec2(-17.5, 16.5)) < 15.5; }

vec3 previewLake(vec3 dir) {
    vec3 ro = cameraPosition;
    float hd;
    if (dir.y < 0.0) {
        float tw = (WATER_Y - ro.y) / dir.y;
        vec3 p = ro + dir * tw;
        ivec3 hb; vec3 hn; float ht;
        bool terrainFirst = traceVoxels(ro, dir, 160, hb, hn, ht) && ht < tw;
        if (isLake(p) && !terrainFirst) {
            previewHitDist = tw;
            vec3 n = waterWaveNormal(p, vec3(0.0, 1.0, 0.0), tw);
            vec3 v = -dir;
            float f = waterFresnel(dot(n, v));
            vec3 r = reflect(dir, n);
            r.y = abs(r.y);
            vec3 refl = shadeHit(p + vec3(0.0, 0.02, 0.0), r, hd);
            vec3 td = refract(dir, n, 1.0 / 1.333);
            float bd;
            vec3 below = shadeHit(p - vec3(0.0, 0.02, 0.0), td, bd);
            vec3 tint = vec3(0.247, 0.463, 0.894);
            vec3 T = exp(-waterAbsorption(tint) * min(bd, 64.0));
            vec3 refr = below * T + waterScatterColor(tint, 1.0) * (1.0 - T);
            vec3 col = mix(refr, refl, f);
            ivec3 sb; vec3 sn; float st;
            float sh = traceVoxels(p + vec3(0.0, 0.05, 0.0), lightDir, 96, sb, sn, st) ? 0.0 : 1.0;
            col += directLight * sh * cloudShadow(p) * sunGlint(n, v, lightDir);
            return col;
        }
    }
    vec3 c = shadeHit(ro, dir, hd);
    previewHitDist = hd;
    return c;
}

vec3 shadeHit(vec3 ro, vec3 dir, out float hitDist) {
    ivec3 hb; vec3 hn; float ht;
    vec3 col;
    hitDist = 1e4;
    if (!traceVoxels(ro, dir, 160, hb, hn, ht)) {
        col = skyColorFull(dir);
        float hd; vec4 c = fadeClouds(traceClouds(ro, dir, 1e6, hd), dir, hd);
        return col * (1.0 - c.a) + c.rgb;
    }
    hitDist = ht;
    vec3 p = ro + dir * ht;
    int id = blockAt(hb);
    vec3 f = fract(p);
    vec2 uv = abs(hn.x) > 0.5 ? vec2(f.z, f.y) : (abs(hn.y) > 0.5 ? f.xz : vec2(f.x, f.y));
    Surface s;
    s.albedo = srgbToLinear(blockAlbedo(id, hn, uv, hb));
    s.normal = hn; s.geoNormal = hn;
    s.ao = PREVIEW_AO_ON ? previewAO(hb, hn, p) : 1.0; s.smoothness = 0.0; s.emissive = id == 7 ? 1.0 : 0.0;
    s.flags = id == 5 ? FLAG_SSS : 0;
    vec3 sp = p + hn * 0.01;
    // sky light: open above?
    ivec3 tb; vec3 tn; float tt;
    // Vanilla-ish sky light: full where the column above is open, ~11/15 under a roof.
    float sky = traceVoxels(sp, vec3(0.0, 1.0, 0.0), 24, tb, tn, tt) ? 0.7 : 1.0;
    if (hb.x >= 6 && hb.x <= 11 && hb.z >= 6 && hb.z <= 11 && p.y < 68.0 && p.y > 64.5) sky = 0.45;
    // block light from the glowstone at (9.5, 65.5, 9.5)
    vec3 lp = vec3(9.5, 65.5, 9.5);
    float md = abs(p.x - lp.x) + abs(p.y - lp.y) + abs(p.z - lp.z);
    float blk = saturate((15.0 - md) / 15.0);
    s.light = vec2(blk, saturate(sky));
    float sh = traceVoxels(sp, lightDir, 96, tb, tn, tt) ? 0.0 : 1.0;
    vec3 shadow = vec3(sh) * lightLeakGuard(s.light.y) * cloudShadow(p);
    col = shadeSurface(s, shadow, vec3(0.0), 0.0);
    PREVIEW_FOG_APPLY
    return col;
}
"""


FOG_INCLUDE = '#define PREVIEW_AO_ON true\n#include "/lib/fog.glsl"'
FOG_APPLY = "col = applyAirFog(col, p - cameraPosition);"


# Command-line choices (set in __main__).
OPTS = {"ss": 4, "legacy": False, "post": False, "hdr_format": None, "name": None}


def contact_sheet(body_color, extra, name, w=480, h=270, presets=PRESETS, textures=(), pitch=8.0, cam_y=80.0, fov=70.0,
                  cam_xz=(0.0, 0.0), look_at=None, hdr=False, godrays=False):
    """hdr: the game's two-pass chain (scene -> float colortex2 -> real
    final.fsh), each tile rendered at ss x the tile size and averaged down.
    godrays: add the preview godray march (world scenes only)."""
    build_bin()
    hdr = (hdr or OPTS["post"]) and not OPTS["legacy"]
    ss = max(1, int(OPTS["ss"])) if hdr else 1
    name = OPTS["name"] or name
    tmp = tempfile.mkdtemp(prefix="solstice-preview-")
    if hdr:
        output = (GODRAY_ADD if godrays else "") + HDR_OUTPUT
    else:
        output = LDR_OUTPUT
    body = SKY_BODY.replace("PREVIEW_COLOR", body_color).replace("PREVIEW_EXTRA", extra).replace("PREVIEW_OUTPUT", output)
    frag = shader_from_template(body, tmp)
    post = final_post_shader(tmp) if hdr else None
    hdr_format = OPTS["hdr_format"] or game_hdr_format()
    tex_lines = []
    for tname, unit in textures:
        if tname == "cloudTex":
            p, tw, th = vanilla_clouds_raw(tmp)
            tex_lines.append(f"t cloudTex {unit} {tw} {th} {p}")
    rw, rh = w * ss, h * ss
    if hdr:
        print(f"  HDR chain: scene -> {hdr_format} colortex2 (mipmapped) -> final.fsh, "
              f"{rw}x{rh} per tile averaged to {w}x{h}" + (", godrays" if godrays else ""))
    rows = []
    for label, angle, rain, thunder in presets:
        row = []
        for toward in (True, False):
            if look_at is not None:
                cam = np.array([cam_xz[0], cam_y, cam_xz[1]])
                tgt = np.array(look_at)
                fwd = tgt - cam if toward else np.array([-(tgt - cam)[2], (tgt - cam)[1], (tgt - cam)[0]])
            else:
                fwd = azimuth_forward(angle, toward, pitch)
            u = base_uniforms(angle, fwd, rw, rh, rain, thunder, cam_y=cam_y, fov=fov, cam_xz=cam_xz) + tex_lines
            row.append(downsample(render(frag, rw, rh, u, tmp, post, hdr_format), ss))
        rows.append(np.concatenate(row, 1))
        print(f"  rendered {label}")
    sheet = np.concatenate(rows, 0)
    outdir = os.path.join(ROOT, "previews")
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, f"{name}.png")
    if os.path.basename(out).startswith("baseline_"):
        sys.exit(f"refusing to overwrite {out} (baseline images are kept as they are)")
    write_png(out, sheet)
    print("wrote", out, "rows:", ", ".join(p[0] for p in presets), "| left = toward sun, right = away")
    return out


PBR_BODY = r"""#version 330 compatibility
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/spaces.glsl"
#include "/lib/encoding.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/tonemap.glsl"
#include "/lib/pbr.glsl"
uniform sampler2D gtexture;
uniform int useNormals;
uniform int isMetal;
in vec2 texcoord;
layout(location = 0) out vec4 outColor;
void main() {
    initSky();
    // A flat floor seen from above at an angle; UV tiles the 16x16 texture 3x.
    vec3 viewPos = screenToView(texcoord, 0.5);
    vec3 dir = normalize(viewDirToWorld(viewPos));
    float t = (60.0 - cameraPosition.y) / dir.y;
    vec3 p = cameraPosition + dir * t;
    vec2 uv = fract(p.xz / 1.0);
    vec3 alb = texture(gtexture, uv).rgb;
    vec3 n = vec3(0.0, 1.0, 0.0);
    float contrast = 0.0;
    if (useNormals == 1) n = generatedNormal(gtexture, uv, vec2(0.5), vec2(0.5), n, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), 4.0, contrast);
    else { float c2; generatedNormal(gtexture, uv, vec2(0.5), vec2(0.5), n, vec3(1.0,0.0,0.0), vec3(0.0,0.0,1.0), 4.0, c2); contrast = c2; }
    Surface s;
    s.albedo = srgbToLinear(alb); s.normal = n; s.geoNormal = vec3(0.0, 1.0, 0.0);
    s.light = vec2(0.0, 1.0); s.ao = 1.0; s.emissive = 0.0;
    s.flags = isMetal == 1 ? FLAG_METAL : 0;
    s.smoothness = generatedSmoothness(alb, contrast, isMetal == 1);
    vec3 c = shadeSurface(s, vec3(1.0), vec3(0.0), 0.0);
    if (s.smoothness > 0.01) c += specularLighting(s, -dir, vec3(1.0));
    outColor = vec4(linearToSrgb(tonemapSolstice(c, nightF)), 1.0);
}
"""


def pbr_sheet():
    build_bin()
    tmp = tempfile.mkdtemp(prefix="solstice-preview-")
    frag = shader_from_template(PBR_BODY, tmp)
    rows = []
    for tex, metal in (("cobblestone", 0), ("stone", 0), ("oak_planks", 0), ("iron_block", 1), ("white_concrete", 0)):
        p, tw, th = vanilla_texture_raw(tmp, tex)
        row = []
        for normals in (0, 1):
            sun_angle = 0.04   # low morning sun: bumps show clearly
            fwd = np.array([0.6, -0.8, 0.2])
            u = base_uniforms(sun_angle, fwd, 320, 200, cam_y=62.5) + [
                f"t gtexture 0 {tw} {th} {p}", f"i useNormals {normals}", f"i isMetal {metal}", "i2 atlasSize 16 16"]
            row.append(render(frag, 320, 200, u, tmp))
        rows.append(np.concatenate(row, 1))
        print("  rendered", tex)
    out = os.path.join(ROOT, "previews", (OPTS["name"] or "pbr") + ".png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    write_png(out, np.concatenate(rows, 0))
    print("wrote", out, "| left = flat, right = generated normals; rows: cobblestone, stone, oak planks, iron block, white concrete")


def parse_args():
    import argparse
    ap = argparse.ArgumentParser(description="Solstice offscreen preview renderer (see the module docstring).")
    ap.add_argument("scene", nargs="?", default="sky")
    ap.add_argument("--profile", help="apply a shaders.properties profile, e.g. INSANE")
    ap.add_argument("--game", action="store_true", help="apply the options Iris saved in shaderpacks/Solstice.txt")
    ap.add_argument("--set", action="append", default=[], metavar="NAME=VALUE", help="override one option")
    ap.add_argument("--ss", type=int, default=4, help="supersample factor for HDR scenes (4 = 1920x1080 tiles)")
    ap.add_argument("--legacy", action="store_true", help="old single pass: no bloom/godrays/sharpen")
    ap.add_argument("--post", action="store_true", help="HDR chain for sky/clouds scenes too")
    ap.add_argument("--hdr-format", choices=("rgba16f", "r11g11b10f"), help="default: colortex2Format")
    ap.add_argument("--name", help="output name, previews/NAME.png")
    a = ap.parse_args()
    OPTS.update(ss=a.ss, legacy=a.legacy, post=a.post, hdr_format=a.hdr_format, name=a.name)
    SETTINGS_OVERRIDES.update(settings_overrides(a.profile, a.game, a.set))
    if SETTINGS_OVERRIDES:
        print("  options:", " ".join(filter(None, [a.profile and "profile " + a.profile,
                                                   a.game and "game options", *a.set])))
    return a.scene


if __name__ == "__main__":
    scene = parse_args()
    cloud_presets = [p for p in PRESETS if p[0] in ("noon", "morning", "sunset", "dusk", "night", "rain noon")]
    if scene == "sky":
        contact_sheet("skyColorFull(dir)", "", "sky")
    elif scene == "clouds":
        contact_sheet("previewClouds(dir)", CLOUD_EXTRA, "clouds", presets=cloud_presets,
                      textures=[("cloudTex", 0)], pitch=18.0, cam_y=90.0)
    elif scene == "clouds_above":
        contact_sheet("previewClouds(dir)", CLOUD_EXTRA, "clouds_above", presets=cloud_presets,
                      textures=[("cloudTex", 0)], pitch=-12.0, cam_y=225.0)
    elif scene == "world":
        extra = WORLD_EXTRA.replace("PREVIEW_FOG_INCLUDE", FOG_INCLUDE).replace("PREVIEW_FOG_APPLY", FOG_APPLY)
        contact_sheet("previewWorld(dir)", CLOUD_EXTRA + extra, "world", presets=PRESETS,
                      textures=[("cloudTex", 0)], pitch=-14.0, cam_y=71.0, cam_xz=(2.0, -9.0), look_at=(9.0, 65.0, 8.0),
                      hdr=True, godrays=True)
    elif scene == "hut":
        extra = WORLD_EXTRA.replace("PREVIEW_FOG_INCLUDE", FOG_INCLUDE).replace("PREVIEW_FOG_APPLY", FOG_APPLY)
        pres = [p for p in PRESETS if p[0] in ("noon", "sunset", "night", "golden pm")]
        contact_sheet("previewWorld(dir)", CLOUD_EXTRA + extra, "hut", presets=pres,
                      textures=[("cloudTex", 0)], cam_y=66.6, cam_xz=(8.5, 3.0), look_at=(8.6, 65.6, 9.0),
                      hdr=True, godrays=True)
    elif scene == "lake":
        extra = WORLD_EXTRA.replace("PREVIEW_FOG_INCLUDE", FOG_INCLUDE).replace("PREVIEW_FOG_APPLY", FOG_APPLY)
        pres = [p for p in PRESETS if p[0] in ("noon", "morning", "sunset", "night", "golden pm")]
        contact_sheet("previewLake(dir)", CLOUD_EXTRA + extra, "lake", presets=pres,
                      textures=[("cloudTex", 0)], cam_y=69.0, cam_xz=(-2.0, 2.0), look_at=(-18.0, 62.0, 18.0),
                      hdr=True, godrays=True)
    elif scene == "snow":
        extra = WORLD_EXTRA.replace("PREVIEW_FOG_INCLUDE", FOG_INCLUDE).replace("PREVIEW_FOG_APPLY", FOG_APPLY)
        pres = [p for p in PRESETS if p[0] in ("noon", "golden pm", "sunset")]
        contact_sheet("previewWorld(dir)", CLOUD_EXTRA + "#define PREVIEW_SNOW 1\n" + extra, "snow", presets=pres,
                      textures=[("cloudTex", 0)], pitch=-14.0, cam_y=71.0, cam_xz=(2.0, -9.0), look_at=(9.0, 65.0, 8.0),
                      hdr=True, godrays=True)
    elif scene == "pbr":
        pbr_sheet()
    elif scene == "clouds_flat":
        contact_sheet("previewClouds(dir)", "#define PREVIEW_FLAT 1\n" + CLOUD_EXTRA, "clouds_flat",
                      presets=cloud_presets, textures=[("cloudTex", 0)], pitch=18.0, cam_y=90.0)
    else:
        sys.exit(f"unknown scene {scene}")
