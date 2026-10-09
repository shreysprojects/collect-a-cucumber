--[[
	EggShop  (Script, ServerScriptService)
	Every physical egg on an egg stand (Map/Biomes/<zone>/Eggs/<stand>/<... Egg> Model) gets a
	ProximityPrompt. Triggering it buys the egg for its price in Cash (DataService) and hands the
	player a Tool built from THAT egg model, equipped straight into the hand.

	  * price: EGG_PRICE for every egg; a "Price" attribute on the stand or egg model overrides it
	  * STOCK (2026-09-07): each stand gets a fresh stock every in-game day: first the biome's
	    chance of having ANY stock that day (STOCK_TABLE.Chance: Spawn always, Narmek 2%), then a
	    count in the biome's Min..Max (attributes StockChance / StockRangeMin / StockRangeMax on
	    the stand or egg override), all from a random generator seeded by the SHARED day number
	    (DayNightCycle's real-time calendar) and the egg name, so every server shows the same
	    stock and the rare stands read "Sold out!" most days. Live attributes Stock / StockMax on the egg model, Stock on the
	    prompt; an overhead "X left!" / "Sold out!" billboard (FredokaOne, sized in studs like the
	    rest of the overhead UI) shows the count; the prompt is disabled while sold out; the
	    workspace attribute DayNumber changing (next day) re-rolls everything.
	  * EVERY BOUGHT EGG IS ROLLED (2026-09-07): a weight from KG_MIN (2) to KG_MAX (100,000) on
	    a log ladder the buyer's Strength opens up like the walkspeed curve
	    (StrengthProgression: log10(1 + strength / 100)): reach = that / log10(1 + STRENGTH_FOR_MAX
	    / 100), floored at REACH_FLOOR, and kg = KG_MIN x 10^(decades x reach x u^KG_SKEW) with u
	    random -- weak players only ever get light eggs, strong players get a CHANCE (never a
	    guarantee: the roll is skewed toward the bottom) at huge ones. The size follows the weight
	    on a log scale (SIZE_MIN at 2 kg, + SIZE_PER_DECADE per x10, capped SIZE_MAX): a 100,000
	    kg egg is about 4 x the stand egg. Material (Golden / Diamond) and mutations come from
	    CucumberMutations (MUTATION_CHANCE, then 1..4). The tool is built per purchase: the held
	    egg is scaled by the size (capped at HAND_SCALE_MAX in the hand) and painted with
	    CucumberMutations.ApplyLook; its name reads "<Golden> <NEON> <Egg> Egg (12.5K kg)".
	  * tool: CanBeDropped=false, attributes EggName / Price / Kg / Scale / Material / Mutations /
	    DisplayName, tag "EggTool". EggPlacement places it with the full size + look.
	  * prompts carry attributes EggName / Price / Stock and the tag "EggShopPrompt";
	    StarterPlayerScripts.EggShopClient shows the "not enough cash" toast.
	  * Studio dev hook: workspace:SetAttribute("EggShopDev", "buy:<EggName>") buys one for the
	    first player, "reset" re-rolls today's stock.
]]

--..Services..--
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--..Modules..--
local DataService = require(ServerStorage:WaitForChild("DataService"))
local CucumberMutations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CucumberMutations"))
local NumberAbbrev = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberAbbrev")) -- "$12B" on the prompts (2026-09-23)

