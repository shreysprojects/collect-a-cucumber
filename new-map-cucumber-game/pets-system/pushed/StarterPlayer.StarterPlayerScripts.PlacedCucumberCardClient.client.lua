--[[
	PlacedCucumberCardClient  (LocalScript, StarterPlayerScripts)
	The overhead card on every cucumber standing on a plot (tag "PlacedCucumber", placed by
	CucumberCarry), styled after the Zombie Cucumber Game's vault EarnBillboard (2026-09-06):
	  1. its biome, in the biome's colour (the rarity slot: every biome pays x8 the last)
	  2. its name, white ("Golden" in gold)
	  3. $6.3M/s in green -- the Rate attribute LeaderstatsService stamps on the model
	     (CucumberValues.RateOf while it is on its way), abbreviated by NumberAbbrev. User
	     2026-09-19: plain "$" text instead of the cash icon, in the HUD cash counter's green
	Sized in STUDS (scale units) with a scale-only layout, exactly like PlotBadges' owner badge
	(user, 2026-09-06): the card shrinks with distance like a world object instead of staying a
	fixed number of pixels that reads bigger the farther you stand.
	Built locally on each client and adorned to the cucumber's PlotHitbox (the footprint box
	CucumberCarry adds), so its bottom edge floats a fixed gap above the model's top; removed when
	the cucumber leaves the plot or streams out.
	INCOME POPUPS (user, 2026-09-12): every second LeaderstatsService pays each placed cucumber's
	Rate into its owner's Cash and fires Remotes.CucumberIncome (models, amounts). For every cucumber
	that paid and has a card here, a "+$X" popup (green, same recipe as the card's cash line,
	sized in studs) starts with its bottom edge on the card's TOP edge and floats up POPUP_RISE studs
	over POPUP_TIME seconds, popping in and fading out over the second half. Heartbeat-stepped like
	the other popups (plays in an unfocused Studio too). Skipped beyond POPUP_MAX_DISTANCE so a busy
	plot far away costs nothing.
	PET BUFF BADGES (2026-09-22, pet-system polish): while a pet ability is live on the cucumber
	(attributes PetBuff_Yield / PetBuff_Haste / PetBuff_Guard = its expiry on the server clock,
	written by PetBuffService) a 4th row "Buffs" sits UNDER the cash line: "x1.5 1:29" (gold),
	"+25% 1:29" (cyan) and shield + charges + countdown (green) -- badge texts from
	PetStats.AbilityBadge, colours from PetBalance.ABILITIES. The card grows by BADGE_H studs only
	while at least one buff is live (the other rows are renormalised, so their text sizes never
	change, and card.Top follows so income popups still start on the card's top edge); an unbuffed
	card is exactly the old one. Countdowns tick every BADGE_TICK s from one shared accumulator.
	Only real placed cucumbers show badges (Parent named "Placed" inside workspace.Map.Lobby.Plots,
	re-checked on AncestryChanged): the build-mode move ghost keeps the tag and the PetBuff_*
	attributes but never shows them. The pet modules are resolved lazily, so a missing one only
	turns the badges off. The income popup loop now walks `for i = 1, #amounts` (a cucumber
	streamed out on this client arrives as nil and used to stop ipairs early).
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))
local CucumberMutations = require(Modules:WaitForChild("CucumberMutations"))

