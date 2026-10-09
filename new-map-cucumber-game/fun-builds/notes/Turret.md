# Turret: rebuilt as a twin-cannon sentry (2026-09-24, package DefTurret)

**Model source:** `FB\models\build_Turret.py` (primlib). Output: `FB\models\out\Turret.parts.json`.
Install it as `ServerStorage.Builds.Defences.Turret` (category "Defences").
**Renders:** `FB\models\renders\Turret_front.png`, `_three.png` and `_back.png`.
**Rig pose renders:** `_pose_up.png` (yaw 35, pitch +45), `_pose_down.png` (yaw -70, pitch -25), `_pose_side.png`
(yaw 90, pitch +20) and `_pose_bash.png` (yaw 22.5, pitch -25, a side-on close-up of the barrels over the turntable
rim and a lip corner). They pose Head* and Barrel* exactly as `PoseTurret` does. To re-render them, run
`FB\models\pose_Turret.py` the same way as `run_one.py` (headless Blender; optional args pick poses by tag).

**Fix pass (2026-09-24, after review):** at `MinPitch` -25 the barrels cut into the turntable (clamp 0.15 deep, tubes
0.12) and the lip corners (muzzle rings 0.08, brakes 0.05). That pose is common in play (see Clearances). Fixed by:
* turntable 4.7 -> **4.0** across;
* bearing ring 4.5 -> **3.7**, so it stays one step narrower than the turntable;
* barrel sleeves 0.74 -> **0.70**;
* orange lip top 1.86 -> **1.72**.

The build script now sweeps every moving part against everything it can pass and fails the build on a cut deeper
than 0.03. Pivots, rig names, part count and the footprint are unchanged.
**Behaviour modules:** none. Only the existing `DefenceService` (server) and the new DefenceFX client animate it.

## The look
The old model was a grey box with orange side plates. The new one reads as a cute but dangerous sentry. Its colours are
bright orange armour (ff8a2a), gunmetal (3b4350 / 56627a), near-black trim and cyan neon (4dd2ff).
* **Base (static):** an octagonal DiamondPlate foot with 12 bright bolts, and an octagonal gunmetal plinth.
  * The plinth has raised panels on its four square-on faces, and sloped gussets braced against the four diagonal faces.
  * The front panel has a dark display with three cyan status lights.
  * An orange octagonal lip (6.0 across, top at y 1.72) and a dark bearing ring (3.7 across) sit on top.
* **Head (yaws):**
  * A DiamondPlate turntable, 4.0 across and one step wider than the bearing ring.
  * Two orange cheek plates. Each has a sloped front and a chamfered roof edge, a dark bumper, and a vented side panel.
  * Capped trunnion hubs on both sides.
  * An orange roof with a hatch.
  * A sensor pod with a big cyan **eye**. The eye has a dark bezel, a hood and a white glint, with cyan LEDs on the pod sides.
  * At the back: an ammo drum on a mount, with cross-spoked caps and a brass ammo belt that feeds into the head.
  * Cyan tail lights and an antenna with a cyan tip.
* **Barrels (pitch):**
  * A round gunmetal mantlet with a bolted front plate.
  * Twin steel barrels with dark cooling sleeves and orange ribs.
  * A clamp, and slotted square muzzle brakes.
  * Glowing cyan **muzzle rings** with dark bores, linked by the neon `BarrelMuzzleGlow` bar.

| Measure | Value |
|---|---|
| Static base | 7.2 x 7.2 octagon (inside the 8 x 8 tile) |
| Height | 5.96 to the sensor hood, 6.22 to the antenna tip |
| Model depth | 7.4, because the muzzles reach z = -3.8 at rest |
| Parts | 118 (budget 140). All primitives, no asset upload. Base 37, Head 55, Barrel 26 |
| Cost | `m.attr("Cost", 25000)` |
| Other attributes | `PropSet = "defence"`, plus a `Notes` attribute |

