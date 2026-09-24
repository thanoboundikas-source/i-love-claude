/*
    Overworld sky and the light colours derived from it.

    Everything is in world ("player") space directions and linear HDR units
    where 1.0 = a white surface lit by the noon sun head-on (before exposure).
    One palette drives the sky gradient, the sun/moon/ambient light, the fog
    colour and the cloud lighting, so they always agree.

    Requires common.glsl, uniforms.glsl, settings.glsl.
*/

// ---------------------------------------------------------------- state
vec3 sunDir;        // world-space direction to the sun
vec3 moonDir;       // world-space direction to the moon
vec3 lightDir;      // sun by day, moon by night (matches the shadow map)
float sunElev;      // sin(elevation) of the sun
float dayF;         // 0 night .. 1 day
float nightF;       // 0 day .. 1 night
float sunsetF;      // peaks at sunrise / sunset
float rainF;        // rain amount (smooth)
float stormF;       // thunderstorm amount

vec3 zenithCol;     // sky straight up
vec3 horizonCol;    // sky at the horizon (away from the sun at sunset)
vec3 sunLight;      // direct sunlight colour * intensity
vec3 moonLight;     // direct moonlight colour * intensity
vec3 directLight;   // light from lightDir (what the shadow map is for)
vec3 ambientLight;  // sky light on an upward face under open sky

const vec3 DAY_ZENITH      = vec3(0.08, 0.22, 0.80);
const vec3 DAY_HORIZON     = vec3(0.34, 0.56, 1.00);
const vec3 SUNSET_ZENITH   = vec3(0.07, 0.13, 0.44);
const vec3 SUNSET_TOWARD   = vec3(1.00, 0.44, 0.15);
const vec3 SUNSET_AWAY     = vec3(0.42, 0.29, 0.52);
const vec3 SUNSET_AFTERGLOW = vec3(0.66, 0.26, 0.42);
const vec3 NIGHT_ZENITH    = vec3(0.0055, 0.0100, 0.0290);
const vec3 NIGHT_HORIZON   = vec3(0.0130, 0.0210, 0.0440);

const vec3 SUN_NOON        = vec3(1.00, 0.95, 0.88);
const vec3 SUN_GOLDEN      = vec3(1.00, 0.60, 0.30);
const vec3 MOON_COLOR      = vec3(0.58, 0.70, 1.00);
// Light (not sky) colours: a warmer key than the sun disc/halo tints.
const vec3 SUNLIGHT_NOON   = vec3(1.00, 0.91, 0.78);
const vec3 SUNLIGHT_GOLDEN = vec3(1.00, 0.55, 0.24);

const float SUN_RADIUS_COS  = 0.99952;  // ~1.8 degrees
const float MOON_RADIUS_COS = 0.99939;  // ~2.0 degrees

vec3 overcast(vec3 c, float amount) {
    vec3 grey = vec3(luminance(c)) * vec3(0.86, 0.91, 1.0);
    return mix(c, grey * 0.78, amount);
}

float moonPhaseBrightness() {
    // 0 full .. 4 new .. back to full
    float p = abs(float(moonPhase) - 4.0) / 4.0;
    return mix(0.30, 1.0, p);
}

