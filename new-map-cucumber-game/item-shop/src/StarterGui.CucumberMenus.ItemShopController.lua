--[[
	ItemShopController  (ModuleScript, StarterGui.CucumberMenus)  2026-09-23
	Scripts the authored Grow-a-Garden-style StarterGui.CucumberMenus.BuyShopPanel ("ITEM SHOP"):
	  * the sample rows (attribute PreviewOnly) are thrown away and one row per ItemShopCatalog item is
	    built from Templates.InStockItem: name / type / price, a ViewportFrame picture of the item model
	    (ReplicatedStorage.Assets.Items/<Key>, framed like the authored samples: FOV 32, camera from the
	    front-right at 2.06 x the model's largest side) and a "1 in N" label UNDER the picture = the
	    chance the item is in stock after a restock (user: "have a percent chance under each model
	    viewport like [1 in 10000]")
	  * stock comes from the attributes ItemShopService keeps on Remotes.ItemShop (Stock JSON,
	    NextRestockAt, Restocks): in-stock rows wear the InStockItem look ("N in stock", green BUY),
	    sold-out rows the SoldOutItem look ("Sold out", grey NO STOCK); the RestockBanner counts down to
	    the next restock; a price the player cannot afford is tinted red
	  * BUY -> Remotes.ItemShop:InvokeServer("Buy", key) -> success sounds + flash + a Notify toast, or
	    the server's error as a red toast
	  * the panel opens through MenuController (OpenRequest "BuyShop"): the cart prompt fires
	    Remotes.OpenItemShop and this controller writes that request
	Dev hook: BuyShopPanel attribute ItemShopDev = "open" | "close" | "buy:<Key>".
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ShopCatalog = require(Modules:WaitForChild("ItemShopCatalog"))
local Items = require(Modules:WaitForChild("ItemsCatalog"))
local ButtonFX = require(Modules:WaitForChild("ButtonFX"))
local Notify = require(Modules:WaitForChild("Notify"))

local player = Players.LocalPlayer
local Shop = {}

local PANEL = "BuyShop" --.. the MenuController panel name (OpenRequest "BuyShop")
local VIEW_DIR = Vector3.new(0.35, 0.166, 0.92).Unit --.. the authored sample cameras: front-right, a little above
local VIEW_FOV = 32
local VIEW_DIST = 2.06 --.. x the model's largest side (measured on the authored samples)
local CHANCE_HEIGHT = 26 --.. px of the 104-px preview tile given to the "1 in N" label
local CHANCE_COLOR = Color3.fromRGB(255, 245, 147)
local UNAFFORDABLE = Color3.fromRGB(255, 120, 120)
local REMOTE_WAIT = 20

function Shop.Start(gui, menus)
	local panel = gui:WaitForChild("BuyShopPanel")
	local content = panel:WaitForChild("Content")
	local list = content:WaitForChild("ItemList")
	local templates = panel:WaitForChild("Templates")
	local inStockTemplate = templates:WaitForChild("InStockItem")
	local soldOutTemplate = templates:WaitForChild("SoldOutItem")
	local banner = content:FindFirstChild("RestockBanner")
	local timerLabel = banner and banner:FindFirstChild("Timer")
	local footer = content:FindFirstChild("ShopFooter")
	local itemCount = footer and footer:FindFirstChild("ItemCount")
	local header = content:FindFirstChild("Header")
	local subtitle = header and header:FindFirstChild("Subtitle")
	local connections = {}
	local destroyed = false
	local function connect(signal, fn) table.insert(connections, signal:Connect(fn)) end
	local function tween(instance, seconds, goals)
		TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
	end
	local function hover(button)
		local scale = button:FindFirstChild("HoverScale") or Instance.new("UIScale")
		scale.Name = "HoverScale"
		scale.Parent = button
		connect(button.MouseEnter, function() tween(scale, 0.12, {Scale = 1.035}) end)
		connect(button.MouseLeave, function() tween(scale, 0.12, {Scale = 1}) end)
		connect(button.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then tween(scale, 0.08, {Scale = 0.97}) end
		end)
		connect(button.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then tween(scale, 0.1, {Scale = 1}) end
		end)
	end

	if subtitle then
		subtitle.Text = ("Limited stock. Fresh items every %d minutes."):format(math.max(1, math.floor(ShopCatalog.RESTOCK_SECONDS / 60 + 0.5)))
	end

	--..Rows..--
	local rows = {} -- [key] = {Frame, Def, Item, Stock}
	local remote -- Remotes.ItemShop (set once the server has made it)

	local function ClearSamples()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") and (child:GetAttribute("PreviewOnly") or child:GetAttribute("Live")) then child:Destroy() end
		end
	end

	local function BuildPreview(viewport, key)
		viewport:ClearAllChildren()
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local folder = assets and assets:FindFirstChild("Items")
		local template = folder and folder:FindFirstChild(key)
		if not template then return end
		local world = Instance.new("WorldModel")
		world.Name = "PreviewWorld"
		world.Parent = viewport
		local model = template:Clone()
		model.Parent = world
		local cf, size = model:GetBoundingBox()
		model:PivotTo(model:GetPivot() - cf.Position) -- the bounding box centre on the origin
		local camera = Instance.new("Camera")
		camera.Name = "PreviewCamera"
		camera.FieldOfView = VIEW_FOV
		camera.CFrame = CFrame.lookAt(VIEW_DIR * (VIEW_DIST * math.max(size.X, size.Y, size.Z, 0.5)), Vector3.zero)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		viewport.Ambient = Color3.fromRGB(210, 210, 210)
		viewport.LightColor = Color3.new(1, 1, 1)
		viewport.LightDirection = Vector3.new(-1, -1, -1)
	end

	local function ChanceLabel(tile)
		local label = tile:FindFirstChild("Chance")
		if not label then
			label = Instance.new("TextLabel")
			label.Name = "Chance"
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, -8, 0, CHANCE_HEIGHT)
			label.Position = UDim2.new(0, 4, 1, -CHANCE_HEIGHT - 3)
			label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
			label.TextSize = 19
			label.TextColor3 = CHANCE_COLOR
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center
			label.ZIndex = 12
			local stroke = Instance.new("UIStroke")
			stroke.Name = "TextOutline"
			stroke.Thickness = 2.5
			stroke.Color = Color3.fromRGB(36, 25, 29)
			stroke.Parent = label
			label.Parent = tile
		end
		local viewport = tile:FindFirstChild("ItemPreview")
		if viewport then viewport.Size = UDim2.new(1, 0, 1, -CHANCE_HEIGHT - 2) end
		return label
	end

	--.. the in-stock / sold-out looks are the two authored templates; copy the bits that differ
	local function CopyStyle(row, template)
		local db, sb = row:FindFirstChild("BuyButton"), template:FindFirstChild("BuyButton")
		if db and sb then
			local dg, sg = db:FindFirstChild("Gradient"), sb:FindFirstChild("Gradient")
			if dg and sg then dg.Color = sg.Color end
			local ds, ss = db:FindFirstChild("UIStroke"), sb:FindFirstChild("UIStroke")
			if ds and ss then ds.Color = ss.Color end
			local dr, sr = db:FindFirstChild("InnerRim"), sb:FindFirstChild("InnerRim")
			if dr and sr then
				dr.Visible = sr.Visible
				local drb, srb = dr:FindFirstChild("Border"), sr:FindFirstChild("Border")
				if drb and srb then drb.Color = srb.Color end
			end
			local da, sa = db:FindFirstChild("Action"), sb:FindFirstChild("Action")
			if da and sa then da.Text = sa.Text end
			local dp, sp = db:FindFirstChild("Price"), sb:FindFirstChild("Price")
			if dp and sp then dp.TextColor3 = sp.TextColor3 end
		end
		local dbadge, sbadge = row:FindFirstChild("StockBadge"), template:FindFirstChild("StockBadge")
		if dbadge and sbadge then
			local dg, sg = dbadge:FindFirstChild("Gradient"), sbadge:FindFirstChild("Gradient")
			if dg and sg then dg.Color = sg.Color end
			local dbd, sbd = dbadge:FindFirstChild("Border"), sbadge:FindFirstChild("Border")
			if dbd and sbd then dbd.Color = sbd.Color end
		end
	end

	--..Cash (affordability tint)..--
	local function CashNow()
		local data = player:FindFirstChild("Data")
		local cash = data and data:FindFirstChild("Cash")
		return cash and tonumber(cash.Value) or nil
	end
	local function RefreshAfford()
		local cash = CashNow()
		for _, r in pairs(rows) do
			local price = r.Frame.BuyButton:FindFirstChild("Price")
			if price then
				if r.Stock > 0 and cash and cash < r.Def.Price then
					price.TextColor3 = UNAFFORDABLE
				else
					local template = r.Stock > 0 and inStockTemplate or soldOutTemplate
					price.TextColor3 = template.BuyButton.Price.TextColor3
				end
			end
		end
	end

	--..Buying..--
	local busy = false
	local function Press(key)
		local r = rows[key]
		if not r then return end
		ButtonFX.Sound(ButtonFX.PRESS_SOUND)
		if r.Stock <= 0 then
			Notify.Warn(r.Item.Name .. " is sold out")
			return
		end
		if busy or not remote then return end
		busy = true
		local ok, result = pcall(remote.InvokeServer, remote, "Buy", key)
		busy = false
		if destroyed then return end
		if ok and type(result) == "table" and result.Ok then
			for _, entry in ipairs(ButtonFX.SUCCESS_SOUNDS) do ButtonFX.Sound(entry) end
			ButtonFX.Flash(r.Frame.BuyButton, Color3.new(1, 1, 1), 0.15, 0.4)
			Notify.Success(("Bought a %s!"):format(r.Item.Name))
		else
			ButtonFX.Sound(ButtonFX.FAIL_SOUND)
			Notify.Error((ok and type(result) == "table" and result.Error) or "Could not buy that")
		end
	end

	local function BuildRow(def)
		local item = Items.Get(def.Key)
		if not item then
			warn("[ItemShopController] no ItemsCatalog entry for " .. tostring(def.Key))
			return
		end
		local row = inStockTemplate:Clone()
		row.Name = def.Key
		row.Visible = true
		row.LayoutOrder = def.Order or 0
		row:SetAttribute("ItemKey", def.Key)
		row:SetAttribute("PreviewOnly", nil)
		row:SetAttribute("Live", true)
		local nameLabel = row:FindFirstChild("ItemName")
		if nameLabel then nameLabel.Text = item.Name end
		local typeLabel = row:FindFirstChild("ItemType")
		if typeLabel then typeLabel.Text = def.Type or string.upper(item.Kind or "ITEM") end
		local price = row.BuyButton:FindFirstChild("Price")
		if price then price.Text = ShopCatalog.PriceText(def.Price) end
		local tile = row:FindFirstChild("PreviewTile")
		if tile then
			local viewport = tile:FindFirstChild("ItemPreview")
			if viewport then BuildPreview(viewport, def.Key) end
			ChanceLabel(tile).Text = ShopCatalog.ChanceText(def.Chance)
		end
		row.Parent = list
		rows[def.Key] = {Frame = row, Def = def, Item = item, Stock = 0}
		hover(row.BuyButton)
		connect(row.BuyButton.Activated, function() Press(def.Key) end)
	end

	ClearSamples()
	for _, def in ipairs(ShopCatalog.ITEMS) do BuildRow(def) end
	if itemCount then itemCount.Text = ("%d ITEMS"):format(#ShopCatalog.ITEMS) end
	for _, r in pairs(rows) do
		CopyStyle(r.Frame, soldOutTemplate)
		r.Frame.StockBadge.StockValue.Text = "Sold out"
	end

	--..State from the server..--
	local function ApplyState()
		if not remote then return end
		local raw = remote:GetAttribute("Stock")
		local stock = {}
		if type(raw) == "string" and raw ~= "" then
			local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
			if ok and type(decoded) == "table" then stock = decoded end
		end
		for key, r in pairs(rows) do
			local units = math.floor(tonumber(stock[key]) or 0)
			r.Stock = units
			CopyStyle(r.Frame, units > 0 and inStockTemplate or soldOutTemplate)
			r.Frame.StockBadge.StockValue.Text = units > 0 and (units .. " in stock") or "Sold out"
		end
		RefreshAfford()
	end
	local function UpdateTimer()
		if not (remote and timerLabel) then return end
		local at = tonumber(remote:GetAttribute("NextRestockAt")) or 0
		local left = math.max(0, math.floor(at - workspace:GetServerTimeNow() + 0.999))
		timerLabel.Text = ("%02d:%02d"):format(left // 60, left % 60)
	end
	local nonce = 0
	local function RequestOpen()
		nonce += 1
		gui:SetAttribute("OpenRequest", PANEL .. "#" .. nonce)
	end

	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
		local shopRemote = remotes and remotes:WaitForChild("ItemShop", REMOTE_WAIT)
		local openRemote = remotes and remotes:WaitForChild("OpenItemShop", REMOTE_WAIT)
		if destroyed then return end
		if not shopRemote then
			warn("[ItemShopController] Remotes.ItemShop never appeared (ItemShopService not running?)")
			return
		end
		remote = shopRemote
		ApplyState()
		UpdateTimer()
		connect(remote:GetAttributeChangedSignal("Stock"), ApplyState)
		connect(remote:GetAttributeChangedSignal("Restocks"), function() ApplyState() UpdateTimer() end)
		connect(remote:GetAttributeChangedSignal("NextRestockAt"), UpdateTimer)
		if openRemote then connect(openRemote.OnClientEvent, RequestOpen) end
		local data = player:FindFirstChild("Data") or player:WaitForChild("Data", REMOTE_WAIT)
		local cash = data and (data:FindFirstChild("Cash") or data:WaitForChild("Cash", REMOTE_WAIT))
		if cash and not destroyed then connect(cash.Changed, RefreshAfford) end
		RefreshAfford()
	end)
	connect(RunService.Heartbeat, function()
		if gui:GetAttribute("OpenPanel") == PANEL then UpdateTimer() end
	end)
	connect(gui:GetAttributeChangedSignal("OpenPanel"), function()
		if gui:GetAttribute("OpenPanel") ~= PANEL then return end
		ApplyState()
		UpdateTimer()
		list.CanvasPosition = Vector2.zero
	end)

	--..Dev hook..--
	connect(panel:GetAttributeChangedSignal("ItemShopDev"), function()
		local dev = panel:GetAttribute("ItemShopDev")
		if type(dev) ~= "string" or dev == "" then return end
		panel:SetAttribute("ItemShopDev", nil)
		if dev == "open" then
			RequestOpen()
		elseif dev == "close" then
			menus.Close()
		else
			local key = dev:match("^buy:(%w+)$")
			if key then Press(key) end
		end
	end)

	return {
		Destroy = function()
			destroyed = true
			for _, connection in ipairs(connections) do connection:Disconnect() end
		end,
		Open = RequestOpen,
	}
end

return Shop
