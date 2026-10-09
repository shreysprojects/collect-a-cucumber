--[[---------------------------------------DESCRIPTION------------------------------------------
	XP, level curve, coin rewards, mountain unlocks, and owned snowballs /
	launchers. TotalCoinsCollected and TotalDistanceRolled are lifetime totals
	saved with the player. Classic and Wooden Shovel are always granted and
	equipped on join. Server applies these; the HUD reads the replicated attributes.

	Each snowball and launcher is 2 ^ (Order - 1): 1x, 2x, 4x, 8x. The run
	multiplier adds the equipped pair and pays that in full on XP and coins.
	Classic (1x) with Wooden Shovel (1x) is 2x rewards. The 2nd of each is 4x.
	Throw speed uses the square root of that total, so starters launch at about
	1.4x and a 4x loadout at 2x. Momentum runs out sooner than the reward
	multiplier would suggest, and the next shop price takes more than one run.

	XP comes from snow eaten (SNOW_XP per unit), smashed props (SMASH) and the
	distance rolled (DISTANCE_XP per stud), all times the run multiplier. Levels
	go up to MAX_LEVEL; the HUD shows a full "MAX" bar there.

	Rebirth needs a level, not coins: RebirthLevel(rebirths) = REBIRTH_LEVEL_BASE
	+ REBIRTH_LEVEL_STEP per rebirth already done (level 10, 15, 20, ...). It
	resets the climb (level, coins unless REBIRTH_KEEPS_COINS, mountains,
	snowballs, launchers) and keeps the lifetime totals. Each rebirth adds
	REBIRTH_EARNINGS_PER (0.5x) coins and XP - the "boost" the rebirth panel
	shows - and REBIRTH_LAUNCH_PER (0.15x) launch speed on top of the gear.

	Snowballs and launchers share one order ladder, split across the 8 mountain
	difficulties. A step can be bought only while its mountain is unlocked, and
	only after every earlier step of that catalog is owned.
	GEAR_REQUIRES_MOUNTAIN = false drops the mountain gate (the order still holds).
	The gate reads EffectiveUnlocks: the saved unlocks, plus every mountain when
	StudioSettings.UnlockAll is on in Studio (never written to the DataStore).
	That is the same map the server replicates as the UnlockedMountains attribute,
	so the shop offers exactly what the server sells.
	PurchaseInOrder returns true, or false and a reason: "Invalid", "Owned",
	"BuyInOrder", "MountainLocked", "NotEnoughCoins". EQUIP_ON_BUY = true would
	equip a bought item at once; it is off to keep the buy -> EQUIP flow.

--------------------------------------------------------------------------------------------]]--

local Snowballs = require(script.Parent.Snowballs)
local SnowballLaunchers = require(script.Parent.SnowballLaunchers)
local mountainConfig = require(script.Parent.MountainConfig)()
local mountainPlaces = require(script.Parent.MountainPlaces)()

local config = {}

config.MAX_LEVEL = 1000
config.BASE_XP = 100 -- XP to go from level 1 → 2
config.XP_PER_LEVEL = 40 -- extra XP needed per level after that
config.STARTER_MOUNTAIN = "Frostpeak"
config.STARTER_SNOWBALL = "Classic"
config.STARTER_LAUNCHER = "Wooden Shovel"

-- Gear of a mountain's orders needs that mountain unlocked (beat the one before it).
config.GEAR_REQUIRES_MOUNTAIN = true
config.EQUIP_ON_BUY = false -- true: Buy* equips the bought item (the card skips EQUIP)

config.SNOW_XP = 1
config.SNOW_COINS = 1
-- XP per stud the ball rolls down the track (times the run multiplier). A measured Frostpeak
-- ride already pays ~0.5 XP per stud in snow at 1x, so this adds about half again.
config.DISTANCE_XP = 0.25

-- Rebirth N (N already done) needs level BASE + STEP * N: 10, 15, 20, ... (capped at MAX_LEVEL).
config.REBIRTH_LEVEL_BASE = 10
config.REBIRTH_LEVEL_STEP = 5
config.REBIRTH_KEEPS_COINS = false -- true: a rebirth leaves the coin balance alone
-- Permanent boosts per rebirth. Rewards never reset.
config.REBIRTH_EARNINGS_PER = 0.5
config.REBIRTH_LAUNCH_PER = 0.15

-- Combo adds this fraction of the smash reward per extra hit, capped.
config.COMBO_BONUS = 0.08
config.COMBO_BONUS_CAP = 0.8

