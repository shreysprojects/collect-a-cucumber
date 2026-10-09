# Cucumber set - build contract

**57 models across 8 biomes**, built in Blender through `cucumberlib.py`, meant to read as
**one coherent chunky toy set**: a low-poly cucumber world, Roblox toy-plastic, every model
speckled with the same little raised squares.

| Biome | Models |
|---|---|
| grass (6) | `SlicedCucumber` `SlicedCucumberStack` `Cucumber` `FloweredCucumber` `VinedCucumber` `CucumberTree` |
| desert (7) | `DesertSunDriedSlice` `DesertPricklyCucumber` `DesertSunBakedCucumber` `DesertWrappedCucumber` `DesertCactusCucumber` `DesertPalm` `DesertSandstoneTree` |
| volcano (7) | `VolcanoMoltenSlice` `VolcanoCharredCucumber` `VolcanoMoltenCucumber` `VolcanoFlameCucumber` `VolcanoObsidianTree` `VolcanoVolcanoCucumber` `VolcanoMagmaTree` |
| narmek (8) | `NarmekMoonSlice` `NarmekMeteorCucumber` `NarmekPlanetSlice` `NarmekAstronautCucumber` `NarmekNeonAlienCucumber` `NarmekMoonTree` `NarmekAlienTree` `NarmekGalaxyTree` |
| samurai (7) | `SamuraiKatanaCucumber` `SamuraiBambooCucumber` `SamuraiLanternCucumber` `SamuraiBambooGrove` `SamuraiToriiGate` `SamuraiSakuraTree` `SamuraiSlicedCucumber` |
| farm (6) | `FarmCucumberBasket` `FarmMuddyCucumber` `FarmCrateCucumber` `FarmWindmillPlant` `FarmHayBale` `FarmCucumberTree` |
| snow (8) | `SnowFrozenSlice` `SnowSnowcapCucumber` `SnowSnowballSlice` `SnowCrystalCucumber` `SnowFrozenCucumber` `SnowSnowTree` `SnowIcicleTree` `SnowFrozenTree` |
| underwater (8) | `UnderwaterBubbleSlice` `UnderwaterSeaweedCucumber` `UnderwaterShellSlice` `UnderwaterCoralCucumber` `UnderwaterPearlCucumber` `UnderwaterKelpTree` `UnderwaterBubbleTree` `UnderwaterCoralTree` |

---

## Space & scale

