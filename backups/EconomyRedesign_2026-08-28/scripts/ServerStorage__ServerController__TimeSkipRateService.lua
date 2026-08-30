-- One authoritative, deterministic pickaxe + pet production rate for every Time Skip.
-- Quotes change only with equipment, highest unlocked zone, or active multipliers.
local ServerStorage = game:GetService("ServerStorage")

local ServerController = require(ServerStorage.ServerController)
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local ProfileService = ServerController.GetModule("ProfileService")
local Doors = ServerController.GetDictionary("Doors").Stats
local Pickaxes = ServerController.GetDictionary("Pickaxes").Stats

local TimeSkipRateService = {}

-- These intervals mirror BreakablesService's authoritative server gates.
-- Combo growth remains omitted so store, collectible, and offline quotes stay deterministic.
local PET_TICK = 0.6
local PICKAXE_TICK = 0.25 -- mirrors BreakablesService.MANUAL_HIT_DEBOUNCE (0.35 -> 0.25, 2026-08-23)
local CRIT_CHANCE = 0.10
local CRIT_MULTIPLIER = 5

local ZONE_ORDER = {"Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek"}
local ZONE_HP = {
	Spawn = 1;
	Desert = 3;
	Samurai = 8;
	Farm = 20;
	Snow = 45;
	Underwater = 110;
	Volcano = 240;
	Narmek = 500;
}

-- Mirrors BreakablesService's stable, non-event spawn economy. Sliced cucumbers
-- own 15 baseline slots; the other 24 slots roll from the weighted regular pool.
-- Player-count additions are omitted so another player joining cannot change prices.
local SLICED_SLOTS = 15
local OTHER_SLOTS = 24
local SLICED_TYPE = {HP = 8; Reward = 3}
local BASE_OTHER_TYPES = {
	{Weight = 35; HP = 30; Reward = 8};   -- Cucumber
	{Weight = 22; HP = 120; Reward = 45}; -- Giant Cucumber
	{Weight = 10; HP = 90; Reward = 60};  -- Golden Cucumber
	{Weight = 8; HP = 350; Reward = 140}; -- Cucumber Tree
}
local ZONE_OTHER_TYPES = {
	--.. Empty since 2026-08-21: all eight zones are exclusive now, so every biome is
	--.. quoted from ZONE_EXCLUSIVE_MIX below. Kept because BuildZoneMixture still falls
	--.. back to BASE_OTHER_TYPES + this table for a zone with no exclusive entry.
}

