/*
    Coordinate space conversions (see docs How-To: Coordinate Spaces).
    Requires uniforms.glsl included first.
*/

vec3 screenToView(vec2 uv, float depth) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * ndc;
    return viewPos.xyz / viewPos.w;
}

vec3 viewToScreen(vec3 viewPos) {
    vec4 clip = gbufferProjection * vec4(viewPos, 1.0);
    return clip.xyz / clip.w * 0.5 + 0.5;
}

// Feet player space (origin at camera, world-aligned axes).
vec3 viewToPlayer(vec3 viewPos) {
    return mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
}

vec3 playerToView(vec3 playerPos) {
    return mat3(gbufferModelView) * playerPos + gbufferModelView[3].xyz;
}

// Positive distance from camera for a [0,1] depth buffer value.
float linearDepth(float d) {
    return 2.0 * near * far / (far + near - (2.0 * d - 1.0) * (far - near));
}
