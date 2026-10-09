-- Lava Portal: private Lava Run instances with persistent per-player cooldown.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local COOLDOWN_SECONDS = 60 * 60
local INSTANCE_ORIGIN = Vector3.new(-2000, 600, 7500)
local INSTANCE_SPACING = 650
local DATASTORE_NAME = "LavaPortalCooldown_v1"
local PORTAL_KEY = "Lava"
local BIOME_ZONE = "Volcano"
local PortalProgress = require(game:GetService("ServerStorage"):WaitForChild("PortalCucumberProgress"))
local PortalUnlockService = require(game:GetService("ServerStorage"):WaitForChild("PortalUnlockService"))
local cucumberDestroyed = game:GetService("ServerStorage"):WaitForChild("PortalCucumberDestroyed")

local portal = workspace:WaitForChild("Portals"):WaitForChild("Lava Portal")
local portalPlane = portal:WaitForChild("Portal Ilussion"):FindFirstChildWhichIsA("BasePart", true)
assert(portalPlane, "[LavaPortalService] Lava Portal has no touchable illusion part")

local template = game:GetService("ServerStorage"):WaitForChild("LavaRun")
local transitionRemotes = ReplicatedStorage:WaitForChild("StarterPortalRemotes")
local transition = transitionRemotes:WaitForChild("Transition")
local transitionReady = transitionRemotes:WaitForChild("TransitionReady")
local completion = ReplicatedStorage:WaitForChild("MinigameEffects"):WaitForChild("Completed")
local cancelRun = game:GetService("ServerStorage"):WaitForChild("MinigameSessionCancel")

local remotes = ReplicatedStorage:FindFirstChild("LavaPortalRemotes") or Instance.new("Folder")
remotes.Name = "LavaPortalRemotes"
remotes.Parent = ReplicatedStorage
local getStatus = remotes:FindFirstChild("GetStatus") or Instance.new("RemoteFunction")
getStatus.Name = "GetStatus"
getStatus.Parent = remotes
local statusChanged = remotes:FindFirstChild("StatusChanged") or Instance.new("RemoteEvent")
statusChanged.Name = "StatusChanged"
statusChanged.Parent = remotes
local intro = remotes:FindFirstChild("Intro") or Instance.new("RemoteEvent")
intro.Name = "Intro"
intro.Parent = remotes

local mapFolder = workspace:FindFirstChild("PlayerLavaRuns") or Instance.new("Folder")
mapFolder.Name = "PlayerLavaRuns"
mapFolder.Parent = workspace

local cooldownStore = DataStoreService:GetDataStore(DATASTORE_NAME)
local cooldowns, cooldownLoaded = {}, {}
local activeMaps, mapStates, touchBusy = {}, {}, {}
local slotByUser, freeSlots, nextSlot = {}, {}, 1

local function keyFor(player) return "Player_" .. player.UserId end
local function expiryFrom(value)
	if type(value) == "table" then return tonumber(value.nextReady) or 0 end
	return type(value) == "number" and value or 0
end
local function remainingFor(player)
	return math.max(0, (cooldowns[player.UserId] or 0) - os.time())
end
local function sendStatus(player, unavailable)
	if player.Parent then
		local paidUnlock = PortalUnlockService.HasCredit(player, PORTAL_KEY)
		statusChanged:FireClient(player, { remaining = paidUnlock and 0 or remainingFor(player), unavailable = unavailable == true or not PortalProgress.IsLoaded(player), cucumbersRemaining = paidUnlock and 0 or PortalProgress.Remaining(player, PORTAL_KEY) })
	end
end

--.. Absolute os.time() expiry in the DataStore: counts down across servers,
--.. rejoins, and offline time. Studio uses the SAME store — playtests behave
--.. exactly like production (RemoveAsync the key to reset while testing).
local function loadCooldown(player)
	local expiry = 0
	local ok, value = pcall(function() return cooldownStore:GetAsync(keyFor(player)) end)
	if not ok then
		warn("[LavaPortalService] Cooldown load failed", player, value)
		cooldownLoaded[player.UserId] = false
		sendStatus(player, true)
		return false
	end
	expiry = expiryFrom(value)
	cooldowns[player.UserId] = math.max(cooldowns[player.UserId] or 0, expiry)
	cooldownLoaded[player.UserId] = true
	sendStatus(player)
	return true
