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
    *Changed 2026-09-24, see #67:* AO is now squared, i.e. applied at
    vanilla's visible strength (AO_STRENGTH, default 100; 50 = the old look; 0
    = off), still only on sky/block light, never on direct light.
12. **TAA jitter is gated on the TAA pass existing** (`TAA_JITTER`), so no
    intermediate build ever shakes.

## Sky

13. **Stylised, not physically based.** A hand-tuned palette (day zenith,
    horizon, sunset toward/away from the sun, night) instead of Rayleigh/Mie
    scattering. Physically based skies trend toward the filmic/desaturated
    look the spec rules out, and a palette is trivially cheap and tunable.
    *Changed 2026-09-24, see #67:* palette DAY_ZENITH (0.08,0.22,0.80),
    DAY_HORIZON (0.34,0.56,1.00), SUNSET_ZENITH (0.07,0.13,0.44), horizon
    falloff exp(-8h) (was -6h).
14. **Sunset band hugs the horizon** (exp falloff ~9x faster than the day
    horizon gradient) and the zenith is blended to a blue-violet, so dawn and
    dusk are orange only near the sun and purple opposite it — never orange
    soup.
    *Changed 2026-09-24, see #67:* SUNSET_AWAY (0.42,0.29,0.52) mixed 0.75
    into the horizon, SUNSET_AFTERGLOW (0.66,0.26,0.42); the band is gated off
    above sun elevation 0.32; sun halo pow8*0.04 + pow120*0.22 (was pow5*0.07
    + pow60*0.30).
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
    *Changed 2026-09-24, see #67:* noon key 1.42 x (1,0.91,0.78) warming to
    (1,0.55,0.24) at the horizon (SUNLIGHT_NOON/GOLDEN, separate from the
    sun-disc tint); fill 0.40 x (0.56,0.72,1.00), sunset fill 0.30 x
    (0.62,0.56,0.84), night 0.040; about 5:1 sunlit:shaded tops; sun and moon
    exactly 0 at elevation 0 (no switch pop); faces 1/0.70/0.40; BOUNCE_LIGHT;
    rain direct 0.075, rain fill x0.95.
    *Changed again 2026-09-24 (review), see #69:* sunset fill (0.88,0.70,0.62)
    x 0.40 (warm peach, was lilac 0.30); the key keeps full strength down to
    the horizon (the x0.72 low-sun factor is gone).
    *Changed again 2026-09-24 (second review), see #80:* at a low sun the
    key's N.L is lifted (GOLDEN_LIFT, lighting.glsl) and the key tint reaches
    its noon colour at sun height 0.55 (was 0.45).
21. **Block light curve** keeps a long gentle tail (levels 3–6 stay visible)
    with a hot core near torches; warm torch colour (1.0, 0.6, 0.3).
    *Changed 2026-09-24, see #67:* torch colour graded from TORCH_FAR
    (1,0.46,0.16) to TORCH_NEAR (1,0.66,0.36) (TORCH_COLOR (1,0.56,0.26) on
    forward/water paths), curve 1.8b^5 + 0.30b^2.5 + 0.02b.
    *Changed again 2026-09-24 (review), see #70:* linear tail 0.06b (was
    0.02b), so light levels 2-6 stay readable in caves.
22. **Tonemap maps midtones 1:1** and only rolls off above 0.55, applied to
    the brightest channel so saturation is preserved; hot highlights drift
    toward white. Saturation option defaults to 105%.
    *Changed 2026-09-24, see #67:* FILMIC_CURVE (default on) adds a toe (t =
    0.04 x FILMIC_CONTRAST, a = 0.2) and a shoulder at 0.50, pivot 0.18 (0.18
    in = 0.18 out). Off gives exactly this old curve.
    *Changed again 2026-09-24 (review), see #70:* the toe's black slope follows
    the night/underground gate, a = mix(0.2, 0.55, gate): unchanged by day,
    much gentler at night and in caves.
    *Changed again 2026-09-24 (second review), see #81:* at night and
    underground the low-light shift pulls non-warm pixels toward a moonlit
    blue (MOONLIT_TINT); daytime and warm (block-lit) pixels are unchanged.

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
    *Changed 2026-09-24, see #67:* clouds are lit by the sun first (0.22
    unshadowed scattered sun on every face), sky ambient 0.8x + 0.15 zenith,
    sunset glow x(1 + 1.2 sunsetF).
26. **Soft edges come from optical depth**: a ray clipping a corner passes a
    short distance through the cloud and is partly transparent (density 2.2
    per block). Clearly blocky, slightly soft.
27. **Distance**: clouds blend toward the sky colour behind them
    (exp(-d/900)) and thin out between 1100 and 2400 blocks — no hard edge.
    *Changed 2026-09-24, see #67:* haze 0.60 x (1 - exp(-d/1400)), thinning
    800-2000 blocks.
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
    *Changed 2026-09-24, see #67:* gated by night/underground: full strength
    at night or with little sky light at the eye, 0.2x on the daytime surface,
    so dark materials in daylight shade keep their colour.

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
    *Changed 2026-09-24, see #67:* absorption (1-t) x 0.50 + (0.06,0.04,0.02)
    (clearer shallows, bluer deep water).
46. **Refraction offset shrinks with shallow depth and distance** and is only
    accepted if the bent sample is also behind the surface (no halos of land
    pulled into the water).
47. **Waves are normal-only** (three octaves of moving value noise, fading out
    by 90 blocks so far water doesn't sparkle). No vertex displacement: it
    opens seams at shorelines and against blocks.
    *Changed 2026-09-24, see #67:* wave amplitude 0.30 (was 0.45), scatter
    x0.60 (was 0.42), offsets the darker fill.
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
    *Changed 2026-09-24, see #67:* od = (mix(0.0002,0.0048,rain) + 0.003 storm
    + 3.6e-6 d) x d x height term; colour capped at 0.20 lum(direct) + 0.55
    lum(ambient); border 84-99% of render distance; haze and border applied as
    two mixes, not max().
    *Changed again 2026-09-24 (review), see #74:* the colour cap relaxes as
    the haze thickens (cap = mix(cap, sky, haze)), so rain fog converges on
    the sky colour.
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
    *Changed 2026-09-24, see #67:* march 48 blocks, visibility squared, no
    +0.03 isotropic term, strength 0.08, low-sun factor mix(0.6, 1,
    smoothstep(0, 0.3, light elevation)).
    *Changed again 2026-09-24 (review), see #73:* shaft weight
    vis^2 x (1 - smoothstep(0.75, 1, vis)): a fully lit ray adds nothing.
    *Replaced 2026-09-24 (second review), see #77:* weight vis^2 again, the
    effects pass stores the shadow deficit, and composite1 turns it into
    shafts by comparing each pixel with 4 neighbours across the shafts.
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
    *Changed 2026-09-24, see #67 and #72:* history fetched with a 5-tap
    Catmull-Rom filter, clamped to the central 2x2 texels (anti-ringing).
