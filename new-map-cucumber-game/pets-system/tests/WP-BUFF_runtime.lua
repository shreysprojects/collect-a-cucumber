--[[
	WP-BUFF runtime tests (2026-09-22): Init / Start / Stop and the theft guard through the real entry
	point TryBlockTheft with an injected clock (its third argument must be ignored entirely), grace, one
	charge per frame, expired shields, the deferred ShieldBlocked effect, and ClearCucumber's
	"attributes first, then IncomeService.Refresh" order. Start only connects the PlacedCucumber tag
	signals + one Heartbeat sweeper, both disconnected by Stop() at the end (also on failure). The only
	Instances are UNPARENTED Models (attribute holders, one tagged while unparented), destroyed at the end.
	Run from an edit-peer eval:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-BUFF_runtime.lua"))()
]]
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local SRC = "http://127.0.0.1:8793/"

--..harness (same as WP-BUFF_core)..--
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
local GRACE = provided.PetBalance.GUARD.GraceSeconds

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 12 then table.insert(failures, name .. (detail and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

--..fakes..--
local T = 1790000000
local function Clock() return T end
local emitted, snapshots, refreshes = {}, {}, {}
local Effects = {Emit = function(event, owner, position) table.insert(emitted, {Event = event, Owner = owner, Position = position}) end}
local Income = {Refresh = function(model, now)
	--.. what IncomeService would re-pull at this moment: the attributes must already be mutated
	table.insert(refreshes, {Model = model, Now = now, Mods = #Buff.ModifiersOf(model, now)})
end}
local function Snapshot(player) table.insert(snapshots, player) end

local made = {}
local function Shield(id, expiresAt, charges)
	local m = Instance.new("Model") -- never parented
	m:SetAttribute("CucumberId", id)
	m:SetAttribute("PetBuff_Guard", expiresAt)
	m:SetAttribute("PetBuff_GuardSrc", "pet-guard")
	m:SetAttribute("PetBuff_GuardCharges", charges)
	table.insert(made, m)
	return m
end
local function GuardState(m)
	return tostring(m:GetAttribute("PetBuff_Guard")) .. "/" .. tostring(m:GetAttribute("PetBuff_GuardSrc")) .. "/" .. tostring(m:GetAttribute("PetBuff_GuardCharges"))
end

local ok, err = pcall(function()
	Buff.Init({IncomeService = Income, Effects = Effects, Clock = Clock, Rng = Random.new(7), Snapshot = Snapshot})
	Buff.Init({Clock = function() return 0 end}) -- second call: ignored with a warn
	Check("not started before Start", Buff.IsStarted() == false)
	Buff.Start()
	Buff.Start() -- idempotent
	Check("started", Buff.IsStarted() == true)

	--.. own clock: a caller `now` of 1e9 behaves exactly like nil
	local a = Shield("c-A", T + 100, 1)
	local b = Shield("c-B", T + 100, 1)
	Check("A blocked with now=1e9", Buff.TryBlockTheft(a, nil, 1e9) == true)
	Check("B blocked with nil", Buff.TryBlockTheft(b, nil) == true)
	Check("A and B end identical", GuardState(a) == GuardState(b), GuardState(a) .. " vs " .. GuardState(b))
	Check("last charge removed the shield", a:GetAttribute("PetBuff_Guard") == nil and a:GetAttribute("PetBuff_GuardCharges") == nil and a:GetAttribute("PetBuff_GuardSrc") == nil)
	Check("A grace with now=1e9", Buff.TryBlockTheft(a, nil, 1e9) == true)
	Check("B grace with nil", Buff.TryBlockTheft(b, nil) == true)
	T += GRACE - 0.01
	Check("A still in grace (own clock)", Buff.TryBlockTheft(a, nil, 0) == true)
	T += 0.02
	Check("A grace over, caller now ignored", Buff.TryBlockTheft(a, nil, T - 1) == false)
	Check("B grace over", Buff.TryBlockTheft(b, nil) == false)

	--.. an expired shield never blocks, whatever the caller claims
	local c = Shield("c-C", T - 1, 1)
	Check("expired shield, caller now in the past", Buff.TryBlockTheft(c, nil, T - 100) == false)
	Check("expired shield untouched by the check", c:GetAttribute("PetBuff_GuardCharges") == 1)

	--.. two zombies in the same frame: one charge
	local d = Shield("c-D", T + 50, 1)
	local before = Buff.GetDiagnostics()
	local first = Buff.TryBlockTheft(d, nil)
	local second = Buff.TryBlockTheft(d, nil)
	local after = Buff.GetDiagnostics()
	Check("same frame: both denied", first == true and second == true)
	Check("same frame: one ShieldBlock", after.ShieldBlocks - before.ShieldBlocks == 1, after.ShieldBlocks - before.ShieldBlocks)
	Check("same frame: one GraceReject", after.GraceRejects - before.GraceRejects == 1)

	--.. two charges: the second is spent only after the grace
	local e = Shield("c-E", T + 50, 2)
	Check("2 charges first block", Buff.TryBlockTheft(e, nil) == true and e:GetAttribute("PetBuff_GuardCharges") == 1)
	Check("2 charges shield kept", e:GetAttribute("PetBuff_Guard") == T + 50)
	T += GRACE + 0.1
	Check("2 charges second block", Buff.TryBlockTheft(e, nil) == true and e:GetAttribute("PetBuff_Guard") == nil)

	--.. bad input never errors
	Check("nil cucumber", Buff.TryBlockTheft(nil, nil) == false)
	Check("table cucumber", Buff.TryBlockTheft({}, nil) == false)
	local part = Instance.new("Part") -- never parented
	table.insert(made, part)
	Check("non-Model cucumber", Buff.TryBlockTheft(part, nil) == false)
	local plain = Instance.new("Model")
	table.insert(made, plain)
	Check("no shield at all", Buff.TryBlockTheft(plain, nil) == false)

	--.. the ShieldBlocked effects are deferred (never inside the synchronous check)
	Check("no effect emitted synchronously", #emitted == 0, #emitted)
	task.wait()
	local shields = 0
	for _, x in ipairs(emitted) do
		if x.Event.Kind == "ShieldBlocked" and typeof(x.Event.At) == "Vector3" and typeof(x.Position) == "Vector3"
			and type(x.Event.CucumberId) == "string" and typeof(x.Event.Cucumber) == "Instance" then
			shields += 1
		end
	end
	Check("ShieldBlocked per spent charge (A, B, D, E x2)", shields == 5, shields)
	Check("no snapshot without an owner", #snapshots == 0, #snapshots)

	--.. ClearCucumber: attributes first, then Refresh (tagged model only); snapshot deferred by owner
	local f = Instance.new("Model") -- never parented; tagged while unparented (no signal fires)
	table.insert(made, f)
	f:SetAttribute("CucumberId", "c-F")
	f:SetAttribute("PetBuff_Yield", T + 60)
	f:SetAttribute("PetBuff_Haste", T + 60)
	CollectionService:AddTag(f, "PlacedCucumber")
	Check("F has 2 modifiers", #Buff.ModifiersOf(f, T) == 2)
	Check("ClearCucumber F", Buff.ClearCucumber(f, "Stolen") == true)
	Check("Refresh called once", #refreshes == 1, #refreshes)
	Check("Refresh saw the cleared state", refreshes[1] and refreshes[1].Mods == 0 and refreshes[1].Now == T)
	local g = Instance.new("Model")
	table.insert(made, g)
	g:SetAttribute("PetBuff_Yield", T + 60)
	Check("ClearCucumber untagged", Buff.ClearCucumber(g, "PickUp") == true)
	Check("untagged: no Refresh", #refreshes == 1, #refreshes)

	--.. grants: a started service refuses a non-player / an unknown ability (no instance lookups)
	local gok, gwhy = Buff.Grant(nil, {PetId = "p"}, "Yield")
	Check("grant bad player", gok == false and gwhy == "BadPlayer", gwhy)

	local diag = Buff.GetDiagnostics()
	Check("diag ShieldBlocks", diag.ShieldBlocks == 5, diag.ShieldBlocks)
	Check("diag Cleared", diag.Cleared == 2, diag.Cleared)
	Check("diag Started", diag.Started == 1)
	Check("diag errors 0", diag.Errors == 0, diag.Errors)
end)
Check("runtime block ran", ok, err)
pcall(Buff.Stop)
Check("stopped", Buff.IsStarted() == false)
for _, inst in ipairs(made) do
	CollectionService:RemoveTag(inst, "PlacedCucumber")
	inst:Destroy()
end

return ("WP-BUFF runtime: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
