# HomeHearth package: Fireplace, FloorLamp (2026-09-24)

This package adds two new **Home** builds made of primlib parts (no asset upload needed). Each build gets its own
behaviour module pair.

| Key | Size (w x h x d) | Parts | Cost | Behaviour |
|---|---|---|---|---|
| `Fireplace` | 7.6 x 7.0 x 3.58 (body 7 x 2.25, hearth in front) | 90 | 1500 | prompt "Light fire" / "Put out" toggles `Fun_Lit`: Fire + sparks, a flickering light, glowing embers, candles, chimney smoke, crackle. The mantel clock shows the game's time (`Lighting.ClockTime`) |
| `FloorLamp` | 3.06 x 7.66 x 3.06 | 56 | 300 | prompt "Lamp on" / "Lamp off" at the pull-chain toggles `Fun_On`. It turns on at dusk and off at dawn: a PointLight plus a downward SpotLight, and the whole shade, diffuser and bulb glow warm cream Neon |

The Fireplace uses 90 parts. That is the "big appliance" budget: it is a 7x7 fixture with a working firebox.
The FloorLamp stays within the furniture budget.

## Files
* `models/build_Fireplace.py`, `models/build_FloorLamp.py`: the models (primlib, Home, `Cost` and `DisplayName` attributes)
* `models/out/Fireplace.parts.json`, `models/out/FloorLamp.parts.json`: install these with `install/install_models.lua`, for example `{"Fireplace", "FloorLamp"}`
* renders: `models/renders/{Fireplace,FloorLamp}_{front,three,back}.png`
* lit review renders: `models/renders/_FireplaceLit_*.png` (embers Neon, candles lit) and `_FloorLampLit_*.png`
  (shade panels, diffuser and bulb Neon, as in game). They come from `models/build__FireplaceLit.py` and `build__FloorLampLit.py`, which are
  review-only. Never install them; their parts.json files were deleted.
* `src/behaviours/server/Fireplace.lua` goes to `ServerStorage.FunBehaviours.Fireplace`
* `src/behaviours/client/Fireplace.lua` goes to `ReplicatedStorage.FunBehavioursClient.Fireplace`
* `src/behaviours/server/FloorLamp.lua` goes to `ServerStorage.FunBehaviours.FloorLamp`
* `src/behaviours/client/FloorLamp.lua` goes to `ReplicatedStorage.FunBehavioursClient.FloorLamp`
* `tests/HomeHearth/` holds a headless test: `py tests/HomeHearth/gen.py` runs the four modules on the real
  parts.json models against a Roblox mock. The mock is copied from GardenLights' and extended. 1408 checks, 0 failed.

## Look
* **Fireplace**: a chunky red-brick fireplace (Brick material).
  * Base and hearth: a grey slate plinth course, and a stone hearth in front with a rounded bullnose edge. The
    hearth butts up to the plinth's front face (z -1.05) rather than overlapping it, so no two Slate tops share a strip.
  * Firebox: brick piers and lintel around the opening. A light limestone surround with a keystone frames a
    soot-black firebox with splayed sides, a soot floor and an ash bed.
  * Fire: two iron andirons with brass knobs hold three bark logs with pale cut ends, on a bed of coals.
  * Mantel: a wooden shelf with a rounded front edge and a dark cove, on two corbels.
  * Chimney breast: narrower than the body, joined to it by sloped brick shoulders, with a two-tone stone crown.
    From behind the build reads as a proper chimney.
  * On the mantel:
    * a dark-wood mantel clock with an arched top, brass bezel and finial, cream face and black hands
    * a picture frame leaning on the chimney breast, showing a small sunny landscape
    * a golden cucumber on a little stand
    * three candles in brass cups: tall red ones at each end and a short cream one
  * On the hearth: a companion tool stand (poker with a hook, shovel) and a stack of three spare logs with their
    cut ends facing the room.
