# Biome guardians - Blender source

**Ten rigged, posable low-poly guardians**, one per biome of the New Map cucumber game,
for the "steal a cucumber and it chases you" loop. Built 2026-09-14 from the ten concept
sheets. Blender file: `guardians.blend` (Blender 5.2).

**361 parts / 29 415 tris across the ten**, plus ten seats and one crow. All 21 FBX are
uploaded as group-owned Open Cloud Model assets (group `14583228`); ids in
`fbx/asset-ids.json`.

| # | Biome | Guardian | Parts | Tris | Size (x·y·z) | Seat | Asset id |
|---|---|---|---|---|---|---|---|
| 1 | Spawn | **Strawman** | 33 | 3 150 | 6.1 · 2.8 · 7.7 | hay bale | `127148278962553` |
| 2 | Desert | **Dune** | 30 | 3 437 | 5.0 · 12.4 · 11.3 | sand mound | `136259014216362` |
| 3 | Samurai | **Kabuto** | 42 | 3 646 | 6.2 · 4.6 · 9.9 | stone pedestal | `112703353609220` |
| 4 | Farm | **Brisket** | 37 | 3 236 | 7.9 · 13.5 · 8.6 | mud patch | `73783961501895` |
| 5 | Snow | **Frostbite** | 31 | 2 494 | 7.7 · 5.5 · 9.9 | cracked ice block | `107226314322137` |
| 6 | Underwater | **Pinch** | 51 | 3 480 | 11.1 · 10.2 · 6.9 | rock nook | `136253918533788` |
| 7 | Volcano | **Ember** | 36 | 2 180 | 6.6 · 5.3 · 11.1 | rock pile | `128666843943683` |
| 8 | Narmek | **Orbit** | 29 | 2 514 | 9.4 · 8.8 · 12.6 | crescent moon | `91565440044080` |
| 9 | Toyland | **Tick** | 33 | 2 636 | 4.1 · 3.3 · 9.2 | ABC block stack | `78428855140932` |
| 10 | Neon | **Scan** | 39 | 2 642 | 6.9 · 5.0 · 8.2 | charging pad | `96345579484533` |

Seats: Strawman `108827436978969` · Dune `79329781805961` · Kabuto `130510017125570` ·
Brisket `114972929507307` · Frostbite `110568734106207` · Pinch `79298511338208` ·
Ember `110060470188070` · Orbit `82253613208936` · Tick `116151401602546` ·
Scan `75189983132789`. Strawman's crow: `97305687452235`.

Orbit and Scan are the only two with a deliberate air gap (`min_z` 1.95 and 0.55) - they
hover. Every other guardian's lowest geometry is exactly `z = 0`.

---

## What makes these different from the cucumber set

The cucumbers are static props. These are **rigs**:

- **Every moving part is its own object with its origin ON ITS JOINT** - head, jaw, each
  limb segment, each claw half, the wind-up key, every orbit rock. `G.part(...)` takes a
  `pivot` and moves the mesh so the object's origin lands there.
- **Every part records its rig parent**, so the Motor6D tree is data, not guesswork:
  `manifest.json` carries `{part: {parent, pivot, role, hex, material, sleep_hex, tris}}`.
- **Every part is named `<Guardian>_<Part>_<Role>`** - `Frostbite_Arm_L_FurWhite`. The FBX
  importer drops all materials, so the colour comes back from the role, which is the last
  underscore-separated token.
- **Two states.** The sheet's AWAKE look is what is authored; `SLEEP_LOOK` in `gmath.py`
  darkens the Neon roles for the asleep state, and `POSES["Sit"]` slumps the body onto its
  seat. Eyes are always their own parts so the wake tell reads at 100 studs.
- **Poses are part of the model.** `POSES` maps a part name to `(rx, ry, rz)` degrees
  about its own pivot, inherited by its children - exactly the transform the Motor6D chain
  will apply in Roblox. **If a pose renders right, the pivots are right**, which is the
  cheapest possible test of a rig before Studio ever sees it.

## Conventions

- 1 Blender unit = 1 Roblox stud; **Z up**, ground at **z = 0**, nothing below it.
- Every guardian **faces +Y**. The FBX importer applies a 180° yaw, so the authored front
  lands on Roblox **−Z**, which is the model's LookVector. (`GUARDIANS.md` says "face −Z
  in Blender", which is *down* in a Z-up scene - +Y is the convention that actually yields
  a forward LookVector.)
- **+X is the character's RIGHT**, and renders look down −Y, so **+X appears on the LEFT**.
- Flat shaded, one flat colour per piece, **2 000–4 000 tris** per guardian.
- Roblox export is a pure rotation: after the yaw correction a Blender point `(bx, by, bz)`
  lands at `(bx, bz, −by)`. `manifest.json` carries this in its `space` block so the
  installer cannot get it wrong.

## Files

