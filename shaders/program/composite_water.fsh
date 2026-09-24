/*
    composite1 — full resolution water shading + underwater fog.

    Water pixels (translucent layer marked MAT_WATER in colortex1):
      refraction  scene behind the surface, bent by the wave normal
      absorption  per-channel by the depth of water the light crosses, so
                  shorelines are clear and deep water turns the biome colour
      reflection  from the effects pass (SSR + sky/cloud fallback), or the
                  fallback computed here when WATER_REFLECTIONS is off
      Fresnel + sun glint
    From below the surface: Snell's window (total internal reflection past
    the critical angle shows the underwater fog colour).
    Camera in water: underwater fog to the first surface (UNDERWATER_FOG).
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/spaces.glsl"
#include "/lib/encoding.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/clouds.glsl"
#include "/lib/water.glsl"
#define SHADOW_TAPS 2
#include "/lib/shadows.glsl"
#include "/lib/fog.glsl"
#include "/lib/godrays.glsl"

uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
#if defined WATER_REFLECTIONS || defined GODRAYS_ACTIVE
    uniform sampler2D colortex4;
#endif

#include "/lib/reflections.glsl"

in vec2 texcoord;

/* RENDERTARGETS: 2 */
layout(location = 0) out vec4 outScene;

#ifdef GODRAYS_ACTIVE
// View distance to the surface at a godray neighbour tap (1e4 = sky, like
// dist in main).
float godrayTapDist(vec2 uv) {
    ivec2 size = ivec2(viewWidth, viewHeight);
    float d = texelFetch(depthtex0, clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1), 0).r;
    return d >= 1.0 ? 1e4 : length(screenToView(uv, d));
}
#endif

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    initSky();
    vec3 color = texelFetch(colortex2, px, 0).rgb;
    float d0 = texelFetch(depthtex0, px, 0).r;
    float d1 = texelFetch(depthtex1, px, 0).r;
    vec3 viewPos0 = screenToView(texcoord, d0);
    float dist = d0 >= 1.0 ? 1e4 : length(viewPos0);

    #ifdef WATER_DEFERRED
    vec4 data = texelFetch(colortex1, px, 0);
    if (d0 < d1 && translucentMaterial(data) == MAT_WATER) {
        vec3 tint; float sky;
        unpackTranslucent(data, tint, sky);
        vec3 n = octDecode(data.rg);
        vec3 playerPos = viewToPlayer(viewPos0);
        vec3 camWorld = cameraPosition + gbufferModelViewInverse[3].xyz;
        vec3 v = normalize(-playerPos);
        bool fromBelow = isEyeInWater == 1;
        if (dot(n, v) < 0.0) n = -n;
        vec3 nView = worldDirToView(n);

        // ---- refraction
        vec2 uv = texcoord;
        float depthBehind = d1;
        #ifdef WATER_REFRACTION
            vec3 viewPos1 = screenToView(texcoord, d1);
            float waterDepth = d1 >= 1.0 ? 8.0 : length(viewPos1 - viewPos0);
            vec2 offset = nView.xy * 0.045 * saturate(waterDepth * 0.35) / (1.0 + dist * 0.03);
            vec2 cand = clamp(texcoord - offset, vec2(0.001), vec2(0.999));
            float candD1 = texture(depthtex1, cand).r;
            // Only take the bent sample if it is also behind the water surface.
            if (candD1 > d0) { uv = cand; depthBehind = candD1; }
        #endif
        vec3 behind = texture(colortex2, uv).rgb;

        float cosV = saturate(dot(n, v));
        float f = waterFresnel(cosV);

        if (!fromBelow) {
            vec3 viewBehind = screenToView(uv, depthBehind);
            float path = depthBehind >= 1.0 ? 64.0 : length(viewBehind - viewPos0);
            vec3 T = exp(-waterAbsorption(tint) * path);
            vec3 scatter = waterScatterColor(tint, sky);
            vec3 refracted = behind * T + scatter * (1.0 - T);

            #ifdef WATER_REFLECTIONS
                vec3 refl = texture(colortex4, texcoord).rgb;
            #else
                vec3 rView = reflect(normalize(viewPos0), nView);
                vec3 refl = reflectionMiss(rView, viewDirToWorld(rView), sky, camWorld);
            #endif

            #ifdef SHADOWS
                vec3 sh = shadowVisibility(playerPos, vec3(0.0, 1.0, 0.0), ign(gl_FragCoord.xy)) * lightLeakGuard(sky);
                sh = mix(sh, vec3(skyShadowProxy(sky)), shadowEdgeFade(playerToShadowClip(playerPos)));
            #else
                vec3 sh = vec3(skyShadowProxy(sky));
            #endif
            vec3 glint = directLight * sh * cloudShadow(playerPos + camWorld) * sunGlint(n, v, lightDir);
            // Air fog on the surface itself (reflection + glint); the scene
            // behind was already fogged to its own distance in deferred1.
            vec3 surface = applyAirFog(refl + glint / max(f, 0.02), playerPos);
            color = mix(refracted, surface, f);
        } else {
            // Looking up from under water: the sky/world above is visible
            // inside Snell's window; past the critical angle the surface
            // mirrors the water below.
            float sinT = sqrt(1.0 - cosV * cosV) * 1.333;
            float tir = smoothstep(0.92, 1.0, sinT);
            vec3 inside = underwaterFogColor();
            color = mix(behind * (1.0 - f), inside, tir);
        }
    }

    // Camera under water: fog up to the first thing along the view ray.
    color = applyUnderwaterFog(color, dist);
    #endif

    #ifdef GODRAYS_ACTIVE
        if (isEyeInWater == 0) {
            // Shafts only where lit air sits next to shadowed air: the
            // centre's shadow deficit against the largest of 4 neighbours
            // across the shafts (low-res taps, no extra pass), each compared
            // over the shorter of the two marches (full-res depth taps).
            vec2 a = godrayAcross(texcoord);
            vec2 u0 = texcoord + a * GODRAY_NEAR, u1 = texcoord - a * GODRAY_NEAR;
            vec2 u2 = texcoord + a * GODRAY_FAR,  u3 = texcoord - a * GODRAY_FAR;
            vec4 taps = vec4(texture(colortex4, u0).a, texture(colortex4, u1).a,
                             texture(colortex4, u2).a, texture(colortex4, u3).a);
            vec4 tapDist = vec4(godrayTapDist(u0), godrayTapDist(u1), godrayTapDist(u2), godrayTapDist(u3));
            float shafts = godrayShafts(texture(colortex4, texcoord).a, taps, tapDist, dist);
            vec3 dirW = normalize(viewDirToWorld(viewPos0));
            color += godrayLight(shafts, dirW);
        }
    #endif

    outScene = vec4(color, 1.0);
}
