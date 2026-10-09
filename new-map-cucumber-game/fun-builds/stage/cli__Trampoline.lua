--[[
	Trampoline  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the TRAMPOLINE functional build (fun-builds/CONTRACT.md; user: "trampoline bouncy").
	There is NO server half: the bounce is physics on the local player's own character (network-owned by
	this client) and the mat animation is cosmetic, so everything runs here.

	BOUNCE (the local character only). Every frame near the build: when the root is inside the mat radius
	(authored r 2.95 x Scale) and not rising, a short ray from the root (Include = the Mat* parts, length =
	hip height + a little + this frame's fall) hits the mat - or, as a fallback, the humanoid stands on the
	mat's material at mat height inside the radius - and the character is launched:
	Humanoid:ChangeState(Jumping) (no landing stun) + root.AssemblyLinearVelocity.Y = LAUNCH[level]
	(+ JUMP_BONUS while jump is held), horizontal velocity kept. The Jumping state's own jump impulse may
	REPLACE our Y velocity or ADD to it (not measured yet), and a bare velocity write on a grounded humanoid
	is eaten by the Running controller within a frame, so for ENFORCE_TIME a TWO-SIDED guard holds the launch:
	it sets the vertical speed that still peaks exactly at the launch apex from the height the root has
	reached (sqrt(V^2 - 2 g rise)) whenever the root is off by more than GUARD_SLACK - pushed back up when
	the impulse ate the launch, pulled down when it stacked on top (which would otherwise send a level-4
	bounce ~68 studs up). Working from the height, not the time, also cancels the frame the root flew wrong.
	A bounce that comes within the expected airtime + CHAIN_GAP of the last launch climbs the LAUNCH ladder
	(55 / 75 / 95 / 110 studs/s; gravity 196.2 -> ~7.7 .. 31 studs high); landing on anything that is not the
	mat, or missing the window, resets it. Humanoids that are seated, dead, ragdolled, frozen (WalkSpeed 0)
	or not allowed to jump (Jumping disabled / zero jump power: the carry & collect freezes) never bounce.
	Level >= FLIP_LEVEL bounces do a FRONT FLIP that is purely visual: the root joint's Transform (Motor6D or
	AnimationConstraint) is turned about the root's centre in Stepped (after the Animator, like the lying
	seats in FunBuildClient), the physics root stays upright, so it can never trip or fling the humanoid.
	Only this client sees its own flip (joint transforms do not replicate).

	MAT (every player's character this client sees). The Mat* parts (MatSurface) dip by State_Bottom (-0.5
	authored x Scale) and spring back with a damped oscillation (~0.4 s); the Springs ring follows a fraction
	of it. Kicks come from the local bounce, and from any other player's root that is inside the radius,
	moving down and about to meet the mat (time-to-contact lookahead, <= 4 studs above it). Their fall speed
	is the faster of the replicated AssemblyLinearVelocity and a position-based rate that only samples when
	the root has actually moved, over the real time between those samples (the Step can run twice a frame);
	the impact speed (pitch, ring) is extrapolated from there down to the mat. Parts are posed
	relative to the build's Hitbox (a move re-runs us and lands cleanly), nothing is written at rest, and
	cleanup puts them back. A Boing (FunAssets.Sfx.Boing) per bounce, pitch rising with the level (other
	players: with the impact speed); a dust + sparkle ring on big bounces (level >= RING_LEVEL).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

