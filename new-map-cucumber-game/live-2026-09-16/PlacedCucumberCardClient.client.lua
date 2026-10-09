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

local Cards = {} -- [model] = {Gui, Conns, Adornee, Top, Grow, HalfUp}
local animations = {} -- live popups: one stepping function each

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
		Line(gui, zone, BIOME_FRAC, zoneText, zoneStroke, 1).Name = "Biome"
		local nameLabel = Line(gui, NameText(model), NAME_FRAC, WHITE, DARK_STROKE, 2)
		nameLabel.Name = "CucumberName"
		nameLabel.RichText = true
		local rateLabel = CashLine(gui, RATE_FRAC, 3)
		rateLabel.Text = RateText(model)
		gui.Parent = adornee
		card.Gui = gui
		card.Adornee = adornee
		card.Grow = grow
		card.HalfUp = halfUp
		card.Top = halfUp + GAP_ABOVE * grow + cardH -- the card's TOP edge, studs above the adornee: where a popup starts
		table.insert(card.Conns, model:GetAttributeChangedSignal("Rate"):Connect(function()
			rateLabel.Text = RateText(model)
		end))
	end)
end

local function Remove(model)
	local card = Cards[model]
	if not card then return end
	Cards[model] = nil
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

task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(INCOME_REMOTE, 60)
	if not remote then warn("[PlacedCucumberCardClient] no Remotes." .. INCOME_REMOTE .. " (LeaderstatsService makes it)") return end
	remote.OnClientEvent:Connect(function(models, amounts)
		if type(models) ~= "table" or type(amounts) ~= "table" then return end
		for i, model in ipairs(models) do
			local amount = tonumber(amounts[i])
			if typeof(model) == "Instance" and amount and amount > 0 and amount < math.huge then Popup(model, amount) end
		end
	end)
end)

for _, model in ipairs(CollectionService:GetTagged(TAG)) do Build(model) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(Build)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(Remove)
