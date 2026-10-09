--[[
	fun-builds/install/install_mesh.lua  (2026-09-24) -- edit-mode execute_luau, serve.ps1 on models/out:
	  local f = loadstring(game:GetService("HttpService"):GetAsync(BASE .. "install_mesh.lua"))()
	  return f(BASE, {"Sofa", "Fridge"})      -- keep it to ~6 keys per eval (LoadAsset is slow)
	For each key: asset-ids.json gives the uploaded group Model asset (models/export_mesh.py FBX: every scripted part
	kept by name, everything else merged per look). InsertService:LoadAsset -> every MeshPart:
	  * name = the FBX object name (anything up to a last "." stripped),
	  * the importer's 180-degree yaw undone: CFrame.Angles(0, pi, 0) * CFrame -> authored Roblox frame again,
	  * look re-applied from <Key>.mesh.json by name (the FBX carries no colour / material): Color, Material,
	    Transparency, Reflectance, CanCollide, CastShadow; Anchored, CanTouch off; non-colliding parts get
	    CollisionFidelity Box (cheap), colliding ones keep the default hull,
	then the flat Model goes to ServerStorage.Builds/<category>/<Key> with WorldPivot = identity, the Pivot_* and
	parts.json attrs, AssetId / MeshHash / Source. The previous model (the Parts version, or an older upload)
	moves to ServerStorage.__BuildsBackup_2026_09_24/<category> the FIRST time only.
]]
return function(BASE, keys)
	local HttpService = game:GetService("HttpService")
	local InsertService = game:GetService("InsertService")
	local ServerStorage = game:GetService("ServerStorage")
	local builds = ServerStorage:WaitForChild("Builds")
	local ids = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "asset-ids.json"))
	local report = {}
	for _, key in ipairs(keys) do
		local entry = ids[key]
		if not entry then
			table.insert(report, key .. ": no asset id")
			continue
		end
		local meta = HttpService:JSONDecode(HttpService:GetAsync(BASE .. key .. ".mesh.json"))
		local looks = {}
		for _, o in ipairs(meta.objects) do looks[o.name] = o end
		local ok, asset = pcall(InsertService.LoadAsset, InsertService, tonumber(entry.id))
		if not ok then
			table.insert(report, key .. ": LoadAsset failed " .. tostring(asset))
			continue
		end
		local model = Instance.new("Model")
		model.Name = key
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
					d.CanCollide = look.collide ~= false
					d.CastShadow = look.shadow ~= false
					if look.collide == false then
						pcall(function() d.CollisionFidelity = Enum.CollisionFidelity.Box end)
					end
				else
					table.insert(missing, name)
				end
				d.Parent = model
				n += 1
			end
		end
		asset:Destroy()
		model.WorldPivot = CFrame.new()
		for name, value in pairs(meta.attrs or {}) do
			if type(value) == "table" and #value == 3 then value = Vector3.new(value[1], value[2], value[3]) end
			if type(value) ~= "table" then model:SetAttribute(name, value) end
		end
		for name, v in pairs(meta.pivots or {}) do
			model:SetAttribute("Pivot_" .. name, Vector3.new(v[1], v[2], v[3]))
		end
		model:SetAttribute("AssetId", tonumber(entry.id))
		model:SetAttribute("MeshHash", entry.hash)
		model:SetAttribute("Parts", n)
		model:SetAttribute("Source", "fun-builds/models/build_" .. key .. ".py -> export_mesh.py -> group asset " .. entry.id)
		local category = meta.category or "Home"
		local folder = builds:FindFirstChild(category)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = category
			folder.Parent = builds
		end
		local old = folder:FindFirstChild(key)
		if old then
			local backupRoot = ServerStorage:FindFirstChild("__BuildsBackup_2026_09_24")
			if not backupRoot then
				backupRoot = Instance.new("Folder")
				backupRoot.Name = "__BuildsBackup_2026_09_24"
				backupRoot.Parent = ServerStorage
			end
			local bf = backupRoot:FindFirstChild(category) or Instance.new("Folder")
			bf.Name = category
			bf.Parent = backupRoot
			if bf:FindFirstChild(key) then old:Destroy() else old.Parent = bf end
		end
		model.Parent = folder
		local _, size = model:GetBoundingBox()
		table.insert(report, ("%s -> Builds.%s: %d meshes (asset %s)%s, %.1f x %.1f x %.1f (expected %s)"):format(key, category, n, entry.id,
			#missing > 0 and (" NO LOOK: " .. table.concat(missing, ",")) or "", size.X, size.Y, size.Z,
			meta.size_studs and table.concat(meta.size_studs, " x ") or "?"))
	end
	return table.concat(report, "\n")
end
