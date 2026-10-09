--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
--..
local ProfileService = ServerController.GetModule("ProfileService")
local FastWait = ControllerLoader.GetController("FastWait")
local Network = ControllerLoader.GetController("Network")
local ProductController = ControllerLoader.GetController("ProductController")
local NumberController = ControllerLoader.GetController("NumberController")
local PetController = FrameworkLoader.GetModule("PetController")
--..
local PetStats = ServerController.GetDictionary("Pets").Stats
--..
local PetDefaults = require(script.PetDefaults)
local EquipService = require(script.EquipService)
local EggService = require(script.EggService)
local EvolveServive = require(script.EvolveService)

--..Variables..--


local PetService = {}

--..Functions..--

function PetService.GetPetStats(Player, PetId)
    do
        if Player and PetId then
            local UserData = ProfileService.GetUserData(Player);
            if UserData then
                local PetData = UserData.PetData
                if PetData then
                    local PetTable = PetData[PetId]
                    if PetTable then
                        return PetTable
                    end
                end
            end
        end
    end
end

function PetService.EquipPet(Player, Id)
    do
        if Player and Id then
            return EquipService.EquipPet({Player = Player; PetId = Id})
        end
    end
end

function PetService.EvolvePet(...)
    do
        if ... then
            return EvolveServive.EvolvePet(...)
        end
    end
end

--.. PetService.LockPet and PetService.DeletePet were REMOVED 2026-08-04.
--.. Both features had long since been taken out of the pet inventory UI (only a dead
--.. backup module still called them, and that backup was deleted 2026-08-05), and
--.. DeletePet carried a live data-loss bug while being reachable from any client:
--.. it returned mid-batch on a locked pet AFTER earlier pets were already niled and
--.. Inventory decremented, and it had no type(pet)=="table" guard, so passing the id
--.. "Unlocked" wiped the Pet Index discovery string. Because ProfileService.GetUserData
--.. hands back the LIVE profile.Data table, those partial deletions were permanent.
--.. Pet removal now happens only in two audited places: EvolveService.DeletePets
--.. (evolve consumption) and SellVendorServer's SellPets handler (vendor selling).

function PetService.UnequipAll(Player, PetIds)
    do
        if Player and type(PetIds) == "table" then
            for _,Id in next, PetIds do
                EquipService.EquipPet({Player = Player; PetId = Id})
            end
            return true
        end
    end
end

function PetService.EquipBest(Player, PetIds)
    do
        if Player and type(PetIds) == "table" then
            local EquippedPetIds = {};

            for _,Id in next, PetIds do
                local Result = EquipService.EquipPet({Player = Player; PetId = Id.Id}, true)

                if Result == false then
                    return true, EquippedPetIds
                else
                    table.insert(EquippedPetIds, Id.Id)
                end
            end
            return true, EquippedPetIds
        end
    end
end

function PetService.OpenEgg(...)
    do
        return EggService.CheckEgg(...)
    end
end