--..Config..--
local EGG_PRICE = 100 -- fallback for an egg name PRICE_BY_EGG does not know
--.. 2026-09-23 economy: Cash per egg by the stand's name (EggNameOf: the stand's label); a "Price" attribute on
--.. the stand or egg model still overrides. About 3-5 % of the biome's expected cash at the time.
local PRICE_BY_EGG = {
	Basic = 100, Desert = 1000, Samurai = 12000, Farm = 200000,
	Frozen = 3000000, Ocean = 50000000, Lava = 800000000, Narmek = 12000000000,
}
--.. daily stock per biome index ("01 Spawn" = 1 ... "08 Narmek" = 8): Chance = the odds the stand has
--.. ANY stock that day (otherwise "Sold out!" all day), Min..Max = how many when it does. Harder biomes
--.. are rarer; Narmek shows a single egg about one day in fifty. (2026-09-07: "more sold out")
local STOCK_TABLE = {
	[1] = {Chance = 1.00, Min = 4, Max = 8},
	[2] = {Chance = 0.85, Min = 3, Max = 6},
	[3] = {Chance = 0.70, Min = 2, Max = 5},
	[4] = {Chance = 0.50, Min = 1, Max = 4},
	[5] = {Chance = 0.35, Min = 1, Max = 3},
	[6] = {Chance = 0.20, Min = 1, Max = 2},
	[7] = {Chance = 0.08, Min = 1, Max = 2},
	[8] = {Chance = 0.02, Min = 1, Max = 1},
	[9] = {Chance = 0.02, Min = 1, Max = 1},
	[10] = {Chance = 0.01, Min = 1, Max = 1},
}
local STOCK_DEFAULT = {Chance = 0.5, Min = 1, Max = 4}
--.. DayNightCycle's shared calendar, used only until it stamps workspace.DayNumber (keep in step)
local CYCLE_EPOCH = 1788652800
local DAY_SECONDS_DEFAULT, NIGHT_SECONDS_DEFAULT = 180, 10
local MUTATION_CHANCE = 0.08 -- chance a bought egg mutates at all (then 1..4 mutations with the cucumber odds); 8% = the cucumbers' own mutated-at-all odds (was 0.35 until 2026-09-07)
local KG_MIN, KG_MAX = 2, 100000 -- the weight ladder
local KG_SKEW = 2.2 -- u^KG_SKEW: the roll piles up at the light end; big eggs are a chance, not a promise
local STRENGTH_FOR_MAX = 10000000 -- Strength at which the whole ladder is reachable ("Champion" in StrengthProgression)
local REACH_FLOOR = 0.12 -- fraction of the ladder a brand-new player can reach (about 7 kg)
local SIZE_MIN = 0.8 -- egg scale at KG_MIN
local SIZE_PER_DECADE = 0.7 -- + per x10 kg
local SIZE_MAX = 4.2 -- placed-egg scale cap (100,000 kg = about 4.1)
local HAND_SCALE_MAX = 3 -- the egg in the hand stops growing here (the placed egg uses the full size)
local HAND_EGG_HEIGHT = 2.2 -- studs; the held egg is scaled to this height (x the rolled size)
local GRIP = CFrame.new(0, -0.9, 0.25) -- identity rotation keeps the egg upright in the R15 tool pose; centre 0.9 above the palm, 0.25 forward
local PROMPT_DISTANCE = 12
local PROMPT_HOLD = 0.35 -- seconds; a short hold so a stray key press never spends cash
local OVERHEAD_SIZE = UDim2.fromScale(7, 1.8) -- studs (scale units on a BillboardGui = studs)
local OVERHEAD_LIFT = 0.9 -- studs of air between the egg's top and the label's bottom edge
local OVERHEAD_MAX_DISTANCE = 90
local OVERHEAD_FONT = Enum.Font.FredokaOne -- the font most of the game's UI uses
local IN_STOCK_COLOR = Color3.fromRGB(150, 255, 150)
local LOW_STOCK_COLOR = Color3.fromRGB(255, 225, 110)
local SOLD_OUT_COLOR = Color3.fromRGB(255, 110, 110)
local BIOMES = workspace:WaitForChild("Map"):WaitForChild("Biomes")

--..Variables..--
local Eggs = {} -- [eggName] = {Name, Model, Stand, Host, BiomeIndex, Prompt, Label, Stock, Max}
local Busy = {} -- [player] = true while a purchase is being processed
local StockDay = nil -- the day number the current stock was rolled for

