--[[---------------------------------------DESCRIPTION------------------------------------------
	XP / coins / lifetime coins collected / lifetime distance rolled / rebirths /
	mountain unlocks / owned equipment. Creates leaderstats.Coins and replicates
	Level, XP, XPNeeded, Coins, the lifetime totals, Rebirths, RebirthLevel (the
	level the next rebirth needs), UnlockedMountains, owned snowballs / launchers,
	the equipped names, and the gear multiplier as player attributes.
	UnlockedMountains is PlayerProgress.EffectiveUnlocks: the same map the shop's
	purchase gate reads (Studio UnlockAll included).

--------------------------------------------------------------------------------------------]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playerProgress = require(ReplicatedStorage.Assets.Modules.Shared.PlayerProgress)()

local MODULE = {}
local m_api = {}
local m_sapi = {}
local sself = m_sapi

function MODULE.new(r_sapi)
	sself = r_sapi
	sself.DATAFILES = sself.DATAFILES or {}
	return m_api, m_sapi
end

local function getLeaderstat(player, name)
	local folder = player:FindFirstChild("leaderstats")
	local value = folder and folder:FindFirstChild(name)
	if value and value:IsA("IntValue") then
		return value
	end
	return nil
end

function m_sapi:GetPlayerProgress(player)
	if not player then
		return nil
	end
	local data = sself.DATAFILES[player.Name]
	if data then
		return data
	end
	return sself:SetupPlayerProgress(player)
end

function m_sapi:ReplicateProgress(player)
	local data = sself.DATAFILES[player.Name]
	if not data or not player.Parent then
		return
	end

	player:SetAttribute("Level", data.Level)
	player:SetAttribute("XP", data.XP)
	player:SetAttribute("XPNeeded", playerProgress.XpToNext(data.Level))
	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("TotalCoinsCollected", data.TotalCoinsCollected or 0)
	player:SetAttribute("TotalDistanceRolled", data.TotalDistanceRolled or 0)

	playerProgress.EnsureUnlocks(data)
	player:SetAttribute("Rebirths", data.Rebirths or 0)
	player:SetAttribute("RebirthLevel", playerProgress.RebirthLevel(data.Rebirths))
	player:SetAttribute("UnlockedMountains", playerProgress.EncodeUnlocks(playerProgress.EffectiveUnlocks(data)))
	player:SetAttribute("UnlockedSnowballs", playerProgress.EncodeNames(data.UnlockedSnowballs, playerProgress.STARTER_SNOWBALL))
	player:SetAttribute("UnlockedLaunchers", playerProgress.EncodeNames(data.UnlockedLaunchers, playerProgress.STARTER_LAUNCHER))
	player:SetAttribute("EquippedSnowball", data.EquippedSnowball)
	player:SetAttribute("EquippedLauncher", data.EquippedLauncher)
	player:SetAttribute("Multiplier", playerProgress.EquipmentMultiplier(data.EquippedSnowball, data.EquippedLauncher))

	local coins = getLeaderstat(player, "Coins")
	if coins then
		coins.Value = data.Coins
	end
end

function m_sapi:SetupPlayerProgress(player)
	if not player then
		return nil
	end

	local data = sself.DATAFILES[player.Name]
	if not data then
		data = playerProgress.DefaultProfile()
		playerProgress.EnsureUnlocks(data)
		sself.DATAFILES[player.Name] = data
	end

	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end

	local coins = folder:FindFirstChild("Coins")
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = folder
	end
	coins.Value = data.Coins

	sself:ReplicateProgress(player)
	return data
end

function m_sapi:AwardProgress(player, xp, coins)
	local data = sself:GetPlayerProgress(player)
	if not data then
		return false
	end

	local coinGain = math.floor(tonumber(coins) or 0)
	local xpGain = math.floor(tonumber(xp) or 0)
	if coinGain == 0 and xpGain == 0 then
		return false
	end

	if coinGain > 0 then
		data.Coins = math.max(0, (tonumber(data.Coins) or 0) + coinGain)
		data.TotalCoinsCollected = math.max(0, math.floor(tonumber(data.TotalCoinsCollected) or 0)) + coinGain
	elseif coinGain < 0 then
		data.Coins = math.max(0, (tonumber(data.Coins) or 0) + coinGain)
	end
	if xpGain ~= 0 then
		playerProgress.ApplyXp(data, xpGain)
	end

	data.Dirty = true
	sself:ReplicateProgress(player)
	return true
end

function m_sapi:AddRolledDistance(player, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or not player then
		return false
	end

	local data = sself:GetPlayerProgress(player)
	if not data then
		return false
	end

	data.TotalDistanceRolled = math.max(0, math.floor(tonumber(data.TotalDistanceRolled) or 0)) + amount
	data.Dirty = true
	if player.Parent then
		player:SetAttribute("TotalDistanceRolled", data.TotalDistanceRolled)
	end
	return true
end

return MODULE
