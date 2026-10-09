--[[
	Bed  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the functional Bed (fun-builds/CONTRACT.md, HomeBedroom package).
	  * two LYING seats (ctx:Seat{Lie = true}), one per side of the double bed: "Sleep" prompt, anyone may use
	    them. Each seat's top face rests on the quilt at Pivot_Sleep1 / Pivot_Sleep2 (the pelvis spot, authored
	    +X / -X side), sunk a touch into the quilt, and its LookVector points at the build's +Z - the
	    headboard - so the occupant lies on their back with the head on Pillow1 / Pillow2. Each prompt hangs
	    over its own side of the bed, so a player walking up to a side gets that side's prompt
	  * state for the client half (ReplicatedStorage.FunBehavioursClient.Bed), which floats "Z z z" above
	    every sleeper's head, squashes their pillow and lights the crescent-moon night-light while anyone sleeps:
	      Fun_Sleeper1 / Fun_Sleeper2 = UserId of whoever lies in that side (0 = empty)
	No economy, no physics on the character (the seat weld carries it; jumping gets them up).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage.Modules.FunBuildKit)

--..Config..--
--.. the bed is 8 wide: pelvises 2.0 either side of the centre line, so two 4-wide lying avatars meet edge to
--.. edge; z 1.1 leaves the head top (~2.5 toward +Z) on the pillow, clear of the headboard pad
local SPOTS = { -- pelvis spot on the quilt per side (Pivot_<name>, authored) and its fallback
	{Pivot = "Sleep1", Fallback = Vector3.new(2, 2.2, 1.1)},  -- +X side (the viewer's left from the foot end)
	{Pivot = "Sleep2", Fallback = Vector3.new(-2, 2.2, 1.1)}, -- -X side
}
local SINK = 0.08                          -- authored studs the body sinks into the quilt
local SEAT_SIZE = Vector3.new(2, 0.2, 3)   -- invisible seat; Z runs along the bed
local PROMPT_OUT = 1.5                     -- authored studs from the seat out toward its side of the bed
local PROMPT_UP = 1.2                      -- studs above the quilt
local PROMPT_DISTANCE = 8

local B = {}

--..Behaviour..--
function B.Server(model, ctx)
	local origin = Kit.Origin(model)
	local up = origin.UpVector
	--.. LookVector = the build's +Z (the headboard): a lying occupant's head points along it
	local rotation = origin.Rotation * CFrame.Angles(0, math.pi, 0)
	local objectText = tostring(model:GetAttribute("DisplayName") or "Bed")

	for i, spot in ipairs(SPOTS) do
		local authored = model:GetAttribute("Pivot_" .. spot.Pivot)
		if typeof(authored) ~= "Vector3" then authored = spot.Fallback end
		local top = Kit.ToWorld(model, authored - Vector3.new(0, SINK, 0))
		local seatCF = CFrame.new(top - up * (SEAT_SIZE.Y * 0.5)) * rotation
		local side = authored.X >= 0 and 1 or -1
		local promptWorld = origin.RightVector * (side * PROMPT_OUT * ctx.Scale) + up * PROMPT_UP

		local seat = ctx:Seat(seatCF, {
			Name = "BedSeat" .. i,
			Size = SEAT_SIZE,
			Lie = true,
			Prompt = "Sleep",
			Object = objectText,
			Distance = PROMPT_DISTANCE,
			PromptOffset = seatCF:VectorToObjectSpace(promptWorld),
		})

		--..Who sleeps here (the client half draws the Zs over their head)..--
		local stateKey = "Sleeper" .. i
		ctx:SetState(stateKey, 0)
		ctx:Connect(seat:GetPropertyChangedSignal("Occupant"), function()
			local humanoid = seat.Occupant
			local player = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
			ctx:SetState(stateKey, player and player.UserId or 0)
		end)
	end
end

return B
