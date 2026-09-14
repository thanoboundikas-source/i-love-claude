#version 330 compatibility

// Lightmap-lit particles, rain/snow, and (via fallback) entities and hand.

#include "/lib/settings.glsl"

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out float viewDist;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor  = gl_Color;
    viewDist = length((gl_ModelViewMatrix * gl_Vertex).xyz);
}
