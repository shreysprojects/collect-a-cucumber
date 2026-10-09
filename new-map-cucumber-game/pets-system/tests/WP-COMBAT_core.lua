-- WP-COMBAT core unit tests (2026-09-22): ServerStorage.PetCombatService.Core with plain-table fakes.
-- Loads the module from the loopback src server; creates NO instances, changes nothing in the DataModel,
-- never calls Start with a PetService (no Heartbeat connection is made).
-- Run from an edit-peer execute_luau:
--   return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-COMBAT_core.lua"))()
local HttpService = game:GetService("HttpService")
local src = HttpService:GetAsync("http://127.0.0.1:8793/ServerStorage.PetCombatService.lua")
local compiled, compileErr = loadstring(src)
if not compiled then return "WP-COMBAT core: FAIL compile: " .. tostring(compileErr) end
local M = compiled()
local Core = M.Core

local pass, fail, failures = 0, 0, {}
local function check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 10 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

local V = Vector3.new
local NaN = 0 / 0
local function Z(name, owner, pos, extra)
	local info = {Model = {Name = name}, Owner = owner, Position = pos, Carrying = false, Grappling = false, Health = 50, MaxHealth = 50}
	for k, v in pairs(extra or {}) do info[k] = v end
	return info
end
local function Stats(over)
	local s = {Valid = true, Range = 26, ShotInterval = 2.5, ShotDamage = 3, Rarity = "Common"}
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end
local function Pet(id, user, over)
	return {PetId = id, UserId = user, Stats = Stats(over)}
end

-- run one scan with fakes; damage(model, amount) -> accepted, health (default true, 10)
local function Scan(state, t, pets, infos, positions, log, damage, emitLog)
	return Core.RunScan(state, {
		Now = t, Pets = pets, Infos = Core.NormalizeInfos(infos), Scan = 0.2,
		PositionOf = function(id) return positions[id] end,
		Damage = function(model, amount)
			table.insert(log, {T = t, Model = model, Amount = amount})
			if damage then return damage(model, amount) end
			return true, 10
		end,
		Emit = function(event, owner, position)
			if emitLog then table.insert(emitLog, {Event = event, Owner = owner, Position = position}) end
		end,
	})
end

--.. module shape
check("shape: Init/Start/IsStarted/GetDiagnostics", type(M.Init) == "function" and type(M.Start) == "function" and type(M.IsStarted) == "function" and type(M.GetDiagnostics) == "function")
check("shape: not started before Start", M.IsStarted() == false)
M.Start() -- no Init: must warn and stay off (no Heartbeat connection)
check("shape: Start without Init stays off", M.IsStarted() == false)
local diag = M.GetDiagnostics()
check("shape: diag keys", type(diag.Shots) == "number" and type(diag.Rejected) == "number" and type(diag.DamageDealt) == "number" and type(diag.Scans) == "number")
check("shape: scan 0.2", Core.SCAN == 0.2, Core.SCAN)

--.. Priority
check("priority carry", Core.Priority({Carrying = true, Grappling = true}) == 3)
check("priority grapple", Core.Priority({Grappling = true}) == 2)
check("priority plain", Core.Priority({}) == 1 and Core.Priority(nil) == 1 and Core.Priority({Carrying = "yes"}) == 1)

--.. XZ range
do
	local up = Z("up", 1, V(10, 60, 0))
	check("xz: 50 studs up still in range", Core.ChooseTarget(V(0, 10, 0), 11, {up}) == up)
	check("xz: boundary included", Core.ChooseTarget(V(0, 0, 0), 10, {up}) == up)
	check("xz: out of flat range", Core.ChooseTarget(V(0, 0, 0), 11, {Z("far", 1, V(0, 0, 12))}) == nil)
	check("xz: diagonal", Core.ChooseTarget(V(0, 0, 0), 5, {Z("d", 1, V(3, 100, 4))}) ~= nil and Core.ChooseTarget(V(0, 0, 0), 4.9, {Z("d", 1, V(3, 100, 4))}) == nil)
	check("xz: bad inputs", Core.ChooseTarget(nil, 10, {up}) == nil and Core.ChooseTarget(V(0, 0, 0), NaN, {up}) == nil and Core.ChooseTarget(V(0, 0, 0), 10, nil) == nil)
