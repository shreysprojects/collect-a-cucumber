--[[
	DefenceFXClient  (LocalScript, StarterPlayerScripts)  2026-09-24  fun-builds package DefenceFX
	Client half of the DEFENCE HIT EFFECTS (user: "effects from defenses like freeze tower when hitting stuff can
	have blue particles on each enemy hit") and the defences' IDLE effects.

	HITS. DefenceService (server) queues every damage it deals and sends each player, once per tick, the hits near
	them: ReplicatedStorage.Remotes.DefenceFX:FireClient(player, {{k = kind, z = zombie, p = Vector3, x = flags}, ...}).
	z can be nil on this client (streaming), then the effect plays at p; otherwise it plays on the zombie's torso
	where THIS client draws it. A shaded (phased-out) shadow zombie gets particles only and loses its ice / tint at
	once. Per kind:
	  Frost     every chill tick: snowflake sparkles + mist + 2 small ice shards that fall; a frosty Highlight (fill
	            170,220,255 @0.6, white outline) held while the hits keep coming and faded out from 0.8 s after the
	            last one; Ice crystals stuck on the head / shoulders while it is slowed (nearest zombies first, 5 each,
	            fewer when many are slowed), shed when the slow ends.
	            x.pulse (freeze pulse): a big ice burst and a translucent Ice block encasing the zombie for x.stun s
	            that shatters at the end (shards fly); no crystals while it is inside the block.
	  Tesla     cyan electric sparks + a white flash Highlight for 0.15 s on every hop of the chain
	  Laser     red embers + burn sparks + a red flickering Highlight while it stands in the gate
	  Turret    cyan impact sparks thrown back toward the gun (x.from)
	  Minigun   small yellow sparks + a puff of dust (the server sends at most one per 0.15 s per zombie)
	  Mortar    per burst (x.c, the first hit of a burst draws it): an expanding ground shockwave ring, dirt and flying
	            debris chunks; per zombie hit: an orange flash Highlight + sparks
	  Catapult  dust + flying rock chips at the zombie's feet
	  Spikes    small red sparks + dust at its feet
	BUDGET: at most MAX_PARTS live effect parts: ice blocks may use all of them, flying debris / decoration stops
	BLOCK_RESERVE short (so a freeze pulse always finds room for its blocks), crystals have their own cap CRYSTAL_MAX
	and stop DEBRIS_MIN below where debris stops (so shards / chips / chunks always have room); with the debris
	budget full, the oldest landed debris makes way for a new hit's (RECYCLE_AGE). At most
	MAX_HIGHLIGHTS Highlights (Roblox draws only 31 per client), nothing farther than MAX_DIST from the camera and no
	parts farther than PART_DIST.
	PARTICLES: Emit() spawns its particles where the emitter is when the frame RENDERS, not where it was at the call
	(moving one emitter to 5 zombies and emitting in one frame puts all 5 bursts on the last zombie). So every hit
	gets its own emission point: each style keeps a pool of up to SLOT_MAX attachments in workspace.Terrain (made
	on demand, each with its own emitters) and a point is only moved again 2 frames (= at least one render) after
	its last Emit. More hits of one style in one frame than that are skipped. Particles are world-space
	(LockedToPart off), so moving a point later never drags particles already out. Parts live in the local folder
	workspace.DefenceFXLocal and are all Debris'd. One Heartbeat loop counts frames, moves the debris, tints the
	zombies and ages everything.

	IDLE. Every placed Defences build (tag PlacedBuild; attribute Category "Defences", or a template in
	ReplicatedStorage.PlaceableBuilds.Defences) near the camera:
	  * parts named Glow* pulse their Transparency base .. base + 0.35, a wave running along the parts (restored
	    when the build goes)
	  * Pivot_Mist1..n breathe a slow cold mist that creeps outward (FreezeTower)
	  * Pivot_Spark1..n crackle with tiny sparks now and then (TeslaCoil cyan, LaserGate red; an older model
	    without Spark pivots uses its ProngTip / Beam pivots)
	Nothing runs while the build is Broken. A Transparency the server wrote (BuildHealthService's broken fade) is
	never overwritten or "restored". Builds that stream in / out, move, sell, break or mend restart cleanly.

	Studio test hook (on this client): workspace:SetAttribute("DefenceFXTest", "Frost" | "Frost:pulse" | "Tesla" |
	"Laser" | "Turret" | "Minigun" | "Mortar" | "Catapult" | "Spikes") plays that hit on the nearest zombie, or 14
	studs in front of the camera. Stats on this script's attributes: LiveParts, Crystals, Highlights, Tinted,
	IdleBuilds, Events, EmitPoints (pooled attachments made), BurstsSkipped (no free emission point that frame).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local REMOTE = "DefenceFX"              -- ReplicatedStorage.Remotes.<this> (DefenceService makes it)
local DEFENCES = "Defences"             -- the build category (and ReplicatedStorage.PlaceableBuilds.<this>)
local ZOMBIE_FOLDER = "Zombies"         -- ZombieCatalog.FOLDER
local MAX_PARTS = 60                    -- live effect parts on this client, every kind together
local BLOCK_RESERVE = 12                -- the last parts of MAX_PARTS: only ice blocks may take them
local DEBRIS_MIN = 8                    -- crystals stop this many parts before debris does: flying debris always has room
local CRYSTAL_MAX = 20                  -- crystals on slowed zombies (their own cap)
local CRYSTALS_BUSY = 12                -- once this many crystals are on, a newly slowed zombie gets CRYSTALS_FEW, not all
local CRYSTALS_FEW = 2
local CRYSTAL_STEAL = 15                -- a zombie this much nearer the camera takes the crystals of the farthest one
local SLOT_MAX = 24                     -- emission points per particle style (= hits of one style drawn in one frame)
local MAX_HIGHLIGHTS = 12
local MAX_DIST = 250                    -- studs from the camera: no effect beyond
local PART_DIST = 140                   -- ... and no parts beyond this (particles only, fewer)
local GRAVITY = Vector3.new(0, -80, 0)  -- debris falls slower than the world (196.2) so the eye can follow it
local FADE = 0.35                       -- s: debris fades out over its last FADE seconds
local RECYCLE_AGE = 0.45                -- s: debris this old (landed) may be removed early to make room for a new hit's
local SAFETY_LIFE = 30                  -- s: crystals / Highlights are Debris'd after this and rebuilt if still needed
local BROKEN_T = 0.65                   -- BuildHealthService's broken fade

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local WHITE = Color3.new(1, 1, 1)

local FROST = {
	Fill = rgb(170, 220, 255), FillT = 0.6, Outline = WHITE, OutlineT = 0.15,
	Hold = 0.8, Fade = 0.5,  -- the tint stays full until Hold s after the last hit, then fades out over Fade s
	CrystalHold = 1.0,       -- crystals are shed this long after the last chill tick (the slow lasts 0.8 s)
	Stun = 1.5,              -- ice-block time when the event carries none (DefenceService FROST.PulseStun)
	Block = rgb(165, 215, 255),
}
--.. LASER_HOLD = s after the last laser hit the red flicker stays: hits come every ~0.27-0.33 s (the server's 0.25 s
--.. throttle on a 0.1 s laser tick in a 0.05 s loop) + network jitter, so the Highlight is never dropped between hits
local LASER_HOLD = 0.5
local LASER_FILL, LASER_OUTLINE = rgb(255, 60, 45), rgb(255, 150, 120)
local FLICKER_EVERY = 0.06
local FLASH = {
	Tesla = {Fill = WHITE, FillT = 0.1, Outline = rgb(150, 235, 255), Time = 0.15},
	Mortar = {Fill = rgb(255, 150, 50), FillT = 0.25, Outline = rgb(255, 225, 160), Time = 0.35},
}

--.. flying debris: Class, Size (x 0.7..1.3), Colors, Material, Up / Out = vertical / horizontal launch speed ranges
local ICE = {rgb(205, 238, 255), rgb(170, 220, 255), rgb(235, 248, 255)}
local SHARD = {Class = "WedgePart", Size = Vector3.new(0.16, 0.42, 0.26), Colors = ICE, Material = Enum.Material.Ice,
	Transparency = 0.12, Reflectance = 0.2, Up = {5, 11}, Out = {3, 7}, Spin = 12, Life = 1.3}
local SHARD_BIG = {Class = "WedgePart", Size = Vector3.new(0.3, 0.75, 0.45), Colors = ICE, Material = Enum.Material.Ice,
	Transparency = 0.2, Reflectance = 0.2, Up = {9, 18}, Out = {7, 14}, Spin = 10, Life = 1.7}
local CHIP = {Class = "Part", Size = Vector3.new(0.3, 0.26, 0.3), Colors = {rgb(120, 116, 108), rgb(96, 92, 86), rgb(142, 134, 120)},
	Material = Enum.Material.Slate, Up = {8, 14}, Out = {4, 9}, Spin = 14, Life = 1.2}
local CHUNK = {Class = "Part", Size = Vector3.new(0.6, 0.45, 0.55), Colors = {rgb(72, 64, 56), rgb(98, 84, 68), rgb(124, 106, 84)},
	Material = Enum.Material.Slate, Up = {14, 24}, Out = {9, 17}, Spin = 9, Life = 1.8}

--.. frost crystals on a slowed zombie: body part, spot on it (fractions of its Size, top = 0.5), tilt in degrees;
--.. the most visible spots first (a zombie that only gets CRYSTALS_FEW gets the first ones)
local CRYSTAL_SIZE = Vector3.new(0.3, 0.8, 0.3)
local CRYSTAL_SPOTS = {
	{Part = "Head", At = Vector3.new(0.28, 0.5, 0.05), Tilt = Vector3.new(0, 20, -28)},
	{Part = "LeftUpperArm", At = Vector3.new(0, 0.5, 0), Tilt = Vector3.new(0, 0, 32)},
	{Part = "RightUpperArm", At = Vector3.new(0, 0.5, 0), Tilt = Vector3.new(0, 0, -32)},
	{Part = "Head", At = Vector3.new(-0.25, 0.45, -0.1), Tilt = Vector3.new(8, -15, 32)},
	{Part = "UpperTorso", At = Vector3.new(0.2, 0.45, 0.4), Tilt = Vector3.new(28, 0, -10)},
}

--.. IDLE: per BuildKey. Period = s per glow pulse, Wave = phase step between consecutive Glow parts,
--.. Spark = spark colour (with Spark pivots), Fallback = pivots used when the model has no Pivot_Spark*
local IDLE_RANGE = 200
local IDLE_HZ = 20
local GLOW_AMP = 0.35
local IDLE = {
	FreezeTower = {Period = 2.8, Wave = 0.35},
	TeslaCoil = {Period = 1.5, Wave = 0.7, Spark = rgb(120, 225, 255), Fallback = {"ProngTip1", "ProngTip2", "ProngTip3", "ProngTip4"}},
	LaserGate = {Period = 1.2, Wave = 0.5, Spark = rgb(255, 70, 60), Fallback = {"BeamLeft", "BeamRight"}},
}
local IDLE_DEFAULT = {Period = 2.4, Wave = 0.45}
local MIST_RATE = 1.6           -- particles / s per Mist pivot
local SPARK_GAP = {0.25, 0.8}   -- s between spark crackles on one build

local player = Players.LocalPlayer

--..Textures (built into the client)..--
local TEX = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Spark = "rbxasset://textures/particles/fire_sparks_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	Square = "rbxasset://textures/particles/SquareParticle.png",
}

--..Helpers..--
local function seq(...) -- seq(t0, v0, t1, v1, ...) -> NumberSequence (t0 = 0, last t = 1)
	local args = {...}
	local points = {}
	for i = 1, #args, 2 do table.insert(points, NumberSequenceKeypoint.new(args[i], args[i + 1])) end
	return NumberSequence.new(points)
end

local function cseq(a, b) return ColorSequence.new(a, b) end
local function range(a, b) return NumberRange.new(a, b or a) end
local function Rand(r) return r[1] + math.random() * (r[2] - r[1]) end

local function RandomFlat()
	local a = math.random() * 2 * math.pi
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function RandomRotation()
	return CFrame.Angles(math.random() * 2 * math.pi, math.random() * 2 * math.pi, math.random() * 2 * math.pi)
end

local function RandomSpin(s)
	return Vector3.new((math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s)
end

local function CamPos()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end

local function TorsoOf(zombie)
	local t = zombie:FindFirstChild("UpperTorso") or zombie:FindFirstChild("Torso") or zombie:FindFirstChild("HumanoidRootPart")
	return (t and t:IsA("BasePart")) and t or nil
end

local lastWarn = 0
local function Warn(msg)
	if os.clock() - lastWarn < 5 then return end
	lastWarn = os.clock()
	warn("[DefenceFXClient] " .. tostring(msg))
end

--..Local folder..--
local Folder = Instance.new("Folder")
Folder.Name = "DefenceFXLocal"
Folder.Parent = workspace

--..Ground..--
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true
RayParams.RespectCanCollide = true

--.. the Y of the floor under a point (builds, terrain, the map; not zombies, characters or effects)
local function GroundY(position)
	local ignore = {Folder}
	local zombies = workspace:FindFirstChild(ZOMBIE_FOLDER)
	if zombies then table.insert(ignore, zombies) end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(ignore, plr.Character) end
	end
	RayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -40, 0), RayParams)
	return hit and hit.Position.Y or (position.Y - 3)
end

--..Particle styles (pooled emitters)..--
local function MakeEmitter(parent, s)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = s.Texture
	pe.Color = s.Color
	pe.Size = s.Size
	pe.Transparency = s.Transparency or seq(0, 0, 1, 1)
	pe.Lifetime = s.Lifetime
	pe.Speed = s.Speed
	pe.SpreadAngle = s.Spread or Vector2.new(180, 180)
	pe.Acceleration = s.Acceleration or Vector3.zero
	pe.Drag = s.Drag or 0
	pe.LightEmission = s.LightEmission or 0
	pe.LightInfluence = s.LightInfluence or 1
	pe.Rotation = s.Rotation or range(0, 360)
	pe.RotSpeed = s.RotSpeed or range(-60, 60)
	pe.ZOffset = s.ZOffset or 0.4
	pe.EmissionDirection = s.Direction or Enum.NormalId.Top
	pe.Orientation = s.Orientation or Enum.ParticleOrientation.FacingCamera
	pe.Rate = s.Rate or 0
	pe.LockedToPart = false
	pe.Parent = parent
	return pe
end

local PARALLEL = Enum.ParticleOrientation.VelocityParallel
local FLAT = Enum.ParticleOrientation.VelocityPerpendicular
local FRONT = Enum.NormalId.Front
local STYLES = {
	Frost = {
		{Count = 9, Texture = TEX.Sparkle, Color = cseq(WHITE, rgb(140, 205, 255)), Size = seq(0, 0.55, 1, 0), Transparency = seq(0, 0, 0.7, 0.15, 1, 1),
			Lifetime = range(0.45, 0.8), Speed = range(5, 9), Drag = 3, Acceleration = Vector3.new(0, -5, 0), LightEmission = 0.8, LightInfluence = 0, ZOffset = 0.6},
		{Count = 5, Texture = TEX.Sparkle, Color = cseq(rgb(235, 248, 255), rgb(190, 228, 255)), Size = seq(0, 0.3, 1, 0.2), Transparency = seq(0, 0.05, 0.8, 0.3, 1, 1),
			Lifetime = range(0.9, 1.5), Speed = range(1.5, 3), Drag = 1, Acceleration = Vector3.new(0, -3, 0), RotSpeed = range(-180, 180), LightEmission = 0.5, LightInfluence = 0.2},
		{Count = 2, Texture = TEX.Smoke, Color = cseq(rgb(200, 232, 255), rgb(232, 246, 255)), Size = seq(0, 0.8, 1, 2.2), Transparency = seq(0, 0.45, 1, 1),
			Lifetime = range(0.6, 1.0), Speed = range(1, 2.5), Drag = 2, LightEmission = 0.1, LightInfluence = 0.6, ZOffset = 0},
	},
	IceBurst = {
		{Count = 24, Texture = TEX.Sparkle, Color = cseq(WHITE, rgb(140, 205, 255)), Size = seq(0, 0.9, 1, 0), Transparency = seq(0, 0, 0.7, 0.15, 1, 1),
			Lifetime = range(0.6, 1.1), Speed = range(10, 18), Drag = 3, Acceleration = Vector3.new(0, -6, 0), LightEmission = 0.8, LightInfluence = 0, ZOffset = 0.8},
		{Count = 10, Texture = TEX.Sparkle, Color = cseq(rgb(235, 248, 255), rgb(190, 228, 255)), Size = seq(0, 0.4, 1, 0.25), Transparency = seq(0, 0.05, 0.8, 0.3, 1, 1),
			Lifetime = range(1.2, 2.0), Speed = range(3, 6), Drag = 1, Acceleration = Vector3.new(0, -3, 0), RotSpeed = range(-180, 180), LightEmission = 0.5, LightInfluence = 0.2},
		{Count = 6, Texture = TEX.Smoke, Color = cseq(rgb(200, 232, 255), rgb(235, 247, 255)), Size = seq(0, 1.5, 1, 4.2), Transparency = seq(0, 0.35, 1, 1),
			Lifetime = range(0.9, 1.4), Speed = range(3, 7), Drag = 2.5, LightEmission = 0.15, LightInfluence = 0.6, ZOffset = 0},
	},
	Tesla = {
		{Count = 12, Texture = TEX.Spark, Color = cseq(rgb(220, 250, 255), rgb(60, 165, 255)), Size = seq(0, 0.5, 1, 0), Transparency = seq(0, 0, 1, 0.4),
			Lifetime = range(0.18, 0.35), Speed = range(12, 22), Drag = 5, LightEmission = 1, LightInfluence = 0, Orientation = PARALLEL},
		{Count = 1, Texture = TEX.Sparkle, Color = cseq(WHITE, rgb(120, 210, 255)), Size = seq(0, 2.6, 1, 0.4), Transparency = seq(0, 0, 1, 1),
			Lifetime = range(0.12, 0.18), Speed = range(0), RotSpeed = range(0), LightEmission = 1, LightInfluence = 0, ZOffset = 1},
	},
	Laser = {
		{Count = 5, Texture = TEX.Sparkle, Color = cseq(rgb(255, 170, 80), rgb(255, 50, 25)), Size = seq(0, 0.22, 1, 0.05), Transparency = seq(0, 0, 0.8, 0.2, 1, 1),
			Lifetime = range(0.8, 1.4), Speed = range(1.5, 3.5), Spread = Vector2.new(35, 35), Drag = 1, Acceleration = Vector3.new(0, 5, 0), LightEmission = 1, LightInfluence = 0},
		{Count = 6, Texture = TEX.Spark, Color = cseq(rgb(255, 150, 110), rgb(255, 40, 30)), Size = seq(0, 0.35, 1, 0),
			Lifetime = range(0.15, 0.3), Speed = range(8, 14), Drag = 4, LightEmission = 1, LightInfluence = 0, Orientation = PARALLEL},
		{Count = 1, Texture = TEX.Smoke, Color = cseq(rgb(80, 60, 60), rgb(50, 45, 45)), Size = seq(0, 0.5, 1, 1.5), Transparency = seq(0, 0.55, 1, 1),
			Lifetime = range(0.5, 0.9), Speed = range(1, 2), Acceleration = Vector3.new(0, 3, 0), ZOffset = 0},
	},
	Turret = {
		{Count = 9, Texture = TEX.Spark, Color = cseq(rgb(215, 248, 255), rgb(77, 210, 255)), Size = seq(0, 0.4, 1, 0),
			Lifetime = range(0.12, 0.25), Speed = range(14, 24), Spread = Vector2.new(40, 40), Direction = FRONT, Drag = 5, Acceleration = Vector3.new(0, -20, 0),
			LightEmission = 1, LightInfluence = 0, Orientation = PARALLEL},
		{Count = 1, Texture = TEX.Sparkle, Color = cseq(WHITE, rgb(77, 210, 255)), Size = seq(0, 1.6, 1, 0.2),
			Lifetime = range(0.08, 0.12), Speed = range(0), RotSpeed = range(0), LightEmission = 1, LightInfluence = 0, ZOffset = 1},
	},
	Minigun = {
		{Count = 4, Texture = TEX.Spark, Color = cseq(rgb(255, 245, 190), rgb(255, 180, 70)), Size = seq(0, 0.3, 1, 0),
			Lifetime = range(0.1, 0.2), Speed = range(10, 16), Spread = Vector2.new(55, 55), Direction = FRONT, Drag = 4, Acceleration = Vector3.new(0, -25, 0),
			LightEmission = 1, LightInfluence = 0, Orientation = PARALLEL},
		{Count = 1, Texture = TEX.Smoke, Color = cseq(rgb(180, 160, 130), rgb(150, 135, 115)), Size = seq(0, 0.5, 1, 1.4), Transparency = seq(0, 0.5, 1, 1),
			Lifetime = range(0.4, 0.7), Speed = range(1, 3), Drag = 2, ZOffset = 0},
	},
	MortarHit = {
		{Count = 10, Texture = TEX.Spark, Color = cseq(rgb(255, 225, 140), rgb(255, 110, 40)), Size = seq(0, 0.5, 1, 0),
			Lifetime = range(0.2, 0.4), Speed = range(10, 18), Drag = 3, Acceleration = Vector3.new(0, -20, 0), LightEmission = 1, LightInfluence = 0, Orientation = PARALLEL},
		{Count = 1, Texture = TEX.Sparkle, Color = cseq(rgb(255, 220, 150), rgb(255, 130, 50)), Size = seq(0, 3, 1, 0.4), Transparency = seq(0, 0, 1, 1),
			Lifetime = range(0.15, 0.22), Speed = range(0), RotSpeed = range(0), LightEmission = 1, LightInfluence = 0, ZOffset = 1},
	},
	MortarRing = { -- flat on the ground: the velocity points up and the particle faces along it
		{Count = 1, Texture = TEX.Ring, Color = cseq(rgb(255, 230, 180), rgb(255, 150, 70)), Size = seq(0, 1.5, 1, 22), Transparency = seq(0, 0.05, 0.5, 0.45, 1, 1),
			Lifetime = range(0.55), Speed = range(0.05), Spread = Vector2.zero, Orientation = FLAT, RotSpeed = range(0), LightEmission = 0.7, LightInfluence = 0, ZOffset = 0},
		{Count = 1, Texture = TEX.Smoke, Color = cseq(rgb(150, 132, 110), rgb(120, 108, 92)), Size = seq(0, 3, 1, 24), Transparency = seq(0, 0.3, 1, 1),
			Lifetime = range(0.9), Speed = range(0.05), Spread = Vector2.zero, Orientation = FLAT, RotSpeed = range(-20, 20), ZOffset = 0},
	},
	MortarDirt = {
		{Count = 14, Texture = TEX.Square, Color = cseq(rgb(100, 84, 66), rgb(70, 58, 46)), Size = seq(0, 0.3, 1, 0.22), Transparency = seq(0, 0, 0.8, 0, 1, 1),
			Lifetime = range(0.6, 1.0), Speed = range(14, 24), Spread = Vector2.new(55, 55), Acceleration = Vector3.new(0, -60, 0), RotSpeed = range(-360, 360)},
		{Count = 4, Texture = TEX.Smoke, Color = cseq(rgb(120, 105, 90), rgb(95, 85, 75)), Size = seq(0, 1.5, 1, 4), Transparency = seq(0, 0.35, 1, 1),
			Lifetime = range(0.8, 1.3), Speed = range(4, 9), Spread = Vector2.new(70, 70), Drag = 2, ZOffset = 0},
	},
	Catapult = {
		{Count = 4, Texture = TEX.Smoke, Color = cseq(rgb(165, 148, 120), rgb(135, 122, 104)), Size = seq(0, 1, 1, 2.6), Transparency = seq(0, 0.35, 1, 1),
			Lifetime = range(0.6, 1.1), Speed = range(3, 6), Drag = 2, Acceleration = Vector3.new(0, 1.5, 0), ZOffset = 0},
		{Count = 8, Texture = TEX.Square, Color = cseq(rgb(128, 122, 112), rgb(96, 92, 86)), Size = seq(0, 0.24, 1, 0.18), Transparency = seq(0, 0, 0.8, 0, 1, 1),
			Lifetime = range(0.5, 0.9), Speed = range(8, 14), Spread = Vector2.new(60, 60), Acceleration = Vector3.new(0, -55, 0), RotSpeed = range(-360, 360)},
	},
	Spikes = {
		{Count = 5, Texture = TEX.Spark, Color = cseq(rgb(255, 140, 120), rgb(230, 30, 30)), Size = seq(0, 0.3, 1, 0),
			Lifetime = range(0.12, 0.25), Speed = range(6, 11), Spread = Vector2.new(60, 60), Drag = 3, Acceleration = Vector3.new(0, -20, 0),
			LightEmission = 1, LightInfluence = 0, Orientation = PARALLEL},
		{Count = 2, Texture = TEX.Smoke, Color = cseq(rgb(165, 150, 125), rgb(140, 128, 108)), Size = seq(0, 0.6, 1, 1.6), Transparency = seq(0, 0.5, 1, 1),
			Lifetime = range(0.5, 0.8), Speed = range(1, 3), Drag = 2, ZOffset = 0},
	},
}

--.. emission points: Emit() takes the emitter's position at RENDER time, so a point may move again only once a
--.. frame has rendered since its last Emit (Frame, counted in the Heartbeat, has advanced by 2: between two
--.. Heartbeats lies exactly one render). One point per hit; the pool of a style grows on demand to SLOT_MAX.
local Frame = 0
local EmitPoints, BurstsSkipped = 0, 0
local Styles = {} -- [name] = {Name, Specs, Slots = {{Att, List = {{Emitter, Count}}, Frame}}}
for name, specs in pairs(STYLES) do Styles[name] = {Name = name, Specs = specs, Slots = {}} end

local function NewSlot(style)
	local att = Instance.new("Attachment")
	att.Name = "DefenceFX_" .. style.Name
	att.Parent = workspace.Terrain
	local slot = {Att = att, List = {}, Frame = -1e9}
	for _, s in ipairs(style.Specs) do table.insert(slot.List, {Emitter = MakeEmitter(att, s), Count = s.Count}) end
	table.insert(style.Slots, slot)
	EmitPoints += 1
	return slot
end

--.. a point of this style that has not emitted this frame or the last one (nil when all SLOT_MAX are busy)
local function FreeSlot(style)
	for _, slot in ipairs(style.Slots) do
		if Frame - slot.Frame >= 2 then return slot end
	end
	if #style.Slots < SLOT_MAX then return NewSlot(style) end
	return nil
end

--.. emit a style at a point (scale multiplies the counts); look = a point the emission Front faces (sparks fly back to the gun)
local function Burst(name, position, scale, look)
	local style = Styles[name]
	if not style then return false end
	local slot = FreeSlot(style)
	if not slot then
		BurstsSkipped += 1
		return false
	end
	slot.Frame = Frame
	if look and (look - position).Magnitude > 0.05 then
		slot.Att.WorldCFrame = CFrame.lookAt(position, look)
	else
		slot.Att.WorldCFrame = CFrame.new(position)
	end
	for _, e in ipairs(slot.List) do
		local n = math.floor(e.Count * (scale or 1) + 0.5)
		if n > 0 then e.Emitter:Emit(n) end
	end
	return true
end

--..Effect parts (budgeted)..--
local LiveParts = {}    -- every effect part made (destroyed ones are pruned when a limit is reached)
local CrystalParts = {} -- the crystals among them (their own cap)

--.. drop destroyed parts from a list; returns how many are alive
local function Prune(list)
	local j = 0
	for i = 1, #list do
		local p = list[i]
		if p.Parent then
			j += 1
			list[j] = p
		end
	end
	for i = #list, j + 1, -1 do list[i] = nil end
	return j
end

local function Below(list, limit)
	return #list < limit or Prune(list) < limit
end

--.. may one more part of this budget class be made now?
--..   "Block"   the ice block of a freeze pulse: the whole MAX_PARTS
--..   "Crystal" CRYSTAL_MAX of their own, and only while the total is DEBRIS_MIN below where debris stops
--..   anything else (flying debris, the block's decorative spikes): up to MAX_PARTS - BLOCK_RESERVE
local function Room(class)
	if class == "Block" then return Below(LiveParts, MAX_PARTS) end
	if class == "Crystal" then
		return Below(CrystalParts, CRYSTAL_MAX) and Below(LiveParts, MAX_PARTS - BLOCK_RESERVE - DEBRIS_MIN)
	end
	return Below(LiveParts, MAX_PARTS - BLOCK_RESERVE)
end

local function MakePart(class, props)
	local p = Instance.new(class or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = Folder
	table.insert(LiveParts, p)
	return p
end

--.. a part that stays on a zombie (budget = "Block" / "Crystal" / "Debris", see Room): nil when its budget is used
local function StatePart(budget, class, props, life)
	if not Room(budget) then return nil end
	local p = MakePart(class, props)
	if budget == "Crystal" then table.insert(CrystalParts, p) end
	Debris:AddItem(p, life)
	return p
end

--.. weld an effect part onto a zombie body part so it rides the animation exactly
local function StickTo(part, body)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = part
	weld.Parent = part
	part.Anchored = false
end

--..Flying debris..--
local Flyers = {} -- {Part, Vel, Spin, Ground, Born, Life, T0, Landed, Bounced}

local function Fling(part, vel, spin, ground, life)
	table.insert(Flyers, {Part = part, Vel = vel, Spin = spin, Ground = ground, Born = os.clock(), Life = life, T0 = part.Transparency, Landed = false, Bounced = false})
end

--.. the debris budget is full: the oldest piece that has had time to land (RECYCLE_AGE) goes, so a new hit still
--.. throws its shards / chips instead of the old ones hogging the budget; false when none is old enough
local function RecycleOldest(now)
	local oldest
	for _, f in ipairs(Flyers) do
		if f.Part.Parent and now - f.Born >= RECYCLE_AGE and (not oldest or f.Born < oldest.Born) then oldest = f end
	end
	if not oldest then return false end
	oldest.Part:Destroy() -- StepFlyers drops the record
	return true
end

--.. n debris parts of `spec` thrown from origin (spread = half-extent box to start them in)
local function Scatter(origin, n, spec, ground, spread)
	ground = ground or GroundY(origin)
	for _ = 1, n do
		if not Room("Debris") and not (RecycleOldest(os.clock()) and Room("Debris")) then return end
		local size = spec.Size * (0.7 + math.random() * 0.6)
		local offset = Vector3.zero
		if spread then
			offset = Vector3.new((math.random() - 0.5) * 2 * spread.X, (math.random() - 0.5) * 2 * spread.Y, (math.random() - 0.5) * 2 * spread.Z)
		end
		local part = MakePart(spec.Class, {
			Name = "DefenceFXDebris", Size = size, CFrame = CFrame.new(origin + offset) * RandomRotation(),
			Color = spec.Colors[math.random(1, #spec.Colors)], Material = spec.Material,
			Transparency = spec.Transparency or 0, Reflectance = spec.Reflectance or 0,
		})
		Debris:AddItem(part, spec.Life + 0.5)
		local out = Vector3.new(offset.X, 0, offset.Z)
		local dir = out.Magnitude > 0.1 and out.Unit or RandomFlat()
		Fling(part, dir * Rand(spec.Out) + Vector3.new(0, Rand(spec.Up), 0), RandomSpin(spec.Spin), ground + math.min(size.X, size.Y, size.Z) * 0.5, spec.Life)
	end
end

local function StepFlyers(now, dt)
	dt = math.min(dt, 0.1)
	for i = #Flyers, 1, -1 do
		local f = Flyers[i]
		local part = f.Part
		local age = now - f.Born
		if not part.Parent or age >= f.Life then
			if part.Parent then part:Destroy() end
			Flyers[i] = Flyers[#Flyers]
			Flyers[#Flyers] = nil
		else
			if not f.Landed then
				f.Vel += GRAVITY * dt
				local cf = part.CFrame
				local pos = cf.Position + f.Vel * dt
				local spin = f.Spin * dt
				if pos.Y <= f.Ground then
					pos = Vector3.new(pos.X, f.Ground, pos.Z)
					if not f.Bounced and f.Vel.Y < -10 then
						f.Bounced = true
						f.Vel = Vector3.new(f.Vel.X * 0.4, -f.Vel.Y * 0.3, f.Vel.Z * 0.4)
						f.Spin *= 0.5
					else
						f.Landed = true
					end
				end
				part.CFrame = CFrame.new(pos) * cf.Rotation * CFrame.Angles(spin.X, spin.Y, spin.Z)
			end
			local fadeAt = f.Life - FADE
			if age > fadeAt then
				part.Transparency = f.T0 + (1 - f.T0) * math.clamp((age - fadeAt) / FADE, 0, 1)
			end
		end
	end
end

--..Zombie state (tint, crystals, ice block)..--
local ZState = {} -- [zombie] = {Zombie, Humanoid, FrostLast, LaserLast, Flash, FlashUntil, Highlight, Crystals, Block, BlockUntil}
local HighlightCount = 0

local function StateOf(zombie)
	local st = ZState[zombie]
	if not st then
		st = {Zombie = zombie, Humanoid = zombie:FindFirstChildOfClass("Humanoid"), FrostLast = -1e9, LaserLast = -1e9,
			FlashUntil = 0, BlockUntil = 0, FlickerAt = 0}
		ZState[zombie] = st
	end
	return st
end

local function DropHighlight(st)
	if not st.Highlight then return end
	HighlightCount -= 1
	st.Highlight:Destroy()
	st.Highlight = nil
end

local function EnsureHighlight(st)
	local h = st.Highlight
	if h and h.Parent then return h end
	if h then DropHighlight(st) end -- the safety Debris took it: count it out, make a fresh one
	if HighlightCount >= MAX_HIGHLIGHTS then return nil end
	h = Instance.new("Highlight")
	h.Name = "DefenceFXTint"
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	h.Adornee = st.Zombie
	h.Parent = st.Zombie
	Debris:AddItem(h, SAFETY_LIFE)
	HighlightCount += 1
	st.Highlight = h
	return h
end

local function Flash(st, spec, now)
	st.Flash = spec
	st.FlashUntil = now + spec.Time
end

--.. the tint this frame: a flash (Tesla / Mortar) over the laser flicker over the frost; false when none
local function Tint(st, now)
	local fill, fillT, outline, outlineT
	if now < st.FlashUntil and st.Flash then
		local a = 1 - (st.FlashUntil - now) / st.Flash.Time
		fill, outline = st.Flash.Fill, st.Flash.Outline
		fillT = st.Flash.FillT + (1 - st.Flash.FillT) * a
		outlineT = a
	elseif now - st.LaserLast <= LASER_HOLD then
		fill, outline = LASER_FILL, LASER_OUTLINE
		if now >= st.FlickerAt or not st.FlickerT then
			st.FlickerAt = now + FLICKER_EVERY
			st.FlickerT = 0.35 + math.random() * 0.4
		end
		fillT, outlineT = st.FlickerT, st.FlickerT - 0.2
	else
		local since = now - st.FrostLast
		if since <= FROST.Hold + FROST.Fade then
			local a = math.clamp((since - FROST.Hold) / FROST.Fade, 0, 1)
			fill, outline = FROST.Fill, FROST.Outline
			fillT = FROST.FillT + (1 - FROST.FillT) * a
			outlineT = FROST.OutlineT + (1 - FROST.OutlineT) * a
		end
	end
	if not fill then
		DropHighlight(st)
		return false
	end
	local h = EnsureHighlight(st)
	if h then
		h.FillColor = fill
		h.FillTransparency = fillT
		h.OutlineColor = outline
		h.OutlineTransparency = math.clamp(outlineT, 0, 1)
	end
	return true
end

local function CrystalsIntact(list)
	for _, c in ipairs(list) do
		if not c.Parent then return false end
	end
	return true
end

--.. crystals gone at once, no fall (a nearer zombie takes them, or an ice block swallows them)
local function PopCrystals(st)
	local list = st.Crystals
	st.Crystals = nil
	if not list then return end
	for _, c in ipairs(list) do
		if c.Parent then c:Destroy() end
	end
end

--.. the crystal holder farthest from the camera, if it is at least CRYSTAL_STEAL farther than `dist`
local function FarthestHolder(dist, except)
	local best
	for _, other in pairs(ZState) do
		if other ~= except and other.Crystals and (other.Dist or 0) > dist + CRYSTAL_STEAL and (not best or other.Dist > best.Dist) then
			best = other
		end
	end
	return best
end

--.. Ice crystals on the head / shoulders of a slowed zombie (welded, so they ride the walk animation). All of
--.. CRYSTAL_SPOTS while fewer than CRYSTALS_BUSY crystals are on, CRYSTALS_FEW after that, never past CRYSTAL_MAX;
--.. with the budget full, a zombie CRYSTAL_STEAL nearer the camera than the farthest holder takes that one's
--.. crystals. None while it is inside an ice block. OnBatch calls this nearest zombie first.
local function GrowCrystals(st)
	if st.Block then return end
	if st.Crystals then
		if CrystalsIntact(st.Crystals) then return end
		PopCrystals(st)
	end
	if not Room("Crystal") then
		local victim = FarthestHolder(st.Dist or 0, st)
		local freed = 0
		if victim then
			for _, c in ipairs(victim.Crystals) do
				if c.Parent then freed += 1 end
			end
		end
		if freed == 0 or Prune(CrystalParts) - freed >= CRYSTAL_MAX
			or Prune(LiveParts) - freed >= MAX_PARTS - BLOCK_RESERVE - DEBRIS_MIN then return end
		PopCrystals(victim)
	end
	local live = Prune(CrystalParts)
	local want = math.min(live < CRYSTALS_BUSY and #CRYSTAL_SPOTS or CRYSTALS_FEW, CRYSTAL_MAX - live)
	local zombie = st.Zombie
	local torso = zombie:FindFirstChild("UpperTorso")
	local zscale = math.clamp(torso and torso:IsA("BasePart") and torso.Size.X / 2 or 1, 0.5, 2.2)
	local list = {}
	for _, spot in ipairs(CRYSTAL_SPOTS) do
		if #list >= want then break end
		local body = zombie:FindFirstChild(spot.Part)
		if body and body:IsA("BasePart") then
			local size = CRYSTAL_SIZE * zscale * (0.8 + math.random() * 0.4)
			local tilt = CFrame.Angles(math.rad(spot.Tilt.X), math.rad(spot.Tilt.Y + math.random(-20, 20)), math.rad(spot.Tilt.Z))
			local cf = body.CFrame * CFrame.new(body.Size * spot.At) * tilt * CFrame.new(0, size.Y * 0.3, 0) * CFrame.Angles(0, math.rad(45), 0)
			local crystal = StatePart("Crystal", "Part", {
				Name = "FrostCrystal", Size = size * 0.3, CFrame = cf, Color = ICE[math.random(1, #ICE)],
				Material = Enum.Material.Ice, Transparency = 0.12, Reflectance = 0.25,
			}, SAFETY_LIFE)
			if not crystal then break end
			StickTo(crystal, body)
			TweenService:Create(crystal, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = size}):Play()
			table.insert(list, crystal)
		end
	end
	st.Crystals = #list > 0 and list or nil
end

--.. the slow is over (or the zombie died): the crystals drop off and melt away
local function ShedCrystals(st)
	local list = st.Crystals
	st.Crystals = nil
	if not list then return end
	local ground
	for _, c in ipairs(list) do
		if c.Parent then
			ground = ground or GroundY(c.Position)
			c.Anchored = true
			local weld = c:FindFirstChildOfClass("WeldConstraint")
			if weld then weld:Destroy() end
			Fling(c, RandomFlat() * Rand({1, 3}) + Vector3.new(0, Rand({2, 5}), 0), RandomSpin(8), ground + c.Size.X * 0.5, 0.9)
		end
	end
end

--.. freeze pulse: a translucent Ice block round the zombie (+ two jagged spikes) for `stun` seconds; the block may
--.. use the whole part budget (the reserve is kept for it), the spikes are decoration (debris budget)
local function Encase(st, stun)
	local zombie = st.Zombie
	local root = zombie:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return end
	st.BlockUntil = math.max(st.BlockUntil, os.clock() + stun)
	if st.Block and st.Block[1].Parent then return end
	local ok, cf, size = pcall(function() return zombie:GetBoundingBox() end)
	if not ok or not cf then return end
	size = Vector3.new(math.min(size.X, 8), math.min(size.Y, 14), math.min(size.Z, 8)) + Vector3.new(0.8, 0.5, 0.8)
	local block = StatePart("Block", "Part", {
		Name = "IceBlock", Size = size * 0.7, CFrame = cf, Color = FROST.Block,
		Material = Enum.Material.Ice, Transparency = 0.42, Reflectance = 0.12,
	}, stun + 4)
	if not block then return end
	PopCrystals(st) -- inside the ice now: their budget goes to other zombies
	StickTo(block, root)
	TweenService:Create(block, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = size}):Play()
	local parts = {block}
	for i = 1, 2 do
		local side = i == 1 and 1 or -1
		local csize = Vector3.new(0.5, 1.3, 0.5) * math.clamp(size.X / 3, 0.6, 1.6)
		local ccf = cf * CFrame.new(side * size.X * 0.3, size.Y * 0.5, -side * size.Z * 0.2)
			* CFrame.Angles(0, math.rad(45), math.rad(-side * 22)) * CFrame.new(0, csize.Y * 0.25, 0)
		local spike = StatePart("Debris", "Part", {
			Name = "IceSpike", Size = csize, CFrame = ccf, Color = ICE[1],
			Material = Enum.Material.Ice, Transparency = 0.25, Reflectance = 0.2,
		}, stun + 4)
		if spike then
			StickTo(spike, root)
			table.insert(parts, spike)
		end
	end
	st.Block = parts
end

--.. the stun is over: the block bursts, shards fly
local function Shatter(st)
	local parts = st.Block
	st.Block = nil
	st.BlockUntil = 0
	if not parts then return end
	local main = parts[1]
	local pos, size = main.Position, main.Size
	local alive = main.Parent ~= nil
	for _, p in ipairs(parts) do
		if p.Parent then p:Destroy() end
	end
	if not alive then return end
	local d = (CamPos() - pos).Magnitude
	if d > MAX_DIST then return end
	Burst("IceBurst", pos, 1)
	if d <= PART_DIST then Scatter(pos, 8, SHARD_BIG, nil, size * 0.35) end
end

local function Release(st)
	DropHighlight(st)
	if st.Block then Shatter(st) end
	if st.Crystals then ShedCrystals(st) end
end

local function StepZombies(now)
	for zombie, st in pairs(ZState) do
		local hum = st.Humanoid
		if not zombie.Parent or not hum or hum.Health <= 0 or zombie:GetAttribute("Dead") == true
			or zombie:GetAttribute("Shaded") == true then
			--.. dead: the ice shatters, the crystals drop off, the tint goes; shaded (a shadow zombie phasing out,
			--.. ZombieRaidService SetShade): the same at once, so nothing of ours gives the hidden zombie away
			Release(st)
			ZState[zombie] = nil
		else
			local tinted = Tint(st, now)
			if st.Crystals and now - st.FrostLast > FROST.CrystalHold then ShedCrystals(st) end
			if st.Block and now >= st.BlockUntil then Shatter(st) end
			if not tinted and not st.Crystals and not st.Block then ZState[zombie] = nil end
		end
	end
end

--..Hit effects, per kind..--
local RecentBursts = {} -- {Pos, Time}: one shockwave ring per mortar burst however many zombies it hit

local function NewBurst(centre, now)
	for i = #RecentBursts, 1, -1 do
		local b = RecentBursts[i]
		if now - b.Time > 0.6 then
			table.remove(RecentBursts, i)
		elseif (b.Pos - centre).Magnitude < 2 then
			return false
		end
	end
	table.insert(RecentBursts, {Pos = centre, Time = now})
	return true
end

local Hit = {}

local CrystalQueue = {} -- slowed zombie states of this batch: OnBatch grows their crystals afterwards, nearest first

function Hit.Frost(ev, pos, zombie, dist, now)
	local x = type(ev.x) == "table" and ev.x or {}
	local near = dist <= PART_DIST
	if zombie then
		local st = StateOf(zombie)
		st.FrostLast = now
		st.Dist = dist
		if near then
			if x.pulse then Encase(st, tonumber(x.stun) or FROST.Stun) end -- the block first (its reserve), then the rest
			if not st.Block then table.insert(CrystalQueue, st) end
		end
	end
	if x.pulse then
		Burst("IceBurst", pos, near and 1 or 0.5)
		if near then Scatter(pos, 6, SHARD_BIG) end
	else
		Burst("Frost", pos, near and 1 or 0.5)
		if near then Scatter(pos, 2, SHARD) end
	end
end

local function GrowQueued()
	if #CrystalQueue == 0 then return end
	local queue = CrystalQueue
	CrystalQueue = {}
	table.sort(queue, function(a, b) return (a.Dist or 0) < (b.Dist or 0) end)
	for _, st in ipairs(queue) do
		if ZState[st.Zombie] == st and st.Zombie.Parent then GrowCrystals(st) end
	end
end

function Hit.Tesla(ev, pos, zombie, dist, now)
	Burst("Tesla", pos, dist <= PART_DIST and 1 or 0.6)
	if zombie then Flash(StateOf(zombie), FLASH.Tesla, now) end
end

function Hit.Laser(ev, pos, zombie, dist, now)
	Burst("Laser", pos, dist <= PART_DIST and 1 or 0.5)
	if zombie then StateOf(zombie).LaserLast = now end
end

local function FromOf(ev)
	local from = type(ev.x) == "table" and ev.x.from or nil
	return typeof(from) == "Vector3" and from or nil
end

function Hit.Turret(ev, pos, zombie, dist, now)
	local from = FromOf(ev)
	if from and (from - pos).Magnitude > 0.7 then pos += (from - pos).Unit * 0.6 end -- on the side facing the gun
	Burst("Turret", pos, 1, from)
end

function Hit.Minigun(ev, pos, zombie, dist, now)
	local from = FromOf(ev)
	pos += Vector3.new((math.random() - 0.5) * 0.9, (math.random() - 0.5) * 1.2, (math.random() - 0.5) * 0.9)
	if from and (from - pos).Magnitude > 0.7 then pos += (from - pos).Unit * 0.5 end
	Burst("Minigun", pos, 1, from)
end

function Hit.Mortar(ev, pos, zombie, dist, now)
	Burst("MortarHit", pos, dist <= PART_DIST and 1 or 0.5)
	if zombie then Flash(StateOf(zombie), FLASH.Mortar, now) end
	local c = type(ev.x) == "table" and ev.x.c or nil
	if typeof(c) ~= "Vector3" or not NewBurst(c, now) then return end
	local ground = GroundY(c + Vector3.new(0, 4, 0))
	local at = Vector3.new(c.X, ground + 0.15, c.Z)
	local d = (CamPos() - at).Magnitude
	if d > MAX_DIST then return end
	Burst("MortarRing", at, 1)
	Burst("MortarDirt", at, d <= PART_DIST and 1 or 0.5)
	if d <= PART_DIST then Scatter(at + Vector3.new(0, 0.5, 0), 5, CHUNK, ground) end
end

function Hit.Catapult(ev, pos, zombie, dist, now)
	local ground = GroundY(pos)
	local feet = Vector3.new(pos.X, ground + 0.4, pos.Z)
	Burst("Catapult", feet, dist <= PART_DIST and 1 or 0.5)
	if dist <= PART_DIST then Scatter(feet, 3, CHIP, ground) end
end

function Hit.Spikes(ev, pos, zombie, dist, now)
	Burst("Spikes", pos + Vector3.new(0, 0.3, 0), dist <= PART_DIST and 1 or 0.5)
end

--.. one event {k, z, p, x}: on the zombie as THIS client draws it when it has it, else at the server's point
local function Play(ev, now, camPos)
	local handler = Hit[ev.k]
	if not handler then return end
	local zombie = ev.z
	if typeof(zombie) ~= "Instance" or not zombie.Parent or not zombie:IsA("Model") then zombie = nil end
	local pos = typeof(ev.p) == "Vector3" and ev.p or nil
	local torso = zombie and TorsoOf(zombie)
	if torso then
		if ev.k == "Spikes" and pos then
			pos = Vector3.new(torso.Position.X, pos.Y, torso.Position.Z) -- the plate under its feet
		else
			pos = torso.Position
		end
	else
		zombie = nil
	end
	if not pos then return end
	local dist = (camPos - pos).Magnitude
	if dist > MAX_DIST then return end
	--.. particles yes, no new state (tint / crystals / block) on a corpse or on a shaded (phased-out) shadow zombie
	if zombie and (zombie:GetAttribute("Dead") == true or zombie:GetAttribute("Shaded") == true) then zombie = nil end
	handler(ev, pos, zombie, dist, now)
end

local Events = 0
local function OnBatch(list)
	if type(list) ~= "table" then return end
	local now = os.clock()
	local camPos = CamPos()
	local frostSeen = {} -- two towers chilling one zombie in the same tick: one burst (a pulse always plays)
	for i, ev in ipairs(list) do
		if i > 60 then break end
		if type(ev) == "table" then
			local skip = false
			if ev.k == "Frost" and typeof(ev.z) == "Instance" then
				local pulse = type(ev.x) == "table" and ev.x.pulse == true
				local seen = frostSeen[ev.z]
				if seen == "pulse" or (seen and not pulse) then skip = true end
				frostSeen[ev.z] = pulse and "pulse" or (seen or "slow")
			end
			if not skip then
				local ok, err = pcall(Play, ev, now, camPos)
				if not ok then Warn(err) end
			end
		end
	end
	local ok, err = pcall(GrowQueued)
	if not ok then
		CrystalQueue = {}
		Warn(err)
	end
	Events += #list
end

--..Idle effects on placed defences..--
local Idle = {} -- [model] = {Model, Spec, Glows, Insts, Mists, Points, Spark, SparkAtt, NextSpark, InRange, Phase}

local function TemplateOf(model)
	local root = ReplicatedStorage:FindFirstChild("PlaceableBuilds")
	local folder = root and root:FindFirstChild(DEFENCES)
	return folder and folder:FindFirstChild(Kit.Key(model) or "") or nil
end

local function IsDefence(model)
	return model:GetAttribute("Category") == DEFENCES or TemplateOf(model) ~= nil
end

--.. a Glow part's authored transparency: the template's twin, else its own (a broken fade left over reads as 0)
local function BaseTransparency(template, part)
	local twin = template and template:FindFirstChild(part.Name, true)
	if twin and twin:IsA("BasePart") then return twin.Transparency end
	local t = part.Transparency
	if t >= BROKEN_T - 0.01 then return 0 end
	return t
end

local function IdleStop(model)
	local rec = Idle[model]
	if not rec then return end
	Idle[model] = nil
	for _, g in ipairs(rec.Glows) do
		local part = g.Part
		--.. only undo our own pulse: a value the server wrote since (the broken fade) stays
		if g.Last and not g.Foreign and part.Parent and math.abs(part.Transparency - g.Last) < 0.002 then part.Transparency = g.Base end
	end
	for _, inst in ipairs(rec.Insts) do inst:Destroy() end
end

local function IdleStart(model)
	if Idle[model] or Kit.IsBroken(model) or not Kit.Hitbox(model) or not model:IsDescendantOf(workspace) then return end
	local key = Kit.Key(model)
	local spec = IDLE[key] or IDLE[Kit.Split(key) or ""] or IDLE_DEFAULT
	local rec = {Model = model, Spec = spec, Glows = {}, Insts = {}, Mists = {}, Points = {}, NextSpark = 0, InRange = false, Phase = math.random() * 10}
	local template = TemplateOf(model)
	for i, part in ipairs(Kit.Parts(model, "Glow")) do
		local base = BaseTransparency(template, part)
		if base < 0.99 then table.insert(rec.Glows, {Part = part, Base = base, Top = math.min(1, base + GLOW_AMP), Offset = (i - 1) * spec.Wave}) end
	end
	--.. cold mist creeping outward from Pivot_Mist1..n
	local scale = Kit.Scale(model)
	local centre = Kit.ToWorld(model, Vector3.zero)
	for i = 1, 16 do
		local p = Kit.Pivot(model, "Mist" .. i)
		if not p then break end
		local out = Vector3.new(p.X - centre.X, 0, p.Z - centre.Z)
		out = out.Magnitude > 0.05 and out.Unit or Vector3.xAxis
		local att = Instance.new("Attachment")
		att.Name = "DefenceFX_Mist"
		att.Parent = workspace.Terrain
		att.WorldCFrame = CFrame.lookAt(p, p + out)
		local pe = MakeEmitter(att, {
			Texture = TEX.Smoke, Color = cseq(rgb(205, 235, 255), rgb(240, 250, 255)),
			Size = seq(0, 0.9 * scale, 0.5, 2.2 * scale, 1, 3.2 * scale), Transparency = seq(0, 1, 0.2, 0.55, 0.7, 0.72, 1, 1),
			Lifetime = range(2.5, 4), Speed = range(0.6 * scale, 1.4 * scale), Spread = Vector2.new(30, 12), Direction = FRONT,
			Acceleration = Vector3.new(0, -0.12, 0), Drag = 0.4, RotSpeed = range(-15, 15),
			LightEmission = 0.15, LightInfluence = 0.4, ZOffset = 0, Rate = MIST_RATE,
		})
		pe.Enabled = false -- on when the camera comes in range
		table.insert(rec.Insts, att)
		table.insert(rec.Mists, pe)
	end
	--.. sparks crackling at Pivot_Spark1..n (or the fallback pivots)
	if spec.Spark then
		for i = 1, 32 do
			local p = Kit.Pivot(model, "Spark" .. i)
			if not p then break end
			table.insert(rec.Points, p)
		end
		if #rec.Points == 0 and spec.Fallback then
			for _, name in ipairs(spec.Fallback) do
				local p = Kit.Pivot(model, name)
				if p then table.insert(rec.Points, p) end
			end
		end
		if #rec.Points > 0 then
			local att = Instance.new("Attachment")
			att.Name = "DefenceFX_Spark"
			att.Parent = workspace.Terrain
			rec.SparkAtt = att
			rec.Spark = MakeEmitter(att, {
				Texture = TEX.Spark, Color = cseq(WHITE, spec.Spark), Size = seq(0, 0.22 * scale, 1, 0),
				Lifetime = range(0.15, 0.35), Speed = range(3, 7), Drag = 3, Acceleration = Vector3.new(0, -10, 0),
				LightEmission = 1, LightInfluence = 0, Orientation = PARALLEL, ZOffset = 0.3,
			})
			table.insert(rec.Insts, att)
		end
	end
	if #rec.Glows == 0 and #rec.Mists == 0 and not rec.Spark then return end -- nothing to animate on this model
	Idle[model] = rec
end

local idleAcc, nextRangeCheck = 0, 0
local function StepIdle(now, dt)
	idleAcc += dt
	if idleAcc < 1 / IDLE_HZ then return end
	idleAcc = 0
	local camPos = CamPos()
	local checkRange = now >= nextRangeCheck
	if checkRange then nextRangeCheck = now + 0.25 end
	for model, rec in pairs(Idle) do
		if checkRange then
			local hitbox = Kit.Hitbox(model)
			local inRange = hitbox ~= nil and (hitbox.Position - camPos).Magnitude <= IDLE_RANGE
			if inRange ~= rec.InRange then
				rec.InRange = inRange
				for _, pe in ipairs(rec.Mists) do pe.Enabled = inRange end
			end
		end
		if rec.InRange and not Kit.IsBroken(model) then
			local w = 2 * math.pi / rec.Spec.Period
			for _, g in ipairs(rec.Glows) do
				if not g.Foreign then
					local part = g.Part
					if g.Last and math.abs(part.Transparency - g.Last) > 0.002 then
						g.Foreign = true -- the server changed it (the broken fade): hands off until the restart
					else
						local wave = 0.5 - 0.5 * math.cos(now * w + rec.Phase - g.Offset)
						part.Transparency = g.Base + (g.Top - g.Base) * wave
						g.Last = part.Transparency
					end
				end
			end
			if rec.Spark and now >= rec.NextSpark then
				rec.NextSpark = now + Rand(SPARK_GAP)
				rec.SparkAtt.WorldPosition = rec.Points[math.random(1, #rec.Points)]
				rec.Spark:Emit(math.random(2, 4))
			end
		end
	end
end

--..Watching placed builds (streaming in / out, moved, broken, mended)..--
local Watched = {} -- [model] = {connections}

local function Unwatch(model)
	IdleStop(model)
	local conns = Watched[model]
	if conns then
		for _, c in ipairs(conns) do c:Disconnect() end
		Watched[model] = nil
	end
end

local function Watch(model)
	if Watched[model] or not model:IsA("Model") or not model:IsDescendantOf(workspace) then return end
	--.. the BuildKey attribute and the Hitbox may land a moment after the tag while streaming
	if not Kit.Key(model) or not Kit.Hitbox(model) then
		local t0 = os.clock()
		while (not Kit.Key(model) or not Kit.Hitbox(model)) and os.clock() - t0 < 10 and model.Parent do task.wait(0.1) end
	end
	if Watched[model] or not model:IsDescendantOf(workspace) then return end
	local hitbox = Kit.Hitbox(model)
	if not hitbox or not IsDefence(model) then return end
	local conns = {}
	Watched[model] = conns
	local pending = false
	local function queue()
		if pending then return end
		pending = true
		task.delay(0.3, function()
			pending = false
			if Watched[model] then
				IdleStop(model)
				IdleStart(model)
			end
		end)
	end
	table.insert(conns, hitbox:GetPropertyChangedSignal("CFrame"):Connect(queue))
	table.insert(conns, model:GetAttributeChangedSignal("Broken"):Connect(function()
		if Kit.IsBroken(model) then IdleStop(model) end -- at once: never pulse over the broken fade
		queue()
	end))
	table.insert(conns, model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and d.Name:sub(1, 4) == "Glow" then queue() end -- a part streaming in late
	end))
	table.insert(conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then Unwatch(model) end
	end))
	IdleStart(model)
end

CollectionService:GetInstanceAddedSignal(Kit.PLACED_TAG):Connect(function(model) task.spawn(Watch, model) end)
CollectionService:GetInstanceRemovedSignal(Kit.PLACED_TAG):Connect(Unwatch)
for _, model in ipairs(CollectionService:GetTagged(Kit.PLACED_TAG)) do task.spawn(Watch, model) end

--..Frame loop..--
RunService.Heartbeat:Connect(function(dt)
	Frame += 1 -- one render per Heartbeat: emission points used 2 Heartbeats ago are free again (Burst)
	local now = os.clock()
	local ok, err = pcall(StepFlyers, now, dt)
	if not ok then Warn(err) end
	ok, err = pcall(StepZombies, now)
	if not ok then Warn(err) end
	ok, err = pcall(StepIdle, now, dt)
	if not ok then Warn(err) end
end)

--..Studio test hook..--
local function TestHit(value)
	local kind, flag = tostring(value):match("^(%a+):?(%a*)$")
	if not kind or not Hit[kind] then
		warn("[DefenceFXClient] DefenceFXTest: unknown kind " .. tostring(value))
		return
	end
	local cam = workspace.CurrentCamera
	local camPos = CamPos()
	local best, bestDist
	local folder = workspace:FindFirstChild(ZOMBIE_FOLDER)
	if folder then
		for _, z in ipairs(folder:GetChildren()) do
			local torso = z:IsA("Model") and TorsoOf(z)
			if torso then
				local d = (torso.Position - camPos).Magnitude
				if d <= 200 and (not bestDist or d < bestDist) then best, bestDist = z, d end
			end
		end
	end
	local p = best and TorsoOf(best).Position or (camPos + (cam and cam.CFrame.LookVector or Vector3.zAxis) * 14)
	local x = {slow = true, from = camPos, c = p - Vector3.new(0, 2.5, 0)}
	if flag == "pulse" then
		x.pulse = true
		x.stun = FROST.Stun
	end
	OnBatch({{k = kind, z = best, p = p, x = x}})
end

workspace:GetAttributeChangedSignal("DefenceFXTest"):Connect(function()
	local value = workspace:GetAttribute("DefenceFXTest")
	if value == nil then return end
	workspace:SetAttribute("DefenceFXTest", nil)
	TestHit(value)
end)

--..Stats (read them in a playtest to check the budget numerically)..--
task.spawn(function()
	while true do
		task.wait(0.5)
		local tinted, idle = 0, 0
		for _ in pairs(ZState) do tinted += 1 end
		for _ in pairs(Idle) do idle += 1 end
		script:SetAttribute("LiveParts", Prune(LiveParts))
		script:SetAttribute("Crystals", Prune(CrystalParts))
		script:SetAttribute("EmitPoints", EmitPoints)
		script:SetAttribute("BurstsSkipped", BurstsSkipped)
		script:SetAttribute("Highlights", HighlightCount)
		script:SetAttribute("Tinted", tinted)
		script:SetAttribute("IdleBuilds", idle)
		script:SetAttribute("Events", Events)
	end
end)

--..Server events (the remote can arrive after the idle effects are running)..--
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 60)
	local remote = remotes and remotes:WaitForChild(REMOTE, 60)
	if not remote then
		warn("[DefenceFXClient] ReplicatedStorage.Remotes." .. REMOTE .. " never appeared: hit effects off (idle effects still run)")
		return
	end
	remote.OnClientEvent:Connect(OnBatch)
end)

print("[DefenceFXClient] ready")
