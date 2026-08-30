local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local UserInterfaceLoader = require(ReplicatedStorage.Modules.UserInterfaceLoader)
local ProductController = ControllerLoader.GetController("ProductController")
local SoundController = ControllerLoader.GetController("SoundController")
local HapticUtil = require(ReplicatedStorage.Modules.HapticUtil)
local GetTimeSkipQuote = ReplicatedStorage:WaitForChild("GetTimeSkipQuote")
local GetVaultTimeSkipQuote = ReplicatedStorage:WaitForChild("GetVaultTimeSkipQuote")

local Player = Players.LocalPlayer
local CUCUMBER_ICON = "rbxassetid://130860765613379"
local DESIGN_WIDTH = 1140
local PANEL_FILL = 1.37511

local Module = {}
local Store
local BoostState
local BoostProgressConnection

local function compactAmount(value)
	value = math.max(0, math.floor(tonumber(value) or 0))
	local suffixes = {
		{1e15, "qa"};
		{1e12, "t"};
		{1e9, "b"};
		{1e6, "m"};
		{1e3, "k"};
	}
	for _, suffix in ipairs(suffixes) do
		if value >= suffix[1] then
			local scaled = value / suffix[1]
			local formatted = scaled >= 100 and string.format("%.0f", scaled)
				or scaled >= 10 and string.format("%.1f", scaled)
				or string.format("%.2f", scaled)
			formatted = formatted:gsub("%.?0+$", "")
			return formatted .. suffix[2]
		end
	end
	return tostring(value)
end

local TimeSkipCards = {}

local function refreshTimeSkipQuotes()
	for _, quote in ipairs(TimeSkipCards) do
		task.spawn(function()
			local ok, amount = pcall(GetTimeSkipQuote.InvokeServer, GetTimeSkipQuote, quote.Seconds)
			if not quote.Label.Parent then return end
			quote.Label.Text = ok and ("+" .. compactAmount(amount)) or "?"
		end)
	end
end

local VaultSkipCards = {}

--.. vault skip cards quote COINS (what the buyer's stored vault cucumbers
--.. would print over the duration), so the label is dollar-prefixed; an
--.. empty vault honestly quotes +$0
local function refreshVaultSkipQuotes()
	for _, quote in ipairs(VaultSkipCards) do
		task.spawn(function()
			local ok, amount = pcall(GetVaultTimeSkipQuote.InvokeServer, GetVaultTimeSkipQuote, quote.Seconds)
			if not quote.Label.Parent then return end
			quote.Label.Text = ok and ("+$" .. compactAmount(amount)) or "?"
		end)
	end
end

local function addHover(button)
	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	local baseScale = button:GetAttribute("HoverBaseScale") or 1
	scale.Name = "HoverScale"
	scale.Scale = baseScale
	scale.Parent = button
	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	button.MouseEnter:Connect(function()
		--.. globally throttled hover tick (same key as Main.bindButton)
		SoundController.PlayFX("Click Sound", {Volume = 0.1; Speed = 1.35; Key = "UIHover"; MinInterval = 0.06;})
		TweenService:Create(scale, info, {Scale = baseScale * 1.04}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, info, {Scale = baseScale}):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, info, {Scale = baseScale * 0.97}):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, info, {Scale = baseScale * 1.04}):Play()
	end)
end