-- Bigger props (PropRadius above 4) scale rewards slightly.
config.RADIUS_BONUS = 0.03
config.RADIUS_BONUS_CAP = 0.6

config.SMASH = {
	Default = { XP = 10, Coins = 5 },
	Tree = { XP = 8, Coins = 4 },
	Rock = { XP = 10, Coins = 5 },
	Snowman = { XP = 12, Coins = 6 },
	Fence = { XP = 8, Coins = 4 },
	Sign = { XP = 8, Coins = 4 },
	Equipment = { XP = 12, Coins = 6 },
	Vehicle = { XP = 20, Coins = 12 },
	Building = { XP = 28, Coins = 16 },
	Landmark = { XP = 50, Coins = 28 },
	SkiLift = { XP = 22, Coins = 12 },
	Pond = { XP = 14, Coins = 8 },
	WoodPile = { XP = 10, Coins = 5 },
	Scenery = { XP = 8, Coins = 4 },
}

function config.DefaultProfile()
	return {
		Level = 1,
		XP = 0,
		Coins = 0,
		TotalCoinsCollected = 0,
		TotalDistanceRolled = 0,
		UnlockedMountains = {
			[config.STARTER_MOUNTAIN] = true,
		},
		UnlockedSnowballs = {
			[config.STARTER_SNOWBALL] = true,
		},
		UnlockedLaunchers = {
			[config.STARTER_LAUNCHER] = true,
		},
		EquippedSnowball = config.STARTER_SNOWBALL,
		EquippedLauncher = config.STARTER_LAUNCHER,
		Rebirths = 0,
	}
end

local function asNameMap(value, required)
	local map = {}
	if type(value) == "table" then
		if value[1] ~= nil then
			for _, name in value do
				if type(name) == "string" and name ~= "" then
					map[name] = true
				end
			end
		else
			for name, on in value do
				if type(name) == "string" and on then
					map[name] = true
				end
			end
		end
	elseif type(value) == "string" then
		for token in string.gmatch(value, "[^,]+") do
			local name = string.match(token, "^%s*(.-)%s*$")
			if name and name ~= "" then
				map[name] = true
			end
		end
	end
	if type(required) == "string" and required ~= "" then
		map[required] = true
	end
	return map
end

local function nameList(map, required)
	local list = {}
	for name, on in asNameMap(map, required) do
		if on then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

function config.EnsureUnlocks(profile)
	if type(profile) ~= "table" then
		return config.DefaultProfile()
	end
	if type(profile.Coins) ~= "number" then
		profile.Coins = 0
	else
		profile.Coins = math.max(0, math.floor(profile.Coins))
	end
	if type(profile.TotalCoinsCollected) ~= "number" then
		profile.TotalCoinsCollected = 0
	else
		profile.TotalCoinsCollected = math.max(0, math.floor(profile.TotalCoinsCollected))
	end
	if type(profile.TotalDistanceRolled) ~= "number" then
		profile.TotalDistanceRolled = 0
	else
		profile.TotalDistanceRolled = math.max(0, math.floor(profile.TotalDistanceRolled))
	end
	profile.UnlockedMountains = asNameMap(profile.UnlockedMountains, config.STARTER_MOUNTAIN)
	profile.UnlockedSnowballs = asNameMap(profile.UnlockedSnowballs, config.STARTER_SNOWBALL)
	profile.UnlockedLaunchers = asNameMap(profile.UnlockedLaunchers, config.STARTER_LAUNCHER)
	if type(profile.EquippedSnowball) ~= "string" or not profile.UnlockedSnowballs[profile.EquippedSnowball] then
		profile.EquippedSnowball = config.STARTER_SNOWBALL
	end
	if type(profile.EquippedLauncher) ~= "string" or not profile.UnlockedLaunchers[profile.EquippedLauncher] then
		profile.EquippedLauncher = config.STARTER_LAUNCHER
	end
	if type(profile.Rebirths) ~= "number" then
		profile.Rebirths = 0
	else
		profile.Rebirths = math.max(0, math.floor(profile.Rebirths))
	end
	return profile
end

local function rebirthCount(rebirths)
	return math.max(0, math.floor(tonumber(rebirths) or 0))
end

-- Level needed for the next rebirth, given how many are already done.
function config.RebirthLevel(rebirths)
	local level = config.REBIRTH_LEVEL_BASE + config.REBIRTH_LEVEL_STEP * rebirthCount(rebirths)
	return math.clamp(math.floor(level), 1, config.MAX_LEVEL)
