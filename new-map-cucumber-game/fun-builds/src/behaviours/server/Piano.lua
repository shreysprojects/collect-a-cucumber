--[[
	Piano  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds HomePiano
	Server half of the playable grand piano (fun-builds/CONTRACT.md, package HomePiano; model
	fun-builds/models/build_Piano.py). The piano's bench gets one invisible anchored Seat on Pivot_Bench (the top of
	the bench cushion) turned to face the keyboard (authored +Z), with the framework's prompt "Play piano". Anyone
	may play - it's a piano.
	State Fun_Player = the pianist's UserId (0 = nobody): the client half opens the piano GUI for that player, and
	every client leans the pianist over the keys.
	Action "Note" (client -> server): payload = a MIDI note number, or a chord {n, ...} (at most MAX_CHORD) pressed
	within one client send window. Only the player seated at THIS piano is heard, at most SENDS_PER_SECOND sends and
	NOTES_PER_SECOND notes a second each, every note a whole number in NOTE_MIN..NOTE_MAX. Accepted notes go to
	every client with ctx:Fire("Note", {n | {n, ...}, userId}); the sender's own client skips them (it already
	played them the moment the key went down).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local SEAT_NAME = "PianoBench"                  -- the client half recognises the pianist's SeatPart by this name
local SEAT_SIZE = Vector3.new(2.2, 0.4, 1.2)    -- the invisible Seat; its TOP face sits on Pivot_Bench
local BENCH_FALLBACK = Vector3.new(0, 2.2, -4.5) -- authored Pivot_Bench (build_Piano.py) if the attribute is missing
local PROMPT_DISTANCE = 8
local SENDS_PER_SECOND = 12
local NOTES_PER_SECOND = 30
local MAX_CHORD = 6
local NOTE_MIN, NOTE_MAX = 24, 108              -- MIDI C1 .. C8 (the GUI plays C2 .. B6)

local B = {}
B.Keys = {"Piano"}
B.ActionRange = 30

--..Behaviour..--
function B.Server(model, ctx)
	local top = Kit.Pivot(model, "Bench") or Kit.ToWorld(model, BENCH_FALLBACK)
	--.. the build's authored axes, turned round: the pianist faces authored +Z = the keyboard
	local facing = Kit.Origin(model).Rotation * CFrame.Angles(0, math.pi, 0)
	local seat = ctx:Seat(CFrame.new(top) * facing * CFrame.new(0, -SEAT_SIZE.Y * 0.5, 0), {
		Name = SEAT_NAME,
		Size = SEAT_SIZE,
		Prompt = "Play piano",
		Object = "Piano",
		Distance = PROMPT_DISTANCE,
	})
	ctx.PianoSeat = seat
	ctx.PianoBudget = setmetatable({}, {__mode = "k"}) -- [player] = {t, sends, notes}

	--.. who plays -> Fun_Player (0 = nobody, -1 = a humanoid that is not a player)
	local function sync()
		local humanoid = seat.Occupant
		local player = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
		ctx:SetState("Player", player and player.UserId or (humanoid and -1 or 0))
	end
	ctx:Connect(seat:GetPropertyChangedSignal("Occupant"), sync)
	sync()
end

--..Actions..--
local function ValidNote(n)
	return type(n) == "number" and n == n and n % 1 == 0 and n >= NOTE_MIN and n <= NOTE_MAX
end

B.Actions = {
	Note = function(model, player, payload, ctx)
		local seat = ctx.PianoSeat
		if not seat or not seat.Parent then return end
		local humanoid = ctx:HumanoidOf(player)
		if not humanoid or seat.Occupant ~= humanoid then return end -- only the pianist at THIS piano

		--.. rate limit (per player, per piano)
		local now = os.clock()
		local budget = ctx.PianoBudget[player]
		if not budget or now - budget.t >= 1 then
			budget = {t = now, sends = 0, notes = 0}
			ctx.PianoBudget[player] = budget
		end
		budget.sends += 1
		if budget.sends > SENDS_PER_SECOND then return end

		--.. a note or a chord
		if ValidNote(payload) then payload = {payload} end
		if type(payload) ~= "table" then return end
		local notes = {}
		for i = 1, MAX_CHORD do
			local n = rawget(payload, i)
			if n == nil then break end
			if ValidNote(n) and budget.notes < NOTES_PER_SECOND then
				budget.notes += 1
				table.insert(notes, n)
			end
		end
		if #notes == 0 then return end
		ctx:Fire("Note", {#notes == 1 and notes[1] or notes, player.UserId})
	end,
}

return B
