# Fridge (HomeKitchenA package, 2026-09-24)

A new **Home** build: a tall stainless top-freezer fridge that works. Both doors open and close, the inside is
stocked, the compartment lights up, cold mist spills out and the compressor hums.

| Key | Size (w x h x d) | Parts | Cost | Category | Suggested SCALE |
|---|---|---|---|---|---|
| `Fridge` | 4.02 x 8.06 x 3.2 (handles included) | 89 (budget 90) | 1500 | Home | 1 |

## Files
* `models/build_Fridge.py` builds the model. `models/kitchenlib.py` holds `Swing`, the door-turn helper shared with the Microwave.
* `models/out/Fridge.parts.json` is the file `install/install_models.lua` reads.
* Renders are in `models/renders/Fridge_{front,three,back}.png`.
* `models/build__FridgeOpen.py` is for review only and is **not a build**. It makes renders with both doors open at 100 degrees,
  the same turn the behaviour applies: `models/renders/_FridgeOpen_{front,three,back}.png`. Its parts.json was deleted.
* `src/behaviours/server/Fridge.lua` goes to `ServerStorage.FunBehaviours.Fridge`.
* `src/behaviours/client/Fridge.lua` goes to `ReplicatedStorage.FunBehavioursClient.Fridge`.
* `models/out/Fridge.fbx` + `Fridge.mesh.json` are the merged-mesh export for the mesh route. They were re-exported in the fix
  pass, after the behaviours existed. See "Merged-mesh export" below.
* `tools/kitchen_harness/` (run with `run.ps1`) runs the real server and client halves offline on mocks, using the real
  parts.json. It covers the Fridge and the Microwave. See "How to test".

## Look
* **Outside:** a light-grey stainless Metal skin (`c9d0d8`). The freezer door is on top (y 5.46 to 7.96) and the fridge door
  below (y 0.56 to 5.40). Both are hinged on the viewer's RIGHT (-X), with a dark hinge cap on top.
* **Handles:** chrome bar handles on standoffs along the free (+X) edge. There is also a dark diamond-plate kick grille.
* **Fridge door front:** a note held by a red magnet, a yellow sticky note with a blue magnet, and a kid's drawing of a
  cucumber held by a yellow magnet.
* **Freezer door front:** a badge with a green cucumber logo and a cucumber-shaped magnet.
* **Back:** a dark back panel with a condenser coil grille.
* **Inside:** a white liner, glass shelves and two pale-green crisper drawers. The left drawer holds 3 cucumbers and the
  right one 2 tomatoes. The shelves hold a milk carton with a blue gable top and an egg carton with 3 eggs, a layered
  strawberry cake with a cherry, a pickle jar (glass, with a pickle inside), a cheese wedge with its triangle facing out and
  a hole, and an orange leftovers tub with a blue lid.
* **Door bins:** ketchup, mustard, green soda and orange juice with caps, plus two cans and a butter block.
* **Freezer:** a wire shelf, a strawberry ice-cream tub, an ice-cube tray, a red pizza box, a bag of peas and a frost layer.

## Parts and pivots the behaviour relies on (authored frame, scale 1; front = -Z)
* `Door*`: the fridge door group. It has 26 parts: panel, gasket, liner, bins and bottles, handle, notes and magnets. The
  behaviour rigs every part whose name starts with `Door`. **No other part may start with `Door`.**
* `FreezerDoor*`: the freezer door group (10 parts).
* `Pivot_DoorHinge` (-1.98, 2.98, -1.12) and `Pivot_FreezerHinge` (-1.98, 6.71, -1.12): points on each door's vertical
  hinge axis, at the back face of the door on the hinge edge.
* `State_DoorOpen` = `State_FreezerDoorOpen` = 100: the open angle in degrees about +Y. A positive angle swings the free
  edge toward the front.
* `LightStrip` (fridge ceiling) and `FreezerLight` (freezer back wall): SmoothPlastic strips that turn Neon while their
  compartment is open.
