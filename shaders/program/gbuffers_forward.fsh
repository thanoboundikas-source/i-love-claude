/*
    Forward-shaded geometry (fragment stage). See gbuffers_forward.vsh.

    Writes the lit colour to colortex2 (the HDR scene) and the plain albedo
    to colortex0. If Iris happens to draw this geometry *before* the deferred
    pass, colortex2 is overwritten there and the albedo copy is what shows;
    after the deferred pass the colortex2 write is what shows. Either order
    looks right.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/encoding.glsl"
#include "/lib/material.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/spaces.glsl"
#define SHADOW_TAPS 1
#include "/lib/shadows.glsl"
#include "/lib/water.glsl"
#include "/lib/fog.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 playerPos;

#ifdef FW_BASIC
    /* RENDERTARGETS: 2,0,1 */
#else
    /* RENDERTARGETS: 2,0 */
#endif
layout(location = 0) out vec4 outScene;
layout(location = 1) out vec4 outAlbedo;
#ifdef FW_BASIC
    layout(location = 2) out vec4 outData;
#endif

void main() {
    #ifdef FW_BASIC
        vec4 col = glcolor;
    #else
        vec4 col = texture(gtexture, texcoord) * glcolor;
    #endif
    if (col.a < alphaTestRef) discard;

    initSky();
    vec3 albedo = srgbToLinear(col.rgb);
    vec3 lit;

    #if defined FW_LIT
        vec2 light = lightmapLevels(lmcoord);
        Surface s;
        s.albedo = albedo;
        s.normal = lightDir;          // particles face the camera; light them evenly
        s.geoNormal = lightDir;
        s.light = light;
        s.ao = 1.0;
        s.smoothness = 0.0;
        s.emissive = 0.0;
        s.flags = 0;
        #ifdef SHADOWS
            vec3 shadow = shadowVisibility(playerPos, lightDir, 0.5) * lightLeakGuard(light.y);
            shadow = mix(shadow, vec3(skyShadowProxy(light.y)), shadowEdgeFade(playerToShadowClip(playerPos)));
        #else
            vec3 shadow = vec3(skyShadowProxy(light.y) * 0.8);
        #endif
        lit = shadeSurface(s, shadow, vec3(0.0), 0.0);
    #elif defined FW_WEATHER
        vec2 light = lightmapLevels(lmcoord);
        lit = albedo * (ambientLight * 0.9 + directLight * 0.25 + blockLightCurve(light.x) * TORCH_COLOR * 0.5);
        col.a *= 0.55;
    #elif defined FW_GLOW
        lit = albedo * 3.0;
    #else
        // FW_UNLIT, FW_ADDITIVE, FW_BASIC: as authored.
        lit = albedo;
    #endif

    #if defined FW_LIT || defined FW_WEATHER || defined FW_UNLIT
        lit = applyAirFog(lit, playerPos);
        #ifndef WATER_DEFERRED
            lit = applyUnderwaterFog(lit, length(playerPos));
        #endif
    #endif
    outScene = vec4(lit, col.a);
    outAlbedo = vec4(col.rgb, col.a);
    #ifdef FW_BASIC
        outData = packOpaque(vec3(0.0, 1.0, 0.0), vec2(1.0), 0.0, 0.0, FLAG_UNLIT);
    #endif
}
