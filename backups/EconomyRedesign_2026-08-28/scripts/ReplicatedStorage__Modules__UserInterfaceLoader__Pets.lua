--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
local UserInterfaceLoader = require(ReplicatedStorage.Modules.UserInterfaceLoader)
local Module3D = require(game.ReplicatedStorage.Shared.Module3D)

local NumberController = ControllerLoader.GetController("NumberController")
local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")
local SoundController = ControllerLoader.GetController("SoundController")
local RarityController = require(ReplicatedStorage.Modules.FrameworkLoader.Client.EggController.RarityController)
local ProductController = require(ReplicatedStorage.Modules.ControllerLoader.Custom.ProductController)
local OpenGamepassPopup = ReplicatedStorage:WaitForChild("OpenGamepassPopup")

--..Variables..--
local Player = Players.LocalPlayer
local PlayerData = Player:WaitForChild("PlayerData")
local PetsFolder = PlayerData:WaitForChild("Pets")
local Equipped = PetsFolder:WaitForChild("Equipped")
local MaxEquipped = PetsFolder:WaitForChild("MaxEquipped")
local Inventory = PetsFolder:WaitForChild("Inventory")
local MaxInventory = PetsFolder:WaitForChild("MaxInventory")
--..
local Pets
local Scroll
local ScrollBar
local Template
local GoldenTemplate
--..
local IndexedInfo = {}
--..
local PetStats = Network:InvokeServer("GetData", "Dictionary", {Name = "Pets"})

--=====================================================================
-- 2026-07-25: panel reskinned to the figma "PET INVENTORY" design.
-- The figma layout is grid + search + Equip best / Unequip all only, so the
-- old detail pane (PetStats/PetViewport) and the per-pet Craft / Lock / Delete
-- / Craft All / Multi-Delete / Sort controls are gone. Clicking a tile now
-- toggles equip directly instead of populating a detail pane.
-- Kept deliberately: GoldenTemplate (golden crafts still exist and OnStart
-- WaitForChild's it), and the two gamepass "+" buttons.
--=====================================================================

--.. The panel is the figma canvas verbatim (1154x714, pure offset) driven by a
--.. UIScale, so every child keeps its authored TextSize / stroke / corner radius.
local DESIGN_W, DESIGN_H = 1154, 714
local PANEL_FILL = 1.37511      --.. panel width as a multiple of the Frames box
--.. scrollbar track: the grid spans y 179..586 in design space
local TRACK_Y = 179
local TRACK_H = 407


local Module = {

    Connections = {

    };

    Cache = {};

}
local Connections = Module.Connections
local Cache = Module.Cache

--..Functions..--

--=====================================================================
-- Pet viewport culling: only tiles inside the scroll window render.
-- Roblox does NOT cull ViewportFrames clipped by a ScrollingFrame, so every
-- owned pet's 3D viewport rendered at once (main driver of the ~788MB Gui cost
-- and a spike when the panel opens). We toggle each viewport's Visible based on
-- whether its tile is within the visible scroll window (+ a margin).
--=====================================================================
local Viewports = {}        -- [tile] = Model3D from Module3D:Attach3D
local PanelOpen = false
local CULL_MARGIN = 250      -- px kept rendered beyond the window so scrolling doesn't pop

local function UpdateViewportCulling()
    if not (Scroll and Scroll.Parent) then return end
    if not PanelOpen then
        for tile, m3d in pairs(Viewports) do
            if not tile.Parent then
                Viewports[tile] = nil
            elseif m3d.Visible then
                m3d.Visible = false
            end
        end
        return
    end
    local winTop = Scroll.AbsolutePosition.Y - CULL_MARGIN
    local winBot = Scroll.AbsolutePosition.Y + Scroll.AbsoluteWindowSize.Y + CULL_MARGIN
    for tile, m3d in pairs(Viewports) do
        if not tile.Parent then
            Viewports[tile] = nil
        else
            local tTop = tile.AbsolutePosition.Y
            local tBot = tTop + tile.AbsoluteSize.Y
            local onScreen = tile.Visible and tBot >= winTop and tTop <= winBot
            if m3d.Visible ~= onScreen then
                m3d.Visible = onScreen
            end
        end
    end
end

local cullQueued = false
local function queueCull()
    if cullQueued then return end
    cullQueued = true
    task.delay(0.03, function()
        cullQueued = false
        UpdateViewportCulling()
    end)
end

