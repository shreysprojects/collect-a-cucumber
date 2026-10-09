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
	Rebirth uses the Studio frame when one exists: Foreground.CurrentBoost /
	UpcomingBoost show the earnings boost now and after the next rebirth
	("X1" -> "X1.5"), Background.Level is a level bar (Frame.TextLabel "12/10",
	BackFrame fill) toward the level the next rebirth needs
	(PlayerProgress.RebirthLevel: 10, 15, 20, ...), and Foreground.Buy reads
	"REBIRTH!", grayed until that level is reached; a press invokes Rebirth. The
	main level bar reads "MAX" with a full fill at PlayerProgress.MAX_LEVEL. A
	generated frame is only built when Studio has not supplied one.
	Ascend is the same panel shape (Studio frame HUD/Ascend, built by
	extras/panels/build_panels.lua): CurrentBoost / UpcomingBoost = the permanent
	power multiplier now / after ascending (X1 -> X13), the level bar toward
	PlayerProgress.ASCEND_LEVEL, Buy = "ASCEND!"; a press invokes Ascend, which
	resets everything. It opens by walking up to the heavenly wings: the "Ascend"
	model inside the lobby's StartPlatform (CIRCLE_PANELS, bounding box + pad).

	Attention (not distracting): a small gold arrow bobs above the Shop button
	while the next snowball or blaster can be bought (in order, mountain open,
	affordable) and above the Rebirth button while the rebirth level is reached;
	a bobbing "ASCEND!" billboard hangs over the wings at the ascend level. Each
	one also gets a single Notify.Info toast the first time it becomes available
	(per item / rebirth / ascension, this session). Nothing shows while that panel
	is open or during a ride.

	Mountains cards (Frostpeak, Candy, ...) show Travel when unlocked and Locked
	when not. Travel invokes TravelToMountain (teleport to that mountain's place).
	Frostpeak starts unlocked; other unlocks persist on the player DataStore.

	Shop: the frame (ServerStorage.Assets.UserInterfaces.HUD.Shop, built by
	ras-dev/shop-remake/build_shop_frames.lua) is filled and animated by
	ReplicatedStorage.Assets.Modules.Client.UI.ShopPanel (tabs, rarity cards, buy /
	equip, the celebration effects). This module only opens and closes it:
	OpenPanel -> ShopPanel.Setup, RefreshShopPanel -> ShopPanel.Refresh,
	DisconnectShop -> ShopPanel.Teardown. Rebirth plays the same press / success / fail
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
local PanelManager = require(ReplicatedStorage.Assets.Modules.Client.UI.PanelManager)
local UIUtils = require(ReplicatedStorage.Assets.Modules.Client.UI.UIUtils)
local HUDLayout = require(ReplicatedStorage.Assets.Modules.Client.UI.HUDLayout)
local PurchaseFX = require(ReplicatedStorage.Assets.Modules.Client.UI.PurchaseFX)
local ShopPanel = require(ReplicatedStorage.Assets.Modules.Client.UI.ShopPanel)
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
	Ascend = "Ascend", -- the heavenly wings model in the lobby's StartPlatform
}
local CIRCLE_RADIUS_PAD = { -- extra studs around a trigger's footprint
	Ascend = 4,
}
local HIDES_MAIN = {
	Shop = true,
	Mountains = true,
	Rebirth = true,
	Ascend = true,
}
local REBIRTH_CAN = Color3.fromRGB(46, 160, 90)
local REBIRTH_CANT = Color3.fromRGB(78, 84, 96)
local MENU_DISPLAY_ORDER = 5 -- panels draw above the HUD buttons
local TAB_GRAY = Color3.fromRGB(118, 118, 118)
local TAB_GRAY_TEXT = Color3.fromRGB(188, 188, 188)
local TAB_GRAY_MIX = 0.62
local SHOP_GRAY_DARKEN = 0.62 -- grayColor: the grayed Rebirth / Ascend button gradients
local REBIRTH_FLOAT = "REBIRTH!"
local REBIRTH_TOAST = "Rebirth %d! Boost %s"
local REBIRTH_BUY_TEXT = "REBIRTH!"
local REBIRTH_NEED_TOAST = "Reach level %d first"
local ASCEND_FLOAT = "ASCENDED!"
local ASCEND_TOAST = "Ascension %d! Power %s"
local ASCEND_BUY_TEXT = "ASCEND!"
local MAX_LEVEL_TEXT = "MAX"
-- Attention arrows + one-time toasts.
local ATTENTION_ARROW = "rbxassetid://113666736365393" -- the panel arrow, turned to point at the button
local ATTENTION_COLOR = Color3.fromRGB(255, 214, 64)
local ATTENTION_SIZE = 26 -- px, before the dock's ResponsiveScale
local ATTENTION_GAP = 6 -- px between the button's right edge and the arrow
local ATTENTION_BOB = 4 -- px
local ATTENTION_BOB_RATE = 3.2 -- rad/s
local ATTENTION_SETTLE = 4 -- s after the HUD starts before the first toast
local ATTENTION_TOAST_GAP = 6 -- s between two attention toasts (they queue, never stack)
local ATTENTION_TOASTS = {
	Snowballs = "New snowball ready to buy!",
	Blasters = "New blaster ready to buy!",
	Rebirth = "Rebirth ready!",
	Ascend = "You can ASCEND at the heavenly wings!",
}
local ASCEND_BILLBOARD_TEXT = "ASCEND!"
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
api.RebirthBuyLooks = {}
api.RebirthGradientLooks = {}
api.AscendBuyLooks = {}
api.AscendGradientLooks = {}
api.LevelBars = {}
api.Attention = {}
api.AttentionToasted = {}
api.AttentionToastQueue = {}
api.CircleCache = {}
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
		PurchaseFX.Press(button)
		self:TravelToMountain(mountainId)
	end)
