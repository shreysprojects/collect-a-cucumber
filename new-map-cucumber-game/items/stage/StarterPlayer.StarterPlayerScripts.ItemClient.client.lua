--[[
	ItemClient  (LocalScript, StarterPlayerScripts)  2026-09-23
	Client half of the drop items (ItemService / RS.Modules.ItemsCatalog):
	  * USING: every item tool in the hotbar (attribute ItemTool) fires Remotes.ItemUse on Tool.Activated
	    (equip it with its hotbar slot / number key, then click). Throwables send the aim direction (the
	    mouse hit from the character, the camera look on touch / gamepad). Potions tip the bottle in hand.
	  * BOOST CHIPS: PlayerGui.ItemBoosts - one pill per running boost ("⚡ 2x Speed  1:29") in a row
	    under the HUD's Cash / Strength counters (CucumberHUDDesign.Counters), read from the player
	    attributes SpeedBoostUntil / StrengthBoostUntil / CashBoostUntil (server time).
	  * DROPS: every workspace.ItemDrops model (tag ItemDrop) bobs and turns on this client (anchored parts,
	    local PivotTo only) under a name label coloured by rarity.
	  * EVENTS: Remotes.ItemEvent -> toasts through RS.Modules.Notify + small poofs (pickup, warp ends,
	    holy splash, a sprouting seed, a returned cucumber, a hatched pet).
	Studio hook: ItemBoosts attribute ItemClientDev = "use:<n>" (click the n-th item tool's use).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Catalog = require(Modules:WaitForChild("ItemsCatalog"))
local Notify = require(Modules:WaitForChild("Notify"))
local okSound, SoundController = pcall(function() return require(Modules:WaitForChild("SoundController", 5)) end)
if not okSound then SoundController = nil end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UseRemote = Remotes:WaitForChild("ItemUse", 60)
local Event = Remotes:WaitForChild("ItemEvent", 60)
if not (UseRemote and Event) then
	warn("[ItemClient] Remotes.ItemUse / ItemEvent missing - is ItemService installed?")
	return
end

local DROP_TAG = "ItemDrop"
local CHIP_TICK = 0.2

local function PlayAt(name, position, volume)
	if not SoundController then return end
	pcall(SoundController.PlayFXAt, name, position, {Volume = volume or 0.8, RollOff = 60})
end

--..Poof: a one-shot burst of coloured sparks at a point..--
local function Poof(position, color, count, size)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.7
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size or 0.5), NumberSequenceKeypoint.new(1, 0)})
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = part
	part.Parent = workspace
	emitter:Emit(count or 18)
	task.delay(1.2, function() part:Destroy() end)
end

--..Using tools..--
local character, humanoid
local watched = setmetatable({}, {__mode = "k"})
local busyUntil = 0

local function AimDirection()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if UserInputService.MouseEnabled and root then
		local mouse = player:GetMouse()
		local target = mouse.Hit and mouse.Hit.Position
		if target then
			local dir = target - root.Position
			if dir.Magnitude > 1 then return dir.Unit end
		end
	end
	return camera and camera.CFrame.LookVector or Vector3.zAxis
end

local function TipBottle(tool)
	local base = tool.Grip
	local up = base * CFrame.Angles(math.rad(-75), 0, 0)
	local t1 = TweenService:Create(tool, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Grip = up})
	t1:Play()
	t1.Completed:Connect(function()
		task.wait(0.35)
		if tool.Parent then TweenService:Create(tool, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Grip = base}):Play() end
	end)
end

--..Warp aiming (Kind "Aim", 2026-09-23, user: "anywhere you hover has an arched line trail from you to that spot")..--
--.. While an Aim tool is in hand, every frame a ray through the mouse (the camera look on touch / gamepad) finds the
--.. spot; a purple arched Beam runs from the player's chest to it and a glowing ring lies on it. Click = warp there.
local WARP = Catalog.WARP or {ArcMin = 6, ArcMax = 40, ArcFactor = 0.3, RingDiameter = 4, MaxRange = 1500}
local aim = nil -- {Tool, Folder, From, To, Beam, Ring, Target, Valid, Conn}
--.. the playable ground (biome floors + the lobby box, inset) published by ItemService as Remotes.WarpBounds JSON;
--.. a hovered spot outside it shows a red ring and the click is refused here (the server refuses too)
local WarpRects = {}
local function ReadWarpBounds()
	local raw = Remotes:GetAttribute("WarpBounds")
	if type(raw) ~= "string" or raw == "" then WarpRects = {} return end
	local ok, list = pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
	WarpRects = (ok and type(list) == "table") and list or {}
