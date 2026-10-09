--[[
	Seesaw  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the functional SEESAW (server half: ServerStorage.FunBehaviours.Seesaw; notes/Seesaw.md).
	Every Plank* part (PlankBeamRed, PlankBeamBlue, PlankSeats, PlankHandles, PlankPivotStrap) swings as one
	rigid plank about Pivot_PlankPivot, about the build's authored Z axis. Angles are the build's State_*
	numbers: RedDown = +12 (red +X end on its tyre-stop - the pose the model ships in), Level = 0,
	BlueDown = -12; a positive angle is CFrame.Angles(0, 0, -angle). The rig is taken relative to the LEVEL
	pose (the shipped parts un-rotated by State_RedDown) and everything is posed relative to the Hitbox every
	frame, so a moved build lands cleanly.
	  * nobody on      -> the plank drifts gently back to rest (RedDown) and settles on the red stop
	  * one rider      -> their weight swings their end down onto its tyre-stop (a little bounce)
	  * both riders    -> a see-saw ride between the two down poses, PERIOD 2.2 s: push off, swing across, land
	                      with a bump and a tiny rebound, rest DWELL, push off again. It is a pure function of
	                      Kit.Now() - Fun_Since (starting from the Fun_Lead end), so every client rides in step
	  * sounds: FunAssets.Sfx.Creak as an end pushes off (every reversal), a soft thump (Sfx.Thump, else
	    Sfx.CanDrop) as an end touches down, louder the faster it lands
	  * the two runtime seats (tag FunSeesawSeat, SeesawId = Fun_Id) are carried with the plank locally at the
	    same rotation (seat offset from the server's SeesawOffset, in the level frame), so the welded riders
	    ride along - on every client, since each one moves its own copy
	Cleanup puts every Plank* part back where it was (relative to the Hitbox) and the seats where the server
	put them (the shipped pose).
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))
local FunAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunAssets"))

--..Config..--
local SEAT_TAG = "FunSeesawSeat"          -- must match the server half
local PIVOT_NAME = "PlankPivot"
local PLANK_PREFIX = "Plank"
local DEFAULT_PIVOT = Vector3.new(0, 1.35, 0) -- authored fallback for Pivot_PlankPivot
local DEFAULT_RED_DOWN, DEFAULT_BLUE_DOWN = 12, -12

--.. the ride (both seats taken)
local PERIOD = 2.2            -- s: red down -> blue down -> red down
local DWELL = 0.2             -- s an end rests on its stop between landing and pushing off
local ARRIVE = 0.8            -- 1 = the swing arrives at rest; < 1 = still moving when it lands (the bump)
local REBOUND = 0.05          -- share of the swing the plank kicks back after landing (~0.7 deg)
local START_DELAY = 0.35      -- s after the second rider sits before the first push-off
local BLEND_IN = 0.4          -- s to blend from wherever the plank was into the ride

--.. one rider / nobody: a weight pulling the goal end down onto its stop
local RIDER_ACCEL = 110       -- deg/s^2 (terminal speed = accel / damp)
local RIDER_DAMP = 3.5        -- 1/s
local REST_ACCEL = 30         -- empty: a slow settle back to RedDown
local REST_DAMP = 2.5
--.. (the server half's RIDER_HALF / REST_HALF = when these swings pass level: 0.64 s / 1.4 s - keep in step)
local RESTITUTION = 0.22      -- bounce off a tyre-stop
local SETTLE_SPEED = 2        -- deg/s: slower than this against the goal stop = settled

--.. sounds
local END_ZONE = 1            -- deg from an end that counts as "down" (holds the landing rebound)
local THUMP_MIN_SPEED = 6     -- deg/s: slower landings are silent
local THUMP_FULL_SPEED = 30   -- deg/s: full thump volume
local THUMP_VOLUME = 0.3
local CREAK_VOLUME = 0.4
local CREAK_REST_SCALE = 0.6  -- quieter creak when nobody rides
local CREAK_MIN_GAP = 0.45    -- s

local MAX_DT = 1 / 15
local WAKE_GAP = 0.5          -- s without a Step (camera was far) -> snap to where the plank should be

local B = {}
B.StepRange = 180

--..Helpers..--
local function Smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

--.. the plank swung to `deg` about the pivot (positive drops the red +X end) - same as the server half
local function Swing(deg)
	return CFrame.Angles(0, 0, -math.rad(deg))
end

--.. 0..1 travel -> 0..1 of the swing: eased out of the push-off, still moving when it lands
local SHAPE_NORM = 1 - math.cos(math.pi * ARRIVE)
local function Shape(u)
	return (1 - math.cos(math.pi * ARRIVE * u)) / SHAPE_NORM
end

--.. the ride angle t seconds after the first push-off, between the lead end's angle and the other end's
local function RideAngle(t, from, to)
	if t <= 0 then return from end
	local half = PERIOD * 0.5
	local travel = half - DWELL
	local k = math.floor(t / half)
	local tau = t - k * half
	local a, b = from, to
	if k % 2 == 1 then a, b = to, from end
	if tau < travel then
		return a + (b - a) * Shape(tau / travel)
	end
	--.. resting on b's stop: a small kick back toward level right after the landing, settled by push-off
	local d = (tau - travel) / DWELL
	return b - (b - a) * REBOUND * math.sin(math.pi * d) * (1 - d)
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	local parts = Kit.Parts(model, PLANK_PREFIX)
	if not hitbox or #parts == 0 then return end

	--..Angles (the build's State_* numbers)..--
	local redDown = tonumber(model:GetAttribute("State_RedDown")) or DEFAULT_RED_DOWN
	local blueDown = tonumber(model:GetAttribute("State_BlueDown")) or DEFAULT_BLUE_DOWN
	if math.abs(redDown - blueDown) < 1 then redDown, blueDown = DEFAULT_RED_DOWN, DEFAULT_BLUE_DOWN end
	local ship = redDown -- the model ships RedDown, which is also the empty seesaw's rest
	local lo, hi = math.min(redDown, blueDown), math.max(redDown, blueDown)
	local function EndAngle(side) -- side +1 = red end down, -1 = blue end down
		return side == -1 and blueDown or redDown
	end
	local function ZoneOf(a) -- which end is down at angle a (+1 red / -1 blue / 0 = both in the air)
		if math.abs(a - redDown) <= END_ZONE then return 1 end
		if math.abs(a - blueDown) <= END_ZONE then return -1 end
		return 0
	end

	--..The pivot frame, kept relative to the Hitbox..--
	local pivotPos = Kit.Pivot(model, PIVOT_NAME) or Kit.ToWorld(model, DEFAULT_PIVOT)
	local pivot0 = CFrame.new(pivotPos) * Kit.Origin(model).Rotation
	local pivotRel = hitbox.CFrame:ToObjectSpace(pivot0)

	--..The plank rig: relative to the LEVEL pose (the shipped parts un-rotated by State_RedDown)..--
	local rig = Kit.Rig(parts, pivot0 * Swing(ship))
	local home = {} -- [part] = CFrame relative to the Hitbox, restored on cleanup
	for _, p in ipairs(parts) do home[p] = hitbox.CFrame:ToObjectSpace(p.CFrame) end

	--..Sounds..--
	local strap = Kit.Part(model, "PlankPivotStrap") or parts[1]
	local thumpId = FunAssets.Sfx.Thump or FunAssets.Sfx.CanDrop
	local creak = ctx:Sound(strap, FunAssets.Sfx.Creak, {Volume = CREAK_VOLUME})
	local thumps = {
		[1] = ctx:Sound(Kit.Part(model, "PlankBeamRed") or strap, thumpId, {Volume = THUMP_VOLUME}),
		[-1] = ctx:Sound(Kit.Part(model, "PlankBeamBlue") or strap, thumpId, {Volume = THUMP_VOLUME}),
	}
	local rng = Random.new()
	local lastCreak = 0
	local function Creak(scale)
		local t = os.clock()
		if t - lastCreak < CREAK_MIN_GAP then return end
		lastCreak = t
		creak.Volume = CREAK_VOLUME * scale
		creak.PlaybackSpeed = rng:NextNumber(0.72, 0.9)
		creak:Play()
	end
	local function Thump(side, speed)
		if speed < THUMP_MIN_SPEED then return end
		local s = thumps[side]
		if not s then return end
		s.Volume = THUMP_VOLUME * math.clamp(speed / THUMP_FULL_SPEED, 0.2, 1)
		s.PlaybackSpeed = rng:NextNumber(0.95, 1.1)
		s:Play()
	end

	--..The runtime seats (stream on their own; the server remakes them when the build moves)..--
	local seats = {} -- [side] = {Seat = Seat, Rel = CFrame in the level frame}
	local seatsDirty = true
	local function Consider(inst)
		if not inst:IsA("BasePart") then return end
		local id = ctx:State("Id")
		if id == nil or inst:GetAttribute("SeesawId") ~= id then return end
		local side = inst:GetAttribute("SeesawSide")
		local offset = inst:GetAttribute("SeesawOffset")
		if (side ~= 1 and side ~= -1) or typeof(offset) ~= "Vector3" then return end
		local old = seats[side]
		if old and old.Seat == inst then return end
		seats[side] = {Seat = inst, Rel = CFrame.lookAt(offset, offset + Vector3.new(-side, 0, 0))}
		seatsDirty = true
	end
	ctx:Connect(CollectionService:GetInstanceAddedSignal(SEAT_TAG), function(inst)
		if inst:GetAttribute("SeesawOffset") == nil then
			--.. the attributes can land a moment after the tag: look again when they do
			ctx:Connect(inst.AttributeChanged, function() Consider(inst) end)
		end
		Consider(inst)
	end)
	ctx:OnState("Id", function()
		seats = {}
		for _, inst in ipairs(CollectionService:GetTagged(SEAT_TAG)) do Consider(inst) end
	end)

	--..Mode from the server state..--
	--.. "Ride" (side = the lead end, since), "Hold" (one rider: side = their end), "Rest" (nobody: red down)
	local function ReadMode()
		local red = ctx:State("RiderRed") or 0
		local blue = ctx:State("RiderBlue") or 0
		if red ~= 0 and blue ~= 0 then
			local lead = ctx:State("Lead") == -1 and -1 or 1
			local since = tonumber(ctx:State("Since")) or 0
			if since > 0 then return "Ride", lead, since end
			return "Hold", lead, 0
		elseif red ~= 0 then
			return "Hold", 1, 0
		elseif blue ~= 0 then
			return "Hold", -1, 0
		end
		return "Rest", 1, 0
	end
	local function Steady(mode, side, since, now)
		if mode == "Ride" then return RideAngle(now - since - START_DELAY, EndAngle(side), EndAngle(-side)) end
		return EndAngle(side)
	end

	--..Every frame..--
	local angle, vel = ship, 0
	local zone = ZoneOf(angle)
	local lastMode
	local lastClock = -math.huge
	local blendFrom, blendAt = angle, -math.huge
	local written, writtenAt -- last posed angle / hitbox CFrame
	ctx:Step(function(dt, now)
		if not hitbox.Parent then return end
		local clock = os.clock()
		local mode, side, since = ReadMode()
		local woke = clock - lastClock > WAKE_GAP
		lastClock = clock
		dt = math.clamp(dt, 0, MAX_DT)
		local prev = angle
		local hitSpeed

		if woke then
			--.. first frame, or the camera was away: be where every other client is
			angle, vel = Steady(mode, side, since, now), 0
			blendAt = -math.huge
		elseif mode == "Ride" then
			if lastMode ~= "Ride" then blendFrom, blendAt = angle, clock end
			local target = Steady(mode, side, since, now)
			angle = blendFrom + (target - blendFrom) * Smooth((clock - blendAt) / BLEND_IN)
			vel = dt > 0 and (angle - prev) / dt or 0
		else
			--.. a weight on the goal end pulls it down onto its tyre-stop, which bounces it a little
			local goal = EndAngle(side)
			local accel, damp = RIDER_ACCEL, RIDER_DAMP
			if mode == "Rest" then accel, damp = REST_ACCEL, REST_DAMP end
			if angle ~= goal or vel ~= 0 then
				local dir = goal >= angle and 1 or -1
				vel += (dir * accel - damp * vel) * dt
				angle += vel * dt
				if angle > hi then
					angle = hi
					if vel > 0 then hitSpeed = vel vel = -vel * RESTITUTION end
				elseif angle < lo then
					angle = lo
					if vel < 0 then hitSpeed = -vel vel = -vel * RESTITUTION end
				end
				if math.abs(angle - goal) < 0.05 and math.abs(vel) < SETTLE_SPEED then
					angle, vel = goal, 0
				end
			end
		end
		lastMode = mode

		--..Landing thump / push-off creak..--
		local newZone = ZoneOf(angle)
		if woke then
			zone = newZone
		elseif newZone ~= zone then
			if newZone ~= 0 then
				Thump(newZone, hitSpeed or math.abs(vel))
			elseif zone ~= 0 then
				Creak(mode == "Rest" and CREAK_REST_SCALE or 1)
			end
			zone = newZone
		end

		--..Pose the plank and carry the seats (only when something changed)..--
		local hb = hitbox.CFrame
		if woke or seatsDirty or written == nil or math.abs(angle - written) > 1e-4 or hb ~= writtenAt then
			local pose = hb * pivotRel * Swing(angle)
			Kit.PoseRig(rig, pose)
			for _, s in pairs(seats) do
				if s.Seat.Parent then s.Seat.CFrame = pose * s.Rel end
			end
			written, writtenAt, seatsDirty = angle, hb, false
		end
	end)

	--..Cleanup: the plank back as shipped (relative to where the build IS now), the seats where the server put them..--
	return function()
		if not hitbox.Parent then return end
		for part, rel in pairs(home) do
			if part.Parent then part.CFrame = hitbox.CFrame * rel end
		end
		local shipped = hitbox.CFrame * pivotRel * Swing(ship)
		for _, s in pairs(seats) do
			if s.Seat.Parent then s.Seat.CFrame = shipped * s.Rel end
		end
	end
end

return B