--.. The figma design draws its own scrollbar (ScrollBar), so the real
--.. ScrollingFrame bar is hidden and this drives the art instead.
local function UpdateScrollBar()
    if not (Scroll and ScrollBar) then return end
    local canvas = Scroll.AbsoluteCanvasSize.Y
    local window = Scroll.AbsoluteWindowSize.Y
    if canvas <= 0 or window <= 0 or canvas <= window + 1 then
        ScrollBar.Visible = false
        return
    end
    ScrollBar.Visible = true
    local thumb = math.clamp(window / canvas, 0.08, 1) * TRACK_H
    local travel = math.clamp(Scroll.CanvasPosition.Y / (canvas - window), 0, 1)
    ScrollBar.Size = UDim2.fromOffset(ScrollBar.Size.X.Offset, thumb)
    ScrollBar.Position = UDim2.fromOffset(ScrollBar.Position.X.Offset, TRACK_Y + (TRACK_H - thumb) * travel)
end

local function ApplyFilters()
    if not (Scroll and Pets) then return end
    local Box = Pets.SearchFrame.TextBox
    local Search = string.lower(Box.Text or "")
    for _,v in next, Scroll:GetChildren() do
        if v:IsA("TextButton") then
            v.Visible = Search == "" or string.find(string.lower(v.Name), Search, 1, true) ~= nil
        end
    end
    queueCull() -- tile visibility changed; re-cull viewports
    task.defer(UpdateScrollBar)
end

--.. Finds the tile carrying a given pet id.
local function FindTile(PetId)
    if not Scroll then return nil end
    for _,v in next, Scroll:GetChildren() do
        if v:IsA("TextButton") then
            local Id = v:FindFirstChild("Id")
            if Id and Id.Value == PetId then
                return v
            end
        end
    end
    return nil
end

--.. Hover: scale the WHOLE card, not just its text.
--.. Every tile shares one ZIndex band (10..16) so a card's corner badge draws over
--.. its neighbours. Display uses Global ZIndexBehavior, so the hovered card has to
--.. be lifted together with its children -- moving the card alone would make it
--.. render on top of its own icon and text.
local HOVER_SCALE = 1.08
local HOVER_LIFT = 30
local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function LiftTile(Tile, On)
    if not (Tile and Tile.Parent) then return end

    local Scale = Tile:FindFirstChildOfClass("UIScale")
    if Scale then
        TweenService:Create(Scale, HOVER_TWEEN, {Scale = On and HOVER_SCALE or 1}):Play()
    end

    local Delta = On and HOVER_LIFT or 0
    local function apply(Object)
        local Base = Object:GetAttribute("BaseZ")
        if not Base then
            Base = Object.ZIndex
            Object:SetAttribute("BaseZ", Base)
        end
        Object.ZIndex = Base + Delta
    end
    apply(Tile)
    for _, d in next, Tile:GetDescendants() do
        if d:IsA("GuiObject") then apply(d) end
    end
end

--.. Pet tooltip: mouse hover behaves normally. On touch, a deliberate hold
--.. pins the card open after the finger lifts so mobile players can move their
--.. hand away and read it. A normal tap remains reserved for equip/unequip.
local Tooltip, TooltipTile, TooltipConn
local TooltipPinned = false
local ActiveTooltipTouch, ActiveTooltipTile
local TIP_MARGIN = 18
local TOUCH_TIP_MARGIN = 72 --.. keep the pinned card clear of the player's finger

local function HideTooltip(Tile, Force)
    --.. tile-scoped hide: a stale MouseLeave must not kill a newer tile's card.
    --.. A pinned mobile card ignores ordinary MouseLeave/InputEnded cleanup.
    if Tile and TooltipTile and Tile ~= TooltipTile then return end
    if TooltipPinned and not Force then return end
    TooltipPinned = false
    TooltipTile = nil
    if Tooltip then Tooltip.Visible = false end
    if TooltipConn then TooltipConn:Disconnect() TooltipConn = nil end
end

