# Solstice — design decisions

Judgment calls made while building the Overworld without Chris available.
Each entry says what was chosen and why. Nothing here is sacred: if it looks
wrong in-game, say so and it changes. (The previous session's draft decisions
are preserved in git history, commit d1cb592.)

## Setup

1. **Repo moved into the active Lunar profile.** Lunar runs with isolated
   profiles (`-Dichor.usingIsolatedProfiles=true`, game dir
   `~/.lunarclient/profiles/fullbright-4`), so Iris only sees packs in that
   profile's `shaderpacks/`. The repo now lives there; the old
   `~/Library/Application Support/minecraft/shaderpacks/Solstice` path is a
   symlink to it. Stale copies in the `n` and `test` profiles are left alone.
2. **Reload key is I on this profile** (Iris default R is rebound). Docs and
   TESTING.md use I.
3. **check.sh compiles 65+ option configurations** (defaults, each profile,
   all toggles off, all on, each toggle flipped, each value option at its
   extremes) so "any combination of toggles off" is actually tested, not
   hoped for.
4. **Internal macros always carry a value** (`#define GB_TERRAIN 1`). Found in
   the Iris source (OptionAnnotatedSource): a value-less `#define X` that is
   tested with `#ifdef` becomes a menu option. check.sh now fails on it.
5. **No reversed smoothstep.** `smoothstep(a, b, x)` with a >= b is undefined in
   GLSL and Metal; Apple GPUs are allowed to return garbage. check.sh fails on it.

## Pipeline architecture (Mac-first)

6. **Deferred opaques, forward translucents.** Opaque geometry writes a small
   packed G-buffer (12 bytes/pixel: RGBA8 albedo+AO, RGBA16 normal/light/material);
   one full-res pass lights it. Forward shading every opaque fragment with
   shadow filtering would repeat that work for every overdrawn leaf (cutout
   geometry defeats Apple's hidden-surface removal). Translucents stay
   forward so glass-behind-glass layering works like vanilla.
7. **Few buffers, reused.** colortex1 holds the opaque G-buffer, then the
   translucent layer data (water normal/tint) after the deferred pass — the
   opaque data is dead by then. A marker bit (bit 15 of alpha) that the opaque
   layout never sets tells the two apart, so particles or lines in front of
   leaves can never be mistaken for water.
8. **Scene buffer is R11G11B10F** (4 bytes/pixel) rather than RGBA16F (8).
   Precision is enough for HDR colour; smooth gradients are dithered where
   they are produced and in the final 8-bit output. TAA history keeps
   RGBA16F because accumulation needs the extra bits.
9. **"Unknown draw order" programs write twice.** Glint, spider eyes, beacon
   beams, lines and forward programs write both the albedo buffer and the HDR
   scene buffer. Whichever side of the deferred pass Iris draws them on, the
   right copy shows. Cheaper and safer than guessing Minecraft 26.1's feature
   render order.
10. **Clears only where needed.** The scene, cloud, effects and TAA buffers
    are fully rewritten each frame, so their clears are disabled (saves full-
    screen writes). The G-buffer clears to zero (colortex1 would otherwise
    clear to white, which sets the translucent marker bit).
11. **Vanilla AO kept, but only on sky/block light** (`separateAo=true`), so
    block corners in full sun stay clean while shade keeps vanilla's soft
    corners. If Iris' separateAo does not activate (the docs mention a bug
    without a shadow pass, i.e. POTATO), AO falls back to vanilla's baked
    look — still correct, just applied to all light.
12. **TAA jitter is gated on the TAA pass existing** (`TAA_JITTER`), so no
    intermediate build ever shakes.

## Sky

13. **Stylised, not physically based.** A hand-tuned palette (day zenith,
    horizon, sunset toward/away from the sun, night) instead of Rayleigh/Mie
    scattering. Physically based skies trend toward the filmic/desaturated
    look the spec rules out, and a palette is trivially cheap and tunable.
14. **Sunset band hugs the horizon** (exp falloff ~9x faster than the day
    horizon gradient) and the zenith is blended to a blue-violet, so dawn and
    dusk are orange only near the sun and purple opposite it — never orange
    soup.
15. **One palette drives everything**: sky, fog colour, sun/moon/ambient light
    and (next step) cloud lighting come from the same values, so terrain,
    fog and sky always agree.
