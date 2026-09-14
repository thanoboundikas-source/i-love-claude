#version 330 compatibility

#include "/lib/settings.glsl"

in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    color = glcolor;
}