--..Config..--
local LAUNCH = {55, 75, 95, 110} -- studs/s up, per consecutive bounce
local JUMP_BONUS = 15            -- studs/s added while jump is held
local CHAIN_GAP = 0.6            -- s after the expected landing a bounce still counts as consecutive
local REBOUNCE_COOLDOWN = 0.2    -- s between two launches
local ENFORCE_TIME = 0.15        -- s the launch velocity is guarded against the Jumping impulse
local GUARD_SLACK = 1.5          -- studs/s off the launch trajectory (either way) before the guard steps in
local GUARD_DROP = 1             -- studs below the launch height: something else moved the root, stop guarding
local GUARD_EXTRA = 4            -- studs above the launch trajectory: ditto (a stacked jump stays well under this)
local CONTACT_TOLERANCE = 0.4    -- studs past the feet the ray still counts as touching the mat
local LOOKAHEAD = 1.1            -- x this frame's fall added to the ray (launch just before contact)
local FLOOR_TOLERANCE = 0.35     -- fallback: feet within this of the mat rim height
local WAKE_RADIUS = 14           -- studs beyond the mat radius the local bounce logic runs
local MAT_RADIUS = 2.95          -- authored (the dish rim)
local RIM_RISE = 1.20 - 0.68     -- authored: the dish rim above the mat centre
local MAT_CENTRE = Vector3.new(0, 0.68, 0) -- authored fallback when Pivot_MatCentre is missing
local DEFAULT_BOTTOM = -0.5      -- authored State_Bottom fallback
local FLIP_LEVEL = 4             -- bounces at this level and up front-flip
local FLIP_START = 0.12          -- of the airtime: the flip starts ...
local FLIP_SPAN = 0.62           -- ... and takes this much of it (done well before the landing)
local RING_LEVEL = 3             -- bounces at this level and up throw the dust/sparkle ring
local RING_SPEED = 80            -- other players: impact speed (studs/s) that counts as a big bounce
local PITCH_BASE = 0.95          -- Boing PlaybackSpeed at level 1 ...
local PITCH_STEP = 0.13          -- ... + this per level
local PITCH_HELD = 0.05          -- ... + this while jump is held
--.. the mat spring
local PRESS_TIME = 0.06          -- s to push down to the dip
local SETTLE_DECAY = 0.075       -- s, exponential decay of the rebound
local SETTLE_PERIOD = 0.22       -- s, rebound oscillation period
local SETTLE_TIME = 0.34         -- s after the press the mat is back at rest (e^-4.5 left)
local SPRINGS_FOLLOW = 0.35      -- the Springs ring moves this fraction of the mat's dip
--.. other players' characters
local OTHER_LOOKAHEAD = 0.08     -- s: kick when an incoming root meets the mat within this
local OTHER_MIN_GAP = 0.8        -- studs: always kick inside this band above the mat
local OTHER_MAX_GAP = 4          -- studs: never kick farther above the mat than this
local OTHER_MIN_FALL = 2         -- studs/s down before a root counts as landing
local OTHER_REARM = 0.6          -- s before the same root can kick again (unless it rises first)
local OTHER_SMOOTH = 0.7         -- weight of a new position-rate sample
local OTHER_STALE = 0.15         -- s without movement: the root is standing still

local NO_BOUNCE_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
}

local B = {}
B.Keys = {"Trampoline"}
B.StepRange = 220 -- the local bounce lives in the Step: keep it awake even with the camera zoomed well out

--..Helpers..--
--.. studs from the root's centre down to the feet
local function HipOf(humanoid, root)
	if humanoid.RigType == Enum.HumanoidRigType.R6 then return root.Size.Y * 0.5 + 2 end
	return humanoid.HipHeight + root.Size.Y * 0.5
end

--.. may this humanoid jump at all right now? (carry / collect freezes zero or disable jumping)
local function CanJump(humanoid, root)
	if humanoid.Sit or humanoid.SeatPart or humanoid.PlatformStand or root.Anchored then return false end
	if humanoid.WalkSpeed <= 0 or NO_BOUNCE_STATES[humanoid:GetState()] then return false end
	if not humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then return false end
	local power = humanoid.UseJumpPower and humanoid.JumpPower or humanoid.JumpHeight
	return power > 0
end

local function JumpHeld(humanoid)
	if UserInputService:GetFocusedTextBox() then return false end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then return true end
	if UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA) then return true end
	--.. touch: the on-screen jump button only shows up as Humanoid.Jump
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and humanoid.Jump == true
end

--.. the joint that hangs the body (LowerTorso / R6 Torso) off the HumanoidRootPart, and its frame in the
--.. root's space (Motor6D: C0; AnimationConstraint: Attachment0) - never a carried prop jointed to the root
local BODY_ROOTS = {LowerTorso = true, Torso = true}
local function RootJointOf(character, root)
	for joint in pairs(Kit.Joints(character)) do
		local p0, p1, c0
		if joint:IsA("Motor6D") then
			p0, p1, c0 = joint.Part0, joint.Part1, joint.C0
		elseif joint.Attachment0 and joint.Attachment1 then
			p0, p1, c0 = joint.Attachment0.Parent, joint.Attachment1.Parent, joint.Attachment0.CFrame
		end
		if p0 == root and p1 and BODY_ROOTS[p1.Name] and p1.Parent == character then return joint, c0 end
	end
	return nil
end