end
ReadWarpBounds()
Remotes:GetAttributeChangedSignal("WarpBounds"):Connect(ReadWarpBounds)
local BOUNDS_HEIGHT = 12
local function InsideWarpBounds(position)
	if #WarpRects == 0 then return true end -- not published (yet): let the server decide
	for _, r in ipairs(WarpRects) do
		if position.X >= r.MinX and position.X <= r.MaxX and position.Z >= r.MinZ and position.Z <= r.MaxZ and position.Y <= (r.TopY or math.huge) + BOUNDS_HEIGHT then
			return true
		end
	end
	return false
end
local function AimRayHit()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local ray
	if UserInputService.MouseEnabled or UserInputService.TouchEnabled then
		local at = UserInputService:GetMouseLocation()
		ray = camera:ScreenPointToRay(at.X, at.Y)
	else
		ray = Ray.new(camera.CFrame.Position, camera.CFrame.LookVector)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {workspace:FindFirstChild("ItemDrops")}
	if character then table.insert(exclude, character) end
	if aim and aim.Folder then table.insert(exclude, aim.Folder) end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(ray.Origin, ray.Direction.Unit * 1200, params)
	return hit and hit.Position or nil
end

local function StopAim()
	if not aim then return end
	if aim.Conn then aim.Conn:Disconnect() end
	if aim.Folder then aim.Folder:Destroy() end
	aim = nil
end

local function StartAim(tool)
	StopAim()
	local def = Catalog.Get(tool:GetAttribute("ItemKey"))
	local color = def and def.Color or Color3.fromRGB(170, 100, 255)
	local folder = Instance.new("Folder")
	folder.Name = "WarpAim"
	local function marker(name)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = folder
		local att = Instance.new("Attachment")
		att.CFrame = CFrame.Angles(0, 0, math.rad(90)) -- the Beam's control points run along the attachment X axis: up
		att.Parent = part
		return part, att
	end
	local fromPart, fromAtt = marker("From")
	local toPart, toAtt = marker("To")
	local beam = Instance.new("Beam")
	beam.Attachment0 = fromAtt
	beam.Attachment1 = toAtt
	beam.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 200, 255)), ColorSequenceKeypoint.new(1, color)})
	beam.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 0.25)})
	beam.Width0 = 0.35
	beam.Width1 = 0.6
	beam.Segments = 36
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Enabled = false
	beam.Parent = fromPart
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, WARP.RingDiameter, WARP.RingDiameter)
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.4
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Parent = folder
	local dot = Instance.new("Part")
	dot.Name = "Dot"
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.new(0.9, 0.9, 0.9)
	dot.Color = Color3.fromRGB(235, 200, 255)
	dot.Material = Enum.Material.Neon
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.Parent = folder
	folder.Parent = workspace
	aim = {Tool = tool, Folder = folder, From = fromPart, To = toPart, Beam = beam, Ring = ring, Dot = dot, Target = nil}
	aim.Conn = RunService.RenderStepped:Connect(function()
		if not (aim and aim.Tool == tool and tool.Parent == character) then StopAim() return end
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local target = root and AimRayHit() or nil
		if target and root then
			local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
			if flat.Magnitude > WARP.MaxRange then target = nil end
		end
		aim.Target = target
		if not (target and root) then
			beam.Enabled = false
			ring.Transparency = 1
			dot.Transparency = 1
			aim.Valid = false
			return
		end
		local valid = InsideWarpBounds(target)
		aim.Valid = valid
		local chest = root.Position + Vector3.new(0, 0.8, 0)
		fromPart.CFrame = CFrame.new(chest)
		toPart.CFrame = CFrame.new(target + Vector3.new(0, 0.4, 0))
		local arc = math.clamp((target - chest).Magnitude * WARP.ArcFactor, WARP.ArcMin, WARP.ArcMax)
		beam.CurveSize0 = arc
		beam.CurveSize1 = arc
		beam.Enabled = valid
		local pulse = 0.85 + 0.15 * math.sin(os.clock() * 5)
		ring.Size = Vector3.new(0.2, WARP.RingDiameter * pulse, WARP.RingDiameter * pulse)
		ring.CFrame = CFrame.new(target + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)) -- a flat disc
		ring.Color = valid and color or Color3.fromRGB(255, 70, 70) -- red = outside the map / on a wall
		ring.Transparency = valid and 0.4 or 0.3
		dot.CFrame = CFrame.new(target + Vector3.new(0, 0.6 + 0.2 * math.sin(os.clock() * 4), 0))
		dot.Transparency = valid and 0 or 1
	end)
