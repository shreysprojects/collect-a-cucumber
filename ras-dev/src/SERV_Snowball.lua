--[[---------------------------------------DESCRIPTION------------------------------------------
	Picks the first snowball from Storage/Snowballs, attaches Templates collision,
	and tells the client to follow it with the camera. Rolling over SnowPatches
	drains snow into the ball and scales it up.

--------------------------------------------------------------------------------------------]]--

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local SNOW_TAG = "MountainSnow"

local MODULE = {}
local m_api = {}
local m_sapi = {}
local sself = m_sapi

function MODULE.new(r_sapi)
	sself = r_sapi
	sself.SNOWBALLS = sself.SNOWBALLS or {}
	return m_api, m_sapi
end

local COLLISION_NAMES = {
	BallCollision = true,
	CollisionTemplate = true,
	Collision = true,
}

local function collectTemplates()
	local folder = ServerStorage.Assets.Storage:FindFirstChild(mountainConfig.LAUNCH.StorageFolder)
	if not folder then
		return {}
	end

	local templates = {}
	for _, child in folder:GetChildren() do
		if COLLISION_NAMES[child.Name] then
			continue
		end
		if child:IsA("Model") or child:IsA("BasePart") then
			table.insert(templates, child)
		end
	end
	table.sort(templates, function(a, b)
		return a.Name < b.Name
	end)
	return templates
end

local function isCollisionAsset(instance)
	if not instance then
		return false
	end
	if not (instance:IsA("BasePart") or instance:IsA("Model")) then
		return false
	end
	if COLLISION_NAMES[instance.Name] then
		return true
	end
	return string.find(string.lower(instance.Name), "collision", 1, true) ~= nil
end

local function findCollisionTemplate()
	local name = mountainConfig.LAUNCH.CollisionTemplate
	local folders = {
		ServerStorage.Assets:FindFirstChild("Templates"),
		ServerStorage:FindFirstChild("Templates"),
		ServerStorage.Assets.Storage:FindFirstChild("Templates"),
		ServerStorage.Assets.Storage:FindFirstChild(mountainConfig.LAUNCH.StorageFolder),
	}

	for _, folder in folders do
		if not folder then
			continue
		end

		local named = folder:FindFirstChild(name, true)
		if named and (named:IsA("BasePart") or named:IsA("Model")) then
			return named
		end

		for _, child in folder:GetDescendants() do
			if isCollisionAsset(child) then
				return child
			end
		end

		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") or child:IsA("Model") then
				return child
			end
			if child:IsA("Folder") then
				for _, nested in child:GetChildren() do
					if nested:IsA("BasePart") or nested:IsA("Model") then
						return nested
					end
				end
			end
		end
	end

	return nil
end

local function getRootPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart
		end
		return instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function collectParts(instance)
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, desc in instance:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end
	return parts
end

local function disableVisualCollision(clone)
	for _, part in collectParts(clone) do
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.Massless = true
	end
end

local function attachCollision(clone, template)
	local collision = template:Clone()
	collision.Name = "BallCollision"
	collision.Parent = clone

	local root = getRootPart(collision)
	if not root then
		collision:Destroy()
		return nil
	end

	if collision:IsA("Model") then
		collision:PivotTo(clone:GetPivot())
	else
		collision.CFrame = clone:GetPivot()
	end

	for _, part in collectParts(collision) do
		part.Anchored = false
		part.CanCollide = true
		part.Massless = false
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end

	for _, part in collectParts(clone) do
		if part:IsDescendantOf(collision) or part == collision then
			continue
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = root
	end

	if clone:IsA("Model") then
		clone.PrimaryPart = root
	end

	return root
end

local function prepareBody(clone, collisionTemplate)
	if collisionTemplate then
		disableVisualCollision(clone)
		return attachCollision(clone, collisionTemplate)
	end

	local parts = collectParts(clone)
	local root = getRootPart(clone)
	if clone:IsA("Model") and root then
		clone.PrimaryPart = root
	end

	for _, part in parts do
		part.Anchored = false
		part.CanCollide = true
		part.Massless = false
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end

	return root
end

local patchBases = setmetatable({}, { __mode = "k" })
local growConnection = nil

local function sphereVolume(radius)
	return (4 / 3) * math.pi * radius ^ 3
end

local function getModel(state)
	return state.Model or state
end

local function ancestorHasType(instance, attachmentType)
	local current = instance
	while current and current ~= workspace do
		if current:GetAttribute("AttachmentType") == attachmentType then
			return true
		end
		current = current.Parent
	end
	return false
