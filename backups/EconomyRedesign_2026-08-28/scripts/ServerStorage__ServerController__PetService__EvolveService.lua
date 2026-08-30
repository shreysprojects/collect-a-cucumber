--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
--..
local PetStats = ServerController.GetDictionary("Pets").Stats
--..
local ProfileService = ServerController.GetModule("ProfileService")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local Network = ControllerLoader.GetController("Network")
local EquipService = require(script.Parent.EquipService)
local PetDefaults = require(script.Parent.PetDefaults)

--..Variables..--


local EvolveService = {}

--..Functions..--

local function Error()
    warn("[Evolving]: Error Occured When Eolving Pets")
end

function EvolveService.EvolvePet(Player, SelectedPet, SelectedIds)
    do
        if CurrencyHandler.CheckIfEnough({Player = Player; Currency = "Coins"; Amount = 600_000}) then
            CurrencyHandler.RemoveCurrency(Player, "Coins", 600_000)

            local UserData = ProfileService.GetUserData(Player)
            if UserData then
                local PetData = UserData.PetData
                if PetData then
                    if #SelectedIds ~= 3 then Error(); Network:FireClient(Player, "Notif", {Message = "EVOLVE FAILED!"; Type = "Error";}); return false end

                    for _, PetId in next, SelectedIds do
                        if PetData[PetId] == nil then
                            Error(); Network:FireClient(Player, "Notif", {Message = "EVOLVE FAILED!"; Type = "Error";}); return false
                        else
                            local PetTable = PetData[PetId]
                            if PetTable.Equipped then
                                EquipService.EquipPet({Player = Player; PetId = PetId})
                            end
                        end
                    end

                    RunService.Heartbeat:Wait()

                    EvolveService.DeletePets(Player, SelectedIds)

                    --..
                    local PlayerData = Player:WaitForChild("PlayerData")
                    local PetsFolder = PlayerData:WaitForChild("Pets")
                    local Inventory = PetsFolder:WaitForChild("Inventory")

                    local Id, Table = PetDefaults.SetGoldenDefaults({Name = SelectedPet; Stats = PetStats[SelectedPet];});

                    local UserData = ProfileService.GetUserData(Player);
                    if UserData then
                        local PetData = UserData.PetData
                        PetData[Id] = Table;

                        ProfileService.SetStatToProfile(Player, "PetData", nil, PetData)
                        Inventory.Value += 1

                        wait()

                        Network:FireClient(Player, "AddPet", {Id = Id; Table = Table})
                        Network:FireClient(Player, 'PlaySound', 'Pet Crafting')
                        Network:FireClient(Player, "Notif", {Message = "PETS EVOLVED!"; Type = "Success";})

                        return true
                    else Error();
                    end
                end
            end
        else
            Network:FireClient(Player, "Notif", {Message = "EVOLVE FAILED!"; Type = "Error";})
        end
    end
end

function EvolveService.DeletePets(Player, Ids)
    do
        if Player and Ids then
            local PlayerData = Player:WaitForChild("PlayerData")
            local PetsFolder = PlayerData:WaitForChild("Pets")
            local Inventory = PetsFolder:WaitForChild("Inventory")

            local UserData = ProfileService.GetUserData(Player)
            if UserData then
                local PetData = UserData.PetData
                if PetData then
                    for _,Id in next, Ids do
                        local PetTable = PetData[Id]
                        if PetTable then
                            wait()
                            PetData[Id] = nil
                            Inventory.Value -= 1
                        end
                    end
                    wait()
                    Network:FireClient(Player, "RemovePet", Ids)
                    ProfileService.SetStatToProfile(Player, "PetData", nil, PetData)
                    return true
                end
            end
        end
    end
end

return EvolveService
