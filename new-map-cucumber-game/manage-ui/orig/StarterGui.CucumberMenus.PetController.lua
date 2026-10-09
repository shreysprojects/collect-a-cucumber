--[[
	PetController  (ModuleScript, StarterGui.CucumberMenus)
	Wires the Pets panel (StarterGui.CucumberMenus.PetsPanel, built by
	pets-system/builders/build_petspanel.lua and drawn by PetView) to the server's pet state.

	2026-09-22 (pet system, pets-system/CONTRACTS.md 3.11): MenuClient starts this last and guarded.
	Start(gui, menus) returns at once; a spawned thread waits for Remotes.PetState / PetRequest
	(60 s, "Pets unavailable" otherwise) and asks for the full state (GetState). The server answers
	with a revisioned Full and pushes Deltas afterwards (roster changes, hatches, rolls, the combat
	lock); a Delta only applies on top of the revision it was built from, anything else asks for a
	new Full (at most once a second). GetState is fire-and-forget: nothing waits on it, and when no
	Full arrives the next open / gap / 5 s tick while open asks again. Kind "Totals" messages only
	refresh the footer and never touch the revision; a new profile Generation (admin reset) drops the
	held state first.
	Roster actions (Equip / Unequip / Best income / Best combat) are one pending request at a time:
	the buttons stay disabled until the reply carrying that RequestId arrives (or 5 s pass), and a
	refusal shows a friendly line on the panel instead of closing it. During a night / raid
	(CombatLocked) the panel stays readable, the roster buttons are disabled and the lock banner shows.
	Sorting (income / combat / rarity / newest) and filtering (all / active / reserve) are local
	display only; Best income / Best combat are server-authoritative (EquipBest). v1 uses the
	unequip-first flow: on a full roster the equip button asks the player to unequip one first.
	Keys: P / ButtonL3 toggle the panel, but only while CucumberMenus is enabled (EggHatchClient's
	reveal disables it) and the HUD attributes BuildMode / BenchMode are not set. Gamepad: opening
	focuses SlotRow.Slot1 (the first pet card when no pet is active); closing clears a focus that is
	inside the panel. The one-time migration Notice becomes a Notify.Info toast.
	2026-09-22 (review): a Full whose Result says Ok = false is PetService refusing GetState (profile
	not loaded yet, closing, or a failed migration) and carries an empty placeholder roster, so it is
	never taken as state: the held state (or none) stays, the panel keeps "Loading pets..." or shows
	the refusal line with the buttons disabled, and the open / 5 s retry plus PetService's own Full
	once the pets load bring the real state. The unsolicited hatch refusal (Result.Action = "Hatch",
	InventoryFull) is a Notify.Error toast whether the panel is open or not (CONTRACTS 4.2).
	All the logic the tests exercise lives in the pure PetController.Core table (no instances, no
	requires): Sort, Filter, DisplayList, ApplyState, IsRefusal, LockState, BuildViewModel,
	NextRollText, ErrorText, StateErrorText, NewRequestId, FormatCountdown, FooterOf.
	Dev hook (Studio only): PetsPanel attribute PetsDev = "open" | "close" | "select:<n>" | "back" |
	"equip" | "best:Income" | "best:Combat" | "sort:<Mode>" | "filter:<Mode>" (cleared to nil when read;
	"select" also opens the compact Details page like a tap, "back" closes it). In
	Studio the panel also mirrors PetsRevision / PetsOwned / PetsEquipped / PetsSelected / PetsPending
	attributes so a test can read the menu numerically.
	2026-09-22 (review fixes): a Kind = "Totals" message only redraws the footer (view.SetFooter with
	Core.FooterOf) instead of rebuilding and re-rendering the whole inventory; PetView materialises the
	grid incrementally. A card's view model carries every material / mutation chip (PetView fits them
	to the chip row's width, "+N" for the rest). A "None"-ability pet that is not a real fighter (an
	unknown species kept as Status "Invalid", or Stats.Fighter ~= true) shows "No ability" in white with
	no effect line, and an Invalid pet's combat line reads "Does not fight" instead of "0 dmg every 0s".
]]
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PetController = {}

local ACTION_NAME = "PetsPanel"
local REMOTE_WAIT = 60        -- seconds to wait for Remotes.PetState / PetRequest
local FULL_MIN_GAP = 1        -- GetState at most once a second
local FULL_RETRY = 5          -- while open with no (or a stale) state, ask again this often
local PENDING_TIMEOUT = 5     -- a roster request with no reply frees the buttons after this
local ERROR_SECONDS = 4       -- how long a refusal line stays on the panel
local STEP_SECONDS = 0.25     -- countdown / timeout stepper
local NOTICE_SECONDS = 6

--..Core (pure: plain tables in, plain tables out; unit-tested)..--
local Core = {}
PetController.Core = Core

