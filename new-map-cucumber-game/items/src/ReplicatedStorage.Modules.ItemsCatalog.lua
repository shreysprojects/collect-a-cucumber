--[[
	ItemsCatalog  (ModuleScript, ReplicatedStorage.Modules)  2026-09-23
	The drop ITEMS of the New Map Cucumber Game (user: "potions/items ... boosts for a duration (2x
	speed, 2x strength, 2x coins), teleports like an enderpearl, special cucumbers, special pets,
	redemption tokens ... stored and saved in the bottom inventory, they drop on zombie deaths").
	Every number lives here; ItemService (server) and ItemClient (client) read it.

	  ITEMS  ordered list of {Key, Name, Rarity, Kind, Description, Weight, MinLevel, Color, Boost?, Duration?}
	    Kind  "Drink" = a potion: consumed on click, starts the Boost for Duration seconds (the boosts stack
	          by EXTENDING the timer, never by multiplying twice)
	          "Throw" = thrown where the camera looks (Holy Water: splash where it lands)
	          "Aim"   = click anywhere: an arched trail previews the spot, the click warps the player there
	                    (Warp Pearl; works with a cucumber on the shoulder; at night never across the lobby wall)
	          "Use"   = consumed on click for a one-shot effect (seeds, the token, the egg)
	    Weight / MinLevel  the drop roll: a zombie of variety level L (ZombieCatalog MinLevel) can drop any
	          item whose MinLevel <= L, weighted by Weight x (1 + HARD_BIAS x MinLevel / L)
	  BOOSTS[boost] = {Attr = the player attribute holding the server time the boost ends, Mult, Label, Emoji}
	    Speed    -> SpeedBoostUntil    (StrengthProgressionServer already doubles WalkSpeed while it is ahead)
	    Strength -> StrengthBoostUntil (GymService.AwardRep doubles the strength per rep)
	    Cash     -> CashBoostUntil     (IncomeService.Credit doubles every cash payout)
	  DROP  chance per zombie death = min(MaxChance, BaseChance + PerLevel x level)
	  Models live in ReplicatedStorage.Assets.Items/<Key> (Blender-authored, installed as Parts by
	  items/install_items.lua); the hotbar pictures the tool's own parts.
]]
local M = {}

M.ITEMS = {
	{Key = "SpeedPotion", Name = "Speed Potion", Rarity = "Common", Kind = "Drink", Boost = "Speed", Duration = 90,
		Color = Color3.fromRGB(51, 214, 255), Weight = 22, MinLevel = 1,
		Description = "Drink it: 2x walk speed for 1:30."},
	{Key = "StrengthPotion", Name = "Strength Potion", Rarity = "Uncommon", Kind = "Drink", Boost = "Strength", Duration = 120,
		Color = Color3.fromRGB(255, 80, 80), Weight = 18, MinLevel = 1,
		Description = "Drink it: 2x strength per bench rep for 2:00."},
	{Key = "CashPotion", Name = "Cash Potion", Rarity = "Uncommon", Kind = "Drink", Boost = "Cash", Duration = 120,
		Color = Color3.fromRGB(65, 235, 65), Weight = 18, MinLevel = 1,
		Description = "Drink it: 2x cash from your base for 2:00."},
	{Key = "WarpPearl", Name = "Warp Pearl", Rarity = "Rare", Kind = "Aim",
		Color = Color3.fromRGB(170, 100, 255), Weight = 12, MinLevel = 2,
		Description = "Click anywhere to warp there - even with a cucumber in your arms."},
	{Key = "HolyWater", Name = "Holy Water", Rarity = "Rare", Kind = "Throw",
		Color = Color3.fromRGB(191, 233, 255), Weight = 12, MinLevel = 2,
		Description = "Throw it: every zombie near the splash takes 150 damage and freezes for 2 s."},
	{Key = "RedemptionToken", Name = "Redemption Token", Rarity = "Epic", Kind = "Use",
		Color = Color3.fromRGB(255, 205, 60), Weight = 6, MinLevel = 2,
		Description = "Use it: the last cucumber the zombies stole from you comes back at your feet."},
	{Key = "GoldenSeed", Name = "Golden Seed", Rarity = "Epic", Kind = "Use",
		Color = Color3.fromRGB(255, 205, 60), Weight = 5, MinLevel = 3,
		Description = "Plant it: a GOLDEN cucumber of your best biome sprouts at your feet."},
	{Key = "VoidSeed", Name = "Void Seed", Rarity = "Legendary", Kind = "Use",
		Color = Color3.fromRGB(170, 100, 255), Weight = 2, MinLevel = 6,
		Description = "Plant it: a VOID cucumber of your best biome sprouts at your feet."},
	{Key = "ZombieEgg", Name = "Zombie Egg", Rarity = "Legendary", Kind = "Use",
		Color = Color3.fromRGB(155, 255, 74), Weight = 2, MinLevel = 4,
		Description = "Crack it: a SHADOW pet hatches on the spot. A tiny chance of Gregory."},
}

