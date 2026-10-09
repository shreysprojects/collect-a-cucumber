# Cucumber set, rev 3: Toyland + Neon (2026-09-18)

**14 new models, two new biomes.** The user sent a reference sheet (`ref-toyland-neon/_sheet.png`,
one crop per model beside it: `ref-toyland-neon/<Collection>.png`) and asked for these to
**replace every cucumber in the game's Toyland and Neon biomes**, which until now had no
hand-modelled set, only part-built generic cucumbers.

Everything in `CUCUMBERS.md` still applies: space and scale, style, the `cucumberlib` API,
the hard rules, the module shape and `dryrun.py`. Read that document's sections up to "The
57 briefs" first. This file only adds the new palette keys and the 14 briefs.

**Transcribe each tile literally.** Colours, parts and features come from the reference
crop, not from a general rule about the biome. Where a brief and the tile disagree, the tile
wins; say so in `NOTES`.

**Two deliberate departures from the tiles, for the game's sake:**

1. **Cucumber bodies stand upright** (like all 57 existing models), even where the tile shows
   the cucumber leaning. The game spins every cucumber to a random yaw, and a leaning body
   would change its footprint and its ground contact. Decorations (rings, straps, a hat)
   may tilt; the body does not. The hologram floats and may lean up to 10 degrees.
2. **Slices are ONE disc standing upright, cut face to +Y** (`D.slice_stand(loc, lean_deg=0)`),
   lowest point on z = 0. The game lays an upright disc flat in the field automatically, and
   the index card shows it standing like the tile. It must stay thin front-to-back: its
   Y-extent must be under **0.45 x** its X/Z extents, or the game will not lay it down. So no
   lean, and nothing sticking out of the faces further than about 0.1.

## Where the files go

| Collection | file | archetype |
|---|---|---|
| `ToylandToySlice` | `build_toyland_toy_slice.py` | slice |
| `ToylandLegoCucumber` | `build_toyland_lego_cucumber.py` | cuke |
| `ToylandJackInTheBoxCucumber` | `build_toyland_jack_in_the_box_cucumber.py` | cuke |
| `ToylandToyRocketCucumber` | `build_toyland_toy_rocket_cucumber.py` | cuke |
| `ToylandPinwheelPlant` | `build_toyland_pinwheel_plant.py` | cuke |
| `ToylandBuildingBlockTree` | `build_toyland_building_block_tree.py` | tree |
| `ToylandToyTrainCucumber` | `build_toyland_toy_train_cucumber.py` | prop |
| `NeonNeonSlice` | `build_neon_neon_slice.py` | slice |
| `NeonElectroCucumber` | `build_neon_electro_cucumber.py` | cuke |
| `NeonGridCucumber` | `build_neon_grid_cucumber.py` | cuke |
| `NeonHologramCucumber` | `build_neon_hologram_cucumber.py` | cuke |
| `NeonPalm` | `build_neon_palm.py` | tree |
| `NeonTree` | `build_neon_tree.py` | tree |
| `NeonCyberCucumber` | `build_neon_cyber_cucumber.py` | cuke |

All 14 are registered in `buildall.py` (groups `toyland` and `neon`).

## New palette keys (in `cukemath.py`)

```
toy_red toy_red_dk toy_blue toy_blue_dk toy_yellow toy_yellow_dk toy_green toy_green_dk
toy_white toy_white_sh toy_brown toy_brown_dk toy_magenta toy_orange toy_eye toy_eye_hl
toy_face_lt toy_spoke

neo_night neo_night_dk neo_night_lt neo_trunk neo_cyan neo_magenta neo_purple neo_pink
neo_lime neo_holo neo_holo_lt neo_green neo_green_dk neo_goggle neo_goggle_dk neo_lens
```