local function playTimeSkipEffect()
	task.spawn(function()
		local sellScreen = Player.PlayerGui:FindFirstChild("SellBloom")
		local bloom = sellScreen and sellScreen:FindFirstChild("SellBloom")
		if not bloom then return end
		bloom.ImageColor3 = Color3.fromRGB(120, 240, 90)
		bloom.ImageTransparency = 1
		sellScreen.Enabled = true
		local fadeIn = TweenService:Create(bloom, TweenInfo.new(0.2), {ImageTransparency = 0.5})
		fadeIn:Play()
		fadeIn.Completed:Wait()
		TweenService:Create(bloom, TweenInfo.new(0.35), {ImageTransparency = 1}):Play()
	end)
	task.spawn(function()
		local bursts = Player.PlayerGui:FindFirstChild("EffectBursts")
		local layer = bursts and bursts:FindFirstChild("TimeSkipLayer")
		local template = layer and layer:FindFirstChild("CukeTemplate")
		if not template then return end
		local clones = {}
		local count = 22
		for index = 1, count do
			local icon = template:Clone()
			icon.Name = "CucumberBurst" .. index
			icon.Image = CUCUMBER_ICON
			local size = math.random(46, 88)
			icon.Size = UDim2.fromOffset(size, size)
			icon.Rotation = math.random(-180, 180)
			icon.Visible = true
			icon.Parent = layer
			table.insert(clones, icon)
			local angle = math.rad((360 / count) * index + math.random(-14, 14))
			local distance = math.random(240, 560)
			TweenService:Create(icon, TweenInfo.new(math.random(55, 90) / 100, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(angle) * distance, 0.52, math.sin(angle) * distance - math.random(60, 170));
				Rotation = icon.Rotation + math.random(-260, 260);
				ImageTransparency = 1;
				Size = UDim2.fromOffset(size * 0.35, size * 0.35);
			}):Play()
		end
		task.wait(1.1)
		for _, icon in ipairs(clones) do icon:Destroy() end
	end)
	--.. routed through PlayFX (SFX-gated) with a cash-register layer; the Key
	--.. throttle stops a success handler pair from doubling the register
	SoundController.PlayFX("Sell Sound")
	SoundController.PlayFX("Cash Register", {Key = "CashRegister"; MinInterval = 0.5;})
end

--.. Robux purchase feedback (SFX pass 2026-08-26): every prompt outcome now
--.. answers the player. Success = the time-skip bloom/burst + a Success layer;
--.. declined/failed = a soft neutral thock (deliberately NOT the Error buzzer).
local function purchaseSucceeded()
	playTimeSkipEffect()
	SoundController.PlayFX("Success", {Speed = 1.05})
	pcall(HapticUtil.Pulse, 0.6, 0.15, "Small")
end
local function purchaseDeclined()
	SoundController.PlayFX("Click Sound", {Speed = 0.6; Volume = 0.35;})
end

local function buildCatalog()
	local catalog = Store.ContentPanel.TimeSkipCatalog
	local section = catalog.PicklesSection
	local template = section.TimeSkipCardTemplate
	table.clear(TimeSkipCards)
	for _, child in ipairs(section:GetChildren()) do
		if child:IsA("Frame") and child ~= template then child:Destroy() end
	end

	local ordered = {}
	for name, data in pairs(ProductController.Products.TimeSkips) do
		table.insert(ordered, {Name = name, Data = data})
	end
	table.sort(ordered, function(a, b)
		return (a.Data.Order or 99) < (b.Data.Order or 99)
	end)

	local validIds = {}
	for _, entry in ipairs(ordered) do
		local card = template:Clone()
		card.Name = entry.Name:gsub("%s+", "") .. "Card"
		card.LayoutOrder = entry.Data.Order or 99
		card.Visible = true
		local featured = (entry.Data.Order or 99) >= 4
		local durationLabel = card.DurationLabel
		durationLabel.Text = "..."
		durationLabel.TextColor3 = featured and Color3.fromRGB(255, 204, 45) or Color3.new(1, 1, 1)
		local oldAmountLabel = card:FindFirstChild("CucumberAmountLabel")
		if oldAmountLabel then oldAmountLabel:Destroy() end
		local purchase = card.PurchaseButton
		purchase.Name = "Purchase" .. entry.Name:gsub("%s+", "")
		purchase:SetAttribute("ProductId", entry.Data.Id)
		purchase.PriceLabel.Text = "..."
		addHover(purchase)
		purchase.Activated:Connect(function()
			if entry.Data.Id and entry.Data.Id ~= 0 then
				MarketplaceService:PromptProductPurchase(Player, entry.Data.Id)
			end
		end)
		card.Parent = section
		table.insert(TimeSkipCards, {
			Label = durationLabel;
			Seconds = entry.Data.Seconds or entry.Data.Amount;
			Featured = featured;
		})
		validIds[entry.Data.Id] = true
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, entry.Data.Id, Enum.InfoType.Product)
			if ok and card.Parent then
				purchase.PriceLabel.Text = tostring(info.PriceInRobux or "?")
			elseif card.Parent then
				purchase.PriceLabel.Text = "?"
			end
		end)
	end
	refreshTimeSkipQuotes()

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId ~= Player.UserId or not validIds[productId] then return end
		if not purchased then purchaseDeclined() return end
		local main = UserInterfaceLoader.CacheModule("Main")
		if Store.Visible and main then main.OpenFrame("Store", nil, nil, {}) end
		playTimeSkipEffect()
	end)
