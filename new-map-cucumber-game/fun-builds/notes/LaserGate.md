# LaserGate: rebuilt defence model (package DefLaserGate, 2026-09-24)

Source: `FB\models\build_LaserGate.py` -> `FB\models\out\LaserGate.parts.json` (140 parts, the defence budget maximum).
Renders: `FB\models\renders\LaserGate_front.png`, `_three.png`, `_back.png` (old look: `defenses\renders\LaserGate.png`).
Key `LaserGate`, category `Defences`, `Cost` 250000, `PropSet` "defence2". No behaviour module. DefenceService (server)
and the DefenceFX client drive it.

## Look
The old prop was two grey pillars. The new one is a sci-fi laser fence with two armoured emitter pylons:
* **Feet:** a dark DiamondPlate base plate (2.9 deep), gunmetal toe armour sloping down to the front and back, and
  steel bolt heads.
* **Hazard collars:** yellow with black 45-degree stripes, one low (y 0.9-1.55, front, back and outer faces) and one
  high (y 5.45-5.9, front and back). Dark metal rails frame each collar.
* **Column:** a gunmetal core under off-white armour plates on the front, back and outer faces, with a dark belt at
  mid height.
  * Each front and back plate has a laser-warning sign (a yellow diamond with a dark border and "!").
  * A red neon edge strip runs up each inner corner.
  * The outer face has two vents and a steel grab handle.
* **Emitter spine:** a dark spine on each inner face holds four steel-bezelled red neon lenses, one at each beam
  height.
* **Head:** off-white, with a roof that rises toward the gap. It has a red neon brow on the inner face, red neon slits
  on the front and back, and an antenna with a red neon beacon ball.
* **Floor cables:** dark rubber, with yellow clamps. They join the two feet in front of and behind the passage at
  |z| = 1.40.
* **Size:** 8.04 wide x 2.98 deep. The body is 6.9 tall and the beacons reach 7.11.

## Rig contract (verified numerically from parts.json)
| What | Detail |
|---|---|
| `Beam1`..`Beam4` | Bottom to top. Each is ONE Neon `ff2f2f` **Cylinder** Part (axis X, diameter 0.16), x -1.95..+1.95, z 0, y 2 / 3 / 4 / 5, CanCollide false, CastShadow false. DefenceService finds them by name, turns collisions off, adds its PointLights and shimmers / flickers Transparency. |
| Passage | **Nothing** inside \|x\| <= 2.05, \|z\| <= 1.3, y 0..6 except the beams. Checked with a conservative AABB test over every part: 0 intruders. The innermost pylon surface (the lens faces) is at \|x\| = 2.06. The floor cables and clamps sit at \|z\| 1.31..1.49 and are non-colliding. |
| Origin | Floor centre (min y = 0.00). The bounding box is symmetric (x +/-4.02, z +/-1.49), so the box centre (0, 3.555, 0) is on the yaw axis and DefenceService's `originOf` (Hitbox x -box centre) gives the floor centre. |
| `Glow*` (20 parts, Neon ff2f2f, for DefenceFX to pulse) | `GlowLens<L\|R><1-4>`: lens discs at the beam ends (axis X, d 0.42, faces at \|x\| 2.06). Lens i matches Beam i. <br>`GlowEdge<L\|R><F\|B>`: vertical inner-corner strips. <br>`GlowBrow<L\|R>`: head brow facing the gap. <br>`GlowCap<L\|R><F\|B>`: head front / back slits. <br>`GlowBeacon<L\|R>`: antenna-tip balls. |
| `Pivot_Spark1..8` | Beam ends. For beam i (y_i = 2, 3, 4, 5), `Spark(2i-1)` = (-1.95, y_i, 0) and `Spark(2i)` = (+1.95, y_i, 0). |
| `Pivot_BeamLeft` / `Pivot_BeamRight` | Kept from the old prop: (-/+1.95, 3.5, 0). |
Pylon **L** is at -X and pylon **R** is at +X, the same as the old prop. Static parts are named `PylonL*` / `PylonR*`,
the floor cables `Cable*`. No part names start with `A_`/`B_`/`C_` (those would become variants).

## For the integrator
* Install: replace `ServerStorage.Builds.Defences.LaserGate` (the old MeshPart prop, `AssetId` 112459231146713) with
  these Parts. Copy the attributes Cost, PropSet, Notes and every `Pivot_*`. The old `AssetId` / `Tris` attributes no
  longer apply.
* Keep LaserGate at **scale 1** in `BuildCatalog.SCALE`. DefenceService's `LASER` volume (HalfWidth 1.95,
  HalfDepth 1.25, Height 5.5) is in unscaled studs, and the beams and clear passage are authored to match it.
* Test:
  1. Place the gate on a plot at night and let zombies walk through along its Z axis.
  2. Check that they are not blocked by anything between the pylons.
  3. Check that they take "Laser" damage and that sparks and flicker show at the beams.
  4. Check that the DefenceFX client finds 20 `Glow*` parts and 8 `Pivot_Spark*` attributes on the source model.
* Sound wish (for DefenceFX, optional): a quiet looping electric hum at the gate while a raid is on. The closest
  existing sound is `FunAssets.Sfx.HumLoop` ("Electric Buzz").

## Known limits
* There is a 0.11-stud gap between each beam end (|x| 1.95, fixed by the contract) and its lens face (|x| 2.06,
  fixed by the clear passage). The Neon glow of the beam and lens covers it at play distance.
