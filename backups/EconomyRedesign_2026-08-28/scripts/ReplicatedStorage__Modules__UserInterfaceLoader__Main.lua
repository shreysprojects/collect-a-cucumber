--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService('TweenService')

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
local UserInterfaceLoader = require(ReplicatedStorage.Modules.UserInterfaceLoader)

local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")
local NumberController = ControllerLoader.GetController("NumberController")
local ComponentController = ControllerLoader.GetController("ComponentController")
local TweenController = ControllerLoader.GetController("TweenController")
local ProductController = ControllerLoader.GetController("ProductController")
local SoundController = ControllerLoader.GetController("SoundController")
local HapticUtil = require(ReplicatedStorage.Modules.HapticUtil)


--..Variables..--
local Player = Players.LocalPlayer
--..
local Main

local Module = {

    Debounce = {};
    FramePositions = {};
    FramesOpened = {};

    Gradients = {
        Store = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255,90,93))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,0,0)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255, 102, 102)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255,0,0))
            });
		};
        Offers = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255,179,0))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,115,0)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,213,0)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255,179,0))
            });
        };
        Index = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(247,0,255))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,0,234)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,120,242)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(247,0,255))
            });
        };
        Rebirth = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(120,255,100))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(60,255,60)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(180,255,170)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(120,255,100))
            });
        };
        Trade = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(0,200,255))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(0,170,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(140,230,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(0,200,255))
            });
        };
        Pets = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.532, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(99,206,255))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(178,235,255)),
                ColorSequenceKeypoint.new(0.532, Color3.fromRGB(142,229,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(99,206,255))
            });
        };
        Boosts = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(0,179,255))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(0,157,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(46,238,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(0,179,255))
            });
        };
        Other = {
            HoverGradient = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(209, 209, 209));
        };
        Close = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255,90,93))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,0,0)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255, 60, 60)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255,90,93))
            });
        };
        Sell = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(17,255,0))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(17,255,0)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(169, 255, 182)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(17,255,0))
            });
        };
        Pickaxes = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(214,0,242))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(214,0,242)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(240,150,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(214,0,242))
            });
        };
        Travel = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(0,179,255))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(0,157,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(46,238,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(0,179,255))
            });
        };
        AddButtonGem = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(214,0,242)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(194,0,211)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(214,0,242))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(214,0,242)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(194,0,211)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(214,0,242))
            });
        };
        AddButtonCoins = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,234,0)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,183,0)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255,128,0))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,234,0)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(255,183,0)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255,128,0))
            });
        };
        AddButtonCucumbers = {
            OriginalGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(176,38,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(160,0,225)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(126,0,199))
            });
            HoverGradient = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(176,38,255)),
                ColorSequenceKeypoint.new(0.552, Color3.fromRGB(160,0,225)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(126,0,199))
            });
        }
    };

}
local FramePositions = Module.FramePositions
local FramesOpened = Module.FramesOpened
local Debounce = Module.Debounce

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
end

local BlurSize = 15
local BlurEffect = game.Lighting.UIBlur
local function ToggleBlur(t)
    local PlayerGui = Player:FindFirstChild("PlayerGui")
    local SellBloom = PlayerGui and PlayerGui:FindFirstChild("SellBloom")
    if SellBloom then
        SellBloom.Enabled = not t
    end
    TweenService:Create(BlurEffect, TweenInfo.new(t and .27 or .3, Enum.EasingStyle.Quint), {
        Size = t and BlurSize or 0
    }):Play()
end

