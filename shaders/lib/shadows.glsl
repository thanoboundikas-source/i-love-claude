/*
    Shadow map projection, distortion and filtering.

    Distortion: radial, so texels concentrate near the player (about 5x the
    density of an undistorted map at the centre, fading toward the edge).
    Used identically by shadow.vsh (writing) and the lighting passes (reading).

    Acne: normal offset scaled by the local world-space texel size, plus a
    tiny depth bias. Leaks: handled in lighting.glsl (sky-light guard).
    Filtering: SHADOW_SAMPLES rotated Vogel-disk taps, each a hardware 2x2
    comparison (shadowHardwareFiltering), rotated per pixel and per frame so
    TAA turns the noise into smooth penumbrae.

    Requires uniforms.glsl, settings.glsl, common.glsl.
*/

const float SHADOW_DISTORT = 0.80;

float shadowDistortFactor(vec2 clipXY) {
    return length(clipXY) * SHADOW_DISTORT + (1.0 - SHADOW_DISTORT);
}

vec3 distortShadow(vec3 clipPos) {
    return vec3(clipPos.xy / shadowDistortFactor(clipPos.xy), clipPos.z);
}

#ifndef SHADOW_TAPS
    #define SHADOW_TAPS SHADOW_SAMPLES
#endif

#if defined SHADOWS && !defined SHADOW_PASS
uniform sampler2DShadow shadowtex1;
#ifdef COLORED_SHADOWS_ACTIVE
    uniform sampler2DShadow shadowtex0;
    uniform sampler2D shadowcolor0;
#endif

// World-space size of one shadow texel at a given (undistorted) clip xy.
float shadowTexelWorld(vec2 clipXY) {
    float f = shadowDistortFactor(clipXY);
    float base = 2.0 * shadowDistance / float(shadowMapResolution);
    return base * f * f / (1.0 - SHADOW_DISTORT);
}

vec3 playerToShadowClip(vec3 playerPos) {
    vec3 sv = (shadowModelView * vec4(playerPos, 1.0)).xyz;
    return (shadowProjection * vec4(sv, 1.0)).xyz;
}

// 0 = fully inside the shadow map area, 1 = outside (use the fallback).
float shadowEdgeFade(vec3 clip) {
    float r = max(abs(clip.x), abs(clip.y));
    return smoothstep(0.82, 0.98, r);
}

// Vogel disk sample i of n, rotated by angle.
vec2 vogel(int i, int n, float angle) {
    float r = sqrt((float(i) + 0.5) / float(n));
    float theta = float(i) * 2.39996323 + angle;
    return r * vec2(cos(theta), sin(theta));
}

vec3 tapToScreen(vec3 clip) {
    return distortShadow(clip) * 0.5 + 0.5;
}

// Soft, possibly coloured visibility of the light from a surface.
//   playerPos  surface position in player space
//   geoNormal  un-bumped world normal (for the offset)
//   noise      0..1 per-pixel rotation
// Tap count is the compile-time macro SHADOW_TAPS (set by the program before
// including this file; defaults to the SHADOW_SAMPLES option), so the loop
// bound is never dynamic.
vec3 shadowVisibility(vec3 playerPos, vec3 geoNormal, float noise) {
    vec3 clip = playerToShadowClip(playerPos);
    float texelW = shadowTexelWorld(clip.xy);

    // Normal offset toward the light-facing side, bigger where texels are big.
    float ndl = dot(geoNormal, lightDir);
    vec3 offsetPos = playerPos + geoNormal * texelW * (1.2 + 1.2 * (1.0 - abs(ndl)));
    clip = playerToShadowClip(offsetPos);
    clip.z -= 0.00012;

    // Penumbra: SHADOW_SOFTNESS scales a ~0.08 block radius, never smaller
    // than ~1.2 texels so distant shadows stay smooth.
    float radiusWorld = max(0.08 * float(SHADOW_SOFTNESS) * 0.01, texelW * 1.2);
    float radiusClip = radiusWorld / shadowDistance;
    float angle = noise * TAU;

    float opaque = 0.0;
    for (int i = 0; i < SHADOW_TAPS; i++) {
        vec2 o = vogel(i, SHADOW_TAPS, angle) * radiusClip;
        opaque += texture(shadowtex1, tapToScreen(clip + vec3(o, 0.0)));
    }
    opaque /= float(SHADOW_TAPS);

    vec3 vis = vec3(opaque);
    #ifdef COLORED_SHADOWS_ACTIVE
        if (opaque > 0.001) {
            // Translucent casters (glass, water) are in shadowtex0 but not in
            // shadowtex1: the light that reaches us through them is tinted.
            vec3 center = tapToScreen(clip);
            float anyVis = texture(shadowtex0, center);
            if (anyVis < opaque - 0.001) {
                vec4 sc = texture(shadowcolor0, center.xy);
                vec3 tint;
                if (sc.a < 0.002) {
                    // Water: clear, gently tinted by its biome colour.
                    tint = mix(vec3(1.0), srgbToLinear(sc.rgb) * 1.6, 0.35);
                } else {
                    // Stained glass: coloured, a little dimmer.
                    tint = mix(vec3(1.0), srgbToLinear(sc.rgb) * 1.3, sc.a);
                }
                vis = vec3(anyVis) + (opaque - anyVis) * saturate(tint);
            }
        }
    #endif
    return vis;
}
#endif
