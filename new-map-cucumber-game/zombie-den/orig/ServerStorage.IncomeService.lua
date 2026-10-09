--[[
	IncomeService  (ModuleScript, ServerStorage)
	The one Cash-paying income loop (2026-09-22, pet system): placed cucumbers AND active pets are
	"producers" that earn into their owner's Cash on ONE shared deadline tick (PetBalance.TIMING.INCOME_TICK,
	1 s). It replaces LeaderstatsService's old PayIncome loop, which stays behind as a dormant fallback that only
	runs when this service never started (see LeaderstatsService).
	  * Producers: every Model tagged "PlacedCucumber" (registered on tag add whatever its Parent is - the tag
	    goes on before parenting) and every pet PetService registers after a successful spawn
	    (SetPetProducer / RemovePetProducer). Cached per producer: owner UserId, BaseRate, temporary modifiers,
	    the time it was last settled. A cucumber pays while it is tagged, has a numeric Owner and stands in the
	    workspace (the old rule, so CucumberBase = the old CashPerSec); a pet while its model is in the workspace.
	  * Settlement: each tick pays the REAL elapsed time since the producer's last settlement (a stall pays at
	    most INCOME_MAX_CATCHUP = 5 s, diag CatchupClamps), integrating BaseRate x min(2, product of the live
	    modifier Mults) with the interval split at every cached modifier expiry. A state change (buff added or
	    expired, re-rate, owner change, tag removed, pet replaced / removed) first settles the producer up to that
	    moment into the owner's ledger, so the next tick never pays that span twice; a removal never undoes cash
	    already earned. Amounts are never rounded (Cash stays fractional end to end).
	  * Credit: ONE DataService.Increment(player, "Cash", total, quiet) per owner per tick (one HUD pop). Only
	    when it succeeds do that owner's cucumbers join Remotes.CucumberIncome (models, amounts) and the pets
	    Remotes.PetIncome (models, amounts, petIds); each is fired once per tick to all clients.
	  * Owners: ledgers keyed by UserId, state Live -> Flushed (FlushOwner, the DataService pre-close hook and
	    the only path that may credit a closing profile) -> Forgotten (PlayerRemoving). A settlement for an owner
	    that is not Live or not loaded is dropped (diag LateSettles); a profile reset drops the ledger, restarts
	    the owner's producer clocks and HOLDS every producer registered before it (2026-09-22, S3 residue: the
	    deferred TagRemoved of a cucumber the reset destroyed came 0.3 ms later and paid that gap into the fresh
	    profile). A held producer's settlements are discarded (LateSettles) until a tick finds it eligible (it
	    re-joins from that tick) or it is re-keyed / re-registered, so nothing earned before the reset ever lands.
	  * Attributes it owns on placed cucumbers: "BaseRate" and "Rate" (the effective rate the card prints). It
	    never reads Rate back as an input.
	  * Totals per player {CucumberBase, Cucumber, Pet, Total}: Total -> player.Data.CashPerSec (unsaved);
	    CucumberBase (no buffs, no pets) is the raid threat input (GetThreatIncome). OnTotalsChanged listeners
	    (LeaderstatsService "Cash/s", PetService's footer push) only hear real changes.
	Bootstrapped by ServerScriptService.PetServer: IncomeService.Init({DataService, ModifiersOf, Clock}), Start().
	Core = the pure maths plus Core.NewEngine(env): the whole ledger with the world injected (unit tests run it
	on plain tables, no instances).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))

local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function Positive(x, fallback)
	if Finite(x) and x > 0 then return x end
	return fallback
end

--.. PetBalance numbers once it is installed (stage S1), else the same literals (CONTRACTS section 9)
local PetBalance = {}
do
	local module = Modules:FindFirstChild("PetBalance")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then PetBalance = result end
	end
end
local TIMING = type(PetBalance.TIMING) == "table" and PetBalance.TIMING or {}

--..Config..--
local PLACED_TAG = "PlacedCucumber"
local CASH_KEY = "Cash" -- the DataService key the income lands in
local CASH_PER_SEC = "CashPerSec" -- player.Data NumberValue (derived, never saved)
local CUCUMBER_REMOTE = "CucumberIncome" -- (models, amounts) -> all clients, once per tick
local PET_REMOTE = "PetIncome" -- (models, amounts, petIds) -> all clients, same tick
local INCOME_TICK = Positive(TIMING.INCOME_TICK, 1)
local INCOME_MAX_CATCHUP = Positive(TIMING.INCOME_MAX_CATCHUP, 5)
local RATE_HARD_CAP = Positive(PetBalance.RATE_HARD_CAP, 2)
local FLUSH_ORDER = 20 -- DataService.OnBeforeClose: after PetService.Freeze (10), before SyncRecords (30)
local REFRESH_ATTRIBUTES = {"Zone", "TypeName", "Golden", "Material", "Mutations", "SizeTier"}
local MAX_MODS = 8 -- modifiers cached per cucumber (Yield + Haste today)
local TOTALS_EPSILON = 1e-6 -- relative change that counts as "totals changed"
local MAX_ID_LENGTH = 64
local MAX_NOW_SKEW = 5 -- seconds: a caller's `now` further than this from the Clock is replaced by the Clock
local WARN_INTERVAL = 60

