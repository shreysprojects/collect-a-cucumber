-- WP-MENU fixture (generated): a verbatim copy of builders/build_petspanel.lua as a string, because the
-- loopback servers do not serve builders/. Regenerate after every builder edit. Returns the source text.
return [====[--[[
	build_petspanel.lua  (edit-mode builder chunk; the integration agent runs it once through execute_luau)
	2026-09-22 (pet system, pets-system/CONTRACTS.md 3.11.1). Builds, idempotently:
	  1. StarterGui.CucumberMenus.PetsPanel - the Pets menu in the Index panel's look (Shadow / Body /
	     Header ribbon / CloseButton are clones of IndexPanel.Content's, read-only): Header (Title "PETS",
	     Subtitle "0 / 6 ACTIVE"), SlotRow (Slot1..Slot6), Toolbar (sort / filter / best buttons), PetGrid
	     (ScrollingFrame + UIGridLayout + Empty), Details (Preview, PetName, Rarity, Traits, CashLine,
	     CombatLine, AbilityName, AbilityEffect, AbilityChance, NextRoll, EquipButton), Footer (PetCash,
	     CucumberCash, TotalCash), LockBanner, Status, and PetsPanel.Templates (PetCard, SlotCard, Chip,
	     all Visible = false). Attributes FitMargin = 1 (MenuController.fit; 0.95 before S7) and Reference.
	  2. StarterGui.CucumberHUDDesign.LeftMenu.Pets - the paw opener to the right of the top row: the
	     LeftMenu.Index shell (Corners, Outline, Fill + gradient + studs + InnerHighlight) retinted gold,
	     a frame-drawn PawIcon (Pad + Toe1..Toe4), Label "Pets" and the transparent OpenPets button.
	     No ButtonFX.Prepare (BaseHUDController drives its Size / Position, MenuController its HoverScale).
	  3. StarterGui.EggRevealUI.SingleTemplate.PetStats / PetTraits - the reveal card's stat + trait lines
	     (hidden; EggHatchClient fills and shows them).
	Every instance is AUTHORED here (nothing is generated at runtime except pooled clones of the
	templates); PetView renders the panel, PetController wires it, MenuController opens it.
	Re-running rebuilds all three (the panel keeps its outer Frame / ResponsiveScale / Content /
	MotionScale instances; everything under Content and Templates is recreated). ShopPanel, IndexPanel
	and ManagePanel are never modified.
	Test mode: loadstring(source)({Mode = "module"}) returns {Build, BuildPanel, BuildOpener,
	BuildRevealLabels} and touches nothing; the build functions take their target ScreenGuis as
	arguments, so a test can build into unparented clones.
	2026-09-22 (review fix, phones): the panel also carries a COMPACT layout for small screens. Every
	instance whose rect / text cap / visibility differs on a phone gets `Compact_<Property>` attributes
	(e.g. Compact_Size, Compact_Position, Compact_Visible, Compact_MaxTextSize on its SizeCap); PetView
	swaps them in while PetsPanel.ResponsiveScale.Scale < the panel attribute CompactBelow (0.55) and puts
	the authored values back above it. The compact canvas is still 1140 x 735 design px, laid out so that
	at the 844 x 390 landscape fit (scale ~0.372) every text is >= 30 design px (~11 real px) and every
	button >= 110 design px tall (~41 real px): the six-slot row and the seven sort / filter tabs hide,
	two new cycle buttons (Toolbar.SortCycle "SORT: INCOME", Toolbar.FilterCycle "SHOW: ALL") and the
	two Best buttons share one 110-tall toolbar row, the grid has 2 wide columns of 525 x 196 cards
	(preview left, texts right), and Details becomes a page over the grid + toolbar with a
	Details.BackButton (both new buttons are hidden in the wide layout). The CloseButton's hit area grows
	to 118 x 118 with its art kept centred. Card chip rows clip (ClipsDescendants) as a backstop to
	PetView's width fitting. Details.Traits comes last in the page's text column there (after CashLine)
	and wraps to up to three lines, so a material + all eight mutations still shows at 30 design px.
	2026-09-22 (S7 integration): Content.ClickShield - a transparent, non-selectable TextButton (ZIndex 1) on
	the body's rect, so a click on the panel's art or text no longer falls through to MenuController's Dimmer
	(which closes the panel); only a click outside the panel does. FitMargin 0.95 -> 1: on the iPhone 13
	simulator's real safe area (749 x 310 GUI px) the fit is then 0.362, so compact text is >= 10.9 px and
	buttons >= 39.8 px (0.95 gave 10.3 / 37.8).
]]
local args = ...
local StarterGui = game:GetService("StarterGui")

local C = Color3.fromRGB
local WHITE = C(255, 255, 255)
local DARK = C(12, 12, 12)            -- HUD outline
local INK = C(36, 25, 29)             -- Index panel text outline / EquipReward border
local WINE = C(100, 8, 25)            -- Index panel shadow + body border
local CASH_GREEN = C(65, 235, 20)
local WARN = C(255, 160, 60)          -- Notify.COLORS.Warn
local INFO = C(255, 226, 120)         -- Notify.COLORS.Info
local CARD_TOP, CARD_BOTTOM = C(255, 255, 255), C(226, 234, 242)
local ACTIVE_GREEN = C(84, 200, 40)
local TAB_ON = {C(15, 224, 255), C(0, 170, 240)}
local TAB_OFF = {C(146, 177, 207), C(74, 113, 148)}
local GREEN = {C(149, 255, 70), C(63, 204, 28)}
local GOLD = {C(255, 220, 90), C(240, 170, 20)}
local GOLD_HIGHLIGHT = C(255, 240, 170)
local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")
local BUILDER_XB = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local RIBBON = "rbxassetid://75227340977908"
local REFERENCE = "Pets panel (pet system 2026-09-22): built by pets-system/builders/build_petspanel.lua; PetView renders it, PetController wires it, MenuController opens it"
local COMPACT_BELOW = 0.55            -- PetView uses the compact layout below this ResponsiveScale
local COMPACT_MIN_TEXT = 20           -- compact SizeCap floor (normal texts fit at >= 30; this only stops runaway shrinking)
local COMPACT_BUTTON_H = 110          -- compact button height (design px): ~41 real px at the phone fit
local CLOSE_GROW = 16                 -- compact CloseButton hit area: 86 + 2 x 16 = 118 design px

local function off(x, y) return UDim2.fromOffset(x, y) end

local function make(class, name, parent, props)
	local inst = Instance.new(class)
	inst.Name = name
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
		inst.BackgroundTransparency = 1
		inst.BackgroundColor3 = WHITE
	end
	if inst:IsA("GuiButton") then inst.AutoButtonColor = false end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		inst.Text = ""
		inst.TextColor3 = WHITE
		inst.FontFace = FREDOKA
	end
	for key, value in pairs(props or {}) do inst[key] = value end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	return make("UICorner", "Corners", parent, {CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, radius)})
