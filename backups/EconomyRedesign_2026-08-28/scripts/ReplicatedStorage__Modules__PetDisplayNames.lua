--.. Display-name layer added 2026-08-22 with the Blender pet model swap.
--.. Player data + dictionaries still key pets by their ORIGINAL names (never
--.. rename those -- saves reference them); this maps a data key to the name the
--.. player should SEE. Get() falls back to the key itself, so unmapped pets
--.. (Food Cuke, Boss, Products, Rewards...) are unaffected.
local NAMES = {
	-- Basic Egg (grassy set)
	["Cat"] = "Cucumber Deer";
	["Dog"] = "Moss Turtle";
	["Bunny"] = "Sprout Pup";
	["Wolf"] = "Bloom Bee";
	["Tabby"] = "Vine Gecko";
	["Fox"] = "Meadow Bunny";
	-- Desert Egg
	["Barrel"] = "Dune Scorpion";
	["Treasure Gem"] = "Cactus Fox";
	["Cannon"] = "Sand Scarab";
	["Chest"] = "Oasis Turtle";
	["Desert Overlord"] = "Sun Lizard";
	["Cactus"] = "Relic Cobra";
	-- Samurai Egg
	["Dog Ninja"] = "Sakura Kitsune";
	["Good Ninja"] = "Bamboo Panda";
	["Evil Ninja"] = "Ronin Beetle";
	["Good Samurai"] = "Lantern Crane";
	["Evil Samurai"] = "Kappa Cub";
	["Sensei"] = "Torii Dragon";
	-- Farm Egg
	["Hay"] = "Barn Chick";
	["Bird"] = "Hay Pup";
	["Panda"] = "Tractor Beetle";
	["Cow"] = "Patch Piglet";
	["Pig"] = "Windmill Lamb";
	["Farmer"] = "Harvest Cow";
	-- Frozen Egg (arctic set)
	["Red Snowman"] = "Frost Penguin";
	["Blue Snowman"] = "Glacier Wolf";
	["Frozen Dragon"] = "Snowy Seal";
	["Frozen Hydra"] = "Icicle Owl";
	["Frozen Ice Shock"] = "Polar Cub";
	["Frozen Gem"] = "Crystal Hare";
	-- Ocean Egg (underwater set)
	["Oceanic Dog"] = "Coral Axolotl";
	["Oceanic Kitty"] = "Bubble Turtle";
	["Oceanic Bunny"] = "Kelp Seahorse";
	["Oceanic Bear"] = "Pearl Crab";
	["Ocean Dragon"] = "Starfish Pup";
	["Atlantic Hydra"] = "Clown Ray";
	-- Lava Egg
	["Lava Plume"] = "Magma Hound";
	["Lava Golem"] = "Ember Bat";
	["Lava Veltal"] = "Obsidian Golem";
	["Lava Trio"] = "Flame Salamander";
	["Lava Dragon"] = "Coal Beetle";
	["Demon Dog"] = "Volcano Turtle";
}

local module = {}
module.Names = NAMES

function module.Get(petName)
	return NAMES[petName] or petName
end

return module
