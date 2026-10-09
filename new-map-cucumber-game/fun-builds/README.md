# Fun builds (New Map Cucumber Game, 2026-09-24)

User request: bigger builds where they should be bigger (post lantern, seesaw), every fun build functional
(TV with videos/slideshows, bouncy trampoline, working seesaw ...), new household furniture/appliances, nicer
defence towers, and hit effects from defences (freeze tower = blue particles on every enemy hit).

## Current place contents (edit DM; not saved or published)
* **Scaling** - `BuildCatalog.SCALE` / `ScaleOf(key)`; `BuildService.MakeTemplate` scales every template about its Hitbox
  and stamps `Scale` + `AuthoredCentre`, keeps `Pivot_*` / `State_*` attributes, and sets `ModelStreamingMode = Atomic`.
  Post lantern x2.1 (4.6 -> 9.7 tall), seesaw x1.8 (7.9 -> 14.2 long), trees x1.6, trampoline/slide/TV/hot tub ~x1.5 ...
  Defences stay x1 (DefenceService reads their pivots unscaled).
* **Framework** - `RS.Modules.FunBuildKit`, `SSS.FunBuildService`, `SPS.FunBuildClient`, `RS.Modules.FunAssets`
  (every sound / music / video / picture id, all load-verified). Behaviours = `ServerStorage.FunBehaviours.<Base>` (32)
  + `ReplicatedStorage.FunBehavioursClient.<Base>` (41). Contract for authors: `CONTRACT.md`. Helper parts live in
  `workspace.FunBuildRuntime`; seats via `ctx:Seat` (Lie = true lays people flat); prompts hidden in build mode;
  behaviours restart on move and stop while `Broken`. Dev hook: `workspace:SetAttribute("FunBuildDev", "list"|"restart")`.
* **Fun builds made functional** - TV (on/off, 8 channels: 4 Roblox videos + 4 slideshows, static, CRT on/off),
  Trampoline (growing bounces 13 -> 33 studs, mat dip), Seesaw (2 seats, one rider tilts, two riders see-saw),
  Slide (climbable ladder, seated ride, "Slide!" prompt), HotTub (4 seats, bubbles/steam), DJBooth (8 APM tracks,
  synced, spotlights) + DanceFloor (patterns, dance button), Hammock (lie + swing), BeanBag (sit + squash),
  VendingMachine (free cosmetic snack + drink animation), ArcadeCabinet ("Cucumber Catch" mini-game + high score),
  GlassCase (spinning trophies), NeonSign (flicker / chase), garden: lanterns + tiki torches lit, fountain jets, pond koi,
  tree/sunflower sway, scarecrow crow, hay bale seats, bush rustle.
* **Home category** (22 builds, group assets, merged meshes): Sofa, Armchair, CoffeeTable, DiningTable, Bookshelf, Bed,
  Nightstand, FloorLamp, Fireplace, Piano (playable 2-octave GUI, others hear it), GrandfatherClock (day/night time),
  Fridge, Stove, SinkCounter (tap + toaster), Microwave, WashingMachine, Dryer, Bathtub, Toilet, GamingDesk, Aquarium,
  PottedPlant - each with its behaviour. Build-menu button "Home" with a house glyph (`BuildMenu.Templates.Icons.Home`);
  the category row shrinks to fit narrow phones (BuildMenuClient.Fit).
* **Defences rebuilt** (group assets): FreezeTower, LaserGate, TeslaCoil, Mortar, Minigun, Turret - same rig contract,
  old MeshPart models in `ServerStorage.__BuildsBackup_2026_09_24.Defences`. Minigun SpinRate 1440 -> 480 deg/s (no strobe).
* **Hit effects** - DefenceService `HitFX` queue -> `Remotes.DefenceFX` (per player, within 280 studs) ->
  `SPS.DefenceFXClient`: frost ice bursts + frosty tint + ice crystals (ice block on a pulse stun), tesla sparks,
  laser embers, turret/minigun impact sparks, mortar shockwave, catapult dust, spike sparks; idle Glow* pulses and
  Pivot_Mist / Pivot_Spark emitters on the new defences.

## Round 2 (2026-09-24, user)
* "make tv slightly bigger and make tv play with sound": SCALE.TV 1.45 -> 1.7; videos play their sound by default
  (VIDEO_VOLUME 0.8, fading 28 -> 70 studs, `Sound = false` mutes a channel); slideshow channels carry `Music`
  (looped APM track, 3D sound on the screen, synced to the channel clock). Verified: volume 0.74 at 26 studs, music on ch 5.
