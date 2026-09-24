# RAS - Dev lobby models - brief (2026-09-24)

The game: **RAS ("Roll A Snowball")** on Roblox. Players stand on a lobby platform at the top of a mountain, hold to
charge a launcher (shovels, scoops, slings, cannons...), fling a snowball down the mountain, it rolls, grows and smashes
props, they earn coins + XP, buy better snowballs and launchers in the **Shop**, rebirth, and at level 100 **Ascend**
(a full reset for a permanent x13 multiplier). A **Gift** spot rewards players for liking the game / joining the group.

The lobby has three walk-up landmarks that we are REBUILDING (the current ones are generic grey asset-pack meshes with a
studded texture). Each sits on a coloured neon ring on the floor. The same three models are placed on all 8 mountain
lobbies: Frostpeak (white snow floor `ebf6fc`, steel-blue rock `6882a6`), Candy (browns + pastels), Volcano / Haunted /
Tech / Cosmic / Pirate Glacier / Christmas (mostly dark floors). So every model must read on a **white snow floor AND on
a dark basalt floor**.

| Key (file) | Replaces | What it must say at a glance | Size limits (studs) W(x) x D(y) x H(z) |
|---|---|---|---|
| `Shop` | `ShopCircle.Shop` (kiosk + canopy + merchandise, orange/slate) | "SHOP - buy snowballs + launchers here" | W 15-17.5, D 6-8, H 12-15 |
| `Ascend` | `Ascend` (steps + two pyramid-capped pillars, a big up-arrow with a halo, angel wings; yellow/white/slate) | "ASCEND - go up to heaven, huge power" | W 19-21, D 8-9.5, H 17-19.5 |
| `Gift` | `Group` (a green present with a bow, a thumbs-up on a post, a community board with 3 faces; green/slate/yellow) | "Like the game / join the group - get a gift" | W 17-20, D 5.5-8, H 11-14 |

A player (R15 avatar) is ~5 studs tall - the red blockout in every render.

## Functional rules (do not break these)
* **Front = +Y in Blender.** It faces the lobby centre / the player walking up. Nothing important on the back only;
  the back must still look finished (players walk around).
* **Origin = centre of the footprint on the floor** (bounding box centred on x = 0, y = 0; the floor is z = 0). Nothing
  more than 0.3 below z = 0. `finish()` reports problems - the list must be empty.
* **Shop:** the floor in FRONT of the model is the ring players stand in; keep the counter front clear. A counter top
  around 3.2-3.6 studs high reads right next to a 5-stud avatar.
* **Ascend:** the trigger that opens the Ascend panel is this model's bounding box (+4 studs), so stay inside the size
  limits. The biggest wing mesh MUST use `mesh="Ascend_05_Wings"` (the game floats an "ASCEND!" billboard 4 studs
  above that part's top, so that label should cover the main wing span and sit high on the model). If the wings have a
  second look (e.g. tinted tips) give it a different label, e.g. `WingTips`.
* **Gift:** it is centred on a gold ring (20 studs across); no gameplay attaches to it.
* Words allowed as 3-D text: SHOP, ASCEND, LIKE, GIFT, JOIN (nothing else; no prices, no "FREE", no brand names).

## Style - the three must look like ONE set
* Chunky, toy-like, slightly exaggerated shapes; bevelled edges on boxes (0.08-0.25); flat shading on hard surfaces,
  smooth on round things (the helpers already do this). Strong silhouette readable from 40-60 studs away.
* No detail thinner than ~0.3 studs (it vanishes at lobby distance). Detail comes from GEOMETRY + COLOUR BLOCKING -
  the MeshParts are flat-coloured (no textures).
* 2-3 main colours per model + the shared gold / white / wood; clear contrast between neighbouring parts. White things
  near the floor need a darker/coloured base or trim so they don't melt into the snow floor.
* Palette to start from (`L.PALETTE`): snow `f4f8fc`, snow_shade `d7e6f2`, ice `9fd3ff`, frost `c4e8ff`, gold `ffc93c`,
  gold_dark `e0a526`, gold_neon `ffd54a`, wood `9a6238`, wood_light `c68c52`, wood_dark `6b4226`, slate `2c3a55`,
  slate_light `3b4a66`, orange `ff8c1a`, cream `fff1d6`, red `e8413c`, green `36c45a`, green_dark `1f9447`,
  blue `3a8cf0`, purple `a45de0`, marble `f3f5fa`, white `ffffff`.
  Suggested identity colours: Shop = orange/cream striped awning + wood + slate sign + gold; Ascend = marble white +
  gold + sky/ice blue glow; Gift = green + gold ribbon + a second present colour (red/blue/purple).
* Materials: `SmoothPlastic` (default), `Wood` / `WoodPlanks` for wood, `Marble`, `Snow` (snow caps), `Metal` sparingly,
  `Neon` ONLY for small glow accents (halo, sparkles, a lamp, a portal pane with transparency ~0.3) - the lobby has
  Bloom and big Neon areas blow out to white. No Glass.
* Collide: structure `collide=True`; floating or tiny decor (sparkles, halo, glows) `collide=False`.
* 3-D text: `m.text(name, "SHOP", size, depth, hex, loc=..., font="gill")` - Gill Sans Ultra Bold, faces +Y, reads
  correctly from the front (check the front render). Mount letters ON a board/banner, slightly proud of it.

## Budget
* <= 30,000 triangles per model in total; <= 9,000 per merged mesh (finish() flags it); ideally 8-18 mesh labels per
  model (parts with the same label AND the same look merge into one MeshPart; give labels meaningful names like
  `Awning`, `Counter`, `Sign`, `SignLetters`, `Goods`, `Steps`, `Pillars`, `Halo`, `Present`, `Ribbon`...).
* Sphere subdiv 2 for small balls, 3 only for big hero spheres; cylinders 12-24 segments; text resolution is fixed low.

## Tools (read `lobbylib.py` - it is short)
* `models/build_<Key>.py` defines `build(L)` and returns `m.finish()` where `m = L.Model("<Key>", kept=[...])`.
* Helpers: `m.box`, `m.cyl` (cone with r2), `m.sphere` (scale= for ellipsoids), `m.prism` (extrude a 2-D outline,
  bevel=, matrix=), `m.lathe` (revolve [(r, z)...]), `m.torus`, `m.tube` (lofted polyline, per-point radii), `m.text`,
  `m.custom(name, fn)` for anything else (`L.D` = defenses/defenselib.py: wedge, pyramid, rock, torus, prism, tube,
  cone, chevron_pts...). 2-D outlines: `L.circle_pts`, `L.rounded_rect_pts`, `L.star_pts`, `L.arc_pts`,
  `L.leaf_pts` (feathers!). Transforms: `L.xf(loc, rz=, rx=, ry=, scale=)` (4x4).
* Build + render (headless, a fresh scene, ~3-10 s, safe to run in parallel with the other builders):

      "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python "C:/Users/shrey/OneDrive/Documents/RobloxGames/ras-dev/lobby-models/run_one.py" -- <Key> 2>&1 | grep -E "REPORT|RENDERED|ERROR|Error|Traceback|line [0-9]"

  -> `out/<Key>.json` (sizes, merged meshes, tris, problems) + `renders/<Key>_front.png`, `_three.png`, `_back.png`
  (snow floor) and `_lobby.png` (from ~45 studs on a dark floor). LOOK AT THE RENDERS with the Read tool after every
  change. Do NOT use the Blender MCP tools (the live Blender is reserved for the lead's central review).
