--[[
	Bathtub  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the BUBBLE BATH (server half: ServerStorage.FunBehaviours.Bathtub; fun-builds/CONTRACT.md;
	model = fun-builds/models/build_Bathtub.py).
	  * always: the rubber duck (Duck* parts, one rigid group about Pivot_Duck) bobs, rolls and slowly turns on
	    the water, harder while the foam runs or someone is in the tub; any floating bubbles (BubbleFloat*,
	    optional - the current model has none) hover. Driven by Kit.Now(), so every client shows the same bob.
	  * Fun_Bubbles on: the foam mounds (Foam*) swell and wobble, the loose bubbles (Bubble*) jiggle, soft foam
	    puffs rise off the whole water surface, iridescent bubbles float up out of the tub, and
	    FunAssets.Sfx.BubblesLoop plays (looped, quiet, only while the camera is within NEAR_SOUND studs).
	  * a fresh switch-on (Fun_BubblesAt within SURGE_WINDOW s): a burst of foam + bubbles, and the gold spout
	    pours for POUR_TIME s (a local water stream from Pivot_SpoutTip to the surface, ripples where it lands,
	    FunAssets.Sfx.WaterLoop).
	  * "Splash" {Position, Big} from the server (someone got in / out): spray + a ring + Sfx.Splash.
	Every build part it moves or resizes is put back at rest (relative to where the Hitbox is NOW) on cleanup.
	Particle textures are the engine's built-in rbxasset:// ones (no asset ids).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds" -- a soft ring reads as a bubble
local WATER_MIN = Vector3.new(-3.5, 2.68, -1.45) -- authored fallbacks (build_Bathtub.py)
local WATER_MAX = Vector3.new(2.9, 2.68, 1.45)
local SPOUT_FALLBACK = Vector3.new(2.6, 3.49, 0)
local DUCK_FALLBACK = Vector3.new(1.25, 2.82, -0.9)
local POUR_TIME = 2.6           -- seconds the tap pours after a switch-on
local SURGE_WINDOW = 1.5        -- a switch-on older than this (seen on streaming in) plays no surge
local NEAR_SOUND = 60           -- studs camera <-> tub for the loops
local AWAKE_RANGE = 160         -- studs camera <-> tub for any particles
local DUCK_BOB = 0.05           -- authored studs, idle; x BUSY_BOB while bubbling / someone bathes
local BUSY_BOB = 2.6
local DUCK_ROLL = math.rad(5)
local DUCK_TURN = math.rad(12)  -- slow yaw drift
local FOAM_SWELL = 0.14         -- the foam mounds grow by this fraction while the bubbles run
local FLOAT_RISE = 0.35         -- authored studs the floating bubbles climb while bubbling
local STREAM_WIDTH = 0.16       -- authored diameter of the tap's water stream
local STREAM_COLOR = Color3.fromRGB(150, 215, 245)
local STREAM_ALPHA = 0.35       -- stream transparency while pouring

local B = {}
B.StepRange = 140

--..Helpers..--
--.. Seq(t0, v0, t1, v1, ...) -> NumberSequence
local function Seq(...)
	local args = {...}
	local points = {}
	for i = 1, #args, 2 do table.insert(points, NumberSequenceKeypoint.new(args[i], args[i + 1])) end
	return NumberSequence.new(points)
end

local function Emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

local function Attach(parent, name, cf)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end

local function Authored(model, name, fallback)
	local v = model:GetAttribute("Pivot_" .. name)
	return typeof(v) == "Vector3" and v or fallback
end

--..Behaviour..--
function B.Client(model, ctx)
	local s = ctx.Scale
	local hitbox = Kit.Hitbox(model)
	local hb0 = hitbox.CFrame

	--..Build parts we animate: rest poses in HITBOX space (move-safe)..--
	local duckPivot = hb0:PointToObjectSpace(Kit.ToWorld(model, Authored(model, "Duck", DUCK_FALLBACK)))
	local duck = {}    -- [part] = CFrame relative to the duck pivot (hitbox axes)
	for _, p in ipairs(Kit.Parts(model, "Duck")) do
		duck[p] = CFrame.new(duckPivot):Inverse() * hb0:ToObjectSpace(p.CFrame)
	end
	local foam = {}    -- [part] = {Rel, Size, Phase}
	for i, p in ipairs(Kit.Parts(model, "Foam")) do
		foam[p] = {Rel = hb0:ToObjectSpace(p.CFrame), Size = p.Size, Phase = i * 1.7}
	end
	local loose, floats = {}, {} -- [part] = {Rel, Phase}
	for i, p in ipairs(Kit.Parts(model, "Bubble")) do
		local rec = {Rel = hb0:ToObjectSpace(p.CFrame), Phase = i * 2.3}
		if p.Name:sub(1, 11) == "BubbleFloat" then floats[p] = rec else loose[p] = rec end
	end

	local function PoseDuck(hb, bob, pitch, yaw, roll)
		local pose = hb * CFrame.new(duckPivot + Vector3.new(0, bob, 0)) * CFrame.Angles(pitch, yaw, roll)
		for p, rel in pairs(duck) do p.CFrame = pose * rel end
	end
	local function RestFoam(hb)
		for p, f in pairs(foam) do
			p.Size = f.Size
			p.CFrame = hb * f.Rel
		end
		for p, f in pairs(loose) do p.CFrame = hb * f.Rel end
	end
	ctx:OnCleanup(function()
		if not hitbox.Parent then return end
		local hb = hitbox.CFrame
		PoseDuck(hb, 0, 0, 0, 0)
		RestFoam(hb)
		for p, f in pairs(floats) do p.CFrame = hb * f.Rel end
	end)

	--..Effects host: one invisible local part lying on the water..--
	local wMin = Authored(model, "WaterMin", WATER_MIN)
	local wMax = Authored(model, "WaterMax", WATER_MAX)
	local centre = (wMin + wMax) * 0.5
	local extent = wMax - wMin
	local fx = ctx:Part({
		Name = "BathFX",
		Transparency = 1,
		Size = Vector3.new(math.max(extent.X, 0.5) * s, 0.1, math.max(extent.Z, 0.5) * s),
		CFrame = Kit.CFrameToWorld(model, CFrame.new(centre)) * CFrame.new(0, 0.05, 0),
	})

	--.. foam puffs off the whole surface (steady while bubbling, burst on a switch-on)
	local puffs = Emitter(fx, {
		Name = "FoamPuffs",
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		Size = Seq(0, 0.5 * s, 0.35, 1.2 * s, 1, 1.6 * s),
		Transparency = Seq(0, 1, 0.15, 0.4, 0.7, 0.6, 1, 1),
		Lifetime = NumberRange.new(1.6, 2.4),
		Rate = 10,
		Speed = NumberRange.new(0.3 * s, 0.8 * s),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, 0.3 * s, 0),
		Drag = 0.5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-25, 25),
		LightEmission = 0.15,
		LightInfluence = 0.6,
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	--.. iridescent bubbles drifting up out of the tub, popping at the end of their life
	local floaters = Emitter(fx, {
		Name = "Bubbles",
		Texture = TEX_RING,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 214, 240)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 236, 255)),
		}),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.14 * s, 0.06 * s),
			NumberSequenceKeypoint.new(0.9, 0.3 * s, 0.1 * s),
			NumberSequenceKeypoint.new(1, 0.42 * s, 0.1 * s),
		}),
		Transparency = Seq(0, 0.6, 0.1, 0.1, 0.9, 0.2, 1, 1),
		Lifetime = NumberRange.new(2, 3.4),
		Rate = 12,
		Speed = NumberRange.new(1.2 * s, 2.6 * s),
		SpreadAngle = Vector2.new(28, 28),
		Acceleration = Vector3.new(0, 0.5 * s, 0),
		Drag = 0.7,
		LightEmission = 0.4,
		LightInfluence = 0.4,
		ZOffset = 0.5,
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})

	--.. the tap's water stream: a thin local cylinder from the spout tip down to the surface + ripples below it
	local spout = Kit.ToWorld(model, Authored(model, "SpoutTip", SPOUT_FALLBACK))
	local up = fx.CFrame.UpVector
	local landing = fx.CFrame * CFrame.new(fx.CFrame:PointToObjectSpace(spout) * Vector3.new(1, 0, 1)) -- under the spout, on the water
	local fall = math.max((spout - landing.Position):Dot(up), 0.2)
	local stream = ctx:Part({
		Name = "BathPour",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(fall, STREAM_WIDTH * s, STREAM_WIDTH * s),
		CFrame = CFrame.fromMatrix(landing.Position + up * (fall * 0.5), up, landing.RightVector),
		Color = STREAM_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 1,
	})
	local ripples = Emitter(Attach(fx, "PourLanding", fx.CFrame:ToObjectSpace(landing) * CFrame.new(0, 0.02, 0)), {
		Name = "Ripples",
		Texture = TEX_RING,
		Color = ColorSequence.new(Color3.fromRGB(240, 250, 255)),
		Size = Seq(0, 0.2 * s, 1, 1.1 * s),
		Transparency = Seq(0, 0.25, 1, 1),
		Lifetime = NumberRange.new(0.5, 0.7),
		Rate = 7,
		Speed = NumberRange.new(0.05, 0.08),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, -- flat on the water
		Rotation = NumberRange.new(0, 360),
		LightEmission = 0.2,
		ZOffset = 0.3,
		EmissionDirection = Enum.NormalId.Top,
	})

	--.. splash: a spray + a ring, moved to wherever the splash is and burst with :Emit
	local splashAt = Attach(fx, "Splash", CFrame.new())
	local spray = Emitter(splashAt, {
		Name = "Spray",
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(225, 245, 255)),
		Size = Seq(0, 0.35 * s, 1, 0.12 * s),
		Transparency = Seq(0, 0.15, 0.7, 0.35, 1, 1),
		Lifetime = NumberRange.new(0.45, 0.75),
		Speed = NumberRange.new(7 * s, 11 * s),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -45, 0),
		Drag = 0.5,
		Rotation = NumberRange.new(0, 360),
		LightEmission = 0.2,
		ZOffset = 0.3,
		EmissionDirection = Enum.NormalId.Top,
	})
	local splashRing = Emitter(splashAt, {
		Name = "SplashRing",
		Texture = TEX_RING,
		Color = ColorSequence.new(Color3.fromRGB(245, 252, 255)),
		Size = Seq(0, 0.5 * s, 1, 2.4 * s),
		Transparency = Seq(0, 0.2, 1, 1),
		Lifetime = NumberRange.new(0.7, 0.9),
		Speed = NumberRange.new(0.05, 0.08),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Rotation = NumberRange.new(0, 360),
		LightEmission = 0.2,
		ZOffset = 0.3,
		EmissionDirection = Enum.NormalId.Top,
	})

	--..Sounds..--
	local bubblesLoop = ctx:Sound(fx, FunAssets.Sfx.BubblesLoop, {Name = "BubblesLoop", Looped = true, Volume = 0.3, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND})
	local pourLoop = ctx:Sound(stream, FunAssets.Sfx.WaterLoop, {Name = "Pour", Looped = true, Volume = 0.35, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND})
	local splashSound = ctx:Sound(fx, FunAssets.Sfx.Splash, {Name = "Splash", Volume = 0.55, RollOffMaxDistance = 70})
	ctx.BathFX = {At = splashAt, Spray = spray, Ring = splashRing, Sound = splashSound, Fx = fx}

	--..State..--
	local bubblesOn, bathing, awake, pourUntil = false, false, true, 0
	local function Apply()
		puffs.Enabled = awake and bubblesOn
		floaters.Enabled = awake and bubblesOn
		local near = awake and ctx:CameraDistance() <= NEAR_SOUND
		local wantLoop = near and bubblesOn
		if wantLoop and not bubblesLoop.IsPlaying then
			bubblesLoop:Play()
		elseif not wantLoop and bubblesLoop.IsPlaying then
			bubblesLoop:Stop()
		end
	end
	ctx:OnState("Bubbles", function(value)
		bubblesOn = value == true
		Apply()
	end)
	ctx:OnState("Bathing", function(value)
		bathing = value == true
	end)
	ctx:OnState("BubblesAt", function(value)
		local at = tonumber(value) or 0
		if at <= 0 or Kit.Now() - at > SURGE_WINDOW then return end
		pourUntil = at + POUR_TIME
		if awake then
			puffs:Emit(16)
			floaters:Emit(24)
		end
	end)
	ctx:Every(0.5, function()
		awake = ctx:CameraDistance() <= AWAKE_RANGE
		Apply()
	end)

	--..Per frame: duck, foam, floating bubbles, the pour..--
	local blend, busy, pour = 0, 0, 0
	local foamResting = true
	ctx:Step(function(dt, now)
		local hb = hitbox.CFrame
		blend += ((bubblesOn and 1 or 0) - blend) * math.min(1, dt * 1.5)
		busy += (((bubblesOn or bathing) and 1 or 0) - busy) * math.min(1, dt * 1.2)

		--.. the duck: bob + roll + a slow turn, one rigid group
		local amp = DUCK_BOB * s * (1 + (BUSY_BOB - 1) * busy)
		local bob = amp * (math.sin(now * 2.9) * 0.7 + math.sin(now * 4.3 + 1.1) * 0.3)
		local roll = DUCK_ROLL * (1 + busy) * math.sin(now * 2.3 + 0.6)
		local pitch = DUCK_ROLL * 0.6 * (1 + busy) * math.sin(now * 1.9 + 2.0)
		local yaw = DUCK_TURN * math.sin(now * 0.45)
		PoseDuck(hb, bob, pitch, yaw, roll)

		--.. floating bubbles hover (higher while bubbling)
		for p, f in pairs(floats) do
			local y = (0.1 * math.sin(now * 0.9 + f.Phase) + FLOAT_RISE * blend * (0.5 + 0.5 * math.sin(now * 0.6 + f.Phase))) * s
			p.CFrame = hb * f.Rel * CFrame.new(0.06 * s * math.sin(now * 0.7 + f.Phase), y, 0)
		end

		--.. foam swells + loose bubbles jiggle while bubbling (rest once when it has settled)
		if blend > 0.002 then
			foamResting = false
			for p, f in pairs(foam) do
				local k = blend * (FOAM_SWELL + 0.04 * math.sin(now * 2.3 + f.Phase))
				local ky = blend * (FOAM_SWELL * 1.6 + 0.07 * math.sin(now * 2.9 + f.Phase))
				local size = f.Size * Vector3.new(1 + k, 1 + ky, 1 + k)
				p.Size = size
				p.CFrame = hb * f.Rel * CFrame.new(0, (size.Y - f.Size.Y) * 0.3, 0)
			end
			for p, f in pairs(loose) do
				local jiggle = Vector3.new(math.sin(now * 3.1 + f.Phase) * 0.04, math.sin(now * 2.2 + f.Phase) * 0.1 + 0.08, math.cos(now * 2.7 + f.Phase) * 0.04)
				p.CFrame = hb * f.Rel * CFrame.new(jiggle * (blend * s))
			end
		elseif not foamResting then
			foamResting = true
			RestFoam(hb)
		end

		--.. the tap pours after a switch-on
		local pouring = now < pourUntil
		pour += ((pouring and 1 or 0) - pour) * math.min(1, dt * 6)
		local alpha = 1 - (1 - STREAM_ALPHA) * pour
		if math.abs(stream.Transparency - alpha) > 0.002 then stream.Transparency = alpha end
		ripples.Enabled = pouring and awake
		local wantPour = pouring and awake and ctx:CameraDistance() <= NEAR_SOUND
		if wantPour and not pourLoop.IsPlaying then
			pourLoop:Play()
		elseif not wantPour and pourLoop.IsPlaying then
			pourLoop:Stop()
		end
	end)
end

--..Server events..--
function B.OnEvent(_model, action, payload, ctx)
	if action ~= "Splash" or type(payload) ~= "table" or typeof(payload.Position) ~= "Vector3" then return end
	local fx = ctx.BathFX
	if not fx or ctx:CameraDistance() > AWAKE_RANGE then return end
	--.. drop the splash onto the water surface under the given point
	local rel = fx.Fx.CFrame:PointToObjectSpace(payload.Position)
	fx.At.WorldPosition = fx.Fx.CFrame:PointToWorldSpace(Vector3.new(rel.X, 0.05, rel.Z))
	fx.Spray:Emit(payload.Big and 20 or 12)
	fx.Ring:Emit(payload.Big and 3 or 2)
	fx.Sound.PlaybackSpeed = 0.92 + math.random() * 0.18
	fx.Sound.TimePosition = 0
	fx.Sound:Play()
end

return B
