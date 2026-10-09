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
CucumberValues.EARN_VALUE_PERIOD = 16 -- seconds for a placed cucumber to re-earn its break value (2026-09-23 economy: was 220)
CucumberValues.ZONE_VALUE_STEP = 8 -- every biome is worth this much more than the one before
CucumberValues.GOLDEN_MULT = 12
CucumberValues.FIRST_ZONE_BONUS = 0 -- flat +cash/s in Spawn (2026-09-23: 0, was 0.5 -- the 16 s period already pays 0.5 $/s for a typical Spawn cucumber)
CucumberValues.DEFAULT_REWARD = 8

--.. type Reward per biome (names = CucumberSpawner's RAW pools). 2026-09-23 economy ladder: slice 3,
--.. typical 8 .. tree 64 = 8x the typical = the NEXT biome's typical, so the Index stays monotonic and one
--.. tree never outpays a base of the next biome. 6 types {3, 8, 14, 24, 40, 64}, 7 types
--.. {3, 8, 13, 20, 30, 45, 64}, 8 types {3, 8, 12, 17, 24, 34, 48, 64}.
CucumberValues.REWARDS = {
	Spawn = {["Sliced Cucumber"] = 3, ["Cucumber"] = 8, ["Slice Stack"] = 14, ["Vined Cucumber"] = 24, ["Flowered Cucumber"] = 40, ["Cucumber Tree"] = 64},
	Desert = {["Sun-Dried Slice"] = 3, ["Prickly Cucumber"] = 8, ["Sliced Cucumber"] = 12, ["Sun-Baked Cucumber"] = 17, ["Wrapped Cucumber"] = 24, ["Cactus Cucumber"] = 34, ["Desert Palm"] = 48, ["Sandstone Tree"] = 64},
	Samurai = {["Sliced Cucumber"] = 3, ["Katana Cucumber"] = 8, ["Bamboo Cucumber"] = 13, ["Lantern Cucumber"] = 20, ["Bamboo Grove"] = 30, ["Torii Gate"] = 45, ["Sakura Tree"] = 64},
	Farm = {["Cucumber Basket"] = 3, ["Muddy Cucumber"] = 8, ["Crate Cucumber"] = 14, ["Windmill Plant"] = 24, ["Hay Bale"] = 40, ["Cucumber Tree"] = 64},
	Snow = {["Frozen Slice"] = 3, ["Snowcap Cucumber"] = 8, ["Snowball Slice"] = 12, ["Crystal Cucumber"] = 17, ["Frozen Cucumber"] = 24, ["Snow Tree"] = 34, ["Icicle Tree"] = 48, ["Frozen Tree"] = 64},
	Underwater = {["Bubble Slice"] = 3, ["Seaweed Cucumber"] = 8, ["Shell Slice"] = 12, ["Coral Cucumber"] = 17, ["Pearl Cucumber"] = 24, ["Kelp Tree"] = 34, ["Bubble Tree"] = 48, ["Coral Tree"] = 64},
	Volcano = {["Molten Slice"] = 3, ["Charred Cucumber"] = 8, ["Molten Cucumber"] = 13, ["Flame Cucumber"] = 20, ["Obsidian Tree"] = 30, ["Volcano Cucumber"] = 45, ["Magma Tree"] = 64},
	Narmek = {["Moon Slice"] = 3, ["Meteor Cucumber"] = 8, ["Planet Slice"] = 12, ["Astronaut Cucumber"] = 17, ["Neon Alien Cucumber"] = 24, ["Moon Tree"] = 34, ["Alien Tree"] = 48, ["Galaxy Tree"] = 64},
	--.. 2026-09-18: the hand-modelled Toyland / Neon sets, on the 7-row ladder Samurai / Volcano use
	Toyland = {["Toy Slice"] = 3, ["Lego Cucumber"] = 8, ["Jack-in-the-Box Cucumber"] = 13, ["Toy Rocket Cucumber"] = 20, ["Pinwheel Plant"] = 30, ["Building Block Tree"] = 45, ["Toy Train Cucumber"] = 64},
	Neon = {["Neon Slice"] = 3, ["Electro Cucumber"] = 8, ["Neon Grid Cucumber"] = 13, ["Hologram Cucumber"] = 20, ["Neon Palm"] = 30, ["Neon Tree"] = 45, ["Cyber Cucumber"] = 64},
}
--.. generic pool: the old Toyland / Neon names (legacy saves) and any name a biome table does not know
CucumberValues.GENERIC = {["Cucumber"] = 8, ["Giant Cucumber"] = 40, ["Sliced Cucumber"] = 3, ["Cucumber Tree"] = 64}

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
