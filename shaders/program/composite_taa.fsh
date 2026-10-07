/*
    composite2 — temporal anti-aliasing (TAA on).

    Every gbuffers program jitters its projection by a sub-pixel Halton
    offset each frame; this pass blends the current frame into a history
    buffer (colortex5, never cleared):
      - reprojection with the previous camera (camera motion only; moving
        entities rely on the neighbourhood clip)
      - history clipped to the current 3x3 neighbourhood's colour spread
        (YCoCg, variance clip) -> no ghosting trails
      - done in a compressed (x / (1 + luma)) space so bright pixels do not
        flicker
      - more weight on the current frame while the camera moves -> sharper
        in motion
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/spaces.glsl"

uniform sampler2D colortex2;
uniform sampler2D colortex5;
uniform sampler2D depthtex0;

in vec2 texcoord;

/* RENDERTARGETS: 2,5 */
layout(location = 0) out vec4 outScene;
layout(location = 1) out vec4 outHistory;

vec3 toYCoCg(vec3 c) {
    return vec3(0.25 * c.r + 0.5 * c.g + 0.25 * c.b, 0.5 * c.r - 0.5 * c.b, -0.25 * c.r + 0.5 * c.g - 0.25 * c.b);
}
vec3 fromYCoCg(vec3 c) {
    return vec3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z);
}
vec3 compress(vec3 c) { return c / (1.0 + luminance(c)); }
vec3 expand(vec3 c) { return c / max(1.0 - luminance(c), 1e-3); }

vec3 fetchC(ivec2 p, ivec2 maxP) {
    return toYCoCg(compress(texelFetch(colortex2, clamp(p, ivec2(0), maxP), 0).rgb));
}

// History fetch with a 5-tap Catmull-Rom filter (bilinear taps at the
// combined weights, the 4 corner taps dropped): keeps the history sharp while
// the camera moves, where a single bilinear fetch blurs it a little more
// every frame. Clamped to the central 2x2 texels (anti-ringing).
vec3 historyCatmullRom(vec2 uv) {
    vec2 res = vec2(viewWidth, viewHeight);
    vec2 pos = uv * res;
    vec2 c = floor(pos - 0.5) + 0.5;
    vec2 f = pos - c;
    vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    vec2 w3 = f * f * (-0.5 + 0.5 * f);
    vec2 w12 = w1 + w2;
    vec2 t0 = (c - 1.0) / res;
    vec2 t3 = (c + 2.0) / res;
    vec2 t12 = (c + w2 / w12) / res;
    float a = w12.x * w0.y, b = w0.x * w12.y, m = w12.x * w12.y, d = w3.x * w12.y, e = w12.x * w3.y;
    vec3 sa = texture(colortex5, vec2(t12.x, t0.y)).rgb;
    vec3 sb = texture(colortex5, vec2(t0.x, t12.y)).rgb;
    vec3 sm = texture(colortex5, t12).rgb;
    vec3 sd = texture(colortex5, vec2(t3.x, t12.y)).rgb;
    vec3 se = texture(colortex5, vec2(t12.x, t3.y)).rgb;
    vec3 s = (sa * a + sb * b + sm * m + sd * d + se * e) / (a + b + m + d + e);
    // Anti-ringing: keep the result inside the 2x2 texels it interpolates
    // between. Without this the negative lobes turn a very bright neighbour
    // (sun disc, glowstone, lava, glints) into a dark 1 px outline while the
    // camera moves. The 4 texels are the ones the centre tap just read, so
    // they come from the cache. (Clamping to the 5 bilinear taps instead
    // would clamp every detail peak to a blurred value and lose all the
    // sharpening Catmull-Rom is here for.)
    ivec2 i0 = ivec2(c - 0.5);
    ivec2 maxP = ivec2(res) - 1;
    vec3 q0 = texelFetch(colortex5, clamp(i0,               ivec2(0), maxP), 0).rgb;
    vec3 q1 = texelFetch(colortex5, clamp(i0 + ivec2(1, 0), ivec2(0), maxP), 0).rgb;
    vec3 q2 = texelFetch(colortex5, clamp(i0 + ivec2(0, 1), ivec2(0), maxP), 0).rgb;
    vec3 q3 = texelFetch(colortex5, clamp(i0 + ivec2(1, 1), ivec2(0), maxP), 0).rgb;
    return clamp(s, min(min(q0, q1), min(q2, q3)), max(max(q0, q1), max(q2, q3)));
}

// Clip a colour toward the centre of an AABB (keeps hue, avoids flat clamps).
vec3 clipToBox(vec3 hist, vec3 lo, vec3 hi) {
    vec3 c = 0.5 * (lo + hi);
    vec3 e = 0.5 * (hi - lo) + 1e-5;
    vec3 d = hist - c;
    vec3 a = abs(d / e);
    float m = max(a.x, max(a.y, a.z));
    return m > 1.0 ? c + d / m : hist;
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    ivec2 maxP = ivec2(viewWidth, viewHeight) - 1;

    vec3 cur = fetchC(px, maxP);

    // Neighbourhood statistics (3x3).
    vec3 m1 = cur, m2 = cur * cur;
    vec3 n;
    n = fetchC(px + ivec2(-1, -1), maxP); m1 += n; m2 += n * n;
    n = fetchC(px + ivec2( 0, -1), maxP); m1 += n; m2 += n * n;
    n = fetchC(px + ivec2( 1, -1), maxP); m1 += n; m2 += n * n;
    n = fetchC(px + ivec2(-1,  0), maxP); m1 += n; m2 += n * n;
    n = fetchC(px + ivec2( 1,  0), maxP); m1 += n; m2 += n * n;
    n = fetchC(px + ivec2(-1,  1), maxP); m1 += n; m2 += n * n;
    n = fetchC(px + ivec2( 0,  1), maxP); m1 += n; m2 += n * n;
    n = fetchC(px + ivec2( 1,  1), maxP); m1 += n; m2 += n * n;
    vec3 mean = m1 / 9.0;
    vec3 sigma = sqrt(max(m2 / 9.0 - mean * mean, 0.0));
    vec3 lo = mean - 1.25 * sigma;
    vec3 hi = mean + 1.25 * sigma;

    // Reprojection (the held item stays put on screen: no reprojection).
    float depth = texelFetch(depthtex0, px, 0).r;
    vec2 prevUV = texcoord;
    if (depth > 0.56) {
        vec3 viewPos = screenToView(texcoord, depth);
        vec3 playerPos = viewToPlayer(viewPos);
        vec3 prevPlayer = playerPos + (cameraPosition - previousCameraPosition);
        vec4 prevClip = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(prevPlayer, 1.0));
        prevUV = prevClip.xy / prevClip.w * 0.5 + 0.5;
    }

    vec3 result;
    bool offscreen = any(lessThan(prevUV, vec2(0.0))) || any(greaterThan(prevUV, vec2(1.0)));
    vec3 histRaw = historyCatmullRom(prevUV);
    if (offscreen || any(isnan(histRaw)) || any(isinf(histRaw))) {
        result = fromYCoCg(cur);
    } else {
        vec3 hist = clipToBox(toYCoCg(compress(max(histRaw, 0.0))), lo, hi);
        float motionPx = length((prevUV - texcoord) * vec2(viewWidth, viewHeight));
        float w = mix(0.09, 0.30, saturate(motionPx / 6.0));
        result = fromYCoCg(mix(hist, cur, w));
    }
    result = expand(max(result, 0.0));

    outScene = vec4(result, 1.0);
    outHistory = vec4(result, 1.0);
}
