# Solstice — project rules for Claude

Solstice is a from-scratch Iris shader pack. The owner (Chris) has **no coding
background** and tests in-game. You are the lead graphics programmer. Read this
whole file before touching anything.

## Where everything lives (verified 2026-09-23)

| What | Path |
|---|---|
| Repo = the pack itself | `~/.lunarclient/profiles/fullbright-4/shaderpacks/Solstice` |
| Old location (symlink to the repo) | `~/Library/Application Support/minecraft/shaderpacks/Solstice` |
| Game log (Lunar, active profile) | `~/.lunarclient/profiles/fullbright-4/logs/latest.log` (older runs: `logs/YYYY-MM-DD-N.log.gz`) |
| Screenshots (F2) | `~/.lunarclient/profiles/fullbright-4/screenshots/` |
| Iris config (selected pack) | `~/.lunarclient/profiles/fullbright-4/config/iris.properties` |
| Pack option file Iris writes | `~/.lunarclient/profiles/fullbright-4/shaderpacks/Solstice.txt` |
| Patched shader dump (only in Iris debug mode, Ctrl+D in shader menu) | `~/.lunarclient/profiles/fullbright-4/patched_shaders/` |
| Iris docs (clone of github.com/IrisShaders/docs) | `~/.solstice-dev/iris-docs/src/content/docs/current/` |
| Iris source, branch `26.1` | `~/.solstice-dev/iris-src/` |
| Vanilla 26.1.2 client jar (assets) | `~/.lunarclient/shared/versions/26.1.2/26.1.2.jar` |

Lunar uses **isolated profiles**: the game directory is the profile folder, not
`~/Library/Application Support/minecraft`. If Chris switches Lunar profile, find
the new one: the running java process' cwd (`lsof -a -p <pid> -d cwd`) or the
most frequent `profiles/<name>` in `~/.lunarclient/logs/launcher/main.log`.
Then move or symlink the repo into that profile's `shaderpacks/`.

Keys in this profile: **I = reload shaders**, K = toggle shaders, O = shader
pack menu, F1 = hide HUD, F2 = screenshot, F3 = debug/FPS. (Not R — this
profile rebinds Iris reload to I.) The `fullbrightnesstoggle` mod is installed
(its key is G) — it must be OFF when judging brightness.

## Tools (run these yourself, never ask Chris to describe errors)

- `./check.sh` — expands includes like Iris, injects Iris macros, and runs
  every program through `glslangValidator` in ~65 option configurations
  (defaults, each profile, all toggles off/on, each toggle flipped, each value
  option at its extremes). Then it converts each program to core profile (the
  way the Iris patcher does for the legacy built-ins we use) and compiles +
  links it with **Apple's own OpenGL 4.1 Metal driver** in an offscreen
  context (`tools/applegl.c`, built automatically) — the same compiler the
  game uses. Run it after **every** change and fix everything it reports.
  `--no-apple` skips the Apple stage, `--apple-warnings` shows driver warnings.
  **Stage 3** (`tools/iris_check.sh`) runs **Iris's real patcher** from the
  iris jar on every Iris draw type (ShaderKey) with its real vertex format and
  fallback rules, then links the patched code on Apple GL — the closest thing
  to loading the pack in-game. Harness: `~/.solstice-dev/iris-harness`
  (rebuild with `tools/iris-harness/setup.sh`; needs `brew install openjdk`).
  `--no-iris` skips it. Lunar's log does NOT contain Iris's error text; if the
  game still fails to load, reproduce it with stage 3 or ask Chris to click
  "Copy Info" in chat and paste it.
  It is a strong typo catcher, not proof: the real Iris patcher and runtime
  behaviour are only tested in-game.
- `./tools/gamelog.sh` — prints Iris/shader errors and link warnings from the
  newest game log (`latest.log`). Run it after Chris reloads shaders.
  `./tools/gamelog.sh --all` shows the whole shader-related log section.
- `./tools/newest-screenshot.sh` — prints the path of the newest F2 screenshot;
  open it with the Read tool when Chris says "check the screenshot".

