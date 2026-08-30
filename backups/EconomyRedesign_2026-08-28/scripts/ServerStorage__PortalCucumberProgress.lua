-- Persistent per-player cucumber requirements for activity portals.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network = require(ReplicatedStorage.Modules.ControllerLoader).GetController("Network")

local PortalProgress = {}
PortalProgress.Changed = Instance.new("BindableEvent")
local STORE = DataStoreService:GetDataStore("PortalCucumberProgress_v1")
local REQUIREMENTS = {
	Starter = 18; -- 30% of Spawn boss's 60
	Desert = 27; -- 30% of Desert boss's 90
	Snow = 54; -- 30% of Snow boss's 180
	Lava = 78; -- 30% of Volcano boss's 260
	Void = 90; -- 30% of Narmek boss's 300
}
local progress = {}
local loaded = {}
local loading = {}
local dirty = {}
local revision = {}
local saving = {}
local saveScheduled = {}
local SAVE_DELAY_SECONDS = 30
local MAX_ATTEMPTS = 4
local scheduleSave

local function retryDelay(attempt)
	-- Exponential backoff plus jitter prevents a server full of players from
	-- retrying on the same frame after a Roblox DataStore outage.
	return math.min(8, 0.5 * (2 ^ (attempt - 1))) + math.random() * 0.35
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

local function sanitize(value)
	local result = {}
	if type(value) == "table" then
		for key, requirement in pairs(REQUIREMENTS) do
			result[key] = math.clamp(math.floor(tonumber(value[key]) or 0), 0, requirement)
		end
	else
		for key in pairs(REQUIREMENTS) do result[key] = 0 end
	end
	return result
end

local function saveUser(userId)
	while saving[userId] do task.wait() end
	if not loaded[userId] or not dirty[userId] then return true end

	saving[userId] = true
	local player = Players:GetPlayerByUserId(userId)
	local snapshot = sanitize(progress[userId])
	local snapshotRevision = revision[userId] or 0
	local ok, err = false, nil
	for attempt = 1, MAX_ATTEMPTS do
		ok, err = pcall(function()
			STORE:UpdateAsync("Player_" .. userId, function()
				return snapshot
			end)
		end)
		if ok then break end
		if attempt < MAX_ATTEMPTS then task.wait(retryDelay(attempt)) end
	end
	saving[userId] = nil

	if ok then
		-- Do not clear a change that arrived while this snapshot was saving.
		if revision[userId] == snapshotRevision then
			dirty[userId] = nil
		else
			scheduleSave(userId)
		end
	else
		warn("[PortalCucumberProgress] Save failed after retries", player or userId, err)
		if loaded[userId] then scheduleSave(userId) end
	end
	return ok
end

scheduleSave = function(userId)
	if saveScheduled[userId] then return end
	saveScheduled[userId] = true
	task.delay(SAVE_DELAY_SECONDS, function()
		saveScheduled[userId] = nil
		saveUser(userId)
	end)
end

function PortalProgress.Load(player)
	local userId = player.UserId
	if loaded[userId] then return true end
	if loading[userId] then
		while loading[userId] and player.Parent do task.wait() end
		return loaded[userId] == true
	end
	loading[userId] = true
	local ok, value = false, nil
	for attempt = 1, MAX_ATTEMPTS do
		ok, value = pcall(function()
			return STORE:GetAsync(keyFor(player))
		end)
		if ok or not player:IsDescendantOf(Players) then break end
		if attempt < MAX_ATTEMPTS then task.wait(retryDelay(attempt)) end
	end
	loading[userId] = nil
	if not ok then
		warn("[PortalCucumberProgress] Load failed after retries", player, value)
		loaded[userId] = false
		return false
	end
	if not player:IsDescendantOf(Players) then return false end
	progress[userId] = sanitize(value)
	revision[userId] = 0
	loaded[userId] = true
	PortalProgress.Changed:Fire(player)
	return true
end

function PortalProgress.IsLoaded(player)
	return loaded[player.UserId] == true
end

--.. "Smashes required" board upgrade (2026-08-27): -3 required cucumbers per
--.. level (max 3) on every portal (portals ONLY -- boss summon meters are
--.. shared server-wide, so they were deliberately left out). Read live from
--.. the replicated IntValue so a purchase applies to the very next Remaining()
--.. call; progress still clamps to the FULL requirement, only the effective
--.. target shrinks.
local function upgradeReduction(player)
	local playerData = player:FindFirstChild("PlayerData")
	local upgrades = playerData and playerData:FindFirstChild("Upgrades")
	local level = upgrades and upgrades:FindFirstChild("Smashes required")
	return 3 * math.clamp(level and level.Value or 0, 0, 3)
end

function PortalProgress.Requirement(portalKey, player)
	local requirement = REQUIREMENTS[portalKey]
	if not requirement then return math.huge end
	if player then requirement = math.max(0, requirement - upgradeReduction(player)) end
	return requirement
end

function PortalProgress.Remaining(player, portalKey)
	local requirement = REQUIREMENTS[portalKey]
	if not requirement then return math.huge end
	requirement = math.max(0, requirement - upgradeReduction(player))
	if not loaded[player.UserId] then return requirement end
	return math.max(0, requirement - ((progress[player.UserId] or {})[portalKey] or 0))
end

function PortalProgress.NotifyCooldown(player, seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	if seconds <= 0 then return false end
	Network:FireClient(player, "Notif", {
		Message = ("Wait %02d:%02d to enter again!"):format(math.floor(seconds / 60), seconds % 60);
		Type = "Error";
	})
	return true
end

function PortalProgress.NotifyBlocked(player, portalKey)
	local needed = PortalProgress.Remaining(player, portalKey)
	if needed <= 0 or needed == math.huge then return false end
	Network:FireClient(player, "Notif", {
		Message = ("You need %d more cucumbers to enter!"):format(needed);
		Type = "Error";
	})
	return true
end

function PortalProgress.Add(player, portalKey, amount)
	if not PortalProgress.Load(player) then return false end
	local requirement = REQUIREMENTS[portalKey]
	if not requirement then return false end
	local userId = player.UserId
	local data = progress[userId]
	local old = data[portalKey] or 0
	data[portalKey] = math.clamp(old + math.max(0, math.floor(tonumber(amount) or 1)), 0, requirement)
	if data[portalKey] ~= old then
		revision[userId] = (revision[userId] or 0) + 1
		dirty[userId] = true
		scheduleSave(userId)
		PortalProgress.Changed:Fire(player, portalKey)
		return true
	end
	return false
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(PortalProgress.Load, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(PortalProgress.Load, player)
end

function PortalProgress.Reset(player, portalKey)
	if not PortalProgress.Load(player) then return false end
	local data = progress[player.UserId]
	if (data[portalKey] or 0) ~= 0 then
		data[portalKey] = 0
		revision[player.UserId] = (revision[player.UserId] or 0) + 1
		dirty[player.UserId] = true
		scheduleSave(player.UserId)
		PortalProgress.Changed:Fire(player, portalKey)
	end
	return true
end

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	saveUser(userId)
	progress[userId], loaded[userId], loading[userId], dirty[userId] = nil, nil, nil, nil
	revision[userId], saving[userId], saveScheduled[userId] = nil, nil, nil
end)

game:BindToClose(function()
	for userId in pairs(dirty) do
		saveUser(userId)
	end
end)

return PortalProgress
