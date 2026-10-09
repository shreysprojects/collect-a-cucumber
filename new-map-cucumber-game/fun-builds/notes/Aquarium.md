# Aquarium (package HomeDecor, 2026-09-24)

New Home build: a fish tank on a wooden cabinet. Blue-doored wooden cabinet (plinth, raised door panels, brass
knobs, top slab with a rounded lip) under a black-framed tank: translucent blue water with a paler surface layer,
sand gravel sloping up to the back, coloured pebbles, a blue backdrop with a darker reef, a stone castle (square
towers with red pyramid roofs, crenellated keep, arched door, yellow flag), a treasure-chest bubbler, grey rocks,
four plant clumps (tall green at both back corners, red in the back middle, small lime at the front left), a Neon
light bar along the back under the rim, a black hood over the back half, glass covers over the front half with a
black FEED FLAP in the middle, and a yellow fish-food tub on the hood.

| | |
|---|---|
| Model source | `models/build_Aquarium.py` -> `models/out/Aquarium.parts.json` |
| Renders | `models/renders/Aquarium_front.png`, `_three.png`, `_back.png`; the client's fish + flakes mid-feeding (from the Lua, see Testing): `tests/HomeDecor/renders/aqua_feed_front.png`, `aqua_feed_top.png` |
| Size | 6.6 x 7.38 x 3.18 studs (x, y, z); the tank is 6.04 x 3.4 on a 3.05-high cabinet, hood top 6.7, food tub 7.38 |
| Parts | 85 (it's an appliance-sized showpiece: under the 90 "big appliance" budget, over the 70 furniture one) |
| Attributes | `Cost` = 1500, `DisplayName` = "Aquarium", `Notes` |
| Scale | authored at 1, no `BuildCatalog.SCALE` entry needed (everything handles `Scale` if one is added) |

Glass and water are **SmoothPlastic + Transparency** (glass 0.86, water 0.64, surface layer 0.72), never the Glass
material: Roblox does not draw transparent parts or particles behind a Glass-material part, so the water, the
bubbles and the flakes would vanish behind the front pane.

## Behaviour
* **Server** `src/behaviours/server/Aquarium.lua`: a "Feed fish" prompt (`FeedPrompt`, object "Aquarium",
  distance 10) on the `FeedFlap` part. Anyone may feed (harmless). Pressing it sets state **`Fun_FedAt`** = the
  server time (`Kit.Now()`); presses within 7 s of the last feeding are ignored and the prompt reads
  "Fish are eating..." until the cooldown ends. That number is the whole shared state. No economy impact.
* **Client** `src/behaviours/client/Aquarium.lua` (one `ctx:Step`, StepRange 140, one BulkMoveTo per frame):
  * **5 fish from local parts** (about 50 parts, parented to the camera): clownfish (orange, white stripes), blue
    tang (blue, navy fins, yellow tail), yellow tang (with a snout), royal gramma (purple front, yellow back), and a
    neon tetra (Neon stripe, red belly). Each has an ellipsoid body, white eyes with pupils, a dorsal wedge (anal
    fin on the tall ones) and a two-wedge fan tail that wags faster when it swims faster. Each swims its own closed
    loop (an ellipse with a vertical wave, a time warp so it speeds up and glides) in the water box
    `Pivot_TankMin..Pivot_TankMax`. The loops were fitted offline to this tank: in 40 s of testing no fish comes
    closer than 0.2 to the glass or 0.23 to the surface, none enters the castle, and fish centres stay 0.51+ apart.
    Positions come only from the server clock, so every client shows the same fish in the same place.
  * **Bubbles** trickle from the chest (`Pivot_Bubbler`, 3/s) and pop at the surface (lifetime = rise / speed).
    `Pivot_Bubbler` (1.72, 4.02, -0.66) sits just in front of the lid's front edge (z -0.61 when shut), so the
    column rises clear of the lid in every pose (fix pass: it used to start inside the shut lid and pop out of its
    top face; the harness now checks the column against the lid and chest every frame).
    Every 7 s the **chest lid** (`ChestLid` about `Pivot_ChestHinge`; it rests shut, 22 degrees below the authored
    ajar pose) pops open to 46 degrees and lets out a burst of 9 big bubbles.
  * **Plants** (`Plant<N>Leaf<M>`) sway +-5 degrees about their clump's `Pivot_Plant<N>`, each leaf with its own
    phase; the **castle flag** waves about `Pivot_Flag`; a **PointLight** (pale blue, range 9 x Scale) at
    `Pivot_Light` lights the water; the Neon light bar is part of the model.
  * **Feeding** (driven by `Fun_FedAt`, lasts 6.5 s): the `FeedFlap` (+ `FeedFlapTab`) swings up 68 degrees about
    `Pivot_FeedHinge` (0 - 0.25 s, shut again by 1.55 s, with a click; a client that streams in or wakes up after
    the close does not click for it). 12 flakes (orange / red / yellow / green /
    tan) drop from under the flap onto the water at `Pivot_Feed` (a ring on the water where each lands, one soft
    splash) and drift out across the surface. The fish, in the order they are across the tank, split the flakes
    into side-by-side bands (3 / 3 / 2 / 2 / 2) and each rushes up and eats its band nearest-first, nose up while
    nibbling; every flake vanishes with 3 tiny bubbles and a quiet gulp. Then they blend back into their loops.
    Where two fish crowd the food they are nudged apart (0.45 studs), deterministically. The flakes, the plan and
    every position are a pure function of `Fun_FedAt`, so every client (and one streaming in half-way) sees the
    same show; a late client does not replay landings or gulps that already happened.
  * Cleanup puts the leaves, flag, chest lid and flap back at rest relative to the build's current hitbox.

## Parts / pivots relied on
* Animated: `Plant1Leaf1-5`, `Plant2Leaf1-4`, `Plant3Leaf1-4`, `Plant4Leaf1-3` (long axis = local Y),
  `CastleFlag`, `ChestLid`, `FeedFlap`, `FeedFlapTab`. The prompt sits on `FeedFlap`.
* Pivots (authored): `TankMin` (-2.9, 3.62, -1.2), `TankMax` (2.9, 5.94, 1.2), `WaterSurface`, `Feed`
  (0, 5.94, -0.745), `FeedHinge`, `Bubbler`, `ChestHinge`, `Light`, `Flag`, `Plant1-4`, `Castle`.
* Static look parts: `Water`, `WaterTop`, `Gravel`, `GravelSlope`, `Glass*`, `Backdrop*`, `Rim*`, `Post1-4`,
  `TankBase`, `Hood*`, `Cover L/R`, `TankLight` (Neon), `Castle*`, `Chest*`, `Rock*`, `Pebble*`, `Food*`, cabinet.

## Sounds (FunAssets.Sfx; all skipped while the player's `SFXEnabled` attribute is false)
* `BubblesLoop` (looped, volume 0.14) while the camera is within 45 studs; `Click` for the flap; `Splash`
  (pitched up, quiet) when the flakes land; `Gulp` (pitched up, quiet, at most one per 0.15 s) per flake eaten.
* Wished for: a soft aquarium-filter hum for the loop, a food-shaker rattle for the flap, a tiny "plip" for gulps.

## How to test
1. Install the model (`install/install_models.lua` with `{"Aquarium"}`), add it to the build catalog (Home, 1500),
   install both behaviour modules, place it.
2. Look at it: 5 fish swim, bubbles rise from the chest, the lid pops every 7 s, the plants sway.
3. Press E on "Feed fish" (top front of the tank): the flap opens, flakes sprinkle and spread, all fish come up and
   eat every flake within ~5 s. Checks: model attribute `Fun_FedAt` = the press time; the prompt
   `FeedFlap.FeedPrompt` reads "Fish are eating..." for 7 s; on the client, 12 `FishFlake` parts under the
   Camera turn visible and back to Transparency 1 by 6.5 s; the 5 `FishBody` parts rise to within 0.3 x Scale of
   the water surface.
4. Offline: `cd tests/HomeDecor; py gen.py; luau run.luau` (the mock harness) - 25,648 checks, 0 failures: both halves,
   scale 1 and 1.3, rotated placements, three clients (one joining mid-feeding) showing identical fish, 24 feedings
   surveyed for fish spacing, the bubble column clear of the chest lid, no stale flap click on a late client,
   cleanup restoring every part. `render_dump.py` renders what the Lua builds.

## Known limits
* The fish are visual only (CanQuery/CanCollide off) and sleep with the rest of the behaviour when the camera is
  more than 140 studs away.
* Anyone can feed; a 7 s cooldown keeps it one feeding at a time.
* The flap sweeps a few hundredths of a stud through the hood's rounded front while it opens (hidden overlap).
