-- WP-PETSVC core tests (2026-09-22): PetService.Core pure functions with plain-table fakes. No instances.
local HttpService = game:GetService("HttpService")
local H = loadstring(HttpService:GetAsync("http://127.0.0.1:8795/WP-PETSVC_harness.lua"))()
local C = H.Checker("core")
local PS, fakes = H.LoadPetService()
local Core = PS.Core
local PetStats = fakes.PetStats

local function Count(list, pred)
	local n = 0
	for _, v in ipairs(list) do if pred(v) then n += 1 end end
	return n
end

--..ValidateRequest..--
C.Run("validate", function()
	local ok, err = Core.ValidateRequest(nil)
	C.Check(ok == false and err == "BadRequest", "nil request refused")
	ok, err = Core.ValidateRequest("GetState")
	C.Check(ok == false and err == "BadRequest", "string request refused")
	local okG, cleaned = Core.ValidateRequest({RequestId = "r1", Action = "GetState", UserId = 5, Stats = {}})
	C.Check(okG and cleaned.Action == "GetState" and cleaned.RequestId == "r1", "GetState ok")
	C.Check(cleaned.UserId == nil and cleaned.Stats == nil, "extra fields dropped")
	C.Check(Core.ValidateRequest({RequestId = string.rep("x", 40), Action = "GetState"}) == true, "RequestId 40 ok")
	C.Check(Core.ValidateRequest({RequestId = string.rep("x", 41), Action = "GetState"}) == false, "RequestId 41 refused")
	C.Check(Core.ValidateRequest({RequestId = "", Action = "GetState"}) == false, "empty RequestId refused")
	C.Check(Core.ValidateRequest({RequestId = 5, Action = "GetState"}) == false, "numeric RequestId refused")
	C.Check(Core.ValidateRequest({RequestId = "r", Action = "Delete"}) == false, "unknown action refused")
	C.Check(Core.ValidateRequest({RequestId = "r", Action = "Equip"}) == false, "Equip without PetId refused")
	C.Check(Core.ValidateRequest({RequestId = "r", Action = "Equip", PetId = string.rep("p", 65)}) == false, "PetId 65 refused")
	C.Check(Core.ValidateRequest({RequestId = "r", Action = "Unequip", PetId = 12}) == false, "numeric PetId refused")
	local okE, cleanedE = Core.ValidateRequest({RequestId = "r", Action = "Equip", PetId = "abc", SortMode = "Income"})
	C.Check(okE and cleanedE.PetId == "abc" and cleanedE.SortMode == nil, "Equip ok, SortMode not read")
	C.Check(Core.ValidateRequest({RequestId = "r", Action = "EquipBest", SortMode = "Rarity"}) == false, "bad SortMode refused")
	C.Check(Core.ValidateRequest({RequestId = "r", Action = "EquipBest"}) == false, "EquipBest needs SortMode")
	local okB, cleanedB = Core.ValidateRequest({RequestId = "r", Action = "EquipBest", SortMode = "Combat", PetId = "x"})
	C.Check(okB and cleanedB.SortMode == "Combat" and cleanedB.PetId == nil, "EquipBest ok, PetId not read")
end)

