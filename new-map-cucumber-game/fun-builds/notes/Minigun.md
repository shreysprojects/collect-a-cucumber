# Minigun: rebuilt as a gold-trimmed gatling turret (2026-09-24, package DefMinigun)

**Model source:** `FB\models\build_Minigun.py` (primlib). Output: `FB\models\out\Minigun.parts.json`.
Install it as `ServerStorage.Builds.Defences.Minigun` (category "Defences").

**Renders** (all in `FB\models\renders\`):
* `Minigun_front.png`, `_three.png`, `_back.png`
* Extra views: `Minigun_detail_left.png`, `Minigun_detail_right.png`, `Minigun_top.png`
* `Minigun_posed_yaw60_roll30.png`: the rig posed the way DefenceService poses it

**Behaviour modules:** none. Only the existing `DefenceService` (server) and the new DefenceFX client animate it.

## The look
The old model was an 18-MeshPart charcoal-and-tan blockout. The new one is built from real Roblox parts: gunmetal
`434d5f` and steel-blue `6b7893` Metal, near-black `23262c`, bright steel `9aa7b8`, **gold `f2c13d` as the
top-tier accent**, brass `d9a441` cartridges, hot-orange Neon `ff8a1a` glows and red Neon `ff2f2f` "eyes".

* **Base** (static):
  * An octagon of 8 sloped armour plates (alternating gunmetal and steel-blue) around a core drum.
  * A gold rim and a diamond-plate deck on top.
  * Four diagonal outrigger legs with hydraulic rams, ending in diamond-plate feet with gold bolt caps.
  * A neon status light on each cardinal plate.
  * The static half of the yaw bearing: a steel race with a hot neon seam.
* **Head** (yaws):
  * **Heavy yaw ring:** a gunmetal ring with a gold band and 8 gold bolts. On it sit a neck and a pedestal.
  * **Armoured gun housing:**
    * Steel-blue top armour with a gold centre stripe and a glowing top vent (3 slats).
    * A glowing side vent grille on the -X side (4 slats in a frame), plus a casing eject port with a gold lip.
    * A front armour plate with gold bands and 4 bolts. A sloped glacis brow overhangs the barrel collar.
    * A steel collar with a gold lip.
  * **Scope:** a dark tube with gold rings and a red Neon lens facing -Z.
  * **Antenna:** a whip antenna with a red Neon tip.
  * **Drive motor:** at the back, with 3 steel cooling fins and a gold end cap.
  * **Ammo drum:** on the +X side (the viewer's left from the front), with gold rims, a steel face and a gold hub.
    * A belt of 8 brass cartridges with copper noses loops from the drum top into the feed port on the housing.
* **Spin** (the barrel cluster):
  * A steel-blue hub with 6 gold bolts and a central spindle.
  * **6 steel barrels**, held by a gold clamp and a dark clamp.
  * A dark muzzle block with 6 flared tips and black bores.

| Measure | Value |
|---|---|
| Footprint | 7.85 x 7.85, inside the 8 x 8 tile. The feet reach ±3.925 in x and z. |
| Height | 6.17 at the antenna tip. The scope top is 6.1; the barrel axis is at chest height, 3.875. |
| Parts | **138** (budget 140): Base 33, Head 76, Spin 29. |
| Neon | 9 parts. |
| Collision | 78 fine details have `collide=false`. |
| Cost | `Cost = 5000000000` (same as the live model). |
| Other attributes | `PropSet = "defence2"` and a `Notes` attribute. |

## Rig contract (DefenceService set-2 Minigun branch, no code change needed)
`check()` in the build script enforces all of this on every build.

* **Prefixes:** every part name starts with `Base` (static), `Head` (yaw) or `Spin` (barrel roll). Nothing else.
* **`Head*`** yaws about the vertical axis through the authored origin (x = z = 0). The farthest Head point is at
  horizontal radius **3.87**: the drum's outer rim corner, with the motor cap at 3.65.
* **`Spin*`** rolls about the line through `Pivot_BarrelAxis`, parallel to Z. The barrels point **-Z**.
  * Every Spin part is either a round cylinder centred on that line, or one of 6 copies at 60° steps (barrels,
    tips, bores and hub bolts), so the cluster is exactly balanced (imbalance 0.0000) and cannot wobble.
  * Swept through a full roll AND a full yaw, the farthest Spin point is at radius **3.88**: a bore rim at the muzzle.
* **`Pivot_BarrelAxis` = (0, 3.875, 0):** on the cluster axis, straight above the yaw axis.
  * The old one was (0.45, 4.10, 0). The axis is now centred, so the aim is exact (DefenceService measures the
    target direction from this point).
* **`Pivot_MuzzleTip` = (0, 3.875, -3.8):** on the axis, at the front faces of the barrel tips. The bores stand
  0.015 proud of it. It was (0.45, 4.10, -3.80). The tracers start here.
* **`Pivot_CasingPort` = (-1.34, 3.45, 0.47):** NEW and OPTIONAL, for FX only.
  * It sits just outside the casing eject port on the -X side of the housing: the gun's own left, which is the
    viewer's right when looking at the front.
  * It is authored at rest yaw, so it is a Head point: turn it with the head's current yaw before use. For example,
    compare `HeadHousing`'s live CFrame with its template CFrame, or reuse DefenceService's `Yaw`.
  * Good for a spent-casing spray while firing.
* **Origin:** the authored origin is the floor centre (min y = 0). The static base is symmetric in x and z (±3.925),
  and no Head or Spin part reaches past it. So the source bounding-box centre is (0, 3.085, 0), and `originOf`
  (Hitbox x -centre) lands exactly on the yaw axis.
* **Rest pose:** the model is authored at yaw 0 and roll 0 (barrels level, pointing -Z). That is the pose
  DefenceService expects when it records each part's `Rel`.

## For DefenceFX (the new client)
* **`*Glow*` Neon parts:** these may be pulsed or brightened, e.g. hotter while the barrels are spun up or firing.
  * Hot orange `ff8a1a`: `BaseGlowLight1`-`4` (the status lights), `BaseGlowSeam` (the yaw-bearing seam, static,
    round), `HeadGlowVent` (the -X side grille) and `HeadGlowTopVent`.
  * Red `ff2f2f`: `HeadGlowAntennaTip`.
  * Status light positions: 1 is at the back (+Z), 2 on the left (+X), 3 at the front (-Z) and 4 on the right (-X).
* **`HeadSightLens`** is the red Neon scope lens. It is not named `Glow`, but it is a good "target locked" blinker.
* **Muzzle flash:** use `Pivot_MuzzleTip`. **Barrel heat / spin:** use `Pivot_BarrelAxis`. **Casings:** use
  `Pivot_CasingPort` (see above).
* **No transparent authored parts.** BuildHealthService's broken fade and restore work as-is.

## Notes for the integrator
* **Install:**
  `install_models.lua` with `{"Minigun"}` and `{Backup = true}`. parts.json already says `"Defences"`.
  * The old MeshPart model moves to `ServerStorage.__BuildsBackup_2026_09_24.Defences`.
  * The old `AssetId` / `Tris` attributes are not carried over. Nothing in `live/` reads them.
* **Keep Minigun OUT of `BuildCatalog.SCALE`.** It is not listed today.
  * DefenceService reads `Pivot_*` from the SOURCE model unscaled, and caches the source box centre
    (`BoxCentres`).
  * If the Minigun is ever scaled, `def.Axis` / `def.MuzzleTip` / the centre must be multiplied by the template's
    `Scale`.
* **Placed Miniguns:** existing ones restore from the new template on the next server start (BaseSaveService clones
  the template).
  * If the source is swapped while a server is running, DefenceService's cached `BoxCentres.Minigun` is stale until
    a restart. Install in edit mode, then playtest.
* **Collisions:** the big masses collide (base, legs, feet, rings, housing, front plate, drum, motor, barrels).
  * The Head/Spin parts are CFramed by the server every tick, as before.
* **Test:**
  1. Place a Minigun and check the footprint: it fills the tile, and the feet sit at the tile corners.
  2. Start a night raid or spawn a zombie within 42 studs.
  3. The whole head turns toward the target (the drum, belt, scope and antenna turn with it). The base, legs, deck,
     race and neon seam stay still.
  4. The barrel cluster spins up in place with no wobble; any wobble means a wrong `Pivot_BarrelAxis`.
  5. Tracers leave from the barrel fronts.
  6. Break it (`BuildHealthService`): every part fades to 0.65, and all of them restore to opaque when it mends.
* **Sounds:** none are needed for the model. DefenceService already plays "Riser" and "Zap".

## Open issues / wishes
* The Blender MCP was not used. Per the contract, the model was authored and rendered with headless Blender
  (`run_one.py`), which is parallel-safe.
* **Optional FX wish:** DefenceFX could spray brass casings from `Pivot_CasingPort` while firing. It could also warm
  `HeadGlowVent` / `HeadGlowTopVent` from orange toward yellow-white while spun up.