end

local function sphereHitsPart(center, radius, part)
	local localPoint = part.CFrame:PointToObjectSpace(center)
	local half = part.Size * 0.5
	local closest = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return (localPoint - closest).Magnitude <= radius
end

local function getPatchBase(part)
	local cached = patchBases[part]
	if cached then
		return cached
	end

	cached = {
		Size = part.Size,
		CFrame = part.CFrame,
		Original = part:GetAttribute("SnowOriginal") or part:GetAttribute("SnowAmount") or 1,
	}
	patchBases[part] = cached
	return cached
end

local function hidePatch(part)
	getPatchBase(part)
	part:SetAttribute("SnowAmount", 0)
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
end

local function restoreSnow()
	for _, part in CollectionService:GetTagged(SNOW_TAG) do
		if not part:IsA("BasePart") or not part.Parent then
			continue
		end

		local original = part:GetAttribute("SnowOriginal")
		if type(original) ~= "number" then
			original = part:GetAttribute("SnowAmount") or 1
		end

		local base = getPatchBase(part)
		part.Size = base.Size
		part.CFrame = base.CFrame
		part.Transparency = 0
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part:SetAttribute("SnowAmount", original)
	end
end

local function collectSnow(state)
	local launch = mountainConfig.LAUNCH
	if not workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME) then
		return
	end

	local collectRadius = state.StartRadius * state.Scale + launch.GrowCollectPadding
	local gained = 0

	for _, part in CollectionService:GetTagged(SNOW_TAG) do
		local remaining = part:GetAttribute("SnowAmount")
		if type(remaining) ~= "number" or remaining <= 0 then
			continue
		end
		if not mountainConfig.SNOW.CollectStartPlatform and ancestorHasType(part, mountainConfig.Attachment.StartPlatform) then
			continue
		end
		if not sphereHitsPart(state.Root.Position, collectRadius, part) then
			continue
		end

		gained += remaining
		hidePatch(part)
	end

	if gained <= 0 then
		return
	end

	local maxVolume = sphereVolume(state.StartRadius * launch.GrowMaxScale)
	state.Volume = math.min(maxVolume, state.Volume + gained * launch.GrowVolumePerSnow)
	state.TargetScale = math.clamp(
		(state.Volume / math.max(state.StartVolume, 0.01)) ^ (1 / 3),
		1,
		launch.GrowMaxScale
	)
	state.Scale = state.TargetScale
	state.Model:SetAttribute("TargetSnowScale", state.TargetScale)
end

local function streamAround(player, root)
	if not player or not player.Parent or not root or not root.Parent then
		return
	end

	local ahead = root.Position + root.AssemblyLinearVelocity * 0.8
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(ahead)
		end)
	end)
end

-- Run geometry for the race progress bar: origin/axis from the StartPlatform root,
-- total = along-axis distance to the furthest piece Exit. Cached per mountain.
function m_sapi:GetRun()
	local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	if not mountain then
		return nil
	end
	local cached = sself.RUN
	if cached and cached.Mountain == mountain then
		return cached
	end
	local startPiece = sself:GetStartPlatform()
	local root = startPiece and startPiece:FindFirstChild("Root")
	if not root then
		return nil
	end
	local axis = root.CFrame.LookVector
	axis = Vector3.new(axis.X, 0, axis.Z)
	if axis.Magnitude < 0.05 then
		axis = Vector3.new(0, 0, -1)
	end
	axis = axis.Unit
	local total = 0
	for _, piece in mountain:GetChildren() do
		local pieceRoot = piece:FindFirstChild("Root")
		local exit = pieceRoot and pieceRoot:FindFirstChild("Exit")
		if exit then
			total = math.max(total, (exit.WorldPosition - root.Position):Dot(axis))
		end
	end
	mountain:SetAttribute("RunLength", math.floor(total))
	sself.RUN = { Mountain = mountain, Origin = root.Position, Axis = axis, Total = total }
	return sself.RUN
end

local function updateDistance(player, state)
	local run = sself:GetRun()
	if not run or not player.Parent then
		return
	end
	local along = (state.Root.Position - run.Origin):Dot(run.Axis)
	local distance = math.floor(math.clamp(along, 0, run.Total))
	if player:GetAttribute("Distance") ~= distance then
		player:SetAttribute("Distance", distance)
	end
end