--.. Discovery: the Pet Index reads PlayerData.Pets.Unlocked ("|"-delimited names).
--.. Historically ONLY egg hatches wrote it, so pets from boss forging, the reward
--.. spinner, trades, promos etc. never showed as discovered. Every grant path now
--.. funnels through here (plus a PlayerJoined sweep for pets owned before this fix).
function PetService.MarkDiscovered(Player, PetNames)
    if type(PetNames) == "string" then PetNames = {PetNames} end
    if not (Player and PetNames and #PetNames > 0) then return end

    local PlayerData = Player:FindFirstChild("PlayerData")
    local PetsFolder = PlayerData and PlayerData:FindFirstChild("Pets")
    local Unlocked = PetsFolder and PetsFolder:FindFirstChild("Unlocked")
    if not Unlocked then return end

    local Set = {}
    for _, Name in ipairs(string.split(Unlocked.Value, "|")) do
        Set[Name] = true
    end

    local Added = false
    for _, Name in ipairs(PetNames) do
        if Name ~= "" and not Set[Name] then
            Set[Name] = true
            Unlocked.Value = (Unlocked.Value ~= "" and Unlocked.Value .. "|" or "") .. Name
            Added = true
        end
    end

    if Added then
        ProfileService.SetStatToProfile(Player, "Unlocked", "PetData", Unlocked.Value)
    end
end

function PetService.AddPetToPlayer(InfoTable)
    do
        if InfoTable then
            local Player = InfoTable.Player
            local PetName = InfoTable.Pet

            if Player and PetName then
                local PlayerData = Player:WaitForChild("PlayerData")
                local PetsFolder = PlayerData:WaitForChild("Pets")
                local Inventory = PetsFolder:WaitForChild("Inventory")

                local Id, Table = PetDefaults.SetDefaults({Name = PetName; Stats = PetStats[PetName];});

                local UserData = ProfileService.GetUserData(Player);
                if UserData then
                    local PetData = UserData.PetData
                    PetData[Id] = Table;

                    ProfileService.SetStatToProfile(Player, "PetData", nil, PetData)
                    Inventory.Value += 1

                    wait()

                    Network:FireClient(Player, "AddPet", {Id = Id; Table = Table})

                    PetService.MarkDiscovered(Player, PetName)

                    return Id
                else
                    warn("UserData is nil")
                end
            end
        end
    end
end

--.. Defaults

function PetService.PlayerJoined(Player)
    FastWait(3)

    local PlayerData = Player:WaitForChild("PlayerData")
    local PetsFolder = PlayerData:WaitForChild("Pets")
    local Inventory = PetsFolder:WaitForChild("Inventory")

    do
        if ProductController.CheckGamepass(Player, "+75 Pet Storage", false) then
            ProductController.Gamepasses["+75 Pet Storage"].Function(Player)
        end

        -- Rebuild the total once so board levels and owned slot passes stack
        -- regardless of which one loaded or was purchased first.
        local Upgrades = ServerController.GetDictionary("Upgrades")
        if Upgrades and Upgrades.SetPetEquips then
            Upgrades.SetPetEquips(Player)
        end
    end

    local UserData = ProfileService.GetUserData(Player);
    if UserData then
        local PetData = UserData.PetData
        if PetData then
            --.. PetDefaults COPIES a pet's stats into the save when it is granted, so a pet
            --.. someone already owns keeps whatever the dictionary said back then — retuning
            --.. a pet only ever reached new drops. Re-sync every owned pet from the live
            --.. dictionary here, before the equip pass below rebuilds the player's totals.
            --.. Golden pets keep their 1.5x, rounded exactly as SetGoldenDefaults does.
            local Resynced = 0
            for Id, Table in next, PetData do
                if Id ~= "Unlocked" and type(Table) == "table" and Table.Stats then
                    local Defaults = PetStats[Table.Name]

                    if Defaults and Defaults.Stats then
                        local Multi1 = Defaults.Stats.Multi1
                        local Multi2 = Defaults.Stats.Multi2
                        local Damage = Defaults.Stats.Damage or 1

                        if Table.Craft == "Golden" then
                            Multi1 = NumberController.RoundNumber(Multi1 * 1.5)
                            Multi2 = NumberController.RoundNumber(Multi2 * 1.5)
                            Damage = math.floor(Damage * 1.5 + 0.5)
                        end

                        if Table.Stats.Multi1 ~= Multi1 or Table.Stats.Multi2 ~= Multi2 or Table.Stats.Damage ~= Damage then
                            Table.Stats.Multi1 = Multi1
                            Table.Stats.Multi2 = Multi2
                            Table.Stats.Damage = Damage

                            Resynced += 1
                        end
                    end
                end
            end

            if Resynced > 0 then
                ProfileService.SetStatToProfile(Player, "PetData", nil, PetData)
                print(("[PetService] re-synced %d pet(s) to current stats for %s"):format(Resynced, Player.Name))
            end

            --.. catch-up sweep: anything already owned counts as discovered (pets
            --.. from boss forging / spinner / trades predate discovery marking)
            do
                local OwnedNames = {}
                for Id, Table in next, PetData do
                    if Id ~= "Unlocked" and type(Table) == "table" and Table.Name then
                        OwnedNames[#OwnedNames + 1] = Table.Name
                    end
                end
                PetService.MarkDiscovered(Player, OwnedNames)
            end

            for Id, Table in next, PetData do
                if Id ~= "Unlocked" then

                    if Table.Equipped then
                        EquipService.EquipPet({Player = Player; PetId = Id; OnJoin = true})
                    end

                    Network:FireClient(Player, "AddPet", {Id = Id; Table = Table})

                    Inventory.Value += 1

                    wait()
                end
            end

            --PetService.AddPetToPlayer({Player = Player; Pet = "Purple Hydra"})
        end

        -- Lil Pickle is awarded only when the tutorial completion event is validated.
    end

    --.. from here on, CharacterJoined's RestoreEquippedPets owns re-cloning
    --.. equipped pet models after death/respawn (the join pass above owned
    --.. the first spawn; running both on it would duplicate models)
    Player:SetAttribute("EquippedPetsLoaded", true)
    if Player.Character then
        EquipService.RestoreEquippedPets(Player, Player.Character)
    end
end

function PetService.CharacterJoined(Character)
    local Player = Players:GetPlayerFromCharacter(Character)

    --.. Set Up
    local PetFolder = Instance.new("Configuration")
    PetFolder.Name = "Pets"
    PetFolder.Parent = Character

    --.. death/respawn: the equipped pets' models died with the old character
    --.. (pets deal the damage, so a Reset used to silently gut DPS until rejoin)
    if Player then
        task.spawn(EquipService.RestoreEquippedPets, Player, Character)
    end
end

function PetService.Initialize()
    EggService.Initialize()
end

return PetService
