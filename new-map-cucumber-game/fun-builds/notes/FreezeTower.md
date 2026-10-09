# FreezeTower: rebuilt as a crystalline frost spire (2026-09-24, package DefFreezeTower)

**Model source:** `FB\models\build_FreezeTower.py` (primlib). Output: `FB\models\out\FreezeTower.parts.json`.
Install it as `ServerStorage.Builds.Defences.FreezeTower` (category "Defences").
**Renders:** `FB\models\renders\FreezeTower_front.png`, `_three.png` and `_back.png`.
**Behaviour modules:** none. Only the existing `DefenceService` (server) and the new DefenceFX client animate it.

## The look
The old model was a drab charcoal stack. The new one has four parts:
* **Plinth:** a round blue-slate foundation with a pale frosted-metal lip, and a pale limestone drum.
  * A blue frosted-metal belt runs round the drum. It carries 4 neon gems, and neon snowflakes on the front and back.
  * The drum has a snow cap with 4 drifts and 8 icicles hanging over the belt.
* **Clusters:** four ice-crystal clusters (Ice 6fc3ff / 9ed6ff / cfefff) sit on the snow at the diagonals.
* **Obelisk:** a tapered GLACIER obelisk (6fc3ff faces, pale cfefff edges) turned 45° so that an edge faces the front.
  * It stands in a frosted-metal foot and has two collars with blue-steel trim and icicles under the mid collar.
  * It carries 8 neon rune strips, and three big crystals hug its foot.
* **Top:** a round frosted-metal cradle with a neon disc. It holds the glowing **Orb** between four pyramid-tipped ice claws.
  * A floating neon rune ring (12 segments, tilted 10°) circles the orb.
  * Three floating double-ended ice shards and a floating crown crystal sit above it.

| Measure | Value |
|---|---|
| Footprint | 7.8 x 7.8 (inside the 8 x 8 tile) |
| Height | 12.8 |
| Parts | 139 (budget 140), all primitives, no asset upload |
| Cost | `m.attr("Cost", 3000000)` |
| Other attributes | `PropSet = "defence2"`, plus a `Notes` attribute |

## Rig contract (DefenceService set-2 FreezeTower branch, unchanged)
* **`Orb`** is a Neon Ball, diameter 2.2, colour aee6ff, at (0, 9.9, 0). It is the only moving part, and it is exactly
  centred on **`Pivot_OrbCentre` = (0, 9.9, 0)** (x = z = 0).
  * `FrostTick` spins it about the vertical axis through OrbCentre.
  * The server's PointLight and snow emitter go into it.
  * No other part name starts with `Orb`.
* **Clearances:**
  * Claws: 0.07 studs from the orb surface (a box-distance check).
  * Cradle disc: 0.13 below the orb. The crown crystal starts 0.25 above it.
* **Origin:** the authored origin is the floor centre (min y = 0) and the build is symmetric in x/z (±3.9). So
  `originOf` (the Hitbox plus the source bounding-box centre) lands on the yaw axis.
* **`Glow*`** (31 Neon parts, all `collide=false`). The DefenceFX client pulses these, Transparency 0..0.35:
  * `GlowRune01`-`GlowRune12`: the floating ring.
  * `GlowStrip1Low` ... `GlowStrip4High`: the obelisk runes, 2 per face.
  * `GlowGem1`-`4`: belt gems at front, left (+X), back and right (-X).
  * `GlowFlakeFront1-3` and `GlowFlakeBack1-3`: the belt snowflakes.
  * `GlowCradle`: the disc under the orb.
* **`Pivot_Mist1`..`Mist4`** are frost-mist emitter points on the foundation ledge, radius 3.72 at y 0.62:
  * Mist1: front-left (+X, -Z)
  * Mist2: front-right
  * Mist3: back-right
  * Mist4: back-left
* **Everything else is static.** The floating parts are ordinary anchored parts with `collide=false`.

## Notes for the integrator
* **Install:**
  `install_models.lua` with `{"FreezeTower"}` and `{Backup = true, Category = "Defences"}` (parts.json already says
  "Defences").
  * The old MeshPart model moves to `ServerStorage.__BuildsBackup_2026_09_24.Defences`.
  * The old model's `AssetId` / `Tris` attributes are not carried over. Nothing in `live/` reads them.
* **Keep FreezeTower out of `BuildCatalog.SCALE`.** DefenceService uses `Pivot_OrbCentre` unscaled. If the tower is ever
  scaled, `def.OrbCentre` must be multiplied by the template's `Scale`.
* **Placed towers:** existing ones restore from the new template on the next server start. `BaseSaveService` clones the
  template.
* **Test:**
  1. Place a FreezeTower.
  2. Check that `Orb` spins in place at night, with no wobble. It is centred, so any drift means OrbRel or origin
     trouble.
  3. Check that the snow sparkles come off the orb.
  4. With DefenceFX installed, check that the `Glow*` parts pulse and mist rises from the four `Mist` points.
  5. Break the tower (`BuildHealthService`) and check that the fade and restore look right. There are no transparent
     authored parts, so a restore to 0 is correct.
* **No sounds** are needed for the model.
