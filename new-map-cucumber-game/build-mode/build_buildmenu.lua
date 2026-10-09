-- build_buildmenu.lua: edit-mode builder for StarterGui.BuildMenu (run by install.lua, which passes the
-- BuildMenuClient source as the chunk argument). Rebuilds the ScreenGui from scratch every run; every
-- instance is authored here, BuildMenuClient only clones the Templates and sizes things in pixels.
-- Button shell = the HUD LeftMenu look (dark 12,12,12 rounded frame, 2 px outline, white Fill with a
-- vertical gradient + the stud texture at 0.4, InnerHighlight stroke, BuilderSans ExtraBold label
-- with a 2.5 px dark outline, a transparent TextButton "Press" on top).
-- Layout: Categories (bottom row: category buttons, the square X, the square Sell and Grid icons),
-- Catalog (since 2026-09-12 a bare strip of BuildCards just above the Categories row: the panel background,
-- outline, Fill and the Bar (Back / Title / Hint) are authored but hidden - the client keeps them hidden and
-- sizes the strip to its cards), Placing (shown INSTEAD of the others while a
-- build is on the mouse: a hint line over Rotate / Grid / Collisions / Cancel), Templates (hidden
-- CategoryButton / BuildCard / Icons).
local clientSource = ...
local StarterGui = game:GetService("StarterGui")

local DARK = Color3.fromRGB(12, 12, 12)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 200, 60)
local RED = Color3.fromRGB(235, 35, 35)
local CHECK = Color3.fromRGB(40, 175, 60)
local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local FONT_MEDIUM = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold)
local STUDS = "rbxassetid://14905298636"
local CASH = "rbxassetid://15402839520"
local ICON_SELL = "rbxassetid://8214461591" -- Creator Store trash can (decal 8214461600 -> its IMAGE id; an ImageLabel needs the image, not the decal)
local ICON_SELL_TINT = WHITE -- the PNG is already a black outline on a transparent background
local GREEN_TOP, GREEN_BOTTOM, GREEN_HIGHLIGHT = Color3.fromRGB(157, 255, 36), Color3.fromRGB(69, 255, 0), Color3.fromRGB(208, 255, 106)

local function new(class, name, parent, props)
	local inst = Instance.new(class)
	inst.Name = name
	if props then
		for k, v in pairs(props) do inst[k] = v end
	end
	inst.Parent = parent
	return inst
end
local function corner(parent, px, scale)
	return new("UICorner", "Corners", parent, {CornerRadius = UDim.new(scale or 0, px or 0)})