end

--.. priority Carry > Grappling > nearest
do
	local near = Z("near", 1, V(2, 3, 0))
	local grap = Z("grap", 1, V(8, 3, 0), {Grappling = true})
	local carry = Z("carry", 1, V(10, 3, 0), {Carrying = true})
	local carryFar = Z("carryFar", 1, V(30, 3, 0), {Carrying = true})
	local p = V(0, 0, 0)
	check("prio: carry wins", Core.ChooseTarget(p, 26, {near, grap, carry, carryFar}) == carry)
	check("prio: grapple next", Core.ChooseTarget(p, 26, {near, grap, carryFar}) == grap)
	check("prio: nearest last", Core.ChooseTarget(p, 26, {Z("mid", 1, V(6, 3, 0)), near, carryFar}) == near)
	check("prio: out-of-range carrier ignored", Core.ChooseTarget(p, 26, {carryFar}) == nil)
end

--.. keep the current target unless a higher-priority one is in range
do
	local p = V(0, 0, 0)
	local far = Z("far", 1, V(9, 3, 0))
	local near = Z("near", 1, V(2, 3, 0))
	local grap = Z("grap", 1, V(8, 3, 0), {Grappling = true})
	local grapNear = Z("grapNear", 1, V(3, 3, 0), {Grappling = true})
	local carry = Z("carry", 1, V(10, 3, 0), {Carrying = true})
	local carryNear = Z("carryNear", 1, V(1, 3, 0), {Carrying = true})
	check("keep: nearer plain does not steal", Core.ChooseTarget(p, 26, {near, far}, far.Model) == far)
	check("keep: grappler steals from plain", Core.ChooseTarget(p, 26, {near, far, grap}, far.Model) == grap)
	check("keep: nearer grappler does not steal", Core.ChooseTarget(p, 26, {grapNear, grap}, grap.Model) == grap)
	check("keep: carrier steals from grappler", Core.ChooseTarget(p, 26, {grap, carry}, grap.Model) == carry)
	check("keep: nearer carrier does not steal", Core.ChooseTarget(p, 26, {carryNear, carry}, carry.Model) == carry)
	local gone = {Name = "gone"}
	check("keep: vanished current -> best", Core.ChooseTarget(p, 26, {near, far}, gone) == near)
	local outside = Z("outside", 1, V(40, 3, 0))
	check("keep: current out of range -> best", Core.ChooseTarget(p, 26, {near, outside}, outside.Model) == near)
	-- across scans
	local state, log = Core.NewState(), {}
	local pets, pos = {Pet("P1", 1)}, {P1 = p}
	Scan(state, 0, pets, {far}, pos, log)
	Scan(state, 0.2, pets, {far, near}, pos, log)
	check("keep: RunScan keeps target over scans", state.Target.P1 == far.Model, state.Target.P1 and state.Target.P1.Name)
	Scan(state, 0.4, pets, {far, near, grap}, pos, log)
	check("keep: RunScan switches to grappler", state.Target.P1 == grap.Model)
end

