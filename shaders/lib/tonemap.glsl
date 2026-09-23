/*
    Saturation-preserving tonemap.

    The curve is applied to the brightest channel and the colour is scaled by
    the same factor, so hue and saturation survive (no filmic greying of
    midtones). Midtones map 1:1 (vanilla-faithful brightness); only values
    above SHOULDER_START roll off smoothly toward 1. Very hot highlights (sun,
    lava cores) drift toward white like an over-exposed photo instead of
    turning neon.
*/

const float SHOULDER_START = 0.55;

float shoulderCurve(float x) {
    if (x <= SHOULDER_START) return x;
    float w = 1.0 - SHOULDER_START;
    return SHOULDER_START + w * (1.0 - exp(-(x - SHOULDER_START) / w));
}

vec3 tonemapSolstice(vec3 hdr) {
    hdr = max(hdr, vec3(0.0)) * (float(EXPOSURE) * 0.01);
    float peak = max(max(hdr.r, hdr.g), hdr.b);
    if (peak <= 1e-6) return vec3(0.0);
    float mapped = shoulderCurve(peak);
    vec3 c = hdr * (mapped / peak);
    float whiteOut = smoothstep(1.2, 8.0, peak) * 0.65;
    c = mix(c, vec3(mapped), whiteOut);
    return adjustSaturation(c, float(SATURATION) * 0.01);
}