local function tickSnowballs(_dt)
	local any = false
	for player, state in sself.SNOWBALLS do
		if typeof(state) ~= "table" or not state.Root or not state.Root.Parent then
			sself.SNOWBALLS[player] = nil
			continue
		end

		any = true
		collectSnow(state)
		if os.clock() - (state.LastDistance or 0) >= 0.15 then
			state.LastDistance = os.clock()
			updateDistance(player, state)
		end
		if os.clock() - (state.LastStream or 0) >= 0.45 then
			state.LastStream = os.clock()
			streamAround(player, state.Root)
		end
	end

	if not any then
		restoreSnow()
		if growConnection then
			growConnection:Disconnect()
			growConnection = nil
		end
	end
end

local function ensureGrowLoop()
	if growConnection then
		return
	end
	growConnection = RunService.Heartbeat:Connect(tickSnowballs)
end

local function setReplicationFocus(player, part)
	if not player or not player.Parent then
		return
	end
	pcall(function()
		player.ReplicationFocus = part
	end)
end

function m_sapi:ClearSnowball(player)
	setReplicationFocus(player, nil)
	local current = sself.SNOWBALLS[player]
	if current then
		local model = getModel(current)
		if typeof(model) == "Instance" and model.Parent then
			model:Destroy()
		end
		sself.SNOWBALLS[player] = nil
	end

	for _, state in sself.SNOWBALLS do
		if typeof(state) == "table" and state.Root and state.Root.Parent then
			return
		end
	end
	restoreSnow()
end

function m_api:StopSnowball(player)
	sself:ClearSnowball(player)
	ReplicatedStorage.ReEvent:FireClient(player, "UnbindSnowballCamera")
	return true
end

