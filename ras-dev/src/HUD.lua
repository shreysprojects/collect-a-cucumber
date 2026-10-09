--[[---------------------------------------DESCRIPTION------------------------------------------
	HUD module. GUIFramework spawns the empty "Interface" frame into PlayerGui.HUD.Base
	as "HUD" (self.UI); MainUI (the editable frame in ServerStorage.Assets.UserInterfaces.HUD,
	moved under this module by SetupInterfaces) is cloned into it here.
	SetProgress writes Level.Frame.TextLabel as "Level 1" and Frame.XPLabel as "0/10",
	sizes MainUI.Level.BackFrame to the current XP fraction, and sets
	MainUI.Coins to the player's coin balance.

	While a snowball is launched, MainUI.DistanceRolled shows how far the ball
	has rolled and MainUI.CoinsMade shows coins earned on that run. Distance
	only changes its text. CoinsMade pops (scale, a gold flash, and a rising
	+amount) each time more coins land. Both labels stay hidden until launch
	and hide again when the ride ends.

	Shop / Mountains / Rebirth buttons open the frame of the same name IF one exists:
	  1. a panel already spawned by this module,
	  2. a template under this module (SetupInterfaces moves every frame from
	     ServerStorage.Assets.UserInterfaces.HUD here: Shop, Mountains, ...),
	  3. anything under ReplicatedStorage.Assets.UserInterfaces,
	  4. any GuiObject of that name already in PlayerGui.
	Rebirth uses the Studio frame when one exists. Its Foreground.Buy button is
	the coin purchase: the label is the rebirth cost, grayed until the player
	can afford it, and a press invokes Rebirth. A generated frame is only built
	when Studio has not supplied one.

	Mountains cards (Frostpeak, Candy, ...) show Travel when unlocked and Locked
	when not. Travel invokes TravelToMountain (teleport to that mountain's place).
	Frostpeak starts unlocked; other unlocks persist on the player DataStore.

	Shop clones Foreground.Template.Item into ScrollingFrame for every snowball
	or snowball launcher. Blasters / Snowballs switch the list; the active tab
	is grayed out and cannot be pressed again until the other tab is selected.
	Each item's Foreground Name label is the snowball or launcher name. The
	Multiplier label is the catalog multiplier (2 ^ (Order - 1): 1x, 2x, 4x, 8x). Snowball cards set
	Foreground.Info.Icon from the catalog image. Classic and
	Wooden Shovel start owned and equipped; their Buy button reads EQUIPPED
	and its UIGradients (including the UIStroke gradient) are shifted to red.
	Owned (but not equipped) items say EQUIP, keep those gradients' original
	green, and invoke EquipSnowball / EquipLauncher. Only the next locked item
	can be bought, and only once its mountain difficulty is unlocked. Later
	ones stay unavailable, with the same gradients desaturated to a darker gray,
	until the one before them is unlocked. Snowball order N and launcher order N
	share that mountain. A card whose mountain is still locked reads
	"BEAT <previous mountain>" instead of its price (PlayerProgress.GearLockedBy
	on the replicated UnlockedMountains: the same gate the server applies).
	Prices use a $ prefix.
	The Buy label and its TextShadow always show the same string (the Buy
	TextButton's own Text stays empty when it has a label). The Buy button grows
	slightly on hover while it can be pressed (attribute ShopCanBuy). Gray cards
	and an unaffordable Rebirth stay Active (Active = false would stop Activated)
	so a press explains itself; only an EQUIPPED card is inert.

	Buying goes through ReFunction BuySnowball / BuyLauncher, which answer true or
	false and a reason. Every press pops (PurchaseFX.Press); a purchase plays
	PurchaseFX.Success on the button, pops the card with a gold "UNLOCKED!" and
	shows a green toast (Notify); a refusal shakes the button red and says why
	("Need $120 more", "Beat Frostpeak to unlock Coal", "Buy Muddy first").
	A bought card then reads EQUIP (PlayerProgress.EQUIP_ON_BUY = true makes the
	server equip it instead). Rebirth plays the same press / success / fail
	effects with a "REBIRTH!" float. PurchaseFX.WatchPlayers bursts sparkles off
	any player whose gear or rebirths go up by one.

	Panels pop in from the center (UIScale 0.85 -> 1) and pop out on close.
	PanelManager keeps one open at a time and applies FOV + world blur.
	Shop / Mountains hide MainUI while open and restore it when closed.
	Walking into StartPlatform.Circles.ShopCircle / MountainCircle opens that
	panel on enter. PlayerGui attribute "PanelOpen" holds the open panel's name
	(hold-to-launch ignores presses while it is set). Dev hook: set the
	PlayerGui attribute "DevPanel" to a panel name to toggle it, or "DevPress"
	to "Snowballs:Coal" / "Blasters:Leather Sling" / "Rebirth" to press that
	Buy button exactly as a click would (evals cannot FireServer).

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local mountainPlaces = require(ReplicatedStorage.Assets.Modules.Shared.MountainPlaces)()
local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local playerProgress = require(ReplicatedStorage.Assets.Modules.Shared.PlayerProgress)()
local snowballs = require(ReplicatedStorage.Assets.Modules.Shared.Snowballs)
local snowballLaunchers = require(ReplicatedStorage.Assets.Modules.Shared.SnowballLaunchers)
local PanelManager = require(ReplicatedStorage.Assets.Modules.Client.UI.PanelManager)
local UIUtils = require(ReplicatedStorage.Assets.Modules.Client.UI.UIUtils)
local HUDLayout = require(ReplicatedStorage.Assets.Modules.Client.UI.HUDLayout)
local PurchaseFX = require(ReplicatedStorage.Assets.Modules.Client.UI.PurchaseFX)
local Audio = require(ReplicatedStorage.Assets.Modules.Client.Audio)
local Notify = require(ReplicatedStorage.Assets.Modules.Client.UI.Notify)

local BUTTON_PANELS = {
	Shop = "Shop",
	Mountains = "Mountains",
	Rebirth = "Rebirth",
}
local CIRCLE_PANELS = {
	ShopCircle = "Shop",
	MountainCircle = "Mountains",
}
local HIDES_MAIN = {
	Shop = true,
	Mountains = true,
	Rebirth = true,
}
local REBIRTH_CAN = Color3.fromRGB(46, 160, 90)
local REBIRTH_CANT = Color3.fromRGB(78, 84, 96)
local MENU_DISPLAY_ORDER = 5 -- panels draw above the HUD buttons
local DEFAULT_SHOP_TAB = "Snowballs"
local TAB_GRAY = Color3.fromRGB(118, 118, 118)
local TAB_GRAY_TEXT = Color3.fromRGB(188, 188, 188)
local TAB_GRAY_MIX = 0.62
local SHOP_BUY_OWNED = "EQUIP"
local SHOP_BUY_EQUIPPED = "EQUIPPED"
local SHOP_GRAY_DARKEN = 0.62
local SHOP_HOVER_SCALE = 1.08
local SHOP_HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHOP_LOCKED = "BEAT %s" -- button text while the item's mountain is locked (previous mountain)
local SHOP_LOCKED_TOAST = "Beat %s to unlock %s"
local SHOP_IN_ORDER_TOAST = "Buy %s first"
local SHOP_BOUGHT_TOAST = "%s unlocked!"
local SHOP_BOUGHT_FLOAT = "UNLOCKED!"
local SHOP_CARD_POP = 1.12
local NEED_MORE_TOAST = "Need %s more"
local SHOP_REFUSED_TOAST = {
	Owned = "You already own that",
	Invalid = "Can't buy that",
}
local SHOP_ERROR_TOAST = "Can't buy that right now"
local REBIRTH_FLOAT = "REBIRTH!"
local REBIRTH_TOAST = "Rebirth %d!"
local RING_HEIGHT_PAD = 12
local POP_IN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POP_START_SCALE = 0.85
local COIN_POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local COIN_FLASH_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local COIN_FLOAT = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local COIN_FLASH = Color3.fromRGB(255, 236, 120)

local api = {}
api.Connections = {}
api.Panels = {}
api.MountainTravel = {}
api.ShopConnections = {}
api.ShopTabLooks = {}
api.ShopBuyLooks = {}
api.ShopGradientLooks = {}
api.RebirthBuyLooks = {}
api.RebirthGradientLooks = {}
api.PanelShown = {}
api.PanelTweens = {}
api.PanelRegistered = {}

local function getPlayerGui()
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function getWindow()
	local playerGui = getPlayerGui()
	local menu = playerGui:FindFirstChild("Menu")
	if menu and menu:IsA("ScreenGui") and menu.DisplayOrder < MENU_DISPLAY_ORDER then
		menu.DisplayOrder = MENU_DISPLAY_ORDER
	end
	local basis = menu and menu:FindFirstChild("Basis")
	local window = basis and basis:FindFirstChild("Window")
	return window or playerGui:FindFirstChild("HUD") or playerGui
end

local function setPanelOpen(name)
	getPlayerGui():SetAttribute("PanelOpen", name)
end

function api:SetMainVisible(visible)
	local main = self.MainUI
	if main then
		main.Visible = visible
	end
end

function api:SyncMainVisibility()
	for name, panel in self.Panels do
		if HIDES_MAIN[name] and panel.Parent and (panel.Visible or self.PanelShown[name]) then
			self:SetMainVisible(false)
			return
		end
	end
	self:SetMainVisible(true)
end

local function cancelPanelTween(self, name)
	local tween = self.PanelTweens[name]
	if tween then
		tween:Cancel()
		self.PanelTweens[name] = nil
	end
end

local function ensureCenterAnchor(panel)
	if panel:GetAttribute("PanelCentered") then
		return
	end
	panel:SetAttribute("PanelCentered", true)

	local anchor = panel.AnchorPoint
	if anchor.X == 0.5 and anchor.Y == 0.5 then
		return
	end

	local dx = 0.5 - anchor.X
	local dy = 0.5 - anchor.Y
	local size = panel.Size
	local position = panel.Position
	panel.Position = UDim2.new(
		position.X.Scale + dx * size.X.Scale,
		position.X.Offset + dx * size.X.Offset,
		position.Y.Scale + dy * size.Y.Scale,
		position.Y.Offset + dy * size.Y.Offset
	)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
end

local function getPanelScale(panel)
	local named = panel:FindFirstChild("PanelScale")
	if named and named:IsA("UIScale") then
		return named
	end

	local uiScale = panel:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = panel
	end
	uiScale.Name = "PanelScale"
	return uiScale
end

-- Returns template, alreadySpawned
local function findFrame(self, name)
	local spawned = self.Panels[name]
	if spawned and spawned.Parent then
		return spawned, true
	end

	local template = script:FindFirstChild(name)
	if template and template:IsA("GuiObject") then
		return template, false
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local interfaces = assets and assets:FindFirstChild("UserInterfaces")
	if interfaces then
		for _, desc in interfaces:GetDescendants() do
			if desc:IsA("GuiObject") and desc.Name == name and not desc:IsDescendantOf(script) then
				return desc, false
			end
		end
	end

	for _, desc in getPlayerGui():GetDescendants() do
		if desc:IsA("GuiObject") and desc.Name == name and not (self.UI and desc:IsDescendantOf(self.UI)) then
			return desc, true
		end
	end

	return nil, false
end

function api:DisconnectMountainTravel()
	for _, connection in self.MountainTravel do
		if connection then
			connection:Disconnect()
		end
	end
	table.clear(self.MountainTravel)
end

local function unlockedMap()
	return playerProgress.DecodeUnlocks(Players.LocalPlayer:GetAttribute("UnlockedMountains"))
end

local function formatMeters(n)
	local text = tostring(math.floor(n))
	local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", "")) .. " m"
end

local function mountainCards(root)
	if not root then
		return nil, {}
	end
	local scroll = root:FindFirstChild("ScrollingFrame", true)
	if not scroll then
		return nil, {}
	end

	local cards = {}
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			local mountainId = mountainPlaces.NormalizeMountainId(child.Name)
			if mountainId then
				table.insert(cards, { Card = child, MountainId = mountainId })
			end
		end
	end
	return scroll, cards
end

local function findTravelTemplate(cards)
	for _, item in cards do
		local travel = item.Card:FindFirstChild("Travel", true)
		if travel and travel:IsA("GuiButton") then
			return travel
		end
	end
	return nil
end

function api:TravelToMountain(mountainId)
	if self.Traveling then
		return
	end
	self.Traveling = true
	Audio.Play("Teleport")
	task.spawn(function()
		local ok, err = ReplicatedStorage.ReEvent.ReFunction:InvokeServer("TravelToMountain", mountainId)
		if not ok then
			warn("[CLIENT]: Travel failed:", err)
		end
		self.Traveling = false
	end)
end

function api:WireMountainTravel(button, mountainId)
	if not (button and button:IsA("GuiButton")) then
		return
	end
	if self.MountainTravel[button] then
		return
	end
	self.MountainTravel[button] = button.Activated:Connect(function()
		self:TravelToMountain(mountainId)
	end)
end

function api:ApplyMountainLocks(root)
	local _, cards = mountainCards(root)
	if #cards == 0 then
		return false
	end

	local unlocks = unlockedMap()
	local current = mountainPlaces.GetCurrentMountainId()
	local template = findTravelTemplate(cards)

	for _, item in cards do
		local card = item.Card
		local mountainId = item.MountainId
		local isUnlocked = unlocks[mountainId] == true
		local isHere = mountainId == current

		local locked = card:FindFirstChild("Locked", true)
		local travel = card:FindFirstChild("Travel", true)
		if isUnlocked and not (travel and travel:IsA("GuiButton")) and template then
			travel = template:Clone()
			travel.Name = "Travel"
			travel.Parent = card
		end

		if locked then
			locked.Visible = not isUnlocked
		end
		local difficultyLabel = card:FindFirstChild("Difficulty", true)
		if difficultyLabel and (difficultyLabel:IsA("TextLabel") or difficultyLabel:IsA("TextButton")) then
			local level = mountainConfig:GetDifficulty(mountainId)
			local name = mountainConfig:GetDifficultyName(mountainId)
			difficultyLabel.Text = if level and name then tostring(level) .. " · " .. name else ""
		end
		local lengthLabel = card:FindFirstChild("Length", true) or card:FindFirstChild("Distance", true)
		if lengthLabel and (lengthLabel:IsA("TextLabel") or lengthLabel:IsA("TextButton")) then
			local length = mountainConfig:GetLength(mountainId)
			if length then
				lengthLabel.Text = formatMeters(length)
			end
		end
		if travel then
			travel.Visible = isUnlocked
			if travel:IsA("GuiButton") then
				travel.Active = isUnlocked and not isHere
				travel.AutoButtonColor = travel.Active
				if travel:IsA("TextButton") then
					travel.Text = if isHere then "HERE" else "Travel"
				end
				if root ~= script:FindFirstChild("Mountains") then
					self:WireMountainTravel(travel, mountainId)
				end
			end
		end
	end

	return true
end

function api:RefreshMountainsPanel()
	local spawned = self.Panels.Mountains
	if spawned and spawned.Parent then
		self:ApplyMountainLocks(spawned)
	end

	local template = script:FindFirstChild("Mountains")
	if template and template:IsA("GuiObject") and template ~= spawned then
		self:ApplyMountainLocks(template)
	end
end

function api:SetupMountainsPanel(panel)
	if not panel then
		return
	end
	self:ApplyMountainLocks(panel)
end

local MULTIPLIER_SUFFIXES = { "K", "M", "B", "T" }

local function formatCompact(value, prefix, minimum)
	local n = tonumber(value) or 0
	if n < 1000 then
		if minimum and n < minimum then
			n = minimum
		end
		return (prefix or "") .. tostring(math.floor(n + 0.5))
	end

	local tier = math.floor(math.log10(n) / 3)
	if tier > #MULTIPLIER_SUFFIXES then
		tier = #MULTIPLIER_SUFFIXES
	end
	local scaled = n / (10 ^ (tier * 3))
	if scaled >= 999.95 and tier < #MULTIPLIER_SUFFIXES then
		tier += 1
		scaled = n / (10 ^ (tier * 3))
	end

	local text = string.format("%.1f", scaled):gsub("%.0$", "")
	return (prefix or "") .. text .. MULTIPLIER_SUFFIXES[tier]
end

local function formatMultiplier(value)
	return formatCompact(value, "x", 1)
end

local function formatPrice(value)
	return formatCompact(value, "$", 0)
end

local function formatRate(value)
	local rounded = math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
	local text = string.format("%.2f", rounded)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return text .. "x"
end

local function shopCatalog(tab)
	if tab == "Blasters" then
		return snowballLaunchers.List
	end
	return snowballs.List
end

local function nextShopOrder(tab, owned)
	for _, def in shopCatalog(tab) do
		if owned[def.Name] ~= true then
			return def.Order
		end
	end
	return nil
end

local function shopOrderForSale(order, owned, tab)
	if order ~= nextShopOrder(tab, owned) then
		return false
	end
	return playerProgress.GearLockedBy(unlockedMap(), order) == nil
end

-- The mountain to beat before gear of this order is sold, or nil when its mountain is open.
local function shopUnlockMountain(order)
	local lockedBy = playerProgress.GearLockedBy(unlockedMap(), order)
	if not lockedBy then
		return nil
	end
	return mountainConfig:GetPreviousMountain(lockedBy) or lockedBy
end

local function shopLockText(order)
	local beat = shopUnlockMountain(order)
	if not beat then
		return nil
	end
	return string.format(SHOP_LOCKED, string.upper(mountainConfig:GetDisplayName(beat)))
end

local function shopHoverScale(buy)
	local hover = buy:FindFirstChild("HoverScale")
	if hover and hover:IsA("UIScale") then
		return hover
	end
	hover = Instance.new("UIScale")
	hover.Name = "HoverScale"
	hover.Scale = 1
	hover.Parent = buy
	return hover
end

local function bindShopBuyHover(buy)
	if buy:GetAttribute("ShopHoverBound") then
		return
	end
	buy:SetAttribute("ShopHoverBound", true)
	buy:SetAttribute("HoverScaleBound", true)
	local hover = shopHoverScale(buy)
	hover.Scale = 1
	local tween = nil
	local function tweenTo(scale)
		if tween then
			tween:Cancel()
		end
		tween = TweenService:Create(hover, SHOP_HOVER, { Scale = scale })
		tween:Play()
	end
	buy.MouseEnter:Connect(function()
		if buy:GetAttribute("ShopCanBuy") == true and UserInputService.PreferredInput ~= Enum.PreferredInput.Touch then
			tweenTo(SHOP_HOVER_SCALE)
		end
	end)
	buy.MouseLeave:Connect(function()
		tweenTo(1)
	end)
end

local function findShopScroll(root)
	return root and root:FindFirstChild("ScrollingFrame", true)
end

local function findShopItemTemplate(root)
	if not root then
		return nil
	end
	local templateFolder = root:FindFirstChild("Template", true)
	if not templateFolder then
		return nil
	end
	local item = templateFolder:FindFirstChild("Item")
	if item and item:IsA("GuiObject") then
		return item
	end
	return nil
end

local function findShopTabButton(root, name)
	if not root then
		return nil
	end
	local button = root:FindFirstChild(name)
	if button and button:IsA("GuiButton") then
		return button
	end
	return nil
end

local function findShopBuy(item)
	if not item then
		return nil
	end
	local buy = item:FindFirstChild("Buy", true)
	if buy and buy:IsA("GuiButton") then
		return buy
	end
	return nil
end

local function eachShopBuyGradient(buy, callback)
	for _, descendant in buy:GetDescendants() do
		if descendant:IsA("UIGradient") then
			callback(descendant)
		end
	end
end

local function mapGradient(sequence, transform)
	local keypoints = table.create(#sequence.Keypoints)
	for index, keypoint in sequence.Keypoints do
		keypoints[index] = ColorSequenceKeypoint.new(keypoint.Time, transform(keypoint.Value))
	end
	return ColorSequence.new(keypoints)
end

local function grayColor(color)
	local luminance = (color.R * 0.299 + color.G * 0.587 + color.B * 0.114) * SHOP_GRAY_DARKEN
	return Color3.new(luminance, luminance, luminance)
end

local function redColor(color)
	local _, saturation, value = color:ToHSV()
	return Color3.fromHSV(0, saturation, value)
end

local function rememberGradientLook(store, gradient)
	local look = store[gradient]
	if look then
		return look
	end
	local green = gradient.Color
	look = {
		Green = green,
		Red = mapGradient(green, redColor),
		Gray = mapGradient(green, grayColor),
	}
	store[gradient] = look
	return look
end

local function setGuiText(gui, text)
	if gui and (gui:IsA("TextLabel") or gui:IsA("TextButton")) then
		gui.Text = text
	end
end

local function setNamedImage(root, name, image)
	if type(image) ~= "string" or image == "" then
		return
	end
	local node = root and root:FindFirstChild(name, true)
	if not node or node == root then
		return
	end
	if node:IsA("ImageLabel") or node:IsA("ImageButton") then
		node.Image = image
		return
	end
	local imageLabel = node:FindFirstChildWhichIsA("ImageLabel", true)
	if imageLabel then
		imageLabel.Image = image
	end
end

local function setNamedLabel(root, name, text)
	local node = root and root:FindFirstChild(name, true)
	if not node or node == root then
		return
	end

	local label = node
	if not (label:IsA("TextLabel") or label:IsA("TextButton")) then
		label = node:FindFirstChildWhichIsA("TextLabel", true)
	end
	setGuiText(label, text)

	local shadow = label and label:FindFirstChild("TextShadow")
	if not (shadow and (shadow:IsA("TextLabel") or shadow:IsA("TextButton"))) and label and label.Parent then
		shadow = label.Parent:FindFirstChild("TextShadow")
	end
	if shadow and shadow ~= label and (shadow == node or shadow:IsDescendantOf(node)) then
		setGuiText(shadow, text)
	end
end

local function setButtonText(button, text)
	local label = button:FindFirstChild("TextLabel", true)
	if button:IsA("TextButton") then
		-- A Studio button draws its text with a TextLabel (+ TextShadow); its own Text stays empty.
		local drawn = label and (label:IsA("TextLabel") or label:IsA("TextButton"))
		button.Text = if drawn then "" else text
	end
	setGuiText(label, text)

	local shadow = label and label:FindFirstChild("TextShadow")
	if not (shadow and (shadow:IsA("TextLabel") or shadow:IsA("TextButton"))) and label and label.Parent then
		shadow = label.Parent:FindFirstChild("TextShadow")
	end
	if not (shadow and (shadow:IsA("TextLabel") or shadow:IsA("TextButton"))) then
		shadow = button:FindFirstChild("TextShadow", true)
	end
	setGuiText(shadow, text)
end

-- Shop prices live on a TextLabel plus its TextShadow (child or sibling). Rebirth uses the same pair.
local function setPriceText(root, text)
	if not root then
		return
	end
	for _, desc in root:GetDescendants() do
		if desc.Name ~= "TextLabel" or not (desc:IsA("TextLabel") or desc:IsA("TextButton")) then
			continue
		end
		local shadow = desc:FindFirstChild("TextShadow")
		if not (shadow and (shadow:IsA("TextLabel") or shadow:IsA("TextButton"))) and desc.Parent then
			shadow = desc.Parent:FindFirstChild("TextShadow")
		end
		if shadow and shadow ~= desc and (shadow:IsA("TextLabel") or shadow:IsA("TextButton")) then
			setGuiText(desc, text)
			setGuiText(shadow, text)
			return
		end
	end
end

local function shopOwnedMap(tab)
	local player = Players.LocalPlayer
	if tab == "Blasters" then
		return playerProgress.DecodeNames(player:GetAttribute("UnlockedLaunchers"), playerProgress.STARTER_LAUNCHER)
	end
	return playerProgress.DecodeNames(player:GetAttribute("UnlockedSnowballs"), playerProgress.STARTER_SNOWBALL)
end

local function shopEquippedName(tab)
	local player = Players.LocalPlayer
	if tab == "Blasters" then
		local name = player:GetAttribute("EquippedLauncher")
		if type(name) == "string" and name ~= "" then
			return name
		end
		return playerProgress.STARTER_LAUNCHER
	end
	local name = player:GetAttribute("EquippedSnowball")
	if type(name) == "string" and name ~= "" then
		return name
	end
	return playerProgress.STARTER_SNOWBALL
end

local function rememberButtonLook(store, button)
	if store[button] then
		return store[button]
	end
	local look = {
		BackgroundColor3 = button.BackgroundColor3,
		BackgroundTransparency = button.BackgroundTransparency,
		AutoButtonColor = button.AutoButtonColor,
	}
	if button:IsA("TextButton") then
		look.TextColor3 = button.TextColor3
		look.TextTransparency = button.TextTransparency
	end
	if button:IsA("ImageButton") then
		look.ImageColor3 = button.ImageColor3
		look.ImageTransparency = button.ImageTransparency
	end
	store[button] = look
	return look
end

local function applyButtonLook(button, look, grayed)
	button.AutoButtonColor = if grayed then false else look.AutoButtonColor
	if grayed then
		button.BackgroundColor3 = look.BackgroundColor3:Lerp(TAB_GRAY, TAB_GRAY_MIX)
		if look.TextColor3 then
			button.TextColor3 = look.TextColor3:Lerp(TAB_GRAY_TEXT, TAB_GRAY_MIX)
		end
		if look.ImageColor3 then
			button.ImageColor3 = look.ImageColor3:Lerp(TAB_GRAY, TAB_GRAY_MIX)
		end
	else
		button.BackgroundColor3 = look.BackgroundColor3
		if look.TextColor3 then
			button.TextColor3 = look.TextColor3
		end
		if look.ImageColor3 then
			button.ImageColor3 = look.ImageColor3
		end
		if look.TextTransparency then
			button.TextTransparency = look.TextTransparency
		end
		if look.ImageTransparency then
			button.ImageTransparency = look.ImageTransparency
		end
	end
end

function api:DisconnectShop()
	for _, connection in self.ShopConnections do
		if connection then
			connection:Disconnect()
		end
	end
	table.clear(self.ShopConnections)
	table.clear(self.ShopBuyLooks)
	table.clear(self.ShopGradientLooks)
	self.ShopWired = nil
	self.ShopPanelFilled = nil
end

function api:ApplyShopTabButtons(panel, tab)
	for _, name in { "Snowballs", "Blasters" } do
		local button = findShopTabButton(panel, name)
		if not (button and button:IsA("GuiButton")) then
			continue
		end

		local look = rememberButtonLook(self.ShopTabLooks, button)
		local selected = name == tab
		button.Active = not selected
		applyButtonLook(button, look, selected)
	end
end

function api:ApplyShopItemState(item, owned, equipped, forSale, lockText)
	local buy = findShopBuy(item)
	if not (buy and buy:IsA("GuiButton")) then
		return
	end

	local look = rememberButtonLook(self.ShopBuyLooks, buy)
	local text
	local active
	local tint
	if equipped then
		text = SHOP_BUY_EQUIPPED
		active = false
		tint = "Red"
	elseif owned then
		text = SHOP_BUY_OWNED
		active = true
		tint = "Green"
	elseif forSale then
		text = formatPrice(item:GetAttribute("ShopPrice"))
		active = true
		tint = "Green"
	else
		text = lockText or formatPrice(item:GetAttribute("ShopPrice"))
		active = false
		tint = "Gray"
	end

	setButtonText(buy, text)
	-- Active = false stops Activated, so a gray card stays Active to answer a press with its reason.
	-- ShopCanBuy is the real "pressable" state (hover, colour); only EQUIPPED is inert.
	buy.Active = not equipped
	buy:SetAttribute("ShopCanBuy", active)
	applyButtonLook(buy, look, false)
	buy.AutoButtonColor = if active then look.AutoButtonColor else false

	eachShopBuyGradient(buy, function(gradient)
		local colors = rememberGradientLook(self.ShopGradientLooks, gradient)
		gradient.Color = colors[tint]
	end)
	local hover = buy:FindFirstChild("HoverScale")
	if hover and hover:IsA("UIScale") and not active then
		hover.Scale = 1
	end
end

function api:ApplyShopItemStates(panel, tab)
	if not panel then
		return
	end
	tab = tab or self.ShopTab or DEFAULT_SHOP_TAB
	local owned = shopOwnedMap(tab)
	local equipped = shopEquippedName(tab)
	local scroll = findShopScroll(panel)
	if not scroll then
		return
	end
	for _, child in scroll:GetChildren() do
		if child:GetAttribute("ShopItem") then
			local order = child:GetAttribute("Order")
			self:ApplyShopItemState(
				child,
				owned[child.Name] == true,
				child.Name == equipped,
				shopOrderForSale(order, owned, tab),
				shopLockText(order)
			)
		end
	end
end

function api:RefreshShopPanel()
	local spawned = self.Panels.Shop
	if spawned and spawned.Parent then
		self:ApplyShopItemStates(spawned, self.ShopTab)
	end
end

-- Toast text for a purchase the client or the server refused.
local function shopRefusalText(reason, def, tab)
	if reason == "NotEnoughCoins" then
		local coins = math.max(0, math.floor(tonumber(Players.LocalPlayer:GetAttribute("Coins")) or 0))
		return string.format(NEED_MORE_TOAST, formatPrice(math.max(1, (def.Price or 0) - coins)))
	end
	if reason == "MountainLocked" then
		local beat = shopUnlockMountain(def.Order) or mountainConfig:GetPreviousMountain(def.MountainId) or def.MountainId
		return string.format(SHOP_LOCKED_TOAST, mountainConfig:GetDisplayName(beat), def.Name)
	end
	if reason == "BuyInOrder" then
		local nextOrder = nextShopOrder(tab, shopOwnedMap(tab))
		local catalog = if tab == "Blasters" then snowballLaunchers else snowballs
		local nextDef = nextOrder and catalog:GetByOrder(nextOrder)
		if nextDef then
			return string.format(SHOP_IN_ORDER_TOAST, nextDef.Name)
		end
	end
	return SHOP_REFUSED_TOAST[reason] or SHOP_ERROR_TOAST
end

-- Equip an owned card, or buy the next one. Every press pops; the answer succeeds or fails loudly.
function api:PressShopBuy(buy, item, def, tab)
	if self.ShopBusy then
		return
	end
	local owned = shopOwnedMap(tab)
	if owned[def.Name] == true then
		if def.Name == shopEquippedName(tab) then
			return
		end
		PurchaseFX.Press(buy)
		ReplicatedStorage.ReEvent:FireServer(if tab == "Blasters" then "EquipLauncher" else "EquipSnowball", def.Name)
		return
	end

	PurchaseFX.Press(buy)
	local refusal = nil
	if shopUnlockMountain(def.Order) then
		refusal = "MountainLocked"
	elseif def.Order ~= nextShopOrder(tab, owned) then
		refusal = "BuyInOrder"
	end
	if refusal then
		PurchaseFX.Fail(buy)
		Notify.Error(shopRefusalText(refusal, def, tab))
		return
	end

	self.ShopBusy = true
	local invoked, ok, reason = pcall(function()
		return ReplicatedStorage.ReEvent.ReFunction:InvokeServer(if tab == "Blasters" then "BuyLauncher" else "BuySnowball", def.Name)
	end)
	self.ShopBusy = false
	if invoked and ok == true then
		PurchaseFX.Success(buy)
		PurchaseFX.Celebrate(item:FindFirstChild("Foreground") or buy, SHOP_BOUGHT_FLOAT, SHOP_CARD_POP)
		Notify.Success(string.format(SHOP_BOUGHT_TOAST, def.Name))
	else
		if not invoked then
			warn("[CLIENT]: Shop purchase failed:", ok)
		end
		PurchaseFX.Fail(buy)
		Notify.Error(shopRefusalText(if invoked then reason else nil, def, tab))
	end
	self:RefreshShopPanel()
end

function api:FillShopItems(panel, tab)
	local scroll = findShopScroll(panel)
	local template = findShopItemTemplate(panel)
	if not scroll then
		warn("[CLIENT]: Shop ScrollingFrame not found")
		return
	end
	if not template then
		warn("[CLIENT]: Shop Template.Item not found")
		return
	end

	template.Visible = false
	local templateFolder = template.Parent
	if templateFolder and templateFolder:IsA("GuiObject") then
		templateFolder.Visible = false
	end

	for _, child in scroll:GetChildren() do
		if child:GetAttribute("ShopItem") then
			child:Destroy()
		elseif child:IsA("GuiObject") then
			child.Visible = false
		end
	end

	table.clear(self.ShopBuyLooks)
	table.clear(self.ShopGradientLooks)

	local catalog = shopCatalog(tab)
	local owned = shopOwnedMap(tab)
	local equipped = shopEquippedName(tab)
	for _, def in catalog do
		local item = template:Clone()
		item.Name = def.Name
		item.Visible = true
		item.LayoutOrder = def.Order
		item:SetAttribute("ShopItem", true)
		item:SetAttribute("ShopTab", tab)
		item:SetAttribute("Order", def.Order)
		item:SetAttribute("ShopPrice", def.Price)

		setNamedLabel(item, "Name", def.Name)
		setNamedLabel(item, "Multiplier", formatMultiplier(def.Multiplier))
		setNamedImage(item, "Icon", def.Icon)

		local isOwned = owned[def.Name] == true
		self:ApplyShopItemState(item, isOwned, def.Name == equipped, shopOrderForSale(def.Order, owned, tab), shopLockText(def.Order))

		local buy = findShopBuy(item)
		if buy and buy:IsA("GuiButton") then
			bindShopBuyHover(buy)
			buy.Activated:Connect(function()
				self:PressShopBuy(buy, item, def, tab)
			end)
		end

		item.Parent = scroll
	end
end

function api:SetShopTab(panel, tab)
	if tab ~= "Snowballs" and tab ~= "Blasters" then
		return
	end
	if self.ShopTab == tab and self.ShopPanelFilled == panel then
		self:ApplyShopTabButtons(panel, tab)
		self:ApplyShopItemStates(panel, tab)
		return
	end

	self.ShopTab = tab
	self.ShopPanelFilled = panel
	Audio.Play("UITab")
	self:ApplyShopTabButtons(panel, tab)
	self:FillShopItems(panel, tab)
end

function api:WireShopTabs(panel)
	local function wire(name, tab)
		local button = findShopTabButton(panel, name)
		if not (button and button:IsA("GuiButton")) then
			warn("[CLIENT]: Shop tab not found:", name)
			return
		end
		table.insert(self.ShopConnections, button.Activated:Connect(function()
			if self.ShopTab == tab then
				return
			end
			self:SetShopTab(panel, tab)
		end))
	end

	wire("Snowballs", "Snowballs")
	wire("Blasters", "Blasters")
end

function api:SetupShopPanel(panel)
	if not panel then
		return
	end
	if self.ShopWired ~= panel then
		self:DisconnectShop()
		self.ShopWired = panel
		self:WireShopTabs(panel)
	end
	self:SetShopTab(panel, self.ShopTab or DEFAULT_SHOP_TAB)
end

function api:DisconnectRebirth()
	if self.RebirthConnection then
		self.RebirthConnection:Disconnect()
		self.RebirthConnection = nil
	end
	local panel = self.Panels.Rebirth
	local buy = panel and (panel:FindFirstChild("Buy", true) or panel:FindFirstChild("Confirm", true))
	if buy then
		buy:SetAttribute("RebirthWired", nil)
	end
	self.RebirthBusy = false
end

function api:DisconnectEvents()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	self:DisconnectMountainTravel()
	self:DisconnectShop()
	self:DisconnectRebirth()
	self:EndRunReadout()
	self.CircleWatch = nil
	self.InsideCircle = nil
end

function api:ConnectEvents()
	self:DisconnectEvents()
end

function api:HidePanel(name)
	local panel = self.Panels[name]
	if not panel or not panel.Parent then
		self.PanelShown[name] = false
		return
	end
	if self.PanelShown[name] ~= true then
		return
	end

	self.PanelShown[name] = false
	PanelManager.notifyClosed(name)
	Audio.Play("UIClose")
	if getPlayerGui():GetAttribute("PanelOpen") == name then
		setPanelOpen(nil)
	end

	cancelPanelTween(self, name)
	ensureCenterAnchor(panel)
	local uiScale = getPanelScale(panel)
	local tween = TweenService:Create(uiScale, POP_OUT, { Scale = POP_START_SCALE })
	self.PanelTweens[name] = tween
	tween:Play()
	tween.Completed:Once(function()
		if self.PanelTweens[name] == tween then
			self.PanelTweens[name] = nil
		end
		if not self.PanelShown[name] then
			panel.Visible = false
			uiScale.Scale = 1
			self:SyncMainVisibility()
		end
	end)
	self:SyncMainVisibility()
end

function api:WirePanel(panel)
	local close = panel:FindFirstChild("X", true)
	if close and close:IsA("GuiButton") then
		table.insert(self.Connections, close.Activated:Connect(function()
			self:HidePanel(panel.Name)
		end))
	end
	local hoverWatch = UIUtils.bindHoverScaleAll(panel, nil, true)
	if hoverWatch then
		table.insert(self.Connections, hoverWatch)
	end
end

function api:ClosePanels(except)
	for name, panel in self.Panels do
		if name ~= except and panel.Parent then
			self:HidePanel(name)
		end
	end
	if not except then
		setPanelOpen(nil)
	end
end

local function rebirthLabel(parent, name, text, height, font, color, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.Font = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = text
	label.Parent = parent
	return label
end

local function buildRebirthFrame()
	local panel = Instance.new("Frame")
	panel.Name = "Rebirth"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(460, 520)
	panel.BackgroundColor3 = Color3.fromRGB(16, 24, 38)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 5

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(150, 186, 220)
	stroke.Thickness = 2
	stroke.Parent = panel

	local close = Instance.new("TextButton")
	close.Name = "X"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = Color3.fromRGB(48, 58, 74)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 18
	close.TextColor3 = Color3.fromRGB(240, 244, 250)
	close.Text = "X"
	close.AutoButtonColor = true
	close.ZIndex = 6
	close.Parent = panel
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = close

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(24, 56)
	body.Size = UDim2.new(1, -48, 1, -72)
	body.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = body

	local title = rebirthLabel(body, "Title", "Rebirth", 40, Enum.Font.GothamBold, Color3.fromRGB(255, 214, 120), 32)
	title.LayoutOrder = 1
	local count = rebirthLabel(body, "Count", "Rebirths: 0", 28, Enum.Font.GothamBold, Color3.fromRGB(244, 248, 255), 22)
	count.LayoutOrder = 2
	local current = rebirthLabel(body, "CurrentBonus", "Earnings 1x    Launch 1x", 48, Enum.Font.Gotham, Color3.fromRGB(220, 230, 242), 18)
	current.LayoutOrder = 3
	local nextBonus = rebirthLabel(body, "NextBonus", "Next: Earnings 1.5x    Launch 1.15x", 48, Enum.Font.Gotham, Color3.fromRGB(186, 214, 236), 18)
	nextBonus.LayoutOrder = 4
	local cost = rebirthLabel(body, "Cost", "Cost: $25K", 28, Enum.Font.GothamBold, Color3.fromRGB(255, 214, 120), 22)
	cost.LayoutOrder = 5
	local balance = rebirthLabel(body, "Balance", "You have: $0", 28, Enum.Font.Gotham, Color3.fromRGB(244, 248, 255), 18)
	balance.LayoutOrder = 6
	local note = rebirthLabel(body, "Note", "Resets coins, level, mountains, and gear. Keeps lifetime coins and distance.", 56, Enum.Font.Gotham, Color3.fromRGB(168, 180, 196), 16)
	note.LayoutOrder = 7

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.LayoutOrder = 8
	buy.Size = UDim2.new(1, 0, 0, 52)
	buy.BackgroundColor3 = REBIRTH_CANT
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = 20
	buy.TextColor3 = Color3.fromRGB(255, 255, 255)
	buy.Text = "$25K"
	buy.AutoButtonColor = false
	buy.Parent = body
	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 10)
	buyCorner.Parent = buy

	return panel
end

function api:EnsureRebirthFrame()
	local existing = findFrame(self, "Rebirth")
	if existing then
		return existing
	end
	local panel = buildRebirthFrame()
	panel.Parent = script
	return panel
end

function api:RefreshRebirthPanel()
	local panel = self.Panels.Rebirth
	if not panel or not panel.Parent then
		return
	end

	local player = Players.LocalPlayer
	local rebirths = math.max(0, math.floor(tonumber(player:GetAttribute("Rebirths")) or 0))
	local coins = math.max(0, math.floor(tonumber(player:GetAttribute("Coins")) or 0))
	local cost = playerProgress.RebirthCost(rebirths)
	local canAfford = coins >= cost
	local enabled = canAfford and not self.RebirthBusy

	local function setText(name, text)
		local label = panel:FindFirstChild(name, true)
		if label and (label:IsA("TextLabel") or label:IsA("TextButton")) and label.Name ~= "Confirm" then
			label.Text = text
		end
	end

	setText("Count", "Rebirths: " .. tostring(rebirths))
	setText("CurrentBonus", "Earnings " .. formatRate(playerProgress.EarningsMultiplier(rebirths)) .. "    Launch " .. formatRate(playerProgress.LaunchBoost(rebirths)))
	setText("NextBonus", "Next: Earnings " .. formatRate(playerProgress.EarningsMultiplier(rebirths + 1)) .. "    Launch " .. formatRate(playerProgress.LaunchBoost(rebirths + 1)))
	setText("Cost", "Cost: " .. formatPrice(cost))
	setText("Balance", "You have: " .. formatPrice(coins))

	local price = formatPrice(cost)
	setPriceText(panel, price)

	local buy = panel:FindFirstChild("Buy", true) or panel:FindFirstChild("Confirm", true)
	if buy and buy:IsA("GuiButton") then
		setButtonText(buy, price)
		-- Grayed, not inert: an unaffordable press still reaches PressRebirth ("Need $X more").
		buy.Active = not self.RebirthBusy
		local tinted = false
		eachShopBuyGradient(buy, function(gradient)
			tinted = true
			local colors = rememberGradientLook(self.RebirthGradientLooks, gradient)
			gradient.Color = if enabled then colors.Green else colors.Gray
		end)
		if tinted then
			buy.AutoButtonColor = enabled
		else
			local look = rememberButtonLook(self.RebirthBuyLooks, buy)
			applyButtonLook(buy, look, not enabled)
			buy.AutoButtonColor = if enabled then look.AutoButtonColor else false
		end
	end
end

function api:PressRebirth(buy)
	if self.RebirthBusy then
		return
	end
	local player = Players.LocalPlayer
	local rebirths = math.max(0, math.floor(tonumber(player:GetAttribute("Rebirths")) or 0))
	local coins = math.max(0, math.floor(tonumber(player:GetAttribute("Coins")) or 0))
	local cost = playerProgress.RebirthCost(rebirths)
	PurchaseFX.Press(buy)
	if coins < cost then
		PurchaseFX.Fail(buy)
		Notify.Error(string.format(NEED_MORE_TOAST, formatPrice(cost - coins)))
		self:RefreshRebirthPanel()
		return
	end

	self.RebirthBusy = true
	self:RefreshRebirthPanel()
	local invoked, ok, err = pcall(function()
		return ReplicatedStorage.ReEvent.ReFunction:InvokeServer("Rebirth")
	end)
	self.RebirthBusy = false
	self:RefreshRebirthPanel()
	self:RefreshShopPanel()
	self:RefreshMountainsPanel()
	if invoked and ok then
		PurchaseFX.Success(buy)
		PurchaseFX.FloatText(buy, REBIRTH_FLOAT)
		Audio.Play("Rebirth")
		Notify.Success(string.format(REBIRTH_TOAST, rebirths + 1))
	else
		warn("[CLIENT]: Rebirth failed:", if invoked then err else ok)
		PurchaseFX.Fail(buy)
		Notify.Error(if invoked and type(err) == "string" then err else "Rebirth failed")
	end
end

local function findRebirthBuy(panel)
	local buy = panel and (panel:FindFirstChild("Buy", true) or panel:FindFirstChild("Confirm", true))
	if buy and buy:IsA("GuiButton") then
		return buy
	end
	return nil
end

function api:SetupRebirthPanel(panel)
	if not panel then
		return
	end
	self:RefreshRebirthPanel()

	local buy = findRebirthBuy(panel)
	if not buy or buy:GetAttribute("RebirthWired") then
		return
	end
	buy:SetAttribute("RebirthWired", true)
	self.RebirthConnection = buy.Activated:Connect(function()
		self:PressRebirth(buy)
	end)
end

-- Dev hook (PlayerGui attribute "DevPress"): "<Snowballs|Blasters>:<item>" or "Rebirth" opens that
-- panel and presses the button as a click would, so a playtest eval can buy without FireServer.
function api:DevPress(request)
	if request == "Rebirth" then
		local buy = findRebirthBuy(self:OpenPanel("Rebirth"))
		if buy then
			self:PressRebirth(buy)
		end
		return
	end
	local tab, name = string.match(request, "^(%a+):(.+)$")
	local catalog = if tab == "Blasters" then snowballLaunchers elseif tab == "Snowballs" then snowballs else nil
	local def = catalog and catalog:GetByName(name)
	local panel = def and self:OpenPanel("Shop")
	if not panel then
		warn("[CLIENT]: DevPress: unknown request", request)
		return
	end
	self:SetShopTab(panel, tab)
	local scroll = findShopScroll(panel)
	local item = scroll and scroll:FindFirstChild(def.Name)
	local buy = item and findShopBuy(item)
	if buy then
		self:PressShopBuy(buy, item, def, tab)
	end
end

function api:OpenPanel(name)
	if name == "Rebirth" then
		self:EnsureRebirthFrame()
	end

	local template, alreadySpawned = findFrame(self, name)
	if not template then
		warn("[CLIENT]: No frame named", name, "exists in the game yet")
		return nil
	end
	Audio.Play("UIOpen")

	local panel = template
	if not alreadySpawned then
		panel = template:Clone()
		panel.Name = name
		panel.Visible = false
		panel.Parent = getWindow()
	end
	if self.Panels[name] ~= panel then
		self.Panels[name] = panel
		self:WirePanel(panel)
	end

	if not self.PanelRegistered[name] then
		self.PanelRegistered[name] = true
		PanelManager.register(name, function()
			self:HidePanel(name)
		end)
	end

	if self.PanelShown[name] then
		return panel
	end

	PanelManager.notifyOpened(name)
	self:ClosePanels(name)

	cancelPanelTween(self, name)
	ensureCenterAnchor(panel)
	local uiScale = getPanelScale(panel)
	self.PanelShown[name] = true
	uiScale.Scale = POP_START_SCALE
	panel.Visible = true
	local tween = TweenService:Create(uiScale, POP_IN, { Scale = 1 })
	self.PanelTweens[name] = tween
	tween:Play()

	setPanelOpen(name)
	if name == "Mountains" then
		self:SetupMountainsPanel(panel)
	elseif name == "Shop" then
		self:SetupShopPanel(panel)
	elseif name == "Rebirth" then
		self:SetupRebirthPanel(panel)
	end
	self:SyncMainVisibility()
	return panel
end

function api:TogglePanel(name)
	if self.PanelShown[name] then
		self:HidePanel(name)
		return nil
	end
	return self:OpenPanel(name)
end

function api:FindProgressWidgets(main)
	if not main then
		return nil
	end

	local levelRoot = main:FindFirstChild("Level", true)
	if not (levelRoot and levelRoot:IsA("GuiObject")) then
		return nil
	end

	local textHolder = levelRoot:FindFirstChild("Frame")
	local label = textHolder and textHolder:FindFirstChild("TextLabel")
	if not (label and (label:IsA("TextLabel") or label:IsA("TextButton"))) then
		label = levelRoot:FindFirstChild("TextLabel", true)
	end
	if not (label and (label:IsA("TextLabel") or label:IsA("TextButton"))) then
		return nil
	end

	local shadow = textHolder and textHolder:FindFirstChild("TextShadow")
	local fill = levelRoot:FindFirstChild("BackFrame")
	if not (fill and fill:IsA("GuiObject")) then
		return nil
	end

	return {
		Bar = levelRoot,
		Fill = fill,
		LevelLabel = label,
		ShadowLabel = if shadow and (shadow:IsA("TextLabel") or shadow:IsA("TextButton")) then shadow else nil,
	}
end

local FILL_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local LEVELUP_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function pinFillLeft(ui)
	if ui.FillPinned then
		return
	end
	ui.FillPinned = true

	local fill = ui.Fill
	local size = fill.Size
	local pos = fill.Position
	local anchor = fill.AnchorPoint

	ui.FillY = size.Y
	ui.FillWidth = size.X.Offset
	ui.FillScale = fill:GetAttribute("FullWidthScale") or size.X.Scale
	ui.FillUsesOffset = size.X.Scale == 0 and size.X.Offset > 0

	-- Keep the current left edge, then grow width to the right.
	local leftScale = pos.X.Scale - anchor.X * size.X.Scale
	local leftOffset = pos.X.Offset - anchor.X * size.X.Offset
	fill.AnchorPoint = Vector2.new(0, anchor.Y)
	fill.Position = UDim2.new(leftScale, leftOffset, pos.Y.Scale, pos.Y.Offset)
end

local function fillSize(ui, alpha)
	alpha = math.clamp(alpha, 0, 1)
	if ui.FillUsesOffset then
		return UDim2.new(0, math.floor(ui.FillWidth * alpha + 0.5), ui.FillY.Scale, ui.FillY.Offset)
	end
	return UDim2.new((ui.FillScale or 1) * alpha, 0, ui.FillY.Scale, ui.FillY.Offset)
end

local function applyText(ui, text)
	local xpLabel = ui.LevelLabel.Parent:FindFirstChild("XPLabel")
	local levelText, xpText = string.match(text, "^(Level %d+):%s*(.+)$")
	local split = xpLabel and xpLabel:IsA("TextLabel") and levelText ~= nil
	ui.LevelLabel.Text = if split then levelText else text
	if split then
		xpLabel.Text = xpText
	end
	if ui.ShadowLabel then
		ui.ShadowLabel.Text = ui.LevelLabel.Text
	end
end

local function cancelFillTween(ui)
	if ui.FillTween then
		ui.FillTween:Cancel()
		ui.FillTween = nil
	end
end

local function snapFill(ui, alpha)
	cancelFillTween(ui)
	local fill = ui.Fill
	if alpha <= 0 then
		fill.Visible = false
		fill.Size = fillSize(ui, 0)
		return
	end
	fill.Visible = true
	fill.Size = fillSize(ui, alpha)
end

local function tweenFill(ui, alpha, info)
	local fill = ui.Fill
	cancelFillTween(ui)
	info = info or FILL_TWEEN

	if alpha <= 0 then
		if not fill.Visible then
			fill.Size = fillSize(ui, 0)
			return nil
		end
		local tween = TweenService:Create(fill, info, { Size = fillSize(ui, 0) })
		ui.FillTween = tween
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and ui.FillTween == tween then
				fill.Visible = false
				ui.FillTween = nil
			end
		end)
		tween:Play()
		return tween
	end

	if not fill.Visible then
		fill.Size = fillSize(ui, 0)
		fill.Visible = true
	end

	local tween = TweenService:Create(fill, info, { Size = fillSize(ui, alpha) })
	ui.FillTween = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and ui.FillTween == tween then
			ui.FillTween = nil
		end
	end)
	tween:Play()
	return tween
end

local function formatCoins(amount)
	local n = math.max(0, math.floor(tonumber(amount) or 0))
	local text = tostring(n)
	local formatted = string.reverse(text):gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return formatted
end

local function formatDistance(amount)
	return (formatCoins(amount):gsub(",", " ")) .. " m"
end

local function formatRunCoins(amount)
	return "+" .. (formatCoins(amount):gsub(",", " ")) .. " $"
end

local function setLabelText(label, text)
	label.Text = text
	local shadow = label:FindFirstChild("TextShadow")
	if shadow and (shadow:IsA("TextLabel") or shadow:IsA("TextButton")) then
		shadow.Text = text
	end
end

local function earnScale(label)
	local scale = label:FindFirstChild("EarnPop")
	if not (scale and scale:IsA("UIScale")) then
		scale = Instance.new("UIScale")
		scale.Name = "EarnPop"
		scale.Parent = label
	end
	return scale
end

function api:GetRunLabel(name)
	local key = name .. "Label"
	local label = self[key]
	if label and label.Parent then
		return label
	end

	local main = self.MainUI or (self.UI and self.UI:FindFirstChild("MainUI"))
	if not main then
		return nil
	end

	label = main:FindFirstChild(name, true)
	if not (label and (label:IsA("TextLabel") or label:IsA("TextButton"))) then
		local warned = name .. "Warned"
		if not self[warned] then
			self[warned] = true
			warn("[CLIENT]: HUD run label not found (expected MainUI." .. name .. ")")
		end
		return nil
	end

	self[key] = label
	return label
end

local function settleCoinPop(self)
	if self.CoinPopTween then
		self.CoinPopTween:Cancel()
		self.CoinPopTween = nil
	end
	if self.CoinColorTween then
		self.CoinColorTween:Cancel()
		self.CoinColorTween = nil
	end

	local label = self.CoinsMadeLabel
	if label and label.Parent then
		local scale = label:FindFirstChild("EarnPop")
		if scale and scale:IsA("UIScale") then
			scale.Scale = 1
		end
		if self.CoinsMadeColor then
			label.TextColor3 = self.CoinsMadeColor
		end
	end

	if self.CoinFloater then
		self.CoinFloater:Destroy()
		self.CoinFloater = nil
	end
	self.CoinFloaterGain = 0
	self.CoinFloaterUntil = 0
end

local function floatCoinGain(self, label, gain)
	local now = os.clock()
	local floater = self.CoinFloater
	if floater and floater.Parent and now < (self.CoinFloaterUntil or 0) then
		self.CoinFloaterGain = (self.CoinFloaterGain or 0) + gain
		floater.Text = "+" .. formatCoins(self.CoinFloaterGain)
		return
	end

	if floater then
		floater:Destroy()
	end

	-- Parent to the screen, not MainUI, so a UIListLayout does not adopt the popup.
	local screen = label:FindFirstAncestorWhichIsA("ScreenGui")
	if not screen then
		return
	end

	local height = math.max(label.AbsoluteSize.Y, 28)
	local center = label.AbsolutePosition + (label.AbsoluteSize * 0.5) - screen.AbsolutePosition
	local popup = Instance.new("TextLabel")
	popup.Name = "CoinEarn"
	popup.BackgroundTransparency = 1
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.fromOffset(center.X, center.Y)
	popup.Size = UDim2.fromOffset(math.max(label.AbsoluteSize.X, 80), height)
	popup.Font = label.Font
	popup.TextScaled = false
	popup.TextSize = if label.TextScaled then math.clamp(height * 0.85, 16, 42) else math.max(label.TextSize, 16)
	popup.TextColor3 = COIN_FLASH
	popup.TextStrokeTransparency = 0.35
	popup.TextXAlignment = Enum.TextXAlignment.Center
	popup.TextYAlignment = Enum.TextYAlignment.Center
	popup.ZIndex = 50
	popup.Text = "+" .. formatCoins(gain)
	popup.Parent = screen

	self.CoinFloater = popup
	self.CoinFloaterGain = gain
	self.CoinFloaterUntil = now + 0.55

	local tween = TweenService:Create(popup, COIN_FLOAT, {
		Position = UDim2.fromOffset(center.X, center.Y - (height + 8)),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween.Completed:Connect(function()
		if self.CoinFloater == popup then
			self.CoinFloater = nil
			self.CoinFloaterUntil = 0
		end
		if popup.Parent then
			popup:Destroy()
		end
	end)
	tween:Play()
end

local function popCoinsMade(self, label, gain)
	Audio.Play("CoinPop")
	local scale = earnScale(label)
	if self.CoinPopTween then
		self.CoinPopTween:Cancel()
		self.CoinPopTween = nil
	end
	scale.Scale = math.clamp(math.max(scale.Scale, 1) + 0.18, 1.22, 1.45)
	local tween = TweenService:Create(scale, COIN_POP, { Scale = 1 })
	self.CoinPopTween = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and self.CoinPopTween == tween then
			self.CoinPopTween = nil
		end
	end)
	tween:Play()

	if not self.CoinsMadeColor then
		self.CoinsMadeColor = label.TextColor3
	end
	if self.CoinColorTween then
		self.CoinColorTween:Cancel()
		self.CoinColorTween = nil
	end
	label.TextColor3 = COIN_FLASH
	local colorTween = TweenService:Create(label, COIN_FLASH_TWEEN, { TextColor3 = self.CoinsMadeColor })
	self.CoinColorTween = colorTween
	colorTween:Play()

	floatCoinGain(self, label, gain)
end

local function noteRunCoins(self, amount)
	if not self.RunActive then
		return
	end

	-- Count only the increases since the last update, so spending mid-ride (a shop buy)
	-- never pulls the readout down or hides later earnings.
	local total = math.max(0, math.floor(tonumber(amount) or 0))
	local last = self.RunLastCoins or total
	self.RunLastCoins = total
	local previous = self.RunCoinsShown or 0
	local made = previous + math.max(0, total - last)
	if made == previous and self.CoinsMadeLabel and self.CoinsMadeLabel.Parent then
		return
	end
	self.RunCoinsShown = made

	local label = self:GetRunLabel("CoinsMade")
	if not label then
		return
	end
	setLabelText(label, formatRunCoins(made))
	local gain = made - previous
	if gain > 0 then
		popCoinsMade(self, label, gain)
	end
end

function api:SetCoins(amount)
	noteRunCoins(self, amount)
	local main = self.MainUI or (self.UI and self.UI:FindFirstChild("MainUI"))
	if not main then
		return
	end

	local label = self.CoinsLabel
	if not (label and label.Parent) then
		label = main:FindFirstChild("Coins", true)
		if not (label and (label:IsA("TextLabel") or label:IsA("TextButton"))) then
			if not self.CoinsWarned then
				self.CoinsWarned = true
				warn("[CLIENT]: HUD coins label not found (expected MainUI.Coins)")
			end
			return
		end
		self.CoinsLabel = label
	end

	setLabelText(label, formatCoins(amount))
end

function api:BeginRunReadout()
	local player = Players.LocalPlayer
	self.RunActive = true
	self.RunStartCoins = math.max(0, math.floor(tonumber(player:GetAttribute("Coins")) or 0))
	self.RunLastCoins = self.RunStartCoins
	self.RunCoinsShown = 0
	settleCoinPop(self)

	local coins = self:GetRunLabel("CoinsMade")
	if coins then
		if not self.CoinsMadeColor then
			self.CoinsMadeColor = coins.TextColor3
		end
		setLabelText(coins, formatRunCoins(0))
		coins.Visible = true
	end

	local distance = self:GetRunLabel("DistanceRolled")
	if distance then
		setLabelText(distance, formatDistance(player:GetAttribute("Distance") or 0))
		distance.Visible = true
	end

	if self.DistanceConn then
		self.DistanceConn:Disconnect()
		self.DistanceConn = nil
	end
	self.DistanceConn = player:GetAttributeChangedSignal("Distance"):Connect(function()
		if not self.RunActive then
			return
		end
		local label = self:GetRunLabel("DistanceRolled")
		if label then
			setLabelText(label, formatDistance(player:GetAttribute("Distance") or 0))
		end
	end)
end

function api:EndRunReadout()
	self.RunActive = false
	if self.DistanceConn then
		self.DistanceConn:Disconnect()
		self.DistanceConn = nil
	end
	settleCoinPop(self)

	local coins = self:GetRunLabel("CoinsMade")
	if coins then
		coins.Visible = false
	end
	local distance = self:GetRunLabel("DistanceRolled")
	if distance then
		distance.Visible = false
	end
end

function api:SetProgress(data)
	if type(data) ~= "table" then
		return
	end

	self:SetCoins(data.Coins)

	if not self.ProgressUI then
		local main = self.UI and self.UI:FindFirstChild("MainUI")
		self.ProgressUI = self:FindProgressWidgets(main)
		if not self.ProgressUI then
			if not self.ProgressWarned then
				self.ProgressWarned = true
				warn("[CLIENT]: HUD level bar not found (expected MainUI.Level.Frame.TextLabel and MainUI.Level.BackFrame)")
			end
			return
		end
	end

	local ui = self.ProgressUI
	pinFillLeft(ui)

	local level = math.max(1, math.floor(tonumber(data.Level) or 1))
	local xp = math.max(0, math.floor(tonumber(data.XP) or 0))
	local needed = math.max(1, math.floor(tonumber(data.XPNeeded) or 100))
	local alpha = math.clamp(xp / needed, 0, 1)
	local text = string.format("Level %d: %d/%d", level, xp, needed)

	ui.PendingAlpha = alpha
	ui.PendingText = text

	if not ui.FillReady then
		ui.FillReady = true
		ui.ShownLevel = level
		applyText(ui, text)
		snapFill(ui, 0)
		if alpha > 0 then
			tweenFill(ui, alpha)
		end
		return
	end

	if ui.LevelingUp then
		ui.ShownLevel = level
		return
	end

	if ui.ShownLevel and level > ui.ShownLevel then
		ui.ShownLevel = level
		ui.LevelingUp = true
		Audio.Play("LevelUp")
		Audio.Play("UISuccess")
		local token = (ui.FillToken or 0) + 1
		ui.FillToken = token
		task.spawn(function()
			local tween = tweenFill(ui, 1, LEVELUP_TWEEN)
			if tween then
				tween.Completed:Wait()
			end
			if ui.FillToken ~= token then
				ui.LevelingUp = false
				return
			end
			snapFill(ui, 0)
			applyText(ui, ui.PendingText or text)
			local dest = ui.PendingAlpha or alpha
			ui.LevelingUp = false
			if dest > 0 then
				tweenFill(ui, dest)
			end
		end)
		return
	end

	ui.ShownLevel = level
	applyText(ui, text)
	tweenFill(ui, alpha)
end

function api:WireButtons(main)
	for buttonName, panelName in BUTTON_PANELS do
		local button = main:FindFirstChild(buttonName, true)
		if button and button:IsA("GuiButton") then
			table.insert(self.Connections, button.Activated:Connect(function()
				Audio.Play("UIClick")
				if HIDES_MAIN[panelName] then
					self:OpenPanel(panelName)
				else
					self:TogglePanel(panelName)
				end
			end))
		else
			warn("[CLIENT]: HUD button not found:", buttonName)
		end
	end
	-- Preserve authored edges: button size constraints make Size differ from rendered size.
	-- Re-centering from Size shifts the HUD buttons when Play mode starts.
	UIUtils.bindHoverScaleAll(main, { centerPivot = false })
end

local function findCircleModel(name)
	local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	if not mountain then
		return nil
	end
	local circles = mountain:FindFirstChild("Circles", true)
	if circles then
		local circle = circles:FindFirstChild(name)
		if circle then
			return circle
		end
	end
	return mountain:FindFirstChild(name, true)
end

local function getRingVolume(circle)
	local ring = circle:FindFirstChild("NeonRing", true)
	local inner = circle:FindFirstChild("InnerCylinder", true)
	local inst = ring or inner or circle
	if inst:IsA("Model") then
		return inst:GetBoundingBox()
	end
	if inst:IsA("BasePart") then
		return inst.CFrame, inst.Size
	end
end

local function isInsideRing(position, cf, size)
	local localPoint = cf:PointToObjectSpace(position)
	local radius = math.max(size.X, size.Z) * 0.5
	local halfH = size.Y * 0.5
	return localPoint.X * localPoint.X + localPoint.Z * localPoint.Z <= radius * radius
		and localPoint.Y >= -halfH - 2
		and localPoint.Y <= halfH + RING_HEIGHT_PAD
end

local function isRiding()
	local folder = workspace:FindFirstChild("ActiveSnowballs")
	return folder ~= nil and folder:FindFirstChild(Players.LocalPlayer.Name .. "_Snowball") ~= nil
end

function api:WatchCircles()
	if self.CircleWatch then
		return
	end

	self.InsideCircle = nil
	self.CircleWatch = RunService.Heartbeat:Connect(function()
		local character = Players.LocalPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or isRiding() then
			self.InsideCircle = nil
			return
		end

		local inside = nil
		for circleName, panelName in CIRCLE_PANELS do
			local circle = findCircleModel(circleName)
			if not circle then
				continue
			end
			local cf, size = getRingVolume(circle)
			if cf and isInsideRing(hrp.Position, cf, size) then
				inside = circleName
				if self.InsideCircle ~= circleName then
					self:OpenPanel(panelName)
				end
				break
			end
		end
		self.InsideCircle = inside
	end)
	table.insert(self.Connections, self.CircleWatch)
end

function api:Initialize()
	local root = self.UI
	if not root then
		warn("[CLIENT]: HUD interface missing")
		return
	end

	local main = root:FindFirstChild("MainUI")
	if not main then
		-- The editable MainUI lives with the other HUD frames in
		-- ServerStorage.Assets.UserInterfaces.HUD; SetupInterfaces moved it under this module.
		local template = script:FindFirstChild("MainUI")
		if template then
			main = template:Clone()
			main.Parent = root
		end
	end
	self.MainUI = main
	if main then
		main.Visible = true
		table.insert(self.Connections, HUDLayout.BindMain(main))
		self:WireButtons(main)
		self.ProgressUI = self:FindProgressWidgets(main)
		if self.ProgressUI then
			print("[CLIENT]: HUD level bar ready")
		else
			self.ProgressWarned = true
			warn("[CLIENT]: HUD level bar not found (expected MainUI.Level.Frame.TextLabel and MainUI.Level.BackFrame)")
		end
		self:SetCoins(Players.LocalPlayer:GetAttribute("Coins"))
		self:EndRunReadout()
	else
		warn("[CLIENT]: HUD MainUI frame not found")
	end

	local playerGui = getPlayerGui()
	setPanelOpen(nil)
	table.insert(self.Connections, playerGui:GetAttributeChangedSignal("DevPanel"):Connect(function()
		local name = playerGui:GetAttribute("DevPanel")
		if typeof(name) == "string" and name ~= "" then
			self:TogglePanel(name)
		end
	end))
	table.insert(self.Connections, playerGui:GetAttributeChangedSignal("DevPress"):Connect(function()
		local request = playerGui:GetAttribute("DevPress")
		if typeof(request) == "string" and request ~= "" then
			playerGui:SetAttribute("DevPress", nil)
			self:DevPress(request)
		end
	end))
	table.insert(self.Connections, Players.LocalPlayer:GetAttributeChangedSignal("UnlockedMountains"):Connect(function()
		self:RefreshMountainsPanel()
	end))
	self:RefreshMountainsPanel()
	for _, name in { "UnlockedSnowballs", "UnlockedLaunchers", "EquippedSnowball", "EquippedLauncher" } do
		table.insert(self.Connections, Players.LocalPlayer:GetAttributeChangedSignal(name):Connect(function()
			self:RefreshShopPanel()
		end))
	end
	for _, name in { "Coins", "Rebirths" } do
		table.insert(self.Connections, Players.LocalPlayer:GetAttributeChangedSignal(name):Connect(function()
			self:RefreshRebirthPanel()
		end))
	end
	self:RefreshShopPanel()
	self:WatchCircles()
	PurchaseFX.WatchPlayers()

	print("[CLIENT]: HUD ready")
end

return api
