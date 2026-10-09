# Guardian build contract

Ten sitting biome guardians for the "steal a cucumber and it chases you" loop.  This is
the contract a `build_<name>.py` is written against: the space, the API, the hard rules,
and a detailed brief per guardian taken from its concept sheet.

`build_strawman.py` is the **worked example** - it is built, rendered and reviewed, and
every rule below is visible in it.  Read it before writing anything.

---

## 1. Space

- 1 Blender unit = **1 Roblox stud**.  Z up, the floor is **z = 0**, nothing below it.
- Every guardian **faces +Y**.  The FBX importer yaws 180°, so the authored +Y front
  lands on Roblox **−Z**, which is the model's LookVector.  Author +Y, get forward.
- **+X is the character's RIGHT.**  Renders look down −Y, so **+X appears on the LEFT of
  the frame** - anything "on the right as I look at the sheet" is at **negative x**.
- An **R15 avatar is 5 studs tall**, 2 wide, 1 deep, and stands in every render for scale.
- Flat shaded, **one flat colour per piece**, no textures, chunky enough to read at 100
  studs.
- **2 000 – 4 000 triangles** per guardian (the seat and extras are counted separately
  and should stay under ~900 each).  `summary()` flags anything outside the budget.

## 2. The three exports of a build script

```python
COLLECTION = "Kabuto"        # == GUARDIAN for the main model
GUARDIAN   = "Kabuto"        # which ROLES table the colours come from
SEAT       = "Kabuto_Seat"
NOTES      = "one paragraph: size, what each part is, anything a reviewer should know"
POSES      = {"Sit": {...}, "Awake": {...}, "Run": {...}}   # Sit and Awake are required
POSE_LOC   = {"Sit": {"Root": (0, 0.4, -1.0)}}              # optional, per pose
def build(G): ...            # must return the main collection
```

## 3. The hard rules

1. **`G.begin(COLLECTION, GUARDIAN)` first**, and again for each extra collection -
   it clears the collection, so a rebuild is idempotent.  Never `clear_collection`.
2. **Every piece is made with `G.part(...)`, never `new_obj`.**  Each part needs:
   - a **`pivot`** - the (x, y, z) point it ROTATES ABOUT.  A shoulder part pivots at
     the shoulder, not at its own centre.  Geometry is authored in world space as
     normal; `part()` moves the origin onto the pivot for you.
   - a **`role`** - a key in `ROLES[GUARDIAN]` (see `gmath.py`).  It becomes the last
     token of the object name and is how Roblox gets the colour back after the FBX
     drops every material.  A role is ONE token: `FurWhite`, never `Fur_White`.
   - a **`parent`** - the part NAME it hangs off in the rig, or `None` for the root.
     Motor6Ds are built straight from this.  Exactly ONE root per collection.
3. **`Root` and `Hitbox` are required** on the main collection.  `G.root_part(c, lo, hi)`
   makes the invisible rig root (a small box at hip/centre height - it becomes
   HumanoidRootPart); `G.hitbox(c, lo, hi, pivot=..., parent="Root")` makes the
   invisible full-body query box.  Both are transparency 1 and never rendered.
4. **Every moving part is its own object**: head, jaw, each limb SEGMENT, each claw
   half, the key, the tail, every orbit rock.  Eyes are always separate parts so the
   wake tell can switch them to Neon.
5. **Glow parts use their guardian's Neon roles** (`EyeGlow`, `Lava`, `Glow`, `VisorGlow`
   …).  `part()` sets `rbx_material="Neon"` and a safe emission automatically - do not
   pass `emit` above 1.0, it renders a warm hue as pale yellow.
6. **Author the AWAKE look** (that is what the concept sheet shows).  The asleep look is
   `SLEEP_LOOK` in `gmath.py` plus the `Sit` pose; you do not model it twice.
7. **The rest pose is neutral**: standing, weight even, arms a little out, so animation
   has somewhere to go.  Put the character into its dramatic sheet pose in `POSES`.
8. **Nothing below z = 0** and the model is centred on x = 0 (a chase NPC that is not
   centred pivots wrong).  The only exception is a guardian that is meant to be part
   buried - say so in NOTES.
9. **Seat**: a second collection `<Guardian>_Seat`, `prefix="<Guardian>Seat"`, its own
   single root, built where the guardian sits on it (so the `Sit` render composes).
10. **Check it offline** before it goes anywhere near Blender:
    `py dryrun.py build_<name>.py` - it must print `PASS`.

## 4. The API

Everything is reached as `G.<name>`.  `import bmesh, math` at the top of the script; a
part is `bm = bmesh.new()` → primitives → `G.part(...)`.

### Making a part

