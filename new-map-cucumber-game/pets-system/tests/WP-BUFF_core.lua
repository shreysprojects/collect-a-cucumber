--[[
	WP-BUFF core tests (2026-09-22): PetBuffService.Core (eligibility, PickKind / PickTarget uniformity,
	TryBlock state machine, ValidateRecords, guard seconds) + the stateless API (StampFromRecord /
	Serialize round trip, ModifiersOf, ClearCucumber, Grant before Start). Read-only: loads the sources
	through the loopback servers with a private `require` (PetBalance / PetStats from src\, a fake empty
	PetsCatalog); the only Instances are UNPARENTED Models used as attribute holders, destroyed at the end.
	Run from an edit-peer eval:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-BUFF_core.lua"))()
]]
local HttpService = game:GetService("HttpService")
local SRC = "http://127.0.0.1:8793/"

--..harness..--
local function Load(file, provided)
	local fn, err = loadstring(HttpService:GetAsync(SRC .. file), "=" .. file)
	if not fn then error("compile " .. file .. ": " .. tostring(err)) end
	local realGame = game
	local fakeModules = {}
	function fakeModules:FindFirstChild(name)
		if provided[name] ~= nil then return {__sentinel = name} end
		return nil
	end
	fakeModules.WaitForChild = fakeModules.FindFirstChild
	local fakeRS = {Modules = fakeModules}
	function fakeRS:FindFirstChild(name)
		if name == "Modules" then return fakeModules end
		return nil
	end
	fakeRS.WaitForChild = fakeRS.FindFirstChild
	local fakeGame = {}
	function fakeGame:GetService(name)
		if name == "ReplicatedStorage" then return fakeRS end
		return realGame:GetService(name)
	end
	local env = setmetatable({
		game = fakeGame,
		require = function(x)
			if type(x) == "table" and x.__sentinel then return provided[x.__sentinel] end
			return require(x)
		end,
	}, {__index = getfenv(0)})
	setfenv(fn, env)
	return fn()
end

