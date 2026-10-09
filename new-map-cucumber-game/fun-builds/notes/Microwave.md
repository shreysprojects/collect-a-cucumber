# Microwave (HomeKitchenA package, 2026-09-24)

A new **Home** build: a microwave on a small wheeled kitchen cart that works. Heat mode lights the cavity, spins the
turntable, counts down on the display, then dings and puffs steam. The door opens and closes.

| Key | Size (w x h x d) | Parts | Cost | Category | Suggested SCALE |
|---|---|---|---|---|---|
| `Microwave` | 3.35 x 4.13 x 2.46 | 73 | 600 | Home | 1 |

## Files
* `models/build_Microwave.py` builds the model. It uses `models/kitchenlib.py` (`Swing`) for the door and turntable, so
  the review renders match the behaviour's turn.
* `models/out/Microwave.parts.json`
* Renders: `models/renders/Microwave_{front,three,back}.png`.
* `models/build__MicrowaveOpen.py` is for review only and is **not a build**. It renders the door open at -100 degrees
  with the turntable a quarter turn on: `models/renders/_MicrowaveOpen_{front,three,back}.png`. Its parts.json was deleted.
* `src/behaviours/server/Microwave.lua` goes to `ServerStorage.FunBehaviours.Microwave`.
* `src/behaviours/client/Microwave.lua` goes to `ReplicatedStorage.FunBehavioursClient.Microwave`.
* `models/out/Microwave.fbx` + `Microwave.mesh.json` are the merged-mesh export (fix pass). 73 parts become 37 meshes with 20
  kept names: every `Door*` and `Turntable*` part, plus `Display`, `DoorWindow`, `BtnStart`, `BtnOpen`, `CavityLight`,
  `KeypadPanel`, `CaseR` and `CaseTop`. `parts_hash` matches `Microwave.parts.json`.
* `tools/kitchen_harness/run.ps1` is the offline harness shared with the Fridge. See "How to test".

## Look
* **Microwave:** an off-white body (2.6 x 1.45 x 1.8) on rubber feet.
  * The black door has a dark see-through glass window and a chrome bar handle. It is hinged on the viewer's LEFT (+X).
  * The dark keypad column on the right has a green LCD, a 3x3 grid of grey keys, red Stop and green Start buttons, and
    a door-release bar. There are side vents.
  * Inside: a glass turntable carrying a red mug of cocoa with a marshmallow, set off-centre so the spin reads.
* **Cart:** blue legs, wood top and lower shelves with blue front edges, and a back rail with ball finials. It has four
  caster wheels and a chrome push handle on the left with a red tea towel folded over it. On the lower shelf are a
  red-and-white striped popcorn box and a stack of plates.

## Parts and pivots the behaviour relies on (authored frame, scale 1; front = -Z)
* `Door*`: the door group (frame x4, window, handle and standoffs). **No other part may start with `Door`.**
  * `Pivot_DoorHinge` (1.3, 3.405, -0.9) is the vertical hinge axis.
  * `State_DoorOpen` = -100. A negative angle about +Y swings the free (-X) edge to the front. It clears the cart, which
    the render confirms.
* `Turntable*`: plate, mug, handle, cocoa and marshmallow. They spin about the vertical axis through
  `Pivot_Turntable` (0.44, 2.84, -0.04).
* `CavityLight`: the lamp on the cavity side wall, turned Neon by the behaviour. `Pivot_CavityLight` is the cavity
  centre, where the PointLight and the hum sit.
* `Display`: the LCD. The client adds a SurfaceGui on whichever face looks toward the build's front, so it survives a
  merged-mesh install that turns the part's axes.
* `DoorWindow`: tinted amber while heating. `BtnStart` and `BtnOpen` dip in when used.
* `KeypadPanel` carries both prompts at `Pivot_Keypad` (-0.85, 3.4, -1.0). If it is missing, the server falls back to
  `CaseR`, then `CaseTop`, then the Hitbox.
* `Pivot_Steam` (0.48, 4.1, -1.1) is where the steam puffs, just in front of the door top.
* **Mesh export:** every name above is a string literal in the behaviour files, so it is kept by `export_mesh.py`.

## What the behaviour does
* **Server (anyone may use it):**
  * Two prompts at the keypad, with the second dropped 72 px under the first (UIOffset, like the TV):
    * "Heat" with **E** / ButtonX.
    * "Open" / "Close" with **R** / ButtonY.
  * **Heat:** if the door is open, it closes first and heating starts 0.55 s later. Heating runs for 5 s and the prompt
    reads "Heating..." meanwhile.
  * **Opening mid-heat stops the microwave, like a real one:** no ding.
  * Cooldowns: Heat 0.5 s, door 0.55 s.
* **State:**
  * `Fun_Door`: signed server time, the same scheme as the Fridge.
  * `Fun_Heat`: the server time the current heat starts (possibly slightly in the future), 0 when idle.
  * `Fun_Done`: the time the last heat finished.
