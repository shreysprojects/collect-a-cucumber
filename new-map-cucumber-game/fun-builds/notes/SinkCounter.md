# SinkCounter: a working kitchen counter (HomeKitchenB, 2026-09-24)

## Files
- Model: `models/build_SinkCounter.py` produces `models/out/SinkCounter.parts.json` (74 parts, category Home, `Cost` 900, `DisplayName` "Sink Counter").
  Size 8.24 x 5.05 x 3.12 (the worktop is at 3.6; the faucet reaches 5.0). Authored at true size, so use **SCALE 1**.
- Renders: `models/renders/SinkCounter_front.png`, `SinkCounter_three.png`, `SinkCounter_back.png`.
- Server half: `src/behaviours/server/SinkCounter.lua`, installs as `ServerStorage.FunBehaviours.SinkCounter`.
- Client half: `src/behaviours/client/SinkCounter.lua`, installs as `ReplicatedStorage.FunBehavioursClient.SinkCounter`.

## The model
Wooden cabinets on a black toe kick: four panelled doors with chrome pulls, two drawers, and a false front over the sink. The worktop is cream marble, with a pale-blue `CeramicTiles` backsplash and a marble cap.
A deep stainless basin sits in the middle. The worktop is four pieces around the hole, and the basin walls poke 0.03 above it to form the rim. There is a black drain.
Behind the basin is a chrome gooseneck faucet with red (hot, viewer's left) and blue (cold) handle caps, plus a green dish-soap bottle and a yellow/green sponge.
A blue fruit bowl (apples, orange, banana) sits on the left end. A red retro pop-up toaster with two bread slices sits on the right end.
**The toaster housing parts are named `Pop*` (PopBody, PopDome, PopSlot1/2, PopLever...) on purpose.** Nothing but the bread starts with `Toast`, so `Kit.Parts(model, "Toast")` returns exactly the four slice parts.

## What it does
Server:
- `TapPrompt` ("Tap on" / "Tap off", object "Kitchen sink", reach `max(8, 8*scale)`) sits at `Pivot_Tap`, just in front of the faucet. It toggles **`Fun_Tap`**, with a 0.4 s debounce.
  A running tap **turns itself off after 120 s** (`TAP_AUTO_OFF`).
- `ToastPrompt` ("Make toast", object "Toaster") sits at `Pivot_Toaster`, over the toaster. It sets **`Fun_ToastAt = server time + 4`**, which is the moment the toast pops.
  Until that cycle ends (4 + 5 + 0.6 s) the prompt reads **"Toasting..."** and any press is ignored; then it reads "Make toast" again. `Fun_ToastAt` is 0 when idle.
  The server never writes the prompt's `Enabled`: the framework client flips `Enabled` locally to hide every FunBuildPrompt in build mode, and a server write would override that (or be overridden by it).
- Anyone can use both prompts.

Client (local and cosmetic only):
- **Water stream**: a local translucent cylinder `SinkStream` (diameter 0.13 x scale, light blue, shimmering width and transparency) runs from `Pivot_Spout` down to the water surface over `Pivot_SinkFloor`.
  When the tap opens, the stream grows down from the nozzle at 9 studs/s. When it closes, the tail drops away.
- **Pool**: a local `SinkPool` block fills the `Pivot_PoolA`..`Pivot_PoolB` box. It rises to 0.2 stud over 6 s while the tap runs and drains over 3.5 s after.
- **Splash**: a spray of droplets (Rate 22) and flat ripple rings (Rate 4) where the stream lands, riding the pool surface. `FunAssets.Sfx.WaterLoop` loops while water is falling and the camera is within 55 studs.
- **Toaster**, timed entirely from `Fun_ToastAt` and `Kit.Now()`, so every client stays in sync and late joiners jump to the right pose:
  - On the press, `PopLever` slides down 0.3 and the `Toast*` slices sink 0.14 out of sight, over 0.25 s. `Sfx.Click` plays.
  - While toasting, `PopSlot1/2` glow Neon orange, and a wisp of smoke curls out for the last 2.5 s.
  - At `Fun_ToastAt` the slices **pop up 0.8 stud** with a 0.12 overshoot, golden brown, with `Sfx.ToasterPop` and then `Sfx.Ding` 0.15 s later. The sounds play only for clients that saw the pop live, never late. The lever springs back up.
  - 5 s later the slices slide back down over 0.6 s, then fade back to bread colour over 1.5 s.
- If a counter **streams in** while the tap runs, it starts with a full stream and pool; mid-toast, it jumps straight to the right toaster pose (no pop sound).
  A **placed or moved** counter always comes back idle: a move re-runs the server half from scratch, which clears every `Fun_` state and sets `Fun_Tap` false and `Fun_ToastAt` 0.
- Particles switch off when the camera is more than 140 studs away. Step sleeps beyond 150 studs.
- Cleanup puts `Toast*` and `PopLever` back at their **template** rest pose (relative to the Hitbox, so a run that ended mid-pop still restores correctly).
  It also restores the `Color` and `Material` of `Toast*` and `PopSlot*`. The stream, pool and emitters are local ctx parts.

## Parts and pivots it relies on
- `Toast1`, `Toast1Crust`, `Toast2`, `Toast2Crust` (prefix `Toast`), `PopLever`, `PopSlot1`, `PopSlot2`.
- `Pivot_Spout` (0, 4.3, -0.1) is the nozzle tip. `Pivot_SinkFloor` (0, 2.92, -0.1) is the basin floor under it.
  `Pivot_PoolA` (1.3, 2.92, -0.9) and `Pivot_PoolB` (-1.3, 2.92, 0.45) are the pool box. `Pivot_Tap` (0, 4.1, 0.55) and `Pivot_Toaster` (-2.75, 5.31, 0.05) are the prompt spots.
  The client and server both have fallbacks.
- Mesh export: the literals `"Toast"`, `"PopLever"` and `"PopSlot"` keep those parts separate. The pivot names are not prefixes of any part name (`SinkFloor`, not `Basin`), so the basin still merges.

## Sounds wished for
- `WaterLoop` is currently "Water Splash", which is probably a one-shot, so looped it would sound like repeated splashes. It needs a running-tap loop (seamless, 3-8 s).
- `ToasterPop` is "Button Pop", which is acceptable. A springy metallic toaster "ka-chunk" would be better.
- `Ding` ("Notification") and `Click` are fine.

## How to test
1. Place a Sink Counter. The model should show `Fun_Tap` false and `Fun_ToastAt` 0.
   You get two prompts: "Tap on" in front of the faucet and "Make toast" over the toaster. They share the E key, and the closer or faced one shows (OnePerButton).
2. Press "Tap on". `Fun_Tap` becomes true and the prompt reads "Tap off".
   `workspace.CurrentCamera.SinkStream.Transparency` should be around 0.3. `SinkStream.Size.X` is about 1.38 at first and shrinks as the pool rises.
   `SinkPool.Size.Y` should reach about 0.2 after 6 s. `SinkFX.Splash.Spray.Enabled` should be true, and `SinkFX.Splash.WaterLoop.IsPlaying` true near the counter.
3. Press "Tap off". The stream drops away within about 0.2 s and the pool drains over 3.5 s. Separately, check that it shuts itself off 120 s after being turned on.
4. Press "Make toast". `Fun_ToastAt` should be about `workspace:GetServerTimeNow() + 4` and the prompt should read "Toasting..." (still `Enabled`; pressing it does nothing). `PopLever` moves 0.3 down and the slots glow.
   After 4 s, `Toast1.Position.Y` is 0.8 higher than rest, the pop and ding play, and the bread is golden. After 5 more s it slides back.
   The prompt reads "Make toast" again at about 9.6 s.
5. Enter build mode mid-toast and stay in it past 9.6 s: the toaster prompt must stay hidden. Leave build mode: it comes back.
6. Move or sell the counter mid-pop. The slices and lever go back to rest, and nothing is left in `CurrentCamera`.
   After a move the counter comes back idle (tap off, toaster idle); that is expected. To test the streamed-in state, turn the tap on, walk away past the streaming radius and come back: the stream and pool are already full.

## Known limits
- The stream is one straight cylinder, with no curve or breakup.
- Two prompts 3 studs apart share the E key. OnePerButton shows one at a time, which is the game's normal behaviour.
  If you want both visible at once, give the toaster `Key = Enum.KeyCode.F` in the server file.
- For the integrator (framework, not this package): `ctx:Seat` in `FunBuildService.server.lua` (~line 213, `prompt.Enabled = seat.Occupant == nil`) writes a FunBuildPrompt's `Enabled` from the server, the same pattern removed here. A seat vacated while a player is in build mode shows its "Sit" prompt to that player until they toggle build mode.

## Headless test
`py tests/HomeKitchenB/gen.py` runs both behaviours (server and client) against the real parts.json on a mock Roblox (scale 1 / 1.25 / 1.4, yawed 37 degrees). It covers prompts at their pivots, debounce, auto-off, toast timing, the toaster prompt text (never Enabled) including a stale-reset race, glow and cool-down, emitters and lights, far-camera sleep, streaming in mid-state, and cleanup. Result: 251 checks, 0 failed.
