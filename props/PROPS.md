# Plot prop set - build contract

27 decorative / functional props for a Roblox plot game, built in Blender through
`proplib.py`, meant to read as **one coherent toy set** across four families:

| Family | Props |
|---|---|
| Defence | `IronWall` `BarbedStoneWall` `GlassCase` `Catapult` |
| Lighting | `Lantern` `TikiTorch` `NeonSign` |
| Garden | `Sunflower` `Bush` `Tree` `Scarecrow` `Wheelbarrow` `WateringCan` `HayBale` `Fountain` `Pond` |
| Fun | `Trampoline` `Slide` `Seesaw` `HotTub` `DJBooth` `DanceFloor` `Hammock` `BeanBag` `TV` `VendingMachine` `ArcadeCabinet` |

These are **source assets only** - nothing here is wired into a Roblox place.
`proplib.py` is `defenses/defenselib.py` plus the decorative primitives, so this set is a
deliberate stylistic match for the existing defence props.

## Space & scale

| | |
|---|---|
| Units | 1 Blender unit = 1 Roblox stud |
| Up axis | **+Z**, ground plane at **z = 0** |
| Facing | every prop faces **+Y** - its front, its screen, its readable side, the side a player walks up to |
| Centring | centred on **x = 0, y = 0** unless the brief says otherwise |
| Roblox export | `(x, y, z)_rbx = (x, z, −y)_blender` (a pure rotation - the lib handles it, don't pre-rotate) |
| Reference | an R15 avatar is **5 studs tall, ~2 wide, ~1 deep**; a seat is ~2.2 up, a doorway ~7 |
| Wall tile | walls are **8 wide** and stop cleanly at `x = ±4` so copies butt with no gap |

> **The +X / screen-left trap.** Renders look at the prop from the +Y side, so the camera
> is looking down −Y and **+X appears on the LEFT of the frame**. Anything you think of as
> "on the right as I face it" must be built at **negative x**. `D.stroke_text()` already
> handles this for lettering - it lays glyphs out along −X so they read correctly from the
> front. Mostly-symmetric props don't care; a ladder, a coin slot or an arrow does.

## Style

Chunky, low-poly, **flat shaded**, readable in silhouette from 40 studs away - Roblox
toy-plastic, not realism. Large forms first, one or two levels of detail on top, no fine
greebling that vanishes at distance. Prefer `beveled_box` over raw cubes for anything seen
up close: the small highlight on a chamfer is what sells the plastic-toy look.

Two adjacent parts must differ in **value**, not just hue, or the silhouette muddies.
Aim for 3–6 distinct colours per prop - more than that and it reads as noise.

Every part carries a Roblox material. Reach for `"Wood"`/`"WoodPlanks"` on timber,
`"Metal"`/`"DiamondPlate"`/`"CorrodedMetal"` on steel, `"Slate"`/`"Concrete"`/`"Cobblestone"`
on masonry, `"Grass"`/`"LeafyGrass"` on foliage, `"Fabric"`/`"Leather"` on soft goods,
`"Glass"` on panes, `"Neon"` on anything that glows.

## Palette

Use `D.C("key")` - it returns the hex and throws on a typo. Keys (`D.PALETTE` has all 79):

```
metal_dark metal_mid metal_light steel_bright iron_dark iron_mid iron_rust brass copper
gold chrome | wood_light wood_mid wood_dark bamboo log_bark plank_grey | stone_light
stone_mid stone_dark concrete dirt sand gravel | leaf_light leaf_mid leaf_dark leaf_blue
grass moss petal_yellow petal_orange seed_brown stem_green straw hay flower_pink flower_red
flower_white | cloth_red cloth_blue cloth_teal cloth_cream cloth_purple cloth_orange
rubber_black rope canvas | water_shallow water_mid water_deep glass glass_tint foam |
neon_pink neon_cyan neon_lime neon_orange neon_purple neon_yellow neon_red neon_blue
neon_green lamp_warm flame_core flame_mid flame_tip | plastic_red plastic_blue
plastic_yellow plastic_green plastic_white plastic_black screen_dark screen_glow
accent_orange warning_yellow danger_red terracotta
```

A literal hex string is fine too when nothing in the palette fits - but prefer a key.

## Transparency and glow

- `new_obj(..., transparency=t)` uses the **Roblox** convention: `0` solid, `1` invisible.
  Glass panes **0.45–0.6**, water **0.35–0.5**, a lit screen 0.
- `rbx_material="Neon"` makes a part emissive. Pass `emit=` to tune the strength:
  **0.6–1.5 only**. Above ~1.6 the render clips to white and the colour is lost.
- A glass box needs something *inside* it or it reads as an empty rectangle. A water
  surface needs a rim or a basin around it or it reads as a floating sheet.

## Hard rules

1. **No `bpy.ops`, ever** - only `proplib` primitives and `bmesh`.
2. Every mesh is finished with `D.new_obj(part_name, bm, c, hex, rbx_material=...)`.
3. **Deterministic**: `random.Random(seed)` only - never bare `random.*`, never time/date.
4. **Nothing below `z = 0`** unless `NOTES` explicitly says the prop needs a pit.
   Water sits in a raised basin, not a hole.
5. Respect your tri budget (checked by `D.report()`), and keep part count sane -
   merge everything that shares a colour and material into ONE bmesh / one object.
6. Distinct part names, no spaces. The lib prefixes them with the collection name.
7. `build(D)` must be **idempotent** - `D.clear_collection(COLLECTION)` on the first line
   guarantees it. Return the collection.
8. The script must pass `py dryrun.py build_<yours>.py` with no errors.

## Module shape

One file per prop, `build_<snake_case>.py`, next to `proplib.py`:

```python
"""One-line description of the prop."""
import bmesh, math

COLLECTION = "Turret"
NOTES = "Anything the installer needs: footprint, what sits where, how it is meant to be used."
PIVOTS = {"ArmPivot": (0.0, -0.6, 2.4)}       # optional: hinge/rotation points for rigging
STATES = {"Open": 0.0, "Shut": -1.2}           # optional: named offsets/angles for moving parts
VARIANTS = {"A": {"name": "Tall", "x": -5.0},  # required IF your brief asks for variants
            "B": {"name": "Short", "x": 0.0}}

def build(D):
    """D is the imported proplib module.  Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    bm = bmesh.new()
    D.beveled_box(bm, (-3, -3, 0), (3, 3, 1.2), bevel=0.12)
    D.new_obj("BasePlate", bm, c, D.C("metal_dark"), rbx_material="Metal")
    # ... more parts ...
    return c
```

### Variants

Some briefs ask for several versions of the prop (three trees, three lanterns…). Build
them **all into the one collection**, standing side by side along X at the offsets you
declare in `VARIANTS`, and prefix every part name with the variant letter:
`A_Trunk`, `A_Crown`, `B_Trunk`… Anything shared by all variants needs no prefix. Each
variant is still built as if it were centred on its own origin, then offset - so a
variant is separable by name prefix and drops into a game at its own origin.

Leave **3–4 studs of clear air** between variants so the hero render reads them apart.

## `proplib` API

`D` is the module. Every primitive **appends into an existing bmesh** and returns its new
verts, so one bmesh can hold many primitives that become a single object.

### Objects & materials
- `D.coll(name)` / `D.clear_collection(name)`
- `D.C(key)` → palette hex, throws on a typo. `D.PALETTE` is the dict.
- `D.new_obj(name, bm, c, hex, rbx_material="SmoothPlastic", transparency=0.0, metallic=0.0, roughness=0.55, smooth=False, emit=None)`

### Solids
- `D.box(bm, lo, hi, rot=None)` - axis-aligned box between two corners
- `D.cube(bm, loc, size, rot=None)` - `size` scalar or `(sx, sy, sz)`
- `D.beveled_box(bm, lo, hi, bevel=0.1, segments=1, rot=None)` - the workhorse chamfered box
- `D.cyl(bm, a, b, radius, segs=12, r2=None, cap=True)` - cylinder a→b; `r2` truncates it to a cone
- `D.cone(bm, base, tip, r_base, r_tip=0.0, segs=8)`
- `D.spike(bm, base, tip, r, segs=6, tip_r=0.0)` - `segs=4` is a hard pyramid spike
- `D.pyramid(bm, center, size, height, rot=None)`
- `D.uvsphere(bm, loc, radius, segs=12, rings=8, rot=None, scale=(1,1,1))`
- `D.ico(bm, loc, radius, subdiv=1, rot=None, scale=(1,1,1))`
- `D.torus(bm, loc, major, minor, rot=None, seg_major=16, seg_minor=6)`
- `D.tube(bm, points, radii, segs=8, cap=True)` - lofted polyline, per-point radius (0 = a point)
- `D.rock(bm, loc, radius, seed=1, jitter=0.30, subdiv=1, scale=(1,1,1), rot=None)` - faceted boulder
- `D.stone_block(bm, lo, hi, seed=1, jitter=0.06, bevel=0.06, rot=None)` - masonry block
- `D.prism(bm, pts2d, z0, z1, matrix=None)` - extrude a simple closed polygon. The workhorse.
- `D.wedge(bm, lo, hi, rise='+Y', matrix=None)` - ramp filling the box; `rise` names the tall edge
- `D.lathe(bm, profile, segs=12, matrix=None, cap=True, phase=0.0)` - revolve a `(radius, z)`
  profile about Z. Radius 0 = a pole (bowl bottom / cone tip). Pots, bowls, lanterns,
  drums, fountain tiers, bollards, tyres, cans.
- `D.ngon_face(bm, pts2d, z, matrix=None, flip=False)` - one flat n-gon; the cheapest water surface
- `D.sag_sheet(bm, lo, hi, sag=0.35, nx=5, ny=5, thickness=0.08, matrix=None)` - a sheet
  pinned at its rim and drooping in the middle: trampoline mat, hammock, bean-bag top, canvas
- `D.foliage(bm, loc, radius, seed=1, blobs=4, spread=0.55, jitter=0.26, subdiv=1, scale=(1,1,1), flatten=1.0)`
  - a clump of jittered blobs: bush, tree crown, hedge lump. ~80 tris per blob at `subdiv=1`
- `D.slat_run(bm, lo, hi, count, gap_frac=0.35, axis='x', bevel=0.03)` - evenly spaced slats
  filling a box: pickets, bench slats, crate sides, vents, grilles
- `D.rope(bm, a, b, sag=0.5, radius=0.06, n=10, segs=5)` - hanging rope / cable / string light
- `D.coil(bm, base, top, radius, turns=3.0, wire_r=0.05, n=28, segs=5, phase=0.0)` - a helix
- `D.barbed_wire(bm, points, wire_r=0.05, segs=4, barb_every=2, barb_len=0.22, seed=1)`
- `D.stroke_text(bm, text, origin, height=1.0, radius=0.06, segs=5, plane='XZ', center=True, flip=False)`
  - neon tube lettering. `plane='XZ'` stands on a wall, `'XY'` lies on the floor. A-Z 0-9
  and `! ? . , - + ' $ % & * / :` . Size the backing panel with `D.text_width(text, height)`.

### Profiles & layouts (plain lists, no bmesh)
- `D.rounded_rect_pts(w, h, r, segs=3, center=(0,0))` - screens, bezels, signs, tabletops
- `D.arc_pts(center, radius, a0_deg, a1_deg, n=8, ry=None)` - arcs / ellipses
- `D.ngon_pts(n, radius, phase=0.0, center=(0,0))`, `D.star_pts(n, r_out, r_in, phase=0.0, center=(0,0))`
- `D.teardrop_pts(w, h, n=10, center=(0,0))` - leaf / petal / flame outline, pointed at +Y
- `D.chevron_pts(width, depth, thickness, tip_at=+1)` - a `>` arrow pointing +Y
- `D.ring_positions(n, radius, phase=0.0, center=(0,0))` - bolts, petals, lights, fence posts
- `D.grid_positions(nx, ny, sx, sy, center=(0,0), stagger=False)` - a centred lattice of `(x, y)`
- `D.catenary_pts(a, b, sag, n=10)`, `D.helix_pts(base, top, radius, turns, n, phase, radius2)`

### Transforms
- `D.rot_euler(rx=0, ry=0, rz=0)` - **degrees** → 4×4, XYZ order. Pass as `rot=` / `matrix=`.
- `D.place(loc=(0,0,0), rot=None, scale=1.0)` - translate @ rotate @ scale, composed for you
- `D.aim(direction, up=(0,0,1))` - 4×4 taking local +Z onto `direction`
- `D.xform(bm, verts, matrix)` / `D.translate(bm, verts, offset)` - move verts a primitive returned
- `D.mirror_x(bm, verts)` - duplicate geometry mirrored across x = 0

### Inspection
- `D.report(coll)` → `{parts, tris, size_studs, min_z, per_part}`; `D.bounds(coll)`; `D.manifest([...])`

## Gotchas

- `D.prism` needs a **simple** (non-self-intersecting) polygon - a bow-tie makes garbage.
- `beveled_box` clamps `bevel` to 40 % of the smallest dimension, so a 0.2-thick plate
  silently gets a 0.08 chamfer. That's intended.
- The verts `beveled_box` returns are the **post-bevel** ones - don't cache verts across it.
- `torus` (192 tris) and `uvsphere` (168) are expensive at their defaults. Drop `seg_major`,
  `segs`, `rings` hard; `D.prism(D.ngon_pts(...))` is a much cheaper ring.
- Flat shading means a 12-segment cylinder looks 12-sided. That's the house style - 8–12
  segments for anything chunky, 6 for small bolts, 5 for wires.
- `D.lathe` builds one closed shell. To make a *hollow* vessel, run the profile up the
  outside, over the rim and back down the inside, ending at radius 0 on the floor.
- Composition order matters: `D.place(loc, rot)` is translate-then-rotate-about-the-origin
  reading right to left, i.e. the rotation happens **first**, about `(0,0,0)`, then the
  translation. Build a sub-assembly around the origin, then place it.
- A primitive's `rot=` argument rotates about **that primitive's own centre**, not the origin.

## Checking your work

```bash
cd C:/Users/shrey/OneDrive/Documents/RobloxGames/props
py dryrun.py build_<yours>.py
```

`dryrun.py` runs `build()` without Blender: it catches syntax errors, API typos, bad
palette keys, bad hex/material/transparency, duplicate part names, a missing
`clear_collection`, geometry below the ground plane and gross scale mistakes. Its
bounding box is approximate (it does not apply `rot=`/`matrix=`), so treat it as a smell
test - the real build in Blender is the source of truth and is run centrally.