local provided = {PetsCatalog = {PETS = {}, EGGS = {}, EggKey = function(s) return s .. " Egg" end}}
provided.PetBalance = Load("ReplicatedStorage.Modules.PetBalance.lua", provided)
provided.PetStats = Load("ReplicatedStorage.Modules.PetStats.lua", provided)
local Buff = Load("ServerStorage.PetBuffService.lua", provided)
local Core = Buff.Core
local PetBalance = provided.PetBalance

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 12 then table.insert(failures, name .. (detail and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function Near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-9) end

--..1. API surface..--
for _, name in ipairs({"Init", "Start", "IsStarted", "Serialize", "StampFromRecord", "ModifiersOf", "IsEligible", "Grant",
	"TryBlockTheft", "ClearCucumber", "GuardSeconds", "GetDiagnostics", "Stop"}) do
	Check("api " .. name, type(Buff[name]) == "function")
end
for _, name in ipairs({"PickKind", "PickTarget", "TryBlock", "ValidateRecords", "Eligible", "CycleSeconds", "GuardSeconds"}) do
	Check("core " .. name, type(Core[name]) == "function")
end
Check("not started at load", Buff.IsStarted() == false)

--..2. eligibility predicate on fake cucumber tables..--
local NOW = 1790000000
local function Facts(over)
	local f = {Tagged = true, IsModel = true, Owner = 42, UserId = 42, PlotOwner = 42, InPlaced = true, StolenBy = nil,
		CucumberId = "c-1", BaseRestored = true, LocalX = 3, LocalZ = -4, HalfX = 20, HalfZ = 20, Expires = {}}
	for k, v in pairs(over or {}) do f[k] = v end
	return f
end
for _, kind in ipairs({"Yield", "Haste", "Guard"}) do
	Check("eligible base " .. kind, Core.Eligible(Facts(), kind, NOW) == true)
end
local NOPE = {
	{"untagged", {Tagged = false}}, {"not a model", {IsModel = false}}, {"other owner", {Owner = 7}},
	{"owner string", {Owner = "42"}}, {"plot not theirs", {PlotOwner = 7}}, {"plot unowned", {PlotOwner = false}},
	{"not in Placed", {InPlaced = false}}, {"stolen", {StolenBy = "Rotten Shambler"}}, {"no id", {CucumberId = false}},
	{"empty id", {CucumberId = ""}}, {"long id", {CucumberId = string.rep("x", 65)}}, {"number id", {CucumberId = 5}},
	{"not restored", {BaseRestored = false}}, {"restored nil", {BaseRestored = "yes"}},
	{"outside X", {LocalX = 20.6}}, {"outside -Z", {LocalZ = -20.51}}, {"NaN X", {LocalX = 0 / 0}},
	{"inf half", {HalfX = math.huge}}, {"no userid", {UserId = false}},
}
for _, case in ipairs(NOPE) do
	Check("ineligible " .. case[1], Core.Eligible(Facts(case[2]), "Yield", NOW) == false)
end
Check("footprint margin inside", Core.Eligible(Facts({LocalX = 20.4, LocalZ = -20.5}), "Haste", NOW) == true)
Check("unknown kind Wild", Core.Eligible(Facts(), "Wild", NOW) == false)
Check("unknown kind None", Core.Eligible(Facts(), "None", NOW) == false)
Check("nil facts", Core.Eligible(nil, "Yield", NOW) == false)
--.. same kind: never stacked, never refreshed; other kinds still fine
local live = Facts({Expires = {Yield = NOW + 30}})
Check("live Yield blocks Yield", Core.Eligible(live, "Yield", NOW) == false)
Check("live Yield leaves Haste", Core.Eligible(live, "Haste", NOW) == true)
Check("live Yield leaves Guard", Core.Eligible(live, "Guard", NOW) == true)
Check("expired Yield eligible", Core.Eligible(Facts({Expires = {Yield = NOW - 0.01}}), "Yield", NOW) == true)
Check("expiry == now eligible", Core.Eligible(Facts({Expires = {Yield = NOW}}), "Yield", NOW) == true)
Check("garbage expiry eligible", Core.Eligible(Facts({Expires = {Guard = "soon"}}), "Guard", NOW) == true)
Check("NaN now + expiry = live", Core.Eligible(Facts({Expires = {Guard = NOW}}), "Guard", 0 / 0) == false)

--..3. Wild picks only kinds with targets, uniformly (30 000 seeded draws, +-3 sigma)..--
local N = 30000
do
	local rng = Random.new(20260922)
	local counts = {Yield = 0, Haste = 0, Guard = 0}
	local kinds = {"Yield", "Haste", "Guard"}
	for _ = 1, N do
		local k = Core.PickKind(kinds, rng)
		counts[k] += 1
	end
	local sigma = math.sqrt(N * (1 / 3) * (2 / 3))
	for k, c in pairs(counts) do
		Check("PickKind uniform " .. k, math.abs(c - N / 3) <= 3 * sigma, c)
	end
	--.. the Grant path: kinds with at least one eligible target (Yield has none)
	local lists = {Yield = {}, Haste = {"h1", "h2", "h3"}, Guard = {"g1"}}
	local withTargets = {}
	for _, kind in ipairs(kinds) do
		if #lists[kind] > 0 then table.insert(withTargets, kind) end
	end
	local c2 = {Yield = 0, Haste = 0, Guard = 0}
	for _ = 1, N do
		c2[Core.PickKind(withTargets, rng)] += 1
	end
	local s2 = math.sqrt(N * 0.25)
	Check("Wild never picks a kind without targets", c2.Yield == 0, c2.Yield)
	Check("Wild uniform over kinds (not targets) Haste", math.abs(c2.Haste - N / 2) <= 3 * s2, c2.Haste)
	Check("Wild uniform over kinds (not targets) Guard", math.abs(c2.Guard - N / 2) <= 3 * s2, c2.Guard)
	Check("PickKind empty -> nil", Core.PickKind({}, rng) == nil)
	Check("PickKind non-table -> nil", Core.PickKind(nil, rng) == nil)
end

--..4. target choice uniform..--
do
	local rng = Random.new(987654)
	local list = {"a", "b", "c", "d", "e"}
	local counts = {}
	for _ = 1, N do
		local t = Core.PickTarget(list, rng)
		counts[t] = (counts[t] or 0) + 1
	end
	local sigma = math.sqrt(N * 0.2 * 0.8)
	for _, t in ipairs(list) do
		Check("PickTarget uniform " .. t, math.abs((counts[t] or 0) - N / 5) <= 3 * sigma, counts[t])
	end
	Check("PickTarget empty -> nil", Core.PickTarget({}, rng) == nil)
	Check("PickTarget single", Core.PickTarget({"only"}, rng) == "only")
end

--..5. TryBlock state machine..--
do
	local grace = PetBalance.GUARD.GraceSeconds
	local s0 = {GuardExpiresAt = NOW + 100, Charges = 1, GraceUntil = nil}
	local b1, s1 = Core.TryBlock(s0, NOW)
	Check("live shield blocks", b1 == true)
	Check("charge consumed", s1.Consumed == true and s1.Charges == 0)
	Check("last charge clears the shield", s1.GuardExpiresAt == nil)
	Check("grace set", Near(s1.GraceUntil, NOW + grace))
	Check("input state untouched", s0.Charges == 1 and s0.GraceUntil == nil)
	--.. two attempts in one frame -> one charge
	local b2, s2 = Core.TryBlock(s1, NOW)
	Check("same-frame second attempt blocked", b2 == true)
	Check("same-frame second attempt no charge", s2.Consumed == false and s2.Charges == 0)
	local b3, s3 = Core.TryBlock(s2, NOW + grace - 0.01)
	Check("inside grace blocked, no charge", b3 == true and s3.Consumed == false)
	local b4 = Core.TryBlock(s3, NOW + grace)
	Check("grace over, no shield -> not blocked", b4 == false)
	--.. count charges over a burst of attempts
	local consumed, state = 0, {GuardExpiresAt = NOW + 100, Charges = 1}
	for i = 0, 20 do
		local _, ns = Core.TryBlock(state, NOW + i * 0.05)
		if ns.Consumed then consumed += 1 end
		state = ns
	end
	Check("burst consumes exactly one charge", consumed == 1, consumed)
	--.. expired / missing / bad shields
	Check("expired shield does not block", (Core.TryBlock({GuardExpiresAt = NOW - 1, Charges = 1}, NOW)) == false)
	Check("shield expiring now does not block", (Core.TryBlock({GuardExpiresAt = NOW, Charges = 1}, NOW)) == false)
	Check("no shield", (Core.TryBlock({}, NOW)) == false)
	Check("nil state", (Core.TryBlock(nil, NOW)) == false)
	Check("zero charges", (Core.TryBlock({GuardExpiresAt = NOW + 5, Charges = 0}, NOW)) == false)
	Check("half charge", (Core.TryBlock({GuardExpiresAt = NOW + 5, Charges = 0.5}, NOW)) == false)
	Check("NaN charges", (Core.TryBlock({GuardExpiresAt = NOW + 5, Charges = 0 / 0}, NOW)) == false)
	Check("NaN now", (Core.TryBlock({GuardExpiresAt = NOW + 5, Charges = 1}, 0 / 0)) == false)
	--.. two charges: second one only after the grace
	local _, t1 = Core.TryBlock({GuardExpiresAt = NOW + 100, Charges = 2}, NOW)
	Check("2 charges -> 1 left, shield kept", t1.Charges == 1 and t1.GuardExpiresAt == NOW + 100)
	local _, t2 = Core.TryBlock(t1, NOW + 0.5)
	Check("2 charges: grace attempt free", t2.Consumed == false and t2.Charges == 1)
	local b5, t3 = Core.TryBlock(t2, NOW + grace + 0.1)
	Check("2 charges: second charge after grace", b5 == true and t3.Consumed == true and t3.Charges == 0)
end

--..6. ValidateRecords..--
do
	local yieldMax = PetBalance.ABILITIES.Yield.Duration
	local r = Core.ValidateRecords({
		"junk",
		{Kind = "Wild", ExpiresAt = NOW + 10},
		{Kind = "Yield", ExpiresAt = NOW + 50, SourcePetId = "pet-1"},
		{Kind = "Yield", ExpiresAt = NOW + 80, SourcePetId = "pet-9"}, -- duplicate kind: first valid wins
		{Kind = "Haste", ExpiresAt = 0 / 0},
		{Kind = "Haste", ExpiresAt = NOW + 30, SourcePetId = 123}, -- bad source id -> dropped
		{Kind = "Haste", ExpiresAt = NOW + 60},
	}, NOW)
	Check("validate count", #r == 2, #r)
	Check("validate yield first wins", r[1] and r[1].Kind == "Yield" and r[1].ExpiresAt == NOW + 50 and r[1].SourcePetId == "pet-1")
	Check("validate haste no source", r[2] and r[2].Kind == "Haste" and r[2].ExpiresAt == NOW + 60 and r[2].SourcePetId == nil)
	Check("validate non-table", #Core.ValidateRecords("x", NOW) == 0)
	Check("validate NaN now", #Core.ValidateRecords({{Kind = "Yield", ExpiresAt = NOW + 5}}, 0 / 0) == 0)
	local g = Core.ValidateRecords({
		{Kind = "Guard", ExpiresAt = NOW + 200, Charges = 0}, -- no charge -> dropped
		{Kind = "Guard", ExpiresAt = NOW + 200, Charges = 1.5}, -- not whole -> dropped
		{Kind = "Guard", ExpiresAt = NOW + 200}, -- no Charges -> dropped
		{Kind = "Guard", ExpiresAt = NOW + 200, Charges = 3, SourcePetId = "pet-2"}, -- capped to Guard.Charges
	}, NOW)
	Check("guard validate", #g == 1 and g[1].Charges == PetBalance.ABILITIES.Guard.Charges and g[1].SourcePetId == "pet-2")
	local far = Core.ValidateRecords({{Kind = "Yield", ExpiresAt = NOW + 1e6}}, NOW)
	Check("far-future expiry capped", far[1] and far[1].ExpiresAt <= NOW + yieldMax + 5 and far[1].ExpiresAt > NOW + yieldMax, far[1] and far[1].ExpiresAt)
	local many = {}
	for i = 1, 20 do many[i] = {Kind = "Bogus", ExpiresAt = NOW + 1} end
	many[9] = {Kind = "Yield", ExpiresAt = NOW + 5}
	Check("reads at most 8 entries", #Core.ValidateRecords(many, NOW) == 0)
end

--..6b. sweeper verdicts (what the 0.25 s sweep removes)..--
do
	Check("sweep API", type(Core.SweepVerdicts) == "function")
	local v = Core.SweepVerdicts({
		PetBuff_Yield = NOW + 5, PetBuff_YieldSrc = "p1",
		PetBuff_Haste = NOW - 1, PetBuff_HasteSrc = "p2",
		PetBuff_Guard = NOW + 100, PetBuff_GuardCharges = 1,
	}, NOW)
	Check("sweep live Yield", v.Yield == "live")
	Check("sweep expired Haste", v.Haste == "expired")
	Check("sweep live Guard", v.Guard == "live")
	local w = Core.SweepVerdicts({PetBuff_Guard = NOW + 100, PetBuff_GuardCharges = 0, PetBuff_YieldSrc = "orphan", PetBuff_Haste = "x"}, NOW)
	Check("sweep spent Guard invalid", w.Guard == "invalid")
	Check("sweep orphan source invalid", w.Yield == "invalid")
	Check("sweep garbage expiry invalid", w.Haste == "invalid")
	Check("sweep nothing", next(Core.SweepVerdicts({Owner = 1}, NOW)) == nil)
	Check("sweep expiry == now expired", Core.SweepVerdicts({PetBuff_Yield = NOW}, NOW).Yield == "expired")
	Check("sweep no clock keeps", Core.SweepVerdicts({PetBuff_Yield = NOW}, 0 / 0).Yield == "live")
	Check("sweep non-table", next(Core.SweepVerdicts(nil, NOW)) == nil)
end

--..7. guard duration from cycle seconds..--
do
	Check("guard 180/45 script", Near(Core.GuardSeconds(180, 45, nil, nil), 240))
	Check("guard 180/45 mirrors", Near(Core.GuardSeconds(nil, nil, 180, 45), 240))
	Check("guard script wins over mirror", Near(Core.GuardSeconds(100, 20, 180, 45), 135))
	Check("guard defaults", Near(Core.GuardSeconds(nil, nil, nil, nil), PetBalance.DEFAULT_DAY_SECONDS + PetBalance.DEFAULT_NIGHT_SECONDS + PetBalance.GUARD.CycleExtra))
	Check("guard cap 600", Near(Core.GuardSeconds(1000, 1000, nil, nil), 600))
	Check("guard NaN night -> mirror", Near(Core.GuardSeconds(180, 0 / 0, 999, 45), 240))
	Check("guard string attrs -> defaults", Near(Core.GuardSeconds("180", "45", nil, nil), 205))
	Check("guard zero -> 1 s floor (DayNightCycle rule)", Near(Core.GuardSeconds(0, 0, nil, nil), 17))
	local d, n = Core.CycleSeconds(nil, 45, 180, nil)
	Check("CycleSeconds mix", d == 180 and n == 45)
	--.. the live edit DataModel's DayNightCycle attributes (read only)
	local cycle = game:GetService("ServerScriptService"):FindFirstChild("DayNightCycle")
	local expect = cycle and (math.max(1, cycle:GetAttribute("DayDurationSeconds") or 180) + math.max(1, cycle:GetAttribute("NightDurationSeconds") or 10) + 15)
	Check("GuardSeconds() from the place", expect == nil or Near(Buff.GuardSeconds(), math.min(600, expect)), tostring(Buff.GuardSeconds()) .. " vs " .. tostring(expect))
end

--..8. stateless API on unparented attribute holders..--
local made = {}
local function Holder()
	local m = Instance.new("Model") -- never parented: an attribute holder only
	table.insert(made, m)
	return m
end
local okApi, apiErr = pcall(function()
	--.. Stamp -> Serialize round trip, dropping expired / invalid / duplicate entries
	local m = Holder()
	local written = Buff.StampFromRecord(m, {
		{Kind = "Yield", ExpiresAt = NOW + 50, SourcePetId = "pet-1"},
		{Kind = "Haste", ExpiresAt = NOW - 1}, -- expired
		{Kind = "Guard", ExpiresAt = NOW + 200, Charges = 0}, -- invalid
		{Kind = "Guard", ExpiresAt = NOW + 200, Charges = 1, SourcePetId = "pet-2"},
		{Kind = "Yield", ExpiresAt = NOW + 80}, -- duplicate
		{Kind = "Haste", ExpiresAt = NOW + 60},
	}, NOW)
	Check("stamp count", written == 3, written)
	Check("stamp Yield attrs", m:GetAttribute("PetBuff_Yield") == NOW + 50 and m:GetAttribute("PetBuff_YieldSrc") == "pet-1")
	Check("stamp Haste attrs", m:GetAttribute("PetBuff_Haste") == NOW + 60 and m:GetAttribute("PetBuff_HasteSrc") == nil)
	Check("stamp Guard attrs", m:GetAttribute("PetBuff_Guard") == NOW + 200 and m:GetAttribute("PetBuff_GuardSrc") == "pet-2" and m:GetAttribute("PetBuff_GuardCharges") == 1)
	local s = Buff.Serialize(m, NOW)
	Check("serialize count", s and #s == 3, s and #s)
	local byKind = {}
	for _, r in ipairs(s or {}) do byKind[r.Kind] = r end
	Check("serialize Yield", byKind.Yield and byKind.Yield.ExpiresAt == NOW + 50 and byKind.Yield.SourcePetId == "pet-1" and byKind.Yield.Charges == nil)
	Check("serialize Haste", byKind.Haste and byKind.Haste.ExpiresAt == NOW + 60 and byKind.Haste.SourcePetId == nil)
	Check("serialize Guard", byKind.Guard and byKind.Guard.ExpiresAt == NOW + 200 and byKind.Guard.Charges == 1)
	local later = Buff.Serialize(m, NOW + 55)
	Check("serialize drops expired", later and #later == 2)
	Check("serialize all expired -> nil", Buff.Serialize(m, NOW + 1000) == nil)
	Check("serialize JSON-safe", pcall(HttpService.JSONEncode, HttpService, s))
	--.. restore of a buff whose source pet is owned by nobody: expiry unchanged after Stamp -> Serialize
	local ghost = Holder()
	Buff.StampFromRecord(ghost, {{Kind = "Yield", ExpiresAt = NOW + 42.5, SourcePetId = "ghost-pet-id"}}, NOW)
	local g = Buff.Serialize(ghost, NOW + 10)
	Check("unowned source keeps its expiry", g and g[1].ExpiresAt == NOW + 42.5 and g[1].SourcePetId == "ghost-pet-id")
	--.. invalid input writes nothing
	local blank = Holder()
	Check("stamp non-table", Buff.StampFromRecord(blank, "nope", NOW) == 0)
	Check("stamp all invalid", Buff.StampFromRecord(blank, {{Kind = "Yield", ExpiresAt = NOW - 5}}, NOW) == 0)
	Check("nothing written", next(blank:GetAttributes()) == nil)
	Check("stamp non-instance", Buff.StampFromRecord({}, {{Kind = "Yield", ExpiresAt = NOW + 5}}, NOW) == 0)
	local junk = Holder()
	junk:SetAttribute("PetBuff_Yield", "abc")
	Check("serialize garbage attr -> nil", Buff.Serialize(junk, NOW) == nil)
	Check("serialize non-instance -> nil", Buff.Serialize({}, NOW) == nil)

	--.. ModifiersOf: live Yield / Haste only, Guard never
	local mods = Buff.ModifiersOf(m, NOW)
	local mk = {}
	for _, x in ipairs(mods) do mk[x.Kind] = x end
	Check("mods Yield", mk.Yield and mk.Yield.Mult == 1.5 and mk.Yield.ExpiresAt == NOW + 50)
	Check("mods Haste", mk.Haste and mk.Haste.Mult == 1.25 and mk.Haste.ExpiresAt == NOW + 60)
	Check("mods never Guard", mk.Guard == nil and #mods == 2)
	Check("mods product 1.875", Near(mk.Yield.Mult * mk.Haste.Mult, 1.875))
	Check("mods after Yield expiry", #Buff.ModifiersOf(m, NOW + 55) == 1)
	Check("mods non-instance", #Buff.ModifiersOf(nil, NOW) == 0)

	--.. ClearCucumber (works before Init / Start): every PetBuff_* off, once
	Check("clear removes", Buff.ClearCucumber(m, "Dev", NOW) == true)
	local left = 0
	for name in pairs(m:GetAttributes()) do
		if name:sub(1, 8) == "PetBuff_" then left += 1 end
	end
	Check("clear leaves no PetBuff_*", left == 0, left)
	Check("clear again -> false", Buff.ClearCucumber(m, "Dev", NOW) == false)
	Check("clear non-instance", Buff.ClearCucumber("x", "Dev") == false)

	--.. not started: grants refused, theft never blocked, eligibility never errors
	local ok, why = Buff.Grant(nil, {PetId = "p"}, "Yield", NOW)
	Check("grant before Start", ok == false and why == "NotReady")
	local shield = Holder()
	shield:SetAttribute("PetBuff_Guard", workspace:GetServerTimeNow() + 100)
	shield:SetAttribute("PetBuff_GuardCharges", 1)
	Check("TryBlockTheft before Start -> false", Buff.TryBlockTheft(shield, nil) == false)
	Check("shield untouched before Start", shield:GetAttribute("PetBuff_GuardCharges") == 1)
	Check("IsEligible bad player", Buff.IsEligible(nil, shield, "Yield", NOW) == false)
	local diag = Buff.GetDiagnostics()
	local flat = true
	for k, v in pairs(diag) do
		if type(k) ~= "string" or type(v) ~= "number" then flat = false end
	end
	Check("diagnostics flat numbers", flat)
	Check("diagnostics NotReady counted", diag.NotReady == 1 and diag.Cleared == 1, HttpService:JSONEncode(diag))
end)
Check("stateless API block ran", okApi, apiErr)
for _, m in ipairs(made) do m:Destroy() end

return ("WP-BUFF core: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
