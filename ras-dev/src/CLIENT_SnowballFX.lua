--[[---------------------------------------DESCRIPTION------------------------------------------
	Snowball flight feel + effects.

	Owner client (the player riding the ball, network owner of its physics):
	  * lift + glide forces while airborne so jumps float,
	  * a random air trick per flight (glide, backspin, barrel roll, corkscrew, tumble),
	  * clean landings (rolling spin restored, sideways drift removed, camera kick),
	  * steering only on the ground (FLIGHT.Wander; takeoff caps the sideways speed),
	  * off the map (over an edge, below the floor): back onto the last good patch of
	    track at part speed instead of the ride ending (FLIGHT.Recover),
	  * smash detection: rolling through a MountainProp fades it locally right away
	    and asks the server (SmashProp) to fade it for everyone.

	Every client, for every ball in workspace.ActiveSnowballs:
	  * snow spray + ground trail while rolling, wind streaks while flying,
	  * landing bursts, crash debris, thud / crash / whoosh sounds,
	  * fade-out of any prop whose Smashed attribute turns on.

	Hooked from ClientMain (StartSnowballFX) and CLIENT_Snowball (StartAirPhysics /
	StopAirPhysics / GetCameraKick).

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local launchCatalog = require(ReplicatedStorage.Assets.Modules.Shared.LaunchPropCatalog)
local launchMath = require(ReplicatedStorage.Assets.Modules.Shared.LaunchPropMath)
local FLIGHT = mountainConfig.FLIGHT
local COAST = mountainConfig.COAST or {}
local SMASH = mountainConfig.SMASH
local playerProgress = require(ReplicatedStorage.Assets.Modules.Shared.PlayerProgress)()
local COMBO_COLOR = Color3.fromRGB(255, 181, 38)
local HUDLayout = require(ReplicatedStorage.Assets.Modules.Client.UI.HUDLayout)
local SOUNDS = mountainConfig.SOUNDS
local Audio = require(ReplicatedStorage.Assets.Modules.Client.Audio)
local PROPS = mountainConfig.PROPS

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local api = {}

local balls = {} -- [snowball model] = state
local loopConnection = nil
local fxFolder = nil
local fading = setmetatable({}, { __mode = "k" })

local function getVars(self)
	return self and self.Variables
end

local function getRoot(snowball)
	if snowball:IsA("BasePart") then
		return snowball
	end
	if snowball:IsA("Model") then
		return snowball.PrimaryPart or snowball:FindFirstChild("BallCollision") or snowball:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function getFxFolder()
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "LocalSnowballFX"
	fxFolder.Parent = workspace
	return fxFolder
end

----------------------------------------------------------------------------------------------
-- Camera kick (read by the chase camera in CLIENT_Snowball)
----------------------------------------------------------------------------------------------

local function addCameraKick(self, strength)
	local vars = getVars(self)
	if not vars then
		return
	end
	local existing = vars.CameraKick
	local current = 0
	if existing then
		current = existing.Strength * math.exp(-7 * (os.clock() - existing.Start))
	end
	vars.CameraKick = { Start = os.clock(), Strength = math.min(current + strength, 3) }
end

function api:AddCameraKick(strength)
	addCameraKick(self, strength)
end

function api:GetCameraKick(_dt)
	local vars = getVars(self)
	local kick = vars and vars.CameraKick
	if not kick then
		return CFrame.identity
	end
	local t = os.clock() - kick.Start
	if t > 0.7 then
		vars.CameraKick = nil
		return CFrame.identity
	end
	local amp = kick.Strength * math.exp(-7 * t)
	local y = math.sin(t * 34) * 0.9 * amp
	local x = math.sin(t * 27 + 1) * 0.45 * amp
	local roll = math.sin(t * 30) * math.rad(1.6) * amp
	return CFrame.new(x, y, 0) * CFrame.Angles(0, 0, roll)
end

----------------------------------------------------------------------------------------------
-- Each hit holds large and rocks in the middle for one second, then shrinks
-- into the compact gold label below the run readouts. The extra visual hold
-- does not extend ComboWindow for chaining hits or earning bonuses.
----------------------------------------------------------------------------------------------

local COMBO_CENTER_HOLD = 1
local combo = { Count = 0, Best = 0, Last = 0, Token = 0, Tweens = {} }

local function ensureComboGui()
	if combo.Gui and combo.Gui.Parent then
		return combo
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("SnowballCombo")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SnowballCombo"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1001
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name = "Combo"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, SMASH.ComboTopY, SMASH.ComboTopOffset or 0)
	frame.Size = UDim2.fromOffset(520, 48)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui

	-- TextScaled caps at 100 px, so the pop is driven by UIScale on a fixed TextSize.
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = false
	label.TextSize = 32
	label.RichText = true
	label.Text = ""
	label.TextColor3 = COMBO_COLOR
	label.TextStrokeTransparency = 1
	label.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(28, 26, 32)
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	gui.Parent = playerGui
	combo.Gui, combo.Frame, combo.Scale, combo.Label, combo.Stroke = gui, frame, scale, label, stroke
	return combo
end

local function baseComboScale()
	local camera = workspace.CurrentCamera
	local viewport = if combo.Gui then combo.Gui.AbsoluteSize elseif camera then camera.ViewportSize else Vector2.new(1301, 611)
	return HUDLayout.GetScale(viewport) * (611 / 941)
end

-- Where the label settles: ComboTopY + ComboTopOffset at the least, and always under the
-- HUD's ride readouts (MainUI.DistanceRolled / CoinsMade scale with the screen, so a
-- fixed offset covered CoinsMade on most screens). Both guis ignore the inset, so the
-- labels' AbsolutePosition (inset-relative) is shifted by the inset to screen space.
local function comboSettlePosition()
	local camera = workspace.CurrentCamera
	local viewport = if combo.Gui then combo.Gui.AbsoluteSize elseif camera then camera.ViewportSize else Vector2.new(1301, 611)
	local hudScale = HUDLayout.GetScale(viewport)
	local y = HUDLayout.GetTopInset(viewport) + 186 * hudScale
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("HUD")
	if hud then
		local insetY = GuiService:GetGuiInset().Y
		local halfLabel = 0.5 * 32 * baseComboScale() + 3 * hudScale
		for _, name in SMASH.ComboAvoid or { "DistanceRolled", "CoinsMade" } do
			local label = hud:FindFirstChild(name, true)
			if label and label:IsA("GuiObject") and label.Visible and label.AbsoluteSize.Y > 0 then
				-- The HUD pops CoinsMade with an "EarnPop" UIScale (around its anchor) on every
				-- coin gain: measure the resting box and leave room for the biggest pop, so the
				-- combo lands at the same height every hit and a later pop cannot cover it.
				local pop = label:FindFirstChild("EarnPop")
				local k = if pop and pop:IsA("UIScale") and pop.Scale > 0 then pop.Scale else 1
				local restH = label.AbsoluteSize.Y / k
				local anchorY = label.AbsolutePosition.Y + label.AbsoluteSize.Y * label.AnchorPoint.Y
				local grow = if pop then (SMASH.ComboAvoidPop or 1.45) else 1
				local bottom = anchorY + restH * grow * (1 - label.AnchorPoint.Y) + insetY
				y = math.max(y, bottom + (SMASH.ComboClearGap or 6) * hudScale + halfLabel)
			end
		end
	end
	return UDim2.new(0.5, 0, 0, math.floor(y + 0.5))
end

