--[[
	CucumberValues  (ModuleScript, ReplicatedStorage.Modules)
	What a cucumber earns per second while it stands on a plot -- the Zombie Cucumber Game's
	vault economy (BreakablesService type tables + CarryService.EarnRateOf), ported 2026-09-06:
	  break value = type Reward x 8^(biome tier - 1) x material x mutations (CucumberMutations: Golden x12, Diamond x50, NEON x15 ... PRISMATIC x750, that product capped at 5000) x size (HUGE x3 / MASSIVE x6 / COLOSSAL x12, applied OUTSIDE the cap so a giant always pays)
	  cash/s     = max(0.01, break value / 220)       (+0.5 flat in the first biome)
	A plot cucumber re-earns its own break value every ~220 s and every biome pays x8 the last.
	Biome tier = position in ZONES (Spawn 1 ... Neon 10). Toyland / Neon got hand-modelled sets
	on 2026-09-18 (cucumbers/CUCUMBERS-REV3.md) and price through REWARDS like every other biome;
	GENERIC stays as the fallback for the old generic names (legacy saves, see CucumberSpawner LEGACY_TYPES).
	Used by LeaderstatsService (server: "Rate" attribute on placed cucumbers, Cash/s) and
	PlacedCucumberCardClient (client: card text, fallback while the attribute is on its way).
	  CucumberValues.RateOf(zone, typeName, golden)  -> cash/s
	  CucumberValues.RateOfInstance(model)           -> cash/s from its Zone / TypeName / Golden attributes
	  CucumberValues.ValueOf(zone, typeName, golden) -> break value
	  CucumberValues.TierOf(zone), .ZoneColor(zone), .ZoneTextColors(zone) -> text, stroke
]]
local CucumberMutations = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CucumberMutations"))

local CucumberValues = {}

CucumberValues.ZONES = {"Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek", "Toyland", "Neon"}
CucumberValues.EARN_VALUE_PERIOD = 220 -- seconds for a placed cucumber to re-earn its break value
CucumberValues.ZONE_VALUE_STEP = 8 -- every biome is worth this much more than the one before
CucumberValues.GOLDEN_MULT = 12
CucumberValues.FIRST_ZONE_BONUS = 0.5 -- flat +cash/s in Spawn, where the ladder starts in pennies
CucumberValues.DEFAULT_REWARD = 8

--.. type Reward per biome (the live game's BreakablesService tables; names = CucumberSpawner's RAW pools)
CucumberValues.REWARDS = {
	Spawn = {["Sliced Cucumber"] = 3, ["Cucumber"] = 8, ["Slice Stack"] = 20, ["Vined Cucumber"] = 56, ["Flowered Cucumber"] = 144, ["Cucumber Tree"] = 360},
	Desert = {["Sun-Dried Slice"] = 3, ["Prickly Cucumber"] = 8, ["Sliced Cucumber"] = 15, ["Sun-Baked Cucumber"] = 28, ["Wrapped Cucumber"] = 56, ["Cactus Cucumber"] = 105, ["Desert Palm"] = 195, ["Sandstone Tree"] = 360},
	Samurai = {["Sliced Cucumber"] = 3, ["Katana Cucumber"] = 8, ["Bamboo Cucumber"] = 17, ["Lantern Cucumber"] = 37, ["Bamboo Grove"] = 82, ["Torii Gate"] = 173, ["Sakura Tree"] = 360},
	Farm = {["Cucumber Basket"] = 3, ["Muddy Cucumber"] = 8, ["Crate Cucumber"] = 20, ["Windmill Plant"] = 56, ["Hay Bale"] = 144, ["Cucumber Tree"] = 360},
	Snow = {["Frozen Slice"] = 3, ["Snowcap Cucumber"] = 8, ["Snowball Slice"] = 15, ["Crystal Cucumber"] = 28, ["Frozen Cucumber"] = 56, ["Snow Tree"] = 105, ["Icicle Tree"] = 195, ["Frozen Tree"] = 360},
	Underwater = {["Bubble Slice"] = 3, ["Seaweed Cucumber"] = 8, ["Shell Slice"] = 15, ["Coral Cucumber"] = 28, ["Pearl Cucumber"] = 56, ["Kelp Tree"] = 105, ["Bubble Tree"] = 195, ["Coral Tree"] = 360},
	Volcano = {["Molten Slice"] = 3, ["Charred Cucumber"] = 8, ["Molten Cucumber"] = 17, ["Flame Cucumber"] = 37, ["Obsidian Tree"] = 82, ["Volcano Cucumber"] = 173, ["Magma Tree"] = 360},
	Narmek = {["Moon Slice"] = 3, ["Meteor Cucumber"] = 8, ["Planet Slice"] = 15, ["Astronaut Cucumber"] = 28, ["Neon Alien Cucumber"] = 56, ["Moon Tree"] = 105, ["Alien Tree"] = 195, ["Galaxy Tree"] = 360},
	--.. 2026-09-18: the hand-modelled Toyland / Neon sets, on the 7-row ladder Samurai / Volcano use
	Toyland = {["Toy Slice"] = 3, ["Lego Cucumber"] = 8, ["Jack-in-the-Box Cucumber"] = 17, ["Toy Rocket Cucumber"] = 37, ["Pinwheel Plant"] = 82, ["Building Block Tree"] = 173, ["Toy Train Cucumber"] = 360},
	Neon = {["Neon Slice"] = 3, ["Electro Cucumber"] = 8, ["Neon Grid Cucumber"] = 17, ["Hologram Cucumber"] = 37, ["Neon Palm"] = 82, ["Neon Tree"] = 173, ["Cyber Cucumber"] = 360},
}
--.. generic pool: the old Toyland / Neon names (legacy saves) and any name a biome table does not know
CucumberValues.GENERIC = {["Cucumber"] = 8, ["Giant Cucumber"] = 45, ["Sliced Cucumber"] = 3, ["Cucumber Tree"] = 140}

