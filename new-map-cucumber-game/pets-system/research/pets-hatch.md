# Research: pets + eggs + hatching (live snapshot 2026-09-22)

Source: `new-map-cucumber-game/live-2026-09-22/` (read-only mirror). Line numbers refer to those files.
Files read in full: `ReplicatedStorage.Modules.PetsCatalog.lua`, `ServerScriptService.PetHatchService.server.lua`,
`StarterPlayer.StarterPlayerScripts.PetRoamClient.client.lua`, `...EggHatchClient.client.lua`,
`ServerScriptService.EggPlacement.server.lua`, `ServerScriptService.EggShop.server.lua`, `...EggTimerClient.client.lua`,
`...PlacementClient.client.lua`, `...EggShopClient.client.lua`, `ServerScriptService.BaseSaveService.server.lua`,
`ServerStorage.DataService.lua`, `ServerScriptService.AdminService.server.lua`, `ServerScriptService.PlotService.server.lua`,
plus the relevant parts of `CucumberMutations`, `PlotUpgradeService`, `Notify`, `_structure.txt`, `_gui_tree.txt`, and the saved profile.

Grep for `PetHatch|PlotPet|PlacedEgg|EggPlacementAPI|PetHatchAPI|PetsCatalog|EggTool|EggRevealUI|PetsHatched|Pets|RoamXxx` found **no other readers**.
No income, raid, UI, or index script touches pets today. `LeaderstatsService`, `ZombieRaidService`, and `DefenceService` never see a `PlotPet`.
ServerStorage also holds non-running backup copies (`__BaseSaveBackup_2026_09_12` has a `PetHatchService` Script and an `EggPlacement` Script, and `__CarryAndEggLabelsBackup` has an `EggTimerClient`). Studio script searches will also match these copies. Never patch them.

---

## 1. `ReplicatedStorage.Modules.PetsCatalog` - exact data shape

### 1.1 `M.EGGS` (lines 22-112)
```lua
M.EGGS["<Name> Egg"] = { Order = <1..8>, Pets = { ["<internalKey>"] = {Percent = <number>, Rank = <1..6>} } }
```
| Egg key (line) | Order | Pool (Percent, Rank) |
|---|---|---|
| `"Basic Egg"` (23) | 1 | `Gregory` {0.002, **no Rank**} (26), Cat {40,1}, Dog {30,2}, Bunny {15,3}, Wolf {9,4}, Tabby {5,5}, Fox {1,6} |
| `"Desert Egg"` (35) | 2 | Barrel {40,1}, Treasure Gem {30,2}, Cannon {15,3}, Chest {9,4}, Desert Overlord {5,5}, Cactus {1,6} |
| `"Samurai Egg"` (46) | 3 | Dog Ninja {40,1}, Good Ninja {30,2}, Evil Ninja {15,3}, Good Samurai {9,4}, Evil Samurai {5,5}, Sensei {1,6} |
| `"Farm Egg"` (57) | 4 | Hay {40,1}, Bird {30,2}, Panda {15,3}, Cow {9,4}, Pig {5,5}, Farmer {1,6} |
| `"Frozen Egg"` (68) | 5 | Red Snowman {40,1}, Blue Snowman {30,2}, Frozen Dragon {15,3}, Frozen Hydra {9,4}, Frozen Ice Shock {5,5}, Frozen Gem {1,6} |
| `"Ocean Egg"` (79) | 6 | Oceanic Dog {40,1}, Oceanic Kitty {30,2}, Oceanic Bunny {15,3}, Oceanic Bear {9,4}, Ocean Dragon {5,5}, Atlantic Hydra {1,6} |
| `"Lava Egg"` (90) | 7 | Lava Plume {40,1}, Lava Golem {30,2}, Lava Veltal {15,3}, **Lava Trio {9.95,4}** (96), Lava Dragon {5,5}, **Demon Dog {0.05,6}** (98) |
| `"Narmek Egg"` (101) | 8 | Moon Bunny {40,1}, Satellite Pup {30,2}, Alien Slime {15,3}, **Meteor Moth {9.95,4}** (107), Nebula Fox {5,5}, **Cosmo Cat {0.05,6}** (109) |

- 49 pool entries in total. A script check confirmed that every internal key appears in **exactly one** egg, and that the pool key set equals the `M.PETS` key set.
- `Order` 1..8 matches the plan's egg tier. It also matches EggPlacement's `BiomeIndex` (taken from the biome folder prefix `"01 Spawn"`…`"08 Narmek"`).
- The Basic pool sums to **100.002**. `Roll` normalises by the sum, so Gregory's real odds are 0.002/100.002. Lava and Narmek sum to 100.
- **Rank lives only in `EGGS[egg].Pets[key].Rank`**. `M.PETS` has no rank. Implementers need a reverse map from key to egg (Order and Rank).

### 1.2 `M.PETS` (lines 115-173)
```lua
M.PETS["<internalKey>"] = {Rarity = "<Common|Uncommon|Rare|Legendary|Mythical>", DisplayName = "<shown name>"}
```
- Counts: 16 Common, 12 Uncommon, 11 Rare, 7 Legendary, and 3 Mythical (`Gregory` line 123, `Demon Dog` 165, `Cosmo Cat` 172). There are **no Epic pets**.
- The rarity and display names match PLAN section 5 row for row (verified for all 49).
- Keys are the model names in `ReplicatedStorage.Assets.Pets`. `_structure.txt` lists 49 Models there, one per key.

