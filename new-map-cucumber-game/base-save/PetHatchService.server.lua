--[[
	PetHatchService  (Script, ServerScriptService)
	Egg hatching + plot pets, ported from the Zombie Cucumber Game on 2026-09-07.

	  * TRIGGER: a placed egg (EggPlacement, tag "PlacedEgg", attributes HatchAt / Owner / EggName)
	    whose countdown has reached zero hatches the moment its OWNER steps onto it (root inside the
	    egg's hitbox footprint + STEP_MARGIN, up to STEP_HEIGHT above its base). One hatch at a time
	    per player.
	  * ROLL: PetsCatalog.Roll = the zombie EggService float roll over the egg's pool (same eight
	    pools, same odds). Nothing is saved yet (user: no DataStore saving for pets) -- only
	    player attribute PetsHatched counts this session's hatches.
	  * REVEAL: the server destroys the egg and fires ReplicatedStorage.Remotes.PetHatch "Begin"
	    to the owner with everything the client needs to rebuild the egg (EggName / Scale /
	    Material / Mutations) and show the pet (Pet / display name / rarity / odds).
	    EggHatchClient plays the zombie click-to-hatch reveal and answers "Opened"; the pet is
	    spawned then (or after REVEAL_FALLBACK seconds if the answer never comes).
	  * PLOT PETS: the pet model (ReplicatedStorage.Assets.Pets/<name>, shrunk to fit a PET_FIT
	    cube like the zombie petsize cap) is cloned ANCHORED + collision-free into plot.Pets, tagged
	    "PlotPet", attributes PetName / DisplayName / Rarity / Owner / Plot. It does NOT follow the
	    player: this script plans roaming legs inside the plot (random points, EDGE_INSET from the
	    edge, never on top of a placed egg / cucumber) as attributes RoamFrom / RoamTo (Vector3) +
	    RoamStart / RoamEnd (server clock) + RoamIdleUntil; every client animates the walk from
	    those (PetRoamClient: zombie Movement step bounce + facing), so the motion is smooth for
	    everyone and costs the server nothing per frame.
	  * pets are cleared with the plot (Owner attribute -> nil, same rule as EggPlacement).
	  * Studio dev hook: workspace:SetAttribute("PetHatchDev", ...)
	      "ready"               every placed egg's countdown -> 0
	      "hatch:<EggName>"     fake a hatch of that egg (Basic / Desert / ...) for the first player
	      "hatch:<EggName>:<Pet>"  same, forcing the pet
	      "spawn:<Pet>"         spawn a pet on the first player's plot without a reveal
	      "clear"               remove every plot pet
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--..Modules..--
local Catalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetsCatalog"))

--..Config..--
local EGG_TAG = "PlacedEgg"
local PET_TAG = "PlotPet"
local STEP_MARGIN = 1.25 -- studs beyond the egg hitbox footprint that still count as standing on it
local STEP_HEIGHT = 7 -- the root may be this far above the egg's base (standing on top of a big egg)
local REVEAL_FALLBACK = 80 -- seconds: spawn the pet even if the client never reports the reveal done (4 x 15 s idle stages + the reveal)
local PET_FIT = 5 -- studs: pets are shrunk (proportions kept) to fit this cube (zombie ReplicatedStorage.petsize)
local EDGE_INSET = 2 -- studs kept from the plot edge when picking roam points
local SPEED_MIN, SPEED_MAX = 5, 8 -- studs / s per leg
local IDLE_MIN, IDLE_MAX = 1.5, 4.5 -- seconds between legs
local LEG_MIN, LEG_MAX = 8, 26 -- preferred leg length (studs); clamped to the plot
local PLAN_TICK = 0.2
local TRIGGER_TICK = 0.15
local PLOTS = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

--..Instances..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local PetHatch = Remotes:FindFirstChild("PetHatch")
if not PetHatch then
	PetHatch = Instance.new("RemoteEvent")
	PetHatch.Name = "PetHatch"
	PetHatch.Parent = Remotes
end
local PetsAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Pets")

--..State..--
local Pending = {} -- [player] = {Token, Plot, Pet, Spot, EggName}
local Hatched = {} -- [player] = count this session (not saved)
local Rng = Random.new()
local TokenCounter = 0

--..Helpers..--
local function PlotOf(player)
	for _, plot in ipairs(PLOTS:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function PetsFolderOf(plot)
	local folder = plot:FindFirstChild("Pets")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Pets"
		folder.Parent = plot
	end
	return folder
end

local function PlotTop(plot)
	return plot.Position.Y + plot.Size.Y * 0.5
end

--.. zombie Movement.rootToVisibleBottom: how far the visible artwork hangs below the root, so the
--.. pet stands on the ground instead of the invisible root
local function RootToVisibleBottom(pet, root)
	local bottom = math.huge
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			local cf, half = d.CFrame, d.Size * 0.5
			local yExtent = math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
			bottom = math.min(bottom, d.Position.Y - yExtent)
		end
	end
	if bottom == math.huge then
		local cf, size = pet:GetBoundingBox()
		bottom = cf.Position.Y - size.Y * 0.5
	end
	return root.Position.Y - bottom
end

--.. plot-local half extents a pet centre may use
local function RoamBounds(plot, radius)
	local hx = plot.Size.X * 0.5 - EDGE_INSET - radius
	local hz = plot.Size.Z * 0.5 - EDGE_INSET - radius
	return math.max(hx, 0.5), math.max(hz, 0.5)
end

local function ClampToPlot(plot, worldPos, radius)
	local hx, hz = RoamBounds(plot, radius)
	local rel = plot.CFrame:PointToObjectSpace(worldPos)
	local x = math.clamp(rel.X, -hx, hx)
	local z = math.clamp(rel.Z, -hz, hz)
	local p = plot.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
	return Vector3.new(p.X, PlotTop(plot), p.Z)
end

local function Blocked(plot, pos, radius)
	local placed = plot:FindFirstChild("Placed")
	if not placed or #placed:GetChildren() == 0 then return false end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {placed}
	local box = CFrame.new(pos.X, PlotTop(plot) + 2, pos.Z)
	return #workspace:GetPartBoundsInBox(box, Vector3.new(radius * 2, 4, radius * 2), params) > 0
end

--.. a new roam point: a leg of LEG_MIN..LEG_MAX studs in a random direction, kept inside the
--.. plot and off the placed objects; falls back to any free point; nil = nothing free
local function PickPoint(plot, from, radius)
	for _ = 1, 10 do
		local angle = Rng:NextNumber() * math.pi * 2
		local len = Rng:NextNumber(LEG_MIN, LEG_MAX)
		local candidate = ClampToPlot(plot, from + Vector3.new(math.cos(angle) * len, 0, math.sin(angle) * len), radius)
		local d = Vector3.new(candidate.X - from.X, 0, candidate.Z - from.Z).Magnitude
		if d >= 3 and not Blocked(plot, candidate, radius) then return candidate end
	end
	local hx, hz = RoamBounds(plot, radius)
	for _ = 1, 10 do
		local p = plot.CFrame:PointToWorldSpace(Vector3.new(Rng:NextNumber(-hx, hx), 0, Rng:NextNumber(-hz, hz)))
		local candidate = Vector3.new(p.X, PlotTop(plot), p.Z)
		local d = Vector3.new(candidate.X - from.X, 0, candidate.Z - from.Z).Magnitude
		if d >= 3 and not Blocked(plot, candidate, radius) then return candidate end
	end
	return nil
end

local function PlanLeg(pet, plot)
	local now = workspace:GetServerTimeNow()
	local radius = tonumber(pet:GetAttribute("RoamRadius")) or 2
	local from = pet:GetAttribute("RoamTo")
	if typeof(from) ~= "Vector3" then
		local p = pet:GetPivot().Position
		from = Vector3.new(p.X, PlotTop(plot), p.Z)
	end
	from = ClampToPlot(plot, from, radius) -- the plot may have shrunk since the last leg
	local target = PickPoint(plot, from, radius)
	if not target then
		pet:SetAttribute("RoamTo", from)
		pet:SetAttribute("RoamIdleUntil", now + Rng:NextNumber(IDLE_MIN, IDLE_MAX))
		return
	end
	local dist = Vector3.new(target.X - from.X, 0, target.Z - from.Z).Magnitude
	local duration = dist / Rng:NextNumber(SPEED_MIN, SPEED_MAX)
	pet:SetAttribute("RoamFrom", from)
	pet:SetAttribute("RoamTo", target)
	pet:SetAttribute("RoamStart", now)
	pet:SetAttribute("RoamEnd", now + duration)
	pet:SetAttribute("RoamGroundY", PlotTop(plot))
	pet:SetAttribute("RoamIdleUntil", now + duration + Rng:NextNumber(IDLE_MIN, IDLE_MAX))
end

--..Pets..--
local function SpawnPet(player, plot, petName, spot)
	local template = Catalog.ModelOf(petName)
	if not template then
		warn("[PetHatchService] no model for pet " .. tostring(petName))
		return nil
	end
	local pet = template:Clone()
	pet.Name = petName
	--.. size cap (zombie petsize): shrink until it fits the cube, never grow
	local _, size = pet:GetBoundingBox()
	local factor = math.min(1, PET_FIT / size.X, PET_FIT / size.Y, PET_FIT / size.Z)
	if factor < 1 then pet:ScaleTo(pet:GetScale() * factor) end
	local partCount = 0
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			partCount += 1
		elseif d:IsA("BodyMover") or d:IsA("BodyGyro") or d:IsA("BodyPosition") then
			d:Destroy()
		end
	end
	local root = pet.PrimaryPart or pet:FindFirstChild("Root") or pet:FindFirstChildWhichIsA("BasePart", true)
	if not root then pet:Destroy() return nil end
	pet.PrimaryPart = root
	local rootToBottom = RootToVisibleBottom(pet, root)
	local _, fitted = pet:GetBoundingBox()
	local radius = math.max(fitted.X, fitted.Z) * 0.5
	local pos = ClampToPlot(plot, spot, radius)
	local yaw = Rng:NextNumber() * math.pi * 2
	pet:PivotTo(CFrame.new(pos.X, PlotTop(plot) + rootToBottom, pos.Z) * CFrame.Angles(0, yaw, 0))
	local now = workspace:GetServerTimeNow()
	pet:SetAttribute("PetName", petName)
	pet:SetAttribute("DisplayName", Catalog.DisplayNameOf(petName))
	pet:SetAttribute("Rarity", Catalog.RarityOf(petName))
	pet:SetAttribute("Owner", player.UserId)
	pet:SetAttribute("OwnerName", player.Name)
	pet:SetAttribute("Plot", plot.Name)
	pet:SetAttribute("PartCount", partCount)
	pet:SetAttribute("RoamRadius", radius)
	pet:SetAttribute("RoamGroundY", PlotTop(plot))
	pet:SetAttribute("RoamPhase", Rng:NextNumber() * math.pi * 2)
	pet:SetAttribute("RoamTo", Vector3.new(pos.X, PlotTop(plot), pos.Z))
	pet:SetAttribute("RoamIdleUntil", now + Rng:NextNumber(0.5, 2))
	CollectionService:AddTag(pet, PET_TAG)
	pet.Parent = PetsFolderOf(plot)
	return pet
end

local function ClearPlotPets(plot)
	local folder = plot:FindFirstChild("Pets")
	if folder then folder:ClearAllChildren() end
end

--..API for BaseSaveService (2026-09-12): a saved pet comes back without a hatch, an admin reset clears them..--
do
	local ServerStorage = game:GetService("ServerStorage")
	local api = ServerStorage:FindFirstChild("PetHatchAPI") or Instance.new("Folder")
	api.Name = "PetHatchAPI"
	api.Parent = ServerStorage
	local spawn = api:FindFirstChild("SpawnPet") or Instance.new("BindableFunction")
	spawn.Name = "SpawnPet"
	spawn.OnInvoke = function(player, plot, petName, spot)
		if not (player and plot and plot.Parent and type(petName) == "string" and typeof(spot) == "Vector3") then return nil end
		return SpawnPet(player, plot, petName, spot)
	end
	spawn.Parent = api
	local clear = api:FindFirstChild("ClearPets") or Instance.new("BindableFunction")
	clear.Name = "ClearPets"
	clear.OnInvoke = function(plot)
		if plot and plot.Parent then ClearPlotPets(plot) end
		return true
	end
	clear.Parent = api
end

--..Hatching..--
local function Finish(player, token)
	local pending = Pending[player]
	if not pending then return end
	if token and pending.Token ~= token then return end
	Pending[player] = nil
	local plot = pending.Plot
	if plot and plot.Parent and plot:GetAttribute("Owner") == player.UserId then
		SpawnPet(player, plot, pending.Pet, pending.Spot)
	end
	Hatched[player] = (Hatched[player] or 0) + 1
	player:SetAttribute("PetsHatched", Hatched[player])
end

local function BeginReveal(player, plot, spot, eggName, look, forcedPet)
	local pool, key = Catalog.PoolOf(eggName)
	if not pool then
		warn("[PetHatchService] no pet pool for egg " .. tostring(eggName))
		return false
	end
	local pet = forcedPet
	if not pet or not pool[pet] then pet = Catalog.Roll(eggName, Rng) end
	TokenCounter += 1
	local token = TokenCounter
	Pending[player] = {Token = token, Plot = plot, Pet = pet, Spot = spot, EggName = eggName}
	PetHatch:FireClient(player, "Begin", {
		EggName = eggName;
		EggKey = key;
		EggDisplayName = look.DisplayName or (key);
		Scale = look.Scale or 1;
		Material = look.Material;
		Mutations = look.Mutations or "";
		Pet = pet;
		PetDisplayName = Catalog.DisplayNameOf(pet);
		Rarity = Catalog.RarityOf(pet);
		Percent = Catalog.PercentOf(eggName, pet);
		Chance = Catalog.ChanceText(eggName, pet);
	})
	task.delay(REVEAL_FALLBACK, function()
		if player.Parent then Finish(player, token) end
	end)
	print(("[PetHatchService] %s hatched %s (%s, %s%%) from a %s"):format(player.Name, pet, Catalog.RarityOf(pet), tostring(Catalog.PercentOf(eggName, pet)), key))
	return true
end

local function Hatch(player, egg)
	local eggName = egg:GetAttribute("EggName")
	local plot = PlotOf(player)
	if not plot then return end
	egg:SetAttribute("Hatching", true)
	local spot = egg:GetPivot().Position
	local look = {
		DisplayName = egg:GetAttribute("DisplayName");
		Scale = tonumber(egg:GetAttribute("Scale")) or 1;
		Material = egg:GetAttribute("Material");
		Mutations = egg:GetAttribute("Mutations");
	}
	if BeginReveal(player, plot, spot, eggName, look) then
		egg:Destroy()
	else
		egg:SetAttribute("Hatching", nil)
	end
end

--.. the owner standing on a ready egg
local function CheckEgg(egg, now)
	if not egg.Parent or egg:GetAttribute("Hatching") then return end
	local hatchAt = tonumber(egg:GetAttribute("HatchAt"))
	if not hatchAt or hatchAt > now then return end
	local owner = Players:GetPlayerByUserId(tonumber(egg:GetAttribute("Owner")) or 0)
	if not owner or Pending[owner] then return end
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hitbox = egg.PrimaryPart
	if not root or not hitbox then return end
	local rel = hitbox.CFrame:PointToObjectSpace(root.Position)
	local half = hitbox.Size * 0.5
	if math.abs(rel.X) <= half.X + STEP_MARGIN and math.abs(rel.Z) <= half.Z + STEP_MARGIN
		and rel.Y >= -half.Y - 2 and rel.Y <= half.Y + STEP_HEIGHT then
		Hatch(owner, egg)
	end
end

--..Loops..--
local triggerClock, planClock = 0, 0
RunService.Heartbeat:Connect(function(dt)
	triggerClock += dt
	planClock += dt
	if triggerClock >= TRIGGER_TICK then
		triggerClock = 0
		local now = workspace:GetServerTimeNow()
		for _, egg in ipairs(CollectionService:GetTagged(EGG_TAG)) do
			CheckEgg(egg, now)
		end
	end
	if planClock >= PLAN_TICK then
		planClock = 0
		local now = workspace:GetServerTimeNow()
		for _, plot in ipairs(PLOTS:GetChildren()) do
			local folder = plot:IsA("BasePart") and plot:FindFirstChild("Pets")
			if folder then
				for _, pet in ipairs(folder:GetChildren()) do
					if pet:IsA("Model") and now >= (tonumber(pet:GetAttribute("RoamIdleUntil")) or 0) then
						PlanLeg(pet, plot)
					end
				end
			end
		end
	end
end)

--..Wiring..--
PetHatch.OnServerEvent:Connect(function(player, action)
	if action == "Opened" then Finish(player) end
end)

for _, plot in ipairs(PLOTS:GetChildren()) do
	if plot:IsA("BasePart") then
		PetsFolderOf(plot)
		plot:GetAttributeChangedSignal("Owner"):Connect(function()
			if plot:GetAttribute("Owner") == nil then ClearPlotPets(plot) end
		end)
	end
end

Players.PlayerRemoving:Connect(function(player)
	Pending[player] = nil
	Hatched[player] = nil
end)

--..Studio dev hook..--
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("PetHatchDev"):Connect(function()
		local cmd = workspace:GetAttribute("PetHatchDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		workspace:SetAttribute("PetHatchDev", "")
		local player = Players:GetPlayers()[1]
		if cmd == "ready" then
			local now = workspace:GetServerTimeNow()
			for _, egg in ipairs(CollectionService:GetTagged(EGG_TAG)) do egg:SetAttribute("HatchAt", now) end
			print("[PetHatchService] dev: every placed egg is ready")
		elseif cmd == "clear" then
			for _, plot in ipairs(PLOTS:GetChildren()) do
				if plot:IsA("BasePart") then ClearPlotPets(plot) end
			end
		elseif cmd:sub(1, 6) == "hatch:" and player then
			local eggName, forced = cmd:sub(7):match("^([^:]+):?(.*)$")
			local plot = PlotOf(player)
			if plot and not Pending[player] then
				local spot = plot.CFrame:PointToWorldSpace(Vector3.new(0, 0, 0))
				BeginReveal(player, plot, Vector3.new(spot.X, PlotTop(plot), spot.Z), eggName, {}, forced ~= "" and forced or nil)
			end
		elseif cmd:sub(1, 6) == "spawn:" and player then
			local plot = PlotOf(player)
			if plot then
				local spot = plot.CFrame:PointToWorldSpace(Vector3.new(0, 0, 0))
				SpawnPet(player, plot, cmd:sub(7), Vector3.new(spot.X, PlotTop(plot), spot.Z))
			end
		end
	end)
end

print(("[PetHatchService] ready: %d pet models, %d egg pools"):format(#PetsAssets:GetChildren(), (function() local n = 0 for _ in pairs(Catalog.EGGS) do n += 1 end return n end)()))
