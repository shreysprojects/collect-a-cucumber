--[[
	ras-dev/lobby-models/install_lobby.lua  (2026-09-24) -- RAS - Dev edit DM, execute_luau, files served by
	pets-remake/serve.ps1 -Root ras-dev/lobby-models/out (copy this file into out/ first):
	  local f = loadstring(game:GetService("HttpService"):GetAsync(BASE .. "install_lobby.lua"))()
	  return f(BASE, "Shop")            -- ONE key per eval (LoadAsset + 9 placements)
	  return f(BASE, "Shop", true)      -- dry run: report the placements, change nothing

	Key -> the lobby landmark it replaces on EVERY Maps.StartPlatforms.<Mountain> and on the legacy
	Maps.Attachments.StartPlatform:
	  Shop   -> <platform>.ShopCircle.Shop        (Attachments: Circles.ShopCircle.Shop)
	  Ascend -> <platform>.Ascend                 (HUD CIRCLE_PANELS trigger = this model's bounding box + 4)
	  Gift   -> <platform>.Group                  (Attachments: Circles.GroupCircle.Group; sits on GiftCircle)
	The model name stays the same, so HUD.luau (findCircleModel "Ascend", AscendAttention adornee
	"Ascend_05_Wings") keeps working with no code change.

	Template: InsertService:LoadAsset(out/asset-ids.json[key].id) -> every MeshPart: name = FBX object name,
	the importer's 180-degree yaw undone (CFrame.Angles(0, pi, 0) * CFrame -> the authored frame: Blender
	(x, y, z) = Roblox (x, z, -y), origin = footprint centre on the floor, front = -Z), look re-applied from
	<key>.mesh.json (Color, Material, Transparency, Reflectance, CanCollide, CastShadow), Anchored, CanTouch off.

	Placement per platform: the OLD model's bounding box (oriented like its pivot) -> footprint centre + yaw, standing
	on the platform's Root height (= the floor; the old Group floated 0.6 studs above it), and its
	height / the Frostpeak original's height = the platform's scale (Frostpeak 1, the others ~1.157). The new model
	is ScaleTo'd, PivotTo'd there and stamps LobbyModel / LobbyFrame / LobbyScale / AssetId / BuildHash, so a re-run
	(an updated upload) re-uses the same frame. The originals move to
	ServerStorage.Backups.Lobby_before-rebuild_2026-09-24/<Platform>/<Name> the first time only.
	A billboard adorned to the ring model (ShopCircle "SHOP", GroupCircle "LIKE THE GAME!") is raised by however
	much taller the new model is than the original, so it floats above the new sign instead of over it.
]]
local REF_HEIGHT = { Shop = 11.5, Ascend = 17.6, Gift = 11.2 } -- Frostpeak originals' bounding-box heights (scale 1)
local TARGETS = {
	-- ringLight: the ring's PointLight was red (f6381e) on an orange ring and tinted the stall pink/maroon in the
	-- engine; it takes the ring's own InnerCylinder colour (the original is kept in attribute LobbyOrigColor)
	Shop = { name = "Shop", parents = { { "ShopCircle" }, { "Circles", "ShopCircle" } }, ringLight = true },
	Ascend = { name = "Ascend", parents = { {} } },
	-- turn: extra yaw (degrees) on the mountain lobbies (StartPlatforms only) so the gift faces the spawn pad
	-- instead of the lobby centre (players saw it ~60 degrees off its front from the pad)
	Gift = { name = "Group", parents = { {}, { "Circles", "GroupCircle" } }, turn = -25 },
}
local BACKUP = "Lobby_before-rebuild_2026-09-24"

