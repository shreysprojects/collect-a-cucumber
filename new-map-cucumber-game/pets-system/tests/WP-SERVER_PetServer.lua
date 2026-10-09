-- WP-SERVER behaviour test: ServerScriptService.PetServer run in a sandbox (2026-09-22).
-- The source (loopback :8793) runs against fake services and fake pet modules that record their calls
-- (WP-SERVER_fakes.lua, :8795). Read-only: no real Instance is created or parented.
-- Covers CONTRACTS 3.9 / 10.3: remotes, require / Init / Start order and deps, failure isolation, config check,
-- request routing + the rate-limited "Unavailable" reply, OnProfileLoaded, PetDiag, PetServerSkipIncome, PetDev.
local H = game:GetService("HttpService")
local F = loadstring(H:GetAsync("http://127.0.0.1:8795/WP-SERVER_fakes.lua"))()
local SOURCE = H:GetAsync("http://127.0.0.1:8793/ServerScriptService.PetServer.server.lua")
local C = F.Checker("WP-SERVER PetServer")
local check = C.Check
local ORDER = {"PetEffectsBus", "IncomeService", "PetBuffService", "PetService", "PetCombatService"}

--.. opts: Missing = {name = true}, RequireError / InitError / StartError / NeverStarted = name, Studio (default true),
--.. SkipIncome = bool, Problems = n, HandleError = bool
local function Server(opts)
	opts = opts or {}
	local log, print_, warn_ = F.Logger()
	local tasks = F.Task(log)
	local cs = F.CollectionService()
	local players = F.Players()
	local serverStorage = F.Inst("ServerStorage", "ServerStorage")
	local replicated = F.Inst("ReplicatedStorage", "ReplicatedStorage")
	local modulesFolder = F.Inst("Folder", "Modules") modulesFolder.Parent = replicated
	local ws = F.Inst("Workspace", "Workspace")
	rawset(ws, "GetServerTimeNow", function() return 5000 end)
	if opts.SkipIncome then ws:SetAttribute("PetServerSkipIncome", true) end
	local clock = {Now = 100}
	local fakeOs = setmetatable({clock = function() return clock.Now end}, {__index = os})
	local player = F.Player(players, 140977250, "Tester")

	--.. ReplicatedStorage.Modules
	local problems = {}
	for i = 1, opts.Problems or 0 do problems[i] = "problem " .. i end
	F.Module("PetBalance", {Validate = function(catalog) return catalog.IsCatalog and problems or {"wrong catalog"} end}, modulesFolder)
	F.Module("PetsCatalog", {IsCatalog = true}, modulesFolder)
	F.Module("PetStats", {EggOf = function(key) if key == "Cat" then return "Basic Egg", 1, 1 end return nil end}, modulesFolder)

	--.. DataService
	local record = {Id = "pA", Pet = "Cat", AbilityRemaining = 40}
	local data = {Base = {Pets = {record}}}
	local DS = {Saves = 0, Loaded = {}}
	function DS.GetData(p) return p == player and data or nil end
	function DS.RequestSave() DS.Saves += 1 end
	function DS.OnProfileLoaded(cb) table.insert(DS.Loaded, cb) end
	function DS.GetGeneration() return 7 end
	F.Module("DataService", DS, serverStorage)

	--.. pet modules (recording fakes)
	local order, mods = {}, {}
	for _, name in ipairs(ORDER) do
		local m = {Name = name, Started = false, Calls = {}}
		m.Init = function(deps)
			table.insert(order, name .. ".Init")
			m.Deps = deps
			if opts.InitError == name then error("init boom") end
		end
		m.Start = function()
			table.insert(order, name .. ".Start")
			if opts.StartError == name then error("start boom") end
			m.Started = opts.NeverStarted ~= name
		end
		m.IsStarted = function() return m.Started end
		m.GetDiagnostics = function() return {Count = 1, Bad = 0 / 0, Nested = {A = 2}} end
		mods[name] = m
		if not (opts.Missing and opts.Missing[name]) then
			if opts.RequireError == name then
				F.Module(name, function() error("require boom") end, serverStorage)
			else
				F.Module(name, m, serverStorage)
			end
		end
	end
	local Pet, Buff = mods.PetService, mods.PetBuffService
	function Buff.ModifiersOf() return {} end
	function Buff.Grant(p, source, ability) table.insert(Buff.Calls, {"Grant", source, ability}) return true, {Kind = ability, CucumberId = "c1", ExpiresAt = 1} end
	function Buff.ClearCucumber(model, reason) table.insert(Buff.Calls, {"Clear", model, reason}) end
	function Pet.HandleRequest(p, request)
		if opts.HandleError then error("handler boom") end
		table.insert(Pet.Calls, {"HandleRequest", p, request})
	end
	function Pet.EnsureProfileState(p) table.insert(Pet.Calls, {"Ensure", p}) return true end
	function Pet.GrantFromEgg(p, egg, key) table.insert(Pet.Calls, {"Grant", egg, key}) return {Id = "new1", Pet = key}, {Equipped = true, Reserve = false, AutoEquipAfterCombat = false} end
	function Pet.FinishPresentation(p, id, spot, generation) table.insert(Pet.Calls, {"Finish", id, spot, generation}) return true end
	function Pet.Equip(p, id) table.insert(Pet.Calls, {"Equip", id}) return true end
	function Pet.Unequip(p, id) table.insert(Pet.Calls, {"Unequip", id}) return true end
	function Pet.EquipBest(p, mode) table.insert(Pet.Calls, {"Best", mode}) return true end
	function Pet.GetFullState()
		return {Pets = {{Id = "pA", Pet = "Cat", DisplayName = "Cat", Status = "Active", Stats = {Ability = "Yield"}}, {Id = "pF", Pet = "Bunny", Stats = {Ability = "None"}}},
			EquippedIds = {"pA"}, CombatLocked = false, Revision = 3}
	end
	function Pet.GetLogicalPosition() return Vector3.new(1, 2, 3) end

	--.. BaseSaveAPI.Reload
	local reloads = {}
	local baseApi = F.Inst("Folder", "BaseSaveAPI") baseApi.Parent = serverStorage
	F.Inst("BindableFunction", "Reload", {OnInvoke = function(p) table.insert(reloads, p) return true end}).Parent = baseApi

	local runService = {IsStudio = function() return opts.Studio ~= false end, Heartbeat = F.Signal()}
	local http = {
		GenerateGUID = function() return "guid" end,
		JSONEncode = function(_, value) return H:JSONEncode(value) end,
	}
	local services = {
		Players = players, ReplicatedStorage = replicated, ServerStorage = serverStorage, RunService = runService,
		HttpService = http, CollectionService = cs,
	}
	local env = {
		game = {GetService = function(_, name) return services[name] or error("no fake service " .. name) end},
		workspace = ws, require = F.Require, task = tasks, print = print_, warn = warn_, os = fakeOs,
		Instance = {new = function(className) return F.Inst(className, className) end},
	}
	local okRun, runErr = pcall(F.Run, SOURCE, env)
	local remotes = replicated:FindFirstChild("Remotes")
	return {
		Ok = okRun, Err = runErr, Log = log, Task = tasks, Cs = cs, Player = player, Ws = ws, Clock = clock,
		Order = order, Mods = mods, DS = DS, Record = record, Reloads = reloads, ServerStorage = serverStorage,
		Remotes = remotes, PetRequest = remotes and remotes:FindFirstChild("PetRequest"), PetState = remotes and remotes:FindFirstChild("PetState"),
		Dev = function(command) ws:SetAttribute("PetDev", command) end,
		Diag = function()
			local co = tasks.Suspended[1]
			if co then tasks.Resume(co) end
			local json = serverStorage:GetAttribute("PetDiag")
			return json and H:JSONDecode(json) or nil
		end,
	}
