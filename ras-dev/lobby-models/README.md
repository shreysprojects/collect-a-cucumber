# RAS - Dev lobby models (Shop / Ascend / Gift) - 2026-09-24

The three walk-up landmarks on every mountain lobby, rebuilt in Blender and shipped as Group Frenzy mesh assets.
`shots/before_after.png` = the Frostpeak lobby in Studio before / after.

| Key | In the place | Group Frenzy asset (v2) | Notes |
|---|---|---|---|
| `Shop` | `Maps.StartPlatforms.<Mountain>.ShopCircle.Shop` (+ `Maps.Attachments.StartPlatform.Circles.ShopCircle.Shop`) | 113600514796047 | snowy market stall: striped awning, SHOP sign, snowball pyramid, cannon, coins, pegboard launchers; the ShopCircle "SHOP" billboard is raised by however much taller the model is (+3.5 studs at Frostpeak) |
| `Ascend` | `Maps.StartPlatforms.<Mountain>.Ascend` (+ `Attachments.StartPlatform.Ascend`) | 105736693974282 | heaven's gate: marble steps on clouds, columns, ASCEND plaque, blue neon portal with gold chevrons, feathered wings, halo; HUD `CIRCLE_PANELS.Ascend` = this model's bounding box + 4 opens the Ascend panel; the "ASCEND!" attention billboard adorns the mesh `Ascend_05_Wings` |
| `Gift` | `Maps.StartPlatforms.<Mountain>.Group` (+ `Attachments.StartPlatform.Circles.GroupCircle.Group`) | 92458517819488 | big present + LIKE thumbs-up badge + JOIN group sign + minis + sparkles; keeps the name `Group`; centred on `GiftCircle` (untouched - the gift checklist trigger reads that ring), turned 25 degrees toward the spawn pad on the mountain lobbies |

v1 uploads (superseded, unused): Shop 118103744075088, Ascend 96007488952799, Gift 138344047895325.

The models live in `ServerStorage.Assets` (not in the Rojo tree), so they are Studio-only: publishing the place ships
them. No script changed. One lobby tweak: `ShopCircle.LightCore.PointLight` was red `f6381e` on an orange ring and
tinted the stall pink/maroon in the engine; it now uses the ring's own colour `ffb000` (original in attribute
`LobbyOrigColor`, all 8 platforms + Attachments).

## How it was made
* `BRIEF.md` = the design contract. Three builder agents (one per model) wrote `models/build_<Key>.py` against
  `lobbylib.py` and iterated on headless renders; an independent critic reviewed each, a fixer applied it; then a
  second round used REAL Studio screenshots (`shots/v1_*.png`): a set judge measured the in-engine colours and fixed
  a shared palette (gold `ffad2b` / dark gold `d4861e` / neon gold `ffa82e` - `ffc93c` read lemon-yellow under the
  lobby's cyan ambient; the Ascend portal went from Neon `9fd3ff` (bloomed to white) to Neon `3d9bff` at 0.15).
  `review_live.py` lines all three up in the live Blender through the Blender MCP for the lead's review.
* Budgets: Shop 28,088 tris / 33 MeshParts, Ascend 28,164 / 19, Gift 19,948 / 22 (largest mesh 5.6k tris).

## Pipeline
1. `models/build_<Key>.py` - `build(L)` using `lobbylib.py` (on top of `defenses/defenselib.py`). Conventions: 1 unit =
   1 stud, Z up, floor z = 0, front = +Y, origin = footprint centre; every part carries one flat look + a mesh label.
   Blender 5.2 renamed `Mesh.set_sharpness_by_angle` -> `set_sharp_from_angle` (lobbylib tries both).
2. Build + review renders headless: `blender -b --factory-startup --python run_one.py -- <Key>` -> `out/<Key>.json`,
   `renders/<Key>_{front,three,back,lobby}.png`. `tools/part_boxes.py -- <Key>` lists every part's box.
3. `blender -b --factory-startup --python export_mesh.py -- <Key>` -> `out/<Key>.fbx` (parts merged per (label, look))
   + `out/<Key>.mesh.json` (looks by name + `colliders`).
4. `upload.ps1 -Keys Shop,Ascend,Gift -KeyFile <scratchpad key file>` -> Group Frenzy (14583228) Model assets,
   ids in `out/asset-ids.json`. The API key never goes into the repo.
5. **RAS - Dev cannot `InsertService:LoadAsset` a Group Frenzy model** ("User is not authorized to access Asset" - the
   place belongs to another group), but the MESHES inside are usable: run `tools/fetch_meshids.lua` in the user-owned
   New Map place (read-only, nothing parented; POSTs `<Key>.meshids.json` to `studio-shots/receive-b64.ps1` on :8768),
   move the files into `out/`.
6. Studio (RAS - Dev edit DM): serve `out/` with `pets-remake/serve.ps1 -Port 18781 -Root <out>` (copy
   `install_lobby.lua` into `out/`), then per key `loadstring(HttpService:GetAsync(BASE .. "install_lobby.lua"))()(BASE, "<Key>")`
   (`, true` = dry run). It rebuilds the MeshParts with `AssetService:CreateMeshPartAsync(Content.fromUri(meshId))`,
   undoes the importer's 180-degree yaw (`CFrame.Angles(0, pi, 0) * cf`), re-applies the looks, adds the colliders and
   places a copy on every platform at the old model's footprint centre / yaw, standing on the platform Root height,
   scaled by old height / the Frostpeak original's (Frostpeak 1, the other seven ~1.157). Re-running with a new upload
   re-uses the stamped `LobbyFrame` / `LobbyScale`. The first run on freshly uploaded meshes can outlast the ~20-30 s MCP
   timeout: check `get_request_status` / the DataModel before retrying (a blind retry raced the late first run once).

## Collision
Each merged look-group spans islands all over its model, and Roblox's convex decomposition bridged them into invisible
walls (measured: the Launchers / GoldBits / Clouds hulls stood across the whole front). So every MeshPart is visual
only (CanCollide / CanQuery false, Box fidelity) and the solid volumes are invisible anchored `Collider` Parts: the
box of each part named in `models/colliders.json` (fnmatch patterns) plus explicit boxes - the Shop's `StallVolume`
fills the stall up to the awning because a Humanoid steps straight up onto the 3-stud counter otherwise. Verified in a
playtest: raycasts with RespectCanCollide hit exactly the counter face / present box / steps / portal, a walking
player stops at the counter and the present, and walks up the Ascend steps onto the dais.

## Backups
* `backups/RASDev_lobby-models_before-rebuild_2026-09-24.rbxm` (RobloxGames repo): all 27 original models.
* In the place: `ServerStorage.Backups.Lobby_before-rebuild_2026-09-24/<Platform>/{Shop, Ascend, Group}`.
* `shots/before_*.png` / `after_*.png`: the Frostpeak lobby before and after.
