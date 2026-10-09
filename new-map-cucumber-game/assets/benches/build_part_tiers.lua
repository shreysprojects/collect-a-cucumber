--[[
	build_part_tiers.lua  -- run through the Studio MCP execute_luau in EDIT mode.
	Part-built fallback versions of the bench tiers (same layout numbers as build_benches.py, plain
	Parts: blocks, cylinders, balls, "diamonds" = cubes standing on a corner). They need no mesh
	upload and no "Allow Mesh & Image APIs", persist in the place, and are what BenchTierClient
	shows when the Blender runtime meshes cannot be built. Tier 1 (Starter) is the workspace bench
	itself (restyled here as wood + stone), tiers 2-6 go to
	    ReplicatedStorage.Assets.BenchTiers.<Theme>   (attrs Tier, Theme, SeatCFrame, Fallback=true)
	        Visual  (Model, anchored parts at the platform)
	        Barbell (Model, PrimaryPart Bar (Cylinder, local X = bar axis) at the rack)
	Bench space = Blender coords (x along the bench toward the rack, y across, z up, floor z = 0);
	Roblox local = (x, z, -y); world = benchCF * local.  Re-runnable (replaces existing fallbacks).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SCALE = 1.12 -- design-size geometry scaled about the floor origin (same as build_benches.py SCALE / scale_workspace_bench.lua)

local bench = workspace.Map.Lobby.Props.BenchPress
local seat = bench.LieSeat
local liveBar = bench.Barbell.PrimaryPart or bench.Barbell:FindFirstChild("Bar")
local rackCF = liveBar.CFrame
local benchCF = rackCF * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new(-1.5 * SCALE, -3.5 * SCALE, 0)
local log = {}

local TIERS = {
	{name = "Iron", tier = 2, post = 0.30, pad_w = 1.05, pad_t = 0.26, plate_r = 0.70, plate_t = 0.17, plates = 3, bar_r = 0.055, style = "rubber",
		mats = {Frame = {"8e939c", "Metal"}, Pad = {"1f5fd6", "SmoothPlastic"}, Feet = {"232428", "SmoothPlastic"}, Bar = {"c4c8d0", "Metal"}, Plates = {"1b1b1e", "SmoothPlastic"}, Collars = {"9a9ea6", "Metal"}}},
	{name = "Gold", tier = 3, post = 0.36, pad_w = 1.15, pad_t = 0.30, plate_r = 0.78, plate_t = 0.18, plates = 4, bar_r = 0.06, style = "rim",
		mats = {Frame = {"e3b526", "Metal"}, Pad = {"b8202a", "SmoothPlastic"}, Trim = {"f5d76e", "Metal"}, Feet = {"2a2a2e", "SmoothPlastic"}, Gems = {"f6c93c", "Metal"}, Bar = {"d7d9dd", "Metal"}, Plates = {"3a2a1e", "SmoothPlastic"}, Rims = {"e3b526", "Metal"}, Collars = {"e3b526", "Metal"}}},
	{name = "Frost", tier = 4, post = 0.42, pad_w = 1.25, pad_t = 0.34, plate_r = 0.86, plate_t = 0.20, plates = 5, bar_r = 0.065, style = "ice",
		mats = {Frame = {"4fa9e6", "Ice"}, Pad = {"2f9fe0", "SmoothPlastic"}, Trim = {"f4fbff", "SmoothPlastic"}, Crystals = {"b6e6ff", "Ice"}, Glow = {"e6fbff", "Neon"}, Bar = {"cfd6dd", "Metal"}, Plates = {"8fd3fa", "Ice"}, Collars = {"2c4a60", "Metal"}}},
	{name = "Inferno", tier = 5, post = 0.50, pad_w = 1.35, pad_t = 0.38, plate_r = 0.94, plate_t = 0.22, plates = 6, bar_r = 0.07, style = "lava",
		mats = {Frame = {"2c2c31", "Slate"}, Pad = {"c4262b", "SmoothPlastic"}, Trim = {"ff7a1a", "Neon"}, Lava = {"ff5a14", "Neon"}, Bowls = {"3a3a40", "Slate"}, Flames = {"ffb02e", "Neon"}, Bar = {"a9adb4", "Metal"}, Plates = {"35302e", "Slate"}, Glow = {"ff6a1f", "Neon"}, Collars = {"4a4a50", "Metal"}}},
	{name = "Cosmic", tier = 6, post = 0.58, pad_w = 1.45, pad_t = 0.42, plate_r = 0.95, plate_t = 0.30, plates = 3, orb_r = 1.05, bar_r = 0.075, style = "orb",
		mats = {Frame = {"2b2361", "Metal"}, Pad = {"7c3ae0", "SmoothPlastic"}, Trim = {"d9a93a", "Metal"}, Runes = {"8fe9ff", "Neon"}, Crystals = {"7a5cff", "Neon"}, Float = {"7a5cff", "Neon"}, Bar = {"b9bcc7", "Metal"}, Plates = {"2a1a5e", "SmoothPlastic"}, Glow = {"62e8ff", "Neon"}, Collars = {"d9a93a", "Metal"}}},
}

local DIAMOND = CFrame.Angles(math.rad(35.264), 0, math.rad(45)) -- cube standing on a corner
local NO_COLLIDE = {Gems = true, Crystals = true, Float = true, Glow = true, Lava = true, Flames = true, Runes = true, Trim = true}

--.. the map's studded / welded looks: MaterialService variants the user placed there (Plastic based).
--.. Frame-type parts get "Studs", barbell parts "Weld"; glowing (Neon) parts keep their glow.
local VARIANTS = {Frame = "Studs", Pad = "Studs", Feet = "Studs", Trim = "Studs", Bowls = "Studs",
	Bar = "Weld", Collars = "Weld", Plates = "Weld", Rims = "Weld"}

local function ApplyVariant(part, matName, baseMaterialName)
	for _, c in ipairs(part:GetChildren()) do
		if c.Name == "Studs" and (c:IsA("Texture") or c:IsA("Decal")) then c:Destroy() end -- the old overlay
	end
	local variant = VARIANTS[matName]
	if variant and baseMaterialName ~= "Neon" then
		part.Material = Enum.Material.Plastic
		part.MaterialVariant = variant
	else
		part.MaterialVariant = ""
	end
end

local function B2R(v) return Vector3.new(v.X, v.Z, -v.Y) end -- bench (Blender) -> Roblox local

local function Styled(part, cfg, matName)
	local m = cfg.mats[matName] or {"ffffff", "SmoothPlastic"}
	part.Color = Color3.fromHex(m[1])
	part.Material = Enum.Material[m[2]]
	part.Name = matName
	part.Anchored = true
	part.CanCollide = not NO_COLLIDE[matName]
	part.CanQuery = part.CanCollide
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	ApplyVariant(part, matName, m[2])
	return part
end

--.. axis-aligned box from Blender corners lo -> hi
local function Box(parent, cfg, matName, lo, hi)
	local c, s = (lo + hi) / 2, hi - lo
	local p = Instance.new("Part")
	p.Size = Vector3.new(s.X, s.Z, s.Y) * SCALE
	p.CFrame = benchCF * CFrame.new(B2R(c) * SCALE)
	Styled(p, cfg, matName).Parent = parent
	return p
end

--.. any shape at a Blender centre with a Roblox-space size and extra rotation
local function At(parent, cfg, matName, shape, centre, size, rot)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size * SCALE
	p.CFrame = benchCF * CFrame.new(B2R(centre) * SCALE) * (rot or CFrame.identity)
	Styled(p, cfg, matName).Parent = parent
	return p
end

local function Diamond(parent, cfg, matName, centre, size)
	return At(parent, cfg, matName, Enum.PartType.Block, centre, Vector3.new(size, size, size), DIAMOND)
end

--.. prism from a Blender base point to a tip point (square cross-section turned 45 degrees)
local function Prism(parent, cfg, matName, base, tip, r)
	local mid = (base + tip) / 2
	local len = (tip - base).Magnitude
	local p = Instance.new("Part")
	p.Size = Vector3.new(r * 1.6, r * 1.6, len) * SCALE
	p.CFrame = CFrame.lookAt(benchCF * CFrame.new(B2R(mid) * SCALE).Position, benchCF * CFrame.new(B2R(tip) * SCALE).Position) * CFrame.Angles(0, 0, math.rad(45))
	Styled(p, cfg, matName).Parent = parent
	return p
end

local function BuildFrame(visual, cfg)
	local p, w, t, tier, r = cfg.post, cfg.pad_w, cfg.pad_t, cfg.tier, cfg.bar_r
	local zb = 1.3 - t
	local beam_w = 0.22 + (p - 0.2)
	local beam_h = 0.16 + (p - 0.2) * 0.5
	local fh = 0.10 + (p - 0.2) * 0.4
	local x_tail = -1.8 - 0.05 * (tier - 1)
	local feetMat = cfg.mats.Feet and "Feet" or "Frame"
	Box(visual, cfg, "Pad", Vector3.new(x_tail, -w / 2, zb), Vector3.new(1.6, w / 2, 1.3))
	Box(visual, cfg, "Frame", Vector3.new(x_tail + 0.25, -beam_w / 2, zb - beam_h), Vector3.new(1.5, beam_w / 2, zb))
	for _, post in ipairs({{-1.35, 1.2 + (w - 0.9), 0.02}, {1.25, 0.6 + (w - 0.9), 0.15}}) do
		local x, fl, fx = post[1], post[2], post[3]
		Box(visual, cfg, "Frame", Vector3.new(x - p / 2, -p / 2, fh - 0.01), Vector3.new(x + p / 2, p / 2, zb - beam_h + 0.01))
		Box(visual, cfg, feetMat, Vector3.new(x - p / 2 - fx, -fl / 2, 0), Vector3.new(x + p / 2 + fx, fl / 2, fh))
	end
	local yu = 1.25 + p / 2
	local xu0, xu1 = 1.6, 1.6 + p
	local hu = 3.9 + 0.12 * (tier - 1)
	local zs = 3.5 - r
	local hw = 0.12 + (p - 0.2) * 0.3
	for _, s in ipairs({-1, 1}) do
		local y = s * yu
		Box(visual, cfg, "Frame", Vector3.new(xu0, y - p / 2, fh - 0.01), Vector3.new(xu1, y + p / 2, hu))
		Box(visual, cfg, feetMat, Vector3.new(xu0 - 0.5 - (p - 0.2) * 0.5, y - p / 2 - 0.02, 0), Vector3.new(xu1 + 0.5 + (p - 0.2) * 0.5, y + p / 2 + 0.02, fh))
		Box(visual, cfg, "Frame", Vector3.new(1.3, y - hw, zs - 0.1), Vector3.new(xu0 + 0.01, y + hw, zs))
		Box(visual, cfg, "Frame", Vector3.new(1.3, y - hw, zs - 0.1), Vector3.new(1.38, y + hw, zs + 0.3))
	end
	Box(visual, cfg, "Frame", Vector3.new(xu0, -yu, 0), Vector3.new(xu1, yu, 0.14 + (p - 0.2) * 0.3))
	return {zb = zb, yu = yu, xu0 = xu0, xu1 = xu1, hu = hu, fh = fh, beam_h = beam_h, x_tail = x_tail, xo = xu0 + p / 2}
end

local function BuildBarbell(barbell, cfg, g)
	local r, R, T, n, tier = cfg.bar_r, cfg.plate_r, cfg.plate_t, cfg.plates, cfg.tier
	local xc = g.yu + cfg.post / 2 + 0.22
	local x0 = xc + 0.10 + T / 2
	local positions = {}
	for i = 0, n - 1 do positions[#positions + 1] = x0 + i * (T + 0.03) end
	local endX = positions[#positions] + T / 2
	local orbX
	if cfg.style == "orb" then -- Cosmic: galaxy plates, then the big orb on the end
		local orbW = cfg.orb_r * 0.6
		orbX = endX + 0.06 + orbW
		endX = orbX + orbW
	end
	local L = 2 * (endX + 0.35)
	local function cyl(matName, x, thick, radius, tilt)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(thick, radius * 2, radius * 2) * SCALE
		p.CFrame = rackCF * CFrame.new(x * SCALE, 0, 0) * (tilt or CFrame.identity)
		Styled(p, cfg, matName)
		p.CanCollide = false
		p.CanQuery = false
		p.Parent = barbell
		return p
	end
	local bar = cyl("Bar", 0, L, r)
	barbell.PrimaryPart = bar
	for _, s in ipairs({-1, 1}) do
		cyl("Collars", s * xc, 0.12 + (tier - 1) * 0.01, r * 2.2 + 0.05)
		if orbX then
			local orb = Instance.new("Part")
			orb.Shape = Enum.PartType.Ball
			orb.Size = Vector3.new(cfg.orb_r * 1.7, cfg.orb_r * 1.7, cfg.orb_r * 1.7) * SCALE
			orb.CFrame = rackCF * CFrame.new(s * orbX * SCALE, 0, 0)
			Styled(orb, cfg, "Plates")
			orb.CanCollide = false
			orb.CanQuery = false
			orb.Parent = barbell
			cyl("Glow", s * orbX, 0.07, cfg.orb_r + 0.04)
			cyl("Glow", s * orbX, 0.05, cfg.orb_r + 0.12, CFrame.Angles(0, 0, math.rad(20)))
		end
		for _, x in ipairs(positions) do
			local xx = s * x
			if cfg.style == "rubber" or cfg.style == "ice" then
				cyl("Plates", xx, T, R)
			elseif cfg.style == "rim" then
				cyl("Plates", xx, T, R)
				cyl("Rims", xx, T * 0.4, R + 0.05)
			elseif cfg.style == "lava" then
				cyl("Plates", xx - T * 0.3, T * 0.4, R)
				cyl("Plates", xx + T * 0.3, T * 0.4, R)
				cyl("Glow", xx, T * 0.22, R + 0.02)
			elseif cfg.style == "orb" then
				cyl("Plates", xx, T, R)
				cyl("Glow", xx, T * 0.25, R + 0.03)
			end
		end
	end
	return L * SCALE
end

local DECOR = {}
function DECOR.Iron(visual, cfg, g)
	local p = cfg.post
	for _, s in ipairs({-1, 1}) do
		for _, x in ipairs({g.xu0 - 0.17, g.xu1 + 0.17}) do
			At(visual, cfg, "Frame", Enum.PartType.Block, Vector3.new(x, s * g.yu, g.fh + 0.12), Vector3.new(0.28, 0.28, p * 0.8), CFrame.Angles(0, 0, math.rad(45)))
		end
	end
	Box(visual, cfg, "Frame", Vector3.new(g.xu0, -g.yu, 2.2), Vector3.new(g.xu1, g.yu, 2.36))
end
function DECOR.Gold(visual, cfg, g)
	local w, p = cfg.pad_w, cfg.post
	Box(visual, cfg, "Trim", Vector3.new(g.x_tail - 0.06, -w / 2 - 0.05, g.zb - 0.07), Vector3.new(1.66, w / 2 + 0.05, g.zb))
	for _, s in ipairs({-1, 1}) do
		for _, z in ipairs({1.5, 2.6}) do Diamond(visual, cfg, "Gems", Vector3.new(g.xo, s * (g.yu + p / 2 + 0.03), z), 0.2) end
		Diamond(visual, cfg, "Gems", Vector3.new(g.xu0 - 0.03, s * g.yu, 3.05), 0.16)
		Diamond(visual, cfg, "Gems", Vector3.new(g.xo, s * g.yu, g.hu + 0.3), 0.32)
	end
	Diamond(visual, cfg, "Gems", Vector3.new(-1.35, 0, g.zb - g.beam_h - 0.02), 0.18)
end
function DECOR.Frost(visual, cfg, g)
	local w, p = cfg.pad_w, cfg.post
	Box(visual, cfg, "Trim", Vector3.new(g.x_tail - 0.05, -w / 2 - 0.04, g.zb - 0.07), Vector3.new(1.65, w / 2 + 0.04, g.zb))
	for _, s in ipairs({-1, 1}) do
		local yo = s * (g.yu + p / 2)
		for _, c in ipairs({{0.5, 0.35, 0.9, 0.8, 0.2}, {1.7, -0.2, 0.75, 1.1, 0.17}, {2.9, 0.3, 0.6, 1.0, 0.15}}) do
			local z, dx, dy, dz, r = c[1], c[2], c[3], c[4], c[5]
			Prism(visual, cfg, "Crystals", Vector3.new(g.xo, yo, z), Vector3.new(g.xo + dx, yo + s * dy, z + dz), r)
		end
		local base, tip = Vector3.new(g.xo, s * g.yu, g.hu - 0.1), Vector3.new(g.xo, s * g.yu, g.hu + 1.25)
		Prism(visual, cfg, "Crystals", base, base + (tip - base) * 0.78, 0.27)
		Diamond(visual, cfg, "Glow", base + (tip - base) * 0.84, 0.3)
	end
	for _, c in ipairs({{-2.0, 0.85, 0.9, 0.2}, {-2.0, -0.85, 0.7, 0.17}, {0.2, w / 2 + 0.55, 0.8, 0.19}, {0.3, -w / 2 - 0.55, 0.6, 0.16}, {2.5, 0.0, 0.75, 0.2}}) do
		local x, y, h, r = c[1], c[2], c[3], c[4]
		Prism(visual, cfg, "Crystals", Vector3.new(x, y, 0), Vector3.new(x + 0.1, y * 1.15, h), r)
		Diamond(visual, cfg, "Crystals", Vector3.new(x + 0.1, y * 1.15, h), r * 1.3)
	end
end
function DECOR.Inferno(visual, cfg, g)
	local w, p = cfg.pad_w, cfg.post
	Box(visual, cfg, "Trim", Vector3.new(g.x_tail - 0.04, -w / 2 - 0.03, g.zb - 0.05), Vector3.new(1.64, w / 2 + 0.03, g.zb))
	for _, s in ipairs({-1, 1}) do
		local yo = s * (g.yu + p / 2)
		for i, z in ipairs({0.9, 2.0, 3.1}) do
			At(visual, cfg, "Lava", Enum.PartType.Block, Vector3.new(g.xo, yo, z), Vector3.new(0.07, 0.55, 0.05), CFrame.Angles(0, 0, math.rad(i % 2 == 1 and 22 or -22)))
		end
		for i, z in ipairs({1.4, 2.6}) do
			At(visual, cfg, "Lava", Enum.PartType.Block, Vector3.new(g.xu0, s * g.yu, z), Vector3.new(0.05, 0.5, 0.07), CFrame.Angles(math.rad(i % 2 == 1 and 20 or -20), 0, 0))
		end
		Diamond(visual, cfg, "Frame", Vector3.new(g.xo, s * g.yu, g.hu + 0.22), p * 0.7)
		local bx, by = g.xu1 + 0.6, s * (g.yu + 0.8)
		At(visual, cfg, "Bowls", Enum.PartType.Cylinder, Vector3.new(bx, by, 0.18), Vector3.new(0.36, 0.64, 0.64), CFrame.Angles(0, 0, math.rad(90)))
		Diamond(visual, cfg, "Flames", Vector3.new(bx, by, 0.62), 0.32)
		Diamond(visual, cfg, "Flames", Vector3.new(bx + 0.1, by + 0.08, 0.5), 0.2)
		Diamond(visual, cfg, "Flames", Vector3.new(bx - 0.1, by - 0.07, 0.46), 0.16)
	end
	At(visual, cfg, "Lava", Enum.PartType.Block, Vector3.new(-1.35, -p / 2, 0.75), Vector3.new(0.05, 0.4, 0.05))
	At(visual, cfg, "Lava", Enum.PartType.Block, Vector3.new(1.25, p / 2, 0.7), Vector3.new(0.05, 0.36, 0.05))
end
function DECOR.Cosmic(visual, cfg, g)
	local w, p = cfg.pad_w, cfg.post
	Box(visual, cfg, "Trim", Vector3.new(g.x_tail - 0.06, -w / 2 - 0.05, g.zb - 0.07), Vector3.new(1.66, w / 2 + 0.05, g.zb))
	for _, s in ipairs({-1, 1}) do
		local y = s * g.yu
		Box(visual, cfg, "Trim", Vector3.new(g.xu0 - 0.03, y - p * 0.2, 0.3), Vector3.new(g.xu0, y + p * 0.2, g.hu - 0.3))
		Box(visual, cfg, "Trim", Vector3.new(g.xu0 - 0.04, y - p / 2 - 0.04, g.hu), Vector3.new(g.xu1 + 0.04, y + p / 2 + 0.04, g.hu + 0.12))
		for _, z in ipairs({1.4, 2.5}) do
			At(visual, cfg, "Runes", Enum.PartType.Block, Vector3.new(g.xo, s * (g.yu + p / 2 + 0.01), z), Vector3.new(0.2, 0.2, 0.04), CFrame.Angles(0, 0, math.rad(45)))
		end
		Diamond(visual, cfg, "Crystals", Vector3.new(g.xo, y, g.hu + 0.57), 0.36)
		--.. drifting crystals ("Float": BenchTierClient bobs, orbits and spins them)
		Diamond(visual, cfg, "Float", Vector3.new(2.7, s * (g.yu + 1.1), 2.3), 0.3)
		Diamond(visual, cfg, "Float", Vector3.new(-2.3, s * 0.9, 1.9), 0.24)
		Diamond(visual, cfg, "Float", Vector3.new(0.3, s * (w / 2 + 1.0), 3.5), 0.26)
	end
	Box(visual, cfg, "Trim", Vector3.new(-1.35 - p / 2 - 0.05, -p / 2 - 0.05, g.fh), Vector3.new(-1.35 + p / 2 + 0.05, p / 2 + 0.05, g.fh + 0.1))
end

--.. storage
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local tiersFolder = assets:FindFirstChild("BenchTiers") or Instance.new("Folder")
tiersFolder.Name = "BenchTiers"
tiersFolder:SetAttribute("Placeholder", nil)
tiersFolder.Parent = assets

for _, cfg in ipairs(TIERS) do
	local old = tiersFolder:FindFirstChild(cfg.name)
	if old and old:GetAttribute("FromAssets") ~= true then old:Destroy() end
	if not (old and old:GetAttribute("FromAssets") == true) then
		local model = Instance.new("Model")
		model.Name = cfg.name
		model:SetAttribute("Tier", cfg.tier)
		model:SetAttribute("Theme", cfg.name)
		model:SetAttribute("Fallback", true)
		model:SetAttribute("SeatCFrame", seat.CFrame)
		local visual = Instance.new("Model")
		visual.Name = "Visual"
		local g = BuildFrame(visual, cfg)
		DECOR[cfg.name](visual, cfg, g)
		visual.Parent = model
		local barbell = Instance.new("Model")
		barbell.Name = "Barbell"
		local L = BuildBarbell(barbell, cfg, g)
		barbell.Parent = model
		model.Parent = tiersFolder
		table.insert(log, ("%s: %d frame parts, %d barbell parts, bar %.2f"):format(cfg.name, #visual:GetChildren(), #barbell:GetChildren(), L))
	else
		table.insert(log, cfg.name .. ": kept asset model")
	end
end

--.. the workspace bench becomes the Starter look (wood frame, dark pad, stone plates, wood collars)
local starter = {mats = {Frame = {"8a5a2b", "WoodPlanks"}, Pad = {"2a2a2e", "SmoothPlastic"}, Plates = {"8c8c88", "Slate"}, Collars = {"5a3a1c", "Wood"}, Bar = {"b8bcc4", "Metal"}}}
local function restyle(part, matName)
	local m = starter.mats[matName]
	part.Color = Color3.fromHex(m[1])
	part.Material = Enum.Material[m[2]]
end
for _, c in ipairs(bench:GetChildren()) do
	if c:IsA("BasePart") and c ~= seat then
		local group = c.Name == "Pad" and "Pad" or "Frame"
		restyle(c, group)
		ApplyVariant(c, group, starter.mats[group][2])
	end
end
for _, c in ipairs(bench.Barbell:GetChildren()) do
	if c:IsA("BasePart") then
		local group = c.Name == "Bar" and "Bar" or (c.Name == "Collar" and "Collars" or "Plates")
		restyle(c, group)
		ApplyVariant(c, group, starter.mats[group][2])
	end
end
for _, old in ipairs(bench:GetChildren()) do
	if old.Name == "Brace" then old:Destroy() end
end
for _, z in ipairs({1.1, 2.4}) do
	local b = Instance.new("Part")
	b.Name = "Brace"
	b.Size = Vector3.new(0.24, 0.16, 2.9) * SCALE
	b.CFrame = benchCF * CFrame.new(1.72 * SCALE, z * SCALE, 0)
	b.Color = Color3.fromHex("8a5a2b")
	b.Material = Enum.Material.WoodPlanks
	b.Anchored = true
	b.CanCollide = true
	b.Parent = bench
	ApplyVariant(b, "Frame", "WoodPlanks")
end
table.insert(log, "workspace bench restyled as Starter (+2 braces)")
return table.concat(log, "\n")