Core.DEFAULT_SLOTS = 6
Core.MAX_SLOTS = 12
Core.SORT_MODES = {Income = true, Combat = true, Rarity = true, Newest = true}
Core.FILTER_MODES = {All = true, Active = true, Reserve = true}
Core.BEST_MODES = {Income = true, Combat = true}
--.. PetsCatalog.RARITY_ORDER's values; Start passes the live table in, this is the fallback
Core.RARITY_ORDER = {Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythical = 6, Omega = 7, Special = 8}
--.. PetBalance.TEXT entries this menu shows; used only when PetBalance is not installed
Core.DEFAULT_TEXT = {
	LockBanner = "Finish defending your plot to change pets.",
	Unavailable = "Temporarily unavailable",
	NextRoll = "Next chance roll in %s",
	InventoryFull = "Your pet inventory is full.",
}
Core.ERROR_TEXT = { -- PetState Result.Error codes (CONTRACTS 7.2) -> what the panel says
	NotLoaded = "Your pets are still loading - try again in a moment.",
	Closing = "Saving your pets...",
	NotOwned = "That pet is not in your inventory any more.",
	SlotsFull = "All slots are full - unequip a pet first.",
	Unavailable = "Pets are temporarily unavailable.",
	RateLimited = "Too fast - wait a moment.",
	BadRequest = "Something went wrong - try again.",
	NoPlot = "You need your plot to equip pets.",
	MigrationFailed = "Your pets could not be loaded this session.",
}
Core.LOADING_TEXT = "Loading pets..."
Core.STATUS_TEXT = { -- PetView.Status -> the small tag on a card ("" = no tag)
	Active = "",
	Reserve = "",
	Pending = "Hatching...",
	Idle = "Waiting for your plot",
	Invalid = "Unknown pet",
}
Core.EMPTY_TEXT = {
	None = "No pets yet - hatch an egg to get one!",
	Active = "No active pets - equip one from your reserve.",
	Reserve = "No pets in reserve.",
}
Core.NO_ABILITY_TEXT = "No ability"   -- a "None" pet that is not a fighter (unknown species / Invalid)
Core.NO_COMBAT_TEXT = "Does not fight" -- an Invalid pet's combat line

local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
Core.Finite = Finite

local function Num(x)
	return Finite(x) and x or 0
end

local function ValidId(id)
	return type(id) == "string" and #id >= 1 and #id <= 64
end

local function Copy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

local function StatOf(pet, key)
	local stats = type(pet) == "table" and pet.Stats
	return type(stats) == "table" and Num(stats[key]) or 0
end

local function IdOf(pet)
	return type(pet) == "table" and type(pet.Id) == "string" and pet.Id or ""
end

local function Str(value, fallback)
	return type(value) == "string" and value or fallback
end

--.. never errors: a bad template falls back to the default one
local function SafeFormat(template, fallback, ...)
	local ok, result = pcall(string.format, template, ...)
	if ok then return result end
	return string.format(fallback, ...)
end

local function TextOf(env, key)
	local text = type(env) == "table" and env.Text
	local value = type(text) == "table" and text[key]
	return type(value) == "string" and value or Core.DEFAULT_TEXT[key] or ""
end

--..Sorting / filtering (local display only)..--
local function RarityRank(pet, order)
	local rarity = type(pet) == "table" and pet.Rarity
	return Num(type(rarity) == "string" and order[rarity] or 0)
end

local COMPARE = {
	Income = function(a, b)
		local ai, bi = StatOf(a, "Income"), StatOf(b, "Income")
		if ai ~= bi then return ai > bi end
		local ad, bd = StatOf(a, "DPS"), StatOf(b, "DPS")
		if ad ~= bd then return ad > bd end
		return IdOf(a) < IdOf(b)
	end,
	Combat = function(a, b)
		local ad, bd = StatOf(a, "DPS"), StatOf(b, "DPS")
		if ad ~= bd then return ad > bd end
		local ai, bi = StatOf(a, "Income"), StatOf(b, "Income")
		if ai ~= bi then return ai > bi end
		return IdOf(a) < IdOf(b)
	end,
}

