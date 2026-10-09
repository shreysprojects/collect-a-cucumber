--[[
	PetCombatService  (ModuleScript, ServerStorage)  2026-09-22
	Active pets shoot their OWNER's zombies (pets-system/CONTRACTS.md 3.8, PLAN section 6).

	One shared scan every COMBAT_SCAN (0.2 s, a Heartbeat accumulator: a hitch runs ONE scan, never a
	queue of them) asks ServerStorage.ZombieAPI.TargetInfos once (fallback while that bindable is
	missing: ZombieAPI.Zombies + the zombie's Owner / State attributes, Carrying = State "Carry", no
	grapple info) and groups the list by the zombie's Owner (the raided / thief-targeted player's
	UserId). Then every pet from PetService.GetActivePets():
	  - stands at PetService.GetLogicalPosition (the server roam segment, never the model pivot, which
	    does not move on the server: PetRoamClient animates the pets);
	  - looks only at zombies whose Owner is its owner's UserId and whose FLAT (XZ) distance is within
	    Stats.Range (pets stand on the plot top, zombie roots are ~3 studs up);
	  - keeps its current target while it stays valid unless a higher-priority one is in range:
	    carrying a cucumber (3) > grappling one (2) > the nearest (1);
	  - fires once its own deadline has passed. The deadline is advanced FIRST
	    (Core.NextShot = max(prev + interval, now + interval - scan): the long-run cadence holds the
	    nominal ShotInterval despite the 0.2 s quantisation, at most one shot per scan, no burst after
	    a hitch) and THEN ZombieAPI.Damage:Invoke(zombie, Stats.ShotDamage, "Pet") runs, with exactly
	    three arguments (no attacker: a pet never turns a raid hostile). One shot consumes one
	    cooldown even when Damage refuses it; only an accepted shot emits a PetEffectsBus "Shot".
	A newly active pet, or one that finds a target after having none, fires on that same scan unless
	the cooldown of its last shot is still running. A zombie killed by an earlier pet of the same scan
	is not shot again. Deadlines / targets of pets that are no longer active are forgotten, but only when
	the pet list was actually read: a GetActivePets that errors or returns a non-table skips the whole
	scan (counted in Errors) and keeps every deadline, so a failed read can never reset cooldowns into a
	second shot.
	ZombieRaidService destroys and rebuilds ZombieAPI when it starts: the folder is looked up again
	whenever the cached one lost its Parent. Damage stays the last authority (dead / shaded /
	underground zombies are refused there).

	Never: candidates from anything but ZombieAPI (no Humanoid / spatial scans, no guardians), a 4th
	Damage argument, touching pet models or Cash, damage from a client message.

	Use (ServerScriptService.PetServer):
		PetCombatService.Init({PetService = PetService, Effects = PetEffectsBus}) -- Clock optional (os.clock)
		PetCombatService.Start()
	GetDiagnostics(): Shots (accepted), Rejected (invalid damage or refused by Damage), DamageDealt,
	Scans, and Fallback (scans on the Zombies() fallback), NoApi, InvalidStats (pets with unusable
	range / interval, once per activation), Errors, StuckScans.
	Core (pure, unit tests): Priority, ChooseTarget, NextShot, StepAccumulator, NormalizeInfos,
	FallbackInfos, GroupByOwner, ShotEvent, CallDamage, ReadPets, NewState, RunScan.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

--..Pure helpers..--
local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function IsValidId(id)
	return type(id) == "string" and #id >= 1 and #id <= 64
end

local function ValidVector(v)
	return typeof(v) == "Vector3" and Finite(v.X) and Finite(v.Y) and Finite(v.Z)
end

--..Modules..--
local function LoadBalance() -- optional at require time (the loopback unit tests load this file before PetBalance exists)
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local module = modules and modules:FindFirstChild("PetBalance")
	if not module then return nil end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then return result end
	return nil
end
local PetBalance = LoadBalance()

--..Config..--
local TIMING = PetBalance and type(PetBalance.TIMING) == "table" and PetBalance.TIMING or {}
local FX = PetBalance and type(PetBalance.FX) == "table" and PetBalance.FX or {}
local SCAN = (Finite(TIMING.COMBAT_SCAN) and TIMING.COMBAT_SCAN > 0) and TIMING.COMBAT_SCAN or 0.2
local MUZZLE_HEIGHT = Finite(FX.MUZZLE_HEIGHT) and FX.MUZZLE_HEIGHT or 1.5 -- shot origin above the pet's ground point
local ZOMBIE_API = "ZombieAPI" -- ServerStorage.<this> (ZombieCatalog.API)
local API_MEMBERS = {"Damage", "Zombies", "TargetInfos"}
local DAMAGE_SOURCE = "Pet"
local FALLBACK_RARITY = "Common"
local STUCK_SECONDS = 5 -- a scan still running after this long (a yielding Invoke) is reported
local WARN_GAP = 60 -- one warn per reason per minute

--..Core (pure: no Instances touched, no state of its own)..--
local Core = {}
Core.Finite = Finite
Core.IsValidId = IsValidId
Core.SCAN = SCAN
Core.MUZZLE_HEIGHT = MUZZLE_HEIGHT
Core.DAMAGE_SOURCE = DAMAGE_SOURCE

function Core.FlatDistance(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- 3 = carrying one of the owner's cucumbers, 2 = grappling one, 1 = anything else
function Core.Priority(info)
	if type(info) ~= "table" then return 1 end
	if info.Carrying == true then return 3 end
	if info.Grappling == true then return 2 end
	return 1
end

-- the best in-range candidate (priority, then flat distance); the current target is kept while it is
-- in range unless a strictly higher-priority candidate is in range too
function Core.ChooseTarget(petPos, range, candidates, current)
	if not ValidVector(petPos) or not Finite(range) or range <= 0 or type(candidates) ~= "table" then return nil end
	local best, bestPriority, bestDistance
	local kept, keptPriority
	for _, info in ipairs(candidates) do
		if type(info) == "table" and info.Model ~= nil and ValidVector(info.Position) then
			local distance = Core.FlatDistance(petPos, info.Position)
			if distance <= range then
				local priority = Core.Priority(info)
				if current ~= nil and info.Model == current then kept, keptPriority = info, priority end
				if not best or priority > bestPriority or (priority == bestPriority and distance < bestDistance) then
					best, bestPriority, bestDistance = info, priority, distance
				end
			end
		end
	end
	if kept and bestPriority <= keptPriority then return kept end
	return best
end

-- next deadline after a shot due at `prev` fired on the scan at `now`
function Core.NextShot(prev, now, interval, scan)
	if not Finite(scan) or scan < 0 then scan = 0 end
	if not Finite(prev) then prev = now end
	return math.max(prev + interval, now + interval - scan)
end

-- Heartbeat accumulator: returns the new accumulator and whether a scan is due (one at most)
function Core.StepAccumulator(acc, dt, scan)
	if not Finite(acc) or acc < 0 then acc = 0 end
	if not Finite(dt) or dt < 0 then dt = 0 end
	acc += dt
	if acc < scan then return acc, false end
	acc -= scan
	if acc >= scan then acc = 0 end -- a hitch runs one scan, not a burst of them
	return acc, true
end

-- validates a ZombieAPI.TargetInfos result (CONTRACTS 7.5); isModel(model) -> boolean is optional
function Core.NormalizeInfos(raw, isModel)
	local list = {}
	if type(raw) ~= "table" then return list end
	for _, info in ipairs(raw) do
		if type(info) == "table" and info.Model ~= nil and (not isModel or isModel(info.Model))
			and Finite(info.Owner) and ValidVector(info.Position)
			and not (Finite(info.Health) and info.Health <= 0) then
			table.insert(list, info)
		end
	end
	return list
end

-- TargetInfos built from a ZombieAPI.Zombies() list + attributes (used while TargetInfos is missing).
-- read = {Attribute = fn(model, name), Position = fn(model) -> Vector3?, Health = fn(model) -> number?, number? (optional),
--         IsModel = fn(model) -> boolean (optional)}
function Core.FallbackInfos(models, read)
	local list = {}
	if type(models) ~= "table" or type(read) ~= "table" or type(read.Attribute) ~= "function" or type(read.Position) ~= "function" then return list end
	for _, model in ipairs(models) do
		if model ~= nil and (not read.IsModel or read.IsModel(model)) then
			local attr = read.Attribute
			if attr(model, "Dead") ~= true and attr(model, "Shaded") ~= true and attr(model, "Underground") ~= true then
				local owner, state, position = attr(model, "Owner"), attr(model, "State"), read.Position(model)
				local health, maxHealth
				if read.Health then health, maxHealth = read.Health(model) end
				if Finite(owner) and ValidVector(position) and not (Finite(health) and health <= 0) then
					state = type(state) == "string" and state or nil
					table.insert(list, {
						Model = model, Owner = owner, State = state,
						Carrying = state == "Carry", Grappling = false, Digging = false, Day = false,
						Health = Finite(health) and health or nil, MaxHealth = Finite(maxHealth) and maxHealth or nil,
						Position = position,
					})
				end
			end
		end
	end
	return list
end

function Core.GroupByOwner(infos)
	local groups = {}
	if type(infos) ~= "table" then return groups end
	for _, info in ipairs(infos) do
		if type(info) == "table" and Finite(info.Owner) then
			local list = groups[info.Owner]
			if not list then
				list = {}
				groups[info.Owner] = list
			end
			table.insert(list, info)
		end
	end
	return groups
end

-- the PetEffects "Shot" record (CONTRACTS 7.3) and the point it is emitted from
function Core.ShotEvent(pet, target, amount, groundPos, muzzle)
	local from = groundPos + Vector3.new(0, Finite(muzzle) and muzzle or MUZZLE_HEIGHT, 0)
	local stats = type(pet.Stats) == "table" and pet.Stats or {}
	return {
		Kind = "Shot", PetId = pet.PetId, From = from, To = target.Position, Zombie = target.Model,
		Rarity = type(stats.Rarity) == "string" and stats.Rarity or FALLBACK_RARITY, Damage = amount,
	}, from
end

-- ZombieAPI.Damage with EXACTLY three arguments (a 4th Player argument would turn the raid hostile).
-- Returns accepted: boolean, healthLeft: number?, err: string?
function Core.CallDamage(damageFn, model, amount)
	local ok, accepted, health = pcall(damageFn.Invoke, damageFn, model, amount, DAMAGE_SOURCE)
	if not ok then return false, nil, tostring(accepted) end
	return accepted == true, health, nil
end

-- PetService.GetActivePets() -> pets: table?, err: string? (nil pets = the list could not be read)
function Core.ReadPets(petService)
	local fn = type(petService) == "table" and petService.GetActivePets or nil
	if type(fn) ~= "function" then return nil, "GetActivePets missing" end
	local ok, pets = pcall(fn)
	if not ok then return nil, tostring(pets) end
	if type(pets) ~= "table" then return nil, "GetActivePets returned a " .. typeof(pets) end
	return pets, nil
end

function Core.NewState()
	return {
		NextShot = {}, -- [petId] = deadline (Clock time)
		Target = {},   -- [petId] = zombie Model
		Invalid = {},  -- [petId] = true while its stats are unusable (counted once)
		Diag = {Shots = 0, Rejected = 0, DamageDealt = 0, Scans = 0, Fallback = 0, NoApi = 0, InvalidStats = 0, Errors = 0, StuckScans = 0},
	}
end

-- One scan. ctx = {Now = number, Pets = {ActivePet}, Infos = {TargetInfo} (normalized),
--   PositionOf = fn(petId) -> Vector3?, Damage = fn(model, amount) -> accepted, healthLeft?,
--   Emit = fn(event, owner, position)? , Scan = number?, Muzzle = number?}
-- Returns the number of accepted shots. Pets that is not a table (an unread list) changes nothing: the
-- deadlines / targets are pruned only against a list that was really read.
function Core.RunScan(state, ctx)
	if type(ctx.Pets) ~= "table" then return 0 end
	local now = ctx.Now
	local scan = Finite(ctx.Scan) and ctx.Scan or SCAN
	local diag = state.Diag
	diag.Scans += 1
	local groups = Core.GroupByOwner(ctx.Infos)
	local seen = {}
	local fired = 0
	for _, pet in ipairs(ctx.Pets) do
		local petId = type(pet) == "table" and pet.PetId or nil
		if not IsValidId(petId) or seen[petId] then continue end
		seen[petId] = true
		local stats = pet.Stats
		local range = type(stats) == "table" and stats.Range or nil
		local interval = type(stats) == "table" and stats.ShotInterval or nil
		if type(stats) ~= "table" or stats.Valid == false or not Finite(range) or range <= 0 or not Finite(interval) or interval <= 0 then
			if not state.Invalid[petId] then
				state.Invalid[petId] = true
				diag.InvalidStats += 1
			end
			state.Target[petId] = nil
			continue
		end
		state.Invalid[petId] = nil
		if state.NextShot[petId] == nil then state.NextShot[petId] = now end -- newly active: fires on the first scan with a target
		local candidates = Finite(pet.UserId) and groups[pet.UserId] or nil
		local pos = candidates and ctx.PositionOf(petId) or nil
		local target = candidates and ValidVector(pos) and Core.ChooseTarget(pos, range, candidates, state.Target[petId]) or nil
		if not target then
			state.Target[petId] = nil
			continue
		end
		if state.Target[petId] == nil and state.NextShot[petId] < now then
			state.NextShot[petId] = now -- a target after having none: fire on this scan (a running cooldown is kept)
		end
		state.Target[petId] = target.Model
		local deadline = state.NextShot[petId]
		if now < deadline then continue end
		-- revalidate right before the call: still in this scan's list (kills of this scan are removed) and in range
		if not table.find(candidates, target) or Core.FlatDistance(pos, target.Position) > range then continue end
		state.NextShot[petId] = Core.NextShot(deadline, now, interval, scan) -- consumed BEFORE Damage: a yielding Invoke can never cause a second hit
		local amount = stats.ShotDamage
		if not Finite(amount) or amount <= 0 then
			diag.Rejected += 1
			continue
		end
		local accepted, health = ctx.Damage(target.Model, amount)
		if accepted then
			fired += 1
			diag.Shots += 1
			diag.DamageDealt += amount
			if Finite(health) and health <= 0 then
				local index = table.find(candidates, target)
				if index then table.remove(candidates, index) end
			end
			if ctx.Emit then
				local owner = typeof(pet.Player) == "Instance" and pet.Player or pet.UserId
				local event, from = Core.ShotEvent(pet, target, amount, pos, ctx.Muzzle)
				ctx.Emit(event, owner, from)
			end
		else
			diag.Rejected += 1
		end
	end
	for id in pairs(state.NextShot) do
		if not seen[id] then state.NextShot[id] = nil end
	end
	for id in pairs(state.Target) do
		if not seen[id] then state.Target[id] = nil end
	end
	for id in pairs(state.Invalid) do
		if not seen[id] then state.Invalid[id] = nil end
	end
	return fired
end

--..State..--
local PetCombatService = {}
PetCombatService.Core = Core

local Deps = nil -- {PetService, Effects}
local Clock = os.clock
local Started, StartOk = false, false
local State = Core.NewState()
local Api = {Folder = nil, Damage = nil, Zombies = nil, TargetInfos = nil}
local Accumulator = 0
local Scanning, ScanStartedAt, StuckCounted = false, 0, false
local LastWarn = {}

--..Helpers..--
local function WarnOnce(key, message)
	local now = os.clock()
	local last = LastWarn[key]
	if last and now - last < WARN_GAP then return end
	LastWarn[key] = now
	warn(message)
end

local function IsLiveModel(model)
	return typeof(model) == "Instance" and model:IsA("Model") and model.Parent ~= nil
end

local LiveRead = {
	IsModel = IsLiveModel,
	Attribute = function(model, name)
		return model:GetAttribute(name)
	end,
	Position = function(model)
		local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		if root and root:IsA("BasePart") then return root.Position end
		return nil
	end,
	Health = function(model)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then return humanoid.Health, humanoid.MaxHealth end
		return nil, nil
	end,
}

-- (re)binds ServerStorage.ZombieAPI; true when Damage and a target list are available
local function ResolveApi()
	if not (Api.Folder and Api.Folder.Parent == ServerStorage) then
		Api.Folder, Api.Damage, Api.Zombies, Api.TargetInfos = nil, nil, nil, nil
		local folder = ServerStorage:FindFirstChild(ZOMBIE_API)
		if not folder then return false end
		Api.Folder = folder
	end
	local folder = Api.Folder
	for _, name in ipairs(API_MEMBERS) do
		local fn = Api[name]
		if not (fn and fn.Parent == folder) then
			local found = folder:FindFirstChild(name)
			if found and found:IsA("BindableFunction") then Api[name] = found else Api[name] = nil end
		end
	end
	return Api.Damage ~= nil and (Api.TargetInfos ~= nil or Api.Zombies ~= nil)
end

local function ReadInfos()
	if Api.TargetInfos then
		local ok, raw = pcall(Api.TargetInfos.Invoke, Api.TargetInfos)
		if ok then return Core.NormalizeInfos(raw, IsLiveModel) end
		State.Diag.Errors += 1
		WarnOnce("targetinfos", "[PetCombatService] ZombieAPI.TargetInfos failed: " .. tostring(raw))
	end
	if Api.Zombies then
		local ok, models = pcall(Api.Zombies.Invoke, Api.Zombies)
		if ok then
			State.Diag.Fallback += 1
			local built, infos = pcall(Core.FallbackInfos, models, LiveRead)
			if built then return infos end
			models = infos
		end
		State.Diag.Errors += 1
		WarnOnce("zombies", "[PetCombatService] ZombieAPI.Zombies fallback failed: " .. tostring(models))
	end
	return {}
end

local function PositionOf(petId)
	local ok, pos = pcall(Deps.PetService.GetLogicalPosition, petId)
	if ok then return pos end
	return nil
end

local function Damage(model, amount)
	local fn = Api.Damage
	if not fn then return false, nil end
	local accepted, health, err = Core.CallDamage(fn, model, amount)
	if err then
		State.Diag.Errors += 1
		WarnOnce("damage", "[PetCombatService] ZombieAPI.Damage failed: " .. err)
	end
	return accepted, health
end

local function Emit(event, owner, position)
	local effects = Deps.Effects
	if type(effects) ~= "table" or type(effects.Emit) ~= "function" then return end
	local ok, err = pcall(effects.Emit, event, owner, position)
	if not ok then
		State.Diag.Errors += 1
		WarnOnce("emit", "[PetCombatService] PetEffectsBus.Emit failed: " .. tostring(err))
	end
end

local function Scan()
	local now = Clock()
	local pets, err = Core.ReadPets(Deps.PetService)
	if not pets then -- skip the scan: an unread list must not forget the deadlines (no second shot on the next scan)
		State.Diag.Errors += 1
		WarnOnce("pets", "[PetCombatService] PetService.GetActivePets failed: " .. tostring(err))
		return
	end
	local infos = {}
	if #pets > 0 then -- no active pets anywhere: no ZombieAPI call at all
		if ResolveApi() then
			infos = ReadInfos()
		else
			State.Diag.NoApi += 1
			WarnOnce("noapi", "[PetCombatService] ServerStorage." .. ZOMBIE_API .. " (Damage + TargetInfos/Zombies) not found: pets hold fire")
		end
	end
	Core.RunScan(State, {Now = now, Pets = pets, Infos = infos, PositionOf = PositionOf, Damage = Damage, Emit = Emit, Scan = SCAN, Muzzle = MUZZLE_HEIGHT})
end

local function OnHeartbeat(dt)
	local due
	Accumulator, due = Core.StepAccumulator(Accumulator, dt, SCAN)
	if not due then return end
	if Scanning then -- the last scan is still inside a yielding Invoke: skip this one
		if not StuckCounted and os.clock() - ScanStartedAt >= STUCK_SECONDS then
			StuckCounted = true
			State.Diag.StuckScans += 1
			WarnOnce("stuck", ("[PetCombatService] a combat scan has been running for %d s (a ZombieAPI Invoke yielded)"):format(STUCK_SECONDS))
		end
		return
	end
	Scanning, ScanStartedAt, StuckCounted = true, os.clock(), false
	local ok, err = pcall(Scan)
	Scanning = false
	if not ok then
		State.Diag.Errors += 1
		WarnOnce("scan", "[PetCombatService] scan failed: " .. tostring(err))
	end
end

--..API..--
function PetCombatService.Init(deps)
	if Deps then
		warn("[PetCombatService] Init called twice - ignored")
		return
	end
	if type(deps) ~= "table" then
		warn("[PetCombatService] Init needs a deps table")
		return
	end
	Deps = {PetService = deps.PetService, Effects = deps.Effects}
	if type(deps.Clock) == "function" then Clock = deps.Clock end
	if type(deps.PetService) ~= "table" then warn("[PetCombatService] Init without PetService: combat stays off") end
end

function PetCombatService.Start()
	if Started then return end
	local petService = Deps and Deps.PetService
	if type(petService) ~= "table" or type(petService.GetActivePets) ~= "function" or type(petService.GetLogicalPosition) ~= "function" then
		warn("[PetCombatService] Start without Init({PetService = ...}): combat stays off")
		return
	end
	Started = true
	if not PetBalance then warn("[PetCombatService] ReplicatedStorage.Modules.PetBalance missing: default scan 0.2 s / muzzle 1.5") end
	RunService.Heartbeat:Connect(OnHeartbeat)
	StartOk = true
end

function PetCombatService.IsStarted()
	return StartOk
end

function PetCombatService.GetDiagnostics()
	local copy = {}
	for key, value in pairs(State.Diag) do copy[key] = value end
	return copy
end

return PetCombatService