local function PositionTooltip(ScreenPos, TouchMode)
    if not (Tooltip and Pets) then return end
    if TooltipTile and not TooltipTile.Parent then
        HideTooltip(nil, true)
        return
    end
    local Scaler = Pets:FindFirstChildOfClass("UIScale")
    local Scale = (Scaler and Scaler.Scale > 0) and Scaler.Scale or 1
    local LocalPos = (ScreenPos - Pets.AbsolutePosition) / Scale
    local W = Tooltip.AbsoluteSize.X / Scale
    local H = Tooltip.AbsoluteSize.Y / Scale
    local Margin = TouchMode and TOUCH_TIP_MARGIN or TIP_MARGIN
    local X = LocalPos.X + Margin
    if X + W > DESIGN_W then X = LocalPos.X - W - Margin end
    local Y = LocalPos.Y + Margin
    if Y + H > DESIGN_H then Y = LocalPos.Y - H - Margin end
    Tooltip.Position = UDim2.fromOffset(
        math.clamp(X, 0, math.max(0, DESIGN_W - W)),
        math.clamp(Y, 0, math.max(0, DESIGN_H - H))
    )
end

local function ShowTooltip(Tile, Pinned, ScreenPos)
    if not (Tooltip and Tile and Tile.Parent) then return end
    local Id = Tile:FindFirstChild("Id")
    local Info = Id and IndexedInfo[Id.Value]
    local StatsTable = PetStats[Tile.Name]
    local Stats = (Info and Info.Stats) or (StatsTable and StatsTable.Stats) or {}

    Tooltip.PetName.Text = string.upper(require(game.ReplicatedStorage.Modules.PetDisplayNames).Get(Tile.Name))
    local Rarity = (Info and Info.Rarity) or (StatsTable and StatsTable.Rarity) or "Common"
    Tooltip.RarityLabel.Text = string.upper(Rarity)
    local RarityClass = RarityController.Classes[Rarity]
    if RarityClass then
        local Keypoints = RarityClass.Gradient.Keypoints
        Tooltip.RarityLabel.TextColor3 = Keypoints[#Keypoints].Value
    end
    Tooltip.CashSide.Value.Text = "x" .. NumberController.SuffixNumber(Stats.Multi2 or 0)
    Tooltip.CucumberSide.Value.Text = "x" .. NumberController.SuffixNumber(Stats.Multi1 or 0)

    TooltipTile = Tile
    TooltipPinned = Pinned == true
    Tooltip.Visible = true
    local M = Player:GetMouse()
    local Position = ScreenPos or Vector2.new(M.X, M.Y)
    PositionTooltip(Position, TooltipPinned)

    if TooltipConn then TooltipConn:Disconnect() TooltipConn = nil end
    if not TooltipPinned then
        TooltipConn = UserInputService.InputChanged:Connect(function(InputObject)
            if InputObject.UserInputType == Enum.UserInputType.MouseMovement then
                PositionTooltip(Vector2.new(InputObject.Position.X, InputObject.Position.Y), false)
            end
        end)
    end
end

--.. Keeps a tile's equipped star badge and sort order in sync.
local function SetTileEquipped(Tile, IsEquipped)
    if not (Tile and Tile.Parent) then return end
    Tile.Equipped.Visible = IsEquipped
    if IsEquipped then
        Cache[Tile] = Tile.LayoutOrder
        Tile.LayoutOrder = 0
    else
        local Stats = PetStats[Tile.Name]
        Tile.LayoutOrder = (Stats and Stats.Order) or 0
        Cache[Tile] = nil
    end
end


--.. Fires When Frame Opens -> Returns nil
function Module.OnOpen()

    do
        PanelOpen = true
        UpdateViewportCulling()
        UpdateScrollBar()
    end

end

--.. Fires When Frame Closes -> Returns nil
function Module.OnClose()

    do
        PanelOpen = false
        HideTooltip(nil, true)
        UpdateViewportCulling() -- stop rendering all pet viewports while closed
    end

end

--.. Gets Other Modules -> Returns nil
function Module.GetModules()
end

--.. Fires At The Start -> Returns nil
function Module.OnStart(Interface)
    Pets = Interface
    Module.GetModules()

    do
        Scroll = Pets.PetsScroll.ScrollingFrame
        ScrollBar = Pets:FindFirstChild("ScrollBar")
        Tooltip = Pets:FindFirstChild("PetTooltip")

        -- Mobile stats are twice the authored size. UIScale preserves the
        -- card's text, strokes, icons, and spacing as one coherent design.
        if UserInputService.TouchEnabled and Tooltip then
            local MobileScale = Tooltip:FindFirstChild("MobileStatsScale") or Instance.new("UIScale")
            MobileScale.Name = "MobileStatsScale"
            MobileScale.Scale = 1.5
            MobileScale.Parent = Tooltip
        end

        -- A pinned touch tooltip stays after release. Tapping outside the pet grid
        -- dismisses it; touching any pet is handled by that tile and pins its stats.
        UserInputService.InputBegan:Connect(function(InputObject)
            if not TooltipPinned then return end
            local Kind = InputObject.UserInputType
            if Kind ~= Enum.UserInputType.Touch and Kind ~= Enum.UserInputType.MouseButton1 then return end
            local Position = InputObject.Position
            local PlayerGui = Player:FindFirstChildOfClass("PlayerGui")
            if not PlayerGui then return end
            for _, Object in ipairs(PlayerGui:GetGuiObjectsAtPosition(Position.X, Position.Y)) do
                if Object:IsDescendantOf(Scroll) then return end
            end
            ActiveTooltipTouch, ActiveTooltipTile = nil, nil
            HideTooltip(nil, true)
        end)

        -- Releasing on the same pet leaves the card pinned. Sliding the active
        -- finger outside that pet before release hides it immediately.
        UserInputService.InputChanged:Connect(function(InputObject)
            if InputObject ~= ActiveTooltipTouch or not TooltipPinned then return end
            local Tile = ActiveTooltipTile
            if not (Tile and Tile.Parent) then
                ActiveTooltipTouch, ActiveTooltipTile = nil, nil
                HideTooltip(nil, true)
                return
            end
            local Position = Vector2.new(InputObject.Position.X, InputObject.Position.Y)
            local TopLeft, Size = Tile.AbsolutePosition, Tile.AbsoluteSize
            local Inside = Position.X >= TopLeft.X and Position.X <= TopLeft.X + Size.X
                and Position.Y >= TopLeft.Y and Position.Y <= TopLeft.Y + Size.Y
            if not Inside then
                ActiveTooltipTouch, ActiveTooltipTile = nil, nil
                LiftTile(Tile, false)
                HideTooltip(nil, true)
            end
        end)

        --.. Drive the UIScale off the (aspect-locked) Frames box. This is what makes
        --.. the figma canvas responsive without touching any authored property --
        --.. UIScale scales TextSize and stroke thickness, plain Scale sizing does not.
        do
            local Scaler = Pets:FindFirstChildOfClass("UIScale")
            local Host = Pets.Parent
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

        Scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            queueCull()
            UpdateScrollBar()
        end)
        Scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(UpdateScrollBar)

        -- Drive culling off the panel's REAL Visible state. The framework's
        -- OnOpen/OnClose don't fire for this panel (DoesUpdate is off), so we watch
        -- Pets.Visible directly. Re-cull after layout settles, because the first open
        -- fires before the tiles have their AbsolutePositions.
        Pets:GetPropertyChangedSignal("Visible"):Connect(function()
            PanelOpen = Pets.Visible
            UpdateViewportCulling()
            if not PanelOpen then HideTooltip(nil, true) end
            if PanelOpen then
                task.defer(UpdateViewportCulling)
                task.defer(UpdateScrollBar)
                task.delay(0.05, UpdateViewportCulling)
            end
        end)

        Template = Scroll.Template:Clone()
        Scroll.Template:Destroy()
        GoldenTemplate = Scroll:WaitForChild'GoldenTemplate':Clone()
        Scroll.GoldenTemplate:Destroy()

        --.. Equip best / Unequip all
        do
            local Debounce = false
            for _,Button in next, {Pets.EquipBest, Pets.UnequipAll} do
                --.. NO ComponentController here. It recolours the label's UIGradient
                --.. on hover/click, which is what turned "Equip best" gold and
                --.. "Unequip all" cyan in game. Hover is a plain UIScale pop instead
                --.. and the figma text stays white.
                local Scale = Button:FindFirstChildOfClass("UIScale")

                Button.MouseEnter:Connect(function()
                    if Scale then TweenService:Create(Scale, HOVER_TWEEN, {Scale = 1.05}):Play() end
                end)

                Button.MouseLeave:Connect(function()
                    if Scale then TweenService:Create(Scale, HOVER_TWEEN, {Scale = 1}):Play() end
                end)

                Button.MouseButton1Click:Connect(function()
                    if not Debounce then
                        Debounce = true
                        Module.FunctionButtons(Button.Name)
                        FastWait(.5)
                        Debounce = false
                    end
                end)
            end
        end

        --.. Counters + the two gamepass "+" buttons
        do
            local EquippedLabel = Pets.EquippedLabel
            local StorageLabel = Pets.StorageLabel

            local function Update()
                EquippedLabel.Text = Equipped.Value.."/"..MaxEquipped.Value.." Equipped"
                StorageLabel.Text = Inventory.Value.."/"..MaxInventory.Value.." Pets"
            end

            Update()

            for _,v in next, PetsFolder:GetChildren() do
                v.Changed:Connect(function()
                    Update()
                    task.wait(.2)
                    Update()
                end)
            end

            local function WireCapacityPurchase(Label, GamepassName)
                local Button = Label:FindFirstChild("+")
                local Gamepass = ProductController.Gamepasses[GamepassName]
                if not Button or not Button:IsA("GuiButton") then
                    warn("[Pets] Missing + button under " .. Label:GetFullName())
                    return
                end
                if not Gamepass or type(Gamepass.Id) ~= "number" or Gamepass.Id <= 0 then
                    warn("[Pets] Missing gamepass data for " .. GamepassName)
                    return
                end
                local Scale = Button:FindFirstChild("ButtonScale")
                if Scale and Scale:IsA("UIScale") then
                    local BaseScale = Scale.Scale
                    local HoverTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                    Button.MouseEnter:Connect(function()
                        TweenService:Create(Scale, HoverTween, {Scale = BaseScale + 0.1}):Play()
                    end)
                    Button.MouseLeave:Connect(function()
                        TweenService:Create(Scale, HoverTween, {Scale = BaseScale}):Play()
                    end)
                end

                Button.Activated:Connect(function()
                    OpenGamepassPopup:Fire(Gamepass.Id)
                end)
            end

            WireCapacityPurchase(StorageLabel, "+75 Pet Storage")
            WireCapacityPurchase(EquippedLabel, "+4 Pet Slots")
        end

        --.. Search
        do
            Pets.SearchFrame.TextBox:GetPropertyChangedSignal("Text"):Connect(function()
                ApplyFilters()
            end)
        end


        task.defer(UpdateScrollBar)
    end