end
local function stroke(parent, thickness, color, name)
	return new("UIStroke", name or "Outline", parent, {Thickness = thickness, Color = color, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end
local function frame(name, parent, props)
	local f = new("Frame", name, parent, {BorderSizePixel = 0})
	for k, v in pairs(props or {}) do f[k] = v end
	return f
end

--.. HUD-style button shell (Fill gradient + InnerHighlight colour are painted per use by the client)
local function Shell(name, parent, width, height)
	local b = frame(name, parent, {BackgroundColor3 = DARK, Size = UDim2.fromOffset(width or 122, height or 47), ZIndex = 2})
	corner(b, 4)
	stroke(b, 2, DARK)
	local fill = frame("Fill", b, {BackgroundColor3 = WHITE, Position = UDim2.fromScale(0.018, 0.045), Size = UDim2.fromScale(0.964, 0.91), ZIndex = 3})
	corner(fill, 2)
	new("UIGradient", "ColorGradient", fill, {Rotation = 90, Color = ColorSequence.new(GREEN_TOP, GREEN_BOTTOM)})
	new("ImageLabel", "StudTexture", fill, {BackgroundTransparency = 1, BorderSizePixel = 0, Image = STUDS, ImageTransparency = 0.4,
		ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(112, 112), Size = UDim2.fromScale(1, 1), ZIndex = 4})
	local highlight = frame("InnerHighlight", fill, {BackgroundTransparency = 1, Position = UDim2.fromScale(0.017, 0.045), Size = UDim2.fromScale(0.966, 0.91), ZIndex = 5})
	corner(highlight, 2)
	stroke(highlight, 1.5, GREEN_HIGHLIGHT)
	new("UIScale", "Pop", b, {Scale = 1})
	return b
end
local function Label(name, parent, text, props)
	local l = new("TextLabel", name, parent, {BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = FONT, Text = text, TextColor3 = WHITE,
		TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 10})
	new("UIStroke", "TextOutline", l, {Thickness = 2.5, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual})
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end
local function Press(parent)
	return new("TextButton", "Press", parent, {BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 30})
end
local function TextSizeCap(parent, max)
	return new("UITextSizeConstraint", "SizeCap", parent, {MaxTextSize = max, MinTextSize = 8})
end
local function ActionButton(name, parent, text)
	local b = Shell(name, parent, 122, 47)
	Label("Label", b, text, {Position = UDim2.fromScale(0.08, 0.14), Size = UDim2.fromScale(0.84, 0.72)})
	TextSizeCap(b.Label, 26)
	Press(b)
	return b
end
--.. a small corner tag (the grid size) on a square button
local function CornerTag(parent)
	local t = Label("Corner", parent, "1", {AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(0.95, 0.93), Size = UDim2.fromScale(0.5, 0.36), TextXAlignment = Enum.TextXAlignment.Right, Visible = false, ZIndex = 14})
	t.TextOutline.Thickness = 2
	TextSizeCap(t, 18)
	return t
end
--.. the grid glyph: a dark-outlined box (no fill); the client draws N dark bars each way inside "Lines"
--.. (1 stud = 2 bars = the 3 x 3 look, and one more bar each way per Grid press)
local function GridGlyph(parent)
	local box = frame("Box", parent, {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 13})
	corner(box, 0, 0.14)
	stroke(box, 2, DARK)
	frame("Lines", box, {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 14})
	return box
end
--.. a square button holding the grid glyph
local function GridSquare(name, parent)
	local b = Shell(name, parent, 47, 47)
	local slot = frame("Icon", b, {BackgroundTransparency = 1, Position = UDim2.fromScale(0.15, 0.15), Size = UDim2.fromScale(0.7, 0.7), ZIndex = 12})
	new("UIAspectRatioConstraint", "Square", slot, {AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height})
	GridGlyph(slot)
	CornerTag(b)
	Press(b)
	return b
end

local old = StarterGui:FindFirstChild("BuildMenu")
if old then old:Destroy() end
local gui = new("ScreenGui", "BuildMenu", nil, {ResetOnSpawn = false, DisplayOrder = 25, IgnoreGuiInset = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = true})

--..Categories row (bottom centre, transparent container; the client clones CategoryButton into it)..--
local categories = frame("Categories", gui, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1, Visible = false})
new("UIListLayout", "Layout", categories, {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)})

--..Catalog panel (bottom centre): Bar (Back / title / hint) + Row of BuildCards..--
local catalog = frame("Catalog", gui, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -88), Size = UDim2.fromOffset(800, 140), BackgroundColor3 = DARK, BackgroundTransparency = 1, Visible = false, ZIndex = 2, Active = true}) -- Active: a click on the panel never falls through to the placement
corner(catalog, 6)
stroke(catalog, 2, DARK)
new("UIScale", "Pop", catalog, {Scale = 1})
local panel = frame("Fill", catalog, {BackgroundColor3 = Color3.fromRGB(30, 30, 38), Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), ZIndex = 3, Visible = false}) -- hidden: the strip has no background (2026-09-12)
corner(panel, 5)
new("ImageLabel", "StudTexture", panel, {BackgroundTransparency = 1, BorderSizePixel = 0, Image = STUDS, ImageTransparency = 0.82,
	ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(112, 112), Size = UDim2.fromScale(1, 1), ZIndex = 4})
local panelHighlight = frame("InnerHighlight", panel, {BackgroundTransparency = 1, Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), ZIndex = 5})
corner(panelHighlight, 4)
stroke(panelHighlight, 1.5, Color3.fromRGB(72, 72, 88))