* `Pivot_FridgeLight` and `Pivot_FreezerLight`: where the PointLights go. `Pivot_FridgeMist` and `Pivot_FreezerMist`:
  the bottom-front centre of each opening. `OpeningFridge` (3.42, 4.52, 0) and `OpeningFreezer` (3.42, 2.08, 0) give the
  width and height of each opening, which sizes the mist.
* `Pivot_PromptDoor` (1.62, 4.2, -1.95) and `Pivot_PromptFreezer` (1.62, 6.4, -1.95): the prompt spots in front of each handle.
* `Pivot_Hum`: the back bottom (compressor).
* `SkinL`: the static +X side skin, which carries both prompts through attachments. The doors only move on clients, so
  prompts must not sit on door parts. If `SkinL` is missing, the server falls back to `WallL`, then `SkinTop`, then the Hitbox.
* **Merged-mesh export (`export_mesh.py`):** every name above appears as a string literal in the behaviour files, so it is
  kept. `Door` and `FreezerDoor` are prefixes, so each door part stays separate. The static parts can be merged freely.
  * The current export (fix pass, `parts_hash` matches `Fridge.parts.json`) turns 89 parts into 67 meshes with 41 kept
    names: all 26 `Door*` and 10 `FreezerDoor*` parts under their own names, plus `SkinL`, `SkinTop`, `WallL`, `LightStrip`
    and `FreezerLight`.
  * The OLD export (02:55, made before the behaviours existed) merged `SkinL` with `SkinR`, `SkinTop` and both door panels
    into `SkinL_m`, and merged both handles into `DoorHandle_m`. Installing it would have broken both prompts and both
    doors. It has been overwritten. If `Fridge.parts.json` ever changes, re-run
    `blender -b --factory-startup --python models/export_mesh.py -- Fridge Microwave`.
  * Possible saving (needs a change to the shared `export_mesh.py`, so not done here): merging each door group per look
    under names that keep the prefix (e.g. `Door_1`, `FreezerDoor_1`) would cut about 36 door meshes to about 12. The
    behaviour only needs the prefix.

## What the behaviour does
* **Server (anyone may use it):**
  * Two prompts on `SkinL`:
    * "Open" / "Close" with **E** / ButtonX, ObjectText "Fridge".
    * "Open" / "Close" with **R** / ButtonY, ObjectText "Freezer". It uses a second key, like the TV's channel prompt,
      because with OnePerButton the farther prompt would never show.
  * A 0.65 s cooldown per door.
  * A door left open closes itself after 40 s.
* **State:** one signed number per door, so the open flag and its time can never arrive in different frames:
  * `Fun_Door`: > 0 means opened at that `Kit.Now()`, < 0 means closed at `-value`, 0 means shut.
  * `Fun_Freezer`: the same for the freezer door.
* **Client, door swing:**
  * The door group swings about its hinge in 0.6 s. Opening eases out with a small overshoot. Closing eases in and out
    and ends on a thud.
  * The progress comes from server time, so all clients match. A client that streams in mid-swing picks it up silently.
  * While a door is more than 1 degree open, its parts stop colliding **locally**, so a swinging door never shoves the
    local character. They collide again once shut.
* **Client, while a compartment is open:**
  * Its strip turns Neon.
  * A PointLight lights it: warm Range 7 in the fridge, cool Range 5 in the freezer, 2 lights in total.
  * Cold mist spills out of the bottom of the opening, sinks and drifts along the floor. It uses the built-in
    `smoke_main.dds`, Rate 10, and puffs 8 particles on opening.
* **Client, hum:** a quiet refrigerator hum loops at the back (Volume 0.1, 0.16 while a door is open, RollOffMax 26). It only
  runs while the camera is within 34 studs.
* **Client, move / mend:** the server restarts the behaviour, which clears `Fun_Door` / `Fun_Freezer` and sets them to 0.
  The client treats 0 as a silent reset. An open door snaps shut with no thud, and the restarted client starts shut.