--..Functions..--
--.. the stand's own name label (SurfaceGui text that is not "EGG"); the "X left!" stock billboard
--.. added below is skipped, and the result is stamped on the stand (attribute EggName) so
--.. EggPlacement reads the same name whatever the script order
local function EggNameOf(stand)
	local stamped = stand:GetAttribute("EggName")
	if type(stamped) == "string" and stamped ~= "" then return stamped end
	for _, d in ipairs(stand:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text ~= "" and d.Text:upper() ~= "EGG" and not d:FindFirstAncestorWhichIsA("BillboardGui") then
			return d.Text
		end
	end
	return (stand.Name:gsub("%s*Egg%s*Stand$", ""):gsub("%s*Egg$", ""))
end

local function AttrOf(entry, name)
	local v = entry.Model:GetAttribute(name)
	if v == nil then v = entry.Stand:GetAttribute(name) end
	return v
end

local function PriceOf(eggName)
	local entry = Eggs[eggName]
	return tonumber(entry and AttrOf(entry, "Price")) or PRICE_BY_EGG[eggName] or EGG_PRICE
end

--.. "Buy (12B Cash)": the prompt's action text (NumberAbbrev: K / M / B / T ...)
local function BuyText(eggName)
	return ("Buy (%s Cash)"):format(NumberAbbrev.Abbrev(PriceOf(eggName)))
end

local function LargestPart(model)
	local best, bestVolume
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if not best or v > bestVolume then best, bestVolume = d, v end
		end
	end
	return best
end

local function FormatKg(kg)
	if kg < 10 then return ("%.1f kg"):format(kg) end
	if kg < 1000 then return ("%d kg"):format(math.floor(kg + 0.5)) end
	local k = kg / 1000
	local s = k >= 100 and ("%d"):format(math.floor(k + 0.5)) or ("%.1f"):format(k):gsub("%.0$", "")
	return s .. "K kg"
end

--..Stock (same on every server: rolled from the shared day number + the egg name)..--
local function CurrentDay()
	local d = workspace:GetAttribute("DayNumber")
	if typeof(d) == "number" then return math.floor(d) end
	local cycleScript = ServerScriptService:FindFirstChild("DayNightCycle")
	local daySeconds = tonumber(cycleScript and cycleScript:GetAttribute("DayDurationSeconds")) or DAY_SECONDS_DEFAULT
	local nightSeconds = tonumber(cycleScript and cycleScript:GetAttribute("NightDurationSeconds")) or NIGHT_SECONDS_DEFAULT
	return math.floor((workspace:GetServerTimeNow() - CYCLE_EPOCH) / (daySeconds + nightSeconds)) + 1
end

local function NameHash(s)
	local h = 7
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
	return h
end

--.. override attributes are StockChance (0..1), StockRangeMin / StockRangeMax (NOT StockMax: that is the live count)
local function StockRuleOf(entry)
	local rule = STOCK_TABLE[entry.BiomeIndex] or STOCK_DEFAULT
	local chance = tonumber(AttrOf(entry, "StockChance")) or rule.Chance
	local lo = tonumber(AttrOf(entry, "StockRangeMin")) or rule.Min
	local hi = tonumber(AttrOf(entry, "StockRangeMax")) or rule.Max
	lo, hi = math.max(0, math.floor(lo)), math.max(0, math.floor(hi))
	if hi < lo then hi = lo end
	return math.clamp(chance, 0, 1), lo, hi
end

--.. the same day + egg name always gives the same answer, on every server
local function RollStock(entry, day)
	local chance, lo, hi = StockRuleOf(entry)
	local rng = Random.new(day * 1000003 + NameHash(entry.Name))
	if rng:NextNumber() >= chance then return 0 end
	return rng:NextInteger(lo, hi)
end

local function RefreshStockUI(entry)
	local n, max = entry.Stock, entry.Max
	entry.Model:SetAttribute("Stock", n)
	entry.Model:SetAttribute("StockMax", max)
	if entry.Prompt then
		entry.Prompt:SetAttribute("Stock", n)
		entry.Prompt.Enabled = n > 0
		entry.Prompt.ActionText = n > 0 and BuyText(entry.Name) or "Sold out"
	end
	if entry.Label then
		if n <= 0 then
			entry.Label.Text = "Sold out!"
			entry.Label.TextColor3 = SOLD_OUT_COLOR
		else
			entry.Label.Text = ("%d left!"):format(n)
			entry.Label.TextColor3 = n == 1 and LOW_STOCK_COLOR or IN_STOCK_COLOR
		end
	end
end

local function SetStock(entry, n)
	entry.Stock = math.max(0, math.floor(n))
	RefreshStockUI(entry)
end

local function ResetStock(entry, day)
	entry.Max = RollStock(entry, day)
	SetStock(entry, entry.Max)
end

local function ResetAll()
	local day = CurrentDay()
	StockDay = day
	for _, entry in pairs(Eggs) do ResetStock(entry, day) end
end

--.. "X left!" over the egg: a stud-sized billboard (shrinks with distance like the plot badges)
local function BuildOverhead(entry)
	local host = entry.Host
	local old = host:FindFirstChild("StockLabel")
	if old then old:Destroy() end
	local gui = Instance.new("BillboardGui")
	gui.Name = "StockLabel"
	gui.Size = OVERHEAD_SIZE
	gui.Adornee = host
	gui.AlwaysOnTop = true -- the shop label stays on top (2026-09-07: only the placed-egg timer is not AlwaysOnTop)
	gui.MaxDistance = OVERHEAD_MAX_DISTANCE
	gui.ResetOnSpawn = false
	gui.ExtentsOffsetWorldSpace = Vector3.new(0, 1, 0) -- the egg part's top
	gui.StudsOffsetWorldSpace = Vector3.new(0, OVERHEAD_LIFT + OVERHEAD_SIZE.Y.Scale * 0.5, 0) -- the billboard is centred: lift by half its height
	local label = Instance.new("TextLabel")
	label.Name = "Count"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = OVERHEAD_FONT
	label.TextScaled = true
	label.TextColor3 = IN_STOCK_COLOR
	label.Text = ""
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 24, 40)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	gui.Parent = host
	entry.Label = label