| | |
|---|---|
| `G.begin(collection, guardian, prefix=None)` | clear + register a collection, returns it |
| `G.part(name, bm, c, role, pivot, parent=None, material=None, transparency=0.0, moving=None, emit=None, roughness=.55, metallic=0, smooth=False, hex_override=None)` | the only way to make a piece |
| `G.root_part(c, lo, hi, name="Root")` / `G.hitbox(c, lo, hi, pivot=None, parent=None, name="Hitbox")` | the two invisible boxes |

### Boxes, tubes, solids (from `defenselib` / `proplib`)

| | |
|---|---|
| `box(bm, lo, hi, rot=None)` · `cube(bm, loc, size, rot=None)` | axis-aligned boxes |
| `beveled_box(bm, lo, hi, bevel=0.1, segments=1, rot=None)` | the chunky toy-plastic box - **use this, not `box`, for anything big** |
| `stone_block(bm, lo, hi, seed, jitter=0.06, bevel=0.06)` | a box with every corner nudged: masonry |
| `cyl(bm, a, b, radius, segs=12, r2=None, cap=True)` · `cone(bm, base, tip, r_base, r_tip=0, segs=8)` · `spike(bm, base, tip, r, segs=6, tip_r=0)` | round stock between two points |
| `tube(bm, points, radii, segs=8, cap=True)` | lofted tube along a polyline, radius per point |
| `prism(bm, pts2d, z0, z1, matrix=None)` | extrude a 2-D outline - the workhorse |
| `wedge(bm, lo, hi, rise='+Y')` · `pyramid(bm, center, size, height)` | ramps and points |
| `lathe(bm, profile, segs=12, matrix=None, cap=True, phase=0)` | revolve a (radius, z) profile: domes, pots, hats, pads |
| `rock(bm, loc, radius, seed, jitter=0.30, subdiv=1, scale=(1,1,1))` | faceted boulder (80 tris at subdiv 1) |
| `ico`, `uvsphere`, `torus(bm, loc, major, minor, rot=None, seg_major=16, seg_minor=6)` | |
| `foliage(bm, loc, radius, seed, blobs=4, spread=.55, jitter=.26, flatten=1.0)` | a clump of blobs |
| `slat_run(bm, lo, hi, count, gap_frac=.35, axis='x')` | fence pickets, grilles, ribs |
| `stroke_text` / `text_width` | the stroke font (see `face_text` below) |

### Guardian shapes (from `guardianlib`)

| | |
|---|---|
| `tuft(bm, base, direction, n=5, length=.8, width=.16, spread_deg=55, seed=1, segs=3, vary=.35, curve=0)` | a burst of spikes: straw, fur, a brush |
| `spike_shard(bm, base, tip, width, thick=None, roll_deg=0)` | one flat triangular shard (5 faces) |
| `fur_coat(bm, center, radii, n=24, length=.9, width=.5, seed=1, cone_deg=180, axis=(0,0,1), vary=.3, out_bias=.55, shard=True, droop=0)` | shaggy spikes all over an ellipsoid |
| `blob(bm, center, radii, seed=1, jitter=.16, subdiv=1)` | a faceted lump with per-axis radii |
| `puff(bm, center, radius, seed=1, blobs=3, spread=.55)` | a little cloud: steam, dust, snow |
| `tassel(bm, top, length=.9, n=3, width=.13, spread=.22, seed=1, sway=0)` | hanging strips |
| `seam_strip(bm, a, b, width=.22, thick=None, segs=4, bulge=1.0)` | a glowing seam in a gap |
| `boulder_cluster(bm, slots, radius=.9, seed=1, jitter=.3, scale=(1,1,1), vary=.35)` | many rocks in one mesh |
| `crescent(bm, center, r_out=1, r_in=.8, offset=.42, thick=.5, open_deg=150, n=14, rot=None, plane="XZ")` | a crescent moon, horns up |
| `hex_prism(bm, center, radius, height, axis=(0,0,1), sides=6, phase=0, taper=1.0)` | an n-gon plate or peg |
| `diamond(bm, center, radius=.3, length=.8, axis=(0,0,1), sides=4, phase=0, squash=1)` | a four-point gem |
| `ring_band(bm, center, axis, radius=.4, minor=.09, seg_major=12, seg_minor=5)` | a torus on any axis |
| `horn(bm, base, tip, r0=.34, r1=.03, bow=(0,0,0), n=6, segs=6, power=1.2)` | a tapering curved horn / tusk |
| `limb(bm, a, b, r0, r1=None, segs=6, bow=(0,0,0), n=4)` | a tapering limb segment |
| `claw_jaw(bm, hinge, tip, width=.55, thick=.5, curve=.25, teeth=0, side=1, root_w=None)` | one half of a pincer |
| `barnacle(bm, center, normal, r_out=.26, r_in=.13, height=.16, segs=8)` | a crusted ring nub |
| `stud_bump(bm, center, normal, radius=.16, height=.14, segs=5, taper=.55)` | a blunt stud / rivet |
| `patch(bm, center, normal, radius=.5, height=.14, seed=1, jitter=.22, segs=7)` | an irregular flat shell: moss, mud |
| `cross_glyph(bm, center, normal, arm=.28, thick=.09, depth=.06, spin_deg=0)` | a + (spin 45 = an X) |
| `plate(bm, pts2d, thick, at=(0,0,0), normal=(0,1,0), spin_deg=0)` | a flat plate; `normal` is the direction its THICKNESS runs |
| `mitten(bm, center, size=(.7,.55,.8), thumb=.3, bevel=.14, facing=(0,1,0))` | a toy fist |
| `worm_ring(bm, center, axis, radius=1.2, thick=.55, lip=.12, segs=10, spikes=0, spike_len=.35, phase=0)` | one armoured body ring |
| `tooth_ring(bm, center, axis, radius=1.0, n=8, length=.42, width=.16, phase=0, inward=.35)` | a ring of tooth pegs |
| `swirl(bm, top, bottom, r0=.9, r1=.05, turns=1.1, n=14, segs=6, wobble=.25)` | a tapering corkscrew tail |
| `face_text(bm, text, center, normal, height=.6, radius=.05, segs=4, spin_deg=0, depth=0)` | raised letters on a surface |
| `plank(bm, a, b, w=.34, t=.26, bevel=.04)` | a square-section beam between two points |
| `shell_fan(bm, center, normal, radius=2.0, ribs=7, thick=.35, spread_deg=150, rise=.35)` | a ribbed scallop shell |

