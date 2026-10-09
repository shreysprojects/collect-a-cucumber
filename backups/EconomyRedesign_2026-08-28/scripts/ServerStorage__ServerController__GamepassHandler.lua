--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)

local ProductController = ControllerLoader.GetController("ProductController")

--..Variables..--


local GamepassHandler = {}

--..Functions..--

function GamepassHandler.CommitGamepass(InfoTable)
    local Player = InfoTable.Player
    local Character = Player.Character

    if Player then
        if ProductController.CheckGamepass(Player, InfoTable.Name) then
            if ProductController.Gamepasses[InfoTable.Name].Function ~= nil then
                ProductController.Gamepasses[InfoTable.Name].Function(Player)
            end
        end
    end
end

function GamepassHandler.CharacterJoined(Character)
    coroutine.wrap(function()
        local Player = Players:GetPlayerFromCharacter(Character)
        GamepassHandler.CommitGamepass({Player = Player; Name = "Sprint";})
        GamepassHandler.CommitGamepass({Player = Player; Name = "Jetpack";})
        GamepassHandler.CommitGamepass({Player = Player; Name = "Autofarm";})
    end)()
end

function GamepassHandler.PlayerJoined(Player)
    coroutine.wrap(function()
        --GamepassHandler.CommitGamepass({Player = Player; Name = "Throw Faster";})
    end)()
end

return GamepassHandler