* **FloorLamp**: a classic reading lamp.
  * Base: a black weighted base with a domed weight and a brass trim ring.
  * Pole: brass, with two knuckle collars. A round wooden side tray at hand height (y 3.05) holds a red book and
    a mug of coffee.
  * Shade: a tapered (empire) fabric shade of 16 cream panels, which read as pleats. It has a brass trim band
    round the open bottom and a brass rim with a diffuser disc and finial on top. A bulb on a socket is visible
    through the open bottom, and a brass pull-chain with a bead hangs out at the front. The top binding
    (`ShadeRim`) is a brass band y 7.12..7.34, diameter 2.17, deep enough to hide the panels' top corners (each
    panel is cut for the bottom circumference, so near the top neighbours overlap and would show a sawtooth).

## Parts and pivots the behaviours rely on (authored frame, scale 1)
**Fireplace**
* `Ember1..5` are the coal bed and `EmberSeam1..3` are glowing seams on the logs. The client finds them all with
  `Kit.Parts(model, "Ember")`. They are authored as dark charcoal Slate (`3a2f2a`) and turn Neon orange while lit.
* `CandleFlame1..3`: Ellipsoids (a SpecialMesh Sphere), Neon `ffb347`, authored at **Transparency 1**.
  BuildHealthService leaves them at 1 when the build is broken, because it only raises parts below 1.
* `ClockHour` and `ClockMinute` are authored at 10:10: hour at 305 deg and minute at 60 deg, clockwise from 12 as seen
  from the front. The hand's local +Y points along it. `Pivot_ClockCentre` = (0, 5.175, -1.47), and the axis is
  authored Z.
* `PicCanvas`, `PicHill`, `PicSun`: the picture. The canvas front face is the part's Front (-Z) face.
* `Pivot_Fire` (0, 0.95, -0.2) is the log pile. `Pivot_Light` (0, 1.7, -1.55) is just in front of the opening.
  `Pivot_Chimney` (0, 7.0, 0.25) is the top of the crown. `Pivot_Prompt` (0, 1.9, -1.95) is over the hearth.
**FloorLamp**
* `ShadeGlowTop` (the diffuser disc) and `Bulb` are authored SmoothPlastic and turn Neon while on.
* `ShadePanel01..16` are Fabric `f3e7cc` and turn **Neon (255,228,175)**, a soft warm cream, while on
  (`SHADE_NEON = true` in the client module; false would only tint them to `fff7e2`).
* `PullChain` and `PullBead` get tugged about `Pivot_ChainTop` (0.3, 5.7, -0.3).
* `Pivot_Light` (0, 6.1, 0) is the bulb centre. `Pivot_Spot` (0, 5.75, -0.36) is inside the shade just over its
  open bottom, clear of the pole, socket, bulb and chain. `Pivot_Switch` (0.3, 4.64, -0.3) is the bead.

## What the behaviours do
**Fireplace**
* **Server**
  * The prompt "Light fire" / "Put out" (Object "Fireplace", distance 10 x scale) sits on an invisible helper at
    `Pivot_Prompt`.
  * The toggle sets state `Fun_Lit` (true/false). Anyone may use it, and a 0.6 s debounce stops double presses.
  * It always starts **out** (placed, moved, mended, server start) and never lights itself, not even at night.
