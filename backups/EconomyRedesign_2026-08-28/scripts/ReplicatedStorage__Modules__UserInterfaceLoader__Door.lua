--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
local UserInterfaceLoader = require(ReplicatedStorage.Modules.UserInterfaceLoader)

local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")
local NumberController = ControllerLoader.GetController("NumberController")

local Main

--..Variables..--
local Player = Players.LocalPlayer
local DoorStats = Network:InvokeServer("GetData", "Dictionary", {Name = "Doors"})
--..
local Debounce = false
local Opened = false
local Door
local DefaultText
local PromptDoorName

--=====================================================================
-- 2026-08-01: panel rebuilt from the figma UNLOCK design.
-- The panel is the figma canvas verbatim (756x550, pure offset) driven by a
-- UIScale, exactly like the Pets / Settings / Rebirth panels -- UIScale scales
-- TextSize, UIStroke thickness and UICorner radii, while plain Scale sizing
-- scales none of them.
-- NO ComponentController on Purchase: it animates a label's UIGradient on
-- hover, which is what recoloured text on the other figma panels. Hover is a
-- plain UIScale pop instead.
--=====================================================================
local DESIGN_W, DESIGN_H = 756, 550
local PANEL_FILL = 0.72         --.. panel width as a multiple of the Frames box;
                                --.. reproduces the design's ~28.6% of a 16:9 screen

local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Module = {}

--..Functions..--

--.. Fires When Frame Opens -> Returns nil
function Module.OnOpen()

    do



    end

end

--.. Fires When Frame Closes -> Returns nil
function Module.OnClose()

    do



    end

end

--.. Gets Other Modules -> Returns nil
function Module.GetModules()
    --Module = UserInterfaceLoader.GetInterface("InterfaceName")
    Main = UserInterfaceLoader.GetInterface("Main")
end

--.. Fires At The Start -> Returns nil
function Module.OnStart(Interface)
    Door = Interface
    Module.GetModules()

    --.. Responsive scale (Pet Inventory pattern): drive the UIScale off the
    --.. aspect-locked Frames box -- NEVER off the panel's own AbsoluteSize.
    do
        local Scaler = Door:FindFirstChildOfClass("UIScale")
        local Host = Door.Parent
        if Scaler and Host then
            local function UpdateScale()
                if Host.AbsoluteSize.X > 0 then
                    Scaler.Scale = Host.AbsoluteSize.X * PANEL_FILL / DESIGN_W
                end
            end
            UpdateScale()
            Host:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateScale)
        end
    end

    do

        local Button = Door.Purchase
        local Scale = Button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", Button)

        Button.MouseEnter:Connect(function()
            TweenService:Create(Scale, HOVER_TWEEN, {Scale = 1.05}):Play()
        end)

        Button.MouseLeave:Connect(function()
            TweenService:Create(Scale, HOVER_TWEEN, {Scale = 1}):Play()
        end)

        Button.MouseButton1Down:Connect(function()
            TweenService:Create(Scale, HOVER_TWEEN, {Scale = 0.94}):Play()
        end)

        Button.MouseButton1Up:Connect(function()
            TweenService:Create(Scale, HOVER_TWEEN, {Scale = 1.05}):Play()
        end)

        Button.MouseButton1Click:Connect(function()
            if not Debounce then
                Debounce = true

                Main.OpenFrame("Door")
                Network:FireServer("PurchaseDoor", PromptDoorName)
                Door.Middle.Description.Text = DefaultText

                FastWait(1)
                Debounce = false
            end
        end)

    end

end

--..Custom Functions..--

--..
function Module.PromptDoor(DoorName)
    if Opened then else
        Opened = true
        local DoorTable = DoorStats[DoorName]

        PromptDoorName = DoorName

        if DoorTable then
            local Door = Player.PlayerGui.Display.Frame.Frames.Door
			local Price = DoorTable.Stats.Price
			local Currency = DoorTable.Stats.Currency
			--.. price text + currency name are data-driven (doors charge COINS since the 2026-08-26 economy pass)
			DefaultText = 'Are you sure you want to buy <font color="#459CFF">%s</font> for <font color="#FFCC2D">%s %s</font>?'
            Door.Middle.Description.Text = string.format(DefaultText, string.upper(DoorName), string.upper(NumberController.SuffixNumber(Price)), string.upper(Currency))
            Main.OpenFrame("Door")
        end

        FastWait(3)
        Opened = false
    end
end

return Module
