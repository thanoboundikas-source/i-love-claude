/*
    Nether / End fallback pipeline (fragment stage). See dim_forward.vsh.
    Writes linear light to colortex0 (RGBA16F here, see the format line);
    dim_final tonemaps it. Sky pixels keep the vanilla fog clear colour.

const int colortex0Format = RGBA16F;
*/

// Cleared to alpha 0: dim_final shows the fog colour wherever nothing drew
// (depth can't be used: the End sky box does not write depth).
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform float alphaTestRef;
uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;
uniform float nightVision;
uniform int isEyeInWater;
uniform mat4 gbufferModelViewInverse;
#ifdef DF_ENTITY
    uniform vec4 entityColor;
#endif

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 viewPos;
in vec3 viewNormal;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    #ifdef DF_SKYBASIC
        outColor = vec4(srgbToLinear(glcolor.rgb), glcolor.a);
        return;
    #endif
    vec4 tex = texture(gtexture, texcoord);
    vec4 col = tex * vec4(glcolor.rgb, 1.0);
    float alpha = tex.a;
    #ifdef DF_LIT
        // separateAo = true: vanilla AO arrives in the vertex alpha on terrain.
        col.rgb *= glcolor.a > 0.0 && glcolor.a < 1.0 ? glcolor.a : 1.0;
    #else
        alpha *= glcolor.a;
    #endif
    if (alpha < alphaTestRef) discard;
    #ifdef DF_ENTITY
        col.rgb = mix(col.rgb, entityColor.rgb, entityColor.a);
    #endif

    vec3 albedo = srgbToLinear(col.rgb);
    vec3 lit;

    #if defined DF_LIT || defined DF_ENTITY
        // Vanilla's lightmap already carries the dimension's ambient light
        // and warm block light, so brightness stays vanilla-faithful.
        vec3 lm = srgbToLinear(texture(lightmap, lmcoord).rgb);
        vec3 n = mat3(gbufferModelViewInverse) * viewNormal;
        float face = 0.78 + 0.22 * n.y - 0.06 * abs(n.x);
        #ifdef DIM_NETHER
            vec3 tint = vec3(1.05, 0.92, 0.84);
        #else
            vec3 tint = vec3(0.92, 0.90, 1.08);
        #endif
        vec3 light = lm * tint * face * 1.15;
        #ifdef FULLBRIGHT
            light = max(light, vec3(0.20, 0.19, 0.22));
        #endif
        light = max(light, vec3(0.2) * nightVision);
        lit = albedo * light;
    #else
        lit = albedo;
    #endif

    // Vanilla-style linear fog toward the dimension's fog colour.
    #if !defined DF_SKY && !defined DF_SKYBASIC
        float dist = length(viewPos);
        float f = smoothstep(fogStart, max(fogEnd, fogStart + 1.0), dist);
        if (isEyeInWater == 2) f = 1.0 - exp(-dist * 0.9);
        lit = mix(lit, srgbToLinear(fogColor), f);
    #endif

    outColor = vec4(lit, alpha);
}
