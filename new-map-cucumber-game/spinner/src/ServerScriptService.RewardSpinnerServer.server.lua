--[[
	RewardSpinnerServer  (Script, ServerScriptService)  2026-09-23
	Starts ServerStorage.RewardSpinnerService and hooks it to the portals: PortalService.ReturnHome(player,
	"Finished") is the one place every completed minigame passes through (obby chest, Avalanche / Lava Run /
	Bloxout completion pads, the Wild West hunt), so the function is WRAPPED here (same module table as
	PortalLoader's require; PortalService calls it through its own table, so the wrapper sees every call) and a
	"Finished" return home awards one spin. No edit to PortalService itself.
]]
local ServerStorage = game:GetService("ServerStorage")

local RewardSpinnerService = require(ServerStorage:WaitForChild("RewardSpinnerService"))
RewardSpinnerService.Start()

local ok, PortalService = pcall(function() return require(ServerStorage:WaitForChild("PortalService", 30)) end)
if ok and type(PortalService) == "table" and type(PortalService.ReturnHome) == "function" then
	local original = PortalService.ReturnHome
	PortalService.ReturnHome = function(player, reason, ...)
		local title = player and player:GetAttribute("MinigameName") -- clearSession wipes it inside ReturnHome
		local result = original(player, reason, ...)
		if result and reason == "Finished" then
			task.spawn(function()
				local okAward, err = pcall(RewardSpinnerService.Award, player, "Portal:" .. tostring(title or "?"))
				if not okAward then warn("[RewardSpinnerServer] award failed: " .. tostring(err)) end
			end)
		end
		return result
	end
	print("[RewardSpinnerServer] PortalService.ReturnHome wrapped: a finished minigame awards a spin")
else
	warn("[RewardSpinnerServer] PortalService not found - spins only through the dev hook: " .. tostring(PortalService))
end
