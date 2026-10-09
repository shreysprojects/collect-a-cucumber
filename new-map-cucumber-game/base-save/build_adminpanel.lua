-- build_adminpanel.lua: edit-mode builder for StarterGui.AdminPanel (run by base-save/install.lua, which passes
-- the AdminPanelClient source as the chunk argument). Rebuilt from scratch every run. The buttons wear the HUD
-- LeftMenu look (build_buildmenu.lua's Shell: dark rounded frame, gradient fill, stud texture, inner highlight,
-- BuilderSans ExtraBold label with a dark outline, a transparent TextButton "Press" on top).
-- Layout (top-right of the screen, one UIScale on Root): Toggle ("ADMIN") over Panel: Title / Close,
-- DayButton NightButton, CashLabel CashBox CashSet, StrengthLabel StrengthBox StrengthSet, ResetButton, Status.
local clientSource = ...
local StarterGui = game:GetService("StarterGui")

local DARK = Color3.fromRGB(12, 12, 12)
local PANEL = Color3.fromRGB(22, 23, 30)
local RIM = Color3.fromRGB(70, 74, 92)
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(235, 35, 35)
local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local FONT_MEDIUM = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold)
local STUDS = "rbxassetid://14905298636"
local GREEN_TOP, GREEN_BOTTOM, GREEN_HIGHLIGHT = Color3.fromRGB(157, 255, 36), Color3.fromRGB(69, 255, 0), Color3.fromRGB(208, 255, 106)
local NIGHT_TOP, NIGHT_BOTTOM, NIGHT_HIGHLIGHT = Color3.fromRGB(120, 140, 255), Color3.fromRGB(55, 70, 200), Color3.fromRGB(180, 195, 255)
local RED_TOP, RED_BOTTOM, RED_HIGHLIGHT = Color3.fromRGB(255, 100, 100), Color3.fromRGB(230, 30, 30), Color3.fromRGB(255, 196, 196)
local GOLD_TOP, GOLD_BOTTOM, GOLD_HIGHLIGHT = Color3.fromRGB(255, 220, 90), Color3.fromRGB(240, 170, 20), Color3.fromRGB(255, 240, 170)

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

--.. HUD-style button shell (see build_buildmenu.lua)
local function Shell(name, parent, width, height)
	local b = frame(name, parent, {BackgroundColor3 = DARK, Size = UDim2.fromOffset(width or 122, height or 47), ZIndex = 4})
	corner(b, 4)
	stroke(b, 2, DARK)
	local fill = frame("Fill", b, {BackgroundColor3 = WHITE, Position = UDim2.fromScale(0.018, 0.045), Size = UDim2.fromScale(0.964, 0.91), ZIndex = 5})
	corner(fill, 2)
	new("UIGradient", "ColorGradient", fill, {Rotation = 90, Color = ColorSequence.new(GREEN_TOP, GREEN_BOTTOM)})
	new("ImageLabel", "StudTexture", fill, {BackgroundTransparency = 1, BorderSizePixel = 0, Image = STUDS, ImageTransparency = 0.4,
		ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(112, 112), Size = UDim2.fromScale(1, 1), ZIndex = 6})
	local highlight = frame("InnerHighlight", fill, {BackgroundTransparency = 1, Position = UDim2.fromScale(0.017, 0.045), Size = UDim2.fromScale(0.966, 0.91), ZIndex = 7})
	corner(highlight, 2)
	stroke(highlight, 1.5, GREEN_HIGHLIGHT)
	return b
end
local function Paint(shell, top, bottom, highlight)
	shell.Fill.ColorGradient.Color = ColorSequence.new(top, bottom)
	shell.Fill.InnerHighlight.Outline.Color = highlight
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
local function ActionButton(name, parent, text, x, y, w, h, cap)
	local b = Shell(name, parent, w, h)
	b.Position = UDim2.fromOffset(x, y)
	Label("Label", b, text, {Position = UDim2.fromScale(0.06, 0.14), Size = UDim2.fromScale(0.88, 0.72)})
	TextSizeCap(b.Label, cap or 24)
	Press(b)
	return b
