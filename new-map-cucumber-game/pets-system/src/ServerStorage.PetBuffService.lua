--[[
	PetBuffService  (ModuleScript, ServerStorage)
	Cucumber buffs from pet abilities + the Leaf Shield theft guard (2026-09-22, pet-system polish).

	  * RUNTIME TRUTH = replicated attributes on the placed cucumber Model (CONTRACTS 6.2), so a
	    build-mode move, a carrier drop / return and dawn keep them with no code, the cards read
	    them and a Reload rebuilds them from the save:
	      PetBuff_Yield / PetBuff_Haste / PetBuff_Guard     number, ExpiresAt (server epoch =
	                                                        workspace:GetServerTimeNow())
	      PetBuff_YieldSrc / PetBuff_HasteSrc / PetBuff_GuardSrc   string, the source PetId
	      PetBuff_GuardCharges                              number (whole, >= 1)
	    Written only here and by CucumberCarry.RestorePlaced (StampFromRecord, before the tag).
	    BaseSaveService.Collect saves them as the cucumber record's PetBuffs (Serialize): absolute
	    expiries, so offline time consumes a buff and earns nothing.
	  * GRANT  PetService calls Grant(player, source, ability, now) after a successful chance roll.
	    Targets = the owner's placed cucumbers that pass the eligibility rule (IsEligible: tagged,
	    owned, in the owner's plot.Placed, not stolen, a CucumberId, BaseRestored, pivot on the plot
	    footprint -- a carrier-dropped one lying in the lobby is out -- and no live buff of that
	    kind: never stacked, never refreshed). One uniform target; Wild first picks uniformly among
	    the kinds that have a target. No target = the attempt is spent (nothing queued). Never by value.
	  * YIELD / HASTE multiply the cucumber's cash/sec through IncomeService: ModifiersOf(model, now)
	    is its modifier source (Rate = BaseRate x min(RATE_HARD_CAP, product)); state changes go
	    attributes FIRST, then IncomeService.Refresh (which settles with the old modifiers). One
	    sweeper (TIMING.BUFF_SWEEP) removes expired attributes; income itself splits at ExpiresAt.
	  * GUARD  TryBlockTheft(cucumber, zombie) is called by ZombieRaidService inside Grab and before
	    a grapple pull: synchronous, never yields, never errors, uses ITS OWN clock (the zombies run
	    on os.clock(), which must never reach this module). A live charge is consumed -> the theft is
	    denied and the cucumber gets GUARD.GraceSeconds of rejection grace (further attempts denied
	    without a charge); ShieldBlocked effect + snapshot are deferred.
	  * CLEAR  ClearCucumber at a theft (ZombieRaidService.Grab) and a pickup (CucumberCarry.PickUp).
	    Destroy / cleanup paths only unregister: this module never writes Data.Base (the snapshot of
	    the world is BaseSave's job; ours is a deferred, per-player coalesced BaseSaveAPI.Snapshot).

	API: Init(deps) Start() IsStarted() Serialize StampFromRecord ModifiersOf IsEligible Grant
	TryBlockTheft ClearCucumber GuardSeconds GetDiagnostics, Core (pure, unit-tested) and Stop()
	(teardown for Studio tests only). Nothing yields at require: ZombieRaidService may require this
	lazily from inside Grab.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--..Modules (FindFirstChild, never WaitForChild: requiring this must not yield)..--
local Modules = ReplicatedStorage:FindFirstChild("Modules")
local function Sibling(name)
	local module = Modules and Modules:FindFirstChild(name)
	if not module then error("[PetBuffService] ReplicatedStorage.Modules." .. name .. " is missing", 0) end
	return require(module)
end
local PetBalance = Sibling("PetBalance")
local PetStats = Sibling("PetStats")

local PetBuffService = {}

--..Helpers..--
local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function Num(x, fallback)
	if Finite(x) then return x end
	return fallback
end

local function Tab(x)
	return type(x) == "table" and x or {}
end

local function IsValidId(id)
	return type(id) == "string" and #id >= 1 and #id <= 64
end

--..Config (copied out of PetBalance once; every number validated)..--
local PLACED_TAG = "PlacedCucumber"
local KINDS = {"Yield", "Haste", "Guard"} -- the three cucumber effects (Wild picks one of them)
local KIND_SET = {Yield = true, Haste = true, Guard = true}
local RATE_KINDS = {"Yield", "Haste"} -- the ones that change cash/sec (Guard never does)
local ABILITIES = Tab(PetBalance.ABILITIES)
local GUARD = Tab(PetBalance.GUARD)
local GRACE_SECONDS = math.max(0, Num(GUARD.GraceSeconds, 1.5))
local GUARD_MAX_SECONDS = math.max(1, Num(GUARD.MaxSeconds, 600))
local GUARD_EXTRA = Num(GUARD.CycleExtra, 15)
local GUARD_CHARGES = math.max(1, math.floor(Num(Tab(ABILITIES.Guard).Charges, 1)))
local DEFAULT_DAY = Num(PetBalance.DEFAULT_DAY_SECONDS, 180)
local DEFAULT_NIGHT = Num(PetBalance.DEFAULT_NIGHT_SECONDS, 10)
local SWEEP_SECONDS = math.max(0.05, Num(Tab(PetBalance.TIMING).BUFF_SWEEP, 0.25))
local FOOTPRINT_MARGIN = 0.5 -- studs past the plot's half size that still count as "on the plot"
local CLOCK_SLACK = 5 -- seconds a restored expiry may exceed its kind's full duration (server clocks differ a little)
local MAX_RECORDS = 8 -- PetBuffs entries read from one saved cucumber record

local MULT, DURATION = {}, {}
for _, kind in ipairs(RATE_KINDS) do
	local row = Tab(ABILITIES[kind])
	MULT[kind] = (Finite(row.Mult) and row.Mult > 0) and row.Mult or 1
	DURATION[kind] = (Finite(row.Duration) and row.Duration > 0) and row.Duration or 90
end

local WILD_KINDS = {}
for _, kind in ipairs(type(Tab(ABILITIES.Wild).Kinds) == "table" and ABILITIES.Wild.Kinds or KINDS) do
	if KIND_SET[kind] then table.insert(WILD_KINDS, kind) end
end
if #WILD_KINDS == 0 then WILD_KINDS = KINDS end

--.. attribute names per kind (CONTRACTS 6.2)
local ATTR = {}
for _, kind in ipairs(KINDS) do
	ATTR[kind] = {
		Expires = "PetBuff_" .. kind,
		Src = "PetBuff_" .. kind .. "Src",
		Charges = kind == "Guard" and "PetBuff_GuardCharges" or nil,
	}
end

--..State..--
local Initialized, Started, StartedOk = false, false, false
local Income -- IncomeService (optional): Refresh(model, now)
local Effects -- PetEffectsBus (optional): Emit(event, owner, position)
local function DefaultClock()
	return workspace:GetServerTimeNow()
end
local Clock = DefaultClock
local Rng = Random.new()
local Buffed = setmetatable({}, {__mode = "k"}) -- [model] = true: carries PetBuff_* attributes (the sweeper's list)
local Grace = setmetatable({}, {__mode = "k"}) -- [model] = server time: thefts denied WITHOUT a charge until then
local SnapshotQueued = setmetatable({}, {__mode = "k"}) -- [player] = true while a deferred snapshot is pending
local Conns = {}
local LastWarn = {}
local Diag = {
	GrantsYield = 0, GrantsHaste = 0, GrantsGuard = 0, NoTarget = 0, NotReady = 0,
	ShieldBlocks = 0, GraceRejects = 0, Expired = 0, Cleared = 0, Invalid = 0,
	SnapshotFailures = 0, Errors = 0,
}

local function Bump(key)
	Diag[key] = (Diag[key] or 0) + 1
end

local function WarnOnce(key, message)
	local now = os.clock()
	if LastWarn[key] and now - LastWarn[key] < 60 then return end
	LastWarn[key] = now
	warn(message)
end

--.. the injected clock, never trusted blindly (a broken fake must not break a theft check)
local function Now()
	local ok, t = pcall(Clock)
	if ok and Finite(t) then return t end
	return workspace:GetServerTimeNow()
end

--..Core (pure: plain tables in, plain values out; exercised by tests/WP-BUFF_*.lua)..--
local Core = {}

--.. uniform among the kinds that have at least one eligible target (Wild); nil when none
function Core.PickKind(kindsWithTargets, rng)
	if type(kindsWithTargets) ~= "table" or #kindsWithTargets == 0 then return nil end
	return kindsWithTargets[rng:NextInteger(1, #kindsWithTargets)]
end

--.. uniform target: never by value (PLAN 4.2 rule 4)
function Core.PickTarget(list, rng)
	if type(list) ~= "table" or #list == 0 then return nil end
	return list[rng:NextInteger(1, #list)]
end

--.. the longest a buff of this kind can legally still run
function Core.MaxSecondsOf(kind)
	if kind == "Guard" then return GUARD_MAX_SECONDS end
	return DURATION[kind] or 0
end

--.. facts = {Tagged, IsModel, Owner, UserId, PlotOwner, InPlaced, StolenBy, CucumberId, BaseRestored,
--..          LocalX, LocalZ (pivot in plot space), HalfX, HalfZ (plot half size), Expires = {[kind] = n}}
--.. CONTRACTS 3.7 eligibility: every condition required
function Core.Eligible(facts, kind, now)
	if type(facts) ~= "table" or not KIND_SET[kind] then return false end
	if facts.Tagged ~= true or facts.IsModel ~= true then return false end
	local uid = facts.UserId
	if type(uid) ~= "number" or facts.Owner ~= uid or facts.PlotOwner ~= uid then return false end
	if facts.InPlaced ~= true or facts.StolenBy ~= nil then return false end
	if not IsValidId(facts.CucumberId) then return false end
	if facts.BaseRestored ~= true then return false end
	local x, z, hx, hz = facts.LocalX, facts.LocalZ, facts.HalfX, facts.HalfZ
	if not (Finite(x) and Finite(z) and Finite(hx) and Finite(hz)) then return false end
	if math.abs(x) > hx + FOOTPRINT_MARGIN or math.abs(z) > hz + FOOTPRINT_MARGIN then return false end
	--.. a live buff of the same kind: never stacked, never refreshed
	local expires = Tab(facts.Expires)[kind]
	if Finite(expires) and (not Finite(now) or expires > now) then return false end
	return true
end

--.. state = {GuardExpiresAt, Charges, GraceUntil} -> blocked, newState (+ Consumed = a charge was spent)
function Core.TryBlock(state, now)
	state = Tab(state)
	local new = {GuardExpiresAt = state.GuardExpiresAt, Charges = state.Charges, GraceUntil = state.GraceUntil, Consumed = false}
	if not Finite(now) then return false, new end
	if Finite(state.GraceUntil) and now < state.GraceUntil then return true, new end -- grace: denied, no charge
	local expires, charges = state.GuardExpiresAt, state.Charges
	if Finite(expires) and expires > now and Finite(charges) and charges >= 1 then
		new.Charges = math.floor(charges) - 1
		if new.Charges < 1 then
			new.Charges = 0
			new.GuardExpiresAt = nil
		end
		new.GraceUntil = now + GRACE_SECONDS
		new.Consumed = true
		return true, new
	end
	return false, new
end

--.. saved PetBuffs -> clean BuffRecords: known Kind, finite ExpiresAt > now (capped at the kind's full
--.. duration + CLOCK_SLACK), Guard Charges a whole number >= 1 (capped), SourcePetId an id or absent,
--.. one per kind (the first valid one wins). Anything else is dropped.
function Core.ValidateRecords(petBuffs, now)
	local out, seen = {}, {}
	if type(petBuffs) ~= "table" or not Finite(now) then return out end
	for i = 1, math.min(#petBuffs, MAX_RECORDS) do
		local record = petBuffs[i]
		local kind = type(record) == "table" and record.Kind or nil
		if KIND_SET[kind] and not seen[kind] then
			local expires, source = record.ExpiresAt, record.SourcePetId
			local charges = nil
			local valid = Finite(expires) and expires > now and (source == nil or IsValidId(source))
			if valid and kind == "Guard" then
				charges = record.Charges
				valid = Finite(charges) and charges >= 1 and charges % 1 == 0
				if valid then charges = math.min(charges, GUARD_CHARGES) end
			end
			if valid then
				seen[kind] = true
				table.insert(out, {
					Kind = kind,
					ExpiresAt = math.min(expires, now + Core.MaxSecondsOf(kind) + CLOCK_SLACK),
					SourcePetId = source,
					Charges = charges,
				})
			end
		end
	end
	return out
end

--.. the sweeper's verdict per kind from a model's attributes (model:GetAttributes()):
--.. "live" | "expired" | "invalid" (expiry not a number / a Guard without a charge / a source without an
--.. expiry) | nil (nothing of that kind there). Anything but "live" and nil is removed.
function Core.SweepVerdicts(attrs, now)
	local out = {}
	attrs = Tab(attrs)
	for _, kind in ipairs(KINDS) do
		local names = ATTR[kind]
		local expires = attrs[names.Expires]
		local valid = Finite(expires)
		if valid and names.Charges then
			local charges = attrs[names.Charges]
			valid = Finite(charges) and charges >= 1
		end
		if valid and Finite(now) and expires > now then
			out[kind] = "live"
		elseif valid and not Finite(now) then
			out[kind] = "live" -- no usable clock: never remove on a guess
		elseif expires ~= nil or attrs[names.Src] ~= nil or (names.Charges ~= nil and attrs[names.Charges] ~= nil) then
			out[kind] = valid and "expired" or "invalid"
		end
	end
	return out
end

--.. DayNightCycle's own rule: a number attribute counts (at least 1 s); else the workspace mirror; else nil
local function CyclePart(scriptValue, mirrorValue)
	if Finite(scriptValue) then return math.max(1, scriptValue) end
	if Finite(mirrorValue) then return math.max(1, mirrorValue) end
	return nil
end

function Core.CycleSeconds(scriptDay, scriptNight, mirrorDay, mirrorNight)
	return CyclePart(scriptDay, mirrorDay), CyclePart(scriptNight, mirrorNight)
end

--.. min(GUARD.MaxSeconds, day + night + GUARD.CycleExtra) through PetStats (defaults for missing halves)
function Core.GuardSeconds(scriptDay, scriptNight, mirrorDay, mirrorNight)
	local day, night = Core.CycleSeconds(scriptDay, scriptNight, mirrorDay, mirrorNight)
	local ok, seconds = pcall(PetStats.GuardSeconds, day, night)
	if ok and Finite(seconds) and seconds > 0 then return seconds end
	return math.min(GUARD_MAX_SECONDS, (day or DEFAULT_DAY) + (night or DEFAULT_NIGHT) + GUARD_EXTRA)
end

PetBuffService.Core = Core

--..Attributes..--
--.. source + charges first, the expiry (the "live" marker the clients watch) last
local function WriteKind(model, kind, expiresAt, sourceId, charges)
	local names = ATTR[kind]
	model:SetAttribute(names.Src, sourceId)
	if names.Charges then model:SetAttribute(names.Charges, charges) end
	model:SetAttribute(names.Expires, expiresAt)
end

local function RemoveKind(model, kind)
	local names = ATTR[kind]
	local had = model:GetAttribute(names.Expires) ~= nil or model:GetAttribute(names.Src) ~= nil
		or (names.Charges ~= nil and model:GetAttribute(names.Charges) ~= nil)
	if had then
		model:SetAttribute(names.Expires, nil)
		model:SetAttribute(names.Src, nil)
		if names.Charges then model:SetAttribute(names.Charges, nil) end
	end
	return had
end

local function HasAnyBuff(model)
	for _, kind in ipairs(KINDS) do
		local names = ATTR[kind]
		if model:GetAttribute(names.Expires) ~= nil or model:GetAttribute(names.Src) ~= nil
			or (names.Charges ~= nil and model:GetAttribute(names.Charges) ~= nil) then
			return true
		end
	end
	return false
end

--..World..--
local function PlotOf(player)
	local map = workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	local plots = lobby and lobby:FindFirstChild("Plots")
	if not plots then return nil end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function OwnerPlayer(model)
	local uid = model:GetAttribute("Owner")
	if type(uid) ~= "number" then return nil end
	return Players:GetPlayerByUserId(uid)
end

--.. where the effects aim: the footprint box (the card's adornee) when it has one
local function CentreOf(model)
	local hitbox = model:FindFirstChild("PlotHitbox")
	if hitbox and hitbox:IsA("BasePart") then return hitbox.Position end
	if model:IsA("PVInstance") then return model:GetPivot().Position end
	return nil
end

local function FactsOf(player, plot, placed, model)
	local isModel = model:IsA("Model")
	local facts = {
		Tagged = CollectionService:HasTag(model, PLACED_TAG),
		IsModel = isModel,
		Owner = model:GetAttribute("Owner"),
		UserId = player.UserId,
		PlotOwner = plot and plot:GetAttribute("Owner"),
		InPlaced = placed ~= nil and model.Parent == placed,
		StolenBy = model:GetAttribute("StolenBy"),
		CucumberId = model:GetAttribute("CucumberId"),
		BaseRestored = player:GetAttribute("BaseRestored"),
		Expires = {},
	}
	if plot and isModel then
		local p = plot.CFrame:PointToObjectSpace(model:GetPivot().Position)
		facts.LocalX, facts.LocalZ = p.X, p.Z
		facts.HalfX, facts.HalfZ = plot.Size.X * 0.5, plot.Size.Z * 0.5
	end
	for _, kind in ipairs(KINDS) do
		facts.Expires[kind] = model:GetAttribute(ATTR[kind].Expires)
	end
	return facts
end

--..Side effects (all pcall'd: a failing dependency never breaks a grant, a block or a clear)..--
local function RefreshIncome(model, now)
	if not (Income and type(Income.Refresh) == "function") then return end
	if not CollectionService:HasTag(model, PLACED_TAG) then return end -- only a registered producer is refreshed
	local ok, err = pcall(Income.Refresh, model, now)
	if not ok then
		Bump("Errors")
		WarnOnce("refresh", "[PetBuffService] IncomeService.Refresh failed: " .. tostring(err))
	end
end

local function Emit(event, owner, position)
	if not (Effects and type(Effects.Emit) == "function") or typeof(position) ~= "Vector3" then return end
	local ok, err = pcall(Effects.Emit, event, owner, position)
	if not ok then
		Bump("Errors")
		WarnOnce("emit", "[PetBuffService] Effects.Emit failed: " .. tostring(err))
	end
end

--.. default: BaseSaveService's non-quiet snapshot (attribute changes never trigger one by themselves)
local function DefaultSnapshot(player)
	local api = ServerStorage:FindFirstChild("BaseSaveAPI")
	local snapshot = api and api:FindFirstChild("Snapshot")
	if snapshot and snapshot:IsA("BindableFunction") and player.Parent then snapshot:Invoke(player) end
end
local SnapshotFn = DefaultSnapshot

--.. deferred + coalesced per player (never inside the synchronous theft check)
local function QueueSnapshot(player)
	if typeof(player) ~= "Instance" or SnapshotQueued[player] then return end
	SnapshotQueued[player] = true
	task.defer(function()
		SnapshotQueued[player] = nil
		local ok, err = pcall(SnapshotFn, player)
		if not ok then
			Bump("SnapshotFailures")
			WarnOnce("snapshot", "[PetBuffService] snapshot failed: " .. tostring(err))
		end
	end)
end

--..Registry + sweeper..--
--.. rule 0.14: every tagged Model is looked at on add whatever its Parent; only buffed ones are kept
local function OnAdded(model)
	if typeof(model) == "Instance" and model:IsA("Model") and HasAnyBuff(model) then Buffed[model] = true end
end

--.. destroy / cleanup / theft paths only unregister: the saved PetBuffs are BaseSave's (never Data.Base here)
local function OnRemoved(model)
	Buffed[model] = nil
	Grace[model] = nil
end

local function Sweep()
	local now = Now()
	for model in pairs(Buffed) do
		local live, rateChanged = false, false
		local verdicts = Core.SweepVerdicts(model:GetAttributes(), now)
		for _, kind in ipairs(KINDS) do
			local verdict = verdicts[kind]
			if verdict == "live" then
				live = true
			elseif verdict ~= nil then
				RemoveKind(model, kind)
				Bump(verdict == "expired" and "Expired" or "Invalid")
				if kind ~= "Guard" then rateChanged = true end
			end
		end
		if not live then Buffed[model] = nil end
		if rateChanged then RefreshIncome(model, now) end -- attributes first, then the settle + restamp
	end
	for model, untilTime in pairs(Grace) do
		if not Finite(untilTime) or untilTime <= now then Grace[model] = nil end
	end
end

--..Lifecycle..--
--.. deps = {IncomeService?, Effects?, Clock?, Rng?, Snapshot?}
function PetBuffService.Init(deps)
	if Initialized then
		warn("[PetBuffService] Init called twice - ignored")
		return
	end
	Initialized = true
	deps = Tab(deps)
	Income = type(deps.IncomeService) == "table" and deps.IncomeService or nil
	Effects = type(deps.Effects) == "table" and deps.Effects or nil
	if type(deps.Clock) == "function" then Clock = deps.Clock end
	local rng = deps.Rng
	if typeof(rng) == "Random" or (type(rng) == "table" and type(rng.NextInteger) == "function") then
		Rng = rng
	elseif rng ~= nil then
		warn("[PetBuffService] Init: Rng is not a Random - using a fresh one")
	end
	if type(deps.Snapshot) == "function" then SnapshotFn = deps.Snapshot end
end

function PetBuffService.Start()
	if Started then return end
	Started = true
	local ok, err = pcall(function()
		--.. signals before the sweep of what is already tagged (nothing slips between the two)
		table.insert(Conns, CollectionService:GetInstanceAddedSignal(PLACED_TAG):Connect(OnAdded))
		table.insert(Conns, CollectionService:GetInstanceRemovedSignal(PLACED_TAG):Connect(OnRemoved))
		for _, model in ipairs(CollectionService:GetTagged(PLACED_TAG)) do
			OnAdded(model)
		end
		local acc = 0
		table.insert(Conns, RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < SWEEP_SECONDS then return end
			acc = 0
			local swept, sweepErr = pcall(Sweep)
			if not swept then
				Bump("Errors")
				WarnOnce("sweep", "[PetBuffService] sweep failed: " .. tostring(sweepErr))
			end
		end))
	end)
	StartedOk = ok
	if not ok then warn("[PetBuffService] Start failed: " .. tostring(err)) end
end

function PetBuffService.IsStarted()
	return StartedOk
end

--.. teardown for Studio unit tests (disconnects everything; Start can run again). Not used in play.
function PetBuffService.Stop()
	for _, conn in ipairs(Conns) do
		conn:Disconnect()
	end
	table.clear(Conns)
	Started, StartedOk = false, false
end

--..Save / restore (stateless: work before Init / Start)..--
--.. live buffs of a placed cucumber -> {BuffRecord} for its saved record (nil when none)
function PetBuffService.Serialize(model, now)
	if typeof(model) ~= "Instance" then return nil end
	if not Finite(now) then now = Now() end
	local ok, records = pcall(function()
		local raw = {}
		for _, kind in ipairs(KINDS) do
			local names = ATTR[kind]
			local expires = model:GetAttribute(names.Expires)
			if expires ~= nil then
				table.insert(raw, {
					Kind = kind,
					ExpiresAt = expires,
					SourcePetId = model:GetAttribute(names.Src),
					Charges = names.Charges and model:GetAttribute(names.Charges) or nil,
				})
			end
		end
		return Core.ValidateRecords(raw, now)
	end)
	if not ok or type(records) ~= "table" or #records == 0 then return nil end
	return records
end

--.. a saved record's PetBuffs -> attributes (CucumberCarry.RestorePlaced, before the tag). Invalid,
--.. expired and duplicate-kind entries are dropped; returns how many were written.
function PetBuffService.StampFromRecord(model, petBuffs, now)
	if typeof(model) ~= "Instance" then return 0 end
	if not Finite(now) then now = Now() end
	local ok, written = pcall(function()
		local records = Core.ValidateRecords(petBuffs, now)
		for _, record in ipairs(records) do
			WriteKind(model, record.Kind, record.ExpiresAt, record.SourcePetId, record.Charges)
		end
		return #records
	end)
	if not ok then
		Bump("Errors")
		WarnOnce("stamp", "[PetBuffService] StampFromRecord failed: " .. tostring(written))
		return 0
	end
	return written
end

--.. IncomeService's modifier source: live Yield / Haste as {Kind, Mult, ExpiresAt} (Guard never)
function PetBuffService.ModifiersOf(model, now)
	local list = {}
	if typeof(model) ~= "Instance" then return list end
	if not Finite(now) then now = Now() end
	for _, kind in ipairs(RATE_KINDS) do
		local expires = model:GetAttribute(ATTR[kind].Expires)
		if Finite(expires) and expires > now then
			table.insert(list, {Kind = kind, Mult = MULT[kind], ExpiresAt = expires})
		end
	end
	return list
end

--..Eligibility / grants..--
function PetBuffService.IsEligible(player, model, kind, now)
	local ok, result = pcall(function()
		if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(model) ~= "Instance" then return false end
		if not Finite(now) then now = Now() end
		local plot = PlotOf(player)
		local placed = plot and plot:FindFirstChild("Placed")
		return Core.Eligible(FactsOf(player, plot, placed, model), kind, now)
	end)
	return ok and result == true
end

--.. min(GUARD.MaxSeconds, day + night + CycleExtra) from DayNightCycle's attributes, else the workspace
--.. mirrors, else the defaults (OD-22). Read at grant time only: a later cycle change never extends a shield.
function PetBuffService.GuardSeconds()
	local cycle = ServerScriptService:FindFirstChild("DayNightCycle")
	return Core.GuardSeconds(
		cycle and cycle:GetAttribute("DayDurationSeconds"), cycle and cycle:GetAttribute("NightDurationSeconds"),
		workspace:GetAttribute("DayDurationSeconds"), workspace:GetAttribute("NightDurationSeconds"))
end

local function GrantBody(player, source, ability, now)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false, "BadPlayer" end
	local kinds
	if ability == "Wild" then
		kinds = WILD_KINDS
	elseif KIND_SET[ability] then
		kinds = {ability}
	else
		return false, "BadAbility"
	end
	if not Finite(now) then now = Now() end
	--.. every eligible target per kind (one fact read per cucumber)
	local plot = PlotOf(player)
	local placed = plot and plot:FindFirstChild("Placed")
	local lists = {}
	for _, kind in ipairs(kinds) do lists[kind] = {} end
	if placed then
		for _, model in ipairs(placed:GetChildren()) do
			if model:IsA("Model") and CollectionService:HasTag(model, PLACED_TAG) then
				local facts = FactsOf(player, plot, placed, model)
				for _, kind in ipairs(kinds) do
					if Core.Eligible(facts, kind, now) then table.insert(lists[kind], model) end
				end
			end
		end
	end
	local withTargets = {}
	for _, kind in ipairs(kinds) do
		if #lists[kind] > 0 then table.insert(withTargets, kind) end
	end
	local kind = Core.PickKind(withTargets, Rng)
	local model = kind and Core.PickTarget(lists[kind], Rng)
	if not model then
		Bump("NoTarget")
		return false, "NoTarget" -- the attempt is spent; nothing is queued
	end
	local expiresAt, charges
	if kind == "Guard" then
		expiresAt = now + PetBuffService.GuardSeconds()
		charges = GUARD_CHARGES
	else
		expiresAt = now + DURATION[kind]
	end
	source = Tab(source)
	local sourceId = IsValidId(source.PetId) and source.PetId or nil
	WriteKind(model, kind, expiresAt, sourceId, charges)
	Buffed[model] = true
	Bump("Grants" .. kind)
	RefreshIncome(model, now) -- attributes first: Refresh settles with the old modifiers, then re-reads
	local to = CentreOf(model)
	local from = typeof(source.From) == "Vector3" and source.From or to
	local cucumberId = model:GetAttribute("CucumberId")
	Emit({
		Kind = "AbilityApplied", T = now, PetId = sourceId,
		PetName = type(source.DisplayName) == "string" and source.DisplayName or "Your pet",
		Ability = kind, Source = ability, CucumberId = cucumberId, Cucumber = model,
		From = from, To = to, ExpiresAt = expiresAt, Charges = charges,
	}, player, to)
	QueueSnapshot(player)
	return true, {Kind = kind, CucumberId = cucumberId, Model = model, ExpiresAt = expiresAt}
end

--.. source = {PetId, DisplayName, From = Vector3?}; ability = "Yield" | "Haste" | "Guard" | "Wild"
function PetBuffService.Grant(player, source, ability, now)
	if not StartedOk then
		Bump("NotReady")
		return false, "NotReady"
	end
	local ok, granted, detail = pcall(GrantBody, player, source, ability, now)
	if not ok then
		Bump("Errors")
		WarnOnce("grant", "[PetBuffService] Grant failed: " .. tostring(granted))
		return false, "Error"
	end
	return granted, detail
end

--..Theft guard..--
local function TryBlockBody(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return false end
	local now = Now()
	local names = ATTR.Guard
	local blocked, new = Core.TryBlock({
		GuardExpiresAt = model:GetAttribute(names.Expires),
		Charges = model:GetAttribute(names.Charges),
		GraceUntil = Grace[model],
	}, now)
	if not blocked then return false end
	if not new.Consumed then
		Bump("GraceRejects")
		return true
	end
	Grace[model] = new.GraceUntil
	if new.Charges >= 1 then
		model:SetAttribute(names.Charges, new.Charges)
	else
		RemoveKind(model, "Guard") -- the last charge: the shield is gone
	end
	Bump("ShieldBlocks")
	local owner = model:GetAttribute("Owner")
	local cucumberId = model:GetAttribute("CucumberId")
	local at = CentreOf(model)
	task.defer(function()
		Emit({Kind = "ShieldBlocked", T = now, CucumberId = cucumberId, Cucumber = model, At = at}, owner, at)
		local player = type(owner) == "number" and Players:GetPlayerByUserId(owner) or nil
		if player then QueueSnapshot(player) end
	end)
	return true
end

--.. true = deny this theft attempt. Synchronous, never yields, never errors. The third argument is
--.. ignored ENTIRELY: expiry and grace are server epoch (own Clock); the zombies' os.clock() never counts.
function PetBuffService.TryBlockTheft(cucumber, zombie, _now)
	if not StartedOk then return false end
	local ok, blocked = pcall(TryBlockBody, cucumber)
	if not ok then
		Bump("Errors")
		WarnOnce("block", "[PetBuffService] TryBlockTheft failed: " .. tostring(blocked))
		return false
	end
	return blocked == true
end

--.. every PetBuff_* off + grace; reason = "Stolen" | "PickUp" | "Destroyed" | "Dev". Returns whether
--.. anything was removed. Works before Start (a theft / pickup must never keep a buff).
function PetBuffService.ClearCucumber(model, reason, now)
	if typeof(model) ~= "Instance" then return false end
	Grace[model] = nil
	Buffed[model] = nil
	local ok, removed = pcall(function()
		local any = false
		for _, kind in ipairs(KINDS) do
			if RemoveKind(model, kind) then any = true end
		end
		return any
	end)
	if not ok then
		Bump("Errors")
		WarnOnce("clear", "[PetBuffService] ClearCucumber failed: " .. tostring(removed))
		return false
	end
	if not removed then return false end
	Bump("Cleared")
	if not Finite(now) then now = Now() end
	RefreshIncome(model, now) -- still tagged here (Grab / PickUp clear before they untag): settle, then restamp
	if reason ~= "Destroyed" then
		local player = OwnerPlayer(model)
		if player then QueueSnapshot(player) end
	end
	return true
end

--..Diagnostics..--
function PetBuffService.GetDiagnostics()
	local out = table.clone(Diag)
	local buffed = 0
	for _ in pairs(Buffed) do buffed += 1 end
	out.Buffed = buffed
	out.Started = StartedOk and 1 or 0
	return out
end

return PetBuffService
