--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)

local ProfileService = ServerController.GetModule("ProfileService")

--..Variables..--
local FavoritePromptService = {}

--..Functions..--

function FavoritePromptService.PlayerJoined(Player)
	--.. the native "favourite this game?" prompt should only ever show on a player's
	--.. FIRST session. we grant a one-time attribute here; the client (FavoritePromptClient)
	--.. reads it before firing AvatarEditorService:PromptSetFavorite. returning players
	--.. (SeenFavoritePrompt already true) never get the attribute, so are never prompted.
	local profile
	for _ = 1, 30 do
		profile = ProfileService.GetUserData(Player)
		if profile then break end
		task.wait(1)
	end
	if not profile then return end

	if profile.SeenFavoritePrompt ~= true then
		profile.SeenFavoritePrompt = true -- consumed: this is their first session
		Player:SetAttribute("FavoritePromptAllowed", true)
	end
end

function FavoritePromptService.Initialize()
end

return FavoritePromptService
