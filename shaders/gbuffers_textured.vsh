#version 330 compatibility

// Unlit textured geometry: world border, some particles, clouds (via fallback).

#include "/lib/settings.glsl"

out vec2 texcoord;
out vec4 glcolor;
out float viewDist;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor  = gl_Color;
    viewDist = length((gl_ModelViewMatrix * gl_Vertex).xyz);
}
