# TeslaCoil: rebuilt as an iconic tesla tower (2026-09-24, package DefTeslaCoil)

**Model source:** `FB\models\build_TeslaCoil.py` (primlib). Output: `FB\models\out\TeslaCoil.parts.json`.
Install it as `ServerStorage.Builds.Defences.TeslaCoil` (category "Defences").
**Renders:** `FB\models\renders\TeslaCoil_front.png`, `_three.png` and `_back.png`.
**Behaviour modules:** none. Only the existing `DefenceService` (server) and the new DefenceFX client animate it.

## The look
The old model was a grey stack with two blue rings. The new one reads as a tesla coil from across the base:
* **Plinth:** a heavy octagonal steel plinth (3b4350 Metal) with a round DiamondPlate deck.
  * Yellow/black hazard warning plates sit on its four axis faces.
  * Two rivets sit on each diagonal face.
  * The plinth is built from four overlapping blocks. Their tops step up by 0.02 (0.90 / 0.92 / 0.94 / 0.96), so no
    two top faces are coplanar.
* **Transformer drum:** a blue drum (2f64c0) on a steel foot ring.
  * It has a neon power band and a dark lid with 6 bolt heads.
  * **HIGH-VOLTAGE signs** are on the front and back: a yellow triangle on a dark mount, with a black zig-zag
    lightning bolt. The bolt is an upper stroke from top-right to middle-left, a short horizontal link, and a lower
    stroke down-left to the point, in the usual ⚡ orientation.
* **Spark-gap posts:** four posts stand on the deck corners. Each has a white ceramic rod, two blue sheds and a
  glowing cap, with a copper lead running up to the coil's base collar.
* **Insulator:** a ribbed white/blue/white ceramic insulator (3 sheds) lifts the coil.
* **Secondary coil:** 10 stacked copper windings, alternating d9894a / b86f35 Metal. The neon core glows
  between them, and white ceramic collars sit top and bottom, with a blue ceramic cap.
* **Toroid:** a chrome donut: 12 tube segments plus ball joints, with a web plate across the hole and four neon
  breakout nodes.
* **Top:** an insulator neck and a copper-trimmed steel cradle. Four dark-steel claws with copper elbow knuckles
  and neon tips stand around the chrome **Orb**. Each claw leaves a clear air gap to the orb for the arcs.
  * Each claw's upper rod ends at the centre of its neon tip ball, so the ball hides the rod's flat end.

| Measure | Value |
|---|---|
| Footprint | 7.84 x 7.84 (inside the 8 x 8 tile) |
| Height | 12.17 |
| Parts | 139 (budget 140), all primitives, no asset upload |
| Materials | Metal 76, SmoothPlastic 48, Neon 14, DiamondPlate 1 |
| Cost | `m.attr("Cost", 30000000)` |
| Other attributes | `PropSet = "defence2"`, plus a `Notes` attribute |

## Rig contract (DefenceService set-2 TeslaCoil branch, unchanged)
* **`Orb`** is a Metal Ball, diameter 1.7, colour c4dcf2, at (0, 11.32, 0). It is the only moving part, and it is
  exactly centred on **`Pivot_OrbCentre` = (0, 11.32, 0)** (x = z = 0).
  * `TeslaTick` spins it about the vertical axis through OrbCentre.
  * The server's PointLight goes into it.
  * No other part name starts with `Orb`.
  * It rests 0.05 above the cradle and touches nothing, so the spin can't clip anything.
* **`Pivot_ProngTip1..4`** are the centres of the neon claw tips (`GlowTip1..4`), at radius 1.33 and y 11.97, in
  the old model's order:

  | Pivot | Direction | Position |
  |---|---|---|
  | ProngTip1 | front-left (+X, -Z) | (0.94, 11.97, -0.94) |
  | ProngTip2 | front-right (-X, -Z) | (-0.94, 11.97, -0.94) |
  | ProngTip3 | back-right (-X, +Z) | (-0.94, 11.97, 0.94) |
  | ProngTip4 | back-left (+X, +Z) | (0.94, 11.97, 0.94) |

  * Each tip is 1.48 from OrbCentre. After the orb radius (0.85) and the tip ball's radius (0.18), about **0.45
    studs of open air** are left, where `TeslaTick`'s idle arc (`Bolt(OrbCentre -> tip)`: 3 segments, 0.08 thick,
    jag 0.35) can be seen.
  * A sample along each straight arc line meets nothing between the orb and the tip ball. Only the claw's own rod
    end touches the line, and that is inside the tip ball.