end
local function FieldLabel(name, parent, text, x, y, w, h)
	local l = Label(name, parent, text, {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), TextXAlignment = Enum.TextXAlignment.Left})
	TextSizeCap(l, 22)
	return l
end
local function Box(name, parent, x, y, w, h)
	local b = new("TextBox", name, parent, {BackgroundColor3 = Color3.fromRGB(34, 36, 46), BorderSizePixel = 0, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		FontFace = FONT_MEDIUM, Text = "", PlaceholderText = "0", PlaceholderColor3 = Color3.fromRGB(120, 124, 140), TextColor3 = WHITE, TextScaled = true,
		ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5})
	corner(b, 6)
	stroke(b, 2, RIM)
	TextSizeCap(b, 22)
	new("UIPadding", "Pad", b, {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)})
	return b
end

local old = StarterGui:FindFirstChild("AdminPanel")
if old then old:Destroy() end
local gui = new("ScreenGui", "AdminPanel", nil, {ResetOnSpawn = false, DisplayOrder = 40, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})

--.. everything hangs off one top-right Root so a single UIScale scales it about that corner
local root = frame("Root", gui, {BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(360, 400)})
new("UIScale", "Fit", root, {Scale = 1})

local toggle = Shell("Toggle", root, 104, 40)
toggle.AnchorPoint = Vector2.new(1, 0)
toggle.Position = UDim2.new(1, 0, 0, 0)
Label("Label", toggle, "ADMIN", {Position = UDim2.fromScale(0.08, 0.14), Size = UDim2.fromScale(0.84, 0.72)})
TextSizeCap(toggle.Label, 22)
Press(toggle)

local panel = frame("Panel", root, {BackgroundColor3 = PANEL, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 50), Size = UDim2.fromOffset(344, 336), Visible = false, ZIndex = 2})
corner(panel, 8)
stroke(panel, 2, RIM)
Label("Title", panel, "ADMIN PANEL", {Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(280, 30), TextXAlignment = Enum.TextXAlignment.Left})
TextSizeCap(panel.Title, 24)
local close = frame("Close", panel, {BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(30, 30), ZIndex = 3})
Label("Label", close, "X", {Size = UDim2.fromScale(1, 1), TextColor3 = RED})
close.Label.TextOutline.Thickness = 2
TextSizeCap(close.Label, 24)
Press(close)

--.. day / night
ActionButton("DayButton", panel, "START DAY", 14, 52, 154, 44)
local night = ActionButton("NightButton", panel, "START NIGHT", 176, 52, 154, 44)
Paint(night, NIGHT_TOP, NIGHT_BOTTOM, NIGHT_HIGHLIGHT)

--.. cash / strength
FieldLabel("CashLabel", panel, "CASH", 14, 112, 96, 40)
Box("CashBox", panel, 110, 112, 138, 40)
local cashSet = ActionButton("CashSet", panel, "SET", 256, 112, 74, 40, 22)
Paint(cashSet, GOLD_TOP, GOLD_BOTTOM, GOLD_HIGHLIGHT)
FieldLabel("StrengthLabel", panel, "STRENGTH", 14, 162, 96, 40)
Box("StrengthBox", panel, 110, 162, 138, 40)
local strengthSet = ActionButton("StrengthSet", panel, "SET", 256, 162, 74, 40, 22)
Paint(strengthSet, GOLD_TOP, GOLD_BOTTOM, GOLD_HIGHLIGHT)

--.. reset
local reset = ActionButton("ResetButton", panel, "RESET DATA", 14, 220, 316, 44)
Paint(reset, RED_TOP, RED_BOTTOM, RED_HIGHLIGHT)

--.. the last answer from the server
local status = new("TextLabel", "Status", panel, {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 274), Size = UDim2.fromOffset(316, 48),
	FontFace = FONT_MEDIUM, Text = "", TextColor3 = Color3.fromRGB(200, 205, 220), TextScaled = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 10})
TextSizeCap(status, 16)

local client = new("LocalScript", "AdminPanelClient", gui)
client.Source = clientSource
gui.Parent = StarterGui
print(("[build_adminpanel] StarterGui.AdminPanel rebuilt: %d descendants, client %d chars"):format(#gui:GetDescendants(), #clientSource))
