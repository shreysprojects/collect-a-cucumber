--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
local UserInterfaceLoader = require(ReplicatedStorage.Modules.UserInterfaceLoader)
local Module3D = require(game.ReplicatedStorage.Shared.Module3D)

local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")
local TweenController = ControllerLoader.GetController("TweenController")
local ComponentController = ControllerLoader.GetController("ComponentController")
--..
local PetStats = Network:InvokeServer("GetData", "Dictionary", {Name = "Pets"})

--..Variables..--
local Player = Players.LocalPlayer
local Evolving
local Info
local Scroll
local Template
--..
local SelectedIds = {};
local SelectedPet = nil;
local AmountSelected = 0;
local CanEvolve = false;
local Debounce = false;
local Tween;

local Module = {
    Connections = {};
    Gradients = {
        Frame = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(0,235,239)),
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 183, 239)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(0, 251, 255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 183, 239)),
            });
        };
        Evolve = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(204,0,255)),
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(204,0,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(231, 158, 255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(204,0,255)),
            });
        };
    }
}
local Connections = Module.Connections

--..Functions..--

--.. Fires When Frame Opens -> Returns nil
function Module.OnOpen()

    do

        local UserData = Network:InvokeServer("GetUserData")
        if UserData then
            local PetData = UserData.PetData
            if PetData then
                for Index, Values in next, PetData do
                    if Index ~= "Unlocked" then
                        if Values.Craft == "Normal" then
                            local PetTable = PetStats[Values.Name]
                            local NewTemplate = Template:Clone()
                            NewTemplate.Name = Values.Name

                            local FoundViewport = NewTemplate.Icon:FindFirstChildOfClass'ViewportFrame'
                            if FoundViewport then
                                FoundViewport:Destroy()
                            end

                            local Model3D = Module3D:Attach3D(NewTemplate.Icon, game.ReplicatedStorage.Assets.Pets[Values.Name]:Clone())
                            Model3D:SetDepthMultiplier(1.1)
                            Model3D.CurrentCamera.FieldOfView = 5
                            Model3D.Visible = true
                            Model3D:SetCFrame(CFrame.Angles(math.rad(0), math.rad(265), 0))

                            NewTemplate.Icon.Image = ''
                            NewTemplate.PetName.Text = require(game.ReplicatedStorage.Modules.PetDisplayNames).Get(Values.Name)
                            NewTemplate.LayoutOrder = PetTable.Order

                            local Id = Instance.new("StringValue")
                            Id.Name = "Id"
                            Id.Value = Index
                            Id.Parent = NewTemplate

                            NewTemplate.Parent = Scroll

                            local ButtonFunction = ComponentController.new({
                                UIGradient = NewTemplate.PetName.UIGradient;
                                Button = NewTemplate;
                                OriginalGradient = Module.Gradients.Frame.OriginalGradient;
                                HoverGradient = Module.Gradients.Frame.HoverGradient;
                            })
                            Connections[NewTemplate] = {};

                            Connections[NewTemplate].Hover = NewTemplate.MouseEnter:Connect(function()
                                ButtonFunction:Hover()
                                TweenController.TweenObject(NewTemplate.Icon, "Animations", "ButtonHoverLeave", {Rotation = -25})
                            end)
                            Connections[NewTemplate].Leave = NewTemplate.MouseLeave:Connect(function()
                                ButtonFunction:Leave()
                                TweenController.TweenObject(NewTemplate.Icon, "Animations", "ButtonHoverLeave", {Rotation = 0})
                            end)

                            Connections[NewTemplate].Click = NewTemplate.MouseButton1Click:Connect(function()
                                ButtonFunction:Burst()
                                Module.Transfer(NewTemplate)
                            end)
                        end
                    end
                end
            end
        end

    end

end

--.. Fires When Frame Closes -> Returns nil
function Module.OnClose()

    do

        Module.Reset()

        for _,Frame in next, Scroll:GetChildren() do
            if Frame:IsA("TextButton") then
                Connections[Frame].Hover:Disconnect()
                Connections[Frame].Leave:Disconnect()
                Connections[Frame].Click:Disconnect()
                Connections[Frame] = nil

                Frame:Destroy()
            end
        end

    end

end

--.. Gets Other Modules -> Returns nil
function Module.GetModules()
    --Module = UserInterfaceLoader.GetInterface("InterfaceName")
end

