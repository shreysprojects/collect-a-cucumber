-- WP-SERVER unit test: ServerStorage.PetEffectsBus (Core.Recipients / Core.Enqueue / Emit / Flush) - 2026-09-22
-- Read-only: the module is loaded from its source text (loopback :8793) and driven with plain-table fakes
-- (players, clock, sender, root lookup). Start() is never called, so no instance is created.
local H = game:GetService("HttpService")
local SRC = H:GetAsync("http://127.0.0.1:8793/ServerStorage.PetEffectsBus.lua")

local pass, fail, failures = 0, 0, {}
local function check(name, cond, detail)
	if cond then pass += 1 else
		fail += 1
		if #failures < 8 then table.insert(failures, name .. (detail and (" (" .. tostring(detail) .. ")") or "")) end
	end
end
local function Fresh()
	local fn, err = loadstring(SRC)
	assert(fn, err)
	return fn()
end
local function ids(list)
	local out = {}
	for _, p in ipairs(list) do table.insert(out, tostring(p.UserId)) end
	return table.concat(out, ",")
end

--..fakes..--
local function FakePlayer(id, pos) return {UserId = id, Pos = pos, Name = "P" .. id} end
local players = {
	FakePlayer(1, Vector3.new(0, 0, 0)),
	FakePlayer(2, Vector3.new(179.9, 0, 0)),
	FakePlayer(3, Vector3.new(0, 0, 180)), -- exactly on the radius: included
	FakePlayer(4, Vector3.new(180.1, 0, 0)),
	FakePlayer(5, Vector3.new(500, 0, 0)),
	FakePlayer(6, nil), -- no character
}
local function rootOf(p) return p.Pos end
local fakePlayers = {GetPlayers = function() return players end}

