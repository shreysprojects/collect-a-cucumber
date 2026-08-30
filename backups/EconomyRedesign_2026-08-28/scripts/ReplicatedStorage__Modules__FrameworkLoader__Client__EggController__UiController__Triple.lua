--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService('RunService')
local TweenService = game:GetService("TweenService")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
local RarityController = require(script.Parent.Parent.RarityController)
--..
local FastWait = ControllerLoader.GetController("FastWait")
local ProductController = ControllerLoader.GetController("ProductController")
local SoundController = ControllerLoader.GetController("SoundController")

--..Variables..--
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Eggs = Assets:WaitForChild("Eggs")
local Pets = Assets:WaitForChild("Pets")
--..
local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
--..
local FinishedOpening = false
local TripleUi

local module = {}

--..Functions..--

function module.Open(InfoTable)
    do
		if InfoTable then
			local HatchSpeed = Player.PlayerData.FastHatch.Value
			
            local EggName = InfoTable.Egg
            local PetTable = InfoTable.Pets
            local Display = InfoTable.Display
            local EggDisplay = InfoTable.EggDisplay
            local EggCFrame

            --.. Bail BEFORE taking the screen over — see Single. The restore below lives inside
            --.. the i==3 coroutine, so an error in here never reaches a pcall and would leave
            --.. the camera Scriptable and the HUD hidden permanently.
            if not Display or not EggDisplay or not Eggs:FindFirstChild(EggName) or not PetTable or not PetTable[3] then
                warn("[EggHatch] Triple: missing egg/pet data for " .. tostring(EggName) .. " — reveal skipped")
                return
            end

            --.. NO blur during hatches (user request 2026-07-15) — see Single: the played
            --.. 0-tween cancels a mid-flight ToggleBlur tween, the direct set is instant.
            do
                local Blur = game:GetService("Lighting"):FindFirstChild("UIBlur")
                if Blur then
                    TweenService:Create(Blur, TweenInfo.new(.05), {Size = 0}):Play()
                    Blur.Size = 0
                end
            end

            Display.Enabled = false
            EggDisplay.Enabled = false
            EggDisplay:SetAttribute("Hatching", true)

            local PlayerGui = Player:WaitForChild("PlayerGui")
            local BossBar = PlayerGui:FindFirstChild("BossBar")
            local BossBarWasEnabled = BossBar and BossBar.Enabled
            if BossBar then BossBar.Enabled = false end
            --.. persistent wrapper layer designed in StarterGui.EggRevealUI.TripleLayer
            local ScreenGui = PlayerGui:WaitForChild("EggRevealUI"):WaitForChild("TripleLayer")
            TripleUi = script.Triple:Clone()
            local ThisTripleUi = TripleUi
            TripleUi.Parent = ScreenGui

            ConfigureTriple(TripleUi, PetTable, EggName)

            local Instant = InfoTable.Instant == true

            --.. Interactive click-to-hatch (2026-08-10) — see Single, whose helpers
            --.. this reuses (same pattern as ApplyChance). All three eggs share ONE
            --.. click sequence: each egg coroutine gates its shake rounds on this
            --.. stage counter, driven by the click loop after the launcher below.
            --.. Auto hatch and Instant stay hands-free.
            local SingleModule = require(script.Parent.Single)
            local StageGate
            if not Instant and type(InfoTable.ContinueAuto) ~= "function" then
                StageGate = {Stage = 0}
            end

            --.. dead-air pacing only for the hands-free reveals; the interactive
            --.. path shows its click UI immediately instead (user request
            --.. 2026-08-10 "loads too slow"). Clicks during the entrances buffer.
            if not Instant and not StageGate then
                FastWait(.5/HatchSpeed)
            end
            local ClickState = StageGate and SingleModule.StartClickCatcher()

            --.. Reveal FX parity with Single (SFX pass 2026-08-26): the riser +
            --.. rarity stinger + glow fire ONCE per triple hatch, keyed to the
            --.. BEST of the three pets (per-egg calls could let a Rare shimmer
            --.. consume the stinger throttle and mask a Mythical drama sting).
            local RevealFXPlayed = false
            local BestPet = PetTable[1]
            do
                local TierOrder = {Common = 1; Uncommon = 2; Rare = 3; Epic = 4; Legendary = 5; Mythical = 6; Omega = 7; Special = 8;}
                local BestTier = -1
                for PetIndex = 1, 3 do
                    local Rarity = SingleModule.GetRarity and SingleModule.GetRarity(PetTable[PetIndex]) or nil
                    local Tier = Rarity and (TierOrder[Rarity] or 6) or 0
                    if Tier > BestTier then
                        BestTier = Tier
                        BestPet = PetTable[PetIndex]
                    end
                end
            end

            Camera.CameraType = "Scriptable";

            for i=1,3 do
                coroutine.wrap(function()
                    local EggCFrame
                    if Instant then
                        -- Instant + Triple skips all three egg animations but keeps the
                        -- three simultaneous pet reveals in their normal screen slots.
                        local X = (i == 1 and 4) or (i == 3 and -4) or 0
                        EggCFrame = Camera.CFrame * CFrame.new(X, 0, -6)
                    else
                        local Egg = Eggs:FindFirstChild(EggName):Clone()
                        Egg.Parent = workspace.CurrentCamera

                        for _,v in next, Egg:GetDescendants() do
                            if v:IsA("BasePart") then
                                v.CastShadow = false
                                v.CanCollide = false
                            end
                        end

                        tweenModelSize(Egg, .01, .1, "Linear", "Out")
                        EggPosition(Egg, i)

                        --.. see Single: snappy 0.3s pop-in when click-driven so the
                        --.. first shake isn't stuck behind the entrance
                        local EntranceTime = StageGate and .3 or 1
                        local EntranceStyle = StageGate and Enum.EasingStyle.Back or Enum.EasingStyle.Bounce
                        coroutine.wrap(function()
                            tweenModel(Egg, Egg:GetPivot() * CFrame.new(0, 0, 6), TweenInfo.new(EntranceTime, EntranceStyle, Enum.EasingDirection.Out))
                        end)()
                        tweenModelSize(Egg, EntranceTime, 10, StageGate and "Back" or "Bounce", "Out")

                        EggCFrame = Egg:GetPivot()
                        if not StageGate then
                            FastWait(.5/HatchSpeed)
                        end

                        --.. see Single: rounds are click-gated unless auto/instant.
                        --.. Triple's own tweenModel is identical to Single's, so the
                        --.. shared ShakeRound animates this egg the same way. Each egg
                        --.. spins slowly while waiting; shakes wobble relative to the
                        --.. frozen spin angle.
                        local Spin = StageGate and SingleModule.StartEggSpin(Egg, EggCFrame)
                        for RoundIndex, Round in ipairs(SingleModule.ShakeRounds) do
                            if StageGate then
                                while StageGate.Stage < RoundIndex do
                                    RunService.Heartbeat:Wait()
                                end
                            end
                            --.. riser under the FINAL shake round (idempotent:
                            --.. only the first of the three eggs starts it)
                            if RoundIndex == #SingleModule.ShakeRounds then
                                SingleModule.StartRiser()
                            end
                            if Spin then
                                --.. NO click cooldown — see Single: a newer click aborts
                                --.. the running shake, overtaken rounds are skipped
                                if StageGate.Stage <= RoundIndex then
                                    Spin.Pause()
                                    SingleModule.ShakeRound(Egg, EggCFrame, 1, Round[1], Round[2], Round[3], false, Spin.YawCF(), function()
                                        return StageGate.Stage > RoundIndex
                                    end)
                                    Spin.Resume()
                                end
                            else
                                --.. auto hatch: no click to own the pop, so the round plays it
                                SingleModule.ShakeRound(Egg, EggCFrame, HatchSpeed, Round[1], Round[2], Round[3], true)
                            end
                        end
                        if StageGate then
                            while StageGate.Stage < 4 do
                                RunService.Heartbeat:Wait()
                            end
                        end
                        if Spin then
                            EggCFrame = Spin.Stop()
                            --.. the crack click gets the same burst the shakes get
                            SingleModule.ShakeSparkles(EggCFrame)
                        end
                        tweenModel(Egg, EggCFrame, TweenInfo.new(.05, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut, 0, false))
                        --.. see Single: blink-collapse on the crack click, cinematic
                        --.. shrink only for the hands-free auto reveal
                        tweenModelSize(Egg, StageGate and .08 or .5, .01, "Back", "In")

                        EggCFrame = Egg:GetPivot()
                        Egg:Destroy()
                    end

                    local Burst = Assets.Particles.EggOpen:Clone()
                    Burst.Parent = workspace.CurrentCamera
                    Burst.CFrame = EggCFrame

                    coroutine.wrap(function()
                        Burst.Particle.Enabled = true
                        FastWait(.1)
                        Burst.Particle.Enabled = false
                        FastWait(1)
                        Burst:Destroy()
                    end)()

                    --.. card and pet leave TOGETHER: tween-out starts as the hold
                    --.. ends (the old 1s start left the bare pet floating alone
                    --.. for the back half of the hold)
                    coroutine.wrap(function()
                        FastWait(2.25/HatchSpeed)
                        TweenInTriple(TripleUi[i], true, i)
                        FastWait(.75/HatchSpeed)
                        if i == 3 then
                            ThisTripleUi:Destroy() -- the wrapper gui persists
                        end
                    end)()

                    --.. label alignment (user report 2026-08-10): the card x used
                    --.. hardcoded 16:9 guesses (.18/.5/.82) that drift off the pets
                    --.. on other aspect ratios — project the pet's actual position
                    --.. instead. Also dropped the legacy +1 WORLD-x pet offset (its
                    --.. screen direction depended on camera yaw); Single's down-.7
                    --.. is the correct offset.
                    local PetCFrame = EggCFrame * CFrame.fromEulerAnglesXYZ(0,math.rad(180),0) - Vector3.new(0,.7,0)
                    TweenInTriple(TripleUi[i], false, i, PetCFrame.Position)

                    SoundController.PlayFX("Pet Reward")
                    if not RevealFXPlayed then
                        RevealFXPlayed = true
                        SingleModule.PlayRevealFX(BestPet)
                    end
                    local Pet = Pets:FindFirstChild(PetTable[i]):Clone()
                    --.. 2026-08-22: cap reveal display height (see Single) --
                    --.. hand-modelled pets are ~6.6 studs and read way too big.
                    do
                        local _, revealSize = Pet:GetBoundingBox()
                        local RevealMaxHeight = 3.4
                        if revealSize.Y > RevealMaxHeight then
                            Pet:ScaleTo(Pet:GetScale() * (RevealMaxHeight / revealSize.Y))
                        end
                    end
                    Pet.Parent = workspace.CurrentCamera
                    for _, Part in ipairs(Pet:GetDescendants()) do
                if Part:IsA("BasePart") then Part.Anchored = true end
            end
                    Pet:PivotTo(PetCFrame)

                    local Spin

                    Spin = RunService.RenderStepped:Connect(function()
                        if Pet ~= nil and Pet.Parent ~= nil then
                            Pet:PivotTo(Pet:GetPivot() * CFrame.Angles(0,math.rad(-1),0))
                        end
                    end)

                    coroutine.wrap(function()
                        --.. spin through the whole hold AND the shrink (the
                        --.. destroyed-pet guard above makes the overshoot safe) --
                        --.. stopping earlier left the model frozen mid-air
                        FastWait(3.1/HatchSpeed)

                        Spin:Disconnect()
                    end)()

                    FastWait(2.5/HatchSpeed) --.. main "look at your pet" hold (user-tuned: 1.5 too fast, 3 too long)

                    tweenModelSize(Pet, .5, 0, "Back", "In")
                    Pet:Destroy()

                    if i == 3 then
                        local ContinueAuto = type(InfoTable.ContinueAuto) == "function"
                            and InfoTable.ContinueAuto() == true

                        EggDisplay:SetAttribute("Hatching", false)
                        if not ContinueAuto then
                            workspace.CurrentCamera.CameraType = "Custom"
                            Display.Enabled = true
                            -- Let EggController's region loop re-enable and fully lay out the
                            -- BillboardGui only if the player is still standing at this egg.
                            EggDisplay.Enabled = false
                            if BossBar then BossBar.Enabled = BossBarWasEnabled end
                        end

                        return
                    end
                end)()
                --.. tighter launch stagger when click-driven so all three eggs are
                --.. shake-ready almost together
                if not Instant then FastWait((StageGate and .15 or .4)/HatchSpeed) end
            end

            --.. the click driver: clicks 1-3 unlock one shake round on all three
            --.. eggs at once, click 4 cracks them together. Runs inline so the
            --.. catcher is torn down before the reveal cards tween in.
            if StageGate then
                for Stage = 1, 4 do
                    SingleModule.WaitForClicks(ClickState, Stage)
                    StageGate.Stage = Stage
                end
                SingleModule.StopClickCatcher(ClickState)
            end
        end
    end