### Reusable cucumber-set shapes (all available on `G`)

`coral_arm(bm, base, direction, length, radius, depth=2, branches=2, spread=42, shrink=.62, seed, segs=5, curl=.18)`,
`crystal_spire(bm, base, height, radius, segs=6, taper=.58, tip=.34, rot=None)`,
`gem(bm, center, radius=.22, segs=6, squash=1.25, rot=None)`,
`icicle(bm, top, length, radius=.10, segs=5, tilt=(0,0))`, `icicle_row(bm, a, b, count, length, radius, seed)`,
`snow_slab(bm, lo, hi, thick=.26, overhang=.06, drips=3, seed)`,
`disc_canopy(bm, center, radius, thick=.34, rim=.20, segs=12, dome=0)`,
`weave_panel(bm, lo, hi, rows, cols, depth=.10, gap=.035, axis="y")`,
`branch_box(bm, a, b, w0, w1=None, bevel=0, spin=0)` (a tapered SQUARE beam),
`crown_cube(bm, center, size, bevel=.11, rot=None, squash=1)`,
`stepped_base(bm, top_w, h, steps=3, grow=1.32, bevel=.06, z0=0, center=(0,0))`,
`box_studs(bm, lo, hi, faces, per_face=3, size=.3, rise=.05, seed)`,
`stud_patch(bm, point, normal, size=.26, rise=.055, spin=0)`,
`surface_frame(normal, up=(0,0,1))` (a 4×4 that keeps a square square on a surface -
never use bare `aim()` for anything with corners).

### Placement / maths

`place(loc, rot=None, scale=1.0)` → a 4×4 for any `matrix=` argument · `rot_euler(rx, ry, rz)`
(degrees) · `aim(direction)` (+Z onto a direction, arbitrary roll) · `mirror_x(bm, verts)` ·
`translate(bm, verts, offset)` · `xform(bm, verts, matrix)`.

From `gmath`, all running for real in the dry run:
`lerp3`, `add3`, `sub3`, `mul3`, `norm3`, `dist3`, `mid3`,
`chain_points(a, b, n, sag=0, bow=(0,0,0))`, `taper(r0, r1, n, power=1)`,
`sphere_dirs(n, seed, up_bias=0, cone_deg=180, axis=(0,0,1))`,
`ellipsoid_points(center, radii, dirs)`, `crescent_profile(...)`,
`ring_slots(n, radius, phase_deg=0, center=(0,0), squash=1)`,
`leg_slots(n_per_side, y0, y1, x, splay=0)`,
`segment_chain(start, end, n, r0, r1, droop=0, power=1)`,
`boulder_slots(n, center, radii, seed, spread=1)`, `zigzag(a, b, n=5, amp=.18, axis)`,
`fan_angles(n, spread_deg, center_deg=0)`,
plus `ngon_pts`, `arc_pts`, `rounded_rect_pts`, `star_pts`, `teardrop_pts`,
`chevron_pts`, `grid_positions`, `helix_pts`, `catenary_pts`.

## 5. Tri-count feel