end

local function Use(tool)
	local key = tool:GetAttribute("ItemKey")
	local def = Catalog.Get(key)
	if not def then return end
	local now = os.clock()
	if now < busyUntil then return end
	busyUntil = now + Catalog.USE_COOLDOWN
	local request = {Key = key}
	if def.Kind == "Throw" then request.Direction = AimDirection() end
	if def.Kind == "Aim" then
		local target = (aim and aim.Tool == tool and aim.Target) or AimRayHit()
		if not target then
			Notify.Warn("Point at a spot to warp there.", 1.6)
			return
		end
		if not InsideWarpBounds(target) then
			Notify.Warn("Pick a spot on the ground inside the map.", 1.8)
			busyUntil = 0
			return
		end
		request.Target = target
	end
	if def.Kind == "Drink" then TipBottle(tool) end
	local ok, result = pcall(UseRemote.InvokeServer, UseRemote, request)
	if not ok then
		Notify.Error("Couldn't use that right now.")
		return
	end
	if type(result) ~= "table" or result.Ok then return end -- the server's events carry the feedback
	if result.Error == "Cooldown" then return end
	Notify.Warn(result.Message or "Can't use that right now.")
end

local function Watch(tool)
	if not (tool:IsA("Tool") and tool:GetAttribute("ItemTool") == true) or watched[tool] then return end
	watched[tool] = true
	tool.Activated:Connect(function() Use(tool) end)
	--.. an Aim tool (the Warp Pearl) shows its trail while it is in hand
	tool.Equipped:Connect(function()
		if tool:GetAttribute("Kind") == "Aim" then StartAim(tool) end
	end)
	tool.Unequipped:Connect(function()
		if aim and aim.Tool == tool then StopAim() end
	end)
	tool.Destroying:Connect(function()
		if aim and aim.Tool == tool then StopAim() end
	end)
	if tool.Parent == character and tool:GetAttribute("Kind") == "Aim" then StartAim(tool) end
end

local function WatchContainer(container)
	if not container then return end
	for _, tool in ipairs(container:GetChildren()) do Watch(tool) end
	container.ChildAdded:Connect(Watch)
end

local function BindCharacter(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10)
	WatchContainer(newCharacter)
end
WatchContainer(player:WaitForChild("Backpack"))
player.CharacterAdded:Connect(BindCharacter)
if player.Character then BindCharacter(player.Character) end

--..Boost chips..--
local gui = Instance.new("ScreenGui")
gui.Name = "ItemBoosts"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.IgnoreGuiInset = false
gui.Parent = playerGui

local row = Instance.new("Frame")
row.Name = "Row"
row.AnchorPoint = Vector2.new(0.5, 0)
row.Position = UDim2.new(0.5, 0, 0, 96)
row.AutomaticSize = Enum.AutomaticSize.XY
row.BackgroundTransparency = 1
row.Visible = false
row.Parent = gui
local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding = UDim.new(0, 6)
rowLayout.Parent = row