end

--.. Ignore These
function tweenModel(model, CF, info)
	info = TweenInfo.new(info.Time/Player.PlayerData.FastHatch.Value, info.EasingStyle, info.EasingDirection, info.RepeatCount, info.Reverses)
	local CFrameValue = Instance.new("CFrameValue")
	CFrameValue.Value = model:GetPivot()
	CFrameValue:GetPropertyChangedSignal("Value"):Connect(function()
		model:PivotTo(CFrameValue.Value)
	end)
	local tween = TweenService:Create(CFrameValue, info, {Value = CF})
	tween:Play()
	tween.Completed:Connect(function() CFrameValue:Destroy() end)
	return tween
end

function resizeModel(model, a)
    local base = model:GetPivot().Position
    for _, part in pairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Position = base:Lerp(part.Position, a)
            part.Size *= a
        end
    end
end
function tweenModelSize(model, duration, factor, easingStyle, easingDirection, loopback)
	duration = duration/Player.PlayerData.FastHatch.Value
	local s = factor - 1
	local i = 0
	local oldAlpha = 0
	while i < 1 do
		local dt = RunService.Heartbeat:Wait()
		i = math.min(i + dt/duration, 1)
		local alpha = TweenService:GetValue(i, easingStyle, easingDirection)
		resizeModel(model, (alpha*s + 1)/(oldAlpha*s + 1))
		oldAlpha = alpha
	end
