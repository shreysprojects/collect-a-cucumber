# Mortar (Defences) - rebuilt model, package DefMortar (2026-09-24)

Model only: no behaviour modules. The existing `DefenceService` (server: yaw, recoil, shells) and the new
DefenceFX client are the only scripts that animate it.

* Source: `FB\models\build_Mortar.py` -> `FB\models\out\Mortar.parts.json` (123 parts, category `Defences`)
* Renders: `FB\models\renders\Mortar_front.png`, `_three.png`, `_back.png`,
  posed check `Mortar_pose_yaw135_recoil6.png` (Mount yawed 135 deg, Tube at +6 deg recoil)
* Attributes: `Cost = 400000000`, `PropSet = "defence2"`, `State_Elevation = 55`, `Notes` (rig summary)

## Look
A fat bronze barrel with a domed breech and cascabel knob, dark iron reinforcing bands, a trunnion collar, two
lifting handles and a stepped flared muzzle with a black bore and an orange neon core. It sits between red trunnion
cheeks that have big brass bolts, bronze trunnion caps with iron nuts, a yellow elevation handwheel (-X side) and a
small sight with a glass lens (+X side). The cheeks stand on a red turret ring with a diamond-plate deck. A rack of
eight brass shells with orange neon bands stands round the back of the ring. The ring turns on a yellow race
inside two staggered rings of khaki sandbags. Under it all is a diamond-plate armour disc with a glowing orange
rim, and a ramrod lies across the back sandbags.
Footprint 7.95 x 7.94, which fits the 8 x 8 tile. It is 7.92 tall, measured to the muzzle lip.

## Rig contract (unchanged from the old Mortar, DefenceService reads it as-is)
| Group | Parts | Motion |
|---|---|---|
| `Base*` | BasePlate, BaseGlowRim, BasePedestal, BaseRace, BaseSandbag1_01..2_12, BaseRamrod, BaseRamrodBrush | static |
| `Mount*` | MountRing, MountRingLip, MountDeck, MountRingBolt1-8, MountCheekL/R (+Slope/Top/Panel), MountFootL/R, bolts, MountCapL/R, MountNutL/R, MountTransom, MountWheel*, MountSight*, MountShellCase1-8, MountShellNose1-8, MountGlowShell1-8 | yaws about the vertical axis through x = z = 0 |
| `Tube*` | TubeTrunnion, TubeKnob, TubeKnobNeck, TubeBreech, TubeBody, TubeBand*, TubeChase, TubeAstragal, TubeFlare1/2, TubeLip, TubeBore, TubeGlowBore, TubeHandleL/R* | pitches about the axis parallel to X through Pivot_PitchPivot |

* `Pivot_PitchPivot = (0, 3.85, 0.5)`: the trunnion centre. It was (0, 4.0, 0) on the old model; DefenceService reads the attribute, so nothing needs changing.
* `Pivot_MuzzleTip = (0, 7.1266, -1.7943)` = PitchPivot + 4.0 * (0, sin55, -cos55), the centre of the muzzle face. Shells leave from here.
* `Pivot_YawPivot = (0, 1.3, 0)`: the top of the static race. Nothing reads it; it is kept for parity with the old model.
* The tube is built at 55 deg elevation pointing toward -Z and up. The authored origin is the floor centre (min y = 0) and sits on the yaw axis.
* Every part name starts with Base, Mount or Tube. There are no duplicate names.
* Glow parts (orange neon ff8a1f) keep their group prefix: `BaseGlowRim` (a thin band round the armour disc edge), `MountGlowShell1..8` (shell bands) and `TubeGlowBore` (the hot bore core, which pitches with the tube). If DefenceFX pulses them, a flash on `TubeGlowBore` when a shell fires would look good.

## Clearances (checked by sampling every part's true shape, 12 yaws x pitches -6/0/+6/+8)
* No Tube part touches a Mount or Base part and no Mount part touches a Base part. The only planned overlap is `TubeTrunnion` running through the cheeks and caps. It is a cylinder on the pitch axis, so it looks the same at any pitch.
* Recoil (DefenceService pitches +6 deg, which is more vertical, so the breech drops): the knob's lowest point is 1.92 and the deck top is 1.85.
* Mount + Tube stay within r 2.96 of the yaw axis for pitch 0..+8. The sandbags start at r 2.96 and stay below the deck (top 1.6 < 1.72).

## For the integrator
* Install like the other set-2 defences (source in ServerStorage.Builds.Defences.Mortar at authored coordinates, identity rotation), so that `originOf` (Hitbox + source box centre) still matches. The bounding box is almost centred: min (-3.977, 0, -3.971), max (3.973, 7.915, 3.968).
* Test: place a Mortar, start a night raid and watch Mount* turn toward zombies. The barrel should kick up about 6 deg on each shot, and the shell should spawn at the orange bore.
* Tiny details are `collide=False`. The cheeks, ring, deck, barrel, shells and sandbags collide.
* No sounds or scripts are needed.
