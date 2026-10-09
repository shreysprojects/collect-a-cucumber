--[[
	WP-BUFF grapple tests (2026-09-22, review defects #3 and #4) for
	patched\ServerScriptService.ZombieRaidService.server.lua (a Script: it cannot be required in an eval).
	  #3 a grappler killed mid-hook / mid-pull (pets, or dawn with no pets) never puts a lobby-dropped cucumber back
	     into the lobby after the raid's ReturnDropped sent it home;
	  #4 a zombie that grabs a cucumber mid-pull takes the grapple's recorded HOME as its rest (never the dragged
	     pose), and a second grapple never hooks a cucumber that is already on a rope;
	  #4 residual (checker, 2026-09-22) a zombie that grabs a cucumber off another zombie's rope takes it off that
	     rope, so the stale rope's SettleGrapple (EndRaid / ZombiesWin despawn / PreCloseRaids, in any raid.Zombies
	     order) or its pull task never moves the cucumber after the carrier's RestoreCarry sent it home, and never
	     re-pulls one the carrier dropped mid-hook.
	IsWelded, HookedBy, HomeRest, Grab, RestoreCarry, ReturnDropped, Forget, Despawn, SettleGrapple, StartGrapple (its
	task included), EndRaid and PreCloseRaids are cut out of the patched source and run together on plain-table fakes
	with a hand-stepped scheduler: task.spawn / task.wait / Heartbeat:Wait are coroutines, os.clock is a fake clock,
	Instance.new returns plain tables. No Instances are created; nothing in the DataModel is touched.
	Run from an edit-peer eval:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-BUFF_grapple.lua"))()
	An optional first argument replaces the ZombieRaidService source (mutation checks on in-memory edits).
]]
local HttpService = game:GetService("HttpService")
local override = ...
local zrs = ((type(override) == "string" and override)
	or HttpService:GetAsync("http://127.0.0.1:8794/ServerScriptService.ZombieRaidService.server.lua")):gsub("\r\n", "\n")

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 12 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function Pos(src, text, from)
	return (string.find(src, text, from or 1, true))
end
local function Ordered(name, src, texts)
	local at = 1
	for i, text in ipairs(texts) do
		local s = Pos(src, text, at)
		if not s then
			Check(name, false, "missing/out of order #" .. i .. ": " .. text:sub(1, 60))
			return
		end
		at = s + #text
	end
	Check(name, true)
end
local function Cut(src, startText)
	local s = Pos(src, startText)
	if not s then return nil end
	local e = Pos(src, "\nend\n", s)
	return e and src:sub(s, e + 4) or nil
end

Check("ZombieRaidService compiles", loadstring(zrs) ~= nil)

--..1. structure (the fix sits where the flow needs it)..--
Ordered("dying / leaving zombies let go (Forget settles, Kill forgets before the raid-end check)", zrs, {
	"local SettleGrapple -- defined below", "local function Forget(entry)", "SettleGrapple(entry)", "local raid = entry.Raid",
	"function Kill(entry, source)", "Forget(entry)", "if entry.Raid then CheckRaidEnd(entry.Raid) end",
	"local function Despawn(entry, effect)", "Forget(entry)",
	"--..Grapple kinds..--", "function SettleGrapple(entry)", "local function StartGrapple(entry, target)"})
Check("SettleGrapple is not re-declared local", Pos(zrs, "local function SettleGrapple(") == nil)
Ordered("HomeRest reads the rope's home first; Grab still defaults to HomeRest", zrs, {
	"local function HookedBy(raid, model)", "local function HomeRest(raid, model)", "local hook = HookedBy(raid, model)",
	"if hook and hook.GrappleHome then return hook.GrappleHome end", "raid.Dropped[model]",
	"local function Grab(entry, model, restCFrame)", "Rest = restCFrame or HomeRest(raid, model)"})
Ordered("Grab takes the cucumber off another zombie's rope: after the shield guard and the carry rest, before the untag", zrs, {
	"local function Grab(entry, model, restCFrame)", "if TheftBlocked(entry, model) then return false end",
	"Rest = restCFrame or HomeRest(raid, model)", "local hook = HookedBy(raid, model)",
	"if hook then hook.GrappleTarget, hook.GrappleRest = nil, nil end", "CollectionService:RemoveTag(model, PLACED_TAG)"})
