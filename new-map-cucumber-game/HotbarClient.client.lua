--[[
	HotbarClient  (LocalScript, StarterPlayerScripts)
	Replaces the default Roblox backpack hotbar (CoreGui Backpack off) with the same look -- dark
	rounded slots along the bottom, number keys 1-9 / 0, the equipped slot lit up -- except that
	EGGS show as a live picture instead of their name (user 2026-09-07): a ViewportFrame of the
	tool's own Egg model (its rolled size, Golden / Diamond material and mutation colours
	included), slowly turning. Hovering a slot (tapping it on touch) opens a tooltip with the
	egg's name (material / mutation words in their colours), its weight and its mutations.
	Other tools show their TextureId image, or their name like the default backpack.
	More than MAX_HOTBAR tools: the first ten fill the hotbar, the rest sit in a grid above it that
	the "+N" chip or the backtick key toggles.
	Studio hooks (attributes on the Hotbar ScreenGui): DevPress = slot index (equip toggle),
	DevHover = slot index (show its tooltip; 0 hides).
]]
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local CucumberMutations = require(Modules:WaitForChild("CucumberMutations"))

--..Config..--
local MAX_HOTBAR = 10
local SLOT_FRACTION = 0.075 -- of the viewport height
local SLOT_MIN, SLOT_MAX = 44, 64 -- px
local GAP = 6
local BOTTOM = 10
local GRID_COLUMNS = 6
local SPIN_SPEED = math.rad(24) -- egg pictures turn this fast
local TOUCH_TOOLTIP_SECONDS = 2.5
local SLOT_COLOR = Color3.fromRGB(0, 0, 0)
local SLOT_TRANSPARENCY = 0.5
local EQUIPPED_COLOR = Color3.fromRGB(255, 255, 255)
local EQUIPPED_TRANSPARENCY = 0.25
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local TEXT_COLOR_EQUIPPED = Color3.fromRGB(25, 25, 30)
local KEY_TO_SLOT = {One = 1, Two = 2, Three = 3, Four = 4, Five = 5, Six = 6, Seven = 7, Eight = 8, Nine = 9, Zero = 10}
local VIEW_FOV = 40
local VIEW_DIRECTION = Vector3.new(0.35, 0.4, 1).Unit -- camera sits front-top-right of the egg

--..The default backpack goes away (retry: CoreGui may not accept it in the first frames)..--
task.spawn(function()
	for _ = 1, 30 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then return end
		task.wait(0.5)
	end
end)

--..Helpers..--
local function IsEgg(tool)
	return CollectionService:HasTag(tool, "EggTool") or tool:GetAttribute("EggName") ~= nil
end

--.. EggShop's FormatKg
local function FormatKg(kg)
	kg = tonumber(kg) or 0
	if kg < 10 then return ("%.1f kg"):format(kg) end
	if kg < 1000 then return ("%d kg"):format(math.floor(kg + 0.5)) end
	local k = kg / 1000
	local s = k >= 100 and ("%d"):format(math.floor(k + 0.5)) or (("%.1f"):format(k):gsub("%.0$", ""))
	return s .. "K kg"
end

local function SlotPx()
	local camera = workspace.CurrentCamera
	local height = camera and camera.ViewportSize.Y or 720
	return math.clamp(math.floor(height * SLOT_FRACTION), SLOT_MIN, SLOT_MAX)
end

--..GUI..--
local gui = Instance.new("ScreenGui")
gui.Name = "Hotbar"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -BOTTOM)
bar.AutomaticSize = Enum.AutomaticSize.X
bar.BackgroundTransparency = 1
bar.Parent = gui
local barLayout = Instance.new("UIListLayout")
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
barLayout.SortOrder = Enum.SortOrder.LayoutOrder
barLayout.Padding = UDim.new(0, GAP)
barLayout.Parent = bar

--.. "+N" chip at the end of the bar: opens the grid with the overflow tools
local chip = Instance.new("TextButton")
chip.Name = "More"
chip.LayoutOrder = 1000
chip.BackgroundColor3 = SLOT_COLOR
chip.BackgroundTransparency = SLOT_TRANSPARENCY
chip.BorderSizePixel = 0
chip.Font = Enum.Font.GothamBold
chip.TextColor3 = TEXT_COLOR
chip.TextSize = 16
chip.Text = "+0"
chip.Visible = false
chip.Parent = bar
Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 8)