end

local MOUNTAIN_HERE_COLOR = Color3.fromRGB(255, 224, 68)
local TRAVEL_PILL = {
	Go = { Top = Color3.fromRGB(159, 255, 66), Bottom = Color3.fromRGB(64, 214, 0), Stroke = Color3.fromRGB(34, 71, 10) },
	Here = { Top = Color3.fromRGB(255, 233, 107), Bottom = Color3.fromRGB(255, 184, 0), Stroke = Color3.fromRGB(107, 74, 0) },
}

-- The remade Mountains frame: GO! green, HERE gold (Gradient + Outline children). Older frames have neither.
local function paintTravelPill(travel, isHere)
	local look = if isHere then TRAVEL_PILL.Here else TRAVEL_PILL.Go
	local gradient = travel:FindFirstChild("Gradient")
	if gradient and gradient:IsA("UIGradient") then
		gradient.Color = ColorSequence.new(look.Top, look.Bottom)
	end
	local outline = travel:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Color = look.Stroke
	end
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
			local lockText = locked:FindFirstChild("LockText", true)
			if lockText and (lockText:IsA("TextLabel") or lockText:IsA("TextButton")) then
				local previous = mountainConfig:GetPreviousMountain(mountainId)
				lockText.Text = if previous then "FINISH " .. string.upper(mountainConfig:GetDisplayName(previous)) else ""
			end
		end
		-- The mountain you are on gets a gold outline (remade frame; older frames have no Outline).
		local outline = card:FindFirstChild("Outline")
		if outline and outline:IsA("UIStroke") then
			if not card:GetAttribute("OutlineColor") then
				card:SetAttribute("OutlineColor", outline.Color)
			end
			outline.Color = if isHere then MOUNTAIN_HERE_COLOR else card:GetAttribute("OutlineColor")
			outline.Thickness = if isHere then 4.5 else 3
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
				local travelText = if isHere then "HERE" else "GO!"
				local travelLabel = travel:FindFirstChild("TextLabel", true)
				if travelLabel and travelLabel:IsA("TextLabel") then
					travelLabel.Text = travelText
					local shadow = travel:FindFirstChild("TextShadow", true)
					if shadow and shadow:IsA("TextLabel") then
						shadow.Text = travelText
					end
					if travel:IsA("TextButton") then
						travel.Text = ""
					end
				elseif travel:IsA("TextButton") then
					travel.Text = travelText
				end
				paintTravelPill(travel, isHere)
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

-- The rebirth panel's boost labels: "X1", "X1.5", "X2".
local function formatBoost(value)
	return "X" .. (formatRate(value):gsub("x$", ""))
end

-- Shop rules live in ShopPanel; these wrappers keep the attention arrows (buyableItem) on the same logic.
local function shopCatalog(tab)
	return ShopPanel.Catalog(tab).List
end

local function nextShopOrder(tab, owned)
	return ShopPanel.NextOrder(tab, owned)
end

local function shopOrderForSale(order, owned, tab)
	return ShopPanel.OrderForSale(order, owned, tab)
end

local function shopOwnedMap(tab)
	return ShopPanel.OwnedMap(tab)
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
	ShopPanel.Teardown()
	self.ShopWired = nil
end

function api:RefreshShopPanel()
	ShopPanel.Refresh()
end

function api:SetShopTab(panel, tab)
	ShopPanel.SetTab(tab)
end

-- The Shop frame's contents (tabs, cards, buying, equipping, effects) are ShopPanel's.
function api:SetupShopPanel(panel)
	if not panel then
		return
	end
	if ShopPanel.Setup(panel, self) then
		self.ShopWired = panel
	end
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

function api:DisconnectAscend()
	if self.AscendConnection then
		self.AscendConnection:Disconnect()
		self.AscendConnection = nil
	end
	local panel = self.Panels.Ascend
	local buy = panel and panel:FindFirstChild("Buy", true)
	if buy then
		buy:SetAttribute("AscendWired", nil)
	end
	self.AscendBusy = false
end

