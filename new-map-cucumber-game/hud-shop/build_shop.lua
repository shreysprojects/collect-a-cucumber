--[[
	build_shop.lua  (run ONCE in Studio EDIT mode through execute_luau; idempotent)
	Rebuilds  StarterGui.CucumberMenus.ShopPanel.Content  in the Zombie Cucumber Game "Store" look
	(Display.Frame.Frames.Store there): red "SHOP" ribbon, pink panel with a dark-red border, a left
	rail of square icon tabs, one scrolling catalog of sections (Strength packs, Cash packs, Boosts)
	made of the same green stud cards + orange Robux pills. Every instance is AUTHORED here (nothing
	is generated at runtime); ShopController.lua only wires prices, purchases and the tabs.
	Design size 1140 x 735 (the Zombie store's), fitted by MenuController.fit().
]]
local StarterGui = game:GetService("StarterGui")
local gui = StarterGui:WaitForChild("CucumberMenus")
local panel = gui:WaitForChild("ShopPanel")

local DARK_RED = Color3.fromRGB(118, 0, 0)
local PINK = Color3.fromRGB(240, 195, 195)
local GOLD = Color3.fromRGB(255, 220, 80)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

--.. art shared with the Zombie store (same creator, so the ids load here too)
local IMG = {
	Background = "rbxassetid://75881657992560", -- the framed panel
	Ribbon = "rbxassetid://75227340977908", -- red "SHOP" header ribbon
	CloseRect = "rbxassetid://102086640822931",
	ClosePlate = "rbxassetid://111663825325576",
	CloseX = "rbxassetid://73973960226016",
	CashTab = "rbxassetid://92289502784771", -- orange cash tile
	BoostsTab = "rbxassetid://126124956187141", -- blue lightning-cards tile
	CardBackground = "rbxassetid://115036257256165", -- green gradient card
	CardStuds = "rbxassetid://101976791108135",
	PillTop = "rbxassetid://82561484372883",
	PillBottom = "rbxassetid://135030509362648",
	PillUnion = "rbxassetid://81440968694247",
	Robux = "rbxassetid://107616907671837",
	RobuxBig = "rbxassetid://82049654718568",
	BigPillTop = "rbxassetid://118990973424405",
	BigPillBottom = "rbxassetid://89535966466387",
	BigPillUnion = "rbxassetid://77537703318285",
	StudTileA = "rbxassetid://72724192435339",
	StudTileB = "rbxassetid://117970221597391",
	BottomTex = "rbxassetid://123254421663343",
	BottomTexEnd = "rbxassetid://119756180284146",
	PurchaseArt = "rbxassetid://125061005728506",
	LightRight = "rbxassetid://101297226749959",
	LightCenter = "rbxassetid://100484807706069",
	LightLeft = "rbxassetid://71392333950633",
	LightFarLeft = "rbxassetid://75307019656350",
	ProgressBar = "rbxassetid://91407226690699",
	--.. this game's own icons (already on the HUD)
	StrengthIcon = "rbxassetid://15403007921",
	CashIcon = "rbxassetid://15402839520",
}
local FONT_MONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
local FONT_MONT_XB = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
local FONT_BUILDER = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local FONT_BUILDER_XB = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local FONT_FREDOKA = Font.fromEnum(Enum.Font.FredokaOne)

local function off(w, h) return UDim2.fromOffset(w, h) end
local function make(class, name, parent, props)
	local inst = Instance.new(class)
	inst.Name = name
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
		inst.BackgroundTransparency = 1
		inst.BackgroundColor3 = WHITE
	end
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then inst.ScaleType = Enum.ScaleType.Fit end
	if inst:IsA("GuiButton") then inst.AutoButtonColor = false end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		inst.Text = ""
		inst.TextColor3 = WHITE
	end
	for k, v in pairs(props or {}) do inst[k] = v end
	inst.Parent = parent
	return inst
end
local function stroke(parent, thickness, color, mode)
	return make("UIStroke", "UIStroke", parent, {Thickness = thickness, Color = color, ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border})
end
local function label(name, parent, text, font, props)
	local l = make("TextLabel", name, parent, props)
	l.FontFace = font
	l.TextScaled = true
	l.Text = text
	return l
end
local function gradient(parent, rotation, stops)
	local keys = {}
	for _, s in ipairs(stops) do table.insert(keys, ColorSequenceKeypoint.new(s[1], s[2])) end
	return make("UIGradient", "UIGradient", parent, {Rotation = rotation, Color = ColorSequence.new(keys)})
end
local PILL_GRADIENT = {{0, Color3.fromRGB(255, 230, 130)}, {0.16, Color3.fromRGB(255, 230, 130)}, {0.97, Color3.fromRGB(255, 128, 0)}, {1, Color3.fromRGB(255, 128, 0)}}

--.. orange Robux pill (151 x 55) centred on (cx, cy); ProductId lives on the CARD (button.Parent)
local function purchasePill(parent, cx, cy)
	local btn = make("ImageButton", "PurchaseButton", parent, {Size = off(151, 55), AnchorPoint = Vector2.new(0.5, 0.5), Position = off(cx, cy), ZIndex = 13, ImageTransparency = 1})
	btn:SetAttribute("PurchaseTemplate", true)
	local bg = make("Frame", "PurchaseBackground", btn, {Size = off(151, 55), BackgroundTransparency = 0, ZIndex = 11})
	stroke(bg, 4, BLACK)
	gradient(bg, 23, PILL_GRADIENT)
	make("ImageLabel", "TopHighlight", btn, {Image = IMG.PillTop, Size = off(52, 55), Position = off(45, 0), ZIndex = 12})
	make("ImageLabel", "BottomHighlight", btn, {Image = IMG.PillBottom, Size = off(65, 55), Position = off(80, 0), ZIndex = 12})
	make("ImageLabel", "Union", btn, {Image = IMG.PillUnion, Size = off(151, 55), ZIndex = 12})
	make("ImageLabel", "RobuxIcon", btn, {Image = IMG.Robux, Size = off(52, 52), Position = off(19, 2), ZIndex = 13, ScaleType = Enum.ScaleType.Stretch})
	local price = label("Price", btn, "...", FONT_BUILDER, {Size = off(60, 28), Position = off(63, 8), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 14})
	stroke(price, 2, BLACK, Enum.ApplyStrokeMode.Contextual)
	return btn
end

--.. one green stud card (208 x 248): "+100" on top, the icon, the pill
local function productCard(name, parent, order, amountText, iconId, iconSize, attrs)
	local card = make("Frame", name, parent, {Size = off(208, 248), LayoutOrder = order, ZIndex = 5, ClipsDescendants = true})
	for k, v in pairs(attrs) do card:SetAttribute(k, v) end
	make("ImageLabel", "CardBackground", card, {Image = IMG.CardBackground, Size = off(208, 248), ZIndex = 6})
	make("ImageLabel", "StudTexture", card, {Image = IMG.CardStuds, Size = off(435, 149), Position = off(7, 93), ZIndex = 6})
	local amount = label("Amount", card, amountText, FONT_MONT, {Size = off(196, 39), Position = off(6, 11), ZIndex = 8})
	stroke(amount, 3, BLACK, Enum.ApplyStrokeMode.Contextual)
	make("ImageLabel", "Icon", card, {Image = iconId, Size = off(iconSize, iconSize), AnchorPoint = Vector2.new(0.5, 0.5), Position = off(104, 112), ZIndex = 8})
	purchasePill(card, 104, 202)
	return card
end

local function sectionHeader(name, parent, order, text)
	local h = make("Frame", name .. "Header", parent, {Size = UDim2.new(1, -8, 0, 34), LayoutOrder = order})
	local t = label("Title", h, text, FONT_FREDOKA, {Size = UDim2.fromScale(1, 1), TextColor3 = GOLD})
	stroke(t, 2, Color3.fromRGB(90, 30, 10), Enum.ApplyStrokeMode.Contextual)
	return h
end
local function gridSection(name, parent, order, height)
	local s = make("Frame", name .. "Section", parent, {Size = UDim2.new(1, -8, 0, height), LayoutOrder = order})
	make("UIGridLayout", "ProductGrid", s, {CellSize = off(205, 248), CellPadding = off(8, 15), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder})
	return s
end

--.. the wide green boost card (881 x 264, drawn at 0.96 like the Zombie one)
local function boostPill(parent, name, cx, cy, duration)
	local btn = make("ImageButton", name, parent, {Size = off(178, 65), AnchorPoint = Vector2.new(0.5, 0.5), Position = off(cx, cy), ZIndex = 30, ImageTransparency = 1})
	btn:SetAttribute("PurchaseTemplate", true)
	btn:SetAttribute("HoverBaseScale", 0.81)
	btn:SetAttribute("ProductId", 0)
	btn:SetAttribute("DurationTitle", duration)
	local bg = make("Frame", "PurchaseBackground", btn, {Size = off(178, 65), BackgroundTransparency = 0, ZIndex = 31})
	stroke(bg, 4, BLACK)
	gradient(bg, 23, PILL_GRADIENT)
	make("ImageLabel", "TopHighlight", btn, {Image = IMG.BigPillTop, Size = off(61, 65), Position = off(53, 0), ZIndex = 32})
	make("ImageLabel", "BottomHighlight", btn, {Image = IMG.BigPillBottom, Size = off(75, 65), Position = off(96, 0), ZIndex = 33})
	make("ImageLabel", "TextureOverlay", btn, {Image = IMG.BigPillUnion, Size = off(178, 65), ZIndex = 34})
	make("ImageLabel", "RobuxIcon", btn, {Image = IMG.RobuxBig, Size = off(61, 61), Position = off(2, 2), ZIndex = 35, ScaleType = Enum.ScaleType.Stretch})
	local price = label("Price", btn, "...", FONT_BUILDER, {Size = off(98, 34), Position = off(68, 1), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 36})
	stroke(price, 2, BLACK, Enum.ApplyStrokeMode.Contextual)
	local dur = label("Duration", btn, duration, FONT_BUILDER, {Size = off(116, 27), Position = off(55, 35), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 37})
	stroke(dur, 2, BLACK, Enum.ApplyStrokeMode.Contextual)
	return btn
end
local function boostCard(parent)
	local card = make("Frame", "DoubleStrengthBoostCard", parent, {Size = off(881, 264), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), ZIndex = 6})
	card:SetAttribute("Boost", "x2 Strength")
	make("UIScale", "CardScale", card, {Scale = 0.96})
	local bg = make("Frame", "CardBackground", card, {Size = off(870, 260), Position = off(11, 4), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(102, 255, 68), ZIndex = 6})
	stroke(bg, 6, BLACK)
	gradient(bg, 90, {{0, Color3.fromRGB(203, 255, 119)}, {1, Color3.fromRGB(30, 255, 0)}})
	make("Frame", "BottomBorder", card, {Size = off(870, 14), Position = off(11, 250), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(23, 142, 2), ZIndex = 7})
	local studs = make("Frame", "StudTexture", card, {Size = off(863, 237), Position = off(14, 8), ZIndex = 9, ClipsDescendants = true})
	for i, x in ipairs({0, 173, 345, 518, 690}) do
		make("ImageLabel", "StudTile" .. i, studs, {Image = (i % 2 == 1) and IMG.StudTileA or IMG.StudTileB, Size = off(173, 172), Position = off(x, 0), ZIndex = 5 + i, ScaleType = Enum.ScaleType.Stretch})
	end
	for i, x in ipairs({674, 502, 330, 158}) do
		make("ImageLabel", "BottomTexture" .. i, studs, {Image = IMG.BottomTex, Size = off(173, 28), Position = off(x, 209), ZIndex = 10 + i, ScaleType = Enum.ScaleType.Stretch})
	end
	make("ImageLabel", "BottomTexture5", studs, {Image = IMG.BottomTexEnd, Size = off(159, 28), Position = off(0, 209), ZIndex = 15, ScaleType = Enum.ScaleType.Stretch})
	for i, x in ipairs({690, 517, 344, 171, 1}) do
		make("ImageLabel", "PurchaseArtwork" .. i, studs, {Image = IMG.PurchaseArt, Size = off(173, 41), Position = off(x, 172), ZIndex = 15 + i, ScaleType = Enum.ScaleType.Stretch})
	end
	make("ImageLabel", "RightLightOverlay", card, {Image = IMG.LightRight, Size = off(243, 222), Position = off(545, 4), ZIndex = 11})
	make("ImageLabel", "CenterLightOverlay", card, {Image = IMG.LightCenter, Size = off(163, 222), Position = off(440, 4), ZIndex = 12})
	make("ImageLabel", "LeftLightOverlay", card, {Image = IMG.LightLeft, Size = off(107, 222), Position = off(155, 4), ZIndex = 13})
	make("ImageLabel", "FarLeftLightOverlay", card, {Image = IMG.LightFarLeft, Size = off(136, 222), Position = off(56, 4), ZIndex = 14})
	make("ImageLabel", "Artwork", card, {Image = IMG.StrengthIcon, Size = off(150, 150), Position = off(12, 8), ZIndex = 15})
	local desc = label("DescriptionLabel", card, "Double the strength you gain from every rep!", FONT_MONT, {Size = off(479, 54), Position = off(384, 67), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 16})
	stroke(desc, 3, BLACK, Enum.ApplyStrokeMode.Contextual)
	local title = label("BoostNameLabel", card, "x2 Strength", FONT_MONT_XB, {Size = off(343, 55), Position = off(522, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 17})
	stroke(title, 3, BLACK, Enum.ApplyStrokeMode.Contextual)
	local keep = label("PersistenceLabel", card, "SAVES WHEN\nYOU LEAVE!", FONT_MONT_XB, {Size = off(145, 44), Position = off(27, 164), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 0, 0), ZIndex = 18})
	stroke(keep, 2, BLACK, Enum.ApplyStrokeMode.Contextual)
	local bar = make("ImageLabel", "ProgressBarArtwork", card, {Image = IMG.ProgressBar, ImageTransparency = 1, Size = off(260, 27), Position = off(22, 214), ZIndex = 19})
	local track = make("Frame", "ProgressTrack", bar, {Size = UDim2.new(1, -6, 1, -6), Position = off(3, 3), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(245, 245, 245), ZIndex = 20})
	make("Frame", "ProgressFill", track, {Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(26, 190, 19), ZIndex = 21, Visible = false})
	make("UIStroke", "TrackBorder", track, {Thickness = 3, Color = BLACK})
	--.. three duration pills (centres match the Zombie card's 0.81-scaled pills)
	boostPill(card, "Purchase15Minutes", 415, 198, "+15 MINS")
	boostPill(card, "Purchase1Hour", 601, 198, "+1 HOUR")
	boostPill(card, "Purchase5Hours", 787, 198, "+5 HOURS")
	return card
end

--.. a square rail tab; composed tile when there is no art for it
local function tab(name, parent, y, section, imageId, tileColor, iconId)
	local btn = make("ImageButton", name, parent, {Size = off(93, 91), AnchorPoint = Vector2.new(0.5, 0.5), Position = off(46, y + 45), ZIndex = 6, ImageTransparency = 1})
	btn:SetAttribute("Section", section)
	make("UIScale", "TabScale", btn)
	if imageId then
		btn.Image = imageId
		btn.ImageTransparency = 0
	else
		local tile = make("Frame", "Tile", btn, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = tileColor, ZIndex = 6})
		make("UICorner", "UICorner", tile, {CornerRadius = UDim.new(0, 12)})
		stroke(tile, 3, Color3.fromRGB(60, 35, 15))
		gradient(tile, 90, {{0, Color3.fromRGB(255, 255, 255)}, {1, Color3.fromRGB(170, 170, 170)}})
		local inner = make("Frame", "Inner", tile, {Size = UDim2.new(1, -12, 1, -12), Position = off(6, 6), ZIndex = 7})
		make("UICorner", "UICorner", inner, {CornerRadius = UDim.new(0, 8)})
		make("UIStroke", "UIStroke", inner, {Thickness = 2, Color = WHITE, Transparency = 0.35})
		make("ImageLabel", "Icon", tile, {Image = iconId, Size = off(66, 66), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 8})
	end
	return btn
