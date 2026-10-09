--[[
	DenConfig  (ModuleScript, ReplicatedStorage.Modules)  2026-09-24
	The numbers and the pure rules behind the ZOMBIE DEN (StarterGui.CucumberMenus.DenPanel, opened by walking up
	to Map.Lobby.Stations."Zombie Den "), shared by ServerScriptService.ZombieDenService (the authority) and the
	client DenController (display only). User: "lost a cucumber? get it back by getting 3 of X cucumber and trading
	it in, user has 12 hours before the offer expires; X is displayed in a viewport; X has to be near attainable or
	attainable, e.g. 1 biome ahead and lower".

	  DEALS   every cucumber the zombies steal (Data.LostCucumbers, written by ItemService.RecordLoss at every
	          escape - night raids and day thieves alike) becomes a deal: "bring NEED x <Want>", Want = ONE cucumber
	          kind (Zone + Type) PickWant chooses from the biome one ahead of the lost cucumber's, the same biome or
	          the one below (ZONE_WEIGHTS), never more than AHEAD_MAX biomes past what the player can lift right now
	          (AttainableZone: the biome whose typical 8-reward cucumber they lift at CucumberLift.MIN_RATIO), never
	          a slice (reward 3) nor the biome's landmark tree (the row's top reward), cheaper kinds more likely
	          (weight 8 / reward), and a kind the player already keeps NEED of on their base only when nothing else
	          is left. A deal lasts OFFER_SECONDS from the theft (real time: it runs while the player is offline).
	  TRADE   the wanted cucumbers count while they STAND ON THE PLAYER'S BASE (placed, not held by a zombie);
	          TRADE IN takes the NEED cheapest of them and the lost cucumber sprouts at the player's feet at the
	          den, a field cucumber to lift home (the Redemption Token's way). Daytime only, never mid-raid.
	  PANEL   opens by itself within OPEN_RADIUS studs of the den's light ring (no other panel open, not in build
	          mode), closes again past CLOSE_RADIUS; a panel closed by hand stays closed until the player walks
	          away and comes back.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))
local CucumberLift = require(Modules:WaitForChild("CucumberLift"))

local M = {}

