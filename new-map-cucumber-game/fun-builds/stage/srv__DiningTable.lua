--[[
	DiningTable  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the DINING TABLE (fun-builds/CONTRACT.md, package HomeDining): a wooden dining set - a 5 x 4
	table with one chair on each side (two long sides + both ends), each pulled out far enough that a seated
	avatar's torso clears the table edge. Every chair is a real seat: an invisible Seat (ctx:Seat) sits on each
	cushion - Pivot_Seat1..4 = the top of the cushion, where the hips rest - with the usual "Sit" prompt (a taken
	seat hides its prompt). Anyone may sit (like a bench).
	Facing: the model authors where each sitter looks (Pivot_Seat<N>Face = a point straight in front of the
	seat, over the table), so the seats follow the model whatever its layout; without it a seat faces the table
	centre. The candle's flickering flame + glow are purely cosmetic and live in the client half.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local SEAT_COUNT = 4
local SEAT_SIZE = Vector3.new(1.6, 0.4, 1.6) -- X/Z scale with the build, Y stays (the hips rest on the top face)
local PROMPT_DISTANCE = 7

local B = {}
B.Keys = {"DiningTable"}

function B.Server(model, ctx)
	local origin = Kit.Origin(model)
	local up = origin.UpVector
	local scale = ctx.Scale
	local size = Vector3.new(SEAT_SIZE.X * scale, SEAT_SIZE.Y, SEAT_SIZE.Z * scale)

	for i = 1, SEAT_COUNT do
		local authored = model:GetAttribute("Pivot_Seat" .. i)
		if typeof(authored) == "Vector3" then
			local top = Kit.ToWorld(model, authored)
			--.. look where the model says (Pivot_Seat<N>Face), else at the table centre; always level
			local face = model:GetAttribute("Pivot_Seat" .. i .. "Face")
			local target = if typeof(face) == "Vector3"
				then Kit.ToWorld(model, face)
				else Kit.ToWorld(model, Vector3.new(0, authored.Y, 0))
			local look = target - top
			look -= up * look:Dot(up)
			if look.Magnitude < 1e-3 then look = origin.LookVector end
			local pos = top - up * (size.Y * 0.5)
			local cf = CFrame.lookAt(pos, pos + look.Unit, up)
			ctx:Seat(cf, {
				Name = "DiningSeat" .. i,
				Size = size,
				Object = "Dining Chair",
				Distance = PROMPT_DISTANCE,
			})
		end
	end
end

return B