end

--------------------------------------------------------------------------------------------------
panel.Size = off(1140, 735)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundTransparency = 1
if not panel:FindFirstChild("ResponsiveScale") then make("UIScale", "ResponsiveScale", panel) end

local content = panel:FindFirstChild("Content")
if not content or not content:IsA("CanvasGroup") then
	if content then content:Destroy() end
	content = make("CanvasGroup", "Content", panel, {Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 2})
end
for _, child in ipairs(content:GetChildren()) do
	if child.Name ~= "MotionScale" then child:Destroy() end
end
if not content:FindFirstChild("MotionScale") then make("UIScale", "MotionScale", content) end
content.Visible = false -- MenuController shows it
content.GroupTransparency = 1
content.BackgroundTransparency = 1

--.. frame art, ribbon, title
make("ImageLabel", "Background", content, {Image = IMG.Background, Size = off(969, 686), Position = off(106, 47), ZIndex = 2})
local header = make("ImageLabel", "Header", content, {Image = IMG.Ribbon, Size = off(333, 93), Position = off(70, 0), ZIndex = 3})
local title = label("Title", header, "SHOP", FONT_BUILDER_XB, {Size = off(221, 87), Position = off(56, 3), ZIndex = 4})
stroke(title, 5, DARK_RED, Enum.ApplyStrokeMode.Contextual)