`rock`/`blob` at subdiv 1 = **20 tris** (`create_icosphere(subdivisions=1)` is the bare
20-face icosahedron; subdiv 2 is 80) · `beveled_box` ≈ 44 · `box` = 12 ·
`limb` (segs 6, n 4) ≈ 40 · `tube` (segs 5, 5 pts) ≈ 46 · one `tuft` spike at the
default segs 3 = **4 tris** ·
one `spike_shard` = 6 · `barnacle` (segs 8) ≈ 56 · `hex_prism` (6 sides) ≈ 20 ·
`lathe` (8 profile pts, segs 10) ≈ 140 · `torus` (12×5) = 120.
A 30-part guardian of bevelled boxes, tubes and a few lathes lands around 2 500 - which
is where Strawman came out.  If you are under 2 000, add the detail the sheet shows
(studs, bolts, barnacles, fur, cracks); if you are over 4 000, drop `segs` and use
`box` instead of `beveled_box` on small pieces.

## 6. Poses

`POSES[name]` maps a **part name** to `(rx, ry, rz)` in **degrees**, applied in the
part's rest world frame, about its own pivot, and inherited by its children.

**Which axis does what** (world axes, not the part's own - get this wrong and limbs
swing backwards, which is the second most common mistake after a bad pivot):

| the piece points | to swing it… | use |
|---|---|---|
| **down** (a leg, a hanging arm, a tail) | **forward, toward +Y** | `rx` **positive** |
| **down** | sideways, away from the body on the +X side | `ry` negative |
| **out along +X** (an outstretched right arm, a horn, a claw) | **down** | `ry` **positive** |
| out along +X | forward toward +Y | `rz` positive |
| **out along −X** (the left side) | **down** | `ry` **negative** |
| out along −X | forward toward +Y | `rz` negative |
| **up** (a head, a torso, a raised club, an eye stalk) | **forward / nodding down** | `rx` **negative** |
| **forward along +Y** (a jaw plate, a wedge head) | **open upward** | `rx` **positive** |

The two `rx` rows are the same rotation - what changes is which side of the pivot the
mass sits on.  A leg hangs BELOW its hip, so `+rx` swings it forward; a torso stands
ABOVE its waist, so `+rx` tips it BACK and `−rx` is the slump.  Decide by asking where
the geometry is relative to the pivot, not by what the part is called.

A child cancels its parent by rotating the same amount the other way: a thigh at
`rx +58` with a shin at `rx −66` gives a knee bent back under the body.
`POSE_LOC[name]` maps a part name to a `(dx, dy, dz)` offset applied after its rotation
- that is how a rig drops onto its seat (`{"Root": (0, 0.4, -1.0)}`) or hovers.

- **`Sit`** - asleep on the seat.  Render `<Guardian>_Sit.png` shows guardian + seat, so
  it must actually land on the seat, not float over it or sink into it.
- **`Awake`** - the sheet's hero pose: upright, eyes up, weapon raised.
- **`Run`**, and any signature pose you want (`Slam`, `Charge`, `Throw`, `Bite`) - all
  optional, all useful to Phase 2.

If a pose looks right in the render, the pivots are right.  That is the whole point of
the pose check - it is the cheapest possible test of the rig before Studio sees it.

## 7. Checking

```bash
cd C:/Users/shrey/OneDrive/Documents/RobloxGames/guardians
py dryrun.py build_kabuto.py
```

The dry run fakes Blender, so it is safe to run many in parallel.  It catches bad roles,
missing pivots, broken parents, two roots, duplicate names, POSES that name a part that
does not exist, and geometry below the floor.  Its bounding box **ignores `rot=` and
`matrix=`**, so a transform-heavy model may report a wrong size - that is expected, not
a failure.  **Agents never touch Blender**: concurrent `execute_blender_code` calls
share one socket and corrupt each other.

---

# The ten briefs

Sizes are from `gmath.SPEC`.  Colours are role names from `gmath.ROLES` - never a hex
literal.  Every sheet is described as it looks facing you; remember **the character's
right (+X) is on the LEFT of the render**.

---

## 1. Strawman - Spawn - DONE, the worked example

7.15 to the hat, arms out 4.6 wide.  See `build_strawman.py`.

---

## 2. Dune - Desert - sand worm, 12 long / 3.5 wide

**The sheet.** A segmented worm bursting up out of the sand, most of its length still
buried.  The head is a **three-part jaw opened like a flower**: a big upper hood plate
and two side mandibles, each a thick sandstone plate with a raised rim, folded back to
show a **dark red throat** ringed with **cream triangular teeth** (about 7 on the hood,
4 on each mandible, pointing inward).  Below the jaw, on the front of the head, sit two
**amber slit eyes** under heavy sandstone lids.  The body behind the head is a chain of
**armoured rings** - each a drum with a raised leading lip and a few backward-swept
spikes - shrinking as it goes down into the sand.  Chunks of sandstone and sand fly
around the point where it breaks the surface.

