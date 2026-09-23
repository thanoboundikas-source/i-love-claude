/*
    final — sharpen, bloom, tonemap, write to the screen (window resolution).

    Bloom costs no extra pass: Iris builds a mip chain of the HDR scene just
    before this program (colortex2MipmapEnabled) and five blurred levels are
    gathered here with a small tent each (smooths the box-filtered mips). A
    soft knee keeps ordinary midtones from blooming, so only bright things
    (sun, lava, glowstone, sky around the sun) glow and the image stays clean.
*/

#include "/lib/settings.glsl"
#include "/lib/buffers.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/tonemap.glsl"

uniform sampler2D colortex2;
#ifdef BLOOM
    const bool colortex2MipmapEnabled = true;
#endif

in vec2 texcoord;

layout(location = 0) out vec4 outColor;

#ifdef BLOOM
vec3 bloomLevel(float lod) {
    vec2 texel = exp2(lod) / vec2(viewWidth, viewHeight);
    vec3 s = textureLod(colortex2, texcoord + vec2( 0.5,  0.5) * texel, lod).rgb;
    s     += textureLod(colortex2, texcoord + vec2(-0.5,  0.5) * texel, lod).rgb;
    s     += textureLod(colortex2, texcoord + vec2( 0.5, -0.5) * texel, lod).rgb;
    s     += textureLod(colortex2, texcoord + vec2(-0.5, -0.5) * texel, lod).rgb;
    s *= 0.25;
    float l = luminance(s);
    return s * (l / (l + 0.9));   // soft knee
}

vec3 bloom() {
    vec3 b = bloomLevel(2.0) * 0.30
           + bloomLevel(3.0) * 0.26
           + bloomLevel(4.0) * 0.20
           + bloomLevel(5.0) * 0.14
           + bloomLevel(6.0) * 0.10;
    return b;
}
#endif

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    ivec2 maxP = ivec2(viewWidth, viewHeight) - 1;
    vec3 hdr = texelFetch(colortex2, px, 0).rgb;

    #ifdef SHARPEN
        // Contrast-limited unsharp mask on a 5-tap cross: restores the
        // softness TAA adds, clamped to the neighbours so it never halos.
        vec3 a = texelFetch(colortex2, clamp(px + ivec2( 1, 0), ivec2(0), maxP), 0).rgb;
        vec3 b = texelFetch(colortex2, clamp(px + ivec2(-1, 0), ivec2(0), maxP), 0).rgb;
        vec3 c = texelFetch(colortex2, clamp(px + ivec2( 0, 1), ivec2(0), maxP), 0).rgb;
        vec3 d = texelFetch(colortex2, clamp(px + ivec2( 0,-1), ivec2(0), maxP), 0).rgb;
        vec3 lo = min(min(a, b), min(c, d));
        vec3 hi = max(max(a, b), max(c, d));
        vec3 avg = (a + b + c + d) * 0.25;
        float amount = float(SHARPEN_AMOUNT) * 0.01 * 0.6;
        hdr = clamp(hdr + (hdr - avg) * amount, min(lo, hdr), max(hi, hdr));
    #endif

    #ifdef BLOOM
        hdr += bloom() * (0.14 * float(BLOOM_STRENGTH) * 0.01);
    #endif

    vec3 col = tonemapSolstice(hdr);
    col = linearToSrgb(col) + ditherRGB8(gl_FragCoord.xy);
    outColor = vec4(saturate(col), 1.0);
}
