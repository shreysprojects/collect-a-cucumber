--[[
	WP-MENU_core.lua  (2026-09-22) - pure tests of PetController.Core (pets-system/CONTRACTS.md 2 WP-MENU).
	Run read-only from an edit-peer execute_luau:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-MENU_core.lua"))()
	Loads PetController from the src loopback (:8793) with loadstring; creates no instances. Fakes: a
	PetStats stand-in (AbilityEffect only), PetBalance-shaped Text / Abilities tables; NumberAbbrev is the
	live module. Returns "WP-MENU core: PASS n / FAIL m: <first failures>".
]]
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local source = HttpService:GetAsync("http://127.0.0.1:8793/StarterGui.CucumberMenus.PetController.lua")
local chunk, compileError = loadstring(source)
if not chunk then return "WP-MENU core: FAIL 1: compile " .. tostring(compileError) end
local PetController = chunk()
local Core = PetController.Core
local NumberAbbrev = require(ReplicatedStorage.Modules.NumberAbbrev)

local pass, fail, failures = 0, 0, {}
local function check(name, condition, detail)
	if condition then
		pass += 1
	else
		fail += 1
		if #failures < 12 then table.insert(failures, name .. (detail and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function ids(list)
	local out = {}
	for i, pet in ipairs(list) do out[i] = pet.Id end
	return table.concat(out, ",")
end

local function pet(id, income, dps, rarity, acquired, extra)
	local view = {Id = id, Pet = "Cat", DisplayName = "Pet " .. id, Rarity = rarity or "Common", Material = "", Mutations = {},
		AcquiredAt = acquired or 0, Equipped = false, Status = "Reserve", AbilityRemaining = 60,
		Stats = {Income = income, ShotDamage = 3, ShotInterval = 2.5, DPS = dps, Range = 26, Ability = "Yield", AbilityChance = 0.01, AbilityDuration = 90, Fighter = false}}
	for k, v in pairs(extra or {}) do view[k] = v end
	return view
end

