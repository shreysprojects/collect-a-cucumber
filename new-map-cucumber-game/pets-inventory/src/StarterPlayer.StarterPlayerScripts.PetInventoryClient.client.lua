--[[
	PetInventoryClient  (LocalScript, StarterPlayerScripts)  2026-09-23
	Reserve pets sit in the hotbar as tools (PetInventoryService). Taking one out (a hotbar click, its
	number key) starts PLACEMENT, the build / cucumber placement recipe (user: "make placing pet from
	inventory show pet preview like in the build placement system ... place pet anywhere theres space"):
	a see-through copy of the pet (its own catalog model with its traits, shrunk to PetBalance.PET.FIT like
	the live one) follows the mouse over YOUR plot, clamped inside it, RED (parts + Highlight) where it would
	overlap something already placed (plot.Placed: cucumbers, builds, eggs) or when the mouse is off the
	plot; a click / tap on a green ghost sends Remotes.PetInventory {Action = "Equip", PetId, Spot} ->
	PetService.Equip(player, id, spot): the pet appears right there and starts roaming, the tool disappears.
	Putting the tool away (another slot, the same slot again) removes the ghost. The server re-validates
	the spot (on the plot, no overlap) and every PetService rule (cap, combat lock) still answers as a toast.
	Studio hook: LocalPlayer attribute PetInventoryDev = "equip:<n>" (equips the n-th pet tool = shows its
	ghost) | "place:<x>,<z>" (places the equipped pet at that plot-local point, no mouse needed).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Notify = require(Modules:WaitForChild("Notify"))
local PetsCatalog = require(Modules:WaitForChild("PetsCatalog"))
local okBalance, PetBalance = pcall(function() return require(Modules:WaitForChild("PetBalance", 5)) end)
if not okBalance then PetBalance = nil end
local okMut, CucumberMutations = pcall(function() return require(Modules:WaitForChild("CucumberMutations", 5)) end)
if not okMut then CucumberMutations = nil end
local okSound, SoundController = pcall(function() return require(Modules:WaitForChild("SoundController", 5)) end)
if not okSound then SoundController = nil end
local okConfig, ManageConfig = pcall(function() return require(Modules:WaitForChild("ManageConfig", 5)) end)
if not okConfig then ManageConfig = nil end

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local REMOTE_WAIT = 60
local PREVIEW_TRANSPARENCY = 0.5 -- CucumberPlacementClient's ghost
local OCCUPIED_COLOR = Color3.fromRGB(255, 40, 40)
local EDGE_INSET = 1 -- studs kept from the plot edge (the roam planner keeps PET.EDGE_INSET too)
local PET_FIT = PetBalance and type(PetBalance.PET) == "table" and tonumber(PetBalance.PET.FIT) or 5

local ERRORS = {
	SlotsFull = "Your base is full - put a pet away first.",
	CombatLocked = "Finish defending your plot first.",
	NoPlot = "You need a base for that.",
	NoSpace = "No room there - try another spot.",
	OffPlot = "Point at your base to place your pet.",
	NotOwned = "That pet is not yours any more.",
	NotLoaded = "Your data is still loading.",
	Closing = "Your data is saving - try again in a moment.",
	RateLimited = "Slow down a little.",
	Unavailable = "Pets are not available right now.",
	BadRequest = "Something went wrong.",
}

local remote = nil
local busy = false
local tracked = {} -- [tool] = {Conns}
local active = nil -- {Tool, Plot, Preview, Size, BottomOffset, Highlight, Colors, Tinted, Valid, Spot, Conns}
local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

--..Helpers..--
local function MyPlot()
	for _, plot in ipairs(Plots:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function Toast(code)
	local text = ERRORS[code] or (ManageConfig and ManageConfig.ERRORS and ManageConfig.ERRORS[code]) or "Could not let that pet out."
	Notify.Error(text, 2.5)
end

--.. the live pet's look: catalog model, traits applied, shrunk (proportions kept) to PET_FIT like PetService
local function BuildPreview(tool)
	local ok, source = pcall(PetsCatalog.ModelOf, tool:GetAttribute("Pet"))
	if not (ok and source and source:IsA("Model")) then return nil end
	local model = source:Clone()
	model.Name = "PetPlacePreview"
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("BodyMover") then d:Destroy() end
	end
	model:SetAttribute("PrismaticLoop", true)
	local material, mutations = tool:GetAttribute("Material"), tool:GetAttribute("Mutations")
	if CucumberMutations and ((type(material) == "string" and material ~= "") or (type(mutations) == "string" and mutations ~= "")) then
		pcall(CucumberMutations.ApplyLook, model, (type(material) == "string" and material ~= "") and material or nil, mutations)
	end
	local _, size = model:GetBoundingBox()
	local biggest = math.max(size.X, size.Y, size.Z)
	if biggest > PET_FIT and biggest > 0 then
		pcall(function() model:ScaleTo(model:GetScale() * PET_FIT / biggest) end)
	end
	local colors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("IKControl") or d:IsA("Attachment") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.Transparency = math.max(d.Transparency, PREVIEW_TRANSPARENCY)
			colors[d] = d.Color
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then
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
	highlight.Parent = model
	local cf, fitted = model:GetBoundingBox()
	--.. how far the model's pivot sits above its lowest point: the ghost stands on the plot top
	local bottomOffset = model:GetPivot().Position.Y - (cf.Position.Y - fitted.Y * 0.5)
	return model, fitted, bottomOffset, highlight, colors
end

local function Deactivate()
	if not active then return end
	for _, c in ipairs(active.Conns) do c:Disconnect() end
	if active.Preview then active.Preview:Destroy() end
	active = nil
end

local function Tint(state, bad)
	if state.Tinted == bad then return end
	state.Tinted = bad
	state.Highlight.Enabled = bad
	for part, color in pairs(state.Colors) do
		if part.Parent then part.Color = bad and OCCUPIED_COLOR or color end
	end
end

--.. the ghost follows the mouse over the plot; plotLocal (x, z) overrides the mouse (dev hook)
local function Update(plotLocal)
	local state = active
	if not state then return end
	local plot = state.Plot
	if not plot.Parent or plot:GetAttribute("Owner") ~= player.UserId then Deactivate() return end
	local size = state.Size
	local halfX = math.max(0, plot.Size.X * 0.5 - size.X * 0.5 - EDGE_INSET)
	local halfZ = math.max(0, plot.Size.Z * 0.5 - size.Z * 0.5 - EDGE_INSET)
	local onPlot, lp
	if plotLocal then
		onPlot = true
		lp = Vector3.new(plotLocal.X, 0, plotLocal.Y)
	else
		local ray = mouse.UnitRay
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {plot}
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		local target
		if hit and hit.Instance == plot then
			target = hit.Position
			onPlot = true
		else
			--.. the ground plane of the plot: keeps the ghost around even over a placed thing, but a
			--.. point outside the plot itself is not a place to put a pet
			local planeY = plot.Position.Y + plot.Size.Y * 0.5
			local t = (planeY - ray.Origin.Y) / ray.Direction.Y
			target = (t > 0 and t < 2000) and (ray.Origin + ray.Direction * t) or plot.Position
			local rel = plot.CFrame:PointToObjectSpace(target)
			onPlot = math.abs(rel.X) <= plot.Size.X * 0.5 and math.abs(rel.Z) <= plot.Size.Z * 0.5
		end
		lp = plot.CFrame:PointToObjectSpace(target)
	end
	local x = math.clamp(lp.X, -halfX, halfX)
	local z = math.clamp(lp.Z, -halfZ, halfZ)
	local top = plot.Size.Y * 0.5
	local boxCF = plot.CFrame * CFrame.new(x, top + size.Y * 0.5, z)
	state.Preview:PivotTo(plot.CFrame * CFrame.new(x, top + state.BottomOffset, z))
	state.Spot = (plot.CFrame * CFrame.new(x, top, z)).Position
	local holder = plot:FindFirstChild("Placed")
	local occupied = false
	if holder then
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {holder}
		occupied = #workspace:GetPartBoundsInBox(boxCF, size, overlap) > 0
	end
	state.Valid = onPlot and not occupied
	state.OffPlot = not onPlot
	Tint(state, not state.Valid)
end

local function TryPlace(plotLocal)
	local state = active
	if not state or busy or not remote then return end
	Update(plotLocal) -- the mouse may have moved since the last frame (and a tap lands with its click)
	if active ~= state then return end
	if not state.Valid then
		Toast(state.OffPlot and "OffPlot" or "NoSpace")
		return
	end
	local tool = state.Tool
	local id = tool:GetAttribute("PetId")
	if type(id) ~= "string" then return end
	local name = tool:GetAttribute("DisplayName") or tool.Name
	busy = true
	local ok, reply = pcall(remote.InvokeServer, remote, {Action = "Equip", PetId = id, Spot = state.Spot})
	busy = false
	if ok and type(reply) == "table" and reply.Ok then
		Notify.Success(("%s is out in your base!"):format(tostring(reply.Name or name)), 2.5)
		if SoundController and type(SoundController.PlayFX) == "function" then pcall(SoundController.PlayFX, "Pet Reward", {Volume = 0.6}) end
		if active == state then Deactivate() end
	else
		Toast(ok and type(reply) == "table" and reply.Error or "Unavailable")
	end
end

local function Activate(tool)
	Deactivate()
	local plot = MyPlot()
	if not plot then Notify.Warn("You need a base to let a pet out.", 2.5) return end
	local preview, size, bottomOffset, highlight, colors = BuildPreview(tool)
	if not preview then Notify.Warn("That pet cannot be shown right now.", 2.5) return end
	local state = {Tool = tool, Plot = plot, Preview = preview, Size = size, BottomOffset = bottomOffset, Highlight = highlight, Colors = colors, Tinted = false, Valid = false, Spot = nil, Conns = {}}
	active = state
	preview.Parent = workspace
	table.insert(state.Conns, RunService.Heartbeat:Connect(function() Update() end))
	table.insert(state.Conns, UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed or active ~= state then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then task.spawn(TryPlace) end
	end))
	Update()
end

local function Track(tool)
	if not tool:IsA("Tool") or tracked[tool] then return end
	if tool:GetAttribute("PetTool") ~= true then return end
	local entry = {Conns = {}}
	tracked[tool] = entry
	table.insert(entry.Conns, tool.Equipped:Connect(function() Activate(tool) end))
	table.insert(entry.Conns, tool.Unequipped:Connect(function()
		if active and active.Tool == tool then Deactivate() end
	end))
	table.insert(entry.Conns, tool.Destroying:Connect(function()
		if active and active.Tool == tool then Deactivate() end
	end))
	if tool.Parent == player.Character then Activate(tool) end
end

local function Untrack(tool)
	local entry = tracked[tool]
	if not entry then return end
	for _, c in ipairs(entry.Conns) do c:Disconnect() end
	tracked[tool] = nil
	if active and active.Tool == tool then Deactivate() end
end

local function Watch(container)
	if not container then return end
	for _, tool in ipairs(container:GetChildren()) do Track(tool) end
	container.ChildAdded:Connect(Track)
	container.ChildRemoved:Connect(function(tool)
		task.defer(function()
			local backpack = player:FindFirstChild("Backpack")
			if tool.Parent ~= backpack and tool.Parent ~= player.Character then Untrack(tool) end
		end)
	end)
end

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
	local r = remotes and remotes:WaitForChild("PetInventory", REMOTE_WAIT)
	if r and r:IsA("RemoteFunction") then remote = r else warn("[PetInventoryClient] Remotes.PetInventory not found - pet tools do nothing") end
end)

Watch(player:WaitForChild("Backpack"))
player.ChildAdded:Connect(function(child)
	if child.Name == "Backpack" then Watch(child) end
end)
player.CharacterAdded:Connect(function(character)
	Deactivate()
	Watch(character)
end)
if player.Character then Watch(player.Character) end

if RunService:IsStudio() then
	player:GetAttributeChangedSignal("PetInventoryDev"):Connect(function()
		local cmd = player:GetAttribute("PetInventoryDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		player:SetAttribute("PetInventoryDev", nil)
		local kind, arg = cmd:match("^(%w+):?(.*)$")
		if kind == "equip" then
			local n = tonumber(arg) or 1
			local backpack = player:FindFirstChild("Backpack")
			local list = {}
			for _, tool in ipairs(backpack and backpack:GetChildren() or {}) do
				if tool:IsA("Tool") and tool:GetAttribute("PetTool") == true then table.insert(list, tool) end
			end
			table.sort(list, function(a, b) return a.Name < b.Name end)
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if list[n] and humanoid then humanoid:EquipTool(list[n]) end
		elseif kind == "place" then
			local x, z = arg:match("^(-?[%d%.]+),(-?[%d%.]+)$")
			task.spawn(TryPlace, (x and z) and Vector2.new(tonumber(x), tonumber(z)) or nil)
		end
	end)
end
