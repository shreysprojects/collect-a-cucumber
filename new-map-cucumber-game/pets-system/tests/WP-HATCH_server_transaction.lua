--[[
	WP-HATCH server transaction test (2026-09-22, read-only).
	Loads the PATCHED ServerScriptService.PetHatchService source from the loopback server (:8794) and
	runs it inside a sandbox (setfenv) whose game / workspace / services / DataService / PetService /
	BaseSaveAPI are plain-table fakes. Nothing is created or changed in the DataModel; the only live
	thing read is ReplicatedStorage.Modules.PetsCatalog (required, read-only).
	Covers CONTRACTS 4.2 / 7.4 / 8.2: validation gates, lock + HatchBusy, snapshot-before-grant,
	EggInfo shape, consume order (Consumed before Destroy), RequestSave, Begin payload, token-only
	finish (wrong / foreign / repeated / over-long token ignored), fallback timer + cancel, Duplicate,
	InventoryFull pause, grant error release, snapshot yield warning + re-validation, the three
	PetHatchDev fault boundaries, dev hatch / spawn / clear, PlayerRemoving.
	Returns "WP-HATCH server_transaction: PASS n / FAIL m: <first failures>".
]]
local HttpService = game:GetService("HttpService")
local RealCatalog = require(game:GetService("ReplicatedStorage").Modules.PetsCatalog)

local src = HttpService:GetAsync("http://127.0.0.1:8794/ServerScriptService.PetHatchService.server.lua")

local pass, fail, failures = 0, 0, {}
local function check(name, cond, detail)
	if cond then pass += 1 else
		fail += 1
		if #failures < 12 then table.insert(failures, name .. (detail and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

--..Fakes..--
local function Signal()
	local s = {Fns = {}}
	function s:Connect(fn) table.insert(self.Fns, fn) return {Disconnect = function() end} end
	function s:Fire(...) for _, fn in ipairs(self.Fns) do fn(...) end end
	return s
end

local Log = {} -- ordered event log of the transaction
local function log(e) table.insert(Log, e) end
local Tags = {} -- [inst] = {tag = true}

local function Fake(name, class, props)
	local o = {Name = name, ClassName = class, Attrs = {}, Children = {}, AttrSignals = {}}
	for k, v in pairs(props or {}) do o[k] = v end
	function o:GetAttribute(k) return self.Attrs[k] end
	function o:SetAttribute(k, v)
		if k == "Consumed" and v == true then log("consumed") end
		self.Attrs[k] = v
		local sig = self.AttrSignals[k]
		if sig then sig:Fire() end
	end
	function o:GetAttributeChangedSignal(k)
		self.AttrSignals[k] = self.AttrSignals[k] or Signal()
		return self.AttrSignals[k]
	end
	function o:FindFirstChild(n) return self.Children[n] end
	function o:WaitForChild(n) return self.Children[n] end
	function o:GetChildren() local t = {} for _, c in pairs(self.Children) do table.insert(t, c) end return t end
	function o:IsA(c) return self.ClassName == c or (c == "BasePart" and self.ClassName == "Part") end
	function o:IsDescendantOf(anc)
		local p = self.Parent
		while p do if p == anc then return true end p = p.Parent end
		return false
	end
	function o:GetPivot() return self.Pivot or CFrame.new() end
	function o:Destroy()
		log("destroy:" .. self.Name)
		self.Parent = nil
		self.Destroyed = true
		Tags[self] = nil
	end
	return o
end
local function Add(parent, child) parent.Children[child.Name] = child child.Parent = parent return child end

--.. services
local Now = 1000
local Players = Fake("Players", "Players")
Players.List = {}
Players.PlayerRemoving = Signal()
function Players:GetPlayers() local t = {} for _, p in ipairs(self.List) do table.insert(t, p) end return t end
function Players:GetPlayerByUserId(uid) for _, p in ipairs(self.List) do if p.UserId == uid then return p end end return nil end

