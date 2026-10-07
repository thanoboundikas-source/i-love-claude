/*
    Small shared helpers: constants, colour utilities, hashes, noise, dither.
*/

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3 saturate(vec3 x) { return clamp(x, 0.0, 1.0); }
float sq(float x) { return x * x; }
float pow5(float x) { float x2 = x * x; return x2 * x2 * x; }

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Vanilla textures and the final image are sRGB. A 2.2 power curve is used
// both ways so the conversion is cheap and exactly invertible.
vec3 srgbToLinear(vec3 c) { return pow(c, vec3(2.2)); }
vec3 linearToSrgb(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }

// Keeps luminance, scales chroma.
vec3 adjustSaturation(vec3 c, float s) {
    float l = luminance(c);
    return max(vec3(0.0), vec3(l) + (c - vec3(l)) * s);
}

// ---- hashes (sine-free) ----
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 hash33(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 2D value noise with smooth interpolation, range 0..1.
float valueNoise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Interleaved gradient noise: cheap per-pixel noise with a blue-ish spectrum.
float ign(vec2 fragCoord) {
    return fract(52.9829189 * fract(dot(fragCoord, vec2(0.06711056, 0.00583715))));
}

// Temporally varied version for effects that TAA averages out.
float ignAnimated(vec2 fragCoord, int frame) {
    #ifdef TAA
        fragCoord += 5.588238 * float(frame & 63);
    #endif
    return ign(fragCoord);
}

// Triangular dither of +-1 LSB for 8-bit outputs (hides banding).
vec3 ditherRGB8(vec2 fragCoord) {
    float a = ign(fragCoord);
    float b = ign(fragCoord + vec2(71.3, 19.7));
    return vec3(a + b - 1.0) / 255.0;
}
