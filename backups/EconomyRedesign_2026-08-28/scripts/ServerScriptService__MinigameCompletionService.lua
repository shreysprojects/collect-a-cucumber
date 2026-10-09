-- Confirms when the local completion celebration has completely finished.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local effects = ReplicatedStorage:WaitForChild("MinigameEffects")
local finished = effects:FindFirstChild("Finished") or Instance.new("RemoteEvent")
finished.Name = "Finished"
finished.Parent = effects
local chooseReward = effects:FindFirstChild("ChooseReward") or Instance.new("RemoteFunction")
chooseReward.Name = "ChooseReward"
chooseReward.Parent = effects

--.. Weighted reward pool. Cucumber prizes represent the player's production
--.. over the listed duration; their exact payout is quoted and locked server-side.
local REWARD_POOL = {
	{ id = "cucumber_1m",  weight = 17 },
	{ id = "cucumber_2m",  weight = 15 },
	{ id = "cucumber_3m",  weight = 12 },
	{ id = "cucumber_5m",  weight = 10 },
	{ id = "cucumber_10m", weight = 8 },
	{ id = "cucumber_30m", weight = 5 },
	{ id = "cucumber_15m", weight = 9 },
	{ id = "cucumber_1h",  weight = 4 },
	{ id = "shard_1",      weight = 9 },
	{ id = "shard_3",      weight = 4 },
	{ id = "foodegg_1",    weight = 7 },
	--.. coin prizes: the player's VAULT earnings over the listed duration
	--.. (empty vault downgrades to the matching cucumber prize at pick time)
	{ id = "coins_2m",     weight = 10 },
	{ id = "coins_5m",     weight = 8 },
	{ id = "coins_15m",    weight = 6 },
	{ id = "coins_30m",    weight = 3 },
}
local TOTAL_WEIGHT = 0
for _, entry in ipairs(REWARD_POOL) do TOTAL_WEIGHT += entry.weight end

local function pickRewardId()
	local roll = math.random() * TOTAL_WEIGHT
	local counter = 0
	for _, entry in ipairs(REWARD_POOL) do
		counter += entry.weight
		if roll <= counter then return entry.id end
	end
	return REWARD_POOL[1].id
end

local CUCUMBER_REWARD_SECONDS = {
	cucumber_1m = 60,
	cucumber_2m = 120,
	cucumber_3m = 180,
	cucumber_5m = 300,
	cucumber_10m = 600,
	cucumber_15m = 900,
	cucumber_30m = 1800,
	cucumber_1h = 3600,
}
--.. coin prizes mirror the cucumber ones but quote the player's VAULT coin
--.. production (VaultTimeSkipService) instead of cucumber production
local COIN_REWARD_SECONDS = {
	coins_2m = 120,
	coins_5m = 300,
	coins_15m = 900,
	coins_30m = 1800,
}
--.. an empty vault quotes 0 coins; the pick falls back to the same-duration
--.. cucumber prize so nobody ever wins a "+0 Coins" card
local COIN_TO_CUCUMBER = {
	coins_2m = "cucumber_2m",
	coins_5m = "cucumber_5m",
	coins_15m = "cucumber_15m",
	coins_30m = "cucumber_30m",
}
local SHARD_COUNTS = { shard_1 = 1, shard_3 = 3 }
--.. mirrors BreakablesService.BOSS_PETS (that table is module-local)
local BOSS_PETS = {
	Spawn = "Colossal Cucumber"; Desert = "Cactus Colossus";
	Samurai = "Shogun Colossus"; Farm = "Harvest Colossus";
	Snow = "Frozen Colossus"; Underwater = "Abyssal Colossus";
	Volcano = "Magma Colossus"; Narmek = "Cosmic Colossus";
}
local SHARDS_PER_PET = 10