--.. Fires At The Start -> Returns nil
function Module.OnStart(Interface)
    Module.GetModules()
    Evolving = Interface

    Info = Interface.Info
    Scroll = Interface.Scroll.Frame
    Template = Scroll.Template:Clone()
    Scroll.Template:Destroy()

    do
        local Evolve = Info.Evolve
        local Button = Evolve.Button

        local ButtonFunction = ComponentController.new({
            UIGradient = Evolve.Label.UIGradient;
            Button = Button;
            OriginalGradient = Module.Gradients["Evolve"].OriginalGradient;
            HoverGradient = Module.Gradients["Evolve"].HoverGradient;
        })

        Button.MouseEnter:Connect(function()
            ButtonFunction:Hover()

            TweenController.TweenObject(Evolve, "Animations", "ButtonHoverLeave", {Size = UDim2.new(1.07,0,.135,0)})
        end)

        Button.MouseLeave:Connect(function()
            ButtonFunction:Leave()

            TweenController.TweenObject(Evolve, "Animations", "ButtonHoverLeave", {Size = UDim2.new(.913,0,.135,0)})
        end)

        Button.MouseButton1Down:Connect(function()
            TweenController.TweenObject(Evolve, "Animations", "ButtonHoverLeave", {Size = UDim2.new(1.07,0,.1,0)})
        end)

        Button.MouseButton1Up:Connect(function()
            TweenController.TweenObject(Evolve, "Animations", "ButtonHoverLeave", {Size = UDim2.new(1.07,0,.135,0)})
        end)

        Button.MouseButton1Click:Connect(function()
            ButtonFunction:Burst()

            if not Debounce and CanEvolve then
                Debounce = true

                local Response = Network:InvokeServer("EvolvePet", SelectedPet, SelectedIds)

                if Response then
                    for _,Button in next, Scroll:GetChildren() do
                        if Button:IsA("TextButton") and table.find(SelectedIds, Button.Id.Value) then
                            Button:Destroy()
                        end
                    end
                    Info.Evolve.Label.Visible = false
                    Info.Evolve.Darken.Visible = true
                    CanEvolve = false
                    Info.PetAmount.Success.Enabled = false

                    Module.Reset()
                end

                FastWait(.5)
                Debounce = false
            end
        end)

    end

end

--..Custom Functions..--

--..
function Module.Reset()
    do
        SelectedIds = {};
        SelectedPet = nil;
        AmountSelected = 0;
        CanEvolve = false;

        Module.HidePets(false)
        local FoundViewport = Info.View.Icon:FindFirstChildOfClass'ViewportFrame'
        if FoundViewport then
            --Info.View.Icon.Image = ""
            FoundViewport:Destroy()
        end
        Info.PetAmount.Text = string.format("Selected: %s/3", AmountSelected)
    end
end

function Module.Transfer(Frame)
    do
        if Frame then
            local PetTable = PetStats[Frame.Name]

            if Frame:GetAttribute("IsSelected") then
                Frame:SetAttribute("IsSelected", false)
                Frame.SelectedIcon.Visible = false

                Frame.LayoutOrder = PetTable.Order

                AmountSelected -= 1
                Info.PetAmount.Text = string.format("Selected: %s/3", AmountSelected)

                Info.Evolve.Label.Visible = false
                Info.Evolve.Darken.Visible = true
                CanEvolve = false
                Info.PetAmount.Success.Enabled = false

                for Index, PetId in next, SelectedIds do
                    if PetId == Frame.Id.Value then
                        table.remove(SelectedIds, Index)
                        break
                    end
                end

                if AmountSelected == 0 then
                    SelectedPet = nil
                    Module.HidePets(false)
                    local FoundViewport = Info.View.Icon:FindFirstChildOfClass'ViewportFrame'
                    if FoundViewport then
                        --Info.View.Icon.Image = ""
                        FoundViewport:Destroy()
                    end
                end
            else
                if AmountSelected+1 <= 3 then
                    Frame:SetAttribute("IsSelected", true)
                    Frame.SelectedIcon.Visible = true
                    SelectedPet = Frame.Name
                    AmountSelected += 1

                    table.insert(SelectedIds, Frame.Id.Value)

                    Frame.LayoutOrder = AmountSelected

                    Info.PetAmount.Text = string.format("Selected: %s/3", AmountSelected)

                    Info.View.Icon.Size = UDim2.new(.9,0, 1.1, 0)

                    local FoundViewport = Info.View.Icon:FindFirstChildOfClass'ViewportFrame'
                    if FoundViewport then
                        FoundViewport:Destroy()
                    end

                    local Model3D = Module3D:Attach3D(Info.View.Icon, game.ReplicatedStorage.Assets.Pets[SelectedPet]:Clone())
                    Model3D:SetDepthMultiplier(1.1)
                    Model3D.CurrentCamera.FieldOfView = 5
                    Model3D.Visible = true
                    Model3D:SetCFrame(CFrame.Angles(math.rad(0), math.rad(265), 0))
                    Info.View.Icon.Image = ''

                    if Tween ~= nil then
                        Tween:Cancel()
                        Tween = nil
                    end

                    Tween = TweenController.TweenObject(Info.View.Icon, "Animations", "Bounce", {Size = UDim2.new(.9,0,.9,0)}, true)
                    Tween:Play()

                    if AmountSelected == 1 then
                        Module.HidePets(true)

                    elseif AmountSelected == 3 then
                        CanEvolve = true
                        Info.Evolve.Darken.Visible = false
                        Info.Evolve.Label.Visible = true
                        Info.PetAmount.Success.Enabled = true
                    end
                end
            end
        end
    end
end

function Module.HidePets(IsHiding)
    do
        if IsHiding then
            for _,Button in next, Scroll:GetChildren() do
                if Button:IsA("TextButton") and Button.Name ~= SelectedPet then
                    Button.Visible = false
                end
            end
        else
            for _,Button in next, Scroll:GetChildren() do
                if Button:IsA("TextButton") then
                    Button.Visible = true
                end
            end
        end
    end
end

return Module