* **`Pivot_Spark1..4`** are on the toroid's outer equator, on the outer face of each neon breakout node, radius
  3.01 at y 9.3:
  * Spark1: front (-Z)
  * Spark2: left (+X)
  * Spark3: back (+Z)
  * Spark4: right (-X)
* **Origin:** the authored origin is the floor centre (min y = 0) and the build is symmetric in x/z (±3.92). So
  `originOf` (the Hitbox plus the source bounding-box centre) lands on the yaw axis.
* **`Glow*`** (14 Neon parts, all `collide=false` except `GlowCoil`). The DefenceFX client pulses these:
  * `GlowCoil`: the coil core. It shows as glowing lines between the copper windings, so pulsing it makes the
    whole coil "breathe". It is a good one to flash on a zap.
  * `GlowTip1`-`4`: the claw tips, next to the ProngTips.
  * `GlowNode1`-`4`: the toroid breakout nodes, at the Spark points.
  * `GlowPost1`-`4`: the spark-gap post caps, at the deck corners. They are good for a charge-up flicker.
  * `GlowBand`: the drum power band.
* **Everything else is static.**

## Notes for the integrator
* **Install:**
  `install_models.lua` with `{"TeslaCoil"}` and `{Backup = true, Category = "Defences"}` (parts.json already says
  "Defences").
  * The old MeshPart model moves to `ServerStorage.__BuildsBackup_2026_09_24.Defences`.
  * The old `AssetId` / `Tris` attributes are not carried over. Nothing in `live/` reads them.
* **Keep TeslaCoil out of `BuildCatalog.SCALE`.** DefenceService reads `Pivot_OrbCentre` / `ProngTip*` from the source
  unscaled. If the tower is ever scaled, `def.OrbCentre` and `def.Tips` must be multiplied by the template's `Scale`.
* **Orb height:** the orb is higher than before, at 11.32 (it was 9.00). DefenceService has no hard-coded heights
  that matter, because its 8.95 fallback is only used without the pivot.
  * `nearestZombie` measures `TESLA.Range` from the orb, which is now 2.3 studs higher. That is a negligible change
    against a 28-stud range.
* **Placed towers:** existing ones restore from the new template on the next server start. `BaseSaveService` clones the
  template.
* **Test:**
  1. Place a TeslaCoil.
  2. At night, check that `Orb` spins in place with no wobble.
  3. Check the arcs:
     * The idle arcs (`TeslaTick`, every ~0.7 s) should jump from the orb to a random neon claw tip.
     * The attack bolts should start at the orb.
  4. With DefenceFX installed, check that the `Glow*` parts pulse and sparks come off the four toroid nodes
     (`Pivot_Spark1..4`).
  5. Break the tower (`BuildHealthService`) and check that the fade and restore look right. There are no transparent
     authored parts, so a restore to 0 is correct.
* **Sounds:** none needed for the model. DefenceService already plays "Zap" and "Electric Buzz" at the orb on each
  attack.
* **Spare budget:** 1 part.

## Fix pass (2026-09-24, after review)
* **Claws opened.** The idle arcs now have about 0.45 studs of open air to jump, up from 0.14.
  * The tips moved from polar(1.0, 11.92) to polar(1.33, 11.97), and the elbows from polar(1.42, 11.02) to
    polar(1.58, 10.98).
  * The ProngTip order and the height (12.17) are unchanged.
* **Tip balls cap their rods.** `Claw<i>Upper` now ends at the tip centre (it used to stop 0.17 short).
* **Plinth tops** step up by 0.02 instead of 0.01.
* **HV-sign bolt:** it has a horizontal `Sign*BoltLink` block and the usual ⚡ orientation (it used to be mirrored).
  The 2 new parts are paid for by cutting `DrumLidBolt` from 8 to 6. The model is still 139 / 140 parts.
* **Orb spin not changed (not a defect).** The Orb is a uniform ball, so its spin is hard to see. The rig contract
  allows only one `Orb` part, so a spin marker would break it. The life comes from the arcs, the Glow pulse and the
  toroid sparks instead.