local bar = frame("Bar", catalog, {BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 36), ZIndex = 6, Visible = false}) -- hidden: no Back / title / hint (2026-09-12)
local back = Shell("BackButton", bar, 86, 32)
back.AnchorPoint = Vector2.new(0, 0.5)
back.Position = UDim2.fromScale(0, 0.5)
Label("Label", back, "< Back", {Position = UDim2.fromScale(0.08, 0.12), Size = UDim2.fromScale(0.84, 0.76)})
TextSizeCap(back.Label, 22)
Press(back)
local title = Label("Title", bar, "Walls", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 100, 0.5, 0), Size = UDim2.new(0.3, 0, 0.95, 0), TextXAlignment = Enum.TextXAlignment.Left})
TextSizeCap(title, 26)
local hint = new("TextLabel", "Hint", bar, {BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = FONT_MEDIUM, Text = "Pick a build", TextColor3 = Color3.fromRGB(215, 215, 228),
	TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0.3, 0, 0.6, 0), ZIndex = 10})
TextSizeCap(hint, 16)

local row = new("ScrollingFrame", "Row", catalog, {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 48), Size = UDim2.new(1, -16, 1, -56),
	ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ScrollBarThickness = 6,
	ScrollBarImageColor3 = Color3.fromRGB(200, 200, 214), ScrollBarImageTransparency = 0.25, HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, ZIndex = 6})
new("UIListLayout", "Layout", row, {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)})
new("UIPadding", "Padding", row, {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2)})

--..Placing (bottom centre, replaces the other panels while a build is on the mouse): hint over Rotate / Grid / Collisions / Cancel..--
local placing = frame("Placing", gui, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, 0, 0, 80), BackgroundTransparency = 1, Visible = false})
new("UIScale", "Pop", placing, {Scale = 1})
local placingHint = new("TextLabel", "Hint", placing, {BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = FONT_MEDIUM, Text = "Click to place", TextColor3 = Color3.fromRGB(240, 240, 248),
	TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.7, 0, 0, 22), ZIndex = 10})
new("UIStroke", "TextOutline", placingHint, {Thickness = 2, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual})
TextSizeCap(placingHint, 18)
local placingButtons = frame("Buttons", placing, {BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 0, 0, 47)})
new("UIListLayout", "Layout", placingButtons, {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10)})
local rotate = ActionButton("RotateButton", placingButtons, "Rotate")
rotate.LayoutOrder = 1
local stripGrid = GridSquare("GridButton", placingButtons)
stripGrid.LayoutOrder = 2
stripGrid.Corner.Visible = true
-- the Collisions checkbox: a white box with a green tick beside the word
local collisions = Shell("CollisionsButton", placingButtons, 112, 47)
collisions.LayoutOrder = 3
local box = frame("Box", collisions, {BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.08, 0.5), Size = UDim2.fromScale(0.26, 0.6), ZIndex = 12})
new("UIAspectRatioConstraint", "Square", box, {AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height})
corner(box, 3)
stroke(box, 2, DARK)
local check = frame("Check", box, {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 13})
local short = frame("Short", check, {BackgroundColor3 = CHECK, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.34, 0.62), Size = UDim2.fromScale(0.2, 0.45), Rotation = -45, ZIndex = 14})
corner(short, 0, 0.4)
local long = frame("Long", check, {BackgroundColor3 = CHECK, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.6, 0.5), Size = UDim2.fromScale(0.2, 0.8), Rotation = 40, ZIndex = 14})
corner(long, 0, 0.4)
Label("Label", collisions, "Collisions", {Position = UDim2.fromScale(0.4, 0.16), Size = UDim2.fromScale(0.56, 0.68), TextXAlignment = Enum.TextXAlignment.Left})
TextSizeCap(collisions.Label, 22)
Press(collisions)
local cancel = ActionButton("CancelButton", placingButtons, "Cancel")
cancel.LayoutOrder = 4

--..Templates (hidden; a Folder does not hide GUI children, so each one is Visible = false and the client shows its clones)..--
local templates = new("Folder", "Templates", gui)

