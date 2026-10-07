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
    #ifdef FILMIC_CURVE
        // The cinematic toe (its soft night/underground form, gate 1) darkens
        // these dim dimensions; give it back. With the 0.80 night toe, 1.10
        // keeps the Nether's usual 0.01-0.1 range within -4%..+8% of the old
        // identity curve (DECISIONS #84).
        lin *= 1.10;
    #endif
    vec3 c = linearToSrgb(tonemapSolstice(lin, 1.0, 1.0));
    outColor = vec4(saturate(c + ditherRGB8(gl_FragCoord.xy)), 1.0);
}
