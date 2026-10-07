/*
    Nether / End fallback pipeline (vertex stage). A small forward pipeline:
    vanilla lightmap lighting, simple face shading, vanilla-style fog and the
    Solstice tonemap, so these dimensions look clean and never crash until
    their full versions are built. Variants (set by the stubs):
      DF_LIT     lightmap-lit geometry (terrain, block entities, particles)
      DF_ENTITY  entities (hurt/flash colour)
      DF_UNLIT   unlit textured / untextured geometry, glints, eyes
      DF_SKY     sky geometry (the End sky texture), drawn as-is
    DIM_NETHER / DIM_END select the dimension tint.
*/

#include "/lib/settings.glsl"

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 viewPos;
out vec3 viewNormal;

void main() {
    vec4 vp = gl_ModelViewMatrix * gl_Vertex;
    viewPos = vp.xyz;
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor  = gl_Color;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);
}
