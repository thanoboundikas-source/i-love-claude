/*
    Vanilla-style linear distance fog. Phase 1 stand-in; replaced by
    sky-matched atmospheric fog in Phase 2.
*/

uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;

vec3 applyFog(vec3 color, float viewDist) {
    float fogFactor = clamp((viewDist - fogStart) / max(fogEnd - fogStart, 0.0001), 0.0, 1.0);
    return mix(color, fogColor, fogFactor);
}