--.. pets = array of PetView tables; returns a NEW sorted array (the input is left alone).
--.. Income: income, DPS, Id; Combat: DPS, income, Id; Rarity: rarity (best first), income, Id;
--.. Newest: AcquiredAt (newest first), Id. rarityOrder defaults to Core.RARITY_ORDER.
function Core.Sort(pets, mode, rarityOrder)
	local list = {}
	if type(pets) ~= "table" then return list end
	for _, pet in ipairs(pets) do
		if type(pet) == "table" then list[#list + 1] = pet end
	end
	local order = type(rarityOrder) == "table" and rarityOrder or Core.RARITY_ORDER
	local compare
	if mode == "Combat" then
		compare = COMPARE.Combat
	elseif mode == "Rarity" then
		compare = function(a, b)
			local ar, br = RarityRank(a, order), RarityRank(b, order)
			if ar ~= br then return ar > br end
			return COMPARE.Income(a, b)
		end
	elseif mode == "Newest" then
		compare = function(a, b)
			local at, bt = Num(a.AcquiredAt), Num(b.AcquiredAt)
			if at ~= bt then return at > bt end
			return IdOf(a) < IdOf(b)
		end
	else
		compare = COMPARE.Income
	end
	table.sort(list, compare)
	return list
end

--.. "All" | "Active" | "Reserve"; equippedSet ({[id] = true}, optional) overrides each pet's Equipped flag
function Core.Filter(pets, mode, equippedSet)
	local list = {}
	if type(pets) ~= "table" then return list end
	for _, pet in ipairs(pets) do
		if type(pet) == "table" then
			local equipped
			if type(equippedSet) == "table" then equipped = equippedSet[pet.Id] == true else equipped = pet.Equipped == true end
			if mode == "Active" then
				if equipped then list[#list + 1] = pet end
			elseif mode == "Reserve" then
				if not equipped then list[#list + 1] = pet end
			else
				list[#list + 1] = pet
			end
		end
	end
	return list
end

--.. {[id] = true} for the held roster
function Core.EquippedSet(state)
	local set = {}
	if type(state) == "table" and type(state.EquippedIds) == "table" then
		for _, id in ipairs(state.EquippedIds) do set[id] = true end
	end
	return set
end

--.. the held state's pets, filtered then sorted
function Core.DisplayList(state, sortMode, filterMode, rarityOrder, equippedSet)
	if type(state) ~= "table" or type(state.Pets) ~= "table" then return {} end
	local list = {}
	for _, pet in pairs(state.Pets) do list[#list + 1] = pet end
	return Core.Sort(Core.Filter(list, filterMode, equippedSet), sortMode, rarityOrder)
end

--..PetState payloads (CONTRACTS 7.2)..--
local ZERO_TOTALS = {Pet = 0, Cucumber = 0, CucumberBase = 0, Total = 0}

local function CleanTotals(totals, old)
	if type(totals) ~= "table" then return old or ZERO_TOTALS end
	return {Pet = Num(totals.Pet), Cucumber = Num(totals.Cucumber), CucumberBase = Num(totals.CucumberBase), Total = Num(totals.Total)}
end

local function CleanIds(list, limit)
	local out, seen = {}, {}
	if type(list) ~= "table" then return out end
	for _, id in ipairs(list) do
		if ValidId(id) and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
			if limit and #out >= limit then break end
		end
	end
	return out
end

local function HasData(payload)
	return payload.EquippedIds ~= nil or payload.Upserts ~= nil or payload.Removed ~= nil
		or payload.Totals ~= nil or payload.CombatLocked ~= nil
end

--.. a Full carrying Result.Ok == false is PetService refusing GetState (NotLoaded / Closing / MigrationFailed):
--.. its Pets / EquippedIds are an empty placeholder, not the player's roster
function Core.IsRefusal(payload)
	if type(payload) ~= "table" or payload.Kind ~= "Full" then return false end
	local result = payload.Result
	return type(result) == "table" and result.Ok == false
end

--.. state = nil or {Revision, Generation, Slots, EquippedIds, Pets = {[id] = PetView}, AsOf = {[id] = serverTime},
--.. Totals, CombatLocked, ServerTime}. Returns the new state (a new table when anything changed; the input is
--.. never mutated) and needFull (a Full must be requested). now = fallback time stamp when ServerTime is bad.
--..   Full: replaces (a Full older than the held revision of the same generation is ignored as stale);
--..     a refusal Full (Core.IsRefusal) is not state: the held state (or nil) is returned unchanged
--..   Delta: needs a held state of the same generation and BaseRevision == held Revision; a different
--..     Generation drops the held state (nil) and asks for a Full; a gap keeps the held state and asks
--..     for a Full; an old / repeated revision is ignored. A Delta that carries no state fields (a bare
--..     request acknowledgement, e.g. PetServer's "Unavailable" reply) never asks for a Full.
--..   Totals: refreshes Totals only; never touches Revision.
function Core.ApplyState(state, payload, now)
	if type(payload) ~= "table" then return state, false end
	if state ~= nil and type(state) ~= "table" then state = nil end
	local kind = payload.Kind
	local serverTime = Finite(payload.ServerTime) and payload.ServerTime or (Finite(now) and now or nil)
	if kind == "Totals" then
		if not state or type(payload.Totals) ~= "table" then return state, false end
		local new = Copy(state)
		new.Totals = CleanTotals(payload.Totals, state.Totals)
		return new, false
	end
	local revision = payload.Revision
	if not Finite(revision) then return state, false end
	if kind == "Full" then
		if Core.IsRefusal(payload) then return state, false end
		if state and payload.Generation == state.Generation and revision < state.Revision then return state, false end
		local slots = Finite(payload.Slots) and payload.Slots >= 1 and math.floor(math.min(payload.Slots, Core.MAX_SLOTS)) or Core.DEFAULT_SLOTS
		local new = {
			Revision = revision,
			Generation = payload.Generation,
			Slots = slots,
			Pets = {},
			AsOf = {},
			Totals = CleanTotals(payload.Totals, ZERO_TOTALS),
			CombatLocked = payload.CombatLocked == true,
			ServerTime = serverTime,
		}
		if type(payload.Pets) == "table" then
			for _, view in ipairs(payload.Pets) do
				if type(view) == "table" and ValidId(view.Id) then
					new.Pets[view.Id] = view
					new.AsOf[view.Id] = serverTime
				end
			end
		end
		new.EquippedIds = CleanIds(payload.EquippedIds, slots)
		return new, false
	elseif kind == "Delta" then
		if not HasData(payload) then
			if state and payload.Generation == state.Generation and payload.BaseRevision == state.Revision and revision > state.Revision then
				local new = Copy(state)
				new.Revision = revision
				return new, false
			end
			return state, false
		end
		if not state then return nil, true end
		if payload.Generation ~= state.Generation then return nil, true end
		if revision <= state.Revision then return state, false end
		if payload.BaseRevision ~= state.Revision then return state, true end
		local new = Copy(state)
		new.Revision = revision
		new.ServerTime = serverTime
		new.Pets = Copy(state.Pets)
		new.AsOf = Copy(state.AsOf or {})
		if type(payload.Removed) == "table" then
			for _, id in ipairs(CleanIds(payload.Removed)) do
				new.Pets[id] = nil
				new.AsOf[id] = nil
			end
		end
		if type(payload.Upserts) == "table" then
			for _, view in ipairs(payload.Upserts) do
				if type(view) == "table" and ValidId(view.Id) then
					new.Pets[view.Id] = view
					new.AsOf[view.Id] = serverTime
				end
			end
		end
		if payload.EquippedIds ~= nil then new.EquippedIds = CleanIds(payload.EquippedIds, new.Slots) end
		if payload.Totals ~= nil then new.Totals = CleanTotals(payload.Totals, state.Totals) end
		if type(payload.CombatLocked) == "boolean" then new.CombatLocked = payload.CombatLocked end
		return new, false
	end
	return state, false
end

--.. whether roster actions are allowed right now, and whether the lock banner shows
function Core.LockState(state, pending)
	if type(state) ~= "table" then return {Banner = false, Enabled = false, Reason = "Loading"} end
	if state.CombatLocked == true then return {Banner = true, Enabled = false, Reason = "CombatLocked"} end
	if pending then return {Banner = false, Enabled = false, Reason = "Pending"} end
	return {Banner = false, Enabled = true}
end

--.. Result.Error code -> the line the panel shows
function Core.ErrorText(code, env)
	if code == "CombatLocked" then return TextOf(env, "LockBanner") end
	if code == "InventoryFull" then return TextOf(env, "InventoryFull") end
	return Core.ERROR_TEXT[code] or Core.ERROR_TEXT.BadRequest
end

--.. a GetState refusal -> the status line shown while no state is held (not loaded yet = still loading)
function Core.StateErrorText(code, env)
	if code == "NotLoaded" then return Core.LOADING_TEXT end
	return Core.ErrorText(code, env)
end

--.. seconds -> "m:ss" (rounded up, so it reads 0:00 exactly when the time is up; capped at 99:59)
function Core.FormatCountdown(seconds)
	if not Finite(seconds) or seconds <= 0 then return "0:00" end
	local total = math.min(math.ceil(seconds - 1e-6), 5999)
	return string.format("%d:%02d", total // 60, total % 60)
end

--.. unique within the session, <= 40 characters (PetRequest.RequestId)
local requestCounter = 0
local requestPrefix = nil
function Core.NewRequestId()
	if not requestPrefix then
		requestPrefix = string.format("%06x", Random.new():NextInteger(0, 0xFFFFFF))
	end
	requestCounter += 1
	return requestPrefix .. "-" .. requestCounter
end

--.. 0.08 -> "8%", 0.005 -> "0.5%"
local function PercentText(chance)
	local p = math.floor(math.max(0, Num(chance)) * 10000 + 0.5) / 100
	return string.format("%g%%", p)
end

local function ShortNumber(x)
	return string.format("%g", math.floor(Num(x) * 100 + 0.5) / 100)
end

local function AbilityKindOf(pet)
	local stats = type(pet) == "table" and pet.Stats
	local kind = type(stats) == "table" and stats.Ability
	return type(kind) == "string" and kind or "None"
end

--.. the "Next chance roll in 0:42" line (counts down client-side only while the pet is Active)
function Core.NextRollText(pet, asOf, now, env, equipped)
	if type(pet) ~= "table" or AbilityKindOf(pet) == "None" then return "" end
	if pet.Status ~= "Active" then
		if pet.Status == "Reserve" or not equipped then return "Equip it to start its chance rolls" end
		return "Chance rolls paused"
	end
	local remaining = Num(pet.AbilityRemaining)
	if Finite(asOf) and Finite(now) then remaining -= math.max(0, now - asOf) end
	local default = Core.DEFAULT_TEXT.NextRoll
	return SafeFormat(TextOf(env, "NextRoll"), default, Core.FormatCountdown(remaining))
end

local function MutationsOf(pet)
	local out = {}
	if type(pet.Mutations) == "table" then
		for _, name in ipairs(pet.Mutations) do
			if type(name) == "string" and name ~= "" then out[#out + 1] = name end
		end
	end
	return out
end

local function CommonOf(pet)
	local material = Str(pet.Material, "")
	local mutations = MutationsOf(pet)
	return {
		Id = pet.Id,
		Pet = Str(pet.Pet, ""),
		DisplayName = Str(pet.DisplayName, Str(pet.Pet, "?")),
		Rarity = Str(pet.Rarity, "Common"),
		Material = material,
		Mutations = mutations,
		Look = Str(pet.Pet, "") .. "|" .. material .. "|" .. table.concat(mutations, ","),
	}
end

--.. one grid card. Chips = every material / mutation chip in order: PetView fits them to the chip row's
--.. width and folds the rest into "+N" (2026-09-22 review: a count cap alone let wide chips spill over)
function Core.CardOf(pet, equipped, selected, env)
	local card = CommonOf(pet)
	local abbrev = type(env) == "table" and type(env.Abbrev) == "function" and env.Abbrev or tostring
	local chips = {}
	if card.Material ~= "" then chips[#chips + 1] = {Text = card.Material, Word = card.Material} end
	for _, name in ipairs(card.Mutations) do chips[#chips + 1] = {Text = name, Word = name} end
	card.Chips = chips
	card.RateText = "$" .. abbrev(StatOf(pet, "Income")) .. "/s"
	card.Equipped = equipped == true
	card.Selected = selected == true
	card.Status = Str(pet.Status, "Reserve")
	if card.Status == "Unavailable" then
		card.StatusText = TextOf(env, "Unavailable")
	else
		card.StatusText = Core.STATUS_TEXT[card.Status] or ""
	end
	return card
end

--.. the details column for the selected pet
function Core.DetailsOf(state, id, equippedSet, lock, env)
	local pet = state.Pets[id]
	if type(pet) ~= "table" then return nil end
	env = type(env) == "table" and env or {}
	local abbrev = type(env.Abbrev) == "function" and env.Abbrev or tostring
	local stats = type(pet.Stats) == "table" and pet.Stats or {}
	local kind = AbilityKindOf(pet)
	local equipped = equippedSet[id] == true
	local d = CommonOf(pet)
	d.Equipped = equipped
	d.Status = Str(pet.Status, "Reserve")
	d.StatusText = d.Status == "Unavailable" and TextOf(env, "Unavailable") or (Core.STATUS_TEXT[d.Status] or "")
	d.Traits = {}
	if d.Material ~= "" then d.Traits[#d.Traits + 1] = d.Material end
	for _, name in ipairs(d.Mutations) do d.Traits[#d.Traits + 1] = name end
	d.Rate = "$" .. abbrev(Num(stats.Income)) .. "/s"
	d.RateNote = equipped and "" or "when active"
	if d.Status == "Invalid" then
		d.Combat = Core.NO_COMBAT_TEXT
	else
		d.Combat = string.format("%s dmg every %ss  ·  %s nominal DPS  ·  range %s",
			abbrev(Num(stats.ShotDamage)), ShortNumber(stats.ShotInterval), abbrev(Num(stats.DPS)), abbrev(Num(stats.Range)))
	end
	d.AbilityKind = kind
	local abilities = type(env.Abilities) == "table" and env.Abilities or nil
	local row = abilities and abilities[kind]
	d.AbilityName = type(row) == "table" and Str(row.DisplayName, kind) or (kind == "None" and "Fighter" or kind)
	d.AbilityEffect = ""
	local statsModule = env.Stats
	-- 2026-09-22 (review): "None" is the fighter bonus only for real fighters; an unknown species (Invalid,
	-- EmptyStats: Fighter = false, 0 damage) has no ability at all ("NoAbility" has no ABILITIES row: white text)
	if kind == "None" and (stats.Fighter ~= true or d.Status == "Invalid") then
		d.AbilityKind = "NoAbility"
		d.AbilityName = Core.NO_ABILITY_TEXT
		statsModule = nil
	end
	if type(statsModule) == "table" and type(statsModule.AbilityEffect) == "function" then
		local guard = nil
		if kind == "Guard" then
			guard = stats.AbilityDuration
		elseif kind == "Wild" and type(stats.AbilityDurations) == "table" then
			guard = stats.AbilityDurations.Guard
		end
		local ok, text = pcall(statsModule.AbilityEffect, kind, Finite(guard) and guard or nil)
		if ok and type(text) == "string" then d.AbilityEffect = text end
	end
	if kind == "None" then
		d.AbilityChance = ""
	else
		local period = Finite(env.Period) and env.Period or 60
		local every = period == 60 and "each active minute" or string.format("every %ss of active time", ShortNumber(period))
		d.AbilityChance = PercentText(stats.AbilityChance) .. " chance " .. every
	end
	d.NextRoll = Core.NextRollText(pet, state.AsOf and state.AsOf[id], env.Now, env, equipped)
	if equipped then
		d.EquipText, d.EquipAction, d.EquipEnabled = "UNEQUIP", "Unequip", lock.Enabled
	elseif d.Status == "Invalid" then
		d.EquipText, d.EquipAction, d.EquipEnabled = "UNAVAILABLE", nil, false
	elseif #state.EquippedIds >= state.Slots then
		d.EquipText, d.EquipAction, d.EquipEnabled = "UNEQUIP ONE FIRST", nil, false
	else
		d.EquipText, d.EquipAction, d.EquipEnabled = "EQUIP", "Equip", lock.Enabled
	end
	return d
end

--.. the footer's three texts from a Totals table (also the Kind = "Totals" fast path: footer only)
function Core.FooterOf(totals, env)
	local abbrev = type(env) == "table" and type(env.Abbrev) == "function" and env.Abbrev or tostring
	local function Cash(x) return "$" .. abbrev(Num(x)) .. "/s" end
	totals = type(totals) == "table" and totals or ZERO_TOTALS
	return {Pet = Cash(totals.Pet), Cucumber = Cash(totals.Cucumber), Total = Cash(totals.Total)}
end

--.. everything PetView.Render needs. ui = {Sort, Filter, SelectedId, Pending}; env = {Now (server time),
--.. Abbrev, Text (PetBalance.TEXT), Abilities (PetBalance.ABILITIES), Period, Stats (PetStats), RarityOrder}
function Core.BuildViewModel(state, ui, env)
	ui = type(ui) == "table" and ui or {}
	env = type(env) == "table" and env or {}
	if type(state) ~= "table" then state = nil end
	local lock = Core.LockState(state, ui.Pending == true)
	local vm = {
		Loaded = state ~= nil,
		Sort = Core.SORT_MODES[ui.Sort] and ui.Sort or "Income",
		Filter = Core.FILTER_MODES[ui.Filter] and ui.Filter or "All",
		ActionsEnabled = lock.Enabled,
		Banner = {Visible = lock.Banner, Text = lock.Banner and TextOf(env, "LockBanner") or ""},
		Slots = {},
		Cards = {},
		Known = {},
		Footer = Core.FooterOf(ZERO_TOTALS, env),
		Subtitle = "",
		SelectedId = nil,
	}
	if not state then
		for i = 1, Core.DEFAULT_SLOTS do vm.Slots[i] = {Index = i} end
		return vm
	end
	local pets = type(state.Pets) == "table" and state.Pets or {}
	local equippedIds = type(state.EquippedIds) == "table" and state.EquippedIds or {}
	local slots = Finite(state.Slots) and state.Slots or Core.DEFAULT_SLOTS
	local equippedSet = Core.EquippedSet(state)
	vm.Subtitle = string.format("%d / %d ACTIVE", #equippedIds, slots)
	local list = Core.DisplayList({Pets = pets}, vm.Sort, vm.Filter, env.RarityOrder, equippedSet)
	local selected = ui.SelectedId
	if not (ValidId(selected) and pets[selected]) then
		selected = nil
		if list[1] then
			selected = list[1].Id
		else
			for _, id in ipairs(equippedIds) do
				if pets[id] then selected = id break end
			end
		end
	end
	vm.SelectedId = selected
	for i = 1, slots do
		local id = equippedIds[i]
		local pet = id and pets[id]
		if type(pet) == "table" then
			local slot = CommonOf(pet)
			slot.Index = i
			slot.Selected = id == selected
			vm.Slots[i] = slot
		else
			vm.Slots[i] = {Index = i}
		end
	end
	for id in pairs(pets) do vm.Known[id] = true end
	for i, pet in ipairs(list) do
		vm.Cards[i] = Core.CardOf(pet, equippedSet[pet.Id] == true, pet.Id == selected, env)
	end
	if #list == 0 then
		if next(pets) == nil then
			vm.EmptyText = Core.EMPTY_TEXT.None
		else
			vm.EmptyText = Core.EMPTY_TEXT[vm.Filter] or Core.EMPTY_TEXT.None
		end
	end
	vm.Footer = Core.FooterOf(state.Totals, env)
	if selected then
		local newState = {Pets = pets, AsOf = state.AsOf, EquippedIds = equippedIds, Slots = slots}
		vm.Details = Core.DetailsOf(newState, selected, equippedSet, lock, env)
	end
	return vm
end

--..Runtime..--
local function TryRequire(folder, name, wait)
	if not folder then return nil end
	local module = folder:FindFirstChild(name)
	if not module and wait then module = folder:WaitForChild(name, wait) end
	if not module then return nil end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then return result end
	warn("[PetController] " .. name .. ": " .. tostring(result))
	return nil
end

function PetController.Start(gui, menus)
	local panel = gui:FindFirstChild("PetsPanel")
	if not (panel and panel:FindFirstChild("Content")) then
		warn("[PetController] PetsPanel is missing - run pets-system/builders/build_petspanel.lua")
		return {Destroy = function() end}
	end
	local viewModule = script.Parent:FindFirstChild("PetView")
	if not viewModule then
		warn("[PetController] PetView is missing next to PetController")
		return {Destroy = function() end}
	end
	local view = require(viewModule).Start(gui)
	local isStudio = RunService:IsStudio()
	local destroyed = false
	local connections = {}
	local function connect(signal, fn) table.insert(connections, signal:Connect(fn)) end

	local deps = {} -- NumberAbbrev, Notify, PetsCatalog, PetBalance, PetStats (resolved in the start thread)
	local remoteRequest = nil
	local unavailable = false
	local state = nil
	local needFull = false
	local lastFullAsk = -math.huge
	local fullScheduled = false
	local pending = nil -- {RequestId, Action, At}
	local stateError = nil -- a GetState refusal (shown until a Full arrives)
	local flashText, flashUntil = nil, 0
	local ui = {Sort = "Income", Filter = "All", SelectedId = nil}
	local lastVm = nil
	local renderQueued, dirty = false, true
	local wasOpen = false
	local noticeShown = false

	local function IsOpen()
		return gui:GetAttribute("OpenPanel") == "Pets"
	end

	local function Env()
		local balance = deps.PetBalance
		local abbrev = deps.NumberAbbrev and deps.NumberAbbrev.Abbrev
		return {
			Now = workspace:GetServerTimeNow(),
			Abbrev = abbrev or function(n) return string.format("%g", n) end,
			Text = balance and balance.TEXT or nil,
			Abilities = balance and balance.ABILITIES or nil,
			Period = balance and type(balance.TIMING) == "table" and balance.TIMING.ABILITY_PERIOD or nil,
			Stats = deps.PetStats,
			RarityOrder = deps.PetsCatalog and deps.PetsCatalog.RARITY_ORDER or nil,
		}
	end

	local function StatusLine()
		if flashText and os.clock() < flashUntil then return flashText end
		flashText = nil
		if unavailable then return "Pets unavailable" end
		if not state then return stateError or Core.LOADING_TEXT end
		return nil
	end

	local function Mirror()
		if not isStudio then return end
		local owned, equipped = 0, 0
		if state then
			for _ in pairs(state.Pets) do owned += 1 end
			equipped = #state.EquippedIds
		end
		panel:SetAttribute("PetsRevision", state and state.Revision or -1)
		panel:SetAttribute("PetsOwned", owned)
		panel:SetAttribute("PetsEquipped", equipped)
		panel:SetAttribute("PetsSelected", ui.SelectedId or "")
		panel:SetAttribute("PetsPending", pending ~= nil)
	end

	local function Render()
		renderQueued = false
		if destroyed then return end
		Mirror()
		if not IsOpen() then
			dirty = true
			return
		end
		dirty = false
		local vm = Core.BuildViewModel(state, {Sort = ui.Sort, Filter = ui.Filter, SelectedId = ui.SelectedId, Pending = pending ~= nil}, Env())
		ui.SelectedId = vm.SelectedId
		lastVm = vm
		view.Render(vm)
		view.SetStatus(StatusLine())
		Mirror()
	end
	local function QueueRender()
		if renderQueued or destroyed then return end
		renderQueued = true
		task.defer(Render)
	end

	local function Flash(text)
		flashText, flashUntil = text, os.clock() + ERROR_SECONDS
		view.SetStatus(StatusLine())
	end

	local RequestFull
	RequestFull = function()
		if destroyed then return end
		if not remoteRequest then
			needFull = true
			return
		end
		local now = os.clock()
		if now - lastFullAsk >= FULL_MIN_GAP then
			lastFullAsk = now
			remoteRequest:FireServer({RequestId = Core.NewRequestId(), Action = "GetState"})
		elseif not fullScheduled then
			fullScheduled = true
			task.delay(FULL_MIN_GAP - (now - lastFullAsk) + 0.05, function()
				fullScheduled = false
				if not destroyed and (needFull or not state) then RequestFull() end
			end)
		end
	end

	local function Send(action, fields)
		if destroyed then return false end
		if not remoteRequest then
			Flash(unavailable and "Pets unavailable" or "Your pets are still loading - try again in a moment.")
			return false
		end
		if pending then return false end
		local lock = Core.LockState(state, false)
		if not lock.Enabled then
			if lock.Reason == "CombatLocked" then Flash(TextOf(Env(), "LockBanner")) end
			return false
		end
		local request = {RequestId = Core.NewRequestId(), Action = action}
		for key, value in pairs(fields or {}) do request[key] = value end
		pending = {RequestId = request.RequestId, Action = action, At = os.clock()}
		remoteRequest:FireServer(request)
		QueueRender()
		return true
	end

	local function OnState(payload)
		if destroyed or type(payload) ~= "table" then return end
		local result = type(payload.Result) == "table" and payload.Result or nil
		-- 2026-09-22: PetService's unsolicited hatch refusal (the inventory is full) is a toast, panel open or not
		if result and result.Ok == false and result.Action == "Hatch" and deps.Notify and type(deps.Notify.Error) == "function" then
			pcall(deps.Notify.Error, Core.ErrorText(result.Error, Env()), NOTICE_SECONDS)
		end
		local refused = Core.IsRefusal(payload)
		-- the reply to our roster request frees the buttons, whatever its revision
		if pending and payload.RequestId ~= nil and payload.RequestId == pending.RequestId then
			pending = nil
			if result and result.Ok == false then
				Flash(Core.ErrorText(result.Error, Env()))
				view.Feedback(false)
			else
				view.Feedback(true)
			end
		elseif result and result.Ok == false and (result.Action == "GetState" or refused) and not state then
			stateError = Core.StateErrorText(result.Error, Env())
		end
		local newState, gap = Core.ApplyState(state, payload, workspace:GetServerTimeNow())
		if payload.Kind == "Full" then
			if type(payload.Notice) == "string" and payload.Notice ~= "" and not noticeShown then
				noticeShown = true
				if deps.Notify then pcall(deps.Notify.Info, payload.Notice, NOTICE_SECONDS) end
			end
			if refused then
				-- 2026-09-22: not state (ApplyState kept what was held); the open / 5 s retry asks again and
				-- PetService pushes a Full of its own once the pets have loaded
				needFull = true
			elseif newState ~= state and newState ~= nil then
				needFull = false
				stateError = nil
			end
		end
		state = newState
		if gap then
			needFull = true
			RequestFull()
		end
		-- 2026-09-22 (review): a Totals message only changes the footer; a queued render or the next open
		-- draws it anyway, so the open panel just gets its footer rewritten (no view model, no card pass)
		if payload.Kind == "Totals" then
			if state and IsOpen() and not renderQueued then view.SetFooter(Core.FooterOf(state.Totals, Env())) end
			return
		end
		QueueRender()
	end

	--..View callbacks..--
	view.OnSelect(function(petId)
		if type(petId) ~= "string" then return end
		ui.SelectedId = petId
		QueueRender()
	end)
	view.OnEquip(function(petId, equip)
		if not ValidId(petId) then return end
		Send(equip and "Equip" or "Unequip", {PetId = petId})
	end)
	view.OnBest(function(mode)
		if Core.BEST_MODES[mode] then Send("EquipBest", {SortMode = mode}) end
	end)
	view.OnSort(function(mode)
		if Core.SORT_MODES[mode] then
			ui.Sort = mode
			QueueRender()
		end
	end)
	view.OnFilter(function(mode)
		if Core.FILTER_MODES[mode] then
			ui.Filter = mode
			QueueRender()
		end
	end)

	--..Opening / gamepad focus..--
	local function ClearFocus()
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(panel) then GuiService.SelectedObject = nil end
	end
	local function Focus()
		if destroyed or not IsOpen() or not UserInputService.GamepadEnabled then return end
		local target = view.FocusTarget(not state or #state.EquippedIds == 0)
		if target then GuiService.SelectedObject = target end
	end
	connect(gui:GetAttributeChangedSignal("OpenPanel"), function()
		local open = IsOpen()
		if open then
			if not state or needFull then RequestFull() end
			Render()
			if not wasOpen then task.delay(0.05, Focus) end
		elseif wasOpen then
			ClearFocus()
		end
		wasOpen = open
	end)

	--..P / ButtonL3..--
	local hud = gui.Parent and gui.Parent:FindFirstChild("CucumberHUDDesign")
	ContextActionService:BindAction(ACTION_NAME, function(_, inputState)
		if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		if not gui.Enabled then return Enum.ContextActionResult.Pass end
		hud = hud or (gui.Parent and gui.Parent:FindFirstChild("CucumberHUDDesign"))
		if hud and (hud:GetAttribute("BuildMode") == true or hud:GetAttribute("BenchMode") == true) then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then menus.Toggle("Pets") end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.P, Enum.KeyCode.ButtonL3)

	--..One stepper: countdown, pending timeout, retries..--
	local elapsed = 0
	connect(RunService.Heartbeat, function(dt)
		elapsed += dt
		if elapsed < STEP_SECONDS then return end
		elapsed = 0
		if pending and os.clock() - pending.At > PENDING_TIMEOUT then
			pending = nil
			needFull = true
			RequestFull()
			QueueRender()
		end
		if not IsOpen() then return end
		if (not state or needFull) and remoteRequest and os.clock() - lastFullAsk >= FULL_RETRY then RequestFull() end
		if flashText and os.clock() >= flashUntil then view.SetStatus(StatusLine()) end
		if state and ui.SelectedId and state.Pets[ui.SelectedId] then
			local equipped = table.find(state.EquippedIds, ui.SelectedId) ~= nil
			local pet = state.Pets[ui.SelectedId]
			view.SetNextRoll(Core.NextRollText(pet, state.AsOf[ui.SelectedId], workspace:GetServerTimeNow(), Env(), equipped))
		end
	end)

	--..Dev hook (Studio only)..--
	if isStudio then
		connect(panel:GetAttributeChangedSignal("PetsDev"), function()
			local command = panel:GetAttribute("PetsDev")
			if type(command) ~= "string" or command == "" then return end
			panel:SetAttribute("PetsDev", nil)
			local verb, arg = command:match("^(%a+):?(.*)$")
			if verb == "open" then
				menus.Open("Pets")
			elseif verb == "close" then
				menus.Close()
			elseif verb == "select" then
				local list = Core.DisplayList(state, ui.Sort, ui.Filter, Env().RarityOrder, Core.EquippedSet(state))
				local n = math.clamp(math.floor(tonumber(arg) or 1), 1, math.max(1, #list))
				if list[n] then
					ui.SelectedId = list[n].Id
					if view.ShowDetails then view.ShowDetails(true) end -- compact: like tapping the card
					QueueRender()
				end
			elseif verb == "back" then
				if view.ShowDetails then view.ShowDetails(false) end
			elseif verb == "equip" then
				local vm = Core.BuildViewModel(state, {Sort = ui.Sort, Filter = ui.Filter, SelectedId = ui.SelectedId, Pending = pending ~= nil}, Env())
				local d = vm.Details
				if d and d.EquipEnabled and d.EquipAction then
					Send(d.EquipAction, {PetId = d.Id})
				else
					print("PetsDev: equip button disabled (" .. tostring(d and d.EquipText or "no pet selected") .. ")")
				end
			elseif verb == "best" then
				if Core.BEST_MODES[arg] then Send("EquipBest", {SortMode = arg}) end
			elseif verb == "sort" then
				if Core.SORT_MODES[arg] then ui.Sort = arg QueueRender() end
			elseif verb == "filter" then
				if Core.FILTER_MODES[arg] then ui.Filter = arg QueueRender() end
			end
		end)
	end

	--..Modules + remotes (never blocks Start)..--
	task.spawn(function()
		local modules = ReplicatedStorage:FindFirstChild("Modules") or ReplicatedStorage:WaitForChild("Modules", REMOTE_WAIT)
		deps.NumberAbbrev = TryRequire(modules, "NumberAbbrev", 10)
		deps.Notify = TryRequire(modules, "Notify", 10)
		deps.PetsCatalog = TryRequire(modules, "PetsCatalog", 10)
		-- PetStats waits on PetBalance at require time, so it is required only once both are there
		if modules and modules:FindFirstChild("PetBalance") and modules:FindFirstChild("PetStats") then
			deps.PetBalance = TryRequire(modules, "PetBalance")
			deps.PetStats = TryRequire(modules, "PetStats")
		else
			warn("[PetController] PetBalance / PetStats not installed - ability texts are blank")
		end
		if destroyed then return end
		QueueRender()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
		local stateRemote = remotes and remotes:WaitForChild("PetState", REMOTE_WAIT)
		local requestRemote = remotes and remotes:WaitForChild("PetRequest", REMOTE_WAIT)
		if destroyed then return end
		if not (stateRemote and requestRemote) then
			warn("[PetController] Remotes.PetState / PetRequest not found - Pets unavailable")
			unavailable = true
			view.SetStatus(StatusLine())
			QueueRender()
			return
		end
		connect(stateRemote.OnClientEvent, OnState)
		remoteRequest = requestRemote
		RequestFull()
	end)

	view.SetStatus(StatusLine())
	Render()
	return {Destroy = function()
		destroyed = true
		for _, connection in ipairs(connections) do connection:Disconnect() end
		pcall(function() ContextActionService:UnbindAction(ACTION_NAME) end)
		ClearFocus()
		view.Destroy()
	end}
end

return PetController