end

--.. armed by COMPLETING the lava run (not by entering); entry stays blocked
--.. until the countdown fully reaches zero
local function canEnter(player)
	if PortalUnlockService.HasCredit(player, PORTAL_KEY) then
		return true
	end
	if not cooldownLoaded[player.UserId] and not loadCooldown(player) then
		return false
	end
	return remainingFor(player) == 0 and PortalProgress.Remaining(player, PORTAL_KEY) == 0
end

local function startCooldown(player)
	local userId = player.UserId
	local expiry = os.time() + COOLDOWN_SECONDS
	cooldowns[userId] = math.max(cooldowns[userId] or 0, expiry)
	PortalProgress.Reset(player, PORTAL_KEY)
	local ok, err = false, nil
	for attempt = 1, 3 do
		ok, err = pcall(function()
			cooldownStore:UpdateAsync(keyFor(player), function(current)
				if expiryFrom(current) >= expiry then return current end
				return { nextReady = expiry }
			end)
		end)
		if ok then break end
		task.wait(attempt * 0.5)
	end
	if not ok then warn("[LavaPortalService] Cooldown save failed after retries", player, err) end
	sendStatus(player)
end

--.. completion cleanup mirror of PlayerRemoving: the completed map is spent
local function destroyMapFor(userId)
	local state = mapStates[userId]
	if state then
		state.alive = false
		for _, connection in ipairs(state.connections) do pcall(function() connection:Disconnect() end) end
	end
	if activeMaps[userId] then activeMaps[userId]:Destroy() end
	activeMaps[userId], mapStates[userId] = nil, nil
end

local function allocateSlot(player)
	if slotByUser[player.UserId] then return slotByUser[player.UserId] end
	local slot = table.remove(freeSlots)
	if not slot then slot = nextSlot nextSlot += 1 end
	slotByUser[player.UserId] = slot
	return slot
end

local function moveCharacter(player, targetCFrame)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	character:PivotTo(targetCFrame * CFrame.Angles(0, math.pi, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

local function waitForTransitionCover(player)
	local token = HttpService:GenerateGUID(false)
	player:SetAttribute("PortalTransitionReady", nil)
	transition:FireClient(player, "In", token)

	local deadline = os.clock() + 4
	while player.Parent and os.clock() < deadline do
		if player:GetAttribute("PortalTransitionReady") == token then
			return true
		end
		RunService.Heartbeat:Wait()
	end

	if player.Parent then
		transition:FireClient(player, "Out")
	end
	return false
end

local function transitionTeleport(player, targetCFrame, streamPosition, _introMapName)
	if not waitForTransitionCover(player) then
		return false
	end
	if streamPosition then pcall(function() player:RequestStreamAroundAsync(streamPosition, 8) end) end
	local moved = moveCharacter(player, targetCFrame)
	task.wait(0.12)
	if player.Parent then
		transition:FireClient(player, "Out")
	end
	return moved
end

local function ownerFromHit(player, hit)
	local character = hit and hit:FindFirstAncestorOfClass("Model")
	if character and Players:GetPlayerFromCharacter(character) == player then
		return character, character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
	end
end

local function lavaBurst(parent)
	local attachment = Instance.new("Attachment")
	attachment.Parent = parent
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxassetid://241594314"
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 235, 80), Color3.fromRGB(255, 45, 5))
	particles.LightEmission = 0.8
	particles.Lifetime = NumberRange.new(0.25, 0.65)
	particles.Speed = NumberRange.new(10, 23)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Drag = 4
	particles.Rate = 0
	particles.Parent = attachment
	particles:Emit(24)
	Debris:AddItem(attachment, 1)
end

