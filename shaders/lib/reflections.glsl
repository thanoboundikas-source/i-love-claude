/*
    Water reflections. The caller declares colortex2 (HDR scene) and
    depthtex1 (opaque depth). Requires spaces.glsl, sky.glsl, clouds.glsl.

    Order of preference for a reflected ray:
      1. screen-space hit on terrain           (SSR, WATER_REFLECTIONS)
      2. the sky pixel in the reflected direction, if it is on screen: the
         scene buffer already holds the exact sky with the 3D clouds there
      3. analytic sky + flat clouds            (always available)
    Enclosed water (low sky light) reflects mostly darkness, not the sky.
*/

vec3 reflectionMiss(vec3 rView, vec3 rWorld, float skyLight, vec3 camWorld) {
    vec3 col;
    vec3 farScreen = viewToScreen(rView * 4000.0);
    bool onScreen = rView.z < 0.0 && all(greaterThan(farScreen.xy, vec2(0.002))) && all(lessThan(farScreen.xy, vec2(0.998)));
    if (onScreen && texture(depthtex1, farScreen.xy).r >= 1.0) {
        col = texture(colortex2, farScreen.xy).rgb;
    } else {
        vec3 r = vec3(rWorld.x, abs(rWorld.y), rWorld.z);
        col = skyGradient(r);
        #ifdef CLOUDS
            float hd;
            vec4 cl = fadeClouds(flatClouds(camWorld, r, 1e6, hd), r, hd);
            col = col * (1.0 - cl.a) + cl.rgb;
        #endif
    }
    return mix(ambientLight * 0.25 * skyLight, col, smoothstep(0.35, 0.9, skyLight));
}

#ifdef WATER_REFLECTIONS
// Screen-space ray march against the opaque depth (the water surface itself
// is not in depthtex1, so the ray never hits its own surface). Steps grow
// geometrically so a fixed SSR_STEPS covers near and far reflections;
// binary refinement sharpens the hit.
bool traceSSR(vec3 viewPos, vec3 rView, float jitter, out vec2 hitUV) {
    hitUV = vec2(0.0);
    float t = 0.25 + 0.015 * length(viewPos);
    float growth = pow(max(600.0 / t, 1.0001), 1.0 / float(SSR_STEPS));
    t *= mix(0.6, 1.0, jitter);
    float prevT = 0.0;
    for (int i = 0; i < SSR_STEPS; i++) {
        vec3 p = viewPos + rView * t;
        vec3 sp = viewToScreen(p);
        if (sp.x < 0.0 || sp.x > 1.0 || sp.y < 0.0 || sp.y > 1.0 || sp.z > 1.0) return false;
        float sceneD = texture(depthtex1, sp.xy).r;
        if (sceneD < 1.0) {
            float sceneZ = linearizeDepth(sceneD);
            float rayZ = -p.z;
            float thickness = max((t - prevT) * 1.6, 0.35);
            if (rayZ > sceneZ && rayZ - sceneZ < thickness) {
                // refine between prevT and t
                float a = prevT, b = t;
                for (int k = 0; k < 5; k++) {
                    float m = 0.5 * (a + b);
                    vec3 pm = viewPos + rView * m;
                    vec3 sm = viewToScreen(pm);
                    float zm = linearizeDepth(texture(depthtex1, sm.xy).r);
                    if (-pm.z > zm) b = m; else a = m;
                }
                hitUV = viewToScreen(viewPos + rView * b).xy;
                return true;
            }
        }
        prevT = t;
        t *= growth;
    }
    return false;
}
#endif

// Screen-edge fade so SSR hits near the border blend into the fallback.
float ssrEdgeFade(vec2 uv) {
    vec2 e = min(uv, 1.0 - uv);
    return smoothstep(0.0, 0.08, min(e.x, e.y));
}
