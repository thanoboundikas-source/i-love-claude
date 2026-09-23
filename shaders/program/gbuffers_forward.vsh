/*
    Forward-shaded geometry (vertex stage): things Iris draws after the
    deferred lighting pass (particles, rain, translucent entities, held
    translucent items), plus overlays whose draw order is not guaranteed.
    Variants (set by the stub):
      FW_LIT      lightmap + sky lit (particles, translucent entities)
      FW_UNLIT    shown as-is (world border, unlit particles)
      FW_WEATHER  rain and snow
      FW_ADDITIVE glints: additive, unlit
      FW_BASIC    untextured lines (block outline, leashes)
      FW_GLOW     beacon beam: emissive
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/spaces.glsl"

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 playerPos;

void main() {
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    playerPos = viewToPlayer(viewPos.xyz);
    // ftransform() keeps depth bit-identical with other passes drawing the
    // same geometry (glint over items, cracks over blocks).
    gl_Position = applyTaaJitter(ftransform());
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor  = gl_Color;
}
