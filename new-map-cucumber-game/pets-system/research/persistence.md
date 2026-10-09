# Research: persistence + lifecycle (live snapshot 2026-09-22)

Source: `live-2026-09-22/` local mirrors (read-only). Line numbers are the snapshot's. Files read in full:
`ServerStorage.DataService.lua`, `ServerStorage.DataService.ProfileStore.lua`, `ServerScriptService.BaseSaveService.server.lua`,
`ServerScriptService.AdminService.server.lua`, `ServerScriptService.PlotService.server.lua`,
`ServerScriptService.PlotUpgradeService.server.lua`, `ServerScriptService.SpawnAtBaseServer.server.lua`,
`ServerScriptService.PetHatchService.server.lua`, `ServerScriptService.EggPlacement.server.lua`,
`ServerScriptService.LeaderstatsService.server.lua`, `ServerScriptService.CucumberMoveServer.server.lua`, `ServerScriptService.DataLoader.server.lua`;
the relevant ranges of `CucumberCarry`, `BuildService`, `ZombieRaidService`, `GymService`, `PlotBadges`, `PortalService`, `DesertHuntService`;
every `PlayerRemoving` / `BindToClose` / `GetAttributeChangedSignal("Owner")` hit (grep); `_profile_Player_140977250_before-pets.json`, `_structure.txt`, `_manifest.json`.
All scripts named here are enabled in `_manifest.json` (DataService + ProfileStore = ModuleScripts, the rest = Scripts).

---

## 1. ServerStorage.DataService (ModuleScript)

### 1.1 Config (lines 49-55)
| const | value | note |
|---|---|---|
| `STORE_NAME` (49) | `"PlayerData_v1"` | DataStore name |
| `PROFILE_KEY` (50) | `"Player_%d"` | key = `Player_<UserId>` |
| `USE_MOCK_IN_STUDIO` (51) | `false` | **Studio playtests use the LIVE store** (line 75 only mocks when true) |
| `VALUES_FOLDER` (52) | `"Data"` | folder under the Player |
| `PLAYTIME_TICK` (53) | `1` | s |
| `SAVE_DEBOUNCE` (54) | `5` | s, RequestSave coalescing window |
| `AUTO_SAVE_PERIOD` (55) | `60` | pushed into ProfileStore by `ProfileStore.SetConstant("AUTO_SAVE_PERIOD", AUTO_SAVE_PERIOD)` (73) |

### 1.2 TEMPLATE (lines 57-68, verbatim keys)
```lua
local TEMPLATE = {
	Cash = 0,
	Playtime = 0,
	Strength = 0,
	GroupGiftClaimed = false,
	CucumberCollection = {Seen = {}, Families = {}, BestRequired = 0, BestSize = 0, TotalSecured = 0},
	Headbands = {Owned = {}, Equipped = ""},
	PlotLevel = 0,
	Upgrades = {BenchPress = 1},
	Base = {Version = 1, Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}}, -- line 66
	PortalCooldowns = {},
}
local VALUE_ORDER = {"Cash", "Playtime", "Strength"}   -- 69
local REMOVED_KEYS = {"Cukes"}                          -- 70
```
- `DataService.Template = TEMPLATE` (78) exposes the **live** table (mutating it changes Reconcile + ResetProfile). `DataService.StoreName = STORE_NAME` (79).
- `Base.Version = 1` in the template vs `BaseSaveService VERSION = 2` (BaseSave line 34) - confirmed mismatch (PLAN issue 9).
- The header (lines 7-9) still lists only "Cash, Playtime, Strength, PlotLevel, Upgrades" - stale.
- `REMOVED_KEYS` does NOT contain `"Coins"`; the real profile still carries a legacy `Coins` number (section 10).

### 1.3 Module state (81-87)
`Profiles[player] = profile`, `Values[player] = {Cash=NumberValue,...}`, `PlaytimeBase[player] = {At, Value}`, `LastSave[player] = os.clock()`, `SavePending[player] = true`, `LoadedCallbacks = {}`, `Started`.

### 1.4 Public API (exact)
| function | line | behaviour |
|---|---|---|
| `DataService.GetProfile(player)` | 90 | `Profiles[player]` (ProfileStore Profile) or nil. Used by GroupGiftServer (21, 32, with `profile:IsActive()`). |
| `DataService.GetData(player)` | 94 | `profile.Data` or nil. **nil as soon as `Forget(player)` ran** (see 1.7). |
| `DataService.IsLoaded(player)` | 99 | `Profiles[player] ~= nil` |
| `DataService.WaitForData(player, timeout)` | 103 | polls every 0.1 s until `Profiles[player]` set, player left, or `timeout` (default **30 s**); returns GetData (may be nil). |
| `DataService.RequestSave(player)` | 120 | coalesced save: if ≥ `SAVE_DEBOUNCE` since `LastSave[player]` → `SaveNow` (→ `profile:Save()`, 111-117, only if `profile:IsActive()`); else one `task.delay(SAVE_DEBOUNCE - elapsed, ...)` guarded by `SavePending`. No-op if already pending or no profile. `LastSave` is primed at load (243), so a RequestSave in the first 5 s after load is delayed. |
| `DataService.Get(player, key)` | 134 | `data and data[key] or nil` (a `false` value reads as nil). |
| `DataService.Set(player, key, value, quiet)` | 141 | `data[key] = value`; syncs the value object if one exists (`Values[player][key]`); `if key ~= "Playtime" and not quiet then RequestSave`. Returns false if no data. |
| `DataService.Increment(player, key, delta, quiet)` | 152 | `Set(player, key, current + (delta or 1), quiet)`; **returns false if the key is nil** in the profile. |
| `DataService.ResetProfile(player)` | 166 | clears every key of `profile.Data` (170), deep-copies TEMPLATE back (171) → `Base.Version = 1`, **new nested table identities**; `PlaytimeBase` restarts at 0; value objects set to `data[key] or 0`; `RequestSave`. The `profile.Data` table object itself is kept. |
| `DataService.OnProfileLoaded(callback)` | 181 | appends to `LoadedCallbacks`, and **immediately `task.spawn(callback, player, profile)` for every already-loaded profile** (183-185). Registration order ≠ run order guarantee. |
| `DataService.Start()` | 257 | idempotent; connects PlayerAdded/PlayerRemoving, spawns OnPlayerAdded for present players, starts the 1 s Playtime loop (266-275: `Set(player,"Playtime", base.Value + floor(os.clock()-base.At))`, which never RequestSaves). Called once by `ServerScriptService.DataLoader` (line 4). |

There is **no** close/leave/reset signal, no generation counter, and no "before close" callback in DataService today.