local grid = Instance.new("Frame")
grid.Name = "Grid"
grid.AnchorPoint = Vector2.new(0.5, 1)
grid.AutomaticSize = Enum.AutomaticSize.XY
grid.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
grid.BackgroundTransparency = 0.2
grid.BorderSizePixel = 0
grid.Visible = false
grid.Parent = gui
Instance.new("UICorner", grid).CornerRadius = UDim.new(0, 10)
local gridPad = Instance.new("UIPadding")
gridPad.PaddingLeft, gridPad.PaddingRight, gridPad.PaddingTop, gridPad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
gridPad.Parent = grid
local gridLayout = Instance.new("UIGridLayout")
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.CellPadding = UDim2.fromOffset(GAP, GAP)
gridLayout.FillDirectionMaxCells = GRID_COLUMNS
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.Parent = grid

--.. tooltip (one, shared): name / weight / mutations / material
local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.AnchorPoint = Vector2.new(0.5, 1)
tooltip.AutomaticSize = Enum.AutomaticSize.XY
tooltip.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
tooltip.BackgroundTransparency = 0.08
tooltip.BorderSizePixel = 0
tooltip.Visible = false
tooltip.ZIndex = 20
tooltip.Parent = gui
Instance.new("UICorner", tooltip).CornerRadius = UDim.new(0, 8)
local tipStroke = Instance.new("UIStroke")
tipStroke.Color = Color3.fromRGB(70, 70, 88)
tipStroke.Thickness = 1.5
tipStroke.Parent = tooltip
local tipPad = Instance.new("UIPadding")
tipPad.PaddingLeft, tipPad.PaddingRight, tipPad.PaddingTop, tipPad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 7), UDim.new(0, 7)
tipPad.Parent = tooltip
local tipLayout = Instance.new("UIListLayout")
tipLayout.SortOrder = Enum.SortOrder.LayoutOrder
tipLayout.Padding = UDim.new(0, 2)
tipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tipLayout.Parent = tooltip
local function TipLine(name, order, size, font, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.RichText = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 21
	label.Parent = tooltip
	return label
end
local tipName = TipLine("TipName", 1, 18, Enum.Font.FredokaOne, Color3.new(1, 1, 1))
local tipWeight = TipLine("TipWeight", 2, 15, Enum.Font.GothamMedium, Color3.fromRGB(225, 225, 235))
local tipMutations = TipLine("TipMutations", 3, 15, Enum.Font.GothamMedium, Color3.fromRGB(225, 225, 235))
local tipMaterial = TipLine("TipMaterial", 4, 15, Enum.Font.GothamMedium, Color3.fromRGB(225, 225, 235))

--..State..--
local order = {} -- tools in the order they arrived (the default backpack's order)
local slots = {} -- [tool] = slot record
local spinning = {} -- [slot] = true while it has a model to turn
local backpack, character, humanoid
local hoverSlot, touchTipToken

--..Tooltip..--
local function Colored(word)
	local c = CucumberMutations.ColorOf(word)
	return c and CucumberMutations.Font(word, c, true) or word
end

local function FillTooltip(tool)
	if IsEgg(tool) then
		local display = tool:GetAttribute("DisplayName") or tool.Name
		tipName.Text = CucumberMutations.ColorizeName(display)
		tipWeight.Text = "Weight: " .. FormatKg(tool:GetAttribute("Kg"))
		tipWeight.Visible = true
		local list = CucumberMutations.Parse(tool:GetAttribute("Mutations"))
		if #list > 0 then
			local words = {}
			for _, m in ipairs(list) do words[#words + 1] = Colored(m) end
			tipMutations.Text = "Mutations: " .. table.concat(words, ", ")
		else
			tipMutations.Text = "Mutations: none"
		end
		tipMutations.Visible = true
		local material = tool:GetAttribute("Material")
		if type(material) == "string" and material ~= "" then
			tipMaterial.Text = "Material: " .. Colored(material)
			tipMaterial.Visible = true
		else
			tipMaterial.Visible = false
		end
	else
		tipName.Text = tool.Name
		local tip = tool.ToolTip
		tipWeight.Visible = tip ~= nil and tip ~= "" and tip ~= tool.Name
		tipWeight.Text = tip or ""
		tipMutations.Visible = false
		tipMaterial.Visible = false
	end
end

local function PlaceTooltip(slot)
	local frame = slot.Frame
	local origin = gui.AbsolutePosition
	local pos = frame.AbsolutePosition - origin
	tooltip.Position = UDim2.fromOffset(pos.X + frame.AbsoluteSize.X * 0.5, pos.Y - 8)
end

local function ShowTooltip(slot)
	if not slot or not slot.Tool.Parent then return end
	hoverSlot = slot
	FillTooltip(slot.Tool)
	PlaceTooltip(slot)
	tooltip.Visible = true
end

local function HideTooltip(slot)
	if slot and hoverSlot ~= slot then return end
	hoverSlot = nil
	tooltip.Visible = false
end

--..Equip..--
local function Toggle(tool)
	if not (tool and tool.Parent and humanoid and humanoid.Health > 0) then return end
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

--..Slots..--
local function FitCamera(slot)
	local model, viewport = slot.Model, slot.Viewport
	if not (model and viewport) then return end
	local _, size = model:GetBoundingBox()
	local radius = math.max(size.Magnitude * 0.5, 0.5)
	local distance = radius / math.tan(math.rad(VIEW_FOV * 0.5)) * 1.05
	local camera = slot.Camera or Instance.new("Camera")
	camera.FieldOfView = VIEW_FOV
	camera.CFrame = CFrame.lookAt(VIEW_DIRECTION * distance, Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	slot.Camera = camera
end

local function BuildPicture(slot, tool)
	local egg = tool:FindFirstChild("Egg")
	if not egg then return false end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Picture"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.new(1, -6, 1, -6)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(160, 160, 170)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.ZIndex = 2
	viewport.Parent = slot.Frame
	local model = egg:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("ParticleEmitter") or d:IsA("Light") then d:Destroy() end
	end
	local cf = model:GetBoundingBox()
	model.WorldPivot = cf
	model:PivotTo(CFrame.identity) -- centred on the origin; the camera looks at the origin
	model.Parent = viewport
	slot.Viewport = viewport
	slot.Model = model
	slot.Angle = math.random() * math.pi * 2
	FitCamera(slot)
	spinning[slot] = true
	return true
end

local function BuildText(slot, tool)
	if tool.TextureId ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "Picture"
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.new(1, -8, 1, -8)
		image.BackgroundTransparency = 1
		image.Image = tool.TextureId
		image.ScaleType = Enum.ScaleType.Fit
		image.ZIndex = 2
		image.Parent = slot.Frame
		return
	end
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -6, 1, -18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 12
	label.TextWrapped = true
	label.TextColor3 = TEXT_COLOR
	label.Text = tool.Name
	label.ZIndex = 2
	label.Parent = slot.Frame
	slot.Label = label
end

local function MakeSlot(tool)
	local px = SlotPx()
	local frame = Instance.new("Frame")
	frame.Name = "Slot"
	frame.Size = UDim2.fromOffset(px, px)
	frame.BackgroundColor3 = SLOT_COLOR
	frame.BackgroundTransparency = SLOT_TRANSPARENCY
	frame.BorderSizePixel = 0
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = frame
	local number = Instance.new("TextLabel")
	number.Name = "Number"
	number.Position = UDim2.fromOffset(6, 3)
	number.Size = UDim2.fromOffset(16, 14)
	number.BackgroundTransparency = 1
	number.Font = Enum.Font.GothamMedium
	number.TextSize = 12
	number.TextColor3 = TEXT_COLOR
	number.TextXAlignment = Enum.TextXAlignment.Left
	number.Text = ""
	number.ZIndex = 4
	number.Parent = frame
	local button = Instance.new("TextButton")
	button.Name = "Hit"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.ZIndex = 6
	button.Parent = frame
	local slot = {Tool = tool, Frame = frame, Number = number, Stroke = stroke, Conns = {}}
	if not (IsEgg(tool) and BuildPicture(slot, tool)) then BuildText(slot, tool) end
	table.insert(slot.Conns, button.Activated:Connect(function()
		Toggle(tool)
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			--.. no hover on touch: show the card for a moment after the tap
			ShowTooltip(slot)
			local token = os.clock()
			touchTipToken = token
			task.delay(TOUCH_TOOLTIP_SECONDS, function()
				if touchTipToken == token then HideTooltip(slot) end
			end)
		end
	end))
	table.insert(slot.Conns, button.MouseEnter:Connect(function() ShowTooltip(slot) end))
	table.insert(slot.Conns, button.MouseLeave:Connect(function() HideTooltip(slot) end))
	return slot
end

local function Paint(slot, equipped)
	slot.Frame.BackgroundColor3 = equipped and EQUIPPED_COLOR or SLOT_COLOR
	slot.Frame.BackgroundTransparency = equipped and EQUIPPED_TRANSPARENCY or SLOT_TRANSPARENCY
	slot.Stroke.Transparency = equipped and 0.2 or 1
	local textColor = equipped and TEXT_COLOR_EQUIPPED or TEXT_COLOR
	slot.Number.TextColor3 = textColor
	if slot.Label then slot.Label.TextColor3 = textColor end
end

local function Layout()
	local px = SlotPx()
	for i, tool in ipairs(order) do
		local slot = slots[tool]
		if slot then
			slot.Frame.Size = UDim2.fromOffset(px, px)
			slot.Frame.LayoutOrder = i
			slot.Frame.Parent = i <= MAX_HOTBAR and bar or grid
			slot.Number.Text = i <= MAX_HOTBAR and (i == 10 and "0" or tostring(i)) or ""
			Paint(slot, tool.Parent == character)
		end
	end
	local overflow = #order - MAX_HOTBAR
	chip.Size = UDim2.fromOffset(math.floor(px * 0.62), px)
	chip.Visible = overflow > 0
	chip.Text = "+" .. math.max(overflow, 0)
	if overflow <= 0 then grid.Visible = false end
	grid.Position = UDim2.new(0.5, 0, 1, -(BOTTOM + px + 10))
	gridLayout.CellSize = UDim2.fromOffset(px, px)
	bar.Size = UDim2.fromOffset(0, px)
	bar.Visible = #order > 0
	if hoverSlot then
		if hoverSlot.Tool.Parent then PlaceTooltip(hoverSlot) else HideTooltip() end
	end
end

local function Track(tool)
	if not tool:IsA("Tool") or slots[tool] then return end
	table.insert(order, tool)
	slots[tool] = MakeSlot(tool)
	Layout()
end

local function Untrack(tool)
	local slot = slots[tool]
	if not slot then return end
	slots[tool] = nil
	spinning[slot] = nil
	for _, c in ipairs(slot.Conns) do c:Disconnect() end
	if hoverSlot == slot then HideTooltip() end
	slot.Frame:Destroy()
	local index = table.find(order, tool)
	if index then table.remove(order, index) end
	Layout()
end

--.. a tool leaving the backpack may just be moving to the character (equip) and back; only a tool
--.. that ends up in neither is gone
local function OnToolLeft(tool)
	if not tool:IsA("Tool") then return end
	task.defer(function()
		if tool.Parent ~= backpack and tool.Parent ~= character then
			Untrack(tool)
		else
			Layout()
		end
	end)
end

local function Watch(container)
	if not container then return end
	for _, tool in ipairs(container:GetChildren()) do Track(tool) end
	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then Track(child) Layout() end
	end)
	container.ChildRemoved:Connect(OnToolLeft)
end

local function BindCharacter(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10)
	Watch(newCharacter)
	Layout()
end

backpack = player:WaitForChild("Backpack")
Watch(backpack)
player.CharacterAdded:Connect(BindCharacter)
if player.Character then BindCharacter(player.Character) end
--.. a respawn hands the player a fresh Backpack instance
player.ChildAdded:Connect(function(child)
	if child.Name == "Backpack" and child ~= backpack then
		backpack = child
		Watch(child)
	end
end)

--..Input..--
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if input.KeyCode == Enum.KeyCode.Backquote then
		if chip.Visible then grid.Visible = not grid.Visible end
		return
	end
	local index = KEY_TO_SLOT[input.KeyCode.Name]
	if index then Toggle(order[index]) end
end)
chip.Activated:Connect(function() grid.Visible = not grid.Visible end)

--..Egg pictures turn slowly..--
RunService.Heartbeat:Connect(function(dt)
	for slot in pairs(spinning) do
		if slot.Model and slot.Model.Parent then
			slot.Angle = (slot.Angle + dt * SPIN_SPEED) % (math.pi * 2)
			slot.Model:PivotTo(CFrame.Angles(0, slot.Angle, 0))
		else
			spinning[slot] = nil
		end
	end
end)

workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(Layout)

--..Studio hooks..--
if RunService:IsStudio() then
	gui:GetAttributeChangedSignal("DevPress"):Connect(function()
		local i = tonumber(gui:GetAttribute("DevPress"))
		if i and i > 0 then Toggle(order[i]) end
	end)
	gui:GetAttributeChangedSignal("DevHover"):Connect(function()
		local i = tonumber(gui:GetAttribute("DevHover"))
		local tool = i and order[i]
		if tool and slots[tool] then ShowTooltip(slots[tool]) else HideTooltip() end
	end)
end
