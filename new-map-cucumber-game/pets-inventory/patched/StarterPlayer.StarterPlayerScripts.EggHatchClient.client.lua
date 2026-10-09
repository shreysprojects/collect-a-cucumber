--[[
	EggHatchClient  (LocalScript, StarterPlayerScripts)
	The Zombie Cucumber Game's click-to-hatch egg reveal (EggController.UiController.Single,
	interactive path), ported 2026-09-07 for the plot eggs of this place.

	  * PetHatchService fires ReplicatedStorage.Remotes.PetHatch "Begin" with the egg (EggName /
	    Scale / Material / Mutations) and the pet (Pet / PetDisplayName / Rarity / Chance).
	  * Every other UI layer + the core GUI are hidden, the camera is frozen (Scriptable, same
	    CFrame) and the egg -- rebuilt from ReplicatedStorage.PlaceableModels with the placed
	    egg's size + look -- pops in 6 studs in front of the camera and slowly spins.
	  * StarterGui.EggRevealUI.ClickCatcher (the zombie's authored full-screen button + "Click to
	    open!" prompt) counts clicks: clicks 1-3 each play one escalating shake round
	    (SHAKE_ROUNDS: roll / swell / duration, white sparkle burst, rising click note), the 4th
	    click cracks the egg: collapse, EggOpen-style burst, "Pet Reward" + rarity stinger + screen
	    glow, the pet model (capped PET_REVEAL_MAX_HEIGHT) spinning where the egg was, and the
	    reveal card (EggRevealUI.SingleTemplate: PetName with the rarity gradient, PetRarity,
	    "[1 in N]" PetChance). An idle player is advanced one stage per CLICK_IDLE_TIMEOUT.
	  * hold, card + pet leave together, camera + UI restored, then "Opened" is sent so the server
	    spawns the roaming pet on the plot. A watchdog restores the screen if anything dies
	    mid-reveal (the zombie's "stuck camera / no HUD" lesson).
	  * PET SYSTEM (2026-09-22): the pet is already OWNED when "Begin" arrives (PetHatchService
	    commits the hatch first), so the reveal is presentation only. Every acknowledgment (busy,
	    watchdog, normal finish) sends "Opened" WITH the Begin's Token, which finishes only that
	    presentation; the watchdog bumps the local Token so the late finish cannot ack twice. The
	    revealed pet wears the egg's inherited material / mutations (CucumberMutations.ApplyLook),
	    and the card fills the builder-authored PetStats line (green $X/s + ability, from
	    PetStats / PetBalance) and PetTraits line (material / mutation words in their colours) -
	    both hidden when absent. After a successful reveal a toast says where the pet went when it
	    is not active (Notify.Info: PetBalance.TEXT.LockedHatchNotice / ReserveNotice).
	  * Studio test hook: RevealUi:SetAttribute("DevClick", n) counts as a click.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Catalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetsCatalog"))
local CucumberMutations = require(ReplicatedStorage.Modules:WaitForChild("CucumberMutations"))
local SoundController = require(ReplicatedStorage.Modules:WaitForChild("SoundController"))
local NumberAbbrev = require(ReplicatedStorage.Modules:WaitForChild("NumberAbbrev"))
local Notify = require(ReplicatedStorage.Modules:WaitForChild("Notify"))

--.. 2026-09-22: the pet-system modules are optional until installed (the card then hides its stat line)
local function LazyModule(name)
	local cache
	return function()
		if cache then return cache end
		local module = ReplicatedStorage.Modules:FindFirstChild(name)
		if not module then return nil end
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then cache = result end
		return cache
	end
end
local GetPetStats = LazyModule("PetStats")
local GetPetBalance = LazyModule("PetBalance")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local RevealUi = PlayerGui:WaitForChild("EggRevealUI")
local Catcher = RevealUi:WaitForChild("ClickCatcher")
local Prompt = Catcher:WaitForChild("Prompt")
local SingleLayer = RevealUi:WaitForChild("SingleLayer")
local SingleTemplate = RevealUi:WaitForChild("SingleTemplate")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PetHatch = Remotes:WaitForChild("PetHatch")
local Sounds = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds")

--..Config (zombie Single values)..--
local EGG_ENTER_FROM = 12 -- studs in front of the camera where the egg pops in
local EGG_DISTANCE = 6 -- studs in front of the camera where it sits
local ENTRANCE_TIME = 0.3
local EGG_DISPLAY_MAX_HEIGHT = 5.5 -- studs: a 4x placed egg would fill the screen
local SHAKE_ROUNDS = {{12, 1.15, 0.75}, {14, 1.18, 0.75}, {16, 1.22, 0.75}} -- roll deg, peak scale, seconds
local CLICK_IDLE_TIMEOUT = 15
local SPIN_SPEED = math.rad(45) -- display spin while waiting for clicks
local PET_REVEAL_MAX_HEIGHT = 3.4
local PET_SPIN_SPEED = math.rad(60)
local HOLD = 2.5 -- "look at your pet" hold
local CARD_OUT_AT = 2.25
local WATCHDOG = 95 -- seconds: restore everything if the reveal never finished
local ClickPrompts = {"Click to open!", "Click again!", "Keep clicking!", "One more click!"}
local CASH_HEX = "#41EB14" -- 65, 235, 20: the overhead cash green (2026-09-22)
local SEPARATOR = "  \u{00B7}  " -- between the parts of a card line

--..State..--
local Camera = workspace.CurrentCamera
local Busy = false
local Token = 0
local LayerStates, CoreStates
local ActiveRiser

--..Helpers..--
local function Step(duration, style, direction, fn)
	local t = 0
	while t < 1 do
		local dt = RunService.Heartbeat:Wait()
		t = math.min(t + dt / duration, 1)
		fn(TweenService:GetValue(t, style, direction))
	end
end

local function SafeScale(model, scale)
	pcall(model.ScaleTo, model, math.max(0.01, scale))
end

local function PlayClickSound(n)
	local template = Sounds:FindFirstChild("EggClick")
	local sound
	if template then
		sound = template:Clone()
	else
		sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://126409451844008"
		sound.Volume = 0.5
	end
	sound.PlaybackSpeed = 2 ^ ((n - 1) * 2 / 12) -- +2 semitones per click
	sound.Parent = Camera
	sound:Play()
	sound.Ended:Once(function() sound:Destroy() end)
	task.delay(5, function() if sound.Parent then sound:Destroy() end end)
end

--.. a burst of white sparkle glints around the egg per shake (zombie ShakeSparkles)
local function Sparkles(cf)
	local holder = Instance.new("Part")
	holder.Name = "ShakeSparkles"
	holder.Transparency = 1
	holder.CastShadow = false
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Anchored = true
	holder.Size = Vector3.new(1, 1, 1)
	holder.CFrame = cf
	holder.Parent = Camera
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.new(1, 1, 1))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Speed = NumberRange.new(7, 12)
	e.Lifetime = NumberRange.new(0.3, 0.55)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)})
	e.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1)})
	e.Enabled = false
	e.Parent = holder
	e:Emit(24)
	task.delay(1, function() holder:Destroy() end)
