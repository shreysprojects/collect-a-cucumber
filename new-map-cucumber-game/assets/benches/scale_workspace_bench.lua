--[[
	scale_workspace_bench.lua  -- run once through execute_luau (edit mode).
	Scales the workspace bench (Map.Lobby.Props.BenchPress: frame parts, barbell parts, braces AND
	the LieSeat position) about its floor origin so it matches the scaled tier builds (build_benches.py
	SCALE / build_part_tiers.lua SCALE). The seat moves with the bench, so the hands still reach the
	bar: bar - hands = (3.0, 1.6) * (scale - 1) studs, inside BenchServer's grab tolerances (1.2 / 0.35)
	for scale <= 1.2. Records the bench attribute Scale and refuses to run twice.
]]
local SCALE = 1.12
local bench = workspace.Map.Lobby.Props.BenchPress
local seat = bench.LieSeat
local bar = bench.Barbell.PrimaryPart or bench.Barbell:FindFirstChild("Bar")
local current = bench:GetAttribute("Scale") or 1
if math.abs(current - SCALE) < 1e-3 then return "already at scale " .. SCALE end
local factor = SCALE / current
local origin = bar.Position - Vector3.new(1.5 * current, 3.5 * current, 0) -- floor under the pivot (bench-space origin)
local n = 0
for _, d in ipairs(bench:GetDescendants()) do
	if d:IsA("BasePart") then
		local rel = d.Position - origin
		d.CFrame = d.CFrame - d.Position + (origin + rel * factor)
		if d ~= seat then d.Size = d.Size * factor end
		n += 1
	end
end
bench:SetAttribute("Scale", SCALE)
return ("scaled %d parts x%.3f about %s; bar now %s, seat %s, pad top %.2f"):format(n, factor, tostring(origin), tostring(bar.Position), tostring(seat.Position), bench.Pad.Position.Y + bench.Pad.Size.Y / 2)