local function cancelComboTweens()
	for _, tween in combo.Tweens do
		tween:Cancel()
	end
	combo.Tweens = {}
end

local function hideCombo()
	local c = ensureComboGui()
	cancelComboTweens()
	local info = TweenInfo.new(SMASH.ComboFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local t1 = TweenService:Create(c.Label, info, { TextTransparency = 1 })
	local t2 = TweenService:Create(c.Stroke, info, { Transparency = 1 })
	local t3 = TweenService:Create(c.Scale, info, { Scale = baseComboScale() * 0.7 })
	combo.Tweens = { t1, t2, t3 }
	t1:Play()
	t2:Play()
	t3:Play()
	local token = combo.Token
	task.delay(SMASH.ComboFadeTime, function()
		if combo.Token == token then
			c.Frame.Visible = false
		end
	end)
end

local function expireCombo()
	combo.Count = 0
	combo.Token += 1
	hideCombo()
end

-- Returns the new stack count.
local function registerCombo()
	local now = os.clock()
	if now - combo.Last > SMASH.ComboWindow then
		combo.Count = 0
	end
	combo.Count += 1
	combo.Last = now
	combo.Best = math.max(combo.Best, combo.Count)
	Audio.Play("ComboPop", { Pitch = 1 + math.min(combo.Count, 12) * 0.045 })
	combo.Token += 1
	local token = combo.Token

	local c = ensureComboGui()
	cancelComboTweens()
	local base = baseComboScale()
	local bonus = math.floor(math.min(math.max(combo.Count - 1, 0) * playerProgress.COMBO_BONUS, playerProgress.COMBO_BONUS_CAP) * 100 + 0.5)
	c.Label.Text = string.format('🔥 COMBO %d <font size="26">+%d%% $</font>', combo.Count, bonus)
	c.Label.TextColor3 = SMASH.ComboFlashColor
	c.Label.TextTransparency = 0
	c.Stroke.Transparency = 0
	c.Frame.Visible = true
	c.Frame.Position = UDim2.fromScale(0.5, SMASH.ComboStartY)
	c.Frame.Rotation = -7
	-- Keep the center pop compact: 20% smaller again, capped near half the screen width.
	local viewport = c.Gui.AbsoluteSize
	local plainText = c.Label.Text:gsub("<.->", "")
	local textSize = game:GetService("TextService"):GetTextSize(plainText, c.Label.TextSize, c.Label.Font, Vector2.new(10000, 1000))
	local fitScale = viewport.X * 0.51 / math.max(textSize.X + 12, 1)
	c.Scale.Scale = math.min(base * SMASH.ComboPopScale * (64 / c.Label.TextSize) * 0.6, fitScale)

	local rock = TweenService:Create(c.Frame, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 7 })
	local flash = TweenService:Create(c.Label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = COMBO_COLOR })
	combo.Tweens = { rock, flash }
	rock:Play()
	flash:Play()

	task.delay(COMBO_CENTER_HOLD, function()
		if combo.Token ~= token or not c.Frame.Parent then
			return
		end
		cancelComboTweens()
		local pop = TweenInfo.new(SMASH.ComboPopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local move = TweenService:Create(c.Frame, pop, { Position = comboSettlePosition(), Rotation = 0 })
		local shrink = TweenService:Create(c.Scale, pop, { Scale = baseComboScale() })
		combo.Tweens = { move, shrink }
		move:Play()
		shrink:Play()
	end)

	task.delay(COMBO_CENTER_HOLD + SMASH.ComboWindow, function()
		if combo.Token == token then
			expireCombo()
		end
	end)
	return combo.Count
end

----------------------------------------------------------------------------------------------
-- Prop fade-out
----------------------------------------------------------------------------------------------

-- Soft white "explosion" (silent): a burst of glowing white puffs, one bright flash
-- and a quick expanding translucent sphere, all scaled to the structure's size.
local function whiteBurst(position, radius)
	local E = SMASH.Explosion or {}
	local s = math.clamp(radius / 6, 0.5, 2.2) * (E.Scale or 1)

	local part = Instance.new("Part")
	part.Name = "SmashBurst"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * math.max(radius * 0.6, 1.5)
	part.Color = Color3.fromRGB(255, 255, 255)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.35
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(position)

	local att = Instance.new("Attachment")
	att.Parent = part

	local puff = Instance.new("ParticleEmitter")
	puff.Texture = SMOKE
	puff.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	puff.LightEmission = 0.75
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4 * s), NumberSequenceKeypoint.new(1, 4.2 * s) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 1) })
	puff.Lifetime = NumberRange.new(0.35, 0.6)
	puff.Speed = NumberRange.new(16 * s, 38 * s)
	puff.SpreadAngle = Vector2.new(180, 180)
	puff.Drag = 3.5
	puff.Rotation = NumberRange.new(0, 360)
	puff.RotSpeed = NumberRange.new(-60, 60)
	puff.Enabled = false
	puff.Parent = att

	local flash = Instance.new("ParticleEmitter")
	flash.Texture = SPARKLE
	flash.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	flash.LightEmission = 1
	flash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5 * s), NumberSequenceKeypoint.new(1, 9 * s) })
	flash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	flash.Lifetime = NumberRange.new(0.22, 0.28)
	flash.Speed = NumberRange.new(0, 0)
	flash.Enabled = false
	flash.Parent = att

	part.Parent = getFxFolder()
	puff:Emit(math.clamp(math.floor(radius * 2.5 * (E.Density or 1)), 8, 36))
	flash:Emit(1)

	local grow = TweenInfo.new(E.SphereTime or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(part, grow, { Size = Vector3.one * math.max(radius * 2.2, 4), Transparency = 1 }):Play()
	task.delay(1.2, function()
		part:Destroy()
	end)
end

-- Smashed structures vanish instantly; the white burst marks the spot.
local function vanishProp(model, burst)
	if fading[model] then
		return
	end
	fading[model] = true

	local ok, boxCFrame, boxSize = pcall(model.GetBoundingBox, model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CanQuery = false
			desc.CanCollide = false
			desc.Transparency = 1
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 1
		elseif desc:IsA("SurfaceGui") or desc:IsA("BillboardGui") then
			desc.Enabled = false
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Light") or desc:IsA("Beam") or desc:IsA("Trail") then
			desc.Enabled = false
		end
	end

	if burst and ok then
		local radius = model:GetAttribute("PropRadius") or math.max(boxSize.X, boxSize.Z) * 0.5
		whiteBurst(boxCFrame.Position, radius)
	end
end

local function hookProp(model)
	model:GetAttributeChangedSignal("Smashed"):Connect(function()
		if model:GetAttribute("Smashed") then
			vanishProp(model, true)
		end
	end)
	if model:GetAttribute("Smashed") then
		vanishProp(model, false)
	end
end

local function propModelOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if CollectionService:HasTag(model, PROPS.Tag) then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

----------------------------------------------------------------------------------------------
-- FX rig per ball
----------------------------------------------------------------------------------------------

local function makeEmitter(parent, name, props)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Enabled = false
	for key, value in props do
		emitter[key] = value
	end
	emitter.Parent = parent
	return emitter
end

local function makeSound(parent, name, id, volume)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMinDistance = 25
	sound.RollOffMaxDistance = 500
	sound.Parent = parent
	return sound
end

local WHITE = Color3.fromRGB(255, 255, 255)
local ICE = Color3.fromRGB(205, 228, 255)
local WOOD = Color3.fromRGB(128, 84, 46)

local function buildRig(state)
	local part = Instance.new("Part")
	part.Name = "SnowballFX"
	part.Size = Vector3.one
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = state.Root.CFrame

	local ground = Instance.new("Attachment")
	ground.Name = "Ground"
	ground.Parent = part
	local contact = Instance.new("Attachment")
	contact.Name = "Contact"
	contact.Parent = part
	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.CFrame = CFrame.Angles(math.rad(90), 0, 0)
	center.Parent = part
	local trailL = Instance.new("Attachment")
	trailL.Name = "TrailL"
	trailL.Parent = part
	local trailR = Instance.new("Attachment")
	trailR.Name = "TrailR"
	trailR.Parent = part

	state.Spray = makeEmitter(ground, "Spray", {
		Texture = SMOKE,
		Color = ColorSequence.new(WHITE, ICE),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 2.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.35, 0.7),
		Speed = NumberRange.new(14, 32),
		SpreadAngle = Vector2.new(35, 35),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		Acceleration = Vector3.new(0, -30, 0),
		LightEmission = 0.15,
		Rate = 0,
	})
	state.Wind = makeEmitter(center, "Wind", {
		Texture = SPARKLE,
		Color = ColorSequence.new(WHITE, ICE),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Size = NumberSequence.new(0.28),
		Squash = NumberSequence.new(5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.2, 0.35),
		Speed = NumberRange.new(45, 75),
		SpreadAngle = Vector2.new(30, 30),
		LightEmission = 0.4,
		Rate = 0,
	})
	state.Burst = makeEmitter(contact, "Burst", {
		Texture = SMOKE,
		Color = ColorSequence.new(WHITE, ICE),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 0.95),
		Speed = NumberRange.new(28, 60),
		SpreadAngle = Vector2.new(80, 80),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		Acceleration = Vector3.new(0, -70, 0),
		Drag = 1.2,
		LightEmission = 0.1,
		Rate = 0,
	})
	state.Debris = makeEmitter(contact, "Debris", {
		Texture = SMOKE,
		Color = ColorSequence.new(WOOD, Color3.fromRGB(90, 58, 30)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1.1) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(30, 55),
		SpreadAngle = Vector2.new(75, 75),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-250, 250),
		Acceleration = Vector3.new(0, -85, 0),
		Drag = 0.8,
		Rate = 0,
	})

	local trail = Instance.new("Trail")
	trail.Name = "SnowTrail"
	trail.Attachment0 = trailL
	trail.Attachment1 = trailR
	trail.Color = ColorSequence.new(WHITE)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Lifetime = 0.35
	trail.MinLength = 0.5
	trail.LightEmission = 0.2
	trail.Enabled = false
	trail.Parent = part
	state.Trail = trail

	state.Sounds = {
		Whoosh = makeSound(part, "Whoosh", SOUNDS.Whoosh, SOUNDS.Volume.Whoosh),
		Thud = makeSound(part, "Thud", SOUNDS.Thud, SOUNDS.Volume.Thud),
		BigThud = makeSound(part, "BigThud", SOUNDS.BigThud, SOUNDS.Volume.BigThud),
		CrashBig = makeSound(part, "CrashBig", SOUNDS.CrashBig, SOUNDS.Volume.CrashBig),
		CrashSmall = makeSound(part, "CrashSmall", SOUNDS.CrashSmall, SOUNDS.Volume.CrashSmall),
	}
	state.Ground = ground
	state.Contact = contact
	state.TrailL = trailL
	state.TrailR = trailR
	state.RigRadius = -1
	part.Parent = getFxFolder()
	state.Rig = part
	-- Ride loops (3D, on the rig, so other players hear a ball go by): rolling crunch and
	-- wind, driven every frame in stepBall from ground contact, speed and size.
	state.Roll = Audio.Attach(part, "RideRoll", { Volume = 0 })
	state.WindLoop = Audio.Attach(part, "RideWind", { Volume = 0 })
	state.RollVol, state.WindVol = 0, 0
