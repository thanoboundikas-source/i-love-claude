/*
    Opaque geometry -> G-buffer (vertex stage).
    Specialised by the stub that includes it:
      GB_TERRAIN   static blocks: block IDs, emission, vanilla AO in alpha
      GB_ENTITY    entities: hurt/flash overlay colour
      GB_HAND      held items: flagged, no shadow-map lookup later
      GB_BLOCK     block entities (chests, signs, beds...)
      GB_GLOW      always-glowing overlays (spider eyes, lightning)
      GB_DAMAGE    block-breaking cracks: modulate albedo only
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/spaces.glsl"

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 normalW;

#ifdef GB_TERRAIN
    in vec2 mc_Entity;
    in vec4 at_midBlock;
    flat out int blockId;
    flat out float emission;
#endif

void main() {
    gl_Position = applyTaaJitter(ftransform());
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor  = gl_Color;
    normalW  = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);

    #ifdef GB_TERRAIN
        blockId  = int(mc_Entity.x + 0.5);
        emission = clamp(at_midBlock.w / 15.0, 0.0, 1.0);
    #endif
}
