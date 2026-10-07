/*
    Clouds with vanilla shapes.

    The cloud map is the game's own textures/environment/clouds.png (bound
    as `cloudTex` in shaders.properties): one texel = one 12x12 block cell,
    white = cloud. Solstice extrudes each cell into a CLOUD_THICKNESS-tall box
    starting at the vanilla cloud height and traces the boxes with a 2D grid
    walk (one texel fetch per cell crossed, fixed step count). Each crossed
    cloud segment is lit by the face the ray entered through, so tops, sides
    and undersides read like solid blocks; short segments through corners are
    partly transparent, which softens the silhouettes.

    Requires common.glsl, uniforms.glsl, settings.glsl, sky.glsl.
*/

uniform sampler2D cloudTex;

const float CLOUD_CELL = 12.0;          // vanilla cell size in blocks
const float CLOUD_DENSITY = 2.2;        // optical depth per block inside a cloud
const float CLOUD_SPEED = 3072.0 / 3600.0; // blocks per second; wraps seamlessly with frameTimeCounter

float cloudBaseHeight() {
    // NaN in dimensions without clouds; comparisons with NaN are false.
    return (cloudHeight > -10000.0 && cloudHeight < 10000.0) ? cloudHeight : 192.0;
}

vec2 cloudOffset() {
    return vec2(frameTimeCounter * CLOUD_SPEED, 0.0);
}

// Occupancy of one cloud cell (integer cell coordinates), 0 or 1.
float cloudCell(ivec2 cell) {
    // Wrap with float mod: integer % is undefined for negative values in GLSL.
    vec2 size = vec2(textureSize(cloudTex, 0));
    ivec2 t = ivec2(mod(vec2(cell), size));
    return step(0.5, texelFetch(cloudTex, t, 0).r);
}

// Smooth (bilinear) coverage at a world XZ position: soft cloud shadows and
// the flat fallback layer.
float cloudCoverageSmooth(vec2 worldXZ) {
    vec2 p = (worldXZ + cloudOffset()) / CLOUD_CELL - 0.5;
    ivec2 c = ivec2(floor(p));
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = cloudCell(c);
    float b = cloudCell(c + ivec2(1, 0));
    float d = cloudCell(c + ivec2(0, 1));
    float e = cloudCell(c + ivec2(1, 1));
    return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}

// Light arriving at a cloud face with normal n (world space).
vec3 cloudFaceLight(vec3 n, vec3 viewDir, float sunShadow) {
    float ndl = dot(n, lightDir);
    // Sun-dominated like a real cloud: faces toward the light get the full
    // sun (shadowed by clouds in front); every face also gets 0.22 of it
    // scattered through the cloud body (never shadowed), so shade stays
    // bright and neutral instead of taking on the sky's blue. At sunset the
    // high cloud layer still catches the sun after the ground has lost it.
    // With the sun high (above ~20 degrees) the underside sees the whole
    // cloud's thickness between it and the sun, so it gets 0.13: seen
    // toward the sun, sun-averted sides then read as lighter strips over
    // darker undersides instead of one flat plate (DECISIONS #92). A low
    // sun (golden hour, sunset) and the moon keep 0.22. Only with blocky 3D
    // clouds: the flat layer (POTATO, 3D clouds off) is nothing but
    // underside, has no sides to read against and would only turn greyer
    // (#98). With 3D clouds on, the flat fallback used for reflections keeps
    // 0.13, matching the 3D undersides on screen next to it.
    float sunLit = step(0.0, dot(lightDir, sunDir));
    float glow = 1.0 + 1.2 * sunsetF * sunLit;
    float scatter = 0.22;
    #ifdef CLOUDS_VOLUMETRIC
        if (n.y < -0.5) scatter = mix(0.22, 0.13, smoothstep(0.10, 0.35, lightDir.y) * sunLit);
    #endif
    vec3 light = directLight * glow * (max(ndl, 0.0) * sunShadow + scatter);

    // Sky light, much weaker than the sun: tops see the zenith, undersides
    // the horizon (and its sunset band).
    vec3 horizonTint = skyGradient(normalize(vec3(viewDir.x, 0.04, viewDir.z)));
    vec3 skyTop = ambientLight * 0.80 + zenithCol * 0.15 + horizonTint * (0.35 * sunsetF);
    vec3 under = horizonTint * (0.30 + 0.20 * sunsetF) + ambientLight * 0.35;
    vec3 side = mix(under, skyTop, 0.50);
    vec3 amb = n.y > 0.5 ? skyTop : (n.y < -0.5 ? under : side);
    // Rain clouds are heavy and grey.
    return (light + amb) * mix(1.0, 0.62, rainF) * mix(1.0, 0.75, stormF);
}

