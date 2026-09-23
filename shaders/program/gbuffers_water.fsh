/*
    Translucent terrain (fragment stage).
    Glass-like blocks: lit and blended straight into the HDR scene.
    Water: simple lit tint for now (full water arrives in the water step).
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/encoding.glsl"
#include "/lib/material.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"

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

void main() {
    vec4 tex = texture(gtexture, texcoord);
    vec4 col = tex * vec4(glcolor.rgb, 1.0);
    if (col.a < alphaTestRef * 0.5) discard;

    initSky();
    vec3 n = normalize(normalW);
    vec2 light = lightmapLevels(lmcoord);

    Surface s;
    s.albedo = srgbToLinear(col.rgb);
    s.normal = n;
    s.geoNormal = n;
    s.light = light;
    s.ao = 1.0;
    s.smoothness = 0.0;
    s.emissive = emissiveMask(col.rgb, emission, false);
    s.flags = 0;
    vec3 lit = shadeSurface(s, vec3(skyShadowProxy(light.y)), vec3(0.0), 0.0);

    bool isWater = blockId == ID_WATER;
    outScene = vec4(lit, isWater ? max(col.a, 0.55) : col.a);
    outData = packTranslucent(n, glcolor.rgb, light.y, isWater ? MAT_WATER : MAT_GLASS);
}
