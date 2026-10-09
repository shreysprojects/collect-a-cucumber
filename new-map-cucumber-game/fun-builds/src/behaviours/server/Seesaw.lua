--[[
	Seesaw  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the functional SEESAW (fun-builds/CONTRACT.md, notes/Seesaw.md; user: "seesaw functional").
	The build: a red (+X) / blue (-X) plank on an A-frame. Everything named Plank* (PlankBeamRed, PlankBeamBlue,
	PlankSeats, PlankHandles, PlankPivotStrap) is ONE rigid assembly that swings about Pivot_PlankPivot, about the
	build's authored Z axis (the axle runs across the plank). A POSITIVE angle drops the red +X end
	(= CFrame.Angles(0, 0, -angle) in the authored frame) and the model SHIPS in the RedDown pose
	(State_RedDown = +12, State_Level = 0, State_BlueDown = -12).
	  * two invisible anchored seats, one on each yellow seat pad (ctx:Seat, "Ride" prompt, anyone may ride).
	    Each seat's place is worked out in the plank's LEVEL frame (origin = the pivot, +X toward red, authored
	    pad numbers x scale): hips on the pad top, the rider's back just clear of the backstop, facing the
	    pivot / grab bar. The server's plank never moves, so the seats are posed like the shipped plank
	    (RedDown) - the client half re-poses them every frame with the animated plank
	  * state for the client half (ReplicatedStorage.FunBehavioursClient.Seesaw):
	      Fun_RiderRed / Fun_RiderBlue  UserId on the red (+X) / blue (-X) seat, 0 = empty (-1 = a scripted dummy)
	      Fun_Since                     Kit.Now() when BOTH seats became occupied (0 while not both)
	      Fun_Lead                      +1 / -1: the end that was down at Since (+1 = red); the ride starts there
	      Fun_Id                        matches the SeesawId attribute on this build's two seats
	    and on each seat (tag FunSeesawSeat): SeesawId, SeesawSide (+1 red / -1 blue), SeesawOffset (Vector3,
	    the seat's position in the plank's LEVEL frame in world studs; the seat faces the pivot)
	No economy, no physics on the character (the seat weld carries the rider).
]]
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage.Modules.FunBuildKit)

--..Config..--
local SEAT_TAG = "FunSeesawSeat"          -- the client half finds this build's seats by tag + SeesawId
local PIVOT_NAME = "PlankPivot"           -- Pivot_PlankPivot (authored)
local DEFAULT_PIVOT = Vector3.new(0, 1.35, 0) -- fallback if the template lost Pivot_PlankPivot (authored)
local DEFAULT_SHIP = 12                   -- fallback for State_RedDown: the pose the model ships in (deg)
local PAD_TOP = 0.40                      -- authored: seat pad top above the pivot line, plank level
local BACKSTOP_X = 3.06                   -- authored: inner face of each end's backstop, from the pivot
local BACK_GAP = 0.6                      -- studs between the backstop and the rider's root centre
local SEAT_LIFT = 0.03                    -- studs the hips float above the pad (no clipping)
local SEAT_SIZE = Vector3.new(1.6, 0.4, 1.6)
local PROMPT_OFFSET = Vector3.new(0, 1.2, 0) -- in the seat's space (Y up)
local PROMPT_DISTANCE = 8
local SIDES = {{Side = 1, Name = "Red"}, {Side = -1, Name = "Blue"}}
--.. how long the client's plank takes to pass level after it turns toward the other end (keep in step with the
--.. client's RIDER_ACCEL / RIDER_DAMP and REST_ACCEL / REST_DAMP): a ride that starts sooner starts from the old end
local RIDER_HALF = 0.64
local REST_HALF = 1.4
local NPC_RIDER = -1 -- Fun_Rider* for a non-player occupant (a test dummy seated by script: seats are prompt-only)

local B = {}

--..Geometry (the client half uses the same frame: keep in step)..--
--.. the pivot frame: at Pivot_PlankPivot, with the build's authored axes
local function PivotFrame(model)
	local p = Kit.Pivot(model, PIVOT_NAME) or Kit.ToWorld(model, DEFAULT_PIVOT)
	return CFrame.new(p) * Kit.Origin(model).Rotation
