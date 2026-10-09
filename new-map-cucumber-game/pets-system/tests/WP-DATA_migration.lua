-- WP-DATA migration: ServerStorage.PetDataMigration over the real test-profile fixture + edge cases
-- (CONTRACTS section 2 WP-DATA / 3.4). Read-only: PetBalance / PetStats / PetDataMigration are loaded
-- from the loopback src server (:8793) with fake ReplicatedStorage lookups (the live PetsCatalog is
-- required read-only), the fixture JSON from the tests server (:8795). Creates no instances.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 15 then failures[#failures + 1] = name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "") end
	end
end

local function Fetch(port, file)
	return HttpService:GetAsync(("http://127.0.0.1:%d/%s?t=%s"):format(port, file, tostring(os.clock())))
end

--..module loading with injected dependencies..--
local Catalog = require(ReplicatedStorage.Modules.PetsCatalog)
local deps = {PetsCatalog = Catalog}
local function Marker(name) return {__dep = name} end
local fakeModules = {}
function fakeModules:FindFirstChild(name) return deps[name] ~= nil and Marker(name) or nil end
function fakeModules:WaitForChild(name) assert(deps[name] ~= nil, "missing dep " .. name) return Marker(name) end
local fakeRS = {}
function fakeRS:FindFirstChild(name) return name == "Modules" and fakeModules or nil end
function fakeRS:WaitForChild(name) assert(name == "Modules", name) return fakeModules end
local fakeGame = setmetatable({}, {__index = function(_, k)
	if k == "GetService" then
		return function(_, name)
			if name == "ReplicatedStorage" then return fakeRS end
			return game:GetService(name)
		end
	end
	return game[k]
end})
local function Load(file)
	local fn, err = loadstring(Fetch(8793, file), "=" .. file)
	assert(fn, err)
	setfenv(fn, setmetatable({
		game = fakeGame,
		require = function(x)
			if type(x) == "table" and x.__dep then return deps[x.__dep] end
			return require(x)
		end,
	}, {__index = getfenv(0)}))
	return fn()
end
deps.PetBalance = Load("ReplicatedStorage.Modules.PetBalance.lua")
deps.PetStats = Load("ReplicatedStorage.Modules.PetStats.lua")
local PetStats = deps.PetStats
local M = Load("ServerStorage.PetDataMigration.lua")

--..helpers..--
local function DeepCopy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = DeepCopy(x) end
	return c
end
local function DeepEqual(a, b)
	if a ~= a and b ~= b then return true end -- NaN
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not DeepEqual(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
local function Gen(prefix, list)
	local n = 0
	return function()
		n += 1
		if list and list[n] then return list[n] end
		return ("%s-%03d"):format(prefix, n)
	end
end
local function Spawnable(k) return Catalog.PETS[k] ~= nil end
local function AllIds(list)
	for _, rec in ipairs(list) do
		if type(rec) == "table" and not (type(rec.Id) == "string" and #rec.Id >= 1 and #rec.Id <= 64) then return false end
	end
	return true
end
local function HasWarning(report, prefix)
	for _, w in ipairs(report.Warnings or {}) do
		if w:sub(1, #prefix) == prefix then return true end
	end
	return false
end

Check("SCHEMA_VERSION 1", M.SCHEMA_VERSION == 1)

--..1. the real fixture (4 legacy pets, 3 eggs incl. the two ghost eggs, 2 cucumbers, Version 2)..--
local fixture = HttpService:JSONDecode(Fetch(8795, "WP-DATA_fixture_profile.json"))
do
	local data = DeepCopy(fixture.Data)
	local before = DeepCopy(data)
	local base = data.Base
	local posRefs, cucRefs, eggRefs = {}, {}, {}
	for i, p in ipairs(base.Pets) do posRefs[i] = p.Pos end
	for i, c in ipairs(base.Cucumbers) do cucRefs[i] = c end
	for i, e in ipairs(base.Eggs) do eggRefs[i] = e end
	local r = M.Migrate(data, {GenerateId = Gen("id"), Now = 1790106800, IsSpawnable = Spawnable, Scope = "All"})
	Check("fixture: no error", r.Error == nil, r.Error)
	Check("fixture: Legacy", r.Legacy == true)
	Check("fixture: Changed", r.Changed == true)
	Check("fixture: 4 pet ids minted", r.IdsAssigned == 4, r.IdsAssigned)
	local seen, distinct = {}, true
	for _, p in ipairs(base.Pets) do
		if type(p.Id) ~= "string" or seen[p.Id] then distinct = false end
		seen[p.Id] = true
	end
	Check("fixture: pet ids valid + distinct", distinct and AllIds(base.Pets))
	-- Treasure Gem (Desert tier 2: 4.4/s), Dog (rank 2: 0.55/s), then the two Cats (0.5/s) by Id
	local cats = {base.Pets[1].Id, base.Pets[2].Id}
	table.sort(cats)
	local expected = {base.Pets[3].Id, base.Pets[4].Id, cats[1], cats[2]}
	Check("fixture: roster = 4 ids in Income/DPS/Id order", DeepEqual(base.PetRoster, expected), table.concat(base.PetRoster or {}, ","))
	Check("fixture: RosterSize 4", r.RosterSize == 4)
	Check("fixture: PetNoticePending", base.PetNoticePending == true)
	Check("fixture: 3 egg ids", r.EggIds == 3 and AllIds(base.Eggs), r.EggIds)
	Check("fixture: 2 cucumber ids", r.CucumberIds == 2 and AllIds(base.Cucumbers), r.CucumberIds)
	Check("fixture: PetSchemaVersion 1", base.PetSchemaVersion == 1)
	Check("fixture: Version still 2", base.Version == 2)
	Check("fixture: counts unchanged", #base.Pets == 4 and #base.Eggs == 3 and #base.Cucumbers == 2 and #base.Builds == 51)
	local posOk = true
	for i, p in ipairs(base.Pets) do
		if p.Pos ~= posRefs[i] or not DeepEqual(p.Pos, before.Base.Pets[i].Pos) then posOk = false end
	end
	Check("fixture: Pos arrays untouched", posOk)
	local refsOk = true
	for i, c in ipairs(base.Cucumbers) do if c ~= cucRefs[i] then refsOk = false end end
	for i, e in ipairs(base.Eggs) do if e ~= eggRefs[i] then refsOk = false end end
	Check("fixture: egg/cucumber records same tables", refsOk)
	local cat, gem = base.Pets[1], base.Pets[3]
	Check("fixture: SourceEgg", cat.SourceEgg == "Basic Egg" and gem.SourceEgg == "Desert Egg" and base.Pets[4].SourceEgg == "Basic Egg")
	Check("fixture: Material ''", cat.Material == "" and gem.Material == "")
	Check("fixture: Mutations {}", type(cat.Mutations) == "table" and #cat.Mutations == 0 and next(cat.Mutations) == nil)
	Check("fixture: AcquiredAt 0", cat.AcquiredAt == 0 and gem.AcquiredAt == 0)
	Check("fixture: AbilityRemaining 60", cat.AbilityRemaining == 60 and gem.AbilityRemaining == 60)
	Check("fixture: no SourceEggId invented", cat.SourceEggId == nil and cat.EggKg == nil)
	Check("fixture: egg Mutations stay strings", base.Eggs[3].Mutations == "SHADOW,RADIOACTIVE,FROZEN" and base.Eggs[1].Material == "Golden")
	Check("fixture: cucumber Mutations stay strings", base.Cucumbers[1].Mutations == "" and base.Cucumbers[2].SizeTier == "MASSIVE")
	--.. strip everything the migration may add -> identical to the input (keys outside Base included)
	local stripped = DeepCopy(data)
	for _, key in ipairs({"Pets", "Eggs", "Cucumbers"}) do
		for _, rec in ipairs(stripped.Base[key]) do rec.Id = nil end
	end
	for _, p in ipairs(stripped.Base.Pets) do
		p.SourceEgg, p.Material, p.Mutations, p.AcquiredAt, p.AbilityRemaining = nil, nil, nil, nil, nil
	end
	stripped.Base.PetRoster, stripped.Base.PetNoticePending, stripped.Base.PetSchemaVersion = nil, nil, nil
	Check("fixture: nothing else changed", DeepEqual(stripped, before))
	Check("fixture: JSON encodable", (pcall(HttpService.JSONEncode, HttpService, data)))
	Check("fixture: migrated pets Calculate Valid", PetStats.Calculate(gem).Valid == true and math.abs(PetStats.Calculate(gem).Income - 4.4) < 1e-9)

	--.. second run: zero changes, identical ids
	local snap = DeepCopy(data)
	local rosterRef = base.PetRoster
	local r2 = M.Migrate(data, {GenerateId = Gen("again"), IsSpawnable = Spawnable, Scope = "All"})
	Check("rerun: Changed false", r2.Changed == false)
	Check("rerun: Legacy false", r2.Legacy == false)
	Check("rerun: nothing minted", r2.IdsAssigned == 0 and r2.EggIds == 0 and r2.CucumberIds == 0)
	Check("rerun: data identical", DeepEqual(data, snap))
	Check("rerun: roster table kept", base.PetRoster == rosterRef)
	local r3 = M.Migrate(data, {GenerateId = Gen("p"), IsSpawnable = Spawnable, Scope = "Pets"})
	Check("rerun Scope Pets: no change", r3.Changed == false and DeepEqual(data, snap))

	--.. the default IsSpawnable (live Assets.Pets) + default GUIDs give the same roster shape
	local live = DeepCopy(fixture.Data)
	local r4 = M.Migrate(live, nil)
	Check("defaults: no error", r4.Error == nil)
	Check("defaults: GUID ids (36 chars)", #live.Base.Pets[1].Id == 36 and #live.Base.Eggs[1].Id == 36)
	Check("defaults: roster 4 (models exist)", #live.Base.PetRoster == 4 and live.Base.PetRoster[1] == live.Base.Pets[3].Id)
end

--..2. 9 legacy pets -> roster 6, 9 still owned..--
do
	local keys = {"Cat", "Dog", "Bunny", "Wolf", "Tabby", "Fox", "Barrel", "Chest", "Cactus"}
	local pets = {}
	for i, k in ipairs(keys) do pets[i] = {Pet = k, Pos = {i, 2.5, i}} end
	local d = {Base = {Version = 2, Pets = pets, Eggs = {}, Cucumbers = {}, Builds = {}}}
	local r = M.Migrate(d, {GenerateId = Gen("n"), IsSpawnable = Spawnable})
	Check("nine: 9 owned", #d.Base.Pets == 9 and AllIds(d.Base.Pets))
	Check("nine: roster 6", #d.Base.PetRoster == 6 and r.RosterSize == 6)
	local idOf = {}
	for _, p in ipairs(d.Base.Pets) do idOf[p.Pet] = p.Id end
	local want = {idOf.Cactus, idOf.Chest, idOf.Barrel, idOf.Fox, idOf.Tabby, idOf.Wolf} -- 30, 7.8, 4, 3.75, 1.75, 1.625
	Check("nine: best six by income", DeepEqual(d.Base.PetRoster, want), table.concat(d.Base.PetRoster, ","))
	Check("nine: notice", d.Base.PetNoticePending == true)
end

--..3. duplicate pet ids repaired (first kept), minted ids never collide, roster repaired..--
do
	local d = {Base = {Version = 2, PetSchemaVersion = 1, PetRoster = {"A", "A", "B", "ghost"},
		Pets = {{Id = "A", Pet = "Cat"}, {Id = "A", Pet = "Dog"}, {Id = "B", Pet = "Fox"}}, Eggs = {}, Cucumbers = {}}}
	local r = M.Migrate(d, {GenerateId = Gen("x", {"A", "B", "C"}), IsSpawnable = Spawnable})
	local p = d.Base.Pets
	Check("dup: first keeps A", p[1].Id == "A" and p[1].Pet == "Cat")
	Check("dup: later copy re-Id'd without collision", p[2].Id == "C" and p[3].Id == "B", tostring(p[2].Id))
	Check("dup: report", r.DuplicateIds == 1 and r.IdsAssigned == 1 and HasWarning(r, "DuplicatePetId:A"))
	Check("dup: roster repaired", DeepEqual(d.Base.PetRoster, {"A", "B"}), table.concat(d.Base.PetRoster, ","))
	Check("dup: not legacy, no notice", r.Legacy == false and d.Base.PetNoticePending == nil)
	Check("dup: both species still owned", #p == 3)
end

--..4. unknown species kept, excluded from the roster..--
do
	local d = {Base = {Version = 2, Pets = {{Pet = "Nonexistent Pet", Pos = {1, 2, 3}, Extra = "x"}, {Pet = 42}, {Pet = "Cat"}}, Eggs = {}, Cucumbers = {}}}
	local r = M.Migrate(d, {GenerateId = Gen("u"), IsSpawnable = function() return true end})
	local p = d.Base.Pets
	Check("unknown: kept + ids", #p == 3 and AllIds(p) and p[1].Pet == "Nonexistent Pet" and p[2].Pet == 42)
	Check("unknown: extra fields kept", p[1].Extra == "x" and DeepEqual(p[1].Pos, {1, 2, 3}))
	Check("unknown: SourceEgg stays nil", p[1].SourceEgg == nil and p[2].SourceEgg == nil)
	Check("unknown: defaults filled", p[1].Material == "" and p[1].AbilityRemaining == 60 and p[1].AcquiredAt == 0)
	Check("unknown: roster = the Cat only", DeepEqual(d.Base.PetRoster, {p[3].Id}))
	Check("unknown: warning", HasWarning(r, "UnknownSpecies:Nonexistent Pet"))
	Check("unknown: notice (legacy pets existed)", d.Base.PetNoticePending == true)
end

--..5. string mutations -> array; broken arrays cleaned; unknown names kept byte-for-byte..--
do
	local d = {Base = {Version = 2, Pets = {
		{Pet = "Cat", Mutations = "neon, SHADOW,Foo"},
		{Pet = "Dog", Mutations = {"NEON", 5, "VOID"}},
		{Pet = "Fox", Mutations = 7},
		{Pet = "Wolf", Mutations = {[1] = "NEON", [3] = "VOID"}},
	}, Eggs = {}, Cucumbers = {}}}
	local r = M.Migrate(d, {GenerateId = Gen("m"), IsSpawnable = Spawnable})
	local p = d.Base.Pets
	Check("mut: string -> array", DeepEqual(p[1].Mutations, {"NEON", "SHADOW", "Foo"}), table.concat(p[1].Mutations, ","))
	Check("mut: non-strings dropped", DeepEqual(p[2].Mutations, {"NEON", "VOID"}))
	Check("mut: number -> {}", DeepEqual(p[3].Mutations, {}))
	Check("mut: holes cleaned", DeepEqual(p[4].Mutations, {"NEON", "VOID"}))
	Check("mut: UnknownTraits counts Foo", r.UnknownTraits == 1, r.UnknownTraits)
end

--..6. existing traits preserved (no overwrite, no re-casing, nothing written)..--
do
	local rec = {Id = "keep-1", Pet = "Cat", SourceEgg = "Basic Egg", SourceEggId = "egg-9", Material = "Golden",
		Mutations = {"neon", "ROYAL", "Weird"}, EggKg = 5, AcquiredAt = 1790000000, Pos = {1, 0, 2}, AbilityRemaining = 12.5, Custom = {a = 1}}
	local rec2 = {Id = "keep-2", Pet = "Dog", SourceEgg = "Some Future Egg", Material = "Plastic", Mutations = {}, AcquiredAt = 5, AbilityRemaining = 0}
	local d = {Base = {Version = 2, PetSchemaVersion = 1, PetRoster = {"keep-1"}, Pets = {rec, rec2}, Eggs = {}, Cucumbers = {}}}
	local snap = DeepCopy(d)
	local r = M.Migrate(d, {GenerateId = Gen("k"), IsSpawnable = Spawnable})
	Check("traits: untouched", DeepEqual(d, snap))
	Check("traits: Changed false", r.Changed == false)
	Check("traits: UnknownTraits = Weird + Plastic records", r.UnknownTraits == 2, r.UnknownTraits)
end

--..7. Version = 1 base with cucumbers: Version and cucumber records unchanged (only Ids added)..--
do
	local c1 = {Zone = "Spawn", Type = "Cucumber", Name = "Cucumber", Mutations = "", Golden = false}
	local c2 = {Zone = "Desert", Type = "Desert Palm", Name = "Desert Palm", Mutations = "NEON"}
	local d = {Base = {Version = 1, Cucumbers = {c1, c2}, Builds = {{Key = "SpikeTrap"}}, Pets = {}, Eggs = {}}}
	local r = M.Migrate(d, {GenerateId = Gen("v"), IsSpawnable = Spawnable})
	local b = d.Base
	Check("v1: Version stays 1", b.Version == 1)
	Check("v1: cucumbers kept", #b.Cucumbers == 2 and b.Cucumbers[1] == c1 and b.Cucumbers[2] == c2)
	Check("v1: fields unchanged", c1.Mutations == "" and c2.Mutations == "NEON" and c2.Type == "Desert Palm")
	Check("v1: ids only", r.CucumberIds == 2 and AllIds(b.Cucumbers))
	Check("v1: builds untouched", #b.Builds == 1 and b.Builds[1].Id == nil)
	Check("v1: no notice without pets", b.PetNoticePending == nil and DeepEqual(b.PetRoster, {}) and b.PetSchemaVersion == 1)
end

--..8. non-table Base / data -> report error, no throw..--
do
	for _, bad in ipairs({{nil}, {{}}, {{Base = "x"}}, {{Base = 5}}}) do
		local ok, r = pcall(M.Migrate, bad[1], {GenerateId = Gen("b")})
		Check("nobase: no throw", ok, r)
		Check("nobase: Error NoBase", ok and r.Error == "NoBase" and r.Changed == false)
	end
	local d = {Base = {}}
	local ok, r = pcall(M.Migrate, d, nil)
	Check("empty base: arrays created", ok and type(d.Base.Pets) == "table" and type(d.Base.Eggs) == "table" and type(d.Base.Cucumbers) == "table")
	Check("empty base: schema + empty roster, no notice", ok and d.Base.PetSchemaVersion == 1 and DeepEqual(d.Base.PetRoster, {}) and d.Base.PetNoticePending == nil and r.Changed == true)
	Check("empty base: Version untouched", d.Base.Version == nil)
end

--..9. roster repair on schema >= 1 (foreign / duplicate / non-string dropped, > 6 truncated, still owned)..--
do
	local pets = {}
	for i = 1, 8 do pets[i] = {Id = "o" .. i, Pet = "Cat"} end
	local d = {Base = {Version = 2, PetSchemaVersion = 1, Pets = pets, Eggs = {}, Cucumbers = {},
		PetRoster = {"x-foreign", "o1", "o1", 5, "o2", "o3", "o4", "o5", "o6", "o7", "o8"}}}
	local r = M.Migrate(d, {GenerateId = Gen("r"), IsSpawnable = Spawnable})
	Check("repair: owned, first occurrence, max 6", DeepEqual(d.Base.PetRoster, {"o1", "o2", "o3", "o4", "o5", "o6"}), table.concat(d.Base.PetRoster, ","))
	Check("repair: 8 still owned", #d.Base.Pets == 8)
	Check("repair: Changed + size", r.Changed == true and r.RosterSize == 6 and r.Legacy == false)
	d.Base.PetRoster = "garbage"
	Check("repair: non-table -> {}", M.RepairRoster(d.Base) == true and DeepEqual(d.Base.PetRoster, {}))
	local keep = {"o3", "o1"}
	d.Base.PetRoster = keep
	Check("repair: clean roster unchanged", M.RepairRoster(d.Base) == false and d.Base.PetRoster == keep)
	d.Base.PetRoster = {"o3", [3] = "o1"}
	Check("repair: holey roster rewritten", M.RepairRoster(d.Base) == true and DeepEqual(d.Base.PetRoster, {"o3"}))
	Check("repair: bad input false", M.RepairRoster(nil) == false and M.RepairRoster({PetRoster = {}}) == false)
end

--..10. two egg records sharing one Id -> both kept, neither re-Id'd..--
do
	local e1, e2, e3 = {Id = "E1", EggName = "Basic"}, {Id = "E1", EggName = "Desert"}, {EggName = "Farm", Mutations = "NEON"}
	local d = {Base = {Version = 2, Pets = {}, Eggs = {e1, e2, e3, "junk"}, Cucumbers = {}}}
	local r = M.Migrate(d, {GenerateId = Gen("e", {"E1"}), IsSpawnable = Spawnable})
	Check("eggs: duplicates kept as is", #d.Base.Eggs == 4 and e1.Id == "E1" and e2.Id == "E1" and d.Base.Eggs[1] == e1 and d.Base.Eggs[2] == e2)
	Check("eggs: missing id minted without collision", e3.Id ~= nil and e3.Id ~= "E1" and e3.Mutations == "NEON")
	Check("eggs: report", r.DuplicateEggIds == 1 and r.EggIds == 1 and HasWarning(r, "DuplicateEggId:E1") and HasWarning(r, "EggNotTable:4"))
	Check("eggs: junk entry kept", d.Base.Eggs[4] == "junk")
end

--..11. cucumber duplicates get a fresh Id..--
do
	local d = {Base = {Version = 2, Pets = {}, Eggs = {}, Cucumbers = {{Id = "C1", Zone = "Spawn"}, {Id = "C1", Zone = "Farm"}, {Zone = "Snow"}}}}
	local r = M.Migrate(d, {GenerateId = Gen("c"), IsSpawnable = Spawnable})
	local c = d.Base.Cucumbers
	Check("cuc: first keeps C1", c[1].Id == "C1" and c[1].Zone == "Spawn")
	Check("cuc: later duplicate re-Id'd", c[2].Id ~= "C1" and c[2].Id ~= nil and c[3].Id ~= nil and c[2].Id ~= c[3].Id)
	Check("cuc: report", r.CucumberIds == 2 and r.DuplicateCucumberIds == 1)
end

--..12. Scope "Pets": Eggs / Cucumbers byte-identical (even records without Id)..--
do
	local d = {Base = {Version = 2,
		Eggs = {{EggName = "Basic", Mutations = "NEON"}, {Id = "E", EggName = "Farm"}, {Id = "E"}},
		Cucumbers = {{Zone = "Spawn"}, {Id = "C", Zone = "Farm"}, {Id = "C"}},
		Pets = {{Pet = "Cat"}, {Pet = "Fox", Mutations = "void"}}}}
	local eggsBefore, cucBefore = DeepCopy(d.Base.Eggs), DeepCopy(d.Base.Cucumbers)
	local eggsJson, cucJson = HttpService:JSONEncode(d.Base.Eggs), HttpService:JSONEncode(d.Base.Cucumbers)
	local r = M.Migrate(d, {GenerateId = Gen("s"), IsSpawnable = Spawnable, Scope = "Pets"})
	Check("scope: eggs identical", DeepEqual(d.Base.Eggs, eggsBefore) and HttpService:JSONEncode(d.Base.Eggs) == eggsJson)
	Check("scope: cucumbers identical", DeepEqual(d.Base.Cucumbers, cucBefore) and HttpService:JSONEncode(d.Base.Cucumbers) == cucJson)
	Check("scope: pets migrated", AllIds(d.Base.Pets) and DeepEqual(d.Base.Pets[2].Mutations, {"VOID"}) and #d.Base.PetRoster == 2)
	Check("scope: report counts", r.EggIds == 0 and r.CucumberIds == 0 and r.DuplicateEggIds == 0 and r.IdsAssigned == 2)
	local d2 = {Base = {Pets = {}}}
	M.Migrate(d2, {GenerateId = Gen("s2"), Scope = "Pets"})
	Check("scope: missing Eggs/Cucumbers not created", d2.Base.Eggs == nil and d2.Base.Cucumbers == nil and d2.Base.PetSchemaVersion == 1)
	local d3 = {Base = {Pets = {}, Eggs = {{EggName = "Basic"}}}}
	local r3 = M.Migrate(d3, {GenerateId = Gen("s3"), Scope = "Bogus"})
	Check("scope: unknown scope = Pets", d3.Base.Eggs[1].Id == nil and HasWarning(r3, "UnknownScope"))
end

--..13. AbilityRemaining range + AcquiredAt validation..--
do
	local values = {-1, 61, 0 / 0, math.huge, "30", 0, 60, 30.5}
	local want = {60, 60, 60, 60, 60, 0, 60, 30.5}
	local pets = {}
	for i, v in ipairs(values) do pets[i] = {Id = "a" .. i, Pet = "Cat", AbilityRemaining = v, AcquiredAt = (i == 1) and (0 / 0) or 100} end
	local d = {Base = {Version = 2, PetSchemaVersion = 1, PetRoster = {}, Pets = pets, Eggs = {}, Cucumbers = {}}}
	M.Migrate(d, {GenerateId = Gen("t"), IsSpawnable = Spawnable})
	local ok = true
	for i, v in ipairs(want) do if pets[i].AbilityRemaining ~= v then ok = false end end
	Check("ability: out-of-range -> 60, valid kept", ok)
	Check("ability: NaN AcquiredAt -> 0, valid kept", pets[1].AcquiredAt == 0 and pets[2].AcquiredAt == 100)
end

--..14. non-table pet entries kept in place (Invalid)..--
do
	local d = {Base = {Version = 2, Pets = {5, {Pet = "Cat"}, "str"}, Eggs = {}, Cucumbers = {}}}
	local r = M.Migrate(d, {GenerateId = Gen("i"), IsSpawnable = Spawnable})
	local p = d.Base.Pets
	Check("invalid: kept in place", #p == 3 and p[1] == 5 and p[3] == "str" and type(p[2].Id) == "string")
	Check("invalid: counted", r.Invalid == 2)
	Check("invalid: roster = the Cat", DeepEqual(d.Base.PetRoster, {p[2].Id}) and d.Base.PetNoticePending == true)
end

--..15. garbage arrays: warnings, no error, no schema marker when Pets is not a table..--
do
	local d = {Base = {Version = 2, Pets = "bad", Eggs = 7, Cucumbers = {}}}
	local ok, r = pcall(M.Migrate, d, {GenerateId = Gen("g")})
	Check("garbage: no throw", ok, r)
	Check("garbage: warnings", ok and HasWarning(r, "PetsNotTable") and HasWarning(r, "EggsNotTable"))
	Check("garbage: left alone, no marker", d.Base.Pets == "bad" and d.Base.Eggs == 7 and d.Base.PetSchemaVersion == nil and d.Base.PetRoster == nil)
end

--..16. a future schema is never lowered; legacy with zero pets gets no notice..--
do
	local d = {Base = {Version = 2, PetSchemaVersion = 2, PetRoster = {}, Pets = {}, Eggs = {}, Cucumbers = {}}}
	local r = M.Migrate(d, {GenerateId = Gen("f")})
	Check("future schema kept", d.Base.PetSchemaVersion == 2 and r.Changed == false)
	local e = {Base = {Version = 2, PetSchemaVersion = 0, Pets = {}, Eggs = {}, Cucumbers = {}}}
	local r2 = M.Migrate(e, {GenerateId = Gen("z")})
	Check("schema 0 = legacy, no pets -> no notice", r2.Legacy == true and e.Base.PetNoticePending == nil and e.Base.PetSchemaVersion == 1)
end

--..17. SelectInitialRoster directly..--
do
	local pets = {{Id = "b", Pet = "Cat"}, {Id = "a", Pet = "Cat"}, {Id = "c", Pet = "Fox"}, {Id = "d", Pet = "Nope"}, {Pet = "Cat"}, {Id = "b", Pet = "Cactus"}}
	Check("select: slots 2", DeepEqual(M.SelectInitialRoster(pets, Spawnable, 2), {"c", "a"}))
	Check("select: ties by Id, dup id first wins, invalid skipped", DeepEqual(M.SelectInitialRoster(pets, Spawnable, 6), {"c", "a", "b"}))
	Check("select: unspawnable excluded", DeepEqual(M.SelectInitialRoster(pets, function(k) return k ~= "Fox" end, 6), {"a", "b"}))
	Check("select: erroring isSpawnable -> none", DeepEqual(M.SelectInitialRoster(pets, function() error("x") end, 6), {}))
	Check("select: NaN slots -> SLOTS", #M.SelectInitialRoster(pets, Spawnable, 0 / 0) == 3)
	Check("select: non-table -> {}", DeepEqual(M.SelectInitialRoster(nil), {}))
end

--..18. default IsSpawnable (live catalog + Assets.Pets, read-only)..--
Check("IsSpawnable Cat", M.IsSpawnable("Cat") == (Catalog.ModelOf("Cat") ~= nil) and M.IsSpawnable("Cat") == true)
Check("IsSpawnable unknown", M.IsSpawnable("Nope") == false and M.IsSpawnable(nil) == false and M.IsSpawnable(5) == false)

--..19. a broken id generator errors cleanly (DataService pcalls -> Failed)..--
do
	local d = {Base = {Pets = {{Id = "dup", Pet = "Cat"}, {Pet = "Dog"}}}}
	local ok = pcall(M.Migrate, d, {GenerateId = function() return "dup" end})
	Check("generator exhaust -> error", not ok)
	local ok2 = pcall(M.Migrate, {Base = {Pets = {{Pet = "Dog"}}}}, {GenerateId = function() return nil end})
	Check("generator nil -> error", not ok2)
end

--..20. big mixed base: idempotent under a second run with another generator..--
do
	local d = {Base = {Version = 2,
		Pets = {{Pet = "Cat"}, 5, {Id = "X", Pet = "Dog", Mutations = "neon"}, {Id = "X", Pet = "Nope"}, {Pet = "Fox", Material = 3}},
		Eggs = {{EggName = "Basic"}, {Id = "E", EggName = "Farm"}, {Id = "E"}}, Cucumbers = {{Zone = "Spawn"}, {Id = "C"}, {Id = "C"}}}}
	M.Migrate(d, {GenerateId = Gen("one"), IsSpawnable = Spawnable})
	local snap = DeepCopy(d)
	local r2 = M.Migrate(d, {GenerateId = Gen("two"), IsSpawnable = Spawnable})
	Check("mixed: second run no change", r2.Changed == false and DeepEqual(d, snap))
	Check("mixed: material number -> ''", d.Base.Pets[5].Material == "")
end

local summary = ("WP-DATA migration: PASS %d / FAIL %d%s"):format(pass, fail, fail > 0 and (": " .. table.concat(failures, "; ")) or "")
return summary
