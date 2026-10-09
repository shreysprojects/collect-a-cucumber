--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")

--..Variables..--
local Doors = workspace.Doors
local Locations = Doors:FindFirstChild("Locations")

local TeleportService = {}

--..Functions..--

function TeleportService.Teleport(Player, Name)
    if Player and Name then
        local UserData = ProfileService.GetUserData(Player)
        if UserData then
            local DoorData = UserData.DoorData
            if DoorData then
                if string.find(DoorData, Name) then
                    local Character = Player.Character
                    local Location = Locations:FindFirstChild(Name)
                    if Character and Character.PrimaryPart and Location then
                        -- With workspace streaming enabled, request the destination
                        -- before moving so doors/terrain do not pop in under the player.
                        pcall(function()
                            Player:RequestStreamAroundAsync(Location.Position, 3)
                        end)
                        Character:PivotTo(Location.CFrame + Vector3.new(0, 1, 0))
                        Network:FireClient(Player, "AlignCamera", Location.CFrame.LookVector)
                    end
                end
            end
        end
    end
end

return TeleportService
