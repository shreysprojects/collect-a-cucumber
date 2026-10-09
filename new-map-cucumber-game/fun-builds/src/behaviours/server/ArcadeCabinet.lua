--[[
	ArcadeCabinet  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the playable ARCADE CABINET - "CUCUMBER CATCH" (fun-builds/CONTRACT.md, notes/ArcadeCabinet.md).
	Anyone may play (like the boost pad); nothing here touches the economy.
	  Prompt   "Play" (hold 0, E / ButtonX) at the control deck (Pivot_JoystickPivot): opens a SESSION for that
	           player and ctx:FireTo(player, "Open") - the client half builds the game GUI and plays it locally.
	  Sessions [player] = {Mark, Seen}. The first open session is the DRIVER: State Player = its display name
	           (the cabinet screen shows "NOW PLAYING <name>" to everyone else), State Stick = the driver's
	           joystick (-1 / 0 / 1, the client sends "Stick" only on change, throttled) so onlookers see the stick
	           move. A session ends on the client's "Close", when the player leaves / dies / walks SESSION_RANGE
	           away, or goes quiet for QUIET_SECONDS (an open game pings "Alive" every few seconds).
	  Score    {Score, Seconds} at every game over. Never trusted: Seconds is first capped by the SERVER's clock
	           since the session opened / the previous report (a report can't claim more time than really
	           passed, and a replayed report claims ~0 s), then accepted only if Seconds >= MIN_SECONDS and
	           Score <= Seconds * RATE + BONUS (the brief's plausibility rule: >= 5 s, <= 3 per second + 10).
	           A new best for this cabinet -> State HiScore / HiName and ctx:Fire("NewHigh", {Score, Name, UserId})
	           (every client: confetti out of the marquee + Cheer; the scorer's game-over card says so).
	  The cabinet's best survives a move / break / mend of the same placed build (weak table keyed by the
	  model); it is not saved across servers or rejoins (no DataStore - a toy high-score table).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local PROMPT_DISTANCE = 9        -- studs from the joystick (the player stands ~3 studs out at x1.25)
local PROMPT_LIFT = 1            -- authored studs above the deck surface for the prompt anchor
local SESSION_RANGE = 26         -- studs from the hitbox: farther ends the session (the client closes at 20)
local QUIET_SECONDS = 15         -- no "Alive" / "Stick" / "Score" for this long ends the session
local MIN_SECONDS = 5            -- plausibility: a round shorter than this never scores
local RATE, BONUS = 3, 10        -- plausibility: score <= seconds * RATE + BONUS
local CLOCK_SLACK = 3            -- s of network jitter allowed on top of the server-measured round time
local MAX_SCORE = 100000
local NAME_CHARS = 12
local JOYSTICK_FALLBACK = Vector3.new(0.62, 2.74, -1.06) -- authored Pivot_JoystickPivot (props-dump/ArcadeCabinet.txt)

--..State..--
local Best = setmetatable({}, {__mode = "k"}) -- [model] = {Score, Name, UserId}: survives a restart of the same build

local B = {}
B.Keys = {"ArcadeCabinet"}
B.ActionRange = 40

--..Helpers..--
--.. an arcade-style name: the display name, upper case, at most NAME_CHARS characters (utf8-safe)
local function ArcadeName(player)
	local name = player.DisplayName ~= "" and player.DisplayName or player.Name
	name = string.upper(name)
	local ok, length = pcall(utf8.len, name)
	if ok and length and length > NAME_CHARS then
		local cut = utf8.offset(name, NAME_CHARS + 1)
		if cut then name = name:sub(1, cut - 1) end
	elseif not ok or not length then
		name = name:sub(1, NAME_CHARS)
	end
	return name
end

local function Finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

--.. the arcade data this build's Server() keeps on its ctx (Actions reach it through ctx)
local function Data(ctx)
	return ctx.Arcade
end

--.. the driver (first open session) -> State Player / Stick
local function Publish(ctx)
	local a = Data(ctx)
	local driver = a.Order[1]
	if driver ~= a.Driver then
		a.Driver = driver
		ctx:SetState("Stick", 0)
	end
	ctx:SetState("Player", driver and ArcadeName(driver) or nil)
end

local function EndSession(ctx, player)
	local a = Data(ctx)
	if not a or not a.Sessions[player] then return end
	a.Sessions[player] = nil
	local i = table.find(a.Order, player)
	if i then table.remove(a.Order, i) end
	Publish(ctx)
end

--..Behaviour..--
function B.Server(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end

	local a = {Sessions = {}, Order = {}, Driver = nil}
	ctx.Arcade = a

	--.. the cabinet's best so far (this build instance: a move / break re-runs Server() with the same model)
	local best = Best[model]
	if best then
		ctx:SetState("HiScore", best.Score)
		ctx:SetState("HiName", best.Name)
	end
	ctx:SetState("Stick", 0)

	--..Prompt at the control deck..--
	local pivot = model:GetAttribute("Pivot_JoystickPivot")
	if typeof(pivot) ~= "Vector3" then pivot = JOYSTICK_FALLBACK end
	local anchor = Kit.ToWorld(model, pivot + Vector3.new(0, PROMPT_LIFT, 0))
	local prompt = ctx:Prompt(hitbox, {
		Action = "Play", Object = "Cucumber Catch", Hold = 0, Distance = PROMPT_DISTANCE, Name = "PlayPrompt",
		Offset = hitbox.CFrame:PointToObjectSpace(anchor),
	})
	ctx:Connect(prompt.Triggered, function(player)
		if not ctx:Alive() or not ctx:HumanoidOf(player) then return end
		local now = os.clock()
		local s = a.Sessions[player]
		if not s then
			s = {Mark = now, Seen = now}
			a.Sessions[player] = s
			table.insert(a.Order, player)
			Publish(ctx)
		end
		s.Seen = now
		ctx:FireTo(player, "Open")
	end)

	--..Session upkeep..--
	ctx:Connect(Players.PlayerRemoving, function(player) EndSession(ctx, player) end)
	ctx:Every(1, function()
		local now = os.clock()
		for player, s in pairs(a.Sessions) do
			if player.Parent ~= Players or now - s.Seen > QUIET_SECONDS or not ctx:Near(player, SESSION_RANGE) then
				EndSession(ctx, player)
			end
		end
	end)
end

--..Actions (client -> server)..--
B.Actions = {
	--.. {Score = n, Seconds = s} at a game over
	Score = function(model, player, payload, ctx)
		local a = Data(ctx)
		local s = a and a.Sessions[player]
		if not s or type(payload) ~= "table" then return end
		local score, seconds = payload.Score, payload.Seconds
		if not Finite(score) or not Finite(seconds) then return end
		local now = os.clock()
		local elapsed = now - s.Mark
		s.Mark = now
		s.Seen = now
		score = math.floor(score)
		if score <= 0 or score > MAX_SCORE then return end
		seconds = math.min(seconds, elapsed + CLOCK_SLACK)
		if seconds < MIN_SECONDS or score > seconds * RATE + BONUS then return end -- implausible: ignored
		local best = Best[model]
		if best and score <= best.Score then return end
		local name = ArcadeName(player)
		Best[model] = {Score = score, Name = name, UserId = player.UserId}
		ctx:SetState("HiScore", score)
		ctx:SetState("HiName", name)
		ctx:Fire("NewHigh", {Score = score, Name = name, UserId = player.UserId})
	end,

	--.. -1 / 0 / 1: the driver's joystick, mirrored to everyone
	Stick = function(model, player, payload, ctx)
		local a = Data(ctx)
		local s = a and a.Sessions[player]
		if not s or not Finite(payload) then return end
		s.Seen = os.clock()
		if a.Driver ~= player then return end
		local v = payload > 0.5 and 1 or (payload < -0.5 and -1 or 0)
		if ctx:GetState("Stick") ~= v then ctx:SetState("Stick", v) end
	end,

	--.. an open game says it is still there
	Alive = function(model, player, payload, ctx)
		local a = Data(ctx)
		local s = a and a.Sessions[player]
		if s then s.Seen = os.clock() end
	end,

	--.. the game GUI closed (exit, walked away, died)
	Close = function(model, player, payload, ctx)
		EndSession(ctx, player)
	end,
}

return B