void initSky() {
    sunDir  = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    moonDir = normalize(mat3(gbufferModelViewInverse) * moonPosition);
    // The light the shadow map was rendered from (sun by day, moon by night).
    lightDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    bool lightIsSun = dot(lightDir, sunDir) > 0.0;
    sunElev = sunDir.y;

    dayF    = smoothstep(-0.06, 0.22, sunElev);
    nightF  = 1.0 - smoothstep(-0.20, 0.03, sunElev);
    sunsetF = (1.0 - smoothstep(0.0, 0.45, sunElev)) * smoothstep(-0.24, -0.03, sunElev);
    rainF   = rainStrength;
    stormF  = thunderStrength;

    zenithCol  = mix(NIGHT_ZENITH, DAY_ZENITH, dayF);
    zenithCol  = mix(zenithCol, SUNSET_ZENITH, sunsetF * 0.55);
    horizonCol = mix(NIGHT_HORIZON, DAY_HORIZON, dayF);
    horizonCol = mix(horizonCol, SUNSET_AWAY, sunsetF * 0.75);

    float weatherDim = mix(1.0, 0.62, rainF) * mix(1.0, 0.6, stormF);
    zenithCol  = overcast(zenithCol, rainF * 0.85) * weatherDim;
    horizonCol = overcast(horizonCol, rainF * 0.85) * weatherDim;

    // Direct light. The sun warms as it sinks and fades out just below the
    // horizon; the moon takes over at night.
    vec3 sunTint = mix(SUNLIGHT_NOON, SUNLIGHT_GOLDEN, 1.0 - smoothstep(0.0, 0.55, sunElev));
    float sunI = 1.42 * smoothstep(0.0, 0.05, sunElev);
    float moonI = 0.125 * moonPhaseBrightness() * smoothstep(0.0, 0.10, moonDir.y);
    float weatherDirect = mix(1.0, 0.075, rainF) * mix(1.0, 0.5, stormF);
    sunLight  = sunTint * sunI * weatherDirect;
    moonLight = MOON_COLOR * moonI * weatherDirect;
    directLight = lightIsSun ? sunLight : moonLight;

    // Sky (ambient) light: a bluish white by day, a warm peach glow at sunset
    // (the low sun lights the whole sky; a lilac fill turned golden-hour
    // grass olive), dim blue at night. Overcast skies are dimmer but
    // relatively brighter than the sun.
    vec3 ambDay    = vec3(0.56, 0.72, 1.00) * 0.40;
    vec3 ambSunset = vec3(0.88, 0.70, 0.62) * 0.40;
    vec3 ambNight  = vec3(0.40, 0.52, 0.85) * 0.040;
    ambientLight = mix(ambNight, ambDay, dayF);
    ambientLight = mix(ambientLight, ambSunset, sunsetF * 0.7 * (1.0 - dayF * 0.5));
    ambientLight = overcast(ambientLight, rainF * 0.7) * mix(1.0, 0.95, rainF) * mix(1.0, 0.7, stormF);
}

// ---------------------------------------------------------------- sky
// Rotates a world direction into a frame that turns with the sky
// (same rotation chain Iris uses for the shadow camera, driven by sunAngle so
// it never jumps at sunset). Used for stars.
vec3 toCelestial(vec3 v) {
    float skyAngle = fract(sunAngle - 0.25);
    float a = -skyAngle * TAU;
    float r = radians(sunPathRotation);
    float ca = cos(a), sa = sin(a), cr = cos(r), sr = sin(r);
    // pose = RotX(90) * RotZ(a) * RotX(r), applied right to left
    v = vec3(v.x, cr * v.y - sr * v.z, sr * v.y + cr * v.z);   // RotX(r)
    v = vec3(ca * v.x - sa * v.y, sa * v.x + ca * v.y, v.z);   // RotZ(a)
    v = vec3(v.x, -v.z, v.y);                                  // RotX(90)
    return v;
}

// The smooth gradient + sunset band + sun/moon halos. No discs, no stars.
// Also used for fog, so it must be cheap and continuous.
vec3 skyGradient(vec3 dir) {
    float h = dir.y;
    float hp = max(h, 0.0);

    vec3 col = mix(zenithCol, horizonCol, exp(-hp * 8.0));

    // Sunrise / sunset band: thin, hugging the horizon, orange toward the
    // sun and soft purple away from it. Zenith stays blue -> no orange soup.
    float cosSun = dot(dir, sunDir);
    float toward = saturate(cosSun * 0.5 + 0.5);
    // Once the sun is below the horizon the glow turns from orange to a
    // soft rose and fades, instead of going brown.
    float afterglow = 1.0 - smoothstep(-0.16, 0.0, sunElev);
    vec3 towardCol = mix(SUNSET_TOWARD, SUNSET_AFTERGLOW, afterglow);
    vec3 band = mix(SUNSET_AWAY, towardCol, toward * toward * toward);
    band = overcast(band, rainF * 0.9) * mix(1.0, 0.6, rainF);
    float bandMix = exp(-hp * 9.0) * sunsetF * (1.0 - smoothstep(0.05, 0.32, sunElev)) * (0.30 + 0.70 * toward);
    col = mix(col, band, bandMix);

    // Below the horizon (seen past the world edge / in the void) fade to a
    // darker version of the horizon so there is never a hard line.
    col = mix(col, horizonCol * 0.45, 1.0 - smoothstep(-0.35, 0.0, h));

    // Halos: a soft wide glow and a tighter one near the sun disc.
    float cs = max(cosSun, 0.0);
    vec3 haloTint = mix(SUN_NOON, SUN_GOLDEN, sunsetF);
    float sunUp = smoothstep(-0.12, 0.02, sunElev);
    col += haloTint * (pow(cs, 8.0) * 0.04 + pow(cs, 120.0) * 0.22) * sunUp * mix(1.0, 1.8, sunsetF) * (1.0 - rainF * 0.8);

    float cm = max(dot(dir, moonDir), 0.0);
    col += MOON_COLOR * pow(cm, 40.0) * 0.015 * nightF * (1.0 - rainF);

    return col;
}

