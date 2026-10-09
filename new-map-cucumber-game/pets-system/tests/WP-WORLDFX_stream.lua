-- WP-WORLDFX stream tests (2026-09-22, world fix round, review defect 6 client side): runs the WHOLE
-- PetRoamClient (patched, loopback :8794) against plain-table fakes of CollectionService, RunService,
-- task and a 3-part pet model, and checks the re-attach after every way an ATOMIC pet model
-- (PetService.DefaultSpawn sets ModelStreamingMode Atomic since S4) can stream out and back in:
--   B  the model leaves the DataModel (tag removed first) and the SAME instance comes back
--   C  the model leaves, the Heartbeat sees it before the tag-removed signal, a NEW instance comes back
--   D  the model instance stays tagged while all its parts go, fresh parts come back together
--   E  D inside one frame (the parts are replaced before the Heartbeat notices)
--   F  the model streams out while Attach is still waiting for PartCount parts (reservation token)
-- After each: the pet renders at PetMotion.Sample (XZ exact, Y = ground + RootToBottom when idle),
-- every part keeps its server offset from the Root (no tearing) and the removed copy is never moved.
-- Plain tables only: no instances are created, nothing is written.
local H = game:GetService("HttpService")
local SRC, PATCHED = "http://127.0.0.1:8793/", "http://127.0.0.1:8794/"

local function Fetch(base, file)
	return (H:GetAsync(base .. file):gsub("\r\n", "\n"))
end

--.. load a module whose only require is ReplicatedStorage.Modules.<name> (answered from `modules`)
local function FakeFolder(name)
	local inst = {Name = name}
	function inst:WaitForChild(child) return FakeFolder(child) end
	function inst:FindFirstChild(child) return FakeFolder(child) end
	return inst
end
local function LoadWith(src, modules, extra)
	local fn = assert(loadstring(src))
	local fakeGame = {}
	function fakeGame:GetService(service)
		if extra and extra[service] then return extra[service] end
		if service == "ReplicatedStorage" then return FakeFolder("ReplicatedStorage") end
		return game:GetService(service)
	end
	local env = {
		game = fakeGame,
		require = function(target)
			local found = type(target) == "table" and modules[target.Name]
			if not found then error("unexpected require " .. tostring(type(target) == "table" and target.Name or target)) end
			return found
		end,
	}
	if extra then for k, v in pairs(extra.Globals or {}) do env[k] = v end end
	setfenv(fn, setmetatable(env, {__index = getfenv(0)}))
	return fn
end

local PetBalance = assert(loadstring(Fetch(SRC, "ReplicatedStorage.Modules.PetBalance.lua")))()
local PetMotion = LoadWith(Fetch(SRC, "ReplicatedStorage.Modules.PetMotion.lua"), {PetBalance = PetBalance})()

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then pass += 1 else
		fail += 1
		if #failures < 10 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