### 1.5 Load sequence - `OnPlayerAdded` (219-249)
1. 220-222 `Store:StartSessionAsync(PROFILE_KEY:format(player.UserId), {Cancel = function() return player.Parent ~= Players end})` (yields; see 2.2).
2. 223-226 nil → `player:Kick("Your data could not be loaded. Please rejoin.")`.
3. 227 `profile:AddUserId(player.UserId)`.
4. 228 **`profile:Reconcile()`**.
5. 229-231 drop `REMOVED_KEYS`.
6. 232-237 `profile.OnSessionEnd:Connect(function() Forget(player); if player.Parent == Players then player:Kick("Your data was opened on another server. Please rejoin.") end end)`.
7. 238-241 player left during load → `profile:EndSession()`; return.
8. **242 `Profiles[player] = profile`** ← the profile becomes visible to GetData / IsLoaded / WaitForData pollers here.
9. 243 `LastSave`, 244 `PlaytimeBase`, 245 `BuildValues(player, profile.Data)` (player.Data folder parented at the end, 208).
10. 246-248 `for _, callback in ipairs(LoadedCallbacks) do task.spawn(callback, player, profile) end`.

No yield exists between step 4 and step 10, so the whole block is atomic w.r.t. other threads.
**Migration insertion point:** after line 231 (Reconcile + REMOVED_KEYS) and before line 242 (`Profiles[player] = profile`) - i.e. before exposure, not merely before callbacks. It must be `pcall`-wrapped: an error thrown between StartSessionAsync (220) and line 242 leaves an ACTIVE session that `OnPlayerRemoving` will never end (it only ends `Profiles[player]`), so the profile would stay locked + autosaving in this server until shutdown.