-- Mirrors BreakablesService's ZONE_EXCLUSIVE_TYPES: a zone converted to hand-modelled
-- mesh produce spawns ONLY its own list, so neither BASE_OTHER_TYPES nor the
-- ZONE_OTHER_TYPES extras apply to it. Sliced is broken out because it draws from the
-- fixed sliced quota instead of a weighted regular slot. Keep in sync with that table
-- or offline/Robux Time Skip quotes drift away from what the zone actually drops.
-- NOTE: Spawn is intentionally absent -- it was converted to meshes too, but it has
-- always been quoted off the legacy shared pool here and correcting it would move live
-- Spawn Time Skip pricing, which is a separate call to make.
local ZONE_EXCLUSIVE_MIX = {
	Desert = {
		Sliced = {HP = 10; Reward = 4};        -- Sun-Dried Slice
		Other = {
			{Weight = 34; HP = 35; Reward = 10};   -- Prickly Cucumber
			{Weight = 18; HP = 70; Reward = 25};   -- Sliced Cucumber
			{Weight = 14; HP = 130; Reward = 50};  -- Sun-Baked Cucumber
			{Weight = 10; HP = 190; Reward = 85};  -- Wrapped Cucumber
			{Weight = 8; HP = 260; Reward = 110};  -- Cactus Cucumber
			{Weight = 6; HP = 320; Reward = 135};  -- Desert Palm
			{Weight = 5; HP = 400; Reward = 165};  -- Sandstone Tree
		};
	};
	Samurai = {
		Sliced = {HP = 10; Reward = 4};        -- Sliced Cucumber (borrowed from Spawn)
		Other = {
			{Weight = 34; HP = 38; Reward = 11};   -- Katana Cucumber
			{Weight = 20; HP = 80; Reward = 28};   -- Bamboo Cucumber
			{Weight = 13; HP = 150; Reward = 58};  -- Lantern Cucumber
			{Weight = 9; HP = 230; Reward = 98};   -- Bamboo Grove
			{Weight = 6; HP = 330; Reward = 140};  -- Torii Gate
			{Weight = 5; HP = 420; Reward = 175};  -- Sakura Tree
		};
	};
	Farm = {
		Sliced = {HP = 10; Reward = 4};        -- Cucumber Basket
		Other = {
			{Weight = 34; HP = 42; Reward = 12};   -- Muddy Cucumber
			{Weight = 22; HP = 95; Reward = 34};   -- Crate Cucumber
			{Weight = 12; HP = 190; Reward = 76};  -- Windmill Plant
			{Weight = 7; HP = 310; Reward = 130};  -- Hay Bale
			{Weight = 5; HP = 440; Reward = 185};  -- Cucumber Tree
		};
	};
	Snow = {
		Sliced = {HP = 10; Reward = 4};        -- Frozen Slice
		Other = {
			{Weight = 32; HP = 45; Reward = 13};   -- Snowcap Cucumber
			{Weight = 20; HP = 85; Reward = 30};   -- Snowball Slice
			{Weight = 13; HP = 160; Reward = 64};  -- Crystal Cucumber
			{Weight = 9; HP = 250; Reward = 105};  -- Frozen Cucumber
			{Weight = 6; HP = 330; Reward = 138};  -- Snow Tree
			{Weight = 5; HP = 400; Reward = 168};  -- Icicle Tree
			{Weight = 4; HP = 460; Reward = 195};  -- Frozen Tree
		};
	};
	Underwater = {
		Sliced = {HP = 10; Reward = 4};        -- Bubble Slice
		Other = {
			{Weight = 32; HP = 48; Reward = 14};   -- Seaweed Cucumber
			{Weight = 20; HP = 90; Reward = 32};   -- Shell Slice
			{Weight = 13; HP = 170; Reward = 68};  -- Coral Cucumber
			{Weight = 9; HP = 265; Reward = 110};  -- Pearl Cucumber
			{Weight = 6; HP = 345; Reward = 145};  -- Kelp Tree
			{Weight = 5; HP = 415; Reward = 175};  -- Bubble Tree
			{Weight = 4; HP = 480; Reward = 205};  -- Coral Tree
		};
	};
	Volcano = {
		Sliced = {HP = 10; Reward = 4};        -- Molten Slice
		Other = {
			{Weight = 34; HP = 50; Reward = 15};   -- Charred Cucumber
			{Weight = 22; HP = 105; Reward = 38};  -- Molten Cucumber
			{Weight = 14; HP = 195; Reward = 78};  -- Flame Cucumber
			{Weight = 9; HP = 310; Reward = 130};  -- Obsidian Tree
			{Weight = 6; HP = 400; Reward = 168};  -- Volcano Cucumber
			{Weight = 5; HP = 500; Reward = 210};  -- Magma Tree
		};
	};
	Narmek = {
		Sliced = {HP = 10; Reward = 4};        -- Moon Slice
		Other = {
			{Weight = 32; HP = 52; Reward = 16};   -- Meteor Cucumber
			{Weight = 20; HP = 100; Reward = 36};  -- Planet Slice
			{Weight = 13; HP = 185; Reward = 75};  -- Astronaut Cucumber
			{Weight = 9; HP = 290; Reward = 120};  -- Neon Alien Cucumber
			{Weight = 6; HP = 380; Reward = 158};  -- Moon Tree
			{Weight = 5; HP = 450; Reward = 188};  -- Alien Tree
			{Weight = 4; HP = 520; Reward = 220};  -- Galaxy Tree
		};
	};
}

local Initialized = false