--.. the card's biome line: the live game's zone colours (Shards), Neon = the spawner's tint,
--.. Toyland a pink of its own (the spawner's purple tint would read as Narmek on a label)
CucumberValues.ZONE_COLORS = {
	Spawn = Color3.fromRGB(60, 140, 52), Desert = Color3.fromRGB(120, 168, 86), Samurai = Color3.fromRGB(170, 42, 46),
	Farm = Color3.fromRGB(64, 150, 58), Snow = Color3.fromRGB(120, 186, 214), Underwater = Color3.fromRGB(214, 112, 82),
	Volcano = Color3.fromRGB(255, 96, 24), Narmek = Color3.fromRGB(150, 74, 230), Toyland = Color3.fromRGB(255, 105, 180),
	Neon = Color3.fromRGB(0, 255, 255),
}

function CucumberValues.TierOf(zone)
	return table.find(CucumberValues.ZONES, zone) or 1
end

function CucumberValues.RewardOf(zone, typeName)
	local pool = CucumberValues.REWARDS[zone]
	local reward = pool and pool[typeName] or CucumberValues.GENERIC[typeName]
	return reward or CucumberValues.DEFAULT_REWARD
end

--.. break value: Reward x 8^(tier-1) x material x mutations (a bare golden flag = the Golden material)
function CucumberValues.ValueOf(zone, typeName, golden, material, mutations, size)
	local value = CucumberValues.RewardOf(zone, typeName) * CucumberValues.ZONE_VALUE_STEP ^ (CucumberValues.TierOf(zone) - 1)
	if not material and golden then material = "Golden" end
	return value * CucumberMutations.TotalMult(material, mutations, size)
end

--.. cash per second on a plot (fractional: every type x biome x golden combo has its own number)
function CucumberValues.RateOf(zone, typeName, golden, material, mutations, size)
	local rate = math.max(0.01, CucumberValues.ValueOf(zone, typeName, golden, material, mutations, size) / CucumberValues.EARN_VALUE_PERIOD)
	if CucumberValues.TierOf(zone) == 1 then rate += CucumberValues.FIRST_ZONE_BONUS end
	return rate
end

--.. from the attributes CucumberSpawner / CucumberCarry stamp (Zone, TypeName, Golden, SizeTier)
function CucumberValues.RateOfInstance(inst)
	return CucumberValues.RateOf(inst:GetAttribute("Zone") or "Spawn", inst:GetAttribute("TypeName") or inst.Name, inst:GetAttribute("Golden") == true, inst:GetAttribute("Material"), inst:GetAttribute("Mutations"), inst:GetAttribute("SizeTier"))
end

function CucumberValues.ZoneColor(zone)
	return CucumberValues.ZONE_COLORS[zone] or Color3.fromRGB(200, 200, 200)
end

--.. text colour lifted toward light so dark biome colours stay readable over the map, plus a deep
--.. stroke of the same hue
function CucumberValues.ZoneTextColors(zone)
	local h, s, v = CucumberValues.ZoneColor(zone):ToHSV()
	local text = Color3.fromHSV(h, math.clamp(s * 0.85, 0, 1), math.max(v, 0.9))
	local stroke = Color3.fromHSV(h, math.clamp(s, 0, 1), v * 0.3)
	return text, stroke
end

return CucumberValues