M.BOOSTS = {
	Speed = {Attr = "SpeedBoostUntil", Mult = 2, Label = "Speed", Emoji = "⚡", Color = Color3.fromRGB(51, 214, 255)},
	Strength = {Attr = "StrengthBoostUntil", Mult = 2, Label = "Strength", Emoji = "💪", Color = Color3.fromRGB(255, 80, 80)},
	Cash = {Attr = "CashBoostUntil", Mult = 2, Label = "Cash", Emoji = "💰", Color = Color3.fromRGB(65, 235, 65)},
}
M.BOOST_ORDER = {"Speed", "Strength", "Cash"}

M.DROP = {BaseChance = 0.35, PerLevel = 0.03, MaxChance = 0.65, HardBias = 0.35}
M.MAX_STACK = 99
M.PICKUP_RADIUS = 5 -- studs from a player's root to a drop
M.DROP_LIFETIME = 10 -- seconds a drop lies on the ground (2026-09-23, user: a 10 s timer over every drop, then it despawns; was 120)
M.THROW = {Speed = 70, Lift = 16, MaxSeconds = 4, MaxRange = 160}
--.. Kind "Aim" (Warp Pearl, 2026-09-23): the equipped pearl draws an arched trail from the player to the point under
--.. the mouse; a click warps there. ArcFactor x distance = the arch height (clamped), MaxRange = studs from the player
M.WARP = {MaxRange = 1500, ArcMin = 6, ArcMax = 40, ArcFactor = 0.3, RingDiameter = 4}
M.HOLY_WATER = {Damage = 150, Fraction = 0.4, Radius = 12, Stun = 2} -- 2026-09-23: at least Damage, or Fraction of each zombie's max hit points
M.ZOMBIE_EGG = {GregoryChance = 0.02, Mutations = {"SHADOW"},
	RarityWeights = {Common = 0, Uncommon = 6, Rare = 10, Epic = 8, Legendary = 4, Mythical = 1.5, Omega = 0.5, Special = 0}}
M.USE_COOLDOWN = 0.5 -- seconds between two uses per player

M.RARITY_COLORS = {
	Common = Color3.fromRGB(215, 215, 225), Uncommon = Color3.fromRGB(120, 230, 110), Rare = Color3.fromRGB(90, 170, 255),
	Epic = Color3.fromRGB(200, 110, 255), Legendary = Color3.fromRGB(255, 190, 60), Mythical = Color3.fromRGB(255, 90, 160),
}

local ByKey = {}
for i, def in ipairs(M.ITEMS) do
	def.Order = i
	ByKey[def.Key] = def
end

function M.Get(key)
	return type(key) == "string" and ByKey[key] or nil
end

function M.RarityColor(rarity)
	return M.RARITY_COLORS[rarity] or M.RARITY_COLORS.Common
end

--.. the drop roll for a zombie death: nil (no drop) or an item definition
function M.RollDrop(level, rng)
	level = math.clamp(tonumber(level) or 1, 1, 10) -- splitter children carry MinLevel 99: never "level 99" loot
	local random = rng or Random.new()
	local chance = math.min(M.DROP.MaxChance, M.DROP.BaseChance + M.DROP.PerLevel * level)
	if random:NextNumber() >= chance then return nil end
	local pool, weights, total = {}, {}, 0
	for _, def in ipairs(M.ITEMS) do
		if def.MinLevel <= level and def.Weight > 0 then
			local w = def.Weight * (1 + M.DROP.HardBias * def.MinLevel / level)
			table.insert(pool, def)
			table.insert(weights, w)
			total += w
		end
	end
	if total <= 0 then return nil end
	local pick = random:NextNumber() * total
	for i, def in ipairs(pool) do
		pick -= weights[i]
		if pick <= 0 then return def end
	end
	return pool[#pool]
end

--.. server time the boost ends for this player, or nil
function M.BoostUntil(player, boost)
	local info = M.BOOSTS[boost]
	local untilTime = info and tonumber(player:GetAttribute(info.Attr))
	if untilTime and untilTime > workspace:GetServerTimeNow() then return untilTime end
	return nil
end

function M.BoostMult(player, boost)
	local info = M.BOOSTS[boost]
	return (info and M.BoostUntil(player, boost)) and info.Mult or 1
end

function M.FormatTime(seconds)
	seconds = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

return M
