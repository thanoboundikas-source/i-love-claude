/*
    Translucent terrain (vertex stage): water, stained glass, ice, slime,
    honey, nether portal. Water gets its own shading; the rest is lit like
    glass.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/spaces.glsl"

in vec2 mc_Entity;
in vec4 at_midBlock;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 normalW;
out vec3 playerPos;
flat out int blockId;
flat out float emission;

void main() {
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    playerPos = viewToPlayer(viewPos.xyz);
    // ftransform() keeps depth bit-identical with other passes drawing the
    // same geometry (glint over items, cracks over blocks).
    gl_Position = applyTaaJitter(ftransform());
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor  = gl_Color;
    normalW  = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
    blockId  = int(mc_Entity.x + 0.5);
    emission = clamp(at_midBlock.w / 15.0, 0.0, 1.0);
}