end

--.. the plank swung to `deg` about the pivot (positive drops the red +X end)
local function Swing(deg)
	return CFrame.Angles(0, 0, -math.rad(deg))
end

--.. a seat's position in the plank's LEVEL frame (world studs), side +1 = red (+X) / -1 = blue (-X)
local function SeatOffset(side, scale)
	local x = BACKSTOP_X * scale - BACK_GAP
	local y = PAD_TOP * scale - SEAT_SIZE.Y * 0.5 + SEAT_LIFT
	return Vector3.new(side * x, y, 0)
end

--.. the seat's CFrame in the LEVEL frame: at the offset, facing the pivot
local function SeatRel(side, offset)
	return CFrame.lookAt(offset, offset + Vector3.new(-side, 0, 0))
end

--..Behaviour..--
function B.Server(model, ctx)
	local ship = tonumber(model:GetAttribute("State_RedDown")) or DEFAULT_SHIP
	local shipped = PivotFrame(model) * Swing(ship) -- the server's plank as it stands
	local id = string.format("%s_%x", tostring(model:GetAttribute("Owner") or 0), math.random(0, 0x7FFFFFFF))
	local display = tostring(model:GetAttribute("DisplayName") or "Seesaw")

	ctx:SetState("RiderRed", 0)
	ctx:SetState("RiderBlue", 0)
	ctx:SetState("Since", 0)
	ctx:SetState("Lead", 1)
	ctx:SetState("Id", id)

	--..The two seats..--
	local seats = {} -- [side] = Seat
	for _, s in ipairs(SIDES) do
		local offset = SeatOffset(s.Side, ctx.Scale)
		local seat = ctx:Seat(shipped * SeatRel(s.Side, offset), {
			Name = "SeesawSeat" .. s.Name,
			Size = SEAT_SIZE,
			Prompt = "Ride",
			Object = display .. " (" .. s.Name:lower() .. ")",
			Distance = PROMPT_DISTANCE,
			PromptOffset = PROMPT_OFFSET,
		})
		seat:SetAttribute("SeesawId", id)
		seat:SetAttribute("SeesawSide", s.Side)
		seat:SetAttribute("SeesawOffset", offset)
		CollectionService:AddTag(seat, SEAT_TAG)
		seats[s.Side] = seat
	end

	--..Riders -> state..--
	local function RiderId(seat)
		local humanoid = seat.Occupant
		if not humanoid then return 0 end
		local player = Players:GetPlayerFromCharacter(humanoid.Parent)
		return player and player.UserId or NPC_RIDER
	end
	--.. the end the plank is heading for / resting on (+1 red = the shipped rest), since when, and how long it
	--.. takes to get past level from the other end
	local heading, headingAt, headingHalf = 1, -math.huge, 0
	local function Refresh()
		if not ctx:Alive() then return end
		local red, blue = RiderId(seats[1]), RiderId(seats[-1])
		local oldRed, oldBlue = ctx:GetState("RiderRed") or 0, ctx:GetState("RiderBlue") or 0
		local both = red ~= 0 and blue ~= 0
		local wasBoth = oldRed ~= 0 and oldBlue ~= 0
		local now = Kit.Now()
		if both and not wasBoth then
			--.. the ride starts from the end that is down now: the one the plank was heading for, unless it only
			--.. just turned toward it (two riders hopping on together) - then it is still nearer the other end
			local lead = heading
			if now - headingAt < headingHalf then lead = -heading end
			ctx:SetState("Lead", lead)
			ctx:SetState("Since", now)
		elseif not both then
			if wasBoth then ctx:SetState("Since", 0) end
			local h = (red ~= 0 and 1) or (blue ~= 0 and -1) or 1
			if h ~= heading or wasBoth then
				heading, headingAt = h, now
				headingHalf = (red ~= 0 or blue ~= 0) and RIDER_HALF or REST_HALF
			end
		end
		ctx:SetState("RiderRed", red)
		ctx:SetState("RiderBlue", blue)
	end
	for _, seat in pairs(seats) do
		ctx:Connect(seat:GetPropertyChangedSignal("Occupant"), Refresh)
	end
end

return B