end

local function border(parent, thickness, color, name)
	return make("UIStroke", name or "Border", parent, {Thickness = thickness, Color = color, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end

local function gradient(parent, pair, name)
	return make("UIGradient", name or "Gradient", parent, {Rotation = 90, Color = ColorSequence.new(pair[1], pair[2])})
end

--.. FredokaOne, TextScaled, white with the panel's dark outline, capped at maxSize
local function text(name, parent, value, size, pos, props, maxSize, outline)
	local label = make("TextLabel", name, parent, {Size = size, Position = pos, Text = value, TextScaled = true, ZIndex = 10})
	for key, v in pairs(props or {}) do label[key] = v end
	if outline ~= false then
		make("UIStroke", "TextOutline", label, {Thickness = outline or 2.5, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual})
	end
	make("UITextSizeConstraint", "SizeCap", label, {MaxTextSize = maxSize or 40, MinTextSize = 8})
	return label
end

--.. the compact (phone) values of an instance: Compact_<Property> attributes PetView swaps in; maxText /
--.. minText go on its (or its Label's) UITextSizeConstraint
local function compact(inst, props, maxText, minText)
	for key, value in pairs(props or {}) do inst:SetAttribute("Compact_" .. key, value) end
	if maxText then
		local label = inst:FindFirstChild("Label")
		local cap = inst:FindFirstChildOfClass("UITextSizeConstraint") or (label and label:FindFirstChildOfClass("UITextSizeConstraint"))
		if cap then
			cap:SetAttribute("Compact_MaxTextSize", maxText)
			cap:SetAttribute("Compact_MinTextSize", math.min(minText or COMPACT_MIN_TEXT, maxText))
		end
	end
	return inst
end

--.. rounded gradient button with a Label child (PetView paints Gradient and writes Label.Text)
local function button(name, parent, caption, size, pos, pair, z)
	local b = make("TextButton", name, parent, {Size = size, Position = pos, BackgroundTransparency = 0, Selectable = true, ZIndex = z or 10})
	corner(b, 12)
	border(b, 3, INK)
	gradient(b, pair)
	text("Label", b, caption, UDim2.new(1, -12, 1, -8), off(6, 4), {ZIndex = (z or 10) + 1}, 26)
	return b
end

local function viewport(name, parent, size, pos, z)
	return make("ViewportFrame", name, parent, {
		Size = size, Position = pos, ZIndex = z or 10, BackgroundTransparency = 1,
		Ambient = C(160, 160, 170), LightColor = WHITE, LightDirection = Vector3.new(-0.4, -1, -0.6),
	})
end

--.. runtime-only bits a clone must not carry (HoverScale / FXScale / PressScale, scripts)
local function strip(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("UIScale") or d:IsA("LuaSourceContainer") then d:Destroy() end
	end
end

local function cloneArt(art, name, parent)
	local source = art and art:FindFirstChild(name)
	if not source then return nil end
	local copy = source:Clone()
	strip(copy)
	copy.Parent = parent
	return copy
end

--..1. PetsPanel..--
local function BuildTemplates(panel)
	local templates = make("Folder", "Templates", panel)

	-- PetCard 184 x 214 (grid cell); compact: a 525 x 196 cell, preview on the left, texts on the right
	local left = Enum.TextXAlignment.Left
	local card = make("TextButton", "PetCard", templates, {Size = off(184, 214), BackgroundTransparency = 0, Selectable = true, Visible = false, ZIndex = 9})
	corner(card, 14)
	border(card, 3, INK)
	gradient(card, {CARD_TOP, CARD_BOTTOM})
	local bar = make("Frame", "RarityBar", card, {Size = UDim2.new(1, -16, 0, 8), Position = off(8, 8), BackgroundTransparency = 0, ZIndex = 10})
	corner(bar, 4)
	make("UIGradient", "Gradient", bar, {Rotation = 0})
	compact(text("RarityText", card, "COMMON", off(106, 20), off(10, 19), {ZIndex = 11, TextXAlignment = left}, 20, 2),
		{Size = off(206, 34), Position = off(192, 20)}, 30)
	local tag = text("EquippedTag", card, "ACTIVE", off(62, 22), off(114, 18), {ZIndex = 12, BackgroundTransparency = 0, BackgroundColor3 = ACTIVE_GREEN, Visible = false}, 18, 2)
	corner(tag, 8)
	compact(tag, {Size = off(112, 38), Position = off(405, 18)}, 30)
	compact(viewport("Preview", card, off(168, 94), off(8, 40), 10), {Size = off(172, 166), Position = off(10, 22)})
	-- compact: the status tag takes the chip row's place (PetView hides the chips while it shows)
	local status = text("StatusTag", card, "", off(168, 22), off(8, 112), {ZIndex = 12, BackgroundTransparency = 0.25, BackgroundColor3 = C(30, 20, 25), TextColor3 = WARN, Visible = false}, 18, 2)
	corner(status, 6)
	compact(status, {Size = off(325, 36), Position = off(192, 104)}, 30)
	compact(text("PetName", card, "Pet", off(172, 28), off(6, 136), {ZIndex = 11}, 26),
		{Size = off(327, 44), Position = off(190, 56), TextXAlignment = left}, 40)
	-- chips: PetView fits them to this row's width ("+N" for the rest); the clip is only a backstop
	local chips = make("Frame", "Chips", card, {Size = off(168, 18), Position = off(8, 166), ZIndex = 11, ClipsDescendants = true})
	make("UIListLayout", "Layout", chips, {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center})
	compact(chips, {Size = off(325, 36), Position = off(192, 104)})
	compact(text("Rate", card, "$0/s", off(172, 24), off(6, 186), {ZIndex = 11, TextColor3 = CASH_GREEN}, 24, false),
		{Size = off(327, 42), Position = off(190, 146), TextXAlignment = left}, 38)
	make("UIStroke", "TextOutline", card.Rate, {Thickness = 2, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual})

	-- SlotCard 166 x 100 (Slot1..Slot6 are clones)
	local slot = make("TextButton", "SlotCard", templates, {Size = off(166, 100), BackgroundTransparency = 0, Selectable = true, Visible = false, ZIndex = 9})
	corner(slot, 14)
	border(slot, 3, INK)
	gradient(slot, {CARD_TOP, CARD_BOTTOM})
	viewport("Preview", slot, off(150, 66), off(8, 4), 10)
	text("PetName", slot, "", off(158, 26), off(4, 70), {ZIndex = 11}, 24)
	text("Empty", slot, "Empty", UDim2.new(1, -16, 0, 34), off(8, 33), {ZIndex = 11, TextColor3 = C(120, 132, 150)}, 28, false)

	-- Chip (material / mutation tag on a card)
	local chip = make("Frame", "Chip", templates, {Size = off(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = C(90, 96, 120), Visible = false, ZIndex = 12})
	make("UICorner", "UICorner", chip, {CornerRadius = UDim.new(0, 6)})
	make("UIPadding", "Padding", chip, {PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5)})
	local chipLabel = make("TextLabel", "Label", chip, {Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextSize = 14, ZIndex = 13, Text = "NEON"})
	make("UIStroke", "TextOutline", chipLabel, {Thickness = 1.5, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual})
	compact(chip, {Size = off(0, 36)})
	compact(chipLabel, {TextSize = 30})
	return templates
end

local function BuildPanel(menus, art)
	assert(menus, "CucumberMenus missing")
	local panel = menus:FindFirstChild("PetsPanel")
	if panel and not panel:IsA("Frame") then panel:Destroy() panel = nil end
	if not panel then
		panel = Instance.new("Frame")
		panel.Name = "PetsPanel"
		panel.Parent = menus
	end
	panel.Size = off(1140, 735)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Visible = true
	-- 2026-09-22 (S7 integration): 1 (was 0.95). MenuController.fit already keeps 16 / 22 px of screen around a
	-- panel; a phone's real GUI area is its safe area (iPhone 13 landscape: 749 x 310 after the notch, the home
	-- bar and the 58 px top bar), where 0.95 left compact text at 10.3 px and buttons at 37.8 px
	panel:SetAttribute("FitMargin", 1)
	panel:SetAttribute("CompactBelow", COMPACT_BELOW)
	panel:SetAttribute("Compact", nil) -- runtime mirror written by PetView
	panel:SetAttribute("Reference", REFERENCE)
	panel:SetAttribute("PetsDev", nil)
	for _, child in ipairs(panel:GetChildren()) do
		if child.Name ~= "ResponsiveScale" and child.Name ~= "Content" then child:Destroy() end
	end
	local responsive = panel:FindFirstChild("ResponsiveScale")
	if responsive and not responsive:IsA("UIScale") then responsive:Destroy() responsive = nil end
	if not responsive then make("UIScale", "ResponsiveScale", panel, {Scale = 0.66}) end
	local content = panel:FindFirstChild("Content")
	if content and not content:IsA("CanvasGroup") then content:Destroy() content = nil end
	if not content then content = make("CanvasGroup", "Content", panel) end
	for _, child in ipairs(content:GetChildren()) do
		if child.Name ~= "MotionScale" then child:Destroy() end
	end
	content.Size = UDim2.fromScale(1, 1)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ZIndex = 2
	content.Visible = false
	content.GroupTransparency = 1
	local motion = content:FindFirstChild("MotionScale")
	if not (motion and motion:IsA("UIScale")) then
		if motion then motion:Destroy() end
		make("UIScale", "MotionScale", content, {Scale = 1})
	end

	-- art: the Index panel's shadow / body / ribbon / close button (fallbacks match their rects)
	if not cloneArt(art, "Shadow", content) then
		local shadow = make("Frame", "Shadow", content, {Size = off(1120, 694), Position = off(10, 30), BackgroundTransparency = 0, BackgroundColor3 = WINE, ZIndex = 2})
		corner(shadow, 23)
	end
	if not cloneArt(art, "Body", content) then
		local body = make("Frame", "Body", content, {Size = off(1120, 690), Position = off(10, 23), BackgroundTransparency = 0, ZIndex = 3})
		corner(body, 22)
		border(body, 7, WINE)
		gradient(body, {C(255, 220, 225), C(255, 176, 190)})
	end
	local header = cloneArt(art, "Header", content)
	if not header then
		header = make("ImageLabel", "Header", content, {Size = off(390, 103), Position = off(22, 0), Image = RIBBON, ZIndex = 12})
	end
	local title = header:FindFirstChild("Title") or text("Title", header, "", off(280, 94), off(54, 4), {ZIndex = 13, FontFace = BUILDER_XB}, 90)
	title.Text = "PETS"
	local subtitle = header:FindFirstChild("Subtitle") or text("Subtitle", header, "", off(400, 27), off(14, 107), {ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left}, 27, 2)
	subtitle.Text = "0 / 6 ACTIVE"
	subtitle.Size = off(400, 27)
	compact(subtitle, {Size = off(400, 40)}, 40)
	local close = cloneArt(art, "CloseButton", content)
	if not close then
		close = make("TextButton", "CloseButton", content, {Size = off(86, 86), Position = off(1082, 55), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 30, Text = "X", TextScaled = true})
	end
	close.Selectable = true
	-- compact: a bigger hit area around the same centre; the art's offset-sized children move by the growth so
	-- they stay centred
	compact(close, {Size = close.Size + off(2 * CLOSE_GROW, 2 * CLOSE_GROW)})
	for _, child in ipairs(close:GetChildren()) do
		if child:IsA("GuiObject") then compact(child, {Position = child.Position + off(CLOSE_GROW, CLOSE_GROW)}) end
	end
	-- 2026-09-22 (S7 integration): MenuController closes a panel when its full-screen Dimmer button is clicked,
	-- and a click on plain art / text (Frames, labels: not buttons, and Active does not stop it) falls through
	-- to that Dimmer, so tapping the details text or the footer closed the whole panel. A transparent,
	-- non-selectable button under everything, on the body's rect, takes those clicks; only a click outside
	-- the panel reaches the Dimmer.
	local body = content:FindFirstChild("Body")
	local shield = make("TextButton", "ClickShield", content, {ZIndex = 1, Selectable = false,
		Size = body and body.Size or off(1120, 690), Position = body and body.Position or off(10, 23),
		AnchorPoint = body and body.AnchorPoint or Vector2.zero})
	shield.Active = true

	-- messages (top right, beside the ribbon); compact: two wrapped lines each
	compact(text("LockBanner", content, "Finish defending your plot to change pets.", off(560, 38), off(440, 34),
		{ZIndex = 14, TextColor3 = WARN, Visible = false}, 32, 3), {Size = off(580, 72), Position = off(440, 2), TextWrapped = true}, 32)
	compact(text("Status", content, "", off(560, 30), off(440, 76), {ZIndex = 14, TextColor3 = INFO, Visible = false}, 26, 2.5),
		{Size = off(580, 72), Position = off(440, 76), TextWrapped = true}, 30)

	-- templates first: the slot row clones SlotCard
	local templates = BuildTemplates(panel)

	-- six active slots (compact: hidden; the ACTIVE tags, the Active filter and the subtitle cover them)
	local slotRow = make("Frame", "SlotRow", content, {Size = off(1068, 100), Position = off(36, 140), ZIndex = 8, SelectionGroup = true})
	compact(slotRow, {Visible = false})
	make("UIListLayout", "Layout", slotRow, {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center})
	for i = 1, 6 do
		local slot = templates.SlotCard:Clone()
		slot.Name = "Slot" .. i
		slot.LayoutOrder = i
		slot.Visible = true
		slot.Parent = slotRow
	end

	-- toolbar: sort (local), filter (local), best income / best combat (server)
	-- compact: one 110-tall row = SortCycle, FilterCycle (they step through the modes), BestIncome, BestCombat
	local toolbar = make("Frame", "Toolbar", content, {Size = off(1068, 42), Position = off(36, 250), ZIndex = 8})
	compact(toolbar, {Size = off(1068, COMPACT_BUTTON_H), Position = off(36, 150)})
	local buttons = {
		{"SortIncome", "INCOME", 0, 100, TAB_ON}, {"SortCombat", "COMBAT", 106, 100, TAB_OFF},
		{"SortRarity", "RARITY", 212, 100, TAB_OFF}, {"SortNewest", "NEWEST", 318, 100, TAB_OFF},
		{"FilterAll", "ALL", 440, 92, TAB_ON}, {"FilterActive", "ACTIVE", 538, 92, TAB_OFF},
		{"FilterReserve", "RESERVE", 636, 92, TAB_OFF},
		{"BestIncome", "BEST INCOME", 744, 162, GREEN, 540}, {"BestCombat", "BEST COMBAT", 906, 162, GREEN, 810},
		{"SortCycle", "SORT: INCOME", 0, 100, TAB_ON, 0}, {"FilterCycle", "SHOW: ALL", 106, 100, TAB_ON, 270},
	}
	for _, spec in ipairs(buttons) do
		local b = button(spec[1], toolbar, spec[2], off(spec[4], 42), off(spec[3], 0), spec[5], 10)
		if spec[6] then
			compact(b, {Size = off(258, COMPACT_BUTTON_H), Position = off(spec[6], 0), Visible = true}, 34)
		else
			compact(b, {Visible = false})
		end
	end
	toolbar.SortCycle.Visible = false -- wide layout: the separate tabs
	toolbar.FilterCycle.Visible = false

	-- owned pets grid (3 columns, scrolls; compact: 2 wide columns)
	local grid = make("ScrollingFrame", "PetGrid", content, {
		Size = off(592, 340), Position = off(30, 300), ZIndex = 5, SelectionGroup = true, Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8, ScrollBarImageColor3 = WINE, ElasticBehavior = Enum.ElasticBehavior.Never,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	})
	compact(grid, {Size = off(1080, 370), Position = off(30, 270)})
	compact(make("UIGridLayout", "UIGridLayout", grid, {CellSize = off(184, 214), CellPadding = off(8, 10), FillDirectionMaxCells = 3,
		SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left}),
		{CellSize = off(525, 196), FillDirectionMaxCells = 2})
	make("UIPadding", "Padding", grid, {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6)})
	compact(text("Empty", grid, "No pets yet - hatch an egg to get one!", off(184, 214), off(0, 0),
		{ZIndex = 9, LayoutOrder = -1, TextWrapped = true, Visible = false}, 26), nil, 34)

	-- selected pet (compact: a page over the grid + toolbar, opened by tapping a card, closed by BackButton)
	local details = make("Frame", "Details", content, {Size = off(470, 340), Position = off(634, 300), BackgroundTransparency = 0.12, ZIndex = 5})
	corner(details, 16)
	border(details, 4, WINE)
	compact(details, {Size = off(1080, 490), Position = off(30, 150)})
	local preview = viewport("Preview", details, off(140, 122), off(10, 10), 6)
	preview.BackgroundTransparency = 0.55
	preview.BackgroundColor3 = C(214, 226, 240)
	corner(preview, 12)
	compact(preview, {Size = off(200, 200), Position = off(10, 10)})
	local left = {TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7}
	compact(text("PetName", details, "Select a pet", off(300, 40), off(160, 8), left, 36), {Size = off(560, 48), Position = off(225, 8)}, 46)
	compact(text("Rarity", details, "", off(300, 26), off(160, 48), left, 24, 2), {Size = off(560, 36), Position = off(225, 60)}, 32)
	-- compact: the traits come last in the text column and wrap to up to three 30 px lines (a material + all
	-- eight mutations is ~1065 px at 30), top-aligned so a short list leaves the gap below it, not above
	compact(text("Traits", details, "", off(300, 24), off(160, 76), {TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, RichText = true}, 22, 2),
		{Size = off(560, 90), Position = off(225, 146), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top}, 30)
	local equip = button("EquipButton", details, "EQUIP", off(300, 44), off(160, 104), GREEN, 7)
	equip.Visible = false
	compact(equip, {Size = off(268, COMPACT_BUTTON_H), Position = off(800, 124)}, 34)
	local back = button("BackButton", details, "BACK", off(120, 44), off(340, 104), TAB_ON, 7)
	back.Visible = false -- wide layout: details are always beside the grid
	compact(back, {Size = off(268, COMPACT_BUTTON_H), Position = off(800, 8), Visible = true}, 34)
	compact(text("CashLine", details, "", off(442, 30), off(14, 146), {TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, RichText = true}, 28),
		{Size = off(560, 42), Position = off(225, 100)}, 36)
	compact(text("CombatLine", details, "", off(442, 26), off(14, 178), left, 24, 2), {Size = off(1052, 38), Position = off(14, 242)}, 30)
	compact(text("AbilityName", details, "", off(442, 30), off(14, 208), left, 28), {Size = off(1052, 40), Position = off(14, 284)}, 34)
	compact(text("AbilityEffect", details, "", off(442, 44), off(14, 238), {TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 7, TextWrapped = true}, 22, 2),
		{Size = off(1052, 76), Position = off(14, 328)}, 30)
	compact(text("AbilityChance", details, "", off(442, 24), off(14, 284), left, 22, 2), {Size = off(1052, 36), Position = off(14, 408)}, 30)
	compact(text("NextRoll", details, "", off(442, 24), off(14, 310), left, 22, 2), {Size = off(1052, 36), Position = off(14, 448)}, 30)

	-- totals
	local footer = make("Frame", "Footer", content, {Size = off(1068, 40), Position = off(36, 648), ZIndex = 8})
	compact(footer, {Size = off(1068, 52), Position = off(36, 646)})
	compact(text("PetCash", footer, "Pets  $0/s", off(340, 40), off(0, 0), {ZIndex = 9, RichText = true}, 30), {Size = off(340, 50)}, 34)
	compact(text("CucumberCash", footer, "Cucumbers  $0/s", off(340, 40), off(364, 0), {ZIndex = 9, RichText = true}, 30), {Size = off(340, 50)}, 34)
	compact(text("TotalCash", footer, "Total  $0/s", off(340, 40), off(728, 0), {ZIndex = 9, RichText = true}, 30), {Size = off(340, 50)}, 34)

	return panel
end

--..2. The paw opener..--
local function BuildOpener(hud)
	local menu = hud and hud:FindFirstChild("LeftMenu")
	local source = menu and menu:FindFirstChild("Index")
	if not source then return nil, "LeftMenu.Index missing" end
	local old = menu:FindFirstChild("Pets")
	if old then old:Destroy() end
	local labelSource = source:FindFirstChild("Label")
	local pets = source:Clone()
	for _, name in ipairs({"BookIcon", "Label", "OpenIndex"}) do
		local child = pets:FindFirstChild(name)
		if child then child:Destroy() end
	end
	strip(pets)
	pets.Name = "Pets"
	pets.Position = UDim2.new(1.07, 0, 0, 0)
	pets.Size = UDim2.new(1, 0, 0.455, 0)
	pets.ZIndex = 2
	pets.Visible = true
	make("UIAspectRatioConstraint", "Square", pets, {AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, AspectType = Enum.AspectType.FitWithinMaxSize})
	-- gold fill (the admin / build catalog gold) so the paw reads apart from Shop / Index
	local fill = pets:FindFirstChild("Fill")
	local fillGradient = fill and fill:FindFirstChild("ColorGradient")
	if fillGradient then fillGradient.Color = ColorSequence.new(GOLD[1], GOLD[2]) end
	local highlight = fill and fill:FindFirstChild("InnerHighlight")
	local highlightStroke = highlight and highlight:FindFirstChildOfClass("UIStroke")
	if highlightStroke then highlightStroke.Color = GOLD_HIGHLIGHT end
	-- frame-drawn paw: one pad + four toes, white with the HUD's dark outline
	local paw = make("Frame", "PawIcon", pets, {Size = UDim2.fromScale(0.56, 0.56), Position = UDim2.fromScale(0.5, 0.37), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 12})
	make("UIAspectRatioConstraint", "UIAspectRatioConstraint", paw, {AspectRatio = 1})
	local function blob(name, size, pos)
		local part = make("Frame", name, paw, {Size = size, Position = pos, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 0, ZIndex = 13})
		make("UICorner", "UICorner", part, {CornerRadius = UDim.new(1, 0)})
		make("UIStroke", "UIStroke", part, {Thickness = 2, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
		return part
	end
	blob("Pad", UDim2.fromScale(0.52, 0.44), UDim2.fromScale(0.5, 0.7))
	blob("Toe1", UDim2.fromScale(0.2, 0.25), UDim2.fromScale(0.15, 0.4))
	blob("Toe2", UDim2.fromScale(0.2, 0.25), UDim2.fromScale(0.37, 0.17))
	blob("Toe3", UDim2.fromScale(0.2, 0.25), UDim2.fromScale(0.63, 0.17))
	blob("Toe4", UDim2.fromScale(0.2, 0.25), UDim2.fromScale(0.85, 0.4))
	-- label in the Shop / Index style
	local label = make("TextLabel", "Label", pets, {Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.5, 0.81),
		AnchorPoint = Vector2.new(0.5, 0.5), Text = "Pets", TextScaled = true, ZIndex = 10,
		FontFace = labelSource and labelSource.FontFace or BUILDER_XB, TextColor3 = labelSource and labelSource.TextColor3 or WHITE})
	local sourceStroke = labelSource and labelSource:FindFirstChild("TextOutline")
	make("UIStroke", "TextOutline", label, {Thickness = sourceStroke and sourceStroke.Thickness or 2.5,
		Color = sourceStroke and sourceStroke.Color or DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual})
	make("TextButton", "OpenPets", pets, {Size = UDim2.fromScale(1, 1), ZIndex = 30, Selectable = true})
	pets.Parent = menu
	return pets
end

--..3. Reveal card lines..--
local function BuildRevealLabels(reveal)
	local template = reveal and reveal:FindFirstChild("SingleTemplate")
	if not template then return nil, "EggRevealUI.SingleTemplate missing" end
	for _, name in ipairs({"PetStats", "PetTraits"}) do
		local old = template:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local function line(name, size, pos)
		local label = make("TextLabel", name, template, {Size = size, Position = pos, AnchorPoint = Vector2.new(0.5, 0.5),
			TextScaled = true, RichText = true, Visible = false, ZIndex = 2})
		make("UIStroke", "UIStroke", label, {Thickness = 2.5, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual})
		return label
	end
	line("PetStats", UDim2.new(0.42, 0, 0.036, 0), UDim2.new(0.5, 0, 0.80, 0))
	line("PetTraits", UDim2.new(0.42, 0, 0.03, 0), UDim2.new(0.5, 0, 0.762, 0))
	return template
end

local function Build(targets)
	local report = {}
	local menus = targets.Menus
	local art = targets.Art
	if art == nil and menus then
		local index = menus:FindFirstChild("IndexPanel")
		art = index and index:FindFirstChild("Content")
	end
	local panel = BuildPanel(menus, art)
	report[#report + 1] = ("PetsPanel %d instances"):format(#panel:GetDescendants())
	local opener, openerError = BuildOpener(targets.Hud)
	report[#report + 1] = opener and ("LeftMenu.Pets %d instances"):format(#opener:GetDescendants()) or ("opener FAILED: " .. tostring(openerError))
	local reveal, revealError = BuildRevealLabels(targets.Reveal)
	report[#report + 1] = reveal and "EggRevealUI PetStats + PetTraits" or ("reveal labels FAILED: " .. tostring(revealError))
	local summary = "build_petspanel: " .. table.concat(report, "; ")
	print(summary)
	return summary
end

if type(args) == "table" and args.Mode == "module" then
	return {Build = Build, BuildPanel = BuildPanel, BuildOpener = BuildOpener, BuildRevealLabels = BuildRevealLabels}
end
return Build({
	Menus = StarterGui:WaitForChild("CucumberMenus", 5),
	Hud = StarterGui:WaitForChild("CucumberHUDDesign", 5),
	Reveal = StarterGui:WaitForChild("EggRevealUI", 5),
})
]====]
