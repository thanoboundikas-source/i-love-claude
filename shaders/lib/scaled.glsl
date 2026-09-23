/*
    Render-scaled passes. A scaled pass draws its fullscreen quad into the
    lower-left [0, scale]^2 region of the target (the docs note this equals
    the scale.<program> directive, done in the vertex stage). Its texcoord
    still spans 0..1 = the full frame it represents, so it samples full-res
    inputs (depth, G-buffer) directly at texcoord.

    Consumers map a full-frame uv into the region with scaledUV().
    Requires uniforms.glsl (viewWidth/viewHeight).
*/

vec4 scaleQuadPos(vec4 clipPos, float scale) {
    clipPos.xy = (clipPos.xy * 0.5 + 0.5) * scale * 2.0 - 1.0;
    return clipPos;
}

vec2 scaledUV(vec2 uv, float scale) {
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
    return clamp(uv * scale, 0.5 * texel, vec2(scale) - 0.5 * texel);
}