end

local function fitRig(state, radius)
	if math.abs(radius - state.RigRadius) < 0.05 then
		return
	end
	state.RigRadius = radius
	state.Ground.CFrame = CFrame.new(0, -radius + 0.2, 0) * CFrame.Angles(math.rad(60), 0, 0)
	state.Contact.CFrame = CFrame.new(0, -radius + 0.3, 0)
	state.TrailL.CFrame = CFrame.new(-radius * 0.85, -radius + 0.35, 0)
	state.TrailR.CFrame = CFrame.new(radius * 0.85, -radius + 0.35, 0)
	local sizeScale = math.clamp(radius / 2, 0.6, 3)
	state.Spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7 * sizeScale), NumberSequenceKeypoint.new(1, 2.4 * sizeScale) })
	state.Burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2 * sizeScale), NumberSequenceKeypoint.new(1, 3.6 * sizeScale) })
end

----------------------------------------------------------------------------------------------
-- Flight physics (owner only)
----------------------------------------------------------------------------------------------

local function weightedTrick()
	local total = 0
	for _, weight in FLIGHT.Tricks do
		total += weight
	end
	local roll = math.random() * total
	local acc = 0
	for name, weight in FLIGHT.Tricks do
		acc += weight
		if roll <= acc then
			return name
		end
	end
	return "Glide"
end

local function applyTrick(state, radius)
	if math.random() > FLIGHT.TrickChance then
		return
	end
	local root = state.Root
	local vel = root.AssemblyLinearVelocity
	local travel = state.Travel
	local right = Vector3.new(-travel.Z, 0, travel.X)
	local rolling = Vector3.yAxis:Cross(vel) / math.max(radius, 0.5)
	local flip = if math.random() < 0.5 then 1 else -1
	local trick = weightedTrick()
	local omega

	if trick == "Glide" then
		omega = rolling * 0.08
	elseif trick == "Backspin" then
		omega = rolling * FLIGHT.BackspinFactor
	elseif trick == "BarrelRoll" then
		omega = travel * FLIGHT.BarrelRollSpin * flip + rolling * 0.15
	elseif trick == "Corkscrew" then
		omega = Vector3.yAxis * FLIGHT.CorkscrewSpin * flip + right * 4
	else
		local axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		if axis.Magnitude < 0.05 then
			axis = right
		end
		omega = axis.Unit * FLIGHT.TumbleSpin
	end

	root.AssemblyAngularVelocity = omega
	state.LastTrick = trick
end

-- (defined before checkSmash, which calls it: a later definition would be an unset global)
local function powerMultiplier(state)
	local model = state.Model
	local power = model and model:GetAttribute("PowerMultiplier")
	if type(power) ~= "number" then
		local player = Players.LocalPlayer
		power = player and player:GetAttribute("Multiplier")
	end
	if type(power) ~= "number" or power < 1 then
		return 1
	end
	return power
end

