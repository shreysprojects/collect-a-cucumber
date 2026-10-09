--[[---------------------------------------DESCRIPTION------------------------------------------
	Player DataStore (XP / coins / lifetime coins collected / lifetime distance
	rolled / rebirths / unlocked mountains / owned equipment) and travel between
	mountain places. Load on join, save on leave / autosave / BindToClose. Classic
	and Wooden Shovel are always granted.

	TravelToMountain, Rebirth and Ascend are the client-callable APIs here.
	UnlockMountain is server-only; finishing a run (SERV_Snowball) grants the next
	mountain. Rebirth needs the level PlayerProgress.RebirthLevel(rebirths) (10, 15,
	20, ...), Ascend needs ASCEND_LEVEL (100) and resets everything for a permanent
	13x; both answer false plus "Reach level N first" below their level.

	Save safety: a profile is only saved once its DataStore read succeeded
	(data.Loaded). Until then DATAFILES holds a default placeholder, so a leave /
	autosave / shutdown during the read writes nothing. A read that fails every
	retry marks the profile LoadFailed and kicks the player so they rejoin (in
	Studio they keep playing on defaults and nothing is saved). A forced save
	waits for an autosave that is still writing that player, then writes a fresh
	snapshot. Lifetime totals only grow (a rebirth keeps them), so a write whose
	totals are behind the stored ones is refused as stale.

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local playerProgress = require(ReplicatedStorage.Assets.Modules.Shared.PlayerProgress)()
local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local mountainPlaces = require(ReplicatedStorage.Assets.Modules.Shared.MountainPlaces)()

local STORE_NAME = "RAS_PlayerData_v1"
local AUTOSAVE_SECONDS = 60
local SAVE_RETRY = 3
local LOAD_RETRY = 5
local LOAD_FAILED_MESSAGE = "Couldn't load your data, please rejoin."

local MODULE = {}
local m_api = {}
local m_sapi = {}
local sself = m_sapi

local store = nil
local storeWarned = false
local traveling = {}
local rebirthing = {}

local function getStore()
	if store ~= nil then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		return store
	end
	if not storeWarned then
		storeWarned = true
		warn("[SERVER]: Player DataStore unavailable:", result)
	end
	store = false
	return nil
end

local function storeKey(player)
	local userId = player and player.UserId
	if type(userId) ~= "number" or userId <= 0 then
		return nil
	end
	return "u_" .. tostring(userId)
end

local function toStore(data)
	playerProgress.EnsureUnlocks(data)
	return {
		Level = data.Level,
		XP = data.XP,
		Coins = data.Coins,
		TotalCoinsCollected = data.TotalCoinsCollected,
		TotalDistanceRolled = data.TotalDistanceRolled,
		UnlockedMountains = playerProgress.UnlockList(data.UnlockedMountains),
		UnlockedSnowballs = playerProgress.NameList(data.UnlockedSnowballs, playerProgress.STARTER_SNOWBALL),
		UnlockedLaunchers = playerProgress.NameList(data.UnlockedLaunchers, playerProgress.STARTER_LAUNCHER),
		EquippedSnowball = data.EquippedSnowball,
		EquippedLauncher = data.EquippedLauncher,
		Rebirths = data.Rebirths,
		Ascensions = data.Ascensions,
	}
end

local function applySaved(data, saved)
	if type(saved) ~= "table" then
		return data
	end
	if type(saved.Level) == "number" then
		data.Level = math.clamp(math.floor(saved.Level), 1, playerProgress.MAX_LEVEL)
	end
	if type(saved.XP) == "number" then
		data.XP = math.max(0, math.floor(saved.XP))
	end
	if type(saved.Coins) == "number" then
		data.Coins = math.max(0, math.floor(saved.Coins))
	end
	if type(saved.TotalCoinsCollected) == "number" then
		data.TotalCoinsCollected = math.max(0, math.floor(saved.TotalCoinsCollected))
	else
		data.TotalCoinsCollected = data.Coins or 0
	end
	if type(saved.TotalDistanceRolled) == "number" then
		data.TotalDistanceRolled = math.max(0, math.floor(saved.TotalDistanceRolled))
	end
	if saved.UnlockedMountains ~= nil then
		data.UnlockedMountains = saved.UnlockedMountains
	end
	if saved.UnlockedSnowballs ~= nil then
		data.UnlockedSnowballs = saved.UnlockedSnowballs
	end
	if saved.UnlockedLaunchers ~= nil then
		data.UnlockedLaunchers = saved.UnlockedLaunchers
	end
	if type(saved.EquippedSnowball) == "string" then
		data.EquippedSnowball = saved.EquippedSnowball
	end
	if type(saved.EquippedLauncher) == "string" then
		data.EquippedLauncher = saved.EquippedLauncher
	end
	if type(saved.Rebirths) == "number" then
		data.Rebirths = math.max(0, math.floor(saved.Rebirths))
	end
	if type(saved.Ascensions) == "number" then
		data.Ascensions = math.max(0, math.floor(saved.Ascensions))
	end
	playerProgress.EnsureUnlocks(data)
	return data
end

-- Lifetime totals only grow (ApplyRebirth keeps them), so a stored save that is
-- ahead of the payload came from a newer session: never write over it. An ascension
-- resets the totals but bumps Ascensions, which only ever grows: a payload with more
-- ascensions is the newer one whatever its totals say; one with fewer is stale.
local function isBehind(stored, payload)
	if type(stored) ~= "table" then
		return false
	end
	local storedAscensions = math.floor(tonumber(stored.Ascensions) or 0)
	local payloadAscensions = math.floor(tonumber(payload.Ascensions) or 0)
	if payloadAscensions ~= storedAscensions then
		return payloadAscensions < storedAscensions
	end
	local storedCoins = math.floor(tonumber(stored.TotalCoinsCollected) or 0)
	local storedRolled = math.floor(tonumber(stored.TotalDistanceRolled) or 0)
	return storedCoins > payload.TotalCoinsCollected or storedRolled > payload.TotalDistanceRolled
end

local function withRetry(label, fn, tries)
	tries = tries or SAVE_RETRY
	local lastErr
	for attempt = 1, tries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < tries then
			task.wait(0.4 * attempt)
		end
	end
	warn("[SERVER]:", label, lastErr)
	return false, lastErr
end

function MODULE.new(r_sapi)
	sself = r_sapi
	sself.DATAFILES = sself.DATAFILES or {}
	sself.PlayerDataSaving = sself.PlayerDataSaving or {}

	if not sself.PlayerDataBound then
		sself.PlayerDataBound = true
		game:BindToClose(function()
			sself:SaveAllPlayerData(true)
			if RunService:IsStudio() then
				task.wait(0.5)
			end
		end)
		task.spawn(function()
			while true do
				task.wait(AUTOSAVE_SECONDS)
				sself:SaveAllPlayerData(false)
			end
		end)
	end

	return m_api, m_sapi
end

function m_sapi:LoadPlayerData(player)
	if not player then
		return nil
	end

	local existing = sself.DATAFILES[player.Name]
	if existing and existing.Loaded then
		return existing
	end

	-- Placeholder until the read succeeds: SavePlayerData skips a profile that is
	-- not Loaded, so a leave / autosave during the read never writes these defaults.
	local data = existing or playerProgress.DefaultProfile()
	playerProgress.EnsureUnlocks(data)
	data.Loaded = false
	data.LoadFailed = nil
	sself.DATAFILES[player.Name] = data

	local grantedEquipment = true
	local missingCoins = true
	local missingTotals = true
	local key = storeKey(player)
	local ds = key and getStore()
	if ds then
		local ok, saved = withRetry("LoadPlayerData " .. player.Name, function()
			return ds:GetAsync(key)
		end, LOAD_RETRY)
		if sself.DATAFILES[player.Name] ~= data or not player.Parent then
			-- They left (PlayerRemoving dropped the placeholder) while the read ran.
			return nil
		end
		if not ok then
			data.LoadFailed = true
			data.Dirty = false
			if RunService:IsStudio() then
				warn("[SERVER]: Couldn't load", player.Name, "data - playing on defaults, nothing will be saved this session")
				return data
			end
			warn("[SERVER]: Couldn't load", player.Name, "data - kicking them so their save is not overwritten")
			player:Kick(LOAD_FAILED_MESSAGE)
			return nil
		end
		applySaved(data, saved)
		missingCoins = type(saved) ~= "table" or type(saved.Coins) ~= "number"
		missingTotals = type(saved) ~= "table"
			or type(saved.TotalCoinsCollected) ~= "number"
			or type(saved.TotalDistanceRolled) ~= "number"
		grantedEquipment = type(saved) ~= "table"
			or saved.UnlockedSnowballs == nil
			or saved.UnlockedLaunchers == nil
			or type(saved.EquippedSnowball) ~= "string"
			or type(saved.EquippedLauncher) ~= "string"
	end

	data.Loaded = true
	data.Dirty = grantedEquipment or missingCoins or missingTotals
	print("[SERVER]: Loaded player data", player.Name, "unlocks", playerProgress.EncodeUnlocks(data.UnlockedMountains), "equipped", data.EquippedSnowball, data.EquippedLauncher, "collected", data.TotalCoinsCollected, "rolled", data.TotalDistanceRolled, "rebirths", data.Rebirths)
	return data
end

function m_sapi:SavePlayerData(player, force)
	if not player then
		return false
	end

	local data = sself.DATAFILES[player.Name]
	if not data then
		return false
	end
	-- Still loading, or the read failed: these are defaults, not the player's
	-- save, and writing them would wipe it.
	if not data.Loaded or data.LoadFailed then
		return false
	end
	if not force and not data.Dirty then
		return true
	end

	local key = storeKey(player)
	local ds = key and getStore()
	if not ds then
		data.Dirty = false
		return false
	end

	if sself.PlayerDataSaving[player] then
		if not force then
			return false
		end
		-- Leave / shutdown / travel / rebirth: don't drop this save while the
		-- autosave writes an older snapshot; wait, then write the current data.
		while sself.PlayerDataSaving[player] do
			task.wait()
		end
	end
	sself.PlayerDataSaving[player] = true

	-- Cleared before the snapshot, so a change made during the write stays Dirty.
	data.Dirty = false
	local payload = toStore(data)
	local stale = false
	local ok = withRetry("SavePlayerData " .. player.Name, function()
		ds:UpdateAsync(key, function(stored)
			stale = isBehind(stored, payload)
			if stale then
				return nil
			end
			return payload
		end)
	end)

	sself.PlayerDataSaving[player] = nil
	if ok and stale then
		warn("[SERVER]: Not saving", player.Name, "- the stored lifetime totals are ahead of this server's copy")
		ok = false
	end
	if not ok then
		data.Dirty = true
	end
	return ok
end

function m_sapi:SaveAllPlayerData(force)
	for _, player in Players:GetPlayers() do
		sself:SavePlayerData(player, force)
	end
end

function m_sapi:MarkPlayerDataDirty(player)
	local data = sself.DATAFILES[player and player.Name]
	if data then
		data.Dirty = true
	end
end

function m_sapi:UnlockMountain(player, mountainId)
	mountainId = mountainPlaces.NormalizeMountainId(mountainId)
	if not player or not mountainId then
		return false
	end

	local data = sself:GetPlayerProgress(player)
	if not data then
		return false
	end

	if not playerProgress.UnlockMountain(data, mountainId) then
		return false
	end

	data.Dirty = true
	sself:ReplicateProgress(player)
	sself:SavePlayerData(player, true)
	print("[SERVER]: Unlocked mountain", mountainId, "for", player.Name)
	return true
end

function m_sapi:UnlockNextMountain(player)
	local current = mountainPlaces.GetCurrentMountainId()
	local nextId = mountainConfig:GetNextMountain(current)
	if not nextId then
		return false
	end
	return sself:UnlockMountain(player, nextId)
end

function m_sapi:EnforceMountainAccess(player)
	if not player or RunService:IsStudio() then
		return
	end

	local current = mountainPlaces.GetCurrentMountainId()
	if current == mountainPlaces.START_MOUNTAIN then
		return
	end

	local data = sself:GetPlayerProgress(player)
	-- Defaults from a failed read would bounce them off a mountain they own.
	if not data or not data.Loaded or data.LoadFailed then
		return
	end
	if playerProgress.IsUnlocked(data, current) then
		return
	end

	local placeId, environment = mountainPlaces.GetPlaceId(mountainPlaces.START_MOUNTAIN)
	if not placeId then
		warn("[SERVER]:", player.Name, "is on locked mountain", current, "but", mountainPlaces.START_MOUNTAIN, "has no place ID (", environment, ")")
		return
	end

	print("[SERVER]: Sending", player.Name, "from locked", current, "to", mountainPlaces.START_MOUNTAIN)
	sself:SavePlayerData(player, true)
	pcall(function()
		TeleportService:TeleportAsync(placeId, { player })
	end)
end

-- After a rebirth / ascension reset: save, end any ride, hand back the starter launcher.
local function finishReset(player, label)
	local callOk, callErr = pcall(function()
		sself:SavePlayerData(player, true)
		if sself.MountainFinishing then
			sself.MountainFinishing[player] = nil
		end
		sself:ClearSnowball(player)
		ReplicatedStorage.ReEvent:FireClient(player, "UnbindSnowballCamera")
		sself:ClearLauncher(player)
		if sself:IsPlayerOnLaunchPad(player) then
			sself:GiveLauncher(player, playerProgress.STARTER_LAUNCHER)
		end
		sself:EnforceMountainAccess(player)
	end)
	if not callOk then
		warn("[SERVER]:", label, "reset saved in memory, but a follow-up step failed:", callErr)
	end
end

function m_api:Rebirth(player)
	if not player or rebirthing[player] then
		return false, "Already rebirthing"
	end

	local data = sself:GetPlayerProgress(player)
	if not data then
		return false, "Rebirth failed"
	end
	local ready, needLevel = playerProgress.CanRebirth(data)
	if not ready then
		return false, string.format("Reach level %d first", needLevel)
	end
	if not playerProgress.ApplyRebirth(data) then
		return false, "Rebirth failed"
	end

	rebirthing[player] = true
	data.Dirty = true
	sself:ReplicateProgress(player)
	finishReset(player, "Rebirth")
	rebirthing[player] = nil

	print("[SERVER]:", player.Name, "rebirthed to", data.Rebirths)
	return true
end

-- The heavenly wings: level ASCEND_LEVEL resets everything for a permanent 13x per ascension.
function m_api:Ascend(player)
	if not player or rebirthing[player] then
		return false, "Already ascending"
	end

	local data = sself:GetPlayerProgress(player)
	if not data then
		return false, "Ascend failed"
	end
	local ready, needLevel = playerProgress.CanAscend(data)
	if not ready then
		return false, string.format("Reach level %d first", needLevel)
	end
	if not playerProgress.ApplyAscend(data) then
		return false, "Ascend failed"
	end

	rebirthing[player] = true
	data.Dirty = true
	sself:ReplicateProgress(player)
	finishReset(player, "Ascend")
	rebirthing[player] = nil

	print("[SERVER]:", player.Name, "ascended to", data.Ascensions, "power x" .. tostring(playerProgress.AscendMultiplier(data.Ascensions)))
	return true
end

function m_api:TravelToMountain(player, mountainId)
	if traveling[player] then
		return false, "Already traveling"
	end

	mountainId = mountainPlaces.NormalizeMountainId(mountainId)
	if not mountainId then
		return false, "Unknown mountain"
	end

	local data = sself:GetPlayerProgress(player)
	if not data or not playerProgress.IsUnlocked(data, mountainId) then
		return false, "Mountain is locked"
	end

	local current = mountainPlaces.GetCurrentMountainId()
	if mountainId == current then
		return false, "Already on this mountain"
	end

	if RunService:IsStudio() then
		return false, "Can't travel between places in Studio. Set ReplicatedFirst.StudioSettings.MountainId and play."
	end

	local placeId, environment = mountainPlaces.GetPlaceId(mountainId)
	if not placeId then
		return false, string.format("No place ID set for %s (%s). Add it in MountainPlaces.", mountainId, environment or "?")
	end

	if placeId == game.PlaceId then
		return false, "Already on this mountain"
	end

	traveling[player] = true
	sself:ClearSnowball(player)
	sself:SavePlayerData(player, true)

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, { player })
	end)
	if not ok then
		traveling[player] = nil
		warn("[SERVER]: Teleport to", mountainId, "failed:", err)
		return false, "Teleport failed"
	end

	print("[SERVER]: Travel", player.Name, "->", mountainId, placeId)
	return true
end

return MODULE