--..fakes..--
local function Signal()
	local s = {Handlers = {}}
	function s:Connect(fn)
		local conn = {Connected = true}
		s.Handlers[conn] = fn
		function conn:Disconnect()
			conn.Connected = false
			s.Handlers[conn] = nil
		end
		return conn
	end
	function s:Fire(...)
		local list = {}
		for conn, fn in pairs(s.Handlers) do list[#list + 1] = {conn, fn} end
		for _, pair in ipairs(list) do
			if pair[1].Connected then pair[2](...) end
		end
	end
	function s:Count()
		local n = 0
		for _ in pairs(s.Handlers) do n += 1 end
		return n
	end
	return s
end

local PartMT = {}
PartMT.__index = function(self, key)
	if key == "Position" then return rawget(self, "CFrame").Position end
	return PartMT[key]
end
function PartMT.IsA(_, class) return class == "BasePart" or class == "Part" end
local function Part(name, cf, size)
	return setmetatable({Name = name, CFrame = cf, Size = size, Transparency = 0, CanCollide = true, CanTouch = true, CanQuery = true}, PartMT)
end

local ModelMT = {}
ModelMT.__index = ModelMT
function ModelMT:IsA(class) return class == "Model" end
function ModelMT:GetAttribute(name) return self.Attrs[name] end
function ModelMT:GetDescendants() return table.clone(self.Children) end
function ModelMT:FindFirstChild(name)
	for _, p in ipairs(self.Children) do if p.Name == name then return p end end
	return nil
end
function ModelMT:WaitForChild(name) return self:FindFirstChild(name) end
function ModelMT:GetPivot() return self.PrimaryPart.CFrame end -- PivotOffset = identity
function ModelMT:PivotTo(cf)
	local delta = cf * self:GetPivot():Inverse()
	for _, p in ipairs(self.Children) do p.CFrame = delta * p.CFrame end
	self.Pivots += 1
end
function ModelMT:AddPart(p) -- a part streaming in: parented, then DescendantAdded
	p.Parent = self
	table.insert(self.Children, p)
	self.DescendantAdded:Fire(p)
end
function ModelMT:RemoveAllParts() -- every part streams out together (the engine clears PrimaryPart)
	for _, p in ipairs(self.Children) do p.Parent = nil end
	table.clear(self.Children)
	self.PrimaryPart = nil
end

--.. the pet: Root 2x2x2, Body 3x2x4 half a stud lower (the lowest part: RootToBottom 1.5), Head turned
local ROOT_TO_BOTTOM = 1.5
local GROUND = 5
local SERVER_PIVOT = CFrame.new(100, GROUND + ROOT_TO_BOTTOM, 50) * CFrame.Angles(0, 0.3, 0) -- DefaultSpawn pose
local OFFSETS = {
	{"Root", CFrame.new(), Vector3.new(2, 2, 2)},
	{"Body", CFrame.new(0, -0.5, 1), Vector3.new(3, 2, 4)},
	{"Head", CFrame.new(0, 1.2, -1.8) * CFrame.Angles(0, 0.4, 0), Vector3.new(1.5, 1.5, 1.5)},
}
local ATTRS = {
	PartCount = #OFFSETS, RoamPhase = 0, RoamRadius = 2,
	RoamFrom = Vector3.new(90, GROUND, 50), RoamTo = Vector3.new(110, GROUND, 50),
	RoamStart = 1000, RoamEnd = 1010, RoamGroundY = GROUND, RoamSeq = 7,
}
local folder = {Name = "Pets"}
local function ServerParts(which)
	local parts = {}
	for _, o in ipairs(OFFSETS) do
		if not which or which[o[1]] then parts[#parts + 1] = Part(o[1], SERVER_PIVOT * o[2], o[3]) end
	end
	return parts
end
local function NewModel(name, which)
	local m = setmetatable({Name = name, Attrs = table.clone(ATTRS), Children = {}, Pivots = 0, DescendantAdded = Signal()}, ModelMT)
	for _, p in ipairs(ServerParts(which)) do
		p.Parent = m
		table.insert(m.Children, p)
	end
	m.PrimaryPart = m:FindFirstChild("Root")
	m.Parent = folder
	return m
end

--.. CollectionService / RunService / workspace / task
local tagged = {}
local addedSignal, removedSignal = Signal(), Signal()
local CS = {}
function CS:GetTagged() local out = {} for m in pairs(tagged) do out[#out + 1] = m end return out end
function CS:GetInstanceAddedSignal() return addedSignal end
function CS:GetInstanceRemovedSignal() return removedSignal end
function CS:HasTag(model) return type(model) == "table" and model.Tag == true end -- tags stay on the instance
local heartbeat = Signal()
local RS = {Heartbeat = heartbeat}
local clock = 1000
local fakeWorkspace = {}
function fakeWorkspace:GetServerTimeNow() return clock end
local deferred, suspended, waits = {}, {}, 0
local osClock = 0 -- the script's os.clock (Attach's PART_WAIT deadline): advanced by every task.wait
local fakeOs = setmetatable({clock = function() return osClock end}, {__index = os})
local fakeTask = {}
function fakeTask.spawn(fn, ...)
	local co = coroutine.create(fn)
	local ok, err = coroutine.resume(co, ...)
	if not ok then error(err) end
	if coroutine.status(co) == "suspended" then table.insert(suspended, co) end
end
function fakeTask.defer(fn, ...) table.insert(deferred, table.pack(fn, ...)) end
function fakeTask.wait(seconds)
	waits += 1
	osClock += tonumber(seconds) or 0.03
	return coroutine.yield()
end
local function Flush() -- the deferred-signal invocation point
	while #deferred > 0 do
		local batch = deferred
		deferred = {}
		for _, d in ipairs(batch) do d[1](table.unpack(d, 2, d.n)) end
	end
end
local function Resume() -- task.wait resumes (one step per call)
	local list = suspended
	suspended = {}
	for _, co in ipairs(list) do
		local ok, err = coroutine.resume(co)
		if not ok then error(err) end
		if coroutine.status(co) == "suspended" then table.insert(suspended, co) end
	end
end
local function Beat(t) -- one frame: deferred + waits, Heartbeat at server time t, deferred
	clock = t
	Flush()
	Resume()
	heartbeat:Fire(1 / 60)
	Flush()
end
local function StreamIn(model) -- the model (all its parts) enters the DataModel with its tag
	model.Tag = true
	model.Parent = folder
	tagged[model] = true
	addedSignal:Fire(model)
end
local function StreamOut(model, heartbeatFirst, t) -- the model leaves; optionally a Heartbeat runs before the tag signal
	model.Parent = nil
	tagged[model] = nil
	if heartbeatFirst then Beat(t) end
	removedSignal:Fire(model)
end

--..checks..--
local function MaxTear(model) -- largest distance of any part from where its server offset puts it (studs)
	local root = model.PrimaryPart
	if not root then return math.huge end
	local worst = 0
	for _, o in ipairs(OFFSETS) do
		local p = model:FindFirstChild(o[1])
		if not p then return math.huge end
		worst = math.max(worst, (p.Position - (root.CFrame * o[2]).Position).Magnitude)
	end
	return worst
end
local function PlacedAt(model, t, idle) -- XZ = the sample; Y = ground + RootToBottom when idle
	local pos = PetMotion.Sample(PetMotion.ReadSegment(model), t)
	local pivot = model:GetPivot().Position
	local xz = Vector3.new(pivot.X - pos.X, 0, pivot.Z - pos.Z).Magnitude
	local y = pivot.Y - (pos.Y + ROOT_TO_BOTTOM)
	return xz <= 1e-4 and (not idle or math.abs(y) <= 1e-4) and (idle or (y >= -1e-4 and y <= 0.7 + 1e-4)), ("xz %.5f y %.5f"):format(xz, y)
end

--.. the metric itself: a coherent pet reads 0, a pet with one part 5 studs off reads 5
do
	local m = NewModel("Probe")
	Check("tear metric: coherent = 0", MaxTear(m) <= 1e-6, MaxTear(m))
	local head = m:FindFirstChild("Head")
	head.CFrame = head.CFrame + Vector3.new(5, 0, 0)
	Check("tear metric: 5 studs off = 5", math.abs(MaxTear(m) - 5) <= 1e-6, MaxTear(m))
end

--.. A: start-up (GetTagged) attach, then render
local A = NewModel("Cat")
A.Tag = true
tagged[A] = true
local roamSrc = Fetch(PATCHED, "StarterPlayer.StarterPlayerScripts.PetRoamClient.client.lua")
local run = LoadWith(roamSrc, {PetMotion = PetMotion}, {
	CollectionService = CS, RunService = RS,
	Globals = {workspace = fakeWorkspace, task = fakeTask, os = fakeOs},
})
local okRun, runErr = pcall(run)
Check("PetRoamClient runs on the fakes", okRun, runErr)
Check("one Heartbeat connection", heartbeat:Count() == 1, heartbeat:Count())
Beat(1005)
local okA, dA = PlacedAt(A, 1005, false)
Check("A walking at the sample", okA, dA)
Check("A coherent", MaxTear(A) <= 1e-4, MaxTear(A))
Check("A collision stripped", A.PrimaryPart.CanCollide == false and A:FindFirstChild("Body").CanQuery == false)
Beat(1012)
okA, dA = PlacedAt(A, 1012, true)
Check("A idle at To", okA, dA)

--.. B: the model streams out (tag signal first), the SAME instance streams back in at the server pose
StreamOut(A, false)
local pivotsOut = A.Pivots
Beat(1013)
Check("B not moved while out", A.Pivots == pivotsOut, A.Pivots - pivotsOut)
for _, o in ipairs(OFFSETS) do A:FindFirstChild(o[1]).CFrame = SERVER_PIVOT * o[2] end -- the engine re-sends the server pose
A.Attrs.RoamFrom, A.Attrs.RoamTo, A.Attrs.RoamStart, A.Attrs.RoamEnd, A.Attrs.RoamSeq =
	Vector3.new(110, GROUND, 50), Vector3.new(110, GROUND, 70), 1014, 1024, 8 -- a new leg was planned meanwhile
StreamIn(A)
Beat(1016)
local okB, dB = PlacedAt(A, 1016, false)
Check("B re-attached at the new leg's sample", okB, dB)
Check("B coherent", MaxTear(A) <= 1e-4, MaxTear(A))
Beat(1030)
okB, dB = PlacedAt(A, 1030, true)
Check("B idle at the new To", okB, dB)

--.. C: out with a Heartbeat before the tag signal, then a NEW instance streams in
StreamOut(A, true, 1031)
pivotsOut = A.Pivots
local C = NewModel("Cat")
C.Attrs = table.clone(A.Attrs)
StreamIn(C)
Beat(1032)
Beat(1033)
local okC, dC = PlacedAt(C, 1033, true)
Check("C new instance attached", okC, dC)
Check("C coherent", MaxTear(C) <= 1e-4, MaxTear(C))
Check("C old instance never moved again", A.Pivots == pivotsOut, A.Pivots - pivotsOut)
Check("C old instance's watcher gone", A.DescendantAdded:Count() == 0, A.DescendantAdded:Count())

--.. D: the model instance stays tagged; all its parts stream out, fresh parts come back together
C:RemoveAllParts()
Beat(1034) -- the Heartbeat sees the Root gone: detach + watch
Check("D watching while the parts are out", C.DescendantAdded:Count() == 1, C.DescendantAdded:Count())
pivotsOut = C.Pivots
Beat(1035)
Check("D not moved while out", C.Pivots == pivotsOut)
C.Attrs.RoamFrom, C.Attrs.RoamTo, C.Attrs.RoamStart, C.Attrs.RoamEnd, C.Attrs.RoamSeq =
	Vector3.new(110, GROUND, 70), Vector3.new(95, GROUND, 60), 1036, 1046, 9
for _, p in ipairs(ServerParts()) do C:AddPart(p) end -- one packet: every part, at the server pose
C.PrimaryPart = C:FindFirstChild("Root") -- the reference resolves after the parts arrive
Beat(1040) -- deferred Reattach -> Attach, then the Heartbeat renders it
Beat(1041)
local okD, dD = PlacedAt(C, 1041, false)
Check("D re-attached at the sample", okD, dD)
Check("D coherent", MaxTear(C) <= 1e-4, MaxTear(C))
Check("D watcher dropped after the re-attach", C.DescendantAdded:Count() == 0, C.DescendantAdded:Count())
Beat(1050)
okD, dD = PlacedAt(C, 1050, true)
Check("D ground height kept (RootToBottom re-measured)", okD, dD)

--.. E: the parts are replaced inside one frame (the Heartbeat only sees a stale Root)
C:RemoveAllParts()
for _, p in ipairs(ServerParts()) do C:AddPart(p) end -- nobody is watching yet: these signals go nowhere
C.PrimaryPart = C:FindFirstChild("Root")
Beat(1051) -- stale Root -> detach + watch (+ one deferred check that finds the new Root)
Beat(1052)
Beat(1053)
local okE, dE = PlacedAt(C, 1053, true)
Check("E re-attached", okE, dE)
Check("E coherent", MaxTear(C) <= 1e-4, MaxTear(C))
Check("E no watcher left", C.DescendantAdded:Count() == 0, C.DescendantAdded:Count())

--.. F: a pet streams out while Attach still waits for its parts (only the Root arrived so far)
local F = NewModel("Wolf", {Root = true})
StreamIn(F) -- Attach reserves it and waits for PartCount 3
Check("F waiting for parts", waits >= 1, waits)
StreamOut(F, false) -- tag removed: the reservation is dropped
Beat(1054) -- the waiting Attach resumes, sees its token is gone and stops
Check("F not attached after it left", F.Pivots == 0, F.Pivots)
local F2 = NewModel("Wolf") -- the whole model streams back in (a new instance)
StreamIn(F2)
Beat(1055)
Beat(1056)
local okF, dF = PlacedAt(F2, 1056, true)
Check("F2 attached", okF, dF)
Check("F2 coherent", MaxTear(F2) <= 1e-4, MaxTear(F2))
--.. the abandoned Attach polls until its PART_WAIT deadline (5 s of task.wait(0.1)), then returns on the token
for i = 1, 80 do
	if #suspended == 0 then break end
	Beat(1056 + i * 0.1)
end
Check("F abandoned Attach ended at PART_WAIT", #suspended == 0, #suspended)
Check("F old copy never attached", F.Pivots == 0, F.Pivots)
okF, dF = PlacedAt(F2, clock, true)
Check("F2 still rendered", okF and MaxTear(F2) <= 1e-4, dF)

return ("WP-WORLDFX stream: PASS %d / FAIL %d: %s"):format(pass, fail, table.concat(failures, "; "))
