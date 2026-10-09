# Stove: a working kitchen range (HomeKitchenB, 2026-09-24)

## Files
- Model: `models/build_Stove.py` produces `models/out/Stove.parts.json` (84 parts, category Home, `Cost` 1000, `DisplayName` "Stove").
  Size 4.11 x 4.83 x 3.51 (the cooktop is at 3.6; the pan handle and the tea towel stick out at the front). Authored at true size, so use **SCALE 1** (no BuildCatalog entry needed).
- Renders: `models/renders/Stove_front.png`, `Stove_three.png`, `Stove_back.png`.
- Server half: `src/behaviours/server/Stove.lua`, installs as `ServerStorage.FunBehaviours.Stove`.
- Client half: `src/behaviours/client/Stove.lua`, installs as `ReplicatedStorage.FunBehavioursClient.Stove`.

## The model
A cream range on four black rubber feet. The top is black glass in a chrome frame, with four electric coil burners (two big, two small).
Each burner is a chrome drip ring, then `Burner<XX>` (the outer coil), then `CoilGap<XX>` (dark), then `Burner<XX>In` (the inner coil), then `CoilHub<XX>`.
At the back is a back guard (backsplash) with a black control panel. The panel has four white knobs on chrome skirts with red ticks, a green digital clock and a red `PowerLight`.
The oven door has a black `OvenWindow`, with a dark `OvenRack` and `OvenRoast` silhouette in front of it. There is also a chrome bar handle with a blue striped tea towel, a vent strip, a drawer and a back service panel.
A frying pan with a fried egg sits on the front-left burner, with its handle turned toward the cook. A red enamel kettle sits on the front-right burner, with its spout pointing to the viewer's right.

## What it does
Server:
- One prompt, `StovePrompt` ("Turn on" / "Turn off", object "Stove", reach `max(10, 10*scale)`), sits on the Hitbox at `Pivot_Controls` (the knob panel).
  It toggles the model attribute **`Fun_On`**, which starts false. There is a 0.4 s debounce, and anyone can use it.

Client (local and cosmetic only):
- **Coils (`Burner*`)** heat up over 1.8 s. They first darken toward a dull red in their own material. From 12% heat they turn **Neon** and ramp to red-orange `(255,86,30)` with a faint flicker.
  When switched off they cool down over 3.5 s.
- **Heat shimmer**: a faint warm smoke-texture haze (Rate 5) rises off each outer coil that has nothing standing on it.
  A coil counts as covered when it is within 0.5 authored studs of `Pivot_PanTop` or `Pivot_KettleBase`. In practice that means the two back burners.
- **Pan**: from `Pivot_PanTop`, oil pops (sparkles texture, bright specks that fly up and fall, Rate 9) and a wisp of smoke (Rate 3) come off a 0.72-stud box over the pan.
  `FunAssets.Sfx.Sizzle` loops at volume 0.3 while the stove is on (heat > 0.4) and the camera is within 45 studs.
- **Kettle**: after about 7 s on, steam puffs out of `Pivot_SpoutTip`. The spout direction is `Pivot_KettleBase` to `Pivot_SpoutTip`.
- **OvenWindow** warms over 3 s to a glowing Neon orange. The rack and roast stay dark in front of it, so they show as silhouettes.
- The **PowerLight** turns Neon red while the stove is on.
- **2 PointLights** (the contract allows 2 or fewer): a warm light over the cooktop (range 7 x scale, brightness 1.1 x heat) and one in front of the oven window (range 6 x scale).
- `Sfx.Click` plays on every switch, if the camera is within 60 studs.
- If a stove **streams in** while already on, it starts hot with no ramp.
  A **placed or moved** stove always comes back OFF: a move re-runs the server half from scratch, which clears every `Fun_` state and sets `Fun_On` false.
- Particles and lights switch off when the camera is more than 140 studs away. Step sleeps beyond 150 studs.
- Cleanup restores `Color` and `Material` of every `Burner*`, `OvenWindow` and `PowerLight` part from the template. It never touches Transparency, so the Broken fade is left alone.
  Every emitter and light lives on local helper parts (`StoveFX`, `StovePanFX`), which the ctx destroys.

## Parts and pivots it relies on
- `Burner*` (8 coil parts). An outer coil is any `Burner*` part whose name does not end in "In".
- `OvenWindow`, `PowerLight`.
- `Pivot_Controls` (0, 4.3, 0.855), `Pivot_PanTop` (0.95, 3.935, -0.62), `Pivot_OvenWindow` (0, 2.0, -1.61), `Pivot_SpoutTip` (-1.61, 4.185, -0.62), `Pivot_KettleBase` (-0.95, 3.685, -0.62).
  The client has fallbacks for Controls, PanTop and OvenWindow. If there is no kettle pivot, the kettle simply doesn't steam.
- Mesh export (`export_mesh.py`): the string literals `"Burner"`, `"OvenWindow"` and `"PowerLight"` keep those parts separate. The pivot names were chosen so they are **not** prefixes of part names (`PanTop`, not `Pan`), so the pan and kettle still merge.

## Sounds wished for
- `Sizzle` is currently "Electric Buzz" and needs a real frying-pan sizzle loop (seamless, 3-8 s).
- A kettle whistle (one-shot or loop) would be a nice extra, but nothing is wired for it yet.
- `Click` is fine.

## How to test
1. Place a Stove. `workspace.FunBuildRuntime.Stove_<owner>_<hex>` should exist, and the model's `Fun_On` should be false.
   The prompt "Turn on" appears on the knob panel when you walk up to the front.
2. Press it. `Fun_On` becomes true and the prompt reads "Turn off".
   Within about 2 s every `Burner*` part has `Material = Neon` and a Color near (255,86,30). Check with the client eval `model.BurnerBR.Material`.
   `OvenWindow` should be Neon orange after about 3 s, and `PowerLight` Neon red.
3. Look for particles: `workspace.CurrentCamera.StoveFX` has `Shimmer*` attachments (2), and `StovePanFX` has emitters `OilPops` and `PanSmoke`, both enabled.
   `StoveFX.KettleSteam.Steam.Enabled` should be true after about 7 s. `StovePanFX.Sizzle.IsPlaying` should be true near the stove.
4. Press again. Everything cools down over about 3.5 s, then the coils go back to SmoothPlastic `(79,84,94)`.
5. Move the stove while it is on. After a move it comes back OFF (`Fun_On` false, cold coils, prompt "Turn on"); that is expected.
   To test the streamed-in state, turn it on, walk away past the streaming radius and come back: it should already be hot, with no ramp.
   Selling it should leave nothing behind in `CurrentCamera`.

## Known limits
- The heat shimmer is a translucent warm haze. Roblox has no screen-space distortion, so it cannot be a true shimmer.
- The stove stays on until someone turns it off. It is cheap: all the work is on clients near it.

## Headless test
`py tests/HomeKitchenB/gen.py` runs both behaviours (server and client) against the real parts.json on a mock Roblox (scale 1 / 1.25 / 1.4, yawed 37 degrees). It covers prompts at their pivots, debounce, auto-off, toast timing, glow and cool-down, emitters and lights, far-camera sleep, streaming in mid-state, and cleanup. Result: 251 checks, 0 failed.