float starField(vec3 dir) {
    vec3 p = toCelestial(dir) * 160.0;
    vec3 cell = floor(p);
    float rnd = hash13(cell);
    if (rnd < 0.988) return 0.0;
    vec3 center = cell + 0.2 + 0.6 * hash33(cell + 17.0);
    float d = length(p - center);
    float strength = (rnd - 0.988) / 0.012;
    float twinkle = 0.75 + 0.25 * sin(frameTimeCounter * (2.0 + 3.0 * strength) + rnd * 100.0);
    return (1.0 - smoothstep(0.04, 0.26, d)) * (0.3 + 0.7 * strength * strength) * twinkle;
}

vec3 sunDisc(vec3 dir) {
    float c = dot(dir, sunDir);
    float edge = smoothstep(SUN_RADIUS_COS, SUN_RADIUS_COS + 0.00006, c);
    if (edge <= 0.0) return vec3(0.0);
    // limb darkening
    float mu = saturate((c - SUN_RADIUS_COS) / (1.0 - SUN_RADIUS_COS));
    float limb = 0.62 + 0.38 * sqrt(mu);
    vec3 tint = mix(SUN_NOON, SUN_GOLDEN * vec3(1.0, 0.85, 0.75), 1.0 - smoothstep(0.0, 0.25, sunElev));
    float horizonFade = smoothstep(-0.03, 0.01, dir.y);
    return tint * 38.0 * edge * limb * horizonFade * (1.0 - rainF * 0.97);
}

vec3 moonDisc(vec3 dir) {
    float c = dot(dir, moonDir);
    float edge = smoothstep(MOON_RADIUS_COS, MOON_RADIUS_COS + 0.00006, c);
    if (edge <= 0.0) return vec3(0.0);

    // Local disc coordinates -> a sphere normal facing us.
    vec3 up0 = abs(moonDir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 right = normalize(cross(up0, moonDir));
    vec3 up = cross(moonDir, right);
    float rad = sqrt(1.0 - MOON_RADIUS_COS * MOON_RADIUS_COS);
    vec2 q = vec2(dot(dir, right), dot(dir, up)) / rad;
    float z = sqrt(max(1.0 - dot(q, q), 0.0));
    vec3 n = vec3(q, z);

    // Phase: 0 full (lit from the front) .. 4 new (lit from behind).
    float ang = float(moonPhase) * (TAU / 8.0);
    vec3 l = vec3(sin(ang), 0.0, cos(ang));
    float lit = smoothstep(-0.06, 0.12, dot(n, l));

    // Gentle maria so it reads as the moon, not a white dot.
    float maria = valueNoise2(q * 3.1 + 7.0) * 0.6 + valueNoise2(q * 7.3) * 0.4;
    float albedo = mix(0.72, 1.0, smoothstep(0.35, 0.65, maria));

    float horizonFade = smoothstep(-0.03, 0.01, dir.y);
    vec3 col = MOON_COLOR * vec3(0.95, 0.97, 1.0) * (lit * albedo * 3.2 + 0.03) * edge;
    return col * horizonFade * (1.0 - rainF * 0.97);
}

// Full sky for a view ray that hits nothing.
vec3 skyColorFull(vec3 dir) {
    vec3 col = skyGradient(dir);
    #ifdef STARS
        float starVis = nightF * (1.0 - rainF) * smoothstep(0.0, 0.18, dir.y);
        if (starVis > 0.0) col += vec3(0.80, 0.88, 1.0) * starField(dir) * 0.55 * starVis;
    #endif
    col += sunDisc(dir);
    col += moonDisc(dir);
    return col;
}

// Colour of distant haze in a direction: the sky right at/above the horizon,
// so fully fogged terrain melts into the sky behind it.
vec3 fogSkyColor(vec3 dir) {
    vec3 d = normalize(vec3(dir.x, max(dir.y, 0.0) * 0.85 + 0.02, dir.z));
    return skyGradient(d);
}