## Rig contract (DefenceService set-1 Turret branch, unchanged)
* **`BasePlinth`** is a Block centred at (0, 0.975, 0). `def.Origin = CFrame.new(BasePlinth.Position) * hitbox rotation`,
  so the yaw axis is x = z = 0.
  * It is the 0-degree block of the plinth octagon. Its siblings `BasePlinthB/C/D` are static and are not looked up.
* **`HeadTrunnion`** is a Cylinder (axis X), 4.44 long and d 0.8, centred at **(0, 3.70, 0)**. That centre is the pitch
  pivot.
  * The name starts with "Head", so it yaws. It is round about X, so it looks right under the pitching barrels.
* **Name prefixes:** `Head*` parts yaw (55 parts). `Barrel*` parts pitch about X through the trunnion, then yaw (26 parts).
  Everything else is `Base*` and static. `report()` in the build script asserts this.
* **Rest pose:** zero yaw and zero pitch, with the barrels pointing -Z.
  * The barrel axes are at x = ±0.5 and y = 3.70.
  * The muzzle-ring fronts are at z = -3.76 and the bores at -3.80.
* **`BarrelMuzzleGlow`** is a Neon 4dd2ff Block, size (1.0, 0.18, 0.1), at (0, 3.70, -3.70). It has no rotation: its
  local X runs across the barrels and it faces -Z.
  * Shots leave from `CFrame * (±0.5, 0, -0.15)` = (±0.5, 3.70, -3.85). That is 0.05 in front of each bore centre, and
    matches `Pivot_MuzzleTipL/R`.
  * The tracer takes its colour from this part, so it stays cyan.
* **Clearances:** checked on every build by `report()` -> `clash_sweep()` in `build_Turret.py`. The build fails on
  a regression.
  * **Radius** (box corners, conservative): the Head parts stay within 3.64 of the axis. The Barrel parts stay within
    3.90 over pitch -25..+45 at any yaw, so a full spin stays inside the 8 x 8 tile.
  * **Clash sweep:** poses the rig exactly like `PoseTurret`.
    * It checks every Barrel part against every Head part at each pitch from -25 to +45, in 1-degree steps. They yaw
      together, so yaw doesn't matter there.
    * It checks every Head and Barrel part against every Base part at every yaw (2-degree steps) crossed with every
      pitch.
    * Depth is the deepest surface sample (0.05 apart) of either part inside the other. Measuring both ways means a
      corner poking into a face also counts.
    * It asserts that nothing cuts deeper than **0.03**.
    * `BarrelMantlet` is skipped against the Head parts. It is an X-axis cylinder on the pitch axis, so it looks the
      same at every pitch, and its overlaps with `HeadTrunnion`, `HeadChin` and `HeadRear` are fixed construction.
    * It takes about 2 s.
    * A finer run (0.5-degree yaw, samples 0.03 apart) gave the same numbers.
  * **Why -25 matters:** it is a common pose, not a rare one.
    * A Spawnling (ZombieCatalog Scale 0.6, root about 1.8 up; Bloated Splitters spawn 3 from level 5) bashing the
      turret stands about 4 studs from the axis.
    * The aim is then atan(-1.9 / 4), about -25, so `PoseTurret` holds `MinPitch` for the whole bash, right where the
      player is looking.
  * **What the sweep measures now:**

    | Contact | Depth | Why |
    |---|---|---|
    | `HeadTurntable` on `BaseRing` | 0.020 | The seat, by design: coaxial round parts, the same at every yaw |
    | `BarrelSleeveL/R` rim on the turntable top, at -25 only | 0.007 | Not visible |
    | Everything else | under 0.005 | |

  * **Gaps at -25, worked out by hand:**
    * The clamp's lower back edge passes about 0.09 outside the turntable rim.
    * The tube undersides cross the turntable's top plane about 0.08 outside the rim.
    * The muzzle rings' lowest point (y 1.72) passes just outside a lip corner (radius 3.27 against 3.25).
    * The muzzle brakes stay about 0.09 above the lip.
  * **At +45:** the mantlet plate's top corner stays 0.23 in front of the roof edge and 0.12 under the eye bezel.
  * **Before the fix pass**, the same sweep failed the old geometry: clamp 0.150, tubes 0.117, muzzle rings 0.080 into
    the lip corners, brakes 0.052. Lowering the lip only to 1.76 still left the muzzle rings 0.029 into the corners,
    hence 1.72.