local function checkSmash(state, radius, prevPos, pos)
	local decor = workspace:FindFirstChild(PROPS.WorkspaceFolder)
	if not decor then
		return
	end
	local params = state.Overlap
	if not params then
		params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		state.Overlap = params
	end
	params.FilterDescendantsInstances = { decor }

	local delta = pos - prevPos
	local length = delta.Magnitude
	local cf, size
	if length > 0.5 then
		cf = CFrame.lookAt((pos + prevPos) / 2, pos)
		size = Vector3.new(radius * 2, radius * 2, length + radius * 2)
	else
		cf = CFrame.new(pos)
		size = Vector3.one * radius * 2
	end

	for _, part in workspace:GetPartBoundsInBox(cf, size, params) do
		local model = propModelOf(part)
		if model and not model:GetAttribute("Smashed") and not state.Smashed[model] then
			state.Smashed[model] = true
			local category = model:GetAttribute("PropCategory") or "Default"
			local propRadius = model:GetAttribute("PropRadius") or 3
			local big = category == "Building" or category == "Landmark" or propRadius >= 8

			-- Instant vanish + silent white burst at the structure.
			vanishProp(model, true)

			-- Combo stacks; every stack makes the hit kick a little harder.
			local stack = registerCombo()
			local bonus = math.min(stack * (SMASH.ComboKickPerStack or 0.06), SMASH.ComboMaxBonus or 1)
			if SMASH.SmashSound then
				local sound = if big then state.Sounds.CrashBig else state.Sounds.CrashSmall
				sound.PlaybackSpeed = 0.9 + math.random() * 0.2 + math.min(stack, 12) * (SMASH.ComboPitchPerStack or 0.025)
				sound:Play()
			end

			local speed = state.Root.AssemblyLinearVelocity.Magnitude
			local loss = SMASH.SpeedLoss[category] or SMASH.SpeedLoss.Default
			local energyLoss = (SMASH.EnergyLoss and (SMASH.EnergyLoss[category] or SMASH.EnergyLoss.Default)) or 0
			-- Fast balls plow through; slower ones bleed speed and energy.
			if speed >= (COAST.FastSpeed or 78) * powerMultiplier(state) then
				local scale = COAST.FastSmashScale or 0.18
				loss *= scale
				energyLoss *= scale
			end
			state.Root.AssemblyLinearVelocity *= (1 - loss)
			state.SpeedPeak = math.min(state.SpeedPeak or speed, state.Root.AssemblyLinearVelocity.Magnitude)
			if state.Energy ~= nil then
				state.Energy = math.max(0, state.Energy - energyLoss)
			end
			addCameraKick(state.Self, (SMASH.Kick[category] or SMASH.Kick.Default) * (1 + bonus))
			state.SmashCount = (state.SmashCount or 0) + 1
			pcall(function()
				state.Model:SetAttribute("ClientCombo", stack)
				state.Model:SetAttribute("ClientBestCombo", combo.Best)
			end)

			ReplicatedStorage.ReEvent:FireServer("SmashProp", model)
		end
	end
end


local function lerpPair(pair, t)
	t = math.clamp(t, 0, 1)
	if type(pair) ~= "table" then
		return pair or 0
	end
	return (pair[1] or 0) + ((pair[2] or pair[1] or 0) - (pair[1] or 0)) * t
end

local function resolveCharge(state)
	local charge = state.Model:GetAttribute("LaunchCharge")
	if type(charge) == "number" then
		state.Charge = math.clamp(charge, 0, 1)
	elseif state.Charge == nil then
		local launchSpeed = state.Model:GetAttribute("LaunchSpeed")
		local settings = mountainConfig.LAUNCH.Charge
		if type(launchSpeed) == "number" and settings then
			local span = math.max((settings.MaxSpeed or 78) - (settings.MinSpeed or 22), 1)
			charge = (launchSpeed - (settings.MinSpeed or 22)) / span
		else
			charge = 0.5
		end
		state.Charge = math.clamp(charge, 0, 1)
	end
	if state.Energy == nil then
		state.Energy = 1
	end
	return state.Charge or 0.5
end

-- Arcade momentum keeper. A fast ball plows through kinks and keeps most of its
-- speed. A slower one keeps the hit (and loses a little more) so objects can stop it.
local function keepMomentum(state, dt, hit, speed, vel, radius)
	-- While a launch-helper hold is active, do not treat the boost as an impact
	-- and do not restore a pre-grant peak over it.
	if state.GrantAt and os.clock() - state.GrantAt < (state.GrantHold or 0) then
		state.SpeedPeak = speed
		return
	end
	local peak = state.SpeedPeak or 0
	peak = math.max(speed, peak - (FLIGHT.PeakDecay or 400) * dt)
	local fast = math.max(speed, peak) >= (COAST.FastSpeed or 78) * powerMultiplier(state)
	if fast and peak > (FLIGHT.ImpactMinSpeed or 60) and speed < peak * (FLIGHT.ImpactRatio or 0.7) then
		local n = (hit and hit.Normal) or state.GroundNormal or Vector3.yAxis
		local axis = state.Axis or Vector3.new(0, 0, -1)
		local tangent = axis - n * axis:Dot(n)
		if tangent.Magnitude > 0.05 then
			tangent = tangent.Unit
			local keep = peak * (FLIGHT.ImpactKeep or 0.82)
			local bounce = math.max(vel:Dot(n), 0) * 0.5
			local newVel = tangent * keep + n * bounce
			state.Root.AssemblyLinearVelocity = newVel
			state.Root.AssemblyAngularVelocity = n:Cross(newVel) / math.max(radius, 0.5)
			state.ImpactFixes = (state.ImpactFixes or 0) + 1
			pcall(function()
				state.Model:SetAttribute("ImpactFixes", state.ImpactFixes)
			end)
			peak = keep
		end
	elseif not fast and peak > 25 and speed < peak * 0.85 then
		local extra = COAST.HitSlow or 0.08
		local newVel = vel * (1 - extra)
		state.Root.AssemblyLinearVelocity = newVel
		peak = newVel.Magnitude
	end
	state.SpeedPeak = peak
end

-- Charge-scaled coast: drag + a decaying energy budget. Weak launches fade out
-- quickly; a full hold lasts much longer. Spent energy brakes even on downhill.
-- Later mountains drain energy faster until equipped power catches the gear
-- that mountain expects. At the expected power, coast time matches mountain 1.
local function coastDrainScale(state)
	local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	local mountainId = mountain and mountain:GetAttribute("MountainId")
	local resistance = mountainConfig:CoastResistance(mountainId)
	local power = mountainConfig:EffectivePower(powerMultiplier(state))
	if resistance < 1 then
		resistance = 1
	end
	return resistance / math.max(power, 1)
end