**Build it REARED UP** (as on the sheet): the tail root at the ground on −Y, the body
curving up and forward, the head at the top on +Y at about z 9.5, looking slightly down
at the player.  Model the jaws **CLOSED** (the three plates folded into a blunt cone
nose) - `POSES["Awake"]` opens them, `POSES["Bite"]` opens them wide.  That is the only
way the jaw pivots can be checked.

**Parts** (~26): `Root` (in the sand at the tail), `Hitbox`,
`Body1`..`Body6` (`Sandstone`, each a `worm_ring`, radius 1.75 → 0.75, chained; each
parented to the one below), `Ring1`..`Ring6` is NOT needed - put the raised lip in the
same part - `Neck` (`Sandstone`), `Head` (`Sandstone`, the skull the three plates hinge
on), `JawTop` (`Sandstone`, pivot on the hinge at the back of the hood),
`Mandible_R` / `Mandible_L` (`Sandstone`, hinged at the sides), `TeethTop`,
`TeethR`, `TeethL` (`Teeth`, each parented to its plate), `Throat` (`Mouth`, a cone
inside the head), `Eye_R` / `Eye_L` (`EyeGlow`), `Lid_R` / `Lid_L` (`RingShadow`),
`Gap1`..`Gap3` (`RingShadow`, thin bands showing between the big rings - optional if the
tri budget is tight).

**Seat** `Dune_Seat` - the **sand mound**: a low flattened mound of `Sand` about 6 × 4 ×
1.3 with `SandDark` shadow at its base, a few sandstone chips, and the two closed eye
lids showing on the front of it.  It is what slides along the ground while the worm
travels underground, so the mound alone must read as "something is under there".

---

## 3. Kabuto - Samurai - stone oni, 9 standing / 4 × 4

**The sheet.** A squat, immensely heavy blocky statue.  **Square head** with a heavy
brow, a grimace, deep-set **amber glowing eyes**, two **cream tusks** pointing up from
the lower jaw, and **two big horns** sweeping forward and up out of the top corners of
the head.  **Square shoulders** far wider than the hips, with **green moss patches** on
top of each.  **Amber crack lines glow** down the chest, along both arms and both legs -
jagged, like lightning.  A thick **red rope belt** with a big knot at the front and two
tassels hanging to the knee; matching **red rope bands** round one wrist and one ankle
and round the club's grip.  Big blocky fists.  The right hand holds a **kanabo**: a long
tapering stone club covered in **square studs**, glowing cracks running up it, planted
on the ground beside it.  Moss also on one knee.

**Parts** (~30): `Root`, `Hitbox`, `Torso` (`Stone`), `Belt` (`Rope`, the knot + two
`tassel`s), `Head` (`Stone`), `Horn_R`/`Horn_L` (`Stone`), `Tusks` (`Tusks`),
`Eye_R`/`Eye_L` (`EyeGlow`), `Pauldron_R`/`Pauldron_L` (`Stone`),
`Moss_R`/`Moss_L`/`MossKnee` (`Moss`), `ArmUpper_R/L`, `ArmLower_R/L`, `Fist_R/L`
(`Stone`), `Hips` (`Stone`), `LegUpper_R/L`, `LegLower_R/L`, `Foot_R/L` (`Stone`),
`Club` (`Stone`, parented to `Fist_R`), `ClubGrip` (`Rope`, parented to `Club`),
`ClubCracks` (`EyeGlow`, parented to `Club`),
`CracksTorso`, `CracksArm_R`, `CracksArm_L`, `CracksLeg_R`, `CracksLeg_L` (`EyeGlow`,
each parented to the piece it runs over - use `zigzag()` + `seam_strip()` or thin
`plate`s sunk into the stone so they read as light in a channel).
`StoneDark` is for the recessed sides so the blocks read as blocks.

**Seat** `Kabuto_Seat` - a **square stone pedestal** about 4.2 × 4.2 × 1.6 (use
`stepped_base`), a **torii-style lintel** behind it in `Rope` red (two posts and two
cross beams, about 5.5 tall and 4.6 wide), two small `Stone` lanterns with a warm
`Lantern` light panel, moss patches and a few grass tufts at the base.

---

## 4. Brisket - Farm - bull, 8 at the shoulder / 12 long

**The sheet.** A bull with its head down, mid-charge.  The front of it is **enormous**
and the back is small: a massive chestnut chest and shoulder mass, a thick low-slung
head, and much smaller hindquarters.  The **horns are wider than the body** - huge,
cream, round in section, sweeping out sideways then curving forward and up to points.
The muzzle is a big soft **cream block** with a **pink nose**, a **brass ring** through
the septum, and **two white steam puffs** blowing out of the nostrils.  Small angry
**red glowing eyes** set deep under the brow.  Ears tucked back behind the horns.
**Black hooves**, thick legs (upper + lower per leg).  A thin tail with a **black tuft**
flicking up behind.  Clods of mud fly around its feet.

