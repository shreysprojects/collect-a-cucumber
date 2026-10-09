# Cucumber set - Blender source

**57 models across 8 biomes** for the cucumber game, built procedurally in Blender from a
set of reference sheets. Built 2026-09-13. Blender file: `cucumbers.blend` (Blender 5.2).

**285 parts / 139 538 tris.** All 57 are **installed in the Place1 Studio place** - see
[Installed into Roblox](#installed-into-roblox-2026-09-13) at the end.

Every model is a chunky low-poly toy: flat shaded, 3–6 colours, and speckled with the
raised light squares that tie the whole set together. An R15 avatar is 5 studs tall and
stands in every hero render for scale.

| Biome | Models |
|---|---|
| grass | `SlicedCucumber` `SlicedCucumberStack` `Cucumber` `FloweredCucumber` `VinedCucumber` `CucumberTree` |
| desert | `DesertSunDriedSlice` `DesertPricklyCucumber` `DesertSunBakedCucumber` `DesertWrappedCucumber` `DesertCactusCucumber` `DesertPalm` `DesertSandstoneTree` |
| volcano | `VolcanoMoltenSlice` `VolcanoCharredCucumber` `VolcanoMoltenCucumber` `VolcanoFlameCucumber` `VolcanoObsidianTree` `VolcanoVolcanoCucumber` `VolcanoMagmaTree` |
| narmek | `NarmekMoonSlice` `NarmekMeteorCucumber` `NarmekPlanetSlice` `NarmekAstronautCucumber` `NarmekNeonAlienCucumber` `NarmekMoonTree` `NarmekAlienTree` `NarmekGalaxyTree` |
| samurai | `SamuraiKatanaCucumber` `SamuraiBambooCucumber` `SamuraiLanternCucumber` `SamuraiBambooGrove` `SamuraiToriiGate` `SamuraiSakuraTree` `SamuraiSlicedCucumber` |
| farm | `FarmCucumberBasket` `FarmMuddyCucumber` `FarmCrateCucumber` `FarmWindmillPlant` `FarmHayBale` `FarmCucumberTree` |
| snow | `SnowFrozenSlice` `SnowSnowcapCucumber` `SnowSnowballSlice` `SnowCrystalCucumber` `SnowFrozenCucumber` `SnowSnowTree` `SnowIcicleTree` `SnowFrozenTree` |
| underwater | `UnderwaterBubbleSlice` `UnderwaterSeaweedCucumber` `UnderwaterShellSlice` `UnderwaterCoralCucumber` `UnderwaterPearlCucumber` `UnderwaterKelpTree` `UnderwaterBubbleTree` `UnderwaterCoralTree` |

---

## The three archetypes

Every model is a variation on one of three shapes, and the library exists to make those
three shapes identical everywhere:

**The cucumber** - an 8-sided pillar **4.0 studs tall, 1.36 across**, chamfered top and
bottom, with a small square stem nub on its head. `D.cuke_body`. Its skin carries the
set's signature **raised square speckles**, snapped to facet centres so they lie flat
(`D.cuke_studs`). Facet 1 faces +Y.

**The slice** - a 10-sided drum, **r 0.80 × 0.42 thick**, built as four objects: a dark
rim, light speckles on the rim, a pale cut face standing proud of each flat end, and
square pips on the faces. `D.slice_disc` / `slice_studs` / `slice_face` / `slice_seeds`,
placed with `D.slice_lay` and `D.slice_stand`.

**The tree** - a stacked plinth, a blocky tapering trunk, square-section branch forks and
a cluster of speckled crown cubes, **11–13 studs tall**. `D.stepped_base` /
`blocky_trunk` / `branch_box` / `crown_cluster`.

---

## Conventions

- 1 Blender unit = 1 Roblox stud; **Z up**, ground at **z = 0**.
- Every model **faces +Y** - the side the camera and the player see.
- Roblox export is a pure rotation: `(x, y, z)_rbx = (x, z, −y)_blender`.
- Nothing sits below `z = 0`.
- Flat shaded, box-projected UVs, triangulated.
- Per-object custom props `rbx_hex` / `rbx_material` / `rbx_transparency` carry the Roblox
  appearance, so the installer rebuilds each model's look without re-deriving it.
  `manifest.json` has every row.

> **The +X / screen-left trap.** Renders view from the +Y side, so the camera looks down
> −Y and **+X appears on the LEFT of the frame**. Anything "on the right as I face it" is
> at negative x.

---

## Files

| | |
|---|---|
| `CUCUMBERS.md` | the build contract: space, scale, style, palette, full API reference, hard rules, and a detailed brief for all 57 models |
| `cukemath.py` | the numbers-only half - the palette and every helper that returns values rather than geometry. Imports nothing but `math`/`random`, so `dryrun.py` runs it for real |
| `cucumberlib.py` | the geometry library: `proplib` re-exported, plus the cucumber body, the speckles, the slice, the tree parts, wrap ribbons, surface cracks, snow drifts, icicles, palm fronds, ice spires, coral arms, saucer canopies, basket weave and kanji |
| `dryrun.py` | offline validator - runs a build script **without Blender** by faking `bpy`/`bmesh`/`mathutils` |
| `build_*.py` | one module per model, each exporting `COLLECTION`, `NOTES` and `build(D)` |
| `buildall.py` | orchestrator - reloads from disk, builds, reports, renders, exports FBX, dumps the manifest |
| `manifest.json` | every part's Roblox appearance (hex, material, transparency, tris) plus each model's report, biome, archetype and notes |
| `upload-cucumbers.ps1` | uploads every FBX as a group-owned Open Cloud Model asset, firing all creates then polling them together |
| `make_install.py` | merges `manifest.json` + `fbx/asset-ids.json` into `install-payload.json` |
| `install.lua` | the Studio-side installer: `API.install(names)` and `API.display(origin, gap, rowGap)` |
| `fbx/` | one FBX per model, Y-up / −Z-forward, 1 unit = 1 stud, plus `asset-ids.json` |
| `renders/` | a hero render per model and one contact sheet per biome |
| `cucumbers.blend` | the saved scene |

---

## Rebuilding

From a blender-mcp session:

```python
exec(open(r"C:\Users\shrey\OneDrive\Documents\RobloxGames\cucumbers\buildall.py").read())
print(summary(build_all()))   # build every model; parts / tris / bbox / min_z each
render_each()                 # hero render per model
render_groups()               # one contact sheet per biome
manifest_json(); export_all(); save()
```

Everything reloads from disk on each call, so editing a `build_*.py` and re-running picks
the change up with no Blender restart. `build_all("Cucumber")`, `build_all("volcano")` and
`render_each(["Cucumber", "CucumberTree"])` all work - a model name, a list, or a biome.

**Each `execute_blender_code` call gets a fresh namespace**, so re-`exec` `buildall.py` at
the top of every call.

## Checking a build script without Blender

```bash
cd C:/Users/shrey/OneDrive/Documents/RobloxGames/cucumbers
py dryrun.py build_desert_palm.py     # or no argument to check every build_*.py
```

`dryrun.py` executes `build()` against a stand-in library that knows every real API name.
It catches syntax errors, calls to primitives that do not exist, palette-key typos, bad
hex/material/transparency values, duplicate part names, a missing `clear_collection`,
geometry below the ground plane and gross scale mistakes - all without touching Blender,
so many scripts can be validated in parallel. It imports `cukemath` **for real**, so
`cuke_point`, `cuke_stud_slots` and `wrap_frames` return the same numbers they will in
Blender. Its bounding box ignores `rot=`/`matrix=` transforms, so a transform-heavy model
(any slice group) reports a wrong bbox and may warn about `min_z` - expected, not a
failure. The Blender build is the source of truth.

---

## How this set was built

`cucumberlib.py` and the three archetype models were authored and validated in Blender
first, so the shared shapes were proven before anything else was written. Each of the
remaining 54 models was then authored against its brief in `CUCUMBERS.md` by a separate
agent, validated offline with `dryrun.py`, and built centrally in one Blender session -
agents never touch Blender, because concurrent `execute_blender_code` calls share one
socket and corrupt each other. Every model was then **reviewed from its render**, not its
code, against its reference tile, and the defects found were fixed and rebuilt.


---

## Installed into Roblox (2026-09-13)

All 57 models are in the **Place1** Studio place as Models under
**`ServerStorage.CucumberSet`** - 57 Models / 285 MeshParts - and laid out for viewing in
**`Workspace.CucumberSetDisplay`**, one row per biome running back along −Z from z = −40.

Each FBX was uploaded through Open Cloud as a group-owned Model asset (group `14583228`),
loaded with `InsertService:LoadAsset`, then post-processed. Asset ids are in
`fbx/asset-ids.json`.

### What the installer does to each model

- Strips the `<Collection>.` prefix from every part name (`Cucumber.Body` → `Body`).
- **Rotates 180° about Y.** Roblox's FBX importer applies a 180° yaw, so raw imports face
  backwards. After the correction a Blender point `(bx, by, bz)` lands at `(bx, bz, −by)`,
  putting each model's authored front (+Y in Blender) on **−Z in Roblox**.
- **Re-applies colour, material and transparency from `manifest.json`.** The FBX import
  loses all of it - every part arrives grey `Plastic` - so this step is not optional.
- Anchors every part, clears `PrimaryPart` and sets `WorldPivot` to the origin, so
  `model:PivotTo(CFrame.new(x, y, z))` places a model with its footprint centred on
  `(x, z)` and its base exactly on `y`. Every model's min-Y is 0.

**Verified after install: 57/57 models, 285/285 parts, 0 colour/material/transparency
mismatches, 0 unanchored parts, 0 bad pivots.**

### Attributes on each model

| Attribute | Meaning |
|---|---|
| `AssetId` | the group-owned Model asset it was loaded from |
| `Biome` | `grass` `desert` `volcano` `narmek` `samurai` `farm` `snow` `underwater` |
| `Archetype` | `cuke` / `slice` / `tree` / `gate` / `prop` |
| `Tris` | triangle count |
| `Notes` | the build script's `NOTES` |

### Re-running the install

The assets are already uploaded, so a re-install only needs `make_install.py` (merges
`manifest.json` + `fbx/asset-ids.json` into `install-payload.json`), the loopback server
(`pets-remake/serve.ps1 -Root cucumbers -Port 8765`), and then `API.install(names)` from
`install.lua` - 8 or 9 models per `execute_luau` call, because `InsertService:LoadAsset`
is slow enough that the whole set in one call blows the ~20 s proxy timeout.

### Blender-only appearance parameters

`emit`, `roughness` and `metallic` drive the Blender render only - `manifest.json` carries
**colour, material and transparency and nothing else**, so none of them reach Roblox. They
still matter for reviewing from renders: an `emit` near 1.0 pushes a warm hue past 1.0 in
linear space and renders vivid orange as pale yellow, and any `metallic` or a `roughness`
under ~0.3 turns a flat low-poly facet into a mirror that blows out to white. This set caps
`emit` at 0.65, `metallic` at 0, and `roughness` at 0.32 or more for that reason.


---

## Idle VFX and animation (2026-09-13)

**19 of the 57** - a third of the set - carry a constant, purely aesthetic idle treatment.
Files: `idle-spec.json` (the spec), `idlefx.lua` (the runtime), `bake_fx.lua` (the installer).

### How it is split

- **VFX instances** - ParticleEmitters, PointLights, a Trail, and added geometry - are
  baked as real children of the models in `ServerStorage.CucumberSet`. They persist when
  the place is saved and are visible in edit mode with nothing running.
- **Motion** is a JSON **`IdleMotion` attribute** on each model, read at runtime by one
  `Script` with `RunContext = Client` at `Workspace.CucumberIdleFX`. Nothing is hard-coded
  per model, so a model carries its own animation wherever it is copied. It animates
  anchored parts locally, so it costs **zero network traffic** and never touches the
  server's copy.
- Everything the baker creates is tagged `IdleFXBaked = true`, so `API.clear()` and a
  re-bake find and remove the previous pass. `API.audit()` lists what each model carries.

### Motion kinds the driver supports

| kind | fields | what it does |
|---|---|---|
| `bob` | amp, period, phase | sinusoidal Y offset |
| `drift` | amp, period, phase, axis | sinusoidal horizontal offset |
| `sway` | deg, period, phase, axis | lean, **pivoting at the model base** so the footprint stays put |
| `rock` | deg, period, phase, axis | rotation about the part group's own centre |
| `spin` | speed, axis | continuous rotation about the group centre |
| `twirl` | speed | continuous rotation about the **model's** Y axis |
| `orbit` | speed | revolve position about the model Y axis, orientation unchanged |
| `breathe` | scale, period, phase | uniform Size + offset scale of the group |
| `pulse` | prop, from, to, period, phase | sinusoidal property animation |
| `flicker` | prop, base, amp, hz | smooth pseudo-random property walk |

Each entry targets `"model"` or a named subset of parts, and entries stack - which is how
you get lag and counter-motion (a crown yawing while its outer stud layer trails it by
0.04 of a period).

**`spin` vs `twirl` matters.** Several models merge multiple objects into one MeshPart -
`NarmekGalaxyTree.Discs` holds a big disc on the mast plus two on side forks. Spinning that
about its centroid swings the whole group around a meaningless midpoint and threw the
footprint out by 3.4 studs. `twirl` rotates about the mast instead: the on-axis disc turns
in place and the off-axis ones sweep around the trunk, which is what a turntable looks like
and holds the growth to 0.3 studs.

### Verified in a live playtest

19/19 animate, none still. Worst horizontal footprint growth over a 7-second sweep is
**+0.70 studs** (the flame cucumber's licks) and worst dip below ground is **−0.05**. Total
ParticleEmitter Rate across all 19 models is **20.8/s**; 19 emitters, 8 lights, 1 trail,
23 added parts (9 visible, 14 invisible emitter hosts).

### Two gotchas worth keeping

- `ParticleEmitter.EmitterSize` does not exist in this Studio version. To emit from a
  volume (a canopy shedding leaves across its whole width rather than dribbling them from
  one point), parent the emitter to an **invisible sizing Part** - an emitter parented to a
  part emits throughout that part's volume. `bake_fx.lua` does this whenever a VFX entry
  has an `Offset` or `EmitterSize`.
- `Lifetime` is a `NumberRange` on a `ParticleEmitter` but a plain **number** on a `Trail`;
  `SpreadAngle` is a `Vector2`, not a `NumberRange`.

### How the treatments were chosen

A gauntlet, run as a Workflow: 6 independent designers on different angles produced **48
candidates**; 12 judges scored all 48 on three separate lenses (visual appeal;
non-disruptiveness and cost, weighted heaviest; fit and distinctness), which **eliminated
12 on safety alone**; the top 16 were then paired by adjacent seed - so near-equals had to
beat each other rather than just confirm the screen - with **3 voters per match**. The 8
survivors plus one reserve were assigned across the 19 models, matched to what each object
already is: the pinwheel and the saucers turn, the flame curls, the bubble tree rises, the
sakura sheds petals that settle on its stones.

Winners: `Speckle Wave`, `Governor Spin`, `Three Leaves Down`, `Settle Skirt`,
`The Vent Breathes`, `Orbits Keep Time`, `Shared Plot Wind`, `Hanging Weight`
(+ `Loose Speckles` as reserve).

### Re-running it

```lua
local f = loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8765/bake_fx.lua"))()
f.clear()      -- remove every baked instance and attribute, and the driver
f.bake()       -- VFX instances + IdleMotion attributes + the driver
f.display()    -- rebuild Workspace.CucumberSetDisplay from the library
f.audit()      -- what each model carries, and the total particle rate
```

Needs `pets-remake/serve.ps1 -Root cucumbers -Port 8765` running to serve the spec and the
driver source.

---

## Rev 3: Toyland + Neon (2026-09-18)

**14 more models** (the set is now **71 models / 373 parts / 164 368 tris**), from a reference
sheet the user sent: `ref-toyland-neon/_sheet.png`, cut into one tile per model beside it.
Briefs, palette and the two deliberate departures from the tiles (cucumber bodies stand
upright; slices are ONE upright disc that the game lays flat) are in `CUCUMBERS-REV3.md`.
Hero renders `renders/Toyland*.png` / `renders/Neon*.png`, contact sheets
`renders/_biome_toyland.png` / `renders/_biome_neon.png`.

| toyland | `ToylandToySlice` `ToylandLegoCucumber` `ToylandJackInTheBoxCucumber` `ToylandToyRocketCucumber` `ToylandPinwheelPlant` `ToylandBuildingBlockTree` `ToylandToyTrainCucumber` |
|---|---|
| **neon** | `NeonNeonSlice` `NeonElectroCucumber` `NeonGridCucumber` `NeonHologramCucumber` `NeonPalm` `NeonTree` `NeonCyberCucumber` |

- New palette keys `toy_*` and `neo_*` in `cukemath.py`; both groups registered in
  `buildall.py` (`build_all("toyland")`, `render_groups(["neon"])` ...).
- Same fan-out as the first 54: 14 agents each wrote one `build_*.py` against its brief +
  tile, validated only with `py dryrun.py` (Python 3.12 via the `py` launcher), then an
  independent reviewer per script checked it against brief + tile + library source and fixed
  what it found; the builds and renders ran centrally in one Blender session. All 14 built
  first time; every render matched its tile.
- Every glow part is `rbx_material "Neon"` (emit 0.6 for the review render only); the Grid
  cucumber's body is Glass 0.35 and the hologram Neon 0.35, so both read see-through in game.
- Uploaded with **`upload-rev3.ps1`** (group 14583228; merges into `fbx/asset-ids.json`,
  never refuses a key over the embedded JWT's `exp`). Installed into the New Map place by
  **`install_rev3.lua`** + **`game-template-map-rev3.json`** (per-model in-field size). Unlike
  `install_game.lua` it ADDS 14 slots and leaves the other 60 alone. Game-side details (pools,
  rewards, legacy save migration) are in `../new-map-cucumber-game/README.md`, section
  "Toyland + Neon get hand-modelled cucumbers".
