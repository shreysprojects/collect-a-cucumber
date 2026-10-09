# New Map Cucumber Game (placeId 87967102884366)

Work done 2026-09-05 through the Roblox Studio MCP (edit mode, no desktop input).

## Workspace layout after the reorganisation

```
Workspace
├─ Map
│  ├─ Lobby            Floor / Shops / Leaderboards / Stations   (everything at x >= 1144)
│  ├─ Biomes
│  │  ├─ 01 Spawn      (map label "Basic egg / lobby field", slab centre x=1074)
│  │  ├─ 02 Desert     (x=933)
│  │  ├─ 03 Samurai    (x=793)
│  │  ├─ 04 Farm       (x=653)
│  │  ├─ 05 Snow       (map: Frozen, x=513)
│  │  ├─ 06 Underwater (map: Ocean, x=373)
│  │  ├─ 07 Volcano    (map: Lava, x=233)
│  │  ├─ 08 Narmek     (map: Space, x=93)
│  │  ├─ 09 Toyland    (new: rainbow walls, clouds, duck, dice, blocks, x=-47)
│  │  └─ 10 Neon       (new: neon strips, cyan portal, x=-187)
│  │       each biome: Floor / Walls / Eggs / Portals / Chests / Decor
│  ├─ Borders          Lobby Border, Zombie Night Wall model, far end wall + its Text
│  └─ Dividers         the 10 "Level Line" models + the divider part at x=1003
├─ SpawnArea           Folder, parts "1".."10" (index = zone order, attribute Zone=<name>),
│                      CanCollide=false / CanQuery=true / Transparency=1 like the live game
├─ Terrain, Camera
```

`workspace.Breakables` does NOT exist in the saved place; the runtime script creates it.

Biome folders carry attributes `Zone`, `ZoneIndex`, `SlabX`, `MapLabel`. Every moved
instance carries `OrigIndex` (its original Workspace child index) so the layout can be
reverted mechanically; the whole operation is also one ChangeHistory waypoint.

Items were assigned to a biome by their bounding-box centre X (slabs are 140 studs
wide, boundaries at x = -117 + 140k). Note: "LeaderBoard Time" (x=454) and
"LeaderBoard Cukes" (x=878) physically sit inside the Snow and Desert slabs, so they
landed in those biomes' Decor folders, not in Lobby/Leaderboards.

## Runtime cucumber spawning

`CucumberSpawner.server.lua` = `ServerScriptService.CucumberSpawner` (Script). It is a
port of the population half of the live game's BreakablesService and runs only when
the game runs:

- fills `workspace.Breakables/<Zone>` from `workspace.SpawnArea/<index>` with the live
  type pools/weights, one guaranteed landmark tree, 4% golden, x0.75 template scale,
  padded random points snapped to the floor, spacing rules
- zones with a player (plus neighbours) get 7 sliced + 12 regular (scaling with player
  count up to 28 / 32); idle zones keep a 2 + 3 baseline and drain one per step after
  an 8 s grace, exactly like the original's paced worker
- destroying a spawned cucumber frees its slot, so future smash code gets refills for
  free; each holder has attributes `TypeName`, `Zone`, `Sliced`, `Golden`, `Template`
  and the CollectionService tag `Breakable`
- zone folders show live `Active` / `Sliced` / `Other` attributes while running
- Toyland and Neon have no hand-modelled set, so they use the generic pool + the
  procedural BuildCucumber with the tints in `ZONE_COLOR` (purple / cyan neon glow)

Templates live in `ServerStorage.Assets.BreakableModels` (59 models, 407 MeshParts,
copied from the live game). Damage / HP / rewards / pets are not part of this script.

## Transfer trick that worked

`import_rbxm` still times out (both 2026-08-27 and today). What works: `export_rbxm`
from the source place, copy the file into the running Studio's
`%LOCALAPPDATA%\Roblox\Versions\<version>\content\` folder, then in the destination
place run `game:GetObjects("rbxasset://<file>.rbxm")` via execute_luau (it returns the root list; `InsertService:LoadLocalAsset` is refused there).

## Plots (added 2026-09-05, later the same day)

`workspace.Map.Lobby.Plots` holds six 50 x 85 plot floors named `Plot 1`..`Plot 6`
(attribute `PlotIndex`, ordered by Z) lined up along the lobby's east wall at x~1267.
`PlotService.server.lua` = `ServerScriptService.PlotService`:

- every joining player gets a random free plot (attributes `Owner` / `OwnerName` on
  the plot, `Plot` on the Player); the plot is released when they leave
- the player spawns and respawns at the very front of their plot: an invisible
  SpawnLocation `PlotSpawn` is created at runtime 3 studs inside the west edge (the
  edge facing the lobby interior), and `Player.RespawnLocation` points at it; a
  CharacterAdded check re-pivots the character if the engine put it anywhere else
- `FRONT_DIRECTION`, `FRONT_INSET`, `FACE_INTO_PLOT` and `FALLBACK_SPAWN` are the
  config knobs at the top of the script
- with more players than plots the extra player spawns at the lobby centre and a
  warning is logged; set MaxPlayers = 6 in Game Settings

## Player data (ProfileStore)

Saving uses **ProfileStore** (loleris' successor to ProfileService: session locking,
auto-save, save on leave/shutdown, automatic mock store when Studio API access is off).
The library is `ProfileStore.luau` (verbatim from github.com/MadStudioRoblox/ProfileStore,
64,654 bytes) installed as `ServerStorage.DataService.ProfileStore`.

- `DataService.lua` = `ServerStorage.DataService` (ModuleScript): store `PlayerData_v1`,
  key `Player_<UserId>`, template `{Coins = 0, Cukes = 0, Playtime = 0}`
- `DataLoader.server.lua` = `ServerScriptService.DataLoader`: the one call to `Start()`
- each loaded player gets `player.Data` (Folder, **not leaderstats**) with NumberValues
  `Coins`, `Cukes`, `Playtime` that replicate to the client; server-side writes to those
  values are saved, and `DataService.Set/Increment/Get/WaitForData/OnProfileLoaded`
  are the API for other scripts
- `Playtime` = whole seconds in game across sessions, advanced once a second by DataService
- bump `STORE_NAME` to wipe everyone; set `USE_MOCK_IN_STUDIO = true` to keep Studio
  tests off the live DataStore

## Egg shop (ProximityPrompts + egg tools)

`EggShop.server.lua` = `ServerScriptService.EggShop`, `EggShopClient.client.lua` =
`StarterPlayerScripts.EggShopClient`.

- at server start every physical egg model under `Map/Biomes/<zone>/Eggs/<stand>` gets a
  `BuyPrompt` ProximityPrompt ("<Name> Egg" / "Buy (100 Coins)", 12 studs, 0.35 s hold);
  the egg name comes from the stand's EggName label (Basic, Desert, Samurai, Farm, Frozen,
  Ocean, Lava, Narmek)
- `EGG_PRICE = 100` for every egg; a `Price` attribute on the stand or egg model overrides
  it per egg later (no need to touch the script)
- buying charges Coins through DataService and equips a Tool built at runtime from that
  same physical egg model (cloned, scaled to `HAND_EGG_HEIGHT` 2.2 studs, meshes welded
  to an invisible Handle). Templates live in `ServerStorage.EggTools`; tools are named
  "<Name> Egg", CanBeDropped=false, attributes `EggName` / `Price`, tag `EggTool`
- `GRIP = CFrame.new(0, -0.9, 0.25)` with identity rotation keeps the egg upright in the
  R15 tool pose (a -90 degree X rotation cancels the hand attachment and lays it sideways)
- the client script shows a toast: "Not enough Coins! You need N more." / "Bought a X Egg!"
- hatching / what the egg tool does when activated is not implemented yet

## Egg placement (build on your plot)

Modelled on the DevForum "PlacementService" pattern (Plot part = bounds, placeable
models with a hitbox PrimaryPart, an item holder per plot, one RemoteFunction, server
re-validation). `EggPlacement.server.lua` = `ServerScriptService.EggPlacement`,
`PlacementClient.client.lua` = `StarterPlayerScripts.PlacementClient`.

- server start: `ReplicatedStorage.PlaceableModels/<Name> Egg` built from each physical
  egg (PLACED_SCALE 1 = stand size) with an invisible `Hitbox` PrimaryPart;
  `ReplicatedStorage.Remotes.requestPlacement`; a `Placed` folder inside every plot
- client: while an `EggTool` is equipped, a half-transparent preview of that egg follows
  the mouse over the player's own plot, snapped to `GRID_SIZE` (1 stud) and clamped so
  its footprint never leaves the plot; `R` rotates 90 degrees. If the spot overlaps
  anything in `plot.Placed` (GetPartBoundsInBox, same test as the server) the preview is
  covered in a red Highlight; otherwise it looks normal. Click / tap places.
  Uses Heartbeat rather than RenderStepped so it keeps tracking in an unfocused Studio.
- server: only trusts the client's X/Z + yaw, rebuilds the CFrame on the plot top,
  rejects "outside plot" / "occupied" / "cooldown" / wrong tool, then clones the model
  into `plot.Placed` (attributes Owner, EggName, tag PlacedEgg) and destroys the tool
- when a plot's Owner attribute clears (player left) its Placed folder is emptied
- placements are NOT persisted yet; hatching is still not implemented

## Changes 2026-09-05 (later): walkspeed, placement fixes, save-on-change

- `StarterPlayer.CharacterWalkSpeed = 30` (default was 16)
- PlacementClient: aims with `Mouse.UnitRay` (always under the cursor) and no longer
  smooths the preview, so the egg sits exactly where the cursor is; the preview is only
  shown while the player stands at their own plot (`AT_BASE_MARGIN` 6 studs outside the
  edge); EggPlacement rejects placements with "not at base" for the same rule
- DataService: every change to Coins / Cukes (any key except Playtime) is written to the
  DataStore immediately via `Profile:Save()`, coalesced to at most one write per
  `SAVE_DEBOUNCE` (5 s) per player; Playtime rides along and the periodic auto-save is
  now every 60 s (`AUTO_SAVE_PERIOD`). `DataService.RequestSave(player)` forces one.
  Verified: a coin change was readable from the raw DataStore 1 s later.

## Sound system (ported from the Zombie Cucumber Game)

- `ReplicatedStorage.Assets.Sounds`: the 47 SFX Sound templates copied verbatim (Click Sound,
  Collect, EggPop, Cucumber Break, Cash Register, ... with their AuthoredVolume attributes)
- `SoundService."Background Music"`: the lobby/game track, looped, volume 0.3, Playing=true,
  SoundId **rbxassetid://1846271108** (the original used 1841974586)
- `ReplicatedStorage.Modules.SoundController` (`SoundController.lua`): the original API made
  standalone. Server `PlaySound(name, parent?, opts)`; client `PlayFX(name, opts)`,
  `PlayFXAt(name, position, opts)`, `PlayerSoundClient(name)`. SFX gate: `SetSFXEnabled(bool)`
  or LocalPlayer attribute `SFXEnabled = false` (replaces the old SettingsController check)
- `ReplicatedStorage.Modules.MusicManager` (`MusicManager.lua`): verbatim port; fade
  Play/Pause/Stop/Resume, tag ducking (`SetDuck(tag, factor)`), `SetMuted`, `IsMuted`
- `StarterPlayerScripts.MusicClient` (`MusicClient.client.lua`): registers + fades in the
  track and mirrors the LocalPlayer attribute `MusicMuted` into MusicManager
- `SoundService.RespectFilteringEnabled = true` as in the original
- known: the "Electric Buzz" template (rbxassetid://8278770516) is an archived asset and logs
  "Failed to load sound" on every client; it is the same in the original game. Replace its id
  or delete the template.

## Bench press (Blender) + lie-down seat

- `assets/BenchPress.{fbx,obj,blend}`: low-poly bench press built with the Blender MCP,
  318 tris / 204 verts in 4 material objects (Pad, Frame, Bar, Plate), 1 unit = 1 stud,
  hidden faces stripped, exported Y-up / -Z forward, triangulated.
- Open Cloud upload (2026-09-05) FAILED: the key authenticates for reads (assets read,
  users, universes all 200) but every create request with a file + creator returns
  403 "User not authenticated" -> the key lacks the Assets API **Write** scope. Fix on
  create.roblox.com > Open Cloud > API keys > Assets API > Write. The pasted key's embedded
  token also expires ~1 hour after issue. Upload command that will work once fixed:
  `curl -X POST https://apis.roblox.com/assets/v1/assets -H "x-api-key: KEY" --form 'request={"assetType":"Model","displayName":"BenchPress","description":"...","creationContext":{"creator":{"userId":"140977250"}}}' --form 'fileContent=@BenchPress.fbx;type=model/fbx'`
  then poll `GET /assets/v1/operations/{operationId}` and `InsertService:LoadAsset(assetId)`.
- Meanwhile `workspace.Map.Lobby.Props.BenchPress` is a **part-built stand-in** with the
  exact same geometry/colours (attribute StandIn=true) at (1195, floor, 130) on the lobby
  walkway. Replace its visual parts with the imported mesh; keep `LieSeat`.
- `LieSeat` (Seat, invisible, CanTouch=false, tag LieSeat, attribute LiePose=true) is rotated
  so the seated pose lies on its back with the head at the rack; its `LiePrompt`
  ProximityPrompt ("Lie down") is handled by `BenchServer.server.lua`
  (`ServerScriptService.BenchServer`: seat:Sit on trigger, prompt hidden while occupied).
  `BenchLieClient.client.lua` (`StarterPlayerScripts.BenchLieClient`) stops the sit animation
  on LiePose seats so the body lies straight. Jump to get up. Verified in playtest: body 0.6
  studs above the pad, head at the rack end, no animation playing while lying.

## Bench press animation (the Blender way)

- Rack raised: bar now 3.5 studs above the floor (uprights 3.9) in both the Blender model
  (`assets/BenchPress.fbx/.obj` re-exported, still 318 tris) and the part stand-in, so a lying
  R15's near-extended arms reach the bar (hands end 0.19 studs under it).
- `assets/BenchPressAnim.fbx`: an R15 rig (bones named exactly like the R15 parts,
  HumanoidRootPart root, joint positions read from a Studio-built R15 via its RigAttachments,
  every bone pointing straight up with roll 0 so bone-local axes = Roblox joint axes) with
  skinned box bodies and a 2 s / 60-frame looping "BenchPress" action: frame 0 arms up to the
  bar, frame 30 bar at the chest (elbows out and down, forearms vertical), frame 60 = frame 0;
  legs static, thighs down to the floor. `assets/BenchPressAnim.json` holds the same poses as
  quaternions; `assets/BenchPress.blend` has everything.
- Verified in Studio: the same poses built as a KeyframeSequence + temporary id play on the
  lying character (arms to the ceiling at the top, chest height at the bottom).
- To publish: Studio > Avatar tab > Animation Editor > select an R15 rig (Rig Builder) > ...
  menu > Import > From FBX Animation > `BenchPressAnim.fbx`, then Publish to Roblox, and put
  the resulting `rbxassetid://<id>` into the `AnimationId` attribute on
  `workspace.Map.Lobby.Props.BenchPress.LieSeat`. `BenchLieClient` plays it looped
  (Action priority) whenever someone lies on the bench; empty attribute = neutral lying pose.

## Publishing the bench-press animation (state on 2026-09-05 evening)

- `ServerStorage.BenchPressAnimation` (KeyframeSequence, 3 keyframes, same poses as the FBX)
  exists in the place and is exported to `assets/BenchPressAnimation.rbxm`.
- Studio's own publish flow was triggered from the plugin context
  (`plugin:SaveSelectedToRoblox()` on the selected KeyframeSequence): the **"Asset
  Configuration" dialog is open in the New Map Studio window** with the name prefilled.
  Clicking Submit there publishes it as an Animation. It could not be clicked remotely:
  the Qt dialog exposes nothing to UI Automation and the user's Roblox game window was in
  front, so no focus stealing.
- Alternative that needs no clicking: Open Cloud accepts `assetType: "Animation"` with an
  .rbxm. `assets/upload-animation.ps1` does the upload + polling and prints the id; it needs
  an API key with Assets **Read + Write** in `ROBLOX_OPEN_CLOUD_API_KEY` (the key tried today
  had read only).
- Either way, finish by setting `LieSeat`'s `AnimationId` attribute to `rbxassetid://<id>`.
- **Published 2026-09-06:** the user clicked Submit; the asset is `BenchPressAnimation`,
  **rbxassetid://100549795320967** (found via the public inventory endpoint
  `inventory.roblox.com/v2/users/140977250/inventory/24`). `LieSeat.AnimationId` is set to it.

## Barbell in the hands (2026-09-06)

- Bar, collars and plates are grouped as `BenchPress.Barbell` (PrimaryPart = Bar). At server
  start `BenchServer` welds collars/plates to the bar (WeldConstraint), keeps the bar anchored,
  and stores `RackCFrame` / `Held` / `Holder` attributes + tag `Barbell`.
- While someone lies on the seat the server watches the fingertips' midpoint; once it is at bar
  height (±0.35), within 0.6 along the bar and within 1.2 studs along the bench (you lie with
  your eyes under the bar and unrack it forward), it sets `Held=true, Holder=<name>`.
- `BarbellClient.client.lua` (`StarterPlayerScripts.BarbellClient`) then places the bar every
  frame (once per frame: RenderStepped, Heartbeat only on frames RenderStepped skipped) at the midpoint of the holder's two hands, 0.15 studs toward
  the fingertips, with its axis running hand to hand and kept level, on every client. On
  `Held=false` (occupant left) it tweens the bar back to `RackCFrame` in 0.35 s.
- Verified: grab 0.32 s after lying down, bar within 0.07 studs of the hands through the press
  (1.1 studs of travel), axis alignment 1.000, all 7 parts along, returns to the rack on jump.
- Rejected first attempt: a Weld to the RightHand made the bar twist with the hand (78 degrees
  off lateral) and drift up to 1.7 studs from the hands' midpoint.

## Strength + "+1" popup (2026-09-06)

- `Strength` is a saved DataService value (template + `player.Data.Strength` NumberValue, not
  leaderstats; existing profiles get it via Reconcile).
- BenchServer counts reps server-side while the barbell is held: fingertips drop >= 0.85 studs
  below the rack height (bottom), then come back within 0.3 (top) = one rep -> `Strength += 1`
  (STRENGTH_PER_REP) and `Remotes.StrengthPopup:FireAllClients(character, 1)`.
- `StrengthPopupClient.client.lua` (`StarterPlayerScripts.StrengthPopupClient`) draws a
  BillboardGui on the lifter's Head: icon `rbxassetid://15403007921` (40 px) on the left, "+1"
  (FredokaOne 34, white, dark stroke) on the right; it rises 2.2 studs over 1.4 s and fades
  during the second half, then destroys itself. Every client shows it, so others see your reps.
- Verified: one rep per 2 s animation loop, Strength 0 -> 3 over three loops, popups with the
  icon loaded (the very first popup's image was still downloading at 0.15 s, later ones loaded).

## Gym platform + UPGRADES / QUESTS boards (2026-09-06)

Built from the user's mockup at the spot where they had moved the bench (between the old
`Upgrader` and `QuestBoard` stations, which showed the old game's vault upgrades; those two
models were removed, backup in `backups/NewMap_2026-09-05/OldUpgraderQuestBoard.rbxm`).

- `Map/Lobby/Props/GymPlatform`: lime base skirt + dark concrete slab (14 x 20 at
  1216.5, -17) with lime trim; the bench sits on the slab; two boards on posts behind the rack
  (`UpgradesBoard` at z=-21.4, `QuestsBoard` at z=-12.6, facing west toward the bench), each a
N
  Boards are Models tagged `GymBoard` with attribute `Board` = Upgrades | Quests; the
  SurfaceGui is `Face.BoardGui`, rows are `Rows/<Id>` with `Sub` and `Button`.
- `GymService.lua` (`ServerStorage.GymService`, started by `GymLoader.server.lua`): config
N (Lift 100 kg = 20 kg per rep, Do 50 Reps, Reach 1K Strength; rewards
  250 / 500 / 5000 Coins, claim once). Remotes `GymBoardState` (push) and `GymBoardAction`
  ("Buy"|"Claim"|"State", id). Data: `Upgrades` and `Quests` tables in the DataService
  template; BenchServer now calls `GymService.AwardRep`.
- `GymBoardsClient.client.lua`: renders this player's state into the workspace SurfaceGuis
  (local edits, so each player sees their own levels/progress), BUY / CLAIM buttons call the
  action remote, toast for the result. Quest buttons read CLAIM (grey until complete, gold when
  claimable, DONE after) instead of the mockup's BUY. Waits for streamed-in GUI children
  (workspace.StreamingEnabled is now on in this place).
N
- Note: ProximityPrompts never show while the Studio window is unfocused (RenderStepped = 0),
  so headless tests seat via `seat:Sit`; the E prompt is unchanged.

## Bench-press animation v3 (2026-09-06): no more twisting arms

Why the old clip twisted: every joint got the shortest rotation to a target direction, so the
elbow bent in an arbitrary plane and slerp rolled the arms about their own axis mid-rep; the
hands also slid along the bar (grip 2.1 -> 3.9 studs).

v3 builds the poses with joint mechanics (`BenchPress.blend`, action BenchPress4):
- elbows are pure hinges (rotation about the upper arm's local X) in the plane of upper arm and
  forearm; the same hinge axis is used at the top and bottom so nothing rolls while pressing;
  knees the same but bending backward
- grip fixed slightly wider than the shoulders (~2.5 studs), bar finishes above the shoulders
  and slightly back, bottom at mid/lower chest with the elbows ~63 degrees from the torso and
  just below the bench line
- wrists pronate 54-59 degrees so the palms/grip axis face the bar (real lifters do this)
- feet flat on the floor, head tilted slightly toward the bar

Measured in Studio (right hand, one rep): old clip hand roll vs bar 86 deg, grip 2.11-3.87,
elbow 4-148 deg; v3 hand roll 22 deg max, grip 2.26-2.70, elbow 8-129 deg.
Exported the same way: `assets/BenchPressAnim.fbx` (R15-named rig + baked clip),
`assets/BenchPressAnim.json`, `ServerStorage.BenchPressAnimation` (KeyframeSequence v3) ready
for Save-to-Roblox; the published id must then replace `LieSeat.AnimationId`
(currently the old rbxassetid://100549795320967).
- **v3 published 2026-09-06 as rbxassetid://132461296099170** (BenchPressAnimation);
  `LieSeat.AnimationId` now points at it (the old 100549795320967 is unused).
- Rep counter (2026-09-06): the fixed 0.85/0.3 thresholds stopped counting with clip v3 (its
  hands travel from 0.49 above to 0.82 below the rack). BenchServer now learns the fingertip
  height range per session and counts a rep when the hands go below the midpoint by 30% of the
  range and come back above it (REP_MIN_RANGE 0.5, REP_BAND 0.3). Verified: +level every 2.0 s
  from the first rep.

## Upgrade board rework (2026-09-06): Faster reps + Better benchpress

The three UPGRADES rows (Strength / Stamina / Speed) were removed and replaced by two:

| Id | Row | Effect per level | Cost (Coins) | Max |
|---|---|---|---|---|
| `FasterReps` | Faster reps (lightning icon) | bench-press clip plays 1.1x faster than the level before (speed = 1.1^(lvl-1)) | 150 * lvl | 15 |
| `BenchPress` | Better benchpress (weightlifter icon) | strength per rep doubles (1, 2, 4, 8 ... = 2^(lvl-1)) | 100 * 2^(lvl-1) | 20 |

- `GymService.lua`: UPGRADES config with an `Effect(level)` text; `StrengthPerRep(data)` and
  `RepSpeed(data)`; `AwardRep` pays `StrengthPerRep`; `Buy` and profile load set the player
  attributes `RepSpeed` and `StrengthPerRep`; the board state carries `Effect` per upgrade.
  The old Speed -> WalkSpeed effect is gone (WalkSpeed stays the StarterPlayer default 30).
- `BenchLieClient.client.lua`: after playing the clip it calls `track:AdjustSpeed(RepSpeed)`
  and re-applies on `GetAttributeChangedSignal("RepSpeed")`, so buying while lying down speeds
  up the current set. The adaptive rep counter in BenchServer follows any clip speed.
- `GymBoardsClient.client.lua`: `Sub` reads "Lv. N  -  <effect>" (e.g. "Lv. 2  -  +2 per rep",
  with a middle dot as the separator).
- `DataService.lua` template: `Upgrades = {FasterReps = 1, BenchPress = 1}` (old keys are
  reconciled in but ignored).
- Studio: the UpgradesBoard rows were rebuilt by cloning the old Strength row (same 54 px
  layout) into `Rows/FasterReps` and `Rows/BenchPress`; Strength/Stamina/Speed rows deleted.
- Verified in playtest: Lv.1 -> +1 per rep every 2.0 s; after buying Better benchpress +2 per
  rep; after buying Faster reps mid-set the track's Speed read 1.10 and reps came every
  1.82 s; board text and Coins updated on both buys. Test profile afterwards: Coins 500,
  Strength 44, both upgrades reset to Lv. 1 via a direct DataStore UpdateAsync.

## Bench-press tiers (2026-09-06): six themed Blender benches, one per Better benchpress level

Reference: the user's 6-tier mockup (Starter / Iron / Gold / Frost / Inferno / Cosmic). Built in
Blender through the Blender MCP; each tier is chunkier than the last (posts 0.24 -> 0.58 studs,
pad 0.95 -> 1.45 wide, bigger/more plates) but keeps the same functional anchors as the current
bench so the LieSeat, the grab detection and the bench-press animation work unchanged: floor at
the bench origin, pad top 1.3 studs up, bar at (+1.5, 3.5) running across the bench, hooks at
x 1.3..1.6, uprights' inner faces at 1.25 from the centre (thickness grows outward).

Files in `assets/benches/`:
- `benchlib.py` (bmesh primitives, rough/ice discs, octahedra, crystals; FBX export; preview
  render), `build_benches.py` (tier configs + generic frame/barbell + per-theme decor), the
  saved scene `BenchTiers.blend`, `<Tier>_preview.png` renders.
- `<Tier>_Bench.fbx` = frame + pad + decor as one object per Roblox material (Frame, Pad, Trim,
  Feet, Gems, Crystals, Glow, Lava, Bowls, Flames, Runes) plus a 0.1-stud `Anchor` cube at the
  origin for placement. `<Tier>_Barbell.fbx` = Bar (along local X, centred on the origin = part
  local X is the bar axis, what BenchServer/BarbellClient need), Collars, Plates (+ Rims / Glow).
  Bench-space coords: Blender X = bench length (rack at +X), Y = across, Z up; Roblox = (x, z, -y).
- Triangles (bench + barbell): Starter 460, Iron 664, Gold 1000, Frost 772, Inferno 1440,
  Cosmic 908. All flat-shaded, no textures (colours/materials applied per part in Studio).
- `manifest.json` = per-part hex colour, Roblox material, transparency, tri count, bar length.
- `upload-model.ps1` (one .fbx -> Open Cloud "Model" asset, polls the operation),
  `upload-all.ps1` (all 12 files -> `asset-ids.json`, resumable), `install_benches.lua` +
  `make-install.ps1` (fills the ids + manifest into `install_benches.generated.lua`, which is run
  through the Studio MCP in edit mode: LoadAsset each id, fix scale via the Anchor / bar length,
  align on the Anchor (bench) and the Bar (barbell), rename `<Tier>_<Part>` -> `<Part>`, apply the
  manifest looks, build `ReplicatedStorage.Assets.BenchTiers.<Theme>` (attrs Tier, Theme,
  SeatCFrame) with `Visual` (anchored frame parts at the platform) + `Barbell` (PrimaryPart Bar at
  the rack), then swap the workspace bench's stand-in parts for the Starter tier, keeping LieSeat;
  the old parts go to `ServerStorage.__BenchStandInBackup`).

**Upload status: blocked on the Open Cloud key.** The key pasted earlier still answers
`403 PERMISSION_DENIED "User not authenticated"` on asset creation (reads work) = the key has no
Assets API *Write* permission. Also re-tested and unavailable from the MCP plugin context:
`AssetImportService` (nil) and `AssetService:CreateAssetAsync` ("not available yet"). To finish:
create/edit the key at create.roblox.com -> Open Cloud -> API Keys with "Assets API" Read+Write
for user 140977250 (and an IP rule that allows this PC), then
`$env:ROBLOX_OPEN_CLOUD_API_KEY="..."; .\upload-all.ps1; .\make-install.ps1` and run the generated
Lua in Studio (edit mode). Never commit a key.

In-game tier display (installed and playtested with temporary block stand-ins for the tier models):
- `GymService`: `BenchTier(data)` = clamp(Better benchpress level, 1, 6), pushed as the player
  attribute `BenchTier` with the other effects. `MAX_BENCH_TIER = 6`.
- `BenchTierClient.client.lua` (StarterPlayerScripts): every 0.5 s checks the local tier and the
  server bench (`workspace.Map.Lobby.Props.BenchPress`, found by path so streaming is fine). For
  tier > 1 it hides the server bench's parts locally (LocalTransparencyModifier, LieSeat excluded),
  clones the tier's `Visual` (moved by the live LieSeat vs the stored SeatCFrame, so a moved bench
  still lines up) and clones the tier's barbell parts as massless, non-colliding parts welded to
  the server `Bar`, which BarbellClient already moves, so every tier's barbell follows the hands.
  Tier 1 shows the server bench itself. If a tier model is missing it falls back to the server
  bench. Verified: 22 server parts hidden, local copies at the tier positions, during a lift of
  1.32 studs the welded bar/plates stayed at 0.000 studs from the server bar, and resetting the
  tier removed everything and unhid the server parts.

### Bench tiers in the game without uploads: runtime meshes (2026-09-06, later)

Because the Open Cloud key still has no Assets Write permission, the six Blender benches ship
INSIDE the place as geometry data and are built into MeshParts on each client:
- `assets/benches/<Theme>.lua` (from `benchlib.export_luau`) -> `ReplicatedStorage.Assets.BenchMeshData.<Theme>`
  ModuleScripts (10-32 KB each): `Theme, Tier, BarLength, Parts[<Part>] = {Group = Bench|Barbell,
  Color, Material, Transparency, Size, Offset, V, T}`. Bench parts are offset from the bench origin
  (floor under the pivot), barbell parts from the bar centre with the bar along local X. Pulled into
  Studio with the loopback file server trick (`pets-remake/serve.ps1 -Root assets/benches`, plugin
  context `HttpService:GetAsync`).
- `BenchRuntimeMesh.lua` (`ReplicatedStorage.Modules.BenchRuntimeMesh`): probes the EditableMesh
  API once, builds each part once (EditableMesh, flat face normals, dummy UV ->
  `AssetService:CreateMeshPartAsync`), and `BuildTier(theme, benchCF, rackCF)` returns a
  `<Theme>{Visual, Barbell(PrimaryPart Bar)}` model in world space (clones keep the mesh).
- `BenchTierClient.client.lua` now handles every tier (1..6) through the local-visual path: it
  prefers a real asset model (`Assets.BenchTiers.<Theme>` with attribute `FromAssets=true`, made by
  `install_benches.lua`), else a runtime-built model (cached per tier), else it leaves the server
  bench visible. The bench origin comes from the Barbell's `RackCFrame` attribute:
  `benchCF = rackCF * Angles(0,-90deg,0) * CFrame.new(-1.5,-3.5,0)`. Local frame copies never collide
  (physics stays on the hidden server parts).
- The workspace bench (`Map.Lobby.Props.BenchPress`) stays the part-built stand-in on purpose: it
  is the universal fallback and the physics/seat/barbell root for everyone.
- Verified in edit mode (plugin context, exempt from the gate): all six tiers build in
  0.0-0.18 s, the Starter pad top and bar land exactly on the stand-in's (-227.00 / rack), and the
  screenshots show the intended looks (wood + stone, steel + blue, gold + gems, ice crystals with
  neon tips, basalt + neon lava seams + fire bowls, navy/gold + orbs with neon rings).

**GATE:** runtime EditableMesh in play needs Game Settings > Security > "Allow Mesh & Image APIs"
(cannot be toggled from Luau/MCP). See the playtest note below for whether it was on.
- Playtest 2026-09-06: the gate was OFF in this place (client probe: "EditableMesh is not
  accessible. Go to the Security Tab in Experience Settings to enable this API"), so the client
  logged the single BenchRuntimeMesh warning and left the 22 stand-in parts visible (fallback
  confirmed, no errors). Once the user enables Game Settings > Security > Allow Mesh & Image APIs
  nothing else changes: the next playtest builds the tiers on the client. Note: the test account's
  saved data now reads Coins 170399, Strength 199093, Better benchpress Lv. 14, Faster reps Lv. 15,
  all quests claimed (not set by this session), so it currently shows the Cosmic tier (6).

### Bench tiers visible without the gate: part-built fallbacks (2026-09-06, later still)

The user still saw only the stand-in (the Mesh & Image API setting was not enabled), so every
tier now also exists as plain Parts, which need no upload and no setting and persist in the place:
- `assets/benches/build_part_tiers.lua` (run through execute_luau in edit mode, re-runnable):
  same layout numbers as `build_benches.py` (Box helper takes Blender-space corners, Roblox local
  = (x, z, -y), world = benchCF * local), Cylinder parts for bars/plates/collars/rings, Ball for the
  Cosmic orbs, cubes standing on a corner (CFrame.Angles(35.264deg, 0, 45deg)) for gems / crystal
  tips / flames / spikes, 45-degree-turned prisms for ice crystals. Tiers 2-6 go to
  `ReplicatedStorage.Assets.BenchTiers.<Theme>` with attribute `Fallback=true` (Visual + Barbell,
  PrimaryPart Bar). Frame parts collide except decor (Gems, Crystals, Glow, Lava, Flames, Runes,
  Trim); barbell parts never collide.
- Tier 1 = the workspace bench itself: the stand-in was restyled as the Starter (WoodPlanks frame,
  dark pad, Slate stone plates, Wood collars, two wooden braces added), so it doubles as the
  always-visible fallback and the physics/seat/barbell root.
- `BenchTierClient` priority per tier: asset model (`FromAssets`) > Blender runtime mesh (gate on)
  > part fallback (`Fallback`) > server bench. `build_part_tiers.lua` keeps any `FromAssets` model.
- `GymService`: Better benchpress `Max = 6` = the number of bench tiers, so the last upgrade is the
  Cosmic bench (was Max 20).
- Test profile `Player_140977250` reset to the template (everything 0, both upgrades Lv. 1, quests
  cleared) via DataStore UpdateAsync while no session was active; the saved data also carried a
  `PlotLevel` key from the other session's plot-upgrade system, which the reset dropped (its
  Reconcile restores the default).
- Verified in a playtest (gate still off): tier 1 shows the wood/stone server bench; forcing the
  local tier to 2..6 showed 20/25/36/38/33 frame parts + 9/15/9/27/9 barbell parts with the right
  pad colours at pad top -227.00 (same as the bench), 24 server parts hidden each time; back to 1
  restores the server bench. Edit-mode screenshot of the side-by-side row matched the Blender looks.

### Studded texture on every bench (2026-09-06)

The map's studs are `Texture rbxassetid://6372755229`, tinted black at Transparency 0.8, tiled at
4 or 8 studs on walls/floors (732 instances). The benches reuse it at 2 studs per tile so the studs
stay readable on bench-sized parts:
- Parts (workspace Starter bench, fallback tiers 2-6): six `Texture` faces named `Studs` per part
  (`ApplyStuds` in `build_part_tiers.lua`, also run once over the existing models: 23 + 203 parts;
  skipped balls, thin rods such as the bar, invisible parts).
- Runtime Blender meshes (`BenchRuntimeMesh`): each face gets box-projected UVs (dominant normal
  axis, one tile per `STUDS_TILE` = 2 studs) and the source MeshPart gets a `Decal` named `Studs`
  (MeshParts map Decals through the mesh UVs). Clones keep it.
- FBX / asset path: `benchlib.box_project_uvs` writes the same UVs into the exported meshes and
  `install_benches.lua` adds the same Decal.
Note for edit-mode checks: the execute_luau VM caches required modules, so after patching a
ModuleScript require a `:Clone()` of it to test the new code.

### Bigger benches, more plates (2026-09-06)

- Every tier is built at design size and scaled x1.12 about its floor origin (`SCALE` in
  `build_benches.py` and `build_part_tiers.lua`; `manifest.json` / the data modules carry `scale`
  and `rack_offset` = (1.68, 3.92), which `BenchRuntimeMesh.BenchCFrame` and `install_benches.lua`
  use instead of the old (1.5, 3.5)). The workspace bench was scaled once the same way by
  `scale_workspace_bench.lua` (25 parts incl. the LieSeat position; bench attribute `Scale = 1.12`,
  refuses to run twice). Because the seat moves with the bench, the hands end up
  (3.0, 1.6) x 0.12 = (0.36, 0.19) studs short of the rack, inside the grab tolerances; the bar
  follows the hands once held. Playtest: grab after 0.6 s, every rep counted.
- Plates per side: Starter 2, Iron 3, Gold 4, Frost 5, Inferno 6 (each a two-half lava plate),
  Cosmic 3 galaxy plates with neon rings + the orb on the end. Bar lengths (scaled): 5.62 / 6.25 /
  6.92 / 7.75 / 8.71 / 10.71 studs. Triangles: 460 / 664 / 1208 / 884 / 1872 / 1532.
- Verified: fallback tiers and the runtime meshes put the pad top at -226.84 like the scaled bench,
  the bar at the rack; tiers 2-6 swap in with 6 / 8 / 10 / 24 / 8 plate parts.
- Edit-mode testing gotcha: the execute_luau VM caches every `require`d ModuleScript (data modules
  too); to test fresh code/data, require a clone of the module and temporarily swap a cloned
  `BenchMeshData` folder in under the real name.

## Quest system removed (2026-09-06)

The QUESTS board and everything behind it are gone from the place:
- `Map.Lobby.Props.GymPlatform.QuestsBoard` destroyed (backup:
  `backups/NewMap_2026-09-05/QuestsBoard_removed_2026-09-06.rbxm`).
- `GymService`: no QUESTS config, no `Claim` action / remote kind, no quest counters in `AwardRep`,
  no `BAR_KG`; the board state no longer carries `Quests`. The module was re-based on the live
  version, which another session had rewritten meanwhile (single "Bench press" upgrade = strength
  x2 and speed x2 per level, Robux developer-product path, `GymDev` Studio hook, the separate
  `BenchUpgradeBoard`); that rewrite had dropped the `BenchTier` attribute, so it is back
  (`MAX_BENCH_TIER = 6`, `BenchTier(data)`, set in `ApplyEffects`) and the upgrade's `Max` is 6
  again = the last bench tier (the rewrite had 20).
- `GymBoardsClient`: Upgrades rows only (no CLAIM / DONE); it only matters for boards tagged
  `GymBoard` with `Board = "Upgrades"` (none at the moment, the bench upgrade lives on the
  BenchUpgrade board owned by the other session).
- `DataService` template: `Quests` key removed (old profiles keep a stale `Quests` table, ignored).
- Repo copies of GymService.lua / GymBoardsClient.lua / DataService.lua updated to match.

## Plot owner badges (2026-09-06)

`PlotBadges.server.lua` (ServerScriptService.PlotBadges): a BillboardGui above every claimed plot
showing the owner's circular headshot and display name, styled after the user's reference
screenshot (white outer ring 4 px, dark navy inner ring 3 px, light grey disc behind the
`rbxthumb://type=AvatarHeadShot` image, name in GothamBlack 18 px white with a dark 2.5 px stroke).
- Reads only the plot attributes PlotService sets (`Owner` UserId, `OwnerName`); nothing in
  PlotService changed. Badge appears on assignment, disappears on release.
- Anchor: invisible part `plot.PlotBadge` above the CENTRE of the plot, 27 studs over the plot
  surface (first version sat on the front edge at 15 studs, then centred at 20; raised again on request);
  it follows the plot's Size / CFrame because PlotUpgradeService grows plots at runtime.
- Sized in studs (BillboardGui Size = scale 14.06 x 10.31 = the 9 x 6.6 first cut enlarged 25% twice, avatar circle ~6.4 studs, TextScaled name,
  proportional rings via nested circles + UIAspectRatioConstraint) so it shrinks with distance like
  the reference; the first version used a fixed pixel size, which looked huge from far away.
  AlwaysOnTop, MaxDistance 600.
- Studio screenshots were unavailable (window occluded); verified numerically in a playtest.
## Plot cucumber cards + leaderstats (2026-09-06)

- `NumberAbbrev.lua` (`ReplicatedStorage.Modules.NumberAbbrev`): `Abbrev(n)` -> "1.2M"-style strings, up to 3
  significant digits (1.23K / 12.3K / 123K), below 1000 the number itself (max 2 decimals), one suffix per
  power of 1000 up to centillion: K M B T Qa Qi Sx Sp Oc No Dc UDc ... Vg (10^63) ... Tg Qd Qq Sg St Og Ng Ce
  (10^303). Verified: 999999 -> 1M, 1200000 -> 1.2M, 5.4e12 -> 5.4T, 1e63 -> 1Vg, 1e303 -> 1Ce.
- `CucumberValues.lua` (`ReplicatedStorage.Modules.CucumberValues`): the Zombie vault economy, ported:
  coins/s = max(0.01, Reward x 8^(biome tier - 1) [x12 Golden] / 220) (+0.5 flat in Spawn). Reward tables per
  biome = the Zombie BreakablesService pools (same names as CucumberSpawner's RAW); Toyland / Neon price
  through the generic pool (Cucumber 8, Giant 45, Sliced 3, Tree 140). ZONE_COLORS = the Zombie Shards zone
  colours (Toyland pink, Neon cyan) for the card's biome line. Samples: Spawn Cucumber 0.54/s, Desert
  Prickly 0.29/s, golden Narmek Galaxy Tree 41.2M/s, golden Neon Cucumber Tree 1.02B/s.
- `LeaderstatsService.server.lua` (`ServerScriptService.LeaderstatsService`): `player.leaderstats` =
  StringValues `Strength`, `Coins/s` (abbreviated mirrors; the core playerlist's own formatting stops at B).
  Raw numbers stay in `player.Data` (`Strength`, plus derived `CoinsPerSec`, never saved). Stamps a replicated
  `Rate` attribute on every `PlacedCucumber`; Coins/s = sum of Rate over the player's placed cucumbers
  (Owner = UserId), refreshed on profile load, tag add / remove, plot Owner changes. DISPLAY ONLY: nothing
  pays the Coins/s into Coins yet.
- `PlacedCucumberCardClient.client.lua` (`StarterPlayerScripts.PlacedCucumberCardClient`): BillboardGui
  `CucumberCard` (6 x 2.64 STUDS: scale-sized like PlotBadges' owner badge so it shrinks with distance, user
  2026-09-06; MaxDistance 60, no AlwaysOnTop) adorned to each placed cucumber's PlotHitbox, bottom edge
  0.8 studs above the model top: biome line (biome colour) / name (white, "Golden" gold via RichText) /
  coin icon `rbxassetid://15402839520` + gold "0.54/s" -- the Zombie EarnBillboard recipe (FredokaOne,
  TextScaled, UIStroke 2.4 px). Scale-only layout: line heights are fractions of the card, the coin icon is a
  square via UIAspectRatioConstraint (ScaleWithParentSize / Height), the rate label AutomaticSize X inside its
  scale-height row. Client-built, removed on tag removal / stream-out. Verified: 257 x 113 px at 10 studs,
  65 x 29 px at 40 studs (x4 shrink for x4 distance), icon and rate label scale with it.
- Verified in a playtest 2026-09-06: Strength 40936 -> "40.9K"; placed Spawn Cucumber -> Rate 0.536, card
  "Spawn / Cucumber / 0.54/s", Coins/s "0.54"; pick-up -> "0"; placed golden Narmek Galaxy Tree -> card
  "Narmek / Golden Galaxy Tree / 41.2M/s", Coins/s "41.2M", the previous card removed.

## Egg hatch timer label (2026-09-06)

Placed eggs show "Egg" (red) with a countdown underneath, like the user's reference screenshot.
- `EggPlacement.server.lua`: `HATCH_SECONDS = 300`; a placed egg gets attributes `PlacedAt` and
  `HatchAt` (workspace:GetServerTimeNow() based, so every client counts the same clock) next to the
  existing Owner / EggName and the `PlacedEgg` tag. Nothing happens at zero yet (per the user).
- `EggTimerClient.client.lua` (StarterPlayerScripts): for every `PlacedEgg` model, a BillboardGui
  on its Hitbox (offset slightly below the egg centre so the text sits over the lower half, like
  the reference): "Egg" in GothamBlack red (235,40,40) with a dark 3 px stroke, the time in white
  ("4m 47s", "47s", stops at "0s"), TextScaled. Sized in studs (scale 6 x 3.2) with a scale-only
  layout so it shrinks with distance like the plot badges; AlwaysOnTop, MaxDistance 250. Updated
  every 0.5 s from the attribute; removed with the egg.
- Verified in a playtest (tool created server-side, placement invoked from the client): "Egg /
  4m 59s", 4m 57s a second later, 125 px wide at 20 studs and 31 px at 80 studs.

## Bench: material variants, moving decor, walk-on seats, owner-only, +10% per level (2026-09-06)

Context: the other session's PlotUpgradeService now stands a COPY of `Map.Lobby.Props.BenchPress`
beside every plot at runtime (`Map.Lobby.PlotFixtures/<plot>/BenchPress`, tag `PlotBench`,
attribute `Plot`), moves the template to `ServerStorage.PlotFixtureTemplates`, and refreshes the
Barbell's `RackCFrame` after every move; GymService.SyncPlot keeps `BenchLevel` / `BenchTier` /
`BenchCost` on each plot, and BenchTierClient (rewritten by that session) shows every bench with
its OWNER's tier. Everything below builds on that.
- **Materials:** the "Studs" texture overlays are gone. Frame / pad / feet / trim / bowls use the
  MaterialService variant `Studs`, barbell parts (bar, collars, plates, rims) the variant `Weld`
  (both Plastic based, placed by the user; Neon parts keep their glow). Applied to the template
  bench, the part-built fallback tiers (`build_part_tiers.lua` -> `ApplyVariant`) and the runtime
  meshes (`BenchRuntimeMesh.VARIANTS`, mapped through the box-projected UVs).
- **Moving decor:** Cosmic's drifting crystals are separate parts named `Float` (fallback) /
  `Float1..6` (Blender export, `build_benches.py`); BenchTierClient bobs, circles (0.7 studs) and
  spins them every Heartbeat; Inferno's `Flames` flicker (size pulse + bob).
- **Walk-on seats, owner only:** BenchServer removes the ProximityPrompt and keeps the LieSeat
  untouchable (CanTouch false, so the engine never seats anyone by itself). An invisible
  `SeatTrigger` box (3.4 x 1.6 x 1.2 studs, bench space, 0.4 above the seat centre) sits over the
  pad; on Touched it calls `seat:Sit(humanoid)` -- only for the owner of the bench's plot (bench
  attribute `Plot` -> plot `Owner`), so nobody else is ever seated. A bench without a plot is open
  to everyone. Players get up by jumping; a 3 s per-player cooldown keeps the trigger from
  re-seating someone still standing in it. Engine notes learned the hard way: a player character is
  simulated by its client, so server-side `Humanoid.Jump` / `Humanoid.Sit = false` do not reliably
  un-seat it (Sit=false even leaves `SeatPart` stuck and the humanoid can never touch-sit there
  again), server `Humanoid:MoveTo` does nothing, but `seat:Sit()` and teleports do work, and the
  engine's own re-seat cooldown after getting up is ~3 s. The seat itself is untouched (an earlier
  attempt enlarged it; the lying position / hand-to-bar margins were measured identical either way).
- **+10% per level:** `ReplicatedStorage.Modules.BenchScale` (shared): factor 1.1^(level-1) applied
  to the footprint (x along the bench about the bar's x, z across) with heights untouched, so the
  bar height, the seat and the animation stay valid; barbell parts scale uniformly about the bar.
  BenchServer captures each copy's unscaled layout at hook time and re-applies on `BenchLevel`
  changes and after PlotUpgradeService moves (RackCFrame refresh); bench attribute `BenchScale`.
  BenchTierClient applies the same transform to the tier visuals (and places them bar-on-bar).
- Verified in playtests: variants on template / fallbacks / meshes, walk-on seating, grab + reps at
  level 6 (scale 1.61: pad 6.5 studs long), all 6 Cosmic crystals moving, template pad has grown to
  4.06 studs by someone else's edit (scaling multiplies whatever the template is).
## Upgrade board button colours (2026-09-06, user)

- Both plot-side boards (`PlotUpgradeClient.client.lua` = plot size, `BenchBoardClient.client.lua` = bench):
  coin button GREEN (58,196,72 / rim 22,104,34) when you can press it (your plot + enough Coins), RED
  (228,40,40 / rim 122,14,14) when you cannot (not enough Coins, or not your plot), GREY only at MAX. The
  bench board's Robux button is ALWAYS green (was purple / grey).
- A shared `Paint(button, rim, color, dark)` helper in each client colours the background, the Rim
  UIStroke, the Cost / Price label strokes and the plot board's arrow icon frames (Icon > Bar / Tip), so
  a green button never keeps red trim. The old constants PURPLE / PURPLE_DARK are gone.
- Verified in a playtest: own plot board green at $1K with 996K Coins, other plots' boards red, own bench
  board grey (MAXED), every Robux button green.
## "+N" strength popup sized in studs (2026-09-06, user)

- `StrengthPopupClient.client.lua`: the popup BillboardGui is 3.6 x 1.15 STUDS (scale units, was 150 x 48 px),
  scale-only layout like PlotBadges' owner badge: icon = 0.83 of the height kept square by a
  UIAspectRatioConstraint (ScaleWithParentSize / Height), "+N" label = 0.92 of the height with TextScaled +
  AutomaticSize X, list padding 4% of the width. Pop (UIScale), arc (StudsOffset), tilt and fade unchanged.
- Verified in a playtest (6 fake "+7" pops fired from the server): 196 x 63 px at 8 studs, 49 x 16 px at
  32 studs (x4 shrink for x4 distance), icon 52 -> 13 px, label 52 x 58 -> 13 x 15 px.
## Strength gate + collect animations (2026-09-06)

User: "when collecting a cucumber the player does a pick-up animation (bend over, reach for
the cucumber, pick it up); also a struggling animation; harder cucumbers require a certain
amount of Strength (made-up numbers, ignore the economy for now); with just about enough
strength you keep pulling for a couple of seconds depending on your strength. Build the
animations with the Blender MCP and publish them through Open Cloud."

### Pieces
- `ReplicatedStorage.Modules.CucumberStrength` (mirror `CucumberStrength.lua`): requirement
  rules, bands and the choreography timeline. Placeholder ladder `ZONE_BASE` Spawn 0 /
  Desert 10 / Samurai 30 / Farm 100 / Snow 300 / Underwater 1K / Volcano 3K / Narmek 10K /
  Toyland 30K / Neon 100K, times a per-type factor (0.6..1.5 by a name hash), slices x0.5,
  trees x3 (min 12), golden x2 (min 6), rounded to 2 significant digits. Bands: strength >=
  1.5x = easy, < 0.5x = too heavy, in between = struggle for 1..6 s (3 s at exactly the
  requirement, whole 1 s loops). Timeline: APPROACH 0.6 s + struggle + GRAB_T 1.0 s into the
  1.4 s pick-up clip.
- `CucumberCarry` (server, mirror `CucumberCarry.server.lua`): `AttachCollectPrompt` stamps
  `StrengthRequired` on every field cucumber. `Collect` now: hands-full / seated refusals, a
  `CollectingBy` attribute lock + the prompt disabled while somebody tugs, verdict from
  CucumberStrength; fail -> `Remotes.CollectAnim` {Kind="Tug"} then the "Too heavy! Needs N
  Strength (you have M). Hit the bench!" refusal; easy / struggle -> {Kind="Collect",
  Struggle=s, Required} to ALL clients, then the server waits APPROACH + struggle + GRAB_T and
  runs `Grab` (re-checks alive / reach / hands, BuildCarryModel + GiveCarry, destroys the
  field holder) or sends {Kind="Cancel"} and releases. Busy lasts until the lift finishes.
- `CucumberSpawner`: stamps `Tree` on holders (one line).
- `StarterPlayerScripts.CollectAnimClient` (new, mirror `CollectAnimClient.client.lua`): the
  choreography. Own character: walk up (a per-frame Humanoid:Move loop toward a stand point
  radius*0.55+1.3 studs out, decelerating over the last 3 studs -- MoveTo crawled on the
  physique-scaled avatars -- then face the cucumber), freeze input (PlayerModule controls when present --
  this place's PlayerScripts has NO PlayerModule, so WalkSpeed / jump are zeroed AFTER the
  walk-up), loop CucumberStruggle, play CucumberPickUp; a stud-sized "PULLING... N" bar
  over the cucumber. Every client: the cucumber tips toward the puller (8 deg + tremble, 0.15
  lift) each loop with a quiet "Dirt Dig", then rides the hands' midpoint from 0.7 s into the
  pick-up until GRAB_T ("Whoosh"); Cancel restores the pivot. Animation source =
  `ReplicatedStorage.Assets.Animations.<Name>` Animation instances; while an AnimationId is
  empty, Studio registers the KeyframeSequence stored next to it (`<Name>Sequence`) through
  KeyframeSequenceProvider:RegisterKeyframeSequence (Studio only).
- `CucumberPromptClient`: the ObjectText gets a RichText "(flex) N" (green easy / yellow
  struggle / red too heavy); ActionText "Too heavy!" / "Collect (tug)".

### Animations (Blender)
- `assets/CucumberAnims.blend`: the R15Rig armature appended from BenchPress.blend + clean
  block preview meshes. `assets/anims/r15animlib.py` = pose helpers: two-bone leg IK that
  keeps the ankles planted (hip drop / hips-back / root pitch), arm IK honouring the R15 rest
  geometry (the elbow hangs 0.5 studs OUTSIDE the shoulder attachment: upper arm
  (+-0.5, -0.774, 0), forearm (0, -0.807, 0); the elbow hinge is kept along t x forward so
  nothing twists), head look-at, keying, 15 fps sampling to JSON, FBX export, workbench
  preview renders. `build_cucumber_anims.py` authors both clips
  (`exec(open(path).read())` inside Blender).
- CucumberPickUp 1.4 s: idle -> bend (hip drop 0.22, root -22, waist -68, wrists on the
  cucumber at (+-0.55, -2.02, -1.72)) at 0.43 s -> grip closed 0.7 s -> lift (hands at the
  chest (+-0.38, -0.95, -1.3)) 1.0 s = GRAB_T -> upright with the left wrist at the shoulder
  (-1.05, 0.35, -0.72) at 1.4 s.
- CucumberStruggle 1.0 s loop: grip -> hips-back squat pull (hip drop 0.45, hip_back 0.38,
  root -14, waist -54: the R15 arms are so short the shoulders must stay low for the hands to
  stay on the cucumber) with tremble -> slip back -> grip.
- Exports in `assets/anims/`: `<Name>.json` (pose samples), `<Name>.fbx` (Animation Editor
  "Import from FBX Animation"), `<Name>.rbxm` (the KeyframeSequence, for Open Cloud),
  `preview_*.png`.
- Studio: `ReplicatedStorage.Assets.Animations` = CucumberPickUp / CucumberStruggle
  (Animation, AnimationId EMPTY until published) + CucumberPickUpSequence /
  CucumberStruggleSequence (KeyframeSequence, Priority Action, Struggle loops).

### Publishing
- **PUBLISHED 2026-09-06 (later) under Group Frenzy (groupId 14583228)** with a key the user pasted:
  CucumberPickUp = `rbxassetid://113720951097278`, CucumberStruggle = `rbxassetid://111914270576623`;
  both AnimationIds are set in `ReplicatedStorage.Assets.Animations`. **Caveat:** Studio reports the
  place as owned by the USER (game.CreatorType User, CreatorId 140977250). Roblox only plays
  animations owned by the experience creator, so on a live server these group-owned clips will
  not load until the experience belongs to Group Frenzy (or they are re-uploaded under the user
  with `upload-animations.ps1` without -GroupId). The Studio RegisterKeyframeSequence fallback
  only kicks in while an AnimationId is EMPTY.
- `upload-animations.ps1` takes `-GroupId <id>` to publish under a group (default: the user).
- `assets/anims/upload-animations.ps1` uploads both .rbxm files as Animation assets (needs
  `ROBLOX_OPEN_CLOUD_API_KEY` with Assets Read + Write for user 140977250) and prints the
  AnimationId one-liner for the Studio command bar.
- Or in Studio: right-click each `...Sequence` > Save to Roblox > Submit, then paste
  `rbxassetid://<id>` into the matching Animation's AnimationId.
- Until then the clips only play in Studio (RegisterKeyframeSequence fallback); on a live
  server the choreography still runs (walk-up, freeze, timing, cucumber rocking, bar) but
  the character itself does not animate.

### Verified (solo playtest, 2026-09-06)
- strength 6 vs Cucumber Tree (12): Struggle track 0.6-6.6 s, PickUp 6.6-8.0 s, cucumber
  tilt 9.5 deg / lift 0.15, carry attribute at 7.618 s (expected 7.6), bar shown then
  removed, WalkSpeed 0 -> restored.
- easy path (real strength 1.35e17, Cucumber, 6 studs away): walked 6.0 -> 3.6 studs before
  the clip, faced it (dot 0.9995), PickUp clip, carry attribute at 1.601 s (expected 1.6).
  Test-harness gotcha: teleporting the root only 3 studs above the cucumber buried the
  8-stud Champion physique's legs (HipHeight 4.17) and made every walk-up crawl 0.4 studs;
  keep the root at its standing height when teleporting.
- strength 2 vs 12: Tug 1 s, toast "Too heavy! Needs 12 Strength (you have 2). Hit the
  bench!", holder restored to a 0.000 offset, prompt re-enabled, CollectingBy cleared.
- Gotchas hit: the DayNightCycle Night (every 180 s, lasts 5 s) clears the fields and
  teleports players to the lobby -> a collect in progress cancels cleanly (Grab fails, Cancel
  sent). `CucumberSpawnerAPI.SpawnCarried` returns nil when the Spawn field is at its cap
  (Drop then refuses "field is full"). The test account's Strength is 1.35e17 (restored).
- Backups: `ServerStorage.__CollectAnimBackup_2026_09_06` (CucumberCarry / CucumberSpawner /
  CucumberPromptClient before the patch).

### 2026-09-06 (later): "I try collecting cucumbers and nothing is happening"
Root cause = the pre-existing morning-spawn crash: `CucumberSpawner`'s BeginDay asserted on any
slot it could not fill, the Desert pool lists "Desert Palm" whose template `Desert Desert Palm`
does not exist in BreakableModels, so about one day in ten the assert threw inside
`DayNightCycle`'s `beginDay:Invoke`, the cycle loop died, `CyclePhase` stayed "PreparingDay"
forever and `CucumberCarry.Collect` refused every press silently. Fixes:
- `CucumberSpawner`: at startup every RAW / TYPES entry is checked against BreakableModels; a
  type with no template is flagged `Missing`, warned ONCE ("... 'Desert Palm' will not spawn")
  and skipped by PickType / SlicedTypeFor / TreeTypeFor. BeginDay no longer asserts: a slot
  that fails just warns and the day goes on.
- `DayNightCycle`: `beginDay:Invoke(day)` is wrapped in pcall (warns "[DayNightCycle] BeginDay
  failed: ..." instead of dying). Backup in `ServerStorage.__CollectAnimBackup_2026_09_06`.
- `CucumberCarry.Collect`: a press outside the Day phase now toasts "The fields are closed
  until dawn!" instead of doing nothing.
Verified: Day 1 starts with the warning and 60 cucumbers; a collect forced during "Night"
shows the toast; a daytime collect still picks up (Sliced Cucumber on the shoulder in 3 s).

### 2026-09-06 (later): carry billboard in studs, no pickup toast
User: delete the "Collected a ____!" toast; the overhead carried-cucumber UI must not grow as
the camera moves away -- size it like the plot owner badge. `CarryClient`: the Pickup cue now
only plays the Collect sound (the toast line is gone; Replant / FlyHome / Placed / Refused
toasts stay); the CarryBillboard is `UDim2.fromScale(6, 2.4)` (studs, MaxDistance 120,
LightInfluence 0, scale-only children, TextScaled) instead of 250x100 px with the device-fit
resize, and its anchor sits half the height + 0.4 studs above the model top. Verified in a
playtest: 262 x 105 px at 10 studs, 131 x 52 at 20, 65 x 26 at 40 (exact inverse scaling),
no toast after a pickup. Backup: `ServerStorage.__CollectAnimBackup_2026_09_06.CarryClient`.

## Bench tiers 7 + 8 (2026-09-06, user): Celestial and Void Emperor after Cosmic

Reference: the user's mockup "7 - CELESTIAL" (white marble + gold, winged uprights, gold spires,
glowing white diamonds, white/gold plates) and "8 - VOID EMPEROR" (obsidian + gold, red glowing
slots and diamonds, crown spikes, floating dark-red crystals, red pad, black plates with red rings).

- **Build:** `assets/benches/build_benches.py` gained the two tiers (`TIERS += [...]`, decor
  functions `decor_celestial` / `decor_void`, plate styles `halo` / `void`) and a `size_tier` key:
  both new tiers are built with **Cosmic's footprint** (`size_tier=6`: post 0.58, pad 1.45 wide,
  same tail length / upright height, 3 plates, no orbs), so nothing grows after Cosmic. Tris:
  Celestial 1380 (bench 560 + barbell 820), Void Emperor 1308 (544 + 764) vs Cosmic 1440.
  `BenchTiers.blend` holds all eight; `<Theme>_preview.png` renders.
- **Upload (Open Cloud Assets API, Model from FBX):** `upload-all.ps1 -KeyFile <key> -GroupId 14583228
  -Tiers <Theme>` -> `asset-ids.json`. The user's key returns 403 "User not authenticated" for
  `creator.userId`, but works with `creator.groupId 14583228` (Group Frenzy), so the four Model
  assets are **group-owned**: Celestial bench 84161418385358 / barbell 128607903317104, VoidEmperor
  bench 139713291746130 / barbell 111718218271304. Meshes render anywhere (only animations/audio
  are creator-gated), and `InsertService:LoadAsset` accepts them in Studio edit mode.
- **Install:** `assets/benches/install_tiers_78.lua` (execute_luau, edit mode): LoadAsset both
  assets, undo the FBX import's 180-degree yaw about the Anchor part, place the frame in bench space
  (`BenchScale.BenchCFrame(rack)`) and the barbell bar-onto-bar at the template bench's rack, apply
  the colours + **MaterialService variants** (Plastic + `Studs` on frame/pad/trim/wings, Plastic +
  `Weld` on bar/collars/plates/rims, Neon on Glow / Float1..6) and store
  `ReplicatedStorage.Assets.BenchTiers.<Theme>` (attrs Tier 7/8, Theme, FromAssets=true, SeatCFrame,
  AssetIds). Installed extents match Cosmic within 0.06 studs (x -2.4..3.2, z +-3.1; only the
  spires/wings are taller).
- **Game wiring:** `GymService.MAX_BENCH_TIER = 8` (Better benchpress Max 8: level 7 costs 6,400,
  level 8 12,800 Coins with the existing 100*2^(L-1) ladder); `BenchRuntimeMesh.THEMES` lists
  Celestial + VoidEmperor (asset models only, no BenchMeshData / part fallback);
  `BenchScale.MAX_GROWTH_LEVEL = 6` caps the +10%/level footprint growth at the Cosmic size for both
  the server bench (BenchServer) and the tier visuals (BenchTierClient), so levels 7-8 keep the
  level-6 bench size. The `Float1..6` crystals of Void Emperor drift like Cosmic's.
- Gotchas: no system Python on this PC (run the build scripts inside Blender's Python; the
  blender-mcp context needs `bpy.context.temp_override(window/area/region/selected_objects)` for
  `export_scene.fbx`); `upload-all.ps1 -Tiers` takes one tier per call when invoked through
  `powershell -File` (an array flattens to the first element).

## Cucumber mutations + materials (2026-09-06, user: "taken from the zombie cucumber game")
- `ReplicatedStorage.Modules.CucumberMutations` (mirror `CucumberMutations.lua`): the zombie
  game's rarity mix as weights -- NEON x15 (100), SHADOW x15 (100), FROZEN x20 (40),
  RADIOACTIVE x25 (25), MOLTEN x25 (25), ROYAL x40 (15), VOID x150 (8), PRISMATIC x750 (0.5) --
  and two MATERIALS: Golden (4%, x12, Foil; = the old Golden flag) and Diamond (0.6%, x50,
  Glass). Every fresh spawn rolls a material (one at most, Diamond checked first) and 0-4
  distinct mutations (`COUNT_CHANCES` 92% / 5% / 2% / 0.8% / 0.2%); the combined multiplier
  is `TotalMult` = material x every mutation, capped at 5000. Names read
  "Golden NEON FROZEN Cucumber"; `ColorizeName` returns RichText with each word in its colour
  (dark SHADOW / VOID lifted for readability); `AnnouncementRichText` builds the chat line.
- Attributes on every field / carried / placed cucumber: `Material` ("Golden" | "Diamond" |
  nil), `Mutations` ("NEON,FROZEN" | ""), `Golden` kept as a bool.
- `CucumberSpawner`: `Register` stamps them; `SpawnBreakable` rolls on organic spawns and keeps
  what a `fixed` re-plant already had (`SpawnCarried(zone, typeName, golden, point, extra)`
  now takes `extra = {Material, Mutations}`); looks = Diamond recolour + Glass + sparkle +
  light, one colour-coded ParticleEmitter per mutation on the root, the first mutation tints a
  material-less body, PRISMATIC cycles the rainbow; `Remotes.MutationAnnounce` fires to every
  client for fresh mutated spawns (not re-plants). Studio hook:
  `workspace:SetAttribute("MutationDev", "Spawn:NEON,FROZEN:Golden")` spawns one 6 studs in
  front of the first player and announces it.
- `StarterPlayerScripts.MutationChatClient` (new): RBXGeneral `DisplaySystemMessage` with
  RichText: `[NEON + FROZEN] Golden Vined Cucumber spawned in Desert!` -- mutation words in
  their mutation colours, the material in its colour, the biome in CucumberValues' zone colour.
- `CucumberCarry`: Material / Mutations travel through Grab -> carry entry -> Drop
  (SpawnCarried extra) -> Place (attributes) -> PickUp; player attrs
  `CarryingCucumberMaterial` / `CarryingCucumberMutations`; the Collect prompt's ObjectText is
  now the full name.
- `CucumberValues`: `ValueOf / RateOf(zone, typeName, golden, material, mutations)` multiply by
  `CucumberMutations.TotalMult`; `RateOfInstance` reads the new attributes, so
  LeaderstatsService's Coins/s and the plot cards price mutations automatically.
- `CarryClient` / `CucumberPromptClient` / `PlacedCucumberCardClient` show the name through
  `ColorizeName` (RichText; the prompt truncates long names).
- Verified in a playtest: dawn rolled 4 mutated + 3 golden of 60; a forced
  "Golden NEON FROZEN Cucumber" had Mutation_NEON + Mutation_FROZEN emitters, a light, the
  coloured prompt text, 131.4 coins/s (0.036 x 12 x 15 x 20); it kept everything through
  collect and drop; the chat line arrived with the colour tags. Backups
  `*_preMutations` in `ServerStorage.__CollectAnimBackup_2026_09_06`.

## Bench grab for any avatar size (2026-09-06, user: "small avatars not able to grab barbell")

Cause: BenchServer only marked the barbell Held when the fingertips came within GRAB_VERTICAL
(0.35 studs) of the bar height and within 1.2 studs of it along the bench. The rack height was
tuned for the default R15 arm (reach 1.84: fingertips peak 0.34 under the bar, so even the default
was marginal); a 0.65-scale avatar's hands peak 0.88 under the bar and lie 1.3-1.8 studs tail-ward
of it, a 0.5-scale one 1.09 under, so the grab never fired and no reps were counted.

Fix (BenchServer + BarbellClient, mirrors updated):
- **Reach-aware grab:** the occupant's straight-arm reach is measured from the R15 rig attachments
  (shoulder -> elbow -> wrist -> hand centre + GRIP_OFFSET). The hands count as "up" when they are
  within 0.35 of the bar OR within GRAB_BELOW_PEAK (0.2) of the top of their own reach, predicted as
  shoulder height + REACH_TOP (0.9) x reach (measured 0.91 for 1.0 and 0.65 scale) and also as the
  highest point the hands have actually been seen at once they come back down. GRAB_FORWARD 1.2 -> 1.6.
- **Scoot:** 0.6 s after seating the shoulder midpoint's along-bench offset from the bar is averaged
  over 6 frames and the engine's SeatWeld C0 is shifted so it equals SHOULDER_FORWARD_REF (1.47, the
  default avatar's), clamped to +-1.5 studs (seat attribute Scoot). Short torsos move toward the
  rack (0.65 scale: +0.73, 0.5 scale: +1.02), big ones away (1.25 scale: -0.43), the default ~0.
- **Rep threshold:** REP_MIN_RANGE (0.5) scales with reach / 1.84 (min 0.2) so short arms' smaller
  travel still counts.
- **BarbellClient:** the bar blends from the rack to the hands over 0.2 s at the grab instead of
  snapping (short arms grab well below the rack).
Verified in a solo playtest (scale values set on the Humanoid, seat:Sit from the server): 1.0 held
0.45 s, 0.65 held 0.78 s, 0.5 held 0.73 s, 1.25 held 0.18 s, all counting reps; bar rides the small
avatar's hands. Server-side `Humanoid.Sit = false` did not unseat the test character; destroying
`LieSeat.SeatWeld` does. The test account gained ~5.8K Strength from the trials.

### 2026-09-06 (later): "the two new benchpresses don't show"
The Celestial / VoidEmperor models had vanished from `ReplicatedStorage.Assets.BenchTiers` (every script edit survived, so it was an undo or another session restoring that folder, not a reload). Re-installed with `install_tiers_78.lua` (idempotent) and verified in a playtest: the level-8 plot builds `LocalBenchVisual` from the VoidEmperor MeshParts, and rays through the hollow middle of the Wings / Trim mesh parts MISS (a mesh that failed to download would fall back to a box and hit), so the group-owned meshes do load in the user-owned place. `ContentProvider:PreloadAsync` is useless as a check from an MCP client eval: it reports Failure for every asset, the avatar's own Roblox body meshes included. BenchTierClient now warns once when a tier has no model. **The place must be SAVED (Ctrl+S) or the models and script edits are lost again.**

## Barbell with no physics (2026-09-06, user: "benchpress weights come off")
Screenshot from the live game: a tier-1 bench with its stone plates lying on the floor away from the
bar. BenchServer used to UN-anchor the plates/collars (Massless) and WeldConstraint them to the
anchored bar, so any moment without a valid weld (late hook after the DataStore-backed modules load,
an older published version, streaming, a broken weld) let physics drop them, and once BenchServer
captured the layout with fallen plates it kept them there. Not reproducible in Studio (welds held
through resizes, level changes and a far teleport), so the mechanism was removed instead:
- **BenchServer:** `AnchorBarbell` anchors every barbell part (CanCollide/CanQuery/CanTouch false,
  stale welds destroyed) and stamps each non-root part with a `BarOffset` attribute (its CFrame
  relative to the bar); `ApplyLevel` re-places the parts about the rack and re-stamps. The grab test
  now measures against RackCFrame (the server bar never moves).
- **BarbellClient:** one bar CFrame poses the whole set (`SetPose` = bar + BarOffset parts); Held ->
  hands (0.2 s blend from the rack), released -> 0.35 s quad-out ease back to RackCFrame; then the
  server's replicated rest pose stands. Models tagged `BarFollower` (ObjectValue `ServerBar` +
  parts with BarOffset) are posed in the same step.
- **BenchTierClient:** the themed barbell copies are anchored followers (tag BarFollower) instead of
  massless welded parts, so they can never fall or trail the bar by a frame.
Verified in a solo playtest: 42 barbell parts on 6 benches all anchored / offset-stamped / attached;
while pressing, plates follow the bar with 0.000 error and the tier copies ride it; a level change
mid-press re-stamps the offsets with 0.000 error; getting up returns everything to the rack. The
template bench in Studio already had anchored, non-colliding barbell parts. **Publish + save** the
place for the live game to get this.

## Hidden strength + heavy-carry stumble (2026-09-06)

User: "remove the strength thing beside each cucumber (the requirement stays, hidden); with
just enough strength you struggle, pick it up, carry it a little and keep falling; slow the
player down while holding it; with a bit of extra strength no slowdown and no fall; build the
falling animation with the Blender MCP and export it with the Open Cloud key."

### Rules (`ReplicatedStorage.Modules.CucumberStrength`)
- Bands: `FLOOR_RATIO` 1.0 -- below the requirement the cucumber will not budge (1 s tug, then
  "Too heavy! Hit the bench to get stronger." -- no numbers anywhere); struggle band 1.0..1.5x
  (tug `STRUGGLE_MAX` 5 s at exactly the requirement down to `STRUGGLE_MIN` 1 s just under
  1.5x, whole 1 s loops); `EASY_RATIO` 1.5x = clean lift, full speed, never stumbles.
- Heavy carry = any struggle-band pick-up: WalkSpeed x `HEAVY_SPEED_MULT` 0.6, and a stumble
  after `FallDelay(ratio, rng)` = `FALL_DELAY_MIN` 3 s (at the requirement) .. `FALL_DELAY_MAX`
  7 s (just under 1.5x) +-`FALL_JITTER` 25 %; `FALL_RETRY` 2 s when a stumble cannot happen
  right now (busy / seated / fields closed / field full).
- Timeline: `FALL_LENGTH` 2.4 (CucumberFall clip), `FALL_DROP_T` 0.467 (the load leaves the
  shoulder), `FALL_FLIGHT` 0.5 (tumble to the ground), `FALL_LAND_AHEAD` 3 studs.
- New: `Ratio(strength, required)`, `FallDelay(ratio, rng)`; `STRUGGLE_MID` is gone.

### Server (`CucumberCarry`)
- `Collect` hands `heavy = (verdict == "struggle")` and the ratio to `Grab`; `GiveCarry` keeps
  `Heavy` / `Ratio` on the carry entry, `SetCarryAttributes` stamps the player attribute
  `CarryingCucumberHeavy`, and a heavy grab calls `ScheduleStumble`.
- `Stumble(player, entry)`: refused while Busy / seated / outside Day (retried); landing =
  raycast under `root + look * FALL_LAND_AHEAD`; sets `entry.Falling` and Busy for
  FALL_LENGTH; `Remotes.CollectAnim {Kind = "Fall", Player, Landing}` to everyone; at
  FALL_DROP_T `SpawnCarried(zone, type, golden, landing, {Material, Mutations})` makes it a
  real field cucumber again right there (lobby included -- it counts toward its zone's cap),
  then `Take` + destroy the shoulder copy, `{Kind = "FallDrop", Holder, From}` to everyone and
  `CarryFX {Kind = "Stumble"}` to the owner. A nil spawn (field full / closed) keeps the load
  and retries later.
- `Drop` / `Place` refuse while `Falling`. The Tug / Collect payloads and the refusal toast no
  longer carry the number. Dev hook: `workspace:SetAttribute("CarryDev", "stumble:<Name>")`.

### Clients
- `CollectAnimClient`: a small speed controller -- frozen (choreography, fallback mode) -> 0,
  heavy -> base x 0.6, otherwise the server's value stands; base = the `StrengthWalkSpeed`
  attribute StrengthProgressionServer stamps (it also writes Humanoid.WalkSpeed itself, so a
  WalkSpeed change that is not ours becomes the new base and is re-scaled). `Fall` = freeze on
  the spot + the CucumberFall track (2.4 s) + "Big Thud" for everyone at 0.733 s; `FallDrop` =
  the freshly spawned holder tumbles from the shoulder (`From`) to its own pivot in a low arc
  with a spin over FALL_FLIGHT, then "Dirt Dig". The struggle bar reads "PULLING..." only.
- `CucumberPromptClient`: the strength row, its colours and the "Too heavy!" / "(tug)"
  previews are gone -- name (material / mutation colours) + "Collect" only.
- `CarryClient`: hint "So heavy! Hurry, you can't hold it for long" (orange) while heavy;
  `Stumble` FX = toast "Oof! The <name> was too heavy to carry far. Pick it up again!" + dirt
  puff at the landing after FALL_FLIGHT.

### Animation (Blender MCP)
- `assets/anims/build_cucumber_fall.py` (r15animlib): **CucumberFall** 2.4 s one-shot -- carry
  pose 0.0, trip (right foot catches, right arm out) 0.233, pitched over with both arms flung
  0.467 (= FALL_DROP_T), face-plant prone with the legs straight back 0.733, settle 0.9, dazed
  head lift 1.0, all fours (thighs vertical, shins flat behind, straight arms) 1.267, right foot
  comes under 1.467, crouch 1.667, rising 2.0, idle 2.4. The left wrist follows the shoulder
  load through the UpperTorso frame (`carry_local`). Exports CucumberFall.json / .fbx and
  preview_CucumberFall_*.png (CukeStandIn hidden for the renders). Prone knees dip ~0.25 stud
  under the floor plane -- invisible on the real rig.
- `assets/anims/build_kfs.lua`: JSON -> `RS.Assets.Animations.CucumberFallSequence` (37
  keyframes at 15 fps, Linear poses, Action) fetched through `pets-remake/serve.ps1`; then
  `export_rbxm` -> CucumberFall.rbxm; `upload-animations.ps1 -Names CucumberFall -GroupId
  14583228` -> **`rbxassetid://104943185056357`** (Group Frenzy; the user's key still answers
  403 "User not authenticated" for `creator.userId`, so the same caveat as the other two
  clips applies: the place is user-owned, group-owned animations need a group-owned
  experience or a re-upload under the user). `RS.Assets.Animations.CucumberFall.AnimationId`
  is set; the KeyframeSequence stays next to it for the Studio fallback.
- `pets-remake/receive.ps1` (new): POST loopback (port 8766) that writes a script's Source to
  disk as `<Root>\<name>` (CRLF) -- exact mirrors without pasting sources through the chat.

### Verified (solo playtest 2026-09-06, awesomeotheraccount, Strength 134,772, StrengthRequired
overridden to strength / 1.2 on a Spawn "Sliced Cucumber", collected via the CarryDev hook)
- prompt "Sliced Cucumber / Collect" (no number), bar "PULLING...", struggle 3.0 s, heavy
  attribute at +4.65 s, WalkSpeed 43.8 -> 26.3 (x0.6) once the lift finished, hint swapped,
  CucumberFall at +5.26 s after the grab, drop 0.45 s into it, toast, holder re-spawned 3 studs
  ahead (4.62 from the root, standing on a 3.6 hip height), WalkSpeed back to 43.8 exactly
  2.4 s after the fall started; collecting the dropped one repeated the whole cycle. No script
  errors. Backups of the pre-change mirrors: `backups/*.before-hidden-heavy-2026-09-06`.
- Test gotchas: the workspace attribute `PhaseEndsAt` says how much Day is left (a run needs
  ~40 s); the client's WalkSpeed never replicates to the server, sample it with a client eval.

### Lobby = safe (2026-09-06, user: "after the user leaves the biomes and enters the lobby they walk at normal speed even with a heavy cucumber and don't fall anymore; screen bounce + sound on reaching the lobby with a cucumber")
- `CucumberCarry`: `ComputeLobbyBox()` reads the inner faces of the `Map.Borders."Lobby Border"`
  wall bands once LayoutReady is set (world half-extents -- the north / south bands are
  Size.X-thin parts rotated 90 deg, an axis-based test silently fell back to the plot box);
  fallback = plots row + 80 studs of walkway. Logged at start:
  `[CucumberCarry] lobby box X 1148.3..1301.8 Z -87.9..348.1`. A 0.1 s watch over every carry:
  inside the box -> `Heavy = false` for good (attribute cleared -> CollectAnimClient restores
  full speed; the pending stumble sees `Heavy == false` and does nothing) and, on an
  outside -> inside edge, `CarryFX {Kind = "LobbyReached", Name, WasHeavy}` to the owner.
  `entry.InLobby` starts as the pick-up position's state, so a cucumber picked up inside the
  lobby gives no cue. Walking back out with it stays settled (user: "don't fall anymore").
- `CarryClient`: `LobbyReached` = `cameraBounce()` (BindToRenderStep at Camera+1: damped
  0.65 s dip of 1.3 studs + 1.5 deg roll + FOV +7 punch; the previous frame's offset is removed
  first when nobody else rewrote the camera, so it never accumulates without a camera script)
  + billboard punch + "Big Thud" 0.4 + "Magic Shimmer" 0.55 + (heavy only) toast "Phew! You
  made it to the lobby with the X. It feels lighter already!".
- Verified (solo playtest): heavy Sliced Cucumber, teleported to x 1230 -> heavy attribute
  cleared 0.10 s later, WalkSpeed 15.2 -> 25.3, toast, FOV 70 -> 71.8 -> 70 over 0.6 s, still
  carrying 9 s later (no stumble), still settled after teleporting back to the Spawn field.
  A client-driven walk-in probe could not move the character at all (Studio unfocused =
  throttled client), so the entrance edge is covered by the box numbers + the teleport edge.
- Note: the test account's Strength read 13 in this run (134,772 an hour earlier) -- not
  touched by these tests (only holder StrengthRequired attributes were overridden).

## Collect prompt shows the whole cucumber name (2026-09-06, user)
`CucumberPromptClient` truncated long ObjectTexts ("Golden Sliced...") because the custom prompt's
BillboardGui is a fixed 230 x 60 px. Now `TextTruncate = None` and a `fitWidth()` hooked to both
labels' `TextBounds` widens the gui to badge + text + 12 px whenever the name (rich text with
mutation colours) or the action text is wider (short names keep 230). Verified on a play client with
a replica billboard: "Golden Sliced Diamond NEON FROZEN Sun-Baked Cucumber" = 463 px of text ->
gui 535 px, label fits; "Cucumber" -> 230 px. (Real prompts cannot be shown while Studio is
unfocused, so the script itself was compile-checked only.) Mirror updated (its file is CRLF, so
patch it line-wise).

## Flat slices + Cukes removed (2026-09-06, user)

### Slices lie flat
- The hand-modelled slice discs (Spawn / Desert / Samurai "Sliced Cucumber", Desert "Sun-Dried
  Slice", Narmek "Moon Slice" / "Planet Slice") are authored standing on their edge (thin along the
  model's Z, seed face toward +Z). `CucumberSpawner` now lays them flat: `LayFlatIfDisc(model,
  typeDef)` runs for every template whose type is Sliced or whose name contains "Slice", measures
  the extents without the Shadow part, and when Z < `DISC_THIN_RATIO` (0.45) x the face extents
  it pivots the model by `FLAT_ROTATION` (-90 deg about X: +Z -> +Y, seeds up) and returns the
  flat extents + `Lift` (pivot height over the lowest point + 0.02). Placement uses
  `point + Lift` and `yaw * FLAT_ROTATION`; `FlattenShadow` re-lays the template's Shadow
  cylinder flat under the disc (0.92 x the diameter, 0.04 above the ground point). Anything
  that is not a standing disc (Slice Stack, Frozen Slice cube, Snowball / Bubble / Shell,
  Molten Slice already flat, Cucumber Basket) takes the old path unchanged.
- Carry / plot placement need nothing: RestRotation / RestLift are read from the field pose.
- Verified (playtest census, day 525): every disc slice FLAT with Y extents 0.48-0.91 against
  3-5 stud faces, shadows horizontal (axis |Y| = 1.00) 0.02 above the spawn point, cubes / balls
  still standing, no script errors.

### Cukes removed
- `ServerStorage.DataService`: `Cukes` dropped from TEMPLATE and VALUE_ORDER (`player.Data`
  now holds Coins / Playtime / Strength); `REMOVED_KEYS = {"Cukes"}` is nil-ed out of every
  profile right after `Reconcile()`, so the DataStore forgets the key on the player's next
  save. No other script referenced Cukes.
- `workspace.Map.Biomes["02 Desert"].Decor["LeaderBoard Cukes"]` (an unwired 18-stud
  leaderboard prop, 3 SurfaceGuis) deleted; backup `backups/LeaderBoard_Cukes_removed_2026-09-06.rbxm`.
- The template mesh names `Cuke_Body*` / `CukeV_*` / `CukeT_*` etc. are just model part names
  and stay.
- **2026-09-07: "LeaderBoard Cukes" RESTORED** (user) from the backup rbxm, back in
  `Map.Biomes["02 Desert"].Decor` at its original spot (68 descendants, 18 x 18 x 20.8 at
  877.8, -220, 101). `import_rbxm` timed out on this 37 KB file every way (path, URL, simple
  parent) while a 2.5 KB probe imported fine; the working route is the one in the MCP notes:
  copy the file into the running Studio's `content\` folder and
  `game:GetObjects("rbxasset://<file>.rbxm")` from execute_luau, then parent. The Cukes
  data key stays removed.

## Water bottle click SFX (2026-09-07, user)
- `StarterPlayerScripts.BenchBonusClient` (the bench "Click me!" water bottle, offers owned by
  BenchServer through `Remotes.BenchBonusPopup`): a valid click now plays `SoundController.PlayFX
  ("Water Gulp", {Variants = {"Water Gulp", "Water Gulp 2"}, Volume 0.7, Pitch 0.05, Key
  "BottleGulp", MinInterval 0.15})` before firing the claim.
- New templates in `ReplicatedStorage.Assets.Sounds`: `Water Gulp` = rbxassetid://9114172114
  ("Drinking Cu Gulping 7"), `Water Gulp 2` = rbxassetid://9114171960 ("Drinking Cu Gulping 5"),
  both Pro Sound Effects (Roblox's free licensed library), Volume 0.6, AuthoredVolume attr.
- Verified in a playtest client: both gulps load and play (1.01 s / 0.92 s). The old UI click
  templates (`Click Sound` 421058925, `EggClick`, `Coin Tick`) never load in the Studio client
  (IsLoaded false, length 0) -- so no click layer; worth checking those ids in the live game.

## Egg stock, rolled eggs (kg / size / mutations) (2026-09-07, user)
User: "for each egg add a stock count + an overhead 'X left!' in the game's font, stock resets every
in-game day; when an egg is bought it mutates, gets a size and a kg value (more kg = bigger); the
held egg and the placed egg show that size / mutation (same mutations as cucumbers)".
- **Font:** FredokaOne (census: 55 GUI labels + 11 script uses, vs GothamSSm 48 on the user's stands).
- **EggShop (rewritten):** `DEFAULT_STOCK 5` per stand per in-game day (`MaxStock` attribute on the
  stand / egg model overrides); live attributes `Stock` / `StockMax` on the egg model, `Stock` on
  the prompt; a stud-sized BillboardGui `StockLabel` (7 x 1.8 studs, AlwaysOnTop, MaxDistance 90,
  FredokaOne TextScaled + dark UIStroke) on the egg's largest part reads "5 left!" (green, yellow at
  1) / "Sold out!" (red); the prompt is disabled + "Sold out" at 0; `workspace.DayNumber` changes
  (DayNightCycle.runDay) restock everything. Every purchase rolls `RollEgg`: kg = KG_BASE (2, or the
  stand's `Kg` attribute) x 2^N(0, 0.45) clamped x0.35..x3 (one decimal), scale = (kg/base)^(1/3)
  clamped 0.75..1.45, material = CucumberMutations.RollMaterial (4% Golden / 0.6% Diamond),
  mutations with MUTATION_CHANCE 0.35 then RollCountAtLeastOne (1..4). The tool is now built per
  purchase (no ServerStorage.EggTools templates any more): egg scaled to 2.2 x scale studs,
  `CucumberMutations.ApplyLook` (ParticleScale 0.6), name "<Golden> <NEON> <Egg> Egg (2.4 kg)",
  attributes EggName / DisplayName / Kg / Scale / Material ("" when none) / Mutations / Price.
  Studio hook: `workspace:SetAttribute("EggShopDev", "buy:<EggName>" | "reset")`.
- **CucumberMutations.ApplyLook(model, material, mutations, {ParticleScale})** (new, shared): the
  spawner's look verbatim (Golden = Foil, Diamond = Glass + DiamondSparkle + light, first mutation
  tints an unmaterialed body, one emitter per mutation, MutationLight, PRISMATIC rainbow loop);
  skips Shadow / Hitbox / Handle; idempotent (named emitters, PrismaticLoop attribute).
- **EggPlacement:** template looked up by the tool's `EggName` attribute (tool names now carry the
  roll), footprint / hitbox / model scaled by the tool's `Scale` (clamped 0.5..2), ApplyLook on the
  placed model, attributes Kg / Scale / Material / Mutations / DisplayName kept; BuildPlaceable
  strips BillboardGuis (the stock label) too.
- **PlacementClient:** same lookup, preview scaled + ApplyLook'd (lights + emitters disabled).
- Verified in a solo playtest (dev hook, test account): 8 stands "5 left!" FredokaOne; 5 Basic buys ->
  tools "MOLTEN Basic Egg (1.5 kg)" scale 0.91 / "SHADOW ... (2.7 kg)" 1.11 / plain 1.2 kg 0.84 ...,
  held egg heights 1.92..2.51 studs, tints ff5a1e / 2d2a42 / c4ff28 + emitter + light; stand ->
  "Sold out!" red, prompt disabled, 6th buy refused; DayNumber bump -> "5 left!". Placement results
  are in the summary below.
- Placement verified (client eval, requestPlacement): preview of "MOLTEN Desert Egg (2.5 kg)" = hitbox x1.077, MOLTEN tint + emitter + light at preview transparency; placed models keep hitbox/scale/kg/mutations/DisplayName and the look; a 1.4 kg Basic placed at x0.888; tools consumed. GOTCHA fixed on the way: EggNameOf() (both scripts) took the first non-"EGG" TextLabel under the stand, which became the new "5 left!" billboard, so every placeable model was named "5 left! Egg" -> the name is now stamped on the stand (attribute EggName) and BillboardGui labels are skipped.

### Per-biome daily stock, 2 kg .. 100,000 kg weights, Strength-gated rolls (2026-09-07, user)
- **Stock:** `STOCK_RANGE` by biome index (Spawn 6-11, Desert 5-10, Samurai 4-9, Farm 3-8, Snow 2-7,
  Underwater 2-6, Volcano 1-4, Narmek 0-2; Toyland 0-2 / Neon 0-1 if stands ever appear), overridable
  per stand / egg with `StockRangeMin` / `StockRangeMax` (NOT `StockMax`: that is the live attribute --
  the first version used the same name for both and yesterday's count clamped today's roll). Each
  stand's daily count = `Random.new(day * 1000003 + NameHash(eggName)):NextInteger(lo, hi)` with the
  SHARED day number (workspace `DayNumber` from DayNightCycle, or the same epoch / 180 s + 10 s formula
  before it is stamped), so every server rolls the same stock; a DayNumber change re-rolls.
- **Weight:** `KG_MIN 2 .. KG_MAX 100000`; reach = clamp(log10(1 + strength/100) /
  log10(1 + 1e7/100), 0.12, 1) (the walkspeed curve's shape; 10M Strength = the whole ladder);
  kg = 2 x 10^(4.7 x reach x u^2.2), u random -> weak players cap near 7 kg, 10M Strength gives a
  21 kg median, ~10K kg at the 90th percentile, ~79K at the 99th, 100K max. Names format as
  "574 kg" / "6.5K kg". Size = 0.8 + 0.7 per x10 kg (100K kg = 4.1x, capped 4.2); the HELD egg is
  capped at 3x (6.6 studs), the placed egg uses the full scale (placement clamps raised to 5).
- Verified in a playtest: three consecutive day numbers matched the offline formula for all 8 stands;
  Strength 0 -> five eggs of 2.0-3.0 kg; Strength 1e7 -> 12 eggs from 2.0 kg to a 25.2K kg Golden
  Desert Egg (hand 6.8 studs); a 788 kg Basic egg placed at 2.62x. Test account Strength restored
  to 605069 (it was 605069, not the 1.35e17 noted earlier).

- 2026-09-07 (user: "make mutated eggs rarer"): EggShop MUTATION_CHANCE 0.35 -> 0.08 (about 1 egg in 12 mutates; materials unchanged at 4% Golden / 0.6% Diamond).

### Egg billboards not AlwaysOnTop + hatch time per biome (2026-09-07, user)
- EggTimerClient and the EggShop `StockLabel` billboards are `AlwaysOnTop = false`. The timer label used to sit inside the egg (lower half) and only showed through the mesh because of AlwaysOnTop, so it now floats above the egg top (StudsOffset = half height + LABEL_GAP 0.2 + half the label). Countdown gained an hours format ("1h 6m").
- EggPlacement: `HATCH_BY_BIOME` by the egg stand biome index (Spawn 3 s, Desert 10, Samurai 30, Farm 90, Snow 240, Underwater 600, Volcano 1500, Narmek 3600; default 300) x (1 + 0.08 per x10 kg above 2 kg) x (1 + 0.08 per mutation) x (Golden +10% / Diamond +15%); placeable models carry `BiomeIndex`, placed eggs carry `HatchSeconds`. Verified: 3.7K kg SHADOW Basic egg -> 4 s, 44 kg Narmek egg -> 3986 s ("1h 6m").

- 2026-09-07 correction: only the PLACED egg timer is AlwaysOnTop=false; the shop "X left!" StockLabel is back to AlwaysOnTop=true.

### Rarer egg stock (2026-09-07, user: "more sold out, last egg super rare")
- EggShop `STOCK_TABLE` per biome index: {Chance, Min, Max} = the odds the stand has ANY stock on a given in-game day, then the count. Basic 100% 4-8, Desert 85% 3-6, Samurai 70% 2-5, Farm 50% 1-4, Frozen 35% 1-3, Ocean 20% 1-2, Lava 8% 1-2, Narmek 2% exactly 1 (about one in-game day in fifty; a day is 190 s, so roughly every 2.6 real hours). Overrides: attributes StockChance / StockRangeMin / StockRangeMax. Same seeded roll (day number + egg name) so every server agrees. 20,000-day simulation matched the table (Narmek in stock 1.9% of days).
- 2026-09-07 (user): reworked -- a bubbly **pop** when the bottle pops up (`PlayPopSfx` after the
  pop-in tween: "Bottle Pop" = rbxassetid://9112872235, "Bottle Pop 2" = 9112872239, "Small
  Bubbles Water Surface Float Up Pop 7 / 5", Volume 0.55) and a **splash** on a valid click
  (`PlayClickSfx`: "Water Splash" = 9117946641, "Water Splash 2" = 9117947324, "Puddle Stomps
  Small Water Splashes 3 / 12", Volume 0.6). All Pro Sound Effects. The gulp templates were
  removed. Verified in a playtest client: all four load (0.4-0.8 s; a cold load can take
  more than 0.5 s, so a "not loaded" reading right after the first play is not a dead id).
- 2026-09-07 (user: "I barely hear the sfx"): measured with `Sound.PlaybackLoudness` in a
  playtest client -- it reads the RAW clip (0-1000) before Volume, so heard loudness = peak x
  Volume. References: Collect 434 x 0.3 = 130, Whoosh 452 x 0.55 = 249, Big Thud 174 x 0.65 = 113,
  Success 93 x 0.5 = 47. The bubble pops peaked at 2 (x0.55 = 1, inaudible) and the first
  splashes at 18 / 5. Replaced: "Bottle Pop" = 9113263649, "Bottle Pop 2" = 9113263454 (Pro Sound
  Effects "Balloon Pop 3 / 1", Cartoon category, peak ~480-510, AuthoredVolume 0.5 -> ~240),
  "Water Splash" = 9117946863 @ 4.0 (peak 61 -> 244), "Water Splash 2" = 9117946857 @ 6.0 (peak
  39 -> 234). BenchBonusClient no longer passes Volume to PlayFX -- the templates' AuthoredVolume
  is the single knob. Loudness recipe: `assets/anims/../README` above; clone the template, Volume 0
  to warm it, then sample PlaybackLoudness per Heartbeat for its length.

## Pets + egg hatching (2026-09-07, user: "implement pets from zombie cucumber game, only the models; zombie hatch UI when the owner steps on a 0 s egg; hatched pets roam the base, no follow; no DataStore yet")

Only the pets that hatch from the zombie game's eight walk-up eggs came across (49 models:
6 per egg + the secret Gregory). Product, boss, reward and Food Cuke Egg pets were left behind.
Nothing about pets is saved yet (user) -- a rejoin starts with an empty base.

### Pieces
- `ReplicatedStorage.Assets.Pets/<name>` -- the 49 zombie models 1:1 (PrimaryPart `Root`, parts
  welded to it, CanCollide off). Transferred with `export_rbxm` -> Studio `content\` ->
  `game:GetObjects("rbxasset://zombie_pets_import.rbxm")` (`import_rbxm` still times out on big
  files). Copies: `backups/Pets_2026-09-07/zombie_pets_49_models.rbxm` + `zombie_hatchui.rbxm`.
- `StarterGui.EggRevealUI` -- the zombie's authored reveal layer (ClickCatcher full-screen button +
  FredokaOne "Click to open!" prompt, SingleLayer) with the zombie's `Single` card frame added as
  `SingleTemplate` (PetName / PetRarity gradients, PetChance "[1 in N]" tag, PetUnlocked hidden).
- `ReplicatedStorage.Modules.PetsCatalog` (`PetsCatalog.lua`) -- the zombie `Dictionaries.Eggs`
  pools + odds (40/30/15/9/5/1, Lava / Narmek 9.95 + 0.05 ultra-chase, Gregory 0.002% rank-less in
  the Basic Egg), rarity + display name per pet (`PetDisplayNames`: "Cat" shows as "Cucumber
  Deer"), the rarity gradients / glow colours (`RarityController`), `Roll` (float weighted roll,
  no pity -- pity needed saved data), `EggKey("Basic") -> "Basic Egg"`, `ChanceText`.
  Egg names line up exactly: the stands' EggName attribute (Basic / Desert / Samurai / Farm /
  Frozen / Ocean / Lava / Narmek) + " Egg" = the zombie pool key.
- `ServerScriptService.PetHatchService` (`PetHatchService.server.lua`):
  - trigger loop (0.15 s): every `PlacedEgg` whose `HatchAt` has passed hatches when its OWNER's
    root is inside the egg hitbox footprint + 1.25 studs, up to 7 studs above its base ("steps on
    it"); one hatch at a time per player.
  - rolls the pet, fires `Remotes.PetHatch` "Begin" {EggName, Scale, Material, Mutations, Pet,
    PetDisplayName, Rarity, Percent, Chance} to the owner, destroys the egg. The pet is spawned
    when the client answers "Opened" (end of the reveal) or after 80 s.
  - plot pets: clone shrunk to fit a 5-stud cube (zombie `petsize` cap), anchored, no collisions,
    into `plot.Pets`, tag `PlotPet`, attributes PetName / DisplayName / Rarity / Owner / Plot /
    PartCount. Roaming is PLANNED here as attributes only: `RoamFrom` / `RoamTo` (world points on
    the plot top, 8-26 stud legs at 5-8 studs/s, 2 studs in from the edge, never on a placed
    egg / cucumber), `RoamStart` / `RoamEnd` (server clock), `RoamIdleUntil` (1.5-4.5 s pauses),
    `RoamGroundY`, `RoamPhase`. Cleared with the plot (Owner -> nil). Player attribute
    `PetsHatched` counts the session.
  - dev hook `workspace:SetAttribute("PetHatchDev", ...)`: `ready` (all eggs -> 0 s),
    `hatch:<Egg>[:<Pet>]` (reveal without an egg), `spawn:<Pet>`, `clear`.
- `StarterPlayerScripts.EggHatchClient` (`EggHatchClient.client.lua`) -- the zombie
  `UiController.Single` interactive path: hides every other LayerCollector + the core GUI
  (remembering states), camera Scriptable, egg rebuilt from `ReplicatedStorage.PlaceableModels`
  with the placed size (display height capped 5.5 studs) + `CucumberMutations.ApplyLook`, pops in
  from 12 to 6 studs in front of the camera (Back, 0.3 s), 45 deg/s display spin; clicks 1-3 =
  the three escalating shake rounds ({12 deg, x1.15}, {14, x1.18}, {16, x1.22}, 0.75 s, sparkle
  burst, EggClick pitched +2 semitones per click, riser under round 3, a newer click aborts the
  running round); 4th click = collapse (0.08 s), EggOpen-style burst, "Pet Reward" + rarity
  stinger (Magic Shimmer / Drama Sting + Thunder) + screen glow, the pet (capped 3.4 studs)
  spinning where the egg was + the Single card; 2.5 s hold, card out at 2.25 s, pet shrinks,
  camera + UI restored, "Opened" sent. Idle players advance one stage per 15 s; a 95 s watchdog
  restores the screen. Studio hook: `PlayerGui.EggRevealUI:SetAttribute("DevClick", n)` = a click.
- `StarterPlayerScripts.PetRoamClient` (`PetRoamClient.client.lua`) -- replays the plan on every
  client from `GetServerTimeNow()` (identical for all players, smooth, zero per-frame network):
  zombie `Movement` feel -- artwork planted on the ground (`rootToVisibleBottom`), step bounce
  `|sin(t*9 + phase)| * 0.7` while walking, spring-like settle (10/s) toward the planned point,
  yaw eased (8/s) toward the direction of travel. Pets never follow the player.
- `EggTimerClient`: the countdown reads a green "Ready!" at zero.

### Verified (solo playtest 2026-09-07, awesomeotheraccount, Plot 5)
- dev hatch `hatch:Basic:Cat`: egg 6.0 studs in front of the camera, every other layer hidden,
  catcher up; 4 DevClicks: prompts Click to open! -> Click again! -> Keep clicking! -> One more
  click!, egg gone on the 4th; card CUCUMBER DEER / COMMON / [1 in 2.5]; HatchPet 3.4 tall at 6.5
  studs; camera Custom + layers back ~4.5 s after the crack (FreeGiftGui stayed off = its default);
  Cat spawned on the plot (fit 2.5 x 5.0 x 4.0), PetsHatched 1.
- real path: `EggShopDev buy:Basic` (551 kg, scale 2.51) -> `requestPlacement` at plot (12, 10)
  -> HatchSeconds 4 -> label "Ready!" while standing 8 studs away (egg stays) -> root moved onto
  it -> egg gone in 0.33 s, reveal up; second Cat spawned at the egg's spot (rel 12, 10).
- roam sample (12 s): 28 studs travelled, 0 samples outside the plot, root 2.50-3.18 studs over
  the plot top (rest = rootToBottom 2.50, +0.68 bounce mid-step).
- no script errors. Studio captures were unavailable (window minimized). Test account spent 100
  Coins on the test egg. NOT saved/published by me.

## Night less dark, day never dusky (2026-09-07, user: "game gets too dark at night, make night slightly brighter; night = 10 s")
- Night was already `NightDurationSeconds = 10` (attribute on `ServerScriptService.DayNightCycle`,
  code default 10). What read as a long dark night was the DAY: `dayClock` swept `ClockTime`
  8 -> 18 over the 180 s day, so the sun sank into a dusk for the last minute of every day.
- Day now sweeps `DayClockStart` -> `DayClockEnd` (script attributes, default 11 -> 16): the sun
  stays high, darkness is only the 10 s night.
- Night look (0.5 s tween, then restored at dawn): ClockTime 0, Brightness 1 (was 0.8), Ambient
  60,66,98 (was 35,40,65), OutdoorAmbient 78,85,122 (was 45,50,80) -- about 55% of the day's
  Ambient 110 / OutdoorAmbient 158 instead of ~35%. All four are script attributes
  (`NightClockTime` / `NightBrightness` / `NightAmbient` / `NightOutdoorAmbient`) so the look can
  be tuned in the Properties panel without code.
- Mirror `DayNightCycle.server.lua` refreshed from the live script (it had drifted).

## Weak lift + fling back (2026-09-07, user: "you can pick up any cucumber, but without the required strength you pretty much just fall right after pulling and picking it up; when falling fling the player a little back")

Before: below the requirement the cucumber would not budge (1 s tug + "Too heavy!"). Now every
cucumber can be lifted; too little strength means the same struggle -> lift -> stumble cycle as
the heavy band, only the stumble comes a few tenths of a second after standing up, every time.

### Rules (`ReplicatedStorage.Modules.CucumberStrength`)
- `Evaluate` returns a new verdict **"weak"** (ratio < `FLOOR_RATIO` 1.0) with `WEAK_STRUGGLE`
  5 s of tugging. `WEAK_CAN_LIFT = false` brings back the old "fail" tug + refusal.
- `WeakFallDelay(rng)` = the rest of the pick-up clip after the grab (`PICKUP_LENGTH - GRAB_T`
  0.4 s, the server is Busy until then) + `WEAK_HOLD_MIN..MAX` 0.3..0.7 s standing with it.
  `WEAK_RETRY` 0.5 s when the slip cannot happen right now (heavy carries keep `FALL_RETRY` 2 s).
- Fling: `FLING_BACK` 28 studs/s, `FLING_UP` 6, decaying to zero over `FLING_TIME` 0.25 s.

### Server (`CucumberCarry`)
- `Collect`: a weak verdict goes through the normal Collect choreography; `Grab(..., heavy =
  verdict ~= "easy", ratio, weak = verdict == "weak")`; the carry entry gets `Weak`, the player
  attribute `CarryingCucumberWeak` is stamped next to `CarryingCucumberHeavy` (weak carries are
  heavy too: slowed walk + stumble).
- `ScheduleStumble`: weak -> `WeakFallDelay`, else `FallDelay(ratio)`; retries use `RetryDelay`.
- `Stumble`'s `CarryFX {Kind = "Stumble"}` carries `Weak = true` for the toast.
- `Place` refuses a weak carry ("Too heavy! You can't hold it steady enough to set it down.").
- The lobby watch skips weak entries: the lobby never settles a cucumber you are too weak for
  (the heavy band still settles there as before).

### Clients
- `CollectAnimClient`: `fling(char, hum)` at the start of `runFall` -- a `LinearVelocity`
  (`Fling`, attachment `FlingAttachment` on the root, MaxForce inf, world vector) set to
  `back * FLING_BACK + up * FLING_UP` and scaled down per Heartbeat to zero over `FLING_TIME`,
  then destroyed. A plain `AssemblyLinearVelocity` write is cancelled by the Humanoid's ground
  controller within a frame (measured 0.38 studs back for 22/16; the Running state never even
  left the floor at 30/30), `ChangeState(Freefall)` + velocity gave 1.4 studs, the Jumping state
  a full 7-stud jump -- the fading constraint is the one that reads as a shove.
- `CarryClient`: hint "WAY too heavy! It's slipping..." (red) while `CarryingCucumberWeak`;
  Stumble toast with `Weak`: "Too heavy! The X slipped right off. Hit the bench to get stronger."

### Verified (solo playtest 2026-09-07, awesomeotheraccount, Strength 9, a Spawn "Cucumber" with
StrengthRequired overridden to 40 = ratio 0.225, collected via the CarryDev hook)
- Collect {Struggle = 5} -> grab 6.62 s later (Carrying + Heavy + Weak attributes at once) ->
  Fall 0.84-0.88 s after the grab -> FallDrop + Stumble {Weak = true} 0.48 s into the fall ->
  toast "Too heavy! The Cucumber slipped right off. Hit the bench to get stronger." -> attributes
  cleared, holder re-spawned ahead. Twice (first run without a working fling, second with it).
- Fling: root sampled per Heartbeat from the Fall event: 0.45 / 2.87 / 4.12 / 4.23 studs back at
  0.0 / 0.1 / 0.2 / 0.33 s, peak 0.91 studs up, back on the floor by 0.33 s, `Fling` +
  `FlingAttachment` gone by 0.26 s, WalkSpeed back to 25.2 afterwards. Humanoid state never
  left Running (no jump/fall animation flicker).
- No CucumberCarry warnings in the server log. Backups of the pre-change mirrors:
  `backups/*.before-weak-lift-2026-09-07`. NOT saved / published (another session was editing
  DayNightCycle in the same place at the time).

## Upgrade button pops (2026-09-07, user: "pop effects on the upgrade buttons when clicking them and when the plot / bench press upgrades")
- `ReplicatedStorage.Modules.ButtonFX` (`ButtonFX.lua`), used by PlotUpgradeClient + BenchBoardClient:
  - `Prepare(gui)` once per button / level label: re-anchors it on its centre (a UIScale scales
    about the AnchorPoint) and adds the `FXScale` UIScale; the base position is kept in the
    attribute `FXBasePosition`.
  - `Press` = squash-and-pop 1 -> 0.9 -> 1.07 -> 1 (0.25 s) + "Button Pop" (new
    `Assets.Sounds` template, Pro Sound Effects Balloon Pop 2 = 9113263444, Volume 0.3).
  - `Success` = pop to 1.18 + white flash sheet (keeps the UICorner) + "Cash Register" 1.5 /
    "Magic Shimmer" 1.2 (volumes from measured peaks 97 / 88 -> ~150 / ~105 heard).
  - `Fail` = 6-7 px side shake (0.35 s, decaying) + red flash + "Error" 1.2.
  - `Celebrate(board, levelLabel)` = the level label pops to 1.3, a gold FredokaOne "LEVEL UP!"
    floats 70 px up out of it and fades (0.9 s), and 45 gold/green sparkles burst off the board's
    Face part into the world (EmissionDirection = the SurfaceGui face).
  - Heartbeat-stepped animations (not TweenService) so they run in an unfocused Studio too; a
    newer pop cancels the running one (attribute tokens).
- Clients: every press -> `Press`; not your plot / server refusal -> `Fail`; server ok -> `Success`
  (a Robux press only pops: the purchase prompt decides). The celebration is driven by the plot
  attribute (`PlotLevel` / `BenchLevel`) going up by exactly 1 more than 3 s after the last Owner
  change, so EVERY client near the board sees it and the owner's saved level arriving at join does
  not trigger it.
- Verified (solo playtest): pops measured 0.900 / 1.086 / 1.000, success peak 1.198, shake 6 px and
  back to base, flash sheets destroyed; all four sounds load (peaks above); dev hooks
  `PlotUpgradeDev` "Plot 6:6" and `GymDev` "bench:8" each fired exactly one FXLevelUp + FXSparks on
  their board, the -1 restores fired none. NOT saved/published by me.

### Weak hold scales with strength / required (2026-09-07, user: "depending on how much strength the user has compared to how much is needed, let them walk a couple of steps before falling")
- `CucumberStrength.WeakHold(ratio)` = `WEAK_HOLD_MIN` 0.2 s + (`WEAK_HOLD_MAX` 2.0 s - 0.2) x
  ratio ^ `WEAK_HOLD_CURVE` 1.5: ratio 0.1 -> 0.26 s (slips as you stand up), 0.3 -> 0.5 s,
  0.5 -> 0.84 s, 0.7 -> 1.25 s, 0.9 -> 1.74 s, 0.99 -> 1.97 s; then the heavy band starts at
  3 s. `WeakFallDelay(ratio, rng)` = the 0.4 s left of the pick-up clip + WeakHold x
  (1 +-`FALL_JITTER` 25 %). `ScheduleStumble` passes `entry.Ratio`.
- The walk happens at heavy speed (`HEAVY_SPEED_MULT` 0.6): the input freeze ends when the
  pick-up clip does, so the whole hold is walkable.
- Verified (solo playtest, Strength 9): required 10 (ratio 0.9) -> WalkSpeed 15.1 restored
  0.45 s after the grab, fall 2.30 s after the grab = 1.85 s of walking; required 90 (ratio
  0.1) -> free at 0.43 s, fall at 0.63 s = 0.20 s. Both stumbles carried Weak = true.
- Test gotchas: the `CarryDev` hook is edge-triggered (set it to nil first when re-firing the
  same command); some Breakables are plain Parts (Toyland "Sliced Cucumber"), so nearest-holder
  scans must handle `IsA("BasePart")`; a `task.delay` inside a server eval that errors dies
  silently. Still NOT saved / published.
## Drop / slip on the spot in any biome + fling toward the previous biome (2026-09-07, user)

User: "slipped/dropped cucumbers drop on the spot you are on, regardless of what biome you are
in, but dropping it outside of the biomes (like the lobby) sends it back to the biome it was
from" and "fling the PLAYER: he cannot carry -> he gets flung a couple of studs, towards an
earlier biome (that direction, backwards) -> then the fall animation".

### Where the load goes
- `CucumberCarry.BuildBiomes()` reads one XZ box per `Map.Biomes."NN Name"` folder from its
  `Floor` parts (140 x 112 slabs in a row along X; Volcano is bigger), fallback = the SpawnArea
  field slab like `CucumberSpawner.SlabIndexAt`. `BiomeAt(position)` (the lobby wins at the
  seam via `InLobby`) drives both rules: `Drop` re-plants at your feet inside ANY biome and
  flies home outside them; `Stumble` keeps the load `FALL_LAND_AHEAD` 1.5 studs ahead of where
  you stood inside a biome and flies it home (Stumble cue `Home = true, Zone`: Slide Whistle +
  comet + "slipped off and flew back to X" toast, no FallDrop tumble) outside.
- **Spawner fix**: `GetZonePoint` clamped every preferred point into the zone's own field, so a
  drop in another biome silently landed on a fresh spot at home (the "lobby included" note from
  2026-09-06 was wrong: it returned a holder, just not there). New `extra.Anywhere = true` on
  `SpawnCarried` (-> `fixed.Anywhere` -> `GetZonePoint(..., anywhere)`): the exact XZ, rested on
  the ground under it, no bounds / spacing check. CucumberCarry passes it for on-the-spot drops
  and slips; an in-field point that is clear still goes through the old validation first.
- Cucumbers keep their home zone folder / population count wherever they lie; the night wipe
  clears them like any field cucumber. No client-side zone culling exists any more
  (CucumberStreamClient is gone), so a Spawn cucumber lying in Neon renders fine.

### The fling
- Order is now fling -> touchdown -> CucumberFall clip. `CucumberStrength.FLING_DISTANCE` 4.5
  studs over `FLING_TIME` 0.25 s; `FLING_BACK / FLING_UP` are gone. The server's
  `TowardPreviousBiome(position)` = flat unit vector to the previous biome's centre (the lobby
  box centre from the first biome; outside every biome the nearest one decides) goes out in the
  Fall cue as `FlingDir`; `CollectAnimClient.fling(char, dir, s)` drives a `LinearVelocity`
  along a real parabola (up speed g*T/2, along speed D/T, updated per Heartbeat), destroys it
  at T, zeroes the velocity, and only then plays the clip. Every clip time on the server
  (drop at FALL_DROP_T, Busy for FALL_LENGTH) and the thud (FALL_PLANT_T) are offset by
  FLING_TIME.

### Verified (solo playtest 2026-09-07, Strength 9, weak = StrengthRequired 90)
- Slip in the Spawn field facing away from the lobby: FlingDir (1.00, 0, 0.02) = toward the
  lobby, 5.2 studs of travel, 2.2 studs peak, constraint gone + clip started at 0.27 s, load
  re-spawned 1.5 studs ahead of the take-off spot 0.74 s after the cue, weak toast, no leftovers.
- Easy carry dropped at (937, 130) in the Desert: the Spawn "NEON Slice Stack" landed 2.1 studs
  from the root, still in `Breakables.Spawn`. Same cucumber dropped in the lobby: FlyHome cue,
  comet, "Sent ... back to Spawn!", back in the Spawn field.
- Slip in the Desert (a Spawn cucumber moved there): FlingDir (1.00, 0, 0.01) toward Spawn, load
  stayed at the slip spot in the Desert. Slip inside the lobby: `Home = true`, load back in the
  Spawn field, comet + "slipped off and flew back to Spawn" toast.
- Test tricks: the Spawn field is capped at 6, so `SpawnCarried` returns nil there -- relocate an
  existing holder instead (Model: PivotTo; Part holders: offset every BasePart, the shadow is a
  loose child). No CucumberCarry / CucumberSpawner warnings in the server log. Backups
  `backups/*.before-fling-v2-2026-09-07`, `backups/CucumberSpawner.server.lua.before-anywhere-2026-09-07`.
  NOT saved / published.

### Pull times halved + fling scales with the requirement (2026-09-07, user: "takes too long to pull cucumbers that are too strong, reduce by half; fling player 20+ studs depending on cucumber strength requirement")
- `STRUGGLE_MAX` 5 -> 2.5 s (at the requirement), `STRUGGLE_MIN` 1 -> 0.5 s (just under
  EASY_RATIO), `WEAK_STRUGGLE` 5 -> 2.5 s (below the requirement); struggle times now round to
  `STRUGGLE_STEP` 0.5 s (the 1 s clip loop, `STRUGGLE_LOOP`, is untouched -- the client's
  rocking visual keys off it). The whole ladder was halved, not just the weak band, so a
  cucumber you can barely lift never pulls longer than one you cannot.
- `CucumberStrength.FlingFor(ratio)` -> distance, flight time: `FLING_DISTANCE_MIN` 5 studs at
  the requirement (and every heavy-band stumble, ratio >= 1) up to `FLING_DISTANCE_MAX` 30 at
  ratio 0, `distance = MIN + (MAX - MIN) * (1 - ratio) ^ FLING_CURVE` (0.7: 90 % -> 10 studs,
  70 % -> 16, 50 % -> 20, 30 % -> 24.5, 10 % -> 28); flight time `FLING_TIME_MIN` 0.25 s ..
  `FLING_TIME_MAX` 0.6 s along the same fraction (peak height g*T^2/8: 1.5 .. 9 studs).
  `FLING_DISTANCE` / `FLING_TIME` are gone. The server puts `FlingDistance` / `FlingTime` in
  the Fall cue and offsets the drop / Busy / thud by that flight time; `CollectAnimClient.fling`
  takes them (constants as fallback) and now raycasts along the flight first: a wall within
  the distance shortens the flight (same speed, less time) instead of grinding the
  constraint into it.
- Verified (solo playtest, Strength 9, Spawn field): required 10 (ratio 0.9) -> pull 2.5 s,
  grab 4.13 s after the collect cue, fling 10.0 requested / 10.9 measured, 3.4 studs peak, clip
  on touchdown at 0.33 s, drop 0.82 s after the cue; required 90 (ratio 0.1) -> fling 28.2
  requested / 29.2 measured, 9.3 studs peak, 0.6 s flight, clip at 0.60 s, drop at 1.05 s. No
  leftovers, walk speed restored. Backups `backups/*.before-fling-scale-2026-09-07`. NOT
  saved / published.

### Fling removed: drop first, then fall (2026-09-07, user: "remove the fling, make player drop cucumber first then fall")
- The stumble is now: the load leaves the shoulder AT ONCE (server: `SpawnCarried` at the slip
  spot or home, `Take`, then the `Fall` cue + `FallDrop` tumble / `Stumble {Home}` cue in the
  same frame; a failed spawn returns false before any cue so the retry path is unchanged),
  and `FALL_AFTER_DROP` 0.4 s later the player trips: `CollectAnimClient.runFall` plays
  CucumberFall from `FALL_CLIP_START` 0.233 s (the carry-pose lead-in is skipped because the
  hands are empty by then) to the end, so the fall lasts `FALL_LENGTH - FALL_CLIP_START` =
  2.17 s; the server's Busy window and the thud use the same offsets. `FALL_DROP_T`, every
  `FLING_*` constant, `FlingFor`, `fling()` and `TowardPreviousBiome` are gone; `BiomeAt` stays
  for the drop / slip rule. The Fall cue no longer carries FlingDir / FlingDistance / FlingTime.
- Verified (solo playtest, Strength 9 vs required 90): carry attribute cleared, FallDrop and
  Stumble cue 0.00 s after the Fall cue, holder 1.5 studs ahead; clip started 0.43 s after the
  cue at TimePosition 0.233; control back 2.60 s after the cue; the character moved 0.00 studs
  (no constraint ever created). Backups `backups/*.before-no-fling-2026-09-07`. NOT saved /
  published.

## The strength ladder: four bands + lobby settles everything (2026-09-07, user)

User: "once the player is past the biomes and in the lobby don't let cucumbers slip and fall;
let players get some extra steps in before slipping, but for requirements too far from the
user's strength keep it as is; develop a nice algorithm with the ranges the user's strength
should be in for: pulling and carrying easily / a lot of steps but falling occasionally / some
steps but falling a lot / barely being able to walk without falling".

### The algorithm (`ReplicatedStorage.Modules.CucumberStrength`)
`ratio = strength / required`. `M.BANDS` is one table, top band first; a band runs from its
`MinRatio` up to the next band's, and every number inside a band interpolates linearly from
its bottom value to its top value (`BandFor(ratio)` -> band, t):

| band | ratio | pull (tug) | walk speed | stays up for (after standing up) |
|---|---|---|---|---|
| easy | >= 1.5 | none | x1.0 | forever |
| sturdy | 1.0 .. 1.5 | 2.5 s -> 0.5 s | x0.8 | 5 s -> 10 s |
| shaky | 0.5 .. 1.0 | 2.5 s | x0.6 | 1.5 s -> 4 s |
| hopeless | < 0.5 | 2.5 s | x0.5 | 0.2 s -> 0.8 s (unchanged: "too far, keep as is") |

Every hold gets +-`FALL_JITTER` 25 %. Pull times round to `STRUGGLE_STEP` 0.5 s. Helpers:
`Evaluate(strength, required)` -> band name (or "fail" with `WEAK_CAN_LIFT` off), pull
seconds, band table; `SpeedFor(ratio)`; `HoldFor(ratio, rng)`; `FallDelay(ratio, rng)` = the
0.4 s left of the pick-up clip + the hold (nil = never); `RetryFor(ratio)` (hopeless retries
every 0.5 s, the rest every `FALL_RETRY` 2 s). Gone: STRUGGLE_MIN/MAX, WEAK_STRUGGLE,
WEAK_HOLD_*, WeakHold, WeakFallDelay, HEAVY_SPEED_MULT, FALL_DELAY_MIN/MAX, WEAK_RETRY.
Tuning = edit the `M.BANDS` rows (add a band by inserting a row; the code never assumes four).

### Server (`CucumberCarry`)
- `Grab(..., band, ratio)`: entry / player attributes `Heavy` (any band below easy), `Weak`
  (hopeless only: the "slipped right off" toast + hint), `CarryingCucumberSpeed` (the band's
  multiplier, only while Heavy), `CarryingCucumberBand` (name, only while Heavy).
  `ScheduleStumble` uses `FallDelay(ratio)` for every band; `RetryDelay` = `RetryFor`.
- LOBBY = SAFE for EVERY band: the lobby watch no longer skips weak carries; on entry it clears
  Heavy / Weak / Speed, sets Band = "settled", and the LobbyReached cue fires as before. `Place`
  refuses only a carry that is both Heavy and below `FLOOR_RATIO`, so a settled carry can be
  placed.
### Clients
- `CollectAnimClient`: the speed controller reads `CarryingCucumberSpeed` (nil = the server's
  speed stands) instead of the Heavy flag x0.6.
- `CarryClient`: one hint per band -- sturdy "Heavy! You can carry it a good way, but watch
  your step" (amber), shaky "So heavy! Hurry, you can't hold it for long" (orange), hopeless
  "WAY too heavy! It's slipping..." (red); normal hint once the lobby settles it.

### Verified (solo playtest 2026-09-07, Strength 9)
- sturdy (required 7.5, ratio 1.2): pull 1.5 s, grab 3.12 s after the cue, WalkSpeed 20.2
  (x0.8), "watch your step" hint, slipped 7.18 s after the grab (0.4 + hold 6.78 in 5.25..8.75).
- shaky (required 12, ratio 0.75): pull 2.5 s, WalkSpeed 15.1 (x0.6), "hurry" hint, slipped
  3.17 s after the grab (hold 2.77 in 2.06..3.44).
- hopeless (required 90, ratio 0.1): pull 2.5 s, WalkSpeed 12.6 (x0.5), "slipping" hint,
  Weak = true, slipped 0.77 s after the grab (hold 0.37 in 0.24..0.40).
- lobby: a hopeless carry teleported into the lobby at the grab settled 0.04 s later (Heavy /
  Weak / Speed / Band cleared, LobbyReached wasHeavy = true, normal hint, WalkSpeed 25.2) and
  was still on the shoulder 4 s later -- no slip.
- Backups `backups/*.before-bands-2026-09-07`. NOT saved / published.

## One notification style for the whole game (2026-09-07, user: "look at the 'Not enough money' UI, for all game notifications use this type of text UI that pops up near the bottom of the screen")

The reference (a screenshot from another game) is big bold red text with a dark outline,
centred just above the hotbar, no panel. Nothing in this place drew it, so it is rebuilt from
the picture in ONE module and every notification now goes through it.

### `ReplicatedStorage.Modules.Notify` (mirror `Notify.lua`, client-only)
- `Notify.Show(text, color?, seconds?)`, plus `Error / Warn / Success / Info(text, seconds?)`
  with the palette `Notify.COLORS` (Error = the reference red 240/58/58, Warn orange, Success
  green, Info yellow). The outline is the text colour x `OUTLINE_DARKEN` 0.22. A new message
  replaces the one on screen (token + the running tweens are cancelled).
- One ScreenGui "GameNotify" (IgnoreGuiInset, DisplayOrder 2000) with a TextLabel centred at
  `POSITION` 50 % / 66 % of the screen, `WIDTH` 92 % x `HEIGHT` 15 % (room for two lines),
  TextScaled + TextWrapped with a UITextSizeConstraint cap = `TEXT_HEIGHT` 7.5 % of the screen
  height (max `MAX_TEXT_PX` 64), FredokaOne, UIStroke `STROKE_RATIO` 0.1 of the text height
  (2..6 px, LineJoinMode Round), UIScale pop `POP_FROM` 0.7 -> 1 over `POP_TIME` 0.16 s (Back
  easing), `HOLD` 2 s, `FADE` 0.35 s. `fit()` recomputes the cap and the outline whenever the
  ScreenGui resizes (label.TextSize is meaningless under TextScaled -- the first version read it
  and got a 2 px outline).
- Callers: EggShopClient ("Not enough Coins! ...", "Bought a ... !"), CarryClient (every
  CarryFX toast: refused / fly home / stumble / lobby), GymBoardsClient, PlotUpgradeClient,
  BenchBoardClient (board results, "This is not your plot"). Each keeps a two-line local
  `Toast(text, color)` that forwards to `Notify.Show`; their own ScreenGuis (EggShopNotify,
  CarryNotify, GymToast, PlotUpgradeToast, BenchBoardToast) and dark panels are gone, and the
  pale error / success colours were swapped for `Notify.COLORS.Error / Success / Warn`.

### Verified (solo playtest 2026-09-07, 1301 x 611 play window)
- "Not enough money": centre 50.0 % / 66.0 % of the screen, one line 352 x 46 px (7.5 % of the
  height), outline 4.58 px, FredokaOne, red 240/58/58 with the dark-red outline; pop scale
  0.70 -> 1.03 -> 1.00 in 0.15 s; visible 2.0 s, faded out by 2.4 s.
- A long message ("Phew! You made it to the lobby ...") wraps to two lines of the same 46 px
  (bounds 1189 x 90); green with the dark-green outline.
- The real path works: a server `CarryFX {Kind = "Refused", Reason = "Not enough money"}`
  showed the same label through CarryClient. PlayerGui holds only GameNotify for toasts now.
- Backups `backups/*.before-notify-2026-09-07`. NOT saved / published.

## Hotbar with egg pictures + hover card (2026-09-07, user: "eggs as images in the hotbar instead of text; hover shows kg, mutations and the egg's name")
- `StarterPlayerScripts.HotbarClient` (`HotbarClient.client.lua`) replaces the default backpack
  hotbar (`SetCoreGuiEnabled(Backpack, false)`, retried until CoreGui accepts it) with the same
  look: dark rounded slots (0,0,0 @ 0.5, UICorner 8, 44-64 px = 7.5% of the viewport height) along
  the bottom, number labels 1-9 / 0, number keys equip / unequip (`Humanoid:EquipTool` /
  `UnequipTools`), the equipped slot lit (white @ 0.25 + white stroke, dark text).
- Egg tools (tag `EggTool`) show a ViewportFrame of the tool's own `Egg` model (welds / particles
  stripped, centred on the origin, camera front-top-right at FOV 40 fitted to the bounding
  sphere), turning at 24 deg/s -- so the rolled size, Golden / Diamond material and mutation
  colours are all in the picture. Other tools: TextureId image, else the name (default look).
- Hover (MouseEnter on the slot's hit button; a tap on touch, for 2.5 s) opens one shared
  tooltip 8 px above the slot: the egg's display name with material / mutation words in their
  colours (`CucumberMutations.ColorizeName`), "Weight: 574 kg" (EggShop's FormatKg), "Mutations:
  NEON, FROZEN" coloured or "Mutations: none", and a "Material: Golden" line when there is one.
  Non-egg tools: name (+ ToolTip text when it differs).
- More than 10 tools: the first ten fill the hotbar, a "+N" chip appears and the backtick key /
  the chip toggle a grid (6 per row) with the rest. The bar hides when there are no tools.
- Tools are tracked from the Backpack AND the Character (equipping moves them); a tool that ends
  up in neither is dropped from the bar next frame; respawns rebind the new Backpack / character.
- Studio hooks on the Hotbar ScreenGui: `DevPress` = slot index (toggle equip), `DevHover` = slot
  index (show its card, 0 hides). Attribute-changed signals are deferred: write 0, wait a frame,
  then the index, or the handler runs twice with the final value (bit the first probe).
- EggHatchClient's hide / restore of the core GUI records the Backpack as off and restores off.
- Verified (solo playtest, 3 bought eggs + 9 dummy tools): CoreGui Backpack off, 10 bar slots +
  2 grid slots + "+2" chip, egg slots carry 2-part viewports, equipped highlight follows
  EquipTool / UnequipTools, tooltip bottom 8 px above the slot top and centred on it, texts
  "Basic Egg / Weight: 6.9 kg / Mutations: none", a Golden NEON FROZEN stamp renders the coloured
  RichText name + "Material: Golden". Test account bought three cheap eggs (300 Coins).

### "Too heavy" is the whole message (2026-09-07, user: "when you can't carry a cucumber just make it say 'Too heavy' instead of all the other stuff")
- `CarryClient`: the Stumble cue shows `TOO_HEAVY` = "Too heavy" (red) for every band and both
  landings (on the spot / flew home); the four long variants ("... slipped right off. Hit the
  bench ...", "Oof! ... too heavy to carry far ...", the two "flew back to X" lines) are gone.
  The dirt puff / comet + Slide Whistle FX stay.
- `CucumberCarry`: the two server refusals that meant "can't carry it" -- Place with a
  below-requirement carry, and the WEAK_CAN_LIFT = false tug -- now send Reason = "Too heavy".
- Unchanged on purpose: the lobby arrival ("Phew! ..."), a deliberate DROP ("Sent the X back
  to Y!"), "Your hands are full!", "Stand up first!", "The fields are closed until dawn!", and
  the billboard hints while carrying (watch your step / hurry / it's slipping).
- Pushed and hash-verified against the mirrors; text-only change, no playtest. Backups
  `backups/*.before-tooheavy-2026-09-07`. NOT saved / published.

## Headband strength boost + open shop (2026-09-09, user: "shop dialogue just says 'What do you wanna buy?'; show all headbands, lock none behind each other; each headband multiplies bench-press strength per rep, first 2x, second 3x ...; replace 'TIER X / Y' with 'Nx STRENGTH BOOST' and the bolt image rbxassetid://15403203770 on its left")

The live `HeadbandShopClient` is NOT the 1167-line self-built panel from the 2026-09-09 morning
session any more: a later session replaced it with a 271-line controller that drives an
AUTHORED `StarterGui.HeadbandShop` (copied from the Zombie place, cards + preview + `Stats` frame
all pre-built). The repo mirror `headband-shop/HeadbandShopClient.lua` now holds that live version.

- `ReplicatedStorage.Modules.HeadbandsCatalog`: every entry gained `StrengthMult = Tier + 1`
  (Sweatband 2x, Red Bandana 3x, Camo 4x, Cucumber 5x ... Champion 13x) and the helper
  `Catalog.StrengthMultOf(name)` -> that number, or 1 for `""` / an unknown name (never nil/0).
- `ServerStorage.GymService`: `StrengthPerRep(data)` = `2^(BenchPress level - 1)` x
  `GymService.HeadbandMultiplier(data)` (reads `data.Headbands.Equipped` through the catalog).
  The bonus click (`AwardRep(player, BONUS_MULTIPLIER)`) and the "+N" popup inherit it because
  both go through `StrengthPerRep`. New `GymService.Refresh(player)` = attributes + board push.
- `ServerScriptService.HeadbandService`: requires GymService; `Publish()` (every buy / equip /
  unequip / profile load) calls `GymService.Refresh` so the `StrengthPerRep` attribute and the
  gym board follow the worn band.
- `HeadbandShopClient`: `unlocked()` always returns true (the authored "Locked" card state is
  never shown; the function stays so a lock can come back); `Stats.Tier` shows
  `Catalog.StrengthMultOf(name) .. "x STRENGTH BOOST"`.
- Authored GUI (`StarterGui.HeadbandShop.Shop.Body.Preview.Stats`): new `BoostIcon` ImageLabel
  (`rbxassetid://15403203770`, the VectorIcons "Bolt" Image, 56x56 at (14, 6), ScaleType Fit,
  ZIndex 49); `Tier` moved to (74, 4) and narrowed to 304x61 so it sits to the icon's right.
  Both "2x ..." and "13x STRENGTH BOOST" report TextFits at that width.
- `ShopDialogClient`: `GREETING = "What do you wanna buy?"`; the three options are unchanged.
- Verified in edit mode only (the "previous test still in progress" playtest block is back):
  all five scripts loadstring-compile, the pushed sources round-trip and checksum-match the
  mirrors, and a DataService-stubbed copy of GymService gives L1 bare 1 / Sweatband 2 /
  RedBandana 3 / CucumberBand 5, L3 Camo 16, L8 Champion 1664, bogus name = bench only.
- Transfer: live sources dumped with `pets-remake/receive.ps1` (Studio `PostAsync` to
  127.0.0.1:8766) into `backups/*.before-boost-2026-09-09`, edited locally with a checked Perl
  patch, pushed back whole with `pets-remake/serve.ps1` + `HttpService:GetAsync`. NOT saved /
  published.

### Booth prompt opens the shop directly (2026-09-09, user: "get rid of the dialogue when hitting shop prompt, just make it instantly open the headbands shop")
- `HeadbandShopClient`: connects `Remotes.OpenShopDialog.OnClientEvent` (the booth prompt, fired
  per player by HeadbandService) straight to `open()`. The `OpenHeadbandShop` attribute path and
  the `HeadbandShopDev` hook still work.
- `ShopDialogClient`: **Disabled** (LocalScript property, kept in StarterPlayerScripts for
  reference with a DISABLED note in its header); the typed bubble, the three choice pills and the
  "Show me defenses" toast no longer exist in play.
- `HeadbandService`: the ProximityPrompt now reads ActionText "Open" / ObjectText "Headband Shop"
  (was "Talk" / "Shopkeeper") since there is nobody to talk to. Remote name unchanged.
- Edit-mode only (playtest still blocked): the three scripts loadstring-compile, and the mirrors
  checksum-match live. NOT saved / published.

### "Nx strength" fills the preview row (2026-09-09, user: "just say strength, not strength boost; get rid of the 'X COINS' text underneath and make '#x STRENGTH' fill the entire space; STRENGTH lower case")
- `HeadbandShopClient`: `Stats.Tier` now reads `Catalog.StrengthMultOf(name) .. "x strength"`; the
  `Stats.Price` line is gone (the buy button already says "BUY 15K" / "EQUIP" / "EQUIPPED" / "FREE").
- Authored GUI (`StarterGui.HeadbandShop.Shop.Body.Preview.Stats`): the `Price` TextLabel was
  DESTROYED (it was 332x61 at (30, 67), ZIndex 50, FredokaOne, TextScaled, white, 4 px black
  UIStroke -- rebuild from that if it is ever wanted back). The row above the button (button top
  is y = 144.5) is now `BoostIcon` 80x80 at (22, 32) + `Tier` 270x132 at (108, 6); both
  "2x strength" and "13x strength" report TextFits (bounds 138x78 at the 0.6 UIScale, i.e. the
  text is width-limited at roughly 45 px design size, up from about 29).
- `HeadbandsCatalog`: doc line updated to the new wording. Mirrors checksum-match live. Edit-mode
  only (playtest still blocked). NOT saved / published.

### Coin icon beside the buy price (2026-09-09, user: "next to buy and the purchase amount put the coins icon rbxassetid://15402839520")
- Authored GUI: `StarterGui.HeadbandShop.Shop.Body.Preview.Stats.BuyButton.CoinIcon` ImageLabel
  (`rbxassetid://15402839520`, the VectorIcons "Coin" Image, 52x52, anchor (0, 0.5) at (260, 38),
  ZIndex 55 like the Label, ScaleType Fit, authored Visible = false).
- `HeadbandShopClient`: `showCoin(priced)` -- beside a price the Label shrinks from 285 to 225 wide
  (285 - 52 icon - 8 gap) and slides left so "BUY 15K" + icon stay centred in the button; EQUIP /
  EQUIPPED / FREE / BUYING... / EQUIPPING... get the full width back and hide the icon. Called from
  `refresh()` (priced = not wearing, not owned, Price > 0) and from `submit()` for the transient text.
  "BUY 500" ... "BUY 50M" all TextFit in the 225 width (they are height-limited at 58 px, so there
  is a small gap before the icon).
- Mirror checksum-matches live; edit-mode only (playtest still blocked). NOT saved / published.

### Coin icon moved before BUY (2026-09-09, user: "yeah put it before buy")
- `BuyButton.CoinIcon` now sits at the left edge of the label area, (27, 38) anchor (0, 0.5), and the
  225-wide priced label is centred at x = 200 (spans 87.5..312.5), so the pair reads "[coin] BUY 15K".
  Only `showCoin()` in `HeadbandShopClient` changed (label x = left + icon + gap + width/2); the
  hide/show rules are the same. Mirror checksum-matches live. NOT saved / published.

## HUD made live + Zombie-style shop (2026-09-10)

User: "make the HUD functional (live values, working day/night timer), replace cash with the Zombie
game's coin icon in gold, make the shop frame like the Zombie store (cucumbers / pet bundles /
boosts), make the strength + button open the shop on its strength section, author all UI in
StarterGui". Sources + builders live in `hud-shop/` (served to Studio with
`pets-remake/serve.ps1 -Port 8769 -Root hud-shop`, applied by `hud-shop/install.lua` in one
execute_luau). Backup of the previous StarterGui pair:
`backups/StarterGui_CucumberMenus+HUD_before-shop-2026-09-10.rbxm`.

**StarterGui.CucumberHUDDesign** (authored, `build_hud.lua` patches it; `HUDClient` LocalScript inside):
- `Counters.StrengthValue` / `Counters.CoinValue` (was CashValue) follow `player.Data.Strength` /
  `.Coins` in the design's "189.9M" style (one decimal above 1000, NumberAbbrev suffixes) with a
  Heartbeat-stepped PopScale pop on change. `CoinIcon` (was CashIcon) = the Zombie wallet coin
  `rbxassetid://15402839520`; the value is the Zombie wallet gold (255,200,60), no "$".
- `NightTimer.TimeLabel`: Day -> "in 4m 43s" (until night), Night -> "ends in 8s", from the
  workspace attributes CyclePhase / PhaseEndsAt against `workspace:GetServerTimeNow()`.
- `Counters.AddStrength` is centre-anchored with a transparent `OpenStrengthShop` TextButton on top:
  ButtonFX press pop, then `CucumberMenus:SetAttribute("OpenRequest", "Shop:Strength#n")`.
- Dev hook: `CucumberHUDDesign` attribute `HUDDev = "plus"` presses the +.

**StarterGui.CucumberMenus.ShopPanel** (authored by `build_shop.lua`, 1140 x 735 like the Zombie
`Display.Frame.Frames.Store`; every instance is in StarterGui, nothing is generated at runtime):
- Zombie art ids: framed background 75881657992560, red "SHOP" ribbon 75227340977908, close button
  102086640822931 / 111663825325576 / 73973960226016, coin tab 92289502784771, boosts tab
  126124956187141, green stud card 115036257256165 + 101976791108135, orange Robux pill
  82561484372883 / 135030509362648 / 81440968694247 + Robux icon 107616907671837 (big pill
  118990973424405 / 89535966466387 / 77537703318285 + 82049654718568), boost card tiles / lights /
  artwork ids as in the Zombie DoubleCucumbersBoostCard. The Strength tab is a composed tile
  (green, arm icon 15403007921) because the Zombie has no such tab.
- `Content.ContentPanel.Catalog` (ScrollingFrame, AutomaticCanvasSize Y) holds, in LayoutOrder:
  `StrengthHeader` + `StrengthSection` (Small/Medium/LargeStrengthPack: attrs StrengthAmount
  100 / 1000 / 10000, ProductId 0), `CoinsHeader` + `CoinsSection` (Small/Medium/LargeCoinPack:
  CoinsAmount 10000 / 50000 / 250000, ProductId 0), `BoostsHeader` + `BoostsSection`
  (`DoubleStrengthBoostCard` "x2 Strength" with three duration pills, ProductId 0 - no boost
  system exists yet, they only say SOON). Pet bundles were left out: the product pets are not in
  this place.
- Pills = GuiButtons with attribute `PurchaseTemplate`; the ProductId is read from the pill, else its
  card. Id 0 -> price "SOON" + Notify "Coming soon!"; id > 0 -> GetProductInfo price +
  PromptProductPurchase, success = flash + Cash Register / Magic Shimmer + Notify "Purchase
  complete!". **To sell a pack:** create the Developer Product, paste its id into the card's
  ProductId attribute (StarterGui, no code change), publish.
- `ShopController` (ModuleScript in CucumberMenus, started by MenuClient): prices, purchases, the
  tab rail (attribute `Section` on each tab; selected tab TabScale 1.12; `ShopPanel` attribute
  `RequestedTab = "<Section>"` selects + scrolls; the tab follows manual scrolling). Scroll + tab
  animations are Heartbeat-stepped (ButtonFX.Animate). Measured: ScrollingFrame.CanvasPosition,
  AbsoluteCanvasSize and AbsoluteWindowSize share the same SCREEN-pixel space under a UIScale.
- `MenuController` changes: fit() uses each panel's own authored size; hover() honours a
  `HoverBaseScale` attribute (the boost pills rest at 0.81); gui attribute
  `OpenRequest = "<Panel>[:<Section>][#nonce]"` opens a panel on a section (RequestedTab is
  cleared then re-set one step later so the same section re-fires); `api.Open(name, section)`.
- Dev hook: `ShopPanel` attribute `ShopDev = "tab:<Section>" | "buy:<n>"`.
- `ServerScriptService.ShopProductsServer`: registers every card with ProductId > 0 and
  StrengthAmount / CoinsAmount through `GymService.RegisterProduct` (DataService.Increment on
  receipt; NotProcessedYet until the profile is loaded).

Verified in a solo playtest (unfocused Studio, numeric): HUD 32.2K / 1.2K gold, timer "in 1m 34s"
= PhaseEndsAt - now, + -> OpenPanel Shop / RequestedTab Strength / Strength tab 1.12, Coins tab
scrolls the header to 0.5 px from the top, Boosts clamps to the canvas end, manual scrolling moves
the highlight, + again lands back on Strength, a SOON pill toasts "Coming soon!". NOT saved /
published by me.

## Left-menu swap transition (2026-09-10, user: "when shop and index change to build and manage, tween the shop and index out and tween the build and manage in with a really nice transition, so the player notices it but it's not disruptive")

`StarterGui.CucumberHUDDesign.BaseHUDController` (mirror `hud-shop/BaseHUDController.lua`, backup
`backups/StarterGui_CucumberHUDDesign_before-menu-swap-tween-2026-09-10.rbxm`) used to flip the
Visible flags of the five `LeftMenu` buttons (Shop / Index outside the owned plot, Build / Manage
inside, BenchStrength while lying on the bench). It now animates each button's *presence* (0 =
tucked away, 1 = the authored pose):
- leaving: slides toward the screen edge by 42 % of its width while shrinking to 82 % and fading,
  0.16 s Quad In; arriving: the reverse with a Back Out overshoot (~3 % past rest), 0.30 s, setting
  off 0.08 s after the old occupant of its slot starts leaving; the bottom row trails the top by
  0.06 s. Whole swap ~0.45 s.
- pose = Size / Position written directly (no UIScale: MenuController's HoverScale already sits in
  Shop / Index, and two UIScales under one object do NOT stack - measured 200x100 with two 0.5
  scales = 100x50). Fade = every BackgroundTransparency / ImageTransparency / TextTransparency /
  UIStroke.Transparency below 1 is snapshotted (at Start, and again each time a settled button
  starts leaving) and lerped toward 1, so no CanvasGroup and the authored look comes back exactly
  (StudTexture 0.40, CenterGlow 0.79 ...). Visible = presence > 0.
- Heartbeat-stepped through `ButtonFX.Animate` (plays and can be measured in an unfocused Studio).
- a newer swap bumps the button's token: the running move stops and the next one continues from
  the current presence (a reversal 0.12 s in turns straight back, no jump); a returning button that
  is already part-way in skips the 0.08 s slot delay. The first mode after spawn is applied without
  motion (players spawn on their plot, so Build / Manage simply start visible).
- HUD attributes BaseMode / BenchMode unchanged. Dev hook: `CucumberHUDDesign` attribute
  `BaseDev = "inside" | "bench" | "outside"` forces a mode, nil releases it.

Verified in a solo playtest (unfocused Studio, per-frame client sampling): leave -> Build x 0 ->
-0.09 -> -0.23 -> -0.33 (fill 0 -> 0.15 -> 0.65 -> 1) in 0.16 s, Shop -0.33 -> +0.033 (1.02
size) -> 0 by 0.43 s, Index / Manage the same 0.05 s later; enter = mirror; bench = Build stays,
Manage out, BenchStrength in (w 1.16 -> 1.35); out/in/out flicks and 0.12 s / 0.20 s reversals all
settle on the authored values with no leftover transparency. NOT saved / published by me.

## Build mode (2026-09-10, user: "click Build -> hide Build / Manage and the backpack, bottom-middle buttons in the same style, one per kind of build in ServerStorage.Builds; a kind shows its builds - title, viewport, cost - in a long row at the bottom, not covering the screen; clicking a build buys it, it's on your mouse and you place it in your base")

Sources in `build-mode/` (served with `pets-remake/serve.ps1 -Port 8770 -Root new-map-cucumber-game/build-mode`,
applied by `build-mode/install.lua` in one execute_luau). Backups: `backups/ServerStorage_Builds_flat-before-build-mode-2026-09-10.rbxm`
(the props before sorting), `backups/StarterGui_CucumberHUDDesign_before-menu-swap-tween-2026-09-10.rbxm` (HUD).

**The catalog is the folder.** `ServerStorage.Builds` was sorted into `Walls` (WoodenWall 150, StoneWall 400,
IronWall 800, BarbedStoneWall 1,200), `Defences` (SpikeTrap 500, BoostPad 750, Catapult 1,500, Turret 2,500),
`Garden` (Sunflower 50 .. Fountain 1,000) and `Fun` (BeanBag 150 .. DJBooth 2,000); every model got a `Cost`
attribute (edit it in Studio to re-price - no code change). One bottom button per subfolder, one card per
model; the eight Blender collections that ship three props side by side (attribute `Variants`, parts
prefixed A_/B_/C_: Tree, Bush, Sunflower, HayBale, Lantern, TikiTorch, BeanBag, NeonSign) become one card
per variant (`Tree_A` "Oak", `Tree_B` "Pine", `Tree_C` "Sapling" ...; names in `BuildCatalog.VARIANT_NAMES`).
48 builds in all. Move a model between subfolders to move its card; drop a new model in to sell it; a
subfolder the catalog does not know gets a neutral grey button after the four.

- `ReplicatedStorage.Modules.BuildCatalog` (mirror `BuildCatalog.lua`): categories (order + gradient
  colours: Walls amber, Defences red, Garden the HUD green, Fun purple; Back / Rotate cyan, Done / Cancel
  red), default costs, variant names, `BuildsIn(category)` (cheapest first) / `Find(key)` over the
  templates, `FormatCost` ("1,500").
- `ServerScriptService.BuildService` (mirror `BuildService.server.lua`): at start clones every model into
  `ReplicatedStorage.PlaceableBuilds/<Category>/<Key>` - variant parts split by prefix, all anchored, an
  invisible `Hitbox` PrimaryPart around the bounding box, the authoring attributes (Notes, Pivot_*,
  State_* ...) dropped, `Key / Category / DisplayName / Cost / Source` stamped. Answers
  `Remotes.requestBuildPlacement(key, cframe) -> ok, reason` with EggPlacement's rules (own plot, standing
  at the base, X / Z + yaw only, footprint inside the plot, no overlap with `plot.Placed`) PLUS the plot's
  fixtures (`Map.Lobby.PlotFixtures/<plot>`: upgrade board, bench, gym platform), then charges the Cost
  (`DataService.Get / Increment` "Coins") and clones the build into `plot.Placed` (attributes Owner /
  BuildKey / Category / DisplayName / Cost / PlotX / PlotZ / Yaw, tag `PlacedBuild`). Coins are charged
  at placement, never on the pick, so cancelling costs nothing.
- `StarterGui.BuildMenu` (built by `build_buildmenu.lua`, DisplayOrder 25): `Categories` (transparent
  bottom-centre row, UIListLayout) and `Catalog` (dark panel: `Bar` = Back / Title / Hint / Rotate /
  Cancel, `Row` = horizontal ScrollingFrame of cards) plus `Templates` (`CategoryButton`, `BuildCard`,
  frame-built `Icons` Walls / Defences / Garden / Fun / Done / Box). The button shell copies the HUD
  LeftMenu look exactly (dark 12,12,12 rounded frame + 2 px outline, white Fill with a 90-deg gradient +
  stud texture 14905298636 at 0.4, InnerHighlight stroke, BuilderSans ExtraBold label with a 2.5 px dark
  outline, transparent `Press` TextButton on top).
- `BuildMenuClient` (LocalScript in BuildMenu, mirror `BuildMenuClient.client.lua`): Build ->
  `CucumberHUDDesign` attribute `BuildMode = true` (BaseHUDController tucks the WHOLE left menu away with
  the swap motion), `PlayerGui.Hotbar.Enabled = false`, tools unequipped, the Categories row pops up (a
  UIScale Pop on the row, Back Out). A category -> Catalog (title, cards with a ViewportFrame of the
  template centred on the origin at a 35-deg FOV, DisplayName, coin icon + cost). A card -> affordability
  check (else red flash + "Need N more Coins") then the ghost (PlacementClient's logic: mouse ray on the
  plot slab, 1-stud grid, clamped inside, red Highlight while it overlaps plot.Placed or the fixtures -
  same test as the server); click / tap places, R / Rotate turns 90, right-click / Esc / Cancel / the
  same card drops it; after a placement the same build stays on the mouse (walls tile fast). Done,
  walking out (BaseMode false), dying or respawning exits: BuildMode false, hotbar back. Sizes are pixels
  from the ScreenGui (`Fit`): buttons 44-74 px tall x 2.6, catalog 28 % of the height (170-250 px) x 62 %
  of the width (320-980 px); cards 0.8 : 1 of the row.
- Dev hooks: BuildMenu attribute `BuildDev = enter | exit | back | category:<Name> | pick:<Key> | place |
  place:<x>,<z> (plot space) | rotate | cancel`; the existing workspace `HeadbandDev = coins:<n>` tops up.

**Verified** (solo playtest 2026-09-10, 1585 x 553 play window, per-step client sampling): templates Walls 4 /
Defences 4 / Garden 23 / Fun 17; enter -> BuildMode true, Build + Manage hidden, Hotbar disabled, five
122 x 47 buttons (Walls, Defences, Garden, Fun, Done 82 x 47) centred at the bottom; Walls -> 4 cards
("Wooden Wall" 150 .. "Barbed Stone Wall" 1,200) each with its model in the viewport, panel 980 x 170 at
the bottom centre; pick -> ghost + Rotate / Cancel + hint; place at (0, -20) -> coins 1200 -> 1050, the
wall in plot.Placed with PlotX 0 / PlotZ -20 / Yaw 0; rotate + place at (12, -20) -> 900 coins, Yaw 90;
placing on the taken spot -> refused by the client's own overlap test (no coins, no call); cancel / back /
Defences / Garden / Fun / exit -> Build back at rest, hotbar on, no ghost left. NOT saved / published.

**Not done / caveats:** placed builds are NOT saved (nothing on a plot is yet - eggs and cucumbers vanish
on rejoin too); PlotX / PlotZ / Yaw / BuildKey are stamped so a plot save can serialise them. There is no
remove / sell / move yet (the Manage button is the natural home). Placed builds keep their authored
collisions (walls block, floors are walkable); the Blender notes about non-collidable glass / water were not
applied. Turrets, traps and boost pads are decoration for now - no behaviour.

### Build mode fixes + floors (2026-09-10, later, user: "builds keep unselecting randomly when I select them; Build / Manage tween scale on hover; in the walls section add Flooring and a Staircase built from parts - going up the staircase lets you lay flooring on a second floor 10 studs up, never on the first; the Done button is just a square with a red X; don't let my PC sleep")

- **Unselecting:** right-click cancelled the placement, and right-click drag is the camera orbit, so every
  camera turn dropped the build. Right-click now does nothing (Esc / Cancel drop it; clicking the selected
  card again no longer toggles it off either). The Catalog panel is `Active`, so a click on it never falls
  through to a placement.
- **Hover pops:** BaseHUDController gives Build / Manage the pop MenuController gives Shop / Index (a
  HoverScale UIScale: 1.035 hovered, 0.97 pressed, 0.12 s, Heartbeat-stepped) and resets it to 1 when the
  button tucks away. Dev hook: `CucumberHUDDesign` attribute `HoverDev = hover:Build | press:Manage |
  leave:Build`.
- **Staircase + Flooring** (`build-mode/make_stairs_flooring.lua`, part-built into `ServerStorage.Builds.Walls`):
  Staircase 4 x 14 x 10 to the landing (8 block steps of 1.25 rise x 1.5 run with lighter tread caps, a
  2-deep landing, handrails on both sides, the far edge of the landing open), Cost 600. Flooring 8 x 8 x 1
  of four plank strips, Cost 200, attributes `Level = 2` + `IsFloor = true`.
- **Floors:** `BuildCatalog.LEVEL_HEIGHT = 10`. A Level 2 template aims at the plane 10 studs above the
  plot (the mouse ray meets that plane in plot space) and is valid only while the player's root is within
  `UPSTAIRS_SLACK = 4` of the level - up the stairs or on flooring - otherwise the ghost stays red and the
  hint reads "Go up a staircase to lay flooring". IsFloor puts the tile's TOP at the level, flush with the
  landing. BuildService applies the same rule ("Go up a staircase to build up there"); the overlap test runs
  at that height, so a tile cannot cover the stairwell (the staircase hitbox reaches its rails) but butts
  against it. Placed builds carry `Level`. Give any model `Level = 2` in Studio and it becomes an upstairs
  build (its bottom then sits on the level).
- **Close button:** the Categories row ends in a square (h x h) with only a red X glyph on a light fill
  (`BuildCatalog.CLOSE`), no label.
- `keep-awake.ps1` (repo root): SetThreadExecutionState keeps Windows and the display awake while it runs
  (default 6 h; Ctrl+C or killing the powershell process ends it, no settings are touched). Windows PowerShell
  5.1 refuses `[uint32]0x80000000` (it reads the literal as a negative int32) - the flag is written as decimal.

Verified (solo playtest 2026-09-10): hover:Build -> 1.035, press:Manage -> 0.970, leave -> 1.000, and Build's
scale reads 1.000 again after it tucked away; Done 47 x 47, label hidden, glyph (235,35,35); Walls cards
Wooden Wall 150, Flooring 200, Stone Wall 400, Staircase 600, Iron Wall 800, Barbed Stone Wall 1,200; Flooring
picked on the ground: ghost 9.5 above the plot, red, hinted, a place attempt spends nothing; Staircase placed
(29 parts, landing top exactly 10.00 above the plot); root moved onto the landing (13.9 up): hint normal,
Flooring placed at (0, -36) with its top at 10.00, Level 2, -200 Coins; the same tile over the stairwell
refused; back on the ground it is red again; exit restores Build + hotbar. NOT saved / published.

### Flooring on both floors, builds on flooring (2026-09-10, later, user: "allow flooring on the first floor too - it only turns the grass into planks, no extra thickness; let users place anything on the flooring, and on the second-floor flooring")

- **Where a build lands** is now the floor the PLAYER stands on (`BuildCatalog.PlayerLevel`: the ground,
  or the storey 10 up once the root is within `UPSTAIRS_SLACK = 4` of it - step 3 of a staircase, the
  landing, existing flooring). No `Level` attribute on models any more; the server reads the level back
  from the requested height (a build's bottom, a tile's top: `LevelFromEdge`) and refuses anything above
  the player's floor ("Go up a staircase to build up there").
- **Flooring is a surface** (`IsFloor = true`): on the ground its top sits `FLOOR_LIFT = 0.05` above the
  grass (`FloorTop`) - the grass reads as planks, no step a humanoid feels, no coplanar flicker; upstairs
  its top is AT the level, flush with the staircase landing.
- **Overlap by kind** (`BuildCatalog.Blocks`, client + server): on the ground a tile and a build ignore
  each other - a wall stands on a tile, a tile slides under an existing wall / egg / cucumber - while a
  tile blocks a tile and a build blocks a build; upstairs a tile blocks on everything (never through the
  stairs); fixtures (bench, board, platform) block everything.
- **Support upstairs** (`BuildCatalog.Supported`): anything but a tile on level 2 needs a placed floor
  tile under the centre and the four (half-stud inset) corners of its footprint, else the ghost stays red
  with "Needs flooring under it" and the server refuses with the same words. A second staircase on
  upstairs flooring is allowed but `MAX_LEVELS = 2` keeps builds on level 2 (raise it for more storeys).

Verified (solo playtest 2026-09-10): ground tile at (10, 10) top 0.05 above the grass, Level 1, ghost never
red; Wooden Wall on that tile allowed, bottom exactly at the plot top; a second tile overlapping it stays
red and spends nothing; a tile slid under a wall already standing at (30, 10); a level-2 wall requested
from the ground via the remote -> "Go up a staircase to build up there"; upstairs: tile at (0, -36) top
10.00, wall on it bottom 10.00 (Level 2), the same wall over bare air red + "Needs flooring under it" on the
client and refused by the server with the same words, while the ground version of that spot went through;
a tile over the stairwell refused. NOT saved / published.

### Grass grid, 10-stud walls, moving builds (2026-09-10, later, user: "flooring completely replaces the grass tile it's on (turn the base grass into tiles); make flooring collide; the X button is just a text label; walls 10 studs so they reach the second floor; highlight the object red when it can't be placed; when an object is selected hide the build menu, show only Rotate and Cancel; click any placed object to move it")

- **Grass tiles.** BuildService gives every plot a `GrassTiles` folder: `BuildCatalog.CELL` (8) x 8 parts
  in the plot's colour / material / top texture (edge strips take the remainder), columns centred on
  the plot's X, rows hung off the BACK edge that PlotUpgradeService keeps fixed (`FRONT_DIRECTION`
  (-1,0,0) copied into BuildCatalog), rebuilt when the plot is resized. Their top (`FLOOR_LIFT` 0.1
  above the slab) is the ground walking surface; they collide, the slab itself never did. Plot 1 (70 x
  85) = 110 tiles, 80 full. `CanQuery = false`, so the placement rays still hit the plot slab.
- **Flooring replaces a grass tile.** An IsFloor build snaps to the nearest FULL cell
  (`BuildCatalog.SnapCell`, client + server, yaw forced to 0) with its top at the grass top; `RefreshGrass`
  (on every plot.Placed change and after a move) makes the grass tile under a ground tile invisible +
  non-collidable and brings it back when the tile leaves. Placed tiles always collide.
- **Levels re-based on the walking surface** (`BuildCatalog.SurfaceY`): ground = grass top; upstairs =
  ground + `LEVEL_HEIGHT` (10) + `FLOOR_THICKNESS` (1), i.e. the upstairs tiles REST ON the 10-stud walls
  (bottom at 10, top at 11) and the Staircase landing was raised to 11 (8 steps of 1.375) to stay flush.
  A tile's TOP and a build's BOTTOM both sit at the surface; the level is read back from that edge.
- **Walls 10 tall** (`build-mode/scale_walls.lua`): stretched in height only (each part's Size.Y and
  height above the pivot x 1.25), width kept at 8 so they tile with the grid - a uniform ScaleTo made
  them 10 wide and a wall no longer fitted on one flooring tile (caught in the playtest).
- **Red when it can't go there:** the ghost's parts turn (255,60,60) and the red Highlight covers it
  whenever it overlaps, lacks flooring under it upstairs, or (tiles) the cell is taken; colours return
  the moment it can.
- **Placing strip:** while a build is on the mouse the catalog / category row hide and only `Placing`
  (a hint line over Rotate + Cancel) shows; Cancel / Esc / a drop bring the previous panel back.
- **Moving:** in build mode a placed build under the mouse lights up (white Highlight); clicking it
  lifts a ghost of it (the original goes 85 % see-through locally), the same strip shows, a click
  drops it through `Remotes.requestBuildMove(model, cframe)` - free, the same validation as a
  placement with the build's own parts ignored (`Validate(... ignore)`), attributes re-stamped, grass
  refreshed - Esc / Cancel puts it back. Builds only (tag PlacedBuild, own plot, Owner = you).
- **X button:** the close square's glyph is a single red "X" TextLabel (BuilderSans ExtraBold, dark
  outline).
- Dev hooks: `BuildDev = move:<placed model name> | move:last` joined the list.

Verified (solo playtest 2026-09-10): 110 grass tiles, top 0.10 above the slab, colliding, textured;
X = a 47 x 47 square with one "X" label; picking a wall hides the catalog and shows Placing with Rotate +
Cancel (ghost hitbox 10.00 tall), Cancel brings the catalog back; a tile aimed at (10, 10) landed on cell
(12, 9.5) with its top at 0.10 and that grass tile went transparent + non-colliding while its neighbour
stayed; a second tile aimed at a taken spot: ghost RED + Highlight; a wall on the tile: bottom 0.10, Level 1;
Staircase landing top 11.10; from the landing a tile at cell (4, -38.5) top 11.10; a wall over bare air
upstairs: "Needs flooring under it" + RED; moving the ground wall to (30, 10) (original faint 0.85 while
lifted, catalog back after); moving the ground tile (12, 9.5) -> (20, 17.5) restored the old grass tile and
hid the new one; a cancelled move left the wall where it was; the character stood on the upstairs tile
(root 4.6 above the surface, tile parts colliding). After the width fix (walls 8.0 x 10.0, Barbed 8.3): a
wall on the upstairs tile went in with its bottom at 11.10 and top at 21.10, and a tile laid over a ground
wall met its top exactly (wall top 10.10 = tile bottom 10.10). NOT saved / published.

### Plain 12-stud walls, upstairs tiling rule, Sell + Grid buttons (2026-09-10, later, user: "second-floor flooring has to be placed next to each other, the first touching a staircase end; remove Esc keybinds; use Blender to remove the spikes / gaps from each wall - just normal walls of whatever material; second floor at 12 studs and walls 12 high; a Sell button next to the X that sells any furniture you click while it is on; a grid-size button next to it for more precision")

- **Plain walls** (`plainwalls/build_plain_walls.py`, run in the open props.blend as NEW collections
  PlainWoodenWall / PlainStoneWall / PlainIronWall / PlainBarbedStoneWall so the spiky originals stay):
  8 x 12 tiling segments, flat tops, no pickets / barbs / wire - planks with two rails, coursed stone,
  riveted plates, and the "barbed" one is now a plain darker stone wall with a coping and plinth. 3-5
  parts each. Exported to `plainwalls/fbx/`, uploaded as group-owned Model assets (group 14583228,
  ids in `plainwalls/fbx/asset-ids.json`: WoodenWall 73524860990936, StoneWall 85011800830858, IronWall
  71752348100770, BarbedStoneWall 85084655395487) with the benches' `upload-model.ps1`, and installed by
  `build-mode/install_walls.lua` (LoadAsset, strip the collection prefix, undo the importer's 180-deg
  yaw, recolour from `plainwalls/manifest.json`, anchor + collide, pivot at the origin, keep the old
  Cost). The spiky originals are in `backups/ServerStorage_Builds_Walls_spiky-before-plain-2026-09-10.rbxm`.
  Renders: `plainwalls/renders/`.
- **12-stud storey:** `BuildCatalog.LEVEL_HEIGHT = 12`; upstairs surface = ground + 13; the Staircase
  was rebuilt with 8 steps of 1.625 to a landing at 13 (`make_stairs_flooring.lua`) and carries
  `IsStairs = true`.
- **Staircase snap** (`BuildCatalog.SnapStairs`, client + server): the landing's open edge (the hitbox's
  -Z face) lands on a grass-cell boundary along the way it faces and the 4-wide landing is centred in a
  cell across it, so the first upstairs tile butts against it exactly.
- **Upstairs tiles must join the floor** (`BuildCatalog.FloorAnchored`, client + server): edge to edge
  with a tile already on that level, or the cell straight off a staircase landing (a probe half a stud
  beyond the landing edge must fall inside the tile); else "Start at the top of a staircase" / "Place
  it next to another tile", red ghost, no call.
- **No Escape keybinds** in build mode (hints say "Cancel drops it" / "Cancel puts it back"). The shop
  panels' Escape (MenuController) is untouched.
- **Sell:** a Sell toggle after the X (amber; red "Selling" while on). While on, the hover glow is red
  and clicking one of your placed builds sells it through `Remotes.requestBuildSell(model)`:
  `BuildCatalog.SELL_REFUND` (0.5) of its Cost comes back, toast "Sold Wooden Wall for 75 Coins". Opening
  a category or leaving build mode turns it off.
- **Grid:** a "Grid 1" button after Sell cycles `BuildCatalog.GRID_SIZES` (1 / 0.5 / 0.25 studs) for
  ordinary builds; Flooring still snaps to cells and the Staircase to cell edges.
- Dev hooks: `BuildDev = sell | sellclick:<Name>|last | grid` joined the list.

Verified (solo playtest 2026-09-10): wall templates 8.0 x 12.0 (stone 8.1 from the block jitter) with the
new part names; row = Walls / Defences / Garden / Fun / X 47 x 47 / Sell 94 x 47 / Grid 94 x 47; Grid ->
"Grid 0.5" and a wall aimed at (10.3, 10.3) landed on (10.5, 10.5); a Staircase aimed at (0, -20) snapped to
(4, -19.47) with its landing edge on z = -26.5 and its landing top 13.10 above the slab; from the
landing a tile aimed far away: "Start at the top of a staircase" + RED, nothing placed; the cell off the
landing (4, -30.5) went in with its top at 13.10; the diagonal cell: "Place it next to another tile" +
RED; the edge-adjacent cell went in; a wall on the upstairs tile: bottom 13.10; Sell on -> "Selling",
selling the ground wall paid 75 Coins with the toast, Sell off -> "Sell". NOT saved / published. The
Open Cloud key the user pasted in chat was written to a session temp file for the four uploads and
deleted straight after; it should be rotated.

### Barbed wall back, flooring on the edges, Collisions + Grid on the strip, icon squares (2026-09-10, later, user: "revert the barbed stone wall; let me place flooring anywhere in the base even edges; add grid and collisions buttons to the rotate / cancel menu, collisions as a checkbox; make Sell and Grid square buttons with icons")

- **BarbedStoneWall reverted** from `backups/ServerStorage_Builds_Walls_spiky-before-plain-2026-09-10.rbxm`
  (import_rbxm -> clone -> height-only stretch to 12 -> replaced the plain one, Cost kept). The plain
  barbed asset 85084655395487 stays uploaded but unused; the other three plain walls stay.
- **Flooring on every cell:** `BuildCatalog.SnapCell` now returns the nearest cell of ANY size (full or
  edge strip) with its width / depth, and `BuildCatalog.FitTile` stretches the tile's parts + Hitbox to
  it about the pivot - the ghost every frame, the placed model once, a moved tile again on its new
  cell. So the 3-wide side strips and the 5-deep front strip take flooring and the grass strip under
  them hides like any cell. Upstairs adjacency (`FloorAnchored`) now tests boxes touching, any sizes.
- **Collisions** (`BuildCatalog.Blocks(part, holder, floor, level, collisions)`, client + server): the
  placing strip is now Rotate / Grid / Collisions / Cancel. Collisions is a checkbox (white box, green
  tick; green shell when ticked, grey when not; ticked by default, `DEFAULT_COLLISIONS`). Ticked: a
  build may not overlap another build and an upstairs tile may not cut through anything; unticked:
  builds may intersect. Fixtures always block and a tile never takes a held cell. The client sends
  `{Collisions = bool}` with every placement and move and the server honours it.
- **Grid on the strip:** the same square Grid button as the row, both showing the size in the corner
  ("1" / ".5" / ".25") and both cycling the shared setting.
- **Icon squares:** Sell and Grid are h x h squares with Creator Store decals - Sell an orange price tag
  (icons8, 109373579106675) on a light face that turns red while selling; Grid a Material Symbols 3 x 3
  grid (103137915783183, white, tinted dark) on the light-blue face. `BuildCatalog.ICONS`.
- Dev hook: `BuildDev = collisions` (toggle) joined the list.

Verified (solo playtest 2026-09-10): BarbedStoneWall template 8.28 x 12.00 x 2.31 with Ironwork /
BarbedWire / Capstones / Moss / Plinth; Sell and Grid 47 x 47 with the two decal ids, no labels, Grid corner
"1"; the strip: Grid 47 x 47, Collisions 117 x 47 ticked, Cancel; two grid presses -> ".25" on both
buttons; a second wall on a placed wall with collisions on: refused (1 wall, nothing spent), with the box
unticked: placed (2 walls, -150); a tile aimed at (35, 10) landed on the 3 x 8 side strip (planks 0.75
wide) and hid that grass strip; a tile at (35, 42) landed on the 3 x 5 corner strip; moving the edge tile
to (10, 10) refit it to 8 x 8, restored the old strip and hid the new cell. NOT saved / published.

### Cells that divide the plot exactly (2026-09-10, later, user: "make it so flooring completely replaces the part of the grass that it is placed on" - a screenshot of grass still showing beside tiles at the plot edge)

The plot is not a whole number of 8-stud cells, so the leftover strips along the edges stayed grass
unless tiled separately and a tile never ran to the edge. Now `BuildCatalog.Cells` divides each axis
into round(Size / CELL) EQUAL cells (Plot 1, 70 x 85: 9 x 11 cells of 7.78 x 7.73 - 99 tiles), so the
grid ends exactly on the plot edges and a tile placed anywhere fills its whole cell, edge included,
with nothing left over. Every Flooring tile is `FitTile`d to its cell; the grass tile's checker texture is
scaled to one period per cell (`StudsPerTileU/V = cell size`); `RefreshGrass` matches a tile to its
grass cell by position (within 0.1) instead of a rounded key, since cell centres now land on fractions.
The staircase / adjacency edges use each cell's own half-width (a fixed 4 left the landing 0.14 off the
edge in the first pass - fixed and re-checked: SnapStairs puts the landing face on -19.318 = the row edge).

Verified (solo playtest 2026-09-10): 99 grass tiles 7.78 x 7.73, texture 7.78 / 7.73; a tile aimed at
the back-right corner (35, -42) spans x 27.22..35.00 and z -42.50..-34.77 - exactly to both edges - and
its grass tile is transparent; its neighbour spans 19.44..27.22 (gap 0.000) and hides its own grass tile,
two hidden in all; the staircase snapped and the first upstairs tile chained off its landing at top
13.10. NOT saved / published. Note for the tester: this run's character spawned OUTSIDE the plot (lobby
spawn) - build mode then correctly says "Go to your base to build" until you walk in.

### Sell / Grid icons visible (2026-09-10, later, user: "I can't see sell and grid icons")

The squares were given the Creator Store DECAL ids (109373579106675 / 103137915783183); an ImageLabel
needs the underlying IMAGE id, so nothing drew. Resolved in Studio with
`InsertService:LoadAsset(decalId)` -> the Decal's `Texture`: Sell = 117943484902841, Grid =
113674539986704 (`BuildCatalog.ICONS`, `build_buildmenu.lua`). Verified in a solo playtest screenshot: the
orange price tag on the Sell square and the dark 3 x 3 grid with the "1" corner tag on the Grid square,
`IsLoaded = true` on both (ContentProvider:PreloadAsync reports Failure for every image in this Studio
harness, the coin and stud textures included - not a usable signal).

### Trash icon, drawn grid icon, no stairs upstairs (2026-09-11, user: "use a trash icon for Sell; for Grid something like the attached 3 x 3 grid icon, and add grid lines to the icon for every click; you can't place a staircase on the second floor")

- **Sell** = the Creator Store "Garbage icon" decal 8214461600 (a black trash-can outline PNG on a
  transparent background) -> its IMAGE id 8214461591 (`ICON_SELL` in `build_buildmenu.lua`,
  `BuildCatalog.ICONS.Sell`), untinted on the light face. Candidates 136196706074977 / 14002617522 /
  11768918612 are white-on-transparent (would need a dark tint), 8214461600 already reads dark.
- **Grid** is no longer an image. `GridGlyph` (builder) draws a dark-outlined, unfilled box with an
  empty `Lines` frame, on both the row's `Icons.Grid` template and the strip's `GridButton`;
  the client's `DrawGrid` fills `Lines` with `gridIndex + 1` two-pixel dark bars each way at
  i / (n + 1): snap 1 = 2 bars (the 3 x 3 look), 0.5 = 3 (4 x 4), 0.25 = 4 (5 x 5), back to 2 on the
  fourth press. `UpdateGridButtons` redraws both buttons alongside the corner tag, so the icon and
  the "1 / .5 / .25" tag always agree.
- **Staircase upstairs refused.** Server `Validate`: `if isStairs and level >= 2 then "Stairs go on
  the ground floor"` - placed BEFORE the player-floor check so the answer is the stairs rule wherever
  the player stands (place and move share it). Client `UpdatePreview`: an `IsStairs` ghost on level 2
  is invalid (red) with the same hint (`STAIRS_HINT`) - checked before the flooring / support rules.

Verified in a solo playtest (awesomeotheraccount on Plot 1): bars per button 4 -> 6 -> 8 -> 4 on
the row and strip Grid buttons with corner tags 1 / .5 / .25 / 1; the trash image `IsLoaded`
(32.9 px); screenshots of the row show the trash can and the 3 x 3 then 4 x 4 grid glyph. Server:
placing a Staircase at the level-2 surface -> `false, "Stairs go on the ground floor"`; placing one on the
ground -> ok; moving that one to level 2 -> the same refusal; sold back for 300. Client: standing at
level 2 with a Staircase picked, `Placing.Hint` = "Stairs go on the ground floor" and nothing was
placed. Gotcha: anchoring the character's root on the CLIENT does not replicate its position, so the
server still saw the player downstairs in the first run ("Go up a staircase to build up there") - which
is why the stairs rule now comes first. Not saved / published.

### One square per grass cell, the ghost stands in for the grass (2026-09-11, user: "split the grass on each plot into square tiles the same size as flooring; flooring completely replaces the grass tile; in build mode the hovered grass tile is hidden and replaced by the placeholder wooden one so there's no collision" + two screenshots of a translucent tile streaking against the grass)

- **Why the grass read as smaller tiles.** Each grass cell carried the plot's checker texture scaled to
  one period per cell - a 2 x 2 checker inside every cell - so the squares you saw were half a cell
  (about 3.9 studs) while a Flooring tile covers a whole cell. Now every grass cell is ONE flat square:
  no Texture child, two shades of the plot colour (the colour, and the same darkened a fifth - what the
  20 % black checker did) alternating by cell like a chessboard (`GrassShade` in BuildService, from the
  `I` / `J` indices `BuildCatalog.Cells` now carries).
- **Cell size** stays round(Size / 8) equal cells per axis (7.78 x 7.73 on the 70 x 85 plot): a plot is
  not a whole number of 8s and the edges must not leave a remainder (the round before), so a Flooring
  tile is stretched to its cell (`FitTile`) and tile and cell are always the same size - as near to
  square as the plot allows. Exact 8 x 8 squares would need the plot ladder changed to multiples of 8
  (it is 54 / 58 / 62 / 65 / 68 / 70 wide by 64 .. 85 deep, with 2-stud gaps between plots); not done.
- **Hover.** `GrassTileAt` + `HoverGrass` (BuildMenuClient): while a Flooring ghost stands on a ground
  cell that grass tile gets `LocalTransparencyModifier = 1` (client only). The ghost's top and the grass
  top are coplanar, which is what streaked in the screenshots. The previous tile is restored the moment
  the ghost moves to another cell, the player leaves the base, or placing stops (`StopPlacing`). A
  placed tile is still hidden for real by the server (`RefreshGrass`: Transparency 1 + CanCollide
  false) - with no Texture child there is nothing else to hide.
- Dev hook `BuildDev = "aim:<x>,<z>"` / `"aim:off"`: a standing plot-space aim that the `place` hook
  keeps (so a hover can be inspected).

Verified in a solo playtest (awesomeotheraccount on Plot 1; driven through the official Roblox Studio
MCP's `execute_luau` in the Client DataModel - see the gotcha): 99 tiles of 7.78 x 7.73, 0 Texture
children, 50 light + 49 dark, 0 neighbouring pairs share a shade. Hover cell A -> A modifier 1, B 0;
hover B -> A 0, B 1; place -> B Transparency 1, CanCollide false, the tile fitted to 7.78 x 7.73; cancel
-> B modifier back to 0 while the server's hide stays; move the tile over A -> A modifier 1 while
hovering, after the drop A Transparency 1 and B back to 0 / collidable; sell -> A back to 0. Not saved /
published.

**Gotcha (bridge):** the chrrxs Studio plugin auto-updated to v3.1.4 while its MCP server was still
v3.1.3, so every play-session peer failed `/ready` with HTTP 426 plugin_version_mismatch (Studio
console). `solo_playtest start` then says "not ready" / "did not become ready" even though Studio IS
in Play mode; the edit peer (loaded before the update) keeps working. Fallback used here: the official
Roblox_Studio MCP - `list_roblox_studios`, `get_studio_state`, `execute_luau` with
`datamodel_type` Client / Server, `start_stop_play`. Fix: restart the chrrxs MCP server (a new
desktop-app session) so it matches the plugin.

## Placed cucumbers pay every second + "+X" popups (2026-09-12, user: "make owned cucumbers generate money every second (there is already a set amount for every cucumber) and make it tween up from their overhead every second the amount of money it just made")

- **Income** (`LeaderstatsService.server.lua`): a 1 s loop (`INCOME_TICK`) walks every `PlacedCucumber`
  whose Owner is a player in the server with a loaded profile and standing in the workspace, sums
  `Rate x tick` (the Rate attribute the service already stamps - CucumberValues) and pays it with
  `DataService.Increment(player, "Coins", total, true)`. The HUD wallet and everything else that reads
  `player.Data.Coins` follow on their own. Nothing else changed: the Coins/s leaderstat, the card's
  rate line and the Rate stamping are as before.
- **Quiet writes** (`DataService.lua`): `Set` / `Increment` take a 4th argument `quiet`. The profile and
  the value object are updated as usual (the object's Changed hook sees the profile already matching and
  stays silent) but no `RequestSave` is made - the coins ride the next save: another key's write, the
  60 s ProfileStore autosave, or leaving. Without it the income would have asked for a DataStore write
  every second (debounced to one per 5 s, still ~700 writes an hour per player).
- **Tell the clients**: the same tick fires `Remotes.CucumberIncome` (RemoteEvent, created by the service)
  to everyone with two parallel arrays - the cucumbers that paid and their amounts.
- **Popups** (`PlacedCucumberCardClient.client.lua`): for each paid cucumber that has a card on this
  client (and is within `POPUP_MAX_DISTANCE` 70 studs of the camera), a BillboardGui `IncomePopup` on
  the same PlotHitbox: the card's own coin line recipe (coin icon + gold FredokaOne "+0.51", gold
  stroke), 4.4 x 1.05 STUDS (scale units, giants scale it like the card), its bottom edge starting on
  the card's TOP edge (`card.Top`, remembered when the card is built) and floating up `POPUP_RISE` 2.6
  studs over `POPUP_TIME` 1 s with a quad-out ease, a 0.16 s scale pop-in (0.3 -> 1.12 -> 1) and a
  fade over the second half; destroyed at the end. One shared Heartbeat step drives all live popups
  (plays in an unfocused Studio, like ButtonFX). `CoinLine` now returns label, icon, stroke, row so the
  popup can reuse it.

Verified in a solo playtest (awesomeotheraccount; driven through the official Roblox Studio MCP's
`execute_luau` - the chrrxs runtime peers still cannot register, see the plugin-version gotcha above):
a Spawn Sliced Cucumber placed on the plot (rate 0.5136/s) -> coins +1.5409 in 3.05 s = exactly 3 x rate,
Coins/s leaderstat "0.51", 3 popups in 3.05 s; one popup followed through its life: text "+0.51" in
gold with the coin icon, 4.40 x 1.05 studs, born a hair above the card's top edge (4.38 vs 4.21 - one
frame of rise), y 5.71 at 0.32 s (scale back to 1.00, no fade), y 6.72 and 63 % faded at 0.78 s, gone
at 1.18 s. The card itself still reads "Spawn / Sliced Cucumber / 0.51/s". An earlier run had a Cucumber
Tree (2.1364/s) pay +6.4091 in 3.10 s (= 3 ticks) before the night raid stole it. Mirrors
(LeaderstatsService / PlacedCucumberCardClient / DataService) refreshed. NOT saved / published.

Gotcha caught on the way: the first push of the client dropped `row.Parent = parent` from `CoinLine`
while adding its extra returns - the popup (and the card's rate line!) came out empty. Always dump a
built billboard's descendants in the check, not just its size and offset. Also: a RemoteFunction's
`OnServerInvoke` cannot be read from a server eval ("callback member ... get is not available") - drive
placement from the Client DataModel with `requestCucumberPlacement:InvokeServer(cframe)` after the
CarryDev `collect:<name>` hook.

## Base saving (cucumbers, pets, builds) + the admin panel (2026-09-12, user: "make it so cucumbers, pets and base builds save; make an admin panel for awesomeotheraccount: start night, start day, set my coins / strength and reset data (which does not work in Studio)")

Sources in `base-save/` (install: `stage.js` copies the patched DataService / PetHatchService / BuildService mirrors in,
`serve.ps1 -Port 8770 -Root base-save` + `receive.ps1 -Port 8766 -Root new-map-cucumber-game`, then `install.lua` in one
edit-mode eval: whole-file pushes, the two new scripts, the panel, and anchored in-place patches of CucumberCarry /
CucumberSpawner / DayNightCycle whose mirrors it then writes back through the receiver).

- **`BaseSaveService.server.lua`** (ServerScriptService): `profile.Data.Base = {Version, SavedAt, Cucumbers, Builds, Pets}`
  (added to DataService's template; Reconcile gives it to old profiles). Every position is stored relative to the plot's
  BACK-EDGE frame (`BuildCatalog.BackZ` - the edge PlotUpgradeService never moves), so a base survives a plot upgrade and a
  different plot next visit. Records: cucumber = kind (Zone / Type / Golden / Material / Mutations / SizeTier / Name) + the
  model pivot + the PlotHitbox CFrame and size; build = Key + Level + pivot; pet = PetName + position.
  RESTORE on profile load: wait for PlotService's plot, then for the plot's `PlotLevel` attribute to equal the saved level
  (PlotUpgradeService resizes asynchronously), a beat for the grass grid, then builds (ground floor first) -> cucumbers ->
  pets through the owning services' bindables. Nothing is charged or validated. SNAPSHOT after that: tag add / remove on
  PlacedCucumber / PlacedBuild / PlotPet, build moves (PlotX / PlotZ / Yaw / Level attributes) - debounced 0.5 s, then a
  real save - and a 30 s heartbeat (quiet) for wandering pets. A pick-up clears Owner before the tag goes, so an unowned
  removal refreshes every active player (cheap). LEAVE: the plot's cucumbers + builds are cleared (pets / eggs already go
  with the Owner attribute) so the next tenant starts clean and a return never doubles up. `ServerStorage.BaseSaveAPI`:
  Snapshot / Reset (empties plot + Data.Base, pauses) / Resume / Reload (empty + rebuild from the save: the test round trip).
- **Owning services' restore APIs.** `CucumberCarry`: `CucumberCarryAPI.RestorePlaced(player, plot, record, pivot, boxCF, boxSize)`
  spawns a field cucumber of the saved kind (`SpawnCarried` with `Force = true` - a new flag that skips the fields-closed
  and biome-full checks in SpawnCarried AND SpawnBreakable, so a night join restores too), clones it the way Grab() does
  (BuildCarryModel: rest pose + PlaceScale), destroys the field one, grows the copy back, pivots it exactly, rebuilds the
  PlotHitbox from the saved CFrame / size, stamps the attributes and the tag; `ClearPlaced(plot)`. `PetHatchService`:
  `PetHatchAPI.SpawnPet(player, plot, petName, spot)` / `ClearPets(plot)`. `BuildService`: `BuildServiceAPI.RestoreBuild(player,
  plot, key, pivot, level)` (SnapCell + FitTile for tiles, SnapStairs for stairs, height from the level) / `ClearBuilds(plot)`.
- **`DataService.lua`**: `Base` in the template; `DataService.ResetProfile(player)` = the whole profile back to a deep copy of
  the template, value objects updated, Playtime base restarted, saved at once.
- **`AdminService.server.lua`** + `Remotes.AdminAction(action, value) -> ok, message`, admins = `{[140977250] = "awesomeotheraccount"}`
  (everyone else: "Not an admin", whatever the client says; 0.3 s cooldown). `day` / `night` -> `ServerStorage.DayNightAPI.Force`
  (new in DayNightCycle: a forced night ends the day loop now and runs NightDurationSeconds; a forced day ends nightWait,
  lowers the wall and runs a FULL day from now off the shared clock, then `schedule()` takes over again). `coins` / `strength`
  + number -> DataService.Set (HUD, playerlist, physique follow). `reset` -> BaseSaveAPI.Reset, DataService.ResetProfile, the
  plot's Owner attribute bounced nil -> back (PlotUpgradeService level 0, GymService bench 1, EggPlacement / PetHatchService
  clear, badges refresh), BaseSaveAPI.Resume, LoadCharacter (physique, headband, carried load all fresh). It works in
  Studio because the profile is live there too ("Roblox API services available") - nothing is mocked.
- **`build_adminpanel.lua` + `AdminPanelClient.client.lua`** -> `StarterGui.AdminPanel`: an "ADMIN" HUD-style button at the
  top right opens the panel (START DAY / START NIGHT, COINS [box] SET, STRENGTH [box] SET, RESET DATA - press twice within
  5 s, Status line + Notify toast for every answer). The ScreenGui destroys itself for anyone not in ADMINS. One UIScale
  (720 px tall = 1.0, clamped 0.7 .. 1.2). Dev hook: gui attribute `AdminDev` = toggle | day | night | coins:<n> |
  strength:<n> | reset.

Verified in a solo playtest (awesomeotheraccount on Plot 3, official Roblox Studio MCP): all 11 bindables + the remote
present; forced night 0.4 s (45 s night), forced day 1.1 s (a full 180 s day, "Day 2502 started"); coins 12345 -> HUD
"12.3K", strength 500 -> playerlist 500, "abc" -> "Enter a number, 0 or more". Round trip: a Slice Stack cucumber, a
WoodenWall (yaw 90), a Flooring tile and a Cat pet placed -> Snapshot true -> Reload (empty + restore from Data.Base) in
0.9 s -> all four back, each moved 0.000 studs, facings equal (the pet takes a fresh random yaw), hitbox sizes equal, the
cucumber's Rate re-stamped 0.5909 -> 0.5909. Reset: coins 12020 -> 0, strength 500 -> 0, Playtime -> 1, plot 70 x 85
level 6 -> 50 x 60 level 0, bench level 1, plot emptied (0 cucumbers / builds / pets / eggs, 48 grass tiles rebuilt),
character respawned, saving resumed (Snapshot true). Backup of the six touched scripts:
`ServerStorage.__BaseSaveBackup_2026_09_12`. NOT saved / published.

Not covered: placed EGGS are not saved (not asked; an egg mid-hatch is lost on leave), and the leave path (plot cleared on
PlayerRemoving) could not be exercised in a solo playtest. Gotchas met: a RemoteFunction's `OnServerInvoke` cannot be READ
from a server eval (place from the Client DataModel); `require`-ing DataService in a server eval is a second module
instance (GetData nil) - read `player.Data` values / the leaderstats instead; `serve.ps1` serves ONE flat folder (hence
stage.js); the night raid steals test cucumbers, so test persistence by day.

### Saved eggs that count down offline + the vanishing bench (2026-09-12, user: "save placed eggs, and let them countdown offline; upgrading bench caused its baseparts to disappear like this, fix" + a screenshot of a floating barbell over three flat slabs)

**Eggs.** `base-save/install2.lua` (same two loopback servers as install.lua). `EggPlacement.server.lua` gained
`ServerStorage.EggPlacementAPI.RestoreEgg(player, plot, record, pivot)` / `ClearEggs(plot)`: the placeable template
by EggName, scaled by the saved Scale, pivoted to the saved pivot, the roll re-stamped (Kg / Scale / Material /
Mutations / DisplayName, `CucumberMutations.ApplyLook`) and the CLOCK copied as saved - `PlacedAt` / `HatchAt` are
`workspace:GetServerTimeNow()` values, i.e. real time, so the countdown keeps running while the owner is away and
an egg whose HatchAt has passed is ready the moment its owner steps on it (PetHatchService.CheckEgg compares the
same clock; EggTimerClient shows "0s"). `BaseSaveService` saves `Data.Base.Eggs` (EggName, Kg, Scale, Material,
Mutations, DisplayName, HatchSeconds, PlacedAt, HatchAt, Pivot), restores eggs FIRST on rejoin, watches the
PlacedEgg tag for snapshots, and clears them on Reset / Reload; DataService's template Base has `Eggs = {}`.
Verified in a solo playtest: two eggs made through the API (a Golden NEON Basic 1.2x with 120 s to go, a plain
one whose clock ran out 30 s "ago") -> Snapshot -> Reload -> both back 0.000 studs off, 117.1 s / -32.9 s left
(the wall clock kept ticking, nothing was reset), material / scale / mutations / names intact.

**Bench.** Not the upgrade itself: `BenchTierClient` shows a bench tier by building its Blender geometry at run
time with EditableMesh (`BenchRuntimeMesh.BuildTier`), and the client's EditableMesh MEMORY BUDGET ran out
part-way through ("Failed to create empty EditableMesh that was requested due to reaching memory budget limits").
`BuildTier` skipped the meshes that failed and returned a half-built model - one flat slab (the pad) plus the bar -
which the client cached and showed for the plot: the floating barbell over slabs in the screenshot. Every tier-1
bench had a two-part "Starter" build for the same reason, and the Starter builds were what ate the budget first.
Fixes: (1) `BenchRuntimeMesh.BuildTier` is all-or-nothing - if any mesh of a theme fails it destroys the model,
warns, sets the runtime path unavailable for the session and returns nil, so `BenchTierClient.TierModel` falls
through to the part-built `Assets.BenchTiers` models (Fallback=true, tiers 2-6) or the server bench; (2)
`BenchTierClient.TierModel` returns nil for tier 1 (the server bench IS the Starter look), so no budget is spent
on six Starter copies. Verified: tier-1 plots show the server bench (25 parts visible, nothing hidden), the tier-2
plot shows a complete runtime Iron bench (Feet / Frame / Pad meshes, bottom on the plot top, top at the bar) with
IsAvailable still true. Backups of EggPlacement / BenchRuntimeMesh / BenchTierClient joined
`ServerStorage.__BaseSaveBackup_2026_09_12`. NOT saved / published.

Gotcha: one playtest started right after the install still ran the OLD client copies (stale visuals, missing
bindable) - a second start had the new ones. Check a marker string in the running `PlayerScripts` copy before
trusting a negative result.

### Grass texture back on every tile, flooring that really replaces its cell (2026-09-12, user: "add back the texture that was there for grass to each and every grass tile, make grass look like it did before while keeping the tile system; flooring did not replace the grass tile - from any angle grass should not overlap the tile")

- **Look.** Round 9's two flat shades are gone. Every grass tile is the plot's colour / material / stud top plus
  a clone of the plot's own top Texture (rbxassetid://6372755229, 20 % black checker) at ONE period per cell:
  the plot had one period per 8 studs and a cell is ~8, so the checker reads exactly as the original plot did
  and each tile starts a period at its corner, seamless across the grid (`BuildGrass`).
- **The overlap.** A placed floor tile fits its cell exactly (checked: an 8.33 x 7.50 tile on the 8.33 x 7.50
  cell of a level-0 plot, 0.000 off), so the overlap the user saw comes from a plot RESIZE: an upgrade (or the
  admin reset) regrids the cells (round(Size / 8) per axis, every cell changes size) while the placed flooring
  kept its old size and spot, straddling the new grass tiles - and `RefreshGrass` only hid the tile whose centre
  matched, so nothing was hidden. Fixes in `BuildService`: (1) `RefitTiles(plot)` runs after every grass
  rebuild: each floor tile is re-snapped and re-fitted (SnapCell + FitTile) to the cell it now stands in and
  each staircase to the new cell edges, PlotX / PlotZ / Yaw re-stamped; (2) `RefreshGrass` hides every grass
  tile whose cell a ground floor tile covers by more than 0.25 studs (footprint overlap, not a centre match);
  (3) a hidden tile is not just transparent: its Texture goes to 1 (a Texture renders whatever the part's
  transparency), collisions off, and it SINKS 1 stud into the slab (`HIDE_DROP`), so nothing of it can z-fight
  the floor from any angle; a `Hidden` attribute keeps the work idempotent.
- **Hover.** The client's `HoverGrass` now hides the hovered tile's Texture too (`SetGrassHidden`) and only
  brings it back when the server still shows the tile - a tile the server hid under a placed floor keeps its
  texture off when the ghost moves on.

Verified in a solo playtest (level-0 plot, 48 tiles): all 48 textured at studs-per-tile = cell size, one colour,
Studs top; two saved floor tiles restored with their grass hidden (texture 1, sunk to y -0.81 vs 0.19, no
collision) and 0 visible grass overlapping their footprints; `PlotUpgradeDev` to level 1 regridded to 56 tiles
of 7.71 x 8.00 and both floors re-fitted to 7.71 x 8.00 on their new cells (0.000 off, tops still at the
surface, 2 hidden, 0 overlapping), back to level 0 the same; hover A -> A hidden (modifier 1, texture 1), hover B
-> A back (0.80) B hidden, place at B -> server hides B (transparency 1, texture 1, sunk), cancel -> B stays
hidden, sell -> B back (texture 0.80, y 0.19). Screenshot (official MCP capture): the plot reads as the
original checker + studs with the wood tile clean in the middle. NOT saved / published.

Note: the user was testing in Studio at the same time (playtests ended under me several times); the admin
tests earlier had reset THEIR profile (coins / strength / plot level) - coins and strength were put back to the
session-start values (883,000 / 1e15) through the panel, the plot level stays at 0.

## Zombie night raid, bat, working defences (2026-09-10, user: "when it hits night, a cutscene points at the zombie door, zombies come out, teleport to right outside your base, go after your cucumbers; 3 stolen = 'The zombies win.'; bat in StarterPack; turret + traps functional; harder varieties from how good the cucumbers are")

Sources: `zombie-raid/` (install through `pets-remake/serve.ps1 -Port 8771 -Root new-map-cucumber-game/zombie-raid` + `install.lua` in one edit-mode execute_luau).

### Pieces
- `ReplicatedStorage.Modules.ZombieCatalog` (ZombieCatalog.lua): 12 varieties over 3 rigs (Shambler / Runner / Brute x 4 tiers each: Rotten Shambler L1 60 HP 8 st/s ... Titan Brute L10 900 HP scale 1.7), each with MinLevel / Health / Speed / Scale / Skin / Cloth / Glow colours. THREAT: every placed cucumber = biomeIndex^1.6 x (1 + 0.6 per mutation) x material (Golden 1.5 / Diamond 2.2) x size (HUGE 1.3 / MASSIVE 1.7 / COLOSSAL 2.2), plus 4 x log10(1 + Coins/s); level = 1 + floor(3.2 x log10(1 + score / 2)) capped at MAX_LEVEL 10 (three Spawn cucumbers = level 1-2, eight Desert/Samurai ~ 5, a dozen Narmek/Neon = the cap). WAVE: round(2 + 0.7 x level) zombies (3..9) drawn from every variety with MinLevel <= level, weighted toward the hardest (Weight x (1 + 2 x MinLevel / level)); the single hardest unlocked variety is always in. STEAL_LIMIT 3. BUILD_HEALTH = what zombies must bash through (WoodenWall 120, StoneWall 300, IronWall 600, BarbedStoneWall 900 and it bites back 8 per swing, default 150).
- `ServerStorage.Assets.Zombies/{Shambler,Runner,Brute}` (build_zombies.lua, run once, idempotent): `Players:CreateHumanoidModelFromDescription` R15 block bodies; in edit mode they arrive with AnimationConstraints instead of Motor6Ds, so the 15 Motor6Ds are built from the `*RigAttachment` pairs (C0 = parent attachment CFrame, C1 = child attachment CFrame, parented to the child part); Animate / BodyColors / FaceControls / HumanoidDescription stripped. Dressed with welded Parts carrying a `Role` attribute (Skin / Cloth / Glow / Bone / Dark / Metal) so a variety retints the rig: Shambler = one neon eye + empty socket, hanging jaw, teeth, three ribs through a gash, waist rags, lolling head (Neck C0 tilt); Runner = twin eyes under a furrowed brow, fangs, four-spike neon mohawk, three claws per hand, spine spikes; Brute = horns, heavy brow, tooth row, stone shoulder pads with spikes, bloated belly, three glowing chest cracks, a chain. `Model:ScaleTo` DOES scale HipHeight (measured; folder attribute ScaleToScalesHip).
- `ServerScriptService.ZombieRaidService` (ZombieRaidService.server.lua): watches `workspace.CyclePhase`. NIGHT -> one raid per player with a plot (NewRaid: threat -> level, wave, Limit = min(3, cucumbers placed at that moment); plot attrs ThreatLevel / RaidAlive / RaidStolen / RaidLimit / RaidOver). Every zombie is spawned in a 6-wide grid around the den ring (Map.Lobby.Stations."Zombie Den ".Circle Light, x 1158+) 7 studs underground with the root anchored, `Remotes.ZombieRaid {Kind="Cutscene", Focus, Seconds 6.5, Rise 1.4}` goes to all clients, dirt bursts + "Rock Crumble", a server TweenService tween lifts the roots over 1.4 s, then Unanchor (velocities zeroed, SetNetworkOwner nil, ChangeState Running) and MoveTo 12 studs east; at 6.5 s each raid's zombies are set down on a line BASE_OFFSET 20 studs in front of the plot's front edge (4 studs apart, facing +X), "CutsceneEnd" + "RaidStart {Level, Count, Limit, Cucumbers}". RAID tick (0.1 s, Heartbeat): WalkSpeed = variety speed x 0.85 while carrying x 0.45 while slowed, 0 while stunned; Seek = nearest tagged PlacedCucumber of the owner (+8 studs per other zombie already targeting it), PathfindingService path (AgentRadius 2 + 2 per scale above 1, no jumping, repath every 2 s or when the goal moves 2+ studs, waypoints at 3 studs), straight line when there is no path; within GRAB_RANGE 4 (+ half the hitbox) -> Grab: tag "PlacedCucumber" removed (income stops, card disappears), parts un-anchored / massless / no collide, WeldConstraints to the primary where missing, a `CarryWeld` puts the PlotHitbox upright above the UpperTorso (C0 = up x (hitbox^-1 x primary)), model re-parented into the zombie, "Grabbed" to the owner; Carry = straight west; 16 studs beyond the front edge = Escape: model destroyed, Stolen += 1, "Stolen {Name, Stolen, Limit}", the zombie sinks away; Stolen >= Limit -> "ZombiesWin" and the rest sink away. Stuck (< 0.6 studs in 1.6 s) -> Bash: a ray toward the move target through plot.Placed finds a PlacedBuild (not a floor / staircase): Health attr -= 25 per 1 s, "Big Thud", at 0 the build is destroyed ("BuildDestroyed" to the owner, "Rock Crumble", dust); no obstacle -> jump. No cucumbers -> Wander the plot. Kill (ZombieAPI.Damage -> Health 0, or Humanoid.Died): a carried cucumber goes back EXACTLY where it stood (anchoring / collision / query / massless restored per part, tag back, "Saved"), "Wet Crunch", glow poof, fade + sink 1.1 s. Every zombie gone (killed or escaped) -> "Survived {Stolen}". Day -> EndAll("Dawn"): carried cucumbers restored, zombies burn away (orange poof + fade), "Dawn" to owners whose raid was still on. Owner leaves -> raid ends, zombies deleted. Zombies never enter FallingDown / Ragdoll / Swimming (SetStateEnabled false) - with the root anchored for the rise the Humanoid sat in FallingDown and stayed there ~3 s after release, so the big ones toppled (measured).
- `ServerStorage.ZombieAPI` (BindableFunctions): Damage(model, amount, source) -> ok, healthLeft (red flash 0.1 s on every part, "Hit Crunch" rate-limited 0.08 s, "Bat" also stuns 0.3 s); Zombies() -> live models; IsZombie(model); Slow(model, seconds); Stun(model, seconds). Zombies: workspace.Zombies, tag Zombie, attrs Variety / Owner / State (Seek | Carry | Wander) / Dead, collision group "Zombies" (pass through each other), ModelStreamingMode Persistent, animations = the Roblox zombie pack (walk 616168032, run 616163682 for speed >= 14, idles 616158929 / 616160636; walk AdjustSpeed = speed / 11 or / 16), stud-sized name + health BillboardGui on the head (6 x 1.5 studs, MaxDistance 140).
- `ServerScriptService.DefenceService` (DefenceService.server.lua): registers every PlacedBuild whose BuildKey is Turret / SpikeTrap / Catapult (tag added / removed signals + a CFrame watcher on the Hitbox that carries the rig origin along when a build is moved). Turret: origin = BasePlinth position + the Hitbox rotation; Head* parts yaw about it, Barrel* pitch about the HeadTrunnion (Rel = origin-space CFrames captured at registration; pose = origin x Ry(yaw) [x T x Rx(pitch) x T^-1] x Rel); nearest zombie within 45 studs, turn 540 deg/s, fire every 0.45 s once within 8 deg: 0.14-stud neon tracer + PointLight from the alternating muzzle of BarrelMuzzleGlow, "Zap", 12 damage; rests after 2 s without a target. SpikeTrap: every part but the BasePlate stops colliding (the kerb + pit + spikes read as a ladder: a zombie went into Climbing on the kerb), any zombie inside the 8 x 8 plate takes 7 every 0.4 s and is slowed 0.6 s. Catapult: origin from the Wheels part (authored centre (0, 0.96, -0.275)), Arm* parts swing about ArmPivot (0, 2.30, 1.30) to -92 deg in 0.12 s, a Slate boulder flies a parabola from the ArmBucket to the target's predicted position in 1.3 s (arc 14 + 0.12 per stud), lands with 45 splash damage falling to half at 9 studs, dust + "Rock Crumble" + "Big Thud", arm resets over 1 s, every 4.5 s, range 8..60. BoostPad has no behaviour.
- `StarterPack.Bat` (build_bat.lua + BatServer.server.lua): part-built bat (cylinders along the Handle's local X: barrel, taper, black tape, knob, red stripes) held with the sword grip turned onto that axis (`Grip = fromMatrix((-1.35, 0, 0), (0, 1, 0), (1, 0, 0))`), CanBeDropped false. BatServer: Tool.Activated (server side) -> a "toolanim" = "Slash" StringValue (the default Animate script plays the R15 tool slash and eats the value), "Air Slice", and 0.18 s later every live zombie within 8 studs (+ extra for wide roots) and 65 deg of the character's facing takes 35 through ZombieAPI.Damage; one swing per 0.55 s. The Bat shows in the custom hotbar (slot 1, text "Bat" - no TextureId).
- `StarterPlayerScripts.ZombieRaidClient` (ZombieRaidClient.client.lua): Cutscene = fade to black 0.25 s, Scriptable camera on the den focus from offset (27, 12, -14) to (17, 5.5, 9) over Seconds (smoothstep), FOV 62 -> 54, a decaying shake during the rise, "Drama Sting" + Notify.Warn("THE ZOMBIES ARE COMING!"); CutsceneEnd (or a Seconds + 1.5 watchdog) fades, restores Custom camera + subject, fades in. Heartbeat-stepped (runs with Studio unfocused). Messages through RS.Modules.Notify: RaidStart "Zombie raid! Threat level N - K zombies want your cucumbers" (+ "Alarm Bell"; no cucumbers: "... no cucumbers to steal, smash them!"), Grabbed "A <variety> grabbed your <name>!", Stolen "The zombies stole your <name>! (n/limit)", Saved "You saved your <name>!", BuildDestroyed "The zombies smashed your <build>!", ZombiesWin "The zombies win." (+ "Sad Trombone"), Survived "You survived the night!" / "The raid is over! You lost N cucumbers." (+ "Victory Sting"), Dawn "Dawn! The zombies burn away.".
- `DayNightCycle.NightDurationSeconds` 10 -> 90 (attribute on the script) so a raid has time to play out; the day is still 180 s (270 s cycle, renumbered days).

### Studio hooks
`workspace:SetAttribute("ZombieDev", ...)` (edge-triggered, cleared after it runs): `raid` / `raid:<level>` (ends whatever is running, then a full cutscene raid for every player with a plot at that level), `cutscene` (camera only), `end` (dawn for everyone), `kill` (every zombie dies), `spawn:<Variety Name>` (one zombie 10 studs in front of player 1, in that player's raid - a finished raid is re-opened). Fixtures for tests: clone `ServerStorage.Assets.BreakableModels` children into `plot.Placed` with a PlotHitbox + the placed-cucumber attributes + tag (LeaderstatsService stamps Rate), and `ReplicatedStorage.PlaceableBuilds/<Category>/<Key>` clones with Owner / BuildKey + tag PlacedBuild (see the session transcript for the exact snippet). Two SetAttribute writes on the hook in one frame collapse into one (deferred signals) - `task.wait` between them.

### Verified (solo playtest 2026-09-10, awesomeotheraccount on Plot 1)
- Cutscene: camera on the den, warning text, all six zombies (two Iron Brutes, Bloated Brute, Plague / Rotten Shambler, Feral Runner) upright and Running through the rise (sampled every 0.5 s: up 1.00, states Running, x 1158 -> 1171 walking out, x 1197 after the teleport, then marching in at 13 / 7 studs/s).
- Undefended plot with 3 cucumbers, level 5 (6 zombies): grabs at +10 s ("A Feral Runner grabbed your Underwater Bubble Slice!"), steals at +16 / +21 / +23 s, "the zombies win" logged + the client message.
- Defended plot (Turret + SpikeTrap + Catapult fixtures, 5 cucumbers, level 4-6): the turret killed most of the wave, runners still got 1-2 through; "survived (level 6, stolen 1/3)".
- Bat: 110 -> 75 -> 40 on a stunned Plague Shambler (two swings, 35 each), a Rotten Shambler killed by two swings ("survived" logged), the bat stands upright in the fist like a sword.
- SpikeTrap alone: 7 HP every 0.4 s until dead; Catapult alone: boulder at +0.3 s, hits at +1.3 s (30-39 damage with the falloff), next shot at +4.4 s, arm swing seen on ArmBeam.Position.Y; wall bashing: an Iron Brute boxed in by four WoodenWalls bashed the one between it and the cucumbers 120 -> 95 -> 70 -> 45 -> 20 -> destroyed in 6 s, then walked through.
- Dawn: EndAll clears raids and zombies; a later `raid` hook works again from Idle.
- Fixed on the way: the last zombie leaving by ESCAPE never checked the raid end (Survived only fired on kills; a later kill in the same raid then reported it) -> Escape calls CheckRaidEnd; the trap kerb put zombies into Climbing -> only the BasePlate collides; runner speeds 15/17/19/21 -> 13/15/17/19 and BASE_OFFSET 14 -> 20 so an undefended base gets a few more seconds.
NOT saved / published by me. Not done: no coin rewards for kills, no HUD counter for the raid (the plot attributes RaidAlive / RaidStolen are there for one), zombies ignore players (they only want cucumbers), placed builds are still not persisted (BuildService), Pets / eggs on the plot are ignored by zombies.

### The door (2026-09-11, user: "make it so zombies come out of this door, the cutscene is from here, and when stealing they walk back to this door")
The user built a ZOMBIE NIGHT sign + green arch (a UnionOperation with a Warning decal above it) onto the lobby face of `Map.Borders.NightBarrier` - the wall DayNightCycle raises across the lobby entrance at night. ZombieRaidService now reads the door from the arch (`DoorArch()`: the barrier's UnionOperation, else the part holding the Warning decal, else the old Zombie Den) - `DoorPoint()` = arch face + DOOR_OUT 1.8 studs into the lobby at the arch's Z (x 1150.85, z 130.37, ground from a raycast, cached 1 s, stamped as the barrier attribute DoorPoint). Only the wall's Y changes as it rises, so the door is the lobby entrance whether it is up (night) or under the floor (a daytime dev raid).
- CUTSCENE: no more rising from the ground. Rows of DOOR_COLUMNS 4 zombies (3 studs apart across the arch, rows 2.8 studs deep) step out of the arch, the first after DOOR_FIRST 1.2 s (the wall takes ~1 s to rise), then one row every DOOR_ROW_GAP 0.5 s (squeezed to fit the 6.5 s cutscene when there are many), each row with a green poof + "Thunder" (first) / "Whoosh", and they shamble WALK_OUT 14 studs into the lobby until the teleport to the bases. Client camera: focus = the door ground point, from (40, 16, -12) looking 12 studs up the wall (the sign) to (21, 7, 9) looking 5 up (the doorway), shake while the first rows step out.
- CARRY: a carrier paths back across the lobby to DoorPoint (Plot 1 -> door is ~180 studs, 20-25 s at 8-13 studs/s x 0.85 - time to chase it with the bat) and is gone within DOOR_REACH 5 studs of it (poof at the door). ESCAPE_MARGIN / the rise tween / DenPoint are gone.
- Verified in a solo playtest: dev raid by day - 4 zombies at x 1153-1154 z 126-135 at 1.5 s, walked out to x 1163, teleported to the base at 6.6 s, grabbed at 11-14 s, the runners walked (1252,-45) -> (1153,126) in ~20 s and vanished there (stolen 1-2/3), the shambler followed; natural night - wall up, sign + arch + four zombies stepping out in the cutscene frame. NOT saved / published by me.

### Night 45 s, no raid without cucumbers, dawn verdict, daytime thieves, stacked notifications (2026-09-11, user)
- `DayNightCycle.NightDurationSeconds` 90 -> 45. A raid from the door can barely land three steals in 45 s from a far plot, so most nights now end at dawn.
- NO CUCUMBERS = NO RAID: `StartRaids` only raids players with at least one placed cucumber (`raid.Cucumbers > 0`); if nobody has any there is no cutscene either ("[ZombieRaid] night: nobody has cucumbers placed, no raid").
- DAWN VERDICT (`EndRaid` reason "Dawn"): nothing stolen -> Kind "Survived" ("You survived the night!" = the player WON the night); some stolen -> Kind "Dawn" with Stolen ("The night is over. You lost N cucumbers."). Both burn the leftovers and return carried cucumbers. Log: "dawn for <name>: stolen a/b -> won the night | night over".
- DAYTIME THIEVES: a scheduler thread fires every DAY_THIEF_MIN..MAX (50..100) seconds of daylight (first DAY_THIEF_GRACE 25 s after dawn, and only while no night raid is running), picks a random player who has cucumbers placed and no live thief, and `SpawnThief` puts ONE low-tier zombie (THIEF_POOL by threat level: Rotten Shambler; +Scrawny Runner from level 2; +Plague Shambler from 4; +Feral Runner from 7) at the door with a poof + "Whoosh". It WALKS to that base (no teleport - you can see it coming and meet it with the bat / it runs the turret gauntlet), steals one cucumber the usual way and walks it back to the door ("ThiefStole": "A thief got away with your X!"); killed carriers still return the cucumber ("Saved"); with nothing left to steal it walks back and leaves (state "Leave"). Thieves live in `DayRaids[player]` (raid.Day = true: Limit huge, no win / lose, no plot attributes, one per player at a time); night falling ends them (`EndDayRaids("Night")` inside StartRaids), the owner leaving too. Owner message on spawn: Kind "Thief" -> "A <variety> is sneaking toward your base!". Dev hook `ZombieDev = "thief"`.
- The tick loop no longer waits for Phase "Raid": every entry in Raids + DayRaids ticks unless `entry.Hold` (set while a night wave stands at the door during the cutscene, cleared at the base).
- NOTIFY STACK (`RS.Modules.Notify`, mirror Notify.lua): up to MAX_STACK 3 messages at once - the newest at POSITION (66 % down), older ones pushed up by their rendered height (TextBounds, the cap as the floor) + STACK_GAP 1.2 % of the screen; a fourth throws the oldest out; each message keeps its own hold, fades, and the rest slide back over SHIFT_TIME 0.12 s. API unchanged (Show / Error / Warn / Success / Info); `Notify.Labels()` lists the live labels. Measured in the playtest: three rows at y 345 / 291 / 238 (46 px text, 54 px pitch), the fourth evicted the first, the stack closed up after a fade.
- Verified (solo playtest): dev raid with 0 cucumbers -> no zombies + the log line; a dev thief walked door -> Plot 3 (14 s), grabbed, walked back (28 s) -> "A thief got away with your Underwater Bubble Slice!"; the natural night (cutscene at the arch, 3 zombies, all stunned by a test hook so nothing could be stolen) ended 45 s later with "You survived the night!" and the "won the night" log.

### Night teleport home, Build prompt on the plot board, build-mode barrier + leave dialog (2026-09-11, user)
- NIGHT TELEPORT (`ZombieRaidService.SendHome`): when the night raid starts every raided player is stood at the front of their own plot (`plot.PlotSpawn` + 2.6 up, seats released, velocity zeroed) 0.5 s into the cutscene (after DayNightCycle's own lane returns) and again at the deploy if they are not at the base (`AtBase`, plot + 6 studs). The wave itself is set down BASE_OFFSET = 20 studs in front of the plot's front edge (unchanged).
- BUILD PROMPT (`build-mode/BuildPromptServer.server.lua` -> SSS.BuildPromptServer): a Custom-style ProximityPrompt ("Your base" / "Build", E, 12 studs, no line of sight) on an Attachment 1.4 studs above the Panel of every PlotUpgradeBoard-tagged board copy (PlotUpgradeService stands one per plot; attribute Plot), tag BuildPrompt. Trigger as the owner -> the character is stood INSIDE the base (10 studs in from the front edge, facing in, unseated) and `Remotes.BuildModeEnter {Kind = "Enter", Plot}` goes to that client; anyone else gets `{Kind = "Refused", Reason = "That's not your base"}` (Notify). CucumberPromptClient draws it like the collect prompt.
- BARRIER + DIALOG (`build-mode/BuildBarrierClient.client.lua` -> StarterPlayerScripts.BuildBarrierClient): on `BuildModeEnter` it waits up to 3 s for the HUD attribute BaseMode (BaseHUDController) and fires the BuildMenu hook `BuildDev = "enter"`. While the HUD attribute BuildMode is true it rings the player's plot with four client-only invisible walls (40 tall, 2 thick, 0.5 outside the edge, CanCollide on, CanQuery off so placement rays and the camera ignore them; rebuilt when the plot resizes); bumping one (Touched by the local character, 1.5 s gap) opens the leave dialog; BuildMode false removes walls + dialog. Every BuildPrompt is enabled locally only on the player's own board. Dev hook: `PlayerGui.BuildLeaveConfirm` attribute `LeaveDev = touch | exit | stay`.
- THE DIALOG (`build-mode/build_leave_frame.lua` -> StarterGui.BuildLeaveConfirm.Leave): the Zombie Cucumber Game's "Unlock" door frame (`StarterGui.Display.Frame.Frames.Door`, exported to `build-mode/UnlockFrame.rbxm`; the install copies it into Studio's `content\` folder and loads it with `game:GetObjects("rbxasset://UnlockFrame.rbxm")`) - beige studded panel with the triple orange outline, orange gradient heading, X close - restyled: heading "Leave?", body "Are you sure you want to <red>leave</red> build mode?", the one green Purchase button cloned into a red Exit (left, gradient 255,112,100 -> 206,40,40) and a green Stay (right, 132,240,102 -> 52,176,56), 300 x 103 px each at y 450. Exit -> `BuildDev = "exit"`; Stay and the X close it. Authored 756 x 550 px; the client's UIScale fits it to 78 % of the viewport height (one UIScale only - two never stack) and pops it 0.8 -> 1 on show.

### Fixes after the user's first try (2026-09-11, later): "Label" on the prompt, leave through the prompt, spawn on the plot, no dialog, faint walls
- "Label": the live `CucumberPromptClient` (newer than the mirror was - another session added a third "NextTier" strength row) left that row at its default text "Label" for any prompt whose holder has no StrengthRequired. Patched in place: the row starts empty and the non-cucumber branch clears it (+ resets the action colour). Mirror refreshed from the live source through receive.ps1 (the mirror is now the live 305-line version).
- LEAVE THROUGH THE PROMPT: `BuildBarrierClient` reports its build state to the server on the same remote (`BuildModeEnter:FireServer(true|false)` on the HUD's BuildMode change; `BuildPromptServer.Building[player]`) and relabels its own board's prompt locally ("Build" <-> "Leave build mode"). Triggering while building -> the server answers `{Kind = "Leave"}` (no teleport) and the client fires the BuildMenu "exit" hook.
- SPAWN ON JOIN: new `SSS.SpawnAtBaseServer` (mirror SpawnAtBaseServer.server.lua): for 4 s after every spawn (once the player has the Plot attribute) a character standing outside its plot (+ 6 studs) is stood on the plot's PlotSpawn. The first spawn of the test session was indeed off the plot ("stood on Plot 2 (0.0s after spawning)"), so the guard earns its keep.
- NO DIALOG, FAINT WALLS: the leave-confirm frame is gone (StarterGui.BuildLeaveConfirm deleted, build_leave_frame.lua + UnlockFrame.rbxm removed, no Touched logic); the fence walls are now Transparency 0.8, pale green (150, 255, 170), SmoothPlastic, still client-only / collidable / CanQuery off.
- Verified (solo playtest): 6 prompts (one per board), only the player's own enabled; trigger -> teleported 10 studs inside (root x 1226.85 on a front edge of 1216.85), BuildMode true, prompt reads "Leave build mode", four 0.8-transparent walls (2 x 40 x 90 / 75 x 40 x 2 around the 70 x 85 plot); trigger again -> BuildMode false, walls gone. Night teleport: character parked at the lobby entrance, `raid:2` -> at the PlotSpawn (1219.85, 22.09) within 1 s and still there at the deploy.

### Three new zombie kinds (2026-09-11, user: shadow / one-hit sprinters / grapple hook)
Six varieties in `ZombieCatalog` (18 total), two tiers of each kind, flagged on the variety table:
- SHADOW (`Shadow = true`): Shadow Stalker (L4, 90 HP, 11 st/s, purple glow) and Void Wraith (L8, 200 HP, 12, magenta). `ZombieRaidService.SetShade`: solid for SHADOW_VISIBLE 2.5 s, then every BasePart at SHADOW_TRANSPARENCY 0.7 (name tag and bar at 0.6) for SHADOW_HIDDEN 5 s, and so on (a small glow poof on each switch; model attribute Shaded). While shaded the zombie is LEFT OUT of `ZombieAPI.Zombies()` - the turret, spike trap, catapult and the bat all read that list, so none of them see it - and `ZombieAPI.Damage` refuses (returns false). Carrying a cucumber forces it solid, so the way to stop one is to hit it on the way out (or catch a visible window).
- ONE-HIT SPRINTERS (`Health = 1`): Blitz Runner (L3, 26 st/s, scale 0.8, yellow) and Lightning Runner (L8, 32 st/s, white / cyan). Nothing special in code: one trap tick, one tracer or one bat swing kills them, but they cross a plot in a few seconds.
- GRAPPLE (`Grapple = true`, `GrappleRange`): Hook Lurker (L5, 120 HP, 12 st/s, reach 24, Runner rig) and Chain Reaper (L9, 300 HP, 13 st/s, reach 32, Brute rig). `StartGrapple`: within GrappleRange of its target it stops (StunUntil covers the whole grapple), turns to face it, a rope Beam runs from its RightHand to the cucumber's primary part ("Whoosh", owner told Kind "Grappled": "A Hook Lurker hooked your X!"), after GRAPPLE_HOOK 0.25 s the cucumber slides to 2.5 studs in front of it over GRAPPLE_PULL 0.6 s (PivotTo lerp, "Metal Heavy"), then the usual Grab - with the cucumber's ORIGINAL pivot passed as the rest pose, so killing the carrier still returns it to where it stood - and it runs off at GRAPPLE_CARRY_SPEED 1.15 x its speed (other carriers slow to 0.85). If the zombie dies or the cucumber is taken by someone else mid-pull, the cucumber is put back.

### Digger + Splitter (2026-09-11, user: "make digger, splitter")
- DIGGER (`Digger = true`): Mole Digger (L4, 100 HP, 9 st/s, earth brown) and Tunnel Fiend (L8, 220 HP, 11). `StartDig`: with a target at least DIG_RANGE_MIN 12 studs away (i.e. straight from the drop line) it stops, a mound puff + "Dirt Dig", root anchored, sinks DIG_DEPTH 6 studs over DIG_DIVE 0.6 s, travels underground at DIG_SPEED 18 st/s in a straight line (mound puffs on the surface every 0.45 s so you can see it coming) to a point one stud inside grab reach of the cucumber on the side it came from, rises over 0.6 s facing it, and grabs on the next tick. Underground it is out of `ZombieAPI.Zombies()` and `Damage` refuses (model attribute Underground) - walls, the spike line and the turret are all passed under. One dig per DIG_COOLDOWN 8 s; it walks the cucumber back on foot like everyone else.
- SPLITTER (`Split = {Variety, Count}`): Bloated Splitter (L5, 240 HP, 6.5 st/s, scale 1.35) bursts into 3 Spawnlings (Runner rig at 0.6, 20 HP, 18 st/s) and Gorged Splitter (L9, 450 HP, 7, scale 1.5) into 3 Gorelings (0.65, 35 HP, 20). In `Kill`, right after the parent leaves the count and BEFORE the raid-end check, the children are spawned in a ring 2.4 studs around it (same raid, Alive += 1 each, they inherit the parent's target), glow poof, owner told Kind "Split" ("The Bloated Splitter burst into 3 Spawnlings!"). The parent's carried cucumber is returned first, so the children go for it again. Spawnling / Goreling have MinLevel 99 + Weight 0, so a wave never rolls them directly.
- Client kinds added: "Digging" ("A Mole Digger is burrowing toward your cucumbers!"), "Split".

## 2026-09-12 Zombie hostility (hit them and they hit back when you are in their way)

User: "when u start hitting zombies, zombies turn hostile towards you. they do NOT chase after you or
follow you, but if you are in their way they hit you which knocks you back 10 studs."

- **Trigger** (`zombie-raid/BatServer.server.lua` + `ZombieRaidService.server.lua`): the bat now passes the
  swinging Player as a 4th argument to `ZombieAPI.Damage(model, amount, source, attacker)`. The first hit a
  player lands on any zombie of a raid puts them in `raid.Hostile[player]` (checked BEFORE the kill so a
  one-hit sprinter counts), every zombie of that raid gets a red name tag (`HOSTILE_COLOR`, later spawns
  and split children too), the player is told `{Kind = "Hostile"}` -> "The zombies turned on you! Stay
  out of their way." Turret / trap / catapult damage never triggers it (no attacker).
- **The swing** (`InTheWay` / `Swat`, called from `Tick` right after the grapple / dig early-out, so it
  runs whatever the zombie is doing - seeking, carrying, wandering, leaving): a hostile player whose root
  is within `HIT_RANGE` 4.5 studs (x max(1, 0.85 x scale)) and inside the front `HIT_CONE` (cos 60 deg)
  of the zombie's LookVector, within 6 studs vertically. The zombie stops for `HIT_PAUSE` 0.5 s (via
  `StunUntil`, which `Tick` reads as WalkSpeed 0), turns to face them, plays `ANIMATIONS.Swing` (the
  R15 tool slash 522635514, Action priority) with "Air Slice"; `SWING_DELAY` 0.2 s later, if they are
  still within reach + 2, `HIT_DAMAGE` 10 off their Humanoid, "Hit Crunch", and `{Kind = "Hit",
  Direction, Distance = 10, Seconds = 0.35}` to that player. One swing per `HIT_COOLDOWN` 1.4 s per
  zombie. The zombie's goal never changes for a player (no chasing) - it resumes its path after the pause.
  Shaded shadows and diggers underground never swing.
- **The knockback** (`ZombieRaidClient.client.lua` `knockback`): the character's physics is client-owned,
  so the shove runs on the hit player's client: a `LinearVelocity` (World, Vector mode, MaxForce inf) on
  the root drives a real parabola - along speed D/T, up speed g*T/2 - g*t - updated per Heartbeat for
  `Seconds`, then it is destroyed and the velocity zeroed (`KNOCKBACK_TIME` 0.35 s: peak g*T^2/8 = 3
  studs, a shove rather than a launch; 0.45 s measured 6 studs up). Toast "A <zombie> knocked you back!".
- **Verified** (playtest 2026-09-12 via the official Roblox_Studio MCP, chrrxs runtime peer blocked by
  the 3.1.4 / 3.1.3 plugin mismatch): dev-spawned Rotten Shambler, `Damage(z, 5, "Bat", player)` ->
  name tag (0.75,1,0.35) -> (1,0.32,0.32), server print "hostile to them now", client toast shown.
  Character pivoted 3 studs in front of it: health 100 -> 90 at 0.3 s, distance 2.1 -> 11.2 studs by
  0.8 s, client saw the ZombieKnockback constraint, 10.9 studs flat / 3.9 peak, toast "A Rotten
  Shambler knocked you back!", the zombie carried on wandering (no chase). No server warnings.
- **Gotcha**: the official MCP's Client `execute_luau` runs in its own VM with its own require cache -
  `require(Notify).Labels()` there sees a SECOND GameNotify copy, not the game's toasts; read the game's
  `PlayerGui.GameNotify` TextLabels directly instead.

## 2026-09-12 Build durability: bashed builds break, mend by day, are never destroyed

User: "make it so zombies deal damage to builds like walls, defenses, decoration etc. each defense has a
healthbar when damaged but they always heal throughout the daytime and never take longer than the daytime
to heal back fully. by next night all defenses are at 100% again. and make it so defenses are never fully
destroyed / irreperaable since my wall was completely got rid of forever at one point by a zombie. do not
make it so they go out of their way to destroy stuff, only stuff in their path."

- **New `build-mode/BuildHealthService.server.lua`** (-> `ServerScriptService.BuildHealthService`, pushed
  from its own loopback server: serve.ps1 serves one folder, no subpaths). Every `PlacedBuild` except
  floors / stairs gets `Health` / `MaxHealth` attributes (`ZombieCatalog.BuildHealth(BuildKey)`: WoodenWall
  120, StoneWall 300, IronWall 600, BarbedStoneWall 900, Turret 400, Catapult 300, everything else 150)
  and a stud-sized `BuildHealthTag` BillboardGui over its Hitbox (name + bar, 5 x 1.5 studs, 0.6 above the
  top, green / amber / red like the zombie bar) that is only Enabled while Health < MaxHealth.
  `ServerStorage.BuildAPI`: `Damage(model, amount, source) -> health, broken`, `IsBroken(model)`,
  `Heal(model | nil)`.
- **Broken, never destroyed**: at 0 the model stays; attribute `Broken = true`, every part but the Hitbox
  fades to 0.65 (originals remembered per part) and stops colliding, so zombies AND players walk through;
  dust + "Rock Crumble"; further damage is refused; the tag reads "<name> (broken)". `DefenceService`
  skips any model with `Broken == true` (no tracking, no fire, no spikes).
- **Healing**: every 1 s while `CyclePhase == "Day"` a damaged build gains MaxHealth x dt / HealSeconds,
  HealSeconds = 0.8 x DayDurationSeconds (DayNightCycle attribute; 180 -> 144 s, so 0 -> full inside one
  day). A broken build mends (originals restored, sparkle + "Magic Shimmer") at 35 % of its health. When
  `CyclePhase` flips to Night everything is set to 100 % and mended regardless (the guarantee); nothing
  heals at night. Dev hook `workspace.BuildHealthDev = "damage:<n>" | "break" | "heal"` (all builds).
- **ZombieRaidService.Bash** keeps its trigger (a zombie stuck for STUCK_SECONDS against whatever is in
  front of it - never a detour) but the raycast now only includes builds that still stand, and the damage
  goes through `BuildAPI.Damage` (25 per swing as before). On break: `{Kind = "BuildBroken", Name}` ->
  "The zombies broke your <name>! It mends by morning." (`BuildDestroyed` is gone); barbed walls still
  hurt the basher.
- **Verified** (playtest 2026-09-12, official Roblox_Studio MCP): WoodenWall 120 -> 70 after `Damage 50`
  (bar Enabled, fill 0.58) -> 0 after 70 more (Broken, 3 parts at 0.65 / CanCollide off, model still
  there, further damage refused) -> Health set to 41.5 + one day tick = 42.3 -> mended (parts solid, bar
  still showing, "(broken)" gone). Turret 400 -> 0 = Broken, 22 parts non-colliding. CyclePhase flipped
  to Night: wall + turret back to 120 / 400, bars hidden, "night: 2 build(s) restored". Real zombie: a
  cucumber ringed by four WoodenWalls, a Rotten Shambler stuck at the ring bashed 99 -> 75 -> 51 -> 26 ->
  2 -> 0 over 8.7 s, "Wooden Wall broke (Zombie)", then walked on through. No warnings. (The first
  attempt was cut short by a real dawn burning the zombie away - the shared real-time clock had rolled
  into night; check `CyclePhase` before a long server-side test.)

## 2026-09-12 Knockback only, thieves clear of nightfall, no building at night, catalog at the top

User: "1. dont let zombies damage player (only knockback) 2. make daytime zombies not spawn within 20s of
the night incoming 3. at night make it so users exit build mode and cannot enter build mode 4. put the
pick a build UI at the top of the screen instead of bottom. if its making the other build option buttons
hidden, dont let them hide."

1. `ZombieRaidService` `HIT_DAMAGE = 0`: a hostile zombie's swing only shoves (the `TakeDamage` call is
   skipped at 0). Verified: pivoted in front of a hostile Rotten Shambler, health stayed 100 while the
   character flew 1.8 -> 10.1 studs.
2. `DAY_THIEF_NIGHT_GUARD = 20`: the thief scheduler also needs `SecondsToNight() >= 20`, where
   `SecondsToNight` = `workspace.PhaseEndsAt` (DayNightCycle's shared end-of-phase server time) minus
   `workspace:GetServerTimeNow()`. A thief already walking is still cleared when night falls
   (EndDayRaids). Logic-checked (the window is 20 s of a 180 s day; not caught live).
3. Build mode locks at night. `BuildMenuClient.Enter` refuses while `workspace.CyclePhase == "Night"`
   ("You can't build at night"); a `CyclePhase` listener Exits an open build mode the moment night falls
   with "Night! Build mode is closed until morning."; `BuildPromptServer` refuses the board prompt at
   night with the same reason (Leave still works). Verified: `BuildDev = "enter"` during a real night ->
   BuildMode nil + the toast; in build mode by day, CyclePhase flipped to Night -> BuildMode false, all
   panels hidden, the toast at +0.3 s.
4. The Catalog ("pick a build") panel hangs from the TOP: `Fit` sets AnchorPoint (0.5, 0) and puts its top
   `TOP` (12) px under the HUD NightTimer's real bottom edge (`timer.AbsolutePosition.Y + AbsoluteSize.Y`,
   both ScreenGuis share the inset; fallback 5.5 % + 14 px if the timer is missing). `OpenCategory` no
   longer hides the Categories row, so the category buttons, X, Sell and Grid stay on screen under the
   panel and another category is one click away (switching categories from the row works). The Placing
   strip still replaces the row while a build is on the mouse (unchanged). `build_buildmenu.lua` authors
   the same anchor / a 74 px default. Verified on a 1585 x 553 viewport: catalog top y = 68, timer bottom
   56 (gap 12), panel 980 x 170 ending at y 238, Categories row visible at y 492; a first attempt with a
   5.5 %-of-screen guess overlapped the timer by 2 px (the timer is 42 px tall there, not 30), hence the
   real-edge anchor.
- Gotcha: one official-MCP `start_stop_play(true)` started a play session whose DataModel predated the
  chrrxs push (none of the new markers were in the play server's Sources while both edit DataModels had
  them). Stop + start again fixed it; read a marker from the play DM before trusting a test.

## 2026-09-12 Carriers drop the cucumber where they fall; hostility leaves name tags alone

User: "1. when zombie dies/disappears make them drop cucumber on the spot instead of sending cucumber
back 2. dont make nametags change on hostility"

- `ZombieRaidService.RestoreCarry(entry, silent, dropAt)`: with `dropAt` (the carrier's root position)
  the cucumber is stood up as a placed cucumber again at THAT spot - `DropRest` keeps the rest pose's
  rotation and height, and clamps the X / Z inside the plot by half its `RestSize` footprint + 1 stud,
  so a carrier killed on its way across the lobby never strands the cucumber outside the base (placed
  cucumbers cannot be picked up again). Callers: `Kill` (bat / defences: "Saved" now reads "You saved
  your <name>! It dropped where the <zombie> fell."), the ZombiesWin sink, and `EndRaid` for dawn / a
  called-off raid (silent). The owner LEAVING still puts it back where it stood (they are gone; the
  base save records whatever stands in Placed). Escape at the door is unchanged (stolen).
- Hostility no longer recolours the raid's name tags (`HOSTILE_COLOR` and both tint loops removed);
  the "Hostile" toast is the only signal.
- Verified (playtest 2026-09-12): a Scrawny Runner carried a fixture 29.8 studs, a bat hit left its
  tag colour unchanged, the kill put the cucumber back in Placed (tagged) 0.0 studs from where it
  fell, same height; a second carrier that had left the plot (plot-space x -26.2, half 25) was
  despawned by the `end` hook and the cucumber landed at x -22.0 (clamped), 4.2 studs from where it
  stood. Both the first play sessions after a chrrxs push were stale again (stop + start fixed it).

## 2026-09-12 Catalog flush with the top of the screen; a daytime theft closes build mode

User: "make it so pick a build UI goes all the way to the top of screen even covering the daytime
indicator" / "make it so when a cucumber is stolen in daytime, build mode closes".

- `StarterGui.BuildMenu.IgnoreGuiInset = true` (authored in `build_buildmenu.lua` too) and `Fit` puts the
  Catalog at `UDim2.new(0.5, 0, 0, 0)`: the panel's top edge is the real top of the screen (its
  AbsolutePosition.Y reads -58 in inset coordinates) and, with BuildMenu's DisplayOrder 25 over the HUD's
  20, it covers the NightTimer (day / night indicator) while a category is open. The 12 px timer-edge
  anchor from earlier today is gone. Categories / Placing are bottom-anchored, so the inset change does
  not move them.
- `BuildMenuClient` listens on `Remotes.ZombieRaid`: `{Kind = "ThiefStole"}` (a daytime thief got away
  with a cucumber) Exits an open build mode with "Build mode closed." (the ZombieRaidClient's "A thief
  got away with your <name>!" toast stacks with it). The grab moment ("Grabbed") was left alone - the
  user said "stolen".
- Verified (playtest 2026-09-12): catalog abs top y = -58, spanning x 302..1282, the timer's rect
  (685..899, 14..56) fully inside it, Categories still visible; `ThiefStole` fired from the server ->
  BuildMode false, catalog hidden, both toasts. The play DM was current on the first start this time.

## 2026-09-12 Pick-a-build = a bare card strip above the bottom buttons (final); Cancel fix

User: "nevermind. lets put the pick a build UI just above the other build buttons at bottom. and also get
rid of the back button on the pick a build UI. get rid of the 'pick a build' label and get rid of the
category title above the builds. then hide the background. essentially itll just show the builds cards
when clicking a build. also make the builds cards tween up. / clicking cancel when placing build hides the
build buttons at bottom. fix."

- The two earlier top-of-screen placements from today are superseded. `StarterGui.BuildMenu.IgnoreGuiInset`
  is back to false. `Fit` now hides the Catalog's chrome (BackgroundTransparency 1, Fill hidden, Outline
  stroke disabled, Bar with Back / Title / Hint hidden), makes the Row fill the frame, sizes cards to
  20 % of the screen height (96..150 px, 0.8 aspect) and the strip to its cards (n x CardW + 8 px gaps +
  16, capped at 62 % of the width / 980 px - Garden's 23 cards scroll inside 806 px) and anchors it
  (0.5, 1) at `layout.CatalogY = -(BOTTOM + row height + CATALOG_GAP 10)`, i.e. 10 px above the
  Categories row. `build_buildmenu.lua` authors the same hidden state so a rebuilt GUI matches.
- `Rise()` (replaces the panel Pop in `OpenCategory`): the strip starts `RISE` 36 px lower and eases
  up over 0.26 s (ButtonFX.Animate, Quad out, token-guarded like Pop); the first cards still pop in
  with their stagger. Measured y 386 -> 361 -> 354 (settled), strip bottom 10 px above the row.
- BUG FIX: `RestorePanels` (StopPlacing / Cancel) turned the catalog back on but not the Categories row
  (a leftover from when the panel replaced the row), so Cancel left the bottom buttons hidden. It now
  shows both in catalog mode. Verified: pick -> only the Placing strip; cancel -> strip + row back.

## 2026-09-13 Placement grid doubled

User: "build movement grid squares is too tiny. make it slightly bigger. i am talking about the actual
grid to place builds."

- `BuildCatalog.GRID_SIZES` = {2, 1, 0.5} studs (was {1, 0.5, 0.25}): the default snap is now 2 studs,
  the Grid button still cycles finer steps. The server never snaps (BuildService validates the sent
  CFrame), Flooring / Staircase keep snapping to grass cells, so only this table changed (live edit +
  mirror; the BuildMenuClient header comment updated to match).
- Verified (playtest 2026-09-13, after a Studio restart - the whole day's work was still in the place,
  new chrrxs instance:sbg-jhc / official studio 6da540af): `aim:3.3,1.2` put the WoodenWall Preview at
  plot-space (4.00, 2.00); the old grid would have given (3, 1).

## 2026-09-13 Dropped cucumbers stay where the carrier fell; the next zombie carries them on

User: "when zombie dies/disappears make them drop cucumber on the spot instead of sending cucumber
straight back. another zombie can pick up cucumber from there and carry on."

- The 2026-09-12 clamp-into-the-plot is gone. `RestoreCarry(entry, silent, dropAt)` (only `Kill` passes
  dropAt) now stands the cucumber up at the EXACT spot the carrier fell - plot or lobby floor - at its
  usual height over the ground (`GroundY` on the Map only + the rest pose's lift over the plot top),
  keeps it in the plot's Placed holder with the PlacedCucumber tag, and records it in
  `raid.Dropped[model] = {Rest = home pose, Name}`. Every zombie of the raid targets it like any other
  cucumber (`CucumbersOf` reads the holder), so the next one walks out, grabs it and carries on.
- `HomeRest(raid, model)` hands the ORIGINAL home on: `Grab` uses it as `carry.Rest` (and clears the
  Dropped entry), the grapple passes it too, so a second kill drops it again with the same home.
- `ReturnDropped(raid)`: when the raid is over - every zombie dead ("Survived" / a day thief's raid
  closing), the zombies win, `EndRaid` (dawn, called off, owner left) - every cucumber still lying in
  the holder goes back to its home pose, and `ServerStorage.BaseSaveAPI.Snapshot(player)` is invoked
  (the base save keys off tag changes; a pivot alone would ride the 30 s heartbeat). Raid-end
  `RestoreCarry` calls send carried loads straight home (no point dropping them first).
- Edge: if the owner leaves while a cucumber lies in the lobby and BaseSave's leave snapshot runs
  before ZombieRaidService's PlayerRemoving handler, the saved position is the lobby spot.
- Verified (playtest 2026-09-13, first half): fixture carried out to plot-space (28.2, 10.5) by a
  Scrawny Runner, killed -> cucumber in Placed, tagged, 0.0 studs from where it fell, height -223.25
  (lobby floor) vs home -223.02, and a second Runner picked it up 1.8 s later. NOT verified live: the
  second drop while the raid continues and the return home at raid end - a new play session appeared
  mid-test (not started by me) and was left alone. Recipe: place a cucumber, `ZombieDev = "spawn:Scrawny
  Runner"` x3, kill carriers with `ZombieAPI.Damage(z, 9999)`; the last kill prints
  "[ZombieRaid] N dropped cucumber(s) went home on <player>'s plot".

## 2026-09-13 Join spawn no longer fights the player

User: "when first joining and try running out of my base i keep getting tped back into my base. please fix"

- Cause: `SpawnAtBaseServer` (2026-09-11) re-checked the character every 0.25 s for WATCH_SECONDS 4 s
  counted from the moment the plot attribute appeared (not from the spawn), and stood any off-plot
  character back on PlotSpawn each time - so a player who had already run out kept being shoved back.
- Fix: `Settle` waits for the plot, gives up if it arrived more than GRACE_SECONDS (4) after the spawn,
  then looks at the character at most TWICE (now and SECOND_TRY 0.6 s later) and only moves it when it is
  off the plot (+ 6) AND `Humanoid.MoveDirection` is zero (not walking). Never a loop, never a third look.
  The second look is there because the first pivot can lose to the client's own spawn replication, or
  to DayNightCycle's lane return when a player joins during the night (the engine's default spawn is
  beyond the night barrier for a frame; the night loop returns "lane" players to LobbyReturnCFrame at
  (1193, -226, 130) - observed once as plot-space x 108 a second after a night-time join).
- Verified (playtest 2026-09-13): a respawn shoved to the lobby return point at 0.25 s read plot-space
  x 180, was back at 0 by 0.53 s ("try 2" at 0.7 s) and stayed; pivoted 30 studs out of the plot after
  the grace it stayed at x -57 for 2 s. PlotService's PlaceCharacter and DayNightCycle's CharacterAdded
  hook are single-shot and were not the cause.

## 2026-09-13 Move placed cucumbers in build mode; red ghost when a spot is taken

User: "let users be able to move cucumbers around in build mode / make cucumber highlight red when
cannot be placed somewhere".

- NEW `build-mode/CucumberMoveServer.server.lua` (-> `ServerScriptService.CucumberMoveServer`): creates
  `Remotes.requestCucumberMove` (RemoteFunction; `InvokeServer(model, cframe) -> true | false, reason`)
  and re-runs CucumberCarry.Place's rules for a cucumber that already stands in the caller's
  `plot.Placed`: owner + PlacedCucumber tag, not `StolenBy` a zombie, caller at the base (margin 6), the
  target rebuilt from X / Z + yaw on the plot surface, the RestSize footprint inside the plot, and no
  overlap (box x 0.96) with anything else in Placed (its own parts ignored). Then `PivotTo` the rest
  pose (RestRotation / RestLift), the PlotHitbox re-laid upright at the new footprint, and
  `BaseSaveAPI.Snapshot(player)` so the save follows at once. Refused at night; 0.15 s cooldown.
- `BuildMenuClient`: `CucumberUnderMouse` (the PlotHitbox is the only part that answers rays) joins
  `BuildUnderMouse` for the hover glow and the click; `StartMovingCucumber` lifts a see-through clone
  (original faded via LocalTransparencyModifier) with the current yaw derived from the pivot;
  `UpdateCucumberPreview` (a branch at the top of `UpdatePreview`) follows the plot surface on the
  current grid, R rotates, and `SetGhostValid` turns the parts + Highlight RED when the box overlaps
  anything else in Placed or the footprint cannot fit ("Something is already standing there" / "Too
  big for your plot at this angle"); `TryPlace` sends `requestCucumberMove`. Sell mode refuses cucumbers.
  Dev hook `movecucumber:<name>|last`. Cucumbers stay ground-floor (no upstairs rules).
- `CucumberPlacementClient` (the carried-cucumber ghost) now tints its PARTS red as well as the
  Highlight when occupied / too big (colours remembered per part, restored when valid).
- Verified (playtest 2026-09-13, a `CarryDev collect` Sliced Cucumber placed at (8, 4) through
  requestCucumberPlacement; the test plot was packed with a restored base): `movecucumber:last` ->
  strip + "Sliced Cucumber Preview"; aimed at a computed free cell (-16, -4): Highlight off, 0/5 red
  parts, normal hint; aimed over a WoodenWall at (-10, 0): Highlight on, 5/5 red parts, "Something is
  already standing there"; a drop on the wall was refused and the cucumber stayed; `place:-16,-4` ->
  pivot and PlotHitbox both at (-16, -4), tag kept, original un-faded, strip closed. Test wall +
  cucumber removed afterwards.

## 2026-09-13 Big cucumbers collide with a smaller footprint

User: "bigger/massive cucumbers are really sensitive about placement and are hard to place - its
impossible to place them near anything. make this less sensitive."

- Cause: every occupancy test used the cucumber's FULL bounding box (RestSize x 0.96), and every placed
  cucumber's invisible PlotHitbox WAS that full box - for a tree or a giant that is mostly canopy, so
  nothing could stand under its leaves and two of them could never be neighbours.
- NEW `ReplicatedStorage.Modules.CucumberFootprint` (`CucumberFootprint.lua`): `Factor(size)` =
  clamp(TARGET 6 / max(size.X, size.Z), MIN 0.5, SHRINK 0.96) and `Box(size)` = (X x f, Y x 0.96,
  Z x f). Up to 6 studs wide nothing changes (x 0.96 as before); a 12-stud tree keeps a 6-stud
  footprint, the widest keep half. Used everywhere the test runs so ghost, server and hitbox agree:
  `CucumberCarry.Place` (bounds + overlap + the PlotHitbox it lays) and `RestorePlaced` (the hitbox
  from RestSize rather than the saved, older full box), `CucumberPlacementClient` (Update + QuickPlace),
  `CucumberMoveServer` (also re-lays the hitbox on every move), `BuildMenuClient` (the move ghost).
  Builds benefit too: a build's ghost now only collides with the smaller cucumber hitbox.
- Verified (playtest 2026-09-13, the alt account's packed base): restored hitboxes read e.g. MASSIVE
  Frozen Tree RestSize 12.3 x 15.3 -> box 6.2 x 7.7, MASSIVE Pearl 8.3 x 7.9 -> 6.0 x 5.7, small ones
  unchanged (x 0.96). A 1-stud scan found (-11, -12), where the OLD box overlapped 5 things (catapult,
  flooring, slice stack, sandstone tree, turret) and the new box none: the ghost showed green, the
  move went through, the tree stood there. Its original spot could not be re-taken by a validated
  move (the saved layout had it overlapping a turret + trap - base restore never validates), so it
  was put back through the server (PivotTo + hitbox + Snapshot). Note: a flooring tile under a spot
  still blocks a cucumber (pre-existing: any Placed part counts).


---

## 2026-09-14 — BIOME GUARDIANS, phase 1: the ten models (Blender)

Ten sitting guardians, one per biome, for the "steal a cucumber and it chases you" loop.
**Phase 1 is the modelling only** — nothing is installed in the place yet. Source lives in
`RobloxGames/guardians/` (its own `README.md` has the full detail); the modelling brief is
`new-map-cucumber-game/guardians/GUARDIANS.md`.

**What exists now.** `Strawman` (Spawn), `Dune` (Desert), `Kabuto` (Samurai), `Brisket`
(Farm), `Frostbite` (Snow), `Pinch` (Underwater), `Ember` (Volcano), `Orbit` (Narmek),
`Tick` (Toyland), `Scan` (Neon) — **361 parts / 29 415 tris**, every one inside the
2 000–4 000 budget, plus a seat prop each (hay bale, sand mound, pedestal, mud patch, ice
block, rock nook, rock pile, crescent moon, block stack, charging pad) and a crow for
Strawman's wake burst. All 21 FBX are uploaded as group-owned Open Cloud Model assets
(group `14583228`); ids in `guardians/fbx/asset-ids.json`.

**These are rigs, not props.** Every moving part is its own object **with its origin on its
joint**, and every part records its **rig parent**, so `guardians/manifest.json` carries the
whole Motor6D tree as data: `{part: {parent, pivot, role, hex, material, sleep_hex, tris}}`
per guardian, plus the poses and a `space` block giving the Blender→Roblox conversion.
Phase 2 builds the Motor6Ds straight from that rather than deriving anything.

**Naming carries the colour.** The FBX importer drops every material, so each part is named
`<Guardian>_<Part>_<Role>` (`Frostbite_Arm_L_FurWhite`) and the installer stamps the colour
from the role — the last underscore-separated token. Role tables are per guardian in
`guardians/gmath.py`, so every guardian has its own `EyeGlow`. `SLEEP_LOOK` gives the dark
variant for the asleep state; eyes are always separate Neon parts so the wake tell reads at
100 studs.

**Facing.** `GUARDIANS.md` says to face the model "−Z in Blender", which is *down* in a
Z-up scene. The convention that actually yields a forward LookVector is **+Y in Blender**:
the importer's 180° yaw lands it on Roblox −Z. All ten are authored +Y.

**Poses are the rig test.** Each script exports `POSES` (`Sit`, `Awake`, usually `Run` and a
signature pose) mapping a part to `(rx, ry, rz)` about its own pivot, inherited by children —
the same transform the Motor6D chain will apply. Rendering a pose therefore *proves the
pivots*: `renders/<Guardian>_Sit.png` and `_Awake.png` exist for all ten and all compose
correctly. Axis rule worth keeping: a limb hanging BELOW its pivot swings forward on `+rx`,
but a piece standing ABOVE its pivot (torso, head) tips BACK on `+rx` and slumps on `−rx`.

**How it was built.** The library plus Strawman were proven in Blender first; the other nine
were authored in parallel (one agent each) against a written brief transcribed from the ten
concept sheets, validated offline by `guardians/dryrun.py`, then re-read by an independent
reviewer. Every guardian was then **reviewed from its render against its sheet** and the
defects fixed in a second pass — a crab whose giant claw swept inward and vanished into the
silhouette, a golem built from beads instead of boulders, a yeti reading blue instead of
white with its fur in tiled rows, an oni whose horns swept backwards, a drone with a box for
a head. Agents never touch Blender: concurrent `execute_blender_code` calls share one socket.

**Open Cloud key note.** The key the user pastes is `w/<apikey><base64 JWT>`. The embedded
JWT carries an `exp` one hour after `iat` — **it does not govern the key**. A key whose
embedded `exp` had passed 2 hours earlier uploaded all 21 assets without complaint. Never
pre-flight on it (`cucumbers/upload-cucumbers.ps1` does, and will refuse a good key);
`guardians/upload-guardians.ps1` only warns.

**Still to do:** Phase 2 (rig + animate + install under `ServerStorage.Assets.Guardians`),
then Phase 3 (the chase system), Phase 4 (pickup refresh), Phase 5 (player stealing).


## 2026-09-15 — BIOME GUARDIANS, phase 2: rigged, animated, installed

All ten guardians are now **in the place** at `ServerStorage.Assets.Guardians.<Name>` —
each a Humanoid rig with its full Motor6D tree, its seat model in a `Props` folder, and an
`Anims` folder of **7 published Animation assets**. 70 animations in total; ids in
`guardians/anims/anim-ids.json`. Nothing is in Workspace: Phase 3 spawns them.

**Install** (`guardians/install.lua`, served through `pets-remake/serve.ps1 -Root guardians
-Port 8771`): `LoadAsset` → yaw 180° about Y → rename `Guardian_Part_Role` to `Part` with a
`Role` attribute → re-apply colour/material/transparency from `install-payload.json` (the
FBX import loses all of it) → **build the Motor6Ds from attachment pairs** exactly the way
`zombie-raid/build_zombies.lua` does → add a Humanoid with `HipHeight` measured from the
real drop to the lowest geometry. `f.install(names)` 3-4 at a time, `f.verify()`,
`f.anims()`.

**`Root` and `Hitbox` are rebuilt as plain axis-aligned Parts.** Every imported part carries
the FBX importer's own axis rotation, so an imported part's LookVector points DOWN. That is
invisible for a mesh but fatal for a PrimaryPart: `PivotTo` uses `PrimaryPart.CFrame` as the
pivot, so the first `PivotTo` laid the whole guardian on its face. Caught by checking the
HRP's LookVector right after the first install.

**The joints are WORLD-ALIGNED**: each attachment sits at the joint with identity world
rotation, so a clip's rotation is the Motor6D `Transform` directly, with no per-part frame
correction. That is what makes the Blender poses usable as-is.

**Clips** (`guardians/clips.py` → `clips.json` → `build_anims.lua` → KeyframeSequences):
`SitIdle` (loop), `Wake`, `Run` (loop), `Grab`, `ReturnToSeat`, `Stunned` (loop) and one
signature each — CrowShake, DiveSurface, Slam, Charge, Throw, Snap, Throw, Blink, Rewind,
Blink. `Run` is generated as **the authored Run pose and its MIRROR**, which is a whole
stride cycle from one key pose. `Stunned` is **topology-driven** (droop decaying with joint
depth) rather than name-driven, because a worm, a crab and a hovering drone have no part
called `ArmUpper` — the name-matched first version moved 1 of Pinch's 50 motors; it now
moves 100 % on all ten.

**Space conversion**: a pose is `(rx, ry, rz)` about BLENDER world axes; Blender maps to
Roblox by `M = Rx(-90°)`, so the Roblox rotation is `M · R_b · M⁻¹` — conjugation, not a
component swap. `clips.py` emits QUATERNIONS so no Euler ordering has to agree across the
two engines.

**Verified in a playtest**: all 70 clips loaded from their published asset ids on their own
rigs, each with the right length and a real set of Motor6D `Transform`s rotating; then all
ten placed in-world on their seats playing `SitIdle`.

Two traps found here and worth keeping:
- A freshly uploaded animation returns `AnimationTrack.Length == 0` until the asset actually
  downloads. Poll for it; zero is not a failure.
- The trace of a Roblox rotation matrix is `RightVector.X + UpVector.Y − LookVector.Z`,
  because `LookVector` is the NEGATIVE Z axis. Getting that wrong made identity measure as
  90° and made a completely dead rig look like it was animating.
- `assets/anims/upload-animations.ps1` claims a group-owned animation only plays in
  group-owned experiences. **Tested false**: group `14583228` animation `129265796517160`
  played fine in this USER-owned place. Group upload is the only route this key allows and
  it works.

**Still to do:** Phase 3 (the chase system), Phase 4 (pickup refresh), Phase 5 (stealing).


## 2026-09-15 — BIOME GUARDIANS, phase 3: the chase system

Steal a cucumber out of a biome's field and that biome's guardian wakes up and comes for
you. Source in `guardian-chase/`; live in the place.

**New**: `ReplicatedStorage.Modules.GuardianCatalog` (all the tuning + per-guardian
character), `ServerScriptService.GuardianService` (the whole state machine),
`StarterPlayerScripts.GuardianClient` (toasts, in the one `Notify` style).
**Edited, minimally**: `CucumberCarry` (+`CucumberCarryAPI.TakeCarried`, 18 lines),
`StarterPack.Bat.BatServer` (swings at guardians as well as zombies),
`CucumberMutations` (+`M.SPECIAL` with the `GUARDED` mark).

**THE RACE IS THE DESIGN.** Chase speed is solved every tick from the TARGET's own
`WalkSpeed` and their `CarryingCucumberSpeed` multiplier: 7 % faster than they are moving
loaded, and always at least 10 % slower than they could move empty. Keep the heavy
cucumber and it reels you in; drop it and you are gone. Nothing is hard-coded — which
matters here, because WalkSpeed is driven by gym strength and the test save runs at
**103 studs/s** against a StarterPlayer base of 25.

| | |
|---|---|
| wake | first field pickup in its biome; targets carriers of ITS cucumbers, nearest first, empty-handed players are invisible |
| openings | one of charge / cut-off / feint picked per wake — verified mixing over 8 wakes each |
| pace | sprint bursts with rests (Ember never rests; Frostbite starts slow; Tick rewinds) |
| fence | the biome edge is the finish line — it never leaves, crossing sends it home |
| catch | the zombie knockback (same remote, same payload — measured 10.6 studs of flight), the cucumber comes off your shoulder, it carries it home and plants it with the **GUARDED** mutation (×10) |
| decoy | a cucumber dropped in the biome is reclaimed first |
| heat | server-wide, +1 per theft banked in the lobby, reset at dawn; wakes them faster, runs them harder, lengthens reach |
| bat | 4 blows knock one out for 60 s; beating a HIGH-HEAT one drops a rare mutated cucumber (verified: "VOID Sliced Cucumber") |
| night | fields shut, everyone back to bed |
| dev hook | `workspace.GuardianDev` = `wake:Spawn` / `sleep:all` / `stun:Farm` / `heat:5` / `home:Neon` / `list` |

**GUARDED is a mutation, not a special case.** `CucumberMutations.M.SPECIAL` holds it
OUTSIDE `M.MUTATIONS`, so `RollMutations` can never put it on a fresh cucumber, but
`byName` finds it — which means value, plot rate, colour, display name and the chat
announcement all work with no change to any value code. A reclaimed cucumber reads
"GUARDED Cucumber Tree" and is worth ten times as much.

### Four things that cost real time here

- **The seat was 20 studs up a wall.** `SeatSpot` put it behind the field and raycast for
  ground — but the Spawn field is at y −229 and the ledge behind it at −209, so Strawman
  sat above its own field and could never reach anyone in it. Seats now sample the ground
  from just above the FIELD's height and step inside the field if what is behind it rises
  more than `SEAT_MAX_RISE`.
- **The fence sent it straight back to bed.** With no `workspace.Zones.ZoneParts` in this
  place the biome falls back to `SpawnArea.<n>` (120 × 44) — smaller than the biome and
  not containing the seat — so the guardian woke, failed the fence test on the next tick
  and returned. Hence `FENCE_MARGIN` (20 studs) around the field.
- **`SPEED_MAX = 46` made the chase impossible**, because players here run at 103.
- **A `nil` type name silently spawns nothing.** The high-heat knockout drop called
  `SpawnCarried(zone, nil, ...)` and produced no cucumber and no error; it now borrows a
  type already growing in that field.

Verified in a playtest, each as its own measurement: ten guardians asleep on their seats
on their own field floors; real pickup via the `CarryDev` hook → wake → chase (34 studs
closed to 0.5) → catch → cucumber taken → carried home → planted as GUARDED; decoy
reclaimed after a drop; 4 bat hits → Stunned and still stunned 4 s later; high-heat
knockout dropped VOID; heat 0 at dawn; guardians asleep at night; behaviour variety across
8 wakes; knockback 10.6 studs.

### 2026-09-15 (later) — guardians LURK, chase you to the lobby, fixed speeds, sleeping z's

**Lurking.** A guardian no longer perches on its seat all day. The day-time idle is a
patrol: it picks a random point inside its biome, walks there at `LURK_SPEED` (34 % of its
set pace) with its eyes still dark, pauses to look around, and after `REST_AFTER_STOPS`
stops drops back onto its seat for a sit before setting off again. Night is still a proper
sleep.

States: `Asleep` (night) → `Resting` (sat on the seat by day) → `Lurking` → `Waking` →
`Chasing`/`Reclaiming` → `Returning` → back to `Resting`. A theft wakes it from any of the
idle three, and **one already on its feet skips the stand-up clip and starts after you at
`WAKE_FROM_LURK` (35 %) of the usual delay** — being caught mid-prowl is more dangerous
than waking one that was sitting down. Measured 10/10 prowling, 71–127 studs of path each
over 18 s.

Two things it needed: **seat props are no longer collidable** (a guardian jammed against
its own hay bale and ground there), and **stuck detection** — `Humanoid:MoveTo` walks in a
straight line, so anything in the way meant a 9-second stall; if it has not moved 2 studs
in 2.5 s it repicks.

**No GUARDED mutation.** Reverted entirely: no ×10, no tag, no `M.SPECIAL` in
`CucumberMutations`, no `Guarded` attributes. A cucumber a guardian takes back goes down
exactly as it was. The guardian standing over the field IS the protection. Verified: 60
cucumbers, 0 guarded, a Sliced Cucumber back to a value of 3 (it was 30).

**It chases you to the lobby.** The biome edge is no longer the finish line — a guardian
follows you out of its own biome and breaks off only when you are inside the lobby walls
(same `Map.Borders["Lobby Border"]` box CucumberCarry uses), or you drop the cucumber, or
it catches you. `FENCE_MARGIN` now only keeps a *lurking* guardian in its own patch.
Verified: it crossed its old fence by 24 studs mid-chase, and broke off with
`Reason = "they reached the lobby"` when the runner got home.

Two knock-ons that had to change with it:
- **`LOSE_DISTANCE` 150 → 700.** At 150 a guardian gave up before the runner was halfway
  home, which defeats the whole rule.
- **Fall recovery.** A chase that can leave the biome can run off an edge, and anything
  below `FallenPartsDestroyHeight` is *destroyed* — which is exactly how one build reduced
  all ten to a Humanoid and an Anims folder. A guardian more than 40 studs below its seat
  is now put straight back on it.

**A set WalkSpeed per guardian, climbing the biome ladder.** Nothing is solved from the
player any more: `GuardianCatalog.GUARDIANS.<name>.speed` is the number in studs/second.

| Strawman | Dune | Kabuto | Brisket | Frostbite | Pinch | Ember | Orbit | Tick | Scan |
|---|---|---|---|---|---|---|---|---|---|
| 24 | 32 | 40 | 48 | 56 | 64 | 72 | 80 | 88 | 96 |

A new player outruns the Spawn scarecrow; nobody outruns the Neon sentinel. Heat still
runs them a little harder and the burst/rest cycle still breathes, but the base is fixed.
Verified: Scan chased at exactly 96, Strawman lurks at 8 (24 × 0.34).

**Sleeping z's.** A `BillboardGui` of drifting z's over any guardian that is sitting down
(`Asleep` or `Resting`). Built on the server so it replicates once, **animated on the
client on Heartbeat** — no network cost, and it keeps running with Studio unfocused, which
TweenService does not. Sized in **studs** like the plot owner badge. Each z rises
`ZZZ_RISE` studs over `ZZZ_PERIOD`, drifting sideways, growing and fading, the three of
them offset in phase so they file upward. Verified animating on a resting Brisket.

## 2026-09-16 Click-to-lift pickup: the bar, kg weights, Blender lift clip (user: "delete the current cucumber pickup system entirely")

User: a long bar like the screenshot -- the strength icon drifts left; every click pushes it right;
all the way right = picked up, all the way left = the pickup fails; red end on the left, green on
the right; the camera frames the whole body and the cucumber; a Blender pickup animation where every
click brings the cucumber up a little; strength-based: lots of strength = 2-3 clicks, not enough =
the icon always wins whatever the clicks per second; weights in kg from 3-4 kg for the lightest
Spawn cucumber to a trillion for the lightest Neon one, shown instead of a strength requirement.

### What went (all in `ServerStorage.__LiftRebuildBackup_2026_09_16`, disabled; disk backup
`backups/NewMap_pickup_before_lift_rebuild_2026-09-16.rbxm`)
- `RS.Modules.CucumberStrength` (bands, grip budget, carry modes, recovery window, band labels)
- `StarterPlayerScripts.CollectAnimClient` (walk-up + struggle / pick-up / fall clips, speed controller)
- `StarterPlayerScripts.CucumberGripClient` (the GRIP! panel, STEADY button, carry-mode cycling)
- `RS.Assets.Animations` CucumberPickUp / CucumberStruggle / CucumberFall + their KeyframeSequences
- inside `CucumberCarry`: Heavy / Weak / Speed / Band / Ratio, Stumble, ScheduleStumble, the grip
  Heartbeat, SteadyCucumber / CucumberCarryMode / CancelCucumberPickup / CollectAnim remotes, the
  rescue-pickup shortcut, the "stumble" dev hook, Place's too-heavy refusal
- inside `CarryClient`: the per-band hints, the Stumble / Steadied cues

### What is new
- `RS.Modules.CucumberLift` (mirror `CucumberLift.lua`): WEIGHTS + THE BAR + the timeline.
  kg = `ZONE_BASE[zone]` (Spawn 3, Desert 60, Samurai 1.2K, Farm 25K, Snow 500K, Underwater 10M,
  Volcano 200M, Narmek 4B, Toyland 60B, Neon 1T) x (reward / 3) ^ 0.55 (CucumberValues.REWARDS:
  the 360-reward tree is ~14x its biome's slice, still under the next biome's slice) x Golden 2 /
  Diamond 4 x 1.5 per mutation x SizeScale ^ 1.5, two significant digits. 1 kg asks for 1 Strength:
  `ratio = Strength / kg`. `Params(ratio, trait)`: ratio >= 1 -> Gain clamp(0.065 x ratio^1.2,
  0.065, 0.36) per click, Drift 0.12 / ratio per second (x1 ~10 clicks, x2 ~5, x3.5+ two clicks);
  ratio < 1 -> Gain 0.022 x ratio, Drift 0.45 .. 1.2 per second -- MAX_CPS 20 clicks per second adds
  at most 0.44 per second, under the 0.45 drift floor, so the icon always wins. Slippery (CucumberAdventure trait) drifts x1.25.
  `Of(holder)` reads the WeightKg attribute CucumberCarry stamps on every field cucumber,
  `Format(kg)` -> "12 kg" / "1.2K kg" / "1T kg" (NumberAbbrev), `Difficulty(ratio)` -> easy (>= 3)
  / medium (>= 1.5) / hard (>= 1) / too heavy + a colour for the prompt.
- `RS.Modules.CucumberLiftPoses` (GENERATED: `assets/anims/json_to_poses_module.js` from
  `CucumberLift.json`): 22 pose samples at 15 fps, 7 numbers per joint, Motor6D.Transform values.
- `StarterPlayerScripts.CucumberLiftClient` (mirror `CucumberLiftClient.client.lua`): the whole
  client side. Own lift: walk-up (Humanoid:Move per frame, APPROACH 0.6 s), face it, freeze
  (WalkSpeed 0 held on Stepped, no jump, no AutoRotate, PlayerModule controls off when present),
  camera swings (Scriptable, 0.35 s quad-out) to the cucumber's far side looking back at the
  player -- distance from the vertical / horizontal FOV so the whole body and the cucumber fit,
  eye 0.28 x distance above the focus, pulled in when a wall is in the way -- and THE BAR appears:
  `PlayerGui.CucumberLiftBar` = full-screen click Catcher (every click / tap anywhere counts,
  nothing under it gets them) + Root (78 % wide, 15 % tall, capped 1400 x 100 px, bottom at 87 %)
  with Title (name, coloured by CucumberMutations, + kg), Hint ("CLICK! CLICK! CLICK!" / TAP,
  pulsing), Track (grey, 30 % translucent, 8 px corners, 4 px dark outline), RedZone / GreenZone
  (5 % of the track each), Icon (the HUD's strength image rbxassetid://15403007921, 1.55 x the
  track height, pops on every click, tilts and trembles when the drift is winning). Gamepad A /
  R2 click too; X / B cancel. Heartbeat: p -= Drift x dt, click: p += Gain; p >= 1 -> "done" to the
  server + the hoist (clip 1.0 -> 1.4 s over HOIST_LEN 0.4), p <= 0 or MAX_TIME 12 s -> "fail":
  "Too heavy" (Notify), Big Thud, the pose and the cucumber sink back over FAIL_RELAX 0.45 s.
  Progress goes to the server at 8 Hz for the other clients.
  THE POSE (every client): the CucumberLift clip is scrubbed by progress and written straight into
  the R15 Motor6D.Transform values on RunService.Stepped (weight-blended in / out over 0.15 s,
  translations scaled by HumanoidRootPart.Size.Y / 2 for the physique-scaled bodies), so it needs
  NO Animation asset -- it plays on a live server whoever owns the place (the old clips were
  group-owned and only ran in Studio). The cucumber rides the hands' midpoint up (giants only
  1 / SizeScale of the way), smoothed.
- `CucumberCarry` (mirror `CucumberCarry.server.lua`): `Collect` locks the cucumber
  (CollectingBy, prompt off, Busy), unequips tools (the bat would swing on every click), computes
  kg / ratio / Params for THIS player and fires {Kind = "Start", Player, Holder, Token, Name, Kg,
  Start, Gain, Drift} to everyone. `attempt.Finish(result)`: "done" is believed only when
  strength >= kg and the claim comes at least APPROACH / 2 + MinClicks / MAX_CPS seconds after the
  press (else it is turned into a cancel and logged) -> {Kind = "Hoist"} to all, HOIST_LEN later
  `Grab` (alive / reach / hands re-checked) swaps the field cucumber for the shoulder copy;
  "fail" -> {Kind = "Fail"}; "cancel" / no answer for APPROACH + MAX_TIME + 2 s -> {Kind =
  "Cancel"}. Progress ticks are relayed to the OTHER clients (12 Hz cap). Every field cucumber
  gets WeightKg; placed / restored copies carry it too. Carry entries keep Kg (player attribute
  CarryingCucumberKg; `Required` = kg for CucumberAdventure's "heaviest secured" records). The
  lobby watch only marks CucumberCarrySafe + the LobbyReached cue now. DropForNight / TakeCarried
  cancel a running bar first. Dev hook: `CarryDev` = "collect:<Name>" | "win:<Name>" |
  "lose:<Name>" | "drop:<Name>" | "pickup:<Name>".
- `CucumberPromptClient`: name, "Lift", and the weight row "12 kg" in the Difficulty colour
  (prefixed by the CucumberAdventure trait when it has one). `CarryClient`: a kg line under the
  name on the shoulder billboard; hints / cues of the old system gone.

### The clip (Blender, headless: `blender -b CucumberAnims.blend --python build_cucumber_lift.py`)
The Blender MCP addon was not running, so the same r15animlib pipeline ran in background mode
(`assets/anims/build_cucumber_lift.py`). CucumberLift 1.4 s: 0.00 deep squat grip (hip drop 0.45,
hips back 0.38, root -14, waist -54, hands closed on the cucumber), 0.33 rising with the load at
the knees (arms straight down), 0.60 nearly upright with the load at the thighs (the screenshot),
1.00 upright, elbows bent, the load hugged at the chest, 1.40 the carry pose (left hand steadying
the shoulder load). The bar scrubs 0..1.0, the hoist plays 1.0..1.4 once. Arm reach errors 0 except
the grip pose (0.18, the same as the old struggle grip). Exports: CucumberLift.json / .fbx,
preview_CucumberLift_{000,033,060,100,140}.png, the action saved in CucumberAnims.blend.

### Strength economy note
The kg ladder is what was asked for (Spawn slice 3 kg .. Neon slice 1T kg). Today's strength
sources (bench 2^(level-1) per rep up to 128 x headband up to 13, shop packs up to 50K) reach the
first three or four biomes; the Snow .. Neon weights assume the strength economy grows (rebirths,
multipliers) -- `CucumberLift.ZONE_BASE` is the one table to retune.

### Verified (solo playtest 2026-09-16, awesomeotheraccount, 1301 x 611 play window, LiftDevCPS auto-clicker)
- strength 10M vs Slice Stack 8.5 kg: bar at 0.60 s, 0.35 -> 0.71 -> hoist at 0.95 s (two clicks at 6 cps),
  idle at 1.60 s, CarryingCucumber "Slice Stack" / CarryingCucumberKg 8.5, LeftHand rose from -1.71 to
  +2.07 studs above the root (the Motor6D scrub works), the cucumber rode up 2.3 studs, camera
  Scriptable -> Custom, WalkSpeed 55 / JumpPower 50 restored, bar hidden.
- strength 3 vs Sliced Cucumber 3 kg (ratio 1, 6 cps): +0.065 per click against the drift, hoist at 3.43 s.
- strength 2.7 vs 3 kg (ratio 0.9) at 20 cps: the icon sank 0.34 -> 0.07 and MAX_TIME failed it at 12.6 s
  (with the shipped Gain 0.022 it loses faster); "Too heavy" toast, holder back at its pivot (0.00 studs
  off), prompt re-enabled, CollectingBy nil, camera Custom.
- a forged {Result = "done"} 0.05 s after Start at ratio 0.9: server warn "claimed a lift ... refused",
  Cancel to the client, nothing carried.
- screenshot: full body facing the camera with the cucumber in front, bar with red / green ends, icon,
  "Sliced Cucumber · 3 kg", "CLICK! CLICK! CLICK!", above the hotbar. Camera 9.9 studs out for the 5.5-stud
  Beginner physique.
- Test gotchas: the Spawn guardian (GuardianService) wakes on the pickup and CATCHES a frozen tester in
  a few seconds (Strawman attrs State Resting / Reason "caught them") -- carries vanish between tests
  without any bug; night closes the fields mid-test (180 s days); the `collect:` dev hook forces a lift
  from any distance, which is why the camera framing now ignores a cucumber more than 16 studs away.
- NOT saved / published; the RAS places open beside it were not touched.

### Follow-up (2026-09-16, user: "remove the slippery / bouncy tags above wild cucumbers; make the bar smaller, like the original attachment; give the player some time before the icon starts moving back")
- The trait prefix on the prompt's weight row is gone (it reads "3 kg" only); CucumberAdventure still
  rolls CarryTrait on holders but nothing shows it and `CucumberLift.Params(ratio)` no longer takes
  it (the Slippery drift multiplier is deleted).
- The bar: Root = 46 % of the screen wide with a UIAspectRatioConstraint of 10.3 (the reference
  bar's shape), so 598 x 58 px on a 1301-wide window (was 78 % x 15 %); the Title (name + kg) and
  the Hint hang above it (55 % of the track height), the icon is 1.4 x the track height. Capped at
  820 px wide, never under 340.
- `CucumberLift.GRACE` = 0.7 s: after the bar appears the icon holds still (clicks still count)
  until the camera pan (CAMERA_IN 0.35) is over plus a breath; the losing tremble waits for it too.
- Verified (solo playtest, 1301 x 611): weight row "3 kg" on a Bouncy Sliced Cucumber; bar 598 x
  58 px; p stayed 0.350 until the first drift at 0.72 s.

## 2026-09-16 Defence set 2: Mortar, Tesla Coil, Freeze Tower, Minigun, Laser Gate (user: "build these with blender mcp, import with my opencloud key, add as defenses users can place in build mode, script each")
Five Blender props (headless, `defenses/BRIEF-2026-09-16.md`, five parallel agents) uploaded as Group
Frenzy Model assets and installed into `ServerStorage.Builds.Defences` (`defenses/install_set2.lua`),
so build mode sells them (Cost 3500 / 4000 / 3000 / 5000 / 2000). `DefenceService` (mirror
`zombie-raid/DefenceService.server.lua`, backup `ServerStorage.__DefenceSet2Backup_2026_09_16`) gained
the five behaviours: Mortar (60 splash r10 every 3.6 s, 12..75 studs, arcing shell), TeslaCoil (18 dmg
chaining x0.75 to 3 more within 12 studs every 1.5 s), FreezeTower (24-stud aura: slow + 4 hp/s chill;
`FreezePulse = true` attribute = 1.5 s stun every 10 s), Minigun (single target, 4 dmg x 12.5/s after a
1.2 s spin-up), LaserGate (25 dps to anything standing in the 2.5-stud-deep gap). `ZombieCatalog.BUILD_HEALTH` has
the five keys. Full write-up: `defenses/README-set2.md`.
Verified (solo playtest, test builds placed by `defenses/test_place.lua`-style evals, Rotten
Shamblers 60 hp): Mortar 2 shells / 2 bursts, 3 zombies at 50 studs dead in 3 s; Tesla 4 hits per zap
at 18/14/10/7.5, 4 dead by 9 s, orb spinning; Minigun one target at a time, 45 tracers = 180 hp at
4 each, barrels rolling; Freeze WalkSpeed 8 -> 3.6, 60 -> 4 hp over 14 s, pulse stun to speed 0;
Laser Gate: two zombies held in the gap lost 60 -> 9 / 22 hp in 8 s at the first 14-dps tuning with sparks and beam flicker (shipped at 25 dps, 2.5 studs deep). Gotchas: the plot's SurfaceY is plot-RELATIVE (world = plot Y + it; the
map sits at y -229); a test build placed with the PlacedBuild tag is SAVED by BaseSave and restored
on the next playtest (clean it out of the profile); setting `Broken = true` by hand to idle other
defences must be undone by hand (BuildHealthService never mends what it did not break).

### Near-miss band + the biome signs (2026-09-17, user: "even if the strength is slightly below the requirement the user still has a chance ... within a certain range or really close he should be able to get it if he clicks fast enough; follow the signs in each biome that show the strength requirement")
- `CucumberLift.ZONE_BASE` now IS the sign ladder (`Map.Biomes."01 Spawn".Decor.Sign` x 9, "💪N
  recommended!" at each biome entrance): Desert 300, Samurai 2K, Farm 15K, Snow 400K, Underwater 6M,
  Volcano 40M, Narmek 750M, Toyland 14B, Neon 1T (Spawn has no sign: 3 kg). `REWARD_POWER` 0.55 -> 0.4 so
  a biome's tree (x6.8 its slice) stays under the next sign (the smallest sign step is x6.7): Spawn
  3 / 4.4 / 6.4 / 9.7 / 14 / 20 kg, Desert 300 .. 2K, Samurai 2K .. 14K, ... Neon 1T .. 4.7T.
- `Params(ratio)` has three bands now: STRONG (>= 1, as before), NEAR MISS (`NEAR.MinRatio` 0.65 ..
  1: Gain 0.06 x ratio, drift = gain x break-even cps, the break-even rate running 3 cps just under
  the weight to 10 cps at 0.65 - so 6 cps wins at 0.9, 10 cps wins at 0.8 in ~4.5 s, 0.65 needs
  10+), HOPELESS (< 0.65: unchanged, nothing wins). `Feasible` = ratio >= 0.65 (the server accepts a
  "done" claim down there); `CpsToWin(ratio)` and a "close" Difficulty row ("Close! Click fast",
  orange); the prompt's weight row appends " · Click fast!" in that band.
- Verified (solo playtest, LiftDevCPS auto-clicker on a 3 kg Sliced Cucumber): ratio 0.80 at 10 cps
  lifted in 4.0 s; 0.80 at 4 cps failed at 4.6 s; 0.50 at 20 cps failed at 2.2 s; 0.90 at 6 cps lifted
  in 9.9 s. Test gotcha: the field is empty at night (180 s day / 45 s night) - check CyclePhase first.

### Guardians follow you out of their biome + heavy loads slow you (2026-09-17, user)
- **Guardian chase.** `GuardianService.AimPoint` clamped a "cutoff" guardian's destination to its own
  field (`ClampToZone` with FENCE_MARGIN - 6 of slack) and the blink step did the same, so those
  guardians stopped at the biome edge while the thief ran on. Both clamps are gone: while a player
  still carries its cucumber (that is what the Chasing target list is) the guardian goes wherever
  they go; the lobby (`Safe`) still sends it home, as does a drop or the catch. Lurking still uses
  the InZone fence. GIVE_UP_SECONDS (120) and LOSE_DISTANCE (700) unchanged.
- **Carry slowdown.** `CucumberLift.SpeedFor(ratio)` = 1 at or above the weight, sliding linearly to
  `CARRY_SPEED_MIN` 0.45 at the bottom of the near-miss band (ratio 0.65): ratio 0.9 -> x0.84, 0.8 ->
  x0.69, 0.7 -> x0.53. `StrengthProgressionServer.refresh` multiplies its WalkSpeed by it from the
  `CarryingCucumberKg` attribute (it also re-runs on that attribute) and `CucumberLiftClient` applies
  the same when it restores the walk after a lift, so the client never overwrites the slow value.
  Dropping / placing clears the attribute -> full speed.
- Verified (solo playtest through the official Studio MCP - the chrrxs plugin had auto-updated to
  v3.1.5 against a v3.1.4 server, so its play peers were refused): Slice Stack 6.4 kg lifted at ratio
  0.8 -> server AND client WalkSpeed 17.23 vs base 25.13 = x0.686; carrier teleported into the
  Desert field -> Strawman "Chasing" crossed the Spawn field edge (x 1015) at 4.6 s, gap 160 -> 7
  studs, caught the carrier at 8.2 s, player alive. Test gotcha: 130 studs sideways (Z) from a field
  is open void - the character dies and the carry vanishes; move the carrier along X into the
  neighbouring field instead.

### The shown weight is not the requirement (2026-09-17, user: "kg numbers not directly correlated with strength ... show lower values / different numbers so the player doesn't know the exact strength they need; adds mystery")
- `CucumberLift.Shown(kg, zone, typeName)` = `DISPLAY.Scale` 0.55 x kg ^ `DISPLAY.Power` 0.93, nudged
  +-`DISPLAY.Jitter` 12 % by a stable hash of biome + type (the same kind always reads the same),
  two significant digits. It rises with the real weight but is never the Strength number: Spawn
  slice 3 -> "1.5 kg", Cucumber 4.4 -> ~"2.2 kg", Desert slice 300 -> ~"110 kg", Neon slice 1T ->
  ~"77B kg" (the biome signs still say the real recommended Strength).
- Plumbing: `CucumberCarry` stamps `ShownKg` next to `WeightKg` on every field cucumber (and on placed /
  restored copies), keeps `entry.ShownKg`, sets the player attribute `CarryingCucumberShownKg` next to
  the real `CarryingCucumberKg` (which the bar and the slowdown still use), and sends the shown value
  as `Kg` in the lift's Start payload (the bar title). `CucumberPromptClient` shows
  `CucumberLift.ShownOf(holder)`, `CarryClient` shows `CarryingCucumberShownKg`. Nothing the client
  receives carries the requirement any more; the Difficulty colour on the prompt (easy / medium /
  hard / close / too heavy) stays as the only hint.
- Verified (solo playtest via the official Studio MCP; its `multi_edit` tool replayed the exact
  old/new edits since the chrrxs bridge had no peers and the official Luau sandbox has no HTTP or
  `require`): field cucumbers carry both numbers (Sliced Cucumber WeightKg 3 / ShownKg 1.6, Wrapped
  Cucumber 970 / 300, Windmill Plant 48K / 13K, Molten Cucumber 80M / 13M); a lift's Start payload
  carried Kg 1.6; the carry stamped CarryingCucumberKg 3 + CarryingCucumberShownKg 1.6; the shoulder
  billboard read "1.6 kg".

### Guardian catch: the cucumber drops where you stand, knockback scales with strength (2026-09-17, user)
- **Drop, not take.** `GuardianService`'s catch no longer pulls the cucumber off your shoulder and
  carries it home (TakeCarried / HoldCucumber). It calls the new `ServerStorage.CucumberCarryAPI
  .DropAtFeet(player)` (CucumberCarry): the load becomes a field cucumber again at your feet -
  `SpawnCarried` with `Anywhere = true`, so it lands right there whatever field / biome you are in -
  with the Replant cue (dirt puff), the toast "<Guardian> knocked the <name> out of your hands!", and
  the guardian goes home empty-handed ("caught them"). It does NOT reclaim it (GoHome puts it in
  Returning before the decoy check runs), so you can pick it straight back up; a deliberate DROP
  still works as a decoy as before.
- **Knockback by strength.** `KnockbackFor(entry, player)`: the guardian's strength = `GuardianCatalog
  .STRENGTH_MULT` (5) x its biome's lightest cucumber (`CucumberLift.ZONE_BASE`, the sign ladder:
  Strawman 15, Dune 1.5K, ... Neon 5T); ratio = your Strength / that, on a log2 scale from
  `KNOCKBACK_LOG_LOW` -2 (a quarter as strong: `KNOCKBACK_MAX` 14 studs) to `KNOCKBACK_LOG_HIGH` 2
  (four times as strong: `KNOCKBACK_MIN` 3 studs); equal strength = 8.5. `Knockback(entry, player,
  dir, distance)` passes it in the ZombieRaid "Hit" payload the client flies (KNOCKBACK_TIME 0.35 s).
  Zombie hits (ZombieRaidService) are untouched.
- Verified (solo playtest via the official Studio MCP, Strawman): strength 10,000 -> Hit Distance
  3.0, the "Cucumber" standing 4.6 studs from the player, Strawman Returning holding 0 models;
  strength 3 (ratio 0.2) -> Hit Distance 14.0, the player flew 13.9 studs in 1 s, the Sliced
  Cucumber 2.9 studs from the catch spot, Strawman Returning holding 0. GuardianCatalog has no disk
  mirror; `live-2026-09-16/GuardianService.server.lua` is the current text.

### The lift difficulty curve (2026-09-17, user: "the strength ranges are too minimal, only 4 scenarios ... there should be more ranges of strength that do more ... an algorithm to correlate strength with all this")

- **One curve instead of three bands.** `CucumberLift.CURVE` is a table of rows `{Ratio, Clicks, Cps}`
  (ratio = Strength / kg): `Clicks` = clicks that fill the bar from START with no drift
  (`Gain = (1 - START) / Clicks`), `Cps` = the click rate that only holds the icon still
  (`Drift = Gain x Cps`). A lift sits between two rows by log2(ratio) (linear interpolation,
  `M.Curve(ratio)`), so every ratio is its own difficulty. STRONG / NEAR / WEAK are gone;
  `M.MIN_RATIO` 0.4 is the floor (below it `M.WEAK` = 24 clicks of gain shrinking with the ratio and a
  0.55..1.15 drift: MAX_CPS never keeps up, Feasible = false, the server refuses the claim too).
  Clicking at c per second wins in `Clicks / (c - Cps)` seconds (after the 0.7 s grace), slower than
  Cps loses, and anything slower than about `Clicks / 11 + Cps` runs into the 12 s timeout.
  `M.TimeToWin(ratio, cps)` computes it; `Params` now also returns Clicks / Cps.

  | ratio | clicks | hold cps | feel | 3 cps | 5 cps | 8 cps | 12 cps | 20 cps |
  |---|---|---|---|---|---|---|---|---|
  | 16+ | 1 | 0 | one click | 0.3 s | 0.2 | 0.1 | 0.1 | 0.1 |
  | 8 | 2 | 0 | two clicks | 0.7 | 0.4 | 0.2 | 0.2 | 0.1 |
  | 4 | 3 | 0.5 | three clicks | 1.1 | 0.6 | 0.4 | 0.2 | 0.1 |
  | 2 | 5 | 1 | a few clicks | 2.2 | 1.1 | 0.6 | 0.4 | 0.2 |
  | 1.5 | 7 | 1.5 | casual clicking | 4.0 | 1.7 | 0.9 | 0.6 | 0.3 |
  | 1.2 | 9 | 2 | steady | 7.6 | 2.5 | 1.3 | 0.8 | 0.4 |
  | 1 (= the sign) | 11 | 3 | steady, ~5 cps | fail | 4.5 | 1.8 | 1.0 | 0.6 |
  | 0.9 | 12 | 4.2 | click fast, 6-7 cps, no autoclicker | fail | fail | 2.4 | 1.2 | 0.6 |
  | 0.8 | 14 | 5.5 | click a LOT, 7-8 cps, still a human | fail | fail | 4.1 | 1.6 | 0.7 |
  | 0.7 | 16 | 7.5 | a real masher, 9-10 cps | fail | fail | fail | 2.4 | 0.9 |
  | 0.6 | 18 | 10 | autoclicker territory | fail | fail | fail | 5.5 | 1.1 |
  | 0.5 | 20 | 13 | autoclicker | fail | fail | fail | fail | 1.6 |
  | 0.4 | 22 | 17 | the last liftable weight | fail | fail | fail | fail | 3.4 |
  | < 0.4 | - | never | "Too heavy", the icon always wins | fail | fail | fail | fail | fail |

  Within a biome that ladders the types: at the sign's Strength the slice (x1) is a steady 11 clicks,
  the Cucumber (x1.47 kg) a masher's 0.68, the tree (x6.8) impossible; x2 the sign = 5 clicks / 9
  clicks / impossible; x4 = 3 / 5 / extreme 0.59; x8 = 2 / 3 / 9 clicks. Tune the feel by editing
  rows (add rows freely; keep them sorted by Ratio, strongest first).
- **Display follows the curve.** `M.DIFFICULTY` has eight rows: trivial (>= 8), easy (>= 3), medium
  (>= 1.5), hard (>= 1), close (>= 0.85, prompt "· Click fast!", bar "CLICK FAST!"), mash (>= 0.7,
  "· Mash!" / "CLICK FASTER!!"), extreme (>= MIN_RATIO, "· Extreme!" / "MASH!!!"), impossible ("Too
  heavy", the default "CLICK! CLICK! CLICK!"). `Difficulty(ratio)` returns the row as a 4th value;
  CucumberPromptClient appends `row.Hint` to the weight row, CucumberCarry sends `Band = params.Band`
  in the Start payload and CucumberLiftClient's `hintFor(band)` puts `row.Bar` on the bar (touch:
  CLICK -> TAP, MASH -> TAP FAST). `SpeedFor` now slides 1 -> 0.45 over ratio 1 -> 0.4 (0.9 = x0.908,
  0.8 = x0.817, 0.55 = x0.588).
- Verified (solo playtest via the official Studio MCP, LiftDevCPS auto-clicker, a PlayerGui
  LiftDevState watcher logging "phase after N s"): ratio 8 -> hoist after 0.40 s (2 clicks); 3.1 ->
  0.80 s (4 clicks); 1 @ 5 cps -> 4.60 s; 1 @ 2 cps -> fail after 7.35 s (p 0.001); 0.9 @ 6 cps ->
  5.17 s with "CLICK FAST!", walk 23.10 = 25.43 x 0.908; 0.9 @ 4 cps -> timeout fail at 12.02 s (p
  0.379); 0.8 @ 8 cps -> 4.13 s with "CLICK FASTER!!"; 0.55 @ 12 cps -> timeout fail at 12.02 s (p
  0.824, "MASH!!!"); 0.55 @ 15 cps -> 3.13 s, carried, walk 14.72 = 25.04 x 0.588; 0.3 @ 20 cps ->
  fail after 2.80 s; the prompt at 0.55 read "2.3 kg · Extreme!" in the extreme colour. Gotchas
  again: a lift that crosses nightfall ends "idle" (not a fail), and a win while standing IN the
  field is caught by the guardian within two seconds (the first 0.55 run "lost" its carry that way;
  from the plot it carried).

### Formulas for the clicks and the fall-back, and the two approaches compared (2026-09-17, user: "vary the clicks needed + fall back speed with strength and use formulas. Then compare both approaches")

- **Formula mode (live).** `CucumberLift.CURVE_MODE = "formula"`; `M.FORMULA = {ClicksAtSign = 11,
  OneClickRatio = 16, DriftAtSign = 0.18, DriftPower = 1}`:
  - `Clicks = ClicksAtSign x ratio ^ -ClickPower`, `ClickPower = log(ClicksAtSign) / log(OneClickRatio)`
    = 0.865, so it is exactly 11 clicks at the sign and 1 click at 16x (clamped to 1 above that).
  - `Drift = DriftAtSign x ratio ^ -DriftPower` bar per second: 0.18 at the sign (2 s from START to
    the red end with no clicks), and with DriftPower 1 every halving of the ratio doubles the fall-back.
  - `Gain = (1 - START) / Clicks`; the hold rate (what only keeps the icon still) = `Drift / Gain`
    = 3.05 x ratio ^ -1.865 cps. `M.CurveFormula` returns Clicks and that hold rate; `M.Curve`
    dispatches on CURVE_MODE, the table lives on as `M.CurveTable` / `M.CURVE`. Everything else
    (Params, TimeToWin, DIFFICULTY bands, MIN_RATIO 0.4, the WEAK band below it) is shared.
- **Side by side** (T = table, F = formula; win times at a steady click rate, "fail" = the icon wins
  or the 12 s timeout does):

  | ratio | clicks T / F | hold cps T / F | slowest winning cps T / F | @5 cps T / F | @8 T / F | @12 T / F | @20 T / F |
  |---|---|---|---|---|---|---|---|
  | 16 | 1 / 1 | 0 / 0 | - | 0.2 / 0.2 | 0.1 / 0.1 | 0.1 / 0.1 | 0.1 / 0.1 |
  | 8 | 2 / 2 | 0 / 0.1 | - | 0.4 / 0.4 | 0.2 / 0.2 | 0.2 / 0.2 | 0.1 / 0.1 |
  | 4 | 3 / 4 | 0.5 / 0.2 | - | 0.6 / 0.7 | 0.4 / 0.4 | 0.2 / 0.3 | 0.1 / 0.2 |
  | 2 | 5 / 7 | 1.0 / 0.8 | - | 1.1 / 1.3 | 0.6 / 0.8 | 0.4 / 0.5 | 0.2 / 0.3 |
  | 1.5 | 7 / 8 | 1.5 / 1.4 | - | 1.7 / 1.9 | 0.9 / 1.0 | 0.6 / 0.6 | 0.3 / 0.4 |
  | 1.2 | 9 / 10 | 2.0 / 2.2 | 2.7 / 2.9 | 2.5 / 2.8 | 1.3 / 1.4 | 0.8 / 0.8 | 0.4 / 0.5 |
  | 1 | 11 / 11 | 3.0 / 3.0 | 3.8 / 3.8 | 4.5 / 4.5 | 1.8 / 1.8 | 1.0 / 1.0 | 0.6 / 0.6 |
  | 0.9 | 12 / 13 | 4.2 / 3.7 | 5.0 / 4.5 | 11.3 / 7.3 | 2.4 / 2.2 | 1.2 / 1.1 | 0.6 / 0.6 |
  | 0.8 | 14 / 14 | 5.5 / 4.6 | 6.4 / 5.5 | fail / fail | 4.1 / 3.0 | 1.6 / 1.4 | 0.7 / 0.7 |
  | 0.7 | 16 / 15 | 7.5 / 5.9 | 8.4 / 6.9 | fail / fail | fail / 5.2 | 2.4 / 1.8 | 0.9 / 0.8 |
  | 0.6 | 18 / 18 | 10.0 / 7.9 | 11.0 / 8.9 | fail / fail | fail / fail | 5.5 / 2.8 | 1.1 / 1.0 |
  | 0.5 | 20 / 21 | 13.0 / 11.1 | 14.0 / 12.2 | fail / fail | fail / fail | fail / fail | 1.6 / 1.4 |
  | 0.4 | 22 / 25 | 17.0 / 16.8 | 17.9 / 17.9 | fail / fail | fail / fail | fail / fail | 3.4 / 3.9 |

- **Comparison.**
  - *Shape.* The formula is two straight lines in log-log space (clicks and drift are power laws of
    the ratio): monotone, no seams, and it extrapolates on its own. The table is a hand-drawn
    polyline through 14 anchors: also monotone, but the slope changes at every row (a lift at 0.75 is
    a blend of the 0.8 and 0.7 rows) and it only covers what is listed.
  - *Feel.* Identical at the sign (11 clicks, hold 3 cps). The formula is gentler below it: the hold
    rate at 0.9 / 0.8 / 0.7 / 0.6 / 0.5 is 3.7 / 4.6 / 5.9 / 7.9 / 11.1 against the table's 4.2 / 5.5
    / 7.5 / 10 / 13, so more of the sub-weight range is a human's (slowest winning rate at 0.8: 5.5
    vs 6.4 cps, 0.7: 6.9 vs 8.4, 0.6: 8.9 vs 11). Above the sign it is a touch stiffer (ratio 2: 7
    clicks vs 5, ratio 4: 4 vs 3). Both floors are 0.4 (about 18 cps).
  - *Tuning.* Four knobs vs 42 numbers. A formula change moves the whole curve coherently: raise
    DriftPower to 1.15 for the table's harder hard band, but then MIN_RATIO must rise to about 0.43
    (20 cps no longer wins at 0.4 inside 12 s); lower ClicksAtSign for an easier game everywhere.
    The table lets you pin one band without touching its neighbours (e.g. "0.7 must be a 9-cps
    masher") at the cost of keeping all the rows consistent by hand.
  - *Verdict.* Formula stays live: it is the algorithm the user asked for, it spreads the "click a
    lot but still human" range wider, and it is explainable in one sentence ("every halving of your
    strength vs the weight doubles the fall-back and adds ~80 % more clicks"). Flip CURVE_MODE to
    "table" to A/B them in-game; nothing else changes.
- Verified (solo playtest via the official Studio MCP, LiftDevCPS + the LiftDevLog watcher, formula
  mode): ratio 16 @ 5 cps -> hoist after 0.20 s (one click); 0.8 @ 7 cps -> 4.30 s with "CLICK
  FASTER!!" (the table would fail at 7); 0.7 @ 8 cps -> 5.25 s (the table would fail at 8), walk
  18.16 = 25.04 x 0.725; 0.6 @ 8 cps -> timeout fail at 12.00 s (p 0.569); 0.5 @ 15 cps -> 3.22 s,
  walk 13.68; 0.4 @ 20 cps -> 3.96 s, walk 11.34 (x0.45). The sim's predictions were 0.2 / 4.2 / 5.2
  / fail / 3.1 / 3.9. Float edge: 3 x 0.7 / 3 lands a hair under 0.7, so that lift showed the
  "extreme" shout, harmless.

### The shown kg is now a big compressive curve (2026-09-17, user: "make the displayed kg values less, e.g. 12 kg for 200 strength, then 34 kg for 2.2K, then 100 kg for 70K, like it would be a big curve")

- `CucumberLift.DISPLAY = {Base = 1, Low = {Strength = 200, Kg = 12}, High = {Strength = 70000, Kg =
  100}, Jitter = 0.05}`. `Shown(kg)` = `Base + Scale x ln(kg) ^ Power`, with Scale and Power solved
  from the two anchors at load (`displayCurve()`: Power = ln((High.Kg - Base) / (Low.Kg - Base)) /
  ln(ln(High.Strength) / ln(Low.Strength)) = 2.95, Scale = 0.080), then the +-5 % biome/type
  wobble and two significant digits. The three points land: 200 -> 12, 2.2K -> 34 (35 with that
  hash's wobble), 70K -> 100. To move the curve, edit the two anchors in your own words ("12 kg for
  200 strength"); the jitter was cut from 12 % to 5 % so it can no longer reorder neighbouring
  types after this much compression (Spawn: 1.1 / 1.3 / 1.6 / 1.8 / 2.4 / 3.2, zero inversions).
- What the biome signs read now (lightest slice -> the x6.8 tree): Spawn 1.1 -> 3.2 kg, Desert 15 ->
  32, Samurai 32 -> 60, Farm 66 -> 110, Snow 150 -> 230, Underwater 270 -> 390, Volcano 390 ->
  510, Narmek 570 -> 740, Toyland 850 -> 1.1K, Neon 1.4K -> 1.8K. (Before: 1.6 -> 8.9, 98 -> 650,
  ... 77B kg.) Nothing else changed: ShownKg is stamped at spawn (AttachCollectPrompt) and at
  restore (RestorePlaced recomputes from Kg), so saved bases pick the new numbers up on the next
  restore; the requirement (WeightKg) and the bar are untouched.
- Verified (Edit-mode run of the live module + a fresh solo playtest reading the stamped ShownKg
  attributes per biome).

### Heavier cucumbers are slightly bigger; giants weigh more (2026-09-17, user: "make the higher kg cucumbers slightly bigger, size depending on kg's, and make the mutated size cucumbers' kg's a bit higher")

- **Size from the kg.** `CucumberLift.WEIGHT_SIZE = {Type = 0.1, Biome = 0.02}` and
  `CucumberLift.WeightScale(zone, typeName, material, mutations)` = 1 + Type x log10(kg / the biome's
  lightest) + Biome x log10(the biome's lightest / Spawn's 3 kg), where kg is the cucumber's weight
  WITHOUT the giant size mutation (giants keep their own x2 / x3 / x4). So inside a biome the x6.8
  tree is ~8 % bigger than the slice, Golden +3 %, Diamond +6 %, mutations ~+2 % each; across the
  ladder the slice itself grows Desert +4 %, Samurai +6 %, Farm +7 %, Snow +10 %, Underwater +13 %,
  Volcano +14 %, Narmek +17 %, Toyland +19 %, Neon +23 % (a Diamond NEON,FROZEN Neon tree tops out at
  x1.41). CucumberSpawner requires CucumberLift and multiplies `weightScale` into the model scale
  next to TEMPLATE_SCALE and the giant `sizeScale` (both the template clone and the part-built
  slice / cucumber), and the giant placement fallbacks (drop the edge inset, then the spacing) now
  also kick in when `sizeScale x weightScale > 1`, so a bigger normal cucumber never loses its slot.
  Nothing downstream needed a change: the carry copy shrinks to an armful whatever the field size,
  PlaceScale restores the field size on the plot, footprints / reach / prompts read the extents.
- **Giants weigh more.** `CucumberLift.SIZE_POWER` 1.5 -> 1.8: kg x SizeScale ^ 1.8 = x3.5 / x7.2 /
  x12 for the 2x / 3x / 4x giants (was x2.8 / x5.2 / x8). A 4x Spawn tree is 250 kg (was 160); the
  shown weight follows through the display curve.
- Verified (Edit-mode run of the live module for the factors above + a solo playtest reading every
  field model's `GetScale()` against 0.75 x SizeScale x WeightScale from its attributes).

### Prompt colours + centred labels (2026-09-18, user: "remove the 'extreme' tag and just make it say the weight, make it orange; the current orange tags yellow while the easy ones are green; center the 'cucumber' and 'lift' labels, make it look better")

- `CucumberLift.COLORS = {Green, Yellow, Orange, Red}` and the DIFFICULTY rows now use them: trivial /
  easy / medium (ratio >= 1.5) GREEN (130,255,80); hard (1 .. 1.5) and the close / mash rows (0.7 .. 1,
  still with their "Click fast!" / "Mash!" nudges) YELLOW (255,222,65); extreme (0.4 .. 0.7) ORANGE
  (255,150,50) with NO Hint any more -- the prompt shows just the weight (the bar still shouts
  "MASH!!!" during the lift); impossible RED (255,79,105). CucumberPromptClient reads the row's Color
  and Hint, so nothing else changed there.
- The prompt's text column (ObjectText / ActionText / Weight) is a centred stack beside the key
  badge: the three labels sit 8 px in from the badge and from the right edge (`BADGE + 8`, width
  `-(BADGE + 16)`), TextXAlignment Center, at y 4 / 26 / 60 (the action line moved down 3 px so the
  small name no longer touches the big "Lift"); `fitWidth` = BADGE + 16 + the widest label, so the
  column is exactly as wide as the longest line and every line shares its centre.
- Verified (Edit-mode run of Difficulty: ratio 10 / 2 green, 1.2 / 0.9 / 0.75 yellow with the nudges
  on 0.9 and 0.75 only, 0.5 orange with no hint, 0.2 red; solo playtest next to a 20 kg Cucumber Tree
  at strength 11: the billboard read "Cucumber Tree" / "Lift" / "3.2 kg" in rgb(255,150,50), all
  three labels centred on x = 158.0 of the 270 px billboard, y 4 / 26 / 60).

### Four clicks minimum (2026-09-18, user: "you need a minimum of 4 clicks for easy cucumbers, since 1 click instant pick up is too easy")

- `CucumberLift.MIN_CLICKS = 4`, applied in `Params` for BOTH curve modes: the curve's clicks are
  floored to 4 AFTER its fall-back speed is taken (`drift = 0.65 / rawClicks x cps`), so the floor
  only shrinks each click (Gain = 0.65 x (1 + CLICK_MARGIN) / clicks) and the drift is unchanged.
  `CLICK_MARGIN = 0.03` gives the clicks 3 % to spare so the tiny drift of an easy lift never costs a
  5th click at a lazy rate. Formula mode now reads: ratio 3.2 and up 4 clicks, 3 -> 5, 2 -> 7 (6 at
  8 cps), 1.5 -> 8, 1.2 -> 10, 1 -> 11 (unchanged from here down; the hold at the sign is 2.96 cps
  instead of 3.05 because of the margin). Table mode: the 16 / 8 / 4 rows (1 / 2 / 3 clicks) are
  floored to 4 too.
- Verified (Edit-mode run: clicks needed at 3 / 5 / 8 cps = 4 / 4 / 4 at ratio 16, 5 / 4 / 4 at 4,
  5 / 5 / 5 at 3; solo playtest with the LiftDevCPS auto-clicker: ratio 16 @ 5 cps -> hoist after 0.80 s
  on the 4th click, ratio 16 @ 3 cps -> 1.35 s on the 4th click, ratio 3 @ 5 cps -> 1.02 s on the 5th).

### Hands rise with the bar + the key badge hugs the text (2026-09-18, user: "bring E closer to the text"; "using blender mcp or roblox studio (try both) animate users hands where they move up when bringing the strength icon up the bar")

- **Root cause first: the lift pose never reached the avatar.** R15 characters in this place now
  arrive with `AnimationConstraint` joints (LeftShoulder, Waist, Root, ...) instead of Motor6Ds, so
  CucumberLiftClient's `motorsOf` (`d:IsA("Motor6D")`) found NOTHING and the Stepped sampler had no
  joints to write -- the character just stood in its idle while the bar ran (verified: the left hand
  sat at -1.12 studs over the root for the whole lift, the shoulder joint at the idle's 1-7 deg).
  Fix: `motorsOf` accepts `Motor6D` or `AnimationConstraint` (same `Transform` property, same rig
  attachment frame), and `rigFor` refreshes the joint map on every lift (the physique upgrades
  rebuild the joints, so a per-character cache goes stale).
- **Bar -> clip mapping.** `liftTimeFor(p)`: the bar's START (0.35) maps to `LIFT_KNEE` = 10 % of
  the lift clip (hands just off the ground, the cucumber already in them), the green end to LIFT_LEN
  (the load at the chest); below START the hands sink back to the ground as the icon slides to the
  red end. Each click also sets `Rig.Pump` = 0.05 s, decaying at 6/s, so the hands heave a touch on
  every click. The cucumber visual starts at P = 1 (into the hands at once) and rides them the whole
  way instead of floating toward them by progress; a fail still sinks it back (P = 0). Other
  players' lifts use the same mapping.
- **Blender (headless; the Blender MCP addon was not reachable, so `blender -b assets/CucumberAnims.blend
  --python assets/anims/build_cucumber_lift.py` with Blender 4.5).** The clip's hand targets were
  raised: THIGH y -0.95 -> -0.7 at t 0.6, CHEST y -0.2 -> +0.3 (z -0.95) at t 1.0 -- the old "chest"
  was belly height; the wrists now travel -1.96 -> -1.45 -> -0.7 -> +0.3 studs (root-relative, reach
  error 0). Rebuilt CucumberLift.json / .fbx / preview PNGs, regenerated CucumberLiftPoses.lua with
  json_to_poses_module.js (22 frames, 1.4 s) and pushed it by writing `Source` from an Edit-mode
  execute_luau (the official MCP sandbox allows `Source` writes; that is the 12 KB path that
  multi_edit is too fiddly for).
- **Badge.** CucumberPromptClient WIDTH 270 -> 140 is only the minimum: `fitWidth` already hugs the
  widest label, so the billboard is exactly badge + 8 px + the text column + 8 px and the key sits
  next to the centred stack ("Sliced Cucumber" billboard 189 px, badge edge x 50, all three labels
  centred on x 117.5, 48 px from the badge to "Lift"; it was 270 px with the stack centred on 158).
- Verified (solo playtest, ratio 1 at 4 cps, sampled every 0.3 s): left hand over the root -1.29
  (idle) -> -1.70 at p 0.41 (the grip) -> -1.15 at 0.64 -> -0.44 at 0.75 -> -0.05 at 0.83 -> +0.21
  at 0.91 -> +0.30 at 0.98, monotonic with the bar; the cucumber's height matched the hand within
  0.02 the whole way (c = h), shoulder pitch 70 deg at the grip settling to 20 deg at the chest.

### Camera glitch: a lift cut short by nightfall (2026-09-18, user: "camera glitch when picking up cucumber and then night happens. fix")

- **What happened.** Nightfall runs DayNightCycle's return: `CucumberCarryAPI.DropForNight` (which
  cancels a pending lift -> the client gets `Cancel`), then `character:PivotTo(lobby)`, and a
  moment later ZombieRaidClient's den cutscene takes the camera (Scriptable + a CFrame every
  Heartbeat, restores to Custom at its end). The lift camera's way out was a 0.4 s glide back to the
  ABSOLUTE camera CFrame saved at the lift start -- a spot in the biome the character had just been
  teleported away from -- bound at RenderPriority Camera + 1, so for that 0.4 s it overrode the
  cutscene's CFrame writes, and at the end it set `CameraType = Custom` under the running cutscene:
  the default camera and the cutscene then fought over the CFrame for the cutscene's whole length.
- **Fix (CucumberLiftClient, camera block).** (1) The way back is remembered relative to the
  character (`Cam.Saved.Offset` = root-space camera CFrame) and, if the character is gone or has
  moved more than `CAM_SNAP_DISTANCE` (20 studs) since the lift began (night return, respawn), the
  camera is handed straight back with no glide (`cameraRestore`). (2) `cameraYield`: every frame the
  binding checks that the camera is still ours -- CameraType still Scriptable and `cam.CFrame` still
  equal to what we wrote last frame (`Cam.LastWrite`); if another controller wrote it or reset the
  type, the lift unbinds and leaves the camera exactly as it is, never touching CameraType / FOV.
  `cameraOut` after a yield is a no-op (`Cam.Active` false).
- Verified: a lift started 1.2 s before a real nightfall -- at the flip the character jumped 75 then
  204 studs to the lobby; the camera went Custom 13 studs from the character on the very next sample
  (no glide), the cutscene then ran Scriptable at its den and handed back to Custom at 13 studs when
  it finished. A fake cutscene during a lift (Scriptable + CFrame writes 50 studs up for 1.5 s, then
  Custom): the lift camera yielded on the first foreign frame (distance 14 -> 50 with no fighting),
  stayed hands-off, and the camera settled at 14 studs Custom when the other controller let go.
  Note: the official MCP sandbox cannot fire `DayNightAPI.Force` (capabilities), so the night was
  timed from `PhaseEndsAt`.

### Freeze Tower range disc removed (2026-09-18, user: "get rid of this visible range around one of the towers in my base")

- The green translucent circle on the ground around a placed Freeze Tower was DefenceService's
  `FrostAura` (a Neon cylinder of FROST.Radius x 2, pulsing). `FROST.ShowAura = false` now skips
  creating it; the slow / chill / pulse gameplay, the orb spin, the frost puffs on zombies and the
  snow off the orb are untouched. Set `ShowAura = true` to bring the disc back. The aura pulse /
  move / destroy code already tolerated a missing aura, so nothing else changed.
- Verified: a fresh solo playtest restored the base (Flooring x14, FreezeTower x1, Mortar x1,
  SpikeTrap x30, Staircase x1, TeslaCoil x1) with 0 FrostAura parts in the workspace and the
  FreezeTower model registered (no Broken flag, all its authored parts present).

### Coins are now Cash (2026-09-18, user: "replace mentions of coins with Cash and replace all coin icons in game with 15402858705")

- **Icon.** 15402858705 is an Image asset ("Money", VectorIcons), so it is used directly as
  `rbxassetid://15402858705`. Every live GUI image that used the coin (rbxassetid://15402839520) was
  swapped in place: HUD Counters.CoinIcon, HeadbandShop BuyButton.CoinIcon, the ShopPanel's
  CoinsTab.Icon and the 13 CoinIcons under the six pack cards, BuildMenu's BuildCard.CostRow.CoinIcon
  (17 objects), plus the PlacedCucumberCardClient `COIN_ICON` constant that draws the plot cards'
  income line and the "+X" popups. The ServerStorage *Backup* GUI copies were left as they were.
- **Text.** Player-facing strings only; the data key `Coins` (DataService / Data.Coins / attributes
  CoinsAmount, CoinsPerSec), instance names (CoinIcon, CoinValue, CoinsTab, CoinPack*) and the
  AdminAction "coins" command are unchanged so saves and remotes keep working. Changed: the
  leaderstat "Coins/s" -> "Cash/s" (LeaderstatsService, the player list), "Not enough Cash! You
  need N more." (EggShopClient), "Buy (N Cash)" egg prompts (EggShop), "Need N more Cash" (BuildService,
  BuildMenuClient, PlotUpgradeService, HeadbandService; GymService "Need N Cash"), "Sold X for N Cash"
  (BuildMenuClient), "Buy the X first (N Cash)" (HeadbandService), the shop tab "CASH" and header
  "CASH PACKS -- FILL YOUR WALLET" (the coin emoji became a banknote), the admin panel label "CASH"
  and its reset warning, and the server logs that named the currency. The old coin
  Backup GUIs in ServerStorage still say COINS.
- Gotcha: the official MCP `multi_edit` with `replace_all = true` silently applied nothing in two of
  three scripts (it reported success); every occurrence was then edited with its own unique context.
- Verified in a solo playtest: leaderstats read "Strength, Cash/s"; the HUD icon, the shop tab icon
  and the build card icon all report rbxassetid://15402858705 (loaded); no TextLabel in the
  PlayerGui says "coin" any more; all edited scripts compile.

## 2026-09-18 The night wall no longer lifts or traps the guardians (collision groups)

- **Bug (observed 2026-09-18).** `workspace.Map.Borders.NightBarrier` (18 BaseParts; the largest is
  1437 x 35.5 x 113 studs, CanCollide, anchored) is tweened by DayNightCycle from 5 studs under the biome
  floor (top -234.2) to 35 studs above it (top -194.5) at nightfall, and set straight to the raised pivot
  when a server starts mid-night. The ten guardian rigs in `workspace.Guardians` (unanchored Humanoid
  models from GuardianService, seated at y -223..-228 on the `<Name>_Seat` models) stand inside that
  footprint, so on a normal night the wall carried them up and they spent the whole night sitting on TOP
  of it at -193.5; on a mid-night start they spawned inside the solid wall, physics ejected them downward
  past seat Y - 40, and GuardianService's fell-off-the-world catch (TickOne) re-seated them inside the
  wall again: ten "fell off the world and was put back" warnings about twice a second, all night.
- **Fix.** Two PhysicsService collision groups, `NightBarrier` and `Guardians`, set not to collide with
  each other. BOTH scripts register both groups and the rule (an `IsCollisionGroupRegistered` guard plus
  pcall, so it is idempotent and load order does not matter); everything happens at runtime on every
  server, nothing is stored in the place, and Default is untouched, so players are still blocked by the
  wall exactly as before.
  - `SSS.DayNightCycle`: every BasePart under NightBarrier gets `CollisionGroup = "NightBarrier"` in the
    same loop that anchors it, before LoweredPivot / RaisedPivot are computed.
  - `SSS.GuardianService`: `Spawn` sets `CollisionGroup = "Guardians"` on every BasePart of the clone (in
    the loop that unanchors them, before the model is parented), on the parked `<Name>_Seat` parts, and
    through `model.DescendantAdded` on anything parented under the guardian later (a held cucumber from
    HoldCucumber), so re-seating (Sleep / Rest / TickOne's PivotTo) and a rebuild keep the group. The two
    ground probes (`GroundAt` and `SeatSpot.groundNear`) now cast with `RaycastParams.CollisionGroup =
    "Guardians"`, so they see through the raised wall the way the body does (a `GroundAt` from +60 studs
    during a mid-night start would otherwise have reported the wall top). The TickOne catch itself stays,
    a chase can still run off an edge; only the wall as a trigger is gone.
  - Mirrors: `live-2026-09-16/DayNightCycle.server.lua` and `GuardianService.server.lua` were regenerated
    from the live scripts (same byte checksum as the Studio Source).
- **Verified (solo playtest through the official Roblox_Studio MCP; this script's NightDurationSeconds
  attribute is 45 s at the moment, days 180 s).**
  - In the play server: NightBarrier<->Guardians collidable false, NightBarrier<->Default true,
    Guardians<->Default true; all 18 barrier parts in NightBarrier, all 361 guardian parts and the 56 seat
    parts in Guardians, the player's root in Default.
  - Normal nightfall (day 4887): a server-side sampler parked the player over the Spawn field 3 s before
    the flip (inside the lane at x 1075) and at the flip the character stood on the lobby return point
    (1189, -225, 130): the night return still works. The wall top went -234.2 -> -194.5 within 1 s and
    every one-second sample for the next 17 s of night read 10 guardians at y -228.3..-223.2 (seat
    height), 0 "fell off the world", 0 warnings from LogService.
  - Mid-night start: play stopped and restarted with about 27 s of night left; the new server booted
    straight into "Night after day 4887" (no Day line), spawned the ten guardians inside the raised wall
    (top -194.5) and they sat at -228.3..-223.2, Asleep, in group Guardians; the console showed no
    warning at all.
  - The same server then ran through the dawn: wall top back at -234.2, 10 guardians still at
    -228.3..-223.2, "Day 4888 started" in the console with no GuardianService warning anywhere in the
    session (LogService count 0 across the hand-over as well).

### Everything is Cash now, data included (2026-09-18, user: "rename everything to Cash even data since there's no data in this game")

- A token swap Coins -> Cash / coins -> cash / COINS -> CASH, then Coin -> Cash / coin -> cash /
  COIN -> CASH, applied from an Edit-mode execute_luau to every live script Source (27 scripts: the
  DataService template key is now `Cash`, DataService.Get/Increment(player, "Cash"), Data.Cash,
  CashPerSec, COINS_KEY -> CASH_KEY, the leaderboard fixture "LeaderBoard Cash", AdminAction "cash",
  dev hooks "cash:<n>", sounds "Cash Tick" / "Boss Cash Pickup", catalog fields), to 41 instance
  names (HUD Counters.CashIcon / CashValue, ShopPanel CashHeader / CashSection / CashPack* /
  CashIcons.Cash1-5 / CashTab, AdminPanel CashLabel / CashBox / CashSet, BuildCard CashIcon, the two
  sounds, the lobby leaderboard), to 10 attribute names (the shop packs' CashAmount) and 3 string
  attribute values (CashTab @Section = "Cash", the HUD @Reference note). All 27 scripts compile.
- Left alone on purpose: the ServerStorage *Backup* copies, and physical props whose "coin" is an
  object, not currency: ServerStorage.Builds.Fun.ArcadeCabinet (State_CoinDoor*, Pivot_CoinDoorHinge,
  the Notes text), VendingMachine (Pivot_CoinSlot) and the Wild West vault's RCoin parts.
- Saved profiles: the old `Coins` key is simply orphaned; ProfileStore's reconcile adds `Cash` at the
  template default (the user confirmed there is no player data to keep). The same swap was run
  over the 44 non-backup disk mirrors (swap_cash_disk.py recipe: six ordered replaces, plural first).
- Verified in a solo playtest: Data has Cash (no Coins), leaderstats "Strength, Cash/s", the HUD's
  CashValue label tracks Data.Cash, the placed-cucumber income keeps paying into Cash (it grew over
  6 s), the shop CashTab carries Section = "Cash", the admin panel's CashSet / CashBox / CashLabel
  exist, and the console showed no errors from the swap.

### Lift prompt in the default Roblox prompt's look (2026-09-18, user: "make the prompt lift UI look like this: Lift instead of Steal, Cucumber (X kg) instead of Egg, keep the X kg colour coded")

- CucumberPromptClient now draws the reference layout: a soft dark rounded panel (`root` itself:
  black at PANEL_TRANSPARENCY 0.55, UICorner 12), the key badge (44 px, PAD 10 in from the left) and
  two LEFT-aligned lines beside it -- ObjectText small (GothamMedium 16) reading
  `Cucumber <font color="#hex">(1.1 kg)</font>` with the kg in the difficulty colour
  (CucumberLift.COLORS green / yellow / orange / red via Color3:ToHex), and ActionText ("Lift")
  in GothamBold 24 (FONT_ACTION was FredokaOne; the key glyph uses it too). The separate Weight row
  and its "Click fast!" / "Mash!" nudge words are gone from the prompt: the colour carries the band
  and the lift bar still shouts during the lift. HEIGHT 66 (was 86), rows at y 7 / 28, thinner
  outlines (1.2 / 1.6), `fitWidth` = PAD + badge + PAD + the wider line + PAD.
- Verified in a solo playtest (see the numbers in the session notes): the billboard reads
  "<name> (<kg>)" / "Lift" with the kg span coloured, both lines share the same left edge beside the
  badge, and the panel hugs the two lines.

### Prompt sized in studs, at torso height, no panel (2026-09-18, user: "prompt UI doesn't scale up when bringing the camera further, keep it the same size no matter position; bring the prompt to user torso height; remove the background behind the prompt")

- **Studs, not pixels.** The BillboardGui is now sized in studs (`HEIGHT_STUDS` 1.1 tall, width =
  the px layout x `STUDS_PER_PX`), so it shrinks with distance like any world object instead of
  staying a fixed number of pixels that looks bigger and bigger as the camera backs away -- the
  same rule as the owner badge. The px layout (WIDTH x HEIGHT, badge 44, PAD 10, the two text
  lines) is unchanged: `root` is the px layout box and ONE UIScale maps it onto the stud-sized
  billboard every RenderStepped (`fit = gui.AbsoluteSize.Y / HEIGHT`) multiplied by the press / pop
  animation value, which now lives in a NumberValue `Anim` (the hold 0.92 / release 1 / trigger 1.15 /
  pop-in 0.7 -> 1 / hide -> 0.7 tweens target it) because UIScales do not stack. `fitWidth` grows the
  px box and the stud width together. `hide` keeps the fit loop alive until the shrink tween ends.
- **Torso height.** ExtentsOffset is zero and `placeAtTorso` sets `StudsOffsetWorldSpace.Y` =
  UpperTorso.Y - the prompt part's Y every frame, so the prompt floats level with the player's
  chest over the cucumber whatever its size (the old top-edge + PROMPT_LIFT_CAP rule is gone).
- **No panel.** `root` is transparent again; the badge keeps its own translucent fill and ring.
- Verified in a solo playtest (chrrxs bridge): the billboard's on-screen height halved when the
  camera was moved from 8 to 16 studs away (a stud-sized billboard), its world position matched the
  player's UpperTorso height, and the root's BackgroundTransparency read 1.

### Prompt size held steady across the zoom range (2026-09-18, user: "prompt ui gets smaller as you go further; refer to the base owner UI for how to make overhead ui the same size")

- The plot owner badge (PlotBadges) uses the very same technique -- a BillboardGui sized in studs --
  it just is 14 x 10 studs and 27 studs up, so it never reads small. The prompt at 1.1 studs did.
  Now `HEIGHT_STUDS` = 2.0 and the per-frame fit clamps the on-screen height to `MIN_PX .. MAX_PX`
  = 56 .. 120 px (before the press animation): close up it stops growing, far away it stops
  shrinking, and in between it is world-anchored at the cucumber's scale. Measured in a solo
  playtest (1301 x 611 viewport): content 120 px at 6 studs (ceiling), 73 px at 12, 56 px at 24 and
  at 40 (floor); the badge 80 / 49 / 37 / 37 px. Torso height and the missing panel re-checked.
- Tuning: MIN_PX / MAX_PX are the band, HEIGHT_STUDS the world size inside it. Set MIN_PX = MAX_PX
  for a fixed-pixel prompt, or MIN_PX 0 / MAX_PX huge for a pure stud one.
- Session gotcha: with two Claude sessions on one Studio, `solo_playtest start` can answer "already
  running" and the evals then run inside the OTHER session's playtest (old scripts!) -- and a blind
  `stop` kills their session (it happened once here). Check `solo_playtest status` first and only
  stop a playtest you started.

### The kg sits beside "Lift" (2026-09-18, user: "put the X kg beside lift label")

- CucumberPromptClient: the name line is just the (colourised) name; the action line is
  `Lift <font size="18" color="#hex">(1.3 kg)</font>` -- ActionText has RichText on, the kg span is
  OBJECT_SIZE + 2 px (a size under the bold 24 px "Lift") in the difficulty colour. Non-cucumber
  prompts (the plot board) still show a plain action. Verified in a solo playtest at a yellow-band
  strength: "Cucumber" over "Lift (1.3 kg)" with the span in rgb(255,222,65), both lines on the same
  left edge.

## Index panel order (2026-09-18, user: "put the cucumbers in the index frame in order of worst to best, left to right")

The collection index (`StarterGui.CucumberMenus.IndexPanel`, rendered by `IndexView` from the
`CucumberCollectionBook` payload) listed each biome's cucumbers ALPHABETICALLY: the server module
`ServerStorage.CucumberAdventure` built the per-zone catalog in `M.SetCatalog` with a plain
`table.sort(names)`. The grid is a 4-wide `UIGridLayout` (Horizontal, TopLeft, LayoutOrder = card
index), so the catalog order is the on-screen order left -> right, top -> bottom.

- `SetCatalog` now sorts by break value ascending (`CucumberValues.RewardOf(zone, name)`, the same
  number the plot income uses), commoner spawn weight first on a tie, then the name. Card numbers
  `#01..` follow the same order (worst = #01). The `Seen` keys are `zone:name`, so saved progress is
  unaffected; the equip/unlock logic only counts names.
- Result per tab (Spawn): Sliced Cucumber, Cucumber, Slice Stack, Vined Cucumber, Flowered Cucumber,
  Cucumber Tree. Toyland / Neon (generic pool): Sliced Cucumber, Cucumber, Giant Cucumber, Cucumber Tree.
- Mirror: `new-map-cucumber-game/CucumberAdventure.lua`; backup of the module before the change:
  `backups/NewMap_CucumberAdventure_before-index-order_2026-09-18.rbxm`.

### Shop cash-pack icons 2-6 (2026-09-18, user: "in the shop UI for the cash icons for purchase cards 2-6 use these icons" + five Money-2 .. Money-6 decal links)

- The five links are DECALS (economy AssetTypeId 13); an ImageLabel needs the image inside, so
  they were resolved with InsertService:LoadAsset from the chrrxs edit peer (the official MCP
  sandbox refuses LoadAsset): Money-2 15402862297 -> rbxassetid://15402862269, Money-3 15402864644 ->
  15402864619, Money-4 15402867181 -> 15402867151, Money-5 15402870055 -> 15402870039, Money-6
  15402872470 -> 15402872439. Card 1 (CashPack10000) keeps the Money icon 15402858705.
- Applied to every icon under `CashIcons` of the cards in price order (LayoutOrder 1-6):
  CashPack50000 (1 icon) Money-2, CashPack100000 (1) Money-3, CashPack250000 (2) Money-4,
  CashPack500000 (3) Money-5, CashPack1000000 (5) Money-6 -- the icon COUNTS per card were left as
  authored. Read back in a solo playtest: all 13 icons carry the new ids (IsLoaded stays false on the hidden panel, the untouched card-1 icon included, so that flag says nothing). The
  hud-shop/build_shop.lua builder still writes the single Money icon; re-running it would revert
  these (set the ids there too if the panel is ever rebuilt).

### One centred icon per cash card (2026-09-18, user: "for each card in cash shop just use one icon in the center")

- Every CashPack card's `CashIcons` now holds a single `Cash1` laid out like the 10K card's: 126 x 126
  px, AnchorPoint 0.5/0.5, Position 0.5/0.5 of the 246 x 150 icon area, ZIndex 9 (the three Sparkle
  labels stay). Removed: CashPack250000.Cash2, CashPack500000.Cash2-3, CashPack1000000.Cash2-5.
  No script names those icons or walks CashIcons (checked). The Money-2..6 artwork from the previous
  change stays on cards 2-6. The hud-shop/build_shop.lua builder still authors the old stacks.

## HUD counters show one decimal (2026-09-18, user: "for the cash and strength indicators display the first decimal like 200.1M")

`StarterGui.CucumberHUDDesign.HUDClient`'s `Compact` used to print three-digit mantissas as
integers (200.1M -> "200M") and trimmed ".0". Now every value from 1000 up prints exactly one
decimal, floored (200,149,999 -> "200.1M", 1,000 -> "1.0K", 999,999 -> "999.9K"); below 1000 it
is still a plain integer, now floored as well (999.6 -> "999", it used to round up to "1000"). Only the two HUD counters (Cash / Strength) use this formatter; the
playerlist and the plot cards still use NumberAbbrev's 3-significant-digit style.
Backup: `backups/NewMap_HUDClient_before-one-decimal_2026-09-18.rbxm`; mirror `hud-shop/HUDClient.client.lua`.

## Silent guardian catch (2026-09-18, user: "get rid of these notifications when taking cucumber")

A guardian catch used to throw two toasts at once: the server's
`"<Guardian> knocked the <Cucumber> out of your hands!"` (or `"<Guardian> hit you!"` when there was
nothing to drop) from `GuardianService`'s catch block, and `"A <Guardian> knocked you back!"` from
`ZombieRaidClient`'s `Hit` handler (the guardian reuses the zombie knockback remote).
- `GuardianService`: the catch block no longer calls `Toast`; the knockback + the cucumber falling
  at your feet are the whole feedback. Its `Knockback` payload now carries `Silent = true`.
- `ZombieRaidClient` `Hit`: the "knocked you back!" toast only fires when the payload is not
  Silent, so zombie hits during the night raid still announce themselves.
Backup: `backups/NewMap_GuardianService+ZombieRaidClient_before-silent-catch_2026-09-18.rbxm`;
mirrors `guardian-chase/GuardianService.server.lua`, `zombie-raid/ZombieRaidClient.client.lua`.

## Guardian fling (2026-09-18, user: "make the knockback higher when hit by a guardian, I want the player flung")

The catch throw is still strength-scaled (2026-09-17 rule) but the whole ladder is bigger and the
AIR TIME now rides the same log2 curve, which is what sets the height: ZombieRaidClient's
`knockback` flies a ballistic arc that lands after `Seconds`, so the peak is gravity x s^2 / 8.
- `GuardianCatalog`: `KNOCKBACK_MIN 3 -> 6`, `KNOCKBACK_MAX 14 -> 30`, new `KNOCKBACK_TIME_MIN 0.5`
  / `KNOCKBACK_TIME_MAX 0.9` (weak = far and ~20 studs up, strong = 6 studs and a ~6-stud hop; it
  used to be a flat 0.35 s = ~3 studs up). `KNOCKBACK_TIME` / `KNOCKBACK_DISTANCE` stay as fallbacks.
- `GuardianService`: `KnockbackFor` returns `distance, seconds, ratio`; `Knockback(entry, player,
  dir, distance, seconds)` puts the seconds in the Hit payload. Zombie hits are untouched (their own
  service sends its own Distance / Seconds).
Backup: `backups/NewMap_GuardianService+Catalog_before-fling_2026-09-18.rbxm`; mirrors in `guardian-chase/`.

## No record toasts, no guardian hits (2026-09-18, user: "Get rid of all collection record notifications" / "Get rid of being able to hit and knock out guardians as well as those notifications for guardians")

- `CucumberAdventureClient`: the `Records` payload no longer queues toasts ("New heaviest cucumber
  secured!", "First Impossible carry secured!", "Close call!...", "New discovery! ...",
  "... collection complete!"). The server still fires `Records` (IndexController refreshes the
  Index panel on it) and still saves the progress. The `Rescue` hint and the night countdown stay.
- `StarterPack.Bat.BatServer`: the GuardianAPI sweep is gone - the bat only hits zombies.
- `GuardianService`: `DamageGuardian` is a stub that returns false (the hit counter, the 60 s
  knockout, the high-heat mutated drop and its toasts are retired; `ServerStorage.GuardianAPI`
  still exists and always refuses). The "<guardian> is waking up!" toast and the server-wide
  "<player> escaped <guardian> with a <size> <cucumber>!" broadcast are removed too, so the
  guardian system shows NO toasts any more (Toast / Broadcast helpers + GuardianClient's handler
  remain, unused). Catalog STUN_* constants are now dead knobs.
Backups: `backups/NewMap_GuardianService+AdventureClient_before-no-stun_2026-09-18.rbxm`,
`backups/NewMap_StarterPack_Bat_before-no-guardian-hits_2026-09-18.rbxm`.

## Toyland + Neon get hand-modelled cucumbers (2026-09-18, user: "Build these using blender MCP then import to roblox using my GROUP roblox opencloud key. Then implement into my game new map cucumber game Toyland and Neon biomes for their cucumbers, completely replacing their current cucumbers.")

The last two biomes used to spawn the part-built GENERIC pool (Cucumber / Giant Cucumber / Sliced Cucumber / Cucumber Tree, tinted purple or cyan). They now have their own 7-model sets, built in Blender from the user's reference sheet: source, briefs, renders and asset ids live in `../cucumbers/` (see `CUCUMBERS-REV3.md` and the "Rev 3" section of `../cucumbers/README.md`).

| weight | Toyland (reward) | Neon (reward) |
|---|---|---|
| 25 S | Toy Slice (3) | Neon Slice (3) |
| 53 | Lego Cucumber (8) | Electro Cucumber (8) |
| 25 | Jack-in-the-Box Cucumber (17) | Neon Grid Cucumber (17) |
| 12 | Toy Rocket Cucumber (37) | Hologram Cucumber (37) |
| 6 | Pinwheel Plant (82) | Neon Palm (82) |
| 3 | Building Block Tree (173) | Neon Tree (173) |
| 1 T | Toy Train Cucumber (360) | Cyber Cucumber (360) |

The sheet lists each biome common -> rare, left to right; the rarest is the "T" landmark the spawner always keeps one of, on the same 7-row reward ladder Samurai / Volcano use.

**What changed in the place:**
- `ServerStorage.Assets.BreakableModels` + `ReplicatedStorage.CucumberIndexPreviews`: +14 each (74 / 74), named `"<Zone> <TypeName>"` (so four doubled: `Neon Neon Slice`, `Neon Neon Grid Cucumber`, `Neon Neon Palm`, `Neon Neon Tree`, the `Desert Desert Palm` convention). Same Hitbox / Shadow / centred-pivot contract as the other 60; models carry attribute `Rev3 = true`. Installed by `../cucumbers/install_rev3.lua` (`stage` / `build` / `add` / `verify` / `remove`).
- `CucumberSpawner`: `RAW.Toyland` + `RAW.Neon`; `LEGACY_TYPES` (old generic name -> new type of the nearest value: Sliced Cucumber -> slice 3->3, Cucumber -> Lego/Electro 8->8, Giant Cucumber -> Toy Rocket/Hologram 45->37, Cucumber Tree -> Building Block Tree/Neon Tree 140->173) used by `TypeByName` only, so old plot saves come back as the new models; a startup warn for any RAW name missing from `CucumberValues.REWARDS`. TYPES / ZONE_COLOR stay but no zone rolls them any more.
- `CucumberValues.REWARDS`: Toyland + Neon rows (GENERIC stays for the legacy names).
- `CucumberCarry.RestorePlaced`: a migrated record (the spawner answered with a different TypeName) is re-stood the way `Place()` does: saved x/z/yaw from the footprint box, resting on the plot surface, clamped inside the plot, new display name ("Golden Giant Cucumber" -> "Golden Hologram Cucumber").
- `BaseSaveService`: cucumber records that fail to restore are KEPT (`Kept[player]`, appended to every snapshot) instead of being wiped by the 30 s heartbeat - the "(kept in the save)" message is now true for cucumbers.
- `StarterGui.CucumberMenus.IndexView`: the purple / cyan repaint of Toyland / Neon previews is gone.
- `GuardianService.HoldCucumber`: welds every part of the carried decoy to its root before unanchoring (template cucumbers have no welds; only the Hitbox used to follow the guardian).

**Verified in a solo playtest (2026-09-18/19):** no spawner warnings; 6 + 6 field cucumbers of the new types with ground gap 0.00 (slices laid flat, 1.1-1.4 tall); all 14 types + all 8 legacy names through `SpawnCarried`; a saved "Golden Giant Cucumber" (Neon) restored as "Golden Hologram Cucumber" exactly on the plot surface with income stamped; a forced unrestorable record survived Reload + Snapshot and was cleaned up; index rows worst -> best with the real models on the cards (72 total); every new holder has its prompt on the Hitbox; no script errors. Mirrors: `live-2026-09-16/` (+ `IndexView.lua`). NOT saved / published by me. **Publish note:** old servers cannot restore the new names and would drop them through the heartbeat, so use "Shut Down All Servers" when publishing.

## Cucumber cash line = green "$" text (2026-09-19, user: "make overhead cucumber cash indicators green and replace the cash icon with $ text so it should say $cash/s in green")

`StarterPlayerScripts.PlacedCucumberCardClient`: the card's cash line is now plain text `$50K/s` and the rising income popups `+$50K`, both in the HUD cash counter's colours (text 65,235,20, UIStroke 12,12,12, same FredokaOne / 2.4 px stroke / stud sizing as before); the cash ImageLabel (`CASH_ICON`, `ICON_FRAC`) is gone and `CashLine` returns `t, stroke, row`. Pushed as surgical hunks (`pets-remake/mkpatch.py` + `apply_patches.lua`). Verified in a solo playtest: 4/4 cards and 4/4 popups read `$...` / `+$...` in green with no icon, screenshot checked. Mirrors: `PlacedCucumberCardClient.client.lua` (root + `live-2026-09-16/`). NOT saved / published by me.

## Owner badge 6 studs higher and 1.25x bigger (2026-09-19, user: "bring the overhead base owner tag 6 more studs up and make it 1.25x bigger")

`ServerScriptService.PlotBadges`: `BADGE_HEIGHT` 27 -> 33 (the badge's centre, above the plot surface) and `BADGE_W, BADGE_H` 14.06 x 10.31 -> 17.58 x 12.89 studs (x1.25; the layout is scale-only, so the headshot rings and the name grow with it). Being bigger, its bottom edge rises 6 - 1.29 = 4.7 studs and its top 7.3. Verified in a solo playtest: anchor 33.00 studs above the plot top, gui 17.58 x 12.89 (no screenshot: the Studio window was minimized). Mirror `PlotBadges.server.lua` updated. NOT saved / published by me.

## Slow Mode button hides on the bench press (2026-09-19, user: "when user is on treadmil hide the slow mode button" - there is no treadmill; the user picked the bench press)

`StarterGui.CucumberHUDDesign.SlowModeClient` (written by another session; mirror now `SlowModeClient.client.lua`): the `LeftMenu.SlowMode` row is hidden while build mode is on (as before) OR while the character's `Humanoid.SeatPart` is a bench seat (`LieSeat`, or any seat under a model tagged `PlotBench`); a SeatPart watcher is re-attached on every CharacterAdded. Verified in a solo playtest by `LieSeat:Sit(humanoid)` from the server: visible -> hidden on the bench -> visible after the SeatWeld was removed (the bench's walk-on SeatTrigger then re-seated the character and the row hid again, as it should). NOT saved / published by me.

## Build-mode prices in green "$", per-defence limits with [X/Y] cards, and a working Boost Pad (2026-09-19, user: "in build mode instead of cash icon do $ symbol and state the price in green not gold so it would say $price. also make it so u can place 3 of each defense ... in each card above the icon put a white label that says [X/Y] ... for towers make it so u can only place 1 of it (so max 1 freeze tower and 1 tesla coil) and ... only 1 boost pad. Make the boost pad functional - prompt 'Speed up' on it and triggering prompt shakes screen with zap sound effect, makes u 2x faster for 15 seconds. Make it so every base expansion upgrade, limits for each defense increases by 1 ... except for boost pad - that limit always stays at 1")

**Prices.** `BuildMenuClient.MakeCard` writes `"$" .. BuildCatalog.FormatCost(Cost)` in the HUD cash green (65,235,20) and destroys the card's `CostRow.CashIcon` (the template still has it; the client drops it per card, so re-running `build_buildmenu.lua` cannot bring the gold icon back silently). The build-mode money toasts follow: "Need $1,500 more" (client + the server's refusal) and "Sold Turret for $1,250".

**Defence limits.** Shared rule in `BuildCatalog` so the card and the server agree:
`LIMITED_CATEGORY = "Defences"`, `LIMIT_BASE_DEFAULT = 3`, `LIMIT_BASE = {FreezeTower = 1, TeslaCoil = 1, BoostPad = 1}`, `LIMIT_FIXED = {BoostPad}`, `LimitOf(key, plotLevel) = base + plotLevel` (fixed keys never grow), plus `IsLimited(key)` (its template's Category) and the attribute prefixes `BuildCount_` / `BuildLimit_`.
By plot level 0..6: SpikeTrap / Turret / Catapult / Mortar / Minigun / LaserGate **3..9**, FreezeTower + TeslaCoil **1..7**, BoostPad **1 always**.
- `BuildService.Place` checks it after the cooldown and BEFORE `Validate` and before any Cash moves, refusing with "Turret limit reached [3/3]"; on success it returns `(true, placed, limit)` so `BuildMenuClient.TryPlace` takes the build off the mouse at the cap. `Move` and `RestoreBuild` are NOT capped: a base that is already over a limit (saved before this, or after an admin level reset) keeps everything and is only refused NEW placements.
- `PublishCounts(player)` (deferred) stamps `BuildCount_<Key>` / `BuildLimit_<Key>` on the player for every Defences key; `WatchPlot` triggers it from `Placed` ChildAdded/ChildRemoved (place, sell, restore, ClearBuilds, plot release) and from the plot's `Owner` / `PlotLevel` attributes, and `DataService.OnProfileLoaded` covers the join. Client-side counting was rejected: StreamingEnabled can stream a plot out.
- Cards: defence cards get a white `[X/Y]` `Count` label (a clone of `Title`, cap 16) at y 0.03..0.15 and their `View` moves to 0.16..0.62, so it sits directly above the preview. `RefreshCounts()` runs on every `player.AttributeChanged` for those prefixes and on `OpenCategory` (cards are built once per session). Picking at the cap = fail sound + red flash + "… limit reached [3/3]" and the build never reaches the mouse.

**Boost Pad.** New `ServerScriptService.BoostPadService` + `StarterPlayerScripts.BoostPadClient` (mirrors in `build-mode/`).
- Every placed pad (tag `PlacedBuild`, BuildKey `BoostPad`; placed, restored or moved) gets a Custom-style `SpeedUpPrompt` ("Boost Pad" / "Speed up", E, hold 0, 12 studs) on its `TreadDeck`, tagged `BoostPadPrompt`. It cannot be authored on the source model: `MakeTemplate` strips prompts. Broken pads (`BuildHealthService`) have it disabled until they mend; 1 s per-player trigger cooldown; anyone may use a pad.
- Trigger sets the player attribute `SpeedBoostUntil = GetServerTimeNow() + 15`. `StrengthProgressionServer` multiplies EVERY speed it writes (refresh, the post-Physique restore, the respawn line) by 2 while that is ahead, listens to the attribute and schedules the drop-back at expiry; `CucumberLiftClient`'s post-lift restore applies the same multiplier. Re-triggering restarts the 15 s and never stacks. `CharacterRemoving` clears it, so death / respawn / admin reset end it.
- `BoostPadClient` plays `SoundController.PlayFX("Zap")` and shakes the screen with a fading `Humanoid.CameraOffset` jitter (0.5 s, scaled by camera distance, skipped while the camera is Scriptable - lift / cutscene / hatch). It also sets pad prompts' `MaxActivationDistance` to 0 locally while the HUD `BuildMode` attribute is on, so a click in build mode selects the pad instead of boosting.

Reviewed by three independent agents before the push (no client defects; three low-severity fixes applied: the trigger cooldown, the zoom-scaled shake, the "$" toasts). Backup `backups/NewMap_build-limits-boostpad_before_2026-09-19.rbxm`. Mirrors updated: `build-mode/BuildCatalog.lua`, `build-mode/BuildService.server.lua`, `build-mode/BuildMenuClient.client.lua`, `build-mode/BoostPadService.server.lua`, `build-mode/BoostPadClient.client.lua`, `live-2026-09-16/StrengthProgressionServer.server.lua`, `CucumberLiftClient.client.lua`. **Do not re-run `base-save/install.lua`**: its `base-save/BuildService.server.lua` is a 2026-09-12 copy and would revert all of this. NOT saved / published by me.

**Known gap (low, exploit-only):** between joining and BaseSaveService finishing the restore, `CountPlaced` sees an empty plot, so someone firing `requestBuildPlacement` directly could push past a cap; the restore then adds the saved builds on top. A `BaseRestoring` flag on the player, checked in `Place`, would close it.

**Playtest-verified (2026-09-19, test account's Plot 5 at PlotLevel 2):** cards read "$500".."$5,000" in green (65,235,20) with no cash icon and a white [X/Y] at y 0.03 over a View moved to 0.16; the 9 limits published were SpikeTrap/Turret/Catapult/Mortar/Minigun/LaserGate 5, FreezeTower/TeslaCoil 3, BoostPad 1 (= base + level 2), and a legacy over-limit base rendered [30/5] for its 30 spike traps. Picking a capped build never reaches the mouse; the server refused with "Boost Pad limit reached [1/1]" and "Turret limit reached [5/5]"; placing the 5th Turret returned (true, 5, 5) and the card went [4/5] -> [5/5] live; selling all 5 put it back to [0/5]. The restored pad carried its SpeedUpPrompt on TreadDeck ("Boost Pad" / "Speed up", Custom, E, hold 0, 12 studs, LOS off), MaxActivationDistance 0 in build mode and 12 after leaving. The boost: WalkSpeed 120 -> 240 on trigger, back to 120 after 15.1 s, Zap played and the camera shook 0.45 studs. NOT verified by a real key press: an unfocused Studio never SHOWS prompts (PromptShown never fires), so the trigger was driven by setting SpeedBoostUntil exactly as the prompt's handler does - press E on a pad in game to confirm the last hop.

## Portal HUD fit + portal night rules (2026-09-22, user: "hud glitches with portal hud. warning when entering portal one min before. 'Portals are blocked 1 min before night!'. and it tps u back automatically when night starts, with a warning 30s beforehand.")
Sources mirrored in `portals/` (checksums equal to Studio). Backup: `backups/NewMap_portals_before-night-rules_2026-09-22.rbxm`.
- **The glitch:** `PortalHudClient` placed the run timer + map name on fixed fractions (IgnoreGuiInset, DisplayOrder 9000), so they drew straight over `CucumberHUDDesign.Counters` (Strength / Cash, top centre), and Return Home sat on the Hotbar's first slot. Now the MinigameHUD respects the inset and is laid out every frame from the real rectangles: Timer + one line (map name, or the night countdown) 6 px under the counters, the Return Home caption 6 px above `Hotbar.Bar` with the house button on top of it. DisplayOrder 22 (HUD 20 < it < BuildMenu 25 < CucumberMenus 60 < GameNotify 2000) so menus and toasts cover it. The stack's bottom is the MinigameHUD attribute `StackBottom`; `DesertHuntClient` hangs "Rats: x / y" 4 px under it (DesertRatProgress DisplayOrder 23, was 9001).
- **Night rules (`ServerStorage.PortalService`, NIGHT RULES block):** `BLOCK_BEFORE_NIGHT` 60 -> `Enter` refuses and fires StateChanged "Blocked" = "Portals are blocked 1 min before night!" (at night "Portals are closed at night!"), at most every 3 s per player. `WARN_BEFORE_NIGHT` 30 -> one StateChanged "NightWarning" per run: toast "Night in 30s! You'll be sent home." + the map-name line becomes a live "Night in Ns!" countdown. `RETURN_LEAD` 2 -> `ReturnHome(player, "Night")` starts 2 s before `PhaseEndsAt` so the iris transition is over at nightfall; a run found during the night (admin-forced night) goes home at once; a respawn while the return is due ends the run where the respawn put the player. Timings are also attributes on `ReplicatedStorage.MinigameHudRemotes`.
- **Bug this fixed on the way:** before, a portal player stayed in the map all night; the raid's SendHome pulled them to their plot 0.5 s into the night and PortalService's fall check (`Y < FallY`) threw them straight back to the map start, so the raid stole from an empty base.
**Playtest-verified (2026-09-22, 1301x611 viewport):** counters 14..63 px, timer 70..120, countdown line 122..147, house button 416..471, caption 471..492, hotbar 498..543 (no overlaps; the screenshot before showed "Classic Obby" across the cash counter). Touching the Spawn portal with 46 s of day left was refused with the toast, repeated every 3 s while standing in it. With the block lowered to 20 s for the test (playtest-only), a run entered at 31.7 s got the toast at 29.9 s and the countdown 30 -> 1; the trip home started at 1.9 s, the player stood at the lobby return point at 1.1 s, and 0.5 s into the night the raid moved them to their plot and nothing pulled them back ("survived, stolen 0/2"). A run forced in at night was sent home within 3 s. NOT saved/published.
## Slow mode 25, counters hidden in minigames, 1-hour portal cooldowns + strength to enter (2026-09-22, user: "slow mode walkspeed make it 25 / hide top indicators during minigame to bring the minigame timer up / have 1hr cooldowns for portals, above each portal display the cool down like 1:00:00 then 59:59.. / add a strength requirement to enter portals ... [strength icon] #strength required ... eg if its 300 recommended to lift cucumbers in biome, make it 560 to enter portal")
Backup: `backups/NewMap_slowmode+portal-cooldowns_before_2026-09-22.rbxm`. Mirrors: `StrengthProgressionServer.server.lua`, `CucumberLiftClient.client.lua`, `DataService.lua` (root) and `portals/PortalService.lua`, `portals/PortalHudClient.client.lua`, new `portals/PortalSignClient.client.lua` (checksums equal to Studio).
- **Slow mode:** `StrengthProgressionServer` SLOW_MODE_SPEED = 25 (was a literal 16 in two places); `CucumberLiftClient` restores 25 after a lift. The boost pad still doubles it.
- **Minigame HUD:** `PortalHudClient` hides `CucumberHUDDesign.Counters` (Strength / Cash) while `InPortalMinigame` and shows them again after; the timer now starts at the counters' own top edge (14 px) instead of under them.
- **Strength to enter:** authored attribute `StrengthRequired` on each portal model. Numbers are the biome signs' "recommended" values changed up (signs live in `01 Spawn.Decor`, one per biome entrance: Desert 300, Samurai 2k, Farm 15k, Snow 400k, Underwater 6M, Volcano 40M, Narmek 750M, Toyland 14B, Neon 1T):

| Portal | Destination | Biome sign | StrengthRequired |
|---|---|---|---|
| Spawn (Lobby Portal) | StarterObby | none | 75 |
| Desert Portal | DesertHunt | 300 | 560 |
| Narmek Portal | VoidBloxout | 750M | 1.35B |
| Neon Portal | SnowAvalanche | 1T | 1.9T |

  `PortalService.Enter` checks night rules, then the cooldown ("Portal on cooldown! Come back in 57:12"), then `Data.Strength` ("You need 560 strength to enter this portal!"), all through StateChanged "Blocked" -> Notify.Error, at most every 3 s.
- **Cooldown:** `PortalService.COOLDOWN_SECONDS` 3600 per player per portal, started when a run begins (not when it ends). Saved as `Data.PortalCooldowns[destination]` = server time it opens (new DataService template key; Reconcile fills old profiles) and mirrored on the player attribute `PortalReadyAt_<destination>`; loaded on join, expired entries dropped.
- **Sign:** `PortalService.addSign` hangs an invisible 1-stud anchor `PortalSign` 1.5 studs over each portal's bounding-box top (tag `PortalSign`, attrs PortalDestination / StrengthRequired). `PortalSignClient` builds a BillboardGui on it for the local player: 11 studs wide (studs rule), content laid out in 320x150 px and fitted with one UIScale; top line = the cooldown ("1:00:00", then "59:59" .. "0:01", hidden when ready), bottom row = strength icon + the requirement (NumberAbbrev: 75 / 560 / 1.35B / 1.9T) in the HUD's Builder Sans ExtraBold Italic, green once the player's strength reaches it, red below. AlwaysOnTop, MaxDistance 150, rebuilt when the anchor streams back in.**Playtest-verified (2026-09-22, test account strength 318K):** slow mode WalkSpeed 46.02 -> 25.00 -> 46.02. Narmek portal refused with "You need 1.35B strength to enter this portal!" every 3 s; signs read 75 / 560 green and 1.35B / 1.9T red. A Spawn run started the cooldown (attribute and Data both 3598 s left, FormatTime "59:59"); in the run the counters were hidden and the timer sat at 14..64 px (the counters' old spot) with the countdown line at 66..91; home again -> counters back, the portal refused with "Portal on cooldown! Come back in 59:44" and its sign showed "59:37" over "75". A cooldown saved at +120 s came back after a playtest restart with 99 s left. Test cooldowns were cleared from the test account's real profile afterwards. NOT verified by picture: the chrrxs capture_screenshot does not draw client-created BillboardGuis (even a clone of a place-authored one), so the sign was checked by its live layout numbers. NOT saved/published.
## Portal signs readable in every biome (2026-09-22, user: "i dont see the portal strength requirement text for portals after desert portal")
The Narmek and Neon signs were built and drawn, but at 11 studs wide their bare red text ("1.35B", "1.9T" - the account is short of both) vanished against those biomes' dark blue walls; the green Spawn/Desert numbers read fine on light walls. `PortalSignClient` now puts each line on a dark rounded pill (16,16,24 at 0.2 transparency, AutomaticSize X, UIPadding 16/18), the billboard is 17 studs wide (was 11, layout box 320x160 px), and the short-of-it red is 255,80,80. Backup of the previous mirror: `portals/PortalSignClient.client.lua.before-pill-2026-09-22`. Verified by capture at Narmek ("1.35B" on the pill), Neon ("1.9T", plus a "59:59" cooldown pill from a temporary attribute) and Desert (earlier, "560"). Capture gotcha: chrrxs capture_screenshot skips AlwaysOnTop billboards; set AlwaysOnTop = false on the client copy to see a sign. NOT saved/published.
## CORRECTION: the missing signs were two unregistered portals (2026-09-22, user: "revert that change. u are wrong. the signs do not show above volcano portal and the ice portal. fix")
The "readable in every biome" section above was WRONG and its change (dark pills, 17-stud sign, brighter red) is reverted: `PortalSignClient` is back to the 11-stud version (checksum 4143244500 before today's key tweak), and `portals/PortalSignClient.client.lua.pill-reverted-2026-09-22` keeps the reverted text for reference. The Narmek and Neon signs always rendered. A read-only investigation workflow (place scan + engine research + code review, each finding checked by two skeptics) found SIX portal frames by their 0.305 x 6.743 x 12.853 entrance planes, not four: the Snow biome's ice frame and the Volcano biome's lava frame sat in `05 Snow.Decor` / `07 Volcano.Decor` as plain "Model"s (OrigIndex 119 / 115) with no PortalDestination, so `hookPortal` skipped them: no sign, no entry trigger, a solid plane. Name searches for "portal" missed them.
- Moved into new `Portals` folders and named `Ice Portal` / `Volcano Portal` (no script references Decor children).
- `Volcano Portal`: PortalDestination `LavaRun` (the Lava Run map existed in PortalMaps with no portal), StrengthRequired 73,000,000 (the Volcano sign says 40M).
- `Ice Portal`: PortalDestination `SnowAvalanche` (the Avalanche snow map, which the Neon Portal also opens), StrengthRequired 740,000 (the Snow sign says 400K), PortalId `IcePortal`.
- `PortalService.cooldownKey(portal)` = the optional PortalId, else PortalDestination, so the Ice and Neon portals keep separate hours while the older four keep their saved keys; the sign anchor carries it as `CooldownKey` and `PortalSignClient` reads it.
Backup: `backups/NewMap_ice+volcano-portals_before_2026-09-22.rbxm`. **Playtest-verified:** 6 sign anchors (Volcano at y -212.1, Ice at -210.6); captures show "73M" over the lava arch and "740K" over the ice arch (AlwaysOnTop switched off on the client copy only, because the capture tool skips AlwaysOnTop billboards); with the requirement lowered in the playtest only, the Volcano portal opened `LavaRun_<userId>` ("Lava Run") and the Ice portal opened `Avalanche_<userId>` with cooldowns LavaRun 3598 s and IcePortal 3598 s while the Neon key SnowAvalanche stayed 0; the signs showed "59:43" / "59:49"; test cooldowns cleared from the real profile. Seen on the way: the test account's saved Strength is 0 (Cash 2.1B) - nothing here writes Strength. NOT saved/published.
## Manage panel wired up (2026-09-23, user: "script the manage ui - make manage button open it, then look at every aspect of manage ui and implement whatever is there i.e u might see selling pets, u implement selling pets. etc.")
The designed `StarterGui.CucumberMenus.ManagePanel` is live: the left menu's Manage button (inside the base) opens it like Shop / Index / Pets, its three tabs are real - Pets (the active roster, SELL = 220 s of the pet's cash/s, `PetService.Sell` deletes the record), Cucumbers (every placed cucumber, SELL = 220 s of its cash/s, the model is destroyed), Zombies (live threat level via `ZombieAPI.ThreatLevel`, nights survived per level via `ZombieAPI.RaidResult`, OFFLINE EARNINGS: survive one night at your current level and being away pays 50 % of the unboosted cucumber cash/s for up to 8 h, toasted on the next join). The capacities the panel talks about now exist: cucumbers `10 + 2 x PlotLevel` (placement refused "base full"), active pets `3 + PlotLevel` capped at 6 (rosters already over it keep their pets). Numbers in `ReplicatedStorage.Modules.ManageConfig`; sources, hunks, push recipe and the test report in `manage-ui/` (README.md, tests/REPORT.md); backup `backups/NewMap_manage-ui_before_2026-09-23.rbxm`. Tested on the isolated PetTest profile; not saved / published.

## Pets menu removed, pets in the hotbar, click-for-info frame, rarity under the name (2026-09-23, user: "lets get rid of pets menu/pets button but make a backup of it. in pet overhead put their rarity under their name instead of beside it. make name white but rarity color coded. make it so clicking on pet opens a frame on the side, draggable, smaller, same kinda theme, and it just shows all the pet info along with a description of its ability. make it so inactive pets are just in ur inventory (the inventory that is at bottom of screen)")
The Pets panel, its two modules and the paw button are gone (backup `backups/NewMap_PetsMenu_before-removal_2026-09-23.rbxm`). Every owned pet that is not active is a Tool in the hotbar (new `ServerScriptService.PetInventoryService` mirrors owned-minus-roster into Backpack tools; HotbarClient draws the pet model and a pet tooltip); clicking the tool lets it out (`Remotes.PetInventory` Equip -> PetService.Equip, cap / combat-lock refusals toast). Clicking a pet in the world opens the new draggable PET INFO frame (`StarterPlayerScripts.PetInfoClient`, Manage-panel theme, right side, smaller): preview, white name, colour-coded rarity, owner, traits, cash/s, damage / DPS / range, egg + rank, ability name + description + chance, and PUT IN INVENTORY for your own pets. The overhead card now stacks the white name over the rarity word in its rarity gradient. Sources, hunks, push recipe and the test report: `pets-inventory/`. Not saved / published.

## Pet placement ghost + trimmed egg reveal (2026-09-23 later, user: "make placing pet from inventory show pet preview like in the build placement system u got build preview - place pet anywhere theres space" / "in egg hatching make it just show pet - pet name/rarity and chance of getting pet, dont show all that other info")
Taking a pet out of the hotbar now shows a see-through copy of the pet on your plot, red where there is no room (over placed cucumbers / builds / eggs, or off the plot); a click places it right there (`Remotes.PetInventory` Equip with a Spot, validated server-side, `PetService.Equip(player, id, spot)`). The egg reveal card shows only the pet, its name, rarity and `[1 in N]` chance (the cash/ability and traits lines stay hidden). Sources + report: `pets-inventory/` (README "Round 2"). Not saved / published.

## Bright night: day light all night, only the sky turns starry (2026-09-23, user: "make night in this game similar brightness where there is no darkness aspect, its basically bright but its just the sky looks like night")
- Reference: a screenshot of another game whose night is fully lit with a black, star-filled sky.
- `ServerScriptService.DayNightCycle` (mirror DayNightCycle.server.lua): the night no longer tweens
  the sun down. `runNight` keeps `Lighting.ClockTime` where the day clock left it and tweens
  Brightness / Ambient / OutdoorAmbient to the DAY values captured at start (`originalBrightness`
  etc.), then `applyNightSky()` swaps the six `Lighting.Sky` textures to a starfield, sets the
  Atmosphere Color/Decay to navy (40,45,70 / 20,24,44) and disables SunRays; `runDay` calls
  `applyDaySky()` which restores the day textures, the atmosphere colours and SunRays.
- Night skybox default = Creator Store "Starry night sky (Skybox)" 3451179493 (black sky, small
  stars on all six faces): Bk 3451163360 / Dn 3451162694 / Ft 3451161099 / Lf 3451175494 /
  Rt 3451160296 / Up 3451161536. Read with `game:GetObjects("rbxassetid://3451179493")` in an
  edit-mode eval (preview_asset / InsertService are gated by "Allow Loading Third Party Assets";
  GetObjects is not). Other candidates looked at: classic Starry Night 64669546 (aurora + sea
  horizon on the side faces), 119552206 (near-black Milky Way), 1613988671 (brown clouds),
  150147929 (blue winter).
- Attributes on the script, all optional: `NightSkyboxBk/Dn/Ft/Lf/Rt/Up` (number id or content
  string), `NightAtmosphereColor` / `NightAtmosphereDecay` (Color3), and the old
  `NightClockTime` / `NightBrightness` / `NightAmbient` / `NightOutdoorAmbient` are now overrides
  that default to the day values. The four old attribute VALUES (0 / 1 / 60,66,98 / 78,85,122) were
  removed from the script, otherwise the dark night would have stayed.
- Verified in a solo playtest: forced night -> ClockTime 11, Brightness 3, Ambient 110,
  OutdoorAmbient 158 (= day), sky faces 3451161099 etc., atmosphere navy, SunRays off, screenshot
  = lit plot under a black starry sky; forced day -> day faces 10930708925 etc., atmosphere
  210,220,235 / 150,170,200, SunRays on. No DayNightCycle warnings.
- Backup: backups/NewMap_DayNightCycle+Lighting_before-bright-night_2026-09-23.rbxm. Not saved /
  published by me.
- 2026-09-23 (user, later): "brightness = 1 instead of 3 at night" -> the `NightBrightness`
  attribute on `ServerScriptService.DayNightCycle` is set to 1 again (the only Night* attribute
  present now; the code default is still the day value). Verified in a playtest: night Brightness
  1.00 with the day ambients and the star sky, dawn back to 3.00.

## Index rarity + collection trails (2026-09-23)

The biome landmark (the "T" tree, last Index card) is no longer forced to stand every day: it is a
1-in-N regular roll (`CucumberSpawner.LANDMARK_ODDS`, Spawn 100 .. Neon 1000), every type def carries
its per-roll `Odds`, and the Index cards show `[1 in X]` (white from 1 in 10, gold for the landmark).
Completing a biome unlocks its character trail (`ReplicatedStorage.Modules.CollectionTrails`, one per
biome, engine textures only) which also multiplies bench strength ((biome index + 1)x, stacking with
the headband via `GymService.TrailMultiplier`); the Index reward button equips / unequips it.
Full write-up, the spawn-rate table and the test recipe: `index-rarity-trails/README.md`.

## ECONOMY REBUILD (2026-09-23, user: "go through the entire game and set up the economy ... threat levels ... number of defenses ... guardians fast, chase on pickup, knock back further, users faster at higher strengths")
Design + every number: `economy/PLAN.md` (sections 1-6). Pre-change snapshot: `backups/NewMap_economy_before_2026-09-23.rbxm`
(33 instances) + `economy/before-2026-09-23-attributes.json` (portal + build Cost attributes). Byte-exact mirrors of every
touched script AFTER the change: `economy/live-after/<Service>.<Name>.lua` (30 files, lengths = #Source).
- Three aligned ladders: strength requirement x10 per biome (`CucumberLift.ZONE_BASE` 3 .. 3e10), cash x8 per biome with
  prices at 10-25 % of a biome's earnings, zombie HP / defence damage / bat / pet damage x3 per level or tier.
- Income: `CucumberValues` EARN_VALUE_PERIOD 16 (typical Spawn cucumber 0.5 $/s), no Spawn bonus, tree = 8x typical =
  the next biome's typical (rows 3..64). Field 10 per biome (`CucumberSpawner` CUCUMBERS_PER_BIOME 10 incl. 2 slices).
  Sell = 120 s of income (`ManageConfig`).
- Strength: `GymService` per rep 3^(tier-1), BENCH_COSTS 300 / 7K / 100K / 1.5M / 25M / 400M / 6B; `HeadbandsCatalog`
  mults 2,3,4,6,8,12,16,24,32,48,64,96 and prices 0 .. 3T. WalkSpeed = 25 x 1.15^log10(1 + S/3), cap 120 (140 boosted)
  (`StrengthProgression` / `StrengthProgressionServer`).
- Plot: `PlotUpgrades` 400 / 4K / 60K / 1M / 15M / 250M. Eggs (`EggShop` PRICE_BY_EGG): 100 .. 12B. Portals:
  StrengthRequired 100 / 1K / 1M / 100M / 1B / 100B, finish pays `PortalService.PORTAL_REWARDS` (6K .. 800B, toast via
  PortalHudClient "Reward"), Neon Portal got PortalId "NeonPortal". Signs rewritten (300 .. 30B).
- Builds: Cost attributes + `BuildCatalog.DEFAULT_COST` (SpikeTrap 300 .. Minigun 5B, walls 100 .. 100M),
  `UNLOCK_STRENGTH` / `UnlockOf` / `IsUnlocked` (Catapult 300 .. Minigun 300M), `BuildService.Place` refuses locked keys,
  `BuildMenuClient` LockShade overlay + "🔒 💪3K" label + refusal toast; `FormatCost` abbreviates from 100K.
- Zombies (`ZombieCatalog`): score = base VALUE (reward x 8^(biome-1) x mutation mult capped 12), level = 1 +
  floor(log8(score/128)) (a Spawn base = 1, Desert = 2 ... Neon = 10), wave 4..16, `HpMult` 3^(level-1) to 2,187 then
  3,281 / 4,921, role HP (shambler 60 / runner 40 / brute 200-300 / titan 600, sprinters 1), `HealthOf(variety, level)`,
  BUILD_HEALTH tiers (Wooden 150 .. Minigun 656K), BARBED_FRACTION 0.10, ALIVE_CAP 48. `ZombieRaidService`: Spawn uses
  HealthOf, bash = 25 x HpMult, barbed reflect, door + thieves respect the cap. `DefenceService` damage: turret 100,
  catapult 180, laser 800 dps, frost chill 50, tesla 1,800, mortar 18K, minigun 1,500 (trap 7). Bat = 35 x 3^log10(S/300).
  Pet shot damage x3 per egg tier (`PetBalance.TIER_DAMAGE_STEP`). Holy Water = 40 % of max HP. Item shop price x4 per
  threat level (`ItemShopCatalog.PRICE_LEVEL_STEP`, attribute ItemShopPriceMult, panel refreshes on State).
- Guardians (`GuardianCatalog`): speeds 32 .. 131 (1.3x the sign-strength player), bursts 4-6 s / rests 0.6-1 s at 0.9,
  lurk 0.5, wake 0.4-0.9 s, reach 8, cooldown 1.2, knockback 10..45 studs / 0.55..1.1 s; wake at LIFT START through the
  player attribute `LiftingCucumberZone` (`CucumberCarry` sets it when the bar opens, clears in release();
  `GuardianService.CandidateZone` = Lifting or Carrying; the catch still needs the carry). Also fixed: the chase rest read
  a missing `REST_SECONDS_CHASE` and fell back to a full sprint length.
- Verified in a solo playtest on the Studio test profile: clean boot, every service prints the new numbers, WalkSpeed 46.6
  at 84.8K strength, threat level from base value, a forced level-5 raid (10 zombies, Iron Brute 20,250 HP) cleared in
  ~15 s by a base with tier 6-7 defences, a forced level-7 raid (11 zombies, 36K-146K HP) beat the same base (1 mortar,
  1 tesla, 30 traps) and stole its one cucumber = the intended "under-equipped" outcome; guardian woke at 32 studs/s and
  closed to 2 studs on a lift start, no catch without a carry, home after the cancel; locked cards render; item shop
  multiplier attribute flows. NOTE: the test profile (PetTest_140977250) lost its MASSIVE Frozen Tree to that raid.
- Pre-existing, not fixed: `ReplicatedStorage.Assets.Sounds.Electric Buzz` (rbxassetid 8278770516) is archived and spams
  "Failed to load sound" every tesla arc. Stale comments: `CucumberLift` header (old sign numbers), `CollectionTrails` "2^".
- Store key stays `PlayerData_v1` (no wipe). Nothing saved / published by me.
- 2026-09-23 (user, later): the "The zombies turned on you! Stay out of their way." toast is gone
  (`StarterPlayerScripts.ZombieRaidClient` Hostile handler is a no-op; the server still sends Kind "Hostile" and the
  hostility mechanic is unchanged).
- 2026-09-23 (user: "guardians attack too fast, even before you pick it up" -> implement plan section 7 options 1-3 +
  the escape toast): `GuardianCatalog` ARRIVAL_SLACK 0.5 / CATCH_GRACE 1.5 / GRAB_WINDUP 0.6 / GRAB_REACH_SLACK 1.15 /
  GRAB_MISS_COOLDOWN 0.8 / HINT. `CucumberCarry` publishes `LiftingExpectedSeconds` when the bar opens (APPROACH + 0.3 +
  min(MAX_TIME, Clicks / max(1.5, 6 - Cps)): 1.6 s trivial, 4.5 s at the sign, 11-13 s hard) and clears it in release();
  Grab stamps `CarryingSince`. `GuardianService.Wake` holds WakeAt so travel lands ARRIVAL_SLACK after the expected lift
  (a pickup already in hand keeps the plain delay) and sends the HINT toast once per session; the catch: a lifter is
  hovered, a fresh carry (< CATCH_GRACE) gets the signature roar instead of a grab, then the Grab clip starts in reach
  and the hit lands GRAB_WINDUP later only if the target is still within reach x GRAB_REACH_SLACK (else a whiff +
  GRAB_MISS_COOLDOWN). Verified: compile + catalog values; a 6 s expected lift with the guardian 54 studs out had it at
  2 studs by 8.3 s (not before); the grace / wind-up path is code-verified only (a real lift is needed; the passive
  watcher `_G.GuardianWatch` in the server VM logs state changes + Lifting/Carrying attributes for 240 s).

## Defence range disc in build mode (2026-09-23, user: "show defense range when defense is selected in build mode (like a big circle around it)")

Sources: the live `StarterGui.BuildMenu.BuildMenuClient` (mirror `build-mode/BuildMenuClient.client.lua`) and
`ServerScriptService.DefenceService` (mirror `zombie-raid/DefenceService.server.lua`), pushed as surgical hunks with
`pets-remake/mkpatch.py` + `apply_patches.lua` (9 + 3 edits, then 2 follow-ups). Backup
`backups/NewMap_BuildMenuClient+DefenceService_before-range-disc_2026-09-23.rbxm`.

- **The numbers stay on the server.** DefenceService owns every range (TURRET.Range 45, CATAPULT 60 / MinRange 8,
  MORTAR 75 / 12, TESLA 28, FROST.Radius 24, MINIGUN 42); a new `RANGES` table maps kind -> {Range, MinRange} and a
  startup task waits for `ReplicatedStorage.PlaceableBuilds.Defences` (BuildService builds it at its own startup) and
  stamps `Range` / `MinRange` attributes on each template (ChildAdded keeps stamping). Attributes replicate, so the
  client never carries a copy. BuildService strips every attribute but its own off a template, which is why the stamp
  goes on the template and not the ServerStorage source. SpikeTrap / LaserGate / BoostPad get no Range: no disc.
- **The client draws it.** `StartPlacing` reads the template's Range / MinRange (both the card pick and the click-to-move
  path go through it) and builds `MakeRangeDisc`: a Model "RangeDisc" = a SmoothPlastic cylinder Fill (0.08 thick,
  RANGE_COLOR 120,205,255 @ 0.78) + a rim of Neon block segments (`RangeRim`: clamp(floor(r x 1.4), 36, 96) segments,
  length r x step x 1.06 so they overlap, 1 stud wide, RANGE_RIM_COLOR 55,170,255 @ 0.1, tangent via
  `CFrame.fromMatrix(centre, tangent, yAxis)`), plus for a MinRange a red inner Fill + rim (the dead zone a catapult /
  mortar cannot hit). `ShowRangeDisc` pivots it to `plot.CFrame * CFrame.new(x, surface + RANGE_LIFT 0.12, z)` right
  after the ghost's PivotTo (flat on the ghost's floor, centred under it), un-parents it in the away-from-base branch
  alongside the ghost, and StopPlacing destroys it. Every part: Anchored, CanCollide / CanQuery / CanTouch false,
  CastShadow false, so it never answers the mouse ray or the placement overlap test.
- **Its own model in workspace, not inside the ghost:** the ghost's red `OccupiedHighlight` (AlwaysOnTop) would paint
  a 150-stud disc red every time the spot is taken.
- **Gotcha (cost one cycle):** a Model with a PrimaryPart IGNORES `WorldPivot`; its pivot is the primary part's. The
  Fill is a cylinder stood up by `CFrame.Angles(0, 0, 90 deg)`, so the first cut's PivotTo rotated the whole disc by
  -90 deg about Z and the ring stood vertical (rim #1 measured 60 studs BELOW the centre). Fix: `fill.PivotOffset =
  CFrame.Angles(0, 0, -90 deg)` before it becomes the PrimaryPart, so the model pivot is upright at the centre.
- Verified in a solo playtest (dev hook `BuildDev = enter / category:Defences / pick:Catapult / aim:0,10`): Range 60 /
  MinRange 8 attributes on the template; 84 outer rim segments at r 60.00 and 36 inner at r 8.00, all 0.06-0.09 above
  the fill; the fill's axis vertical (RightVector (0, 1, 0)); fill 0.12 above the ghost's bottom, 0.00 horizontal
  offset; Cancel destroys it; a simulated click on a placed Catapult (WorldToViewportPoint of its Hitbox = screenshot
  pixels 1:1, NO inset added) lifted it with the same disc under the ghost. Screenshots: a pale cyan wash across the
  plot with the rim as a bright line, the red 8-stud dead zone round the catapult ghost.
- Nothing saved / published by me. The night raid closes build mode (ThiefStole), so range checks need daylight.

## Guardian NAP CYCLE, human-clickable lift curve, biome PvP (2026-09-23, user: "guardian broken - delay in attacking or
## sometimes doesn't attack at all - fix; make it so the guardian has to be ASLEEP when you lift, otherwise it attacks
## as soon as you try; all ranges (green, yellow, orange) clickable without an autoclicker; timer above the sleeping
## guardian; PvP in biomes - bat knocks players back and drops their cucumber")
- The same-day delayed-arrival / catch-grace / wind-up experiment is REMOVED (it caused the delay and the misses):
  `GuardianService.Wake` is the plain wake again, the catch is the instant grab at reach (carry required),
  `CucumberCarry` no longer publishes LiftingExpectedSeconds (CarryingSince stays, unused). The HINT toast stays.
- NAP CYCLE (`GuardianCatalog` SLEEP_SECONDS {25, 40} / AWAKE_SECONDS {12, 20}): by day a guardian naps on its seat
  (`Nap`: State Asleep + model attr `SleepUntil` = server time), wakes (`WakeUp`: `AwakeUntil` attr, Lurk, and goes
  straight for anyone lifting or carrying in its biome via Carriers/Nearest), prowls / rests with its EYES LIT
  (Rest and Lurk now SetEyes true), and lies down again when AwakeUntil passes (TickOne; an awake guardian without a
  clock gets one). Dawn starts with a nap. `OnCarryChanged` ignores Asleep: lifting while it naps is the safe window;
  lifting late in the countdown = it wakes onto you. Night = Sleep() with no clock.
- TIMER (`GuardianClient`): a client-built BillboardGui `SleepTimer` on each guardian root, TIMER_WIDTH x TIMER_HEIGHT
  studs (6 x 1.4), TIMER_GAP 0.8 above the z's: "💤 23s" green while napping (counts SleepUntil against
  GetServerTimeNow), "AWAKE" red while up by day, blank at night. Z's only for State Asleep now (SLEEPING table).
- LIFT CURVE (`CucumberLift.FORMULA` DriftAtSign 0.095, DriftPower 0): hold rate 0.6 cps (green) / 1.6 at the sign /
  2.1 at 0.7 / 3.4 at MIN_RATIO 0.4 (was 3 / 6 / 17). Wins: yellow 0.7-1 in 4-8 s at 4 cps; orange 0.55 in 5-7 s at
  5-6 cps; orange 0.4 in 9 s at 6 cps (15 s at 5 = timeout). Red (< 0.4) still impossible. DIFFICULTY comments updated.
- PVP (`StarterPack.Bat.BatServer` sweepPlayers): a swing hits other players in the same RANGE/CONE arc when both
  stand inside the biome lane (NightBarrier largest part footprint + PVP_MARGIN 20; the lobby is safe): ZombieRaid
  remote {Kind Hit, Silent, Distance PVP_DISTANCE 12, Seconds 0.4, Damage 0} (the zombie / guardian flight) +
  CucumberCarryAPI.DropAtFeet when they carry + "Big Thud"; PVP_COOLDOWN 1.2 s per victim. Not runtime-tested (needs
  two players); compiles, lane resolved from the barrier at start.
- Verified in the user's playtest (passively): all ten guardians Asleep at dawn with SleepUntil 15-29 s, labels
  "💤 12s".. on the streamed-in ones, z's on, no GuardianService warnings.

## Bench toast, instant headband buys, 10 s drop timer (2026-09-23, user: "when upgrading benchpress notification - don't show the new strength per rep / speed. Buying headband takes a long time to load, fix. 10s timer above each dropped item/boost by zombies - item despawns after timer.")

Pushed as surgical hunks (`pets-remake/mkpatch.py` + `apply_patches.lua`); backup
`backups/NewMap_Gym+Headband+Items_before-toast-fit-timer_2026-09-23.rbxm` (the six scripts as they were).
Mirrors refreshed from live: `GymService.lua`, `economy/live-after/*`, `headband-shop/HeadbandService.lua`,
`headband-shop/HeadbandFitter.lua` (new mirror), `items/src/*`.

- **Bench toast.** `GymService.Buy` returned `"Bench press Lv. 6 (+243 per rep, 6x speed)"`; it now returns
  `"Bench press Lv. 6!"`. The board still shows the effect line (State.Effect is untouched). Verified with a real
  purchase on the test account (Lv. 5 -> 6, 25M Cash).
- **Headband buys.** Measured before: `Remotes.HeadbandAction` Equip took 0.83-1.12 s to answer (a cold band
  1.4-2.2 s) because `HeadbandService` ran `ApplyToCharacter` -> `HeadbandFitter.Build` (CreateEditableMeshAsync +
  CreateDataModelContentAsync + CreateMeshPartAsync per band part) INSIDE the remote; the client shows
  "BUYING..." until the reply. Saves and GymService.Refresh cost 0.000 s. Three changes:
  1. `Buy` / `Equip` / `Unequip` `task.spawn(ApplyToCharacter, player)`: the reply comes back in ~0.05 s and the
     band pops onto the head when its fit is done (ApplyToCharacter's FitRevision guard already drops stale fits).
  2. `WarmFits(player)` on the booth prompt (Triggered -> OpenShopDialog): fits every band for that head in the
     background, cheapest first, one per frame, throw-away accessories destroyed (the fitter copies the cached
     mesh onto the clone with ApplyMesh, so the cache survives). Dev hook `HeadbandDev = "warm"`.
  3. THE CACHE WAS BROKEN: `HeadbandFitter.WarpedMesh` keys its MeshCache on the 64 measured radii at `%.5f`, and
     `Fitter.Measure` raycasts the head in head-local space - float error from the head's world pose (idle
     animation) moved radii by more than 1e-5 between calls, so the same band missed at random (hit / miss /
     hit measured for GoldBand). The key keeps two decimals now. Result: repeat builds 0.001 s (was 0.2-1.5 s);
     after the warm-up an Equip answers in 0.03-0.05 s AND the band is on the head in 0.05 s.
- **Drop timer.** `ItemsCatalog.DROP_LIFETIME` 120 -> 10. `ItemService.SpawnDrop` stamps `DespawnAt` = SpawnAt +
  DROP_LIFETIME (server clock; PickTick still destroys at the lifetime, measured 10.1 s). `ItemClient.AddDrop`
  grew the billboard to 2.1 studs (offset 2.0) with a `Timer` label (FredokaOne, white, 0.29) over the name (0.44)
  and hint (0.27); the RenderStepped loop writes `ceil(left) .. "s"` ("10s" for the first second .. "1s"), red
  (255,80,70) at <= 3 s, and at 0 `ExpireDrop` hides the parts + label locally under a grey poof so nothing
  lingers past the label while the server's 0.25 s tick removes it. Verified: 5s/4s white, 3s red on a screenshot,
  server destroy at 10.1 s.
- Gotchas: the bridge SERIALISES evals across peers (a server eval with a 12 s wait delayed the client eval past
  the drop's life) - spawn and observe in the same response, server call first, short waits. Nothing saved /
  published by me.
- 2026-09-23 (user: "guardian sleeps even when it says awake; nap 5-12 s (then 7-13 s), awake 12-20 s; sfx on taking a cucumber even
  when asleep"): SLEEP_SECONDS {7, 13} (was {5, 12} for a minute). NO SEAT REST while awake - the Lurk branch never calls Rest any more (the sit
  pose is the sleeping pose), a chase that returns home goes Lurk if AwakeUntil is still ahead else Nap, "fell off the
  world" -> Nap; Rest() is now unused. GuardianAudio.StolenFrom moved inside the wake branch of OnCarryChanged (a napping
  guardian is silent). Verified in a playtest watcher: dawn -> nap -> Lurking (awake 14-19 s) -> Asleep (sleep 8-9 s),
  zero Resting transitions.

## Menus dead-centre on the screen (2026-09-23, user: "put all frames such as shops, manage, index in the dead center of screen when open, as they kind of go in weird positions")

Every centred panel (CucumberMenus: ShopPanel / IndexPanel / ManagePanel / BuyShopPanel; StarterGui.HeadbandShop.Shop;
FreeGiftGui.Window) is anchored (0.5, 0.5) at (0.5, 0.5) and MenuController's open tween lands the Content at (0.5, 0.5)
- but those three ScreenGuis had `IgnoreGuiInset = false`, so "0.5" was the centre of the area UNDER the 58 px top
bar: every panel sat 29 px below the true window centre (measured at 1920 x 1080: Shop top gap 253, bottom gap 195;
headband shop 140 / 82). That asymmetry is the "weird position". Fix = a property flip, no script change:
`StarterGui.CucumberMenus`, `StarterGui.HeadbandShop`, `StarterGui.FreeGiftGui` now have `IgnoreGuiInset = true`
(all were false). MenuController.fit() and HeadbandShopClient.fitScale() read gui.AbsoluteSize, so they follow the
full-window size on their own; the Dimmer / Backdrop now cover the top-bar band too. Measured after: 1920 x 1080 Shop
224 / 224 top / bottom, headband shop 110 / 111, FreeGift 309 / 309, all left = right; iPhone 13 preset 45 / 45
(the panel's top 13 px reach into the transparent top-bar band on phones, clear of its corner icons - kept for the
bigger phone text). EggRevealUI / SelectingReward / PortalTransition / ZombieCutscene already ignored the inset;
AdminPanel (top-right) and PetInfoUI (side frame) are not centred by design.

GOTCHA that cost a cycle: `GuiObject.AbsolutePosition` is ALWAYS relative to the inset origin (58 px below the window
top), even inside an IgnoreGuiInset ScreenGui - such a gui's own AbsolutePosition.Y reads -58. Window-space y =
AbsolutePosition.Y + GuiInset.Y for every gui. Nothing saved / published by me.
- 2026-09-23 (user): the overhead label reads "AWAKE FOR 12s" counting down the model's AwakeUntil attribute (GuardianClient,
  updated every frame so it ticks each second); a chase that outlasts the window, or a guardian up without a clock, shows
  plain "AWAKE". Napping still reads "💤 9s".
- 2026-09-23 (user): the sleep timer sits RIGHT above the head: GuardianClient.placeTimer puts the label's bottom 0.3 studs
  over the head top (head top = the server Zzz gui offset minus ZZZ_HEAD_GAP) and lifts the z's gui locally to start above
  the label; placed once per guardian when its z's stream in (attribute Placed on the SleepTimer gui).

## Mutated eggs hatch pets OF that mutation, worth more (2026-09-23, user: "make it so mutated egg makes sure pet hatched is of that mutation, giving better stats")

The inheritance already existed end to end (EggShop roll -> tool attrs -> placed egg attrs -> PetHatchService eggInfo ->
PetService.GrantFromEgg record.Material / Mutations -> PetStats affixes) and a test hatch confirmed it (a restored Golden
VOID+NEON Basic egg gave a Golden VOID,NEON Tabby). Two things were missing: nothing NAMED the pet by its mutation, and
the bonuses were small (NEON +15 % income). Pushed as surgical hunks; backup
`backups/NewMap_pet-mutation-names_before_2026-09-23.rbxm` (PetBalance, PetStats, PetHatchService, PetInventoryService,
PetCardClient).

- **Name = traits + species, everywhere.** `PetStats.Calculate` now sets `Stats.DisplayName` = material word + known
  mutation words + catalog name ("Golden VOID NEON Vine Gecko"), keeps the bare name in `Stats.SpeciesName` and the list
  in `Stats.TraitWords` (new helper `PetStats.TraitWords(material, mutations)`). Everything that read
  stats.DisplayName follows: PetService stamps it as the plot model's DisplayName attribute, PetInfoClient's title,
  ManageController's list. PetHatchService's reveal payload (`PetDisplayName`) and PetInventoryService's reserve
  tools (tool.Name / DisplayName attr / NameOf) used the catalog word directly and now take the stats name.
  PetCardClient colours the trait words of the overhead name with `CucumberMutations.ColorizeName` (RichText; Golden
  gold, VOID purple, NEON green - the species word stays white, the width estimate still uses the plain length).
- **Bonuses (PetBalance.MUTATIONS, income adds to the material multiplier / combat adds to shot damage):**
  NEON 0.50/0.10, SHADOW 0.50/0.10, FROZEN 0.75/0.15, RADIOACTIVE 1.00/0.20, MOLTEN 1.00/0.20, ROYAL 1.50/0.30,
  VOID 3.00/0.50, PRISMATIC 6.00/1.00 (were 0.15 .. 2.00 / 0.02 .. 0.12); INCOME_AFFIX_CAP 8 -> 16, DAMAGE_AFFIX_CAP
  0.25 -> 1.0. Materials unchanged (Golden x1.5, Diamond x2). So a NEON pet earns x1.5, a VOID pet x4, Golden VOID NEON
  x6.75; combat +10 % .. x2.
- Verified in a solo playtest (isolated PetTest profile): record "Golden VOID NEON Vine Gecko" 11.81/s vs 1.75 plain,
  shot 15.18 vs 9.20; plot model DisplayName attr carries the name; overhead card RichText with coloured words; a
  Diamond PRISMATIC egg's reveal payload read "Diamond PRISMATIC Vine Gecko" at 24.5/s. Test recipe: restore an egg
  with `ServerStorage.EggPlacementAPI.RestoreEgg(player, plot, {EggName="Basic", Material="Diamond",
  Mutations={"PRISMATIC"}, HatchAt=now, ...}, pivot)` then `Character:PivotTo` onto it from the CLIENT (a server
  teleport is overridden). Nothing saved / published by me.

## Pet card damage icon + egg-weight pet size (2026-09-23, user: "in pet overhead at base beside the cash/s show icon 15403025691 and damage beside it" / "higher kg eggs make pets slightly bigger, which gives better stats ... but a small higher tier pet can potentially beat a huge lower tier pet")

Pushed as surgical hunks; backup `backups/NewMap_pet-size-damage-icon_before_2026-09-23.rbxm` (PetBalance, PetStats,
PetService, PetCardClient, PetInfoClient, EggHatchClient).

- **Damage on the overhead card.** `PetCardClient`'s cash row is now "$12.3/s", a DAMAGE_GAP spacer, the DAMAGE_ICON
  image (`rbxassetid://15403025691` - an Image asset, "Ammo", AssetTypeId 1, so it goes straight into an ImageLabel;
  a square DAMAGE_ICON_SIZE 0.88 of the row) and the shot damage (`ShotDamage` attribute, NumberAbbrev, DAMAGE_COLOR
  = the Fighter red 255,90,70). `Core.DamageText`, `RenderRate` re-renders on Rate AND ShotDamage changes, DropCard
  clears `entry.DamageLabel`. Measured on the card: Rate 22 x 8 px, gap 2.3, icon 7.1 x 7.0 (loaded), damage 11 x 8.
- **Size from the egg's kg.** `PetBalance.SIZE = {KG_BASE 2, SCALE_PER_DECADE 0.07, MAX_SCALE 1.35, INCOME_PER_SCALE
  1.5, DAMAGE_PER_SCALE 1.0}`; `PetStats.SizeScale(kg)` = 1 + 0.07 x log10(kg / 2) capped 1.35, `SizeMultipliers(kg)`
  -> income 1 + 1.5 x (scale - 1), damage 1 + 1.0 x (scale - 1). `Calculate` reads `record.EggKg` (saved by
  GrantFromEgg since 2026-09-22; legacy pets = scale 1) and multiplies income / shot; Stats carry EggKg / SizeScale /
  SizeIncome / SizeDamage. PetService scales the spawned model by SizeScale AFTER the PET.FIT shrink and stamps
  EggKg / SizeScale attributes; PetInfoClient passes EggKg into its recompute; EggHatchClient scales the revealed pet
  before the height cap. Ladder: 20 kg x1.07 size / x1.11 income, 2,000 kg x1.21 / x1.32, 100,000 kg x1.33 / x1.49
  income / x1.33 damage. TIER_STEP is x8, so the biggest plain Basic pet (Tabby 2.61/s) stays under a plain Desert
  pet (Chest 7.80/s); only traits push past (100K kg Golden VOID Tabby 15.68/s) - "potentially".
- Verified in a solo playtest (PetTest profile): a restored 50,000 kg Basic egg hatched a Moss Turtle at SizeScale
  1.308, Rate 0.80/s (x1.46), bbox 6.54 studs long (the fit cube is 5); the existing Golden VOID NEON Vine Gecko (5 kg)
  reads SizeScale 1.028, Rate 12.31, ShotDamage 15.60; screenshot: coloured name, "Rare", "$12.3/s [icon] 15.6".
  The long trait name wraps to two lines on the card (TextScaled always wraps) - left as is.
- Nothing saved / published by me.
