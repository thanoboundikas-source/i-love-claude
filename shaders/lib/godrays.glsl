/*
    Godrays: light scattered by the air between the camera and a surface,
    visible where sunlight is broken up by terrain and trees. Marches the
    view ray through the shadow map (GODRAY_SAMPLES, jittered) at the scaled
    effects resolution; the phase function and colour are applied in
    composite1 at full resolution. Requires shadows.glsl (SHADOWS on).
*/

#ifdef GODRAYS_ACTIVE
// Light reaching the ray: squared visibility, so partly lit rays stand out
// from shadowed ones. Monotonic: a more lit ray is never dimmer.
float godrayShaftWeight(float vis) {
    return vis * vis;
}

// Optical depth of a march to a surface `dist` blocks away (at most 48):
// the scattered light a fully lit ray of that length would get.
float godrayDepthTerm(float dist) {
    return 1.0 - exp(-min(dist, 48.0) * 0.012);
}
vec4 godrayDepthTerm(vec4 dist) {
    return 1.0 - exp(-min(dist, vec4(48.0)) * 0.012);
}

// The effects pass stores the ray's *shadow deficit*: how much scattered
// light the shadow casters along the march take away, (1 - weight) times the
// optical depth of the march. Open air stores 0. composite1 turns it into
// shafts by comparing each pixel with its neighbours (godrayShafts), so a
// low sun over open land never gets a glowing veil; the distance haze in
// fog.glsl is the only open-air term.
float godrayAmount(vec3 playerEnd, float jitter) {
    float dist = min(length(playerEnd), 48.0);
    vec3 dir = playerEnd / max(length(playerEnd), 1e-4);
    float stepLen = dist / float(GODRAY_SAMPLES);
    float vis = 0.0;
    for (int i = 0; i < GODRAY_SAMPLES; i++) {
        vec3 p = dir * (stepLen * (float(i) + jitter));
        vec3 sp = tapToScreen(playerToShadowClip(p));
        bool inside = sp.x > 0.0 && sp.x < 1.0 && sp.y > 0.0 && sp.y < 1.0;
        vis += inside ? texture(shadowtex1, sp) : 1.0;
    }
    vis /= float(GODRAY_SAMPLES);
    return (1.0 - godrayShaftWeight(vis)) * godrayDepthTerm(dist);
}

// Shafts from the stored deficits: a pixel glows by how much more light its
// ray gets than the most shadowed ray beside it. Open air (all deficits 0)
// and uniform shadow both give 0; a lit gap next to shadowed air gives a
// shaft. Using the deficit, not the lit amount, means depth edges in open
// air (a near hill against the sky) add nothing.
//
// Rays of different lengths are compared over the shorter march: a
// longer neighbour's deficit is scaled to the centre's optical depth (its
// shadowed fraction times the centre's depth). Without that, a short ray
// to a near surface, even a fully shadowed one, glowed by the difference
// in ray length (hourglass bands on shaded tree trunks, DECISIONS #83). A
// shorter neighbour keeps its own (smaller) deficit, so the far side of a
// near dark object gets no rim.
//
// What this guarantees: no pixel glows more than the light its own ray
// receives (optical depth minus its deficit), so a fully shadowed ray
// never glows. What it does not: the glow marks where the deficit changes
// most within GODRAY_FAR across the shafts, an edge detector, not a
// comparison with the lit air beside a whole band. Inside a partly
// shadowed band wider than ~4% of the screen, the pixels next to full
// shadow can glow more than the fully lit air on the band's other side
// (1D worked case, 48-block rays: lit air next to a vis-0.9 band 0.083,
// the band's pixels next to full shadow 0.355, its middle 0; DECISIONS
// #90).
//
// Sun shafts are parallel in the world, so on screen they all run through
// the vanishing point of the light direction. The 4 neighbours sit ACROSS
// that direction (GODRAY_NEAR and GODRAY_FAR of the screen height away), so
// an edge lying across the shafts, like a hill crest under a low sun, gets
// no rim glow.
const float GODRAY_NEAR = 0.015;
const float GODRAY_FAR = 0.040;

// Unit screen direction across the shafts at uv, in uv units per screen
// height (x already divided by the aspect ratio).
vec2 godrayAcross(vec2 uv) {
    vec4 l = gbufferProjection * vec4(shadowLightPosition, 0.0);
    vec2 radial = l.xy - (uv * 2.0 - 1.0) * l.w;
    radial.x *= aspectRatio;
    float len = length(radial);
    vec2 a = len > 1e-6 ? vec2(-radial.y, radial.x) / len : vec2(1.0, 0.0);
    return vec2(a.x / aspectRatio, a.y);
}

// centre, taps: stored deficits; tapDist, dist: surface distances of the
// taps and of the centre pixel (1e4 for the sky, as in composite1).
float godrayShafts(float centre, vec4 taps, vec4 tapDist, float dist) {
    float dc = godrayDepthTerm(dist);
    vec4 dn = godrayDepthTerm(tapDist);
    vec4 t = taps * min(vec4(1.0), dc / max(dn, vec4(1e-4)));
    float m = max(max(t.x, t.y), max(t.z, t.w));
    return clamp(m - centre, 0.0, max(dc - centre, 0.0));
}

// Henyey-Greenstein phase: strong forward scattering toward the light.
float phaseHG(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

vec3 godrayLight(float amount, vec3 viewDirWorld) {
    float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
    float phase = phaseHG(dot(viewDirWorld, lightDir), 0.72);
    // 0.24 (was 0.08 with a x0.6 low-sun damper, which left real shafts
    // invisible): the neighbour step and the cap above already keep open
    // air and fully shadowed rays at exactly 0, so the strength only scales
    // real shafts (DECISIONS #90).
    float strength = 0.24 * float(GODRAY_STRENGTH) * 0.01;
    return directLight * amount * phase * strength * smoothstep(0.1, 0.6, eyeSky) * (1.0 - rainF * 0.6);
}
#endif