### 1.3 Colour tables
- `M.RARITY_GRADIENTS` (176-185): entries for Common, Uncommon, Rare, **Epic (180: 249,215,255 → 226,0,255)**, Legendary, Mythical, Omega, and Special.
- `M.RARITY_GLOW` (186-195): **Epic = 226,0,255** (190). Omega and Special also appear.
- `M.RARITY_ORDER` (196): `{Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythical=6, Omega=7, Special=8}`. It has gaps (Epic 4), so sort by the value rather than by position.
- Epic, Omega, and Special are unused colours. EggHatchClient's `RevealFX` also has an `"Epic"` sound branch (302).

### 1.4 Functions
| Fn | Lines | Behaviour / gotcha |
|---|---|---|
| `EggKey(eggName)` | 199-204 | Strips a trailing `"(…)"` and `"Egg"`, then appends `" Egg"`. It returns nil when the result is not in EGGS. `"Basic"` → `"Basic Egg"`. |
| `PoolOf(eggName)` | 206-209 | Returns **two values**: `pool, key`. |
| `Roll(eggName, rng?)` | 213-229 | Draws a float in `u * total` and walks the pool with `pairs()`. `rng` is a `Random` object (it uses `rng:NextNumber()`). The iteration order of `pairs` is not a documented contract, so **a fixed seed does not map to a fixed pet across VMs**. Only the distribution is stable. |
| `PercentOf(egg, pet)` | 231-235 | Returns the raw Percent, not normalised. |
| `ChanceText(egg, pet)` | 238-246 | Returns `"[1 in N]"` using `100/percent`, not `total/percent`. Gregory gives `"[1 in 50000]"`. It returns nil when the pet is not in that egg. |
| `RarityOf(pet)` | 248-251 | **An unknown key returns `"Common"`.** Do not use it to validate keys. |
| `DisplayNameOf(pet)` | 253-256 | An unknown key returns the key itself. |
| `ListedPets(egg)` | 259-268 | Skips rank-less entries, which is how Gregory is hidden. **No live script calls this.** |
| `ModelOf(pet)` | 270-274 | Returns `ReplicatedStorage.Assets.Pets:FindFirstChild(pet)` or nil. The catalog stores no model references itself. |

Stale comments (fix them if touched): line 14 says "no pet saving yet". Pets have saved `{Pet,Pos}` since 2026-09-12.

---

## 2. Eggs: purchase → placement → timer → save/restore

### 2.1 EggShop tool (`ServerScriptService.EggShop`)
- `RollEgg(eggName, player)` (257-271) returns `{Kg, Scale, Material, Mutations(list), Strength}`.
  - Material comes from `CucumberMutations.RollMaterial()` (nil, `"Golden"`, or `"Diamond"`).
  - Mutations are rolled with 8% chance (`MUTATION_CHANCE`, line 69) and are then a list of 1..4 **distinct** names.
- `BuildTool` (274-329) sets these Tool attributes (283-289): `EggName` (the **short** name, e.g. `"Basic"`), `DisplayName`, `Kg`, `Scale`, `Material` (**`""` when normal**), and `Mutations` (`CucumberMutations.Join` comma string). It adds the tag `"EggTool"` (289).
  - `Purchase` adds `Price` afterwards (347).
  - The client adds `Announced` (EggShopClient 32).
  - `CanBeDropped=false`, and the tool name is `"<display> (<kg>)"`.
- Egg tools are **not saved**. A tool in the Backpack is lost on leave.
- Dev hook (Studio only, 420-437): `workspace:SetAttribute("EggShopDev", "buy:<EggName>" | "reset")`. The hook resets the attribute to **nil**.

### 2.2 EggPlacement (`ServerScriptService.EggPlacement`)
- At start, it builds `ReplicatedStorage.PlaceableModels/"<EggName> Egg"` (94-124).
  - The model gets an invisible `Hitbox` PrimaryPart with CanQuery=true.
  - The template carries the attributes `EggName` (short) and `BiomeIndex` (120-121). Clones inherit both.
- `Place(player, tool, cframe)` (158-226) runs through the RemoteFunction `Remotes.requestPlacement` (317-324), which returns `ok, reason`.
  - The tool must have the `EggTool` tag.
  - The player must be at the base (within ±6 studs).
  - The server rebuilds the CFrame from the client's X/Z and yaw, then checks the bounds and the overlap against `plot.Placed`.
  - **Attributes on the placed egg** (204-221): `Owner`, `EggName`, `Kg` (default 0), `Scale` (clamped 0.5..5), `Material` (**nil for normal**, since `""` becomes nil at 209), `Mutations` (Join string, `""` if none), `DisplayName`, `HatchSeconds`, `PlacedAt`, and `HatchAt` (server clock = `workspace:GetServerTimeNow()`). `BiomeIndex` is inherited from the template.
  - It applies `CucumberMutations.ApplyLook(placed, material, mutations)` (216), adds the tag `"PlacedEgg"` (222), and parents the egg to `plot.Placed` (223).
  - Finally it runs `tool:Destroy()` (224).
- `HatchSeconds(biomeIndex, kg, material, mutations)` (128-134) computes `HATCH_BY_BIOME` = {3, 10, 30, 90, 240, 600, 1500, 3600, 3600, 3600} s (49), multiplied by a kg factor, a mutation factor, and a material factor.
- **There is no egg ID anywhere.** No attribute, record field, or tool attribute carries one.
- `plot.Placed` holds **eggs, placed cucumbers, and builds together** (BuildService 191 and CucumberCarry 856 use the same folder).
- When the plot's `Owner` clears, EggPlacement empties **the whole `Placed` folder**, including cucumbers and builds (311-313, `HolderOf(plot):ClearAllChildren()`).

