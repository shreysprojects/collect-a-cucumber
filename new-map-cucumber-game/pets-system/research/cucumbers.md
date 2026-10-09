# Research: placed cucumber lifecycle (for CucumberId + pet buffs)

Source: the read-only snapshot `live-2026-09-22/` (2026-09-22). All line numbers are in those files.
Files read in full: `ServerScriptService.CucumberCarry.server.lua` (1229 lines), `ServerScriptService.CucumberMoveServer.server.lua`,
`ServerScriptService.BaseSaveService.server.lua`, `ServerScriptService.LeaderstatsService.server.lua`,
`StarterPlayer.StarterPlayerScripts.CucumberPlacementClient.client.lua`, `StarterPlayer.StarterPlayerScripts.PlacedCucumberCardClient.client.lua`.
Read in part: `ServerScriptService.CucumberSpawner.server.lua` (Register, SpawnBreakable, SpawnCarried, GetZonePoint),
`ServerScriptService.ZombieRaidService.server.lua` (Grab / RestoreCarry / ReturnDropped / Kill / Escape / EndRaid / Tick / StartGrapple / StartDig / PlayerRemoving),
`StarterGui.BuildMenu.BuildMenuClient.client.lua` (the cucumber move), `ServerStorage.CucumberAdventure.lua` (Decorate / DropMetadata),
`ServerScriptService.EggPlacement.server.lua`, `ServerScriptService.AdminService.server.lua`, `ServerScriptService.PlotService.server.lua`,
`ServerScriptService.BuildService.server.lua` (Sell), `ReplicatedStorage.Modules.ZombieCatalog.lua` (ThreatOf), `_profile_Player_140977250_before-pets.json`.

---

## 1. TL;DR