local TAG = "PlacedCucumber"
local INCOME_REMOTE = "CucumberIncome"
local FONT = Enum.Font.FredokaOne
local CARD_W, CARD_H = 6, 2.64 -- studs (scale = studs on a BillboardGui, like PlotBadges' 14.06 x 10.31 badge)
local BIOME_FRAC, NAME_FRAC, RATE_FRAC = 0.30, 0.37, 0.33 -- line heights as fractions of CARD_H
local GAP_ABOVE = 0.8 -- studs between the model's top and the card's bottom edge
local MAX_DISTANCE = 60
--.. the HUD cash counter's colours (StarterGui.CucumberHUDDesign.Counters.CashValue + its UIStroke)
local CASH_GREEN = Color3.fromRGB(65, 235, 20)
local CASH_STROKE = Color3.fromRGB(12, 12, 12)
local WHITE = Color3.fromRGB(255, 255, 255)
local DARK_STROKE = Color3.fromRGB(25, 20, 35)
local STROKE = 2.4 -- px, like the owner badge's 2.5 px name stroke
--.. the "+X" income popup
local POPUP_W, POPUP_H = 4.4, 1.05 -- studs (scale = studs), the card's cash line at about its own size
local POPUP_RISE = 2.6 -- studs it floats up from the card's top edge
local POPUP_TIME = 1.0 -- seconds it lives (the next one comes a second later)
local POPUP_POP = 0.16 -- seconds for the scale pop-in (0.3 -> 1.12 -> 1)
local POPUP_FADE_FROM = 0.5 -- fraction of POPUP_TIME where the fade-out starts
local POPUP_MAX_DISTANCE = 70 -- studs from the camera beyond which no popup is built
--.. pet buff badges (2026-09-22)
local BADGE_H = 0.8 -- studs the card grows by while at least one pet buff is live
local BADGE_KINDS = {"Yield", "Haste", "Guard"} -- badge order, left to right
local BADGE_TICK = 0.25 -- s between countdown refreshes (one shared accumulator)
local BADGE_BACK = Color3.fromRGB(12, 12, 12) -- the dark pill behind a badge
local BADGE_BACK_TRANSPARENCY = 0.4
local SHIELD_GLYPH = "\u{1F6E1}\u{FE0F}"

--..Pure badge helpers (2026-09-22): the unit tests load this source with loadstring(src)("__core")..--
local Core = {}

local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
Core.Finite = Finite

--.. "1:30" for 89.2 s (rounded UP, so a live buff never reads 0:00); broken or <= 0 -> "0:00"; capped at 99:59
function Core.FormatCountdown(seconds)
	if not Finite(seconds) or seconds <= 0 then return "0:00" end
	local whole = math.min(math.ceil(seconds), 5999)
	return ("%d:%02d"):format(whole // 60, whole % 60)
end

--.. the kinds (in `order`) whose PetBuff_<kind> expiry is still ahead of now; model = anything with GetAttribute
function Core.LiveBuffs(model, now, order)
	local kinds = {}
	for _, kind in ipairs(order) do
		local expiresAt = model:GetAttribute("PetBuff_" .. kind)
		if Finite(expiresAt) and Finite(now) and expiresAt > now then kinds[#kinds + 1] = kind end
	end
	return kinds
end

--.. badge width as a fraction of the card for n badges side by side
function Core.BadgeWidth(n)
	if n <= 1 then return 0.5 end
	return math.min(0.5, 0.96 / n - 0.02)
end

--.. "x1.5 1:30" / "+25% 1:30" / "<shield>1 3:59" (Guard shows its live charges, else the badge text)
function Core.BadgeText(kind, badge, charges, remaining, shieldGlyph)
	local countdown = Core.FormatCountdown(remaining)
	if kind == "Guard" then
		local count = Finite(charges) and charges >= 1 and tostring(math.floor(charges)) or tostring(badge or "")
		return (shieldGlyph or "") .. count .. " " .. countdown
	end
	if type(badge) ~= "string" or badge == "" then return countdown end
	return badge .. " " .. countdown
end

if ... == "__core" then return Core end -- unit tests only: a LocalScript is never started with arguments

local Cards = {} -- [model] = {Gui, Conns, Adornee, Top, Grow, HalfUp, CardW, CardH, Rows, BadgeRow, Badges, BadgeKey}
local animations = {} -- live popups: one stepping function each
local BuffCards = {} -- [model] = card, for the cards showing at least one badge (the countdown accumulator walks these)

--.. PetBalance / PetStats, resolved lazily (2026-09-22): a missing pet module only turns the badges off, never the card
local petModules = nil
local function PetModules()
	if petModules ~= nil then return petModules or nil end
	local balance, stats = Modules:FindFirstChild("PetBalance"), Modules:FindFirstChild("PetStats")
	if not balance or not stats then return nil end -- not installed (yet): asked again next time
	local okBalance, Balance = pcall(require, balance)
	local okStats, Stats = pcall(require, stats)
	if okBalance and okStats and type(Balance) == "table" and type(Stats) == "table" then
		petModules = {Balance = Balance, Stats = Stats}
	else
		petModules = false
		warn("[PlacedCucumberCardClient] pet modules failed to load - buff badges are off")
	end
	return petModules or nil
end

local function Line(parent, text, frac, color, strokeColor, order)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, frac)
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.LayoutOrder = order
	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Thickness = STROKE
	stroke.Parent = t
	t.Parent = parent
	return t
end

--.. the green "$6.3M/s" text, centred in its row: the row is a fraction of the card and the text
--.. auto-widens from its scaled height -- no pixel sizes anywhere, so the line rides the stud sizing
--.. (the cash icon that used to sit left of the number is gone: the "$" says it, user 2026-09-19)
local function CashLine(parent, frac, order)
	local row = Instance.new("Frame")
	row.Name = "CashLine"
	row.Size = UDim2.fromScale(1, frac)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = row
	local t = Instance.new("TextLabel")
	t.Name = "Rate"
	t.BackgroundTransparency = 1
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromScale(0, 1)
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = CASH_GREEN
	t.Text = ""
	t.LayoutOrder = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = CASH_STROKE
	stroke.Thickness = STROKE
	stroke.Parent = t
	t.Parent = row
	row.Parent = parent
	return t, stroke, row
end

local function RateText(model)
	local rate = tonumber(model:GetAttribute("Rate")) or CucumberValues.RateOfInstance(model)
	return "$" .. NumberAbbrev.Abbrev(rate) .. "/s"
end

local function NameText(model)
	--.. material + mutation words in their colours (CucumberMutations: "Golden NEON Cucumber")
	return CucumberMutations.ColorizeName(model:GetAttribute("CucumberName") or model.Name)
end

--..Pet buff badges (2026-09-22)..--
--.. a real placed cucumber, not the build-mode move ghost ("<name> Preview", parented to workspace)
local function IsRealPlaced(model)
	local parent = model.Parent
	if not parent or parent.Name ~= "Placed" then return false end
	local map = workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	local plots = lobby and lobby:FindFirstChild("Plots")
	return plots ~= nil and model:IsDescendantOf(plots)
end

--.. (re)build the "Buffs" row for `kinds` and resize the card: the old rows keep their stud heights
local function SetBadgeRow(card, kinds, mods)
	local n = #kinds
	local grow = card.Grow or 1
	local total = n > 0 and card.CardH + BADGE_H * grow or card.CardH
	local s = card.CardH / total
	for _, row in ipairs(card.Rows) do row[1].Size = UDim2.fromScale(1, row[2] * s) end
	card.Gui.Size = UDim2.fromScale(card.CardW, total)
	card.Gui.StudsOffsetWorldSpace = Vector3.new(0, card.HalfUp + GAP_ABOVE * grow + total * 0.5, 0)
	card.Top = card.HalfUp + GAP_ABOVE * grow + total
	if card.BadgeRow then card.BadgeRow:Destroy() end
	card.BadgeRow, card.Badges = nil, {}
	card.BadgeKey = table.concat(kinds, ",")
	if n == 0 then return end
	local abilities = mods and type(mods.Balance.ABILITIES) == "table" and mods.Balance.ABILITIES or {}
	local row = Instance.new("Frame")
	row.Name = "Buffs"
	row.Size = UDim2.fromScale(1, BADGE_H * grow / total)
	row.BackgroundTransparency = 1
	row.LayoutOrder = 4
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0.02, 0)
	lay.Parent = row
	for i, kind in ipairs(kinds) do
		local info = abilities[kind]
		local color = info and typeof(info.Color) == "Color3" and info.Color or WHITE
		local badge = Instance.new("TextLabel")
		badge.Name = kind
		badge.Size = UDim2.fromScale(Core.BadgeWidth(n), 0.9)
		badge.BackgroundColor3 = BADGE_BACK
		badge.BackgroundTransparency = BADGE_BACK_TRANSPARENCY
		badge.Font = FONT
		badge.TextScaled = true
		badge.TextColor3 = color
		badge.Text = ""
		badge.LayoutOrder = i
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = badge
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0.08, 0), UDim.new(0.08, 0)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0.1, 0), UDim.new(0.1, 0)
		pad.Parent = badge
		local stroke = Instance.new("UIStroke")
		stroke.Color = CASH_STROKE
		stroke.Thickness = STROKE
		stroke.Parent = badge
		badge.Parent = row
		card.Badges[kind] = badge
	end
	row.Parent = card.Gui
	card.BadgeRow = row
