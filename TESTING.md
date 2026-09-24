# Testing Solstice against Complementary Reimagined

About 30 minutes. You'll take 20 screenshots: 10 shots, each once with
Reimagined and once with Solstice, from exactly the same spot. I label and
compare them myself afterwards.

**MacBook keys:** the F-keys need **fn**: fn+F1 hides the HUD, fn+F2 takes
a screenshot, fn+F3 shows FPS. The letter keys below need no fn.
On your Lunar profile: **O** opens the shader pack menu, **K** turns shaders
on/off, **I** reloads shaders.

---

## 1. One-time setup

1. **Reimagined is already installed.** `ComplementaryReimagined_r5.8.1.zip` is
   in the same folder as Solstice:
   `~/.lunarclient/profiles/fullbright-4/shaderpacks/`. If it is ever missing,
   download it from <https://modrinth.com/shader/complementary-reimagined>. In
   the game press **O** → **Open Shader Pack Folder...**, drag the downloaded
   `.zip` into that folder (don't unzip it), then close and reopen the menu.
   Both packs then show in the same list, so you can switch without restarting.
2. **Turn off the fullbright mod.** Press **G** until the game looks normal
   (the `fullbrightnesstoggle` mod). It would spoil the brightness comparison.
3. **Check Solstice loads.** Press **O**. If a button in that menu says
   *Shaders: Disabled*, click it so it says *Enabled*. Select **Solstice**, click **Apply**, then
   **Done**. If chat shows *"The shaderpack failed to load!"*, stop here and
   tell me. I'll read the log myself; no need to copy anything.
4. **Use the profile you play.** Press **O** → **Shader Pack Settings...**.
   Leave Solstice on **INSANE** (the look was tuned there). Leave Reimagined
   on its own default settings.
5. **Make a test world.** Singleplayer → **Create New World** → Game Mode
   **Creative**, **Allow Commands: ON**. (For an existing world: Esc →
   **Open to LAN** → **Allow Commands: ON** → **Start LAN World**.)
6. **Freeze the world** so both screenshots of a pair match. Type these in
   chat (press **T**, type, Enter):
   ```
   /gamerule advance_time false
   /gamerule advance_weather false
   /gamerule spawn_mobs false
   /weather clear
   ```
   (In 26.1.2 these game rules are called `advance_time` and
   `advance_weather`. The old names `doDaylightCycle` / `doWeatherCycle`
   no longer work.)

---

## 2. How to take each pair

For **every** shot, in this exact order:

1. Set the time/weather with the command listed for the shot.
2. Stand where the shot says, look at the scene, then **don't touch the mouse
   or keys** until both screenshots are taken.
3. Press **fn+F1** to hide the HUD.
4. Press **O** → select **Complementary Reimagined** → **Apply** → **Done**.
   Wait 2–3 seconds for it to settle.
5. Press **fn+F2** (screenshot **A** = Reimagined).
6. Press **O** → select **Solstice** → **Apply** → **Done**. Wait 2–3 seconds.
7. Press **fn+F2** (screenshot **B** = Solstice).
8. Press **fn+F1** to get the HUD back, then go to the next shot.

**Always Reimagined first, then Solstice, and no other screenshots in
between.** That order is how I tell them apart; you don't need to rename
anything. If you mess up a pair, finish the session and tell me which shot
it was.

---

## 3. The shot list

| # | Shot | Commands | Where to stand / look |
|---|---|---|---|
| 1 | Sunrise | `/time set 23300` `/weather clear` | Open ground, facing the sunrise (east), sun just above the horizon, some terrain in view. |
| 2 | Noon | `/time set 6000` | Open grassland or a village, sun behind you or to the side, trees and shadows in view. |
| 3 | Sunset | `/time set 12500` | Face the sunset (west), sun low, terrain and sky both in frame. |
| 4 | Night | `/time set 18000` | Open ground looking slightly up so moon and stars show, some terrain at the bottom. |
| 5 | Rain | `/time set 6000` `/weather rain` | The same open area as noon, looking at ground, trees and distant hills. |
| 6 | Cave with torches | `/weather clear` `/time set 6000` | Inside a cave or dug-out room lit only by 3–4 torches, no sky visible. (Add a soul torch in view if you have one.) |
| 7 | Underwater | `/time set 6000` | Swim 3–4 blocks below the surface of a lake or ocean, looking sideways and a little up. |
| 8 | Lake at sunset | `/time set 12500` | Stand on a shore, looking across a lake toward the setting sun. |
| 9 | Clouds from below | `/time set 6000` | Open ground, look up at about 45° with lots of clouds in view. |
| 10 | Clouds from a mountain top | `/time set 6000` | Fly or `/tp @s ~ 210 ~` above the cloud layer (clouds are at about y 192), look down across the cloud tops toward the horizon. |

(Minecraft day times: 0 = morning, 6000 = noon, 12000 = evening, 18000 =
midnight, 23000 = dawn.)

When you're done, say **"screenshots done"**. I'll pair them with
`tools/pair_screenshots.py` into `previews/compare/` as
`01_sunrise_A_reimagined.png`, `01_sunrise_B_solstice.png`, and so on, then
compare each pair.

---

## 4. Also useful to try (optional)

- **Profiles**: **O** → **Shader Pack Settings...** → click **Profile** to cycle
  POTATO / REGULAR / INSANE, then **Apply**. Note the FPS for each (fn+F3,
  top-left).
- **Fullbright**: the **Fullbright** button on the main settings page. Caves
  should become visible without torches and still look colourful.
- **A broken feature**: every feature has its own on/off button in the
  sub-menus (*Sky & Clouds*, *Lighting & Shadows*, *Water*, *Atmosphere*,
  *Post Processing*, *Generated Materials*). If something looks wrong, turn
  that one off, click **Apply**, and tell me which it was.
- **Nether and End** should look like clean vanilla with the Solstice colour
  grade. No shadows or clouds there yet.