end

--.. the zombie Assets.Particles.EggOpen burst, rebuilt in code
local function Burst(cf)
	local holder = Instance.new("Part")
	holder.Name = "EggOpen"
	holder.Transparency = 1
	holder.CastShadow = false
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Anchored = true
	holder.Size = Vector3.new(1, 1, 1)
	holder.CFrame = cf
	holder.Parent = Camera
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxassetid://7661011084"
	e.Color = ColorSequence.new(Color3.new(1, 1, 1))
	e.LightEmission = 0.1
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(3, 5)
	e.SpreadAngle = Vector2.new(360, 360)
	e.Rotation = NumberRange.new(0, 359)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.Acceleration = Vector3.new(0, 1, 0)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0);
		NumberSequenceKeypoint.new(0.03, 0.19);
		NumberSequenceKeypoint.new(0.06, 0.31);
		NumberSequenceKeypoint.new(0.34, 0.5);
		NumberSequenceKeypoint.new(0.98, 0.38);
		NumberSequenceKeypoint.new(1, 0);
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1);
		NumberSequenceKeypoint.new(0.06, 0.06);
		NumberSequenceKeypoint.new(1, 1);
	})
	e.Enabled = false
	e.Parent = holder
	e:Emit(60)
	task.delay(3, function() holder:Destroy() end)
