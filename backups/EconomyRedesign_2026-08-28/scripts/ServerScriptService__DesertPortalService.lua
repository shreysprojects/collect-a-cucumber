-- Desert Portal: private Wild West rat hunts with persistent per-player cooldown.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local COOLDOWN_SECONDS = 60 * 60
local INSTANCE_ORIGIN = Vector3.new(-2000, 600, 9000)
local INSTANCE_SPACING = 650
local DATASTORE_NAME = "DesertPortalCooldown_v1"
local PORTAL_KEY = "Desert"
local BIOME_ZONE = "Desert"
local PortalProgress = require(game:GetService("ServerStorage"):WaitForChild("PortalCucumberProgress"))
local PortalUnlockService = require(game:GetService("ServerStorage"):WaitForChild("PortalUnlockService"))
local cucumberDestroyed = game:GetService("ServerStorage"):WaitForChild("PortalCucumberDestroyed")
local RAT_COUNT = 10

local portal = workspace:WaitForChild("Portals"):WaitForChild("Desert Portal")
local portalPlane = portal:WaitForChild("Portal Ilussion"):FindFirstChildWhichIsA("BasePart", true)
assert(portalPlane, "[DesertPortalService] Desert Portal has no touchable illusion part")

local template = ServerStorage:WaitForChild("Wild_West")
local revolverTemplate = ServerStorage:WaitForChild("Revolver")
local ratTemplate = ReplicatedStorage:WaitForChild("Rat")
local transitionRemotes = ReplicatedStorage:WaitForChild("StarterPortalRemotes")
local transition = transitionRemotes:WaitForChild("Transition")
local transitionReady = transitionRemotes:WaitForChild("TransitionReady")
local completion = ReplicatedStorage:WaitForChild("MinigameEffects"):WaitForChild("Completed")
local cancelRun = game:GetService("ServerStorage"):WaitForChild("MinigameSessionCancel")

local remotes = ReplicatedStorage:FindFirstChild("DesertPortalRemotes") or Instance.new("Folder")
remotes.Name = "DesertPortalRemotes"
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
local progress = remotes:FindFirstChild("Progress") or Instance.new("RemoteEvent")
progress.Name = "Progress"
progress.Parent = remotes
local ratKillConfirmed = remotes:FindFirstChild("RatKillConfirmed") or Instance.new("RemoteEvent")
ratKillConfirmed.Name = "RatKillConfirmed"
ratKillConfirmed.Parent = remotes

local mapFolder = workspace:FindFirstChild("PlayerWildWestHunts") or Instance.new("Folder")
mapFolder.Name = "PlayerWildWestHunts"
mapFolder.Parent = workspace

local cooldownStore = DataStoreService:GetDataStore(DATASTORE_NAME)
local cooldowns, cooldownLoaded = {}, {}
local activeMaps, mapStates, touchBusy = {}, {}, {}
local slotByUser, freeSlots, nextSlot = {}, {}, 1

local function boundsOf(root)
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local half = descendant.Size * 0.5
			local position = descendant.Position
			minimum = Vector3.new(
				math.min(minimum.X, position.X - half.X),
				math.min(minimum.Y, position.Y - half.Y),
				math.min(minimum.Z, position.Z - half.Z)
			)
			maximum = Vector3.new(
				math.max(maximum.X, position.X + half.X),
				math.max(maximum.Y, position.Y + half.Y),
				math.max(maximum.Z, position.Z + half.Z)
			)
		end
	end
	return minimum, maximum
end

local templateMinimum, templateMaximum = boundsOf(template)
local templateCenter = (templateMinimum + templateMaximum) * 0.5

local function keyFor(player)
	return "Player_" .. player.UserId
end

local function expiryFrom(value)
	if type(value) == "table" then
		return tonumber(value.nextReady) or 0
	end
	return type(value) == "number" and value or 0
end

local function remainingFor(player)
	return math.max(0, (cooldowns[player.UserId] or 0) - os.time())
end