Iris log strings to look for (from Iris source): `Program link log for <prog>`
(WARN, usually harmless unused-attribute notes), `Shader compilation failed
for <prog>`, `Failed to create shader rendering pipeline, disabling shaders!`,
`Failed to load the shaderpack`, `ShaderCompileException`. Lunar's log does
not show Iris INFO lines such as "Using shaderpack".

## Hard constraints (never violate)

- Iris shader pack format, Minecraft **26.1.2**, Lunar Client's bundled Iris
  (the profile ships `iris-fabric-1.11.4+mc26.1.2`; Chris cannot change it).
  Verify every directive, uniform and macro against the cloned Iris docs or
  Iris source. **Never work from memory.**
- MacBook Pro M5 Pro, 16 GB unified memory, macOS, Retina (~3000x2000).
  Game log reports `OpenGL Version: 4.1 Metal`. **OpenGL 4.1 max.**
  Every shader starts with `#version 330 compatibility` (docs recommend the
  compatibility profile). No compute shaders, SSBOs, image load/store,
  custom images, atomic counters, geometry shaders, or any GL 4.2+ feature.
- Mac-first, not a Windows pack with fallbacks. Apple GPUs are tile-based and
  bandwidth-limited through Apple's GL layer: fewest passes possible, few small
  packed buffers, no dynamic loop bounds (loop counts are compile-time
  constants), no dynamic array indexing, no giant branching uber-shaders.
  Prefer many small programs (one source per program family, specialised with
  `#define` before a shared include).
- Personal use. **Never copy or read code from Complementary or any other
  pack.** Write everything fresh. (Comparing screenshots against Reimagined is
  fine; reading its files is not.)
- No resource pack. Normals and specular are generated procedurally from the
  vanilla textures.
- Git: commit after every working step with a clear message.
- Iris patcher rule: never name identifiers starting with `iris_`, `irisMain`
  or `moj_import`.
- colortex0–3 cannot be *read* in gbuffers programs (they sample the atlas).
- Internal helper macros must carry a value (`#define GB_TERRAIN 1`). Iris
  turns any value-less `#define X` that is tested with `#ifdef` into a menu
  option (OptionAnnotatedSource). check.sh fails on this.
- Never write `smoothstep(a, b, x)` with a >= b (undefined in GLSL/Metal).
  Use `1.0 - smoothstep(b, a, x)`. check.sh fails on this.
- Comments in shaders.properties start with `# ` (hash + space): Iris runs a C
  preprocessor over it, so `#word` can be read as a directive.
- **Never add a `gbuffers_line` program.** If a pack provides it, Iris 26.1
  patches it through its core-profile path (`isLines` in
  IrisRenderingPipeline), which leaves `#version 330 compatibility` and
  `ftransform()` unconverted; Apple GL rejects it and the whole pack fails to
  load. Outlines fall back to `gbuffers_basic`, which works. (Found 2026-09-24,
  first in-game load.)
- Program stubs in `shaders/`, `shaders/nether/`, `shaders/end/` are generated
  by `tools/gen_stubs.py`; edit the table there, put code in `shaders/program/`.

## The look (target spec)