local categoryButton = Shell("CategoryButton", templates, 122, 47)
categoryButton.Visible = false
local iconSlot = frame("Icon", categoryButton, {BackgroundTransparency = 1, Position = UDim2.fromScale(0.06, 0.16), Size = UDim2.fromScale(0.24, 0.68), ZIndex = 12})
new("UIAspectRatioConstraint", "Square", iconSlot, {AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height})
Label("Label", categoryButton, "Walls", {Position = UDim2.fromScale(0.36, 0.15), Size = UDim2.fromScale(0.6, 0.7), TextXAlignment = Enum.TextXAlignment.Left})
TextSizeCap(categoryButton.Label, 30)
CornerTag(categoryButton)
Press(categoryButton)

local card = frame("BuildCard", templates, {Visible = false, BackgroundColor3 = DARK, Size = UDim2.fromOffset(120, 150), ZIndex = 2})
corner(card, 6)
stroke(card, 2, DARK)
new("UIScale", "Pop", card, {Scale = 1})
local cardFill = frame("Fill", card, {BackgroundColor3 = Color3.fromRGB(44, 44, 56), Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), ZIndex = 3})
corner(cardFill, 5)
new("ImageLabel", "StudTexture", cardFill, {BackgroundTransparency = 1, BorderSizePixel = 0, Image = STUDS, ImageTransparency = 0.72,
	ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(112, 112), Size = UDim2.fromScale(1, 1), ZIndex = 4})
local cardHighlight = frame("InnerHighlight", cardFill, {BackgroundTransparency = 1, Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), ZIndex = 5})
corner(cardHighlight, 4)
stroke(cardHighlight, 1.5, Color3.fromRGB(96, 96, 116))
new("ViewportFrame", "View", card, {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.9, 0.58),
	Ambient = Color3.fromRGB(165, 165, 178), LightColor = Color3.fromRGB(255, 255, 255), LightDirection = Vector3.new(-0.4, -1, -0.6), ZIndex = 6})
Label("Title", card, "Wooden Wall", {Position = UDim2.fromScale(0.05, 0.63), Size = UDim2.fromScale(0.9, 0.17)})
TextSizeCap(card.Title, 20)
local costRow = frame("CostRow", card, {BackgroundTransparency = 1, Position = UDim2.fromScale(0.1, 0.81), Size = UDim2.fromScale(0.8, 0.14), ZIndex = 8})
new("UIListLayout", "Layout", costRow, {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4)})
local cash = new("ImageLabel", "CashIcon", costRow, {BackgroundTransparency = 1, BorderSizePixel = 0, Image = CASH, Size = UDim2.fromScale(1, 1), LayoutOrder = 1, ZIndex = 9})
new("UIAspectRatioConstraint", "Square", cash, {AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height})
local cost = Label("CostLabel", costRow, "150", {Size = UDim2.fromScale(0.7, 1), TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X})
cost.Size = UDim2.fromScale(0, 1)
TextSizeCap(cost, 20)
Press(card)

--..Icons: glyphs the client copies into a category button's Icon slot..--
local icons = new("Folder", "Icons", templates)
local function glyph(name)
	return frame(name, icons, {Visible = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 12})
end
local function piece(parent, props, radiusScale)
	local p = frame("Piece", parent, {ZIndex = 13, AnchorPoint = Vector2.new(0.5, 0.5)})
	for k, v in pairs(props) do p[k] = v end
	if radiusScale then corner(p, 0, radiusScale) end
	return p
end
-- Walls: three courses of bricks in running bond
local walls = glyph("Walls")
local brick = Color3.fromRGB(240, 170, 95)
for row_, y in ipairs({0.18, 0.5, 0.82}) do
	if row_ == 2 then
		piece(walls, {BackgroundColor3 = brick, Position = UDim2.fromScale(0.12, y), Size = UDim2.fromScale(0.2, 0.26)}, 0.15)
		piece(walls, {BackgroundColor3 = brick, Position = UDim2.fromScale(0.5, y), Size = UDim2.fromScale(0.42, 0.26)}, 0.15)
		piece(walls, {BackgroundColor3 = brick, Position = UDim2.fromScale(0.88, y), Size = UDim2.fromScale(0.2, 0.26)}, 0.15)
	else
		piece(walls, {BackgroundColor3 = brick, Position = UDim2.fromScale(0.26, y), Size = UDim2.fromScale(0.46, 0.26)}, 0.15)
		piece(walls, {BackgroundColor3 = brick, Position = UDim2.fromScale(0.75, y), Size = UDim2.fromScale(0.46, 0.26)}, 0.15)
	end
