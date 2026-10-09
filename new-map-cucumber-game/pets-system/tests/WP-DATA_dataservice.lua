-- WP-DATA DataService: the PATCHED ServerStorage.DataService (loopback :8794) run against a fake
-- ProfileStore / Players / RunService / ServerStorage / Instance / task, so the real module (and its
-- ProfileStore) is never required. Covers CONTRACTS 4.1: migration before exposure + report, before-
-- close ordering / once-only guard / leave vs Shutdown vs External vs lost ownership, left-during-load,
-- generations, ResetProfile migration + reset callbacks, the Studio-only PetTestProfileKey, and the
-- optional-module paths (absent / require error / Migrate error). Read-only: creates no instances.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 15 then failures[#failures + 1] = name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "") end
	end
end

local function Fetch(port, file)
	return HttpService:GetAsync(("http://127.0.0.1:%d/%s?t=%s"):format(port, file, tostring(os.clock())))
end

local function DeepCopy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = DeepCopy(x) end
	return c
end

--..PetDataMigration (+ PetBalance / PetStats) from src with fake ReplicatedStorage lookups..--
local Catalog = require(ReplicatedStorage.Modules.PetsCatalog)
local deps = {PetsCatalog = Catalog}
local function Marker(name) return {__dep = name} end
local fakeModules = {}
function fakeModules:FindFirstChild(name) return deps[name] ~= nil and Marker(name) or nil end
function fakeModules:WaitForChild(name) assert(deps[name] ~= nil, "missing dep " .. name) return Marker(name) end
local fakeRS = {}
function fakeRS:FindFirstChild(name) return name == "Modules" and fakeModules or nil end
function fakeRS:WaitForChild(name) assert(name == "Modules", name) return fakeModules end
local rsGame = setmetatable({}, {__index = function(_, k)
	if k == "GetService" then
		return function(_, name)
			if name == "ReplicatedStorage" then return fakeRS end
			return game:GetService(name)
		end
	end
	return game[k]
end})
local function LoadSrc(file)
	local fn, err = loadstring(Fetch(8793, file), "=" .. file)
	assert(fn, err)
	setfenv(fn, setmetatable({
		game = rsGame,
		require = function(x)
			if type(x) == "table" and x.__dep then return deps[x.__dep] end
			return require(x)
		end,
	}, {__index = getfenv(0)}))
	return fn()
end
deps.PetBalance = LoadSrc("ReplicatedStorage.Modules.PetBalance.lua")
deps.PetStats = LoadSrc("ReplicatedStorage.Modules.PetStats.lua")
local M = LoadSrc("ServerStorage.PetDataMigration.lua")

--..fakes..--
local function Signal()
	local s = {Handlers = {}}
	function s:Connect(fn)
		table.insert(self.Handlers, fn)
		return {Disconnect = function() end}
	end
	function s:Fire(...)
		for _, fn in ipairs(table.clone(self.Handlers)) do fn(...) end
	end
	return s
end

local function ReconcileTable(target, template) -- ProfileStore's Reconcile
	for k, v in pairs(template) do
		if type(k) == "string" then
			if target[k] == nil then
				target[k] = DeepCopy(v)
			elseif type(target[k]) == "table" and type(v) == "table" then
				ReconcileTable(target[k], v)
			end
		end
	end
end

local function NewProfile(key, template, data, log)
	local p = {Key = key, Data = data, Active = true, UserIds = {}, Saves = 0,
		OnLastSave = Signal(), OnSessionEnd = Signal(), OnSave = Signal()}
	function p:AddUserId(id) table.insert(self.UserIds, id) end
	function p:Reconcile() ReconcileTable(self.Data, template) end
	function p:IsActive() return self.Active end
	function p:Save() self.Saves += 1 end
	--.. the synchronous (pre-UpdateAsync) part of SaveProfileAsync(profile, true, nil, reason)
	function p:FinalSave(reason)
		self.OnSave:Fire()
		table.insert(log, "OnLastSave:" .. reason)
		self.OnLastSave:Fire(reason)
		self.Active = false
		table.insert(log, "OnSessionEnd")
		self.OnSessionEnd:Fire()
		self.Written = DeepCopy(self.Data) -- what UpdateAsync serialises afterwards
	end
	function p:EndSession()
		if self.Active then self:FinalSave("Manual") end
	end
	return p
end

local dsSource = Fetch(8794, "ServerStorage.DataService.lua")

local function LoadDS(opts)
	opts = opts or {}
	local S = {Warns = {}, Errors = {}, Delays = {}, Requires = 0, Sessions = {}, Profiles = {}, Log = {}}
	local Players = {PlayerAdded = Signal(), PlayerRemoving = Signal(), List = {}}
	function Players:GetPlayers() return self.List end
	S.Players = Players
	local lib = {IsClosing = false}
	function lib.SetConstant() end
	function lib.New(_, template)
		S.Template = template
		local store = {}
		store.Mock = store
		function store:StartSessionAsync(key, params)
			table.insert(S.Sessions, key)
			if opts.OnStart then opts.OnStart(key, params) end
			if opts.FailLoad then return nil end
			local profile = NewProfile(key, template, DeepCopy(opts.ProfileData or {}), S.Log)
			table.insert(S.Profiles, profile)
			return profile
		end
		return store
	end
	S.Lib = lib
	local migrationMarker = {__dep = "PetDataMigration"}
	local parent = {}
	function parent:FindFirstChild(name)
		if name == "PetDataMigration" and opts.Migration ~= "absent" then return migrationMarker end
		return nil
	end
	local fakeScript = {Parent = parent, Name = "DataService"}
	function fakeScript:WaitForChild(name) return {__dep = name} end
	local attrs = opts.Attrs or {}
	local ServerStorage = {}
	function ServerStorage:GetAttribute(k) return attrs[k] end
	local RunService = {}
	function RunService:IsStudio() return opts.Studio == true end
	local fakeGame = {}
	function fakeGame:GetService(name)
		if name == "Players" then return Players end
		if name == "RunService" then return RunService end
		if name == "ServerStorage" then return ServerStorage end
		if name == "HttpService" then return HttpService end
		error("unexpected service " .. tostring(name))
	end
	local env = {
		game = fakeGame,
		script = fakeScript,
		require = function(x)
			if type(x) == "table" and x.__dep == "ProfileStore" then return lib end
			if x == migrationMarker then
				S.Requires += 1
				if opts.Migration == "requireError" then error("boom at require", 0) end
				return opts.MigrationModule or M
			end
			error("unexpected require")
		end,
		Instance = {new = function(class) return {ClassName = class, Changed = Signal(), Value = 0} end},
		task = {
			spawn = function(f, ...)
				local ok, err = pcall(f, ...)
				if not ok and err ~= "STOP_WAIT" then table.insert(S.Errors, tostring(err)) end
			end,
			delay = function(t, f) table.insert(S.Delays, {t, f}) end,
			wait = function() error("STOP_WAIT", 0) end,
		},
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
			table.insert(S.Warns, table.concat(parts, " "))
		end,
	}
	local fn, err = loadstring(dsSource, "=DataService(patched)")
	assert(fn, err)
	setfenv(fn, setmetatable(env, {__index = getfenv(0)}))
	S.DS = fn()
	return S.DS, S
end

local function NewPlayer(S, name, userId)
	local p = {Name = name, UserId = userId or 140977250, Parent = S.Players}
	function p:Kick(msg) self.Kicked = msg end
	return p
end

local function WarnHas(S, text)
	for _, w in ipairs(S.Warns) do
		if w:find(text, 1, true) then return true end
	end
	return false
end

local fixture = HttpService:JSONDecode(Fetch(8795, "WP-DATA_fixture_profile.json"))

--..A. normal load (the real legacy profile) + leave flush ordering..--
do
	local DS, S
	local probe = {}
	local wrapper = {Migrate = function(data, ctx)
		probe.Exposed = DS.GetData(probe.Player) ~= nil
		probe.Loaded = DS.IsLoaded(probe.Player)
		probe.Generation = DS.GetGeneration(probe.Player)
		probe.Ctx = ctx
		return M.Migrate(data, ctx)
	end}
	DS, S = LoadDS({ProfileData = fixture.Data, MigrationModule = wrapper})
	Check("A: template Base.Version 2", DS.Template.Base.Version == 2)
	Check("A: template has no pet schema keys", DS.Template.Base.PetSchemaVersion == nil and DS.Template.Base.PetRoster == nil)
	Check("A: new API present", type(DS.OnBeforeClose) == "function" and type(DS.IsClosing) == "function" and type(DS.GetGeneration) == "function"
		and type(DS.OnProfileReset) == "function" and type(DS.GetMigrationReport) == "function" and type(DS.ProfileKeyOf) == "function")
	local atLoad = {}
	DS.OnProfileLoaded(function(player, profile)
		atLoad.Report = DS.GetMigrationReport(player)
		atLoad.Generation = DS.GetGeneration(player)
		atLoad.Schema = profile.Data.Base.PetSchemaVersion
		atLoad.Roster = profile.Data.Base.PetRoster and #profile.Data.Base.PetRoster
	end)
	DS.Start()
	local player = NewPlayer(S, "Tester")
	probe.Player = player
	S.Players.PlayerAdded:Fire(player)
	local profile = S.Profiles[1]
	Check("A: real key", S.Sessions[1] == "Player_140977250", S.Sessions[1])
	Check("A: migration ran before exposure", probe.Exposed == false and probe.Loaded == false and probe.Generation == nil)
	Check("A: ctx", probe.Ctx and probe.Ctx.Scope == "All" and type(probe.Ctx.GenerateId) == "function"
		and #probe.Ctx.GenerateId() == 36 and type(probe.Ctx.Now) == "number")
	local report = DS.GetMigrationReport(player)
	Check("A: report stored", type(report) == "table" and report.Changed == true and report.Legacy == true and report.Failed == nil)
	Check("A: callbacks see migrated data", atLoad.Schema == 1 and atLoad.Roster == 4 and atLoad.Report == report)
	Check("A: generation set before exposure-visible", type(atLoad.Generation) == "number" and atLoad.Generation == DS.GetGeneration(player))
	Check("A: Version kept 2 + Cash kept", profile.Data.Base.Version == 2 and DS.Get(player, "Cash") == fixture.Data.Cash)
	Check("A: not closing", DS.IsClosing(player) == false)
	Check("A: no errors / warns", #S.Errors == 0 and #S.Warns == 0, S.Errors[1] or S.Warns[1])

	local order, seen = {}, {}
	local function Recorder(tag, extra)
		return function(p, prof, reason)
			table.insert(order, tag)
			seen[tag] = {Data = DS.GetData(p) ~= nil, Closing = DS.IsClosing(p), Reason = reason, Active = prof:IsActive(), Profile = prof}
			if extra then extra(p, prof, reason) end
		end
	end
	DS.OnBeforeClose(Recorder("A", function(p) DS.GetData(p).Base.FlushMark = true end), 40)
	DS.OnBeforeClose(Recorder("B"), 10)
	DS.OnBeforeClose(Recorder("C"))
	DS.OnBeforeClose(Recorder("D"), 10)
	DS.OnBeforeClose(Recorder("Err", function() error("callback boom") end), 20)
	DS.OnBeforeClose(Recorder("Late", function() DS.OnBeforeClose(function() table.insert(order, "Registered") end, 1) end), 60)
	DS.OnBeforeClose("not a function", 5)
	DS.OnBeforeClose(Recorder("NaN"), 0 / 0)
	player.Parent = nil -- Deferred signals: already nil inside PlayerRemoving
	S.Players.PlayerRemoving:Fire(player)
	Check("A: order 10,10,20,40,50,50(NaN->50),60", table.concat(order, ",") == "B,D,Err,A,C,NaN,Late", table.concat(order, ","))
	Check("A: reason Leave", seen.B and seen.B.Reason == "Leave" and seen.C.Reason == "Leave")
	Check("A: callbacks see data + closing + active profile", seen.B.Data and seen.B.Closing and seen.B.Active and seen.C.Data and seen.C.Active and seen.C.Profile == profile)
	Check("A: callback error warned, rest ran", WarnHas(S, "callback boom") and seen.C ~= nil)
	Check("A: flush written in the final save", profile.Written and profile.Written.Base.FlushMark == true)
	Check("A: OnLastSave after flush, callbacks ran once", S.Log[1] == "OnLastSave:Manual" and #order == 7)
	Check("A: forgotten", DS.GetData(player) == nil and DS.GetGeneration(player) == nil and DS.GetMigrationReport(player) == nil and DS.IsClosing(player) == false)
	Check("A: no kick on leave", player.Kicked == nil)

	--.. a second player: the callback registered during the first close runs now (no replay before)
	local gen1 = atLoad.Generation -- (the loaded callback overwrites atLoad for the second player)
	local p2 = NewPlayer(S, "Second", 2)
	S.Players.PlayerAdded:Fire(p2)
	Check("A: generations distinct + increasing", DS.GetGeneration(p2) ~= nil and DS.GetGeneration(p2) > gen1)
	order = {}
	p2.Parent = nil
	S.Players.PlayerRemoving:Fire(p2)
	Check("A: late registration runs on the next close", order[1] == "Registered" and #order == 8, table.concat(order, ","))
end

--..B. shutdown (OnLastSave "Shutdown") + later PlayerRemoving -> callbacks once..--
do
	local DS, S = LoadDS({ProfileData = fixture.Data})
	DS.Start()
	local player = NewPlayer(S, "Tester")
	S.Players.PlayerAdded:Fire(player)
	local count, reason, hadData = 0, nil, nil
	DS.OnBeforeClose(function(p, _, r)
		count += 1
		reason = r
		hadData = DS.GetData(p) ~= nil
	end, 10)
	S.Lib.IsClosing = true
	Check("B: IsClosing during ProfileStore shutdown", DS.IsClosing(player) == true)
	S.Profiles[1]:FinalSave("Shutdown")
	Check("B: ran once with Shutdown + data", count == 1 and reason == "Shutdown" and hadData == true)
	Check("B: forgotten after session end", DS.GetData(player) == nil)
	S.Players.PlayerRemoving:Fire(player)
	Check("B: PlayerRemoving afterwards is a no-op", count == 1)
	Check("B: kicked (still in game at shutdown)", player.Kicked ~= nil)
end

--..C. external takeover (OnLastSave "External"): flush once, kick..--
do
	local DS, S = LoadDS({ProfileData = fixture.Data})
	DS.Start()
	local player = NewPlayer(S, "Tester")
	S.Players.PlayerAdded:Fire(player)
	local reasons = {}
	DS.OnBeforeClose(function(_, _, r) table.insert(reasons, r) end)
	S.Profiles[1]:FinalSave("External")
	Check("C: External flush once", #reasons == 1 and reasons[1] == "External")
	Check("C: kicked with the takeover message", player.Kicked == "Your data was opened on another server. Please rejoin.")
	Check("C: forgotten", DS.GetData(player) == nil and DS.IsClosing(player) == false)
end

--..D. lost ownership (OnSessionEnd only): no flush, data gone..--
do
	local DS, S = LoadDS({ProfileData = fixture.Data})
	DS.Start()
	local player = NewPlayer(S, "Tester")
	S.Players.PlayerAdded:Fire(player)
	local count = 0
	DS.OnBeforeClose(function() count += 1 end)
	S.Profiles[1].Active = false
	S.Profiles[1].OnSessionEnd:Fire()
	Check("D: no flush on lost ownership", count == 0)
	Check("D: forgotten", DS.GetData(player) == nil and DS.GetGeneration(player) == nil and DS.GetMigrationReport(player) == nil)
	player.Parent = nil
	S.Players.PlayerRemoving:Fire(player)
	Check("D: leave afterwards no flush", count == 0)
end

--..E. player left during StartSessionAsync: migrated + ended, never exposed, no close callbacks..--
do
	local player
	local DS, S = LoadDS({ProfileData = fixture.Data, OnStart = function() player.Parent = nil end})
	local loadedCalls, count = 0, 0
	DS.OnProfileLoaded(function() loadedCalls += 1 end)
	DS.OnBeforeClose(function() count += 1 end)
	DS.Start()
	player = NewPlayer(S, "Leaver")
	S.Players.PlayerAdded:Fire(player)
	local profile = S.Profiles[1]
	Check("E: session ended", profile.Active == false and profile.Written ~= nil)
	Check("E: never exposed", DS.GetData(player) == nil and loadedCalls == 0)
	Check("E: no close callbacks", count == 0)
	Check("E: state cleared", DS.GetGeneration(player) == nil and DS.GetMigrationReport(player) == nil)
	Check("E: OnLastSave had no DataService listener", #profile.OnLastSave.Handlers == 0)
end

--..F. Studio-only isolated profile key..--
do
	local function KeyFor(opts)
		local DS, S = LoadDS(opts)
		DS.Start()
		local player = NewPlayer(S, "Tester")
		S.Players.PlayerAdded:Fire(player)
		return S.Sessions[1], DS.ProfileKeyOf(player), S
	end
	local key, keyOf, S = KeyFor({Studio = true, Attrs = {PetTestProfileKey = "PetTest"}, ProfileData = {}})
	Check("F: studio test key", key == "PetTest_140977250" and keyOf == "PetTest_140977250", key)
	Check("F: loud warn", WarnHas(S, "STUDIO TEST PROFILE: using key PetTest_140977250"))
	Check("F: live server ignores it", (KeyFor({Studio = false, Attrs = {PetTestProfileKey = "PetTest"}})) == "Player_140977250")
	Check("F: bad chars ignored", (KeyFor({Studio = true, Attrs = {PetTestProfileKey = "Pet-Test"}})) == "Player_140977250")
	Check("F: too long ignored", (KeyFor({Studio = true, Attrs = {PetTestProfileKey = string.rep("a", 41)}})) == "Player_140977250")
	Check("F: 40 chars ok", (KeyFor({Studio = true, Attrs = {PetTestProfileKey = string.rep("a", 40)}})) == string.rep("a", 40) .. "_140977250")
	Check("F: non-string ignored", (KeyFor({Studio = true, Attrs = {PetTestProfileKey = 5}})) == "Player_140977250")
	Check("F: empty ignored", (KeyFor({Studio = true, Attrs = {PetTestProfileKey = ""}})) == "Player_140977250")
	Check("F: unset", (KeyFor({Studio = true})) == "Player_140977250")
end

--..G. ResetProfile: template (Version 2) + migration + new generation + reset callbacks..--
do
	local DS, S = LoadDS({ProfileData = fixture.Data})
	DS.Start()
	local player = NewPlayer(S, "Tester")
	S.Players.PlayerAdded:Fire(player)
	local profile = S.Profiles[1]
	local gen1 = DS.GetGeneration(player)
	local oldBase = profile.Data.Base
	local calls = {}
	DS.OnProfileReset(function(p, prof)
		table.insert(calls, {Tag = "one", Player = p, Profile = prof, Gen = DS.GetGeneration(p), Schema = prof.Data.Base.PetSchemaVersion})
	end)
	DS.OnProfileReset(function() table.insert(calls, {Tag = "err"}) error("reset boom") end)
	DS.OnProfileReset(function() table.insert(calls, {Tag = "three"}) end)
	DS.OnProfileReset(42)
	local delaysBefore = #S.Delays + profile.Saves
	local ok = DS.ResetProfile(player)
	local base = profile.Data.Base
	Check("G: returns true", ok == true)
	Check("G: template data", DS.Get(player, "Cash") == 0 and base ~= oldBase and #base.Pets == 0 and #base.Builds == 0)
	Check("G: Version 2 + migrated", base.Version == 2 and base.PetSchemaVersion == 1 and type(base.PetRoster) == "table" and #base.PetRoster == 0)
	Check("G: no notice on an empty reset", base.PetNoticePending == nil)
	Check("G: template not mutated", DS.Template.Base.PetSchemaVersion == nil and DS.Template.Base.PetRoster == nil)
	local gen2 = DS.GetGeneration(player)
	Check("G: generation advanced", type(gen2) == "number" and gen2 > gen1)
	Check("G: callbacks in order, error isolated", #calls == 3 and calls[1].Tag == "one" and calls[2].Tag == "err" and calls[3].Tag == "three")
	Check("G: callback args + sees new gen/data", calls[1].Player == player and calls[1].Profile == profile and calls[1].Gen == gen2 and calls[1].Schema == 1)
	Check("G: reset error warned", WarnHas(S, "reset boom"))
	local report = DS.GetMigrationReport(player)
	Check("G: report replaced", type(report) == "table" and report.Legacy == true and report.IdsAssigned == 0 and report.Failed == nil)
	Check("G: save requested", #S.Delays + profile.Saves > delaysBefore)
	Check("G: unknown player", DS.ResetProfile(NewPlayer(S, "Nobody", 3)) == false)
end

--..H. PetDataMigration absent: skipped (not a failure), load continues..--
do
	local DS, S = LoadDS({ProfileData = fixture.Data, Migration = "absent"})
	DS.Start()
	local player = NewPlayer(S, "Tester")
	S.Players.PlayerAdded:Fire(player)
	local report = DS.GetMigrationReport(player)
	Check("H: NoModule report", report and report.Error == "NoModule" and report.Failed == nil)
	Check("H: loaded, untouched", DS.GetData(player) ~= nil and DS.GetData(player).Base.PetSchemaVersion == nil and DS.GetData(player).Base.Pets[1].Id == nil)
	Check("H: no warn", #S.Warns == 0 and S.Requires == 0)
end

--..I. require error: Failed, warned once, not re-required for the next player..--
do
	local DS, S = LoadDS({ProfileData = fixture.Data, Migration = "requireError"})
	DS.Start()
	local p1, p2 = NewPlayer(S, "One", 1), NewPlayer(S, "Two", 2)
	S.Players.PlayerAdded:Fire(p1)
	S.Players.PlayerAdded:Fire(p2)
	local r1, r2 = DS.GetMigrationReport(p1), DS.GetMigrationReport(p2)
	Check("I: Failed reports", r1 and r1.Failed == true and r1.Error == "RequireFailed" and r2 and r2.Failed == true)
	Check("I: loads continue", DS.GetData(p1) ~= nil and DS.GetData(p2) ~= nil)
	Check("I: required once, warned once", S.Requires == 1 and #S.Warns == 1 and WarnHas(S, "could not be loaded"), S.Requires .. "/" .. #S.Warns)
end

--..J. Migrate throws: Failed + warn, load continues, callbacks still run..--
do
	local DS, S = LoadDS({ProfileData = fixture.Data, MigrationModule = {Migrate = function() error("migrate boom") end}})
	local loaded = 0
	DS.OnProfileLoaded(function() loaded += 1 end)
	DS.Start()
	local player = NewPlayer(S, "Tester")
	S.Players.PlayerAdded:Fire(player)
	local r = DS.GetMigrationReport(player)
	Check("J: Failed report", r and r.Failed == true and tostring(r.Error):find("migrate boom", 1, true) ~= nil)
	Check("J: warned", WarnHas(S, "pet data migration (load) failed for Tester"))
	Check("J: exposed + callbacks", DS.GetData(player) ~= nil and loaded == 1 and DS.GetGeneration(player) ~= nil)
end

--..K. failed load kicks, nothing stored; unchanged Set/Increment/RequestSave semantics..--
do
	local DS, S = LoadDS({FailLoad = true})
	DS.Start()
	local player = NewPlayer(S, "Tester")
	S.Players.PlayerAdded:Fire(player)
	Check("K: kick message", player.Kicked == "Your data could not be loaded. Please rejoin.")
	Check("K: nothing stored", DS.GetMigrationReport(player) == nil and DS.GetGeneration(player) == nil)
	local DS2, S2 = LoadDS({ProfileData = {}})
	DS2.Start()
	local p = NewPlayer(S2, "Tester")
	S2.Players.PlayerAdded:Fire(p)
	Check("K: reconciled template profile", DS2.Get(p, "Cash") == 0 and DS2.GetData(p).Base.Version == 2 and DS2.GetData(p).Base.PetSchemaVersion == 1)
	Check("K: Set/Increment", DS2.Set(p, "Cash", 5) == true and DS2.Increment(p, "Cash", 2) == true and DS2.Get(p, "Cash") == 7)
	Check("K: values folder built", S2.Profiles[1] ~= nil and #S2.Errors == 0, S2.Errors[1])
end

local summary = ("WP-DATA dataservice: PASS %d / FAIL %d%s"):format(pass, fail, fail > 0 and (": " .. table.concat(failures, "; ")) or "")
return summary