--..Helpers..--
local LastWarn = {}
local function WarnOnce(key, message)
	local now = os.clock()
	if LastWarn[key] and now - LastWarn[key] < WARN_INTERVAL then return end
	LastWarn[key] = now
	warn("[IncomeService] " .. message)
end

local function IsValidId(id)
	return type(id) == "string" and #id >= 1 and #id <= MAX_ID_LENGTH
end

local function UserIdOf(player)
	if typeof(player) == "Instance" then
		return player:IsA("Player") and player.UserId or nil
	end
	if type(player) == "table" and Finite(player.UserId) then return player.UserId end
	return nil
end

local function ZeroTotals()
	return {CucumberBase = 0, Cucumber = 0, Pet = 0, Total = 0}
end

--..Core: pure maths (no state, no instances)..--
local Core = {}
Core.Finite = Finite
Core.IsValidId = IsValidId

--.. product of the Mults live at time t (live = t < ExpiresAt), capped
function Core.EffectiveMult(mods, t, cap)
	cap = Positive(cap, RATE_HARD_CAP)
	local mult = 1
	if type(mods) == "table" and Finite(t) then
		for _, mod in ipairs(mods) do
			if type(mod) == "table" and Finite(mod.Mult) and mod.Mult > 0 and Finite(mod.ExpiresAt) and t < mod.ExpiresAt then
				mult *= mod.Mult
			end
		end
	end
	return math.min(cap, mult)
end

--.. the start of the span to pay: a stall pays at most maxCatchup seconds
function Core.ClampElapsed(t0, t1, maxCatchup)
	if not Finite(t0) or not Finite(t1) or t0 > t1 then return t1, false end
	maxCatchup = Positive(maxCatchup, INCOME_MAX_CATCHUP)
	if t1 - t0 > maxCatchup then return t1 - maxCatchup, true end
	return t0, false
end

--.. integral of baseRate x EffectiveMult(t) over [t0, t1], split at every modifier expiry inside it
function Core.SettleAmount(baseRate, mods, t0, t1, cap)
	if not (Finite(baseRate) and baseRate > 0 and Finite(t0) and Finite(t1) and t1 > t0) then return 0 end
	cap = Positive(cap, RATE_HARD_CAP)
	local cuts = {}
	if type(mods) == "table" then
		for _, mod in ipairs(mods) do
			if type(mod) == "table" and Finite(mod.ExpiresAt) and mod.ExpiresAt > t0 and mod.ExpiresAt < t1 then
				table.insert(cuts, mod.ExpiresAt)
			end
		end
		table.sort(cuts)
	end
	local amount, from = 0, t0
	for _, cut in ipairs(cuts) do
		if cut > from then
			amount += baseRate * Core.EffectiveMult(mods, (from + cut) * 0.5, cap) * (cut - from)
			from = cut
		end
	end
	amount += baseRate * Core.EffectiveMult(mods, (from + t1) * 0.5, cap) * (t1 - from)
	return Finite(amount) and amount or 0
end

--.. relative change test for the totals push
function Core.TotalsChanged(a, b)
	if not Finite(a) or not Finite(b) then return a ~= b end
	return math.abs(a - b) > TOTALS_EPSILON * math.max(math.abs(a), math.abs(b))
end

--[[ Core.NewEngine(env) -> engine: the complete producer registry / ledger / tick. Everything that touches the
	world comes through env (the real one is built in IncomeService.Init; tests pass plain-table fakes):
	  Clock() -> number                        DataService {GetData, IsLoaded, Increment, IsClosing?}
	  ModifiersOf(model, now) -> {Modifier}     BaseRateOf(model) -> number
	  IsTagged(model), InWorld(model) -> bool   OwnerIdOf(model) -> any (validated here)
	  PlayerByUserId(userId) -> player?         IsPresent(player) -> bool (player.Parent == Players)
	  SetAttribute(model, name, value)          WriteCashPerSec(player, total)
	  Watch(model) -> {connection}              Defer(fn)          OnTotals(player, totals)
	  Warn(key, message)?                       RateCap?, MaxCatchup? (numbers)
	Engine functions are plain closures: engine.Tick(now) etc. ]]
