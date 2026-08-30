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
local HapticUtil = require(ReplicatedStorage.Modules.HapticUtil)

--..Variables..--
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Eggs = Assets:WaitForChild("Eggs")
local Pets = Assets:WaitForChild("Pets")
--..
local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local module = {}

--..Functions..--

--.. Hatch odds for the "[1 in N]" corner tag. Same data source as the egg pad
--.. display (GetData -> Dictionaries.Eggs), fetched once. Returns nil when the
--.. pet has no odds in this egg (e.g. the playtime-reward mystery pets).
local EggStatsCache
local function ChanceText(EggName, Pet)
	if not EggStatsCache then
		local ok, res = pcall(function()
			return ControllerLoader.GetController("Network"):InvokeServer("GetData", "Dictionary", {Name = "Eggs"})
		end)
		if not ok or type(res) ~= "table" then return nil end
		EggStatsCache = res
	end
	local egg = EggStatsCache[EggName]
	local entry = egg and egg.Pets and egg.Pets[Pet]
	local percent = entry and tonumber(entry.Percent)
	if not percent or percent <= 0 then return nil end
	local n = 100 / percent
	if n >= 9.5 or n % 1 == 0 then
		return ("[1 in %d]"):format(math.floor(n + 0.5))
	end
	return ("[1 in %.1f]"):format(n)
end
module.ChanceText = ChanceText

--.. Fill the PetChance tag on a reveal frame (hidden when there are no odds).
local function ApplyChance(Holder, EggName, Pet)
	local Chance = Holder:FindFirstChild("PetChance")
	if not Chance then return end
	local text = ChanceText(EggName, Pet)
	Chance.Visible = text ~= nil
	if text then Chance.Text = text end
end
module.ApplyChance = ApplyChance

--=====================================================================
-- Reveal FX (SFX pass 2026-08-26). Shared with Triple (same pattern as
-- ApplyChance/ShakeRound): riser under the final shake round, rarity-tiered
-- stinger + rarity-colored screen glow at the reveal.
--=====================================================================

--.. lazily-fetched pet dictionary (same data source RarityController uses)
local PetStatsCache
local function PetRarity(Pet)
	if not PetStatsCache then
		local ok, res = pcall(function()
			return ControllerLoader.GetController("Network"):InvokeServer("GetData", "Dictionary", {Name = "Pets"})
		end)
		if not ok or type(res) ~= "table" then return nil end
		PetStatsCache = res
	end
	local stats = PetStatsCache[Pet]
	return stats and stats.Rarity or nil
end
module.GetRarity = PetRarity --.. Triple picks its best-of-three reveal pet with this

--.. representative flat colors per rarity (mirror of ClientNetwork's
--.. RareHatchChat hex table)
local RarityGlowColors = {
	Common = Color3.fromRGB(255, 255, 255);
	Uncommon = Color3.fromRGB(0, 207, 145);
	Rare = Color3.fromRGB(0, 255, 255);
	Epic = Color3.fromRGB(226, 0, 255);
	Legendary = Color3.fromRGB(255, 247, 0);
	Mythical = Color3.fromRGB(246, 139, 255);
	Omega = Color3.fromRGB(255, 138, 0);
	Special = Color3.fromRGB(255, 80, 80);
}

--.. One live riser at a time; started at the final shake round, stopped at the
--.. reveal (PlayRevealFX). PlayFX's MaxLife still reaps it if a hatch aborts.
local ActiveRiser
function module.StartRiser()
	if ActiveRiser then return end
	ActiveRiser = SoundController.PlayFX("Riser", {Volume = 0.4; Key = "HatchRiser"; MinInterval = 1;})
end
function module.StopRiser()
	local Riser = ActiveRiser
	ActiveRiser = nil
	if Riser then
		pcall(function()
			Riser:Stop()
			Riser:Destroy()
		end)
	end
end