--.. Actually pays the reward out. Rate-based cucumber rewards are already
--.. multiplier-adjusted by TimeSkipRateService, shards bank into the player's HIGHEST
--.. unlocked zone's boss bucket, and the food egg rolls the real hatch (pity included).
local function grantReward(player, id, securedCucumberAmount)
	local ok, err = pcall(function()
		local ServerStorage = game:GetService("ServerStorage")
		local ServerController = require(ServerStorage:WaitForChild("ServerController"))
		local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
		local Network = ControllerLoader.GetController("Network")
		local NumberController = ControllerLoader.GetController("NumberController")

		local rewardSeconds = CUCUMBER_REWARD_SECONDS[id]
		if rewardSeconds then
			local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
			local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
			local amount = tonumber(securedCucumberAmount)
			if not amount or amount ~= amount or amount < 1 or amount == math.huge then
				amount = TimeSkipRateService.Quote(player, rewardSeconds)
			end
			amount = math.max(1, math.floor(amount))
			CurrencyHandler.AddCurrency({
				Player = player; Currency = "Cucumbers"; HasTotal = true;
				Amount = amount; WasPurchase = true;
			})
			Network:FireClient(player, "Notif", {Message = ("\u{1F952} +%s CUCUMBERS!"):format(
				NumberController.SuffixNumber(amount)); Type = "Success";})
			return
		end

		local coinSeconds = COIN_REWARD_SECONDS[id]
		if coinSeconds then
			--.. quoted from the player's vault production; the quote already
			--.. carries the coin multipliers, so the award is flat
			local VaultTimeSkipService = ServerController.GetModule("VaultTimeSkipService")
			local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
			local amount = tonumber(securedCucumberAmount)
			if not amount or amount ~= amount or amount < 1 or amount == math.huge then
				amount = VaultTimeSkipService.Quote(player, coinSeconds)
			end
			amount = math.max(1, math.floor(amount))
			CurrencyHandler.AddCurrency({
				Player = player; Currency = "Coins"; HasTotal = true;
				Amount = amount; WasPurchase = true;
			})
			Network:FireClient(player, "Notif", {Message = ("\u{1F4B0} +$%s COINS!"):format(
				NumberController.SuffixNumber(amount)); Type = "Success";})
			return
		end

		--.. shard ids arrive zone-qualified from pick time ("shard_3_Volcano") so the
		--.. reel, the reveal text, and the grant all agree on WHICH boss's shard it is
		local shardsText, shardZone = id:match("^shard_(%d+)_(%a+)$")
		local shards = tonumber(shardsText) or SHARD_COUNTS[id]
		if shards then
			local ProfileService = ServerController.GetModule("ProfileService")
			local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
			local profile = ProfileService.GetUserData(player)
			if not profile then return end
			local zone = (shardZone and BOSS_PETS[shardZone]) and shardZone
				or TimeSkipRateService.HighestUnlockedZone(player)
			local petName = BOSS_PETS[zone] or "Colossal Cucumber"
			profile.BossShards = profile.BossShards or {}
			profile.BossShards[zone] = (profile.BossShards[zone] or 0) + shards
			Network:FireClient(player, "ShardEffect")
			local remaining = SHARDS_PER_PET - profile.BossShards[zone]
			if remaining > 0 then
				Network:FireClient(player, "Notif", {Message = ("\u{1F48E} +%d %s SHARD%s!"):format(
					shards, petName, shards == 1 and "" or "S", remaining); Type = "Success";})
			else
				Network:FireClient(player, "Notif", {Message = ("\u{1F48E} %s SHARDS READY \u{2014} FORGE YOUR PET!"):format(
					petName); Type = "Success";})
			end
			return
		end

		if id == "foodegg_1" then
			local EggService = require(ServerStorage.ServerController.PetService.EggService)
			local hatchedName
			local rolled, result = pcall(EggService.GenerateRandomPet, player, "Food Cuke Egg", "Single")
			if rolled and type(result) == "table" and type(result[1]) == "string" then
				hatchedName = result[1]
			end
			Network:FireClient(player, "Notif", {Message = hatchedName
				and ("\u{1F95A} HATCHED %s!"):format(string.upper(hatchedName))
				or "\u{1F95A} +1 FOOD CUKE EGG!"; Type = "Success";})
			return
		end

		warn("[MinigameCompletionService] unknown reward id:", id)
	end)
	if not ok then
		warn("[MinigameCompletionService] grant failed for", id, err)
	end
end

local function getTimeSkipRateService()
	local ServerController = require(game:GetService("ServerStorage"):WaitForChild("ServerController"))
	return ServerController.GetModule("TimeSkipRateService")
end

local function getVaultTimeSkipService()
	local ServerController = require(game:GetService("ServerStorage"):WaitForChild("ServerController"))
	return ServerController.GetModule("VaultTimeSkipService")
end

--.. locks the exact payout of any rate-quoted prize (cucumber OR coin) at
--.. pick time so nothing during the spinner can change what the card pays
local function lockCucumberAmount(player, rewardId)
	local seconds = CUCUMBER_REWARD_SECONDS[rewardId]
	if seconds then
		local amount = getTimeSkipRateService().Quote(player, seconds)
		player:SetAttribute("PendingMinigameRewardAmount", amount)
		return amount
	end
	local coinSeconds = COIN_REWARD_SECONDS[rewardId]
	if coinSeconds then
		local amount = getVaultTimeSkipService().Quote(player, coinSeconds)
		player:SetAttribute("PendingMinigameRewardAmount", amount)
		return amount
	end
	player:SetAttribute("PendingMinigameRewardAmount", nil)
	return nil
end

