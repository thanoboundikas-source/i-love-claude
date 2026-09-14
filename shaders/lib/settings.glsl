/*
    Solstice — settings.glsl
    Every user-facing option lives here. Each program includes this file, so
    option macros are defined identically everywhere (required by Iris).
*/

//#define FULLBRIGHT //Lifts the minimum light level so caves are visible without torches.

#define RENDER_SCALE 1.0 // [0.5 0.6 0.7 0.75 0.8 0.9 1.0] Resolution multiplier for the expensive passes. Wired in Phase 1, takes visible effect in Phase 2.
