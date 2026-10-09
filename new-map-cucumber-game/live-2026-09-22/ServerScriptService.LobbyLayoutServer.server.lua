--.. LobbyLayoutServer: lays the lobby out from its plots at server start (ServerStorage.LobbyLayout),
--.. then flags Map.Lobby.LayoutReady so PlotService / PlotUpgradeService read the final plot geometry.
local ServerStorage = game:GetService("ServerStorage")
local lobby = workspace:WaitForChild("Map"):WaitForChild("Lobby")
local ok, result = pcall(function()
	return require(ServerStorage:WaitForChild("LobbyLayout")).Apply()
end)
if ok then
	print(("[LobbyLayout] %d plots, row Z %.1f..%.1f, box X %.1f..%.1f Z %.1f..%.1f"):format(result.Plots, result.Row[1], result.Row[2], result.Box.West, result.Box.East, result.Box.North, result.Box.South))
else
	warn("[LobbyLayout] layout failed, lobby left as built: " .. tostring(result))
end
lobby:SetAttribute("LayoutReady", true)