| | |
|---|---|
| Units | 1 Blender unit = 1 Roblox stud |
| Up axis | **+Z**, ground plane at **z = 0** |
| Facing | every model faces **+Y** - the side the render camera and the player see |
| Centring | centred on **x = 0, y = 0** unless the brief says otherwise |
| Roblox export | `(x, y, z)_rbx = (x, z, −y)_blender` (the lib handles it - don't pre-rotate) |
| Reference | an R15 avatar is **5 studs tall**; it stands beside every hero render |

**Standard sizes - do not drift from these**, they are what makes the set look like a set:

| Archetype | Size |
|---|---|
| upright cucumber (`D.CUKE_H` × `D.CUKE_R`) | **4.0 tall, r 0.68** (1.36 across) |
| slice disc (`D.SLICE_R` / `D.SLICE_T`) | **r 0.80, 0.42 thick** |
| a slice GROUP | ≈ 3.2 × 2.4 × 1.8 |
| a tree | **11–13 tall**, crown ≤ 7 wide |
| torii gate | ≈ 11 wide × 10 tall |
| bamboo grove | ≈ 9 tall |
| windmill | ≈ 12 tall |
| hay bale | ≈ 4.6 × 3.0 × 3.0 |
| basket / crate | ≈ 3.6 wide × 3.4 tall |

> **The +X / screen-left trap.** Renders look at the model from the +Y side, so the camera
> looks down −Y and **+X appears on the LEFT of the frame**. Anything "on the right as I
> face it" must be built at **negative x**. Symmetric models don't care; a katana, an arm,
> a hanging tag does.

---

## Style

Chunky, low-poly, **flat shaded**, readable in silhouette from 40 studs away. Large forms
first, one or two levels of detail on top. Prefer `beveled_box` over raw cubes.

**The one thing that ties the whole set together is the raised square speckle** - the little
light squares dotted over every cucumber, every crown cube, every slice rim. Never leave a
model without them unless its brief says so. `D.cuke_studs` / `D.box_studs` / `D.slice_studs`
place them; `D.stud_patch` does one by hand.

Two adjacent parts must differ in **value**, not only hue. Aim for **3–6 distinct colours
per model**; more reads as noise.

Every part carries a Roblox material: `"Grass"`/`"LeafyGrass"` on foliage, `"Wood"`/
`"WoodPlanks"` on timber, `"Slate"`/`"Sandstone"`/`"Rock"`/`"Basalt"` on stone,
`"Ice"`/`"Glacier"`/`"Snow"` on the snow biome, `"Neon"` on anything that glows,
`"Metal"`/`"Foil"` on steel, `"Fabric"`/`"Leather"` on cloth, `"Glass"` on bubbles,
`"SmoothPlastic"` on the cucumber flesh itself.

### Transparency and glow

- `new_obj(..., transparency=t)` is the **Roblox** convention: `0` solid, `1` invisible.
  Bubbles **0.45–0.6**, ice **0.15–0.3**.
- `rbx_material="Neon"` makes a part emissive; pass `emit=` to tune, **0.6–1.5 only**.
  Above ~1.6 the render clips to white and the colour is lost.

---

## Palette

`D.C("key")` returns the hex and throws on a typo. All 79 `proplib` keys are still there
(`wood_mid`, `stone_dark`, `gold`, `neon_cyan`, …) plus this set's own:

```
cuke_green cuke_mid cuke_dark cuke_deep cuke_stud cuke_stud_dk cuke_pale cuke_seed cuke_stem

des_olive des_olive_dk des_baked des_baked_dk des_crack des_spike des_spike_dk
des_bandage des_bandage_d des_sand des_stone des_stone_dk des_trunk des_trunk_dk
des_frond des_frond_dk des_coconut des_flower des_flower_c

vol_char vol_char_lt vol_char_dk vol_lava vol_lava_hot vol_lava_core vol_ember
vol_obsidian vol_ash

nar_moon nar_moon_dk nar_moon_lt nar_glow_grn nar_meteor nar_meteor_lt nar_glow_pur
nar_planet_b nar_planet_g nar_planet_c nar_suit nar_suit_sh nar_orange nar_visor
nar_visor_lt nar_metal nar_alien_grn nar_gem nar_gem_dk nar_ufo nar_ufo_dk nar_teal
nar_teal_dk nar_amber nar_amber_dk nar_galaxy nar_galaxy_dk nar_galaxy_c nar_star

sam_steel sam_hilt sam_gold sam_gold_dk sam_ribbon sam_ribbon_dk sam_bamboo sam_bamboo_dk
sam_stalk sam_stalk_dk sam_leaf sam_roof sam_roof_lt sam_warm sam_paper sam_ink sam_torii
sam_torii_dk sam_sakura sam_sakura_dk sam_bark sam_bark_dk sam_rock sam_rock_dk

farm_basket farm_basket_d farm_crate farm_crate_d farm_mud farm_mud_lt farm_hay
farm_hay_dk farm_strap farm_cream farm_red farm_wood farm_wood_dk farm_bark farm_bark_dk

snow_white snow_shadow snow_ice snow_ice_lt snow_ice_dk snow_crystal snow_pine
snow_pine_dk snow_bark snow_bark_dk

sea_bubble sea_bubble_lt sea_weed sea_weed_dk sea_shell sea_shell_dk sea_shell_in
sea_coral_p sea_coral_pd sea_coral_r sea_coral_o sea_pearl sea_pearl_sh sea_kelp
sea_kelp_dk sea_stalk sea_stalk_dk sea_deep sea_deep_dk
```

A literal hex string is legal when nothing fits, but prefer a key.

---

## `cucumberlib` API

`D` is the module. It re-exports **everything in `props/proplib.py`** - `box`, `cube`,
`beveled_box`, `cyl`, `cone`, `spike`, `pyramid`, `uvsphere`, `ico`, `torus`, `tube`,
`rock`, `stone_block`, `prism`, `wedge`, `lathe`, `ngon_face`, `sag_sheet`, `foliage`,
`slat_run`, `rope`, `coil`, `barbed_wire`, `stroke_text`, the profile helpers
(`rounded_rect_pts`, `arc_pts`, `ngon_pts`, `star_pts`, `teardrop_pts`, `chevron_pts`,
`ring_positions`, `grid_positions`, `catenary_pts`, `helix_pts`), the transforms
(`rot_euler`, `place`, `aim`, `xform`, `translate`, `mirror_x`) and `report` / `bounds` /
`manifest`. **Their full reference is `../props/PROPS.md`** - read it for anything below.

Every primitive **appends into an existing bmesh** and returns its new verts, so one bmesh
can hold many primitives that become one object.

### The cucumber body

- `D.CUKE_H` = 4.0, `D.CUKE_R` = 0.68, `D.CUKE_SEGS` = 8, `D.CUKE_PROFILE`,
  `D.CUKE_PROFILE_STUB` (a squatter berry shape for tree fruit and basket fruit).
- `D.cuke_body(bm, h=, r=, profile=None, segs=8, phase=None, matrix=None, nub=None)`
  - the pillar. `nub=(width, height)` adds the stem cube on top; `nub=True` is the default
  one; `nub=None` leaves it off. `matrix=D.place(loc, rot)` puts it somewhere else.
- **Facet 1 faces +Y.** Facet centres go anticlockwise seen from above: 0 = +45°, 1 = +Y,
  2 = 135°, 3 = −X, 5 = −Y (the back), 7 = +X.
- `D.cuke_radius(zf, profile=None)` → radius FRACTION at height fraction `zf`.
- `D.cuke_point(h=, r=, zf=, angle_deg=, profile=None, offset=0.0)` → a point on the skin
  (+Y is 90°). `D.cuke_normal(angle_deg)` → its outward normal.
- `D.cuke_facet_point(h=, r=, zf=, facet=, ...)` → `(point, normal)` at a facet centre.
- `D.cuke_facet_angle(facet, segs=8)` → radians.

### Speckles (the set's signature)

- `D.stud_patch(bm, point, normal, size=0.26, rise=0.055, bevel=0.03, aspect=1.0, spin=0.0)`
  - one raised square, sitting flat AND upright on the surface.
- `D.cuke_studs(bm, h=, r=, rows=6, per_row=3, z0=0.14, z1=0.88, size=0.26, rise=0.055,
  seed=1, skip=0.0, matrix=None, slots=None)` - scatter them over a body. Snapped to facet
  centres so they lie flat. `slots=[(zf, facet), ...]` places them by hand.
- `D.cuke_stud_slots(rows, per_row, z0, z1, ...)` → the `(zf, facet)` list, to edit.
- `D.box_studs(bm, lo, hi, faces=("+x","-x","+y","-y","+z"), per_face=3, grid=None,
  size=0.3, rise=0.05, seed=1, margin=0.26)` - scatter them over a box's faces.
  `grid=(2,2)` lays them on a lightly jittered lattice, which reads better on crown cubes.
- `D.surface_frame(normal, up=(0,0,1))` - the 4×4 that keeps a square upright on a surface.

### The slice

- `D.slice_disc(bm, center=(0,0,0), radius=0.80, thick=0.42, segs=10, matrix=None)`
  - the dark rim: a short 10-sided drum whose axis is LOCAL Z, so it lies flat like a coin.
- `D.slice_face(bm, ..., inset=0.12, proud=0.02, both=True)` - the pale cut face(s).
- `D.slice_seeds(bm, ..., n=5, size=0.135, ring=0.40, centre_seed=True)` - the pips.
- `D.slice_studs(bm, ..., n=6, size=0.18)` - the speckles on the RIM.
- `D.slice_lay(loc, tilt_deg=0, spin_deg=0)` - matrix for a disc lying flat.
- `D.slice_stand(loc, lean_deg=0, turn_deg=0)` - matrix for one standing, cut face to +Y.
  Positive `lean_deg` tips its top away from the viewer.

**Build a slice group as four objects**, not four-objects-per-disc: loop the discs into one
bmesh per material (`Rims`, `RimStuds`, `Faces`, `Seeds`). Pass the SAME `radius`/`thick`/
`matrix` to all four calls for a given disc.

### Trees

- `D.stepped_base(bm, top_w, h, steps=3, grow=1.32, bevel=0.06, center=(0,0))` - the
  stacked plinth every tree stands on, widest at the bottom.
- `D.blocky_trunk(bm, z0, z1, w0, w1=None, blocks=3, bevel=0.06, center=(0,0), twist=0.0)`
  - stacked boxes tapering up.
- `D.branch_box(bm, a, b, w0, w1=None, bevel=0.0)` - a tapered square-section beam.
- `D.crown_cube(bm, center, size, bevel=0.11, rot=None)` - one foliage cube.
- `D.crown_cluster(bm, center, size, spots, bevel=0.11)` - several, `spots` =
  `[(dx, dy, dz)]` or `[(dx, dy, dz, size_multiplier)]`.

### Everything else

- `D.ribbon(bm, frames, width, thick, taper=None)` - loft a strip along
  `[(point, out_normal), ...]`.
- `D.wrap_ribbon(bm, h=, r=, z0=, z1=, turns=, width=, thick=, phase_deg=, offset=0.06,
  taper=None)` - a band spiralling up a cucumber: the vine, the bandage, the flame.
- `D.wrap_frames(...)` - the same frames, if you want to loft something else along them.
- `D.spiral_pts(center, r0, r1, turns, n, plane="XZ")` - a flat spiral (curled tendril).
- `D.leaf_blade(bm, length, width, thick, matrix=None, ridge=0.06)` - a faceted leaf
  pointing along +Y in the XY plane; place it with `matrix=D.place(loc, D.rot_euler(...))`.
- `D.surface_line(bm, [(zf, angle_deg), ...], h=, r=, width=, rise=)` - a strip laid along
  the skin: lava cracks, veins, mud runs, lightning.
- `D.crack_lines(bm, [[(zf, ang), ...], ...], h=, r=, width=, rise=)` - several at once.
- `D.spike_ring(bm, h=, r=, rows=, per_row=, z0=, z1=, length=, base_r=, droop=0.0)`
  - spikes standing out of a body, snapped to facets.
- `D.snow_slab(bm, lo, hi, thick=0.26, overhang=0.06, drips=3, drip_len=0.34,
  sides=("-y",))` - a drift on top of a box with drips down the front.
- `D.cuke_snow_cap(bm, h=, r=, thick=0.34, drips=4, top_zf=0.86)` - a cap on a cucumber.
- `D.icicle(bm, top, length, radius)` / `D.icicle_row(bm, a, b, count, length, radius)`.
- `D.crystal_spire(bm, base, height, radius, segs=6, taper=0.58, tip=0.34, rot=None)`.
- `D.gem(bm, center, radius=0.22, segs=6, squash=1.25, rot=None)` - a faceted jewel lump.
- `D.palm_frond(bm, base, yaw_deg, pitch_deg, length, width, thick, droop, teeth=0.26)`
  - a drooping serrated frond, swung around Z by `yaw_deg`.
- `D.coral_arm(bm, base, direction, length, radius, depth=2, branches=2, spread=42)`.
- `D.disc_canopy(bm, center, radius, thick, rim=0.20, segs=12, dome=0.0)` - a saucer.
- `D.weave_panel(bm, lo, hi, rows, cols, depth=0.10, axis="y")` - basket weave.
- `D.kanji_samurai(bm, origin, size, thick, face="+y")` - 侍 as box strokes in the XZ plane.

---

## Hard rules

1. **No `bpy.ops`, ever** - only `cucumberlib` primitives and `bmesh`.
2. Every mesh is finished with `D.new_obj(part_name, bm, c, hex, rbx_material=...)`.
3. **Deterministic**: `random.Random(seed)` only - never bare `random.*`, never time/date.
4. **Nothing below `z = 0`** unless `NOTES` explicitly says the model needs a pit.
5. **Merge everything that shares a colour + material into ONE bmesh / ONE object.**
   Target **4–8 parts per model**; 12 is the hard ceiling.
6. Tri budget: **≤ 2200 tris** for a cucumber or a slice group, **≤ 4500** for a tree or a
   gate. `D.report()` prints the count. Speckles are ~48 tris each - 20 is plenty.
7. Distinct part names, no spaces. The lib prefixes them with the collection name.
8. `build(D)` must be **idempotent** - `D.clear_collection(COLLECTION)` on the first line
   guarantees it. Return the collection.
9. The script must pass `py dryrun.py build_<yours>.py` with no errors.

---

## Module shape

One file per model, `build_<snake_case>.py`, next to `cucumberlib.py`:

```python
"""One-line description of the model."""
import bmesh, math

COLLECTION = "DesertPricklyCucumber"
NOTES = "What it is, its footprint, what sits where - the installer reads this."


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    bm = bmesh.new()
    D.cuke_body(bm, h=D.CUKE_H, r=D.CUKE_R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")
    # ... more parts ...
    return c
```

`PIVOTS` / `STATES` (optional) carry rig data into the manifest, same as the prop set.

---

## Worked examples - read these first

`build_cucumber.py`, `build_sliced_cucumber.py` and `build_cucumber_tree.py` are already
written and built. They are the three archetypes; **every other model is a variation on
one of them.** Read the one that matches yours before writing a line.

### The upright-cucumber recipe

```python
H, R = D.CUKE_H, D.CUKE_R
bm = bmesh.new()
D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

bm = bmesh.new()
D.cuke_studs(bm, h=H, r=R, rows=7, per_row=3, z0=0.11, z1=0.90, size=0.28, seed=7)
D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")
```

Then add whatever this biome puts on it - spikes, a wrap, cracks, a snow cap, a hat.

### The slice-group recipe

Four discs, four objects; see `build_sliced_cucumber.py` for the exact loop.

### The tree recipe

`stepped_base` → `blocky_trunk` → 3–4 `branch_box` forks → `crown_cluster` of 5–6 cubes →
`box_studs` on each cube → optional hanging fruit. See `build_cucumber_tree.py`.

---

## Checking your work

```bash
cd C:/Users/shrey/OneDrive/Documents/RobloxGames/cucumbers
py dryrun.py build_<yours>.py
```

`dryrun.py` runs `build()` **without Blender**: it catches syntax errors, API typos, bad
palette keys, bad hex/material/transparency, duplicate part names, a missing
`clear_collection`, geometry below the ground plane and gross scale mistakes. Its bounding
box ignores `rot=` / `matrix=` transforms, so:

- a model that places things with matrices (any slice group) will report a wrong bbox and
  may warn about `min_z` - **that warning is expected there and is not a failure**;
- the real build in Blender is the source of truth and is run centrally.

**You must not run Blender.** Concurrent `execute_blender_code` calls share one socket and
corrupt each other. Write the script, dry-run it, and hand it over.

---

# The 57 briefs

Each brief gives the target size, the parts, and what must be recognisable. Colours are
palette keys. Where a brief says "standard body" it means `h=D.CUKE_H, r=D.CUKE_R` with a
`(0.30, 0.30)` nub; where it says "standard speckles" it means
`rows=7, per_row=3, z0=0.11, z1=0.90, size=0.28`.

---

## grass

### `Cucumber` - `build_cucumber.py` - DONE
The reference silhouette. Standard body in `cuke_green`, standard speckles in `cuke_stud`.
2 parts.

### `SlicedCucumber` - `build_sliced_cucumber.py` - DONE
Four discs: one big standing, one tipped against it, two lying flat. 4 parts.

### `CucumberTree` - `build_cucumber_tree.py` - DONE
12 tall. Brown blocky trunk, 4 forks, 6 speckled green crown cubes, 4 hanging cucumbers.

### `SlicedCucumberStack` - `build_sliced_cucumber_stack.py`
**≈ 1.9 × 1.9 × 2.7.** A neat stack of **four** discs lying flat, one on top of another,
each rotated a little about Z (say 0°, 22°, −16°, 38°) and offset sideways by 0.06–0.12 so
the stack leans and you can see every rim. Bottom disc r 0.82, each one above ~0.97× the
one below. Standard slice colours: `cuke_dark` rims, `cuke_stud` rim speckles, `cuke_pale`
faces, `cuke_seed` pips. Only the TOP disc's pips really show, but build them on both faces
of every disc anyway (`both=True`) - they peek out between the discs, which is what the
reference shows. 4 parts.

### `FloweredCucumber` - `build_flowered_cucumber.py`
**≈ 2.8 × 1.9 × 4.6.** Standard body + standard speckles in `cuke_green` / `cuke_stud`.
Out of the body's upper right (NEGATIVE x - remember the screen-left trap) a `cuke_stem`
stem arcs up and out: a `D.tube` along 4–5 points from about `(−0.3, 0.1, 2.9)` up to
`(−1.25, −0.15, 3.9)`, radius 0.09 tapering to 0.06. At its end a **white five-part flower**:
four `flower_white` petals as flat rounded boxes arranged in a `+` (use `D.ring_xy(4, 0.30)`
for their centres) standing in the XZ-ish plane facing +Y, plus a `petal_yellow` cube centre
0.22 across. Then **two or three `leaf_dark` leaves** (`D.leaf_blade`, length 0.85, width
0.55) on short stems off the same arc, one pointing up-left, one down-right, each tilted
~25° out of vertical so their facets catch light. 6 parts: Body, Studs, Stem, Petals,
FlowerCentre, Leaves.

### `VinedCucumber` - `build_vined_cucumber.py`
**≈ 2.4 × 2.0 × 4.7.** Standard body + speckles. A `stem_green` **vine spirals up it**:
`D.wrap_ribbon(bm, turns=1.9, z0=0.10, z1=0.88, width=0.34, thick=0.15, phase_deg=-30,
offset=0.05)`. At the top the vine leaves the body and **curls into a tendril**: a
`D.tube` along `D.spiral_pts(center=(-0.55, -0.1, 4.35), r0=0.06, r1=0.34, turns=1.4,
n=14, plane="XZ")` with radii tapering 0.10 → 0.05, joined to the top of the wrap by a
short arc. Two `leaf_dark` `leaf_blade`s off the vine, one at mid height pointing up-left,
one lower pointing right. 5 parts: Body, Studs, Vine, Tendril, Leaves.

---

## desert

### `DesertSunDriedSlice` - `build_desert_sun_dried_slice.py`
The `SlicedCucumber` arrangement (copy its DISCS table and loop) **recoloured sun-dried**:
rims `des_olive_dk`, rim speckles `des_olive`, faces `des_sand`, pips `des_baked`. Material
`"Sand"` on the faces, `"SmoothPlastic"` elsewhere. Discs a touch thinner (×0.9 thickness) -
they have dried out. 4 parts.

### `DesertPricklyCucumber` - `build_desert_prickly_cucumber.py`
**≈ 2.1 × 2.1 × 4.5.** Standard body in `cuke_green` with `des_olive` speckles (`rows=6,
per_row=2, size=0.24`) - the skin still shows. Over it,
`D.spike_ring(bm, rows=5, per_row=3, z0=0.14, z1=0.88, length=0.34, base_r=0.15,
segs_spike=4, droop=-0.15)` in `des_spike` - hard little cream pyramids pointing slightly
UP and out, 15 of them. 3 parts: Body, Studs, Spikes.

### `DesertSunBakedCucumber` - `build_desert_sun_baked_cucumber.py`
**≈ 1.5 × 1.5 × 4.4.** A body in drab `des_baked` (olive-khaki, clearly drier than
`cuke_green`), speckles in `des_baked_dk` (DARKER than the body - baked, not fresh).
Its signature is **dark cracks**: 3 or 4 `D.surface_line` runs in `des_crack`, width 0.075,
rise 0.015, each a short jagged polyline of 4–6 `(zf, angle_deg)` points - e.g. an X across
the front facet around `zf 0.45–0.65, angle 70–110`, a vertical split near `angle 40`, a
short fork near `angle 130`. Keep them on the front half (angles 30°–150°) so they read.
4 parts: Body, Studs, Cracks, and a `des_baked_dk` nub-and-shoulder piece if you want a
fifth.

### `DesertWrappedCucumber` - `build_desert_wrapped_cucumber.py`
**≈ 1.9 × 1.9 × 4.4.** Standard body in `cuke_green` + `cuke_stud` speckles - but the body
is mostly HIDDEN by **three broad cream bandage bands** spiralling up it, like a mummy wrap:
`D.wrap_ribbon` three times with `width=0.62, thick=0.12, turns=1.15`, at `z0/z1` of
(0.08, 0.42), (0.34, 0.68) and (0.60, 0.94), each with a different `phase_deg` (−20, 100,
220) so they overlap slightly and read as one continuous wrap. Bands in `des_bandage`, with
a second object of thin `des_bandage_d` edge lines is optional. Speckles only where the
body shows (use `slots=` or `skip=0.5`). 4 parts.

### `DesertCactusCucumber` - `build_desert_cactus_cucumber.py`
**≈ 3.4 × 1.6 × 4.6.** A **saguaro**: the standard body, plus **two arms**. Each arm is a
short horizontal `cuke_body` (h 0.75, r 0.30) coming out of the side at `zf ≈ 0.45` then an
upright `cuke_body` (h 1.25, r 0.30) elbowing up - build each with
`matrix=D.place(loc, D.rot_euler(...))`. Left arm (POSITIVE x, screen-left) rises higher
than the right. Body and arms `cuke_green`, speckles `cuke_stud` on body and arms.
`des_spike` spikes over the whole thing (`spike_ring`, `rows=4, per_row=2, length=0.24,
base_r=0.11`) plus a few by hand on the arms. On top a **yellow flower**: five
`des_flower` petals (`D.ring_xy(5, 0.26)` centres, flat rounded boxes tilted 25° up from
horizontal) round a `des_flower_c` brown centre cube 0.2 across, sitting on the head at
z ≈ 4.1. 6 parts: Body, Arms, Studs, Spikes, Petals, FlowerCentre.

### `DesertPalm` - `build_desert_palm.py`
**≈ 6.5 × 6.5 × 12.** A **stepped tan trunk**: `stepped_base(top_w=1.5, h=1.5, steps=2,
grow=1.4)` in `des_trunk_dk`, then **five stacked tapering blocks** up to z ≈ 8.2 in
`des_trunk` - build them by hand as 5 `beveled_box`es, each narrower and slightly offset,
so the trunk reads as chunky segments, not a smooth cone (that stepping is the reference's
signature). Bottom block 1.35 across, top 0.85. At the top, **seven `des_frond` palm
fronds** (`D.palm_frond`, length 2.7, width 0.66, droop 1.0, pitch 22, teeth 0.26) at
`yaw_deg` every ~51°, their bases at z ≈ 8.3. Two `des_coconut` coconuts (`uvsphere`
r 0.30, segs 8, rings 5) tucked under the crown at z ≈ 8.0. 5 parts: Base, Trunk, Fronds,
Coconuts, and `des_frond_dk` for two or three of the back fronds so the crown has depth.

### `DesertSandstoneTree` - `build_desert_sandstone_tree.py`
**≈ 6.5 × 5.5 × 11.5.** The `CucumberTree` silhouette rebuilt in **stone**: a wide
`stepped_base(top_w=1.6, h=1.9, steps=3, grow=1.34)` in `des_stone_dk`, a `blocky_trunk` of
stacked sandstone blocks in `des_stone` to z ≈ 6.2, three or four `branch_box` forks in
`des_trunk_dk` (brown, so the branches read against the stone), and a crown of **five
sandstone cubes** in `des_stone` with `des_stone_dk` speckles. Materials `"Sandstone"` on
the stone, `"Wood"` on the branches. No hanging fruit. 5 parts.

---

## volcano

### `VolcanoMoltenSlice` - `build_volcano_molten_slice.py`
The `SlicedCucumber` arrangement recoloured **molten**: rims `vol_char`, rim speckles
`vol_lava` (`rbx_material="Neon"`, `emit=1.0`), faces `vol_lava_hot` (Neon, `emit=0.9`),
pips `vol_lava_core` (Neon, `emit=1.1`). Materials: `"Basalt"` on the rims. The glow is the
point - a black rim with an orange-hot interior. 4 parts.

### `VolcanoCharredCucumber` - `build_volcano_charred_cucumber.py`
**≈ 2.1 × 2.1 × 4.5.** The `DesertPricklyCucumber` shape in charcoal: body `vol_char`
(`"Basalt"`), speckles `vol_lava` (Neon, emit 1.0, `rows=6, per_row=2, size=0.24`), and
`D.spike_ring(rows=5, per_row=3, length=0.34, base_r=0.16, segs_spike=4, droop=-0.10)` in
`vol_ember` (Neon, emit 0.9) - glowing orange pyramid spikes on a black body. 3 parts.

### `VolcanoMoltenCucumber` - `build_volcano_molten_cucumber.py`
**≈ 1.5 × 1.5 × 4.4.** Body `vol_char` (`"Basalt"`), a few `vol_lava` speckles
(`rows=5, per_row=2, size=0.26`, Neon emit 1.0), and its signature: a **web of glowing lava
cracks** over the front. Use `D.crack_lines` with 5–6 polylines in `vol_lava_core`
(Neon, emit 1.2), width 0.10, rise 0.025 - a long near-vertical spine from `zf 0.15` to
`0.85` around `angle 90`, with 4 shorter branches forking off it left and right at angles
55–130. Make them meet: the reference is a cracked-lava NETWORK, not separate scratches.
4 parts: Body, Studs, Cracks, and a `vol_lava` glow ring at the neck if you want a fifth.

### `VolcanoFlameCucumber` - `build_volcano_flame_cucumber.py`
**≈ 2.2 × 2.2 × 4.7.** Body `vol_char` with `vol_lava` speckles. Around it a **flame ribbon
spirals up**: `D.wrap_ribbon(turns=2.1, z0=0.06, z1=0.96, width=0.50, thick=0.14,
phase_deg=-50, offset=0.05, taper=(1.15, 0.55))` in `vol_lava_hot` (Neon, emit 1.2), and a
second, narrower one just inside it in `vol_lava_core` (Neon, emit 1.4) so the flame has a
hot core. Finish with 3–4 `vol_lava_core` flame licks flicking off the top of the ribbon
(small `D.spike`s or `teardrop_pts` prisms). 5 parts.

### `VolcanoVolcanoCucumber` - `build_volcano_volcano_cucumber.py`
**≈ 1.7 × 1.7 × 4.6.** Body `vol_char` + `vol_lava` speckles (`rows=6, per_row=3`). Its head
is a **crater brimming with lava that dribbles down**: a `vol_lava_core` (Neon, emit 1.3)
`D.lathe` cap over the top `zf 0.84 → 1.0` - profile going out to 1.05× the body radius,
with a dished top (run the profile out, up over the rim and back DOWN into a shallow bowl)
- plus 5 or 6 drips running down the sides, each a `D.tube` of 3 points from the rim down to
`zf 0.55–0.72`, radius 0.13 → 0.05. 4 parts: Body, Studs, LavaCap, Drips.

### `VolcanoObsidianTree` - `build_volcano_obsidian_tree.py`
**≈ 6.8 × 5.8 × 11.5.** The `CucumberTree` silhouette in **black glass**: `stepped_base` +
`blocky_trunk` + 4 `branch_box` forks all in `vol_obsidian` (`"Basalt"`,
`roughness=0.25`), crown of 5–6 cubes in `vol_char` with **`vol_lava` speckles**
(Neon, emit 1.0) - black cubes studded with glowing orange squares is exactly the
reference. No hanging fruit. 4 parts.

### `VolcanoMagmaTree` - `build_volcano_magma_tree.py`
**≈ 6.8 × 5.8 × 11.8.** Same skeleton as `VolcanoObsidianTree` but **veined**: trunk and
branches `vol_char`, crown cubes `vol_char`, and then a whole object of `vol_lava_core`
(Neon, emit 1.3) glow lines - thin `beveled_box` strips running UP the trunk's corners and
along the top edges of the branches, plus `box_studs` on the crown cubes in `vol_lava_hot`
(Neon, emit 1.1) at `size=0.5` so the cubes read as cracking open. The tree should look lit
from inside. 5 parts: Base, Trunk, Crown, Veins, CrownGlow.

---

## narmek

### `NarmekMoonSlice` - `build_narmek_moon_slice.py`
The `SlicedCucumber` arrangement as **moon rock**: rims `nar_moon_dk`, rim speckles
`nar_moon`, faces `nar_moon_lt`, pips `nar_moon_dk`. Materials `"Rock"` / `"Concrete"`.
Then the one bright note: on the big standing disc's front face a single **glowing green
square** - one `D.stud_patch` in `nar_glow_grn` (Neon, emit 1.1), `size=0.26`, placed on the
face instead of one of the pips. 5 parts.

### `NarmekMeteorCucumber` - `build_narmek_meteor_cucumber.py`
**≈ 2.0 × 2.0 × 4.5.** Body `nar_meteor` (dark purple, `"Rock"`), speckles `nar_meteor_lt`.
Stuck all over it, **faceted rock shards**: 10–12 `D.gem(radius 0.20–0.30, segs=6,
squash=1.0)` in `nar_meteor_lt`, placed on facet points with a random `rot` so they jut out
at angles. Down the front, one **bright purple lightning crack**: a single `D.surface_line`
in `nar_glow_pur` (Neon, emit 1.3), width 0.11, whose `(zf, angle)` points zig-zag -
e.g. `(0.12, 96) (0.30, 80) (0.45, 100) (0.62, 82) (0.80, 98)`. 4 parts.

### `NarmekPlanetSlice` - `build_narmek_planet_slice.py`
**≈ 2.6 × 2.0 × 1.7.** NOT the usual arrangement: **three discs, and the standing one is a
round PLANET** - a `D.uvsphere(radius 0.85, segs=10, rings=7)` in `nar_planet_b` with
**green continent patches** (`nar_planet_g`) - 5 or 6 `stud_patch`es at `size=0.34–0.55`,
`aspect` 0.7–1.6, scattered over the sphere's facet points so they read as landmasses - and
`nar_planet_c` cyan speckles. In front, two ordinary flat discs, rims `nar_planet_b`,
faces `nar_planet_g`, pips `nar_planet_c`. 5 parts: Planet, Continents, PlanetStuds, Rims,
Faces (fold the pips into Faces' object if that keeps you at 5).

### `NarmekAstronautCucumber` - `build_narmek_astronaut_cucumber.py`
**≈ 1.9 × 1.7 × 5.0.** A cucumber in a **spacesuit**. Standard body in `nar_suit` (white),
with `nar_suit_sh` speckles kept sparse (`rows=4, per_row=2, size=0.22`). On the FRONT
(+Y, facet 1): a big dark **visor** - a `rounded_rect_pts` prism in `nar_visor`, 0.85 wide
× 0.62 tall, curved to sit on the body at `zf ≈ 0.74`, with a thin `nar_visor_lt` highlight
bar across its top left. Below it a `nar_metal` **chest control box** 0.55 × 0.34 with an
`nar_orange` button and two tiny `nar_glow_grn` (Neon) lights. Two `nar_orange` stripe bands
round the body at `zf 0.30` and `zf 0.52` (thin `wrap_ribbon`s with `turns=1.0`, or lathe
rings). On top a short `nar_metal` **antenna** (a 0.06-radius `cyl` up 0.55) ending in an
`nar_orange` ball. 7 parts.

### `NarmekNeonAlienCucumber` - `build_narmek_neon_alien_cucumber.py`
**≈ 3.2 × 1.6 × 4.4.** The `DesertCactusCucumber` shape - body plus two elbowed arms - in
bright `nar_alien_grn`, with `cuke_stud` speckles. Instead of spikes, **magenta crystal
gems**: 12–14 `D.gem(radius 0.20, segs=6, squash=1.3)` in `nar_gem` (Neon, emit 1.0) on
facet points over the body and both arms, each rotated a little. A few `nar_gem_dk` ones
among them for depth. 5 parts: Body, Arms, Studs, Gems, GemsDark.

### `NarmekMoonTree` - `build_narmek_moon_tree.py`
**≈ 6.0 × 4.5 × 11.5.** A **cratered grey stone stalk** topped by **two glowing purple
saucers**. Trunk: `stepped_base(top_w=1.7, h=1.6, steps=2, grow=1.35)` + `blocky_trunk` to
z ≈ 7.2, tapering 1.45 → 0.95, all `nar_moon` (`"Rock"`), pitted with **craters** - 6–8
`stud_patch`es in `nar_moon_dk` SUNK into the surface (`rise=-0.02, sink=0.12`) at
`size 0.3–0.5`. One short `branch_box` fork out to the right (negative x) at z ≈ 5.8.
Canopies: `D.disc_canopy(center=(0,0,7.9), radius=2.3, thick=0.42, rim=0.26, segs=12,
dome=0.35)` in `nar_ufo` on the main trunk, and a smaller one (radius 1.35) on the fork.
Under each, a `nar_glow_pur` (Neon, emit 1.2) **glow ring** - a flat `disc_canopy` of
slightly smaller radius and 0.12 thick. 5 parts.

### `NarmekAlienTree` - `build_narmek_alien_tree.py`
**≈ 6.2 × 5.2 × 11.5.** The `CucumberTree` skeleton in **alien teal**: `stepped_base` +
`blocky_trunk` + 4 forks in `nar_teal` with `nar_teal_dk` speckles on the trunk blocks.
The crown is **five ORANGE SPHERES**, not cubes: `D.uvsphere(radius 1.1–1.45, segs=10,
rings=7)` in `nar_amber`, in a loose cluster, with `nar_amber_dk` speckles
(use `stud_patch` at facet points, or `box_studs` on their bounding boxes at `margin=0.45`).
5 parts.

### `NarmekGalaxyTree` - `build_narmek_galaxy_tree.py`
**≈ 6.5 × 5.0 × 11.8.** A **purple stepped trunk** (`stepped_base` + `blocky_trunk` +
2 short forks, all `nar_galaxy`, speckles `nar_galaxy_dk`) carrying **three flat galaxy
discs**: `disc_canopy(radius 2.2 / 1.35 / 1.15, thick=0.34, rim=0.20, segs=14)` in
`nar_galaxy_dk` - one big on top at z ≈ 10.4, two smaller on the forks. On the TOP face of
each disc, a **spiral galaxy**: two arms drawn as `D.tube`s along `D.spiral_pts(center=disc
centre, r0=0.12, r1=0.9×disc radius, turns=1.05, n=14, plane="XY")` (and the same rotated
180°) in `nar_star`, radius 0.10 → 0.05, plus a bright `nar_galaxy_c` (Neon, emit 1.3) core
lump at the middle. Scatter 8–10 tiny `nar_star` stud_patches over the discs. 6 parts.

---

## samurai

### `SamuraiSlicedCucumber` - `build_samurai_sliced_cucumber.py`
**THREE discs, not four**, and bigger: one standing at the back (r 0.88), two lying in front
(r 0.80, r 0.72). Standard grass slice colours (`cuke_dark` / `cuke_stud` / `cuke_pale` /
`cuke_seed`). Add **two small `sam_rock` stones** at the base, 0.35–0.5 across
(`D.rock(radius 0.3, seed=..)`), which is what sets this apart from `SlicedCucumber`.
5 parts.

### `SamuraiKatanaCucumber` - `build_samurai_katana_cucumber.py`
**≈ 2.0 × 1.8 × 6.4.** Standard body + speckles in `cuke_green` / `cuke_stud`. **A katana is
driven into its head**, standing straight up and leaning back ~8°: from z ≈ 3.7 upward -
a short `sam_steel` blade stub, a `sam_gold` **tsuba** (guard: a flat `ngon_pts(8, 0.26)`
prism 0.10 thick) at z ≈ 4.25, then a `sam_hilt` **handle** (a `beveled_box` 0.20 × 0.20 ×
1.55) up to z ≈ 5.9, with **four `sam_gold` diamond wraps** on it (small `stud_patch`es at
`spin=45`, on the front and both sides), and a `sam_hilt` pommel cap. Round the body at
`zf ≈ 0.55` a **red ribbon**: a `wrap_ribbon(turns=1.0, width=0.30, thick=0.10)` in
`sam_ribbon` plus a bow - two short `sam_ribbon` tails hanging down the front-left. From the
ribbon hangs a small dark **tag**: a `sam_ink` box 0.3 × 0.38 × 0.08 with a `sam_gold`
diamond on it, on a short thread. 8 parts.

### `SamuraiBambooCucumber` - `build_samurai_bamboo_cucumber.py`
**≈ 2.4 × 1.7 × 4.4.** Body in a brighter `sam_stalk` green with `cuke_stud` speckles
kept as a fine, regular grid (`rows=8, per_row=4, size=0.20, stagger=False`) so the skin
reads like bamboo. **Three `sam_bamboo` tan bands** ring it at `zf 0.22, 0.50, 0.78` - each
a `D.lathe` ring (or a `wrap_ribbon` with `turns=1.0`), 0.26 tall, standing 0.05 proud.
Small `sam_leaf` leaves sprout at two of the bands: 4 `leaf_blade`s (length 0.7, width 0.34)
angled up and out, two to each side. 4 parts.

### `SamuraiLanternCucumber` - `build_samurai_lantern_cucumber.py`
**≈ 2.0 × 2.0 × 5.6.** Standard body + speckles. On its head sits a **Japanese lantern**:
a `sam_bamboo` box 0.95 × 0.95 × 0.9 at z ≈ 4.2 with a warm `sam_warm` (Neon, emit 1.0)
window panel on the front and both sides (inset `beveled_box`es), a `sam_gold_dk` frame band
top and bottom, and above it a `sam_roof` **pyramid roof** 1.5 across with a 0.35 rise plus
a small finial cube - give the roof a `sam_roof_lt` ridge line so it reads as tiled. Down the
body's front face a **cream tag** (`sam_paper` box 0.52 × 0.66 × 0.07 at `zf ≈ 0.45`,
standing 0.04 proud) carrying **侍** - `D.kanji_samurai(bm, origin=(0, -0.72, 1.85),
size=0.42, thick=0.05)` in `sam_ink`. 7 parts.

### `SamuraiBambooGrove` - `build_samurai_bamboo_grove.py`
**≈ 3.4 × 2.6 × 9.2.** **Four bamboo stalks** of different heights (9.2, 7.6, 6.4, 5.0)
standing in a loose clump within a 2.2-stud footprint, each an 8-sided `D.cyl` (radius 0.24,
segs 8) in `sam_stalk`, each leaning 2–5° in a different direction. Every stalk is
**segmented by `sam_bamboo` bands** every ~1.3 studs (thin `lathe` rings or `cyl`s of
radius 0.27, 0.14 tall). Off the upper thirds, **eight `sam_leaf` leaf blades**
(`leaf_blade`, length 1.0, width 0.32) angled up and out. At the base, **three `sam_rock`
stones** (`D.rock`, radius 0.45–0.65) and a few `sam_stalk_dk` shoots poking up. 6 parts.

### `SamuraiToriiGate` - `build_samurai_torii_gate.py`
**≈ 11 × 2.0 × 10.2.** A **torii**. Two `sam_torii` red pillars (0.85 across, slightly
tapered, `blocky_trunk` works) at x = ±3.9, standing on `sam_roof` dark-grey plinths
(1.25 across, 0.9 tall). A `sam_torii` **crossbeam** (the nuki) at z ≈ 6.6, 9.2 long,
0.55 × 0.55, running right through both pillars. Above it at z ≈ 8.6 the **kasagi** - a
`sam_roof` dark lintel 11 long, 0.85 tall, 1.0 deep, whose ENDS TURN UP: build it as three
`beveled_box`es, the outer two rotated ±7° about Y and lifted, or as a `prism` of a gently
curved outline. Under the kasagi a thinner `sam_torii` shimaki band. In the middle, hanging
from the nuki, a `sam_paper` **plaque** 1.5 × 1.9 × 0.14 with **侍** on it
(`D.kanji_samurai(size=1.15, thick=0.09)` in `sam_ink`). `sam_gold` square studs on the
pillars (`box_studs`, `grid=(1,4)`, `size=0.22`) and on the beam ends. 7 parts.

### `SamuraiSakuraTree` - `build_samurai_sakura_tree.py`
**≈ 6.8 × 5.6 × 11.8.** The `CucumberTree` skeleton in `sam_bark` / `sam_bark_dk`, with a
crown of **pink blossom cubes**: 7 `crown_cluster` cubes (size ≈ 2.3) in `sam_sakura`, with
`sam_sakura_dk` `box_studs` (`grid=(2,2)`, `size=0.42`). At the base, **three `sam_rock`
stones** and a low ring of `grass` tufts (small `prism`s or `foliage`). Plus **six falling
petals** - tiny `sam_sakura` flat squares (0.22 across, 0.05 thick) scattered in the air
between z 1.5 and 6, each rotated randomly; they are what makes this read as sakura.
6 parts.

---

## farm

### `FarmMuddyCucumber` - `build_farm_muddy_cucumber.py`
**≈ 1.5 × 1.5 × 4.4.** Standard body in `cuke_green` with `cuke_stud` speckles, then **splatter it with mud** - 10–12 `stud_patch`es in
`farm_mud`, `size` varying 0.26–0.55, `aspect` 0.6–1.5, `spin` random, at facet points from
`zf 0.05` to `0.85`, concentrated toward the BOTTOM half. A few smaller `farm_mud_lt` ones
on top of them for a two-tone splatter. Material `"Mud"` on the mud. 4 parts.

### `FarmCucumberBasket` - `build_farm_cucumber_basket.py`
**≈ 3.8 × 3.4 × 4.2.** A **round woven basket** holding three cucumbers. Basket: a
`D.lathe` body (profile out to radius 1.5 at the rim, in to 1.25 at the base, hollowed by
running the profile back down the inside) in `farm_basket`, segs 12, height 1.7, sitting on
z = 0; over its outside a **weave** of `farm_basket_d` bands - 3 horizontal `lathe` rings
plus 10 vertical `beveled_box` staves, or use `D.weave_panel` wrapped as flat panels if
simpler. A `farm_basket_d` rim band at the top. A **handle**: an arch of `D.tube` from
(1.45, 0, 1.6) up over to (−1.45, 0, 1.6), peaking at z ≈ 3.9, radius 0.14. Inside, **three
cucumbers** (`cuke_body` with `CUKE_PROFILE_STUB`, h 1.9, r 0.42) leaning out at different
angles, in `cuke_green` with `cuke_stud` speckles - their tops must clear the rim.
7 parts.

### `FarmCrateCucumber` - `build_farm_crate_cucumber.py`
**≈ 3.6 × 3.0 × 3.4.** A **slatted wooden crate** holding four cucumbers. Crate: four sides
of `D.slat_run` in `farm_crate` (three horizontal slats a side, 2.9 × 2.4 footprint,
1.7 tall), `farm_crate_d` corner posts (0.28 square) at all four corners, and a floor.
Inside, **four cucumbers** (`CUKE_PROFILE_STUB`, h 2.1, r 0.44) poking up and out at
different leans, `cuke_green` + `cuke_stud`. 6 parts.

### `FarmHayBale` - `build_farm_hay_bale.py`
**≈ 4.6 × 3.0 × 3.0.** A **rectangular bale** lying on its side: a `beveled_box`
4.4 × 2.8 × 2.8 in `farm_hay` with `bevel=0.22`, textured all over with `box_studs`
(`grid=(3,3)`, `size=0.42`, `rise=0.05`) in `farm_hay_dk` - the reference's straw texture is
exactly our speckle. **Three `farm_strap` leather straps** round it (flat `beveled_box`
bands 0.34 wide, 0.10 proud, at x = −1.35, 0, +1.35, each wrapping the top and both sides),
each with a small `wood_dark` buckle on the front. Material `"Sand"` on the hay, `"Leather"` on the straps. 4 parts.

### `FarmWindmillPlant` - `build_farm_windmill_plant.py`
**≈ 4.6 × 2.2 × 12.** A **lattice tower with a fan on top**. Tower: four `farm_wood` legs
(`branch_box`, 0.20 square) from a 2.0-stud-square footprint at z = 0 in to a 0.7-stud
square at z = 8.6; **X cross-bracing** on the front and back faces at three levels
(`branch_box` diagonals, 0.13 square) in `farm_wood_dk`, plus horizontal girts. On top, a
`farm_wood_dk` hub box, and an **eight-blade fan** standing in the XZ plane facing +Y: each
blade a `beveled_box` 1.85 long × 0.44 wide × 0.09, radiating from a `farm_bark` centre
hub (a `cyl` of radius 0.34 along Y), alternating `farm_cream` and `farm_red`. Rotate each
blade about Y with `D.rot_euler(0, i * 45, 0)` - build it as a spoke offset then rotated.
Fan centre at z ≈ 9.6, radius ≈ 2.1. 6 parts. `PIVOTS = {"FanHub": (0.0, -0.35, 9.6)}` and
`STATES = {"Spin": 45.0}` so a game can turn it.

### `FarmCucumberTree` - `build_farm_cucumber_tree.py`
**≈ 6.4 × 5.6 × 11.8.** Very close to `CucumberTree` but **farmier**: `stepped_base` with
THREE steps in `farm_bark_dk` (a wide root flare), `blocky_trunk` in `farm_bark`, **two**
big forks rather than four, one crown of **four large `cuke_green` cubes** (size 2.8) with
`cuke_stud` `box_studs`, and **three cucumbers hanging** below. 5 parts.

---

## snow

### `SnowFrozenSlice` - `build_snow_frozen_slice.py`
The `SlicedCucumber` arrangement **frozen**: rims `snow_ice` (`"Ice"`, `transparency=0.12`),
rim speckles `snow_ice_lt`, faces `snow_white` (`"Glacier"`), pips `snow_ice_lt`. 4 parts.

### `SnowSnowballSlice` - `build_snow_snowball_slice.py`
**≈ 2.6 × 2.4 × 2.2.** NOT discs: **three snowballs stacked in a pyramid** - two on the
ground (`uvsphere` radius 0.78, segs 10, rings 7, centres at x = ±0.80, y = 0.1, z = 0.76)
and one on top (radius 0.72, z ≈ 1.62) - in `snow_white` (`"Snow"`), each speckled with
`snow_ice_lt` `stud_patch`es (8 per ball, on its facet points, `size=0.26`). A thin
`snow_shadow` contact shadow disc under each is optional. 2–3 parts.

### `SnowSnowcapCucumber` - `build_snow_snowcap_cucumber.py`
**≈ 2.0 × 2.0 × 4.8.** Body in `snow_ice` (`"Ice"`, `transparency=0.10`) with `snow_ice_lt`
speckles. On top, `D.cuke_snow_cap(thick=0.36, drips=4, top_zf=0.85)` in `snow_white`
(`"Snow"`). Down the sides, **white snow spikes** pointing outward and slightly UP:
`D.spike_ring(rows=5, per_row=3, length=0.30, base_r=0.14, segs_spike=5, droop=-0.25)` in
`snow_white`. 4 parts.

### `SnowFrozenCucumber` - `build_snow_frozen_cucumber.py`
**≈ 2.1 × 2.1 × 5.0.** Body `snow_ice` (`"Ice"`, transparency 0.12) + `snow_ice_lt`
speckles. Its signature is **thick snow that has PILED on top and is hanging over the
edges**: `D.cuke_snow_cap(thick=0.46, drips=6, drip_len=0.85, spread=1.25, top_zf=0.80)` in
`snow_white`, plus 3 or 4 extra `D.tube` tongues running further down the front to
`zf ≈ 0.35`. No spikes - this one is soft and heavy where `SnowSnowcapCucumber` is spiky.
3 parts.

### `SnowCrystalCucumber` - `build_snow_crystal_cucumber.py`
**≈ 2.6 × 2.4 × 4.8.** NOT a cucumber body at all: a **cluster of ice crystals**. One tall
central `D.crystal_spire(base=(0,0,0), height=4.4, radius=0.60, segs=6, taper=0.55,
tip=0.30)` in `snow_crystal` (`"Ice"`, transparency 0.15), flanked by **six smaller spires**
(heights 1.2–2.6, radii 0.22–0.40) leaning 8–22° outward around it - use
`rot=D.rot_euler(lean, 0, yaw)` on each. Speckle them all with `snow_white` `stud_patch`es
(4–5 per spire). 3 parts.

### `SnowSnowTree` - `build_snow_snow_tree.py`
**≈ 5.6 × 5.6 × 11.5.** A **conifer**: a `snow_bark` trunk (`stepped_base` + `blocky_trunk`)
to z ≈ 2.6, then **four stacked tiers** of foliage - each tier a squat `D.lathe` cone
(or a 4-sided `pyramid`/`cone`) in `snow_pine`, radii 2.6 / 2.1 / 1.6 / 1.0 at z = 2.4,
4.5, 6.4, 8.1, each 2.3 tall - and **a white snow cap sitting on every tier** (a matching
cone in `snow_white`, slightly larger and only 0.45 tall, capping each tier's top).
A pointed `snow_white` tip at z ≈ 10.6. `snow_pine_dk` speckles on the tiers.
5 parts. Materials `"LeafyGrass"` on the pine, `"Snow"` on the white.

### `SnowIcicleTree` - `build_snow_icicle_tree.py`
**≈ 6.4 × 5.4 × 11.5.** A `snow_bark` blocky tree (base + trunk + **four `branch_box`
forks** reaching out nearly horizontally at z ≈ 7.5–8.5), with **no crown cubes**. Instead:
a `snow_white` **snow cap on top of every branch and on the trunk head**
(`D.snow_slab` over each branch's end box, or flattened `beveled_box`es), and
**`snow_ice_lt` icicles hanging under each branch** (`D.icicle_row(a, b, count=4,
length=0.7, radius=0.11)`, `"Ice"`, transparency 0.15). 4 parts.

### `SnowFrozenTree` - `build_snow_frozen_tree.py`
**≈ 6.4 × 5.4 × 11.5.** The `CucumberTree` skeleton in `snow_bark`, but the crown cubes are
**blocks of pale blue ICE** (`snow_ice_lt`, `"Ice"`, transparency 0.15) - five cubes of size
2.3 - each wearing a `snow_white` **snow cap** on its top face (`D.snow_slab` on each cube).
`snow_white` speckles on the ice. 5 parts.

---

## underwater

### `UnderwaterBubbleSlice` - `build_underwater_bubble_slice.py`
The `SlicedCucumber` arrangement as **glassy bubbles**: rims `sea_bubble` (`"Glass"`,
`transparency=0.42`), rim speckles `sea_bubble_lt` (transparency 0.15), faces
`sea_bubble_lt` (`"Glass"`, transparency 0.35), pips `snow_white`. Round the discs off by
using `segs=14` so they read as bubbles rather than coins. 4 parts.

### `UnderwaterShellSlice` - `build_underwater_shell_slice.py`
**≈ 2.8 × 2.4 × 1.9.** An **open clam shell**. Two ribbed halves: each a `D.lathe`-ish
fan - easiest is a `prism` of `D.arc_pts((0,0), 1.15, -80, 80, n=9)` closed back to the
hinge, 0.30 thick, with **seven raised ribs** (`beveled_box` strips radiating from the
hinge, 0.10 proud) in `sea_shell_dk` over a `sea_shell` body. The bottom half lies open on
the ground tilted back 20°; the top half stands up behind it, hinged at the back and opened
~70°. Inside the bottom half, a `sea_shell_in` cream **pearl-lining face** with five
`sea_pearl` pips - the reference's "slice" read. 5 parts.

### `UnderwaterSeaweedCucumber` - `build_underwater_seaweed_cucumber.py`
**≈ 1.9 × 1.9 × 4.5.** A cucumber whose sides are **rippled like kelp**. Build the body
with a custom lathe: take `CUKE_PROFILE` and, instead of `cuke_body`, call `D.lathe` with a
profile whose radius WOBBLES up the height - e.g. multiply each profile radius by
`1 + 0.13 * sin(z_fraction * 7 * pi)` over 22 profile rows - in `sea_weed`. Then `segs=10`.
Speckles in `cuke_stud` (lighter than the body), `rows=6, per_row=2`. Add 4 thin
`sea_weed_dk` vertical fin strips down the sides (`surface_line` runs from `zf 0.1` to
`0.9` at four angles) so the ripple reads in silhouette. 3 parts.

### `UnderwaterCoralCucumber` - `build_underwater_coral_cucumber.py`
**≈ 3.0 × 2.6 × 4.6.** Body `sea_coral_p` (purple) with `sea_coral_r` (red) speckles.
Sprouting from its sides, **five red coral arms**: `D.coral_arm(base=cuke_point(...),
direction=outward-and-up, length=0.95, radius=0.15, depth=2, branches=2, spread=40)` in
`sea_coral_r`, at `zf` 0.25, 0.42, 0.55, 0.70, 0.80 and spread round the angles so some
come toward the viewer. 3 parts.

### `UnderwaterPearlCucumber` - `build_underwater_pearl_cucumber.py`
**≈ 2.3 × 2.3 × 4.5.** Body `sea_pearl` (cream) with `sea_pearl_sh` speckles.
**Six big white pearls** stuck down its sides: `D.uvsphere(radius 0.32, segs=10, rings=7)`
in `snow_white`, `smooth=True`, `roughness=0.2`, at facet points from `zf 0.20` to `0.85`,
alternating sides (facets 0, 2, 1, 7, 2, 0 - spread them so three read on the front).
3 parts.

### `UnderwaterKelpTree` - `build_underwater_kelp_tree.py`
**≈ 6.0 × 5.4 × 11.5.** A **stepped teal stalk** with a crown of **long drooping kelp
blades**. Stalk: `stepped_base(top_w=1.6, h=1.7, steps=3, grow=1.3)` + `blocky_trunk` to
z ≈ 7.4 in `sea_stalk`, with `sea_stalk_dk` speckles. Crown: **nine `sea_kelp` fronds**
(`D.palm_frond`, length 2.9, width 0.70, droop 2.0 - much more droop than the palm, so they
hang down - pitch 32, teeth 0.18) at `yaw_deg` every 40°, bases at z ≈ 7.5, three of them in
`sea_kelp_dk` for depth. 5 parts.

### `UnderwaterBubbleTree` - `build_underwater_bubble_tree.py`
**≈ 6.2 × 5.2 × 11.8.** A `sea_deep` blue stepped trunk (base + `blocky_trunk` + **four
`branch_box` forks**) with `sea_deep_dk` speckles, carrying **four translucent bubbles**
instead of crown cubes: `D.uvsphere(radius 1.55 / 1.05 / 0.95 / 0.85, segs=12, rings=8)` in
`sea_bubble_lt` (`"Glass"`, `transparency=0.48`, `smooth=True`), the biggest on top.
Speckle each bubble with 5 `snow_white` `stud_patch`es (`transparency=0.2`) so they catch
light. 4 parts.

### `UnderwaterCoralTree` - `build_underwater_coral_tree.py`
**≈ 6.4 × 5.6 × 11.5.** A `sea_coral_p` purple stepped trunk (base + `blocky_trunk` to
z ≈ 5.5, `sea_coral_pd` speckles) that breaks into **branching staghorn coral**: three
`D.coral_arm(length=2.6, radius=0.34, depth=3, branches=2, spread=38)` growing up and out
from z ≈ 5.2 - one in `sea_coral_r` (red), one in `sea_coral_o` (orange), one in
`sea_coral_r` again - so the crown is a red-and-orange thicket. No cubes, no leaves.
4 parts.