* **Client:** one `heat` value rises over 1.2 s when lit and falls over 3.5 s when put out, so the embers and the
  light die down slowly.
  * Two `Fire` instances (Size 3.2/2.2, Heat 7/5, orange) and a spark emitter (9/s, built-in texture) sit on
    invisible local parts at `Pivot_Fire`.
  * One PointLight (255,150,70) at `Pivot_Light` has Range 20 x scale and **shadows on**, so the glow spills out of
    the opening into the room. Its Brightness flickers every frame and its Range at 10 Hz, driven by `Kit.Now()`
    noise so every client shows the same flicker.
  * The Ember parts go Neon and flicker between deep red and orange.
  * The candles catch one after another, 0.35 s and then 0.3 s apart. Their flames flicker by SpecialMesh Scale, and
    they go out at once with the fire.
  * Chimney smoke (3/s) rises from `Pivot_Chimney` while heat is above 0.3.
  * `Sfx.FireLoop` crackles while lit, only when the camera is within 55 studs, with volume following the heat.
  * A live change (camera within 120 studs) plays `FireIgnite` with a spark burst on lighting, or `FireOut` with a
    smoke puff on putting out. Streaming in or seeing it from far away snaps to the state silently.
  * **Always:** the clock hands show the game's time, `Lighting.ClockTime` (hour = ClockTime % 12, minute =
    ClockTime x 60 % 60), which is the same clock the GrandfatherClock reads, so every clock on a plot and every
    player agree. They update at 10 Hz (a game minute passes every ~0.6 s by day) and skip the update when the time
    hasn't moved. When the cycle jumps (16:00 -> 0:00 at nightfall, 0:00 -> 11:00 at daybreak) the mantel clock
    snaps; it does not whirr round like the GrandfatherClock. If
    `FunAssets.Pictures` is not empty, the frame shows one of them as a Decal on `PicCanvas`, picked from the build's
    position so every client shows the same one, and the painted hill and sun are hidden locally.
  * Cleanup restores the Ember Color and Material, the flames' Transparency and mesh Scale, the clock hands'
    CFrame (relative to the hitbox, so it is correct after a move), and PicHill/PicSun, keeping the broken fade
    while the build is Broken.
  * Lights: 1 PointLight. Particles: sparks 9/s, smoke 3/s, and a burst-only puff.
**FloorLamp**
* **Server**
  * The prompt "Lamp on" / "Lamp off" (Object "Floor Lamp", distance 8 x scale) sits at the pull-chain bead and
    sets state `Fun_On`, with a 0.4 s debounce. Anyone may flip it. Each accepted press also fires
    `ctx:Fire("Tug")` to all clients.
  * **Day/night:** it starts on at night and off by day. Every dusk switches it on and every dawn switches it off,
    read from `workspace.IsNight` (or `CyclePhase == "Night"` if IsNight is unset). Only a real change counts, so a
    lamp someone switched off by hand stays off for the rest of that night.
* **Client:** one `glow` value rises over 0.25 s and falls over 0.4 s.
  * A PointLight (Range 14, Brightness 1.3, no shadows because it sits inside the shade) at the bulb.
  * A **SpotLight** (Face Bottom, Angle 110, Range 16, Brightness 2.6, shadows on) at `Pivot_Spot`, which throws a
    round pool of light on the floor through the open bottom.
  * The whole shade glows: the 16 fabric panels, the diffuser disc on top and the bulb go Neon, so the lamp reads as
    on from every side, even in the game's bright daytime lighting.
  * The state change only eases the glow. The chain tug (down 0.22 studs and back over 0.32 s) and `Sfx.Click` play
    from `B.OnEvent("Tug")`, which the server fires **only** from the prompt. The dusk/dawn switch sends no event,
    so the lamps on a plot don't all pull their chains and click at nightfall. A Tug seen from more than 120 studs
    away is ignored.
  * Lights: exactly 2. There are no particles.

## Sounds (FunAssets)
* Used, all already in `FunAssets.Sfx` (nothing to add):
  * `FireLoop` (9112780462): a real fireplace crackle loop.
  * `FireIgnite` (4510176414): match strike and flare, played on lighting.
  * `FireOut` (9113702967): blow-out puff, played on putting out.
  * `Click`: the lamp's pull-chain.
* `Whoosh` is only a fallback in the code, in case `FireIgnite` / `FireOut` are ever removed.
* No sound wishes left.

## BuildCatalog suggestions
* `DEFAULT_CATEGORY`: `Fireplace = "Home", FloorLamp = "Home"`. The parts.json category is already "Home".
* `DEFAULT_COST`: `Fireplace = 1500, FloorLamp = 300`. The Cost attribute carries these.
* `SCALE`: leave both at 1. They are authored for the 6-stud avatar: mantel top 4.375, total height 7; lamp 7.66.
  Both behaviours scale with `ctx.Scale`: pivots via `Kit.Pivot`, and Fire size, ranges and particles are multiplied by scale.

