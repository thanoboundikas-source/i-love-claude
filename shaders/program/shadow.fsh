/*
    shadow — depth goes to shadowtex0/1 automatically; shadowcolor0 stores
    what translucent casters do to the light:
      water: rgb = biome water tint, a = 0 (clear, just tinted)
      glass: rgb = glass colour,      a = its opacity
    Opaque casters write their colour too; it is never read (shadowtex1
    already says they block the light).
*/

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/material.glsl"

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;
flat in int blockId;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outShadowColor;

void main() {
    vec4 c = texture(gtexture, texcoord) * vec4(glcolor.rgb, 1.0);
    if (blockId == ID_WATER) {
        outShadowColor = vec4(glcolor.rgb, 0.0);
    } else {
        if (c.a < 0.1) discard;
        outShadowColor = vec4(c.rgb, max(c.a, 0.01));
    }
}
