-- WP-STATS motion: PetMotion.Sample / ReadSegment / ToAttributes (segment edge cases, stale-seq gating).
-- Read-only: loads PetBalance + PetMotion from the loopback src server (:8793); fake models are plain
-- tables with a GetAttribute method (no instances).
local HttpService = game:GetService("HttpService")

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 12 then failures[#failures + 1] = name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "") end
	end
end
local function VNear(v, x, y, z)
	return typeof(v) == "Vector3" and math.abs(v.X - x) < 1e-6 and math.abs(v.Y - y) < 1e-6 and math.abs(v.Z - z) < 1e-6
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

local B = Load("ReplicatedStorage.Modules.PetBalance.lua", {})
local M = Load("ReplicatedStorage.Modules.PetMotion.lua", {PetBalance = B})

Check("MUZZLE_HEIGHT re-export", M.MUZZLE_HEIGHT == B.FX.MUZZLE_HEIGHT and M.MUZZLE_HEIGHT == 1.5)

local from, to = Vector3.new(0, 50, 0), Vector3.new(10, 70, 0)
local seg = {From = from, To = to, Start = 100, End = 110, GroundY = 5, Seq = 3}

local pos, walking, heading = M.Sample(seg, 90)
Check("before start = From, idle", VNear(pos, 0, 5, 0) and walking == false, pos)
Check("heading unit +X", VNear(heading, 1, 0, 0), heading)
pos, walking = M.Sample(seg, 100)
Check("at start = From", VNear(pos, 0, 5, 0) and walking == false)
pos, walking, heading = M.Sample(seg, 105)
Check("midpoint lerp walking", VNear(pos, 5, 5, 0) and walking == true and VNear(heading, 1, 0, 0), pos)
pos, walking = M.Sample(seg, 102.5)
Check("quarter lerp", VNear(pos, 2.5, 5, 0) and walking == true, pos)
pos, walking = M.Sample(seg, 110)
Check("at end = To", VNear(pos, 10, 5, 0) and walking == false)
pos, walking = M.Sample(seg, 1e9)
Check("after end = To, idle", VNear(pos, 10, 5, 0) and walking == false)

pos, walking = M.Sample({From = from, To = to, Start = 100, End = 100, GroundY = 5}, 100)
Check("zero duration -> To idle", VNear(pos, 10, 5, 0) and walking == false)
pos, walking = M.Sample({From = from, To = to, Start = 100, End = 90, GroundY = 5}, 95)
Check("End < Start -> To idle", VNear(pos, 10, 5, 0) and walking == false)
pos, walking, heading = M.Sample({To = to, Start = 100, End = 110, GroundY = 5}, 105)
Check("missing From -> To, no heading", VNear(pos, 10, 5, 0) and walking == false and heading == nil)
pos = M.Sample({From = "junk", To = to, Start = 100, End = 110, GroundY = 5}, 105)
Check("junk From -> To", VNear(pos, 10, 5, 0))
local nan = 0 / 0
pos, walking = M.Sample({From = from, To = to, Start = nan, End = 110, GroundY = 5}, 105)
Check("NaN Start -> To idle", VNear(pos, 10, 5, 0) and walking == false)
pos, walking = M.Sample({From = from, To = to, Start = 100, End = math.huge, GroundY = 5}, 105)
Check("inf End -> To idle", VNear(pos, 10, 5, 0) and walking == false)
pos, walking = M.Sample(seg, nan)
Check("NaN now -> To idle", VNear(pos, 10, 5, 0) and walking == false)
pos, walking = M.Sample({From = from, To = to, GroundY = 5}, 105)
Check("missing times -> To", VNear(pos, 10, 5, 0) and walking == false)

local p, w, h = M.Sample(nil, 5)
Check("nil segment", p == nil and w == false and h == nil)
p, w, h = M.Sample({From = from, Start = 1, End = 2, GroundY = 5}, 1.5)
Check("missing To", p == nil and w == false and h == nil)
p = M.Sample({From = from, To = to, Start = 1, End = 2}, 1.5)
Check("missing GroundY", p == nil)
p = M.Sample({From = from, To = to, Start = 1, End = 2, GroundY = nan}, 1.5)
Check("NaN GroundY", p == nil)
p = M.Sample({From = from, To = Vector3.new(nan, 0, 0), Start = 1, End = 2, GroundY = 5}, 1.5)
Check("NaN To", p == nil)
p = M.Sample("junk", 1)
Check("non-table segment", p == nil)

local _, shortWalking, shortHeading = M.Sample({From = Vector3.new(0, 0, 0), To = Vector3.new(0.1, 0, 0.1), Start = 1, End = 2, GroundY = 0}, 1.5)
Check("tiny XZ move -> walking, no heading", shortHeading == nil and shortWalking == true)
local here = Vector3.new(4, 9, 4)
pos, walking, heading = M.Sample({From = here, To = here, Start = 1, End = 5, GroundY = 2}, 3)
Check("timed idle (From == To) -> not walking", VNear(pos, 4, 2, 4) and walking == false and heading == nil)
local _, _, vertHeading = M.Sample({From = Vector3.new(0, 0, 0), To = Vector3.new(0, 40, 0), Start = 1, End = 2, GroundY = 0}, 1.5)
Check("vertical-only move -> no heading", vertHeading == nil)
local _, _, diag = M.Sample({From = Vector3.new(0, 0, 0), To = Vector3.new(3, 0, -4), Start = 1, End = 2, GroundY = 0}, 1.5)
Check("diagonal heading unit", VNear(diag, 0.6, 0, -0.8), diag)

--.. ReadSegment on fake models
local function FakeModel(attrs)
	return {GetAttribute = function(_, name) return attrs[name] end, Attrs = attrs}
end
local read = M.ReadSegment(FakeModel({RoamFrom = from, RoamTo = to, RoamStart = 100, RoamEnd = 110, RoamGroundY = 5, RoamSeq = 7}))
Check("ReadSegment full", read and read.From == from and read.To == to and read.Start == 100 and read.End == 110 and read.GroundY == 5 and read.Seq == 7)
Check("ReadSegment -> Sample", read and VNear((M.Sample(read, 105)), 5, 5, 0))
Check("ReadSegment no RoamTo", M.ReadSegment(FakeModel({RoamFrom = from, RoamGroundY = 5, RoamSeq = 1})) == nil)
Check("ReadSegment no GroundY", M.ReadSegment(FakeModel({RoamTo = to, RoamSeq = 1})) == nil)
local partial = M.ReadSegment(FakeModel({RoamTo = to, RoamGroundY = 5, RoamStart = nan, RoamSeq = "x"}))
Check("ReadSegment partial", partial and partial.From == nil and partial.Start == nil and partial.Seq == nil)
Check("ReadSegment junk", M.ReadSegment(nil) == nil and M.ReadSegment(5) == nil and M.ReadSegment({}) == nil)
Check("ReadSegment erroring model", M.ReadSegment({GetAttribute = function() error("boom") end}) == nil)

--.. ToAttributes order (RoamSeq last) + round trip through a fake model
local list = M.ToAttributes(seg)
local names = {}
for i, pair in ipairs(list) do names[i] = pair[1] end
Check("ToAttributes order", table.concat(names, ",") == "RoamFrom,RoamTo,RoamStart,RoamEnd,RoamGroundY,RoamSeq", table.concat(names, ","))
Check("ToAttributes ends with RoamSeq", list[#list][1] == "RoamSeq" and list[#list][2] == 3)
local idle = M.ToAttributes({To = to, Start = 5, End = 5, GroundY = 5, Seq = 9})
Check("ToAttributes missing From -> To", idle[1][2] == to)
local attrs = {}
for _, pair in ipairs(list) do attrs[pair[1]] = pair[2] end
local back = M.ReadSegment(FakeModel(attrs))
Check("round trip", back and back.From == from and back.To == to and back.Start == 100 and back.End == 110 and back.GroundY == 5 and back.Seq == 3)

--.. segment cache seq gating (the PetRoamClient rule: update only on a new RoamSeq with a complete segment)
local cache = {Seq = nil, Seg = nil}
local function Step(model)
	local seq = model:GetAttribute("RoamSeq")
	if seq == cache.Seq then return false end
	local s = M.ReadSegment(model)
	if not s then return false end
	cache.Seq, cache.Seg = seq, s
	return true
end
local live = {RoamFrom = from, RoamTo = to, RoamStart = 100, RoamEnd = 110, RoamGroundY = 5, RoamSeq = 1}
local model = FakeModel(live)
Check("gate: first complete accepted", Step(model) == true)
live.RoamTo = Vector3.new(20, 0, 0) -- half-published: To changed, Seq not yet
Check("gate: same seq ignored", Step(model) == false and cache.Seg.To == to)
live.RoamSeq = 2
live.RoamGroundY = nil -- broken publish
Check("gate: incomplete kept old", Step(model) == false and cache.Seg.To == to)
live.RoamGroundY = 5
Check("gate: next complete accepted", Step(model) == true and cache.Seg.To == Vector3.new(20, 0, 0))

local summary = ("WP-STATS motion: PASS %d / FAIL %d"):format(pass, fail)
if fail > 0 then summary ..= ": " .. table.concat(failures, "; ") end
return summary
