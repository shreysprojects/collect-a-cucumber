--[[
	Fountain  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLights
	Client half of the RUNNING FOUNTAIN (server half: ServerStorage.FunBehaviours.Fountain makes the water, jets
	and foam parts non-colliding so people can wade into the basin). Everything here is local VFX on one invisible
	anchor part at the build's authored origin, so no build part is touched and nothing needs restoring:
	  * the PLUME: droplets shoot up from Pivot_JetOrigin to just over Pivot_JetTop and fall back into the upper
	    bowl (Pivot_BowlWaterTop) - speed / lifetime solved from those pivots and one gravity G, so they land on
	    the water whatever the build's scale
	  * the five STREAMS: droplets ride the Jets mesh's five parabolas from the bowl lip down into the basin
	    (the curves of props/build_fountain.py _arc_points, re-solved here with the same gravity)
	  * SPLASH RINGS: flat expanding rings (built-in shockwave texture, lying on the water) where the streams hit
	    the basin water (Pivot_BasinWaterTop) and where the plume falls back into the bowl, a droplet kicked up
	    with each basin splash, and every PUFF_EVERY s a soft mist puff over a splash; a faint mist hangs over the
	    bowl all the time
	  * anyone walking through the basin water leaves ripple rings (checked every 0.3 s for every character)
	  * a looping water sound (FunAssets.Sfx.WaterLoop) only while the camera is within NEAR_SOUND studs
	Blender -> Roblox authored frame: (x, y, z) -> (x, z, -y); a stream at Blender angle a leaves along
	(cos a, 0, -sin a).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = {Sfx = {}}
pcall(function() FunAssets = require(Modules:WaitForChild("FunAssets", 15)) end)

--..Config..--
local G = 26                     -- AUTHORED studs/s^2 for every droplet (x ctx.Scale in the world; flight times are scale-free)
local PLUME_RATE = 12            -- droplets / s up the central plume
local PLUME_SPREAD = 11          -- degrees: the plume opens into an umbrella landing ~0.6 out from the finial
local PLUME_OVERSHOOT = 1.05     -- peak a hair over Pivot_JetTop
local STREAM_RATE = 2            -- droplets / s down EACH of the five streams
local DROP_SIZE = 0.13           -- AUTHORED studs
local BASIN_RING_EVERY = 0.4     -- s between splash rings where the streams land
local BOWL_RING_EVERY = 0.45     -- s between rings where the plume falls back
local PUFF_EVERY = 1.8           -- s between mist puffs over a basin splash
local RING_LIFT = 0.03           -- AUTHORED studs above the water plane
local BOWL_RING_R = {0.45, 0.72} -- AUTHORED radius band of the plume's splash rings (the finial is ~0.35 wide there)
local WADE_R = {1.15, 2.55}      -- AUTHORED radius band of basin water a character can wade in (pedestal .. wall)
local WADE_SPEED = 1.5           -- studs/s a character must move to leave ripples
local NEAR_SOUND = 40            -- studs camera <-> fountain: the water loop plays inside this ...
local FAR_SOUND = 46             -- ... and stops beyond this
local SOUND_VOLUME = 0.3
local WATER_COLOR = ColorSequence.new(Color3.fromRGB(228, 246, 255), Color3.fromRGB(160, 215, 250))
local RING_COLOR = Color3.fromRGB(230, 247, 255)
local MIST_COLOR = Color3.fromRGB(225, 240, 255)
local TEX_OVERRIDE = type(FunAssets.Textures) == "table" and FunAssets.Textures or {} -- the integrator may add verified images
local TEX = {
	Drop = TEX_OVERRIDE.Droplet or "rbxasset://textures/particles/explosion01_implosion_main.dds", -- soft round dot
	Ring = TEX_OVERRIDE.Ripple or "rbxasset://textures/particles/explosion01_shockwave_main.dds",  -- soft ring
	Mist = TEX_OVERRIDE.Mist or "rbxasset://textures/particles/smoke_main.dds",
}
--.. authored fallbacks when a template lacks the Pivot_* attributes
local DEFAULT_PIVOTS = {
	JetOrigin = Vector3.new(0, 3.62, 0), JetTop = Vector3.new(0, 4.20, 0),
	BowlWaterTop = Vector3.new(0, 2.50, 0), BasinWaterTop = Vector3.new(0, 0.72, 0),
}
--.. the five streams of the Jets mesh (build_fountain.py: JET_ANGLES, _arc_points; stream 4 is thrown shorter / flatter)
local JETS = {
	{Angle = 54, R0 = 1.50, DR = 0.88, Z0 = 2.52, Rise = 0.32, Z1 = 0.74},
	{Angle = 126, R0 = 1.50, DR = 0.88, Z0 = 2.52, Rise = 0.32, Z1 = 0.74},
	{Angle = 198, R0 = 1.50, DR = 0.88, Z0 = 2.52, Rise = 0.32, Z1 = 0.74},
	{Angle = 278, R0 = 1.50, DR = 0.70, Z0 = 2.52, Rise = 0.17, Z1 = 0.74},
	{Angle = 342, R0 = 1.50, DR = 0.88, Z0 = 2.52, Rise = 0.32, Z1 = 0.74},
}

local B = {}
B.StepRange = 180

--..Helpers..--
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

local function AuthoredPivot(model, name)
	local v = model:GetAttribute("Pivot_" .. name)
	return typeof(v) == "Vector3" and v or DEFAULT_PIVOTS[name]
end

--.. a stream's parabola (r = R0 + DR t, z = Z0 + v t - g t^2, through Z1 at t = 1 with its crest Rise over Z0)
--.. played in real time so its gravity is G: -> outward speed, upward speed (authored studs/s), flight time (s)
local function JetLaunch(jet)
	local d = jet.Z1 - jet.Z0
	local tc = (jet.Rise - math.sqrt(jet.Rise * jet.Rise - d * jet.Rise)) / d
	local v = 2 * jet.Rise / tc
	local g = jet.Rise / (tc * tc)
	local flight = math.sqrt(2 * g / G)
	return jet.DR / flight, v / flight, flight
end

local function Attach(parent, name, cf)
	local att = Instance.new("Attachment")
	att.Name = name
	att.CFrame = cf
	att.Parent = parent
	return att
end

--.. water droplets: stretched along their flight, falling at G. o = {Rate, Speed (world), Spread, Life, Direction, Size}
local function Droplets(parent, scale, o)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = o.Name or "FunDroplets"
	pe.Texture = TEX.Drop
	pe.Rate = o.Rate
	pe.Lifetime = NumberRange.new(o.Life * 0.94, o.Life)
	pe.Speed = NumberRange.new(o.Speed * 0.96, o.Speed * 1.03)
	pe.SpreadAngle = Vector2.new(o.Spread, o.Spread)
	pe.EmissionDirection = o.Direction or Enum.NormalId.Front
	pe.Acceleration = Vector3.new(0, -G * scale, 0)
	pe.Drag = 0
	local s = (o.Size or DROP_SIZE) * scale
	pe.Size = NumberSequence.new({kp(0, s * 0.8), kp(0.5, s), kp(1, s * 0.7)})
	pe.Transparency = NumberSequence.new({kp(0, 0.2), kp(0.8, 0.25), kp(1, 0.75)})
	pe.Color = WATER_COLOR
	pe.LightEmission = 0.35
	pe.LightInfluence = 0.6
	pe.Orientation = Enum.ParticleOrientation.VelocityParallel
	pcall(function() pe.Squash = NumberSequence.new(0.6) end) -- streaks along the flight (newer engine property)
	pe.Parent = parent
	return pe
end

--.. flat rings lying on the water (VelocityPerpendicular + a tiny upward speed), emitted by hand with :Emit
local function Rings(parent, scale, size0, size1, life, alpha)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "FunRings"
	pe.Texture = TEX.Ring
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(life * 0.9, life * 1.1)
	pe.Speed = NumberRange.new(0.02)
	pe.SpreadAngle = Vector2.zero
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	pe.Rotation = NumberRange.new(0, 360)
	pe.Size = NumberSequence.new({kp(0, size0 * scale), kp(1, size1 * scale)})
	pe.Transparency = NumberSequence.new({kp(0, alpha), kp(0.6, (1 + alpha) * 0.5 + 0.1), kp(1, 1)})
	pe.Color = ColorSequence.new(RING_COLOR)
	pe.LightEmission = 0.3
	pe.LightInfluence = 0.7
	pe.Parent = parent
	return pe
end

--.. soft mist: slow, big, almost clear puffs
local function Mist(parent, scale, rate)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "FunMist"
	pe.Texture = TEX.Mist
	pe.Rate = rate
	pe.Lifetime = NumberRange.new(2.2, 3.2)
	pe.Speed = NumberRange.new(0.3 * scale, 0.7 * scale)
	pe.SpreadAngle = Vector2.new(70, 70)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Acceleration = Vector3.new(0, 0.2 * scale, 0)
	pe.Drag = 0.8
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-20, 20)
	pe.Size = NumberSequence.new({kp(0, 0.7 * scale), kp(1, 2.0 * scale)})
	pe.Transparency = NumberSequence.new({kp(0, 1), kp(0.25, 0.86), kp(1, 1)})
	pe.Color = ColorSequence.new(MIST_COLOR)
	pe.LightEmission = 0.15
	pe.LightInfluence = 0.8
	pe.Parent = parent
	return pe
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local scale = ctx.Scale
	local jetOrigin = AuthoredPivot(model, "JetOrigin")
	local jetTop = AuthoredPivot(model, "JetTop")
	local bowlTop = AuthoredPivot(model, "BowlWaterTop")
	local basinTop = AuthoredPivot(model, "BasinWaterTop")

	--.. every effect hangs off one invisible local part at the authored origin: attachment positions = authored * scale
	local anchor = ctx:Part({Name = "FunFountainFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = Kit.Origin(model)})

	--..Plume..--
	local rise = math.max(0.2, (jetTop.Y - jetOrigin.Y) * PLUME_OVERSHOOT)
	local fall = rise + math.max(0, jetOrigin.Y - bowlTop.Y)
	local plumeLife = math.sqrt(2 * rise / G) + math.sqrt(2 * fall / G)
	local plumeAt = Attach(anchor, "Plume", CFrame.new(Vector3.new(0, jetOrigin.Y, 0) * scale))
	Droplets(plumeAt, scale, {
		Name = "Plume", Rate = PLUME_RATE, Speed = math.sqrt(2 * G * rise) * scale, Spread = PLUME_SPREAD,
		Life = plumeLife, Direction = Enum.NormalId.Top,
	})

	--..Streams (bowl lip -> basin) + where they land..--
	local landings = {} -- authored points on the basin water
	for i, jet in ipairs(JETS) do
		local out, up, flight = JetLaunch(jet)
		local a = math.rad(jet.Angle)
		local radial = Vector3.new(math.cos(a), 0, -math.sin(a))
		local lip = (radial * jet.R0 + Vector3.new(0, jet.Z0, 0)) * scale
		local velocity = radial * out + Vector3.new(0, up, 0)
		local at = Attach(anchor, "Stream" .. i, CFrame.lookAt(lip, lip + velocity.Unit))
		Droplets(at, scale, {Name = "Stream", Rate = STREAM_RATE, Speed = velocity.Magnitude * scale, Spread = 2.5, Life = flight})
		table.insert(landings, radial * (jet.R0 + jet.DR - 0.08))
	end

	--..Splash rings, kicks, mist..--
	local basinY = basinTop.Y + RING_LIFT
	local bowlY = bowlTop.Y + RING_LIFT
	local basinAt = Attach(anchor, "BasinSplash", CFrame.new(Vector3.new(landings[1].X, basinY, landings[1].Z) * scale))
	local basinRing = Rings(basinAt, scale, 0.22, 1.15, 0.8, 0.3)
	local kick = Droplets(basinAt, scale, {Name = "Kick", Rate = 0, Speed = 2.4 * scale, Spread = 30, Life = 0.34, Direction = Enum.NormalId.Top, Size = 0.1})
	local puff = Mist(basinAt, scale, 0)
	local bowlAt = Attach(anchor, "BowlSplash", CFrame.new(Vector3.new(BOWL_RING_R[1], bowlY, 0) * scale))
	local bowlRing = Rings(bowlAt, scale, 0.14, 0.62, 0.6, 0.35)
	local mistAt = Attach(anchor, "Mist", CFrame.new(Vector3.new(0, bowlTop.Y + 0.35, 0) * scale))
	Mist(mistAt, scale, 1.2)

	--..Water sound (near only)..--
	local soundAt = Attach(anchor, "Sound", CFrame.new(Vector3.new(0, bowlTop.Y * 0.6, 0) * scale))
	local water
	if FunAssets.Sfx.WaterLoop then
		local ok, sound = pcall(function()
			return ctx:Sound(soundAt, FunAssets.Sfx.WaterLoop, {
				Name = "FunWater", Looped = true, Volume = SOUND_VOLUME, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND,
			})
		end)
		if ok then water = sound end
	end
	if water then
		local function SyncSound()
			local d = ctx:CameraDistance()
			if d <= NEAR_SOUND and not water.IsPlaying then
				water:Play()
			elseif d > FAR_SOUND and water.IsPlaying then
				water:Stop()
			end
		end
		SyncSound()
		ctx:Every(0.5, SyncSound)
	end

	--..Every frame: splash timers (asleep far away with the rest of ctx:Step)..--
	local rng = Random.new()
	local basinClock, bowlClock, puffClock = 0, BOWL_RING_EVERY * 0.5, 0
	local jetIndex = 0
	ctx:Step(function(dt)
		basinClock += dt
		bowlClock += dt
		puffClock += dt
		if basinClock >= BASIN_RING_EVERY then
			basinClock = 0
			jetIndex = (jetIndex + rng:NextInteger(1, #landings - 1)) % #landings -- a different stream every time
			local p = landings[jetIndex + 1]
			local jx, jz = rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.08, 0.08)
			basinAt.Position = Vector3.new(p.X + jx, basinY, p.Z + jz) * scale
			basinRing:Emit(1)
			kick:Emit(1)
			if puffClock >= PUFF_EVERY then
				puffClock = 0
				puff:Emit(1)
			end
		end
		if bowlClock >= BOWL_RING_EVERY then
			bowlClock = 0
			local a = rng:NextNumber(0, 2 * math.pi)
			local r = rng:NextNumber(BOWL_RING_R[1], BOWL_RING_R[2])
			bowlAt.Position = Vector3.new(math.cos(a) * r, bowlY, math.sin(a) * r) * scale
			bowlRing:Emit(1)
		end
	end)

	--..Wading ripples: anyone moving through the basin water..--
	local lastRipple = {} -- [player] = os.clock()
	ctx:Every(0.3, function()
		if ctx:CameraDistance() > B.StepRange then return end
		local origin = Kit.Origin(model)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and now - (lastRipple[player] or 0) > 0.35 then
				local p = origin:PointToObjectSpace(root.Position) / scale
				local r = math.sqrt(p.X * p.X + p.Z * p.Z)
				local v = root.AssemblyLinearVelocity
				if r > WADE_R[1] and r < WADE_R[2] and p.Y > basinTop.Y and p.Y < basinTop.Y + 5 / scale
					and Vector3.new(v.X, 0, v.Z).Magnitude > WADE_SPEED then
					lastRipple[player] = now
					basinAt.Position = Vector3.new(p.X, basinY, p.Z) * scale
					basinRing:Emit(1)
				end
			end
		end
		for player in pairs(lastRipple) do
			if player.Parent == nil then lastRipple[player] = nil end
		end
	end)
end

return B
