# Plot prop set - Blender source

27 decorative and functional props for a Roblox plot game, built procedurally in Blender.

Built 2026-09-09. Blender file: `props.blend` (Blender 5.2 LTS).
**Installed 2026-09-10** into the New Map Cucumber Game place under `ServerStorage.Builds`,
together with the 5 props from `../defenses/` - see [Installed into Roblox](#installed-into-roblox-2026-09-10)
at the end. No gameplay code references them yet; they are a library to place from.

**322 parts / 37 669 tris across 27 props.** An R15 avatar is 5 studs tall for scale, and
appears in every render as the red blockout dummy.

This set is a deliberate stylistic match for `../defenses/` - `proplib.py` is that set's
`defenselib.py` plus the decorative primitives, so the two read as one family.

---

## The props

### Defence

| Prop | Collection | Parts | Tris | Size (x × y × z studs) |
|---|---|---:|---:|---|
| Iron wall | `IronWall` | 12 | 1208 | 8.0 × 1.6 × 8.0 |
| Barbed-wire stone wall | `BarbedStoneWall` | 9 | 2220 | 8.3 × 2.3 × 7.6 |
| Glass display case | `GlassCase` | 10 | 1196 | 4.0 × 3.0 × 6.0 |
| Catapult | `Catapult` | 12 | 1708 | 4.8 × 6.6 × 5.1 |

Both walls **tile seamlessly** at `x = ±4` - proven in `renders/IronWall_tiled.png` and
`renders/BarbedStoneWall_tiled.png`. Half-width corner posts on the iron wall butt into one
full pier; the stone wall's running bond, capstones, arms and all three wire strands
continue across the seam with no gap and no doubled geometry.

### Lighting

| Prop | Collection | Parts | Tris | Size | Variants |
|---|---|---:|---:|---|---|
| Lanterns | `Lantern` | 19 | 1538 | 11.0 × 1.4 × 4.6 | post / paper / garden |
| Tiki torches | `TikiTorch` | 20 | 1388 | 11.5 × 1.8 × 5.5 | bamboo / tiki head / brazier |
| Neon signs | `NeonSign` | 17 | 1804 | 23.6 × 1.3 × 6.3 | OPEN / THIS WAY / CUCUMBER marquee |

Neon lettering is real tube geometry from a stroke font in `proplib` - not a texture - so it
survives any scale. Emission is held at 1.1–1.3; above ~1.6 the colour clips to white.

### Garden

| Prop | Collection | Parts | Tris | Size | Variants |
|---|---|---:|---:|---|---|
| Sunflowers | `Sunflower` | 16 | 1294 | 13.1 × 2.0 × 4.6 | tall / medium+bud / clump of 3 |
| Bushes | `Bush` | 15 | 850 | 16.8 × 3.0 × 2.4 | shrub / box hedge / flowering |
| Trees | `Tree` | 11 | 1344 | 23.9 × 6.0 × 12.9 | oak 11 / pine 12.9 / sapling 6.5 |
| Scarecrow | `Scarecrow` | 11 | 1406 | 3.4 × 1.3 × 5.6 | - |
| Wheelbarrow | `Wheelbarrow` | 6 | 856 | 2.0 × 3.9 × 2.2 | - |
| Watering can | `WateringCan` | 7 | 858 | 1.6 × 3.4 × 2.0 | - |
| Hay bales | `HayBale` | 10 | 1294 | 15.9 × 4.2 × 2.8 | round / square / stack of 3 |
| Fountain | `Fountain` | 10 | 1910 | 6.9 × 7.1 × 4.2 | - |
| Pond with fish | `Pond` | 15 | 1565 | 9.2 × 6.6 × 2.3 | - |

The **pond and the fountain both sit entirely above ground** - the water is held in a raised
rim / basin wall, so either can be dropped onto flat terrain with no excavation. The pond's
3 koi, its lily pads and its lotus flowers are separate objects (prefixed `Fish` / `Lily`)
so a game can animate them.

### Fun

| Prop | Collection | Parts | Tris | Size | Variants |
|---|---|---:|---:|---|---|
| Trampoline | `Trampoline` | 7 | 1234 | 8.0 × 8.0 × 1.6 | - |
| Slide | `Slide` | 6 | 1710 | 3.6 × 11.1 × 6.0 | - |
| Seesaw | `Seesaw` | 9 | 944 | 7.9 × 1.6 × 3.2 | - |
| Hot tub | `HotTub` | 9 | 1504 | 6.5 × 7.7 × 3.0 | - |
| DJ booth | `DJBooth` | 11 | 2060 | 8.1 × 2.8 × 4.2 | - |
| Dance floor | `DanceFloor` | 20 | 1080 | 8.0 × 8.0 × 0.4 | - |
| Hammock | `Hammock` | 6 | 1216 | 10.6 × 2.2 × 3.2 | - |
| Bean bags | `BeanBag` | 15 | 1122 | 14.2 × 2.9 × 1.8 | pouf / slouch / ottoman |
| TV | `TV` | 14 | 864 | 6.4 × 1.9 × 4.9 | - |
| Vending machine | `VendingMachine` | 12 | 1886 | 3.2 × 1.7 × 6.6 | - |
| Arcade cabinet | `ArcadeCabinet` | 13 | 1610 | 2.8 × 3.0 × 6.4 | - |

The **dance floor is built to be animated**: its 16 tiles are separate Neon objects named
`Tile_r<row>_c<col>`, row 0 at the back (−y), col 0 at the +x edge. Recolour them at runtime.

---

## Conventions

- 1 Blender unit = 1 Roblox stud; **Z up**, ground at **z = 0**.
- Every prop **faces +Y** - its front, screen, readable side, the side a player walks up to.
- Roblox export is a pure rotation: `(x, y, z)_rbx = (x, z, −y)_blender`.
- Nothing sits below `z = 0` (largest excursion in the whole set is −0.015 studs).
- Flat shaded, box-projected UVs at 2 studs per tile, triangulated.
- Per-object custom props `rbx_hex` / `rbx_material` / `rbx_transparency` carry the Roblox
  appearance, so an installer can rebuild each prop out of Parts or MeshParts without
  re-deriving the look. `manifest.json` has every row.

> **The +X / screen-left trap.** Renders view the prop from the +Y side, so the camera looks
> down −Y and **+X appears on the LEFT of the frame**. Anything "on the right as I face it"
> is at negative x. `D.stroke_text()` handles this for lettering automatically.

### Variants

Props marked *Variants* build all three into one collection, standing side by side along X,
with every part name prefixed `A_` / `B_` / `C_`. Each module exports a `VARIANTS` dict
giving each one's name and x offset, so a variant is separable by name prefix and drops
into a game at its own origin:

```
Lantern     A PostLantern x-5.2   B PaperLantern x 0.0   C GardenLantern x+4.6
TikiTorch   A BambooTorch x+5.0   B TikiHead     x 0.0   C Brazier       x-5.0
NeonSign    A OpenSign    x+9.8   B ArrowSign    x+2.3   C Marquee       x-7.4
Sunflower   A Tall        x+5.0   B Medium       x 0.0   C Clump         x-5.4
Bush        A Shrub       x+7.0   B Hedge        x 0.0   C FloweringBush x-7.0
Tree        A Oak         x+10.0  B Pine         x 0.0   C Sapling       x-9.5
HayBale     A RoundBale   x-6.4   B SquareBale   x 0.0   C Stack         x+6.4
BeanBag     A Pouf        x+6.0   B Slouch       x 0.0   C Ottoman       x-5.8
```

---

## Rigging data the build scripts emit

Each module optionally exports `PIVOTS` (hinge / anchor points) and `STATES` (named angles
or offsets in degrees / studs). All of it is folded into `manifest.json`.

| Prop | Moving group | Pivot | States |
|---|---|---|---|
| `Catapult` | parts named `Arm*` | `ArmPivot (0, −1.30, 2.30)`, axis along X | `Loaded 0` → `Fired −92` (negative swings the bucket forward over the top toward +Y) |
| `Seesaw` | parts named `Plank*` | `PlankPivot (0, 0, 1.35)`, axis along X | `RedDown +12` / `Level 0` / `BlueDown −12`; built in `RedDown` |
| `Trampoline` | parts named `Mat*` | `MatCentre (0, 0, 0.68)` | `Rest 0` / `Bottom −0.5` (studs down) |
| `VendingMachine` | delivery flap | `FlapHinge (0.47, 0.70, 1.58)`, `DropPoint (0.47, 0.36, 1.05)` | `FlapShut 0` / `FlapAjar −22` / `FlapOpen −78` |
| `ArcadeCabinet` | joystick, coin door | `JoystickPivot (0.62, 1.06, 2.74)`, `CoinDoorHinge (−1.16, 0.76, 1.25)` | `CoinDoorShut 0` / `CoinDoorOpen −100` |
| `DJBooth` | platters, tonearms, spot cans | `DeckA/BPlatter`, `DeckA/BTonearm`, `SpotA/B` | `ArmPlaying 0` / `ArmParked 20`; spot aims `−120` floor, `−100` crowd, `−55` sky |
| `DanceFloor` | 16 `Tile_r*_c*` | `FloorCentre`, `TileR0C0 (2.61, −2.61, 0.34)`, `TileR3C3 (−2.61, 2.61, 0.34)` | `On 0` / `Dim 0.45` / `Off 0.85` (transparency) |
| `TV` | screen | `ScreenSwivel (0, −0.10, 1.66)` | `Straight 0` / `TurnedLeft 20` / `TurnedRight −20` |
| `GlassCase` | - | `DisplayPoint (0, 0, 3.05)` - where the game drops the trophy | - |
| `Pond` | `Fish1..3`, `Lily*` | fish at z 0.34, `WaterSurface (0, 0, 0.50)` | - |
| `Fountain` | - | `BasinWaterTop z 0.72`, `BowlWaterTop z 2.50`, `JetOrigin z 3.62` | - |
| `HotTub` | - | `WaterSurface z 2.25`, `RimSeatFront`, `StepTop`, `PanelTop` | - |
| `Hammock` | bed | `RingPlusX / RingMinusX (±3.04, 0, 2.1)`, `BedLow (0, 0, 1.2)` | - |
| `Wheelbarrow` | - | `WheelAxle (0, 0.95, 0.55)`, `TubPivot (0, −0.25, 1.14)` | - |
| `Scarecrow` | - | `ArmCentre`, `CrowPerch`, `HatBase` | - |
| `Lantern` / `TikiTorch` / `Sunflower` | - | per-variant light / flame / flower-neck anchors | - |

---

## Files

| | |
|---|---|
| `proplib.py` | the primitive library: everything in `defenses/defenselib.py` plus a lathe, rounded-rect / arc / star / teardrop profiles, catenary rope, helices, barbed wire, sagging fabric, foliage clumps, slat runs and a stroke font for neon lettering |
| `PROPS.md` | the build contract: space, scale, facing, palette, module shape, full API reference, gotchas |
| `dryrun.py` | offline validator - runs a build script **without Blender** by faking `bpy`/`bmesh`/`mathutils` |
| `build_*.py` | one module per prop, each exporting `COLLECTION`, `NOTES`, `build(D)` and optionally `PIVOTS` / `STATES` / `VARIANTS` |
| `buildall.py` | orchestrator - reloads everything from disk, builds, reports, renders every sheet, exports FBX, dumps the manifest |
| `manifest.json` | every part's Roblox appearance (hex, material, transparency, tris) plus each prop's report, notes and rig data |
| `fbx/` | one FBX per prop, 27 files, Y-up / −Z-forward, 1 unit = 1 stud |
| `renders/` | a hero and a player's-eye angle per prop, two wall tiling proofs, four group contact sheets, and `_lineup_all.png` |
| `props.blend` | the saved scene |

## Rebuilding

From a blender-mcp session:

```python
exec(open(r"C:\Users\shrey\OneDrive\Documents\RobloxGames\props\buildall.py").read())
print(summary(build_all()))    # build every prop; parts / tris / bbox / min_z per prop
render_each()                  # hero render per prop
render_all()                   # every sheet
manifest_json(); export_all(); save()
```

Everything reloads from disk on each call, so editing a `build_*.py` and re-running picks
the change up with no Blender restart. `build_all("Tree")`, `build_all("garden")` and
`render_each("Fountain")` all work - a prop name, a list, or a group name.

Note that each `execute_blender_code` call gets a fresh namespace, so re-`exec` `buildall.py`
at the top of every call.

## Checking a build script without Blender

```bash
cd C:/Users/shrey/OneDrive/Documents/RobloxGames/props
py dryrun.py build_tree.py     # or no argument to check every build_*.py
```

`dryrun.py` executes `build()` against a stand-in library that knows every real API name. It
catches syntax errors, calls to primitives that do not exist, palette-key typos, bad
hex/material/transparency values, duplicate part names, a missing `clear_collection`,
geometry below the ground plane and gross scale mistakes - all without touching Blender, so
many scripts can be validated in parallel. Its bounding box is approximate (it does not
apply `rot=`/`matrix=` transforms); the Blender build is the source of truth.

---

## Deviations from the original briefs (deliberate)

- **Seesaw** runs along **X**, not Y - 7.9 long in x, 1.6 deep in y. End-on to the viewer a
  seesaw is unreadable; side-on its tilted plank is the whole silhouette. "Faces +Y" is
  honoured in spirit: the readable side faces the player.
- **Hammock** is 10.6 wide rather than 8. The A-frame stands have to splay wider than the
  bed they carry, or the bed's rope ends foul the posts.
- **Pond** finished at 9.2 × 6.6 rather than 11 × 8, after its outline was jittered into an
  irregular natural blob instead of a regular polygon.
- **Catapult** `Fired` is **−92°**, not the +105° first specified. With the hinge at the
  back and the arm cocked back-and-up, −92 is the rotation that actually lands the beam on
  the padded stop bar; the sign convention is stated in its `NOTES`.
- **Catapult pose**: the first build modelled the arm raked back and *down* as briefed, and
  it read as a farm cart - the arm vanished behind the deck. It is now cocked back and *up*
  at ~42° so the arm is the silhouette.
- **Tri budgets**: 10 props finished over their per-prop budget, the largest being
  `BarbedStoneWall` at 2220 against 1700 (the extra bought the seam fix and readable barbs),
  `DJBooth` 2060/2000 and `VendingMachine` 1886/1700. The whole set is 37 669 tris, averaging
  1395 per prop, which is comfortable for a decorative set of this size, so the overruns were
  accepted rather than clawed back. `HayBale` was the one exception - 2002 against 1100 was
  pulled back to 1294.

## How this set was built

Each prop was authored against `PROPS.md` by a separate agent, validated offline with
`dryrun.py`, then built and rendered centrally in one Blender session. Every prop was then
**reviewed from its renders** - not its code - against the question "would a player
recognise this instantly from 40 studs away", and the defects found were fixed and rebuilt.
All 27 build with no errors and no geometry below ground.

---

## Installed into Roblox (2026-09-10)

All 27 props here **plus the 5 props from `../defenses/`** are installed in the
**New Map Cucumber Game** place (`87967102884366`) as Models under
**`ServerStorage.Builds`** - 32 models, 383 MeshParts.

Each FBX was uploaded through Open Cloud as a group-owned Model asset (group `14583228`),
loaded with `InsertService:LoadAsset`, then post-processed in Studio. Asset ids are
recorded in `props/fbx/asset-ids.json` and `defenses/fbx/asset-ids.json`.

### What the installer does to each prop

- Strips the `<Collection>.` prefix from every part name (`IronWall.Plates` → `Plates`).
- **Rotates 180° about Y.** Roblox's FBX importer applies a 180° yaw, so raw imports face
  backwards. After the correction a Blender point `(bx, by, bz)` lands at `(bx, bz, −by)`,
  which puts the prop's authored front (+Y in Blender) on **−Z in Roblox** - the standard
  Roblox forward direction.
- **Re-applies colour, material and transparency from `manifest.json`.** The FBX import
  loses all of it - every part arrives grey `Plastic` - so this step is not optional.
  Verified: 383/383 parts match the manifest exactly.
- Anchors every part, clears `PrimaryPart` and sets `WorldPivot` to the origin, so
  `model:PivotTo(CFrame.new(x, y, z))` places the prop with its footprint centred on
  `(x, z)` and its base sitting exactly on `y`. Every prop's min-Y is 0.

### Attributes on each model

| Attribute | Meaning |
|---|---|
| `AssetId` | the group-owned Model asset it was loaded from |
| `PropSet` | `plot` (27) or `defence` (5) |
| `Tris` | triangle count |
| `Notes` | the build script's `NOTES`, truncated to 900 chars |
| `Pivot_<Name>` | a `Vector3` hinge/anchor point, already converted to Roblox space |
| `State_<Name>` | a named angle (degrees) or offset (studs) for a moving group |
| `Variants` | JSON `{letter: {name, x}}` for the 8 multi-variant props |

So a script can find the catapult's hinge with
`model:GetAttribute("Pivot_ArmPivot")` and its fired angle with
`model:GetAttribute("State_Fired")` without consulting this document.

### Re-running the install

`upload-batch.ps1` (fires all the Open Cloud create requests, then polls them together)
and `make_install.py` (merges both manifests + both asset-id maps into one payload) were
session scratch scripts. The durable inputs are the two `manifest.json` files and the two
`fbx/asset-ids.json` files - the assets are already uploaded, so a re-install only needs
`InsertService:LoadAsset` plus the yaw/appearance/pivot pass described above.
