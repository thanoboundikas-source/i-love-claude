/*
    deferred — volumetric blocky clouds at RENDER_SCALE resolution
    (colortex3 is sized by size.buffer in shaders.properties).
    Output: premultiplied cloud colour + opacity, composited in deferred1.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/spaces.glsl"
#include "/lib/sky.glsl"
#include "/lib/clouds.glsl"

uniform sampler2D depthtex0;

in vec2 texcoord;

/* RENDERTARGETS: 3 */
layout(location = 0) out vec4 outClouds;

void main() {
    #ifdef CLOUDS_VOLUMETRIC
        initSky();

        // Farthest depth under this low-res pixel, so clouds seen past a
        // terrain edge are not lost; deferred1 masks them back off terrain
        // that is nearer than the cloud layer.
        vec2 fullSize = vec2(textureSize(depthtex0, 0));
        vec2 lowTexel = 1.0 / (fullSize * CLOUD_SCALE);
        ivec2 maxPx = ivec2(fullSize) - 1;
        float d = 0.0;
        d = max(d, texelFetch(depthtex0, clamp(ivec2((texcoord + vec2(-0.25, -0.25) * lowTexel) * fullSize), ivec2(0), maxPx), 0).r);
        d = max(d, texelFetch(depthtex0, clamp(ivec2((texcoord + vec2( 0.25, -0.25) * lowTexel) * fullSize), ivec2(0), maxPx), 0).r);
        d = max(d, texelFetch(depthtex0, clamp(ivec2((texcoord + vec2(-0.25,  0.25) * lowTexel) * fullSize), ivec2(0), maxPx), 0).r);
        d = max(d, texelFetch(depthtex0, clamp(ivec2((texcoord + vec2( 0.25,  0.25) * lowTexel) * fullSize), ivec2(0), maxPx), 0).r);

        vec3 viewPos = screenToView(texcoord, d);
        vec3 dir = normalize(viewDirToWorld(viewPos));
        float maxDist = d >= 1.0 ? 1e6 : length(viewPos);
        vec3 origin = cameraPosition + gbufferModelViewInverse[3].xyz;

        float hitDist;
        vec4 c = traceClouds(origin, dir, maxDist, hitDist);
        outClouds = fadeClouds(c, dir, hitDist);
    #else
        outClouds = vec4(0.0);
    #endif
}
