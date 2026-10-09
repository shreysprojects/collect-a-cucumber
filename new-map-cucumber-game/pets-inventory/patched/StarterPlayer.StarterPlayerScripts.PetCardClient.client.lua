--[[
	PetCardClient  (LocalScript, StarterPlayerScripts)
	The overhead card on every plot pet (tag "PlotPet", spawned by PetService) and its income
	popups -- the pet twin of PlacedCucumberCardClient, built with the same recipe (2026-09-22,
	pet-system polish):
	  1. the pet's display name in plain WHITE, and under it (2026-09-23, user: "put their rarity
	     under their name instead of beside it, name white but rarity color coded") the rarity word
	     on a row of its own, RARITY_H studs tall, in its rarity gradient (PetsCatalog.RARITY_GRADIENTS).
	     Each width comes from the character count and shrinks when a long word would not fit, so
	     the row always stays inside the card (TextScaled then fits the text to its box).
	  2. its cash/s in the HUD cash green ("$0.5/s" = the Rate attribute PetService stamps, plain
	     text, no cash icon), then (2026-09-23, user: "beside the cash/s show this icon 15403025691 and
	     damage beside it") a small gap, the DAMAGE_ICON image as a square on the row and the shot damage
	     (the ShotDamage attribute, NumberAbbrev) in DAMAGE_COLOR; both re-render on attribute changes.
	  3. ABILITY TAG (2026-09-22, S4 polish): pets with an ability get a third row, TAG_H studs tall:
	     the ability's glyph in a square as tall as the row, then its DisplayName in the ability
	     colour with the dark stroke ("✨ Lucky Harvest"; the word's width comes from its character
	     count, like the rarity word, and shrinks to the room left on a long name). It replaces the old
	     0.8-row round chip, whose emoji drew ~0.57 studs tall on a chip of its own colour and read as
	     a plain coloured dot at normal distance. The card grows by TAG_H and the name / cash rows
	     keep their stud heights; Fighters (Ability None) keep the plain CARD_W x CARD_H card.
	Sized in STUDS (scale units only: CARD_W x CARD_H studs), AlwaysOnTop off, LightInfluence 0,
	MaxDistance 60, parented to the pet's PrimaryPart (PetRoamClient PivotTo's the anchored model
	locally, so the card rides along) and floating GAP_ABOVE over the model's top.
	STREAMING: cards are keyed by model. When the PrimaryPart streams out the card goes with it;
	the model's DescendantAdded watcher rebuilds the card once the PrimaryPart (or a BasePart named
	Root) is back while the PlotPet tag is still there.
	INCOME POPUPS: IncomeService fires Remotes.PetIncome(models, amounts, petIds) on the same 1 s tick
	as CucumberIncome (every client, credited amounts only). Every paid pet with a card here gets a
	green "+$X" rising from the card's top edge (PlacedCucumberCardClient's popup recipe and
	numbers); at most FX.MAX_POPUPS are alive at once (a new one past the cap is dropped) and none
	is built beyond POPUP_MAX_DISTANCE.
	PRISMATIC: PetService pre-sets PrismaticLoop so CucumberMutations.ApplyLook never starts its
	per-model server colour loop for pets; instead this script's one Heartbeat stepper cycles the
	colour of every streamed pet whose Mutations attribute holds PRISMATIC, locally, with the
	ApplyLook recipe (Color3.fromHSV((t * 0.12) % 1, 0.65, 1) every 0.15 s).
	Reads PetBalance / PetsCatalog for caps and colours only; never computes rewards.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TAG = "PlotPet"
