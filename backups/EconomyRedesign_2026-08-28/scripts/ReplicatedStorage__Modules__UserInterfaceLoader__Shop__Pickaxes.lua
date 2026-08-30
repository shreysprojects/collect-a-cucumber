--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")
local TweenController = ControllerLoader.GetController("TweenController")
local NumberController = ControllerLoader.GetController("NumberController")
local Module3D = ControllerLoader.GetController("Module3D")
--..
local PickaxeStats = Network:InvokeServer("GetData", "Dictionary", {Name = "Pickaxes"})

--=====================================================================
-- 2026-08-01: rewritten against the figma "ItemShop" panel. Same behaviour as
-- before -- the instance names are the only thing that moved:
--
--   old Frame.Info.ItemName            -> Body.Preview.ItemName
--   old Frame.Info.Icon                -> Body.Preview.Icon          (viewport host)
--   old Frame.Info.GainFrame.GainText  -> Body.Preview.Stats.Damage + .Range
--   old Frame.Info.BuyButton           -> Body.Preview.Stats.BuyButton (+ .Label)
--   old Frame.Scroll.Frame             -> Body.Scroll
--   old Template.DarkerFrame.Icon      -> Template.Content.Enabled.Icon
--   old Template.DarkerFrame.Locked    -> Template.Content.Locked     (whole state frame)
--   old Template.DarkerFrame.Title     -> Template.Content.Enabled.Pill (+ .Label)
--
-- The design ships the README's two-state card (Enabled / Locked): instead of
-- recolouring one pill grey we swap the whole state frame, which is what the
-- locked/unlocked gate used to fake. The equipped pickaxe still gets the green pill.
--
-- NO ComponentController: it writes UIGradient.Color onto the button's TextLabel
-- and would recolour the authored figma text. Hover is a plain UIScale pop.
--=====================================================================

--..Variables..--
local Assets = ReplicatedStorage.Assets
local PickaxeAssets = Assets.Pickaxes
--..
local Player = Players.LocalPlayer
local PlayerData = Player:WaitForChild("PlayerData")
local PickaxeData = PlayerData:WaitForChild("Pickaxes")
local Owned = PickaxeData:WaitForChild("Owned")
local Equipped = PickaxeData:WaitForChild("Equipped")
local BuyAmount = PickaxeData:WaitForChild("BuyAmount")
--..
local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
--.. design px -- the preview icon pops in and elastically settles on select
local ICON_REST = UDim2.fromOffset(248, 248)
local ICON_POP = UDim2.fromOffset(302, 302)
--.. ZIndex band the panel was authored with (Display is ZIndexBehavior Global)
local CARD_ICON_Z = 26
local PREVIEW_ICON_Z = 46
--.. glyphs kept out of the source as escapes so the transport cannot mangle them
local BOLT = utf8.char(0x26A1)
local ARROW = utf8.char(0x27A4)
--..
local Debounce = false
local Initialized = false
local Panel
local Selected
local Tween

local module = {

    --.. the equipped card reads green; everything reachable keeps the design's
    --.. yellow-to-green pill. Locked cards swap to the Locked state frame.
    Equipped = {
        A = Color3.fromRGB(116, 222, 110);
        B = Color3.fromRGB(30, 150, 70);
    };
    Ready = {
        A = Color3.fromRGB(253, 252, 71);
        B = Color3.fromRGB(36, 254, 65);
    };

}

--..Functions..--