end

--.. VAULT SKIPS section: same card language as the pickles grid, but each
--.. card quotes the coins the buyer's OWN vault would print over the
--.. duration (GetVaultTimeSkipQuote -> VaultTimeSkipService). Id 0 entries
--.. render as "SOON" and refuse the purchase prompt until the dashboard
--.. products exist in ProductController.Products.VaultTimeSkips.
local function buildVaultCatalog()
	local catalog = Store.ContentPanel.TimeSkipCatalog
	local section = catalog:FindFirstChild("VaultSkipsSection")
	if not section then return end -- older gui without the section: skip quietly
	local template = section.TimeSkipCardTemplate
	table.clear(VaultSkipCards)
	for _, child in ipairs(section:GetChildren()) do
		if child:IsA("Frame") and child ~= template then child:Destroy() end
	end

	local ordered = {}
	for name, data in pairs(ProductController.Products.VaultTimeSkips or {}) do
		table.insert(ordered, {Name = name, Data = data})
	end
	table.sort(ordered, function(a, b)
		return (a.Data.Order or 99) < (b.Data.Order or 99)
	end)

	local validIds = {}
	for _, entry in ipairs(ordered) do
		local card = template:Clone()
		card.Name = "Vault" .. entry.Name:gsub("%s+", "") .. "Card"
		card.LayoutOrder = entry.Data.Order or 99
		card.Visible = true
		local featured = (entry.Data.Order or 99) >= 4
		local durationLabel = card.DurationLabel
		durationLabel.Text = "..."
		durationLabel.TextColor3 = featured and Color3.fromRGB(255, 204, 45) or Color3.new(1, 1, 1)
		local oldAmountLabel = card:FindFirstChild("CucumberAmountLabel")
		if oldAmountLabel then oldAmountLabel:Destroy() end
		local purchase = card.PurchaseButton
		purchase.Name = "PurchaseVault" .. entry.Name:gsub("%s+", "")
		purchase:SetAttribute("ProductId", entry.Data.Id)
		purchase.PriceLabel.Text = "..."
		addHover(purchase)
		purchase.Activated:Connect(function()
			if entry.Data.Id and entry.Data.Id ~= 0 then
				MarketplaceService:PromptProductPurchase(Player, entry.Data.Id)
			end
		end)
		card.Parent = section
		table.insert(VaultSkipCards, {
			Label = durationLabel;
			Seconds = entry.Data.Seconds or entry.Data.Amount;
		})
		if entry.Data.Id and entry.Data.Id ~= 0 then
			validIds[entry.Data.Id] = true
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, entry.Data.Id, Enum.InfoType.Product)
				if ok and card.Parent then
					purchase.PriceLabel.Text = tostring(info.PriceInRobux or "?")
				elseif card.Parent then
					purchase.PriceLabel.Text = "?"
				end
			end)
		else
			purchase.PriceLabel.Text = "SOON"
		end
	end
	refreshVaultSkipQuotes()

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId ~= Player.UserId or not validIds[productId] then return end
		if not purchased then purchaseDeclined() return end
		local main = UserInterfaceLoader.CacheModule("Main")
		if Store.Visible and main then main.OpenFrame("Store", nil, nil, {}) end
		playTimeSkipEffect()
	end)
