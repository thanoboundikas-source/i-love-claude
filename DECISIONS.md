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

## Lighting and shadows

33. **Radial shadow distortion (0.8)**: ~5x texel density near the player,
    coarser far away. Same function in shadow.vsh and every reader.
34. **Acne**: normal offset scaled by the *local* world-space texel size
    (derived from the distortion), larger on surfaces at grazing angles to the
    light, plus a tiny depth bias. No constant world-space offset, so contact
    shadows stay tight near the player.
35. **Soft shadows = rotated Vogel-disk PCF on hardware 2x2 comparisons**
    (4/8/16 taps POTATO-less/REGULAR/INSANE), penumbra ~0.08 blocks (option),
    never below ~1.2 texels so far shadows don't alias. Rotation changes per
    pixel and per frame; TAA resolves it. **No PCSS** (contact-hardening):
    it needs raw depth reads next to hardware comparisons (a required feature
    flag, extra blocker-search taps) — not worth the cost/risk on GL 4.1.
36. **Light leaks**: direct light is multiplied by a sky-light guard
    (smoothstep 0.03..0.30 of the lightmap sky level). Sealed caves have no sky
    light, so no sun can leak in even where the shadow map is coarse.
    Beyond the shadow distance the sky-light proxy takes over with a smooth
    blend, no visible edge.
37. **Coloured shadows**: shadowtex1 (opaque) gives the PCF result; one extra
    shadowtex0 + shadowcolor0 tap tints light that passed a translucent
    caster. Water is marked with alpha 0 in shadowcolor0 and only tints
    lightly (it is clear); stained glass tints by its colour and opacity.
    Deep underwater darkness comes from vanilla's sky light, which drops one
    level per block of water.
38. **lightDir comes from `shadowLightPosition`**, so the direct light always
    matches the shadow map exactly (no mismatch around sunset).
39. **Held item** uses the sky-light proxy at the player's eye instead of the
    shadow map (its depth is fake and the player model would shadow it).
40. **Particles get one shadow tap, glass two** — enough to stop them glowing
    in shade, cheap enough for heavy particle scenes.
41. **Low-light desaturation** in the tonemap (below ~0.06 luminance colour
    fades 45% toward a slightly blue grey): nights and dark caves read as
    night rather than dim daylight; lit areas are untouched.

## Water

42. **Deferred water, forward everything else translucent.** Water writes its
    wave normal, biome tint and sky light to the translucent layer and nothing
    to the scene; composite1 shades it (refraction needs the scene behind it,
    which a gbuffers program cannot read). Glass stays forward so layering
    works. Known consequence: water seen *through* glass is the glass over
    unshaded underwater scene (rare: aquariums).
43. **Reflections: SSR on water only**, at RENDER_SCALE x (0.5 in REGULAR),
    geometric step growth (SSR_STEPS covers 0.25..600 blocks) + 5 binary
    refinement steps, against opaque depth so the surface never hits itself.
44. **Clouds in reflections:** a missed ray looks up the scene pixel in its
    direction at infinity — if that pixel is sky, it already contains the
    exact sky *and the 3D clouds*. Only when that is off-screen or blocked does
    it fall back to the analytic sky + flat clouds. Cheap and accurate.
45. **Absorption from the biome tint** (per block, red absorbed first) over the
    real path length behind the surface: shallow water is clear (clean
    shoreline, no foam — not in spec), deep water takes the biome colour.
46. **Refraction offset shrinks with shallow depth and distance** and is only
    accepted if the bent sample is also behind the surface (no halos of land
    pulled into the water).
47. **Waves are normal-only** (three octaves of moving value noise, fading out
    by 90 blocks so far water doesn't sparkle). No vertex displacement: it
    opens seams at shorelines and against blocks.
48. **Sun glint**: GGX (roughness 0.2) on the wave normal, shadowed by the
    shadow map and cloud shadows.
49. **Underwater**: fog uses vanilla's `fogColor` (biome water fog colour while
    submerged) lit by the eye's sky light; looking up gives Snell's window
    with total internal reflection past the critical angle.
50. **POTATO water** is forward-shaded: sky + flat-cloud reflection, deep
    colour, glint, alpha by Fresnel. SSR/refraction stay off per spec, but
    matte water looked broken.

## Atmosphere

51. **Fog = height haze + border fade**, whichever is stronger. Haze is
    analytic exponential height fog (scale height 55 blocks around sea level),
    density 0.0016/block clear, 0.0075 rain, +0.004 thunder, scaled by
    FOG_DENSITY. Its colour is the sky gradient *behind the object*, so
    distant terrain melts into the horizon (and into the sunset glow toward
    the sun). The border fade (72-98% of render distance) is kept even with
    Distance Fog off, because a visible world edge is never wanted.
52. **Caves stay clean**: haze fades out with the eye's sky light, so
    underground there is no bright sky-coloured fog. Lava, powder snow,
    blindness and darkness get their own fogs.
53. **Water surfaces fog only their reflection + glint**; the refracted scene
    was already fogged to its own distance in deferred1 (avoids double fog).
