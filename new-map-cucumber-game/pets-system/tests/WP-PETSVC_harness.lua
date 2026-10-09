-- WP-PETSVC test harness (2026-09-22). Read-only: creates NO instances, changes nothing in the DataModel.
-- Loads PetBalance / PetStats / PetMotion / PetService from the src loopback server (:8793) into a fake
-- environment (game:GetService("ReplicatedStorage").Modules.X resolves to the loaded copies, the live
-- PetsCatalog / CucumberMutations / BuildCatalog are required for real) and builds plain-table fakes.
--   local H = loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-PETSVC_harness.lua"))()
--   local ctx = H.Setup({...})
local HttpService = game:GetService("HttpService")
local RealRS = game:GetService("ReplicatedStorage")
local SRC = "http://127.0.0.1:8793/"

local H = {}

local function MakeEnv(fakes)
	local FakeModules = {}
	function FakeModules:WaitForChild(name)
		if fakes[name] then return {__fakeModule = name, Name = name} end
		if fakes.__missing and fakes.__missing[name] then return nil end -- a partial install (the require must fail fast)
		return RealRS:WaitForChild("Modules"):WaitForChild(name, 5)
	end
	FakeModules.FindFirstChild = FakeModules.WaitForChild
	local FakeRS = {}
	function FakeRS:WaitForChild(name)
		if name == "Modules" then return FakeModules end
		return RealRS:WaitForChild(name, 5)
	end
	function FakeRS:FindFirstChild(name)
		if name == "Modules" then return FakeModules end
		return RealRS:FindFirstChild(name)
	end
	local FakeServerStorage = {}
	function FakeServerStorage:FindFirstChild() return nil end -- PetDataMigration etc. "not installed"
	function FakeServerStorage:WaitForChild() return nil end
	local FakeGame = {}
	function FakeGame:GetService(name)
		if name == "ReplicatedStorage" then return FakeRS end
		if name == "ServerStorage" then return FakeServerStorage end
		return game:GetService(name)
	end
	return setmetatable({
		game = FakeGame,
		require = function(m)
			if type(m) == "table" and m.__fakeModule then return fakes[m.__fakeModule] end
			return require(m)
		end,
	}, {__index = getfenv(0)})
end

local SourceCache = {}
function H.LoadFile(file, fakes)
	local src = SourceCache[file]
	if not src then
		src = HttpService:GetAsync(SRC .. file)
		SourceCache[file] = src
	end
	local fn, err = loadstring(src, "=" .. file)
	if not fn then error("compile " .. file .. ": " .. tostring(err)) end
	setfenv(fn, MakeEnv(fakes))
	return fn()
end

-- fresh copies of the three shared modules + PetService (fresh module state each call)
function H.LoadPetService(extraFakes)
	local fakes = {}
	fakes.PetBalance = H.LoadFile("ReplicatedStorage.Modules.PetBalance.lua", fakes)
	fakes.PetMotion = H.LoadFile("ReplicatedStorage.Modules.PetMotion.lua", fakes)
	fakes.PetStats = H.LoadFile("ReplicatedStorage.Modules.PetStats.lua", fakes)
	for k, v in pairs(extraFakes or {}) do fakes[k] = v end
	local PetService = H.LoadFile("ServerStorage.PetService.lua", fakes)
	return PetService, fakes
end

local function Attrs(obj)
	obj.Attrs = obj.Attrs or {}
	function obj:GetAttribute(k) return self.Attrs[k] end
	function obj:SetAttribute(k, v) self.Attrs[k] = v end
	return obj
end

function H.NewPlayer(userId, name)
	return Attrs({UserId = userId, Name = name or ("Tester" .. userId)})
end

function H.NewPlot(ownerId, name)
	return Attrs({Name = name or "Plot 1", CFrame = CFrame.new(100, 0, 50), Position = Vector3.new(100, 0, 50),
		Size = Vector3.new(60, 1, 60), Attrs = {Owner = ownerId}})
end

function H.NewModel()
	local m = Attrs({Destroyed = false})
	function m:Destroy() self.Destroyed = true end
	return m
end

function H.PetRec(id, key, extra)
	local rec = {Id = id, Pet = key, SourceEgg = nil, Material = "", Mutations = {}, AcquiredAt = 0, AbilityRemaining = 60}
	for k, v in pairs(extra or {}) do rec[k] = v end
	return rec
end

function H.NewProfile(pets, roster, eggs)
	return {Cash = 0, Base = {Version = 2, SavedAt = 0, Cucumbers = {}, Builds = {}, Eggs = eggs or {}, Pets = pets or {},
		PetRoster = roster or {}, PetSchemaVersion = 1}}
end

