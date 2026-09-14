#version 330 compatibility

#include "/lib/settings.glsl"
#include "/lib/fog.glsl"

uniform sampler2D gtexture;
uniform float alphaTestRef;

in vec2 texcoord;
in vec4 glcolor;
in float viewDist;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    color = texture(gtexture, texcoord) * glcolor;
    if (color.a < alphaTestRef) discard;
    color.rgb = applyFog(color.rgb, viewDist);
}
