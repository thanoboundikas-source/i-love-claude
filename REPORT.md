# Solstice — Overworld build report

> This describes the first build (2026-09-23). On 2026-09-24 the look was
> replaced by look v2, "clear and cinematic": no haze, stronger lighting and
> colour grading. See CLAUDE.md, *The look*, and DECISIONS #67–#101.

Built 2026-09-23 in one session, without in-game testing (I cannot press keys in
your game). Everything is committed in git, one commit per step. Read
**"Test these first"** before anything else.

## What was built

The whole Overworld, in the requested order, one commit each:

| Step | What you should see |
|---|---|
| 1. Sky | Smooth blue gradient, crisp round sun with a soft glow, a moon with all 8 phases, stars that turn with the sky, sunrise/sunset orange only near the sun and soft purple away from it, grey overcast in rain, darker in thunder. |
| 2. Clouds | Vanilla's own cloud shapes, extruded into thick blocky clouds (8 blocks, adjustable), with bright tops, softly shaded far sides, sky/sunset-tinted undersides, soft edges, slow drift, fading into the distance. Soft cloud shadows drift over the ground. POTATO gets a flat vanilla-style layer instead. |
| 3. Lighting + shadows | Soft filtered sun/moon shadows, no acne, no light leaking into caves, sky-tinted blue-white shade, warm torch light, block light tinted by nearby glowing blocks (soul fire blue, lava orange), sunlight glowing through leaves, stained glass tinting sunlight. |
| 4. Water | Reflections of terrain, sky **and clouds**, refraction, gentle waves, clear shorelines turning biome-blue with depth, sun glint, tinted underwater fog, Snell's window looking up from below. |
| 5. Atmosphere | Distance fog in the colour of the sky behind it (distant hills melt into the horizon, warm toward a sunset), the world edge fades into the sky, thicker grey fog in rain, clean caves, subtle godrays, wet glossy darkening in rain. |
| 6. Post | TAA (smooth edges, no shimmer), bloom on bright things (sun, lava, glowstone), light sharpening, a saturation-preserving tonemap. |
| 7. Generated PBR | Pixel-accurate bevels from the vanilla textures (raised cobblestones, brick mortar, plank grooves), metal blocks shine, polished blocks have a soft gloss. No resource pack. |
| 8. Profiles | POTATO / REGULAR / INSANE, Render Scale, Fullbright in every profile, safe Nether and End. |

Every feature has its own on/off switch in *Shader Pack Settings*, and the pack
compiles with any combination switched off.

### How it is put together (short)

- One lighting pass for all solid blocks (a small packed G-buffer), forward
  shading for see-through things. That's cheaper on Apple GPUs than lighting
  every overlapping leaf.
- Only the expensive screen work is scaled: clouds at Render Scale, reflections
  and godrays at Render Scale × ½ (REGULAR) or × 1 (INSANE), in genuinely
  smaller buffers.
- POTATO runs only four stages: world → lighting/sky → see-through things → tonemap.
- Full design log with the reasoning: [DECISIONS.md](DECISIONS.md) (65 entries).

### Checks that were run (all pass)

- `./check.sh`: 61 programs × 65 option combinations (each profile, every toggle
  off, every toggle on, each toggle flipped alone, each slider at both ends).
  All compile with glslang **and** with Apple's own OpenGL 4.1 Metal driver
  (the same one your game reports), after converting them the way Iris does.
- Offline previews rendered with the pack's real code on your GPU (sky at 8
  times of day, clouds from below and above, a small voxel test world, a lake,
  real vanilla textures for the generated normals). Several problems were found
  and fixed this way, such as muddy dusk colours, grid lines inside clouds and
  noisy generated normals.

## Key decisions and why

1. **Repo moved into the Lunar profile you play on.** Lunar gives each profile
   its own game folder (`~/.lunarclient/profiles/fullbright-4`). Iris only saw
   Complementary there, not Solstice. The old path is now a shortcut (symlink).
2. **Deferred lighting for solid blocks, forward for translucents.** One lighting
   pass instead of lighting every overlapping fragment. That suits the Mac's
   tile-based GPU, and it keeps glass layering vanilla-correct.
3. **Vanilla's real `clouds.png` drives the clouds**, traced cell by cell.
   Exactly vanilla shapes, perfectly blocky, and cheap (about 25 texture reads
   per pixel at reduced resolution).
