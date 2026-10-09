--[[
	GymService  (ModuleScript, ServerStorage)
	Server logic behind the gym platform's bench upgrade board and the bench reps.
	(The QUESTS board and quest system were removed on 2026-09-06.)

	Data (DataService profile):
		Strength            -- grows by StrengthPerRep per rep
		Upgrades = {BenchPress = 1}
	Bench upgrade (ONE upgrade with two effects, sold on the BenchUpgrade board):
		level L -> strength per rep 2^(L-1) x the worn headband's StrengthMult (HeadbandsCatalog: tier N
		           is (N+1)x, bare-headed 1x; HeadbandService keeps data.Headbands.Equipped and calls
		           GymService.Refresh on every equip)  (player attribute StrengthPerRep, BenchServer)
		        -> rep animation speed REP_SPEEDS[L]  (attribute RepSpeed, BenchLieClient)
		        -> bench model tier clamp(L, 1, MAX_BENCH_TIER)  (attribute BenchTier, BenchTierClient)
		Cash: BENCH cost per level below. Robux: Developer Product BENCH_PRODUCT_ID grants one level
		(create the product in the Creator Dashboard, paste its id below; while it is 0 the Robux
		button shows BENCH_ROBUX_PRICE and answers "not set up yet").
		The old "Faster reps" upgrade was merged into this one on 2026-09-06; old profiles may still
		carry Upgrades.FasterReps (and Quests), which are ignored.
	Config below: UPGRADES (cost per level, max level, effect text).
	Plots: every plot carries attributes BenchLevel / BenchTier / BenchCost (Cash to the next level, 0 at
	max) / BenchMax for its owner (SyncPlot: refreshed on Owner changes, profile load and every buy),
	so the per-plot BenchUpgrade boards (BenchBoardClient) and plot benches (BenchTierClient) can be
	shown by everyone. An unowned plot reads level 1.

	Remotes (ReplicatedStorage.Remotes):
		GymBoardState  RemoteEvent  server -> client: full board state table
		    {Cash, Strength, Upgrades = {BenchPress = {Level, Cost, Max, Effect}},
		     Bench = {ProductId, RobuxPrice}}
		GymBoardAction RemoteFunction client -> server: ("Buy"|"Robux"|"State", id) -> ok, message

	API: GymService.Start(), GymService.AwardRep(player) -> strength gained,
	     GymService.Buy(player, id), GymService.Robux(player, id),
	     GymService.GrantBenchLevel(player) -> ok (used by the Robux receipt), GymService.Push(player),
	     GymService.Refresh(player) (attributes + board again after an outside change, e.g. a headband equip),
	     GymService.RegisterProduct(productId, handler(player, receipt) -> granted) for other products
	     (this module owns MarketplaceService.ProcessReceipt and dispatches by ProductId)
	Studio dev hook: workspace:SetAttribute("GymDev", "<playerName or bench>:<level>") sets that player's bench level
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local DataService = require(ServerStorage:WaitForChild("DataService"))
local HeadbandsCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("HeadbandsCatalog")) -- StrengthMult per band

local GymService = {}