local function sendStatus(player, unavailable)
	if player.Parent then
		local paidUnlock = PortalUnlockService.HasCredit(player, PORTAL_KEY)
		statusChanged:FireClient(player, {
			remaining = paidUnlock and 0 or remainingFor(player),
			unavailable = unavailable == true or not PortalProgress.IsLoaded(player),
			cucumbersRemaining = paidUnlock and 0 or PortalProgress.Remaining(player, PORTAL_KEY),
		})
	end
end

--.. Absolute os.time() expiry in the DataStore: counts down across servers,
--.. rejoins, and offline time. Studio uses the SAME store — playtests behave
--.. exactly like production (RemoveAsync the key to reset while testing).
local function loadCooldown(player)
	local expiry = 0
	local ok, value = pcall(function()
		return cooldownStore:GetAsync(keyFor(player))
	end)
	if not ok then
		warn("[DesertPortalService] Cooldown load failed", player, value)
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

--.. armed by COMPLETING the hunt (not by entering); entry stays blocked until
--.. the countdown fully reaches zero
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
	if not ok then
		warn("[DesertPortalService] Cooldown save failed after retries", player, err)
	end
	sendStatus(player)
end

local function allocateSlot(player)
	if slotByUser[player.UserId] then
		return slotByUser[player.UserId]
	end
	local slot = table.remove(freeSlots)
	if not slot then
		slot = nextSlot
		nextSlot += 1
	end
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
	if streamPosition then
		pcall(function()
			player:RequestStreamAroundAsync(streamPosition, 8)
		end)
	end
	local moved = moveCharacter(player, targetCFrame)
	task.wait(0.12)
	if player.Parent then
		transition:FireClient(player, "Out")
	end
	return moved
end

local function isPickaxe(instance)
	-- Pickaxes are Tool instances since 2026-08-10 (IsPickaxe marker at the Tool
	-- root); the BasePart arm covers any legacy welded copy still on a character.
	return (instance:IsA("Tool") or instance:IsA("BasePart")) and instance:FindFirstChild("IsPickaxe") ~= nil
end