local Heartbeat = Signal()
local RunService = {Heartbeat = Heartbeat}
function RunService:IsStudio() return true end

local CollectionService = {}
function CollectionService:GetTagged(tag)
	local t = {}
	for inst, set in pairs(Tags) do if set[tag] then table.insert(t, inst) end end
	table.sort(t, function(a, b) return a.Name < b.Name end)
	return t
end
function CollectionService:HasTag(inst, tag) return Tags[inst] ~= nil and Tags[inst][tag] == true end

local guidN = 0
local FakeHttp = {}
function FakeHttp:GenerateGUID() guidN += 1 return ("TOKEN-%04d"):format(guidN) end

--.. ReplicatedStorage: Modules (PetsCatalog real, PetBalance/PetStats fakes) + Remotes.PetHatch
local ReplicatedStorage = Fake("ReplicatedStorage", "ReplicatedStorage")
local Modules = Add(ReplicatedStorage, Fake("Modules", "Folder"))
local FakePetBalance = {
	TIMING = {REVEAL_FALLBACK = 100},
	ABILITIES = {Yield = {Duration = 90}, Haste = {Duration = 90}, Guard = {Charges = 1}},
	DEFAULT_DAY_SECONDS = 180, DEFAULT_NIGHT_SECONDS = 10,
}
local FakePetStats = {}
function FakePetStats.Calculate(record)
	return {Valid = true, Income = 0.5, ShotDamage = 3, ShotInterval = 2.5, DPS = 1.2, Ability = record.Pet == "Dog" and "Guard" or "Yield",
		AbilityChance = 0.01, Fighter = false}
end
function FakePetStats.GuardSeconds(d, n) return math.min(600, d + n + 15) end
Add(Modules, Fake("PetsCatalog", "ModuleScript", {Module = RealCatalog}))
Add(Modules, Fake("PetBalance", "ModuleScript", {Module = FakePetBalance}))
Add(Modules, Fake("PetStats", "ModuleScript", {Module = FakePetStats}))
local Remotes = Add(ReplicatedStorage, Fake("Remotes", "Folder"))
local PetHatch = Add(Remotes, Fake("PetHatch", "RemoteEvent"))
PetHatch.OnServerEvent = Signal()
PetHatch.Fired = {}
function PetHatch:FireClient(player, action, payload)
	log("begin")
	table.insert(self.Fired, {Player = player, Action = action, Payload = payload})
end

--.. DataService fake
local DS = {Loaded = {}, Closing = {}, Saves = 0, Gen = 7}
function DS.IsLoaded(p) return DS.Loaded[p] == true end
function DS.IsClosing(p) return DS.Closing[p] == true end
function DS.GetGeneration() return DS.Gen end
function DS.RequestSave() DS.Saves += 1 log("save") end
function DS.GetData() return {} end

--.. PetService fake
local PS = {Ready = {}, Mode = "ok", Grants = {}, Finish = {}, Detach = {}, Reserve = false, N = 0}
function PS.IsReady(p) return PS.Ready[p] == true end
function PS.GrantFromEgg(p, eggInfo, petKey)
	log("grant")
	table.insert(PS.Grants, {Player = p, EggInfo = eggInfo, PetKey = petKey})
	if PS.Mode == "throw" then error("boom") end
	if PS.Mode == "full" then return nil, {Error = "InventoryFull"} end
	if PS.Mode == "dup" then return {Id = "PET-OLD", Pet = "Cat", SourceEggId = eggInfo.EggId}, {Duplicate = true} end
	PS.N += 1
	return {Id = "PET-" .. PS.N, Pet = petKey, SourceEggId = eggInfo.EggId}, {Equipped = not PS.Reserve, Reserve = PS.Reserve, AutoEquipAfterCombat = false}
end
function PS.FinishPresentation(p, petId, spot, gen) table.insert(PS.Finish, {Player = p, PetId = petId, Spot = spot, Generation = gen}) return true end
function PS.DetachPlot(p, reason) table.insert(PS.Detach, {Player = p, Reason = reason}) end