local function secureReward(player, token)
	if type(token) ~= "string" or player:GetAttribute("MinigameCompletionToken") ~= token then return nil end
	local pending = player:GetAttribute("PendingMinigameReward")
	if type(pending) == "string" then
		if (CUCUMBER_REWARD_SECONDS[pending] or COIN_REWARD_SECONDS[pending]) and type(player:GetAttribute("PendingMinigameRewardAmount")) ~= "number" then
			lockCucumberAmount(player, pending)
		end
		return pending
	end

	pending = pickRewardId()
	if COIN_REWARD_SECONDS[pending] then
		--.. an empty vault quotes 0: swap to the same-duration cucumber prize
		local coins = 0
		pcall(function()
			coins = getVaultTimeSkipService().Quote(player, COIN_REWARD_SECONDS[pending])
		end)
		if not coins or coins < 1 then
			pending = COIN_TO_CUCUMBER[pending] or "cucumber_5m"
		end
	end
	if SHARD_COUNTS[pending] then
		local zone = "Spawn"
		pcall(function()
			zone = getTimeSkipRateService().HighestUnlockedZone(player)
		end)
		pending = pending .. "_" .. (BOSS_PETS[zone] and zone or "Spawn")
	end

	-- Reserve both the result and its exact cucumber quote now. Equipment/rate changes
	-- during the spinner can never change what its winning card ultimately pays.
	player:SetAttribute("PendingMinigameReward", pending)
	player:SetAttribute("MinigameRewardSecuredToken", token)
	lockCucumberAmount(player, pending)
	return pending
end

local function rewardPayload(player, pending)
	if type(pending) ~= "string" then return nil end
	local amounts = {}
	local ok, service = pcall(getTimeSkipRateService)
	if ok and service then
		for id, seconds in pairs(CUCUMBER_REWARD_SECONDS) do
			amounts[id] = service.Quote(player, seconds)
		end
	end
	--.. coin quotes for the reel's coin tiles; zero-quote tiles are omitted so
	--.. an empty vault never renders a "+0 Coins" card
	local coinAmounts = {}
	local okV, vaultSkips = pcall(getVaultTimeSkipService)
	if okV and vaultSkips then
		for id, seconds in pairs(COIN_REWARD_SECONDS) do
			local q = vaultSkips.Quote(player, seconds)
			if q and q >= 1 then coinAmounts[id] = q end
		end
	end
	local locked = player:GetAttribute("PendingMinigameRewardAmount")
	if CUCUMBER_REWARD_SECONDS[pending] and type(locked) == "number" then
		amounts[pending] = locked
	end
	if COIN_REWARD_SECONDS[pending] and type(locked) == "number" then
		coinAmounts[pending] = locked
	end
	return { id = pending, cucumberAmounts = amounts, coinAmounts = coinAmounts }
end

local function watchCompletionTokens(player)
	player:GetAttributeChangedSignal("MinigameCompletionToken"):Connect(function()
		local token = player:GetAttribute("MinigameCompletionToken")
		if type(token) == "string" and token ~= "" then
			secureReward(player, token)
		end
	end)
end

Players.PlayerAdded:Connect(watchCompletionTokens)
for _, player in ipairs(Players:GetPlayers()) do watchCompletionTokens(player) end

chooseReward.OnServerInvoke = function(player, token)
	local pending = secureReward(player, token)
	return rewardPayload(player, pending)
end

finished.OnServerEvent:Connect(function(player, token)
	if type(token) ~= "string" or #token > 100 then return end
	if player:GetAttribute("MinigameCompletionToken") ~= token then return end
	local pending = player:GetAttribute("PendingMinigameReward")
	if type(pending) ~= "string" or player:GetAttribute("MinigameRewardSecuredToken") ~= token then return end
	local securedCucumberAmount = player:GetAttribute("PendingMinigameRewardAmount")

	-- Clear the secured state before granting so duplicate Finished packets can never
	-- duplicate a reward. This event is sent only after the spinner has fully returned.
	player:SetAttribute("PendingMinigameReward", nil)
	player:SetAttribute("PendingMinigameRewardAmount", nil)
	player:SetAttribute("MinigameRewardSecuredToken", nil)
	player:SetAttribute("MinigameCompletionToken", nil)
	player:SetAttribute("LastMinigameReward", pending)
	grantReward(player, pending, securedCucumberAmount)
	player:SetAttribute("MinigameCompletionFinished", token)
end)

Players.PlayerRemoving:Connect(function(player)
	player:SetAttribute("MinigameCompletionFinished", nil)
	player:SetAttribute("MinigameCompletionToken", nil)
	player:SetAttribute("PendingMinigameReward", nil)
	player:SetAttribute("PendingMinigameRewardAmount", nil)
	player:SetAttribute("MinigameRewardSecuredToken", nil)
end)

print("[MinigameCompletionService] Server-authoritative reward pool + real grants ready.")