function api:DisconnectEvents()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	self:DisconnectMountainTravel()
	self:DisconnectShop()
	self:DisconnectRebirth()
	self:DisconnectAscend()
	self:ClearAttention()
	self:EndRunReadout()
	self.CircleWatch = nil
	self.InsideCircle = nil
	table.clear(self.CircleCache)
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
	self:QueueAttention()
end

-- Remade panels (Shop, Mountains) are authored at a design size under Panel.Fit (UIScale):
-- fitted to the screen with a margin, centred a little above the middle so the toast strip
-- stays clear (ShopPanel does the same for the shop).
local PANEL_FIT = { Width = 1140, Height = 735, MarginX = 40, MarginY = 120, Min = 0.35, Max = 1.1, CenterY = 0.46 }

local function bindPanelFit(self, panel)
	local inner = panel:FindFirstChild("Panel")
	local fit = inner and inner:FindFirstChild("Fit")
	local screen = panel:FindFirstAncestorWhichIsA("ScreenGui")
	if not (fit and fit:IsA("UIScale") and screen) then
		return
	end
	local function apply()
		local size = screen.AbsoluteSize
		local designWidth = tonumber(inner:GetAttribute("DesignWidth")) or PANEL_FIT.Width
		local designHeight = tonumber(inner:GetAttribute("DesignHeight")) or PANEL_FIT.Height
		local scale = math.min((size.X - PANEL_FIT.MarginX) / designWidth, (size.Y - PANEL_FIT.MarginY) / designHeight)
		fit.Scale = math.clamp(scale, PANEL_FIT.Min, PANEL_FIT.Max)
		inner.Position = UDim2.fromScale(0.5, PANEL_FIT.CenterY)
	end
	apply()
	table.insert(self.Connections, screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply))
end

function api:WirePanel(panel)
	local close = panel:FindFirstChild("X", true)
	if close and close:IsA("GuiButton") then
		table.insert(self.Connections, close.Activated:Connect(function()
			self:HidePanel(panel.Name)
		end))
	end
	local dimmer = panel:FindFirstChild("Dimmer")
	if dimmer and dimmer:IsA("GuiButton") then
		table.insert(self.Connections, dimmer.Activated:Connect(function()
			self:HidePanel(panel.Name)
		end))
	end
	bindPanelFit(self, panel)
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
	local level = math.max(1, math.floor(tonumber(player:GetAttribute("Level")) or 1))
	local needLevel = playerProgress.RebirthLevel(rebirths)
	local ready = level >= needLevel
	local enabled = ready and not self.RebirthBusy

	local function setText(name, text)
		local label = panel:FindFirstChild(name, true)
		if label and (label:IsA("TextLabel") or label:IsA("TextButton")) and label.Name ~= "Confirm" then
			label.Text = text
		end
	end

	-- Studio frame: boost now -> after the next rebirth, and the level bar toward the gate.
	setText("CurrentBoost", formatBoost(playerProgress.EarningsMultiplier(rebirths)))
	setText("UpcomingBoost", formatBoost(playerProgress.EarningsMultiplier(rebirths + 1)))
	self:SetPanelLevelBar(panel, level, needLevel)

	-- Generated fallback frame.
	setText("Count", "Rebirths: " .. tostring(rebirths))
	setText("CurrentBonus", "Earnings " .. formatRate(playerProgress.EarningsMultiplier(rebirths)) .. "    Launch " .. formatRate(playerProgress.LaunchBoost(rebirths)))
	setText("NextBonus", "Next: Earnings " .. formatRate(playerProgress.EarningsMultiplier(rebirths + 1)) .. "    Launch " .. formatRate(playerProgress.LaunchBoost(rebirths + 1)))
	setText("Cost", "Needs level " .. tostring(needLevel))
	setText("Balance", "You are level " .. tostring(level))

	local buy = panel:FindFirstChild("Buy", true) or panel:FindFirstChild("Confirm", true)
	if buy and buy:IsA("GuiButton") then
		setButtonText(buy, REBIRTH_BUY_TEXT)
		-- Grayed, not inert: an early press still reaches PressRebirth ("Reach level N first").
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
	local level = math.max(1, math.floor(tonumber(player:GetAttribute("Level")) or 1))
	local needLevel = playerProgress.RebirthLevel(rebirths)
	PurchaseFX.Press(buy)
	if level < needLevel then
		PurchaseFX.Fail(buy)
		Notify.Error(string.format(REBIRTH_NEED_TOAST, needLevel))
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
		Notify.Success(string.format(REBIRTH_TOAST, rebirths + 1, formatBoost(playerProgress.EarningsMultiplier(rebirths + 1))))
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

----------------------------------------------------------------------------------------------
-- Ascend: the Studio frame HUD/Ascend (same shape as Rebirth), opened by the heavenly wings.
----------------------------------------------------------------------------------------------

