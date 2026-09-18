--[[---------------------------------------DESCRIPTION------------------------------------------
	Snowball flight feel + effects.

	Owner client (the player riding the ball, network owner of its physics):
	  * lift + glide forces while airborne so jumps float,
	  * a random air trick per flight (glide, backspin, barrel roll, corkscrew, tumble),
	  * clean landings (rolling spin restored, sideways drift removed, camera kick),
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

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local FLIGHT = mountainConfig.FLIGHT
local SMASH = mountainConfig.SMASH
local SOUNDS = mountainConfig.SOUNDS
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
-- Combo counter: every smash stacks while hits keep coming. Each hit pops the
-- label big in the middle of the screen and tweens it up to a small orange label
-- at the top; it fades out ComboWindow seconds after the last hit.
----------------------------------------------------------------------------------------------

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
	frame.Size = UDim2.fromOffset(520, 96)
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
	label.TextSize = 64
	label.Text = ""
	label.TextColor3 = SMASH.ComboColor
	label.TextStrokeTransparency = 1
	label.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = SMASH.ComboStrokeColor
	stroke.Thickness = 4
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	gui.Parent = playerGui
	combo.Gui, combo.Frame, combo.Scale, combo.Label, combo.Stroke = gui, frame, scale, label, stroke
	return combo
end

local function baseComboScale()
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 900
	return math.clamp(height / 900, 0.55, 1.15)
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
	combo.Token += 1
	local token = combo.Token

	local c = ensureComboGui()
	cancelComboTweens()
	local base = baseComboScale()
	c.Label.Text = if combo.Count == 1 then "SMASH!" else string.format("x%d COMBO!", combo.Count)
	c.Label.TextColor3 = SMASH.ComboFlashColor
	c.Label.TextTransparency = 0
	c.Stroke.Transparency = 0
	c.Frame.Visible = true
	c.Frame.Position = UDim2.fromScale(0.5, SMASH.ComboStartY)
	c.Frame.Rotation = math.random(-7, 7)
	c.Scale.Scale = base * SMASH.ComboPopScale

	local pop = TweenInfo.new(SMASH.ComboPopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local t1 = TweenService:Create(c.Frame, pop, { Position = UDim2.new(0.5, 0, SMASH.ComboTopY, SMASH.ComboTopOffset or 0), Rotation = 0 })
	local t2 = TweenService:Create(c.Scale, pop, { Scale = base })
	local t3 = TweenService:Create(c.Label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = SMASH.ComboColor })
	combo.Tweens = { t1, t2, t3 }
	t1:Play()
	t2:Play()
	t3:Play()

	task.delay(SMASH.ComboWindow, function()
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

			local loss = SMASH.SpeedLoss[category] or SMASH.SpeedLoss.Default
			state.Root.AssemblyLinearVelocity *= (1 - loss)
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

-- Arcade momentum keeper. Rolling into a concave kink (steep slope straight into a
-- jump kicker, valley wall) at 300 studs/s makes the engine eat most of the speed in
-- one contact and the ball ends up rocking in a bowl. Only an impact can drop the
-- speed by 30% within a fraction of a second (uphill braking is gradual), so when
-- that happens we put most of it back along the surface, pointing down the run.
local function keepMomentum(state, dt, hit, speed, vel, radius)
	local peak = state.SpeedPeak or 0
	peak = math.max(speed, peak - (FLIGHT.PeakDecay or 400) * dt)
	if peak > (FLIGHT.ImpactMinSpeed or 60) and speed < peak * (FLIGHT.ImpactRatio or 0.7) then
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
	end
	state.SpeedPeak = peak
end

-- Left/right wandering. A smooth noise target (pulled toward the nearest structure
-- ahead) sets where across the track the ball wants to be; we blend its sideways
-- velocity toward that, capped to a fraction of the forward speed so it carves
-- instead of skidding. Soft edges keep it on the 100-stud track.
local function seekTarget(state, pos, right)
	local W = FLIGHT.Wander
	local now = os.clock()
	if now - (state.SeekAt or 0) < (W.SeekInterval or 0.12) then
		return state.SeekX
	end
	state.SeekAt = now
	state.SeekX = nil
	local decor = workspace:FindFirstChild(PROPS.WorkspaceFolder)
	if not decor or (W.Seek or 0) <= 0 then
		return nil
	end
	local params = state.Overlap
	if not params then
		params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		state.Overlap = params
	end
	params.FilterDescendantsInstances = { decor }
	local axis = state.Axis
	local centre = pos + axis * (W.SeekRange / 2)
	local cf = CFrame.lookAt(centre, centre + axis)
	local best, bestDist = nil, math.huge
	for _, part in workspace:GetPartBoundsInBox(cf, Vector3.new(W.SeekWidth * 2, 40, W.SeekRange), params) do
		local model = propModelOf(part)
		if model and not model:GetAttribute("Smashed") and not state.Smashed[model] then
			local ok, pivot = pcall(model.GetPivot, model)
			if ok then
				local ahead = (pivot.Position - pos):Dot(axis)
				if ahead > 5 and ahead < bestDist then
					best, bestDist = pivot.Position, ahead
				end
			end
		end
	end
	if best then
		state.SeekX = (best - state.AxisOrigin):Dot(right)
	end
	return state.SeekX
end

local function steerWander(state, dt, grounded, pos)
	local W = FLIGHT.Wander
	local right = state.Right
	if not W or not right then
		return
	end
	local root = state.Root
	local vel = root.AssemblyLinearVelocity
	local forward = vel:Dot(state.Axis)
	if forward < 15 then
		return
	end

	state.WanderSeed = state.WanderSeed or math.random() * 1000
	local t = os.clock() * W.Speed
	local targetX = math.noise(t, state.WanderSeed) * 2 * W.Amplitude
	local seekX = seekTarget(state, pos, right)
	if seekX then
		targetX = targetX + (seekX - targetX) * W.Seek
	end
	targetX = math.clamp(targetX, -W.EdgeLimit + 4, W.EdgeLimit - 4)

	local offset = (pos - state.AxisOrigin):Dot(right)
	local wanted = (targetX - offset) * W.Gain
	local cap = math.max(forward, 15) * W.MaxHeading
	wanted = math.clamp(wanted, -cap, cap)

	-- Edge safety: sideways speed toward the nearer edge is limited by the room left,
	-- and past the limit the ball is pushed back with a fast blend (air included).
	local room = W.EdgeLimit - math.abs(offset)
	local blendRate = if grounded then W.GroundBlend else W.AirBlend
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
	state.WanderTarget = targetX
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
					local targetVy = if farHit.Position.Y + radius + 2 > pos.Y then (G.ClimbSpeed or 45) else 0
					local newVy = vel.Y + (targetVy - vel.Y) * math.min(1, (G.Blend or 5) * dt)
					root.AssemblyLinearVelocity = Vector3.new(vel.X, newVy, vel.Z)
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
	elseif not state.Airborne and now - (state.LastGrounded or now) >= FLIGHT.MinAirTime then
		state.Airborne = true
		state.AirStart = state.LastGrounded or now
		state.TrickDone = false
		onTakeoff(state, speed)
	end

	local travel = Vector3.new(vel.X, 0, vel.Z)
	if travel.Magnitude > 1 then
		state.Travel = travel.Unit
	elseif not state.Travel then
		state.Travel = Vector3.new(0, 0, -1)
	end

	state.Rig.CFrame = CFrame.lookAt(pos, pos + state.Travel)
	fitRig(state, radius)

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
		stepPhysics(state, dt, grounded, radius, pos, hit)
		checkSmash(state, radius, prevPos, pos)

		-- Rolled off the end of the finish platform: end the ride instead of
		-- watching the ball fall for ten seconds.
		if state.FloorY and pos.Y < state.FloorY and not state.Ended then
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
end

-- Race progress bar (StarterGui.RaceProgressGui from RAS - Maps): its controller draws
-- one marker per player from the replicated player attribute "Distance", which the
-- server writes while a ball rides. We only feed it the run length + finish label.
local function withCommas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function api:SetupRaceProgress()
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local gui = playerGui:WaitForChild("RaceProgressGui", 20)
		if not gui then
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
	-- Ride over: let the final combo linger briefly, then clear it.
	if combo.Count > 0 then
		combo.Token += 1
		local token = combo.Token
		task.delay(1.5, function()
			if combo.Token == token then
				expireCombo()
			end
		end)
	end
end

return api