* **Client, other:** `ctx:Step` does work only while a door is moving. Cleanup restores CFrame, CanCollide (skipped while
  Broken, because BuildHealthService owns collisions then), Material and Color.

## Sounds
All three are the dedicated FunAssets keys (see `assets/ASSETS.md`). They play at **PlaybackSpeed 1**, and each clip is
timed to the 0.6 s swing (the `SOUNDS` table in the client):
* `Sfx.FridgeHum` ("Refrigerator", 72 s loop): Volume 0.1, or 0.16 while a door is open.
* `Sfx.FridgeOpen` ("Refrigerator Door Open 3", seal squeak at 0.65 s): it starts at TimePosition 0.5, so the squeak comes
  about 0.15 s into the swing as the door leaves the seal.
* `Sfx.FridgeClose` ("Refrigerator Doors 1", thud at 0.35 s): it starts 0.25 s into the closing swing, so its thud lands
  when the door meets the cabinet at 0.6 s.
* Fallbacks, used only if a key is ever removed: `HumLoop` (now the same fridge hum, speed 1), `DoorOpen` (Skip 0.45) and
  `DoorClose` (speed 0.9, clunk at 0.25 s).
* Check by ear in a playtest: the hum volume, and whether the squeak and thud offsets feel right. They come from
  ASSETS.md timings, not from listening.

## How to test
1. Install: `install_models.lua` with `{"Fridge"}` (or the mesh route), then put both `Fridge.lua` modules into
   FunBehaviours and FunBehavioursClient.
2. Place a Fridge. Walk up to it: an E "Open" prompt (Fridge) sits in front of the lower handle and an R "Open" prompt
   (Freezer) in front of the upper one.
   * **Press E.** Server: `Fun_Door` becomes a positive server time and the prompt reads "Close".
   * Client: the `DoorPanel` CFrame turns about 100 degrees about `Pivot_DoorHinge` over 0.6 s. `LightStrip.Material` is
     Neon. The runtime PointLight under Camera ("FridgeLight") is Enabled, and the "ColdMist" emitter is Enabled.
   * **Press E again.** `Fun_Door` becomes negative, the door swings shut with a thud, and the light and mist go off.
3. The same with R and `Fun_Freezer` / `FreezerDoor*`.
4. Leave a door open for 40 s: it closes itself.
5. Move the fridge while a door is open: the behaviour restarts and the server resets the state to 0, so the doors do NOT
   stay open. They snap shut silently, with no thud, and are shut at the new spot. Break it (`Broken = true`): the doors
   snap shut and the lights and mist stop.
6. Offline, without Studio: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\kitchen_harness\run.ps1` prints
   `ALL OK`. It runs 21 Fridge checks on a placement scaled x1.2 and turned 90 degrees:
   * prompts on SkinL, the hum id and speed
   * the open sound's clip start, the 100 degree swing, Neon, light, mist burst and local no-collide
   * the close thud timing, shut and solid again
   * the move reset: no sound and the doors shut; cleanup back to the home CFrames; the restarted client is silent and works.

## Known limits / open questions
* An open door reaches about 4 studs out past the hitbox, to the front-right. It is visual only and can clip a neighbouring build.
* Nothing has run in Studio yet. The checks so far are renders, luacheck OK, an undeclared-name scan and the offline
  kitchen harness (ALL OK).
* Fix pass, 2026-09-24: `client/Fridge.lua` began with a UTF-8 BOM. luacheck.ps1 missed it because .NET strips BOMs, but
  the Luau CLI rejects it ("got Unicode character U+feff"), and so might a raw Source paste. It is removed. Install these
  files as plain UTF-8.
* Merged-mesh install: the liner walls will merge into one colliding MeshPart whose hull fills the cabinet. That is harmless,
  because the doors cover it and nobody can walk in anyway. `Box` fidelity would do as well.