--.. pink content panel with the scrolling catalog
local contentPanel = make("Frame", "ContentPanel", content, {Size = off(917, 590), Position = off(133, 109), BackgroundTransparency = 0, BackgroundColor3 = PINK, ZIndex = 5})
stroke(contentPanel, 4, DARK_RED)
local catalog = make("ScrollingFrame", "Catalog", contentPanel, {
	Size = UDim2.new(1, -40, 1, -40), Position = off(20, 20), ZIndex = 10,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 8,
	ScrollBarImageColor3 = Color3.fromRGB(150, 40, 40), ElasticBehavior = Enum.ElasticBehavior.Never,
})
make("UIListLayout", "CatalogLayout", catalog, {Padding = UDim.new(0, 12), FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder})

sectionHeader("Strength", catalog, 10, "💪 STRENGTH PACKS — GET STRONGER INSTANTLY")
local strength = gridSection("Strength", catalog, 11, 248)
productCard("SmallStrengthPack", strength, 1, "+100", IMG.StrengthIcon, 116, {StrengthAmount = 100, ProductId = 0})
productCard("MediumStrengthPack", strength, 2, "+1,000", IMG.StrengthIcon, 116, {StrengthAmount = 1000, ProductId = 0})
productCard("LargeStrengthPack", strength, 3, "+10,000", IMG.StrengthIcon, 116, {StrengthAmount = 10000, ProductId = 0})

