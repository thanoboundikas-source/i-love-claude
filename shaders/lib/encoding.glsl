/*
    G-buffer packing. colortex1 is RGBA16 (unsigned normalized, 65536 exact
    levels per channel), so integer bit packing below is lossless.

    Opaque layout (written by gbuffers before the deferred pass):
      R, G = octahedral world-space normal
      B    = block light (bits 8-15) | sky light (bits 0-7)
      A    = bit 15: 0 (not translucent layer)
             bits 8-14: smoothness (7 bits)
             bits 4-7:  emissive strength (4 bits)
             bits 0-3:  flags (FLAG_*)

    Translucent layout (written by gbuffers_water after the deferred pass,
    over the same buffer; only trusted where depthtex0 < depthtex1):
      R, G = octahedral world-space normal (wave normal)
      B    = tint red (bits 8-15) | tint green (bits 0-7)
      A    = bit 15: 1 (translucent layer marker)
             bits 12-14: material (MAT_*)
             bits 8-11:  sky light (4 bits)
             bits 0-7:   tint blue
*/

const int FLAG_SSS   = 1;   // foliage / thin plants: light passes through
const int FLAG_METAL = 2;   // generated specular says "metal"
const int FLAG_HAND  = 4;   // held item: skip shadow map, depth is fake
const int FLAG_UNLIT = 8;   // outlines, leashes: albedo shown as-is

const int MAT_NONE  = 0;
const int MAT_WATER = 1;
const int MAT_GLASS = 2;

vec2 signNotZero(vec2 v) {
    return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

vec2 octEncode(vec3 n) {
    n /= abs(n.x) + abs(n.y) + abs(n.z);
    vec2 e = (n.z >= 0.0) ? n.xy : (1.0 - abs(n.yx)) * signNotZero(n.xy);
    return e * 0.5 + 0.5;
}

vec3 octDecode(vec2 e) {
    e = e * 2.0 - 1.0;
    vec3 n = vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
    if (n.z < 0.0) n.xy = (1.0 - abs(n.yx)) * signNotZero(n.xy);
    return normalize(n);
}

int unorm16ToInt(float f) { return int(f * 65535.0 + 0.5); }
float intToUnorm16(int i) { return float(i) / 65535.0; }

float packLight(vec2 blockSky) {
    ivec2 iv = ivec2(clamp(blockSky, 0.0, 1.0) * 255.0 + 0.5);
    return intToUnorm16(iv.x * 256 + iv.y);
}

vec2 unpackLight(float f) {
    int iv = unorm16ToInt(f);
    return vec2(float(iv >> 8), float(iv & 255)) / 255.0;
}

float packMaterial(float smoothness, float emissive, int flags) {
    int s = int(clamp(smoothness, 0.0, 1.0) * 127.0 + 0.5);
    int e = int(clamp(emissive, 0.0, 1.0) * 15.0 + 0.5);
    return intToUnorm16((s << 8) | (e << 4) | (flags & 15));
}

void unpackMaterial(float m, out float smoothness, out float emissive, out int flags) {
    int iv = unorm16ToInt(m);
    smoothness = float((iv >> 8) & 127) / 127.0;
    emissive = float((iv >> 4) & 15) / 15.0;
    flags = iv & 15;
}

vec4 packOpaque(vec3 normal, vec2 blockSky, float smoothness, float emissive, int flags) {
    return vec4(octEncode(normal), packLight(blockSky), packMaterial(smoothness, emissive, flags));
}

vec4 packTranslucent(vec3 normal, vec3 tint, float skyLight, int material) {
    ivec3 t = ivec3(clamp(tint, 0.0, 1.0) * 255.0 + 0.5);
    int sky = int(clamp(skyLight, 0.0, 1.0) * 15.0 + 0.5);
    float b = intToUnorm16((t.r << 8) | t.g);
    float a = intToUnorm16(32768 | ((material & 7) << 12) | (sky << 8) | t.b);
    return vec4(octEncode(normal), b, a);
}

bool isTranslucentLayer(vec4 data) {
    return (unorm16ToInt(data.a) & 32768) != 0;
}

int translucentMaterial(vec4 data) {
    int a = unorm16ToInt(data.a);
    return (a & 32768) != 0 ? ((a >> 12) & 7) : MAT_NONE;
}

void unpackTranslucent(vec4 data, out vec3 tint, out float skyLight) {
    int b = unorm16ToInt(data.b);
    int a = unorm16ToInt(data.a);
    tint = vec3(float(b >> 8), float(b & 255), float(a & 255)) / 255.0;
    skyLight = float((a >> 8) & 15) / 15.0;
}
