--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
--..
local ProfileService = ServerController.GetModule("ProfileService")
local NumberController = ControllerLoader.GetController("NumberController")

--..Variables..--


local PetDefaults = {}

--..Functions..--

local function Error()
    warn("[PetDefaults]: Error Occured When Creating Defaults")
end

function PetDefaults.SetDefaults(InfoTable)
    do
        if InfoTable then
            local Name = InfoTable.Name
            local Stats = InfoTable.Stats

            if Name and Stats then
                local Id = HttpService:GenerateGUID(true)
                if Id then
                    local PetTable = {};
                    PetTable = {};

                    PetTable.Name = Name;--Stats.Name;
                    PetTable.Craft = "Normal";
                    PetTable.Rarity = Stats.Rarity;
                    PetTable.Equipped = false;

                    PetTable.Stats = {};
                    PetTable.Stats.Multi1 = Stats.Stats.Multi1;
                    PetTable.Stats.Multi2 = Stats.Stats.Multi2;
                    PetTable.Stats.Damage = Stats.Stats.Damage or 1;

                    PetTable.Levels = {};
                    PetTable.Levels.Level = 0;
                    PetTable.Levels.XP = 0;
                    PetTable.Levels.RequiredXP = 50;

                    return Id, PetTable
                else
                    Error()
                end
            else
                Error()
            end
        end
    end
end

function PetDefaults.SetGoldenDefaults(InfoTable)
    do
        if InfoTable then
            local Name = InfoTable.Name
            local Stats = InfoTable.Stats

            if Name and Stats then
                local Id = HttpService:GenerateGUID(true)
                if Id then
                    local PetTable = {};
                    PetTable = {};

                    PetTable.Name = Name;
                    PetTable.Craft = "Golden";
                    PetTable.Rarity = Stats.Rarity;
                    PetTable.Equipped = false;

                    PetTable.Stats = {};
                    PetTable.Stats.Multi1 = NumberController.RoundNumber(Stats.Stats.Multi1 * 1.5);
                    PetTable.Stats.Multi2 = NumberController.RoundNumber(Stats.Stats.Multi2 * 1.5);
                    PetTable.Stats.Damage = math.floor((Stats.Stats.Damage or 1) * 1.5 + 0.5);

                    PetTable.Levels = {};
                    PetTable.Levels.Level = 0;
                    PetTable.Levels.XP = 0;
                    PetTable.Levels.RequiredXP = 150;

                    return Id, PetTable
                else
                    Error()
                end
            else
                Error()
            end
        end
    end
end

return PetDefaults