### 2.3 EggTimerClient
- Adds a BillboardGui `"EggTimer"` (8×4.2 studs, `AlwaysOnTop=false`) to each `PlacedEgg`.
- It reads `EggName`, `Material` (falling back to `Golden`), `Mutations`, and `HatchAt`.
- It shows "Ready!" when `HatchAt <= now` (114-118). It ignores `Hatching` and any consumed state.

### 2.4 PlacementClient
- Shows a preview with `ApplyLook` (154) and calls `requestPlacement:InvokeServer(tool, TargetCF)` (134).
- Nothing in it concerns IDs or pets.

### 2.5 Saved egg record (BaseSaveService `Collect`, 96-105)
```lua
{ EggName = "Basic", Kg = 198, Scale = 2.19, Material = "Golden"|nil (key ABSENT when normal),
  Mutations = "SHADOW,RADIOACTIVE,FROZEN" | "",   -- comma string, CucumberMutations.Join
  DisplayName = "...", HatchSeconds = 4, PlacedAt = <server time>, HatchAt = <server time>,
  Pivot = {12 numbers: anchor:ToObjectSpace(egg:GetPivot())} }
```
- `Owner`, `BiomeIndex`, and `Hatching` are not saved.
- Collect includes **every** `PlacedEgg` with a matching `Owner` that is a descendant of the plot and has an `EggName`. It has no consumed or hatching filter.

### 2.6 Egg restore
- `EggPlacementAPI.RestoreEgg(player, plot, record, pivot)` (231-259) returns `placed` or `nil, reason`.
  - It rebuilds from the template, clamps Scale, runs `Join(record.Mutations)`, and treats a Material of `""` as nil.
  - If `HatchAt` is missing it defaults to `now` (ready immediately). If `HatchSeconds` is missing it is derived from HatchAt and PlacedAt.
- BaseSave restores **eggs first** (187-193), then builds, cucumbers, and pets. The header comment at line 14 omits eggs.
- A failed egg restore is **not kept**: only cucumbers are kept (`Kept`, 63, 216-228). It is dropped by the next snapshot, the same as pets.

### 2.7 CucumberMutations facts that matter for inheritance
- `Parse(str|table)` (94-104) **drops unknown names** and **does not dedupe**.
- `Join(list)` (106-108) is `table.concat(Parse(list), ",")`. Placed and restored eggs can therefore never contain unknown mutation names, because Join runs at placement (208) and restore (242).
- The known names are NEON, SHADOW, FROZEN, RADIOACTIVE, MOLTEN, ROYAL, VOID, and PRISMATIC (36-45). The materials are Golden and Diamond (46-49).
- `ApplyLook(model, material, mutations, opts)` (320-391) has these effects:
  - It **recolours every BasePart** to the material colour, or to the first mutation's colour when there is no material.
  - Diamond sets `Material=Glass`.
  - It adds `Mutation_<NAME>` emitters and `MutationLight` / `DiamondLight` / `DiamondSparkle`.
  - **PRISMATIC starts a `while model.Parent` recolour loop** every 0.15 s (379-390).

---

## 3. Hatch flow (`ServerScriptService.PetHatchService`)

### 3.1 Config (44-56)
`EGG_TAG="PlacedEgg"`, `PET_TAG="PlotPet"`, `STEP_MARGIN=1.25`, `STEP_HEIGHT=7`, `REVEAL_FALLBACK=80`, `PET_FIT=5`, `EDGE_INSET=2`,
`SPEED_MIN,MAX=5,8`, `IDLE_MIN,MAX=1.5,4.5`, `LEG_MIN,MAX=8,26`, `PLAN_TICK=0.2`, `TRIGGER_TICK=0.15`, and `PLOTS=workspace.Map.Lobby.Plots`.

The remote `Remotes.PetHatch` (RemoteEvent) is **created at runtime** by this script (59-70). The edit-mode `Remotes` folder only holds GymBoardState and GymBoardAction.

### 3.2 State (74-77)
```lua
Pending[player] = {Token = <int>, Plot = <plot>, Pet = <key>, Spot = <Vector3>, EggName = <short name>}
Hatched[player] = <session count>   -- mirrored to player attribute "PetsHatched" (no reader anywhere)
Rng = Random.new(); TokenCounter = 0
```
Pending does **not** store Material, Mutations, Kg, Scale, or DisplayName. These traits are lost at Finish (PLAN issue 2).

### 3.3 Trigger: `CheckEgg(egg, now)` (335-351) from Heartbeat every 0.15 s (358-364)
The loop scans **every** `PlacedEgg` in the server. An egg hatches when all of these hold:
- The egg is still parented and does not have `Hatching` set.
- `HatchAt <= now`.
- The owner (from the `Owner` attribute) is in-game with no `Pending[owner]`, which limits each player to one hatch at a time.
- The owner's `HumanoidRootPart` is inside the `egg.PrimaryPart` (Hitbox) footprint, with `STEP_MARGIN` on X and Z, and between `-half.Y-2` and `half.Y+STEP_HEIGHT` on Y.

When all hold, it calls `Hatch(owner, egg)`. There is no check for night, raid, or combat.

### 3.4 `Hatch(player, egg)` (315-332)
- `plot = PlotOf(player)`, and returns if there is none.
- `egg:SetAttribute("Hatching", true)`, and `spot = egg:GetPivot().Position`.
- `look = {DisplayName, Scale (tonumber or 1), Material, Mutations}` is read from the egg attributes.
- If `BeginReveal(...)` succeeds, **`egg:Destroy()` runs immediately, in the same server step as the Begin fire** (327-328). Otherwise it clears `Hatching` and returns.
  - When a pool is missing, CheckEgg retries every 0.15 s and warns each time.
