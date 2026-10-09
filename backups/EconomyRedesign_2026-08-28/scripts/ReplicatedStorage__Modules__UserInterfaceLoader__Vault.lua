--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local UserInterfaceLoader = require(ReplicatedStorage.Modules.UserInterfaceLoader)

local Network = ControllerLoader.GetController("Network")
local NumberController = ControllerLoader.GetController("NumberController")

--..Variables..--
local Player = Players.LocalPlayer
local Vault
local Main
local Claiming = false

--=====================================================================
-- 2026-08-01: panel rebuilt from the figma "ClaimAFK" design, replacing the
-- old Vault frame outright. Same 756x550 canvas family as the Door "Unlock"
-- panel -- the figma canvas verbatim in pure offset px, driven by a single
-- UIScale, exactly like the Pets / Settings / Rebirth / Door panels. UIScale
-- scales TextSize, UIStroke thickness and UICorner radii; plain Scale sizing
-- scales none of them.
--
-- NO ComponentController on CollectButton: it animates a label's UIGradient on
-- hover, which recolours the authored figma text. Hover is a plain UIScale pop
-- instead, so Module.Gradients is gone -- nothing indexes it any more.
--
-- The amount no longer carries a cucumber emoji prefix: the design has a real
-- cucumber Icon ImageLabel sitting next to the Amount label.
--=====================================================================
local DESIGN_W, DESIGN_H = 756, 550
local PANEL_FILL = 0.72         --.. panel width as a multiple of the Frames box;
                                --.. reproduces the design's ~28.6% of a 16:9 screen

local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Module = {}

--..Functions..--

--.. Fires When Frame Opens -> Returns nil
function Module.OnOpen()

end

--.. Fires When Frame Closes -> Returns nil
function Module.OnClose()

end

--.. Gets Other Modules -> Returns nil
function Module.GetModules()
    Main = UserInterfaceLoader.GetInterface("Main")
end

--.. Opens the popup with the given banked amount
function Module.ShowVault(Amount)
    if not Vault then return end
    --.. no emoji prefix -- Vault.Icon is the cucumber
    Vault.Amount.Text = NumberController.SuffixNumber(Amount)
    -- GroupOfferClient waits on this state so startup popups cannot overlap.
    Player:SetAttribute("OfflineRewardFlow", "Open")
    Main.OpenFrame("Vault")
end

--.. Fires At The Start -> Returns nil
function Module.OnStart(Interface)
    Vault = Interface
    -- Set this before the delayed server check so an early group-offer ping queues
    -- instead of opening over a reward that has not been discovered yet.
    Player:SetAttribute("OfflineRewardFlow", "Checking")
    Module.GetModules()

    --.. Responsive scale (Pet Inventory pattern): drive the UIScale off the
    --.. aspect-locked Frames box -- NEVER off the panel's own AbsoluteSize.
    do
        local Scaler = Vault:FindFirstChildOfClass("UIScale")
        local Host = Vault.Parent
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

    -- Main owns the close buttons and toggles Frame.Visible directly. Watching the
    -- frame here catches both Collect and X without touching shared Main/Playtime code.
    Vault:GetPropertyChangedSignal("Visible"):Connect(function()
        if not Vault.Visible and Player:GetAttribute("OfflineRewardFlow") == "Open" then
            Player:SetAttribute("OfflineRewardFlow", "Done")
        end
    end)

    do
        local Button = Vault.CollectButton
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
            if Claiming then return end
            Claiming = true

            local Granted = Network:InvokeServer("ClaimVault")
            if Granted and Granted > 0 then
                ReplicatedStorage.Assets.Sounds['Sell Sound']:Play()
            end
            Main.OpenFrame("Vault") -- toggles the open frame closed

            Claiming = false
        end)
    end

    --.. After the loading screen is gone, ask the server what piled up while we were away
    coroutine.wrap(function()
        local PlayerGui = Player:WaitForChild("PlayerGui")
        local Start = os.clock()
        while PlayerGui:FindFirstChild("LoadingScreen") and os.clock() - Start < 30 do
            task.wait(0.5)
        end
        task.wait(1.5)

        local Amount = Network:InvokeServer("GetVault")
        if Amount and Amount >= 1 then
            Module.ShowVault(Amount)
        else
            Player:SetAttribute("OfflineRewardFlow", "Done")
        end
    end)()
end

--..Custom Functions..--

--..

return Module