| | |
|---|---|
| `GUARDIAN-BUILD.md` | the build contract: space, API reference, hard rules, the pose-axis table, and a detailed brief per guardian taken from its concept sheet |
| `gmath.py` | the numbers-only half - `ROLES` (per-guardian colour tables), `SPEC`, `SLEEP_LOOK`, `NEON_ROLES`, and every helper that returns values rather than geometry. Imports only `math`/`random`, so `dryrun.py` runs it for real |
| `guardianlib.py` | the geometry library: `cucumberlib` (hence `proplib`/`defenselib`) re-exported, plus `G.part` / `G.apply_pose` / `G.rig_tree`, and the shapes ten guardians need - fur coats, tufts, lava seams, crescents, barnacles, pincers, horns, worm rings, mittens, fins, diamonds, swirls |
| `dryrun.py` | offline validator - runs a build script **without Blender** by faking `bpy`/`bmesh`/`mathutils` |
| `build_*.py` | one module per guardian, each exporting `COLLECTION`, `GUARDIAN`, `NOTES`, `POSES` and `build(G)` |
| `buildall.py` | orchestrator - reloads from disk, builds, poses, renders, dumps the manifest, exports FBX |
| `manifest.json` | every part's colour, material, pivot, rig parent and tri count, plus the poses and the Blender→Roblox space contract |
| `upload-guardians.ps1` | uploads every FBX as a group-owned Open Cloud Model asset, firing all creates then polling together |
| `fbx/` | one FBX per collection (guardian, seat, extras) plus `asset-ids.json` |
| `renders/` | a hero render per guardian, plus `_Sit` and `_Awake` state renders |
| `guardians.blend` | the saved scene |

## Rebuilding

From a blender-mcp session:

```python
exec(open(r"C:\Users\shrey\OneDrive\Documents\RobloxGames\guardians\buildall.py").read())
print(summary(build_all()))     # build all ten; parts / tris / size / min_z / rig errors
render_each()                   # hero render per guardian
render_states()                 # Sit and Awake, each on its seat
render_contact()                # all ten in one frame, the coherence check
manifest_json(); export_all(); save()
```

Everything reloads from disk on every call, so editing a `build_*.py` and re-running picks
the change up with no Blender restart. `build_all("Pinch")` and
`render_view("Kabuto", "slam", yaw=30, pose="Slam")` both work.

**Each `execute_blender_code` call gets a fresh namespace**, so re-`exec` `buildall.py` at
the top of every call.

## Checking a build script without Blender

```bash
cd C:/Users/shrey/OneDrive/Documents/RobloxGames/guardians
py dryrun.py build_pinch.py        # or no argument to check every build_*.py
```

`dryrun.py` executes `build()` against a stand-in library that knows every real API name.
It catches syntax errors, unknown primitives, a role that is not in `ROLES[guardian]`, a
part with no pivot, **a pivot nowhere near its own geometry**, a rig with no root or two
roots or a missing parent or a cycle, duplicate part names, poses that name a part that
does not exist, a missing `Hitbox`, and geometry below the ground plane - all without
touching Blender, so many scripts can be validated in parallel. Its bounding box ignores
`rot=`/`matrix=` transforms, so a transform-heavy model reports an approximate size; the
Blender build is the source of truth.

## How this set was built

`gmath.py`, `guardianlib.py` and **Strawman** were authored and proven in Blender first -
built, posed, rendered and reviewed against its sheet - so the joint-origin machinery, the
role naming and the pose check were all validated before anything else was written. The
other nine were then authored in parallel, one agent per guardian, against the brief in
`GUARDIAN-BUILD.md` and validated with `dryrun.py` only; **agents never touch Blender**,
because concurrent `execute_blender_code` calls share one socket and corrupt each other.
Each script was then re-read by an independent adversarial reviewer against the same brief.

Then every guardian was **reviewed from its render against its concept sheet** - not from
its code - and the defects that found (a crab whose claws did not read, a golem built from
beads instead of boulders, a yeti that read blue instead of white, an oni whose horns swept
the wrong way) were written up as a per-guardian critique and fixed in a second pass.

## Blender-only appearance parameters

`emit`, `roughness` and `metallic` drive the Blender render only - `manifest.json` carries
**colour, material and transparency and nothing else**. They still matter for reviewing
from renders: an `emit` near 1.0 pushes a warm hue past 1.0 in linear space and renders
vivid orange as pale yellow, and `metallic` or a low `roughness` turns a flat facet into a
mirror. `G.part` caps Neon emission at 0.62 for that reason.

The render rig is also deliberately flat and evenly lit on a light card
(`LIGHT_KEY`/`LIGHT_FILL`/`LIGHT_RIM`/`WORLD_BG` in `guardianlib.py`), because the
inherited preview rig rendered a 140,60,50 shirt as muddy purple and the first review
chased colour bugs that were not there.

---

## Phase 2 - rigged, animated and installed (2026-09-15)

