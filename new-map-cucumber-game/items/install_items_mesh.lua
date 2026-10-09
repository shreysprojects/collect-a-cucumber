--[[
	items/install_items_mesh.lua -- execute_luau (edit mode) with pets-remake/serve.ps1 -Port 879x -Root items/fbx
	running (this file copied into fbx/). Replaces the primitive-Part item models in ReplicatedStorage.Assets.Items
	with the uploaded Blender MESHES: InsertService:LoadAsset(group asset id from asset-ids.json), strip the
	"<Key>." prefix the FBX carries on part names, undo the importer's 180-degree yaw, re-apply colour / material /
	transparency from <Key>.parts.json by part name (the FBX loses them), anchor + no collide, pivot at the bottom
	centre. The Part version moves to ReplicatedStorage.Assets.__ItemsPartsBackup_2026_09_23 (kept as a fallback).
	Idempotent per key. Call with a list of keys (LoadAsset is slow: at most ~5 per call).
	  local f = loadstring(HttpService:GetAsync(BASE .. "install_items_mesh.lua"))()
	  return f(BASE, {"SpeedPotion", "StrengthPotion"})
]]
return function(BASE, only)
	local HttpService = game:GetService("HttpService")
	local InsertService = game:GetService("InsertService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local function fetch(name)
		local ok, body = pcall(HttpService.GetAsync, HttpService, BASE .. name)
		assert(ok, "fetch " .. name .. ": " .. tostring(body))
		return body
	end
	local ids = HttpService:JSONDecode(fetch("asset-ids.json"))
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local folder = assets:WaitForChild("Items")
	local backup = assets:FindFirstChild("__ItemsPartsBackup_2026_09_23")
	if not backup then
		backup = Instance.new("Folder")
		backup.Name = "__ItemsPartsBackup_2026_09_23"
		backup.Parent = assets
	end
	local report = {}
	for _, key in ipairs(only) do
		local id = tonumber(ids[key])
		if not id then
			table.insert(report, key .. ": NO ASSET ID")
			continue
		end
		local info = HttpService:JSONDecode(fetch(key .. ".parts.json"))
		local byName = {}
		for _, p in ipairs(info.parts) do byName[p.name] = p end
		local ok, container = pcall(InsertService.LoadAsset, InsertService, id)
		if not (ok and container) then
			table.insert(report, ("%s: LoadAsset %d failed: %s"):format(key, id, tostring(container)))
			continue
		end
		local model = Instance.new("Model")
		model.Name = key
		local parts, missing = 0, {}
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("BasePart") then
				local name = d.Name:gsub("^" .. key .. "%.", "")
				d.Name = name
				d.CFrame = CFrame.Angles(0, math.pi, 0) * d.CFrame -- the importer's yaw
				local p = byName[name]
				if p then
					d.Color = Color3.fromHex(p.hex)
					d.Material = Enum.Material[p.material] or Enum.Material.SmoothPlastic
					d.Transparency = tonumber(p.transparency) or 0
				else
					table.insert(missing, name)
				end
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				d.CastShadow = true
				d.Parent = model
				parts += 1
			end
		end
		container:Destroy()
		if parts == 0 then
			model:Destroy()
			table.insert(report, key .. ": asset had no parts")
			continue
		end
		model.PrimaryPart = nil
		local cf, size = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(cf.Position.X, cf.Position.Y - size.Y * 0.5, cf.Position.Z)
		model:SetAttribute("ItemKey", key)
		model:SetAttribute("Height", size.Y)
		model:SetAttribute("AssetId", id)
		model:SetAttribute("Source", "Blender items/build_items.py (FBX mesh asset)")
		model:SetAttribute("Tris", info.tris or 0)
		local old = folder:FindFirstChild(key)
		if old then
			if old:GetAttribute("AssetId") == nil then -- the Part version: keep it as the fallback
				local prev = backup:FindFirstChild(key)
				if prev then prev:Destroy() end
				old.Parent = backup
			else
				old:Destroy()
			end
		end
		model.Parent = folder
		table.insert(report, ("%s: asset %d, %d mesh parts, %.2f x %.2f x %.2f%s"):format(key, id, parts, size.X, size.Y, size.Z, #missing > 0 and (" MISSING look for " .. table.concat(missing, ",")) or ""))
	end
	print("[install_items_mesh] " .. table.concat(report, " | "))
	return table.concat(report, "\n")
end
