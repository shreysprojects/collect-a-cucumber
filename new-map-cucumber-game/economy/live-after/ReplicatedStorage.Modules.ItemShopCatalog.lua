--[[
	ItemShopCatalog  (ModuleScript, ReplicatedStorage.Modules)  2026-09-23
	The lobby ITEM SHOP: the potion / boost cart sells the nine drop items (ItemsCatalog) for Cash,
	Grow-a-Garden style - one shared stock per SERVER that restocks every RESTOCK_SECONDS, and every
	item is a lottery: at each restock it is in stock with probability 1 / Chance ("1 in 100" ...
	"1 in 25000", shown under its picture), with Stock.Min .. Stock.Max units when it is. User
	2026-09-23: "each boost very rare ... some boosts [1 in 100] then other stuff like [1 in 10000+]".

	Every number lives here; ItemShopService (server) and ItemShopController (client) read it.

	  ITEMS  ordered list of {Key, Price, Chance, Stock = {Min, Max}, Type}
	    Key     an ItemsCatalog key (name / rarity / description / model come from there)
	    Price   Cash per unit (DataService "Cash")
	    Chance  1 in Chance per restock that the item is in stock at all
	    Stock   units on the shelf when it is in stock (uniform integer)
	    Type    the small caption under the name ("POTION", "UTILITY", "SEED", "EGG", "TOKEN")
	  RESTOCK_SECONDS  seconds between restocks (the shop UI counts down to the next one)
	  DEV_CHANCE_DIV   Studio only: divides every Chance so a playtest can see stock (1 = live odds)
]]
local RunService = game:GetService("RunService")

local M = {}

M.RESTOCK_SECONDS = 300
--.. 2026-09-23 (economy): the buyer pays Price x PRICE_LEVEL_STEP^(threat level - 1) (ZombieAPI.ThreatLevel = the biome
--.. their base is worth); ItemShopService publishes the multiplier as the player attribute ItemShopPriceMult
M.PRICE_LEVEL_STEP = 4

M.ITEMS = {
	{Key = "SpeedPotion", Price = 2500, Chance = 100, Stock = {Min = 3, Max = 12}, Type = "POTION"},
	{Key = "StrengthPotion", Price = 5000, Chance = 100, Stock = {Min = 2, Max = 8}, Type = "POTION"},
	{Key = "CashPotion", Price = 7500, Chance = 150, Stock = {Min = 2, Max = 6}, Type = "POTION"},
	{Key = "WarpPearl", Price = 15000, Chance = 250, Stock = {Min = 1, Max = 5}, Type = "UTILITY"},
	{Key = "HolyWater", Price = 25000, Chance = 500, Stock = {Min = 1, Max = 4}, Type = "UTILITY"},
	{Key = "GoldenSeed", Price = 50000, Chance = 5000, Stock = {Min = 1, Max = 2}, Type = "SEED"},
	{Key = "VoidSeed", Price = 100000, Chance = 25000, Stock = {Min = 1, Max = 1}, Type = "SEED"},
	{Key = "ZombieEgg", Price = 250000, Chance = 10000, Stock = {Min = 1, Max = 1}, Type = "EGG"},
	{Key = "RedemptionToken", Price = 500000, Chance = 1000, Stock = {Min = 1, Max = 2}, Type = "TOKEN"},
}

--.. Studio playtests would never see stock at the live odds; the server divides every Chance by this
--.. in Studio only (1 = the live odds; the ItemShopDev hook can force stock regardless).
M.DEV_CHANCE_DIV = RunService:IsStudio() and 1 or 1

M.MAX_PER_PURCHASE = 1 -- one unit per click (the button is spammable, stock is the limit)
M.ACTION_COOLDOWN = 0.25 -- seconds between two purchases per player

local ByKey = {}
for i, def in ipairs(M.ITEMS) do
	def.Order = i
	ByKey[def.Key] = def
end

function M.Get(key)
	return type(key) == "string" and ByKey[key] or nil
end

--.. "1 in 100" / "1 in 25K" for the label under the picture (Chance is an integer)
function M.ChanceText(chance)
	chance = math.max(1, math.floor(tonumber(chance) or 1))
	local text
	if chance >= 1000000 and chance % 100000 == 0 then
		text = string.format("%gM", chance / 1000000)
	elseif chance >= 1000 and chance % 100 == 0 then
		text = string.format("%gK", chance / 1000)
	else
		text = tostring(chance)
	end
	return "1 in " .. text
end

--.. "$2.5K" / "$500K" / "$1.2M" in the HUD's cash style (green text, no icon)
function M.PriceText(price)
	price = math.max(0, math.floor(tonumber(price) or 0))
	local function trim(n) -- one decimal, ".0" dropped
		local s = string.format("%.1f", n)
		return s:gsub("%.0$", "")
	end
	if price >= 1e12 then return "$" .. trim(price / 1e12) .. "T" end
	if price >= 1e9 then return "$" .. trim(price / 1e9) .. "B" end
	if price >= 1e6 then return "$" .. trim(price / 1e6) .. "M" end
	if price >= 1e3 then return "$" .. trim(price / 1e3) .. "K" end
	return "$" .. tostring(price)
end

return M
