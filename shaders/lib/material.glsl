/*
    Per-surface material helpers used by the gbuffers programs.
    Block IDs come from block.properties (mc_Entity.x).
*/

const int ID_WATER      = 1;
const int ID_LEAVES     = 10;
const int ID_PLANT      = 11;
const int ID_METAL      = 20;
const int ID_FULL_GLOW  = 30;

// Lightmap coordinate (0.5/16 .. 15.5/16) to 0..1 light level.
vec2 lightmapLevels(vec2 lmcoord) {
    return clamp((lmcoord * 16.0 - 0.5) / 15.0, 0.0, 1.0);
}

// How strongly a texel glows (0..1). `emission` is the block's own light
// level / 15 (at_midBlock.w). Blocks tagged "whole texture glows" glow
// everywhere; others (torches, lanterns, lit ores) only in their bright or
// saturated texels, so the torch stick and the stone around ore stay unlit.
float emissiveMask(vec3 albedoSrgb, float emission, bool wholeTexture) {
    if (emission <= 0.0) return 0.0;
    if (wholeTexture) return emission;
    float maxc = max(albedoSrgb.r, max(albedoSrgb.g, albedoSrgb.b));
    float minc = min(albedoSrgb.r, min(albedoSrgb.g, albedoSrgb.b));
    float sat = (maxc - minc) / max(maxc, 1e-4);
    float bright = smoothstep(0.55, 0.85, maxc);
    float colourful = smoothstep(0.25, 0.55, sat) * smoothstep(0.35, 0.6, maxc);
    float hot = smoothstep(0.88, 0.97, maxc);
    return emission * saturate(max(bright * (0.35 + 0.65 * smoothstep(0.1, 0.4, sat)), max(colourful, hot)));
}
