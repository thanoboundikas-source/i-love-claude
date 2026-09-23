/*
    deferred1 — full resolution. Lights every opaque pixel from the G-buffer
    and draws the sky where nothing was drawn. Output: HDR scene (colortex2).
*/

#include "/lib/settings.glsl"
#include "/lib/buffers.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/spaces.glsl"
#include "/lib/encoding.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
#ifdef COLORED_LIGHT
    uniform sampler2D colortex6;
    const bool colortex6MipmapEnabled = true;
#endif

in vec2 texcoord;

/* RENDERTARGETS: 2 */
layout(location = 0) out vec4 outScene;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    float depth = texelFetch(depthtex0, px, 0).r;
    initSky();

    vec3 viewPos = screenToView(texcoord, depth);
    vec3 color;

    if (depth >= 1.0) {
        vec3 dir = normalize(viewDirToWorld(viewPos));
        color = skyColorFull(dir);
    } else {
        vec4 albedoAo = texelFetch(colortex0, px, 0);
        vec4 data = texelFetch(colortex1, px, 0);

        Surface s;
        s.albedo = srgbToLinear(albedoAo.rgb);
        s.ao = albedoAo.a;
        s.normal = octDecode(data.rg);
        s.geoNormal = s.normal;
        s.light = unpackLight(data.b);
        unpackMaterial(data.a, s.smoothness, s.emissive, s.flags);

        if ((s.flags & FLAG_HAND) != 0) viewPos = screenToViewHand(texcoord, depth);

        if ((s.flags & FLAG_UNLIT) != 0) {
            color = s.albedo * (1.0 + s.emissive * 3.0);
        } else {
            vec3 shadow = vec3(skyShadowProxy(s.light.y));

            vec3 tint = vec3(0.0);
            float tintWeight = 0.0;
            #ifdef COLORED_LIGHT
                // Nearby glowing blocks on screen colour the block light.
                // Two blurred mip levels: local detail + wider coverage.
                vec4 e1 = textureLod(colortex6, texcoord, 4.0);
                vec4 e2 = textureLod(colortex6, texcoord, 6.0);
                vec4 e = e1 * 0.6 + e2 * 0.4;
                tint = e.rgb / max(e.a, 1e-4);
                tintWeight = saturate(e.a * 24.0) * smoothstep(0.02, 0.2, s.light.x);
            #endif

            color = shadeSurface(s, shadow, tint, tintWeight);
        }
    }

    outScene = vec4(color, 1.0);
}
