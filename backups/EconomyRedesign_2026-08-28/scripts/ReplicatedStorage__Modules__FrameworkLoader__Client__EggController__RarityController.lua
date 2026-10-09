--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
--..
local Network = ControllerLoader.GetController("Network")

--..Variables..--
local PetStats = Network:InvokeServer("GetData", "Dictionary", {Name = "Pets"})
--..

local RarityController = {

    Classes = {
        Common = {
            Gradient = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(206,255,198));
        };
        Uncommon = {
            Gradient = ColorSequence.new(Color3.fromRGB(213,255,0), Color3.fromRGB(0,207,145));
        };
        Rare = {
            Gradient = ColorSequence.new(Color3.fromRGB(0,255,255), Color3.fromRGB(0,145,255));
        };
        Epic = {
            Gradient = ColorSequence.new(Color3.fromRGB(249,215,255), Color3.fromRGB(226,0,255));
        };
        Legendary = {
            Gradient = ColorSequence.new(Color3.fromRGB(255,247,0), Color3.fromRGB(255,183,0));
        };
        Mythical = {
            Gradient = ColorSequence.new(Color3.fromRGB(246, 139, 255), Color3.fromRGB(25, 182, 255));
        };
        Omega = {
            Gradient = ColorSequence.new(Color3.fromRGB(255,234,0), Color3.fromRGB(255,0,0));
        };
        Special = {
            Gradient = ColorSequence.new(Color3.fromRGB(255,219,219), Color3.fromRGB(255,0,0));
        };
    };

}

--..Functions..--

function RarityController.GetColors(Pet, Label)
    local SpecificPetStat = PetStats[Pet]

    if Label then
        Label.Text = string.upper(SpecificPetStat.Rarity)
        Label.UIGradient.Color = RarityController.Classes[SpecificPetStat.Rarity].Gradient
    end
end

return RarityController