local function HighestUnlockedZone(Player)
	local profile = Player and ProfileService.GetUserData(Player)
	local owned = {Spawn = true}
	if profile then
		for _, zoneName in ipairs(string.split(profile.DoorData or "Spawn", " # ")) do
			owned[zoneName] = true
		end
	end
	for index = #ZONE_ORDER, 1, -1 do
		local zoneName = ZONE_ORDER[index]
		if owned[zoneName] then
			return zoneName
		end
	end
	return "Spawn"
end

function TimeSkipRateService.HighestUnlockedZone(Player)
	return HighestUnlockedZone(Player)
end

local function ExpectedAppliedPerStrike(damage, hp)
	damage = math.max(0, tonumber(damage) or 0)
	local normalApplied = math.min(damage, hp)
	local critApplied = math.min(damage * CRIT_MULTIPLIER, hp)
	return normalApplied * (1 - CRIT_CHANCE) + critApplied * CRIT_CHANCE
end

local function BuildZoneMixture(zoneName)
	local zoneWall = ZONE_HP[zoneName] or 1
	local economy = Doors[zoneName] and Doors[zoneName].Orbs or {Orb = 1; Multi = 1}
	local zoneValue = (economy.Orb or 1) * (economy.Multi or 1)
	local totalSlots = SLICED_SLOTS + OTHER_SLOTS

	--.. an exclusive zone replaces BOTH the shared pool and its ZONE_OTHER_TYPES extras
	local exclusive = ZONE_EXCLUSIVE_MIX[zoneName]
	local slicedType = exclusive and exclusive.Sliced or SLICED_TYPE
	local mixture = {{
		Share = SLICED_SLOTS / totalSlots;
		HP = slicedType.HP * zoneWall;
		Reward = slicedType.Reward * zoneValue;
	}}

	local baseTypes = exclusive and exclusive.Other or BASE_OTHER_TYPES
	local zoneTypes = (not exclusive) and (ZONE_OTHER_TYPES[zoneName] or {}) or {}
	local totalWeight = 0
	for _, definition in ipairs(baseTypes) do totalWeight += definition.Weight end
	for _, definition in ipairs(zoneTypes) do totalWeight += definition.Weight end

	local function AddOther(definition)
		table.insert(mixture, {
			Share = (OTHER_SLOTS / totalSlots) * (definition.Weight / totalWeight);
			HP = definition.HP * zoneWall;
			Reward = definition.Reward * zoneValue;
		})
	end
	for _, definition in ipairs(baseTypes) do AddOther(definition) end
	for _, definition in ipairs(zoneTypes) do AddOther(definition) end
	return mixture
end

local function RateForMixture(mixture, damage, interval)
	if damage <= 0 then return 0 end
	local rate = 0
	for _, target in ipairs(mixture) do
		rate += target.Share
			* (ExpectedAppliedPerStrike(damage, target.HP) / target.HP)
			* target.Reward
			/ interval
	end
	return math.max(0, rate)
end

-- Base pickaxe damage is shared with the live pickaxe's tier curve. Friend boosts and
-- weak-point combo growth are intentionally omitted: both depend on live server
-- circumstances and would make saved/offline or Robux quotes unstable.
function TimeSkipRateService.GetPickaxeDamage(Player)
	-- Combat, Time Skips, and the pickaxe store all read the same dictionary stat.
	local damage = 4
	pcall(function()
		local equipped = Player.PlayerData.Pickaxes.Equipped.Value
		local definition = Pickaxes[equipped]
		damage = definition and definition.Stats and definition.Stats.Damage or damage
	end)
	return math.max(1, math.floor(tonumber(damage) or 4))
end

function TimeSkipRateService.GetPetStrike(Player)
	local equipped = 0
	local petDamage = 0
	pcall(function()
		equipped = Player.PlayerData.Pets.Equipped.Value
		petDamage = math.floor(Player.PlayerData.Pets.Damage.Value)
	end)
	if equipped <= 0 then
		return 0
	end
	return math.max(1, 2 + petDamage)
end

