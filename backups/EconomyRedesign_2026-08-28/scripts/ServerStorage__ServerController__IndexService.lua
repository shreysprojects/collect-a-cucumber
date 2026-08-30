--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local Network = ControllerLoader.GetController("Network")

--..Config..--
local PETS_PER_MILESTONE = 5
local COINS_PER_MILESTONE = 500 -- COINS x milestone number (name kept for the UI contract)

--..Variables..--
local IndexService = {}

--..Functions..--

local function DiscoveredCount(profile)
	local unlocked = profile.PetData and profile.PetData.Unlocked or ""
	if unlocked == "" then return 0 end
	local n = 0
	for _ in string.gmatch(unlocked, "[^|]+") do n += 1 end
	return n
end

function IndexService.Initialize()
	Network:BindFunctions({
		--.. Per-biome boss shard counts for the Shards UI: {[zone] = count}. 10 of a zone's
		--.. shards forge that boss's pet (spent on forge), so this is the live 0-9 remainder.
		GetBossShards = function(Player)
			local profile = ProfileService.GetUserData(Player)
			if not profile then return {} end
			return profile.BossShards or {}
		end,

		--.. FORGE button in the Shards menu: spend 10 of a biome's shards to forge its boss pet.
		ForgeBossPet = function(Player, zone)
			local Breakables = ServerController.GetModule("BreakablesService")
			if not Breakables or not Breakables.ForgeBossPet then return false end
			return Breakables.ForgeBossPet(Player, zone)
		end,

		GetIndexProgress = function(Player)
			local profile = ProfileService.GetUserData(Player)
			if not profile then return nil end
			local discovered = DiscoveredCount(profile)
			local claimed = profile.IndexClaimed or 0
			return {
				Discovered = discovered;
				Claimed = claimed;
				Claimable = math.floor(discovered / PETS_PER_MILESTONE) - claimed;
				PerMilestone = PETS_PER_MILESTONE;
				NextReward = COINS_PER_MILESTONE * (claimed + 1);
			}
		end,

		ClaimIndexReward = function(Player)
			local profile = ProfileService.GetUserData(Player)
			if not profile then return 0 end
			local discovered = DiscoveredCount(profile)
			local claimed = profile.IndexClaimed or 0
			if math.floor(discovered / PETS_PER_MILESTONE) <= claimed then return 0 end

			profile.IndexClaimed = claimed + 1
			local reward = COINS_PER_MILESTONE * profile.IndexClaimed
			local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
			CurrencyHandler.AddCurrency({Player = Player; Currency = "Coins"; Amount = reward; WasPurchase = true; HasTotal = true;})
			Network:FireClient(Player, "Notif", {Message = ("\u{1F4D6} INDEX MILESTONE %d! +%d COINS"):format(profile.IndexClaimed, reward); Type = "Success";})
			return reward
		end,
	})
end

return IndexService
