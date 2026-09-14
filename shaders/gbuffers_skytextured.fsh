#version 330 compatibility

#include "/lib/settings.glsl"

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    color = texture(gtexture, texcoord) * glcolor;
}