- Destroying the egg removes its tag. BaseSave's `QueueOwner` then takes a snapshot 0.5 s later and calls `RequestSave`, so **the egg leaves `Data.Base` about 0.5 s after the hatch starts**. The pet only enters `Data.Base` once `Finish` spawns it.

### 3.5 `BeginReveal(player, plot, spot, eggName, look, forcedPet)` (284-313)
- `pool, key = Catalog.PoolOf(eggName)`. It warns and returns false if there is no pool.
- `pet = forcedPet` is used only if `pool[forcedPet]` exists. Otherwise `pet = Catalog.Roll(eggName, Rng)`.
- `TokenCounter += 1`, then `Pending[player] = {...}`.
- It fires **`PetHatch:FireClient(player, "Begin", payload)`** (295-307) with this payload:

| field | value |
|---|---|
| `EggName` | the egg's `EggName` attribute (short, e.g. `"Basic"`) |
| `EggKey` | `"Basic Egg"` |
| `EggDisplayName` | `look.DisplayName or key` |
| `Scale` | `look.Scale or 1` |
| `Material` | `look.Material` (**nil when normal**) |
| `Mutations` | `look.Mutations or ""` (comma string) |
| `Pet` | internal key |
| `PetDisplayName` | `Catalog.DisplayNameOf(pet)` |
| `Rarity` | `Catalog.RarityOf(pet)` |
| `Percent` | `Catalog.PercentOf(eggName, pet)` |
| `Chance` | `Catalog.ChanceText(eggName, pet)` (string or nil) |

  **The payload has no token, no Kg, and no pet ID.** The client uses EggName, Scale, Material, Mutations, Pet, PetDisplayName, Rarity, and Chance, and ignores EggKey, EggDisplayName, and Percent.
- It then runs `task.delay(REVEAL_FALLBACK=80, function() if player.Parent then Finish(player, token) end end)` (308-310).
- It logs a print (311).

### 3.6 Messages on `Remotes.PetHatch`, complete list
- Server → client: only `"Begin", payload`.
- Client → server: only `"Opened"`, with **no arguments**.
- The handler at 382-384, `if action == "Opened" then Finish(player) end`, runs with `token = nil`. Because of `if token and pending.Token ~= token` (274), **any Opened finishes whatever is currently pending**.

### 3.7 `Finish(player, token)` (271-282)
- `Pending[player] = nil`.
- If `pending.Plot` still exists and its `Owner == player.UserId`, it calls `SpawnPet(player, plot, pending.Pet, pending.Spot)`. If not, **the pet silently never exists**.
- It then increments `Hatched`, which updates the `PetsHatched` attribute.

### 3.8 Leave handling (395-398)
- `Pending[player] = nil` and `Hatched[player] = nil`.
- The fallback closure checks `player.Parent` and does nothing.
- The egg was already destroyed and removed from the save, so **leaving mid-reveal loses the egg and never grants the pet** (PLAN issue 1 is confirmed).
- Admin reset and Reload **do not** clear `Pending`. A pet that is pending during a reset still spawns afterwards, and the next snapshot then saves it.

---

## 4. `EggHatchClient` - reveal, HUD/camera handling, and the three `Opened` paths

- Config (45-57): `WATCHDOG=95` s is **longer than the server's `REVEAL_FALLBACK=80`**. `CLICK_IDLE_TIMEOUT=15` auto-advances each of the 4 click stages. Other values are `HOLD=2.5` and `PET_REVEAL_MAX_HEIGHT=3.4`.
  - An idle player's reveal takes about 66 s. `BuildEgg` can add up to 15 s of `WaitForChild` (329), which can exceed the 80 s server fallback.
- State (60-64): `Busy`, and `Token`, which is a **local counter unrelated to the server token**.

### 4.1 Hiding and restoring
- `Reveal` saves the camera type first. The OnClientEvent handler also records its own `prevCameraType` (521).
- `HideUi()` (255-270) handles the GUI layers:
  - It records each PlayerGui `LayerCollector`'s `Enabled` in `LayerStates` (all except `EggRevealUI`) and disables it.
  - It records every `CoreGuiType` in `CoreStates`, then calls `SetCoreGuiEnabled(All, false)`.
- `PlayerGui.ChildAdded` (272-274) also hides **any layer added while `Busy`**.
  - This includes `Notify`'s `"GameNotify"` ScreenGui and the reveal's own `"HatchRevealGlow"` ScreenGui (created in `RevealFX`, 310-321). The rarity glow is therefore likely never visible.
  - Any new reveal or stat UI must be placed **inside `EggRevealUI`**. Owner toasts sent during a reveal will not be seen.
- Camera: `Camera.CameraType = Scriptable` (443), with the CFrame unchanged. The egg and pet are built under `workspace.CurrentCamera`.
- `Restore(prevCameraType)` (423-438):
  - Inside a pcall: `Catcher.Visible=false`. If the camera is Scriptable, it sets the type back to `prevCameraType or Custom`. It destroys the camera children `HatchEgg`, `HatchPet`, `ShakeSparkles`, and `EggOpen`, and clears `SingleLayer`.
  - It then calls `StopRiser()` and `RestoreUi()` (276-289), which restores the layers that are still parented and the CoreGui states.