local function applyCoast(state, dt, grounded, hit)
	local charge = resolveCharge(state)
	local drain = lerpPair(COAST.EnergyDrain, charge) * coastDrainScale(state)
	local energy = math.max(0, (state.Energy or 1) - drain * dt)
	state.Energy = energy

	local root = state.Root
	local vel = root.AssemblyLinearVelocity

	-- Once the budget is gone, cancel this frame's slope gravity so the ball can
	-- actually halt on a downhill instead of creeping forever.
	if energy < (COAST.BrakeBelow or 0.2) and grounded and hit then
		local spent = 1 - energy / math.max(COAST.BrakeBelow or 0.2, 0.01)
		local g = Vector3.new(0, -workspace.Gravity, 0)
		local along = g - hit.Normal * g:Dot(hit.Normal)
		vel -= along * dt * spent
	end

	local horiz = Vector3.new(vel.X, 0, vel.Z)
	local speedH = horiz.Magnitude
	if speedH < 0.05 then
		if energy < (COAST.BrakeBelow or 0.2) then
			root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
			root.AssemblyAngularVelocity *= math.max(0, 1 - (COAST.SpinDamp or 4) * dt)
		end
		return
	end

	local drag = lerpPair(if grounded then COAST.GroundDrag else COAST.AirDrag, charge)
	drag *= 1 + (1 - energy) * (COAST.EmptyDragBonus or 2.2)
	local damp = lerpPair(if grounded then COAST.GroundDamp else COAST.AirDamp, charge)
	if energy < (COAST.BrakeBelow or 0.2) then
		local spent = 1 - energy / math.max(COAST.BrakeBelow or 0.2, 0.01)
		drag += (COAST.BrakeAccel or 36) * spent
		damp += (COAST.BrakeDamp or 5) * spent
	end

	local cap = lerpPair(COAST.MaxSpeed, charge)
	cap *= powerMultiplier(state)
	cap *= (COAST.CapFloor or 0.32) + (1 - (COAST.CapFloor or 0.32)) * energy
	if state.GrantCapSpeed and state.GrantAt then
		local elapsed = os.clock() - state.GrantAt
		cap = launchMath.easeCap(cap, state.GrantCapSpeed, elapsed, state.GrantHold, state.GrantFade)
		if not launchMath.grantActive(elapsed, state.GrantHold, state.GrantFade) then
			state.GrantCapSpeed = nil
		end
	end

	local newSpeed = math.min(speedH, cap)
	newSpeed *= math.exp(-damp * dt)
	newSpeed = math.max(0, newSpeed - drag * dt)
	local dir = horiz / speedH
	root.AssemblyLinearVelocity = Vector3.new(dir.X * newSpeed, vel.Y, dir.Z * newSpeed)

	if energy < (COAST.BrakeBelow or 0.2) then
		root.AssemblyAngularVelocity *= math.max(0, 1 - (COAST.SpinDamp or 4) * dt)
	end
end

local function readSteer(state)
	if not state.Physics then
		return 0
	end
	local vars = getVars(state.Self)
	local value = vars and vars.Steer
	if type(value) ~= "number" then
		return 0
	end
	return math.clamp(value, -1, 1)
end

-- Rolling stays on the downhill line: no auto weave, and leftover sideways
-- speed is bled off. Left/right is only player steering on the ground.
-- Flight is up/down only (plus a soft edge push if it drifts off the track).
local function steerWander(state, dt, grounded, pos)
	local W = FLIGHT.Wander
	local right = state.Right
	if not W or not right then
		return
	end
	local root = state.Root
	local vel = root.AssemblyLinearVelocity
	local forward = vel:Dot(state.Axis)
	if forward < 12 then
		return
	end

	local player = readSteer(state)
	local steering = grounded and math.abs(player) > 0.05
	local offset = (pos - state.AxisOrigin):Dot(right)
	local wanted = 0
	local heading = W.MaxHeading
	local blendRate = if grounded then W.GroundBlend else W.AirBlend

	if steering then
		local playerTarget = player * (W.EdgeLimit - 8)
		wanted = (playerTarget - offset) * W.Gain
		wanted += player * math.max(forward, 15) * (W.PlayerHeading or 0)
		heading = W.PlayerMaxHeading or W.MaxHeading
		blendRate = math.max(blendRate, W.PlayerBlend or 7)
	end

	local cap = math.max(forward, 15) * heading
	wanted = math.clamp(wanted, -cap, cap)

	-- Edge safety: sideways speed toward the nearer edge is limited by the room left,
	-- and past the limit the ball is pushed back with a fast blend (air included).
	local room = W.EdgeLimit - math.abs(offset)
	if offset ~= 0 and math.sign(wanted) == math.sign(offset) then
		wanted = math.sign(wanted) * math.min(math.abs(wanted), math.max(room, 0) * 3)
	end
	if room < 0 then
		wanted = -math.sign(offset) * math.min(cap, 40 + math.abs(room) * 4)
		blendRate = 8
	elseif room < 6 then
		blendRate = math.max(blendRate, 6)
	end

	local realLateral = vel:Dot(right)
	local lateral = realLateral
	if room < 0 and math.sign(lateral) == math.sign(offset) then
		lateral = 0 -- never keep sliding outward past the limit
	end
	local blend = math.min(1, blendRate * dt)
	local newLateral = lateral + (wanted - lateral) * blend
	if math.abs(newLateral - realLateral) > 0.01 then
		root.AssemblyLinearVelocity = vel + right * (newLateral - realLateral)
	end
	state.WanderTarget = if steering then player * (W.EdgeLimit - 8) else 0
end

local function stepPhysics(state, dt, grounded, radius, pos, hit)
	local root = state.Root
	local lift = state.Lift
	if not lift or not lift.Parent then
		return
	end
	local mass = root.AssemblyMass
	local weight = mass * workspace.Gravity

	if hit then
		state.GroundNormal = hit.Normal
	end
	local currentVel = root.AssemblyLinearVelocity
	keepMomentum(state, dt, hit, currentVel.Magnitude, currentVel, radius)

	if state.Airborne then
		local vel = root.AssemblyLinearVelocity
		local speed = vel.Magnitude
		-- Full lift only once the ball is coming down: arcs peak naturally, then float.
		local liftFraction = FLIGHT.LiftFraction
		if vel.Y > 0 then
			liftFraction *= (FLIGHT.LiftRisingFactor or 0.5)
		end

		-- Gap guard: jump pieces have a hole between kicker and landing. If there is no
		-- track under where the ball will be shortly but there is track further ahead,
		-- glide across (gravity cancelled, sink damped, gentle climb when the landing
		-- sits higher than the ball) instead of dropping into the hole.
		state.GapGuard = false
		if state.Probe and speed > 20 then
			local G = FLIGHT.GapGuard or {}
			local flat = Vector3.new(vel.X, 0, vel.Z)
			local near = pos + flat * (G.NearTime or 0.25)
			local nearHit = workspace:Raycast(Vector3.new(near.X, pos.Y + 60, near.Z), Vector3.new(0, -900, 0), state.Probe)
			if not nearHit then
				local farDist = math.max(speed * (G.FarTime or 0.7), G.FarMin or 80)
				local far = pos + state.Travel * farDist
				local farHit = workspace:Raycast(Vector3.new(far.X, pos.Y + 120, far.Z), Vector3.new(0, -1200, 0), state.Probe)
				if farHit then
					state.GapGuard = true
					liftFraction = 1
					local lofting = state.GrantLoftUntil and os.clock() < state.GrantLoftUntil and vel.Y > 0
					local targetVy = if farHit.Position.Y + radius + 2 > pos.Y then (G.ClimbSpeed or 45) else 0
					if not (lofting and targetVy < vel.Y) then
						local newVy = vel.Y + (targetVy - vel.Y) * math.min(1, (G.Blend or 5) * dt)
						root.AssemblyLinearVelocity = Vector3.new(vel.X, newVy, vel.Z)
					end
				end
			end
		end

		lift.Force = Vector3.new(0, weight * liftFraction, 0) + state.Travel * (weight * FLIGHT.GlideFraction)
		if not state.TrickDone and os.clock() - state.AirStart >= FLIGHT.MinAirTime + FLIGHT.TrickDelay then
			state.TrickDone = true
			applyTrick(state, radius)
		end

		-- About to touch down: put the spin back to a clean roll BEFORE contact so a
		-- trick never turns into friction braking (a backspin landing at 300 studs/s
		-- cost two thirds of the speed in testing).
		vel = root.AssemblyLinearVelocity
		speed = vel.Magnitude
		if state.TrickDone and speed > 5 and state.Probe then
			local ahead = workspace:Raycast(pos, vel.Unit * (radius + speed * (FLIGHT.PreLandTime or 0.07)), state.Probe)
			if ahead then
				root.AssemblyAngularVelocity = ahead.Normal:Cross(vel) / math.max(radius, 0.5)
			end
		end
	else
		lift.Force = Vector3.zero
	end

	steerWander(state, dt, grounded, pos)
	applyCoast(state, dt, grounded, hit)
