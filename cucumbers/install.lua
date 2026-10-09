--!nolint
-- Installs the cucumber set into a place.  Run in Studio EDIT mode through the MCP
-- execute_luau tool, a few models per call (InsertService:LoadAsset is slow enough that
-- the whole set in one call blows the ~20 s proxy timeout).
--
-- It pulls install-payload.json off the loopback server (serve.ps1 on 127.0.0.1:8765),
-- loads each model's group-owned Model asset, and then does the three things an FBX
-- import always needs:
--   1. strips the "<Collection>." prefix the FBX carries on every part name
--   2. yaws every part 180 degrees about Y - Roblox's FBX importer faces them backwards
--   3. re-applies colour / material / transparency from the manifest, BY PART NAME,
--      because the import loses all of it and every part arrives grey Plastic
--
-- Usage from execute_luau:
--   local f = loadstring(game:GetService("HttpService"):GetAsync(BASE .. "install.lua"))
--   return f()({"Cucumber", "CucumberTree"})

local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local BASE = "http://127.0.0.1:8765/"
local LIB_FOLDER = "CucumberSet"
local DISPLAY_FOLDER = "CucumberSetDisplay"

local function folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function hexToColor3(hex)
	local n = tonumber(hex, 16) or 0
	return Color3.fromRGB(bit32.band(bit32.rshift(n, 16), 255),
		bit32.band(bit32.rshift(n, 8), 255), bit32.band(n, 255))
end

local MATERIAL = {}
for _, m in ipairs(Enum.Material:GetEnumItems()) do
	MATERIAL[m.Name] = m
end

-- world-space AABB measured from part CFrames, because Model:GetBoundingBox() reports in
-- the PIVOT's frame and returns nonsense-looking axes once a PrimaryPart is set
local function worldAABB(model)
	local lo, hi
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, sz = d.CFrame, d.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz2 = -1, 1, 2 do
						local p = cf:PointToWorldSpace(Vector3.new(sz.X * sx, sz.Y * sy, sz.Z * sz2))
						lo = lo and Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z)) or p
						hi = hi and Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z)) or p
					end
				end
			end
		end
	end
	return lo, hi
end

local function installOne(name, info, lib)
	local existing = lib:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local ok, container = pcall(function()
		return InsertService:LoadAsset(info.assetId)
	end)
	if not ok or not container then
		return nil, ("LoadAsset failed: %s"):format(tostring(container))
	end

	-- the asset's contents: usually one Model, occasionally the parts directly
	local src = nil
	for _, ch in ipairs(container:GetChildren()) do
		if ch:IsA("Model") then
			src = ch
			break
		end
	end
	if not src then
		src = container
	end

	local model = Instance.new("Model")
	model.Name = name
	for _, ch in ipairs(src:GetChildren()) do
		ch.Parent = model
	end
	container:Destroy()

	local YAW = CFrame.Angles(0, math.pi, 0)
	local applied, missed, total = 0, {}, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			total += 1
			local short = d.Name:match("%.([^%.]+)$") or d.Name
			d.Name = short
			d.CFrame = YAW * d.CFrame
			local look = info.parts[short]
			if look then
				d.Color = hexToColor3(look.hex)
				d.Material = MATERIAL[look.material] or Enum.Material.SmoothPlastic
				d.Transparency = look.transparency or 0
				applied += 1
			else
				table.insert(missed, short)
			end
			d.Anchored = true
			d.CanCollide = true
			d.CastShadow = true
		end
	end

	model.PrimaryPart = nil
	model.WorldPivot = CFrame.new()

	model:SetAttribute("AssetId", info.assetId)
	model:SetAttribute("Biome", info.biome)
	model:SetAttribute("Archetype", info.archetype)
	model:SetAttribute("Tris", info.tris)
	model:SetAttribute("Notes", info.notes)
	model.Parent = lib

	local lo, hi = worldAABB(model)
	return {
		name = name,
		parts = total,
		applied = applied,
		missed = missed,
		size = hi and (hi - lo) or Vector3.zero,
		minY = lo and lo.Y or 0,
	}
end

local function payload()
	return HttpService:JSONDecode(HttpService:GetAsync(BASE .. "install-payload.json"))
end

local API = {}

--- Load `names` out of Open Cloud into ServerStorage.CucumberSet.
function API.install(names)
	local data = payload()
	local lib = folder(ServerStorage, LIB_FOLDER)
	local out = {}
	for _, name in ipairs(names) do
		local info = data.models[name]
		if not info then
			table.insert(out, ("%-27s NO PAYLOAD ENTRY"):format(name))
		else
			local res, err = installOne(name, info, lib)
			if not res then
				table.insert(out, ("%-27s FAILED %s"):format(name, err))
			else
				table.insert(out, ("%-27s %2d parts, %2d coloured%s  %.2f x %.2f x %.2f  minY %.3f")
					:format(res.name, res.parts, res.applied,
						#res.missed > 0 and (" MISSING:" .. table.concat(res.missed, ",")) or "",
						res.size.X, res.size.Y, res.size.Z, res.minY))
			end
		end
	end
	return table.concat(out, "\n")
end

--- Lay the whole library out in Workspace: one ROW per biome, models spaced by their own
--- footprint so a 12-stud tree does not sit on top of a 2-stud slice group.
function API.display(origin, gap, rowGap)
	origin = origin or Vector3.new(0, 0, -30)
	gap = gap or 6
	rowGap = rowGap or 16

	local data = payload()
	local lib = ServerStorage:FindFirstChild(LIB_FOLDER)
	if not lib then
		return "no ServerStorage." .. LIB_FOLDER
	end
	local old = workspace:FindFirstChild(DISPLAY_FOLDER)
	if old then
		old:Destroy()
	end
	local disp = folder(workspace, DISPLAY_FOLDER)

	-- group by biome, in the payload's declared order
	local byBiome, order = {}, {}
	for _, b in ipairs(data.biomeOrder) do
		byBiome[b] = {}
		table.insert(order, b)
	end
	local names = {}
	for name in pairs(data.models) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local b = data.models[name].biome
		if not byBiome[b] then
			byBiome[b] = {}
			table.insert(order, b)
		end
		table.insert(byBiome[b], name)
	end

	local z = origin.Z
	local placed, lines = 0, {}
	for _, b in ipairs(order) do
		local row = byBiome[b]
		if #row > 0 then
			-- row depth is the deepest model in it
			local depth = 0
			local widths = {}
			for _, name in ipairs(row) do
				local m = lib:FindFirstChild(name)
				if m then
					local lo, hi = worldAABB(m)
					widths[name] = hi and (hi.X - lo.X) or 4
					depth = math.max(depth, hi and (hi.Z - lo.Z) or 4)
				end
			end
			local total = 0
			for _, name in ipairs(row) do
				total += (widths[name] or 4) + gap
			end
			local x = origin.X - total / 2
			for _, name in ipairs(row) do
				local m = lib:FindFirstChild(name)
				if m then
					local w = widths[name] or 4
					x += w / 2
					local clone = m:Clone()
					clone:PivotTo(CFrame.new(x, origin.Y, z))
					clone.Parent = disp
					placed += 1
					x += w / 2 + gap
				end
			end
			table.insert(lines, ("%-11s %2d models, row depth %.1f at z %.0f"):format(b, #row, depth, z))
			z -= depth + rowGap
		end
	end
	return ("placed %d models in workspace.%s\n%s"):format(placed, DISPLAY_FOLDER,
		table.concat(lines, "\n"))
end

return API
