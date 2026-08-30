-- Starter Portal: per-player Classic Obby instances with a global persistent cooldown.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local COOLDOWN_SECONDS = 60 * 60
local INSTANCE_SPACING = 500
local INSTANCE_ORIGIN = Vector3.new(-500, 500, 4000)
local DATASTORE_NAME = "StarterPortalCooldown_v1"
local PORTAL_KEY = "Starter"
local BIOME_ZONE = "Spawn"
local PortalProgress = require(game:GetService("ServerStorage"):WaitForChild("PortalCucumberProgress"))
local PortalUnlockService = require(game:GetService("ServerStorage"):WaitForChild("PortalUnlockService"))
local cucumberDestroyed = game:GetService("ServerStorage"):WaitForChild("PortalCucumberDestroyed")

local portal = workspace:WaitForChild("Portals"):WaitForChild("Starter Portal")
local portalPlane = portal:WaitForChild("Portal Ilussion"):FindFirstChildWhichIsA("BasePart", true)
assert(portalPlane, "[StarterPortalService] Starter Portal has no touchable illusion part")

local template = game:GetService("ServerStorage"):WaitForChild("Classic Obby")
local templateSpawn = template:WaitForChild("PortalSpawn")
local templateRotation = template:GetPivot().Rotation

local obbyFolder = workspace:FindFirstChild("PlayerObbies") or Instance.new("Folder")
obbyFolder.Name = "PlayerObbies"
obbyFolder.Parent = workspace

local remotes = ReplicatedStorage:FindFirstChild("StarterPortalRemotes") or Instance.new("Folder")
remotes.Name = "StarterPortalRemotes"
remotes.Parent = ReplicatedStorage

local getStatus = remotes:FindFirstChild("GetStatus") or Instance.new("RemoteFunction")
getStatus.Name = "GetStatus"
getStatus.Parent = remotes

local statusChanged = remotes:FindFirstChild("StatusChanged") or Instance.new("RemoteEvent")
statusChanged.Name = "StatusChanged"
statusChanged.Parent = remotes

local transition = remotes:FindFirstChild("Transition") or Instance.new("RemoteEvent")
transition.Name = "Transition"
transition.Parent = remotes

local transitionReady = remotes:FindFirstChild("TransitionReady") or Instance.new("RemoteEvent")
transitionReady.Name = "TransitionReady"
transitionReady.Parent = remotes
transitionReady.OnServerEvent:Connect(function(player, token)
	if type(token) == "string" then
		player:SetAttribute("PortalTransitionReady", token)
	end
end)

local completion = ReplicatedStorage:WaitForChild("MinigameEffects"):WaitForChild("Completed")
local cancelRun = game:GetService("ServerStorage"):WaitForChild("MinigameSessionCancel")

local cooldownStore = DataStoreService:GetDataStore(DATASTORE_NAME)
local cooldowns = {}
local cooldownLoaded = {}
local activeObbies = {}
local touchBusy = {}
local slotByUser = {}
local freeSlots = {}
local nextSlot = 1

local function keyFor(player)
	return "Player_" .. player.UserId
end

local function expiryFrom(value)
	if type(value) == "table" then
		return tonumber(value.nextReady) or 0
	end
	if type(value) == "number" then
		return value
	end
	return 0
end

local function remainingFor(player)
	return math.max(0, (cooldowns[player.UserId] or 0) - os.time())
end

local function sendStatus(player, unavailable)
	if not player.Parent then
		return
	end
	local paidUnlock = PortalUnlockService.HasCredit(player, PORTAL_KEY)
	statusChanged:FireClient(player, {
		remaining = paidUnlock and 0 or remainingFor(player),
		unavailable = unavailable == true or not PortalProgress.IsLoaded(player),
		cucumbersRemaining = paidUnlock and 0 or PortalProgress.Remaining(player, PORTAL_KEY),
	})
end

--.. The cooldown is an absolute os.time() expiry stored in the DataStore, so it
--.. keeps counting down across servers, rejoins, and fully offline time. Studio
--.. uses the SAME store (no in-memory stand-in anymore), so playtests behave
--.. exactly like production — to reset while testing, RemoveAsync the key.
local function loadCooldown(player)
	local userId = player.UserId
	local expiry = 0

	local ok, value = pcall(function()
		return cooldownStore:GetAsync(keyFor(player))
	end)
	if not ok then
		warn("[StarterPortalService] Could not load cooldown for", player, value)
		cooldownLoaded[userId] = false
		sendStatus(player, true)
		return false
	end
	expiry = expiryFrom(value)

	-- Never let a slower initial read overwrite a cooldown started after the player joined.
	cooldowns[userId] = math.max(cooldowns[userId] or 0, expiry)
	PortalProgress.Reset(player, PORTAL_KEY)
	cooldownLoaded[userId] = true
	sendStatus(player)
	return true
end

--.. Entry is allowed ONLY when no cooldown is running; the countdown must fully
--.. finish. The cooldown itself is armed by COMPLETING the minigame, not by entering.
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
		warn("[StarterPortalService] Cooldown save failed after retries", player, err)
	end
	sendStatus(player)
end

local function allocateSlot(player)
	local existing = slotByUser[player.UserId]
	if existing then
		return existing
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
	if not root then
		return false
	end

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

local function transitionTeleport(player, targetCFrame, streamPosition)
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

local function portalReturnCFrame()
	return portalPlane.CFrame * CFrame.new(0, 2, -8)
end