--.. ServerStorage: DataService, PetService, BaseSaveAPI.Snapshot
local ServerStorage = Fake("ServerStorage", "ServerStorage")
Add(ServerStorage, Fake("DataService", "ModuleScript", {Module = DS}))
Add(ServerStorage, Fake("PetService", "ModuleScript", {Module = PS}))
local SaveApi = Add(ServerStorage, Fake("BaseSaveAPI", "Folder"))
local Snapshot = Add(SaveApi, Fake("Snapshot", "BindableFunction"))
Snapshot.Hook = nil
function Snapshot:Invoke(player)
	log("snapshot")
	if Snapshot.Hook then Snapshot.Hook(player) end
	return true
end

--.. workspace: Map.Lobby.Plots with one plot; attributes for the dev hook
local Workspace = Fake("Workspace", "Workspace")
function Workspace:GetServerTimeNow() return Now end
local Map = Add(Workspace, Fake("Map", "Model"))
local Lobby = Add(Map, Fake("Lobby", "Model"))
local Plots = Add(Lobby, Fake("Plots", "Folder"))
local plot = Add(Plots, Fake("Plot1", "Part", {Position = Vector3.new(0, 0, 0), Size = Vector3.new(40, 1, 40), CFrame = CFrame.new()}))
local placed = Add(plot, Fake("Placed", "Folder"))

--.. players
local function MakePlayer(name, uid)
	local p = Fake(name, "Player", {UserId = uid})
	p.Parent = Players
	local character = Fake("Character", "Model")
	Add(character, Fake("HumanoidRootPart", "Part", {Position = Vector3.new(0, 3, 0)}))
	p.Character = character
	table.insert(Players.List, p)
	return p
end
local alice = MakePlayer("Alice", 101)
local bob = MakePlayer("Bob", 202)
plot.Attrs.Owner = 101
alice.Attrs.BaseRestored = true
DS.Loaded[alice] = true
PS.Ready[alice] = true

local eggN = 0
local function MakeEgg(opts)
	opts = opts or {}
	eggN += 1
	local egg = Fake(("Egg%02d"):format(eggN), "Model", {Pivot = CFrame.new(opts.X or 0, 1.5, 0)})
	egg.PrimaryPart = Fake("Hitbox", "Part", {CFrame = CFrame.new(opts.X or 0, 1.5, 0), Size = Vector3.new(4, 5, 4)})
	egg.Attrs = {Owner = opts.Owner or 101, EggName = opts.EggName or "Basic", HatchAt = opts.HatchAt or (Now - 1),
		EggId = opts.NoId and nil or (opts.EggId or ("EGG-" .. eggN)), Kg = 12.5, Scale = 1.4, Material = opts.Material,
		Mutations = opts.Mutations or "NEON,SHADOW", DisplayName = "Basic Egg (12.5 kg)"}
	egg.Parent = opts.Parent or placed
	Tags[egg] = {PlacedEgg = true}
	return egg
end

--.. task fake: delays are captured and fired by hand
local Delays = {}
local FakeTask = {}
function FakeTask.delay(seconds, fn, ...)
	local h = {Seconds = seconds, Fn = fn, Args = table.pack(...), Cancelled = false}
	table.insert(Delays, h)
	return h
end
function FakeTask.cancel(h) if type(h) == "table" then h.Cancelled = true end end
function FakeTask.spawn(fn, ...) return fn(...) end
function FakeTask.defer(fn, ...) return fn(...) end
function FakeTask.wait() return 0 end
local function FireDelay(h) if h and not h.Cancelled then h.Fn(table.unpack(h.Args, 1, h.Args.n)) end end