local function OpenFrame(Frame, val)
    if Frame then else return end
    local IsOpen = Frame.Visible;
    local Frames = Main:FindFirstChild("Frames")

    if IsOpen and val then return end

    local PlayedTransitionSound = false
    --.. one shared swoosh per OpenFrame call; closes read pitched-down (0.85),
    --.. opens play straight (1.0)
    local function playTransitionSound(speed)
        if PlayedTransitionSound then return end
        SoundController.PlayFX("UI Transition", {Speed = speed or 1})
        PlayedTransitionSound = true
    end

    for _,ExisitingFrame in next, Frames:GetChildren() do
        if ExisitingFrame:IsA("Frame") then
            if ExisitingFrame.Visible then
                playTransitionSound(0.85)
                ToggleBlur(false)
                TweenController.TweenObject(ExisitingFrame, "FrameTweens", "Out", {Position = FramePositions[ExisitingFrame].OutPosition})
                ExisitingFrame.Visible = false
            end
        end
    end

    if IsOpen then
        playTransitionSound(0.85)
        TweenController.TweenObject(Frame, "FrameTweens", "Out", {Position = FramePositions[Frame].OutPosition})
        if FramesOpened[Frame] then
            Frame.Visible = false
            ToggleBlur(false)
        end

        for Index, Value in next, FramesOpened do
            if Index == Frame then continue end
            FramesOpened[Index] = nil;
        end
    else
        if IsOpen then return end

        ToggleBlur(true)
        playTransitionSound(1)
        Frame.Position = FramePositions[Frame].TweenPosition
        Frame.Visible = true
        TweenController.TweenObject(Frame, "FrameTweens", "In", {Position = FramePositions[Frame].Position})
    end
end

