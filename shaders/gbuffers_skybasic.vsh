#version 330 compatibility

// Vanilla sky disc, horizon, void, and stars (passthrough in Phase 1;
// replaced by the gradient sky in Phase 2).

#include "/lib/settings.glsl"

out vec4 glcolor;

void main() {
    gl_Position = ftransform();
    glcolor = gl_Color;
}
