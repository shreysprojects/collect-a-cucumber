--[[
	PetBalance  (ModuleScript, ReplicatedStorage.Modules)
	Every number of the pet system in one place (2026-09-22, pet-system polish). Pure data: the
	server (PetService, IncomeService, PetBuffService, PetCombatService, PetEffectsBus) and the
	clients (Pets menu, reveal card, pet cards, effects) all read these tables; PetStats turns them
	into per-pet stats and ability texts. Balance passes change THIS file first.

	  * income  = BASE_INCOME * TIER_STEP^(eggTier - 1) * RARITY.Income * (1 + RANK_STEP * (rank - 1)) * affix
	  * damage  = RARITY.Damage * (1 + BIOME_DAMAGE_STEP * (eggTier - 1)) * affix * (FIGHTER_MULT for "None")
	  * affixes = MATERIALS / MUTATIONS (pet multipliers only -- CucumberMutations stays the cucumber maths)
	  * SPECIES_ABILITY = internal PetsCatalog key -> "Yield" | "Haste" | "Guard" | "Wild" | "None"
	  * ABILITIES hold the ability numbers; TEXT holds only templates (PetStats.AbilityShort /
	    AbilityEffect / AbilityBadge fill them, so a number never lives in a string)

	Validate(catalog) -> {problem strings}   empty when PetsCatalog and these tables agree; never
	errors (PetServer warns the first few at bootstrap -- an unknown new key warns, never crashes).
	Never: requires anything, touches Instances (Color3 values are fine).
]]
local PetBalance = {}

PetBalance.SLOTS = 6
PetBalance.MAX_OWNED = 1000           -- safety cap on new grants (profile size); OD-28, user to confirm
PetBalance.BASE_INCOME = 0.5          -- Basic tier cash/s before rarity/rank/traits
PetBalance.TIER_STEP = 8              -- x8 per egg tier
PetBalance.RANK_STEP = 0.10           -- +10 % per rank above 1
PetBalance.MAX_RANK = 6
PetBalance.RANK_OVERRIDES = {Gregory = 6} -- rankless secret pet
PetBalance.BIOME_DAMAGE_STEP = 0.05   -- +5 % shot damage per egg tier above 1
PetBalance.FIGHTER_MULT = 1.15        -- species with Ability "None"
PetBalance.INCOME_AFFIX_CAP = 8
PetBalance.DAMAGE_AFFIX_CAP = 0.25    -- AffixDamage <= 1.25
PetBalance.RATE_HARD_CAP = 2.0        -- cucumber temporary multiplier cap (Yield x Haste = 1.875)
PetBalance.FALLBACK_RARITY = "Common"

PetBalance.RARITY = {
	Common    = {Income = 1.0,  Damage = 3,  Interval = 2.50, Range = 26, Chance = 0.01},
	Uncommon  = {Income = 1.5,  Damage = 5,  Interval = 2.25, Range = 29, Chance = 0.02},
	Rare      = {Income = 2.5,  Damage = 8,  Interval = 2.00, Range = 32, Chance = 0.04},
	Legendary = {Income = 5.0,  Damage = 12, Interval = 1.75, Range = 35, Chance = 0.08},
	Mythical  = {Income = 10.0, Damage = 18, Interval = 1.50, Range = 38, Chance = 0.12},
}

PetBalance.EGG_TIERS = {["Basic Egg"] = 1, ["Desert Egg"] = 2, ["Samurai Egg"] = 3, ["Farm Egg"] = 4,
	["Frozen Egg"] = 5, ["Ocean Egg"] = 6, ["Lava Egg"] = 7, ["Narmek Egg"] = 8}
PetBalance.EGG_ZONES = {["Basic Egg"] = "Spawn", ["Desert Egg"] = "Desert", ["Samurai Egg"] = "Samurai",
	["Farm Egg"] = "Farm", ["Frozen Egg"] = "Snow", ["Ocean Egg"] = "Underwater", ["Lava Egg"] = "Volcano",
	["Narmek Egg"] = "Narmek"}