end

----------------------------------------------------------------------------------------------
-- Per-ball step (every client)
----------------------------------------------------------------------------------------------

local function onTakeoff(state, speed)
	if speed > 60 then
		local sound = state.Sounds.Whoosh
		sound.Volume = SOUNDS.Volume.Whoosh * math.clamp(speed / 200, 0.4, 1.4)
		sound.PlaybackSpeed = 0.9 + math.random() * 0.2
		sound:Play()
	end
end

local function onLanding(state, airTime, hit, radius)
	local root = state.Root
	local vel = root.AssemblyLinearVelocity
	local impact = math.abs(math.min(vel.Y, 0))

	if state.Physics then
		-- Clean rolling spin for whatever direction the ball is carving in.
		root.AssemblyAngularVelocity = hit.Normal:Cross(vel) / math.max(radius, 0.5)
	end

	if airTime >= FLIGHT.LandingBurstMinAir then
		local count = math.clamp(math.floor(airTime * 25 + impact / 6), 10, 70)
		state.Burst:Emit(count)
		local heavy = impact > 90 or airTime > 1
		local sound = if heavy then state.Sounds.BigThud else state.Sounds.Thud
		sound.PlaybackSpeed = 0.9 + math.random() * 0.2
		sound:Play()
		if state.Physics then
			addCameraKick(state.Self, FLIGHT.LandingKick * math.clamp(impact / 100, 0.3, 2.2))
		end
	end
end

local function removeBall(model, reason)
	local state = balls[model]
	if not state then
		return
	end
	balls[model] = nil
	pcall(function()
		model:SetAttribute("FXRemoved", string.format("%s @%.1f", tostring(reason or "folder"), os.clock()))
	end)
	if state.Rig then
		state.Rig:Destroy()
	end
	if state.Lift then
		state.Lift:Destroy()
	end
end

-- Last good patch of track: sampled while rolling, well inside the edges (FLIGHT.Recover).
-- The ball goes back there when it falls off the map instead of the ride ending.
local function sampleGoodTrack(state, hit, speed, now)
	local R = FLIGHT.Recover
	if not R or not hit or not state.Right or not state.AxisOrigin then
		return
	end
	if speed < 5 or now - (state.GoodSampledAt or 0) < (R.SampleInterval or 0.25) then
		return
	end
	local W = FLIGHT.Wander or {}
	local offset = (hit.Position - state.AxisOrigin):Dot(state.Right)
	if math.abs(offset) > (W.EdgeLimit or 40) - (R.EdgeMargin or 6) then
		return
	end
	state.GoodSampledAt = now
	state.LastGood = {
		Position = hit.Position,
		Offset = offset,
		Travel = state.Travel,
		Speed = speed,
	}
end

-- Put the ball back on the last good track sample, pulled toward the centreline, rolling at
-- part of its speed. Returns true when it recovered (or just did), false when the ride should
-- end instead (nothing to go back to, or it keeps happening).
local function recoverToTrack(state, radius, now, reason)
	local R = FLIGHT.Recover
	local good = state.LastGood
	if not R or not good then
		return false
	end
	if now - (state.LastRecoverAt or -math.huge) < (R.Cooldown or 3) then
		return true
	end
	local window = R.Window or 20
	local kept = {}
	for _, t in state.RecoverTimes or {} do
		if now - t < window then
			table.insert(kept, t)
		end
	end
	if #kept >= (R.MaxPerWindow or 3) then
		return false
	end
	table.insert(kept, now)
	state.RecoverTimes = kept
	state.LastRecoverAt = now

	local root, model = state.Root, state.Model
	local target = good.Position - state.Right * (good.Offset * (R.CentrePull or 0.5))
	local surface = state.Probe and workspace:Raycast(target + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), state.Probe)
	if surface then
		target = surface.Position
	end
	target += Vector3.new(0, radius + 1, 0)
	local travel = good.Travel or state.Travel or state.Axis or Vector3.new(0, 0, -1)
	local speed = math.max((good.Speed or 0) * (R.SpeedKeep or 0.6), R.MinSpeed or 30)
	if model:IsA("Model") then
		model:PivotTo(CFrame.new(target))
	else
		root.CFrame = CFrame.new(target)
	end
	root.AssemblyLinearVelocity = travel * speed
	root.AssemblyAngularVelocity = Vector3.zero
	state.Airborne = false
	state.LastGrounded = now
	state.LastPos = target
	state.GapGuard = false
	state.SpeedPeak = speed -- the drop back is not an impact for the momentum keeper
	if state.Lift then
		state.Lift.Force = Vector3.zero
	end
	Audio.Play("Teleport")
	warn(string.format("[CLIENT]: Ball off the map (%s) - back on the track at %s", tostring(reason), tostring(target)))
	return true
end

