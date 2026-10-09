# Defence prop set - build contract

Five props, built in Blender through `defenselib.py`, meant to read as **one coherent set**:
`Turret`, `WoodenWall`, `StoneWall`, `SpikeTrap`, `BoostPad`.

Nothing here is wired into any Roblox place yet - these are source assets only.

## Space & scale

| | |
|---|---|
| Units | 1 Blender unit = 1 Roblox stud |
| Up axis | **+Z**, ground plane at **z = 0** |
| Facing | every prop faces **+Y** - the direction attackers come from. A turret's barrel, a boost pad's arrows and a wall's outer/weathered face all point +Y. |
| Centring | centred on **x = 0, y = 0** unless the brief says otherwise |
| Roblox export | `(x, y, z)_rbx = (x, z, −y)_blender` (a pure rotation - handled by the lib, don't pre-rotate) |
| Reference scale | an R15 avatar is **5 studs tall, ~2 wide, ~1 deep**. `defenselib.build_stage()` puts a red blockout dummy at `(0, −6, 0)` in renders. |
| Tile | the standard footprint is **8 × 8 studs** (`defenselib.TILE`) |

## Style

Chunky, low-poly, **flat shaded**, readable in silhouette from 40 studs away - Roblox
tower-defence toy-fortress, not realism. Large forms first, one or two levels of detail on
top, no fine greebling that vanishes at distance. Prefer chamfered boxes
(`beveled_box`) over raw cubes for anything a player sees up close: the small highlight on
a chamfer is what sells the plastic-toy look.

Every part gets a colour from the shared palette. Two adjacent parts must differ in
**value**, not just hue, or the silhouette muddies.

## Shared palette

| Role | Hex | Notes |
|---|---|---|
| Metal dark | `3b4350` | frames, undersides, shadow parts |
| Metal mid | `6c7789` | main steel |
| Metal light | `9aa7b8` | highlights, barrels |
| Wood light | `c08a4e` | plank faces |
| Wood mid | `8a5a2b` | plank sides |
| Wood dark | `6b4423` | frame, shadow gaps |
| Stone light | `b9b3a7` | top-lit blocks |
| Stone mid | `8f8a80` | body blocks |
| Stone dark | `6b675f` | recesses, mortar |
| Moss | `5f8f4a` | weathering accents |
| Accent orange | `ff8a3d` | team/tech accent, warning stripes |
| Warning yellow | `f2c13d` | hazard chevrons |
| Danger red | `d9443c` | spikes' warning band, danger trim |
| Energy cyan | `4dd2ff` | use with `rbx_material="Neon"` for glow |
| Rubber black | `2a2d33` | treads, grips, gaskets |
| Steel bright | `d5dbe4` | spike tips, polished edges |

## Hard rules

1. **No `bpy.ops`, ever.** Only `defenselib` primitives + `bmesh`. (`bpy.ops` needs a
   context override in this MCP session and will fail.)
2. Every mesh is created with `D.new_obj(part_name, bm, c, hex, rbx_material=...)` - that
   handles triangulation, flat shading, UVs and the `rbx_*` custom props.
3. **Deterministic**: `random.Random(seed)` only - never bare `random.*`, never `Date`/time.
4. Nothing dips below `z = 0` except parts the brief explicitly sinks (say so in `NOTES`).
5. Respect the tri budget in your brief. Check it with `D.report("<Collection>")`.
6. Distinct part names, no spaces (the lib prefixes them with the collection name).
7. Walls must **tile**: the geometry stops cleanly at `x = ±4` so two copies butt together
   with no gap and no overlap.

## Module shape

Each prop is one file, `build_<prop>.py`, next to `defenselib.py`:

```python
"""One-line description."""
import bmesh

COLLECTION = "Turret"
NOTES = "Anything the installer needs to know."
PIVOTS = {"YawPivot": (0.0, 0.0, 2.4)}      # optional, see your brief
STATES = {}                                  # optional, see your brief

def build(D):
    """D is the imported defenselib module. Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    bm = bmesh.new()
    D.beveled_box(bm, (-3, -3, 0), (3, 3, 1.2), bevel=0.12)
    D.new_obj("BasePlate", bm, c, "3b4350")
    # ... more parts ...
    return c
```

`build(D)` must be **idempotent** - calling it twice leaves the same result, which
`clear_collection` on the first line guarantees.

## `defenselib` API

Import is handled for you; `D` is the module. All primitives **append into an existing
bmesh** and return their new verts, so one `bmesh` can hold many primitives that become a
single object.

### Objects & materials
- `D.coll(name)` → collection (created if missing)
- `D.clear_collection(name)` → wipe it
- `D.new_obj(name, bm, c, hex, rbx_material="SmoothPlastic", transparency=0.0, metallic=0.0, roughness=0.55, smooth=False)` → object.
  `rbx_material` is a Roblox `Enum.Material` name - `"SmoothPlastic"`, `"Plastic"`,
  `"Metal"`, `"DiamondPlate"`, `"Wood"`, `"WoodPlanks"`, `"Slate"`, `"Concrete"`,
  `"Neon"`, `"Grass"`. `"Neon"` also makes it emissive in renders.

### Solids
- `D.box(bm, lo, hi, rot=None)` - axis-aligned box between two corners
- `D.cube(bm, loc, size, rot=None)` - `size` is a scalar or `(sx, sy, sz)`
- `D.beveled_box(bm, lo, hi, bevel=0.1, segments=1, rot=None)` - chamfered box
- `D.cyl(bm, a, b, radius, segs=12, r2=None, cap=True)` - cylinder from point `a` to `b`; `r2` makes it a truncated cone
- `D.cone(bm, base, tip, r_base, r_tip=0.0, segs=8)`
- `D.spike(bm, base, tip, r, segs=6, tip_r=0.0)` - `segs=4` is a hard pyramid spike
- `D.pyramid(bm, center, size, height, rot=None)` - square pyramid standing on `center`
- `D.uvsphere(bm, loc, radius, segs=12, rings=8, rot=None, scale=(1,1,1))`
- `D.ico(bm, loc, radius, subdiv=1, rot=None, scale=(1,1,1))`
- `D.torus(bm, loc, major, minor, rot=None, seg_major=16, seg_minor=6)`
- `D.tube(bm, points, radii, segs=8, cap=True)` - lofted polyline, `radii` per point (0 = a point)
- `D.rock(bm, loc, radius, seed=1, jitter=0.30, subdiv=1, scale=(1,1,1), rot=None)` - faceted boulder
- `D.stone_block(bm, lo, hi, seed=1, jitter=0.06, bevel=0.06, rot=None)` - masonry block with nudged corners
- `D.prism(bm, pts2d, z0, z1, matrix=None)` - extrude a simple closed polygon from `z0` to `z1`. The workhorse.
- `D.wedge(bm, lo, hi, rise='+Y', matrix=None)` - ramp filling the box; `rise` names the tall edge (`'+Y'`, `'-Y'`, `'+X'`, `'-X'`)

### Profiles & layouts (return plain lists, no bmesh)
- `D.chevron_pts(width, depth, thickness, tip_at=+1)` - a `>` arrow profile pointing +Y, for `prism`
- `D.ngon_pts(n, radius, phase=0.0, center=(0,0))`
- `D.ring_positions(n, radius, phase=0.0, center=(0,0))` - bolt heads, spike rings, lights
- `D.grid_positions(nx, ny, sx, sy, center=(0,0), stagger=False)` - centred lattice of `(x, y)`

### Transforms
- `D.rot_euler(rx=0, ry=0, rz=0)` - **degrees** → 4×4, XYZ order. Pass as the `rot=` / `matrix=` arg.
- `D.aim(direction, up=(0,0,1))` - 4×4 taking local +Z onto `direction`
- `D.xform(bm, verts, matrix)` - apply a 4×4 to verts a primitive returned
- `mathutils.Matrix.Translation(v)` composes with the above using `@`

### Inspection
- `D.report(coll_name)` → `{parts, tris, size_studs, min_z, per_part}`
- `D.bounds(coll_name)` → `(min_vec, max_vec)`
- `D.manifest(coll_names)` → per-part Roblox appearance rows

### Rendering (the orchestrator runs these - you don't)
- `D.build_stage()`, `D.render(coll_names, path, yaw_deg=, pitch_deg=, dist_mul=)`

## Gotchas

- `D.prism` needs a **simple** (non-self-intersecting) polygon; it triangulates fine but
  will produce garbage from a bow-tie.
- `beveled_box` clamps `bevel` to 40 % of the smallest dimension, so a 0.2-thick plate
  silently gets a 0.08 chamfer - that's intended.
- The verts `beveled_box` returns are the *post-bevel* ones; don't cache verts across it.
- `torus` and `uvsphere` are expensive (192 / 168 tris at defaults). Drop `seg_major`,
  `segs` and `rings` hard, or use `D.prism(D.ngon_pts(...))` for a cheap ring.
- Flat shading means a 12-segment cylinder looks 12-sided. That is the house style -
  8–12 segments for anything chunky, 6 for small bolts.