--..Sort..--
do
	local pets = {pet("b", 5, 1), pet("a", 5, 1), pet("c", 5, 2), pet("d", 9, 0), pet("e", 1, 9)}
	local before = ids(pets)
	check("sort income", ids(Core.Sort(pets, "Income")) == "d,c,a,b,e", ids(Core.Sort(pets, "Income")))
	check("sort leaves input", ids(pets) == before)
	check("sort combat", ids(Core.Sort(pets, "Combat")) == "e,c,a,b,d", ids(Core.Sort(pets, "Combat")))
	check("sort unknown mode = income", ids(Core.Sort(pets, "Bogus")) == "d,c,a,b,e")
	local rarity = {pet("r1", 1, 1, "Common"), pet("r2", 1, 1, "Mythical"), pet("r3", 5, 1, "Rare"), pet("r4", 9, 1, "Rare"), pet("r0", 1, 1, "Mythical"), pet("r5", 99, 1, "Nope")}
	check("sort rarity", ids(Core.Sort(rarity, "Rarity")) == "r0,r2,r4,r3,r1,r5", ids(Core.Sort(rarity, "Rarity")))
	check("sort rarity custom order", ids(Core.Sort(rarity, "Rarity", {Common = 9})) == "r1,r5,r4,r3,r0,r2", ids(Core.Sort(rarity, "Rarity", {Common = 9})))
	local newest = {pet("n2", 1, 1, nil, 100), pet("n1", 1, 1, nil, 100), pet("n3", 1, 1, nil, 300), pet("n0", 1, 1, nil, 0)}
	check("sort newest", ids(Core.Sort(newest, "Newest")) == "n3,n1,n2,n0", ids(Core.Sort(newest, "Newest")))
	local garbage = {pet("g1", 0 / 0, math.huge, nil, 0 / 0), pet("g2", 2, 1), {Id = "g3"}, "junk", pet("g0", -math.huge, 0)}
	local ok, sorted = pcall(Core.Sort, garbage, "Income")
	check("sort garbage no error", ok, sorted)
	check("sort garbage finite order", ok and ids(sorted) == "g2,g0,g1,g3", ok and ids(sorted))
	check("sort nil", #Core.Sort(nil, "Income") == 0)
end

--..Filter..--
do
	local pets = {pet("a", 1, 1, nil, 0, {Equipped = true}), pet("b", 1, 1), pet("c", 1, 1, nil, 0, {Equipped = true})}
	check("filter all", ids(Core.Filter(pets, "All")) == "a,b,c")
	check("filter active", ids(Core.Filter(pets, "Active")) == "a,c")
	check("filter reserve", ids(Core.Filter(pets, "Reserve")) == "b")
	check("filter set overrides flag", ids(Core.Filter(pets, "Active", {b = true})) == "b")
	check("filter unknown = all", #Core.Filter(pets, "Bogus") == 3)
end

--..ApplyState..--
local function full(revision, generation, extra)
	local payload = {Kind = "Full", Revision = revision, Generation = generation, Slots = 6, ServerTime = 1000,
		EquippedIds = {"p1", "p2"}, Pets = {pet("p1", 1, 1, nil, 0, {Equipped = true, Status = "Active"}), pet("p2", 2, 1, nil, 0, {Equipped = true, Status = "Active"}), pet("p3", 3, 1)},
		Totals = {Pet = 3, Cucumber = 10, CucumberBase = 8, Total = 13}, CombatLocked = false}
	for k, v in pairs(extra or {}) do payload[k] = v end
	return payload
end
do
	local s, need = Core.ApplyState(nil, full(5, 1))
	check("full from nil", s and s.Revision == 5 and s.Generation == 1 and not need)
	check("full pets map", s and s.Pets.p1 and s.Pets.p3 and s.Pets.p2.Stats.Income == 2)
	check("full equipped", s and table.concat(s.EquippedIds, ",") == "p1,p2")
	check("full totals", s and s.Totals.Total == 13 and s.Totals.CucumberBase == 8)
	check("full asOf", s and s.AsOf.p1 == 1000)

	local delta = {Kind = "Delta", Revision = 6, BaseRevision = 5, Generation = 1, ServerTime = 1010,
		EquippedIds = {"p1", "p2", "p3"}, Upserts = {pet("p3", 3, 1, nil, 0, {Equipped = true, Status = "Active"})}, Removed = {"p2"},
		Totals = {Pet = 4, Cucumber = 10, CucumberBase = 8, Total = 14}, CombatLocked = true}
	local s2, need2 = Core.ApplyState(s, delta)
	check("delta applied", s2 and s2.Revision == 6 and not need2)
	check("delta upsert", s2 and s2.Pets.p3.Status == "Active" and s2.AsOf.p3 == 1010 and s2.AsOf.p1 == 1000)
	check("delta removed", s2 and s2.Pets.p2 == nil and s2.AsOf.p2 == nil)
	check("delta equipped", s2 and table.concat(s2.EquippedIds, ",") == "p1,p2,p3")
	check("delta totals + lock", s2 and s2.Totals.Total == 14 and s2.CombatLocked == true)
	check("delta did not mutate input", s.Revision == 5 and s.Pets.p2 ~= nil and s.CombatLocked == false and s.Pets.p3.Status == "Reserve")

	local gap = {Kind = "Delta", Revision = 9, BaseRevision = 8, Generation = 1, Upserts = {pet("p9", 1, 1)}}
	local s3, need3 = Core.ApplyState(s2, gap)
	check("gap keeps state + needFull", s3 == s2 and need3 == true)
	local stale = {Kind = "Delta", Revision = 6, BaseRevision = 5, Generation = 1, Upserts = {pet("p9", 1, 1)}}
	local s4, need4 = Core.ApplyState(s2, stale)
	check("stale delta ignored", s4 == s2 and need4 == false)
	local newGen = {Kind = "Delta", Revision = 7, BaseRevision = 6, Generation = 2, Upserts = {pet("p9", 1, 1)}}
	local s5, need5 = Core.ApplyState(s2, newGen)
	check("new generation drops state", s5 == nil and need5 == true)
	local s6, need6 = Core.ApplyState(nil, gap)
	check("delta without state -> NeedFull", s6 == nil and need6 == true)

	local ack = {Kind = "Delta", Revision = 0, BaseRevision = 0, RequestId = "x", Result = {Ok = false, Error = "Unavailable", Action = "GetState"}, ServerTime = 1}
	local s7, need7 = Core.ApplyState(nil, ack)
	check("ack without state: no NeedFull", s7 == nil and need7 == false)
	local s8, need8 = Core.ApplyState(s2, {Kind = "Delta", Revision = 7, BaseRevision = 6, Generation = 1, RequestId = "y", Result = {Ok = false, Error = "SlotsFull", Action = "Equip"}})
	check("contiguous ack advances revision", s8 and s8.Revision == 7 and s8.Pets.p3 and not need8)
	local s9, need9 = Core.ApplyState(s2, {Kind = "Delta", Revision = 6, BaseRevision = 5, Generation = 1, RequestId = "z", Result = {Ok = true, Action = "Equip"}})
	check("old ack ignored", s9 == s2 and not need9)

	local s10, need10 = Core.ApplyState(s2, {Kind = "Totals", Totals = {Pet = 1, Cucumber = 2, CucumberBase = 2, Total = 3}, ServerTime = 2000})
	check("totals msg updates footer only", s10 and s10.Totals.Total == 3 and s10.Revision == s2.Revision and not need10 and s2.Totals.Total == 14)
	local s11, need11 = Core.ApplyState(nil, {Kind = "Totals", Totals = {Pet = 1}})
	check("totals msg without state", s11 == nil and not need11)

	local s12, need12 = Core.ApplyState(s2, full(4, 1))
	check("stale full ignored", s12 == s2 and not need12)
	local s13 = Core.ApplyState(s2, full(1, 7))
	check("full with new generation accepted", s13 and s13.Generation == 7 and s13.Revision == 1)

	local messy = full(3, 1, {Slots = 0 / 0, EquippedIds = {"p1", "p1", 5, "p2", "p3", "a", "b", "c", "d", "e"},
		Pets = {pet("p1", 1, 1), "junk", {Id = ""}, {Id = string.rep("x", 65)}, pet("p2", 1, 1)}, Totals = {Pet = 0 / 0, Total = math.huge}, ServerTime = 0 / 0})
	local s14 = Core.ApplyState(nil, messy, 555)
	local count = 0
	if s14 then for _ in pairs(s14.Pets) do count += 1 end end
	check("messy full: valid pets only", count == 2, count)
	check("messy full: slots default + ids deduped/capped", s14 and s14.Slots == 6 and #s14.EquippedIds == 6 and s14.EquippedIds[2] == "p2", s14 and table.concat(s14.EquippedIds, ","))
	check("messy full: totals finite", s14 and s14.Totals.Pet == 0 and s14.Totals.Total == 0)
	check("messy full: asOf fallback", s14 and s14.AsOf.p1 == 555)
	local s15, need15 = Core.ApplyState(s2, {Kind = "Delta", Revision = 0 / 0, BaseRevision = 6, Generation = 1, Upserts = {}})
	check("NaN revision ignored", s15 == s2 and not need15)
	check("non-table payload", select(1, Core.ApplyState(s2, "x")) == s2)

	-- 2026-09-22 (review): PetService's not-ready Full (empty placeholder roster + Result.Ok == false) is not state
	local function refusal(revision, generation, code)
		return {Kind = "Full", Revision = revision, Generation = generation, RequestId = "g1", Slots = 6, EquippedIds = {}, Pets = {},
			Totals = {Pet = 0, Cucumber = 0, CucumberBase = 0, Total = 0}, CombatLocked = false, ServerTime = 1,
			Result = {Ok = false, Action = "GetState", Error = code}}
	end
	check("IsRefusal: not-ready Full", Core.IsRefusal(refusal(1, 0, "NotLoaded")) == true)
	check("IsRefusal: ordinary Full", Core.IsRefusal(full(1, 1)) == false)
	check("IsRefusal: Full with Ok result", Core.IsRefusal(full(1, 1, {Result = {Ok = true, Action = "GetState"}})) == false)
	check("IsRefusal: refused Delta is not a Full refusal", Core.IsRefusal({Kind = "Delta", Result = {Ok = false, Action = "GetState"}}) == false)
	check("IsRefusal: junk", Core.IsRefusal(nil) == false and Core.IsRefusal({Kind = "Full", Result = "x"}) == false)
	local r1, rneed1 = Core.ApplyState(nil, refusal(1, 1, "MigrationFailed"))
	check("MigrationFailed Full leaves no state", r1 == nil and rneed1 == false)
	local lock1 = Core.LockState(r1, false)
	check("MigrationFailed Full: actions stay disabled", lock1.Enabled == false and lock1.Reason == "Loading")
	local vm1 = Core.BuildViewModel(r1, {}, {})
	check("MigrationFailed Full: panel not loaded, no empty-roster text", vm1.Loaded == false and vm1.ActionsEnabled == false and vm1.EmptyText == nil and vm1.Subtitle == "")
	local r2, rneed2 = Core.ApplyState(nil, refusal(1, 0, "NotLoaded"))
	check("NotLoaded Full leaves no state", r2 == nil and rneed2 == false)
	local r3, rneed3 = Core.ApplyState(s2, refusal(50, 1, "Closing"))
	check("refusal keeps the held state", r3 == s2 and rneed3 == false and s2.Revision == 6)
	local r4 = Core.ApplyState(s2, refusal(50, 9, "NotLoaded"))
	check("refusal with another generation keeps the held state", r4 == s2)
	local r5 = Core.ApplyState(r2, full(3, 1))
	check("real Full after a refusal is adopted", r5 and r5.Revision == 3 and r5.Pets.p1 ~= nil)
	check("StateErrorText NotLoaded = loading", Core.StateErrorText("NotLoaded", nil) == Core.LOADING_TEXT)
	check("StateErrorText MigrationFailed", Core.StateErrorText("MigrationFailed", nil) == Core.ERROR_TEXT.MigrationFailed)
	check("StateErrorText Closing", Core.StateErrorText("Closing", nil) == Core.ERROR_TEXT.Closing)
	check("StateErrorText unknown", Core.StateErrorText(nil, nil) == Core.ERROR_TEXT.BadRequest)
end

--..LockState..--
do
	local l1 = Core.LockState(nil, false)
	check("lock: loading", l1.Enabled == false and l1.Banner == false and l1.Reason == "Loading")
	local l2 = Core.LockState({CombatLocked = true}, false)
	check("lock: combat banner", l2.Enabled == false and l2.Banner == true and l2.Reason == "CombatLocked")
	local l3 = Core.LockState({CombatLocked = false}, true)
	check("lock: pending", l3.Enabled == false and l3.Banner == false and l3.Reason == "Pending")
	local l4 = Core.LockState({CombatLocked = false}, false)
	check("lock: free", l4.Enabled == true and l4.Banner == false)
end

--..BuildViewModel..--
local FakeStats = {AbilityEffect = function(kind, guard) return "effect:" .. kind .. ":" .. tostring(guard) end}
local ENV = {
	Now = 1010,
	Abbrev = NumberAbbrev.Abbrev,
	Text = {LockBanner = "LOCKED!", Unavailable = "UNAV", NextRoll = "Next in %s", InventoryFull = "FULL"},
	Abilities = {Yield = {DisplayName = "Lucky Harvest"}, Guard = {DisplayName = "Leaf Shield"}, None = {DisplayName = "Fighter"}},
	Period = 60,
	Stats = FakeStats,
}
do
	local base = full(5, 1)
	base.Pets[1].AbilityRemaining = 42
	base.Pets[3].Stats.Ability = "None"
	base.Pets[3].Stats.Fighter = true -- a real fighter (PetStats: Ability None <=> Fighter)
	base.Pets[3].Material = "Golden"
	base.Pets[3].Mutations = {"NEON", "VOID", "ROYAL"}
	base.Pets[2].Stats.Ability = "Guard"
	base.Pets[2].Stats.AbilityDuration = 240
	base.Pets[2].Status = "Unavailable"
	local s = Core.ApplyState(nil, base)
	local vm = Core.BuildViewModel(s, {Sort = "Income", Filter = "All"}, ENV)
	check("vm loaded + subtitle", vm.Loaded and vm.Subtitle == "2 / 6 ACTIVE", vm.Subtitle)
	check("vm cards sorted", #vm.Cards == 3 and vm.Cards[1].Id == "p3" and vm.Cards[3].Id == "p1")
	check("vm default selection = first card", vm.SelectedId == "p3" and vm.Cards[1].Selected and not vm.Cards[2].Selected)
	check("vm slots", #vm.Slots == 6 and vm.Slots[1].Id == "p1" and vm.Slots[2].Id == "p2" and vm.Slots[3].Id == nil and vm.Slots[6].Index == 6)
	check("vm known", vm.Known.p1 and vm.Known.p2 and vm.Known.p3)
	check("vm footer", vm.Footer.Pet == "$3/s" and vm.Footer.Cucumber == "$10/s" and vm.Footer.Total == "$13/s", vm.Footer.Pet)
	check("vm card rate + equipped", vm.Cards[3].RateText == "$1/s" and vm.Cards[3].Equipped == true and vm.Cards[1].Equipped == false)
	-- 2026-09-22 (review #11): every chip goes to the view, which fits them by width ("+N" there)
	check("vm chips uncapped", #vm.Cards[1].Chips == 4 and vm.Cards[1].Chips[1].Text == "Golden" and vm.Cards[1].Chips[4].Text == "ROYAL"
		and vm.Cards[1].Chips[2].Word == "NEON", vm.Cards[1].Chips[4] and vm.Cards[1].Chips[4].Text)
	check("vm unavailable tag", vm.Cards[2].StatusText == "UNAV", vm.Cards[2].StatusText)
	check("vm actions enabled", vm.ActionsEnabled == true and vm.Banner.Visible == false)
	-- fighter in reserve on a 2/6 roster
	local d = vm.Details
	check("details fighter", d and d.AbilityName == "Fighter" and d.AbilityChance == "" and d.NextRoll == "" and d.AbilityEffect == "effect:None:nil")
	check("details equip", d and d.EquipText == "EQUIP" and d.EquipAction == "Equip" and d.EquipEnabled == true)
	check("details traits", d and #d.Traits == 4 and d.Traits[1] == "Golden")
	check("details rate note", d and d.Rate == "$3/s" and d.RateNote == "when active")
	check("details combat line", d and d.Combat == "3 dmg every 2.5s  ·  1 nominal DPS  ·  range 26", d and d.Combat)
	-- equipped yield pet with a countdown
	local vm2 = Core.BuildViewModel(s, {Sort = "Income", Filter = "All", SelectedId = "p1"}, ENV)
	local d2 = vm2.Details
	check("details selected kept", vm2.SelectedId == "p1" and vm2.Slots[1].Selected == true)
	check("details unequip", d2 and d2.EquipText == "UNEQUIP" and d2.EquipAction == "Unequip" and d2.EquipEnabled)
	check("details countdown", d2 and d2.NextRoll == "Next in 0:32", d2 and d2.NextRoll)
	check("details chance", d2 and d2.AbilityChance == "1% chance each active minute", d2 and d2.AbilityChance)
	check("details yield name/effect", d2 and d2.AbilityName == "Lucky Harvest" and d2.AbilityEffect == "effect:Yield:nil")
	-- guard effect receives the guard seconds; unavailable roster pet
	local d3 = Core.BuildViewModel(s, {SelectedId = "p2"}, ENV).Details
	check("details guard seconds", d3 and d3.AbilityEffect == "effect:Guard:240", d3 and d3.AbilityEffect)
	check("details unavailable rolls paused", d3 and d3.NextRoll == "Chance rolls paused" and d3.StatusText == "UNAV")
	-- filters + empty texts
	local vmActive = Core.BuildViewModel(s, {Filter = "Active"}, ENV)
	check("vm filter active", #vmActive.Cards == 2 and vmActive.Filter == "Active")
	local empty = Core.ApplyState(nil, full(1, 1, {Pets = {}, EquippedIds = {}}))
	local vmEmpty = Core.BuildViewModel(empty, {}, ENV)
	check("vm empty inventory", vmEmpty.EmptyText == Core.EMPTY_TEXT.None and vmEmpty.Details == nil and vmEmpty.SelectedId == nil)
	local reserveEmpty = Core.ApplyState(nil, full(1, 1, {Pets = {pet("p1", 1, 1, nil, 0, {Equipped = true})}, EquippedIds = {"p1"}}))
	check("vm reserve empty", Core.BuildViewModel(reserveEmpty, {Filter = "Reserve"}, ENV).EmptyText == Core.EMPTY_TEXT.Reserve)
	-- lock banner state
	local locked = Core.ApplyState(nil, full(1, 1, {CombatLocked = true}))
	local vmLocked = Core.BuildViewModel(locked, {SelectedId = "p3"}, ENV)
	check("vm lock banner", vmLocked.Banner.Visible and vmLocked.Banner.Text == "LOCKED!" and vmLocked.ActionsEnabled == false)
	check("vm lock disables equip", vmLocked.Details and vmLocked.Details.EquipEnabled == false and vmLocked.Details.EquipText == "EQUIP")
	local vmPending = Core.BuildViewModel(s, {Pending = true}, ENV)
	check("vm pending disables", vmPending.ActionsEnabled == false and vmPending.Banner.Visible == false)
	-- full roster: unequip-first flow
	local fullRoster = full(1, 1)
	fullRoster.Pets = {}
	fullRoster.EquippedIds = {}
	for i = 1, 7 do
		table.insert(fullRoster.Pets, pet("q" .. i, i, 1, nil, 0, {Equipped = i <= 6, Status = i <= 6 and "Active" or "Reserve"}))
		if i <= 6 then table.insert(fullRoster.EquippedIds, "q" .. i) end
	end
	local sFull = Core.ApplyState(nil, fullRoster)
	local d4 = Core.BuildViewModel(sFull, {SelectedId = "q7"}, ENV).Details
	check("full roster asks to unequip first", d4 and d4.EquipText == "UNEQUIP ONE FIRST" and d4.EquipEnabled == false and d4.EquipAction == nil)
	check("full roster subtitle", Core.BuildViewModel(sFull, {}, ENV).Subtitle == "6 / 6 ACTIVE")
	local invalid = Core.ApplyState(nil, full(1, 1, {Pets = {pet("z", 1, 1, nil, 0, {Status = "Invalid"})}, EquippedIds = {}}))
	local d5 = Core.BuildViewModel(invalid, {}, ENV).Details
	check("invalid pet cannot equip", d5 and d5.EquipText == "UNAVAILABLE" and d5.EquipEnabled == false)
	-- 2026-09-22 (review #10): an unknown species (PetStats.EmptyStats: Ability None, Fighter false, 0 stats) is not
	-- a fighter: "No ability" (no ABILITIES row -> white), no effect / chance / roll line, and "Does not fight"
	local function unknown(extra, stats, dropFighter)
		local v = pet("u", 0, 0, nil, 0, extra)
		v.Stats = {Income = 0, ShotDamage = 0, ShotInterval = 0, DPS = 0, Range = 0, Ability = "None", AbilityChance = 0, Fighter = false}
		for k, value in pairs(stats or {}) do v.Stats[k] = value end
		if dropFighter then v.Stats.Fighter = nil end
		return Core.BuildViewModel(Core.ApplyState(nil, full(1, 1, {Pets = {v}, EquippedIds = {}})), {}, ENV).Details
	end
	local du = unknown({Status = "Invalid"})
	check("invalid: no ability", du and du.AbilityName == Core.NO_ABILITY_TEXT and du.AbilityKind == "NoAbility" and ENV.Abilities[du.AbilityKind] == nil, du and du.AbilityName)
	check("invalid: no fighter effect / chance / roll", du and du.AbilityEffect == "" and du.AbilityChance == "" and du.NextRoll == "", du and du.AbilityEffect)
	check("invalid: does not fight", du and du.Combat == Core.NO_COMBAT_TEXT and not du.Combat:find("dmg", 1, true), du and du.Combat)
	local duf = unknown({Status = "Invalid"}, {Fighter = true}) -- PetService's InvalidStats fallback says Fighter = true
	check("invalid with Fighter = true: still no ability", duf and duf.AbilityName == Core.NO_ABILITY_TEXT and duf.AbilityEffect == "")
	local dn = unknown({Status = "Reserve"}, {ShotDamage = 2, ShotInterval = 2, DPS = 1, Range = 20})
	check("None without Fighter flag: no ability", dn and dn.AbilityName == Core.NO_ABILITY_TEXT and dn.AbilityEffect == "" and dn.Combat:find("dmg", 1, true) ~= nil, dn and dn.AbilityName)
	local dm = unknown({Status = "Reserve"}, nil, true)
	check("None with a missing Fighter field: no ability", dm and dm.AbilityName == Core.NO_ABILITY_TEXT)
	local dfr = unknown({Status = "Reserve"}, {Fighter = true, ShotDamage = 3, ShotInterval = 2.5, DPS = 1.2, Range = 26})
	check("real fighter keeps the fighter line", dfr and dfr.AbilityName == "Fighter" and dfr.AbilityKind == "None" and dfr.AbilityEffect == "effect:None:nil", dfr and dfr.AbilityEffect)
	local okBareInvalid, bareInvalid = pcall(function()
		local v = pet("u2", 0, 0, nil, 0, {Status = "Invalid"})
		v.Stats = {Ability = "None", Fighter = false}
		return Core.BuildViewModel(Core.ApplyState(nil, full(1, 1, {Pets = {v}, EquippedIds = {}})), {}, nil).Details
	end)
	check("invalid pet with a bare env", okBareInvalid and bareInvalid and bareInvalid.AbilityName == Core.NO_ABILITY_TEXT, okBareInvalid and "" or bareInvalid)
	-- FooterOf (the Totals fast path) = BuildViewModel's footer
	local footerOf = Core.FooterOf({Pet = 3, Cucumber = 10, CucumberBase = 8, Total = 13}, ENV)
	check("FooterOf texts", footerOf.Pet == "$3/s" and footerOf.Cucumber == "$10/s" and footerOf.Total == "$13/s", footerOf.Pet)
	check("FooterOf = vm footer", footerOf.Pet == vm.Footer.Pet and footerOf.Total == vm.Footer.Total)
	local footerBad = Core.FooterOf({Pet = 0 / 0, Total = math.huge}, nil)
	check("FooterOf bad input", footerBad.Pet == "$0/s" and footerBad.Total == "$0/s" and Core.FooterOf(nil, ENV).Cucumber == "$0/s", footerBad.Pet)
	-- no state
	local vmNil = Core.BuildViewModel(nil, {}, ENV)
	check("vm nil state", vmNil.Loaded == false and #vmNil.Slots == 6 and #vmNil.Cards == 0 and vmNil.ActionsEnabled == false)
	-- missing env pieces never error
	local okBare, vmBare = pcall(Core.BuildViewModel, s, nil, nil)
	check("vm bare env", okBare and vmBare.Details ~= nil and vmBare.Details.AbilityEffect == "", okBare and "" or vmBare)
	local badEnv = table.clone(ENV)
	badEnv.Text = {NextRoll = "%d %d"}
	local d6 = Core.BuildViewModel(s, {SelectedId = "p1"}, badEnv).Details
	check("bad NextRoll template falls back", d6 and d6.NextRoll == "Next chance roll in 0:32", d6 and d6.NextRoll)
end

--..NextRollText / FormatCountdown / ids / errors..--
do
	local active = pet("a", 1, 1, nil, 0, {Status = "Active", AbilityRemaining = 10})
	check("nextroll clamps at 0:00", Core.NextRollText(active, 100, 200, ENV, true) == "Next in 0:00")
	check("nextroll no asOf", Core.NextRollText(active, nil, 200, ENV, true) == "Next in 0:10")
	local reserve = pet("r", 1, 1, nil, 0, {Status = "Reserve"})
	check("nextroll reserve", Core.NextRollText(reserve, 100, 200, ENV, false) == "Equip it to start its chance rolls")
	local cases = {{0, "0:00"}, {-5, "0:00"}, {0 / 0, "0:00"}, {math.huge, "0:00"}, {0.1, "0:01"}, {59.2, "1:00"}, {60, "1:00"}, {61, "1:01"}, {125, "2:05"}, {1e9, "99:59"}}
	for _, case in ipairs(cases) do
		check("countdown " .. tostring(case[1]), Core.FormatCountdown(case[1]) == case[2], Core.FormatCountdown(case[1]))
	end
	local seen, unique, maxLength = {}, true, 0
	for _ = 1, 5000 do
		local id = Core.NewRequestId()
		if type(id) ~= "string" or seen[id] then unique = false end
		seen[id] = true
		maxLength = math.max(maxLength, #id)
	end
	check("request ids unique", unique)
	check("request ids <= 40 chars", maxLength <= 40 and maxLength >= 3, maxLength)
	check("error SlotsFull", Core.ErrorText("SlotsFull", ENV) == Core.ERROR_TEXT.SlotsFull)
	check("error CombatLocked uses banner text", Core.ErrorText("CombatLocked", ENV) == "LOCKED!")
	check("error InventoryFull uses TEXT", Core.ErrorText("InventoryFull", ENV) == "FULL")
	check("error unknown", Core.ErrorText("???", nil) == Core.ERROR_TEXT.BadRequest)
	check("error default text without env", Core.ErrorText("CombatLocked", nil) == Core.DEFAULT_TEXT.LockBanner)
	local codes = {"NotLoaded", "Closing", "CombatLocked", "NotOwned", "SlotsFull", "Unavailable", "RateLimited", "BadRequest", "NoPlot", "MigrationFailed", "InventoryFull"}
	local allMapped = true
	for _, code in ipairs(codes) do
		local text = Core.ErrorText(code, nil)
		if type(text) ~= "string" or text == "" or (code ~= "BadRequest" and text == Core.ERROR_TEXT.BadRequest) then allMapped = false end
	end
	check("every contract error code has its own text", allMapped)
end

return ("WP-MENU core: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
