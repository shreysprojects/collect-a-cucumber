# HomeLaundry package: WashingMachine + Dryer (2026-09-24)

Two new **Home** builds made from primlib parts, with no asset upload. Each has its own behaviour module pair, and
the Dryer modules reuse the washer's engine.

| Key | Size (w x h x d, incl. props on top) | Parts | Cost | Accent |
|---|---|---|---|---|
| `WashingMachine` | 3.46 x 4.94 x 3.82 (cabinet top at 4.0) | 90 | 1200 | blue `3f79d4` |
| `Dryer` | 3.62 x 4.80 x 3.64 (cabinet top at 4.0) | 90 | 1000 | red `d9443c` |

Both are at the 90-part appliance budget. Authored at scale 1 for the 6-stud avatar, so `BuildCatalog.SCALE` is not
needed. Any scale works if you set one.

## Files
* `models/laundrylib.py`: the shared front-loader (cabinet, octagonal opening, drum, door, console, pivots).
* `models/build_WashingMachine.py`, `models/build_Dryer.py`: the two builds (top props, the dryer's side vent).
* `models/out/WashingMachine.parts.json`, `models/out/Dryer.parts.json`: for `install/install_models.lua`,
  category `Home`.
* Review only, not installed: `models/build__WasherOpen.py`, `models/build__DryerOpen.py` (door open, water
  shown, louvres open), `models/build__WasherRun.py` (door SHUT, water shown: the mid-wash look through the porthole).
  Their `out/*.json` were deleted. `models/laundry_views.py` renders extra angles.
* Renders:
  * `models/renders/WashingMachine_{front,three,back}.png`
  * `models/renders/Dryer_{front,three,back}.png`
  * `models/renders/_WasherOpen_*.png`, `_DryerOpen_*.png`, `_DryerOpen_sideA.png` (the vent side)
  * `models/renders/_WasherRun_{front,three,back}.png` (mid-wash, door shut)
* `src/behaviours/server/WashingMachine.lua` goes to `ServerStorage.FunBehaviours.WashingMachine`. It is the engine;
  `Make(kind)` is exported.
* `src/behaviours/server/Dryer.lua` goes to `ServerStorage.FunBehaviours.Dryer`. It is
  `require(script.Parent.WashingMachine).Make("Dryer")`.
* `src/behaviours/client/WashingMachine.lua` goes to `ReplicatedStorage.FunBehavioursClient.WashingMachine` (the engine).
* `src/behaviours/client/Dryer.lua` goes to `ReplicatedStorage.FunBehavioursClient.Dryer`, which requires the sibling.
* **Install all four.** Each Dryer module does `WaitForChild("WashingMachine", 10)` on its sibling.
* `tests/HomeLaundry/`: an offline harness that runs the real framework, the four modules and the two models in a
  mock world. `powershell -File tests\HomeLaundry\run.ps1` currently reports 0 failed checks, 0 runtime errors and
  0 warnings. Since the fix pass it also checks the authored DoorGlass material, "Door locked" mid-cycle, prompts
  staying hidden when a cycle ends in build mode, every cloth landing near its own angle, no cloth left high up the
  wall once the drum stops, and the client patch for an old Glass porthole. Both old bugs fail these checks.

## Look
A white chunky front-loader on rubber feet with a dark toe-kick plinth and rounded front edges. It has a rolled
top-front lip, an accent trim strip under the console, and a small accent badge with a tiny cucumber on it.

The porthole is a domed glass in a 16-segment chrome ring. It is **SmoothPlastic** (tint `d4eeff`, Transparency 0.55,
Reflectance 0.15), not Roblox Glass: the Glass material hides every transparent part and particle behind it, so the
Water and suds would never show through the shut door (the same limit `notes/GlassCase.md` hit). It has an accent handle on the
viewer's right, and a chrome hinge plate and pin on the viewer's left.

Behind the glass the cabinet is really hollow. The opening is octagonal (a square hole plus 4 corner wedges), and
the drum sits inside it: 9 DiamondPlate slats (40 degrees apart, the baffles on slat centres), 3 white baffles, a back plate with 3 dark spokes, and clothes lying
at the bottom. The washer's clothes are a red sock, a yellow shirt, purple pants and a cucumber. The dryer's are a
pink towel, a white sock, a teal shirt and a cucumber.

The console has:
* a detergent drawer (washer) or a lint-trap pull (dryer)
* a dark screen in an accent bezel
* an LED and a green start button
* a timer dial with a chrome ring, a tick, an accent knob, a cap and a pointer

On top, the washer has folded pink and teal towels and an orange detergent jug. The dryer has a yellow basket of
clean laundry with a blue sock hanging out. On the back, the washer has a service plate, hot and cold taps and a
power cord. The cord hugs the back face (overlapping it by 0.02) from a dark strain-relief plug (`PowerPlug`)
down to the floor. The dryer has the same cord and plug and a round louvred chrome exhaust vent on its -X side (the viewer's right).

## Parts and pivots the behaviour relies on (authored frame, scale 1)
* `Drum*` is the rigid drum: `DrumBack`, `DrumSlat01..09`, `DrumBaffle1..3`, `DrumSpoke1..3`. It spins about the
  authored-Z axis through `Pivot_Drum` (0, 1.78, -0.96).
* `DrumCloth1..4` are the clothes, which the client tumbles separately. Each one's angle from the drum bottom is read
  from its rest position. A cloth that falls lands within 0.3 rad of its OWN authored angle (never all at the
  bottom), and when the drum stops, a cloth left more than 1.25 rad up the wall slides back down.
* `Door*` is `DoorRing01..16`, `DoorGlass` (SmoothPlastic, see Look), `DoorShine`, `DoorHandle` and `DoorArm`. They swing about the vertical axis
  through `Pivot_DoorHinge` (1.36, 1.78, -1.72). Open is -105 degrees about +Y, which swings the door out to the front
  on the +X side. `HingePlate` and `HingePin` stay fixed.
* `DialKnob`, `DialCap` and `DialPointer` turn about authored Z through `Pivot_Dial`. `DialRing` and `DialTick` stay
  fixed.
* `Screen` shows the countdown on its Front face (-Z). `Led` is Neon and gets recoloured. `ButtonStart` sinks 0.05 along
  +Z when pressed.
* `Water` (washer only) is authored INVISIBLE (Transparency 1), 1.8 x 0.74 x 1.05. Its corners sit outside the drum,
  hidden in the cabinet cavity. `Pivot_WaterTop` is its surface.
* `VentSlat1..3` (dryer only) tilt about their own authored Z. The lint blows from `Pivot_Vent` toward `Pivot_VentOut`.
* `Pivot_StartPrompt` and `Pivot_DoorPrompt` are where the prompts float. `Pivot_DoorCentre` is the front of the glass,
  where the sparkle burst comes from.
* Model attributes: `Cost`, `DisplayName`, `Notes`.

## What it does
**Server** (state only, nothing moves):
* **"Start" prompt (E / ButtonX)** in front of the screen. It sets `Fun_CycleEnd = Kit.Now() + 15`, and a timer resets
  it to `0`. While a cycle runs the prompt reads **"Stop"** and ends it early. Starting shuts an open door first.
* **"Open door" / "Close door" prompt (F / ButtonY)** on the porthole toggles `Fun_Door`. It only works while idle: mid-cycle it
  reads **"Door locked"** and presses do nothing. The server never toggles a prompt's `Enabled` (that replicates and
  would undo FunBuildClient's build-mode hide).
* Anyone may use it. There is no economy effect. Presses are debounced by 0.6 s.

**Client** (driven by `Fun_CycleEnd` + `Kit.Now()`, so every client shows the same moment):
* **Washer, 15 s:**

  | Time | Phase | What happens |
  |---|---|---|
  | 0 - 1.4 s | FILL | Blue water rises behind the glass, with a pour loop. |
  | 0.6 - 9.4 s | WASH | The drum turns about 320 degrees one way, stops, then turns back, twice. The clothes ride up the wall and tumble down through the middle. The water sloshes with the drum, and suds rise. |
  | 9.4 - 10.6 s | DRAIN | The water drains, with the pour loop. |
  | 10.6 - 14.6 s | SPIN | The drum reaches 22 rad/s. The clothes are pinned to the wall, the hum pitches up and the machine shakes hardest. |
  | 15 s | Done | Ding, a sparkle burst off the glass, and the screen blinks DONE / CLEAN!. |

* **Dryer:** the drum turns steadily at 4.4 rad/s. The clothes are carried nearly to the top before they drop. Other
  effects:
  * A warm orange glow inside the drum.
  * Warm cream lint puffs and white fluff flecks out of the side vent, while the louvres flutter open.
  * A gentle jiggle.
  * Amber screen text: DRY, then COOL for the last 3.5 s, then Ding and FLUFFY!.
* **Both machines:**
  * The whole machine jiggles about its feet (smoothed noise on every part). The Hitbox never moves, so the
    framework's move watcher is not triggered.
  * The screen is a SurfaceGui in PlayerGui, adorned to `Screen`, with `ResetOnSpawn` false. It shows `0:12` plus the
    phase and a progress bar, and READY / OPEN when idle.
  * The dial winds up and runs back with the time left, and the LED pulses.
  * The hum loop only plays within 55 studs.
  * The door swings open with a little spring bounce and shuts with a thunk.
* All motion is relative to the Hitbox (`BulkMoveTo`, one `ctx:Step`). The idle machine does no per-frame part work.
  Rest poses come from the template in `ReplicatedStorage.PlaceableBuilds` (Hitbox space), or from the placed copy if
  the template is missing or re-scaled.
* Cleanup puts every part back relative to where the build is now. It restores the Water's size and transparency and
  the Led colour. This is safe for a move, sale, break or stream-out mid-cycle; all of these are tested offline.
* Lights: 1 PointLight per machine (the drum light). Particles: suds up to 12/s; lint 6/s + 7/s; a sparkle burst of 16.

## How to test in Studio
1. Install the models (`install_models.lua` with `{"WashingMachine", "Dryer"}`) and the four behaviour modules. Place
   both in a plot.
2. In a playtest, press the prompts. Alternatively, on the **server** use the test hook:
   `model:SetAttribute("LaundryPress", "Start")` or `model:SetAttribute("LaundryPress", "Door")`. It clears itself.
3. Read the states:
   * **Server:** `model:GetAttribute("Fun_CycleEnd")` (0 when idle) and `Fun_Door`.
   * **Client, mid-wash:**
     * `Water.Transparency == 0.42`, and the water shows through the SHUT porthole (DoorGlass is SmoothPlastic).
     * `PlayerGui.LaundryScreen` has `Time` = `0:NN` and `Phase` = WASH/SPIN/DRY/COOL.
     * `workspace.CurrentCamera.LaundryFX` has the `Hum` sound playing.
     * The dryer's `workspace.CurrentCamera.LaundryVent` has `Puffs.Enabled` true.

## Sounds (FunAssets.Sfx)
Used: `WasherLoop` (hum, pitched by drum speed), `WaterLoop` (fill / drain), `Ding`, `Click` (start / stop), `DoorOpen`,
`DoorClose`. The dryer asks for `DryerLoop` first and falls back to `WasherLoop`.

**Wishes:**
* `WasherLoop`: a real washing-machine drum slosh / hum loop. Today it is "Rock Crumble".
* `DryerLoop`: a soft tumbling hum with the odd button clunk.
* A short water-fill gush.
* A chunky door "clunk".

## Known limits / notes for the integrator
* The door ring is 16 chrome cylinder segments, so the joints show small bumps. At game scale it reads as a chunky
  porthole ring.
* `DoorGlass` collides and the other door parts don't. The door only swings on clients. On the server it stays shut, so
  other players' collisions don't see an open door.
* **Reinstall both models** from the new `out/*.parts.json` (2026-09-24 fix pass: DoorGlass SmoothPlastic, 9 slats,
  PowerPlug). A copy still installed from the old export (DoorGlass = Glass) is patched on each client: while the
  behaviour runs its DoorGlass is drawn SmoothPlastic (Reflectance >= 0.15), restored on cleanup. The server and
  build-mode previews would still show the old Glass until the reinstall.
* primlib rounds part rotations to 5 decimals, so an idle part is exact in position and within about 1e-5 in rotation.