- A **placed cucumber** is a `Model` in `plot.Placed` (a Folder under the plot BasePart) with tag `"PlacedCucumber"` and attribute `Owner = UserId`. It carries an invisible anchored `PlotHitbox` Part (the footprint box; the saved `Box`/`Size`, the card's adornee, the mouse-ray target).
- It is created in exactly **two** places, both in CucumberCarry: `Place()` (the player places a shoulder-carried cucumber, line 872) and `RestorePlaced()` (BaseSaveService rebuilds it from the profile, line 967). Both set every attribute **before** `AddTag` (956 / 1038) and parent **after** (957 / 1039).
- **Same instance survives:** a build-mode move (CucumberMoveServer only `PivotTo`s it), a zombie grab (the model itself is welded onto the zombie and reparented into it), a carrier kill (dropped where it fell, re-tagged), raid end / dawn / "ZombiesWin" leftovers (sent home), `ReturnDropped`. Nothing on the model except `StolenBy` changes during a theft.
- **A new instance** is built only by `RestorePlaced()` (rejoin, `BaseSaveAPI.Reload`). **Destroyed** by: zombie `Escape` (the successful theft), `ClearPlaced` (leave / admin reset / reload), EggPlacement's "plot lost its Owner" `ClearAllChildren`, `RestoreCarry` when the raid owner or holder is gone, or the carrying zombie being destroyed from outside.
- Placed cucumbers have **no player-facing pickup and cannot be sold**: `PickUp()` is reachable only from the Studio dev hook `workspace.CarryDev = "pickup:<Name>"`.
- **No stable id exists today.** Saved records are `{Zone, Type, Golden, Material?, Mutations, SizeTier?, Name, Pivot, Box, Size}`. `JourneyId` (a GUID from CucumberAdventure) is on the model but is **re-rolled on every restore** and must not be reused as CucumberId.
- **Minimal plan:** mint `CucumberId` in `Place()` and restore it from `record.Id` in `RestorePlaced()` (both before AddTag). Save it (and the buffs) in `BaseSaveService.Collect`. Moves, zombie drops, returns and dawn keep it with no code at all. Clear buffs in `PickUp()`, and in `ZombieRaidService.Grab()` right after the new `TryBlockTheft` check. Destroy paths only unregister the runtime state and must never write `Data.Base`.

---

## 2. Lifecycle map

```
field holder (tag "Breakable", workspace.Breakables.<Zone>)          CucumberSpawner.Register 197-219
   | Lift bar "done" -> CucumberCarry.Grab 537-572: BuildCarryModel(holder) CLONE, holder:Destroy()
   v
shoulder model "CarriedCucumber" in the character (no tag, no Owner)  GiveCarry 430-487
   | Drop / DropAtFeet -> SpawnCarried => a NEW field holder; the shoulder model is destroyed (ClearCarry)
   | DropForNight -> the same model becomes "NightDroppedCucumber" debris (untagged, Debris-expired)
   | requestCucumberPlacement -> Place 872-960: Take() (the SAME model), scale back up, anchor,
   |                           add PlotHitbox, set attributes, AddTag "PlacedCucumber", parent to plot.Placed
   v
PLACED (tag PlacedCucumber, Owner, in plot.Placed)  <-- RestorePlaced 967-1041 (profile -> NEW model)
   | requestCucumberMove -> CucumberMoveServer.Move 59-111: PivotTo + hitbox re-lay (SAME instance, tag untouched)
   | ZombieRaidService.Grab 522-570: RemoveTag, StolenBy, weld, reparent INTO the zombie (SAME instance)
   |     -> Kill 713 / RestoreCarry 575-615: back into plot.Placed (maybe lying in the lobby), StolenBy nil, AddTag (SAME)
   |     -> Escape 765-770: model:Destroy()  (the successful theft)
   |     -> EndRaid/Dawn 1341, ZombiesWin 791: RestoreCarry home; ReturnDropped 618-636 PivotTo home (SAME)
   | PickUp 1069-1120 (Studio dev hook only): RemoveTag, Owner/CucumberName nil, shrink, GiveCarry (SAME model -> shoulder)
   | ClearPlaced 1043-1055 (leave, admin Reset, Reload): RemoveTag + Destroy
   | EggPlacement 311-313: plot Owner -> nil => plot.Placed:ClearAllChildren() (destroys cucumbers too)
```

---

## 3. Every place the `PlacedCucumber` tag is added or removed

| # | File : line | Op | Function | Context / state at that moment |
|---|---|---|---|---|
| 1 | CucumberCarry 956 | **AddTag** | `Place` | Model has parent nil (after `Take`, 507). All attributes already set (945-955). Parent set on the next line (957). The comment says "attributes first: LeaderstatsService stamps Rate off this". |
| 2 | CucumberCarry 1038 | **AddTag** | `RestorePlaced` | Model is a fresh `BuildCarryModel` clone, parent nil. Attributes set 1027-1037, parent 1039. |
| 3 | CucumberCarry 1049 | **RemoveTag** | `ClearPlaced` | Followed right away by `model:Destroy()` (1050). `Owner` is still set. Callers: BaseSaveService leave (268), `BaseSaveAPI.Reset` (299), `BaseSaveAPI.Reload` (324). |
| 4 | CucumberCarry 1108 | **RemoveTag** | `PickUp` | Then `Owner` nil (1109), `CucumberName` nil (1110), `Parent = nil` (1111), `GiveCarry` (1112). PlotHitbox already destroyed (1087) and the model shrunk (1089-1093). |
| 5 | ZombieRaidService 533 | **RemoveTag** | `Grab` (zombie) | Tag goes **before** `StolenBy` is set (534). The model is reparented into the zombie at 561. Callers: Tick ordinary grab 1271, grapple final 1048, digger (it surfaces, then the ordinary Tick grab). |
| 6 | ZombieRaidService 613 | **AddTag** | `RestoreCarry` | `PivotTo(rest)` 610, `StolenBy` nil 611, `Parent = holder` 612, then the tag. Callers: `Kill` 713 (drops it at the zombie's spot), `Escape` "ZombiesWin" cleanup 791, `EndRaid` 1341 (Dawn / Night / Left). |
| 7 | implicit | removal | `Escape` 770 `carry.Model:Destroy()` | Already untagged (Grab). It is only destroyed. |
| 8 | implicit | removal | EggPlacement 311-313 `HolderOf(plot):ClearAllChildren()` when `plot.Owner` becomes nil | Destroys every child of Placed (eggs, builds, **cucumbers**). The tag-removed signal fires because the instance leaves the DataModel. Triggered by `PlotService.Release` (PlayerRemoving, 163-171/198) and by the `AdminService.ResetData` Owner bounce (93-98). |
| 9 | implicit | removal | `RestoreCarry` 586-588 `model:Destroy()` | When the raid holder is gone or `raid.Player.Parent` is nil (the owner left). Already untagged. |
| 10 | implicit | removal | ZombieRaidService `Tick` 1217-1222 | The zombie model was destroyed from outside while carrying: `entry.Carry = nil`, and the cucumber goes with its parent. Already untagged. |

Readers of the tag (they don't write it): LeaderstatsService 31/54-60/156-161; ZombieRaidService `CucumbersOf` 256-266, the target check 1261, the grapple checks 1029/1035/1049; BaseSaveService `Collect` 106-118 plus the tag signals 250-256; CucumberMoveServer 30/69; CucumberCarry dev hook 1222; clients: PlacedCucumberCardClient 33/265-267, BuildMenuClient 105/947.

**Signals are Deferred in this place.** CucumberCarry 472-475 ("signals are deferred, so a detach + re-attach inside one frame...") and BaseSaveService 328 ("the tag-removed events of the clearing fire deferred") both depend on it. So tag-added/removed handlers run after the calling code has finished its synchronous segment.

**Tag signals fire only in the DataModel.** In Place/RestorePlaced, the `AddTag` happens while the model's parent is nil. `GetInstanceAddedSignal("PlacedCucumber")` therefore fires when it is parented (957 / 1039), and by then every attribute (and a future CucumberId) is already there.

---

## 4. Attributes on a placed cucumber model

### 4a. Set explicitly by `Place()` (945-955) and `RestorePlaced()` (1027-1037), in this order, before the tag

| Attribute | Type | Place() source | RestorePlaced() source | Notes |
|---|---|---|---|---|
| `Owner` | number (UserId) | `player.UserId` 945 | `player.UserId` 1027 | Cleared only by `PickUp` 1109. Never changed by the zombies. |
| `CucumberName` | string | `meta.Name` (holder.Name = display name) 946 | `record.Name`, or the new display name if the type was LEGACY-migrated, 1025/1028 | Card title, zombie "Grabbed" toasts. Cleared by `PickUp` 1110. `model.Name` is set to the same value (944 / 1026). |
| `Zone` | string | `meta.Zone` 947 | the spawned holder's Zone 1029 | One of the CucumberSpawner `ZONES` (20). |
| `TypeName` | string | `meta.TypeName` 948 | the holder's TypeName 1030 (can differ from `record.Type` because of LEGACY_TYPES, 993) | |
| `Golden` | bool | `meta.Golden == true` 949 | 1031 | true iff Material == "Golden" (spawner 723). |
| `Material` | string or nil | 950 | 1032 | "Golden" / "Diamond" / nil. |
| `Mutations` | string | `meta.Mutations or ""` 951 | 1033 | **Comma string** "NEON,FROZEN" (CucumberMutations.Join), never an array. |
| `SizeTier` | string or nil | 952 | 1034 | "HUGE" / "MASSIVE" / "COLOSSAL" / nil. |
| `SizeScale` | number | 953 | 1035 | 1 / 2 / 3 / 4. |
| `WeightKg` | number | `meta.Kg` (the lift requirement) 954 | `CucumberLift.Of(holder)` 1036 | |
| `ShownKg` | number | 955 | 1037 | |

### 4b. Set by `BuildCarryModel` (304-372) on the clone, and kept on the placed model

| Attribute | Line | Used by |
|---|---|---|
| `RestRotation` (CFrame) | 367 | Place 890, Move 79, both client ghosts |
| `RestSize` (Vector3, field scale) | 368 | footprint (CucumberFootprint.Box), bounds and overlap tests |
| `RestLift` (number) | 369 | the resting height |
| `PlaceScale` (number = 1/shrink) | 370 | Place 920-924 grows the model back; PickUp 1089-1093 shrinks it again; CucumberPlacementClient 256 |

### 4c. Inherited through the CLONE of the field holder (`BuildCarryModel` clones `src`, so every holder attribute is copied)

- From `CucumberSpawner.Register` 200-210: `SpawnDay`, `TypeName`, `Zone`, `Sliced`, `Golden`, `Material`, `Mutations`, `SizeTier`, `SizeScale`, `Tree`, `Template`.
- From `CucumberAdventure.Decorate` 173-178: `CarryTrait`, **`JourneyId`** (GUID), `JourneyRecorded`, `JourneyRecordedBy`, `JourneyRecoveryUsed`, `RescueCount`. Maybe also `RescueOwner` / `RescueUntil` (`Rescue` 185-186).
- From `CucumberCarry.AttachCollectPrompt` 694-695: `WeightKg`, `ShownKg`.
- `CollectingBy` is cleared on the holder before the clone (543 / 979), so it is never inherited.
- **`JourneyId` is NOT an identity.** `RestorePlaced` spawns a fresh holder with no `JourneyId` in `extra` (970-971), so Decorate mints a new GUID on every restore. On a field drop it is carried along instead (DropMetadata 181). Don't reuse it.

### 4d. Set by other services

| Attribute | Where | Notes |
|---|---|---|
| `Rate` | LeaderstatsService `StampRate` 47-51, run on every tag-added (157-159) and as a fallback in `EarningFor` 57 | `CucumberValues.RateOfInstance` reads Zone / TypeName / Golden / Material / Mutations / SizeTier (CucumberValues 81). It is never restamped on attribute changes, only on a tag add. It stays on the model through a Grab and through a dev PickUp. The card listens to `GetAttributeChangedSignal("Rate")` (PlacedCucumberCardClient 168-170). |
| `StolenBy` | ZombieRaidService Grab 534 (the zombie model's name), cleared in RestoreCarry 611 | Read by CucumberMoveServer 70 and BuildMenuClient 549/947. |
| (none) | `raid.Dropped[model]` (603-609) is an **internal table only** | Nothing on the model marks "dropped by a killed carrier, lying off its home spot" (see H8). |

### 4e. Children

- `PlotHitbox`: Part, Transparency 1, Anchored, CanCollide false, CanTouch false, **CanQuery true**, size = `CucumberFootprint.Box(RestSize)`. Created in Place 934-943 / RestorePlaced 1014-1023. Re-laid by Move 102-106. Destroyed by PickUp 1087.
- `BaseSaveService.Collect` **skips a cucumber that has no PlotHitbox** (108-109). The card adorns to it (PlacedCucumberCardClient 123-127). Zombie grab reach uses it (1152-1156).

---

## 5. CucumberCarry functions (the placement side)

- **`BuildCarryModel(src)` 304-372.** Clones the field holder (or wraps a Part in a Model), strips BillboardGui / ClickDetector / ProximityPrompt / scripts / "Shadow", **removes the "Breakable" tag** (328-331), welds and unanchors, shrinks to an armful, and records RestRotation / RestSize / RestLift / PlaceScale.
- **`GiveCarry(player, model, meta)` 430-487.** Welds to the shoulder, names it "CarriedCucumber", parents it to the character, sets the `Carrying*` player attributes (404-416). `AncestryConn` 476-485 destroys the model if it is displaced.
- **`Take(player)` 490-509.** Detaches the shoulder model (removes ShoulderWeld / CarryGrip), sets `Parent = nil`, returns `model, entry`. The same instance is placed afterwards.
- **`Grab(player, holder, host, force, kg)` 537-572** (the field lift, not the zombie one). `holder:SetAttribute("CollectingBy", nil)`, `BuildCarryModel(holder)`, builds `meta` from the holder attributes (546-563), `GiveCarry`, `holder:Destroy()` (566).
- **`Place(player, cframe)` 872-960.** Checks (874-913): carrying, a CFrame, `PLACE_COOLDOWN`, your own plot, standing at the base (`AT_BASE_MARGIN` 6), RestSize / RestRotation present, footprint inside the plot, no overlap with any part in `plot.Placed` (`GetPartBoundsInBox`, Include {holder}). Then `LastPlace` (915), **`Take`** (916). After `Take` the model is detached, and an error in the rest of `Place` loses the cucumber (see H4). Scale back up (920-924), `PivotTo` rest pose (926), anchor (927-932), PlotHitbox (934-943), attributes (944-955), **AddTag 956**, parent 957, `CarryFX {Kind="Placed"}` 958. Called from `PlaceRemote.OnServerInvoke` 1174-1181 inside a `pcall`.
- **`RestorePlaced(player, plot, record, pivot, boxCF, boxSize)` 967-1041.** Steps:
  1. `SpawnCarried:Invoke(record.Zone or "Spawn", record.Type, record.Golden == true, pivot.Position, {Anywhere = true, Force = true, Material = record.Material, Mutations = record.Mutations, SizeTier = record.SizeTier})` (970-971). This makes a real field holder (tag Breakable, population counted, Decorate re-rolls the trait and JourneyId).
  2. Build `meta` (973-978), `BuildCarryModel(holder)`, then `holder:Destroy()` straight away (980-981).
  3. Grow the model back by PlaceScale (983-987).
  4. If LEGACY-migrated (`meta.TypeName ~= record.Type`, 993), recompute the pivot and box (995-1006).
  5. `PivotTo(pivot)`, anchor, PlotHitbox, attributes, **AddTag 1038**, parent 1039.
  - Returns the model, or `nil, reason`.
  - **`record` is the live profile sub-table** (`data.Base.Cucumbers[i]`, passed by BaseSaveService 219). Writing to it writes the profile.
- **`ClearPlaced(plot)` 1043-1055.** For each tagged child of Placed: RemoveTag, Destroy. Returns the count.
- **`PickUp(player, placed, force)` 1069-1120.** Studio dev hook only (declared 870, "Studio hook only: placed cucumbers show no prompt"). The same instance goes back onto the shoulder. `meta.Recorded = true` (1095). It keeps every attribute except Owner / CucumberName, **including `Rate`**, and any future CucumberId or buff attributes, until code strips them.
- **`Drop` 715-753 / `DropAtFeet` 759-778.** Make a NEW field holder via `SpawnCarried` (extra = `Adventure.DropMetadata(entry)` + `Anywhere`), then `ClearCarry` destroys the shoulder model. Model attributes are **not** copied (only zone / type / golden and the DropMetadata fields).

### `ServerStorage.CucumberCarryAPI` (Folder, created 789-791) and its callers

| Bindable | Lines | Signature | Caller(s) |
|---|---|---|---|
| `DropForNight` | 792-817 | `(player) -> bool` | DayNightCycle 25 / 162 |
| `TakeCarried` | 822-832 | `(player) -> model, entry` | GuardianService resolves it at 112. The current catch uses DropAtFeet instead (1030-1042); no live `:Invoke` of TakeCarried was found. |
| `DropAtFeet` | 835-845 | `(player) -> holder?` | GuardianService 113 / 1042 |
| `RestorePlaced` | 1058-1061 | `(player, plot, record, pivot, boxCF, boxSize) -> model / nil, reason` | BaseSaveService 48 / 219 |
| `ClearPlaced` | 1062-1065 | `(plot) -> n` | BaseSaveService 49 / 268 / 299 / 324 |

Remotes owned by CucumberCarry: `DropCucumber` (RemoteEvent, 104 / 1169), `requestCucumberPlacement` (RemoteFunction, 105 / 1174), `CarryFX` (106), `CucumberLift` (107).

### CucumberSpawner pieces used by the lifecycle

- **`Register(holder, zone, typeDef, golden, material, mutations, sizeTier)` 197-219.** Sets `Live[holder]`, `TrackAdded`, the attributes (200-210), and `AddTag "Breakable"` (211). Its `AncestryChanged` hook frees the population slot when the holder leaves the workspace (213-218).
- **`SpawnCarried(zone, typeName, golden, point?, extra?)` 839-852.** `extra` fields: `Force`, `Anywhere`, `Material`, `Mutations`, `SizeTier`, `Trait`, `JourneyId`, `Recorded`, `RecordedBy`, `RecoveryUsed`, `Rescues`. Returns nil when the fields are closed or the population is full, **unless `Force`**. `Force` also skips the `CUCUMBERS_PER_BIOME` cap (845-848). `TypeByName` falls back to `LEGACY_TYPES` (819-832). There is **no id pass-through**, and none is needed: RestorePlaced sets the id on its own model.
- **`SpawnBreakable(..., fixed)` 697-800.** Keeps `fixed.Material`, `fixed.Mutations` and `fixed.SizeTier` (711-719). With `Anywhere` and a preferred point, `GetZonePoint` always returns that point, snapped to the ground (333-336). `AnnounceSpawn` stays quiet for fixed spawns (472).

---

## 6. Moves (CucumberMoveServer + BuildMenuClient)

- Server `Move(player, model, cframe)` 59-111, reached through `Remotes.requestCucumberMove` (RemoteFunction, 35-40, `OnServerInvoke` 113-120 inside a pcall).
- Refusal checks, in order: not a Model (60), bad CFrame (61), `CyclePhase == "Night"` (62), `MOVE_COOLDOWN` 0.15 (64), no plot (66), `model.Parent ~= plot.Placed` (68), missing tag or `Owner ~= UserId` (69), `StolenBy` set (70), not at base (74-77), no RestSize / RestRotation (78-80), outside the plot (88-90), overlap with anything else in Placed (94-99).
- Then **`model:PivotTo(...)`** (101), and the PlotHitbox gets its new Size / CFrame (102-106).
- Last, `ServerStorage.BaseSaveAPI.Snapshot` is invoked in a `task.defer` + `pcall` (107-109).
- **It is the same instance throughout. No tag or attribute changes, so every attribute survives: Owner, Rate, a future CucumberId, buff attributes.**
- The client never tells the server a move has started. `StartMovingCucumber` (BuildMenuClient 953-1027) clones the model into a local ghost and sets `LocalTransparencyModifier = 0.85` on the original (995-1000). Cancel is purely local. The server sees only the final atomic `InvokeServer(model, TargetCF)` (720). So **the server has no "being moved" state**: the cucumber keeps earning and stays targetable while the ghost is on the mouse.
- The ghost clone (966-984) destroys WeldConstraint / Weld / IKControl / Attachment / ProximityPrompt / BillboardGui / Highlight and disables ParticleEmitter / Light. Any other child class a server puts under the model (Beam, Trail, SelectionBox, SurfaceGui, Sound, extra Parts) **is cloned into the ghost**.
- Sell mode refuses cucumbers (BuildMenuClient 1078, "Cucumbers can't be sold here"). BuildService `Sell` requires the `PlacedBuild` tag (545).
- CucumberPlacementClient (carried → plot) clones the **shoulder** model for its ghost (251). It sends `requestCucumberPlacement:InvokeServer(boxCF)` (217, QuickPlace 201). The server trusts only X/Z and yaw.

---

## 7. Theft, drops, returns, dawn: is it the same instance?

| Event | Code | Instance | Tag / attributes |
|---|---|---|---|
| Ordinary grab (Tick 1270-1271), grapple final (1048), digger (surfaces, then Tick grab) | `Grab(entry, model, restCFrame)` 522-570 | **same** | RemoveTag 533, `StolenBy = zombie name` 534, extra CarryLink welds, `Weld "CarryWeld"` to the torso, every part unanchored + non-colliding + massless (535-560), **Parent = the zombie model** 561. `carry = {Model, Rest = restCFrame or HomeRest, Holder = model.Parent, Parts, Name}` 531. |
| Grapple pull (before the grab) | `StartGrapple` 997-1054 | same | Still tagged, **no StolenBy**. The model is `PivotTo`-lerped toward the zombie (1033-1041). If the tag disappears mid-pull the attempt aborts (1035). A failed `Grab` → `target:PivotTo(rest)` (1048). An aborted pull with the tag still present → `PivotTo(rest)` (1049-1050). |
| Carrier killed | `Kill` 710-748 → `RestoreCarry(entry, false, entry.Root.Position)` 713 | **same** | Re-stood at the zombie's feet, **possibly in the lobby, still in `plot.Placed`**. `raid.Dropped[model] = {Rest = home, Name}` (603-609), `StolenBy = nil`, Parent = holder, **AddTag** 613. It earns again right away (LeaderstatsService only checks the tag, Owner and "in workspace"). |
| Another zombie takes the dropped one | `Grab` (532 clears `raid.Dropped[model]`, `HomeRest` hands the home pose on) | same | same as a grab |
| Successful theft | `Escape` 765-800: `carry.Model:Destroy()` 770, `raid.Stolen += 1` | **destroyed** | already untagged |
| Raid over: Survived / ZombiesWin / Dawn / Night (day thieves) / Left | `EndRaid` 1336-1366 → `RestoreCarry(entry, reason ~= "Left")` 1341 (no dropAt = straight home to `carry.Rest`), then `ReturnDropped` 1351 | **same** | `ReturnDropped` 618-636 only `PivotTo(info.Rest)` for models still in the holder (the tag is untouched), then `BaseSaveAPI.Snapshot` (631-633). ZombiesWin leftovers: `RestoreCarry(other, true)` 791 + `ReturnDropped` 795. CheckRaidEnd Survived: `ReturnDropped` 703. Day thieves: 695. |
| Owner left mid-carry | `PlayerRemoving` 1617-1622 → `EndRaid(raid, "Left")` → `RestoreCarry` | same, or destroyed | Destroyed when `raid.Player.Parent` is nil or the holder is gone (586-588). Otherwise it is put back into Placed with the tag (see H9). |
| Dawn | `OnPhase` 1606-1613 → `EndAll("Dawn")` 1372 → `EndRaid` | **same** | as above. Nothing at dawn builds a new placed cucumber. DayNightCycle's dawn reseed only touches field cucumbers. |

The `Owner` attribute is never touched by the zombies. `Rate` stays on the model while it is carried; `StampRate` rewrites it on the re-tag.

---

## 8. BaseSaveService cucumber records

- **Record shape**, written by `Collect` 106-118, for each `CollectionService:GetTagged("PlacedCucumber")` model that is `IsA("Model")`, has `Owner == uid`, is `IsDescendantOf(plot)` and has a PlotHitbox BasePart:

  ```lua
  {Zone = attr Zone, Type = attr TypeName, Golden = attr Golden == true, Material = attr Material, Mutations = attr Mutations,
   SizeTier = attr SizeTier, Name = attr CucumberName or model.Name,
   Pivot = Pack(anchor:ToObjectSpace(model:GetPivot())), Box = Pack(anchor:ToObjectSpace(hitbox.CFrame)), Size = PackV(hitbox.Size)}
  ```

  - `anchor` = the plot's top surface at the middle of its BACK edge (`AnchorOf` 74-77).
  - `Pack` is 12 CFrame components, `PackV` is 3 numbers.
  - **Every record is rebuilt from attributes, so any new field (`Id`, `PetBuffs`) must be added here.** Only `Kept` records (restores that failed this session) are copied through verbatim (119).
- **Real profile** (`_profile_Player_140977250_before-pets.json`): 2 cucumber records.
  - The keys that appear are `Golden, Type, Name, Zone, Size, Mutations ("" string), Pivot, Box`, plus `SizeTier` on the giant.
  - `Material` is absent when nil. There is no Id.
  - `Base.Version = 2`. Pets are `{Pet, Pos}` (4 of them). Eggs have no Id.
- **`Snapshot(player, quiet)` 133-141.** Needs `Active[player]` and not `Paused`, and the plot's Owner must still be the player. Then `data.Base = Collect(...)`, which is a **new Base table** (95); unknown Base fields are dropped. When not quiet it calls `RequestSave`.
- **Snapshot triggers.** Tag add/remove on PlacedCucumber / PlacedBuild / PlotPet / PlacedEgg (250-256, debounced 0.5 s, non-quiet). Build `PlotX / PlotZ / Yaw / Level` attribute changes (39, 245-249). A 30 s heartbeat (quiet, 273-280). `BaseSaveAPI.Snapshot` (293, non-quiet).
  - **Cucumber attribute changes do NOT trigger a snapshot.** CucumberMoveServer and ReturnDropped call `BaseSaveAPI.Snapshot` explicitly for that reason.
- **`Restore(player)` 162-242.** Order: wait for data, the plot and PlotLevel, then eggs (187-193), builds (194-203), cucumbers (204-229), pets (230-236).
  - The **V1 gate** (210-214) drops all cucumber records when `Base.Version < 2`.
  - Each cucumber record goes through `restorePlaced:Invoke(player, plot, rec, anchor*pivot, anchor*box, size)` inside a pcall. A failure → `Kept[player]`.
  - **`Active[player] = plot` is set only after everything (238).** It is the only "restore finished" flag, it is internal, and there is no signal. If nothing failed, a quiet `Snapshot` follows (241).
- **Leave: `PlayerRemoving` 261-271.** Clears Active / Paused / Queued / Kept, then `ClearPlaced` + `ClearBuilds`. **No final snapshot.** The profile keeps whatever the last snapshot wrote (PLAN issue 11).
- **`BaseSaveAPI.Reset` 294-311.** Paused, clear everything, `data.Base = {Version = 2, SavedAt, Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}}`, `RequestSave`.
- **`Resume` 312-316.**
- **`Reload` 318-332.** Paused, Active nil, clear all, wait 0.6 s, un-pause, `Restore` from the unchanged `Data.Base`.

---

## 9. Recommendations: CucumberId

**Attribute:** `CucumberId`, a string from `HttpService:GenerateGUID(false)` (the same generator CucumberAdventure uses for `JourneyId`). CucumberCarry has no HttpService local yet: add `local HttpService = game:GetService("HttpService")` to its Services block (64-69).

### 9.1 Create: `CucumberCarry.Place()`

Add it next to the other attributes, **before `AddTag` at 956**:

```lua
taken:SetAttribute("CucumberId", HttpService:GenerateGUID(false)) -- 2026-09-22: stable id for pet buffs / saves
```

- Always mint a fresh one. A field lift's clone can never carry a CucumberId: field holders are fresh `SpawnBreakable` models and `Drop` does not copy model attributes.
- The only path where a placed model comes back through `Place` is the dev `PickUp`, and 9.4 strips the id there.
- Minting also avoids any duplicate-id risk.
- `GenerateGUID` cannot throw. Still keep new code in Place free of anything that can error: everything after `Take()` (916) runs on a detached model (H4).

### 9.2 Restore: `CucumberCarry.RestorePlaced()`

Add it **before `AddTag` at 1038**:

```lua
local id = record.Id
model:SetAttribute("CucumberId", (type(id) == "string" and #id > 0 and #id <= 64) and id or HttpService:GenerateGUID(false))
```

- The buff attributes (9.6) must be stamped here as well, before 1038, so tag-added listeners (the IncomeService rate, the card badges, PetBuffService registration) see the full state in one step.
- `record` is already passed in, so BaseSaveService's `restorePlaced:Invoke` signature doesn't change.
- **The LEGACY-migrated branch (993-1006) keeps the same record, so it keeps the same Id.**

### 9.3 Save: `BaseSaveService.Collect` 110-115

Add `Id = model:GetAttribute("CucumberId")` and a `PetBuffs` array serialized from the model's buff attributes (skip expired entries).

- `Kept` records (119) keep their saved `Id` / `PetBuffs` untouched. Absolute expiry lets them lapse on their own.
- In the `Restore` loop (216-229), keep a per-restore `seen[Id]` set. On a duplicate, mint a new Id for the later record before invoking. This mirrors PLAN 8.1's pet rule.
- PetDataMigration should give Ids to legacy cucumber records before the restore (PLAN 8.2), so that a restore that partly fails does not leave records without an Id. If no Id is assigned, RestorePlaced mints one and the next snapshot persists it (the 30 s heartbeat snapshots even when something failed, since it includes Kept).

### 9.4 Preserve / strip

| Path | Action |
|---|---|
| `CucumberMoveServer.Move` (101-109) | **Nothing needed.** It is the same instance and nothing is re-tagged. Settlement isn't needed either: the rate and eligibility are unchanged. Optional: after the successful `PivotTo`, fire a "moved" notice for effects. Effects parented or adorned to the model / PlotHitbox follow it anyway. |
| ZombieRaidService `Grab` → `RestoreCarry` / `ReturnDropped` / `EndRaid` (dawn) | **Nothing needed for the id** (same instance, attributes untouched). Buffs are cleared at Grab (9.5). |
| `Escape` 770 / the destroy paths | Unregister only (9.5). |
| `PickUp` 1094-1111 (dev only) | Before `RemoveTag` at 1108: clear `CucumberId` and every buff attribute (and `BaseRate` if added). Settlement happens on the tag removal. |
| `Drop` / `DropAtFeet` / `DropForNight` / `TakeCarried` | Nothing: shoulder models never keep an id once PickUp strips it. |

### 9.5 Where pet buffs must be cleared, or only unregistered

| Trigger | Where | What |
|---|---|---|
| **Zombie capture** | `ZombieRaidService.Grab` 522, at the very top (before `carry` 531 / `RemoveTag` 533) | Call `PetBuffService.TryBlockTheft(model, entry.Model, now)`. If it returns true, `return false`: the ordinary Tick path then drops the target (1271), and the grapple path already restores `rest` (1048). This one guard covers the ordinary, grapple-final and digger captures. If it returns false, **clear all buffs** (settle first), then continue. The grapple also needs a pre-pull check at the entry of `StartGrapple` (997) (zombie researcher's area). |
| **Pickup** (dev hook) | `PickUp` before 1108 | clear buffs + CucumberId |
| **Destroy / cleanup**: `ClearPlaced` (leave 268, Reset 299, Reload 324), EggPlacement `ClearAllChildren` 312, `Escape` 770, `RestoreCarry` 587, zombie destroyed 1217-1222 | tag-removed signal + `Destroying` / ancestry | **Unregister runtime state only. Never write `Data.Base`.** BaseSaveService already stops snapshotting first (`Active[player] = nil` 263 / `Paused` 295 / 321-322), so the last saved `PetBuffs` survive leave and Reload, and Reset wipes them on purpose (307). |
| **Ownership change** | The model's `Owner` changes only in PickUp. A plot changing hands destroys Placed's children (EggPlacement 311-313, PlotService Release 168, AdminService bounce 94) | Also re-check `plot:GetAttribute("Owner") == model Owner` at every proc and at every settle. |
| **Unequipping the source pet** | none | PLAN 4.3: effects keep running. |

Classifying a removal by reading attributes inside the tag-removed handler is order-fragile: Grab removes the tag **before** setting StolenBy (533 → 534), and PickUp removes it **before** clearing Owner (1108 → 1109). With deferred signals the handler happens to see the final state, but don't depend on it. Put the explicit clear calls in `Grab` and `PickUp`, and treat every other removal as unregister-only.

### 9.6 Buff state representation (proposal; CONTRACTS.md pins the names)

- Keep the runtime truth for a placed cucumber **on the model as replicated attributes**, set only by PetBuffService (and by RestorePlaced from the record).
  - Example names: `BuffYieldUntil` / `BuffHasteUntil` / `BuffGuardUntil` (number, `workspace:GetServerTimeNow()` epoch, the same clock EggPlacement uses for `HatchAt` 220-221), `BuffYieldPet` / `BuffHastePet` / `BuffGuardPet` (source PetId string), `BuffGuardCharges` (int), plus `BaseRate` (IncomeService) with `Rate` = the effective rate.
- Why attributes:
  1. Moves, zombie drop / return and dawn keep them with no code.
  2. `Collect` serializes them into `PetBuffs` the same way it does every other field.
  3. PlacedCucumberCardClient already works off model attributes and rebuilds on the tag (265-267).
  4. A Reload rebuilds from `Data.Base` without PetBuffService touching the profile.
- Persistence: attribute changes don't snapshot on their own. After an apply / consume / clear, call `ServerStorage.BaseSaveAPI.Snapshot` with `task.defer(function() pcall(snapshot.Invoke, snapshot, player) end)`, as CucumberMoveServer does (107-109). **Never inside the synchronous `TryBlockTheft`.**

### 9.7 Registration and eligibility

- Register on `GetInstanceAddedSignal("PlacedCucumber")`: CucumberId and the buff attributes are already set at that point. Unregister on `GetInstanceRemovedSignal`.
- Eligibility predicate for a proc target (server):

  ```lua
  CollectionService:HasTag(m, "PlacedCucumber") and m:IsA("Model")
  and m:GetAttribute("Owner") == uid and plot:GetAttribute("Owner") == uid
  and m.Parent == plot:FindFirstChild("Placed")
  and m:GetAttribute("StolenBy") == nil
  and type(m:GetAttribute("CucumberId")) == "string"
  and BaseRestored(player)                                  -- see below
  and InsidePlot(plot, m:GetPivot().Position)               -- excludes carrier-dropped cucumbers lying in the lobby (H8)
  ```

- **Restore readiness needs a new, explicit signal.** BaseSaveService should publish one, for example `player:SetAttribute("BaseRestored", true)` next to `Active[player] = plot` at 238, cleared at the start of Reset (295), at the start of Reload (321) and on leave (263), or an equivalent `BaseSaveAPI.IsRestored(player)` bindable. RestorePlaced models get tagged one at a time *during* the restore, so "the tag exists" does not mean "the restore is complete".
- Optional: have ZombieRaidService set a `RaidDropped = true` attribute in RestoreCarry's `dropAt` branch (603-609) and clear it in Grab (532) and ReturnDropped (626). This replaces the bounds check with an explicit flag.

### 9.8 Effects placement

Build the buff badges, shield shell and so on **on the client** (PlacedCucumberCardClient / PetEffectsClient, adorned to `PlotHitbox`). Server-side instances under the model would cause trouble:

- They get welded and carried by zombies (Grab 535-546).
- Any BasePart with CanQuery on blocks every overlap test that includes `plot.Placed`: Place 911, Move 97, BuildService, EggPlacement, both client ghosts.
- They get cloned into the move ghost (BuildMenuClient 966-984 strips only some classes).
- They risk being mistaken for, or replacing, the `PlotHitbox` that `Collect` requires (108).

---

## 10. PLAN.md section 2 (and related sections) vs the live code

1. **"Pickup ... clears its pet buffs"** (4.3, 14 "Buff saves") and **"pickup clears effects"** (9, CucumberCarry row): there is **no gameplay pickup** of placed cucumbers. `PickUp` runs only from the Studio `CarryDev` hook (870, 1068, 1221-1224). The header says placed cucumbers show "NO prompt (user call 2026-09-05)" (46-47). They can't be sold either (BuildMenuClient 1078; BuildService.Sell needs `PlacedBuild`). Still implement the clear in PickUp for dev tests, but the gameplay removal paths are the zombie Grab / Escape plus the cleanup paths.
2. **"neither stolen nor actively being moved/carried"** (4.3): the server has **no moving state**. The move is a single atomic `PivotTo` (CucumberMoveServer 101) and the ghost is client-only. A "carried" (shoulder) cucumber is never a PlacedCucumber. Only `StolenBy` (plus the tag) needs checking. The "small explicit move-state hook" (9, conditional checks) is not needed for identity or eligibility.
3. **"Restore must be complete before eligibility"** (4.3): no readiness signal exists. `Active[player]` (BaseSave 238) is private (see 9.7).
4. **"under the owner's current plot"** (4.3): a cucumber dropped by a killed carrier is in `plot.Placed`, tagged, **earning**, but can physically lie in the lobby (RestoreCarry 603-610). Only the internal `raid.Dropped` table knows. Being "under the plot" in the hierarchy doesn't mean it is physically on the plot.
5. **"a new owner must never inherit ... effects"** (8.4) and **"PlotService ... cleanup"** (9): as well as BaseSaveService's leave `ClearPlaced`, **EggPlacement 311-313 destroys every child of `plot.Placed` (cucumbers included) whenever the plot's Owner becomes nil**. PLAN issue 11 names only DataService and BaseSaveService. The AdminService reset bounces the Owner (93-98), so the reset also passes through this path.
6. **Issue 11 / 8.4 ("preserve PetSchemaVersion and any unknown Base fields")**: `Collect` builds a brand-new Base table (95) and rebuilds every cucumber record from attributes (110-115). Unknown Base fields **and** unknown per-cucumber fields (a future `Id` / `PetBuffs`) are dropped unless `Collect` writes them explicitly. `Reset` (307) also builds a bare Base.
7. **8.1 cucumber schema**: the live `Mutations` in a cucumber record is a **comma string**, not an array (the model attribute is copied straight in). `Material` / `SizeTier` are absent when nil. Don't normalize these to the pet schema's array format; `CucumberValues`, `ZombieCatalog.ThreatOf` and `SpawnCarried` all expect the string.
8. **7 "Recompute when material/mutations/size/zone/type/ownership/tag ... changes"**: on a placed cucumber, material / mutations / size / zone / type are written once (Place / RestorePlaced) and never change. LeaderstatsService stamps `Rate` only on a tag add (157-159) and in the `EarningFor` fallback. The real triggers are tag add / remove, a buff change and a plot Owner change (164-171).
9. **4.4 / issue 8 grapple restore**: the rest-pose restore on a failed final grab already exists (`if not Grab(...) then target:PivotTo(rest) end`, 1048). A `TryBlockTheft` inside `Grab` inherits it for free. The digger has no capture of its own: it surfaces and the ordinary Tick grab (1270-1271) takes the cucumber.
10. **Issue 6 / 7 "IncomeOf reads Data.CashPerSec"**: confirmed (ZombieRaidService 268-272). `ZombieCatalog.ThreatOf` reads the cucumber's Zone / Mutations / Material / Golden / SizeTier attributes, **not `Rate`** (ZombieCatalog 154, 180-183). So an effective `Rate` on the model does not leak into threat. Only `CashPerSec` does.
11. **8.4 restore order** "cucumbers/builds/eggs": live is eggs → builds → cucumbers → pets (187-236). Pets come last, which suits "attach the selected pets" after the cucumbers.

---

## 11. Hazards (things implementers could get wrong)

- **H1. Don't use `JourneyId` as the identity.** It is re-rolled by `CucumberAdventure.Decorate` on every `RestorePlaced` (the holder is spawned without `JourneyId`), and it flows through field drops.
- **H2. Set CucumberId and buff attributes BEFORE `AddTag`** (Place 956, RestorePlaced 1038). Tag-added listeners (the IncomeService rate, cards, registries, BaseSave QueueOwner) must see the final state. (The added signal fires on the parenting at 957 / 1039, but keep the ordering anyway.)
- **H3. `Collect` rebuilds every cucumber record.** Forgetting to add `Id` / `PetBuffs` there silently erases them on the next snapshot, usually within 0.5 s of any tag change.
- **H4. In `Place()`, anything after `Take()` (916) runs on a detached model.** An error there is caught by the remote's pcall (1175), but the carry is already cleared and the cucumber is lost. Keep new code there error-free: no requires or yields, and pcall anything non-trivial.
- **H5. `RestorePlaced`'s `record` is the live profile table.** Mutating it (for example `record.Id = ...`) is a profile write, and it is also shared with `Kept`. Do Id repair in the migration or the BaseSave restore loop on purpose, not as a side effect.
- **H6. Destroy / cleanup paths must never write `Data.Base` or mark buffs cleared in the profile.** Leave (263-270) and Reload (321-327) stop snapshots *before* clearing, so the last snapshot keeps the buffs. A PetBuffService that edits `data.Base.Cucumbers[i].PetBuffs` on tag removal would erase buffs on every rejoin or Reload.
- **H7. Cucumber attribute changes don't trigger a save.** Call `BaseSaveAPI.Snapshot` deferred after apply / consume / clear. Snapshot requires `Active[player]` and fails quietly before the restore finishes. The heartbeat snapshot is quiet (it rides the autosave).
- **H8. Carrier-dropped cucumbers** lie in the lobby while tagged, earning and parented to `plot.Placed`, with no attribute saying so.
  - The owner can move one back in daytime (Move checks only the parent and the tag).
  - A later `ReturnDropped` then `PivotTo`s it to its old home spot and ignores overlaps.
  - A snapshot taken while it lies in the lobby saves the lobby pivot.
  - Decide whether these are proc-eligible; recommended: no.
- **H9. The owner leaves mid-carry.** `EndRaid("Left")` → `RestoreCarry` puts the model back into Placed with the tag whenever `raid.Player.Parent` is still set. PlayerRemoving handlers across PlotService, EggPlacement (via the Owner change), BaseSaveService and ZombieRaidService run in no guaranteed order, so a "ghost" cucumber with the old Owner could linger in a freed plot. Registries must key on model Owner **and** plot Owner, and **never assume the plot's Placed folder only holds the current owner's things**. Test this.
- **H10. A stolen cucumber is missing from every snapshot during the carry** (tag removed, parented into the zombie). If the player leaves, or the server stops, before RestoreCarry and a new snapshot, the save loses it. Buff state is cleared at Grab, so nothing extra is lost. Don't try to "remember" buffs across a grab.
- **H11. Tag-removed classification is order-fragile** (Grab: tag 533 before StolenBy 534; PickUp: tag 1108 before Owner nil 1109). Signals are Deferred here (CucumberCarry 472-475, BaseSave 328). Use explicit calls in Grab / PickUp.
- **H12. `TryBlockTheft` inside `Grab` must stay synchronous.** No BindableFunction snapshot, no `task.wait`, no DataService save. Defer the side effects (the snapshot, the effect event).
- **H13. LeaderstatsService `StampRate` on every tag add** (157-159) will overwrite an effective `Rate` with the base rate after a RestoreCarry re-tag or a restore. IncomeService must own `Rate` / `BaseRate` and replace this stamping. Otherwise buffs vanish from the card after a zombie drop, or come back doubled.
- **H14. Server-side buff effects under the model** get welded and carried by zombies, block the `plot.Placed` overlap tests if CanQuery is on, get cloned into the move ghost, and could shadow the `PlotHitbox` (see 9.8). Keep effects client-side and never name or destroy `PlotHitbox`.
- **H15. The move is client-ghosted.** The original keeps earning and stays targetable during the ghost. There's no server "moving" flag, so don't invent one that could get stuck.
- **H16. `RestorePlaced` goes through `SpawnCarried{Force = true}`.** For one frame a real `Breakable` field holder exists (population counted, tag-added signals fire, CucumberCarry defers `AttachCollectPrompt`). Pet code must only ever look at `PlacedCucumber`, never at `Breakable`.
- **H17. Duplicate Ids** can come from corrupted or edited saves. De-duplicate per restore (keep the first) and never trust a client-sent id; remotes should pass the model Instance, as `requestCucumberMove` does.
- **H18. Several backup copies of CucumberCarry exist in ServerStorage** (`__CollectAnimBackup_2026_09_06`, `__CarryAndEggLabelsBackup`, `__CarryConvenienceBackup`, `__BaseSaveBackup_2026_09_12`, `ShopGroupGiftBackup_20260915`, `__LiftRebuildBackup_2026_09_16`; see `_structure.txt`). Patch only `ServerScriptService.CucumberCarry`.
- **H19. `CucumberIncome` fires to ALL clients** (LeaderstatsService 112) with model Instances. Clients skip models that haven't streamed in. Keep the `(models, amounts)` shape.
- **H20. `Mutations` on cucumbers is a comma string.** Don't convert it while adding `PetBuffs` to the record.