## How to test (Studio)
1. Install with `install_models.lua` `{"Fireplace", "FloorLamp"}`, then stage the four modules.
2. Place a Fireplace.
   * Walk to the hearth and the prompt "Light fire" appears. Press E.
   * Server: `model:GetAttribute("Fun_Lit") == true`, and the prompt now says "Put out".
   * Client:
     * `workspace.CurrentCamera.FireplaceFlame1.Fire.Enabled` is true.
     * `FireplaceFire.FireplaceLight.PointLight.Enabled` is true, with Brightness around 1.9 to 2.5.
     * `Ember1.Material` is Neon.
     * After about 1 s all three `CandleFlame*` parts are at Transparency 0.
     * `FireplaceChimney.ChimneySmoke.Enabled` is true.
   * Put it out: the embers still glow for about 3 s, then return to charcoal.
   * The clock hands should show `Lighting.ClockTime` (for example 15:30 shows 3:30) and agree with a
     GrandfatherClock on the same plot.
3. Place a FloorLamp.
   * By day it is off. Press "Lamp on" at the chain: `Fun_On == true`, the chain dips with a click, and the whole
     shade (all 16 `ShadePanel*`), the diffuser and the bulb go Neon warm cream.
   * `workspace.CurrentCamera.FloorLampSpot.SpotLight.Enabled` is true, and there is a pool of light on the floor.
   * Force a night with the admin panel, or `workspace:SetAttribute("IsNight", true)` on the server: every lamp
     turns on **without** a chain tug or click. Force day and every lamp turns off, also silently.
4. Move or sell either build while it is lit or on: everything resets. The fireplace starts out; the lamp takes the
   day/night default. Break it with `Broken = true`: every effect stops and the parts go back as authored.

## Known limits / open questions
* **Not verified in Studio.** Only the headless renders and the mock tests have run.
  * The effect hosts are local `ctx:Part`s under `workspace.CurrentCamera`, like HotTub's. If Fire, PointLight or
    SpotLight turn out not to render from a camera-parented part, parent them to Attachments on build parts
    (`FireboxFloor`, `Pole`) instead, which is Lantern's approach. It is a small change.
  * The Fire instances are sized to stay inside the firebox: opening top at y 3.25 x scale, Fire at y 0.95, Heat 7.
    Check that the flames don't lick out over the lintel. If they do, lower `FIRES[i].Heat` / `Size` in the client
    module.
* The game's night is "bright" (day lighting values), so both builds' lights are subtle outdoors. The Neon parts
  carry the "on" read: embers and candles on the fireplace; the whole shade, the diffuser and the bulb on the lamp.
* The lamp's dusk/dawn automation overrides a manual choice at each phase change. A lamp switched on by hand during
  the day goes off at the next dawn, which is the next phase change.
* The Fireplace is 90 parts: the big-appliance cap. The tiny parts are CanCollide false: candles, tools, clock,
  picture, embers, spare logs.
* The user said Blender MCP may be used for builds. This package used the headless `run_one.py` route instead,
  because the contract requires it for parallel agents.

## Fix pass (2026-09-24, after review)
* FloorLamp look: `SHADE_NEON` now defaults to true, with the panels in Neon (255,228,175). The lit preview
  (`build__FloorLampLit.py` via `PREVIEW_ON`) renders the panels that way too, and the lamp now reads as on from the side.
* Fireplace: a new `SizeFires(heat)` helper runs on every heat change and after a snap. Before this, a relight
  seen from over 120 studs away (or a build streaming in lit) after a live put-out left the flames at the Size 2 floor.
* FloorLamp: the chain tug and click play only on the server's `Tug` event, which only the prompt fires. The
  dusk/dawn switch now only eases the glow.
* Fireplace clock: shows `Lighting.ClockTime` instead of `os.date`.
* FloorLamp model: the `ShadeRim` band is now y 7.12..7.34 with diameter 2.17, which hides the top sawtooth.
* Fireplace model: the `Hearth` now covers z -2.05..-1.05, so its top no longer overlaps the plinth's. Part
  counts are unchanged: 90 and 56.
* Tests: 1408 checks, 0 failed. New checks cover the clock following ClockTime, including the midnight snap, the
  flame size after a far-away relight, no tug or click from the dusk switch, Tug only from the prompt, and the Neon panels.
