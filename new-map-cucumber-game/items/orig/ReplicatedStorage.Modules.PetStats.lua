--[[
	PetStats  (ModuleScript, ReplicatedStorage.Modules)
	Pure pet maths (2026-09-22, pet-system polish): turns a saved pet record {Pet, Material,
	Mutations} into income / combat / ability numbers from PetBalance + PetsCatalog, and builds every
	ability text from the PetBalance numbers. The server (PetService, PetDataMigration, IncomeService,
	PetBuffService, PetCombatService) and the clients (Pets menu, reveal card, pet cards, effects)
	call the SAME functions, so a number shown is the number paid. No state, no randomness, no
	Instances (PetsCatalog.ModelOf is never called here); nothing here ever errors.

	  SpeciesEgg[petKey] = {Egg, Tier, Rank?}   built once at require from PetsCatalog.EGGS
	                                            (PetBalance.RANK_OVERRIDES wins over the pool rank)
	  IsFinite(x)  IsValidId(id)  EggOf(petKey) -> eggKey?, tier?, rank?  EggKeyOfShortName("Desert")
	  NormalizeMaterial(v) -> "" | name      NormalizeMutations(v) -> {names}  (comma string or array;
	    known names upper-cased, unknown kept byte-for-byte, distinct, a string reads 16 tokens max,
	    an array is never truncated)       SplitMutations(list) -> known, unknown
	  MutationString(list) -> "NEON,VOID" (known only, for CucumberMutations.ApplyLook / attributes)
	  AffixIncome(material, mutations)  AffixDamage(material, mutations)  AbilityOf(petKey)
	  Calculate(record) -> Stats (always finite; Valid = false only when record.Pet is no PETS key)
	  Compare(a, b, mode) {Id, Stats} "Income" | "Combat" (Id tie-break; table.sort ready)
	  GuardSeconds(day, night)  RateMultiplier({Yield = true, Haste = true}) -> 1.875
	  AbilityBadge(kind)  AbilityShort(kind, guardSeconds?)  AbilityEffect(kind, guardSeconds?)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PetBalance = require(Modules:WaitForChild("PetBalance"))
local PetsCatalog = require(Modules:WaitForChild("PetsCatalog"))

local PetStats = {}

local MAX_WARNINGS = 8 -- Stats.Warnings / Stats.UnknownMutations length cap
local MAX_STRING_TOKENS = 16 -- tokens read from a comma string (egg / cucumber source)
local ABILITY_KINDS = {Yield = true, Haste = true, Guard = true, Wild = true, None = true}

local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function Num(x, fallback)
	if Finite(x) then return x end
	return fallback
end

local function Round(x)
	return math.floor(x + 0.5)
end

local function Tab(x)
	return type(x) == "table" and x or {}
end

local MAX_RANK = math.max(1, math.floor(Num(PetBalance.MAX_RANK, 6)))
local MAX_ID_LENGTH = Num(Tab(PetBalance.REQUESTS).MAX_ID_LENGTH, 64)

PetStats.IsFinite = Finite

function PetStats.IsValidId(id)
	return type(id) == "string" and #id >= 1 and #id <= MAX_ID_LENGTH
end

--..SpeciesEgg: which egg a species hatches from (tier + rank), built once..--
local SpeciesEgg = {}
PetStats.SpeciesEgg = SpeciesEgg -- read-only for callers
do
	local tiers = Tab(PetBalance.EGG_TIERS)
	local overrides = Tab(PetBalance.RANK_OVERRIDES)
	for eggKey, egg in pairs(Tab(PetsCatalog.EGGS)) do
		local pool = type(egg) == "table" and egg.Pets or nil
		if type(eggKey) == "string" and type(pool) == "table" then
			local tier = tiers[eggKey]
			local tierKnown = Finite(tier) and tier >= 1
			tier = tierKnown and math.floor(tier) or 1
			for petKey, entry in pairs(pool) do
				if type(petKey) == "string" then
					local rank = overrides[petKey]
					if rank == nil and type(entry) == "table" then rank = entry.Rank end
					if not Finite(rank) then rank = nil end
					--.. a pet in two pools (PetBalance.Validate flags it): lowest tier, then egg name, so the pick is stable
					local current = SpeciesEgg[petKey]
					if not current or tier < current.Tier or (tier == current.Tier and eggKey < current.Egg) then
						SpeciesEgg[petKey] = {Egg = eggKey, Tier = tier, Rank = rank, TierKnown = tierKnown}
					end
				end
			end
		end
	end
end

--.. raw rank (override first) -> clamped rank, changed?  nil when there is no usable rank
local function RankOf(petKey)
	local raw = Tab(PetBalance.RANK_OVERRIDES)[petKey]
	if raw == nil then
		local egg = SpeciesEgg[petKey]
		raw = egg and egg.Rank
	end
	if not Finite(raw) then return nil, false end
	local rank = math.clamp(math.floor(raw), 1, MAX_RANK)
	return rank, rank ~= raw
end

function PetStats.EggOf(petKey)
	local egg = type(petKey) == "string" and SpeciesEgg[petKey] or nil
	if not egg then return nil, nil, nil end
	return egg.Egg, egg.Tier, (RankOf(petKey))
end

--.. "Desert" -> "Desert Egg" (EggShop / EggPlacement stamp the short biome name)
function PetStats.EggKeyOfShortName(shortName)
	if type(shortName) ~= "string" or type(PetsCatalog.EggKey) ~= "function" then return nil end
	local ok, key = pcall(PetsCatalog.EggKey, shortName)
	return ok and type(key) == "string" and key or nil
end

--..traits (material + mutations)..--
function PetStats.NormalizeMaterial(value)
	if type(value) ~= "string" then return "" end
	return value
end

local function MaterialRow(material)
	if type(material) ~= "string" or material == "" then return nil end
	local row = Tab(PetBalance.MATERIALS)[material]
	return type(row) == "table" and row or nil
end

local function KnownMutation(token)
	local upper = token:upper()
	if type(Tab(PetBalance.MUTATIONS)[upper]) == "table" then return upper end
	return nil
end

function PetStats.NormalizeMutations(value)
	local out, seen = {}, {}
	local function Push(token)
		if type(token) ~= "string" or token == "" then return end
		local stored = KnownMutation(token) or token
		if seen[stored] then return end
		seen[stored] = true
		out[#out + 1] = stored
	end
	if type(value) == "string" then
		local read = 0
		for token in value:gmatch("[^,%s]+") do
			read += 1
			if read > MAX_STRING_TOKENS then break end
			Push(token)
		end
	elseif type(value) == "table" then
		--.. array order; holes skipped rather than stopping the walk, never truncated
		local indices = {}
		for k in pairs(value) do
			if type(k) == "number" and k >= 1 and k % 1 == 0 then indices[#indices + 1] = k end
		end
		table.sort(indices)
		for _, i in ipairs(indices) do Push(value[i]) end
	end
	return out
end

function PetStats.SplitMutations(list)
	local known, unknown = {}, {}
	for _, token in ipairs(PetStats.NormalizeMutations(list)) do
		local canonical = KnownMutation(token)
		if canonical then
			known[#known + 1] = canonical
		else
			unknown[#unknown + 1] = token
		end
	end
	return known, unknown
end

function PetStats.MutationString(list)
	local known = PetStats.SplitMutations(list)
	return table.concat(known, ",")
end

--.. known = distinct canonical mutation names -> AffixIncome, AffixDamage
local function Affixes(material, known)
	local mat = MaterialRow(material)
	local matIncome = mat and Num(mat.Income, 1) or 1
	local combat = mat and Num(mat.Combat, 0) or 0
	local incomeBonus = 0
	local mutations = Tab(PetBalance.MUTATIONS)
	for _, name in ipairs(known) do
		local row = mutations[name]
		if type(row) == "table" then
			incomeBonus += Num(row.Income, 0)
			combat += Num(row.Combat, 0)
		end
	end
	local income = math.min(Num(PetBalance.INCOME_AFFIX_CAP, math.huge), matIncome * (1 + incomeBonus))
	local damage = 1 + math.min(Num(PetBalance.DAMAGE_AFFIX_CAP, math.huge), combat)
	return Num(income, 1), Num(damage, 1)
end

function PetStats.AffixIncome(material, mutations)
	local known = PetStats.SplitMutations(mutations)
	return (Affixes(PetStats.NormalizeMaterial(material), known))
end

function PetStats.AffixDamage(material, mutations)
	local known = PetStats.SplitMutations(mutations)
	local _, damage = Affixes(PetStats.NormalizeMaterial(material), known)
	return damage
end

--.. -> ability, hasRow
local function AbilityRowOf(petKey)
	if type(petKey) ~= "string" or Tab(PetsCatalog.PETS)[petKey] == nil then return "None", false end
	local ability = Tab(PetBalance.SPECIES_ABILITY)[petKey]
	if ability == nil then return "None", false end
	if ABILITY_KINDS[ability] then return ability, true end
	return "None", true
end

function PetStats.AbilityOf(petKey)
	return (AbilityRowOf(petKey))
end

--..Calculate..--
local function AddWarning(stats, code)
	local warnings = stats.Warnings
	if #warnings >= MAX_WARNINGS then return end
	for _, w in ipairs(warnings) do
		if w == code then return end
	end
	warnings[#warnings + 1] = code
end

local function EmptyStats(pet)
	return {
		Valid = false,
		Pet = pet,
		DisplayName = pet or "Unknown pet",
		Rarity = type(PetBalance.FALLBACK_RARITY) == "string" and PetBalance.FALLBACK_RARITY or "Common",
		RarityKnown = false,
		EggKey = nil, EggTier = 0, Rank = 0,
		AffixIncome = 0, AffixDamage = 0,
		Income = 0, ShotDamage = 0, ShotInterval = 0, DPS = 0, Range = 0,
		Ability = "None", AbilityChance = 0, Fighter = false,
		UnknownMutations = {}, UnknownMaterial = nil, Warnings = {},
	}
end

local function Calculate(record)
	local pet = type(record) == "table" and record.Pet or nil
	if type(pet) ~= "string" then pet = nil end
	local stats = EmptyStats(pet)
	local info = pet and Tab(PetsCatalog.PETS)[pet]
	if info == nil then
		AddWarning(stats, "UnknownPet")
		return stats
	end
	stats.Valid = true
	info = Tab(info)
	if type(info.DisplayName) == "string" then stats.DisplayName = info.DisplayName end

	--.. rarity row (unknown -> the fallback row, the catalog word kept for display)
	local rarities = Tab(PetBalance.RARITY)
	local row = type(info.Rarity) == "string" and rarities[info.Rarity] or nil
	if type(row) == "table" then
		stats.Rarity, stats.RarityKnown = info.Rarity, true
	else
		row = Tab(rarities[stats.Rarity])
		if type(info.Rarity) == "string" then stats.Rarity = info.Rarity end
		AddWarning(stats, "UnknownRarity")
	end

	--.. egg tier + rank
	local egg = SpeciesEgg[pet]
	local tier = 1
	if egg then
		stats.EggKey, tier = egg.Egg, egg.Tier
		if not egg.TierKnown then AddWarning(stats, "NoTier") end
	else
		AddWarning(stats, "NoEgg")
	end
	local rank, clamped = RankOf(pet)
	if not rank then
		rank = 1
		AddWarning(stats, "NoRank")
	elseif clamped then
		AddWarning(stats, "RankClamped")
	end
	stats.EggTier, stats.Rank = tier, rank

	--.. traits (unknown names kept for display/recovery, ignored in the maths)
	local material = PetStats.NormalizeMaterial(record.Material)
	if material ~= "" and not MaterialRow(material) then
		stats.UnknownMaterial = material
		AddWarning(stats, "UnknownMaterial")
	end
	local known, unknown = PetStats.SplitMutations(record.Mutations)
	for i = 1, math.min(#unknown, MAX_WARNINGS) do stats.UnknownMutations[i] = unknown[i] end
	if #unknown > 0 then AddWarning(stats, "UnknownMutations") end
	local affixIncome, affixDamage = Affixes(material, known)

	--.. ability
	local ability, hasRow = AbilityRowOf(pet)
	if not hasRow then
		AddWarning(stats, "NoAbilityRow")
	elseif ability == "None" and Tab(PetBalance.SPECIES_ABILITY)[pet] ~= "None" then
		AddWarning(stats, "UnknownAbility")
	end
	local fighter = ability == "None"

	--.. numbers
	local income = Num(PetBalance.BASE_INCOME, 0) * Num(PetBalance.TIER_STEP, 1) ^ (tier - 1)
		* Num(row.Income, 0) * (1 + Num(PetBalance.RANK_STEP, 0) * (rank - 1)) * affixIncome
	local shot = Num(row.Damage, 0) * (1 + Num(PetBalance.BIOME_DAMAGE_STEP, 0) * (tier - 1)) * affixDamage
		* (fighter and Num(PetBalance.FIGHTER_MULT, 1) or 1)
	local interval = Num(row.Interval, 0)
	if interval <= 0 then
		interval = 0
		AddWarning(stats, "BadInterval")
	end
	local chance = fighter and 0 or math.clamp(Num(row.Chance, 0), 0, 1)

	local function Clean(x)
		if Finite(x) then return x end
		AddWarning(stats, "NonFinite")
		return 0
	end
	stats.AffixIncome = Clean(affixIncome)
	stats.AffixDamage = Clean(affixDamage)
	stats.Income = Clean(income)
	stats.ShotDamage = Clean(shot)
	stats.ShotInterval = interval
	stats.DPS = interval > 0 and Clean(stats.ShotDamage / interval) or 0
	stats.Range = Clean(Num(row.Range, 0))
	stats.Ability = ability
	stats.AbilityChance = chance
	stats.Fighter = fighter
	return stats
end

function PetStats.Calculate(record)
	local ok, stats = pcall(Calculate, record)
	if ok and type(stats) == "table" then return stats end
	local pet = type(record) == "table" and rawget(record, "Pet") or nil
	stats = EmptyStats(type(pet) == "string" and pet or nil)
	AddWarning(stats, "Error")
	return stats
end

--..sorting..--
local function StatOf(entry, field)
	local stats = type(entry) == "table" and entry.Stats or nil
	local v = type(stats) == "table" and stats[field] or nil
	return Finite(v) and v or 0
end

local function IdOf(entry)
	local id = type(entry) == "table" and entry.Id or nil
	return type(id) == "string" and id or tostring(id or "")
end

--.. mode "Income" (default): Income desc, DPS desc, Id asc; "Combat": DPS desc, Income desc, Id asc
function PetStats.Compare(a, b, mode)
	local first, second = "Income", "DPS"
	if mode == "Combat" then first, second = "DPS", "Income" end
	local a1, b1 = StatOf(a, first), StatOf(b, first)
	if a1 ~= b1 then return a1 > b1 end
	local a2, b2 = StatOf(a, second), StatOf(b, second)
	if a2 ~= b2 then return a2 > b2 end
	return IdOf(a) < IdOf(b)
end

--..ability timing / rate..--
function PetStats.GuardSeconds(daySeconds, nightSeconds)
	local guard = Tab(PetBalance.GUARD)
	local day = (Finite(daySeconds) and daySeconds >= 0) and daySeconds or Num(PetBalance.DEFAULT_DAY_SECONDS, 0)
	local night = (Finite(nightSeconds) and nightSeconds >= 0) and nightSeconds or Num(PetBalance.DEFAULT_NIGHT_SECONDS, 0)
	local total = day + night + Num(guard.CycleExtra, 0)
	return math.max(0, math.min(Num(guard.MaxSeconds, math.huge), total))
end

--.. kinds = set {Yield = true, Haste = true} (an array of names works too); Guard/Wild/None add nothing
function PetStats.RateMultiplier(kinds)
	local mult = 1
	if type(kinds) == "table" then
		local abilities = Tab(PetBalance.ABILITIES)
		local seen = {}
		for k, v in pairs(kinds) do
			local kind = nil
			if type(k) == "string" and v then
				kind = k
			elseif type(v) == "string" then
				kind = v
			end
			if kind and not seen[kind] then
				seen[kind] = true
				local row = abilities[kind]
				local m = type(row) == "table" and row.Mult or nil
				if Finite(m) and m > 0 then mult *= m end
			end
		end
	end
	return math.min(Num(PetBalance.RATE_HARD_CAP, math.huge), mult)
end

--..texts: the only place ability numbers become words..--
local function AbilityRow(kind)
	local row = Tab(PetBalance.ABILITIES)[kind]
	return type(row) == "table" and row or nil
end

local function PercentOf(mult)
	return Round((mult - 1) * 100)
end

local function GuardSecondsOr(value)
	if Finite(value) and value >= 0 then return Round(value) end
	return Round(PetStats.GuardSeconds(nil, nil))
end

local function SafeText(fn, ...)
	local ok, text = pcall(fn, ...)
	return ok and type(text) == "string" and text or ""
end

--.. "x1.5" (Yield) / "+25%" (Haste) / "1" (Guard charges) / ""
function PetStats.AbilityBadge(kind)
	return SafeText(function()
		local row = AbilityRow(kind)
		if not row then return "" end
		if kind == "Yield" then return ("x%g"):format(row.Mult) end
		if kind == "Haste" then return ("+%d%%"):format(PercentOf(row.Mult)) end
		if kind == "Guard" then return tostring(row.Charges) end
		return ""
	end)
end

--.. "x1.5 for 90s" / "+25% for 90s" / "blocks one theft for 240s"; Wild / None -> ""
function PetStats.AbilityShort(kind, guardSeconds)
	return SafeText(function()
		local template = Tab(Tab(PetBalance.TEXT).Short)[kind]
		local row = AbilityRow(kind)
		if type(template) ~= "string" or not row then return "" end
		if kind == "Yield" then return template:format(row.Mult, Round(row.Duration)) end
		if kind == "Haste" then return template:format(PercentOf(row.Mult), Round(row.Duration)) end
		if kind == "Guard" then return template:format(GuardSecondsOr(guardSeconds)) end
		return ""
	end)
end

--.. the menu's exact-effect line; Wild names its three kinds with their durations
function PetStats.AbilityEffect(kind, guardSeconds)
	return SafeText(function()
		local templates = Tab(Tab(PetBalance.TEXT).Effect)
		local template = templates[kind]
		local row = AbilityRow(kind)
		if type(template) ~= "string" or not row then return "" end
		if kind == "Yield" then return template:format(row.Mult, Round(row.Duration)) end
		if kind == "Haste" then return template:format(PercentOf(row.Mult), Round(row.Duration)) end
		if kind == "Guard" then return template:format(Round(row.Charges), GuardSecondsOr(guardSeconds)) end
		if kind == "None" then return template:format(PercentOf(Num(PetBalance.FIGHTER_MULT, 1))) end
		if kind == "Wild" then
			local parts = {}
			for _, sub in ipairs(Tab(row.Kinds)) do
				local subRow = AbilityRow(sub)
				if subRow and sub ~= "Wild" then
					parts[#parts + 1] = ("%s (%s)"):format(tostring(subRow.DisplayName or sub), PetStats.AbilityShort(sub, guardSeconds))
				end
			end
			if #parts == 3 then return template:format(parts[1], parts[2], parts[3]) end
			return table.concat(parts, ", ")
		end
		return ""
	end)
end

return PetStats