- `BuildEgg(info)` (327-364) clones `PlaceableModels["<EggName> Egg"]`, scales it by `info.Scale` (clamped, max 5.5 studs tall), and runs `pcall(ApplyLook, egg, info.Material, info.Mutations)` (348).
- `BuildPet(petName, cf)` (366-383) clones `Catalog.ModelOf`, caps the height at 3.4, and anchors it. **It applies no material or mutation look.**
- `BuildCard(info)` (385-415) uses `EggRevealUI.SingleTemplate`, which has these labels (from `_gui_tree`):
  - `PetName` shows the display name with the rarity gradient.
  - `PetRarity` shows the rarity.
  - `PetUnlocked` is **always hidden** (405-406: "needs saved discovery data; none yet").
  - `PetChance` shows `info.Chance`.
- Studio hook: `EggRevealUI:SetAttribute("DevClick", n)` counts as a click (226-230), but only while `ClickCatcher.Visible`.

### 4.2 The three acknowledgment paths, all in `PetHatch.OnClientEvent` (511-539)
1. **Busy** (513-517): if a Begin arrives while `Busy`, it runs `warn(...)` and `PetHatch:FireServer("Opened")` immediately, with no reveal. This happens in practice because the server fallback (80 s) is shorter than the client watchdog (95 s): after the fallback, the server can start another hatch while the client is still Busy.
2. **Watchdog** (522-529): `task.delay(95)` checks `if Busy and Token == myToken`. If so, it runs `Restore(prevCameraType)`, sets `Busy=false`, and sends `FireServer("Opened")`.
3. **Normal finish** (530-538): `pcall(Reveal, info)`. If the pcall fails, it warns and runs `Restore(prevCameraType)`. **Then**, `if Token == myToken`, it sets `Busy=false` and sends `FireServer("Opened")`. The error path acknowledges too.
   - `Reveal` itself calls `Restore` at its end (508). Opened is therefore sent after the camera and HUD are back.
- **Double ack is possible.** If the watchdog fires, the `pcall` path can still send a second `Opened` later, because `Token` is unchanged. Today that could finish a *later* pending hatch early. With server tokens this must be ignored.

---

## 5. Pet spawn: `SpawnPet(player, plot, petName, spot)` (191-241)

1. `template = Catalog.ModelOf(petName)`. If there is none, it warns `"[PetHatchService] no model for pet X"` and returns nil.
2. `pet = template:Clone(); pet.Name = petName` (internal key).
3. **Size cap** (200-202): `factor = min(1, PET_FIT/size.X, PET_FIT/size.Y, PET_FIT/size.Z)`. If `factor < 1`, it calls `pet:ScaleTo(pet:GetScale()*factor)`. It shrinks only and never grows.
4. Every BasePart gets `Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false, Massless=true`. `BodyMover/BodyGyro/BodyPosition` are destroyed. `partCount` is counted (203-215).
5. `root = pet.PrimaryPart or pet:FindFirstChild("Root") or first BasePart`. If there is none, it destroys the pet and returns nil. Otherwise it sets `pet.PrimaryPart = root`.
6. `rootToBottom = RootToVisibleBottom(pet, root)` (103-117). This measures parts with Transparency < 0.95 and falls back to the bounding box.
7. `radius = max(fitted.X, fitted.Z)*0.5`; `pos = ClampToPlot(plot, spot, radius)`; `yaw = random 0..2π`.
8. `pet:PivotTo(CFrame.new(pos.X, PlotTop+rootToBottom, pos.Z) * yaw)` (224). This is the **only** time the server ever moves a pet.
9. **Attributes** (226-237): `PetName` (key), `DisplayName`, `Rarity`, `Owner` (UserId), `OwnerName`, `Plot` (plot.Name), `PartCount`, `RoamRadius`, `RoamGroundY` (PlotTop), `RoamPhase` (0..2π), `RoamTo` (Vector3 at PlotTop), and `RoamIdleUntil` (now+0.5..2).
   - `RoamFrom`, `RoamStart`, and `RoamEnd` are **not** set at spawn.
10. `CollectionService:AddTag(pet, "PlotPet")` (238) runs **before** `pet.Parent = PetsFolderOf(plot)` (239). The tag-added signal fires on parenting.
11. It returns the model.

- `PetsFolderOf(plot)` (87-95) creates `plot.Pets` (Folder) on demand. All plots get one at start (388).
- `ClearPlotPets(plot)` (243-246) runs `plot.Pets:ClearAllChildren()`.

---

## 6. Roam planner (server)

- `PlotTop(plot) = plot.Position.Y + plot.Size.Y/2` (97-99). Plot Y never changes on resize (PlotUpgradeService `Resize` 118-127 changes Size X/Z and moves the CFrame, keeping the back edge fixed).
- `RoamBounds(plot, radius)` (120-124) gives half-extents `max(Size/2 - EDGE_INSET - radius, 0.5)` on X and Z.
- `ClampToPlot(plot, worldPos, radius)` (126-133) clamps in plot space and returns the point **at PlotTop**.
- `Blocked(plot, pos, radius)` (135-143) runs `GetPartBoundsInBox` with an Include filter on `plot.Placed`.
  - The box is `CFrame(pos.X, PlotTop+2, pos.Z)` with size `(2r, 4, 2r)`.
  - It catches eggs, cucumbers (`PlotHitbox`), and builds. Upstairs flooring sits above the box and is not included.
  - It returns false if Placed is missing or empty. Pets are CanQuery=false, so they never block each other.
- `PickPoint(plot, from, radius)` (147-163) returns nil when no free point is found:
  - It makes 10 tries of a random-direction leg of `LEG_MIN..LEG_MAX` length, clamped, with ≥3 studs moved and not Blocked.
  - It then makes 10 tries of a uniformly random point in the bounds with the same tests.