function api:EnsureAscendFrame()
	local existing = findFrame(self, "Ascend")
	if not existing then
		warn("[CLIENT]: No Ascend frame in the game (ServerStorage.Assets.UserInterfaces.HUD.Ascend)")
	end
	return existing
end

function api:RefreshAscendPanel()
	local panel = self.Panels.Ascend
	if not panel or not panel.Parent then
		return
	end

	local player = Players.LocalPlayer
	local ascensions = math.max(0, math.floor(tonumber(player:GetAttribute("Ascensions")) or 0))
	local level = math.max(1, math.floor(tonumber(player:GetAttribute("Level")) or 1))
	local needLevel = playerProgress.AscendLevel()
	local ready = level >= needLevel
	local enabled = ready and not self.AscendBusy

	local function setText(name, text)
		local label = panel:FindFirstChild(name, true)
		if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
			label.Text = text
		end
	end

	setText("CurrentBoost", formatBoost(playerProgress.AscendMultiplier(ascensions)))
	setText("UpcomingBoost", formatBoost(playerProgress.AscendMultiplier(ascensions + 1)))
	self:SetPanelLevelBar(panel, level, needLevel)

	local buy = findRebirthBuy(panel)
	if buy then
		setButtonText(buy, ASCEND_BUY_TEXT)
		-- Grayed, not inert: an early press still explains itself ("Reach level 100 first").
		buy.Active = not self.AscendBusy
		local tinted = false
		eachShopBuyGradient(buy, function(gradient)
			tinted = true
			local colors = rememberGradientLook(self.AscendGradientLooks, gradient)
			gradient.Color = if enabled then colors.Green else colors.Gray
		end)
		if tinted then
			buy.AutoButtonColor = enabled
		else
			local look = rememberButtonLook(self.AscendBuyLooks, buy)
			applyButtonLook(buy, look, not enabled)
			buy.AutoButtonColor = if enabled then look.AutoButtonColor else false
		end
	end
end

function api:PressAscend(buy)
	if self.AscendBusy then
		return
	end
	local player = Players.LocalPlayer
	local ascensions = math.max(0, math.floor(tonumber(player:GetAttribute("Ascensions")) or 0))
	local level = math.max(1, math.floor(tonumber(player:GetAttribute("Level")) or 1))
	local needLevel = playerProgress.AscendLevel()
	PurchaseFX.Press(buy)
	if level < needLevel then
		PurchaseFX.Fail(buy)
		Notify.Error(string.format(REBIRTH_NEED_TOAST, needLevel))
		self:RefreshAscendPanel()
		return
	end

	self.AscendBusy = true
	self:RefreshAscendPanel()
	local invoked, ok, err = pcall(function()
		return ReplicatedStorage.ReEvent.ReFunction:InvokeServer("Ascend")
	end)
	self.AscendBusy = false
	self:RefreshAscendPanel()
	self:RefreshRebirthPanel()
	self:RefreshShopPanel()
	self:RefreshMountainsPanel()
	if invoked and ok then
		PurchaseFX.Success(buy)
		PurchaseFX.FloatText(buy, ASCEND_FLOAT)
		Audio.Play("Rebirth")
		Audio.Play("LevelUp")
		Notify.Success(string.format(ASCEND_TOAST, ascensions + 1, formatBoost(playerProgress.AscendMultiplier(ascensions + 1))))
	else
		warn("[CLIENT]: Ascend failed:", if invoked then err else ok)
		PurchaseFX.Fail(buy)
		Notify.Error(if invoked and type(err) == "string" then err else "Ascend failed")
	end
end

function api:SetupAscendPanel(panel)
	if not panel then
		return
	end
	self:RefreshAscendPanel()

	local buy = findRebirthBuy(panel)
	if not buy or buy:GetAttribute("AscendWired") then
		return
	end
	buy:SetAttribute("AscendWired", true)
	self.AscendConnection = buy.Activated:Connect(function()
		self:PressAscend(buy)
	end)
end

-- Dev hook (PlayerGui attribute "DevPress"): "<Snowballs|Blasters>:<item>", "Rebirth" or "Ascend"
-- opens that panel and presses the button as a click would, so a playtest eval can buy without FireServer.
function api:DevPress(request)
	if request == "Rebirth" then
		local buy = findRebirthBuy(self:OpenPanel("Rebirth"))
		if buy then
			self:PressRebirth(buy)
		end
		return
	end
	if request == "Ascend" then
		local buy = findRebirthBuy(self:OpenPanel("Ascend"))
		if buy then
			self:PressAscend(buy)
		end
		return
	end
	local tab, name = string.match(request, "^(%a+):(.+)$")
	local def = (tab == "Blasters" or tab == "Snowballs") and ShopPanel.Catalog(tab):GetByName(name)
	local panel = def and self:OpenPanel("Shop")
	if not panel then
		warn("[CLIENT]: DevPress: unknown request", request)
		return
	end
	ShopPanel.DevPress(tab, def.Name)
end

