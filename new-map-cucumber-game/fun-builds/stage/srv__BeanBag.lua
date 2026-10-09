--[[
	BeanBag  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the functional bean bags (fun-builds/CONTRACT.md) - serves BeanBag_A (Pouf),
	BeanBag_B (Slouch) and BeanBag_C (Ottoman).
	  * one low seat on top of the bag: "Flop down" prompt, anyone may use it. The seat's top face (where the
	    hips rest) is the bag's top as it will be SQUASHED by the client (x SQUASH_Y about the floor), a
	    little sunk in; the occupant faces the build's front (-Z) - on the Slouch that puts the back against
	    the tall bolster (+Z) and the hips in the seat hollow (B_Seat)
	  * Fun_Occupied (true while someone sits) drives the client half (ReplicatedStorage.FunBehavioursClient
	    .BeanBag): the bag squashes while occupied, springs back when free, and goes "poof" on sit
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage.Modules.FunBuildKit)

--..Config..--
local VARIANTS = { -- the part each variant's seat rests on (its top centre)
	A = "A_Body", -- Pouf: purple dome, top 1.61 authored
	B = "B_Seat", -- Slouch: the hollow in front of the back bolster, top 1.19
	C = "C_Dome", -- Ottoman: cushion dome, top 1.45
}
local SQUASH_Y = 0.88     -- keep in step with the client half
local SINK = 0.06         -- authored studs the hips sink below the squashed top
local MIN_HIPS = 1.05     -- authored: never lower than this (at x1.4 = 1.47 studs), so sitting feet clear the floor
local SEAT_SIZE = Vector3.new(2, 0.4, 2)
local PROMPT_OFFSET = Vector3.new(0, 1.3, 0)
local PROMPT_DISTANCE = 7

local B = {} -- module name BeanBag = the base key: serves BeanBag_A / _B / _C

--..Helpers..--
--.. half the part's extent along a world direction (its oriented box, not its centre)
local function HalfExtent(part, dir)
	local cf, s = part.CFrame, part.Size
	return 0.5 * (math.abs(cf.RightVector:Dot(dir)) * s.X + math.abs(cf.UpVector:Dot(dir)) * s.Y + math.abs(cf.LookVector:Dot(dir)) * s.Z)
end

--.. the part the seat rests on: the variant's named part, else the variant's tallest part
local function SeatPart(model, variant)
	local named = variant and VARIANTS[variant]
	local part = named and Kit.Part(model, named)
	if part then return part end
	local best, bestTop
	for _, p in ipairs(Kit.Parts(model, variant and (variant .. "_") or "")) do
		local top = p.Position.Y + HalfExtent(p, Vector3.yAxis)
		if not bestTop or top > bestTop then best, bestTop = p, top end
	end
	return best
end

--..Behaviour..--
function B.Server(model, ctx)
	local part = SeatPart(model, ctx.Variant)
	if not part then return end
	local floor = Kit.Floor(model)
	local up = floor.UpVector
	local top = floor:PointToObjectSpace(part.Position + up * HalfExtent(part, up)) -- floor frame, scaled studs
	local hips = math.max(top.Y * SQUASH_Y - SINK * ctx.Scale, MIN_HIPS * ctx.Scale)
	local seatTop = floor:PointToWorldSpace(Vector3.new(top.X, hips, top.Z))
	local seat = ctx:Seat(CFrame.new(seatTop - up * (SEAT_SIZE.Y * 0.5)) * floor.Rotation, {
		Name = "BeanBagSeat",
		Size = SEAT_SIZE,
		Prompt = "Flop down",
		Object = tostring(model:GetAttribute("DisplayName") or "Bean Bag"),
		Distance = PROMPT_DISTANCE,
		PromptOffset = PROMPT_OFFSET,
	})

	ctx:SetState("Occupied", false)
	ctx:Connect(seat:GetPropertyChangedSignal("Occupant"), function()
		ctx:SetState("Occupied", seat.Occupant ~= nil)
	end)
end

return B
