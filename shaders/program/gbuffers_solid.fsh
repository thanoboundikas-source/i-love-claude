/*
    Opaque geometry -> G-buffer (fragment stage). See gbuffers_solid.vsh.
    Writes:
      colortex0  albedo (sRGB) + vanilla AO
      colortex1  normal, light levels, material (lib/encoding.glsl)
      colortex6  emissive colour for the coloured block-light tint
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/encoding.glsl"
#include "/lib/material.glsl"
#include "/lib/pbr.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;
#ifdef GB_ENTITY
    uniform vec4 entityColor;
#endif

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normalW;
#ifdef GB_TERRAIN
    flat in int blockId;
    flat in float emission;
    flat in vec2 spriteMid;
    flat in vec2 spriteHalf;
    in vec3 tangentW;
    flat in float tangentSign;
    in float viewDist;
#endif

#ifdef GB_DAMAGE
    /* RENDERTARGETS: 0 */
    layout(location = 0) out vec4 outAlbedo;
#else
    #ifdef COLORED_LIGHT
        /* RENDERTARGETS: 0,1,6 */
    #else
        /* RENDERTARGETS: 0,1 */
    #endif
    layout(location = 0) out vec4 outAlbedo;
    layout(location = 1) out vec4 outData;
    #ifdef COLORED_LIGHT
        layout(location = 2) out vec4 outEmissive;
    #endif
#endif

void main() {
    vec4 tex = texture(gtexture, texcoord);

    #ifdef GB_DAMAGE
        // Vanilla blends cracks as 2*src*dst: grey 0.5 = no change. Alpha 0.5
        // keeps the AO stored in colortex0.a intact.
        if (tex.a < 0.1) discard;
        outAlbedo = vec4(tex.rgb, 0.5);
    #else
        vec3 albedo = tex.rgb * glcolor.rgb;
        float alpha = tex.a;
        float ao = 1.0;
        #ifdef GB_TERRAIN
            ao = glcolor.a;         // separateAo=true: vanilla AO lives here
        #else
            alpha *= glcolor.a;
        #endif
        if (alpha < alphaTestRef) discard;

        #ifdef GB_ENTITY
            albedo = mix(albedo, entityColor.rgb, entityColor.a);
        #endif

        vec2 light = lightmapLevels(lmcoord);
        int flags = 0;
        float emissive = 0.0;
        float smoothness = 0.0;

        #ifdef GB_TERRAIN
            if (blockId == ID_LEAVES || blockId == ID_PLANT) flags |= FLAG_SSS;
            emissive = emissiveMask(albedo, emission, blockId == ID_FULL_GLOW);
        #endif
        #ifdef GB_HAND
            flags |= FLAG_HAND;
        #endif
        #ifdef GB_GLOW
            flags |= FLAG_UNLIT;
            emissive = 1.0;
        #endif

        vec3 n = normalize(normalW);

        #if defined GB_TERRAIN && (defined GENERATED_NORMALS || defined GENERATED_SPECULAR)
            if ((flags & FLAG_SSS) == 0 && emissive < 0.5) {
                vec3 t = normalize(tangentW - n * dot(tangentW, n));
                vec3 b = cross(t, n) * tangentSign;
                float contrast;
                n = generatedNormal(gtexture, texcoord, spriteMid, spriteHalf, n, t, b, viewDist, contrast);
                bool metal = blockId == ID_METAL;
                smoothness = generatedSmoothness(albedo, contrast, metal);
                if (metal && smoothness > 0.0) flags |= FLAG_METAL;
            }
        #endif

        outAlbedo = vec4(albedo, ao);
        outData = packOpaque(n, light, smoothness, emissive, flags);
        #ifdef COLORED_LIGHT
            #ifdef GB_TERRAIN
                outEmissive = vec4(srgbToLinear(albedo) * emissive, emissive);
            #else
                outEmissive = vec4(0.0);
            #endif
        #endif
    #endif
}
