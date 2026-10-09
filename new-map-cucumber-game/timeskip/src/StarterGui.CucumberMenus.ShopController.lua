--[[
	ShopController  (ModuleScript, StarterGui.CucumberMenus)  2026-09-10
	Wires the authored ShopPanel (built by hud-shop/build_shop.lua in the Zombie store look):
	  * every GuiButton with the PurchaseTemplate attribute is a Robux pill; its ProductId comes
	    from the button (boost pills) or the card it sits in (pack cards, which also carry
	    StrengthAmount / CashAmount for ShopProductsServer). Id 0 shows "SOON" and only toasts.
	    Prices come from MarketplaceService:GetProductInfo; purchases go through
	    PromptProductPurchase and are answered (flash + sounds + toast) on
	    PromptProductPurchaseFinished.
	  * TabRail tabs (attribute Section) scroll the Catalog to "<Section>Header"; the selected tab
	    is drawn bigger (TabScale). ShopPanel attribute RequestedTab = "<Section>" selects a tab
	    from outside (MenuController sets it from OpenRequest "Shop:<Section>"), and the current
	    section follows manual scrolling.
	  * TIME SKIPS (2026-09-23): the pack cards carry TimeSkipSeconds + TimeSkipCurrency ("Cash" | "Strength")
	    and their Amount label shows ONLY the value the buyer would get ("+$2.5M" / "+12.3M"): the buyer's own
	    production over that duration, fetched from Remotes.TimeSkipQuote (TimeSkipServer -> TimeSkipService)
	    once at start, every time the shop opens and every TIMESKIP_REFRESH seconds while it is open. No
	    duration and no "time skip" wording on the card (user 2026-09-23).
	Scroll + tab animations are stepped on Heartbeat (ButtonFX.Animate), not TweenService, so
	they also run (and can be verified) in an unfocused Studio. ScrollingFrame.CanvasPosition,
	AbsoluteCanvasSize and AbsoluteWindowSize all share the same SCREEN-pixel space under the
	panel's UIScale (measured 2026-09-10), so no scale maths is needed.
	Dev hook: ShopPanel attribute ShopDev = "tab:<Section>" | "buy:<n>" (press the n-th pill).
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ButtonFX = require(Modules:WaitForChild("ButtonFX"))
local Notify = require(Modules:WaitForChild("Notify"))
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))

local player = Players.LocalPlayer
local Shop = {}

local TAB_SELECTED = 1
local TAB_HOVER = 0.05
local DEFAULT_SECTION = "Strength"
local SCROLL_SECONDS = 0.35
local TIMESKIP_REFRESH = 5 -- seconds between quote refreshes while the shop is open

