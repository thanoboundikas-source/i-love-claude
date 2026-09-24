/*
    Surface lighting for the Overworld. Requires sky.glsl (initSky() called).

    Units: linear HDR, 1.0 = white surface lit by the noon sun head-on.
    Light terms:
      direct  - sun/moon * N.L * shadow (shadow map when SHADOWS is on,
                sky-light proxy otherwise)
      ambient - sky light, vanilla-like directional falloff, AO
      block   - torch light from the lightmap, tinted by COLORED_LIGHT
      floor   - tiny minimum so caves are not pure black (FULLBRIGHT lifts it)
*/

const vec3 TORCH_COLOR = vec3(1.00, 0.56, 0.26);   // mid colour (forward/water paths)
const vec3 TORCH_NEAR  = vec3(1.00, 0.66, 0.36);   // hot core next to the source
const vec3 TORCH_FAR   = vec3(1.00, 0.46, 0.16);   // deep amber at the edge of the pool

// Block light brightness: bright near the source, a long gentle tail so
// dimly lit areas stay readable (vanilla keeps level 3-6 visible too).
float blockLightCurve(float b) {
    float b2 = b * b;
    return 1.8 * b2 * b2 * b + 0.30 * b2 * sqrt(b) + 0.02 * b;
}

// Sky light reaching a surface (under trees, in overhangs, caves).
float skyLightCurve(float s) {
    return s * s * s;
}

// Face shading for the ambient term: top 1.0, sides 0.70, bottom 0.40, so
// blocks in shade keep a readable form (BOUNCE_LIGHT adds warm light back to
// sides and bottoms by day).
float ambientDirectional(vec3 n) {
    return 0.70 + 0.30 * n.y;
}

// Minimum light in the dark. FULLBRIGHT (and night vision) lift it with a
// cool, slightly saturated tint so caves read as "moonlit", never flat grey.
vec3 ambientFloor() {
    vec3 floorCol = vec3(0.0035, 0.0040, 0.0050);
    #ifdef FULLBRIGHT
        floorCol = vec3(0.19, 0.21, 0.25);
    #endif
    floorCol = max(floorCol, vec3(0.20, 0.22, 0.25) * nightVision);
    return floorCol;
}

struct Surface {
    vec3 albedo;      // linear
    vec3 normal;      // world space
    vec3 geoNormal;   // world space, un-bumped (for shadow bias)
    vec2 light;       // block, sky (0..1)
    float ao;
    float smoothness;
    float emissive;
    int flags;
};

// Direct-light visibility when there is no shadow map: only surfaces open to
// the sky get sun (vanilla has no shadows at all; this keeps caves and the
// shade under trees dark).
float skyShadowProxy(float sky) {
    return smoothstep(0.80, 0.96, sky);
}

// Stops sunlight leaking into sealed spaces where the shadow map is wrong
// (far away, very low sun): no sky light means no sun.
float lightLeakGuard(float sky) {
    return smoothstep(0.03, 0.30, sky);
}

// Block-light colour. COLORED_LIGHT passes a screen-space tint (see
// deferred_lighting.fsh); otherwise torches are warm everywhere.
vec3 blockLightColor(vec3 tint, float tintWeight, float b) {
    vec3 c = mix(TORCH_FAR, TORCH_NEAR, smoothstep(0.55, 1.0, b));
    #ifdef COLORED_LIGHT
        float l = max(luminance(tint), 1e-4);
        vec3 t = tint / l * luminance(c);
        c = mix(c, t, tintWeight);
    #endif
    return c;
}

// Assemble the lighting. `shadow` is the direct-light visibility (rgb so
// stained glass can tint it), already including the leak guard.
vec3 shadeSurface(Surface s, vec3 shadow, vec3 blockTint, float blockTintWeight) {
    float NdotL = dot(s.normal, lightDir);
    float diffuse = max(NdotL, 0.0);

    #ifdef FOLIAGE_SSS
        if ((s.flags & FLAG_SSS) != 0) {
            // Thin foliage: light from behind comes through, softly.
            diffuse = max(diffuse, 0.0) * 0.75 + max(-NdotL, 0.0) * 0.35 + 0.18;
        }
    #endif

    vec3 direct = directLight * diffuse * shadow;

    // Vanilla AO is stored as the multiplier vanilla applies to sRGB colour;
    // squaring it gives the same visible strength in linear light.
    float ao2 = pow(max(s.ao, 0.001), float(AO_STRENGTH) * 0.02);

    float skyAmb = skyLightCurve(s.light.y);
    vec3 ambient = ambientLight * skyAmb * ambientDirectional(s.normal) * ao2;

    #ifdef BOUNCE_LIGHT
        // Sun/moon light bounced off the ground onto walls and undersides:
        // a warm fill against the cool sky fill (none on tops, full on bottoms).
        ambient += directLight * (max(lightDir.y, 0.0) * 0.08) * vec3(1.00, 0.90, 0.70)
                 * (0.5 - 0.5 * s.normal.y) * skyAmb * ao2;
    #endif

    vec3 block = blockLightColor(blockTint, blockTintWeight, s.light.x) * blockLightCurve(s.light.x) * mix(1.0, ao2, 0.8);

    // Metals reflect most of their light specularly; keep some diffuse so
    // iron and gold blocks still read as their colour indoors.
    vec3 diffuseAlbedo = (s.flags & FLAG_METAL) != 0 ? s.albedo * 0.6 : s.albedo;
    vec3 lit = diffuseAlbedo * (direct + ambient + block + ambientFloor() * ao2);
    lit += s.albedo * s.emissive * 4.0;
    return lit;
}

// Specular: a GGX sun/moon highlight plus a cheap sky reflection on smooth
// surfaces (wet ground in rain, metal, polished blocks). v = direction to the
// camera. Only called when smoothness > 0.
vec3 specularLighting(Surface s, vec3 v, vec3 shadow) {
    float rough = max(1.0 - s.smoothness, 0.12);
    float a = rough * rough;
    float a2 = a * a;
    bool metal = (s.flags & FLAG_METAL) != 0;
    vec3 f0 = metal ? s.albedo : vec3(0.04);

    vec3 n = s.normal;
    float ndv = saturate(dot(n, v));
    vec3 h = normalize(v + lightDir);
    float ndh = saturate(dot(n, h));
    float ndl = saturate(dot(n, lightDir));
    float vdh = saturate(dot(v, h));
    float d = ndh * ndh * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * d * d);
    float k = a * 0.5;
    float G = (ndl / (ndl * (1.0 - k) + k)) * (ndv / (ndv * (1.0 - k) + k));
    vec3 F = f0 + (1.0 - f0) * pow5(1.0 - vdh);
    vec3 sun = directLight * shadow * D * G * F / max(4.0 * ndv, 1e-3);

    // Sky reflection, weakened for rough surfaces and where the sky is hidden.
    vec3 r = reflect(-v, n);
    vec3 envF = f0 + (max(vec3(1.0 - rough), f0) - f0) * pow5(1.0 - ndv);
    vec3 env = skyGradient(vec3(r.x, abs(r.y), r.z)) * (r.y < 0.0 ? 0.35 : 1.0);
    env *= envF * s.smoothness * s.smoothness * skyLightCurve(s.light.y);

    return min(sun, vec3(40.0)) + env;
}