* "above each defense have an overhead ui that shows damage (same symbol as pets damage indicator) and shows range":
  DefenceService STATS -> template attrs StatDamage / StatDamageSuffix / StatRange; `SPS.DefenceStatsClient` draws
  "[Ammo icon 15403025691] 100  [range glyph] 45" in studs over each placed defence (lifts over the health bar, hidden
  while Broken; the boost pad has none). Range glyph = ring + centre dot + radius line with a bead (frame-drawn).
* "make laser gates taller, wider, make the pillars less thick": LaserGate v2 (12 wide, ~10 tall, 1.1-stud pylons, six
  beams Beam1..6 at y 1.5..9, x +/-4.75); DefenceService LASER HalfWidth 4.75 / Height 9.8 / MaxBeams 8.

## Pipelines
* Models: `models/build_<Key>.py` (primlib = Roblox primitives in Roblox coordinates) ->
  `blender -b --factory-startup --python models/run_one.py -- <Key>` (parts.json + renders) ->
  `models/export_mesh.py` (merge unscripted parts per look, keep every name a behaviour uses) ->
  `tools/upload_models.ps1 -Keys ... -KeyFile <scratch key>` (Group Frenzy 14583228; ids in `models/out/asset-ids.json`) ->
  `install/install_mesh.lua` via `serve.ps1 -Root models/out` (yaw fix + look re-apply). Parts-only fallback:
  `install/install_models.lua`. Line-up review in the live Blender MCP: `models/lineup.py`.
* Scripts: `tools/stage.ps1` (luacheck + flat stage) -> `install/install_behaviours.lua`; shared scripts patched
  surgically with `pets-remake/mkpatch.py` + `apply_patches.lua`. Syntax check: `tools/luacheck.ps1`.
* Mirrors of every changed live script: `live-after/`. Pre-change backup: `backups/NewMap_fun-builds_before_2026-09-24.rbxm`.

## Verified in a playtest (2026-09-24)
No errors/warnings from any behaviour. TV video (1280x720) playing; trampoline 12.7/18.7/28/33-stud bounces;
seesaw two-rider oscillation (rider +-1 stud); slide ride 40 studs/s; bed/hammock/bath lying; every seat;
lamps, fireplace, stove, tap, toaster, microwave, fridge, washer/dryer, flush, fish feeding, trophy, neon switch, DJ
music; arcade GUI; broken -> all behaviours stop, healed -> restart; build-mode Home category + a real Sofa placement;
freeze tower ice crystals + tint on zombies (196+ FX events per raid); category row on iPhone 7 (666 px) fits.

## Known limits
* TV videos play with sound since round 2; whether each stock Roblox clip actually carries audio is unverified by ear.
* Trampoline tops out ~33 studs - enough to hop a 12-stud wall.
* Scaled builds that were already placed/saved may now overlap neighbours (restores never validate).
* Prompts that share E with a closer prompt only show when you're nearest to them (normal Roblox behaviour).

## Round 3 (2026-09-24, user)
* "make the gaming desk make u play the actual game (the cuke run thing)": GamingDesk is a real game now - sitting opens the
  `CukeRun` ScreenGui (jump Space/W/Up/click/tap, hold = higher; duck S/Down under drones; Enter = play again;
  Backspace/X/EXIT = stand up), keys captured by ContextActionService at high priority + controls off while playing;
  deterministic sim (seed + input events, 120 Hz fixed step) so other clients' monitors replay the real run 0.3 s behind;
  server validates inputs + scores (Fun_Seed / Fun_Since / Fun_EndTick / Fun_Best). Verified: Space keeps you seated,
  Enter = new seed, Backspace stands you up and restores jumping, desk record shown.
  GOTCHA: the first client build had 222 top-level locals - Studio's compiler caps a function at 200 (the rokit luau
  CLI accepted it) -> `tools/fold_locals.py` folded 42 look constants into `LOOK`; `tools/luacheck.ps1` now wraps the
  source in a function (still misses the 200 cap on this CLI version - install_behaviours' Studio loadstring is the real check).
* "make stats of each defense only show in build mode": DefenceStatsClient follows PlayerGui.CucumberHUDDesign BuildMode.
* Guardians: 2x chase speed at the start of a chase until within 20 studs (GuardianService CATCHUP_MULT / CATCHUP_UNTIL).
