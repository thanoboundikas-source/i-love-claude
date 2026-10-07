/*
    Generated PBR from vanilla textures (no resource pack).

    Normals: the texture's brightness is treated as height (dark crevices are
    low). Gradients come from the four neighbouring texels at texel centres,
    wrapped inside the block's own sprite so nothing bleeds in from the next
    texture in the atlas. The result is a crisp per-pixel bevel that matches
    vanilla's pixel art; it fades out with distance (no sparkle).

    Specular: smoothness from simple, stable cues — metal blocks are shiny,
    flat low-contrast bright textures (concrete, quartz, polished stone) are
    semi-glossy, everything else is matte. Rain adds gloss separately.

    Requires common.glsl and the atlas sampler bound as gtexture.
*/

uniform ivec2 atlasSize;

vec2 wrapInSprite(vec2 uv, vec2 mid, vec2 halfSize) {
    vec2 lo = mid - halfSize;
    vec2 size = max(halfSize * 2.0, vec2(1e-6));
    return lo + mod(uv - lo, size);
}

float texHeight(sampler2D tex, vec2 uv) {
    vec4 c = textureLod(tex, uv, 0.0);
    return c.a < 0.1 ? 0.0 : luminance(c.rgb);
}

// Returns the bumped world normal and the local texture contrast (0..1).
// Each texel stays flat in its middle; its edges are bevelled toward the
// neighbour's height, so brighter texels read as slightly raised pixels.
vec3 generatedNormal(sampler2D tex, vec2 uv, vec2 mid, vec2 halfSize, vec3 n, vec3 t, vec3 b,
                     float dist, out float contrast) {
    vec2 texel = 1.0 / vec2(max(atlasSize, ivec2(1)));
    vec2 cell = uv / texel;
    vec2 c = (floor(cell) + 0.5) * texel;
    vec2 f = fract(cell);
    float h0 = texHeight(tex, c);
    float hL = texHeight(tex, wrapInSprite(c - vec2(texel.x, 0.0), mid, halfSize));
    float hR = texHeight(tex, wrapInSprite(c + vec2(texel.x, 0.0), mid, halfSize));
    float hU = texHeight(tex, wrapInSprite(c - vec2(0.0, texel.y), mid, halfSize));
    float hD = texHeight(tex, wrapInSprite(c + vec2(0.0, texel.y), mid, halfSize));
    contrast = saturate((abs(hR - hL) + abs(hD - hU) + abs(4.0 * h0 - hL - hR - hD - hU) * 0.5) * 1.5);

    #ifdef GENERATED_NORMALS
        const float BEVEL = 0.28;   // fraction of a texel that is bevelled
        float wL = 1.0 - smoothstep(0.0, BEVEL, f.x);
        float wR = smoothstep(1.0 - BEVEL, 1.0, f.x);
        float wU = 1.0 - smoothstep(0.0, BEVEL, f.y);
        float wD = smoothstep(1.0 - BEVEL, 1.0, f.y);
        // Slope across each edge: half the height step between the texels.
        float gu = (h0 - hL) * wL + (hR - h0) * wR;
        float gv = (h0 - hU) * wU + (hD - h0) * wD;
        float strength = float(NORMAL_STRENGTH) * 0.01 * 2.2 * (1.0 - smoothstep(10.0, 36.0, dist));
        return normalize(n - (t * gu + b * gv) * strength);
    #else
        return n;
    #endif
}

// Smoothness 0..1 and metal flag for a terrain texel.
float generatedSmoothness(vec3 albedoSrgb, float contrast, bool isMetal) {
    #ifdef GENERATED_SPECULAR
        float l = luminance(albedoSrgb);
        if (isMetal) return mix(0.55, 0.85, smoothstep(0.2, 0.7, l)) * (1.0 - contrast * 0.5);
        float flatness = 1.0 - smoothstep(0.02, 0.12, contrast);
        return flatness * smoothstep(0.25, 0.65, l) * 0.30;
    #else
        return 0.0;
    #endif
}
