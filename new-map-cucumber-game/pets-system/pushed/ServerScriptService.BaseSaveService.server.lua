--[[
	BaseSaveService  (Script, ServerScriptService)
	Saves what stands on a player's plot and puts it back when they return (user, 2026-09-12):
	  * placed cucumbers (tag "PlacedCucumber", CucumberCarry), base builds (tag "PlacedBuild",
	    BuildService) and placed eggs (tag "PlacedEgg",
	    EggPlacement; with their HatchAt clock, which is real time, so they count down while the owner
	    is away) - the ones with Owner = the player. Pets are no longer read from the world (PETS below).
	  * profile.Data.Base = {Version, SavedAt, Cucumbers, Builds, Pets, Eggs} (DataService; the template has an
	    empty one, so old profiles get it on Reconcile). Every position is stored relative to the plot's
	    BACK-EDGE frame (the edge PlotUpgradeService never moves - BuildCatalog.BackZ), so a saved base
	    lands in the same place after a plot upgrade and on a different plot next visit.
	  * RESTORE: once the profile is in and PlotService has handed out a plot, wait for PlotUpgradeService
	    to apply the saved PlotLevel (the plot's PlotLevel attribute), then eggs -> builds (ground floor first) ->
	    cucumbers through the owning services' bindables (EggPlacementAPI.RestoreEgg, ServerStorage.BuildServiceAPI.RestoreBuild,
	    CucumberCarryAPI.RestorePlaced). Nothing is charged or validated on the way back. Then the player's
	    BaseRestored attribute goes true and PetService attaches the equipped pets (PETS below).
	  * SNAPSHOT: after the restore, every tag add / remove on the player's things, every build move
	    (PlotX / PlotZ / Yaw / Level attributes) and a HEARTBEAT (pet positions + countdowns) rewrite Data.Base; the
	    structural ones ask DataService for a save, the heartbeat rides the autosave.
	  * LEAVE: a last quiet snapshot, then the plot is emptied (cucumbers + builds here; eggs go with the Owner
	    attribute, pets with PetService.DetachPlot) so the next tenant starts clean and a return never doubles up.
	  * ServerStorage.BaseSaveAPI (BindableFunctions) for AdminService: Snapshot(player), Reset(player)
	    (empties the plot and Data.Base, pauses snapshots), Resume(player); Reload(player) (tests) and
	    IsRestored(player) (2026-09-22).
	PETS (2026-09-22, pets-system CONTRACTS 4.8):
	  * Data.Base.Pets is the CANONICAL owned-pet list (active + reserve) and belongs to PetService. A
	    snapshot carries it - and PetRoster, PetSchemaVersion, PetNoticePending and any unknown Base key - over
	    by reference instead of rebuilding it from PlotPet tags; PetService.SyncRecords first writes the pets'
	    logical positions / ability countdowns into those records. Without PetService (staged install) the
	    records are still carried through untouched.
	  * IDs: saved eggs carry Id (the world egg's EggId), cucumbers Id (CucumberId) + PetBuffs
	    (PetBuffService.Serialize, absolute expiries). Eggs are single-use: a consumed egg, or one whose Id is
	    an owned pet's SourceEggId, is never saved or restored again, and a repeated egg Id is dropped at
	    restore (never re-IDed); a repeated cucumber Id gets a fresh one. Egg records that do not come back
	    are kept (KeptEggs) like the failed cucumbers (Kept).
	  * READINESS: the world restore never waits on the pet system. After Active the player gets
	    BaseRestored = true and, if PetService is ready within 2 s, EnsureProfileState + AttachPlot (else
	    PetService.Start's late sweep attaches them).
	  * FLUSH: DataService.OnBeforeClose(..., 40) snapshots the plot while it still stands (PlotService releases
	    it, and the LEAVE teardown here empties it, one deferred step after the leave, whichever PlayerRemoving
	    handler fires first); Reset / Reload / leave clear BaseRestored and detach the pets
	    (runtime only, records untouched). Every pet-module call is optional and pcall-guarded.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local DataService = require(ServerStorage:WaitForChild("DataService"))
local BuildCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BuildCatalog"))

local function Lazy(name) -- 2026-09-22: pet-system modules are optional until their stage is installed
	local cache
	return function()
		if cache then return cache end
		local module = ServerStorage:FindFirstChild(name)
		if not module then return nil end
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then cache = result end
		return cache
	end
end
local PetService = Lazy("PetService")() -- canonical pet ownership (nil: pets are neither synced nor attached, records still carried)
local PetBuffs = Lazy("PetBuffService") -- cucumber buff records (Serialize is pure: works before its Start)

local PLOTS = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
local TAG_CUCUMBER, TAG_BUILD, TAG_EGG = "PlacedCucumber", "PlacedBuild", "PlacedEgg" -- 2026-09-22: no PlotPet (pets are PetService's records)
local VERSION = 2 -- 2 (2026-09-13): the cucumber set was replaced; see the gate in Restore
local SNAPSHOT_DEBOUNCE = 0.5 -- seconds: a burst of changes becomes one write
local HEARTBEAT = 30 -- seconds between quiet snapshots (pet positions)
local PLOT_TIMEOUT = 20 -- seconds to wait for PlotService to hand out a plot
local LEVEL_TIMEOUT = 10 -- seconds to wait for PlotUpgradeService to apply the saved level
local MOVE_ATTRIBUTES = {PlotX = true, PlotZ = true, Yaw = true, Level = true} -- BuildService.Stamp: a moved build

--..The owning services' restore / clear bindables (each service makes its own folder at start)..--
local function Bindable(folderName, name)
	local folder = ServerStorage:WaitForChild(folderName, 120)
	local fn = folder and folder:WaitForChild(name, 120)
	if not fn then warn(("[BaseSave] no ServerStorage.%s.%s - that kind will not save"):format(folderName, name)) end
	return fn
end
local restorePlaced = Bindable("CucumberCarryAPI", "RestorePlaced")
local clearPlaced = Bindable("CucumberCarryAPI", "ClearPlaced")
local restoreBuild = Bindable("BuildServiceAPI", "RestoreBuild")
local clearBuilds = Bindable("BuildServiceAPI", "ClearBuilds")
local restoreEgg = Bindable("EggPlacementAPI", "RestoreEgg")
local clearEggs = Bindable("EggPlacementAPI", "ClearEggs")

local Active = {} -- [player] = plot once the restore is through (snapshots on)
local Paused = {} -- [player] = true while an admin reset empties the plot
local Queued = {} -- [player] = true while a debounced snapshot is pending
--.. [player] = saved cucumber records that failed to come back this session (2026-09-18). Every
--.. snapshot rebuilds Data.Base from what stands on the plot, so without this the 30 s heartbeat
--.. would silently drop them; they ride along in each snapshot and are retried on the next join
local Kept = {}
local KeptEggs = {} -- [player] = saved egg records that did not come back this session (2026-09-22, like Kept)
local LastWarn = {} -- [key] = os.clock() of the last warn of that kind

--..Helpers..--
local function WarnOnce(key, message) -- 2026-09-22: at most one warn per kind per minute
	local now = os.clock()
	if LastWarn[key] and now - LastWarn[key] < 60 then return end
	LastWarn[key] = now
	warn(message)
end

local function IsValidId(id)
	return type(id) == "string" and #id >= 1 and #id <= 64
end

--.. PetService calls are optional: skipped while it is missing / not started, pcall-guarded, warned once.
--.. always = true skips the started check (DetachPlot is safe on a module that never started)
local function PetCall(always, name, ...)
	if not PetService or type(PetService[name]) ~= "function" then return false end
	if not always then
		local okStarted, started = pcall(PetService.IsStarted)
		if not okStarted or started ~= true then return false end
	end
	local ok, result = pcall(PetService[name], ...)
	if not ok then
		WarnOnce("pet:" .. name, ("[BaseSave] PetService.%s failed: %s"):format(name, tostring(result)))
		return false
	end
	return true, result
end

--.. [eggId] = true for every egg an owned pet hatched from (eggs are single-use)
local function OwnedSourceEggs(pets)
	local owned = {}
	if type(pets) ~= "table" then return owned end
	for _, rec in ipairs(pets) do
		if type(rec) == "table" and type(rec.SourceEggId) == "string" then owned[rec.SourceEggId] = true end
	end
	return owned
end

--.. remove one record from a live profile array by identity (a hatch may have shifted it meanwhile)
local function RemoveRecord(list, rec)
	if type(list) ~= "table" then return false end
	for i, other in ipairs(list) do
		if other == rec then
			table.remove(list, i)
			return true
		end
	end
	return false
end

local function PlotOf(player)
	for _, plot in ipairs(PLOTS:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

--.. the frame everything is saved against: the plot's top surface at the middle of its BACK edge
local function AnchorOf(plot)
	local backZ = BuildCatalog.BackZ(plot)
	return plot.CFrame * CFrame.new(0, plot.Size.Y * 0.5, backZ)
end

local function Pack(cf) return {cf:GetComponents()} end
local function Unpack(t)
	if type(t) ~= "table" or #t ~= 12 then return nil end
	for i = 1, 12 do if type(t[i]) ~= "number" then return nil end end
	return CFrame.new(table.unpack(t))
end
local function PackV(v) return {v.X, v.Y, v.Z} end
local function UnpackV(t)
	if type(t) ~= "table" or #t ~= 3 or type(t[1]) ~= "number" or type(t[2]) ~= "number" or type(t[3]) ~= "number" then return nil end
	return Vector3.new(t[1], t[2], t[3])
end

--..Snapshot: what stands on the plot -> Data.Base..--
--.. 2026-09-22: the new Base is built FROM the old one - every key except the world lists is carried over by
--.. reference (Pets, PetRoster, PetSchemaVersion, PetNoticePending, unknown keys): pets are PetService's
--.. canonical records, never rebuilt from PlotPet tags. Never throws (every pet-module call is pcall'd).
local function Collect(player, plot, data)
	local anchor = AnchorOf(plot)
	local uid = player.UserId
	local old = type(data.Base) == "table" and data.Base or {}
	PetCall(false, "SyncRecords", player, anchor) -- pet Pos / AbilityRemaining into the records first
	local base = {}
	for key, value in pairs(old) do
		if key ~= "Version" and key ~= "SavedAt" and key ~= "Cucumbers" and key ~= "Builds" and key ~= "Eggs" then base[key] = value end
	end
	base.Version = VERSION
	base.SavedAt = os.time()
	base.Cucumbers, base.Builds, base.Eggs = {}, {}, {}
	base.Pets = old.Pets or {}
	local ownedSource = OwnedSourceEggs(old.Pets) -- hatched eggs are never saved again
	local emittedEgg = {}
	for _, egg in ipairs(CollectionService:GetTagged(TAG_EGG)) do
		if egg:IsA("Model") and egg:GetAttribute("Owner") == uid and egg:IsDescendantOf(plot) and egg:GetAttribute("EggName") then
			local id = egg:GetAttribute("EggId")
			local usable = egg:GetAttribute("Consumed") ~= true and not (id and (ownedSource[id] or emittedEgg[id]))
			if usable then
				if id then emittedEgg[id] = true end
				table.insert(base.Eggs, {
					Id = id,
					EggName = egg:GetAttribute("EggName"), Kg = egg:GetAttribute("Kg"), Scale = egg:GetAttribute("Scale"),
					Material = egg:GetAttribute("Material"), Mutations = egg:GetAttribute("Mutations"), DisplayName = egg:GetAttribute("DisplayName"),
					HatchSeconds = egg:GetAttribute("HatchSeconds"), PlacedAt = egg:GetAttribute("PlacedAt"), HatchAt = egg:GetAttribute("HatchAt"),
					Pivot = Pack(anchor:ToObjectSpace(egg:GetPivot())),
				})
			end
		end
	end
	local keptEgg = {}
	for _, rec in ipairs(KeptEggs[player] or {}) do
		local id = rec.Id
		if not (id and (emittedEgg[id] or ownedSource[id] or keptEgg[id])) then
			if id then keptEgg[id] = true end
			table.insert(base.Eggs, rec)
		end
	end
	local buffs = PetBuffs()
	for _, model in ipairs(CollectionService:GetTagged(TAG_CUCUMBER)) do
		if model:IsA("Model") and model:GetAttribute("Owner") == uid and model:IsDescendantOf(plot) then
			local box = model:FindFirstChild("PlotHitbox")
			if box and box:IsA("BasePart") then
				local rec = {
					Id = model:GetAttribute("CucumberId"),
					Zone = model:GetAttribute("Zone"), Type = model:GetAttribute("TypeName"), Golden = model:GetAttribute("Golden") == true,
					Material = model:GetAttribute("Material"), Mutations = model:GetAttribute("Mutations"), SizeTier = model:GetAttribute("SizeTier"),
					Name = model:GetAttribute("CucumberName") or model.Name,
					Pivot = Pack(anchor:ToObjectSpace(model:GetPivot())), Box = Pack(anchor:ToObjectSpace(box.CFrame)), Size = PackV(box.Size),
				}
				if buffs and rec.Id ~= nil then
					local ok, petBuffs = pcall(buffs.Serialize, model)
					if ok then
						rec.PetBuffs = petBuffs
					else
						WarnOnce("serialize", "[BaseSave] PetBuffService.Serialize failed (cucumber saved without buffs): " .. tostring(petBuffs))
					end
				end
				table.insert(base.Cucumbers, rec)
			end
		end
	end
	for _, rec in ipairs(Kept[player] or {}) do table.insert(base.Cucumbers, rec) end
	for _, model in ipairs(CollectionService:GetTagged(TAG_BUILD)) do
		if model:IsA("Model") and model:GetAttribute("Owner") == uid and model:IsDescendantOf(plot) and model:GetAttribute("BuildKey") then
			table.insert(base.Builds, {Key = model:GetAttribute("BuildKey"), Level = tonumber(model:GetAttribute("Level")) or 1, Pivot = Pack(anchor:ToObjectSpace(model:GetPivot()))})
		end
	end
	return base
end

local function Snapshot(player, quiet)
	local plot = Active[player]
	if not plot or Paused[player] or not plot.Parent or plot:GetAttribute("Owner") ~= player.UserId then return false end
	local data = DataService.GetData(player)
	if not data then return false end
	data.Base = Collect(player, plot, data)
	if not quiet then DataService.RequestSave(player) end
	return true
end

local function Queue(player)
	if not Active[player] or Paused[player] or Queued[player] then return end
	Queued[player] = true
	task.delay(SNAPSHOT_DEBOUNCE, function()
		Queued[player] = nil
		if Active[player] and not Paused[player] then Snapshot(player, false) end
	end)
end

--.. a thing was added / removed / moved: its owner's base changed. A pick-up clears the Owner attribute
--.. before the tag goes, so when the owner cannot be read every active player is refreshed (cheap)
local function QueueOwner(inst)
	local uid = inst:GetAttribute("Owner")
	local player = uid and Players:GetPlayerByUserId(uid)
	if player then Queue(player) return end
	for p in pairs(Active) do Queue(p) end
end

--..Restore: Data.Base -> the plot, once the plot is the saved size..--
local function Restore(player)
	local data = DataService.WaitForData(player, 60)
	if not data or player.Parent ~= Players then return end
	local plot
	local deadline = os.clock() + PLOT_TIMEOUT
	while player.Parent == Players and os.clock() < deadline do
		plot = PlotOf(player)
		if plot then break end
		task.wait(0.25)
	end
	if not plot then
		if player.Parent == Players then warn("[BaseSave] " .. player.Name .. " got no plot; nothing restored") end
		return
	end
	local wantLevel = tonumber(data.PlotLevel) or 0
	deadline = os.clock() + LEVEL_TIMEOUT
	while plot:GetAttribute("PlotLevel") ~= wantLevel and os.clock() < deadline and player.Parent == Players do task.wait(0.1) end
	task.wait(0.3) -- the grass grid rebuilds a frame after the resize
	if player.Parent ~= Players or plot:GetAttribute("Owner") ~= player.UserId then return end
	local base = type(data.Base) == "table" and data.Base or nil
	local anchor = AnchorOf(plot)
	local counts, failed = {Builds = 0, Cucumbers = 0, Pets = 0, Eggs = 0}, 0
	if base then
		--.. eggs first: their clock kept running while the owner was away (HatchAt is real time), so a
		--.. ready one hatches the moment the owner steps on it.
		--.. 2026-09-22: eggs are single-use. A copy of the list is walked (a hatch may change the live one); a
		--.. record repeating an Id seen earlier, or whose Id an owned pet hatched from, is removed from the live
		--.. list instead of restored (never re-IDed); one without an Id gets one; a record that does not come
		--.. back is kept (KeptEggs) and rides every snapshot until a later join restores it
		KeptEggs[player] = nil
		local ownedSource = OwnedSourceEggs(base.Pets)
		local eggs, seenEgg = {}, {}
		for _, rec in ipairs(type(base.Eggs) == "table" and base.Eggs or {}) do table.insert(eggs, rec) end
		for _, rec in ipairs(eggs) do
			if type(rec) ~= "table" then continue end
			if IsValidId(rec.Id) and (seenEgg[rec.Id] or ownedSource[rec.Id]) then
				RemoveRecord(base.Eggs, rec)
				print(("[BaseSave] %s: dropped egg record %s (%s)"):format(player.Name, rec.Id, seenEgg[rec.Id] and "duplicate id" or "already hatched"))
				continue
			end
			if not IsValidId(rec.Id) then
				rec.Id = HttpService:GenerateGUID(false)
				print(("[BaseSave] %s: egg record without an id got %s"):format(player.Name, rec.Id))
			end
			seenEgg[rec.Id] = true
			local pivot = Unpack(rec.Pivot)
			local restored = false
			if rec.EggName and pivot and restoreEgg then
				local ok, result, reason = pcall(restoreEgg.Invoke, restoreEgg, player, plot, rec, anchor * pivot)
				restored = ok and result and true or false
				if restored then counts.Eggs += 1 else failed += 1 warn(("[BaseSave] egg %s not restored: %s"):format(tostring(rec.EggName), tostring(ok and reason or result))) end
			end
			if not restored then
				KeptEggs[player] = KeptEggs[player] or {}
				table.insert(KeptEggs[player], rec)
			end
		end
		local builds = {}
		for _, rec in ipairs(type(base.Builds) == "table" and base.Builds or {}) do table.insert(builds, rec) end
		table.sort(builds, function(a, b) return (tonumber(a.Level) or 1) < (tonumber(b.Level) or 1) end) -- the ground floor first
		for _, rec in ipairs(builds) do
			local pivot = Unpack(rec.Pivot)
			if rec.Key and pivot and restoreBuild then
				local ok, result, reason = pcall(restoreBuild.Invoke, restoreBuild, player, plot, rec.Key, anchor * pivot, tonumber(rec.Level) or 1)
				if ok and result then counts.Builds += 1 else failed += 1 warn(("[BaseSave] build %s not restored: %s"):format(tostring(rec.Key), tostring(ok and reason or result))) end
			end
		end
		--.. 2026-09-13: the whole cucumber set was replaced with new models. Type names and
		--.. zones are unchanged, so CucumberAdventure's "<Zone>:<TypeName>" collection keys and
		--.. CucumberValues' rewards all still resolve -- but a placed cucumber's stored Pivot is
		--.. the height of the OLD model's centre, and the new models are a different height, so
		--.. replaying a version-1 record would bury or float every cucumber on the plot. Drop
		--.. those records once, per profile. Builds, pets and eggs are untouched.
		if (tonumber(base.Version) or 0) < 2 and type(base.Cucumbers) == "table" and #base.Cucumbers > 0 then
			print(("[BaseSave] %s: dropping %d cucumber(s) saved under base version %s - the cucumber set was replaced")
				:format(player.Name, #base.Cucumbers, tostring(base.Version)))
			base.Cucumbers = {}
		end
		Kept[player] = nil
		--.. 2026-09-22: walk a copy taken AFTER the version gate above (it swaps the array). Cucumbers are not
		--.. single-use: a record repeating an earlier Id (or without one) gets a fresh Id before it is restored
		local cucumbers, seenCucumber, repaired = {}, {}, 0
		for _, rec in ipairs(type(base.Cucumbers) == "table" and base.Cucumbers or {}) do table.insert(cucumbers, rec) end
		for _, rec in ipairs(cucumbers) do
			if type(rec) == "table" then
				if not IsValidId(rec.Id) or seenCucumber[rec.Id] then
					rec.Id = HttpService:GenerateGUID(false)
					repaired += 1
				end
				seenCucumber[rec.Id] = true
			end
		end
		if repaired > 0 then print(("[BaseSave] %s: %d cucumber record(s) got a fresh id (missing or repeated)"):format(player.Name, repaired)) end
		for _, rec in ipairs(cucumbers) do
			local pivot, box, size = Unpack(rec.Pivot), Unpack(rec.Box), UnpackV(rec.Size)
			if rec.Type and pivot and box and size and restorePlaced then
				local ok, result, reason = pcall(restorePlaced.Invoke, restorePlaced, player, plot, rec, anchor * pivot, anchor * box, size)
				if ok and result then
					counts.Cucumbers += 1
				else
					failed += 1
					Kept[player] = Kept[player] or {}
					table.insert(Kept[player], rec)
					warn(("[BaseSave] cucumber %s not restored: %s"):format(tostring(rec.Name or rec.Type), tostring(ok and reason or result)))
				end
			end
		end
	end
	Active[player] = plot
	--.. 2026-09-22: the world is back - pets may hatch / earn / take buffs from now on. The equipped pets are
	--.. PetService's (it spawns them from the canonical records); it gets 2 s to be ready, otherwise its own
	--.. late-start sweep attaches everyone whose BaseRestored is true
	player:SetAttribute("BaseRestored", true)
	if PetService then
		local okReady, ready = pcall(PetService.WaitReady, 2)
		if okReady and ready == true then
			PetCall(false, "EnsureProfileState", player)
			local okAttach, spawned = PetCall(false, "AttachPlot", player, plot)
			if okAttach then counts.Pets = tonumber(spawned) or 0 end
		end
	end
	print(("[BaseSave] %s on %s (level %d): restored %d builds, %d cucumbers, %d pets, %d eggs%s"):format(player.Name, plot.Name, wantLevel, counts.Builds, counts.Cucumbers, counts.Pets, counts.Eggs, failed > 0 and (", " .. failed .. " FAILED (kept in the save)") or ""))
	--.. what actually came back is the truth from here on - unless something failed, then the save is kept as it was
	if failed == 0 then Snapshot(player, true) end
end

--..Wiring..--
local function WatchBuild(model)
	model.AttributeChanged:Connect(function(name)
		if MOVE_ATTRIBUTES[name] then QueueOwner(model) end
	end)
end
--.. 2026-09-22: pet models (PlotPet) are not a trigger any more: spawning / despawning one changes no saved
--.. record, and PetService asks for its own save when the roster changes
for _, tag in ipairs({TAG_CUCUMBER, TAG_BUILD, TAG_EGG}) do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		if tag == TAG_BUILD then WatchBuild(inst) end
		QueueOwner(inst)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(QueueOwner)
end
for _, model in ipairs(CollectionService:GetTagged(TAG_BUILD)) do WatchBuild(model) end

DataService.OnProfileLoaded(function(player) task.spawn(Restore, player) end)

--.. 2026-09-22: the pre-close flush (DataService runs these before the final save, in order: pets frozen 10,
--.. income settled 20, pet records synced 30, raids settled 35, then this) writes the plot while it still stands
if type(DataService.OnBeforeClose) == "function" then
	DataService.OnBeforeClose(function(player)
		local ok, err = pcall(Snapshot, player, true)
		if not ok then WarnOnce("close", "[BaseSave] pre-close snapshot failed: " .. tostring(err)) end
	end, 40)
end

local function Leave(player)
	local plot = Active[player]
	if plot then
		--.. 2026-09-22: one last quiet snapshot (the final save follows; refused once the profile is gone)
		local ok, err = pcall(Snapshot, player, true)
		if not ok then WarnOnce("leave", "[BaseSave] leave snapshot failed: " .. tostring(err)) end
	end
	player:SetAttribute("BaseRestored", nil)
	Active[player] = nil
	Paused[player] = nil
	Queued[player] = nil
	Kept[player] = nil
	KeptEggs[player] = nil
	if plot and plot.Parent then
		if clearPlaced then pcall(clearPlaced.Invoke, clearPlaced, plot) end
		if clearBuilds then pcall(clearBuilds.Invoke, clearBuilds, plot) end
	end
	PetCall(true, "DetachPlot", player, "Left")
end

--.. 2026-09-22: PlayerRemoving handlers fire in any order. With the pre-close flush the teardown waits one
--.. deferred step (like PlotService's Release), so DataService's flush (raids settled at 35, the snapshot at
--.. 40) always finds Active[player] and a full plot - torn down first, the flush snapshot was refused and a
--.. cucumber a zombie carried (sent home at 35) was missing from the final save. By then the profile is gone,
--.. so the snapshot in Leave is refused. Without the flush (older DataService) the leave snapshot must beat the
--.. final save and stays synchronous
Players.PlayerRemoving:Connect(function(player)
	if type(DataService.OnBeforeClose) == "function" then
		task.defer(Leave, player)
	else
		Leave(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(HEARTBEAT)
		for player, plot in pairs(Active) do
			if plot and not Paused[player] then
				local ok, err = pcall(Snapshot, player, true) -- 2026-09-22: one bad player never stops the loop
				if not ok then WarnOnce("heartbeat", "[BaseSave] heartbeat snapshot failed: " .. tostring(err)) end
			end
		end
	end
end)

--..API (AdminService)..--
do
	local api = ServerStorage:FindFirstChild("BaseSaveAPI") or Instance.new("Folder")
	api.Name = "BaseSaveAPI"
	api.Parent = ServerStorage
	local function bindable(name, fn)
		local b = api:FindFirstChild(name) or Instance.new("BindableFunction")
		b.Name = name
		b.OnInvoke = fn
		b.Parent = api
	end
	bindable("Snapshot", function(player) return Snapshot(player, false) end)
	bindable("Reset", function(player)
		Paused[player] = true
		player:SetAttribute("BaseRestored", nil) -- 2026-09-22: no hatches / buffs until Resume
		local plot = Active[player] or PlotOf(player)
		local cleared = 0
		if plot then
			if clearPlaced then local ok, n = pcall(clearPlaced.Invoke, clearPlaced, plot) cleared += (ok and tonumber(n)) or 0 end
			if clearBuilds then local ok, n = pcall(clearBuilds.Invoke, clearBuilds, plot) cleared += (ok and tonumber(n)) or 0 end
			PetCall(true, "DetachPlot", player, "Reset")
			if clearEggs then local ok, n = pcall(clearEggs.Invoke, clearEggs, plot) cleared += (ok and tonumber(n)) or 0 end
		end
		Kept[player] = nil -- an admin reset empties the base, the unrestored records included
		KeptEggs[player] = nil
		local data = DataService.GetData(player)
		if data then
			--.. 2026-09-22: the empty base is already on the pet schema (no reserve pets, empty roster)
			data.Base = {Version = VERSION, SavedAt = os.time(), Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}, PetRoster = {}, PetSchemaVersion = 1}
			DataService.RequestSave(player)
		end
		return true, cleared
	end)
	bindable("Resume", function(player)
		Paused[player] = nil
		if not Active[player] then Active[player] = PlotOf(player) end
		if Active[player] then
			--.. 2026-09-22: never waits - a PetService that is not started attaches them in its late sweep
			player:SetAttribute("BaseRestored", true)
			PetCall(false, "EnsureProfileState", player)
			PetCall(false, "AttachPlot", player, Active[player])
		end
		return Active[player] ~= nil
	end)
	--.. empty the plot and rebuild it from Data.Base as a rejoin would (the persistence test's round trip)
	bindable("Reload", function(player)
		local plot = Active[player] or PlotOf(player)
		if not plot then return false, "no plot" end
		Paused[player] = true
		Active[player] = nil
		Queued[player] = nil
		player:SetAttribute("BaseRestored", nil) -- 2026-09-22: Restore sets it again
		if clearPlaced then pcall(clearPlaced.Invoke, clearPlaced, plot) end
		if clearBuilds then pcall(clearBuilds.Invoke, clearBuilds, plot) end
		PetCall(true, "DetachPlot", player, "Reload")
		if clearEggs then pcall(clearEggs.Invoke, clearEggs, plot) end
		task.wait(0.6) -- the tag-removed events of the clearing fire deferred; they must find nothing to snapshot
		Paused[player] = nil
		Restore(player)
		return Active[player] ~= nil
	end)
	--.. 2026-09-22: true once the base is back and snapshots run (pet-system readiness)
	bindable("IsRestored", function(player)
		return Active[player] ~= nil and not Paused[player]
	end)
end

print("[BaseSave] placed cucumbers, builds, pets and eggs save to Data.Base and come back on rejoin")
