--[[
	BuildCatalog  (ModuleScript, ReplicatedStorage.Modules)  2026-09-10
	Shared half of build mode (user: "click Build -> category buttons at the bottom middle styled like
	the HUD -> a row of builds with title / viewport / cost -> click one, it is on your mouse, place it
	in your base").
	  * ServerStorage.Builds/<Category>/<Model> IS the catalog: one bottom button per subfolder (order
	    and colours in CATEGORIES below, other folders get a neutral look after them), one card per
	    model - or one per variant for the A_ / B_ / C_ prefixed collections (attribute Variants, the
	    Blender props that ship three props side by side). Move a model between subfolders to move its
	    card; drop a new model in to sell it.
	  * cost = the model's Cost attribute (organize_builds stamped DEFAULT_COST once on 2026-09-10; edit
	    the attribute in Studio to re-price, no code change). Selling pays back SELL_REFUND of it.
	  * FLOORS AND THE GRID: the plot's grass is a grid of CELL x CELL tiles (BuildService builds
	    plot.GrassTiles: columns centred on the plot's X, rows hung off the BACK edge that
	    PlotUpgradeService keeps fixed across upgrades; round(Size / CELL) cells per axis, all the same
	    size, so the grid ends exactly on the plot edges and nothing is left over). The ground
	    walking surface is the grass tiles' top, FLOOR_LIFT above the plot slab. A Flooring tile
	    (IsFloor) snaps to the nearest cell, FitTile stretches the tile to the cell's exact size, and it
	    REPLACES that grass tile - nothing of the grass shows where a tile is. Upstairs (level 2) the tiles rest on the
	    LEVEL_HEIGHT-tall walls: bottom LEVEL_HEIGHT above the ground surface, top FLOOR_THICKNESS
	    higher = the upstairs walking surface, flush with the Staircase landing. Every build lands on
	    the floor the PLAYER stands on (PlayerLevel); a tile's TOP and a build's BOTTOM both sit at
	    SurfaceY(level). A tile and a build never block each other on the ground; upstairs anything but
	    a tile must have flooring under its footprint (Supported) and a tile must JOIN the upstairs
	    floor (FloorAnchored: edge to edge with a tile already up there, or the cell straight off a
	    staircase landing). A Staircase (IsStairs) snaps so its landing's open edge lies on a cell
	    boundary (SnapStairs), so that first tile butts against it exactly.
	  * COLLISIONS (2026-09-10, later): the Collisions checkbox on the placing strip. On (default), a
	    build may not overlap another build and an upstairs tile may not cut through anything; off,
	    builds may intersect each other. Fixtures always block, and a tile never goes into a taken cell
	    (Blocks).
	  * BuildService clones every model into ReplicatedStorage.PlaceableBuilds/<Category>/<Key> with an
	    invisible "Hitbox" PrimaryPart and attributes Key / Category / DisplayName / Cost / Source /
	    IsFloor / IsStairs / Unlock (2026-09-23: the Strength it needs, UNLOCK_STRENGTH below);
	    BuildMenuClient reads those. This module lists them for both sides.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local M = {}

M.FOLDER = "Builds"              -- ServerStorage.Builds/<Category>/<Model>
M.TEMPLATES = "PlaceableBuilds"  -- ReplicatedStorage.PlaceableBuilds/<Category>/<Key>
M.PLACED_TAG = "PlacedBuild"
M.REMOTE = "requestBuildPlacement"
M.MOVE_REMOTE = "requestBuildMove"
M.SELL_REMOTE = "requestBuildSell"
M.CELL = 8               -- the grass / flooring grid, studs: the plot is divided into round(Size / 8) cells per axis, so every cell is the same size (7.78 x 7.73 on a 70 x 85 plot - as near square as a plot that is not a whole number of 8s allows), nothing is left over at the edges and a tile runs right to them; a Flooring tile is stretched to its cell (FitTile) so tile and cell are always the same size
M.GRASS_THICKNESS = 0.12 -- the grass tiles (sunk 0.02 into the plot slab)
M.FLOOR_LIFT = 0.1       -- the grass tiles' top above the plot slab = the ground walking surface
M.FLOOR_THICKNESS = 1    -- a Flooring tile
M.LEVEL_HEIGHT = 12      -- clear height of a storey: the walls are 12 tall and the next floor's tiles rest on them
M.MAX_LEVELS = 2         -- the ground and one upper floor (raise it and the same rules carry on up)
M.UPSTAIRS_SLACK = 4     -- the player's root counts as "on" a level from this far below its surface (the root rides ~3 above the feet)
M.FRONT_DIRECTION = Vector3.new(-1, 0, 0) -- = PlotUpgradeService.FRONT_DIRECTION: a plot's front faces this way, its BACK edge never moves
M.SELL_REFUND = 0.5      -- fraction of a build's Cost paid back when it is sold
M.GRID_SIZES = {2, 1, 0.5} -- the Grid button cycles these (studs; 2026-09-13: doubled from 1 / 0.5 / 0.25, user "grid squares is too tiny"); Flooring always snaps to cells, a Staircase to cell edges
M.DEFAULT_COLLISIONS = true -- the Collisions checkbox starts ticked
--.. Creator Store decals for the square buttons: an orange price tag (icons8) and a Material Symbols 3 x 3 grid (white; tinted dark on the button)
M.ICONS = {Sell = "rbxassetid://8214461591"} -- IMAGE id of the Creator Store trash can (decal 8214461600 resolved through InsertService:LoadAsset -> Decal.Texture; an ImageLabel given a decal id shows nothing). The Grid icon is frame-drawn by the client (gridIndex + 1 lines each way).

--.. the bottom buttons, in order; colours follow the HUD (green Shop / Build, cyan Index / Manage)
M.CATEGORIES = {
	{Name = "Walls", Label = "Walls", Top = Color3.fromRGB(255, 190, 60), Bottom = Color3.fromRGB(255, 130, 0), Highlight = Color3.fromRGB(255, 232, 160)},
	{Name = "Defences", Label = "Defences", Top = Color3.fromRGB(255, 100, 100), Bottom = Color3.fromRGB(230, 30, 30), Highlight = Color3.fromRGB(255, 196, 196)},
	{Name = "Garden", Label = "Garden", Top = Color3.fromRGB(157, 255, 36), Bottom = Color3.fromRGB(69, 255, 0), Highlight = Color3.fromRGB(208, 255, 106)},
	{Name = "Fun", Label = "Fun", Top = Color3.fromRGB(220, 130, 255), Bottom = Color3.fromRGB(165, 45, 255), Highlight = Color3.fromRGB(242, 206, 255)},
	{Name = "Home", Label = "Home", Top = Color3.fromRGB(110, 200, 255), Bottom = Color3.fromRGB(30, 130, 240), Highlight = Color3.fromRGB(200, 235, 255)}, -- 2026-09-24: furniture + appliances
}

--.. 2026-09-24 (user: "make some builds bigger that should be bigger. eg. post lantern is wayy too small. seesaw could be
--.. bigger/longer"): the Blender props were authored against a 5-stud avatar, New Map characters stand ~6 studs and
--.. grow with their physique, next to 12-stud walls. BuildService scales each template about its Hitbox by this
--.. (exact key first - "Lantern_A" - then the base key - "Lantern"); unlisted builds stay 1. Placed and saved copies
--.. come from the template, so they follow on the next server start.
M.SCALE = {
	Lantern_A = 2.1, Lantern_B = 1.7, Lantern_C = 1.5,             -- post lamp 4.6 -> 9.7 tall
	TikiTorch_A = 1.5, TikiTorch_B = 1.5, TikiTorch_C = 1.4,
	Tree_A = 1.6, Tree_B = 1.6, Tree_C = 1.5,
	Sunflower = 1.5, Scarecrow = 1.35, Fountain = 1.5, Pond = 1.3, HayBale = 1.3,
	Wheelbarrow = 1.3, WateringCan = 1.3, Bush = 1.25,
	Seesaw = 1.8,                                                   -- 7.9 -> 14.2 long
	Trampoline = 1.5, Slide = 1.5, TV = 1.7, HotTub = 1.4, -- TV 1.45 -> 1.7 (2026-09-24, user: "make tv slightly bigger") DJBooth = 1.3, DanceFloor = 1.5,
	ArcadeCabinet = 1.25, VendingMachine = 1.25, Hammock = 1.35, BeanBag = 1.4, GlassCase = 1.25, NeonSign = 1.5,
}

function M.ScaleOf(key)
	if type(key) ~= "string" then return 1 end
	local s = M.SCALE[key]
	if s == nil then
		local base = key:match("^(.-)_%u$")
		s = base and M.SCALE[base]
	end
	return tonumber(s) or 1
end
M.NEUTRAL = {Top = Color3.fromRGB(200, 205, 215), Bottom = Color3.fromRGB(140, 148, 165), Highlight = Color3.fromRGB(235, 238, 245)}
M.BACK = {Top = Color3.fromRGB(0, 232, 255), Bottom = Color3.fromRGB(0, 185, 239), Highlight = Color3.fromRGB(170, 245, 255)}
M.DONE = {Top = Color3.fromRGB(255, 100, 100), Bottom = Color3.fromRGB(230, 30, 30), Highlight = Color3.fromRGB(255, 196, 196)}
M.CLOSE = {Top = Color3.fromRGB(250, 250, 255), Bottom = Color3.fromRGB(205, 211, 224), Highlight = Color3.fromRGB(255, 255, 255)} -- the square red-X button
M.SELL_OFF = {Top = Color3.fromRGB(250, 250, 255), Bottom = Color3.fromRGB(205, 211, 224), Highlight = Color3.fromRGB(255, 255, 255)} -- the Sell square at rest (the orange tag on a light face)
M.SELL_ON = {Top = Color3.fromRGB(255, 110, 110), Bottom = Color3.fromRGB(225, 25, 25), Highlight = Color3.fromRGB(255, 200, 200)} -- ... and while selling
M.GRID = {Top = Color3.fromRGB(200, 240, 255), Bottom = Color3.fromRGB(120, 190, 240), Highlight = Color3.fromRGB(230, 250, 255)} -- the Grid square
M.COLLIDE_ON = {Top = Color3.fromRGB(157, 255, 36), Bottom = Color3.fromRGB(69, 255, 0), Highlight = Color3.fromRGB(208, 255, 106)} -- the Collisions box, ticked
M.COLLIDE_OFF = {Top = Color3.fromRGB(210, 214, 222), Bottom = Color3.fromRGB(150, 156, 170), Highlight = Color3.fromRGB(238, 240, 246)} -- ... unticked

--.. where organize_builds put each model (a model that later turns up in another subfolder simply
--.. follows the folder; this table is only the record of the first sort)
M.DEFAULT_CATEGORY = {
	WoodenWall = "Walls", StoneWall = "Walls", IronWall = "Walls", BarbedStoneWall = "Walls", Staircase = "Walls", Flooring = "Walls",
	Turret = "Defences", SpikeTrap = "Defences", BoostPad = "Defences", Catapult = "Defences",
	Bush = "Garden", Tree = "Garden", Sunflower = "Garden", Pond = "Garden", Fountain = "Garden", Scarecrow = "Garden",
	HayBale = "Garden", WateringCan = "Garden", Wheelbarrow = "Garden", Lantern = "Garden", TikiTorch = "Garden",
	ArcadeCabinet = "Fun", BeanBag = "Fun", DJBooth = "Fun", DanceFloor = "Fun", Hammock = "Fun", HotTub = "Fun",
	Seesaw = "Fun", Slide = "Fun", Trampoline = "Fun", TV = "Fun", VendingMachine = "Fun", GlassCase = "Fun", NeonSign = "Fun",
}
--.. Cash; used only when a model has no Cost attribute (2026-09-23 economy: the defence / wall rows match
--.. the Cost attributes stamped on ServerStorage.Builds that day - x10 per unlock tier, see UNLOCK_STRENGTH)
M.DEFAULT_COST = {
	WoodenWall = 100, StoneWall = 600, IronWall = 60000, BarbedStoneWall = 100000000, Staircase = 300, Flooring = 100,
	SpikeTrap = 300, BoostPad = 400, Catapult = 2500, Turret = 25000, LaserGate = 250000, FreezeTower = 3000000,
	TeslaCoil = 30000000, Mortar = 400000000, Minigun = 5000000000,
	Sunflower = 50, WateringCan = 60, Bush = 75, HayBale = 100, Wheelbarrow = 120, Scarecrow = 200, Lantern = 250,
	TikiTorch = 250, Tree = 300, Pond = 600, Fountain = 1000,
	BeanBag = 150, Hammock = 300, TV = 350, Seesaw = 400, Trampoline = 450, GlassCase = 500, NeonSign = 600,
	VendingMachine = 700, DanceFloor = 800, ArcadeCabinet = 900, Slide = 1000, HotTub = 1500, DJBooth = 2000,
}
M.FALLBACK_COST = 100
--.. card titles for the variant collections (else the Variants JSON name, split on capitals)
M.VARIANT_NAMES = {
	Tree = {A = "Oak", B = "Pine", C = "Sapling"},
	Bush = {A = "Shrub", B = "Hedge", C = "Flowering Bush"},
	Sunflower = {A = "Tall Sunflower", B = "Sunflower", C = "Sunflower Clump"},
	HayBale = {A = "Round Bale", B = "Square Bale", C = "Hay Stack"},
	Lantern = {A = "Post Lantern", B = "Paper Lantern", C = "Garden Lantern"},
	TikiTorch = {A = "Bamboo Torch", B = "Tiki Head", C = "Brazier"},
	BeanBag = {A = "Pouf", B = "Slouch Bag", C = "Ottoman"},
	NeonSign = {A = "Open Sign", B = "Arrow Sign", C = "Marquee"},
}

--.. "WoodenWall" -> "Wooden Wall", "DJBooth" -> "DJ Booth", "TV" -> "TV"
function M.SplitCamel(name)
	local s = tostring(name or "")
	s = s:gsub("(%l)(%u)", "%1 %2")
	s = s:gsub("(%u)(%u%l)", "%1 %2")
	s = s:gsub("(%a)(%d)", "%1 %2")
	return s
end

function M.CategoryInfo(name)
	for _, info in ipairs(M.CATEGORIES) do
		if info.Name == name then return info end
	end
	return nil
end

function M.CostOf(model)
	local cost = tonumber(model:GetAttribute("Cost"))
	if cost == nil then cost = M.DEFAULT_COST[model.Name] or M.FALLBACK_COST end
	return math.max(0, math.floor(cost))
end

--.. what a sale pays back
function M.RefundOf(cost)
	return math.floor(math.max(0, tonumber(cost) or 0) * M.SELL_REFUND)
end

--..Floors (all Y values in the plot's own space; the plot slab's top is Size.Y / 2)..--

--.. a level's walking surface: a floor tile's TOP and a build's BOTTOM both sit here
function M.SurfaceY(plot, level)
	level = math.clamp(level or 1, 1, M.MAX_LEVELS)
	return plot.Size.Y * 0.5 + M.FLOOR_LIFT + (level - 1) * (M.LEVEL_HEIGHT + M.FLOOR_THICKNESS)
end

--.. the level the player is standing on, from their root's position (world space)
function M.PlayerLevel(plot, rootPosition)
	local rp = plot.CFrame:PointToObjectSpace(rootPosition)
	local level = 1
	for l = 2, M.MAX_LEVELS do
		if rp.Y >= M.SurfaceY(plot, l) - M.UPSTAIRS_SLACK then level = l end
	end
	return level
end

--.. the level whose surface is nearest a placement's edge (a build's bottom, a tile's top)
function M.LevelFromEdge(plot, edgeY)
	local best, bestDistance = 1, math.huge
	for l = 1, M.MAX_LEVELS do
		local distance = math.abs(edgeY - M.SurfaceY(plot, l))
		if distance < bestDistance then best, bestDistance = l, distance end
	end
	return best
end

--..The grid (plot space)..--

--.. plot-space z of the back edge (fixed across plot upgrades) and the sign toward the front
function M.BackZ(plot)
	local sign = plot.CFrame.ZVector:Dot(M.FRONT_DIRECTION) >= 0 and 1 or -1
	return -sign * plot.Size.Z * 0.5, sign
end

--.. every grass cell: round(Size / CELL) equal cells per axis - columns centred on the plot's X, rows
--.. from the back edge - so the grid ends exactly on the plot edges. Cached per plot size.
local cellCache = {} -- [plot] = {Key, Cells, XCentres, ZCentres, XEdges, ZEdges}
local function Grid(plot)
	local backZ, sign = M.BackZ(plot)
	local key = ("%.2f,%.2f,%d"):format(plot.Size.X, plot.Size.Z, sign)
	local cached = cellCache[plot]
	if cached and cached.Key == key then return cached end
	local halfX = plot.Size.X * 0.5
	local columns, rows = {}, {}
	-- as many cells per axis as fit at ~CELL studs, all the same size, so the grid ends exactly on the plot edges
	local nx = math.max(1, math.round(plot.Size.X / M.CELL))
	local nz = math.max(1, math.round(plot.Size.Z / M.CELL))
	local w, d = plot.Size.X / nx, plot.Size.Z / nz
	for i = 1, nx do
		table.insert(columns, {C = -halfX + w * (i - 0.5), W = w, Full = true})
	end
	for j = 1, nz do
		table.insert(rows, {C = backZ + sign * d * (j - 0.5), W = d, Full = true})
	end
	local cells = {}
	for i, column in ipairs(columns) do
		for j, row in ipairs(rows) do
			table.insert(cells, {X = column.C, Z = row.C, W = column.W, D = row.W, Full = column.Full and row.Full, I = i, J = j})
		end
	end
	-- the full cells' centres and edges along each axis (what a staircase landing snaps to)
	local xCentres, zCentres, xEdges, zEdges = {}, {}, {}, {}
	for _, column in ipairs(columns) do
		if column.Full then
			table.insert(xCentres, column.C)
			table.insert(xEdges, column.C - column.W * 0.5)
			table.insert(xEdges, column.C + column.W * 0.5)
		end
	end
	for _, row in ipairs(rows) do
		if row.Full then
			table.insert(zCentres, row.C)
			table.insert(zEdges, row.C - row.W * 0.5)
			table.insert(zEdges, row.C + row.W * 0.5)
		end
	end
	cached = {Key = key, Cells = cells, XCentres = xCentres, ZCentres = zCentres, XEdges = xEdges, ZEdges = zEdges}
	cellCache[plot] = cached
	return cached
end

function M.Cells(plot)
	return Grid(plot).Cells
end

local function Nearest(list, v)
	local best, bestDistance
	for _, candidate in ipairs(list) do
		local distance = math.abs(candidate - v)
		if not best or distance < bestDistance then best, bestDistance = candidate, distance end
	end
	return best or v
end

--.. the nearest cell: x, z, width, depth
function M.SnapCell(plot, x, z)
	local best, bestDistance
	for _, cell in ipairs(M.Cells(plot)) do
		local distance = (cell.X - x) ^ 2 + (cell.Z - z) ^ 2
		if not best or distance < bestDistance then best, bestDistance = cell, distance end
	end
	if not best then return x, z, M.CELL, M.CELL end
	return best.X, best.Z, best.W, best.D
end

--.. stretch a floor tile (parts + Hitbox, all axis-aligned) to a cell's width / depth about its pivot
function M.FitTile(model, w, d)
	local hitbox = model.PrimaryPart
	if not hitbox then return end
	local base = hitbox.Size
	local sx, sz = w / math.max(base.X, 0.01), d / math.max(base.Z, 0.01)
	if math.abs(sx - 1) < 1e-4 and math.abs(sz - 1) < 1e-4 then return end
	local pivot = hitbox.CFrame
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(part.CFrame)
			part.Size = Vector3.new(part.Size.X * sx, part.Size.Y, part.Size.Z * sz)
			part.CFrame = pivot * (CFrame.new(rel.Position.X * sx, rel.Position.Y, rel.Position.Z * sz) * rel.Rotation)
		end
	end
end

--.. a staircase (IsStairs): its landing's open edge is the hitbox's -Z face. Snap so that face lies on a
--.. cell boundary along the way it faces and the 4-wide landing is centred in a cell across it, so the
--.. first upstairs tile butts against the landing exactly. x, z = the candidate centre; yaw in radians.
function M.SnapStairs(plot, x, z, yaw, size)
	local grid = Grid(plot)
	if #grid.XCentres == 0 or #grid.ZCentres == 0 then return x, z end
	local dirX, dirZ = -math.sin(yaw), -math.cos(yaw) -- the -Z face direction after the yaw
	local halfZ = size.Z * 0.5
	local faceX, faceZ = x + dirX * halfZ, z + dirZ * halfZ
	if math.abs(dirX) > 0.5 then
		faceX = Nearest(grid.XEdges, faceX)
		faceZ = Nearest(grid.ZCentres, faceZ)
	else
		faceZ = Nearest(grid.ZEdges, faceZ)
		faceX = Nearest(grid.XCentres, faceX)
	end
	return faceX - dirX * halfZ, faceZ - dirZ * halfZ
end

--.. half-stud key for matching a tile to its cell
function M.CellKey(x, z)
	return math.floor(x * 2 + 0.5) .. "," .. math.floor(z * 2 + 0.5)
end

--..Overlap rules (client + server)..--

--.. does a part found inside the placement box block it? Fixtures (anything not in plot.Placed) always
--.. do, and a tile never goes into a cell another tile holds. With collisions ON a build may not overlap
--.. another build and an upstairs tile may not cut through anything; with them OFF those pass. A tile
--.. and a build ignore each other on the ground (the tile slides under the wall, the wall stands on the tile)
function M.Blocks(part, holder, placingFloor, level, collisions)
	local model = part:FindFirstAncestorWhichIsA("Model")
	if not (holder and model and model:IsDescendantOf(holder)) then return true end
	local floorPart = model:GetAttribute("IsFloor") == true
	if placingFloor then
		if floorPart then return true end
		if level >= 2 then return collisions ~= false end
		return false
	end
	if floorPart then return false end
	return collisions ~= false
end

--.. upstairs, anything but a tile must stand on flooring: the centre and the four corners of the
--.. footprint (inset half a stud) each need a placed floor tile just under the build's bottom
function M.Supported(holder, targetCF, size, ignore)
	if not holder then return false end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {holder}
	local hx, hz = math.max(0, size.X * 0.5 - 0.5), math.max(0, size.Z * 0.5 - 0.5)
	local y = -size.Y * 0.5 - 0.3
	for _, offset in ipairs({Vector3.new(0, y, 0), Vector3.new(hx, y, hz), Vector3.new(-hx, y, hz), Vector3.new(hx, y, -hz), Vector3.new(-hx, y, -hz)}) do
		local point = targetCF:PointToWorldSpace(offset)
		local held = false
		for _, part in ipairs(workspace:GetPartBoundsInRadius(point, 0.35, params)) do
			local model = part:FindFirstAncestorWhichIsA("Model")
			if model and model:GetAttribute("IsFloor") == true and not (ignore and part:IsDescendantOf(ignore)) then
				held = true
				break
			end
		end
		if not held then return false end
	end
	return true
end

--.. an upstairs tile must join the floor: share an edge with a tile already on that level (boxes
--.. touching, any sizes), or be the cell straight off a staircase landing (the probe point half a stud
--.. beyond the landing's open edge, half a stud below its top). Returns ok, and whether any tile is up
--.. there yet (for the hint).
function M.FloorAnchored(holder, targetCF, size, level, ignore)
	if not holder then return false, false end
	local anyTile = false
	local ok = false
	for _, model in ipairs(holder:GetChildren()) do
		local hitbox = model ~= ignore and model:IsA("Model") and model.PrimaryPart or nil
		if hitbox then
			if model:GetAttribute("IsFloor") == true and model:GetAttribute("Level") == level then
				anyTile = true
				if not ok then
					local sb = hitbox.Size
					local d = targetCF:PointToObjectSpace(hitbox.Position)
					local halfX, halfZ = (size.X + sb.X) * 0.5, (size.Z + sb.Z) * 0.5
					if (math.abs(math.abs(d.X) - halfX) < 0.3 and math.abs(d.Z) < halfZ - 0.3)
						or (math.abs(math.abs(d.Z) - halfZ) < 0.3 and math.abs(d.X) < halfX - 0.3) then
						ok = true
					end
				end
			elseif not ok and model:GetAttribute("IsStairs") == true then
				local landingTop = -hitbox.Size.Y * 0.5 + M.LEVEL_HEIGHT + M.FLOOR_THICKNESS
				local probe = hitbox.CFrame:PointToWorldSpace(Vector3.new(0, landingTop - 0.5, -hitbox.Size.Z * 0.5 - 0.5))
				local lp = targetCF:PointToObjectSpace(probe)
				if math.abs(lp.X) <= size.X * 0.5 and math.abs(lp.Z) <= size.Z * 0.5 and math.abs(lp.Y) <= size.Y * 0.5 + 0.5 then
					ok = true
				end
			end
		end
	end
	return ok, anyTile
end

--.. 1500 -> "1,500"
--.. 2026-09-23 (economy): defences now cost up to 5B, so 100K and up abbreviate ("250K", "3M", "5B", one
--.. decimal when it is not a round number); below that the comma style stays ("25,000")
function M.FormatCost(n)
	n = math.floor(tonumber(n) or 0)
	local abs = math.abs(n)
	local sign = n < 0 and "-" or ""
	if abs >= 100000 then
		local suffixes = {{1e15, "Qa"}, {1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"}}
		for _, entry in ipairs(suffixes) do
			if abs >= entry[1] then
				local value = abs / entry[1]
				local text = value >= 100 and string.format("%d", math.floor(value)) or string.format("%.1f", math.floor(value * 10) / 10):gsub("%.0$", "")
				return sign .. text .. entry[2]
			end
		end
	end
	local s = tostring(abs)
	local k
	repeat
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return sign .. s
end

--.. the A_ / B_ / C_ collections: {{Letter = "A", Name = "Oak", X = 10}, ...} by letter, or nil
function M.VariantsOf(model)
	local raw = model:GetAttribute("Variants")
	if type(raw) ~= "string" or raw == "" then return nil end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(data) ~= "table" then return nil end
	local list = {}
	for letter, info in pairs(data) do
		if type(info) == "table" and type(letter) == "string" then
			table.insert(list, {Letter = letter, Name = tostring(info.name or letter), X = tonumber(info.x) or 0})
		end
	end
	table.sort(list, function(a, b) return a.Letter < b.Letter end)
	return #list > 0 and list or nil
end

function M.KeyOf(model, variant)
	return variant and (model.Name .. "_" .. variant.Letter) or model.Name
end

function M.DisplayNameOf(model, variant)
	if variant then
		local names = M.VARIANT_NAMES[model.Name]
		return names and names[variant.Letter] or M.SplitCamel(variant.Name)
	end
	return M.SplitCamel(model.Name)
end

--.. ReplicatedStorage.PlaceableBuilds (BuildService makes it at start; the client waits for it)
function M.TemplatesFolder(timeout)
	return ReplicatedStorage:WaitForChild(M.TEMPLATES, timeout or 60)
end

--.. the templates of one category, cheapest first
function M.BuildsIn(category)
	local folder = ReplicatedStorage:FindFirstChild(M.TEMPLATES)
	local sub = folder and folder:FindFirstChild(tostring(category))
	local list = {}
	if sub then
		for _, m in ipairs(sub:GetChildren()) do
			if m:IsA("Model") then table.insert(list, m) end
		end
	end
	table.sort(list, function(a, b)
		local ca, cb = tonumber(a:GetAttribute("Cost")) or 0, tonumber(b:GetAttribute("Cost")) or 0
		if ca ~= cb then return ca < cb end
		return tostring(a:GetAttribute("DisplayName") or a.Name) < tostring(b:GetAttribute("DisplayName") or b.Name)
	end)
	return list
end

--.. the template with this Key, in any category
function M.Find(key)
	local folder = ReplicatedStorage:FindFirstChild(M.TEMPLATES)
	if not folder or type(key) ~= "string" then return nil end
	for _, sub in ipairs(folder:GetChildren()) do
		local m = sub:FindFirstChild(key)
		if m and m:IsA("Model") then return m end
	end
	return nil
end

--..Defence limits (2026-09-19, user: "u can place 3 of each defense ... towers only 1 (max 1 freeze
--.. tower and 1 tesla coil) ... only 1 boost pad ... every base expansion upgrade, limits for each
--.. defense increases by 1 except for boost pad - that limit always stays at 1")
--.. A defence = a template in LIMITED_CATEGORY. Its limit = its base + the plot's expansion level
--.. (PlotUpgrades 0..6), except the LIMIT_FIXED keys, which never grow. BuildService enforces it on
--.. Place only (never on a move or a base-save restore, so nobody loses builds they already have)
--.. and publishes the player attributes BuildCount_<Key> / BuildLimit_<Key>; the build cards draw
--.. their white "[X/Y]" from those.
M.LIMITED_CATEGORY = "Defences"
M.LIMIT_BASE_DEFAULT = 3
M.LIMIT_BASE = {FreezeTower = 1, TeslaCoil = 1, BoostPad = 1} -- the two towers, and the boost pad
M.LIMIT_FIXED = {BoostPad = true}                              -- never grows with the plot
M.COUNT_ATTR = "BuildCount_"
M.LIMIT_ATTR = "BuildLimit_"

--.. true when builds of this key are capped (its template is a defence)
function M.IsLimited(key)
	local t = M.Find(key)
	return t ~= nil and t:GetAttribute("Category") == M.LIMITED_CATEGORY
end

--.. how many of this key one base at expansion level plotLevel may hold, or nil when uncapped
function M.LimitOf(key, plotLevel)
	if not M.IsLimited(key) then return nil end
	local base = M.LIMIT_BASE[key] or M.LIMIT_BASE_DEFAULT
	if M.LIMIT_FIXED[key] then return base end
	return base + math.max(0, math.floor(tonumber(plotLevel) or 0))
end

--..Strength unlocks (2026-09-23 economy plan, section 3 "Defences": each unlock tier is one biome of
--.. strength - the kg base of the biome the build is meant to be bought in - so the defences arrive
--.. one tier at a time as the player's Strength climbs x10 per biome). A key that is not listed is
--.. free (0). BuildService stamps the template attribute Unlock = UnlockOf(key) and refuses Place
--.. while Data.Strength < Unlock ("Needs 💪3K strength"); BuildMenuClient dims those cards with a
--.. "🔒 💪3K" label and refuses the pick. Moves, sells and base-save restores never check it.
M.UNLOCK_STRENGTH = {
	Catapult = 300, StoneWall = 300,
	Turret = 3000,
	LaserGate = 30000, IronWall = 30000,
	FreezeTower = 300000,
	TeslaCoil = 3000000,
	Mortar = 30000000, BarbedStoneWall = 30000000,
	Minigun = 300000000,
}

--.. the Strength a build needs before it can be placed (0 = none); a variant key "Tree_A" asks for "Tree"
function M.UnlockOf(key)
	if type(key) ~= "string" then return 0 end
	local unlock = M.UNLOCK_STRENGTH[key]
	if unlock == nil then
		local base = key:match("^(.-)_%u$")
		unlock = base and M.UNLOCK_STRENGTH[base]
	end
	return math.max(0, tonumber(unlock) or 0)
end

function M.IsUnlocked(strength, key)
	return (tonumber(strength) or 0) >= M.UnlockOf(key)
end

return M
