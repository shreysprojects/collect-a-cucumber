# DiningTable (package HomeDining, 2026-09-24, fix pass same day)

New Home build: a wooden dining set - a 5 x 4 table (top at y 3.2) with four chairs round it, one per side,
each facing across the table; red runner with yellow stitching draped over both ends, four blue-rimmed
plates each with a cucumber on it, centrepiece = brass candlestick with a lit candle + blue vase of flowers.

| | |
|---|---|
| Model source | `models/build_DiningTable.py` -> `models/out/DiningTable.parts.json` |
| Renders | `models/renders/DiningTable_front.png`, `_three.png`, `_back.png` |
| Size | 8.08 x 4.78 x 7.88 studs (x, y, z), 70 parts (budget 70), category Home |
| Attributes | `Cost` = 900, `DisplayName` = "Dining Table" |
| Scale | authored at 1 - no `BuildCatalog.SCALE` entry needed |

## Fix pass (reviewer findings)
* **Candle never flickered** (client): `math.noise` works in 32-bit floats, so raw server time (~1.79e9)
  lost its fraction and the flame froze. The Step now folds the clock (`t = now % 1000`) before the noise
  calls, like Lantern / TikiTorch / NeonSign. Proven in `tests/HomeDining` (the test fails on the old code:
  1 distinct flame height in 30 frames; passes now: 30 of 30, height swing ~27 %, brightness 0.95..1.69).
* **End sitters pressed into the table**: the table is now 5 long (was 6), so the end chairs' seat centres
  are 0.70 beyond the table end and 0.63 beyond the runner flap (a ~1-deep torso clears it); side chairs are
  1.1 beyond the long edges. Footprint unchanged (8.08 x 7.88).
  *Reviewer's option A (two chairs per long side at x = +/-1.5) was rejected*: side by side at 3.0 spacing,
  two seated avatars' arms (shoulders + arms ~4 wide, ~4.2 at the 6.1 physique) would overlap ~1 stud. One chair
  per side keeps every pair of seats >= 4.46 apart.
* **Seat facing is now authored**: `Pivot_Seat<N>Face` = a point 1 stud straight ahead of each seat; the server
  looks at it (fallback: the table centre). Straight across for every seat, whatever a later layout does.
* **Chair splat floated**: now 1.14 x 1.80 x 0.12 at y 3.46 - overlaps each post by 0.02 and runs 0.02 into the
  crest rail.
* **Knees clipped the apron**: the solid 5.3 x 0.28 x 3.3 apron is now a thin inset underframe 2.8 x 0.14 x 2.2
  (bottom 2.86), >= 1.8 ahead of every seat, so knees (~1.5 forward of the hips) never reach it. The table legs sit
  outside every sitter's leg path. The top is 0.22 thick (underside 2.98).

## Behaviour
* **Server** `src/behaviours/server/DiningTable.lua`: four `ctx:Seat`s named `DiningSeat1..4` (Object "Dining
  Chair", prompt distance 7). Each seat's TOP face sits on `Pivot_SeatN` (cushion top, y 2.13) and its
  LookVector points (level) at `Pivot_SeatNFace`. Seat size 1.6 x 0.4 x 1.6 (x/z scaled with the build).
  Anyone may sit.
* **Client** `src/behaviours/client/DiningTable.lua`: a `PointLight` "CandleGlow" (warm, range 10 x Scale, no
  shadows) inside the Neon `CandleFlame` part, and one `ctx:Step` that flickers the flame: height +/-20 %
  from its foot (the wick stays put), slight narrowing, +/-7 degree sway, orange<->yellow colour, light
  brightness/range breathing. Seeded per table position; server time folded to % 1000 for `math.noise`.
  The flame's Size / CFrame / Color are restored (hitbox-relative) on cleanup. StepRange 140.

## Parts / pivots relied on
* `Pivot_Seat1` (+X end, faces -X), `Pivot_Seat2` (-X end, faces +X), `Pivot_Seat3` (front, faces +Z),
  `Pivot_Seat4` (back, faces -Z) - authored cushion tops; `Pivot_Seat1Face..Seat4Face` - the look targets.
* `CandleFlame` (Ellipsoid = Block + SpecialMesh Sphere, Neon ffb347). `Pivot_Candle` = the candle top (not
  used by code, there for anyone who wants smoke/particles).
* Chair parts `Chair<N>Seat/Cushion/LegFL/LegFR/PostL/PostR/Crest/Splat`, table `TableTop/TableApron/
  TableLeg1-4/TableFoot1-4`, `Runner/RunnerFlapL/R/RunnerStitchF/B`, `PlateRim1-4/Plate1-4/Cucumber1-4`,
  `CandleBase/CandleStem/Candle`, `Vase/VaseNeck/VaseLeafL/R/FlowerRed/Yellow/White`.

## Headless test
`py tests/HomeDining/gen.py` (mock.luau copied from tests/HomeHearth + the module sources + parts.json; Luau CLI):
391 checks, 0 failed - seat tops on the pivots, level, facing their Face pivots, each seat facing the top,
torso >= 0.6 clear of the edge/flap, apron >= 1.7 ahead, knees clear of the table legs, seats >= 4.2 apart,
flame/brightness change every frame on an epoch-sized clock, the flame foot stays on the wick, full restore
on cleanup.

## How to test in Studio
1. Install the model (`install/install_models.lua` with keys `{"DiningTable"}`), add it to the build
   catalog (Home, 900), place it.
2. `workspace.FunBuildRuntime` gets a folder `DiningTable_<owner>_<hex>` holding `DiningSeat1..4`; four "Sit"
   prompts show at the chairs (nearest one at a time). Sit in each: hips on the cushion, facing straight across
   the table, torso not touching the table edge / runner flap. Check the knees under the table from the side.
3. Client: `CandleFlame.CandleGlow` exists; `CandleFlame.Size.Y` changes frame to frame; after moving / selling /
   breaking the build the flame is back to its template Size.

## Sounds wished for
None needed.

## Known limits
* The table is 5 x 4 (the brief said ~6 x 4): a 6-long table would push the end chairs out to a ~9.2 footprint.
* Knee depth is estimated (~1.5 forward of the hips, thigh top ~3.1): the thighs may still slip a little
  under the table top's underside (2.98) - hidden inside the top, not through it (top face 3.2). Check a tall
  physique stage in a playtest.
* The candle glows day and night (one light, brightness ~1.3).