* The budget is used up (140 parts). Any additions need something else removed. Cheapest cuts: the cable clamps (4)
  or the bolts (8).
* Blender renders Neon as a pale pink emission. In Studio `ff2f2f` Neon reads as a hot red.

## v2 2026-09-24: taller, wider, slimmer (user: "make laser gates taller, wider, make the pillars less thick")
Everything above describes **v1** (8 wide, 4 beams, 1.5-thick pylons). v2 replaces it. Same file
(`FB\models\build_LaserGate.py`), same outputs (`FB\models\out\LaserGate.parts.json`,
`FB\models\renders\LaserGate_front.png / _three.png / _back.png`). The v1 script, parts.json and renders are backed up
in this session's scratchpad (`lasergate_v1\`).

**Look:** the style and palette are unchanged. It still has two sci-fi emitter pylons with yellow/black hazard
collars, off-white armour plates on a gunmetal core, red neon lenses, inner-edge strips, brow and slits, DiamondPlate
feet with sloped toe armour, antenna beacons, and floor cables with yellow clamps. The proportions are new:
* **Size:** 12.20 wide x 3.00 deep x 11.09 tall. The bounding box is x +/-6.10, y 0..11.09, z +/-1.50, and its centre
  is (0, 5.545, 0), so it is symmetric about x = 0 and z = 0.
* **Pylons:** each one is centred at |x| = 5.45. The body is 1.1 wide in X (inner face 4.85, outer plate 5.98) and
  1.36-1.56 deep (the plates are +/-0.68 and the collar rails +/-0.78).
  * **Feet:** "ski" feet flare outward to |x| 6.10 and reach z +/-1.5.
  * **Heads:** z +/-0.8, x 4.85..6.06.
  * **Roofs:** they rise toward the gap and overhang it to |x| 4.60. The overhang is only above the passage (roof
    bottom at y 10.02).
  * **Heights:** the tallest roof point is 10.57 and the beacon tops are 11.09.
* **Column:** split into three panels by two dark belts at y 3.95 and 6.35. The warning signs sit on the middle panel
  at y 5.15. The lower hazard collar is at y 0.9-1.4 (front, back and outer stripes) and the upper one at y 8.9-9.4
  (front and back stripes).
* **Parts:** 140, the defence budget maximum. 38 collide. To fit the budget, each foot now has 2 bolts, at the toe
  tips.

**Rig contract (verified numerically from parts.json):**
| What | Detail |
|---|---|
| `Beam1`..`Beam6` | Bottom to top. Each is ONE Neon `ff2f2f` Cylinder (axis X, d 0.16), x -4.75..+4.75, z 0, y 1.5 / 3.0 / 4.5 / 6.0 / 7.5 / 9.0. CanCollide false, CastShadow false. |
| Passage | No CanCollide part within \|x\| <= 4.8, \|z\| <= 1.3, y 0..10 (conservative AABB test: 0 intruders). The innermost solid surface below y 10 is at \|x\| 4.85, so the clear gap is 9.7. Only the non-colliding `GlowLens*` reach inside \|x\| 4.8: they run x 4.73..4.87 and sleeve the beam ends, so no beam floats. The floor cables (d 0.18, z +/-1.31..1.49) and clamps (z 1.305..1.495) are non-colliding. |
| `Glow*` (24 Neon ff2f2f parts) | `GlowLens<L\|R><1-6>`: d 0.3, one per beam end, lens i = beam i. <br>`GlowEdge<L\|R><F\|B>`: inner-corner strips, y 1.54..8.86. <br>`GlowBrow<L\|R>`: on the roof's inner face, y 10.2..10.36. <br>`GlowCap<L\|R><F\|B>`: head slits. <br>`GlowBeacon<L\|R>`: antenna tips at y 10.98. |
| `Pivot_Spark1..12` | Beam i: `Spark(2i-1)` = (-4.75, y_i, 0) and `Spark(2i)` = (+4.75, y_i, 0). |
| `Pivot_BeamLeft` / `Pivot_BeamRight` | (-/+4.75, 5.25, 0). |
| Attributes | `Cost` 250000, `PropSet` "defence2", `Notes` (updated for v2). Category `Defences`. |
Checks: no duplicate names. There is no same-direction coplanar face overlap except the bottom faces of the foot
plates, cables and clamps, which rest on the ground at y 0 and are never visible. Nothing floats.

**For the integrator (v2 changes):**
* DefenceService `LASER` must match the new gate. It is currently HalfWidth 1.95 / Height 5.5 / HalfDepth 1.25; it
  needs about **HalfWidth 4.75, Height ~9.5-10**, with HalfDepth 1.25 unchanged. With the old numbers only the
  middle 3.9 studs of the 9.5-stud beams would damage.
* DefenceFX: it now finds 24 `Glow*` parts and 12 `Pivot_Spark*` attributes. If anything is hard-coded to 4 beams or
  8 sparks, loop over `Beam%d` / `Pivot_Spark%d` until one is missing instead.
* The footprint grew from 8.04 x 2.98 to 12.2 x 3.0, and the height from 7.1 to 11.1. Check the build-mode
  placement grid/limits and the Hitbox (built from the bounding box) against the bigger size.
* Keep LaserGate at **scale 1** in `BuildCatalog.SCALE`.
