/*
    Godrays: light scattered by the air between the camera and a surface,
    visible where sunlight is broken up by terrain and trees. Marches the
    view ray through the shadow map (GODRAY_SAMPLES, jittered) at the scaled
    effects resolution; the phase function and colour are applied in
    composite1 at full resolution. Requires shadows.glsl (SHADOWS on).
*/

#ifdef GODRAYS_ACTIVE
// Average light visibility along the ray, scaled by how much air there is.
float godrayAmount(vec3 playerEnd, float jitter) {
    float dist = min(length(playerEnd), 160.0);
    vec3 dir = playerEnd / max(length(playerEnd), 1e-4);
    float stepLen = dist / float(GODRAY_SAMPLES);
    float vis = 0.0;
    for (int i = 0; i < GODRAY_SAMPLES; i++) {
        vec3 p = dir * (stepLen * (float(i) + jitter));
        vec3 sp = tapToScreen(playerToShadowClip(p));
        bool inside = sp.x > 0.0 && sp.x < 1.0 && sp.y > 0.0 && sp.y < 1.0;
        vis += inside ? texture(shadowtex1, sp) : 1.0;
    }
    vis /= float(GODRAY_SAMPLES);
    return vis * (1.0 - exp(-dist * 0.012));
}

// Henyey-Greenstein phase: strong forward scattering toward the light.
float phaseHG(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

vec3 godrayLight(float amount, vec3 viewDirWorld) {
    float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
    float phase = phaseHG(dot(viewDirWorld, lightDir), 0.72) + 0.03;
    float strength = 0.10 * float(GODRAY_STRENGTH) * 0.01;
    return directLight * amount * phase * strength * smoothstep(0.1, 0.6, eyeSky) * (1.0 - rainF * 0.6);
}
#endif
