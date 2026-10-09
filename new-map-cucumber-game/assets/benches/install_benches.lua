--[[
	install_benches.lua  -- template; make-install.ps1 fills __ASSETS__ / __MANIFEST__ and the result
	is run in Studio edit mode through the MCP execute_luau (plugin context).
	For every tier: InsertService:LoadAsset(bench id / barbell id) -> MeshParts, fix scale, align the
	bench on its Anchor part and the barbell on its Bar, rename "<Tier>_<Part>" -> "<Part>", apply
	the manifest colours / materials, and store
		ReplicatedStorage.Assets.BenchTiers.<Theme>  (attrs Tier, Theme, SeatCFrame)
			Visual  (Model, anchored frame parts at the platform)
			Barbell (Model, PrimaryPart Bar, at the rack; local X = bar axis)
	Then the workspace bench (Map.Lobby.Props.BenchPress) gets the Starter tier's parts as its
	visible frame + Barbell, keeping LieSeat; the old stand-in parts are moved to
	ServerStorage.__BenchStandInBackup.
]]
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ASSETS = HttpService:JSONDecode([==[__ASSETS__]==]) -- {Starter = {bench = id, barbell = id}, ...}
local MANIFEST = HttpService:JSONDecode([==[__MANIFEST__]==]) -- build_benches.export_all() output
local ONLY = nil -- set to a theme name to (re)install one tier
local ANCHOR_SIZE = 0.1
local COLLIDE = {Frame = true, Pad = true, Feet = true, Trim = true, Bowls = true}

local bench = workspace.Map.Lobby.Props.BenchPress
local seat = bench.LieSeat
local liveBar = bench.Barbell.PrimaryPart or bench.Barbell:FindFirstChild("Bar")
local RACK_CF = liveBar.CFrame -- bar centre; local X along the bar
local rackOffset = MANIFEST.rack_offset or {1.5, 3.5} -- bar centre from the bench origin (scaled builds: 1.5 * scale, 3.5 * scale)
local ORIGIN = RACK_CF.Position - Vector3.new(rackOffset[1], rackOffset[2], 0) -- Blender origin = floor under the bench pivot
local log = {}
local function say(...) table.insert(log, table.concat({...}, " ")) end

local function Look(entries)
	local map = {}
	for _, e in ipairs(entries) do map[e.name] = e end
	return map
end

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

local function Style(part, entry, theme)
	local short = part.Name:gsub("^" .. theme .. "_", "")
	part.Name = short
	if entry then
		part.Color = Color3.fromHex(entry.hex)
		part.Material = Enum.Material[entry.material]
		part.Transparency = entry.transparency or 0
	end
	part.Anchored = true
	part.CanCollide = COLLIDE[short] == true
	part.CanQuery = COLLIDE[short] == true
	part.CanTouch = false
	part.CastShadow = true
	if part:IsA("MeshPart") then part.DoubleSided = false end
	--.. studded overlay like the rest of the map; the FBX meshes carry box-projected UVs (benchlib)
	local studs = Instance.new("Decal")
	studs.Name = "Studs"
	studs.Texture = "rbxassetid://6372755229"
	studs.Color3 = Color3.new(0, 0, 0)
	studs.Transparency = 0.8
	studs.Face = Enum.NormalId.Front
	studs.Parent = part
	return short
end

local folder = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
folder.Name = "Assets"
folder.Parent = ReplicatedStorage
local tiersFolder = folder:FindFirstChild("BenchTiers") or Instance.new("Folder")
tiersFolder.Name = "BenchTiers"
tiersFolder.Parent = folder