end
for _, p in ipairs(walls:GetChildren()) do stroke(p, 1.5, DARK) end
-- Defences: three spike tips over a dark base plate
local defences = glyph("Defences")
for _, x in ipairs({0.18, 0.5, 0.82}) do
	local spike = piece(defences, {BackgroundColor3 = Color3.fromRGB(236, 236, 246), Position = UDim2.fromScale(x, 0.5), Size = UDim2.fromScale(0.3, 0.3), Rotation = 45}, 0.08)
	stroke(spike, 1.5, DARK)
end
local plate = piece(defences, {BackgroundColor3 = Color3.fromRGB(70, 70, 84), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromScale(0.98, 0.34), ZIndex = 14}, 0.25)
stroke(plate, 1.5, DARK)
-- Garden: a round bush on a soil patch
local garden = glyph("Garden")
local soil = piece(garden, {BackgroundColor3 = Color3.fromRGB(125, 84, 44), Position = UDim2.fromScale(0.5, 0.86), Size = UDim2.fromScale(0.94, 0.24)}, 1)
stroke(soil, 1.5, DARK)
local bushA = piece(garden, {BackgroundColor3 = Color3.fromRGB(72, 186, 62), Position = UDim2.fromScale(0.36, 0.5), Size = UDim2.fromScale(0.56, 0.56), ZIndex = 14}, 1)
stroke(bushA, 1.5, DARK)
local bushB = piece(garden, {BackgroundColor3 = Color3.fromRGB(72, 186, 62), Position = UDim2.fromScale(0.66, 0.56), Size = UDim2.fromScale(0.5, 0.5), ZIndex = 14}, 1)
stroke(bushB, 1.5, DARK)
piece(garden, {BackgroundColor3 = Color3.fromRGB(130, 230, 100), Position = UDim2.fromScale(0.42, 0.38), Size = UDim2.fromScale(0.2, 0.2), ZIndex = 15}, 1)
-- Fun: an eight-point star
local fun = glyph("Fun")
local starA = piece(fun, {BackgroundColor3 = Color3.fromRGB(255, 220, 70), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62)}, 0.12)
stroke(starA, 1.5, DARK)
local starB = piece(fun, {BackgroundColor3 = Color3.fromRGB(255, 220, 70), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62), Rotation = 45}, 0.12)
stroke(starB, 1.5, DARK)
piece(fun, {BackgroundColor3 = Color3.fromRGB(255, 245, 190), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.24, 0.24), ZIndex = 15}, 1)
-- Done: just a red "X" text label
local done = glyph("Done")
local x = Label("X", done, "X", {Size = UDim2.fromScale(1, 1), TextColor3 = RED, ZIndex = 13})
x.TextOutline.Thickness = 2
-- Sell: a Creator Store trash can; Grid: the frame-drawn box the client fills with lines
local sell = glyph("Sell")
new("ImageLabel", "Image", sell, {BackgroundTransparency = 1, BorderSizePixel = 0, Image = ICON_SELL, ImageColor3 = ICON_SELL_TINT, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(1, 1), ZIndex = 13})
local grid = glyph("Grid")
GridGlyph(grid)
-- Neutral: a plain box for categories this build does not know
local box2 = glyph("Box")
local boxA = piece(box2, {BackgroundColor3 = Color3.fromRGB(226, 230, 238), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.7, 0.7)}, 0.12)
stroke(boxA, 1.5, DARK)

--..Client..--
local client = new("LocalScript", "BuildMenuClient", nil)
client.Source = clientSource
client.Parent = gui
gui.Parent = StarterGui
print(("[build_buildmenu] StarterGui.BuildMenu rebuilt: %d descendants, client %d chars"):format(#gui:GetDescendants(), #clientSource))
