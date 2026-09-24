/*
    Air fog. Requires common.glsl, uniforms.glsl, settings.glsl, sky.glsl.

    Two parts, applied one after the other:
      haze    height fog (denser near sea level, much denser in rain/thunder).
              In clear air it grows with distance squared, so the first ~100
              blocks stay crisp and only far land gains blue depth. Its colour
              is the sky behind the object, capped at the brightness the sun
              and sky light could scatter, so it never lifts terrain to white.
      border  fades the last 15% of render distance into the exact sky
              colour, so the edge of the loaded world is never visible
    Underground (little sky light at the eye) the haze fades out: caves stay
    clean and never get a bright blue fog. Lava / powder snow / blindness
    fogs are handled here too.
*/

const float HAZE_CAP_SUN = 0.20;
const float HAZE_CAP_SKY = 0.55;

float fogHazeAmount(vec3 playerPos, float dist) {
    float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
    // Linear part (weather) + quadratic part (clear air): the first ~100
    // blocks stay crisp, distant terrain still gains depth.
    float lin = mix(0.00020, 0.0048, rainF) + stormF * 0.0030;
    const float QUAD = 3.6e-6;
    // Height falloff (scale height 55 blocks around y = 63): integrate
    // density * exp(-(y - 63) / H) along the ray, analytically.
    const float H = 55.0;
    float y0 = cameraPosition.y - 63.0;
    float dy = playerPos.y;
    float k = dy / H;
    float heightTerm = exp(-y0 / H) * (abs(k) > 1e-3 ? (1.0 - exp(-k)) / k : 1.0);
    float od = (lin + QUAD * dist) * dist * min(heightTerm, 4.0) * float(FOG_DENSITY) * 0.01;
    float haze = 1.0 - exp(-od);
    return haze * smoothstep(0.05, 0.45, eyeSky);
}

// Colour distant terrain fades toward: the sky behind it, but never brighter
// than what the sun and sky light could scatter toward the camera. Keeps the
// blue depth cue without lifting terrain toward a milky white.
vec3 fogHazeColor(vec3 dir) {
    vec3 c = fogSkyColor(dir);
    float l = luminance(c);
    float cap = luminance(directLight) * HAZE_CAP_SUN + luminance(ambientLight) * HAZE_CAP_SKY;
    return c * (min(l, cap) / max(l, 1e-4));
}

float fogBorderAmount(vec3 playerPos) {
    float horiz = length(playerPos.xz);
    return smoothstep(far * 0.84, far * 0.99, horiz);
}

vec3 applyAirFog(vec3 color, vec3 playerPos) {
    float dist = length(playerPos);
    vec3 dir = playerPos / max(dist, 1e-4);

    if (isEyeInWater == 2) {       // lava
        return mix(color, vec3(1.8, 0.45, 0.06), 1.0 - exp(-dist * 0.9));
    }
    if (isEyeInWater == 3) {       // powder snow
        return mix(color, vec3(0.55, 0.62, 0.72), 1.0 - exp(-dist * 0.7));
    }
    if (isEyeInWater == 1) return color;   // water: lib/water.glsl

    #ifdef FOG
        color = mix(color, fogHazeColor(dir), fogHazeAmount(playerPos, dist));
        color = mix(color, fogSkyColor(dir), fogBorderAmount(playerPos));
    #else
        color = mix(color, fogSkyColor(dir), fogBorderAmount(playerPos));
    #endif

    // Blindness / darkness effect: the world fades to black close by.
    float dark = max(blindness, darknessFactor);
    if (dark > 0.0) color *= mix(1.0, exp(-dist * 0.25), dark);
    return color;
}