local Warns, Prints = {}, {}
local InstanceNewCalls = 0
local fakeGame = {}
function fakeGame:GetService(name)
	return ({Players = Players, ReplicatedStorage = ReplicatedStorage, CollectionService = CollectionService,
		RunService = RunService, ServerStorage = ServerStorage, HttpService = FakeHttp})[name] or error("no fake service " .. name)
end

local env = {
	game = fakeGame, workspace = Workspace, Vector3 = Vector3, CFrame = CFrame, Random = Random, task = FakeTask,
	math = math, string = string, table = table, typeof = typeof, type = type, tostring = tostring, tonumber = tonumber,
	pairs = pairs, ipairs = ipairs, pcall = pcall, error = error, select = select, setmetatable = setmetatable,
	coroutine = coroutine, os = os, next = next, unpack = unpack, getmetatable = getmetatable, rawget = rawget,
	Instance = {new = function() InstanceNewCalls += 1 error("Instance.new called in the sandbox") end},
	warn = function(...) local t = table.pack(...) local s = {} for i = 1, t.n do s[i] = tostring(t[i]) end table.insert(Warns, table.concat(s, " ")) end,
	print = function(...) local t = table.pack(...) local s = {} for i = 1, t.n do s[i] = tostring(t[i]) end table.insert(Prints, table.concat(s, " ")) end,
	require = function(m)
		if type(m) == "table" and m.Module ~= nil then return m.Module end
		error("sandbox require of an unknown module")
	end,
}
local chunk, err = loadstring(src, "=PetHatchService(patched)")
if not chunk then return "WP-HATCH server_transaction: COMPILE FAIL " .. tostring(err) end
setfenv(chunk, env)
local okLoad, loadErr = pcall(chunk)
check("script loads in the sandbox", okLoad, loadErr)
if not okLoad then return ("WP-HATCH server_transaction: PASS %d / FAIL %d: %s"):format(pass, fail, table.concat(failures, "; ")) end
check("no Instance.new at load (remotes found)", InstanceNewCalls == 0)
check("ready print mentions PetService", Prints[#Prints] and Prints[#Prints]:find("PetService", 1, true) ~= nil, Prints[#Prints])

local function Tick() Heartbeat:Fire(0.2) end
local function Opened(player, token) PetHatch.OnServerEvent:Fire(player, "Opened", token) end
local function Dev(cmd) Workspace:SetAttribute("PetHatchDev", cmd) end
local function Reset() table.clear(Log) end
local function Seq() return table.concat(Log, ",") end
local function LastBegin() local f = PetHatch.Fired[#PetHatch.Fired] return f and f.Payload end

--..1. validation gates (nothing may hatch)..--
local egg1 = MakeEgg({Material = "Golden"})
alice.Attrs.BaseRestored = nil
Reset() Tick()
check("gate: BaseRestored nil -> no hatch", #PS.Grants == 0 and egg1.Attrs.Hatching == nil and #Log == 0, Seq())
alice.Attrs.BaseRestored = true
PS.Ready[alice] = false
Reset() Tick()
check("gate: PetService not ready -> no hatch", #PS.Grants == 0 and egg1.Attrs.Hatching == nil, Seq())
PS.Ready[alice] = true
DS.Closing[alice] = true
Reset() Tick()
check("gate: closing -> no hatch", #PS.Grants == 0 and egg1.Attrs.Hatching == nil, Seq())
DS.Closing[alice] = nil
alice.Character.Children.HumanoidRootPart.Position = Vector3.new(30, 3, 30)
Reset() Tick()
check("gate: not standing on the egg -> no hatch", #PS.Grants == 0, Seq())
alice.Character.Children.HumanoidRootPart.Position = Vector3.new(0, 3, 0)
egg1.Attrs.HatchAt = Now + 50
Reset() Tick()
check("gate: countdown running -> no hatch", #PS.Grants == 0, Seq())
egg1.Attrs.HatchAt = Now - 1
egg1.Attrs.EggId = nil
Reset() Tick()
check("gate: egg without EggId -> no hatch, lock released", #PS.Grants == 0 and egg1.Attrs.Hatching == nil and not egg1.Destroyed, Seq())
egg1.Attrs.EggId = "EGG-1"

--..2. the normal transaction..--
Reset() Tick()
check("hatch: order snapshot > grant > consumed > destroy > save > begin", Seq() == "snapshot,grant,consumed,destroy:Egg01,save,begin", Seq())
local g = PS.Grants[#PS.Grants]
check("hatch: EggInfo fields", g and g.EggInfo.EggId == "EGG-1" and g.EggInfo.EggName == "Basic" and g.EggInfo.Kg == 12.5
	and g.EggInfo.Material == "Golden" and g.EggInfo.Mutations == "NEON,SHADOW", g and HttpService:JSONEncode(g.EggInfo))
check("hatch: rolled key is in the Basic pool", g and RealCatalog.PoolOf("Basic")[g.PetKey] ~= nil, g and g.PetKey)
check("hatch: egg Consumed + destroyed", egg1.Attrs.Consumed == true and egg1.Destroyed == true)
local b = LastBegin()
check("begin: to the owner with action Begin", PetHatch.Fired[#PetHatch.Fired].Player == alice and PetHatch.Fired[#PetHatch.Fired].Action == "Begin")
check("begin: token / PetId / Kg / Reserve / Auto", b and type(b.Token) == "string" and #b.Token <= 64 and b.PetId == "PET-1" and b.Kg == 12.5
	and b.Reserve == false and b.AutoEquipAfterCombat == false, b and HttpService:JSONEncode({b.Token, b.PetId, b.Kg, b.Reserve, b.AutoEquipAfterCombat}))
check("begin: existing fields kept", b and b.EggName == "Basic" and b.EggKey == "Basic Egg" and b.EggDisplayName == "Basic Egg (12.5 kg)"
	and b.Scale == 1.4 and b.Material == "Golden" and b.Mutations == "NEON,SHADOW" and b.Pet == g.PetKey
	and b.PetDisplayName == RealCatalog.DisplayNameOf(g.PetKey) and b.Rarity == RealCatalog.RarityOf(g.PetKey)
	and b.Percent == RealCatalog.PercentOf("Basic", g.PetKey) and b.Chance == RealCatalog.ChanceText("Basic", g.PetKey))
check("begin: Stats block", b and type(b.Stats) == "table" and b.Stats.Income == 0.5 and b.Stats.DPS == 1.2 and b.Stats.AbilityChance == 0.01
	and b.Stats.Fighter == false and (b.Stats.Ability ~= "Yield" or b.Stats.AbilityDuration == 90), b and b.Stats and HttpService:JSONEncode(b.Stats))
local timer1 = Delays[#Delays]
check("fallback timer = PetBalance.TIMING.REVEAL_FALLBACK (100)", timer1 and timer1.Seconds == 100, timer1 and timer1.Seconds)
check("one save requested", DS.Saves == 1, DS.Saves)

--.. one hatch at a time: a second ready egg waits while the reveal is on screen
local egg2 = MakeEgg({X = 0})
Reset() Tick()
check("busy: second egg waits for the active reveal", #PS.Grants == 1 and egg2.Attrs.Hatching == nil, Seq())

--..3. tokens..--
Opened(alice, "TOKEN-9999")
check("token: unknown token ignored", #PS.Finish == 0)
Opened(bob, b.Token)
check("token: another player's token ignored", #PS.Finish == 0)
Opened(alice, b.Token .. string.rep("x", 70))
check("token: over-long token ignored", #PS.Finish == 0)
PetHatch.OnServerEvent:Fire(alice, "Opened", 12345)
check("token: non-string token ignored", #PS.Finish == 0)
PetHatch.OnServerEvent:Fire(alice, "Opened")
check("token: legacy no-token Opened ignored", #PS.Finish == 0)
Opened(alice, b.Token)
local f1 = PS.Finish[1]
check("token: right token finishes once", #PS.Finish == 1 and f1.Player == alice and f1.PetId == "PET-1" and f1.Generation == 7
	and typeof(f1.Spot) == "Vector3" and (f1.Spot - Vector3.new(0, 1.5, 0)).Magnitude < 1e-3, f1 and tostring(f1.Spot))
check("token: fallback timer cancelled", timer1.Cancelled == true)
check("PetsHatched attribute counts the presentation", alice.Attrs.PetsHatched == 1, alice.Attrs.PetsHatched)
Opened(alice, b.Token)
FireDelay(timer1)
check("token: repeated Opened / late timer do nothing", #PS.Finish == 1)

--..4. fallback path (no Opened)..--
Reset() Tick() -- egg2 hatches now
local b2 = LastBegin()
check("second egg hatches after the first presentation ended", egg2.Destroyed == true and b2 and b2.PetId == "PET-2", Seq())
local timer2 = Delays[#Delays]
FireDelay(timer2)
check("fallback: timer finishes the presentation", #PS.Finish == 2 and PS.Finish[2].PetId == "PET-2")
Opened(alice, b2.Token)
check("fallback: Opened after the fallback does nothing", #PS.Finish == 2)

--..5. Duplicate (EggId already some pet's SourceEggId)..--
PS.Mode = "dup"
local savesBefore, firedBefore = DS.Saves, #PetHatch.Fired
local egg3 = MakeEgg({})
Reset() Tick()
check("duplicate: egg consumed, save, no Begin", egg3.Destroyed == true and egg3.Attrs.Consumed == true and DS.Saves == savesBefore + 1
	and #PetHatch.Fired == firedBefore, Seq())
PS.Mode = "ok"
local egg4 = MakeEgg({})
Reset() Tick()
check("duplicate: HatchBusy released (next egg hatches)", egg4.Destroyed == true and #PetHatch.Fired == firedBefore + 1, Seq())
Opened(alice, LastBegin().Token)

--..6. InventoryFull..--
PS.Mode = "full"
local grantsBefore = #PS.Grants
local egg5 = MakeEgg({})
Reset() Tick()
check("full: egg kept, lock + Hatching released", not egg5.Destroyed and egg5.Attrs.Hatching == nil and egg5.Attrs.Consumed == nil and #PS.Grants == grantsBefore + 1, Seq())
Reset() Tick() Tick()
check("full: FullUntil pauses the owner (no retry spam)", #PS.Grants == grantsBefore + 1, #PS.Grants - grantsBefore)
PS.Mode = "ok"
egg5.Parent = nil Tags[egg5] = nil -- retire it (FullUntil lasts 10 real seconds)

--..7. grant throws..--
local fresh = MakePlayer("Cara", 303)
local plot2 = Add(Plots, Fake("Plot2", "Part", {Position = Vector3.new(100, 0, 0), Size = Vector3.new(40, 1, 40), CFrame = CFrame.new(100, 0, 0)}))
local placed2 = Add(plot2, Fake("Placed", "Folder"))
plot2.Attrs.Owner = 303
fresh.Attrs.BaseRestored = true
DS.Loaded[fresh] = true
PS.Ready[fresh] = true
fresh.Character.Children.HumanoidRootPart.Position = Vector3.new(100, 3, 0)
PS.Mode = "throw"
local egg6 = MakeEgg({Owner = 303, X = 100, Parent = placed2})
local warnsBefore = #Warns
Reset() Tick()
check("throw: egg kept + released, warned", not egg6.Destroyed and egg6.Attrs.Hatching == nil and #Warns > warnsBefore, Seq())
PS.Mode = "ok"
Reset() Tick()
check("throw: HatchBusy released (retry succeeds)", egg6.Destroyed == true, Seq())
Opened(fresh, LastBegin().Token)

--..8. snapshot slow / yields / removes the egg..--
--.. slow but synchronous (no frame passes): reported as slow, never as a yield. Runs before the yield case so
--.. the "snapshotyield" WarnOnce key is still unused and the negative check means something
Snapshot.Hook = function() local t0 = os.clock() while os.clock() - t0 < 0.08 do end end
local eggSlow = MakeEgg({Owner = 303, X = 100, Parent = placed2})
warnsBefore = #Warns
Reset() Tick()
local sawSlowYield, sawSlow = false, false
for i = warnsBefore + 1, #Warns do
	if Warns[i]:find("yielded", 1, true) then sawSlowYield = true end
	if Warns[i]:find("took", 1, true) and Warns[i]:find("ms", 1, true) then sawSlow = true end
end
check("slow synchronous snapshot is not called a yield", not sawSlowYield, Warns[#Warns])
check("slow synchronous snapshot is reported as slow (hatch still commits)", sawSlow and eggSlow.Destroyed == true, Seq())
Opened(fresh, LastBegin().Token)
Snapshot.Hook = function() Heartbeat:Fire(0.016) end -- a frame passes inside the invoke = a yield
local egg7 = MakeEgg({Owner = 303, X = 100, Parent = placed2})
warnsBefore = #Warns
Reset() Tick()
local sawYieldWarn = false
for i = warnsBefore + 1, #Warns do if Warns[i]:find("yielded", 1, true) then sawYieldWarn = true end end
check("snapshot yield is warned (hatch still commits)", sawYieldWarn and egg7.Destroyed == true, Seq())
Opened(fresh, LastBegin().Token)
Snapshot.Hook = function() end
local egg8 = MakeEgg({Owner = 303, X = 100, Parent = placed2})
grantsBefore = #PS.Grants
Snapshot.Hook = function() egg8.Parent = nil end -- the egg vanished during the snapshot
Reset() Tick()
check("re-validation: egg gone after the snapshot -> no grant, released", #PS.Grants == grantsBefore and egg8.Attrs.Hatching == nil, Seq())
Snapshot.Hook = nil
egg8.Parent = placed2
Reset() Tick()
check("re-validation: HatchBusy released (egg hatches later)", egg8.Destroyed == true, Seq())
Opened(fresh, LastBegin().Token)

--..9. fault boundaries (Studio hooks)..--
Dev("fail:pre-grant")
check("dev hook resets the attribute to \"\"", Workspace.Attrs.PetHatchDev == "")
local egg9 = MakeEgg({Owner = 303, X = 100, Parent = placed2})
grantsBefore = #PS.Grants
Reset() Tick()
check("fault pre-grant: no grant, egg intact, released", #PS.Grants == grantsBefore and not egg9.Destroyed and egg9.Attrs.Hatching == nil
	and egg9.Attrs.Consumed == nil, Seq())
Reset() Tick()
check("fault pre-grant is one-shot (next tick hatches)", egg9.Destroyed == true and #PS.Grants == grantsBefore + 1, Seq())
Opened(fresh, LastBegin().Token)

Dev("fail:post-grant")
local egg10 = MakeEgg({Owner = 303, X = 100, Parent = placed2})
savesBefore, firedBefore = DS.Saves, #PetHatch.Fired
Reset() Tick()
check("fault post-grant: granted, egg left Hatching, no consume/save/begin", Seq() == "snapshot,grant" and not egg10.Destroyed
	and egg10.Attrs.Hatching == true and egg10.Attrs.Consumed == nil and DS.Saves == savesBefore and #PetHatch.Fired == firedBefore, Seq())
local egg11 = MakeEgg({Owner = 303, X = 100, Parent = placed2})
Reset() Tick()
check("fault post-grant: HatchBusy + lock released (another egg hatches)", egg11.Destroyed == true and #PetHatch.Fired == firedBefore + 1, Seq())
Reset() Tick()
check("fault post-grant: the Hatching egg is never re-triggered", not egg10.Destroyed and #PS.Grants == grantsBefore + 3, Seq())
Opened(fresh, LastBegin().Token)

Dev("fail:post-destroy")
local egg12 = MakeEgg({Owner = 303, X = 100, Parent = placed2})
savesBefore, firedBefore = DS.Saves, #PetHatch.Fired
Reset() Tick()
check("fault post-destroy: consumed + destroyed, no save/begin", Seq() == "snapshot,grant,consumed,destroy:" .. egg12.Name
	and DS.Saves == savesBefore and #PetHatch.Fired == firedBefore, Seq())
local egg13 = MakeEgg({Owner = 303, X = 100, Parent = placed2})
Reset() Tick()
check("fault post-destroy: HatchBusy released", egg13.Destroyed == true, Seq())
Opened(fresh, LastBegin().Token)

--..10. PlayerRemoving mid-reveal..--
local egg14 = MakeEgg({Owner = 303, X = 100, Parent = placed2})
Reset() Tick()
local b14 = LastBegin()
local timer14 = Delays[#Delays]
local finishBefore = #PS.Finish
Players.PlayerRemoving:Fire(fresh)
FireDelay(timer14)
Opened(fresh, b14.Token)
check("leave mid-reveal: presentation dropped (no finish), timer cancelled", #PS.Finish == finishBefore and timer14.Cancelled == true)

--..11. dev grants..--
local grants0, finish0, fired0, saves0 = #PS.Grants, #PS.Finish, #PetHatch.Fired, DS.Saves
Dev("hatch:Basic:Cat")
local dg = PS.Grants[#PS.Grants]
check("dev hatch: saved grant with EggId nil", #PS.Grants == grants0 + 1 and dg.Player == alice and dg.EggInfo.EggId == nil
	and dg.EggInfo.EggName == "Basic" and dg.PetKey == "Cat" and DS.Saves == saves0 + 1)
check("dev hatch: reveal begun with a token", #PetHatch.Fired == fired0 + 1 and LastBegin().Pet == "Cat" and type(LastBegin().Token) == "string")
Dev("spawn:Dog")
check("dev hatch: refused while a reveal runs", #PS.Grants == grants0 + 1)
Opened(alice, LastBegin().Token)
Dev("spawn:Dog")
dg = PS.Grants[#PS.Grants]
check("dev spawn: grant (EggName Basic) + immediate finish, no Begin", dg.PetKey == "Dog" and dg.EggInfo.EggName == "Basic" and dg.EggInfo.EggId == nil
	and #PS.Finish == finish0 + 2 and PS.Finish[#PS.Finish].PetId == "PET-" .. PS.N and #PetHatch.Fired == fired0 + 1)
Dev("spawn:NotAPet")
check("dev spawn: unknown pet refused", #PS.Grants == grants0 + 2)
Dev("hatch:Basic:NotInPool")
dg = PS.Grants[#PS.Grants]
check("dev hatch: a forced pet outside the pool is rerolled", #PS.Grants == grants0 + 3 and RealCatalog.PoolOf("Basic")[dg.PetKey] ~= nil, dg.PetKey)
Opened(alice, LastBegin().Token)
Dev("clear")
check("dev clear: DetachPlot(\"Reload\") for every player", #PS.Detach == #Players.List and PS.Detach[1].Reason == "Reload")
Dev("ready")
local allReady = true
for _, e in ipairs(CollectionService:GetTagged("PlacedEgg")) do if e.Attrs.HatchAt ~= Now then allReady = false end end
check("dev ready: HatchAt = now on every placed egg", allReady)

--..12. reserve flag reaches the payload..--
PS.Reserve = true
local egg15 = MakeEgg({Owner = 303, X = 100, Parent = placed2}) -- Alice is still inside her 10 s FullUntil pause
Reset() Tick()
check("reserve: Begin.Reserve = true", egg15.Destroyed == true and LastBegin().Reserve == true, Seq())
PS.Reserve = false
check("no Instance.new during the run", InstanceNewCalls == 0)

return ("WP-HATCH server_transaction: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