local INCOME_REMOTE = "PetIncome"
local FONT = Enum.Font.FredokaOne
local CARD_W, CARD_H = 5.2, 1.9 -- studs (scale = studs on a BillboardGui, like PlotBadges' owner badge)
local NAME_FRAC, RATE_FRAC = 0.52, 0.48 -- row heights as fractions of CARD_H
local TAG_H = 0.8 -- studs the card grows by for the ability tag row (the cucumber card's BADGE_H)
local RARITY_SIZE = 0.7 -- the rarity word's height relative to the name's (kept for NameRowWidths)
local RARITY_H = 0.62 -- studs: the rarity row under the name (2026-09-23)
local CHAR_W = 0.56 -- FredokaOne's average advance per character, in text heights (width estimate)
local ROW_ROOM = 0.96 -- share of a row the name + rarity word (or the ability tag) may fill (the rest is padding)
local ROW_GAP = 0.02 -- a row's UIListLayout padding, as a fraction of the row's width
local GAP_ABOVE = 0.6 -- studs between the pet's top and the card's bottom edge
local MAX_DISTANCE = 60
--.. the HUD cash counter's colours (StarterGui.CucumberHUDDesign.Counters.CashValue + its UIStroke)
local CASH_GREEN = Color3.fromRGB(65, 235, 20)
local CASH_STROKE = Color3.fromRGB(12, 12, 12)
local WHITE = Color3.fromRGB(255, 255, 255)
local DARK_STROKE = Color3.fromRGB(25, 20, 35)
local STROKE = 2.4 -- px, like the cucumber card
local ABILITY_GLYPHS = {Yield = "\u{2728}", Haste = "\u{26A1}", Guard = "\u{1F6E1}\u{FE0F}", Wild = "\u{1F3B2}"}
local SEPARATOR = "\u{00B7} " -- "· Mythical"
local DAMAGE_ICON = "rbxassetid://15403025691" -- 2026-09-23 (user): the damage icon on the cash row (Image asset "Ammo")
local DAMAGE_ICON_SIZE = 0.88 -- of the cash row's height
local DAMAGE_GAP = 0.05 -- of the row's width, between the cash/s and the icon
local DAMAGE_COLOR = Color3.fromRGB(255, 90, 70) -- the Fighter red (PetBalance.ABILITIES.None.Color)
--.. the "+$X" income popup (PlacedCucumberCardClient's numbers)
local POPUP_W, POPUP_H = 4.4, 1.05 -- studs
local POPUP_RISE = 2.6 -- studs it floats up from the card's top edge
local POPUP_TIME = 1.0 -- seconds it lives
local POPUP_POP = 0.16 -- seconds for the scale pop-in (0.3 -> 1.12 -> 1)
local POPUP_FADE_FROM = 0.5 -- fraction of POPUP_TIME where the fade-out starts
local POPUP_MAX_DISTANCE = 70 -- studs from the camera beyond which no popup is built
local PRISMATIC_STEP = 0.15 -- s between colour steps (ApplyLook's loop)
local LOOK_SKIP = {Shadow = true, Hitbox = true, Handle = true} -- the parts ApplyLook never colours
local PART_WAIT = 5 -- s the streaming guard waits for PartCount parts

--..Pure helpers (2026-09-22): the unit tests load this source with loadstring(src)("__core")..--
local Core = {}

local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
Core.Finite = Finite

--.. "$0.5/s" for a finite, non-negative rate; "" otherwise (no Rate attribute = no cash line)
function Core.RateText(rate, abbrev)
	if not Finite(rate) or rate < 0 then return "" end
	return "$" .. abbrev(rate) .. "/s"
end

--.. "15.2" for a finite, non-negative shot damage; "" otherwise (no ShotDamage attribute = no number)
function Core.DamageText(damage, abbrev)
	if not Finite(damage) or damage < 0 then return "" end
	return abbrev(damage)
end

--.. does a comma / space separated list ("NEON,PRISMATIC") hold `name` (matched upper-case)
function Core.HasMutation(list, name)
	if type(list) ~= "string" then return false end
	for word in list:gmatch("[^,%s]+") do
		if word:upper() == name then return true end
	end
	return false
end

--.. widths of the name and the rarity word as fractions of the name row (rowAspect = row width /
--.. row height): natural widths when both fit, shrunk together by the same factor when they don't
function Core.NameRowWidths(nameChars, rarityChars, rowAspect)
	local aspect = Finite(rowAspect) and math.max(rowAspect, 0.1) or 1
	local nameW = math.max(tonumber(nameChars) or 0, 1) * CHAR_W
	local rarityW = math.max(tonumber(rarityChars) or 0, 0) * CHAR_W * RARITY_SIZE
	local total = nameW + rarityW
	local room = aspect * ROW_ROOM
	local s = total > room and room / total or 1
	return nameW * s / aspect, rarityW * s / aspect
end

--.. a live-count cap: Take() -> false when full (the caller drops the new item), Give() frees one
function Core.NewCap(max)
	local cap = {Live = 0, Max = Finite(max) and math.max(math.floor(max), 0) or 0, Dropped = 0}
	function cap:Take()
		if self.Live >= self.Max then
			self.Dropped += 1
			return false
		end
		self.Live += 1
		return true
	end
	function cap:Give()
		if self.Live > 0 then self.Live -= 1 end
	end
	return cap
end

--.. CucumberMutations.ApplyLook's PRISMATIC colour at time t
function Core.PrismaticColor(t)
	return Color3.fromHSV(((Finite(t) and t or 0) * 0.12) % 1, 0.65, 1)
end

--.. the ability tag: glyph, word ("✨", "Lucky Harvest" = the ability's DisplayName, or its key
--.. when the row has none). nil for None (Fighters), an unknown ability or a non-string attribute
function Core.AbilityTag(ability, abilities, glyphs)
	if type(ability) ~= "string" or ability == "None" then return nil end
	local glyph = type(glyphs) == "table" and glyphs[ability] or nil
	if type(glyph) ~= "string" then return nil end
	local row = type(abilities) == "table" and abilities[ability] or nil
	local word = type(row) == "table" and row.DisplayName or nil
	if type(word) ~= "string" or word == "" then word = ability end
	return glyph, word
end

--.. the card's height (studs) and its row heights as fractions of it: the rarity row adds RARITY_H
--.. studs (2026-09-23), the tag row TAG_H, and the name / cash rows keep their stud heights
--.. (NAME_FRAC / RATE_FRAC of CARD_H). Returns total, nameFrac, rateFrac, tagFrac, rarityFrac.
function Core.CardRows(hasTag)
	local total = CARD_H + RARITY_H + (hasTag and TAG_H or 0)
	local s = CARD_H / total
	return total, NAME_FRAC * s, RATE_FRAC * s, hasTag and TAG_H / total or 0, RARITY_H / total
end

--.. widths of the tag's glyph (a square on the row height) and word as fractions of the tag row
--.. (rowAspect = row width / row height): the word's natural width, or the room the glyph leaves
function Core.TagWidths(wordChars, rowAspect)
	local aspect = Finite(rowAspect) and math.max(rowAspect, 1) or 1
	local glyphW = 1 / aspect
	local wordW = math.max(tonumber(wordChars) or 0, 1) * CHAR_W / aspect
	return glyphW, math.min(wordW, math.max(ROW_ROOM - glyphW - ROW_GAP, 0))
end

Core.CARD_W, Core.TAG_H, Core.ABILITY_GLYPHS = CARD_W, TAG_H, ABILITY_GLYPHS -- read by the unit tests

if ... == "__core" then return Core end -- unit tests only: a LocalScript is never started with arguments

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))
local PetsCatalog = require(Modules:WaitForChild("PetsCatalog"))
local PetBalance = require(Modules:WaitForChild("PetBalance"))
local okMutations, CucumberMutations = pcall(function() return require(Modules:WaitForChild("CucumberMutations", 5)) end) -- 2026-09-23: colours the trait words of a pet's name
if not okMutations then CucumberMutations = nil end

local ABILITIES = type(PetBalance.ABILITIES) == "table" and PetBalance.ABILITIES or {}
local FX = type(PetBalance.FX) == "table" and PetBalance.FX or {}
local Popups = Core.NewCap(tonumber(FX.MAX_POPUPS) or 32)

local Entries = {} -- [model] = {Conns, CardConns, Gui, Root, RateLabel, Top, Building, Parts, PartsDirty}
local Prismatic = {} -- [model] = entry, for the streamed pets whose Mutations hold PRISMATIC
local animations = {} -- live popups: one stepping function each

local function Label(name, parent, text, color, strokeColor, order)
	local t = Instance.new("TextLabel")
	t.Name = name
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
	return t, stroke
end

--.. a horizontal, centred row that is a fraction of its parent's height (scale units only)
local function Row(name, parent, frac, order, vertical)
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.fromScale(1, frac)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.VerticalAlignment = vertical or Enum.VerticalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(ROW_GAP, 0)
	lay.Parent = row
	row.Parent = parent
	return row
end

local function Gradient(label, rarity)
	local gradients = PetsCatalog.RARITY_GRADIENTS
	local seq = type(gradients) == "table" and (gradients[rarity] or gradients.Common) or nil
	if typeof(seq) ~= "ColorSequence" then return end
	local g = Instance.new("UIGradient")
	g.Color = seq
	g.Rotation = 90
	g.Parent = label
end

--.. row 3 (ability pets only): the glyph as tall as the row + "Lucky Harvest" in the ability colour
--.. with the dark stroke -- a word the player can read, not a colour-only dot
local function AbilityTag(parent, ability, glyph, word, frac)
	local row = Row("AbilityTag", parent, frac, 4) -- 2026-09-23: after name / rarity / cash
	local info = ABILITIES[ability]
	local color = type(info) == "table" and typeof(info.Color) == "Color3" and info.Color or WHITE
	local glyphW, wordW = Core.TagWidths(utf8.len(word) or #word, CARD_W / TAG_H)
	local icon = Label("Glyph", row, glyph, WHITE, CASH_STROKE, 1)
	icon.Size = UDim2.fromScale(glyphW, 1)
	local label = Label("Ability", row, word, color, CASH_STROKE, 2)
	label.Size = UDim2.fromScale(wordW, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left -- hugs the glyph when TextScaled fits it narrower
	return row
end

local function RootOf(model)
	local root = model.PrimaryPart
	if root and root:IsDescendantOf(model) then return root end
	root = model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then return root end
	return nil
end

--.. streaming guard (PetRoamClient's): wait until the whole model is here before measuring it
local function WaitForParts(model)
	local wanted = tonumber(model:GetAttribute("PartCount")) or 0
	local deadline = os.clock() + PART_WAIT
	while os.clock() < deadline do
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
		if n >= wanted then return end
		task.wait(0.1)
	end
end

local function RenderRate(model, entry)
	if entry.RateLabel then
		entry.RateLabel.Text = Core.RateText(model:GetAttribute("Rate"), NumberAbbrev.Abbrev)
	end
	if entry.DamageLabel then
		entry.DamageLabel.Text = Core.DamageText(model:GetAttribute("ShotDamage"), NumberAbbrev.Abbrev)
	end
end

local function DropCard(entry)
	for _, c in ipairs(entry.CardConns) do c:Disconnect() end
	table.clear(entry.CardConns)
	local gui = entry.Gui
	entry.Gui, entry.Root, entry.RateLabel, entry.DamageLabel, entry.Top = nil, nil, nil, nil, nil
	if gui then gui:Destroy() end
end

local function BuildCard(model)
	local entry = Entries[model]
	if not entry or entry.Gui or entry.Building then return end
	if not RootOf(model) then return end -- the DescendantAdded watcher calls again when it streams in
	entry.Building = true
	task.spawn(function()
		WaitForParts(model)
		entry.Building = false
		if Entries[model] ~= entry or entry.Gui then return end
		local root = RootOf(model)
		if not root or not model:IsDescendantOf(workspace) then return end
		local cf, ext = model:GetBoundingBox()
		local halfUp = math.max(cf.Position.Y + ext.Y * 0.5 - root.Position.Y, 0)
		local ability = model:GetAttribute("Ability")
		local glyph, word = Core.AbilityTag(ability, ABILITIES, ABILITY_GLYPHS)
		local cardH, nameFrac, rateFrac, tagFrac, rarityFrac = Core.CardRows(glyph ~= nil)
		local gui = Instance.new("BillboardGui")
		gui.Name = "PetCard"
		gui.Adornee = root
		gui.Size = UDim2.fromScale(CARD_W, cardH) -- scale = studs: shrinks with distance
		--.. the billboard is centred on its offset: lift it by half its height so the BOTTOM edge sits GAP_ABOVE over the pet
		gui.StudsOffsetWorldSpace = Vector3.new(0, halfUp + GAP_ABOVE + cardH * 0.5, 0)
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.MaxDistance = MAX_DISTANCE
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = gui
		--.. row 1: "Cosmo Cat" in plain white (2026-09-23: the rarity moved to its own row under the name)
		local rarity = model:GetAttribute("Rarity")
		rarity = type(rarity) == "string" and rarity ~= "" and rarity or "Common"
		local name = model:GetAttribute("DisplayName")
		name = type(name) == "string" and name ~= "" and name or model.Name
		local nameRow = Row("NameRow", gui, nameFrac, 1, Enum.VerticalAlignment.Bottom)
		local nameW = Core.NameRowWidths(utf8.len(name) or #name, 0, CARD_W / (CARD_H * NAME_FRAC))
		local nameLabel = Label("PetName", nameRow, name, WHITE, DARK_STROKE, 1)
		nameLabel.Size = UDim2.fromScale(nameW, 1)
		--.. 2026-09-23 (user: a mutated egg hatches a pet OF that mutation): the inherited trait words the name now
		--.. carries ("Golden VOID NEON Tabby", PetStats) in their cucumber colours; the species word stays white
		if CucumberMutations then
			local okRich, rich = pcall(CucumberMutations.ColorizeName, name)
			if okRich and type(rich) == "string" and rich:find("<font", 1, true) then
				nameLabel.RichText = true
				nameLabel.Text = rich
			end
		end
		nameLabel.TextYAlignment = Enum.TextYAlignment.Bottom
		--.. row 2: the rarity word, colour-coded by its rarity gradient
		local rarityRow = Row("RarityRow", gui, rarityFrac, 2)
		local rarityW = Core.NameRowWidths(utf8.len(rarity) or #rarity, 0, CARD_W / RARITY_H)
		local rarityLabel = Label("RarityWord", rarityRow, rarity, WHITE, DARK_STROKE, 1)
		rarityLabel.Size = UDim2.fromScale(rarityW, 1)
		Gradient(rarityLabel, rarity)
		--.. row 3: the green "$X/s", then (2026-09-23, user) the damage icon with the shot damage beside it
		local cashRow = Row("CashLine", gui, rateFrac, 3)
		local rateLabel = Label("Rate", cashRow, "", CASH_GREEN, CASH_STROKE, 1)
		rateLabel.AutomaticSize = Enum.AutomaticSize.X -- auto-widens from its scaled height
		rateLabel.Size = UDim2.fromScale(0, 1)
		local gap = Instance.new("Frame")
		gap.Name = "Gap"
		gap.BackgroundTransparency = 1
		gap.Size = UDim2.fromScale(DAMAGE_GAP, 1)
		gap.LayoutOrder = 2
		gap.Parent = cashRow
		local icon = Instance.new("ImageLabel")
		icon.Name = "DamageIcon"
		icon.BackgroundTransparency = 1
		icon.Image = DAMAGE_ICON
		icon.ScaleType = Enum.ScaleType.Fit
		--.. a square: the row is RATE_FRAC x CARD_H studs tall on a CARD_W-stud-wide card (CardRows keeps the stud height)
		icon.Size = UDim2.fromScale(DAMAGE_ICON_SIZE * (RATE_FRAC * CARD_H) / CARD_W, DAMAGE_ICON_SIZE)
		icon.LayoutOrder = 3
		icon.Parent = cashRow
		local damageLabel = Label("Damage", cashRow, "", DAMAGE_COLOR, CASH_STROKE, 4)
		damageLabel.AutomaticSize = Enum.AutomaticSize.X
		damageLabel.Size = UDim2.fromScale(0, 1)
		--.. row 3 (ability pets only): "✨ Lucky Harvest"
		if glyph then AbilityTag(gui, ability, glyph, word, tagFrac) end
		gui.Parent = root
		entry.Gui, entry.Root, entry.RateLabel, entry.DamageLabel = gui, root, rateLabel, damageLabel
		entry.Top = halfUp + GAP_ABOVE + cardH -- the card's TOP edge, studs above the root: where a popup starts
		RenderRate(model, entry)
		--.. the PrimaryPart streamed out (the card went with it): drop it, DescendantAdded rebuilds it
		table.insert(entry.CardConns, gui.AncestryChanged:Connect(function()
			if entry.Gui == gui and not gui:IsDescendantOf(workspace) then DropCard(entry) end
		end))
	end)
end

local function UpdatePrismatic(model, entry)
	local on = Core.HasMutation(model:GetAttribute("Mutations"), "PRISMATIC")
	Prismatic[model] = on and entry or nil
	entry.PartsDirty = true
end

local function Attach(model)
	if Entries[model] or not model:IsA("Model") then return end
	local entry = {Conns = {}, CardConns = {}, PartsDirty = true}
	Entries[model] = entry
	UpdatePrismatic(model, entry)
	table.insert(entry.Conns, model:GetAttributeChangedSignal("Rate"):Connect(function()
		RenderRate(model, entry)
	end))
	table.insert(entry.Conns, model:GetAttributeChangedSignal("ShotDamage"):Connect(function()
		RenderRate(model, entry)
	end))
	table.insert(entry.Conns, model:GetAttributeChangedSignal("Mutations"):Connect(function()
		UpdatePrismatic(model, entry)
	end))
	table.insert(entry.Conns, model.DescendantAdded:Connect(function(d)
		if not d:IsA("BasePart") then return end
		entry.PartsDirty = true
		if entry.Gui or entry.Building then return end
		task.defer(function() -- the PrimaryPart reference resolves after the part itself arrives
			if Entries[model] == entry and CollectionService:HasTag(model, TAG) then BuildCard(model) end
		end)
	end))
	table.insert(entry.Conns, model.DescendantRemoving:Connect(function(d)
		if d:IsA("BasePart") then entry.PartsDirty = true end
	end))
	BuildCard(model)
end

local function Detach(model)
	local entry = Entries[model]
	if not entry then return end
	Entries[model] = nil
	Prismatic[model] = nil
	for _, c in ipairs(entry.Conns) do c:Disconnect() end
	DropCard(entry)
end

--..Income popups: "+$X" floating up from the top edge of the pet's card..--
local function Popup(model, amount)
	local entry = Entries[model]
	local root = entry and entry.Root
	if not root or not root.Parent or not entry.Gui or not entry.Top then return end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - root.Position).Magnitude > POPUP_MAX_DISTANCE then return end
	if not Popups:Take() then return end -- FX.MAX_POPUPS alive already: this one is dropped
	local gui = Instance.new("BillboardGui")
	gui.Name = "PetIncomePopup"
	gui.Adornee = root
	gui.Size = UDim2.fromScale(POPUP_W, POPUP_H) -- scale = studs: shrinks with distance like the card
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = MAX_DISTANCE
	local startY = entry.Top + POPUP_H * 0.5 -- centred billboard: its bottom edge sits on the card's top edge
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
	local row = Row("CashLine", frame, 1, 1)
	local label, stroke = Label("Amount", row, "+$" .. NumberAbbrev.Abbrev(amount), CASH_GREEN, CASH_STROKE, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	gui.Parent = root
	local t0 = os.clock()
	table.insert(animations, function(now)
		local t = now - t0
		if t >= POPUP_TIME or not root.Parent or not gui.Parent then
			gui:Destroy()
			Popups:Give()
			return false
		end
		local k = t / POPUP_TIME
		local eased = 1 - (1 - k) * (1 - k) -- quad out: fast off the card, easing as it fades
		gui.StudsOffsetWorldSpace = Vector3.new(0, startY + POPUP_RISE * eased, 0)
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

--.. PRISMATIC pets: the ApplyLook parts (Shadow / Hitbox / Handle skipped), cached until a part streams in or out
local function LookParts(model)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not LOOK_SKIP[d.Name] then parts[#parts + 1] = d end
	end
	return parts
end

local prismaticClock, prismaticT = 0, 0
local function StepPrismatic()
	if next(Prismatic) == nil then return end
	local color = Core.PrismaticColor(prismaticT)
	for model, entry in pairs(Prismatic) do
		if entry.PartsDirty or not entry.Parts then
			entry.Parts = LookParts(model)
			entry.PartsDirty = false
		end
		for _, p in ipairs(entry.Parts) do
			if p.Parent then p.Color = color end
		end
	end
end

--.. ONE Heartbeat stepper (not RenderStepped: keeps stepping while the Studio window is unfocused)
RunService.Heartbeat:Connect(function(dt)
	prismaticT += dt
	prismaticClock += dt
	if prismaticClock >= PRISMATIC_STEP then
		prismaticClock = 0
		StepPrismatic()
	end
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
	if not remote then warn("[PetCardClient] no Remotes." .. INCOME_REMOTE .. " (IncomeService makes it) - pet income popups are off") return end
	remote.OnClientEvent:Connect(function(models, amounts)
		if type(models) ~= "table" or type(amounts) ~= "table" then return end
		--.. by index, not ipairs: a pet streamed out on this client arrives as nil in `models`
		for i = 1, #amounts do
			local model, amount = models[i], amounts[i]
			if typeof(model) == "Instance" and Finite(amount) and amount > 0 then Popup(model, amount) end
		end
	end)
end)

for _, model in ipairs(CollectionService:GetTagged(TAG)) do Attach(model) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(Attach)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(Detach)
