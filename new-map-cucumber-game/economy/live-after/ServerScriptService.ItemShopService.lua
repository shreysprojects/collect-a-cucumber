--[[
	ItemShopService  (Script, ServerScriptService)  2026-09-23
	The lobby ITEM SHOP: the green cart in Map.Lobby.Shops (the former "Sell Shop", now "Item Shop")
	sells the nine drop items for Cash through the Grow-a-Garden-style StarterGui.CucumberMenus.BuyShopPanel.
	Numbers: ReplicatedStorage.Modules.ItemShopCatalog (prices, "1 in N" stock chances, stock ranges,
	restock interval). Items: ReplicatedStorage.Modules.ItemsCatalog + ServerStorage.ItemAPI.Give
	(ItemService's stacked hotbar tools). Cash: ServerStorage.DataService ("Cash").

	  STOCK    one shelf per SERVER. Every RESTOCK_SECONDS each item rolls 1 in Chance to be in stock
	           (Stock.Min .. Stock.Max units), otherwise it is sold out until the next restock. Buying
	           takes one unit; the shelf never refills between restocks.
	  STATE    attributes on Remotes.ItemShop (replicated to every client):
	             Stock         JSON {[Key] = units}
	             NextRestockAt workspace:GetServerTimeNow() of the next restock
	             Restocks      how many restocks this server has rolled (a change signal for clients)
	  BUY      Remotes.ItemShop (RemoteFunction) ("Buy", key) -> {Ok = true, Stock = n, Cash = n}
	           or {Ok = false, Error = "..."} (message for a toast). Checks: loaded profile, known
	           key, in stock, enough Cash, per-player cooldown. Cash is taken first; a failed Give
	           refunds it.
	  PROMPT   an invisible "ItemShopAnchor" Part just inside the cart's open front (a CHILD of the
	           cart, because LobbyLayout slides every shop along Z at server start) carries a
	           ProximityPrompt ("Open" / "Item Shop"); Triggered -> Remotes.OpenItemShop:FireClient,
	           which ItemShopController answers by opening the panel.
	  STUDIO   Remotes.ItemShop attribute ItemShopDev = "restock" (roll now) | "stockall[:<n>]" (every
	           item in stock, n units) | "stock:<Key>:<n>" | "clear" | "cash:<n>" (first player)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Catalog = require(Modules:WaitForChild("ItemShopCatalog"))
local Items = require(Modules:WaitForChild("ItemsCatalog"))
local DataService = require(ServerStorage:WaitForChild("DataService"))

--..Config..--
local CART_NAMES = {"Item Shop", "Sell Shop"} --.. Map.Lobby.Shops[...]: the first that exists
local ANCHOR_NAME = "ItemShopAnchor"
local PROMPT_NAME = "ItemShopPrompt"
local PROMPT_TAG = "ShopBoothPrompt" --.. same tag as the headband booth prompt
local PROMPT_DISTANCE = 12
local TALK_FORWARD = 2 --.. studs from the cart's centre toward its open front
local TALK_HEIGHT = 3.2 --.. studs above the lobby floor
local LAYOUT_WAIT = 5 --.. seconds to spin on Map.Lobby.LayoutReady
local STREAM_WAIT = 30

--..Remotes..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local function Remote(class, name)
	local r = Remotes:FindFirstChild(name)
	if r and not r:IsA(class) then r:Destroy() r = nil end
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
local ShopRemote = Remote("RemoteFunction", "ItemShop")
local OpenRemote = Remote("RemoteEvent", "OpenItemShop")

--..State..--
local Stock = {} -- [Key] = units
local Restocks = 0
local NextRestockAt = 0
local rng = Random.new()
local LastAction = {} -- [player] = os.clock()

local function ItemApi(name)
	local api = ServerStorage:FindFirstChild("ItemAPI")
	local fn = api and api:FindFirstChild(name)
	return fn and fn:IsA("BindableFunction") and fn or nil
end

--.. 2026-09-23 (economy): prices scale with the buyer's threat level (ZombieAPI.ThreatLevel = the biome their base is
--.. worth), x Catalog.PRICE_LEVEL_STEP per level, published as the player attribute ItemShopPriceMult for the panel
local function PriceMult(player)
	local api = ServerStorage:FindFirstChild("ZombieAPI")
	local fn = api and api:FindFirstChild("ThreatLevel")
	local level = 1
	if fn and fn:IsA("BindableFunction") then
		local ok, lv = pcall(fn.Invoke, fn, player)
		if ok and type(lv) == "number" then level = lv end
	end
	local mult = (Catalog.PRICE_LEVEL_STEP or 1) ^ (math.clamp(level, 1, 10) - 1)
	if player and player.Parent then player:SetAttribute("ItemShopPriceMult", mult) end
	return mult
end
local function PriceOf(player, def)
	return math.floor(def.Price * PriceMult(player) + 0.5)
end

local function Publish()
	ShopRemote:SetAttribute("Stock", HttpService:JSONEncode(Stock))
	ShopRemote:SetAttribute("NextRestockAt", NextRestockAt)
	ShopRemote:SetAttribute("Restocks", Restocks)
end

local function Roll()
	local inStock = {}
	Stock = {}
	for _, def in ipairs(Catalog.ITEMS) do
		local chance = math.max(1, math.floor(def.Chance / math.max(1, Catalog.DEV_CHANCE_DIV or 1)))
		if rng:NextInteger(1, chance) == 1 then
			local units = rng:NextInteger(def.Stock.Min, def.Stock.Max)
			if units > 0 then
				Stock[def.Key] = units
				table.insert(inStock, ("%s x%d"):format(def.Key, units))
			end
		end
	end
	Restocks += 1
	NextRestockAt = workspace:GetServerTimeNow() + Catalog.RESTOCK_SECONDS
	Publish()
	print(("[ItemShopService] restock #%d: %s"):format(Restocks, #inStock > 0 and table.concat(inStock, ", ") or "nothing in stock"))
end

--..Buying..--
local function Buy(player, key)
	if not DataService.IsLoaded(player) then return {Ok = false, Error = "Your data is still loading"} end
	local def = Catalog.Get(key)
	local item = def and Items.Get(key)
	if not (def and item) then return {Ok = false, Error = "Unknown item"} end
	local units = tonumber(Stock[key]) or 0
	if units <= 0 then return {Ok = false, Error = item.Name .. " is sold out"} end
	local price = PriceOf(player, def) -- 2026-09-23: x4 per threat level
	local cash = tonumber(DataService.Get(player, "Cash")) or 0
	if cash < price then
		return {Ok = false, Error = ("Need %s more Cash"):format(Catalog.PriceText(price - cash):sub(2))}
	end
	local give = ItemApi("Give")
	if not give then return {Ok = false, Error = "The shop is not ready"} end
	if not DataService.Increment(player, "Cash", -price) then return {Ok = false, Error = "Could not take the Cash"} end
	local ok, result = pcall(give.Invoke, give, player, key, 1)
	if not (ok and result) then
		DataService.Increment(player, "Cash", price) --.. refund
		warn("[ItemShopService] Give failed for " .. key .. ": " .. tostring(result))
		return {Ok = false, Error = "Could not hand over the item"}
	end
	Stock[key] = units - 1
	if Stock[key] <= 0 then Stock[key] = nil end
	Publish()
	DataService.RequestSave(player)
	print(("[ItemShopService] %s bought %s for %s (%d left)"):format(player.Name, key, Catalog.PriceText(price), Stock[key] or 0))
	return {Ok = true, Stock = Stock[key] or 0, Cash = tonumber(DataService.Get(player, "Cash")) or 0, Name = item.Name}
end

ShopRemote.OnServerInvoke = function(player, kind, key)
	local now = os.clock()
	if LastAction[player] and now - LastAction[player] < Catalog.ACTION_COOLDOWN then return {Ok = false, Error = "Slow down"} end
	LastAction[player] = now
	if kind == "Buy" then
		if type(key) ~= "string" then return {Ok = false, Error = "Unknown item"} end
		local ok, result = pcall(Buy, player, key)
		if not ok then
			warn("[ItemShopService] Buy: " .. tostring(result))
			return {Ok = false, Error = "Something went wrong"}
		end
		return result
	elseif kind == "State" then
		local mult = PriceMult(player) -- refreshes the ItemShopPriceMult attribute the panel reads
		return {Ok = true, Stock = Stock, NextRestockAt = NextRestockAt, Restocks = Restocks, PriceMult = mult}
	end
	return {Ok = false, Error = "Unknown action"}
end
Players.PlayerRemoving:Connect(function(player) LastAction[player] = nil end)

--..The cart prompt (never hard-code the cart's coordinates: LobbyLayout slides it every server start)..--
local function WorldBounds(model)
	local min, max
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, half = d.CFrame, d.Size * 0.5
			local ext = Vector3.new(
				math.abs(cf.RightVector.X) * half.X + math.abs(cf.UpVector.X) * half.Y + math.abs(cf.LookVector.X) * half.Z,
				math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z,
				math.abs(cf.RightVector.Z) * half.X + math.abs(cf.UpVector.Z) * half.Y + math.abs(cf.LookVector.Z) * half.Z
			)
			local lo, hi = cf.Position - ext, cf.Position + ext
			min = min and Vector3.new(math.min(min.X, lo.X), math.min(min.Y, lo.Y), math.min(min.Z, lo.Z)) or lo
			max = max and Vector3.new(math.max(max.X, hi.X), math.max(max.Y, hi.Y), math.max(max.Z, hi.Z)) or hi
		end
	end
	return min, max
end

local function FloorTopY(lobby, fallback)
	local floor = lobby:FindFirstChild("Floor")
	local part = floor and (floor:IsA("BasePart") and floor or floor:FindFirstChildWhichIsA("BasePart", true))
	if part then return part.Position.Y + part.Size.Y * 0.5 end
	return fallback
end

--.. the cart's open front: the big union shell's +Z axis (its customer side); fall back to the pivot rule
local function OpenDirection(cart)
	local shell
	for _, d in ipairs(cart:GetDescendants()) do
		if d:IsA("UnionOperation") and d.Size.X > 15 and (not shell or d.Size.Magnitude > shell.Size.Magnitude) then shell = d end
	end
	local dir
	if shell then
		dir = shell.CFrame.ZVector
	else
		local pivot = cart:GetPivot()
		dir = -pivot.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	return dir.Magnitude > 0.1 and dir.Unit or Vector3.xAxis
end

local function SetupPrompt()
	local map = workspace:WaitForChild("Map", STREAM_WAIT)
	local lobby = map and map:WaitForChild("Lobby", STREAM_WAIT)
	if not lobby then
		warn("[ItemShopService] no Map.Lobby -- the cart prompt was not built")
		return
	end
	local deadline = os.clock() + LAYOUT_WAIT
	while not lobby:GetAttribute("LayoutReady") and os.clock() < deadline do task.wait(0.05) end
	local shops = lobby:WaitForChild("Shops", STREAM_WAIT)
	local cart
	for _, name in ipairs(CART_NAMES) do
		cart = shops and shops:FindFirstChild(name)
		if cart then break end
	end
	if not cart then
		warn("[ItemShopService] no Lobby.Shops[Item Shop] -- the cart prompt was not built")
		return
	end
	local open = OpenDirection(cart)
	local min, max = WorldBounds(cart)
	if not min then return end
	local centre = (min + max) * 0.5
	local floorY = FloorTopY(lobby, min.Y)
	local spot = Vector3.new(centre.X, floorY + TALK_HEIGHT, centre.Z) + open * TALK_FORWARD

	local old = cart:FindFirstChild(ANCHOR_NAME)
	if old then old:Destroy() end
	local anchor = Instance.new("Part")
	anchor.Name = ANCHOR_NAME
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.lookAt(spot, spot + open)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = cart

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Open"
	prompt.ObjectText = "Item Shop"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt:SetAttribute("Shop", "Items")
	CollectionService:AddTag(prompt, PROMPT_TAG)
	prompt.Triggered:Connect(function(player)
		OpenRemote:FireClient(player)
	end)
	prompt.Parent = anchor
	print(("[ItemShopService] cart prompt on %s at %.1f, %.1f, %.1f"):format(cart.Name, spot.X, spot.Y, spot.Z))
end

--..Restock loop..--
task.spawn(function()
	Roll()
	while true do
		local wait = NextRestockAt - workspace:GetServerTimeNow()
		if wait > 0 then task.wait(math.min(wait, 5)) end
		if workspace:GetServerTimeNow() >= NextRestockAt then Roll() end
	end
end)
task.spawn(SetupPrompt)

--..Studio hooks..--
if RunService:IsStudio() then
	ShopRemote:SetAttribute("ItemShopDev", nil)
	ShopRemote:GetAttributeChangedSignal("ItemShopDev"):Connect(function()
		local cmd = ShopRemote:GetAttribute("ItemShopDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		ShopRemote:SetAttribute("ItemShopDev", nil)
		if cmd == "restock" then
			Roll()
			return
		end
		local n = cmd:match("^stockall:?(%d*)$")
		if n then
			for _, def in ipairs(Catalog.ITEMS) do Stock[def.Key] = tonumber(n) or def.Stock.Max end
			Publish()
			print("[ItemShopService] dev: everything in stock")
			return
		end
		local key, units = cmd:match("^stock:(%w+):(%d+)$")
		if key then
			if Catalog.Get(key) then
				Stock[key] = tonumber(units) > 0 and tonumber(units) or nil
				Publish()
				print(("[ItemShopService] dev: %s = %s"):format(key, tostring(Stock[key] or 0)))
			else
				warn("[ItemShopService] dev: unknown key " .. key)
			end
			return
		end
		if cmd == "clear" then
			Stock = {}
			Publish()
			print("[ItemShopService] dev: shelf cleared")
			return
		end
		local cash = tonumber(cmd:match("^cash:(%-?%d+)$"))
		if cash then
			local player = Players:GetPlayers()[1]
			if player then
				DataService.Increment(player, "Cash", cash)
				print(("[ItemShopService] dev: %+d Cash for %s -> %s"):format(cash, player.Name, tostring(DataService.Get(player, "Cash"))))
			end
			return
		end
		warn("[ItemShopService] dev: use restock / stockall[:n] / stock:<Key>:<n> / clear / cash:<n>")
	end)
end

print(("[ItemShopService] %d items for sale, restock every %ds (Remotes.ItemShop / OpenItemShop)"):format(#Catalog.ITEMS, Catalog.RESTOCK_SECONDS))