57. **Bloom has no pass of its own**: Iris generates colortex2's mip chain just
    before final; final gathers levels 2-6 with a 4-tap tent each. A soft
    knee (l/(l+0.9)) means midtones barely bloom and the image stays clean;
    the sun, lava, glowstone and bright sky glow. Always "half res" or lower
    by construction, so REGULAR's "bloom at half res" is met in every profile.
    *Changed 2026-09-24, see #67:* threshold 1.0 with soft knee 0.5 (only real
    highlights bloom), flat level weights 0.2, strength 0.20 x BLOOM_STRENGTH,
    mip levels offset by log2(viewHeight/1080) so the glow size does not
    depend on resolution.
    *Changed again 2026-09-24 (review), see #71:* threshold 1.8, knee 0.3:
    nothing below HDR luminance 1.5 blooms (sunlit snow is ~1.3).
58. **Sharpening**: 5-tap unsharp mask in final, clamped to the neighbours'
    range (no halos), strength 0.6 x SHARPEN_AMOUNT.
59. **No vignette, no chromatic aberration, no film grain, no lens flare** —
    not in the spec and they work against "clean". Vanilla vignette is off.
    *Changed 2026-09-24, see #67:* vignette and split toning are now IN (owner
    asked for cinematic), each with its own toggle and strength; still no
    chromatic aberration, film grain or lens flare.
    *Split toning changed 2026-09-24 (review), see #75:* daytime surface only,
    and blue pixels are never cooled.
    *And again (second review), see #78:* the sky (depth 1) is masked out.

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

## Clear cinematic pass (owner feedback 2026-09-24)

