--[[
	HeadbandsCatalog  (ModuleScript, ReplicatedStorage.Modules)
	The 12 headbands sold at the lobby's "BUY YOUR TOOLS!" booth (user 2026-09-09). Shared by
	ServerScriptService.HeadbandService (prices, ownership, the worn Accessory) and by the shop
	UI (the card grid and the preview panel), so the numbers live in exactly one place.

	Each entry:
		Name         the collection name; also the Model name under ReplicatedStorage.Assets.Headbands
		DisplayName  what a player reads
		Tier         1..12; the shop's sort order
		Price        Cash; tier 1 is FREE so a new player always owns something
		Blurb        one line for the preview panel
		Color        the card's accent colour
		StrengthMult every bench-press rep is multiplied by this while the band is worn
		             (ServerStorage.GymService.StrengthPerRep); the shop shows it as "<N>x strength"

	PRICE LADDER: a half-decade curve -- the price multiplies by about 3.16 per tier (x10 every two
	tiers), 500 Cash at tier 2 climbing to 50M at tier 12, so the last band stays a long-term goal
	for a player who is selling cucumbers rather than a weekend's work.

	BOOST LADDER (user 2026-09-09): tier N gives (N + 1)x strength per rep -- 2x for the free Sweatband,
	3x for the Red Bandana ... 13x for the Champion Band. Bare-headed is 1x. Every band is on sale from
	the start; nothing is locked behind the tier below it.

	Use:
		local Catalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("HeadbandsCatalog"))
		for _, entry in ipairs(Catalog.List()) do ... end     --.. sorted by Tier, do not mutate
		Catalog.Get("GoldBand").Price
		Catalog.IsValid(name)
		Catalog.StrengthMultOf(name)                          --.. 1 for "" / unknown
		Catalog.ModelOf(name)                                 --.. nil while the Blender model is not in yet
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Config..--
local M = {}

M.ASSETS_FOLDER = "Assets" --.. ReplicatedStorage.Assets
M.MODELS_FOLDER = "Headbands" --.. ReplicatedStorage.Assets.Headbands.<Name>
M.DEFAULT = "Sweatband" --.. tier 1: granted to every profile on load, never bought
M.MAX_TIER = 12

--..The catalogue.. (tier order; prices are the half-decade ladder described above)--
local BANDS = {
	{Name = "Sweatband", DisplayName = "Sweatband", Tier = 1, StrengthMult = 2, Price = 0,
		Color = Color3.fromRGB(236, 240, 241),
		Blurb = "Cheap terry cloth. Every cucumber hauler starts here."},
	{Name = "RedBandana", DisplayName = "Red Bandana", Tier = 2, StrengthMult = 3, Price = 500,
		Color = Color3.fromRGB(214, 48, 49),
		Blurb = "Knotted tight at the back. Pure attitude, zero protection."},
	{Name = "CamoBand", DisplayName = "Camo Band", Tier = 3, StrengthMult = 4, Price = 1500,
		Color = Color3.fromRGB(106, 130, 70),
		Blurb = "Green on green. The cucumbers never see you coming."},
	{Name = "CucumberBand", DisplayName = "Cucumber Band", Tier = 4, StrengthMult = 5, Price = 5000,
		Color = Color3.fromRGB(125, 255, 95),
		Blurb = "A whole cucumber strapped to your forehead. Obviously."},
	{Name = "StrawBand", DisplayName = "Straw Band", Tier = 5, StrengthMult = 6, Price = 15000,
		Color = Color3.fromRGB(226, 190, 110),
		Blurb = "Woven from farm straw and held together by optimism."},
	{Name = "LeafCrown", DisplayName = "Leaf Crown", Tier = 6, StrengthMult = 7, Price = 50000,
		Color = Color3.fromRGB(80, 200, 120),
		Blurb = "Fresh vine leaves, awarded to the champion of the harvest."},
	{Name = "SteelBand", DisplayName = "Steel Band", Tier = 7, StrengthMult = 8, Price = 150000,
		Color = Color3.fromRGB(160, 172, 184),
		Blurb = "Riveted plate. Heavy, cold and impossible to ignore."},
	{Name = "CactusBand", DisplayName = "Cactus Band", Tier = 8, StrengthMult = 9, Price = 500000,
		Color = Color3.fromRGB(150, 180, 110),
		Blurb = "Desert spines the whole way round. Do not headbutt anything."},
	{Name = "FrostBand", DisplayName = "Frost Band", Tier = 9, StrengthMult = 10, Price = 1500000,
		Color = Color3.fromRGB(158, 231, 255),
		Blurb = "Carved from glacier ice that somehow never melts."},
	{Name = "GoldBand", DisplayName = "Gold Band", Tier = 10, StrengthMult = 11, Price = 5000000,
		Color = Color3.fromRGB(255, 200, 60),
		Blurb = "Solid gold, and badly hidden under all that sweat."},
	{Name = "LavaBand", DisplayName = "Lava Band", Tier = 11, StrengthMult = 12, Price = 15000000,
		Color = Color3.fromRGB(255, 110, 62),
		Blurb = "Still cooling. It hisses whenever it rains."},
	{Name = "ChampionBand", DisplayName = "Champion Band", Tier = 12, StrengthMult = 13, Price = 50000000,
		Color = Color3.fromRGB(170, 110, 255),
		Blurb = "The last band. Worn only by the greatest cucumber lifter alive."},
}

--..Variables..--
local ORDER = {} --.. BANDS sorted by Tier; handed straight back by List()
local BY_NAME = {}
do
	for _, entry in ipairs(BANDS) do
		table.insert(ORDER, entry)
		BY_NAME[entry.Name] = entry
	end
	table.sort(ORDER, function(a, b) return a.Tier < b.Tier end)
end

--..Functions..--

--.. every headband, cheapest tier first. Read only -- callers share this table.
function M.List()
	return ORDER
end

--.. the entry for a collection name, or nil
function M.Get(name)
	if type(name) ~= "string" then return nil end
	return BY_NAME[name]
end

function M.IsValid(name)
	return M.Get(name) ~= nil
end

function M.DisplayNameOf(name)
	local entry = M.Get(name)
	return entry and entry.DisplayName or tostring(name)
end

function M.PriceOf(name)
	local entry = M.Get(name)
	return entry and entry.Price or nil
end

--.. the bench-press multiplier a worn band gives: GymService.StrengthPerRep multiplies every rep by
--.. this. Tier N is (N + 1)x, and a bare head ("") or an unknown name is 1x -- never nil, never 0.
function M.StrengthMultOf(name)
	local entry = M.Get(name)
	local mult = entry and tonumber(entry.StrengthMult)
	if mult and mult > 0 then return mult end
	return 1
end

--.. where a band's artwork is expected to live (for warnings while the models are still in Blender)
function M.AssetPath(name)
	return ("ReplicatedStorage.%s.%s.%s"):format(M.ASSETS_FOLDER, M.MODELS_FOLDER, tostring(name))
end

--.. the Blender model, or nil if it has not been uploaded yet. Never yields, never errors:
--.. every caller must degrade gracefully while the artwork is missing.
function M.ModelOf(name)
	if not M.IsValid(name) then return nil end
	local assets = ReplicatedStorage:FindFirstChild(M.ASSETS_FOLDER)
	local folder = assets and assets:FindFirstChild(M.MODELS_FOLDER)
	local model = folder and folder:FindFirstChild(name)
	if model and (model:IsA("Model") or model:IsA("BasePart")) then return model end
	return nil
end

return M