function Core.NewEngine(env)
	local DataService = env.DataService
	local cap = Positive(env.RateCap, RATE_HARD_CAP)
	local maxCatchup = Positive(env.MaxCatchup, INCOME_MAX_CATCHUP)

	local Producers = {} -- [Model | PetId] = Producer
	local ByOwner = {} -- [UserId] = {[producer key] = true}
	local Owners = {} -- [UserId] = {Player, State = "Live"|"Flushed"|"Forgotten", LedgerCucumber, LedgerPet, LastTotals}
	local Dirty = {} -- [UserId] = true: totals to recompute on the next deferred flush
	local dirtyScheduled = false
	local producerCount = 0
	local Diag = {PaidCucumberCash = 0, PaidPetCash = 0, CatchupClamps = 0, CreditFailures = 0, InvalidRates = 0,
		LateSettles = 0, Flushes = 0}

	local E = {Producers = Producers, ByOwner = ByOwner, Owners = Owners, Diag = Diag}

	local function Warn(key, message)
		if env.Warn then pcall(env.Warn, key, message) end
	end

	--..DataService (feature-checked, pcall'd: never an error into the tick)..--
	local function HasData(player)
		local ok, data = pcall(DataService.GetData, player)
		return ok and data ~= nil
	end
	local function IsLoaded(player)
		local ok, loaded = pcall(DataService.IsLoaded, player)
		return ok and loaded == true
	end
	local function IsClosing(player)
		if type(DataService.IsClosing) ~= "function" then return false end
		local ok, closing = pcall(DataService.IsClosing, player)
		return ok and closing == true
	end
	local function Credit(player, amount)
		--.. 2026-09-23 (items): a Cash Potion doubles every payout while CashBoostUntil (server time) is ahead
		if typeof(player) == "Instance" then
			local boostUntil = tonumber(player:GetAttribute("CashBoostUntil"))
			if boostUntil and boostUntil > workspace:GetServerTimeNow() then amount *= 2 end
		end
		local ok, result = pcall(DataService.Increment, player, CASH_KEY, amount, true)
		if not ok then Warn("credit", "Increment failed: " .. tostring(result)) end
		return ok and result == true
	end

	--..Owners..--
	local function NewOwner(player)
		return {Player = player, State = "Live", LedgerCucumber = 0, LedgerPet = 0, LastTotals = nil}
	end
	--.. the entry for a UserId; a present player that is not the entry's player = a new session (rejoin)
	local function ResolveOwner(userId)
		if type(userId) ~= "number" then return nil end
		local entry = Owners[userId]
		local ok, present = pcall(env.PlayerByUserId, userId)
		if ok and present ~= nil and (entry == nil or entry.Player ~= present) then
			entry = NewOwner(present)
			Owners[userId] = entry
		end
		return entry
	end
	local function OwnerOfPlayer(player, userId)
		local entry = Owners[userId]
		if entry == nil or entry.Player ~= player then
			entry = NewOwner(player)
			Owners[userId] = entry
		end
		return entry
	end
	local function Present(player)
		local ok, present = pcall(env.IsPresent, player)
		return ok and present == true
	end
	--.. settled cash may only be stored for a Live, loaded owner (closing is fine: FlushOwner credits it)
	local function Store(p, amount, popup)
		if not (Finite(amount) and amount > 0) then return end
		if p.Held then -- registered before its owner's profile reset: the fresh profile owes it nothing
			Diag.LateSettles += 1
			return
		end
		local entry = ResolveOwner(p.OwnerId)
		if not (entry and entry.State == "Live" and IsLoaded(entry.Player)) then
			Diag.LateSettles += 1
			return
		end
		if p.Kind == "Pet" then entry.LedgerPet += amount else entry.LedgerCucumber += amount end
		if popup then p.PendingPopup += amount end
	end

	--..Producers..--
	local function Eligible(p)
		local ok, result
		if p.Kind == "Pet" then
			ok, result = pcall(env.InWorld, p.Model)
			return ok and result == true
		end
		if type(p.OwnerId) ~= "number" then return false end
		ok, result = pcall(env.IsTagged, p.Model)
		if not (ok and result == true) then return false end
		ok, result = pcall(env.InWorld, p.Model)
		return ok and result == true
	end

	--.. settle one producer up to now; returns what it earned since its last settlement (0 when not eligible)
	local function Settle(p, now, eligible)
		if not Finite(now) then return 0 end
		local from = p.LastSettled
		if Finite(from) and now <= from then return 0 end -- never move the clock back (no double pay)
		p.LastSettled = now
		if not Finite(from) then return 0 end
		local start, clamped = Core.ClampElapsed(from, now, maxCatchup)
		if clamped then Diag.CatchupClamps += 1 end
		if not eligible then return 0 end
		if p.Kind == "Pet" then
			local amount = p.BaseRate * (now - start)
			return (Finite(amount) and amount > 0) and amount or 0
		end
		return Core.SettleAmount(p.BaseRate, p.Mods, start, now, cap)
	end

	local function Advance(p, now) -- skip a span without paying it
		if not Finite(p.LastSettled) or now > p.LastSettled then p.LastSettled = now end
		p.PendingPopup = 0
	end

	local function HasExpired(p, now)
		for _, mod in ipairs(p.Mods) do
			if mod.ExpiresAt <= now then return true end
		end
		return false
	end

	local function OwnerIdOf(model)
		local ok, owner = pcall(env.OwnerIdOf, model)
		if ok and Finite(owner) then return owner end
		return nil
	end

	local function BaseRateOf(model)
		local ok, rate = pcall(env.BaseRateOf, model)
		if ok and Finite(rate) and rate >= 0 then return rate end
		Diag.InvalidRates += 1
		return 0
	end

	local function PullMods(model, now)
		local ok, list = pcall(env.ModifiersOf, model, now)
		if not ok then
			Warn("mods", "ModifiersOf failed: " .. tostring(list))
			return {}
		end
		local mods = {}
		if type(list) ~= "table" then return mods end
		for _, mod in ipairs(list) do
			if #mods >= MAX_MODS then break end
			if type(mod) == "table" then
				if Finite(mod.Mult) and mod.Mult > 0 and Finite(mod.ExpiresAt) then
					if mod.ExpiresAt > now then
						table.insert(mods, {Kind = tostring(mod.Kind), Mult = mod.Mult, ExpiresAt = mod.ExpiresAt})
					end
				else
					Diag.InvalidRates += 1
				end
			end
		end
		return mods
	end

	local function Stamp(p, now)
		pcall(env.SetAttribute, p.Model, "BaseRate", p.BaseRate)
		pcall(env.SetAttribute, p.Model, "Rate", p.BaseRate * Core.EffectiveMult(p.Mods, now, cap))
	end

	local FlushDirty
	local function MarkDirty(userId)
		if type(userId) ~= "number" then return end
		Dirty[userId] = true
		if dirtyScheduled then return end
		dirtyScheduled = true
		local ok, err = pcall(env.Defer, function()
			dirtyScheduled = false
			local okFlush, errFlush = pcall(FlushDirty, env.Clock())
			if not okFlush then Warn("totals", "totals flush: " .. tostring(errFlush)) end
		end)
		if not ok then
			dirtyScheduled = false
			Warn("defer", "Defer failed: " .. tostring(err))
		end
	end

	local function Attach(p)
		if type(p.OwnerId) ~= "number" then return end
		local set = ByOwner[p.OwnerId]
		if not set then
			set = {}
			ByOwner[p.OwnerId] = set
		end
		set[p.Key] = true
	end

	local function Detach(p)
		local set = type(p.OwnerId) == "number" and ByOwner[p.OwnerId]
		if not set then return end
		set[p.Key] = nil
		if next(set) == nil then ByOwner[p.OwnerId] = nil end
	end

	local function Unregister(p)
		if Producers[p.Key] ~= p then return end
		Producers[p.Key] = nil
		producerCount -= 1
		Detach(p)
		for _, conn in ipairs(p.Conns) do
			pcall(function() conn:Disconnect() end)
		end
		table.clear(p.Conns)
	end

	local function RegisterCucumber(model, now)
		local p = {Kind = "Cucumber", Key = model, Model = model, OwnerId = OwnerIdOf(model), BaseRate = BaseRateOf(model),
			Mods = PullMods(model, now), LastSettled = now, PendingPopup = 0, Conns = {}}
		Producers[model] = p
		producerCount += 1
		Attach(p)
		local ok, conns = pcall(env.Watch, model)
		if ok and type(conns) == "table" then
			p.Conns = conns
		elseif not ok then
			Warn("watch", "attribute listeners failed: " .. tostring(conns))
		end
		Stamp(p, now)
		MarkDirty(p.OwnerId)
		return p
	end

	--..Totals..--
	local function TotalsOf(userId, now)
		local totals = ZeroTotals()
		local set = ByOwner[userId]
		if set then
			for key in pairs(set) do
				local p = Producers[key]
				if p and Eligible(p) then
					if p.Kind == "Pet" then
						totals.Pet += p.BaseRate
					else
						totals.CucumberBase += p.BaseRate
						totals.Cucumber += p.BaseRate * Core.EffectiveMult(p.Mods, now, cap)
					end
				end
			end
		end
		totals.Total = totals.Cucumber + totals.Pet
		return totals
	end

	--.. CashPerSec follows every time (cheap, only written when it differs); listeners hear real changes only
	local function CommitTotals(entry, totals)
		local ok, err = pcall(env.WriteCashPerSec, entry.Player, totals.Total)
		if not ok then Warn("cashpersec", "CashPerSec write failed: " .. tostring(err)) end
		local last = entry.LastTotals
		if last and not Core.TotalsChanged(last.Total, totals.Total) and not Core.TotalsChanged(last.CucumberBase, totals.CucumberBase) then
			return
		end
		entry.LastTotals = totals
		ok, err = pcall(env.OnTotals, entry.Player, table.clone(totals))
		if not ok then Warn("listeners", "OnTotals failed: " .. tostring(err)) end
	end

	FlushDirty = function(now)
		for userId in pairs(Dirty) do
			Dirty[userId] = nil
			local entry = ResolveOwner(userId)
			if entry and entry.State == "Live" and Present(entry.Player) then
				CommitTotals(entry, TotalsOf(userId, now))
			end
		end
	end
	E.FlushDirty = FlushDirty

	--..Tick..--
	--.. one owner: settle every producer, one credit for ledger + tick, popups only when the credit landed
	local function PayOwner(userId, entry, set, now, batch, expiring)
		local player = entry.Player
		local cucumber, pet = 0, 0
		local totals = ZeroTotals()
		local paid = {}
		if set then
			for key in pairs(set) do
				local p = Producers[key]
				if p then
					local eligible = Eligible(p)
					local amount = Settle(p, now, eligible)
					if p.Held then -- pre-reset span: discarded; an eligible producer re-joins from this tick
						if amount > 0 then Diag.LateSettles += 1 end
						amount = 0
						p.PendingPopup = 0
						if eligible then p.Held = nil end
					end
					if p.Kind == "Pet" then pet += amount else cucumber += amount end
					local popup = amount + p.PendingPopup
					p.PendingPopup = 0
					if popup > 0 then table.insert(paid, {p, popup}) end
					if eligible then
						if p.Kind == "Pet" then
							totals.Pet += p.BaseRate
						else
							totals.CucumberBase += p.BaseRate
							totals.Cucumber += p.BaseRate * Core.EffectiveMult(p.Mods, now, cap)
						end
					end
					if p.Kind == "Cucumber" and HasExpired(p, now) then table.insert(expiring, p) end
				end
			end
		end
		totals.Total = totals.Cucumber + totals.Pet
		local ledgerCucumber, ledgerPet = entry.LedgerCucumber, entry.LedgerPet
		local total = ledgerCucumber + ledgerPet + cucumber + pet
		if not Finite(total) then
			Diag.InvalidRates += 1
			entry.LedgerCucumber, entry.LedgerPet = 0, 0
		elseif total > 0 then
			if Credit(player, total) then
				entry.LedgerCucumber, entry.LedgerPet = 0, 0
				Diag.PaidCucumberCash += ledgerCucumber + cucumber
				Diag.PaidPetCash += ledgerPet + pet
				for _, pair in ipairs(paid) do
					local p, amount = pair[1], pair[2]
					if p.Kind == "Pet" then
						table.insert(batch.PetModels, p.Model)
						table.insert(batch.PetAmounts, amount)
						table.insert(batch.PetIds, p.PetId)
					else
						table.insert(batch.CucumberModels, p.Model)
						table.insert(batch.CucumberAmounts, amount)
					end
				end
			else
				Diag.CreditFailures += 1
				if IsLoaded(player) then -- keep it for the next tick (no popups for it)
					entry.LedgerCucumber = ledgerCucumber + cucumber
					entry.LedgerPet = ledgerPet + pet
				else
					entry.LedgerCucumber, entry.LedgerPet = 0, 0
					Diag.LateSettles += 1
				end
			end
		end
		CommitTotals(entry, totals)
	end

	function E.Tick(now)
		local batch = {CucumberModels = {}, CucumberAmounts = {}, PetModels = {}, PetAmounts = {}, PetIds = {}}
		local expiring = {}
		local visited = {}
		for userId, set in pairs(ByOwner) do
			visited[userId] = true
			local entry = ResolveOwner(userId)
			local live = entry ~= nil and entry.State == "Live"
			if live and IsClosing(entry.Player) then
				continue -- only FlushOwner may settle / credit a closing owner
			end
			if live and Present(entry.Player) and IsLoaded(entry.Player) then
				PayOwner(userId, entry, set, now, batch, expiring)
			else
				for key in pairs(set) do -- departed / unloaded / flushed owner: the span is not paid
					local p = Producers[key]
					if p then
						Advance(p, now)
						if p.Kind == "Cucumber" and HasExpired(p, now) then table.insert(expiring, p) end
					end
				end
			end
		end
		for userId, entry in pairs(Owners) do
			if not visited[userId] then
				if entry.State == "Live" then
					if Present(entry.Player) and IsLoaded(entry.Player) and not IsClosing(entry.Player) then
						PayOwner(userId, entry, nil, now, batch, expiring) -- ledger only (last producer removed)
					end
				elseif not Present(entry.Player) then
					Owners[userId] = nil -- departed and nothing registered under it: nothing can settle into it
				end
			end
		end
		for _, p in ipairs(expiring) do -- a cached modifier ran out: re-pull + restamp Rate after paying
			if Producers[p.Key] == p then E.Refresh(p.Model, now) end
		end
		return batch
	end

	--..State changes..--
	function E.Refresh(model, now)
		if model == nil then return end
		local p = Producers[model]
		if p == nil then
			local ok, tagged = pcall(env.IsTagged, model)
			if ok and tagged == true then RegisterCucumber(model, now) end
			return
		end
		if p.Kind ~= "Cucumber" then return end
		Store(p, Settle(p, now, Eligible(p)), true)
		p.BaseRate = BaseRateOf(model)
		p.Mods = PullMods(model, now)
		Stamp(p, now)
		MarkDirty(p.OwnerId)
	end

	--.. tag removed: the span since the last settlement is paid with the cached mods (the model is already
	--.. untagged / out of the workspace, so eligibility is not re-judged), then the producer is dropped
	function E.TagRemoved(model, now)
		local p = Producers[model]
		if p == nil or p.Kind ~= "Cucumber" then return end
		Store(p, Settle(p, now, type(p.OwnerId) == "number"), false)
		Unregister(p)
		MarkDirty(p.OwnerId)
	end

	function E.OwnerChanged(model, now)
		local p = Producers[model]
		if p == nil or p.Kind ~= "Cucumber" then return end
		local newOwner = OwnerIdOf(model)
		if newOwner == p.OwnerId then return end
		Store(p, Settle(p, now, Eligible(p)), false) -- to the OLD owner
		p.PendingPopup = 0
		p.Held = nil -- a new owner key starts clean
		local oldOwner = p.OwnerId
		Detach(p)
		p.OwnerId = newOwner
		Attach(p)
		MarkDirty(oldOwner)
		MarkDirty(newOwner)
	end

	function E.SetPetProducer(player, petId, model, rate, now)
		local userId = UserIdOf(player)
		if not userId or not IsValidId(petId) then return false end
		if not (Finite(rate) and rate >= 0) then
			Diag.InvalidRates += 1
			rate = 0
		end
		local p = Producers[petId]
		if p and p.Kind ~= "Pet" then return false end
		if p then
			Store(p, Settle(p, now, Eligible(p)), p.Model == model)
			if p.Model ~= model then p.PendingPopup = 0 end
			p.Held = nil -- re-registered after any reset: earns from now
			if p.OwnerId ~= userId then
				local oldOwner = p.OwnerId
				Detach(p)
				p.OwnerId = userId
				Attach(p)
				MarkDirty(oldOwner)
			end
			p.Model = model
			p.BaseRate = rate
		else
			p = {Kind = "Pet", Key = petId, PetId = petId, OwnerId = userId, Model = model, BaseRate = rate, Mods = {},
				LastSettled = now, PendingPopup = 0, Conns = {}}
			Producers[petId] = p
			producerCount += 1
			Attach(p)
		end
		MarkDirty(userId)
		return true
	end

	function E.RemovePetProducer(petId, now)
		local p = Producers[petId]
		if p == nil or p.Kind ~= "Pet" then return end
		Store(p, Settle(p, now, Eligible(p)), false) -- popup share dropped with the model
		Unregister(p)
		MarkDirty(p.OwnerId)
	end

	function E.SettleOwner(player, now)
		local userId = UserIdOf(player)
		if not userId or IsClosing(player) then return end
		local set = ByOwner[userId]
		if not set then return end
		for key in pairs(set) do
			local p = Producers[key]
			if p then Store(p, Settle(p, now, Eligible(p)), true) end
		end
	end

	--.. the pre-close credit (rule 0.13: gated on GetData only). Idempotent: once Flushed it credits 0.
	function E.FlushOwner(player, now)
		local userId = UserIdOf(player)
		if not userId or not HasData(player) then return false end
		local entry = OwnerOfPlayer(player, userId)
		if entry.State ~= "Live" then return true end
		local cucumber, pet = entry.LedgerCucumber, entry.LedgerPet
		local set = ByOwner[userId]
		if set then
			for key in pairs(set) do
				local p = Producers[key]
				if p then
					local amount = Settle(p, now, Eligible(p))
					p.PendingPopup = 0
					if p.Held then -- pre-reset span: discarded
						if amount > 0 then Diag.LateSettles += 1 end
						amount = 0
					end
					if p.Kind == "Pet" then pet += amount else cucumber += amount end
				end
			end
		end
		entry.LedgerCucumber, entry.LedgerPet = 0, 0
		entry.State = "Flushed"
		Diag.Flushes += 1
		local total = cucumber + pet
		if not (Finite(total) and total > 0) then return true end
		if Credit(player, total) then
			Diag.PaidCucumberCash += cucumber
			Diag.PaidPetCash += pet
			return true
		end
		Diag.CreditFailures += 1
		return false
	end

	function E.PlayerRemoving(player, now)
		local userId = UserIdOf(player)
		if not userId then return end
		local ok, err = pcall(E.FlushOwner, player, now) -- a no-op when the pre-close flush already ran
		if not ok then Warn("flush", "FlushOwner on leave: " .. tostring(err)) end
		local entry = Owners[userId]
		if entry and entry.Player == player then
			entry.State = "Forgotten"
			entry.LedgerCucumber, entry.LedgerPet = 0, 0
		end
		Dirty[userId] = nil
	end

	--.. DataService.ResetProfile: the fresh profile owes nothing - drop the ledger, restart the clocks and hold
	--.. every producer registered so far (a deferred TagRemoved lands after `now`; Store / PayOwner / FlushOwner
	--.. discard a held producer's settlements)
	function E.ProfileReset(player, now)
		local userId = UserIdOf(player)
		if not userId then return end
		local entry = Owners[userId]
		if entry and entry.Player == player then
			entry.LedgerCucumber, entry.LedgerPet = 0, 0
			entry.LastTotals = nil
		end
		local set = ByOwner[userId]
		if set then
			for key in pairs(set) do
				local p = Producers[key]
				if p then
					Advance(p, now)
					p.Held = true
				end
			end
		end
		MarkDirty(userId)
	end

	--..Queries..--
	function E.GetTotals(player, now)
		local userId = UserIdOf(player)
		if not userId then return ZeroTotals() end
		return TotalsOf(userId, now)
	end

	function E.GetCucumberRates(model, now)
		local p = Producers[model]
		if p == nil or p.Kind ~= "Cucumber" then return nil, nil end
		return p.BaseRate * Core.EffectiveMult(p.Mods, now, cap), p.BaseRate
	end

	function E.GetDiagnostics()
		local out = table.clone(Diag)
		out.Producers = producerCount
		return out
	end

	--.. drop every producer (a failed Start): disconnects their attribute listeners, pays nothing
	function E.Clear()
		local all = {}
		for _, p in pairs(Producers) do table.insert(all, p) end
		for _, p in ipairs(all) do Unregister(p) end
	end

	return E
end

--..Service state..--
local IncomeService = {}
IncomeService.Core = Core

local Engine = nil -- Core.NewEngine(...) once Init ran
local DataServiceRef = nil
local Clock = function() return workspace:GetServerTimeNow() end
local Started = false
local Starting = false
local Listeners = {} -- {{Fn = fn}}: OnTotalsChanged subscribers (may subscribe before Init)
local Connections = {}
local CucumberRemote, PetRemote = nil, nil

local function Now(now)
	local clock = Clock()
	if Finite(now) and math.abs(now - clock) <= MAX_NOW_SKEW then return now end
	return clock
end

local function Guard(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then WarnOnce(key, key .. ": " .. tostring(err)) end
end

local function FireListeners(player, totals)
	for _, entry in ipairs(table.clone(Listeners)) do
		local ok, err = pcall(entry.Fn, player, totals)
		if not ok then WarnOnce("listener", "OnTotalsChanged listener: " .. tostring(err)) end
	end
end

--.. player.Data.CashPerSec (LeaderstatsService creates it in Setup too; whoever is first creates it)
local function WriteCashPerSec(player, total)
	if typeof(player) ~= "Instance" then return end
	local data = player:FindFirstChild("Data")
	if not data then return end
	local value = data:FindFirstChild(CASH_PER_SEC)
	if not value then
		value = Instance.new("NumberValue")
		value.Name = CASH_PER_SEC
		value.Parent = data
	end
	if value:IsA("NumberValue") and value.Value ~= total then value.Value = total end
end

--.. per-cucumber attribute listeners, stored on the producer, disconnected when it is unregistered
local function WatchCucumber(model)
	local conns = {}
	for _, name in ipairs(REFRESH_ATTRIBUTES) do
		table.insert(conns, model:GetAttributeChangedSignal(name):Connect(function()
			if Engine then Guard("refresh", Engine.Refresh, model, Clock()) end
		end))
	end
	table.insert(conns, model:GetAttributeChangedSignal("Owner"):Connect(function()
		if Engine then Guard("owner", Engine.OwnerChanged, model, Clock()) end
	end))
	return conns
end

--.. LeaderstatsService find-or-creates CucumberIncome too: never yield between the find and the Parent
local function FindOrCreateRemote(folder, name)
	local remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	return remote
end

local function OnTagAdded(model)
	if Engine and typeof(model) == "Instance" and model:IsA("Model") then
		Guard("register", Engine.Refresh, model, Clock()) -- registers (idempotent); Parent is not judged here
	end
end

local function OnTagRemoved(model)
	if Engine then Guard("unregister", Engine.TagRemoved, model, Clock()) end
end

local function Tick(now)
	local batch = Engine.Tick(now)
	if #batch.CucumberModels > 0 and CucumberRemote then
		CucumberRemote:FireAllClients(batch.CucumberModels, batch.CucumberAmounts)
	end
	if #batch.PetModels > 0 and PetRemote then
		PetRemote:FireAllClients(batch.PetModels, batch.PetAmounts, batch.PetIds)
	end
end

--..Lifecycle..--
function IncomeService.Init(deps)
	if Engine then
		warn("[IncomeService] Init called twice - ignored")
		return
	end
	assert(type(deps) == "table" and type(deps.DataService) == "table", "[IncomeService] Init: DataService is required")
	DataServiceRef = deps.DataService
	if type(deps.Clock) == "function" then Clock = deps.Clock end
	local modifiersOf = type(deps.ModifiersOf) == "function" and deps.ModifiersOf or function() return {} end
	Engine = Core.NewEngine({
		Clock = function() return Clock() end,
		DataService = deps.DataService,
		ModifiersOf = modifiersOf,
		BaseRateOf = CucumberValues.RateOfInstance,
		IsTagged = function(model)
			return typeof(model) == "Instance" and CollectionService:HasTag(model, PLACED_TAG)
		end,
		InWorld = function(model)
			return typeof(model) == "Instance" and model:IsDescendantOf(workspace)
		end,
		OwnerIdOf = function(model) return model:GetAttribute("Owner") end,
		PlayerByUserId = function(userId) return Players:GetPlayerByUserId(userId) end,
		IsPresent = function(player) return typeof(player) == "Instance" and player.Parent == Players end,
		SetAttribute = function(model, name, value)
			if model:GetAttribute(name) ~= value then model:SetAttribute(name, value) end
		end,
		WriteCashPerSec = WriteCashPerSec,
		Watch = WatchCucumber,
		Defer = task.defer,
		OnTotals = FireListeners,
		Warn = WarnOnce,
		RateCap = RATE_HARD_CAP,
		MaxCatchup = INCOME_MAX_CATCHUP,
	})
end

function IncomeService.Start()
	if Started or Starting then return end
	if not Engine then
		warn("[IncomeService] Start before Init - ignored")
		return
	end
	Starting = true
	local ok, err = pcall(function()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if not remotes then
			remotes = Instance.new("Folder")
			remotes.Name = "Remotes"
			remotes.Parent = ReplicatedStorage
		end
		CucumberRemote = FindOrCreateRemote(remotes, CUCUMBER_REMOTE)
		PetRemote = FindOrCreateRemote(remotes, PET_REMOTE)
		--.. signals first, then the sweep (registration is idempotent)
		table.insert(Connections, CollectionService:GetInstanceAddedSignal(PLACED_TAG):Connect(OnTagAdded))
		table.insert(Connections, CollectionService:GetInstanceRemovedSignal(PLACED_TAG):Connect(OnTagRemoved))
		for _, model in ipairs(CollectionService:GetTagged(PLACED_TAG)) do OnTagAdded(model) end
		if type(DataServiceRef.OnBeforeClose) == "function" then
			DataServiceRef.OnBeforeClose(function(player) IncomeService.FlushOwner(player) end, FLUSH_ORDER)
		end
		if type(DataServiceRef.OnProfileReset) == "function" then
			DataServiceRef.OnProfileReset(function(player)
				if Engine then Guard("reset", Engine.ProfileReset, player, Clock()) end
			end)
		end
		table.insert(Connections, Players.PlayerRemoving:Connect(function(player)
			if Engine then Guard("leave", Engine.PlayerRemoving, player, Clock()) end
		end))
	end)
	if not ok then
		for _, conn in ipairs(Connections) do conn:Disconnect() end
		table.clear(Connections)
		pcall(Engine.Clear)
		Starting = false
		error("[IncomeService] Start failed: " .. tostring(err), 0)
	end
	Started = true
	--.. ONE deadline loop: nextTick += INCOME_TICK (no task.wait drift); more than a tick behind -> resync
	local nextTick = Clock() + INCOME_TICK
	local ticking = false
	table.insert(Connections, RunService.Heartbeat:Connect(function()
		if ticking then return end
		local now = Clock()
		if not Finite(now) or now < nextTick then return end
		nextTick += INCOME_TICK
		if nextTick <= now then nextTick = now + INCOME_TICK end
		ticking = true
		local okTick, errTick = pcall(Tick, now)
		ticking = false
		if not okTick then WarnOnce("tick", "income tick: " .. tostring(errTick)) end
	end))
	print(("[IncomeService] started: %d placed cucumbers registered, income every %gs -> Cash + %s / %s"):format(
		Engine.GetDiagnostics().Producers, INCOME_TICK, CUCUMBER_REMOTE, PET_REMOTE))
end

function IncomeService.IsStarted()
	return Started
end

--..Producers (no-ops until Start finished)..--
function IncomeService.Refresh(model, now)
	if not Started then return end
	Guard("refresh", Engine.Refresh, model, Now(now))
end

function IncomeService.SetPetProducer(player, petId, model, ratePerSec, now)
	if not Started then return end
	Guard("pet", Engine.SetPetProducer, player, petId, model, ratePerSec, Now(now))
end

function IncomeService.RemovePetProducer(petId, now)
	if not Started then return end
	Guard("pet", Engine.RemovePetProducer, petId, Now(now))
end

function IncomeService.SettleOwner(player, now)
	if not Started then return end
	Guard("settle", Engine.SettleOwner, player, Now(now))
end

function IncomeService.FlushOwner(player)
	if not Engine then return false end
	local ok, result = pcall(Engine.FlushOwner, player, Clock())
	if not ok then
		WarnOnce("flush", "FlushOwner: " .. tostring(result))
		return false
	end
	return result == true
end

--..Queries (never error, safe before Init / Start)..--
function IncomeService.GetTotals(player)
	if not Engine then return ZeroTotals() end
	local ok, totals = pcall(Engine.GetTotals, player, Clock())
	if ok and type(totals) == "table" then return totals end
	return ZeroTotals()
end

function IncomeService.GetThreatIncome(player)
	if not Started then return nil end -- callers fall back to CashPerSec
	return IncomeService.GetTotals(player).CucumberBase
end

function IncomeService.GetCucumberRates(model)
	if not Engine then return nil, nil end
	local ok, effective, base = pcall(Engine.GetCucumberRates, model, Clock())
	if ok then return effective, base end
	return nil, nil
end

function IncomeService.OnTotalsChanged(fn)
	if type(fn) ~= "function" then return function() end end
	local entry = {Fn = fn}
	table.insert(Listeners, entry)
	return function()
		local index = table.find(Listeners, entry)
		if index then table.remove(Listeners, index) end
	end
end

function IncomeService.GetDiagnostics()
	if not Engine then
		return {PaidCucumberCash = 0, PaidPetCash = 0, CatchupClamps = 0, CreditFailures = 0, InvalidRates = 0,
			Producers = 0, LateSettles = 0, Flushes = 0}
	end
	return Engine.GetDiagnostics()
end

return IncomeService