end

-- true when the profile's level reaches RebirthLevel; always returns that level too.
function config.CanRebirth(profile)
	local rebirths = type(profile) == "table" and profile.Rebirths or 0
	local need = config.RebirthLevel(rebirths)
	local level = type(profile) == "table" and math.floor(tonumber(profile.Level) or 1) or 1
	return level >= need, need
end

function config.EarningsMultiplier(rebirths)
	return 1 + rebirthCount(rebirths) * config.REBIRTH_EARNINGS_PER
end

function config.LaunchBoost(rebirths)
	return 1 + rebirthCount(rebirths) * config.REBIRTH_LAUNCH_PER
end

-- The level is the gate. Success resets the climb (and the coins unless
-- REBIRTH_KEEPS_COINS), then adds one rebirth.
function config.ApplyRebirth(profile)
	if type(profile) ~= "table" then
		return false
	end
	config.EnsureUnlocks(profile)
	if not config.CanRebirth(profile) then
		return false
	end

	local totalCoins = profile.TotalCoinsCollected
	local totalDistance = profile.TotalDistanceRolled
	local rebirths = profile.Rebirths + 1
	profile.Level = 1
	profile.XP = 0
	if not config.REBIRTH_KEEPS_COINS then
		profile.Coins = 0
	end
	profile.TotalCoinsCollected = totalCoins
	profile.TotalDistanceRolled = totalDistance
	profile.Rebirths = rebirths
	profile.UnlockedMountains = {
		[config.STARTER_MOUNTAIN] = true,
	}
	profile.UnlockedSnowballs = {
		[config.STARTER_SNOWBALL] = true,
	}
	profile.UnlockedLaunchers = {
		[config.STARTER_LAUNCHER] = true,
	}
	profile.EquippedSnowball = config.STARTER_SNOWBALL
	profile.EquippedLauncher = config.STARTER_LAUNCHER
	return true
end

function config.EncodeUnlocks(map)
	return table.concat(nameList(map, config.STARTER_MOUNTAIN), ",")
end

function config.DecodeUnlocks(value)
	return asNameMap(value, config.STARTER_MOUNTAIN)
end

function config.UnlockList(map)
	return nameList(map, config.STARTER_MOUNTAIN)
end

function config.EncodeNames(map, required)
	return table.concat(nameList(map, required), ",")
end

function config.DecodeNames(value, required)
	return asNameMap(value, required)
end

function config.NameList(map, required)
	return nameList(map, required)
end

function config.IsUnlocked(profile, mountainId)
	if mountainId == config.STARTER_MOUNTAIN then
		return true
	end
	local unlocks = profile and profile.UnlockedMountains
	return type(unlocks) == "table" and unlocks[mountainId] == true
end

function config.UnlockMountain(profile, mountainId)
	if type(profile) ~= "table" or type(mountainId) ~= "string" or mountainId == "" then
		return false
	end
	config.EnsureUnlocks(profile)
	if profile.UnlockedMountains[mountainId] then
		return false
	end
	profile.UnlockedMountains[mountainId] = true
	return true
end

-- Saved unlocks plus Studio's UnlockAll. A copy: the profile (and the DataStore) never sees the extras.
function config.EffectiveUnlocks(profile)
	local unlocks = asNameMap(profile and profile.UnlockedMountains, config.STARTER_MOUNTAIN)
	if mountainPlaces.StudioUnlockAll() then
		for _, mountainId in mountainConfig.MountainOrder do
			unlocks[mountainId] = true
		end
	end
	return unlocks
end

-- The locked mountain that gates gear of this order, or nil when it can be sold with these unlocks.
function config.GearLockedBy(unlocks, order)
	if not config.GEAR_REQUIRES_MOUNTAIN then
		return nil
	end
	local mountainId = mountainConfig:MountainIdForOrder(order)
	if not mountainId or mountainId == config.STARTER_MOUNTAIN then
		return nil
	end
	if type(unlocks) == "table" and unlocks[mountainId] == true then
		return nil
	end
	return mountainId
end

function config.OwnsSnowball(profile, name)
	if name == config.STARTER_SNOWBALL then
		return true
	end
	local unlocks = profile and profile.UnlockedSnowballs
	return type(unlocks) == "table" and unlocks[name] == true
end

function config.OwnsLauncher(profile, name)
	if name == config.STARTER_LAUNCHER then
		return true
	end
	local unlocks = profile and profile.UnlockedLaunchers
	return type(unlocks) == "table" and unlocks[name] == true