function api:OpenPanel(name)
	if name == "Rebirth" then
		self:EnsureRebirthFrame()
	elseif name == "Ascend" then
		self:EnsureAscendFrame()
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
	elseif name == "Ascend" then
		self:SetupAscendPanel(panel)
	end
	self:SyncMainVisibility()
	self:QueueAttention()
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

-- A panel's level bar (a Frame named Level anywhere in it: Frame.TextLabel + TextShadow over a
-- BackFrame fill; Rebirth and Ascend both have one), driven like the main bar: "level/needed",
-- filled to level / needed.
function api:SetPanelLevelBar(panel, level, needLevel)
	local ui = self.LevelBars[panel.Name]
	if not ui or ui.Panel ~= panel or not ui.Fill.Parent then
		ui = nil
		for _, child in panel:GetDescendants() do
			if child.Name == "Level" and child:IsA("Frame") then
				local holder = child:FindFirstChild("Frame")
				local label = holder and holder:FindFirstChild("TextLabel")
				local fill = child:FindFirstChild("BackFrame")
				if label and label:IsA("TextLabel") and fill and fill:IsA("GuiObject") then
					local shadow = holder:FindFirstChild("TextShadow")
					ui = {
						Panel = panel,
						Bar = child,
						Fill = fill,
						LevelLabel = label,
						ShadowLabel = if shadow and shadow:IsA("TextLabel") then shadow else nil,
					}
					break
				end
			end
		end
		self.LevelBars[panel.Name] = ui
		if not ui then
			return
		end
	end

	pinFillLeft(ui)
	local need = math.max(1, math.floor(tonumber(needLevel) or 1))
	local shown = math.max(1, math.floor(tonumber(level) or 1))
	applyText(ui, string.format("%d/%d", shown, need))
	local alpha = math.clamp(shown / need, 0, 1)
	if not ui.FillReady then
		ui.FillReady = true
		snapFill(ui, alpha)
		return
	end
	tweenFill(ui, alpha)
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

-- Ride over: the "+N $" readout (top centre) swings to the middle of the screen and grows,
-- holds a second, then dives into the coin counter (top left), which pops.
local RUN_FLY = {
	Grow = 1.9,
	ToCenter = 0.55,
	Hold = 1.0,
	ToCounter = 0.6,
	Center = Vector2.new(0.5, 0.42),
	EndScale = 0.45,
	CounterPop = 1.3,
}

function api:CancelRunCoinsFly()
	self.RunFlyToken = (self.RunFlyToken or 0) + 1
	if self.RunFlyLabel then
		self.RunFlyLabel:Destroy()
		self.RunFlyLabel = nil
	end
end

-- The coin counter (LeftDock.Coins + CoinsImage) pops gold when the flown readout lands.
function api:PopCoinsCounter()
	local main = self.MainUI
	if not main then
		return
	end
	local coinsLabel = self.CoinsLabel
	if not (coinsLabel and coinsLabel.Parent) then
		coinsLabel = main:FindFirstChild("Coins", true)
	end
	local targets = {}
	if coinsLabel and coinsLabel:IsA("TextLabel") then
		table.insert(targets, coinsLabel)
	end
	local image = main:FindFirstChild("CoinsImage", true)
	if image and image:IsA("GuiObject") then
		table.insert(targets, image)
	end
	if #targets == 0 then
		return
	end
	Audio.Play("CoinPop")
	local token = (self.CounterPopToken or 0) + 1
	self.CounterPopToken = token
	local scales = {}
	for _, target in targets do
		local scale = target:FindFirstChild("CounterPop")
		if not (scale and scale:IsA("UIScale")) then
			scale = Instance.new("UIScale")
			scale.Name = "CounterPop"
			scale.Parent = target
		end
		table.insert(scales, scale)
	end
	if coinsLabel and coinsLabel:IsA("TextLabel") and not self.CoinsBaseColor then
		self.CoinsBaseColor = coinsLabel.TextColor3
	end
	local baseColor = self.CoinsBaseColor
	task.spawn(function()
		PurchaseFX.Animate(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
			local k = RUN_FLY.CounterPop - (RUN_FLY.CounterPop - 1) * a
			for _, scale in scales do
				scale.Scale = k
			end
			if coinsLabel and baseColor then
				coinsLabel.TextColor3 = COIN_FLASH:Lerp(baseColor, a)
			end
		end, function()
			return self.CounterPopToken == token
		end)
		if self.CounterPopToken == token then
			for _, scale in scales do
				scale.Scale = 1
			end
			if coinsLabel and baseColor then
				coinsLabel.TextColor3 = baseColor
			end
		end
	end)
end