end

--..Custom Functions..--

function Module.AddPetToInventory(InfoTable)
    do
        if Template == nil then
            FastWait(1)
        end

        if InfoTable ~= nil then
            local PetId = InfoTable.Id
            local PetTable = InfoTable.Table
            if PetId and PetTable then
                IndexedInfo[PetId] = PetTable
                local StatsTable = PetStats[PetTable.Name]
                local t

                if PetTable.Craft == "Golden" then
                    if not GoldenTemplate then
                        repeat wait()until GoldenTemplate
                    end
                    t = GoldenTemplate:Clone()
                else
                    if not Template then
                        repeat wait()until Template
                    end
                    t = Template:Clone()
                end
                t.Parent = Scroll;
                t.Name = PetTable.Name;
                t.LayoutOrder = StatsTable and StatsTable.Order or 0;
                Connections[t] = {};

                --.. The tile badge is the pet's DAMAGE, so it agrees with the sword
                --.. row in the stats panel. It briefly showed Multi1+Multi2 ("power")
                --.. instead, which made a pet read 2.1 on its tile and +3 DMG in the
                --.. panel. EquipBest still ranks by combined multipliers -- that is
                --.. computed in FunctionButtons and never read off this label.
                local Stats = PetTable.Stats or {}
                local Damage = Stats.Damage or math.max(1, math.ceil((Stats.Multi1 or 1) / 2))
                t.PetName.Text = NumberController.SuffixNumber(Damage)

                --.. card background = the pet's rarity colour. The viewport that sits
                --.. on top is transparent, so this reads as the backdrop behind the
                --.. pet. The figma orange border is left untouched.
                local Rarity = PetTable.Rarity or (StatsTable and StatsTable.Rarity) or "Common"
                local RarityClass = RarityController.Classes[Rarity]
                if RarityClass then
                    local Keypoints = RarityClass.Gradient.Keypoints
                    t.BackgroundColor3 = Keypoints[#Keypoints].Value
                end

                local Model3D = Module3D:Attach3D(t.Icon, game.ReplicatedStorage.Assets.Pets[PetTable.Name]:Clone())
                Model3D:SetDepthMultiplier(1.1)
                Model3D.CurrentCamera.FieldOfView = 5
                Model3D.Visible = true
                Model3D:SetCFrame(CFrame.Angles(math.rad(0), math.rad(265), 0))
                Viewports[t] = Model3D -- register for viewport culling
                queueCull()

                --.. Icon fills the whole card, and Module3D fits a centred square to
                --.. it, so the pet renders card-sized. (Module3D was writing that
                --.. square in raw pixels, which the panel's UIScale applied twice --
                --.. fixed in Module3D.UpdateFrameSize.)

                t.Icon.Image = ''

                SetTileEquipped(t, PetTable.Equipped and true or false)

                local Id = Instance.new("StringValue", t)
                Id.Name = "Id"
                Id.Value = PetId

                --.. NO ComponentController on tiles either -- it was animating
                --.. PetName's UIGradient, which is what turned the damage text blue.
                Connections[t].Hover = t.MouseEnter:Connect(function()
                    if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
                    LiftTile(t, true)
                    ShowTooltip(t, false)
                end)
                Connections[t].Leave = t.MouseLeave:Connect(function()
                    if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
                    LiftTile(t, false)
                    HideTooltip(t)
                end)

                --.. Mobile: even the lightest touch immediately pins the stats card.
                --.. Release never hides it, and the normal click still toggles equip.
                Connections[t].TouchShow = t.InputBegan:Connect(function(InputObject)
                    if InputObject.UserInputType ~= Enum.UserInputType.Touch then return end
                    local Position = Vector2.new(InputObject.Position.X, InputObject.Position.Y)
                    ActiveTooltipTouch, ActiveTooltipTile = InputObject, t
                    LiftTile(t, true)
                    ShowTooltip(t, true, Position)
                end)
                Connections[t].TouchHide = t.InputEnded:Connect(function(InputObject)
                    if InputObject.UserInputType ~= Enum.UserInputType.Touch then return end
                    if ActiveTooltipTouch == InputObject then
                        ActiveTooltipTouch, ActiveTooltipTile = nil, nil
                    end
                    LiftTile(t, false)
                    -- Intentionally remain pinned only when released without sliding away.
                end)

                --.. A normal tap continues to toggle equip/unequip.
                Connections[t].Click = t.MouseButton1Click:Connect(function()
                    Module.ToggleEquip(t)
                end)

                ApplyFilters()
            end
        end
    end
end

function Module.RemovePetFromInventory(PetIds)
    do
        task.defer(function() ApplyFilters() end)
        if PetIds ~= nil then
            for _,PetId in next, PetIds do
                local PetButton = FindTile(PetId)
                if PetButton then
                    if Connections[PetButton] then
                        for _, Conn in next, Connections[PetButton] do
                            if typeof(Conn) == "RBXScriptConnection" then Conn:Disconnect() end
                        end
                        Connections[PetButton] = nil
                    end
                    if Viewports[PetButton] then
                        Viewports[PetButton]:Destroy() -- Model3D:Destroy frees the model + disconnects FrameChanged
                        Viewports[PetButton] = nil
                    end
                    if TooltipTile == PetButton then HideTooltip(nil, true) end
                    Cache[PetButton] = nil
                    PetButton:Destroy()
                end
                if IndexedInfo[PetId] then
                    IndexedInfo[PetId] = nil
                end
            end
        end
    end
end

--=====================================================================
-- Equip/unequip feedback (SFX pass 2026-08-26)
--=====================================================================
--.. quick punch on the tile's own (hover) UIScale; the captured base keeps the
--.. hover/rest state intact on both ends of the punch
local function PunchTile(Tile)
    local Scale = Tile and Tile:FindFirstChildOfClass("UIScale")
    if not Scale then return end
    local Base = Scale.Scale
    TweenService:Create(Scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = Base * 1.08}):Play()
    task.delay(0.08, function()
        if Scale.Parent then
            TweenService:Create(Scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = Base}):Play()
        end
    end)