Plus everything already there (`cuke_*`, proplib's `plastic_*`, `neon_*`, ...).

## Materials

- **Toyland is toy plastic:** `"SmoothPlastic"` on everything except the cucumber skin, which
  stays `"SmoothPlastic"` too. No `"Neon"` in Toyland apart from the rocket's little flame.
- **Neon glows:** every glowing tube, ring, band, grid line, pixel and light strip is
  `rbx_material="Neon"` with `emit=0.6` (the render cap for this set is 0.65: above it,
  warm hues wash out to yellow and the review render lies). Dark bodies are
  `"SmoothPlastic"` (or `"Metal"` for pedestals). Cucumber skin stays `"SmoothPlastic"` green.
- Never `metallic`, never `roughness` under 0.32 (see `README.md`, "Blender-only
  appearance parameters").

## Faces (three Toyland cucumbers have one)

The Jack-in-the-Box head, the Toy Rocket head and the Toy Train cucumber have a cartoon face
on their **+Y facet** (the front): two eyes, and on two of them a mouth.

- **Eye** = a black rounded square (`toy_eye`, about 0.30 wide x 0.36 tall, 0.05 proud of the
  skin), with a small white square highlight (`toy_eye_hl`, 0.10) in its upper outer corner,
  0.02 proud of the eye. Eyes ~0.42 apart, centre to centre.
- **Mouth** = a short dark bar or a 3-segment smile made of small boxes, `toy_eye`.
- Place them with `D.cuke_point` / `D.cuke_facet_point` at angle 90 (facet 1 = +Y) and
  `D.surface_frame(normal)` so the squares sit flat on the facet. **Eyes and highlights are
  separate parts** (`Eyes`, `EyeShine`), merged across both eyes.

---

# The 14 briefs

Standard body = `h=D.CUKE_H, r=D.CUKE_R`, nub `(0.30, 0.30)`. Standard speckles =
`rows=7, per_row=3, z0=0.11, z1=0.90, size=0.28`.

---

## toyland

### `ToylandToySlice` - `build_toyland_toy_slice.py`
Tile: a single chunky cucumber slice standing on its edge. Dark green rind, bright light-green
cut face with a pale centre and pale radial spokes, lighter squares on the rind.

- **One disc, standing upright, cut face to +Y**: `m = D.slice_stand((0, 0, R), lean_deg=0)`
  with `R = 0.86`, `thick = 0.46` (a touch chunkier than standard). With the lib's default
  phase a 10-gon vertex points straight down once stood up, so a centre at z = R puts the
  lowest point on z = 0.
- `Rim` - `D.slice_disc`, `toy_green_dk`.
- `RimStuds` - `D.slice_studs(n=7, size=0.20)`, `cuke_stud`.
- `Face` - `D.slice_face(inset=0.10)`, `toy_face_lt`.
- `Spokes` - 8 thin pale radial bars on EACH cut face, from a small pale hub (a flat
  0.18-radius disc) out to 0.78 of the face radius, 0.07 wide, 0.02 proud of the face;
  plus the hub. `toy_spoke`. Build them in the disc's local frame and transform by `m`.
- `Seeds` - `D.slice_seeds(n=6, size=0.14, ring=0.45, centre_seed=False)`, `cuke_seed`.
- ~1.72 x 0.5 x 1.72. 5 parts.

### `ToylandLegoCucumber` - `build_toyland_lego_cucumber.py`
Tile: a green cucumber covered in chunky raised bumps, capped with a **yellow LEGO brick**
(a square plate with one round stud on top), and a small **white peg** poking out under it.

- `Peg` - white cylinder r 0.22, z 0 .. 0.16, centred; `toy_white`. The cucumber stands on it.
- `Body` - standard body lifted by 0.16 (use `matrix=D.place((0, 0, 0.16))` or equivalent),
  **no nub** (the brick replaces it); `cuke_green`.
- `Bumps` - the set's speckles but chunkier and DARKER than the body, the way the tile's
  bumps read: `D.cuke_studs(rows=7, per_row=3, size=0.30, rise=0.09, seed=4)`, lifted with
  the body, colour `cuke_mid`.
- `Brick` - yellow `beveled_box` 1.10 x 1.10 x 0.34 sitting ON the body's flat top
  (top z = 4.16), tilted 8 degrees about X like a cap slightly askew; `toy_yellow`.
- `BrickStud` - one round stud on the brick: cylinder r 0.26, h 0.18, 12 segs, on the brick's
  top centre (same tilt); `toy_yellow_dk` (one step darker so it reads).
- ~1.5 x 1.5 x 4.7. 5 parts.

### `ToylandJackInTheBoxCucumber` - `build_toyland_jack_in_the_box_cucumber.py`
Tile: a red toy box with a big yellow star on each side, open at the top; a green coiled
spring rises out of it holding up a cucumber head with a cartoon face and a red bowler hat.
Two yellow sticks lean out of the box's back corners (the open lid's hinges) and a small
yellow crank handle sticks out of its right side.

- `Box` - `beveled_box` 2.4 x 2.4 x 2.1 (z 0 .. 2.1), `toy_red`, bevel 0.10. Plus a slightly
  proud rim band round the top edge (2.52 x 2.52 x 0.22 at z 1.90 .. 2.12) in the SAME part.
- `Stars` - one yellow 5-point star plate on each of the 4 sides, centred at z 1.0, outer
  radius 0.62, inner 0.27, 0.06 proud of the face (`D.star_pts` + a thin prism/extrusion,
  or `ngon_face`); `toy_yellow`.
- Sticks: two yellow square sticks 0.12 x 0.12 x 1.5 from the back top corners
  (x = +-1.0, y = -1.0, z 2.0) leaning OUTWARD 25 degrees and back 10; plus the crank at
  **negative x** (the tile's right): a 0.5 stub along -X from the side at z 1.1, ending in a
  short upturned handle 0.14 x 0.14 x 0.4. Stars, sticks and crank are ONE part `Yellow`,
  `toy_yellow` (same colour + material).
- `Spring` - `D.coil` (or `D.helix_pts` + a tube) from z 2.05 up to z 3.25, radius 0.55,
  4.5 turns, wire 0.13; `cuke_green`.
- `Head` - a cucumber: a standard body scaled to h 2.3 (r 0.70), base at z 3.15, with a nub;
  `cuke_green`. `HeadStuds` - `D.cuke_studs` on the head (rows 3, per_row 3), `cuke_stud`.
  Keep the face facet (+Y, angle 90) free of studs.
- `Eyes` + `EyeShine` - see "Faces": eyes at zf 0.62 of the head, +-0.22 from centre.
  `Nose` - a small green bump (0.26 cube, bevelled) just under the eyes, `cuke_mid`.
- `Hat` - a red bowler: a flat 10-gon brim r 0.95 x 0.10 and an 8-sided crown r 0.62
  tapering to 0.52, 0.55 tall, sitting on the head top and tilted 10 degrees about X toward
  the viewer; `toy_red`. May share the `Box` part (same colour + material).
- Total height ~6.0. <= 12 parts, <= 2200 tris.

### `ToylandToyRocketCucumber` - `build_toyland_toy_rocket_cucumber.py`
Tile: a cucumber riding in a white toy rocket. The rocket body is a white 8-sided tube with a
red rim at its top and a blue round porthole on the front; the cucumber's head (face: eyes,
open smile, dark cheek dots) pokes out of the top wearing a red nose cone; three red fins
(left, right, and one on the front with a yellow and an orange dot) and a blue base ring.

- `Base` - blue 8-sided ring/drum r 0.92, z 0 .. 0.45; `toy_blue`.
- `Hull` - white 8-sided lathe from z 0.45 to z 2.9, r 1.02 bulging to 1.08 in the middle;
  `toy_white`.
- `Red` (one part, `toy_red`): a band r 1.10, z 2.80 .. 3.00 round the hull top; three
  fins (thick wedges 0.22 thick, 1.05 tall, reaching 0.75 out from the hull), one on each
  side (+X and -X) and one on the FRONT (+Y), bottoms at z 0.05; and the nose cone (below).
- `Porthole` - blue ring (outer r 0.42, inner 0.28, 0.08 proud) on the hull front at z 1.9,
  plus a slightly recessed darker disc inside; ring `toy_blue`, inner disc `toy_blue_dk`.
- `FinDots` - a yellow (upper) and an orange (lower) square on the front fin, 0.02 proud;
  if two colours are needed use two parts (`DotYellow` `toy_yellow`, `DotOrange` `toy_orange`).
- `Head` - the top of a cucumber: an 8-sided body r 0.78 rising from inside the hull (z 2.6)
  to z 4.25 with a rounded top, `cuke_green`; `HeadStuds` a few speckles, `cuke_stud`,
  none on the face facet.
- `Eyes` + `EyeShine` at zf ~0.55 of the visible head; `Mouth` = an open smile (a small
  dark trapezoid / 3 boxes) under them; two tiny dark cheek squares. Merge mouth + cheeks
  into `Eyes` (same colour).
- `Red` also holds the **nose cone**: an 8-sided cone r 0.62 at its base, 0.95 tall, sitting
  on the head top.
- Total height ~5.2. <= 12 parts.

### `ToylandPinwheelPlant` - `build_toyland_pinwheel_plant.py`
Tile: a toy pinwheel "flower" on a curved green stem, planted in a green toy brick with round
studs on top. Six folded blades round a red hub with a green centre stud: going clockwise
from the top-left as you face it, blue, red, yellow, green, green, yellow.

- `Brick` - green `beveled_box` 2.2 x 2.2 x 0.95 (z 0 .. 0.95), `toy_green`; `BrickStuds` -
  four round studs r 0.30 x 0.18 on its top (2 x 2 grid, 1.0 apart), same part as Brick is
  fine (same colour) - make it ONE part `Brick`.
- `Stem` - a gently S-curved square-section stem (`D.branch_box` segments, 0.26 wide) from
  the brick top up to the hub at (0, 0.10, 4.4), `toy_green_dk`.
- The pinwheel faces **+Y** (the viewer), its disc in the XZ plane, centred at z 4.4.
  Each **blade** is a folded kite: a flat triangle from the hub out to radius 1.55, 0.08
  thick, with its outer half twisted/folded forward ~25 degrees (two triangles sharing an
  edge) so it reads as a pinwheel vane, not a flat fan. Blades at 60-degree steps.
  Colour by blade: one part per colour: `BladeBlue` `toy_blue`, `BladeRed` `toy_red`,
  `BladeYellow` `toy_yellow` (x2), `BladeGreen` `toy_green` (x2). Remember +X renders on
  the LEFT: the tile's top-left blue blade is at +X.
- `Hub` - red 10-gon disc r 0.36 x 0.20 on the front of the blades, `toy_red`; plus a green
  stud r 0.16 x 0.14 on it (put the stud in the `BladeGreen` part).
- ~3.2 x 2.2 x 6.0. <= 9 parts.

### `ToylandBuildingBlockTree` - `build_toyland_building_block_tree.py`
Tile: a tree built from toy bricks. A trunk of stacked brown bricks (visible seams), a crown
of stacked green bricks in three staggered layers with round studs on the top faces.

- `Trunk` - brown bricks: 4 stacked `beveled_box` blocks 1.25 x 1.25 x 1.25 from z 0 to
  z 5.0, alternating slightly (+-0.04) so the seams read, `toy_brown`; a thin seam band
  between blocks can be `toy_brown_dk` (part `TrunkSeams`) or just rely on bevels.
- `Crown` - green bricks (`beveled_box`, bevel 0.08), studded:
  - layer 1 (z 5.0 .. 6.3): a wide slab of 4-5 bricks spanning ~6.4 x 3.4, staggered;
  - layer 2 (z 6.3 .. 7.6): ~5.6 x 3.0, offset half a brick;
  - layer 3 (z 7.6 .. 9.0): ~3.6 x 2.6, centred a bit back;
  - top (z 9.0 .. 10.0): one 2.4 x 2.0 brick.
  Brick sizes like 2.0 x 1.6 x 1.3 so the brick pattern shows. `toy_green`.
- `CrownStuds` - round studs (cylinders r 0.30, h 0.20, 12 segs) on every exposed top face
  of the crown bricks, on a 1.0 grid, <= 26 studs. The tile shows them the crown's own green;
  make them one step LIGHTER (`plastic_green`) so they still read at distance.
- Optional: a few crown bricks in `toy_green_dk` for value variation (part `CrownDark`).
- ~6.4 x 3.4 x 10.2. <= 4500 tris, <= 6 parts.

### `ToylandToyTrainCucumber` - `build_toyland_toy_train_cucumber.py`
Tile: a chunky toy train engine seen from the side. Blue chassis on a red undercarriage with
four yellow wheels (dark yellow hubs); at the FRONT a red chimney column with a wide yellow
cap and small magenta blocks at its foot; at the BACK a blue open tub (the cab) with a big
green cucumber sitting in it (two little dark eyes).

The train's long axis is **X**; its side faces +Y (the viewer). The chimney is at the
**front = +X** (the tile's left, remember +X renders on the LEFT).

- `Chassis` - blue `beveled_box` 4.4 x 1.9 x 0.75, z 0.55 .. 1.30; the cab tub - a blue open
  box 1.9 x 1.9 x 0.95 on the back half (x -2.2 .. -0.3), z 1.30 .. 2.25, walls 0.18 thick
  (build as 4 wall boxes + floor); plus a small blue block between. All `toy_blue`.
- `Under` - red box 3.6 x 1.3 x 0.5 under the chassis, z 0.30 .. 0.80, `toy_red`; the chimney
  (red 8-sided column r 0.42, z 1.30 .. 2.9, at x +1.45) in the same part.
- `Wheels` - four yellow cylinders r 0.55, 0.30 thick, axis along Y, at x +-1.35, on both
  sides (y +-0.95), lowest point on z 0; `toy_yellow`. `Hubs` - a darker yellow hub disc
  r 0.22 x 0.10 on each wheel's outer face, `toy_yellow_dk`.
- `Cap` - the chimney's wide yellow cap block 1.15 x 1.15 x 0.45 on top (z 2.9 .. 3.35),
  `toy_yellow` (merge into `Wheels`: same colour + material).
- `Blocks` - two magenta cubes 0.45 at the chimney foot, `toy_magenta`.
- `Cuke` - a squat cucumber (`D.CUKE_PROFILE_STUB` if it suits, or a standard body at
  h 2.4, r 0.82) standing in the tub, base at z 1.45, top ~z 3.85, nub on top,
  `cuke_green`; `CukeStuds` speckles, `cuke_stud`; `Eyes` = two small dark squares
  (0.18) facing +Y at zf 0.45 (no highlights needed).
- ~4.6 x 2.1 x 3.9. <= 12 parts, <= 2800 tris.

---

## neon

### `NeonNeonSlice` - `build_neon_neon_slice.py`
Tile: one cucumber slice standing on its edge, framed by a glowing magenta-purple neon ring.
Lime cut face with pale radial spokes, dark green rind.

- **One disc, standing upright, cut face +Y**, `R = 0.82`, `thick = 0.42`, lowest point on
  z = 0 (see the Toy Slice note about the 10-gon's lowest vertex).
- `Rim` - `D.slice_disc`, `cuke_dark`. `RimStuds` - `D.slice_studs(n=6)`, `cuke_stud`.
- `Face` - `D.slice_face(inset=0.10)`, `neo_lime`, `"SmoothPlastic"`.
- `Spokes` - 8 pale radial bars + a pale hub on each face (as the Toy Slice), `cuke_pale`.
- `Halo` - a Neon ring hugging the rim: a torus/tube around the disc's edge, radius R + 0.06,
  tube radius 0.07, in the disc's plane, 16-20 segments; `neo_purple`, `rbx_material="Neon"`,
  `emit=0.6`. It must not push the disc's lowest point below z = 0: raise the whole disc so
  the halo's lowest point is at z = 0.
- **Keep the Y-extent thin** (< 0.45 x diameter) - the halo lies in the disc plane, so it
  does not add depth.
- ~1.9 x 0.46 x 1.9. 6 parts.

### `NeonElectroCucumber` - `build_neon_electro_cucumber.py`
Tile: a green cucumber with a lighter checker of speckles, circled by two glowing cyan rings.

- `Body` - standard body with nub, `cuke_green`. `Studs` - standard speckles, `cuke_stud`.
- `Rings` - two cyan Neon tori around the body, NOT touching it: ring 1 centred at
  zf 0.36 (z 1.45), radius 1.05, tube 0.09, tilted 14 degrees about X; ring 2 at zf 0.62
  (z 2.5), radius 1.02, tube 0.09, tilted -12 degrees about X and 8 about Y. 16 segments
  round, 6 round the tube. `neo_cyan`, `rbx_material="Neon"`, `emit=0.6`. One part.
- The tile's stem is plain green: keep the standard nub on the body.
- ~2.3 x 2.3 x 4.3. 3 parts.

### `NeonGridCucumber` - `build_neon_grid_cucumber.py`
Tile: a see-through cucumber drawn in glowing wireframe: cyan lines running lengthwise, and
magenta-purple rings running round it, over a dark, empty-looking body. A lime stem on top
and a little lime tip at the bottom.

- `Body` - standard body, **no nub**, dark and translucent: `neo_night`,
  `rbx_material="Glass"`, `transparency=0.35`.
- `GridLong` - 8 cyan lines along the body, one on each facet EDGE (between facets, angle
  = facet angle + 22.5), from zf 0.03 to zf 0.97, 0.07 wide, 0.03 proud: `D.surface_line`
  with `[(zf, angle) ...]` points; `neo_cyan`, Neon, emit 0.6.
- `GridRings` - 6 magenta rings round the body at zf 0.16, 0.30, 0.44, 0.58, 0.72, 0.86
  (each a closed `D.surface_line` loop of 9 points: angles 0..360 step 45, 0.07 wide,
  0.035 proud so they sit over the long lines); `neo_purple`, Neon, emit 0.6.
- `Lime` (one part, `neo_lime`, Neon, emit 0.6): a stem nub 0.30 x 0.40 on top, and a tip
  0.20 x 0.20 x 0.10 at z 0 .. 0.10 under the bottom centre. Lift the body 0.06 so it rests
  on the tip and the lowest point stays z = 0.
- ~1.5 x 1.5 x 4.5. 4 parts.

### `NeonHologramCucumber` - `build_neon_hologram_cucumber.py`
Tile: a translucent glowing-blue cucumber hovering above a dark hexagonal pedestal whose
sides carry cyan light strips and whose top glows; small glowing blue squares float round it.

- `Pedestal` - a 6-sided prism r 1.35 (flat-to-flat ~2.34), z 0 .. 0.42, dark `neo_night`,
  `"Metal"`; a slightly smaller top plate (r 1.22, z 0.42 .. 0.50) `neo_night_lt`
  (part `PedestalTop`, `"SmoothPlastic"`).
- `Strips` - a cyan Neon light strip inset on each of the 6 side faces (0.9 long x 0.12
  tall, 0.03 proud, at z 0.21), plus a thin cyan Neon ring (r 1.18, tube 0.05) on the top
  plate's edge; `neo_cyan`, Neon, emit 0.6.
- `Holo` - the cucumber: standard body with nub, base at z 0.78 (floating 0.28 above the
  top), leaning up to 10 degrees about Y; `neo_holo`, `rbx_material="Neon"`,
  `transparency=0.35`, emit 0.5.
- `ScanLines` - 5 thin lighter rings round the hologram (surface lines at zf 0.2 .. 0.8,
  0.05 wide) + 4 lengthwise lines, `neo_holo_lt`, Neon, `transparency=0.3`. Transform with
  the same lean as `Holo`.
- `Pixels` - 9 small floating cubes (0.16 .. 0.26) scattered round the hologram between
  z 1.4 and z 4.2, 1.1 .. 1.6 from its axis, deterministic (`random.Random(seed)`),
  `neo_holo_lt`, Neon, emit 0.6. They float: that is the point.
- ~3.0 x 3.0 x 4.9. 6 parts.

### `NeonPalm` - `build_neon_palm.py`
Tile: a palm tree with a dark indigo segmented trunk ringed by three glowing magenta bands,
standing on a small dark disc with a glowing magenta rim; a crown of blocky fronds, some
solid green, some glowing cyan, some green with glowing magenta tips; a cluster of green
coconut lumps under the crown.

Read `build_desert_palm.py` first: same skeleton (`D.palm_frond`), different colours.

- `Base` - a dark 12-gon disc r 1.15 x 0.18 (z 0 .. 0.18), `neo_night`. `BaseGlow` - a
  magenta Neon ring on its rim (tube 0.06), part `Magenta` (see below).
- `Trunk` - segmented, gently curving (lean ~6 degrees toward +Y/-X), 6-8 stacked
  tapering 8-sided segments from r 0.52 at the base to r 0.34 under the crown, top at
  z ~9.2; `neo_trunk`.
- `Magenta` - three glowing magenta bands round the trunk at z 2.0, 4.3, 6.6 (0.16 tall,
  0.04 proud of the trunk surface) + the base rim ring; `neo_magenta`, Neon, emit 0.6.
- `Fronds` - 8 fronds round the crown top (z ~9.3), 3.4 long, drooping:
  3 solid green (`neo_green`, part `FrondsGreen`), 3 cyan Neon (`neo_cyan`, part
  `FrondsCyan`, emit 0.6), 2 green with the OUTER 45% magenta Neon (split each frond into
  an inner green piece in `FrondsGreen` and an outer tip in `Magenta`).
- `Coconuts` - 4-5 green bevelled lumps (0.55) hanging under the crown, `neo_green_dk`.
- 11-13 tall, crown <= 7.5 wide. <= 4500 tris, <= 8 parts.

### `NeonTree` - `build_neon_tree.py`
Tile: a blocky tree whose crown is a cluster of cubes: glowing cyan cubes, glowing magenta
cubes, and solid green cubes. Dark indigo blocky trunk with two short branches and two neon
bands (cyan upper, magenta lower), on a flat dark square base with a glowing purple edge.

Read `build_cucumber_tree.py` first: the same tree recipe.

- `Base` - flat dark square plinth 2.6 x 2.6 x 0.22, `neo_night`. `BaseGlow` - a thin
  0.06 frame round its top edge, `neo_purple`, Neon, emit 0.6.
- `Trunk` - `D.blocky_trunk` from z 0.22 to z 6.0, w 1.1 -> 0.8, + 2 short `branch_box`
  arms up-outward into the crown; `neo_trunk`.
- Bands: a cyan Neon band at z 3.9 and a magenta one at z 2.4 (0.14 tall, 0.04 proud).
  The cyan band goes in the `Cyan` part, the magenta band in the `Magenta` part, together
  with the glowing cubes of the same colour.
- Crown: ~11 cubes 1.5 .. 2.1 on a side, clustered between z 5.5 and z 11.2, <= 7 wide:
  4 cyan (part `Cyan`, `neo_cyan`, Neon, emit 0.55), 3 magenta (part `Magenta`,
  `neo_magenta`, Neon, emit 0.55), 4 green (part `CubesGreen`, `neo_green`,
  `"SmoothPlastic"`). Only the green cubes carry the set's speckles (`D.box_studs`,
  part `CubeStuds`, `neo_green_dk`); the glowing cubes stay plain. The glowing cubes sit on
  the OUTSIDE of the cluster (they are what you see first in the tile) and a cyan cube
  crowns the top.
- 11-12 tall. <= 4500 tris, <= 8 parts.

### `NeonCyberCucumber` - `build_neon_cyber_cucumber.py`
Tile: a green cucumber wearing lavender VR goggles: a chunky visor on the front with two
dark lenses that glow pink, a strap round the body, and a cyan light on the strap's side.

- `Body` - standard body with nub, `cuke_green`. `Studs` - standard speckles, `cuke_stud`,
  skipping the band the goggles cover (zf 0.60 .. 0.76).
- `Goggles` - the strap: an 8-sided band hugging the body at zf 0.62 .. 0.74, 0.10 proud,
  tilted 6 degrees about X (lower at the front); the visor: a `beveled_box` 1.30 wide x 0.62
  tall x 0.40 deep on the front (+Y), its back face on the skin, same tilt; `neo_goggle`.
  A darker frame line round the visor front (a 0.05 inset rim) in `neo_goggle_dk`
  (part `GoggleRim`).
- `Lenses` - two dark lenses 0.46 x 0.34 set 0.03 proud of the visor front, `neo_lens`.
  `LensGlow` - a pink Neon bar across the lower half of each lens (0.38 x 0.10, 0.02 proud
  of the lens), `neo_pink`, Neon, emit 0.6.
- `SideLight` - a cyan Neon block 0.18 x 0.34 x 0.26 on the strap at the body's
  **negative-x** side (the tile's right), `neo_cyan`, Neon, emit 0.6.
- ~1.7 x 1.9 x 4.3. <= 8 parts.

---

## Rarity order (game data, not modelling)

The sheet lists each biome common -> rare, left to right, exactly like the other biomes'
pools (`CucumberSpawner` RAW): slice first (the sliced slot), then the commons, and the
rarest last. The rarest is the biome's landmark "payday" the spawner always keeps one of.

| weight | Toyland | Neon |
|---|---|---|
| 25 (sliced) | Toy Slice | Neon Slice |
| 53 | Lego Cucumber | Electro Cucumber |
| 25 | Jack-in-the-Box Cucumber | Neon Grid Cucumber |
| 12 | Toy Rocket Cucumber | Hologram Cucumber |
| 6 | Pinwheel Plant | Neon Palm |
| 3 | Building Block Tree | Neon Tree |
| 1 (landmark) | Toy Train Cucumber | Cyber Cucumber |