--.. Rarity-tiered stinger layered over the base Pet Reward, plus a full-screen
--.. glow in the rarity color. Key + MinInterval 1.5 keep AUTO-HATCH from
--.. turning the stingers into a siren; the glow throttles itself the same way.
local LastGlow = 0
function module.PlayRevealFX(Pet)
	module.StopRiser()

	local Rarity = PetRarity(Pet)
	if Rarity == "Rare" then
		SoundController.PlayFX("Magic Shimmer", {Volume = 0.4; Key = "RarityStinger"; MinInterval = 1.5;})
	elseif Rarity == "Epic" or Rarity == "Legendary" then
		--.. deeper Magic Shimmer, NOT Star Sting (2026-08-26, user): auto-hatch
		--.. reveals fire mid-gameplay from the world billboard, and the sting is
		--.. reserved for combo milestones/crits
		SoundController.PlayFX("Magic Shimmer", {Volume = 0.55; Speed = 0.85; Key = "RarityStinger"; MinInterval = 1.5;})
		pcall(HapticUtil.Pulse, 0.5, 0.15, "Small")
	elseif Rarity and Rarity ~= "Common" and Rarity ~= "Uncommon" then
		--.. Mythical and every higher tier (Omega / Special / future ranks)
		SoundController.PlayFX("Drama Sting", {Volume = 0.6; Key = "RarityStinger"; MinInterval = 1.5;})
		SoundController.PlayFX("Thunder", {Volume = 0.25; Speed = 1.2; Key = "RarityStingerThunder"; MinInterval = 1.5;})
		pcall(HapticUtil.Pulse, 0.8, 0.25, "Small")
	end

	--.. glow: rarity color at 0.55 transparency fading to 1 over 0.5s
	local now = os.clock()
	if now - LastGlow < 0.5 then return end
	LastGlow = now
	local Color = RarityGlowColors[Rarity]
	if not Color then return end
	local PlayerGui = Player:FindFirstChild("PlayerGui")
	if not PlayerGui then return end
	local Gui = Instance.new("ScreenGui")
	Gui.Name = "HatchRevealGlow"
	Gui.DisplayOrder = 9999
	Gui.IgnoreGuiInset = true
	Gui.ResetOnSpawn = false
	local Glow = Instance.new("Frame")
	Glow.BackgroundColor3 = Color
	Glow.BorderSizePixel = 0
	Glow.Size = UDim2.fromScale(1, 1)
	Glow.BackgroundTransparency = 0.55
	Glow.Parent = Gui
	Gui.Parent = PlayerGui
	TweenService:Create(Glow, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	task.delay(0.6, function() Gui:Destroy() end)
end

function module.Open(InfoTable)
    do
		if InfoTable then
			local HatchSpeed = Player.PlayerData.FastHatch.Value
			
            local EggName = InfoTable.Egg
            local PetString = InfoTable.Pets
            local Display = InfoTable.Display
            local EggDisplay = InfoTable.EggDisplay
            local EggCFrame

            --.. Bail BEFORE taking the screen over. This used to hide the HUD and switch the
            --.. camera to Scriptable first, and only then error on Eggs:FindFirstChild(EggName)
            --.. :Clone() when the egg was missing — stranding the camera and HUD for good.
            if not Display or not EggDisplay or not Eggs:FindFirstChild(EggName) or not PetString or not PetString[1] then
                warn("[EggHatch] Single: missing egg/pet data for " .. tostring(EggName) .. " — reveal skipped")
                return
            end

            --.. NO blur during hatches (user request 2026-07-15). Direct set for an
            --.. instant effect, plus a played 0-tween to CANCEL any panel ToggleBlur
            --.. tween still mid-flight on Lighting.UIBlur (a running tween would
            --.. otherwise stomp the direct set).
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

            local PlayerGui = Player:FindFirstChild("PlayerGui")
            local BossBar = PlayerGui and PlayerGui:FindFirstChild("BossBar")
            local BossBarWasEnabled = BossBar and BossBar.Enabled
            if BossBar then BossBar.Enabled = false end

            local Instant = InfoTable.Instant == true
            local Interactive = not Instant and type(InfoTable.ContinueAuto) ~= "function"

            --.. dead-air pacing only for the hands-free reveals: the HUD is already
            --.. hidden here, so the interactive path skips straight to the egg and
            --.. its click UI instead (user request 2026-08-10 "loads too slow")
            if not Instant and not Interactive then
                FastWait(.5/HatchSpeed)
            end

            Camera.CameraType = "Scriptable";

            if Instant then
                --.. Paid instant hatch starts directly at the reward reveal: no egg clone,
                --.. entrance, shake sequence, egg-pop sounds, or egg-collapse tween.
                EggCFrame = Camera.CFrame + Camera.CFrame.LookVector * 6
            else
                --.. click UI up IMMEDIATELY — before the entrance bounce, not after.
                --.. Clicks landed while the egg is still bouncing in buffer into
                --.. ClickState.Count and cash in as soon as the rounds can play.
                local ClickState
                if Interactive then
                    ClickState = module.StartClickCatcher()
                end

                local Egg = Eggs:FindFirstChild(EggName):Clone()
                Egg.Parent = workspace.CurrentCamera

                for _,v in next, Egg:GetDescendants() do
                    if v:IsA("BasePart") then
                        v.CastShadow = false
                        v.CanCollide = false
                    end
                end

                tweenModelSize(Egg, .01, .1, "Linear", "Out")
                Egg:PivotTo((Camera.CFrame + Camera.CFrame.LookVector * 12))

                --.. interactive: a snappy 0.3s pop-in so an immediate click's shake
                --.. isn't stuck behind a full second of entrance (user report
                --.. 2026-08-10 "shake is delayed on click"); auto keeps the slow
                --.. cinematic bounce
                local EntranceTime = Interactive and .3 or 1
                local EntranceStyle = Interactive and Enum.EasingStyle.Back or Enum.EasingStyle.Bounce
                coroutine.wrap(function()
                    tweenModel(Egg, Egg:GetPivot() * CFrame.new(0, 0, 6), TweenInfo.new(EntranceTime, EntranceStyle, Enum.EasingDirection.Out))
                end)()
                tweenModelSize(Egg, EntranceTime, 10, Interactive and "Back" or "Bounce", "Out")

                EggCFrame = Egg:GetPivot()
                if not Interactive then
                    FastWait(.5/HatchSpeed)
                end

                --.. Interactive hatch (2026-08-10, user request): the egg no longer
                --.. shakes itself open. Clicks 1-3 each play one escalating shake
                --.. round and the 4th click cracks it. Auto hatch keeps the old
                --.. hands-free sequence (clicking would defeat AFK hatching);
                --.. Instant already skips this whole block. An idle player is
                --.. advanced one stage per CLICK_IDLE_TIMEOUT so the reveal always
                --.. finishes inside UiController's hatch watchdog budget.
                if not Interactive then
                    for RoundIndex, Round in ipairs(module.ShakeRounds) do
                        --.. riser under the FINAL shake round; stopped at reveal
                        if RoundIndex == #module.ShakeRounds then module.StartRiser() end
                        ShakeRound(Egg, EggCFrame, HatchSpeed, Round[1], Round[2], Round[3], true)
                    end
                else
                    --.. slow display spin while waiting; each shake freezes the
                    --.. spin and wobbles relative to the frozen angle
                    local Spin = module.StartEggSpin(Egg, EggCFrame)
                    for Stage, Round in ipairs(module.ShakeRounds) do
                        module.WaitForClicks(ClickState, Stage)
                        --.. riser under the FINAL shake round; stopped at reveal
                        if Stage == #module.ShakeRounds then module.StartRiser() end
                        --.. NO click cooldown (user request 2026-08-10): a newer click
                        --.. aborts the running shake mid-frame, and rounds a spam-clicker
                        --.. has already overtaken are skipped outright so the crack
                        --.. never waits on animation.
                        if ClickState.Count <= Stage then
                            Spin.Pause()
                            --.. HatchSpeed 1: click feel is constant; yaw goes in PostCF
                            --.. so the rock stays in the screen plane
                            ShakeRound(Egg, EggCFrame, 1, Round[1], Round[2], Round[3], false, Spin.YawCF(), function()
                                return ClickState.Count > Stage
                            end)
                            Spin.Resume()
                        end
                    end
                    module.WaitForClicks(ClickState, 4)
                    module.StopClickCatcher(ClickState)
                    --.. crack open from wherever the spin ended: the settle and the
                    --.. pet reveal below all key off EggCFrame
                    EggCFrame = Spin.Stop()
                    --.. the crack click gets the same burst the shakes get
                    ShakeSparkles(EggCFrame)
                end
                tweenModel(Egg, EggCFrame, TweenInfo.new(.05, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut, 0, false))
                --.. the 4th click must cut to the pet with no dead time (user
                --.. request 2026-08-10): blink-collapse for interactive, keep the
                --.. slow cinematic shrink for the hands-free auto reveal
                tweenModelSize(Egg, Interactive and .08 or .5, .01, "Back", "In")

                EggCFrame = Egg:GetPivot()
                Egg:Destroy()
            end

            local Burst = Assets.Particles.EggOpen:Clone()
            Burst.Parent = workspace.CurrentCamera
            Burst.CFrame = game.Workspace.CurrentCamera.CFrame + game.Workspace.CurrentCamera.CFrame.LookVector * 2

            do
                coroutine.wrap(function()
                    Burst.Particle.Enabled = true
                    wait(.1)
                    Burst.Particle.Enabled = false
                    FastWait(1)
                    Burst:Destroy()
                end)()
            end

            --.. persistent wrapper layer designed in StarterGui.EggRevealUI.SingleLayer
            local ScreenGui = Player:WaitForChild("PlayerGui"):WaitForChild("EggRevealUI"):WaitForChild("SingleLayer")
            local SingleUi = script.Single:Clone()
            SingleUi.Parent = ScreenGui

            ConfigureSingle(SingleUi, PetString[1], EggName, InfoTable.RarityText)
            TweenInSingle(SingleUi, false) --.. Change Text

            SoundController.PlayFX("Pet Reward")
            module.PlayRevealFX(PetString[1])
            local Pet = Pets:FindFirstChild(PetString[1]):Clone()
            --.. 2026-08-22: hand-modelled pets are ~6.6 studs tall (old meshes ~3)
            --.. and filled the screen at reveal; cap the DISPLAY clone's height.
            --.. Cap-only -- smaller legacy pets keep their size.
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
            Pet:PivotTo(EggCFrame * CFrame.fromEulerAnglesXYZ(0,math.rad(180),0) - Vector3.new(0,.7,0))

            local Spin

            Spin = RunService.RenderStepped:Connect(function()
                if Pet ~= nil and Pet.Parent ~= nil then
                    Pet:PivotTo(Pet:GetPivot() * CFrame.Angles(0,math.rad(-1),0))
                end
            end)

            coroutine.wrap(function()
                --.. spin through the whole hold AND the shrink (the destroyed-pet
                --.. guard above makes the overshoot safe) -- stopping earlier left
                --.. the model frozen mid-air, which read as a stuck image
                FastWait(3.1/HatchSpeed)

                Spin:Disconnect()
            end)()

            --.. card and pet leave TOGETHER: tween-out starts as the hold ends, so
            --.. both are gone at ~3.0 right when the HUD comes back (the old 1s
            --.. start left the bare pet floating alone for the back half of the hold)
            coroutine.wrap(function()
                FastWait(2.25/HatchSpeed)
                TweenInSingle(SingleUi, true)
                FastWait(.75/HatchSpeed)
                SingleUi:Destroy() -- the wrapper gui persists
            end)()

            FastWait(2.5/HatchSpeed) --.. main "look at your pet" hold (user-tuned: 1.5 too fast, 3 too long)

            tweenModelSize(Pet, .5, 0, "Back", "In")
            Pet:Destroy()

            FastWait(.5/HatchSpeed)

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
    end