end

--.. one shake round (zombie ShakeRound): rock to +angle with a Back punch while swelling, swing
--.. through to -angle, settle upright; aborts when a newer click arrives
local function ShakeRound(egg, baseCF, angle, peak, duration, postCF, shouldAbort)
	Sparkles(baseCF)
	local baseScale = egg:GetScale()
	local t = 0
	while t < 1 and egg.Parent and egg.PrimaryPart do
		if shouldAbort and shouldAbort() then break end
		local dt = RunService.Heartbeat:Wait()
		t = math.min(t + dt / duration, 1)
		local roll
		if t < 0.28 then
			roll = angle * TweenService:GetValue(t / 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		elseif t < 0.6 then
			roll = angle - 2 * angle * TweenService:GetValue((t - 0.28) / 0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		else
			roll = -angle * (1 - TweenService:GetValue((t - 0.6) / 0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
		end
		local swell = 1 + (peak - 1) * math.sin(t * math.pi)
		SafeScale(egg, baseScale * swell)
		egg:PivotTo(baseCF * CFrame.fromEulerAnglesXYZ(0, 0, math.rad(roll)) * postCF)
	end
	if egg.Parent then
		SafeScale(egg, baseScale)
		if egg.PrimaryPart then egg:PivotTo(baseCF * postCF) end
	end
end

--.. slow display spin while the egg waits for clicks (zombie StartEggSpin)
local function StartSpin(egg, baseCF)
	local angle, paused = 0, false
	local conn = RunService.Heartbeat:Connect(function(dt)
		if paused or not egg.Parent or not egg.PrimaryPart then return end
		angle = (angle + dt * SPIN_SPEED) % (math.pi * 2)
		egg:PivotTo(baseCF * CFrame.Angles(0, angle, 0))
	end)
	local spin = {}
	function spin.Frame() return baseCF * CFrame.Angles(0, angle, 0) end
	function spin.YawCF() return CFrame.Angles(0, angle, 0) end
	function spin.Pause() paused = true end
	function spin.Resume() paused = false end
	function spin.Stop() conn:Disconnect() return spin.Frame() end
	return spin
end

local function StartCatcher()
	local state = {Count = 0, Connections = {}}
	Prompt.Text = ClickPrompts[1]
	Catcher.Visible = true
	local function click()
		state.Count += 1
		if state.Count < 4 then PlayClickSound(state.Count) end -- the crack click's sound is the Pet Reward itself
		Prompt.Text = ClickPrompts[math.min(state.Count + 1, 4)]
	end
	table.insert(state.Connections, Catcher.Activated:Connect(click))
	if RunService:IsStudio() then
		table.insert(state.Connections, RevealUi:GetAttributeChangedSignal("DevClick"):Connect(function()
			if Catcher.Visible then click() end
		end))
	end
	return state
end

local function WaitForClicks(state, target)
	local deadline = os.clock() + CLICK_IDLE_TIMEOUT
	while state.Count < target do
		if os.clock() > deadline then state.Count = target break end
		RunService.Heartbeat:Wait()
	end
end

local function StopCatcher(state)
	for _, c in ipairs(state.Connections) do c:Disconnect() end
	table.clear(state.Connections)
	Catcher.Visible = false
end

--.. hide every other UI layer + the core GUI for the reveal, remembering each one's state
local function HideLayer(layer)
	if not LayerStates or not layer:IsA("LayerCollector") or layer == RevealUi then return end
	if LayerStates[layer] == nil then LayerStates[layer] = layer.Enabled end
	layer.Enabled = false
end

local function HideUi()
	if not LayerStates then
		LayerStates = {}
		for _, layer in ipairs(PlayerGui:GetChildren()) do HideLayer(layer) end
	end
	if not CoreStates then
		CoreStates = {}
		for _, coreType in ipairs(Enum.CoreGuiType:GetEnumItems()) do
			if coreType ~= Enum.CoreGuiType.All then
				local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, coreType)
				if ok then CoreStates[coreType] = enabled end
			end
		end
	end
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
end

PlayerGui.ChildAdded:Connect(function(layer)
	if Busy then HideLayer(layer) end
end)

local function RestoreUi()
	if LayerStates then
		for layer, enabled in pairs(LayerStates) do
			if layer.Parent then layer.Enabled = enabled end
		end
		LayerStates = nil
	end
	if CoreStates then
		for coreType, enabled in pairs(CoreStates) do
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreType, enabled)
		end
		CoreStates = nil
	end
end

local function StopRiser()
	local riser = ActiveRiser
	ActiveRiser = nil
	if riser then pcall(function() riser:Stop() riser:Destroy() end) end
end

--.. rarity-tiered stinger + full-screen glow in the rarity colour (zombie PlayRevealFX)
local function RevealFX(rarity)
	StopRiser()
	if rarity == "Rare" then
		SoundController.PlayFX("Magic Shimmer", {Volume = 0.4, Key = "RarityStinger", MinInterval = 1.5})
	elseif rarity == "Epic" or rarity == "Legendary" then
		SoundController.PlayFX("Magic Shimmer", {Volume = 0.55, Speed = 0.85, Key = "RarityStinger", MinInterval = 1.5})
	elseif rarity and rarity ~= "Common" and rarity ~= "Uncommon" then
		SoundController.PlayFX("Drama Sting", {Volume = 0.6, Key = "RarityStinger", MinInterval = 1.5})
		SoundController.PlayFX("Thunder", {Volume = 0.25, Speed = 1.2, Key = "RarityStingerThunder", MinInterval = 1.5})
	end
	local color = Catalog.RARITY_GLOW[rarity]
	if not color then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchRevealGlow"
	gui.DisplayOrder = 9999
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	local glow = Instance.new("Frame")
	glow.BackgroundColor3 = color
	glow.BorderSizePixel = 0
	glow.Size = UDim2.fromScale(1, 1)
	glow.BackgroundTransparency = 0.55
	glow.Parent = gui
	gui.Parent = PlayerGui
	TweenService:Create(glow, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	task.delay(0.6, function() gui:Destroy() end)
end

--.. the egg in front of the camera: the placeable template with the placed egg's size + look
local function BuildEgg(info)
	local models = ReplicatedStorage:FindFirstChild("PlaceableModels") or ReplicatedStorage:WaitForChild("PlaceableModels", 10)
	local template = models and (models:FindFirstChild(tostring(info.EggName) .. " Egg") or models:WaitForChild(tostring(info.EggName) .. " Egg", 5))
	local egg
	if template then
		egg = template:Clone()
		for _, d in ipairs(egg:GetDescendants()) do
			if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("LuaSourceContainer") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.CastShadow = false
			end
		end
		local scale = math.clamp(tonumber(info.Scale) or 1, 0.5, 5)
		local _, size = egg:GetBoundingBox()
		if size.Y * scale > EGG_DISPLAY_MAX_HEIGHT then scale = EGG_DISPLAY_MAX_HEIGHT / size.Y end
		if math.abs(scale - 1) > 1e-3 then SafeScale(egg, egg:GetScale() * scale) end
		pcall(CucumberMutations.ApplyLook, egg, info.Material, info.Mutations)
	else
		warn("[EggHatchClient] no placeable model for " .. tostring(info.EggName) .. " - plain egg")
		egg = Instance.new("Model")
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(3.6, 4.5, 3.6)
		ball.Color = Color3.fromRGB(240, 235, 220)
		ball.Anchored = true
		ball.CanCollide = false
		ball.CastShadow = false
		ball.Parent = egg
		egg.PrimaryPart = ball
	end
	egg.Name = "HatchEgg"
	return egg
end

local function BuildPet(petName, cf, material, mutations, kg)
	local template = Catalog.ModelOf(petName)
	if not template then return nil end
	local pet = template:Clone()
	--.. SIZE (2026-09-23): a pet from a heavier egg is a little bigger (PetStats.SizeScale; then the reveal height cap)
	local PetStats = GetPetStats()
	if PetStats then
		local okSize, sizeScale = pcall(PetStats.SizeScale, kg)
		if okSize and type(sizeScale) == "number" and sizeScale > 1 then SafeScale(pet, pet:GetScale() * sizeScale) end
	end
	local _, size = pet:GetBoundingBox()
	if size.Y > PET_REVEAL_MAX_HEIGHT then SafeScale(pet, pet:GetScale() * (PET_REVEAL_MAX_HEIGHT / size.Y)) end
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	pet.Parent = Camera
	pet:PivotTo(cf)
	--.. 2026-09-22: the pet inherits the egg's material / mutations (after parenting, so a PRISMATIC
	--.. colour loop runs while the reveal shows it and stops when the pet is destroyed)
	if type(material) ~= "string" or material == "" then material = nil end
	pcall(CucumberMutations.ApplyLook, pet, material, type(mutations) == "string" and mutations or "")
	return pet
end

--..Card lines (2026-09-22)..--
local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function Escape(text)
	return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

--.. "Lucky Harvest x1.5 for 90s  -  1% / min"; a fighter reads "Fighter: +15% damage". Every ability
--.. number comes from PetBalance through the PetStats text helpers
local function AbilityLine(stats, PetStats, PetBalance)
	local ability = stats.Ability
	local abilities = type(PetBalance.ABILITIES) == "table" and PetBalance.ABILITIES or {}
	if stats.Fighter == true or ability == "None" then
		local row = abilities.None
		local text = PetStats.AbilityEffect("None")
		if type(text) ~= "string" or text == "" then return nil end
		return type(row) == "table" and typeof(row.Color) == "Color3" and CucumberMutations.Font(text, row.Color, true) or Escape(text)
	end
	local row = abilities[ability]
	if type(row) ~= "table" or type(row.DisplayName) ~= "string" then return nil end
	local line = typeof(row.Color) == "Color3" and CucumberMutations.Font(row.DisplayName, row.Color, true) or Escape(row.DisplayName)
	local guardSeconds = Finite(stats.AbilityDuration) and math.floor(stats.AbilityDuration + 0.5) or nil
	local short = PetStats.AbilityShort(ability, guardSeconds)
	if type(short) == "string" and short ~= "" then line ..= " " .. Escape(short) end
	if Finite(stats.AbilityChance) and stats.AbilityChance > 0 then
		line ..= SEPARATOR .. ("%g%% / min"):format(math.floor(stats.AbilityChance * 1000 + 0.5) / 10)
	end
	return line
end

--.. PetStats label: green cash/sec, then the ability line (nil = hide the label)
local function StatsText(stats)
	local PetStats, PetBalance = GetPetStats(), GetPetBalance()
	if type(stats) ~= "table" or not (PetStats and PetBalance) then return nil end
	local income = Finite(stats.Income) and math.max(stats.Income, 0) or 0
	local text = ('<font color="%s">$%s/s</font>'):format(CASH_HEX, NumberAbbrev.Abbrev(income))
	local ok, ability = pcall(AbilityLine, stats, PetStats, PetBalance)
	if ok and type(ability) == "string" and ability ~= "" then text ..= SEPARATOR .. ability end
	return text
end

--.. PetTraits label: the inherited material + mutation words in their colours (nil = a normal egg)
local function TraitsText(material, mutations)
	local words = {}
	if type(material) == "string" and material ~= "" then
		local c = CucumberMutations.ColorOf(material)
		table.insert(words, c and CucumberMutations.Font(material, c, true) or Escape(material))
	end
	for _, name in ipairs(CucumberMutations.Parse(type(mutations) == "string" and mutations or "")) do
		local c = CucumberMutations.ColorOf(name)
		table.insert(words, c and CucumberMutations.Font(name, c, true) or Escape(name))
	end
	if #words == 0 then return nil end
	return table.concat(words, SEPARATOR)
end

local function BuildCard(info)
	local card = SingleTemplate:Clone()
	card.Name = "Single"
	card.Size = UDim2.new(0, 0, 0, 0)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.Visible = true
	local rarity = info.Rarity or "Common"
	local gradient = Catalog.RARITY_GRADIENTS[rarity] or Catalog.RARITY_GRADIENTS.Common
	local nameLabel = card:FindFirstChild("PetName")
	if nameLabel then
		nameLabel.Text = string.upper(info.PetDisplayName or info.Pet or "?")
		local g = nameLabel:FindFirstChild("UIGradient")
		if g then g.Color = gradient end
	end
	local rarityLabel = card:FindFirstChild("PetRarity")
	if rarityLabel then
		rarityLabel.Text = string.upper(rarity)
		local g = rarityLabel:FindFirstChild("UIGradient")
		if g then g.Color = gradient end
	end
	local unlocked = card:FindFirstChild("PetUnlocked")
	if unlocked then unlocked.Visible = false end -- needs saved discovery data; none yet
	local chance = card:FindFirstChild("PetChance")
	if chance then
		chance.Visible = info.Chance ~= nil
		if info.Chance then chance.Text = info.Chance end
	end
	--.. 2026-09-23 (user: "just show pet - pet name/rarity and chance of getting pet, dont show all that other
	--.. info"): the cash/sec + ability and traits lines of 2026-09-22 stay hidden (StatsText / TraitsText kept
	--.. for the info frame's sake)
	for _, name in ipairs({"PetStats", "PetTraits"}) do
		local label = card:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			label.Text = ""
			label.Visible = false
		end
	end
	card.Parent = SingleLayer
	TweenService:Create(card, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 1, 0)}):Play()
	return card
end

local function CardOut(card)
	TweenService:Create(card, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, 0.8, 0)}):Play()
	task.delay(1, function() card:Destroy() end)
