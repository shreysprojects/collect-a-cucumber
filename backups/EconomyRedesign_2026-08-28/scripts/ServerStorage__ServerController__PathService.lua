--[[
	PathService - first-session "choose your path" starter pet.
	Client asks GetPathState; if unchosen it shows the picker and calls
	ChoosePath once. Exactly one grant per profile, auto-equipped.
]]
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
local PATHS = {
	Smasher = "Smasher Sprout";
	Farmer = "Farmer Sprout";
	Banker = "Banker Sprout";
}

local PathService = {}
local Busy = {}

function PathService.Initialize()
	Network:BindFunctions({
		GetPathState = function(Player)
			local profile = ProfileService.GetUserData(Player)
			return profile and profile.ChosenPath == true
		end,

		ChoosePath = function(Player, pathKey)
			if type(pathKey) ~= "string" or not PATHS[pathKey] then return false end
			if Busy[Player] then return false end
			Busy[Player] = true

			local ok, result = pcall(function()
				local profile = ProfileService.GetUserData(Player)
				if not profile or profile.ChosenPath == true then return false end
				profile.ChosenPath = true

				local PetService = ServerController.GetModule("PetService")
				local EquipService = require(ServerStorage.ServerController.PetService.EquipService)
				local id = PetService.AddPetToPlayer({Player = Player; Pet = PATHS[pathKey]})
				if id then
					task.wait(0.5)
					EquipService.EquipPet({Player = Player; PetId = id; OnJoin = true})
				end
				Network:FireClient(Player, "Notif", {Message = ("\u{2728} %s JOINS YOUR TEAM!"):format(string.upper(PATHS[pathKey])); Type = "Success";})
				return true
			end)

			Busy[Player] = nil
			return ok and result or false
		end,
	})

	Players.PlayerRemoving:Connect(function(Player)
		Busy[Player] = nil
	end)
end

return PathService