end

local function fillPetPreview(card, petName)
	local preview = card:FindFirstChild("PetPreview")
	local source = ReplicatedStorage.Assets.Pets:FindFirstChild(petName)
	if not preview or not source then return end
	preview:ClearAllChildren()
	local world = Instance.new("WorldModel")
	world.Parent = preview
	local model = source:Clone()
	model.Parent = world
	model:PivotTo(CFrame.new())
	local bounds, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + -bounds.Position)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	local radius = math.max(size.X, size.Y, size.Z)
	camera.CFrame = CFrame.lookAt(Vector3.new(radius * 0.7, radius * 0.25, radius * 2.15), Vector3.new(0, 0, 0))
	camera.Parent = preview
	preview.CurrentCamera = camera
end

local function buildBundleCatalog()
	local section = Store.ContentPanel.TimeSkipCatalog.BundlesSection
	local validIds = {}
	for _, card in ipairs(section:GetChildren()) do
		if not card:IsA("Frame") or not card.Visible then continue end
		local productId = card:GetAttribute("ProductId")
		local petName = card:GetAttribute("PetName")
		local purchase = card:FindFirstChild("PurchaseButton")
		if purchase and productId then
			validIds[productId] = true
			addHover(purchase)
			purchase.MouseButton1Click:Connect(function()
				MarketplaceService:PromptProductPurchase(Player, productId)
			end)
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
				if purchase.Parent then
					purchase.PriceLabel.Text = ok and tostring(info.PriceInRobux or "?") or "?"
				end
			end)
		end
		fillPetPreview(card, petName)
	end

	--.. bundle purchase feedback (there was NONE before this pass)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId ~= Player.UserId or not validIds[productId] then return end
		if purchased then purchaseSucceeded() else purchaseDeclined() end
	end)
end

local function buildBoostCatalog()
	local section = Store.ContentPanel.TimeSkipCatalog.BoostsSection
	local card = section:FindFirstChild("DoubleCucumbersBoostCard")
	if not card then return end
	local validIds = {}
	for _, purchase in ipairs(card:GetChildren()) do
		if not purchase:IsA("GuiButton") then continue end
		local productId = purchase:GetAttribute("ProductId")
		if not productId then continue end
		validIds[productId] = true
		addHover(purchase)
		purchase.MouseButton1Click:Connect(function()
			MarketplaceService:PromptProductPurchase(Player, productId)
		end)
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
			if purchase.Parent then
				purchase.PriceLabel.Text = ok and tostring(info.PriceInRobux or "?") or "?"
			end
		end)
	end

	--.. boost purchase feedback (there was NONE before this pass)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId ~= Player.UserId or not validIds[productId] then return end
		if purchased then purchaseSucceeded() else purchaseDeclined() end
	end)
end

local function scrollToSection(section)
	local catalog = Store.ContentPanel.TimeSkipCatalog
	task.defer(function()
		task.wait()
		local targetY = catalog.CanvasPosition.Y + section.AbsolutePosition.Y - catalog.AbsolutePosition.Y
		local maximum = math.max(0, catalog.AbsoluteCanvasSize.Y - catalog.AbsoluteWindowSize.Y)
		targetY = math.clamp(targetY, 0, maximum)
		TweenService:Create(catalog, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			CanvasPosition = Vector2.new(0, targetY)
		}):Play()
	end)
end

function Module.Boosts(data)
	if type(data) ~= "table" or data.BoostName ~= "2x Cucumbers" then return end
	local remaining = math.max(0, tonumber(data.TimeRemaining) or 0)
	local total = math.max(remaining, tonumber(data.TotalDuration) or remaining)
	BoostState = {
		Remaining = remaining;
		Total = total;
		UpdatedAt = os.clock();
	}
