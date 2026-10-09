--[[
	PetsCatalog  (ModuleScript, ReplicatedStorage.Modules)
	The egg -> pet tables of the Zombie Cucumber Game, ported 2026-09-07 (only the pets that hatch
	from the eight walk-up eggs; product / boss / reward pets were left behind on purpose).

	  * EGGS[<name> Egg].Pets = {[petName] = {Percent, Rank}} -- the exact zombie pools + odds
	    (standardised 40/30/15/9/5/1 with the 0.05% ultra-chase slots on Lava / Narmek and the
	    secret 1-in-50,000 Gregory in the Basic Egg -- rank-less, so he never shows in a list)
	  * PETS[petName] = {Rarity, DisplayName} -- the rarity the reveal card colours by and the
	    name players SEE (data keys stay the original model names, exactly like the zombie game)
	  * models live in ReplicatedStorage.Assets.Pets/<petName> (PrimaryPart "Root", parts welded
	    to it, CanCollide off) -- transferred 1:1 from the zombie place
	  * Roll(eggName) = the zombie EggService float roll (weight / total); no pity, no
	    guaranteed-rare (those needed saved data and there is no pet saving yet)
	  * EggKey("Basic") -> "Basic Egg" (EggShop / EggPlacement stamp the short biome name)
	  * ChanceText(eggName, pet) -> "[1 in N]" for the reveal card corner tag
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = {}

M.EGGS = {
	["Basic Egg"] = {
		Order = 1;
		Pets = {
			["Gregory"] = {Percent = 0.002}; -- 1 in 50,000: the secret (no Rank = never listed)
			["Cat"] = {Percent = 40, Rank = 1};
			["Dog"] = {Percent = 30, Rank = 2};
			["Bunny"] = {Percent = 15, Rank = 3};
			["Wolf"] = {Percent = 9, Rank = 4};
			["Tabby"] = {Percent = 5, Rank = 5};
			["Fox"] = {Percent = 1, Rank = 6};
		};
	};
	["Desert Egg"] = {
		Order = 2;
		Pets = {
			["Barrel"] = {Percent = 40, Rank = 1};
			["Treasure Gem"] = {Percent = 30, Rank = 2};
			["Cannon"] = {Percent = 15, Rank = 3};
			["Chest"] = {Percent = 9, Rank = 4};
			["Desert Overlord"] = {Percent = 5, Rank = 5};
			["Cactus"] = {Percent = 1, Rank = 6};
		};
	};
	["Samurai Egg"] = {
		Order = 3;
		Pets = {
			["Dog Ninja"] = {Percent = 40, Rank = 1};
			["Good Ninja"] = {Percent = 30, Rank = 2};
			["Evil Ninja"] = {Percent = 15, Rank = 3};
			["Good Samurai"] = {Percent = 9, Rank = 4};
			["Evil Samurai"] = {Percent = 5, Rank = 5};
			["Sensei"] = {Percent = 1, Rank = 6};
		};
	};
	["Farm Egg"] = {
		Order = 4;
		Pets = {
			["Hay"] = {Percent = 40, Rank = 1};
			["Bird"] = {Percent = 30, Rank = 2};
			["Panda"] = {Percent = 15, Rank = 3};
			["Cow"] = {Percent = 9, Rank = 4};
			["Pig"] = {Percent = 5, Rank = 5};
			["Farmer"] = {Percent = 1, Rank = 6};
		};
	};
	["Frozen Egg"] = {
		Order = 5;
		Pets = {
			["Red Snowman"] = {Percent = 40, Rank = 1};
			["Blue Snowman"] = {Percent = 30, Rank = 2};
			["Frozen Dragon"] = {Percent = 15, Rank = 3};
			["Frozen Hydra"] = {Percent = 9, Rank = 4};
			["Frozen Ice Shock"] = {Percent = 5, Rank = 5};
			["Frozen Gem"] = {Percent = 1, Rank = 6};
		};
	};
	["Ocean Egg"] = {
		Order = 6;
		Pets = {
			["Oceanic Dog"] = {Percent = 40, Rank = 1};
			["Oceanic Kitty"] = {Percent = 30, Rank = 2};
			["Oceanic Bunny"] = {Percent = 15, Rank = 3};
			["Oceanic Bear"] = {Percent = 9, Rank = 4};
			["Ocean Dragon"] = {Percent = 5, Rank = 5};
			["Atlantic Hydra"] = {Percent = 1, Rank = 6};
		};
	};
	["Lava Egg"] = {
		Order = 7;
		Pets = {
			["Lava Plume"] = {Percent = 40, Rank = 1};
			["Lava Golem"] = {Percent = 30, Rank = 2};
			["Lava Veltal"] = {Percent = 15, Rank = 3};
			["Lava Trio"] = {Percent = 9.95, Rank = 4};
			["Lava Dragon"] = {Percent = 5, Rank = 5};
			["Demon Dog"] = {Percent = 0.05, Rank = 6};
		};
	};
	["Narmek Egg"] = {
		Order = 8;
		Pets = {
			["Moon Bunny"] = {Percent = 40, Rank = 1};
			["Satellite Pup"] = {Percent = 30, Rank = 2};
			["Alien Slime"] = {Percent = 15, Rank = 3};
			["Meteor Moth"] = {Percent = 9.95, Rank = 4};
			["Nebula Fox"] = {Percent = 5, Rank = 5};
			["Cosmo Cat"] = {Percent = 0.05, Rank = 6};
		};
	};
}

--.. Rarity + the display name the player sees (zombie PetDisplayNames). Keys = model names.
M.PETS = {
	-- Basic Egg (grassy set)
	["Cat"] = {Rarity = "Common", DisplayName = "Cucumber Deer"};
	["Dog"] = {Rarity = "Common", DisplayName = "Moss Turtle"};
	["Bunny"] = {Rarity = "Uncommon", DisplayName = "Sprout Pup"};
	["Wolf"] = {Rarity = "Rare", DisplayName = "Bloom Bee"};
	["Tabby"] = {Rarity = "Rare", DisplayName = "Vine Gecko"};
	["Fox"] = {Rarity = "Legendary", DisplayName = "Meadow Bunny"};
	["Gregory"] = {Rarity = "Mythical", DisplayName = "Gregory"};
	-- Desert Egg
	["Barrel"] = {Rarity = "Common", DisplayName = "Dune Scorpion"};
	["Treasure Gem"] = {Rarity = "Common", DisplayName = "Cactus Fox"};
	["Cannon"] = {Rarity = "Common", DisplayName = "Sand Scarab"};
	["Chest"] = {Rarity = "Uncommon", DisplayName = "Oasis Turtle"};
	["Desert Overlord"] = {Rarity = "Rare", DisplayName = "Sun Lizard"};
	["Cactus"] = {Rarity = "Legendary", DisplayName = "Relic Cobra"};
	-- Samurai Egg
	["Dog Ninja"] = {Rarity = "Common", DisplayName = "Sakura Kitsune"};
	["Good Ninja"] = {Rarity = "Uncommon", DisplayName = "Bamboo Panda"};
	["Evil Ninja"] = {Rarity = "Uncommon", DisplayName = "Ronin Beetle"};
	["Good Samurai"] = {Rarity = "Rare", DisplayName = "Lantern Crane"};
	["Evil Samurai"] = {Rarity = "Rare", DisplayName = "Kappa Cub"};
	["Sensei"] = {Rarity = "Legendary", DisplayName = "Torii Dragon"};
	-- Farm Egg
	["Hay"] = {Rarity = "Common", DisplayName = "Barn Chick"};
	["Bird"] = {Rarity = "Common", DisplayName = "Hay Pup"};
	["Panda"] = {Rarity = "Uncommon", DisplayName = "Tractor Beetle"};
	["Cow"] = {Rarity = "Uncommon", DisplayName = "Patch Piglet"};
	["Pig"] = {Rarity = "Rare", DisplayName = "Windmill Lamb"};
	["Farmer"] = {Rarity = "Legendary", DisplayName = "Harvest Cow"};
	-- Frozen Egg (arctic set)
	["Red Snowman"] = {Rarity = "Common", DisplayName = "Frost Penguin"};
	["Blue Snowman"] = {Rarity = "Common", DisplayName = "Glacier Wolf"};
	["Frozen Dragon"] = {Rarity = "Uncommon", DisplayName = "Snowy Seal"};
	["Frozen Hydra"] = {Rarity = "Uncommon", DisplayName = "Icicle Owl"};
	["Frozen Ice Shock"] = {Rarity = "Rare", DisplayName = "Polar Cub"};
	["Frozen Gem"] = {Rarity = "Legendary", DisplayName = "Crystal Hare"};
	-- Ocean Egg (underwater set)
	["Oceanic Dog"] = {Rarity = "Common", DisplayName = "Coral Axolotl"};
	["Oceanic Kitty"] = {Rarity = "Common", DisplayName = "Bubble Turtle"};
	["Oceanic Bunny"] = {Rarity = "Uncommon", DisplayName = "Kelp Seahorse"};
	["Oceanic Bear"] = {Rarity = "Uncommon", DisplayName = "Pearl Crab"};
	["Ocean Dragon"] = {Rarity = "Rare", DisplayName = "Starfish Pup"};
	["Atlantic Hydra"] = {Rarity = "Legendary", DisplayName = "Clown Ray"};
	-- Lava Egg
	["Lava Plume"] = {Rarity = "Common", DisplayName = "Magma Hound"};
	["Lava Golem"] = {Rarity = "Common", DisplayName = "Ember Bat"};
	["Lava Veltal"] = {Rarity = "Uncommon", DisplayName = "Obsidian Golem"};
	["Lava Trio"] = {Rarity = "Rare", DisplayName = "Flame Salamander"};
	["Lava Dragon"] = {Rarity = "Rare", DisplayName = "Coal Beetle"};
	["Demon Dog"] = {Rarity = "Mythical", DisplayName = "Volcano Turtle"};
	-- Narmek Egg (space set; these already carry their display names)
	["Moon Bunny"] = {Rarity = "Common", DisplayName = "Moon Bunny"};
	["Satellite Pup"] = {Rarity = "Common", DisplayName = "Satellite Pup"};
	["Alien Slime"] = {Rarity = "Uncommon", DisplayName = "Alien Slime"};
	["Meteor Moth"] = {Rarity = "Rare", DisplayName = "Meteor Moth"};
	["Nebula Fox"] = {Rarity = "Legendary", DisplayName = "Nebula Fox"};
	["Cosmo Cat"] = {Rarity = "Mythical", DisplayName = "Cosmo Cat"};
}

--.. reveal-card gradients (zombie RarityController.Classes) + the screen-glow colours
M.RARITY_GRADIENTS = {
	Common = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(206, 255, 198));
	Uncommon = ColorSequence.new(Color3.fromRGB(213, 255, 0), Color3.fromRGB(0, 207, 145));
	Rare = ColorSequence.new(Color3.fromRGB(0, 255, 255), Color3.fromRGB(0, 145, 255));
	Epic = ColorSequence.new(Color3.fromRGB(249, 215, 255), Color3.fromRGB(226, 0, 255));
	Legendary = ColorSequence.new(Color3.fromRGB(255, 247, 0), Color3.fromRGB(255, 183, 0));
	Mythical = ColorSequence.new(Color3.fromRGB(246, 139, 255), Color3.fromRGB(25, 182, 255));
	Omega = ColorSequence.new(Color3.fromRGB(255, 234, 0), Color3.fromRGB(255, 0, 0));
	Special = ColorSequence.new(Color3.fromRGB(255, 219, 219), Color3.fromRGB(255, 0, 0));
}
M.RARITY_GLOW = {
	Common = Color3.fromRGB(255, 255, 255);
	Uncommon = Color3.fromRGB(0, 207, 145);
	Rare = Color3.fromRGB(0, 255, 255);
	Epic = Color3.fromRGB(226, 0, 255);
	Legendary = Color3.fromRGB(255, 247, 0);
	Mythical = Color3.fromRGB(246, 139, 255);
	Omega = Color3.fromRGB(255, 138, 0);
	Special = Color3.fromRGB(255, 80, 80);
}
M.RARITY_ORDER = {Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythical = 6, Omega = 7, Special = 8}

--.. "Basic" / "Basic Egg" / "Basic Egg (2.4 kg)" -> "Basic Egg"
function M.EggKey(eggName)
	if type(eggName) ~= "string" then return nil end
	local base = eggName:gsub("%s*%b()%s*$", ""):gsub("%s*Egg%s*$", "")
	local key = base .. " Egg"
	return M.EGGS[key] and key or nil
end

function M.PoolOf(eggName)
	local key = M.EggKey(eggName)
	return key and M.EGGS[key].Pets or nil, key
end

--.. the zombie EggService roll: float roll over the summed weights (integer rolls broke the
--.. fractional-percent chase pets). rng = optional Random
function M.Roll(eggName, rng)
	local pool = M.PoolOf(eggName)
	if not pool then return nil end
	local total = 0
	for _, entry in pairs(pool) do total += entry.Percent end
	local roll = (rng and rng:NextNumber() or math.random()) * total
	local counter = 0
	local chosen
	for pet, entry in pairs(pool) do
		counter += entry.Percent
		if counter >= roll then chosen = pet break end
	end
	if not chosen then
		for pet in pairs(pool) do chosen = pet break end
	end
	return chosen
end

function M.PercentOf(eggName, pet)
	local pool = M.PoolOf(eggName)
	local entry = pool and pool[pet]
	return entry and tonumber(entry.Percent) or nil
end

--.. "[1 in N]" corner tag (nil when the pet has no odds in that egg)
function M.ChanceText(eggName, pet)
	local percent = M.PercentOf(eggName, pet)
	if not percent or percent <= 0 then return nil end
	local n = 100 / percent
	if n >= 9.5 or n % 1 == 0 then
		return ("[1 in %d]"):format(math.floor(n + 0.5))
	end
	return ("[1 in %.1f]"):format(n)
end

function M.RarityOf(pet)
	local info = M.PETS[pet]
	return info and info.Rarity or "Common"
end

function M.DisplayNameOf(pet)
	local info = M.PETS[pet]
	return info and info.DisplayName or pet
end

--.. the pool listed by rank (rank-less secrets are skipped, exactly like the zombie egg display)
function M.ListedPets(eggName)
	local pool = M.PoolOf(eggName)
	local list = {}
	if not pool then return list end
	for pet, entry in pairs(pool) do
		if entry.Rank then list[#list + 1] = {Name = pet, Percent = entry.Percent, Rank = entry.Rank} end
	end
	table.sort(list, function(a, b) return a.Rank < b.Rank end)
	return list
end

function M.ModelOf(pet)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local pets = assets and assets:FindFirstChild("Pets")
	return pets and pets:FindFirstChild(pet) or nil
end

return M
