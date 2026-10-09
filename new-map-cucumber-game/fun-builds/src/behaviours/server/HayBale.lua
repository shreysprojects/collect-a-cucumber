--[[
	HayBale  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package GardenLife
	Sit spots on the hay (HayBale x1.3). No client half: the seat, its "Sit" prompt and the sitting pose are all
	FunBuildService's ctx:Seat.
	  HayBale_B Square Bale  one seat on top, in the middle of the long side, facing the build's front: the bale is
	                         2.6 x 1.4 x 1.4 (AUTHORED), top at y 1.40, so the thighs rest on the straw and the legs
	                         hang over the front face.
	  HayBale_C Hay Stack    one seat on the TOP bale (it lies crossways at x 6.60, z -0.50, top at y 2.80 and
	                         overhangs the front bale): near its front end, facing front, so the knees clear the end
	                         and the legs dangle in front of the stack - a king-of-the-haystack perch.
	  HayBale_A Round Bale   nothing (B.Keys leaves it out).
	Anyone may sit (a seat can't be used to grief the owner). The seat's top face is flush with the straw.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local SEAT_SIZE = Vector3.new(2, 0.4, 2)
--.. AUTHORED point on top of the straw under the sitter's hips (front = -Z), per variant
local SPOTS = {
	B = Vector3.new(0, 1.40, 0.10),
	C = Vector3.new(6.60, 2.80, -1.00),
}

local B = {}
B.Keys = {"HayBale_B", "HayBale_C"}

function B.Server(model, ctx)
	local spot = SPOTS[ctx.Variant or ""]
	if not spot then return end
	--.. CFrameToWorld: authored position (scaled) with the build's own axes, so the seat looks toward the front
	local top = Kit.CFrameToWorld(model, CFrame.new(spot))
	ctx:Seat(top * CFrame.new(0, -SEAT_SIZE.Y * 0.5, 0), {Name = "HaySeat", Size = SEAT_SIZE, Prompt = "Sit", Distance = 8})
end

return B