end

--.. Click-to-hatch (2026-08-10). Shared with Triple, which requires these off
--.. this module (same pattern as ApplyChance). One shake "round" is one burst
--.. of side-to-side wobbles; the three rounds escalate exactly like the old
--.. automatic sequence did.
--.. One round per click, ~half a second, modeled frame-by-frame on the pet sim
--.. reference (2026-08-10): the egg swells toward the camera while rocking one
--.. way, shrinks back while rocking through to the other side, then lands
--.. upright — with a white flash + sparkle burst. {Roll deg, Peak scale, Duration}.
module.ShakeRounds = {
    {12, 1.15, .75};
    {14, 1.18, .75};
    {16, 1.22, .75};
}

local CLICK_IDLE_TIMEOUT = 15
local ClickPrompts = {
    [1] = "Click to open!";
    [2] = "Click again!";
    [3] = "Keep clicking!";
    [4] = "One more click!";
}

--.. One note per click, pitched up 2 semitones each click (1.00/1.12/1.26/1.41).
--.. Clones the authored Assets.Sounds.EggClick so spam clicks overlap cleanly
--.. instead of restarting one instance.
local function PlayClickSound(ClickNumber)
    local Template = game.ReplicatedStorage.Assets.Sounds:FindFirstChild("EggClick")
    local Sound
    if Template then
        Sound = Template:Clone()
    else
        Sound = Instance.new("Sound")
        Sound.SoundId = "rbxassetid://126409451844008"
        Sound.Volume = 0.5
    end
    Sound.PlaybackSpeed = 2 ^ ((ClickNumber - 1) * 2 / 12)
    Sound.Parent = workspace.CurrentCamera
    Sound:Play()
    Sound.Ended:Once(function() Sound:Destroy() end)
    task.delay(5, function()
        if Sound.Parent then Sound:Destroy() end
    end)