-- Returns the safe 1x production estimate across the zone's real baseline
-- cucumber mixture; zone position and live farming history are never sampled.
function TimeSkipRateService.GetTheoreticalBreakdown(Player)
	local zoneName = HighestUnlockedZone(Player)
	local mixture = BuildZoneMixture(zoneName)
	local pickaxeDamage = TimeSkipRateService.GetPickaxeDamage(Player)
	local petDamage = TimeSkipRateService.GetPetStrike(Player)
	local pickaxeRate = RateForMixture(mixture, pickaxeDamage, PICKAXE_TICK)
	local petRate = RateForMixture(mixture, petDamage, PET_TICK)

	local averageHP = 0
	local averageReward = 0
	for _, target in ipairs(mixture) do
		averageHP += target.Share * target.HP
		averageReward += target.Share * target.Reward
	end

	return {
		Zone = zoneName;
		HP = averageHP; -- compatibility: now the weighted target average
		Reward = averageReward;
		MixtureSize = #mixture;
		PickaxeDamage = pickaxeDamage;
		PetDamage = petDamage;
		PickaxeRate = pickaxeRate;
		PetRate = petRate;
		BaseRate = math.max(0, pickaxeRate + petRate);
	}
end

function TimeSkipRateService.TheoreticalBaseRate(Player)
	return TimeSkipRateService.GetTheoreticalBreakdown(Player).BaseRate
end

-- Deterministic by design: ordinary farming history never changes a quote.
-- The value moves only when pickaxe, pets, highest unlocked zone, or multipliers move.
function TimeSkipRateService.GetBaseRate(Player)
	return TimeSkipRateService.TheoreticalBaseRate(Player)
end

function TimeSkipRateService.GetRate(Player)
	local baseRate = TimeSkipRateService.GetBaseRate(Player)
	if baseRate <= 0 then
		return 0
	end
	return CurrencyHandler.GetMulipliers({
		Player = Player;
		Currency = "Cucumbers";
		Amount = baseRate;
	})
end

-- Pet-only production rate WITH cucumber multipliers applied. This is what offline
-- earnings checkpoint (2026-08-22): the vault popup says "your pets kept collecting",
-- and the old full rate silently included the PICKAXE clicking rate -- nobody is
-- clicking while offline. Returns 0 with no pets equipped (thematically honest, and
-- the tutorial hands out Lil Pickle within minutes).
function TimeSkipRateService.GetPetRate(Player)
	local info = TimeSkipRateService.GetTheoreticalBreakdown(Player)
	if not info or (info.PetRate or 0) <= 0 then return 0 end
	return CurrencyHandler.GetMulipliers({
		Player = Player;
		Currency = "Cucumbers";
		Amount = info.PetRate;
	})
end

function TimeSkipRateService.Quote(Player, seconds)
	seconds = math.max(0, tonumber(seconds) or 0)
	local final = TimeSkipRateService.GetRate(Player) * seconds
	return math.max(1, math.floor(final))
end

-- Offline earnings must use the trusted rate saved at the previous checkpoint,
-- but their time conversion still belongs to this central calculator.
function TimeSkipRateService.QuoteStoredRate(rate, seconds, efficiency)
	rate = math.max(0, tonumber(rate) or 0)
	seconds = math.max(0, tonumber(seconds) or 0)
	efficiency = math.clamp(tonumber(efficiency) or 1, 0, 1)
	return math.max(0, math.floor(rate * seconds * efficiency))
end

-- The only grant path for a live Time Skip. Quote already includes cucumber
-- multipliers, so the flat award must not apply them a second time.
function TimeSkipRateService.Grant(Player, seconds)
	local amount = TimeSkipRateService.Quote(Player, seconds)
	CurrencyHandler.AddCurrency({
		Player = Player;
		Currency = "Cucumbers";
		HasTotal = true;
		Amount = amount;
		WasPurchase = true;
	})
	return amount
end

function TimeSkipRateService.Initialize()
	if Initialized then return end
	Initialized = true
	print("[TimeSkipRateService] deterministic pickaxe + pet quotes ready")
end

return TimeSkipRateService
