-- WP-SERVER behaviour test: patched ServerScriptService.BaseSaveService run in a sandbox (2026-09-22).
-- The patched source (loopback :8794) runs with fake game services / plot / bindables / DataService /
-- PetService / PetBuffService (WP-SERVER_fakes.lua, :8795). Read-only: no real Instance is created or parented.
-- Covers CONTRACTS 4.8: canonical Base carry-over, egg/cucumber ids, consumed + hatched egg filtering, KeptEggs,
-- the v1 gate before the cucumber copy, readiness (BaseRestored / WaitReady / AttachPlot), leave / reset /
-- resume / reload / IsRestored, OnBeforeClose(40), heartbeat pcall, PetService missing / not started, and (G)
-- PlotPet models no longer queue snapshots / saves.
local H = game:GetService("HttpService")
local F = loadstring(H:GetAsync("http://127.0.0.1:8795/WP-SERVER_fakes.lua"))()
local SOURCE = H:GetAsync("http://127.0.0.1:8794/ServerScriptService.BaseSaveService.server.lua")
local C = F.Checker("WP-SERVER BaseSave")
local check = C.Check

local P = {CFrame.new(0, 0, -5):GetComponents()} -- a saved pivot (anchor-local)
local PB = {CFrame.new(1, 0, -6):GetComponents()}

