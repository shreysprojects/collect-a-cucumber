--[[
	BenchTierClient  (LocalScript, StarterPlayerScripts)
	Shows every plot bench (models tagged "PlotBench", attribute Plot = plot name; PlotUpgradeService
	stands one by each plot) with the LOOK of its plot owner's bench tier: the plot's BenchTier
	attribute (GymService.SyncPlot, 1..6 = BenchRuntimeMesh.THEMES). Everyone sees your themed
	bench on your plot; an unowned plot shows tier 1.
	The server bench keeps the functional pieces (part-built frame, LieSeat, Barbell moved by
	BenchServer / BarbellClient). This script hides that bench's parts locally and shows the tier's
	meshes:
	  1. a real tier model in ReplicatedStorage.Assets.BenchTiers (attr FromAssets=true), or
	  2. a model built at run time by ReplicatedStorage.Modules.BenchRuntimeMesh (needs Game
	     Settings > Security > Allow Mesh & Image APIs), or
	  3. the part-built fallback tier models in Assets.BenchTiers (attr Fallback=true).
	Tier 1 has no stored model: the server bench itself is the Starter look. If nothing can be shown
	the server bench stays visible, so nothing is ever missing.
	Placement: the tier's Visual is moved so its bar lands on the server bar's rest position
	(Barbell attribute RackCFrame);
	the barbell parts are welded to the server Bar so they follow the lift.
	Size: the visual grows with the plot's BenchLevel exactly like the server bench does
	(ReplicatedStorage.Modules.BenchScale: +10% footprint per level about the bar, heights kept,
	barbell uniform), so the tier look always sits on the real bench.
	Animation: parts named Float / Float<n> (Cosmic's drifting crystals) bob, circle and spin;
	parts named Flames (Inferno's fire bowls) flicker. Everything is re-checked every CHECK_PERIOD
	seconds: tier or level changes, a moved bench (plot resized), streaming in / out.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local BenchRuntimeMesh = require(Modules:WaitForChild("BenchRuntimeMesh"))
local BenchScale = require(Modules:WaitForChild("BenchScale"))

local BENCH_TAG = "PlotBench"
local CHECK_PERIOD = 0.5
local MAX_TIER = #BenchRuntimeMesh.THEMES
local FLOAT_RADIUS = 0.7 -- studs: drifting crystals circle this far around their spot
local FLOAT_BOB = 0.35
local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

local shown = {} -- [bench] = {Tier, Level, Visual, Barbell, ServerBar, Rack, Anim = {entries}}
local runtimeModels = {} -- [tier] = Model built by BenchRuntimeMesh (parented to nil, cloned when shown)
local building = {} -- [bench] = true while a build runs
local warnedMissing = {} -- [tier] = true once the missing-model warning has been printed

local function PlotOf(bench)
	local name = bench:GetAttribute("Plot")
	return name and Plots:FindFirstChild(name) or nil
end

local function TierOf(bench)
	local plot = PlotOf(bench)
	local tier = plot and plot:GetAttribute("BenchTier")
	return math.clamp(math.floor(tonumber(tier) or 1), 1, MAX_TIER)
end

local function LevelOf(bench)
	local plot = PlotOf(bench)
	return math.max(1, math.floor(tonumber(plot and plot:GetAttribute("BenchLevel")) or 1))
end

local function ServerBar(bench)
	local barbell = bench:FindFirstChild("Barbell")
	local bar = barbell and (barbell.PrimaryPart or barbell:FindFirstChild("Bar"))
	if bar and bar:IsDescendantOf(workspace) then return bar, barbell end
	return nil
end

--.. where the bar rests: BenchServer / PlotUpgradeService keep it on the Barbell model
local function RackOf(barbell, bar)
	local rack = barbell:GetAttribute("RackCFrame")
	if typeof(rack) == "CFrame" then return rack end
	return bar.CFrame
end

--.. stored tier models: attribute FromAssets (real mesh assets) or Fallback (part-built versions)
local function StoredTierModel(tier, attribute)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("BenchTiers")
	if not folder then return nil end
	for _, m in ipairs(folder:GetChildren()) do
		if m:GetAttribute("Tier") == tier and m:GetAttribute(attribute) == true then return m end
	end
	return nil
end

--.. priority: real assets > Blender meshes built at run time > part-built fallback > server bench.
--.. May yield (first runtime build of a theme); returns nil when nothing can be shown.
local function TierModel(tier, bench, rack)
	local fromAssets = StoredTierModel(tier, "FromAssets")
	if fromAssets then return fromAssets end
	if tier <= 1 then return nil end -- the server bench IS the Starter look: no EditableMesh budget spent on it (2026-09-12)
	if runtimeModels[tier] then return runtimeModels[tier] end
	if BenchRuntimeMesh.IsAvailable() then
		local model = BenchRuntimeMesh.BuildTier(BenchRuntimeMesh.ThemeForTier(tier), rack)
		if model then
			local seat = bench:FindFirstChild("LieSeat")
			if seat then model:SetAttribute("SeatCFrame", seat.CFrame) end
			runtimeModels[tier] = model
			return model
		end
	end
	local fallback = StoredTierModel(tier, "Fallback")
	if not fallback and tier > 1 and not warnedMissing[tier] then
		warnedMissing[tier] = true
		warn(("[BenchTierClient] no model for bench tier %d in ReplicatedStorage.Assets.BenchTiers (FromAssets / Fallback) -- the server bench stays visible; tiers 7-8 are installed by assets/benches/install_tiers_78.lua"):format(tier))
	end
	return fallback
end

local function Clear(bench)
	local s = shown[bench]
	if not s then return end
	if s.Visual then s.Visual:Destroy() end
	if s.Barbell then s.Barbell:Destroy() end
	shown[bench] = nil
end

local function SetHidden(bench, hidden)
	for _, d in ipairs(bench:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "LieSeat" then
			d.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local function IsFloat(name)
	return name == "Float" or name:match("^Float%d+$") ~= nil
end

local function Build(bench, tier, level, serverBar, barbell, rack)
	local model = TierModel(tier, bench, rack)
	local visualSrc = model and model:FindFirstChild("Visual")
	local barSrc = model and model:FindFirstChild("Barbell")
	local tierBar = barSrc and (barSrc.PrimaryPart or barSrc:FindFirstChild("Bar"))
	if not (visualSrc and tierBar and serverBar.Parent) then return false end
	local scale = BenchScale.Factor(level)
	local benchCF = BenchScale.BenchCFrame(rack)
	local anim = {}

	--.. frame: anchored copy, moved from where the tier model was built to this bench, then grown
	--.. to the bench's level exactly like BenchServer grows the real bench
	local visual = visualSrc:Clone()
	visual.Name = "LocalBenchVisual"
	--.. bar onto bar: the rack never moves, while BenchServer resizes and shifts the seat's touch volume
	local delta = rack * tierBar.CFrame:Inverse()
	visual:PivotTo(delta * visual:GetPivot())
	for _, p in ipairs(visual:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false -- physics stays on the server bench parts, which are only hidden
			p.CanQuery = false
			p.CanTouch = false
			local cf, size = BenchScale.FrameTransform(benchCF:ToObjectSpace(p.CFrame), p.Size, scale)
			p.Size = size
			p.CFrame = benchCF * cf
			if IsFloat(p.Name) then
				table.insert(anim, {Kind = "Float", Part = p, Base = p.CFrame, Phase = math.random() * math.pi * 2})
			elseif p.Name == "Flames" then
				table.insert(anim, {Kind = "Flames", Part = p, Base = p.CFrame, BaseSize = p.Size, Phase = math.random() * math.pi * 2})
			end
		end
	end
	visual.Parent = workspace

	--.. barbell: ANCHORED copies (no welds, no physics -- nothing can fall off) at the tier model's
	--.. offsets grown about the bar. The model is tagged "BarFollower" with an ObjectValue "ServerBar"
	--.. and each copy carries its BarOffset, so BarbellClient poses the copies in the very same step
	--.. as the server bar it moves with the holder's hands (never a frame behind).
	local bb = Instance.new("Model")
	bb.Name = "LocalBenchBarbell"
	local barCF = tierBar.CFrame
	for _, p in ipairs(barSrc:GetDescendants()) do
		if p:IsA("BasePart") then
			local c = p:Clone()
			for _, ch in ipairs(c:GetChildren()) do
				if ch:IsA("Constraint") or ch:IsA("WeldConstraint") or ch:IsA("JointInstance") then ch:Destroy() end
			end
			c.Anchored = true
			c.CanCollide = false
			c.CanQuery = false
			c.CanTouch = false
			local cf, size = BenchScale.BarbellTransform(barCF:Inverse() * p.CFrame, p.Size, scale)
			c.Size = size
			c.CFrame = serverBar.CFrame * cf
			c:SetAttribute("BarOffset", cf)
			c.Parent = bb
		end
	end
	local ref = Instance.new("ObjectValue")
	ref.Name = "ServerBar"
	ref.Value = serverBar
	ref.Parent = bb
	CollectionService:AddTag(bb, "BarFollower")
	bb.Parent = workspace
	shown[bench] = {Tier = tier, Level = level, Visual = visual, Barbell = bb, ServerBar = serverBar, Rack = rack, Anim = anim}
	return true
end

local function Moved(a, b)
	return (a.Position - b.Position).Magnitude > 0.05 or (a.LookVector - b.LookVector).Magnitude > 0.02
end

local function Tick()
	local live = {}
	for _, bench in ipairs(CollectionService:GetTagged(BENCH_TAG)) do
		if bench:IsDescendantOf(workspace) then
			live[bench] = true
			local tier = TierOf(bench)
			local level = LevelOf(bench)
			local serverBar, barbell = ServerBar(bench)
			local rack = serverBar and RackOf(barbell, serverBar)
			local want = serverBar ~= nil
			local s = shown[bench]
			if s and (not want or s.Tier ~= tier or s.Level ~= level or s.ServerBar ~= serverBar or Moved(s.Rack, rack)) then
				Clear(bench)
				s = nil
			end
			if want and not s and not building[bench] then
				building[bench] = true
				local ok, err = pcall(Build, bench, tier, level, serverBar, barbell, rack)
				building[bench] = nil
				if not ok then warn("[BenchTierClient] build failed:", err) end
			end
			SetHidden(bench, shown[bench] ~= nil)
		end
	end
	for bench in pairs(shown) do
		if not live[bench] then Clear(bench) end
	end
end

--.. drifting crystals and flickering flames on the shown tier visuals
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, s in pairs(shown) do
		for _, e in ipairs(s.Anim) do
			local part = e.Part
			if part.Parent then
				if e.Kind == "Float" then
					local ang = t * 0.7 + e.Phase
					local offset = Vector3.new(math.cos(ang) * FLOAT_RADIUS, math.sin(t * 1.6 + e.Phase) * FLOAT_BOB, math.sin(ang) * FLOAT_RADIUS)
					part.CFrame = CFrame.new(e.Base.Position + offset) * CFrame.Angles(0, t * 1.2 + e.Phase, 0) * e.Base.Rotation
				else
					local k = 1 + 0.12 * math.sin(t * 9 + e.Phase)
					part.Size = e.BaseSize * k
					part.CFrame = e.Base * CFrame.new(0, 0.12 * math.sin(t * 5 + e.Phase), 0)
				end
			end
		end
	end
end)

task.spawn(function()
	while true do
		Tick()
		task.wait(CHECK_PERIOD)
	end
end)
