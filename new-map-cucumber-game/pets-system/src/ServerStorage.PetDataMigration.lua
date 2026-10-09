--[[
	PetDataMigration  (ModuleScript, ServerStorage)
	The pet-system profile migration (2026-09-22). Pure table work on profile.Data.Base:
	DataService runs it on every loaded profile after Reconcile and BEFORE the profile is exposed
	(and again inside ResetProfile, Scope "All"); PetService.EnsureProfileState re-runs it with
	Scope "Pets" (pets + roster only, Eggs / Cucumbers are never touched by a runtime re-run).

	Migrate(data, ctx) -> report      mutates data.Base in place; idempotent (a second run changes
	                                  nothing and keeps every Id); never errors on bad data
	  ctx = {GenerateId = fn() -> string (default HttpService GUID), Now = number? (accepted, unused:
	         legacy AcquiredAt stays 0), IsSpawnable = fn(petKey) -> boolean (default IsSpawnable),
	         Scope = "All" (default) | "Pets" (anything else is treated as "Pets")}
	  1. data.Base must be a table (else report.Error = "NoBase"). A missing Pets array (and, Scope
	     "All", Eggs / Cucumbers) is created; a present non-table is left alone + a warning.
	  2. Eggs ("All"): an Id when missing/invalid. A DUPLICATE egg Id is left alone: eggs are
	     single-use, a fresh Id would make a copy hatchable twice (BaseSave Restore keeps the first).
	  3. Cucumbers ("All"): an Id when missing/invalid; a later duplicate gets a fresh one.
	  4. Pets: an Id when missing/invalid (a later duplicate gets a fresh one, the first keeps it),
	     then ONLY missing/invalid fields are filled: SourceEgg (reverse catalog map; left nil for an
	     unknown species), Material "", Mutations (comma string -> array, broken array cleaned, a
	     clean string array is kept exactly), AcquiredAt 0, AbilityRemaining 60 (also when outside
	     0..60). Pos, SourceEggId, EggKg and unknown fields are never touched; non-table entries stay
	     where they are (report.Invalid).
	  5. Roster: no PetSchemaVersion yet (legacy) -> PetRoster = the six best spawnable pets by income
	     (PetStats.Compare "Income") + PetNoticePending when any legacy pet record existed (the
	     one-time "six active pets" notice); otherwise RepairRoster.
	  6. PetSchemaVersion = SCHEMA_VERSION, written LAST (never lowered).
	  report = {Legacy, IdsAssigned (pet Ids minted), DuplicateIds (pet duplicates re-Id'd),
	            DuplicateEggIds (left alone), DuplicateCucumberIds (re-Id'd), Invalid (non-table pets),
	            RosterSize, EggIds / CucumberIds (Ids minted), UnknownTraits (pets with an unknown
	            mutation / material name), Changed (anything written), Error?, Warnings (<= 20)}
	SelectInitialRoster(pets, isSpawnable?, slots?) -> {id}   valid-Id, spawnable, Stats.Valid pets,
	                                  best income first, at most `slots`
	RepairRoster(base) -> changed     keeps owned Id strings only, first occurrence, at most SLOTS
	                                  (dropped extras stay owned); also used by PetService
	IsSpawnable(petKey) -> boolean    a PetsCatalog.PETS key whose model is in ReplicatedStorage.Assets.Pets
	Never: changes Base.Version, adds/removes egg / cucumber / build / pet records, touches keys
	outside data.Base, yields, saves, spawns, reads Workspace.
]]

--..Services..--
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
--.. FindFirstChild, never WaitForChild: DataService requires this inside OnPlayerAdded, which must not
--.. yield. A missing module errors here and DataService's pcall(require) turns that into a report.
local function Need(parent, name)
	local child = parent and parent:FindFirstChild(name)
	if not child then error(("[PetDataMigration] %s is missing"):format(name), 0) end
	return child
end
local Modules = Need(ReplicatedStorage, "Modules")
local PetBalance = require(Need(Modules, "PetBalance"))
local PetStats = require(Need(Modules, "PetStats"))
local PetsCatalog = require(Need(Modules, "PetsCatalog"))

--..Config..--
local SCHEMA_VERSION = 1
local SLOTS = PetBalance.SLOTS
local ABILITY_PERIOD = PetBalance.TIMING.ABILITY_PERIOD
local MAX_WARNINGS = 20
local MINT_ATTEMPTS = 16
local ARRAY_KEYS = {"Pets", "Eggs", "Cucumbers"}

local PetDataMigration = {}
PetDataMigration.SCHEMA_VERSION = SCHEMA_VERSION

--..Functions..--
local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function IsValidId(id)
	return type(id) == "string" and #id >= 1 and #id <= 64
end

local function DefaultId()
	return HttpService:GenerateGUID(false)
end

local function NewReport()
	return {
		Legacy = false, IdsAssigned = 0, DuplicateIds = 0, DuplicateEggIds = 0, DuplicateCucumberIds = 0,
		Invalid = 0, RosterSize = 0, EggIds = 0, CucumberIds = 0, UnknownTraits = 0, Changed = false,
		Error = nil, Warnings = {},
	}
end

local function Warn(report, message)
	if #report.Warnings < MAX_WARNINGS then table.insert(report.Warnings, message) end
end

--.. a fresh valid id nobody holds yet (a GUID never repeats; the retry only matters for test generators)
local function Mint(generate, taken)
	for _ = 1, MINT_ATTEMPTS do
		local id = generate()
		if IsValidId(id) and not taken[id] then
			taken[id] = true
			return id
		end
	end
	error("[PetDataMigration] GenerateId gave no fresh valid id", 0)
end

--.. a clean saved mutation list: nothing but strings at 1..n (duplicates / case are left as saved)
local function IsStringArray(value)
	if type(value) ~= "table" then return false end
	local count = 0
	for key, item in pairs(value) do
		if type(key) ~= "number" or type(item) ~= "string" then return false end
		count += 1
	end
	return count == #value
end

function PetDataMigration.IsSpawnable(petKey)
	return type(petKey) == "string" and PetsCatalog.PETS[petKey] ~= nil and PetsCatalog.ModelOf(petKey) ~= nil
end

--.. the migration's first roster: best income first (then DPS, then Id), unknown / unspawnable skipped
function PetDataMigration.SelectInitialRoster(pets, isSpawnable, slots)
	local roster = {}
	if type(pets) ~= "table" then return roster end
	if type(isSpawnable) ~= "function" then isSpawnable = PetDataMigration.IsSpawnable end
	slots = Finite(slots) and math.max(0, math.floor(slots)) or SLOTS
	local candidates, used = {}, {}
	for _, rec in ipairs(pets) do
		if type(rec) == "table" and IsValidId(rec.Id) and not used[rec.Id] and type(rec.Pet) == "string" then
			used[rec.Id] = true
			local ok, spawnable = pcall(isSpawnable, rec.Pet)
			if ok and spawnable then
				local stats = PetStats.Calculate(rec)
				if type(stats) == "table" and stats.Valid then
					table.insert(candidates, {Id = rec.Id, Stats = stats})
				end
			end
		end
	end
	table.sort(candidates, function(a, b) return PetStats.Compare(a, b, "Income") end)
	for i = 1, math.min(slots, #candidates) do roster[i] = candidates[i].Id end
	return roster
end

--.. owned Id strings only, first occurrence, at most SLOTS; a new table only when something changed
function PetDataMigration.RepairRoster(base)
	if type(base) ~= "table" or type(base.Pets) ~= "table" then return false end
	local roster = base.PetRoster
	if type(roster) ~= "table" then
		base.PetRoster = {}
		return true
	end
	local owned = {}
	for _, rec in ipairs(base.Pets) do
		if type(rec) == "table" and IsValidId(rec.Id) then owned[rec.Id] = true end
	end
	local clean, used = {}, {}
	for _, id in ipairs(roster) do
		if #clean >= SLOTS then break end
		if type(id) == "string" and owned[id] and not used[id] then
			used[id] = true
			table.insert(clean, id)
		end
	end
	local count = 0
	for _ in pairs(roster) do count += 1 end
	if count == #clean then
		local same = true
		for i, id in ipairs(clean) do
			if roster[i] ~= id then same = false break end
		end
		if same then return false end
	end
	base.PetRoster = clean
	return true
end

--.. fills only missing/invalid pet fields; returns whether anything was written
local function FillPetFields(rec, report)
	local changed = false
	local petKey = rec.Pet
	if type(petKey) ~= "string" or PetsCatalog.PETS[petKey] == nil then
		Warn(report, "UnknownSpecies:" .. tostring(petKey))
	end
	if type(rec.SourceEgg) ~= "string" or rec.SourceEgg == "" then
		local eggKey = type(petKey) == "string" and PetStats.EggOf(petKey) or nil
		if eggKey then
			rec.SourceEgg = eggKey
			changed = true
		end
	end
	local material = PetStats.NormalizeMaterial(rec.Material)
	if rec.Material ~= material then
		rec.Material = material
		changed = true
	end
	if not IsStringArray(rec.Mutations) then
		local old = rec.Mutations
		rec.Mutations = (type(old) == "string" or type(old) == "table") and PetStats.NormalizeMutations(old) or {}
		changed = true
	end
	local _, unknown = PetStats.SplitMutations(rec.Mutations)
	if (type(unknown) == "table" and #unknown > 0) or (material ~= "" and PetBalance.MATERIALS[material] == nil) then
		report.UnknownTraits += 1
	end
	if not Finite(rec.AcquiredAt) then
		rec.AcquiredAt = 0
		changed = true
	end
	local remaining = rec.AbilityRemaining
	if not Finite(remaining) or remaining < 0 or remaining > ABILITY_PERIOD then
		rec.AbilityRemaining = ABILITY_PERIOD
		changed = true
	end
	return changed
end

function PetDataMigration.Migrate(data, ctx)
	local report = NewReport()
	if type(ctx) ~= "table" then ctx = {} end
	local base = type(data) == "table" and data.Base or nil
	if type(base) ~= "table" then
		report.Error = "NoBase"
		Warn(report, type(data) == "table" and "BaseNotTable" or "DataNotTable")
		return report
	end
	local generate = type(ctx.GenerateId) == "function" and ctx.GenerateId or DefaultId
	local isSpawnable = type(ctx.IsSpawnable) == "function" and ctx.IsSpawnable or PetDataMigration.IsSpawnable
	local scope = ctx.Scope
	if scope == nil then scope = "All" end
	if scope ~= "All" and scope ~= "Pets" then
		Warn(report, "UnknownScope:" .. tostring(scope))
		scope = "Pets" -- the narrower run: never touches eggs / cucumbers
	end

	-- 1. arrays
	if base.Pets == nil then
		base.Pets = {}
		report.Changed = true
	end
	if scope == "All" then
		for _, key in ipairs({"Eggs", "Cucumbers"}) do
			if base[key] == nil then
				base[key] = {}
				report.Changed = true
			end
		end
	end
	local taken = {} -- every valid Id already saved, so a minted one never collides
	for _, key in ipairs(ARRAY_KEYS) do
		local list = base[key]
		if type(list) == "table" then
			for _, rec in ipairs(list) do
				if type(rec) == "table" and IsValidId(rec.Id) then taken[rec.Id] = true end
			end
		elseif list ~= nil then
			Warn(report, key .. "NotTable")
		end
	end

	if scope == "All" then
		-- 2. eggs: single-use, so a duplicate Id is reported and left (BaseSave Restore drops the copy)
		if type(base.Eggs) == "table" then
			local seen = {}
			for index, rec in ipairs(base.Eggs) do
				if type(rec) ~= "table" then
					Warn(report, ("EggNotTable:%d"):format(index))
				elseif not IsValidId(rec.Id) then
					rec.Id = Mint(generate, taken)
					seen[rec.Id] = true
					report.EggIds += 1
					report.Changed = true
				elseif seen[rec.Id] then
					report.DuplicateEggIds += 1
					Warn(report, "DuplicateEggId:" .. rec.Id)
				else
					seen[rec.Id] = true
				end
			end
		end
		-- 3. cucumbers: a later duplicate gets a fresh Id (PetBuffs are left for Restore to filter)
		if type(base.Cucumbers) == "table" then
			local seen = {}
			for index, rec in ipairs(base.Cucumbers) do
				if type(rec) ~= "table" then
					Warn(report, ("CucumberNotTable:%d"):format(index))
				else
					if not IsValidId(rec.Id) or seen[rec.Id] then
						if IsValidId(rec.Id) then
							report.DuplicateCucumberIds += 1
							Warn(report, "DuplicateCucumberId:" .. rec.Id)
						end
						rec.Id = Mint(generate, taken)
						report.CucumberIds += 1
						report.Changed = true
					end
					seen[rec.Id] = true
				end
			end
		end
	end

	local pets = base.Pets
	if type(pets) ~= "table" then
		return report -- nothing to convert: no roster, no schema marker (conversion did not happen)
	end

	-- 4. pets
	local legacyPets = 0
	local seen = {}
	for index, rec in ipairs(pets) do
		if type(rec) ~= "table" then
			report.Invalid += 1
			Warn(report, ("PetNotTable:%d"):format(index))
			continue
		end
		legacyPets += 1
		if not IsValidId(rec.Id) or seen[rec.Id] then
			if IsValidId(rec.Id) then
				report.DuplicateIds += 1
				Warn(report, "DuplicatePetId:" .. rec.Id)
			end
			rec.Id = Mint(generate, taken)
			report.IdsAssigned += 1
			report.Changed = true
		end
		seen[rec.Id] = true
		if FillPetFields(rec, report) then report.Changed = true end
	end

	-- 5. roster
	local schema = base.PetSchemaVersion
	local legacy = not (Finite(schema) and schema >= 1)
	report.Legacy = legacy
	if legacy then
		base.PetRoster = PetDataMigration.SelectInitialRoster(pets, isSpawnable, SLOTS)
		if legacyPets > 0 then base.PetNoticePending = true end
		report.Changed = true
	elseif PetDataMigration.RepairRoster(base) then
		report.Changed = true
	end
	report.RosterSize = type(base.PetRoster) == "table" and #base.PetRoster or 0

	-- 6. the schema marker, last
	if not (Finite(schema) and schema >= SCHEMA_VERSION) then
		base.PetSchemaVersion = SCHEMA_VERSION
		report.Changed = true
	end
	return report
end

return PetDataMigration
