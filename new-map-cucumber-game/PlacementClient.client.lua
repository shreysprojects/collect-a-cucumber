--[[
	PlacementClient  (LocalScript, StarterPlayerScripts)
	Client half of the egg placement system. While an egg Tool (tag "EggTool")
	is equipped AND the player is standing at their own plot, a see-through
	preview of that egg sits under the mouse on the plot (snapped to GRID_SIZE,
	clamped so it never leaves the plot). Away from the plot nothing is shown.
	If the spot overlaps something already placed the preview is covered in red;
	otherwise it looks normal. Click / tap to place; R rotates by ROTATION_STEP.
	The server (EggPlacement) re-validates everything and consumes the tool.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

--..Config..--
local GRID_SIZE = 1 -- studs; 0 = free placement
local ROTATION_STEP = 90 -- degrees per R press
local PREVIEW_TRANSPARENCY = 0.5
local OCCUPIED_COLOR = Color3.fromRGB(255, 40, 40)
local COLLISION_SHRINK = 0.96 -- keep in step with EggPlacement
local AT_BASE_MARGIN = 6 -- studs outside the plot edge that still count as "at the base" (keep in step with EggPlacement)

--..Variables..--
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestPlacement = Remotes:WaitForChild("requestPlacement")
local Models = ReplicatedStorage:WaitForChild("PlaceableModels")
local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
local CucumberMutations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CucumberMutations")) -- the egg's material / mutation look on the preview

local active = nil -- {Tool, Plot, Preview, Hitbox, Highlight, Yaw, TargetCF, Valid, Connections}

--..Functions..--
local function MyPlot()
	for _, plot in ipairs(Plots:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function Snap(v)
	if GRID_SIZE <= 0 then return v end
	return math.round(v / GRID_SIZE) * GRID_SIZE
end

local function Footprint(size, yaw)
	local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
	return c * size.X + s * size.Z, s * size.X + c * size.Z
end

local function AtBase(plot)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local rp = plot.CFrame:PointToObjectSpace(root.Position)
	return math.abs(rp.X) <= plot.Size.X * 0.5 + AT_BASE_MARGIN
		and math.abs(rp.Z) <= plot.Size.Z * 0.5 + AT_BASE_MARGIN
		and rp.Y > -10 and rp.Y < 60
end

local function Deactivate()
	if not active then return end
	for _, c in ipairs(active.Connections) do c:Disconnect() end
	if active.Preview then active.Preview:Destroy() end
	active = nil
end

local function Update()
	local state = active
	if not state then return end
	local plot, hitbox = state.Plot, state.Hitbox
	if not plot.Parent then Deactivate() return end

	--.. only while standing at the base; elsewhere the preview is hidden and nothing can be placed
	if not AtBase(plot) then
		if state.Preview.Parent then state.Preview.Parent = nil end
		state.Valid = false
		return
	elseif not state.Preview.Parent then
		state.Preview.Parent = workspace
	end

	--.. aim with the mouse's own ray (always under the cursor); hit the plot directly,
	--.. otherwise meet the plot's top plane
	local ray = mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {plot}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	--.. the Include filter takes the plot's DESCENDANTS too, and placed cucumbers now carry a
	--.. full-size PlotHitbox with CanQuery on (2026-09-08): only the plot slab itself aims the egg
	if hit and hit.Instance ~= plot then hit = nil end
	local target
	if hit then
		target = hit.Position
	else
		local planeY = plot.Position.Y + plot.Size.Y * 0.5
		local t = (planeY - ray.Origin.Y) / ray.Direction.Y
		target = (t > 0 and t < 2000) and (ray.Origin + ray.Direction * t) or plot.Position
	end

	--.. snap + clamp inside the plot, in the plot's own space
	local size = hitbox.Size
	local yaw = math.rad(state.Yaw)
	local fx, fz = Footprint(size, yaw)
	local lp = plot.CFrame:PointToObjectSpace(target)
	local x = math.clamp(Snap(lp.X), -plot.Size.X * 0.5 + fx * 0.5, plot.Size.X * 0.5 - fx * 0.5)
	local z = math.clamp(Snap(lp.Z), -plot.Size.Z * 0.5 + fz * 0.5, plot.Size.Z * 0.5 - fz * 0.5)
	local targetCF = plot.CFrame * CFrame.new(x, plot.Size.Y * 0.5 + size.Y * 0.5, z) * CFrame.Angles(0, yaw, 0)
	state.TargetCF = targetCF
	state.Preview:PivotTo(targetCF) -- no smoothing: the egg sits exactly where the cursor is

	--.. occupied? (same test the server runs)
	local holder = plot:FindFirstChild("Placed")
	local occupied = false
	if holder then
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {holder}
		occupied = #workspace:GetPartBoundsInBox(targetCF, size * COLLISION_SHRINK, overlap) > 0
	end
	state.Valid = not occupied
	state.Highlight.Enabled = occupied
end

local function TryPlace()
	local state = active
	if not state or not state.Valid or not state.TargetCF or not state.Preview.Parent then return end
	local tool = state.Tool
	local ok = requestPlacement:InvokeServer(tool, state.TargetCF)
	if not ok and active == state then
		state.Highlight.Enabled = true -- flash red on a rejection, next Update() restores it
	end
end

local function Activate(tool)
	Deactivate()
	local plot = MyPlot()
	local eggName = tool:GetAttribute("EggName")
	local template = eggName and Models:FindFirstChild(eggName .. " Egg")
	if not plot or not template or not template.PrimaryPart then return end

	local preview = template:Clone()
	preview.Name = tool.Name .. " Preview"
	--.. the egg's rolled size + look (EggShop attributes on the tool), exactly what the server will place
	local scale = math.clamp(tonumber(tool:GetAttribute("Scale")) or 1, 0.5, 5) -- keep in step with EggPlacement
	if math.abs(scale - 1) > 1e-3 then preview:ScaleTo(preview:GetScale() * scale) end
	local material = tool:GetAttribute("Material")
	if material == "" then material = nil end
	CucumberMutations.ApplyLook(preview, material, tool:GetAttribute("Mutations"), {ParticleScale = 0.6})
	for _, d in ipairs(preview:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d.Name ~= "Hitbox" then d.Transparency = math.max(d.Transparency, PREVIEW_TRANSPARENCY) end
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("Light") then
			d.Enabled = false
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "OccupiedHighlight"
	highlight.FillColor = OCCUPIED_COLOR
	highlight.OutlineColor = OCCUPIED_COLOR
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = preview
	-- not parented yet: Update() shows it only while the player is at the base

	local state = {
		Tool = tool, Plot = plot, Preview = preview, Hitbox = preview.PrimaryPart, Highlight = highlight,
		Yaw = 0, TargetCF = nil, Valid = false, Connections = {},
	}
	active = state
	--.. Heartbeat (not RenderStepped) so the preview keeps tracking while the window is unfocused
	table.insert(state.Connections, RunService.Heartbeat:Connect(Update))
	table.insert(state.Connections, UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed or active ~= state then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TryPlace()
		end
	end))
	table.insert(state.Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or active ~= state then return end
		if input.KeyCode == Enum.KeyCode.R then state.Yaw = (state.Yaw + ROTATION_STEP) % 360 end
	end))
	table.insert(state.Connections, tool.Unequipped:Connect(function()
		if active == state then Deactivate() end
	end))
	table.insert(state.Connections, tool.AncestryChanged:Connect(function()
		if active == state and tool.Parent ~= player.Character then Deactivate() end
	end))
	Update()
end

local function WatchCharacter(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and CollectionService:HasTag(child, "EggTool") then
			Activate(child)
		end
	end)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and CollectionService:HasTag(child, "EggTool") then Activate(child) end
	end
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then Deactivate() end
	end)
end

player.CharacterAdded:Connect(WatchCharacter)
if player.Character then WatchCharacter(player.Character) end
