/*
    G-buffer packing. colortex1/colortex5 are RGBA16 (unsigned normalized,
    65535 exact levels per channel), so 8+8 bit packs are lossless.

    Layout (RGBA16):
      R, G = octahedral-encoded world-space normal
      B    = block light (hi 8) + sky light (lo 8)
      A    = smoothness (hi 8) + emissive (4) + flags (4)
    Flags: 1 = subsurface/foliage, 2 = metal, 4 = hand, 8 = unlit/fullbright.
*/

const int FLAG_SSS   = 1;
const int FLAG_METAL = 2;
const int FLAG_HAND  = 4;
const int FLAG_UNLIT = 8;

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

float pack2x8(vec2 v) {
    ivec2 iv = ivec2(clamp(v, 0.0, 1.0) * 255.0 + 0.5);
    return float(iv.x * 256 + iv.y) / 65535.0;
}

vec2 unpack2x8(float f) {
    int iv = int(f * 65535.0 + 0.5);
    return vec2(float(iv / 256), float(iv - (iv / 256) * 256)) / 255.0;
}

float packMaterial(float smoothness, float emissive, int flags) {
    int s = int(clamp(smoothness, 0.0, 1.0) * 255.0 + 0.5);
    int e = int(clamp(emissive, 0.0, 1.0) * 15.0 + 0.5);
    return float(s * 256 + e * 16 + flags) / 65535.0;
}

void unpackMaterial(float m, out float smoothness, out float emissive, out int flags) {
    int iv = int(m * 65535.0 + 0.5);
    smoothness = float(iv / 256) / 255.0;
    int rest = iv - (iv / 256) * 256;
    emissive = float(rest / 16) / 15.0;
    flags = rest - (rest / 16) * 16;
}
