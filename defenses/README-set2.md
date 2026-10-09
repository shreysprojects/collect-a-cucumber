# Defence set 2 (2026-09-16): Mortar, Tesla Coil, Freeze Tower, Minigun, Laser Gate

User: five reference renders (dark charcoal low-poly props with one accent colour each) -
"build these with blender mcp and import into roblox using my opencloud key (group key, Group
Frenzy), add them into the game as defenses users can place down in build mode, script each
defense": Mortar = explosive shells in a high arc, heavy splash, slow, long range; Tesla Coil =
chain lightning between clustered enemies; Freeze Tower = slows everything nearby (upgrades could
freeze completely); Minigun = single target, extremely high sustained damage after a spin-up; Laser
Gate = beams across an entrance, continuous damage while crossing.

## Blender (headless)
The Blender MCP addon was not running, so the props were built with Blender 4.5 in background
mode through the existing `defenselib.py` (`STYLE.md` rules) by five parallel agents, one prop
each, from `BRIEF-2026-09-16.md` (the shared palette + one section per prop written from the
reference images: forms, sizes, part names, rig groups, PIVOTS). `run_headless.py` builds ONE
script into `defenses.blend` without saving it (so five can run at once), prints the REPORT,
renders `renders/<Prop>.png` + `<Prop>_eye.png`, exports `fbx/<Prop>.fbx` and
`fbx/<Prop>.manifest.json` (parts with hex / material / transparency, pivots, states, notes).

| Prop | script | parts / tris | size (studs, Blender x y z) | rig |
|---|---|---|---|---|
| Mortar | `build_mortar.py` | 14 / 1112 | 6.28 x 6.28 x 7.51 | Base* static, Mount* yaw, Tube* pitch about (0, 0, 4.0); MuzzleTip (0, 2.008, 6.867); built at 55 deg |
| TeslaCoil | `build_tesla_coil.py` | 14 / 1292 | 6.84 x 6.84 x 9.85 | static; Orb spins; OrbCentre (0, 0, 9.0); ProngTip1..4 (+-0.853, +-0.853, 9.585); CoilGlow = Neon |
| FreezeTower | `build_freeze_tower.py` | 15 / 1232 | 6.85 x 6.91 x 9.79 | static; Orb (Neon) spins; OrbCentre (0, 0, 8.68); Ice* parts SmoothPlastic |
| Minigun | `build_minigun.py` | 18 / 1576 | 6.84 x 7.24 x 5.60 | Base* static, Head* yaw, Spin* rolls about BarrelAxis (0.45, *, 4.1) along +Y; MuzzleTip (0.45, 3.8, 4.1) |
| LaserGate | `build_laser_gate.py` | 20 / 1120 | 7.98 x 2.62 x 6.40 | static; Beam1..4 (Neon, z 2/3/4/5) span x -1.95..1.95; PillarL* / PillarR* |

Palette (this set, not the first set's blue-grey): body `45474d` / `565962` / `6a6e78`, bolts
`2f3136`, ice `9ed6ff` + orb `bfe4ff` Neon, laser `ff2f2f` Neon, tan `c8b276`, Tesla blue
`4f7fc2` + `35a7ff` Neon + orb `7fb3e8` Metal.

## Upload + install
`upload-set2.ps1 -KeyFile <scratch key>` runs `assets/benches/upload-model.ps1` per FBX as a
GROUP-owned Model (14583228) and writes `fbx/asset-ids-set2.json`:
Mortar 109345820438797, LaserGate 112459231146713, TeslaCoil 76620249287317, Minigun
135523957568572, FreezeTower 104160326837517. The key lived in the session scratchpad only and
was deleted afterwards.
`install_set2.lua` (served by `pets-remake/serve.ps1 -Port 8767 -Root defenses/fbx`, run through
execute_luau in edit mode): LoadAsset -> strip the `<Collection>.` prefix -> undo the importer's
180-degree yaw -> recolour from the manifest -> anchor (the four Beam parts do NOT collide, so
zombies walk through the gate) -> `WorldPivot = identity` (min-Y 0) -> attributes Cost / AssetId /
PropSet "defence2" / Tris / Notes / `Pivot_<Name>` (Roblox space: `(x, z, -y)`) / `State_<Name>`
-> `ServerStorage.Builds.Defences.<Prop>`. Costs: Mortar 3500, TeslaCoil 4000, FreezeTower 3000,
Minigun 5000, LaserGate 2000 (edit the Cost attribute to re-price). Build mode lists them
automatically (the folder IS the catalog; display names "Tesla Coil" etc. from SplitCamel).
`ZombieCatalog.BUILD_HEALTH`: Mortar 350, TeslaCoil 350, FreezeTower 450, Minigun 450, LaserGate 300.

## Behaviour (`ServerScriptService.DefenceService`, mirror `new-map-cucumber-game/zombie-raid/DefenceService.server.lua`)
The template BuildService makes drops the authoring attributes, so a set-2 defence reads its
rig from the SOURCE model (`Builds.Defences[Source]`: Pivot_*) and its authored origin from the
placed Hitbox: `origin = Hitbox.CFrame * CFrame.new(-source bounding-box centre)`. Part groups
are found by name prefix and posed relative to that origin (Head* / Mount* yaw about the origin's
Y, Tube* pitches about PitchPivot, Spin* rolls about BarrelAxis along the prop's Z).

| Defence | numbers (DefenceService config table) |
|---|---|
| Mortar | Range 75, MinRange 12, Interval 3.6 s, Damage 60 splash, Radius 10 (half at the edge), Flight 1.7 s, Arc 24; Mount* turns 240 deg/s, fires inside a 10-deg cone at the target's predicted spot; shell with a smoke trail, orange burst flash, fire + smoke puffs, "Big Break" + "Big Thud"; recoil dip on the tube |
| TeslaCoil | Range 28, Interval 1.5 s, Damage 18 then x0.75 per hop, Chain 3 (4 zombies), ChainRange 12; jagged neon bolts orb -> zombie -> zombie, hit flashes, "Zap" + "Electric Buzz"; idle arcs orb -> prong tips every ~0.7 s; the orb turns 60 deg/s |
| FreezeTower | Radius 24 (flat), every 0.5 s: Slow 0.8 s (ZombieRaidService SLOW_MULT 0.45) + Chill 2 damage on every zombie inside; frost puffs; a translucent neon aura disc on the ground breathes; snow off the orb. FreezePulse: a placed model with attribute `FreezePulse = true` also stuns everything inside for 1.5 s every 10 s (burst + "Magic Zoom") - the "briefly freeze completely" upgrade, off by default |
| Minigun | Range 42, Interval 0.08 s (12.5 shots/s), Damage 4 (50 dps), locks ONE target and keeps it while it lives and stays in range; Spinup 1.2 s (barrels roll up to 1440 deg/s, "Riser") before the first shot, Spindown 1.6 s; thin yellow tracers with a little spread, "Zap" every 3rd shot |
| LaserGate | no target: every 0.1 s a zombie whose root is inside the gate volume (x within 1.95 of the centre, y 0..5.5, z within 1.25) takes 25 x 0.1 damage (25 dps: ~8 per walking crossing, ~20 slowed, the full rate while stuck at the pillars), sparks + "Electric Buzz" per zombie every 0.35 s, the beams flicker; idle shimmer on the beams; red PointLights on the beams |

Broken (BuildHealthService) idles every one of them; a moved build carries its origin along.