local function Same(a, b)
	return (a.Position - b.Position).Magnitude < 1e-3
		and a.RightVector:Dot(b.RightVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
end

local function Emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	for k, v in pairs(props) do
		pcall(function() e[k] = v end)
	end
	e.Parent = parent
	return e
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	local matParts = Kit.Parts(model, "Mat")
	if not hitbox or #matParts == 0 then
		warn("[Trampoline] no Hitbox / Mat* parts on " .. model:GetFullName())
		return
	end
	local player = ctx.Player
	local scale = ctx.Scale
	local springs = Kit.Part(model, "Springs")

	--..Geometry (authored numbers x Scale; a move re-runs the behaviour)..--
	local up = hitbox.CFrame.UpVector
	local centre = Kit.Pivot(model, "MatCentre") or Kit.ToWorld(model, MAT_CENTRE)
	local matR = MAT_RADIUS * scale
	local rimRise = RIM_RISE * scale
	local bottom = (tonumber(model:GetAttribute("State_Bottom")) or DEFAULT_BOTTOM) * scale
	local matMaterial = matParts[1].Material

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = matParts

	--..Mat rig: rest poses relative to the Hitbox..--
	local rig = {}
	for _, part in ipairs(matParts) do
		table.insert(rig, {Part = part, Rel = hitbox.CFrame:ToObjectSpace(part.CFrame), Follow = 1})
	end
	if springs then
		table.insert(rig, {Part = springs, Rel = hitbox.CFrame:ToObjectSpace(springs.CFrame), Follow = SPRINGS_FOLLOW})
	end
	local posed = false
	local function Pose(offset)
		local hcf = hitbox.CFrame
		for _, r in ipairs(rig) do
			if r.Part.Parent then r.Part.CFrame = hcf * CFrame.new(0, offset * r.Follow, 0) * r.Rel end
		end
	end

	--..Effects: a local helper part over the mat carries the sounds and the ring emitters..--
	local fx = ctx:Part({
		Name = "TrampolineFX",
		Size = Vector3.new(matR * 2, 0.2, matR * 2),
		CFrame = CFrame.new(centre + up * (rimRise * 0.6)) * hitbox.CFrame.Rotation,
		Transparency = 1,
	})
	local boings = {}
	for i = 1, 3 do boings[i] = ctx:Sound(fx, FunAssets.Sfx.Boing, {Name = "Boing" .. i, Looped = false}) end
	local nextBoing = 1
	local function Boing(pitch)
		local s = boings[nextBoing]
		nextBoing = nextBoing % #boings + 1
		s.PlaybackSpeed = pitch
		s.TimePosition = 0
		s:Play()
	end
	local whoosh = ctx:Sound(fx, FunAssets.Sfx.Whoosh, {Name = "FlipWhoosh", Looped = false, PlaybackSpeed = 1.1})

	local dust = Emitter(fx, {
		Name = "Dust",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(242, 240, 234)),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1)}),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5 * scale), NumberSequenceKeypoint.new(1, 1.4 * scale)}),
		Lifetime = NumberRange.new(0.45, 0.7),
		Speed = NumberRange.new(4, 7),
		SpreadAngle = Vector2.new(25, 25),
		Drag = 4,
		Acceleration = Vector3.new(0, -2, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		EmissionDirection = Enum.NormalId.Top,
		LightInfluence = 1,
	})
	local sparkle = Emitter(fx, {
		Name = "Sparkle",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 226, 110), Color3.fromRGB(255, 255, 255)),
		LightEmission = 1,
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1)}),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0)}),
		Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(9, 15),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -28, 0),
		Drag = 1.5,
		EmissionDirection = Enum.NormalId.Top,
	})
	--.. a ring off the dish rim (a full disc of puffs where the shape API differs - still reads as dust)
	for _, e in ipairs({dust, sparkle}) do
		pcall(function()
			e.Shape = Enum.ParticleEmitterShape.Disc
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
			e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
			e.ShapePartial = 1
		end)
	end
	local function Ring(big)
		pcall(function()
			dust:Emit(big and 18 or 12)
			sparkle:Emit(big and 20 or 10)
		end)
	end

	--..Mat spring: a kick presses the mat to amp x State_Bottom, then a damped rebound..--
	local kickAt = nil   -- os.clock() of the last kick, nil = at rest
	local kickAmp = 0    -- dip fraction the press goes to (1 = State_Bottom)
	local kickFrom = 0   -- dip fraction when the kick came (a kick mid-rebound presses from there)
	local dipFrac = 0
	local function Kick(amp)
		kickFrom = dipFrac
		kickAmp = math.clamp(amp, 0, 1)
		kickAt = os.clock()
	end
	local function DipAt(t)
		if t < PRESS_TIME then
			return kickFrom + (kickAmp - kickFrom) * math.sin(t / PRESS_TIME * math.pi * 0.5)
		end
		local u = t - PRESS_TIME
		if u >= SETTLE_TIME then return nil end
		return kickAmp * math.exp(-u / SETTLE_DECAY) * math.cos(2 * math.pi * u / SETTLE_PERIOD)
	end
	local function AnimateMat()
		if not kickAt then return end
		local f = DipAt(os.clock() - kickAt)
		if f then
			dipFrac = f
			Pose(f * bottom)
			posed = true
		else
			kickAt, dipFrac = nil, 0
			if posed then Pose(0) posed = false end
		end
	end

	--..Front flip (visual only, local character)..--
	local flip = nil     -- {Joint, C0, Inv, Character, T0, Delay, Dur, Base, Last}
	local flipConn = nil
	local function EndFlip()
		local f = flip
		flip = nil
		if flipConn then flipConn:Disconnect() flipConn = nil end
		if f and f.Base and f.Joint.Parent then
			pcall(function() f.Joint.Transform = f.Base end) -- in case the Animator does not own this joint
		end
	end
	local function FlipStep()
		local f = flip
		if not f then return end
		if not f.Joint.Parent then EndFlip() return end
		local t = os.clock() - f.T0
		if t >= f.Delay + f.Dur then EndFlip() return end
		--.. the Animator rewrites Transform every frame it owns the joint; if it did not, don't compound our own turn
		local cur = f.Joint.Transform
		local base = (f.Last and Same(cur, f.Last)) and f.Base or cur
		f.Base = base
		local u = math.clamp((t - f.Delay) / f.Dur, 0, 1)
		u = u * u * (3 - 2 * u)
		--.. body = root * R * C0 * T * C1^-1 with R about the root centre -> T' = C0^-1 * R * C0 * T; head goes forward (-Z) first
		local out = f.Inv * CFrame.Angles(-2 * math.pi * u, 0, 0) * f.C0 * base
		f.Joint.Transform = out
		f.Last = out
	end
	local function StartFlip(character, root, airTime)
		EndFlip()
		local joint, c0 = RootJointOf(character, root)
		if not joint then return end
		flip = {
			Joint = joint, C0 = c0, Inv = c0:Inverse(), Character = character, T0 = os.clock(),
			Delay = airTime * FLIP_START, Dur = airTime * FLIP_SPAN,
		}
		flipConn = RunService.Stepped:Connect(function()
			local ok = pcall(FlipStep)
			if not ok then EndFlip() end
		end)
		whoosh.TimePosition = 0
		whoosh:Play()
	end
	ctx:OnCleanup(EndFlip)

	--..Local bounce..--
	local level = 0              -- 0 = no chain
	local lastLaunch = -math.huge -- os.clock()
	local airTime = 0            -- expected airtime of the last launch
	local guard = nil            -- {T0, V, Y0, Root}: keep the launch on its trajectory through the Jumping impulse

	local function Bounce(humanoid, root, character, vel)
		local now = os.clock()
		if level > 0 and now - lastLaunch <= airTime + CHAIN_GAP then
			level = math.min(level + 1, #LAUNCH)
		else
			level = 1
		end
		local held = JumpHeld(humanoid)
		local v = LAUNCH[level] + (held and JUMP_BONUS or 0)
		pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
		root.AssemblyLinearVelocity = Vector3.new(vel.X, v, vel.Z)
		guard = {T0 = now, V = v, Y0 = root.Position.Y, Root = root}
		lastLaunch = now
		airTime = 2 * v / math.max(workspace.Gravity, 1)
		Kick(0.55 + 0.15 * level)
		Boing(PITCH_BASE + PITCH_STEP * (level - 1) + (held and PITCH_HELD or 0))
		if level >= RING_LEVEL then Ring(level >= FLIP_LEVEL) end
		if level >= FLIP_LEVEL then StartFlip(character, root, airTime) end
	end

	local function LocalStep(dt)
		local humanoid, root, character = ctx:LocalCharacter()
		if not humanoid then
			level, guard = 0, nil
			if flip then EndFlip() end
			return
		end
		if flip and flip.Character ~= character then EndFlip() end
		local now = os.clock()

		--.. guard the launch against the Jumping state's own impulse, both ways: the target is the vertical speed
		--.. that peaks at the launch apex (Y0 + V^2 / 2g) from where the root is now, so a frame flown too fast
		--.. (impulse added) or too slow (impulse replaced) is paid back and the apex stays LAUNCH[level]^2 / 2g
		if guard then
			local t = now - guard.T0
			local rise = root.Position.Y - guard.Y0
			if t > ENFORCE_TIME or guard.Root ~= root or rise < -GUARD_DROP or rise > guard.V * t + GUARD_EXTRA then
				guard = nil
			else
				local target = math.sqrt(math.max(guard.V * guard.V - 2 * workspace.Gravity * rise, 0))
				local v = root.AssemblyLinearVelocity
				if math.abs(v.Y - target) > GUARD_SLACK then root.AssemblyLinearVelocity = Vector3.new(v.X, target, v.Z) end
			end
		end

		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if flip and grounded and now - flip.T0 > 0.25 then EndFlip() end -- landed early (on anything): stop spinning
		local rel = root.Position - centre
		local h = rel:Dot(up)
		local flat = (rel - up * h).Magnitude
		local inside = flat <= matR
		--.. walked / fell off onto something else (near or far), or the chain window ran out
		local chainOver = now - lastLaunch > airTime + CHAIN_GAP
		if level > 0 and (chainOver or (grounded and not inside and now - lastLaunch > 0.25)) then level = 0 end
		if flat > matR + WAKE_RADIUS or math.abs(h) > 90 then return end

		if not inside or now - lastLaunch < REBOUNCE_COOLDOWN then return end
		if not CanJump(humanoid, root) then return end
		local vel = root.AssemblyLinearVelocity
		if vel.Y > 1 then return end
		local hip = HipOf(humanoid, root)
		local reach = hip + CONTACT_TOLERANCE + math.max(0, -vel.Y) * dt * LOOKAHEAD
		local contact = workspace:Raycast(root.Position, -up * reach, rayParams) ~= nil
		if not contact and humanoid.FloorMaterial == matMaterial then
			contact = h - hip <= rimRise + FLOOR_TOLERANCE
		end
		if contact then Bounce(humanoid, root, character, vel) end
	end

	--..Other players: dip the mat when they come down on it..--
	local seen = setmetatable({}, {__mode = "k"}) -- [root] = {Y, T, VY, Armed, At}
	local function WatchOthers()
		local now = os.clock()
		for _, other in ipairs(Players:GetPlayers()) do
			local character = other ~= player and other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid then
				local rel = root.Position - centre
				local h = rel:Dot(up)
				local s = seen[root]
				if not s then
					s = {Y = h, T = now, VY = 0, Armed = true, At = 0}
					seen[root] = s
				end
				--.. position rate: sample only when the root has moved, over the real time since it last moved
				--.. (ctx:Step can run on RenderStepped AND Heartbeat in one frame; one of them sees no new position)
				if math.abs(h - s.Y) > 1e-4 then
					local span = now - s.T
					if span > 1e-3 then
						local raw = (h - s.Y) / span
						s.VY += (raw - s.VY) * (span > OTHER_STALE and 1 or OTHER_SMOOTH)
					end
					s.Y, s.T = h, now
				elseif now - s.T > OTHER_STALE then
					s.VY = 0
				end
				--.. + the replicated velocity (instant, but may read 0 / stale): whichever says "falling faster" wins,
				--.. and both must agree before a root counts as rising
				local vy = math.min(s.VY, root.AssemblyLinearVelocity:Dot(up))
				local flat = (rel - up * h).Magnitude
				if flat <= matR then
					local gap = h - HipOf(humanoid, root) - rimRise * (flat / matR) ^ 2
					if not s.Armed and (vy > 4 or gap > OTHER_MAX_GAP + 1 or now - s.At > OTHER_REARM) then s.Armed = true end
					local band = math.clamp(-vy * OTHER_LOOKAHEAD, OTHER_MIN_GAP, OTHER_MAX_GAP)
					if s.Armed and vy < -OTHER_MIN_FALL and gap <= band and gap > -1.5 then
						s.Armed, s.At = false, now
						--.. the kick comes up to 4 studs early: extrapolate the fall to the mat for the impact speed
						local speed = math.sqrt(vy * vy + 2 * workspace.Gravity * math.max(gap, 0))
						Kick(0.55 + speed / 200)
						Boing(PITCH_BASE + PITCH_STEP * 3 * math.clamp((speed - 20) / 90, 0, 1))
						if speed >= RING_SPEED then Ring(speed >= LAUNCH[#LAUNCH] - 10) end
					end
				elseif not s.Armed and now - s.At > OTHER_REARM then
					s.Armed = true
				end
			end
		end
	end

	--..Frame loop (one Step for the build)..--
	ctx:Step(function(dt)
		LocalStep(dt)
		WatchOthers()
		AnimateMat()
	end)

	return function()
		EndFlip()
		guard = nil
		if posed and hitbox.Parent then Pose(0) end
		posed = false
	end
end

return B