--..Core.Recipients (radius selection)..--
do
	local bus = Fresh()
	local Core = bus.Core
	check("radius constant 180", Core.RADIUS == 180, Core.RADIUS)
	check("cap constant 48", Core.MAX_EVENTS == 48, Core.MAX_EVENTS)
	local origin = Vector3.new(0, 0, 0)
	check("owner far + 3 near", ids(Core.Recipients(5, origin, players, rootOf)) == "1,2,3,5", ids(Core.Recipients(5, origin, players, rootOf)))
	check("owner near counted once", ids(Core.Recipients(1, origin, players, rootOf)) == "1,2,3", ids(Core.Recipients(1, origin, players, rootOf)))
	check("nil position = owner only", ids(Core.Recipients(5, nil, players, rootOf)) == "5")
	check("NaN position = owner only", ids(Core.Recipients(5, Vector3.new(0 / 0, 0, 0), players, rootOf)) == "5")
	check("inf position = owner only", ids(Core.Recipients(5, Vector3.new(math.huge, 0, 0), players, rootOf)) == "5")
	check("absent owner = near only", ids(Core.Recipients(99, origin, players, rootOf)) == "1,2,3")
	check("nil owner = near only", ids(Core.Recipients(nil, origin, players, rootOf)) == "1,2,3")
	check("radius override", ids(Core.Recipients(5, origin, players, rootOf, 10)) == "1,5")
	check("players not a table", #Core.Recipients(5, origin, nil, rootOf) == 0)
	local ok, list = pcall(Core.Recipients, 5, origin, players, function() error("boom") end)
	check("rootOf error tolerated", ok and ids(list) == "5", ok and ids(list) or list)
	check("rootOf non-vector tolerated", ids(Core.Recipients(5, origin, players, function() return "x" end)) == "5")
	check("OwnerIdOf number", Core.OwnerIdOf(7) == 7)
	check("OwnerIdOf NaN", Core.OwnerIdOf(0 / 0) == nil)
	check("OwnerIdOf string", Core.OwnerIdOf("7") == nil)
	check("OwnerIdOf table", Core.OwnerIdOf({UserId = 7}) == nil)
end

--..Core.Enqueue (cap, oldest dropped first)..--
do
	local Core = Fresh().Core
	local queue, dropped = {}, {}
	for i = 1, 5 do table.insert(dropped, Core.Enqueue(queue, {Id = i}, 3)) end
	check("enqueue drop counts", table.concat(dropped, ",") == "0,0,0,1,1", table.concat(dropped, ","))
	check("enqueue keeps newest", #queue == 3 and queue[1].Id == 3 and queue[3].Id == 5)
	local q2 = {}
	local total = 0
	for i = 1, 50 do total += Core.Enqueue(q2, {Id = i}, nil) end
	check("default cap 48", #q2 == 48 and total == 2 and q2[1].Id == 3, #q2 .. "/" .. total)
	local q3 = {}
	for i = 1, 3 do Core.Enqueue(q3, {Id = i}, 0) end
	check("cap floor 1", #q3 == 1 and q3[1].Id == 3)
end

--..Emit / Flush with injected clock, players, sender..--
do
	local bus = Fresh()
	local clock = 1000
	local sent = {}
	bus.Init({
		Clock = function() return clock end,
		Players = fakePlayers,
		RootOf = rootOf,
		Fire = function(player, payload) table.insert(sent, {Player = player, Payload = payload}) end,
	})
	check("not started", bus.IsStarted() == false)
	local far = Vector3.new(5000, 0, 0)
	local last, monotonic = 0, true
	local events = {}
	for i = 1, 60 do
		local ev = {Kind = "Shot", PetId = "p" .. i}
		bus.Emit(ev, 5, far)
		if type(ev.Id) ~= "number" or ev.Id ~= last + 1 then monotonic = false end
		last = ev.Id or last
		events[i] = ev
	end
	check("ids monotonic 1..60", monotonic and last == 60, last)
	check("T stamped from clock", events[1].T == 1000)
	check("Owner stamped", events[1].Owner == 5)
	local d = bus.GetDiagnostics()
	check("emitted 60", d.Emitted == 60, d.Emitted)
	check("cap drops 12", d.Dropped == 12, d.Dropped)
	check("queued 48", d.Queued == 48, d.Queued)
	d.Emitted = -1
	check("diagnostics are a copy", bus.GetDiagnostics().Emitted == 60)
	local batches = bus.Flush(2000)
	check("one batch", batches == 1 and #sent == 1, batches)
	local payload = sent[1] and sent[1].Payload
	check("batch to owner", sent[1] and sent[1].Player.UserId == 5)
	check("batch T = flush time", payload and payload.T == 2000)
	check("batch holds the newest 48", payload and #payload.Events == 48 and payload.Events[1].Id == 13 and payload.Events[48].Id == 60)
	d = bus.GetDiagnostics()
	check("sent 48", d.Sent == 48 and d.Batches == 1 and d.Queued == 0, d.Sent)
	check("second flush empty", bus.Flush(2001) == 0 and #sent == 1)

	-- caller T kept; several recipients share the event
	sent = {}
	local ev = {Kind = "AbilityApplied", T = 5}
	bus.Emit(ev, 5, Vector3.new(0, 0, 0))
	check("caller T kept", ev.T == 5)
	check("id continues", ev.Id == 61, ev.Id)
	check("four recipients", bus.Flush() == 4 and #sent == 4, #sent)
	local got = {}
	for _, s in ipairs(sent) do got[s.Player.UserId] = s.Payload.Events[1] == ev end
	check("same event to 1,2,3,5", got[1] and got[2] and got[3] and got[5] and not got[4] and not got[6])
	check("flush default time = clock", sent[1] and sent[1].Payload.T == clock)

	-- bad input: dropped + counted, never an error, no id consumed
	local before = bus.GetDiagnostics()
	local okAll = true
	for _, args in ipairs({
		{nil, 5, far}, {"x", 5, far}, {{}, 5, far}, {{Kind = 3}, 5, far},
		{{Kind = "Shot"}, nil, far}, {{Kind = "Shot"}, 0 / 0, far}, {{Kind = "Shot"}, math.huge, far}, {{Kind = "Shot"}, "5", far},
	}) do
		local ok = pcall(bus.Emit, args[1], args[2], args[3])
		okAll = okAll and ok
	end
	local after = bus.GetDiagnostics()
	check("bad input never errors", okAll)
	check("bad input counted", after.Invalid - before.Invalid == 8, after.Invalid - before.Invalid)
	check("bad input emits nothing", after.Emitted == before.Emitted and after.Queued == 0)
	local ev2 = {Kind = "ShieldBlocked"}
	bus.Emit(ev2, 5, nil)
	check("no id consumed by bad input", ev2.Id == 62, ev2.Id)
	check("nil position = owner only diag", bus.GetDiagnostics().OwnerOnly == before.OwnerOnly + 1)
	sent = {}
	bus.Flush()
	check("owner-only delivered", #sent == 1 and sent[1].Player.UserId == 5)

	-- second Init ignored
	bus.Init({Clock = function() return -1 end})
	local ev3 = {Kind = "Shot"}
	bus.Emit(ev3, 5, far)
	check("second Init ignored", ev3.T == clock)
end

--..sender / players failures..--
do
	local bus = Fresh()
	bus.Init({Clock = function() return 1 end, Players = {GetPlayers = function() error("no players") end}, RootOf = rootOf})
	local ok = pcall(bus.Emit, {Kind = "Shot"}, 5, Vector3.new())
	check("GetPlayers error swallowed", ok and bus.GetDiagnostics().Invalid == 1)
	local bus2 = Fresh()
	bus2.Init({Clock = function() return 1 end, Players = fakePlayers, RootOf = rootOf, Fire = function() error("net down") end})
	bus2.Emit({Kind = "Shot"}, 5, Vector3.new(5000, 0, 0))
	local okFlush, n = pcall(bus2.Flush)
	local d = bus2.GetDiagnostics()
	check("send error swallowed", okFlush and n == 0 and d.SendErrors == 1 and d.Sent == 0, tostring(n))
	local bus3 = Fresh()
	bus3.Init({Clock = function() return 1 end, Players = fakePlayers, RootOf = rootOf}) -- no Fire, not started: no remote
	bus3.Emit({Kind = "Shot"}, 5, Vector3.new(5000, 0, 0))
	check("no sender before Start keeps the queue", bus3.Flush() == 0 and bus3.GetDiagnostics().Queued == 1)
end

return ("WP-SERVER PetEffectsBus: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