end

--.. PostCF: the frozen spin yaw, applied AFTER the roll so the rock always
--.. happens in the screen plane. Without it the roll axis turns with the spin
--.. and at ~90 degrees of yaw the rock points into the screen — invisible on
--.. an egg silhouette (the "shaking disappeared" bug, 2026-08-10). Interactive
--.. call sites also pass HatchSpeed = 1: a click response has a fixed feel,
--.. FastHatch only speeds up the automatic reveals.
--.. ShouldAbort: polled every frame; returning true cuts the round short (the
--.. egg still resets to its base frame/scale). Lets a newer click interrupt the
--.. running shake so there is zero click cooldown.
function ShakeRound(Egg, EggCFrame, HatchSpeed, Angle, PeakScale, Duration, PlaySound, PostCF, ShouldAbort)
    PostCF = PostCF or CFrame.identity
    --.. Interactive rounds stay SILENT here: the click handler owns the pop so
    --.. it's exactly one sound per click (three Triple eggs shake per click but
    --.. must not stack three pops). Auto rounds pass PlaySound = true.
    if PlaySound then
        SoundController.PlayFX("EggPop")
    end
    ShakeSparkles(EggCFrame)

    --.. the reference's three "frames" as one continuous curve: rock to +Angle
    --.. with a Back punch while the egg swells to PeakScale, swing through to
    --.. -0.8*Angle as it shrinks back, then settle upright at exactly the base
    --.. frame so the display spin resumes without a snap.
    local BaseScale = Egg:GetScale()
    local T = 0
    local Length = Duration / HatchSpeed
    while T < 1 and Egg.Parent and Egg.PrimaryPart do
        if ShouldAbort and ShouldAbort() then break end
        local Delta = RunService.Heartbeat:Wait()
        T = math.min(T + Delta / Length, 1)

        local Roll
        --.. equal-strength left AND right rock (user report 2026-08-10: the right
        --.. swing was 0.8x with a soft ease and read as left-only): punch to
        --.. +Angle, punch through to a FULL -Angle with the same Back snap so it
        --.. dwells there just as long, then return to center.
        if T < .28 then
            Roll = Angle * TweenService:GetValue(T / .28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        elseif T < .6 then
            Roll = Angle - 2 * Angle * TweenService:GetValue((T - .28) / .32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        else
            Roll = -Angle * (1 - TweenService:GetValue((T - .6) / .4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
        end
        local Swell = 1 + (PeakScale - 1) * math.sin(T * math.pi)

        Egg:ScaleTo(BaseScale * Swell)
        Egg:PivotTo(EggCFrame * CFrame.fromEulerAnglesXYZ(0, 0, math.rad(Roll)) * PostCF)
    end

    if Egg.Parent then
        Egg:ScaleTo(BaseScale)
        if Egg.PrimaryPart then
            Egg:PivotTo(EggCFrame * PostCF)
        end
    end
end
module.ShakeRound = ShakeRound

--.. A burst of white sparkle glints around the egg per shake (the little
--.. diamond stars in the reference frames).
function ShakeSparkles(BaseCFrame)
    local Camera = workspace.CurrentCamera
    if not Camera then return end

    local Holder = Instance.new("Part")
    Holder.Name = "ShakeSparkles"
    Holder.Transparency = 1
    Holder.CastShadow = false
    Holder.CanCollide = false
    Holder.CanQuery = false
    Holder.CanTouch = false
    Holder.Anchored = true
    Holder.Size = Vector3.new(1, 1, 1)
    Holder.CFrame = BaseCFrame
    Holder.Parent = Camera

    local Emitter = Instance.new("ParticleEmitter")
    Emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    Emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
    Emitter.LightEmission = 1
    Emitter.LightInfluence = 0
    Emitter.Speed = NumberRange.new(7, 12)
    Emitter.Lifetime = NumberRange.new(.3, .55)
    Emitter.SpreadAngle = Vector2.new(180, 180)
    Emitter.Rotation = NumberRange.new(0, 360)
    Emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1);
        NumberSequenceKeypoint.new(1, 0);
    })
    Emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0);
        NumberSequenceKeypoint.new(.7, 0);
        NumberSequenceKeypoint.new(1, 1);
    })
    Emitter.Enabled = false
    Emitter.Parent = Holder

    Emitter:Emit(24)
    task.delay(1, function() Holder:Destroy() end)
