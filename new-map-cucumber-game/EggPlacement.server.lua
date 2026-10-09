--[[
	EggPlacement  (Script, ServerScriptService)
	Server half of the egg placement system (structure follows the DevForum
	"PlacementService" pattern: Plot part = bounds, placeable models with a
	hitbox PrimaryPart in ReplicatedStorage, an item holder folder per plot,
	one RemoteFunction "requestPlacement", full re-validation on the server).

	  * at start: builds ReplicatedStorage.PlaceableModels/<Name> Egg from each
	    physical egg (same models the shop uses), scaled by PLACED_SCALE, with an
	    invisible "Hitbox" PrimaryPart sized to the egg and the attribute BiomeIndex (the
	    biome the stand lives in); creates ReplicatedStorage.Remotes.requestPlacement and a
	    "Placed" folder in every plot
	  * requestPlacement(tool, cframe) -> true/false. The server only trusts the
	    client's X/Z and yaw: it rebuilds the CFrame on the plot surface, rejects
	    anything whose footprint leaves the player's own plot, rejects overlaps
	    with already placed objects (GetPartBoundsInBox against plot.Placed),
	    then clones the model into plot.Placed and consumes the egg tool
	  * the tool's roll travels with the egg (2026-09-07): the model is found by the tool's
	    EggName attribute, scaled by its Scale attribute (heavier eggs are bigger, EggShop) and
	    painted with CucumberMutations.ApplyLook (Material / Mutations attributes); the placed
	    model keeps Kg / Scale / Material / Mutations / DisplayName
	  * placed objects carry attributes Owner / EggName; when a plot's Owner
	    attribute clears (PlotService released it) its Placed folder is emptied
	  * placements are saved by BaseSaveService (2026-09-12, profile.Data.Base.Eggs) and come back through
	    ServerStorage.EggPlacementAPI.RestoreEgg with their HatchAt clock, so the countdown runs offline
	  * HATCH TIME (2026-09-07, user): by the egg's home biome (HATCH_BY_BIOME: Spawn 3 s ...
	    Narmek 1 h) times a small size / mutation / material factor (HATCH_PER_DECADE,
	    HATCH_PER_MUTATION, HATCH_MATERIAL); placed eggs carry PlacedAt / HatchAt (server clock) /
	    HatchSeconds for the "Egg + countdown" label drawn by EggTimerClient; nothing happens when
	    it reaches zero yet
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

--..Modules..--
local CucumberMutations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CucumberMutations"))

--..Config..--
local PLACED_SCALE = 1 -- relative to the physical egg on its stand (4.75 studs tall)
local COLLISION_SHRINK = 0.96 -- hitbox fraction used for the overlap test so edges may touch
local PLACE_COOLDOWN = 0.2 -- seconds per player
local BOUNDS_EPSILON = 0.05
local AT_BASE_MARGIN = 6 -- studs outside the plot edge that still count as "at the base" (keep in step with PlacementClient)
local SCALE_MIN, SCALE_MAX = 0.5, 5 -- sanity clamp for the tool's Scale attribute (EggShop caps at 4.2 for a 100,000 kg egg)
--.. hatch time (seconds) by the egg's home biome index ("01 Spawn" = 1 ... "08 Narmek" = 8)
local HATCH_BY_BIOME = {[1] = 3, [2] = 10, [3] = 30, [4] = 90, [5] = 240, [6] = 600, [7] = 1500, [8] = 3600, [9] = 3600, [10] = 3600}
local HATCH_DEFAULT = 300
local HATCH_PER_DECADE = 0.08 -- +8% per x10 kg above 2 kg (a 100,000 kg egg: +38%)
local HATCH_PER_MUTATION = 0.08 -- +8% per mutation (up to 4)
local HATCH_MATERIAL = {Golden = 0.1, Diamond = 0.15} -- +10% / +15%
local PLOTS = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
local BIOMES = workspace:WaitForChild("Map"):WaitForChild("Biomes")

--..Instances..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local requestPlacement = Remotes:FindFirstChild("requestPlacement")
if not requestPlacement then
	requestPlacement = Instance.new("RemoteFunction")
	requestPlacement.Name = "requestPlacement"
	requestPlacement.Parent = Remotes
end
local Models = ReplicatedStorage:FindFirstChild("PlaceableModels")
if not Models then
	Models = Instance.new("Folder")
	Models.Name = "PlaceableModels"
	Models.Parent = ReplicatedStorage
end

--..Variables..--
local LastPlace = {} -- [player] = os.clock()

--..Functions..--
--.. same rule as EggShop (which stamps the stand with attribute EggName); the shop's "X left!"
--.. stock billboard is never mistaken for the name label
local function EggNameOf(stand)
	local stamped = stand:GetAttribute("EggName")
	if type(stamped) == "string" and stamped ~= "" then return stamped end
	for _, d in ipairs(stand:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text ~= "" and d.Text:upper() ~= "EGG" and not d:FindFirstAncestorWhichIsA("BillboardGui") then
			return d.Text
		end
	end
	return (stand.Name:gsub("%s*Egg%s*Stand$", ""):gsub("%s*Egg$", ""))
end

local function BuildPlaceable(eggName, eggModel, biomeIndex)
	local model = eggModel:Clone()
	model.Name = eggName .. " Egg"
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") or d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") then d:Destroy() end -- the shop's prompt + stock label stay on the stand
	end
	if PLACED_SCALE ~= 1 then model:ScaleTo(model:GetScale() * PLACED_SCALE) end
	local cf, size = model:GetBoundingBox()
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = size
	hitbox.CFrame = CFrame.new(cf.Position) -- upright box at the egg's centre
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true -- the overlap test finds placed objects through their hitbox
	hitbox.Parent = model
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= hitbox then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	model.PrimaryPart = hitbox
	model:SetAttribute("EggName", eggName)
	model:SetAttribute("BiomeIndex", biomeIndex)
	model.Parent = Models
	return model
end

--.. seconds until a placed egg hatches: the home biome's base time, a little longer for heavy,
--.. mutated or Golden / Diamond eggs
local function HatchSeconds(biomeIndex, kg, material, mutations)
	local base = HATCH_BY_BIOME[tonumber(biomeIndex) or 0] or HATCH_DEFAULT
	local mult = 1 + HATCH_PER_DECADE * math.max(0, math.log10(math.max(tonumber(kg) or 2, 2) / 2))
	mult *= 1 + HATCH_PER_MUTATION * #CucumberMutations.Parse(mutations)
	mult *= 1 + (HATCH_MATERIAL[material] or 0)
	return math.max(1, math.round(base * mult))
end

local function PlotOf(player)
	for _, plot in ipairs(PLOTS:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function HolderOf(plot)
	local holder = plot:FindFirstChild("Placed")
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = "Placed"
		holder.Parent = plot
	end
	return holder
end

local function Footprint(size, yaw)
	local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
	return c * size.X + s * size.Z, s * size.X + c * size.Z
end

local function Place(player, tool, cframe)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or not CollectionService:HasTag(tool, "EggTool") then return false, "not an egg" end
	local character = player.Character
	if not (tool.Parent == character or tool.Parent == player:FindFirstChild("Backpack")) then return false, "tool not yours" end
	if typeof(cframe) ~= "CFrame" then return false, "bad cframe" end
	local now = os.clock()
	if LastPlace[player] and now - LastPlace[player] < PLACE_COOLDOWN then return false, "cooldown" end
	local plot = PlotOf(player)
	if not plot then return false, "no plot" end
	--.. must be standing at the base
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false, "no character" end
	local rp = plot.CFrame:PointToObjectSpace(root.Position)
	if math.abs(rp.X) > plot.Size.X * 0.5 + AT_BASE_MARGIN or math.abs(rp.Z) > plot.Size.Z * 0.5 + AT_BASE_MARGIN then
		return false, "not at base"
	end
	local eggName = tool:GetAttribute("EggName")
	local template = eggName and Models:FindFirstChild(eggName .. " Egg")
	if not template or not template.PrimaryPart then return false, "no model" end
	--.. the egg's rolled size travels on the tool (EggShop): the footprint, the hitbox and the model all scale with it
	local scale = math.clamp(tonumber(tool:GetAttribute("Scale")) or 1, SCALE_MIN, SCALE_MAX)
	local size = template.PrimaryPart.Size * scale

	--.. rebuild the placement from the client's X/Z + yaw only, on the plot surface
	local relative = plot.CFrame:ToObjectSpace(cframe)
	local _, yaw = relative:ToEulerAnglesYXZ()
	local fx, fz = Footprint(size, yaw)
	local x, z = relative.Position.X, relative.Position.Z
	if math.abs(x) + fx * 0.5 > plot.Size.X * 0.5 + BOUNDS_EPSILON or math.abs(z) + fz * 0.5 > plot.Size.Z * 0.5 + BOUNDS_EPSILON then
		return false, "outside plot"
	end
	local target = plot.CFrame * CFrame.new(x, plot.Size.Y * 0.5 + size.Y * 0.5, z) * CFrame.Angles(0, yaw, 0)

	--.. occupied?
	local holder = HolderOf(plot)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {holder}
	if #workspace:GetPartBoundsInBox(target, size * COLLISION_SHRINK, params) > 0 then
		return false, "occupied"
	end

	LastPlace[player] = now
	local placed = template:Clone()
	if math.abs(scale - 1) > 1e-3 then placed:ScaleTo(placed:GetScale() * scale) end
	placed:PivotTo(target)
	placed:SetAttribute("Owner", player.UserId)
	placed:SetAttribute("EggName", template:GetAttribute("EggName"))
	--.. the roll (EggShop): weight, size, material + mutations, and the same look as the held egg
	local material = tool:GetAttribute("Material")
	local mutations = CucumberMutations.Join(tool:GetAttribute("Mutations"))
	if material == "" then material = nil end
	local kg = tonumber(tool:GetAttribute("Kg")) or 0
	placed:SetAttribute("Kg", kg)
	placed:SetAttribute("Scale", scale)
	placed:SetAttribute("Material", material)
	placed:SetAttribute("Mutations", mutations)
	placed:SetAttribute("DisplayName", tool:GetAttribute("DisplayName") or (eggName .. " Egg"))
	CucumberMutations.ApplyLook(placed, material, mutations)
	--.. hatch countdown on the server clock; EggTimerClient renders it (nothing happens at zero yet)
	local hatch = HatchSeconds(template:GetAttribute("BiomeIndex"), kg, material, mutations)
	placed:SetAttribute("HatchSeconds", hatch)
	placed:SetAttribute("PlacedAt", workspace:GetServerTimeNow())
	placed:SetAttribute("HatchAt", workspace:GetServerTimeNow() + hatch)
	CollectionService:AddTag(placed, "PlacedEgg")
	placed.Parent = holder
	tool:Destroy()
	return true
end

--..API for BaseSaveService (2026-09-12): a saved egg comes back at its saved pivot with its saved clock
--..(HatchAt is server time = real time, so the countdown kept running while the owner was away; an egg
--..whose HatchAt has passed is ready the moment its owner steps on it), an admin reset clears them..--
local function RestoreEgg(player, plot, record, pivot)
	if not (player and plot and plot.Parent and type(record) == "table" and typeof(pivot) == "CFrame") then return nil, "bad restore" end
	local eggName = record.EggName
	local template = type(eggName) == "string" and Models:FindFirstChild(eggName .. " Egg")
	if not template or not template.PrimaryPart then return nil, "no model for " .. tostring(eggName) end
	local scale = math.clamp(tonumber(record.Scale) or 1, SCALE_MIN, SCALE_MAX)
	local placed = template:Clone()
	if math.abs(scale - 1) > 1e-3 then placed:ScaleTo(placed:GetScale() * scale) end
	placed:PivotTo(pivot)
	local material = record.Material
	if material == "" then material = nil end
	local mutations = CucumberMutations.Join(record.Mutations)
	placed:SetAttribute("Owner", player.UserId)
	placed:SetAttribute("EggName", template:GetAttribute("EggName"))
	placed:SetAttribute("Kg", tonumber(record.Kg) or 0)
	placed:SetAttribute("Scale", scale)
	placed:SetAttribute("Material", material)
	placed:SetAttribute("Mutations", mutations)
	placed:SetAttribute("DisplayName", record.DisplayName or (eggName .. " Egg"))
	CucumberMutations.ApplyLook(placed, material, mutations)
	local now = workspace:GetServerTimeNow()
	local hatchAt = tonumber(record.HatchAt) or now
	placed:SetAttribute("HatchSeconds", tonumber(record.HatchSeconds) or math.max(0, hatchAt - (tonumber(record.PlacedAt) or now)))
	placed:SetAttribute("PlacedAt", tonumber(record.PlacedAt) or now)
	placed:SetAttribute("HatchAt", hatchAt)
	CollectionService:AddTag(placed, "PlacedEgg")
	placed.Parent = HolderOf(plot)
	return placed
end

local function ClearEggs(plot)
	local holder = plot and plot:FindFirstChild("Placed")
	if not holder then return 0 end
	local n = 0
	for _, model in ipairs(holder:GetChildren()) do
		if CollectionService:HasTag(model, "PlacedEgg") then
			model:Destroy()
			n += 1
		end
	end
	return n
end

do
	local ServerStorage = game:GetService("ServerStorage")
	local api = ServerStorage:FindFirstChild("EggPlacementAPI") or Instance.new("Folder")
	api.Name = "EggPlacementAPI"
	api.Parent = ServerStorage
	local restore = api:FindFirstChild("RestoreEgg") or Instance.new("BindableFunction")
	restore.Name = "RestoreEgg"
	restore.OnInvoke = RestoreEgg
	restore.Parent = api
	local clear = api:FindFirstChild("ClearEggs") or Instance.new("BindableFunction")
	clear.Name = "ClearEggs"
	clear.OnInvoke = ClearEggs
	clear.Parent = api
end

--..Setup..--
for _, biome in ipairs(BIOMES:GetChildren()) do
	local eggsFolder = biome:FindFirstChild("Eggs")
	if eggsFolder then
		local biomeIndex = tonumber(biome.Name:match("^(%d+)"))
		for _, stand in ipairs(eggsFolder:GetChildren()) do
			local eggModel
			for _, c in ipairs(stand:GetChildren()) do
				if c:IsA("Model") and c.Name:find("Egg") then eggModel = c break end
			end
			if eggModel then
				local eggName = EggNameOf(stand)
				if not Models:FindFirstChild(eggName .. " Egg") then BuildPlaceable(eggName, eggModel, biomeIndex) end
			end
		end
	end
end

for _, plot in ipairs(PLOTS:GetChildren()) do
	if plot:IsA("BasePart") then
		plot.CanQuery = true -- the client aims at the plot with a raycast
		HolderOf(plot)
		plot:GetAttributeChangedSignal("Owner"):Connect(function()
			if plot:GetAttribute("Owner") == nil then HolderOf(plot):ClearAllChildren() end
		end)
	end
end

requestPlacement.OnServerInvoke = function(player, tool, cframe)
	local ok, result, reason = pcall(Place, player, tool, cframe)
	if not ok then
		warn("[EggPlacement] " .. tostring(result))
		return false
	end
	return result == true, reason
end

Players.PlayerRemoving:Connect(function(player) LastPlace[player] = nil end)
print(("[EggPlacement] %d placeable egg models ready"):format(#Models:GetChildren()))
