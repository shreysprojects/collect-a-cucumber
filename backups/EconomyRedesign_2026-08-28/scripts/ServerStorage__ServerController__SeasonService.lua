--..Services..--
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local Network = ControllerLoader.GetController("Network")
local NumberController = ControllerLoader.GetController("NumberController")

--..Config..--
local SEASON_ENABLED = false -- MASTER SWITCH. Flip to true (and set SEASON_EPOCH to release Monday) to launch Season 1.
-- NOTE for launch: the Hall of Green is now the per-player ScreenGui StarterGui.HallOfGreen —
-- wire a FireAllClients("HallData", ...) feed + client handler to fill SeasonLabel/Countdown/TopList/Champions.
local SEASON_EPOCH = 1783296000 -- Monday, July 6 2026 00:00 UTC. EDIT THIS to the Monday of release week.
local SEASON_LENGTH = 7 * 24 * 60 * 60 -- one week
local PUSH_INTERVAL = 120 -- seconds between standings pushes
local TRACKED = {"Cucumbers", "Coins"}

local REWARDS = {
	CucumbersChampion = "Golden Cucumber";
	CoinsChampion = "Solid Gold Coin";
	CucumbersTop10 = "Silver Pickle";
}

--..Variables..--
local SeasonService = {}

local WinnersStore = DataStoreService:GetDataStore("CucumberSeasonWinners_L2") -- versioned so Studio test data can't pollute launch seasons
local WinnersCache = {} -- [season] = snapshot table (only truthy results cached)
local NameCache = {} -- [userId] = username

--..Functions..--

function SeasonService.GetCurrentSeason()
	local now = os.time()
	if now < SEASON_EPOCH then return 0 end
	return math.floor((now - SEASON_EPOCH) / SEASON_LENGTH) + 1
end

function SeasonService.GetSeasonEndTime(season)
	return SEASON_EPOCH + season * SEASON_LENGTH
end

local function GetSeasonStore(season, stat)
	return DataStoreService:GetOrderedDataStore(("CucumberSeasonL2_%d_%s"):format(season, stat))
end

local function GetName(userId)
	if NameCache[userId] then return NameCache[userId] end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		NameCache[userId] = name
		return name
	end
	return "???"
end

local function EnsureSeason(profile)
	local current = SeasonService.GetCurrentSeason()
	local ss = profile.SeasonStats
	if ss.Season ~= current then
		ss.Season = current
		ss.Cucumbers = 0
		ss.Coins = 0
	end
	return ss
end

function SeasonService.AddSeasonStat(Player, Currency, Amount)
	if not SEASON_ENABLED then return end
	if not table.find(TRACKED, Currency) then return end
	if SeasonService.GetCurrentSeason() < 1 then return end
	local profile = ProfileService.GetUserData(Player)
	if not profile or not profile.SeasonStats then return end
	local ss = EnsureSeason(profile)
	ss[Currency] += Amount
end

local function PushStandings()
	local season = SeasonService.GetCurrentSeason()
	if season < 1 then return end
	for _,Player in ipairs(Players:GetPlayers()) do
		local profile = ProfileService.GetUserData(Player)
		if profile and profile.SeasonStats then
			local ss = EnsureSeason(profile)
			if ss.Season == season then
				for _,stat in ipairs(TRACKED) do
					local value = math.floor(ss[stat])
					if value > 0 then
						pcall(function()
							GetSeasonStore(season, stat):SetAsync(Player.UserId, value)
						end)
					end
				end
			end
		end
		task.wait()
	end
end

function SeasonService.GetWinners(season)
	if WinnersCache[season] then return WinnersCache[season] end
	local ok, result = pcall(function()
		return WinnersStore:GetAsync("Season" .. season)
	end)
	if ok and result then
		WinnersCache[season] = result
	end
	if ok then return result end
	return nil
end

local function FinalizeSeason(season)
	local snapshot = {FinalizedAt = os.time()}
	for _,stat in ipairs(TRACKED) do
		local ok, page = pcall(function()
			return GetSeasonStore(season, stat):GetSortedAsync(false, 10):GetCurrentPage()
		end)
		if not ok then return false end
		local list = {}
		for rank, entry in ipairs(page) do
			table.insert(list, {UserId = tonumber(entry.key), Value = entry.value, Rank = rank})
		end
		snapshot[stat] = list
	end

	-- cross-server lock: UpdateAsync only writes if nobody finalized first
	local wonLock = false
	local ok = pcall(function()
		WinnersStore:UpdateAsync("Season" .. season, function(old)
			if old ~= nil then return nil end
			wonLock = true
			return snapshot
		end)
	end)
	if not ok then return false end

	WinnersCache[season] = WinnersCache[season] or snapshot

	if wonLock then
		local champ = snapshot.Cucumbers and snapshot.Cucumbers[1]
		if champ then
			local name = GetName(champ.UserId)
			for _,plr in ipairs(Players:GetPlayers()) do
				Network:FireClient(plr, "Notif", {Message = ("SEASON %d: %s WINS!"):format(season, string.upper(name)); Type = "Success";})
			end
		end
	end
	return true