end

--.. brief green flash on the tile's authored UIStroke, restored exactly
local function FlashEquipStroke(Tile)
    local Stroke = Tile and Tile:FindFirstChildOfClass("UIStroke")
    if not Stroke or Tile:GetAttribute("StrokeFlashing") then return end
    Tile:SetAttribute("StrokeFlashing", true)
    local Color, Thickness = Stroke.Color, Stroke.Thickness
    Stroke.Color = Color3.fromRGB(70, 255, 100)
    Stroke.Thickness = Thickness + 2
    local Tween = TweenService:Create(Stroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Color = Color; Thickness = Thickness;})
    Tween:Play()
    Tween.Completed:Once(function()
        Stroke.Color, Stroke.Thickness = Color, Thickness
        Tile:SetAttribute("StrokeFlashing", nil)
    end)
end

--.. bulk paths ripple their punches 40ms apart (and play NO per-pet sounds)
local function StaggerPunches(Tiles)
    task.spawn(function()
        for _, Tile in ipairs(Tiles) do
            PunchTile(Tile)
            task.wait(0.04)
        end
    end)
end

--.. Tile click. Equips if there's room, unequips if already equipped.
local ToggleDebounce = false
function Module.ToggleEquip(Tile)
    if ToggleDebounce then return end
    if not (Tile and Tile.Parent) then return end
    local Id = Tile:FindFirstChild("Id")
    if not Id then return end

    ToggleDebounce = true

    local Result = Network:InvokeServer("EquipPet", Id.Value)
    RunService.Heartbeat:Wait()

    if Result == "Equipped" then
        SetTileEquipped(Tile, true)
        SoundController.PlayFX("EggPop", {Speed = 1.25; Volume = 0.4;})
        PunchTile(Tile)
        FlashEquipStroke(Tile)
    elseif Result == "Unequipped" then
        SetTileEquipped(Tile, false)
        SoundController.PlayFX("EggPop", {Speed = 0.8; Volume = 0.35;})
        PunchTile(Tile)
    end

    FastWait(.15)
    ToggleDebounce = false
