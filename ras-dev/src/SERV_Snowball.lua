--[[---------------------------------------DESCRIPTION------------------------------------------
	Picks the equipped snowball from Storage/Snowballs, attaches Templates collision,
	and tells the client to follow it with the camera. Classic is granted on join
	and used until the player equips another owned ball.

	Rolling carves the snow: every Carve.Interval the server finds the ball's
	ground contact, removes the exposed snow layer inside a footprint the width
	of the ball, and turns what it actually removed into growth and rewards.
	Snow and smash rewards are scaled by the equipped snowball × launcher
	multiplier, and that same multiplier lengthens the launch.
	The riding client reports its own contact point (CarveSnow) so a fast ride
	cannot outrun the server's view of the roll; that request is validated
	against the server's ball position before it is used.

	Reaching FinishPlatform parks the ball in front of it and keeps the chase
	camera on the ball, then unlocks the next mountain and teleports them there.

--------------------------------------------------------------------------------------------]]--

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local mountainPlaces = require(ReplicatedStorage.Assets.Modules.Shared.MountainPlaces)()
local playerProgress = require(ReplicatedStorage.Assets.Modules.Shared.PlayerProgress)()
local snowField = require(ServerStorage.Modules.SnowField)

local MODULE = {}
local m_api = {}
local m_sapi = {}
local sself = m_sapi

function MODULE.new(r_sapi)
	sself = r_sapi
	sself.SNOWBALLS = sself.SNOWBALLS or {}
	sself.MountainFinishing = sself.MountainFinishing or {}
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

-- "Candy_Cane" / "Candy Cane" -> "candycane": no order prefix, case, spaces or separators.
local function compactAssetName(name)
	if type(name) ~= "string" then
		return ""
	end
	local trimmed = string.gsub(string.lower(name), "^%d+[%s_%-]*", "")
	return (string.gsub(trimmed, "[^%w]", ""))
end

local function isSnowballAsset(instance)
	if not instance then
		return false
	end
	if COLLISION_NAMES[instance.Name] then
		return false
	end
	if string.find(string.lower(instance.Name), "collision", 1, true) then
		return false
	end
	return instance:IsA("Model") or instance:IsA("BasePart")
end

