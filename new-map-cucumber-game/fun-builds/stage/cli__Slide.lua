--[[
	Slide  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the SLIDE functional build (fun-builds/CONTRACT.md; user: "make all the fun stuff
	functional"). Server half: ServerStorage.FunBehaviours.Slide (ladder truss, "Slide!" prompt, whee relay).
	Everything here moves only the LOCAL character (network-owned by this client).

	GEOMETRY (authored Roblox frame, scale 1, front = -Z; props-dump/Slide.txt @Notes, Blender (x, y, z) ->
	Roblox (x, z, -y)): the chute's riding surface is the parabola
	    Y(t) = 0.40 + 4.00 (1 - t)^2,  Z(t) = 2.45 - 7.85 t      t 0 = the mouth at the deck, 1 = the exit
	(45 deg at the mouth, flat at the run-out; 13.6 studs long at x1.5), channel inner half width 1.12.
	The curve gives the direction and the speed; the real surface under the rider (a ray onto the Chute
	part's collision geometry, whatever its CollisionFidelity) gives the height.

	RIDE. Every frame near the build (one ctx:Step): when the local root is over the channel on the sloped
	part (t 0.02 .. 0.8), between 0.3 studs and its own standing root height + START_HEIGHT_SLACK above the
	riding surface (4.6 on a default avatar; physique bodies stand taller - a Champion's root is ~5.7 over
	its feet - so a fixed ceiling would never let them walk or fall into a ride), not jumping up, and a ray
	down hits the Chute part, the ride starts: Humanoid.Sit = true (the sit pose; if the humanoid never
	reaches Seated within SIT_GRACE, or drops out of it without jumping, it is held with PlatformStand
	instead and a jump press ends the ride), the whee plays and the server relays it to everyone. Each frame
	(bound just before the camera, Heartbeat as a fallback while rendering is paused) the speed grows with
	the slope (G_EFF x sin(slope) - FRICTION, MIN_SPEED .. MAX_SPEED ~45 studs/s), t advances by
	speed / |dP/dt|, the root is placed on the curve (lateral offset eased to the centre line), glued to the
	real surface + a sitting lift (SIT_LIFT_K x the root's height + SIT_LIFT_EXTRA: ~1.8 on a default R15,
	matching the measured ~1.7 of a seated root over a seat's top face; it scales with the body, not the
	legs, because a seated rider's legs are folded forward), leaned TILT of the way into the slope and given
	the matching velocity. The first moment blends from where the character really was. At t = 1 it
	stands them up (Sit off, Freefall) upright at the exit with a small forward + up pop over the bumper.
	Jumping (the seat's own jump-out) ends the ride where they are; so does death / the build going away.
	The "Slide!" prompt on the deck (server) starts the same ride from the mouth (t = 0).

	LADDER. The server's two invisible TrussParts make the ladder climbable between its rails, but the grab
	hoop over the back of the deck is only 2.2 studs high at x1.5, so a climber cannot step through it: while
	the local humanoid is Climbing up in the band behind the ladder and its root reaches the deck height -
	MANTLE_BELOW, it is lifted along a short arc over the hoop onto the middle of the deck (MANTLE_TIME),
	facing the chute. The trigger is on the ROOT on purpose: what the hoop blocks is the head, which sits
	~2.3 over the root on every physique, so a tall body (whose root is already near deck height from the
	ground) is mantled as soon as it starts to climb - a step up, not a climb, for an 8-stud Champion.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

--..Geometry (authored frame, scale 1)..--
local CH_Z0, CH_Z1 = 2.45, -5.40   -- chute mouth / exit
local CH_Y0, CH_Y1 = 4.40, 0.40    -- riding surface at the mouth / exit
local CH_HALF = 1.12               -- channel inner half width
local DECK_Y = 4.40                -- deck walking surface
local DECK_Z0, DECK_Z1 = 2.45, 4.18
local LADDER_Z0, LADDER_Z1 = 4.0, 6.8 -- the band behind the ladder a climber's root is in
local LADDER_HALF = 1.8            -- |X| of that band
local FOOTPRINT_HALF = 2.6         -- |X| quick reject
local FOOTPRINT_Z0, FOOTPRINT_Z1 = CH_Z1 - 0.6, 7.6

--..Config..--
local START_T_MIN, START_T_MAX = 0.02, 0.8   -- a ride starts on the sloped part only
local START_HEIGHT_MIN = 0.3       -- studs the root is at least above the riding surface ...
local START_HEIGHT_SLACK = 1.6     -- ... and at most its standing root height (StandLift) + this (4.6 on a default avatar)
local START_RISE_MAX = 10          -- studs/s: a character jumping up past the chute does not start
local LATERAL_SLACK = 0.25         -- authored studs past the channel wall still counted
local G_EFF = 150                  -- studs/s^2 x sin(slope): gravity along the chute (196.2 would be ~48 at the exit)
local FRICTION = 6                 -- studs/s^2
local MIN_SPEED, MAX_SPEED = 12, 45
local TILT = 0.7                   -- 0 = rider upright, 1 = square to the chute surface
local SIT_LIFT_K = 0.85            -- R15 sitting lift = the root's height x this + SIT_LIFT_EXTRA (1.8 on a 2-stud root);
local SIT_LIFT_EXTRA = 0.1         -- studs. No HipHeight term: the legs are folded forward, the torso holds the root up
local LATERAL_MAX = 0.35           -- authored: the rider starts at most this far off the centre line ...
local LATERAL_EASE = 5             -- ... and eases onto it (1/s)
local GLUE_ABOVE, GLUE_BELOW = 1.3, 0.6 -- authored: a surface hit this far above / below the curve is trusted
local GLUE_EASE = 15               -- 1/s: the glue offset follows the hits this fast
local BLEND_WALK, BLEND_PROMPT = 0.12, 0.25 -- s: blend from where the character was onto the chute
local SIT_GRACE = 0.2              -- s to reach the Seated state before falling back to PlatformStand
local EXIT_FORWARD_MIN, EXIT_FORWARD_MAX = 12, 24 -- studs/s forward pop at the exit (0.55 x ride speed)
local EXIT_UP = 20                 -- studs/s up at the exit (hops the 0.6 stud bumper)
local COOLDOWN = 0.8               -- s after a ride before another can start
local MAX_RIDE = 4                 -- s safety cap
local MANTLE_BELOW = 0.6           -- studs: the climber's root this far under the deck surface triggers the mantle
local MANTLE_RISE_MIN = 0.5        -- studs/s up: only a climber going UP is mantled
local MANTLE_TIME = 0.28           -- s
local MANTLE_ARC = 1.2             -- authored studs of extra height mid-arc (over the hoop)
local WHEE_VOLUME = 0.8
local RIDE_BIND, MANTLE_BIND = "FunSlideRide", "FunSlideMantle"
local STATUS_ATTR, LAST_ATTR = "FunSlide", "FunSlideLast" -- LOCAL player attributes (not replicated) for playtests:
-- "ride" / "mantle" / nil now, and a summary of the last one ("exit v=42.6 t=1.00 0.46s sit lift=1.80")

--..Variables (one local character: shared by every slide)..--
local player = Players.LocalPlayer
local Ride = nil        -- the ride in progress
local Mantle = nil      -- the ladder mantle in progress
local CooldownUntil = 0

local B = {}
B.StepRange = 250 -- detection is a footprint test first; zoomed-out players on the slide still ride

--..Curve (authored)..--
local function CurvePoint(t, x)
	local u = 1 - t
	return Vector3.new(x, CH_Y1 + (CH_Y0 - CH_Y1) * u * u, CH_Z0 + (CH_Z1 - CH_Z0) * t)
end

--.. d(point)/dt: its direction is downhill, its length the authored studs per unit t
local function CurveVelocity(t)
	return Vector3.new(0, -2 * (CH_Y0 - CH_Y1) * (1 - t), CH_Z1 - CH_Z0)
end

local function TOfZ(z)
	return (z - CH_Z0) / (CH_Z1 - CH_Z0)
end

--..Character helpers..--
local function StandLift(humanoid, root)
	if humanoid.RigType == Enum.HumanoidRigType.R6 then return 3 end
	return humanoid.HipHeight + root.Size.Y * 0.5
end

--.. the seated root's height over the chute floor: CONTRACT.md measured a sitting root ~1.7 over a seat's top face
--.. (1.9 over the centre of a 0.4-thick seat). It follows the torso / root, which physique bodies scale by
--.. BodyHeightScale, not HipHeight (leg length: 4.17 on a Champion, and the legs are folded forward)
local function SitLift(humanoid, root)
	if humanoid.RigType == Enum.HumanoidRigType.R6 then return 2.2 end
	return root.Size.Y * SIT_LIFT_K + SIT_LIFT_EXTRA
end

local BLOCKING_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Swimming] = true,
}

--.. may the local character start a ride now?
local function Free(humanoid, root, allowClimbing)
	if Ride or Mantle or os.clock() < CooldownUntil then return false end
	if root.Anchored or humanoid.SeatPart or humanoid.Sit or humanoid.PlatformStand then return false end
	local state = humanoid:GetState()
	if BLOCKING_STATES[state] then return false end
	if state == Enum.HumanoidStateType.Climbing and not allowClimbing then return false end
	local camera = workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Scriptable then return false end -- lift / cutscene / hatch
	return true
end

local function PlayWhee(parent)
	local ok, sound = pcall(Kit.MakeSound, FunAssets.Sfx.Whee, {Name = "SlideWhee", Volume = WHEE_VOLUME})
	if not ok or not sound then return end
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 6)
end

--..Ride..--
--.. the real riding surface under a curve point: studs along up from the curve (0 when nothing trusted is hit)
local function GlueOffset(data, surfW)
	if not data.rayParams then return 0 end
	local s = data.scale
	local from = surfW + data.upW * (GLUE_ABOVE * s + 0.5)
	local hit = workspace:Raycast(from, -data.upW * ((GLUE_ABOVE + GLUE_BELOW) * s + 0.5), data.rayParams)
	if not hit then return 0 end
	local dy = (hit.Position - surfW):Dot(data.upW)
	if dy > -GLUE_BELOW * s and dy < GLUE_ABOVE * s then return dy end
	return 0
end

--.. where the rider's root goes for the ride's current t / x / glue: position, look, up, downhill tangent (world)
local function Pose(r)
	local data = r.data
	local origin, upW = data.origin, data.upW
	local tanA = CurveVelocity(r.t).Unit
	local tanW = origin:VectorToWorldSpace(tanA)
	local normalW = origin:VectorToWorldSpace(Vector3.new(0, -tanA.Z, tanA.Y)) -- square to the surface, pointing up
	local sitUp = (upW * (1 - TILT) + normalW * TILT).Unit
	local look = (tanW - sitUp * tanW:Dot(sitUp)).Unit
	local surfW = origin:PointToWorldSpace(CurvePoint(r.t, r.x) * data.scale)
	return surfW + upW * r.glue + sitUp * r.lift, look, sitUp, tanW, surfW
end

local function Unbind(name)
	pcall(RunService.UnbindFromRenderStep, RunService, name)
end

local function EndRide(finished)
	local r = Ride
	if not r then return end
	Ride = nil
	CooldownUntil = os.clock() + COOLDOWN
	Unbind(RIDE_BIND)
	if r.heartbeat then r.heartbeat:Disconnect() end
	player:SetAttribute(STATUS_ATTR, nil)
	player:SetAttribute(LAST_ATTR, string.format("%s v=%.1f t=%.2f %.2fs %s lift=%.2f", finished and "exit" or "bail", r.v, r.t, r.age, r.mode, r.lift))
	local humanoid, root = r.humanoid, r.root
	if r.mode == "stand" and humanoid.Parent then humanoid.PlatformStand = false end
	if not (humanoid.Parent and root.Parent and humanoid.Health > 0) then return end
	local upW = r.data.upW
	if finished then
		--.. the exit: stand up, upright, facing out, a small hop forward over the bumper
		if humanoid.Sit and not humanoid.SeatPart then humanoid.Sit = false end
		local forward = r.data.forwardW
		local exitW = r.data.origin:PointToWorldSpace(CurvePoint(1, 0) * r.data.scale)
		local pos = exitW + upW * (math.max(r.glue, 0) + StandLift(humanoid, root) + 0.15)
		root.CFrame = CFrame.lookAt(pos, pos + forward, upW)
		root.AssemblyLinearVelocity = forward * math.clamp(r.v * 0.55, EXIT_FORWARD_MIN, EXIT_FORWARD_MAX) + upW * EXIT_UP
		root.AssemblyAngularVelocity = Vector3.zero
		pcall(humanoid.ChangeState, humanoid, Enum.HumanoidStateType.Freefall)
	else
		--.. bailed out (jumped / the build went away): stand upright where they are, momentum kept
		if r.mode == "sit" and humanoid.Sit and not humanoid.SeatPart then humanoid.Sit = false end
		local look = root.CFrame.LookVector
		local flat = look - upW * look:Dot(upW)
		if flat.Magnitude > 1e-3 then
			local p = root.Position
			root.CFrame = CFrame.lookAt(p, p + flat.Unit, upW)
		end
	end
end

local function RideTick()
	local r = Ride
	if not r then return end
	local now = os.clock()
	local dt = math.min(now - r.clock, 0.05)
	if dt <= 0 then return end
	r.clock = now
	local humanoid, root, data = r.humanoid, r.root, r.data
	if not (r.ctx:Alive() and humanoid.Parent and root.Parent and humanoid.Health > 0) or root.Anchored then
		EndRide(false)
		return
	end
	r.age += dt
	if r.age > MAX_RIDE then EndRide(false) return end

	--.. the pose: seated (jump gets them out), or PlatformStand when the sit will not hold
	if r.mode == "sit" then
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Seated then r.sat = true end
		if not humanoid.Sit then
			if humanoid.Jump or state == Enum.HumanoidStateType.Jumping then EndRide(false) return end -- jumped out
			if r.sat or r.age > SIT_GRACE then
				--.. dropped out of the sit on its own, or never reached Seated (state disabled): hold them rigid instead
				r.mode = "stand"
				humanoid.PlatformStand = true
			else
				humanoid.Sit = true
			end
		end
	else
		if humanoid.Jump then EndRide(false) return end
		humanoid.PlatformStand = true
	end

	--.. speed: gravity along the slope, capped; t advances by distance / (studs per unit t)
	local vel = CurveVelocity(r.t)
	r.v = math.clamp(r.v + (G_EFF * -vel.Unit.Y - FRICTION) * dt, MIN_SPEED, MAX_SPEED)
	r.t += r.v * dt / (vel.Magnitude * data.scale)
	if r.t >= 1 then EndRide(true) return end
	r.x *= 1 - math.min(1, dt * LATERAL_EASE)

	--.. place the root: on the curve, glued to the real surface, leaned into the slope
	local surfW = data.origin:PointToWorldSpace(CurvePoint(r.t, r.x) * data.scale)
	r.glue += (GlueOffset(data, surfW) - r.glue) * math.min(1, dt * GLUE_EASE)
	local pos, look, up, tanW = Pose(r)
	if r.age < r.blend then
		local k = r.age / r.blend
		pos += r.offset * (1 - k * k * (3 - 2 * k))
	end
	root.CFrame = CFrame.lookAt(pos, pos + look, up)
	root.AssemblyLinearVelocity = tanW * r.v
	root.AssemblyAngularVelocity = Vector3.zero
end

local function StartRide(ctx, data, humanoid, root, t, x, v, blend)
	local r = {
		ctx = ctx, data = data, humanoid = humanoid, root = root,
		t = math.clamp(t, 0, 0.95), x = x, v = math.clamp(v, MIN_SPEED, MAX_SPEED),
		age = 0, clock = os.clock(), blend = blend, lift = SitLift(humanoid, root), glue = 0,
		mode = "sit", sat = false,
	}
	r.glue = GlueOffset(data, data.origin:PointToWorldSpace(CurvePoint(r.t, r.x) * data.scale))
	local pos = Pose(r)
	r.offset = root.Position - pos
	if r.offset.Magnitude > 16 then r.offset = Vector3.zero end -- a teleport-length jump: just snap
	Ride = r
	player:SetAttribute(STATUS_ATTR, "ride")
	humanoid.Sit = true
	PlayWhee(root)
	ctx:Send("Ride", true)
	--.. just before the camera, so the camera follows this frame's pose; Heartbeat drives it while rendering is paused
	Unbind(RIDE_BIND)
	RunService:BindToRenderStep(RIDE_BIND, Enum.RenderPriority.Camera.Value - 1, RideTick)
	r.heartbeat = RunService.Heartbeat:Connect(function()
		if Ride == r and os.clock() - r.clock > 0.06 then RideTick() end
	end)
end

--..Ladder mantle..--
local function EndMantle()
	local m = Mantle
	if not m then return end
	Mantle = nil
	Unbind(MANTLE_BIND)
	if m.heartbeat then m.heartbeat:Disconnect() end
	CooldownUntil = math.max(CooldownUntil, os.clock() + 0.3)
	player:SetAttribute(STATUS_ATTR, nil)
	player:SetAttribute(LAST_ATTR, string.format("mantle %.2fs", m.age))
	local humanoid = m.humanoid
	if humanoid.Parent and humanoid.Health > 0 then
		pcall(humanoid.ChangeState, humanoid, Enum.HumanoidStateType.Freefall)
	end
end

local function MantleTick()
	local m = Mantle
	if not m then return end
	local now = os.clock()
	local dt = math.min(now - m.clock, 0.05)
	m.clock = now
	local humanoid, root, data = m.humanoid, m.root, m.data
	if not (m.ctx:Alive() and humanoid.Parent and root.Parent and humanoid.Health > 0) or root.Anchored then
		EndMantle()
		return
	end
	m.age += dt
	local k = math.min(m.age / MANTLE_TIME, 1)
	local e = k * k * (3 - 2 * k)
	local pos = m.from:Lerp(m.to, e) + data.upW * (math.sin(math.pi * k) * MANTLE_ARC * data.scale)
	root.CFrame = CFrame.lookAt(pos, pos + data.forwardW, data.upW)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if k >= 1 then EndMantle() end
end

local function StartMantle(ctx, data, humanoid, root)
	local deckMid = (DECK_Z0 + DECK_Z1) * 0.5
	local to = data.origin:PointToWorldSpace(Vector3.new(0, DECK_Y, deckMid) * data.scale)
		+ data.upW * (StandLift(humanoid, root) + 0.1)
	local m = {ctx = ctx, data = data, humanoid = humanoid, root = root, from = root.Position, to = to, age = 0, clock = os.clock()}
	Mantle = m
	player:SetAttribute(STATUS_ATTR, "mantle")
	Unbind(MANTLE_BIND)
	RunService:BindToRenderStep(MANTLE_BIND, Enum.RenderPriority.Camera.Value - 1, MantleTick)
	m.heartbeat = RunService.Heartbeat:Connect(function()
		if Mantle == m and os.clock() - m.clock > 0.06 then MantleTick() end
	end)
end

--..Behaviour..--
function B.Client(model, ctx)
	local chute = Kit.Part(model, "Chute")
	local origin = Kit.Origin(model) -- a move re-runs the behaviour, so this stays true for this run
	local data = {
		origin = origin, scale = ctx.Scale, upW = origin.UpVector, forwardW = origin.LookVector, rayParams = nil,
	}
	if chute then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {chute}
		data.rayParams = params
	end
	local s = data.scale

	--.. the prompt on the deck ("Start" from the server): the ride from the mouth
	ctx.SlideStart = function()
		local humanoid, root = ctx:LocalCharacter()
		if not humanoid or not Free(humanoid, root, true) then return end
		StartRide(ctx, data, humanoid, root, 0, 0, MIN_SPEED, BLEND_PROMPT)
	end

	--.. walking / falling onto the chute starts a ride; climbing near the top of the ladder mantles onto the deck
	ctx:Step(function()
		if Ride or Mantle then return end
		local humanoid, root = ctx:LocalCharacter()
		if not humanoid then return end
		local rel = data.origin:PointToObjectSpace(root.Position)
		local p = rel / s
		if math.abs(p.X) > FOOTPRINT_HALF or p.Z < FOOTPRINT_Z0 or p.Z > FOOTPRINT_Z1 or p.Y > DECK_Y + 6 then return end
		local rise = root.AssemblyLinearVelocity:Dot(data.upW)
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Climbing then
			if os.clock() >= CooldownUntil and math.abs(p.X) < LADDER_HALF and p.Z > LADDER_Z0 and p.Z < LADDER_Z1
				and rel.Y >= DECK_Y * s - MANTLE_BELOW and rise > MANTLE_RISE_MIN and not root.Anchored then
				StartMantle(ctx, data, humanoid, root)
			end
			return
		end
		if math.abs(p.X) > CH_HALF + LATERAL_SLACK then return end
		local t = TOfZ(p.Z)
		if t < START_T_MIN or t > START_T_MAX then return end
		local height = rel.Y - CurvePoint(t, 0).Y * s
		local standH = StandLift(humanoid, root) -- a physique body stands (and lands) with its root this high
		if height < START_HEIGHT_MIN or height > standH + START_HEIGHT_SLACK or rise > START_RISE_MAX then return end
		if not Free(humanoid, root, false) then return end
		if data.rayParams and not workspace:Raycast(root.Position, -data.upW * (height + 1.5), data.rayParams) then return end
		local tanW = data.origin:VectorToWorldSpace(CurveVelocity(t).Unit)
		local x = math.clamp(p.X, -LATERAL_MAX, LATERAL_MAX)
		StartRide(ctx, data, humanoid, root, t, x, root.AssemblyLinearVelocity:Dot(tanW), BLEND_WALK)
	end)

	return function()
		ctx.SlideStart = nil
		if Ride and Ride.ctx == ctx then EndRide(false) end
		if Mantle and Mantle.ctx == ctx then EndMantle() end
	end
end

function B.OnEvent(_model, action, payload, ctx)
	if action == "Start" then
		if ctx.SlideStart then ctx.SlideStart() end
	elseif action == "Whee" then
		if payload == player.UserId then return end -- the rider already played it
		local other = Players:GetPlayerByUserId(tonumber(payload) or 0)
		local root = other and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if root then PlayWhee(root) end
	end
end

return B