end


function Module.FunctionButtons(Button)
    do
        if Button == "UnequipAll" then
            UnequipAll()
        elseif Button == "EquipBest" then
            local PetTable = {}
            UnequipAll(true) --.. silent: EquipBest owns this action's ONE composite
            RunService.Heartbeat:Wait()

            for _,v in next, Scroll:GetChildren() do
                if v:IsA("TextButton") and v:FindFirstChild("Id") then
                    local PetId = v.Id.Value
                    local PetInfo_ = IndexedInfo[PetId] or Network:InvokeServer("GetPetStats", PetId)
                    if PetInfo_ then
                        IndexedInfo[PetId] = PetInfo_
                        local TotalMulti = (PetInfo_.Stats.Multi1 or 0) + (PetInfo_.Stats.Multi2 or 0)

                        table.insert(PetTable, {
                            Id = PetId;
                            Total = tonumber(TotalMulti);
                        })
                    end
                end
            end
            RunService.Heartbeat:Wait()
            table.sort(PetTable, function(a,b)
                return a.Total > b.Total
            end)
            RunService.Heartbeat:Wait()

            local Result, EquippedIds = Network:InvokeServer("EquipBest", PetTable)

            RunService.Heartbeat:Wait()

            if Result then
                --.. ONE composite for the whole bulk action (no per-pet sounds)
                SoundController.PlayFX("Whoosh", {Speed = 1.2})
                --.. Magic Shimmer, NOT Star Sting (2026-08-27: sting = combo-milestone-only)
                SoundController.PlayFX("Magic Shimmer", {Volume = 0.35})
                local Punched = {}
                for _,v in next, Scroll:GetChildren() do
                    if v:IsA("TextButton") and v:FindFirstChild("Id") then
                        if table.find(EquippedIds, v.Id.Value) then
                            SetTileEquipped(v, true)
                            table.insert(Punched, v)
                        end
                    end
                end
                StaggerPunches(Punched)
            end
        end
    end
end

function UnequipAll(SkipFX)
    local EquippedTable = {};

    for _,v in next, Scroll:GetChildren() do
        if v:IsA("TextButton") and v:FindFirstChild("Id") then
            if v.Equipped.Visible then
                table.insert(EquippedTable, v.Id.Value)
            end
        end
    end

    local Result = Network:InvokeServer("UnequipAll", EquippedTable)

    RunService.Heartbeat:Wait()

    if Result then
        --.. ONE composite for the bulk action (EquipBest passes SkipFX and
        --.. plays its own); no per-pet sounds in bulk paths
        if not SkipFX and #EquippedTable > 0 then
            SoundController.PlayFX("Whoosh", {Speed = 1.2})
        end
        local Punched = {}
        for _,v in next, Scroll:GetChildren() do
            if v:IsA("TextButton") and v:FindFirstChild("Id") then
                if table.find(EquippedTable, v.Id.Value) then
                    SetTileEquipped(v, false)
                    table.insert(Punched, v)
                end
            end
        end
        if not SkipFX then
            StaggerPunches(Punched)
        end
    end
    FastWait(.1)
end

return Module
