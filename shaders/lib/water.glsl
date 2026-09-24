/*
    Water: waves, optics, colour. Requires common.glsl, uniforms.glsl,
    settings.glsl, sky.glsl (and clouds.glsl for reflected clouds).
*/

// ---------------------------------------------------------------- waves
// Height field in blocks: a few layers of moving value noise, gentle.
float waveHeight(vec2 p, float t) {
    float h = 0.0;
    h += (valueNoise2(p * 0.55 + vec2(t * 0.22, t * 0.13)) - 0.5) * 0.50;
    h += (valueNoise2(p * 1.35 - vec2(t * 0.31, -t * 0.19)) - 0.5) * 0.24;
    h += (valueNoise2(p * 2.70 + vec2(-t * 0.47, t * 0.41)) - 0.5) * 0.05;
    return h;
}

// World-space normal of a water top face. Waves fade out with distance so
// far water stays calm instead of sparkling.
vec3 waterWaveNormal(vec3 worldPos, vec3 geoNormal, float dist) {
    #ifdef WATER_WAVES
        if (geoNormal.y < 0.5) return geoNormal;
        float t = frameTimeCounter;
        vec2 p = worldPos.xz;
        const float e = 0.08;
        float h0 = waveHeight(p, t);
        float hx = waveHeight(p + vec2(e, 0.0), t);
        float hz = waveHeight(p + vec2(0.0, e), t);
        float amp = 0.30 * (1.0 - smoothstep(20.0, 90.0, dist));
        vec3 n = normalize(vec3(-(hx - h0) / e * amp, 1.0, -(hz - h0) / e * amp));
        return n;
    #else
        return geoNormal;
    #endif
}

// ---------------------------------------------------------------- optics
float waterFresnel(float cosTheta) {
    return 0.02 + 0.98 * pow5(1.0 - saturate(cosTheta));
}

// Per-block absorption from the biome water tint (sRGB vertex colour).
// Blue water absorbs red first, so deep water turns blue, shallow stays clear.
vec3 waterAbsorption(vec3 tintSrgb) {
    vec3 t = srgbToLinear(tintSrgb);
    return (1.0 - t) * 0.50 + vec3(0.06, 0.04, 0.02);
}

// Colour of light scattered back by the water body (what deep water looks
// like), lit by the sky and a little sun.
vec3 waterScatterColor(vec3 tintSrgb, float skyLight) {
    vec3 t = srgbToLinear(tintSrgb);
    vec3 light = ambientLight * (0.25 + 0.75 * skyLight * skyLight) + directLight * 0.18 * skyLight;
    return t * light * 0.60;
}

// Sharp sun glint (GGX, low roughness) on the wave normal.
float sunGlint(vec3 n, vec3 v, vec3 l) {
    vec3 h = normalize(v + l);
    float ndh = saturate(dot(n, h));
    float ndl = saturate(dot(n, l));
    const float a2 = 0.0016;       // roughness 0.2^2 squared
    float d = ndh * ndh * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * d * d);
    return D * ndl * waterFresnel(saturate(dot(h, v))) * 0.25;
}

// ---------------------------------------------------------------- fog
// Underwater fog colour: vanilla's fogColor is the biome water fog colour
// while the camera is in water; darker the less sky light reaches the eye.
vec3 underwaterFogColor() {
    float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
    vec3 c = srgbToLinear(fogColor);
    vec3 light = ambientLight * (0.15 + 0.85 * eyeSky * eyeSky) + directLight * 0.15 * eyeSky;
    return c * light * 0.9 + c * 0.004;
}

vec3 applyUnderwaterFog(vec3 color, float dist) {
    #ifdef UNDERWATER_FOG
        if (isEyeInWater == 1) {
            vec3 absorb = vec3(0.10, 0.055, 0.035);
            vec3 t = exp(-absorb * dist);
            color = color * t + underwaterFogColor() * (1.0 - t);
        }
    #endif
    return color;
}