54. **Godrays are shadow-map volumetric light**, not a screen-space radial
    blur: they appear through trees and window gaps even when the sun is off
    screen, and never smear across the sky. GODRAY_SAMPLES (8 REGULAR, 12
    INSANE) jittered steps up to 160 blocks in the scaled effects pass (alpha
    of colortex4); Henyey-Greenstein phase (g=0.72) and colour are applied at
    full resolution in composite1. Strength 0.10 x option — "subtle". Off
    underground and much weaker in rain.
55. **Wet look**: in rainy biomes (`biome_precipitation == 1`, so no wet
    deserts or snow), sky-exposed surfaces — mostly tops — darken (albedo
    squared toward itself) and gain smoothness 0.85, which the generated
    specular turns into a gloss. Driven by `wetness`, so it dries slowly.

## Post-processing

56. **TAA in its own pass (composite2)**, full resolution, history in RGBA16F
    colortex5. Camera-only reprojection (per-object motion vectors would need
    another full-res buffer written by every entity program); moving mobs
    rely on the neighbourhood clip, which keeps ghosting to a faint trail at
    most. Variance clip (1.25 sigma) in YCoCg, in a compressed x/(1+luma)
    space so bright pixels don't flicker. Current-frame weight 0.09 standing
    still, up to 0.30 while moving (sharper in motion). Held item is not
    reprojected. NaN/inf history is discarded.
57. **Bloom has no pass of its own**: Iris generates colortex2's mip chain just
    before final; final gathers levels 2-6 with a 4-tap tent each. A soft
    knee (l/(l+0.9)) means midtones barely bloom and the image stays clean;
    the sun, lava, glowstone and bright sky glow. Always "half res" or lower
    by construction, so REGULAR's "bloom at half res" is met in every profile.
58. **Sharpening**: 5-tap unsharp mask in final, clamped to the neighbours'
    range (no halos), strength 0.6 x SHARPEN_AMOUNT.
59. **No vignette, no chromatic aberration, no film grain, no lens flare** —
    not in the spec and they work against "clean". Vanilla vignette is off.

## Generated PBR

60. **Normals are edge bevels, not per-texel tilts.** Brightness = height;
    each texel keeps a flat middle and its outer 28% bevels toward the
    neighbour's height. The first version (one gradient per texel) looked
    like noise in the preview renderer; bevels read as raised/sunken pixels —
    cobblestone stones, brick mortar, plank grooves — which suits pixel art
    and stays vanilla-faithful. Neighbours wrap inside the block's own sprite
    (bounds from `mc_midTexCoord`), so no bleeding from the next atlas tile.
    Strength fades out between 10 and 36 blocks: no distant sparkle.
    Terrain only; plants/leaves and glowing blocks are skipped.
61. **Specular from stable cues only**: metal blocks (block.properties ID 20)
    get smoothness 0.55-0.85 with coloured (albedo) F0 and reduced diffuse;
    flat, low-contrast bright textures (concrete, quartz, polished stone) get
    up to 0.30; everything else is matte. Rain gloss (wet look) comes on top.
    Guessing more materials from colour alone produced plastic-looking grass
    and dirt in tests, so it doesn't.
62. **Specular lighting**: GGX sun/moon highlight (clamped to avoid fireflies)
    plus a sky-gradient reflection weighted by smoothness² and sky light —
    enough for wet ground, iron and polished stone without SSR on every
    surface (which the spec does not ask for and the frame budget can't pay).

## Profiles and dimensions

63. **Profiles list every performance-relevant option** (identical key set in
    all three) so Iris always recognises which profile is active. Defaults in
    settings.glsl equal REGULAR. User taste options (brightness, saturation,
    cloud thickness, fog amount, strengths, sun angle, FULLBRIGHT) are in no
    profile, so switching profile never resets them — FULLBRIGHT works in all
    three.
64. **What each profile actually runs** (passes, not just flags):
    POTATO = gbuffers + deferred1 + translucents + final (no shadow pass, no
    cloud pass, no composites; flat clouds, forward water, tonemap only).
    REGULAR = everything; clouds at 0.75x; reflections + godrays at 0.375x
    (0.75 x half); 2048 shadow map / 128 blocks / 8 taps; 8 godray samples;
    16 SSR steps. INSANE = everything; clouds, reflections, godrays at 1.0x;
    4096 / 192 blocks / 16 taps; 12 godray samples; 32 SSR steps.
65. **Nether and End use a small forward fallback** (`shaders/nether`,
    `shaders/end`, selected by dimension.properties): vanilla's own lightmap
    (which already carries each dimension's ambient light and block light),
    simple face shading, vanilla-style fog toward `fogColor`, the Solstice
    tonemap/saturation, FULLBRIGHT and night vision. No shadows, clouds or
    post there yet — those are the later prompts. The End sky box is drawn
    as-is; anything uncovered shows vanilla's fog colour.

## Fixes after first in-game test

66. **2026-09-24, pack failed to load: `gbuffers_line` removed.** Lunar's log
    hides Iris's error text, so the failure was reproduced offline by running
    Iris's real patcher (from the iris jar) on every draw type and linking the
    result on Apple GL: only `LINES -> gbuffers_line` failed ("syntax error:
    #version"). Iris only takes its core-profile line path when the pack ships
    `gbuffers_line`; without it, outlines use `gbuffers_basic` via the normal
    path, which also widens lines correctly. This check is now stage 3 of
    check.sh.