function api:FlyRunCoins(label)
	local screen = label:FindFirstAncestorWhichIsA("ScreenGui")
	if not screen then
		return
	end
	self:CancelRunCoinsFly()
	local token = self.RunFlyToken
	local size = label.AbsoluteSize
	local start = label.AbsolutePosition + size * 0.5 - screen.AbsolutePosition
	local clone = label:Clone()
	clone.Name = "RunCoinsFly"
	local strokes = {}
	for _, child in clone:GetChildren() do
		if child:IsA("UIScale") or child:IsA("UITextSizeConstraint") then
			child:Destroy()
		elseif child:IsA("UIStroke") then
			table.insert(strokes, { Stroke = child, Thickness = child.Thickness })
		end
	end
	clone.AnchorPoint = Vector2.new(0.5, 0.5)
	clone.Position = UDim2.fromOffset(start.X, start.Y)
	clone.Size = UDim2.fromOffset(size.X, size.Y)
	clone.TextScaled = true
	clone.TextTransparency = 0
	clone.Visible = true
	clone.ZIndex = 60
	clone.Parent = screen
	self.RunFlyLabel = clone
	local grow = RUN_FLY.Grow
	local function place(point, k)
		clone.Position = UDim2.fromOffset(point.X, point.Y)
		clone.Size = UDim2.fromOffset(size.X * k, size.Y * k)
		for _, entry in strokes do
			entry.Stroke.Thickness = entry.Thickness * k
		end
	end
	task.spawn(function()
		local function alive()
			return self.RunFlyToken == token and clone.Parent ~= nil
		end
		local screenSize = screen.AbsoluteSize
		local center = Vector2.new(screenSize.X * RUN_FLY.Center.X, screenSize.Y * RUN_FLY.Center.Y)
		PurchaseFX.Animate(RUN_FLY.ToCenter, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
			place(start:Lerp(center, a), 1 + (grow - 1) * a)
		end, alive)
		if not alive() then
			return
		end
		Audio.Play("UISuccess")
		local holdUntil = os.clock() + RUN_FLY.Hold
		while alive() and os.clock() < holdUntil do
			RunService.Heartbeat:Wait()
		end
		if not alive() then
			return
		end
		local target = self.CoinsLabel
		if not (target and target.Parent) and self.MainUI then
			target = self.MainUI:FindFirstChild("Coins", true)
		end
		local dest = if target and target:IsA("GuiObject") then target.AbsolutePosition + target.AbsoluteSize * 0.5 - screen.AbsolutePosition else Vector2.new(80, 80)
		PurchaseFX.Animate(RUN_FLY.ToCounter, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
			place(center:Lerp(dest, a), grow + (RUN_FLY.EndScale - grow) * a)
		end, alive)
		if self.RunFlyToken == token then
			clone:Destroy()
			self.RunFlyLabel = nil
			self:PopCoinsCounter()
		end
	end)
end

function api:BeginRunReadout()
	local player = Players.LocalPlayer
	self.RunActive = true
	self.RunStartCoins = math.max(0, math.floor(tonumber(player:GetAttribute("Coins")) or 0))
	self.RunLastCoins = self.RunStartCoins
	self.RunCoinsShown = 0
	settleCoinPop(self)
	self:CancelRunCoinsFly()

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
		if coins.Visible and (self.RunCoinsShown or 0) > 0 then
			self:FlyRunCoins(coins)
		end
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
	if playerProgress.IsMaxLevel(level) then
		-- The cap: a full bar that says so (the server stops awarding XP here).
		alpha = 1
		text = string.format("Level %d: %s", level, MAX_LEVEL_TEXT)
	end

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

local function isInsideRing(position, cf, size, pad)
	local localPoint = cf:PointToObjectSpace(position)
	local radius = math.max(size.X, size.Z) * 0.5 + (pad or 0)
	local halfH = size.Y * 0.5
	return localPoint.X * localPoint.X + localPoint.Z * localPoint.Z <= radius * radius
		and localPoint.Y >= -halfH - 2
		and localPoint.Y <= halfH + RING_HEIGHT_PAD
end

local function isRiding()
	local folder = workspace:FindFirstChild("ActiveSnowballs")
	return folder ~= nil and folder:FindFirstChild(Players.LocalPlayer.Name .. "_Snowball") ~= nil
end

-- Trigger models are looked up once and kept while they stay in the world (a recursive
-- FindFirstChild over the whole mountain every frame is what this replaces).
function api:GetCircleModel(name)
	local cached = self.CircleCache[name]
	if cached and cached.Parent and cached:IsDescendantOf(workspace) then
		return cached
	end
	local found = findCircleModel(name)
	self.CircleCache[name] = found
	return found
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
			local circle = self:GetCircleModel(circleName)
			if not circle then
				continue
			end
			local cf, size = getRingVolume(circle)
			if cf and isInsideRing(hrp.Position, cf, size, CIRCLE_RADIUS_PAD[circleName]) then
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
		-- Toasts stay above the level bar while the HUD shows (a panel hides MainUI).
		Notify.AvoidAbove(main:FindFirstChild("BottomDock") or main:FindFirstChild("Level", true))
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
	for _, name in { "Level", "Rebirths", "Ascensions" } do
		table.insert(self.Connections, Players.LocalPlayer:GetAttributeChangedSignal(name):Connect(function()
			self:RefreshRebirthPanel()
			self:RefreshAscendPanel()
		end))
	end
	self:RefreshShopPanel()
	self:WatchCircles()
	self:WatchAttention()
	PurchaseFX.WatchPlayers()

	print("[CLIENT]: HUD ready")