--..Limiter..--
C.Run("limiter", function()
	local L = Core.NewLimiter(1, 2)
	C.Check(L:Take(0) and L:Take(0), "burst of 2")
	C.Check(not L:Take(0), "third in the same instant refused")
	C.Check(not L:Take(0.5), "half a token is not enough")
	C.Check(L:Take(1.0), "refilled at 1/s")
	C.Check(not L:Take(0 / 0), "NaN clock never refills")
	local R = Core.NewLimiter(2, 4)
	local n = 0
	for _ = 1, 10 do if R:Take(10) then n += 1 end end
	C.Eq(n, 4, "roster burst 4")
	C.Check(R:Take(10.5), "roster refill 2/s")
	C.Check(not R:Take(10.5), "one token per half second")
	C.Check(not R:Take(5), "clock going backwards gives nothing")
	--.. counted takes (2026-09-22, review #5: the EquipBest model budget spends one token per model)
	local M = Core.NewLimiter(2, 12)
	C.Check(M:Take(0, 12), "a whole-team swap (12) fits the burst")
	C.Check(not M:Take(0, 1), "empty after it")
	C.Check(not M:Take(2, 6), "4 tokens after 2 s: a 6-model swap is refused")
	C.Check(M:Take(2, 4), "all or none: the refused take spent nothing")
	C.Check(M:Take(2, 0), "a zero-model take always passes")
	C.Check(not M:Take(3, 3) and M:Take(3, 2), "2 per second refill")
	local D = Core.NewLimiter(1, 2)
	C.Check(D:Take(0, 0 / 0) and D:Take(0) and not D:Take(0), "NaN count = one token")
end)

--..Equip / Unequip..--
C.Run("equip", function()
	local owned = {a = true, b = true, c = true, bad = true}
	local ctx = {Slots = 6, Locked = false, HasPlot = true,
		IsOwned = function(id) return owned[id] == true end,
		IsEquippable = function(id) return id ~= "bad" end}
	local r1 = Core.Equip({}, "a", ctx)
	C.Check(r1 and #r1 == 1 and r1[1] == "a", "equip a")
	local r2 = Core.Equip(r1, "a", ctx)
	C.Check(r2 and #r2 == 1 and r2[1] == "a", "equip a twice = same roster")
	C.Check(r2 ~= r1, "new table returned")
	local _, e = Core.Equip({}, "a", {Slots = 6, Locked = true, HasPlot = true, IsOwned = ctx.IsOwned})
	C.Eq(e, "CombatLocked", "locked")
	_, e = Core.Equip({}, "a", {Slots = 6, Locked = false, HasPlot = false, IsOwned = ctx.IsOwned})
	C.Eq(e, "NoPlot", "no plot")
	_, e = Core.Equip({}, "zzz", ctx)
	C.Eq(e, "NotOwned", "not owned")
	_, e = Core.Equip({}, 5, ctx)
	C.Eq(e, "NotOwned", "non-string id")
	_, e = Core.Equip({}, "bad", ctx)
	C.Eq(e, "Unavailable", "unavailable species")
	_, e = Core.Equip({"x1", "x2", "x3", "x4", "x5", "x6"}, "b", ctx)
	C.Eq(e, "SlotsFull", "slot cap 6")
	local r3 = Core.Equip({"x1", "x2", "x3", "x4", "x5"}, "b", ctx)
	C.Check(r3 and #r3 == 6 and r3[6] == "b", "sixth slot ok")
	local u = Core.Unequip({"a", "b"}, "a")
	C.Check(#u == 1 and u[1] == "b", "unequip a")
	local u2 = Core.Unequip(u, "a")
	C.Check(#u2 == 1 and u2[1] == "b", "unequip absent = same")
end)

--..EquipBest..--
C.Run("equipbest", function()
	local pets = {
		H.PetRec("id-cat2", "Cat"), H.PetRec("id-nope", "Nope"), H.PetRec("id-fox", "Fox"), H.PetRec("id-dog", "Dog"),
		H.PetRec("id-cosmo", "Cosmo Cat"), H.PetRec("id-chest", "Chest"), H.PetRec("id-cat1", "Cat"),
		H.PetRec("id-greg", "Gregory"), H.PetRec("id-bunny", "Bunny"), H.PetRec("id-fox", "Cosmo Cat"), -- duplicate id: first wins
	}
	local spawnable = function(key) return key ~= "Chest" end
	local want = {"id-cosmo", "id-greg", "id-fox", "id-bunny", "id-dog", "id-cat1"}
	local r = Core.EquipBest(pets, PetStats.Calculate, spawnable, "Income", 6)
	C.Eq(table.concat(r, ","), table.concat(want, ","), "income order")
	local shuffled = {}
	for i = #pets, 1, -1 do table.insert(shuffled, pets[i]) end
	-- reversed input: the duplicate id now appears first (Cosmo Cat under id-fox), so compare a clean copy
	local clean = {}
	for i, p in ipairs(pets) do if i ~= 10 then table.insert(clean, p) end end
	local rev = {}
	for i = #clean, 1, -1 do table.insert(rev, clean[i]) end
	local r2 = Core.EquipBest(rev, PetStats.Calculate, spawnable, "Income", 6)
	C.Eq(table.concat(r2, ","), table.concat(want, ","), "same input set -> same roster")
	local rc = Core.EquipBest(clean, PetStats.Calculate, spawnable, "Combat", 6)
	C.Eq(rc[1], "id-cosmo", "combat first")
	C.Eq(rc[2], "id-greg", "combat second")
	C.Check(not table.find(rc, "id-nope") and not table.find(rc, "id-chest"), "invalid / unspawnable never chosen")
	local r3 = Core.EquipBest(clean, PetStats.Calculate, spawnable, "Income", 2)
	C.Eq(table.concat(r3, ","), "id-cosmo,id-greg", "slots respected")
	local r4 = Core.EquipBest({}, PetStats.Calculate, spawnable, "Income", 6)
	C.Eq(#r4, 0, "empty")
end)

--..GrantFromEgg: hatch commit matrix..--
local function Ids(prefix)
	local n = 0
	return function()
		n += 1
		return prefix .. n
	end
end
local function Ctx(extra)
	local ctx = {GenerateId = Ids("pet-"), Now = 1790000000.7, AllowRoster = true, Locked = false, Slots = 6, MaxOwned = 1000,
		IsSpawnable = function() return true end, Index = {ById = {}, BySourceEgg = {}}}
	for k, v in pairs(extra or {}) do ctx[k] = v end
	return ctx
end
local function Base(eggs, pets, roster)
	return {Version = 2, Eggs = eggs, Pets = pets or {}, PetRoster = roster or {}, Cucumbers = {}, Builds = {}}
end
local function EggCount(base, id)
	return Count(base.Eggs, function(r) return type(r) == "table" and r.Id == id end)
end
local function PetCount(base, id)
	return Count(base.Pets, function(r) return type(r) == "table" and r.SourceEggId == id end)
end

C.Run("commit (a) egg absent", function()
	local base = Base({{Id = "other"}})
	local rec, info = Core.GrantFromEgg(base, {EggId = "E1", EggName = "Basic"}, "Cat", Ctx())
	C.Check(rec ~= nil and not info.Duplicate, "(a) granted")
	C.Check((EggCount(base, "E1") == 1) ~= (PetCount(base, "E1") == 1), "(a) egg XOR pet")
	C.Eq(#base.Eggs, 1, "(a) other egg kept")
end)
C.Run("commit (b) egg present", function()
	local base = Base({{Id = "E1", EggName = "Basic"}, {Id = "E2"}})
	local ctx = Ctx()
	local rec, info = Core.GrantFromEgg(base, {EggId = "E1", EggName = "Basic"}, "Cat", ctx)
	C.Check(rec ~= nil and info.EggRemoved == true, "(b) granted, egg removed")
	C.Eq(EggCount(base, "E1"), 0, "(b) egg gone")
	C.Eq(PetCount(base, "E1"), 1, "(b) pet there")
	C.Eq(#base.Eggs, 1, "(b) E2 kept")
	C.Check(ctx.Index.ById[rec.Id] == rec and ctx.Index.BySourceEgg.E1 == rec, "(b) index updated")
end)
C.Run("commit (c) already owned", function()
	local owned = H.PetRec("p1", "Cat", {SourceEggId = "E1"})
	local base = Base({{Id = "E1", EggName = "Basic"}}, {owned})
	local rec, info = Core.GrantFromEgg(base, {EggId = "E1", EggName = "Basic"}, "Fox", Ctx({Index = {ById = {p1 = owned}, BySourceEgg = {E1 = owned}}}))
	C.Check(rec == owned and info.Duplicate == true, "(c) existing pet returned")
	C.Eq(#base.Pets, 1, "(c) no second pet")
	C.Eq(EggCount(base, "E1"), 0, "(c) stale egg record removed")
	local base2 = Base({{Id = "E1"}}, {owned})
	local rec2, info2 = Core.GrantFromEgg(base2, {EggId = "E1"}, "Fox", Ctx({Index = nil}))
	C.Check(rec2 == owned and info2.Duplicate and #base2.Eggs == 0 and #base2.Pets == 1, "(c) scan fallback without index")
end)
C.Run("commit (d) junk before match", function()
	local base = Base({"junk", 42, {Id = "E0"}, {Id = "E1", EggName = "Basic"}})
	local rec = Core.GrantFromEgg(base, {EggId = "E1", EggName = "Basic"}, "Cat", Ctx())
	C.Check(rec ~= nil, "(d) granted")
	C.Check((EggCount(base, "E1") == 1) ~= (PetCount(base, "E1") == 1), "(d) egg XOR pet")
	C.Eq(#base.Eggs, 3, "(d) junk + E0 kept")
	C.Eq(base.Eggs[1], "junk", "(d) junk untouched")
end)
C.Run("commit record shape", function()
	local base = Base({{Id = "E1", EggName = "Basic"}})
	base.PetRoster = nil
	local rec, info = Core.GrantFromEgg(base, {EggId = "E1", EggName = "Basic", Kg = 5, Material = "Golden", Mutations = "neon,ROYAL, Foo"}, "Cat", Ctx())
	C.Eq(rec.Id, "pet-1", "id from GenerateId")
	C.Eq(rec.Pet, "Cat", "Pet key")
	C.Eq(rec.SourceEgg, "Basic Egg", "SourceEgg")
	C.Eq(rec.SourceEggId, "E1", "SourceEggId")
	C.Eq(rec.Material, "Golden", "Material")
	C.Eq(table.concat(rec.Mutations, ","), "NEON,ROYAL,Foo", "Mutations array (unknown kept)")
	C.Eq(rec.EggKg, 5, "EggKg")
	C.Eq(rec.AcquiredAt, 1790000000, "AcquiredAt integer")
	C.Eq(rec.AbilityRemaining, 60, "AbilityRemaining 60")
	C.Check(rec.Pos == nil, "no Pos yet")
	C.Check(type(base.PetRoster) == "table" and base.PetRoster[1] == rec.Id, "missing roster created + equipped")
	C.Check(info.Equipped == true and info.Reserve == false and info.AutoEquipAfterCombat == false, "info equipped")
	local rec2 = Core.GrantFromEgg(base, {EggName = "Desert"}, "Chest", Ctx({GenerateId = Ids("x-")}))
	C.Check(rec2.SourceEggId == nil and rec2.Material == "" and #rec2.Mutations == 0 and rec2.EggKg == nil, "dev grant: no egg id, normal traits")
	C.Eq(rec2.SourceEgg, "Desert Egg", "dev grant SourceEgg")
	local rec3 = Core.GrantFromEgg(base, {}, "Fox", Ctx({GenerateId = Ids("y-")}))
	C.Eq(rec3.SourceEgg, "Basic Egg", "SourceEgg from the species when EggName is missing")
end)
C.Run("commit roster rules", function()
	local base = Base({}, {}, {})
	local rec, info = Core.GrantFromEgg(base, {}, "Cat", Ctx({Locked = true}))
	C.Check(info.Reserve and info.AutoEquipAfterCombat and #base.PetRoster == 0, "locked + free slot -> reserve, after combat")
	local full = {"a", "b", "c", "d", "e", "f"}
	base = Base({}, {}, full)
	rec, info = Core.GrantFromEgg(base, {}, "Cat", Ctx())
	C.Check(info.Reserve and not info.AutoEquipAfterCombat and #base.PetRoster == 6, "full roster -> reserve")
	base = Base({}, {}, {"a", "b", "c", "d", "e", "f"})
	rec, info = Core.GrantFromEgg(base, {}, "Cat", Ctx({Locked = true}))
	C.Check(info.Reserve and not info.AutoEquipAfterCombat, "full + locked -> reserve, no queue")
	base = Base({}, {}, {})
	rec, info = Core.GrantFromEgg(base, {}, "Cat", Ctx({IsSpawnable = function() return false end}))
	C.Check(info.Reserve and not info.AutoEquipAfterCombat and #base.PetRoster == 0, "unspawnable -> reserve")
	--.. (2026-09-22, review #8) the after-combat promise counts the hatches already queued this lock
	base = Base({}, {}, {"a", "b", "c", "d", "e"})
	rec, info = Core.GrantFromEgg(base, {}, "Cat", Ctx({Locked = true, Pending = 0}))
	C.Check(info.Reserve and info.AutoEquipAfterCombat, "5/6 + nothing queued -> promised the last slot")
	rec, info = Core.GrantFromEgg(base, {}, "Cat", Ctx({Locked = true, Pending = 1}))
	C.Check(info.Reserve and not info.AutoEquipAfterCombat and #base.PetRoster == 5, "5/6 + one queued -> no promise (slot taken)")
	base = Base({}, {}, {"a", "b", "c", "d"})
	rec, info = Core.GrantFromEgg(base, {}, "Cat", Ctx({Locked = true, Pending = 1}))
	C.Check(info.AutoEquipAfterCombat, "4/6 + one queued -> still a slot")
	rec, info = Core.GrantFromEgg(base, {}, "Cat", Ctx({Locked = true, Pending = 0 / 0}))
	C.Check(info.AutoEquipAfterCombat, "NaN Pending = 0")
	rec, info = Core.GrantFromEgg(base, {}, "Cat", Ctx({Locked = true, Pending = -3}))
	C.Check(info.AutoEquipAfterCombat, "negative Pending = 0")
	base = Base({}, {}, {"a", "b", "c", "d", "e"})
	rec, info = Core.GrantFromEgg(base, {}, "Cat", Ctx({Pending = 3}))
	C.Check(info.Equipped and #base.PetRoster == 6, "unlocked: Pending never blocks a direct equip")
end)
C.Run("commit refusals", function()
	local pets = {H.PetRec("p1", "Cat"), H.PetRec("p2", "Cat"), H.PetRec("p3", "Cat")}
	local base = Base({{Id = "E1"}}, pets, {"p1"})
	local rec, info = Core.GrantFromEgg(base, {EggId = "E1"}, "Cat", Ctx({MaxOwned = 3}))
	C.Check(rec == nil and info.Error == "InventoryFull", "InventoryFull at the cap")
	C.Check(#base.Pets == 3 and #base.Eggs == 1 and #base.PetRoster == 1, "no mutation at the cap")
	rec, info = Core.GrantFromEgg(base, {EggId = "E1"}, "Unicorn", Ctx())
	C.Check(rec == nil and info.Error == "UnknownSpecies", "unknown species refused")
	C.Check(#base.Pets == 3 and #base.Eggs == 1, "no mutation on unknown species")
	rec, info = Core.GrantFromEgg(nil, {}, "Cat", Ctx())
	C.Check(rec == nil and info.Error ~= nil, "nil base refused")
	local seq = {"p1", "p1", "fresh"}
	local i = 0
	local base2 = Base({}, {H.PetRec("p1", "Cat")})
	rec = Core.GrantFromEgg(base2, {}, "Cat", Ctx({Index = nil, GenerateId = function() i += 1 return seq[i] end}))
	C.Eq(rec and rec.Id, "fresh", "colliding generated id skipped")
end)

--..StepAbility..--
C.Run("step ability", function()
	local rng = Random.new(1)
	local e = {{Id = "a", Remaining = 60, Chance = 1}}
	local rolls = Core.StepAbility(e, 0.25, rng)
	C.Check(#rolls == 0 and e[1].Remaining == 59.75, "equip then 0.25 s: no roll")
	e = {{Id = "a", Remaining = 12, Chance = 1}}
	local total, at = 0, nil
	for step = 1, 60 do
		local r = Core.StepAbility(e, 0.25, rng)
		total += #r
		if #r > 0 and not at then at = step end
	end
	C.Eq(at, 48, "Remaining 12 rolls exactly after 12 s")
	C.Eq(total, 1, "one roll in 15 s")
	e = {{Id = "a", Remaining = 0.1, Chance = 0}}
	rolls = Core.StepAbility(e, 0.25, rng)
	C.Check(#rolls == 1 and rolls[1].Success == false and e[1].Remaining == 60, "reset to 60 before the draw (no carry)")
	e = {{Id = "a", Remaining = 10, Chance = 1}}
	rolls = Core.StepAbility(e, 30, rng)
	C.Check(#rolls == 1 and e[1].Remaining == 60, "30 s hitch -> one roll")
	e = {{Id = "a", Remaining = 0 / 0, Chance = 1}}
	rolls = Core.StepAbility(e, 0.25, rng)
	C.Check(#rolls == 0 and e[1].Remaining == 59.75, "NaN countdown -> 60")
	e = {{Id = "a", Remaining = 5, Chance = 1}}
	rolls = Core.StepAbility(e, 0 / 0, rng)
	C.Check(#rolls == 0 and e[1].Remaining == 5, "NaN dt ignored")
	e = {{Id = "a", Remaining = 0.2, Chance = 0, Force = true}}
	rolls = Core.StepAbility(e, 0.25, rng)
	C.Check(#rolls == 1 and rolls[1].Success == true, "Force = success")
	e = {{Id = "a", Remaining = 0.2, Chance = 0 / 0}}
	rolls = Core.StepAbility(e, 0.25, rng)
	C.Check(#rolls == 1 and rolls[1].Success == false, "NaN chance = 0")
end)

--..Probability (seeded, +-3 sigma)..--
C.Run("probability", function()
	local rng = Random.new(20260922)
	local N = 20000
	for _, p in ipairs({0.01, 0.02, 0.04, 0.08, 0.12}) do
		local entries = table.create(N)
		for i = 1, N do entries[i] = {Id = i, Remaining = 0.1, Chance = p} end
		local rolls = Core.StepAbility(entries, 0.25, rng)
		local hits = 0
		for _, r in ipairs(rolls) do if r.Success then hits += 1 end end
		local mean, sigma = N * p, math.sqrt(N * p * (1 - p))
		C.Check(#rolls == N, ("p=%.2f: one roll per entry"):format(p))
		C.Check(math.abs(hits - mean) <= 3 * sigma, ("p=%.2f: %d hits vs %.0f +- %.1f"):format(p, hits, mean, 3 * sigma))
	end
end)

--..BuildPetView..--
C.Run("petview", function()
	local rec = H.PetRec("v1", "Cat", {Material = "Golden", Mutations = {"NEON", "Foo"}, SourceEgg = "Basic Egg", AcquiredAt = 1790000000})
	local v = Core.BuildPetView(rec, nil, true, 240)
	C.Check(v.Id == "v1" and v.Pet == "Cat" and v.DisplayName == "Cucumber Deer" and v.Rarity == "Common", "identity fields")
	C.Check(v.Status == "Idle" and v.Equipped == true, "equipped without runtime = Idle")
	C.Eq(table.concat(v.Mutations, ","), "NEON", "known mutations only")
	C.Eq(v.Material, "Golden", "material")
	C.Eq(v.SourceEgg, "Basic Egg", "source egg")
	C.Eq(v.AcquiredAt, 1790000000, "acquired")
	C.Eq(v.AbilityRemaining, 60, "remaining")
	local s = v.Stats
	C.Check(s.Ability == "Yield" and s.AbilityDuration == 90 and s.AbilityDurations == nil and s.Fighter == false, "Yield duration 90")
	C.Check(math.abs(s.Income - 0.5 * 1.5 * 1.15) < 1e-9, "golden NEON income 0.8625")
	C.Check(math.abs(s.AbilityChance - 0.01) < 1e-9, "chance 1 %")
	C.Check(s.ShotDamage > 0 and s.ShotInterval == 2.5 and s.Range == 26, "combat numbers")
	local g = Core.BuildPetView(H.PetRec("v2", "Dog"), nil, false, 240)
	C.Check(g.Status == "Reserve" and g.Stats.Ability == "Guard" and g.Stats.AbilityDuration == 240, "Guard uses guard seconds")
	local w = Core.BuildPetView(H.PetRec("v3", "Gregory"), {Status = "Active"}, true, 240)
	C.Check(w.Status == "Active" and w.Stats.Ability == "Wild" and w.Stats.AbilityDuration == nil, "Wild: no single duration")
	C.Check(w.Stats.AbilityDurations and w.Stats.AbilityDurations.Yield == 90 and w.Stats.AbilityDurations.Haste == 90 and w.Stats.AbilityDurations.Guard == 240, "Wild durations")
	local f = Core.BuildPetView(H.PetRec("v4", "Bunny"), nil, false)
	C.Check(f.Stats.Ability == "None" and f.Stats.AbilityDuration == nil and f.Stats.Fighter == true, "fighter")
	local bad = Core.BuildPetView(H.PetRec("v5", "Unicorn", {AbilityRemaining = 0 / 0}), nil, true)
	C.Check(bad.Status == "Invalid" and bad.AbilityRemaining == 60 and bad.Stats.Income == 0, "unknown species -> Invalid, finite")
	local ok = pcall(HttpService.JSONEncode, HttpService, v)
	C.Check(ok, "PetView is JSON-safe (remote-safe)")
end)

return C.Summary()