end

--..Rolls..--
--.. how far up the kg ladder this player can reach (0..1), the walkspeed curve's log10(1 + strength / 100)
local function Reach(strength)
	local s = tonumber(strength) or 0
	if s ~= s or s < 0 then s = 0 end
	local r = math.log10(1 + s / 100) / math.log10(1 + STRENGTH_FOR_MAX / 100)
	return math.clamp(r, REACH_FLOOR, 1)
end

local function SizeOf(kg)
	return math.clamp(SIZE_MIN + SIZE_PER_DECADE * math.log10(kg / KG_MIN), SIZE_MIN, SIZE_MAX)
end

local function RollEgg(eggName, player)
	local strength = DataService.Get(player, "Strength") or 0
	local decades = math.log10(KG_MAX / KG_MIN)
	local u = math.random() ^ KG_SKEW -- skewed toward 0: most eggs stay light, big ones are rare
	local kg = KG_MIN * 10 ^ (decades * Reach(strength) * u)
	kg = math.clamp(kg, KG_MIN, KG_MAX)
	kg = kg < 100 and math.round(kg * 10) / 10 or math.round(kg)
	local scale = SizeOf(kg)
	local material = CucumberMutations.RollMaterial()
	local mutations = {}
	if math.random() < MUTATION_CHANCE then
		mutations = CucumberMutations.RollMutations(nil, CucumberMutations.RollCountAtLeastOne())
	end
	return {Kg = kg, Scale = scale, Material = material, Mutations = mutations, Strength = strength}
end

