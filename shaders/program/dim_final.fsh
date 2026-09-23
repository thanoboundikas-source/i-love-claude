/*
    Nether / End final: same tonemap and grading as the Overworld. Pixels
    nothing drew on show vanilla's fog colour (the colortex0 clear colour).
*/

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/tonemap.glsl"

uniform sampler2D colortex0;
uniform vec3 fogColor;

in vec2 texcoord;

layout(location = 0) out vec4 outColor;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec4 scene = texelFetch(colortex0, px, 0);
    // Drawn geometry was blended over a transparent black clear; whatever is
    // left uncovered shows the vanilla fog colour behind it.
    vec3 lin = scene.rgb + srgbToLinear(fogColor) * (1.0 - saturate(scene.a));
    vec3 c = linearToSrgb(tonemapSolstice(lin));
    outColor = vec4(saturate(c + ditherRGB8(gl_FragCoord.xy)), 1.0);
}
