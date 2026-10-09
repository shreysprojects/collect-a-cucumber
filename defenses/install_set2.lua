--[[
	defenses/install_set2.lua -- ONE execute_luau (edit mode) with pets-remake/serve.ps1 -Port 8767
	-Root defenses running. Installs the 2026-09-16 defence set (Mortar, TeslaCoil, FreezeTower,
	Minigun, LaserGate) into ServerStorage.Builds.Defences: InsertService:LoadAsset(each group asset),
	strip the "<Collection>." prefix from part names, undo the FBX importer's 180-degree yaw, re-apply
	colour / material / transparency from fbx/<Collection>.manifest.json (the FBX loses them), anchor +
	collide (beams / neon glow parts do NOT collide), pivot at the authored origin, attributes Cost /
	AssetId / PropSet / Tris / Notes / Pivot_<Name> (converted to Roblox space) / State_<Name>.
	Inputs on the server: fbx/asset-ids-set2.json, fbx/<Collection>.manifest.json. Idempotent (an
	existing model of the same name is replaced; its Cost attribute is kept if it has one).
]]
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")
local BASE = "http://127.0.0.1:8767/fbx/"
local function fetch(name)
	local ok, body = pcall(HttpService.GetAsync, HttpService, BASE .. name)
	assert(ok, "fetch " .. name .. ": " .. tostring(body))
	return body
end
local ids = HttpService:JSONDecode(fetch("asset-ids-set2.json"))
local folder = ServerStorage:WaitForChild("Builds"):WaitForChild("Defences")
local COST = {Mortar = 3500, TeslaCoil = 4000, FreezeTower = 3000, Minigun = 5000, LaserGate = 2000}
--.. parts that must never collide (zombies walk through the laser beams; glow parts are decoration)
local NO_COLLIDE = {LaserGate = {Beam1 = true, Beam2 = true, Beam3 = true, Beam4 = true}}
local function rbx(v) -- Blender (x, y, z) -> Roblox (x, z, -y) after the yaw fix
	return Vector3.new(v[1], v[3], -v[2])
end

local report = {}
for coll, id in pairs(ids) do
	id = tonumber(id)
	assert(id, "no asset id for " .. coll)
	local man = HttpService:JSONDecode(fetch(coll .. ".manifest.json"))
	local byPart = {}
	for _, entry in ipairs(man.parts) do
		byPart[entry.name] = entry
		byPart[entry.name:gsub("^" .. coll .. "%.", "")] = entry
	end
	local ok, container = pcall(InsertService.LoadAsset, InsertService, id)
	assert(ok and container, "LoadAsset " .. tostring(id) .. " failed: " .. tostring(container))
	local old = folder:FindFirstChild(coll)
	local cost = (old and tonumber(old:GetAttribute("Cost"))) or COST[coll] or 1000
	local model = Instance.new("Model")
	model.Name = coll
	local parts, missing = 0, {}
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") then
			local name = d.Name:gsub("^" .. coll .. "%.", "")
			local entry = byPart[name]
			d.Name = name
			d.CFrame = CFrame.Angles(0, math.pi, 0) * d.CFrame -- the importer's yaw
			if entry then
				d.Color = Color3.fromHex(entry.hex)
				d.Material = Enum.Material[entry.material] or Enum.Material.SmoothPlastic
				d.Transparency = entry.transparency or 0
			else
				table.insert(missing, name)
			end
			d.Anchored = true
			d.CanCollide = not (NO_COLLIDE[coll] and NO_COLLIDE[coll][name])
			d.CanTouch = false
			d.TopSurface = Enum.SurfaceType.Smooth
			d.BottomSurface = Enum.SurfaceType.Smooth
			d.Parent = model
			parts += 1
		end
	end
	container:Destroy()
	model.PrimaryPart = nil
	model.WorldPivot = CFrame.new()
	local cf, size = model:GetBoundingBox()
	model:SetAttribute("Cost", cost)
	model:SetAttribute("AssetId", id)
	model:SetAttribute("PropSet", "defence2")
	model:SetAttribute("Tris", man.tris or 0)
	model:SetAttribute("Notes", (man.notes or ""):sub(1, 900))
	for name, v in pairs(man.pivots or {}) do
		if type(v) == "table" and #v == 3 then model:SetAttribute("Pivot_" .. name, rbx(v)) end
	end
	for name, v in pairs(man.states or {}) do
		if type(v) == "number" then model:SetAttribute("State_" .. name, v) end
	end
	if old then old:Destroy() end
	model.Parent = folder
	table.insert(report, ("%s: asset %d parts %d size %.2f x %.2f x %.2f minY %.2f cost %d%s"):format(coll, id, parts, size.X, size.Y, size.Z, cf.Position.Y - size.Y * 0.5, cost, #missing > 0 and (" MISSING " .. table.concat(missing, ",")) or ""))
end
print("[install_set2] " .. table.concat(report, " | "))
return table.concat(report, " | ")
