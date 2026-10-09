--[[
	CucumberPlacementClient  (LocalScript, StarterPlayerScripts)
	Plot placement for a CARRIED cucumber -- the same flow PlacementClient gives egg
	tools: while you carry a cucumber (player attribute CarryingCucumber, set by
	CucumberCarry) AND stand at your own plot, a see-through copy of the cucumber on
	your shoulder -- grown back to the size it was in the wild -- follows the mouse over the plot in its natural resting pose
	(snapped to GRID_SIZE, clamped inside the plot, RED - parts and Highlight - when it
	overlaps something already placed or hangs outside; 2026-09-13). Click / tap places it through Remotes.requestCucumberPlacement;
	R rotates by ROTATION_STEP. The server re-validates everything.
	Steps aside whenever an egg tool is equipped (PlacementClient owns the click then).
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
local COLLISION_SHRINK = 0.96 -- keep in step with CucumberCarry
local AT_BASE_MARGIN = 6 -- keep in step with CucumberCarry

--..Variables..--
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestPlacement = Remotes:WaitForChild("requestCucumberPlacement")
local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

local active = nil -- {Plot, Preview, Size, Lift, RestRotation, Highlight, Yaw, TargetCF, Valid, Connections}
local Actions = game:GetService("ContextActionService")
local Notify = require(ReplicatedStorage.Modules.Notify)
local CucumberFootprint = require(ReplicatedStorage.Modules:WaitForChild("CucumberFootprint")) -- 2026-09-13: the collision box shrinks with width
local QuickPlace

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

local function EggToolEquipped()
	local char = player.Character
	if not char then return false end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") and CollectionService:HasTag(c, "EggTool") then return true end
	end
	return false
end

local function Deactivate()
	Actions:UnbindAction("QuickPlaceCucumber")
	if not active then return end
	for _, c in ipairs(active.Connections) do c:Disconnect() end
	if active.Preview then active.Preview:Destroy() end
	active = nil
end

local function Update()
	local state = active
	if not state then return end
	local plot = state.Plot
	if not plot.Parent or player:GetAttribute("CarryingCucumber") == nil then Deactivate() return end

	--.. only while standing at the base with no egg tool out
	if not AtBase(plot) or EggToolEquipped() then
		if state.QuickBound then Actions:UnbindAction("QuickPlaceCucumber") state.QuickBound = false end
		if state.Preview.Parent then state.Preview.Parent = nil end
		state.Valid = false
		return
	elseif not state.Preview.Parent then
		state.Preview.Parent = workspace
	end

	if not state.QuickBound then
		Actions:BindAction("QuickPlaceCucumber", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then task.spawn(QuickPlace) end
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
		Actions:SetTitle("QuickPlaceCucumber", "Quick place")
		Actions:SetPosition("QuickPlaceCucumber", UDim2.fromScale(.72, .48))
		state.QuickBound = true
	end
	local ray = mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {plot}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	--.. the Include filter takes the plot's DESCENDANTS too, and every placed cucumber now carries
	--.. a full-size PlotHitbox with CanQuery on (2026-09-08) -- without this the cursor snaps to the
	--.. top of whatever is already standing there instead of to the ground
	if hit and hit.Instance ~= plot then hit = nil end
	local target
	if hit then
		target = hit.Position
	else
		local planeY = plot.Position.Y + plot.Size.Y * 0.5
		local t = (planeY - ray.Origin.Y) / ray.Direction.Y
		target = (t > 0 and t < 2000) and (ray.Origin + ray.Direction * t) or plot.Position
	end

	local size = state.Size
	local box = CucumberFootprint.Box(size) -- the footprint the server tests (smaller than the canopy for wide ones)
	local yaw = math.rad(state.Yaw)
	local fx, fz = Footprint(box, yaw)
	local lp = plot.CFrame:PointToObjectSpace(target)
	--.. a full-size cucumber (2026-09-08) can be wider than the plot's own half-width: never build
	--.. an empty clamp range (math.clamp errors when min > max), just pin it to the middle and let
	--.. the server refuse it
	local halfX = math.max(0, plot.Size.X * 0.5 - fx * 0.5)
	local halfZ = math.max(0, plot.Size.Z * 0.5 - fz * 0.5)
	--.. wider than the plot at this yaw: the clamp pins it to the middle and it still hangs off
	--.. both edges, so say so with the red highlight rather than letting a green ghost be refused
	local tooBig = fx > plot.Size.X or fz > plot.Size.Z
	local x = math.clamp(Snap(lp.X), -halfX, halfX)
	local z = math.clamp(Snap(lp.Z), -halfZ, halfZ)
	local top = plot.Size.Y * 0.5
	local boxCF = plot.CFrame * CFrame.new(x, top + size.Y * 0.5, z) * CFrame.Angles(0, yaw, 0)
	state.TargetCF = boxCF
	state.Preview:PivotTo(plot.CFrame * CFrame.new(x, top + state.Lift, z) * CFrame.Angles(0, yaw, 0) * state.RestRotation)

	--.. occupied? (same test the server runs)
	local holder = plot:FindFirstChild("Placed")
	local occupied = false
	if holder then
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {holder}
		occupied = #workspace:GetPartBoundsInBox(boxCF, box, overlap) > 0
	end
	state.Valid = not occupied and not tooBig
	state.Highlight.Enabled = occupied or tooBig
	--.. and the parts themselves go red (2026-09-13: the Highlight alone was easy to miss)
	local bad = occupied or tooBig
	if state.Tinted ~= bad then
		state.Tinted = bad
		for part, color in pairs(state.Colors or {}) do
			if part.Parent then part.Color = bad and OCCUPIED_COLOR or color end
		end
	end
end

QuickPlace = function()
	local state = active
	if not state or state.QuickBusy or not AtBase(state.Plot) or EggToolEquipped() then return end
	state.QuickBusy = true
	local plot, size = state.Plot, state.Size
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then state.QuickBusy = false return end
	local lp = plot.CFrame:PointToObjectSpace(root.Position)
	local yaw = math.rad(state.Yaw)
	local box = CucumberFootprint.Box(size)
	local fx, fz = Footprint(box, yaw)
	local halfX, halfZ = (plot.Size.X - fx) * .5, (plot.Size.Z - fz) * .5
	if halfX < 0 or halfZ < 0 then
		state.QuickBusy = false
		Notify.Warn("This cucumber needs more room. Try rotating it.")
		return
	end
	local candidates = {}
	local step = math.max(2, math.sqrt((halfX * 2 + 1) * (halfZ * 2 + 1) / 1800))
	for x = -halfX, halfX, step do
		for z = -halfZ, halfZ, step do
			table.insert(candidates, {X = x, Z = z, Distance = (x - lp.X)^2 + (z - lp.Z)^2})
		end
	end
	table.sort(candidates, function(a, b) return a.Distance < b.Distance end)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = {plot:FindFirstChild("Placed") or state.Preview}
	for i, candidate in ipairs(candidates) do
		if active ~= state or not AtBase(plot) or EggToolEquipped() then state.QuickBusy = false return end
		local cf = plot.CFrame * CFrame.new(candidate.X, plot.Size.Y * .5 + size.Y * .5, candidate.Z) * CFrame.Angles(0, yaw, 0)
		if #workspace:GetPartBoundsInBox(cf, box, overlap) == 0 then
			local ok, placed = pcall(function() return requestPlacement:InvokeServer(cf) end)
			state.QuickBusy = false
			if ok and placed then
				if active == state then Deactivate() end
			else Notify.Warn("That spot changed. Try quick place again.") end
			return
		end
		if i % 24 == 0 then RunService.Heartbeat:Wait() end
	end
	state.QuickBusy = false
	Notify.Warn("No free spot here. Try rotating or placing manually.")
end

local function TryPlace()
	local state = active
	if not state or state.QuickBusy or not state.Valid or not state.TargetCF or not state.Preview.Parent then return end
	local ok, reason = requestPlacement:InvokeServer(state.TargetCF)
	if ok then
		Deactivate()
	elseif active == state then
		state.Highlight.Enabled = true -- flash red on a rejection, next Update() restores it
		--.. cucumbers stand at their full wild size since 2026-09-08, so a big one (a tree, a
		--.. giant) can simply not fit: say why instead of flashing red forever
		if reason == "outside plot" then
			Notify.Warn("This one is too big to fit there. Rotate it, or upgrade your plot.")
		elseif reason == "occupied" then
			Notify.Warn("Something is already standing there.")
		end
	end
end

local function Activate()
	Deactivate()
	local plot = MyPlot()
	if not plot then return end
	--.. the shoulder model replicates a beat after the attribute
	local model
	local deadline = os.clock() + 4
	while os.clock() < deadline and player:GetAttribute("CarryingCucumber") ~= nil do
		local char = player.Character
		model = char and char:FindFirstChild("CarriedCucumber")
		if model and typeof(model:GetAttribute("RestSize")) == "Vector3" and typeof(model:GetAttribute("RestRotation")) == "CFrame" then break end
		model = nil
		task.wait(0.1)
	end
	if not model or active then return end
	local size = model:GetAttribute("RestSize")
	local restRot = model:GetAttribute("RestRotation")
	local lift = tonumber(model:GetAttribute("RestLift")) or size.Y * 0.5

	local preview = model:Clone()
	preview.Name = "CucumberPlacePreview"
	--.. the shoulder copy is shrunk to an armful, but a placed cucumber stands at its FIELD size
	--.. (CucumberCarry, 2026-09-08) and RestSize / RestLift above are measured at that scale --
	--.. so the ghost grows by the same factor or it would not match its own footprint
	local placeScale = tonumber(model:GetAttribute("PlaceScale")) or 1
	if placeScale ~= 1 then preview:ScaleTo(preview:GetScale() * placeScale) end
	local colors = {}
	for _, d in ipairs(preview:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("IKControl") or d:IsA("Attachment") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Transparency = math.max(d.Transparency, PREVIEW_TRANSPARENCY)
			colors[d] = d.Color
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("Light") or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then
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
		Plot = plot, Preview = preview, Size = size, Lift = lift, RestRotation = restRot, Highlight = highlight,
		Yaw = 0, TargetCF = nil, Valid = false, Connections = {}, Colors = colors, Tinted = false,
	}
	active = state
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
	Update()
end

player:GetAttributeChangedSignal("CarryingCucumber"):Connect(function()
	if player:GetAttribute("CarryingCucumber") ~= nil then
		task.spawn(Activate)
	else
		Deactivate()
	end
end)
player.CharacterAdded:Connect(function()
	Deactivate()
	if player:GetAttribute("CarryingCucumber") ~= nil then task.spawn(Activate) end
end)
if player:GetAttribute("CarryingCucumber") ~= nil then task.spawn(Activate) end