function Shop.Start(gui, menus)
	local panel = gui:WaitForChild("ShopPanel")
	local content = panel:WaitForChild("Content")
	local catalog = content:WaitForChild("ContentPanel"):WaitForChild("Catalog")
	local rail = content:WaitForChild("TabRail")
	local connections = {}
	local destroyed = false
	local function connect(signal, fn) table.insert(connections, signal:Connect(fn)) end

	--..Products..--
	local buttons = {} -- every pill, in tree order
	local byProduct = {} -- [productId] = {button, ...}
	local function ProductOf(button)
		local id = button:GetAttribute("ProductId")
		if id == nil and button.Parent then id = button.Parent:GetAttribute("ProductId") end
		return tonumber(id) or 0
	end
	local function FillPrice(button)
		local price = button:FindFirstChild("Price")
		if not price then return end
		local id = ProductOf(button)
		if id <= 0 then
			price.Text = "SOON"
			return
		end
		price.Text = "..."
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, Enum.InfoType.Product)
			if destroyed or not price.Parent then return end
			price.Text = (ok and type(info) == "table" and info.PriceInRobux) and tostring(info.PriceInRobux) or "?"
		end)
	end
	local function Press(button)
		ButtonFX.Sound(ButtonFX.PRESS_SOUND)
		local id = ProductOf(button)
		if id <= 0 then
			Notify.Info("Coming soon!")
			return
		end
		local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, id)
		if not ok then
			warn("[ShopController] PromptProductPurchase: " .. tostring(err))
			Notify.Error("Could not open the Robux purchase")
		end
	end
	for _, item in ipairs(panel:GetDescendants()) do
		if item:IsA("GuiButton") and item:GetAttribute("PurchaseTemplate") then
			table.insert(buttons, item)
			local id = ProductOf(item)
			if id > 0 then
				byProduct[id] = byProduct[id] or {}
				table.insert(byProduct[id], item)
			end
			FillPrice(item)
			connect(item.Activated, function() Press(item) end)
		end
	end
	connect(MarketplaceService.PromptProductPurchaseFinished, function(userId, productId, purchased)
		if userId ~= player.UserId or not byProduct[productId] then return end
		if purchased then
			for _, entry in ipairs(ButtonFX.SUCCESS_SOUNDS) do ButtonFX.Sound(entry) end
			for _, button in ipairs(byProduct[productId]) do ButtonFX.Flash(button, Color3.new(1, 1, 1), 0.15, 0.4) end
			Notify.Success("Purchase complete!")
		else
			ButtonFX.Sound({"Button Pop", 0.15})
		end
	end)

	--..Time skips (2026-09-23): live quotes of the buyer's own rates..--
	local skipCards = {}
	for _, item in ipairs(panel:GetDescendants()) do
		if item:IsA("GuiObject") and tonumber(item:GetAttribute("TimeSkipSeconds")) then table.insert(skipCards, item) end
	end
	local quoteRemote
	local function RefreshTimeSkips()
		if #skipCards == 0 then return end
		if not quoteRemote then
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			quoteRemote = remotes and remotes:FindFirstChild("TimeSkipQuote")
			if not (quoteRemote and quoteRemote:IsA("RemoteFunction")) then quoteRemote = nil return end
		end
		for _, card in ipairs(skipCards) do
			task.spawn(function()
				local label = card:FindFirstChild("Quote") or card:FindFirstChild("Amount")
				if not label then return end
				local ok, quote = pcall(quoteRemote.InvokeServer, quoteRemote, tonumber(card:GetAttribute("TimeSkipSeconds")) or 0)
				if destroyed or not label.Parent then return end
				if ok and type(quote) == "table" then
					if card:GetAttribute("TimeSkipCurrency") == "Strength" then
						label.Text = "+" .. NumberAbbrev.Abbrev(math.floor(tonumber(quote.Strength) or 0))
					else
						label.Text = "+$" .. NumberAbbrev.Abbrev(math.floor(tonumber(quote.Cash) or 0))
					end
				elseif ok and quote == nil then
					-- throttled: keep the last quote
				else
					label.Text = "?"
				end
			end)
			task.wait(0.12) -- the server throttles quotes to 10 / s per player
		end
	end
	task.spawn(function()
		--.. one refresh as soon as the server's remote exists (the labels start as "..."), then while open
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
		if remotes then remotes:WaitForChild("TimeSkipQuote", 30) end
		if not destroyed then RefreshTimeSkips() end
		while not destroyed do
			if gui:GetAttribute("OpenPanel") == "Shop" then RefreshTimeSkips() end
			task.wait(TIMESKIP_REFRESH)
		end
	end)

	--..Tabs + sections..--
	local tabs = {} -- [section] = tab button
	for _, tab in ipairs(rail:GetChildren()) do
		local section = tab:IsA("GuiButton") and tab:GetAttribute("Section")
		if section then tabs[section] = tab end
	end
	local function HeaderOf(section)
		return catalog:FindFirstChild(section .. "Header") or catalog:FindFirstChild(section .. "Section")
	end
	local selected = DEFAULT_SECTION
	local hovering = {}
	local tabTokens = {}
	local function SetTabScale(tab, target)
		local scale = tab:FindFirstChild("TabScale")
		if not scale then return end
		local token = (tabTokens[tab] or 0) + 1
		tabTokens[tab] = token
		task.spawn(function()
			local from = scale.Scale
			ButtonFX.Animate(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
				scale.Scale = from + (target - from) * a
			end, function() return not destroyed and tabTokens[tab] == token end)
		end)
	end
	local function RefreshTabs()
		for section, tab in pairs(tabs) do
			local target = (section == selected) and TAB_SELECTED or 1
			local outline = tab:FindFirstChild("Outline")
			if outline then
				outline.Color = Color3.fromRGB(45, 43, 25)
				outline.Thickness = 3
			end
			if hovering[tab] then target += TAB_HOVER end
			SetTabScale(tab, target)
		end
	end
	local scrollToken = 0
	local tracking = true
	local function ScrollTo(section)
		local target = HeaderOf(section)
		if not target then return end
		scrollToken += 1
		local token = scrollToken
		task.defer(function()
			if destroyed then return end
			task.wait() -- one frame: the panel may have just become visible
			if token ~= scrollToken then return end
			local from = catalog.CanvasPosition.Y
			local maximum = math.max(0, catalog.AbsoluteCanvasSize.Y - catalog.AbsoluteWindowSize.Y)
			local y = math.clamp(from + (target.AbsolutePosition.Y - catalog.AbsolutePosition.Y), 0, maximum)
			tracking = false
			ButtonFX.Animate(SCROLL_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
				-- Recalculate while the opening animation changes the panel scale.
				local currentMaximum = math.max(0, catalog.AbsoluteCanvasSize.Y - catalog.AbsoluteWindowSize.Y)
				local currentTarget = math.clamp(catalog.CanvasPosition.Y + target.AbsolutePosition.Y - catalog.AbsolutePosition.Y, 0, currentMaximum)
				catalog.CanvasPosition = Vector2.new(0, from + (currentTarget - from) * a)
			end, function() return not destroyed and token == scrollToken end)
			if token == scrollToken then tracking = true end
		end)
	end
	local function Select(section, scroll)
		if not tabs[section] then return end
		selected = section
		RefreshTabs()
		if scroll then ScrollTo(section) end
	end
	for section, tab in pairs(tabs) do
		connect(tab.Activated, function()
			ButtonFX.Sound(ButtonFX.PRESS_SOUND)
			if panel:GetAttribute("RequestedTab") == section then
				Select(section, true)
			else
				panel:SetAttribute("RequestedTab", section)
			end
		end)
		connect(tab.MouseEnter, function() hovering[tab] = true RefreshTabs() end)
		connect(tab.MouseLeave, function() hovering[tab] = nil RefreshTabs() end)
	end
	connect(panel:GetAttributeChangedSignal("RequestedTab"), function()
		local section = panel:GetAttribute("RequestedTab")
		if tabs[section] then Select(section, true) end
	end)
	--.. the tab follows manual scrolling: the last header at or above the top of the window
	local function TrackScroll()
		if not tracking or destroyed then return end
		local atEnd = catalog.CanvasPosition.Y >= (catalog.AbsoluteCanvasSize.Y - catalog.AbsoluteWindowSize.Y) - 2
		local best, bestY
		for section in pairs(tabs) do
			local header = HeaderOf(section)
			if header then
				local offset = header.AbsolutePosition.Y - catalog.AbsolutePosition.Y
				if (offset <= 12 or atEnd) and (not bestY or offset > bestY) then best, bestY = section, offset end
			end
		end
		if best and best ~= selected then
			selected = best
			RefreshTabs()
		end
	end
	connect(catalog:GetPropertyChangedSignal("CanvasPosition"), TrackScroll)

	--.. land on the requested section every time the panel opens (it was invisible before)
	connect(gui:GetAttributeChangedSignal("OpenPanel"), function()
		if gui:GetAttribute("OpenPanel") ~= "Shop" then return end
		task.delay(0.05, function()
			if destroyed then return end
			for _, button in ipairs(buttons) do FillPrice(button) end
			Select(panel:GetAttribute("RequestedTab") or DEFAULT_SECTION, true)
			RefreshTimeSkips()
		end)
	end)
	Select(panel:GetAttribute("RequestedTab") or DEFAULT_SECTION, false)

	--..Dev hook..--
	connect(panel:GetAttributeChangedSignal("ShopDev"), function()
		local dev = panel:GetAttribute("ShopDev")
		if type(dev) ~= "string" or dev == "" then return end
		local kind, arg = dev:match("^(%a+):(.+)$")
		if kind == "tab" then
			panel:SetAttribute("RequestedTab", arg)
		elseif kind == "buy" then
			local button = buttons[tonumber(arg) or 0]
			if button then Press(button) end
		elseif kind == "quotes" then
			RefreshTimeSkips()
		end
		panel:SetAttribute("ShopDev", nil)
	end)

	return {
		Destroy = function()
			destroyed = true
			for _, connection in ipairs(connections) do connection:Disconnect() end
		end,
		Select = function(section) panel:SetAttribute("RequestedTab", section) end,
	}
end

return Shop