Ordered("StartGrapple: one rope per cucumber, refused before any mutation", zrs, {
	"local function StartGrapple(entry, target)", "if HookedBy(entry.Raid, target) then return false end", "entry.Grappling = true"})
Ordered("grapple task records its home before the rope is live", zrs, {
	"local rest = target:GetPivot()", "local home = HomeRest(entry.Raid, target)", "entry.GrappleHome = home",
	"entry.GrappleTarget, entry.GrappleRest = target, rest", "task.wait(ZombieCatalog.GRAPPLE_HOOK)"})
Ordered("tail: settled read before the clear; no pivot once settled; home once the raid is over", zrs, {
	"entry.Grappling = nil", "local settled = entry.GrappleTarget ~= target",
	"if entry.GrappleTarget == target then entry.GrappleTarget, entry.GrappleRest = nil, nil end",
	"if not Grab(entry, target, home) then target:PivotTo(rest) end",
	"elseif not settled and target.Parent and CollectionService:HasTag(target, PLACED_TAG) then",
	"target:PivotTo((raid and (raid.Over or raid.Ended)) and home or rest)"})
--.. the ZombiesWin loop lives inside Escape (too many dependencies to cut); T14 replays it in this order
Ordered("ZombiesWin loop order (replayed by T14)", zrs, {
	'raid.Result = "ZombiesWin"', "for _, other in ipairs(raid.Zombies) do", "if not other.Dead then",
	"RestoreCarry(other, true)", 'Despawn(other, "Escape")', "ReturnDropped(raid)"})

--..2. behaviour: the real functions on fakes, stepped by hand..--
local NAMES = {
	"local function IsWelded(primary, part)",
	"local function HookedBy(raid, model)",
	"local function HomeRest(raid, model)",
	"local function Grab(entry, model, restCFrame)",
	"local function RestoreCarry(entry, silent, dropAt, force)",
	"local function ReturnDropped(raid, noSnapshot)",
	"local function Forget(entry)",
	"local function Despawn(entry, effect)",
	"function SettleGrapple(entry)",
	"local function StartGrapple(entry, target)",
	"local function EndRaid(raid, reason)",
	"local function PreCloseRaids(player)",
}
local pieces, missing = {}, {}
for i, name in ipairs(NAMES) do
	pieces[i] = Cut(zrs, name)
	if not pieces[i] then table.insert(missing, name) end
