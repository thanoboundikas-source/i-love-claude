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
  later sessions (DECISIONS #67-68).
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
  at noon, about 3400 K at the horizon) against a cooler, clearly darker sky
  fill (about 5:1 sunlit to shaded tops at noon). Golden hour stays
  directional down to the horizon, with no pop at the sun/moon switch. Soft
  filtered shadows, no acne, no light leaking, vanilla-strength corner AO in
  shade, warm ground bounce, coloured block light (hot core, amber falloff;
  warm torch/lava, cool soul fire).
- Sky: deep clean blue with a narrow horizon band, crisp sun and moon with a
  tight halo, stars at night. Colourful sunrise and sunset (orange toward the
  sun, lilac away), never orange soup. Rain and thunder states.
- Clouds: match Complementary Reimagined's default style as closely as possible,
  from scratch: vanilla cloud shapes extruded into thick solid blocky volumes
  with visible sides and undersides. Lit like solid objects: bright sunlit tops,
  softly shaded far sides, undersides tinted by sky and sunset colour. Warm lit
  side / cool shaded side at sunset, dim bluish moonlit at night. Slightly soft
  edges but clearly blocky — not fluffy photoreal cumulus, not a flat texture.
  Vanilla height, slow drift, soft ground shadows in REGULAR/INSANE, fade into
  distance fog with no hard edge. Must be cheap. Lit by the sun first, with
  near-white tops, cool grey-blue shade and a peach glow at sunset.
- Water: clear and blue, not teal. Reflections (including clouds),
  refraction, calm gentle waves, tinted underwater fog, clean shoreline.
- Atmosphere: distance fog as above. Godrays are shafts only where something
  casts a shadow (near 48 blocks), never an open-air glow. Rain fog and wet
  look.
- Post: a hue-preserving cinematic tonemap (toe + soft shoulder, pivot 0.18)
  with a fixed time-of-day exposure (night/underground x1.5, golden hour
  x1.25). Split toning (warm lit / cool shade, never the sky or torches), a
  subtle vignette, thresholded bloom (only real highlights glow), TAA with
  Catmull-Rom history, light sharpening. Optional darken-only local contrast
  (off by default). Every grading feature has its own toggle under Colour
  Grading.

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
  light (B, 8+8 bits), A = smoothness 7 | emissive 4 | flags 4, bit 15 clear.
  After the deferred pass the same buffer holds the *translucent layer*
  written by `gbuffers_water` (normal, biome tint, sky light, material) with
  bit 15 set. Layout: `lib/encoding.glsl`.
- `colortex2` R11F_G11F_B10F — HDR scene colour. deferred1 writes it,
  translucents blend into it, composite1/2 refine it, final tonemaps it
  (mipmapped in final for bloom).
- `colortex3` RGBA16F, size = RENDER_SCALE — clouds (premultiplied rgb, alpha).
- `colortex4` RGBA16F, size = RENDER_SCALE × (HALF_RES_FX ? 0.5 : 1) — water
  reflection (rgb) + godray amount (a).
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
  or GODRAYS) → `composite1` (water shading, underwater fog, godray add;
  water features or GODRAYS) → `composite2` (TAA) → `final` (sharpen, local
  contrast, bloom, vignette, time-of-day exposure, tonemap + grade).
- Switched off with `program.<name>.enabled` blocks in shaders.properties.
- Nether/End: `shaders/nether/`, `shaders/end/` (dimension.properties), a
  forward pipeline using the vanilla lightmap (`program/dim_*`).

Offline tools: `tools/preview.py sky|clouds|clouds_above|clouds_flat|world|hut|lake|pbr`
renders the pack's lib code on the Apple GPU to `previews/*.png` (a contact
sheet you can open with the Read tool) — use it to judge looks before asking
Chris to test. world/hut/lake show vanilla-style corner AO.
`previews/baseline_*.png` are the pre-2026-09-24 look; keep them, but they no
longer match. `tools/pair_screenshots.py` labels the TESTING.md comparison
screenshots.

Source layout: `shaders/lib/` shared code, `shaders/program/` program bodies
included by thin per-program stubs in `shaders/`, `shaders/nether/`,
`shaders/end/`.
