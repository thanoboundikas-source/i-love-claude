/*
    final — sharpen, local contrast, bloom, vignette, time-of-day exposure,
    tonemap + grade, write to the screen (window resolution).

    Bloom costs no extra pass: Iris builds a mip chain of the HDR scene just
    before this program (colortex2MipmapEnabled) and five blurred levels are
    gathered here with a small tent each. A threshold (1.8, soft knee 0.3, so
    nothing below 1.5 blooms) means only real highlights bloom (sun,
    emissive blocks ~3, lava, glints). The sky (0.5-1.3) and even the
    brightest sunlit diffuse surfaces (snow, white concrete, quartz, sand:
    up to ~1.4) never do, so snowy and desert biomes get no milky veil.
    Level sizes follow the window height (1080p reference).
*/

#include "/lib/settings.glsl"
#include "/lib/buffers.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/tonemap.glsl"

// Brightness given back by FILMIC_CURVE at night / golden hour / a
// mid-height sun (see below).
const float FILMIC_NIGHT_GAIN = 1.25;    // night / underground (the toe is gentle there)
#if GOLDEN_LIFT == 0
    // No low-sun key lift: the exposure carries golden hour alone (#69).
    const float FILMIC_GOLDEN_GAIN = 1.40;
#else
    const float FILMIC_GOLDEN_GAIN = 1.12;    // sun above ~3 degrees (the key lift carries it)
#endif
const float FILMIC_HORIZON_GAIN = 1.40;   // sun at the horizon, where the key has faded out
const float FILMIC_MIDSUN_GAIN = 1.25;    // mid-height sun, peak ~20 degrees, none from ~53 (noon unchanged)

uniform sampler2D colortex2;
#ifdef SPLIT_TONING
    uniform sampler2D depthtex0;
#endif
#if defined BLOOM || defined LOCAL_CONTRAST
    const bool colortex2MipmapEnabled = true;
#endif

in vec2 texcoord;

layout(location = 0) out vec4 outColor;

#if defined BLOOM || defined LOCAL_CONTRAST
// 4-tap tent on one mip level (smooths the box-filtered mips).
vec3 mipTent(float lod) {
    vec2 texel = exp2(lod) / vec2(viewWidth, viewHeight);
    vec3 s = textureLod(colortex2, texcoord + vec2( 0.5,  0.5) * texel, lod).rgb;
    s     += textureLod(colortex2, texcoord + vec2(-0.5,  0.5) * texel, lod).rgb;
    s     += textureLod(colortex2, texcoord + vec2( 0.5, -0.5) * texel, lod).rgb;
    s     += textureLod(colortex2, texcoord + vec2(-0.5, -0.5) * texel, lod).rgb;
    return s * 0.25;
}
#endif

