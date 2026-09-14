#version 330 compatibility

// Phase 1: passthrough. The scaled-viewport (RENDER_SCALE) lighting and
// effect passes hook in here in Phase 2.

#include "/lib/settings.glsl"

uniform sampler2D colortex0;

in vec2 texcoord;

// Referenced so Iris registers the RENDER_SCALE option before Phase 2 uses it.
const float solsticeRenderScale = RENDER_SCALE;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    color = texture(colortex0, texcoord);
}