for _, tierInfo in ipairs(MANIFEST.tiers) do
	local theme = tierInfo.name
	if ONLY == nil or ONLY == theme then
		local ids = ASSETS[theme]
		if ids and ids.bench and ids.barbell then
			local old = tiersFolder:FindFirstChild(theme)
			if old then old:Destroy() end
			local tierModel = Instance.new("Model")
			tierModel.Name = theme
			tierModel:SetAttribute("Tier", tierInfo.tier)
			tierModel:SetAttribute("Theme", theme)
			tierModel:SetAttribute("SeatCFrame", seat.CFrame)
			tierModel:SetAttribute("FromAssets", true) -- BenchTierClient prefers these over runtime-built meshes

			--.. bench frame
			local wrapper, parts = LoadParts(ids.bench)
			local look = Look(tierInfo.bench)
			local anchor
			for _, p in ipairs(parts) do
				if p.Name == theme .. "_Anchor" or p.Name == "Anchor" then anchor = p end
			end
			assert(anchor, theme .. ": no Anchor part in the bench asset")
			local scale = ANCHOR_SIZE / anchor.Size.X
			if math.abs(scale - 1) > 0.02 then
				say(theme, "bench scale fix x" .. string.format("%.4f", scale))
				wrapper:ScaleTo(scale)
			end
			local delta = ORIGIN - anchor.Position
			local visual = Instance.new("Model")
			visual.Name = "Visual"
			for _, p in ipairs(parts) do
				if p ~= anchor then
					p.CFrame = CFrame.new(delta) * p.CFrame
					Style(p, look[p.Name], theme)
					p.Parent = visual
				end
			end
			anchor:Destroy()
			wrapper:Destroy()
			visual.Parent = tierModel

			--.. barbell
			local bwrapper, bparts = LoadParts(ids.barbell)
			local blook = Look(tierInfo.barbell)
			local bar
			for _, p in ipairs(bparts) do
				if p.Name == theme .. "_Bar" or p.Name == "Bar" then bar = p end
			end
			assert(bar, theme .. ": no Bar part in the barbell asset")
			local wanted = tierInfo.bar_length
			if wanted then
				local longest = math.max(bar.Size.X, bar.Size.Y, bar.Size.Z)
				local bscale = wanted / longest
				if math.abs(bscale - 1) > 0.02 then
					say(theme, "barbell scale fix x" .. string.format("%.4f", bscale))
					bwrapper:ScaleTo(bscale)
				end
			end
			local axis = bar.CFrame.RightVector
			if bar.Size.Z > bar.Size.X and bar.Size.Z > bar.Size.Y then
				say(theme, "WARNING: bar mesh is longest along Z, not X")
			end
			local barCF = bar.CFrame
			local barbell = Instance.new("Model")
			barbell.Name = "Barbell"
			for _, p in ipairs(bparts) do
				p.CFrame = RACK_CF * (barCF:Inverse() * p.CFrame)
				Style(p, blook[p.Name], theme)
				p.CanCollide = false
				p.CanQuery = false
				p.Parent = barbell
			end
			barbell.PrimaryPart = bar
			bwrapper:Destroy()
			barbell.Parent = tierModel
			tierModel.Parent = tiersFolder
			local tris = 0
			for _, e in ipairs(tierInfo.bench) do tris += e.tris end
			for _, e in ipairs(tierInfo.barbell) do tris += e.tris end
			say(theme, "installed:", #visual:GetChildren(), "frame parts,", #barbell:GetChildren(), "barbell parts,", tris, "tris")
		else
			say(theme, "skipped (no asset ids)")
		end
	end
end

--.. put the Starter tier on the workspace bench (keep LieSeat; back up the stand-in parts)
local starter = tiersFolder:FindFirstChild("Starter")
if starter and (ONLY == nil or ONLY == "Starter") then
	local backup = ServerStorage:FindFirstChild("__BenchStandInBackup")
	if not backup then
		backup = Instance.new("Model")
		backup.Name = "__BenchStandInBackup"
		backup.Parent = ServerStorage
	end
	for _, c in ipairs(bench:GetChildren()) do
		if c ~= seat then c.Parent = backup end
	end
	for _, p in ipairs(starter.Visual:GetChildren()) do
		p:Clone().Parent = bench
	end
	local newBarbell = starter.Barbell:Clone()
	newBarbell.Parent = bench
	bench:SetAttribute("StandIn", nil)
	bench:SetAttribute("Note", "Starter tier meshes (assets/benches); other tiers in ReplicatedStorage.Assets.BenchTiers are shown per player by BenchTierClient")
	say("workspace bench now uses the Starter tier; old parts in ServerStorage.__BenchStandInBackup")
end
return table.concat(log, "\n")