end

--..The reveal..--
local function Restore(prevCameraType)
	pcall(function()
		Catcher.Visible = false
		if Camera.CameraType == Enum.CameraType.Scriptable then
			Camera.CameraType = prevCameraType or Enum.CameraType.Custom
		end
		for _, name in ipairs({"HatchEgg", "HatchPet", "ShakeSparkles", "EggOpen"}) do
			for _, c in ipairs(Camera:GetChildren()) do
				if c.Name == name then c:Destroy() end
			end
		end
		for _, c in ipairs(SingleLayer:GetChildren()) do c:Destroy() end
	end)
	StopRiser()
	RestoreUi()
end

local function Reveal(info)
	local prevCameraType = Camera.CameraType
	HideUi()
	Camera.CameraType = Enum.CameraType.Scriptable

	local state = StartCatcher()
	local egg = BuildEgg(info)
	local baseScale = egg:GetScale()
	SafeScale(egg, baseScale * 0.1)
	local camCF = Camera.CFrame
	local startCF = camCF + camCF.LookVector * EGG_ENTER_FROM
	local endCF = camCF + camCF.LookVector * EGG_DISTANCE
	egg:PivotTo(startCF)
	egg.Parent = Camera
	Step(ENTRANCE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
		egg:PivotTo(startCF:Lerp(endCF, a))
		SafeScale(egg, baseScale * (0.1 + 0.9 * a))
	end)
	SafeScale(egg, baseScale)
	local eggCF = endCF

	--.. clicks 1-3: one escalating shake round each (a newer click aborts the running one;
	--.. rounds a spam-clicker has overtaken are skipped)
	local spin = StartSpin(egg, eggCF)
	for stage, round in ipairs(SHAKE_ROUNDS) do
		WaitForClicks(state, stage)
		if stage == #SHAKE_ROUNDS and not ActiveRiser then
			ActiveRiser = SoundController.PlayFX("Riser", {Volume = 0.4, Key = "HatchRiser", MinInterval = 1})
		end
		if state.Count <= stage then
			spin.Pause()
			ShakeRound(egg, eggCF, round[1], round[2], round[3], spin.YawCF(), function() return state.Count > stage end)
			spin.Resume()
		end
	end
	WaitForClicks(state, 4)
	StopCatcher(state)
	eggCF = spin.Stop()
	Sparkles(eggCF)

	--.. crack: blink-collapse, burst, reward
	Step(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.In, function(a)
		SafeScale(egg, baseScale * (1 - 0.99 * math.clamp(a, 0, 1)))
	end)
	egg:Destroy()
	Burst(Camera.CFrame + Camera.CFrame.LookVector * 2)

	local card = BuildCard(info)
	SoundController.PlayFX("Pet Reward")
	RevealFX(info.Rarity)
	local pet = BuildPet(info.Pet, eggCF * CFrame.Angles(0, math.pi, 0) - Vector3.new(0, 0.7, 0), info.Material, info.Mutations, info.Kg)
	if pet then pet.Name = "HatchPet" end
	local spinConn = RunService.Heartbeat:Connect(function(dt)
		if pet and pet.Parent and pet.PrimaryPart then
			pet:PivotTo(pet:GetPivot() * CFrame.Angles(0, -PET_SPIN_SPEED * dt, 0))
		end
	end)
	task.delay(CARD_OUT_AT, function() if card.Parent then CardOut(card) end end)
	task.wait(HOLD)
	if pet then
		local petScale = pet:GetScale()
		Step(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In, function(a)
			SafeScale(pet, petScale * (1 - math.clamp(a, 0, 1)))
		end)
		pet:Destroy()
	end
	spinConn:Disconnect()
	task.wait(0.5)
	Restore(prevCameraType)