- **Only the endpoint is tested. The straight walk can pass through builds, eggs, and cucumbers.**
- `PlanLeg(pet, plot)` (165-188):
  - `radius = RoamRadius or 2`.
  - `from = RoamTo`, or the pivot position when RoamTo is not a Vector3. It is then run through `ClampToPlot` (173). This is **the only reaction to a plot resize**: the leg that is in progress finishes, and the *next* leg starts from the clamped point.
  - If no target is found, it sets **only** `RoamTo = from` (clamped) and `RoamIdleUntil = now + idle`. The old From/Start/End stay (stale, already completed).
  - Otherwise, it computes `duration = dist / NextNumber(5,8)`. `dist ≥ 3`, so the duration is at least 0.375 s. It then sets, **in this order**: `RoamFrom`, `RoamTo`, `RoamStart=now`, `RoamEnd=now+duration`, `RoamGroundY=PlotTop`, `RoamIdleUntil=now+duration+NextNumber(1.5,4.5)`.
  - It has no sequence or generation attribute.
- Loop (365-378): every 0.2 s it walks **every plot's** `Pets` children (Models) and calls `PlanLeg` where `now >= RoamIdleUntil`.
  - The clock is `workspace:GetServerTimeNow()`.
  - The server reads back only `RoamTo`, `RoamRadius`, and `RoamIdleUntil`.
- **The server pivot never changes after spawn.** `pet:GetPivot()` is the spawn point, and that is what BaseSave saves as `Pos`.

---

## 7. `PetRoamClient` (per-frame logic)

- Constants: `TAG="PlotPet"`, `WALK_STEP_RATE=9`, `WALK_BOUNCE_HEIGHT=0.7`, `SETTLE_RATE=10`, `TURN_RATE=8` (19-24).
- `Attach(model)` (63-89) runs for existing and newly tagged models:
  - It sets `pets[model]=false` as a reservation.
  - In a task, it resolves `root = PrimaryPart or WaitForChild("Root",10)`.
  - It waits up to 5 s until the BasePart count reaches `PartCount` (streaming guard, 70-77).
  - It bails if the model was unparented or the reservation changed.
  - It builds the state `{Root, RootToBottom, Yaw, TargetYaw, Phase=RoamPhase or random, Pos=root XZ}`.
- `RootToVisibleBottom` (29-48) also **locally** sets `CanCollide/CanTouch/CanQuery=false` on every part.
- `Detach` (91-93) runs on tag removed, or from the Heartbeat when `model.Parent` or `Root.Parent` is nil.
- Heartbeat (103-141): `now = workspace:GetServerTimeNow()`, `settle = 1-exp(-dt*10)`, and `turn = 1-exp(-dt*8)`.
  - If `RoamFrom`, `RoamTo`, `RoamStart`, and `RoamEnd` are all valid **and `t1 > t0`**, it computes `a=(now-t0)/(t1-t0)`:
    - `a≤0` → `from`.
    - `a≥1` → `to`.
    - Otherwise it lerps, sets `walking=true`, and updates `TargetYaw = atan2(-d.X,-d.Z)` when the horizontal distance is above 0.2.
  - Else, if `RoamTo` is a Vector3, the target is `to`. Else, the target is the current Pos.
  - `s.Pos = s.Pos:Lerp(targetXZ, settle)` (134). This is an **exponential low-pass that already trails the logical point** by about speed/10, roughly 0.5–0.8 studs while walking.
  - The yaw is smoothed. The bounce is `|sin(now*9+phase)|*0.7` only while walking.
  - It calls `model:PivotTo(CFrame.new(Pos.X, GroundY+RootToBottom+step, Pos.Z) * Angles(0,Yaw,0))` (137).
  - `GroundY` (55-61) reads `RoamGroundY`, falls back to plot top via the `Plot` attribute, and then to the pivot Y.
- `workspace.StreamingEnabled` is on (see the HeadbandService comment at line 66), and pet models use the default streaming mode.
  - **Likely gap (not Studio-verified):** if only the `Root` streams out, `Detach` runs. The Model instance stays with its tag, so no InstanceAdded fires when it streams back, and the pet is never re-attached. It would sit frozen at the server spawn pivot on that client.
  - Parts that stream in after the 5 s wait keep their server-relative offsets.

---

## 8. Persistence of pets today (BaseSaveService) + the real profile

- `Collect` (125-129) produces pet records `{Pet = PetName attr, Pos = PackV(anchor:PointToObjectSpace(pet:GetPivot().Position))}`.
  - `anchor = plot.CFrame * CFrame.new(0, Size.Y/2, BuildCatalog.BackZ(plot))` (74-77).
  - `Pos` is the **spawn** point, plus the root height in Y, which is ignored on restore.
- Restore (230-236) calls `spawnPet:Invoke(player, plot, rec.Pet, anchor:PointToWorldSpace(pos))` for each record that has `Pet` and a valid `Pos`.
  - A failure increments `failed`, which skips only the first "truth" snapshot (241). The next queued or 30 s heartbeat snapshot (`Collect` rebuilds from tags) **drops the failed pet** (PLAN issue 4). **Failed eggs are dropped the same way.**
- Triggers: tag add or remove on `PlotPet` and `PlacedEgg` calls `QueueOwner`, which snapshots after 0.5 s and calls `RequestSave` (250-256). There is also a quiet heartbeat every 30 s (273-280). **There is no snapshot on leave** (261-271).
- `DataService.TEMPLATE.Base = {Version = 1, Cucumbers, Builds, Pets, Eggs}` (DataService 66). BaseSave writes `VERSION = 2` (34).
  - `DataService.ResetProfile` (166-179) rewrites `Data.Base` with the **Version-1 template**. The admin reset path first writes an empty Version-2 base (BaseSave 307), then ResetProfile overwrites it with Version 1.
