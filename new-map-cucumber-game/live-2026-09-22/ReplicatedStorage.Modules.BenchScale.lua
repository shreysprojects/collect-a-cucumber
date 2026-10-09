--[[
	BenchScale  (ModuleScript, ReplicatedStorage.Modules)
	Per-level bench growth: every bench upgrade level makes the bench STEP (10%) bigger.
	The growth is in the bench's footprint: positions and sizes ALONG the bench (x) and ACROSS it
	(z) scale by Factor(level); heights stay as they are, and along the bench the scaling is centred
	on the bar's x, so the rack, the bar height, the seat (which never moves) and the lying pose /
	grab detection keep working at every level. Barbell parts scale uniformly about the bar centre
	(longer bar, bigger plates, same rack height).
	Used by BenchServer for the real plot benches and by BenchTierClient for the tier visuals, so
	both grow identically.
	Bench space: origin on the floor under the bench pivot, x toward the rack, y up, z across; the
	bar centre sits at RACK_OFFSET and the Bar part's local X runs across the bench.
]]
local BenchScale = {}
BenchScale.STEP = 1.1
BenchScale.MAX_GROWTH_LEVEL = 6 -- the bench stops growing at the Cosmic tier; Celestial (7) / VoidEmperor (8) keep that size
BenchScale.RACK_OFFSET = Vector3.new(1.68, 3.92, 0) -- bar centre from the bench origin (scaled base build)

function BenchScale.Factor(level)
	local l = math.max(1, math.floor(tonumber(level) or 1))
	l = math.min(l, BenchScale.MAX_GROWTH_LEVEL)
	return BenchScale.STEP ^ (l - 1)
end

--.. bench space from where the bar rests
function BenchScale.BenchCFrame(rackCF, rackOffset)
	local off = rackOffset or BenchScale.RACK_OFFSET
	return rackCF * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new(-off.X, -off.Y, -off.Z)
end

local function Aligned(rot) -- every local axis lines up with a bench axis (blocks, cylinders); turned decor does not
	for _, v in ipairs({rot.RightVector, rot.UpVector, rot.LookVector}) do
		if math.max(math.abs(v.X), math.abs(v.Y), math.abs(v.Z)) < 0.95 then return false end
	end
	return true
end

local function SizeFactor(rot, s) -- per local axis: vertical axes keep their size, horizontal ones grow
	local function f(v) return math.abs(v.Y) > 0.5 and 1 or s end
	return Vector3.new(f(rot.RightVector), f(rot.UpVector), f(rot.LookVector))
end

--.. frame part: offset = its unscaled CFrame in bench space, size = its unscaled size
--.. returns the scaled bench-space CFrame and size
function BenchScale.FrameTransform(offset, size, s, rackX)
	rackX = rackX or BenchScale.RACK_OFFSET.X
	local p = offset.Position
	local cf = CFrame.new(rackX + (p.X - rackX) * s, p.Y, p.Z * s) * offset.Rotation
	local newSize = Aligned(offset.Rotation) and size * SizeFactor(offset.Rotation, s) or size * s
	return cf, newSize
end

--.. barbell part: offset relative to the Bar root; uniform growth about the bar centre
function BenchScale.BarbellTransform(offset, size, s)
	return CFrame.new(offset.Position * s) * offset.Rotation, size * s
end

return BenchScale
