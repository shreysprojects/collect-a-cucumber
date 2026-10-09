--[[
	PetInfoClient  (LocalScript, StarterPlayerScripts)  2026-09-23
	Click a pet in the world -> a small draggable PET INFO frame on the right of the screen, in the
	Manage panel's look (pink stud body, red header plate, green / blue / orange cards), showing
	everything about that pet: preview, name (white), rarity (rarity colour), owner, traits, cash/s,
	shot damage / interval / DPS / range, egg + rank, and its ability with a plain description
	(PetStats.AbilityEffect) and the chance per roll. The owner's own pets get a PUT IN INVENTORY
	button (Remotes.PetInventory Unequip -> the pet goes back to the hotbar).
	  * Pick: pets are CanQuery = false (no raycast), so a click is matched against every streamed
	    PlotPet's screen-space bounding box (nearest wins); ignored while a menu panel is open, in
	    build mode, or with a tool in hand (the bat / an egg / a pet tool has its own click).
	  * Drag: the header strip; the frame is kept on screen. Esc / X / the pet leaving closes it.
	  * Sized by a UIScale (SCALE_FOR_HEIGHT of the viewport height, 0.62 .. 1) - "smaller".
	Studio hook: ScreenGui attribute PetInfoDev = "open:<n>" (n-th PlotPet of my plot) | "close" | "putaway".
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PetsCatalog = require(Modules:WaitForChild("PetsCatalog"))
local PetStats = require(Modules:WaitForChild("PetStats"))
local PetBalance = require(Modules:WaitForChild("PetBalance"))
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))
local Notify = require(Modules:WaitForChild("Notify"))
local okMut, CucumberMutations = pcall(function() return require(Modules:WaitForChild("CucumberMutations", 5)) end)
if not okMut then CucumberMutations = nil end

local player = Players.LocalPlayer
local C = Color3.fromRGB
local TAG = "PlotPet"
local PICK_RANGE = 140 -- studs from the camera
local PICK_PAD = 6 -- px around the projected box
local SCALE_FOR_HEIGHT = 820 -- viewport height at which the frame is drawn 1:1
local PANEL_W, PANEL_H = 340, 500
local STUD = "rbxassetid://14905298636"
local HEADER_IMAGE = "rbxassetid://75227340977908"
local ABILITY_GLYPHS = {Yield = "\u{2728}", Haste = "\u{26A1}", Guard = "\u{1F6E1}\u{FE0F}", Wild = "\u{1F3B2}", None = "\u{1F525}"}
local FONT = Enum.Font.FredokaOne
local WHITE = C(255, 255, 255)
local TEXT_STROKE = C(36, 25, 29)
local ABILITIES = type(PetBalance.ABILITIES) == "table" and PetBalance.ABILITIES or {}
local TIMING = type(PetBalance.TIMING) == "table" and PetBalance.TIMING or {}
local ERRORS = {
	CombatLocked = "Finish defending your plot first.", NotOwned = "That pet is not yours.", NotLoaded = "Your data is still loading.",
	Closing = "Your data is saving - try again in a moment.", RateLimited = "Slow down a little.", Unavailable = "Pets are not available right now.",
}

