/*
    Air fog. Requires common.glsl, uniforms.glsl, settings.glsl, sky.glsl.

    Two parts, the stronger wins:
      haze    exponential height fog (denser near sea level, much denser in
              rain/thunder), coloured with the sky behind the object so
              distant terrain melts into the horizon
      border  fades the last stretch of render distance into the sky, so the
              edge of the loaded world is never visible
    Underground (little sky light at the eye) the haze fades out: caves stay
    clean and never get a bright blue fog. Lava / powder snow / blindness
    fogs are handled here too.
*/

float fogHazeAmount(vec3 playerPos, float dist) {
    float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
    float density = mix(0.0016, 0.0075, rainF) + stormF * 0.004;
    density *= float(FOG_DENSITY) * 0.01;
    // Height falloff (scale height 55 blocks around y = 63): integrate
    // density * exp(-(y - 63) / H) along the ray, analytically.
    const float H = 55.0;
    float y0 = cameraPosition.y - 63.0;
    float dy = playerPos.y;
    float k = dy / H;
    float heightTerm = exp(-y0 / H) * (abs(k) > 1e-3 ? (1.0 - exp(-k)) / k : 1.0);
    float od = density * dist * min(heightTerm, 4.0);
    float haze = 1.0 - exp(-od);
    return haze * smoothstep(0.05, 0.45, eyeSky);
}

float fogBorderAmount(vec3 playerPos) {
    float horiz = length(playerPos.xz);
    return smoothstep(far * 0.72, far * 0.98, horiz);
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
        float amount = max(fogHazeAmount(playerPos, dist), fogBorderAmount(playerPos));
        color = mix(color, fogSkyColor(dir), amount);
    #else
        color = mix(color, fogSkyColor(dir), fogBorderAmount(playerPos));
    #endif

    // Blindness / darkness effect: the world fades to black close by.
    float dark = max(blindness, darknessFactor);
    if (dark > 0.0) color *= mix(1.0, exp(-dist * 0.25), dark);
    return color;
}
