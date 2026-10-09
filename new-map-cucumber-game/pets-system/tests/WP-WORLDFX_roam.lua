-- WP-WORLDFX roam tests (2026-09-22): PetRoamClient's pure helpers -- the segment cache's RoamSeq
-- gating through the REAL PetMotion.ReadSegment / Sample (loaded from src with PetBalance injected),
-- the shot squash, aim yaw and angle wrap. Plain-table fake models; no instances, nothing written.
local H = game:GetService("HttpService")
local SRC, PATCHED = "http://127.0.0.1:8793/", "http://127.0.0.1:8794/"

local function Fetch(base, file)
	return (H:GetAsync(base .. file):gsub("\r\n", "\n"))
end

--.. load a module whose only require is ReplicatedStorage.Modules.<name> (answered from `modules`)
local function LoadWith(src, modules)
	local fn = assert(loadstring(src))
	local function Fake(name)
		local inst = {Name = name}
		function inst:WaitForChild(child) return Fake(child) end
		function inst:FindFirstChild(child) return Fake(child) end
		return inst
	end
	local fakeGame = {}
	function fakeGame:GetService(service)
		if service == "ReplicatedStorage" then return Fake("ReplicatedStorage") end
		return game:GetService(service)
	end
	local env = setmetatable({
		game = fakeGame,
		require = function(target)
			local found = type(target) == "table" and modules[target.Name]
			if not found then error("unexpected require " .. tostring(type(target) == "table" and target.Name or target)) end
			return found
		end,
	}, {__index = getfenv(0)})
	setfenv(fn, env)
	return fn()
end

local PetBalance = assert(loadstring(Fetch(SRC, "ReplicatedStorage.Modules.PetBalance.lua")))()
local PetMotion = LoadWith(Fetch(SRC, "ReplicatedStorage.Modules.PetMotion.lua"), {PetBalance = PetBalance})
local Core = assert(loadstring(Fetch(PATCHED, "StarterPlayer.StarterPlayerScripts.PetRoamClient.client.lua")))("__core")

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then pass += 1 else
		fail += 1
		if #failures < 8 then table.insert(failures, name .. (detail and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function Near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function NearV(a, b) return typeof(a) == "Vector3" and (a - b).Magnitude <= 1e-6 end

--.. a fake pet model: attributes in a table, reads counted
local function FakeModel(attrs)
	local m = {Attrs = attrs, Reads = 0}
	function m:GetAttribute(name) self.Reads += 1 return self.Attrs[name] end
	return m
end
local reads = 0
local function CountingRead(model)
	reads += 1
	return PetMotion.ReadSegment(model)
end

local A, B, C = Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(0, 0, 20)
local model = FakeModel({RoamFrom = A, RoamTo = B, RoamStart = 100, RoamEnd = 110, RoamGroundY = 5, RoamSeq = 1})
local state = {}

-- 1. first complete segment is taken
Check("first read accepted", Core.RefreshSegment(state, model.Attrs.RoamSeq, CountingRead, model) == true)
Check("first read seq", state.Seq == 1)
Check("first read To", state.Segment and NearV(state.Segment.To, B))

-- 2. same RoamSeq -> no re-read at all (cached)
reads = 0
Check("same seq no change", Core.RefreshSegment(state, 1, CountingRead, model) == false)
Check("same seq no read", reads == 0, reads)

-- 3. a partial update (RoamTo / times rewritten, RoamSeq not yet) keeps the old segment
model.Attrs.RoamFrom, model.Attrs.RoamTo, model.Attrs.RoamStart, model.Attrs.RoamEnd = B, C, 111, 120
Check("partial update ignored", Core.RefreshSegment(state, model.Attrs.RoamSeq, CountingRead, model) == false)
Check("partial update keeps To", NearV(state.Segment.To, B))
local pos = PetMotion.Sample(state.Segment, 105)
Check("partial update samples old leg", NearV(pos, Vector3.new(5, 5, 0)), pos)