#ifdef CLOUDS_VOLUMETRIC
// Traces the cloud slab along a ray. origin = world position of the camera,
// dir = normalized world direction, maxDist = distance to the terrain (or a
// large number for sky). Returns premultiplied colour (rgb) and opacity (a),
// and the distance to the first cloud hit (for fog).
vec4 traceClouds(vec3 origin, vec3 dir, float maxDist, out float hitDist) {
    hitDist = -1.0;
    float y0 = cloudBaseHeight();
    float y1 = y0 + float(CLOUD_THICKNESS);

    // Ray / slab interval.
    float tEnter, tExit;
    if (abs(dir.y) < 1e-5) {
        if (origin.y < y0 || origin.y > y1) return vec4(0.0);
        tEnter = 0.0; tExit = 1e6;
    } else {
        float ta = (y0 - origin.y) / dir.y;
        float tb = (y1 - origin.y) / dir.y;
        tEnter = max(min(ta, tb), 0.0);
        tExit = max(ta, tb);
    }
    tExit = min(tExit, maxDist);
    if (tExit <= tEnter) return vec4(0.0);

    // Grid walk in the XZ plane, in cell units.
    vec2 off = cloudOffset();
    vec2 p = (origin.xz + off + dir.xz * tEnter) / CLOUD_CELL;
    vec2 d = dir.xz / CLOUD_CELL;
    ivec2 cell = ivec2(floor(p));
    ivec2 stepDir = ivec2(d.x >= 0.0 ? 1 : -1, d.y >= 0.0 ? 1 : -1);
    vec2 invD = 1.0 / max(abs(d), vec2(1e-6));
    vec2 nextBound = (vec2(cell) + vec2(stepDir.x > 0 ? 1.0 : 0.0, stepDir.y > 0 ? 1.0 : 0.0) - p);
    vec2 tMax = tEnter + abs(nextBound) * invD;   // distance along the ray to the next x / z boundary
    vec2 tDelta = invD;

    float t = tEnter;
    int lastAxis = -1;                             // -1 = entered through top/bottom plane
    float transmittance = 1.0;
    vec3 color = vec3(0.0);
    bool inside = false;                           // previous cell was cloud too
    vec3 n = vec3(0.0, 1.0, 0.0);

    for (int i = 0; i < CLOUD_STEPS; i++) {
        float tNext = min(min(tMax.x, tMax.y), tExit);
        float occ = cloudCell(cell);
        if (occ > 0.5) {
            float segment = tNext - t;
            // Only a real entry (from open air) picks a new face; crossing
            // into a neighbouring cloud cell keeps the face we came in by,
            // so no grid lines appear inside a cloud.
            if (!inside) {
                if (lastAxis < 0) n = vec3(0.0, dir.y < 0.0 ? 1.0 : -1.0, 0.0);
                else if (lastAxis == 0) n = vec3(-float(stepDir.x), 0.0, 0.0);
                else n = vec3(0.0, 0.0, -float(stepDir.y));
            }

            // Self-shadow: is there cloud between this face and the sun?
            vec3 hp = origin + dir * (t + 0.05);
            float sunShadow = 1.0;
            if (lightDir.y > 0.02) {
                float toTop = max((y1 - hp.y) / lightDir.y, 0.0);
                vec3 s1 = hp + lightDir * min(toTop * 0.5 + 2.0, 40.0);
                vec3 s2 = hp + lightDir * min(toTop + 6.0, 90.0);
                float o1 = (s1.y < y1) ? cloudCell(ivec2(floor((s1.xz + off) / CLOUD_CELL))) : 0.0;
                float o2 = (s2.y < y1) ? cloudCell(ivec2(floor((s2.xz + off) / CLOUD_CELL))) : 0.0;
                sunShadow = 1.0 - 0.45 * o1 - 0.25 * o2;
            }

            vec3 lit = cloudFaceLight(n, dir, sunShadow);
            float a = 1.0 - exp(-CLOUD_DENSITY * segment);
            color += transmittance * a * lit;
            if (hitDist < 0.0) hitDist = t;
            transmittance *= 1.0 - a;
            if (transmittance < 0.02) break;
        }
        inside = occ > 0.5;
        if (tNext >= tExit) break;
        t = tNext;
        if (tMax.x < tMax.y) { cell.x += stepDir.x; tMax.x += tDelta.x; lastAxis = 0; }
        else                 { cell.y += stepDir.y; tMax.y += tDelta.y; lastAxis = 1; }
    }

    return vec4(color, 1.0 - transmittance);
}
#endif

