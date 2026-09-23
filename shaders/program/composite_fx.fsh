/*
    composite — scaled effects pass (colortex4, size = RENDER_SCALE x
    HALF_RES_FX, set in shaders.properties).
      rgb: water reflection colour (water pixels only)
      a:   godrays (added in the godrays step)
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/spaces.glsl"
#include "/lib/encoding.glsl"
#include "/lib/sky.glsl"
#include "/lib/clouds.glsl"
#include "/lib/water.glsl"

uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

#include "/lib/reflections.glsl"

in vec2 texcoord;

/* RENDERTARGETS: 4 */
layout(location = 0) out vec4 outFx;

void main() {
    initSky();
    vec4 fx = vec4(0.0);
    ivec2 fullSize = textureSize(depthtex0, 0);
    ivec2 fullPx = clamp(ivec2(texcoord * vec2(fullSize)), ivec2(0), fullSize - 1);
    float d0 = texelFetch(depthtex0, fullPx, 0).r;
    float d1 = texelFetch(depthtex1, fullPx, 0).r;

    #ifdef WATER_REFLECTIONS
        if (d0 < d1) {
            vec4 data = texelFetch(colortex1, fullPx, 0);
            if (translucentMaterial(data) == MAT_WATER) {
                vec3 tint; float sky;
                unpackTranslucent(data, tint, sky);
                vec3 nWorld = octDecode(data.rg);
                vec3 viewPos = screenToView(texcoord, d0);
                vec3 nView = worldDirToView(nWorld);
                vec3 v = normalize(viewPos);
                if (dot(nView, -v) < 0.0) nView = -nView;
                vec3 rView = reflect(v, nView);
                vec3 rWorld = viewDirToWorld(rView);
                vec3 camWorld = cameraPosition + gbufferModelViewInverse[3].xyz;

                vec3 miss = reflectionMiss(rView, rWorld, sky, camWorld);
                vec2 hitUV;
                float jitter = ignAnimated(gl_FragCoord.xy, frameCounter);
                if (isEyeInWater == 0 && traceSSR(viewPos, rView, jitter, hitUV)) {
                    vec3 hit = texture(colortex2, hitUV).rgb;
                    fx.rgb = mix(miss, hit, ssrEdgeFade(hitUV));
                } else {
                    fx.rgb = miss;
                }
            }
        }
    #endif

    outFx = fx;
}
