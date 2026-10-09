--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

--..Modules..--
local Single = require(script.Single)
local Triple = require(script.Triple)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
--..
local FastWait = ControllerLoader.GetController("FastWait")
local Network = ControllerLoader.GetController("Network")
local Module3D = ControllerLoader.GetController("Module3D")
local TweenController = ControllerLoader.GetController("TweenController")
local ComponentController = ControllerLoader.GetController("ComponentController")
local NumberController = ControllerLoader.GetController("NumberController")
--..
--.. EggStats/Unlocked resolve in the background below: this module is
--.. required during the client boot chain (by EggController AND ClientNetwork),
--.. and blocking the require on server data (a remote invoke, profile-backed
--.. PlayerData) used to hang the whole chain -- permanent loading cover with
--.. a dead SKIP button. Every use site guards against them still being nil.
local EggStats

--..Variables..--
local Assets = ReplicatedStorage:WaitForChild("Assets", 30)
local Pets = Assets and Assets:WaitForChild("Pets", 10)
--..
local Player = Players.LocalPlayer
local Unlocked

--.. fetch egg display data without ever blocking the require; retry because a
--.. nil EggStats forever would leave every egg hover panel without prices/pets
task.spawn(function()
    while EggStats == nil do
        local ok, res = pcall(function()
            return Network:InvokeServer("GetData", "Dictionary", {Name = "Eggs"})
        end)
        if ok and type(res) == "table" then
            EggStats = res
        else
            warn("[EggUiController] egg stats fetch failed; retrying: ".. tostring(res))
            task.wait(3)
        end
    end
end)
local PlayerGui = Player:WaitForChild("PlayerGui", 30)
local EggUi = PlayerGui and PlayerGui:WaitForChild("EggUi", 20)
local Gui = EggUi and EggUi:WaitForChild("BillboardGui", 10)
local Frame = Gui and Gui:WaitForChild("Frame", 10)
local EggDebounce = false
local Enabled = false
local AutoStopGui
local Template

local UiController = {
    Sizes = {
        In = UDim2.new(1,0,1,0);
        Out = UDim2.new(0,0,0,0)
    };

    Gradients = {
        Other = {
            HoverGradient = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(209, 209, 209));
        };
    };

    KeyBinds = {};

    Debounce = {};
}
local Sizes = UiController.Sizes
local Debounce = UiController.Debounce
local Keybinds = UiController.KeyBinds

--.. Screen-size clamp (2026-08-21). The billboard is stud-sized (18x15), so
--.. its apparent size is purely camera-to-egg distance. In open areas (spawn)
--.. the camera keeps its distance and the panel reads normally, but in
--.. enclosed biomes (Narmek, Lava, ...) wall occlusion shoves the camera to
--.. within a few studs of the egg and the same panel ballooned past 2x the
--.. screen. FEEDBACK clamp: read the panel's actually-rendered pixel height
--.. every frame and shrink the billboard's stud size so it never covers more
--.. than MAX_HEIGHT_FRACTION of the screen -- immune to camera/adornee/offset
--.. semantics because it corrects what is really on screen. AlwaysOnTop
--.. canvases scale linearly with Size, so the corrective write lands exactly
--.. on target the next frame (no oscillation); growth back to full size is
--.. damped. (BillboardGui.DistanceLowerLimit would be the native fix, but it
--.. is a no-op in the current engine -- verified in-playtest.)
local BASE_GUI_SIZE = Gui.Size
local MAX_HEIGHT_FRACTION = 0.85 -- the normal open-field spawn view uses ~0.85 at closest natural approach
game:GetService("RunService").RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then return end
	if not (Gui.Enabled and Gui.Adornee) then
		if Gui.Size ~= BASE_GUI_SIZE then Gui.Size = BASE_GUI_SIZE end
		return
	end
	local viewportY = camera.ViewportSize.Y
	if viewportY <= 0 then return end
	local coverage = Frame.AbsoluteSize.Y / viewportY
	if coverage <= 0.01 then return end -- panel hidden/collapsing; leave it alone

	local currentScale = Gui.Size.Y.Scale / BASE_GUI_SIZE.Y.Scale
	local wanted = math.min(1, currentScale * MAX_HEIGHT_FRACTION / coverage)
	if wanted < currentScale then
		currentScale = wanted -- snap down: never render an over-cap frame longer than needed
	else
		currentScale = math.min(1, currentScale + (wanted - currentScale) * 0.2)
	end
	local target = UDim2.new(BASE_GUI_SIZE.X.Scale * currentScale, 0, BASE_GUI_SIZE.Y.Scale * currentScale, 0)
	if Gui.Size ~= target then
		Gui.Size = target
	end