- The real profile (`_profile_Player_140977250_before-pets.json`):
  - `Data.Base.Version = 2` and `SavedAt = 1790106753`.
  - `Pets`, 4 legacy records:
    - `{Pet="Cat",Pos={-16,2.5,51}}`
    - `{Pet="Cat",Pos={-5,2.5,28}}`
    - `{Pet="Treasure Gem",Pos={1,2.5,53}}`
    - `{Pet="Dog",Pos={-11,1.166,35}}`
    
    These are two Basic Commons of the same species, one Desert Common, and one Basic Common. There are no IDs and no traits.
  - `Eggs`, 3 records, all with `HatchAt` in the past, so all are ready:
    - Golden NEON Basic: Kg 5, Scale 1.2, HatchSeconds 300, **Pivot Y = -225.92**.
    - Normal Basic: Kg 2, Scale 1, HatchSeconds 60, **no `Material` key**, **Pivot Y = -226.42**.
    - `"SHADOW,RADIOACTIVE,FROZEN"` Basic: Kg 198, Scale 2.197, HatchSeconds 4, Pivot Y 5.22 (normal).
  - The first two eggs are saved about 226 studs **below** the plot surface, apparently from an early world-space save; plots sit at roughly Y -226. They restore buried, can never be stepped on, and so never hatch. Every snapshot re-saves them.
  - The profile also contains a legacy top-level `Coins` key next to `Cash` (not in `REMOVED_KEYS`). This is not the pet system's business.

---

## 9. Bindable APIs and their callers

| API (ServerStorage) | Publisher (lines) | Signature → return | Callers |
|---|---|---|---|
| `PetHatchAPI.SpawnPet` | PetHatchService 254-260 | `(player, plot, petName, spot:Vector3)` → the pet Model or nil. It validates the types and `plot.Parent`. | BaseSaveService 52 (Bindable) and 233 (restore) |
| `PetHatchAPI.ClearPets` | PetHatchService 261-267 | `(plot)` → `true` (runs `ClearAllChildren` on plot.Pets) | BaseSaveService 53, 301 (`Reset`), 326 (`Reload`) |
| `EggPlacementAPI.RestoreEgg` | EggPlacement 279-282 | `(player, plot, record, pivot:CFrame)` → the Model, or `nil, reason` | BaseSaveService 54 and 190 |
| `EggPlacementAPI.ClearEggs` | EggPlacement 283-286 | `(plot)` → the count of destroyed `PlacedEgg`s in plot.Placed | BaseSaveService 55, 302 (`Reset`), 327 (`Reload`) |
| `BaseSaveAPI.Snapshot/Reset/Resume/Reload` | BaseSave 283-333 | - | AdminService 81-82 (Reset, Resume); CucumberMoveServer 107 and ZombieRaidService 631 (Snapshot). `Reload` has **no live caller** and is only a test hook. |

- BaseSave's `Bindable(folder, name)` (42-47) runs at **script top level** with `WaitForChild(…, 120)` **per object** (48-55).
  - If `PetHatchAPI` or either bindable goes missing, BaseSaveService stalls up to 120–240 s before it registers `OnProfileLoaded` (259). Nothing restores during that time.
  - So keep publishing both names, or patch BaseSave in the same step.
- The lifecycle hooks keyed off the plot `Owner` attribute:
  - PetHatchService 386-393 → `ClearPlotPets`.
  - EggPlacement 307-315 → the whole `Placed` folder is cleared.
  - These are triggered by PlotService `Release` on PlayerRemoving (163-171, 198) and by AdminService's Owner bounce (91-101).

---

## 10. Dev hooks (all Studio-only, `RunService:IsStudio()`)

- **PetHatchService** (401-430): `workspace:SetAttribute("PetHatchDev", cmd)`. The hook resets the attribute to `""`. `player = Players:GetPlayers()[1]`.
  - `"ready"`: sets `HatchAt = now` on **every** `PlacedEgg` on the server.
  - `"clear"`: runs `ClearPlotPets` on every plot.
  - `"hatch:<EggName>[:<Pet>]"`: calls `BeginReveal` at the plot centre with `look = {}` if nothing is Pending. It uses **no egg**, so there is no EggId to consume, and a Pet not in the pool is ignored.
  - `"spawn:<Pet>"`: calls `SpawnPet` at the plot centre. Because BaseSave snapshots tags, this **effectively grants a saved pet** today.
- **EggShop**: `"EggShopDev"` accepts `buy:<EggName>` or `reset`.
- **EggHatchClient**: the `EggRevealUI` attribute `DevClick`.
- **AdminService** (live-profile reset): the UserId 140977250 permission check at 111.

---

## 11. What moves into `ServerStorage.PetService` vs what stays in `PetHatchService`

**Move (extract) into PetService**, which is the owner of plot-pet runtime:
- The constants `PET_TAG`, `PET_FIT`, `EDGE_INSET`, `SPEED_MIN/MAX`, `IDLE_MIN/MAX`, `LEG_MIN/MAX`, and `PLAN_TICK` (45, 49-54), plus the `PetsAssets` reference (71).
- `PetsFolderOf` (87-95), `PlotTop` (97-99), `RootToVisibleBottom` (103-117), `RoamBounds` (120-124), `ClampToPlot` (126-133), `Blocked` (135-143), `PickPoint` (147-163), `PlanLeg` (165-188), `SpawnPet` (191-241), and `ClearPlotPets` (243-246).
  - `SpawnPet` becomes "spawn an **existing owned record**": it takes a record rather than a name, stamps `PetId`, and never grants anything.