return function(BASE, key, dryRun)
	local HttpService = game:GetService("HttpService")
	local InsertService = game:GetService("InsertService")
	local ServerStorage = game:GetService("ServerStorage")
	local target = TARGETS[key]
	assert(target, "unknown key " .. tostring(key))
	local maps = ServerStorage.Assets.Storage.Maps
	local report = {}

	-- every platform that carries this landmark -------------------------------------------------------------
	local sites = {}
	local function addSite(label, platform)
		for _, path in ipairs(target.parents) do
			local node = platform
			for _, step in ipairs(path) do
				node = node and node:FindFirstChild(step)
			end
			local model = node and node:FindFirstChild(target.name)
			if model and model:IsA("Model") then
				table.insert(sites, { label = label, parent = node, old = model, root = platform:FindFirstChild("Root"),
					mountain = platform.Parent == maps.StartPlatforms })
				return
			end
		end
		table.insert(report, label .. ": no " .. target.name .. " found")
	end
	for _, platform in ipairs(maps.StartPlatforms:GetChildren()) do
		addSite(platform.Name, platform)
	end
	local legacy = maps:FindFirstChild("Attachments") and maps.Attachments:FindFirstChild("StartPlatform")
	if legacy then
		addSite("Attachments.StartPlatform", legacy)
	end

	-- placement frames, measured BEFORE anything changes ------------------------------------------------------
	local function topOf(model)
		local cf, size = model:GetBoundingBox()
		return cf.Position.Y + size.Y / 2
	end
	for _, site in ipairs(sites) do
		local old = site.old
		if old:GetAttribute("LobbyModel") then
			site.frame = old:GetAttribute("LobbyFrame")
			site.scale = old:GetAttribute("LobbyScale")
			site.origTop = old:GetAttribute("LobbyOrigTop")
		end
		if typeof(site.frame) ~= "CFrame" or type(site.scale) ~= "number" then
			local cf, size = old:GetBoundingBox()
			local bottom = cf.Position - cf.UpVector * (size.Y / 2)
			if site.root and site.root:IsA("BasePart") then
				-- the platform Root sits on the floor (the old Group floated 0.6 studs up); stand on the floor
				bottom = Vector3.new(bottom.X, site.root.Position.Y, bottom.Z)
			end
			site.frame = CFrame.new(bottom) * cf.Rotation
			site.scale = size.Y / REF_HEIGHT[key]
			site.origTop = cf.Position.Y + size.Y / 2
		end
		local _, yaw = site.frame:ToOrientation()
		table.insert(report, ("%s: frame (%.2f, %.2f, %.2f) yaw %.1f scale %.3f"):format(site.label, site.frame.X,
			site.frame.Y, site.frame.Z, math.deg(yaw), site.scale))
	end
	if dryRun then
		return table.concat(report, "\n")
	end

	-- template ------------------------------------------------------------------------------------------------
	local ids = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "asset-ids.json"))
	local entry = ids[key]
	assert(entry, "no asset id for " .. key)
	local meta = HttpService:JSONDecode(HttpService:GetAsync(BASE .. key .. ".mesh.json"))
	local looks = {}
	for _, o in ipairs(meta.objects) do
		looks[o.name] = o
	end
	-- with authored colliders every MeshPart is visual only (a merged look-group spans islands all over the model
	-- and its convex decomposition bridged them into invisible walls); the solid volumes are invisible box Parts
	local useColliders = type(meta.colliders) == "table" and #meta.colliders > 0
	-- RAS - Dev belongs to another group than Group Frenzy, so LoadAsset of the Model refuses ("User is not
	-- authorized to access Asset"). The MESHES inside it are usable anywhere, so tools/fetch_meshids.lua (run in a
	-- place where LoadAsset works, e.g. the New Map, read-only) writes <key>.meshids.json = {parts = [{name,
	-- meshId, size, cf}]} and the MeshParts are rebuilt here with AssetService:CreateMeshPartAsync.
	local asset
	local okIds, meshIds = pcall(function()
		return HttpService:JSONDecode(HttpService:GetAsync(BASE .. key .. ".meshids.json"))
	end)
	if okIds and meshIds and tostring(meshIds.assetId) == tostring(entry.id) then
		local AssetService = game:GetService("AssetService")
		asset = Instance.new("Model")
		local pending, failed = #meshIds.parts, {}
		for _, p in ipairs(meshIds.parts) do
			task.spawn(function()
				local look = looks[p.name]
				local fidelity = (useColliders or (look and look.collide == false)) and Enum.CollisionFidelity.Box
					or Enum.CollisionFidelity.PreciseConvexDecomposition
				local okMp, mp = pcall(AssetService.CreateMeshPartAsync, AssetService, Content.fromUri(p.meshId),
					{ CollisionFidelity = fidelity })
				if okMp and mp then
					mp.Name = p.name
					mp.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
					mp.CFrame = CFrame.new(table.unpack(p.cf))
					mp.Parent = asset
				else
					table.insert(failed, p.name .. ": " .. tostring(mp))
				end
				pending -= 1
			end)
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 60 do
			task.wait(0.05)
		end
		assert(#failed == 0 and pending == 0, "CreateMeshPartAsync failed: " .. table.concat(failed, "; ") .. " pending " .. pending)
	else
		local ok, loaded = pcall(InsertService.LoadAsset, InsertService, tonumber(entry.id))
		assert(ok, "LoadAsset failed: " .. tostring(loaded))
		asset = loaded
	end
	local template = Instance.new("Model")
	template.Name = target.name
	local missing, n = {}, 0
	for _, d in ipairs(asset:GetDescendants()) do
		if d:IsA("MeshPart") then
			local name = d.Name:match("([^%.]+)$") or d.Name
			local look = looks[name]
			d.Name = name
			d.CFrame = CFrame.Angles(0, math.pi, 0) * d.CFrame
			d.Anchored = true
			d.CanTouch = false
			if look then
				d.Color = Color3.fromHex(look.color)
				d.Material = Enum.Material[look.material] or Enum.Material.SmoothPlastic
				d.Transparency = tonumber(look.transparency) or 0
				d.Reflectance = tonumber(look.reflectance) or 0
				d.CanCollide = (not useColliders) and look.collide ~= false
				d.CanQuery = not useColliders -- visual only: no box-shaped ghost hits for raycasts / mouse
				d.CastShadow = look.shadow ~= false
				pcall(function()
					d.CollisionFidelity = (useColliders or look.collide == false) and Enum.CollisionFidelity.Box
						or Enum.CollisionFidelity.PreciseConvexDecomposition
				end)
			else
				table.insert(missing, name)
			end
			d.Parent = template
			n += 1
		end
	end
	asset:Destroy()
	if useColliders then
		for _, c in ipairs(meta.colliders) do
			local part = Instance.new("Part")
			part.Name = "Collider"
			part:SetAttribute("Source", c.name)
			part.Anchored = true
			part.CanCollide = true
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Transparency = 1
			part.Size = Vector3.new(c.size[1], c.size[2], c.size[3])
			part.CFrame = CFrame.new(c.centre[1], c.centre[2], c.centre[3])
			part.Parent = template
		end
	end
	template.WorldPivot = CFrame.new()
	local _, tsize = template:GetBoundingBox()
	table.insert(report, ("template %s: %d meshes from asset %s, %.2f x %.2f x %.2f (expected %s x %s x %s)%s"):format(
		key, n, entry.id, tsize.X, tsize.Y, tsize.Z, tostring(meta.size_studs.width_x), tostring(meta.size_studs.height_z),
		tostring(meta.size_studs.depth_y), #missing > 0 and (" NO LOOK: " .. table.concat(missing, ",")) or ""))
	assert(n == #meta.objects, ("mesh count %d ~= manifest %d"):format(n, #meta.objects))

	-- replace -------------------------------------------------------------------------------------------------
	local backups = ServerStorage:FindFirstChild("Backups")
	if not backups then
		backups = Instance.new("Folder")
		backups.Name = "Backups"
		backups.Parent = ServerStorage
	end
	local root = backups:FindFirstChild(BACKUP)
	if not root then
		root = Instance.new("Folder")
		root.Name = BACKUP
		root.Parent = backups
	end
	for _, site in ipairs(sites) do
		local model = template:Clone()
		model:ScaleTo(site.scale)
		local turn = (site.mountain and target.turn) or 0
		model:PivotTo(site.frame * CFrame.Angles(0, math.rad(turn), 0))
		model:SetAttribute("LobbyTurn", turn)
		if target.ringLight then
			local core = site.parent:FindFirstChild("LightCore")
			local light = core and core:FindFirstChildWhichIsA("PointLight")
			local ring = site.parent:FindFirstChild("InnerCylinder")
			if light and ring then
				if light:GetAttribute("LobbyOrigColor") == nil then
					light:SetAttribute("LobbyOrigColor", light.Color)
				end
				light.Color = ring.Color
			end
		end
		model:SetAttribute("LobbyModel", key)
		model:SetAttribute("LobbyFrame", site.frame)
		model:SetAttribute("LobbyScale", site.scale)
		model:SetAttribute("LobbyOrigTop", site.origTop)
		model:SetAttribute("AssetId", tonumber(entry.id))
		model:SetAttribute("BuildHash", meta.build_hash)
		model:SetAttribute("Source", "ras-dev/lobby-models/models/build_" .. key .. ".py -> Group Frenzy asset " .. entry.id)
		local old = site.old
		if old:IsDescendantOf(root) then
			-- a concurrent / timed-out earlier run already backed this original up: never touch it again
			-- (2026-09-24: a retried install raced its timed-out first run and destroyed the backed-up originals)
		elseif old:GetAttribute("LobbyModel") then
			old:Destroy() -- an earlier upload of ours; the original is already in Backups
		else
			local folder = root:FindFirstChild(site.label)
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = site.label
				folder.Parent = root
			end
			if folder:FindFirstChild(old.Name) then
				old:Destroy()
			else
				old.Parent = folder
			end
		end
		-- exactly one copy per site: drop any other of our copies a racing run left behind
		for _, other in ipairs(site.parent:GetChildren()) do
			if other ~= model and other.Name == target.name and other:GetAttribute("LobbyModel") then
				other:Destroy()
			end
		end
		model.Parent = site.parent
		-- keep a ring billboard above the new model
		local billboard = site.parent:FindFirstChildOfClass("BillboardGui")
		local raised = 0
		if billboard and billboard.Adornee == site.parent then
			local base = billboard:GetAttribute("LobbyBaseOffsetY")
			if base == nil then
				base = billboard.StudsOffset.Y
				billboard:SetAttribute("LobbyBaseOffsetY", base)
			end
			raised = math.max(0, topOf(model) - site.origTop)
			billboard.StudsOffset = Vector3.new(billboard.StudsOffset.X, base + raised, billboard.StudsOffset.Z)
		end
		local cf, size = model:GetBoundingBox()
		table.insert(report, ("%s: placed %s %.1f x %.1f x %.1f at (%.1f, %.1f, %.1f)%s"):format(site.label, model.Name,
			size.X, size.Y, size.Z, cf.X, cf.Y - size.Y / 2, cf.Z, raised > 0 and (" billboard +" .. string.format("%.1f", raised)) or ""))
	end
	template:Destroy()
	return table.concat(report, "\n")
end