local function connectCompletionChest(player, obby)
	local reward = obby:FindFirstChild("Reward Tresure")
	local chest = reward and reward:FindFirstChild("Chest")
	if not chest then
		warn("[StarterPortalService] Generated obby has no completion chest")
		return
	end

	local completionBusy = false
	local function completeFromChest(hit)
		if completionBusy then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		if Players:GetPlayerFromCharacter(character) ~= player then
			return
		end
		completionBusy = true
		local completionToken = HttpService:GenerateGUID(false)
		player:SetAttribute("MinigameCompletionFinished", nil)
		player:SetAttribute("MinigameCompletionToken", completionToken)
		completion:FireClient(player, completionToken)
		task.spawn(function()
			local deadline = os.clock() + 25
			while player.Parent and os.clock() < deadline and player:GetAttribute("MinigameCompletionFinished") ~= completionToken do
				RunService.Heartbeat:Wait()
			end
			transitionTeleport(player, portalReturnCFrame(), portalPlane.Position)
			player:SetAttribute("InStarterObby", false)
			--.. completing the obby is what arms the 1-hour lock; the private
			--.. instance is spent, so destroy it (re-entry then requires the
			--.. countdown to finish and a fresh obby)
			startCooldown(player)
			local spent = activeObbies[player.UserId]
			activeObbies[player.UserId] = nil
			if spent then
				spent:Destroy()
			end
			task.delay(1, function()
				completionBusy = false
			end)
		end)
	end

	for _, descendant in ipairs(chest:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanTouch = true
			descendant.Touched:Connect(completeFromChest)
		end
	end
end

local function createObby(player)
	local old = activeObbies[player.UserId]
	if old and old.Parent then
		return old
	end

	local slot = allocateSlot(player)
	local clone = template:Clone()
	clone.Name = "ClassicObby_" .. player.UserId
	clone:SetAttribute("OwnerUserId", player.UserId)
	clone:PivotTo(CFrame.new(INSTANCE_ORIGIN + Vector3.new((slot - 1) * INSTANCE_SPACING, 0, 0)) * templateRotation)
	clone.Parent = obbyFolder
	activeObbies[player.UserId] = clone
	connectCompletionChest(player, clone)
	return clone
end

local function enterObby(player, obby)
	local spawnMarker = obby:FindFirstChild("PortalSpawn")
	if not spawnMarker or not spawnMarker:IsA("BasePart") then
		warn("[StarterPortalService] Generated obby is missing PortalSpawn")
		return false
	end

	-- This attribute is replicated to the client so normal-world helpers such as
	-- the next-door arrow stay hidden for the entire private obby session.
	player:SetAttribute("InStarterObby", true)
	local moved = transitionTeleport(player, spawnMarker.CFrame, spawnMarker.Position)
	if not moved then
		player:SetAttribute("InStarterObby", false)
	end
	return moved
end

local function onPortalTouched(hit)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = Players:GetPlayerFromCharacter(character)
	if not player or touchBusy[player.UserId] then
		return
	end
	if player:GetAttribute("MinigameKey") and not player:GetAttribute("InStarterObby") then
		return
	end

	touchBusy[player.UserId] = true
	task.spawn(function()
		local existing = activeObbies[player.UserId]
		if existing and existing.Parent then
			--.. re-entering your own still-active (not yet completed) run is free;
			--.. completion destroys the obby, so this can never bypass the cooldown
			enterObby(player, existing)
			sendStatus(player)
		elseif canEnter(player) then
			local paidUnlock = PortalUnlockService.HasCredit(player, PORTAL_KEY)
			local obby = createObby(player)
			local entered = enterObby(player, obby)
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
	if key ~= "StarterObby" then return end
	local userId = player.UserId
	local obby = activeObbies[userId]
	activeObbies[userId] = nil
	player:SetAttribute("InStarterObby", false)
	if obby then obby:Destroy() end
end)

getStatus.OnServerInvoke = function(player)
	if not cooldownLoaded[player.UserId] then
		loadCooldown(player)
	end
	local paidUnlock = PortalUnlockService.HasCredit(player, PORTAL_KEY)
	return {
		remaining = paidUnlock and 0 or remainingFor(player),
		unavailable = not PortalProgress.IsLoaded(player),
		cucumbersRemaining = paidUnlock and 0 or PortalProgress.Remaining(player, PORTAL_KEY),
	}
end

local function bindObbyRespawn(player)
	player:SetAttribute("InStarterObby", false)
	player.CharacterAdded:Connect(function()
		task.wait(0.35)
		if not player:GetAttribute("InStarterObby") then
			return
		end

		local obby = activeObbies[player.UserId]
		local spawnMarker = obby and obby:FindFirstChild("PortalSpawn")
		if spawnMarker and spawnMarker:IsA("BasePart") then
			moveCharacter(player, spawnMarker.CFrame)
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	bindObbyRespawn(player)
	task.spawn(loadCooldown, player)
end)

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	local obby = activeObbies[userId]
	if obby then
		obby:Destroy()
	end
	local slot = slotByUser[userId]
	if slot then
		table.insert(freeSlots, slot)
	end
	activeObbies[userId] = nil
	slotByUser[userId] = nil
	touchBusy[userId] = nil
	cooldowns[userId] = nil
	cooldownLoaded[userId] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindObbyRespawn(player)
	task.spawn(loadCooldown, player)
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

print("[StarterPortalService] Ready: per-player Classic Obbies and 1-hour global cooldown enabled.")
