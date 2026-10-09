--[[
	LobbyLayout  (ModuleScript, ServerStorage)
	Lays the lobby out from its plots. ServerScriptService.LobbyLayoutServer runs it at every
	server start (so the live game always follows the rule); after editing the plots in Studio
	(size, count, position, PlotIndex order) re-run it from the command bar:
	    require(game.ServerStorage.LobbyLayout).Apply()

	Rule (numbers in CONFIG):
	  * plots stand in PlotIndex order along the row (world Z), PLOT_GAP studs apart, the row
	    centred on the biome entrance; every plot's BACK edge (world +X) lies on the east wall's
	    inner face (BACK_GAP studs away)
	  * the north / south walls close END_MARGIN studs beyond the outer plots; the east wall stands
	    at the plots' back edge; the west wall keeps its entrance opening and runs to the corners;
	    north / south walls span outer face to outer face, east / west walls sit between them
	  * the floor and the invisible ceiling (map slab + lobby strips) cover the box the walls enclose
	  * side items, on each side of the entrance: a Shop SHOP_FROM_ENTRANCE studs from the entrance
	    edge, a Leaderboard LEADERBOARD_FROM_CORNER studs from the corner wall face, a Station
	    halfway between them (folders Lobby.Shops / Stations / Leaderboards; side = pivot Z against
	    the entrance centre; only Z moves, X / height / rotation are kept; several models of one
	    kind on one side move as a block)
	    Today: Shops = Sell Shop (north) / Buy Shop (south); Stations = Group Chest + QuestBoard (north,
	    they move together, keeping their spacing) / Zombie Den (south); Leaderboards = Smashes (north) /
	    Cash (south). Drop a new model into one of those folders and it joins that side's block.
	  * everything in Lobby.Props and the hand-placed workspace.PlotUpgrade board move with Plot 1
	Wall parts are recognised by where they stand, so their bands, colours and textures are kept.
]]
local LobbyLayout = {}

--..Config..--
local CONFIG = {
	PLOT_GAP = 2, -- studs between neighbouring plots along the row
	END_MARGIN = 3, -- studs from the outer plots to the north / south wall faces
	BACK_GAP = 0, -- studs from the plots' back edge to the east wall face (0 = touching)
	SHOP_FROM_ENTRANCE = 31.4, -- shop pivot -> entrance edge
	LEADERBOARD_FROM_CORNER = 11, -- leaderboard pivot -> corner wall face
	FLOOR_WEST_X = 1144.25, -- the lobby floor starts where the biome lane floor ends
	ENTRANCE = {74.09, 186.09}, -- opening in the west wall; used only if the wall segments cannot be read
}
LobbyLayout.CONFIG = CONFIG

--..Helpers..--
local function PivotOf(inst)
	if inst:IsA("Model") then return inst:GetPivot() end
	return inst.CFrame
end

local function MoveBy(inst, delta)
	if inst:IsA("Model") then
		inst:PivotTo(inst:GetPivot() + delta)
	elseif inst:IsA("BasePart") then
		inst.CFrame = inst.CFrame + delta
	end
end

--.. world-axis footprint of a part: minX, maxX, minZ, maxZ
local function Extents(part)
	local half, cf = part.Size * 0.5, part.CFrame
	local ex = math.abs(cf.XVector.X) * half.X + math.abs(cf.YVector.X) * half.Y + math.abs(cf.ZVector.X) * half.Z
	local ez = math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
	return cf.Position.X - ex, cf.Position.X + ex, cf.Position.Z - ez, cf.Position.Z + ez
end

--.. resize a part so its world X / Z footprint is sizeX by sizeZ, keeping height and rotation
local function SetFootprint(part, sizeX, sizeZ)
	local cf, s = part.CFrame, part.Size
	local newX, newZ = s.X, s.Z
	if math.abs(cf.XVector.X) > 0.9 then newX = sizeX elseif math.abs(cf.ZVector.X) > 0.9 then newZ = sizeX end
	if math.abs(cf.XVector.Z) > 0.9 then newX = sizeZ elseif math.abs(cf.ZVector.Z) > 0.9 then newZ = sizeZ end
	part.Size = Vector3.new(newX, s.Y, newZ)
end

local function SetCentreXZ(part, x, z)
	part.CFrame = CFrame.new(x, part.Position.Y, z) * part.CFrame.Rotation
end