**Build it standing**, head low but not on the ground; the sheet's head-down charge is
`POSES["Charge"]`.  Body long along Y: the chest at +Y (the front, facing the camera),
the rump at −Y.

**Parts** (~26): `Root`, `Hitbox`, `Body` (`Chestnut`, one big `blob`/bevelled mass
tapering to the rump), `Neck` (`Chestnut`), `Head` (`Chestnut`),
`Horn_R`/`Horn_L` (`Horn`, use `horn()` with a `bow`), `Ear_R`/`Ear_L`
(`ChestnutDark`), `Muzzle` (`Horn`), `Nose` (`Nose`), `Ring` (`Ring`, a `ring_band`
hanging out of the septum), `Eye_R`/`Eye_L` (`EyeGlow`),
`Steam_R`/`Steam_L` (`Steam`, two `puff`s in front of the nostrils),
`LegUpperF_R/L`, `LegLowerF_R/L`, `HoofF_R/L`, `LegUpperB_R/L`, `LegLowerB_R/L`,
`HoofB_R/L` (`Chestnut` / `Hoof`), `Tail` (`Chestnut`), `TailTuft` (`Hoof`).

**Seat** `Brisket_Seat` - a **mud patch**: a flat irregular `Mud` puddle about 7 × 5 with
`MudDark` in the middle and a few clods around the rim, a **broken fence corner** in
`Fence` (two posts and two rails, one rail snapped), and a few `Grass` tufts.

---

## 5. Frostbite - Snow - yeti, 10 standing / 5 × 4

**The sheet.** A hunched, immensely shaggy giant.  The whole silhouette is made of
**overlapping triangular fur shards** - bright `FurWhite` on top, `FurShadow` blue-white
underneath and in the recesses - so there is no smooth surface anywhere.  A **pear body**
with **no neck**: the head is a bump on the front of the shoulder mass.  The face is a
**dark blue-grey oval** set deep in the fur, with **two tiny glowing ice-blue eyes**, a
heavy brow, and **two cream fangs** pointing down over an underbite.  **Arms reach the
ground**, thick as tree trunks, ending in **dark palms**.  **Big dark flat feet**.  It is
breathing frost: a few pale ice shards float in front of its mouth.

Build the fur with `fur_coat` per body region so the shards travel with the joint they
belong to: `FurBody`, `FurShoulder_R/L`, `FurArm_R/L`, `FurLeg_R/L`, `FurHead`.  Under
them, plain `FurShadow` blobs give the volume - the shards only need to cover the
silhouette, not every square stud.

**Parts** (~24): `Root`, `Hitbox`, `Body` (`FurShadow`), `FurBody` (`FurWhite`),
`Head` (`FurShadow`), `FurHead` (`FurWhite`), `Face` (`Face`), `Brow` (`FaceDark`),
`Eye_R`/`Eye_L` (`EyeGlow`), `Fangs` (`Fangs`),
`ArmUpper_R/L` (`FurShadow`) + `FurArm_R/L` (`FurWhite`), `ArmLower_R/L` (`FurShadow`),
`Hand_R/L` (`Face`), `Leg_R/L` (`FurShadow`), `Foot_R/L` (`Face`),
`FurShoulder_R/L` (`FurWhite`).

**Seat** `Frostbite_Seat` - a **cracked ice block** about 4.6 × 3.4 × 1.8 in `Ice` with
`IceDark` cracks (thin sunken plates), a couple of `crystal_spire` shards leaning out of
it, and a low `FurWhite` snow drift round the base.

---

## 6. Pinch - Underwater - king crab, 6 tall / 14 wide / 8 deep

**The sheet.** A wide low crab crusted with reef.  A **domed carapace** in `Shell`,
segmented across the back, with a **tan `Underside` belly plate** showing at the front
between the legs.  **Eight legs**, four a side, each **two segments** - a thick
`Shell` upper that kinks downward and a tapering `Shell` lower ending in a sharp
**tan point**.  **One claw far bigger than the other**: the big one is on the crab's
RIGHT (+X, the LEFT of the render) and is raised, nearly as big as the body; the small
one is low on the other side.  Each claw is an arm, a palm, and two pincer halves - a
fixed lower jaw and a hinged upper jaw, both `Shell` with `Underside` tips and a couple
of blunt teeth on the inside edge.  **Two eye stalks** rise off the top of the shell:
short `Shell` stalks carrying **octagonal plates** (`EyeSocket`) with a bright **green
cross** (`EyeGlow`) in each.  The shell is crusted with **cream barnacle rings** (7–9,
`barnacle()`) and **teal coral sprigs** (5–6, `coral_arm()`).  Bubbles rise from it.

