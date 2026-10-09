--[[
	Aquarium  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package HomeDecor
	Client half of the fish tank (server half: ServerStorage.FunBehaviours.Aquarium; fun-builds/CONTRACT.md).
	  * FIVE FISH built from local parts (ellipsoid body, eyes with pupils, a dorsal fin, a two-wedge fan tail that
	    wags faster the faster the fish swims, plus each species' markings): a clownfish, a blue tang, a yellow
	    tang, a royal gramma and a neon tetra. Each swims its own smooth closed loop (an ellipse with a vertical
	    wave, speeding up and gliding) inside the water box Pivot_TankMin..Pivot_TankMax. The loops were fitted
	    offline to the authored tank (DESIGN_MIN/MAX): no fish touches the glass, the gravel, the castle, the chest
	    or another fish; a different box is mapped onto them linearly. Positions are a pure function of the
	    server clock (Kit.Now), so every client sees the same fish in the same place.
	  * BUBBLES trickle from the treasure chest (Pivot_Bubbler) and pop at the water surface; every LID_PERIOD s
	    the chest lid (ChestLid, hinged at Pivot_ChestHinge) pops open and lets out a burst of big bubbles
	  * the PLANTS (Plant<N>Leaf<M>) sway in the current about their clump's base (Pivot_Plant<N>), the castle
	    flag (CastleFlag, Pivot_Flag) waves, and a cool PointLight under the hood (Pivot_Light) lights the water
	  * FEEDING (state Fun_FedAt = the server time someone pressed "Feed fish"): the FeedFlap flips open, 12 food
	    flakes sprinkle onto the water under it (little rings where they land) and drift apart, and the fish rush
	    up and gobble them - 2-3 each, nearest first, nose-up while they nibble; every flake vanishes with a gulp
	    and a few bubbles - then swim back into their loops. The flakes and the plan are seeded by Fun_FedAt, so a
	    player who streams in half-way sees the same moment as everyone else.
	Sounds (FunAssets.Sfx, all skipped while the player's SFXEnabled attribute is false): BubblesLoop near the
	tank, Click for the flap, Splash when the flakes land, Gulp per flake eaten.
	Every build part it moves (leaves, flag, chest lid, feed flap) goes back to rest relative to the build's
	current hitbox on cleanup. Particle textures are the engine's built-in rbxasset:// ones.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

local player = Players.LocalPlayer

--..Config..--
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds" -- soft ring: bubbles + landing rings
local DESIGN_MIN = Vector3.new(-2.90, 3.62, -1.20) -- the water box the fish loops were fitted in (authored TankMin/Max)
local DESIGN_MAX = Vector3.new(2.90, 5.94, 1.20)
local FEED_FALLBACK = Vector3.new(0, 5.94, -0.745)
local BUBBLER_FALLBACK = Vector3.new(1.72, 4.02, -0.66)
local LIGHT_FALLBACK = Vector3.new(0, 5.97, 0.3)
local LIGHT_COLOR = Color3.fromRGB(190, 232, 255)
local LIGHT_BRIGHTNESS = 1.2
local LIGHT_RANGE = 9            -- authored studs (x Scale)
local NEAR_SOUND = 45            -- studs camera <-> tank for the bubbling loop
local TAIL_WAG = 0.38            -- rad each side
local YAW_RATE = 7               -- 1/s: how fast a fish turns toward where it is heading
local PITCH_RATE = 5
local PITCH_MAX = 0.5
local NIBBLE_PITCH = 0.45        -- nose up while nibbling a flake
local SPACING = 0.45             -- authored studs: fish centres closer than this get nudged apart (only at the food)
local WALL_MARGIN = Vector3.new(0.35, 0.3, 0.28) -- authored: fish centres keep this far inside the water box
local SURFACE_MARGIN = 0.12      -- ... and this far under the surface
--.. plants / flag / chest lid / feed flap
local SWAY_AMP = math.rad(5)
local SWAY_PERIOD = 3.6
local FLAG_AMP = 0.35
local FLAG_PERIOD = 1.3
local LID_PERIOD = 7.0           -- s between chest-lid pops (server clock)
local LID_SHUT = math.rad(-22)   -- rest: shut (the authored lid is 24 degrees ajar)
local LID_OPEN = math.rad(22)    -- popped open: 46 degrees
local LID_TIMES = {0.22, 1.1, 1.6} -- open by, start closing, shut by (s into the cycle)
local FLAP_OPEN = math.rad(68)
local FLAP_TIMES = {0.25, 1.2, 1.55} -- open by, start closing, shut by (s after Fun_FedAt)
--.. feeding (seconds after Fun_FedAt)
local N_FLAKES = 12
local DROP_FROM, DROP_TO = 0.12, 0.6 -- flakes leave the flap over this window
local DROP_HEIGHT = 0.45         -- authored studs above the water they fall from
local FALL_TIME = 0.35
local FLAKE_DRIFT_TAU = 0.9      -- s: how fast the flakes spread on the surface
local RUSH_START, RUSH_STAGGER = 0.45, 0.13
local APPROACH, NIBBLE, MOVE, LINGER, RETURN = 0.85, 0.45, 0.55, 0.25, 1.3
local FEED_TIME = 6.5            -- after this nothing of a feeding is left
local NIBBLE_DEPTH = 0.17        -- authored studs: a feeding fish's centre under its flake
local FLAKE_SIZE = Vector3.new(0.13, 0.05, 0.1) -- authored (x Scale)
local FLAKE_COLORS = {
	Color3.fromRGB(242, 120, 48), Color3.fromRGB(217, 68, 60), Color3.fromRGB(242, 193, 61),
	Color3.fromRGB(120, 190, 70), Color3.fromRGB(200, 150, 90),
}
local FLAKE_AREA_MIN = Vector3.new(-2.35, 0, -0.98) -- design box XZ the flakes may drift in (clear of the castle)
local FLAKE_AREA_MAX = Vector3.new(2.35, 0, 0.2)
local WHITE = Color3.fromRGB(247, 247, 242)
local INK = Color3.fromRGB(35, 38, 44)

--.. the fish: Loop = design-box ellipse (C centre, RX/RZ radii, Rot degrees, RY/KY/PY vertical wave, Period s per
--.. loop, Dir, Glide/GlidePeriod: a time warp that speeds up and glides, needs Glide * Period < GlidePeriod),
--.. Meals = flakes it eats per feeding (they add up to N_FLAKES), Look = authored proportions + colours
local FISH = {
	{Name = "Clown", Meals = 3,
		Loop = {C = Vector3.new(1.10, 4.55, 0.52), RX = 1.05, RZ = 0.34, Rot = 6, RY = 0.14, KY = 2, PY = 0.5,
			Period = 12.0, Dir = 1, Glide = 0.22, GlidePeriod = 4.7, Phase = 0.0},
		Look = {W = 0.24, H = 0.32, L = 0.66, Body = "ff7a1a", Fin = "ff9a3c", Tail = "ff9a3c", Stripes = {-0.2, 0.12}, Stripe = "f7f7f2"}},
	{Name = "Tang", Meals = 3,
		Loop = {C = Vector3.new(1.05, 5.00, -0.62), RX = 1.20, RZ = 0.30, Rot = 0, RY = 0.18, KY = 1, PY = 1.2,
			Period = 13.0, Dir = -1, Glide = 0.22, GlidePeriod = 5.1, Phase = 1.3},
		Look = {W = 0.20, H = 0.44, L = 0.74, Body = "2f6fe0", Fin = "1b2f73", Tail = "f2c13d", Anal = true}},
	{Name = "Yellow", Meals = 2,
		Loop = {C = Vector3.new(1.05, 5.38, 0.52), RX = 1.10, RZ = 0.32, Rot = -5, RY = 0.10, KY = 1, PY = 0.0,
			Period = 14.0, Dir = -1, Glide = 0.22, GlidePeriod = 4.3, Phase = 2.4},
		Look = {W = 0.18, H = 0.50, L = 0.66, Body = "ffd23a", Fin = "ffe066", Tail = "ffe066", Snout = true, Anal = true}},
	{Name = "Gramma", Meals = 2,
		Loop = {C = Vector3.new(-1.65, 4.72, -0.45), RX = 0.60, RZ = 0.40, Rot = -6, RY = 0.18, KY = 1, PY = 2.0,
			Period = 9.0, Dir = -1, Glide = 0.22, GlidePeriod = 3.9, Phase = 4.1},
		Look = {W = 0.18, H = 0.30, L = 0.60, Body = "a24fe0", Fin = "a24fe0", Tail = "f7cf2f", Back = "f7cf2f"}},
	{Name = "Tetra", Meals = 2,
		Loop = {C = Vector3.new(0.00, 5.66, -0.58), RX = 2.20, RZ = 0.34, Rot = 0, RY = 0.05, KY = 2, PY = 0.7,
			Period = 12.0, Dir = 1, Glide = 0.22, GlidePeriod = 5.3, Phase = 0.9},
		Look = {W = 0.13, H = 0.22, L = 0.52, Body = "b8d4ee", Fin = "d6e6f5", Tail = "d6e6f5", Neon = "2fd9ff", Belly = "e8413a"}},
}

local B = {}
B.StepRange = 140

--..Helpers..--
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

local function Smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function LerpAngle(a, b, f)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * f
end

local function SameCFrame(a, b)
	return (a.Position - b.Position).Magnitude < 1e-3 and a.LookVector:Dot(b.LookVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
end

local function SfxOn()
	return player:GetAttribute("SFXEnabled") ~= false
end

--.. a local-only part of any class (ctx:Part only makes Parts; fins and tails are WedgeParts)
local function LocalPart(ctx, className, props)
	local p = Instance.new(className)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = workspace.CurrentCamera
	ctx:Add(p)
	return p
end

local function Ellipsoid(ctx, size, color, name, material)
	local p = LocalPart(ctx, "Part", {Name = name, Size = size, Color = color, Material = material or Enum.Material.SmoothPlastic})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function Ball(ctx, d, color, name)
	return LocalPart(ctx, "Part", {Name = name, Shape = Enum.PartType.Ball, Size = Vector3.one * d, Color = color})
end

local function Emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_RING
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Top
	e.LightEmission = 0.3
	e.LightInfluence = 0.5
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

--..Fish..--
--.. builds one fish from local parts: {Spec, Body = {{part, offset}}, Tail = {{part, offset from the tail root}},
--.. TailRoot}; nose toward -Z, up +Y, k = studs per authored unit (Scale)
local function BuildFish(ctx, spec, k)
	local look = spec.Look
	local w0, h0, l0 = look.W, look.H, look.L
	local W, H, L = w0 * k, h0 * k, l0 * k
	local fish = {Spec = spec, Body = {}, Tail = {}, TailRoot = CFrame.new(0, 0, L * 0.42)}
	local function body(part, offset) table.insert(fish.Body, {part, offset}) end
	local bodyColor = Color3.fromHex(look.Body)
	local finColor = Color3.fromHex(look.Fin)
	body(Ellipsoid(ctx, Vector3.new(W, H, L), bodyColor, "FishBody"), CFrame.identity)
	--.. markings
	for _, z0 in ipairs(look.Stripes or {}) do
		local f = math.sqrt(math.max(0.05, 1 - (2 * z0) ^ 2)) -- the body's cross-section there
		body(Ellipsoid(ctx, Vector3.new(w0 * f + 0.03, h0 * f + 0.03, 0.07) * k, Color3.fromHex(look.Stripe), "FishStripe"),
			CFrame.new(0, 0, z0 * L))
	end
	if look.Back then -- the royal gramma's yellow back half
		body(Ellipsoid(ctx, Vector3.new(w0 + 0.012, h0 * 0.94, l0 * 0.56) * k, Color3.fromHex(look.Back), "FishBack"),
			CFrame.new(0, 0, 0.2 * L))
	end
	if look.Neon then -- the neon tetra's glowing stripe + red belly
		body(Ellipsoid(ctx, Vector3.new(w0 + 0.012, 0.05, l0 * 0.72) * k, Color3.fromHex(look.Neon), "FishNeon", Enum.Material.Neon),
			CFrame.new(0, 0.03 * k, -0.02 * L))
		body(Ellipsoid(ctx, Vector3.new(w0 + 0.006, h0 * 0.4, l0 * 0.45) * k, Color3.fromHex(look.Belly), "FishBelly"),
			CFrame.new(0, -0.045 * k, 0.14 * L))
	end
	if look.Snout then -- the yellow tang's pointed snout
		body(Ellipsoid(ctx, Vector3.new(W * 0.5, H * 0.2, L * 0.28), bodyColor, "FishSnout"), CFrame.new(0, -H * 0.05, -L * 0.48))
	end
	--.. eyes (white + pupil)
	local eye = math.max(0.09, 0.3 * h0) * k
	local ex = W * 0.35
	for _, s in ipairs({-1, 1}) do
		body(Ball(ctx, eye, WHITE, "FishEye"), CFrame.new(s * ex, H * 0.12, -L * 0.3))
		body(Ball(ctx, eye * 0.6, INK, "FishPupil"), CFrame.new(s * (ex + eye * 0.3), H * 0.12, -L * 0.3 - eye * 0.1))
	end
	--.. fins: a dorsal wedge rising toward the back (+ an anal fin under the tall ones)
	local dh, dl = H * 0.36, L * 0.46
	body(LocalPart(ctx, "WedgePart", {Name = "FishDorsal", Size = Vector3.new(0.05 * k, dh, dl), Color = finColor}),
		CFrame.new(0, H * 0.41 + dh * 0.5, 0))
	if look.Anal then
		body(LocalPart(ctx, "WedgePart", {Name = "FishAnal", Size = Vector3.new(0.05 * k, dh * 0.6, dl * 0.6), Color = finColor}),
			CFrame.new(0, -(H * 0.4 + dh * 0.3), 0.1 * L) * CFrame.Angles(0, 0, math.pi))
	end
	--.. tail: two wedges fanning out behind the root (the lower one upside down)
	local tl, th = L * 0.32, H * 0.46
	local tailColor = Color3.fromHex(look.Tail)
	table.insert(fish.Tail, {LocalPart(ctx, "WedgePart", {Name = "FishTail", Size = Vector3.new(0.05 * k, th, tl), Color = tailColor}),
		CFrame.new(0, th * 0.5, tl * 0.5)})
	table.insert(fish.Tail, {LocalPart(ctx, "WedgePart", {Name = "FishTail", Size = Vector3.new(0.05 * k, th, tl), Color = tailColor}),
		CFrame.new(0, -th * 0.5, tl * 0.5) * CFrame.Angles(0, 0, math.pi)})
	return fish
end

--.. a loop at server time t -> design-box position, velocity (design studs / s)
local function LoopAt(loop, t)
	local w, w2 = 2 * math.pi / loop.Period, 2 * math.pi / loop.GlidePeriod
	local progress = w * t + loop.Glide * math.sin(w2 * t)
	local rate = loop.Dir * (w + loop.Glide * w2 * math.cos(w2 * t))
	local s = loop.Dir * progress + loop.Phase
	local a = math.rad(loop.Rot)
	local ca, sa = math.cos(a), math.sin(a)
	local ex, ez = loop.RX * math.cos(s), loop.RZ * math.sin(s)
	local dex, dez = -loop.RX * math.sin(s), loop.RZ * math.cos(s)
	local wave = loop.KY * s + loop.PY
	local pos = Vector3.new(loop.C.X + ex * ca - ez * sa, loop.C.Y + loop.RY * math.sin(wave), loop.C.Z + ex * sa + ez * ca)
	local vel = Vector3.new(dex * ca - dez * sa, loop.RY * loop.KY * math.cos(wave), dex * sa + dez * ca) * rate
	return pos, vel
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local scale = ctx.Scale
	local home = hitbox.CFrame
	local origin = Kit.Origin(model)
	local rotation = origin.Rotation
	local timeOffset = (home.Position.X * 0.61 + home.Position.Z * 0.37) % 60 -- neighbouring tanks aren't in lockstep

	--..The water box: design box -> this build's Pivot_TankMin/Max (authored)..--
	local boxMin = model:GetAttribute("Pivot_TankMin")
	local boxMax = model:GetAttribute("Pivot_TankMax")
	if typeof(boxMin) ~= "Vector3" or typeof(boxMax) ~= "Vector3" then boxMin, boxMax = DESIGN_MIN, DESIGN_MAX end
	local boxK = (boxMax - boxMin) / (DESIGN_MAX - DESIGN_MIN)
	local function Map(p) return boxMin + (p - DESIGN_MIN) * boxK end
	local surfaceY = boxMax.Y
	local function Authored(name, fallback)
		local v = model:GetAttribute("Pivot_" .. name)
		return typeof(v) == "Vector3" and v or fallback
	end
	local feedPoint = Authored("Feed", FEED_FALLBACK)
	local bubbler = Authored("Bubbler", BUBBLER_FALLBACK)
	local areaMin, areaMax = Map(FLAKE_AREA_MIN), Map(FLAKE_AREA_MAX)
	local function World(p) return origin * CFrame.new(p * scale) end -- authored point -> world CFrame (authored axes)

	--..Build parts we animate: rest = hitbox-relative, restored on cleanup..--
	local rest = {} -- [part] = hitbox-relative CFrame
	local function Remember(part) rest[part] = home:ToObjectSpace(part.CFrame) end
	--.. a rig about an authored pivot: {Parts, Rel (pivot-relative), Pivot (world CFrame, authored axes)}
	local function Rig(parts, pivotName, fallback)
		local p = model:GetAttribute("Pivot_" .. pivotName)
		if typeof(p) ~= "Vector3" then p = fallback end
		if not p or #parts == 0 then return nil end
		local pivot = CFrame.new(Kit.ToWorld(model, p)) * rotation
		local rig = {Parts = parts, Rel = {}, Pivot = pivot}
		for i, part in ipairs(parts) do
			Remember(part)
			rig.Rel[i] = pivot:ToObjectSpace(part.CFrame)
		end
		return rig
	end

	--.. plants: one rig per clump, each leaf with its own phase
	local clumps = {}
	for _, part in ipairs(Kit.Parts(model, "Plant")) do
		local n, m = part.Name:match("^Plant(%d+)Leaf(%d+)$")
		if n then
			n, m = tonumber(n), tonumber(m)
			clumps[n] = clumps[n] or {}
			table.insert(clumps[n], {Part = part, Index = m})
		end
	end
	local leaves = {} -- {Part, Rel, Pivot, Phase}
	for n, list in pairs(clumps) do
		local parts = {}
		for _, item in ipairs(list) do table.insert(parts, item.Part) end
		local rig = Rig(parts, "Plant" .. n, nil)
		if rig then
			for i, item in ipairs(list) do
				table.insert(leaves, {Part = item.Part, Rel = rig.Rel[i], Pivot = rig.Pivot, Phase = n * 1.1 + item.Index * 0.45})
			end
		end
	end
	local flagPart = Kit.Part(model, "CastleFlag")
	local flagRig = flagPart and Rig({flagPart}, "Flag", nil)
	local lidPart = Kit.Part(model, "ChestLid")
	local lidRig = lidPart and Rig({lidPart}, "ChestHinge", nil)
	local flapParts = {}
	for _, name in ipairs({"FeedFlap", "FeedFlapTab"}) do
		local part = Kit.Part(model, name)
		if part then table.insert(flapParts, part) end
	end
	local flapRig = Rig(flapParts, "FeedHinge", nil)
	local posed = false

	--..Effects host: an invisible local part at the authored origin (attachments in authored axes)..--
	local fx = ctx:Part({Name = "AquariumFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = origin})
	local function Attach(name, authored)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = authored * scale
		a.Parent = fx
		return a
	end
	local rise = math.max(0.3, surfaceY - bubbler.Y) -- authored studs from the bubbler to the surface
	local bubbleAt = Attach("Bubbler", bubbler)
	local trickle = Emitter(bubbleAt, {
		Name = "Trickle",
		Color = ColorSequence.new(Color3.fromRGB(235, 250, 255)),
		Size = NumberSequence.new({kp(0, 0.07 * scale), kp(1, 0.12 * scale)}),
		Transparency = NumberSequence.new({kp(0, 0.15), kp(0.9, 0.25), kp(1, 1)}),
		Speed = NumberRange.new(1.0 * scale),
		Lifetime = NumberRange.new(rise / 1.0 * 0.97, rise / 1.0),
		SpreadAngle = Vector2.new(6, 6),
		Rate = 3,
		ZOffset = 0.5, -- draw over the translucent water they rise through
	})
	local burst = Emitter(bubbleAt, {
		Name = "Burst",
		Color = ColorSequence.new(Color3.fromRGB(240, 252, 255)),
		Size = NumberSequence.new({kp(0, 0.12 * scale), kp(1, 0.2 * scale)}),
		Transparency = NumberSequence.new({kp(0, 0.1), kp(0.9, 0.2), kp(1, 1)}),
		Speed = NumberRange.new(1.4 * scale),
		Lifetime = NumberRange.new(rise / 1.4 * 0.95, rise / 1.4),
		SpreadAngle = Vector2.new(14, 14),
		ZOffset = 0.5,
	})
	local gulpAt = Attach("Gulp", feedPoint)
	local gulp = Emitter(gulpAt, {
		Name = "Gulp",
		Color = ColorSequence.new(Color3.fromRGB(240, 252, 255)),
		Size = NumberSequence.new({kp(0, 0.05 * scale), kp(1, 0.09 * scale)}),
		Transparency = NumberSequence.new({kp(0, 0.15), kp(1, 1)}),
		Speed = NumberRange.new(0.3 * scale, 0.6 * scale),
		Lifetime = NumberRange.new(0.3, 0.45),
		SpreadAngle = Vector2.new(35, 35),
		ZOffset = 0.5,
	})
	local ringAt = Attach("Ring", feedPoint)
	local ring = Emitter(ringAt, {
		Name = "LandRing",
		Color = ColorSequence.new(Color3.fromRGB(225, 245, 255)),
		Size = NumberSequence.new({kp(0, 0.1 * scale), kp(1, 0.55 * scale)}),
		Transparency = NumberSequence.new({kp(0, 0.35), kp(1, 1)}),
		Speed = NumberRange.new(0.02),
		Lifetime = NumberRange.new(0.6, 0.8),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, -- lies flat on the water
		Rotation = NumberRange.new(0, 360),
		ZOffset = 0.3,
	})
	--.. the tank light
	local lightAt = Attach("Light", Authored("Light", LIGHT_FALLBACK))
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Brightness = LIGHT_BRIGHTNESS
	light.Range = LIGHT_RANGE * scale
	light.Shadows = false
	light.Parent = lightAt

	--..Sounds..--
	local bubbleLoop = ctx:Sound(fx, FunAssets.Sfx.BubblesLoop, {Name = "Bubbles", Looped = true, Volume = 0.14,
		RollOffMinDistance = 5, RollOffMaxDistance = NEAR_SOUND})
	local click = ctx:Sound(fx, FunAssets.Sfx.Click, {Name = "Click", Volume = 0.35, RollOffMaxDistance = 40})
	local splash = ctx:Sound(fx, FunAssets.Sfx.Splash, {Name = "Sprinkle", Volume = 0.16, PlaybackSpeed = 1.9, RollOffMaxDistance = 40})
	local gulpSound = ctx:Sound(fx, FunAssets.Sfx.Gulp, {Name = "Gulp", Volume = 0.12, RollOffMaxDistance = 35})
	local function Play(sound, pitch)
		if not SfxOn() or ctx:CameraDistance() > NEAR_SOUND then return end
		if pitch then sound.PlaybackSpeed = pitch end
		sound.TimePosition = 0
		sound:Play()
	end
	ctx:Every(0.5, function()
		local want = SfxOn() and ctx:CameraDistance() <= NEAR_SOUND
		if want and not bubbleLoop.IsPlaying then
			bubbleLoop:Play()
		elseif not want and bubbleLoop.IsPlaying then
			bubbleLoop:Stop()
		end
		local awake = ctx:CameraDistance() <= B.StepRange
		trickle.Enabled = awake
		light.Enabled = awake
	end)

	--..Fish..--
	local fishes = {}
	for _, spec in ipairs(FISH) do
		local fish = BuildFish(ctx, spec, scale)
		local _, vel = LoopAt(spec.Loop, Kit.Now() + timeOffset)
		fish.Yaw = math.atan2(-vel.X, -vel.Z)
		fish.Pitch = 0
		fish.Wag = math.random() * 6.28
		table.insert(fishes, fish)
	end
	local moveParts, moveCFrames = {}, {}

	--..Flakes: a pool of local parts, shown only during a feeding..--
	local flakeParts = {}
	for i = 1, N_FLAKES do
		flakeParts[i] = ctx:Part({Name = "FishFlake", Size = FLAKE_SIZE * scale, Transparency = 1, Material = Enum.Material.SmoothPlastic,
			CFrame = World(feedPoint)})
	end

	--..Feeding plan (pure function of Fun_FedAt: identical on every client)..--
	local feed = nil
	local function MakeFeed(t0)
		local rng = Random.new(math.floor((t0 * 1000) % 2147483000) + 1)
		local f = {T0 = t0, Flakes = {}, Plans = {}, Landed = {}, Eaten = {}, Rang = false, FlapDone = false}
		--.. every flake drifts to its own slot across the surface (shuffled, so the drop order doesn't sweep left to
		--.. right): the fish spread out along the tank instead of piling up under the flap
		local slots = {}
		for i = 1, N_FLAKES do slots[i] = i end
		for i = N_FLAKES, 2, -1 do
			local j = rng:NextInteger(1, i)
			slots[i], slots[j] = slots[j], slots[i]
		end
		for i = 1, N_FLAKES do
			local a = rng:NextNumber(0, 2 * math.pi)
			local r = rng:NextNumber(0, 0.28)
			local land = Vector3.new(feedPoint.X + math.cos(a) * r, surfaceY, feedPoint.Z + math.sin(a) * r)
			local u = (slots[i] - 0.5) / N_FLAKES
			local final = Vector3.new(
				math.clamp(areaMin.X + (areaMax.X - areaMin.X) * u + rng:NextNumber(-0.12, 0.12), areaMin.X, areaMax.X), surfaceY,
				rng:NextNumber(areaMin.Z, areaMax.Z))
			f.Flakes[i] = {
				Drop = DROP_FROM + (DROP_TO - DROP_FROM) * (i - 1) / (N_FLAKES - 1) + rng:NextNumber(-0.03, 0.03),
				Land = land, Final = final, Color = FLAKE_COLORS[rng:NextInteger(1, #FLAKE_COLORS)],
				Spin = rng:NextNumber(-4, 4), Tilt = rng:NextNumber(-0.35, 0.35), Eat = nil,
			}
		end
		--.. who eats what: the fish, ordered by where they are across the tank when the rush starts, split the flakes
		--.. (ordered by where they drift to) into side-by-side bands - Meals each - so nobody swims through anybody;
		--.. each fish eats its band nearest-first (from where it is, then from its last meal)
		local startPos, order = {}, {}
		for i, fish in ipairs(fishes) do
			f.Plans[i] = {Start = RUSH_START + RUSH_STAGGER * (i - 1), Meals = {}}
			startPos[i] = Map((LoopAt(fish.Spec.Loop, t0 + timeOffset + f.Plans[i].Start)))
			order[i] = i
		end
		table.sort(order, function(a, b) return startPos[a].X < startPos[b].X end)
		local byX = {}
		for k = 1, N_FLAKES do byX[k] = k end
		table.sort(byX, function(a, b) return f.Flakes[a].Final.X < f.Flakes[b].Final.X end)
		local nextFlake = 1
		for _, i in ipairs(order) do
			local plan = f.Plans[i]
			local band = {}
			for _ = 1, fishes[i].Spec.Meals do
				if nextFlake <= N_FLAKES then
					band[byX[nextFlake]] = true
					nextFlake += 1
				end
			end
			local from = startPos[i]
			while next(band) do
				local best, bestD = nil, math.huge
				for k in pairs(band) do
					local flake = f.Flakes[k]
					local dx, dz = flake.Final.X - from.X, flake.Final.Z - from.Z
					local dist = dx * dx + dz * dz
					if dist < bestD or (dist == bestD and k < best) then best, bestD = k, dist end
				end
				band[best] = nil
				local last = plan.Meals[#plan.Meals]
				local arrive = last and last.Eat + MOVE or plan.Start + APPROACH
				table.insert(plan.Meals, {Flake = best, Arrive = arrive, Eat = arrive + NIBBLE})
				f.Flakes[best].Eat = arrive + NIBBLE
				from = f.Flakes[best].Final
			end
		end
		for _, plan in ipairs(f.Plans) do
			local last = plan.Meals[#plan.Meals]
			plan.Leave = (last and last.Eat or plan.Start) + LINGER
		end
		for i, flake in ipairs(f.Flakes) do flakeParts[i].Color = flake.Color end
		return f
	end

	--.. where a flake is t s into the feeding (authored), eaten or not
	local function FlakeTrack(flake, t)
		if t <= flake.Drop then return flake.Land + Vector3.new(0, DROP_HEIGHT, 0) end
		local landT = flake.Drop + FALL_TIME
		if t < landT then
			local u = (t - flake.Drop) / FALL_TIME
			return (flake.Land + Vector3.new(0, DROP_HEIGHT * (1 - u * u), 0))
		end
		local p = flake.Land:Lerp(flake.Final, 1 - math.exp(-(t - landT) / FLAKE_DRIFT_TAU))
		return p + Vector3.new(0, 0.012 * math.sin(t * 3 + flake.Spin), 0)
	end

	--.. a feeding fish's target (authored), blend weight and nibbling flag at t s into the feeding
	local function FeedTarget(plan, f, t)
		local meals = plan.Meals
		if #meals == 0 or t < plan.Start or t > plan.Leave + RETURN then return nil, 0, false end
		local w
		if t < plan.Start + APPROACH then
			w = Smooth((t - plan.Start) / APPROACH)
		elseif t > plan.Leave then
			w = 1 - Smooth((t - plan.Leave) / RETURN)
		else
			w = 1
		end
		local cur = #meals
		for k = 1, #meals do
			if t < meals[k].Eat then cur = k break end
		end
		local meal = meals[cur]
		local down = Vector3.new(0, -NIBBLE_DEPTH, 0)
		local target = FlakeTrack(f.Flakes[meal.Flake], t) + down
		if cur > 1 and t < meal.Arrive then
			local prev = meals[cur - 1]
			local from = FlakeTrack(f.Flakes[prev.Flake], t) + down
			target = from:Lerp(target, Smooth((t - prev.Eat) / MOVE))
		end
		local nibbling = t >= meal.Arrive - 0.1 and t < meal.Eat + 0.05
		if nibbling then target += Vector3.new(0, 0.03 * math.sin(t * 14), 0) end
		return target, w, nibbling
	end

	--.. every fish's authored position at server time now -> out[i], nibbling -> nib[i]. Where two fish come closer
	--.. than SPACING (only ever while they crowd the food: the loops keep > 0.5 apart) they are nudged apart, then
	--.. kept inside the water. A pure function of the time and Fun_FedAt, so it is identical on every client.
	local wallMin = boxMin + Vector3.new(WALL_MARGIN.X, WALL_MARGIN.Y, WALL_MARGIN.Z)
	local wallMax = boxMax - Vector3.new(WALL_MARGIN.X, SURFACE_MARGIN, WALL_MARGIN.Z)
	local function School(now, out, nib)
		for i, fish in ipairs(fishes) do
			local pos = Map((LoopAt(fish.Spec.Loop, now + timeOffset)))
			local nibbling = false
			if feed then
				local target, w, nb = FeedTarget(feed.Plans[i], feed, now - feed.T0)
				if target and w > 0 then pos, nibbling = pos:Lerp(target, w), nb end
			end
			out[i], nib[i] = pos, nibbling
		end
		for _ = 1, 2 do
			for i = 1, #fishes do
				for j = i + 1, #fishes do
					local d = out[j] - out[i]
					local dist = d.Magnitude
					if dist < SPACING then
						local push = (dist > 1e-4 and d / dist or Vector3.xAxis) * ((SPACING - dist) * 0.5)
						out[i] -= push
						out[j] += push
					end
				end
			end
		end
		for i = 1, #fishes do
			local p = out[i]
			out[i] = Vector3.new(math.clamp(p.X, wallMin.X, wallMax.X), math.clamp(p.Y, wallMin.Y, wallMax.Y), math.clamp(p.Z, wallMin.Z, wallMax.Z))
		end
	end

	ctx:OnState("FedAt", function(t0)
		if type(t0) == "number" and Kit.Now() - t0 < FEED_TIME then
			feed = MakeFeed(t0)
			if Kit.Now() - t0 < 0.4 then Play(click, 1.1) end
		end
	end)

	--..Every frame..--
	local lastCycle = nil
	local lastGulp = 0
	local posNow, nibNow, posAhead, nibAhead = {}, {}, {}, {}
	ctx:Step(function(dt, now)
		if not (hitbox.Parent and SameCFrame(hitbox.CFrame, home)) then return end -- moved: the restart is on its way
		local n = 0
		local ease = 1 - math.exp(-YAW_RATE * dt)
		local easeP = 1 - math.exp(-PITCH_RATE * dt)

		--.. fish (velocity from where the school is 0.05 s later: follows the rush to the food as well as the loops)
		School(now, posNow, nibNow)
		School(now + 0.05, posAhead, nibAhead)
		for i, fish in ipairs(fishes) do
			local pos, nibbling = posNow[i], nibNow[i]
			local vel = (posAhead[i] - pos) / 0.05
			local flat = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
			if flat > 0.08 then fish.Yaw = LerpAngle(fish.Yaw, math.atan2(-vel.X, -vel.Z), ease) end
			local wantPitch = nibbling and NIBBLE_PITCH or math.clamp(math.atan2(vel.Y, math.max(flat, 0.05)), -PITCH_MAX, PITCH_MAX)
			fish.Pitch += (wantPitch - fish.Pitch) * easeP
			local speed = vel.Magnitude
			fish.Wag = (fish.Wag + dt * 2 * math.pi * (1.3 + 2.2 * math.min(speed, 1.6) + (nibbling and 1.5 or 0))) % (2 * math.pi)
			local wag = TAIL_WAG * math.sin(fish.Wag)
			local sway = -0.07 * math.sin(fish.Wag - 1.2) -- the head counter-swings the tail
			local cf = World(pos) * CFrame.Angles(0, fish.Yaw + sway, 0) * CFrame.Angles(fish.Pitch, 0, 0)
			for _, item in ipairs(fish.Body) do
				n += 1
				moveParts[n] = item[1]
				moveCFrames[n] = cf * item[2]
			end
			local tail = cf * fish.TailRoot * CFrame.Angles(0, wag, 0)
			for _, item in ipairs(fish.Tail) do
				n += 1
				moveParts[n] = item[1]
				moveCFrames[n] = tail * item[2]
			end
		end

		--.. plants sway in the current
		posed = true
		local w1, w2 = 2 * math.pi / SWAY_PERIOD, 2 * math.pi / (SWAY_PERIOD * 1.4)
		for _, leaf in ipairs(leaves) do
			local az = SWAY_AMP * math.sin(w1 * now + leaf.Phase)
			local ax = 0.4 * SWAY_AMP * math.sin(w2 * now + leaf.Phase * 1.7)
			n += 1
			moveParts[n] = leaf.Part
			moveCFrames[n] = leaf.Pivot * CFrame.Angles(ax, 0, az) * leaf.Rel
		end
		if flagRig then
			local a = FLAG_AMP * math.sin(2 * math.pi * now / FLAG_PERIOD) + 0.1 * math.sin(2 * math.pi * now / 0.47)
			n += 1
			moveParts[n] = flagRig.Parts[1]
			moveCFrames[n] = flagRig.Pivot * CFrame.Angles(0, a, 0) * flagRig.Rel[1]
		end

		--.. chest lid: shut, pops open every LID_PERIOD s with a burst of bubbles
		if lidRig then
			local clock = now + timeOffset
			local cycle = math.floor(clock / LID_PERIOD)
			local u = clock - cycle * LID_PERIOD
			if cycle ~= lastCycle then
				if lastCycle ~= nil and u < 0.5 and ctx:CameraDistance() <= B.StepRange then burst:Emit(9) end
				lastCycle = cycle
			end
			local open
			if u < LID_TIMES[1] then
				open = Smooth(u / LID_TIMES[1])
			elseif u < LID_TIMES[2] then
				open = 1
			else
				open = 1 - Smooth((u - LID_TIMES[2]) / (LID_TIMES[3] - LID_TIMES[2]))
			end
			n += 1
			moveParts[n] = lidRig.Parts[1]
			moveCFrames[n] = lidRig.Pivot * CFrame.Angles(LID_SHUT + (LID_OPEN - LID_SHUT) * open, 0, 0) * lidRig.Rel[1]
		end

		--.. feeding: flap, flakes, gulps
		if feed then
			local t = now - feed.T0
			if t > FEED_TIME then
				for _, part in ipairs(flakeParts) do part.Transparency = 1 end
				if flapRig and not feed.FlapDone then -- slept through the close (camera was far): shut it now
					for k, part in ipairs(flapRig.Parts) do
						n += 1
						moveParts[n] = part
						moveCFrames[n] = flapRig.Pivot * flapRig.Rel[k]
					end
				end
				feed = nil
			else
				if flapRig and not feed.FlapDone then
					local open
					if t < FLAP_TIMES[1] then
						open = Smooth(t / FLAP_TIMES[1])
					elseif t < FLAP_TIMES[2] then
						open = 1
					else
						open = 1 - Smooth((t - FLAP_TIMES[2]) / (FLAP_TIMES[3] - FLAP_TIMES[2]))
						if t >= FLAP_TIMES[3] then
							feed.FlapDone = true
							if t - FLAP_TIMES[3] < 0.3 then Play(click, 0.9) end -- not for a close long past (late / waking client)
						end
					end
					local cf = flapRig.Pivot * CFrame.Angles(FLAP_OPEN * open, 0, 0)
					for k, part in ipairs(flapRig.Parts) do
						n += 1
						moveParts[n] = part
						moveCFrames[n] = cf * flapRig.Rel[k]
					end
				end
				for i, flake in ipairs(feed.Flakes) do
					local part = flakeParts[i]
					local eaten = flake.Eat and t >= flake.Eat
					if t < flake.Drop or eaten then
						part.Transparency = 1
						if eaten and not feed.Eaten[i] then
							feed.Eaten[i] = true
							if t - flake.Eat < 0.5 then
								gulpAt.Position = FlakeTrack(flake, t) * scale
								gulp:Emit(3)
								if os.clock() - lastGulp > 0.15 then
									lastGulp = os.clock()
									Play(gulpSound, 1.6 + math.random() * 0.5)
								end
							end
						end
					else
						local p = FlakeTrack(flake, t)
						if t >= flake.Drop + FALL_TIME and not feed.Landed[i] then
							feed.Landed[i] = true
							if t - (flake.Drop + FALL_TIME) < 0.4 then -- not when catching up on a feeding already under way
								ringAt.Position = Vector3.new(p.X, surfaceY + 0.02, p.Z) * scale
								ring:Emit(1)
								if not feed.Rang then
									feed.Rang = true
									Play(splash)
								end
							end
						end
						local fade = (not flake.Eat and t > FEED_TIME - 1) and (t - (FEED_TIME - 1)) or 0
						part.Transparency = fade
						n += 1
						moveParts[n] = part
						moveCFrames[n] = World(p + Vector3.new(0, FLAKE_SIZE.Y * 0.5, 0)) * CFrame.Angles(flake.Tilt, flake.Spin * t, 0)
					end
				end
			end
		end

		for i = #moveParts, n + 1, -1 do
			moveParts[i] = nil
			moveCFrames[i] = nil
		end
		if n > 0 then workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged) end
	end)

	--..Cleanup: every moved build part back at rest where the build is now..--
	return function()
		if not (posed and model:IsDescendantOf(workspace) and hitbox.Parent) then return end
		local now = hitbox.CFrame
		for part, rel in pairs(rest) do
			if part.Parent then part.CFrame = now * rel end
		end
	end
end

return B
