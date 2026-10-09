--[[
	BuildService  (Script, ServerScriptService)  2026-09-10
	Server half of build mode. At start it turns ServerStorage.Builds/<Category>/<Model> into placeable
	templates in ReplicatedStorage.PlaceableBuilds/<Category>/<Key>: variant collections are split by
	their A_ / B_ / C_ part prefix (one build each), every part is anchored, an invisible "Hitbox"
	PrimaryPart wraps the bounding box (the overlap test and the placement height use it), the
	authoring attributes (Notes, Pivot_*, State_* ...) are dropped and Key / Category / DisplayName /
	Cost / Source / IsFloor / IsStairs are stamped (BuildCatalog).
	GRASS TILES: every plot gets plot.GrassTiles, round(Size / BuildCatalog.CELL) equal cells per axis (the
	plot's colour / material / stud top and its checker Texture at one period per cell, columns centred on the plot's
	X, rows hung off the back edge PlotUpgradeService keeps fixed, the grid ending exactly on the edges)
	whose top is the ground walking surface. A placed Flooring tile fills exactly one cell (FitTile) and
	RefreshGrass makes that grass tile invisible and non-collidable - nothing of the grass shows where a
	tile is; it comes back when the tile leaves. Rebuilt when the plot is resized.
	Remotes.requestBuildPlacement(key, cframe, {Collisions = bool}) -> ok, reason. Own plot, standing at the base, only the
	client's X / Z + yaw (+ which floor) are trusted, the footprint must stay inside the plot, nothing
	may overlap plot.Placed (eggs, cucumbers, builds) or the plot's fixtures. A Flooring tile snaps to
	a full grid cell; a Staircase (IsStairs) snaps so its landing's open edge lies on a cell boundary.
	Then the Cost is taken from the player's Cash (DataService) and the build is cloned into
	plot.Placed with attributes Owner / BuildKey / Category / DisplayName / Cost / Level / PlotX / PlotZ
	/ Yaw and the tag "PlacedBuild". Cash are charged at placement, never on the pick.
	Remotes.requestBuildMove(model, cframe, {Collisions = bool}) -> ok, reason: the same validation for one of the player's
	own placed builds (its own parts ignored), then it is pivoted there for free.
	Remotes.requestBuildSell(model) -> ok, refund | reason: one of the player's own placed builds is
	destroyed and BuildCatalog.SELL_REFUND of its Cost is paid back.
	FLOORS: a build lands on the floor the player stands on (BuildCatalog.PlayerLevel); the level is
	read back from the requested height and may never be above the player's. A tile's TOP and a
	build's BOTTOM both sit at BuildCatalog.SurfaceY(level): the grass top on the ground, LEVEL_HEIGHT
	+ FLOOR_THICKNESS above it upstairs (tiles rest on the 12-stud walls, flush with the Staircase
	landing). Tiles and builds ignore each other in the overlap test on the ground (Blocks); upstairs a
	tile blocks on everything, anything else must have flooring under its whole footprint
	(Supported), and a tile must JOIN the upstairs floor (FloorAnchored: edge to edge with a tile
	already up there, or the cell straight off a staircase landing).
	Placed builds are NOT saved yet (nothing on a plot is). EggPlacement empties plot.Placed when the
	plot is released.
	EDGES + COLLISIONS (2026-09-10, later): a Flooring tile snaps to the nearest cell of ANY size and is
	stretched to it (BuildCatalog.FitTile), so the edge strips take flooring too. The Collisions option the
	client sends (the checkbox on the placing strip) is passed to BuildCatalog.Blocks: off, builds may
	intersect each other; fixtures always block and a tile never takes a held cell.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

--..Modules..--
local DataService = require(ServerStorage:WaitForChild("DataService"))
local BuildCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BuildCatalog"))

--..Config..--
local COLLISION_SHRINK = 0.96 -- hitbox fraction for the overlap test so edges may touch (keep in step with BuildMenuClient)
local PLACE_COOLDOWN = 0.15 -- seconds per player
local BOUNDS_EPSILON = 0.05
local AT_BASE_MARGIN = 6 -- studs outside the plot edge that still count as "at the base" (EggPlacement / BaseHUDController)
local KEEP_ATTRIBUTES = {Key = true, Category = true, DisplayName = true, Cost = true, Source = true, IsFloor = true, IsStairs = true}
local LOBBY = workspace:WaitForChild("Map"):WaitForChild("Lobby")
local PLOTS = LOBBY:WaitForChild("Plots")

--..Instances..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local function RemoteFunction(name)
	local remote = Remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = Remotes
	end
	return remote
end
local requestBuildPlacement = RemoteFunction(BuildCatalog.REMOTE)
local requestBuildMove = RemoteFunction(BuildCatalog.MOVE_REMOTE)
local requestBuildSell = RemoteFunction(BuildCatalog.SELL_REMOTE)
local Templates = ReplicatedStorage:FindFirstChild(BuildCatalog.TEMPLATES)
if Templates then
	Templates:ClearAllChildren()
else
	Templates = Instance.new("Folder")
	Templates.Name = BuildCatalog.TEMPLATES
end

--..Variables..--
local LastPlace = {} -- [player] = os.clock()

--..Templates..--
local function MakeTemplate(source, category, folder, variant)
	local model = source:Clone()
	local key = BuildCatalog.KeyOf(source, variant)
	model.Name = key
	if variant then
		local prefix = variant.Letter .. "_"
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and child.Name:sub(1, #prefix) ~= prefix then child:Destroy() end
		end
	end
	local isFloor = source:GetAttribute("IsFloor") == true
	local parts = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			parts += 1
			d.Anchored = true
			d.CanTouch = false
			if isFloor then d.CanCollide = true end -- a surface: always walkable
		end
	end
	if parts == 0 then
		model:Destroy()
		return nil
	end
	local cf, size = model:GetBoundingBox()
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = size
	hitbox.CFrame = CFrame.new(cf.Position) -- upright box around the build
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true -- the overlap test finds placed builds through it
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	for name in pairs(model:GetAttributes()) do
		if not KEEP_ATTRIBUTES[name] then model:SetAttribute(name, nil) end
	end
	model:SetAttribute("Key", key)
	model:SetAttribute("Category", category)
	model:SetAttribute("DisplayName", BuildCatalog.DisplayNameOf(source, variant))
	model:SetAttribute("Cost", BuildCatalog.CostOf(source))
	model:SetAttribute("Source", source.Name)
	model:SetAttribute("IsFloor", isFloor)
	model:SetAttribute("IsStairs", source:GetAttribute("IsStairs") == true)
	model.Parent = folder
	return model
end

local function BuildTemplates()
	local source = ServerStorage:WaitForChild(BuildCatalog.FOLDER, 30)
	if not source then
		warn("[BuildService] ServerStorage." .. BuildCatalog.FOLDER .. " is missing; build mode has nothing to sell")
		Templates.Parent = ReplicatedStorage
		return 0, 0
	end
	local builds, categories = 0, 0
	for _, sub in ipairs(source:GetChildren()) do
		if sub:IsA("Folder") then
			local folder = Instance.new("Folder")
			folder.Name = sub.Name
			for _, model in ipairs(sub:GetChildren()) do
				if model:IsA("Model") then
					local variants = BuildCatalog.VariantsOf(model)
					if variants then
						for _, variant in ipairs(variants) do
							if MakeTemplate(model, sub.Name, folder, variant) then builds += 1 end
						end
					elseif MakeTemplate(model, sub.Name, folder) then
						builds += 1
					end
				end
			end
			if #folder:GetChildren() > 0 then
				categories += 1
				folder.Parent = Templates
			else
				folder:Destroy()
			end
		elseif sub:IsA("Model") then
			warn(("[BuildService] %s sits directly in ServerStorage.%s; move it into a category subfolder (Walls / Defences / Garden / Fun) to sell it"):format(sub.Name, BuildCatalog.FOLDER))
		end
	end
	Templates.Parent = ReplicatedStorage
	return builds, categories
end

--..Plots..--
local function PlotOf(player)
	for _, plot in ipairs(PLOTS:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function HolderOf(plot)
	local holder = plot:FindFirstChild("Placed")
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = "Placed"
		holder.Parent = plot
	end
	return holder
end

--..Defence limits (2026-09-19): BuildCatalog.LimitOf(key, the owner's saved plot level). Checked in
--..Place only - a move keeps the same build, and a base-save restore must never lose anything, so a
--..base already over a limit keeps what it has and simply cannot place more of that one..--
local function PlotLevelOf(player)
	local data = DataService.GetData(player)
	return data and tonumber(data.PlotLevel) or 0
end

local function CountPlaced(plot, userId, key)
	local holder = plot and plot:FindFirstChild("Placed")
	local n = 0
	for _, m in ipairs(holder and holder:GetChildren() or {}) do
		if m:IsA("Model") and m:GetAttribute("BuildKey") == key and m:GetAttribute("Owner") == userId
			and CollectionService:HasTag(m, BuildCatalog.PLACED_TAG) then
			n += 1
		end
	end
	return n
end

--.. BuildCount_<Key> / BuildLimit_<Key> on the player for every capped build: the build cards draw
--.. their "[X/Y]" from these (the plot and its Placed folder can stream out on a client; these can't).
--.. Deferred, so a burst of changes (a restore, a clear) is one pass.
local publishPending = {}
local function PublishCounts(player)
	if not player or publishPending[player] then return end
	publishPending[player] = true
	task.defer(function()
		publishPending[player] = nil
		if player.Parent ~= Players then return end
		local plot = PlotOf(player)
		local level = PlotLevelOf(player)
		local folder = ReplicatedStorage:FindFirstChild(BuildCatalog.TEMPLATES)
		local sub = folder and folder:FindFirstChild(BuildCatalog.LIMITED_CATEGORY)
		for _, template in ipairs(sub and sub:GetChildren() or {}) do
			local key = template.Name
			local limit = BuildCatalog.LimitOf(key, level)
			if limit then
				player:SetAttribute(BuildCatalog.COUNT_ATTR .. key, plot and CountPlaced(plot, player.UserId, key) or 0)
				player:SetAttribute(BuildCatalog.LIMIT_ATTR .. key, limit)
			end
		end
	end)
end

local function PublishPlotOwner(plot)
	local userId = plot:GetAttribute("Owner")
	local player = type(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
	if player then PublishCounts(player) end
end

local function FixturesOf(plot)
	local fixtures = LOBBY:FindFirstChild("PlotFixtures")
	return fixtures and fixtures:FindFirstChild(plot.Name) or nil
end

--..Grass tiles..--
--.. every tile wears the plot's own look (user, 2026-09-12: "add back the texture ... like it did before"):
--.. the plot's colour, material and stud top, plus a copy of its top Texture at one period per cell. The
--.. plot had one period per 8 studs and a cell is ~8, so the checker reads exactly as it did and every
--.. tile starts a period at its own corner - seamless across the grid.
local function PlotTexture(plot)
	return plot:FindFirstChildOfClass("Texture")
end
local HIDE_DROP = 1 -- studs a hidden grass tile sinks into the slab: nothing of it (texture included) can ever z-fight a floor tile
local OVERLAP_MARGIN = 0.25 -- studs: a floor tile must reach this far into a grass cell to count as covering it (touching edges do not)

local function TileCFrame(plot, cx, cz, hidden)
	local surface = BuildCatalog.SurfaceY(plot, 1)
	return plot.CFrame * CFrame.new(cx, surface - BuildCatalog.GRASS_THICKNESS * 0.5 - (hidden and HIDE_DROP or 0), cz)
end

local function BuildGrass(plot)
	local folder = plot:FindFirstChild("GrassTiles")
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = "GrassTiles"
		folder.Parent = plot
	end
	local texture = PlotTexture(plot)
	for _, cell in ipairs(BuildCatalog.Cells(plot)) do
		local tile = Instance.new("Part")
		tile.Name = "Grass"
		tile.Size = Vector3.new(cell.W, BuildCatalog.GRASS_THICKNESS, cell.D)
		tile.CFrame = TileCFrame(plot, cell.X, cell.Z, false)
		tile.Color = plot.Color
		tile.Material = plot.Material
		tile.TopSurface = plot.TopSurface
		tile.BottomSurface = Enum.SurfaceType.Smooth
		tile.Anchored = true
		tile.CanCollide = true
		tile.CanQuery = false -- the placement rays aim at the plot slab, not at the grass
		tile.CanTouch = false
		tile:SetAttribute("CellX", cell.X)
		tile:SetAttribute("CellZ", cell.Z)
		tile:SetAttribute("Full", cell.Full)
		if texture then
			local t = texture:Clone()
			t.StudsPerTileU = cell.W -- one period of the plot's checker per cell
			t.StudsPerTileV = cell.D
			t.OffsetStudsU = 0
			t.OffsetStudsV = 0
			t.Parent = tile
		end
		tile.Parent = folder
	end
	return folder
end

--.. a grass tile disappears under a ground-floor Flooring tile - any tile whose cell the flooring covers by
--.. more than OVERLAP_MARGIN, not only the one whose centre matches (a plot resize regrids the cells and
--.. RefitTiles re-snaps the flooring, but this holds either way) - and comes back when the flooring goes.
--.. Hidden = invisible, texture off, no collision, sunk HIDE_DROP into the slab.
local function RefreshGrass(plot)
	local folder = plot:FindFirstChild("GrassTiles")
	if not folder then return end
	local holder = plot:FindFirstChild("Placed")
	local surface = BuildCatalog.SurfaceY(plot, 1)
	local covers = {} -- plot-space footprints of the ground-floor tiles (floor tiles never turn: yaw 0)
	if holder then
		for _, model in ipairs(holder:GetChildren()) do
			local hitbox = model:IsA("Model") and model:GetAttribute("IsFloor") == true and model.PrimaryPart or nil
			if hitbox then
				local lp = plot.CFrame:PointToObjectSpace(hitbox.Position)
				if math.abs(lp.Y + hitbox.Size.Y * 0.5 - surface) < 0.5 then
					table.insert(covers, {X = lp.X, Z = lp.Z, HalfW = hitbox.Size.X * 0.5, HalfD = hitbox.Size.Z * 0.5})
				end
			end
		end
	end
	local base = PlotTexture(plot)
	for _, tile in ipairs(folder:GetChildren()) do
		local cx, cz = tile:GetAttribute("CellX") or 0, tile:GetAttribute("CellZ") or 0
		local hw, hd = tile.Size.X * 0.5, tile.Size.Z * 0.5
		local hidden = false
		for _, c in ipairs(covers) do
			if (hw + c.HalfW) - math.abs(cx - c.X) > OVERLAP_MARGIN and (hd + c.HalfD) - math.abs(cz - c.Z) > OVERLAP_MARGIN then
				hidden = true
				break
			end
		end
		if tile:GetAttribute("Hidden") ~= hidden then
			tile:SetAttribute("Hidden", hidden)
			tile.Transparency = hidden and 1 or 0
			tile.CanCollide = not hidden
			tile.CFrame = TileCFrame(plot, cx, cz, hidden)
			local texture = tile:FindFirstChildOfClass("Texture")
			if texture then texture.Transparency = hidden and 1 or (base and base.Transparency or 0.8) end
		end
	end
end

--.. a plot resize regrids the cells (round(Size / CELL) per axis, so every cell changes size): every floor
--.. tile is re-snapped and re-fitted to the cell it now stands in and every staircase to the new cell edges,
--.. so nothing straddles two grass tiles (user, 2026-09-12: "grass overlapping with tile" after a plot change)
local function RefitTiles(plot)
	local holder = plot:FindFirstChild("Placed")
	if not holder then return 0 end
	local n = 0
	for _, model in ipairs(holder:GetChildren()) do
		if model:IsA("Model") and model.PrimaryPart and CollectionService:HasTag(model, BuildCatalog.PLACED_TAG) then
			local isFloor = model:GetAttribute("IsFloor") == true
			local isStairs = model:GetAttribute("IsStairs") == true
			if isFloor or isStairs then
				local hitbox = model.PrimaryPart
				local rel = plot.CFrame:ToObjectSpace(hitbox.CFrame)
				local _, yaw = rel:ToEulerAnglesYXZ()
				local x, z = rel.Position.X, rel.Position.Z
				local level = math.clamp(math.floor(tonumber(model:GetAttribute("Level")) or 1), 1, BuildCatalog.MAX_LEVELS)
				local surface = BuildCatalog.SurfaceY(plot, level)
				local target
				if isFloor then
					local cw, cd
					x, z, cw, cd = BuildCatalog.SnapCell(plot, x, z)
					BuildCatalog.FitTile(model, cw, cd)
					yaw = 0
					target = plot.CFrame * CFrame.new(x, surface - hitbox.Size.Y * 0.5, z)
				else
					x, z = BuildCatalog.SnapStairs(plot, x, z, yaw, hitbox.Size)
					target = plot.CFrame * CFrame.new(x, surface + hitbox.Size.Y * 0.5, z) * CFrame.Angles(0, yaw, 0)
				end
				model:PivotTo(target)
				model:SetAttribute("PlotX", x)
				model:SetAttribute("PlotZ", z)
				model:SetAttribute("Yaw", math.deg(yaw))
				n += 1
			end
		end
	end
	return n
end

local function WatchPlot(plot)
	local holder = HolderOf(plot)
	local function refresh() task.defer(RefreshGrass, plot) end
	holder.ChildAdded:Connect(refresh)
	holder.ChildRemoved:Connect(refresh)
	--.. defence counts: every way a build comes or goes (place, sell, restore, clear, release) passes
	--.. through Placed; a new owner or a plot upgrade changes the limits
	local function publish() PublishPlotOwner(plot) end
	holder.ChildAdded:Connect(publish)
	holder.ChildRemoved:Connect(publish)
	plot:GetAttributeChangedSignal("Owner"):Connect(publish)
	plot:GetAttributeChangedSignal("PlotLevel"):Connect(publish)
	local pending = false
	local function rebuild()
		if pending then return end
		pending = true
		task.defer(function() -- Resize sets Size then CFrame; wait for both
			pending = false
			BuildGrass(plot)
			RefitTiles(plot)
			RefreshGrass(plot)
		end)
	end
	plot:GetPropertyChangedSignal("Size"):Connect(rebuild)
	plot:GetPropertyChangedSignal("CFrame"):Connect(rebuild)
	BuildGrass(plot)
	RefreshGrass(plot)
end

--..Placement..--
local function Footprint(size, yaw)
	local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
	return c * size.X + s * size.Z, s * size.X + c * size.Z
end

--.. everything both a placement and a move must pass; ignore = the model being moved
local function Validate(player, size, isFloor, isStairs, cframe, ignore, collisions)
	if typeof(cframe) ~= "CFrame" then return false, "Bad placement" end
	local plot = PlotOf(player)
	if not plot then return false, "You have no plot" end
	--.. must be standing at the base
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false, "No character" end
	local rp = plot.CFrame:PointToObjectSpace(root.Position)
	if math.abs(rp.X) > plot.Size.X * 0.5 + AT_BASE_MARGIN or math.abs(rp.Z) > plot.Size.Z * 0.5 + AT_BASE_MARGIN then
		return false, "Stand in your base to build"
	end
	--.. only the client's X / Z + yaw (+ floor) are trusted; a tile fills one grid cell, square; a staircase
	--.. lands its open landing edge on a cell boundary
	local relative = plot.CFrame:ToObjectSpace(cframe)
	local _, yaw = relative:ToEulerAnglesYXZ()
	local x, z = relative.Position.X, relative.Position.Z
	local cellW, cellD
	if isFloor then
		x, z, cellW, cellD = BuildCatalog.SnapCell(plot, x, z)
		size = Vector3.new(cellW, size.Y, cellD) -- the tile stretches to its cell (an edge strip is narrower)
		yaw = 0
	elseif isStairs then
		x, z = BuildCatalog.SnapStairs(plot, x, z, yaw, size)
	end
	local fx, fz = Footprint(size, yaw)
	if math.abs(x) + fx * 0.5 > plot.Size.X * 0.5 + BOUNDS_EPSILON or math.abs(z) + fz * 0.5 > plot.Size.Z * 0.5 + BOUNDS_EPSILON then
		return false, "Keep it inside your plot"
	end
	--.. which floor: read back from the requested height (a tile's top, a build's bottom), never above
	--.. the floor the player stands on; a tile's top and a build's bottom both sit AT the surface
	local edge = isFloor and (relative.Position.Y + size.Y * 0.5) or (relative.Position.Y - size.Y * 0.5)
	local level = BuildCatalog.LevelFromEdge(plot, edge)
	if isStairs and level >= 2 then return false, "Stairs go on the ground floor" end -- before the player check: never upstairs, wherever they stand
	if level > BuildCatalog.PlayerLevel(plot, root.Position) then return false, "Go up a staircase to build up there" end
	local surface = BuildCatalog.SurfaceY(plot, level)
	local centreY = isFloor and (surface - size.Y * 0.5) or (surface + size.Y * 0.5)
	local target = plot.CFrame * CFrame.new(x, centreY, z) * CFrame.Angles(0, yaw, 0)
	--.. occupied? (placed eggs / cucumbers / builds and the plot's own fixtures; tiles and builds pass
	--.. each other on the ground; a moved build ignores itself)
	local holder = HolderOf(plot)
	local filter = {holder}
	local fixtures = FixturesOf(plot)
	if fixtures then table.insert(filter, fixtures) end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = filter
	for _, part in ipairs(workspace:GetPartBoundsInBox(target, size * COLLISION_SHRINK, params)) do
		if not (ignore and part:IsDescendantOf(ignore)) and BuildCatalog.Blocks(part, holder, isFloor, level, collisions) then
			return false, "Something is in the way"
		end
	end
	if level >= 2 then
		if isFloor then
			--.. an upstairs tile must join the floor: next to a tile up there, or straight off a landing
			local anchored, anyTile = BuildCatalog.FloorAnchored(holder, target, size, level, ignore)
			if not anchored then return false, anyTile and "Place it next to another tile" or "Start at the top of a staircase" end
		elseif not BuildCatalog.Supported(holder, target, size, ignore) then
			return false, "Needs flooring under it"
		end
	end
	return true, {Plot = plot, Holder = holder, Target = target, Level = level, X = x, Z = z, Yaw = yaw, W = cellW, D = cellD}
end

local function Stamp(model, key, fit)
	model:SetAttribute("BuildKey", key)
	model:SetAttribute("Level", fit.Level)
	model:SetAttribute("PlotX", fit.X)
	model:SetAttribute("PlotZ", fit.Z)
	model:SetAttribute("Yaw", math.deg(fit.Yaw))
end

local function Options(options)
	return type(options) == "table" and options.Collisions ~= false
end

local function Place(player, key, cframe, options)
	local template = BuildCatalog.Find(key)
	if not template or not template.PrimaryPart then return false, "Unknown build" end
	local now = os.clock()
	if LastPlace[player] and now - LastPlace[player] < PLACE_COOLDOWN then return false, "Too fast" end
	--.. defence limits (2026-09-19): checked before the spot and before any Cash moves
	local limit = BuildCatalog.LimitOf(key, PlotLevelOf(player))
	local have = 0
	if limit then
		have = CountPlaced(PlotOf(player), player.UserId, key)
		if have >= limit then
			return false, ("%s limit reached [%d/%d]"):format(tostring(template:GetAttribute("DisplayName") or key), have, limit)
		end
	end
	local isFloor = template:GetAttribute("IsFloor") == true
	local ok, fit = Validate(player, template.PrimaryPart.Size, isFloor, template:GetAttribute("IsStairs") == true, cframe, nil, Options(options))
	if not ok then return false, fit end
	--.. pay
	local cost = math.max(0, tonumber(template:GetAttribute("Cost")) or 0)
	local cash = DataService.Get(player, "Cash")
	if cash == nil then return false, "Your data is still loading" end
	if cash < cost then return false, ("Need $%s more"):format(BuildCatalog.FormatCost(cost - cash)) end
	LastPlace[player] = now
	if cost > 0 then DataService.Increment(player, "Cash", -cost) end
	--.. place
	local placed = template:Clone()
	if isFloor and fit.W then BuildCatalog.FitTile(placed, fit.W, fit.D) end
	placed:PivotTo(fit.Target)
	placed:SetAttribute("Owner", player.UserId)
	Stamp(placed, key, fit)
	CollectionService:AddTag(placed, BuildCatalog.PLACED_TAG)
	placed.Parent = fit.Holder
	print(("[BuildService] %s placed %s on %s for %s Cash (%.1f, %.1f, yaw %d, level %d)"):format(player.Name, key, fit.Plot.Name, BuildCatalog.FormatCost(cost), fit.X, fit.Z, math.round(math.deg(fit.Yaw)), fit.Level))
	if limit then return true, have + 1, limit end -- the client drops the build off the mouse at the limit
	return true
end

--.. one of the player's own placed builds, or nil + reason
local function OwnBuild(player, model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not CollectionService:HasTag(model, BuildCatalog.PLACED_TAG) then return nil, "Not a build" end
	if not model.PrimaryPart then return nil, "Can't touch that" end
	local plot = PlotOf(player)
	if not plot or model.Parent ~= plot:FindFirstChild("Placed") or model:GetAttribute("Owner") ~= player.UserId then return nil, "Not yours" end
	return plot
end

local function Move(player, model, cframe, options)
	local plot, reason = OwnBuild(player, model)
	if not plot then return false, reason end
	local now = os.clock()
	if LastPlace[player] and now - LastPlace[player] < PLACE_COOLDOWN then return false, "Too fast" end
	local key = model:GetAttribute("BuildKey")
	local isFloor = model:GetAttribute("IsFloor") == true
	local ok, fit = Validate(player, model.PrimaryPart.Size, isFloor, model:GetAttribute("IsStairs") == true, cframe, model, Options(options))
	if not ok then return false, fit end
	LastPlace[player] = now
	if isFloor and fit.W then BuildCatalog.FitTile(model, fit.W, fit.D) end
	model:PivotTo(fit.Target)
	Stamp(model, key, fit)
	RefreshGrass(plot)
	print(("[BuildService] %s moved %s on %s to (%.1f, %.1f, yaw %d, level %d)"):format(player.Name, tostring(key), plot.Name, fit.X, fit.Z, math.round(math.deg(fit.Yaw)), fit.Level))
	return true
end

local function Sell(player, model)
	local plot, reason = OwnBuild(player, model)
	if not plot then return false, reason end
	local now = os.clock()
	if LastPlace[player] and now - LastPlace[player] < PLACE_COOLDOWN then return false, "Too fast" end
	if not DataService.IsLoaded(player) then return false, "Your data is still loading" end
	LastPlace[player] = now
	local name = tostring(model:GetAttribute("DisplayName") or model.Name)
	local refund = BuildCatalog.RefundOf(model:GetAttribute("Cost"))
	model:Destroy()
	if refund > 0 then DataService.Increment(player, "Cash", refund) end
	RefreshGrass(plot)
	print(("[BuildService] %s sold %s on %s for %s Cash"):format(player.Name, name, plot.Name, BuildCatalog.FormatCost(refund)))
	return true, refund, name
end

--..API for BaseSaveService (2026-09-12): a saved build comes back free and unvalidated at its saved pivot
--..(the level is saved too, the height is re-derived from it), an admin reset / a leaving player clears them..--
local function RestoreBuild(player, plot, key, pivot, level)
	local template = BuildCatalog.Find(key)
	if not template or not template.PrimaryPart then return nil, "Unknown build " .. tostring(key) end
	if typeof(pivot) ~= "CFrame" or not plot or not plot.Parent then return nil, "Bad restore" end
	local isFloor = template:GetAttribute("IsFloor") == true
	local isStairs = template:GetAttribute("IsStairs") == true
	local size = template.PrimaryPart.Size
	local relative = plot.CFrame:ToObjectSpace(pivot)
	local _, yaw = relative:ToEulerAnglesYXZ()
	local x, z = relative.Position.X, relative.Position.Z
	local cellW, cellD
	if isFloor then
		x, z, cellW, cellD = BuildCatalog.SnapCell(plot, x, z)
		size = Vector3.new(cellW, size.Y, cellD)
		yaw = 0
	elseif isStairs then
		x, z = BuildCatalog.SnapStairs(plot, x, z, yaw, size)
	end
	level = math.clamp(math.floor(tonumber(level) or 1), 1, BuildCatalog.MAX_LEVELS)
	local surface = BuildCatalog.SurfaceY(plot, level)
	local centreY = isFloor and (surface - size.Y * 0.5) or (surface + size.Y * 0.5)
	local target = plot.CFrame * CFrame.new(x, centreY, z) * CFrame.Angles(0, yaw, 0)
	local placed = template:Clone()
	if isFloor and cellW then BuildCatalog.FitTile(placed, cellW, cellD) end
	placed:PivotTo(target)
	placed:SetAttribute("Owner", player.UserId)
	Stamp(placed, key, {Level = level, X = x, Z = z, Yaw = yaw})
	CollectionService:AddTag(placed, BuildCatalog.PLACED_TAG)
	placed.Parent = HolderOf(plot)
	return placed
end

local function ClearBuilds(plot)
	local holder = plot and plot:FindFirstChild("Placed")
	if not holder then return 0 end
	local n = 0
	for _, model in ipairs(holder:GetChildren()) do
		if model:IsA("Model") and CollectionService:HasTag(model, BuildCatalog.PLACED_TAG) then
			model:Destroy()
			n += 1
		end
	end
	RefreshGrass(plot)
	return n
end

do
	local api = ServerStorage:FindFirstChild("BuildServiceAPI") or Instance.new("Folder")
	api.Name = "BuildServiceAPI"
	api.Parent = ServerStorage
	local restore = api:FindFirstChild("RestoreBuild") or Instance.new("BindableFunction")
	restore.Name = "RestoreBuild"
	restore.OnInvoke = RestoreBuild
	restore.Parent = api
	local clear = api:FindFirstChild("ClearBuilds") or Instance.new("BindableFunction")
	clear.Name = "ClearBuilds"
	clear.OnInvoke = ClearBuilds
	clear.Parent = api
end

--..Setup..--
local builds, categories = BuildTemplates()
local plots = 0
for _, plot in ipairs(PLOTS:GetChildren()) do
	if plot:IsA("BasePart") then
		WatchPlot(plot)
		plots += 1
	end
end

local function Guard(fn, label)
	return function(player, ...)
		local ok, result, a, b = pcall(fn, player, ...)
		if not ok then
			warn("[BuildService] " .. label .. ": " .. tostring(result))
			return false, "Something went wrong"
		end
		return result == true, a, b
	end
end
requestBuildPlacement.OnServerInvoke = Guard(Place, "place")
requestBuildMove.OnServerInvoke = Guard(Move, "move")
requestBuildSell.OnServerInvoke = Guard(Sell, "sell")

Players.PlayerRemoving:Connect(function(player) LastPlace[player] = nil publishPending[player] = nil end)
--.. the saved plot level arrives with the profile: publish the counts / limits then (and for anyone already in)
DataService.OnProfileLoaded(function(player) PublishCounts(player) end)
for _, player in ipairs(Players:GetPlayers()) do PublishCounts(player) end
print(("[BuildService] %d builds in %d categories ready (%s); grass tiles on %d plots"):format(builds, categories, BuildCatalog.TEMPLATES, plots))
