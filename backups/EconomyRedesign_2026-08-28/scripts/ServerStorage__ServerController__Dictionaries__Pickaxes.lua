--..Services..--
--.. Pickaxes replaced the pickaxe line (Aug 2026). The first 17 tiers keep the exact
--.. prices/damage/range the pickaxes shipped with; BloodMoon and Rainbow are the two
--.. new top tiers added for the extra pack models.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--


--..Variables..--
local ClientAssets = ReplicatedStorage:FindFirstChild("Assets")
local Animations = ClientAssets:FindFirstChild("Animations")
local Assets = ServerStorage:FindFirstChild("Assets")
local Tools = Assets:FindFirstChild("Pickaxes")

--..Functions..--

local EquipFunctions = {
    ["Single"] = function(Tool, Character)
        if not (Tool and Character) then return end

        --.. Assets are real Tool instances now (converted 2026-08-10): the mesh
        --.. lives in Tool.Handle and the hold pose comes from Tool.Grip, so the
        --.. grip is editable per pickaxe with a tool grip editor plugin on the
        --.. Tools in ReplicatedStorage.Assets.Pickaxes. EquipTool welds the
        --.. Handle to the RightHand via the standard RightGrip weld.
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        if not Humanoid or Humanoid.Health <= 0 then return end

        Humanoid:EquipTool(Tool)
    end,
};

return {

    ["Stats"] = {
        ["Wood Pickaxe"] = {

            ["Stats"] = {
                Price = 0;
                Damage = 4;
                Range = 6;
            };

            Order = 0;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Stone Pickaxe"] = {

            ["Stats"] = {
                Price = 500;
                Damage = 5;
                Range = 7;
            };

            Order = 1;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Bronze Pickaxe"] = {

            ["Stats"] = {
                Price = 2000;
                Damage = 8;
                Range = 8;
            };

            Order = 2;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Iron Pickaxe"] = {

            ["Stats"] = {
                Price = 6000;
                Damage = 11;
                Range = 9;
            };

            Order = 3;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Steel Pickaxe"] = {

            ["Stats"] = {
                Price = 15000;
                Damage = 16;
                Range = 10;
            };

            Order = 4;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Gold Pickaxe"] = {

            ["Stats"] = {
                Price = 40000;
                Damage = 23;
                Range = 11;
            };

            Order = 5;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Emerald Pickaxe"] = {

            ["Stats"] = {
                Price = 100000;
                Damage = 32;
                Range = 12;
            };

            Order = 6;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Ruby Pickaxe"] = {

            ["Stats"] = {
                Price = 250000;
                Damage = 46;
                Range = 13;
            };

            Order = 7;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Amethyst Pickaxe"] = {

            ["Stats"] = {
                Price = 600000;
                Damage = 66;
                Range = 14;
            };

            Order = 8;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Diamond Pickaxe"] = {

            ["Stats"] = {
                Price = 1500000;
                Damage = 93;
                Range = 15;
            };

            Order = 9;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Valentine Pickaxe"] = {

            ["Stats"] = {
                Price = 4000000;
                Damage = 133;
                Range = 16;
            };

            Order = 10;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Magma Pickaxe"] = {

            ["Stats"] = {
                Price = 10000000;
                Damage = 189;
                Range = 17;
            };

            Order = 11;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["VoidNeon Pickaxe"] = {

            ["Stats"] = {
                Price = 25000000;
                Damage = 268;
                Range = 18;
            };

            Order = 12;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["CosmicIce Pickaxe"] = {

            ["Stats"] = {
                Price = 60000000;
                Damage = 381;
                Range = 19;
            };

            Order = 13;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["YinYang Pickaxe"] = {

            ["Stats"] = {
                Price = 150000000;
                Damage = 542;
                Range = 20;
            };

            Order = 14;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Galaxy Pickaxe"] = {

            ["Stats"] = {
                Price = 400000000;
                Damage = 769;
                Range = 21;
            };

            Order = 15;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["SolarFlare Pickaxe"] = {

            ["Stats"] = {
                Price = 1000000000;
                Damage = 1093;
                Range = 22;
            };

            Order = 16;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["BloodMoon Pickaxe"] = {

            ["Stats"] = {
                Price = 2500000000;
                Damage = 1550;
                Range = 23;
            };

            Order = 17;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Rainbow Pickaxe"] = {

            ["Stats"] = {
                Price = 6000000000;
                Damage = 2200;
                Range = 24;
            };

            Order = 18;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
    };
}