67. **2026-09-24, Chris: "too hazy, make it more cinematic, the lighting
    looks bad". Look v2 "clear and cinematic".** Diagnosis: the three
    complaints had one cause, nothing in the frame was allowed to be dark or
    distant. (a) Clear-weather fog was linear from 0 m (4.9/9.6/18.2% at
    32/64/128 blocks) toward a horizon colour 3-30x brighter than terrain;
    (b) the sky fill was 42% of the sun, so shade was pale (3.1:1); (c) the
    tone curve was the identity below 0.55, so blacks sat on a raised floor;
    plus godrays with a +0.03 isotropic glow over 160 blocks, a bloom knee
    that let 40% of the sky and 18% of terrain bloom, a near-white horizon
    band and a pow5 sun halo that whitened 60 degrees of sky. Changes (all
    constants in the entries marked "see #67"):
    - **Clear air** (#51, #54, #13/#14, #25/#27, #45/#47): quadratic
      clear-air haze (1.0/2.7/8.0% at 32/64/128) with a luminance-capped
      colour, so far hills become blue silhouettes a little darker than the
      sky; narrow border fade; godrays are near shafts only; deeper sky with
      a narrow horizon band and tight halo; clouds lit by the sun (white, not
      lavender); clear blue water.
    - **Motivated lighting** (#20, #21, #11): warm strong key, cooler darker
      fill (5:1), golden hour directional to the horizon, sun and moon both 0
      at the horizon (no pop); stronger face shading (0.70/0.40) with warm
      ground bounce (BOUNCE_LIGHT) so shaded sides are not muddy blue;
      vanilla-strength AO in shade (AO_STRENGTH); torch pools with a hot core
      and amber edge.
    - **Cinematic grade** (#22, #41, #57, #59, #68): hue-preserving toe +
      shoulder (FILMIC_CURVE, FILMIC_CONTRAST), split toning gated by hue so
      the blue sky and warm lights are never tinted (SPLIT_TONING,
      SPLIT_TONE_STRENGTH), subtle vignette (VIGNETTE, VIGNETTE_STRENGTH:
      -25% linear in the corners at 100%), thresholded bloom, optional
      darken-only local contrast (LOCAL_CONTRAST, off: it forces the mip
      chain), TAA history with a 5-tap Catmull-Rom fetch (keeps 73% of 4 px
      detail in motion instead of 47%).
    - All new options are taste options in no profile (#63), under O >
      Colour Grading and O > Lighting & Shadows. No new passes, buffers or
      uniforms; loop bounds unchanged.
    - Not adopted from the audits: fill 0.37 / sunset fill 0.20 and faces
      0.64 + 0.36 n.y (muddy golden hour and near-black shaded dirt steps
      together with the toe); desaturation range 0.002-0.035 (replaced by the
      day/night gate); DAY_HORIZON (0.42,0.62,1.00) and a pow8*0.05 halo (the
      deeper palette was used); cloud thinning 1100-2400 (800-2000 cleans the
      horizon band).
    - Preview, INSANE, before -> after (AO-enabled preview for both): noon
      terrain saturation 0.53/0.49 -> 0.61/0.58, noon p5 luma 0.23 -> 0.11,
      noon p90/p10 2.3 -> 4.5, sunset p90/p10 1.4-1.6 -> 2.1-2.5, rain
      saturation 0.37/0.31 -> 0.46/0.41, noon sky saturation 0.35 -> 0.40-0.42,
      far lake water hue 200 -> 207 degrees, godray on/off difference at noon
      0.56 -> 0.30 levels, noon mean -7%/-12%, night mean unchanged
      (+1%/-5%), sunlit grass unchanged (within 2% with the vignette off).
      Sunset/rain frames are darker (0.24 -> 0.16-0.18, 0.33 -> 0.23-0.25):
      that is the old fog wash going away. First knobs if Chris finds them
      too dark (corrected to the current values, #79): golden hour
      FILMIC_GOLDEN_GAIN 1.12 -> 1.20 (final.fsh) or GOLDEN_LIFT 0.73 -> 0.85
      (lighting.glsl), sunset fill ambSunset x0.40 -> x0.46 (sky.glsl), rain
      weatherDirect 0.075 -> 0.10 (sky.glsl). Lower each one to go darker.
    - Blind spots of the 80x80-block preview, to confirm in game: fog past
      ~57 blocks and the border fade (checked numerically), caves (x1.25
      gain and the 0.80 night toe since #84, the desaturation gate and,
      since #81, the moonlit low-light tint), underwater (fog light ~26%
      darker with the new fill), Nether/End (x1.10 since #84). Overrides
      the old "Not filmic" spec line.
    - *Note 2026-09-24 (third review), see #85:* every preview number in
      #67-#82 was measured with a preview grass about twice as green and
      bright as vanilla plains grass. #85 re-measures the acceptance list
      on vanilla colours and restates the albedo-dependent criteria.
68. **Fixed time-of-day exposure for the cinematic toe.** The toe darkens dim
    scenes most, so final.fsh multiplies by 1.5 at night or underground
    (FILMIC_NIGHT_GAIN; 1.25 with FULLBRIGHT, whose toe is halved) and by
    1.25 at golden hour, sun elevation 0-0.30 (FILMIC_GOLDEN_GAIN).
    dim_final uses 1.25 when FILMIC_CURVE is on. Tested in the design pass: night gain
    1.3/1.5/1.7: night mean 0.142/0.155/0.167 (old 0.156). Golden gain 1.25
    moves the sunset mean from 0.159 to 0.181. It is a uniform-driven curve
    (sunAngle, eyeBrightnessSmooth), not a histogram: no extra pass.
    Underground counts as night, so a torch-lit cave looks the same at noon
    and midnight; entering a cave ramps up over eyeBrightnessSmooth's lag,
    which reads like eye adaptation. Lower FILMIC_NIGHT_GAIN to 1.3 if caves
    look too bright.
    *Changed 2026-09-24 (review), see #69/#70:* night/underground gain 1.35,
    golden gain 1.40 over sun height 0-0.40, dim_final x1.15.
    *Changed again 2026-09-24 (second review), see #80:* golden gain x1.12
    (FILMIC_GOLDEN_GAIN) with the sun above ~3 degrees, rising to x1.40
    (FILMIC_HORIZON_GAIN) as the key fades out at the horizon.
    *Changed again 2026-09-24 (third review), see #84:* night/underground
    gain x1.25 (FULLBRIGHT x1.125), dim_final x1.10.

### Review fixes (two critics on look v2, 2026-09-24)

Two reviews of the first look-v2 commit (a visual one on re-rendered
previews, a technical one on the diff) found eight problems. All fixed; the
constants are in the entries above marked "see #69-#76". check.sh: 80
configs, 2497 compiles, 0 errors / 0 warnings; Apple GL 2497 and Iris
patcher stage 193, 0 failed. Preview criteria from #67 still hold (35/35
measured tiles); numbers below are INSANE, bottom 55% of each tile, sRGB.

69. **Golden hour was dull olive.** Sun at 4-13 degrees: a flat top gets
    almost no key (N.L = sin elevation), so it was lit by a lilac fill, and
    the ground sat about 2 stops under noon with a blue cast. The old preview
    hid it (sunrise/sunset presets are 1.6 degrees, morning 18.6). Changes:
    sunset fill vec3(0.88, 0.70, 0.62) x 0.40 (a warm peach sky light; the
    critic's (0.92, 0.68, 0.58) tipped the "no orange wash toward the sun"
    check to G/R 1.38, this one keeps 1.42); the key's x0.72 low-sun factor
    removed (godrayLight's lowSun term already keeps shafts in check);
    FILMIC_GOLDEN_GAIN 1.25 -> 1.40 and its gate widened from sun height 0.30
    to 0.40 (at 6 degrees the old gate only gave x1.17). The combined gain
    now runs ~1.40 through twilight into the night's 1.35 with no dip.
    Result, HEAD -> now: ground mean at 6 degrees 0.22 -> 0.27 (+21%), sunset
    0.16-0.18 -> 0.22-0.24 (+34%), ground b/g 0.46-0.49 -> 0.41-0.42 (less
    blue), saturation 0.59-0.61. The pre-v2 look had 0.28-0.29 at 6
    degrees, but hazy (saturation 0.43-0.48), so golden hour is back to its
    old brightness without the veil. Morning (18.6 degrees) +3%, noon
    unchanged. tools/preview.py has "golden am" / "golden pm" presets (sun
    ~6 degrees) at the end of the world, hut and lake sheets.
    *Correction 2026-09-24 (third review), see #85:* "back to its old
    brightness" was an artefact of the too-green preview grass. With
    vanilla grass colours the golden-hour ground is 7-26% darker than the
    pre-v2 look (sunlit grass brighter and golden, shade much deeper).
    *Changed 2026-09-24 (second review), see #80:* the x1.40 gain lifted
    the shade along with the ground and kept golden hour flat (lit/shade 1.2
    on grass tops). The warmth now comes from a low-sun key lift, and the gain
    is x1.12 (x1.40 only at the horizon).
70. **Night shadows crushed to black, and torch pools cut off too fast.**
    The toe's black slope a = 0.2 cut everything below ~0.005 linear by 2
    stops, and the x1.5 night gain only made up for that at ~0.035. Now
    a = mix(0.2, 0.55, lowLightGate), so daytime frames are identical and
    night/caves get a gentle toe; FILMIC_NIGHT_GAIN 1.5 -> 1.35; torch curve
    tail 0.02b -> 0.06b. Night ground: pixels below 12/255 13.0/18.4% ->
    6.6/8.6%, p5 8 -> 10-11 /255, mean vs pre-v2 +4.7% / +1.6%. Cave stone
    lit by a torch (modelled through the whole chain), light levels
    2/3/4/5/6: HEAD 2/3/5/9/16, now 5/8/12/17/23 (pre-v2 5/8/13/18/25);
    level 15 stays a hot ~177 (pre-v2 126). dim_final's lift 1.25 -> 1.15:
    with the gentler toe (it passes gate 1), 1.25 would have made Nether
    midtones 21-27% brighter than the old curve; 1.15 keeps its usual
    0.03-0.1 range within -5%..+11% (reasoned only, the preview cannot
    render the Nether).
    *Changed 2026-09-24 (third review), see #84:* with vanilla grass
    colours a = 0.55 still left 9.5-12.9% of the night ground under
    12/255. Now a = 0.80 at gate 1, FILMIC_NIGHT_GAIN 1.25, ambNight x0.060,
    dim_final x1.10. (Below the 0.03-0.1 range, a = 0.55 with x1.15 was
    darker than stated: -20% at 0.01.)
71. **Bloom veiled snowy and desert biomes.** A threshold of 1.0 with a 0.5
    knee starts blooming at 0.5; a sunlit snow top at noon is ~1.3. Now
    BLOOM_THRESHOLD 1.8, BLOOM_KNEE 0.3: nothing below 1.5 blooms, which is
    just over the brightest sunlit diffuse surface (~1.4). Emissive blocks
    (~3), lava, glints and the sun (38) still bloom. New preview scene
    `snow` (snow ground, white-concrete stone): bloom on/off difference at
    noon HEAD 0.48 levels mean (max 15) -> 0.00 (max 1); around the sun it
    is still up to 11-14 levels.
72. **TAA drew dark 1 px outlines round very bright pixels in motion.** The
    Catmull-Rom history's negative lobes turned a bright neighbour into a
    negative value (sun disc, glowstone, lava, glints). Fix: clamp the
    result to the min/max of the central 2x2 texels (4 texelFetch reads of
    the texels the centre tap just read, so from the cache). 1D simulation
    of the exact TAA loop (compress, 1.25 sigma clip, motion-weighted blend):
    worst dark-side pixel vs truth, unclamped 0.12-0.61 -> 1.00 in every
    case (sun/sky, glowstone/wall, lava/cave, sunlit/shade; 0.37-4.5
    px/frame). 4 px detail kept in motion: 0.39-0.49 (bilinear 0.26-0.39,
    unclamped 0.46-0.59). The critic's suggested clamp to the 5 bilinear
    taps also removes the outlines, but the taps are already blurred, so it
    clamps every detail peak to a bilinear value and keeps only 0.26-0.39,
    the same as having no Catmull-Rom at all.
73. **Godrays still glowed in open air at a low sun.** vis^2 is 1 for a ray
    with nothing casting a shadow, so a low sun over open land added
    +50-90% linear to backlit terrain. Now godrayAmount uses
    godrayShaftWeight(vis) = vis^2 x (1 - smoothstep(0.75, 1.0, vis)):
    identical to vis^2 for any ray that is at least 25% shadowed (forest
    canopies, window light, cave mouths), zero for a fully lit ray. Chosen
    over the critic's 4 vis (1 - vis): that one lifts heavily shadowed rays
    (vis 0.1 -> 0.36 instead of 0.01), so a dim forest interior would get a
    uniform glow and the lit:shadowed shaft contrast would fall from 9:1 to
    2.3:1. Godray on/off difference: noon 0.30 -> 0.01 levels, sunset
    toward the sun 0.47 -> 0.16 (p99 4 -> 2). The price: no glow in open air
    beside a lone tree seen against the sun. That is what "never an open-air
    glow" in the spec means. The preview mirror uses the same function.
    *Correction and replacement 2026-09-24 (second review), see #77:* this
    weight was not monotonic, and the "price" above left out the worst
    part. At 12 samples a fully lit ray gave 0.000, 11/12 lit 0.218, 10/12
    0.514, 9/12 0.562 (the peak), 6/12 0.250. So a ray a quarter in shadow
    was the brightest in the frame and the fully lit air next to it got
    nothing: lit:shadowed contrast was inverted (0 : 0.56) in the most
    common case, a low sun over land with trees or hills 30-48 blocks out.
    Backlit shade filled in with warm glow (preview, toward-sun tiles:
    shaded grass tops +0.17-0.33 levels, sunlit ones +0.00-0.05), and a
    camera standing in shade got the glow on every ray. Per-pixel jitter
    near vis 1 also flipped rays between 0 and 0.218.
74. **Rain fog: bright band at the world edge.** The haze colour cap
    (sun + sky light) fell to 59% of the horizon sky in rain, so the fog
    plateaued at about half the sky's brightness and then the border fade
    doubled it over the last blocks. Now fogHazeColor(dir, haze) relaxes the
    cap with the haze amount itself: cap = mix(cap, sky luminance, haze).
    Thin haze (all of clear weather within ~150 blocks, near rain fog) keeps
    the cap, and thick fog converges on the sky colour. Model, rain noon,
    far 192: fog at the border start 59% -> 82% of the sky (a clear noon is
    84%), terrain at 160 blocks 0.110 -> 0.141, monotonic into the sky. The
    critic's version (full relaxation whenever it rains) was tested: it also
    greyed the near rain fog, and rain terrain saturation fell to 0.354 on
    one tile (criterion >= 0.40). This version keeps 0.452 / 0.400.
75. **Split toning tinted torch light and the night sky**, which the menu
    text said it never does. Now splitTone(c, lowLightGate) scales both
    weights by (1 - gate), so there is no toning at night, underground, in
    torch-lit caves or in the Nether/End (dim_final passes gate 1). Blue
    pixels are never cooled (the cool weight x (1 - blueness)), which also
    spares the dusk and sunset zenith. Daytime shade is still cooled: the noon
    darkest-quarter b/r is still 1.71-1.76x the sunlit quarter's. Menu text
    (lang, settings.glsl) and the CLAUDE.md spec now say "daytime only".
    *Changed 2026-09-24 (second review), see #78:* it still warmed the warm
    sky (sunset band, sun halo, sunset-lit clouds: +4.5% red, -8% blue on
    the band toward the sun); the sky is now masked by depth.
76. **Preview tooling.** Golden-hour presets (#69), the `snow` bloom test
    (#71), godray mirror via godrayShaftWeight, and the docstring's march
    length corrected (160 -> 48). Unchanged caveats: the 80x80-block preview
    cannot show far fog or the border (#74 is modelled numerically), caves
    (#70 torch levels are modelled), underwater or the Nether/End. The
    "vignette off" corner ratio in #67's criteria (0.86-0.90) was already
    0.78 before this round. That comes from the deeper, narrower sky
    gradient, not the vignette, whose own effect (0.734 on vs 0.779 off)
    matches the design.

### Second review fixes (re-verification of look v2, 2026-09-24)

A technical and a visual re-check of the review fixes found five problems.
All five are fixed below; the constants are in the entries above marked
"see #77-#81". Preview numbers: INSANE (Chris's saved options, `--game`),
sRGB, "ground" = bottom 45% of a tile, "grass lit/shade" = sunlit and
shadowed grass tops picked with a per-pixel mask of the same camera (block
id, sun visibility, face). check.sh: 80 configs, 2497 compiles, 0 errors / 0
warnings; Apple GL 2497 and Iris patcher stage 193, 0 failed. The #67
acceptance list: 34/35; the one miss (rain R tile saturation 0.3997
against 0.40) was already there before this round.

77. **Godrays: monotonic weight, shafts found in screen space.** #73's
    weight was inverted (see its correction). Now godrayShaftWeight(vis) =
    vis^2 again, and the effects pass stores the ray's *shadow deficit*,
    (1 - vis^2) x (1 - exp(-0.012 d)), in colortex4.a: 0 for any ray with
    no shadow caster along it, whatever its length. composite1 reads it at
    the pixel and at 4 neighbours and adds godrayLight(max(max(neighbours)
    - centre, 0)): open air and uniform shadow give 0, lit air beside
    shadowed air gives a shaft, and a shadowed pixel never glows more than
    the lit air next to it (*correction, third review: only true for rays
    of equal length, see below and #83*). Cost: 4 more bilinear taps of the low-res
    buffer and one mat4 x vec4; no pass, buffer or loop. Three changes to
    the reviewer's version, each tested:
    - Deficit, not the lit amount. The suggested max(a0 - min(taps), 0) on
      a = vis^2 x (1 - exp(-0.012 d)) is not 0 in open air: the distance
      term differs between rays, so the sky just above a hill 10 blocks
      away got 0.44 - 0.11 = 0.33 with no shadow anywhere, and all receding
      open ground got a small positive term.
    - Neighbours across the shafts, not +-x/+-y. Sun shafts are parallel in
      the world, so on screen they all run through the vanishing point of
      the light direction; the taps sit perpendicular to the line toward
      it. An edge lying across the shafts (a hill crest under a low sun)
      then gets no rim glow; an edge along them (a trunk) does, which is
      the edge of its shaft.
    - Spacing 1.5% and 4% of the screen height (GODRAY_NEAR/FAR), not 8 FX
      texels: the same on screen in every profile (8 texels are 0.7% of the
      height at INSANE 1080p, 2% at REGULAR). Lit gaps up to ~8% of the
      screen height fill completely. The price: a wider lit beam only
      glows along its edges, and near a shadow edge the glow ends where the
      4% tap leaves the shadow.
    Numbers. Field test (preview's march at 1920x1080, 4 jitter frames,
    golden pm, camera in sun looking across open land with a tree and the
    hut toward the sun): near shadow edges lit air 0.52e-3 HDR vs shadowed
    0.15e-3 (#73: 0.00 vs 0.49e-3, inverted); open air far from any
    shadow 0.04e-3 (plain vis^2 with no neighbour step: 8.7e-3, the veil).
    Camera in a tree's shade looking into the sun: #73 lit the whole sky
    around the sun (every ray 11/12 lit), now only radial streaks from the
    tree. World sheet, godray on/off, toward-sun tiles: #73 shaded grass
    tops +0.17-0.33 levels, sunlit +0.00-0.05; now sunset lit +0.11 /
    shaded +0.03, golden hour at most +0.05 either (well under a level,
    noise). Noon: 0.00-0.01. Not
    resolved (neither was #73): 12 samples over 48 blocks cannot resolve a
    1-block window beam; in-room beams stay invisible. The preview traces
    each neighbour as its own ray; the game bilinear-samples the buffer.
    *Correction 2026-09-24 (third review), see #83:* the deficit makes
    depth edges harmless only in open air, where every deficit is 0. The
    deficit grows with the ray's length, so in shadowed air a short ray to
    a near surface (a backlit trunk, a canopy edge, a wall in shade) got
    the difference in ray length as glow, even when fully shadowed:
    hourglass bands on shaded trunks, and a fully shadowed trunk could
    glow 3.4x more than a real beam beside it. None of the world, hut and
    lake cameras exercised that case. #83 compares rays over the shorter
    march and caps the glow at the ray's own light.
78. **Split toning never touches the sky.** final.fsh reads depthtex0
    (declared only with SPLIT_TONING) and passes surface = 0 for depth 1:
    sky, sun, moon and our clouds, which deferred1 composites onto depth-1
    pixels. Before, the sunset band toward the sun was warmed by up to 8
    levels, and the grey rain/thunder sky cooled by 1-3. World sheet: sky
    pixels bit-identical with SPLIT_TONING on and off in all 20 tiles; the
    sky sheet through the HDR chain too. dim_final passes 1 (its gate of 1
    turns toning off anyway). The menu text was already right.
79. **#67's tuning advice was stale.** Its "too dark" knobs pointed at old
    values (following them would have lowered the golden gain from 1.40 to
    1.35 and the sunset fill from 0.40 to 0.36, the opposite of the aim),
    and its blind-spot gains were 1.5 / 1.25. Now relative to the current
    code (golden gain 1.12, GOLDEN_LIFT 0.73, ambSunset x0.40, rain
    weatherDirect 0.075) and x1.35 caves / x1.15 Nether-End (now x1.25 /
    x1.10, #84; #67 updated).
80. **Golden hour: warm, directional ground.** With the sun at 4-13
    degrees a flat top gets N.L = sin(elevation) ~ 0.1, so it was lit
    mostly by the cool fill, and #69's x1.40 gain lifted fill and shade
    together: ground kept its noon colour and grass lit/shade was 1.2
    (noon 2.7-3.0). Now:
    - GOLDEN_LIFT 0.73 (lighting.glsl): diffuse = pow(N.L, 1 - lift), lift
      = 0.73 x sunsetF while the sun is up. Tops get 0.44 of the key at 6
      degrees (0.11 before), sun-facing sides are unchanged, and it is
      still multiplied by the sun's shadow, so shade stays fill-only and
      cool. The reviewer's wrap, saturate((N.L + k) / (1 + k)), was tried
      first (k 0.45 and 0.70) and gives the same tops, but it also lights
      faces with N.L <= 0: a side facing along the sun got 0.38 of the key.
      The shadow-map path drops those faces (shadowFor), the no-shadow path
      (POTATO, past the shadow distance) does not, so the two would
      disagree. The power curve is 0 at N.L = 0 on every path. It runs to
      the horizon; the sun's own fade (sun height 0-0.05) takes the key
      out, and the moon is never lifted.
    - Key tint reaches its noon colour at sun height 0.55 (was 0.45): a
      slightly more golden key at 5-25 degrees, noon unchanged.
    - FILMIC_GOLDEN_GAIN 1.40 -> 1.12, FILMIC_HORIZON_GAIN 1.40 (new): the
      gain is x1.12 with the sun above ~3 degrees and rises to x1.40 over
      sun height 0.055 -> 0.02, just as the key fades. The reviewer's 1.05
      left the golden-hour ground 3% darker than before; 1.12 keeps its
      mean the same (0.259 both). A smoothstep(0.03, 0.10) ramp (the
      reviewer's) or (0, 0.06) with 1.25 at the horizon was tried: a bump
      at 3 degrees, then a 12-14% drop by 1.6. Sun-height sweep of the world tile,
      ground luma, 21.6 / 15.5 / 9.3 / 6.2 / 4.7 / 3.1 / 1.6 / 0 / -3.1
      degrees: before 0.329 0.292 0.277 0.259 0.256 0.254 0.243 0.237
      0.238, now 0.328 0.292 0.276 0.258 0.265 0.262 0.247 0.237 0.238. At
      and below the horizon it is identical, so the sun/moon switch is
      unchanged.
    Results, before -> now (world golden am / pm, L and R tiles; snow golden
    pm): grass tops lit/shade 1.22-1.27 -> 1.68-1.76 (sunset preset, 1.6
    degrees: 1.07-1.11 -> 1.42-1.47; noon unchanged 2.66/3.02); lit grass
    (61,96,32) -> (83,120,32), R/G 0.63-0.65 -> 0.69-0.70, B/G 0.33-0.35 ->
    0.26-0.28 (noon's lit grass 0.30); snow lit R/B 1.08-1.10 -> 1.40-1.41
    (target >= 1.25), snow shade B/R 1.08-1.10 -> 1.09-1.10 (target >
    1.05); no orange wash toward the sun: sunset R tile G/R 1.423 -> 1.419
    (criterion >= 1.40), golden pm R 1.497 -> 1.470; shade grass G 75-79 ->
    67-71, p5 28-30 -> 24-27 /255, below 12/255 at most 0.2%: darker, not
    black. Not met: the ground-mean targets. Ground R/G 0.64-0.67 -> 0.66-
    0.69 (target >= 0.70), B/G 0.38-0.41 -> 0.33-0.39 (target <= noon's
    0.33/0.35; met only on golden am L, 0.329). In this preview 38-65% of
    the golden-hour ground is shaded grass top, plus 16-23% shaded sides
    (a 6-degree sun makes 1-block steps cast ~10-block shadows), and shade
    is lit by the fill, which is cool on purpose. Both classes are warmer than at noon (lit B/G 0.26 vs 0.30,
    shade 0.38-0.40 vs 0.45-0.47); the mean is bluer because there is so
    much more shade. A warmer fill would fail the snow-shade target and
    the orange-wash check (G/R 1.419 against 1.40). The one tile with 45%
    sunlit grass meets B/G.
    *Note 2026-09-24 (third review), see #85:* the R/G miss was the
    preview's too-green grass. With vanilla colours golden ground R/G is
    0.86-0.89 and sunlit grass (75,82,32) is golden-olive; B/G is still met
    on one tile of four, for the reason above.
81. **Night: moonlit blue instead of olive.** At night and underground
    the low-light shift in the tonemap now moves non-warm dim pixels 60%
    (was 45%) toward lum x MOONLIT_TINT (0.76, 0.95, 1.48). Warm pixels
    (red above green, or yellow like torch-lit grass) keep the old shift
    exactly, so block light is untouched, and daytime (gate 0) is
    unchanged. MOONLIT_TINT has luminance 0.95, not 1: at 1.0 the bluer
    night measured 1% brighter in sRGB and the #67 "night mean +-5%" check
    failed (+5.7%). Results, before -> now: night ground B/G 0.61/0.64 ->
    0.73/0.77, dusk 0.61/0.65 -> 0.69/0.73; p5 11.2/10.4 -> 11.2/10.4 /255,
    below 12/255 6.6/8.6% -> 6.5/8.3%, mean 0.156/0.131 -> 0.157/0.131;
    noon rows identical, rain ground identical (its sky changed only by
    #78). Torch-lit planks and grass by block-light level at the hut door:
    identical to before at every level (grass at the far edge of the pool
    +1 blue level). The reviewer's first version skipped only red-above-
    green pixels and removed the shift from them entirely, which made dim
    torch-lit planks more saturated than before (B 28 -> 12). Caves: stone
    lit only by the cave floor ambient turns slightly bluer; torch-lit
    stone is warm and unchanged. Nether/End (dim_final passes gate 1):
    their red/yellow pixels are warm and unchanged; dark neutral pixels
    turn slightly bluer. Confirm both in game.
    *Note 2026-09-24 (third review), see #84/#85:* these night numbers are
    on the too-green preview grass. With vanilla colours the night was
    crushed (9.5-12.9% of the ground under 12/255); #84 fixes it. The
    moonlit tint itself holds: ground B/R 1.13-1.16.
82. **Preview tooling.** preview.c binds a depthtex0 stand-in for final.fsh
    (the scene shader's location 1: 1 = sky, 0.5 = geometry), so the #78
    mask is tested; the single-pass sky/cloud sheets pass surface 0. The
    godray mirror runs composite1's shaft step, tracing each neighbour as
    its own ray (with the lake's water plane in the lake scene,
    PREVIEW_LAKE). The golden am/pm presets (sun ~6 degrees) were already
    there.

### Third review fixes (real grass colours, godray cap, night crush, 2026-09-24)

A visual and a technical re-check of the second round found four problems:
the preview's grass was about twice as green as the game's, which hid a
crushed night and made the golden-hour brightness claims wrong; and the
godray shaft step still made shadowed surfaces glow. All fixed below.
Preview numbers: INSANE (`--game`), sRGB levels, "ground" = bottom 45% of
a tile, preview with the new vanilla grass colours (#85) unless noted.
"pre-v2" = commit 7dbdd21 rendered with the same preview (AO, golden
presets, vanilla grass). check.sh: 80 configs, 2497 compiles, 0 errors / 0
warnings; Apple GL 2497 and Iris patcher stage 193, 0 failed.

83. **Godrays: rays compared over the shorter march, glow capped at the
    ray's own light.** The stored deficit (1 - vis^2) x depth(d) grows
    with the ray's length d, so #77's max(neighbours) - centre gave a
    short ray to a near surface the *difference in ray length* as glow,
    whether or not its own air was lit (see #77's correction). Worked
    case: a fully shaded trunk 3 blocks away (deficit 0.035) beside a
    ray over 20 blocks of shaded floor (0.213) got 0.178; a real 50%-lit
    beam beside it only 0.053. On screen: curved hourglass bands on the
    shaded side of trunks near a low sun (the across-shaft taps turn
    around the sun). Now godrayShafts() takes the 4 neighbours' surface
    distances (composite1 reads depthtex0 at each tap) and scales a
    *longer* neighbour's deficit to the centre's optical depth (its
    shadowed fraction x the centre's depth); a shorter neighbour keeps
    its own deficit; and the result is clamped to the centre ray's own
    light (depth - deficit). Open air still gives 0; a fully shadowed ray
    can never glow; a real beam between shadowed rays of similar length
    is unchanged. Cost: 4 texelFetch of depthtex0 and 4 screenToView in
    composite1; no pass, buffer or loop. The preview mirror passes each
    tap's own hit distance.
    The two reviewers' fixes were each tested and each fixed one half:
    - Technical (keep the deficit, cap at the ray's own light): fully
      shadowed rays 0, but in the new canopy scene (#86) at golden hour
      the forest interior's rays are all part-lit (the low sun streams in
      under the roof), so the cap never bites and the trunk bands stayed
      (on-off mean 0.51 -> 0.45 levels).
    - Visual (store the distance-free shadowed fraction, multiply by the
      centre's depth): trunk bands gone, but a long part-lit ray next to
      any near shadowed silhouette gets its whole lit amount: in the
      reviewer's sparse forest, sky pixels got mean 39-108e-3 shafts,
      p95 290-370e-3 (#77 and this fix: 2-15e-3, p95 2-69e-3), a halo
      round every tree against the sky.
    The chosen version is exactly the smaller of the two, per neighbour.
    Numbers (analysis at 640x360, fixed jitter, INSANE 12 samples):
    - Technical reviewer's forest, looking toward the sun, rays fully in
      shadow (vis <= 1/12), mean / p95 x1e-3: golden pm 12.6 / 75 -> 0.0 /
      0.0, morning 18.2 / 101 -> 0.03 / 0.1, noon 6.8 / 43 -> 0 / 0. Mostly
      lit rays (vis >= 0.67): golden pm 16.6 / 63 -> 16.2 / 63, morning
      9.1 / 69 -> 9.1 / 69 (kept). Shaded surfaces with part-lit rays:
      golden pm 13.0 -> 4.4, morning 9.3 -> 3.6.
    - Canopy scene through the real final chain, toward the sun, godrays
      on - off (mean / p99 / max levels): noon 0.23 / 2.8 / 4.0 -> 0.01 /
      0.2 / 1.0; morning 0.79 / 10.4 / 30.7 -> 0.03 / 0.9 / 4.0 (the band
      case); golden am 0.42 / 5.9 / 15.3 -> 0.27 / 4.1 / 15.3; golden pm
      0.51 / 6.1 / 23.3 -> 0.32 / 4.1 / 23.3. The remaining peak is a soft
      beam under the roof's sunward edge, lit air beside the roof's
      shadow: a real shaft.
    - world / lake sheets: at most 2 levels from before on any pixel;
      hut: up to 8 levels at one hill crest near the sun, where the glow
      is kept (mean +0.09-0.10 -> +0.05-0.07).
    Unchanged limits: vis^2 over 12 samples makes a ray crossing one thin
    shaft almost dark, and the 4-tap step only draws the edges of beams
    wider than ~4% of the screen, so godrays stay subtle (the menu says
    so). The canopy scene is the place to judge any later strength or
    weight change.
84. **Night: no crushed shade with real grass colours.** With vanilla
    colours faces turned from the moon, the ground under trees and leaf
    undersides sat at 8-11/255: shade lit only by ambNight 0.040, then
    cut again by the 0.55 night toe after the x1.35 gain (a dirt side
    ~0.0026 linear). The reviewer's tested set is adopted: ambNight
    x0.040 -> x0.060 (sky.glsl), night toe a 0.55 -> 0.80 (tonemap.glsl,
    gate 1), FILMIC_NIGHT_GAIN 1.35 -> 1.25 (final.fsh; FULLBRIGHT 1.175
    -> 1.125). Plus dim_final x1.15 -> x1.10: the softer toe also reaches
    the Nether/End (gate 1), and x1.10 keeps their 0.01-0.1 range within
    -4%..+8% of the old identity curve (-6% at 0.005); x1.15 would give
    +0%..+13%. Reasoned only: the preview cannot render the Nether/End, so
    confirm them in game.
    World night row, L / R, HEAD -> now (pre-v2): under 12/255 9.5 / 12.9%
    -> 1.9 / 2.9% (0.0 / 1.2%); under 16/255 18.5 / 25.5% -> 11.6 / 16.1%
    (8.3 / 12.0%); p5 10.4 / 10.2 -> 13.4 / 12.6 (15.2 / 14.3); mean 29.5
    / 25.8 -> 32.7 / 29.1 (29.4 / 26.7); ground B/R 1.13 / 1.15 -> 1.14 /
    1.16. Dusk p5 18 -> 20. Noon, morning, rain, thunder: at most 1 level
    on any pixel; sunrise, sunset, golden hour at most 3. Night sky
    through the HDR chain: mean 35.3 -> 36.0, dusk 79.2 -> 76.7. Torch
    light: hut wall by block light 0.65-0.8 / 0.8+ (124,71,24) /
    (173,105,40) -> (119,69,24) / (165,101,38); cave stone (sky light 0,
    through the whole chain) light level 2 / 6 / 10 / 15: (16,14,14) /
    (36,30,26) / (94,68,43) / (193,159,118) -> (17,15,15) / (38,31,27) /
    (91,66,42) / (184,151,112) (pre-v2 15 / 35 / 79 / 157 in red):
    levels 2-6 a touch brighter, the hot core 5% dimmer. FULLBRIGHT caves
    within 5 levels.
    Trade-off: the night mean is now 9-11% above pre-v2 (the #67 "+-5%"
    check fails), because the moonlit tops are brighter than pre-v2 and
    the shade had to come up. Sweeping ambNight 0.055-0.080, toe 0.80-1.0,
    gain 1.0-1.25 (12 settings): p5 never gets past ~13.4 (moon-shaded
    dirt sides and trunk sides in corner AO), and a mean within +7%
    needs the gain at 1.15 or below: at 1.15 the tail is worse (under
    12/255 2.5 / 3.8%), at 1.0-1.05 the torch core is 8-10% dimmer than
    with this set. Keeping torch light was judged more important than 5%
    of night brightness.
85. **The preview's grass was twice as green as the game's.**
    tools/preview.py grass id 1 (top and side top) vec3(0.36, 0.60, 0.22)
    -> vec3(0.34, 0.44, 0.21), leaves id 5 vec3(0.23, 0.46, 0.14) ->
    vec3(0.27, 0.39, 0.11): the 26.1.2 jar's grass_block_top / oak_leaves
    mean times the plains grass #91BD59 / foliage #77AB2F tint (what
    gbuffers_solid writes, tex x glcolor), divided by the 0.97 mean of the
    preview's jitter. Checked: dirt, stone, planks and log tops were
    already within ~5% (log sides are ~10% dark; left, a small area).
    Green in linear light was 1.95x too high, so #67-#82 were measured on
    a greener, brighter world than Chris sees. Same code (HEAD f500207),
    old -> vanilla grass: noon ground mean 126.9 / 109.3 -> 96.5 / 83.5,
    saturation 0.63 / 0.59 -> 0.51 / 0.48.
    What changes in the story:
    - Golden hour: sunlit grass is golden-olive, (75,82,32), R/G 0.86-0.89
      (#80's unmet R/G >= 0.70 was the preview), percentile lit/shade 5.0-
      6.4 (pre-v2 1.7-2.0), snow lit R/B 1.39-1.40 with shade B/R 1.09-
      1.10, no orange wash (G/R toward the sun 1.11 sunset / 1.15 golden,
      pre-v2 0.98 / 1.07). Ground B/G is at or below noon's on 1 of 4
      tiles (shade share, as in #80). But the ground is 7-26% *darker*
      than pre-v2 (means golden am L/R, pm L/R 55.8 / 47.3 / 48.8 / 44.0,
      pre-v2 60.1 / 59.0 / 58.3 / 59.4), not "about as bright": sunlit
      grass is brighter than pre-v2 (G 82 vs 69-72), the shade is far
      deeper (p5 21-24 vs 41-46; pre-v2 shade was veiled). Knobs tested:
      FILMIC_GOLDEN_GAIN 1.12 -> 1.25 gives +5%, ambSunset x0.40 -> x0.46
      gives +3% (+6% at sunset); neither closes the gap, both flatten the
      light. Kept: the darker shade is the cinematic contrast the owner
      asked for. The spec line in CLAUDE.md now says so.
    - Rain: saturation 0.31 / 0.27 (pre-v2 0.24 / 0.19, so +0.07); the
      #67 ">= 0.40" was on the green grass. Rain mean 47 / 46 vs pre-v2
      69 / 70: darker, the old fog wash is gone; first knob if Chris
      finds rain too dark: weatherDirect 0.075 -> 0.10 (sky.glsl).
    - Night: the crush (#84).
    Restated acceptance list (world sheet, bottom 55% unless noted), with
    the albedo-dependent criteria made relative to pre-v2 on the same
    preview: noon / morning saturation >= pre-v2 + 0.06 (0.49 / 0.47 and
    0.44 / 0.47 vs 0.41 / 0.37 and 0.35 / 0.36); rain saturation >= pre-
    v2 + 0.05 (0.31 / 0.27 vs 0.24 / 0.19); rain sky saturation <= 0.25
    (0.18); noon p5 0.08-0.13 (0.107 / 0.097); night p5 >= 0.025 (0.053 /
    0.050); night ground under 12/255 <= 3% (new; 1.9 / 2.9%); noon
    p90/p10 >= 3.5 (3.8 / 4.3); sunset and sunrise p90/p10 >= 2.0 (2.05-
    2.41); noon shade-cool / lit-cool >= pre-v2 + 0.10 (1.52 / 1.43 vs
    1.32 / 1.28; was >= 1.5); noon lit-quarter B/R <= pre-v2 - 0.10 (0.57
    / 0.59 vs 0.70 / 0.73; was <= 0.55); noon mean >= -12% vs pre-v2;
    night mean +-5%; sunset and sunrise mean >= 0.15 (0.17-0.20); noon
    sky saturation >= 0.38 (0.40 / 0.42) and luma 0.60-0.68 (0.64 /
    0.63); no orange wash: sunset R G/R >= pre-v2 + 0.05 (1.109 vs 0.983;
    was >= 1.40) and golden pm R G/R >= pre-v2 (1.146 vs 1.067). Result:
    35 / 38. Misses: night mean +9.9% / +8.7% (#84 trade-off) and noon R
    mean -16.2% (L -11.3%): the veil and the raised black floor are gone
    (noon p5 0.21 -> 0.10) while sunlit grass is within 4% of pre-v2 (G
    126 vs 131); with the greener grass the lit tops weighed more and it
    read -7% / -12%. HEAD f500207 on the same list: also 35 / 38 (its
    misses: night under 12/255 9.5 / 12.9%, noon R mean).
86. **Preview tooling.** Vanilla grass and leaf colours (#85; the
    previews/baseline_*.png sheets are untouched and keep the old green).
    New scene `canopy` (DECISIONS #83's test): a 2-block leaf roof 7-8
    blocks up with 18% random 2x2 holes on trunks every 7 x 9 blocks,
    camera deep inside at (5.5, 65.6, -17.5) looking toward and away from
    the sun at noon, morning and golden am/pm. Shafts may only come from
    lit holes and the sunward roof edge; shaded trunks and floor must
    never glow. The godray mirror passes each neighbour's own hit
    distance to godrayShafts, as composite1 reads depthtex0 at each tap.
