--[[
	PetMotion  (ModuleScript, ReplicatedStorage.Modules)
	The one shared answer to "where is this plot pet right now" (2026-09-22, pet-system polish).
	PetService (server) plans roaming legs as a Segment and publishes it as model attributes;
	PetRoamClient / PetEffectsClient read the same attributes back and sample the same segment on
	the same clock (workspace:GetServerTimeNow()), so server range checks, shot origins, saved
	positions and what every player sees all agree -- no second low-pass smoothing on top.

	  Segment = {From: Vector3?, To: Vector3, Start: number, End: number, GroundY: number, Seq: number?}
	  Sample(seg, now) -> pos: Vector3?, walking: boolean, heading: Vector3?
	      nil / broken To or GroundY -> nil, false, nil; broken From -> To; broken or empty time
	      range (or a non-finite now) -> To, idle; now <= Start -> From; now >= End -> To; else a
	      linear lerp (walking, unless the leg has no XZ travel at all). pos.Y = GroundY.
	      heading = unit XZ of To - From when that XZ length is > 0.2, else nil.
	  ReadSegment(model) -> Segment?      attributes RoamFrom / RoamTo / RoamStart / RoamEnd /
	                                      RoamGroundY / RoamSeq (nil when RoamTo / RoamGroundY are broken)
	  ToAttributes(seg) -> {{name, value}} the publish order, RoamSeq LAST (clients treat a new
	                                      RoamSeq as "the segment is complete")
	  MUZZLE_HEIGHT                       PetBalance.FX.MUZZLE_HEIGHT (shot origin above the root)
	Pure: no state, no Instances created, never errors.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetBalance = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetBalance"))

local PetMotion = {}

local HEADING_MIN = 0.2 -- studs of XZ travel before a segment has a direction (PetRoamClient's old 0.04 squared)
local ATTRIBUTE_ORDER = {"RoamFrom", "RoamTo", "RoamStart", "RoamEnd", "RoamGroundY", "RoamSeq"}

PetMotion.MUZZLE_HEIGHT = type(PetBalance.FX) == "table" and PetBalance.FX.MUZZLE_HEIGHT or 1.5
PetMotion.ATTRIBUTES = ATTRIBUTE_ORDER -- read-only

local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function ValidVector(v)
	return typeof(v) == "Vector3" and Finite(v.X) and Finite(v.Y) and Finite(v.Z)
end

function PetMotion.Sample(seg, now)
	if type(seg) ~= "table" then return nil, false, nil end
	local to, groundY = seg.To, seg.GroundY
	if not ValidVector(to) or not Finite(groundY) then return nil, false, nil end
	local from = ValidVector(seg.From) and seg.From or to

	local heading = nil
	local dx, dz = to.X - from.X, to.Z - from.Z
	local length = math.sqrt(dx * dx + dz * dz)
	if length > HEADING_MIN then heading = Vector3.new(dx / length, 0, dz / length) end

	local t0, t1 = seg.Start, seg.End
	if not Finite(t0) or not Finite(t1) or t1 <= t0 or not Finite(now) then
		return Vector3.new(to.X, groundY, to.Z), false, heading
	end
	if now <= t0 then
		return Vector3.new(from.X, groundY, from.Z), false, heading
	end
	if now >= t1 then
		return Vector3.new(to.X, groundY, to.Z), false, heading
	end
	local a = (now - t0) / (t1 - t0)
	--.. a leg with no XZ travel (From missing / equal to To) is standing still, not walking in place
	return Vector3.new(from.X + dx * a, groundY, from.Z + dz * a), length > 0, heading
end

--.. model = the pet Model (anything with GetAttribute works, so tests can pass a plain table)
function PetMotion.ReadSegment(model)
	if typeof(model) ~= "Instance" and not (type(model) == "table" and type(model.GetAttribute) == "function") then
		return nil
	end
	local ok, seg = pcall(function()
		local to = model:GetAttribute("RoamTo")
		local groundY = model:GetAttribute("RoamGroundY")
		if not ValidVector(to) or not Finite(groundY) then return nil end
		local from = model:GetAttribute("RoamFrom")
		local t0 = model:GetAttribute("RoamStart")
		local t1 = model:GetAttribute("RoamEnd")
		local seq = model:GetAttribute("RoamSeq")
		return {
			From = ValidVector(from) and from or nil,
			To = to,
			Start = Finite(t0) and t0 or nil,
			End = Finite(t1) and t1 or nil,
			GroundY = groundY,
			Seq = Finite(seq) and seq or nil,
		}
	end)
	if ok then return seg end
	return nil
end

--.. {{"RoamFrom", v}, ... {"RoamSeq", n}} -- apply in order with model:SetAttribute(name, value)
function PetMotion.ToAttributes(seg)
	seg = type(seg) == "table" and seg or {}
	local from = seg.From
	if from == nil then from = seg.To end
	return {
		{ATTRIBUTE_ORDER[1], from},
		{ATTRIBUTE_ORDER[2], seg.To},
		{ATTRIBUTE_ORDER[3], seg.Start},
		{ATTRIBUTE_ORDER[4], seg.End},
		{ATTRIBUTE_ORDER[5], seg.GroundY},
		{ATTRIBUTE_ORDER[6], seg.Seq},
	}
end

return PetMotion