end)

--.. A hatch is a full-screen reveal. Preserve every UI layer's exact prior state,
--.. then hide all gameplay/tutorial UI until the reveal finishes. EggRevealUI is
--.. the reveal itself; AutoHatchControls must remain available so auto hatch can
--.. always be stopped. This also catches custom BillboardGuis such as tutorial arrows.
local HatchLayerStates
local HatchCoreStates
local HATCH_UI_EXEMPT = {
    EggRevealUI = true;
    AutoHatchControls = true;
    --.. Single/Triple hide + restore the boss bar THEMSELVES (BossBarWasEnabled).
    --.. Managing it here too made the deferred Hatching handler snapshot the bar
    --.. AFTER the reveal had already hidden it, then re-apply that stale "false"
    --.. right after the reveal's own restore — the bar stayed invisible forever.
    BossBar = true;
}

local function HideHatchLayer(Layer)
    if not HatchLayerStates
        or not Layer:IsA("LayerCollector")
        or HATCH_UI_EXEMPT[Layer.Name] then
        return
    end

    if HatchLayerStates[Layer] == nil then
        HatchLayerStates[Layer] = Layer.Enabled
    end
    Layer.Enabled = false
end

local function SetHatchUiHidden(Hidden)
    if Hidden then
        if not HatchLayerStates then
            HatchLayerStates = {}
            for _, Layer in ipairs(PlayerGui:GetChildren()) do
                HideHatchLayer(Layer)
            end
        end

        if not HatchCoreStates then
            HatchCoreStates = {}
            for _, CoreType in ipairs(Enum.CoreGuiType:GetEnumItems()) do
                if CoreType ~= Enum.CoreGuiType.All then
                    local Ok, WasEnabled = pcall(function()
                        return StarterGui:GetCoreGuiEnabled(CoreType)
                    end)
                    if Ok then HatchCoreStates[CoreType] = WasEnabled end
                end
            end
        end
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
        end)
        return
    end

    if HatchLayerStates then
        for Layer, WasEnabled in pairs(HatchLayerStates) do
            if Layer.Parent then Layer.Enabled = WasEnabled end
        end
        HatchLayerStates = nil
    end

    if HatchCoreStates then
        for CoreType, WasEnabled in pairs(HatchCoreStates) do
            pcall(function()
                StarterGui:SetCoreGuiEnabled(CoreType, WasEnabled)
            end)
        end
        HatchCoreStates = nil
    end
end

-- Hide UI layers which replicate or are created after a hatch has already begun.
PlayerGui.ChildAdded:Connect(function(Layer)
    if Gui:GetAttribute("Hatching") == true then
        HideHatchLayer(Layer)
    end
end)

--.. The hatch reveal (Single/Triple/Quad) takes the screen over: it hides the HUD, hides this
--.. egg UI, hides the boss bar, and puts the camera into Scriptable. It used to undo all of
--.. that ONLY on its happy path, so any error mid-reveal stranded the player with a frozen
--.. camera, no HUD, and — if a panel happened to be open — Lighting.UIBlur pinned at 15.
--.. That is the "screen stuck and blurry" report. This puts the state back no matter what.
local HatchToken = 0