M.NEED = 3 -- cucumbers of the wanted kind per deal
M.OFFER_SECONDS = 12 * 3600 -- a deal lasts this long from the theft (real time)
M.OPEN_RADIUS = 14 -- studs (flat) from the den's light ring: the panel opens
M.CLOSE_RADIUS = 19 -- ... and closes again past this (hysteresis, so a player on the edge never flickers)
M.PROXIMITY_STEP = 0.2 -- seconds between the client's distance checks
M.DEN_STATION = "Zombie Den " -- workspace.Map.Lobby.Stations.<this> (the trailing space is the model's name)
M.ZONE_WEIGHTS = {[1] = 0.5, [0] = 0.35, [-1] = 0.15} -- biome delta from the lost cucumber's -> weight
M.AHEAD_MAX = 1 -- never more than this many biomes past the player's attainable biome
M.SLICE_REWARD = 3 -- the lightest kind of every biome (never asked for)
M.CHEAP_WEIGHT_BASE = 8 -- weight of a kind = this / its reward (the typical 8-reward kind = 1)

M.REMOTE = "DenRequest" -- ReplicatedStorage.Remotes.DenRequest (RemoteFunction, client -> server)
M.STATE_REMOTE = "DenState" -- ReplicatedStorage.Remotes.DenState (RemoteEvent, server -> player)
M.REQUEST_PER_SECOND = 2 -- per player, all actions together (burst 4)
M.REQUEST_BURST = 4
M.TRADE_CONFIRM_SECONDS = 3 -- the first TRADE IN tap arms "SURE?" this long

M.ERRORS = { -- server error code -> what the player reads
	NotLoaded = "Your data is still loading.",
	Closing = "Your data is saving - try again in a moment.",
	Night = "The den only trades by daylight.",
	CombatLocked = "Finish defending your plot first.",
	NotFound = "That deal is gone.",
	Expired = "That deal has expired.",
	NotEnough = "You need 3 of the wanted cucumber on your base.",
	Busy = "A zombie has hold of one of them!",
	NoPlot = "You need a base for that.",
	NoCharacter = "You need to be standing at the den.",
	SpawnFailed = "The zombies could not hand it over - try again in a moment.",
	RateLimited = "Slow down a little.",
	BadRequest = "Something went wrong.",
	Unavailable = "Not available right now.",
}

local function Finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function M.Key(zone, typeName)
	return tostring(zone) .. "|" .. tostring(typeName)
end

--.. the kinds of a biome a deal may ask for: {{Type, Reward}} cheapest first, no slice, no landmark tree
function M.Candidates(zoneName)
	local pool = CucumberValues.REWARDS[zoneName]
	local list = {}
	if type(pool) ~= "table" then
		table.insert(list, {Type = "Cucumber", Reward = CucumberValues.GENERIC["Cucumber"] or 8})
		return list
	end
	local top = 0
	for _, reward in pairs(pool) do
		if Finite(reward) and reward > top then top = reward end
	end
	for typeName, reward in pairs(pool) do
		if Finite(reward) and reward > M.SLICE_REWARD and reward < top then
			table.insert(list, {Type = typeName, Reward = reward})
		end
	end
	if #list == 0 then -- a one- or two-kind biome: whatever is not the slice
		for typeName, reward in pairs(pool) do
			if Finite(reward) and reward > M.SLICE_REWARD then table.insert(list, {Type = typeName, Reward = reward}) end
		end
	end
	table.sort(list, function(a, b)
		if a.Reward ~= b.Reward then return a.Reward < b.Reward end
		return a.Type < b.Type
	end)
	return list
end

--.. the highest biome whose typical (cheapest non-slice) cucumber this strength lifts at CucumberLift.MIN_RATIO
function M.AttainableZone(strength)
	strength = Finite(strength) and math.max(0, strength) or 0
	local zones = CucumberValues.ZONES
	for i = #zones, 1, -1 do
		local candidates = M.Candidates(zones[i])
		local typical = candidates[1]
		local ok, kg = pcall(CucumberLift.Compute, zones[i], typical and typical.Type or "Cucumber")
		if not (ok and Finite(kg) and kg > 0) then
			kg = (CucumberLift.ZONE_BASE[zones[i]] or 3) * (8 / 3) ^ (CucumberLift.REWARD_POWER or 0.4)
		end
		if strength / kg >= (CucumberLift.MIN_RATIO or 0.4) then return i end
	end
	return 1
end

local function Roll(rng, weighted)
	local total = 0
	for _, w in ipairs(weighted) do total += w.Weight end
	if total <= 0 then return weighted[1] end
	local pick = (rng and rng:NextNumber() or math.random()) * total
	for _, w in ipairs(weighted) do
		pick -= w.Weight
		if pick <= 0 then return w end
	end
	return weighted[#weighted]
end

--.. the kind a deal asks for: {Zone, Type, Reward}
--..   lostZone   1..#ZONES (the stolen cucumber's biome index; a name is accepted too)
--..   strength   the player's Strength (caps the biome at AttainableZone + AHEAD_MAX)
--..   rng        a Random (optional)
--..   exclude    set of Key(zone, type) the player already keeps NEED of (used only when something else is left)
--..   lostReward the stolen cucumber's type reward (CucumberValues.RewardOf; default the typical 8)
function M.PickWant(lostZone, strength, rng, exclude, lostReward)
	local zones = CucumberValues.ZONES
	if type(lostZone) == "string" then lostZone = CucumberValues.TierOf(lostZone) end
	lostZone = math.clamp(Finite(lostZone) and math.floor(lostZone) or 1, 1, #zones)
	local cap = math.min(#zones, M.AttainableZone(strength) + M.AHEAD_MAX)
	local options = {}
	for delta, weight in pairs(M.ZONE_WEIGHTS) do
		local z = lostZone + delta
		if z >= 1 and z <= cap then table.insert(options, {Zone = z, Weight = weight}) end
	end
	if #options == 0 then table.insert(options, {Zone = math.clamp(math.min(lostZone, cap), 1, #zones), Weight = 1}) end
	table.sort(options, function(a, b) return a.Zone < b.Zone end)
	local zoneIndex = Roll(rng, options).Zone
	local zoneName = zones[zoneIndex]
	local candidates = M.Candidates(zoneName)
	--.. within the biome: the kind whose NEED-fold base value sits closest to the lost cucumber's base value
	--.. (a lost tree asks for the biome's bigger kinds, a lost slice for its cheap ones); mutations / size of
	--.. the lost one never count - the deal is about the kind, not the roll
	local lostValue = math.max(1, (Finite(lostReward) and lostReward or M.CHEAP_WEIGHT_BASE) * CucumberValues.ZONE_VALUE_STEP ^ (lostZone - 1))
	local function weightOf(c)
		local value = M.NEED * c.Reward * CucumberValues.ZONE_VALUE_STEP ^ (zoneIndex - 1)
		local gap = math.abs(math.log(value / lostValue) / math.log(CucumberValues.ZONE_VALUE_STEP)) -- biomes of difference
		return 1 / (1 + gap)
	end
	local weighted = {}
	for _, c in ipairs(candidates) do
		if not (exclude and exclude[M.Key(zoneName, c.Type)]) then
			table.insert(weighted, {Type = c.Type, Reward = c.Reward, Weight = weightOf(c)})
		end
	end
	if #weighted == 0 then
		for _, c in ipairs(candidates) do
			table.insert(weighted, {Type = c.Type, Reward = c.Reward, Weight = weightOf(c)})
		end
	end
	local pick = Roll(rng, weighted)
	return {Zone = zoneName, Type = pick.Type, Reward = pick.Reward}
end

--.. a Want table from a saved record is trusted only when it names a real kind
function M.ValidWant(want)
	if type(want) ~= "table" or type(want.Zone) ~= "string" or type(want.Type) ~= "string" then return false end
	if not table.find(CucumberValues.ZONES, want.Zone) then return false end
	return #want.Type > 0 and #want.Type <= 64
end

--.. "3 x Prickly Cucumber"
function M.WantText(want, need)
	need = Finite(need) and need or M.NEED
	return string.format("%d x %s", need, want and tostring(want.Type) or "cucumber")
end

--.. the ReplicatedStorage.CucumberIndexPreviews child that pictures a kind ("Desert Prickly Cucumber")
function M.PreviewName(zone, typeName)
	return tostring(zone or "Spawn") .. " " .. tostring(typeName or "Cucumber")
end

--.. 43200 -> "12h 0m", 5400 -> "1h 30m", 90 -> "1m 30s", 9 -> "9s"
function M.Countdown(seconds)
	seconds = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
	local h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
	if h > 0 then return string.format("%dh %dm", h, m) end
	if m > 0 then return string.format("%dm %ds", m, s) end
	return string.format("%ds", s)
end

return M
