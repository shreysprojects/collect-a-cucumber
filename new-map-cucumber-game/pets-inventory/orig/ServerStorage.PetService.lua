--[[
	PetService  (ModuleScript, ServerStorage)
	Canonical pet ownership + the plot-pet runtime (2026-09-22, pet-system polish). Bootstrapped by
	ServerScriptService.PetServer (Init -> Start); BaseSaveService / PetHatchService call it directly.

	  * OWNERSHIP: profile.Data.Base.Pets is the one list of owned pets (active + reserve, PetRecord
	    {Id, Pet, SourceEgg, SourceEggId?, Material, Mutations = {..}, EggKg?, AcquiredAt, Pos?,
	    AbilityRemaining}) and Data.Base.PetRoster the ordered active selection (<= PetBalance.SLOTS ids).
	    Records are never rebuilt from the world, never deleted here, and a pet whose model cannot spawn
	    stays owned. Only GrantFromEgg adds a record (the hatch commit: the egg record leaves Base.Eggs
	    and the pet record enters Base.Pets back to back, nothing that can throw in between), only the
	    roster calls (Equip / Unequip / EquipBest / the after-combat auto-equip) change the roster, and
	    only the scheduler / SyncRecords write AbilityRemaining / Pos.
	  * RUNTIME: per player an index (ById / BySourceEgg, keyed to the identity of the Base.Pets array
	    and the DataService profile generation - rebuilt when either changes) and one RuntimePet per
	    owned record with a derived Status: Active (spawned roster pet) / Pending (hatched into the
	    roster, waiting for its reveal) / Idle (roster, no plot attached) / Unavailable (roster, no
	    model: missing asset, failed spawn or vanished model; retried every UNAVAILABLE_RETRY s) /
	    Reserve / Invalid (unknown species). Session state (PetState Revision, request limiters) lives
	    per player session and survives runtime rebuilds.
	  * PLOT PETS (moved here from PetHatchService, same numbers, now PetBalance.PET): the model
	    (ReplicatedStorage.Assets.Pets/<key>, shrunk to fit a PET.FIT cube) is cloned ANCHORED and
	    collision-free into plot.Pets, tagged "PlotPet", with the section-6.1 attributes (PetId, PetName,
	    DisplayName, Rarity, Owner, OwnerName, Plot, PartCount, Material, Mutations, Rate, Ability,
	    ShotDamage, ShotInterval, Range, RoamRadius, RoamPhase + the roam segment, RoamSeq LAST),
	    PrismaticLoop = true BEFORE CucumberMutations.ApplyLook (so no server colour loop ever runs for a
	    pet; PetCardClient cycles PRISMATIC locally), all set before parenting; ModelStreamingMode Atomic
	    (S4: streams in / out whole, so a part can never return alone at the spawn pose). Only roster pets spawn.
	    A model destroyed by anything else turns its pet Unavailable (no income, no fire) until respawned.
	  * ROAMING: one shared planner (TIMING.ROAM_PLAN) keeps each spawned pet's logical segment
	    {From, To, Start, End, GroundY, Seq} and publishes it through PetMotion.ToAttributes; every leg
	    starts ROAM_LEAD s in the future so clients hold it before it begins. The server never moves a
	    pet after spawning it: PetMotion.Sample of the segment is the pet's position for combat range,
	    shot origins and saved Pos (PetRoamClient animates the same segment). Legs pick random points
	    LEG_MIN..LEG_MAX away inside the plot, EDGE_INSET from the edge, never on a placed thing; a plot
	    resize clamps every pet to the new bounds and replans.
	  * ABILITIES: every ABILITY_TICK the scheduler counts down AbilityRemaining of each Active roster
	    ability pet (owner loaded, not closing, plot attached, BaseRestored), at most MAX_TICK_DT per tick;
	    at zero it resets to ABILITY_PERIOD FIRST, then draws once (rarity chance) and on success asks
	    PetBuffService.Grant for the effect. No join / equip / offline roll, no backlog after a hitch.
	  * COMBAT LOCK: workspace CyclePhase == "Night" or the player's RaidLive attribute (mirrored to
	    PetCombatLocked). Roster actions are refused while locked; a hatch while locked goes to reserve
	    and, when a slot was free, joins the team at the unlock (PendingAutoEquip, runtime only).
	    (2026-09-22 review) "Free" counts the hatches already queued this lock, so every promise can be
	    kept, and a queued hatch stays presentation-pending: an unlock during its reveal equips it, the
	    reveal's end (FinishPresentation) spawns it at the egg spot.
	  * PetState (Remotes.PetState via Deps.SendState): Full on GetState / rebuild, revisioned Deltas for
	    changes and request results, unrevisioned Totals (<= 1 per TOTALS_PUSH) from IncomeService.
	    Requests: the Session limiters, plus (2026-09-22 review) a model budget for a client's EquipBest
	    (MODEL_CHURN_BURST spawns + despawns at once, MODEL_CHURN_PER_SECOND after that; over it the
	    request is refused "RateLimited" untouched). The EquipBest API itself is never throttled.
	  * CLOSE: DataService.OnBeforeClose Freeze (10) and SyncRecords (30) gate only on GetData ~= nil.

	API: Init(deps) Start() WaitReady(timeout?) IsStarted() IsReady(player) EnsureProfileState(player)
	AttachPlot(player, plot) DetachPlot(player, reason) SyncRecords(player, anchor?) HasSourceEgg(player,
	eggId) GrantFromEgg(player, eggInfo, petKey) FinishPresentation(player, petId, spot?, generation?)
	Equip / Unequip(player, petId) EquipBest(player, mode) HandleRequest(player, request)
	IsCombatLocked(player) GetActivePets() GetLogicalPosition(petId, now?) GetFullState(player)
	Freeze(player) GetDiagnostics() Core.*  (CONTRACTS.md 3.5). Extras: Tick(now?) = the Heartbeat
	scheduler body (tests drive it with an injected Clock), RefreshCombatLock(player),
	PushTotals(player, totals) = the IncomeService.OnTotalsChanged handler Start subscribes,
	HandlePlayerRemoving(player) = the Players.PlayerRemoving handler Start connects, and the
	Studio-only DevSetAbilityRemaining(player, petId, s) / DevForceProc(player, petId) for PetServer's
	PetDev "roll:" / "proc:" hooks. Optional test deps besides the contract ones: IsSpawnable(petKey),
	CyclePhase() and Migration (a PetDataMigration stand-in; false = none).
	Never: pays Cash, calls ZombieAPI, reads ownership from PlotPet tags, yields (except WaitReady).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

--..Modules (FindFirstChild, never WaitForChild: BaseSaveService / PetHatchService require this lazily at
--.. their top level, so a missing module must fail the require at once instead of hanging them - 0.5)..--
local Modules = ReplicatedStorage:FindFirstChild("Modules")
local function Need(name)
	local module = Modules and Modules:FindFirstChild(name)
	if not module then error("[PetService] ReplicatedStorage.Modules." .. name .. " is missing", 0) end
	return require(module)
end
local PetBalance = Need("PetBalance") -- first: PetStats / PetMotion wait on it
local PetStats = Need("PetStats")
local PetMotion = Need("PetMotion")
local Catalog = Need("PetsCatalog")
local CucumberMutations = Need("CucumberMutations")
local BuildCatalog = Need("BuildCatalog")

--..Helpers (pure)..--
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

--..Config..--
local PET_TAG = "PlotPet"
local TIMING = Tab(PetBalance.TIMING)
local PET = Tab(PetBalance.PET)
local REQUESTS = Tab(PetBalance.REQUESTS)
local SLOTS = Num(PetBalance.SLOTS, 6)
local MAX_OWNED = Num(PetBalance.MAX_OWNED, 1000)
local ABILITY_PERIOD = Num(TIMING.ABILITY_PERIOD, 60)
local ABILITY_TICK = Num(TIMING.ABILITY_TICK, 0.25)
local ROAM_PLAN = Num(TIMING.ROAM_PLAN, 0.2)
local ROAM_LEAD = Num(TIMING.ROAM_LEAD, 0.3)
local TOTALS_PUSH = Num(TIMING.TOTALS_PUSH, 1)
local UNAVAILABLE_RETRY = Num(TIMING.UNAVAILABLE_RETRY, 30)
local PET_FIT = Num(PET.FIT, 5) -- studs: pets are shrunk (proportions kept) to fit this cube (zombie petsize)
local EDGE_INSET = Num(PET.EDGE_INSET, 2) -- studs kept from the plot edge when picking roam points
local SPEED_MIN, SPEED_MAX = Num(PET.SPEED_MIN, 5), Num(PET.SPEED_MAX, 8) -- studs / s per leg
local IDLE_MIN, IDLE_MAX = Num(PET.IDLE_MIN, 1.5), Num(PET.IDLE_MAX, 4.5) -- seconds between legs
local LEG_MIN, LEG_MAX = Num(PET.LEG_MIN, 8), Num(PET.LEG_MAX, 26) -- preferred leg length (studs); clamped to the plot
local MAX_ID_LENGTH = Num(REQUESTS.MAX_ID_LENGTH, 64)
local MAX_REQUEST_ID_LENGTH = Num(REQUESTS.MAX_REQUEST_ID_LENGTH, 40)
--.. (2026-09-22, review #5) pet models a client's EquipBest requests may spawn + despawn: one whole-team swap
--.. at once, then 2 per second (a single Equip / Unequip is one model per roster token already)
local MODEL_CHURN_PER_SECOND = Num(REQUESTS.MODEL_CHURN_PER_SECOND, 2)
local MODEL_CHURN_BURST = Num(REQUESTS.MODEL_CHURN_BURST, SLOTS * 2)
local MAX_TICK_DT = 5 -- s: one ability tick never counts down more than this (hitch policy: no backlog)
local SPAWN_IDLE_MIN, SPAWN_IDLE_MAX = 0.5, 2 -- s before a fresh pet's first leg
local MIN_LEG = 3 -- studs: a roam point closer than this is not worth walking to
local LOCK_POLL = 1 -- s: fallback combat-lock poll (the attribute watchers normally catch it first)
local STALE_POLL = 1 -- s: profile tables replaced under the runtime (restore tool / edits) -> rebuild
local PROFILE_SIZE_PERIOD = 120 -- s between profile-size samples (ProfileBytesMax)
local PROFILE_SIZE_WARN = 1024 * 1024 -- bytes
local INVENTORY_FULL_PUSH = 60 -- s between InventoryFull hatch notices per player
local WARN_INTERVAL = 60 -- s: one warn per reason per server per minute
local CLOCK_SANITY = 3600 -- s: a caller's `now` further than this from the server clock is ignored
local DEFAULT_GUARD = PetStats.GuardSeconds(PetBalance.DEFAULT_DAY_SECONDS, PetBalance.DEFAULT_NIGHT_SECONDS)
local ACTIONS = {GetState = true, Equip = true, Unequip = true, EquipBest = true}
local SORT_MODES = {Income = true, Combat = true}
local KNOWN_MATERIALS = Tab(PetBalance.MATERIALS)
local ABILITIES = Tab(PetBalance.ABILITIES)
local TEXT = Tab(PetBalance.TEXT)

local function IsValidId(id)
	return type(id) == "string" and #id >= 1 and #id <= MAX_ID_LENGTH
end

local function GenerateId()
	return HttpService:GenerateGUID(false)
end

--..State..--
local PetService = {}
local Core = {}
PetService.Core = Core

local Deps = {}
local DataService = nil -- Deps.DataService, set by Init
local Inited, Started, StartOk = false, false, false
local Clock = function() return workspace:GetServerTimeNow() end
local AbilityRng, RoamRng = Random.new(), Random.new()
local Session = {} -- [player] = {Revision, ClientReady, LastTotalsPush, limiters...} (whole player session)
local Runtime = {} -- [player] = {Generation, PetsArray, KnownCount, Index, Plot, Attached, Frozen, Pets, Spawned, PendingAutoEquip}
local Frozen = {} -- [player] = true once the close phase began (survives rebuilds)
local LockState = {} -- [player] = the last mirrored combat lock
local PendingDeltas = {} -- [player] = {Upserts = {[id] = true}, Roster, Lock} waiting for the deferred flush
local TotalsDirty = {} -- [player] = totals owed to the client (throttled Kind "Totals")
local SendingFull = {} -- [player] = true while a Full is being built (a rebuild inside must not send another)
local PlayerConns = {} -- [player] = {RBXScriptConnection}
local PlotConns = {} -- [plot] = {RBXScriptConnection}
local ResizeQueued = {} -- [plot] = true while a deferred resize replan is pending
local LastRun = {} -- scheduler clocks (server epoch)
local ActiveCache, ActiveDirty = {}, true
local MigrationCache = nil
local WarnedAt = {}
local Diag = {
	SpawnFailures = 0, Rolls = 0, ProcSuccess = 0, ProcNoTarget = 0, ProcSkipped = 0, ProcErrors = 0,
	DeniedRequests = 0, Repairs = 0, UnknownTraits = 0, ModelVanished = 0, AutoEquipped = 0,
	InventoryFull = 0, OwnedMax = 0, ProfileBytesMax = 0, Rebuilds = 0, SchedulerErrors = 0,
}

local function WarnOnce(key, msg)
	local now = os.clock()
	local last = WarnedAt[key]
	if last and now - last < WARN_INTERVAL then return end
	WarnedAt[key] = now
	warn(msg)
end

--..DataService access (feature-checked; everything answers safely before Init)..--
local function GetDataOf(player)
	if not DataService or player == nil then return nil end
	local ok, data = pcall(DataService.GetData, player)
	if ok and type(data) == "table" then return data end
	return nil
end

local function IsClosing(player)
	if DataService and type(DataService.IsClosing) == "function" then
		local ok, closing = pcall(DataService.IsClosing, player)
		return ok and closing == true
	end
	return false
end

local function GenerationOf(player)
	if DataService and type(DataService.GetGeneration) == "function" then
		local ok, generation = pcall(DataService.GetGeneration, player)
		if ok and Finite(generation) then return generation end
	end
	return 0
end

local function MigrationReportOf(player)
	if DataService and type(DataService.GetMigrationReport) == "function" then
		local ok, report = pcall(DataService.GetMigrationReport, player)
		if ok and type(report) == "table" then return report end
	end
	return nil
end

local function RequestSave(player)
	if DataService and type(DataService.RequestSave) == "function" then
		pcall(DataService.RequestSave, player)
	end
end

--.. 2026-09-23 (Manage panel): the roster limit grows with the plot level - ReplicatedStorage.Modules.ManageConfig
--.. .PetCapacity(Data.PlotLevel), never above SLOTS; without that module (or a profile) it is SLOTS. A roster that
--.. is already bigger keeps its pets (nothing is unequipped for it); new equips wait for room.
local ManageConfigCache = nil
local function SlotsOf(player)
	if ManageConfigCache == nil then
		local modules = ReplicatedStorage:FindFirstChild("Modules")
		local module = modules and modules:FindFirstChild("ManageConfig")
		local ok, result = false, nil
		if module then ok, result = pcall(require, module) end
		ManageConfigCache = (ok and type(result) == "table" and type(result.PetCapacity) == "function") and result or false
	end
	if not ManageConfigCache then return SLOTS end
	local data = GetDataOf(player)
	local ok, n = pcall(ManageConfigCache.PetCapacity, data and data.PlotLevel or 0)
	if ok and Finite(n) then return math.clamp(math.floor(n), 1, SLOTS) end
	return SLOTS
end

--.. PetDataMigration is optional until its stage is installed (Deps.Migration: test stand-in, false = none)
local function MigrationModule()
	if Deps.Migration ~= nil then return Deps.Migration or nil end
	if MigrationCache then return MigrationCache end
	local module = ServerStorage:FindFirstChild("PetDataMigration")
	if not module then return nil end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then MigrationCache = result end
	return MigrationCache
end

local function IsSpawnable(petKey)
	if type(Deps.IsSpawnable) == "function" then
		local ok, result = pcall(Deps.IsSpawnable, petKey)
		return ok and result == true
	end
	return type(petKey) == "string" and Catalog.PETS[petKey] ~= nil and Catalog.ModelOf(petKey) ~= nil
end

local function PhaseOf()
	if type(Deps.CyclePhase) == "function" then
		local ok, phase = pcall(Deps.CyclePhase)
		return ok and phase or nil
	end
	return workspace:GetAttribute("CyclePhase")
end

local function AttrOf(object, name)
	local ok, value = pcall(function() return object:GetAttribute(name) end)
	if ok then return value end
	return nil
end

local function OwnerOf(plot)
	return AttrOf(plot, "Owner")
end

local function GuardSecondsNow()
	local buffs = Deps.PetBuffService
	if buffs and type(buffs.GuardSeconds) == "function" then
		local ok, seconds = pcall(buffs.GuardSeconds)
		if ok and Finite(seconds) and seconds > 0 then return seconds end
	end
	return DEFAULT_GUARD
end

--..Roster helpers (the live array is always re-read from the profile)..--
local function RosterArray(base)
	local roster = type(base) == "table" and base.PetRoster or nil
	return type(roster) == "table" and roster or {}
end

local function RosterList(data)
	local out = {}
	for _, id in ipairs(RosterArray(data and data.Base)) do
		if type(id) == "string" then table.insert(out, id) end
	end
	return out
end

local function RosterSet(data)
	local set = {}
	for _, id in ipairs(RosterArray(data and data.Base)) do
		if type(id) == "string" then set[id] = true end
	end
	return set
end

local function CopyRoster(roster)
	local out = {}
	for _, id in ipairs(Tab(roster)) do
		if type(id) == "string" and not table.find(out, id) then table.insert(out, id) end
	end
	return out
end

--.. write `list` into base.PetRoster in place (a missing / broken roster becomes a fresh array)
local function SetRoster(base, list)
	local live = base.PetRoster
	if type(live) ~= "table" then
		live = {}
		base.PetRoster = live
	end
	table.clear(live)
	for i, id in ipairs(list) do live[i] = id end
	return live
end

--..Plot geometry (moved from PetHatchService, 2026-09-07 port)..--
local function PlotTop(plot)
	return plot.Position.Y + plot.Size.Y * 0.5
end

--.. BaseSaveService's save frame: the plot's top surface at the middle of its BACK edge
local function AnchorOf(plot)
	local backZ = BuildCatalog.BackZ(plot)
	return plot.CFrame * CFrame.new(0, plot.Size.Y * 0.5, backZ)
end

--.. zombie Movement.rootToVisibleBottom: how far the visible artwork hangs below the root, so the
--.. pet stands on the ground instead of the invisible root
local function RootToVisibleBottom(pet, root)
	local bottom = math.huge
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			local cf, half = d.CFrame, d.Size * 0.5
			local yExtent = math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
			bottom = math.min(bottom, d.Position.Y - yExtent)
		end
	end
	if bottom == math.huge then
		local cf, size = pet:GetBoundingBox()
		bottom = cf.Position.Y - size.Y * 0.5
	end
	return root.Position.Y - bottom
end

--.. plot-local half extents a pet centre may use
local function RoamBounds(plot, radius)
	local hx = plot.Size.X * 0.5 - EDGE_INSET - radius
	local hz = plot.Size.Z * 0.5 - EDGE_INSET - radius
	return math.max(hx, 0.5), math.max(hz, 0.5)
end

local function ClampToPlot(plot, worldPos, radius)
	local hx, hz = RoamBounds(plot, radius)
	local rel = plot.CFrame:PointToObjectSpace(worldPos)
	local x = math.clamp(rel.X, -hx, hx)
	local z = math.clamp(rel.Z, -hz, hz)
	local p = plot.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
	return Vector3.new(p.X, PlotTop(plot), p.Z)
end

local function Blocked(plot, pos, radius)
	local placed = typeof(plot) == "Instance" and plot:FindFirstChild("Placed") or nil
	if not placed or #placed:GetChildren() == 0 then return false end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {placed}
	local box = CFrame.new(pos.X, PlotTop(plot) + 2, pos.Z)
	return #workspace:GetPartBoundsInBox(box, Vector3.new(radius * 2, 4, radius * 2), params) > 0
end

local function FlatDistance(a, b)
	return Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
end

--.. a new roam point: a leg of LEG_MIN..LEG_MAX studs in a random direction, kept inside the
--.. plot and off the placed objects; falls back to any free point; nil = nothing free
local function PickPoint(plot, from, radius)
	for _ = 1, 10 do
		local angle = RoamRng:NextNumber() * math.pi * 2
		local len = RoamRng:NextNumber(LEG_MIN, LEG_MAX)
		local candidate = ClampToPlot(plot, from + Vector3.new(math.cos(angle) * len, 0, math.sin(angle) * len), radius)
		if FlatDistance(from, candidate) >= MIN_LEG and not Blocked(plot, candidate, radius) then return candidate end
	end
	local hx, hz = RoamBounds(plot, radius)
	for _ = 1, 10 do
		local p = plot.CFrame:PointToWorldSpace(Vector3.new(RoamRng:NextNumber(-hx, hx), 0, RoamRng:NextNumber(-hz, hz)))
		local candidate = Vector3.new(p.X, PlotTop(plot), p.Z)
		if FlatDistance(from, candidate) >= MIN_LEG and not Blocked(plot, candidate, radius) then return candidate end
	end
	return nil
end

local function PlotsFolder()
	local map = workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	return lobby and lobby:FindFirstChild("Plots") or nil
end

local function PlotOf(player)
	local plots = PlotsFolder()
	if not plots then return nil end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function PetsFolderOf(plot)
	local folder = plot:FindFirstChild("Pets")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Pets"
		folder.Parent = plot
	end
	return folder
end

--..Core (pure; unit-tested with plain tables)..--
local Limiter = {}
Limiter.__index = Limiter

--.. token bucket: `Rate` tokens per second up to `Burst`; Take(now, count?) spends `count` (default 1)
--.. tokens, all or none
function Limiter:Take(now, count)
	count = (Finite(count) and count >= 0) and count or 1
	if Finite(now) then
		if self.Last == nil then self.Last = now end
		if now > self.Last then
			self.Tokens = math.min(self.Burst, self.Tokens + (now - self.Last) * self.Rate)
			self.Last = now
		end
	end
	if self.Tokens >= count then
		self.Tokens -= count
		return true
	end
	return false
end

function Core.NewLimiter(ratePerSec, burst)
	local rate = (Finite(ratePerSec) and ratePerSec > 0) and ratePerSec or 1
	local cap = (Finite(burst) and burst >= 1) and math.floor(burst) or 1
	return setmetatable({Rate = rate, Burst = cap, Tokens = cap, Last = nil}, Limiter)
end

--.. PetRequest (7.1): only RequestId / Action / PetId / SortMode are read
function Core.ValidateRequest(req)
	if type(req) ~= "table" then return false, "BadRequest" end
	local requestId, action = req.RequestId, req.Action
	if type(requestId) ~= "string" or #requestId < 1 or #requestId > MAX_REQUEST_ID_LENGTH then return false, "BadRequest" end
	if type(action) ~= "string" or not ACTIONS[action] then return false, "BadRequest" end
	local cleaned = {RequestId = requestId, Action = action}
	if action == "Equip" or action == "Unequip" then
		if not IsValidId(req.PetId) then return false, "BadRequest" end
		cleaned.PetId = req.PetId
	elseif action == "EquipBest" then
		if type(req.SortMode) ~= "string" or not SORT_MODES[req.SortMode] then return false, "BadRequest" end
		cleaned.SortMode = req.SortMode
	end
	return true, cleaned
end

--.. ctx = {Slots, Locked, HasPlot, IsOwned(id), IsEquippable(id)} -> a new roster (already equipped:
--.. the same ids, a no-op) or nil + error code
function Core.Equip(roster, petId, ctx)
	ctx = Tab(ctx)
	if ctx.Locked then return nil, "CombatLocked" end
	if not ctx.HasPlot then return nil, "NoPlot" end
	if not IsValidId(petId) or type(ctx.IsOwned) ~= "function" or not ctx.IsOwned(petId) then return nil, "NotOwned" end
	local copy = CopyRoster(roster)
	if table.find(copy, petId) then return copy end
	if type(ctx.IsEquippable) == "function" and not ctx.IsEquippable(petId) then return nil, "Unavailable" end
	if #copy >= Num(ctx.Slots, SLOTS) then return nil, "SlotsFull" end
	table.insert(copy, petId)
	return copy
end

function Core.Unequip(roster, petId)
	local out = {}
	for _, id in ipairs(Tab(roster)) do
		if type(id) == "string" and id ~= petId and not table.find(out, id) then table.insert(out, id) end
	end
	return out
end

--.. the top `slots` owned, valid, spawnable pets by PetStats.Compare(mode) (Id tie-break: same input,
--.. same roster)
function Core.EquipBest(pets, statsOf, isSpawnable, mode, slots)
	mode = mode == "Combat" and "Combat" or "Income"
	slots = Finite(slots) and math.max(0, math.floor(slots)) or SLOTS
	local candidates, seen = {}, {}
	for _, rec in ipairs(Tab(pets)) do
		if type(rec) == "table" and IsValidId(rec.Id) and not seen[rec.Id] then
			seen[rec.Id] = true
			local okStats, stats = pcall(statsOf, rec)
			local spawnable = true
			if type(isSpawnable) == "function" then
				local okSpawn, result = pcall(isSpawnable, rec.Pet)
				spawnable = okSpawn and result == true
			end
			if okStats and type(stats) == "table" and stats.Valid and spawnable then
				table.insert(candidates, {Id = rec.Id, Stats = stats})
			end
		end
	end
	table.sort(candidates, function(a, b) return PetStats.Compare(a, b, mode) end)
	local roster = {}
	for i = 1, math.min(slots, #candidates) do roster[i] = candidates[i].Id end
	return roster
end

local function ScanSourceEgg(pets, eggId)
	for _, rec in ipairs(Tab(pets)) do
		if type(rec) == "table" and rec.SourceEggId == eggId then return rec end
	end
	return nil
end

local function IdTaken(pets, index, id)
	if index and index.ById[id] ~= nil then return true end
	for _, rec in ipairs(Tab(pets)) do
		if type(rec) == "table" and rec.Id == id then return true end
	end
	return false
end

--.. THE HATCH COMMIT (8.2 step 4). ctx = {GenerateId, Now, AllowRoster, Locked, Slots, MaxOwned,
--.. IsSpawnable, Index?, Pending?}. Pinned order: (a) everything that can fail, (b) egg record out + pet record
--.. in + roster + index back to back with nothing that can throw in between
function Core.GrantFromEgg(base, eggInfo, petKey, ctx)
	ctx = Tab(ctx)
	if type(base) ~= "table" or type(base.Pets) ~= "table" then return nil, {Error = "NotLoaded"} end
	eggInfo = Tab(eggInfo)
	local eggId = IsValidId(eggInfo.EggId) and eggInfo.EggId or nil
	local index = type(ctx.Index) == "table" and ctx.Index or nil
	if index then
		if type(index.ById) ~= "table" then index.ById = {} end
		if type(index.BySourceEgg) ~= "table" then index.BySourceEgg = {} end
	end
	local eggs = type(base.Eggs) == "table" and base.Eggs or nil
	local function FindEgg()
		if not eggId or not eggs then return nil end
		for i, rec in ipairs(eggs) do
			if type(rec) == "table" and rec.Id == eggId then return i end
		end
		return nil
	end

	--.. this egg was already hatched: drop its stale record, hand back the pet it gave (never a reroll)
	if eggId then
		local existing = (index and index.BySourceEgg[eggId]) or ScanSourceEgg(base.Pets, eggId)
		if existing then
			local idx = FindEgg()
			if idx then table.remove(eggs, idx) end
			return existing, {Duplicate = true, Equipped = false, Reserve = false, AutoEquipAfterCombat = false, EggRemoved = idx ~= nil}
		end
	end
	if #base.Pets >= Num(ctx.MaxOwned, MAX_OWNED) then return nil, {Error = "InventoryFull"} end

	--.. (a) every fallible step
	if type(petKey) ~= "string" then return nil, {Error = "UnknownSpecies"} end
	local stats = PetStats.Calculate({Pet = petKey})
	if type(stats) ~= "table" or not stats.Valid then return nil, {Error = "UnknownSpecies"} end
	local mutations = PetStats.NormalizeMutations(eggInfo.Mutations)
	local material = PetStats.NormalizeMaterial(eggInfo.Material)
	local id
	for _ = 1, 4 do
		local candidate = type(ctx.GenerateId) == "function" and ctx.GenerateId() or GenerateId()
		if IsValidId(candidate) and not IdTaken(base.Pets, index, candidate) then
			id = candidate
			break
		end
	end
	if not id then return nil, {Error = "IdFailed"} end
	local record = {
		Id = id,
		Pet = petKey,
		SourceEgg = PetStats.EggKeyOfShortName(eggInfo.EggName) or (PetStats.EggOf(petKey)),
		SourceEggId = eggId,
		Material = material,
		Mutations = mutations,
		EggKg = Finite(eggInfo.Kg) and eggInfo.Kg or nil,
		AcquiredAt = math.floor(Num(ctx.Now, os.time())),
		AbilityRemaining = ABILITY_PERIOD,
	}
	local roster = base.PetRoster
	local freshRoster = nil
	if type(roster) ~= "table" then
		freshRoster = {}
		roster = freshRoster
	end
	local spawnable = true
	if type(ctx.IsSpawnable) == "function" then
		local ok, result = pcall(ctx.IsSpawnable, petKey)
		spawnable = ok and result == true
	end
	local slots = Num(ctx.Slots, SLOTS)
	local open = ctx.AllowRoster ~= false and spawnable
	local equip = open and #roster < slots and not ctx.Locked
	--.. (2026-09-22, review #8) the after-combat promise only covers a slot that no earlier queued hatch of
	--.. this lock is already waiting for (ctx.Pending = the queue length)
	local queued = Finite(ctx.Pending) and math.max(0, math.floor(ctx.Pending)) or 0
	local afterCombat = open and ctx.Locked == true and #roster + queued < slots
	local idx = FindEgg()

	--.. (b) the commit: nothing below can throw
	if idx then table.remove(eggs, idx) end
	table.insert(base.Pets, record)
	if freshRoster then base.PetRoster = freshRoster end
	if equip then table.insert(roster, id) end
	if index then
		index.ById[id] = record
		if eggId then index.BySourceEgg[eggId] = record end
	end
	return record, {Equipped = equip, Reserve = not equip, AutoEquipAfterCombat = afterCombat, Duplicate = false, EggRemoved = idx ~= nil}
end

--.. entries = {{Id, Remaining, Chance, Force?}}: counts Remaining down by dt; at zero it goes back to
--.. ABILITY_PERIOD BEFORE the one draw, so a hitch can never replay a backlog. Returns {{Id, Success}}
function Core.StepAbility(entries, dt, rng)
	local rolls = {}
	if not Finite(dt) or dt <= 0 then return rolls end
	for _, entry in ipairs(Tab(entries)) do
		if type(entry) == "table" then
			local remaining = entry.Remaining
			if not Finite(remaining) or remaining < 0 or remaining > ABILITY_PERIOD then remaining = ABILITY_PERIOD end
			remaining -= dt
			if remaining <= 0 then
				remaining = ABILITY_PERIOD
				local chance = Finite(entry.Chance) and math.clamp(entry.Chance, 0, 1) or 0
				local draw = rng and rng:NextNumber() or math.random()
				table.insert(rolls, {Id = entry.Id, Success = entry.Force == true or draw < chance})
			end
			entry.Remaining = remaining
		end
	end
	return rolls
end

--.. PetView (7.2). guardSeconds (optional 4th argument) = the Leaf Shield duration shown for Guard / Wild
function Core.BuildPetView(record, runtimePet, equipped, guardSeconds)
	record = Tab(record)
	local stats = runtimePet and runtimePet.Stats
	if type(stats) ~= "table" then stats = PetStats.Calculate(record) end
	local status = runtimePet and runtimePet.Status
	if type(status) ~= "string" then
		if not stats.Valid then
			status = "Invalid"
		elseif equipped then
			status = "Idle"
		else
			status = "Reserve"
		end
	end
	local ability = type(stats.Ability) == "string" and stats.Ability or "None"
	local guard = Finite(guardSeconds) and guardSeconds or DEFAULT_GUARD
	local duration, durations
	if ability == "Yield" or ability == "Haste" then
		duration = Num(Tab(ABILITIES[ability]).Duration, nil)
	elseif ability == "Guard" then
		duration = guard
	elseif ability == "Wild" then
		durations = {Yield = Num(Tab(ABILITIES.Yield).Duration, 0), Haste = Num(Tab(ABILITIES.Haste).Duration, 0), Guard = guard}
	end
	local known = PetStats.SplitMutations(PetStats.NormalizeMutations(record.Mutations))
	local remaining = record.AbilityRemaining
	if not Finite(remaining) or remaining < 0 or remaining > ABILITY_PERIOD then remaining = ABILITY_PERIOD end
	return {
		Id = record.Id,
		Pet = type(record.Pet) == "string" and record.Pet or "",
		DisplayName = stats.DisplayName,
		Rarity = stats.Rarity,
		SourceEgg = type(record.SourceEgg) == "string" and record.SourceEgg or nil,
		Material = PetStats.NormalizeMaterial(record.Material),
		Mutations = known,
		AcquiredAt = Num(record.AcquiredAt, 0),
		Equipped = equipped == true,
		Status = status,
		AbilityRemaining = remaining,
		Stats = {
			Income = Num(stats.Income, 0), ShotDamage = Num(stats.ShotDamage, 0), ShotInterval = Num(stats.ShotInterval, 0),
			DPS = Num(stats.DPS, 0), Range = Num(stats.Range, 0), Ability = ability, AbilityChance = Num(stats.AbilityChance, 0),
			AbilityDuration = duration, AbilityDurations = durations, Fighter = stats.Fighter == true,
		},
	}
end

--..Runtime..--
local QueueDelta -- forward (deferred, coalesced PetState delta)

local function InvalidStats(record)
	return {Valid = false, Pet = nil, DisplayName = tostring(Tab(record).Pet), Rarity = "Common", RarityKnown = false,
		EggTier = 1, Rank = 1, AffixIncome = 1, AffixDamage = 1, Income = 0, ShotDamage = 0, ShotInterval = 0, DPS = 0,
		Range = 0, Ability = "None", AbilityChance = 0, Fighter = true, UnknownMutations = {}, Warnings = {"StatsError"}}
end

local function NewRuntimePet(record)
	local ok, stats = pcall(PetStats.Calculate, record)
	if not ok or type(stats) ~= "table" then stats = InvalidStats(record) end
	return {
		Id = record.Id, Record = record, Status = "Reserve", Model = nil, Segment = nil, IdleUntil = 0, Radius = 2,
		PresentationPending = false, PendingSpot = nil, Stats = stats, Despawning = false, Producer = false,
	}
end

local function HasUnknownTraits(stats)
	local unknown = stats.UnknownMutations
	return (type(unknown) == "table" and #unknown > 0) or (type(stats.UnknownMaterial) == "string" and stats.UnknownMaterial ~= "")
end

--.. PresentationPending wins over Idle; a roster pet with a plot but no model is Unavailable
local function DeriveStatus(rt, rp, inRoster)
	if not rp.Stats.Valid then return "Invalid" end
	if not inRoster then return "Reserve" end
	if rp.PresentationPending then return "Pending" end
	if rp.Model then return "Active" end
	if not rt.Attached then return "Idle" end
	return "Unavailable"
end

local function RefreshStatus(player, rt, rp, inRoster, push)
	local status = DeriveStatus(rt, rp, inRoster)
	if status ~= rp.Status then
		rp.Status = status
		ActiveDirty = true
		if push then QueueDelta(player, rp.Id) end
	end
end

local function RefreshStatuses(player, rt, push)
	local data = GetDataOf(player)
	if not data then return end
	local set = RosterSet(data)
	for id, rp in pairs(rt.Pets) do RefreshStatus(player, rt, rp, set[id] ~= nil, push) end
end

--.. the runtime still describes the profile's tables (same Pets array, generation and length)
local function IsCurrent(player, rt)
	local data = GetDataOf(player)
	local base = data and data.Base
	if type(base) ~= "table" then return false end
	if base.Pets ~= rt.PetsArray or GenerationOf(player) ~= rt.Generation then return false end
	return type(base.Pets) ~= "table" or #base.Pets == rt.KnownCount
end

local function BuildRuntime(player, data, generation, old)
	local pets = data.Base.Pets
	local rt = {
		Generation = generation, PetsArray = pets, KnownCount = type(pets) == "table" and #pets or 0,
		Index = {ById = {}, BySourceEgg = {}}, Plot = nil, Attached = false, Frozen = Frozen[player] == true,
		Pets = {}, Spawned = {}, PendingAutoEquip = {},
	}
	--.. the same profile generation keeps what only the runtime knows (a reveal in flight, the queue)
	local keep = old ~= nil and old.Generation == generation
	for _, rec in ipairs(Tab(pets)) do
		if type(rec) == "table" and IsValidId(rec.Id) and not rt.Index.ById[rec.Id] then
			rt.Index.ById[rec.Id] = rec
			if IsValidId(rec.SourceEggId) and not rt.Index.BySourceEgg[rec.SourceEggId] then
				rt.Index.BySourceEgg[rec.SourceEggId] = rec
			end
			local rp = NewRuntimePet(rec)
			local prev = keep and old.Pets[rec.Id] or nil
			if prev then
				rp.PresentationPending = prev.PresentationPending
				rp.PendingSpot = prev.PendingSpot
				rp.ForceProc = prev.ForceProc
			end
			if HasUnknownTraits(rp.Stats) then Diag.UnknownTraits += 1 end
			rt.Pets[rec.Id] = rp
		end
	end
	Diag.OwnedMax = math.max(Diag.OwnedMax, rt.KnownCount)
	if keep then
		for _, id in ipairs(old.PendingAutoEquip) do
			if rt.Pets[id] and not table.find(rt.PendingAutoEquip, id) then table.insert(rt.PendingAutoEquip, id) end
		end
	end
	local set = RosterSet(data)
	for id, rp in pairs(rt.Pets) do rp.Status = DeriveStatus(rt, rp, set[id] ~= nil) end
	return rt
end

--.. a Player instance that already left (PlayerRemoving ran; plain-table test fakes never count)
local function Departed(player)
	return typeof(player) == "Instance" and player.Parent == nil
end

local function SessionOf(player)
	local s = Session[player]
	if not s then
		s = {
			Revision = 0, ClientReady = false, LastTotalsPush = -math.huge, LastInventoryFull = -math.huge,
			SavedGeneration = nil,
			StateLimiter = Core.NewLimiter(REQUESTS.STATE_PER_SECOND, REQUESTS.STATE_BURST),
			RosterLimiter = Core.NewLimiter(REQUESTS.ROSTER_PER_SECOND, REQUESTS.ROSTER_BURST),
			ReplyLimiter = Core.NewLimiter(1, 2),
			ChurnLimiter = Core.NewLimiter(MODEL_CHURN_PER_SECOND, MODEL_CHURN_BURST),
		}
		--.. a late read for a departed player gets a throwaway session: storing it would keep the Player alive
		if not Departed(player) then Session[player] = s end
	end
	return s
end

--..Producers (IncomeService pays; PetService only registers spawned roster pets)..--
local function AddProducer(player, rp)
	local income = Deps.IncomeService
	if not income or type(income.SetPetProducer) ~= "function" or not rp.Model then return end
	local ok, err = pcall(income.SetPetProducer, player, rp.Id, rp.Model, rp.Stats.Income, nil)
	if ok then
		rp.Producer = true
	else
		WarnOnce("producer", "[PetService] SetPetProducer: " .. tostring(err))
	end
end

local function RemoveProducer(rp)
	if not rp.Producer then return end
	rp.Producer = false
	local income = Deps.IncomeService
	if income and type(income.RemovePetProducer) == "function" then
		local ok, err = pcall(income.RemovePetProducer, rp.Id, nil)
		if not ok then WarnOnce("producer", "[PetService] RemovePetProducer: " .. tostring(err)) end
	end
end

--..Spawning: "spawn an EXISTING record" (never a grant)..--
local function Publish(rp)
	local model = rp.Model
	if not model or not rp.Segment then return end
	pcall(function()
		for _, pair in ipairs(PetMotion.ToAttributes(rp.Segment)) do model:SetAttribute(pair[1], pair[2]) end
	end)
end

--.. where a pet appears when nothing better is known: its saved Pos (back-edge local, y ignored) or the
--.. plot centre
local function SavedSpot(plot, record)
	local pos = record.Pos
	if type(pos) == "table" and Finite(pos[1]) and Finite(pos[3]) then
		local ok, world = pcall(function() return AnchorOf(plot):PointToWorldSpace(Vector3.new(pos[1], 0, pos[3])) end)
		if ok and typeof(world) == "Vector3" then return world end
	end
	return plot.Position
end

local function StampAttributes(model, player, plot, record, rp, radius)
	local stats = rp.Stats
	local material = PetStats.NormalizeMaterial(record.Material)
	model:SetAttribute("PetId", record.Id)
	model:SetAttribute("PetName", record.Pet)
	model:SetAttribute("DisplayName", tostring(stats.DisplayName))
	model:SetAttribute("Rarity", tostring(stats.Rarity))
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("OwnerName", player.Name)
	model:SetAttribute("Plot", plot.Name)
	model:SetAttribute("Material", KNOWN_MATERIALS[material] and material or nil)
	model:SetAttribute("Mutations", PetStats.MutationString(PetStats.NormalizeMutations(record.Mutations)))
	model:SetAttribute("Rate", Num(stats.Income, 0))
	model:SetAttribute("Ability", tostring(stats.Ability))
	model:SetAttribute("ShotDamage", Num(stats.ShotDamage, 0))
	model:SetAttribute("ShotInterval", Num(stats.ShotInterval, 0))
	model:SetAttribute("Range", Num(stats.Range, 0))
	model:SetAttribute("RoamRadius", radius)
	model:SetAttribute("RoamPhase", RoamRng:NextNumber() * math.pi * 2)
	for _, pair in ipairs(PetMotion.ToAttributes(rp.Segment)) do model:SetAttribute(pair[1], pair[2]) end -- RoamSeq last
end

local function IdleSegment(plot, pos, now, seq)
	local ground = PlotTop(plot)
	local point = Vector3.new(pos.X, ground, pos.Z)
	return {From = point, To = point, Start = now, End = now, GroundY = ground, Seq = seq}
end

--.. the live spawn: clone, fit, anchor, place, stamp, look, tag, parent (last)
local function DefaultSpawn(player, plot, record, rp, spot, now)
	local template = Catalog.ModelOf(record.Pet)
	if not template then return nil, "no model for pet " .. tostring(record.Pet) end
	local pet
	local ok, err = pcall(function()
		pet = template:Clone()
		pet.Name = record.Pet
		--.. size cap (zombie petsize): shrink until it fits the cube, never grow
		local _, size = pet:GetBoundingBox()
		local factor = math.min(1, PET_FIT / size.X, PET_FIT / size.Y, PET_FIT / size.Z)
		if factor < 1 then pet:ScaleTo(pet:GetScale() * factor) end
		local partCount = 0
		for _, d in ipairs(pet:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Massless = true
				partCount += 1
			elseif d:IsA("BodyMover") or d:IsA("BodyGyro") or d:IsA("BodyPosition") then
				d:Destroy()
			end
		end
		local root = pet.PrimaryPart or pet:FindFirstChild("Root") or pet:FindFirstChildWhichIsA("BasePart", true)
		if not root then error("no BasePart in the model") end
		pet.PrimaryPart = root
		local rootToBottom = RootToVisibleBottom(pet, root)
		local _, fitted = pet:GetBoundingBox()
		local radius = math.max(fitted.X, fitted.Z) * 0.5
		local pos = ClampToPlot(plot, spot, radius)
		local yaw = RoamRng:NextNumber() * math.pi * 2
		pet:PivotTo(CFrame.new(pos.X, PlotTop(plot) + rootToBottom, pos.Z) * CFrame.Angles(0, yaw, 0))
		rp.Radius = radius
		rp.Segment = IdleSegment(plot, pos, now, 1)
		pet:SetAttribute("PartCount", partCount)
		StampAttributes(pet, player, plot, record, rp, radius)
		--.. pre-set so ApplyLook never starts its server PRISMATIC loop (PetCardClient cycles it locally)
		pet:SetAttribute("PrismaticLoop", true)
		--.. (2026-09-22, S4) stream the pet as ONE unit: in the Default mode every anchored part streams on
		--.. its own, and a part that streams back in lands at the server (spawn) pose while PetRoamClient has
		--.. moved the rest, tearing the model apart (37 studs measured); Atomic sends / removes it whole
		pet.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		local material = PetStats.NormalizeMaterial(record.Material)
		local mutations = PetStats.MutationString(PetStats.NormalizeMutations(record.Mutations))
		pcall(CucumberMutations.ApplyLook, pet, material ~= "" and material or nil, mutations)
		local folder = PetsFolderOf(plot)
		for _, child in ipairs(folder:GetChildren()) do -- backstop: never two models for one pet
			if child:GetAttribute("PetId") == record.Id then child:Destroy() end
		end
		CollectionService:AddTag(pet, PET_TAG)
		pet.Parent = folder
	end)
	if not ok then
		if pet then pcall(function() pet:Destroy() end) end
		rp.Segment = nil
		return nil, err
	end
	return pet
end

--.. Deps.Spawner (tests): the override builds the model; PetService still places + stamps it
local function OverrideSpawn(player, plot, record, rp, spot, now)
	local ok, model = pcall(Deps.Spawner, player, plot, record, spot)
	if not ok then return nil, model end
	if model == nil then return nil, "spawner returned nil" end
	local radius = Num(AttrOf(model, "RoamRadius"), 2)
	rp.Radius = radius
	rp.Segment = IdleSegment(plot, ClampToPlot(plot, spot, radius), now, 1)
	local okStamp, err = pcall(StampAttributes, model, player, plot, record, rp, radius)
	if not okStamp then
		rp.Segment = nil
		pcall(function() model:Destroy() end)
		return nil, err
	end
	return model
end

local function OnModelDestroying(player, rp, model)
	if rp.Model ~= model or rp.Despawning then return end -- ours to remove, or an old orphan
	if rp.DestroyConn then
		rp.DestroyConn:Disconnect()
		rp.DestroyConn = nil
	end
	rp.Model = nil
	rp.Segment = nil
	RemoveProducer(rp)
	Diag.ModelVanished += 1
	local rt = Runtime[player]
	if rt and rt.Pets[rp.Id] == rp then
		rt.Spawned[rp.Id] = nil
		RefreshStatus(player, rt, rp, RosterSet(GetDataOf(player))[rp.Id] ~= nil, true)
	end
	ActiveDirty = true
end

local function SpawnPet(player, rt, rp, spot)
	local plot = rt.Plot
	if not plot or rp.Model then return false end
	local record = rp.Record
	local now = Clock()
	if typeof(spot) ~= "Vector3" then spot = SavedSpot(plot, record) end
	local model, err
	if type(Deps.Spawner) == "function" then
		model, err = OverrideSpawn(player, plot, record, rp, spot, now)
	else
		model, err = DefaultSpawn(player, plot, record, rp, spot, now)
	end
	if not model then
		Diag.SpawnFailures += 1
		WarnOnce("spawn:" .. tostring(record.Pet), ("[PetService] pet %s (%s) could not spawn: %s"):format(tostring(record.Pet), tostring(record.Id), tostring(err)))
		return false
	end
	rp.Model = model
	rp.Despawning = false
	rp.IdleUntil = now + RoamRng:NextNumber(SPAWN_IDLE_MIN, SPAWN_IDLE_MAX)
	rt.Spawned[rp.Id] = rp
	if typeof(model) == "Instance" then
		rp.DestroyConn = model.Destroying:Connect(function() OnModelDestroying(player, rp, model) end)
	end
	AddProducer(player, rp)
	ActiveDirty = true
	return true
end

local function Despawn(rt, rp)
	local model = rp.Model
	rp.Despawning = true
	if rp.DestroyConn then
		rp.DestroyConn:Disconnect()
		rp.DestroyConn = nil
	end
	RemoveProducer(rp)
	rp.Model = nil
	rp.Segment = nil
	if rt then rt.Spawned[rp.Id] = nil end
	if model ~= nil then pcall(function() model:Destroy() end) end
	rp.Despawning = false
	ActiveDirty = true
end

--..Roaming (one shared planner)..--
local function PlanLeg(rt, rp, now)
	local plot = rt.Plot
	local radius = rp.Radius
	local here = PetMotion.Sample(rp.Segment, now) or plot.Position
	local from = ClampToPlot(plot, here, radius) -- the plot may have shrunk since the last leg
	local target = PickPoint(plot, from, radius)
	local seq = (rp.Segment and Finite(rp.Segment.Seq) and rp.Segment.Seq or 0) + 1
	local ground = PlotTop(plot)
	local start = now + ROAM_LEAD -- published ahead of time: clients hold the leg before it begins
	if not target then
		rp.Segment = {From = from, To = from, Start = start, End = start, GroundY = ground, Seq = seq}
		rp.IdleUntil = now + RoamRng:NextNumber(IDLE_MIN, IDLE_MAX)
	else
		local duration = FlatDistance(from, target) / RoamRng:NextNumber(SPEED_MIN, SPEED_MAX)
		rp.Segment = {From = from, To = target, Start = start, End = start + duration, GroundY = ground, Seq = seq}
		rp.IdleUntil = start + duration + RoamRng:NextNumber(IDLE_MIN, IDLE_MAX)
	end
	Publish(rp)
end

--.. PlotUpgradeService resized a plot: every pet on it idles at its clamped logical point, replans next tick
local function ReplanPlot(plot)
	ResizeQueued[plot] = nil
	local now = Clock()
	for _, rt in pairs(Runtime) do
		if rt.Attached and rt.Plot == plot then
			for _, rp in pairs(rt.Spawned) do
				if rp.Model then
					local here = PetMotion.Sample(rp.Segment, now) or plot.Position
					local seq = (rp.Segment and Finite(rp.Segment.Seq) and rp.Segment.Seq or 0) + 1
					rp.Segment = IdleSegment(plot, ClampToPlot(plot, here, rp.Radius), now, seq)
					rp.IdleUntil = now
					Publish(rp)
				end
			end
		end
	end
end

--..PetState messages..--
local function Send(player, payload)
	if type(Deps.SendState) ~= "function" then return end
	local ok, err = pcall(Deps.SendState, player, payload)
	if not ok then WarnOnce("send", "[PetService] SendState: " .. tostring(err)) end
end

local function TotalsOf(player, given)
	local totals = given
	if type(totals) ~= "table" then
		totals = nil
		local income = Deps.IncomeService
		if income and type(income.GetTotals) == "function" then
			local ok, result = pcall(income.GetTotals, player)
			if ok and type(result) == "table" then totals = result end
		end
	end
	totals = Tab(totals)
	return {Pet = Num(totals.Pet, 0), Cucumber = Num(totals.Cucumber, 0), CucumberBase = Num(totals.CucumberBase, 0), Total = Num(totals.Total, 0)}
end

local function EquippedIds(rt, data)
	local out = {}
	for _, id in ipairs(RosterList(data)) do
		if rt.Pets[id] and not table.find(out, id) then table.insert(out, id) end
	end
	return out
end

local function NotReadyReason(player)
	if not GetDataOf(player) then return "NotLoaded" end
	if Frozen[player] or IsClosing(player) then return "Closing" end
	local report = MigrationReportOf(player)
	if report and report.Failed == true then return "MigrationFailed" end
	return "NotLoaded"
end

local function CleanRequestId(request)
	local id = type(request) == "table" and request.RequestId or nil
	if type(id) == "string" and #id >= 1 and #id <= MAX_REQUEST_ID_LENGTH then return id end
	return nil
end

local function ActionName(action)
	if type(action) == "string" then return action:sub(1, 24) end
	return "?"
end

local function BuildFull(player, revision, requestId, result, consumeNotice)
	local payload = {
		Kind = "Full", Revision = revision, Generation = GenerationOf(player), RequestId = requestId, Result = result,
		Slots = SlotsOf(player), EquippedIds = {}, Pets = {}, Totals = TotalsOf(player),
		CombatLocked = PetService.IsCombatLocked(player), ServerTime = Clock(),
	}
	local data = GetDataOf(player)
	local rt = Runtime[player]
	if not data or not rt or type(data.Base) ~= "table" then
		if not result then payload.Result = {Ok = false, Action = "GetState", Error = NotReadyReason(player)} end
		return payload
	end
	local set = RosterSet(data)
	payload.EquippedIds = EquippedIds(rt, data)
	local guard = GuardSecondsNow()
	local seen = {}
	for _, rec in ipairs(Tab(data.Base.Pets)) do
		if type(rec) == "table" and IsValidId(rec.Id) and not seen[rec.Id] then
			seen[rec.Id] = true
			local rp = rt.Pets[rec.Id]
			if rp and rp.Record ~= rec then rp = nil end -- a stale runtime never hides a record
			table.insert(payload.Pets, Core.BuildPetView(rec, rp, set[rec.Id] ~= nil, guard))
		end
	end
	if consumeNotice and data.Base.PetNoticePending then
		payload.Notice = TEXT.MigrationNotice
		data.Base.PetNoticePending = nil
	end
	return payload
end

local function SendDelta(player, requestId, result, pd)
	if pd == nil then
		pd = PendingDeltas[player]
		PendingDeltas[player] = nil
	end
	local s = SessionOf(player)
	s.Revision += 1
	local payload = {
		Kind = "Delta", Revision = s.Revision, BaseRevision = s.Revision - 1, Generation = GenerationOf(player),
		RequestId = requestId, Result = result, ServerTime = Clock(),
	}
	local rt = Runtime[player]
	local data = GetDataOf(player)
	if pd and rt and data then
		local set = RosterSet(data)
		local guard = GuardSecondsNow()
		local upserts = {}
		for id in pairs(pd.Upserts) do
			local rp = rt.Pets[id]
			if rp then table.insert(upserts, Core.BuildPetView(rp.Record, rp, set[id] ~= nil, guard)) end
		end
		if #upserts > 0 then payload.Upserts = upserts end
		if pd.Removed then -- 2026-09-23: sold pets leave the client's inventory
			local removed = {}
			for id in pairs(pd.Removed) do table.insert(removed, id) end
			if #removed > 0 then payload.Removed = removed end
		end
		if pd.Roster then
			payload.EquippedIds = EquippedIds(rt, data)
			payload.Totals = TotalsOf(player)
		end
	end
	if pd and pd.Lock then payload.CombatLocked = PetService.IsCombatLocked(player) end
	Send(player, payload)
end

local function FlushDelta(player, pd)
	if PendingDeltas[player] ~= pd then return end -- already sent with a request reply, or superseded by a Full
	PendingDeltas[player] = nil
	local s = Session[player]
	if not s or not s.ClientReady then return end
	SendDelta(player, nil, nil, pd)
end

--.. changes are pushed only to a client that asked for state once (ClientReady); one frame's changes
--.. become one Delta (a request reply takes whatever is queued along with it)
QueueDelta = function(player, petId, roster, lock, removedId)
	local s = Session[player]
	if not s or not s.ClientReady then return end
	local pd = PendingDeltas[player]
	if not pd then
		pd = {Upserts = {}, Roster = false, Lock = false}
		PendingDeltas[player] = pd
		task.defer(FlushDelta, player, pd)
	end
	if petId then pd.Upserts[petId] = true end
	if roster then pd.Roster = true end
	if lock then pd.Lock = true end
	if removedId then -- 2026-09-23 (Sell)
		pd.Removed = pd.Removed or {}
		pd.Removed[removedId] = true
	end
end

local function SendFull(player, requestId, result)
	local s = SessionOf(player)
	SendingFull[player] = true
	if GetDataOf(player) and not Frozen[player] then
		local rt = Runtime[player]
		if not rt or not IsCurrent(player, rt) then pcall(PetService.EnsureProfileState, player) end
	end
	SendingFull[player] = nil
	PendingDeltas[player] = nil -- the Full carries everything
	s.Revision += 1
	local ok, payload = pcall(BuildFull, player, s.Revision, requestId, result, true)
	if ok then
		Send(player, payload)
	else
		WarnOnce("full", "[PetService] building a Full PetState failed: " .. tostring(payload))
	end
end

--..Combat lock + the after-combat auto-equip (OD-11)..--
local function RunAutoEquip(player, rt)
	if #rt.PendingAutoEquip == 0 or rt.Frozen or Frozen[player] or not rt.Attached then return 0 end
	local data = GetDataOf(player)
	local base = data and data.Base
	if type(base) ~= "table" then return 0 end
	local roster = CopyRoster(RosterArray(base))
	local added = {}
	for _, id in ipairs(rt.PendingAutoEquip) do
		if #roster >= SlotsOf(player) then break end
		local rp = rt.Pets[id]
		if rp and rp.Stats.Valid and not table.find(roster, id) and IsSpawnable(rp.Record.Pet) then
			table.insert(roster, id)
			table.insert(added, rp)
		end
	end
	table.clear(rt.PendingAutoEquip)
	if #added == 0 then return 0 end
	SetRoster(base, roster)
	for _, rp in ipairs(added) do
		rp.Record.AbilityRemaining = ABILITY_PERIOD
		if not rp.PresentationPending and not rp.Model then SpawnPet(player, rt, rp, nil) end
		RefreshStatus(player, rt, rp, true, false)
		QueueDelta(player, rp.Id, true)
	end
	Diag.AutoEquipped += #added
	ActiveDirty = true
	RequestSave(player)
	return #added
end

local function UpdateLock(player)
	local locked = PetService.IsCombatLocked(player)
	local previous = LockState[player]
	if previous == locked then return locked end
	LockState[player] = locked
	pcall(function() player:SetAttribute("PetCombatLocked", locked) end)
	if previous ~= nil then QueueDelta(player, nil, false, true) end
	if not locked then
		local rt = Runtime[player]
		if rt then RunAutoEquip(player, rt) end
	end
	return locked
end
PetService.RefreshCombatLock = UpdateLock

--..Attach / detach..--
local function Detach(player, reason, silent)
	local rt = Runtime[player]
	if not rt then return end
	local touched = false
	for _, rp in pairs(rt.Pets) do
		if rp.Model or rp.Producer then
			Despawn(rt, rp)
			touched = true
		end
	end
	local wasAttached = rt.Attached
	rt.Attached = false
	rt.Plot = nil
	if wasAttached or touched then
		ActiveDirty = true
		RefreshStatuses(player, rt, not silent)
	end
end

local Rebuild -- forward

local function EnsureRuntime(player)
	local rt = Runtime[player]
	if rt and IsCurrent(player, rt) then return true end
	return PetService.EnsureProfileState(player)
end

local function HasPlot(player, rt)
	local plot = rt.Plot
	if not rt.Attached or not plot then return false end
	if typeof(plot) == "Instance" and not plot.Parent then return false end
	return OwnerOf(plot) == player.UserId
end

--..Public API..--
function PetService.Init(deps)
	if Inited then
		warn("[PetService] Init called twice - ignored")
		return
	end
	deps = Tab(deps)
	if type(deps.DataService) ~= "table" then error("[PetService] Init: DataService is required") end
	Inited = true
	Deps = deps
	DataService = deps.DataService
	if type(deps.Clock) == "function" then Clock = deps.Clock end
	if deps.Rng ~= nil and (typeof(deps.Rng) == "Random" or type(deps.Rng) == "table") then
		AbilityRng, RoamRng = deps.Rng, deps.Rng
	end
	if type(deps.SendState) ~= "function" then warn("[PetService] Init: no SendState - PetState messages are dropped") end
end

function PetService.IsStarted()
	return StartOk
end

function PetService.WaitReady(timeout)
	if StartOk then return true end
	local deadline = os.clock() + Num(timeout, 30)
	while not StartOk and os.clock() < deadline do task.wait(0.1) end
	return StartOk
end

function PetService.IsReady(player)
	if not GetDataOf(player) or Frozen[player] or IsClosing(player) then return false end
	local rt = Runtime[player]
	return rt ~= nil and not rt.Frozen
end

--.. idempotent: re-runs the pet half of the migration (roster repair), (re)builds the runtime when it no
--.. longer describes the profile, and asks for a save when the migration wrote anything
function PetService.EnsureProfileState(player)
	local data = GetDataOf(player)
	if not data then return false, "NotLoaded" end
	if Frozen[player] or IsClosing(player) then return false, "Closing" end
	local report = MigrationReportOf(player)
	if report and report.Failed == true then return false, "MigrationFailed" end
	if type(data.Base) ~= "table" then return false, "MigrationFailed" end
	local changed = false
	local migration = MigrationModule()
	if migration and type(migration.Migrate) == "function" then
		local ok, result = pcall(migration.Migrate, data, {GenerateId = GenerateId, Now = os.time(), IsSpawnable = IsSpawnable, Scope = "Pets"})
		if not ok then
			WarnOnce("migrate", "[PetService] PetDataMigration (Pets) failed: " .. tostring(result))
			return false, "MigrationFailed"
		end
		if type(result) == "table" and result.Changed then
			changed = true
			Diag.Repairs += 1
		end
		if type(data.Base) ~= "table" then return false, "MigrationFailed" end
	end
	local generation = GenerationOf(player)
	local rt = Runtime[player]
	if not rt or changed or not IsCurrent(player, rt) then Rebuild(player, data, generation) end
	local s = SessionOf(player)
	if s.SavedGeneration ~= generation then
		s.SavedGeneration = generation
		local loadReport = MigrationReportOf(player)
		if loadReport and loadReport.Changed then changed = true end
	end
	if changed then RequestSave(player) end
	return true
end

Rebuild = function(player, data, generation)
	local old = Runtime[player]
	local reattach = nil
	if old then
		--.. same profile generation (e.g. the Pets array was replaced by a restore): come back on the same plot
		if old.Attached and old.Plot and old.Generation == generation then reattach = old.Plot end
		Detach(player, "Rebuild", true)
	end
	Runtime[player] = BuildRuntime(player, data, generation, old)
	ActiveDirty = true
	Diag.Rebuilds += 1
	if reattach and AttrOf(player, "BaseRestored") == true and OwnerOf(reattach) == player.UserId then
		PetService.AttachPlot(player, reattach)
	end
	PendingDeltas[player] = nil
	local s = Session[player]
	if s and s.ClientReady and not SendingFull[player] then SendFull(player) end
end

function PetService.AttachPlot(player, plot)
	if plot == nil then return 0 end
	if not EnsureRuntime(player) then return 0 end
	local rt = Runtime[player]
	if not rt or rt.Frozen or Frozen[player] then return 0 end
	if OwnerOf(plot) ~= player.UserId then return 0 end
	if rt.Attached and rt.Plot ~= plot then Detach(player, "Rebuild", true) end
	rt.Plot = plot
	rt.Attached = true
	local spawned = 0
	for _, id in ipairs(RosterList(GetDataOf(player))) do
		local rp = rt.Pets[id]
		if rp and not rp.Model and not rp.PresentationPending and rp.Stats.Valid then
			if SpawnPet(player, rt, rp, nil) then spawned += 1 end
		end
	end
	ActiveDirty = true
	RefreshStatuses(player, rt, true)
	if not UpdateLock(player) then RunAutoEquip(player, rt) end
	return spawned
end

function PetService.DetachPlot(player, reason)
	Detach(player, reason, false)
end

--.. close-phase safe: gates only on the profile still being there
function PetService.SyncRecords(player, anchor)
	local data = GetDataOf(player)
	if data == nil then return end
	local rt = Runtime[player]
	if not rt or not rt.Plot then return end
	local base = data.Base
	if type(base) ~= "table" or type(base.Pets) ~= "table" then return end
	local byId = rt.Index.ById
	if base.Pets ~= rt.PetsArray then -- stale index: write into the profile's own records
		byId = {}
		for _, rec in ipairs(base.Pets) do
			if type(rec) == "table" and IsValidId(rec.Id) and not byId[rec.Id] then byId[rec.Id] = rec end
		end
	end
	if typeof(anchor) ~= "CFrame" then
		local ok, result = pcall(AnchorOf, rt.Plot)
		if not ok then return end
		anchor = result
	end
	local now = Clock()
	for id, rp in pairs(rt.Spawned) do
		local rec = byId[id]
		if rec and rp.Model then
			local pos = PetMotion.Sample(rp.Segment, now)
			if pos then
				local lp = anchor:PointToObjectSpace(pos)
				if Finite(lp.X) and Finite(lp.Z) then rec.Pos = {lp.X, 0, lp.Z} end
			end
			local remaining = rp.Record.AbilityRemaining
			if not Finite(remaining) or remaining < 0 or remaining > ABILITY_PERIOD then remaining = ABILITY_PERIOD end
			rec.AbilityRemaining = remaining
		end
	end
end

function PetService.HasSourceEgg(player, eggId)
	if not IsValidId(eggId) then return false end
	local rt = Runtime[player]
	if rt and IsCurrent(player, rt) then return rt.Index.BySourceEgg[eggId] ~= nil end
	local data = GetDataOf(player)
	local pets = data and type(data.Base) == "table" and data.Base.Pets or nil
	return ScanSourceEgg(pets, eggId) ~= nil
end

--.. the synchronous hatch commit (8.2 step 4); does NOT RequestSave (the caller does)
function PetService.GrantFromEgg(player, egg, petKey)
	local data = GetDataOf(player)
	if not data then return nil, {Error = "NotLoaded"} end
	if Frozen[player] or IsClosing(player) then return nil, {Error = "Closing"} end
	local ok, err = EnsureRuntime(player)
	if not ok then return nil, {Error = err or "NotLoaded"} end
	local rt = Runtime[player]
	if not rt or rt.Frozen then return nil, {Error = "Closing"} end
	data = GetDataOf(player)
	local base = data and data.Base
	if type(base) ~= "table" or type(base.Pets) ~= "table" or base.Pets ~= rt.PetsArray then return nil, {Error = "NotLoaded"} end
	local rosterSet, queued = RosterSet(data), 0
	for _, id in ipairs(rt.PendingAutoEquip) do
		if rt.Pets[id] and not rosterSet[id] then queued += 1 end -- slots already promised this lock
	end
	local record, info = Core.GrantFromEgg(base, egg, petKey, {
		GenerateId = GenerateId, Now = os.time(), AllowRoster = true, Locked = PetService.IsCombatLocked(player),
		Slots = SlotsOf(player), MaxOwned = MAX_OWNED, IsSpawnable = IsSpawnable, Index = rt.Index, Pending = queued,
	})
	if not record then
		if info and info.Error == "InventoryFull" then
			Diag.InventoryFull += 1
			local s = SessionOf(player)
			if s.ClientReady and os.clock() - s.LastInventoryFull >= INVENTORY_FULL_PUSH then
				s.LastInventoryFull = os.clock()
				SendDelta(player, nil, {Ok = false, Action = "Hatch", Error = "InventoryFull"})
			end
		end
		return nil, info
	end
	if info.Duplicate then return record, info end
	--.. (c) runtime entry + delta
	rt.KnownCount = #base.Pets
	Diag.OwnedMax = math.max(Diag.OwnedMax, rt.KnownCount)
	local rp = NewRuntimePet(record)
	if HasUnknownTraits(rp.Stats) then Diag.UnknownTraits += 1 end
	rt.Pets[record.Id] = rp
	if info.Equipped then
		rp.PresentationPending = true -- spawns when its reveal is done (FinishPresentation)
	elseif info.AutoEquipAfterCombat then
		--.. (2026-09-22, review #9) pending too: an unlock mid-reveal equips it, but only the reveal's end spawns it
		rp.PresentationPending = true
		table.insert(rt.PendingAutoEquip, record.Id)
	end
	RefreshStatus(player, rt, rp, info.Equipped, false)
	QueueDelta(player, record.Id, info.Equipped)
	return record, info
end

--.. the reveal is over (or its fallback fired): clear PresentationPending, spawn when still due. Returns
--.. true when the presentation was finished for a current pet (spawned or not)
function PetService.FinishPresentation(player, petId, spot, generation)
	local rt = Runtime[player]
	local rp = rt and IsValidId(petId) and rt.Pets[petId] or nil
	if not rp then return false end
	rp.PresentationPending = false
	rp.PendingSpot = nil
	local data = GetDataOf(player)
	local inRoster = RosterSet(data)[petId] ~= nil
	if (generation ~= nil and generation ~= rt.Generation) or Frozen[player] or rt.Frozen or not data then
		RefreshStatus(player, rt, rp, inRoster, true)
		return false
	end
	if inRoster and HasPlot(player, rt) and rp.Model == nil and rp.Stats.Valid then
		SpawnPet(player, rt, rp, typeof(spot) == "Vector3" and spot or nil)
	end
	RefreshStatus(player, rt, rp, inRoster, true)
	return true
end

local function RosterGuard(player)
	local data = GetDataOf(player)
	if not data then return nil, nil, "NotLoaded" end
	if Frozen[player] or IsClosing(player) then return nil, nil, "Closing" end
	local ok, err = EnsureRuntime(player)
	if not ok then return nil, nil, err or "NotLoaded" end
	local rt = Runtime[player]
	if not rt then return nil, nil, "NotLoaded" end
	if rt.Frozen then return nil, nil, "Closing" end
	data = GetDataOf(player)
	if not data or type(data.Base) ~= "table" then return nil, nil, "NotLoaded" end
	return rt, data
end

function PetService.Equip(player, petId)
	local rt, data, err = RosterGuard(player)
	if not rt then return false, err end
	local base = data.Base
	local roster = RosterArray(base)
	local newRoster, refusal = Core.Equip(roster, petId, {
		Slots = SlotsOf(player), Locked = PetService.IsCombatLocked(player), HasPlot = HasPlot(player, rt),
		IsOwned = function(id) return rt.Pets[id] ~= nil end,
		IsEquippable = function(id)
			local rp = rt.Pets[id]
			return rp ~= nil and rp.Stats.Valid == true and IsSpawnable(rp.Record.Pet)
		end,
	})
	if not newRoster then return false, refusal end
	if table.find(roster, petId) then return true end -- already equipped: nothing to do
	SetRoster(base, newRoster)
	local rp = rt.Pets[petId]
	rp.Record.AbilityRemaining = ABILITY_PERIOD -- a fresh 60 s: equipping never gives an instant roll
	local queued = table.find(rt.PendingAutoEquip, petId)
	if queued then table.remove(rt.PendingAutoEquip, queued) end
	if not rp.PresentationPending and not rp.Model then SpawnPet(player, rt, rp, nil) end
	RefreshStatus(player, rt, rp, true, false)
	ActiveDirty = true
	QueueDelta(player, petId, true)
	RequestSave(player)
	return true
end

function PetService.Unequip(player, petId)
	local rt, data, err = RosterGuard(player)
	if not rt then return false, err end
	if PetService.IsCombatLocked(player) then return false, "CombatLocked" end
	local queued = table.find(rt.PendingAutoEquip, petId)
	if queued then table.remove(rt.PendingAutoEquip, queued) end
	local base = data.Base
	local roster = RosterArray(base)
	if not table.find(roster, petId) then return true end -- absent: nothing to do
	SetRoster(base, Core.Unequip(roster, petId))
	local rp = rt.Pets[petId]
	if rp then
		if rp.Model or rp.Producer then Despawn(rt, rp) end
		rp.Record.AbilityRemaining = ABILITY_PERIOD
		RefreshStatus(player, rt, rp, false, false)
	end
	ActiveDirty = true
	QueueDelta(player, petId, true)
	RequestSave(player)
	return true
end

--.. 2026-09-23 (Manage panel): SELL - the pet leaves the roster, its record leaves Data.Base.Pets for good and
--.. the client hears a Delta with Removed. Refused while combat-locked or mid-reveal (PresentationPending).
--.. The caller pays the cash (ManageService: ManageConfig.PetSellValue(stats.Income)).
--.. Returns true, nil, record, stats | false, err
function PetService.Sell(player, petId)
	local rt, data, err = RosterGuard(player)
	if not rt then return false, err end
	if PetService.IsCombatLocked(player) then return false, "CombatLocked" end
	if not IsValidId(petId) then return false, "BadRequest" end
	local rp = rt.Pets[petId]
	if not rp then return false, "NotOwned" end
	if rp.PresentationPending then return false, "Unavailable" end
	local base = data.Base
	if type(base.Pets) ~= "table" or base.Pets ~= rt.PetsArray then return false, "NotLoaded" end
	local queued = table.find(rt.PendingAutoEquip, petId)
	if queued then table.remove(rt.PendingAutoEquip, queued) end
	local roster = RosterArray(base)
	if table.find(roster, petId) then SetRoster(base, Core.Unequip(roster, petId)) end
	if rp.Model or rp.Producer then Despawn(rt, rp) end
	local index
	for i, rec in ipairs(base.Pets) do
		if rec == rp.Record then index = i break end
	end
	if index then table.remove(base.Pets, index) end
	rt.KnownCount = #base.Pets
	rt.Pets[petId] = nil
	rt.Spawned[petId] = nil
	if rt.Index.ById[petId] == rp.Record then rt.Index.ById[petId] = nil end
	local eggId = rp.Record.SourceEggId
	if IsValidId(eggId) and rt.Index.BySourceEgg[eggId] == rp.Record then rt.Index.BySourceEgg[eggId] = nil end
	ActiveDirty = true
	QueueDelta(player, nil, true, false, petId)
	RequestSave(player)
	return true, nil, rp.Record, rp.Stats
end

--.. budget (a client request only: the session's ChurnLimiter) = the models this swap would spawn + despawn;
--.. over it the request is refused "RateLimited" before anything changes (review #5)
local function EquipBestWith(player, mode, budget)
	local rt, data, err = RosterGuard(player)
	if not rt then return false, err end
	if not SORT_MODES[mode] then return false, "BadRequest" end
	if PetService.IsCombatLocked(player) then return false, "CombatLocked" end
	if not HasPlot(player, rt) then return false, "NoPlot" end
	local base = data.Base
	local old = CopyRoster(RosterArray(base))
	local roster = Core.EquipBest(base.Pets, function(rec)
		local rp = rt.Pets[rec.Id]
		return rp and rp.Stats or PetStats.Calculate(rec)
	end, IsSpawnable, mode, SlotsOf(player))
	local oldSet, newSet = {}, {}
	for _, id in ipairs(old) do oldSet[id] = true end
	for _, id in ipairs(roster) do newSet[id] = true end
	local same = #old == #roster
	for i, id in ipairs(roster) do
		if old[i] ~= id then same = false end
	end
	if budget then
		local churn = 0
		for _, id in ipairs(old) do
			local rp = rt.Pets[id]
			if not newSet[id] and rp and (rp.Model or rp.Producer) then churn += 1 end
		end
		for _, id in ipairs(roster) do
			local rp = rt.Pets[id]
			if not oldSet[id] and rp and not rp.PresentationPending and not rp.Model then churn += 1 end
		end
		if churn > 0 and not budget:Take(os.clock(), churn) then return false, "RateLimited" end
	end
	table.clear(rt.PendingAutoEquip)
	SetRoster(base, roster)
	for _, id in ipairs(old) do -- leaving the team: countdown back to 60, model gone
		if not newSet[id] then
			local rp = rt.Pets[id]
			if rp then
				if rp.Model or rp.Producer then Despawn(rt, rp) end
				rp.Record.AbilityRemaining = ABILITY_PERIOD
				QueueDelta(player, id)
			end
		end
	end
	for _, id in ipairs(roster) do -- joining: a fresh 60 s; members that stay keep their countdown
		if not oldSet[id] then
			local rp = rt.Pets[id]
			rp.Record.AbilityRemaining = ABILITY_PERIOD
			if not rp.PresentationPending and not rp.Model then SpawnPet(player, rt, rp, nil) end
			QueueDelta(player, id)
		end
	end
	RefreshStatuses(player, rt, true)
	ActiveDirty = true
	QueueDelta(player, nil, true)
	if not same then RequestSave(player) end
	return true
end

--.. the API (PetDev, server callers) is never throttled; client requests go through HandleRequest
function PetService.EquipBest(player, mode)
	return EquipBestWith(player, mode, nil)
end

local ROSTER_ACTIONS = {
	Equip = function(player, cleaned) return PetService.Equip(player, cleaned.PetId) end,
	Unequip = function(player, cleaned) return PetService.Unequip(player, cleaned.PetId) end,
	EquipBest = function(player, cleaned) return EquipBestWith(player, cleaned.SortMode, SessionOf(player).ChurnLimiter) end,
}

--.. PetRequest (PetServer): limiters first (whatever the load state), then validation, dispatch, reply
function PetService.HandleRequest(player, request)
	if player == nil or Departed(player) then return end -- a request queued before the leave: nobody to answer
	local s = SessionOf(player)
	local now = os.clock()
	local action = type(request) == "table" and request.Action or nil
	if action == "GetState" then
		if not s.StateLimiter:Take(now) then
			Diag.DeniedRequests += 1
			return -- GetState is fire-and-forget: over the limit it is simply dropped
		end
	elseif not s.RosterLimiter:Take(now) then
		Diag.DeniedRequests += 1
		if s.ReplyLimiter:Take(now) then
			SendDelta(player, CleanRequestId(request), {Ok = false, Action = ActionName(action), Error = "RateLimited"})
		end
		return
	end
	local valid, cleaned = Core.ValidateRequest(request)
	if not valid then
		Diag.DeniedRequests += 1
		SendDelta(player, CleanRequestId(request), {Ok = false, Action = ActionName(action), Error = cleaned})
		return
	end
	if cleaned.Action == "GetState" then
		s.ClientReady = true
		SendFull(player, cleaned.RequestId, nil)
		return
	end
	local ok, done, err = pcall(ROSTER_ACTIONS[cleaned.Action], player, cleaned)
	if not ok then
		WarnOnce("request:" .. cleaned.Action, ("[PetService] %s failed: %s"):format(cleaned.Action, tostring(done)))
		done, err = false, "Unavailable"
	end
	if done ~= true then Diag.DeniedRequests += 1 end
	SendDelta(player, cleaned.RequestId, {Ok = done == true, Action = cleaned.Action, Error = done ~= true and (err or "Unavailable") or nil})
end

function PetService.IsCombatLocked(player)
	if PhaseOf() == "Night" then return true end
	return player ~= nil and AttrOf(player, "RaidLive") == true
end

function PetService.GetActivePets()
	if ActiveDirty then
		ActiveDirty = false
		local list = {}
		for player, rt in pairs(Runtime) do
			if rt.Attached and not rt.Frozen and not Frozen[player] then
				for id, rp in pairs(rt.Spawned) do
					if rp.Status == "Active" and rp.Model then
						table.insert(list, {PetId = id, Player = player, UserId = player.UserId, Model = rp.Model, Plot = rt.Plot, Stats = rp.Stats})
					end
				end
			end
		end
		ActiveCache = list
	end
	return ActiveCache
end

function PetService.GetLogicalPosition(petId, now)
	if not IsValidId(petId) then return nil end
	local current = Clock()
	if not Finite(now) or math.abs(now - current) > CLOCK_SANITY then now = current end -- a foreign clock (os.clock) never reaches the sample
	for _, rt in pairs(Runtime) do
		local rp = rt.Pets[petId]
		if rp then
			if not rp.Model then return nil end
			return (PetMotion.Sample(rp.Segment, now))
		end
	end
	return nil
end

function PetService.GetFullState(player)
	local s = SessionOf(player)
	return BuildFull(player, s.Revision, nil, nil, false)
end

--.. IncomeService.OnTotalsChanged handler (subscribed in Start): a throttled, unrevisioned Kind "Totals"
function PetService.PushTotals(player, totals)
	if player == nil then return end
	TotalsDirty[player] = type(totals) == "table" and totals or true
end

--.. close phase (DataService.OnBeforeClose order 10): no more roster actions, grants, presentations or rolls
function PetService.Freeze(player)
	if GetDataOf(player) == nil then return end
	Frozen[player] = true
	local rt = Runtime[player]
	if rt then rt.Frozen = true end
	ActiveDirty = true
end

function PetService.GetDiagnostics()
	local out = {}
	for key, value in pairs(Diag) do out[key] = value end
	local active, reserve, invalid = 0, 0, 0
	for _, rt in pairs(Runtime) do
		for _, rp in pairs(rt.Pets) do
			if rp.Status == "Active" then
				active += 1
			elseif rp.Status == "Reserve" then
				reserve += 1
			elseif rp.Status == "Invalid" then
				invalid += 1
			end
		end
	end
	out.Active, out.Reserve, out.Invalid = active, reserve, invalid
	return out
end

--..Studio-only helpers for PetServer's PetDev hook ("roll:<PetId>" / "proc:<PetId>")..--
local function DevPet(player, petId)
	if not RunService:IsStudio() then return nil end
	local rt = Runtime[player]
	return rt and IsValidId(petId) and rt.Pets[petId] or nil
end

function PetService.DevSetAbilityRemaining(player, petId, seconds)
	local rp = DevPet(player, petId)
	if not rp or not Finite(seconds) then return false end
	rp.Record.AbilityRemaining = math.clamp(seconds, 0, ABILITY_PERIOD)
	QueueDelta(player, petId)
	return true
end

function PetService.DevForceProc(player, petId)
	local rp = DevPet(player, petId)
	if not rp then return false end
	rp.ForceProc = true
	return true
end

--..Scheduler (ONE Heartbeat for every pet in the server)..--
local function Due(key, period, now)
	local last = LastRun[key]
	if last == nil or now < last then
		LastRun[key] = now
		return false, 0
	end
	if now - last >= period then
		LastRun[key] = now
		return true, now - last
	end
	return false, 0
end

local function Proc(player, rp, now)
	local buffs = Deps.PetBuffService
	if not buffs or type(buffs.Grant) ~= "function" then
		Diag.ProcSkipped += 1
		return
	end
	local source = {PetId = rp.Id, DisplayName = tostring(rp.Stats.DisplayName), From = PetMotion.Sample(rp.Segment, now)}
	local ok, granted, detail = pcall(buffs.Grant, player, source, rp.Stats.Ability, now)
	if not ok then
		Diag.ProcErrors += 1
		WarnOnce("grant", "[PetService] PetBuffService.Grant: " .. tostring(granted))
	elseif granted then
		Diag.ProcSuccess += 1
	elseif detail == "NoTarget" then
		Diag.ProcNoTarget += 1
	else
		Diag.ProcErrors += 1
	end
end

local function AbilityStep(now, dt)
	for player, rt in pairs(Runtime) do
		if rt.Attached and not rt.Frozen and not Frozen[player] and not IsClosing(player)
			and AttrOf(player, "BaseRestored") == true and IsCurrent(player, rt) then
			local entries, byId = {}, {}
			for _, id in ipairs(RosterList(GetDataOf(player))) do
				local rp = rt.Pets[id]
				if rp and not byId[id] and rp.Status == "Active" and rp.Model and rp.Stats.Valid and rp.Stats.Ability ~= "None" then
					byId[id] = rp
					table.insert(entries, {Id = id, Remaining = rp.Record.AbilityRemaining, Chance = rp.Stats.AbilityChance, Force = rp.ForceProc})
				end
			end
			if #entries > 0 then
				local rolls = Core.StepAbility(entries, dt, AbilityRng)
				for _, entry in ipairs(entries) do byId[entry.Id].Record.AbilityRemaining = entry.Remaining end
				for _, roll in ipairs(rolls) do
					local rp = byId[roll.Id]
					rp.ForceProc = nil
					Diag.Rolls += 1
					if roll.Success then Proc(player, rp, now) end
					QueueDelta(player, roll.Id)
				end
				if #rolls > 0 then RequestSave(player) end
			end
		end
	end
end

local function RoamStep(now)
	for _, rt in pairs(Runtime) do
		if rt.Attached and rt.Plot then
			for _, rp in pairs(rt.Spawned) do
				if rp.Model and not rp.Despawning and now >= rp.IdleUntil then
					local ok, err = pcall(PlanLeg, rt, rp, now)
					if not ok then WarnOnce("roam", "[PetService] roam planning: " .. tostring(err)) end
				end
			end
		end
	end
end

--.. OD-13: a roster pet without a model comes back as soon as its asset is there again
local function RetryStep()
	for player, rt in pairs(Runtime) do
		if rt.Attached and not rt.Frozen and not Frozen[player] then
			for _, id in ipairs(RosterList(GetDataOf(player))) do
				local rp = rt.Pets[id]
				if rp and rp.Status == "Unavailable" and not rp.Model and not rp.PresentationPending
					and (type(Deps.Spawner) == "function" or IsSpawnable(rp.Record.Pet)) then
					if SpawnPet(player, rt, rp, nil) then RefreshStatus(player, rt, rp, true, true) end
				end
			end
		end
	end
end

local function StaleStep()
	for player, rt in pairs(Runtime) do
		if not Frozen[player] and GetDataOf(player) and not IsCurrent(player, rt) then
			local ok, err = pcall(PetService.EnsureProfileState, player)
			if not ok then WarnOnce("stale", "[PetService] runtime refresh failed: " .. tostring(err)) end
		end
	end
end

local function LockStep()
	for player in pairs(Runtime) do UpdateLock(player) end
	for _, player in ipairs(Players:GetPlayers()) do
		if not Runtime[player] then UpdateLock(player) end
	end
end

local function SizeStep()
	for player, rt in pairs(Runtime) do
		if rt.Attached then
			local data = GetDataOf(player)
			if data then
				local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
				if ok and type(encoded) == "string" then
					Diag.ProfileBytesMax = math.max(Diag.ProfileBytesMax, #encoded)
					if #encoded > PROFILE_SIZE_WARN then
						WarnOnce("size", ("[PetService] %s's profile is %d bytes"):format(tostring(player.Name), #encoded))
					end
				end
			end
		end
	end
end

local function TotalsStep()
	local wall = os.clock()
	for player, totals in pairs(TotalsDirty) do
		local s = Session[player]
		if not s or not s.ClientReady then
			TotalsDirty[player] = nil
		elseif wall - s.LastTotalsPush >= TOTALS_PUSH then
			TotalsDirty[player] = nil
			s.LastTotalsPush = wall
			Send(player, {Kind = "Totals", Totals = TotalsOf(player, totals), ServerTime = Clock()})
		end
	end
end

--.. the Heartbeat body (also driven directly by tests with an injected Clock)
function PetService.Tick(now)
	now = Finite(now) and now or Clock()
	TotalsStep()
	if Due("Roam", ROAM_PLAN, now) then RoamStep(now) end
	local due, dt = Due("Ability", ABILITY_TICK, now)
	if due then AbilityStep(now, math.min(dt, MAX_TICK_DT)) end
	if Due("Stale", STALE_POLL, now) then StaleStep() end
	if Due("Lock", LOCK_POLL, now) then LockStep() end
	if Due("Retry", UNAVAILABLE_RETRY, now) then RetryStep() end
	if Due("Size", PROFILE_SIZE_PERIOD, now) then SizeStep() end
end

--..Wiring..--
local function OnPlotOwner(plot)
	local owner = plot:GetAttribute("Owner")
	for player, rt in pairs(Runtime) do
		if rt.Plot == plot and owner ~= player.UserId then Detach(player, "PlotLost", false) end
	end
	--.. what is left in plot.Pets belongs to nobody attached here any more (runtime models only)
	local folder = plot:FindFirstChild("Pets")
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if owner == nil or child:GetAttribute("Owner") ~= owner then child:Destroy() end
		end
	end
end

local function WirePlot(plot)
	if not plot:IsA("BasePart") or PlotConns[plot] then return end
	PetsFolderOf(plot)
	PlotConns[plot] = {
		plot:GetAttributeChangedSignal("Owner"):Connect(function() OnPlotOwner(plot) end),
		--.. PlotUpgradeService sets Size then CFrame: replan once both are in
		plot:GetPropertyChangedSignal("Size"):Connect(function()
			if ResizeQueued[plot] then return end
			ResizeQueued[plot] = true
			task.defer(ReplanPlot, plot)
		end),
	}
end

local function WirePlots(plots)
	for _, plot in ipairs(plots:GetChildren()) do WirePlot(plot) end
	plots.ChildAdded:Connect(function(child) task.defer(WirePlot, child) end)
end

local function WatchPlayer(player)
	if PlayerConns[player] then return end
	PlayerConns[player] = {
		player:GetAttributeChangedSignal("RaidLive"):Connect(function() UpdateLock(player) end),
	}
	UpdateLock(player)
end

local function DropPlayer(player)
	pcall(Detach, player, "Left", true)
	Runtime[player] = nil
	Session[player] = nil
	Frozen[player] = nil
	LockState[player] = nil
	PendingDeltas[player] = nil
	TotalsDirty[player] = nil
	SendingFull[player] = nil
	local conns = PlayerConns[player]
	PlayerConns[player] = nil
	if conns then
		for _, conn in ipairs(conns) do conn:Disconnect() end
	end
	ActiveDirty = true
end

--.. PlayerRemoving handlers run in any order (8.3): when this one runs before DataService's, that one's
--.. close phase (Freeze at order 10) re-keys the Player afterwards, so the drop runs once more deferred,
--.. after every handler of this leave (the BaseSave / PlotService teardown pattern)
local function OnPlayerRemoving(player)
	if GetDataOf(player) ~= nil then pcall(PetService.SyncRecords, player) end
	DropPlayer(player)
	task.defer(DropPlayer, player)
end
PetService.HandlePlayerRemoving = OnPlayerRemoving -- extra: tests drive the leave directly

local function OnReset(player)
	if GetDataOf(player) == nil then return end
	Detach(player, "Reset", true)
	PendingDeltas[player] = nil
	local ok, err = pcall(PetService.EnsureProfileState, player) -- new generation: fresh runtime, Full if the client is ready
	if not ok then WarnOnce("reset", "[PetService] reset rebuild failed: " .. tostring(err)) end
end

--.. BaseSave's Restore may have run before this module started: attach everyone already restored
local function LateStartSweep()
	for _, player in ipairs(Players:GetPlayers()) do
		local rt = Runtime[player]
		if player:GetAttribute("BaseRestored") == true and not (rt and rt.Attached) then
			local plot = PlotOf(player)
			if plot then
				pcall(PetService.EnsureProfileState, player)
				pcall(PetService.AttachPlot, player, plot)
			end
		end
	end
end

function PetService.Start()
	if Started then return end
	if not Inited then
		warn("[PetService] Start before Init - not started")
		return
	end
	Started = true
	local plots = PlotsFolder()
	if plots then
		WirePlots(plots)
	else
		task.spawn(function()
			local map = workspace:WaitForChild("Map", 60)
			local lobby = map and map:WaitForChild("Lobby", 60)
			local found = lobby and lobby:WaitForChild("Plots", 60)
			if found then WirePlots(found) else warn("[PetService] no workspace.Map.Lobby.Plots - plot pets cannot spawn") end
		end)
	end
	workspace:GetAttributeChangedSignal("CyclePhase"):Connect(function()
		for player in pairs(Runtime) do UpdateLock(player) end
		for _, player in ipairs(Players:GetPlayers()) do UpdateLock(player) end
	end)
	Players.PlayerAdded:Connect(WatchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do WatchPlayer(player) end
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	if type(DataService.OnBeforeClose) == "function" then
		DataService.OnBeforeClose(function(player) PetService.Freeze(player) end, 10)
		DataService.OnBeforeClose(function(player) PetService.SyncRecords(player) end, 30)
	else
		warn("[PetService] DataService has no OnBeforeClose - pet positions/countdowns save with the next snapshot only")
	end
	if type(DataService.OnProfileReset) == "function" then DataService.OnProfileReset(OnReset) end
	local income = Deps.IncomeService
	if income and type(income.OnTotalsChanged) == "function" then
		local ok, err = pcall(income.OnTotalsChanged, PetService.PushTotals)
		if not ok then WarnOnce("totals", "[PetService] OnTotalsChanged: " .. tostring(err)) end
	end
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(PetService.Tick)
		if not ok then
			Diag.SchedulerErrors += 1
			WarnOnce("tick", "[PetService] scheduler: " .. tostring(err))
		end
	end)
	LateStartSweep()
	StartOk = true
	print(("[PetService] started: %d slots, ability roll every %ds of active time"):format(SLOTS, ABILITY_PERIOD))
end

return PetService