All ten are **installed in the New Map place** at `ServerStorage.Assets.Guardians.<Name>`,
each a Humanoid rig with its Motor6D tree, its seat, and an `Anims` folder of 7 published
Animation assets. **70 animations**, ids in `anims/anim-ids.json`.

### The rig

`install.lua` does the whole install from `install-payload.json`:

- **`LoadAsset`, then yaw the model 180° about Y.** The importer lands a Blender point at
  `(-bx, bz, by)`; after the correction it is at `(bx, bz, -by)` and the authored +Y front
  faces Roblox −Z, the model's LookVector.
- **Renames** each part from `Guardian_Part_Role` to just `Part`, with the role in a `Role`
  attribute - animation Poses are keyed by part name, so short names matter.
- **Re-applies colour / material / transparency**: the FBX import loses all of it.
- **Builds the Motor6Ds from attachment pairs**, the zombie-rig recipe: an Attachment in
  each of Part0 and Part1 at the joint, and `C0`/`C1` set from them. The joint's world
  rotation is IDENTITY, which is what lets a clip's rotations be used as-is.
- **Adds a Humanoid**, sets `HipHeight` from the real drop to the lowest geometry, and
  parks the seat and extras in a `Props` folder inside the model.

**`Root` and `Hitbox` are rebuilt as plain axis-aligned Parts** (`boxify`). Every imported
part carries the FBX importer's own axis rotation, so an imported part's LookVector points
DOWN - harmless for an invisible mesh, fatal for a PrimaryPart, because `PivotTo` uses
`PrimaryPart.CFrame` as the pivot and lays the whole guardian on its face. This was a real
bug caught by checking the HRP's LookVector after the first install.

| | parts | motors | hip |
|---|---|---|---|
| Strawman | 33 | 32 | 2.75 |
| Dune | 30 | 29 | 0.08 |
| Kabuto | 42 | 41 | 3.50 |
| Brisket | 37 | 36 | 4.68 |
| Frostbite | 31 | 30 | 2.33 |
| Pinch | 51 | 50 | 1.79 |
| Ember | 36 | 35 | 5.14 |
| Orbit | 29 | 28 | 3.90 |
| Tick | 33 | 32 | 2.10 |
| Scan | 39 | 38 | 2.88 |

Dune's hip is ~0 by design - its root sits at the tail, in the sand.

### The clips

`clips.py` turns each build script's key POSES into the seven clips the chase system needs
and writes `clips.json`; `build_anims.lua` turns that into KeyframeSequences in Studio.

| clip | | |
|---|---|---|
| `SitIdle` | loop 3.2 s | the asleep pose, breathing |
| `Wake` | 1.1 s | Sit → Awake with an overshoot |
| `Run` | loop 0.88 s | **the Run pose and its MIRROR** - one key pose is a whole stride |
| `Grab` | 0.78 s | wind back, then everything that can reach throws forward |
| `ReturnToSeat` | 1.0 s | Awake → Sit |
| `Stunned` | loop 1.8 s | bat-knocked: the whole rig sags and sways |
| signature | 0.6–1.75 s | CrowShake, DiveSurface, Slam, Charge, Throw, Snap, Throw, Blink, Rewind, Blink |

**The space conversion is the part worth understanding.** A pose is `(rx, ry, rz)` degrees
about the BLENDER world axes. Blender maps to Roblox by `M = Rx(-90°)`. A rotation `R_b`
about Blender axes is the rotation **`M · R_b · M⁻¹`** about Roblox axes - conjugation, not
a component swap. `clips.py` builds the full matrix and emits a QUATERNION, so no Euler
ordering convention has to agree across the two engines.

**`Stunned` is topology-driven, not name-driven.** The first version folded parts named
`ArmUpper*`/`Head*`, which a worm, a crab and a hovering drone do not have - it moved 1 of
50 motors on Pinch. It now droops every joint by an amount that decays with its depth in
the rig, and moves **100 % of the motors on all ten**.

### Verified in a playtest

Every one of the 70 clips was loaded **from its published asset id** on its own rig and
measured: correct track length, and a real subset of Motor6D `Transform`s rotated.

Two measurement traps worth keeping: a freshly uploaded animation returns
`AnimationTrack.Length == 0` until the asset actually downloads (poll for it, do not treat
zero as a failure); and the trace of a Roblox rotation matrix is
`RightVector.X + UpVector.Y − LookVector.Z`, because `LookVector` is the NEGATIVE Z axis -
getting that wrong made identity measure as 90° and every clip look like it was working.

### Open Cloud note

The repo's older `assets/anims/upload-animations.ps1` says "a group-owned animation only
plays in group-owned experiences". **That is not true here, and it was tested**: animation
`129265796517160`, owned by group `14583228`, loaded and played on a rig in the USER-owned
New Map place. Group upload is the only route this key family allows (a `userId` creator
context returns 403), and it works.