end

local function RenderBadges(model, card, now, mods)
	for kind, badge in pairs(card.Badges) do
		local expiresAt = model:GetAttribute("PetBuff_" .. kind)
		local remaining = Finite(expiresAt) and expiresAt - now or 0
		badge.Text = Core.BadgeText(kind, mods.Stats.AbilityBadge(kind), model:GetAttribute("PetBuff_GuardCharges"), remaining, SHIELD_GLYPH)
	end
end

--.. on PetBuff_* changes, ancestry changes (ghost filter) and every BADGE_TICK while badges show
local function RefreshBuffs(model)
	local card = Cards[model]
	if not card or not card.Gui or not card.CardH then return end
	local now = workspace:GetServerTimeNow()
	local mods = IsRealPlaced(model) and PetModules() or nil
	local kinds = mods and Core.LiveBuffs(model, now, BADGE_KINDS) or {}
	if table.concat(kinds, ",") ~= (card.BadgeKey or "") then SetBadgeRow(card, kinds, mods) end
	if #kinds > 0 then
		BuffCards[model] = card
		RenderBadges(model, card, now, mods)
	else
		BuffCards[model] = nil
	end
end

local function Build(model)
	if Cards[model] then return end
	local card = {Conns = {}}
	Cards[model] = card -- reserved while the footprint box streams in
	task.spawn(function()
		local hitbox = model:WaitForChild("PlotHitbox", 5)
		if Cards[model] ~= card or not model:IsDescendantOf(workspace) then return end
		local adornee, halfUp
		if hitbox and hitbox:IsA("BasePart") then
			adornee, halfUp = hitbox, hitbox.Size.Y * 0.5
		else
			adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			if not adornee then Cards[model] = nil return end
			local cf, ext = model:GetBoundingBox()
			halfUp = cf.Position.Y + ext.Y * 0.5 - adornee.Position.Y
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "CucumberCard"
		gui.Adornee = adornee
		--.. a giant carries a proportionally bigger card (square-rooted, so it grows with the
		--.. cucumber without turning into a billboard of its own) -- still sized in STUDS either way
		local grow = math.sqrt(math.max(tonumber(model:GetAttribute("SizeScale")) or 1, 1))
		local cardW, cardH = CARD_W * grow, CARD_H * grow
		gui.Size = UDim2.fromScale(cardW, cardH) -- scale = studs: shrinks with distance
		--.. the billboard is centred on its offset: lift it by half its height so the BOTTOM edge sits GAP_ABOVE over the model
		gui.StudsOffsetWorldSpace = Vector3.new(0, halfUp + GAP_ABOVE * grow + cardH * 0.5, 0)
		gui.AlwaysOnTop = false
		--.. cucumbers stand at full size since 2026-09-08, so a card can start 50 studs up: the
		--.. flat 60-stud cut-off used to hide a giant's card before you could read it
		gui.MaxDistance = MAX_DISTANCE + halfUp * 2
		gui.LightInfluence = 0
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = gui
		local zone = model:GetAttribute("Zone") or "Spawn"
		local zoneText, zoneStroke = CucumberValues.ZoneTextColors(zone)
		local biomeLabel = Line(gui, zone, BIOME_FRAC, zoneText, zoneStroke, 1)
		biomeLabel.Name = "Biome"
		local nameLabel = Line(gui, NameText(model), NAME_FRAC, WHITE, DARK_STROKE, 2)
		nameLabel.Name = "CucumberName"
		nameLabel.RichText = true
		local rateLabel, _, cashRow = CashLine(gui, RATE_FRAC, 3)
		rateLabel.Text = RateText(model)
		gui.Parent = adornee
		card.Gui = gui
		card.Adornee = adornee
		card.Grow = grow
		card.HalfUp = halfUp
		card.Top = halfUp + GAP_ABOVE * grow + cardH -- the card's TOP edge, studs above the adornee: where a popup starts
		card.CardW, card.CardH = cardW, cardH -- the unbuffed size; SetBadgeRow grows from it
		card.Rows = {{biomeLabel, BIOME_FRAC}, {nameLabel, NAME_FRAC}, {cashRow, RATE_FRAC}}
		table.insert(card.Conns, model:GetAttributeChangedSignal("Rate"):Connect(function()
			rateLabel.Text = RateText(model)
		end))
		--.. pet buff badges (2026-09-22): PetBuff_* changes + the ghost filter re-check on ancestry changes
		table.insert(card.Conns, model.AttributeChanged:Connect(function(name)
			if string.sub(name, 1, 8) == "PetBuff_" then RefreshBuffs(model) end
		end))
		table.insert(card.Conns, model.AncestryChanged:Connect(function()
			RefreshBuffs(model)
		end))
		RefreshBuffs(model)
	end)