sectionHeader("Cash", catalog, 20, "🪙 CASH PACKS — FILL YOUR WALLET")
local cash = gridSection("Cash", catalog, 21, 248)
productCard("SmallCashPack", cash, 1, "+10K", IMG.CashIcon, 112, {CashAmount = 10000, ProductId = 0})
productCard("MediumCashPack", cash, 2, "+50K", IMG.CashIcon, 112, {CashAmount = 50000, ProductId = 0})
productCard("LargeCashPack", cash, 3, "+250K", IMG.CashIcon, 112, {CashAmount = 250000, ProductId = 0})

sectionHeader("Boosts", catalog, 30, "⚡ BOOSTS — DOUBLE YOUR GAINS")
local boosts = make("Frame", "BoostsSection", catalog, {Size = UDim2.new(1, -8, 0, 262), LayoutOrder = 31})
boostCard(boosts)

--.. left tab rail
local rail = make("Frame", "TabRail", content, {Size = UDim2.fromScale(1, 1), ZIndex = 5})
tab("StrengthTab", rail, 153, "Strength", nil, Color3.fromRGB(150, 225, 95), IMG.StrengthIcon)
tab("CashTab", rail, 255, "Cash", IMG.CashTab)
tab("BoostsTab", rail, 356, "Boosts", IMG.BoostsTab)

--.. red close button (MenuController wires .Activated + hover)
local close = make("ImageButton", "CloseButton", content, {Size = off(86, 86), AnchorPoint = Vector2.new(0.5, 0.5), Position = off(1067, 56), ZIndex = 30, ImageTransparency = 1})
make("ImageLabel", "Rectangle", close, {Image = IMG.CloseRect, Size = off(81, 85), Position = off(-3, -6), ZIndex = 31, ScaleType = Enum.ScaleType.Stretch})
make("ImageLabel", "Plate", close, {Image = IMG.ClosePlate, Size = off(72, 72), Position = off(0, 2), ZIndex = 31, ScaleType = Enum.ScaleType.Stretch})
local x = make("Frame", "X", close, {Size = off(40, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = off(36, 35), ZIndex = 32})
make("ImageLabel", "X", x, {Image = IMG.CloseX, Size = off(46, 48), Position = off(-3, -4), ZIndex = 32})

panel:SetAttribute("RequestedTab", "Strength")
panel:SetAttribute("Reference", "Zombie Cucumber Game Store look (Display.Frame.Frames.Store); built by hud-shop/build_shop.lua; ShopController wires it")
print("[build_shop] ShopPanel rebuilt:", #content:GetDescendants(), "instances")