end

function ConfigureTriple(TripleFrame, PetTable, EggName)
    --.. "[1 in N]" corner tags share Single's helper (same odds source/format)
    local ApplyChance = require(script.Parent.Single).ApplyChance
    for i=1,3 do
        local PetName = TripleFrame[i].PetName
        local PetRarity = TripleFrame[i].PetRarity
        local PetUnlocked = TripleFrame[i].PetUnlocked

        PetName.Text = string.upper(require(game.ReplicatedStorage.Modules.PetDisplayNames).Get(PetTable[i]))
        RarityController.GetColors(PetTable[i], PetRarity)
        ApplyChance(TripleFrame[i], EggName, PetTable[i])
    end
end
function TweenInTriple(TripleFrame, Remove, EggNum, WorldPosition)
    if Remove then
        local tween = TweenService:Create(TripleFrame, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0,0,0,0)})
        tween:Play()
    else
        local Position
        local Width = .25

        --.. center the card on its pet by projecting the pet's world position
        --.. to the screen (x only; the bottom-strip y stays). The per-EggNum
        --.. constants survive as a fallback when no position is supplied.
        local Camera = workspace.CurrentCamera
        if WorldPosition and Camera then
            --.. the three pets sit 4 studs apart ~6 studs from the camera, so
            --.. their on-screen spacing depends on viewport aspect + FOV. Cap
            --.. the card width just under that spacing so neighbouring cards
            --.. (and their TextScaled names) can NEVER touch on any device —
            --.. wide monitors squeeze the pets together, phones spread them out.
            local Viewport = Camera.ViewportSize
            local HalfH = math.atan(math.tan(math.rad(Camera.FieldOfView / 2)) * Viewport.X / Viewport.Y)
            local SpacingScale = (4 / (6 * math.tan(HalfH))) * 0.5
            Width = math.min(.25, SpacingScale * 0.92)

            local Screen = Camera:WorldToViewportPoint(WorldPosition)
            local Edge = Width / 2 + 0.01
            local XScale = math.clamp(Screen.X / Viewport.X, Edge, 1 - Edge)
            Position = UDim2.new(XScale, 0, 0.88, 0)
        elseif EggNum == 1 then
            Position = UDim2.new(0.82,0,0.88,0)
        elseif EggNum == 2 then
            Position = UDim2.new(0.5,0,0.88,0)
        elseif EggNum == 3 then
            Position = UDim2.new(0.18,0,0.88,0)
        end
        local tween = TweenService:Create(TripleFrame, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(Width, 0, .17, 0); Position = Position})
        tween:Play()
    end
end

function EggPosition(Egg, EggNumber) --.. Sets Up The Egg Position
    Egg:PivotTo((game.Workspace.CurrentCamera.CFrame + game.Workspace.CurrentCamera.CFrame.LookVector * 12))

    if EggNumber == 1 then --.. Left
        Egg:PivotTo(Egg:GetPivot() * CFrame.new(4, 0, 0))
    elseif EggNumber == 2 then --.. Middle
        Egg:PivotTo(Egg:GetPivot() * CFrame.new(0, 0, 0))
    elseif EggNumber == 3 then --.. Right
        Egg:PivotTo(Egg:GetPivot() * CFrame.new(-4, 0, 0))
    end
end

function EggOpen(Egg, EggNumber)
    if EggNumber == 2 then --.. Middle
        wait(.4)
    elseif EggNumber == 3 then --.. Right
        wait(.8)
    end
end

return module