PetBalance.MATERIALS = {
	Golden  = {Income = 1.5, Combat = 0.05},
	Diamond = {Income = 2.0, Combat = 0.10},
}
PetBalance.MUTATIONS = {
	NEON = {Income = 0.15, Combat = 0.02}, SHADOW = {Income = 0.20, Combat = 0.03},
	FROZEN = {Income = 0.25, Combat = 0.03}, RADIOACTIVE = {Income = 0.30, Combat = 0.04},
	MOLTEN = {Income = 0.30, Combat = 0.04}, ROYAL = {Income = 0.50, Combat = 0.05},
	VOID = {Income = 1.00, Combat = 0.08}, PRISMATIC = {Income = 2.00, Combat = 0.12},
}

PetBalance.ABILITIES = { -- numbers live ONLY here; every text is built by the PetStats text helpers (3.2)
	Yield = {DisplayName = "Lucky Harvest", Mult = 1.5, Duration = 90, Color = Color3.fromRGB(255, 205, 40)},
	Haste = {DisplayName = "Quick Grow", Mult = 1.25, Duration = 90, Color = Color3.fromRGB(60, 220, 255)},
	Guard = {DisplayName = "Leaf Shield", Charges = 1, Color = Color3.fromRGB(90, 230, 110)},
	Wild  = {DisplayName = "Wild Card", Kinds = {"Yield", "Haste", "Guard"}, Color = Color3.fromRGB(255, 120, 230)},
	None  = {DisplayName = "Fighter", Color = Color3.fromRGB(255, 90, 70)},
}
PetBalance.GUARD = {CycleExtra = 15, MaxSeconds = 600, GraceSeconds = 1.5, StunSeconds = 0.8, AvoidSeconds = 4}
PetBalance.DEFAULT_DAY_SECONDS = 180
PetBalance.DEFAULT_NIGHT_SECONDS = 10 -- DayNightCycle's own fallback (the live attribute is 45)

PetBalance.TIMING = {
	ABILITY_PERIOD = 60, ABILITY_TICK = 0.25,
	INCOME_TICK = 1, INCOME_MAX_CATCHUP = 5,
	COMBAT_SCAN = 0.2, ROAM_PLAN = 0.2, BUFF_SWEEP = 0.25,
	FX_FLUSH = 0.1, TOTALS_PUSH = 1,
	REVEAL_FALLBACK = 100, -- > EggHatchClient WATCHDOG (95)
	ROAM_LEAD = 0.3,       -- roam segments start this far in the future (replication lead, 3.5)
	UNAVAILABLE_RETRY = 30, -- respawn attempt for Unavailable roster pets (OD-13)
}
PetBalance.PET = {FIT = 5, EDGE_INSET = 2, SPEED_MIN = 5, SPEED_MAX = 8, IDLE_MIN = 1.5, IDLE_MAX = 4.5, LEG_MIN = 8, LEG_MAX = 26}
PetBalance.REQUESTS = {STATE_PER_SECOND = 1, STATE_BURST = 2, ROSTER_PER_SECOND = 2, ROSTER_BURST = 4,
	MAX_ID_LENGTH = 64, MAX_REQUEST_ID_LENGTH = 40}
PetBalance.FX = {MAX_PROJECTILES = 64, MAX_POPUPS = 32, RADIUS = 180, MAX_EVENTS_PER_BATCH = 48,
	SHOT_TRAVEL_MIN = 0.12, SHOT_TRAVEL_MAX = 0.2, ARC_TIME = 0.32, MUZZLE_HEIGHT = 1.5}