end

local function Remove(model)
	local card = Cards[model]
	if not card then return end
	Cards[model] = nil
	BuffCards[model] = nil
	for _, c in ipairs(card.Conns) do c:Disconnect() end
	if card.Gui then card.Gui:Destroy() end
end

--..Income popups: "+$X" floating up from the top edge of the cucumber's card..--
local function Popup(model, amount)
	local card = Cards[model]
	local adornee = card and card.Adornee
	if not adornee or not adornee.Parent or not card.Top then return end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - adornee.Position).Magnitude > POPUP_MAX_DISTANCE + (card.HalfUp or 0) * 2 then return end
	local grow = card.Grow or 1
	local w, h = POPUP_W * grow, POPUP_H * grow
	local gui = Instance.new("BillboardGui")
	gui.Name = "IncomePopup"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(w, h) -- scale = studs: shrinks with distance like the card
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = card.Gui and card.Gui.MaxDistance or MAX_DISTANCE
	local startY = card.Top + h * 0.5 -- centred billboard: its bottom edge sits on the card's top edge
	gui.StudsOffsetWorldSpace = Vector3.new(0, startY, 0)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = frame
	local label, stroke = CashLine(frame, 1, 1)
	label.Name = "Amount"
	label.Text = "+$" .. NumberAbbrev.Abbrev(amount)
	gui.Parent = adornee
	local t0 = os.clock()
	local rise = POPUP_RISE * grow
	table.insert(animations, function(now)
		local t = now - t0
		if t >= POPUP_TIME or not adornee.Parent or not gui.Parent then
			gui:Destroy()
			return false
		end
		local k = t / POPUP_TIME
		local eased = 1 - (1 - k) * (1 - k) -- quad out: fast off the card, easing as it fades
		gui.StudsOffsetWorldSpace = Vector3.new(0, startY + rise * eased, 0)
		local s = 1
		if t < POPUP_POP then
			local p = t / POPUP_POP
			if p < 0.7 then
				s = 0.3 + 0.82 * (p / 0.7)
			else
				s = 1.12 - 0.12 * ((p - 0.7) / 0.3)
			end
		end
		scale.Scale = s
		local f = math.clamp((k - POPUP_FADE_FROM) / (1 - POPUP_FADE_FROM), 0, 1)
		label.TextTransparency = f
		stroke.Transparency = f
		return true
	end)