4. **Reflections reuse the on-screen sky**, so the 3D clouds appear in water for
   free wherever that part of the sky is visible.
5. **Coloured block light is screen-based.** True per-source coloured light
   needs voxels, which need GL 4.3 (compute or image writes), and that's
   impossible on macOS. Nearby glowing blocks on screen tint the block light
   instead. The default warm torch colour covers the rest.
6. **A hand-tuned sky palette, not physical scattering.** Physically based skies
   drift toward the desaturated look the spec rules out. One palette drives the
   sky, fog, light and clouds, so they always agree.
7. **Godrays trace the shadow map**, not a screen blur, so they show through
   trees even when the sun is off-screen.
8. **Generated normals are pixel-edge bevels.** Per-pixel tilts looked like
   noise; bevels read as vanilla pixel art with depth.
9. **The time/weather game rules are new in 26.1.2**: `advance_time` and
   `advance_weather` (read from the game code), not `doDaylightCycle`.
   TESTING.md uses the new names.

## Test these first (least confident → most confident)

1. **Does it load at all?** Select Solstice (**O** → Solstice → **Apply** →
   **Done**; if a button there says *Shaders: Disabled*, click it first) and
   watch the chat. The Iris patcher and runtime directives can't be run
   offline: buffer sizes, the cloud texture binding, per-buffer blending. If
   chat says *"The shaderpack failed to load!"*, just tell me; I'll read the
   log.
2. **Clouds.** They depend on Iris binding `clouds.png` to the pack. If there
   are no clouds, or the whole sky is one cloud, that binding failed. Also
   check that they drift slowly and look right from below and from above.
3. **Things drawn in an unusual order in 26.1.** Check these are present and
   look sensible:
   - your hand and held items
   - particles (smoke, rain splashes)
   - the enchantment glint on items and armour
   - the block selection outline
   - spider eyes
   - beacon beams
   - lightning
   - name tags and sign text
4. **Generated normals on every face.** Look closely at cobblestone on walls
   and floors. The bumps should look raised on all sides. Tell me if some
   faces look like dents, or if you see stripes or seams at block edges.
5. **Brightness versus Reimagined** (the comparison session). Sun/shade
   balance, cave darkness, night brightness and tonemap were tuned on test
   scenes, not your worlds. These are one-line changes.
6. **Shadows**: acne (striped dark bands) on flat ground at sunrise/sunset,
   shadows detached from their blocks, noisy leaves, and light leaking into
   caves.
7. **TAA**: ghost trails behind moving mobs, and shimmer or smearing on the
   held item.
8. **Water**: odd reflection edges at the top of the screen, refraction halos,
   the view from under water, and water seen through glass (known limitation:
   it looks untinted).
9. **Nether and End**: they should look like clean vanilla with the Solstice
   colour grade. No shadows or clouds there yet.
10. **Coloured block light**: soul-fire blue near soul torches. The tint can
    shift a little as a glowing block leaves the screen (the known trade-off).

## FPS instructions

On a MacBook the F-keys need **fn**: press **fn+F3** for the debug screen. FPS
is the first number on the top-left line (e.g. `98 fps`).

1. Stand still in a normal spot (forest or village, daytime, clear weather).
2. With shaders off (**K** toggles), note the FPS.
3. Press **K** again, press **O** (shader pack menu) → select **Solstice** →
   **Shader Pack Settings...** → click the **Profile** button to cycle
   POTATO → REGULAR → INSANE. After each change press **Apply**, go back to the
   game and wait about 5 seconds, then note the FPS.
4. Switch to Complementary Reimagined (same menu) and note its FPS in the same
   spot.
5. Send me the numbers. For more speed on REGULAR, lower **Render Scale**
   first, then **Shadow Resolution**, then **Shadow Smoothness**.

Your Lunar settings cap FPS at 260 with VSync off. That's fine for comparing.

## Where things are

- Pack/repo: `~/.lunarclient/profiles/fullbright-4/shaderpacks/Solstice`
- Rules for future sessions: [CLAUDE.md](CLAUDE.md) · decisions: [DECISIONS.md](DECISIONS.md) ·
  test plan: [TESTING.md](TESTING.md)
- Tools: `./check.sh`, `tools/gamelog.sh`, `tools/newest-screenshot.sh`,
  `tools/preview.py`, `tools/pair_screenshots.py`