--.. one sandboxed server: fake world + the script loaded. opts.Pet = "started" | "idle" | "missing"
local function World(base, opts)
	opts = opts or {}
	local log, print_, warn_ = F.Logger()
	local tasks = F.Task(log)
	local cs = F.CollectionService()
	local players = F.Players()
	local serverStorage = F.Inst("ServerStorage", "ServerStorage")
	local replicated = F.Inst("ReplicatedStorage", "ReplicatedStorage")
	local modules = F.Inst("Folder", "Modules")
	modules.Parent = replicated
	F.Module("BuildCatalog", {BackZ = function(plot) return plot.Size.Z * 0.5 end}, modules)
	local ws = F.Inst("Workspace", "Workspace")
	local map = F.Inst("Folder", "Map") map.Parent = ws
	local lobby = F.Inst("Folder", "Lobby") lobby.Parent = map
	local plots = F.Inst("Folder", "Plots") plots.Parent = lobby
	local plot = F.Inst("Part", "Plot 1", {CFrame = CFrame.new(100, 0, 0), Size = Vector3.new(40, 1, 40)})
	plot.Parent = plots
	local placed = F.Inst("Folder", "Placed") placed.Parent = plot
	local player = F.Player(players, 140977250, "Tester")
	plot:SetAttribute("Owner", player.UserId)
	plot:SetAttribute("PlotLevel", 0)

	local guid = 0
	local http = {GenerateGUID = function() guid += 1 return "guid-" .. guid end}

	--.. DataService fake
	local data = {PlotLevel = 0, Base = base}
	local DS = {Saves = 0, Loaded = {}, Close = {}, GetDataError = false, Gone = false}
	function DS.GetData(p) if DS.GetDataError then error("GetData exploded") end return p == player and not DS.Gone and data or nil end
	function DS.WaitForData(p) return DS.GetData(p) end
	function DS.RequestSave() DS.Saves += 1 end
	function DS.OnProfileLoaded(cb) table.insert(DS.Loaded, cb) end
	if not opts.NoClose then -- opts.NoClose: an older DataService without the pre-close flush
		function DS.OnBeforeClose(fn, order) table.insert(DS.Close, {Fn = fn, Order = order}) end
	end
	F.Module("DataService", DS, serverStorage)

	--.. owning services' bindables (fake world side)
	local calls = {RestoreEgg = {}, RestorePlaced = {}, RestoreBuild = 0}
	local function api(folderName, fns)
		local folder = F.Inst("Folder", folderName) folder.Parent = serverStorage
		for name, fn in pairs(fns) do F.Inst("BindableFunction", name, {OnInvoke = fn}).Parent = folder end
	end
	local function clearTagged(tag)
		local n = 0
		for _, inst in ipairs(cs:GetTagged(tag)) do
			if inst:IsDescendantOf(plot) then cs:RemoveTag(inst, tag) inst:Destroy() n += 1 end
		end
		return n
	end
	local function WorldEgg(id, attrs)
		local egg = F.Inst("Model", "Egg", {Pivot = CFrame.new(100, 1, 5)})
		egg:SetAttribute("Owner", player.UserId)
		egg:SetAttribute("EggName", "Basic")
		egg:SetAttribute("EggId", id)
		for k, v in pairs(attrs or {}) do egg:SetAttribute(k, v) end
		egg.Parent = placed
		cs:AddTag(egg, "PlacedEgg")
		return egg
	end
	local function WorldCucumber(id, attrs)
		local model = F.Inst("Model", "Cuke", {Pivot = CFrame.new(100, 2, 5)})
		F.Inst("Part", "PlotHitbox", {CFrame = CFrame.new(100, 2, 5), Size = Vector3.new(2, 2, 2)}).Parent = model
		model:SetAttribute("Owner", player.UserId)
		model:SetAttribute("TypeName", "T")
		model:SetAttribute("Zone", "Spawn")
		model:SetAttribute("CucumberId", id)
		for k, v in pairs(attrs or {}) do model:SetAttribute(k, v) end
		model.Parent = placed
		cs:AddTag(model, "PlacedCucumber")
		return model
	end
	api("EggPlacementAPI", {
		RestoreEgg = function(p, pl, rec, pivot)
			table.insert(calls.RestoreEgg, rec)
			if rec.EggName == "FAIL" then return nil, "broken egg" end
			return WorldEgg(rec.Id)
		end,
		ClearEggs = function() return clearTagged("PlacedEgg") end,
	})
	api("CucumberCarryAPI", {
		RestorePlaced = function(p, pl, rec)
			table.insert(calls.RestorePlaced, rec)
			if rec.Type == "FAIL" then return nil, "broken cucumber" end
			return WorldCucumber(type(rec.Id) == "string" and rec.Id or nil, {HasBuff = rec.PetBuffs ~= nil})
		end,
		ClearPlaced = function() return clearTagged("PlacedCucumber") end,
	})
	api("BuildServiceAPI", {
		RestoreBuild = function() calls.RestoreBuild += 1 return true end,
		ClearBuilds = function() return clearTagged("PlacedBuild") end,
	})

	--.. pet modules
	local Pet = {Calls = {}, Started = opts.Pet ~= "idle"}
	function Pet.IsStarted() return Pet.Started end
	function Pet.WaitReady() table.insert(Pet.Calls, "WaitReady") return Pet.Started end
	function Pet.EnsureProfileState() table.insert(Pet.Calls, "Ensure") return true end
	function Pet.AttachPlot(p, pl) table.insert(Pet.Calls, "Attach") Pet.AttachedPlot = pl return 3 end
	function Pet.DetachPlot(p, reason) table.insert(Pet.Calls, "Detach:" .. tostring(reason)) end
	function Pet.SyncRecords(p, anchor)
		table.insert(Pet.Calls, "Sync")
		Pet.SyncAnchor = anchor
		local pets = data.Base and type(data.Base) == "table" and data.Base.Pets
		if type(pets) == "table" then for _, rec in ipairs(pets) do if type(rec) == "table" then rec.Synced = (rec.Synced or 0) + 1 end end end
	end
	if opts.Pet ~= "missing" then F.Module("PetService", Pet, serverStorage) end
	local Buff = {}
	function Buff.Serialize(model)
		if model:GetAttribute("SerializeError") then error("bad buff attrs") end
		if model:GetAttribute("HasBuff") then return {{Kind = "Yield", ExpiresAt = 99}} end
		return nil
	end
	F.Module("PetBuffService", Buff, serverStorage)

	local services = {
		Players = players, ReplicatedStorage = replicated, ServerStorage = serverStorage,
		CollectionService = cs, HttpService = http,
	}
	local game_ = {GetService = function(_, name) return services[name] or error("no fake service " .. name) end}
	local env = {
		game = game_, workspace = ws, require = F.Require, task = tasks, print = print_, warn = warn_,
		Instance = {new = function(className) return F.Inst(className, className) end},
	}
	F.Run(SOURCE, env)
	local apiFolder = serverStorage:FindFirstChild("BaseSaveAPI")
	local function Api(name, ...)
		local bindable = apiFolder:FindFirstChild(name)
		if not bindable then return "missing bindable " .. name end
		return bindable.OnInvoke(...)
	end
	return {
		Log = log, Task = tasks, Cs = cs, Players = players, Player = player, Plot = plot, Placed = placed,
		Data = data, DS = DS, Calls = calls, Pet = Pet, Api = Api, WorldEgg = WorldEgg, WorldCucumber = WorldCucumber,
		Restore = function() for _, cb in ipairs(DS.Loaded) do cb(player) end end,
		ServerStorage = serverStorage,
	}