local chips = {}
for i, boost in ipairs(Catalog.BOOST_ORDER) do
	local info = Catalog.BOOSTS[boost]
	local chip = Instance.new("Frame")
	chip.Name = boost
	chip.LayoutOrder = i
	chip.AutomaticSize = Enum.AutomaticSize.XY
	chip.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	chip.BackgroundTransparency = 0.2
	chip.BorderSizePixel = 0
	chip.Visible = false
	chip.Parent = row
	Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 9)
	local stroke = Instance.new("UIStroke")
	stroke.Color = info.Color
	stroke.Thickness = 1.6
	stroke.Transparency = 0.15
	stroke.Parent = chip
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = chip
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 17
	label.TextColor3 = info.Color
	label.Text = ""
	label.Parent = chip
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(12, 12, 12)
	textStroke.Thickness = 1.2
	textStroke.Parent = label
	chips[boost] = {Frame = chip, Label = label, Info = info}
end

local function LayoutRow()
	local hud = playerGui:FindFirstChild("CucumberHUDDesign")
	local counters = hud and hud:FindFirstChild("Counters")
	if counters and counters:IsA("GuiObject") and counters.AbsoluteSize.Y > 0 and counters.Visible then
		local x = counters.AbsolutePosition.X - gui.AbsolutePosition.X + counters.AbsoluteSize.X * 0.5
		local y = counters.AbsolutePosition.Y - gui.AbsolutePosition.Y + counters.AbsoluteSize.Y + 6
		row.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	else
		row.Position = UDim2.new(0.5, 0, 0, 96)
	end
end

task.spawn(function()
	while true do
		local now = workspace:GetServerTimeNow()
		local any = false
		for boost, chip in pairs(chips) do
			local untilTime = tonumber(player:GetAttribute(chip.Info.Attr))
			local left = untilTime and untilTime - now or 0
			if left > 0 then
				any = true
				chip.Label.Text = ("%s %dx %s  %s"):format(chip.Info.Emoji, chip.Info.Mult, chip.Info.Label, Catalog.FormatTime(left))
				chip.Frame.Visible = true
			else
				chip.Frame.Visible = false
			end
		end
		if any then LayoutRow() end
		row.Visible = any
		task.wait(CHIP_TICK)
	end
end)