Build it with the big claw **down and forward at rest**; the sheet's raised claw is
`POSES["Awake"]` and the snap is `POSES["Snap"]`.

**Parts** (~34): `Root`, `Hitbox`, `Carapace` (`Shell`), `Belly` (`Underside`),
`Barnacles` (`Barnacle`, all of them in one part on the carapace),
`Coral` (`Coral`, likewise), `Stalk_R`/`Stalk_L` (`Shell`), `EyePlate_R`/`EyePlate_L`
(`EyeSocket`), `Eye_R`/`Eye_L` (`EyeGlow`),
`LegU_R1..R4` / `LegU_L1..L4` (`Shell`) and `LegL_R1..R4` / `LegL_L1..L4`
(`Shell`, tan tip built into the same part) - the legs march back along −Y,
`ClawArm_R`/`ClawArm_L` (`Shell`), `ClawPalm_R`/`ClawPalm_L` (`Shell`),
`PincerTop_R`/`PincerBot_R`/`PincerTop_L`/`PincerBot_L` (`Shell`).

Sixteen leg parts is a lot of objects but they are cheap - keep each `limb()` at segs 5.

**Seat** `Pinch_Seat` - a **rock nook**: a horseshoe of `Rock`/`RockDark` boulders about
7 wide opening toward +Y, a **big ribbed `shell_fan` shell** standing behind it, `Sand`
on the floor, two coral sprigs and a small `Starfish` five-armed star on the sand.

---

## 7. Ember - Volcano - magma golem, 11 standing / 5 × 5

**The sheet.** A pile of basalt boulders standing up, held together by lava.  **The glow
lives in the GAPS** - every boulder floats a little apart from its neighbours and a
bright `Lava` seam bridges the gap, with `EmberGlow` hotter at the core.  The head is a
single boulder with **two glowing hexagonal eye pits** and a **zigzag crack for a mouth**.
Two big **shoulder boulders** sit high and wide; the arms are boulder-upper, boulder-
forearm, and a huge boulder fist.  The core is a cluster of smaller boulders with a
bright seam running through the middle.  Legs are boulder thigh, boulder shin, boulder
foot.  A few loose chips float free around the body.  One hand holds a **loose throwing
rock** - a boulder with its own seams.

Use `boulder_cluster()` for each body region and `seam_strip()` between regions;
`sphere_dirs`/`boulder_slots` place them deterministically.  Keep every seam part
parented to the region it belongs to, or the glow will not travel with the limb.

**Parts** (~26): `Root`, `Hitbox`, `Core` (`Basalt`), `CoreSeams` (`Lava`),
`Head` (`Basalt`), `Eye_R`/`Eye_L` (`EmberGlow`), `Mouth` (`Lava`),
`Shoulder_R/L` (`Basalt`), `ArmUpper_R/L`, `ArmLower_R/L`, `Fist_R/L` (`Basalt`),
`SeamArm_R/L` (`Lava`), `Hips` (`Basalt`), `LegUpper_R/L`, `LegLower_R/L`, `Foot_R/L`
(`Basalt`), `SeamLeg_R/L` (`Lava`), `Chips` (`BasaltLight`, the loose floaters, parented
to `Core`), `ThrowRock` (`Basalt`, parented to `Fist_R`), `ThrowSeams` (`Lava`).

**Seat** `Ember_Seat` - the **rock pile** it sleeps as: a 5 × 5 × 2.6 heap of `Basalt`
boulders with `Ash` dust between them and **no glow at all**, so it reads as scenery, plus
a few `Ash` shards on the floor.

---

## 8. Orbit - Narmek - meteor colossus, 12 tall, hovers 2 up

**The sheet.** A cosmic being with no legs.  The head is a **hood shaped like a crescent**:
a dark `Navy` angular hood with a **grey `MoonGrey` crescent** laid over its front and a
single **purple glowing crack** across it.  Sharp `Navy` shoulder spikes.  On the chest a
**cyan four-point `Starlight` diamond**, with two smaller ones beside it.  Below the
waist the body becomes a **tapering swirl** that ends in a point, with a diamond at the
tip - no legs at all.  **Two floating hands** with no arms between them and the body:
each a `Navy` claw mount carrying **three purple glowing crystal claws**.  **Six orbit
rocks** ring the figure - dark `Navy` chunks, each with a cyan diamond set into it -
on a ring about 4.5 studs across, tilted.  Small navy chips drift between them.

Everything hovers: the whole rig sits 2 studs off the floor, so `Root` is at z ~6 and
NOTHING touches z 0 - say so in NOTES, it is the one guardian allowed an air gap.  The
crescent moon it sits on is the SEAT, not part of the model.

