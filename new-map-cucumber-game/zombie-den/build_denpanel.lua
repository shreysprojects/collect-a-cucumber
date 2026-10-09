--[[
	build_denpanel.lua  (run in Studio EDIT mode through execute_luau; idempotent)  2026-09-24
	Builds  StarterGui.CucumberMenus.DenPanel  in the Manage / Index look: the same 1140 x 735 design frame,
	the Shadow / pink Body / red "ZOMBIE DEN" ribbon / red close X CLONED from ManagePanel.Content, one
	scrolling list of deals and a notice bar, plus Templates.DenRow = ManagePanel.Templates.CucumberRow
	grown to 150 px with a second viewport (the WANTED kind), an "x3" badge, a "have / need" line, a
	countdown and the SELL button turned into TRADE IN. Every instance is AUTHORED here; DenController
	only fills it and MenuController animates it (registered as panels.Den, no HUD opener).
]]
local StarterGui = game:GetService("StarterGui")
local gui = StarterGui:WaitForChild("CucumberMenus")
local manage = gui:WaitForChild("ManagePanel")
local manageContent = manage:WaitForChild("Content")
local manageTemplates = manage:WaitForChild("Templates")

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local OUTLINE = C(36, 25, 29)
local GOLD = C(255, 205, 60)
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
	if inst:IsA("GuiButton") then inst.AutoButtonColor = false end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		inst.Text = ""
		inst.TextColor3 = WHITE
	end
	for k, v in pairs(props or {}) do inst[k] = v end
	inst.Parent = parent
	return inst
end
local function outline(label, thickness, color)
	return make("UIStroke", "TextOutline", label, {Thickness = thickness or 2.5, Color = color or OUTLINE, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual})
end
local function text(name, parent, str, size, props)
	local l = make("TextLabel", name, parent, props)
	l.FontFace = FONT_FREDOKA
	l.TextScaled = false
	l.TextSize = size
	l.Text = str
	outline(l)
	return l
end

--------------------------------------------------------------------------------------------------
--.. the panel frame (same shape as ManagePanel: MenuController fits it by ResponsiveScale)
local panel = gui:FindFirstChild("DenPanel")
if not panel then
	panel = Instance.new("Frame")
	panel.Name = "DenPanel"
	panel.Parent = gui
end
panel.Size = off(1140, 735)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundTransparency = 1
panel.BorderSizePixel = 0
panel.ZIndex = manage.ZIndex
panel.Visible = true
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

--.. chrome cloned from the Manage panel: shadow, pink body, ribbon, close X
for _, name in ipairs({"Shadow", "Body", "Header", "CloseButton"}) do
	local clone = manageContent:WaitForChild(name):Clone()
	clone.Parent = content
end
local header = content.Header
header.Title.Text = "ZOMBIE DEN"
header.Subtitle.Text = "Lost a cucumber? Bring the zombies what they want and it comes back."

--.. list title, description, the scrolling list, the empty state, the notice bar
text("ListTitle", content, "Stolen from you  0", 33, {Size = off(900, 43), Position = off(36, 150), ZIndex = 12, TextXAlignment = Enum.TextXAlignment.Left})
text("ListDescription", content, "Each deal lasts 12h 0m. Bring 3 of what the zombies want and yours comes back.", 22, {Size = off(1040, 26), Position = off(37, 192), ZIndex = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C(255, 242, 245)})
local list = make("ScrollingFrame", "OfferList", content, {
	Size = off(1076, 392), Position = off(31, 228), ZIndex = 7,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 8,
	ScrollBarImageColor3 = C(150, 40, 40), ElasticBehavior = Enum.ElasticBehavior.Never,
})
make("UIPadding", "UIPadding", list, {PaddingLeft = UDim.new(0, 7), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 6)})
make("UIListLayout", "RowLayout", list, {Padding = UDim.new(0, 10), FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Left, SortOrder = Enum.SortOrder.LayoutOrder})
text("EmptyState", content, "The zombies have nothing of yours.", 29, {Size = off(1016, 50), Position = off(62, 380), ZIndex = 12, TextXAlignment = Enum.TextXAlignment.Center, Visible = false})
local notice = manageContent.Pages.Cucumbers.CapacityNotice:Clone()
notice.Name = "Notice"
notice.Position = off(25, 640)
notice.Visible = true
notice.Text.Text = "Place the wanted cucumbers on your base, then TRADE IN here. Daytime only."
notice.Parent = content

--------------------------------------------------------------------------------------------------
--.. the row template: the Manage cucumber row, taller, with the wanted kind beside the lost one
local templates = panel:FindFirstChild("Templates")
if not templates then
	templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = panel
end
for _, child in ipairs(templates:GetChildren()) do child:Destroy() end
local row = manageTemplates:WaitForChild("CucumberRow"):Clone()
row.Name = "DenRow"
row.Size = off(1044, 150)
row.Visible = false
for attr in pairs(row:GetAttributes()) do row:SetAttribute(attr, nil) end

local lostView = row:WaitForChild("Preview")
lostView.Name = "LostPreview"
lostView.Size = off(134, 134)
lostView.Position = off(8, 8)
text("LostCaption", row, "YOURS", 16, {Size = off(134, 20), Position = off(8, 128), ZIndex = 14, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C(255, 242, 245)})

local itemName = row:WaitForChild("ItemName")
itemName.Position = off(155, 10)
itemName.Size = off(470, 36)
itemName.Text = "Get back: Cucumber"
local itemDetail = row:WaitForChild("ItemDetail")
itemDetail.Position = off(156, 50)
itemDetail.Size = off(470, 26)
itemDetail.Text = "Spawn  -  $0/s"
text("WantLine", row, "They want 3 x Cucumber (Spawn)", 22, {Size = off(470, 28), Position = off(156, 84), ZIndex = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C(255, 226, 120)})
text("Expires", row, "Deal ends in 12h 0m", 20, {Size = off(470, 26), Position = off(156, 116), ZIndex = 12, TextXAlignment = Enum.TextXAlignment.Left})

local wantView = lostView:Clone()
wantView.Name = "WantPreview"
wantView.Size = off(126, 112)
wantView.Position = off(644, 8)
wantView.Parent = row
local badge = make("TextLabel", "WantBadge", row, {Size = off(54, 32), Position = off(724, 4), ZIndex = 16, BackgroundTransparency = 0, BackgroundColor3 = GOLD, Text = "x3", TextColor3 = WHITE, TextSize = 24, FontFace = FONT_FREDOKA})
make("UICorner", "Corners", badge, {CornerRadius = UDim.new(0, 9)})
make("UIStroke", "Border", badge, {Thickness = 2.5, Color = OUTLINE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
outline(badge, 2)
make("UIGradient", "Gradient", badge, {Rotation = 90, Color = ColorSequence.new(C(255, 230, 130), C(255, 160, 40))})
text("HaveLabel", row, "0 / 3 on your base", 19, {Size = off(150, 24), Position = off(632, 122), ZIndex = 14, TextXAlignment = Enum.TextXAlignment.Center})

local button = row:WaitForChild("SellButton")
button.Name = "TradeButton"
button.Position = off(802, 37)
button.Action.Text = "TRADE IN"
local progress = button:WaitForChild("SellValue")
progress.Name = "Progress"
progress.Text = "0 / 3"
row.Parent = templates

panel:SetAttribute("Reference", "Manage / Index look (ManagePanel chrome cloned); built by zombie-den/build_denpanel.lua; DenController fills it, MenuController animates it")
print(("[build_denpanel] DenPanel built: %d instances, row template %d"):format(#content:GetDescendants(), #row:GetDescendants()))