--..Config..--
GymService.REP_SPEEDS = {1, 2, 4, 7, 11, 18, 27, 32} -- indexed by bench tier
local function RepSpeedForLevel(level)
	return GymService.REP_SPEEDS[math.clamp(level, 1, #GymService.REP_SPEEDS)]
end
GymService.MAX_BENCH_TIER = 8 -- themed bench models (Starter, Iron, Gold, Frost, Inferno, Cosmic, Celestial, VoidEmperor), one per level
GymService.BENCH_PRODUCT_ID = 0 -- Developer Product id that grants one bench level for Robux (0 = not set up yet)
GymService.BENCH_ROBUX_PRICE = 625 -- shown on the Robux button until the product's real price can be read
GymService.UPGRADES = {
	{Id = "BenchPress", Name = "Bench press", Max = GymService.MAX_BENCH_TIER, Cost = function(level) return 100 * 2 ^ (level - 1) end, -- max level = last bench tier
		Effect = function(level) return ("+%d per rep, %dx speed"):format(2 ^ (level - 1), RepSpeedForLevel(level)) end},
}

--..Remotes..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local function remote(className, name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
local StateEvent = remote("RemoteEvent", "GymBoardState")
local ActionFunction = remote("RemoteFunction", "GymBoardAction")

--..State..--
local RobuxPrice = GymService.BENCH_ROBUX_PRICE
local Products = {} -- [productId] = function(player, receipt) -> true when granted

--..Helpers..--
local function UpgradeDef(id)
	for _, u in ipairs(GymService.UPGRADES) do if u.Id == id then return u end end
end
local function Level(data, id)
	return math.max(1, math.floor(tonumber(data.Upgrades and data.Upgrades[id]) or 1))
end

--.. the worn headband multiplies every rep (HeadbandService writes data.Headbands.Equipped; 1x bare-headed)
function GymService.HeadbandMultiplier(data)
	local headbands = type(data.Headbands) == "table" and data.Headbands or nil
	return HeadbandsCatalog.StrengthMultOf(headbands and headbands.Equipped)
end

function GymService.StrengthPerRep(data)
	return 2 ^ (Level(data, "BenchPress") - 1) * GymService.HeadbandMultiplier(data)
end

function GymService.RepSpeed(data)
	return RepSpeedForLevel(Level(data, "BenchPress"))
end

function GymService.BenchTier(data)
	return math.clamp(Level(data, "BenchPress"), 1, GymService.MAX_BENCH_TIER)
end

local function PlotsFolder()
	local map = workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	return lobby and lobby:FindFirstChild("Plots")
end

local function PlotOf(player)
	local plots = PlotsFolder()
	if not plots then return nil end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

--.. the plot's bench attributes for its owner (level 1 while nobody owns it)
function GymService.SyncPlot(plot)
	local def = UpgradeDef("BenchPress")
	local userId = plot:GetAttribute("Owner")
	local player = userId and Players:GetPlayerByUserId(userId)
	local data = player and DataService.GetData(player)
	local level = data and Level(data, "BenchPress") or 1
	plot:SetAttribute("BenchLevel", level)
	plot:SetAttribute("BenchTier", data and GymService.BenchTier(data) or 1)
	plot:SetAttribute("BenchCost", level < def.Max and def.Cost(level) or 0)
	plot:SetAttribute("BenchMax", def.Max)
end

--.. player attributes the clients read (BenchLieClient uses RepSpeed for the clip speed,
--.. BenchTierClient shows the bench model for BenchTier)
local function ApplyEffects(player)
	local data = DataService.GetData(player)
	if not data then return end
	player:SetAttribute("RepSpeed", GymService.RepSpeed(data))
	player:SetAttribute("StrengthPerRep", GymService.StrengthPerRep(data))
	player:SetAttribute("BenchTier", GymService.BenchTier(data))
	local plot = PlotOf(player)
	if plot then GymService.SyncPlot(plot) end
end

--.. attributes and board again after something outside this module changed the per-rep maths
--.. (HeadbandService on every equip / unequip / first buy)
function GymService.Refresh(player)
	ApplyEffects(player)
	GymService.Push(player)
end

function GymService.State(player)
	local data = DataService.GetData(player)
	if not data then return nil end
	local state = {Cash = data.Cash or 0, Strength = data.Strength or 0, Upgrades = {},
		Bench = {ProductId = GymService.BENCH_PRODUCT_ID, RobuxPrice = RobuxPrice}}
	for _, u in ipairs(GymService.UPGRADES) do
		local level = Level(data, u.Id)
		state.Upgrades[u.Id] = {Level = level, Cost = level < u.Max and u.Cost(level) or nil, Max = u.Max, Effect = u.Effect(level)}
	end
	return state
end

function GymService.Push(player)
	local state = GymService.State(player)
	if state then StateEvent:FireClient(player, state) end
end

--..Actions..--
function GymService.AwardRep(player, multiplier)
	local data = DataService.GetData(player)
	if not data then return nil end
	-- Multiplier is supplied only by trusted server callers (bonus click = server-selected multiplier).
	local gain = GymService.StrengthPerRep(data) * (multiplier or 1)
	--.. 2026-09-23 (items): a Strength Potion doubles every rep while StrengthBoostUntil (server time) is ahead
	local boostUntil = tonumber(player:GetAttribute("StrengthBoostUntil"))
	if boostUntil and boostUntil > workspace:GetServerTimeNow() then gain *= 2 end
	DataService.Increment(player, "Strength", gain)
	GymService.Push(player)
	return gain
end

local function RaiseLevel(player, def, data)
	local level = Level(data, def.Id)
	data.Upgrades[def.Id] = level + 1
	DataService.RequestSave(player)
	ApplyEffects(player)
	GymService.Push(player)
	return level + 1
end

function GymService.Buy(player, id)
	local def = UpgradeDef(id)
	local data = DataService.GetData(player)
	if not def or not data then return false, "Not available" end
	local level = Level(data, id)
	if level >= def.Max then return false, "Max level" end
	local cost = def.Cost(level)
	if (data.Cash or 0) < cost then return false, ("Need %d Cash"):format(cost) end
	DataService.Increment(player, "Cash", -cost)
	local newLevel = RaiseLevel(player, def, data)
	return true, ("%s Lv. %d (%s)"):format(def.Name, newLevel, def.Effect(newLevel))
end

--.. one bench level without paying Cash (the Robux product)
function GymService.GrantBenchLevel(player)
	local def = UpgradeDef("BenchPress")
	local data = DataService.GetData(player)
	if not def or not data then return false end
	if Level(data, def.Id) >= def.Max then return false end
	RaiseLevel(player, def, data)
	return true
end

function GymService.Robux(player, id)
	if id ~= "BenchPress" then return false, "Not available" end
	if GymService.BENCH_PRODUCT_ID == 0 then return false, "Robux purchase is not set up yet" end
	local data = DataService.GetData(player)
	if not data then return false, "Not available" end
	if Level(data, "BenchPress") >= UpgradeDef("BenchPress").Max then return false, "Max level" end
	local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, GymService.BENCH_PRODUCT_ID)
	if not ok then
		warn("[GymService] PromptProductPurchase: " .. tostring(err))
		return false, "Could not open the Robux purchase"
	end
	return true, "Opening the Robux purchase"
end

--..Developer products..--
function GymService.RegisterProduct(productId, handler)
	Products[productId] = handler
end

local function ProcessReceipt(receipt)
	local handler = Products[receipt.ProductId]
	if not handler then
		warn(("[GymService] no handler for product %d; receipt kept for later"):format(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local ok, granted = pcall(handler, player, receipt)
	if not ok then warn("[GymService] product handler: " .. tostring(granted)) end
	if ok and granted then return Enum.ProductPurchaseDecision.PurchaseGranted end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

--..Start..--
local started = false
function GymService.Start()
	if started then return GymService end
	started = true
	ActionFunction.OnServerInvoke = function(player, kind, id)
		if type(kind) ~= "string" or type(id) ~= "string" then return false, "Bad request" end
		if kind == "Buy" then return GymService.Buy(player, id) end
		if kind == "Robux" then return GymService.Robux(player, id) end
		if kind == "State" then GymService.Push(player) return true end
		return false, "Unknown action"
	end
	DataService.OnProfileLoaded(function(player)
		ApplyEffects(player)
		GymService.Push(player)
	end)
	MarketplaceService.ProcessReceipt = ProcessReceipt
	--.. keep every plot's bench attributes fresh for its owner
	task.spawn(function()
		local plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
		for _, plot in ipairs(plots:GetChildren()) do
			if plot:IsA("BasePart") then
				plot:GetAttributeChangedSignal("Owner"):Connect(function() GymService.SyncPlot(plot) end)
				GymService.SyncPlot(plot)
			end
		end
	end)
	if GymService.BENCH_PRODUCT_ID > 0 then
		GymService.RegisterProduct(GymService.BENCH_PRODUCT_ID, function(player) return GymService.GrantBenchLevel(player) end)
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, GymService.BENCH_PRODUCT_ID, Enum.InfoType.Product)
			if ok and type(info) == "table" and tonumber(info.PriceInRobux) then
				RobuxPrice = tonumber(info.PriceInRobux)
				for _, player in ipairs(Players:GetPlayers()) do GymService.Push(player) end
			else
				warn("[GymService] could not read the bench product price: " .. tostring(info))
			end
		end)
	end
	--.. Studio dev hook
	if game:GetService("RunService"):IsStudio() then
		workspace:GetAttributeChangedSignal("GymDev"):Connect(function()
			local cmd = workspace:GetAttribute("GymDev")
			if type(cmd) ~= "string" then return end
			local who, level = cmd:match("^(.-):(%d+)$")
			if not who then return end
			local player = Players:FindFirstChild(who) or Players:GetPlayers()[1]
			local data = player and DataService.GetData(player)
			if data then
				data.Upgrades.BenchPress = math.clamp(tonumber(level), 1, UpgradeDef("BenchPress").Max)
				DataService.RequestSave(player)
				ApplyEffects(player)
				GymService.Push(player)
			end
			workspace:SetAttribute("GymDev", nil)
		end)
	end
	return GymService
end

return GymService