local function RestoreHatchState()
    pcall(function()
        workspace.CurrentCamera.CameraType = Enum.CameraType.Custom

        --.. never leave the interactive hatch's full-screen click catcher up —
        --.. it would invisibly eat every click for the rest of the session
        local RevealUi = PlayerGui:FindFirstChild("EggRevealUI")
        local Catcher = RevealUi and RevealUi:FindFirstChild("ClickCatcher")
        if Catcher then Catcher.Visible = false end

        local Display = PlayerGui:FindFirstChild("Display")
        if Display then Display.Enabled = true end

        local BossBar = PlayerGui:FindFirstChild("BossBar")
        if BossBar then BossBar.Enabled = true end

        -- Never resurrect a detached egg BillboardGui. Walking away during the
        -- reveal clears its Adornee/DisplayedEgg; enabling it here created the
        -- orphaned compressed "Hatch Once" text in the 3D world.
        local displayedEgg = Gui:GetAttribute("DisplayedEgg")
        local validAdornee = Gui.Adornee and Gui.Adornee.Parent
        if validAdornee and type(displayedEgg) == "string" and displayedEgg ~= "" then
            Frame.Size = Sizes.In
            Gui.Enabled = true
        else
            Gui.Enabled = false
            Gui.Adornee = nil
            Gui:SetAttribute("DisplayedEgg", "")
            Frame.Size = Sizes.Out
        end
        Gui:SetAttribute("Hatching", false)

        --.. Main.ToggleBlur only clears the blur when a panel is closed through OpenFrame.
        --.. If no panel is actually open, a leftover blur is stale — drop it.
        local Blur = game:GetService("Lighting"):FindFirstChild("UIBlur")
        if Blur and Blur.Size > 0 and Display then
            local Frames = Display:FindFirstChild("Frame") and Display.Frame:FindFirstChild("Frames")
            local AnyOpen = false
            if Frames then
                for _, Frame in next, Frames:GetChildren() do
                    if Frame:IsA("GuiObject") and Frame.Visible then AnyOpen = true break end
                end
            end
            if not AnyOpen then Blur.Size = 0 end
        end
    end)
end

--.. Triple and Quad run their reveals inside coroutine.wrap, so an error in there can NEVER
--.. reach the pcall below — it just kills that coroutine silently. A watchdog is the only
--.. thing that can catch those. If the reveal hasn't cleared "Hatching" long after it should
--.. have finished, it died; put the screen back.
local ReadyGuiStates

local function HideReadyIndicators()
    if not ReadyGuiStates then
        ReadyGuiStates = {}
        for _, Name in ipairs({"RewardArrow", "RebirthArrow", "ShardArrow"}) do
            local ReadyGui = PlayerGui:FindFirstChild(Name)
            if ReadyGui and ReadyGui:IsA("LayerCollector") then
                ReadyGuiStates[ReadyGui] = ReadyGui.Enabled
            end
        end
    end

    for ReadyGui in pairs(ReadyGuiStates) do
        if ReadyGui.Parent then
            ReadyGui.Enabled = false
        end
    end
end

local function RestoreReadyIndicators()
    if not ReadyGuiStates then return end

    for ReadyGui, WasEnabled in pairs(ReadyGuiStates) do
        if ReadyGui.Parent then
            ReadyGui.Enabled = WasEnabled
        end
    end
    ReadyGuiStates = nil
end

local function RestoreAutoUiIfIdle()
    if Gui:GetAttribute("Hatching") ~= true then
        RestoreHatchState()
        RestoreReadyIndicators()
    end
end

local function WatchHatch(Token, HatchSpeed, MaxTime)
    coroutine.wrap(function()
        FastWait(MaxTime or (20 / math.max(HatchSpeed, 1) + 5))

        if Token == HatchToken and Gui:GetAttribute("Hatching") then
            warn("[EggController] hatch reveal never finished — restoring camera and HUD")
            RestoreHatchState()
            Enabled = false
        end
    end)()
end

local function SetAutoStopVisible(IsVisible)
    if AutoStopGui then
        AutoStopGui.Enabled = IsVisible == true
    end
end