**Parts** (~24): `Root`, `Hitbox`, `Torso` (`Navy`), `Shoulders` (`NavyLight`),
`ChestGem` (`Starlight`), `Swirl` (`Navy`), `SwirlTip` (`Starlight`),
`Head` (`Navy`), `Crescent` (`MoonGrey`), `Crack` (`Glow`),
`Hand_R`/`Hand_L` (`NavyLight`), `Claws_R`/`Claws_L` (`Glow`),
`OrbitRock1`..`OrbitRock6` (`Navy`, each its own part with its pivot AT THE RING CENTRE
so a spin animation is one rotation per rock), `RockGems` (`Starlight`),
`Chips` (`NavyLight`).

**Seat** `Orbit_Seat` - the **crescent moon**, horns pointing up: a big `MoonGrey`
crescent about 7 wide and 1.4 thick (`crescent()`), `MoonShadow` on its inner face, and
five `Starlight` diamonds set into it - one at each horn tip and three along the belly.

---

## 9. Tick - Toyland - wind-up soldier, 9 standing / 4 × 3

**The sheet.** A tin toy robot.  The body is a **red barrel** with a big **cream
five-point star** painted on the chest, a **blue collar band** at the top and a **blue
belt band** at the bottom, and **brass bolts** round both bands.  The head is a **cream
dome** on a cream collar, with a **cyan visor slot** across the front - that slot is the
only eye.  On top: a small brass finial and a **yellow bulb**.  On its back, a
**huge brass wind-up key**: a shaft and two big flat ring loops, like a clock key, about
2.2 studs across.  Arms: a **blue shoulder ball**, a **cream upper arm**, a **red mitten
fist** - one raised, one down.  Legs are stubby **blue** with a brass bolt at the knee
and **big rounded blue feet**.

**Parts** (~26): `Root`, `Hitbox`, `Body` (`Red`), `Star` (`Cream`, a `star_pts` plate
on the chest), `CollarBand`/`BeltBand` (`Blue`), `Bolts` (`Brass`, all of them one part),
`Head` (`Cream`), `Visor` (`VisorGlow`), `Finial` (`Brass`), `Bulb` (`Bulb`),
`Key` (`Brass`, pivot ON ITS OWN SHAFT AXIS so it can turn in place - this is the
signature), `Shoulder_R/L` (`Blue`), `ArmUpper_R/L` (`Cream`), `ArmLower_R/L` (`Cream`),
`Fist_R/L` (`Red`, `mitten()`), `Leg_R/L` (`Blue`), `Knee_R/L` (`Brass`),
`Foot_R/L` (`Blue`).

**Seat** `Tick_Seat` - a **stack of ABC blocks**: five or six 1.5-stud cubes in `Red`,
`Blue`, `BlockGreen`, `BlockYellow` and `Cream`, stacked two high and slightly askew,
each with a raised `Cream` letter (`face_text`) on its face - A, B, C, and a couple of
plain ones.  A small `Red`/`Cream` ball rests beside them.

---

## 10. Scan - Neon - laser sentinel, 8 tall, hovers at 4, 6 × 6

**The sheet.** A hovering angular drone, gloss black with hard neon strips.  The head is
a **wedge** - an arrowhead pointing +Y - with a **wide magenta visor bar** across its
front and **two antenna spikes** on top.  The body is a **hexagonal core plate** with a
**white glowing hex centre**, ringed by a cyan strip and a magenta strip.  **Two floating
shoulder pods** hang either side, each an angular black shield with a **cyan inner face**
and a **magenta edge**, joined to the core by a short black link.  **Four long angular
fins** hang below and behind, each with a magenta strip down one edge and a cyan strip
down the other.  An **under-lens** on the belly is where the scan cone comes from.
Nothing touches the ground.

Every neon piece is a separate part so the whole thing can go dark when it sleeps -
`SLEEP_LOOK` darkens `Magenta`, `Cyan` and `Core` together.

**Parts** (~22): `Root`, `Hitbox`, `Core` (`Body`), `CoreRing` (`Cyan`),
`CoreGlow` (`Core`), `CoreEdge` (`Magenta`), `Head` (`Body`), `Visor` (`Magenta`),
`Antenna` (`Body`), `Link_R`/`Link_L` (`Body`), `Pod_R`/`Pod_L` (`Body`),
`PodFace_R`/`PodFace_L` (`Cyan`), `PodEdge_R`/`PodEdge_L` (`Magenta`),
`Fin_FR`/`Fin_FL`/`Fin_BR`/`Fin_BL` (`Body`), `FinGlow` (`Magenta`, one part carrying
every fin's strip is fine only if the fins do not move independently - otherwise one
per fin), `Lens` (`Cyan`).

**Seat** `Scan_Seat` - the **charging pad**: a dark `PadDark` hexagonal plate about 5
across and 0.5 thick, a **glowing cyan ring** set into its top face, cable trim running
off one side, and three or four `PadRock` rocks around it with thin magenta strips - the
same rocks the sheet shows it resting among.