end

-- true, or false and a reason (see the header).
function config.PurchaseInOrder(profile, field, entries, name)
	if type(profile) ~= "table" or type(field) ~= "string" or type(name) ~= "string" or name == "" then
		return false, "Invalid"
	end
	config.EnsureUnlocks(profile)
	local owned = profile[field]
	if type(owned) ~= "table" then
		return false, "Invalid"
	end
	if owned[name] == true then
		return false, "Owned"
	end

	local target = nil
	for _, entry in entries do
		if owned[entry.Name] ~= true then
			if entry.Name == name then
				target = entry
			end
			break
		end
	end
	if not target then
		return false, "BuyInOrder"
	end

	if config.GearLockedBy(config.EffectiveUnlocks(profile), target.Order) then
		return false, "MountainLocked"
	end

	local price = math.max(0, math.floor(tonumber(target.Price) or 0))
	local coins = math.max(0, math.floor(tonumber(profile.Coins) or 0))
	if coins < price then
		return false, "NotEnoughCoins"
	end
	profile.Coins = coins - price
	owned[name] = true
	return true
end

function config.SetEquippedSnowball(profile, name)
	if type(profile) ~= "table" or type(name) ~= "string" or name == "" then
		return false
	end
	config.EnsureUnlocks(profile)
	if not profile.UnlockedSnowballs[name] then
		return false
	end
	profile.EquippedSnowball = name
	return true
end

function config.SetEquippedLauncher(profile, name)
	if type(profile) ~= "table" or type(name) ~= "string" or name == "" then
		return false
	end
	config.EnsureUnlocks(profile)
	if not profile.UnlockedLaunchers[name] then
		return false
	end
	profile.EquippedLauncher = name
	return true
end

local function equippedMultiplier(catalog, name)
	local item = catalog:GetByName(name) or catalog:GetByOrder(1)
	local multiplier = item and item.Multiplier or 1
	if multiplier < 1 then
		return 1
	end
	return multiplier
end

function config.EquipmentMultiplier(snowballName, launcherName)
	return equippedMultiplier(Snowballs, snowballName) + equippedMultiplier(SnowballLaunchers, launcherName)
end

-- Reward multiplier stays the shop total. Throw speed and the coast cap use
-- the square root, so a 2x loadout is not a 2x cannon.
function config.LaunchPower(gear)
	local value = tonumber(gear) or 1
	if value < 1 then
		value = 1
	end
	return math.sqrt(value)
end

function config.XpToNext(level)
	level = math.max(1, math.floor(tonumber(level) or 1))
	return config.BASE_XP + config.XP_PER_LEVEL * (level - 1)
end

function config.IsMaxLevel(level)
	return math.floor(tonumber(level) or 1) >= config.MAX_LEVEL
end

function config.ApplyXp(profile, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return 0
	end
	if profile.Level >= config.MAX_LEVEL then
		profile.XP = 0
		return 0
	end

	profile.XP += amount
	local levels = 0
	while profile.Level < config.MAX_LEVEL do
		local need = config.XpToNext(profile.Level)
		if profile.XP < need then
			break
		end
		profile.XP -= need
		profile.Level += 1
		levels += 1
	end
	if profile.Level >= config.MAX_LEVEL then
		profile.XP = 0
	end
	return levels
end

function config.RewardsForSnow(amount)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if amount <= 0 then
		return 0, 0
	end
	return amount * config.SNOW_XP, amount * config.SNOW_COINS
end

-- XP for studs rolled (a fraction; the caller carries the remainder between calls).
function config.RewardsForDistance(studs)
	studs = math.max(0, tonumber(studs) or 0)
	return studs * config.DISTANCE_XP
end

function config.RewardsForSmash(category, radius, combo)
	local row = config.SMASH[category] or config.SMASH.Default
	local extraRadius = math.clamp((tonumber(radius) or 4) - 4, 0, 20)
	local sizeMult = 1 + math.min(extraRadius * config.RADIUS_BONUS, config.RADIUS_BONUS_CAP)
	local extraHits = math.max((tonumber(combo) or 1) - 1, 0)
	local comboMult = 1 + math.min(extraHits * config.COMBO_BONUS, config.COMBO_BONUS_CAP)
	local xp = math.max(1, math.floor(row.XP * sizeMult * comboMult + 0.5))
	local coins = math.max(1, math.floor(row.Coins * sizeMult * comboMult + 0.5))
	return xp, coins
end

return function()
	return config
end
