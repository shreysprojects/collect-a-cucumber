--[[
	Sofa  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds HomeLiving
	Server half of the living-room couches: the Sofa (3 seats) and its matching Armchair (1 seat) - one module
	serves both keys. Every Pivot_Seat<i> attribute on the build (authored: the SQUASHED top of seat cushion i -
	where the client's squash leaves it while someone sits, so the sitter rests in the dent; see
	fun-builds/models/couchlib.py) gets an invisible anchored Seat, its top face on the pivot, facing the build's
	FRONT (-Z) with the framework's "Sit" prompt (ctx:Seat). Anyone may sit - it's a couch.
	State Fun_Seat<i> = the sitter's UserId (0 = empty, -1 = a humanoid that is not a player) so every client
	can squash cushion i and play the soft poof (ReplicatedStorage.FunBehavioursClient.Sofa).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local MAX_SEATS = 6                        -- Pivot_Seat1 .. Pivot_Seat6 at most (stops at the first missing one)
local SEAT_SIZE = Vector3.new(1.8, 0.4, 1.8) -- the invisible Seat; its TOP face sits on the pivot

local B = {}
B.Keys = {"Sofa", "Armchair"}

function B.Server(model, ctx)
	--.. the build's authored axes in the world: a seat facing -Z authored faces the couch's front
	local rotation = Kit.Origin(model).Rotation
	for i = 1, MAX_SEATS do
		local name = "Seat" .. i
		local top = Kit.Pivot(model, name)
		if not top then break end
		local seat = ctx:Seat(CFrame.new(top) * rotation * CFrame.new(0, -SEAT_SIZE.Y * 0.5, 0), {
			Name = tostring(ctx.Base) .. name,
			Size = SEAT_SIZE,
			Prompt = "Sit",
			Distance = 8,
		})
		--.. who sits here -> Fun_Seat<i> (clients squash the cushion from it)
		local function sync()
			local humanoid = seat.Occupant
			local player = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
			ctx:SetState(name, player and player.UserId or (humanoid and -1 or 0))
		end
		ctx:Connect(seat:GetPropertyChangedSignal("Occupant"), sync)
		sync()
	end
end

return B
