--[[---------------------------------------DESCRIPTION------------------------------------------
	Scatters themed props over every generated piece so the whole run reads like one
	long snow resort: tree lines along both edges, cabin hamlets with fences, wood
	piles and snowmen, ski-lift lines with cables and chairs, distance and slope
	signs, ponds in the valleys and plenty of smashable clutter in the rolling lane.

	Placement is seeded (mountain seed + piece index) so every server differs but a
	given seed always builds the same resort. Designer sockets are still honoured:
	Destructible_N / LandmarkPoint / attachments with a PropModel attribute.

	Props go to workspace.MountainDecor/<PieceName> as Atomic models tagged
	"MountainProp" so streaming only sends nearby ones. The snowball smashes them:
	CLIENT_SnowballFX detects the hit, SERV_Snowball:SmashProp confirms it.

	placeMountainProps(mountainModel, mountainId, seed) -> count

--------------------------------------------------------------------------------------------]]--

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local T = mountainConfig.Attachment

local TRACK_HALF = 50

----------------------------------------------------------------------------------------------
-- Random helpers
----------------------------------------------------------------------------------------------

local function pick(rng, list)
	if not list or #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

-- entries = { { item, weight }, ... }
local function weightedPick(rng, entries)
	local total = 0
	for _, entry in entries do
		total += entry[2]
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber(0, total)
	local acc = 0
	for _, entry in entries do
		acc += entry[2]
		if roll <= acc then
			return entry[1]
		end
	end
	return entries[#entries][1]
end

-- Bell-ish number centred on 0, mostly within +-spread.
local function gaussian(rng, spread)
	local v = (rng:NextNumber() + rng:NextNumber() + rng:NextNumber()) / 3 - 0.5
	return v * 3 * spread
end

local function withCommas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

----------------------------------------------------------------------------------------------
-- Library
----------------------------------------------------------------------------------------------

local function findLibrary(settings)
	local storage = ServerStorage.Assets.Storage
	local propsFolder = storage:FindFirstChild(settings.StorageFolder)
	if not propsFolder then
		return nil
	end
	return propsFolder:FindFirstChild(settings.LibraryName)
end

local function buildLibrary(libraryFolder)
	local lib = { byName = {}, byCategory = {}, all = {} }
	for _, model in libraryFolder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local info = model:FindFirstChild("PropInfo")
		local catValue = info and info:FindFirstChild("Category")
		local fx = info and info:FindFirstChild("FootprintX")
		local fz = info and info:FindFirstChild("FootprintZ")
		local ok, _, size = pcall(function()
			return model:GetBoundingBox()
		end)
		if not ok then
			size = Vector3.new(4, 4, 4)
		end
		local entry = {
			Name = model.Name,
			Model = model,
			Category = (catValue and catValue.Value ~= "" and catValue.Value) or "Scenery",
			FootX = (fx and fx.Value > 0 and fx.Value) or size.X,
			FootZ = (fz and fz.Value > 0 and fz.Value) or size.Z,
			Height = size.Y,
		}
		entry.Radius = math.max(entry.FootX, entry.FootZ) * 0.5
		lib.byName[model.Name] = entry
		lib.byCategory[entry.Category] = lib.byCategory[entry.Category] or {}
		table.insert(lib.byCategory[entry.Category], entry)
		table.insert(lib.all, entry)
	end
	return lib
end

local function buildPools(lib, settings)
	local function list(name)
		return lib.byCategory[name] or {}
	end

	local P = {}
	P.Trees = list("Tree")
	P.Rocks = list("Rock")
	P.Buildings = table.clone(list("Building"))
	table.sort(P.Buildings, function(a, b)
		return a.Radius < b.Radius
	end)
	P.Fences = list("Fence")
	P.Snowmen = list("Snowman")
	P.Equipment = list("Equipment")
	P.Vehicles = list("Vehicle")
	P.WoodPiles = list("WoodPile")
	P.Ponds = list("Pond")
	P.Landmarks = list("Landmark")

	-- Generic themes only carry Scenery; split it by footprint so both pools fill.
	P.SmallScenery, P.BigScenery = {}, {}
	for category, entries in lib.byCategory do
		if category == "Tree" or category == "Rock" or category == "Building" or category == "Fence"
			or category == "Snowman" or category == "Equipment" or category == "Vehicle"
			or category == "WoodPile" or category == "Pond" or category == "Landmark"
			or category == "Sign" or category == "SkiLift" then
			continue
		end
		for _, entry in entries do
			if entry.Radius * 2 >= settings.BigFootprint then
				table.insert(P.BigScenery, entry)
			else
				table.insert(P.SmallScenery, entry)
			end
		end
	end
	if #P.Trees == 0 then
		P.Trees = P.BigScenery
	end

	-- Smashable clutter for the rolling lane
	P.Lane = {}
	local function addAll(src, weight)
		for _, entry in src do
			table.insert(P.Lane, { entry, weight })
		end
	end
	addAll(P.Snowmen, 3)
	addAll(P.Fences, 2)
	addAll(P.WoodPiles, 2)
	addAll(P.Equipment, 1.5)
	addAll(P.Vehicles, 1.5)
	addAll(P.SmallScenery, 2)
	for _, entry in P.Rocks do
		if entry.Radius < 5 then
			table.insert(P.Lane, { entry, 0.8 })
		end
	end
	for _, entry in P.Trees do
		if entry.Radius < 4 then
			table.insert(P.Lane, { entry, 0.6 })
		end
	end

	-- Things that gather around a cabin
	P.Satellites = {}
	local function addSat(src, weight)
		for _, entry in src do
			table.insert(P.Satellites, { entry, weight })
		end
	end
	addSat(P.Fences, 3)
	addSat(P.WoodPiles, 3)
	addSat(P.Snowmen, 3)
	addSat(P.Equipment, 2)
	addSat(P.Vehicles, 2)
	addSat(P.SmallScenery, 2)
	local flag = lib.byName.Resort_Flag
	if flag then
		table.insert(P.Satellites, { flag, 1.2 })
	end

	-- Edge-side big scenery for themes without buildings
	P.EdgeBig = {}
	for _, entry in P.Buildings do
		if entry.Radius <= 15 then
			table.insert(P.EdgeBig, { entry, 30 / entry.Radius })
		end
	end
	for _, entry in P.BigScenery do
		table.insert(P.EdgeBig, { entry, 1.5 })
	end

	return P
end

----------------------------------------------------------------------------------------------
-- Piece context: ground sampler + occupancy grid
----------------------------------------------------------------------------------------------

local function getSectionKind(section)
	local kind = section:GetAttribute("AttachmentType")
	if kind then
		return kind
	end
	local best = nil
	for _, typeName in mountainConfig.Attachments do
		if section.Name == typeName or string.sub(section.Name, 1, #typeName + 1) == typeName .. "_" then
			if not best or #typeName > #best then
				best = typeName
			end
		end
	end
	return best or section.Name
end

local function getSectionIndex(section)
	return tonumber(string.match(section.Name, "_(%d+)$")) or 0
end

local function collectSections(mountain)
	local sections = {}
	if mountain:FindFirstChild("Root") and mountain:FindFirstChild("Collision") then
		table.insert(sections, mountain)
		return sections
	end
	for _, child in mountain:GetChildren() do
		if child:IsA("Model") and child:FindFirstChild("Root") and child:FindFirstChild("Collision") then
			table.insert(sections, child)
		end
	end
	table.sort(sections, function(a, b)
		local ia, ib = getSectionIndex(a), getSectionIndex(b)
		if ia == ib then
			return a.Name < b.Name
		end
		return ia < ib
	end)
	return sections
end

local function makeContext(section, settings, snowHeight, decorRoot, seed)
	local root = section:FindFirstChild("Root")
	local collision = section:FindFirstChild("Collision")
	if not root or not collision then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { collision }

	local cf = root.CFrame
	local exit = root:FindFirstChild("Exit")
	local length = exit and -exit.Position.Z or nil
	if not length or length < 20 then
		local _, size = section:GetBoundingBox()
		length = size.Z
	end

	local items = {}
	local ctx = {
		Section = section,
		Kind = getSectionKind(section),
		Index = getSectionIndex(section),
		CFrame = cf,
		Length = length,
		Settings = settings,
		Placed = 0,
		Rng = Random.new(seed + getSectionIndex(section) * 7919),
	}

	-- world position on the snow surface at piece-local (x, z), plus normal + slope in degrees
	function ctx.Sample(x, z)
		local origin = cf:PointToWorldSpace(Vector3.new(x, 160, z))
		local hit = workspace:Raycast(origin, Vector3.new(0, -520, 0), params)
		if not hit then
			return nil
		end
		local slope = math.deg(math.acos(math.clamp(hit.Normal.Y, -1, 1)))
		return hit.Position + Vector3.new(0, snowHeight, 0), hit.Normal, slope
	end

	function ctx.Free(x, z, r)
		for _, item in items do
			local dx, dz = item.x - x, item.z - z
			local reach = item.r + r
			if dx * dx + dz * dz < reach * reach then
				return false
			end
		end
		return true
	end

	function ctx.Occupy(x, z, r)
		table.insert(items, { x = x, z = z, r = r })
	end

	local folder = Instance.new("Folder")
	folder.Name = section.Name
	folder.Parent = decorRoot
	ctx.Folder = folder

	return ctx
end

----------------------------------------------------------------------------------------------
-- Placing one prop
----------------------------------------------------------------------------------------------

local SNOW_COLOR = mountainConfig.SNOW.SnowColor
local SNOW_MATERIAL = mountainConfig.SNOW.SnowMaterial

local function rotateXZ(x, z, yaw)
	local c, s = math.cos(yaw), math.sin(yaw)
	return x * c + z * s, -x * s + z * c
end

local function finishClone(clone, entry, ctx)
	clone.Name = entry.Name
	clone:SetAttribute("PropCategory", entry.Category)
	clone:SetAttribute("PropRadius", entry.Radius)
	clone:SetAttribute("Piece", ctx.Section.Name)
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = desc.Name ~= "Root"
		end
	end
	CollectionService:AddTag(clone, ctx.Settings.Tag)
	clone.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	clone.Parent = ctx.Folder
	ctx.Placed += 1
	return clone
end

-- opts: margin, sink, maxSlope, boundsRadius, ignoreOccupancy, skipBounds
local function placeEntry(ctx, entry, x, z, yaw, opts)
	opts = opts or {}
	local settings = ctx.Settings
	local margin = opts.margin or 1.5
	local boundsRadius = opts.boundsRadius or entry.Radius

	if not opts.skipBounds then
		if math.abs(x) + boundsRadius > TRACK_HALF - settings.EdgeMargin then
			return nil
		end
		if z > -(boundsRadius + 3) or z < -(ctx.Length - boundsRadius - 3) then
			return nil
		end
	end
	if not opts.ignoreOccupancy and not ctx.Free(x, z, entry.Radius + margin) then
		return nil
	end

	local pos, _, slope = ctx.Sample(x, z)
	if not pos then
		return nil
	end
	local maxSlope = opts.maxSlope or settings.MaxSlope[entry.Category] or settings.MaxSlope.Default
	if slope > maxSlope then
		return nil
	end

	local basePos = pos
	local terrace = nil
	local isBig = entry.Category == "Building" or entry.Category == "Landmark" or entry.Radius * 2 >= settings.BigFootprint
	if isBig then
		local hx, hz = entry.FootX * 0.5, entry.FootZ * 0.5
		local maxY, minY = pos.Y, pos.Y
		for _, corner in { { hx, hz }, { -hx, hz }, { hx, -hz }, { -hx, -hz } } do
			local cx, cz = rotateXZ(corner[1], corner[2], yaw)
			local p = ctx.Sample(x + cx, z + cz)
			if p then
				maxY = math.max(maxY, p.Y)
				minY = math.min(minY, p.Y)
			end
		end
		basePos = Vector3.new(pos.X, maxY, pos.Z)
		if maxY - minY > 0.6 then
			terrace = { top = maxY - 0.2, bottom = minY - 1.5 }
		end
	end

	local sink = opts.sink or 0.1
	local rotation = ctx.CFrame.Rotation * CFrame.Angles(0, yaw, 0)
	local pivot = CFrame.new(basePos + Vector3.new(0, 0.5 - sink, 0)) * rotation

	local clone = entry.Model:Clone()
	clone:PivotTo(pivot)

	if terrace then
		local height = terrace.top - terrace.bottom
		local part = Instance.new("Part")
		part.Name = "Terrace"
		part.Size = Vector3.new(entry.FootX + 2, height, entry.FootZ + 2)
		part.CFrame = CFrame.new(Vector3.new(basePos.X, terrace.bottom + height / 2, basePos.Z)) * rotation
		part.Color = SNOW_COLOR
		part.Material = SNOW_MATERIAL
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CastShadow = false
		part.Parent = clone:FindFirstChild("Geometry") or clone
	end

	ctx.Occupy(x, z, entry.Radius + margin)
	return finishClone(clone, entry, ctx), x, z
end

local function tryPlace(ctx, entry, x, z, yaw, opts, attempts, jitter)
	for i = 1, attempts or 1 do
		local jx = if i == 1 then x else x + ctx.Rng:NextNumber(-jitter, jitter)
		local jz = if i == 1 then z else z + ctx.Rng:NextNumber(-jitter, jitter)
		local clone, px, pz = placeEntry(ctx, entry, jx, jz, yaw, opts)
		if clone then
			return clone, px, pz
		end
	end
	return nil
end

local function setSignText(clone, text)
	for _, desc in clone:GetDescendants() do
		if desc:IsA("TextLabel") then
			desc.Text = text
		end
	end
end

----------------------------------------------------------------------------------------------
-- Features
----------------------------------------------------------------------------------------------

local function scatterTreeline(ctx, P)
	if #P.Trees == 0 and #P.Rocks == 0 then
		return
	end
	local rng = ctx.Rng
	local settings = ctx.Settings
	local density = math.max(settings.Density, 0.05)
	local stepMin, stepMax = settings.TreeStep[1], settings.TreeStep[2]

	for _, side in { -1, 1 } do
		local z = -rng:NextNumber(6, 22)
		while z > -(ctx.Length - 8) do
			local entry, x, sink
			if rng:NextNumber() < 0.74 and #P.Trees > 0 then
				entry = pick(rng, P.Trees)
				x = side * rng:NextNumber(37, 46)
				sink = 0.7
			elseif #P.Rocks > 0 then
				entry = pick(rng, P.Rocks)
				x = side * rng:NextNumber(30, 44)
				sink = 0.9
			end
			if entry then
				tryPlace(ctx, entry, x, z, rng:NextNumber(0, 2 * math.pi), { sink = sink, margin = 1 }, 2, 6)
			end
			z -= rng:NextNumber(stepMin, stepMax) / density
		end
	end
end

local function buildHamlet(ctx, P, side, zCenter)
	if #P.EdgeBig == 0 then
		return false
	end
	local rng = ctx.Rng
	local settings = ctx.Settings
	local entry = weightedPick(rng, P.EdgeBig)
	if not entry then
		return false
	end

	local innerMost = 22
	local outerMost = TRACK_HALF - settings.EdgeMargin - entry.Radius
	if outerMost < innerMost then
		outerMost = innerMost
	end
	local x = side * rng:NextNumber(innerMost, outerMost)
	local yaw = side * math.pi / 2 + math.rad(rng:NextNumber(-25, 25))
	local house, hx, hz = tryPlace(ctx, entry, x, zCenter, yaw, { margin = 2 }, 3, 14)
	if not house then
		return false
	end

	local inward = -side
	for _ = 1, rng:NextInteger(2, 4) do
		local sat = weightedPick(rng, P.Satellites)
		if not sat then
			break
		end
		local sx, sz
		if rng:NextNumber() < 0.55 then
			sx = hx + inward * (entry.Radius + sat.Radius + rng:NextNumber(1, 5))
			sz = hz + rng:NextNumber(-entry.Radius, entry.Radius)
		else
			sx = hx + rng:NextNumber(-entry.Radius * 0.6, entry.Radius * 0.6)
			sz = hz + (if rng:NextNumber() < 0.5 then 1 else -1) * (entry.Radius + sat.Radius + rng:NextNumber(1, 4))
		end
		local satYaw
		if sat.Category == "Fence" then
			satYaw = if rng:NextNumber() < 0.7 then math.pi / 2 else 0
		elseif sat.Category == "Sign" then
			satYaw = math.pi
		elseif sat.Category == "Vehicle" or sat.Category == "Equipment" then
			satYaw = rng:NextNumber(0, 2 * math.pi)
		else
			satYaw = rng:NextNumber(0, 2 * math.pi)
		end
		tryPlace(ctx, sat, sx, sz, satYaw, { margin = 1 }, 2, 3)
	end
	return true
end

local function scatterHamlets(ctx, P)
	local chance = ctx.Settings.HamletChance[ctx.Kind]
	if not chance or chance <= 0 then
		return
	end
	local rng = ctx.Rng
	local count = 0
	if ctx.Kind == T.DestructionZone then
		count = 2
	elseif rng:NextNumber() < chance * math.min(ctx.Settings.Density, 1.5) then
		count = 1
		if ctx.Length >= 260 and rng:NextNumber() < 0.4 then
			count = 2
		end
	end
	if count == 0 then
		return
	end

	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local zLo, zHi = -(ctx.Length - 30), -30
	for i = 1, count do
		local z = rng:NextNumber(zLo, zHi)
		if count == 2 then
			-- spread the two along the piece
			local third = (zHi - zLo) / 2
			z = zLo + third * (i - 1) + rng:NextNumber(third * 0.15, third * 0.85)
		end
		buildHamlet(ctx, P, side, z)
		side = -side
	end
end

local function scatterPonds(ctx, P)
	if #P.Ponds == 0 then
		return
	end
	if ctx.Kind ~= T.Flat_Transition and ctx.Kind ~= T.Valley_Small and ctx.Kind ~= T.Valley_Large and ctx.Kind ~= T.FinishPlatform then
		return
	end
	local rng = ctx.Rng
	if rng:NextNumber() > ctx.Settings.PondChance then
		return
	end
	local entry = pick(rng, P.Ponds)
	for _ = 1, 5 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = side * rng:NextNumber(16, 34)
		local z = rng:NextNumber(-(ctx.Length - 20), -20)
		if placeEntry(ctx, entry, x, z, rng:NextNumber(0, 2 * math.pi), { margin = 2, sink = 0.55 }) then
			return
		end
	end
end

local function scatterLane(ctx, P)
	if #P.Lane == 0 then
		return
	end
	local rng = ctx.Rng
	local settings = ctx.Settings
	local per100 = settings.LaneDensity[ctx.Kind]
	if per100 == nil then
		per100 = 0.8
	end
	local count = math.floor(ctx.Length / 100 * per100 * settings.Density + rng:NextNumber())
	local zMin, zMax = -(ctx.Length - 10), -10
	if ctx.Kind == T.JumpRamp then
		zMax = -185 -- keep the ramp and the flight zone clear
	end
	if zMax <= zMin then
		return
	end

	for _ = 1, count do
		local entry = weightedPick(rng, P.Lane)
		if #P.Buildings > 0 and rng:NextNumber() < 0.07
			and (ctx.Kind == T.Downhill_Gentle or ctx.Kind == T.Flat_Transition or ctx.Kind == T.DestructionZone or ctx.Kind == T.Valley_Small) then
			entry = P.Buildings[1]
		end
		if not entry then
			break
		end
		local x = math.clamp(gaussian(rng, settings.LaneSpread), -settings.LaneHalfWidth, settings.LaneHalfWidth)
		local z = rng:NextNumber(zMin, zMax)
		local yaw
		if entry.Category == "Sign" then
			yaw = math.pi
		elseif entry.Category == "Fence" then
			yaw = if rng:NextNumber() < 0.6 then 0 else math.pi / 2
		elseif entry.Category == "Building" then
			yaw = math.pi + math.rad(rng:NextNumber(-20, 20))
		else
			yaw = rng:NextNumber(0, 2 * math.pi)
		end
		tryPlace(ctx, entry, x, z, yaw, { margin = 1.2 }, 3, 12)
	end

	-- Destruction zones get fence rows across the lane too
	if ctx.Kind == T.DestructionZone and #P.Fences > 0 then
		for _ = 1, 2 do
			local fence = pick(rng, P.Fences)
			local z = rng:NextNumber(zMin, zMax)
			local x0 = rng:NextNumber(-30, 6)
			for k = 0, 2 do
				placeEntry(ctx, fence, x0 + k * (fence.FootX + 0.6), z, 0, { margin = 0.4 })
			end
		end
	end
end

local function findLip(ctx, fromZ)
	-- first z (stepping downhill) where the surface gets steeper than 55 degrees
	local prevZ = fromZ
	local z = fromZ
	while z > -(ctx.Length - 6) do
		local _, _, slope = ctx.Sample(0, z)
		if slope and slope > 55 then
			return prevZ
		end
		prevZ = z
		z -= 4
	end
	return nil
end

local function placeWarnings(ctx, lib)
	local pole = lib.byName.Warning_Pole
	if not pole then
		return
	end
	local rng = ctx.Rng
	local lipZ
	if ctx.Kind == T.JumpRamp then
		local boost = ctx.Section.Root:FindFirstChild("BoostPoint")
		lipZ = (boost and boost.Position.Z or -70) + 8
	elseif ctx.Kind == T.Drop then
		lipZ = findLip(ctx, -12)
		if lipZ then
			lipZ += 3
		else
			lipZ = -40
		end
	else
		return
	end
	for _, x in { -34, -21, 21, 34 } do
		placeEntry(ctx, pole, x + rng:NextNumber(-2, 2), lipZ, math.pi, { margin = 0.5, maxSlope = 50 })
	end
end

local function placeSlopeSign(ctx, lib)
	local sign = lib.byName.Sign_SlopeDifficulty
	if not sign then
		return
	end
	local rng = ctx.Rng
	local text
	if ctx.Kind == T.Downhill_Steep then
		text = "STEEP SLOPE"
	elseif ctx.Kind == T.Drop then
		text = "CLIFF AHEAD"
	elseif ctx.Kind == T.JumpRamp then
		text = "JUMP AHEAD"
	elseif ctx.Kind == T.DestructionZone then
		text = "SMASH ZONE"
	elseif ctx.Kind == T.Downhill_Gentle and rng:NextNumber() < 0.2 then
		text = "EASY SLOPE"
	else
		return
	end
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local clone = tryPlace(ctx, sign, side * rng:NextNumber(28, 40), -rng:NextNumber(10, 22), math.pi, { margin = 1, maxSlope = 45 }, 2, 6)
	if clone then
		setSignText(clone, text)
	end
end

local function placeWelcome(ctx, lib)
	local sign = lib.byName.Sign_Welcome
	if not sign then
		return
	end
	for _, side in { -1, 1 } do
		tryPlace(ctx, sign, side * 30, -10, math.pi, { margin = 1, maxSlope = 45 }, 2, 4)
	end
end

local function placeSocketProps(ctx, lib, settings)
	-- Designer sockets: Destructible_N -> Targets[n], LandmarkPoint -> Landmark, PropModel attribute
	local root = ctx.Section:FindFirstChild("Root")
	if not root then
		return
	end
	local sockets = {}
	for _, inst in root:GetChildren() do
		if inst:IsA("Attachment") then
			table.insert(sockets, inst)
		end
	end
	table.sort(sockets, function(a, b)
		return a.Name < b.Name
	end)

	for _, socket in sockets do
		local modelName = nil
		local custom = socket:GetAttribute("PropModel")
		if typeof(custom) == "string" and custom ~= "" then
			modelName = custom
		elseif socket.Name == "LandmarkPoint" then
			modelName = if settings.PlaceFinalLodge then settings.Landmark else nil
		elseif string.sub(socket.Name, 1, 13) == "Destructible_" and settings.Targets then
			local n = tonumber(string.match(socket.Name, "(%d+)$")) or 1
			modelName = settings.Targets[(n - 1) % #settings.Targets + 1]
		end
		local entry = modelName and lib.byName[modelName]
		if entry then
			local p = socket.Position
			placeEntry(ctx, entry, p.X, p.Z, math.pi, { margin = 1.5, maxSlope = 45, skipBounds = true })
		end
	end
end

local function decorateFinish(ctx, lib, P, settings)
	local rng = ctx.Rng
	local arch = nil
	for _, entry in P.Landmarks do
		if string.find(string.lower(entry.Name), "arch", 1, true) then
			arch = entry
		end
	end
	arch = arch or lib.byName.Finish_Arch
	if arch then
		placeEntry(ctx, arch, 0, -14, math.pi, { margin = 0.5, maxSlope = 45, skipBounds = true })
	end

	local finishList = settings.Finish
	if type(finishList) == "string" then
		finishList = { finishList }
	end
	local spots = { { -34, -48 }, { 34, -48 }, { -34, -118 }, { 34, -118 } }
	if finishList then
		for i, spot in spots do
			local name = finishList[(i - 1) % #finishList + 1]
			local entry = lib.byName[name]
			if entry and entry.Category == "Building" then
				local side = if spot[1] < 0 then -1 else 1
				tryPlace(ctx, entry, spot[1], spot[2], side * math.pi / 2 + math.rad(rng:NextNumber(-15, 15)), { margin = 2 }, 2, 8)
			end
		end
	end
	local flag = lib.byName.Resort_Flag
	if flag then
		for _, x in { -14, 14 } do
			tryPlace(ctx, flag, x, -30, math.pi, { margin = 0.5 }, 2, 4)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Mountain-level features
----------------------------------------------------------------------------------------------

local function buildLiftLine(run, side, tower, cable, chair, settings, rng)
	local span = settings.SkiLiftSpan
	local x = side * (TRACK_HALF - settings.EdgeMargin - 3.6)
	local towers = {} -- { pivot = CFrame, ctx = ctx }
	local sinceLast = math.huge
	local lastPos = nil

	for _, ctx in run do
		local z = -8
		while z > -(ctx.Length - 8) do
			local pos = ctx.Sample(x, z)
			if pos then
				if lastPos then
					sinceLast += (pos - lastPos).Magnitude
				end
				lastPos = pos
				if sinceLast >= span then
					local clone = placeEntry(ctx, tower, x, z, 0, { margin = 1, boundsRadius = 3.5, sink = 0.3 })
					if clone then
						table.insert(towers, { pivot = clone:GetPivot(), ctx = ctx })
						sinceLast = 0
					end
				end
			end
			z -= 2
		end
	end

	if #towers < 2 or not cable then
		return
	end

	for i = 1, #towers - 1 do
		local a, b = towers[i], towers[i + 1]
		local ctx = a.ctx
		for k, offset in { Vector3.new(-5, 25, 0), Vector3.new(5, 25, 0) } do
			local pa = a.pivot:PointToWorldSpace(offset)
			local pb = b.pivot:PointToWorldSpace(offset)
			local length = (pb - pa).Magnitude
			if length < 4 then
				continue
			end
			local clone = cable.Model:Clone()
			local cablePart = clone:FindFirstChild("Cable", true)
			if cablePart then
				cablePart.Size = Vector3.new(cablePart.Size.X, cablePart.Size.Y, length)
			end
			clone:PivotTo(CFrame.lookAt((pa + pb) / 2, pb))
			finishClone(clone, cable, ctx)

			if chair and rng:NextNumber() < (settings.SkiLiftChairChance or 0.5) then
				local chairs = 1
				for c = 1, chairs do
					local t = (c - 0.5) / chairs + rng:NextNumber(-0.3, 0.3)
					t = math.clamp(t, 0.12, 0.88)
					local point = pa + (pb - pa) * t
					local yaw = if k == 1 then math.pi else 0
					local rotation = ctx.CFrame.Rotation * CFrame.Angles(0, yaw, 0)
					local mount = rotation:VectorToWorldSpace(Vector3.new(0, 8.5, 1.2))
					local chairClone = chair.Model:Clone()
					chairClone:PivotTo(CFrame.new(point - mount) * rotation)
					finishClone(chairClone, chair, ctx)
				end
			end
		end
	end
end

local function buildSkiLifts(contexts, lib, settings, rng)
	local tower = lib.byName.SkiLift_Tower
	local cable = lib.byName.SkiLift_CableSegment
	local chair = lib.byName.SkiLift_Chair
	if not tower then
		return
	end

	local n = #contexts
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local i = 1 + rng:NextInteger(settings.SkiLiftGap[1], settings.SkiLiftGap[2])
	while i <= n - 1 do
		local stretch = rng:NextInteger(settings.SkiLiftStretch[1], settings.SkiLiftStretch[2])
		local run = {}
		local j = i
		while j <= n - 1 and #run < stretch do
			local ctx = contexts[j]
			if ctx.Kind == T.Drop or ctx.Kind == T.JumpRamp or ctx.Kind == T.StartPlatform or ctx.Kind == T.FinishPlatform then
				break
			end
			table.insert(run, ctx)
			j += 1
		end
		if #run >= 2 then
			buildLiftLine(run, side, tower, cable, chair, settings, rng)
			side = -side
		end
		i = math.max(j, i + 1) + rng:NextInteger(settings.SkiLiftGap[1], settings.SkiLiftGap[2])
	end
end

local function placeDistanceSigns(contexts, lib, settings, rng)
	local sign = lib.byName.Sign_Distance
	if not sign then
		return
	end
	local every = settings.DistanceSignEvery
	if not every or every <= 0 then
		return
	end
	local travelled = 0
	for _, ctx in contexts do
		local startDist = travelled
		local endDist = travelled + ctx.Length
		travelled = endDist
		if ctx.Kind == T.StartPlatform then
			continue
		end
		local m = math.ceil(startDist / every) * every
		if m == startDist then
			m += every
		end
		while m <= endDist do
			local z = -(m - startDist)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local clone = tryPlace(ctx, sign, side * rng:NextNumber(34, 42), z, math.pi, { margin = 1, maxSlope = 45 }, 3, 10)
				or tryPlace(ctx, sign, -side * rng:NextNumber(34, 42), z, math.pi, { margin = 1, maxSlope = 45 }, 3, 10)
			if clone then
				setSignText(clone, withCommas(m) .. " STUDS")
			end
			m += every
		end
	end
end

----------------------------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------------------------

local function placeMountainProps(mountainModel, mountainId, seed)
	local settings = mountainConfig:GetPropSettings(mountainId)
	if not settings.Enabled then
		return 0
	end

	local libraryFolder = findLibrary(settings)
	if not libraryFolder then
		warn("[SERVER]: Prop library not found:", settings.StorageFolder, settings.LibraryName)
		return 0
	end
	local lib = buildLibrary(libraryFolder)
	if #lib.all == 0 then
		warn("[SERVER]: Prop library is empty:", libraryFolder:GetFullName())
		return 0
	end
	local P = buildPools(lib, settings)

	local snow = mountainConfig:GetSnowSettings(mountainId)
	local snowHeight = if snow.Enabled then snow.Thickness else 0
	seed = seed or 0

	-- Fresh decor root in workspace (streamable; the mountain pieces are Persistent)
	local decorRoot = workspace:FindFirstChild(settings.WorkspaceFolder)
	if decorRoot then
		decorRoot:Destroy()
	end
	decorRoot = Instance.new("Folder")
	decorRoot.Name = settings.WorkspaceFolder
	decorRoot:SetAttribute("MountainId", mountainId)
	decorRoot.Parent = workspace

	local contexts = {}
	for _, section in collectSections(mountainModel) do
		local old = section:FindFirstChild(settings.DecorFolder)
		if old then
			old:Destroy()
		end
		local ctx = makeContext(section, settings, snowHeight, decorRoot, seed)
		if ctx then
			table.insert(contexts, ctx)
		end
	end

	local globalRng = Random.new(seed + 17)

	-- Designer sockets + special pieces first so they always get their spot
	for _, ctx in contexts do
		if ctx.Kind == T.StartPlatform then
			continue
		end
		placeSocketProps(ctx, lib, settings)
		if ctx.Kind == T.FinishPlatform then
			decorateFinish(ctx, lib, P, settings)
		end
		placeWarnings(ctx, lib)
		placeSlopeSign(ctx, lib)
		if ctx.Index == 2 then
			placeWelcome(ctx, lib)
		end
	end

	buildSkiLifts(contexts, lib, settings, globalRng)
	placeDistanceSigns(contexts, lib, settings, globalRng)

	local placed = 0
	for _, ctx in contexts do
		if ctx.Kind ~= T.StartPlatform then
			scatterHamlets(ctx, P)
			scatterPonds(ctx, P)
			scatterLane(ctx, P)
			scatterTreeline(ctx, P)
		end
		placed += ctx.Placed
		if ctx.Placed == 0 then
			ctx.Folder:Destroy()
		end
	end

	decorRoot:SetAttribute("PropCount", placed)
	return placed
end

return placeMountainProps
