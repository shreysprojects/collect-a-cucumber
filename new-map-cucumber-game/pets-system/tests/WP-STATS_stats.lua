-- WP-STATS stats: PetStats against the live PetsCatalog (PLAN 3.2-3.4 examples, affixes, caps, garbage
-- records, text helpers, sorting) plus fake catalogs / copied balance tables injected at load.
-- Read-only: loads PetBalance + PetStats from the loopback src server (:8793), creates no instances.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 12 then failures[#failures + 1] = name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "") end
	end
end
local function Near(a, b, tol)
	return type(a) == "number" and math.abs(a - b) <= (tol or 1e-9) * math.max(1, math.abs(b))
end
local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local sources = {}
local function Load(file, deps)
	sources[file] = sources[file] or HttpService:GetAsync("http://127.0.0.1:8793/" .. file, true)
	local fn, err = loadstring(sources[file], "=" .. file)
	assert(fn, err)
	local fakeModules = {WaitForChild = function(_, name) return "dep:" .. name end}
	local fakeRS = {WaitForChild = function(_, _) return fakeModules end}
	local fakeGame = setmetatable({GetService = function(_, name)
		if name == "ReplicatedStorage" then return fakeRS end
		return game:GetService(name)
	end}, {__index = function(_, k) return game[k] end})
	setfenv(fn, setmetatable({
		game = fakeGame,
		require = function(x)
			if type(x) == "string" and x:sub(1, 4) == "dep:" then
				local dep = deps[x:sub(5)]
				assert(dep ~= nil, "missing dep " .. x)
				return dep
			end
			return require(x)
		end,
	}, {__index = getfenv(0)}))
	return fn()
end
local function Copy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = Copy(v) end
	return c
end
local function Has(list, needle)
	for _, v in ipairs(list) do
		if v == needle then return true end
	end
	return false
end
local function Same(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local Catalog = require(ReplicatedStorage.Modules.PetsCatalog)
local B = Load("ReplicatedStorage.Modules.PetBalance.lua", {})
local S = Load("ReplicatedStorage.Modules.PetStats.lua", {PetBalance = B, PetsCatalog = Catalog})

--.. SpeciesEgg / EggOf
local speciesCount = 0
for _ in pairs(S.SpeciesEgg) do speciesCount += 1 end
Check("SpeciesEgg covers 49", speciesCount == 49, speciesCount)
local egg, tier, rank = S.EggOf("Chest")
Check("EggOf Chest", egg == "Desert Egg" and tier == 2 and rank == 4, tostring(egg) .. tostring(tier) .. tostring(rank))
egg, tier, rank = S.EggOf("Gregory")
Check("EggOf Gregory override", egg == "Basic Egg" and tier == 1 and rank == 6)
egg, tier, rank = S.EggOf("Cosmo Cat")
Check("EggOf Cosmo Cat", egg == "Narmek Egg" and tier == 8 and rank == 6)
Check("EggOf unknown", S.EggOf("Nope") == nil and S.EggOf(nil) == nil and S.EggOf(5) == nil)
Check("EggKeyOfShortName", S.EggKeyOfShortName("Desert") == "Desert Egg" and S.EggKeyOfShortName("Frozen") == "Frozen Egg"
	and S.EggKeyOfShortName("Toyland") == nil and S.EggKeyOfShortName(nil) == nil and S.EggKeyOfShortName(3) == nil)

--.. ids / finite
Check("IsValidId", S.IsValidId(HttpService:GenerateGUID(false)) and S.IsValidId("a") and S.IsValidId(("x"):rep(64))
	and not S.IsValidId("") and not S.IsValidId(("x"):rep(65)) and not S.IsValidId(12) and not S.IsValidId(nil))
Check("IsFinite", S.IsFinite(1.5) and not S.IsFinite(0 / 0) and not S.IsFinite(math.huge) and not S.IsFinite("1"))

--.. PLAN 3.2 income examples
local function Calc(pet, material, mutations)
	return S.Calculate({Pet = pet, Material = material, Mutations = mutations})
end
local cat = Calc("Cat")
Check("Cat 0.5", Near(cat.Income, 0.5), cat.Income)
Check("Fox 3.75", Near(Calc("Fox").Income, 3.75), Calc("Fox").Income)
local greg = Calc("Gregory")
Check("Gregory 7.5", Near(greg.Income, 7.5), greg.Income)
Check("Gregory no rank warning", not Has(greg.Warnings, "NoRank") and greg.Rank == 6 and greg.Ability == "Wild", table.concat(greg.Warnings, ","))
Check("Chest 7.8", Near(Calc("Chest").Income, 7.8), Calc("Chest").Income)
local cosmo = Calc("Cosmo Cat")
Check("Cosmo Cat 15,728,640", Near(cosmo.Income, 15728640), cosmo.Income)

--.. affixes
Check("Golden NEON ROYAL 2.475", Near(S.AffixIncome("Golden", {"NEON", "ROYAL"}), 2.475), S.AffixIncome("Golden", {"NEON", "ROYAL"}))
Check("affix from comma string", Near(S.AffixIncome("Golden", "NEON,ROYAL"), 2.475))
Check("duplicate mutation counted once", Near(S.AffixIncome("", {"NEON", "NEON", "neon"}), 1.15), S.AffixIncome("", {"NEON", "NEON", "neon"}))
Check("duplicate in string counted once", Near(S.AffixIncome(nil, "VOID, VOID"), 2))
Check("income cap 8", S.AffixIncome("Diamond", {"PRISMATIC", "VOID", "ROYAL"}) == 8, S.AffixIncome("Diamond", {"PRISMATIC", "VOID", "ROYAL"}))
Check("damage cap 1.25", S.AffixDamage("Diamond", {"PRISMATIC", "VOID", "ROYAL"}) == 1.25, S.AffixDamage("Diamond", {"PRISMATIC", "VOID", "ROYAL"}))
Check("damage affix Golden NEON", Near(S.AffixDamage("Golden", {"NEON"}), 1.07), S.AffixDamage("Golden", {"NEON"}))
Check("affix normal = 1", S.AffixIncome("", {}) == 1 and S.AffixDamage(nil, nil) == 1)
Check("unknown material ignored", S.AffixIncome("Plutonium", {"FOO"}) == 1 and S.AffixDamage("Plutonium", {"FOO"}) == 1)
local golden = Calc("Cat", "Golden", {"NEON", "ROYAL"})
Check("Cat Golden NEON ROYAL income", Near(golden.Income, 0.5 * 2.475), golden.Income)

--.. combat (PLAN 3.4)
Check("Deer 3 dmg", Near(cat.ShotDamage, 3) and cat.ShotInterval == 2.5 and Near(cat.DPS, 1.2), cat.DPS)
Check("Cosmo 24.3 / 1.5 = 16.2", Near(cosmo.ShotDamage, 24.3) and cosmo.ShotInterval == 1.5 and Near(cosmo.DPS, 16.2), cosmo.DPS)
local cosmoMax = Calc("Cosmo Cat", "Diamond", {"PRISMATIC", "VOID", "ROYAL"})
Check("Cosmo max affix 20.25 DPS", Near(cosmoMax.DPS, 20.25), cosmoMax.DPS)
local bunny = Calc("Bunny")
Check("fighter Bunny 5.75", Near(bunny.ShotDamage, 5.75) and bunny.Fighter == true and bunny.Ability == "None" and bunny.AbilityChance == 0, bunny.ShotDamage)
Check("Cat not fighter, chance 1%", cat.Fighter == false and cat.Ability == "Yield" and cat.AbilityChance == 0.01)
Check("Cosmo chance 12%, range 38", cosmo.AbilityChance == 0.12 and cosmo.Range == 38)
Check("Cat valid + clean", cat.Valid and #cat.Warnings == 0 and cat.RarityKnown and cat.Rarity == "Common" and cat.DisplayName == "Cucumber Deer"
	and cat.EggKey == "Basic Egg" and cat.EggTier == 1 and cat.Rank == 1, table.concat(cat.Warnings, ","))

--.. every live species: valid, finite, warning-free
local dirty = 0
for key in pairs(Catalog.PETS) do
	local st = Calc(key, "Diamond", {"PRISMATIC"})
	local ok = st.Valid and #st.Warnings == 0
	for _, f in ipairs({"Income", "ShotDamage", "ShotInterval", "DPS", "Range", "AbilityChance", "AffixIncome", "AffixDamage", "EggTier", "Rank"}) do
		if not Finite(st[f]) then ok = false end
	end
	if not ok then dirty += 1 end
end
Check("all 49 valid/finite/no warnings", dirty == 0, dirty)

--.. unknown key / garbage records
local unknown = Calc("Not A Pet")
Check("unknown key invalid", unknown.Valid == false and unknown.Income == 0 and unknown.DPS == 0 and unknown.ShotDamage == 0
	and unknown.Ability == "None" and unknown.AbilityChance == 0 and unknown.EggTier == 0 and unknown.Rank == 0 and unknown.Pet == "Not A Pet")
local nan = 0 / 0
local garbage = {nil, 5, "Cat", true, {}, {Pet = 7}, {Pet = "Cat", Material = nan, Mutations = nan},
	{Pet = "Cat", Material = {}, Mutations = {1, true, nan, {}, "NEON"}}, {Pet = nan}, {Pet = "Cat", Mutations = 12},
	setmetatable({}, {__index = function() error("boom") end})}
local garbageOk = true
for i = 1, 11 do
	local ok, st = pcall(S.Calculate, garbage[i])
	if not ok or type(st) ~= "table" then
		garbageOk = false
	else
		for _, f in ipairs({"Income", "ShotDamage", "ShotInterval", "DPS", "Range", "AbilityChance", "AffixIncome", "AffixDamage", "EggTier", "Rank"}) do
			if not Finite(st[f]) then garbageOk = false end
		end
		if type(st.Warnings) ~= "table" or #st.Warnings > 8 or type(st.DisplayName) ~= "string" then garbageOk = false end
	end
end
Check("garbage records -> finite, no error", garbageOk)
local mixed = Calc("Cat", 5, {1, true, "NEON", "Sparkly"})
Check("non-string mutations dropped, unknown reported", Near(mixed.AffixIncome, 1.15) and mixed.UnknownMutations[1] == "Sparkly"
	and Has(mixed.Warnings, "UnknownMutations") and mixed.UnknownMaterial == nil, mixed.AffixIncome)
local plut = Calc("Cat", "Plutonium")
Check("unknown material kept + warned", plut.UnknownMaterial == "Plutonium" and Has(plut.Warnings, "UnknownMaterial") and Near(plut.Income, 0.5))

--.. NormalizeMutations / Split / MutationString
Check("Normalize 'neon, Foo'", Same(S.NormalizeMutations("neon, Foo"), {"NEON", "Foo"}), table.concat(S.NormalizeMutations("neon, Foo"), ","))
Check("Normalize nil/number", #S.NormalizeMutations(nil) == 0 and #S.NormalizeMutations(12) == 0)
Check("Normalize array", Same(S.NormalizeMutations({"void", "VOID", "Foo", "foo", 5}), {"VOID", "Foo", "foo"}))
local long = {}
for i = 1, 20 do long[i] = "Custom" .. i end
Check("array of 20 not truncated", #S.NormalizeMutations(long) == 20)
local longStr = {}
for i = 1, 20 do longStr[i] = "Custom" .. i end
Check("string reads 16 tokens", #S.NormalizeMutations(table.concat(longStr, ",")) == 16)
Check("array with hole kept", Same(S.NormalizeMutations({[1] = "NEON", [3] = "VOID"}), {"NEON", "VOID"}))
local known, unk = S.SplitMutations({"NEON", "Foo", "royal"})
Check("SplitMutations", Same(known, {"NEON", "ROYAL"}) and Same(unk, {"Foo"}))
Check("MutationString known only", S.MutationString({"NEON", "Foo", "VOID"}) == "NEON,VOID" and S.MutationString(nil) == "" and S.MutationString({"Foo"}) == "")
Check("NormalizeMaterial", S.NormalizeMaterial(nil) == "" and S.NormalizeMaterial("") == "" and S.NormalizeMaterial(4) == ""
	and S.NormalizeMaterial("Golden") == "Golden" and S.NormalizeMaterial("weird") == "weird")

--.. AbilityOf
Check("AbilityOf", S.AbilityOf("Cat") == "Yield" and S.AbilityOf("Dog") == "Guard" and S.AbilityOf("Wolf") == "Haste"
	and S.AbilityOf("Gregory") == "Wild" and S.AbilityOf("Bunny") == "None" and S.AbilityOf("Nope") == "None" and S.AbilityOf(nil) == "None")

--.. GuardSeconds / RateMultiplier
Check("GuardSeconds(180,45)=240", S.GuardSeconds(180, 45) == 240)
Check("GuardSeconds(1000,1000)=600", S.GuardSeconds(1000, 1000) == 600)
Check("GuardSeconds defaults", S.GuardSeconds(nil, 0 / 0) == 205 and S.GuardSeconds(math.huge, 45) == 240)
Check("RateMultiplier Yield+Haste 1.875", S.RateMultiplier({Yield = true, Haste = true}) == 1.875)
Check("RateMultiplier single/none/guard", S.RateMultiplier({Yield = true}) == 1.5 and S.RateMultiplier({}) == 1
	and S.RateMultiplier(nil) == 1 and S.RateMultiplier({Guard = true, Haste = true}) == 1.25 and S.RateMultiplier({Yield = false}) == 1)
Check("RateMultiplier array form", S.RateMultiplier({"Yield", "Haste"}) == 1.875)

--.. text helpers (built from ABILITIES)
Check("AbilityBadge", S.AbilityBadge("Yield") == "x1.5" and S.AbilityBadge("Haste") == "+25%" and S.AbilityBadge("Guard") == "1"
	and S.AbilityBadge("Wild") == "" and S.AbilityBadge("None") == "" and S.AbilityBadge(nil) == "")
Check("AbilityShort", S.AbilityShort("Yield") == "x1.5 for 90s" and S.AbilityShort("Haste") == "+25% for 90s"
	and S.AbilityShort("Guard", 240) == "blocks one theft for 240s" and S.AbilityShort("Wild") == "" and S.AbilityShort("None") == "",
	S.AbilityShort("Guard", 240))
Check("AbilityShort Guard default", S.AbilityShort("Guard") == "blocks one theft for 205s", S.AbilityShort("Guard"))
Check("AbilityEffect Yield", S.AbilityEffect("Yield") == "One cucumber earns x1.5 cash/sec for 90s", S.AbilityEffect("Yield"))
Check("AbilityEffect Haste", S.AbilityEffect("Haste") == "One cucumber produces 25% faster for 90s", S.AbilityEffect("Haste"))
Check("AbilityEffect Guard", S.AbilityEffect("Guard", 240) == "Blocks 1 zombie theft on one cucumber for up to 240s", S.AbilityEffect("Guard", 240))
Check("AbilityEffect None", S.AbilityEffect("None") == "Fighter: +15% damage", S.AbilityEffect("None"))
Check("AbilityEffect Wild", S.AbilityEffect("Wild", 240) == "Lucky Harvest (x1.5 for 90s), Quick Grow (+25% for 90s) or Leaf Shield (blocks one theft for 240s)",
	S.AbilityEffect("Wild", 240))
Check("AbilityEffect unknown", S.AbilityEffect("Nope") == "" and S.AbilityEffect(nil) == "")

--.. copied balance: text follows the numbers
local B2 = Copy(B)
B2.ABILITIES.Yield.Mult = 2
B2.ABILITIES.Yield.Duration = 120
B2.ABILITIES.Haste.Mult = 1.4
local S2 = Load("ReplicatedStorage.Modules.PetStats.lua", {PetBalance = B2, PetsCatalog = Catalog})
Check("badge follows Mult", S2.AbilityBadge("Yield") == ("x%g"):format(B2.ABILITIES.Yield.Mult) and S2.AbilityBadge("Haste") == "+40%", S2.AbilityBadge("Haste"))
Check("short follows Mult/Duration", S2.AbilityShort("Yield") == "x2 for 120s" and S2.AbilityShort("Haste") == "+40% for 90s", S2.AbilityShort("Yield"))
Check("effect follows Mult", S2.AbilityEffect("Yield") == "One cucumber earns x2 cash/sec for 120s")
Check("rate follows Mult", Near(S2.RateMultiplier({Yield = true, Haste = true}), 2) and S2.RateMultiplier({Yield = true, Haste = true}) <= 2)

--.. fake catalog: no ability row, rank 9, missing rank
local fakeCatalog = Copy(Catalog)
fakeCatalog.EggKey = Catalog.EggKey
fakeCatalog.PETS["Test Newbie"] = {Rarity = "Rare", DisplayName = "Newbie"}
fakeCatalog.EGGS["Basic Egg"].Pets["Test Newbie"] = {Percent = 1, Rank = 3}
fakeCatalog.EGGS["Desert Egg"].Pets.Chest.Rank = 9
fakeCatalog.EGGS["Basic Egg"].Pets.Cat.Rank = nil
fakeCatalog.PETS["Test Orphan"] = {Rarity = "Epic", DisplayName = "Orphan"}
local S3 = Load("ReplicatedStorage.Modules.PetStats.lua", {PetBalance = B, PetsCatalog = fakeCatalog})
local newbie = S3.Calculate({Pet = "Test Newbie"})
Check("no ability row -> valid None + NoAbilityRow", newbie.Valid and newbie.Ability == "None" and newbie.Fighter and Has(newbie.Warnings, "NoAbilityRow")
	and Near(newbie.ShotDamage, 8 * 1.15), table.concat(newbie.Warnings, ","))
Check("Validate reports newbie", #B.Validate(fakeCatalog) >= 1)
local chest9 = S3.Calculate({Pet = "Chest"})
Check("rank 9 clamped to 6 + warning", chest9.Rank == 6 and Has(chest9.Warnings, "RankClamped") and Near(chest9.Income, 4 * 1.5 * 1.5), chest9.Rank)
local cat0 = S3.Calculate({Pet = "Cat"})
Check("missing rank -> 1 + NoRank", cat0.Rank == 1 and Has(cat0.Warnings, "NoRank") and Near(cat0.Income, 0.5))
local orphan = S3.Calculate({Pet = "Test Orphan"})
Check("orphan: NoEgg tier 1 + unknown rarity fallback", orphan.Valid and orphan.EggTier == 1 and Has(orphan.Warnings, "NoEgg")
	and orphan.RarityKnown == false and orphan.Rarity == "Epic" and Has(orphan.Warnings, "UnknownRarity") and Near(orphan.Income, 0.5)
	and Has(orphan.Warnings, "NoAbilityRow"), table.concat(orphan.Warnings, ","))
Check("absent key invalid (fake)", S3.Calculate({Pet = "Gone"}).Valid == false)

--.. Compare
local function Entry(id, income, dps) return {Id = id, Stats = {Income = income, DPS = dps}} end
local list = {Entry("c", 5, 1), Entry("a", 5, 1), Entry("b", 5, 3), Entry("d", 9, 0), Entry("e", 0 / 0, 2), {Id = "f"}}
table.sort(list, function(x, y) return S.Compare(x, y, "Income") end)
local ids = {}
for i, e in ipairs(list) do ids[i] = e.Id end
Check("Compare Income", table.concat(ids) == "dbacef", table.concat(ids))
table.sort(list, function(x, y) return S.Compare(x, y, "Combat") end)
for i, e in ipairs(list) do ids[i] = e.Id end
Check("Compare Combat", table.concat(ids) == "beacdf", table.concat(ids))
table.sort(list, S.Compare)
for i, e in ipairs(list) do ids[i] = e.Id end
Check("Compare default Income", table.concat(ids) == "dbacef", table.concat(ids))
Check("Compare irreflexive", S.Compare(list[1], list[1], "Income") == false)

local summary = ("WP-STATS stats: PASS %d / FAIL %d"):format(pass, fail)
if fail > 0 then summary ..= ": " .. table.concat(failures, "; ") end
return summary
