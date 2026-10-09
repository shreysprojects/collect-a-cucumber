--..Services..--
--.. (2026-08-28 ECONOMY REDESIGN: damage x2.75/step, price ~x3.4-5/step — 5 dmg/400c to 147M dmg/5Qa.)
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
                Damage = 3;
                Range = 6;
            };

            Order = 0;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Stone Pickaxe"] = {

            ["Stats"] = {
                Price = 400;
                Damage = 5;
                Range = 7;
            };

            Order = 1;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Bronze Pickaxe"] = {

            ["Stats"] = {
                Price = 6000;
                Damage = 14;
                Range = 8;
            };

            Order = 2;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Iron Pickaxe"] = {

            ["Stats"] = {
                Price = 60000;
                Damage = 38;
                Range = 9;
            };

            Order = 3;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Steel Pickaxe"] = {

            ["Stats"] = {
                Price = 500000;
                Damage = 105;
                Range = 10;
            };

            Order = 4;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Gold Pickaxe"] = {

            ["Stats"] = {
                Price = 2500000;
                Damage = 290;
                Range = 11;
            };

            Order = 5;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Emerald Pickaxe"] = {

            ["Stats"] = {
                Price = 10000000;
                Damage = 800;
                Range = 12;
            };

            Order = 6;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Ruby Pickaxe"] = {

            ["Stats"] = {
                Price = 60000000;
                Damage = 2200;
                Range = 13;
            };

            Order = 7;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Amethyst Pickaxe"] = {

            ["Stats"] = {
                Price = 300000000;
                Damage = 6000;
                Range = 14;
            };

            Order = 8;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Diamond Pickaxe"] = {

            ["Stats"] = {
                Price = 2000000000;
                Damage = 16500;
                Range = 15;
            };

            Order = 9;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Valentine Pickaxe"] = {

            ["Stats"] = {
                Price = 10000000000;
                Damage = 45000;
                Range = 16;
            };

            Order = 10;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Magma Pickaxe"] = {

            ["Stats"] = {
                Price = 60000000000;
                Damage = 124000;
                Range = 17;
            };

            Order = 11;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["VoidNeon Pickaxe"] = {

            ["Stats"] = {
                Price = 250000000000;
                Damage = 340000;
                Range = 18;
            };

            Order = 12;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["CosmicIce Pickaxe"] = {

            ["Stats"] = {
                Price = 1000000000000;
                Damage = 935000;
                Range = 19;
            };

            Order = 13;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["YinYang Pickaxe"] = {

            ["Stats"] = {
                Price = 6000000000000;
                Damage = 2600000;
                Range = 20;
            };

            Order = 14;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Galaxy Pickaxe"] = {

            ["Stats"] = {
                Price = 40000000000000;
                Damage = 7000000;
                Range = 21;
            };

            Order = 15;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["SolarFlare Pickaxe"] = {

            ["Stats"] = {
                Price = 200000000000000;
                Damage = 19500000;
                Range = 22;
            };

            Order = 16;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["BloodMoon Pickaxe"] = {

            ["Stats"] = {
                Price = 1000000000000000;
                Damage = 53500000;
                Range = 23;
            };

            Order = 17;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
        ["Rainbow Pickaxe"] = {

            ["Stats"] = {
                Price = 5000000000000000;
                Damage = 147000000;
                Range = 24;
            };

            Order = 18;

            Animation = Animations:FindFirstChild("Idle");

            EquipFunction = function(...) EquipFunctions.Single(...) end,
        };
    };
}
