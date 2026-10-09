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
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")

--..Variables..--


local ArmorHandler = {

}

--..Functions..--
function ArmorHandler.RemoveArmor(Player)
    do
        local Character = Player.Character

        for _,v in next, Character:GetDescendants() do
            if v and v.Parent then
                if v:IsA("BasePart") and v.Parent.Parent == Character then
                    if v.Parent:FindFirstChild("IsPickaxe") or v.Parent.Parent:FindFirstChild("IsPickaxe") or v.Name == "Circle" or v.Parent.Name == "Circle" then else
                        v:Destroy()
                    end
                end
            end
        end
    end
end

function ArmorHandler.LoadArmorOnCharacter(Player, NewArmorCharacter, ClearCurrent)
    do
        if ClearCurrent then ArmorHandler.RemoveArmor(Player) wait() end

        local ArmorTable = {};

        local Character = Player.Character

        for _,v in next, NewArmorCharacter:GetDescendants() do
            if v:IsA("BasePart") and v.Parent.Parent == NewArmorCharacter then
                v.Name = v.Parent.Name
                ArmorTable[v] = {
                    Part = v;
                    CFrameOffset = v.Parent.CFrame.p - v.CFrame.p;
                    Orientaion = v.Orientation;
                };
            end
        end

        for Index, Table in next, ArmorTable do
            local Armor = Table.Part
            local NewArmor = Armor:Clone()
            local Limb = Character[Armor.Name]
            local CFrameOffset = NewArmorCharacter[Armor.Name].CFrame:Inverse() * NewArmor.CFrame
            local Orientaion = Table.Orientaion


            NewArmor.Parent = Character:FindFirstChild(Armor.Name)
            NewArmor.CFrame = Limb.CFrame*CFrameOffset

            local WeldConstraint = Instance.new("WeldConstraint", NewArmor)
            WeldConstraint.Part0 = NewArmor
            WeldConstraint.Part1 = Character:FindFirstChild(Armor.Name)
        end

        return
    end
end

function ArmorHandler.Initialize()
    do

    end
end

return ArmorHandler