* **Pivots (authored, rest pose):**

  | Pivot | Position |
  |---|---|
  | `Pivot_YawPivot` | (0, 2.2, 0) |
  | `Pivot_PitchPivot` | (0, 3.7, 0) |
  | `Pivot_MuzzleTipL` | (0.5, 3.7, -3.85) |
  | `Pivot_MuzzleTipR` | (-0.5, 3.7, -3.85) |
  | `Pivot_EyeLens` | (0, 5.4, -0.33) |
  | `Pivot_DrumCentre` | (0, 3.55, 2.6) |

  They keep the old model's pivot names. The yaw and pitch move the tips and the eye at run time, so an FX script should
  read the live parts (`BarrelMuzzleGlow`, `HeadEye`), not these points.

## For the DefenceFX author
These are the Neon parts that can pulse or flash:
* **Moving with the head:** `HeadEye`, `HeadEyeGlint`, `HeadSensorLedL/R`, `HeadTailLightL/R`, `HeadAntennaTip`.
* **Moving with the barrels:** `BarrelRingL/R`, `BarrelMuzzleGlow`.
* **Static:** `BaseLight1-3`.

The Turret has no `Glow*` prefix like the FreezeTower and LaserGate, because the set-1 rig takes the `Head`/`Barrel`/`Base`
prefixes. Suggestions:
* Flash the eye while the turret has a target.
* Flash `BarrelRing<side>` on each shot. The server alternates `def.Side`: the first shot comes from -X
  (`BarrelRingR`), the next from +X (`BarrelRingL`). Each shot makes a `Tracer` part at workspace root.
* Put the muzzle flash at `BarrelMuzzleGlow.CFrame * (±0.5, 0, -0.15)`.

Don't CFrame the Head or Barrel parts on the client: the server's `PoseTurret` owns them.

## Notes for the integrator
* **Install:** `install_models.lua` with `{"Turret"}` and `{Backup = true}` (parts.json already says "Defences").
  * The old MeshPart model (AssetId 127864046617307) moves to `ServerStorage.__BuildsBackup_2026_09_24.Defences`.
  * The old `AssetId` / `Tris` attributes are not carried over. Nothing in `live/` reads them. I grepped the old part
    names too, and no script references them.
* **Keep Turret out of `BuildCatalog.SCALE`, or at 1.** `DefenceService` fires from `BarrelMuzzleGlow.CFrame * (±0.5, 0,
  -0.15)` in unscaled studs. At another scale the barrels would no longer sit at ±0.5.
* **Placed turrets:** existing ones restore from the new template on the next server start (`BaseSaveService` clones
  the template).
* **Test:**
  1. Place a Turret and start a night raid.
  2. The head should yaw about its centre with no wobble. A wobble means the origin is wrong.
  3. The barrels should pitch about the hub axle. The mantlet cylinder should turn in place between the cheeks.
  4. Tracers should leave alternately from the left and right muzzle ring, in cyan.
  5. Break the turret (`BuildHealthService`) and check the fade and restore. There are no transparent authored parts.
* **Sound wish (optional):** a punchier twin-cannon shot than the current `SoundController.PlayFXAt("Zap")`, for example a
  short "pew"/blaster pop. Nothing in the model depends on it.
* **Collisions:** the main armour, base and barrel parts collide. Tiny details (bolts, vents, LEDs, antenna, ammo belt,
  bores, brake slots, hatch) are `collide=false`.