local function CreateAutoStopButton()
    if AutoStopGui then return end

    --.. designed in StarterGui.AutoHatchControls; this just binds behavior
    local ScreenGui = PlayerGui:WaitForChild("AutoHatchControls")
    AutoStopGui = ScreenGui

    local Button = ScreenGui:WaitForChild("StopButton")
    Button.Activated:Connect(function()
        Enabled = false
        SetAutoStopVisible(false)
        RestoreAutoUiIfIdle()
    end)

    --.. The button is authored at a fixed 190x58 px for 1080p. Shrink it on
    --.. small viewports, but keep a floor above HudScaler's 0.3 so the one
    --.. control that STOPS auto-hatch stays comfortably tappable on phones.
    local Scale = Button:FindFirstChildOfClass("UIScale")
    if not Scale then
        Scale = Instance.new("UIScale")
        Scale.Parent = Button
    end
    local function ApplyScale()
        local Camera = workspace.CurrentCamera
        local View = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
        Scale.Scale = math.clamp(math.min(View.X / 1920, View.Y / 1080), 0.55, 1)
    end
    ApplyScale()
    local ViewportConn
    local function BindCamera()
        if ViewportConn then ViewportConn:Disconnect() end
        local Camera = workspace.CurrentCamera
        if Camera then
            ViewportConn = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(ApplyScale)
        end
        ApplyScale()
    end
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(BindCamera)
    BindCamera()
end

local function OpenEgg(Type)
    if EggDebounce then return end
    EggDebounce = true

    --.. Capture the egg ONCE, up front. This used to re-read the DisplayedEgg attribute AFTER
    --.. the server round-trip; walking off the pad in that window cleared it to "", and the
    --.. reveal then died on Eggs:FindFirstChild("") -> nil, which is what stranded the camera.
    local EggName = Gui:GetAttribute("DisplayedEgg")

    --.. Always release the debounce, even if the server rejects the hatch or returns
    --.. nothing (e.g. no egg selected -> CheckEgg saw a nil egg and returned nil).
    --.. Previously the client errored on InfoTable.Result before resetting EggDebounce,
    --.. which left hatching permanently stuck for the rest of the session.
    local ok, err = pcall(function()
        if EggName == nil or EggName == "" then
            Enabled = false
            return
        end

        local InfoTable = Network:InvokeServer("OpenEgg", EggName, Type, Player)

        if type(InfoTable) == "table" and InfoTable.Result then
            HideReadyIndicators()
            local Display = PlayerGui:FindFirstChild("Display")

            local HatchSpeed = 1
            pcall(function() HatchSpeed = Player.PlayerData.FastHatch.Value end)

            HatchToken += 1
            --.. Interactive click-to-hatch (Single/Triple, non-instant) can sit idle
            --.. ~15s per click before auto-advancing; give those reveals a far larger
            --.. watchdog budget than the fully automatic ones or the watchdog would
            --.. rip the screen back mid-wait.
            local Interactive = (Type == "Single" or Type == "Triple") and InfoTable.Instant ~= true
            WatchHatch(HatchToken, HatchSpeed, Interactive and 90 or nil)

            if Type == "Single" then
                Single.Open({Egg = EggName; Pets = InfoTable.Pets; Display = Display; EggDisplay = Gui})
            elseif Type == "Triple" then
                Triple.Open({Egg = EggName; Pets = InfoTable.Pets; Display = Display; EggDisplay = Gui; Instant = InfoTable.Instant == true})
            elseif Type == "Instant" then
                Single.Open({Egg = EggName; Pets = InfoTable.Pets; Display = Display; EggDisplay = Gui; Instant = true})
            elseif Type == "Auto" then
                --.. The reveal calls this at the exact moment it finishes. Queueing the next
                --.. request directly removes the old timed polling gap while keeping this
                --.. stack bounded across an unlimited auto-hatch session.
                local ContinueAuto = function()
                    if not Enabled then return false end

                    task.defer(function()
                        if Enabled then
                            OpenEgg("Auto")
                        end
                    end)
                    return true
                end

                if #InfoTable.Pets == 1 then
                    Single.Open({Egg = EggName; Pets = InfoTable.Pets; Display = Display; EggDisplay = Gui; ContinueAuto = ContinueAuto; Instant = InfoTable.Instant == true})
                elseif #InfoTable.Pets == 3 then
                    Triple.Open({Egg = EggName; Pets = InfoTable.Pets; Display = Display; EggDisplay = Gui; ContinueAuto = ContinueAuto; Instant = InfoTable.Instant == true})
                end
            end
        else
            Enabled = false
        end
    end)

    if not ok then
        Enabled = false
        --.. Single.Open runs inline, so its errors land here — put the screen back immediately
        --.. rather than making the player wait out the watchdog.
        RestoreHatchState()
        warn("[EggController] hatch attempt failed: " .. tostring(err))
    end

    EggDebounce = false

    if Type == "Auto" and not Enabled then
        SetAutoStopVisible(false)
        RestoreAutoUiIfIdle()
    end