local function connectRagdoll(player, state, object, impulseOrigin)
	for _, part in ipairs(object:IsA("BasePart") and { object } or object:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanTouch = true
			table.insert(state.connections, part.Touched:Connect(function(hit)
				local _, humanoid, root = ownerFromHit(player, hit)
				if not humanoid or not root or state.ragdolled then return end
				state.ragdolled = true
				humanoid.PlatformStand = true
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
				local origin = impulseOrigin and impulseOrigin() or part.Position
				local away = root.Position - origin
				if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
				root:ApplyImpulse((away.Unit * 44 + Vector3.new(0, 34, 0)) * root.AssemblyMass)
				lavaBurst(root)
				task.delay(1.4, function()
					if humanoid.Parent and humanoid.Health > 0 then
						humanoid.PlatformStand = false
						humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
					end
					state.ragdolled = false
				end)
			end))
		end
	end
end

local function configureMap(player, map)
	local state = { connections = {}, alive = true, ragdolled = false, finished = false }
	mapStates[player.UserId] = state
	local spawnLocation = map:WaitForChild("SpawnLocation")
	spawnLocation.Enabled = false
	spawnLocation.CanCollide = false
	spawnLocation.Transparency = 1
	map.RedSpawn.Enabled = false
	map.BlueSpawn.Enabled = false

	local function resetToSpawn(hit, withBurst)
		local character, humanoid, root = ownerFromHit(player, hit)
		if not character or not humanoid or not root or humanoid.Health <= 0 or state.resetting then
			return false
		end
		state.resetting = true
		if withBurst then lavaBurst(root) end
		humanoid.PlatformStand = false
		state.ragdolled = false
		character:PivotTo(spawnLocation.CFrame * CFrame.new(0, 4, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		task.delay(0.7, function()
			state.resetting = false
		end)
		return true
	end

	for _, spinner in ipairs(map.Spinners:GetChildren()) do
		connectRagdoll(player, state, spinner, function() return spinner:GetPivot().Position end)
	end
	local windmill = map.Obby:WaitForChild("SpinPart")
	connectRagdoll(player, state, windmill)

	local walls = {}
	for _, groupName in ipairs({ "SmashWalls1", "SmashWalls2", "SmashWalls3" }) do
		for _, wall in ipairs(map.Obby[groupName]:GetChildren()) do
			if wall:IsA("BasePart") then
				local killBrick = wall:FindFirstChild("KillBrick")
				local wallPoint = wall:FindFirstChild("WallPoint")
				local killPoint = wallPoint and wallPoint:FindFirstChild("KillPoint")
				if killBrick and wallPoint and killPoint then
					killBrick.CanTouch = true
					table.insert(state.connections, killBrick.Touched:Connect(function(hit)
						resetToSpawn(hit, true)
					end))
					table.insert(walls, {
						number = tonumber(string.match(wall.Name, "%d+")) or 0,
						wall = wall,
						kill = killBrick,
						wallTarget = wallPoint.Position,
						killTarget = killPoint.Position,
						wallHome = wall.Position,
						killHome = killBrick.Position,
					})
				end
			end
		end
	end

	local heartbeat = RunService.Heartbeat:Connect(function(deltaTime)
		if not state.alive or not map.Parent then return end
		for _, spinner in ipairs(map.Spinners:GetChildren()) do
			if spinner:IsA("Model") then spinner:PivotTo(spinner:GetPivot() * CFrame.Angles(0, math.rad(88) * deltaTime, 0)) end
		end
		windmill.CFrame *= CFrame.Angles(math.rad(105) * deltaTime, 0, 0)
	end)
	table.insert(state.connections, heartbeat)

	local function playWall(entry, inward)
		TweenService:Create(entry.wall, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.4), {
			Position = inward and entry.wallTarget or entry.wallHome,
		}):Play()
		TweenService:Create(entry.kill, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.4), {
			Position = inward and entry.killTarget or entry.killHome,
		}):Play()
	end
	task.spawn(function()
		while state.alive and map.Parent do
			task.wait(1)
			for _, entry in ipairs(walls) do if entry.number == 3 or entry.number == 4 then playWall(entry, true) end end
			task.wait(0.5)
			for _, entry in ipairs(walls) do if entry.number ~= 3 and entry.number ~= 4 then playWall(entry, true) end end
			task.wait(0.5)
			for _, entry in ipairs(walls) do if entry.number == 3 or entry.number == 4 then playWall(entry, false) end end
			task.wait(1)
			for _, entry in ipairs(walls) do if entry.number ~= 3 and entry.number ~= 4 then playWall(entry, false) end end
		end
	end)

	local lava = map.KillParts:WaitForChild("Lava")
	lava.CanTouch = true
	table.insert(state.connections, lava.Touched:Connect(function(hit)
		resetToSpawn(hit, true)
	end))
	local lavaHome = lava.Position
	task.spawn(function()
		local lowered = false
		while state.alive and map.Parent do
			lowered = not lowered
			local tween = TweenService:Create(lava, TweenInfo.new(10, Enum.EasingStyle.Linear), {
				Position = lowered and (lavaHome + Vector3.new(0, 0, -50)) or lavaHome,
			})
			tween:Play()
			tween.Completed:Wait()
		end
	end)

	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, descendant in ipairs(map:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local half, position = descendant.Size * 0.5, descendant.Position
			minimum = Vector3.new(math.min(minimum.X, position.X-half.X), math.min(minimum.Y, position.Y-half.Y), math.min(minimum.Z, position.Z-half.Z))
			maximum = Vector3.new(math.max(maximum.X, position.X+half.X), math.max(maximum.Y, position.Y+half.Y), math.max(maximum.Z, position.Z+half.Z))
		end
	end
	local boundsSize = maximum - minimum
	local boundsCenter = (minimum + maximum) * 0.5
	local void = Instance.new("Part")
	void.Name = "LavaRunVoid"
	void.Anchored = true
	void.CanCollide = false
	void.CanQuery = false
	void.CanTouch = true
	void.Transparency = 1
	void.Size = Vector3.new(boundsSize.X + 160, 8, boundsSize.Z + 160)
	void.CFrame = CFrame.new(boundsCenter.X, minimum.Y - 35, boundsCenter.Z)
	void.Parent = map
	table.insert(state.connections, void.Touched:Connect(function(hit)
		resetToSpawn(hit, false)
	end))

	local finish = map.Completion:WaitForChild("Union")
	table.insert(state.connections, finish.Touched:Connect(function(hit)
		local character = ownerFromHit(player, hit)
		if not character or state.finished then return end
		state.finished = true
		local completionToken = HttpService:GenerateGUID(false)
		player:SetAttribute("MinigameCompletionFinished", nil)
		player:SetAttribute("MinigameCompletionToken", completionToken)
		completion:FireClient(player, completionToken)
		task.spawn(function()
			local deadline = os.clock() + 25
			while player.Parent and os.clock() < deadline and player:GetAttribute("MinigameCompletionFinished") ~= completionToken do
				RunService.Heartbeat:Wait()
			end
			transitionTeleport(player, portalPlane.CFrame * CFrame.new(0, 2, -8), portalPlane.Position)
			player:SetAttribute("InLavaRun", false)
			startCooldown(player) --.. completing the run arms the 1-hour lock
			destroyMapFor(player.UserId)
		end)
	end))
end

local function createMap(player)
	local old = activeMaps[player.UserId]
	if old and old.Parent then return old end
	local slot = allocateSlot(player)
	local clone = template:Clone()
	clone.Name = "LavaRun_" .. player.UserId
	clone:SetAttribute("OwnerUserId", player.UserId)
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then descendant.Disabled = true end
	end
	local desiredSpawn = INSTANCE_ORIGIN + Vector3.new((slot - 1) * INSTANCE_SPACING, 0, 0)
	local delta = desiredSpawn - clone.SpawnLocation.Position
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then descendant.CFrame += delta end
	end
	clone.Parent = mapFolder
	activeMaps[player.UserId] = clone
	configureMap(player, clone)
	return clone
end

local function enterMap(player, map)
	local spawnLocation = map:FindFirstChild("SpawnLocation")
	if not spawnLocation then return false end
	player:SetAttribute("InLavaRun", true)
	local moved = transitionTeleport(player, spawnLocation.CFrame * CFrame.new(0, 7, 0), spawnLocation.Position, map.Name)
	if not moved then player:SetAttribute("InLavaRun", false) end
	return moved
end

local function onPortalTouched(hit)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = Players:GetPlayerFromCharacter(character)
	if not player or touchBusy[player.UserId] then return end
	if player:GetAttribute("MinigameKey") and not player:GetAttribute("InLavaRun") then return end
	touchBusy[player.UserId] = true
	task.spawn(function()
		local existing = activeMaps[player.UserId]
		if existing and existing.Parent then
			--.. re-entering your own still-active (not yet completed) run is free;
			--.. completion destroys the map, so this can never bypass the cooldown
			enterMap(player, existing)
			sendStatus(player)
		elseif canEnter(player) then
			local paidUnlock = PortalUnlockService.HasCredit(player, PORTAL_KEY)
			local entered = enterMap(player, createMap(player))
			if entered and paidUnlock then
				PortalUnlockService.Consume(player, PORTAL_KEY)
			end
			sendStatus(player)
		else
			--.. cooldown or cucumber requirement still blocks entry.
			local cooldownRemaining = remainingFor(player)
			if cooldownRemaining > 0 then
				PortalProgress.NotifyCooldown(player, cooldownRemaining)
			else
				PortalProgress.NotifyBlocked(player, PORTAL_KEY)
			end
			sendStatus(player)
		end
		task.wait(1.25)
		touchBusy[player.UserId] = nil
	end)
end

cancelRun.Event:Connect(function(player, key)
	if key ~= "LavaRun" then return end
	player:SetAttribute("InLavaRun", false)
	destroyMapFor(player.UserId)
end)

local function bindPlayer(player)
	player:SetAttribute("InLavaRun", false)
	player.CharacterAdded:Connect(function()
		task.wait(0.4)
		if not player:GetAttribute("InLavaRun") then return end
		local map = activeMaps[player.UserId]
		local spawnLocation = map and map:FindFirstChild("SpawnLocation")
		if spawnLocation then moveCharacter(player, spawnLocation.CFrame * CFrame.new(0, 7, 0)) end
	end)
	task.spawn(loadCooldown, player)
end

getStatus.OnServerInvoke = function(player)
	if not cooldownLoaded[player.UserId] then loadCooldown(player) end
	local paidUnlock = PortalUnlockService.HasCredit(player, PORTAL_KEY)
	return { remaining = paidUnlock and 0 or remainingFor(player), unavailable = not PortalProgress.IsLoaded(player), cucumbersRemaining = paidUnlock and 0 or PortalProgress.Remaining(player, PORTAL_KEY) }
end

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	local state = mapStates[userId]
	if state then
		state.alive = false
		for _, connection in ipairs(state.connections) do pcall(function() connection:Disconnect() end) end
	end
	if activeMaps[userId] then activeMaps[userId]:Destroy() end
	if slotByUser[userId] then table.insert(freeSlots, slotByUser[userId]) end
	activeMaps[userId], mapStates[userId], slotByUser[userId] = nil, nil, nil
	touchBusy[userId], cooldowns[userId], cooldownLoaded[userId] = nil, nil, nil
end)
for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end
PortalProgress.Changed.Event:Connect(function(player, changedKey)
	if (not changedKey or changedKey == PORTAL_KEY) and player.Parent then sendStatus(player) end
end)

cucumberDestroyed.Event:Connect(function(player, zoneName)
	if zoneName == BIOME_ZONE and player.Parent and remainingFor(player) == 0 and PortalProgress.IsLoaded(player) then
		PortalProgress.Add(player, PORTAL_KEY, 1)
	end
end)

PortalUnlockService.Register(PORTAL_KEY, {
	Part = portalPlane,
	IsLocked = function(player)
		if not cooldownLoaded[player.UserId] and not loadCooldown(player) then
			return false
		end
		if not PortalProgress.IsLoaded(player) then
			return false
		end
		return remainingFor(player) > 0 or PortalProgress.Remaining(player, PORTAL_KEY) > 0
	end,
	Refresh = sendStatus,
})

portalPlane.CanTouch = true
portalPlane.Touched:Connect(onPortalTouched)

print("[LavaPortalService] Ready: private Lava Run maps and one-hour cooldown enabled.")
