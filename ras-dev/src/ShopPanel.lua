--[[---------------------------------------DESCRIPTION------------------------------------------
	ShopPanel: everything inside the HUD's Shop frame. HUD.luau still owns the panel
	itself (open / close pop, PanelManager exclusivity, the ShopCircle trigger, the X);
	on every open it calls ShopPanel.Setup(panel, hud), on every replicated progress
	change ShopPanel.Refresh(), and ShopPanel.Teardown() when it disconnects.

	The frame (ServerStorage.Assets.UserInterfaces.HUD.Shop, built by
	ras-dev/shop-remake/build_shop_frames.lua in the RobloxGames repo) is authored in
	design pixels on a 1140 x 735 Panel:
	  Shop (root)                         full screen; HUD pops its PanelScale
	    Dimmer (TextButton)               oversized, a click closes the shop
	    Panel + Fit (UIScale)             fitted to the screen here (FIT_*)
	      TabRail.Snowballs / .Blasters   tabs (TabScale, Dim overlay, gold outline)
	      Header ("SHOP" ribbon), X, Shadow
	      Body.Balance.Value              the coin balance, rolls to each new value
	      Body.Content.Heading            per-tab line
	      Body.Content.Grid               ScrollingFrame + UIGridLayout of cards
	      Templates.Card                  Title / Rarity / Mult / Icon / Lock / Equipped
	                                      ribbon (Stamp UIScale) / Buy pill (Coin + Label),
	                                      Pop UIScale on the card

	Cards: one per catalog entry (Snowballs.List / SnowballLaunchers.List), rarity
	gradient + stroke, "x8" multiplier chip, catalog icon. Buy pill states:
	  EQUIPPED (gold, inert) / EQUIP (green) / price (green = affordable, amber = not)
	  / price grayed (buy the earlier one first, padlock) / "BEAT <mountain>" (gray,
	  padlock; PlayerProgress.GearLockedBy on the replicated UnlockedMountains).
	The next card for sale pulses a gold outline and the grid scrolls to it on open.
	Cards pop in with a stagger on every fill, lift a little on hover (mouse only).

	Buying (ReFunction BuySnowball / BuyLauncher -> true, or false + reason) is
	checked on the client first (mountain, order, coins) so a refusal answers at
	once: PurchaseFX.Fail + Notify.Error. A purchase plays PurchaseFX.Success on the
	pill, pops the card, floats "UNLOCKED!", bursts confetti + a shockwave, sweeps a
	shine, flies coins from the pill into the balance (which then rolls down, red),
	and toasts. Equipping (ReEvent EquipSnowball / EquipLauncher) is optimistic: the
	EQUIPPED ribbon stamps onto the card immediately (thud + shimmer + shine), the
	old card loses it, and the replicated EquippedSnowball / EquippedLauncher
	attribute confirms (or reverts after EQUIP_CONFIRM seconds).

	All motion is stepped on Heartbeat (PurchaseFX.Animate), so it also plays in an
	unfocused Studio window. Dev hook (through HUD DevPress): "<Snowballs|Blasters>:<name>".

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local playerProgress = require(ReplicatedStorage.Assets.Modules.Shared.PlayerProgress)()
local snowballs = require(ReplicatedStorage.Assets.Modules.Shared.Snowballs)
local snowballLaunchers = require(ReplicatedStorage.Assets.Modules.Shared.SnowballLaunchers)
local PurchaseFX = require(script.Parent.PurchaseFX)
local Notify = require(script.Parent.Notify)
local Audio = require(ReplicatedStorage.Assets.Modules.Client.Audio)

local ShopPanel = {}

ShopPanel.DEFAULT_TAB = "Snowballs"
ShopPanel.TABS = { "Snowballs", "Blasters" }
ShopPanel.DESIGN = Vector2.new(1140, 735)
ShopPanel.FIT_MARGIN = Vector2.new(40, 120) -- screen px kept free around the panel (Notify toasts sit at 91.5 %)
ShopPanel.FIT_MIN = 0.35
ShopPanel.FIT_MAX = 1.1
ShopPanel.PANEL_CENTER_Y = 0.46 -- a little above centre: the toast strip stays clear below the panel
ShopPanel.HEADINGS = {
	Snowballs = "❄ SNOWBALLS — A BIGGER BALL EARNS MORE",
	Blasters = "🚀 BLASTERS — LAUNCH HARDER, ROLL FARTHER",
}
ShopPanel.RARITY = {
	Common = { Top = Color3.fromRGB(230, 247, 255), Bottom = Color3.fromRGB(166, 221, 245), Stroke = Color3.fromRGB(31, 78, 110), Text = Color3.fromRGB(221, 238, 255) },
	Uncommon = { Top = Color3.fromRGB(212, 255, 208), Bottom = Color3.fromRGB(98, 217, 108), Stroke = Color3.fromRGB(30, 90, 42), Text = Color3.fromRGB(214, 255, 210) },
	Rare = { Top = Color3.fromRGB(214, 228, 255), Bottom = Color3.fromRGB(93, 141, 255), Stroke = Color3.fromRGB(31, 60, 140), Text = Color3.fromRGB(214, 228, 255) },
	Epic = { Top = Color3.fromRGB(240, 216, 255), Bottom = Color3.fromRGB(178, 102, 255), Stroke = Color3.fromRGB(79, 28, 140), Text = Color3.fromRGB(240, 216, 255) },
	Legendary = { Top = Color3.fromRGB(255, 243, 184), Bottom = Color3.fromRGB(255, 201, 58), Stroke = Color3.fromRGB(122, 75, 0), Text = Color3.fromRGB(255, 243, 184) },
}
ShopPanel.PILLS = {
	Buy = { Top = Color3.fromRGB(159, 255, 66), Bottom = Color3.fromRGB(64, 214, 0), Stroke = Color3.fromRGB(34, 71, 10) },
	Poor = { Top = Color3.fromRGB(255, 210, 90), Bottom = Color3.fromRGB(245, 158, 11), Stroke = Color3.fromRGB(110, 62, 0) },
	Equip = { Top = Color3.fromRGB(159, 255, 66), Bottom = Color3.fromRGB(64, 214, 0), Stroke = Color3.fromRGB(34, 71, 10) },
	Equipped = { Top = Color3.fromRGB(255, 233, 107), Bottom = Color3.fromRGB(255, 184, 0), Stroke = Color3.fromRGB(107, 74, 0) },
	Locked = { Top = Color3.fromRGB(185, 194, 204), Bottom = Color3.fromRGB(122, 135, 148), Stroke = Color3.fromRGB(54, 62, 74) },
}
ShopPanel.TEXT = {
	Equip = "EQUIP",
	Equipped = "EQUIPPED",
	Locked = "BEAT %s",
	LockedToast = "Beat %s to unlock %s",
	InOrderToast = "Buy %s first",
	NeedMoreToast = "Need %s more",
	BoughtToast = "%s unlocked!",
	BoughtFloat = "UNLOCKED!",
	Refused = { Owned = "You already own that", Invalid = "Can't buy that" },
	Error = "Can't buy that right now",
}
ShopPanel.GOLD = Color3.fromRGB(255, 224, 68)
ShopPanel.NAVY = Color3.fromRGB(16, 42, 67)
ShopPanel.BALANCE_UP = Color3.fromRGB(156, 255, 122)
ShopPanel.BALANCE_DOWN = Color3.fromRGB(255, 138, 138)
ShopPanel.CARD_HOVER = 1.035
ShopPanel.CARD_POP = 1.14
ShopPanel.ENTRANCE_FROM = 0.6
ShopPanel.ENTRANCE_TIME = 0.26
ShopPanel.ENTRANCE_STAGGER = 0.03
ShopPanel.SCROLL_TIME = 0.4
ShopPanel.BALANCE_ROLL = 0.5
ShopPanel.EQUIP_CONFIRM = 2.5
ShopPanel.TAB_SELECTED = 1
ShopPanel.TAB_IDLE = 0.9
ShopPanel.TAB_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
ShopPanel.COIN_FLY = 8

local player = Players.LocalPlayer
local state = nil

----------------------------------------------------------------------------------------------
-- Catalog rules (shared with HUD.luau's attention arrows through the exports at the bottom)
----------------------------------------------------------------------------------------------

local function catalogFor(tab)
	if tab == "Blasters" then
		return snowballLaunchers
	end
	return snowballs
end

local function unlockedMap()
	return playerProgress.DecodeUnlocks(player:GetAttribute("UnlockedMountains"))
end

local function ownedMap(tab)
	if tab == "Blasters" then
		return playerProgress.DecodeNames(player:GetAttribute("UnlockedLaunchers"), playerProgress.STARTER_LAUNCHER)
	end
	return playerProgress.DecodeNames(player:GetAttribute("UnlockedSnowballs"), playerProgress.STARTER_SNOWBALL)
end

local function equippedName(tab)
	local name = player:GetAttribute(if tab == "Blasters" then "EquippedLauncher" else "EquippedSnowball")
	if type(name) == "string" and name ~= "" then
		return name
	end
	return if tab == "Blasters" then playerProgress.STARTER_LAUNCHER else playerProgress.STARTER_SNOWBALL
end

local function nextOrder(tab, owned)
	for _, def in catalogFor(tab).List do
		if owned[def.Name] ~= true then
			return def.Order
		end
	end
	return nil
end

-- The mountain to beat before gear of this order is sold, or nil when its mountain is open.
local function unlockMountain(order)
	local lockedBy = playerProgress.GearLockedBy(unlockedMap(), order)
	if not lockedBy then
		return nil
	end
	return mountainConfig:GetPreviousMountain(lockedBy) or lockedBy
end

local function orderForSale(order, owned, tab)
	if order ~= nextOrder(tab, owned) then
		return false
	end
	return playerProgress.GearLockedBy(unlockedMap(), order) == nil
end

local function coins()
	return math.max(0, math.floor(tonumber(player:GetAttribute("Coins")) or 0))
end

local SUFFIXES = { "K", "M", "B", "T" }

local function formatCompact(value, prefix)
	local n = tonumber(value) or 0
	if n < 1000 then
		return (prefix or "") .. tostring(math.floor(n + 0.5))
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES)
	local scaled = n / (10 ^ (tier * 3))
	if scaled >= 999.95 and tier < #SUFFIXES then
		tier += 1
		scaled = n / (10 ^ (tier * 3))
	end
	local text = string.format("%.1f", scaled):gsub("%.0$", "")
	return (prefix or "") .. text .. SUFFIXES[tier]
end

local function formatPrice(value)
	return formatCompact(value, "$")
end

local function formatCoins(amount)
	local n = math.max(0, math.floor(tonumber(amount) or 0))
	local text = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (text:gsub("^,", ""))
end

local function refusalText(reason, def, tab)
	if reason == "NotEnoughCoins" then
		return string.format(ShopPanel.TEXT.NeedMoreToast, formatPrice(math.max(1, (def.Price or 0) - coins())))
	end
	if reason == "MountainLocked" then
		local beat = unlockMountain(def.Order) or mountainConfig:GetPreviousMountain(def.MountainId) or def.MountainId
		return string.format(ShopPanel.TEXT.LockedToast, mountainConfig:GetDisplayName(beat), def.Name)
	end
	if reason == "BuyInOrder" then
		local order = nextOrder(tab, ownedMap(tab))
		local nextDef = order and catalogFor(tab):GetByOrder(order)
		if nextDef then
			return string.format(ShopPanel.TEXT.InOrderToast, nextDef.Name)
		end
	end
	return ShopPanel.TEXT.Refused[reason] or ShopPanel.TEXT.Error
end

----------------------------------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------------------------------

local function connect(signal, fn)
	local connection = signal:Connect(fn)
	table.insert(state.Connections, connection)
	return connection
end

local function prefersHover()
	return UserInputService.PreferredInput ~= Enum.PreferredInput.Touch
end

local function paint(frame, look)
	local gradient = frame:FindFirstChild("Gradient")
	if gradient and gradient:IsA("UIGradient") then
		gradient.Color = ColorSequence.new(look.Top, look.Bottom)
	end
	local outline = frame:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Color = look.Stroke
	end
end

local function cardScale(entry)
	entry.Pop.Scale = entry.Entrance * entry.Hover * entry.Bump
end

-- Heartbeat-stepped ease of one card factor (Entrance / Hover / Bump); a newer call cancels.
local function animateFactor(entry, key, target, duration, style, direction)
	local tokens = entry.Tokens
	local token = (tokens[key] or 0) + 1
	tokens[key] = token
	local from = entry[key]
	task.spawn(function()
		PurchaseFX.Animate(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, function(a)
			entry[key] = from + (target - from) * a
			cardScale(entry)
		end, function()
			return state ~= nil and tokens[key] == token and entry.Card.Parent ~= nil
		end)
		if state and tokens[key] == token then
			entry[key] = target
			cardScale(entry)
		end
	end)
end

local function setPill(entry, kind, text, showCoin)
	paint(entry.Buy, ShopPanel.PILLS[kind])
	entry.BuyLabel.Text = text
	entry.BuyCoin.Visible = showCoin
	if showCoin then
		entry.BuyLabel.Position = UDim2.new(0.5, 18, 0.5, 0)
		entry.BuyLabel.Size = UDim2.new(1, -80, 0, 34)
	else
		entry.BuyLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		entry.BuyLabel.Size = UDim2.new(1, -24, 0, 34)
	end
end

----------------------------------------------------------------------------------------------
-- Balance pill
----------------------------------------------------------------------------------------------

local function showBalance(value)
	state.Balance.Shown = value
	state.Refs.BalanceValue.Text = formatCoins(value)
end

local function bumpBalance()
	local pop = state.Refs.BalancePop
	local token = (state.Balance.PopToken or 0) + 1
	state.Balance.PopToken = token
	task.spawn(function()
		PurchaseFX.Animate(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
			pop.Scale = 1.14 - 0.14 * a
		end, function()
			return state ~= nil and state.Balance.PopToken == token
		end)
	end)
end

local function applyBalance(animate)
	if not state then
		return
	end
	local target = coins()
	local balance = state.Balance
	balance.Target = target
	if balance.Shown == nil or not animate or balance.Shown == target then
		showBalance(target)
		return
	end
	local from = balance.Shown
	local token = (balance.Token or 0) + 1
	balance.Token = token
	local label = state.Refs.BalanceValue
	label.TextColor3 = if target > from then ShopPanel.BALANCE_UP else ShopPanel.BALANCE_DOWN
	bumpBalance()
	task.spawn(function()
		PurchaseFX.Animate(ShopPanel.BALANCE_ROLL, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			showBalance(math.floor(from + (target - from) * a + 0.5))
		end, function()
			return state ~= nil and balance.Token == token
		end)
		if not (state and balance.Token == token) then
			return
		end
		showBalance(target)
		local flash = label.TextColor3
		PurchaseFX.Animate(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			label.TextColor3 = flash:Lerp(ShopPanel.GOLD, a)
		end, function()
			return state ~= nil and balance.Token == token
		end)
	end)
end

-- Coins changed: roll now, or once the coin flight of a purchase has landed.
local function queueBalance()
	if not state then
		return
	end
	local hold = (state.Balance.HoldUntil or 0) - os.clock()
	if hold > 0 then
		task.delay(hold, function()
			if state and os.clock() >= (state.Balance.HoldUntil or 0) then
				applyBalance(true)
			end
		end)
		return
	end
	applyBalance(true)
end

----------------------------------------------------------------------------------------------
-- Cards
----------------------------------------------------------------------------------------------

local function entriesOf(tab)
	local list = {}
	for _, entry in state.Cards do
		if entry.Tab == tab then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		return a.Def.Order < b.Def.Order
	end)
	return list
end

local function applyStates(tab, opts)
	if not state or state.Filled ~= tab then
		return
	end
	opts = opts or {}
	local owned = ownedMap(tab)
	local optimistic = state.Optimistic[tab]
	local replicated = equippedName(tab)
	if optimistic and optimistic == replicated then
		state.Optimistic[tab] = nil
		optimistic = nil
	end
	local equipped = optimistic or replicated
	local order = nextOrder(tab, owned)
	local balance = coins()
	state.PulseEntry = nil

	for _, entry in entriesOf(tab) do
		local def = entry.Def
		local isOwned = owned[def.Name] == true
		local isEquipped = def.Name == equipped
		local lockedBy = unlockMountain(def.Order)
		local kind, text, showCoin
		if isEquipped then
			kind, text, showCoin = "Equipped", ShopPanel.TEXT.Equipped, false
		elseif isOwned then
			kind, text, showCoin = "Equip", ShopPanel.TEXT.Equip, false
		elseif lockedBy then
			kind, text, showCoin = "Locked", string.format(ShopPanel.TEXT.Locked, string.upper(mountainConfig:GetDisplayName(lockedBy))), false
		elseif def.Order ~= order then
			kind, text, showCoin = "Locked", formatPrice(def.Price), true
		elseif balance < (def.Price or 0) then
			kind, text, showCoin = "Poor", formatPrice(def.Price), true
		else
			kind, text, showCoin = "Buy", formatPrice(def.Price), true
		end
		if not (state.Busy and state.BusyEntry == entry) then
			setPill(entry, kind, text, showCoin)
		end
		entry.Kind = kind
		local locked = kind == "Locked"
		entry.Lock.Visible = locked
		entry.Icon.ImageTransparency = if locked then 0.45 else 0
		entry.Buy.Active = kind ~= "Equipped"
		entry.Buy.AutoButtonColor = false

		local ribbon = entry.Equipped
		if isEquipped and not ribbon.Visible then
			if opts.animateEquip == def.Name then
				PurchaseFX.Stamp(ribbon)
			else
				ribbon.Visible = true
			end
		elseif not isEquipped and ribbon.Visible then
			if opts.animateEquip then
				PurchaseFX.Unstamp(ribbon)
			else
				ribbon.Visible = false
			end
		end

		if (kind == "Buy" or kind == "Poor") and not state.PulseEntry then
			state.PulseEntry = entry
		end
		if entry.PulseBase and entry ~= state.PulseEntry then
			entry.Outline.Color = entry.PulseBase
			entry.Outline.Thickness = 3
		end
	end
end

local function celebrate(entry)
	local card, buy = entry.Card, entry.Buy
	PurchaseFX.Success(buy)
	animateFactor(entry, "Bump", ShopPanel.CARD_POP, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(0.12, function()
		if state and entry.Card.Parent then
			animateFactor(entry, "Bump", 1, 0.24)
		end
	end)
	PurchaseFX.FloatText(card, ShopPanel.TEXT.BoughtFloat)
	PurchaseFX.Shockwave(card)
	PurchaseFX.Confetti(card, 34)
	PurchaseFX.Shine(card)
	PurchaseFX.CoinFly(buy, state.Refs.Balance, ShopPanel.COIN_FLY, function(index)
		if index == 1 and state then
			state.Balance.HoldUntil = 0
			applyBalance(true)
		end
	end)
end

local function buyItem(entry)
	local def, tab, buy = entry.Def, entry.Tab, entry.Buy
	state.Busy = true
	state.BusyEntry = entry
	local previous = entry.BuyLabel.Text
	entry.BuyLabel.Text = "..."
	state.Balance.HoldUntil = os.clock() + 1.5
	local invoked, ok, reason = pcall(function()
		return ReplicatedStorage.ReEvent.ReFunction:InvokeServer(if tab == "Blasters" then "BuyLauncher" else "BuySnowball", def.Name)
	end)
	if not state then
		return
	end
	state.Busy = false
	state.BusyEntry = nil
	if not entry.Card.Parent then
		return
	end
	if invoked and ok == true then
		celebrate(entry)
		Notify.Success(string.format(ShopPanel.TEXT.BoughtToast, def.Name))
	else
		state.Balance.HoldUntil = 0
		entry.BuyLabel.Text = previous
		if not invoked then
			warn("[CLIENT]: Shop purchase failed:", ok)
		end
		PurchaseFX.Fail(buy)
		Notify.Error(refusalText(if invoked then reason else nil, def, tab))
	end
	applyStates(tab)
end

local function equipItem(entry)
	local def, tab = entry.Def, entry.Tab
	PurchaseFX.Press(entry.Buy)
	state.Optimistic[tab] = def.Name
	applyStates(tab, { animateEquip = def.Name })
	Audio.Play("UISuccess")
	PurchaseFX.Sound({ "Magic Shimmer", 0.7 })
	PurchaseFX.Shine(entry.Card)
	ReplicatedStorage.ReEvent:FireServer(if tab == "Blasters" then "EquipLauncher" else "EquipSnowball", def.Name)
	task.delay(ShopPanel.EQUIP_CONFIRM, function()
		if state and state.Optimistic[tab] == def.Name and equippedName(tab) ~= def.Name then
			state.Optimistic[tab] = nil
			applyStates(tab)
		end
	end)
end

local function press(entry)
	if not state or state.Busy then
		return
	end
	local def, tab, buy = entry.Def, entry.Tab, entry.Buy
	local owned = ownedMap(tab)
	if owned[def.Name] == true then
		if def.Name == (state.Optimistic[tab] or equippedName(tab)) then
			PurchaseFX.Press(buy)
			return
		end
		equipItem(entry)
		return
	end

	PurchaseFX.Press(buy)
	local refusal = nil
	if unlockMountain(def.Order) then
		refusal = "MountainLocked"
	elseif def.Order ~= nextOrder(tab, owned) then
		refusal = "BuyInOrder"
	elseif coins() < (def.Price or 0) then
		refusal = "NotEnoughCoins"
	end
	if refusal then
		PurchaseFX.Fail(buy)
		Notify.Error(refusalText(refusal, def, tab))
		return
	end
	buyItem(entry)
end

local function entrance(tab)
	local list = entriesOf(tab)
	local token = (state.EntranceToken or 0) + 1
	state.EntranceToken = token
	for _, entry in list do
		entry.Tokens.Entrance = (entry.Tokens.Entrance or 0) + 1
		entry.Entrance = ShopPanel.ENTRANCE_FROM
		cardScale(entry)
	end
	task.spawn(function()
		local start = os.clock()
		local from = ShopPanel.ENTRANCE_FROM
		local total = ShopPanel.ENTRANCE_TIME + (#list - 1) * ShopPanel.ENTRANCE_STAGGER
		local done = false
		while not done do
			local dt = RunService.Heartbeat:Wait()
			if not state or state.EntranceToken ~= token then
				return
			end
			local now = os.clock() - start
			done = now >= total
			for index, entry in list do
				local a = math.clamp((now - (index - 1) * ShopPanel.ENTRANCE_STAGGER) / ShopPanel.ENTRANCE_TIME, 0, 1)
				entry.Entrance = from + (1 - from) * TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				cardScale(entry)
			end
		end
		for _, entry in list do
			entry.Entrance = 1
			cardScale(entry)
		end
	end)
end

-- Scroll the grid so the next card for sale (else the equipped one) sits near the top.
local function scrollToFocus(tab)
	local grid = state.Refs.Grid
	local token = (state.ScrollToken or 0) + 1
	state.ScrollToken = token
	task.delay(0.05, function()
		if not state or state.ScrollToken ~= token or state.Filled ~= tab then
			return
		end
		local target = state.PulseEntry
		if not target then
			for _, entry in entriesOf(tab) do
				if entry.Kind == "Equipped" then
					target = entry
					break
				end
			end
		end
		if not target then
			return
		end
		-- Row geometry from the layout, not from AbsolutePosition: a card mid pop-in (Pop < 1)
		-- reports the top-left of its shrunken rect, and the panel itself is still popping.
		local layout = grid:FindFirstChildOfClass("UIGridLayout")
		local padding = grid:FindFirstChildOfClass("UIPadding")
		if not layout then
			return
		end
		local cellWidth = layout.CellSize.X.Offset
		local cellHeight = layout.CellSize.Y.Offset
		local padY = layout.CellPadding.Y.Offset
		local padTop = if padding then padding.PaddingTop.Offset else 0
		local columns = math.max(1, layout.FillDirectionMaxCells)
		local row = 0
		for index, entry in entriesOf(tab) do
			if entry == target then
				row = math.floor((index - 1) / columns)
				break
			end
		end
		local function desiredY()
			-- screen px per design px right now (Fit x the HUD's pop scale)
			local k = target.Card.AbsoluteSize.X / math.max(1e-3, cellWidth * target.Pop.Scale)
			local rowY = (padTop + row * (cellHeight + padY) - 12) * k
			local maximum = math.max(0, grid.AbsoluteCanvasSize.Y - grid.AbsoluteWindowSize.Y)
			return math.clamp(rowY, 0, maximum)
		end
		local from = grid.CanvasPosition.Y
		if math.abs(desiredY() - from) < 2 then
			return
		end
		PurchaseFX.Animate(ShopPanel.SCROLL_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
			grid.CanvasPosition = Vector2.new(0, from + (desiredY() - from) * a)
		end, function()
			return state ~= nil and state.ScrollToken == token
		end)
	end)
end

local function bindCardHover(entry)
	local card = entry.Card
	connect(card.MouseEnter, function()
		if state and prefersHover() and entry.Kind ~= "Locked" then
			animateFactor(entry, "Hover", ShopPanel.CARD_HOVER, 0.12)
		end
	end)
	connect(card.MouseLeave, function()
		if state then
			animateFactor(entry, "Hover", 1, 0.14)
		end
	end)
end

local function fill(tab)
	local refs = state.Refs
	local grid, template = refs.Grid, refs.Template
	state.EntranceToken = (state.EntranceToken or 0) + 1
	for _, child in grid:GetChildren() do
		if child:GetAttribute("ShopItem") then
			child:Destroy()
		end
	end
	table.clear(state.Cards)
	state.PulseEntry = nil

	for _, def in catalogFor(tab).List do
		local card = template:Clone()
		card.Name = def.Name
		card.LayoutOrder = def.Order
		card.Visible = true
		card:SetAttribute("ShopItem", true)
		card:SetAttribute("ShopTab", tab)
		card:SetAttribute("Order", def.Order)
		card:SetAttribute("ShopPrice", def.Price)

		local look = ShopPanel.RARITY[def.Rarity] or ShopPanel.RARITY.Common
		paint(card, look)
		card.Title.Text = def.Name
		card.Rarity.Text = string.upper(def.Rarity)
		card.Rarity.TextColor3 = look.Text
		card.Mult.Label.Text = "x" .. formatCompact(def.Multiplier)
		card.Icon.Image = def.Icon or ""
		local buy = card.Buy
		buy:SetAttribute("HoverScaleBound", true) -- UIUtils skips it; the pill pops through PurchaseFX

		local entry = {
			Card = card,
			Def = def,
			Tab = tab,
			Pop = card.Pop,
			Outline = card.Outline,
			PulseBase = look.Stroke,
			Buy = buy,
			BuyLabel = buy.Label,
			BuyCoin = buy.Coin,
			Icon = card.Icon,
			Lock = card.Lock,
			Equipped = card.Equipped,
			Entrance = 1,
			Hover = 1,
			Bump = 1,
			Tokens = {},
			Kind = "Locked",
		}
		state.Cards[def.Name] = entry
		connect(buy.Activated, function()
			press(entry)
		end)
		bindCardHover(entry)
		card.Parent = grid
	end
	state.Filled = tab
	applyStates(tab)
end

----------------------------------------------------------------------------------------------
-- Tabs, fit, pulse
----------------------------------------------------------------------------------------------

local function styleTabs(tab)
	for name, button in state.Refs.Tabs do
		local selected = name == tab
		local scale = button:FindFirstChild("TabScale")
		if scale then
			TweenService:Create(scale, ShopPanel.TAB_TWEEN, { Scale = if selected then ShopPanel.TAB_SELECTED else ShopPanel.TAB_IDLE }):Play()
		end
		local dim = button:FindFirstChild("Dim")
		if dim then
			dim.BackgroundTransparency = if selected then 1 else 0.6
		end
		local outline = button:FindFirstChild("Outline")
		if outline then
			outline.Color = if selected then ShopPanel.GOLD else ShopPanel.NAVY
			outline.Thickness = 4
		end
	end
end

function ShopPanel.SetTab(tab)
	if not state or not table.find(ShopPanel.TABS, tab) then
		return
	end
	state.Tab = tab
	styleTabs(tab)
	state.Refs.Heading.Text = ShopPanel.HEADINGS[tab] or string.upper(tab)
	if state.Filled ~= tab then
		fill(tab)
	else
		applyStates(tab)
	end
	entrance(tab)
	scrollToFocus(tab)
end

local function fit()
	local refs = state.Refs
	local screen = refs.Screen
	if not screen then
		return
	end
	local size = screen.AbsoluteSize
	local scale = math.min((size.X - ShopPanel.FIT_MARGIN.X) / ShopPanel.DESIGN.X, (size.Y - ShopPanel.FIT_MARGIN.Y) / ShopPanel.DESIGN.Y)
	refs.Fit.Scale = math.clamp(scale, ShopPanel.FIT_MIN, ShopPanel.FIT_MAX)
	refs.Panel.Position = UDim2.fromScale(0.5, ShopPanel.PANEL_CENTER_Y)
end

local function startPulse()
	if state.Pulse then
		return
	end
	state.Pulse = connect(RunService.Heartbeat, function()
		local entry = state.PulseEntry
		if not entry or not state.Root.Visible then
			return
		end
		local k = 0.5 + 0.5 * math.sin(os.clock() * 4.2)
		entry.Outline.Color = entry.PulseBase:Lerp(ShopPanel.GOLD, k)
		entry.Outline.Thickness = 3 + 1.6 * k
	end)
end

----------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------

function ShopPanel.Teardown()
	if not state then
		return
	end
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	state = nil
end

-- Called by HUD.luau on every open. `host` is the HUD api (HidePanel closes the shop).
function ShopPanel.Setup(root, host)
	if state and state.Root == root and root.Parent then
		state.Host = host or state.Host
		fit()
		applyBalance(false)
		ShopPanel.SetTab(state.Tab or ShopPanel.DEFAULT_TAB)
		return true
	end
	ShopPanel.Teardown()

	local panel = root:FindFirstChild("Panel")
	local body = panel and panel:FindFirstChild("Body")
	local content = body and body:FindFirstChild("Content")
	local grid = content and content:FindFirstChild("Grid")
	local templates = panel and panel:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("Card")
	local balance = body and body:FindFirstChild("Balance")
	local rail = panel and panel:FindFirstChild("TabRail")
	if not (grid and template and balance and rail) then
		warn("[CLIENT]: Shop frame is missing Panel.Body.Content.Grid / Templates.Card / Body.Balance / TabRail")
		return false
	end

	state = {
		Root = root,
		Host = host,
		Connections = {},
		Cards = {},
		Optimistic = {},
		Balance = {},
		Tab = ShopPanel.DEFAULT_TAB,
		Filled = nil,
		Busy = false,
		Refs = {
			Screen = root:FindFirstAncestorWhichIsA("ScreenGui"),
			Panel = panel,
			Fit = panel:FindFirstChild("Fit") or Instance.new("UIScale", panel),
			Grid = grid,
			Template = template,
			Heading = content:FindFirstChild("Heading"),
			Balance = balance,
			BalanceValue = balance:FindFirstChild("Value"),
			BalancePop = balance:FindFirstChild("Pop") or Instance.new("UIScale", balance),
			Tabs = {},
		},
	}
	local refs = state.Refs
	refs.Fit.Name = "Fit"
	for _, name in ShopPanel.TABS do
		local button = rail:FindFirstChild(name)
		if button and button:IsA("GuiButton") then
			refs.Tabs[name] = button
			connect(button.Activated, function()
				if state and state.Tab ~= name then
					Audio.Play("UITab")
					ShopPanel.SetTab(name)
				end
			end)
		else
			warn("[CLIENT]: Shop tab not found:", name)
		end
	end

	local dimmer = root:FindFirstChild("Dimmer")
	if dimmer and dimmer:IsA("GuiButton") then
		connect(dimmer.Activated, function()
			if state and state.Host and state.Host.HidePanel then
				state.Host:HidePanel("Shop")
			end
		end)
	end
	if refs.Screen then
		connect(refs.Screen:GetPropertyChangedSignal("AbsoluteSize"), fit)
	end
	connect(player:GetAttributeChangedSignal("Coins"), queueBalance)

	fit()
	applyBalance(false)
	startPulse()
	ShopPanel.SetTab(state.Tab)
	return true
end

-- Replicated progress changed (CLIENT_PlayerProgress -> HUD.RefreshShopPanel).
function ShopPanel.Refresh()
	if not state then
		return
	end
	if state.Filled then
		applyStates(state.Filled, { animateEquip = state.Optimistic[state.Filled] })
	end
end

-- Dev hook: press a card's pill exactly as a click would ("Snowballs:Coal").
function ShopPanel.DevPress(tab, name)
	if not state then
		return false
	end
	ShopPanel.SetTab(tab)
	local entry = state.Cards[name]
	if not entry then
		warn("[CLIENT]: Shop DevPress: unknown item", tab, name)
		return false
	end
	press(entry)
	return true
end

function ShopPanel.IsOpen()
	return state ~= nil and state.Root.Visible
end

-- Catalog rules, shared with HUD.luau (attention arrows).
ShopPanel.Catalog = catalogFor
ShopPanel.OwnedMap = ownedMap
ShopPanel.EquippedName = equippedName
ShopPanel.NextOrder = nextOrder
ShopPanel.OrderForSale = orderForSale
ShopPanel.UnlockMountain = unlockMountain
ShopPanel.FormatPrice = formatPrice

return ShopPanel
