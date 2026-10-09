--[[
	Hammock  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the functional Hammock (server half: ServerStorage.FunBehaviours.Hammock).
	  * the Bed / Weave / Cords parts swing as one rigid sling about the line through Pivot_RingMinusX and
	    Pivot_RingPlusX (the two rings): a tiny sway while it is empty, a gentle +/-5 degree rock while
	    someone lies in it. The angle is amplitude * sin(2 pi * serverTime / PERIOD) and the amplitude ramps
	    from the server's Fun_Occupied / Fun_Since, so every client shows the same swing at the same moment
	  * the runtime seat (workspace.FunBuildRuntime.<Fun_Seat>.HammockSeat) is carried with the sling locally,
	    so the lying occupant (welded to it) rocks too - on every client, since each one moves its own copy
	  * a Creak when someone drops in, then an occasional one at the end of a swing while occupied (which
	    swings creak is decided from the swing's index, so every client creaks together)
	Everything is posed relative to the build's Hitbox each frame (a move lands cleanly) and put back on
	cleanup: build parts at their rest pose, the seat at the CFrame the server gave it.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))
local FunAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunAssets"))

--..Config..--
local SWING_PARTS = {"Bed", "Weave", "Cords"} -- hang off the ring line; Rings / Rails / Timber stay put
local SEAT_NAME = "HammockSeat"                -- must match the server half
local PERIOD = 3                               -- seconds per full swing (both amplitudes, so ramps never jump)
local SWING_DEG = 5                            -- occupied amplitude
local IDLE_DEG = 0.6                           -- empty: a tiny sway
local RAMP_IN = 1.6                            -- seconds from sway to full swing after someone lies down
local RAMP_OUT = 2.8                           -- ... and back after they get up
local CREAK_CHANCE = 0.4                       -- of each swing end, while occupied
local CREAK_MIN_DEG = 2.5                      -- no creak until the swing is this big
local CREAK_VOLUME = 0.35
local SEAT_RETRY = 0.5                         -- seconds between looks for the (streamed) seat

local B = {}
B.StepRange = 150

--..Helpers..--
local function Smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

--.. a deterministic 0..1 from an integer: exact integer maths, so every client gets the same value
local function Hash01(n)
	n = math.floor(n) % 100003
	return ((n * 7919 + 4099) % 1000) / 1000
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	local ringA = model:GetAttribute("Pivot_RingMinusX")
	local ringB = model:GetAttribute("Pivot_RingPlusX")
	if not hitbox or typeof(ringA) ~= "Vector3" or typeof(ringB) ~= "Vector3" then return end

	--..The swing axis (the ring line), kept relative to the Hitbox..--
	local pA, pB = Kit.ToWorld(model, ringA), Kit.ToWorld(model, ringB)
	if (pB - pA).Magnitude < 0.01 then return end
	local axisDir = (pB - pA).Unit
	local up = Kit.Origin(model).UpVector
	up = (up - axisDir * up:Dot(axisDir)).Unit
	local axisCF = CFrame.fromMatrix((pA + pB) * 0.5, axisDir, up) -- local X = the ring line
	local axisRel = hitbox.CFrame:ToObjectSpace(axisCF)

	--..The sling rig..--
	local rig = {}   -- [part] = CFrame relative to the axis
	local home = {}  -- [part] = CFrame relative to the Hitbox (restored on cleanup)
	local creakParent
	for _, name in ipairs(SWING_PARTS) do
		local part = Kit.Part(model, name)
		if part then
			rig[part] = axisCF:ToObjectSpace(part.CFrame)
			home[part] = hitbox.CFrame:ToObjectSpace(part.CFrame)
			creakParent = creakParent or part
		end
	end
	if not next(rig) then return end

	local creak = ctx:Sound(creakParent, FunAssets.Sfx.Creak, {Volume = CREAK_VOLUME, PlaybackSpeed = 0.6})

	--..State..--
	local occupied, since = false, 0
	local primed = false
	ctx:OnState("Occupied", function(v)
		local now = v == true
		if primed and now and not occupied then -- someone just dropped in: the ropes take the weight
			creak.PlaybackSpeed = 0.5
			creak:Play()
		end
		primed = true
		occupied = now
	end)
	ctx:OnState("Since", function(v) since = tonumber(v) or 0 end)

	--..The runtime seat (streams on its own; the server remakes it when the build moves)..--
	local seat, seatRel, seatHome
	local seatFolder = ctx:State("Seat")
	local nextLook = 0
	local function ReleaseSeat()
		if seat and seat.Parent and seatHome then seat.CFrame = seatHome end
		seat, seatRel, seatHome = nil, nil, nil
	end
	local function FindSeat(axisNow)
		local runtime = workspace:FindFirstChild(Kit.RUNTIME_FOLDER)
		local folder = type(seatFolder) == "string" and runtime and runtime:FindFirstChild(seatFolder)
		local s = folder and folder:FindFirstChild(SEAT_NAME)
		if s and s:IsA("BasePart") then
			seat, seatHome = s, s.CFrame -- a fresh instance: this is the server's (unswung) CFrame
			seatRel = axisNow:ToObjectSpace(seatHome)
		end
	end
	ctx:OnState("Seat", function(v)
		if v == seatFolder then return end
		ReleaseSeat()
		seatFolder = v
		nextLook = 0
	end)

	--..Amplitude (radians) at server time now..--
	local swingRad, idleRad = math.rad(SWING_DEG), math.rad(IDLE_DEG)
	local function Amplitude(now)
		local age = now - since
		if occupied then return idleRad + (swingRad - idleRad) * Smooth(age / RAMP_IN) end
		return swingRad + (idleRad - swingRad) * Smooth(age / RAMP_OUT)
	end

	--..Every frame..--
	local lastEnd
	ctx:Step(function(_, now)
		if not hitbox.Parent then return end
		local axisNow = hitbox.CFrame * axisRel
		local amp = Amplitude(now)
		local phase = (now % PERIOD) / PERIOD
		local pose = axisNow * CFrame.Angles(amp * math.sin(phase * 2 * math.pi), 0, 0)
		Kit.PoseRig(rig, pose)

		--.. carry the seat (and whoever lies on it)
		if seat and not seat.Parent then seat, seatRel, seatHome = nil, nil, nil end
		if not seat and os.clock() >= nextLook then
			nextLook = os.clock() + SEAT_RETRY
			FindSeat(axisNow)
		end
		if seat and seatRel then seat.CFrame = pose * seatRel end

		--.. a creak at some swing ends (sin peaks at phase 0.25 / 0.75)
		local swingEnd = math.floor((now - PERIOD * 0.25) / (PERIOD * 0.5))
		if lastEnd and swingEnd ~= lastEnd and occupied and amp >= math.rad(CREAK_MIN_DEG) and Hash01(swingEnd) < CREAK_CHANCE then
			creak.PlaybackSpeed = 0.52 + 0.16 * Hash01(swingEnd + 17)
			creak:Play()
		end
		lastEnd = swingEnd
	end)

	--..Cleanup: rest pose relative to where the build IS now, seat back where the server put it..--
	return function()
		ReleaseSeat()
		if not hitbox.Parent then return end
		for part, rel in pairs(home) do
			if part.Parent then part.CFrame = hitbox.CFrame * rel end
		end
	end
end

return B