// Cheap flat vanilla-style layer (POTATO, 3D clouds off, and reflections).
vec4 flatClouds(vec3 origin, vec3 dir, float maxDist, out float hitDist) {
    hitDist = -1.0;
    float y = cloudBaseHeight() + float(CLOUD_THICKNESS) * 0.5;
    if (abs(dir.y) < 1e-4) return vec4(0.0);
    float t = (y - origin.y) / dir.y;
    if (t <= 0.0 || t > maxDist) return vec4(0.0);
    vec3 p = origin + dir * t;
    float cov = cloudCoverageSmooth(p.xz);
    if (cov <= 0.0) return vec4(0.0);
    hitDist = t;
    vec3 n = vec3(0.0, origin.y < y ? -1.0 : 1.0, 0.0);
    vec3 lit = cloudFaceLight(n, dir, 1.0);
    float a = smoothstep(0.15, 0.85, cov) * 0.9;
    return vec4(lit * a, a);
}

// Distance fade: clouds melt into the sky colour and thin out far away, so
// the cloud field never ends in a hard line.
vec4 fadeClouds(vec4 c, vec3 dir, float hitDist) {
    if (c.a <= 0.0 || hitDist < 0.0) return c;
    float haze = 1.0 - exp(-hitDist / 1400.0);
    vec3 skyBehind = skyGradient(dir);
    vec3 col = c.rgb / max(c.a, 1e-4);
    col = mix(col, skyBehind, haze * 0.60);
    float thin = 1.0 - smoothstep(800.0, 2000.0, hitDist);
    float a = c.a * thin;
    return vec4(col * a, a);
}

// Soft cloud shadow on the ground: coverage where the light ray from a
// surface crosses the middle of the cloud layer.
float cloudShadow(vec3 worldPos) {
    #ifdef CLOUD_SHADOWS_ACTIVE
        float y = cloudBaseHeight() + float(CLOUD_THICKNESS) * 0.5;
        if (lightDir.y < 0.05 || worldPos.y > y) return 1.0;
        vec3 p = worldPos + lightDir * ((y - worldPos.y) / lightDir.y);
        float cov = cloudCoverageSmooth(p.xz);
        float strength = 0.55 * smoothstep(0.05, 0.25, lightDir.y) * (1.0 - rainF);
        return 1.0 - cov * strength;
    #else
        return 1.0;
    #endif
}