- The **planner half** of the Heartbeat loop (357, 365-378), which should become the shared scheduler. It also needs a separate `Random` instance for roam, so the hatch-roll RNG stays injectable on its own.
- The `plot.Pets` creation and the `Owner`→nil despawn wiring (386-393). Despawning must **never** touch ownership.
- `PetHatchAPI.SpawnPet/ClearPets` (249-268), republished as **compatibility adapters** for as long as BaseSave calls them. SpawnPet means "attach an existing record", and ClearPets means "despawn runtime models only".
- The dev branches `"clear"` and `"spawn:"` (411-414, 422-427). `spawn:` must explicitly choose between grant and display-only.
- The remaining ownership pieces: the canonical record, roster, ID index, save/restore, and presentation-pending state. Today these do not exist; ownership is inferred from world tags by BaseSave.

**Stay in PetHatchService** (trigger, roll, and reveal):
- `EGG_TAG`, `STEP_MARGIN/HEIGHT`, `REVEAL_FALLBACK`, `TRIGGER_TICK`, the `PetHatch` remote creation (59-70), `Pending`, `Hatched`, `TokenCounter`, and the roll `Rng`.
- `PlotOf` (a duplicate is fine), `CheckEgg` (335-351), and the trigger half of Heartbeat (356, 358-364).
- `Hatch` (315-332). This becomes: validate, then take a per-egg lock, then commit through PetService (grant + remove the egg record atomically), then mark the egg consumed and destroy it, then fire Begin.
- `BeginReveal` (284-313). It keeps the roll and payload, and adds PetId, token, and traits.
- `Finish` (271-282). It becomes "presentation done" and calls PetService to spawn the already-owned pet.
- The `OnServerEvent "Opened"` handler (382-384). It must check the token.
- `PlayerRemoving` (395-398). It clears only presentation state.
- The dev hooks `"ready"` and `"hatch:"`, and the ready print.

---

## 12. PLAN §2 claims vs the live code (corrections / additions)

1. The PetsCatalog row says it "stores … models". **Not stored.** `ModelOf` looks up `ReplicatedStorage.Assets.Pets/<key>` by name. Everything else in that row is correct: 49 species, 8 eggs, secret Gregory, weighted odds, internal and display names, rarity.
2. PetHatchService, issue 1: this is confirmed, and slightly worse than described. The egg is destroyed **in the same step** as the Begin fire (327-328), and the profile loses it within about 0.5 s (a tag-removed snapshot). A pending pet is also not cleared by admin reset or Reload.
3. Issue 2: confirmed. In addition, **`Kg` is not even in the reveal payload**, and a normal material is `nil` in the payload and on the egg attribute, `""` on the tool, and an **absent key** in the saved egg record.
4. Issue 4: confirmed for pets, and **the same is true for eggs**. Only cucumbers have `Kept`.
5. Issue 5: confirmed. `pet:GetPivot()` is always the spawn or restore point, so the saved `Pos` never reflects the roam position.
6. Issue 9: confirmed. `ResetProfile` also writes a Version-1 `Base` during an admin reset.
7. Issue 10: confirmed. `DayNightCycle` `NightDurationSeconds=45` and `DayDurationSeconds=180` (`_structure`). In addition, EggShop has a live **fallback constant** `NIGHT_SECONDS_DEFAULT = 10` (EggShop 68), not just a comment. The backup DayNightCycle in `__CarryAndEggLabelsBackup` also still says 10.
8. Issue 11: confirmed. Also, PlotService's `Release` clears the plot `Owner` on PlayerRemoving, which **independently** wipes `plot.Pets` (PetHatchService 390) and the entire `plot.Placed` (EggPlacement 312). BaseSave takes no leave snapshot at all.
9. §5 says "Gregory's hidden discovery behavior should remain as it is". **There is no pet discovery behaviour in the live code.** `ListedPets` (the only code that hides Gregory) has zero callers, there is no pet index, and the reveal card's `PetUnlocked` is always hidden. Gregory is revealed normally when hatched, with the card showing `"[1 in 50000]"`. "Hidden" can only mean "never listed in any unowned list".
10. §6 says "reuse current … obstacle checks … streamed-part readiness".
    - The obstacle check tests **leg endpoints only** against `plot.Placed`, which includes builds.
    - The readiness guard runs only at Attach, and a Root stream-out leaves the pet un-animated (see §7).
    - The client **already has** the exponential settle low-pass that §6 says not to add. It trails by up to about 0.8 studs.
11. §8.1 and §10 mismatches:
    - The egg source key is the short `EggName` (`"Desert"`); `"Desert Egg"` only comes from `Catalog.EggKey`.
    - The weight attribute is `Kg`, not `EggKg`.
    - Egg `Mutations` is a comma **string**, not an array, and it can never contain unknown names because `Join` strips them.
    - PetHatch `Opened` currently carries no arguments, and Begin has no token.
12. §3.1 tier mapping: `EGGS[*].Order` (1..8) and the egg `BiomeIndex` already encode the tier. The egg short names are `Basic`, `Desert`, `Samurai`, `Farm`, `Frozen`, `Ocean`, `Lava`, and `Narmek` (EggTimerClient 8-13). "Ocean Egg Stand" is in `06 Underwater`.
13. Stale comments to correct if touched: PetHatchService 10-11 ("Nothing is saved yet"), PetsCatalog 13-14, EggPlacement 29-30 ("nothing happens when it reaches zero yet"), and BaseSave 14 (the restore order omits eggs-first).
