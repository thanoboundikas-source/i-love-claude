#version 330 compatibility

// Writes the finished frame to the screen. Always full window resolution.

#include "/lib/settings.glsl"

uniform sampler2D colortex0;

in vec2 texcoord;

layout(location = 0) out vec4 color;

void main() {
    color = texture(colortex0, texcoord);
}