end

----------------------------------------------------------------------------------------------
-- Attention: a small bobbing arrow above the Shop / Rebirth buttons and an "ASCEND!" billboard
-- over the wings while that action is available, plus one quiet toast the first time each
-- becomes available. Hidden while that panel is open and during a ride.
----------------------------------------------------------------------------------------------

-- The next item of a catalog that can be bought right now (in order, mountain open,
-- affordable), or nil.
local function buyableItem(tab, coins)
	local owned = shopOwnedMap(tab)
	local order = nextShopOrder(tab, owned)
	if not order then
		return nil
	end
	for _, def in shopCatalog(tab) do
		if def.Order == order then
			if shopOrderForSale(order, owned, tab) and coins >= math.max(0, math.floor(tonumber(def.Price) or 0)) then
				return def
			end
			return nil
		end
	end
	return nil
end

local function attentionArrow(button)
	local arrow = button:FindFirstChild("Attention")
	if arrow and arrow:IsA("ImageLabel") then
		return arrow
	end
	arrow = Instance.new("ImageLabel")
	arrow.Name = "Attention"
	arrow.BackgroundTransparency = 1
	-- Beside the button, pointing at it: above it sits the coin counter / the button before.
	arrow.AnchorPoint = Vector2.new(0, 0.5)
	arrow.Position = UDim2.new(1, ATTENTION_GAP, 0.5, 0)
	arrow.Size = UDim2.fromOffset(ATTENTION_SIZE, ATTENTION_SIZE)
	arrow.Image = ATTENTION_ARROW
	arrow.ImageColor3 = ATTENTION_COLOR
	arrow.Rotation = 180 -- the panel's "next" arrow points right; turned to point left at the button
	arrow.ZIndex = (button.ZIndex or 1) + 5
	arrow.Visible = false
	arrow.Parent = button
	return arrow
end

function api:AttentionState()
	local player = Players.LocalPlayer
	local coins = math.max(0, math.floor(tonumber(player:GetAttribute("Coins")) or 0))
	local level = math.max(1, math.floor(tonumber(player:GetAttribute("Level")) or 1))
	local rebirths = math.max(0, math.floor(tonumber(player:GetAttribute("Rebirths")) or 0))
	local ascensions = math.max(0, math.floor(tonumber(player:GetAttribute("Ascensions")) or 0))
	local state = { Shop = {}, Rebirth = nil, Ascend = nil }
	for _, tab in { "Snowballs", "Blasters" } do
		local def = buyableItem(tab, coins)
		if def then
			state.Shop[tab] = def.Name
		end
	end
	if level >= playerProgress.RebirthLevel(rebirths) then
		state.Rebirth = rebirths + 1
	end
	if level >= playerProgress.AscendLevel() then
		state.Ascend = ascensions + 1
	end
	return state
end

-- One toast per key (item name, rebirth number, ascension number) per session, only once the
-- HUD has been up for ATTENTION_SETTLE seconds, and one at a time ATTENTION_TOAST_GAP apart:
-- a join with a full shop and a rebirth ready shows them one by one, never as a stack.
function api:AttentionToast(key, text)
	if self.AttentionToasted[key] then
		return
	end
	-- Not marked during the settle: the check that runs at ATTENTION_SETTLE shows these once.
	if os.clock() - (self.AttentionStarted or 0) < ATTENTION_SETTLE then
		return
	end
	self.AttentionToasted[key] = true
	table.insert(self.AttentionToastQueue, text)
	self:DrainAttentionToasts()
end

function api:DrainAttentionToasts()
	if self.AttentionDraining then
		return
	end
	self.AttentionDraining = true
	task.spawn(function()
		while #self.AttentionToastQueue > 0 do
			local wait = ATTENTION_TOAST_GAP - (os.clock() - (self.AttentionLastToast or -ATTENTION_TOAST_GAP))
			if wait > 0 then
				task.wait(wait)
			end
			local text = table.remove(self.AttentionToastQueue, 1)
			if text then
				self.AttentionLastToast = os.clock()
				Notify.Info(text)
			end
		end
		self.AttentionDraining = false
	end)
end