function H.NewDataService()
	local ds = {Data = {}, Saves = {}, Gen = {}, Closing = {}, Reports = {}}
	function ds.GetData(p) return ds.Data[p] end
	function ds.IsLoaded(p) return ds.Data[p] ~= nil end
	function ds.RequestSave(p) ds.Saves[p] = (ds.Saves[p] or 0) + 1 end
	function ds.GetGeneration(p) return ds.Gen[p] or 1 end
	function ds.IsClosing(p) return ds.Closing[p] == true end
	function ds.GetMigrationReport(p) return ds.Reports[p] end
	return ds
end

function H.NewIncome()
	local inc = {Producers = {}, Adds = 0, Removes = 0}
	function inc.SetPetProducer(p, id, model, rate) inc.Producers[id] = rate inc.Adds += 1 end
	function inc.RemovePetProducer(id) inc.Producers[id] = nil inc.Removes += 1 end
	function inc.GetTotals() return {Pet = 1.5, Cucumber = 10, CucumberBase = 8, Total = 11.5} end
	function inc.OnTotalsChanged(fn) inc.Fn = fn return function() end end
	return inc
end

function H.NewBuffs()
	local b = {Grants = {}, Result = true}
	function b.Grant(player, source, ability, now)
		table.insert(b.Grants, {Player = player, Source = source, Ability = ability, Now = now})
		if b.Result == true then return true, {Kind = ability} end
		return false, b.Result
	end
	function b.GuardSeconds() return 240 end
	return b
end

-- one player (UserId 1) with a profile, an owned fake plot, fakes wired into PetService.Init
-- opts: Pets, Roster, Eggs, Phase, Spawnable (fn), SpawnFail = {[petKey] = true}, Seed
function H.Setup(opts)
	opts = opts or {}
	local PetService, fakes = H.LoadPetService()
	local ctx = {PetService = PetService, Fakes = fakes, Sent = {}, Spawns = {}, T = {Now = 1.8e9, Phase = opts.Phase or "Day"}}
	ctx.DS = H.NewDataService()
	ctx.Income = H.NewIncome()
	ctx.Buffs = H.NewBuffs()
	ctx.Player = H.NewPlayer(1)
	ctx.Player:SetAttribute("BaseRestored", true)
	ctx.Plot = H.NewPlot(1)
	ctx.DS.Data[ctx.Player] = H.NewProfile(opts.Pets, opts.Roster, opts.Eggs)
	PetService.Init({
		DataService = ctx.DS,
		IncomeService = (not opts.NoIncome) and ctx.Income or nil,
		PetBuffService = (not opts.NoBuffs) and ctx.Buffs or nil,
		SendState = function(player, payload) table.insert(ctx.Sent, payload) end,
		Clock = function() return ctx.T.Now end,
		Rng = Random.new(opts.Seed or 7),
		Spawner = function(player, plot, record, spot)
			if opts.SpawnFail and opts.SpawnFail[record.Pet] then return nil end
			local m = H.NewModel()
			table.insert(ctx.Spawns, {Id = record.Id, Model = m, Spot = spot})
			return m
		end,
		IsSpawnable = opts.Spawnable or function(key) return fakes.PetStats.Calculate({Pet = key}).Valid end,
		CyclePhase = function() return ctx.T.Phase end,
		Migration = false,
	})
	function ctx.Data() return ctx.DS.Data[ctx.Player] end
	function ctx.Roster() return ctx.DS.Data[ctx.Player].Base.PetRoster end
	function ctx.SpawnCount(id)
		local n = 0
		for _, s in ipairs(ctx.Spawns) do if id == nil or s.Id == id then n += 1 end end
		return n
	end
	function ctx.LastSent() return ctx.Sent[#ctx.Sent] end
	return ctx
end

function H.Checker(name)
	local c = {Name = name, Pass = 0, Fail = 0, Failures = {}}
	function c.Check(cond, label)
		if cond then
			c.Pass += 1
		else
			c.Fail += 1
			table.insert(c.Failures, label)
		end
	end
	function c.Eq(a, b, label)
		c.Check(a == b, ("%s (got %s, want %s)"):format(label, tostring(a), tostring(b)))
	end
	function c.Run(label, fn)
		local ok, err = pcall(fn)
		if not ok then
			c.Fail += 1
			table.insert(c.Failures, label .. " THREW " .. tostring(err))
		end
	end
	function c.Summary()
		local first = {}
		for i = 1, math.min(#c.Failures, 8) do first[i] = c.Failures[i] end
		return ("WP-PETSVC %s: PASS %d / FAIL %d%s"):format(c.Name, c.Pass, c.Fail, #first > 0 and (": " .. table.concat(first, " | ")) or "")
	end
	return c
end

return H