16. **Sun and moon are procedural discs** (sun ~1.8° radius, limb darkening,
    HDR so bloom makes the glow; moon ~2° with all 8 phases and subtle maria).
    Crisper than vanilla's square textures, and they rotate correctly with
    sunPathRotation because they come from `sunPosition`/`moonPosition`.
17. **Stars turn with the sky.** The star field is rotated with the same
    rotation chain Iris uses for the shadow camera, driven by `sunAngle`
    (checked in the Iris source), so there is no jump at sunset.
18. **Biome sky colour is not used.** Vanilla's `skyColor` barely varies with
    biome and its time-of-day curve fights the palette. Clean and consistent
    won over faithful-to-a-subtle-vanilla-detail.
19. **sunPathRotation defaults to -30°** so noon shadows are angled
    (menu-adjustable).

## Lighting calibration (tuning knobs, easy to change)

20. Noon sun 1.15, day sky ambient 0.62 (bluish white), sunlit/shaded ratio
    about 3:1 in linear light — brighter shade than Bliss/Photon, closer to
    Complementary's bright look while keeping depth. Ambient keeps vanilla's
    face shading (top 1.0, sides 0.8, bottom 0.6).
21. **Block light curve** keeps a long gentle tail (levels 3–6 stay visible)
    with a hot core near torches; warm torch colour (1.0, 0.6, 0.3).
22. **Tonemap maps midtones 1:1** and only rolls off above 0.55, applied to
    the brightest channel so saturation is preserved; hot highlights drift
    toward white. Saturation option defaults to 105%.

## Clouds

23. **The game's own `clouds.png` is the cloud map** (bound with Iris'
    `customTexture` from `minecraft:textures/environment/clouds.png`, checked
    in the Iris source). Shapes are therefore exactly vanilla's — it is the
    vanilla asset, not code from another pack.
24. **Blocky volumes by grid walk, not noise ray-marching.** Each 12x12 cell is
    extruded to `CLOUD_THICKNESS` (default 8, vanilla is 4 — "thick" per the
    spec) from the vanilla cloud height up. The ray visits each crossed cell
    once (one texel fetch per cell, `CLOUD_STEPS` fixed), so cost is ~25 texel
    reads per pixel at reduced resolution. Cheap, deterministic (nothing for
    TAA to smear) and perfectly blocky.
25. **Lit like solid objects.** Each cloud segment is shaded by the face the
    ray entered through: sunlit tops, sun-facing sides, softly lit far sides
    (0.2 wrap light for scattering), undersides lit by the horizon/sunset
    colour. Two taps toward the sun darken faces shadowed by other clouds.
    Crossing into a neighbouring cloud cell keeps the entry face, so no grid
    lines appear inside a cloud (found and fixed with the preview renderer).
26. **Soft edges come from optical depth**: a ray clipping a corner passes a
    short distance through the cloud and is partly transparent (density 2.2
    per block). Clearly blocky, slightly soft.
27. **Distance**: clouds blend toward the sky colour behind them
    (exp(-d/900)) and thin out between 1100 and 2400 blocks — no hard edge.
28. **Drift speed 0.853 blocks/s** (vanilla ~0.6). Chosen so 3600 s of
    `frameTimeCounter` (which Iris wraps hourly) moves exactly one texture
    period (3072 blocks) — the wrap is invisible.
29. **Volumetric pass runs at RENDER_SCALE** into a genuinely smaller buffer
    (`size.buffer.colortex3`), picked with `#if RENDER_SCALE == …` in
    shaders.properties. Upsampling artefacts are suppressed analytically:
    terrain nearer than the cloud layer never receives clouds.
30. **Rain darkens clouds** (x0.62, thunder x0.75 more) but does not change
    coverage — vanilla's map has no rain variant and inventing one would be
    an unrequested feature.
31. **POTATO / 3D off gets a flat layer**, not nothing: 4 texel reads,
    smooth-filtered, at mid-cloud height. The sky looks dead without clouds
    and the cost is negligible. `CLOUDS` off removes clouds entirely.
32. **Cloud shadows** project the surface along the light onto the middle of
    the cloud layer and read the smooth coverage (12-block soft edge),
    strength 55%, faded out in rain and at low sun.