end

local function GrantSeasonRewards(Player, season)
	local winners = SeasonService.GetWinners(season)
	if not winners then return end

	local profile = ProfileService.GetUserData(Player)
	if not profile then return end
	if profile.ClaimedSeasonRewards == nil then profile.ClaimedSeasonRewards = {} end
	local key = "Season" .. season
	if profile.ClaimedSeasonRewards[key] then return end
	profile.ClaimedSeasonRewards[key] = true

	local earned = {}

	for _,entry in ipairs(winners.Cucumbers or {}) do
		if entry.UserId == Player.UserId then
			if entry.Rank == 1 then
				table.insert(earned, REWARDS.CucumbersChampion)
				profile.GoldenChampion = true
			else
				table.insert(earned, REWARDS.CucumbersTop10)
			end
		end
	end
	for _,entry in ipairs(winners.Coins or {}) do
		if entry.UserId == Player.UserId and entry.Rank == 1 then
			table.insert(earned, REWARDS.CoinsChampion)
		end
	end

	if #earned == 0 then return end

	local PetService = ServerController.GetModule("PetService")
	for _,petName in ipairs(earned) do
		PetService.AddPetToPlayer({Player = Player; Pet = petName})
		Network:FireClient(Player, "Notif", {Message = ("SEASON %d REWARD: %s!"):format(season, string.upper(petName)); Type = "Success";})
		task.wait(0.5)
	end
end

function SeasonService.PlayerJoined(Player)
	if not SEASON_ENABLED then return end
	local profile
	for i = 1, 30 do
		profile = ProfileService.GetUserData(Player)
		if profile then break end
		task.wait(1)
	end
	if not profile or not profile.SeasonStats then return end
	EnsureSeason(profile)

	local current = SeasonService.GetCurrentSeason()
	for season = math.max(1, current - 4), current - 1 do
		GrantSeasonRewards(Player, season)
	end
end

function SeasonService.CharacterJoined(Character)
	if not SEASON_ENABLED then return end
	local Player = Players:GetPlayerFromCharacter(Character)
	if not Player then return end
	local profile = ProfileService.GetUserData(Player)
	if not profile or not profile.GoldenChampion then return end

	task.spawn(function()
		local head = Character:WaitForChild("Head", 15)
		if not head then return end
		local tag = head:WaitForChild("Tag", 15)
		if tag then
			local frame = tag:FindFirstChild("Frame")
			local nameLabel = frame and frame:FindFirstChild("PlayerName")
			if nameLabel then
				nameLabel.Text = "\u{1F451} " .. nameLabel.Text
				nameLabel.TextColor3 = Color3.fromRGB(255, 213, 0)
			end
		end
		local torso = Character:FindFirstChild("UpperTorso") or Character:FindFirstChild("Torso")
		if torso and not torso:FindFirstChild("GoldenAura") then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "GoldenAura"
			emitter.Color = ColorSequence.new(Color3.fromRGB(255, 213, 0))
			emitter.LightEmission = 1
			emitter.Rate = 6
			emitter.Lifetime = NumberRange.new(1, 1.6)
			emitter.Speed = NumberRange.new(0.5, 1.5)
			emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0)})
			emitter.Transparency = NumberSequence.new(0.2)
			emitter.Parent = torso
		end
	end)
end

function SeasonService.Initialize()
	if not SEASON_ENABLED then return end

	local lastKnownSeason = SeasonService.GetCurrentSeason()
	while true do
		PushStandings()

		local current = SeasonService.GetCurrentSeason()
		local prev = current - 1
		if prev >= 1 and not SeasonService.GetWinners(prev) then
			FinalizeSeason(prev)
			-- immediately grant to anyone online
			for _,plr in ipairs(Players:GetPlayers()) do
				task.spawn(GrantSeasonRewards, plr, prev)
			end
		end
		lastKnownSeason = current

		task.wait(PUSH_INTERVAL)
	end
end

return SeasonService
