--[[
	GamingDesk  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds HomeOffice
	Server half of the GAMING DESK (fun-builds/notes/GamingDesk.md). The racing chair gets one invisible Seat at
	Pivot_Seat, facing the desk (authored +Z), with the prompt "Game" - anyone may play, it is a desk.
	CUKE RUN is PLAYED (2026-09-24, user: "make the gaming desk make u play the actual game instead of just show a
	video"): sitting down starts a RUN, the gamer's client plays it in a GUI and the client half of every other
	player re-simulates it on the monitor from the inputs this half relays.
	State (ReplicatedStorage.FunBehavioursClient.GamingDesk draws everything from it):
	  Fun_Player  the gamer's UserId (0 = nobody, -1 = a humanoid that is not a player: no run)
	  Fun_Seed    the current / last run's course seed (0 = none yet)
	  Fun_Since   Kit.Now() when that run started (sim time 0 = Since + READY); a run is LIVE while Since > Ended
	  Fun_Ended   Kit.Now() when the last run ended (the crash was reported, the gamer got up, or it went quiet)
	  Fun_EndTick the ended run's last sim tick, from the gamer's "Over" (0 = not known: the run ended without one).
	              Replays of the run stop there (Ended - Since is later: it includes the network delay)
	  Fun_Final   that run's score (0 = none / not plausible), Fun_Best the desk's best (survives a move / break of
	              the same build; not saved across servers)
	Runs  StartRun on sitting down and on "Again" (new seed + Since). The gamer's "Input" events (press / release,
	      stamped with their sim tick) are checked (the gamer, this seed, known kinds, ticks in order and not ahead
	      of the server clock), stored (up to MAX_EVENTS) as codes tick * 4 + kind and relayed to every client
	      (ctx:Fire "Input" {s, c, n = stored count}); "Sync" answers one client with the whole list ("Events").
	      "Over" {s, score, seconds} ends the run: the score counts only if plausible - seconds >= MIN_SECONDS, no
	      more than the server's clock allows (+ CLOCK_SLACK), score <= seconds * RATE + BONUS - then Final / Best /
	      Ended like before (NEW HI! on the monitor). EndTick = seconds in ticks whenever the time itself is
	      plausible (also for a run too short / a score too high to count). Getting up ends a live run after
	      LEAVE_GRACE (the client's "Over" usually comes first); a live run with no input for QUIET_SECONDS ends
	      without a score.
	      "Leave" stands the gamer up (the client also jumps out itself). No economy impact: the score is only drawn.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local SEAT_SIZE = Vector3.new(1.8, 0.4, 1.8) -- the invisible Seat; its TOP face sits on Pivot_Seat
local SEAT_FALLBACK = Vector3.new(0, 2.12, -1.92) -- authored, if Pivot_Seat is missing (build_GamingDesk.py)
local SEAT_NAME = "GamingDeskSeat"           -- the client half looks for this name on Humanoid.SeatPart

--.. the game (same numbers as the client half)
local TICK_RATE = 120          -- simulation ticks per second
local READY = 1.6              -- s of "READY?" / "GO!" before sim time 0
--.. plausibility: distance points <= VMAX (72) / PX_PER_POINT (3) = 24 per s; coins (50 each) at most one per
--.. obstacle gap, and a gap is at least (AIR_TIME + REACT_TIME = 0.95 s) of running = 52.7 per s -> 76.7 per s
local RATE, BONUS = 80, 150
local MIN_SECONDS = 2          -- a run shorter than this never scores (the first obstacle is ~2.5 s in)
local CLOCK_SLACK = 2          -- s of network jitter on top of the server-measured run time
local MAX_SCORE = 999999
local MAX_EVENTS = 6000        -- stored per run (~50 min of hard play); past it inputs are still relayed, not stored
local MAX_BATCH = 24           -- events per "Input"
local QUIET_SECONDS = 12       -- a live run with no input for this long ends (a run always needs a jump every few s)
local LEAVE_GRACE = 0.75       -- s after the gamer gets up before a live run is ended without a score
local AGAIN_GAP = 0.5          -- s between a run ending and "Again"
local SYNC_GAP = 1             -- s between two "Sync" answers to the same player
local KIND_CODES = {jump = 0, jumpUp = 1, duck = 2, duckUp = 3}

--..State..--
local Seeds = Random.new()
local Best = setmetatable({}, {__mode = "k"}) -- [model] = best score: survives a restart of the same build

local B = {}
B.Keys = {"GamingDesk"}
B.ActionRange = 200 -- "Sync" comes from anyone watching the monitor; the gamer's actions check the gamer

--..Helpers..--
local function Finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function StartRun(ctx)
	local d = ctx.Desk
	local seed
	repeat seed = Seeds:NextInteger(1, 2147483646) until seed ~= d.Seed
	d.Seed, d.Codes, d.LastTick, d.Full = seed, {}, 0, false
	d.Live, d.Quiet = true, os.clock()
	d.Gamer = ctx:GetState("Player")
	d.Since = Kit.Now()
	ctx:SetState("EndTick", 0) -- (set before Since / Seed: replicated in this order)
	ctx:SetState("Since", d.Since)
	ctx:SetState("Seed", seed)
end

--.. score = nil: the run ends without one (Final 0, Best unchanged); endTick = nil: its last tick is not known
local function EndRun(ctx, score, endTick)
	local d = ctx.Desk
	if not d.Live then return end
	d.Live = false
	d.EndedAt = os.clock()
	local final = score or 0
	ctx:SetState("Final", final)
	if score then
		local best = math.max(tonumber(ctx:GetState("Best")) or 0, final)
		Best[ctx.Model] = best
		ctx:SetState("Best", best)
	end
	ctx:SetState("EndTick", endTick or 0) -- (before Ended: a client that sees the end sees its tick)
	ctx:SetState("Ended", Kit.Now())
end

--..Behaviour..--
function B.Server(model, ctx)
	local top = Kit.Pivot(model, "Seat") or Kit.ToWorld(model, SEAT_FALLBACK)
	--.. the build's authored axes turned half a turn: the sitter faces the desk (authored +Z)
	local rotation = Kit.Origin(model).Rotation * CFrame.Angles(0, math.pi, 0)
	local seat = ctx:Seat(CFrame.new(top) * rotation * CFrame.new(0, -SEAT_SIZE.Y * 0.5, 0), {
		Name = SEAT_NAME,
		Size = SEAT_SIZE,
		Prompt = "Game",
		Object = "Gaming Desk",
		Distance = 8,
	})

	local d = {Seat = seat, Seed = 0, Codes = {}, LastTick = 0, Full = false, Live = false, Quiet = 0, Gamer = 0,
		Since = 0, EndedAt = 0, Synced = setmetatable({}, {__mode = "k"})}
	ctx.Desk = d
	ctx:SetState("Player", 0)
	ctx:SetState("Seed", 0)
	ctx:SetState("EndTick", 0)
	ctx:SetState("Best", Best[model] or 0)

	--.. who sits here -> Player + a new run; getting up -> Player 0 and the live run ends
	local function Sync()
		local humanoid = seat.Occupant
		local current = ctx:GetState("Player") or 0
		if humanoid then
			local player = Players:GetPlayerFromCharacter(humanoid.Parent)
			local id = player and player.UserId or -1
			if id ~= current then
				EndRun(ctx, nil)
				ctx:SetState("Player", id)
				if player then StartRun(ctx) end
			end
		elseif current ~= 0 then
			ctx:SetState("Player", 0)
			if d.Live then
				local seed = d.Seed
				task.delay(LEAVE_GRACE, function()
					if ctx:Alive() and d.Live and d.Seed == seed then EndRun(ctx, nil) end
				end)
			end
		end
	end
	ctx:Connect(seat:GetPropertyChangedSignal("Occupant"), Sync)
	Sync()

	--.. a live run that went quiet (the gamer's client stopped sending) ends
	ctx:Every(1, function()
		if d.Live and os.clock() - d.Quiet > QUIET_SECONDS then EndRun(ctx, nil) end
	end)
end

--..Actions (client -> server)..--
B.Actions = {
	--.. {s = seed, t = sim time, k = kind} or {s = seed, e = {{t, k}, ...}}: the gamer's presses / releases
	Input = function(model, player, payload, ctx)
		local d = ctx.Desk
		if not d or not d.Live or player.UserId ~= d.Gamer or type(payload) ~= "table" or payload.s ~= d.Seed then return end
		local list = type(payload.e) == "table" and payload.e or {payload}
		local maxTick = (Kit.Now() - d.Since - READY + CLOCK_SLACK) * TICK_RATE
		local out = {}
		for i = 1, math.min(#list, MAX_BATCH) do
			local e = list[i]
			local code = type(e) == "table" and KIND_CODES[e.k]
			if code and Finite(e.t) then
				local tick = math.floor(e.t * TICK_RATE + 0.5)
				if tick >= 1 and tick >= d.LastTick and tick <= maxTick then
					d.LastTick = tick
					table.insert(out, tick * 4 + code)
				end
			end
		end
		if #out == 0 then return end
		d.Quiet = os.clock()
		if not d.Full and #d.Codes + #out <= MAX_EVENTS then
			table.move(out, 1, #out, #d.Codes + 1, d.Codes)
			ctx:Fire("Input", {s = d.Seed, c = out, n = #d.Codes})
		else
			d.Full = true
			ctx:Fire("Input", {s = d.Seed, c = out, n = -1})
		end
	end,

	--.. {s = seed, score = n, seconds = sim seconds}: the crash (or the gamer left mid-run)
	Over = function(model, player, payload, ctx)
		local d = ctx.Desk
		if not d or not d.Live or player.UserId ~= d.Gamer or type(payload) ~= "table" or payload.s ~= d.Seed then return end
		local score, seconds = payload.score, payload.seconds
		if not Finite(score) or not Finite(seconds) then
			EndRun(ctx, nil)
			return
		end
		score = math.floor(score)
		local elapsed = Kit.Now() - d.Since - READY
		--.. the run's last tick, if the time is possible at all (the replays stop there)
		local endTick = (seconds > 0 and seconds <= elapsed + CLOCK_SLACK) and math.floor(seconds * TICK_RATE + 0.5) or nil
		if score < 0 or score > MAX_SCORE or seconds < MIN_SECONDS or seconds > elapsed + CLOCK_SLACK or score > seconds * RATE + BONUS then
			EndRun(ctx, nil, endTick) -- implausible (or too short): the run ends without a score
			return
		end
		EndRun(ctx, score, endTick)
	end,

	--.. PLAY AGAIN: a new run for the seated gamer
	Again = function(model, player, payload, ctx)
		local d = ctx.Desk
		if not d or d.Live or ctx:GetState("Player") ~= player.UserId then return end
		local humanoid = ctx:HumanoidOf(player)
		if not humanoid or d.Seat.Occupant ~= humanoid then return end
		if os.clock() - d.EndedAt < AGAIN_GAP then return end
		StartRun(ctx)
	end,

	--.. a client that came in late (or missed a relay) wants the whole list of this run
	Sync = function(model, player, payload, ctx)
		local d = ctx.Desk
		if not d or d.Seed == 0 or type(payload) ~= "table" or payload.s ~= d.Seed then return end
		local now = os.clock()
		if now - (d.Synced[player] or -math.huge) < SYNC_GAP then return end
		d.Synced[player] = now
		ctx:FireTo(player, "Events", {s = d.Seed, c = d.Codes, n = d.Full and -1 or #d.Codes})
	end,

	--.. EXIT: stand the gamer up
	Leave = function(model, player, payload, ctx)
		local d = ctx.Desk
		local humanoid = ctx:HumanoidOf(player)
		if not d or not humanoid or d.Seat.Occupant ~= humanoid then return end
		local weld = d.Seat:FindFirstChild("SeatWeld")
		if weld then weld:Destroy() end
	end,
}

return B