end

--.. Heartbeat, not RenderStepped: keeps stepping while the Studio window is unfocused (like ButtonFX)
RunService.Heartbeat:Connect(function()
	if #animations == 0 then return end
	local now = os.clock()
	for index = #animations, 1, -1 do
		if not animations[index](now) then
			animations[index] = animations[#animations]
			animations[#animations] = nil
		end
	end
end)

--.. pet buff badge countdowns (2026-09-22): one shared accumulator, only while a badge shows
local badgeClock = 0
RunService.Heartbeat:Connect(function(dt)
	if next(BuffCards) == nil then
		badgeClock = 0
		return
	end
	badgeClock += dt
	if badgeClock < BADGE_TICK then return end
	badgeClock = 0
	for model in pairs(BuffCards) do RefreshBuffs(model) end
end)

task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(INCOME_REMOTE, 60)
	if not remote then warn("[PlacedCucumberCardClient] no Remotes." .. INCOME_REMOTE .. " (LeaderstatsService makes it)") return end
	remote.OnClientEvent:Connect(function(models, amounts)
		if type(models) ~= "table" or type(amounts) ~= "table" then return end
		for i = 1, #amounts do -- by index (2026-09-22): a cucumber streamed out here arrives as nil and stopped ipairs
			local model = models[i]
			local amount = tonumber(amounts[i])
			if typeof(model) == "Instance" and amount and amount > 0 and amount < math.huge then Popup(model, amount) end
		end
	end)
end)

for _, model in ipairs(CollectionService:GetTagged(TAG)) do Build(model) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(Build)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(Remove)
