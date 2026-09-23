/*
    Solstice — settings.glsl
    Every user-facing option lives here and every program includes this file,
    so each option macro is defined identically everywhere (Iris requirement).
    Defaults match the REGULAR profile, so the profile button shows REGULAR.

    Rule: every feature is a toggle, and the pack must compile with any
    combination of toggles off. check.sh enforces that.

    Iris treats any value-less "#define NAME" that is tested with #ifdef as a
    menu option. Internal helper macros therefore always carry a value
    ("#define NAME 1") so they never show up in the menu.
*/

// ---------------------------------------------------------------- General
//#define FULLBRIGHT //Lifts the ambient light floor so caves are visible without torches. Keeps the colour grading.
#define RENDER_SCALE 75 // [50 60 70 75 80 90 100] Resolution of the expensive screen passes (volumetric clouds, water reflections, godrays).
#define HALF_RES_FX //Runs reflections and godrays at half of the Render Scale (REGULAR). Off = same as Render Scale (INSANE).
#define EXPOSURE 100 // [70 80 90 100 110 120 130] Overall brightness, percent.
#define SATURATION 105 // [90 95 100 105 110 115 120] Colour saturation after tonemapping, percent.

// ---------------------------------------------------------------- Sky
#define STARS //Procedural stars at night.

// ---------------------------------------------------------------- Clouds
#define CLOUDS //Clouds with vanilla shapes. Off = no clouds at all.
#define CLOUDS_3D //Thick blocky volumetric clouds. Off = cheap flat vanilla-style layer.
#define CLOUD_SHADOWS //Clouds cast soft shadows that drift across the ground.
#define CLOUD_THICKNESS 8 // [4 6 8 10 12] Height of the blocky clouds in blocks (vanilla is 4).
#define CLOUD_STEPS 24 // [16 24 32] Cloud cells traced per pixel. More reaches further at low angles.

// ---------------------------------------------------------------- Lighting and shadows
#define SHADOWS //Sun and moon cast real shadows.
const int shadowMapResolution = 2048; // [1024 1536 2048 3072 4096]
const float shadowDistance = 128.0; // [96.0 128.0 160.0 192.0 256.0]
#define SHADOW_SAMPLES 8 // [4 8 12 16 24] Shadow filter taps. More = smoother soft edges, slower.
#define SHADOW_SOFTNESS 100 // [50 75 100 150 200] Width of the soft shadow edge, percent.
#define COLORED_SHADOWS //Stained glass and water tint the light that passes through them.
#define COLORED_LIGHT //Block light takes the colour of nearby glowing blocks on screen (soul fire blue, lava orange, redstone red).
#define FOLIAGE_SSS //Leaves and plants let some sunlight through.
const float sunPathRotation = -30.0; // [-45.0 -30.0 -20.0 -10.0 0.0 10.0 20.0 30.0 45.0]

// ---------------------------------------------------------------- Water
#define WATER_WAVES //Gentle animated waves on water.
#define WATER_REFLECTIONS //Screen-space reflections on water. Sky and clouds still reflect when off.
#define WATER_REFRACTION //The underwater scene bends through the surface.
#define SSR_STEPS 16 // [8 12 16 24 32] Reflection ray steps.
#define UNDERWATER_FOG //Tinted fog while the camera is under water.

// ---------------------------------------------------------------- Atmosphere
#define FOG //Distance fog matched to the sky colour, thicker in rain.
#define FOG_DENSITY 100 // [50 75 100 125 150 200] Distance fog amount, percent.
#define GODRAYS //Subtle light shafts from the sun and moon (needs Shadows).
#define GODRAY_STRENGTH 100 // [50 75 100 150 200] Godray brightness, percent.
#define GODRAY_SAMPLES 8 // [6 8 12 16] Godray samples per pixel.
#define WET_LOOK //Surfaces darken and turn glossy in the rain.

// ---------------------------------------------------------------- Post
#define BLOOM //Soft glow around bright things.
#define BLOOM_STRENGTH 100 // [50 75 100 150 200] Bloom amount, percent.
#define TAA //Temporal anti-aliasing: smooth edges, stable shimmer-free image.
#define SHARPEN //Light sharpening after TAA.
#define SHARPEN_AMOUNT 50 // [25 50 75 100] Sharpening strength, percent.

// ---------------------------------------------------------------- Generated PBR
#define GENERATED_NORMALS //Bumpy surface detail generated from the vanilla textures.
#define NORMAL_STRENGTH 100 // [50 75 100 150 200] Generated normal strength, percent.
#define GENERATED_SPECULAR //Glossiness and metal highlights generated from the vanilla textures.

// ---------------------------------------------------------------- Derived (not options)
#ifdef HALF_RES_FX
    #define FX_SCALE (float(RENDER_SCALE) * 0.005)
#else
    #define FX_SCALE (float(RENDER_SCALE) * 0.01)
#endif
#define CLOUD_SCALE (float(RENDER_SCALE) * 0.01)

// Features that depend on other features.
#if defined GODRAYS && defined SHADOWS
    #define GODRAYS_ACTIVE 1
#endif
#if defined WATER_REFLECTIONS || defined WATER_REFRACTION
    #define WATER_DEFERRED 1
#endif
#if defined CLOUDS && defined CLOUDS_3D
    #define CLOUDS_VOLUMETRIC 1
#endif
#if defined CLOUDS && defined CLOUD_SHADOWS
    #define CLOUD_SHADOWS_ACTIVE 1
#endif
#if defined SHADOWS && defined COLORED_SHADOWS
    #define COLORED_SHADOWS_ACTIVE 1
#endif
// TAA_JITTER (sub-pixel camera jitter) is switched on together with the TAA
// resolve pass in the post-processing step; jitter without a resolve shakes.