end

local function ids(list, field)
	local out = {}
	for _, rec in ipairs(list or {}) do table.insert(out, tostring(rec[field or "Id"])) end
	return table.concat(out, ",")
end
local function count(list, pred) local n = 0 for _, v in ipairs(list or {}) do if pred(v) then n += 1 end end return n end

--..A: restore + snapshot of a migrated base..--
do
	local pets = {{Id = "pet1", Pet = "Cat", SourceEggId = "eggH", Pos = {1, 0, 2}}, {Id = "pet2", Pet = "Dog"}}
	local roster, foo = {"pet1"}, {Bar = 1}
	local base = {
		Version = 2, SavedAt = 1, Pets = pets, PetRoster = roster, PetSchemaVersion = 1, PetNoticePending = true, Foo = foo,
		Eggs = {
			{Id = "eggA", EggName = "Basic", Pivot = P},
			{Id = "eggA", EggName = "Basic", Pivot = P}, -- repeated id: dropped
			{Id = "eggH", EggName = "Basic", Pivot = P}, -- already hatched (pet1.SourceEggId): dropped
			{EggName = "Basic", Pivot = P}, -- no id: gets one
			{Id = "eggF", EggName = "FAIL", Pivot = P}, -- restore fails: KeptEggs
			{Id = "eggX", Pivot = P}, -- cannot be restored (no EggName): KeptEggs
		},
		Builds = {{Key = "Wall", Level = 1, Pivot = P}},
		Cucumbers = {
			{Id = "cuc1", Type = "A", Pivot = P, Box = PB, Size = {1, 1, 1}, PetBuffs = {{Kind = "Yield", ExpiresAt = 99}}},
			{Id = "cuc1", Type = "B", Pivot = P, Box = PB, Size = {1, 1, 1}}, -- repeated id: fresh one
			{Type = "C", Pivot = P, Box = PB, Size = {1, 1, 1}}, -- no id: fresh one
			{Id = "cucF", Type = "FAIL", Pivot = P, Box = PB, Size = {1, 1, 1}}, -- fails: Kept
		},
	}
	local liveEggs = base.Eggs
	local w = World(base)
	check("A no load errors", #w.Task.Errors == 0, w.Task.Errors[1])
	check("A OnBeforeClose order 40", #w.DS.Close == 1 and w.DS.Close[1].Order == 40)
	check("A BaseRestored unset before restore", w.Player:GetAttribute("BaseRestored") == nil)
	w.Restore()
	check("A restore ran clean", #w.Task.Errors == 0, w.Task.Errors[1])
	check("A eggs invoked: eggA, new id, eggF", ids(w.Calls.RestoreEgg) == "eggA,guid-1,eggF", ids(w.Calls.RestoreEgg))
	check("A dup + hatched removed from the live list", #liveEggs == 4 and ids(liveEggs) == "eggA,guid-1,eggF,eggX", ids(liveEggs))
	check("A dropped prints", F.Find(w.Log, "dropped egg record eggA (duplicate id)") and F.Find(w.Log, "dropped egg record eggH (already hatched)"))
	check("A builds restored", w.Calls.RestoreBuild == 1)
	local cukes = w.Calls.RestorePlaced
	check("A cucumbers invoked 4", #cukes == 4, #cukes)
	check("A first cuc1 kept its id", cukes[1] and cukes[1].Id == "cuc1")
	check("A repeated cucumber id replaced", cukes[2] and cukes[2].Id ~= "cuc1" and type(cukes[2].Id) == "string", cukes[2] and cukes[2].Id)
	check("A missing cucumber id assigned", cukes[3] and type(cukes[3].Id) == "string" and cukes[3].Id:sub(1, 5) == "guid-")
	check("A BaseRestored true", w.Player:GetAttribute("BaseRestored") == true)
	check("A pet readiness sequence", table.concat(w.Pet.Calls, ",") == "WaitReady,Ensure,Attach", table.concat(w.Pet.Calls, ","))
	check("A attach got the plot", w.Pet.AttachedPlot == w.Plot)
	check("A print counts pets from AttachPlot", F.Find(w.Log, "3 pets") ~= nil, F.Find(w.Log, "[BaseSave] Tester on"))
	check("A failed restores keep the save (no snapshot)", w.Data.Base == base)
	check("A IsRestored", w.Api("IsRestored", w.Player) == true)

	-- world extras that a snapshot must skip / keep
	w.WorldEgg("eggC", {Consumed = true}) -- consumed mid-hatch
	w.WorldEgg("eggH") -- post-grant fault: egg still in the world, its pet owned
	w.WorldEgg("eggA") -- a second world copy of eggA
	w.WorldEgg(nil) -- an egg without an id (unpatched EggPlacement)
	w.WorldCucumber("cucE", {SerializeError = true})
	local pet = F.Inst("Model", "Cat") pet:SetAttribute("Owner", w.Player.UserId) pet:SetAttribute("PetName", "Cat") pet.Parent = w.Plot
	w.Cs:AddTag(pet, "PlotPet")
	local saves = w.DS.Saves
	check("A snapshot ok", w.Api("Snapshot", w.Player) == true)
	local nb = w.Data.Base
	check("A new base table", nb ~= base and type(nb) == "table")
	check("A version 2", nb.Version == 2 and type(nb.SavedAt) == "number")
	check("A pets by reference", nb.Pets == pets and #pets == 2)
	check("A roster/schema/notice/unknown carried", nb.PetRoster == roster and nb.PetSchemaVersion == 1 and nb.PetNoticePending == true and nb.Foo == foo)
	check("A SyncRecords called during collect", w.Pet.Calls[#w.Pet.Calls] == "Sync" and pets[1].Synced == 1)
	check("A sync anchor is the back edge", w.Pet.SyncAnchor and (w.Pet.SyncAnchor.Position - Vector3.new(100, 0.5, 20)).Magnitude < 1e-6, w.Pet.SyncAnchor and tostring(w.Pet.SyncAnchor.Position))
	local eggIds = ids(nb.Eggs)
	check("A eggs = world eggA + guid-1 + unnamed + kept eggF/eggX", eggIds == "eggA,guid-1,nil,eggF,eggX", eggIds)
	check("A no consumed / hatched egg saved", not eggIds:find("eggC") and not eggIds:find("eggH"))
	check("A cucumbers have ids", count(nb.Cucumbers, function(r) return type(r.Id) == "string" end) == #nb.Cucumbers and #nb.Cucumbers == 5, #nb.Cucumbers)
	local cuc1 = nil
	for _, r in ipairs(nb.Cucumbers) do if r.Id == "cuc1" then cuc1 = r end end
	check("A buffs serialized", cuc1 and type(cuc1.PetBuffs) == "table" and cuc1.PetBuffs[1].Kind == "Yield")
	local cucE = nil
	for _, r in ipairs(nb.Cucumbers) do if r.Id == "cucE" then cucE = r end end
	check("A serialize error: saved without buffs", cucE and cucE.PetBuffs == nil)
	check("A serialize error warned", F.Find(w.Log, "Serialize failed") ~= nil)
	check("A failed cucumber kept", count(nb.Cucumbers, function(r) return r.Id == "cucF" end) == 1)
	check("A snapshot requested a save", w.DS.Saves == saves + 1)

	-- second snapshot: stable, kept records not doubled
	w.Api("Snapshot", w.Player)
	check("A second snapshot stable", ids(w.Data.Base.Eggs) == eggIds and w.Data.Base.Pets == pets)

	-- reload twice with the failing egg: KeptEggs never grows
	check("A reload ok", w.Api("Reload", w.Player) == true)
	check("A reload detached pets", table.concat(w.Pet.Calls, ","):find("Detach:Reload", 1, true) ~= nil)
	check("A reload BaseRestored again", w.Player:GetAttribute("BaseRestored") == true)
	w.Api("Reload", w.Player)
	w.Api("Snapshot", w.Player)
	local after = w.Data.Base.Eggs
	check("A eggF once after 2 reloads", count(after, function(r) return r.Id == "eggF" end) == 1, ids(after))
	check("A eggX once after 2 reloads", count(after, function(r) return r.Id == "eggX" end) == 1)
	check("A pets still by reference", w.Data.Base.Pets == pets)

	-- heartbeat: one throwing snapshot is caught, the loop lives on
	local hb = w.Task.Suspended[1]
	check("A heartbeat loop suspended", hb ~= nil and coroutine.status(hb) == "suspended")
	w.DS.GetDataError = true
	local okResume = w.Task.Resume(hb)
	w.DS.GetDataError = false
	check("A heartbeat survived an error", okResume and coroutine.status(hb) == "suspended")
	check("A heartbeat warned", F.Find(w.Log, "heartbeat snapshot failed") ~= nil)

	-- pre-close flush callback
	local beforeClose = w.Data.Base
	if w.DS.Close[1] then w.DS.Close[1].Fn(w.Player, {}, "Leave") end
	check("A OnBeforeClose snapshots", w.Data.Base ~= beforeClose and w.Data.Base.Pets == pets)

	-- leave: the teardown waits one deferred step (the flush first); then snapshot, flags, clears, detach
	local beforeLeave = w.Data.Base
	w.Players.PlayerRemoving:Fire(w.Player)
	check("A leave teardown deferred", w.Api("IsRestored", w.Player) == true and w.Player:GetAttribute("BaseRestored") == true
		and #w.Cs:GetTagged("PlacedCucumber") > 0 and w.Data.Base == beforeLeave)
	check("A one deferred teardown", w.Task.RunDeferred() == 1)
	check("A leave snapshot", w.Data.Base ~= beforeLeave)
	check("A leave clears BaseRestored", w.Player:GetAttribute("BaseRestored") == nil)
	check("A leave detaches", w.Pet.Calls[#w.Pet.Calls] == "Detach:Left")
	check("A leave clears cucumbers", #w.Cs:GetTagged("PlacedCucumber") == 0)
	check("A not restored after leave", w.Api("IsRestored", w.Player) == false)
	local afterLeave = w.Data.Base
	w.Api("Snapshot", w.Player)
	check("A snapshot refused after leave", w.Data.Base == afterLeave)
	check("A no task errors", #w.Task.Errors == 0, w.Task.Errors[1])
end

--..B: the v1 gate runs before the cucumber copy; non-table Base..--
do
	local base = {Version = 1, Pets = {}, Eggs = {}, Builds = {}, Cucumbers = {
		{Id = "c1", Type = "A", Pivot = P, Box = PB, Size = {1, 1, 1}},
		{Id = "c2", Type = "B", Pivot = P, Box = PB, Size = {1, 1, 1}},
	}}
	local w = World(base)
	w.Restore()
	check("B v1 cucumbers not restored", #w.Calls.RestorePlaced == 0, #w.Calls.RestorePlaced)
	check("B v1 drop printed", F.Find(w.Log, "dropping 2 cucumber(s) saved under base version 1") ~= nil)
	check("B post-restore snapshot to version 2", w.Data.Base ~= base and w.Data.Base.Version == 2 and #w.Data.Base.Cucumbers == 0)

	local w2 = World("garbage")
	w2.Restore()
	check("B2 non-table base still restored", w2.Player:GetAttribute("BaseRestored") == true and table.concat(w2.Pet.Calls, ","):find("Attach", 1, true) ~= nil)
	check("B2 snapshot builds a clean base", type(w2.Data.Base) == "table" and w2.Data.Base.Version == 2 and type(w2.Data.Base.Pets) == "table")
	check("B no task errors", #w.Task.Errors == 0 and #w2.Task.Errors == 0, w.Task.Errors[1] or w2.Task.Errors[1])
end

--..C: admin reset + resume..--
do
	local w = World({Version = 2, Pets = {{Id = "p"}}, PetRoster = {"p"}, PetSchemaVersion = 1, Eggs = {}, Builds = {}, Cucumbers = {}})
	w.Restore()
	w.Pet.Calls = {}
	local ok = w.Api("Reset", w.Player)
	local b = w.Data.Base
	check("C reset ok", ok == true)
	check("C reset base shape", b.Version == 2 and #b.Pets == 0 and #b.Eggs == 0 and #b.Cucumbers == 0 and #b.Builds == 0
		and type(b.PetRoster) == "table" and #b.PetRoster == 0 and b.PetSchemaVersion == 1 and type(b.SavedAt) == "number")
	check("C reset clears BaseRestored", w.Player:GetAttribute("BaseRestored") == nil)
	check("C reset detaches", table.concat(w.Pet.Calls, ",") == "Detach:Reset", table.concat(w.Pet.Calls, ","))
	check("C paused after reset", w.Api("IsRestored", w.Player) == false)
	w.Pet.Calls = {}
	check("C resume ok", w.Api("Resume", w.Player) == true)
	check("C resume BaseRestored", w.Player:GetAttribute("BaseRestored") == true)
	check("C resume ensure + attach (no wait)", table.concat(w.Pet.Calls, ",") == "Ensure,Attach", table.concat(w.Pet.Calls, ","))
	check("C restored after resume", w.Api("IsRestored", w.Player) == true)
end

--..D: PetService not started / missing..--
do
	local pets = {{Id = "p1", Pet = "Cat"}}
	local w = World({Version = 2, Pets = pets, PetRoster = {"p1"}, Eggs = {}, Builds = {}, Cucumbers = {}}, {Pet = "idle"})
	w.Restore()
	check("D idle: BaseRestored still set", w.Player:GetAttribute("BaseRestored") == true)
	check("D idle: only WaitReady", table.concat(w.Pet.Calls, ",") == "WaitReady", table.concat(w.Pet.Calls, ","))
	w.Api("Snapshot", w.Player)
	check("D idle: no sync, pets carried", w.Data.Base.Pets == pets and #w.Pet.Calls == 1)
	w.Api("Reset", w.Player)
	w.Api("Resume", w.Player)
	check("D idle: detach always, no ensure/attach", table.concat(w.Pet.Calls, ",") == "WaitReady,Detach:Reset", table.concat(w.Pet.Calls, ","))

	local pets2 = {{Id = "p1", Pet = "Cat"}}
	local roster2 = {"p1"}
	local w2 = World({Version = 2, Pets = pets2, PetRoster = roster2, Eggs = {}, Builds = {}, Cucumbers = {}}, {Pet = "missing"})
	w2.Restore()
	check("D missing: BaseRestored", w2.Player:GetAttribute("BaseRestored") == true)
	w2.Api("Snapshot", w2.Player)
	check("D missing: pets + roster carried", w2.Data.Base.Pets == pets2 and w2.Data.Base.PetRoster == roster2)
	w2.Players.PlayerRemoving:Fire(w2.Player)
	w2.Task.RunDeferred()
	check("D no task errors", #w.Task.Errors == 0 and #w2.Task.Errors == 0, w.Task.Errors[1] or w2.Task.Errors[1])
	check("D no warnings about PetService", not F.Find(w2.Log, "PetService."))
end

--..E: leave during a raid, BaseSave's PlayerRemoving fires BEFORE DataService's flush (review finding)..--
do
	local w = World({Version = 2, Pets = {}, PetRoster = {}, PetSchemaVersion = 1, Eggs = {}, Builds = {}, Cucumbers = {
		{Id = "home", Type = "A", Pivot = P, Box = PB, Size = {1, 1, 1}},
	}})
	w.Restore()
	check("E restored", w.Api("IsRestored", w.Player) == true and #w.Cs:GetTagged("PlacedCucumber") == 1)
	w.Pet.Calls = {}
	local saved = w.Data.Base
	-- 1) BaseSave's handler first: nothing torn down, nothing snapshotted yet
	w.Players.PlayerRemoving:Fire(w.Player)
	check("E handler first: plot intact", #w.Cs:GetTagged("PlacedCucumber") == 1 and w.Data.Base == saved)
	check("E handler first: still restored", w.Api("IsRestored", w.Player) == true and w.Player:GetAttribute("BaseRestored") == true)
	check("E handler first: no detach yet", #w.Pet.Calls == 0, table.concat(w.Pet.Calls, ","))
	-- 2) DataService's RunBeforeClose: order 35 sends the carried cucumber home, then order 40 snapshots
	w.WorldCucumber("carried")
	w.DS.Close[1].Fn(w.Player, {}, "Leave")
	local flushed = w.Data.Base
	check("E flush snapshot taken", flushed ~= saved)
	check("E flush saved both cucumbers", ids(flushed.Cucumbers) == "home,carried", ids(flushed.Cucumbers))
	-- 3) EndSession + Forget, then the deferred teardown: snapshot refused, plot emptied, pets detached
	w.DS.Gone = true
	check("E one deferred teardown", w.Task.RunDeferred() == 1)
	check("E final base = the flush", w.Data.Base == flushed)
	check("E cleared", #w.Cs:GetTagged("PlacedCucumber") == 0 and w.Player:GetAttribute("BaseRestored") == nil)
	-- Sync = the flush's Collect; the refused leave snapshot adds none
	check("E detached Left", table.concat(w.Pet.Calls, ",") == "Sync,Detach:Left", table.concat(w.Pet.Calls, ","))
	check("E not restored after", w.Api("IsRestored", w.Player) == false)
	check("E no task errors", #w.Task.Errors == 0, w.Task.Errors[1])
end

--..F: an older DataService without OnBeforeClose: the leave stays synchronous (snapshot before the final save)..--
do
	local w = World({Version = 2, Pets = {}, Eggs = {}, Builds = {}, Cucumbers = {
		{Id = "home", Type = "A", Pivot = P, Box = PB, Size = {1, 1, 1}},
	}}, {NoClose = true})
	w.Restore()
	check("F no flush registered", #w.DS.Close == 0)
	w.WorldCucumber("late")
	local saved = w.Data.Base
	w.Players.PlayerRemoving:Fire(w.Player)
	check("F nothing deferred", #w.Task.Deferred == 0)
	check("F leave snapshot synchronous", w.Data.Base ~= saved and ids(w.Data.Base.Cucumbers) == "home,late", ids(w.Data.Base.Cucumbers))
	check("F cleared synchronously", #w.Cs:GetTagged("PlacedCucumber") == 0 and w.Pet.Calls[#w.Pet.Calls] == "Detach:Left")
	check("F no task errors", #w.Task.Errors == 0, w.Task.Errors[1])
end

--..G: pet models are no snapshot trigger (seam fix); eggs / cucumbers / builds still are..--
do
	local w = World({Version = 2, Pets = {{Id = "p1", Pet = "Cat"}}, PetRoster = {"p1"}, PetSchemaVersion = 1, Eggs = {}, Builds = {}, Cucumbers = {}})
	w.Restore()
	w.Task.RunDelayed() -- whatever the restore itself queued
	local saves = w.DS.Saves
	local pet = F.Inst("Model", "Cat") pet:SetAttribute("Owner", w.Player.UserId) pet:SetAttribute("PetName", "Cat") pet.Parent = w.Plot
	w.Cs:AddTag(pet, "PlotPet")
	check("G pet spawn queues no snapshot", #w.Task.Delayed == 0, #w.Task.Delayed)
	w.Cs:RemoveTag(pet, "PlotPet")
	check("G pet despawn queues no snapshot", #w.Task.Delayed == 0, #w.Task.Delayed)
	local stray = F.Inst("Model", "Stray") stray.Parent = w.Plot -- no Owner: would have refreshed every active player
	w.Cs:AddTag(stray, "PlotPet")
	check("G ownerless pet model queues nothing", #w.Task.Delayed == 0, #w.Task.Delayed)
	check("G no save requested by pet models", w.DS.Saves == saves, w.DS.Saves - saves)
	w.WorldEgg("eggN")
	check("G an egg still queues one snapshot", #w.Task.Delayed == 1, #w.Task.Delayed)
	w.Task.RunDelayed()
	check("G that snapshot asked for one save", w.DS.Saves == saves + 1, w.DS.Saves - saves)
	check("G pets still carried by reference", type(w.Data.Base.Pets) == "table" and w.Data.Base.Pets[1] and w.Data.Base.Pets[1].Id == "p1")
	check("G no task errors", #w.Task.Errors == 0, w.Task.Errors[1])
end

return C.Summary()