function api:UpdateAttention()
	self.AttentionQueued = false
	local main = self.MainUI
	if not main or not main.Parent then
		return
	end
	local state = self:AttentionState()
	local riding = isRiding()

	local shopReady = next(state.Shop) ~= nil
	local shopButton = main:FindFirstChild("Shop", true)
	if shopButton and shopButton:IsA("GuiButton") then
		local arrow = attentionArrow(shopButton)
		arrow.Visible = shopReady and not self.PanelShown.Shop and not riding
		self.Attention.Shop = if arrow.Visible then arrow else nil
	end
	for tab, itemName in state.Shop do
		if not self.PanelShown.Shop then
			self:AttentionToast("Shop:" .. itemName, ATTENTION_TOASTS[tab])
		end
	end

	local rebirthButton = main:FindFirstChild("Rebirth", true)
	if rebirthButton and rebirthButton:IsA("GuiButton") then
		local arrow = attentionArrow(rebirthButton)
		arrow.Visible = state.Rebirth ~= nil and not self.PanelShown.Rebirth and not riding
		self.Attention.Rebirth = if arrow.Visible then arrow else nil
	end
	if state.Rebirth and not self.PanelShown.Rebirth then
		self:AttentionToast("Rebirth:" .. tostring(state.Rebirth), ATTENTION_TOASTS.Rebirth)
	end

	self:SetAscendBillboard(state.Ascend ~= nil and not self.PanelShown.Ascend and not riding)
	if state.Ascend and not self.PanelShown.Ascend then
		self:AttentionToast("Ascend:" .. tostring(state.Ascend), ATTENTION_TOASTS.Ascend)
	end
end

function api:QueueAttention()
	if self.AttentionQueued then
		return
	end
	self.AttentionQueued = true
	task.defer(function()
		if self.AttentionQueued then
			self:UpdateAttention()
		end
	end)
end

-- A bobbing "ASCEND!" over the wings (BillboardGui on the tallest part of the Ascend model).
function api:SetAscendBillboard(on)
	local billboard = self.AscendBillboard
	if not on then
		if billboard then
			billboard:Destroy()
			self.AscendBillboard = nil
		end
		return
	end
	if billboard and billboard.Parent and billboard.Adornee and billboard.Adornee.Parent then
		return
	end
	local model = self:GetCircleModel("Ascend")
	if not model then
		return
	end
	local adornee = model:FindFirstChild("Ascend_05_Wings", true) or model:FindFirstChildWhichIsA("BasePart", true)
	if not adornee then
		return
	end
	if billboard then
		billboard:Destroy()
	end
	billboard = Instance.new("BillboardGui")
	billboard.Name = "AscendAttention"
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromOffset(120, 78)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, adornee.Size.Y / 2 + 4, 0)
	billboard.MaxDistance = 140
	billboard.AlwaysOnTop = false
	billboard.ResetOnSpawn = false
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0.5, 1)
	arrow.Position = UDim2.new(0.5, 0, 1, 0)
	arrow.Size = UDim2.fromOffset(40, 40)
	arrow.Image = ATTENTION_ARROW
	arrow.ImageColor3 = ATTENTION_COLOR
	arrow.Rotation = 90
	arrow.Parent = billboard
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 0, 0, 0)
	label.Size = UDim2.new(1, 0, 0, 34)
	label.Font = Enum.Font.FredokaOne
	label.Text = ASCEND_BILLBOARD_TEXT
	label.TextSize = 30
	label.TextColor3 = ATTENTION_COLOR
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(36, 25, 29)
	stroke.Thickness = 3
	stroke.Parent = label
	billboard.Parent = getPlayerGui()
	self.AscendBillboard = billboard
end

function api:ClearAttention()
	self.AttentionQueued = false
	table.clear(self.AttentionToastQueue)
	for _, arrow in self.Attention do
		if arrow and arrow.Parent then
			arrow.Visible = false
		end
	end
	table.clear(self.Attention)
	self:SetAscendBillboard(false)
end

function api:WatchAttention()
	self.AttentionStarted = os.clock()
	local player = Players.LocalPlayer
	for _, name in { "Coins", "Level", "Rebirths", "Ascensions", "UnlockedSnowballs", "UnlockedLaunchers", "UnlockedMountains" } do
		table.insert(self.Connections, player:GetAttributeChangedSignal(name):Connect(function()
			self:QueueAttention()
		end))
	end
	-- Bob the arrows on Heartbeat (tweens pause while Studio is unfocused; this does not), and
	-- re-check the ride / wings state now and then (the lobby generates after the HUD starts).
	local lastPoll = 0
	table.insert(self.Connections, RunService.Heartbeat:Connect(function()
		local bob = math.sin(os.clock() * ATTENTION_BOB_RATE) * ATTENTION_BOB
		for _, arrow in self.Attention do
			if arrow and arrow.Parent then
				arrow.Position = UDim2.new(1, ATTENTION_GAP + bob, 0.5, 0)
			end
		end
		local billboard = self.AscendBillboard
		if billboard and billboard.Adornee then
			billboard.StudsOffsetWorldSpace = Vector3.new(0, billboard.Adornee.Size.Y / 2 + 4 + bob * 0.2, 0)
		end
		if os.clock() - lastPoll >= 2 then
			lastPoll = os.clock()
			self:QueueAttention()
		end
	end))
	task.delay(ATTENTION_SETTLE, function()
		self:QueueAttention()
	end)
	self:QueueAttention()
end

return api