-- 4. RoamSeq bumped but the segment is broken (RoamTo missing) -> keep the last complete one, retry
model.Attrs.RoamSeq = 2
model.Attrs.RoamTo = nil
reads = 0
Check("broken seg rejected", Core.RefreshSegment(state, 2, CountingRead, model) == false)
Check("broken seg keeps old", NearV(state.Segment.To, B) and state.Seq == 1)
Core.RefreshSegment(state, 2, CountingRead, model)
Check("broken seg retried each frame", reads == 2, reads)

-- 5. the segment completes -> taken
model.Attrs.RoamTo = C
Check("complete seg accepted", Core.RefreshSegment(state, 2, CountingRead, model) == true)
Check("complete seg seq", state.Seq == 2)
Check("complete seg To", NearV(state.Segment.To, C))
local p0, w0 = PetMotion.Sample(state.Segment, 111)
local pm, wm, hm = PetMotion.Sample(state.Segment, 115.5)
local p1, w1 = PetMotion.Sample(state.Segment, 125)
Check("sample at start = From", NearV(p0, Vector3.new(10, 5, 0)) and w0 == false, p0)
Check("sample mid walking", NearV(pm, Vector3.new(5, 5, 10)) and wm == true, pm)
Check("sample heading unit", hm and Near(hm.Magnitude, 1), hm)
Check("sample after end = To", NearV(p1, Vector3.new(0, 5, 20)) and w1 == false, p1)

-- 6. a pet with no RoamSeq (older server) is re-read every call
local legacy = FakeModel({RoamTo = B, RoamGroundY = 1})
local ls = {}
reads = 0
Core.RefreshSegment(ls, nil, CountingRead, legacy)
Core.RefreshSegment(ls, nil, CountingRead, legacy)
Check("no RoamSeq re-reads", reads == 2 and ls.Segment ~= nil, reads)
local lp, lw = PetMotion.Sample(ls.Segment, 0)
Check("legacy idle at To", NearV(lp, Vector3.new(10, 1, 0)) and lw == false, lp)

-- 7. nothing complete yet -> Sample(nil) gives no position (the pet stays put)
local empty = {}
Check("no segment no refresh", Core.RefreshSegment(empty, 1, CountingRead, FakeModel({RoamSeq = 1})) == false)
Check("no segment no pos", PetMotion.Sample(empty.Segment, 0) == nil)

-- 8. shot squash: 0.15 s, 0.85 -> 1 height as a dip, a recoil lean fading out
local d0, l0 = Core.ShotPose(10, 10, 2)
Check("squash start dip", Near(d0, -0.3), d0)
Check("squash start lean", Near(l0, math.rad(8)), l0)
local dh, lh = Core.ShotPose(10.075, 10, 2)
Check("squash half", Near(dh, -0.15) and Near(lh, math.rad(4)), dh)
local de, le = Core.ShotPose(10.15, 10, 2)
Check("squash over", de == 0 and le == 0)
local db = Core.ShotPose(9.9, 10, 2)
Check("squash not before shot", db == 0)
Check("squash NaN shot", (Core.ShotPose(10, 0 / 0, 2)) == 0)
Check("squash nil shot", (Core.ShotPose(10, nil, 2)) == 0)
Check("squash NaN height", (Core.ShotPose(10, 10, 0 / 0)) == 0)

-- 9. aim yaw (PetRoamClient's -Z forward convention) + angle wrap
Check("aim -Z = 0", Near(Core.YawTowards(Vector3.new(0, 0, 0), Vector3.new(0, 3, -5)), 0))
Check("aim +X = -pi/2", Near(Core.YawTowards(Vector3.new(0, 0, 0), Vector3.new(5, 0, 0)), -math.pi / 2))
Check("aim too close = nil", Core.YawTowards(Vector3.new(0, 0, 0), Vector3.new(0.1, 9, 0.1)) == nil)
Check("wrap 3pi/2", Near(Core.ShortestAngle(3 * math.pi / 2), -math.pi / 2))
Check("wrap -3pi/2", Near(Core.ShortestAngle(-3 * math.pi / 2), math.pi / 2))
Check("finite", Core.Finite(1) and not Core.Finite(0 / 0) and not Core.Finite(math.huge) and not Core.Finite("1"))

return ("WP-WORLDFX roam: PASS %d / FAIL %d: %s"):format(pass, fail, table.concat(failures, "; "))
