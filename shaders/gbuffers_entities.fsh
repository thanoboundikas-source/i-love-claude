#version 330 compatibility

#include "/lib/settings.glsl"
#include "/lib/lightmap.glsl"
#include "/lib/fog.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform float alphaTestRef;
uniform vec4 entityColor;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in float viewDist;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    color = texture(gtexture, texcoord) * glcolor;
    color.rgb = mix(color.rgb, entityColor.rgb, entityColor.a);
    if (color.a < alphaTestRef) discard;
    color.rgb *= sampleLightmap(lightmap, lmcoord);
    color.rgb = applyFog(color.rgb, viewDist);
}