#ifdef BLOOM
const float BLOOM_THRESHOLD = 1.8;
const float BLOOM_KNEE = 0.3;
vec3 bloomKnee(vec3 s) {
    float l = luminance(s);
    float soft = clamp(l - BLOOM_THRESHOLD + BLOOM_KNEE, 0.0, 2.0 * BLOOM_KNEE);
    soft = soft * soft / (4.0 * BLOOM_KNEE);
    return s * (max(soft, l - BLOOM_THRESHOLD) / max(l, 1e-4));
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

    #if defined BLOOM || defined LOCAL_CONTRAST
        float lodBias = max(log2(viewHeight / 1080.0), 0.0);
        vec3 mid5 = mipTent(5.0 + lodBias);
    #endif

    #ifdef LOCAL_CONTRAST
        // Darken-only local contrast against the ~50 px neighbourhood mean:
        // shadows next to bright sky or sunlit ground get deeper, nothing is
        // ever brightened (no halos on the sky).
        float lp = luminance(hdr);
        float lm = luminance(mid5);
        float k = float(LOCAL_CONTRAST_STRENGTH) * 0.01 * 0.25;
        hdr *= exp2(clamp(log2((lp + 0.02) / (lm + 0.02)) * k, -0.25, 0.0));
    #endif

    #ifdef BLOOM
        vec3 bl = bloomKnee(mipTent(2.0 + lodBias))
                + bloomKnee(mipTent(3.0 + lodBias))
                + bloomKnee(mipTent(4.0 + lodBias))
                + bloomKnee(mid5)
                + bloomKnee(mipTent(6.0 + lodBias));
        hdr += bl * (0.2 * 0.20 * float(BLOOM_STRENGTH) * 0.01);
    #endif

    #ifdef VIGNETTE
        vec2 q = (texcoord - 0.5) * vec2(aspectRatio, 1.0);
        float r2 = dot(q, q) / (0.25 * (aspectRatio * aspectRatio + 1.0));
        hdr *= 1.0 - float(VIGNETTE_STRENGTH) * 0.0025 * r2 * r2;
    #endif

    // Night / underground gate for the low-light desaturation.
    float sunH = sin(sunAngle * TAU) * cos(radians(sunPathRotation));
    float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
    float nightGate = 1.0 - smoothstep(-0.20, 0.03, sunH);
    float lowLightGate = max(nightGate, 1.0 - smoothstep(0.05, 0.40, eyeSky));
    #ifdef FILMIC_CURVE
        // The toe darkens dim scenes most; give golden hour and night back
        // their brightness so only their contrast changes (a fixed,
        // time-of-day exposure, not eye adaptation).
        // Underground counts as night, so a torch-lit cave looks the same at
        // noon and at midnight. FULLBRIGHT halves the toe, so half the gain.
        // Golden hour (sun height 0-0.40): the low-sun key lift in
        // lighting.glsl lights the ground, so only a small gain is needed
        // (x1.12; x1.40 with GOLDEN_LIFT 0). Within ~2 degrees of the
        // horizon the key fades out (sky.glsl, sun height 0-0.05), so the
        // gain rises to x1.40 as it goes and blends into the night gain
        // through twilight with no dip.
        // Mid-height sun (about 10-45 degrees): flat ground gets only
        // sin(elevation) of the key once the golden lift and gain fade, and
        // the frame sat under vanilla for hours of every day (DECISIONS
        // #88; lighting.glsl keeps a partial lift there too). FILMIC_MIDSUN_GAIN fades in as the golden gain
        // fades out and away again toward noon: in total x1.15 at 6
        // degrees, x1.21 at 14, x1.24 at 20, x1.13 at 35, x1.03 at 45 and
        // x1.00 from ~53 (noon with the default sun path is 60). Off at
        // night and underground (lowLightGate), so caves are unchanged.
        float lowGain = FILMIC_NIGHT_GAIN;
        #ifdef FULLBRIGHT
            lowGain = 1.0 + (FILMIC_NIGHT_GAIN - 1.0) * 0.5;
        #endif
        float goldenF = 1.0 - smoothstep(0.0, 0.40, sunH);
        float goldenGate = goldenF * (1.0 - lowLightGate);
        float goldenGain = mix(FILMIC_HORIZON_GAIN, FILMIC_GOLDEN_GAIN, smoothstep(0.02, 0.055, sunH));
        float midGate = (1.0 - goldenF) * (1.0 - smoothstep(0.35, 0.80, sunH)) * (1.0 - lowLightGate);
        hdr *= mix(1.0, lowGain, lowLightGate) * mix(1.0, goldenGain, goldenGate)
             * mix(1.0, FILMIC_MIDSUN_GAIN, midGate);
    #endif

    // Split toning never touches the sky, the sun, the moon or clouds seen
    // against the sky (depth 1; clouds composited over far terrain, which
    // has depth < 1, are toned). TAA jitters depthtex0 every frame but
    // colortex2 is already resolved, so a 1-pixel mask would flip on and
    // off along every silhouette at up to 7.5 Hz. The mask is the average
    // of a 3x3 box of depth tests: a jitter that moves an edge by a pixel
    // flips one row (or a diagonal) of it, at most 3 of the 9 taps, so the
    // tint on the pixels next to a silhouette changes by at most 1/3 (~1
    // level at the default strength; a 5-tap plus still flips 3 of its 5
    // taps on the edge row, DECISIONS #91). Pure sky and pure geometry are
    // unchanged.
    float surface = 1.0;
    #ifdef SPLIT_TONING
        float geo = 0.0;
        for (int dy = -1; dy < 2; dy++) {
            for (int dx = -1; dx < 2; dx++) {
                geo += texelFetch(depthtex0, clamp(px + ivec2(dx, dy), ivec2(0), maxP), 0).r < 1.0 ? 1.0 : 0.0;
            }
        }
        surface = geo * (1.0 / 9.0);
    #endif
    vec3 col = tonemapSolstice(hdr, lowLightGate, surface);
    col = linearToSrgb(col) + ditherRGB8(gl_FragCoord.xy);
    outColor = vec4(saturate(col), 1.0);
}
