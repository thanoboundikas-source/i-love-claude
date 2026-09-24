/*
    Hue-preserving cinematic tonemap + grade.

    The curve is applied to the brightest channel and the colour is scaled by
    the same factor, so hue and saturation survive. FILMIC_CURVE adds a real
    toe (deeper blacks that keep their detail) and a soft shoulder, pivoting
    at 0.18 so midtone brightness stays vanilla. Very hot highlights (sun,
    lava cores) drift toward white. SPLIT_TONING warms bright warm-coloured
    surfaces and cools neutral shadows on the daytime surface only (never
    the blue sky, never caves or night, so torch light is left alone).

    lowLightGate: 1 = night / underground (full low-light desaturation),
    0 = daytime surface (almost none).
*/

const float TM_PIVOT = 0.18;

float shoulderCurve(float x, float start) {
    if (x <= start) return x;
    float w = 1.0 - start;
    return start + w * (1.0 - exp(-(x - start) / w));
}

// Rational toe: log-log slope 1 at black (detail kept), steeper in the
// shadows, 1 again in the highlights, pivot 0.18 unchanged. a is the slope
// at black: 0.2 (~2 stops deeper) on the daytime surface, 0.55 (~0.8 stop)
// at night / underground (gate = 1), where a deep toe turned every
// moon-shaded side and the edge of every torch pool pure black.
float toeCurve(float x, float gate) {
    float t = 0.04 * float(FILMIC_CONTRAST) * 0.01;
    #ifdef FULLBRIGHT
        t *= 0.5;
    #endif
    float a = mix(0.2, 0.55, gate);
    return x * (x + a * t) / (x + t) * ((TM_PIVOT + t) / (TM_PIVOT + a * t));
}

// Daytime surface only (gate = night / underground): torch- and lava-lit
// caves and the night sky are left alone. Already-blue pixels (the sky at
// any time of day) are never cooled further.
vec3 splitTone(vec3 c, float gate) {
    float st = float(SPLIT_TONE_STRENGTH) * 0.01 * (1.0 - gate);
    float L = luminance(c);
    float warmth = saturate((c.r - c.b) / max(c.r, 1e-4));
    float blueness = saturate((c.b - c.r) / max(c.b, 1e-4));
    float hiW = smoothstep(0.18, 0.70, L) * saturate(2.0 * warmth);
    float loW = (1.0 - smoothstep(0.015, 0.25, L)) * (1.0 - warmth) * (1.0 - blueness);
    c *= mix(vec3(1.0), vec3(1.058, 0.993, 0.898), hiW * st);
    c *= mix(vec3(1.0), vec3(0.932, 1.003, 1.175), loW * st * 0.8);
    return c;
}

vec3 tonemapSolstice(vec3 hdr, float lowLightGate) {
    hdr = max(hdr, vec3(0.0)) * (float(EXPOSURE) * 0.01);

    float lum = luminance(hdr);
    float dim = 1.0 - smoothstep(0.004, 0.06, lum);
    #ifdef FULLBRIGHT
        dim *= 0.25;
    #endif
    dim *= mix(0.2, 1.0, lowLightGate);
    hdr = mix(hdr, vec3(lum) * vec3(0.86, 0.95, 1.12), dim * 0.45);

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
        c = splitTone(c, lowLightGate);
    #endif
    return adjustSaturation(c, float(SATURATION) * 0.01);
}
