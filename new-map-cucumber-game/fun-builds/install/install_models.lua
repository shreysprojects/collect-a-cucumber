--[[
	fun-builds/install/install_models.lua  (2026-09-24) -- edit-mode execute_luau, with
	pets-remake/serve.ps1 -Port 8792 -Root fun-builds/models/out running:
	  local f = loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8792/install_models.lua"))()
	  return f("http://127.0.0.1:8792/", {"Sofa", "Fridge"}, {Backup = true})
	Each <Key>.parts.json (primlib.py) becomes ServerStorage.Builds/<category>/<Key>: one Part per primitive
	(Block / Ball / Cylinder = Part.Shape, Wedge = WedgePart, CornerWedge = CornerWedgePart, Ellipsoid = a
	Block with a SpecialMesh Sphere) at its authored CFrame (the build's floor centre at the origin, front -Z),
	WorldPivot = identity, attributes = parts.json attrs + Pivot_<name> Vector3s + Tris/Parts/Source.
	An existing model of that name is moved to ServerStorage.__BuildsBackup_2026_09_24/<category> first
	(once - an older backup is never overwritten) when opts.Backup is true, else replaced.
]]
return function(BASE, keys, opts)
	opts = opts or {}
	local HttpService = game:GetService("HttpService")
	local ServerStorage = game:GetService("ServerStorage")
	local builds = ServerStorage:WaitForChild("Builds")
	local backupRoot = ServerStorage:FindFirstChild("__BuildsBackup_2026_09_24")
	local report = {}
	for _, key in ipairs(keys) do
		local ok, body = pcall(HttpService.GetAsync, HttpService, BASE .. key .. ".parts.json")
		if not ok then
			table.insert(report, key .. ": FETCH FAILED " .. tostring(body))
			continue
		end
		local info = HttpService:JSONDecode(body)
		local category = opts.Category or info.category or "Home"
		local folder = builds:FindFirstChild(category)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = category
			folder.Parent = builds
		end
		local model = Instance.new("Model")
		model.Name = info.key or key
		local counts = {}
		for _, p in ipairs(info.parts) do
			local part
			if p.shape == "Wedge" then
				part = Instance.new("WedgePart")
			elseif p.shape == "CornerWedge" then
				part = Instance.new("CornerWedgePart")
			else
				part = Instance.new("Part")
				if p.shape == "Ball" then part.Shape = Enum.PartType.Ball
				elseif p.shape == "Cylinder" then part.Shape = Enum.PartType.Cylinder
				else part.Shape = Enum.PartType.Block end
			end
			part.Name = p.name
			part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
			local c = p.cf
			part.CFrame = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
			part.Color = Color3.fromHex(p.color)
			part.Material = Enum.Material[p.material] or Enum.Material.SmoothPlastic
			part.Transparency = tonumber(p.transparency) or 0
			part.Reflectance = tonumber(p.reflectance) or 0
			part.Anchored = true
			part.CanCollide = p.collide ~= false
			part.CanTouch = false
			part.CastShadow = p.shadow ~= false
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			if p.shape == "Ellipsoid" then
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = part
			end
			part.Parent = model
			counts[p.shape] = (counts[p.shape] or 0) + 1
		end
		model.WorldPivot = CFrame.new()
		for name, value in pairs(info.attrs or {}) do
			if type(value) == "table" and #value == 3 then value = Vector3.new(value[1], value[2], value[3]) end
			model:SetAttribute(name, value)
		end
		for name, v in pairs(info.pivots or {}) do
			model:SetAttribute("Pivot_" .. name, Vector3.new(v[1], v[2], v[3]))
		end
		model:SetAttribute("Parts", #info.parts)
		model:SetAttribute("Source", "fun-builds/models/build_" .. key .. ".py (primlib, Roblox parts)")
		local old = folder:FindFirstChild(model.Name)
		if old then
			if opts.Backup then
				if not backupRoot then
					backupRoot = Instance.new("Folder")
					backupRoot.Name = "__BuildsBackup_2026_09_24"
					backupRoot.Parent = ServerStorage
				end
				local bf = backupRoot:FindFirstChild(category) or Instance.new("Folder")
				bf.Name = category
				bf.Parent = backupRoot
				if bf:FindFirstChild(old.Name) then old:Destroy() else old.Parent = bf end
			else
				old:Destroy()
			end
		end
		model.Parent = folder
		local _, size = model:GetBoundingBox()
		local shapes = {}
		for s, n in pairs(counts) do table.insert(shapes, s .. "=" .. n) end
		table.insert(report, ("%s -> Builds.%s: %d parts (%s), %.1f x %.1f x %.1f"):format(model.Name, category, #info.parts, table.concat(shapes, " "), size.X, size.Y, size.Z))
	end
	return table.concat(report, "\n")
end
