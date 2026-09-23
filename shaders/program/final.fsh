/*
    final — tonemap the HDR scene and write the image to the screen.
    Always runs at the window resolution.
*/

#include "/lib/settings.glsl"
#include "/lib/buffers.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/tonemap.glsl"

uniform sampler2D colortex2;

in vec2 texcoord;

layout(location = 0) out vec4 outColor;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 hdr = texelFetch(colortex2, px, 0).rgb;

    vec3 c = tonemapSolstice(hdr);
    c = linearToSrgb(c) + ditherRGB8(gl_FragCoord.xy);
    outColor = vec4(saturate(c), 1.0);
}