end
module.ShakeSparkles = ShakeSparkles

--.. Slow display spin while the egg sits in front of the camera waiting for
--.. clicks. Shake rounds pass Frame() as their base so the wobble is relative
--.. to the frozen spin angle and the yaw never snaps.
local SPIN_SPEED = math.rad(45)
function module.StartEggSpin(Egg, BaseCFrame)
    local Angle = 0
    local Paused = false
    local Connection = RunService.Heartbeat:Connect(function(dt)
        if Paused then return end
        if not Egg.Parent or not Egg.PrimaryPart then return end
        Angle = (Angle + dt * SPIN_SPEED) % (math.pi * 2)
        Egg:PivotTo(BaseCFrame * CFrame.Angles(0, Angle, 0))
    end)

    local Spin = {}
    function Spin.Frame()
        return BaseCFrame * CFrame.Angles(0, Angle, 0)
    end
    function Spin.YawCF()
        return CFrame.Angles(0, Angle, 0)
    end
    function Spin.Pause() Paused = true end
    function Spin.Resume() Paused = false end
    function Spin.Stop()
        Connection:Disconnect()
        return Spin.Frame()
    end
    return Spin
end

--.. The full-screen catcher + "Click to open!" prompt are authored in
--.. StarterGui.EggRevealUI.ClickCatcher (EggRevealUI is hatch-UI-exempt, so it
--.. stays visible while every other layer is hidden). UiController's
--.. RestoreHatchState also force-hides it on any error/watchdog path.
function module.StartClickCatcher()
    local State = {Count = 0}
    local PlayerGui = Player:FindFirstChild("PlayerGui")
    local Wrapper = PlayerGui and PlayerGui:FindFirstChild("EggRevealUI")
    local Catcher = Wrapper and Wrapper:FindFirstChild("ClickCatcher")
    if not Catcher then
        --.. authored button missing: WaitForClicks just times out per stage,
        --.. degrading to a slow self-opening egg instead of a softlock
        warn("[EggHatch] ClickCatcher UI missing - egg will open itself")
        return State
    end
    State.Catcher = Catcher
    State.Prompt = Catcher:FindFirstChild("Prompt")
    if State.Prompt then State.Prompt.Text = ClickPrompts[1] end
    Catcher.Visible = true
    State.Connection = Catcher.MouseButton1Click:Connect(function()
        State.Count += 1
        --.. one rising note per click, EXCEPT the 4th/crack click (user request
        --.. 2026-08-10) — the reveal's own Pet Reward audio carries that moment
        if State.Count < 4 then
            PlayClickSound(State.Count)
        end
        if State.Prompt then
            State.Prompt.Text = ClickPrompts[math.min(State.Count + 1, 4)]
        end
    end)
    return State
