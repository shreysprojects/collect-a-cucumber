--[[
	install_tiers_78.lua  (2026-09-06)  -- run in Studio edit mode through the MCP execute_luau (plugin context).
	Installs the Celestial (tier 7) and Void Emperor (tier 8) bench tiers from the Open Cloud Model assets
	(asset-ids.json; uploaded from Celestial_*.fbx / VoidEmperor_*.fbx) as
		ReplicatedStorage.Assets.BenchTiers.<Theme>  (attrs Tier, Theme, FromAssets=true, SeatCFrame)
			Visual  (Model: anchored MeshParts placed in bench space around the template bench's rack)
			Barbell (Model: PrimaryPart Bar at the rack; local X = bar axis)
	BenchTierClient prefers FromAssets models, moves the Visual bar-onto-bar per plot bench and welds
	the barbell copies to the live Bar, so only the Visual <-> Barbell relationship matters here.
	Roblox's FBX import yaws the Blender build 180 deg about Y (bench x flips), so every loaded part is
	rotated back about the Anchor (Blender origin) before it is placed with BenchScale.BenchCFrame(rack).
	Materials follow the map's MaterialService: Plastic + variant "Studs" (frame, pad, trim, wings) /
	"Weld" (bar, collars, plates, rims); Neon parts (Glow, Float1..6) keep their glow.
]]
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BenchScale = require(ReplicatedStorage.Modules.BenchScale:Clone()) -- clone: bust the eval VM's require cache

local ASSETS = {
	Celestial = {tier = 7, bench = 84161418385358, barbell = 128607903317104,
		hex = {Frame = "f3efe6", Pad = "f7f7f9", Trim = "e6b422", Wings = "e6b422", Glow = "fff1b8",
			Bar = "c9ccd3", Plates = "f2eee6", Rims = "e6b422", Collars = "e6b422"}},
	VoidEmperor = {tier = 8, bench = 139713291746130, barbell = 111718218271304,
		hex = {Frame = "1a171f", Pad = "b0161e", Trim = "d4a11e", Glow = "ff2233", Crystals = "2a0f1c", Float = "9a1426",
			Bar = "b4b7c0", Plates = "1b1520", Collars = "d4a11e"}},
}
local NEON = {Glow = true, Float = true}
local FLIP = CFrame.Angles(0, math.pi, 0) -- undo the FBX import yaw (about the Anchor at the origin)

local bench = workspace.Map.Lobby.Props.BenchPress
local seat = bench:FindFirstChild("LieSeat")
local barbellModel = bench:FindFirstChild("Barbell")
local liveBar = barbellModel and (barbellModel.PrimaryPart or barbellModel:FindFirstChild("Bar"))
assert(seat and liveBar, "template bench needs LieSeat + Barbell.Bar")
local rack = barbellModel:GetAttribute("RackCFrame")
if typeof(rack) ~= "CFrame" then rack = liveBar.CFrame end
local benchCF = BenchScale.BenchCFrame(rack)
local log = {}
local function say(...) table.insert(log, table.concat({...}, " ")) end

local function LoadParts(assetId)
	local ok, wrapper = pcall(function() return InsertService:LoadAsset(assetId) end)
	assert(ok and wrapper, "LoadAsset " .. tostring(assetId) .. " failed: " .. tostring(wrapper))
	local parts = {}
	for _, d in ipairs(wrapper:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	assert(#parts > 0, "asset " .. tostring(assetId) .. " has no parts")
	return wrapper, parts
end

local function Stem(name, theme)
	local short = name:gsub("^" .. theme .. "_", ""):gsub("%.%d+$", "") -- "Celestial_Glow.001" -> "Glow"
	return short, (short:match("^(Float)%d+$") or short)                 -- "Float3" -> group "Float"
end

local function Style(part, theme, info, group, variant)
	local short, stem = Stem(part.Name, theme)
	part.Name = short
	local hex = info.hex[stem] or "ffffff"
	part.Color = Color3.fromHex(hex)
	if NEON[stem] then
		part.Material = Enum.Material.Neon
		part.MaterialVariant = ""
	else
		part.Material = Enum.Material.Plastic
		part.MaterialVariant = variant -- MaterialService "Studs" / "Weld" (BaseMaterial Plastic)
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	if part:IsA("MeshPart") then part.DoubleSided = false end
	return short
end

local folder = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
folder.Name = "Assets"
folder.Parent = ReplicatedStorage
local tiersFolder = folder:FindFirstChild("BenchTiers") or Instance.new("Folder")
tiersFolder.Name = "BenchTiers"
tiersFolder.Parent = folder

for theme, info in pairs(ASSETS) do
	local old = tiersFolder:FindFirstChild(theme)
	if old then old:Destroy() end
	local tierModel = Instance.new("Model")
	tierModel.Name = theme
	tierModel:SetAttribute("Tier", info.tier)
	tierModel:SetAttribute("Theme", theme)
	tierModel:SetAttribute("SeatCFrame", seat.CFrame)
	tierModel:SetAttribute("FromAssets", true)
	tierModel:SetAttribute("AssetIds", info.bench .. "," .. info.barbell)

	--.. bench frame: rotate back about the Anchor, then into bench space around the rack
	local wrapper, parts = LoadParts(info.bench)
	local anchor
	for _, p in ipairs(parts) do
		if p.Name == theme .. "_Anchor" or p.Name == "Anchor" then anchor = p end
	end
	assert(anchor, theme .. ": no Anchor part in the bench asset")
	local scale = 0.1 / anchor.Size.X
	if math.abs(scale - 1) > 0.02 then
		say(theme, "bench scale fix x" .. string.format("%.4f", scale))
		wrapper:ScaleTo(scale)
	end
	local anchorCF = anchor.CFrame
	local visual = Instance.new("Model")
	visual.Name = "Visual"
	local tris = 0
	for _, p in ipairs(parts) do
		if p ~= anchor then
			local localCF = FLIP * (anchorCF:Inverse() * p.CFrame) -- bench space: x toward the rack, y up
			p.CFrame = benchCF * localCF
			Style(p, theme, info, "Bench", "Studs")
			p.Parent = visual
		end
	end
	anchor:Destroy()
	wrapper:Destroy()
	visual.Parent = tierModel

	--.. barbell: bar centre onto the rack, local X = bar axis
	local bwrapper, bparts = LoadParts(info.barbell)
	local bar
	for _, p in ipairs(bparts) do
		if p.Name == theme .. "_Bar" or p.Name == "Bar" then bar = p end
	end
	assert(bar, theme .. ": no Bar part in the barbell asset")
	if bar.Size.X < bar.Size.Y or bar.Size.X < bar.Size.Z then
		say(theme, "WARNING: bar mesh is not longest along X", tostring(bar.Size))
	end
	local barCF = bar.CFrame
	local barbell = Instance.new("Model")
	barbell.Name = "Barbell"
	for _, p in ipairs(bparts) do
		p.CFrame = rack * (barCF:Inverse() * p.CFrame)
		Style(p, theme, info, "Barbell", "Weld")
		p.Parent = barbell
	end
	barbell.PrimaryPart = bar
	bwrapper:Destroy()
	barbell.Parent = tierModel
	tierModel.Parent = tiersFolder

	--.. report: bench-space extents of the visual (x along the bench, z across) + bar length
	local minX, maxX, minZ, maxZ, maxY = math.huge, -math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(visual:GetChildren()) do
		local o = benchCF:ToObjectSpace(p.CFrame)
		minX = math.min(minX, o.X - p.Size.X / 2); maxX = math.max(maxX, o.X + p.Size.X / 2)
		minZ = math.min(minZ, o.Z - p.Size.Z / 2); maxZ = math.max(maxZ, o.Z + p.Size.Z / 2)
		maxY = math.max(maxY, o.Y + p.Size.Y / 2)
	end
	say(theme, ("installed: %d frame parts, %d barbell parts; bench x %.2f..%.2f z %.2f..%.2f top %.2f; bar %.2f long"):format(
		#visual:GetChildren(), #barbell:GetChildren(), minX, maxX, minZ, maxZ, maxY, bar.Size.X))
end

--.. compare with the Cosmic fallback (same footprint expected)
local cosmic = tiersFolder:FindFirstChild("Cosmic")
if cosmic and cosmic:FindFirstChild("Visual") and cosmic:FindFirstChild("Barbell") then
	local cbar = cosmic.Barbell.PrimaryPart or cosmic.Barbell:FindFirstChild("Bar")
	local ccf = BenchScale.BenchCFrame(cbar.CFrame)
	local minX, maxX, minZ, maxZ, maxY = math.huge, -math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(cosmic.Visual:GetChildren()) do
		local o = ccf:ToObjectSpace(p.CFrame)
		minX = math.min(minX, o.X - p.Size.X / 2); maxX = math.max(maxX, o.X + p.Size.X / 2)
		minZ = math.min(minZ, o.Z - p.Size.Z / 2); maxZ = math.max(maxZ, o.Z + p.Size.Z / 2)
		maxY = math.max(maxY, o.Y + p.Size.Y / 2)
	end
	say(("Cosmic fallback: bench x %.2f..%.2f z %.2f..%.2f top %.2f; bar %.2f long"):format(minX, maxX, minZ, maxZ, maxY, cbar.Size.X))
end
print(table.concat(log, "\n"))
