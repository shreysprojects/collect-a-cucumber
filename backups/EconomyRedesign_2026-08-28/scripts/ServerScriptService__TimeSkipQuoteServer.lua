local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerController = require(ServerStorage.ServerController)
local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
local VaultTimeSkipService = ServerController.GetModule("VaultTimeSkipService")
local remote = ReplicatedStorage:WaitForChild("GetTimeSkipQuote")
local vaultRemote = ReplicatedStorage:WaitForChild("GetVaultTimeSkipQuote")

remote.OnServerInvoke = function(player, seconds)
	seconds = math.clamp(tonumber(seconds) or 0, 0, 604800)
	return TimeSkipRateService.Quote(player, seconds)
end

--.. second skip mechanic: coins the player's stored vault cucumbers print
vaultRemote.OnServerInvoke = function(player, seconds)
	seconds = math.clamp(tonumber(seconds) or 0, 0, 604800)
	return VaultTimeSkipService.Quote(player, seconds)
end