function module.Initialize(Frame)
    if Initialized then return end
    if not Frame then return end
    Initialized = true
    Panel = Frame
    do

        local Body = Panel.Body
        local Scroll = Body.Scroll
        local Preview = Body.Preview
        local ItemName = Preview.ItemName
        local IconHost = Preview.Icon
        local Stats = Preview.Stats
        local Damage = Stats.Damage
        local Range = Stats.Range
        local BuyButton = Stats.BuyButton
        local BuyLabel = BuyButton.Label

        local Template = Scroll.Template:Clone()
        Scroll.Template:Destroy()

        --.. StarterPlayerScripts.TutorialClient reads
        --.. Shop.ShopOptions.Frame.Pickaxes.Info.BuyButton.Label.Text to decide whether
        --.. the selected pickaxe is unowned. Mirror every write onto that shim.
        local ShimLabel = Panel:FindFirstChild("ShopOptions")
        ShimLabel = ShimLabel and ShimLabel:FindFirstChild("Frame")
        ShimLabel = ShimLabel and ShimLabel:FindFirstChild("Pickaxes")
        ShimLabel = ShimLabel and ShimLabel:FindFirstChild("Info")
        ShimLabel = ShimLabel and ShimLabel:FindFirstChild("BuyButton")
        ShimLabel = ShimLabel and ShimLabel:FindFirstChild("Label")

        local function SetBuyText(Text)
            BuyLabel.Text = Text
            if ShimLabel then
                ShimLabel.Text = Text
            end
        end

        --.. plain UIScale pop, the house replacement for ComponentController hover
        local function Pop(Button, Scale)
            Scale = Scale or Button:FindFirstChildOfClass("UIScale")
            if not Scale then
                Scale = Instance.new("UIScale")
                Scale.Parent = Button
            end

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
        end

        local function OwnsPickaxe(ItemName)
            local Haystack = " # " .. Owned.Value .. " # "
            return string.find(Haystack, " # " .. ItemName .. " # ", 1, true) ~= nil
        end

        local function ChangeTitle(Card)
            local Pill = Card.Content.Enabled.Pill
            local Gradient = Pill.Fill:FindFirstChildOfClass("UIGradient")
            local Tone = module.Ready

            if OwnsPickaxe(Card.Name) then
                if Equipped.Value == Card.Name then
                    Pill.Label.Text = "EQUIPPED"
                    Tone = module.Equipped
                else
                    Pill.Label.Text = "EQUIP"
                end
            else
                Pill.Label.Text = "BUY"
            end

            if Gradient then
                Gradient.Color = ColorSequence.new(Tone.A, Tone.B)
            end
        end

        local function CheckFunction(Number)
            if Number <= BuyAmount.Value then
                return true
            else
                return false
            end
        end

        local function Transfer(Card)
            if Card == nil then return end
            local Table = PickaxeStats[Card.Name]
            if Table == nil then return end

            if CheckFunction(Table.Order) then
                ItemName.Text = "";
                local Viewport = IconHost:FindFirstChildWhichIsA("ViewportFrame")
                if Viewport then
                    Viewport:Destroy()
                end
                Damage.Text = "";
                Range.Text = "";
                SetBuyText("");

                Selected = nil

                if Tween ~= nil then
                    Tween:Cancel()
                    Tween = nil
                end

                IconHost.Size = ICON_POP

                task.wait()

                if OwnsPickaxe(Card.Name) then
                    SetBuyText("EQUIP")
                else
                    if Table.Stats.Price == 0 then
                        SetBuyText("FREE")
                    else
                        SetBuyText("$" .. NumberController.SuffixNumber(Table.Stats.Price))
                    end
                end

                Selected = Card.Name

                ItemName.Text = string.upper(Card.Name);

                local Source = Card.Content.Enabled.Icon:FindFirstChildWhichIsA("ViewportFrame")
                if Source then
                    local ClonedViewport = Source:Clone()
                    ClonedViewport.Size = UDim2.new(1, 0, 1, 0)
                    ClonedViewport.ZIndex = PREVIEW_ICON_Z
                    ClonedViewport.Parent = IconHost
                end

                --.. Damage, price and range all come from the authoritative pickaxe
                --.. dictionary. The figma preview has separate labels, so the old
                --.. single GainText line is split across the two.
                Damage.Text = BOLT .. " " .. NumberController.SuffixNumber(Table.Stats.Damage or 1) .. " DMG"
                Range.Text = ARROW .. " +" .. Table.Stats.Range .. " RANGE"

                Tween = TweenController.TweenObject(IconHost, "Animations", "Bounce", {Size = ICON_REST}, true)
                Tween:Play()
            end
        end

        local function Update()
            if BuyAmount.Value == 1 then
                Transfer(Scroll:FindFirstChild("Wood Pickaxe"))
            end

            for _, Card in next, Scroll:GetChildren() do
                if Card:IsA("TextButton") then
                    local Table = PickaxeStats[Card.Name]
                    if Table then
                        local Content = Card.Content

                        --.. README's two-state Template: enable one, disable the other
                        if CheckFunction(Table.Order) then
                            Content.Enabled.Visible = true
                            Content.Locked.Visible = false
                            ChangeTitle(Card)
                        else
                            Content.Enabled.Visible = false
                            Content.Locked.Visible = true
                        end
                    end
                end
            end
        end

        local function Initialize()
            local Transfered = false
            for Index, Value in next, PickaxeStats do
                local Card = Template:Clone()
                Card.Name = Index
                Card.LayoutOrder = Value.Order
                Card.Parent = Scroll

                local Content = Card.Content
                local IconSlot = Content.Enabled.Icon

                --.. Viewport
                do
                    local Asset = PickaxeAssets:FindFirstChild(Index)
                    if Asset then
                        --.. assets are Tools now; the viewport wants the bare
                        --.. mesh, so clone the Handle out of the Tool
                        local Source = Asset:IsA("Tool") and Asset:FindFirstChild("Handle") or Asset
                        local Model = Source:Clone()
                        local Model3D = Module3D:Attach3D(IconSlot, Model)
                        Model3D:SetDepthMultiplier(.7)
                        Model3D.CurrentCamera.FieldOfView = 10
                        Model3D.Visible = true
                        Model3D.AnchorPoint = Vector2.new(.5, .5)
                        Model3D.Position = UDim2.new(.5, 0, .5, 0)
                        Model3D.BackgroundTransparency = 1
                        Model3D.Size = UDim2.new(1, 0, 1, 0)
                        Model3D.Ambient = Color3.fromRGB(252, 255, 255)
                        Model3D.LightColor = Color3.fromRGB(255, 255, 255)
                        Model3D.LightDirection = Vector3.new(2, 0, 1)
                        Model3D.ZIndex = CARD_ICON_Z

                        Model3D:SetCFrame(CFrame.Angles(math.rad(-45), math.rad(-90), 0))
                    end
                end

                Pop(Card, Content:FindFirstChildOfClass("UIScale"))

                Card.MouseEnter:Connect(function()
                    TweenController.TweenObject(IconSlot, "Animations", "ButtonHoverLeave", {Rotation = -25})
                end)

                Card.MouseLeave:Connect(function()
                    TweenController.TweenObject(IconSlot, "Animations", "ButtonHoverLeave", {Rotation = 0})
                end)

                Card.MouseButton1Click:Connect(function()
                    Transfer(Card)
                end)

                if not Transfered and Value.Order == 0 then
                    Transfered = true
                    Transfer(Card)
                end
            end

            Update()
        end

        Initialize()

        BuyAmount.Changed:Connect(function()
            Update()
        end)

        Player.CharacterRemoving:Connect(function()
            Panel.Visible = false
            Debounce = false
            if Tween then
                Tween:Cancel()
                Tween = nil
            end
        end)

        --.. Purchase Button
        do
            Pop(BuyButton, BuyButton:FindFirstChildOfClass("UIScale"))

            BuyButton.MouseButton1Click:Connect(function()
                if not Debounce then
                    Debounce = true
                    if Selected ~= nil then
                        -- The server derives purchase-versus-equip from authoritative
                        -- ownership; button copy is presentation only.
                        local Response = Network:InvokeServer("PurchasePickaxe", {
                            Function = "Purchase"; ItemName = Selected})
                        if Response then
                            SetBuyText("EQUIPPED")
                        end
                        Update()
                    end
                    FastWait(.5)
                    Debounce = false
                end
            end)
        end
    end
end

return module
