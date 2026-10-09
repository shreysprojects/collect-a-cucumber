--[[
	items/install_items.lua -- ONE execute_luau (edit mode) with pets-remake/serve.ps1 -Port 879x
	-Root new-map-cucumber-game/items/fbx running. Builds ReplicatedStorage.Assets.Items/<Key> for
	every <Key>.parts.json listed in _items.json: each Blender primitive becomes a Part of the same
	shape (Ball / Block / Cylinder), size, colour, material, transparency and pose. Blender is
	Z-up with the item facing +Y; Roblox = (x, z, -y), so a Blender local frame (X, Y, Z) becomes
	the Roblox local frame (X, Z, -Y): CFrame.fromMatrix(C(t), C(x), C(z), -C(y)) with
	C(v) = (v.x, v.z, -v.y), and a local size (sx, sy, sz) becomes (sx, sz, sy). Cylinders were
	recorded with their axis along local X (Roblox Cylinder parts turn about X).
	Idempotent: an existing model of the same name is replaced. Pivot = bottom centre of the bbox,
	so Model:PivotTo(CFrame.new(x, groundY, z)) stands the item on the ground.
	  local f = loadstring(HttpService:GetAsync(BASE .. "install_items.lua"))()
	  return f(BASE)
]]
return function(BASE)
	local HttpService = game:GetService("HttpService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local function fetch(name)
		local ok, body = pcall(HttpService.GetAsync, HttpService, BASE .. name)
		assert(ok, "fetch " .. name .. ": " .. tostring(body))
		return body
	end
	local keys = HttpService:JSONDecode(fetch("_items.json"))
	local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = ReplicatedStorage
	local folder = assets:FindFirstChild("Items") or Instance.new("Folder")
	folder.Name = "Items"
	folder.Parent = assets

	local function C(v) return Vector3.new(v[1], v[3], -v[2]) end
	local SHAPES = {Ball = Enum.PartType.Ball, Block = Enum.PartType.Block, Cylinder = Enum.PartType.Cylinder}

	local report = {}
	for _, key in ipairs(keys) do
		local info = HttpService:JSONDecode(fetch(key .. ".parts.json"))
		local model = Instance.new("Model")
		model.Name = key
		local biggest, biggestVol = nil, -1
		for _, p in ipairs(info.parts) do
			local m = p.matrix
			local t = {m[1][4], m[2][4], m[3][4]}
			local x = {m[1][1], m[2][1], m[3][1]}
			local y = {m[1][2], m[2][2], m[3][2]}
			local z = {m[1][3], m[2][3], m[3][3]}
			local part = Instance.new("Part")
			part.Name = p.name
			part.Shape = SHAPES[p.shape] or Enum.PartType.Block
			part.Size = Vector3.new(p.size[1], p.size[3], p.size[2])
			part.CFrame = CFrame.fromMatrix(C(t), C(x), C(z), -C(y))
			part.Color = Color3.fromHex(p.hex)
			part.Material = Enum.Material[p.material] or Enum.Material.SmoothPlastic
			part.Transparency = tonumber(p.transparency) or 0
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = true
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Parent = model
			local vol = part.Size.X * part.Size.Y * part.Size.Z
			if p.transparency == 0 and vol > biggestVol then biggest, biggestVol = part, vol end
		end
		model.PrimaryPart = nil
		local cf, size = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(cf.Position.X, cf.Position.Y - size.Y * 0.5, cf.Position.Z)
		model:SetAttribute("ItemKey", key)
		model:SetAttribute("Height", size.Y)
		model:SetAttribute("Source", "Blender items/build_items.py (primitive parts)")
		model:SetAttribute("Tris", info.tris or 0)
		local old = folder:FindFirstChild(key)
		if old then old:Destroy() end
		model.Parent = folder
		table.insert(report, ("%s: %d parts, %.2f x %.2f x %.2f, core %s"):format(key, #info.parts, size.X, size.Y, size.Z, biggest and biggest.Name or "?"))
	end
	print("[install_items] " .. table.concat(report, " | "))
	return table.concat(report, "\n")
end
