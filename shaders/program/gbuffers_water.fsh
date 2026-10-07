/*
    Translucent terrain (fragment stage).

    Water:
      WATER_DEFERRED (reflections or refraction on): writes nothing to the
        scene (alpha 0) and its surface data (wave normal, biome tint, sky
        light) to colortex1; composite1 shades it with refraction and
        reflections.
      otherwise (POTATO): shaded here — sky/cloud reflection, deep-water
        colour, sun glint — and alpha-blended.
    Glass, ice, slime, honey, portals: lit and blended into the scene here,
    and marked in colortex1 so the water pass leaves them alone.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/encoding.glsl"
#include "/lib/material.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/spaces.glsl"
#include "/lib/clouds.glsl"
#include "/lib/water.glsl"
#include "/lib/fog.glsl"
#define SHADOW_TAPS 2
#include "/lib/shadows.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normalW;
in vec3 playerPos;
flat in int blockId;
flat in float emission;

/* RENDERTARGETS: 2,1 */
layout(location = 0) out vec4 outScene;
layout(location = 1) out vec4 outData;

vec3 directShadow(vec3 n, float sky) {
    #ifdef SHADOWS
        vec3 sh = shadowVisibility(playerPos, n, ign(gl_FragCoord.xy)) * lightLeakGuard(sky);
        return mix(sh, vec3(skyShadowProxy(sky)), shadowEdgeFade(playerToShadowClip(playerPos)));
    #else
        return vec3(skyShadowProxy(sky));
    #endif
}

void main() {
    vec4 tex = texture(gtexture, texcoord);
    initSky();
    vec3 geoN = normalize(normalW);
    vec2 light = lightmapLevels(lmcoord);
    vec3 camWorld = cameraPosition + gbufferModelViewInverse[3].xyz;
    float dist = length(playerPos);

    if (blockId == ID_WATER) {
        vec3 n = waterWaveNormal(playerPos + camWorld, geoN, dist);
        #ifdef WATER_DEFERRED
            outScene = vec4(0.0);
            outData = packTranslucent(n, glcolor.rgb, light.y, MAT_WATER);
        #else
            vec3 v = normalize(-playerPos);
            if (dot(n, v) < 0.0) n = geoN;            // seen from below / behind a wave
            float f = waterFresnel(abs(dot(n, v)));
            vec3 r = reflect(-v, n);
            r.y = abs(r.y);
            vec3 refl = skyGradient(r);
            #ifdef CLOUDS
                float hd;
                vec4 cl = fadeClouds(flatClouds(camWorld, r, 1e6, hd), r, hd);
                refl = refl * (1.0 - cl.a) + cl.rgb;
            #endif
            refl = mix(ambientLight * 0.3 * light.y, refl, smoothstep(0.35, 0.9, light.y));
            // Vanilla's animated water texture adds a little surface detail.
            float detail = 0.85 + 0.3 * luminance(tex.rgb);
            vec3 deep = waterScatterColor(glcolor.rgb, light.y) * detail;
            vec3 col = mix(deep, refl, f);
            col += directLight * directShadow(geoN, light.y) * sunGlint(n, v, lightDir);
            col += srgbToLinear(glcolor.rgb) * blockLightCurve(light.x) * TORCH_COLOR * 0.15;
            col = applyAirFog(col, playerPos);
            col = applyUnderwaterFog(col, dist);
            outScene = vec4(col, mix(0.60, 1.0, f));
            outData = packTranslucent(n, glcolor.rgb, light.y, MAT_WATER);
        #endif
        return;
    }

    vec4 col = tex * vec4(glcolor.rgb, 1.0);
    if (col.a < alphaTestRef * 0.5) discard;

    Surface s;
    s.albedo = srgbToLinear(col.rgb);
    s.normal = geoN;
    s.geoNormal = geoN;
    s.light = light;
    s.ao = 1.0;
    s.smoothness = 0.0;
    s.emissive = emissiveMask(col.rgb, emission, false);
    s.flags = 0;
    vec3 lit = shadeSurface(s, directShadow(geoN, light.y), vec3(0.0), 0.0);
    lit = applyAirFog(lit, playerPos);
    #ifndef WATER_DEFERRED
        lit = applyUnderwaterFog(lit, dist);
    #endif

    outScene = vec4(lit, col.a);
    outData = packTranslucent(geoN, glcolor.rgb, light.y, MAT_GLASS);
}