PetBalance.TEXT = {
	MigrationNotice = "You can now choose six active pets. Your other pets are safe in Pets.",
	ProcToast = "%s gave %s to your cucumber - %s", -- (pet display name, ability display name, PetStats.AbilityShort)
	-- templates only; numbers are filled from ABILITIES / GuardSeconds by PetStats.AbilityShort/Effect
	Short = {Yield = "x%g for %ds", Haste = "+%d%% for %ds", Guard = "blocks one theft for %ds"},
	Effect = {Yield = "One cucumber earns x%g cash/sec for %ds", Haste = "One cucumber produces %d%% faster for %ds",
		Guard = "Blocks %d zombie theft on one cucumber for up to %ds", Wild = "%s, %s or %s",
		None = "Fighter: +%d%% damage"}, -- None filled from FIGHTER_MULT
	ShieldToast = "Leaf Shield blocked a thief!",
	ReserveNotice = "Your new pet is in reserve - open Pets to equip it.",
	LockedHatchNotice = "Your new pet joins your team when the fight is over.",
	InventoryFull = "Your pet inventory is full.",
	LockBanner = "Finish defending your plot to change pets.",
	Unavailable = "Temporarily unavailable",
	NextRoll = "Next chance roll in %s",
}

-- internal key -> ability (PLAN section 5; all 49)
PetBalance.SPECIES_ABILITY = {
	-- Basic
	Cat = "Yield", Dog = "Guard", Bunny = "None", Wolf = "Haste", Tabby = "None", Fox = "Yield", Gregory = "Wild",
	-- Desert
	Barrel = "None", ["Treasure Gem"] = "Yield", Cannon = "None", Chest = "Guard", ["Desert Overlord"] = "None", Cactus = "Haste",
	-- Samurai
	["Dog Ninja"] = "None", ["Good Ninja"] = "Guard", ["Evil Ninja"] = "None", ["Good Samurai"] = "Yield",
	["Evil Samurai"] = "None", Sensei = "Haste",
	-- Farm
	Hay = "None", Bird = "Haste", Panda = "None", Cow = "Guard", Pig = "None", Farmer = "Yield",
	-- Frozen
	["Red Snowman"] = "None", ["Blue Snowman"] = "Haste", ["Frozen Dragon"] = "None", ["Frozen Hydra"] = "Guard",
	["Frozen Ice Shock"] = "None", ["Frozen Gem"] = "Yield",
	-- Ocean
	["Oceanic Dog"] = "None", ["Oceanic Kitty"] = "Guard", ["Oceanic Bunny"] = "None", ["Oceanic Bear"] = "Yield",
	["Ocean Dragon"] = "None", ["Atlantic Hydra"] = "Haste",
	-- Lava
	["Lava Plume"] = "None", ["Lava Golem"] = "Haste", ["Lava Veltal"] = "None", ["Lava Trio"] = "Yield",
	["Lava Dragon"] = "None", ["Demon Dog"] = "Guard",
	-- Narmek
	["Moon Bunny"] = "None", ["Satellite Pup"] = "Guard", ["Alien Slime"] = "None", ["Meteor Moth"] = "Haste",
	["Nebula Fox"] = "None", ["Cosmo Cat"] = "Yield",
}

--..Validate (2026-09-22)..--
--.. the ability names a SPECIES_ABILITY row may use
local ABILITY_KINDS = {Yield = true, Haste = true, Guard = true, Wild = true, None = true}
local MAX_PROBLEMS = 100

--.. table keys in a stable order (pairs order is not), so the problem list reads the same every run
local function SortedKeys(t)
	local keys = {}
	if type(t) ~= "table" then return keys end
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

local function IsWholeRank(x, maxRank)
	return type(x) == "number" and x == x and x % 1 == 0 and x >= 1 and x <= maxRank
end

