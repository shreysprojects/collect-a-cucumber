--[[
	WP-BUFF patch tests (2026-09-22) for patched\ServerScriptService.ZombieRaidService.server.lua and
	patched\ServerScriptService.CucumberCarry.server.lua (Scripts: they cannot be required in an eval).
	  1. both compile;
	  2. structure: every 4.6 / 4.7 insertion sits where CONTRACTS pins it (ordered string positions);
	  3. behaviour: the NEW functions (TheftBlocked, IncomeOf, SyncRaidLive, CheckRaidEnd wrapper,
	     PreCloseRaids, TargetInfos) are cut out of the patched source and run against plain-table fakes.
	No Instances are created; nothing in the DataModel is touched.
	Run from an edit-peer eval:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-BUFF_patches.lua"))()
]]
local HttpService = game:GetService("HttpService")
local PATCHED = "http://127.0.0.1:8794/"

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 12 then table.insert(failures, name .. (detail and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

local function Get(file)
	return (HttpService:GetAsync(PATCHED .. file):gsub("\r\n", "\n"))
end
local zrs = Get("ServerScriptService.ZombieRaidService.server.lua")
local carry = Get("ServerScriptService.CucumberCarry.server.lua")

Check("ZombieRaidService compiles", loadstring(zrs) ~= nil)
Check("CucumberCarry compiles", loadstring(carry) ~= nil)

local function Pos(src, text, from)
	return (string.find(src, text, from or 1, true))
end
local function Count(src, text)
	local n, i = 0, 1
	while true do
		local s, e = string.find(src, text, i, true)
		if not s then return n end
		n += 1
		i = e + 1
	end
end
--.. every text found, strictly in this order (each search starts after the previous hit)
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

--..2. structure: ZombieRaidService (CONTRACTS 4.6)..--
Ordered("zrs lazy block after the Modules", zrs, {
	'local SoundController = require(ReplicatedStorage.Modules:WaitForChild("SoundController"))',
	"local function Lazy(name)", 'Lazy("PetBuffService")', 'Lazy("IncomeService")', 'Lazy("DataService")', "--..Config..--"})
Ordered("zrs TargetInfos bindable before API.Parent", zrs, {'Bindable("TargetInfos")', "API.Parent = ServerStorage"})
Ordered("zrs forward-declared SyncRaidLive", zrs, {"local SyncRaidLive", "local function CheckRaidEnd(raid)", "SyncRaidLive = function(player)"})
Ordered("zrs Grab guard before any mutation", zrs, {
	"local function TheftBlocked(entry, model)", "local function Grab(entry, model, restCFrame)",
	"if not torso then return false end", "if TheftBlocked(entry, model) then return false end",
	'pcall(buffs.ClearCucumber, model, "Stolen")', "local carry = {Model = model",
	"CollectionService:RemoveTag(model, PLACED_TAG)", 'model:SetAttribute("StolenBy", entry.Model.Name)'})
Check("zrs TryBlockTheft gets no clock", Pos(zrs, "pcall(buffs.TryBlockTheft, model, entry.Model)") ~= nil and Pos(zrs, "TryBlockTheft, model, entry.Model, os.clock") == nil)
Ordered("zrs grapple home + pre-pull guard", zrs, {
	"local rest = target:GetPivot()", "local home = HomeRest(entry.Raid, target)", "task.wait(ZombieCatalog.GRAPPLE_HOOK)",
	"and not TheftBlocked(entry, target)", "if not Grab(entry, target, home) then target:PivotTo(rest) end"})
Check("zrs no post-pull HomeRest", Pos(zrs, "Grab(entry, target, HomeRest(") == nil)
--.. review fix (2026-09-22): a pending grapple is settled (snap back + pull ends) at every EndRaid and pre-close
Ordered("zrs grapple records its rest + honours a settle", zrs, {
	"local rest = target:GetPivot()", "local home = HomeRest(entry.Raid, target)",
	"entry.GrappleTarget, entry.GrappleRest = target, rest", "task.wait(ZombieCatalog.GRAPPLE_HOOK)",
	"not entry.Dead and entry.GrappleTarget == target and target.Parent", "and not TheftBlocked(entry, target)",
	"if entry.Dead or entry.GrappleTarget ~= target or not target.Parent", "RunService.Heartbeat:Wait()",
	"entry.Grappling = nil", "if entry.GrappleTarget == target then entry.GrappleTarget, entry.GrappleRest = nil, nil end",
	"if not Grab(entry, target, home) then target:PivotTo(rest) end"})
Ordered("zrs SettleGrapple before EndRaid / PreCloseRaids", zrs, {
	"function SettleGrapple(entry)", "local function EndRaid(raid, reason)", "for _, entry in ipairs(raid.Zombies) do",
	"SettleGrapple(entry)", "if not entry.Dead then", 'RestoreCarry(entry, reason ~= "Left", nil, reason == "Left")',
	"local function PreCloseRaids(player)", "for _, entry in ipairs(raid.Zombies) do", "SettleGrapple(entry)",
	"if not entry.Dead and entry.Carry then", "ReturnDropped(raid, true)"})
--.. review fix #3 (2026-09-22): forward-declared (Forget calls it), defined once in the grapple section
Check("zrs one SettleGrapple definition", Count(zrs, "function SettleGrapple(") == 1 and Count(zrs, "local function SettleGrapple(") == 0)
Ordered("zrs SettleGrapple forward-declared before Forget", zrs, {"local SettleGrapple -- defined below", "local function Forget(entry)", "function SettleGrapple(entry)"})
Ordered("zrs NearestCucumber avoid", zrs, {"local function NearestCucumber(entry)", "model == entry.AvoidModel and os.clock() < (entry.AvoidUntil or 0)", "return best"})
Ordered("zrs Tick grab gated by BlockedUntil", zrs, {
	"if dist <= GrabReach(target, entry) then", "if os.clock() >= (entry.BlockedUntil or 0) then",
	"if not Grab(entry, target) then entry.Target = nil end", "end", "return"})
Check("zrs one CheckRaidEnd definition", Count(zrs, "local function CheckRaidEnd(") == 1)
Ordered("zrs CheckRaidEnd wraps the body", zrs, {"local function CheckRaidEndBody(raid)", "local function CheckRaidEnd(raid)", "CheckRaidEndBody(raid)", "SyncRaidLive(raid.Player)"})
Ordered("zrs RestoreCarry force", zrs, {"local function RestoreCarry(entry, silent, dropAt, force)", "force == true or (raid and raid.Player and raid.Player.Parent)"})
Ordered("zrs ReturnDropped noSnapshot", zrs, {"local function ReturnDropped(raid, noSnapshot)", "and not noSnapshot then pcall(snapshot.Invoke"})
Check("zrs EndRaid Left forces", Pos(zrs, 'RestoreCarry(entry, reason ~= "Left", nil, reason == "Left")') ~= nil)
Ordered("zrs sync: StartRaids", zrs, {"Raids[player] = raid", "SyncRaidLive(player)", "table.insert(raids, raid)"})
Ordered("zrs sync: SpawnThief", zrs, {"DayRaids[player] = raid", "SyncRaidLive(player)", "local entry = Spawn(variety, CFrame.new(ground), raid)", "SyncRaidLive(player)", "if not entry then return nil end"})
Ordered("zrs sync: EndRaid", zrs, {"local function EndRaid(raid, reason)", "Raids[raid.Player] = nil", "SyncRaidLive(raid.Player)", "local function EndDayRaids"})
Ordered("zrs sync: ZombiesWin", zrs, {'raid.Result = "ZombiesWin"', "ReturnDropped(raid)", "Publish(raid)", "SyncRaidLive(raid.Player)", "elseif raid then"})
Ordered("zrs sync: dev end/kill/spawn", zrs, {
	'elseif kind == "end" then', "SyncRaidLive(p)", 'elseif kind == "kill" then', "SyncRaidLive(p)",
	'elseif kind == "spawn" then', "Raids[player] = raid", "SyncRaidLive(player)", "raid.Limit = math.min", "SyncRaidLive(player)"})
Ordered("zrs pre-close registration", zrs, {"local function PreCloseRaids(player)", "data.OnBeforeClose, PreCloseRaids, 35"})
Ordered("zrs IncomeOf threat source + fallback", zrs, {"local function IncomeOf(player)", "income.GetThreatIncome(player)", 'data:FindFirstChild("CashPerSec")'})

--..2. structure: CucumberCarry (CONTRACTS 4.7)..--
Ordered("carry services + lazy", carry, {'local RunService = game:GetService("RunService")', 'local HttpService = game:GetService("HttpService")', 'Lazy("PetBuffService")', "--..Config..--"})
Ordered("carry Place id before tag", carry, {"local taken, meta = Take(player)", 'taken:SetAttribute("ShownKg", meta.ShownKg)',
	'taken:SetAttribute("CucumberId", HttpService:GenerateGUID(false))', 'CollectionService:AddTag(taken, "PlacedCucumber")', "taken.Parent = holder"})
Ordered("carry RestorePlaced id + stamp before tag", carry, {"local function RestorePlaced(", 'model:SetAttribute("ShownKg", meta.ShownKg)',
	"local id = record.Id", 'model:SetAttribute("CucumberId"', "pcall(buffs.StampFromRecord, model, record.PetBuffs)",
	'CollectionService:AddTag(model, "PlacedCucumber")', "model.Parent = HolderOf(plot)"})
Check("carry RestorePlaced never writes record.Id", Pos(carry, "record.Id =") == nil)
Ordered("carry PickUp clears before untag", carry, {"PickUp = function(player, placed, force)", 'pcall(buffs.ClearCucumber, placed, "PickUp")',
	'placed:SetAttribute("CucumberId", nil)', 'CollectionService:RemoveTag(placed, "PlacedCucumber")', 'placed:SetAttribute("Owner", nil)'})

--..3. behaviour of the new functions (cut out of the patched source, run on fakes)..--
local function Cut(src, startText)
	local s = Pos(src, startText)
	if not s then return nil end
	local e = Pos(src, "\nend\n", s)
	return e and src:sub(s, e + 4) or nil
end
local function Build(snippet, prefix, suffix, env)
	if not snippet then return nil, "snippet not found" end
	local fn, err = loadstring((prefix or "") .. snippet .. (suffix or ""))
	if not fn then return nil, err end
	setfenv(fn, setmetatable(env, {__index = getfenv(0)}))
	return fn()
end
local fakeTypeof = function(x)
	if type(x) == "table" and x.__instance then return "Instance" end
	return typeof(x)
end

--.. TheftBlocked
do
	local blockNext, lastArgs = true, nil
	local buffs = {TryBlockTheft = function(...) lastArgs = table.pack(...) return blockNext end}
	local env = {PetBuffs = function() return buffs end, GUARD_STUN_SECONDS = 0.8, GUARD_AVOID_SECONDS = 4}
	local TheftBlocked, err = Build(Cut(zrs, "local function TheftBlocked(entry, model)"), nil, "\nreturn TheftBlocked", env)
	Check("TheftBlocked builds", TheftBlocked ~= nil, err)
	if TheftBlocked then
		local cucumber, zombie = {name = "cuke"}, {name = "zombie"}
		local entry = {Target = cucumber, StunUntil = 0, Model = zombie}
		local t0 = os.clock()
		Check("TheftBlocked blocks", TheftBlocked(entry, cucumber) == true)
		Check("TheftBlocked passes (cucumber, zombie) only", lastArgs and lastArgs.n == 2 and lastArgs[1] == cucumber and lastArgs[2] == zombie)
		Check("block drops the target", entry.Target == nil)
		Check("block stuns 0.8", entry.StunUntil >= t0 + 0.8 - 1e-3 and entry.StunUntil <= os.clock() + 0.8 + 1e-3)
		Check("block gates grabs 0.8", entry.BlockedUntil and entry.BlockedUntil >= t0 + 0.8 - 1e-3)
		Check("block avoids that cucumber 4 s", entry.AvoidModel == cucumber and entry.AvoidUntil >= t0 + 4 - 1e-3)
		local long = {Target = cucumber, StunUntil = os.clock() + 50, Model = zombie}
		TheftBlocked(long, cucumber)
		Check("block keeps a longer stun", long.StunUntil > os.clock() + 40)
		blockNext = false
		local free = {Target = cucumber, StunUntil = 0, Model = zombie}
		Check("no block -> false", TheftBlocked(free, cucumber) == false)
		Check("no block leaves the entry", free.Target == cucumber and free.StunUntil == 0 and free.BlockedUntil == nil and free.AvoidModel == nil)
		buffs.TryBlockTheft = function() error("boom") end
		Check("a throwing guard never blocks", TheftBlocked(free, cucumber) == false)
		env.PetBuffs = function() return nil end
		Check("no PetBuffService -> false", TheftBlocked(free, cucumber) == false)
	end
end

--.. IncomeOf
do
	local income = nil
	local env = {IncomeSvc = function() return income end}
	local IncomeOf, err = Build(Cut(zrs, "local function IncomeOf(player)"), nil, "\nreturn IncomeOf", env)
	Check("IncomeOf builds", IncomeOf ~= nil, err)
	if IncomeOf then
		local cps = {Value = 40200}
		local data = {FindFirstChild = function(_, n) return n == "CashPerSec" and cps or nil end}
		local player = {FindFirstChild = function(_, n) return n == "Data" and data or nil end}
		Check("no IncomeService -> CashPerSec", IncomeOf(player) == 40200)
		income = {IsStarted = function() return false end, GetThreatIncome = function() return 123 end}
		Check("not started -> CashPerSec", IncomeOf(player) == 40200)
		income.IsStarted = function() return true end
		Check("started -> GetThreatIncome", IncomeOf(player) == 123)
		income.GetThreatIncome = function() return 0 end
		Check("started, truthful 0", IncomeOf(player) == 0)
		income.GetThreatIncome = function() return nil end
		Check("nil threat -> CashPerSec", IncomeOf(player) == 40200)
		income.GetThreatIncome = function() return 0 / 0 end
		Check("NaN threat -> CashPerSec", IncomeOf(player) == 40200)
		income.GetThreatIncome = function() return math.huge end
		Check("inf threat -> CashPerSec", IncomeOf(player) == 40200)
		income.GetThreatIncome = function() error("boom") end
		Check("throwing threat -> CashPerSec", IncomeOf(player) == 40200)
		local bare = {FindFirstChild = function() return nil end}
		Check("no Data -> 0", IncomeOf(bare) == 0)
	end
end

--.. SyncRaidLive + the CheckRaidEnd wrapper
do
	local Raids, thieves = {}, {}
	local env = {Raids = Raids, HasLiveThief = function(p) return thieves[p] == true end, typeof = fakeTypeof}
	local Sync, err = Build(Cut(zrs, "SyncRaidLive = function(player)"), "local SyncRaidLive\n", "\nreturn SyncRaidLive", env)
	Check("SyncRaidLive builds", Sync ~= nil, err)
	if Sync then
		local function FakePlayer()
			local p = {__instance = true, Parent = "Players", attrs = {}}
			function p:SetAttribute(k, v) self.attrs[k] = v end
			return p
		end
		local p = FakePlayer()
		Raids[p] = {Over = false}
		Sync(p)
		Check("raid live -> true", p.attrs.RaidLive == true)
		Raids[p].Over = true
		p.attrs.RaidLive = "stale"
		Sync(p)
		Check("raid over -> nil (never false)", p.attrs.RaidLive == nil)
		Raids[p] = nil
		thieves[p] = true
		Sync(p)
		Check("live thief -> true", p.attrs.RaidLive == true)
		thieves[p] = nil
		Sync(p)
		Check("idle -> nil", p.attrs.RaidLive == nil)
		local gone = FakePlayer()
		gone.Parent = nil
		Raids[gone] = {Over = false}
		Sync(gone)
		Check("leaving player untouched", gone.attrs.RaidLive == nil)
		Sync(nil)
		Check("nil player no error", true)
		--.. wrapper: body first, then the sync, on every exit
		local calls = {}
		local wrapEnv = {CheckRaidEndBody = function(raid) table.insert(calls, "body") end, SyncRaidLive = function(pl) table.insert(calls, "sync") end}
		local Wrap, werr = Build(Cut(zrs, "local function CheckRaidEnd(raid)"), nil, "\nreturn CheckRaidEnd", wrapEnv)
		Check("CheckRaidEnd wrapper builds", Wrap ~= nil, werr)
		if Wrap then
			Wrap({Player = p})
			Check("wrapper order body -> sync", calls[1] == "body" and calls[2] == "sync" and #calls == 2)
			Wrap({})
			Check("wrapper without player: body only", #calls == 3 and calls[3] == "body")
		end
	end
end

--.. SettleGrapple (review fix 2026-09-22)
do
	local env = {
		CollectionService = {HasTag = function(_, m, tag) return m.tagged == true and tag == "PlacedCucumber" end},
		PLACED_TAG = "PlacedCucumber",
	}
	local Settle, err = Build(Cut(zrs, "function SettleGrapple(entry)"), "local SettleGrapple\n", "\nreturn SettleGrapple", env)
	Check("SettleGrapple builds", Settle ~= nil, err)
	if Settle then
		local function Cuke(tagged, parent)
			local m = {tagged = tagged, Parent = parent, pivots = {}}
			function m:PivotTo(cf) table.insert(self.pivots, cf) end
			return m
		end
		local rest = CFrame.new(4, 5, 6)
		local c = Cuke(true, "Placed")
		local e = {GrappleTarget = c, GrappleRest = rest}
		Settle(e)
		Check("settle pivots a tagged cucumber to its rest", #c.pivots == 1 and c.pivots[1] == rest)
		Check("settle clears the grapple (the pull task stops)", e.GrappleTarget == nil and e.GrappleRest == nil)
		Settle(e)
		Check("settle twice is a no-op", #c.pivots == 1)
		local stolen = Cuke(false, "Zombie")
		local e2 = {GrappleTarget = stolen, GrappleRest = rest}
		Settle(e2)
		Check("settle never moves an untagged (carried / picked-up) model", #stolen.pivots == 0 and e2.GrappleTarget == nil)
		local gone = Cuke(true, nil)
		local e3 = {GrappleTarget = gone, GrappleRest = rest}
		Settle(e3)
		Check("settle never moves a destroyed model", #gone.pivots == 0 and e3.GrappleTarget == nil)
		Check("settle without a grapple no-op", pcall(Settle, {}))
	end
end

--.. PreCloseRaids
do
	local Raids, DayRaids = {}, {}
	local profileLoaded = true
	local restored, returned, settled = {}, {}, {}
	local env = {
		Raids = Raids, DayRaids = DayRaids,
		DataSvc = function() return {GetData = function() return profileLoaded and {} or nil end} end,
		SettleGrapple = function(entry) table.insert(settled, entry) end,
		RestoreCarry = function(entry, silent, dropAt, force) table.insert(restored, {entry, silent, dropAt, force}) entry.Carry = nil end,
		ReturnDropped = function(raid, noSnapshot) table.insert(returned, {raid, noSnapshot}) end,
		warn = function() end,
	}
	local Pre, err = Build(Cut(zrs, "local function PreCloseRaids(player)"), nil, "\nreturn PreCloseRaids", env)
	Check("PreCloseRaids builds", Pre ~= nil, err)
	if Pre then
		local p = {}
		local carrier = {Dead = false, Carry = {}, State = "Carry"}
		local idle = {Dead = false, State = "Seek"}
		local deadCarrier = {Dead = true, Carry = {}, State = "Carry"}
		Raids[p] = {Zombies = {carrier, idle, deadCarrier}}
		local thief = {Dead = false, Carry = {}, State = "Carry"}
		DayRaids[p] = {Zombies = {thief}}
		Pre(p, {}, "Leave")
		Check("pre-close restores live carriers only", #restored == 2 and restored[1][1] == carrier and restored[2][1] == thief)
		Check("pre-close restore args (silent, no drop, force)", restored[1][2] == true and restored[1][3] == nil and restored[1][4] == true)
		Check("pre-close carrier no longer heads for the door", carrier.State == "Seek" and thief.State == "Seek")
		Check("pre-close dead carrier untouched", deadCarrier.State == "Carry")
		Check("pre-close settles every entry's grapple (dead ones too)", #settled == 4 and settled[1] == carrier and settled[2] == idle and settled[3] == deadCarrier and settled[4] == thief, #settled)
		Check("pre-close ReturnDropped both raids, no snapshot", #returned == 2 and returned[1][2] == true and returned[2][2] == true)
		profileLoaded = false
		Pre(p, {}, "Leave")
		Check("pre-close gates on GetData", #restored == 2 and #returned == 2)
		profileLoaded = true
		Raids[p] = {Zombies = {{Dead = false, Carry = {}}}}
		env.RestoreCarry = function() error("boom") end
		DayRaids[p] = {Zombies = {}}
		local ok = pcall(Pre, p)
		Check("pre-close survives a failing raid", ok and #returned == 3, #returned)
		Check("pre-close no raids no-op", pcall(Pre, {}))
	end
end

--.. TargetInfos
do
	local Zombies = {}
	local env = {Zombies = Zombies}
	local Infos, err = Build(Cut(zrs, "TargetInfosAPI.OnInvoke = function()"), "local TargetInfosAPI = {}\n", "\nreturn TargetInfosAPI.OnInvoke", env)
	Check("TargetInfos builds", Infos ~= nil, err)
	if Infos then
		local function Z(name, entryOver)
			local model = {Name = name, Parent = "Zombies", GetPivot = function() return CFrame.new(1, 2, 3) end}
			local entry = {Model = model, Dead = false, Shaded = false, Underground = false, State = "Seek",
				Humanoid = {Health = 50, MaxHealth = 60}, Root = {Parent = model, Position = Vector3.new(10, 3, 5)}}
			for k, v in pairs(entryOver or {}) do entry[k] = v end
			Zombies[model] = entry
			return model, entry
		end
		local nightRaid, dayRaid = {UserId = 42, Day = false}, {UserId = 7, Day = true}
		local carrier = Z("carrier", {Raid = nightRaid, Carry = {}, State = "Carry"})
		local grappler = Z("grappler", {Raid = nightRaid, Grappling = true})
		local thief = Z("thief", {Raid = dayRaid})
		local stray = Z("stray", {Raid = nil})
		Z("dead", {Raid = nightRaid, Dead = true})
		Z("shaded", {Raid = nightRaid, Shaded = true})
		Z("under", {Raid = nightRaid, Underground = true})
		Z("hold", {Raid = nightRaid, Hold = true})
		local gone = Z("gone", {Raid = nightRaid})
		gone.Parent = nil
		local noRoot = Z("noroot", {Raid = nightRaid})
		Zombies[noRoot].Root = {Parent = nil, Position = Vector3.zero}
		local list = Infos()
		local by = {}
		for _, info in ipairs(list) do by[info.Model.Name] = info end
		Check("TargetInfos filter", #list == 5 and by.carrier and by.grappler and by.thief and by.stray and by.noroot, #list)
		local c = by.carrier
		Check("TargetInfo carrier", c and c.Owner == 42 and c.Carrying == true and c.Grappling == false and c.Digging == false and c.Day == false and c.State == "Carry")
		Check("TargetInfo health/pos", c and c.Health == 50 and c.MaxHealth == 60 and c.Position == Vector3.new(10, 3, 5))
		Check("TargetInfo grappling", by.grappler and by.grappler.Grappling == true and by.grappler.Carrying == false)
		Check("TargetInfo day thief", by.thief and by.thief.Day == true and by.thief.Owner == 7)
		Check("TargetInfo stray owner nil", by.stray and by.stray.Owner == nil and by.stray.Day == false)
		Check("TargetInfo pivot fallback", by.noroot and by.noroot.Position == Vector3.new(1, 2, 3))
		local fields = 0
		for _ in pairs(c or {}) do fields += 1 end
		Check("TargetInfo exactly 10 fields (7.5)", fields == 10, fields)
	end
end

return ("WP-BUFF patches: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