--..Look helpers (the Manage panel's recipe)..--
local function Corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
	return c
end
local function Stroke(parent, color, thickness, contextual)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	if contextual then s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual end
	s.Parent = parent
	return s
end
local function Gradient(parent, top, bottom)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
	return g
end
local function Studs(parent, transparency, tile, z)
	local i = Instance.new("ImageLabel")
	i.Name = "StudTexture"
	i.BackgroundTransparency = 1
	i.Size = UDim2.fromScale(1, 1)
	i.Image = STUD
	i.ImageTransparency = transparency
	i.ScaleType = Enum.ScaleType.Tile
	i.TileSize = UDim2.fromOffset(tile, tile)
	i.ZIndex = z
	i.Parent = parent
	Corner(i, 8)
	return i
end
--.. a card in the row / stat-card style: white base, gradient, dark border, pale inner rim, studs
local function Card(name, parent, x, y, w, h, top, bottom, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = WHITE
	f.BorderSizePixel = 0
	f.ZIndex = z
	Corner(f, 12)
	Stroke(f, C(76, 64, 17), 3)
	Gradient(f, top, bottom)
	Studs(f, 0.88, 150, z + 1)
	local rim = Instance.new("Frame")
	rim.Name = "InnerRim"
	rim.Position = UDim2.fromOffset(4, 4)
	rim.Size = UDim2.new(1, -8, 1, -8)
	rim.BackgroundTransparency = 1
	rim.ZIndex = z + 1
	Corner(rim, 9)
	Stroke(rim, C(255, 252, 235), 2)
	rim.Parent = f
	f.Parent = parent
	return f
end
local function Text(name, parent, x, y, w, h, size, text, color, z, align)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.TextSize = size
	t.TextColor3 = color or WHITE
	t.Text = text or ""
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.ZIndex = z
	Stroke(t, TEXT_STROKE, 2.2, true)
	t.Parent = parent
	return t
end

local function Escape(s)
	return (tostring(s):gsub("[<>&]", {["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;"}))
end
local function Hex(color)
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end
local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
local function Money(n) return "$" .. NumberAbbrev.Abbrev(Finite(n) and n or 0) end

--..GUI..--
local gui = Instance.new("ScreenGui")
gui.Name = "PetInfoUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 55
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -20, 0.5, 0)
panel.BackgroundTransparency = 1
panel.Visible = false
panel.Parent = gui
local scale = Instance.new("UIScale")
scale.Name = "FitScale"
scale.Parent = panel

local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.Position = UDim2.fromOffset(9, 9)
shadow.Size = UDim2.fromOffset(PANEL_W - 10, PANEL_H - 14)
shadow.BackgroundColor3 = C(100, 8, 25)
shadow.BorderSizePixel = 0
shadow.ZIndex = 2
Corner(shadow, 17)
shadow.Parent = panel

local body = Instance.new("Frame")
body.Name = "Body"
body.Position = UDim2.fromOffset(5, 3)
body.Size = UDim2.fromOffset(PANEL_W - 10, PANEL_H - 14)
body.BackgroundColor3 = WHITE
body.BorderSizePixel = 0
body.Active = true -- clicks on the frame never reach the world
body.ZIndex = 3
Corner(body, 16)
Stroke(body, C(100, 8, 25), 5)
Gradient(body, C(255, 220, 225), C(255, 176, 190))
Studs(body, 0.89, 200, 4)
local pinkEdge = Instance.new("Frame")
pinkEdge.Name = "PinkEdge"
pinkEdge.Position = UDim2.fromOffset(2, 2)
pinkEdge.Size = UDim2.new(1, -4, 1, -4)
pinkEdge.BackgroundTransparency = 1
pinkEdge.ZIndex = 4
Corner(pinkEdge, 14)
Stroke(pinkEdge, C(255, 39, 92), 2)
pinkEdge.Parent = body
local innerRim = Instance.new("Frame")
innerRim.Name = "InnerRim"
innerRim.Position = UDim2.fromOffset(6, 6)
innerRim.Size = UDim2.new(1, -12, 1, -12)
innerRim.BackgroundTransparency = 1
innerRim.ZIndex = 5
Corner(innerRim, 12)
Stroke(innerRim, C(255, 251, 245), 3)
innerRim.Parent = body
body.Parent = panel

local header = Instance.new("ImageLabel")
header.Name = "Header"
header.Position = UDim2.fromOffset(14, -10)
header.Size = UDim2.fromOffset(190, 50)
header.BackgroundTransparency = 1
header.Image = HEADER_IMAGE
header.ZIndex = 12
header.Parent = panel
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(26, 3)
title.Size = UDim2.fromOffset(140, 44)
title.BackgroundTransparency = 1
title.Font = Enum.Font.BuilderSansExtraBold
title.TextScaled = true
title.TextColor3 = WHITE
title.Text = "PET INFO"
title.ZIndex = 13
Stroke(title, C(118, 0, 0), 3, true)
title.Parent = header

--.. the close X (the Manage panel's pieces at 0.58)
local close = Instance.new("ImageButton")
close.Name = "CloseButton"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, 2, 0, -8)
close.Size = UDim2.fromOffset(86, 86)
close.BackgroundTransparency = 1
close.ImageTransparency = 1
close.ZIndex = 30
local closeScale = Instance.new("UIScale")
closeScale.Scale = 0.58
closeScale.Parent = close
local function Img(name, parent, image, x, y, w, h, z, anchor)
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.BackgroundTransparency = 1
	i.Image = image
	i.Position = UDim2.fromOffset(x, y)
	i.Size = UDim2.fromOffset(w, h)
	i.ZIndex = z
	if anchor then i.AnchorPoint = anchor end
	i.Parent = parent
	return i
end
Img("Rectangle", close, "rbxassetid://102086640822931", -3, -6, 81, 85, 31)
Img("Plate", close, "rbxassetid://111663825325576", 0, 2, 72, 72, 31)
local xFrame = Instance.new("Frame")
xFrame.Name = "X"
xFrame.AnchorPoint = Vector2.new(0.5, 0.5)
xFrame.Position = UDim2.fromOffset(36, 35)
xFrame.Size = UDim2.fromOffset(40, 40)
xFrame.BackgroundTransparency = 1
xFrame.ZIndex = 32
xFrame.Parent = close
Img("X", xFrame, "rbxassetid://73973960226016", -3, -4, 46, 48, 32)
close.Parent = panel

local dragHandle = Instance.new("TextButton")
dragHandle.Name = "DragHandle"
dragHandle.Size = UDim2.new(1, -60, 0, 54)
dragHandle.BackgroundTransparency = 1
dragHandle.Text = ""
dragHandle.AutoButtonColor = false
dragHandle.ZIndex = 20
dragHandle.Parent = panel

--.. preview card + identity
local previewCard = Card("PreviewCard", panel, 18, 52, 118, 118, C(241, 255, 118), C(169, 255, 28), 6)
local viewport = Instance.new("ViewportFrame")
viewport.Name = "Preview"
viewport.Position = UDim2.fromOffset(6, 6)
viewport.Size = UDim2.new(1, -12, 1, -12)
viewport.BackgroundTransparency = 1
viewport.Ambient = C(210, 210, 210)
viewport.LightColor = WHITE
viewport.LightDirection = Vector3.new(-1, -1, -1)
viewport.ZIndex = 9
viewport.Parent = previewCard

local nameLabel = Text("PetName", panel, 146, 54, 176, 30, 24, "", WHITE, 12)
nameLabel.TextScaled = true
local nameCap = Instance.new("UITextSizeConstraint")
nameCap.MaxTextSize = 24
nameCap.MinTextSize = 12
nameCap.Parent = nameLabel
local rarityLabel = Text("Rarity", panel, 146, 86, 176, 24, 20, "", WHITE, 12)
local rarityGradient = Instance.new("UIGradient")
rarityGradient.Rotation = 90
rarityGradient.Parent = rarityLabel
local ownerLabel = Text("Owner", panel, 146, 112, 176, 20, 15, "", C(255, 242, 245), 12)
local traitsLabel = Text("Traits", panel, 146, 134, 176, 36, 15, "", WHITE, 12)
traitsLabel.RichText = true
traitsLabel.TextWrapped = true
traitsLabel.TextYAlignment = Enum.TextYAlignment.Top

--.. stats card
local statsCard = Card("StatsCard", panel, 18, 182, 304, 120, C(171, 234, 255), C(84, 190, 237), 6)
Text("Title", statsCard, 14, 6, 200, 22, 18, "STATS", WHITE, 12)
local statLines = {}
for i = 1, 4 do
	statLines[i] = Text("Line" .. i, statsCard, 14, 28 + (i - 1) * 21, 280, 20, 16, "", WHITE, 12)
end

--.. ability card
local abilityCard = Card("AbilityCard", panel, 18, 312, 304, 116, C(255, 205, 115), C(255, 141, 75), 6)
local abilityTitle = Text("Title", abilityCard, 14, 8, 276, 26, 20, "", WHITE, 12)
local abilityText = Text("Description", abilityCard, 14, 38, 276, 70, 15, "", WHITE, 12)
abilityText.TextWrapped = true
abilityText.TextScaled = true -- a long description (Wild Card lists three effects) shrinks to fit its card
abilityText.TextYAlignment = Enum.TextYAlignment.Top
local abilityCap = Instance.new("UITextSizeConstraint")
abilityCap.MaxTextSize = 15
abilityCap.MinTextSize = 9
abilityCap.Parent = abilityText

--.. the owner's action
local action = Instance.new("TextButton")
action.Name = "PutAway"
action.Position = UDim2.fromOffset(18, 438)
action.Size = UDim2.fromOffset(304, 44)
action.BackgroundColor3 = WHITE
action.BorderSizePixel = 0
action.AutoButtonColor = false
action.Text = ""
action.ZIndex = 15
Corner(action, 11)
Stroke(action, C(36, 72, 12), 3)
Gradient(action, C(155, 255, 51), C(66, 214, 5))
local actionRim = Instance.new("Frame")
actionRim.Name = "InnerRim"
actionRim.Position = UDim2.fromOffset(4, 4)
actionRim.Size = UDim2.new(1, -8, 1, -8)
actionRim.BackgroundTransparency = 1
actionRim.ZIndex = 16
Corner(actionRim, 8)
Stroke(actionRim, C(222, 255, 176), 2)
actionRim.Parent = action
local actionLabel = Text("Label", action, 4, 2, 296, 40, 22, "PUT IN INVENTORY", WHITE, 18, Enum.TextXAlignment.Center)
action.Parent = panel
local actionScale = Instance.new("UIScale")
actionScale.Name = "PopScale"
actionScale.Parent = action

--..State..--
local current = nil -- {Model, Conns}
local remote = nil
local busy = false

local function Fit()
	local camera = workspace.CurrentCamera
	local h = camera and camera.ViewportSize.Y or SCALE_FOR_HEIGHT
	scale.Scale = math.clamp(h / SCALE_FOR_HEIGHT, 0.62, 1)
end
Fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(Fit)

--..Preview..--
local function ClearPreview()
	for _, child in ipairs(viewport:GetChildren()) do child:Destroy() end
	viewport.CurrentCamera = nil
end
local function ShowPreview(key, material, mutations)
	ClearPreview()
	local ok, source = pcall(PetsCatalog.ModelOf, key)
	if not (ok and source and source:IsA("Model")) then return end
	local model = source:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then d:Destroy() end
	end
	model:SetAttribute("PrismaticLoop", true)
	if CucumberMutations and ((material and material ~= "") or (mutations and mutations ~= "")) then
		pcall(CucumberMutations.ApplyLook, model, material ~= "" and material or nil, mutations)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then d:Destroy() end
	end
	local cf, size = model:GetBoundingBox()
	model.WorldPivot = cf
	model:PivotTo(CFrame.Angles(0, math.rad(-24), 0))
	model.Name = "PreviewModel"
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = 32
	local radius = math.max(size.Magnitude * 0.5, 0.5)
	camera.CFrame = CFrame.lookAt(Vector3.new(0.35, 0.28, 1).Unit * (radius * 0.95 / math.tan(math.rad(16))), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport
end

--..Content..--
local function GuardSecondsNow()
	local day = workspace:GetAttribute("DayDurationSeconds")
	local night = workspace:GetAttribute("NightDurationSeconds")
	local ok, seconds = pcall(PetStats.GuardSeconds, Finite(day) and day or nil, Finite(night) and night or nil)
	return ok and seconds or nil
end

local function TraitsText(material, mutations)
	local words = {}
	if type(material) == "string" and material ~= "" then table.insert(words, material) end
	if type(mutations) == "string" then
		for word in mutations:gmatch("[^,%s]+") do table.insert(words, word) end
	end
	if #words == 0 then return string.format('<font color="%s">No traits</font>', Hex(C(255, 226, 232))) end
	local parts = {}
	for _, word in ipairs(words) do
		local color = CucumberMutations and CucumberMutations.ColorOf(word)
		parts[#parts + 1] = color and string.format('<font color="%s">%s</font>', Hex(color), Escape(word)) or Escape(word)
	end
	return table.concat(parts, "  ")
end

local function Render(model)
	local key = model:GetAttribute("PetName")
	local material = model:GetAttribute("Material")
	material = type(material) == "string" and material or ""
	local mutations = model:GetAttribute("Mutations")
	mutations = type(mutations) == "string" and mutations or ""
	local ok, stats = pcall(PetStats.Calculate, {Pet = key, Material = material, Mutations = mutations})
	if not ok or type(stats) ~= "table" then stats = {} end
	local display = model:GetAttribute("DisplayName") or stats.DisplayName or tostring(key)
	local rarity = model:GetAttribute("Rarity") or stats.Rarity or "Common"
	nameLabel.Text = tostring(display)
	rarityLabel.Text = tostring(rarity)
	local seq = type(PetsCatalog.RARITY_GRADIENTS) == "table" and PetsCatalog.RARITY_GRADIENTS[rarity] or nil
	rarityGradient.Color = typeof(seq) == "ColorSequence" and seq or ColorSequence.new(WHITE)
	local ownerName = model:GetAttribute("OwnerName")
	local mine = model:GetAttribute("Owner") == player.UserId
	ownerLabel.Text = mine and "Your pet" or ("Owned by " .. tostring(ownerName or "someone"))
	traitsLabel.Text = TraitsText(material, mutations)
	local rate = model:GetAttribute("Rate")
	if not Finite(rate) then rate = stats.Income or 0 end
	local damage = Finite(model:GetAttribute("ShotDamage")) and model:GetAttribute("ShotDamage") or (stats.ShotDamage or 0)
	local interval = Finite(model:GetAttribute("ShotInterval")) and model:GetAttribute("ShotInterval") or (stats.ShotInterval or 0)
	local range = Finite(model:GetAttribute("Range")) and model:GetAttribute("Range") or (stats.Range or 0)
	local dps = interval > 0 and damage / interval or (stats.DPS or 0)
	statLines[1].Text = ("Cash: %s/s"):format(Money(rate))
	statLines[2].Text = ("Damage: %s every %gs  (%s DPS)"):format(NumberAbbrev.Abbrev(damage), math.floor(interval * 100 + 0.5) / 100, NumberAbbrev.Abbrev(dps))
	statLines[3].Text = ("Range: %d studs"):format(math.floor(range + 0.5))
	local egg = stats.EggKey or "Unknown egg"
	statLines[4].Text = ("Egg: %s  -  Rank %d  -  Tier %d"):format(tostring(egg), math.floor(tonumber(stats.Rank) or 1), math.floor(tonumber(stats.EggTier) or 1))
	local kind = model:GetAttribute("Ability") or stats.Ability or "None"
	local row = ABILITIES[kind]
	local glyph = ABILITY_GLYPHS[kind] or ""
	local abilityName = type(row) == "table" and row.DisplayName or tostring(kind)
	abilityTitle.Text = glyph .. " " .. tostring(abilityName)
	abilityTitle.TextColor3 = type(row) == "table" and typeof(row.Color) == "Color3" and row.Color or WHITE
	local guard = GuardSecondsNow()
	local okEffect, effect = pcall(PetStats.AbilityEffect, kind, guard)
	effect = okEffect and type(effect) == "string" and effect or ""
	if kind == "None" then
		abilityText.Text = (effect ~= "" and effect or "Fighter") .. "\nShoots zombies harder - no ability roll."
	else
		local chance = Finite(stats.AbilityChance) and stats.AbilityChance or 0
		abilityText.Text = ("%s\n%d%% chance every %ds of active time to buff one of your cucumbers."):format(effect, math.floor(chance * 100 + 0.5), math.floor(tonumber(TIMING.ABILITY_PERIOD) or 60))
	end
	action.Visible = mine
	actionLabel.Text = busy and "..." or "PUT IN INVENTORY"
	action.Active = not busy
end

--..Open / close..--
local function Close()
	if not current then return end
	for _, c in ipairs(current.Conns) do c:Disconnect() end
	current = nil
	panel.Visible = false
	ClearPreview()
end

local function Open(model)
	if current and current.Model == model then return end
	Close()
	local entry = {Model = model, Conns = {}}
	current = entry
	Render(model)
	ShowPreview(model:GetAttribute("PetName"), model:GetAttribute("Material"), model:GetAttribute("Mutations"))
	for _, attr in ipairs({"Rate", "Mutations", "Material", "Ability"}) do
		table.insert(entry.Conns, model:GetAttributeChangedSignal(attr):Connect(function()
			if current == entry then Render(model) end
		end))
	end
	table.insert(entry.Conns, model.AncestryChanged:Connect(function()
		if current == entry and not model:IsDescendantOf(workspace) then Close() end
	end))
	panel.Visible = true
	local pop = panel:FindFirstChild("PopScale") or Instance.new("UIScale")
	pop.Name = "PopScale"
	pop.Scale = 0.92
	pop.Parent = panel
	TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
end

close.Activated:Connect(Close)

local function PutAway()
	if busy or not current or not remote then return end
	local model = current.Model
	local id = model:GetAttribute("PetId")
	if type(id) ~= "string" then return end
	busy = true
	Render(model)
	local name = model:GetAttribute("DisplayName") or model.Name
	local ok, reply = pcall(remote.InvokeServer, remote, {Action = "Unequip", PetId = id})
	busy = false
	if ok and type(reply) == "table" and reply.Ok then
		Notify.Success(("%s is back in your inventory."):format(tostring(reply.Name or name)), 2.5)
		Close()
	else
		local code = ok and type(reply) == "table" and reply.Error or "Unavailable"
		Notify.Error(ERRORS[code] or "Could not put that pet away.", 2.5)
		if current and current.Model == model then Render(model) end
	end
end
action.Activated:Connect(PutAway)
action.MouseEnter:Connect(function() TweenService:Create(actionScale, TweenInfo.new(0.12), {Scale = 1.03}):Play() end)
action.MouseLeave:Connect(function() TweenService:Create(actionScale, TweenInfo.new(0.12), {Scale = 1}):Play() end)

--..Drag..--
local dragging = nil
dragHandle.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local origin = panel.AbsolutePosition - gui.AbsolutePosition
	panel.AnchorPoint = Vector2.zero
	panel.Position = UDim2.fromOffset(origin.X, origin.Y)
	dragging = {Start = input.Position, Origin = origin, Input = input}
end)
UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local delta = input.Position - dragging.Start
	local size = panel.AbsoluteSize
	local screen = gui.AbsoluteSize
	local x = math.clamp(dragging.Origin.X + delta.X, -size.X * 0.5, screen.X - size.X * 0.5)
	local y = math.clamp(dragging.Origin.Y + delta.Y, 0, math.max(0, screen.Y - 48))
	panel.Position = UDim2.fromOffset(x, y)
end)
UserInputService.InputEnded:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then dragging = nil end
end)

--..Picking pets in the world..--
local function RootOf(model)
	local root = model.PrimaryPart
	if root and root:IsDescendantOf(model) then return root end
	root = model:FindFirstChild("Root")
	return root and root:IsA("BasePart") and root or nil
end

local function ScreenBox(camera, model)
	local cf, size = model:GetBoundingBox()
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local half = size * 0.5
	for _, sx in ipairs({-1, 1}) do
		for _, sy in ipairs({-1, 1}) do
			for _, sz in ipairs({-1, 1}) do
				local corner = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
				local p, onScreen = camera:WorldToScreenPoint(corner)
				if p.Z <= 0 then return nil end
				minX, minY = math.min(minX, p.X), math.min(minY, p.Y)
				maxX, maxY = math.max(maxX, p.X), math.max(maxY, p.Y)
			end
		end
	end
	return minX, minY, maxX, maxY
end

local function PickPet(position)
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local best, bestDepth = nil, math.huge
	for _, model in ipairs(CollectionService:GetTagged(TAG)) do
		if model:IsA("Model") and model:IsDescendantOf(workspace) then
			local root = RootOf(model)
			if root then
				local depth = (root.Position - camera.CFrame.Position).Magnitude
				if depth <= PICK_RANGE and depth < bestDepth then
					local minX, minY, maxX, maxY = ScreenBox(camera, model)
					if minX and position.X >= minX - PICK_PAD and position.X <= maxX + PICK_PAD and position.Y >= minY - PICK_PAD and position.Y <= maxY + PICK_PAD then
						best, bestDepth = model, depth
					end
				end
			end
		end
	end
	return best
end

local function Blocked()
	local pg = player:FindFirstChild("PlayerGui")
	local menus = pg and pg:FindFirstChild("CucumberMenus")
	if menus and menus:GetAttribute("OpenPanel") ~= nil and menus:GetAttribute("OpenPanel") ~= "" then return true end
	local hud = pg and pg:FindFirstChild("CucumberHUDDesign")
	if hud and hud:GetAttribute("BuildMode") == true then return true end
	local character = player.Character
	if character and character:FindFirstChildOfClass("Tool") then return true end
	return false
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Escape and current then Close() return end
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	if Blocked() then return end
	local model = PickPet(Vector2.new(input.Position.X, input.Position.Y))
	if model then Open(model) end
end)

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 60)
	local r = remotes and remotes:WaitForChild("PetInventory", 60)
	if r and r:IsA("RemoteFunction") then remote = r end
end)

--..Studio hook..--
if RunService:IsStudio() then
	gui:GetAttributeChangedSignal("PetInfoDev"):Connect(function()
		local cmd = gui:GetAttribute("PetInfoDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		gui:SetAttribute("PetInfoDev", nil)
		local kind, arg = cmd:match("^(%w+):?(.*)$")
		if kind == "close" then Close()
		elseif kind == "putaway" then task.spawn(PutAway)
		elseif kind == "open" then
			local n = tonumber(arg) or 1
			local mine = {}
			for _, model in ipairs(CollectionService:GetTagged(TAG)) do
				if model:GetAttribute("Owner") == player.UserId and model:IsDescendantOf(workspace) then table.insert(mine, model) end
			end
			table.sort(mine, function(a, b) return tostring(a:GetAttribute("PetId")) < tostring(b:GetAttribute("PetId")) end)
			if mine[n] then Open(mine[n]) end
		end
	end)
end