end

local function lastSent(remote)
	local sent = remote and rawget(remote, "Sent")
	return sent and sent[#sent] or nil
end
local function sentCount(remote)
	local sent = remote and rawget(remote, "Sent")
	return sent and #sent or 0
end

--..1: full stack..--
do
	local s = Server({Problems = 12})
	check("1 script ran", s.Ok, s.Err)
	check("1 no task errors", #s.Task.Errors == 0, s.Task.Errors[1])
	check("1 remotes", s.PetRequest and s.PetRequest.ClassName == "RemoteEvent" and s.PetState and s.PetState.ClassName == "RemoteEvent")
	local expected = {}
	for _, n in ipairs(ORDER) do table.insert(expected, n .. ".Init") end
	for _, n in ipairs(ORDER) do table.insert(expected, n .. ".Start") end
	check("1 init/start order", table.concat(s.Order, ",") == table.concat(expected, ","), table.concat(s.Order, ","))
	local m = s.Mods
	check("1 bus deps", type(m.PetEffectsBus.Deps) == "table" and next(m.PetEffectsBus.Deps) == nil)
	check("1 income deps", m.IncomeService.Deps.DataService ~= nil and m.IncomeService.Deps.ModifiersOf == m.PetBuffService.ModifiersOf)
	check("1 buff deps", m.PetBuffService.Deps.IncomeService == m.IncomeService and m.PetBuffService.Deps.Effects == m.PetEffectsBus)
	local pd = m.PetService.Deps
	check("1 pet deps", pd.DataService ~= nil and pd.IncomeService == m.IncomeService and pd.PetBuffService == m.PetBuffService
		and pd.Effects == m.PetEffectsBus and type(pd.SendState) == "function")
	check("1 combat deps", m.PetCombatService.Deps.PetService == m.PetService and m.PetCombatService.Deps.Effects == m.PetEffectsBus)
	pd.SendState(s.Player, {Kind = "Full"})
	local sent = lastSent(s.PetState)
	check("1 SendState fires PetState to the player", sent and sent.Player == s.Player and sent.Args[1].Kind == "Full")
	local warns = 0
	for _, line in ipairs(s.Log) do if line:find("WARN [PetServer] config: ", 1, true) then warns += 1 end end
	check("1 config warns capped at 10", warns == 10, warns)
	check("1 ensure registered", #s.DS.Loaded == 1)
	if s.DS.Loaded[1] then s.DS.Loaded[1](s.Player) end
	check("1 ensure called", m.PetService.Calls[1] and m.PetService.Calls[1][1] == "Ensure")
	local request = {RequestId = "r1", Action = "Equip", PetId = "pA"}
	local before = sentCount(s.PetState)
	s.PetRequest.OnServerEvent:Fire(s.Player, request)
	local call = m.PetService.Calls[#m.PetService.Calls]
	check("1 request routed", call[1] == "HandleRequest" and call[2] == s.Player and call[3] == request)
	check("1 no unavailable reply", sentCount(s.PetState) == before)
	local diag = s.Diag()
	check("1 diag published", type(diag) == "table")
	check("1 diag keys", diag and diag.Pet and diag.Income and diag.Buff and diag.Combat and diag.Fx and true or false)
	check("1 diag config problems", diag and diag.ConfigProblems == 12)
	check("1 diag NaN sanitised", diag and diag.Pet.Bad == 0 and diag.Pet.Count == 1 and diag.Pet.Nested.A == 2)
	check("1 diag module states", diag and diag.Modules.PetService == "Started" and diag.Modules.PetCombatService == "Started")
	check("1 diag loop lives on", s.Task.Suspended[1] and coroutine.status(s.Task.Suspended[1]) == "suspended")
	check("1 ready print", F.Find(s.Log, "[PetServer] PetEffectsBus Started, IncomeService Started") ~= nil)

	--.. PetDev
	local pet, buff = m.PetService, m.PetBuffService
	local saves = s.DS.Saves
	s.Dev("grant:Cat:Golden:NEON,VOID")
	check("dev cleared", s.Ws:GetAttribute("PetDev") == nil)
	local grant, finish = pet.Calls[#pet.Calls - 1], pet.Calls[#pet.Calls]
	check("dev grant call", grant and grant[1] == "Grant" and grant[3] == "Cat" and grant[2].EggName == "Basic"
		and grant[2].Material == "Golden" and grant[2].Mutations == "NEON,VOID" and grant[2].EggId == nil)
	check("dev grant saved", s.DS.Saves == saves + 1)
	check("dev grant finished at once", finish and finish[1] == "Finish" and finish[2] == "new1" and finish[4] == 7)
	check("dev grant print", F.Find(s.Log, "granted a SAVED pet Cat") ~= nil)
	s.Dev("grant:Treasure Gem::SHADOW")
	grant = pet.Calls[#pet.Calls - 1]
	check("dev grant spaces + empty material", grant[3] == "Treasure Gem" and grant[2].Material == nil and grant[2].Mutations == "SHADOW" and grant[2].EggName == "Dev")
	s.Dev("equip:pA") check("dev equip", pet.Calls[#pet.Calls][1] == "Equip" and pet.Calls[#pet.Calls][2] == "pA")
	s.Dev("unequip:pA") check("dev unequip", pet.Calls[#pet.Calls][1] == "Unequip")
	s.Dev("best:Combat") check("dev best", pet.Calls[#pet.Calls][1] == "Best" and pet.Calls[#pet.Calls][2] == "Combat")
	local n = #pet.Calls
	s.Dev("best:Speed") check("dev best refuses bad mode", #pet.Calls == n)
	s.Dev("roll:pA") check("dev roll arms the countdown", s.Record.AbilityRemaining == 0.1)
	s.Dev("proc:pA")
	local g = buff.Calls[#buff.Calls]
	check("dev proc grants with the pet as source", g and g[1] == "Grant" and g[3] == "Yield" and g[2].PetId == "pA" and g[2].DisplayName == "Cat" and g[2].From == Vector3.new(1, 2, 3))
	local b = #buff.Calls
	s.Dev("proc:pF") check("dev proc refuses a fighter", #buff.Calls == b)
	-- PetService's own Studio helpers win when present
	function pet.DevSetAbilityRemaining(p, id, seconds) table.insert(pet.Calls, {"DevSet", id, seconds}) return true end
	function pet.DevForceProc(p, id) table.insert(pet.Calls, {"DevForce", id}) return true end
	s.Record.AbilityRemaining = 40
	s.Dev("roll:pA")
	check("dev roll via DevSetAbilityRemaining", pet.Calls[#pet.Calls][1] == "DevSet" and pet.Calls[#pet.Calls][3] == 0.1 and s.Record.AbilityRemaining == 40)
	b = #buff.Calls
	s.Dev("proc:pA")
	check("dev proc via DevForceProc", pet.Calls[#pet.Calls][1] == "DevForce" and pet.Calls[#pet.Calls][2] == "pA" and #buff.Calls == b)
	s.Dev("buff:Guard")
	g = buff.Calls[#buff.Calls]
	check("dev buff", g and g[3] == "Guard" and g[2].PetId == "Dev" and g[2].DisplayName == "Dev")
	b = #buff.Calls
	s.Dev("buff:Wild") check("dev buff refuses Wild", #buff.Calls == b)
	for i, owner in ipairs({140977250, 140977250, 1}) do
		local model = F.Inst("Model", "Cuke" .. i) model:SetAttribute("Owner", owner) model.Parent = s.Ws
		s.Cs:AddTag(model, "PlacedCucumber")
	end
	b = #buff.Calls
	s.Dev("clearbuffs")
	check("dev clearbuffs only own cucumbers", #buff.Calls == b + 2 and buff.Calls[#buff.Calls][3] == "Dev")
	s.Dev("state")
	check("dev state prints", F.Find(s.Log, "PetDev: PetDiag {") ~= nil and F.Find(s.Log, "owns 2 pet(s), equipped [pA]") ~= nil)
	s.Dev("reload") check("dev reload", #s.Reloads == 1 and s.Reloads[1] == s.Player)
	s.Dev("nonsense") check("dev unknown", F.Find(s.Log, "PetDev: unknown command nonsense") ~= nil)
	check("dev no task errors", #s.Task.Errors == 0, s.Task.Errors[1])
end

--..2: PetService missing -> Unavailable replies (rate-limited), combat skipped..--
do
	local s = Server({Missing = {PetService = true}})
	check("2 ran", s.Ok, s.Err)
	check("2 combat skipped", not table.concat(s.Order, ","):find("PetCombatService", 1, true), table.concat(s.Order, ","))
	check("2 no ensure hook", #s.DS.Loaded == 0)
	s.PetRequest.OnServerEvent:Fire(s.Player, {RequestId = "r1", Action = "Equip", PetId = "pA"})
	local sent = lastSent(s.PetState)
	local p = sent and sent.Args[1]
	check("2 unavailable reply", p and p.Kind == "Delta" and p.Revision == 0 and p.BaseRevision == 0 and p.RequestId == "r1"
		and p.Result.Ok == false and p.Result.Error == "Unavailable" and p.Result.Action == "Equip" and p.ServerTime == 5000)
	s.PetRequest.OnServerEvent:Fire(s.Player, {RequestId = "r2", Action = "GetState"})
	check("2 second reply within 1 s dropped", sentCount(s.PetState) == 1)
	s.Clock.Now += 1.01
	s.PetRequest.OnServerEvent:Fire(s.Player, "garbage")
	p = lastSent(s.PetState) and lastSent(s.PetState).Args[1]
	check("2 reply after 1 s, garbage request", sentCount(s.PetState) == 2 and p.RequestId == nil and p.Result.Action == "nil")
	s.Clock.Now += 2
	s.PetRequest.OnServerEvent:Fire(s.Player, {RequestId = string.rep("x", 41), Action = string.rep("A", 500)})
	p = lastSent(s.PetState).Args[1]
	check("2 oversized fields trimmed", p.RequestId == nil and #p.Result.Action == 40)
	s.Dev("grant:Cat")
	check("2 dev reports unavailable", F.Find(s.Log, "PetDev: PetService unavailable") ~= nil)
	local diag = s.Diag()
	check("2 diag states", diag and diag.Modules.PetService == "Missing" and diag.Modules.PetCombatService == "Skipped" and diag.Pet == nil)
	check("2 no task errors", #s.Task.Errors == 0, s.Task.Errors[1])
end

--..3: PetServerSkipIncome (Studio) and non-Studio..--
do
	local s = Server({SkipIncome = true})
	check("3 income not init/started", not table.concat(s.Order, ","):find("IncomeService", 1, true))
	check("3 dependents get nil income", s.Mods.PetBuffService.Deps.IncomeService == nil and s.Mods.PetService.Deps.IncomeService == nil)
	check("3 skip warned", F.Find(s.Log, "PetServerSkipIncome is set") ~= nil)
	local diag = s.Diag()
	check("3 diag skipped", diag and diag.Modules.IncomeService == "Skipped" and diag.Income == nil)

	local live = Server({SkipIncome = true, Studio = false})
	check("3 live server ignores the skip flag", table.concat(live.Order, ","):find("IncomeService.Start", 1, true) ~= nil)
	live.Dev("equip:pA")
	check("3 live server has no PetDev hook", live.Ws:GetAttribute("PetDev") == "equip:pA" and #live.Mods.PetService.Calls == 0)
end

--..4: failure isolation..--
do
	local s = Server({InitError = "PetBuffService"})
	check("4 init error: not started", not table.concat(s.Order, ","):find("PetBuffService.Start", 1, true))
	check("4 init error: not handed on", s.Mods.PetService.Deps.PetBuffService == nil)
	check("4 init error: rest started", s.Mods.PetService.Started and s.Mods.PetCombatService.Started and s.Mods.IncomeService.Started)
	check("4 init error: ModifiersOf still given to income", s.Mods.IncomeService.Deps.ModifiersOf == s.Mods.PetBuffService.ModifiersOf)
	check("4 init error warned", F.Find(s.Log, "PetBuffService.Init failed") ~= nil)
	local diag = s.Diag()
	check("4 diag InitFailed", diag and diag.Modules.PetBuffService == "InitFailed")

	local s2 = Server({StartError = "IncomeService"})
	check("4 start error: later modules start", s2.Mods.PetService.Started and s2.Mods.PetCombatService.Started)
	check("4 start error: status", s2.Diag().Modules.IncomeService == "StartFailed")

	local s3 = Server({RequireError = "PetEffectsBus"})
	check("4 require error: no effects dep", s3.Mods.PetService.Deps.Effects == nil and s3.Mods.PetCombatService.Deps.Effects == nil)
	check("4 require error: status", s3.Diag().Modules.PetEffectsBus == "RequireFailed")

	local s4 = Server({NeverStarted = "PetService"})
	check("4 not started: no ensure hook", #s4.DS.Loaded == 0)
	s4.PetRequest.OnServerEvent:Fire(s4.Player, {RequestId = "r", Action = "GetState"})
	check("4 not started: unavailable", sentCount(s4.PetState) == 1 and #s4.Mods.PetService.Calls == 0)
	--.. seam fix: Start returned quietly without starting -> "NotStarted" (diag + ready print + warn), not "Started"
	check("4 not started: diag NotStarted", s4.Diag().Modules.PetService == "NotStarted")
	check("4 not started: ready print", F.Find(s4.Log, "PetService NotStarted, PetCombatService Started") ~= nil)
	check("4 not started: warned", F.Find(s4.Log, "PetService.Start returned but the module is not started") ~= nil)
	local s6 = Server({NeverStarted = "PetBuffService"})
	local diag6 = s6.Diag()
	check("4 buff not started: status", diag6 and diag6.Modules.PetBuffService == "NotStarted" and diag6.Modules.PetService == "Started")
	check("4 buff not started: later modules still start", s6.Mods.PetService.Started and s6.Mods.PetCombatService.Started)

	local s5 = Server({HandleError = true})
	s5.PetRequest.OnServerEvent:Fire(s5.Player, {RequestId = "r", Action = "Unequip", PetId = "pA"})
	check("4 handler error: unavailable reply + warn", sentCount(s5.PetState) == 1 and F.Find(s5.Log, "HandleRequest failed") ~= nil)
	check("4 no task errors", #s.Task.Errors + #s2.Task.Errors + #s3.Task.Errors + #s4.Task.Errors + #s5.Task.Errors + #s6.Task.Errors == 0)
end

return C.Summary()
