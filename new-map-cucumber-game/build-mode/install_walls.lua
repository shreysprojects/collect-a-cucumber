-- install_walls.lua: ONE execute_luau (edit mode) with pets-remake/serve.ps1 -Port 8770 -Root build-mode
-- running. Replaces the four wall models in ServerStorage.Builds.Walls with the plain 8 x 12 walls
-- built by plainwalls/build_plain_walls.py: InsertService:LoadAsset(each group asset), strip the
-- "<Collection>." prefix from part names, undo the FBX importer's 180-degree yaw, re-apply colour /
-- material / transparency from the manifest (the FBX loses them), anchor + collide, pivot at the origin,
-- keep the old model's Cost. Inputs on the server: plainwalls-manifest.json, plainwalls-asset-ids.json.
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")
local BASE = "http://127.0.0.1:8770/"
local function fetch(name)
	local ok, body = pcall(HttpService.GetAsync, HttpService, BASE .. name)
	assert(ok, "fetch " .. name .. ": " .. tostring(body))
	return body
end
local manifest = HttpService:JSONDecode(fetch("plainwalls-manifest.json"))
local ids = HttpService:JSONDecode(fetch("plainwalls-asset-ids.json"))
local walls = ServerStorage:WaitForChild("Builds"):WaitForChild("Walls")
local DEFAULT_COST = {WoodenWall = 150, StoneWall = 400, IronWall = 800, BarbedStoneWall = 1200}

local byPart = {} -- [collection][part name] = manifest entry
for _, entry in ipairs(manifest.parts) do
	byPart[entry.collection] = byPart[entry.collection] or {}
	byPart[entry.collection][entry.name] = entry
end

local report = {}
for coll, robloxName in pairs(manifest.roblox_names) do
	local id = tonumber(ids[coll])
	assert(id, "no asset id for " .. coll)
	local ok, container = pcall(InsertService.LoadAsset, InsertService, id)
	assert(ok and container, "LoadAsset " .. tostring(id) .. " failed: " .. tostring(container))
	local old = walls:FindFirstChild(robloxName)
	local cost = old and old:GetAttribute("Cost") or DEFAULT_COST[robloxName]
	local model = Instance.new("Model")
	model.Name = robloxName
	local parts, missing = 0, {}
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") then
			local name = d.Name:gsub("^" .. coll .. "%.", "")
			local entry = byPart[coll] and (byPart[coll][coll .. "." .. name] or byPart[coll][name])
			d.Name = name
			d.CFrame = CFrame.Angles(0, math.pi, 0) * d.CFrame -- the importer's yaw
			if entry then
				d.Color = Color3.fromHex(entry.hex)
				d.Material = Enum.Material[entry.material]
				d.Transparency = entry.transparency or 0
			else
				table.insert(missing, name)
			end
			d.Anchored = true
			d.CanCollide = true
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
	model:SetAttribute("PropSet", "defence")
	model:SetAttribute("Tris", manifest.props[coll] and manifest.props[coll].tris or 0)
	model:SetAttribute("Notes", ("Plain %s (plainwalls/build_plain_walls.py, 2026-09-10): 8 x 12 tiling wall - no spikes, barbs or gaps, flat top so the second-floor tiles rest on it; faces -Z after the FBX yaw fix; group asset %d."):format(robloxName, id))
	if old then old:Destroy() end
	model.Parent = walls
	table.insert(report, ("%s: asset %d parts %d size %.2f x %.2f x %.2f minY %.2f%s"):format(robloxName, id, parts, size.X, size.Y, size.Z, cf.Position.Y - size.Y * 0.5, #missing > 0 and (" MISSING " .. table.concat(missing, ",")) or ""))
end
print("[install_walls] " .. table.concat(report, " | "))
return table.concat(report, " | ")