end

function Module.OnStart(interface)
	Store = interface
	local scaler = Store:FindFirstChild("ResponsiveScale")
	local host = Store.Parent
	if scaler and host then
		local function updateScale()
			if host.AbsoluteSize.X > 0 then
				scaler.Scale = host.AbsoluteSize.X * PANEL_FILL / DESIGN_WIDTH
			end
		end
		updateScale()
		host:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	end

	Store.CloseButton.MouseButton1Click:Connect(function()
		if not Store.Visible then return end
		local main = UserInterfaceLoader.CacheModule("Main")
		if main then main.OpenFrame("Store", nil, nil, {}) end
	end)
	addHover(Store.CloseButton)

	addHover(Store.TabRail.PicklesTab)
	addHover(Store.TabRail.BundlesTab)
	addHover(Store.TabRail.BoostsTab)
	buildCatalog()
	buildVaultCatalog()
	buildBundleCatalog()
	buildBoostCatalog()

	if BoostProgressConnection then BoostProgressConnection:Disconnect() end
	local progressFill = Store.ContentPanel.TimeSkipCatalog.BoostsSection.DoubleCucumbersBoostCard
		.ProgressBarArtwork.ProgressTrack.ProgressFill
	BoostProgressConnection = RunService.Heartbeat:Connect(function()
		local progress = 0
		local active = false
		if BoostState and BoostState.Total > 0 then
			local elapsed = os.clock() - BoostState.UpdatedAt
			local remaining = math.max(0, BoostState.Remaining - elapsed)
			active = remaining > 0
			if active then
				progress = math.clamp(1 - (remaining / BoostState.Total), 0, 1)
			else
				BoostState = nil
			end
		end
		progressFill.Visible = active and progress > 0
		progressFill.Size = UDim2.new(progress, 0, 1, 0)
	end)

	Store:GetPropertyChangedSignal("Visible"):Connect(function()
		if Store.Visible then
			refreshTimeSkipQuotes()
			refreshVaultSkipQuotes()
		end
	end)

	local catalog = Store.ContentPanel.TimeSkipCatalog
	local function showRequestedTab()
		local requested = Store:GetAttribute("RequestedTab")
		if requested == "Bundles" then
			scrollToSection(catalog.BundlesSection)
		elseif requested == "Boosts" then
			scrollToSection(catalog.BoostsSection)
		elseif requested == "Vault" then
			--.. land on the header so the section title is in view
			scrollToSection(catalog:FindFirstChild("VaultSkipsHeader") or catalog:FindFirstChild("VaultSkipsSection") or catalog.PicklesSection)
		else
			scrollToSection(catalog.PicklesSection)
		end
	end
	local function selectTab(tabName)
		if Store:GetAttribute("RequestedTab") == tabName then
			showRequestedTab()
		else
			Store:SetAttribute("RequestedTab", tabName)
		end
	end
	Store.TabRail.PicklesTab.MouseButton1Click:Connect(function()
		selectTab("Pickles")
	end)
	Store.TabRail.BundlesTab.MouseButton1Click:Connect(function()
		selectTab("Bundles")
	end)
	Store.TabRail.BoostsTab.MouseButton1Click:Connect(function()
		selectTab("Boosts")
	end)
	local vaultTab = Store.TabRail:FindFirstChild("VaultTab")
	if vaultTab then
		addHover(vaultTab)
		vaultTab.MouseButton1Click:Connect(function()
			selectTab("Vault")
		end)
	end
	Store:GetAttributeChangedSignal("RequestedTab"):Connect(showRequestedTab)
	catalog:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if Store.Visible then task.defer(showRequestedTab) end
	end)
	showRequestedTab()
end

function Module.OnUpdate()
end

return Module
