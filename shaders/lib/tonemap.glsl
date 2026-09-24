/*
    Hue-preserving cinematic tonemap + grade.

    The curve is applied to the brightest channel and the colour is scaled by
    the same factor, so hue and saturation survive. FILMIC_CURVE adds a real
    toe (deeper blacks that keep their detail) and a soft shoulder, pivoting
    at 0.18 so midtone brightness stays vanilla, plus a gentler toe and a
    moonlit blue low-light tint at night / underground. Very hot highlights
    (sun, lava cores) drift toward white. SPLIT_TONING warms bright warm-coloured
    surfaces and cools neutral shadows on the daytime surface only (never
    the sky, never caves or night, so torch light is left alone).

    lowLightGate: 1 = night / underground (full low-light desaturation),
    0 = daytime surface (almost none).
*/

const float TM_PIVOT = 0.18;
// Night / underground low-light tint for non-warm pixels (luminance 0.95:
// at 1.0 the bluer night measured 1% brighter in sRGB than before).
const vec3 MOONLIT_TINT = vec3(0.76, 0.95, 1.48);

float shoulderCurve(float x, float start) {
    if (x <= start) return x;
    float w = 1.0 - start;
    return start + w * (1.0 - exp(-(x - start) / w));
}

// Rational toe: log-log slope 1 at black (detail kept), steeper in the
// shadows, 1 again in the highlights, pivot 0.18 unchanged. a is the slope
// at black: 0.2 (~2 stops deeper) on the daytime surface, 0.80 (~0.3 stop)
// at night / underground (gate = 1), where a deep toe turned every
// moon-shaded side and the edge of every torch pool pure black (0.55 still
// crushed moon-shaded dirt sides to ~8/255, DECISIONS #84).
float toeCurve(float x, float gate) {
    float t = 0.04 * float(FILMIC_CONTRAST) * 0.01;
    #ifdef FULLBRIGHT
        t *= 0.5;
    #endif
    float a = mix(0.2, 0.80, gate);
    return x * (x + a * t) / (x + t) * ((TM_PIVOT + t) / (TM_PIVOT + a * t));
}

// Daytime surface only (gate = night / underground): torch- and lava-lit
// caves and the night sky are left alone. surface = 0 for the sky, the
// sun, the moon and clouds seen against the sky (depth 1 in final; final
// averages the mask over a 3x3 box so TAA jitter cannot flicker it, and
// clouds composited over far terrain count as surface), so the sunset band
// and the sun halo are never warmed or cooled. Already-blue surface pixels
// are never cooled further.
vec3 splitTone(vec3 c, float gate, float surface) {
    float st = float(SPLIT_TONE_STRENGTH) * 0.01 * (1.0 - gate) * surface;
    float L = luminance(c);
    float warmth = saturate((c.r - c.b) / max(c.r, 1e-4));
    float blueness = saturate((c.b - c.r) / max(c.b, 1e-4));
    float hiW = smoothstep(0.18, 0.70, L) * saturate(2.0 * warmth);
    float loW = (1.0 - smoothstep(0.015, 0.25, L)) * (1.0 - warmth) * (1.0 - blueness);
    c *= mix(vec3(1.0), vec3(1.058, 0.993, 0.898), hiW * st);
    c *= mix(vec3(1.0), vec3(0.932, 1.003, 1.175), loW * st * 0.8);
    return c;
}

// surface: 1 = world geometry, 0 = sky, in between along silhouettes
// (only split toning uses it).
vec3 tonemapSolstice(vec3 hdr, float lowLightGate, float surface) {
    hdr = max(hdr, vec3(0.0)) * (float(EXPOSURE) * 0.01);

    // Low-light shift (the eye loses colour in the dark): dim pixels move
    // toward a cool tint. By day (gate 0) it is gentle and unchanged. At
    // night and underground (FILMIC_CURVE on), non-warm pixels move further
    // toward a moonlit blue, so moonlit grass reads blue-green instead of
    // olive. Warm pixels (torch, lava and fire light: red above green, or
    // yellow as on torch-lit grass) keep the old gentle shift, so block
    // light and its amber falloff at levels 2-6 look as before.
    float lum = luminance(hdr);
    float dim = 1.0 - smoothstep(0.004, 0.06, lum);
    #ifdef FULLBRIGHT
        dim *= 0.25;
    #endif
    dim *= mix(0.2, 1.0, lowLightGate);
    // The moonlit tint is part of the Cinematic Tone Curve (FILMIC_CURVE):
    // with the curve off the old gentle shift is used everywhere.
    float moonlit = 0.0;
    #ifdef FILMIC_CURVE
        float warmPx = saturate(max(3.0 * (hdr.r - hdr.g) / max(hdr.r, 1e-5),
            4.0 * (min(hdr.r, hdr.g) - hdr.b) / max(max(hdr.r, hdr.g), 1e-5) - 0.6));
        moonlit = lowLightGate * (1.0 - warmPx);
    #endif
    vec3 lowTint = mix(vec3(0.86, 0.95, 1.12), MOONLIT_TINT, moonlit);
    hdr = mix(hdr, vec3(lum) * lowTint, dim * mix(0.45, 0.60, moonlit));

    float peak = max(max(hdr.r, hdr.g), hdr.b);
    if (peak <= 1e-6) return vec3(0.0);
    #ifdef FILMIC_CURVE
        float mapped = shoulderCurve(toeCurve(peak, lowLightGate), 0.50);
    #else
        float mapped = shoulderCurve(peak, 0.55);
    #endif
    vec3 c = hdr * (mapped / peak);
    float whiteOut = smoothstep(1.2, 8.0, peak) * 0.65;
    c = mix(c, vec3(mapped), whiteOut);
    #ifdef SPLIT_TONING
        c = splitTone(c, lowLightGate, surface);
    #endif
    return adjustSaturation(c, float(SATURATION) * 0.01);
}
