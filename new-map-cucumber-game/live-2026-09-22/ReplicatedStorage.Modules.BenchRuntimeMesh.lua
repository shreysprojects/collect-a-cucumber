--[[
	BenchRuntimeMesh  (ModuleScript, ReplicatedStorage.Modules)
	Builds the themed bench-press tiers (assets/benches, Blender) at run time from geometry data,
	because the Open Cloud key has no Assets Write permission and Studio's CreateAssetAsync is still
	gated, so the meshes cannot be uploaded as assets yet.

	Data:  ReplicatedStorage.Assets.BenchMeshData.<Theme>  ModuleScript (benchlib.export_luau)
	         Theme, Tier, BarLength, Scale, RackOffset,
	         Parts[<Part>] = {Group = "Bench"|"Barbell", Color, Material, Transparency, Size, Offset, V, T}
	       Bench parts: Offset from the bench origin (floor under the bench pivot, bench-space axes:
	       x = along the bench toward the rack, y = up, z = across). Barbell parts: Offset from the
	       bar centre, bar along local X (the axis BenchServer / BarbellClient use).

	BuildTier(theme, rackCF) -> Model <Theme> {attrs Tier, Theme; Visual (anchored MeshParts),
	Barbell (Model, PrimaryPart Bar)} in world space around the rack, or nil when the EditableMesh
	API is off. Each part's mesh is built once per client (EditableMesh -> CreateMeshPartAsync) and
	cloned (clones keep the in-memory mesh). BenchTierClient shows the result per bench.
	Look: the frame / pad / feet / bowls use the map's "Studs" MaterialVariant and the barbell parts
	the "Weld" variant (MaterialService, Plastic based; mapped through the meshes' box-projected UVs),
	glowing parts stay Neon. Parts named Float<n> (Cosmic's drifting crystals) are animated by the
	client.

	REQUIRES Game Settings > Security > "Allow Mesh & Image APIs". Without it IsAvailable() is
	false (first EditableMesh call throws "EditableMesh is not accessible") and the client keeps the
	part-built bench in the workspace, so nothing is ever invisible.

	UPGRADE PATH: once the FBX files are uploaded as assets (assets/benches/upload-all.ps1 with a
	key that has Assets Write, then install_benches.lua), the installer puts real tier models with
	the attribute FromAssets=true in ReplicatedStorage.Assets.BenchTiers and the client prefers those.
]]
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BenchRuntimeMesh = {}
BenchRuntimeMesh.THEMES = {"Starter", "Iron", "Gold", "Frost", "Inferno", "Cosmic", "Celestial", "VoidEmperor"} -- index = tier (7-8 ship as asset models only: Assets.BenchTiers FromAssets)
--.. MaterialService variants (the same studs / weld looks the rest of the map uses); by part group,
--.. numbered parts (Float1...) look up their stem. Neon parts keep their glow.
BenchRuntimeMesh.VARIANTS = {Frame = "Studs", Pad = "Studs", Feet = "Studs", Trim = "Studs", Bowls = "Studs",
	Bar = "Weld", Collars = "Weld", Plates = "Weld", Rims = "Weld"}
BenchRuntimeMesh.UV_TILE = 2 -- studs per UV tile in the box projection (matches benchlib.STUDS_TILE)

local available = nil -- nil = not probed yet
local sources = {} -- [theme .. "/" .. part] = MeshPart (built once)
local pending = {} -- [key] = {threads waiting}

local function DataFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("BenchMeshData")
end

function BenchRuntimeMesh.ThemeForTier(tier)
	return BenchRuntimeMesh.THEMES[math.clamp(math.floor(tier), 1, #BenchRuntimeMesh.THEMES)]
end

function BenchRuntimeMesh.GetData(theme)
	local folder = DataFolder()
	local module = folder and folder:FindFirstChild(theme)
	if not module then return nil end
	local ok, data = pcall(require, module)
	return ok and data or nil
end

--.. the EditableMesh API is gated by the experience's "Allow Mesh & Image APIs" setting:
--.. CreateEditableMesh() returns an object but the first method call throws. Probe once.
function BenchRuntimeMesh.IsAvailable()
	if available ~= nil then return available end
	local ok, err = pcall(function()
		local em = AssetService:CreateEditableMesh()
		em:AddVertex(Vector3.zero)
		em:Destroy()
	end)
	available = ok
	if not ok then
		warn("[BenchRuntimeMesh] EditableMesh unavailable (" .. tostring(err) .. ") -- keeping the part-built bench. Enable Game Settings > Security > Allow Mesh & Image APIs (and republish) for the themed benches.")
	end
	return available
end

--.. the map's studs / weld look for a part group (nil = keep the data's material)
function BenchRuntimeMesh.VariantFor(partName, materialName)
	if materialName == "Neon" then return nil end
	local stem = partName:gsub("%d+$", "")
	return BenchRuntimeMesh.VARIANTS[stem]
end

local function BuildSource(theme, partName, def)
	local em = AssetService:CreateEditableMesh()
	local V, T = def.V, def.T
	local vids = table.create(#V // 3)
	for i = 1, #V, 3 do
		vids[#vids + 1] = em:AddVertex(Vector3.new(V[i], V[i + 1], V[i + 2]))
	end
	local uvScale = 1 / BenchRuntimeMesh.UV_TILE
	for i = 1, #T, 3 do
		local a, b, c = vids[T[i]], vids[T[i + 1]], vids[T[i + 2]]
		local p1, p2, p3 = em:GetPosition(a), em:GetPosition(b), em:GetPosition(c)
		local n = (p2 - p1):Cross(p3 - p1)
		if n.Magnitude > 1e-9 then
			local nid = em:AddNormal(n.Unit) -- flat shading, one normal per face
			local f = em:AddTriangle(a, b, c)
			em:SetFaceNormals(f, {nid, nid, nid})
			--.. box projection along the face's dominant axis, so tiling materials read in studs on every face
			local ax, ay, az = math.abs(n.X), math.abs(n.Y), math.abs(n.Z)
			local function uvOf(p)
				if ax >= ay and ax >= az then return Vector2.new(p.Z, p.Y) * uvScale end
				if ay >= az then return Vector2.new(p.X, p.Z) * uvScale end
				return Vector2.new(p.X, p.Y) * uvScale
			end
			em:SetFaceUVs(f, {em:AddUV(uvOf(p1)), em:AddUV(uvOf(p2)), em:AddUV(uvOf(p3))})
		end
	end
	local src = AssetService:CreateMeshPartAsync(Content.fromObject(em))
	src.Name = partName
	src.Anchored = true
	src.CanCollide = false
	src.CanQuery = false
	src.CanTouch = false
	src.CastShadow = true
	src.Color = Color3.fromHex(def.Color or "ffffff")
	local variant = BenchRuntimeMesh.VariantFor(partName, def.Material)
	if variant then
		src.Material = Enum.Material.Plastic
		src.MaterialVariant = variant
	else
		src.Material = Enum.Material[def.Material] or Enum.Material.SmoothPlastic
	end
	src.Transparency = def.Transparency or 0
	return src
end

--.. one build per theme/part; concurrent callers wait for the first build
local function GetSource(theme, partName, def)
	local key = theme .. "/" .. partName
	local existing = sources[key]
	if existing then return existing end
	if pending[key] then
		table.insert(pending[key], coroutine.running())
		return coroutine.yield()
	end
	pending[key] = {}
	local ok, src = pcall(BuildSource, theme, partName, def)
	if not ok then
		warn("[BenchRuntimeMesh] build failed for", key, src)
		src = nil
	end
	sources[key] = src
	local waiters = pending[key]
	pending[key] = nil
	for _, th in ipairs(waiters) do task.spawn(th, src) end
	return src
end

--.. bench origin (floor under the pivot) from where the bar rests: the data says how far the bar
--.. centre is from the origin (RackOffset = along the bench, up) and the Bar's local X runs across
--.. the bench, a 90 degree yaw from bench space
function BenchRuntimeMesh.BenchCFrame(rackCF, data)
	local off = data and data.RackOffset or {1.5, 3.5}
	return rackCF * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new(-off[1], -off[2], 0)
end

--.. builds the tier in world space around the rack; yields while meshes are created (first time per theme)
function BenchRuntimeMesh.BuildTier(theme, rackCF)
	if not BenchRuntimeMesh.IsAvailable() then return nil end
	local data = BenchRuntimeMesh.GetData(theme)
	if not data then
		warn("[BenchRuntimeMesh] no mesh data for", theme)
		return nil
	end
	local benchCF = BenchRuntimeMesh.BenchCFrame(rackCF, data)
	local model = Instance.new("Model")
	model.Name = theme
	model:SetAttribute("Theme", theme)
	model:SetAttribute("Tier", data.Tier)
	model:SetAttribute("Runtime", true)
	local visual = Instance.new("Model")
	visual.Name = "Visual"
	local barbell = Instance.new("Model")
	barbell.Name = "Barbell"
	local names = {}
	for name in pairs(data.Parts) do table.insert(names, name) end
	table.sort(names)
	local missing = 0
	for _, name in ipairs(names) do
		local def = data.Parts[name]
		local src = GetSource(theme, name, def)
		if not src then
			missing += 1
		else
			local part = src:Clone()
			local offset = CFrame.new(def.Offset[1], def.Offset[2], def.Offset[3])
			if def.Group == "Barbell" then
				part.CFrame = rackCF * offset
				part.Parent = barbell
				if name == "Bar" then barbell.PrimaryPart = part end
			else
				part.CFrame = benchCF * offset
				part.Parent = visual
			end
		end
	end
	--.. all or nothing (2026-09-12, user: "upgrading the bench made its parts disappear"): the client's
	--.. EditableMesh memory budget can run out halfway through a theme ("Failed to create empty
	--.. EditableMesh ... memory budget limits"), and a bench with one slab and a bar is worse than
	--.. no bench. A short theme is dropped, and the runtime path is switched off for this session
	--.. so BenchTierClient falls back to the part-built tier models (Assets.BenchTiers, Fallback=true).
	if missing > 0 or not barbell.PrimaryPart then
		warn(("[BenchRuntimeMesh] %s: %d of %d meshes could not be built (EditableMesh budget?) - runtime benches off for this session, the part-built tiers are shown"):format(theme, missing, #names))
		available = false
		model:Destroy()
		return nil
	end
	visual.Parent = model
	barbell.Parent = model
	return model
end

return BenchRuntimeMesh