local function stepBall(state, dt)
	local root, model = state.Root, state.Model
	if not root.Parent or not model.Parent then
		state.MissingFor = (state.MissingFor or 0) + dt
		if state.MissingFor > 2 then
			removeBall(model, if root.Parent then "model gone" else "root gone")
		end
		return
	end
	state.MissingFor = 0

	local scale = model:GetAttribute("SnowScale") or 1
	local radius = (model:GetAttribute("StartRadius") or 1) * scale
	local pos = root.Position
	local prevPos = state.LastPos or pos
	state.LastPos = pos
	local vel = root.AssemblyLinearVelocity
	local moved = if dt > 0 then (pos - prevPos).Magnitude / dt else 0
	local speed = math.max(vel.Magnitude, moved)

	local params = state.Probe
	if not params then
		params = RaycastParams.new()
		state.Probe = params
	end
	local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	if mountain then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { mountain }
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model, getFxFolder(), Players.LocalPlayer.Character }
	end
	local hit = workspace:Raycast(pos, Vector3.new(0, -(radius + FLIGHT.GroundProbe), 0), params)
	local grounded = hit ~= nil
	local now = os.clock()

	if grounded then
		if state.Airborne then
			state.Airborne = false
			onLanding(state, now - state.AirStart, hit, radius)
		end
		state.LastGrounded = now
		if state.Physics then
			sampleGoodTrack(state, hit, speed, now)
		end
	elseif not state.Airborne and now - (state.LastGrounded or now) >= FLIGHT.MinAirTime then
		state.Airborne = true
		state.AirStart = state.LastGrounded or now
		state.TrickDone = false
		onTakeoff(state, speed)
		-- No steering in the air: cap the sideways speed the ball leaves the ground with.
		local W = FLIGHT.Wander
		if state.Physics and W and W.TakeoffLateralCap and state.Right and state.Axis then
			local v = root.AssemblyLinearVelocity
			local lateral = v:Dot(state.Right)
			local cap = math.abs(v:Dot(state.Axis)) * W.TakeoffLateralCap
			if math.abs(lateral) > cap then
				root.AssemblyLinearVelocity = v + state.Right * (math.sign(lateral) * cap - lateral)
			end
		end
	end

	local travel = Vector3.new(vel.X, 0, vel.Z)
	if travel.Magnitude > 1 then
		state.Travel = travel.Unit
	elseif not state.Travel then
		state.Travel = Vector3.new(0, 0, -1)
	end

	state.Rig.CFrame = CFrame.lookAt(pos, pos + state.Travel)
	fitRig(state, radius)

	-- Ride sound: rolling crunch while grounded (louder and deeper as the ball grows), wind
	-- with speed (more in the air). Both ease so a bump never clicks.
	if state.Roll and state.Roll.Parent and state.WindLoop and state.WindLoop.Parent then
		local size = math.clamp((scale - 1) / 9, 0, 1)
		local ease = 1 - math.exp(-8 * dt)
		local rollTarget = if grounded and speed > 6 then math.clamp((speed - 6) / 140, 0, 1) else 0
		state.RollVol += (rollTarget - state.RollVol) * ease
		state.Roll.Volume = (state.Roll:GetAttribute("BaseVolume") or 0.9) * state.RollVol * (0.6 + 0.4 * size)
		state.Roll.PlaybackSpeed = 0.85 + 0.45 * math.clamp(speed / 220, 0, 1) - 0.3 * size
		local windTarget = math.clamp((speed - 45) / 220, 0, 1) * (if state.Airborne then 1.25 else 0.8)
		state.WindVol += (windTarget - state.WindVol) * ease
		state.WindLoop.Volume = (state.WindLoop:GetAttribute("BaseVolume") or 0.5) * state.WindVol
		state.WindLoop.PlaybackSpeed = 0.9 + 0.35 * math.clamp(speed / 300, 0, 1)
	end
	-- Every whole size step the ball gains: a soft snow whump, deeper the bigger it gets.
	local sizeStep = math.floor(scale)
	if not state.SizeStep then
		state.SizeStep = sizeStep
	elseif sizeStep > state.SizeStep then
		state.SizeStep = sizeStep
		Audio.PlayAt("SizeUp", state.Rig, { Pitch = math.clamp(1.15 - sizeStep * 0.05, 0.6, 1.1) })
	end

	if grounded and speed > 25 then
		state.Spray.Rate = math.clamp(speed * 0.35, 8, 90)
		state.Spray.Enabled = true
		state.Trail.Enabled = speed > 40
	else
		state.Spray.Enabled = false
		state.Trail.Enabled = false
	end
	if state.Airborne and speed > 40 then
		state.Wind.Rate = math.clamp(speed * 0.4, 10, 80)
		state.Wind.Enabled = true
	else
		state.Wind.Enabled = false
	end

	if state.Physics then
		local hold = model:GetAttribute("FinishCFrame")
		if typeof(hold) == "CFrame" then
			root.Anchored = true
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			if model:IsA("Model") then
				model:PivotTo(hold)
			else
				root.CFrame = hold
			end
			return
		end

		stepPhysics(state, dt, grounded, radius, pos, hit)
		if state.Self and state.Self.ScanLaunchProps and not model:GetAttribute("Finishing") then
			state.Self:ScanLaunchProps(state, prevPos, pos, radius, dt)
		end
		checkSmash(state, radius, prevPos, pos)

		-- The server owns snow removal, but it only sees this ball at replication
		-- rate. Reporting the contact point we are actually rolling on keeps the
		-- cleared trail under the ball at speed; the server validates it.
		if grounded and hit then
			local carve = mountainConfig.SNOW.Carve
			if now - (state.LastCarveSent or 0) >= (carve.Interval or 0.05) then
				state.LastCarveSent = now
				ReplicatedStorage.ReEvent:FireServer("CarveSnow", hit.Position)
			end
		end

		-- Reaching the finish parks the ball in front of the platform. The chase
		-- camera stays on the ball; the server unlocks the next mountain from here.
		local finish = state.FinishPiece
		if not finish or not finish.Parent then
			local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
			finish = mountain and mountainConfig.FindFinishPlatform(mountain)
			state.FinishPiece = finish
		end
		if finish and not state.Ended then
			local contact = mountainConfig.FinishContact(finish, prevPos, pos, radius + 12)
			if contact then
				state.FinishPoint = contact
			end
		end

		local finishCfg = mountainConfig.FINISH
		if state.FinishPoint and not state.Ended and not state.FinishGaveUp then
			if not state.FinishStarted then
				state.FinishStarted = now
				model:SetAttribute("Finishing", true)
			end
			if now - state.FinishStarted > (finishCfg.ReportWindow or 6) then
				state.FinishGaveUp = true
				state.FinishPoint = nil
				model:SetAttribute("Finishing", nil)
			elseif now - (state.FinishSentAt or 0) >= (finishCfg.ReportInterval or 0.6) then
				state.FinishSentAt = now
				ReplicatedStorage.ReEvent:FireServer("ReachFinish", state.FinishPoint)
			end
		end

		-- Off the map: below the run's floor, or falling for too long with nothing under the
		-- ball. It goes back onto the last good track (FLIGHT.Recover) and the ride carries
		-- on; it only ends when there is nothing to go back to or it keeps happening. A finish
		-- arrival is handled above.
		if not state.Ended and not model:GetAttribute("Finishing") then
			local R = FLIGHT.Recover or {}
			local belowFloor = state.FloorY ~= nil and pos.Y < state.FloorY
			local fell = belowFloor
			if not fell and state.Airborne and vel.Y < 0 and now - (state.AirStart or now) >= (R.MaxAirTime or 4) then
				local below = state.Probe and workspace:Raycast(pos, Vector3.new(0, -(R.ProbeDepth or 400), 0), state.Probe)
				fell = below == nil
			end
			if fell and not recoverToTrack(state, radius, now, if belowFloor then "below the floor" else "falling") then
				state.Ended = true
				local self = state.Self
				task.defer(function()
					if self and self.StopRide then
						self:StopRide()
					end
				end)
			end
		end
	end
end

local function ensureLoop()
	if loopConnection then
		return
	end
	loopConnection = RunService.Heartbeat:Connect(function(dt)
		for _, state in balls do
			stepBall(state, dt)
		end
	end)
end

local function watchBall(model)
	if balls[model] then
		return balls[model]
	end
	if not (model:IsA("Model") or model:IsA("BasePart")) then
		return nil
	end
	local root = getRoot(model)
	local timeout = os.clock() + 5
	while not root and model.Parent and os.clock() < timeout do
		task.wait(0.1)
		root = getRoot(model)
	end
	if not root or balls[model] then
		return balls[model]
	end

	local state = {
		Model = model,
		Root = root,
		Airborne = false,
		LastGrounded = os.clock(),
		Smashed = setmetatable({}, { __mode = "k" }),
	}
	buildRig(state)
	balls[model] = state
	ensureLoop()
	return state
end

----------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------

function api:StartSnowballFX()
	local vars = getVars(self)
	if vars and vars.SnowballFXStarted then
		return
	end
	if vars then
		vars.SnowballFXStarted = true
	end

	for _, model in CollectionService:GetTagged(PROPS.Tag) do
		hookProp(model)
	end
	CollectionService:GetInstanceAddedSignal(PROPS.Tag):Connect(hookProp)

	local function hookFolder(folder)
		for _, child in folder:GetChildren() do
			task.spawn(watchBall, child)
		end
		folder.ChildAdded:Connect(function(child)
			task.spawn(watchBall, child)
		end)
		folder.ChildRemoved:Connect(removeBall)
	end

	local folder = workspace:FindFirstChild("ActiveSnowballs")
	if folder then
		hookFolder(folder)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "ActiveSnowballs" then
			hookFolder(child)
		end
	end)

	if self.StartLaunchProps then
		self:StartLaunchProps()
	end
end