- **Direction (Chris, 2026-09-24, first in-game test):** "very hazy", "make it
  more cinematic", "the lighting doesn't look good". Target: **clear and
  cinematic**. This replaces the old "Not filmic" line. Do not undo it in
  later sessions (DECISIONS #67-100).
- Mood: Complementary Reimagined's colour. Bright, saturated, clean and
  vanilla-faithful in the brightness of sunlit surfaces, with cinematic
  contrast: deep, clean blacks that are never crushed, soft highlight
  roll-off, warm key / cool shade, a gentle vignette. Never milky, grey,
  gritty, muddy or desaturated.
- Clarity: no veil. In clear weather the first ~100 blocks are crisp (haze
  <= 3% at 64 blocks), and only far land gains blue depth, a little darker
  than the sky behind it. Haze is never brighter than the light could
  scatter. Rain and thunder stay clearly foggy.
- Lighting quality: Bliss/Photon level. A strong warm sun key (about 5600 K
  at noon, about 3100 K at the horizon) against a cooler, clearly darker sky
  fill (about 5:1 sunlit to shaded tops at noon in light; after the toe
  about 10:1 in linear screen values, e.g. lit grass (98,126,56) against
  shaded grass (28,39,24)). Golden hour stays
  directional down to the horizon and warm: the low sun's key is lifted on
  the block face (GOLDEN_LIFT; the generated bump stays linear on top, so
  sunlit ground never gets dark dashes) with sunlit grass golden and
  sunlit snow peach, while shade stays fill-lit and cool under a lilac-blue
  sunset sky fill (warm key / cool shade down to the horizon, #89). Sunlit
  ground at least as bright as the pre-v2 look and golden, shade deeper
  and clean (so the frame is ~10-25% darker than the veiled pre-v2 look,
  #85), no pop at the sun/moon switch. Forest interiors are all shade, so
  they take the whole of that contrast: at noon and in the morning a
  forest under a 2-block leaf roof is ~30-45% darker than pre-v2, and its
  floor about as bright as moonlit open ground (#99). Kept as the look;
  if Chris finds forests too dark, the first knob is ambDay x0.40 -> x0.46
  (sky.glsl: forest floor +7-8%, open ground +2-4%). With the sun 10-45 degrees
  (morning and afternoon, hours of every day) sunlit ground is close to
  vanilla's brightness (matching it from ~20 degrees) and rises smoothly
  to noon, never a dull dip (#88). Night shade is dark but never pure
  black (at most ~3% of moonlit ground under 12/255), and moonlit ground
  reads cool blue-green, not olive (block light keeps its colour; the
  tint is part of FILMIC_CURVE, #93). Soft filtered shadows, no acne,
  no self-shadowing of sunlit ground by the filter (receiver-plane taps,
  #96), no light leaking, vanilla-strength corner AO in shade, warm ground
  bounce, coloured block light (hot core, amber falloff, levels 2-6 still
  readable in caves; warm torch/lava, cool soul fire).
- Sky: deep clean blue with a narrow horizon band, crisp sun and moon with a
  tight halo, stars at night. Colourful sunrise and sunset (orange toward the
  sun, lilac away), never orange soup. Rain and thunder states.
- Clouds: match Complementary Reimagined's default style as closely as possible,
  from scratch: vanilla cloud shapes extruded into thick solid blocky volumes
  with visible sides and undersides. Lit like solid objects: bright sunlit tops,
  softly shaded far sides, undersides tinted by sky and sunset colour (with a
  high sun the undersides are darker than the sun-averted sides, so clouds
  seen toward the sun read as volumes, not flat plates, #92). Warm lit
  side / cool shaded side at sunset, dim bluish moonlit at night. Slightly soft
  edges but clearly blocky — not fluffy photoreal cumulus, not a flat texture.
  Vanilla height, slow drift, soft ground shadows in REGULAR/INSANE, fade into
  distance fog with no hard edge. Must be cheap. Lit by the sun first, with
  near-white tops, cool grey-blue shade and a peach glow at sunset.
- Water: clear and blue, not teal. Reflections (including clouds),
  refraction, calm gentle waves, tinted underwater fog, clean shoreline.
- Atmosphere: distance fog as above; rain fog converges on the sky colour
  (no bright band at the world edge). Godrays are shafts only where
  something casts a shadow (near 48 blocks): lit air next to shadowed air,
  found in screen space across the shafts, comparing rays over the
  shorter of their two marches. Clearly visible under canopies toward a
  low sun (forest roofs; the canopy test, #90). A lone tree or hill
  against a low sun gives at most glare along its sunlit silhouette
  (world/hut/lake toward-sun tiles: on-off mean <= 0.28 levels): its
  shadow is too small a part of a 48-block, 12-sample ray, and next to
  the sun the sky is brighter than any shaft. Never an open-air glow.
  What the code guarantees: no pixel glows more than the light its own
  ray receives, so a fully shadowed ray (a shaded trunk, a wall in shade)
  never glows. That is exact at full-resolution effects (INSANE:
  RENDER_SCALE 100, HALF_RES_FX off). With a scaled effects buffer
  (REGULAR, any lower render scale) composite1 rebuilds each pixel's ray
  from the low-res rays at its own depth, so shadowed air beside near
  silhouettes gets no rim either, but a shaft's own edge spills 1-2 px
  into the shadowed air beside it (#95). What it does not guarantee: the
  glow marks where the shadow changes most within ~4% of the screen
  across the shafts, so inside a partly shadowed band wider than that,
  the pixels next to full shadow can glow more than the fully lit air on
  the band's other side (known limit, #90). Rain fog and wet look.
- Post: a hue-preserving cinematic tonemap (toe + soft shoulder, pivot 0.18;
  a gentler toe and a moonlit low-light tint at night / underground, both
  part of FILMIC_CURVE) with a fixed time-of-day exposure (night/underground
  x1.25; golden hour x1.12, rising to x1.40 at the horizon as the sun's key
  fades, x1.40 throughout with GOLDEN_LIFT 0; mid-height sun up to x1.24
  around 20 degrees, x1.00 from ~53 so noon is unchanged). Split toning on
  the daytime surface only (warm lit / cool shade, never the sky, the sun,
  the moon or clouds seen against the sky, which are masked by depth over a
  3x3 box; that keeps the TAA-jitter flicker along silhouettes to at most
  1/3 of the tint on straight edges and about 5/9 at convex corners, ~1-2
  levels, #100; clouds over far terrain are toned; never night or
  torch-lit caves), a subtle vignette, thresholded bloom (only real highlights glow:
  nothing below HDR 1.5, so snow and sand never veil), TAA with Catmull-Rom
  history clamped against ringing, light sharpening. Optional darken-only
  local contrast (off by default). Every grading feature has its own toggle
  under Colour Grading.

## Profiles

- **POTATO**: sky, lighting colour, tonemap, cheap or no clouds. No shadows,
  reflections or post. Max frame rate.
- **REGULAR**: everything, moderate shadow resolution and samples,
  bloom/godrays/reflections at half res.
- **INSANE**: everything at max.
- **RENDER SCALE** (0.5–1.0) actually scales the expensive passes. Defaults:
  POTATO 0.5, REGULAR 0.75, INSANE 1.0.
- **FULLBRIGHT** toggle in every profile: lifts the ambient floor so caves are
  visible without torches, keeps the colour grading so it never looks flat grey.
- Nether and End: no crashes, sensible fallback lighting. Full versions are
  later prompts.

## Working rules

- Chris is not available while you build. Don't stop to ask. Make judgment
  calls, log them in `DECISIONS.md`, keep going.
- Build order, one commit each: sky, clouds, lighting+shadows, water,
  atmosphere, post, generated PBR, profile wiring.
- Don't add features Chris didn't ask for.
- **Every feature has its own toggle** in the options menu, and the pack must
  compile with any combination of toggles off (so a broken feature can be
  switched off without killing the pack). `check.sh` enforces this.
- After Chris reloads shaders, read the game log yourself (`tools/gamelog.sh`).
- When Chris says "check the screenshot", open the newest image yourself.
- Give Chris exact, verified steps (paths, keys, menu names). He is not a coder.

## Architecture (keep this section current)

See `DECISIONS.md` for the why. Summary:

Buffers (all sizes relative to the window):
- `colortex0` RGBA8 — albedo (sRGB) + vanilla AO in alpha. Written by opaque gbuffers.
- `colortex1` RGBA16 — opaque G-buffer: octahedral normal (R,G), block+sky
  light (B, 8+8 bits), A = FLAG_TERRAIN 1 (bit 14) | smoothness 6 |
  emissive 4 | flags 4, bit 15 clear. FLAG_TERRAIN marks gbuffers_terrain
  pixels: only their bumped normals may be snapped back to the block face
  (lighting.glsl surfaceFaceNormal); entities, block entities and the hand
  use their own normal (#97).
  After the deferred pass the same buffer holds the *translucent layer*
  written by `gbuffers_water` (normal, biome tint, sky light, material) with
  bit 15 set. Layout: `lib/encoding.glsl`.
- `colortex2` R11F_G11F_B10F — HDR scene colour. deferred1 writes it,
  translucents blend into it, composite1/2 refine it, final tonemaps it
  (mipmapped in final for bloom).
- `colortex3` RGBA16F, size = RENDER_SCALE — clouds (premultiplied rgb, alpha).
- `colortex4` RGBA16F, size = RENDER_SCALE × (HALF_RES_FX ? 0.5 : 1) — water
  reflection (rgb) + godray shadow deficit (a; composite1 turns it into
  shafts).
- `colortex5` RGBA16F, never cleared — TAA history.
- `colortex6` RGBA8 — emissive colour for the coloured block-light tint
  (mipmapped before deferred1).
- shadow: `shadowtex0/1` (hardware compare) + `shadowcolor0` (translucent tint;
  alpha 0 = water).

Pass order (Overworld) and when each runs:
- `shadow` (SHADOWS) → gbuffers opaque → `deferred` (3D clouds, scaled) →
  `deferred1` (lighting, sky, clouds composite, fog, POTATO underwater fog;
  always) → gbuffers translucent (water data or POTATO forward water, glass,
  particles, weather) → `composite` (SSR + godray march, scaled; WATER_REFLECTIONS
  or GODRAYS) → `composite1` (water shading, underwater fog, godray shafts
  from 4 neighbour taps of colortex4.a plus depthtex0 at each tap; with a
  scaled colortex4 the centre is rebuilt from the 4 effects texels at the
  pixel's own depth, godrayCentre, #95; water features or GODRAYS) → `composite2` (TAA) →
  `final` (sharpen, local contrast, bloom, vignette, time-of-day exposure,
  tonemap + grade; reads a 3x3 box of depthtex0 for the split-toning sky
  mask).
- Switched off with `program.<name>.enabled` blocks in shaders.properties.
- Nether/End: `shaders/nether/`, `shaders/end/` (dimension.properties), a
  forward pipeline using the vanilla lightmap (`program/dim_*`).

Offline tools: `tools/preview.py sky|clouds|clouds_above|clouds_flat|world|hut|lake|snow|canopy|pbr`
renders the pack's lib code on the Apple GPU to `previews/*.png` (a contact
sheet you can open with the Read tool) — use it to judge looks before asking
Chris to test; `--game` uses Chris's saved options. world/hut/lake show
vanilla-style corner AO; their last rows are real golden hour (sun ~6
degrees; "sunrise"/"sunset" are only 1.6). Grass and leaves use vanilla
plains colours (texture mean x biome tint, #85; before 2026-09-24 the
preview grass was twice as green, so older numbers in DECISIONS read
greener and brighter than the game). `snow` is the bloom test (snow-white
ground must not bloom); `canopy` is the godray test (camera under a holed
leaf roof: shafts only from lit holes and the roof's sunward edge, fully
shadowed trunks must never glow). Sky light under leaves is vanilla-like
(14/15 under one leaf block, 13/15 under two, 0.7 under a solid roof, #99;
before 2026-09-24 every roof gave 0.7, so older canopy numbers are
darker). The preview traces shadows through the voxels (no shadow map, so
it cannot show shadow-filter artefacts such as #96) and traces godrays per
pixel at full resolution (the INSANE path; REGULAR's scaled-buffer
upsampling, #95, is modelled only). `pbr`'s last three rows (grass with the
plains tint, sand, dirt) are golden hour with generated normals: sunlit
ground must show no dark dashes. The
HDR chain gives final.fsh a depthtex0 stand-in (sky mask) and mirrors
composite1's godray shaft step.
`previews/baseline_*.png` are the pre-2026-09-24 look with the old green
preview grass; keep them, but they no longer match. `tools/pair_screenshots.py` labels the TESTING.md comparison
screenshots.

Source layout: `shaders/lib/` shared code, `shaders/program/` program bodies
included by thin per-program stubs in `shaders/`, `shaders/nether/`,
`shaders/end/`.
