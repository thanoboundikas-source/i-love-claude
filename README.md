# Solstice

A Mac-first Minecraft shader pack for Iris. Written from scratch, targeting
OpenGL 4.1 (the macOS ceiling) as the *only* target — no compute shaders, no
SSBOs, no image load/store anywhere.

**Look:** bright, saturated, clean, vanilla-faithful (Complementary Reimagined
mood) with Bliss/Photon-level lighting quality.

## Status

- [x] **Phase 1** — minimal pipeline: vanilla-faithful rendering through Iris,
      three profiles (POTATO / REGULAR / INSANE), Render Scale + Fullbright
      options wired in the shader settings menu.
- [ ] **Phase 2** — full Overworld: soft filtered shadows, coloured block
      light, sky-tinted ambient, gradient sky, water, fog, godrays, bloom,
      TAA, tonemap, procedural PBR.
- [ ] Nether / End (currently fall back to the Overworld programs).

## Install

The repo *is* the pack: it lives directly in
`~/Library/Application Support/minecraft/shaderpacks/Solstice`.
Select **Solstice** in Iris (Options → Video Settings → Shader Packs).
`R` reloads the pack in-game, `K` toggles shaders.

## Layout

- `shaders/shaders.properties` — profiles, option screens, pipeline config
- `shaders/lang/en_us.lang` — option labels and tooltips
- `shaders/lib/` — shared includes (`settings.glsl` holds every option)
- `shaders/gbuffers_*` — geometry programs
- `shaders/composite*`, `shaders/final` — fullscreen passes