local function stashPickaxes(player, state)
	if not state.stash then return end
	-- A Tool pickaxe can sit in the Backpack instead of the character (the
	-- Humanoid auto-swaps it there when another Tool equips), so sweep both.
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in ipairs({ character, backpack }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if isPickaxe(child) then
					child.Parent = state.stash
				end
			end
		end
	end
end

local function removeRevolver(player, state)
	if state.gun and state.gun.Parent then
		state.gun:Destroy()
	end
	state.gun = nil
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in ipairs({ character, backpack }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child.Name == "Revolver" then
					child:Destroy()
				end
			end
		end
	end
end

local function restorePickaxes(player, state)
	removeRevolver(player, state)
	local character = player.Character
	if character and state.stash then
		for _, pickaxe in ipairs(state.stash:GetChildren()) do
			pickaxe.Parent = character
		end
	end

	-- A character replacement can discard the old stashed instance. Reconcile
	-- against saved PickaxeService state after Desert mode is cleared.
	task.delay(0.1, function()
		if not player.Parent or player:GetAttribute("InDesertHunt") then return end
		local current = player.Character
		if not current then return end
		for _, child in ipairs(current:GetChildren()) do
			if isPickaxe(child) then return end
		end
		local ServerController = require(ServerStorage.ServerController)
		ServerController.GetModule("PickaxeService").CharacterJoined(current)
	end)
end

local function giveRevolver(player, state)
	removeRevolver(player, state)
	stashPickaxes(player, state)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not character or not humanoid or not backpack then return false end
	local gun = revolverTemplate:Clone()
	gun.Name = "Revolver"
	gun.CanBeDropped = false
	gun:SetAttribute("DesertHuntWeapon", true)
	gun.Parent = backpack
	humanoid:EquipTool(gun)
	state.gun = gun
	return gun.Parent == character
end

local function makeCamera(folder, name, position, focus)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.lookAt(position, focus)
	part.Parent = folder
	return part
end

local finishHunt

local function ragdollRat(rat)
	local highlight = rat:FindFirstChild("TargetOutline")
	if highlight then highlight:Destroy() end
	local humanoid = rat:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
	end
	for _, motor in ipairs(rat:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local attachment0 = Instance.new("Attachment")
			attachment0.Name = "RagdollAttachment0"
			attachment0.CFrame = motor.C0
			attachment0.Parent = motor.Part0
			local attachment1 = Instance.new("Attachment")
			attachment1.Name = "RagdollAttachment1"
			attachment1.CFrame = motor.C1
			attachment1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = attachment0
			socket.Attachment1 = attachment1
			socket.LimitsEnabled = true
			socket.UpperAngle = 50
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -35
			socket.TwistUpperAngle = 35
			socket.Parent = motor.Parent
			motor.Enabled = false
		end
	end
	for _, part in ipairs(rat:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Massless = false
			part.CanCollide = part.Name ~= "HumanoidRootPart"
		end
	end
	local root = rat:FindFirstChild("HumanoidRootPart")
	if root then
		root:ApplyImpulse((Vector3.new(math.random(-12, 12), 18, math.random(-12, 12))) * root.AssemblyMass)
	end
end

local function configureMap(player, map, ground)
	local state = {
		connections = {},
		alive = true,
		finished = false,
		kills = 0,
		map = map,
		ground = ground,
	}
	mapStates[player.UserId] = state

	local stash = Instance.new("Folder")
	stash.Name = "StoredPickaxe_" .. player.UserId
	stash.Parent = ServerStorage
	state.stash = stash

	local groundTop = ground.Position.Y + ground.Size.Y * 0.5
	state.spawnCFrame = CFrame.new(ground.Position + Vector3.new(0, ground.Size.Y * 0.5 + 4, 0))

	local cameras = Instance.new("Folder")
	cameras.Name = "Cameras"
	cameras.Parent = map
	local focus = ground.Position + Vector3.new(0, 5, 0)
	makeCamera(cameras, "Cutscene1", focus + Vector3.new(62, 34, 62), focus)
	makeCamera(cameras, "Cutscene2", focus + Vector3.new(-58, 25, 28), focus)
	makeCamera(cameras, "Cutscene3", focus + Vector3.new(5, 42, -66), focus)

	local ratsFolder = Instance.new("Folder")
	ratsFolder.Name = "DesertRats"
	ratsFolder.Parent = map
	state.ratsFolder = ratsFolder

	local random = Random.new(player.UserId)
	for index = 1, RAT_COUNT do
		local rat = ratTemplate:Clone()
		rat.Name = "Rat_" .. index
		rat:SetAttribute("DesertRat", true)
		rat:SetAttribute("OwnerUserId", player.UserId)
		local highlight = Instance.new("Highlight")
		highlight.Name = "TargetOutline"
		highlight.Adornee = rat
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 0
		highlight.OutlineColor = Color3.fromRGB(255, 225, 70)
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = rat
		for _, descendant in ipairs(rat:GetDescendants()) do
			if descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant.Disabled = true
			elseif descendant:IsA("BasePart") then
				descendant.CollisionGroup = "Default"
				descendant.CanTouch = true
			end
		end
		local humanoid = rat:FindFirstChildOfClass("Humanoid")
		local root = rat:FindFirstChild("HumanoidRootPart")
		if humanoid and root then
			humanoid.BreakJointsOnDeath = false
			humanoid.MaxHealth = 1
			humanoid.Health = 1
			humanoid.WalkSpeed = 15
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			local angle = (index / RAT_COUNT) * math.pi * 2
			local radius = 24 + (index % 3) * 11
			local position = ground.Position + Vector3.new(math.cos(angle) * radius, ground.Size.Y * 0.5 + 2.2, math.sin(angle) * radius)
			rat.Parent = ratsFolder
			rat:PivotTo(CFrame.lookAt(position, Vector3.new(ground.Position.X, position.Y, ground.Position.Z)))
			pcall(function() root:SetNetworkOwner(nil) end)

			local animation = rat:FindFirstChildWhichIsA("Animation")
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animation and animator then
				pcall(function()
					animator:LoadAnimation(animation):Play()
				end)
			end

			table.insert(state.connections, humanoid.Died:Connect(function()
				local creator = humanoid:FindFirstChild("creator")
				if not state.alive or state.finished or not creator or creator.Value ~= player then
					return
				end
				ragdollRat(rat)
				state.kills += 1
				ratKillConfirmed:FireClient(player, state.kills)
				progress:FireClient(player, state.kills, RAT_COUNT)
				task.delay(2, function()
					if rat.Parent then rat:Destroy() end
				end)
				if state.kills >= RAT_COUNT then
					finishHunt(player, state)
				end
			end))

			task.spawn(function()
				task.wait(random:NextNumber(0.1, 1.2))
				while state.alive and not state.finished and rat.Parent and humanoid.Health > 0 do
					local targetAngle = random:NextNumber(0, math.pi * 2)
					local targetRadius = random:NextNumber(12, 61)
					local target = ground.Position + Vector3.new(
						math.cos(targetAngle) * targetRadius,
						groundTop + 2,
						math.sin(targetAngle) * targetRadius
					)
					humanoid:MoveTo(target)
					task.wait(random:NextNumber(2.1, 4.2))
				end
			end)
		else
			rat:Destroy()
		end
	end

	local minimum, maximum = boundsOf(map)
	local void = Instance.new("Part")
	void.Name = "WildWestVoid"
	void.Anchored = true
	void.CanCollide = false
	void.CanQuery = false
	void.CanTouch = true
	void.Transparency = 1
	void.Size = Vector3.new((maximum.X - minimum.X) + 160, 8, (maximum.Z - minimum.Z) + 160)
	void.CFrame = CFrame.new((minimum.X + maximum.X) * 0.5, minimum.Y - 35, (minimum.Z + maximum.Z) * 0.5)
	void.Parent = map
	table.insert(state.connections, void.Touched:Connect(function(hit)
		local character = hit and hit:FindFirstAncestorOfClass("Model")
		if Players:GetPlayerFromCharacter(character) ~= player then return end
		moveCharacter(player, state.spawnCFrame)
	end))

	progress:FireClient(player, 0, RAT_COUNT)
	return state
end

local function destroyState(player, restore)
	local userId = player.UserId
	local state = mapStates[userId]
	if not state then return end
	state.alive = false
	if restore then
		restorePickaxes(player, state)
	else
		removeRevolver(player, state)
	end
	for _, connection in ipairs(state.connections) do
		pcall(function() connection:Disconnect() end)
	end
	if state.stash and state.stash.Parent then
		state.stash:Destroy()
	end
	if state.map and state.map.Parent then
		state.map:Destroy()
	end
	activeMaps[userId] = nil
	mapStates[userId] = nil
end

finishHunt = function(player, state)
	if state.finished then return end
	state.finished = true
	local completionToken = HttpService:GenerateGUID(false)
	player:SetAttribute("MinigameCompletionFinished", nil)
		player:SetAttribute("MinigameCompletionToken", completionToken)
	completion:FireClient(player, completionToken)
	progress:FireClient(player, RAT_COUNT, RAT_COUNT)
	task.spawn(function()
		local deadline = os.clock() + 25
		while player.Parent and os.clock() < deadline and player:GetAttribute("MinigameCompletionFinished") ~= completionToken do
			RunService.Heartbeat:Wait()
		end
		transitionTeleport(player, portalPlane.CFrame * CFrame.new(0, 2, -8), portalPlane.Position)
		restorePickaxes(player, state)
		player:SetAttribute("InDesertHunt", false)
		startCooldown(player) --.. completing the hunt arms the 1-hour lock
		task.wait(0.75)
		destroyState(player, true)
	end)
end

local function createMap(player)
	local old = activeMaps[player.UserId]
	if old and old.Parent then return old end
	local slot = allocateSlot(player)
	local clone = template:Clone()
	clone.Name = "WildWestHunt_" .. player.UserId
	clone:SetAttribute("OwnerUserId", player.UserId)
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant.Disabled = true
		end
	end
	local desiredCenter = INSTANCE_ORIGIN + Vector3.new((slot - 1) * INSTANCE_SPACING, 0, 0)
	local delta = desiredCenter - templateCenter
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = descendant.CFrame + delta
		end
	end
	clone.Parent = mapFolder
	local ground = clone:FindFirstChild("Union")
	if not ground or not ground:IsA("BasePart") then
		clone:Destroy()
		error("[DesertPortalService] Wild West map has no ground union")
	end
	activeMaps[player.UserId] = clone
	configureMap(player, clone, ground)
	return clone
end

local function enterMap(player, map)
	local state = mapStates[player.UserId]
	if not state then return false end
	player:SetAttribute("InDesertHunt", true)
	progress:FireClient(player, state.kills, RAT_COUNT)
	stashPickaxes(player, state)
	giveRevolver(player, state)
	local moved = transitionTeleport(player, state.spawnCFrame, state.ground.Position, map.Name)
	if not moved then
		player:SetAttribute("InDesertHunt", false)
		destroyState(player, true)
	end
	return moved
end

local function onPortalTouched(hit)
	local character = hit and hit:FindFirstAncestorOfClass("Model")
	local player = Players:GetPlayerFromCharacter(character)
	if not player or touchBusy[player.UserId] or player:GetAttribute("InDesertHunt") then return end
	if player:GetAttribute("MinigameKey") then return end
	touchBusy[player.UserId] = true
	task.spawn(function()
		if not cooldownLoaded[player.UserId] then
			sendStatus(player, true)
			task.wait(1)
		elseif not PortalUnlockService.HasCredit(player, PORTAL_KEY) and (remainingFor(player) > 0 or PortalProgress.Remaining(player, PORTAL_KEY) > 0) then
			--.. cooldown or cucumber requirement still blocks entry.
			local cooldownRemaining = remainingFor(player)
			if cooldownRemaining > 0 then
				PortalProgress.NotifyCooldown(player, cooldownRemaining)
			else
				PortalProgress.NotifyBlocked(player, PORTAL_KEY)
			end
			sendStatus(player)
		else
			local paidUnlock = PortalUnlockService.HasCredit(player, PORTAL_KEY)
			local ok, map = pcall(createMap, player)
			if ok and map then
				local entered = enterMap(player, map)
				if entered and paidUnlock then
					PortalUnlockService.Consume(player, PORTAL_KEY)
				end
			else
				warn("[DesertPortalService] Could not create Wild West hunt", map)
			end
			sendStatus(player)
		end
		task.wait(1.2)
		touchBusy[player.UserId] = nil
	end)
end

getStatus.OnServerInvoke = function(player)
	local paidUnlock = PortalUnlockService.HasCredit(player, PORTAL_KEY)
	return {
		remaining = paidUnlock and 0 or remainingFor(player),
		unavailable = not cooldownLoaded[player.UserId] or not PortalProgress.IsLoaded(player),
		cucumbersRemaining = paidUnlock and 0 or PortalProgress.Remaining(player, PORTAL_KEY),
	}
end

cancelRun.Event:Connect(function(player, key)
	if key ~= "DesertHunt" then return end
	player:SetAttribute("InDesertHunt", false)
	destroyState(player, true)
end)

local function bindPlayer(player)
	if player:GetAttribute("InDesertHunt") == nil then
		player:SetAttribute("InDesertHunt", false)
	end
	player.CharacterAdded:Connect(function(character)
		if not player:GetAttribute("InDesertHunt") then return end
		task.delay(1, function()
			local state = mapStates[player.UserId]
			if not state or not state.alive or not character.Parent then return end
			moveCharacter(player, state.spawnCFrame)
			stashPickaxes(player, state)
			giveRevolver(player, state)
		end)
	end)
	task.spawn(loadCooldown, player)
end

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	destroyState(player, false)
	local slot = slotByUser[userId]
	if slot then
		table.insert(freeSlots, slot)
		slotByUser[userId] = nil
	end
	touchBusy[userId], cooldowns[userId], cooldownLoaded[userId] = nil, nil, nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

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
print("[DesertPortalService] Ready: private Wild West rat hunts and one-hour cooldown enabled.")
