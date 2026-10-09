-- WP-STATS balance: PetBalance literal tables + Validate against the live PetsCatalog and fakes.
-- Read-only: loads PetBalance from the loopback src server (:8793), creates no instances.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 12 then failures[#failures + 1] = name .. (detail and (" [" .. tostring(detail) .. "]") or "") end
	end
end

local function Load(file, deps)
	local src = HttpService:GetAsync("http://127.0.0.1:8793/" .. file, true)
	local fn, err = loadstring(src, "=" .. file)
	assert(fn, err)
	local fakeModules = {WaitForChild = function(_, name) return "dep:" .. name end}
	local fakeRS = {WaitForChild = function(_, _) return fakeModules end}
	local fakeGame = setmetatable({GetService = function(_, name)
		if name == "ReplicatedStorage" then return fakeRS end
		return game:GetService(name)
	end}, {__index = function(_, k) return game[k] end})
	local env = setmetatable({
		game = fakeGame,
		require = function(x)
			if type(x) == "string" and x:sub(1, 4) == "dep:" then
				local dep = deps[x:sub(5)]
				assert(dep ~= nil, "missing dep " .. x)
				return dep
			end
			return require(x)
		end,
	}, {__index = getfenv(0)})
	setfenv(fn, env)
	return fn()
end

local Catalog = require(ReplicatedStorage.Modules.PetsCatalog)
local B = Load("ReplicatedStorage.Modules.PetBalance.lua", {})

--.. literal spot checks (section 9)
Check("SLOTS 6", B.SLOTS == 6)
Check("MAX_OWNED 1000", B.MAX_OWNED == 1000)
Check("BASE_INCOME 0.5", B.BASE_INCOME == 0.5)
Check("TIER_STEP 8", B.TIER_STEP == 8)
Check("MAX_RANK 6", B.MAX_RANK == 6)
Check("Gregory override 6", B.RANK_OVERRIDES.Gregory == 6)
Check("RATE_HARD_CAP 2", B.RATE_HARD_CAP == 2)
Check("Mythical row", B.RARITY.Mythical.Income == 10 and B.RARITY.Mythical.Damage == 18 and B.RARITY.Mythical.Interval == 1.5 and B.RARITY.Mythical.Range == 38 and B.RARITY.Mythical.Chance == 0.12)
Check("Frozen->Snow", B.EGG_ZONES["Frozen Egg"] == "Snow" and B.EGG_ZONES["Ocean Egg"] == "Underwater" and B.EGG_ZONES["Lava Egg"] == "Volcano")
Check("PRISMATIC", B.MUTATIONS.PRISMATIC.Income == 2 and B.MUTATIONS.PRISMATIC.Combat == 0.12)
Check("ABILITIES colours", typeof(B.ABILITIES.Yield.Color) == "Color3" and typeof(B.ABILITIES.None.Color) == "Color3")
Check("TIMING", B.TIMING.ABILITY_PERIOD == 60 and B.TIMING.REVEAL_FALLBACK == 100 and B.TIMING.ROAM_LEAD == 0.3 and B.TIMING.UNAVAILABLE_RETRY == 30)
Check("FX muzzle", B.FX.MUZZLE_HEIGHT == 1.5)
Check("GUARD", B.GUARD.CycleExtra == 15 and B.GUARD.MaxSeconds == 600 and B.GUARD.GraceSeconds == 1.5)

--.. catalog coverage: 49 keys, each in exactly one egg, every key has an ability row, no extra rows, 8 egg tiers
local petCount = 0
for _ in pairs(Catalog.PETS) do petCount += 1 end
Check("49 catalog pets", petCount == 49, petCount)
local inEggs = {}
for eggKey, egg in pairs(Catalog.EGGS) do
	for petKey in pairs(egg.Pets) do inEggs[petKey] = (inEggs[petKey] or 0) + 1 end
end
local badEgg, noRow = 0, 0
for key in pairs(Catalog.PETS) do
	if inEggs[key] ~= 1 then badEgg += 1 end
	if B.SPECIES_ABILITY[key] == nil then noRow += 1 end
end
Check("each pet in exactly one egg", badEgg == 0, badEgg)
Check("every pet has an ability row", noRow == 0, noRow)
local rows, extra = 0, 0
for key in pairs(B.SPECIES_ABILITY) do
	rows += 1
	if Catalog.PETS[key] == nil then extra += 1 end
end
Check("49 ability rows", rows == 49, rows)
Check("no extra ability rows", extra == 0, extra)
local tiers, tierSet = 0, {}
for eggKey, tier in pairs(B.EGG_TIERS) do
	tiers += 1
	tierSet[tier] = true
	Check("tier egg in catalog " .. eggKey, Catalog.EGGS[eggKey] ~= nil)
end
Check("8 egg tiers", tiers == 8, tiers)
for t = 1, 8 do Check("tier " .. t .. " present", tierSet[t] == true) end
local eggCount = 0
for eggKey, egg in pairs(Catalog.EGGS) do
	eggCount += 1
	Check("tier matches Order " .. eggKey, B.EGG_TIERS[eggKey] == egg.Order)
end
Check("8 catalog eggs", eggCount == 8, eggCount)
local kinds = {Yield = 0, Haste = 0, Guard = 0, Wild = 0, None = 0}
for _, ability in pairs(B.SPECIES_ABILITY) do
	if kinds[ability] then kinds[ability] += 1 end
end
Check("ability mix (PLAN 5: 9 Yield, 8 Haste, 8 Guard, 1 Wild, 23 None)",
	kinds.Yield == 9 and kinds.Haste == 8 and kinds.Guard == 8 and kinds.Wild == 1 and kinds.None == 23,
	("Y%d H%d G%d W%d N%d"):format(kinds.Yield, kinds.Haste, kinds.Guard, kinds.Wild, kinds.None))

--.. Validate: live catalog clean
local problems = B.Validate(Catalog)
Check("Validate(live) empty", #problems == 0, problems[1])

--.. Validate never errors on garbage
for _, junk in ipairs({nil, 5, "x", {}, {PETS = 3, EGGS = "y"}, {PETS = {}, EGGS = {["Basic Egg"] = 7}}}) do
	local ok, res = pcall(B.Validate, junk)
	Check("Validate garbage no error", ok and type(res) == "table", res)
end
Check("Validate(nil) reports", #B.Validate(nil) >= 1)

--.. Validate fake catalogs (deep-copied live catalog, then broken on purpose)
local function Copy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = Copy(v) end
	return c
end
local function FakeCatalog()
	return {PETS = Copy(Catalog.PETS), EGGS = Copy(Catalog.EGGS)}
end
local function Has(list, needle)
	for _, p in ipairs(list) do
		if p:find(needle, 1, true) then return true end
	end
	return false
end

local fake = FakeCatalog()
fake.PETS["Test Newbie"] = {Rarity = "Rare", DisplayName = "Newbie"}
fake.EGGS["Basic Egg"].Pets["Test Newbie"] = {Percent = 1, Rank = 3}
local p1 = B.Validate(fake)
Check("no ability row reported", #p1 == 1 and Has(p1, "Test Newbie") and Has(p1, "SPECIES_ABILITY"), p1[1])

fake = FakeCatalog()
fake.EGGS["Desert Egg"].Pets.Chest.Rank = 9
local p2 = B.Validate(fake)
Check("rank 9 flagged", #p2 == 1 and Has(p2, "Chest") and Has(p2, "rank 9"), p2[1])

fake = FakeCatalog()
fake.EGGS["Desert Egg"].Pets.Chest.Rank = 2.5
Check("rank 2.5 flagged", #B.Validate(fake) == 1)

fake = FakeCatalog()
fake.EGGS["Basic Egg"].Pets.Gregory = {Percent = 0.002}
Check("Gregory rankless ok (override)", #B.Validate(fake) == 0)
fake.EGGS["Basic Egg"].Pets.Cat.Rank = nil
local p3 = B.Validate(fake)
Check("missing rank flagged", #p3 == 1 and Has(p3, "Cat"), p3[1])

fake = FakeCatalog()
fake.EGGS["Toyland Egg"] = {Order = 9, Pets = {Cat = {Percent = 1, Rank = 1}}}
local p4 = B.Validate(fake)
Check("new egg: tier+zone+duplicate pool flagged", Has(p4, "EGG_TIERS") and Has(p4, "EGG_ZONES") and Has(p4, "2 egg pools"), #p4)

fake = FakeCatalog()
fake.PETS.Cat.Rarity = "Epic"
local p5 = B.Validate(fake)
Check("unknown rarity flagged", #p5 == 1 and Has(p5, "Epic"), p5[1])

fake = FakeCatalog()
fake.PETS.Cat = nil
local p6 = B.Validate(fake)
Check("row without catalog pet + pool pet missing flagged", Has(p6, "SPECIES_ABILITY row \"Cat\"") and Has(p6, "pool pet \"Cat\""), #p6)

local order1 = table.concat(B.Validate(fake), "|")
local order2 = table.concat(B.Validate(fake), "|")
Check("Validate output stable", order1 == order2)

local summary = ("WP-STATS balance: PASS %d / FAIL %d"):format(pass, fail)
if fail > 0 then summary ..= ": " .. table.concat(failures, "; ") end
return summary
