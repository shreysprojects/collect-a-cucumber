--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
--..
local FastWait = ControllerLoader.GetController("FastWait")
--..
local UiController = require(script.UiController)

--..Variables..--
--.. resolved in Initialize: an untimed WaitForChild at require time blocked
--.. the whole client boot chain (permanent loading cover, dead SKIP button)
--.. whenever workspace.Eggs replicated late
local Eggs
local Player = Players.LocalPlayer

local EggController = {}
EggController.__index = EggController

function EggController.new(EggGroup)
    local RegionTable = {};

    for _,v in next, EggGroup:GetChildren() do
        if v:IsA("Model") then
            local RegionPart = v:FindFirstChild("RegionPart")
            if RegionPart then
                table.insert(RegionTable, RegionPart)
            end
        end
    end

    return setmetatable({
        InRegion = false;
        Group = RegionTable;
        EggDisplayed = "";
        RootPart = nil;
        OriginalGroup = EggGroup
    }, EggController)
end

function EggController:GetRayParameters()
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = self.Group
    raycastParams.IgnoreWater = true
    return raycastParams
end

--.. StreamingEnabled: far eggs (Narmek is ~1100 studs from spawn) are not replicated yet
--.. when the join-time snapshot in .new() runs, and a part that streams out comes back as a
--.. brand-new instance. A one-time list therefore permanently missed the last egg. Re-scan
--.. every tick instead; eight FindFirstChild calls per 0.3s is negligible.
function EggController:RefreshGroup()
    local RegionTable = {};

    for _,v in next, self.OriginalGroup:GetChildren() do
        if v:IsA("Model") then
            local RegionPart = v:FindFirstChild("RegionPart")
            if RegionPart then
                table.insert(RegionTable, RegionPart)
            end
        end
    end

    self.Group = RegionTable
    return RegionTable
end

--.. The character is thrown away and rebuilt on every respawn, and WizardStarterCharacter
--.. reloads it once more right after joining. Holding the first HumanoidRootPart forever
--.. left the raycast firing from a dead body, so the egg UI never appeared again.
function EggController:BindCharacter(Character)
    local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 10)
    if not HumanoidRootPart then return end

    self.RootPart = HumanoidRootPart

    self.InRegion = false;
    self.EggDisplayed = ""
    UiController.ChangeEgg(nil, false)
end

function EggController:CreateLoop()
    do
        if Player.Character then
            coroutine.wrap(function()
                self:BindCharacter(Player.Character)
            end)()
        end

        Player.CharacterAdded:Connect(function(Character)
            self:BindCharacter(Character)
        end)

        coroutine.wrap(function()
            local Parameters = self:GetRayParameters()

            while FastWait(.3) do
                local HumanoidRootPart = self.RootPart

                if HumanoidRootPart and HumanoidRootPart.Parent then
                    Parameters.FilterDescendantsInstances = self:RefreshGroup()
                    local raycastResult = workspace:Raycast(HumanoidRootPart.Position, HumanoidRootPart.CFrame.LookVector - Vector3.new(0,10,0), Parameters)

                    if raycastResult then
                        local Egg = self:GetEggFromRegionPart(raycastResult.Instance)

                        --.. Reconcile, don't edge-trigger. The hatch reveal hides this UI behind
                        --.. our back, and ChangeEgg's show path (the only thing that restores the
                        --.. frame's size) is skipped while "Hatching" is set. An enter/leave-only
                        --.. loop could therefore never bring it back: the frame stayed collapsed
                        --.. at zero size, so the buttons' captions rendered as nothing. Re-assert
                        --.. whenever the UI isn't actually up for the egg we're standing on.
                        if Egg and not UiController.IsHatching() then
                            self.InRegion = true;
                            self.EggDisplayed = Egg.Name

                            if not UiController.IsShowing(Egg) then
                                UiController.ChangeEgg(Egg, true)
                            end
                        end
                    else
                        if self.InRegion then
                            self.InRegion = false;
                            self.EggDisplayed = ""
                            UiController.ChangeEgg(nil, false)
                        end
                    end
                end
            end
        end)()
    end
end

function EggController:GetEggFromRegionPart(RegionPart)
    if self then
        local OriginalGroup = self.OriginalGroup
        for _,Egg in next, OriginalGroup:GetChildren() do
            if RegionPart:IsDescendantOf(Egg) then
                return Egg
            end
        end
    end
end

function EggController.Initialize()
    UiController.Initialize()

    --.. never block the boot chain on workspace.Eggs; the egg proximity UI
    --.. simply comes online whenever the folder finishes replicating
    task.spawn(function()
        Eggs = workspace:FindFirstChild("Eggs") or workspace:WaitForChild("Eggs", 30)
        if not Eggs then
            warn("[EggController] workspace.Eggs still missing after 30s; waiting on replication")
            Eggs = workspace:WaitForChild("Eggs")
        end

        local Controller = EggController.new(Eggs)
        Controller:CreateLoop()
    end)
end

return EggController