local function namedSnowballTemplate(folder, name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local named = folder:FindFirstChild(name)
	if named and isSnowballAsset(named) then
		return named
	end
	local want = compactAssetName(name)
	if want == "" then
		return nil
	end
	for _, child in folder:GetChildren() do
		if isSnowballAsset(child) and compactAssetName(child.Name) == want then
			return child
		end
	end
	return nil
end

local missingWarned = {}

-- Catalog Asset names the model; display names can differ ("Candy Cane").
-- A snowball with no model falls back to the starter's, with one warning.
local function findSnowballTemplate(snowballName)
	local folder = ServerStorage.Assets.Storage:FindFirstChild(mountainConfig.LAUNCH.StorageFolder)
	if not folder then
		return nil
	end

	local catalog = sself.DEF_GVARS.Snowballs
	local info = catalog:GetByName(snowballName)
	local found = namedSnowballTemplate(folder, info and info.Asset) or namedSnowballTemplate(folder, snowballName)
	if found then
		return found
	end

	local key = tostring(snowballName)
	if not missingWarned[key] then
		missingWarned[key] = true
		warn("[SERVER]: No snowball model for", key, "- using the starter snowball")
	end
	local starter = catalog:GetByOrder(1)
	return (starter and namedSnowballTemplate(folder, starter.Asset)) or collectTemplates()[1]
end

local function resolveSnowball(requestedName)
	local catalog = sself.DEF_GVARS.Snowballs
	if type(requestedName) == "string" then
		local named = catalog:GetByName(requestedName)
		if named then
			return named
		end
	end
	return catalog:GetByOrder(1)
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
		part.CollisionGroup = mountainConfig.PHYSICS.SnowballGroup
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
		part.CollisionGroup = mountainConfig.PHYSICS.SnowballGroup
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end

	return root
end

local growConnection = nil

local function getModel(state)
	return state.Model or state
end

local function ballRadius(state)
	return state.StartRadius * (state.Scale or 1)
end

-- The cleared trail is as wide as the ball unless Carve.Width overrides it.
local function carveWidth(state)
	local carve = mountainConfig.SNOW.Carve
	local width = carve.Width or 0
	if width <= 0 then
		width = ballRadius(state) * 2 * (carve.WidthScale or 1) + (carve.WidthPadding or 0) * 2
	end
	return width
end

-- Scale for the snow eaten so far: fast at first, then ever slower, never capped
-- (LAUNCH.GrowStep / GrowDecay; the rate decays exponentially with the scale reached).
local function growthScale(snow)
	local launch = mountainConfig.LAUNCH
	local decay = math.max(tonumber(launch.GrowDecay) or 1.9, 0.05)
	local step = math.max(tonumber(launch.GrowStep) or 0.18, 0)
	return 1 + decay * math.log(1 + math.max(snow, 0) * step / decay)
end

-- Growth is driven by the snow that was actually removed, so a pass over bare
-- track adds nothing.
local function applySnow(state, gained)
	if gained <= 0 then
		return 0
	end

	state.Snow = (state.Snow or 0) + gained
	state.TargetScale = growthScale(state.Snow)
	state.Scale = state.TargetScale
	if state.Model and state.Model.Parent then
		state.Model:SetAttribute("TargetSnowScale", state.TargetScale)
	end
	return gained
end

-- One authoritative removal step. `contact` is an optional client-reported
-- ground point; it is only ever used as a ray origin, so the surface the carve
-- lands on is always one the server raycast itself.
local function carveSnow(state, contact)
	if not state.Root or not state.Root.Parent then
		return 0
	end

	local carve = mountainConfig.SNOW.Carve
	local lift = carve.SampleLift or 4
	local origin, reach
	if contact then
		origin = contact + Vector3.yAxis * lift
		reach = lift + (carve.GroundProbe or 2.5)
	else
		origin = state.Root.Position
		reach = ballRadius(state) + (carve.GroundProbe or 2.5)
	end

	local removed, point = snowField.Carve({
		Origin = origin,
		Reach = reach,
		Width = carveWidth(state),
		Depth = carve.Depth,
		From = state.CarveFrom,
	})

	-- Airborne: drop the anchor so the next landing does not carve a line
	-- through everything the ball flew over.
	state.CarveFrom = point
	return applySnow(state, removed)
end

local function runMultiplier(player, state)
	if state and type(state.Multiplier) == "number" and state.Multiplier >= 1 then
		return state.Multiplier
	end
	local data = sself:GetPlayerProgress(player)
	if not data then
		return 1
	end
	return playerProgress.EquipmentMultiplier(data.EquippedSnowball, data.EquippedLauncher)
end

-- Tiles are worth a fraction of a snow unit each, so the remainder is carried
-- instead of being floored away (and never awarded twice).
local function rewardSnow(player, state, gained)
	if gained <= 0 then
		return
	end

	state.SnowCollected = (state.SnowCollected or 0) + gained
	local carry = (state.RewardCarry or 0) + gained
	local whole = math.floor(carry)
	state.RewardCarry = carry - whole
	if whole <= 0 then
		return
	end

	local xp, coins = playerProgress.RewardsForSnow(whole)
	local multiplier = runMultiplier(player, state)
	sself:AwardProgress(player, xp * multiplier, coins * multiplier)
end

-- XP for the studs rolled since the last distance tick (PlayerProgress.DISTANCE_XP per
-- stud, times the run multiplier). The fraction carries, so nothing is floored away.
local function rewardDistance(player, state, studs)
	if studs <= 0 then
		return
	end
	local carry = (state.DistanceXpCarry or 0) + playerProgress.RewardsForDistance(studs) * runMultiplier(player, state)
	local whole = math.floor(carry)
	state.DistanceXpCarry = carry - whole
	if whole > 0 then
		sself:AwardProgress(player, whole, 0)
	end
end

local function stepCarve(player, state, contact, minGap)
	local now = os.clock()
	if now - (state.LastCarve or 0) < minGap then
		return false
	end
	state.LastCarve = now
	rewardSnow(player, state, carveSnow(state, contact))
	return true
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
	local finishAt = nil
	for _, piece in mountain:GetChildren() do
		local pieceRoot = piece:FindFirstChild("Root")
		local exit = pieceRoot and pieceRoot:FindFirstChild("Exit")
		if exit then
			total = math.max(total, (exit.WorldPosition - root.Position):Dot(axis))
		end
		if piece:GetAttribute("AttachmentType") == mountainConfig.Attachment.FinishPlatform then
			local entrance = pieceRoot and pieceRoot:FindFirstChild(mountainConfig.SOCKETS.Entrance)
			if entrance then
				local along = (entrance.WorldPosition - root.Position):Dot(axis)
				finishAt = if finishAt then math.min(finishAt, along) else along
			end
		end
	end
	if not finishAt or finishAt < total * 0.5 then
		finishAt = total
	end
	local shown = math.floor(total + 1e-3)
	local designed = mountain:GetAttribute("Length")
	if type(designed) == "number" and designed > 0 and math.abs(total - designed) <= 2 then
		shown = designed
	end
	mountain:SetAttribute("RunLength", shown)
	sself.RUN = {
		Mountain = mountain,
		Origin = root.Position,
		Axis = axis,
		Total = total,
		FinishAt = finishAt or total,
	}
	return sself.RUN
end

local function finishEntranceAlong(finish, run)
	local root = finish:FindFirstChild(mountainConfig.SOCKETS.Root)
	local entrance = root and root:FindFirstChild(mountainConfig.SOCKETS.Entrance)
	local position = if entrance and entrance:IsA("Attachment") then entrance.WorldPosition else finish:GetPivot().Position
	return (position - run.Origin):Dot(run.Axis)
end

-- The riding client simulates the ball, so the server's copy can lag behind a
-- fast roll. Accept a finish report when that copy is close enough to the
-- finish that the ball could have reached it since the last physics update.
local function confirmFinish(state, point)
	local finish = sself:GetFinishPlatform()
	if not finish or not state.Root or not state.Root.Parent then
		return false
	end
	local padding = ballRadius(state) + 14
	if not mountainConfig.IsOnFinishPiece(finish, point, padding) then
		return false
	end

	local run = sself:GetRun()
	if not run or run.Total <= 0 then
		return (point - state.Root.Position).Magnitude <= 200
	end

	local speed = state.Root.AssemblyLinearVelocity.Magnitude
	local lead = math.clamp(speed * 0.2, 120, 1500)
	local ballAlong = (state.Root.Position - run.Origin):Dot(run.Axis)
	return ballAlong + lead >= finishEntranceAlong(finish, run) - 24
end

local function beginFinish(player, state)
	if not player or not player.Parent or state.Finishing or sself.MountainFinishing[player] then
		return
	end
	state.Finishing = true
	sself.MountainFinishing[player] = true
	if sself.EndLaunchPropRide then
		sself:EndLaunchPropRide(player)
	end
	task.spawn(function()
		local ok, err = pcall(function()
			sself:CompleteMountainRun(player)
		end)
		if ok then
			return
		end
		warn("[SERVER]: CompleteMountainRun failed:", err)
		sself.MountainFinishing[player] = nil
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and player.Parent then
			pcall(function()
				hrp:SetNetworkOwner(player)
			end)
		end
	end)
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
	if not state.Finishing then
		local recorded = state.RecordedDistance or 0
		if distance > recorded then
			sself:AddRolledDistance(player, distance - recorded)
			state.RecordedDistance = distance
			rewardDistance(player, state, distance - recorded)
		end
	end
	if not state.Finishing and run.Total > 0 and along >= (run.FinishAt or run.Total) - 4 then
		beginFinish(player, state)
	end
end

local function tickSnowballs(_dt)
	local any = false
	local interval = mountainConfig.SNOW.Carve.Interval or 0.05
	for player, state in sself.SNOWBALLS do
		if typeof(state) ~= "table" or not state.Root or not state.Root.Parent then
			sself.SNOWBALLS[player] = nil
			continue
		end

		any = true
		-- Fallback carve from the server's own view of the ball. The rider's
		-- CarveSnow reports share this throttle, so a reporting client drives
		-- the trail and this only fills in when those stop arriving.
		if not state.Finishing then
			stepCarve(player, state, nil, interval)
		end
		if os.clock() - (state.LastDistance or 0) >= 0.15 then
			state.LastDistance = os.clock()
			updateDistance(player, state)
		end
		if os.clock() - (state.LastStream or 0) >= 0.45 then
			state.LastStream = os.clock()
			streamAround(player, state.Root)
		end

		if not state.Finishing then
			local pos = state.Root.Position
			local padding = ballRadius(state) + 12
			local finish = sself:GetFinishPlatform()
			if finish and mountainConfig.FinishContact(finish, state.ServerPos or pos, pos, padding) then
				beginFinish(player, state)
			end
			state.ServerPos = pos
		end
	end

	if not any then
		snowField.RestoreAll()
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
	if sself.EndLaunchPropRide then
		sself:EndLaunchPropRide(player)
	end
	setReplicationFocus(player, nil)
	local current = sself.SNOWBALLS[player]
	if current then
		local model = getModel(current)
		if typeof(model) == "Instance" and model.Parent then
			model:Destroy()
		end
		sself.SNOWBALLS[player] = nil
	end
	-- RaceProgressGui draws the player's profile marker from this attribute.
	if player then
		player:SetAttribute("Distance", 0)
	end

	for _, state in sself.SNOWBALLS do
		if typeof(state) == "table" and state.Root and state.Root.Parent then
			return
		end
	end
	snowField.RestoreAll()
end

function m_api:StopSnowball(player)
	local state = sself.SNOWBALLS[player]
	if typeof(state) == "table" and not state.Finishing and state.Root and state.Root.Parent then
		-- Stopping on the finish (or rolling off it) still completes the mountain.
		local reached = false
		local run = sself:GetRun()
		if run and run.Total > 0 then
			local along = (state.Root.Position - run.Origin):Dot(run.Axis)
			reached = along >= (run.FinishAt or run.Total) - 8
		end
		if not reached then
			local finish = sself:GetFinishPlatform()
			reached = finish ~= nil and mountainConfig.IsOnFinishPiece(finish, state.Root.Position, ballRadius(state) + 24) == true
		end
		if reached then
			beginFinish(player, state)
			return true
		end
	end

	sself:ClearSnowball(player)
	ReplicatedStorage.ReEvent:FireClient(player, "UnbindSnowballCamera")
	return true
end

-- Rider says the ball reached FinishPlatform. Validated against the server ball.
function m_api:ReachFinish(player, point)
	if typeof(point) ~= "Vector3" or point ~= point then
		return false
	end

	local state = sself.SNOWBALLS[player]
	if typeof(state) ~= "table" or state.Finishing then
		return false
	end
	if not confirmFinish(state, point) then
		return false
	end

	beginFinish(player, state)
	return true
end

local function parkSnowball(player, standCF)
	local state = sself.SNOWBALLS[player]
	if typeof(state) ~= "table" or not state.Root or not state.Root.Parent then
		return false
	end

	local root = state.Root
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local parked = standCF + Vector3.yAxis * (ballRadius(state) + 1)
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	local model = getModel(state)
	if typeof(model) == "Instance" then
		if model:IsA("Model") then
			model:PivotTo(parked)
		else
			root.CFrame = parked
		end
		model:SetAttribute("Finishing", true)
		model:SetAttribute("FinishCFrame", parked)
		model:SetAttribute("FinishLook", standCF.LookVector)
	end
	return true
end

function m_sapi:CompleteMountainRun(player)
	if not player or not player.Parent then
		if player and sself.MountainFinishing then
			sself.MountainFinishing[player] = nil
		end
		return false
	end

	local standCF = sself:GetFinishStandCFrame()
	if standCF and player.Parent then
		pcall(function()
			player:RequestStreamAroundAsync(standCF.Position)
		end)
		if not player.Parent then
			sself.MountainFinishing[player] = nil
			return false
		end
		-- Keep the chase camera on the ball. Do not cut to the character.
		parkSnowball(player, standCF)
		ReplicatedStorage.ReEvent:FireClient(player, "HoldAtFinish", standCF)
	end

	task.wait(mountainConfig.FINISH.ArriveHold or 2)
	if not player.Parent then
		sself.MountainFinishing[player] = nil
		return false
	end

	local current = mountainPlaces.GetCurrentMountainId()
	local nextId = mountainConfig:GetNextMountain(current)
	if not nextId then
		sself:StopSnowball(player)
		if standCF then
			sself:PlaceCharacter(player.Character, standCF)
			ReplicatedStorage.ReEvent:FireClient(player, "StandAtFinish", standCF)
		end
		sself.MountainFinishing[player] = nil
		print("[SERVER]:", player.Name, "finished", current)
		return true
	end

	sself:UnlockMountain(player, nextId)
	local ok, err = sself:TravelToMountain(player, nextId)
	sself.MountainFinishing[player] = nil
	if not ok then
		sself:StopSnowball(player)
		if standCF then
			sself:PlaceCharacter(player.Character, standCF)
			ReplicatedStorage.ReEvent:FireClient(player, "StandAtFinish", standCF)
		end
		warn("[SERVER]:", player.Name, "finished", current, "but could not travel to", nextId .. ":", err)
	end
	return ok
end

-- The rider reports the ground contact under its own ball (CLIENT_SnowballFX).
-- The point is only accepted when it is close to where the server thinks the
-- ball is; the removal and the reward are worked out here either way.
function m_api:CarveSnow(player, point)
	if typeof(point) ~= "Vector3" or point.Magnitude ~= point.Magnitude then
		return false
	end

	local state = sself.SNOWBALLS[player]
	if typeof(state) ~= "table" or not state.Root or not state.Root.Parent then
		return false
	end

	local carve = mountainConfig.SNOW.Carve
	local reach = ballRadius(state) + (carve.ClientReach or 60)
	if (point - state.Root.Position).Magnitude > reach then
		return false
	end

	-- Half the interval, so a report that arrives a little early still lands;
	-- the swept carve fills in anything a dropped report would have missed.
	return stepCarve(player, state, point, (carve.Interval or 0.05) * 0.5)
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
	end

	-- Server-side combo (the client shows its own immediate counter; this one is
	-- the authoritative value for scoring).
	local now = os.clock()
	if now - (state.LastSmash or 0) > (mountainConfig.SMASH.ComboWindow or 2.5) then
		state.Combo = 0
	end
	state.Combo = (state.Combo or 0) + 1
	state.LastSmash = now
	state.BestCombo = math.max(state.BestCombo or 0, state.Combo)
	if state.Model and state.Model.Parent then
		state.Model:SetAttribute("Combo", state.Combo)
		state.Model:SetAttribute("BestCombo", state.BestCombo)
	end

	local category = model:GetAttribute("PropCategory") or "Default"
	local radius = model:GetAttribute("PropRadius") or 4
	local xp, coins = playerProgress.RewardsForSmash(category, radius, state.Combo)
	local multiplier = runMultiplier(player, state)
	sself:AwardProgress(player, xp * multiplier, coins * multiplier)
	task.delay(mountainConfig.PROPS.FadeTime + 0.5, function()
		if model.Parent then
			model:Destroy()
		end
	end)
	return true
end

function m_api:EquipSnowball(player, requestedName)
	if not player or type(requestedName) ~= "string" or requestedName == "" then
		return false
	end

	local info = sself.DEF_GVARS.Snowballs:GetByName(requestedName)
	if not info then
		return false
	end

	local data = sself:GetPlayerProgress(player)
	if not data or not playerProgress.SetEquippedSnowball(data, info.Name) then
		return false
	end
	data.Dirty = true
	sself:ReplicateProgress(player)
	return true
end

-- ReFunction: true, or false and a PlayerProgress.PurchaseInOrder reason for the shop to show.
function m_api:BuySnowball(player, requestedName)
	if not player or type(requestedName) ~= "string" or requestedName == "" then
		return false, "Invalid"
	end

	local catalog = sself.DEF_GVARS.Snowballs
	local info = catalog:GetByName(requestedName)
	if not info then
		return false, "Invalid"
	end

	local data = sself:GetPlayerProgress(player)
	if not data then
		return false, "Invalid"
	end
	local bought, reason = playerProgress.PurchaseInOrder(data, "UnlockedSnowballs", catalog.List, info.Name)
	if not bought then
		return false, reason
	end
	if playerProgress.EQUIP_ON_BUY then
		playerProgress.SetEquippedSnowball(data, info.Name)
	end
	data.Dirty = true
	sself:ReplicateProgress(player)
	return true
end

-- The client reports where its launcher let the ball go (the Seat / Muzzle point of the
-- launcher clip at its fire moment, ChargeController OnFire). The ride ball starts there when
-- that is believable: close to the character, nothing solid in between, above the floor.
-- Anything else (old clients, no clip, a bad point) keeps the ground spawn ahead of the pad.
local function launchOrigin(player, requested, radius)
	local settings = mountainConfig.LAUNCH.MuzzleSpawn
	if not (settings and settings.Enabled) or typeof(requested) ~= "Vector3" then
		return nil
	end
	if requested.X ~= requested.X or requested.Y ~= requested.Y or requested.Z ~= requested.Z then
		return nil
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	if (requested - hrp.Position).Magnitude > (settings.MaxDistance or 14) then
		return nil
	end
	local exclude = { character }
	local folder = workspace:FindFirstChild("ActiveSnowballs")
	if folder then
		table.insert(exclude, folder)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	pcall(function()
		params.CollisionGroup = settings.CollisionGroup or "Snowball"
	end)
	local from = hrp.Position + Vector3.yAxis * 1.5
	if workspace:Raycast(from, requested - from, params) then
		return nil -- a wall between the character and the launcher's muzzle
	end
	local lift = radius + (settings.FloorClearance or 0.05)
	local down = workspace:Raycast(requested + Vector3.yAxis * lift, Vector3.new(0, -(lift * 2 + 6), 0), params)
	if down and requested.Y - down.Position.Y < lift then
		requested = Vector3.new(requested.X, down.Position.Y + lift, requested.Z)
	end
	return requested
end

function m_api:Launch(player, requestedSpeed, requestedOrigin)
	if sself.MountainFinishing[player] then
		return false
	end

	local data = sself:GetPlayerProgress(player)
	local info = resolveSnowball((data and data.EquippedSnowball) or player:GetAttribute("EquippedSnowball"))
	local template = info and findSnowballTemplate(info.Name)
	if not template then
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

	local clone = template:Clone()
	clone.Name = player.Name .. "_Snowball"
	if info then
		clone:SetAttribute("EquippedName", info.Name)
	end

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
	-- Extra friction so a weak launch can actually roll to a stop.
	do
		local current = root.CurrentPhysicalProperties
		root.CustomPhysicalProperties = PhysicalProperties.new(
			current.Density,
			launch.Friction or current.Friction,
			launch.Elasticity or 0.35,
			launch.FrictionWeight or current.FrictionWeight,
			launch.ElasticityWeight or 3
		)
	end

	local radius = math.max(root.Size.X, root.Size.Y, root.Size.Z) / 2
	local origin = launchOrigin(player, requestedOrigin, radius)
	if origin then
		clone:PivotTo(spawnCF.Rotation + origin)
		clone:SetAttribute("LaunchOrigin", origin)
	else
		clone:PivotTo(spawnCF + spawnCF.UpVector * (radius + 0.2))
	end
	clone:SetAttribute("SnowScale", 1)
	clone:SetAttribute("TargetSnowScale", 1)
	clone:SetAttribute("StartRadius", radius)
	clone:SetAttribute("BaseScale", if clone:IsA("Model") then clone:GetScale() else 1)
	clone:SetAttribute("BaseDensity", root.CurrentPhysicalProperties.Density)
	local rideToken = string.format("%d:%d:%d", player.UserId, math.floor(os.clock() * 1000) % 1000000000, math.random(1, 1000000000))
	clone:SetAttribute("RideToken", rideToken)

	pcall(function()
		root:SetNetworkOwner(player)
	end)
	setReplicationFocus(player, root)
	streamAround(player, root)
	player:SetAttribute("Distance", 0) -- race progress marker at the start of the ride

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
	local gear = 1
	local earnings = 1
	local launchBoost = 1
	if data then
		gear = playerProgress.EquipmentMultiplier(data.EquippedSnowball, data.EquippedLauncher)
		local rebirths = data.Rebirths or 0
		earnings = playerProgress.EarningsMultiplier(rebirths)
		launchBoost = playerProgress.LaunchBoost(rebirths)
	end
	local launchPower = playerProgress.LaunchPower(gear)
	local baseSpeed = speed
	speed = math.clamp(baseSpeed * launchPower * launchBoost, 1, launch.MaxPoweredSpeed or 12000)
	clone:SetAttribute("LaunchSpeed", speed)
	-- Coast and loft follow throw speed. Rewards keep the full shop total.
	clone:SetAttribute("PowerMultiplier", launchPower)

	local look = downhill.Unit
	-- Starters follow the slope. A stronger throw levels out and lofts a short hop.
	local velocity = look * speed + Vector3.yAxis * (launch.UpSpeed or 0)
	local thrustDir = look
	if launchPower >= (launch.LoftFrom or 1.8) then
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		else
			flat = flat.Unit
		end
		local loft = math.min(launch.MaxLoft or 56, (launchPower - 1) * (launch.LoftPerMultiplier or 12))
		velocity = flat * speed + Vector3.yAxis * loft
		thrustDir = flat
	end
	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity = spawnCF.RightVector * (8 * baseSpeed / math.max(launch.ThrustSpeed, 1))

	local mass = root.AssemblyMass
	local duration = math.max(launch.ThrustDuration or 0.22, 0.08)
	local boost = launch.ThrustBoost or 0.22
	local force = Instance.new("VectorForce")
	force.Name = "LaunchThrust"
	force.Attachment0 = Instance.new("Attachment")
	force.Attachment0.Name = "ThrustAttachment"
	force.Attachment0.Parent = root
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = thrustDir * mass * speed * boost / duration
	force.Parent = root

	task.delay(duration, function()
		if force.Parent then
			force:Destroy()
		end
	end)

	sself.SNOWBALLS[player] = {
		Player = player,
		Model = clone,
		Root = root,
		StartRadius = radius,
		Snow = 0, -- snow units eaten (growth curve input; SnowCollected is the reward counter)
		Scale = 1,
		TargetScale = 1,
		BaseScale = if clone:IsA("Model") then clone:GetScale() else 1,
		BaseSize = if clone:IsA("BasePart") then clone.Size else nil,
		BaseDensity = root.CurrentPhysicalProperties.Density,
		Multiplier = gear * earnings,
		RideToken = rideToken,
	}
	if sself.BeginLaunchPropRide then
		sself:BeginLaunchPropRide(player, rideToken)
	end
	ensureGrowLoop()
	ReplicatedStorage.ReEvent:FireClient(player, "BindSnowballCamera", clone)
	return true
end

return MODULE