--..Drops: bob + turn + label..--
local drops = {} -- [model] = {Base = CFrame, Phase = number, Label = BillboardGui}
local function AddDrop(model)
	if drops[model] or not model:IsA("Model") then return end
	local part = model:FindFirstChildWhichIsA("BasePart")
	if not part then return end
	local rarity = tostring(model:GetAttribute("Rarity") or "Common")
	local color = Catalog.RarityColor(rarity)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DropLabel"
	billboard.Adornee = part
	billboard.Size = UDim2.new(6, 0, 1.5, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.7, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.Size = UDim2.fromScale(1, 0.62)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = color
	name.Text = tostring(model:GetAttribute("DisplayName") or model.Name)
	name.Parent = billboard
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(12, 12, 12)
	nameStroke.Thickness = 2
	nameStroke.Parent = name
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Position = UDim2.fromScale(0, 0.62)
	hint.Size = UDim2.fromScale(1, 0.38)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.TextColor3 = Color3.fromRGB(235, 235, 240)
	hint.Text = rarity .. " - walk over it"
	hint.Parent = billboard
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Color = Color3.fromRGB(12, 12, 12)
	hintStroke.Thickness = 1.5
	hintStroke.Parent = hint
	billboard.Parent = part
	drops[model] = {Base = model:GetPivot(), Phase = math.random() * math.pi * 2, Label = billboard}
end
for _, model in ipairs(CollectionService:GetTagged(DROP_TAG)) do AddDrop(model) end
CollectionService:GetInstanceAddedSignal(DROP_TAG):Connect(AddDrop)
CollectionService:GetInstanceRemovedSignal(DROP_TAG):Connect(function(model) drops[model] = nil end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for model, info in pairs(drops) do
		if not model.Parent then
			drops[model] = nil
		else
			local lift = 0.25 + math.sin(t * 2.4 + info.Phase) * 0.18
			model:PivotTo(info.Base * CFrame.new(0, lift, 0) * CFrame.Angles(0, (t * 1.3 + info.Phase) % (math.pi * 2), 0))
		end
	end
end)

--..Events from the server..--
local function Mine(p) return p.Player == player end
local HANDLERS = {
	Toast = function(p)
		local fn = Notify[p.Style] or Notify.Info
		fn(tostring(p.Text or ""), p.Seconds)
	end,
	Picked = function(p)
		local def = Catalog.Get(p.Key)
		Notify.Success(("+1 %s  (x%d)"):format(p.Name or (def and def.Name) or "item", tonumber(p.Count) or 1), 1.8)
	end,
	PickedFX = function(p)
		local def = Catalog.Get(p.Key)
		if typeof(p.Position) == "Vector3" then Poof(p.Position, def and def.Color or Color3.new(1, 1, 1), 14, 0.4) end
	end,
	Drink = function(p)
		if typeof(p.Position) == "Vector3" then PlayAt("Bottle Pop", p.Position, 0.9) end
		if not Mine(p) then return end
		local info = Catalog.BOOSTS[p.Boost]
		local left = (tonumber(p.Until) or 0) - workspace:GetServerTimeNow()
		if info then Notify.Show(("%s %dx %s for %s!"):format(info.Emoji, info.Mult, info.Label, Catalog.FormatTime(left)), info.Color, 2.2) end
	end,
	Warp = function(p)
		local def = Catalog.Get("WarpPearl")
		local color = def and def.Color or Color3.fromRGB(170, 100, 255)
		if typeof(p.From) == "Vector3" then Poof(p.From, color, 22, 0.6) end
		if typeof(p.To) == "Vector3" then Poof(p.To, color, 26, 0.6) end
	end,
	Splash = function(p)
		local def = Catalog.Get("HolyWater")
		if typeof(p.Position) == "Vector3" then Poof(p.Position, def and def.Color or Color3.new(1, 1, 1), 40, 0.9) end
		if not Mine(p) then return end
		local hits = tonumber(p.Hits) or 0
		if hits > 0 then
			Notify.Success(("Holy Water burned %d zombie%s!"):format(hits, hits == 1 and "" or "s"), 2)
		else
			Notify.Info("The Holy Water hit no zombies.", 1.6)
		end
	end,
	Planted = function(p)
		local color = p.Void and Color3.fromRGB(170, 100, 255) or Color3.fromRGB(255, 205, 60)
		if typeof(p.Position) == "Vector3" then Poof(p.Position, color, 28, 0.6) end
		if Mine(p) then Notify.Success(("%s sprouted at your feet - collect it!"):format(p.Name or "A cucumber"), 3) end
	end,
	Redeemed = function(p)
		if typeof(p.Position) == "Vector3" then Poof(p.Position, Color3.fromRGB(255, 205, 60), 28, 0.6) end
		if Mine(p) then Notify.Success(("Your %s is back - collect it!"):format(p.Name or "cucumber"), 3) end
	end,
	Hatched = function(p)
		if not Mine(p) then return end
		if p.Secret then
			Notify.Success("GREGORY?! The secret pet crawled out of the Zombie Egg!", 4)
		else
			Notify.Success(("A SHADOW %s (%s) hatched from the Zombie Egg!"):format(p.Name or "pet", p.Rarity or "Common"), 3.5)
		end
		if not p.Equipped then task.delay(1.2, function() Notify.Info("It's waiting in your inventory.", 2) end) end
	end,
}
Event.OnClientEvent:Connect(function(p)
	if type(p) ~= "table" then return end
	local handler = HANDLERS[p.Kind]
	if handler then
		local ok, err = pcall(handler, p)
		if not ok then warn("[ItemClient] " .. tostring(p.Kind) .. ": " .. tostring(err)) end
	end
end)

--..Studio hook..--
if RunService:IsStudio() then
	gui:GetAttributeChangedSignal("ItemClientDev"):Connect(function()
		local cmd = gui:GetAttribute("ItemClientDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		gui:SetAttribute("ItemClientDev", nil)
		local n = tonumber(cmd:match("^use:(%d+)$"))
		if not n then return end
		local tools = {}
		for _, container in ipairs({player:FindFirstChild("Backpack"), character}) do
			if container then
				for _, tool in ipairs(container:GetChildren()) do
					if tool:IsA("Tool") and tool:GetAttribute("ItemTool") == true then table.insert(tools, tool) end
				end
			end
		end
		local tool = tools[n]
		if tool then
			if humanoid and tool.Parent ~= character then humanoid:EquipTool(tool) task.wait(0.2) end
			Use(tool)
		end
	end)
end

print("[ItemClient] ready")