end

local function StartAutoHatch()
    if Enabled or EggDebounce then return end

    Enabled = true
    SetAutoStopVisible(true)
    OpenEgg("Auto")
end


--.. Roblox can keep TextScaled labels inside a BillboardGui blank until their button
--.. changes size. Rebuild the hatch captions whenever the panel appears by briefly
--.. switching them to fixed-size text for one rendered frame, then restoring scaling.
local function RefreshHatchButtonText()
    local Inner = Frame:FindFirstChild("Frame")
    local EggDisplay = Inner and Inner:FindFirstChild("EggDisplay")
    local HatchButtons = EggDisplay and EggDisplay:FindFirstChild("HatchButtons")
    if not HatchButtons then return end

    local Labels = {}
    for _, Object in ipairs(HatchButtons:GetDescendants()) do
        if Object:IsA("TextLabel") and Object.Visible then
            Labels[#Labels + 1] = {Object, Object.TextScaled}
            Object.TextTransparency = 0
            Object.TextScaled = false
        end
    end

    if #Labels == 0 then return end
    RunService.RenderStepped:Wait()

    for _, Entry in ipairs(Labels) do
        local Label, WasScaled = Entry[1], Entry[2]
        if Label.Parent then
            Label.Visible = true
            Label.TextTransparency = 0
            Label.TextScaled = WasScaled
        end
    end
end

function UiController.IsHatching()
    return Gui:GetAttribute("Hatching") == true
end

--.. "Showing" means all three agree. The hatch reveal flips Gui.Enabled back on by itself but
--.. never restores Frame.Size, and ChangeEgg's show path — the ONLY thing that does — is
--.. skipped while "Hatching" is set. So the frame could be left collapsed at Sizes.Out while
--.. Enabled and Adornee still looked perfectly healthy, and every button and caption then
--.. rendered at ZERO size. That is the "button text disappears after hatching" bug.
--.. EggController reconciles against this every tick instead of only on the enter/leave edge.
function UiController.IsShowing(CurrentEgg)
    return Gui.Enabled
        and Gui.Adornee == CurrentEgg
        and Frame.Size == Sizes.In
end

function UiController.ChangeEgg(CurrentEgg, IsIn)
    do
        if IsIn then
            if Gui:GetAttribute("Hatching") then return end --.. don't re-show hover UI mid-hatch

            --.. Never render gradient-filled TextScaled labels while their ancestor is
            --.. growing from zero. That can poison Roblox's shared gradient text cache,
            --.. making both this panel and unrelated HUD captions disappear. Lay the
            --.. panel out at full size while disabled, then reveal it in one frame.
            Gui.Enabled = false
            Frame.Size = Sizes.In
            Gui.Adornee = CurrentEgg
            Gui:SetAttribute("DisplayedEgg", CurrentEgg.Name)
            Gui.Enabled = true
            RefreshHatchButtonText()
        else
            --.. Hide first so the zero-sized layout is never submitted to the renderer.
            Gui.Enabled = false
            Gui.Adornee = nil
            Gui:SetAttribute("DisplayedEgg", "")
            Frame.Size = Sizes.Out

            Enabled = false
        end
    end
end

function UiController.PlayInstantReward(PetName, RarityText)
    if type(PetName) ~= "string" or PetName == "" or Gui:GetAttribute("Hatching") then
        return false
    end

    local Display = PlayerGui:FindFirstChild("Display")
    if not Display then return false end

    local WasDisplayEnabled = Display.Enabled
    local WasEggEnabled = Gui.Enabled
    local WasAdornee = Gui.Adornee
    local WasDisplayedEgg = Gui:GetAttribute("DisplayedEgg")
    local WasFrameSize = Frame.Size

    HideReadyIndicators()
    HatchToken += 1
    local HatchSpeed = 1
    pcall(function() HatchSpeed = Player.PlayerData.FastHatch.Value end)
    WatchHatch(HatchToken, HatchSpeed)

    local Character = Player.Character
    local Root = Character and (Character:FindFirstChild("HumanoidRootPart") or Character.PrimaryPart)
    local Camera = workspace.CurrentCamera
    if Root and Camera then
        local Focus = Root.Position + Vector3.new(0, 4.5, 0)
        Camera.CameraType = Enum.CameraType.Scriptable
        Camera.CFrame = CFrame.lookAt(Focus + Root.CFrame.LookVector * 12, Focus)
    end

    task.spawn(function()
        local Ok, Error = pcall(function()
            Single.Open({
                Egg = "Food Cuke Egg";
                Pets = {PetName};
                Display = Display;
                EggDisplay = Gui;
                Instant = true;
                RarityText = RarityText;
            })
        end)

        if not Ok then
            warn("[EggController] instant reward reveal failed: " .. tostring(Error))
            RestoreHatchState()
        end

        if Gui.Parent then
            Gui:SetAttribute("Hatching", false)
            Gui:SetAttribute("DisplayedEgg", WasDisplayedEgg or "")
            Gui.Adornee = WasAdornee
            Gui.Enabled = WasEggEnabled
            Frame.Size = WasFrameSize
        end
        if Display.Parent then Display.Enabled = WasDisplayEnabled end
        if Camera then Camera.CameraType = Enum.CameraType.Custom end
        RestoreReadyIndicators()
    end)

    return true
end

function UiController.Initialize()
    do
        CreateAutoStopButton()
        SetAutoStopVisible(false)

        Gui:GetAttributeChangedSignal("Hatching"):Connect(function()
            local IsHatching = Gui:GetAttribute("Hatching") == true
            SetHatchUiHidden(IsHatching)

            if not IsHatching and not Enabled then
                RestoreHatchState()
                RestoreReadyIndicators()
                task.defer(RefreshHatchButtonText)
            end
        end)

        Gui.Enabled = false
        Gui.Adornee = nil
        Frame.Size = Sizes.Out

        do
            local Frame = Frame.Frame
            local EggDisplay = Frame.EggDisplay
            local HatchButtons = EggDisplay.HatchButtons
            local PetDisplay = EggDisplay.PetDisplay
            local EggNameText = Frame.TextLabel

            --.. Persistent TextScaled labels inside this BillboardGui can disappear when
            --.. Roblox drops their UIGradient text surface. Merely disabling the gradient
            --.. still leaves the broken render object cached, so remove cosmetic text
            --.. gradients entirely. The captions already use the same white base color.
            local function RemoveTextGradient(TextObject)
                for _, Child in ipairs(TextObject:GetChildren()) do
                    if Child:IsA("UIGradient") then
                        Child:Destroy()
                    end
                end
            end

            RemoveTextGradient(EggNameText)
            for _, Object in ipairs(HatchButtons:GetDescendants()) do
                --.. A TextButton's direct UIGradient colors its background, so only
                --.. remove gradients belonging to child text labels.
                if Object:IsA("TextLabel") then
                    RemoveTextGradient(Object)
                end
            end

            Template = PetDisplay.Pets.Template:Clone()
            PetDisplay.Pets.Template:Destroy()

            local NormalButtons = {};

            Gui:GetAttributeChangedSignal("DisplayedEgg"):Connect(function()
                local EggName = Gui:GetAttribute("DisplayedEgg")
                if EggName ~= "" then
                    local EggTable = EggStats and EggStats[EggName]

                    EggNameText.Text = EggName

                    if EggTable then
                        HatchButtons.PriceFrame.PriceButton.TextLabel.Text = NumberController.SuffixNumber(EggTable.Price).. " Coins"
                    end
                end

                PetsInEgg()
            end)

            --.. Buttons
            do
                for _,v in next, HatchButtons.Buttons1:GetChildren() do
                    if v:IsA("TextButton") then
                        table.insert(NormalButtons, v)
                    end
                end

                for _,v in next, HatchButtons.Buttons2:GetChildren() do
                    if v:IsA("TextButton") then
                        table.insert(NormalButtons, v)
                    end
                end

                for _,Button in next, NormalButtons do
                    Button.MouseButton1Click:Connect(function()
                        if Debounce[Button] == nil then
                            Debounce[Button] = true

                            Clicked(Button)

                            for _,v in next, Keybinds do
                                if v.Button == Button then
                                    v.Function()
                                end
                            end

                            FastWait(.5)
                            Debounce[Button] = nil
                        end
                    end)
                end
            end

            --.. Keybinds
            do
                Keybinds[Enum.KeyCode.E] = {
                    Button = HatchButtons.Buttons1.HatchOnceButton;
                    Function = function()
                        OpenEgg("Single")
                    end,
                };
                Keybinds[Enum.KeyCode.R] = {
                    Button = HatchButtons.Buttons1.TripleHatchButton;
                    Function = function()
                        OpenEgg("Triple")
                    end,
                };
                Keybinds[Enum.KeyCode.T] = {
                    Button = HatchButtons.Buttons2.AutoHatchButton;
                    Function = function()
                        StartAutoHatch()
                    end,
                };
                Keybinds[Enum.KeyCode.Q] = {
                    Button = HatchButtons.Buttons2.InstantHatchButton;
                    Function = function()
                        OpenEgg("Instant")
                    end,
                };
            end

            do
                UserInputService.InputBegan:Connect(function(i,g)
                    if g then return end
                    if i.UserInputType == Enum.UserInputType.Keyboard then
                        if Keybinds[i.KeyCode] ~= nil then
                            if Debounce["Input"] == nil then
                                Debounce["Input"] = true

                                local KeyTable = Keybinds[i.KeyCode]
                                KeyTable.Function()
                                Clicked(KeyTable.Button)

                                FastWait(.5)
                                Debounce["Input"] = nil
                            end
                        end
                    end
                end)
            end

            --.. Unlocked is profile-backed and appears only after the server
            --.. finishes the profile load; never block Initialize (part of the
            --.. boot chain) waiting for it
            task.spawn(function()
                local PlayerData = Player:WaitForChild("PlayerData")
                local PetFolder = PlayerData:WaitForChild("Pets")
                Unlocked = PetFolder:WaitForChild("Unlocked")

                Unlocked.Changed:Connect(function()
                    UpdateUnlocked()
                end)
                --.. tiles built before this resolved rendered as locked; fix them
                UpdateUnlocked()
            end)
        end
    end
end

function Clicked(Button)
    if not Button then return end
    local originalSize = Button.Size
    TweenController.TweenObject(Button, "Animations", "ButtonTapped", {
        Size = UDim2.new(.55, 0, .8, 0)
    })
    task.delay(.18, function()
        if Button.Parent then
            TweenController.TweenObject(Button, "Animations", "ButtonHoverLeave", {
                Size = originalSize
            })
        end
    end)
end

local function Viewport(parent, Model, ViewportCFrame)
    local Viewport = Module3D:Attach3D(parent, Model)
    Viewport:SetDepthMultiplier(1)
    Viewport.CurrentCamera.FieldOfView = 50
    Viewport.Visible = true
    Viewport.BorderColor3 = Color3.fromRGB(0, 0, 0)
    Viewport.AnchorPoint = Vector2.new(.5,.5)
    Viewport.Position = UDim2.new(.5,0,.5,0)
    Viewport.BackgroundTransparency = 1
    Viewport.Size = UDim2.new(.95,0,.95,0)
    Viewport.Ambient = Color3.fromRGB(255, 255, 255)
    Viewport.LightColor = Color3.fromRGB(255, 255, 255)
    Viewport.LightDirection = Vector3.new(-1,1,1)

    Viewport:SetCFrame(ViewportCFrame)

    return Viewport
end

--.. Percent text color per drop rank, matching the reference style:
--.. common green -> blue -> purple -> gold -> red for the rarest.
local RankColors = {
	[1] = Color3.fromRGB(88, 196, 72);
	[2] = Color3.fromRGB(64, 148, 255);
	[3] = Color3.fromRGB(172, 110, 245);
	[4] = Color3.fromRGB(255, 168, 35);
	[5] = Color3.fromRGB(235, 82, 62);
	[6] = Color3.fromRGB(226, 48, 48);
}

local LastBuiltEgg = nil -- egg whose hover tiles are currently built, to dedupe rebuilds
function PetsInEgg()
    do
        local Frame = Frame.Frame
        local EggDisplay = Frame.EggDisplay
        local PetDisplay = EggDisplay.PetDisplay
        --..
        local EggName = Gui:GetAttribute("DisplayedEgg")

        -- Always clear the previous egg's tiles first, and skip a redundant same-egg
        -- rebuild. The build path below used to APPEND without clearing, so walking egg
        -- A -> B (both non-"") piled B's tiles + cloned 3D pet Models on top of A's,
        -- leaking ViewportFrames + Models unboundedly while walking between eggs.
        if EggName == LastBuiltEgg then
            return
        end
        LastBuiltEgg = EggName
        for _,v in next, PetDisplay.Pets:GetChildren() do
            if v:IsA("Frame") then
                v:Destroy()
            end
        end

        if EggName ~= "" then
            local EggTable = EggStats and EggStats[EggName]
            if not (EggTable and EggTable.Pets) then
                --.. stats not fetched yet; forget the dedupe so the next
                --.. DisplayedEgg change rebuilds this egg's tiles
                LastBuiltEgg = nil
                return
            end

            for Index, Values in next, EggTable.Pets do
                -- Entries without a numeric Rank are SECRET pets (Gregory): the egg
                -- display pretends they do not exist, exactly as the Pets dictionary
                -- intends. This also hardens the build against future data holes,
                -- which used to abort tile building mid-egg with a nil-to-number error.
                local rank = tonumber(Values.Rank)
                if rank then
                    local PetFrame = Template:Clone()

                    PetFrame.Name = Index
                    PetFrame.PetRarity.Text = (tonumber(Values.Percent) or 0).."%"
                    PetFrame.PetRarity.TextColor3 = RankColors[Values.Rank] or Color3.fromRGB(255, 255, 255)
                    PetFrame.LayoutOrder = rank

                    PetFrame.Parent = PetDisplay.Pets

                    local PetTemplate = Pets:FindFirstChild(Index)
                    if PetTemplate then
                        local PetModel = PetTemplate:Clone()
                        Viewport(PetFrame, PetModel, CFrame.new(0,0,0) * CFrame.fromEulerAnglesXYZ(0,math.rad(-65),0))
                    else
                        warn(("[EggController] missing pet model for %s"):format(Index))
                    end
                end
            end

            -- Update after every tile is fully built. Special frames without a
            -- ViewportFrame (for example Chest) are handled safely below.
            UpdateUnlocked()
        else
            for _,v in next, PetDisplay.Pets:GetChildren() do
                if v:IsA("Frame") then
                    v:Destroy()
                end
            end
        end
    end
end

function UpdateUnlocked()
    if not Unlocked then return end -- profile data not replicated yet
    do
        local Frame = Frame.Frame
        local EggDisplay = Frame.EggDisplay
        local PetDisplay = EggDisplay.PetDisplay.Pets

        for _,v in next, PetDisplay:GetChildren() do
            if v:IsA("Frame") then
                local PetName = v:FindFirstChild("PetName")
                local PetViewport = v:FindFirstChild("ViewportFrame") or v:FindFirstChildWhichIsA("ViewportFrame")
                local IsUnlocked = Unlocked.Value:find(v.Name, 1, true) ~= nil

                if PetName then
                    PetName.Text = IsUnlocked and require(game.ReplicatedStorage.Modules.PetDisplayNames).Get(v.Name) or "???"
                end
                if PetViewport then
                    PetViewport.ImageColor3 = IsUnlocked
                        and Color3.fromRGB(255,255,255)
                        or Color3.fromRGB(0,0,0)
                end
            end
        end
    end
end

return UiController
