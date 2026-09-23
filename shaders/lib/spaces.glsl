/*
    Coordinate space conversions (docs: How To > Coordinate Spaces) and the
    TAA sub-pixel jitter. Requires uniforms.glsl.
*/

vec3 projectAndDivide(mat4 m, vec3 p) {
    vec4 h = m * vec4(p, 1.0);
    return h.xyz / h.w;
}

// Screen (uv 0..1, depth 0..1) to view space.
vec3 screenToView(vec2 uv, float depth) {
    return projectAndDivide(gbufferProjectionInverse, vec3(uv, depth) * 2.0 - 1.0);
}

// Same, for pixels flagged as hand: Iris squashes hand depth by MC_HAND_DEPTH
// in NDC, so undo that first (docs: MC_HAND_DEPTH).
vec3 screenToViewHand(vec2 uv, float depth) {
    float ndcZ = (depth * 2.0 - 1.0) / MC_HAND_DEPTH;
    return projectAndDivide(gbufferProjectionInverse, vec3(uv * 2.0 - 1.0, ndcZ));
}

vec3 viewToScreen(vec3 viewPos) {
    return projectAndDivide(gbufferProjection, viewPos) * 0.5 + 0.5;
}

// "Player" space: camera at the origin, world-aligned axes (feet player space
// in the docs; the eye offset is inside gbufferModelViewInverse[3]).
vec3 viewToPlayer(vec3 viewPos) {
    return mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
}

vec3 playerToView(vec3 playerPos) {
    return mat3(gbufferModelView) * playerPos + gbufferModelView[3].xyz;
}

vec3 viewDirToWorld(vec3 v) { return mat3(gbufferModelViewInverse) * v; }
vec3 worldDirToView(vec3 v) { return mat3(gbufferModelView) * v; }

// Positive distance along the view axis for a 0..1 depth value, exact for the
// game's perspective projection (uses its own z terms, so no guessing about
// where the far plane is).
float linearizeDepth(float d) {
    float ndcZ = d * 2.0 - 1.0;
    return gbufferProjection[3][2] / (ndcZ + gbufferProjection[2][2]);
}

// ---- TAA jitter: Halton(2,3), 8 positions, in pixels (-0.5..0.5) ----
vec2 taaJitterPixels(int frame) {
    const vec2 seq[8] = vec2[8](
        vec2( 0.000000, -0.166667), vec2(-0.250000,  0.166667),
        vec2( 0.250000, -0.388889), vec2(-0.375000, -0.055556),
        vec2( 0.125000,  0.277778), vec2(-0.125000, -0.277778),
        vec2( 0.375000,  0.055556), vec2(-0.437500,  0.388889)
    );
    int i = frame & 7;
    // Unrolled select instead of a dynamic array index (Mac-first rule).
    vec2 j = seq[0];
    if (i == 1) j = seq[1];
    if (i == 2) j = seq[2];
    if (i == 3) j = seq[3];
    if (i == 4) j = seq[4];
    if (i == 5) j = seq[5];
    if (i == 6) j = seq[6];
    if (i == 7) j = seq[7];
    return j;
}

// Apply in every gbuffers vertex shader after computing gl_Position.
vec4 applyTaaJitter(vec4 clipPos) {
    #ifdef TAA_JITTER
        vec2 j = taaJitterPixels(frameCounter) * 2.0 / vec2(viewWidth, viewHeight);
        clipPos.xy += j * clipPos.w;
    #endif
    return clipPos;
}