-- Race progress bar (the RaceProgressGui UI: ServerStorage.Modules.UserInterfaces + its
-- frames, spawned into PlayerGui by GUIFramework): it draws one marker per player from the
-- replicated player attribute "Distance", which the server writes while a ball rides. We
-- only feed it the run length + finish label.
local function withCommas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function api:SetupRaceProgress()
	task.spawn(function()
		local gui = self.GUIFramework and self.GUIFramework:GetUI("RaceProgressGui")
		if not gui then
			warn("[CLIENT]: RaceProgressGui UI not found (manifest entry missing?)")
			return
		end

		local hooked = setmetatable({}, { __mode = "k" })
		local function apply()
			local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
			local total = mountain and mountain:GetAttribute("RunLength")
			if typeof(total) ~= "number" or total <= 0 then
				return
			end
			gui:SetAttribute("MaxDistance", total)
			local finish = gui:FindFirstChild("FinishLabel", true)
			if finish and finish:IsA("TextLabel") then
				finish.Text = withCommas(total) .. " m"
			end
		end
		local function hook(mountain)
			if hooked[mountain] then
				return
			end
			hooked[mountain] = true
			mountain:GetAttributeChangedSignal("RunLength"):Connect(apply)
			apply()
		end

		local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
		if mountain then
			hook(mountain)
		end
		workspace.ChildAdded:Connect(function(child)
			if child.Name == mountainConfig.WORKSPACE_NAME then
				task.defer(hook, child)
			end
		end)
	end)
end

function api:StartAirPhysics(snowball, root)
	api.StopAirPhysics(self)
	local state = watchBall(snowball)
	if not state then
		return
	end
	root = root or state.Root
	state.Root = root
	state.Physics = true
	state.Self = self
	state.SmashCount = 0
	state.Charge = nil
	state.Energy = 1
	state.LaunchGrantSeq = 0
	state.GrantCapSpeed = nil
	state.GrantAt = nil
	state.GrantHold = nil
	state.GrantFade = nil
	state.GrantLoftUntil = nil
	resolveCharge(state)
	if self.ResetLaunchPropLocal then
		self:ResetLaunchPropLocal()
	end

	local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	local startPiece = mountain and mountain:FindFirstChild(mountainConfig.Attachment.StartPlatform .. "_1")
	local axisRoot = startPiece and startPiece:FindFirstChild("Root")
	local axis = axisRoot and axisRoot.CFrame.LookVector or Vector3.new(0, 0, -1)
	axis = Vector3.new(axis.X, 0, axis.Z)
	if axis.Magnitude < 0.05 then
		axis = Vector3.new(0, 0, -1)
	end
	axis = axis.Unit
	state.Axis = axis
	state.Right = Vector3.new(-axis.Z, 0, axis.X)
	state.AxisOrigin = axisRoot and axisRoot.Position or root.Position
	state.Travel = axis

	-- Lowest point of the run (finish exit) minus a margin: below this the ride is over.
	state.FloorY = nil
	if mountain then
		local lowest = math.huge
		for _, piece in mountain:GetChildren() do
			local exit = piece:FindFirstChild("Root") and piece.Root:FindFirstChild("Exit")
			if exit then
				lowest = math.min(lowest, exit.WorldPosition.Y)
			end
		end
		if lowest < math.huge then
			state.FloorY = lowest - 150
		end
	end
	pcall(function()
		snowball:SetAttribute("FXRig", state.Rig and state.Rig.Name or "none")
	end)

	local attachment = root:FindFirstChild("FlightAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "FlightAttachment"
		attachment.Parent = root
	end
	local lift = Instance.new("VectorForce")
	lift.Name = "FlightLift"
	lift.Attachment0 = attachment
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Force = Vector3.zero
	lift.Parent = root
	state.Lift = lift
end

function api:StopAirPhysics()
	for _, state in balls do
		if state.Physics then
			state.Physics = false
			if state.Lift then
				state.Lift:Destroy()
				state.Lift = nil
			end
		end
	end
	-- Let the last center hold and upward transition finish before clearing it.
	if combo.Count > 0 then
		local token = combo.Token
		local remainingAnimation = COMBO_CENTER_HOLD + SMASH.ComboPopTime - (os.clock() - combo.Last)
		task.delay(math.max(1.5, remainingAnimation + 0.5), function()
			if combo.Token == token then
				expireCombo()
			end
		end)
	end
end

local function ownerBall()
	for _, state in balls do
		if state.Physics and state.Root and state.Root.Parent and state.Model and state.Model.Parent then
			return state
		end
	end
	return nil
end

-- Server-approved helper. Strength comes from the shared catalog, not from the payload.
function api:ApplyApprovedLaunchGrant(payload)
	Audio.Play("HelperGrant") -- the owner's own rising whoosh on top of the helper's 3D sound
	if type(payload) ~= "table" then
		return false
	end
	local seq = payload.Seq
	if type(seq) ~= "number" or seq ~= seq or seq <= 0 then
		return false
	end
	local state = ownerBall()
	if not state or not state.Physics then
		return false
	end
	local model = state.Model
	if model:GetAttribute("Finishing") or typeof(model:GetAttribute("FinishCFrame")) == "CFrame" then
		return false
	end
	if type(payload.RideToken) ~= "string" or model:GetAttribute("RideToken") ~= payload.RideToken then
		return false
	end
	if type(payload.PropId) ~= "string" or type(payload.Kind) ~= "string" then
		return false
	end
	if seq <= (state.LaunchGrantSeq or 0) then
		return false
	end
	local mechanics = launchCatalog.Mechanic(payload.Kind)
	if not mechanics or not launchMath.finiteVector(payload.Forward) then
		return false
	end
	if payload.Route ~= nil and not launchMath.finiteVector(payload.Route) then
		return false
	end

	state.LaunchGrantSeq = seq
	local limits = {
		MaxForward = mountainConfig.LAUNCH.MaxPoweredSpeed or 12000,
		MaxUp = launchCatalog.Settings.MaxUpSpeed or 140,
		LateralFraction = launchCatalog.Settings.LateralFraction or 0.45,
		HeadingBlend = launchCatalog.Settings.HeadingBlend or 0.25,
	}
	local newVel, _, capSpeed = launchMath.computeGrant(
		state.Root.AssemblyLinearVelocity,
		payload.Forward,
		payload.Route,
		mechanics,
		limits
	)
	state.Root.AssemblyLinearVelocity = newVel
	local radius = (model:GetAttribute("StartRadius") or 1) * (model:GetAttribute("SnowScale") or 1)
	if state.GroundNormal and not state.Airborne then
		state.Root.AssemblyAngularVelocity = state.GroundNormal:Cross(newVel) / math.max(radius, 0.5)
	end
	state.Energy = math.clamp((state.Energy or 0) + (mechanics.EnergyAdd or 0), 0, 1)
	state.SpeedPeak = newVel.Magnitude
	local now = os.clock()
	if capSpeed and capSpeed > 0 then
		state.GrantCapSpeed = capSpeed
		state.GrantAt = now
		state.GrantHold = mechanics.CapHold or 0.5
		state.GrantFade = mechanics.CapFade or 0.4
	end
	if (mechanics.UpSpeed or 0) > 0 then
		state.GrantLoftUntil = now + (mechanics.CapHold or 0.5)
	end
	local vars = getVars(state.Self)
	if vars then
		local grace = mechanics.StopGrace or 0.7
		vars.LaunchPropStopGraceUntil = math.max(vars.LaunchPropStopGraceUntil or 0, now + grace)
	end
	return true
end

return api