### 1.6 Value objects under `player.Data` (BuildValues 188-209)
- Folder `Data` with NumberValues `Cash`, `Playtime`, `Strength` (VALUE_ORDER). Each `.Changed` (199-205): if `live[key] ~= newValue` then write back into the profile and (except Playtime) `RequestSave`. Server writes to `player.Data.Cash.Value` therefore save like `Set`.
- `player.Data.CashPerSec` is a NumberValue created by **LeaderstatsService** (129-134): derived, **not a profile key, never saved**, no DataService hook. (PLAN's "Data.CashPerSec" = this instance.) ZombieRaidService `IncomeOf` (268-272) reads it.
- Keep writing Cash/Strength through `Set/Increment` (value object synced) - a direct `data.Cash = x` leaves the value object stale and a later deferred `.Changed` can write the old value back.

### 1.7 Leave - `OnPlayerRemoving` (251-255)
```lua
local function OnPlayerRemoving(player)
	local profile = Profiles[player]
	if profile then profile:EndSession() end -- final save
	Forget(player)
end
```
`profile:EndSession()` → `task.spawn(SaveProfileAsync, self, true, nil, "Manual")` which, **synchronously before its first yield**, fires `OnSave`, `OnLastSave("Manual")`, removes the profile from the autosave list and fires `OnSessionEnd` → DataService's handler (232) runs `Forget(player)` (and `player:Kick(...)` if `player.Parent == Players` is still true during PlayerRemoving - harmless but real). So **immediately after line 253 returns, `GetData(player)` is nil.** The DataStore write (UpdateAsync) happens later on the spawned thread.

### 1.8 Save paths summary
- Non-quiet `Set/Increment`, value-object writes, `RequestSave` → coalesced `profile:Save()` (≤1 write per 5 s per player).
- `quiet` writes (e.g. income, `LeaderstatsService.PayIncome` 109: `DataService.Increment(player, "Cash", total, true)`) ride the next save.
- ProfileStore autosave ≈ every 60 s per profile (2.6), final save on EndSession / shutdown.
- `RequestSave` callers: BaseSaveService 139 (non-quiet snapshot), 308 (Reset); GroupGiftServer 38; HeadbandService 220/242/254/389/522/536; PlotUpgradeService 287/333; CucumberAdventure 107/163; GymService 190/302; PortalService 102; DataService internal 148/177/203.
- `OnProfileLoaded` subscribers: BaseSaveService 259, BuildService 674, GroupGiftServer 56, HeadbandService 387, LeaderstatsService 153, CucumberAdventure 204, GymService 264. `WaitForData` users: BaseSaveService 163 (60 s), PlotUpgradeService 258 (default 30 s), CucumberAdventure 127 (20 s), PortalService 108 (60 s).

---

## 2. ServerStorage.DataService.ProfileStore (loleris ProfileStore, as shipped)

### 2.1 Constants (170-181)
`AUTO_SAVE_PERIOD = 300` (overridden to **60** by DataService), `LOAD_REPEAT_PERIOD = 10`, `FIRST_LOAD_REPEAT = 5`, `SESSION_STEAL = 40`, `ASSUME_DEAD = 630`, `START_SESSION_TIMEOUT = 120`, `CRITICAL_STATE_ERROR_COUNT = 5`, `CRITICAL_STATE_ERROR_EXPIRE = 120`, `CRITICAL_STATE_EXPIRE = 120`, `MAX_MESSAGE_QUEUE = 1000`.

### 2.2 `ProfileStore:StartSessionAsync(profile_key, params)` (1364-1631)
- params: `Steal = true` (ignore an existing lock), `Cancel = fn() -> boolean` (stop trying, return nil). DataService passes only `Cancel`.
- Returns nil immediately if `ProfileStore.IsClosing` (1382). Errors if the key is already active in this server (1390-1392).
- Session conflict: requests `ForceLoadSession`, publishes a MessagingService "end session" to the owner, retries after 5 s then every 10 s, steals after `SESSION_STEAL` (40 s); a lock older than `ASSUME_DEAD` (630 s) is taken at once. A rejoin onto a new server while the old server still holds the lock can take ~5-40+ s.
- DataStore errors: exponential backoff 1→20 s; the 120 s `START_SESSION_TIMEOUT` only applies when **no** `Cancel` was given (1612-1614) - so for DataService it retries until the player leaves.
- If the server began closing / the request was cancelled at the moment the profile loaded, it is released immediately and nil is returned (1552-1556).

### 2.3 Profile methods (as implemented)
| method | line | behaviour |
|---|---|---|
| `Profile:IsActive()` | 1082 | `ActiveSessionCheck[self.session_token] == self` |
| `Profile:Reconcile()` | 1086 → `ReconcileTable` 408-422 | fills **missing string keys** from the template (deep copy), recursing into keys where both sides are tables. Never removes, never overwrites existing values/types, never touches array elements. |
| `Profile:EndSession()` | 1090 | if active → `task.spawn(SaveProfileAsync, self, true, nil, "Manual")`; returns immediately. |
| `Profile:Save()` | 1172 | warns + returns if inactive; moves the profile behind the autosave index (delays its autosave); `task.spawn(SaveProfileAsync, self)`. There is **no `RequestSave` in ProfileStore** (that is DataService's coalescer). |
| `Profile:AddUserId / RemoveUserId` | 1096 / 1113 | GDPR ids. |
| `Profile:MessageHandler(fn)` | 1138 | global-update messages (unused here). |
| `Profile:SetAsync()` | 1128 | view-mode only. |
| Signals | 1058-1061 | `OnAfterSave(last_saved_data)`, `OnSave()`, `OnLastSave(reason)` with reason `"Manual"` / `"Shutdown"` / `"External"`, `OnSessionEnd()`. |

Custom Signal (188-308): `Connect` inserts at the list head (262-270) → **listeners fire newest-first**; `Fire` does `task.spawn(runner, listener, ...)` per listener (281-292) - each listener runs synchronously until its first yield; a yielding listener does not block the next listener or the caller.

### 2.4 `SaveProfileAsync(profile, is_ending_session, is_overwriting, last_save_reason)` (709-938) - order
1. 715 `profile.OnSave:Fire()`
2. 716-718 if ending: `profile.OnLastSave:Fire(last_save_reason or "Manual")`
3. 720-726 if ending (not overwrite): disconnect MessagingService sub, `RemoveProfileFromAutoSave(profile)` (profile becomes **inactive**), `profile.OnSessionEnd:Fire()` (→ DataService `Forget`)
4. 735-934 UpdateAsync loop; the transform (747-812) does `latest_data.Data = profile.Data` (791) **at transform time** (after the network round trip - the table is captured by reference, so writes made during that yield window may or may not be included: never rely on it); clears `ActiveSession` when ending (799-801). Ending saves repeat until success (backoff up to 20 s, 8 s for "Shutdown", 930).
5. After a successful non-final save that finds the session no longer owned → `OnSessionEnd` (912-921). A pending ForceLoad from another server → `SaveProfileAsync(profile, true, false, "External")` (843-848).
6. 924 `OnAfterSave`.

### 2.5 Autosave (Heartbeat, 2115-2153)
Round-robin over `AutoSaveList`: one profile every `AUTO_SAVE_PERIOD / #profiles` seconds → each profile ≈ every 60 s; profiles loaded less than `AUTO_SAVE_PERIOD / 2` (30 s) ago are skipped. `task.spawn(SaveProfileAsync, profile)` (not ending).

### 2.6 DataStore access + shutdown (2070-2111, 2189-2241)
- Live server: `DataStoreState = "Access"` set synchronously at require (2108), so the `task.spawn` at 2191 binds `game:BindToClose` **during `require(ProfileStore)`**, i.e. before DataService's own code (DataService line 46) returns.
- Studio: a probe `DataStoreService:GetDataStore("____PS"):SetAsync("____PS", os.time())` (2080) yields first; BindToClose is bound only after it resolves.
- **Access mode BindToClose (2208-2239):** `ProfileStore.IsClosing = true`; for every active profile `task.spawn(function() SaveProfileAsync(profile, true, nil, "Shutdown") ... end)`; then waits until all save/load jobs are done. This path **does not go through DataService.OnPlayerRemoving** - it fires `OnSave` → `OnLastSave("Shutdown")` → `OnSessionEnd` (DataService `Forget` + kick if still parented) → UpdateAsync, per profile.
- **Mock / NoAccess mode BindToClose (2199-2202):** only `IsClosing = true; task.wait()` - no final save, no OnLastSave, no OnSessionEnd.
- `ProfileStore.IsClosing` (module field) is readable by DataService to refuse new actions during shutdown.

### 2.7 Precisely what happens
- **Player leave (normal):** Roblox fires PlayerRemoving → (unspecified handler order, see §8) DataService `OnPlayerRemoving` → `profile:EndSession()` → spawned SaveProfileAsync runs synchronously through OnSave, OnLastSave("Manual"), autosave removal, OnSessionEnd (`Forget`, possible Kick) and yields in UpdateAsync; `Forget(player)` again (254). The DataStore write completes asynchronously with retries; the server stays alive for it only if a BindToClose is waiting (ProfileStore's waits for `ActiveProfileSaveJobs`).
- **Game close (live / Studio with API access):** ProfileStore's BindToClose ends every still-active profile with reason "Shutdown" (same synchronous pre-yield sequence), waits for all jobs (engine cap 30 s). Whether PlayerRemoving fires before/after/never for each player is not controlled by this code; if DataService's handler runs later, `Profiles[player]` is already nil (Forget) → no-op.
- **External takeover:** another server's ForceLoad makes this server run `SaveProfileAsync(..., "External")` → OnLastSave("External") → OnSessionEnd → DataService forgets + kicks the player.

---

## 3. ServerScriptService.BaseSaveService (Script)

### 3.1 Config (32-39)
`PLOTS = workspace.Map.Lobby.Plots`; tags `TAG_CUCUMBER, TAG_BUILD, TAG_PET, TAG_EGG = "PlacedCucumber", "PlacedBuild", "PlotPet", "PlacedEgg"` (33); `VERSION = 2` (34); `SNAPSHOT_DEBOUNCE = 0.5` (35); `HEARTBEAT = 30` (36); `PLOT_TIMEOUT = 20` (37); `LEVEL_TIMEOUT = 10` (38); `MOVE_ATTRIBUTES = {PlotX, PlotZ, Yaw, Level}` (39).

Bindables resolved at startup by `Bindable(folderName, name)` (42-47: `WaitForChild(folder, 120)` then `WaitForChild(name, 120)`, warns "that kind will not save" if missing): `CucumberCarryAPI.RestorePlaced/ClearPlaced`, `BuildServiceAPI.RestoreBuild/ClearBuilds`, `PetHatchAPI.SpawnPet/ClearPets`, `EggPlacementAPI.RestoreEgg/ClearEggs` (48-55). If one is renamed/moved the kind silently stops restoring **but snapshots still rebuild that array from the world** → e.g. a missing `PetHatchAPI.SpawnPet` wipes saved pets at the first snapshot.

State: `Active[player] = plot` (snapshots on only after restore), `Paused[player]`, `Queued[player]`, `Kept[player]` = failed cucumber records (57-63).

### 3.2 Coordinates (73-89)
`AnchorOf(plot) = plot.CFrame * CFrame.new(0, plot.Size.Y * 0.5, BuildCatalog.BackZ(plot))` - top surface, middle of the BACK edge (never moves on plot upgrades). `Pack(cf) = {cf:GetComponents()}` (12 numbers), `Unpack` validates 12 numbers; `PackV(v) = {X,Y,Z}`, `UnpackV` validates 3 numbers.

### 3.3 `Collect(player, plot)` → Data.Base (92-131)
Line 95: `local base = {Version = VERSION, SavedAt = os.time(), Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}}` - **a brand-new table with exactly these six keys**; any other Base field is dropped on every snapshot.
- **Eggs** (96-105): tagged `PlacedEgg`, `IsA("Model")`, `Owner == uid`, `IsDescendantOf(plot)`, has `EggName` → `{EggName, Kg, Scale, Material, Mutations, DisplayName, HatchSeconds, PlacedAt, HatchAt, Pivot = Pack(anchor:ToObjectSpace(egg:GetPivot()))}` (attributes copied raw; `Material` nil for normal). An egg with `Hatching = true` is still collected until destroyed.
- **Cucumbers** (106-118): tagged `PlacedCucumber`, Model, Owner, descendant, with a `PlotHitbox` BasePart → `{Zone, Type = TypeName, Golden (bool), Material, Mutations, SizeTier, Name = CucumberName or model.Name, Pivot, Box = Pack(anchor:ToObjectSpace(box.CFrame)), Size = PackV(box.Size)}`. Then line 119 appends every `Kept[player]` record.
- **Builds** (120-124): tagged `PlacedBuild`, Model, Owner, descendant, has `BuildKey` → `{Key, Level = tonumber(Level) or 1, Pivot}`.
- **Pets** (125-129) - current collection from the world:
```lua
for _, pet in ipairs(CollectionService:GetTagged(TAG_PET)) do
	if pet:IsA("Model") and pet:GetAttribute("Owner") == uid and pet:IsDescendantOf(plot) and pet:GetAttribute("PetName") then
		table.insert(base.Pets, {Pet = pet:GetAttribute("PetName"), Pos = PackV(anchor:PointToObjectSpace(pet:GetPivot().Position))})
	end
end
```
  The server pivot of a pet **never moves** after `SpawnPet` (PetRoamClient `PivotTo`s on the client only, line 137, no remote), so `Pos` is always the spawn spot (the egg's position). The real profile confirms it (integer X/Z, section 10). The header's "a HEARTBEAT (pets wander)" is ineffective.

### 3.4 `Snapshot(player, quiet)` (133-141)
Refuses (returns false, writes nothing) when: `not Active[player]`, `Paused[player]`, `not plot.Parent`, `plot:GetAttribute("Owner") ~= player.UserId`, or no data. Otherwise `data.Base = Collect(player, plot)` (**replaces the table** - stale references to the old `data.Base` / `data.Base.Pets` afterwards) and `RequestSave` unless quiet. Non-yielding.

### 3.5 Snapshot triggers
- `Queue(player)` (143-150): if Active and not Paused and not Queued → `task.delay(0.5, ...)` → `Snapshot(player, false)` (non-quiet → RequestSave).
- `QueueOwner(inst)` (154-159): owner from the instance's `Owner` attribute; if unreadable (pick-up clears Owner before the tag goes) → Queue every Active player.
- Tag signals (250-256): `GetInstanceAddedSignal` / `GetInstanceRemovedSignal` for all four tags → QueueOwner; `TAG_BUILD` adds also run `WatchBuild` (245-249: `AttributeChanged` on `PlotX/PlotZ/Yaw/Level` → QueueOwner); existing builds watched at 257.
- Heartbeat loop (273-280): every 30 s, `Snapshot(player, true)` (quiet - rides the next save) for every Active, non-Paused player.
- Explicit `BaseSaveAPI.Snapshot` from CucumberMoveServer (107-109, `task.defer`) and ZombieRaidService `ReturnDropped` (631-633, only if `raid.Player.Parent`).
- Nothing snapshots at **leave**.

### 3.6 `Restore(player)` (162-242) - order and waits
Spawned from `DataService.OnProfileLoaded(function(player) task.spawn(Restore, player) end)` (259).
1. 163-164 `DataService.WaitForData(player, 60)`; return if none / left.
2. 165-175 poll `PlotOf(player)` (plot whose `Owner == UserId`) every 0.25 s up to `PLOT_TIMEOUT` 20 s; no plot → warn "got no plot; nothing restored", return (Active never set → the save is never overwritten this session).
3. 176-178 `wantLevel = tonumber(data.PlotLevel) or 0`; poll `plot:GetAttribute("PlotLevel") ~= wantLevel` every 0.1 s up to `LEVEL_TIMEOUT` 10 s (continues anyway on timeout).
4. 179 `task.wait(0.3)` (grass grid rebuild). 180 abort if left or Owner changed (Active never set).
5. **Eggs first** (187-193): `restoreEgg:Invoke(player, plot, rec, anchor * pivot)` for records with `rec.EggName` and a valid Pivot.
6. **Builds** (194-203): copied, sorted by `Level` ascending (ground floor first), `restoreBuild:Invoke(player, plot, rec.Key, anchor * pivot, tonumber(rec.Level) or 1)`.
7. **Version-1 cucumber migration** (204-214), exact code:
```lua
		if (tonumber(base.Version) or 0) < 2 and type(base.Cucumbers) == "table" and #base.Cucumbers > 0 then
			print(("[BaseSave] %s: dropping %d cucumber(s) saved under base version %s - the cucumber set was replaced")
				:format(player.Name, #base.Cucumbers, tostring(base.Version)))
			base.Cucumbers = {}
		end
```
   (`base` is the live `data.Base`, so the wipe is in memory at once; `Version` itself is only bumped to 2 by the next snapshot.) **Any code that writes a Base table without `Version = 2` (nil → 0) arms this wipe for the next join.**
8. 215 `Kept[player] = nil`; **Cucumbers** (216-229): `restorePlaced:Invoke(player, plot, rec, anchor * pivot, anchor * box, size)`; on failure the record is appended to `Kept[player]` (failed-restore preservation - cucumbers only).
9. **Pets** (230-236): `spawnPet:Invoke(player, plot, rec.Pet, anchor:PointToWorldSpace(pos))` for records with `rec.Pet` and a valid 3-number `Pos`. Failure → `failed += 1` + warn, **not kept**.
10. 238 `Active[player] = plot`; 239 summary print (says "FAILED (kept in the save)"); 241 `if failed == 0 then Snapshot(player, true) end`.

Consequences:
- Failed eggs / builds / pets are only "kept" until the next snapshot (next tag event, or ≤30 s heartbeat) - then `Collect` rebuilds the arrays from the world and they are gone (PLAN issue 4 is true for pets **and** eggs and builds).
- Records failing the preconditions (`rec.Pet and pos`, `rec.EggName and pivot`, `rec.Key and pivot`, `rec.Type and pivot and box and size`) are neither restored, nor counted failed, nor kept → silently dropped by the next snapshot. A reserve pet record without `Pos` would vanish.
- Before step 10 every tag event is ignored (Queue requires Active). A restored ready egg can be hatched (PetHatchService CheckEgg) during the restore window: the egg is destroyed, the pet is only `Pending` → the post-restore snapshot (241) saves neither.

### 3.7 Leave handler (261-271)
```lua
Players.PlayerRemoving:Connect(function(player)
	local plot = Active[player]
	Active[player] = nil
	Paused[player] = nil
	Queued[player] = nil
	Kept[player] = nil
	if plot and plot.Parent then
		if clearPlaced then pcall(clearPlaced.Invoke, clearPlaced, plot) end
		if clearBuilds then pcall(clearBuilds.Invoke, clearBuilds, plot) end
	end
end)
```
No final snapshot; a debounced snapshot pending at that moment is discarded (its delayed callback finds `Active[player] == nil`). Pets/eggs are left to the Owner-attribute handlers (§5, §6).

### 3.8 `ServerStorage.BaseSaveAPI` (283-333, BindableFunctions)
| bindable | line | behaviour | callers |
|---|---|---|---|
| `Snapshot(player)` | 293 | `Snapshot(player, false)` → bool | CucumberMoveServer 107-109 (deferred); ZombieRaidService `ReturnDropped` 631-633 |
| `Reset(player)` | 294-311 | `Paused = true`; plot = `Active[player] or PlotOf(player)`; ClearPlaced + ClearBuilds + ClearPets + ClearEggs (counts summed except pets); `Kept = nil`; `data.Base = {Version = VERSION, SavedAt = os.time(), Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}}`; RequestSave; returns `true, cleared`. Leaves Paused. | AdminService 81/85 |
| `Resume(player)` | 312-316 | `Paused = nil`; `Active[player] = Active[player] or PlotOf(player)`; returns bool. No immediate snapshot. | AdminService 82/102 |
| `Reload(player)` | 318-332 | needs a plot; Paused, `Active = nil`, `Queued = nil`; clears all four kinds; `task.wait(0.6)` (deferred tag-removed events must find nothing to snapshot); `Paused = nil`; `Restore(player)` (yields up to ~90 s); returns `Active[player] ~= nil`. `Kept` is not cleared first (Restore resets it). | **no live caller** (persistence test hook) |

---

## 4. PetHatchService touch points (persistence only)
- `REVEAL_FALLBACK = 80` (48); `Pending[player] = {Token, Plot, Pet, Spot, EggName}` (74, 294).
- `SpawnPet(player, plot, petName, spot)` (191-241): `Catalog.ModelOf(petName)` or nil (+warn "no model for pet"); clamps `spot` into the plot (Y ignored → plot top); sets attributes `PetName, DisplayName, Rarity, Owner, OwnerName, Plot, PartCount, RoamRadius, RoamGroundY, RoamPhase, RoamTo, RoamIdleUntil`; tag `PlotPet`; parent `plot.Pets` (folder created by `PetsFolderOf`).
- `ServerStorage.PetHatchAPI.SpawnPet` (254-260): `OnInvoke(player, plot, petName, spot)` → nil unless `player and plot and plot.Parent and type(petName)=="string" and typeof(spot)=="Vector3"`; returns the model or nil. `ClearPets` (261-267): `plot.Pets:ClearAllChildren()`, returns true. Only caller: BaseSaveService.
- `Hatch` (315-332): `BeginReveal` then **`egg:Destroy()`** (328) → egg tag removed → snapshot 0.5 s later drops the egg; pet exists only in `Pending` until `Finish` (Opened or 80 s fallback, 308-310).
- `PetHatch.OnServerEvent` "Opened" → `Finish(player)` with **no token** (382-384) → completes whatever is pending.
- Owner cleared → `ClearPlotPets(plot)` (389-391). PlayerRemoving (395-398) → `Pending[player] = nil` (hatch lost if mid-reveal), `Hatched[player] = nil`.
- Admin reset does **not** cancel `Pending`: a reveal started before the reset still spawns its pet afterwards (Finish only checks the plot Owner, 277) and the next snapshot saves it.

## 5. EggPlacement touch points
- Placed eggs live in **`plot.Placed`** (shared with placed cucumbers and builds) with attributes `Owner, EggName (short, e.g. "Basic"), Kg, Scale, Material (nil for normal), Mutations (CucumberMutations.Join string), DisplayName, HatchSeconds, PlacedAt, HatchAt` + tag `PlacedEgg` (204-223). No ID.
- `EggPlacementAPI.RestoreEgg(player, plot, record, pivot)` (231-259): no bounds check (the saved pivot is trusted), `Material "" → nil`, `CucumberMutations.Join(record.Mutations)` (drops unknown names), HatchAt kept (real time → offline countdown). Returns model or `nil, reason`. `ClearEggs(plot)` (261-272) destroys only `PlacedEgg`-tagged children, returns count.
- **Owner cleared → `HolderOf(plot):ClearAllChildren()` (311-313): destroys EVERYTHING in `plot.Placed` - eggs, placed cucumbers AND builds.** This is the biggest independent world-destroyer on leave (via PlotService.Release).
- PlayerRemoving (326): `LastPlace[player] = nil` only.

## 6. CucumberCarry / BuildService save hooks (for completeness)
- Placed cucumbers: parented to `plot.Placed` (CucumberCarry `HolderOf` 855-863), tag `PlacedCucumber`, attributes `Owner, CucumberName, Zone, TypeName, Golden, Material, Mutations, SizeTier, SizeScale, WeightKg, ShownKg`, child `PlotHitbox` (934-957). No ID today.
- `CucumberCarryAPI.RestorePlaced(player, plot, record, pivot, boxCF, boxSize)` (967-1041): respawns via `SpawnCarried` (Force/Anywhere), LEGACY_TYPES migration re-seats migrated types (989-1006). `ClearPlaced(plot)` (1043-1055) removes tag + destroys tagged children of Placed, returns count. PlayerRemoving (1183-1189): `CancelPending`, `Carrying/Busy/LastPlace/LastRelay = nil` (a shoulder-carried cucumber is not a base item and is not saved).
- Builds: `plot.Placed`, `BuildServiceAPI.RestoreBuild(player, plot, key, pivot, level)` (588-618; snaps floors/stairs, re-derives height from level), `ClearBuilds(plot)` (620-632). PlayerRemoving (672) clears rate-limit tables only. Owner changes → `publish` counts (404).

## 7. Plot ownership and plot size

### 7.1 ServerScriptService.PlotService
- Attributes (header 14): **`plot.Owner` (UserId number), `plot.OwnerName` (string), `player.Plot` (plot name string)**; plots also carry `PlotIndex` (sort, 81-84). Six plots `Plot 1..Plot 6` (`_structure.txt`).
- Startup (85-89): every plot's Owner/OwnerName cleared, a hidden `PlotSpawn` SpawnLocation built per plot (57-74), rebuilt on plot Size/CFrame change (91-118, deferred) and the owner's RespawnLocation re-pointed.
- `Assign(player)` (144-161) on **PlayerAdded, before the profile loads**: random free plot, sets `PlotOf/OwnerOf`, `Owner`, `OwnerName`, `player.Plot`, `RespawnLocation`. No free plot → warn, `RespawnLocation = nil`, no plot all session.
- `Release(player)` (163-171) on **`Players.PlayerRemoving:Connect(Release)` (198)**: clears `PlotOf/OwnerOf`, `plot.Owner = nil`, `plot.OwnerName = nil`, `player.Plot = nil`. It destroys nothing itself, but `Owner → nil` synchronously (Immediate) or at the next resumption point (Deferred) triggers:
  - EggPlacement 311-313: `plot.Placed:ClearAllChildren()` (eggs + cucumbers + builds)
  - PetHatchService 389-391: `plot.Pets:ClearAllChildren()`
  - PlotUpgradeService 304 → `SyncOwner` → `Resize(plot, 0)` (plot shrinks to level 0, fixtures move)
  - BuildService 404 publish counts; PlotBadges 151 badge refresh; GymService 274 `SyncPlot`; LeaderstatsService 167 `RefreshAllIncome`.
- PlotService knows nothing about DataService.

### 7.2 ServerScriptService.PlotUpgradeService
- `Resize(plot, level)` (118-127): size from `PlotUpgrades.Size`, back edge fixed, sets attribute **`PlotLevel`** (125) - BaseSave's restore waits on it.
- `SyncOwner(plot)` (250-262) on every Owner change (303-306): no owner → `Resize(plot, 0)` at once; else spawned `DataService.WaitForData(player)` (**default 30 s**) → `Resize(plot, data and data.PlotLevel or 0)` (if the profile is slower than 30 s - possible during a session steal - the plot is sized 0 and BaseSave proceeds after its 10 s LEVEL_TIMEOUT with a mismatched size).
- `Buy` (265-291): `DataService.Increment(player, "Cash", -cost)`, `data.PlotLevel = level + 1` (direct write), `RequestSave`, `Resize`. Remote `Remotes.PlotUpgradeAction` ("Buy"). PlayerRemoving (317) clears `LastBuy`. Studio hook `workspace.PlotUpgradeDev = "Plot 1:3"` (320-338) writes `data.PlotLevel` too.

### 7.3 ServerScriptService.SpawnAtBaseServer
Character placement only: waits for `player:GetAttribute("Plot")` (PLOT_WAIT 10 s, 0.2 s poll), at most two looks (`GRACE_SECONDS 4`, `SECOND_TRY 0.6`, `MARGIN 6`, `ROOT_UP 2.6`), pivots to `PlotSpawn`. **No PlayerRemoving, no persistence, no plot mutation.** Irrelevant to saves except that it depends on PlotService's `Plot` attribute.

## 8. AdminService (ServerScriptService)
- `ADMINS = {[140977250] = "awesomeotheraccount"}` (26); `COOLDOWN = 0.3` (27); remote `Remotes.AdminAction` RemoteFunction (30-35). `OnServerInvoke(player, action, value)` (110-131): `if not ADMINS[player.UserId] then return false, "Not an admin" end` (111) - the only permission check; cooldown; actions `"day"`, `"night"` (`ServerStorage.DayNightAPI.Force:Fire`), `"cash"`, `"strength"` (`DataService.Set` after `IsLoaded`), `"reset"`; everything pcall'd. PlayerRemoving (133) clears `LastAction`.
- `ResetData(player)` (79-108), in order:
  1. `DataService.IsLoaded` check.
  2. `BaseSaveAPI.Reset` (85): Paused, plot cleared (cucumbers, builds, pets, eggs), `Kept = nil`, `data.Base = {Version = 2, ...}`, RequestSave.
  3. `DataService.ResetProfile(player)` (88): **every key replaced from TEMPLATE → `Base.Version = 1`**, new nested tables, RequestSave.
  4. Owner bounce (91-101): `Owner/OwnerName = nil` → `task.wait()` → restored → EggPlacement/PetHatchService clear again, PlotUpgradeService resizes to 0 then re-syncs (data.PlotLevel = 0); waits ≤5 s for `PlotLevel == 0`. PlotService's internal maps are untouched.
  5. `BaseSaveAPI.Resume` (102) - snapshots back on, **no snapshot taken**, so Base.Version stays 1 until the next structural change.
  6. `task.defer(player:LoadCharacter)` (103-105).
- Not reset: PetHatchService `Pending`/`Hatched`, ZombieRaidService raids, CucumberCarry carry state, any cached references to the old `data.Base` tables.
- Studio caveat (header 13-14): "Works in Studio the same way (the profile is live there too - ProfileStore is not mocked)." With `USE_MOCK_IN_STUDIO = false` an admin reset in a playtest **wipes the real profile of UserId 140977250** (the one in `_profile_...json`).

## 9. Every PlayerRemoving / BindToClose handler
Order between handlers of different scripts (and between connections of one signal) is **unspecified**. `workspace.SignalBehavior` is not recorded in the snapshot - check it read-only in Studio before relying on Immediate vs Deferred timing (it also decides whether `player.Parent == Players` is still true inside handlers).

| handler | line | effect | destroys world/profile state? |
|---|---|---|---|
| DataService `OnPlayerRemoving` | DataService 251-255 (conn 261) | EndSession (final save) + Forget → GetData nil | profile access ends |
| PlotService `Release` | PlotService 198 | Owner/OwnerName/Plot attrs → nil ⇒ EggPlacement clears `plot.Placed`, PetHatchService clears `plot.Pets`, PlotUpgradeService `Resize(0)` | **YES (indirect, biggest)** |
| BaseSaveService | 261-271 | Active/Paused/Queued/Kept nil; ClearPlaced + ClearBuilds; no snapshot | **YES** |
| ZombieRaidService | 1617-1622 | `EndRaid(raid, "Left")` for night + day raids: zombies destroyed; `RestoreCarry(entry, true)` puts a carried cucumber back into `plot.Placed` with the tag (or **destroys it** if `raid.Player.Parent` is nil, 586-588); `ReturnDropped` (+ `BaseSaveAPI.Snapshot` only if `raid.Player.Parent`) | **YES** (re-adds cucumbers after the last snapshot / can orphan one on a released plot) |
| PetHatchService | 395-398 | `Pending = nil` (in-flight hatch lost), `Hatched = nil` | **YES (pending pet)** |
| CucumberCarry | 1183-1189 | cancels lift, forgets shoulder carry | carried cucumber only (never saved) |
| HeadbandService | 496-502 | `state.Cleanup()`, tables | character only |
| PortalService | 442-446 | `clearSession` (minigame map destroyed, attrs) | minigame only |
| DesertHuntService | 185 | `module.Cleanup` (gun, attrs) | no |
| StrengthProgressionServer | 118-125 | disconnects | no |
| LeaderstatsService | 154 | `Stats[player] = nil` (stops paying) | no |
| AdminService 133, BenchServer 155 & 491, BuildService 672, BuildPromptServer 52, BoostPadService 81, CucumberSpawner 1024, EggPlacement 326, CucumberMoveServer 121, EggShop 418, GuardianService 1226, GroupGiftServer 59, PlotUpgradeService 317, CucumberAdventure 214, PortalTransitionService 19 | - | rate-limit / session tables | no |
| ProfileStore `game:BindToClose` | ProfileStore 2199-2202 (mock) / 2208-2239 (access) | IsClosing; access mode: ends all sessions ("Shutdown") and waits | profile access ends |

No other `BindToClose` exists in the place.

## 10. Where the pre-close flush hook must go

**Profile side (DataService):**
1. Leave: in `OnPlayerRemoving` (251-255), run the pre-close callbacks synchronously **immediately before `profile:EndSession()` on line 253** (after it, `Forget` has already run via OnSessionEnd and GetData is nil).
2. Shutdown / external takeover: ProfileStore ends sessions itself in its BindToClose (2208-2239) and in the "External" path without calling DataService's leave handler. Hook `profile.OnLastSave` in `OnPlayerAdded`, next to the `OnSessionEnd` connection (line 232). `OnLastSave` fires at ProfileStore line 717, before `OnSessionEnd` (725) and before the UpdateAsync that serialises `profile.Data` (791), for all three reasons. A DataService-level `game:BindToClose` cannot be guaranteed to run first (ProfileStore binds during `require` on live servers and bound callbacks run concurrently).
3. Use one idempotent guard keyed by the profile object (the leave path runs the callbacks, then EndSession fires OnLastSave → no-op). Callbacks must not yield (a yield lets SaveProfileAsync continue: autosave removal, Forget, UpdateAsync). In mock/NoAccess mode there is no final save at shutdown (nothing is persisted anyway).
Sketch (names illustrative; CONTRACTS.md pins the real API):
```lua
local BeforeClose, ClosedProfiles = {}, {} -- fn(player, profile, reason); [profile] = true
function DataService.OnBeforeClose(fn) table.insert(BeforeClose, fn) end
local function RunBeforeClose(player, profile, reason)
	if ClosedProfiles[profile] then return end
	ClosedProfiles[profile] = true
	for _, fn in ipairs(BeforeClose) do
		local ok, err = pcall(fn, player, profile, reason)
		if not ok then warn("[DataService] before-close: " .. tostring(err)) end
	end
end
-- OnPlayerAdded, after line 232:
profile.OnLastSave:Connect(function(reason) RunBeforeClose(player, profile, reason) end)
-- OnPlayerRemoving, before line 253:
if profile then RunBeforeClose(player, profile, "Leave") profile:EndSession() end
```

**World side (the snapshot must see an intact plot):** the flush's `Snapshot` only works while `Active[player]` is set and `plot.Owner == player.UserId`. PlotService.Release (Owner → nil → Placed/Pets cleared, Resize 0) and BaseSave's own leave handler may run before DataService's handler. Keep Snapshot's guards (line 135) - they turn a too-late flush into "keep the last snapshot" instead of "save an empty plot". To make the flush effective:
- BaseSave's leave handler should `Snapshot(player, true)` before `Active[player] = nil` (262-263), and BaseSave should also register the DataService pre-close callback (whichever runs first wins; both are non-yielding).
- Deterministic option (preferred by PLAN 8.4): stop destroying from independent PlayerRemoving handlers - DataService fires a post-close signal after EndSession and PlotService.Release / BaseSave clear / PetService despawn run from it (keep a PlayerRemoving fallback for players whose profile never loaded, e.g. `if not DataService.IsLoaded(player) then Release(player) end`). Deferring `Release` with `task.defer` is a cheaper but weaker ordering trick.
- With canonical pet records held in the profile (not rebuilt from `PlotPet` tags) a missed world flush only loses logical positions/countdown progress, never ownership.
- End/settle the owner's raid inside the close sequence before the snapshot: a cucumber in a zombie's hands at leave is untagged (Grab 533) and therefore missing from the last snapshot (and the leave-time `RestoreCarry` re-tags it only after that).

## 11. The real saved profile (`_profile_Player_140977250_before-pets.json`)
Raw ProfileStore record: `{UserIds: [140977250], RobloxMetaData: [], GlobalUpdates: [0, []], WasOverwritten: false, Data: {...}, MetaData: {LastUpdate: 1790106762, MetaTags: [], ProfileCreateTime: 1788715426, SessionLoadCount: 403}}` (no `ActiveSession` → released at dump time). Empty Lua tables serialise as `[]` (RobloxMetaData, PortalCooldowns, Families).

`Data` keys (types):
| key | value |
|---|---|
| `Cash` | float 2154397399.109 |
| `Coins` | float 2099411071.013 - **legacy key, not in TEMPLATE nor REMOVED_KEYS**; do not reuse |
| `Playtime` | int 58874 |
| `Strength` | int 0 |
| `PlotLevel` | int 2 |
| `Upgrades` | `{BenchPress: 8}` |
| `GroupGiftClaimed` | true |
| `Headbands` | `{Equipped: "ChampionBand", Owned: {Sweatband: true, ChampionBand: true}}` |
| `CucumberCollection` | `{BestName (string, not in TEMPLATE), TotalSecured: 34, Seen: {"<Zone>:<Type>": true ×15}, Families: [], BestSize: 1, BestRequired: 7000000}` |
| `PortalCooldowns` | `[]` |
| `Base` | `{Version: 2, SavedAt: 1790106753 (2026-09-22 19:52:33 UTC), Pets[4], Builds[51], Cucumbers[2], Eggs[3]}` - no other keys |

`Base.Pets` (4 records, only `Pet` + `Pos`, no ID/traits):
```json
{"Pet":"Cat","Pos":[-16,2.5,51]}, {"Pet":"Cat","Pos":[-5,2.5,28]},
{"Pet":"Treasure Gem","Pos":[1,2.5,53]}, {"Pet":"Dog","Pos":[-11,1.16619873046875,35]}
```
`Pet` = internal catalog key (not the display name); duplicates of a species occur (two `Cat`). `Pos` = back-edge-anchor-local `{x, y, z}`; `y` is the pet's root height above the plot top (ignored on restore); integer x/z = the egg spot the pet spawned at (server pivot never moves).

`Base.Eggs` (3 records): keys `EggName` ("Basic" - short name; `PetsCatalog.EggKey` → "Basic Egg"), `Kg` (5 / 2 / 198), `Scale`, `Material` (**present only when not normal**: "Golden"), `Mutations` (comma string: "NEON", "", "SHADOW,RADIOACTIVE,FROZEN"), `DisplayName` ("Golden NEON Basic Egg"...), `HatchSeconds`, `PlacedAt`, `HatchAt` (unix floats), `Pivot` (12 numbers). **Two eggs (HatchAt 2026-09-12) have Pivot Y ≈ -225.9 / -226.4**, i.e. they are restored ~226 studs under the plot surface every session (RestoreEgg trusts the pivot) and can never be stood on/hatched - ghost records that every snapshot re-saves. Migration must keep them (assign IDs, do not drop).

`Base.Cucumbers` (2 records): keys `Type`, `Name`, `Zone`, `Golden` (bool), `Mutations` (string, ""), `Pivot` (12), `Box` (12), `Size` (3), optional `SizeTier` ("MASSIVE"), optional `Material` (absent here). No ID.

`Base.Builds` (51 records): `{Key, Level, Pivot}`; keys SpikeTrap 30, Flooring 14 (Level 2), Catapult 2, FreezeTower, Staircase, Mortar, BoostPad, TeslaCoil (1 each).

## 12. PLAN.md section 2 cross-check
Confirmed: DataService reconciles before callbacks and spawns callbacks (228, 247); BaseSave saves pets as `{Pet, Pos}` (127); Base VERSION 2 vs template 1 (34 vs 66); the v1 cucumber wipe (210-214); egg destroyed at reveal start, pet spawned on Opened/80 s fallback, Pending dropped on leave (328, 48, 396); stale server pet pivots (static `GetPivot`, confirmed by the saved data); pets live in `plot.Pets` tagged `PlotPet`; LeaderstatsService pays quietly every second and fires `CucumberIncome`.

Corrections / additions (the live code contradicts or goes beyond the plan):
1. **Issue 11 is incomplete.** BaseSave's leave handler is not the main world destroyer: `PlotService.Release` (Owner → nil) makes **EggPlacement clear all of `plot.Placed` (eggs, cucumbers, builds)**, PetHatchService clear `plot.Pets` and PlotUpgradeService resize to level 0; ZombieRaidService's `EndRaid(…, "Left")` also moves cucumbers. And there is **no snapshot at leave at all** - the saved Base is whatever the last (0.5 s-debounced or 30 s-heartbeat) snapshot wrote; a pending debounced snapshot is discarded.
2. **"DataService ends the profile session in its leave handler"** is only the leave path. On shutdown ProfileStore's own BindToClose ends every session (reason "Shutdown") without calling DataService; hook `profile.OnLastSave` as well (§10).
3. **"Migrate before callbacks"** - the precise requirement is before line 242 (`Profiles[player] = profile`), because GetData/IsLoaded/WaitForData expose the data from that line; and the migration must be pcall-guarded (session-leak risk, §1.5).
4. **Issue 4 is broader:** failed egg and build restores are dropped by the next snapshot too, and malformed records are dropped without even counting as failed. The "kept in the save" print (239) is only true until the next snapshot.
5. **PLAN 8.1 "Correct the template's base version to 2"** is safe for Reconcile (existing values are never overwritten) - but `DataService.ResetProfile` currently re-seeds `Base.Version = 1` after `BaseSaveAPI.Reset` wrote 2 (AdminService 85 → 88); the fix covers that.
6. **PLAN 8.1 / 8.2 template fields:** do NOT put `PetSchemaVersion` in `TEMPLATE.Base` - `profile:Reconcile()` (line 228) would stamp it onto every old profile before the migration and the migration would think it already ran. Put only empty containers (e.g. `PetRoster = {}`) in the template, or none.
7. **PLAN 7 "Data.CashPerSec"** is the NumberValue `player.Data.CashPerSec` owned by LeaderstatsService, not a profile field.
8. **PLAN 8.3 step 2 "Snapshot pending world placement changes through the base save API"**: `BaseSaveAPI.Snapshot` returns false (and does nothing) before the restore finished, while Paused, or after the Owner changed; and a successful Snapshot **replaces `data.Base`** - re-read `data.Base.Eggs` after it; never hold the old table.
9. **Record formats the plan's schema must bridge:** egg/cucumber `Mutations` are comma strings (plan's pet record uses an array), `Material` is absent for normal (plan says "empty for normal"), egg `EggName` is the short name ("Basic") while the plan's `SourceEgg` example is the catalog key ("Desert Egg"). `CucumberMutations.Parse/Join` drop unknown names (Parse 94-104), so they cannot be used to "retain unknown metadata".
10. **PLAN 8.4 BaseSaveAPI.Reload** exists (318-332) but has no live caller and only pauses BaseSave snapshots - no other service is paused.

## 13. Hazards for implementers
1. `TEMPLATE.Base.PetSchemaVersion` (or any "migrated" marker) in the template ⇒ Reconcile marks old profiles migrated ⇒ legacy pets never migrate.
2. `Collect` (95) + `Snapshot` (138) replace `data.Base` wholesale with six keys: PetSchemaVersion, PetRoster, reserve pets, IDs, PetBuffs, unknown fields all vanish on the next snapshot (0.5 s debounce / 30 s heartbeat / Reset). Build the new Base from the old one (copy unknown keys) and take Pets from canonical records, not `PlotPet` tags.
3. Any Base table written without `Version = 2` (nil counts as 0) arms the v1 cucumber wipe (210) on the next join.
4. An error in the new migration between `StartSessionAsync` and `Profiles[player] = profile` leaks an active, never-ended session - pcall it.
5. Pre-close callbacks after `EndSession`/`OnSessionEnd` see `GetData(player) == nil`; writes to `profile.Data` after that race the UpdateAsync. Flush strictly before line 253 and in `OnLastSave`; never yield in a flush callback.
6. PlayerRemoving handler order is unspecified: PlotService.Release can have already emptied `plot.Placed`/`plot.Pets` and resized the plot. Keep Snapshot's `Active`/`Paused`/`Owner` guards; never snapshot a plot whose Owner is not the player.
7. Deleting array records with `t[i] = nil` creates gaps ProfileStore cannot save (header line 9); use `table.remove`. No Vector3/CFrame/Instances in profile data (use Pack/PackV arrays). Mixed tables lose their string keys.
8. Saved pet `Pos` is the spawn spot, not the roaming position; the server pivot is static.
9. Failed pet/egg/build restores and precondition-failing records are dropped by the next snapshot; a reserve pet with no `Pos` would be too, unless BaseSave stops rebuilding Pets from the world.
10. Renaming/moving `ServerStorage.PetHatchAPI.SpawnPet` / `ClearPets` without updating BaseSave ⇒ BaseSave warns after 120 s and skips pet restore, and world-rebuilt snapshots then save an empty Pets list.
11. Admin reset: `ResetProfile` gives new nested tables (drop cached references; use a profile generation counter), resets `Base.Version` to the template value, does not cancel `PetHatchService.Pending` (a pre-reset hatch re-grants a pet), and Resume takes no snapshot. In Studio it wipes the REAL test profile (restore from the JSON backup).
12. `OnProfileLoaded` callbacks are spawned with no order (and replayed immediately for already-loaded profiles); BaseSave's Restore is spawned again and yields up to 60 + 20 + 10 + 0.3 s. PetService must not assume restore order; expose a synchronous `EnsureProfileState`.
13. A restored ready egg can hatch before BaseSave sets `Active` (tag events ignored); the post-restore snapshot then saves neither the egg nor the pending pet.
14. A cucumber a zombie is carrying at leave is untagged and missing from the last snapshot; EndRaid("Left") re-tags it afterwards or destroys it if the player is already unparented; depending on handler order it can end up orphaned in a released plot's `Placed` folder.
15. `RequestSave` is coalesced (5 s) and asynchronous; quiet writes wait for the ~60 s autosave or the final save. Nothing is durable synchronously.
16. `WaitForData` default timeout is 30 s; PlotUpgradeService uses it, so a slow session steal can leave the plot at level 0 while BaseSave restores after its 10 s LEVEL_TIMEOUT.
17. ProfileStore signal listeners fire newest-first via `task.spawn`; a yielding `OnLastSave` listener does not hold the save.
18. The real profile has two ghost eggs under the plot and a legacy `Coins` key - migrations must preserve unknown/odd records, not "clean them up".
19. `DataService.Template` is the live TEMPLATE table - never mutate it at runtime.
20. `workspace.SignalBehavior` is unknown from the snapshot; code that checks `player.Parent == Players` inside PlayerRemoving (DataService 234, ZombieRaidService 586) behaves differently under Deferred signals.
