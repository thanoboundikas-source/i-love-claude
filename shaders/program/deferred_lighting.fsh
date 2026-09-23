/*
    deferred1 — full resolution. Lights every opaque pixel from the G-buffer,
    draws the sky where nothing was drawn, and composites the clouds on top.
    Output: HDR scene (colortex2).
*/

#include "/lib/settings.glsl"
#include "/lib/buffers.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/spaces.glsl"
#include "/lib/encoding.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/clouds.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
#ifdef CLOUDS_VOLUMETRIC
    uniform sampler2D colortex3;
#endif
#ifdef COLORED_LIGHT
    uniform sampler2D colortex6;
    const bool colortex6MipmapEnabled = true;
#endif

in vec2 texcoord;

/* RENDERTARGETS: 2 */
layout(location = 0) out vec4 outScene;

// Distance along a world ray at which it first reaches the cloud layer.
float cloudEntryDistance(vec3 origin, vec3 dir) {
    float y0 = cloudBaseHeight();
    float y1 = y0 + float(CLOUD_THICKNESS);
    if (origin.y >= y0 && origin.y <= y1) return 0.0;
    if (abs(dir.y) < 1e-5) return 1e9;
    float t = ((origin.y < y0 ? y0 : y1) - origin.y) / dir.y;
    return t > 0.0 ? t : 1e9;
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    float depth = texelFetch(depthtex0, px, 0).r;
    initSky();

    vec3 viewPos = screenToView(texcoord, depth);
    vec3 dir = normalize(viewDirToWorld(viewPos));
    vec3 camWorld = cameraPosition + gbufferModelViewInverse[3].xyz;
    float dist = 1e9;
    vec3 color;

    if (depth >= 1.0) {
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

        bool isHand = (s.flags & FLAG_HAND) != 0;
        if (isHand) viewPos = screenToViewHand(texcoord, depth);
        vec3 playerPos = viewToPlayer(viewPos);
        dist = isHand ? 0.0 : length(viewPos);

        if ((s.flags & FLAG_UNLIT) != 0) {
            color = s.albedo * (1.0 + s.emissive * 3.0);
        } else {
            vec3 shadow = vec3(skyShadowProxy(s.light.y));
            shadow *= cloudShadow(playerPos + camWorld);

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

    // Clouds in front of this pixel (terrain nearer than the cloud layer
    // never gets any, which also stops low-res cloud edges bleeding onto it).
    #ifdef CLOUDS
        if (dist > cloudEntryDistance(camWorld, dir)) {
            #ifdef CLOUDS_VOLUMETRIC
                vec4 cl = texture(colortex3, texcoord);
            #else
                float hitDist;
                vec4 cl = fadeClouds(flatClouds(camWorld, dir, dist, hitDist), dir, hitDist);
            #endif
            color = color * (1.0 - cl.a) + cl.rgb;
        }
    #endif

    outScene = vec4(color, 1.0);
}