--..Tool (built per purchase: size + look are part of the egg)..--
local function BuildTool(entry, roll)
	local eggName = entry.Name
	local display = CucumberMutations.DisplayName(eggName .. " Egg", roll.Material, roll.Mutations)
	local tool = Instance.new("Tool")
	tool.Name = ("%s (%s)"):format(display, FormatKg(roll.Kg))
	tool.ToolTip = tool.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = GRIP
	tool:SetAttribute("EggName", eggName)
	tool:SetAttribute("DisplayName", display)
	tool:SetAttribute("Kg", roll.Kg)
	tool:SetAttribute("Scale", roll.Scale)
	tool:SetAttribute("Material", roll.Material or "")
	tool:SetAttribute("Mutations", CucumberMutations.Join(roll.Mutations))
	CollectionService:AddTag(tool, "EggTool")

	local egg = entry.Model:Clone()
	egg.Name = "Egg"
	for _, d in ipairs(egg:GetDescendants()) do
		if d:IsA("ProximityPrompt") or d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") then d:Destroy() end
	end
	local handScale = math.min(roll.Scale, HAND_SCALE_MAX)
	local _, size = egg:GetBoundingBox()
	if size.Y > 0 then egg:ScaleTo(egg:GetScale() * HAND_EGG_HEIGHT * handScale / size.Y) end
	local cf = egg:GetBoundingBox()

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 0.6, 0.6)
	handle.CFrame = CFrame.new(cf.Position) -- upright, at the egg's centre
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Anchored = false
	handle.Parent = tool

	for _, d in ipairs(egg:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = d
			weld.Parent = d
		end
	end
	CucumberMutations.ApplyLook(egg, roll.Material, roll.Mutations, {ParticleScale = 0.6})
	egg.Parent = tool
	return tool
end

local function Purchase(player, eggName)
	if Busy[player] then return false, "busy" end
	local entry = Eggs[eggName]
	if not entry then return false, "unknown egg" end
	if entry.Stock <= 0 then return false, "sold out" end
	Busy[player] = true
	local bought = false
	local ok, err = pcall(function()
		local price = PriceOf(eggName)
		local cash = DataService.Get(player, "Cash")
		if cash == nil then return end -- data still loading
		if cash < price then return end -- client shows the toast
		if entry.Stock <= 0 then return end
		DataService.Increment(player, "Cash", -price)
		SetStock(entry, entry.Stock - 1)
		local tool = BuildTool(entry, RollEgg(eggName, player))
		tool:SetAttribute("Price", price)
		tool.Parent = player:WaitForChild("Backpack", 5) or player
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid:EquipTool(tool)
		end
		bought = true
	end)
	Busy[player] = nil
	if not ok then warn("[EggShop] purchase failed for " .. player.Name .. ": " .. tostring(err)) end
	return ok and bought, err
end

local function AddPrompt(entry)
	local host = entry.Host
	local old = host:FindFirstChild("BuyPrompt")
	if old then old:Destroy() end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ObjectText = entry.Name .. " Egg"
	prompt.ActionText = BuyText(entry.Name)
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.HoldDuration = PROMPT_HOLD
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute("EggName", entry.Name)
	prompt:SetAttribute("Price", PriceOf(entry.Name))
	CollectionService:AddTag(prompt, "EggShopPrompt")
	prompt.Triggered:Connect(function(player)
		Purchase(player, entry.Name)
	end)
	prompt.Parent = host
	entry.Prompt = prompt
	return prompt
end

--..Setup..--
for _, biome in ipairs(BIOMES:GetChildren()) do
	local eggsFolder = biome:FindFirstChild("Eggs")
	if eggsFolder then
		local biomeIndex = tonumber(biome.Name:match("^(%d+)"))
		for _, stand in ipairs(eggsFolder:GetChildren()) do
			local eggModel
			for _, c in ipairs(stand:GetChildren()) do
				if c:IsA("Model") and c.Name:find("Egg") then eggModel = c break end
			end
			if eggModel then
				local eggName = EggNameOf(stand)
				stand:SetAttribute("EggName", eggName) -- EggPlacement reads this back
				local host = LargestPart(eggModel)
				if Eggs[eggName] then
					warn(("[EggShop] duplicate egg name %s (%s)"):format(eggName, stand:GetFullName()))
				elseif not host then
					warn(("[EggShop] %s has no parts"):format(stand:GetFullName()))
				else
					local entry = {Name = eggName, Model = eggModel, Stand = stand, Host = host, BiomeIndex = biomeIndex, Stock = 0, Max = 0}
					Eggs[eggName] = entry
					BuildOverhead(entry)
					AddPrompt(entry)
				end
			end
		end
	end
end
ResetAll()

--.. new in-game day (DayNightCycle stamps DayNumber when a day starts): re-roll today's stock
workspace:GetAttributeChangedSignal("DayNumber"):Connect(function()
	if CurrentDay() ~= StockDay then ResetAll() end
end)

Players.PlayerRemoving:Connect(function(player) Busy[player] = nil end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("EggShopDev"):Connect(function()
		local cmd = workspace:GetAttribute("EggShopDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		workspace:SetAttribute("EggShopDev", nil)
		if cmd == "reset" then
			ResetAll()
			print("[EggShop] dev: re-rolled today's stock")
			return
		end
		local eggName = cmd:match("^buy:(.+)$")
		local player = Players:GetPlayers()[1]
		if eggName and player then
			local ok, err = Purchase(player, eggName)
			print(("[EggShop] dev: buy %s for %s -> %s %s"):format(eggName, player.Name, tostring(ok), tostring(err or "")))
		end
	end)
end

local names = {}
for name in pairs(Eggs) do names[#names + 1] = ("%s x%d"):format(name, Eggs[name].Max) end
table.sort(names)
print(("[EggShop] %d eggs ready for day %s: %s (prices Basic %s .. Narmek %s, fallback %d)"):format(#names, tostring(StockDay), table.concat(names, ", "), NumberAbbrev.Abbrev(PRICE_BY_EGG.Basic), NumberAbbrev.Abbrev(PRICE_BY_EGG.Narmek), EGG_PRICE))