--.. catalog = ReplicatedStorage.Modules.PetsCatalog (or a fake with PETS / EGGS). Checks, in order:
--..   every PETS key has a SPECIES_ABILITY row naming a known ability; every row names a PETS key;
--..   every EGGS key has EGG_TIERS + EGG_ZONES; every rarity PETS uses has a RARITY row;
--..   every pool rank (after RANK_OVERRIDES) is a whole number in 1..MAX_RANK;
--..   plus: every pool pet is a PETS key, every PETS key hatches from exactly one egg.
function PetBalance.Validate(catalog)
	local problems = {}
	local function Add(text)
		if #problems < MAX_PROBLEMS then problems[#problems + 1] = text end
	end
	local ok, err = pcall(function()
		if type(catalog) ~= "table" then
			Add("catalog is not a table")
			return
		end
		local pets = catalog.PETS
		local eggs = catalog.EGGS
		if type(pets) ~= "table" then Add("catalog.PETS is not a table") pets = {} end
		if type(eggs) ~= "table" then Add("catalog.EGGS is not a table") eggs = {} end
		local abilities = type(PetBalance.SPECIES_ABILITY) == "table" and PetBalance.SPECIES_ABILITY or {}
		local rarities = type(PetBalance.RARITY) == "table" and PetBalance.RARITY or {}
		local overrides = type(PetBalance.RANK_OVERRIDES) == "table" and PetBalance.RANK_OVERRIDES or {}
		local maxRank = tonumber(PetBalance.MAX_RANK) or 6

		for _, key in ipairs(SortedKeys(pets)) do
			local ability = abilities[key]
			if ability == nil then
				Add(("pet %q has no SPECIES_ABILITY row"):format(tostring(key)))
			elseif not ABILITY_KINDS[ability] then
				Add(("pet %q has unknown ability %q"):format(tostring(key), tostring(ability)))
			end
			local info = pets[key]
			local rarity = type(info) == "table" and info.Rarity or nil
			if type(rarity) ~= "string" then
				Add(("pet %q has no Rarity"):format(tostring(key)))
			elseif type(rarities[rarity]) ~= "table" then
				Add(("rarity %q (pet %q) has no RARITY row"):format(rarity, tostring(key)))
			end
		end
		for _, key in ipairs(SortedKeys(abilities)) do
			if pets[key] == nil then
				Add(("SPECIES_ABILITY row %q is not a catalog pet"):format(tostring(key)))
			end
		end

		local eggCount = {} -- [petKey] = number of egg pools it is in
		for _, eggKey in ipairs(SortedKeys(eggs)) do
			if type(PetBalance.EGG_TIERS[eggKey]) ~= "number" then
				Add(("egg %q has no EGG_TIERS entry"):format(tostring(eggKey)))
			end
			if type(PetBalance.EGG_ZONES[eggKey]) ~= "string" then
				Add(("egg %q has no EGG_ZONES entry"):format(tostring(eggKey)))
			end
			local egg = eggs[eggKey]
			local pool = type(egg) == "table" and egg.Pets or nil
			if type(pool) ~= "table" then
				Add(("egg %q has no Pets pool"):format(tostring(eggKey)))
			else
				for _, petKey in ipairs(SortedKeys(pool)) do
					eggCount[petKey] = (eggCount[petKey] or 0) + 1
					if pets[petKey] == nil then
						Add(("pool pet %q (%s) is not a catalog pet"):format(tostring(petKey), tostring(eggKey)))
					end
					local entry = pool[petKey]
					local rank = overrides[petKey]
					if rank == nil and type(entry) == "table" then rank = entry.Rank end
					if rank == nil then
						Add(("pool pet %q (%s) has no rank and no RANK_OVERRIDES entry"):format(tostring(petKey), tostring(eggKey)))
					elseif not IsWholeRank(rank, maxRank) then
						Add(("pool pet %q (%s) rank %s is not a whole number in 1..%d"):format(tostring(petKey), tostring(eggKey), tostring(rank), maxRank))
					end
				end
			end
		end
		for _, key in ipairs(SortedKeys(pets)) do
			local n = eggCount[key] or 0
			if n == 0 then
				Add(("pet %q is in no egg pool"):format(tostring(key)))
			elseif n > 1 then
				Add(("pet %q is in %d egg pools"):format(tostring(key), n))
			end
		end
	end)
	if not ok then Add("Validate failed: " .. tostring(err)) end
	return problems
end

return PetBalance