* **Client, door:** the door swings in 0.45 s (ease-out-back open, ease-in-out close with a click). It stops colliding
  locally while open. The cavity lamp glows softly while the door is open.
* **Client, while heating:**
  * The lamp turns Neon warm and the PointLight turns warm (Range 4.5, the only light).
  * The window turns amber.
  * The turntable makes **exactly one turn** in the 5 s, so it ends where it began. A cancelled heat leaves it where it stopped.
  * The hum loops, the LCD counts down 0:05 to 0:01, and the Start button dips with a beep.
* **Client, done:**
  * A Ding plays.
  * A 14-particle steam burst puffs over the door, then trickles for 1.2 s.
  * The LCD blinks END for 4 s.
  * Otherwise the LCD shows the in-game clock (`Lighting.ClockTime`, 12-hour format).
* **Client, other:**
  * A client that streams in mid-heat picks up the spin, light, countdown and hum silently, and still dings when the heat ends.
  * **Fix pass:** the first heat after a client starts the behaviour (after a stream-in, move or mend) used to end with no
    ding and no steam, and the Start button did not press or beep. The first `Fun_Heat` / `Fun_Done` value of 0 matched the
    initial 0 and returned before priming. They now start at -1.
  * A move or mend resets the state to 0. The client treats that as silent: an open door snaps shut with no clunk and no
    door-button press, and a heat in progress stops without a ding.
  * The single `ctx:Step` sleeps beyond 140 studs.
  * Cleanup restores CFrame, CanCollide (skipped while Broken), Material and Color.

## Sounds
All from FunAssets (see `assets/ASSETS.md`). Timing and pitch live in the `SOUNDS` table in the client:
* `Sfx.MicrowaveHum` ("Microwave hum / in operation", 10.6 s loop): **PlaybackSpeed 1**, Volume 0.22, looped while heating.
* `Sfx.MicrowaveBeep` (0.12 s keypad beep): **PlaybackSpeed 1**, played with the Start button press.
* `Sfx.Ding` ("Desk Bell ... Single Ringing Ding", strike at 0.2 s): it starts at TimePosition 0.15, so the ding comes
  with the steam puff.
* `Sfx.DoorOpen` ("Refrigerator Door Open 2", squeak at 0.6-0.9 s): speed 1.1 from TimePosition 0.5, so the squeak comes
  just after the door is released.
* `Sfx.DoorClose` ("Washing Machine Door 1", clunk at 0.25 s): speed 1.15, for a lighter door. It starts about 0.23 s into
  the 0.45 s closing swing, so the clunk lands when the door meets the case.
* Fallbacks, used only if a key is ever removed: `HumLoop` (speed 1.25) and `Click` (speed 1.4).
* Check by ear in a playtest: the volumes and the clip offsets. They come from ASSETS.md timings, not from listening.

## How to test
1. Install: `install_models.lua` with `{"Microwave"}`, plus both `Microwave.lua` modules.
2. Place it and walk up: "Heat" (E) and "Open" (R) show stacked at the keypad.
   * **Press E.** `Fun_Heat` is set to a server time and the prompt reads "Heating...".
   * Client: `CavityLight.Material` is Neon and the `DoorWindow` colour is amber. `TurntableMug` circles the plate once in
     5 s. The LCD counts down.
   * After 5 s: `Fun_Heat` = 0 and `Fun_Done` is set. A ding and steam play, and the LCD blinks END.
3. **Press R.** `Fun_Door` goes positive, the door swings open to the left, and the cavity glows softly. **Press E while
   it is open:** it swings shut, then heats.
4. Press R mid-heat: the heat stops (`Fun_Heat` = 0, no ding) and the door opens.
5. Move it mid-heat with the door open: it goes silent and the door snaps shut. The first Heat afterwards beeps, spins and
   dings.
6. Offline, without Studio: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\kitchen_harness\run.ps1` prints
   `ALL OK`. It runs 23 Microwave checks on the real parts.json, turned -90 degrees:
   * the first heat: beep, Start press, hum, LCD countdown, a Ding at 5.0 s from 0.15 s, 14 steam particles, the mug back
     home after exactly one turn
   * the door: open clip start and -100 degrees; heat with the door open, with the clunk landing at the swing end
   * the move reset mid-heat: silent, no button press; cleanup; the restarted client's first heat dings
   * a stream-in mid-heat: only the hum resumes, and the ding still comes.
   Mutation check: with the old `0, 0` init and the old reset handling, the harness reports 9 failures.

## Known limits / open questions
* Nothing has run in Studio yet. The checks so far are renders, luacheck OK, an undeclared-name scan and the offline
  kitchen harness (ALL OK).
* Fix pass: `client/Microwave.lua` and `server/Microwave.lua` began with a UTF-8 BOM, which the Luau CLI rejects. It is
  removed. Install these files as plain UTF-8.
* The open door reaches about 1.7 studs past the front of the hitbox. It is visual only.
* The LCD font is `Enum.Font.Arcade` (pixel look). If the integrator prefers the game font, `FredokaOne` also works.
