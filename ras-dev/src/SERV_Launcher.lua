--[[---------------------------------------DESCRIPTION------------------------------------------
	Clones the equipped snowball launcher from Storage/SnowballLaunchers and
	welds it to the right hand while the player is on the launch platform.

	Also: copies the snowball looks to ReplicatedStorage.Assets.SnowballVisuals (the clients
	show the ball sitting in / leaving the launcher, SnowballAnimations/LauncherBall), and
	relays each player's hold / release (LauncherPose) as a player attribute so everyone else
	plays the same launcher clip at the same moment (CLIENT_LauncherObservers).

--------------------------------------------------------------------------------------------]]--

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local playerProgress = require(ReplicatedStorage.Assets.Modules.Shared.PlayerProgress)()

local MODULE = {}
local m_api = {}
local m_sapi = {}
local sself = m_sapi

-- Visual copies of every snowball for the clients (no scripts, no collision).
local function publishSnowballVisuals()
	local source = ServerStorage.Assets.Storage:FindFirstChild(mountainConfig.LAUNCH.StorageFolder)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not (source and assets) or assets:FindFirstChild("SnowballVisuals") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SnowballVisuals"
	for _, template in source:GetChildren() do
		if not (template:IsA("Model") or template:IsA("BasePart")) then
			continue
		end
		local copy = template:Clone()
		for _, d in copy:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		local parts = copy:GetDescendants()
		table.insert(parts, copy)
		for _, part in parts do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
		copy.Parent = folder
	end
	folder.Parent = assets
end

function MODULE.new(r_sapi)
	sself = r_sapi
	sself.LAUNCHERS = sself.LAUNCHERS or {}
	-- Per-player request counter: a later equip / unequip cancels an equip still waiting.
	sself.LAUNCHER_REQUEST = sself.LAUNCHER_REQUEST or setmetatable({}, { __mode = "k" })
	sself.LAUNCHER_POSE = sself.LAUNCHER_POSE or setmetatable({}, { __mode = "k" })
	task.defer(function()
		local ok, err = pcall(publishSnowballVisuals)
		if not ok then
			warn("[SERVER]: Snowball visuals not published:", err)
		end
	end)
	return m_api, m_sapi
end

-- The client asks for the launcher the frame its own pad check passes, a few
-- replication ticks before the server sees that position. Give the position
-- this long to catch up before treating the request as "not on the pad".
local EQUIP_GRACE = 1.0
local EQUIP_POLL = 0.1

local function getCatalog()
	return sself.DEF_GVARS.SnowballLaunchers
end

local function getSettings()
	return mountainConfig.LAUNCHER
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

local function getRootPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function getHand(character)
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

local function findNamed(instance, name, className)
	for _, desc in instance:GetDescendants() do
		if desc.Name == name and desc:IsA(className) then
			return desc
		end
	end
	if instance.Name == name and instance:IsA(className) then
		return instance
	end
	return nil
end

local function findGrip(model, gripName)
	local attachment = findNamed(model, gripName, "Attachment")
	if attachment then
		return attachment
	end
	return findNamed(model, "Handle", "Attachment") or findNamed(model, "Handle", "BasePart")
end

local function prepareVisual(clone)
	for _, part in collectParts(clone) do
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
	end
end

local function isTemplate(instance)
	return instance:IsA("Model") or instance:IsA("BasePart") or instance:IsA("Tool")
end

-- "12_Snow_Revolver" -> "snowrevolver": no order prefix, case, spaces or separators.
local function compactAssetName(name)
	if type(name) ~= "string" then
		return ""
	end
	local trimmed = string.gsub(string.lower(name), "^%d+[%s_%-]*", "")
	return (string.gsub(trimmed, "[^%w]", ""))
end

