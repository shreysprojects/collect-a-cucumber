--[[
	Pond  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLights
	Client-only behaviour for the koi pond (no server half: nothing is shared but the clock, Kit.Now()).
	  * three KOI built from local parts (ellipsoid body + eyes + koi-pattern spots + pectoral paddles + dorsal fin
	    + a forked two-wedge tail that wags faster when the fish speeds up; 10 parts each, local only) swim lazy
	    loops just under Pivot_WaterSurface, one loop near each of the Fish1..3 pivots. The loops were fitted
	    offline to the real waterline (the 9-point shore of props/build_pond.py: 0.2+ authored studs of clearance
	    for nose and tail, loops kept apart); speed glides in and out, fish bank into their turns, and Fish1's tall
	    dorsal fin cuts the surface like the authored one did.
	    The static Fish1..3 / FishEyes / FishMarks meshes are hidden LOCALLY (LocalTransparencyModifier, so the
	    server's Transparency - and BuildHealthService's broken fade / mend - is never touched) and shown again on
	    cleanup. BuildMenuClient's move ghost writes LocalTransparencyModifier on every build part (0.85 while the
	    build is on the mouse, back to 0 when the move ends) and a cancelled / same-spot move doesn't restart this
	    behaviour, so the static koi are re-hidden whenever anything lowers it; the swimming koi copy the ghost
	    value from the Bank so they fade with the rest of the pond during a move.
	  * RIPPLES: flat expanding rings (built-in shockwave texture lying on the water) now and then in open water,
	    where a koi noses the surface, a small wake behind Fish1's fin, and under anyone walking on the pond
	  * the lily pads (+ their lotus flowers) BOB: LilyPads and LilyLotus are one merged mesh each, so the whole
	    set rises / falls / drifts a few hundredths together; restored on cleanup relative to the current hitbox
	The Water part stays COLLIDABLE: it is the pond's surface (a zero-thickness sheet 0.34 above the bed), the
	water is only ~0.45 studs deep in the world, and letting people sink to the bed would only put their feet
	through the koi and the lily pads - so people walk ON the pond and leave ripples instead.
	Authored frame here = the Roblox one: Blender (x, y, z) -> (x, z, -y).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local WATER_Y = 0.50             -- authored fallback for Pivot_WaterSurface
local HIDE = {"Fish1", "Fish2", "Fish3", "FishEyes", "FishMarks"} -- the static koi the swimming ones replace
local GHOST = {"Bank", "Water", "Bed"} -- a build part whose LocalTransparencyModifier (build-mode move ghost) the koi copy
local ORANGE = Color3.fromRGB(255, 138, 61)  -- accent_orange ff8a3d (the authored koi)
local WHITE = Color3.fromRGB(242, 239, 228)  -- flower_white f2efe4
local EYE = Color3.fromRGB(35, 38, 44)       -- plastic_black 23262c
local FIN_ORANGE = Color3.fromRGB(255, 172, 112)
local FIN_WHITE = Color3.fromRGB(250, 247, 238)
local FIN_ALPHA = 0.15
local TAIL_WAG = math.rad(22)    -- tail swing each side
local TAIL_ROOT = 0.46           -- body-local z of the tail root (x fish size)
local TAIL_W, TAIL_L = 0.22, 0.34 -- each tail half: width across, length back (x fish size)
local TAIL_FORK = math.rad(8)    -- each tail lobe splays outward this much (the forked koi tail)
local PECTORAL_SWEEP = math.rad(35) -- pectoral fins swept back
local BANK = 0.25                -- roll per rad/s of turning (clamped to BANK_MAX)
local BANK_MAX = 0.2
--.. the koi. Centre/RX/RZ/Rot: an ellipse in the authored XZ plane (fitted to the shoreline offline); Period s per
--.. loop, Dir +1/-1; Glide/GlidePeriod: a time warp so they speed up and glide (Glide * 2pi/GlidePeriod < 2pi/Period);
--.. Under: studs below the water surface; Size: the authored fish scale; Beats: tail beats per loop
local FISH = {
	{Name = "Fish1", Centre = Vector2.new(1.60, -0.20), RX = 1.30, RZ = 0.90, Rot = -20, Period = 13.0, Dir = 1,
		Glide = 0.35, GlidePeriod = 5.3, Phase = 0.0, Under = 0.15, Size = 1.00, Koi = "Orange", Sail = 0.145, Beats = 24, Wake = true},
	{Name = "Fish2", Centre = Vector2.new(-0.70, 0.90), RX = 0.62, RZ = 0.50, Rot = 35, Period = 11.0, Dir = -1,
		Glide = 0.30, GlidePeriod = 4.1, Phase = 2.1, Under = 0.17, Size = 0.94, Koi = "White", Sail = 0.09, Beats = 16},
	{Name = "Fish3", Centre = Vector2.new(-1.62, -0.95), RX = 0.60, RZ = 0.70, Rot = 25, Period = 9.5, Dir = 1,
		Glide = 0.30, GlidePeriod = 3.7, Phase = 4.0, Under = 0.16, Size = 0.84, Koi = "Orange", Sail = 0.09, Beats = 16},
}
--.. koi-pattern spots, body-local (x fish size): white saddles on the orange koi, red-orange patches on the white one
local SPOTS = {
	Orange = {
		{Pos = Vector3.new(0, 0.112, -0.16), Size = Vector3.new(0.16, 0.06, 0.26)},
		{Pos = Vector3.new(0, 0.114, 0.14), Size = Vector3.new(0.13, 0.05, 0.20)},
	},
	White = {
		{Pos = Vector3.new(0, 0.105, -0.24), Size = Vector3.new(0.20, 0.06, 0.30)},
		{Pos = Vector3.new(0.02, 0.112, 0.10), Size = Vector3.new(0.16, 0.055, 0.26)},
	},
}
--.. the open waterline (authored XZ, inner shore x 1.008 of build_pond.py's ring) and the lily pads (x, z, radius)
local SHORE = {
	Vector2.new(3.785, -0.488), Vector2.new(2.912, -2.326), Vector2.new(0.603, -1.860), Vector2.new(-1.016, -2.620),
	Vector2.new(-3.261, -1.660), Vector2.new(-2.534, 0.856), Vector2.new(-0.982, 2.055), Vector2.new(1.788, 2.361),
	Vector2.new(3.132, 0.556),
}
local PADS = {
	Vector3.new(-2.00, -1.20, 0.68), Vector3.new(-0.55, -1.76, 0.46), Vector3.new(2.25, -0.92, 0.52),
	Vector3.new(0.65, 1.53, 0.58), Vector3.new(-2.10, 0.45, 0.40),
}
--.. ripples
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds" -- engine built-in soft ring
local RING_COLOR = Color3.fromRGB(222, 242, 255)
local RING_LIFT = 0.025          -- authored studs above the water
local RANDOM_RIPPLE = {1.4, 3.2} -- s between open-water ripples
local KISS_RIPPLE = {3.0, 6.0}   -- s between "a koi noses the surface" ripples
local WAKE_EVERY = 0.7           -- s between Fish1 fin-wake rings
local SHORE_MARGIN = 0.45        -- authored studs a random ripple keeps from the waterline
local WALK_SPEED = 1.5           -- studs/s a character on the pond must move to leave ripples
--.. lily pad bob (authored studs / degrees)
local BOB_AMP, BOB_PERIOD = 0.03, 3.1
local BOB_TILT, BOB_YAW = 0.6, 1.5

local B = {}
B.StepRange = 150

--..Helpers..--
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

--.. a local-only part of any class (ctx:Part only makes Parts; the tail and fins are WedgeParts)
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

local function Ellipsoid(ctx, size, color, name)
	local p = LocalPart(ctx, "Part", {Name = name, Size = size, Color = color})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function InsideShore(x, z)
	local inside = false
	local n = #SHORE
	for i = 1, n do
		local a, b = SHORE[i], SHORE[i % n + 1]
		if (a.Y > z) ~= (b.Y > z) and x < (b.X - a.X) * (z - a.Y) / (b.Y - a.Y) + a.X then inside = not inside end
	end
	return inside
end

local function ShoreDistance(x, z)
	local best = math.huge
	local n = #SHORE
	for i = 1, n do
		local a, b = SHORE[i], SHORE[i % n + 1]
		local d = b - a
		local t = math.clamp(((x - a.X) * d.X + (z - a.Y) * d.Y) / d:Dot(d), 0, 1)
		best = math.min(best, (Vector2.new(x, z) - (a + d * t)).Magnitude)
	end
	return best
end

--.. a random open-water point (authored XZ) clear of the shore and the pads, or nil
local function RandomOpenWater(rng)
	for _ = 1, 12 do
		local x, z = rng:NextNumber(-3.2, 3.7), rng:NextNumber(-2.6, 2.3)
		if InsideShore(x, z) and ShoreDistance(x, z) > SHORE_MARGIN then
			local clear = true
			for _, pad in ipairs(PADS) do
				if (Vector2.new(x, z) - Vector2.new(pad.X, pad.Y)).Magnitude < pad.Z + 0.2 then clear = false break end
			end
			if clear then return x, z end
		end
	end
	return nil
end

--.. builds one koi: {Spec, K, Body = {{part, offset}}, Tail = {{part, offset from the tail root}}}
local function BuildKoi(ctx, spec, scale)
	local k = spec.Size * scale
	local main = spec.Koi == "White" and WHITE or ORANGE
	local accent = spec.Koi == "White" and ORANGE or WHITE
	local finColor = spec.Koi == "White" and FIN_WHITE or FIN_ORANGE
	local koi = {Spec = spec, K = k, Body = {}, Tail = {}}
	--.. body: an ellipsoid 0.37 x 0.25 x 1.04 (the authored koi's proportions), nose toward -Z
	table.insert(koi.Body, {Ellipsoid(ctx, Vector3.new(0.374, 0.254, 1.04) * k, main, "KoiBody"), CFrame.identity})
	for _, side in ipairs({-1, 1}) do
		local eye = LocalPart(ctx, "Part", {Name = "KoiEye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.09 * k, Color = EYE})
		table.insert(koi.Body, {eye, CFrame.new(side * 0.135 * k, 0.05 * k, -0.35 * k)})
		--.. pectoral fin: a flat paddle behind the head, swept back
		local pec = Ellipsoid(ctx, Vector3.new(0.22, 0.025, 0.12) * k, finColor, "KoiPectoral")
		pec.Transparency = FIN_ALPHA
		table.insert(koi.Body, {pec, CFrame.new(side * 0.2 * k, -0.035 * k, -0.15 * k) * CFrame.Angles(0, -side * PECTORAL_SWEEP, 0)})
	end
	for _, spot in ipairs(SPOTS[spec.Koi] or SPOTS.Orange) do
		table.insert(koi.Body, {Ellipsoid(ctx, spot.Size * k, accent, "KoiSpot"), CFrame.new(spot.Pos * k)})
	end
	--.. dorsal fin: a thin wedge, tall toward the back; Fish1's is tall enough to break the surface
	local fin = LocalPart(ctx, "WedgePart", {Name = "KoiFin", Size = Vector3.new(0.05, spec.Sail, 0.40) * k, Color = finColor, Transparency = FIN_ALPHA})
	table.insert(koi.Body, {fin, CFrame.new(0, (0.05 + spec.Sail * 0.5) * k, 0.02 * k)})
	--.. tail: two flat wedges fanning out behind the root (each wedge's triangle turned to lie in the XZ plane:
	--.. sharp end at the root, wide end back), each splayed TAIL_FORK outward so a notch opens between the lobes
	local half = Vector3.new(0.035, TAIL_W, TAIL_L) * k
	local right = LocalPart(ctx, "WedgePart", {Name = "KoiTail", Size = half, Color = finColor, Transparency = FIN_ALPHA})
	local left = LocalPart(ctx, "WedgePart", {Name = "KoiTail", Size = half, Color = finColor, Transparency = FIN_ALPHA})
	table.insert(koi.Tail, {right, CFrame.Angles(0, TAIL_FORK, 0) * CFrame.new(TAIL_W * 0.5 * k, 0, TAIL_L * 0.5 * k) * CFrame.Angles(0, 0, -math.pi / 2)})
	table.insert(koi.Tail, {left, CFrame.Angles(0, -TAIL_FORK, 0) * CFrame.new(-TAIL_W * 0.5 * k, 0, TAIL_L * 0.5 * k) * CFrame.Angles(0, 0, math.pi / 2)})
	return koi
end

--.. where a koi is at server time t: authored position, heading (authored XZ velocity), turn rate (rad/s), loop progress
local function KoiPose(spec, t, phase)
	local w, w2 = 2 * math.pi / spec.Period, 2 * math.pi / spec.GlidePeriod
	local progress = w * t + spec.Glide * math.sin(w2 * t)       -- always increasing (Glide * w2 < w)
	local rate = spec.Dir * (w + spec.Glide * w2 * math.cos(w2 * t)) -- ds/dt
	local s = spec.Dir * progress + spec.Phase + phase
	local a = math.rad(spec.Rot)
	local ca, sa = math.cos(a), math.sin(a)
	local ex, ez = spec.RX * math.cos(s), spec.RZ * math.sin(s)
	local dx, dz = -spec.RX * math.sin(s), spec.RZ * math.cos(s)  -- d/ds before rotation
	local x = spec.Centre.X + ex * ca - ez * sa
	local z = spec.Centre.Y + ex * sa + ez * ca
	local hx, hz = (dx * ca - dz * sa) * rate, (dx * sa + dz * ca) * rate
	local turn = rate * spec.RX * spec.RZ / math.max(1e-4, dx * dx + dz * dz) -- > 0 = turning to the fish's right
	return x, z, hx, hz, turn, progress
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local scale = ctx.Scale
	local surface = model:GetAttribute("Pivot_WaterSurface")
	local waterY = typeof(surface) == "Vector3" and surface.Y or WATER_Y
	local seedPhase = ((hitbox.Position.X * 0.61 + hitbox.Position.Z * 0.37) % 6.283)
	local rng = Random.new()

	--..Hide the static koi (locally)..--
	--.. BuildMenuClient sets LocalTransparencyModifier = 0.85 on every part of a build being moved and StopPlacing
	--.. puts it back to 0; a cancelled move (or a drop on the same spot) leaves the hitbox where it was, so nothing
	--.. restarts this behaviour - hide them again whenever anything lowers it. The ctx:Alive() guard matters:
	--.. FunBuildClient.Stop marks the ctx dead BEFORE running the cleanup below, which shows them again
	local hidden = {}
	for _, name in ipairs(HIDE) do
		local part = Kit.Part(model, name)
		if part then
			part.LocalTransparencyModifier = 1
			table.insert(hidden, part)
			ctx:Connect(part:GetPropertyChangedSignal("LocalTransparencyModifier"), function()
				if ctx:Alive() and part.Parent and part.LocalTransparencyModifier < 1 then part.LocalTransparencyModifier = 1 end
			end)
		end
	end

	--..Swimming koi..--
	local kois = {}
	for _, spec in ipairs(FISH) do table.insert(kois, BuildKoi(ctx, spec, scale)) end
	local moveParts, moveCFrames = {}, {}
	for _, koi in ipairs(kois) do
		for _, item in ipairs(koi.Body) do table.insert(moveParts, item[1]) end
		for _, item in ipairs(koi.Tail) do table.insert(moveParts, item[1]) end
	end

	--.. the swimming koi are local parts BuildMenuClient never sees: copy its move ghost from a build part so they
	--.. fade with the rest of the pond while it is on the mouse (and come back when the move ends)
	local ghost
	for _, name in ipairs(GHOST) do
		ghost = Kit.Part(model, name)
		if ghost then break end
	end
	if ghost then
		local function FollowGhost()
			if not ctx:Alive() then return end
			local g = ghost.LocalTransparencyModifier
			for _, part in ipairs(moveParts) do part.LocalTransparencyModifier = g end
		end
		ctx:Connect(ghost:GetPropertyChangedSignal("LocalTransparencyModifier"), FollowGhost)
		FollowGhost()
	end

	--..Lily pad bob rig..--
	local pads = Kit.Part(model, "LilyPads")
	local bobRig, bobRel
	if pads then
		local bobParts = {pads}
		local lotus = Kit.Part(model, "LilyLotus")
		if lotus then table.insert(bobParts, lotus) end
		local bobPivot = CFrame.new(pads.Position) * Kit.Origin(model).Rotation
		bobRel = hitbox.CFrame:ToObjectSpace(bobPivot)
		bobRig = Kit.Rig(bobParts, bobPivot)
	end

	--..Ripples: one movable attachment on a local anchor at the authored origin..--
	local anchor = ctx:Part({Name = "FunPondFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = Kit.Origin(model)})
	local rippleAt = Instance.new("Attachment")
	rippleAt.Name = "Ripple"
	rippleAt.Position = Vector3.new(0, waterY + RING_LIFT, 0) * scale
	rippleAt.Parent = anchor
	local function RingEmitter(size0, size1, life, alpha)
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "FunRipple"
		pe.Texture = TEX_RING
		pe.Rate = 0
		pe.Lifetime = NumberRange.new(life * 0.9, life * 1.1)
		pe.Speed = NumberRange.new(0.02)
		pe.SpreadAngle = Vector2.zero
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular -- lies flat on the water
		pe.Rotation = NumberRange.new(0, 360)
		pe.Size = NumberSequence.new({kp(0, size0 * scale), kp(1, size1 * scale)})
		pe.Transparency = NumberSequence.new({kp(0, alpha), kp(0.6, (1 + alpha) * 0.5 + 0.1), kp(1, 1)})
		pe.Color = ColorSequence.new(RING_COLOR)
		pe.LightEmission = 0.2
		pe.LightInfluence = 0.8
		pe.Parent = rippleAt
		return pe
	end
	local ripple = RingEmitter(0.25, 1.7, 1.5, 0.35)
	local wake = RingEmitter(0.12, 0.55, 0.8, 0.45)
	local function RippleAt(emitter, x, z, count)
		rippleAt.Position = Vector3.new(x, waterY + RING_LIFT, z) * scale
		emitter:Emit(count or 1)
	end

	--..Every frame: koi, pads, ripple timers..--
	local lastPose = {} -- [koi] = {x, z, hx, hz} (authored), for kisses / wakes
	for _, koi in ipairs(kois) do lastPose[koi] = {0, 0, 0, 0} end
	local nextRandom = Kit.Now() + rng:NextNumber(RANDOM_RIPPLE[1], RANDOM_RIPPLE[2])
	local nextKiss = Kit.Now() + rng:NextNumber(KISS_RIPPLE[1], KISS_RIPPLE[2])
	local nextWake = Kit.Now() + WAKE_EVERY
	ctx:Step(function(_, now)
		local origin = Kit.Origin(model)
		local n = 0
		for _, koi in ipairs(kois) do
			local spec, k = koi.Spec, koi.K
			local x, z, hx, hz, turn, progress = KoiPose(spec, now, seedPhase)
			local beat = math.sin(spec.Beats * progress)
			local wag = TAIL_WAG * beat
			local sway = 0.1 * math.sin(spec.Beats * progress - 1.2)          -- the head counter-swings the tail
			local roll = -math.clamp(turn * BANK, -BANK_MAX, BANK_MAX)
			local y = waterY - spec.Under + 0.012 * math.sin(now * 1.3 + spec.Phase * 3)
			local yaw = math.atan2(-hx, -hz)
			local fishCF = origin * CFrame.new(Vector3.new(x, y, z) * scale) * CFrame.Angles(0, yaw + sway, 0) * CFrame.Angles(0, 0, roll)
			for _, item in ipairs(koi.Body) do
				n += 1
				moveCFrames[n] = fishCF * item[2]
			end
			local tailCF = fishCF * CFrame.new(0, 0, TAIL_ROOT * k) * CFrame.Angles(0, wag, 0)
			for _, item in ipairs(koi.Tail) do
				n += 1
				moveCFrames[n] = tailCF * item[2]
			end
			local pose = lastPose[koi]
			pose[1], pose[2], pose[3], pose[4] = x, z, hx, hz
		end
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)

		if bobRig then
			local lift = BOB_AMP * scale * math.sin(now * 2 * math.pi / BOB_PERIOD)
			local tiltX = math.rad(BOB_TILT) * math.sin(now * 2 * math.pi / 3.7 + 0.5)
			local tiltZ = math.rad(BOB_TILT) * math.sin(now * 2 * math.pi / 4.9 + 2.0)
			local yaw = math.rad(BOB_YAW) * math.sin(now * 2 * math.pi / 7.3 + 1.0)
			Kit.PoseRig(bobRig, hitbox.CFrame * bobRel * CFrame.new(0, lift, 0) * CFrame.Angles(tiltX, yaw, tiltZ))
		end

		if now >= nextRandom then
			nextRandom = now + rng:NextNumber(RANDOM_RIPPLE[1], RANDOM_RIPPLE[2])
			local x, z = RandomOpenWater(rng)
			if x then RippleAt(ripple, x, z) end
		end
		if now >= nextKiss then
			nextKiss = now + rng:NextNumber(KISS_RIPPLE[1], KISS_RIPPLE[2])
			local pose = lastPose[kois[rng:NextInteger(1, #kois)]]
			if pose and (pose[3] ~= 0 or pose[4] ~= 0) then
				local speed = math.max(1e-4, math.sqrt(pose[3] * pose[3] + pose[4] * pose[4]))
				local nose = 0.4 -- authored studs ahead of the body centre
				RippleAt(ripple, pose[1] + pose[3] / speed * nose, pose[2] + pose[4] / speed * nose)
			end
		end
		if now >= nextWake then
			nextWake = now + WAKE_EVERY
			for _, koi in ipairs(kois) do
				local pose = lastPose[koi]
				if koi.Spec.Wake and (pose[3] ~= 0 or pose[4] ~= 0) then RippleAt(wake, pose[1], pose[2]) end
			end
		end
	end)

	--..Ripples under anyone walking on the pond..--
	local lastRipple = {} -- [player] = os.clock()
	ctx:Every(0.3, function()
		if ctx:CameraDistance() > B.StepRange then return end
		local origin = Kit.Origin(model)
		local clock = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and clock - (lastRipple[player] or 0) > 0.35 then
				local p = origin:PointToObjectSpace(root.Position) / scale
				local v = root.AssemblyLinearVelocity
				if p.Y > waterY - 0.2 and p.Y < waterY + 5 / scale and InsideShore(p.X, p.Z)
					and Vector3.new(v.X, 0, v.Z).Magnitude > WALK_SPEED then
					lastRipple[player] = clock
					RippleAt(ripple, p.X, p.Z)
				end
			end
		end
		for player in pairs(lastRipple) do
			if player.Parent == nil then lastRipple[player] = nil end
		end
	end)

	--..Cleanup: the static koi back, the pads at rest where the build is now..--
	return function()
		for _, part in ipairs(hidden) do
			if part.Parent then part.LocalTransparencyModifier = 0 end
		end
		if bobRig and hitbox.Parent then Kit.PoseRig(bobRig, hitbox.CFrame * bobRel) end
	end
end

return B
