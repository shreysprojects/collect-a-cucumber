--[[
	Hammock  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the functional Hammock (fun-builds/CONTRACT.md; user: "make all the fun stuff functional").
	  * one LYING seat (ctx:Seat{Lie = true}) on the bed amidships: "Lie down" prompt, anyone may use it.
	    The seat sits over the sag point (Pivot_BedLow), a touch toward the pillow, and its LookVector points
	    along the build's local -X, so the occupant's head lands on the pillow (the -X end, authored
	    x -2.15..-1.35) and the body fills the usable lie area (authored x -2.2..2.2)
	  * state for the client half (ReplicatedStorage.FunBehavioursClient.Hammock), which swings the
	    Bed / Weave / Cords about the ring line and carries the seat with it locally:
	      Fun_Seat     = name of this build's runtime folder (workspace.FunBuildRuntime.<name>.HammockSeat)
	      Fun_Occupied = true while someone lies in it
	      Fun_Since    = server time (Kit.Now) of the last occupied/free change (0 = never), so every
	                     client ramps the swing up / down identically
	No economy, no physics on the character (the seat weld carries it).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage.Modules.FunBuildKit)

--..Config..--
local SEAT_NAME = "HammockSeat"      -- the client half finds the seat by this name
local BED_LOW = Vector3.new(0, 1.2, 0) -- fallback for Pivot_BedLow (authored)
local BACK_ABOVE_LOW = 0.14          -- authored studs: the occupant's back rests this far above the sheet's underside
local TOWARD_PILLOW = 0.25           -- authored studs the root moves toward -X (the body is longer below the root than above)
local SEAT_SIZE = Vector3.new(2, 0.2, 4) -- invisible seat; Z runs along the hammock
local PROMPT_OFFSET = Vector3.new(0, 1.6, 0) -- in the seat's space (Y up)
local PROMPT_DISTANCE = 9

local B = {}

--..Behaviour..--
function B.Server(model, ctx)
	local low = model:GetAttribute("Pivot_BedLow")
	if typeof(low) ~= "Vector3" then low = BED_LOW end
	local origin = Kit.Origin(model)
	local backAt = Kit.ToWorld(model, Vector3.new(low.X - TOWARD_PILLOW, low.Y + BACK_ABOVE_LOW, low.Z))
	--.. LookVector = the build's -X (CFrame.Angles(0, pi/2, 0) turns -Z onto -X): Lie puts the head toward it
	local rotation = origin.Rotation * CFrame.Angles(0, math.pi / 2, 0)
	local seatCF = CFrame.new(backAt - origin.UpVector * (SEAT_SIZE.Y * 0.5)) * rotation

	local seat = ctx:Seat(seatCF, {
		Name = SEAT_NAME,
		Size = SEAT_SIZE,
		Lie = true,
		Prompt = "Lie down",
		Object = tostring(model:GetAttribute("DisplayName") or "Hammock"),
		Distance = PROMPT_DISTANCE,
		PromptOffset = PROMPT_OFFSET,
	})

	--..State for the client swing..--
	ctx:SetState("Seat", ctx.Folder.Name)
	ctx:SetState("Occupied", false)
	ctx:SetState("Since", 0)
	ctx:Connect(seat:GetPropertyChangedSignal("Occupant"), function()
		local occupied = seat.Occupant ~= nil
		if ctx:GetState("Occupied") == occupied then return end
		ctx:SetState("Since", Kit.Now())
		ctx:SetState("Occupied", occupied)
	end)
end

return B