end

--.. Blocks until the player has clicked Target times in total. Clicks landed
--.. mid-shake are buffered in Count, so spam-clicking chains the rounds
--.. back to back. Advances by itself after CLICK_IDLE_TIMEOUT idle seconds.
function module.WaitForClicks(State, Target)
    local Deadline = os.clock() + CLICK_IDLE_TIMEOUT
    while State.Count < Target do
        if os.clock() > Deadline then
            State.Count = Target
            break
        end
        RunService.Heartbeat:Wait()
    end
end

function module.StopClickCatcher(State)
    if State.Connection then
        State.Connection:Disconnect()
        State.Connection = nil
    end
    if State.Catcher then
        State.Catcher.Visible = false
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

function ConfigureSingle(Single, Pet, EggName, RarityText)
    local PetName = Single.PetName
    local PetRarity = Single.PetRarity
    local PetUnlocked = Single.PetUnlocked


    PetName.Text = string.upper(require(game.ReplicatedStorage.Modules.PetDisplayNames).Get(Pet))
    RarityController.GetColors(Pet, PetRarity)
    if type(RarityText) == "string" and RarityText ~= "" then
        PetRarity.Text = RarityText
    end
    ApplyChance(Single, EggName, Pet) -- "[1 in N]" corner tag
end
function TweenInSingle(Single, Remove)
    if Remove then
        local tween = TweenService:Create(Single, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0,0,0,0); Position = UDim2.new(.5,0,.8,0)})
        tween:Play()
    else
        local tween = TweenService:Create(Single, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(1,0,1,0)})
        tween:Play()
    end
end

return module
