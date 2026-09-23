/*
    shadow — renders the world from the sun/moon into the shadow map.
    Positions are distorted exactly like lib/shadows.glsl reads them.
*/

#define SHADOW_PASS 1
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/shadows.glsl"

in vec2 mc_Entity;

out vec2 texcoord;
out vec4 glcolor;
flat out int blockId;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor  = gl_Color;
    blockId  = int(mc_Entity.x + 0.5);
    gl_Position = ftransform();
    gl_Position.xyz = distortShadow(gl_Position.xyz);
}