--.. Fires At The Start -> Returns nil
function Module.OnStart(Interface)
    coroutine.wrap(function()
        local mouse = Player:GetMouse()
        local function onClick()
            --.. tiny pitch jitter so click sprees don't machine-gun one sample;
            --.. MinInterval also swallows the double InputBegan some devices send
            SoundController.PlayFX("Click Sound", {Pitch = 0.03; Key = "UIClick"; MinInterval = 0.05;})
        end

        local function isOnButton()
            --.. NOTE: every "ClickCatcher" in this codebase is a FUNCTIONAL button
            --.. (Main.clickTarget creates them for bound HUD buttons), so a
            --.. name-based skip would silence the whole HUD. Inert decorations
            --.. are filtered by Active/Visible instead: a button that doesn't
            --.. sink input (Active = false) or isn't shown never clicks.
            local Buttons = Player.PlayerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
            for _, v in ipairs(Buttons) do
                local Class = v.ClassName
                if (Class == 'ImageButton' or Class == 'TextButton') and v.Active and v.Visible then
                    return true
                end
            end

            return false
        end

        type UISType = Enum.UserInputType
        local PC_Click: UISType, MobileTouch: UISType = Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch
        game:GetService'UserInputService'.InputBegan:Connect(function(input)
            local InputType = input.UserInputType
            if (InputType == PC_Click or InputType == MobileTouch) and isOnButton() then
                onClick()
            end
        end)

		--[[for _, v in ipairs(Player.PlayerGui:GetDescendants()) do
			coroutine.wrap(function()
				if v:IsA'TextButton' or v:IsA'ImageButton' then
					v.MouseButton1Click:Connect(onClick)
				end
			end)()
		end
		Player.PlayerGui.DescendantAdded:Connect(function(c)
			if c:IsA'TextButton' or c:IsA'ImageButton' then
				c.MouseButton1Click:Connect(onClick)
			end
		end)]]
    end)()

    Module.GetModules()
    Main = Interface

    do
        local Frames = Main:FindFirstChild("Frames")

        do
            coroutine.wrap(function()
                for _,Frame in next, Frames:GetChildren() do
                    if Frame:IsA("Frame") then
                        FramePositions[Frame] = {};
                        FramePositions[Frame].Position = Frame.Position
                        FramePositions[Frame].OutPosition = Frame.Position + UDim2.new(0,0,1,0)
                        FramePositions[Frame].TweenPosition = Frame.Position - UDim2.new(0,0,1,0)
                    end
                end
            end)()
        end

        do
            for _,v in next, Frames:GetChildren() do
                if v:IsA("Frame") and v.Name ~= "Store" then
                    local ButtonFunction = ComponentController.new({
                        UIGradient = v.CloseButton.TextLabel.UIGradient;
                        Button = v.CloseButton;
                        OriginalGradient = Module.Gradients["Close"].OriginalGradient;
                        HoverGradient = Module.Gradients["Close"].HoverGradient;
                    })

                    --.. X pops to 1.05 on hover (same feel as the Pets buttons)
                    local HoverScale = v.CloseButton:FindFirstChildOfClass("UIScale")
                    if not HoverScale then
                        HoverScale = Instance.new("UIScale")
                        HoverScale.Parent = v.CloseButton
                    end
                    local HoverTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

                    v.CloseButton.MouseEnter:Connect(function()
                        ButtonFunction:Hover()
                        TweenService:Create(HoverScale, HoverTween, {Scale = 1.05}):Play()
                    end)

                    v.CloseButton.MouseLeave:Connect(function()
                        ButtonFunction:Leave()
                        TweenService:Create(HoverScale, HoverTween, {Scale = 1}):Play()
                    end)

                    v.CloseButton.MouseButton1Click:Connect(function()
                        ButtonFunction:Burst()
                        OpenFrame(v)

                        delay(1, function()
                            FramesOpened[v.Name] = nil
                        end)
                    end)
                end
            end
        end

        --====================================================================
        --  Figma HUD chrome wiring
        --  bottom bar -> panels | top -> teleports | gift -> Playtime
        --  right rail -> gamepass prompts | wallet -> currency indicators
        --====================================================================
        local Marketplace = game:GetService("MarketplaceService")
        local ProductCtrl = require(ReplicatedStorage.Modules.ControllerLoader.Custom.ProductController)

        local HUD       = Player.PlayerGui:WaitForChild("HUD")
        local ButtonBar = HUD:WaitForChild("ButtonBar")
        local TopGroup  = HUD:WaitForChild("TopStatus"):WaitForChild("Group 280")
        local RightRail = HUD:WaitForChild("RightRail")
        local LeftRail  = HUD:WaitForChild("LeftRail")
        local Wallet    = HUD:WaitForChild("Wallet")

        --.. A transparent, full-size ImageButton overlay captures clicks on the figma
        --.. TextLabels / Frames that aren't buttons themselves.
        local function clickTarget(object)
            if object:IsA("GuiButton") then return object end
            local existing = object:FindFirstChild("ClickCatcher")
            if existing then return existing end
            local b = Instance.new("ImageButton")
            b.Name, b.BackgroundTransparency, b.ImageTransparency = "ClickCatcher", 1, 1
            b.Size = UDim2.fromScale(1, 1)
            b.AnchorPoint = Vector2.new(0.5, 0.5)
            b.Position = UDim2.fromScale(0.5, 0.5)
            b.ZIndex = 50
            b.Parent = object
            return b
        end

        --.. hover / press pop on the element's own UIScale (added if missing).
        local function bindButton(root, onClick)
            --.. Rail buttons live in a UIListLayout, which flows from each child's
            --.. AbsoluteSize -- and UIScale changes AbsoluteSize. Popping the root
            --.. therefore reflowed the whole rail and shoved its neighbours. Buttons
            --.. that must not do that declare a ScaleTarget attribute naming an inner
            --.. child to pop instead, leaving the root's own rect fixed.
            local hostName = root:GetAttribute("ScaleTarget")
            local scaleHost = (hostName and root:FindFirstChild(hostName)) or root
            local base = scaleHost:FindFirstChild("ButtonScale")
            if not base then base = Instance.new("UIScale"); base.Parent = scaleHost end
            local rest = base.Scale
            local btn = clickTarget(root)
            local function to(s, t) TweenService:Create(base, TweenInfo.new(t, Enum.EasingStyle.Quad), {Scale = s}):Play() end
            btn.MouseEnter:Connect(function()
                --.. globally throttled hover tick (shared Key with Store.addHover)
                SoundController.PlayFX("Click Sound", {Volume = 0.1; Speed = 1.35; Key = "UIHover"; MinInterval = 0.06;})
                to(rest * 1.08, 0.12)
            end)
            btn.MouseLeave:Connect(function() to(rest, 0.12) end)
            btn.MouseButton1Down:Connect(function() to(rest * 0.92, 0.08) end)
            btn.MouseButton1Up:Connect(function() to(rest * 1.08, 0.08) end)
            btn.MouseButton1Click:Connect(onClick)
        end

        --.. Bottom bar -> open the matching panel
        for childName, panelName in pairs({
            BACKPACK = "Pets",
            ["PET INDEX"] = "Index",
            -- Settings moved to the gray topbar circle (TopbarSettingsButtonClient).
            TRADING = "Trade",
            -- SHOP opens the Robux Store panel, NOT the pickaxe shop ("Shop"
            -- frame — that one belongs to the shop vendor / BUY teleport).
            SHOP = "Store",
        }) do
            local b = ButtonBar:FindFirstChild(childName)
            if b then bindButton(b, function() OpenFrame(Frames:FindFirstChild(panelName)) end) end
        end

        --.. Wallet -> live currency indicators + add button (Store)
        --.. task.spawn'd AHEAD of the teleport wiring: its unbounded PlayerData/Doors
        --.. waits must never be able to strand the + at its authored position, and the
        --.. leaderstats wait here must never delay the teleport buttons either.
        task.spawn(function()
            local add = Wallet:FindFirstChild("+")
            local CoinsLabel = Wallet:FindFirstChild("$100")

            --.. pin the + just right of the cash amount: the authored fixed x let
            --.. long numbers (13.25M) run underneath it. TextBounds reports
            --.. POST-UIScale (absolute) pixels while Position offsets are design px,
            --.. so divide by the wallet RegionScale to stay in one space -- same
            --.. rule as the Pets tooltip math. Gap is then identical on every device.
            local WalletScale = Wallet:FindFirstChildOfClass("UIScale")
            local function RepositionAdd()
                if not (add and CoinsLabel) then return end
                local s = (WalletScale and WalletScale.Scale > 0) and WalletScale.Scale or 1
                add.Position = UDim2.fromOffset(
                    CoinsLabel.Position.X.Offset + CoinsLabel.TextBounds.X / s + 18,
                    add.Position.Y.Offset
                )
            end
            if WalletScale then
                WalletScale:GetPropertyChangedSignal("Scale"):Connect(RepositionAdd)
            end

            local leaderstats = Player:WaitForChild("leaderstats", 30)
            if leaderstats then
                local function bindStat(statName, label, suffix)
                    local stat = leaderstats:FindFirstChild(statName)
                    if not (stat and label) then return end
                    local function upd() label.Text = NumberController.SuffixNumber(math.floor(stat.Value)) .. (suffix or "") end
                    upd()
                    stat.Changed:Connect(upd)
                end
                bindStat("Cukes", Wallet:FindFirstChild("15"))
                bindStat("Coins", CoinsLabel)
            end
            if CoinsLabel then
                RepositionAdd()
                task.defer(RepositionAdd) -- re-measure next step in case TextBounds recomputes deferred
                CoinsLabel:GetPropertyChangedSignal("TextBounds"):Connect(RepositionAdd)
            end
            if add then bindButton(add, function() Module.OpenFrame("Store", "Cucumbers") end) end
        end)

        --.. Top -> teleports (BUY = pickaxe shop, BIOME = current biome, SELL = sell area)
        do
            local PlayerData = Player:WaitForChild("PlayerData")
            local OwnedString = PlayerData:WaitForChild("Doors"):WaitForChild("OwnedString")
            local function CurrentBiome()
                local split = string.split(OwnedString.Value, " # ")
                return split[#split]
            end
            local TextService = game:GetService("TextService")
            local function fitTeleportText(label, text)
                label.Text = text
                local width = math.max(label.Size.X.Offset - 16, 40)
                local height = math.max(label.Size.Y.Offset - 4, 20)
                for size = 50, 14, -1 do
local font = label.Font == Enum.Font.Unknown and Enum.Font.FredokaOne or label.Font
                    local bounds = TextService:GetTextSize(text, size, font, Vector2.new(width, height))
                    if bounds.X <= width and bounds.Y <= height then
                        label.TextSize = size
                        return
                    end
                end
                label.TextSize = 14
            end
            --.. each pill is a TextButton carrying its own art; the inner "Label" holds the visible text
            local function textOf(button)
                if not button then return nil end
                return button:FindFirstChild("Label") or button
            end
            local biomeBtn   = TopGroup:FindFirstChild("BIOME")
            local biomeLabel = textOf(biomeBtn)
            if biomeLabel then biomeLabel.TextScaled = true end -- fit long biome names in the pill
            --.. CONTEXT FLIP (2026-08-27): the pill is the BIOME teleport (label =
            --.. your newest biome) while you stand in the LOBBY or the VAULT; out
            --.. in any biome it reads VAULT and teleports to your stall. The
            --.. region tests mirror BossBarClient.inLobby/inBank: LobbyArea part
            --.. box, static bank courtyard box, and the live DeckSlab footprint --
            --.. all re-resolved per call (rebuilds replace the deck; streaming can
            --.. replace LobbyArea).
            local function inLobbyOrVault()
                local char = Player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then return false end
                local p = hrp.Position
                --.. bank courtyard/apron (the walk out the back door)
                if p.X >= 30 and p.X <= 100 and p.Z >= -55 and p.Z <= 50 and p.Y >= -4 and p.Y <= 44 then
                    return true
                end
                --.. vault deck footprint
                local bank = workspace:FindFirstChild("CucumberBank")
                local deck = bank and bank:FindFirstChild("Deck")
                local slab = deck and deck:FindFirstChild("DeckSlab")
                if slab and slab:IsA("BasePart") then
                    local off = slab.CFrame:PointToObjectSpace(p)
                    if math.abs(off.X) <= slab.Size.X / 2 + 4
                        and math.abs(off.Z) <= slab.Size.Z / 2 + 4
                        and off.Y >= -4 and off.Y <= 90 then -- covers all 6 vault storeys (2026-08-27)
                        return true
                    end
                end
                --.. lobby shell (same part BossBarClient keys on)
                local gameFolder = workspace:FindFirstChild("Game")
                local area1 = gameFolder and gameFolder:FindFirstChild("Area 1")
                local assets = area1 and area1:FindFirstChild("Assets")
                local area = assets and assets:FindFirstChild("LobbyArea")
                if area and area:IsA("BasePart") then
                    local off = area.CFrame:PointToObjectSpace(p)
                    return math.abs(off.X) <= area.Size.X / 2 + 2
                        and math.abs(off.Y) <= area.Size.Y / 2 + 5
                        and math.abs(off.Z) <= area.Size.Z / 2 + 2
                end
                return false
            end
            local biomeModeNow = true -- players spawn in the lobby
            local function updateBiome()
                if biomeLabel then
                    fitTeleportText(biomeLabel, biomeModeNow and string.upper(CurrentBiome()) or "VAULT")
                end
            end
            updateBiome()
            OwnedString.Changed:Connect(updateBiome)
            task.spawn(function()
                while true do
                    local m = inLobbyOrVault()
                    if m ~= biomeModeNow then
                        biomeModeNow = m
                        updateBiome()
                    end
                    task.wait(0.3)
                end
            end)

            local buy = TopGroup:FindFirstChild("BUY")
            if buy then local l = textOf(buy); fitTeleportText(l, l.Text); bindButton(buy, function() Network:FireServer("TeleportToShop") end) end
            if biomeBtn then bindButton(biomeBtn, function()
                if biomeModeNow then
                    Network:FireServer("Teleport", CurrentBiome())
                else
                    Network:FireServer("TeleportToVault")
                end
            end) end
            local sell = TopGroup:FindFirstChild("SELL")
            if sell then local l = textOf(sell); fitTeleportText(l, l.Text); bindButton(sell, function() Network:FireServer("TeleportToSell") end) end
        end

        --.. Left gift -> Playtime rewards panel
        do
            local gift = LeftRail:FindFirstChild("Group 300")
            if gift then bindButton(gift, function() OpenFrame(Frames:FindFirstChild("Playtime")) end) end
        end

        --.. Left rail rebirth icon -> Rebirth panel. It is parented inside Group 300
        --.. It is nested in Group 300 on purpose: that is what makes it follow the gift
        --.. button when TopStatusLayout flips the rail horizontal on phone landscape.
        --.. Group 300 pops WobbleVisual rather than itself, so its hover cannot drag it.
        do
            local group = LeftRail:FindFirstChild("Group 300")
            local rb = group and group:FindFirstChild("Rebirth")
            if rb then bindButton(rb, function() OpenFrame(Frames:FindFirstChild("Rebirth")) end) end
        end

        --.. Left rail hoverboard -> mount / dismount the board (server-authoritative)
        do
            local board = LeftRail:FindFirstChild("Hoverboard")
            if board then bindButton(board, function() Network:FireServer("ToggleHoverboard") end) end
        end

        --.. Right rail purchases. Prices come from MarketplaceService on every
        --.. client session, so Creator Dashboard price changes need no UI edits.
        do
            local GamepassPopupEvent = ReplicatedStorage:FindFirstChild("OpenGamepassPopup")
            local NUKE_PRODUCT_ID = 3610280695

            local function openPass(id)
                if GamepassPopupEvent then
                    GamepassPopupEvent:Fire(id)
                else
                    Marketplace:PromptGamePassPurchase(Player, id)
                end
            end

            --.. purchase-result feedback for every gamepass prompt (task 2c):
            --.. success = green bloom + register/success layer, declined = a
            --.. soft neutral thock (deliberately NOT the Error buzzer)
            Marketplace.PromptGamePassPurchaseFinished:Connect(function(purchaser, passId, purchased)
                if purchaser ~= Player then return end
                if purchased then
                    task.spawn(function()
                        local PlayerGui = Player:FindFirstChild("PlayerGui")
                        local SellScreen = PlayerGui and PlayerGui:FindFirstChild("SellBloom")
                        local Bloom = SellScreen and SellScreen:FindFirstChild("SellBloom")
                        if not Bloom then return end
                        Bloom.ImageColor3 = Color3.fromRGB(120, 240, 90)
                        Bloom.ImageTransparency = 1
                        SellScreen.Enabled = true
                        local t = TweenService:Create(Bloom, TweenInfo.new(0.2), {ImageTransparency = 0.5})
                        t:Play()
                        t.Completed:Wait()
                        TweenService:Create(Bloom, TweenInfo.new(0.35), {ImageTransparency = 1}):Play()
                    end)
                    SoundController.PlayFX("Cash Register", {Key = "CashRegister"; MinInterval = 0.5;})
                    SoundController.PlayFX("Success", {Speed = 1.05})
                    pcall(HapticUtil.Pulse, 0.6, 0.15, "Small")
                else
                    SoundController.PlayFX("Click Sound", {Speed = 0.6; Volume = 0.35;})
                end
            end)

            local function priceWidgets(item)
                local group = item and item:FindFirstChild("Group 289")
                return group and group:FindFirstChild("ROBUX 1"), group and (group:FindFirstChild("Price") or group:FindFirstChild("100"))
            end

            local function loadPrice(priceLabel, id, infoType, onLoaded)
                if not priceLabel then
                    warn("[Main] Missing HUD price label for Marketplace item " .. tostring(id))
                    return
                end
                priceLabel.Text = "..."
                task.spawn(function()
                    local productType = infoType == Enum.InfoType.Product and "Product" or "Gamepass"
                    local info = ProductController.GetProductInfo(id, productType)
                    local price = info and tonumber(info.PriceInRobux)
                    if price and price > 0 then
                        onLoaded(tostring(price), info)
                    else
                        -- Marketplace outages are non-fatal; keep the purchase
                        -- button usable and show a neutral price placeholder.
                        onLoaded("--", nil)
                    end
                end)
            end

            local ON_COLOR  = Color3.fromRGB(85, 255, 0)
            local OFF_COLOR = Color3.fromRGB(255, 96, 96)
            local RAIL = {
                Jetpack = {
                    ownsAttr = "OwnsJetpack", enabledAttr = "JetpackEnabled",
                    toggle = function()
                        local rt = ReplicatedStorage:FindFirstChild("JetpackRuntime")
                        local ev = rt and rt:FindFirstChild("ToggleEnabled")
                        if ev then ev:FireServer() end
                    end,
                },
                Sprint = {
                    ownsAttr = "OwnsSprint", enabledAttr = "SprintEnabled",
                    toggle = function() Network:FireServer("ToggleSprint") end,
                },
                Autofarm = {
                    ownsAttr = "OwnsAutofarm", enabledAttr = "AutoFarmEnabled",
                    toggle = function() Network:FireServer("ToggleAutoFarm") end,
                },
            }

            for itemName, cfg in pairs(RAIL) do
                local item = RightRail:FindFirstChild(itemName)
                local pass = ProductCtrl.Gamepasses[itemName]
                if item and pass then
                    local robux, price = priceWidgets(item)
                    local clientOwns = false
                    local displayedPrice = "..."
                    local orig = price and { Color = price.TextColor3, Pos = price.Position, Size = price.Size, Anchor = price.AnchorPoint }

                    local function owned() return clientOwns or Player:GetAttribute(cfg.ownsAttr) == true end
                    local function isOn() return Player:GetAttribute(cfg.enabledAttr) ~= false end
                    local function updateVisual()
                        if not price then return end
                        if owned() then
                            if robux then robux.Visible = false end
                            price.AnchorPoint = Vector2.new(0.5, 0.5)
                            price.Position = UDim2.fromScale(0.5, 0.5)
                            price.Size = UDim2.fromScale(0.94, 0.72)
                            price.Text = isOn() and "ON" or "OFF"
                            price.TextColor3 = isOn() and ON_COLOR or OFF_COLOR
                        elseif orig then
                            if robux then robux.Visible = true end
                            price.AnchorPoint, price.Position, price.Size = orig.Anchor, orig.Pos, orig.Size
                            price.Text, price.TextColor3 = displayedPrice, orig.Color
                        end
                    end

                    updateVisual()
                    loadPrice(price, pass.Id, Enum.InfoType.GamePass, function(value)
                        displayedPrice = value
                        updateVisual()
                    end)
                    Player:GetAttributeChangedSignal(cfg.ownsAttr):Connect(updateVisual)
                    Player:GetAttributeChangedSignal(cfg.enabledAttr):Connect(updateVisual)

                    task.spawn(function()
                        local ok, res = pcall(Marketplace.UserOwnsGamePassAsync, Marketplace, Player.UserId, pass.Id)
                        if ok and res then clientOwns = true; updateVisual() end
                    end)

                    bindButton(item, function()
                        if owned() then cfg.toggle() else openPass(pass.Id) end
                    end)
                end
            end

            local nuke = RightRail:FindFirstChild("Nuke") or RightRail:FindFirstChild("Admin")
            if nuke then
                local _, price = priceWidgets(nuke)
                loadPrice(price, NUKE_PRODUCT_ID, Enum.InfoType.Product, function(value)
                    if price then price.Text = value end
                end)
                bindButton(nuke, function()
                    if GamepassPopupEvent then
                        GamepassPopupEvent:Fire({
                            id = NUKE_PRODUCT_ID,
                            product = true,
                            icon = "rbxassetid://98387716852618",
                        })
                    else
                        Marketplace:PromptProductPurchase(Player, NUKE_PRODUCT_ID)
                    end
                end)
            end
        end

    end

end

--..Custom Functions..--

--..
function Module.OpenFrame(FrameName, SpecificFrame, DoesStayOpen, close)
    local Frames = Main:FindFirstChild("Frames")

    if close then
        local Frame = Frames:FindFirstChild(FrameName)
        OpenFrame(Frame, close[1])
        return
    end

    if FrameName then

        if FramesOpened[FrameName] == nil then
            local Frame = Frames:FindFirstChild(FrameName)
            if Frame then
                if SpecificFrame ~= nil then
                    if not Frame.Visible then
                        OpenFrame(Frame)
                    end

                    if Frame.Name == "Offers" then
                        Frame.OfferOptions.Frame.UIPageLayout:JumpTo(Frame.OfferOptions.Frame:FindFirstChild(SpecificFrame))
                    elseif Frame.Name == "Store" then
                        Frame:SetAttribute("RequestedTab", SpecificFrame or "Pickles")
                    end
                else
                    if not Frame.Visible then

                        if Frame.Name == "Offers" then
                            Frame.OfferOptions.Frame.UIPageLayout:JumpTo(Frame.OfferOptions.Frame:FindFirstChild(SpecificFrame))
                        elseif Frame.Name == "Store" then
                            Frame:SetAttribute("RequestedTab", SpecificFrame or "Pickles")
                        end


                        FramesOpened[FrameName] = DoesStayOpen
                        OpenFrame(Frame)
                    else
                        OpenFrame(Frame)
                    end
                end
            else
                Frame = Main:FindFirstChild(FrameName)
                if Frame then
                    OpenFrame(Main:FindFirstChild(FrameName))
                end
            end
        end
    end
end

return Module
