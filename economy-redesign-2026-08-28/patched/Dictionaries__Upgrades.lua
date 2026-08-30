--..Services..--
--.. (coins economy July 2026: upgrades priced in Coins, x4)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Variables..--
local MAX_PET_EQUIPS = 7

local function setWalkSpeed(Player)
    if not Player then return end

    local Character = Player.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    if Humanoid then
        local Speed = 29
        --.. Sprint gamepass DOUBLES the final walkspeed.
        local ok, ProductController = pcall(function()
            return require(ReplicatedStorage.Modules.ControllerLoader).GetController("ProductController")
        end)
        if ok and ProductController and ProductController.CheckGamepass(Player, "Sprint")
            and Player:GetAttribute("SprintEnabled") ~= false then
            Speed *= 2
        end
        --.. Hoverboard TRIPLES the final speed while it is equipped. The flag is
        --.. owned by HoverboardService; keeping the multiplier here means every
        --.. later recompute (an upgrade purchase, the Sprint pass) preserves it.
        if Player:GetAttribute("Hoverboarding") then
            Speed *= 3
        end
        --.. The goal-driven SUPER STRENGTH event doubles the final stacked speed.
        if Player:GetAttribute("SuperStrengthActive") then
            Speed *= 2
        end
        --.. carrying STOLEN vault goods is heavy (2026-08-27): 1.5x slower
        --.. until the heist resolves (VaultService owns CarryingStolen)
        if Player:GetAttribute("CarryingStolen") then
            Speed /= 1.5
        end
        --.. (the carry 2x speed bonus was removed 2026-08-27, user call --
        --.. CarryService still re-triggers this recompute at carry start/end,
        --.. which is now a harmless no-op speed-wise)
        Humanoid.WalkSpeed = Speed
    end
end

local function setPetEquips(Player)
    if not Player then return end

    local PlayerData = Player:FindFirstChild("PlayerData")
    local PetsFolder = PlayerData and PlayerData:FindFirstChild("Pets")
    local MaxEquipped = PetsFolder and PetsFolder:FindFirstChild("MaxEquipped")
    local Upgrades = PlayerData and PlayerData:FindFirstChild("Upgrades")
    local UpgradeValue = Upgrades and Upgrades:FindFirstChild("Pet equips")
    if not MaxEquipped then return end

    local BoardLevel = math.clamp(UpgradeValue and UpgradeValue.Value or 0, 0, MAX_PET_EQUIPS - 4)
    local LegacyIncrement = 0
    local okServer, ServerController = pcall(require, ServerStorage.ServerController)
    if okServer and ServerController then
        local Profiles = ServerController.GetModule("ProfileService")
        local UserData = Profiles and Profiles.GetUserData(Player)
        LegacyIncrement = UserData and tonumber(UserData.MaxEquipIncrement) or 0
    end

    local PassBonus = 0
    local okProducts, ProductController = pcall(function()
        return require(ReplicatedStorage.Modules.ControllerLoader).GetController("ProductController")
    end)
    if okProducts and ProductController then
        for PassName, Bonus in pairs({["+4 Pet Slots"] = 4;}) do
            local Pass = ProductController.Gamepasses[PassName]
            if Pass and ProductController.CheckGamepass(Player, PassName, false) then
                PassBonus += Bonus
            end
        end
    end

    -- Board cap applies only to the board's base progression. Permanent passes
    -- and legacy purchases stack above it instead of being swallowed by the cap.
    MaxEquipped.Value = 4 + BoardLevel + LegacyIncrement + PassBonus
end

return {
    ["SetWalkSpeed"] = setWalkSpeed; --.. exported so the Sprint gamepass can re-apply the buff on purchase
    ["SetPetEquips"] = setPetEquips; --.. recomputes board + products + gamepasses as one stacked total
    ["Stats"] = {
        ["Vault slots"] = {
            ["Name"] = "VAULT SLOTS";

            ["Stats"] = {
                Description = "+1 Vault Slot";
                Price = 500000;
                Increment = 2;
                MaxUpgrade = 3;
            };

            ["Order"] = 1;
            ["Icon"] = "rbxassetid://6950737906";

            Function = function(Player, Increment)
                --.. VaultService watches the replicated "Vault slots" IntValue and
                --.. relayouts the owner's stall itself; nothing to do here.
            end,
        };

        ["Pet equips"] = {
            ["Name"] = "PET EQUIPS";

            ["Stats"] = {
                Description = "+1 Pet Equip";
                Price = 25000;
                Increment = 2;
                MaxUpgrade = 3;
            };

            ["Order"] = 2;
            ["Icon"] = "rbxassetid://6950738651";

            Function = function(Player, Increment)
                setPetEquips(Player)
            end,
        };

        ["Smashes required"] = {
            ["Name"] = "-3 SMASHES REQUIRED FOR PORTALS";

            ["Stats"] = {
                Description = "-3 Cucumbers for Portals";
                Price = 50000;
                Increment = 3;
                MaxUpgrade = 3;
            };

            ["Order"] = 3;
            ["Icon"] = "rbxassetid://6950737906";

            Function = function(Player, Increment)
                --.. PortalCucumberProgress.Remaining reads the replicated
                --.. "Smashes required" IntValue live and subtracts 3 per level on
                --.. every call (portals only). Nothing to push from here.
            end,
        };
    };
}
