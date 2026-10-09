# Drop items: potions, pearls, seeds, tokens (2026-09-23)

User: "build potions/items for these things via blender mcp for my open game new map cucumber game: boosts for a
duration (2x speed, 2x strength, 2x coins), teleports like maybe enderpearl kind of thing, special cucumbers, special
pets, redemption tokens (use to get cucumber back when u lose it), etc. these are items that are stored and saved in
the bottom inventory. they drop on zombie deaths. build each one along with each ones functionality."

## The nine items (`src/ReplicatedStorage.Modules.ItemsCatalog.lua` = every number)
| Key | Rarity | Kind | What it does | Drop weight / min zombie level |
|---|---|---|---|---|
| SpeedPotion | Common | Drink | 2x walk speed for 1:30 (`SpeedBoostUntil`, StrengthProgressionServer doubles) | 22 / 1 |
| StrengthPotion | Uncommon | Drink | 2x strength per bench rep for 2:00 (`StrengthBoostUntil`, GymService.AwardRep) | 18 / 1 |
| CashPotion | Uncommon | Drink | 2x every cash payout for 2:00 (`CashBoostUntil`, IncomeService.Credit) | 18 / 1 |
| WarpPearl | Rare | Throw | thrown where the mouse / camera points, teleports the thrower where it lands | 12 / 2 |
| HolyWater | Rare | Throw | splash: 150 damage + 2 s stun to every zombie within 12 studs (ZombieAPI) | 12 / 2 |
| RedemptionToken | Epic | Use | the newest cucumber the zombies stole sprouts at your feet (Data.LostCucumbers) | 6 / 2 |
| GoldenSeed | Epic | Use | a GOLDEN cucumber of your best biome sprouts 4 studs ahead | 5 / 3 |
| VoidSeed | Legendary | Use | a VOID cucumber of your best biome sprouts 4 studs ahead | 2 / 6 |
| ZombieEgg | Legendary | Use | PetService.GrantFromEgg of a SHADOW pet (rarity-weighted, 2 % Gregory) | 2 / 4 |

Drop roll per zombie death: chance `min(0.65, 0.35 + 0.03 x level)`, item weights x `(1 + 0.35 x MinLevel / level)`,
level = the variety's `MinLevel` clamped to 1..10. Potions EXTEND a running timer, never stack the multiplier.

## Models: Blender, primitives only
`itemlib.py` + `build_items.py` + `run_items.py` (headless: `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
-b --python run_items.py`). Every item is built from Roblox-representable primitives (Ball / Block / Cylinder), so the
same build writes `fbx/<Key>.fbx` (for a later upload as a real mesh asset when an Open Cloud key is at hand) AND
`fbx/<Key>.parts.json` (shape, size, colour, material, transparency, pure-rotation 4x4 per primitive). `install_items.lua`
rebuilds them out of Parts in `ReplicatedStorage.Assets.Items/<Key>` - no upload needed. Conversion: Roblox local frame
= `fromMatrix(C(t), C(x), C(z), -C(y))` with `C(v) = (v.x, v.z, -v.y)`, local size `(sx, sz, sy)`, cylinders recorded
with their axis along local X. Renders in `renders/` (`sheet.png` = the line-up), `items.blend` = the saved scene.
Why headless and not the MCP addon: the live Blender belonged to the concurrent "RAS GAME" session (LauncherAnims.blend).

## Scripts (`src/`, installed via `pets-system/tools/install_new.lua`)
* `ServerScriptService.ItemService` - saved inventory (`Data.Items[key] = count`, `Data.LostCucumbers`), one stacked Tool
  per item (invisible Handle at the model centre, parts welded on, attrs ItemTool / ItemKey / Count / DisplayName / Rarity /
  Kind / Description / Boost / PartCount), `Remotes.ItemUse` RemoteFunction (must hold the tool; 0.5 s cooldown),
  `Remotes.ItemEvent` RemoteEvent, drops under `workspace.ItemDrops` (tag ItemDrop, proximity pickup 5 studs, 120 s life),
  `ServerStorage.ItemAPI` {Drop(position, level), DropItem(key, position), Give, Count, RecordLoss}. Seeds / tokens spawn
  field cucumbers with `CucumberSpawnerAPI.SpawnCarried` (Anywhere + Force) and park them in `workspace.Breakables.Planted`
  (ClearFields wipes only the zone folders at dusk / dawn); refused at night (CucumberCarry only lifts by day).
  Studio hook `workspace.ItemDev = give:<Key>[:<n>] | drop:<Key> | roll:<level> | use:<Key> | lose | clear`.
