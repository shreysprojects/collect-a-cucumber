--[[
	PetServer  (Script, ServerScriptService)  2026-09-22
	Bootstrap of the pet system (pets-system/CONTRACTS.md 3.9; PLAN section 9 "Dependency/startup rules").
	No gameplay of its own: no formulas, no Cash writes, no record edits - it wires the ServerStorage
	modules together, in this order, every step pcall-isolated (a module that is missing or fails is
	warned about loudly and skipped; the rest still start):
	  1. find-or-create ReplicatedStorage.Remotes + RemoteEvents PetRequest (client -> server) and
	     PetState (server -> owner).
	  2. require IncomeService, PetEffectsBus, PetBuffService, PetService, PetCombatService (each
	     optional - ServerStorage content exists before any Script runs, so nothing is waited for) and
	     DataService (required).
	  2b. PetBalance.Validate(PetsCatalog): up to 10 config problems are warned, the count goes into PetDiag;
	     the bootstrap never aborts on them.
	  3. Init: PetEffectsBus -> IncomeService (ModifiersOf = PetBuffService.ModifiersOf) -> PetBuffService ->
	     PetService (SendState = PetState:FireClient) -> PetCombatService. A module whose Init failed is not
	     handed to the ones after it.
	  4. Start in the same order. A module counts as "Started" only when its IsStarted() says so after Start
	     returned ("NotStarted" when Start returned quietly without starting, "StartFailed" when it threw).
	  5. PetRequest -> PetService.HandleRequest (pcall). While PetService is missing / not started every
	     request gets {Kind = "Delta", Result = {Ok = false, Error = "Unavailable"}} (at most 1/s per player,
	     the rest dropped).
	  6. DataService.OnProfileLoaded -> PetService.EnsureProfileState (only when PetService started).
	  7. every 10 s: ServerStorage attribute PetDiag = JSON {Pet, Income, Buff, Combat, Fx, ConfigProblems,
	     Modules} (each module's GetDiagnostics in pcall).
	Income never depends on this script: LeaderstatsService keeps a latched legacy pay loop that starts if
	IncomeService has not started 10 s after it (OD-21).

	Studio test hooks (RunService:IsStudio() only; workspace attributes, cleared first; "first player" =
	Players:GetPlayers()[1]; every branch checks the module it needs and runs in pcall):
	  * PetDev = "grant:<PetKey>" | "grant:<PetKey>:<Material>" | "grant:<PetKey>:<Material>:<MUT,MUT>"
	             saved dev grant through PetService.GrantFromEgg (a REAL owned pet; reserve unless a slot is
	             free and unlocked), shown at once (no reveal); leave Material empty for normal ("Cat::NEON")
	           | "equip:<PetId>" | "unequip:<PetId>" | "best:Income" | "best:Combat"
	           | "roll:<PetId>"   that pet's ability countdown -> 0.1 s (PetService.DevSetAbilityRemaining; its
	                              next roll comes on the next tick)
	           | "proc:<PetId>"   its next roll is forced to succeed (PetService.DevForceProc; without it, a
	                              successful roll right now: PetBuffService.Grant with that pet as the source)
	           | "buff:<Yield|Haste|Guard>"  grant on a random eligible cucumber, source "Dev"
	           | "clearbuffs"     every buff on the first player's cucumbers
	           | "state"          print the diagnostics + the first player's roster
	           | "reload"         BaseSaveAPI.Reload (pets detach and re-attach from the same records)
	  * PetServerSkipIncome = true (set in EDIT mode before the playtest; read once here): IncomeService is
	    neither Init'ed nor Started and its dependents get nil - tests LeaderstatsService's legacy fallback.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

--..Config..--
local DIAG_PERIOD = 10 -- seconds between PetDiag writes
local UNAVAILABLE_GAP = 1 -- seconds between two "Unavailable" replies to one player
local MAX_CONFIG_WARNINGS = 10
local WARN_INTERVAL = 60 -- seconds between two warns of the same kind
local MODULE_ORDER = {"PetEffectsBus", "IncomeService", "PetBuffService", "PetService", "PetCombatService"}
local DIAG_KEYS = {PetService = "Pet", IncomeService = "Income", PetBuffService = "Buff", PetCombatService = "Combat", PetEffectsBus = "Fx"}
local BUFF_KINDS = {Yield = true, Haste = true, Guard = true}
local BEST_MODES = {Income = true, Combat = true}

--..State..--
local Modules = {} -- [name] = module table (only the ones that required)
local Status = {} -- [name] = "Missing" | "RequireFailed" | "Skipped" | "InitFailed" | "StartFailed" | "NotStarted" | "Started"
local LastWarn = {}
local LastUnavailable = {} -- [player] = os.clock() of the last "Unavailable" reply
local ConfigProblems = 0

--..Helpers..--
local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function WarnOnce(key, message)
	local now = os.clock()
	if LastWarn[key] and now - LastWarn[key] < WARN_INTERVAL then return end
	LastWarn[key] = now
	warn(message)
end

local function IsStarted(module)
	if type(module) ~= "table" or type(module.IsStarted) ~= "function" then return false end
	local ok, started = pcall(module.IsStarted)
	return ok and started == true
end

--.. the module when it is present AND started, else nil
local function Live(name)
	local module = Modules[name]
	if module and IsStarted(module) then return module end
	return nil
end

--..1. Remotes..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local function remote(className, name)
	local r = Remotes:FindFirstChild(name)
	if r and not r:IsA(className) then
		warn(("[PetServer] Remotes.%s is a %s, expected a %s"):format(name, r.ClassName, className))
	end
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
local PetRequest = remote("RemoteEvent", "PetRequest")
local PetState = remote("RemoteEvent", "PetState")

--..2. Modules..--
local DataService = require(ServerStorage:WaitForChild("DataService"))

local function Load(name)
	local module = ServerStorage:FindFirstChild(name)
	if not module then
		print(("[PetServer] %s is not installed - skipped"):format(name))
		Status[name] = "Missing"
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok or type(result) ~= "table" then
		warn(("[PetServer] %s failed to load - skipped: %s"):format(name, tostring(ok and "not a table" or result)))
		Status[name] = "RequireFailed"
		return nil
	end
	return result
end
for _, name in ipairs(MODULE_ORDER) do Modules[name] = Load(name) end

--..2b. Config check (a new catalog key warns, never crashes)..--
do
	local ok, err = pcall(function()
		local folder = ReplicatedStorage:WaitForChild("Modules", 10)
		local balanceModule = folder and folder:FindFirstChild("PetBalance")
		local catalogModule = folder and folder:FindFirstChild("PetsCatalog")
		if not balanceModule or not catalogModule then
			print("[PetServer] PetBalance / PetsCatalog not installed - config check skipped")
			return
		end
		local PetBalance, PetsCatalog = require(balanceModule), require(catalogModule)
		local problems = PetBalance.Validate(PetsCatalog)
		problems = type(problems) == "table" and problems or {}
		ConfigProblems = #problems
		for i = 1, math.min(#problems, MAX_CONFIG_WARNINGS) do
			warn("[PetServer] config: " .. tostring(problems[i]))
		end
	end)
	if not ok then
		ConfigProblems = ConfigProblems + 1
		warn("[PetServer] config check failed: " .. tostring(err))
	end
end

--..3. Init..--
local SkipIncome = RunService:IsStudio() and workspace:GetAttribute("PetServerSkipIncome") == true
if SkipIncome and Modules.IncomeService then
	warn("[PetServer] STUDIO: PetServerSkipIncome is set - IncomeService is not started (legacy income fallback test)")
	Modules.IncomeService = nil
	Status.IncomeService = "Skipped"
end

local Ready = {} -- [name] = module whose Init succeeded (handed to the modules after it)
local function InitModule(name, deps)
	local module = Modules[name]
	if not module then return end
	local ok, err = pcall(module.Init, deps)
	if ok then
		Ready[name] = module
	else
		warn(("[PetServer] %s.Init failed - skipped: %s"):format(name, tostring(err)))
		Status[name] = "InitFailed"
	end
end

local function SendState(player, payload)
	local ok, err = pcall(PetState.FireClient, PetState, player, payload)
	if not ok then WarnOnce("sendstate", "[PetServer] PetState:FireClient failed: " .. tostring(err)) end
end

InitModule("PetEffectsBus", {})
InitModule("IncomeService", {
	DataService = DataService,
	ModifiersOf = Modules.PetBuffService and Modules.PetBuffService.ModifiersOf or nil,
})
InitModule("PetBuffService", {
	IncomeService = Ready.IncomeService,
	Effects = Ready.PetEffectsBus,
})
InitModule("PetService", {
	DataService = DataService,
	IncomeService = Ready.IncomeService,
	PetBuffService = Ready.PetBuffService,
	Effects = Ready.PetEffectsBus,
	SendState = SendState,
})
if Modules.PetCombatService and not Ready.PetService then
	warn("[PetServer] PetCombatService skipped: PetService is unavailable")
	Status.PetCombatService = "Skipped"
else
	InitModule("PetCombatService", {
		PetService = Ready.PetService,
		Effects = Ready.PetEffectsBus,
	})
end

--..4. Start (same order)..--
for _, name in ipairs(MODULE_ORDER) do
	local module = Ready[name]
	if module then
		local ok, err = pcall(module.Start)
		if ok and IsStarted(module) then
			Status[name] = "Started"
		elseif ok then
			--.. Start returned without throwing but did not start (it caught its own error or lacked a dependency)
			warn(("[PetServer] %s.Start returned but the module is not started (see its own warning)"):format(name))
			Status[name] = "NotStarted"
		else
			warn(("[PetServer] %s.Start failed: %s"):format(name, tostring(err)))
			Status[name] = "StartFailed"
		end
	end
end

--..5. Requests..--
local function ReplyUnavailable(player, request)
	local now = os.clock()
	if LastUnavailable[player] and now - LastUnavailable[player] < UNAVAILABLE_GAP then return end -- dropped
	LastUnavailable[player] = now
	local action = type(request) == "table" and request.Action or nil
	local requestId = type(request) == "table" and request.RequestId or nil
	SendState(player, {
		Kind = "Delta", Revision = 0, BaseRevision = 0,
		RequestId = type(requestId) == "string" and #requestId <= 40 and requestId or nil,
		Result = {Ok = false, Error = "Unavailable", Action = tostring(action):sub(1, 40)},
		ServerTime = workspace:GetServerTimeNow(),
	})
end

PetRequest.OnServerEvent:Connect(function(player, request)
	local petService = Live("PetService")
	if petService then
		local ok, err = pcall(petService.HandleRequest, player, request)
		if ok then return end
		WarnOnce("request", "[PetServer] PetService.HandleRequest failed: " .. tostring(err))
	end
	ReplyUnavailable(player, request)
end)

Players.PlayerRemoving:Connect(function(player)
	LastUnavailable[player] = nil
end)

--..6. Profile state on load..--
if Live("PetService") then
	local PetService = Modules.PetService
	DataService.OnProfileLoaded(function(player)
		local ok, result, reason = pcall(PetService.EnsureProfileState, player)
		if not ok then
			WarnOnce("ensure", "[PetServer] EnsureProfileState: " .. tostring(result))
		elseif result == false and reason == "MigrationFailed" then
			WarnOnce("migration", ("[PetServer] %s: pet data migration failed - pets are inert this session (records untouched)"):format(player.Name))
		end
	end)
end

--..7. Diagnostics..--
--.. JSON-safe copy: finite numbers, strings, booleans and one level of nested tables
local function Sanitize(value, depth)
	if type(value) == "number" then return Finite(value) and value or 0 end
	if type(value) == "string" or type(value) == "boolean" then return value end
	if type(value) ~= "table" or depth > 2 then return nil end
	local copy = {}
	for key, item in pairs(value) do
		if type(key) == "string" then copy[key] = Sanitize(item, depth + 1) end
	end
	return copy
end

local function BuildDiag()
	local diag = {ConfigProblems = ConfigProblems, Modules = {}}
	for _, name in ipairs(MODULE_ORDER) do
		diag.Modules[name] = Status[name] or "Missing"
		local module = Modules[name]
		if module and type(module.GetDiagnostics) == "function" then
			local ok, result = pcall(module.GetDiagnostics)
			diag[DIAG_KEYS[name]] = ok and Sanitize(result, 1) or {Error = tostring(result)}
		end
	end
	return diag
end

local function PublishDiag()
	local ok, json = pcall(HttpService.JSONEncode, HttpService, BuildDiag())
	if ok then
		ServerStorage:SetAttribute("PetDiag", json)
	else
		WarnOnce("diag", "[PetServer] PetDiag encode failed: " .. tostring(json))
	end
	return ok and json or nil
end

task.spawn(function()
	while true do
		task.wait(DIAG_PERIOD)
		PublishDiag()
	end
end)

--..8. Studio test hook: workspace.PetDev..--
local function Need(name)
	local module = Live(name)
	if not module then print(("PetDev: %s unavailable"):format(name)) end
	return module
end

--.. the canonical record of one owned pet (read only here)
local function RecordOf(player, petId)
	local data = DataService.GetData(player)
	local pets = data and type(data.Base) == "table" and data.Base.Pets
	if type(pets) ~= "table" then return nil end
	for _, rec in ipairs(pets) do
		if type(rec) == "table" and rec.Id == petId then return rec end
	end
	return nil
end

local function ViewOf(PetService, player, petId)
	local state = PetService.GetFullState(player)
	for _, view in ipairs(type(state) == "table" and type(state.Pets) == "table" and state.Pets or {}) do
		if type(view) == "table" and view.Id == petId then return view end
	end
	return nil
end

--.. "Cat" -> "Basic" (the short egg name EggInfo carries, like a placed egg's EggName attribute)
local function ShortEggName(petKey)
	local folder = ReplicatedStorage:FindFirstChild("Modules")
	local module = folder and folder:FindFirstChild("PetStats")
	if not module then return "Dev" end
	local okRequire, PetStats = pcall(require, module)
	if not okRequire or type(PetStats) ~= "table" or type(PetStats.EggOf) ~= "function" then return "Dev" end
	local ok, eggKey = pcall(PetStats.EggOf, petKey)
	return ok and type(eggKey) == "string" and (eggKey:gsub("%s*Egg$", "")) or "Dev"
end

local function Dev(command)
	local verb, rest = command:match("^(%w+):?(.*)$")
	local player = Players:GetPlayers()[1]
	if not verb then print("PetDev: bad command " .. command) return end
	if not player and verb ~= "state" then print("PetDev: no player") return end

	if verb == "grant" then
		local PetService = Need("PetService")
		if not PetService then return end
		local petKey, material, mutations = rest:match("^([^:]+):?([^:]*):?(.*)$")
		if not petKey then print("PetDev: grant:<PetKey>:<Material>:<MUT,MUT> (the last two optional)") return end
		local egg = {EggId = nil, EggName = ShortEggName(petKey), Material = material ~= "" and material or nil, Mutations = mutations ~= "" and mutations or nil}
		local record, info = PetService.GrantFromEgg(player, egg, petKey)
		if not record then
			print(("PetDev: grant %s refused: %s"):format(petKey, tostring(type(info) == "table" and info.Error or info)))
			return
		end
		DataService.RequestSave(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local generation = type(DataService.GetGeneration) == "function" and DataService.GetGeneration(player) or nil
		PetService.FinishPresentation(player, record.Id, root and root.Position or nil, generation)
		info = type(info) == "table" and info or {}
		print(("PetDev: granted a SAVED pet %s (%s) id %s - equipped %s, reserve %s, auto-equip after combat %s")
			:format(petKey, egg.EggName, tostring(record.Id), tostring(info.Equipped), tostring(info.Reserve), tostring(info.AutoEquipAfterCombat)))
	elseif verb == "equip" or verb == "unequip" then
		local PetService = Need("PetService")
		if not PetService then return end
		local ok, err = (verb == "equip" and PetService.Equip or PetService.Unequip)(player, rest)
		print(("PetDev: %s %s -> %s %s"):format(verb, rest, tostring(ok), tostring(err or "")))
	elseif verb == "best" then
		local PetService = Need("PetService")
		if not PetService then return end
		if not BEST_MODES[rest] then print("PetDev: best:Income | best:Combat") return end
		local ok, err = PetService.EquipBest(player, rest)
		print(("PetDev: best %s -> %s %s"):format(rest, tostring(ok), tostring(err or "")))
	elseif verb == "roll" then
		local PetService = Need("PetService")
		if not PetService then return end
		local armed
		if type(PetService.DevSetAbilityRemaining) == "function" then
			armed = PetService.DevSetAbilityRemaining(player, rest, 0.1) == true
		else
			local rec = RecordOf(player, rest) -- older PetService: the countdown lives on the record
			if rec then rec.AbilityRemaining = 0.1 end
			armed = rec ~= nil
		end
		local view = ViewOf(PetService, player, rest)
		print(("PetDev: roll %s %s (status %s, ability %s; only Active pets count down)"):format(rest, armed and "armed" or "NOT armed (no such pet)",
			tostring(view and view.Status), tostring(view and view.Stats and view.Stats.Ability)))
	elseif verb == "proc" then
		local PetService = Need("PetService")
		if not PetService then return end
		local view = ViewOf(PetService, player, rest)
		local ability = view and type(view.Stats) == "table" and view.Stats.Ability
		if not view then print("PetDev: proc - no owned pet " .. rest) return end
		if type(ability) ~= "string" or ability == "None" then print("PetDev: proc - " .. rest .. " is a fighter (no ability)") return end
		if type(PetService.DevForceProc) == "function" then
			local ok = PetService.DevForceProc(player, rest)
			print(("PetDev: proc %s (%s) -> next roll forced: %s (roll:%s rolls it now)"):format(rest, ability, tostring(ok), rest))
			return
		end
		--.. older PetService without DevForceProc: the successful roll happens now, with the pet as the source
		local PetBuffService = Need("PetBuffService")
		if not PetBuffService then return end
		local source = {PetId = rest, DisplayName = tostring(view.DisplayName or view.Pet), From = PetService.GetLogicalPosition(rest)}
		local ok, detail = PetBuffService.Grant(player, source, ability)
		print(("PetDev: proc %s (%s) -> %s %s"):format(rest, ability, tostring(ok), type(detail) == "table" and tostring(detail.Kind) .. " until " .. tostring(detail.ExpiresAt) or tostring(detail)))
	elseif verb == "buff" then
		local PetBuffService = Need("PetBuffService")
		if not PetBuffService then return end
		if not BUFF_KINDS[rest] then print("PetDev: buff:Yield | buff:Haste | buff:Guard") return end
		local ok, detail = PetBuffService.Grant(player, {PetId = "Dev", DisplayName = "Dev"}, rest)
		print(("PetDev: buff %s -> %s %s"):format(rest, tostring(ok), type(detail) == "table" and tostring(detail.CucumberId) .. " until " .. tostring(detail.ExpiresAt) or tostring(detail)))
	elseif verb == "clearbuffs" then
		local PetBuffService = Need("PetBuffService")
		if not PetBuffService then return end
		local cleared = 0
		for _, model in ipairs(CollectionService:GetTagged("PlacedCucumber")) do
			if model:IsA("Model") and model:GetAttribute("Owner") == player.UserId then
				local ok = pcall(PetBuffService.ClearCucumber, model, "Dev")
				if ok then cleared += 1 end
			end
		end
		print(("PetDev: cleared buffs on %d cucumber(s)"):format(cleared))
	elseif verb == "state" then
		local json = PublishDiag()
		print("PetDev: PetDiag " .. tostring(json))
		local PetService = Live("PetService")
		if PetService and player then
			local state = PetService.GetFullState(player)
			if type(state) == "table" then
				print(("PetDev: %s owns %d pet(s), equipped [%s], combat locked %s, revision %s")
					:format(player.Name, type(state.Pets) == "table" and #state.Pets or 0,
						table.concat(type(state.EquippedIds) == "table" and state.EquippedIds or {}, ", "),
						tostring(state.CombatLocked), tostring(state.Revision)))
			end
		end
	elseif verb == "reload" then
		local api = ServerStorage:FindFirstChild("BaseSaveAPI")
		local reload = api and api:FindFirstChild("Reload")
		if not reload then print("PetDev: BaseSaveAPI unavailable") return end
		print("PetDev: reload -> " .. tostring(reload:Invoke(player)))
	else
		print("PetDev: unknown command " .. command)
	end
end

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("PetDev"):Connect(function()
		local command = workspace:GetAttribute("PetDev")
		if type(command) ~= "string" or command == "" then return end
		workspace:SetAttribute("PetDev", nil) -- edge-triggered
		task.spawn(function()
			local ok, err = pcall(Dev, command)
			if not ok then warn("[PetServer] PetDev " .. command .. " failed: " .. tostring(err)) end
		end)
	end)
end

local summary = {}
for _, name in ipairs(MODULE_ORDER) do table.insert(summary, name .. " " .. (Status[name] or "Missing")) end
print("[PetServer] " .. table.concat(summary, ", ") .. (ConfigProblems > 0 and (" - " .. ConfigProblems .. " config problem(s)") or ""))
