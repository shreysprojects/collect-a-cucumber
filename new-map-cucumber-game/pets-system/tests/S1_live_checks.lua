-- S1 live checks (integration agent, 2026-09-22): runs against the INSTALLED ModuleScripts
-- ReplicatedStorage.Modules.PetBalance / PetStats / PetMotion (not the loopback sources).
-- Edit peer or server VM. Read-only: requires Clone()s (busts the eval require cache; the clones are never
-- parented), creates no parented instances, changes nothing. Returns one summary string.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local pass, fail, failures, notes = 0, 0, {}, {}
local function Check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 16 then failures[#failures + 1] = name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "") end
	end
end
local function Note(s) notes[#notes + 1] = s end
local function Near(a, b, tol)
	return type(a) == "number" and math.abs(a - b) <= (tol or 1e-9) * math.max(1, math.abs(b))
end
local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local rsBefore = #ReplicatedStorage:GetDescendants()
local function Req(name)
	local m = Modules:FindFirstChild(name)
	assert(m and m:IsA("ModuleScript"), "missing live module " .. name)
	return require(m:Clone())
end
local PetBalance = Req("PetBalance")
local PetStats = Req("PetStats")
local PetMotion = Req("PetMotion")
local PetsCatalog = require(Modules:WaitForChild("PetsCatalog"))
Check("no instances created by require", #ReplicatedStorage:GetDescendants() == rsBefore, #ReplicatedStorage:GetDescendants() - rsBefore)

-- A. Validate against the live catalog
local problems = PetBalance.Validate(PetsCatalog)
Check("Validate(PetsCatalog) is a table", type(problems) == "table")
Check("Validate(PetsCatalog) empty", type(problems) == "table" and #problems == 0, type(problems) == "table" and table.concat(problems, " | ") or problems)
Note(("Validate(PetsCatalog) -> %d problems"):format(type(problems) == "table" and #problems or -1))
local okNil, pNil = pcall(PetBalance.Validate, nil)
Check("Validate(nil) never errors + reports", okNil and type(pNil) == "table" and #pNil >= 1, pNil)

-- B. PLAN 3.2 income examples
local function Calc(pet, material, mutations)
	return PetStats.Calculate({Pet = pet, Material = material or "", Mutations = mutations or {}})
end
local samples = {{"Cat", 0.5}, {"Fox", 3.75}, {"Gregory", 7.5}, {"Chest", 7.8}, {"Cosmo Cat", 15728640}}
local got = {}
for _, s in ipairs(samples) do
	local st = Calc(s[1])
	got[#got + 1] = ("%s=%s"):format(s[1], tostring(st.Income))
	Check("income " .. s[1], st.Valid and Near(st.Income, s[2]), st.Income)
	Check("no warnings " .. s[1], #st.Warnings == 0, table.concat(st.Warnings, ","))
end
Note("income: " .. table.concat(got, ", "))
Check("Gregory rank override 6", Calc("Gregory").Rank == 6, Calc("Gregory").Rank)

-- C. PLAN 3.4 combat examples
local deer = Calc("Cat")
Check("Deer shot 3", Near(deer.ShotDamage, 3), deer.ShotDamage)
Check("Deer interval 2.5", Near(deer.ShotInterval, 2.5), deer.ShotInterval)
Check("Deer DPS 1.2", Near(deer.DPS, 1.2), deer.DPS)
local cosmo = Calc("Cosmo Cat")
Check("Cosmo shot 24.3", Near(cosmo.ShotDamage, 24.3), cosmo.ShotDamage)
Check("Cosmo interval 1.5", Near(cosmo.ShotInterval, 1.5), cosmo.ShotInterval)
Check("Cosmo DPS 16.2", Near(cosmo.DPS, 16.2), cosmo.DPS)
local cosmoMax = Calc("Cosmo Cat", "Diamond", {"PRISMATIC", "VOID"})
Check("Cosmo max affix damage 1.25", Near(cosmoMax.AffixDamage, 1.25), cosmoMax.AffixDamage)
Check("Cosmo max affix DPS 20.25", Near(cosmoMax.DPS, 20.25), cosmoMax.DPS)
local bunny = Calc("Bunny")
Check("Bunny fighter 5.75", bunny.Fighter and Near(bunny.ShotDamage, 5.75), bunny.ShotDamage)
Note(("combat: Deer %s dmg / %s s = %s DPS; Cosmo %s / %s = %s DPS; Cosmo max affix %s DPS; Bunny %s"):format(
	tostring(deer.ShotDamage), tostring(deer.ShotInterval), tostring(deer.DPS), tostring(cosmo.ShotDamage),
	tostring(cosmo.ShotInterval), tostring(cosmo.DPS), tostring(cosmoMax.DPS), tostring(bunny.ShotDamage)))

-- D. PLAN 3.3 affixes
Check("Golden NEON ROYAL 2.475", Near(PetStats.AffixIncome("Golden", {"NEON", "ROYAL"}), 2.475), PetStats.AffixIncome("Golden", {"NEON", "ROYAL"}))
Check("income affix cap 8", Near(PetStats.AffixIncome("Diamond", {"PRISMATIC", "VOID", "ROYAL"}), 8), PetStats.AffixIncome("Diamond", {"PRISMATIC", "VOID", "ROYAL"}))
Check("duplicate mutation once", Near(PetStats.AffixIncome("", "NEON, neon,NEON"), 1.15), PetStats.AffixIncome("", "NEON, neon,NEON"))
Check("damage affix cap 1.25", Near(PetStats.AffixDamage("Diamond", {"PRISMATIC", "VOID", "ROYAL"}), 1.25))
local norm = PetStats.NormalizeMutations("neon, Foo")
Check("NormalizeMutations keeps unknown", norm[1] == "NEON" and norm[2] == "Foo" and #norm == 2, table.concat(norm, ","))

-- E. PLAN 3.1 base income per egg tier (rank-1 Common of every egg)
local tierPets = {"Cat", "Barrel", "Dog Ninja", "Hay", "Red Snowman", "Oceanic Dog", "Lava Plume", "Moon Bunny"}
local tierWant = {0.5, 4, 32, 256, 2048, 16384, 131072, 1048576}
for i, pet in ipairs(tierPets) do
	local st = Calc(pet)
	Check("tier base " .. pet, st.EggTier == i and st.Rank == 1 and st.Rarity == "Common" and Near(st.Income, tierWant[i]), st.Income)
end

-- F. every catalog pet against an independent formula
local count, validCount, eggCount = 0, 0, {}
local rows = {}
for petKey, info in pairs(PetsCatalog.PETS) do
	count += 1
	local eggKey, rank
	for ek, egg in pairs(PetsCatalog.EGGS) do
		local entry = egg.Pets[petKey]
		if entry then eggKey = ek; rank = PetBalance.RANK_OVERRIDES[petKey] or entry.Rank end
	end
	local tier = PetBalance.EGG_TIERS[eggKey]
	local r = PetBalance.RARITY[info.Rarity]
	local ability = PetBalance.SPECIES_ABILITY[petKey]
	local fighter = ability == "None"
	local income = 0.5 * 8 ^ (tier - 1) * r.Income * (1 + 0.1 * (rank - 1))
	local shot = r.Damage * (1 + 0.05 * (tier - 1)) * (fighter and 1.15 or 1)
	local st = PetStats.Calculate({Pet = petKey, Material = "", Mutations = {}})
	if st.Valid then validCount += 1 end
	eggCount[eggKey] = (eggCount[eggKey] or 0) + 1
	local okRow = st.Valid and #st.Warnings == 0 and Near(st.Income, income) and Near(st.ShotDamage, shot)
		and Near(st.DPS, shot / r.Interval) and st.Range == r.Range and st.Ability == ability
		and st.Fighter == fighter and Near(st.AbilityChance, fighter and 0 or r.Chance)
		and st.EggKey == eggKey and st.EggTier == tier and st.Rank == rank and st.DisplayName == info.DisplayName
		and Finite(st.Income) and Finite(st.DPS)
	Check("catalog row " .. petKey, okRow, ("inc %s want %s dps %s warn %s"):format(tostring(st.Income), tostring(income), tostring(st.DPS), table.concat(st.Warnings, ",")))
	local e, t, rk = PetStats.EggOf(petKey)
	Check("EggOf " .. petKey, e == eggKey and t == tier and rk == rank)
	rows[#rows + 1] = {Id = petKey, Stats = st}
end
Check("49 catalog pets", count == 49, count)
Check("49 valid", validCount == 49, validCount)
local eggs = 0
for _, n in pairs(eggCount) do eggs += 1 end
Check("8 eggs used", eggs == 8, eggs)
table.sort(rows, function(a, b) return PetStats.Compare(a, b, "Income") end)
Check("Compare Income top = Cosmo Cat", rows[1].Id == "Cosmo Cat", rows[1].Id)
table.sort(rows, function(a, b) return PetStats.Compare(a, b, "Combat") end)
Note(("Combat top = %s (%.4g DPS); Income bottom = Cat"):format(rows[1].Id, rows[1].Stats.DPS))
Check("Compare Combat top is Mythical", rows[1].Stats.Rarity == "Mythical", rows[1].Id)

-- G. garbage records + unknown key
local garbage = {nil, 5, "Cat", {}, {Pet = 0 / 0}, {Pet = "Nope"}, {Pet = "Cat", Material = 0 / 0, Mutations = {1, 2, "NEON", {}}},
	{Pet = "Cat", Material = "Plastic", Mutations = "VOID,, ,Weird"}, {Pet = "Cosmo Cat", Mutations = 12}}
local allFinite, errors = true, 0
for i = 1, 9 do
	local ok, st = pcall(PetStats.Calculate, garbage[i])
	if not ok or type(st) ~= "table" then
		errors += 1
	else
		for _, k in ipairs({"Income", "ShotDamage", "ShotInterval", "DPS", "Range", "AffixIncome", "AffixDamage", "AbilityChance", "EggTier", "Rank"}) do
			if not Finite(st[k]) then allFinite = false end
		end
	end
end
Check("garbage records never error", errors == 0, errors)
Check("garbage records finite", allFinite)
local unk = PetStats.Calculate({Pet = "Nope"})
Check("unknown key Valid=false, 0", unk.Valid == false and unk.Income == 0 and unk.DPS == 0 and unk.Ability == "None")
local plastic = PetStats.Calculate({Pet = "Cat", Material = "Plastic", Mutations = "VOID,Weird"})
Check("unknown material/mutation kept + ignored", plastic.UnknownMaterial == "Plastic" and plastic.UnknownMutations[1] == "Weird" and Near(plastic.Income, 1.0), plastic.Income)

-- H. timing / rate / text helpers
Check("GuardSeconds(180,45)=240", PetStats.GuardSeconds(180, 45) == 240, PetStats.GuardSeconds(180, 45))
Check("GuardSeconds(1000,1000)=600", PetStats.GuardSeconds(1000, 1000) == 600)
Check("GuardSeconds(NaN,nil)=205", PetStats.GuardSeconds(0 / 0, nil) == 205, PetStats.GuardSeconds(0 / 0, nil))
Check("RateMultiplier Yield+Haste 1.875", Near(PetStats.RateMultiplier({Yield = true, Haste = true}), 1.875))
Check("AbilityShort Yield", PetStats.AbilityShort("Yield") == "x1.5 for 90s", PetStats.AbilityShort("Yield"))
Check("AbilityShort Haste", PetStats.AbilityShort("Haste") == "+25% for 90s", PetStats.AbilityShort("Haste"))
Check("AbilityShort Guard 240", PetStats.AbilityShort("Guard", 240) == "blocks one theft for 240s", PetStats.AbilityShort("Guard", 240))
Check("AbilityBadge Yield/Haste/Guard", PetStats.AbilityBadge("Yield") == "x1.5" and PetStats.AbilityBadge("Haste") == "+25%" and PetStats.AbilityBadge("Guard") == "1")
Check("AbilityEffect None", PetStats.AbilityEffect("None") == "Fighter: +15% damage", PetStats.AbilityEffect("None"))
Note("Wild effect: " .. PetStats.AbilityEffect("Wild", 240))
Check("EggKeyOfShortName Desert", PetStats.EggKeyOfShortName("Desert") == "Desert Egg", PetStats.EggKeyOfShortName("Desert"))
Check("IsValidId", PetStats.IsValidId(game:GetService("HttpService"):GenerateGUID(false)) and not PetStats.IsValidId("") and not PetStats.IsValidId(string.rep("a", 65)))

-- I. PetMotion
local seg = {From = Vector3.new(0, 5, 0), To = Vector3.new(10, 5, 0), Start = 100, End = 110, GroundY = 3, Seq = 7}
local p0, w0 = PetMotion.Sample(seg, 99)
local p1, w1, h1 = PetMotion.Sample(seg, 105)
local p2, w2 = PetMotion.Sample(seg, 111)
Check("Motion before start", p0 == Vector3.new(0, 3, 0) and w0 == false, p0)
Check("Motion midpoint", p1 == Vector3.new(5, 3, 0) and w1 == true and h1 == Vector3.new(1, 0, 0), p1)
Check("Motion after end", p2 == Vector3.new(10, 3, 0) and w2 == false, p2)
local pz, wz = PetMotion.Sample({To = Vector3.new(1, 0, 1), Start = 5, End = 5, GroundY = 2}, 5)
Check("Motion zero duration -> To", pz == Vector3.new(1, 2, 1) and wz == false)
Check("Motion nil seg", PetMotion.Sample(nil, 1) == nil)
Check("Motion NaN now -> To idle", (PetMotion.Sample(seg, 0 / 0)) == Vector3.new(10, 3, 0))
local attrs = PetMotion.ToAttributes(seg)
Check("ToAttributes ends RoamSeq", #attrs == 6 and attrs[6][1] == "RoamSeq" and attrs[6][2] == 7 and attrs[1][1] == "RoamFrom")
local fake = {GetAttribute = function(_, k)
	for _, kv in ipairs(attrs) do if kv[1] == k then return kv[2] end end
	return nil
end}
local back = PetMotion.ReadSegment(fake)
Check("ReadSegment round trip", back and back.To == seg.To and back.From == seg.From and back.Start == 100 and back.End == 110 and back.GroundY == 3 and back.Seq == 7)
Check("MUZZLE_HEIGHT 1.5", PetMotion.MUZZLE_HEIGHT == 1.5, PetMotion.MUZZLE_HEIGHT)

Check("no instances created (end)", #ReplicatedStorage:GetDescendants() == rsBefore, #ReplicatedStorage:GetDescendants() - rsBefore)

return ("S1 live checks: PASS %d / FAIL %d%s\n%s"):format(pass, fail,
	fail > 0 and (": " .. table.concat(failures, "; ")) or "", table.concat(notes, "\n"))