* `StarterPlayerScripts.ItemClient` - Tool.Activated -> ItemUse (aim = mouse hit from the character / camera look), the
  bottle tips in hand, boost chips row (`PlayerGui.ItemBoosts`) under `CucumberHUDDesign.Counters`, drop bob / spin +
  rarity-coloured label, toasts through `RS.Modules.Notify`, poofs. Hook `ItemBoosts.ItemClientDev = use:<n>`.

## Patches (`tools/build_stage.py`, hunks against `orig/` = the live mirrors of 2026-09-23; `patched/` = the live text)
DataService TEMPLATE (+Items, +LostCucumbers); ZombieRaidService (Kill -> ItemAPI.Drop, Escape -> ItemAPI.RecordLoss);
GymService.AwardRep (x2 while StrengthBoostUntil); IncomeService.Credit (x2 while CashBoostUntil); CucumberSpawner
(+PickTypeName bindable); BoostPadService (never cuts a potion short, only a pad boost ends with the character);
HotbarClient (item pictures from the tool's own parts, "xN" count badge, item tooltip, egg-name guard, part wait,
stale-slot sweep on respawn, slot-build race guard). Rounds 1-5 are all live; `ACTIVE_ROUNDS` in build_stage.py is what
a re-push sends (the live rounds only reproduce the text - additive hunks must never ride twice).
Backup of the seven patched scripts: `backups/NewMap_items_before_2026-09-23.rbxm`.

## Verified (solo playtests on the PetTest profile, 2026-09-23)
unheld use refused; all three potions: attributes set, WalkSpeed 41.3 -> 82.6, income +241 403 over 3 s vs 40 236/s (x2.00),
AwardRep 3328 vs StrengthPerRep 1664; chips row at the counters' bottom edge with live countdowns; hotbar pictures, badges
and tooltip; Warp Pearl moved the player 28 studs along the throw; Golden / Void Seed sprouted "Golden Snowball Slice" /
"VOID Crystal Cucumber" 5 studs ahead (best biome = Snow from the plot); ground drop picked up (3 -> 4, toast); token
brought back a recorded "Golden NEON Cactus Cucumber" then refused with nothing lost; Zombie Egg hatched a SHADOW Meadow
Bunny (Legendary) into the inventory; 10 dev kills -> 4 drops and the plot's defences dropped 4 more during a real night
raid; Holy Water killed an Iron Brute in front of the player; the inventory survived a rejoin (8 keys); a planted seed
survived a forced night + dawn; planting at night refused; slots == tools after join and after a respawn.

## Meshes uploaded (2026-09-23, later: the user pasted an Open Cloud key)
`upload-items.ps1 -KeyFile <scratchpad>\oc.key` uploaded the nine FBX as GROUP Model assets (group 14583228) ->
`fbx/asset-ids.json`: SpeedPotion 89127270629558, StrengthPotion 99169315077163, CashPotion 134638953118109,
WarpPearl 102650078251713, HolyWater 74529360838489, GoldenSeed 103683901865176, VoidSeed 88137566503278,
ZombieEgg 127819946203387, RedemptionToken 123708997141725. `install_items_mesh.lua` (served from `fbx/`, 3 keys per
call) replaced every `RS.Assets.Items/<Key>` with the MeshPart version (LoadAsset, prefix strip, 180-degree yaw undo,
look re-applied from parts.json, pivot bottom centre; attr AssetId). The Part versions moved to
`RS.Assets.__ItemsPartsBackup_2026_09_23` (also `backups/NewMap_Items_parts-before-mesh_2026-09-23.rbxm`). Verified in
a playtest: all 8 stacked tools rebuilt with MeshParts, hotbar pictures from the meshes, the Speed Potion mesh in hand,
a Zombie Egg drop with 9 MeshParts. Bounding sizes matched the Blender reports exactly.

