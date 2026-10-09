--[[
	Toilet  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the WORKING TOILET (server half: ServerStorage.FunBehaviours.Toilet; fun-builds/CONTRACT.md;
	model = fun-builds/models/build_Toilet.py).
	A flush = state Fun_FlushAt (server time). Every client plays it from that moment, so they all agree:
	  * the flush lever (Handle* parts) dips DIP_ANGLE about Pivot_Handle (the knob end goes down), holds, and
	    springs back
	  * a swirl of blue spins down the bowl: three sparkle trails orbiting Pivot_Bowl on a shrinking spiral
	    plus flat blue rings spinning and shrinking into the middle; the BowlWater darkens while it drains and
	    a ripple ring marks the refill
	  * FunAssets.Sfx.Click (the lever) + FunAssets.Sfx.Flush, only for a flush that just happened (a client
	    streaming in mid-flush sees the rest of it silently)
	Every build part it animates (Handle* CFrames, BowlWater Color) is put back (relative to where the Hitbox
	is NOW) on cleanup. Particle textures are the engine's built-in rbxasset:// ones (no asset ids).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local HANDLE_FALLBACK = Vector3.new(0.98, 3.42, 0.6)  -- authored Pivot_Handle of build_Toilet.py
local BOWL_FALLBACK = Vector3.new(0, 2.165, -0.42)    -- authored Pivot_Bowl
local DIP_ANGLE = math.rad(38)
local DIP_DOWN, DIP_HOLD, DIP_BACK = 0.12, 0.5, 0.95  -- seconds: pressed by, held until, back at rest by
local SWIRL_START, SWIRL_END = 0.15, 2.3              -- seconds the swirl runs
local FLUSH_TOTAL = 3.0                               -- seconds a flush lasts (refill ripple included)
local SOUND_WINDOW = 0.8                              -- a flush older than this when first seen plays silently
local SWIRL_RADIUS = 0.46                             -- authored start radius of the spiral (BowlWater is 1.0 x 1.2)
local SWIRL_TURNS = 2.2                               -- revolutions per second
local SWIRL_ARMS = 3
local WATER_DARK = Color3.fromRGB(28, 104, 196)
local SWIRL_COLOR = ColorSequence.new(Color3.fromRGB(70, 165, 245), Color3.fromRGB(165, 225, 255))
local AWAKE_RANGE = 120                               -- studs camera <-> toilet for particles
local SOUND_RANGE = 70

local B = {}
B.StepRange = 120

--..Helpers..--
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

local function Authored(model, name, fallback)
	local v = model:GetAttribute("Pivot_" .. name)
	return typeof(v) == "Vector3" and v or fallback
end

local function Smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

--.. the lever angle at time tau into a flush
local function DipAt(tau)
	if tau < 0 then return 0 end
	if tau < DIP_DOWN then return DIP_ANGLE * Smooth(tau / DIP_DOWN) end
	if tau < DIP_HOLD then return DIP_ANGLE end
	if tau < DIP_BACK then return DIP_ANGLE * (1 - Smooth((tau - DIP_HOLD) / (DIP_BACK - DIP_HOLD))) end
	return 0
end

--..Behaviour..--
function B.Client(model, ctx)
	local s = ctx.Scale
	local hitbox = Kit.Hitbox(model)
	local hb0 = hitbox.CFrame

	--..The lever rig (hitbox space: move-safe)..--
	local pivot = hb0:PointToObjectSpace(Kit.ToWorld(model, Authored(model, "Handle", HANDLE_FALLBACK)))
	local handle = {} -- [part] = CFrame relative to the pivot point (hitbox axes)
	local reach, tip = -1, nil
	for _, p in ipairs(Kit.Parts(model, "Handle")) do
		local rel = hb0:ToObjectSpace(p.CFrame)
		handle[p] = CFrame.new(pivot):Inverse() * rel
		local d = (rel.Position - pivot).Magnitude
		if d > reach then reach, tip = d, rel.Position end
	end
	--.. turning about (lever x down) by a positive angle swings the lever's free end downward
	local lever = tip and (tip - pivot) or Vector3.xAxis
	local axis = lever:Cross(-Vector3.yAxis)
	axis = axis.Magnitude > 1e-3 and axis.Unit or -Vector3.zAxis
	local function PoseHandle(hb, angle)
		local pose = hb * CFrame.new(pivot) * CFrame.fromAxisAngle(axis, angle)
		for p, rel in pairs(handle) do p.CFrame = pose * rel end
	end

	--..Bowl water colour..--
	local water = Kit.Part(model, "BowlWater")
	local waterColor = water and water.Color
	ctx:OnCleanup(function()
		if water and waterColor then water.Color = waterColor end
		if hitbox.Parent then PoseHandle(hitbox.CFrame, 0) end
	end)

	--..Effects host: a flat local part on the bowl water..--
	local bowlAt = Authored(model, "Bowl", BOWL_FALLBACK)
	local fx = ctx:Part({
		Name = "FlushFX",
		Transparency = 1,
		Size = Vector3.new(0.9 * s, 0.05, 1.1 * s),
		CFrame = Kit.CFrameToWorld(model, CFrame.new(bowlAt)) * CFrame.new(0, 0.03, 0),
	})
	local vortex = Emitter(fx, {
		Name = "Vortex",
		Texture = TEX_RING,
		Color = SWIRL_COLOR,
		Size = Seq(0, 1.0 * s, 1, 0.06 * s),
		Transparency = Seq(0, 0.9, 0.2, 0.25, 1, 1),
		Lifetime = NumberRange.new(0.6, 0.75),
		Rate = 9,
		Speed = NumberRange.new(0.02, 0.04),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, -- flat on the water
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-420, -300),
		LightEmission = 0.35,
		LightInfluence = 0.5,
		ZOffset = 0.2,
		EmissionDirection = Enum.NormalId.Top,
	})
	local arms, trails = {}, {}
	for i = 1, SWIRL_ARMS do
		local a = Instance.new("Attachment")
		a.Name = "SwirlArm" .. i
		a.Parent = fx
		arms[i] = a
		trails[i] = Emitter(a, {
			Name = "Swirl",
			Texture = TEX_SPARK,
			Color = SWIRL_COLOR,
			Size = Seq(0, 0.22 * s, 1, 0.04 * s),
			Transparency = Seq(0, 0.1, 1, 1),
			Lifetime = NumberRange.new(0.3, 0.42),
			Rate = 30,
			Speed = NumberRange.new(0, 0),
			LightEmission = 0.6,
			LightInfluence = 0.3,
			ZOffset = 0.3,
		})
	end
	local refill = Emitter(fx, {
		Name = "Refill",
		Texture = TEX_RING,
		Color = ColorSequence.new(Color3.fromRGB(215, 240, 255)),
		Size = Seq(0, 0.1 * s, 1, 1.0 * s),
		Transparency = Seq(0, 0.3, 1, 1),
		Lifetime = NumberRange.new(0.6, 0.8),
		Speed = NumberRange.new(0.02, 0.04),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		LightEmission = 0.3,
		ZOffset = 0.2,
		EmissionDirection = Enum.NormalId.Top,
	})

	--..Sounds..--
	local tipPart = Kit.Part(model, "FlushPlate") or fx
	local click = ctx:Sound(tipPart, FunAssets.Sfx.Click, {Name = "LeverClick", Volume = 0.45, RollOffMaxDistance = 40})
	local flush = ctx:Sound(fx, FunAssets.Sfx.Flush, {Name = "Flush", Volume = 0.6, RollOffMinDistance = 8, RollOffMaxDistance = SOUND_RANGE})

	--..State..--
	local flushAt, refilled, active = 0, true, false
	ctx:OnState("FlushAt", function(value)
		local at = tonumber(value) or 0
		if at <= 0 or at == flushAt then return end
		flushAt = at
		refilled = false
		local age = Kit.Now() - at
		-- age can be a hair negative when this client's server-time estimate trails the stamp (near-zero
		-- latency, e.g. a Studio solo test): still play it, the visuals simply wait out tau < 0 in the Step
		if age > -0.5 and age < SOUND_WINDOW and ctx:CameraDistance() <= SOUND_RANGE then
			click.PlaybackSpeed = 0.9
			click:Play()
			flush.TimePosition = math.max(age, 0)
			flush:Play()
		end
	end)

	local function SetSwirl(on)
		vortex.Enabled = on
		for _, e in ipairs(trails) do e.Enabled = on end
	end

	--..Per frame (only does work during a flush)..--
	ctx:Step(function(_dt, now)
		local tau = now - flushAt
		if flushAt <= 0 or tau < 0 or tau > FLUSH_TOTAL then
			if active then
				active = false
				SetSwirl(false)
				PoseHandle(hitbox.CFrame, 0)
				if water and waterColor then water.Color = waterColor end
			end
			return
		end
		active = true
		local hb = hitbox.CFrame
		PoseHandle(hb, DipAt(tau))

		--.. the swirl: arms orbit on a shrinking, sinking spiral
		local awake = ctx:CameraDistance() <= AWAKE_RANGE
		local swirling = tau >= SWIRL_START and tau < SWIRL_END
		SetSwirl(swirling and awake)
		if swirling then
			local k = (tau - SWIRL_START) / (SWIRL_END - SWIRL_START)
			local r = SWIRL_RADIUS * s * (1 - 0.85 * k)
			local spin = tau * SWIRL_TURNS * 2 * math.pi * (1 + 0.8 * k) -- speeds up as it drains
			for i, a in ipairs(arms) do
				local ang = spin + (i - 1) * 2 * math.pi / SWIRL_ARMS
				a.Position = Vector3.new(math.cos(ang) * r, 0.02 - 0.08 * s * k, math.sin(ang) * r * 1.15)
			end
		end

		--.. the water darkens while it drains, clears as it refills
		if water and waterColor then
			local w = math.sin(math.pi * math.clamp((tau - SWIRL_START) / (SWIRL_END - SWIRL_START + 0.5), 0, 1))
			water.Color = waterColor:Lerp(WATER_DARK, 0.75 * w)
		end
		if not refilled and tau >= SWIRL_END then
			refilled = true
			if awake then refill:Emit(2) end
		end
	end)
end

return B
