#version 330 compatibility

// Untextured geometry: leashes, block selection outline, chunk debug borders.

#include "/lib/settings.glsl"

out vec4 glcolor;

void main() {
    gl_Position = ftransform();
    glcolor = gl_Color;
}