end

PetHatch.OnClientEvent:Connect(function(action, info)
	if action ~= "Begin" or type(info) ~= "table" then return end
	--.. 2026-09-22: every acknowledgment carries this reveal's server token (it finishes only that presentation)
	local token = type(info.Token) == "string" and info.Token or nil
	if Busy then
		warn("[EggHatchClient] a hatch is already running - pet spawns without a reveal")
		PetHatch:FireServer("Opened", token)
		return
	end
	Busy = true
	Token += 1
	local myToken = Token
	local prevCameraType = Camera.CameraType
	task.delay(WATCHDOG, function()
		if Busy and Token == myToken then
			warn("[EggHatchClient] reveal never finished - restoring camera and HUD")
			Restore(prevCameraType)
			Busy = false
			Token += 1 -- 2026-09-22: the late finish below must not acknowledge a second time
			PetHatch:FireServer("Opened", token)
		end
	end)
	local ok, err = pcall(Reveal, info)
	if not ok then
		warn("[EggHatchClient] " .. tostring(err))
		Restore(prevCameraType)
	end
	if Token == myToken then
		Busy = false
		PetHatch:FireServer("Opened", token)
		--.. 2026-09-22: where the new pet went when it is not active - after the Busy window, so the
		--.. toast layer is no longer hidden by the reveal
		if ok then
			local PetBalance = GetPetBalance()
			local texts = PetBalance and type(PetBalance.TEXT) == "table" and PetBalance.TEXT or {}
			if info.AutoEquipAfterCombat == true and type(texts.LockedHatchNotice) == "string" then
				Notify.Info(texts.LockedHatchNotice)
			elseif info.Reserve == true and type(texts.ReserveNotice) == "string" then
				Notify.Info(texts.ReserveNotice)
			end
		end
	end
end)