local function namedTemplate(folder, name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local named = folder:FindFirstChild(name)
	if named and isTemplate(named) then
		return named
	end
	local want = compactAssetName(name)
	if want == "" then
		return nil
	end
	for _, child in folder:GetChildren() do
		if isTemplate(child) and compactAssetName(child.Name) == want then
			return child
		end
	end
	return nil
end

local missingWarned = {}

-- Catalog Asset names the template; display names can differ ("Revolver").
-- A launcher with no template falls back to the starter's, with one warning.
local function findTemplate(launcherName)
	local folder = ServerStorage.Assets.Storage:FindFirstChild(getSettings().StorageFolder)
	if not folder then
		return nil
	end

	local catalog = getCatalog()
	local info = catalog:GetByName(launcherName)
	local found = namedTemplate(folder, info and info.Asset) or namedTemplate(folder, launcherName)
	if found then
		return found
	end

	local key = tostring(launcherName)
	if not missingWarned[key] then
		missingWarned[key] = true
		warn("[SERVER]: No launcher template for", key, "- using the starter launcher")
	end
	local starter = catalog:GetByOrder(1)
	found = starter and namedTemplate(folder, starter.Asset)
	if found then
		return found
	end
	for _, child in folder:GetChildren() do
		if isTemplate(child) then
			return child
		end
	end
	return nil
end

local function resolveLauncher(requestedName)
	local catalog = getCatalog()
	if type(requestedName) == "string" then
		local named = catalog:GetByName(requestedName)
		if named then
			return named
		end
	end
	return catalog:GetByOrder(1)
end

local function alignToHand(model, hand)
	local settings = getSettings()
	local root = getRootPart(model)
	if not root then
		return false
	end

	if model:IsA("Model") and not model.PrimaryPart then
		model.PrimaryPart = root
	end

	local handGrip = hand:FindFirstChild(settings.HandGrip)
	local modelGrip = findGrip(model, settings.Grip)

	if modelGrip and modelGrip:IsA("Attachment") and handGrip then
		local gripOffset = model:GetPivot():ToObjectSpace(modelGrip.WorldCFrame)
		model:PivotTo(handGrip.WorldCFrame * gripOffset:Inverse())
	elseif modelGrip and modelGrip:IsA("BasePart") then
		local target = if handGrip then handGrip.WorldCFrame else hand.CFrame
		model:PivotTo(target * modelGrip.CFrame:ToObjectSpace(model:GetPivot()))
	else
		model:PivotTo(hand.CFrame * CFrame.new(0, -0.15, -0.35) * CFrame.Angles(math.rad(-80), 0, math.rad(90)))
	end

	return true
end

local function weldToHand(model, hand)
	local root = getRootPart(model)
	if not root then
		return false
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "LauncherGrip"
	motor.Part0 = hand
	motor.Part1 = root
	motor.C0 = hand.CFrame:ToObjectSpace(root.CFrame)
	motor.C1 = CFrame.new()
	motor.Parent = root
	return true
end

function m_sapi:ClearLauncher(player)
	local current = sself.LAUNCHERS[player]
	if current and current.Parent then
		current:Destroy()
	end
	sself.LAUNCHERS[player] = nil

	local character = player and player.Character
	if character then
		local leftover = character:FindFirstChild(getSettings().InstanceName)
		if leftover then
			leftover:Destroy()
		end
	end
end

function m_sapi:GiveLauncher(player, requestedName)
	if not player or not player.Parent then
		return false
	end

	local character = player.Character
	local hand = character and getHand(character)
	if not hand then
		return false
	end

	if not sself:IsPlayerOnLaunchPad(player) then
		return false
	end

	local data = sself:GetPlayerProgress(player)
	local info = resolveLauncher(requestedName or (data and data.EquippedLauncher) or player:GetAttribute("EquippedLauncher"))
	if not info then
		warn("[SERVER]: No snowball launcher in catalog")
		return false
	end

	local current = sself.LAUNCHERS[player]
	if current and current.Parent == character and current:GetAttribute("EquippedName") == info.Name then
		return true
	end

	sself:ClearLauncher(player)

	local template = findTemplate(info.Name)
	if not template then
		warn("[SERVER]: Launcher model missing in Storage/" .. getSettings().StorageFolder .. ":", info.Name)
		return false
	end

	local clone
	if template:IsA("BasePart") then
		clone = Instance.new("Model")
		local part = template:Clone()
		part.Parent = clone
		clone.PrimaryPart = part
	else
		clone = template:Clone()
		if clone:IsA("Tool") then
			clone.CanBeDropped = false
			clone.RequiresHandle = false
		end
	end

	clone.Name = getSettings().InstanceName
	clone:SetAttribute("EquippedName", info.Name)
	-- Scaled about the grip pivot, so the grip still lands in the hand.
	local scale = getSettings().Scale
	if clone:IsA("Model") and type(scale) == "number" and scale > 0 and scale ~= 1 then
		clone:ScaleTo(scale)
	end
	prepareVisual(clone)
	clone.Parent = character

	if not alignToHand(clone, hand) or not weldToHand(clone, hand) then
		warn("[SERVER]: Launcher has no BasePart:", info.Name)
		clone:Destroy()
		return false
	end

	player:SetAttribute("EquippedLauncher", info.Name)
	sself.LAUNCHERS[player] = clone
	return true
end

function m_api:EquipLauncher(player, requestedName)
	if type(requestedName) == "string" and requestedName ~= "" then
		local info = getCatalog():GetByName(requestedName)
		if not info then
			return false
		end

		local data = sself:GetPlayerProgress(player)
		if not data or not playerProgress.SetEquippedLauncher(data, info.Name) then
			return false
		end
		data.Dirty = true
		sself:ReplicateProgress(player)
	end

	local token = (sself.LAUNCHER_REQUEST[player] or 0) + 1
	sself.LAUNCHER_REQUEST[player] = token
	local deadline = os.clock() + EQUIP_GRACE
	while not sself:IsPlayerOnLaunchPad(player) do
		if os.clock() >= deadline or not player.Parent then
			return true
		end
		task.wait(EQUIP_POLL)
		if sself.LAUNCHER_REQUEST[player] ~= token then
			return true -- superseded by a later equip or an unequip
		end
	end
	return sself:GiveLauncher(player)
end

-- ReFunction: true, or false and a PlayerProgress.PurchaseInOrder reason for the shop to show.
-- With EQUIP_ON_BUY on, a bought launcher is also equipped and swapped into the hand on the launch pad.
function m_api:BuyLauncher(player, requestedName)
	if not player or type(requestedName) ~= "string" or requestedName == "" then
		return false, "Invalid"
	end

	local catalog = getCatalog()
	local info = catalog:GetByName(requestedName)
	if not info then
		return false, "Invalid"
	end

	local data = sself:GetPlayerProgress(player)
	if not data then
		return false, "Invalid"
	end
	local bought, reason = playerProgress.PurchaseInOrder(data, "UnlockedLaunchers", catalog.List, info.Name)
	if not bought then
		return false, reason
	end
	local equip = playerProgress.EQUIP_ON_BUY and playerProgress.SetEquippedLauncher(data, info.Name)
	data.Dirty = true
	sself:ReplicateProgress(player)
	if equip and sself:IsPlayerOnLaunchPad(player) then
		-- Off the answer path: the purchase is committed, a hand-swap error must not report it failed.
		task.spawn(function()
			sself:GiveLauncher(player)
		end)
	end
	return true
end

-- Hold / release relay for the other clients (CLIENT_LauncherObservers). The attribute is
-- "<state>:<count>" so two releases in a row still read as a change. At most one write per
-- POSE_MIN_GAP; a state that comes sooner is held back and written when the gap is over, so the
-- last one always lands (a quick tap's release must not be dropped).
local POSE_STATES = { hold = true, release = true, idle = true }
local POSE_MIN_GAP = 0.05

local function applyPose(player, record)
	record.Timer = nil
	local state = record.Pending
	record.Pending = nil
	if not state or not player.Parent then
		return
	end
	record.At = os.clock()
	record.Count += 1
	player:SetAttribute("LauncherPose", state .. ":" .. record.Count)
end

function m_api:LauncherPose(player, state)
	if not player or not POSE_STATES[state] then
		return false
	end
	local record = sself.LAUNCHER_POSE[player]
	if not record then
		record = { At = -math.huge, Count = 0 }
		sself.LAUNCHER_POSE[player] = record
	end
	record.Pending = state
	local wait = POSE_MIN_GAP - (os.clock() - record.At)
	if wait > 0 then
		if not record.Timer then
			record.Timer = task.delay(wait, applyPose, player, record)
		end
		return true
	end
	applyPose(player, record)
	return true
end

function m_api:UnequipLauncher(player)
	-- Cancels an equip that is still waiting for the position to catch up.
	sself.LAUNCHER_REQUEST[player] = (sself.LAUNCHER_REQUEST[player] or 0) + 1
	sself:ClearLauncher(player)
	return true
end

return MODULE
