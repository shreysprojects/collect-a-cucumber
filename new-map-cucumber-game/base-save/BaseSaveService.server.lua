--[[
	BaseSaveService  (Script, ServerScriptService)
	Saves what stands on a player's plot and puts it back when they return (user, 2026-09-12):
	  * placed cucumbers (tag "PlacedCucumber", CucumberCarry), base builds (tag "PlacedBuild",
	    BuildService), plot pets (tag "PlotPet", PetHatchService) and placed eggs (tag "PlacedEgg",
	    EggPlacement; with their HatchAt clock, which is real time, so they count down while the owner
	    is away) - the ones with Owner = the player.
	  * profile.Data.Base = {Version, SavedAt, Cucumbers, Builds, Pets, Eggs} (DataService; the template has an
	    empty one, so old profiles get it on Reconcile). Every position is stored relative to the plot's
	    BACK-EDGE frame (the edge PlotUpgradeService never moves - BuildCatalog.BackZ), so a saved base
	    lands in the same place after a plot upgrade and on a different plot next visit.
	  * RESTORE: once the profile is in and PlotService has handed out a plot, wait for PlotUpgradeService
	    to apply the saved PlotLevel (the plot's PlotLevel attribute), then builds (ground floor first) ->
	    cucumbers -> pets through the owning services' bindables (ServerStorage.BuildServiceAPI.RestoreBuild,
	    CucumberCarryAPI.RestorePlaced, PetHatchAPI.SpawnPet). Nothing is charged or validated on the way back.
	  * SNAPSHOT: after the restore, every tag add / remove on the player's things, every build move
	    (PlotX / PlotZ / Yaw / Level attributes) and a HEARTBEAT (pets wander) rewrite Data.Base; the
	    structural ones ask DataService for a save, the heartbeat rides the autosave.
	  * LEAVE: the plot is emptied (cucumbers + builds here; pets and eggs already go with the Owner
	    attribute) so the next tenant starts clean and a return never doubles up.
	  * ServerStorage.BaseSaveAPI (BindableFunctions) for AdminService: Snapshot(player), Reset(player)
	    (empties the plot and Data.Base, pauses snapshots), Resume(player).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local DataService = require(ServerStorage:WaitForChild("DataService"))
local BuildCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BuildCatalog"))

local PLOTS = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
local TAG_CUCUMBER, TAG_BUILD, TAG_PET, TAG_EGG = "PlacedCucumber", "PlacedBuild", "PlotPet", "PlacedEgg"
local VERSION = 1
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
local spawnPet = Bindable("PetHatchAPI", "SpawnPet")
local clearPets = Bindable("PetHatchAPI", "ClearPets")
local restoreEgg = Bindable("EggPlacementAPI", "RestoreEgg")
local clearEggs = Bindable("EggPlacementAPI", "ClearEggs")

local Active = {} -- [player] = plot once the restore is through (snapshots on)
local Paused = {} -- [player] = true while an admin reset empties the plot
local Queued = {} -- [player] = true while a debounced snapshot is pending

--..Helpers..--
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
local function Collect(player, plot)
	local anchor = AnchorOf(plot)
	local uid = player.UserId
	local base = {Version = VERSION, SavedAt = os.time(), Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}}
	for _, egg in ipairs(CollectionService:GetTagged(TAG_EGG)) do
		if egg:IsA("Model") and egg:GetAttribute("Owner") == uid and egg:IsDescendantOf(plot) and egg:GetAttribute("EggName") then
			table.insert(base.Eggs, {
				EggName = egg:GetAttribute("EggName"), Kg = egg:GetAttribute("Kg"), Scale = egg:GetAttribute("Scale"),
				Material = egg:GetAttribute("Material"), Mutations = egg:GetAttribute("Mutations"), DisplayName = egg:GetAttribute("DisplayName"),
				HatchSeconds = egg:GetAttribute("HatchSeconds"), PlacedAt = egg:GetAttribute("PlacedAt"), HatchAt = egg:GetAttribute("HatchAt"),
				Pivot = Pack(anchor:ToObjectSpace(egg:GetPivot())),
			})
		end
	end
	for _, model in ipairs(CollectionService:GetTagged(TAG_CUCUMBER)) do
		if model:IsA("Model") and model:GetAttribute("Owner") == uid and model:IsDescendantOf(plot) then
			local box = model:FindFirstChild("PlotHitbox")
			if box and box:IsA("BasePart") then
				table.insert(base.Cucumbers, {
					Zone = model:GetAttribute("Zone"), Type = model:GetAttribute("TypeName"), Golden = model:GetAttribute("Golden") == true,
					Material = model:GetAttribute("Material"), Mutations = model:GetAttribute("Mutations"), SizeTier = model:GetAttribute("SizeTier"),
					Name = model:GetAttribute("CucumberName") or model.Name,
					Pivot = Pack(anchor:ToObjectSpace(model:GetPivot())), Box = Pack(anchor:ToObjectSpace(box.CFrame)), Size = PackV(box.Size),
				})
			end
		end
	end
	for _, model in ipairs(CollectionService:GetTagged(TAG_BUILD)) do
		if model:IsA("Model") and model:GetAttribute("Owner") == uid and model:IsDescendantOf(plot) and model:GetAttribute("BuildKey") then
			table.insert(base.Builds, {Key = model:GetAttribute("BuildKey"), Level = tonumber(model:GetAttribute("Level")) or 1, Pivot = Pack(anchor:ToObjectSpace(model:GetPivot()))})
		end
	end
	for _, pet in ipairs(CollectionService:GetTagged(TAG_PET)) do
		if pet:IsA("Model") and pet:GetAttribute("Owner") == uid and pet:IsDescendantOf(plot) and pet:GetAttribute("PetName") then
			table.insert(base.Pets, {Pet = pet:GetAttribute("PetName"), Pos = PackV(anchor:PointToObjectSpace(pet:GetPivot().Position))})
		end
	end
	return base
end

local function Snapshot(player, quiet)
	local plot = Active[player]
	if not plot or Paused[player] or not plot.Parent or plot:GetAttribute("Owner") ~= player.UserId then return false end
	local data = DataService.GetData(player)
	if not data then return false end
	data.Base = Collect(player, plot)
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
		--.. ready one hatches the moment the owner steps on it
		for _, rec in ipairs(type(base.Eggs) == "table" and base.Eggs or {}) do
			local pivot = Unpack(rec.Pivot)
			if rec.EggName and pivot and restoreEgg then
				local ok, result, reason = pcall(restoreEgg.Invoke, restoreEgg, player, plot, rec, anchor * pivot)
				if ok and result then counts.Eggs += 1 else failed += 1 warn(("[BaseSave] egg %s not restored: %s"):format(tostring(rec.EggName), tostring(ok and reason or result))) end
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
		for _, rec in ipairs(type(base.Cucumbers) == "table" and base.Cucumbers or {}) do
			local pivot, box, size = Unpack(rec.Pivot), Unpack(rec.Box), UnpackV(rec.Size)
			if rec.Type and pivot and box and size and restorePlaced then
				local ok, result, reason = pcall(restorePlaced.Invoke, restorePlaced, player, plot, rec, anchor * pivot, anchor * box, size)
				if ok and result then counts.Cucumbers += 1 else failed += 1 warn(("[BaseSave] cucumber %s not restored: %s"):format(tostring(rec.Name or rec.Type), tostring(ok and reason or result))) end
			end
		end
		for _, rec in ipairs(type(base.Pets) == "table" and base.Pets or {}) do
			local pos = UnpackV(rec.Pos)
			if rec.Pet and pos and spawnPet then
				local ok, result = pcall(spawnPet.Invoke, spawnPet, player, plot, rec.Pet, anchor:PointToWorldSpace(pos))
				if ok and result then counts.Pets += 1 else failed += 1 warn(("[BaseSave] pet %s not restored: %s"):format(tostring(rec.Pet), tostring(result))) end
			end
		end
	end
	Active[player] = plot
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
for _, tag in ipairs({TAG_CUCUMBER, TAG_BUILD, TAG_PET, TAG_EGG}) do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		if tag == TAG_BUILD then WatchBuild(inst) end
		QueueOwner(inst)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(QueueOwner)
end
for _, model in ipairs(CollectionService:GetTagged(TAG_BUILD)) do WatchBuild(model) end

DataService.OnProfileLoaded(function(player) task.spawn(Restore, player) end)

Players.PlayerRemoving:Connect(function(player)
	local plot = Active[player]
	Active[player] = nil
	Paused[player] = nil
	Queued[player] = nil
	if plot and plot.Parent then
		if clearPlaced then pcall(clearPlaced.Invoke, clearPlaced, plot) end
		if clearBuilds then pcall(clearBuilds.Invoke, clearBuilds, plot) end
	end
end)

task.spawn(function()
	while true do
		task.wait(HEARTBEAT)
		for player, plot in pairs(Active) do
			if plot and not Paused[player] then Snapshot(player, true) end
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
		local plot = Active[player] or PlotOf(player)
		local cleared = 0
		if plot then
			if clearPlaced then local ok, n = pcall(clearPlaced.Invoke, clearPlaced, plot) cleared += (ok and tonumber(n)) or 0 end
			if clearBuilds then local ok, n = pcall(clearBuilds.Invoke, clearBuilds, plot) cleared += (ok and tonumber(n)) or 0 end
			if clearPets then pcall(clearPets.Invoke, clearPets, plot) end
			if clearEggs then local ok, n = pcall(clearEggs.Invoke, clearEggs, plot) cleared += (ok and tonumber(n)) or 0 end
		end
		local data = DataService.GetData(player)
		if data then
			data.Base = {Version = VERSION, SavedAt = os.time(), Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}}
			DataService.RequestSave(player)
		end
		return true, cleared
	end)
	bindable("Resume", function(player)
		Paused[player] = nil
		if not Active[player] then Active[player] = PlotOf(player) end
		return Active[player] ~= nil
	end)
	--.. empty the plot and rebuild it from Data.Base as a rejoin would (the persistence test's round trip)
	bindable("Reload", function(player)
		local plot = Active[player] or PlotOf(player)
		if not plot then return false, "no plot" end
		Paused[player] = true
		Active[player] = nil
		Queued[player] = nil
		if clearPlaced then pcall(clearPlaced.Invoke, clearPlaced, plot) end
		if clearBuilds then pcall(clearBuilds.Invoke, clearBuilds, plot) end
		if clearPets then pcall(clearPets.Invoke, clearPets, plot) end
		if clearEggs then pcall(clearEggs.Invoke, clearEggs, plot) end
		task.wait(0.6) -- the tag-removed events of the clearing fire deferred; they must find nothing to snapshot
		Paused[player] = nil
		Restore(player)
		return Active[player] ~= nil
	end)
end

print("[BaseSave] placed cucumbers, builds, pets and eggs save to Data.Base and come back on rejoin")