## Round 6 (2026-09-23, user: "make the bat tool have an icon in hotbar" / "remove the final instruction line")
HotbarClient: any tool without a TextureId gets a picture try; a tool that is not an egg / pet / item (the Bat) pictures
its own visible parts, stood up on its longest axis and tilted 25 degrees (WorldPivot reset to identity rotation so
BuildPicture's recentring keeps the tilt; a short Handle wait covers "Tool arrives before its children"). The hover
cards no longer show "Take it in hand, then click ..." (items) or "Click to let it out in your base" (pets).
Verified in a playtest: Bat slot = ViewportFrame with 8 parts (bbox 2.5 x 4.4 x 0.8, longest axis up), 12 tools = 12
picture slots, every item / pet card ends at its description.

## Round 7 (2026-09-23, user: Warp Pearl = click anywhere with an arched trail, works with a cucumber; 20 pearls; blank pet traits)
* **Warp Pearl is Kind "Aim"** (ItemsCatalog.WARP: MaxRange 1500, arch = 0.3 x distance clamped 6..40, ring 4 studs). With
  the pearl in hand `ItemClient` casts a ray through the mouse every frame (camera look on gamepad), draws a purple
  arched Beam (attachments' X axes point up = the Bezier control points, CurveSize = the arch) from the chest to the
  spot with a pulsing Neon ring + dot on it (client-only `workspace.WarpAim`), and a click sends the point:
  `ItemService.Warp` stands the player on the ground under it (raycast, characters / zombies / drops excluded), keeps
  the facing, consumes a pearl; refused mid-minigame, seated, no ground, > MaxRange, or - at night, from inside the
  lobby - to any point outside the lobby box (the CucumberCarry wall rule). A shoulder cucumber (welded) rides along.
  Existing tools pick up the new Description / Kind (Reconcile refreshes them).
* **Gift**: `ItemService.GIFTS` - `pearls-2026-09-23` gives UserId 140977250 20 Warp Pearls once per profile
  (`Data.ItemGifts[id]`), claimed when the profile loads with this script running (so it also reaches the real profile
  the next time the account plays with this code; no edit-mode DataStore write that a live session could overwrite).
* **Blank traits**: HotbarClient pet cards hide the traits line when there are none; PetInfoClient's traits row is "".
Verified in a playtest: gift claimed (20 pearls, flag set); trail Beam enabled with the ring on the hovered spot, gone
on unequip; a click warped 42 studs and consumed a pearl; warp with a carried Cucumber kept it on the shoulder; night
+ facing the fields from the lobby edge = "The night wall blocks the way", night inside the lobby = 30-stud warp;
traitless pets show no traits line, a SHADOW pet shows its traits; the info frame reads "" for a traitless pet.

## Round 8 (2026-09-23, user: "warp teleportation avoids the top border - i keep teleporting outside")
`ItemService.ComputeWarpRects`: the playable ground = every `Map.Biomes.<biome>.Floor` rectangle (its Z range clipped
to the biome's own `Walls`, because the Volcano floor runs past its walls) + the lobby box, all inset 1.5 studs, with a
height cap of 12 studs above the floor top. Published once (3 s after start) as the JSON attribute
`Remotes.WarpBounds`; `Warp` refuses a landing outside them ("Pick a spot on the ground inside the map."), and
`ItemClient` reads the same rects to turn the ring red and skip the click. Verified: 11 rects; wall tops and the floor
past the Volcano wall = OutOfBounds, past the wall / past the lobby = NoGround, field centre / 1.6 studs from the wall
/ Volcano / lobby = warps. Gotcha fixed on the way: `floor and PartsAabb(floor)` keeps only the FIRST return value.

## Notes
* `RS.Assets.Sounds."Electric Buzz"` (rbxassetid 8278770516) is an archived asset (Tesla coil) - pre-existing log noise.
* Not saved / published.