local function SortedPlots(lobby)
	local list = {}
	for _, p in ipairs(lobby.Plots:GetChildren()) do
		if p:IsA("BasePart") then list[#list + 1] = p end
	end
	table.sort(list, function(a, b)
		local ia, ib = tonumber(a:GetAttribute("PlotIndex")), tonumber(b:GetAttribute("PlotIndex"))
		if ia and ib and ia ~= ib then return ia < ib end
		return a.Name < b.Name
	end)
	return list
end

--.. sort the lobby border parts into walls by where they stand
local function WallGroups(border, centreX, centreZ)
	local g = {North = {}, South = {}, East = {}, WestN = {}, WestS = {}, Strips = {}, Roof = nil}
	for _, part in ipairs(border:GetChildren()) do
		if part:IsA("BasePart") then
			local x1, x2, z1, z2 = Extents(part)
			if part.Name == "Lobby Roof North" or part.Name == "Lobby Roof South" then
				table.insert(g.Strips, part)
			elseif x2 - x1 > 1000 then
				g.Roof = part -- the map-wide invisible ceiling slab
			else
				local cx, cz = (x1 + x2) * 0.5, (z1 + z2) * 0.5
				if x2 - x1 > z2 - z1 then
					table.insert(cz < centreZ and g.North or g.South, part)
				elseif cx > centreX then
					table.insert(g.East, part)
				else
					table.insert(cz < centreZ and g.WestN or g.WestS, part)
				end
			end
		end
	end
	return g
end

--..Apply..--
function LobbyLayout.Apply()
	local lobby = workspace:WaitForChild("Map"):WaitForChild("Lobby")
	local border = workspace.Map:WaitForChild("Borders"):WaitForChild("Lobby Border")
	local plots = SortedPlots(lobby)
	assert(#plots > 0, "no plots in " .. lobby.Plots:GetFullName())
	local report = {}

	--.. where things are now
	local plot1Before = plots[1].Position
	local sumX = 0
	for _, p in ipairs(plots) do sumX += p.Position.X end
	local g = WallGroups(border, sumX / #plots, (CONFIG.ENTRANCE[1] + CONFIG.ENTRANCE[2]) * 0.5)
	local ez1, ez2 = CONFIG.ENTRANCE[1], CONFIG.ENTRANCE[2]
	if #g.WestN > 0 and #g.WestS > 0 then
		local _, _, _, nMax = Extents(g.WestN[1])
		local _, _, sMin = Extents(g.WestS[1])
		ez1, ez2 = nMax, sMin -- the opening between the two west wall segments
	end
	local centreZ = (ez1 + ez2) * 0.5
	local westX = (g.WestN[1] or g.WestS[1] or g.East[1]).Position.X
	local T = 8
	local sample = g.East[1] or g.North[1]
	if sample then
		local x1, x2, z1, z2 = Extents(sample)
		T = math.min(x2 - x1, z2 - z1)
	end

	--.. 1. plots: PlotIndex order along Z, PLOT_GAP apart, centred on the entrance, backs on one line
	local widths, depths, total, backX = {}, {}, -CONFIG.PLOT_GAP, -math.huge
	for i, p in ipairs(plots) do
		local x1, x2, z1, z2 = Extents(p)
		widths[i], depths[i] = z2 - z1, x2 - x1
		total += widths[i] + CONFIG.PLOT_GAP
		backX = math.max(backX, x2)
	end
	local z = centreZ - total * 0.5
	for i, p in ipairs(plots) do
		SetCentreXZ(p, backX - depths[i] * 0.5, z + widths[i] * 0.5)
		z += widths[i] + CONFIG.PLOT_GAP
	end
	local rowMinZ, rowMaxZ = centreZ - total * 0.5, centreZ + total * 0.5

	--.. 2. the box
	local northInner, southInner = rowMinZ - CONFIG.END_MARGIN, rowMaxZ + CONFIG.END_MARGIN
	local eastInner = backX + CONFIG.BACK_GAP
	local eastOuter = eastInner + T
	local westOuter = westX - T * 0.5
	local northOuter, southOuter = northInner - T, southInner + T

	--.. 3. walls (every band of each wall)
	for _, part in ipairs(g.North) do SetFootprint(part, eastOuter - westOuter, T) SetCentreXZ(part, (westOuter + eastOuter) * 0.5, northInner - T * 0.5) end
	for _, part in ipairs(g.South) do SetFootprint(part, eastOuter - westOuter, T) SetCentreXZ(part, (westOuter + eastOuter) * 0.5, southInner + T * 0.5) end
	for _, part in ipairs(g.East) do SetFootprint(part, T, southInner - northInner) SetCentreXZ(part, eastInner + T * 0.5, (northInner + southInner) * 0.5) end
	for _, part in ipairs(g.WestN) do SetFootprint(part, T, ez1 - northInner) SetCentreXZ(part, westX, (northInner + ez1) * 0.5) end
	for _, part in ipairs(g.WestS) do SetFootprint(part, T, southInner - ez2) SetCentreXZ(part, westX, (ez2 + southInner) * 0.5) end

	--.. 4. floor
	local floorFolder = lobby:FindFirstChild("Floor")
	local floor = floorFolder and floorFolder:FindFirstChildWhichIsA("BasePart")
	if floor then
		SetFootprint(floor, eastOuter - CONFIG.FLOOR_WEST_X, southOuter - northOuter)
		SetCentreXZ(floor, (CONFIG.FLOOR_WEST_X + eastOuter) * 0.5, (northOuter + southOuter) * 0.5)
	end

	--.. 5. ceiling: the map slab ends at the east face; strips cover what the slab does not
	for _, s in ipairs(g.Strips) do s:Destroy() end
	if g.Roof then
		local rx1, _, rz1, rz2 = Extents(g.Roof)
		SetFootprint(g.Roof, eastOuter - rx1, rz2 - rz1)
		SetCentreXZ(g.Roof, (rx1 + eastOuter) * 0.5, (rz1 + rz2) * 0.5)
		local function strip(name, z1, z2)
			local s = Instance.new("Part")
			s.Name = name
			s.Anchored = true
			s.CanCollide = g.Roof.CanCollide
			s.CanQuery = g.Roof.CanQuery
			s.Transparency = 1
			s.CastShadow = false
			s.Material = g.Roof.Material
			s.Color = g.Roof.Color
			s.Size = Vector3.new(eastOuter - westOuter, g.Roof.Size.Y, z2 - z1)
			s.CFrame = CFrame.new((westOuter + eastOuter) * 0.5, g.Roof.Position.Y, (z1 + z2) * 0.5)
			s.Parent = border
		end
		if northOuter < rz1 - 0.01 then strip("Lobby Roof North", northOuter, rz1) end
		if southOuter > rz2 + 0.01 then strip("Lobby Roof South", rz2, southOuter) end
	end

	--.. 6. side items
	local function sides(folderName)
		local north, south = {}, {}
		local folder = lobby:FindFirstChild(folderName)
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				if m:IsA("Model") or m:IsA("BasePart") then
					table.insert(PivotOf(m).Position.Z < centreZ and north or south, m)
				end
			end
		end
		local byZ = function(a, b) return PivotOf(a).Position.Z < PivotOf(b).Position.Z end
		table.sort(north, byZ)
		table.sort(south, byZ)
		return north, south
	end
	local function placeAnchor(list, index, targetZ) -- the item at index lands on targetZ, the rest keep their spacing
		if #list == 0 then return nil end
		local dz = targetZ - PivotOf(list[index]).Position.Z
		for _, m in ipairs(list) do MoveBy(m, Vector3.new(0, 0, dz)) end
		return targetZ
	end
	local function placeCentre(list, targetZ) -- the block's pivot centre lands on targetZ
		if #list == 0 then return nil end
		local lo, hi = PivotOf(list[1]).Position.Z, PivotOf(list[#list]).Position.Z
		local dz = targetZ - (lo + hi) * 0.5
		for _, m in ipairs(list) do MoveBy(m, Vector3.new(0, 0, dz)) end
		return targetZ
	end
	local shopsN, shopsS = sides("Shops")
	local stationsN, stationsS = sides("Stations")
	local boardsN, boardsS = sides("Leaderboards")
	--.. north of the entrance: items lie at Z < ez1, the corner is northInner
	local shopN = placeAnchor(shopsN, #shopsN, ez1 - CONFIG.SHOP_FROM_ENTRANCE)
	local boardN = placeAnchor(boardsN, 1, northInner + CONFIG.LEADERBOARD_FROM_CORNER)
	placeCentre(stationsN, ((shopN or ez1) + (boardN or northInner)) * 0.5)
	--.. south of the entrance: items lie at Z > ez2, the corner is southInner
	local shopS = placeAnchor(shopsS, 1, ez2 + CONFIG.SHOP_FROM_ENTRANCE)
	local boardS = placeAnchor(boardsS, #boardsS, southInner - CONFIG.LEADERBOARD_FROM_CORNER)
	placeCentre(stationsS, ((shopS or ez2) + (boardS or southInner)) * 0.5)

	--.. 7. props and the board template follow Plot 1
	local delta = plots[1].Position - plot1Before
	if delta.Magnitude > 1e-4 then
		local props = lobby:FindFirstChild("Props")
		if props then
			for _, m in ipairs(props:GetChildren()) do MoveBy(m, delta) end
		end
		local template = workspace:FindFirstChild("PlotUpgrade")
		if template then MoveBy(template, delta) end
	end

	report.Plots = #plots
	report.Row = {rowMinZ, rowMaxZ}
	report.Box = {West = westOuter, East = eastOuter, North = northOuter, South = southOuter}
	report.Entrance = {ez1, ez2}
	report.BackX = backX
	report.Plot1Delta = delta
	return report
end

return LobbyLayout
