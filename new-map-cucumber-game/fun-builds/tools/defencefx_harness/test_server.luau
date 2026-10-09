--!nocheck
-- Offline run of DefenceService (fun-builds package DefenceFX): the LIVE and the PATCHED script each defend the
-- same scripted raid for 11 s (every defence kind, static zombies). Checks the DefenceFX events the patch sends
-- and that every Damage / Slow / Stun call is identical to the live script's (no gameplay number changed).
--   py gen.py; luau test_server.luau
local M = require("./mocks")
local V, CF, new = M.Vector3.new, M.CFrame, M.new

local fails, passes = 0, 0
local function check(cond, msg)
	if cond then passes += 1 else fails += 1 print("FAIL " .. msg) end
end

local TICKS_PER_S = 60
local RUN_FOR = 11

local function run(modName, opts)
	opts = opts or {}
	M.reset()
	math.randomseed(7)
	local warns, log, puffs = {}, {}, {}
	local workspace = new("Workspace") workspace.Name = "Workspace"
	local terrain = new("Terrain", workspace) terrain.Name = "Terrain"
	workspace.Terrain = terrain
	local RS = new("Folder") RS.Name = "ReplicatedStorage"
	local Modules = new("Folder", RS) Modules.Name = "Modules"
	local soundMS = new("ModuleScript", Modules) soundMS.Name = "SoundController"
	local catMS = new("ModuleScript", Modules) catMS.Name = "ZombieCatalog"
	if not opts.noRemotes then local r = new("Folder", RS) r.Name = "Remotes" end
	local PB = new("Folder", RS) PB.Name = "PlaceableBuilds"
	local PBD = new("Folder", PB) PBD.Name = "Defences"
	local SS = new("Folder") SS.Name = "ServerStorage"
	local API = new("Folder", SS) API.Name = "ZombieAPI"
	local Builds = new("Folder", SS) Builds.Name = "Builds"
	local Sources = new("Folder", Builds) Sources.Name = "Defences"

	local zombies = {}
	local function bindable(name, fn) local b = new("BindableFunction", API) b.Name = name b.OnInvoke = fn end
	bindable("Damage", function(z, amount, source) table.insert(log, ("%.4f D %s %s %s"):format(M.clock, z.Name, tostring(amount), source)) return true end)
	bindable("Zombies", function() return table.clone(zombies) end)
	bindable("Slow", function(z, s) table.insert(log, ("%.4f S %s %s"):format(M.clock, z.Name, tostring(s))) return true end)
	bindable("Stun", function(z, s) table.insert(log, ("%.4f T %s %s"):format(M.clock, z.Name, tostring(s))) return true end)

	local RunService = {Heartbeat = M.Signal()}
	local tags = {}
	local CS = {}
	function CS.GetTagged(_, tag) local out = {} for _, i in ipairs(tags[tag] or {}) do table.insert(out, i) end return out end
	function CS.GetInstanceAddedSignal() return M.Signal() end
	function CS.GetInstanceRemovedSignal() return M.Signal() end
	local Debris = {}
	function Debris.AddItem(_, inst, t)
		if inst.ClassName == "Attachment" and inst.Parent == terrain then table.insert(puffs, inst.WorldPosition) end
		M.task.delay(t, function() inst:Destroy() end)
	end
	--.. players: A stands at the west group of defences (freeze / tesla / minigun), B at the east group (laser / spikes /
	--.. turret / catapult / mortar), C far away, D without a character (respawning). With FX_RANGE 280 every hit is near
	--.. exactly one of A / B, so A's + B's batches together are the whole event stream.
	local function playerAt(name, at)
		local plr = new("Player") plr.Name = name
		if at then
			local ch = new("Model") ch.Name = name
			local root = new("Part", ch) root.Name = "HumanoidRootPart" root.CFrame = CF.new(at)
			ch.PrimaryPart = root
			plr.Character = ch
		end
		return plr
	end
	local plist = {playerAt("A", V(0, 3, 0)), playerAt("B", V(560, 3, 0)), playerAt("C", V(0, 3, 5000)), playerAt("D", nil)}
	local Players = {}
	function Players.GetPlayers() return table.clone(plist) end
	local game = {}
	function game.GetService(_, name)
		return ({ReplicatedStorage = RS, ServerStorage = SS, CollectionService = CS, RunService = RunService, Debris = Debris, Players = Players})[name] or error("service " .. name)
	end
	local env = {
		game = game, workspace = workspace, Instance = M.Instance, Vector3 = M.Vector3, CFrame = M.CFrame, Color3 = M.Color3,
		Vector2 = M.Vector2, NumberRange = M.NumberRange, NumberSequence = M.NumberSequence, NumberSequenceKeypoint = M.NumberSequenceKeypoint,
		ColorSequence = M.ColorSequence, Enum = M.Enum, typeof = M.typeof, task = M.task, print = function() end,
		warn = function(...) table.insert(warns, table.concat({...}, " ")) end,
		os = {clock = function() return M.clock end}, script = new("Script"), TweenInfo = M.TweenInfo, RaycastParams = {new = function() return {} end},
		require = function(ms)
			if ms == soundMS then return {PlayFXAt = function() end} end
			if ms == catMS then return {API = "ZombieAPI"} end
			error("require " .. tostring(ms))
		end,
	}

	--.. a placed defence: parts {name = {pos, size}} at world `at` (authored origin = floor centre), source pivots for set 2
	local function place(key, at, parts, pivots, attrs)
		local source = new("Model", Sources) source.Name = key
		local lo, hi = V(-3, 0, -3), V(3, 8, 3)
		local centre = (lo + hi) * 0.5
		local sb = new("Part", source) sb.Name = "Box" sb.Size = hi - lo sb.CFrame = CF.new(centre)
		for k, v in pairs(pivots or {}) do source:SetAttribute("Pivot_" .. k, v) end
		local model = new("Model")
		model.Name = key
		model:SetAttribute("BuildKey", key)
		for k, v in pairs(attrs or {}) do model:SetAttribute(k, v) end
		local hb = new("Part", model) hb.Name = "Hitbox" hb.Size = hi - lo hb.CFrame = CF.new(at + centre)
		model.PrimaryPart = hb
		for name, spec in pairs(parts or {}) do
			local p = new("Part", model) p.Name = name p.CFrame = CF.new(at + spec[1]) p.Size = spec[2] or V(1, 1, 1)
			p.Color = M.Color3.fromRGB(77, 210, 255)
		end
		model.Parent = workspace
		tags.PlacedBuild = tags.PlacedBuild or {}
		table.insert(tags.PlacedBuild, model)
		return model
	end
	local function zombie(name, at)
		local z = new("Model", workspace) z.Name = name
		local root = new("Part", z) root.Name = "HumanoidRootPart" root.CFrame = CF.new(at) root.AssemblyLinearVelocity = V(0, 0, 0)
		new("Humanoid", z)
		table.insert(zombies, z)
		return z
	end

	place("FreezeTower", V(0, 0, 0), {Orb = {V(0, 9.9, 0), V(2.2, 2.2, 2.2)}}, {OrbCentre = V(0, 9.9, 0)}, {FreezePulse = true})
	zombie("F1", V(5, 3, 0)) zombie("F2", V(-6, 3, 4)) zombie("F3", V(0, 3, -10))
	place("TeslaCoil", V(100, 0, 0), {Orb = {V(0, 9, 0)}}, {OrbCentre = V(0, 9, 0), ProngTip1 = V(0.85, 9.59, -0.85)})
	zombie("T1", V(110, 3, 0)) zombie("T2", V(118, 3, 0)) zombie("T3", V(126, 3, 0))
	place("Minigun", V(200, 0, 0), {HeadReceiver = {V(0.4, 4.1, 0.55)}, SpinBarrels = {V(0.45, 4.1, -2.35)}}, {BarrelAxis = V(0.45, 4.1, 0), MuzzleTip = V(0.45, 4.1, -3.8)})
	zombie("M1", V(215, 3, 0))
	place("LaserGate", V(300, 0, 0), {Beam1 = {V(0, 2, 0)}, Beam2 = {V(0, 3, 0)}, Beam3 = {V(0, 4, 0)}, Beam4 = {V(0, 5, 0)}}, {})
	zombie("L1", V(300, 3, 0))
	place("SpikeTrap", V(400, 0, 0), {BasePlate = {V(0, 0.225, 0), V(8, 0.45, 8)}, Spikes = {V(0, 0.6, 0)}})
	zombie("S1", V(401, 3, 1))
	place("Turret", V(500, 0, 0), {BasePlinth = {V(0, 0.59, 0)}, HeadTrunnion = {V(0, 4.8, 0)}, HeadHousing = {V(0, 2.7, 0.7)}, BarrelMuzzleGlow = {V(0, 4.8, -3.84)}, BarrelTubes = {V(0, 4.8, -1.25)}})
	zombie("U1", V(500, 3, -20))
	place("Catapult", V(600, 0, 0), {Wheels = {V(0, 0.96, -0.275)}, ArmBeam = {V(0, 3, 1.3)}, ArmBucket = {V(0, 3.5, 3)}})
	zombie("C1", V(600, 3, -30))
	place("Mortar", V(700, 0, 0), {MountBase = {V(0, 2, 0)}, TubeBody = {V(0, 5, -1)}}, {PitchPivot = V(0, 4, 0), MuzzleTip = V(0, 6.87, -2.01)})
	zombie("R1", V(700, 3, -40)) zombie("R2", V(703, 3, -42))
	if opts.horde then for i = 1, 60 do zombie("H" .. i, V((i % 8) * 2 - 8, 3, math.floor(i / 8) * 2 - 8)) end end

	require("./mod_" .. modName)(env)
	local dt = 1 / TICKS_PER_S
	for _ = 1, math.floor((opts.runFor or RUN_FOR) * TICKS_PER_S) do
		M.clock += dt
		M.runDue()
		RunService.Heartbeat:Fire(dt)
	end
	local batches = {}
	for _, f in ipairs(M.fired) do
		if f[1] == "DefenceFX" then table.insert(batches, {Time = f[3], List = f[2][1], Player = f[4]}) end
	end
	local roots = {}
	for _, plr in ipairs(plist) do roots[plr.Name] = plr.Character and plr.Character.HumanoidRootPart.Position end
	return {log = log, warns = warns, batches = batches, puffs = puffs, roots = roots, remote = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("DefenceFX")}