-- The riding client reports props its ball rolled through (CLIENT_SnowballFX).
-- We confirm the ball was near it, flag it Smashed (every client fades it) and remove it.
function m_api:SmashProp(player, model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.Parent then
		return false
	end
	if not CollectionService:HasTag(model, mountainConfig.PROPS.Tag) or model:GetAttribute("Smashed") then
		return false
	end
	local state = sself.SNOWBALLS[player]
	if typeof(state) ~= "table" or not state.Root or not state.Root.Parent then
		return false
	end
	local ok, pivot = pcall(model.GetPivot, model)
	if not ok then
		return false
	end
	local reach = state.StartRadius * (state.Scale or 1) + (model:GetAttribute("PropRadius") or 4) + mountainConfig.SMASH.ServerReach
	if (pivot.Position - state.Root.Position).Magnitude > reach then
		return false
	end

	model:SetAttribute("Smashed", true)
	model:SetAttribute("SmashedBy", player.Name)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CanQuery = false
			desc.CanCollide = false
		end
	end
	if state.Model and state.Model.Parent then
		state.Model:SetAttribute("SmashCount", (state.Model:GetAttribute("SmashCount") or 0) + 1)

		-- Server-side combo (the client shows its own immediate counter; this one is
		-- the authoritative value for scoring later).
		local now = os.clock()
		if now - (state.LastSmash or 0) > (mountainConfig.SMASH.ComboWindow or 2.5) then
			state.Combo = 0
		end
		state.Combo = (state.Combo or 0) + 1
		state.LastSmash = now
		state.BestCombo = math.max(state.BestCombo or 0, state.Combo)
		state.Model:SetAttribute("Combo", state.Combo)
		state.Model:SetAttribute("BestCombo", state.BestCombo)
	end
	task.delay(mountainConfig.PROPS.FadeTime + 0.5, function()
		if model.Parent then
			model:Destroy()
		end
	end)
	return true
end

function m_api:Launch(player, requestedSpeed)
	local templates = collectTemplates()
	if #templates == 0 then
		warn("[SERVER]: No snowballs in Storage/" .. mountainConfig.LAUNCH.StorageFolder)
		return false
	end

	local padModel = sself:GetLaunchPlatform()
	if padModel and not sself:IsPlayerOnLaunchPad(player) then
		return false
	end

	local spawnCF, downhill
	if padModel then
		spawnCF, downhill = sself:GetPlayerLaunchCFrame(player)
	end
	if not spawnCF then
		spawnCF, downhill = sself:GetMountainLaunchCFrame()
	end
	if not spawnCF then
		spawnCF = sself:GetMountainSpawnCFrame()
	end
	if not spawnCF then
		warn("[SERVER]: Cannot launch; StartPlatform spawn is missing")
		return false
	end
	downhill = downhill or spawnCF.LookVector

	sself:ClearSnowball(player)

	local launch = mountainConfig.LAUNCH
	local collisionTemplate = findCollisionTemplate()
	if collisionTemplate then
		print("[SERVER]: Ball collision:", collisionTemplate:GetFullName())
	else
		warn("[SERVER]: Ball collision template not found in Assets.Templates (expected", launch.CollisionTemplate, ")")
	end

	local template = templates[1]
	local clone = template:Clone()
	clone.Name = player.Name .. "_Snowball"

	local folder = workspace:FindFirstChild("ActiveSnowballs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ActiveSnowballs"
		folder.Parent = workspace
	end
	clone.Parent = folder
	if clone:IsA("Model") then
		clone.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end

	local root = prepareBody(clone, collisionTemplate)
	if not root then
		warn("[SERVER]: Snowball has no BasePart:", template.Name)
		clone:Destroy()
		return false
	end

	-- The ride ball is smaller than the template (LAUNCH.BallScale).
	local ballScale = launch.BallScale or 1
	if ballScale ~= 1 then
		if clone:IsA("Model") then
			clone:ScaleTo(clone:GetScale() * ballScale)
		elseif clone:IsA("BasePart") then
			clone.Size *= ballScale
		end
	end

	-- Snow absorbs impacts: a softer bounce than the default 0.5 elasticity.
	do
		local current = root.CurrentPhysicalProperties
		root.CustomPhysicalProperties = PhysicalProperties.new(
			current.Density,
			current.Friction,
			launch.Elasticity or 0.35,
			current.FrictionWeight,
			launch.ElasticityWeight or 3
		)
	end

	local radius = math.max(root.Size.X, root.Size.Y, root.Size.Z) / 2
	clone:PivotTo(spawnCF + spawnCF.UpVector * (radius + 0.2))
	clone:SetAttribute("SnowScale", 1)
	clone:SetAttribute("TargetSnowScale", 1)
	clone:SetAttribute("StartRadius", radius)
	clone:SetAttribute("BaseScale", if clone:IsA("Model") then clone:GetScale() else 1)
	clone:SetAttribute("BaseDensity", root.CurrentPhysicalProperties.Density)

	pcall(function()
		root:SetNetworkOwner(player)
	end)
	setReplicationFocus(player, root)
	streamAround(player, root)
	player:SetAttribute("Distance", 0) -- race progress marker back to the start

	-- The client sends the hold charge (0..1); it maps onto MinSpeed..MaxSpeed.
	-- Anything above 1 is treated as a raw speed for older callers.
	local speed = launch.ThrustSpeed
	if type(requestedSpeed) == "string" then
		requestedSpeed = tonumber(requestedSpeed)
	end
	if type(requestedSpeed) == "number" then
		local charge = launch.Charge
		if charge and requestedSpeed <= 1 then
			local fraction = math.clamp(requestedSpeed, 0, 1)
			speed = charge.MinSpeed + (charge.MaxSpeed - charge.MinSpeed) * fraction
			clone:SetAttribute("LaunchCharge", fraction)
		else
			speed = requestedSpeed
		end
	end
	speed = math.clamp(speed, 1, 500)
	clone:SetAttribute("LaunchSpeed", speed)

	local look = downhill.Unit
	root.AssemblyLinearVelocity = look * speed + Vector3.yAxis * launch.UpSpeed
	root.AssemblyAngularVelocity = spawnCF.RightVector * (8 * speed / math.max(launch.ThrustSpeed, 1))

	local mass = root.AssemblyMass
	local force = Instance.new("VectorForce")
	force.Name = "LaunchThrust"
	force.Attachment0 = Instance.new("Attachment")
	force.Attachment0.Name = "ThrustAttachment"
	force.Attachment0.Parent = root
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = look * mass * speed * (80 / math.max(launch.ThrustSpeed, 1))
	force.Parent = root

	task.delay(launch.ThrustDuration, function()
		if force.Parent then
			force:Destroy()
		end
	end)

	sself.SNOWBALLS[player] = {
		Model = clone,
		Root = root,
		StartRadius = radius,
		StartVolume = sphereVolume(radius),
		Volume = sphereVolume(radius),
		Scale = 1,
		TargetScale = 1,
		BaseScale = if clone:IsA("Model") then clone:GetScale() else 1,
		BaseSize = if clone:IsA("BasePart") then clone.Size else nil,
		BaseDensity = root.CurrentPhysicalProperties.Density,
	}
	ensureGrowLoop()
	ReplicatedStorage.ReEvent:FireClient(player, "BindSnowballCamera", clone)
	return true
end

return MODULE

