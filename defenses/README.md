# Defence prop set - Blender source

Five base-defence props, built procedurally in Blender. **Nothing here is wired into any
Roblox place** - these are source assets only.

Built 2026-09-09. Blender file: `defenses.blend`.

| Prop | Collection | Parts | Tris | Size (studs, x × y × z) |
|---|---|---:|---:|---|
| Turret | `Turret` | 22 | 1316 | 5.8 × 6.8 × 5.9 |
| Wooden wall | `WoodenWall` | 8 | 816 | 8.0 × 1.4 × 8.0 |
| Stone wall | `StoneWall` | 10 | 968 | 8.0 × 2.8 × 8.0 |
| Spike trap | `SpikeTrap` | 6 | 458 | 8.0 × 8.0 × 3.0 |
| Boost pad | `BoostPad` | 15 | 624 | 8.0 × 12.0 × 2.9 |

**4182 tris / 61 parts total.** An R15 avatar is 5 studs tall for scale.

## Files

| | |
|---|---|
| `defenselib.py` | the primitive library - boxes, bevelled boxes, cylinders, cones, spikes, prisms from 2-D profiles, wedges, jittered rocks, masonry blocks, tubes, tori, plus layout helpers, the render rig and FBX export |
| `STYLE.md` | the build contract: space, scale, facing, palette, module shape, API reference, gotchas |
| `build_*.py` | one module per prop, each exporting `COLLECTION`, `NOTES`, `build(D)` and optionally `PIVOTS` / `STATES` |
| `buildall.py` | orchestrator - reloads everything from disk, builds, reports, renders every sheet |
| `renders/` | hero, player's-eye, study angles, wall tiling proofs, line-up |
| `defenses.blend` | the saved scene |

## Rebuilding

From a blender-mcp session:

```python
exec(open(r"C:\Users\shrey\OneDrive\Documents\RobloxGames\defenses\buildall.py").read())
print(build_all())     # build every prop, report parts / tris / bbox / min_z
print(render_all())    # every render sheet
```

Everything reloads from disk on each call, so editing a `build_*.py` and re-running picks
the change up with no Blender restart. `build_all("StoneWall")` and
`render_each("StoneWall")` do one prop.

## Conventions

- 1 Blender unit = 1 Roblox stud; Z up; ground at z = 0.
- Every prop **faces +Y** - the direction attackers come from.
- Roblox export is a pure rotation: `(x, y, z)_rbx = (x, z, −y)_blender`.
- Per-object custom props `rbx_hex` / `rbx_material` / `rbx_transparency` carry the Roblox
  appearance, so an installer can rebuild each prop out of Parts or MeshParts without
  re-deriving the look. `D.manifest([...])` dumps them.
- Flat shaded, box-projected UVs at 2 studs per tile, triangulated.
- Standard footprint tile is 8 × 8 studs.

## Rigging data the build scripts emit

**Turret** - part names carry the rig: `Base*` is static, `Head*` yaws about Z, `Barrel*`
pitches about a horizontal X axis. Modelled at zero yaw / zero pitch.

```
YawPivot    (0,  0.00, 1.58)      PitchPivot  (0,  0.00, 4.80)
MuzzleTipL  (-0.5, 3.88, 4.80)    MuzzleTipR  (0.5, 3.88, 4.80)
EyeLens     (0,  1.10, 2.75)      DrumCentre  (0, -1.65, 4.35)
```

**Spike trap** - parts named `Spikes*` are the moving bed:

```
STATES = {"Extended": 0.0, "Retracted": -2.63}
```

Verified: at −2.63 the spike tips sit at z 0.34, below the 0.91 frame lip, so they are
fully hidden. The bed reaches z −2.17 when retracted, so **the trap needs a 2.2-stud pit
below ground** to hide in.

## Deviations from the original brief (deliberate, after the render review)

- **Turret** - the gun overhangs the 6 × 6 base: full-yaw sweep radius is 3.99 studs, so it
  stays inside the 8 × 8 tile but not inside its own base. The barrels could not read as a
  gun at 6 × 6. The static base is still 5.8 × 5.8.
- **Stone wall** - 2.8 studs deep rather than the 1.8 first specified. The extra depth is
  the battered plinth and the stepped centre buttress, which is what makes it read as the
  tougher upgrade next to the wooden wall. Still exactly 8 wide, so it still tiles.
- **Boost pad** - the exit gantry posts reach 2.9 studs rather than the 1.2 first
  specified, to mark the exit end. They sit at x = ±4; the middle 6 studs of width are a
  clean flat run.
- **Spike trap** - 9 large spikes rather than a 5 × 5 bed of small ones, which read as a
  hairbrush rather than a threat.

Both walls tile seamlessly at x = ±4 - verified in `renders/WoodenWall_tiled.png` and
`renders/StoneWall_tiled.png` (running bond and merlon pattern continue across the seam).

## Set 2 (2026-09-16): Mortar, Tesla Coil, Freeze Tower, Minigun, Laser Gate
Five more props in the user's darker charcoal + accent look, built headless (`run_headless.py`,
`BRIEF-2026-09-16.md`), uploaded as group assets and INSTALLED in the New Map place as placeable,
scripted defences. Everything about them is in `README-set2.md` next to this file.