--.. owner filter
do
	local state, log = Core.NewState(), {}
	local z1 = Z("own1", 1, V(5, 3, 0))
	local z2 = Z("own2-near-A", 2, V(3, 3, 0))
	local z3 = Z("own2", 2, V(105, 3, 0))
	local zNil = Z("ownerless", nil, V(1, 3, 0))
	local zStr = Z("stringOwner", "1", V(1, 3, 0))
	local zNaN = Z("nanOwner", NaN, V(1, 3, 0))
	local pets = {Pet("A", 1), Pet("B", 2)}
	Scan(state, 0, pets, {z2, zNil, zStr, zNaN, z1, z3}, {A = V(0, 0, 0), B = V(100, 0, 0)}, log)
	local hitBy = {}
	for _, shot in ipairs(log) do hitBy[shot.Model.Name] = (hitBy[shot.Model.Name] or 0) + 1 end
	check("owner: two shots", #log == 2, #log)
	check("owner: A shot its own zombie", hitBy.own1 == 1)
	check("owner: B shot its own zombie", hitBy.own2 == 1)
	check("owner: neighbour / ownerless untouched", hitBy["own2-near-A"] == nil and hitBy.ownerless == nil and hitBy.stringOwner == nil and hitBy.nanOwner == nil)
	check("owner: A has no candidates of owner 2", state.Target.A == z1.Model)
end

--.. NormalizeInfos
do
	local good = Z("good", 1, V(1, 2, 3))
	local list = Core.NormalizeInfos({good, Z("dead", 1, V(0, 0, 0), {Health = 0}), Z("nanpos", 1, V(NaN, 0, 0)), {Owner = 1, Position = V(0, 0, 0)}, "junk", Z("nopos", 1, nil)})
	check("normalize: only the valid info kept", #list == 1 and list[1] == good, #list)
	check("normalize: non-table raw", #Core.NormalizeInfos(nil) == 0 and #Core.NormalizeInfos(5) == 0)
	check("normalize: isModel filter", #Core.NormalizeInfos({good}, function() return false end) == 0)
end

--.. fallback TargetInfos from Zombies() + attributes
do
	local function M_(name, attrs, pos, hp) return {Name = name, attrs = attrs, pos = pos, hp = hp} end
	local read = {
		Attribute = function(m, k) return m.attrs[k] end,
		Position = function(m) return m.pos end,
		Health = function(m) return m.hp, 100 end,
	}
	local carrier = M_("carrier", {Owner = 1, State = "Carry"}, V(10, 3, 0), 50)
	local seeker = M_("seeker", {Owner = 1, State = "Seek"}, V(2, 3, 0), 50)
	local cutscene = M_("cutscene", {Owner = 1}, V(4, 3, 0), 50)
	local models = {
		carrier, seeker, cutscene,
		M_("dead", {Owner = 1, State = "Seek", Dead = true}, V(1, 3, 0), 50),
		M_("shaded", {Owner = 1, State = "Seek", Shaded = true}, V(1, 3, 0), 50),
		M_("underground", {Owner = 1, State = "Seek", Underground = true}, V(1, 3, 0), 50),
		M_("noOwner", {State = "Seek"}, V(1, 3, 0), 50),
		M_("strOwner", {Owner = "1"}, V(1, 3, 0), 50),
		M_("noPos", {Owner = 1}, nil, 50),
		M_("zeroHp", {Owner = 1}, V(1, 3, 0), 0),
	}
	local infos = Core.FallbackInfos(models, read)
	local byName = {}
	for _, info in ipairs(infos) do byName[info.Model.Name] = info end
	check("fallback: 3 usable zombies", #infos == 3, #infos)
	check("fallback: carrier Carrying", byName.carrier and byName.carrier.Carrying == true and byName.carrier.Grappling == false and byName.carrier.State == "Carry")
	check("fallback: seeker not carrying", byName.seeker and byName.seeker.Carrying == false and byName.seeker.Owner == 1)
	check("fallback: nil State kept", byName.cutscene and byName.cutscene.State == nil and byName.cutscene.Carrying == false)
	check("fallback: health read", byName.seeker and byName.seeker.Health == 50 and byName.seeker.MaxHealth == 100)
	check("fallback: carrier prioritised", Core.ChooseTarget(V(0, 0, 0), 26, Core.NormalizeInfos(infos)) == byName.carrier)
	check("fallback: bad args", #Core.FallbackInfos(nil, read) == 0 and #Core.FallbackInfos(models, nil) == 0)
end

--.. NextShot maths + a 3 s hitch
do
	check("nextshot: on-time", math.abs(Core.NextShot(0, 0, 2.5, 0.2) - 2.5) < 1e-9)
	check("nextshot: late scan keeps cadence", math.abs(Core.NextShot(2.5, 2.6, 2.5, 0.2) - 5.0) < 1e-9)
	check("nextshot: hitch no burst", math.abs(Core.NextShot(5.0, 8.0, 2.5, 0.2) - 10.3) < 1e-9)
	check("nextshot: bad prev", math.abs(Core.NextShot(NaN, 4, 2.5, 0.2) - 6.5) < 1e-9)
	local acc, due = Core.StepAccumulator(0.1, 3.0, 0.2)
	check("hitch: one scan due, accumulator reset", due == true and acc == 0, acc)
	local acc2, due2 = Core.StepAccumulator(acc, 1 / 60, 0.2)
	check("hitch: no queued second scan", due2 == false and acc2 < 0.2)
	local acc3, due3 = Core.StepAccumulator(0.19, 0.02, 0.2)
	check("accumulator: remainder kept", due3 == true and math.abs(acc3 - 0.01) < 1e-9, acc3)
end

--.. deadline: no burst after a 3 s hitch (full scans)
do
	local state, log = Core.NewState(), {}
	local z = Z("z", 1, V(5, 3, 0))
	local pets, pos = {Pet("P", 1)}, {P = V(0, 0, 0)}
	for k = 0, 50 do Scan(state, k * 0.2, pets, {z}, pos, log) end -- 0 .. 10 s
	local before = #log
	for k = 0, 15 do Scan(state, 13 + k * 0.2, pets, {z}, pos, log) end -- hitch 10 -> 13, then 13 .. 16 s
	local inWindow, firstAfter = 0, nil
	for i = before + 1, #log do
		local t = log[i].T
		if t < 15.3 - 1e-9 then inWindow += 1 elseif not firstAfter then firstAfter = t end
	end
	check("hitch scans: exactly one shot at the hitch end", inWindow == 1 and log[before + 1].T == 13, inWindow)
	check("hitch scans: next shot >= interval - scan later", firstAfter ~= nil and firstAfter >= 15.3 - 1e-9, firstAfter)
	check("hitch scans: 5 shots in the first 10 s", before == 5, before) -- 0, 2.6, 5.0, 7.6, 10.0
end

--.. cadence over 100 s of jittered 0.2 s scans at interval 2.5 -> 40 +- 1 shots
do
	local rng = Random.new(20260922)
	local state, log = Core.NewState(), {}
	local z = Z("z", 1, V(5, 3, 0))
	local pets, pos = {Pet("P", 1)}, {P = V(0, 0, 0)}
	local t, acc, scans = 0, 0, 0
	while t < 100 do
		local dt = (1 / 60) * rng:NextNumber(0.6, 1.6) -- frame jitter
		t += dt
		local due
		acc, due = Core.StepAccumulator(acc, dt, 0.2)
		if due and t < 100 then
			scans += 1
			Scan(state, t, pets, {z}, pos, log)
		end
	end
	local minGap = math.huge
	for i = 2, #log do minGap = math.min(minGap, log[i].T - log[i - 1].T) end
	check("cadence: 40 +- 1 shots in 100 s", math.abs(#log - 40) <= 1, #log)
	check("cadence: ~500 scans", scans >= 480 and scans <= 505, scans)
	check("cadence: never two shots closer than interval - scan", minGap >= 2.3 - 1e-9, minGap)
	local mean = (log[#log].T - log[1].T) / (#log - 1)
	check("cadence: mean gap ~ nominal", mean >= 2.5 - 1e-9 and mean <= 2.56, mean)
end

--.. a new target fires on the first scan in range
do
	local state, log = Core.NewState(), {}
	local pets, pos = {Pet("P", 1)}, {P = V(0, 0, 0)}
	for k = 0, 25 do Scan(state, k * 0.2, pets, {}, pos, log) end -- idle 0 .. 5 s
	Scan(state, 5.2, pets, {Z("approach", 1, V(40, 3, 0))}, pos, log) -- still out of range
	check("new target: none out of range", #log == 0)
	Scan(state, 5.4, pets, {Z("approach", 1, V(20, 3, 0))}, pos, log)
	check("new target: fires on the first scan in range", #log == 1 and log[1].T == 5.4, #log)
	-- a newly active pet with a target in range fires at once
	local state2, log2 = Core.NewState(), {}
	Scan(state2, 3.0, {Pet("Q", 1)}, {Z("z", 1, V(5, 3, 0))}, {Q = V(0, 0, 0)}, log2)
	check("new pet: fires on its first scan", #log2 == 1 and log2[1].T == 3.0)
end

--.. one shot consumes one cooldown: a new target after a gap does not bypass it
do
	local state, log = Core.NewState(), {}
	local pets, pos = {Pet("P", 1)}, {P = V(0, 0, 0)}
	Scan(state, 0, pets, {Z("a", 1, V(5, 3, 0))}, pos, log)
	Scan(state, 0.2, pets, {}, pos, log)
	Scan(state, 0.4, pets, {}, pos, log)
	for k = 4, 12 do Scan(state, k * 0.2, pets, {Z("b", 1, V(6, 3, 0))}, pos, log) end -- 0.8 .. 2.4
	check("cooldown: no second shot before the interval", #log == 1, #log)
	Scan(state, 2.6, pets, {Z("b", 1, V(6, 3, 0))}, pos, log)
	check("cooldown: next shot after the interval", #log == 2 and log[2].Model.Name == "b")
end

--.. rejects NaN / non-finite / non-positive damage (cooldown still consumed, Damage never called)
do
	for _, bad in ipairs({NaN, math.huge, -3, 0, "5"}) do
		local state, log = Core.NewState(), {}
		local pets, pos = {Pet("P", 1, {ShotDamage = bad})}, {P = V(0, 0, 0)}
		for k = 0, 25 do Scan(state, k * 0.2, pets, {Z("z", 1, V(5, 3, 0))}, pos, log) end -- 0 .. 5 s
		check("bad damage " .. tostring(bad) .. ": no Damage call", #log == 0, #log)
		check("bad damage " .. tostring(bad) .. ": rejected per cooldown", state.Diag.Rejected >= 2 and state.Diag.Rejected <= 3, state.Diag.Rejected)
		check("bad damage " .. tostring(bad) .. ": no shots", state.Diag.Shots == 0 and state.Diag.DamageDealt == 0)
	end
end

--.. invalid range / interval / Valid=false: pet holds fire, counted once
do
	for label, over in pairs({range = {Range = NaN}, interval = {ShotInterval = 0}, invalid = {Valid = false}, infinite = {ShotInterval = math.huge}}) do
		local state, log = Core.NewState(), {}
		local pets, pos = {Pet("P", 1, over)}, {P = V(0, 0, 0)}
		for k = 0, 5 do Scan(state, k * 0.2, pets, {Z("z", 1, V(5, 3, 0))}, pos, log) end
		check("invalid stats " .. label .. ": no fire", #log == 0 and state.Diag.InvalidStats == 1, state.Diag.InvalidStats)
	end
	local state, log = Core.NewState(), {}
	Scan(state, 0, {{PetId = "P", UserId = 1}}, {Z("z", 1, V(5, 3, 0))}, {P = V(0, 0, 0)}, log)
	check("invalid stats: missing Stats", #log == 0 and state.Diag.InvalidStats == 1)
	local state2, log2 = Core.NewState(), {}
	Scan(state2, 0, {Pet("", 1), Pet(("x"):rep(65), 1), "junk", Pet("P", 1)}, {Z("z", 1, V(5, 3, 0))}, {P = V(0, 0, 0)}, log2)
	check("invalid ids skipped, valid pet fires", #log2 == 1)
	local state3, log3 = Core.NewState(), {}
	Scan(state3, 0, {Pet("P", 1)}, {Z("z", 1, V(5, 3, 0))}, {}, log3)
	check("no logical position: no fire", #log3 == 0 and state3.Target.P == nil)
end

--.. a zombie killed earlier in the same scan is not shot again
do
	local state, log = Core.NewState(), {}
	local z = Z("weak", 1, V(5, 3, 0))
	local pets, pos = {Pet("A", 1), Pet("B", 1)}, {A = V(0, 0, 0), B = V(1, 0, 0)}
	Scan(state, 0, pets, {z}, pos, log, function() return true, 0 end)
	check("kill: second pet does not shoot the corpse", #log == 1, #log)
	local state2, log2 = Core.NewState(), {}
	Scan(state2, 0, pets, {Z("weak", 1, V(5, 3, 0)), Z("other", 1, V(9, 3, 0))}, pos, log2, function(model) if model.Name == "weak" then return true, 0 end return true, 20 end)
	check("kill: second pet takes the next zombie", #log2 == 2 and log2[2].Model.Name == "other")
end

--.. forget pets that are no longer active
do
	local state, log = Core.NewState(), {}
	local pos = {A = V(0, 0, 0), B = V(0, 0, 0)}
	Scan(state, 0, {Pet("A", 1), Pet("B", 1)}, {Z("z", 1, V(5, 3, 0))}, pos, log)
	Scan(state, 0.2, {Pet("B", 1)}, {Z("z", 1, V(5, 3, 0))}, pos, log)
	check("forget: A dropped", state.NextShot.A == nil and state.Target.A == nil)
	check("forget: B kept", state.NextShot.B ~= nil and state.Target.B ~= nil)
	Scan(state, 0.4, {}, {}, pos, log)
	check("forget: all dropped", next(state.NextShot) == nil and next(state.Target) == nil)
end

--.. effects only on accepted shots; Shot payload
do
	local state, log, emits = Core.NewState(), {}, {}
	local z = Z("z", 7, V(5, 3, 2))
	local pets, pos = {Pet("P", 7, {Rarity = "Rare", ShotDamage = 8})}, {P = V(1, 10, 1)}
	Scan(state, 0, pets, {z}, pos, log, function() return false, 0 end, emits)
	check("fx: refused shot emits nothing", #emits == 0 and state.Diag.Rejected == 1 and state.Diag.Shots == 0)
	check("fx: refused shot still consumed the cooldown", state.NextShot.P == 2.5, state.NextShot.P)
	Scan(state, 2.6, pets, {z}, pos, log, function() return true, 30 end, emits)
	local e = emits[1]
	check("fx: accepted shot emits once", #emits == 1 and state.Diag.Shots == 1 and state.Diag.DamageDealt == 8)
	check("fx: Shot payload", e and e.Event.Kind == "Shot" and e.Event.PetId == "P" and e.Event.Zombie == z.Model
		and e.Event.Rarity == "Rare" and e.Event.Damage == 8 and e.Event.To == z.Position
		and (e.Event.From - V(1, 11.5, 1)).Magnitude < 1e-6)
	check("fx: owner + position", e and e.Owner == 7 and e.Position == e.Event.From)
	check("fx: no T/Id stamped here (bus stamps them)", e and e.Event.T == nil and e.Event.Id == nil)
end

--.. ZombieAPI.Damage is invoked with exactly three arguments
do
	local count, args
	local fake = {Invoke = function(_, ...) count = select("#", ...); args = {...}; return true, 42 end}
	local marker = {Name = "zombie"}
	local accepted, health, err = Core.CallDamage(fake, marker, 5)
	check("damage call: exactly 3 args", count == 3, count)
	check("damage call: model, amount, \"Pet\"", args[1] == marker and args[2] == 5 and args[3] == "Pet")
	check("damage call: result", accepted == true and health == 42 and err == nil)
	local broken = {Invoke = function() error("boom") end}
	local ok2, _, err2 = Core.CallDamage(broken, marker, 5)
	check("damage call: error caught", ok2 == false and type(err2) == "string")
	local refused = {Invoke = function() return false, 0 end}
	check("damage call: refusal", Core.CallDamage(refused, marker, 5) == false)
end

--.. an unread pet list keeps every deadline (review fix 2026-09-22: no second shot after a failed read)
do
	local list = {Pet("P", 1)}
	local pets, err = Core.ReadPets({GetActivePets = function() return list end})
	check("readpets: table passed through", pets == list and err == nil)
	local p2, e2 = Core.ReadPets({GetActivePets = function() error("cache rebuild") end})
	check("readpets: error -> nil + message", p2 == nil and type(e2) == "string" and e2:find("cache rebuild") ~= nil, e2)
	local p3, e3 = Core.ReadPets({GetActivePets = function() return nil end})
	check("readpets: nil result -> nil", p3 == nil and type(e3) == "string", e3)
	local p4 = Core.ReadPets({GetActivePets = function() return "junk" end})
	check("readpets: string result -> nil", p4 == nil)
	check("readpets: missing service / function", Core.ReadPets(nil) == nil and Core.ReadPets({}) == nil)
	local p5 = Core.ReadPets({GetActivePets = function() return {} end})
	check("readpets: empty list is a real read", type(p5) == "table" and #p5 == 0)

	local state, log = Core.NewState(), {}
	local pets6 = {Pet("A", 1), Pet("B", 1)}
	local pos = {A = V(0, 0, 0), B = V(0, 0, 0)}
	local z = Z("z", 1, V(5, 3, 0))
	Scan(state, 0, pets6, {z}, pos, log)
	check("unread: both pets fired", #log == 2, #log)
	local scansBefore = state.Diag.Scans
	local fired = Scan(state, 0.2, nil, {z}, pos, log) -- the failed read
	check("unread: no fire, nothing pruned", fired == 0 and #log == 2 and state.NextShot.A == 2.5 and state.NextShot.B == 2.5
		and state.Target.A == z.Model and state.Target.B == z.Model, state.NextShot.A)
	check("unread: not counted as a scan", state.Diag.Scans == scansBefore)
	Scan(state, 0.4, pets6, {z}, pos, log) -- the list reads again
	check("unread: no burst on the next good scan", #log == 2, #log)
	for k = 3, 12 do Scan(state, k * 0.2, pets6, {z}, pos, log) end -- 0.6 .. 2.4
	check("unread: still cooling down", #log == 2, #log)
	Scan(state, 2.6, pets6, {z}, pos, log)
	check("unread: next shots at the interval", #log == 4 and log[3].T == 2.6 and log[4].T == 2.6, #log)
	-- the invalid-stats marker survives an unread list too (InvalidStats stays counted once)
	local state2, log2 = Core.NewState(), {}
	local bad = {Pet("X", 1, {Range = NaN})}
	Scan(state2, 0, bad, {z}, {X = V(0, 0, 0)}, log2)
	Scan(state2, 0.2, "junk", {z}, {X = V(0, 0, 0)}, log2)
	Scan(state2, 0.4, bad, {z}, {X = V(0, 0, 0)}, log2)
	check("unread: invalid marker kept", state2.Invalid.X == true and state2.Diag.InvalidStats == 1, state2.Diag.InvalidStats)
end

return ("WP-COMBAT core: PASS %d / FAIL %d%s"):format(pass, fail, fail > 0 and (": " .. table.concat(failures, "; ")) or "")