end

--==================================================================== live vs patched: identical damage / slow / stun
local live = run("server_live")
local patched = run("server")
check(#live.warns == 0, "live run: no warnings (" .. table.concat(live.warns, " | ") .. ")")
check(#patched.warns == 0, "patched run: no warnings (" .. table.concat(patched.warns, " | ") .. ")")
check(#live.log > 100, "the raid dealt damage (" .. #live.log .. " calls)")
--.. pairs(Defences) visits the defences in a different order each run: compare each tick's calls as a sorted set
table.sort(live.log)
table.sort(patched.log)
local same = #live.log == #patched.log
local firstDiff
for i = 1, math.max(#live.log, #patched.log) do
	if live.log[i] ~= patched.log[i] then same = false firstDiff = firstDiff or i end
end
check(same, "every Damage / Slow / Stun call identical" .. (firstDiff and (" (first diff #" .. firstDiff .. ": " .. tostring(live.log[firstDiff]) .. " vs " .. tostring(patched.log[firstDiff]) .. ")") or ""))
local sources = {}
for _, line in ipairs(patched.log) do local s = line:match(" D %S+ %S+ (%a+)$") if s then sources[s] = true end end
for _, s in ipairs({"Frost", "Tesla", "Minigun", "Laser", "Spikes", "Turret", "Catapult", "Mortar"}) do check(sources[s], "damage source " .. s .. " fired in the run") end
check(live.remote == nil and patched.remote ~= nil and patched.remote.ClassName == "RemoteEvent", "patched script creates Remotes.DefenceFX")

--==================================================================== the FX events
local byKind, perZombie, maxBatch = {}, {}, 0
local tBatch = {}
for _, b in ipairs(patched.batches) do
	local batch = b.List
	maxBatch = math.max(maxBatch, #batch)
	for _, ev in ipairs(batch) do
		byKind[ev.k] = byKind[ev.k] or {}
		table.insert(byKind[ev.k], ev)
		local key = ev.k .. ":" .. (ev.z and ev.z.Name or "?")
		perZombie[key] = perZombie[key] or {}
		table.insert(perZombie[key], b.Time)
	end
end
check(maxBatch <= 40, "batches <= 40 events (" .. maxBatch .. ")")
--.. per player: FireClient only (never FireAllClients), one flush per tick at most, only hits within FX_RANGE 280
local perPlayer, allTargeted, farOk = {}, true, true
for _, b in ipairs(patched.batches) do
	if not b.Player then allTargeted = false else
		local name = b.Player.Name
		perPlayer[name] = (perPlayer[name] or 0) + 1
		for _, ev in ipairs(b.List) do
			if (ev.p - patched.roots[name]).Magnitude > 280 + 1e-6 then farOk = false end
		end
	end
end
check(allTargeted, "every batch goes out with FireClient(player, ...)")
check(farOk, "a player only gets the hits within 280 studs of their character")
check((perPlayer.A or 0) > 50 and (perPlayer.B or 0) > 50, ("both defended players get their own hits (A %d, B %d flushes)"):format(perPlayer.A or 0, perPlayer.B or 0))
check((perPlayer.A or 0) <= RUN_FOR / 0.05 + 2 and (perPlayer.B or 0) <= RUN_FOR / 0.05 + 2, "at most one flush per 0.05 s tick per player")
check(perPlayer.C == nil, "a player far from every defence gets nothing (" .. tostring(perPlayer.C) .. ")")
check(perPlayer.D == nil, "a player without a character gets nothing")
do -- A's and B's streams do not overlap here (every hit is near exactly one of them)
	local kindsA, kindsB = {}, {}
	for _, b in ipairs(patched.batches) do
		for _, ev in ipairs(b.List) do
			if b.Player.Name == "A" then kindsA[ev.k] = true elseif b.Player.Name == "B" then kindsB[ev.k] = true end
		end
	end
	check(kindsA.Frost and kindsA.Tesla and kindsA.Minigun and not kindsA.Laser and not kindsA.Mortar, "A (west) gets frost / tesla / minigun, not the east's hits")
	check(kindsB.Laser and kindsB.Spikes and kindsB.Turret and kindsB.Catapult and kindsB.Mortar and not kindsB.Frost, "B (east) gets laser / spikes / turret / catapult / mortar, not the west's")
end
for kind, list in pairs(byKind) do
	local ok = true
	for _, ev in ipairs(list) do
		if M.typeof(ev.p) ~= "Vector3" or M.typeof(ev.z) ~= "Instance" then ok = false end
	end
	check(ok, kind .. " events carry z + p")
end
--.. frost: every chill tick per zombie with slow, one pulse at ~10 s with stun 1.5
local frost = byKind.Frost or {}
local fCount, pulses = {}, {}
for _, ev in ipairs(frost) do
	fCount[ev.z.Name] = (fCount[ev.z.Name] or 0) + 1
	check(ev.x and ev.x.slow == true, "frost event has x.slow")
	if ev.x and ev.x.pulse then table.insert(pulses, ev) check(ev.x.stun == 1.5, "pulse stun = FROST.PulseStun") end
end
for _, n in ipairs({"F1", "F2", "F3"}) do check((fCount[n] or 0) >= 20 and (fCount[n] or 0) <= 23, "frost events for " .. n .. " ~ every 0.5 s (" .. tostring(fCount[n]) .. ")") end
check(#pulses == 3, "one pulse event per zombie in the aura (" .. #pulses .. ")")
local stuns = 0
for _, line in ipairs(patched.log) do if line:find(" T ") then stuns += 1 end end
check(stuns == 3, "the pulse still stuns 3 zombies (" .. stuns .. ")")
--.. tesla: one event per hop, hop numbers 0, 1, 2 on T1, T2, T3
local hopsOk, zaps = true, 0
for _, ev in ipairs(byKind.Tesla or {}) do
	local want = ({T1 = 0, T2 = 1, T3 = 2})[ev.z.Name]
	if ev.x.hop ~= want then hopsOk = false end
	if ev.x.hop == 0 then zaps += 1 end
end
check(hopsOk and zaps >= 6 and #(byKind.Tesla or {}) == zaps * 3, "tesla: an event per hop (" .. zaps .. " zaps, " .. #(byKind.Tesla or {}) .. " events)")
--.. minigun / laser throttles (in batch = tick index; ticks are 0.05 s)
local function minGap(key)
	local list = perZombie[key] or {}
	local gap = math.huge
	for i = 2, #list do gap = math.min(gap, list[i] - list[i - 1]) end
	return gap, #list
end
local mGap, mN = minGap("Minigun:M1")
check(mN >= 30 and mGap >= 0.15 - 1e-6, ("minigun: >= 0.15 s between events per zombie (%d events, min gap %.3f s)"):format(mN, mGap))
local minigunDamage = 0
for _, line in ipairs(patched.log) do if line:find(" Minigun$") then minigunDamage += 1 end end
check(minigunDamage > mN * 1.5, "minigun still fires every 0.08 s (" .. minigunDamage .. " shots)")
local lGap, lN = minGap("Laser:L1")
check(lN >= 30 and lGap >= 0.25 - 1e-6, ("laser: >= 0.25 s between events per zombie (%d events, min gap %.3f s)"):format(lN, lGap))
local fromOk = true
for _, ev in ipairs(byKind.Minigun or {}) do if M.typeof(ev.x.from) ~= "Vector3" then fromOk = false end end
for _, ev in ipairs(byKind.Turret or {}) do if M.typeof(ev.x.from) ~= "Vector3" then fromOk = false end end
check(fromOk and #(byKind.Turret or {}) >= 10, "turret / minigun events carry x.from (" .. #(byKind.Turret or {}) .. " turret)")
--.. spikes on the plate top, catapult / mortar with the burst centre
local spikeOk = #(byKind.Spikes or {}) >= 20
for _, ev in ipairs(byKind.Spikes or {}) do if math.abs(ev.p.Y - 0.45) > 1e-6 or math.abs(ev.p.X - 401) > 1e-6 then spikeOk = false end end
check(spikeOk, "spike events at the plate top under the zombie (" .. #(byKind.Spikes or {}) .. ")")
local cat = byKind.Catapult or {}
check(#cat >= 2 and M.typeof(cat[1].x.c) == "Vector3", "catapult splash events with x.c (" .. #cat .. ")")
local mortar = byKind.Mortar or {}
local r1, r2 = 0, 0
for _, ev in ipairs(mortar) do
	if ev.z.Name == "R1" then r1 += 1 elseif ev.z.Name == "R2" then r2 += 1 end
	check(M.typeof(ev.x.c) == "Vector3", "mortar event has x.c")
end
check(r1 >= 2 and r1 == r2, "mortar: every zombie in the splash gets an event (" .. r1 .. "/" .. r2 .. ")")
--.. the old server puffs on frost / laser zombies are gone (boulder / shell puffs stay)
local function puffsNear(res, points)
	local n = 0
	for _, p in ipairs(res.puffs) do
		for _, q in ipairs(points) do if (V(p.X, 0, p.Z) - V(q.X, 0, q.Z)).Magnitude < 0.5 then n += 1 end end
	end
	return n
end
local fz = {V(5, 0, 0), V(-6, 0, 4), V(0, 0, -10), V(300, 0, 0)}
check(puffsNear(live, fz) > 0, "live: frost / laser puffs on zombies (" .. puffsNear(live, fz) .. ")")
check(puffsNear(patched, fz) == 0, "patched: no frost / laser puffs on zombies (" .. puffsNear(patched, fz) .. ")")
check(#patched.puffs > 0, "patched: boulder / shell / orb puffs still there (" .. #patched.puffs .. ")")

--==================================================================== no Remotes folder yet -> made; a horde -> capped at 40
local fresh = run("server", {noRemotes = true, runFor = 1})
check(fresh.remote ~= nil, "Remotes folder + DefenceFX made when missing")
local horde = run("server", {horde = true, runFor = 4})
local hmax = 0
local fullAt = {}
for _, b in ipairs(horde.batches) do
	hmax = math.max(hmax, #b.List)
	if b.Player.Name == "A" and #b.List == 40 then fullAt[b.Time] = true end
end
check(hmax == 40, "a 60-zombie freeze tick is capped at 40 events for the player there (" .. hmax .. ")")
--.. fairness: the west's flood never pushes the east's own hits out (per-player caps, not one shared 40)
local bDuringFlood = 0
for _, b in ipairs(horde.batches) do
	if b.Player.Name == "B" and fullAt[b.Time] then bDuringFlood += #b.List end
end
local floods = 0
for _ in pairs(fullAt) do floods += 1 end
check(floods >= 4 and bDuringFlood > 0, ("B still gets its hits in the ticks A is flooded (%d floods, %d B events in them)"):format(floods, bDuringFlood))
check(#horde.warns == 0, "horde run: no warnings")

print(("DefenceService harness: %d passed, %d failed"):format(passes, fails))
if fails > 0 then error("FAILED") end