end
Check("every piece cut", #missing == 0, table.concat(missing, " | "))
if #missing > 0 then
	return ("WP-BUFF grapple: PASS %d / FAIL %d: %s"):format(pass, fail, table.concat(failures, "; "))
end

local now = 0
local threads = {}
local instances = {}
local grabs = {} -- every "Grabbed" message the real Grab sends
local blockNext = false
local Zombies = {}
local Raids, DayRaids = {}, {}
local HOLDER = {Name = "Placed", Parent = "Plot"}

local env = {
	PLACED_TAG = "PlacedCucumber",
	Zombies = Zombies,
	Raids = Raids,
	DayRaids = DayRaids,
	ZombieCatalog = {GRAPPLE_HOOK = 0.85, GRAPPLE_PULL = 0.6},
	CollectionService = {
		HasTag = function(_, m, tag) return m.tagged == true and tag == "PlacedCucumber" end,
		AddTag = function(_, m, tag) if tag == "PlacedCucumber" then m.tagged = true end end,
		RemoveTag = function(_, m, tag) if tag == "PlacedCucumber" then m.tagged = false end end,
	},
	SoundController = {PlayFXAt = function() end},
	Send = function(_, msg) if msg.Kind == "Grabbed" then table.insert(grabs, msg) end end,
	print = function() end,
	HolderOf = function() return HOLDER end,
	PlotTop = function() return 0 end,
	GroundY = function() return 0 end,
	Poof = function() end,
	FadeAway = function() end,
	SyncRaidLive = function() end,
	PetBuffs = function() return nil end,
	DataSvc = function() return {GetData = function() return {} end} end,
	ServerStorage = {FindFirstChild = function() return nil end},
	TheftBlocked = function() return blockNext end,
	RunService = {Heartbeat = {Wait = function() coroutine.yield() end}},
	os = {clock = function() return now end},
	Instance = {new = function(class)
		local inst = {ClassName = class}
		function inst:Destroy() self.Destroyed = true end
		table.insert(instances, inst)
		return inst
	end},
	task = {
		spawn = function(fn, ...)
			local co = coroutine.create(fn)
			table.insert(threads, co)
			local ok, err = coroutine.resume(co, ...)
			if not ok then error("spawned task: " .. tostring(err)) end
			return co
		end,
		wait = function() coroutine.yield() end,
	},
}
local exports = {}
for _, name in ipairs(NAMES) do
	local fname = name:match("function (%w+)%(")
	table.insert(exports, fname .. " = " .. fname)
end
local chunk = "local SettleGrapple\n" .. table.concat(pieces) .. "\nreturn {" .. table.concat(exports, ", ") .. "}"
local fn, err = loadstring(chunk)
Check("pieces build together", fn ~= nil, err)
if not fn then
	return ("WP-BUFF grapple: PASS %d / FAIL %d: %s"):format(pass, fail, table.concat(failures, "; "))
end
setfenv(fn, setmetatable(env, {__index = getfenv(0)}))
local api = fn()

local HOME = CFrame.new(0, 3, 0)            -- its place on the plot
local LOBBY = CFrame.new(0, 3, 80)          -- where a pet-killed carrier dropped it
local function Near(a, b) return a and b and (a.Position - b.Position).Magnitude < 1e-3 end
local function At(c) return tostring(c.pose.Position) end

local function Raid()
	local raid = {Zombies = {}, Alive = 0, Over = false, Stolen = 0, Limit = 3, Level = 1,
		Plot = {Parent = "Plots"}, Player = {Name = "P", Parent = "Players"}}
	return raid
end
local function Cuke(pose)
	local m = {tagged = true, Parent = HOLDER, pose = pose, Name = "Cuke", moves = 0, attrs = {}}
	local p = {Name = "Primary", Parent = m, CFrame = CFrame.new(), Anchored = true, CanCollide = true, CanQuery = true, CanTouch = true, Massless = false}
	function p:IsA(class) return class == "BasePart" end
	function p:GetChildren() return {} end
	function p:FindFirstChild(n)
		for _, inst in ipairs(instances) do
			if inst.Parent == self and inst.Name == n and not inst.Destroyed then return inst end
		end
		return nil
	end
	m.PrimaryPart = p
	function m:GetPivot() return self.pose end
	function m:PivotTo(cf) self.pose = cf; self.moves += 1 end
	function m:GetAttribute(k) return self.attrs[k] end
	function m:SetAttribute(k, v) self.attrs[k] = v end
	function m:FindFirstChild() return nil end
	function m:FindFirstChildWhichIsA() return self.PrimaryPart end
	function m:GetExtentsSize() return Vector3.new(2, 4, 2) end
	function m:GetDescendants() return {self.PrimaryPart} end
	function m:Destroy() self.Destroyed = true; self.Parent = nil end
	return m
end
local function Zombie(raid, pos, name)
	local torso = {Name = "UpperTorso", Size = Vector3.new(2, 1.6, 1)}
	local model = {Name = name or "Grappler", attrs = {}}
	function model:FindFirstChild(n) return n == "UpperTorso" and torso or nil end
	function model:SetAttribute(k, v) self.attrs[k] = v end
	function model:Destroy() self.Destroyed = true end
	local e = {Model = model, Raid = raid, Dead = false, StunUntil = 0, Variety = {Name = name or "Grappler"},
		Root = {Position = pos, CFrame = CFrame.new(pos)}, Humanoid = {MoveTo = function() end}}
	table.insert(raid.Zombies, e)
	Zombies[model] = e
	raid.Alive += 1
	return e
end
local function Step(co) -- resume a parked task once
	local ok, e = coroutine.resume(co)
	if not ok then error("task: " .. tostring(e)) end
	return coroutine.status(co)
end
local function Start(entry, cuke)
	local before = #threads
	local started = api.StartGrapple(entry, cuke)
	return started, (#threads > before) and threads[#threads] or nil
end
local function IntoPull(co) now += 0.9; return Step(co) end -- hook over: the pull starts and parks on Heartbeat
local function KillSim(entry) -- Kill's order: Dead, RestoreCarry at the spot it fell, Forget, ... CheckRaidEnd
	entry.Dead = true
	api.RestoreCarry(entry, false, entry.Root.Position)
	api.Forget(entry)
end
local function RaidOver(raid) raid.Over = true; api.ReturnDropped(raid) end -- CheckRaidEndBody at Alive 0 ("Survived")
local function ZombiesWinSim(raid) -- the loop inside Escape (order pinned above)
	raid.Over = true
	for _, other in ipairs(raid.Zombies) do
		if not other.Dead then
			api.RestoreCarry(other, true)
			api.Despawn(other, "Escape")
		end
	end
	api.ReturnDropped(raid)
end
local function DroppedSetup()
	local raid = Raid()
	local c = Cuke(LOBBY)
	raid.Dropped = {[c] = {Rest = HOME, Name = "Cuke"}}
	local g = Zombie(raid, Vector3.new(0, 3, 95))
	return raid, c, g
end
--.. the checker's case: a lobby-dropped cucumber, walker B listed BEFORE grappler A, A hooks it, B grabs it 0.3 s
--.. into the hook (before A's task wakes up); bFirst = false lists A first
local function StaleRopeSetup(bFirst)
	local raid = Raid()
	local c = Cuke(LOBBY)
	raid.Dropped = {[c] = {Rest = HOME, Name = "Cuke"}}
	local a, b
	if bFirst then
		b = Zombie(raid, Vector3.new(0, 3, 82), "Walker")
		a = Zombie(raid, Vector3.new(0, 3, 95), "Grappler")
	else
		a = Zombie(raid, Vector3.new(0, 3, 95), "Grappler")
		b = Zombie(raid, Vector3.new(0, 3, 82), "Walker")
	end
	local started, co = Start(a, c)
	now += 0.3
	local grabbed = api.Grab(b, c)
	return raid, c, a, b, co, started == true and grabbed == true
end

local ok, simErr = pcall(function()
	--.. T1 (#3, the confirmed path): lobby-dropped cucumber, the last grappler killed DURING THE HOOK, raid ends on that kill
	do
		local g0 = #grabs
		local raid, c, g = DroppedSetup()
		local started, co = Start(g, c)
		Check("T1 grapple starts", started == true and co ~= nil and coroutine.status(co) == "suspended")
		Check("T1 rope records rest (lobby) + home", g.GrappleTarget == c and Near(g.GrappleRest, LOBBY) and Near(g.GrappleHome, HOME))
		Check("T1 HookedBy / HomeRest while hooked", api.HookedBy(raid, c) == g and Near(api.HomeRest(raid, c), HOME))
		KillSim(g)
		Check("T1 the kill lets go at once", g.GrappleTarget == nil and Near(c.pose, LOBBY) and raid.Alive == 0)
		RaidOver(raid)
		Check("T1 ReturnDropped sends it home", Near(c.pose, HOME) and raid.Dropped == nil)
		now += 0.9
		Check("T1 task finishes", Step(co) == "dead")
		Check("T1 cucumber STAYS home after the task resumes", Near(c.pose, HOME), At(c))
		Check("T1 no grab, rope cleaned up", #grabs == g0 and instances[#instances].Destroyed == true)
	end
	--.. T2 (#3): killed MID-PULL, raid ends on that kill
	do
		local g0 = #grabs
		local raid, c, g = DroppedSetup()
		local _, co = Start(g, c)
		IntoPull(co)
		now += 0.3
		Step(co)
		Check("T2 the pull drags it", not Near(c.pose, LOBBY) and not Near(c.pose, HOME))
		KillSim(g)
		Check("T2 the kill snaps it back to where it lay", Near(c.pose, LOBBY) and g.GrappleTarget == nil)
		RaidOver(raid)
		now += 0.016
		Check("T2 task finishes", Step(co) == "dead")
		Check("T2 cucumber stays home", Near(c.pose, HOME), At(c))
		Check("T2 still a placed cucumber", c.tagged == true and c.Parent == HOLDER and #grabs == g0)
	end
	--.. T3 (#3, no pets): dawn mid-pull = the real EndRaid (SettleGrapple, Despawn -> Forget, ReturnDropped)
	do
		local raid, c, g = DroppedSetup()
		Raids[raid.Player] = raid
		local _, co = Start(g, c)
		IntoPull(co)
		now += 0.3
		Step(co)
		api.EndRaid(raid, "Dawn")
		Check("T3 dawn sends it home", Near(c.pose, HOME) and raid.Over == true and g.Dead == true and Raids[raid.Player] == nil, At(c))
		now += 0.016
		Step(co)
		Check("T3 cucumber stays home after the task resumes", Near(c.pose, HOME), At(c))
	end
	--.. T4 (#3 safety net): a death that skipped Forget; the raid already over -> home, a live raid -> where it lay
	do
		local raid, c, g = DroppedSetup()
		local _, co = Start(g, c)
		IntoPull(co)
		now += 0.3
		Step(co)
		g.Dead = true -- no Forget: the rope is still on
		RaidOver(raid)
		now += 0.016
		Step(co)
		Check("T4 unsettled + raid over -> home", Near(c.pose, HOME) and g.GrappleTarget == nil, At(c))
		local raid2, c2, g2 = DroppedSetup()
		Zombie(raid2, Vector3.new(30, 3, 30), "Walker") -- the raid goes on
		local _, co2 = Start(g2, c2)
		IntoPull(co2)
		now += 0.3
		Step(co2)
		g2.Dead = true
		now += 0.016
		Step(co2)
		Check("T4 unsettled + raid live -> back where it lay, still dropped", Near(c2.pose, LOBBY) and raid2.Dropped[c2] ~= nil)
	end
	--.. T5 (no regression): cucumber on the plot, grappler killed mid-pull, the raid goes on
	do
		local raid = Raid()
		local c = Cuke(HOME)
		local g = Zombie(raid, Vector3.new(0, 3, 20))
		Zombie(raid, Vector3.new(30, 3, 30), "Walker")
		local _, co = Start(g, c)
		IntoPull(co)
		now += 0.3
		Step(co)
		KillSim(g)
		Check("T5 kill snaps it home at once", Near(c.pose, HOME) and raid.Alive == 1)
		local moves = c.moves
		now += 0.016
		Check("T5 task finishes", Step(co) == "dead")
		Check("T5 task never moves it again", c.moves == moves and Near(c.pose, HOME) and c.tagged == true)
	end
	--.. T6 (no regression): a full pull grabs with the recorded home (the dropped cucumber's real home)
	do
		local g0 = #grabs
		local raid, c, g = DroppedSetup()
		local _, co = Start(g, c)
		IntoPull(co)
		now += 1.0
		Check("T6 task finishes", Step(co) == "dead")
		Check("T6 grapple grabs with its home", #grabs == g0 + 1 and grabs[#grabs].Zombie == "Grappler" and g.Carry and g.Carry.Model == c and Near(g.Carry.Rest, HOME))
		Check("T6 carried: untagged, held, no longer dropped", c.tagged == false and c.Parent == g.Model and raid.Dropped[c] == nil and g.State == "Carry")
		Check("T6 rope released", g.GrappleTarget == nil and api.HookedBy(raid, c) == nil and g.Grappling == nil)
	end
	--.. T7 (no regression): a Leaf Shield blocks at the end of the hook -> it stays where it lay (still dropped)
	do
		local raid, c, g = DroppedSetup()
		local _, co = Start(g, c)
		blockNext = true
		now += 0.9
		Step(co)
		blockNext = false
		Check("T7 blocked grapple leaves it where it lay", Near(c.pose, LOBBY) and c.tagged == true and raid.Dropped[c] ~= nil)
		Check("T7 rope released", g.GrappleTarget == nil and coroutine.status(co) == "dead")
	end
	--.. T8 (#4): another zombie grabs the cucumber MID-PULL -> its carry rest is the home, never the dragged pose
	do
		local raid = Raid()
		local c = Cuke(HOME)
		local a = Zombie(raid, Vector3.new(0, 3, 20))
		local b = Zombie(raid, Vector3.new(0, 3, 10), "Walker")
		local _, co = Start(a, c)
		IntoPull(co)
		now += 0.3
		Step(co)
		Check("T8 dragged mid-pull", not Near(c.pose, HOME))
		Check("T8 HomeRest mid-pull = home (was the dragged pose)", Near(api.HomeRest(raid, c), HOME))
		local threadsBefore = #threads
		Check("T8 a 2nd grapple is refused (one rope per cucumber)", api.StartGrapple(b, c) == false and b.Grappling == nil and b.GrappleTarget == nil and #threads == threadsBefore)
		api.Grab(b, c) -- Tick's ordinary grab: no rest passed
		Check("T8 grabber's carry rest = home", b.Carry and Near(b.Carry.Rest, HOME))
		Check("T8 the grab takes it off A's rope", a.GrappleTarget == nil and a.GrappleRest == nil and api.HookedBy(raid, c) == nil)
		local moves = c.moves
		now += 0.016
		Check("T8 grappler's task ends", Step(co) == "dead")
		Check("T8 grappler never moves the carried cucumber", c.moves == moves and a.GrappleTarget == nil and a.Carry == nil)
	end
	--.. T9 (#4): the same on a lobby-dropped cucumber (home = its drop record's home)
	do
		local raid, c, g = DroppedSetup()
		local b = Zombie(raid, Vector3.new(0, 3, 85), "Walker")
		local _, co = Start(g, c)
		IntoPull(co)
		now += 0.3
		Step(co)
		api.Grab(b, c)
		Check("T9 grabber's carry rest = the dropped cucumber's home", b.Carry and Near(b.Carry.Rest, HOME) and raid.Dropped[c] == nil)
		now += 0.016
		Step(co)
	end
	--.. T10 (#4): a settled rope (pre-close) frees the cucumber for a new grapple; the old task never disturbs it
	do
		local raid = Raid()
		local c = Cuke(HOME)
		local a = Zombie(raid, Vector3.new(0, 3, 20))
		local b = Zombie(raid, Vector3.new(20, 3, 0))
		local _, coA = Start(a, c)
		IntoPull(coA)
		now += 0.3
		Step(coA)
		api.SettleGrapple(a) -- PreCloseRaids / EndRaid
		Check("T10 settle snaps it home", Near(c.pose, HOME) and api.HookedBy(raid, c) == nil)
		local started, coB = Start(b, c)
		Check("T10 a new grapple may hook it", started == true and b.GrappleTarget == c and Near(b.GrappleHome, HOME))
		now += 0.016
		Step(coA)
		Check("T10 the old task leaves the new rope alone", b.GrappleTarget == c and coroutine.status(coA) == "dead")
		api.SettleGrapple(b)
		now += 0.9
		Step(coB)
		Check("T10 cleanup", b.GrappleTarget == nil and coroutine.status(coB) == "dead" and Near(c.pose, HOME))
	end
	--.. T11 Forget: settles once, counts once; T12 no raid
	do
		local raid = Raid()
		local c = Cuke(HOME)
		local g = Zombie(raid, Vector3.new(0, 3, 20))
		local _, co = Start(g, c)
		api.Forget(g)
		api.Forget(g)
		Check("T11 Forget twice: counted once, rope off, model forgotten", raid.Alive == 0 and g.GrappleTarget == nil and Zombies[g.Model] == nil)
		g.Dead = true
		now += 0.9
		Step(co)
		Check("T12 HookedBy / HomeRest without a raid", api.HookedBy(nil, c) == nil and Near(api.HomeRest(nil, c), HOME))
	end
	--.. T13 (#4 residual, checker R1): B grabs off A's rope mid-hook, then dawn = the real EndRaid (B first in the list)
	do
		local raid, c, a, b, co, setupOk = StaleRopeSetup(true)
		Raids[raid.Player] = raid
		Check("T13 setup: A hooked it, B grabbed it with the real home", setupOk and b.Carry and Near(b.Carry.Rest, HOME) and raid.Dropped[c] == nil)
		Check("T13 B's grab took it off A's rope", a.GrappleTarget == nil and a.GrappleRest == nil and api.HookedBy(raid, c) == nil)
		api.EndRaid(raid, "Dawn")
		Check("T13 EndRaid (B first): home, placed", Near(c.pose, HOME) and c.tagged == true and c.Parent == HOLDER and b.Carry == nil, At(c))
		local moves = c.moves
		now += 0.6
		Check("T13 A's task ends", Step(co) == "dead")
		Check("T13 A's task leaves it home", Near(c.pose, HOME) and c.moves == moves and a.Carry == nil, At(c))
	end
	--.. T14 (checker R3): ZombiesWin (the Escape loop: RestoreCarry, then Despawn -> Forget -> SettleGrapple)
	do
		local raid, c, a, b, co, setupOk = StaleRopeSetup(true)
		Check("T14 setup", setupOk)
		ZombiesWinSim(raid)
		Check("T14 ZombiesWin (B first): home, placed", Near(c.pose, HOME) and c.tagged == true and c.Parent == HOLDER and a.Dead and b.Dead, At(c))
		local moves = c.moves
		now += 0.6
		Step(co)
		Check("T14 A's task leaves it home", Near(c.pose, HOME) and c.moves == moves, At(c))
	end
	--.. T15 (checker R4): PreCloseRaids (a leave / shutdown; A stays alive and its task still wakes up afterwards)
	do
		local raid, c, a, b, co, setupOk = StaleRopeSetup(true)
		Check("T15 setup", setupOk)
		Raids[raid.Player] = raid
		api.PreCloseRaids(raid.Player)
		Check("T15 PreCloseRaids (B first): home, placed, B empty-handed", Near(c.pose, HOME) and c.tagged == true and c.Parent == HOLDER and b.Carry == nil and b.State == "Seek", At(c))
		local moves = c.moves
		now += 0.6
		Check("T15 A's task ends (alive, settled)", Step(co) == "dead" and a.Grappling == nil)
		Check("T15 A's task leaves it home, no grab by A", Near(c.pose, HOME) and c.moves == moves and a.Carry == nil and c.tagged == true, At(c))
		Raids[raid.Player] = nil
	end
	--.. T16 (control): the same three raid ends with A listed first
	do
		local raid, c, _, _, co = StaleRopeSetup(false)
		Raids[raid.Player] = raid
		api.EndRaid(raid, "Dawn")
		now += 0.6
		Step(co)
		Check("T16 EndRaid (A first): home", Near(c.pose, HOME) and c.tagged == true, At(c))
		local raid2, c2, _, _, co2 = StaleRopeSetup(false)
		ZombiesWinSim(raid2)
		now += 0.6
		Step(co2)
		Check("T16 ZombiesWin (A first): home", Near(c2.pose, HOME) and c2.tagged == true, At(c2))
		local raid3, c3, _, _, co3 = StaleRopeSetup(false)
		Raids[raid3.Player] = raid3
		api.PreCloseRaids(raid3.Player)
		now += 0.6
		Step(co3)
		Check("T16 PreCloseRaids (A first): home", Near(c3.pose, HOME) and c3.tagged == true, At(c3))
		Raids[raid3.Player] = nil
	end
	--.. T17 (side effect): B grabs off A's rope mid-hook and is killed at once -> dropped where B fell; A's task
	--.. must not snap it back to A's old rest and pull it in (the stale rope's re-pull)
	do
		local g0 = #grabs
		local raid, c, a, b, co, setupOk = StaleRopeSetup(true)
		Zombie(raid, Vector3.new(30, 3, 30), "Walker2") -- the raid goes on
		Check("T17 setup", setupOk and #grabs == g0 + 1)
		KillSim(b)
		local drop = CFrame.new(0, 3, 82)
		Check("T17 B's fall drops it where B fell, home remembered", Near(c.pose, drop) and c.tagged == true and raid.Dropped[c] and Near(raid.Dropped[c].Rest, HOME), At(c))
		local moves = c.moves
		now += 0.6
		Check("T17 A's task ends at once (no pull)", Step(co) == "dead")
		Check("T17 A never re-pulls or grabs it", Near(c.pose, drop) and c.moves == moves and a.Carry == nil and #grabs == g0 + 1, At(c))
		RaidOver(raid)
		Check("T17 the raid's end still sends it home", Near(c.pose, HOME))
	end
end)
Check("simulation ran without error", ok, simErr)

return ("WP-BUFF grapple: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
