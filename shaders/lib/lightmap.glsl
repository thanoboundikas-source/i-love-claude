/*
    Vanilla lightmap sampling. FULLBRIGHT lifts the floor so caves stay
    visible; the max() keeps already-lit areas untouched so grading survives.
*/

vec3 sampleLightmap(sampler2D lightmapSampler, vec2 lightCoord) {
    vec3 light = texture(lightmapSampler, lightCoord).rgb;
    #ifdef FULLBRIGHT
        light = max(light, vec3(0.6));
    #endif
    return light;
}
