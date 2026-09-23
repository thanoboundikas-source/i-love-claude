# Solstice — Phase 2 judgment calls

Decisions I made overnight where the spec left room. Each says what I chose and why.
Nothing here is sacred — tell me what looks wrong in-game and I'll change it.

## Architecture

1. **Buffer budget (8 colortex, heavy reuse).** colortex0 = albedo→HDR scene
   (R11F_G11F_B10F), colortex1 = packed G-buffer (RGBA16: octahedral normal,
   lightmap, material), colortex2 = shadow term (RGBA8, render-scaled region),
   colortex3 = clouds → water reflections → godrays (RGBA16F, reused because
   lifetimes don't overlap), colortex4/5 = translucent albedo + data,
   colortex6 = TAA history (never cleared), colortex7 = bloom (RGBA16F, mipped).
   Reuse keeps total memory/bandwidth down per the Mac-first constraint.

2. **What RENDER_SCALE actually scales.** It scales the *expensive* passes —
   shadow filtering term, volumetric clouds, SSR, godrays — via the documented
   viewport trick (done in the vertex stage, per the docs' note that this
   equals `scale.<program>`). It does NOT scale base geometry or the final
   lighting combine: that would blur every texture on screen. Bloom is
   inherently half-res. REGULAR additionally halves reflections/godrays
   (EFFECTS_RES=50), per spec.

3. **Options are integers (RENDER_SCALE=75, not 0.75).** Iris profile lines and
   GLSL `#if` need ints; percent values display cleanly in the menu. This
   changed the Phase 1 RENDER_SCALE values.

4. **Deferred water, forward everything else translucent.** Water writes its
   surface data to buffers and is shaded in composite (needed for refraction +
   half-res SSR). Stained glass/ice/slime/particles stay forward so vanilla
   layering (glass behind glass) survives. Consequence: water seen *through*
   glass gets simplified shading. Chose vanilla-faithfulness for glass over
   perfect water-behind-glass.

## Lighting

5. **Coloured block light is an approximation.** True per-source coloured light
   needs voxelization (compute/SSBO — impossible on macOS GL 4.1, hard
   constraint). Instead: block light is globally warm (torch orange), and
   emissive blocks glow in *their own* colour (soul fire cool blue, lava
   orange) via a luminance-masked emissive term; bloom spreads that colour
   locally. This reads as coloured light in practice without voxels.

6. **sunPathRotation = -30°** (menu-adjustable). Angled shadows read better
   than straight-overhead noon shadows and match the Complementary feel.

7. **No auto-exposure.** Not in the spec; fixed calibrated exposure keeps the
   image predictable, FULLBRIGHT covers caves. Can add later if nights/caves
   feel off.

8. **Shadows:** hardware-filtered (free 2×2 PCF per tap) + rotated Vogel-disk
   PCF, normal-offset + slope bias against acne, sky-lightmap gating against
   cave light leaks, shadow-map distortion for detail near the player.
   Colored/translucent shadows come from shadowcolor0 (stained glass tints,
   water tints shadows).

9. **Hand is flagged in the G-buffer** and lit with lightmap + sun only (no
   shadow-map lookup, no fog) — the hand's fake depth makes reconstructed
   positions wrong, this is the standard fix.

## Sky & clouds

10. **Sun and moon are fully procedural** (crisp round sun; moon with all 8
    phases drawn analytically). The gradient sky replaces vanilla sky geometry,
    so vanilla sun/moon/star/sky rendering is disabled in shaders.properties.
    Stars are a procedural hash grid — crisp, subtle. Stars don't rotate with
    time (static field; cheap; revisit if you notice).

11. **Clouds: analytic blocky march.** Vanilla-style blob coverage map
    (value-noise, cell-quantized at 12 blocks, thickness quantized in steps)
    extruded to ~8 blocks at the dimension's real cloud height (Iris
    `cloudHeight` uniform). Marched with a 2D cell-DDA: exact ray segments
    through each cloud cell, so edges are crisp-but-soft (short corner
    segments = soft edge automatically) and cost is per-cell, not per-sample.
    Lit per entry-face (sunlit top/sun-facing side, ambient far side, horizon-
    tinted undersides) + 2-tap sun occlusion. Drifts slowly on worldDay+
    worldTime (no wraparound jump). Fades into distance fog.
    POTATO gets a flat single-sample vanilla-style layer instead of "off" —
    measured cost is a couple of noise fetches, and the sky looks dead without
    any clouds. Volumetric runs half-res in REGULAR, full-res in INSANE.

12. **Cloud shadows** = soft coverage lookup along the sun ray (no extra pass),
    REGULAR+INSANE only.

## Water & atmosphere

13. **SSR on water only.** Reflections on every smooth PBR surface would blow
    the frame budget; opaque blocks get sun specular instead. SSR misses fall
    back to the procedural sky+clouds in the reflected direction, so clouds
    reflect properly even off-screen.

14. **POTATO water keeps a sky-Fresnel tint** (it's a colour evaluation, not a
    reflection pass) — pure matte water looked broken in the mood the spec asks
    for. SSR/refraction stay off in POTATO per spec.

15. **Shoreline:** clean = depth-based absorption fade (transparent at 0 depth,
    biome-tinted with distance). No foam — not in spec.

16. **Water vertex bob is ±0.03 blocks.** Tiny seam where water meets terrain
    is possible at that amplitude; fragment-level waves carry most of the look.

17. **Underwater fog** tints by the water's own biome colour (from the surface
    data when available, fallback teal), plus lava/powder-snow fog safety when
    the camera is inside those.

## Post

18. **TAA reprojection is camera-only** (no per-object motion vectors — that
    needs another full-res buffer + every entity pass writing velocity).
    Moving entities can ghost slightly; neighborhood clamping keeps it minor.

19. **Bloom** = bright-pass at half res into a dedicated buffer, then one
    mip-chain gather (driver generateMipmap — no compute needed). Dedicated
    buffer because reusing a scaled-region buffer poisons the mip chain with
    stale data outside the region.

20. **Vanilla vignette disabled** — gritty dark corners fight the clean look.
    Tell me if you want it back.

## Dimensions

21. **Nether/End via dimension.properties** (`nether/` and `end/` folders) so
    the Overworld pipeline stays untouched in the base folder. Both get a
    simple forward pipeline: vanilla-style lightmap lighting with a warm
    (Nether) / cool (End) ambient, fog, FULLBRIGHT support, and the same
    tonemap so grading stays consistent. No shadows/TAA/clouds there yet —
    that's the later prompt. End's vanilla dark sky texture is disabled along
    with the Overworld's (the directives are global), so the End sky is
    near-black — acceptable until the End pass.

22. **gbuffers_basic geometry (leashes, block outline) is flagged fullbright-
    unlit** so the deferred pass leaves it alone regardless of where in the
    frame it renders.
