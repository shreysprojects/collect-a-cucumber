--[[
	PlotUpgradeService  (Script, ServerScriptService)
	Plot size upgrades + the fixtures that stand by every plot.

	SIZES
	  * every plot starts at level 0 (50 x 60 studs); the owner buys up to level 6 (70 x 85) on the
	    PlotUpgrade board. Levels / sizes / costs: ReplicatedStorage.Modules.PlotUpgrades
	  * saved as profile.Data.PlotLevel (DataService); applied when PlotService sets the plot's Owner
	    attribute, back to level 0 when the plot is released
	  * geometry: the BACK edge (against the east wall) and the centre line along the row stay put;
	    depth grows toward the lobby (FRONT_DIRECTION as in PlotService), width grows evenly
	  * plot attribute PlotLevel (replicated); remote Remotes.PlotUpgradeAction ("Buy") -> ok, message

	FIXTURES (one copy per plot, always at the same spot relative to the plot's edges)
	  * templates: workspace.PlotUpgrade (the plot upgrade board) and EVERY child of Map.Lobby.Props
	    (today: BenchPress with its LieSeat + Barbell, and GymPlatform holding the BenchUpgradeBoard).
	    Place them by hand next to ONE plot in Studio. At start each template's offset from the
	    nearest plot is measured (how far in front of / behind the front edge, how far in from the
	    side edge it hugs, height above the plot top, rotation), the template moves to
	    ServerStorage.PlotFixtureTemplates and a copy is stood by every plot with the same offsets.
	    After every resize the copies are moved again, so they keep that corner at any plot size
	  * copies live in Map.Lobby.PlotFixtures/<plot name>/ and carry attribute Plot = plot name (on the
	    copy and on every Model inside it); tags are kept. The PlotUpgrade copy gets tag
	    "PlotUpgradeBoard" (PlotUpgradeClient), a copy holding a LieSeat gets tag "PlotBench"
	    (BenchTierClient), and after a move every Barbell inside gets its RackCFrame attribute
	    refreshed (BenchServer / BarbellClient return the bar there)
	  * Studio dev hook: workspace:SetAttribute("PlotUpgradeDev", "Plot 1:3") sets that plot (and its
	    owner's saved level) to level 3
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--..Modules..--
local DataService = require(ServerStorage:WaitForChild("DataService"))
local PlotUpgrades = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlotUpgrades"))

--..Config..--
local LOBBY = workspace:WaitForChild("Map"):WaitForChild("Lobby")
local PLOTS = LOBBY:WaitForChild("Plots")
local FRONT_DIRECTION = Vector3.new(-1, 0, 0) -- world direction from a plot's centre to its front edge (keep in step with PlotService)
local BOARD_TEMPLATE_NAME = "PlotUpgrade" -- the hand-placed plot upgrade board in workspace
local PROPS_FOLDER = "Props" -- Map.Lobby.Props: every child is a per-plot fixture template
local FIXTURES_FOLDER = "PlotFixtures"
local TEMPLATES_FOLDER = "PlotFixtureTemplates"
local BOARD_TAG = "PlotUpgradeBoard"
local BENCH_TAG = "PlotBench"
local BUY_REACH = 40 -- studs; the buyer must be this close to their own board
local BUY_COOLDOWN = 0.3

--..Remotes..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local Action = Remotes:FindFirstChild("PlotUpgradeAction")
if not Action then
	Action = Instance.new("RemoteFunction")
	Action.Name = "PlotUpgradeAction"
	Action.Parent = Remotes
end

--..State..--
local Info = {} -- [plot] = {Back, Sign, Level, Folder, Fixtures = {[templateName] = copy}, Board = copy of the PlotUpgrade template}
local Templates = {} -- {Name, Model (in ServerStorage), Offset = {Side, FromSide, FromFront, Up, Rot}}
local LastBuy = {} -- [player] = os.clock()

--..Geometry..--
local function Capture(plot)
	local zDot = plot.CFrame.ZVector:Dot(FRONT_DIRECTION)
	if math.abs(zDot) < 0.9 then
		warn(("[PlotUpgrade] %s: its depth axis (local Z) does not run along FRONT_DIRECTION; sizes may come out sideways"):format(plot.Name))
	end
	local sign = zDot >= 0 and 1 or -1
	Info[plot] = {
		Back = plot.CFrame:PointToWorldSpace(Vector3.new(0, 0, -sign * plot.Size.Z * 0.5)),
		Sign = sign,
		Level = nil,
		Folder = nil,
		Fixtures = {},
		Board = nil,
	}
end

local function FixtureCFrame(plot, offset)
	local info = Info[plot]
	local lx = offset.Side * (plot.Size.X * 0.5 - offset.FromSide)
	local lz = info.Sign * (plot.Size.Z * 0.5 - offset.FromFront)
	return plot.CFrame * CFrame.new(lx, plot.Size.Y * 0.5 + offset.Up, lz) * offset.Rot
end

local function RefreshRacks(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") and (d.Name == "Barbell" or CollectionService:HasTag(d, "Barbell")) then
			local root = d.PrimaryPart or d:FindFirstChild("Bar")
			if root then d:SetAttribute("RackCFrame", root.CFrame) end
		end
	end
end

local function PlaceFixtures(plot)
	local info = Info[plot]
	for _, t in ipairs(Templates) do
		local copy = info.Fixtures[t.Name]
		if copy and copy.Parent then
			copy:PivotTo(FixtureCFrame(plot, t.Offset))
			RefreshRacks(copy)
		end
	end
end

local function Resize(plot, level)
	local info = Info[plot]
	level = PlotUpgrades.Clamp(level)
	local width, depth = PlotUpgrades.Size(level)
	plot.Size = Vector3.new(width, plot.Size.Y, depth)
	plot.CFrame = CFrame.new(info.Back + plot.CFrame.ZVector * (info.Sign * depth * 0.5)) * plot.CFrame.Rotation
	info.Level = level
	plot:SetAttribute("PlotLevel", level)
	PlaceFixtures(plot)
end

--..Fixtures..--
local function PivotOf(inst)
	if inst:IsA("Model") then return inst:GetPivot() end
	return inst.CFrame
end

local function MeasureTemplate(template)
	--.. reference plot = the one the template stands on or closest to
	local pivot = PivotOf(template)
	local best, bestDist
	for plot in pairs(Info) do
		local lp = plot.CFrame:PointToObjectSpace(pivot.Position)
		local dx = math.max(0, math.abs(lp.X) - plot.Size.X * 0.5)
		local dz = math.max(0, math.abs(lp.Z) - plot.Size.Z * 0.5)
		local dist = dx * dx + dz * dz
		if not best or dist < bestDist then best, bestDist = plot, dist end
	end
	if not best then return nil end
	local info = Info[best]
	local lp = best.CFrame:PointToObjectSpace(pivot.Position)
	return {
		Side = lp.X >= 0 and 1 or -1, -- which side edge (local X sign) the fixture hugs
		FromSide = best.Size.X * 0.5 - math.abs(lp.X), -- studs in from that edge (negative = outside)
		FromFront = best.Size.Z * 0.5 - info.Sign * lp.Z, -- studs behind the front edge (negative = in front, on the walkway)
		Up = pivot.Position.Y - (best.Position.Y + best.Size.Y * 0.5), -- pivot height above the plot top
		Rot = best.CFrame.Rotation:Inverse() * pivot.Rotation,
	}, best
end

local function Stamp(inst, plotName)
	inst:SetAttribute("Plot", plotName)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("Model") then d:SetAttribute("Plot", plotName) end
	end
end

local function HoldsLieSeat(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("Seat") and CollectionService:HasTag(d, "LieSeat") then return true end
	end
	return false
end

local function MakeFixture(plot, t)
	local info = Info[plot]
	local copy = t.Model:Clone()
	copy.Name = t.Name
	Stamp(copy, plot.Name)
	if t.Name == BOARD_TEMPLATE_NAME then CollectionService:AddTag(copy, BOARD_TAG) end
	if HoldsLieSeat(copy) then CollectionService:AddTag(copy, BENCH_TAG) end
	copy:PivotTo(FixtureCFrame(plot, t.Offset))
	copy.Parent = info.Folder
	RefreshRacks(copy)
	info.Fixtures[t.Name] = copy
	if t.Name == BOARD_TEMPLATE_NAME then info.Board = copy end
	return copy
end

local function CollectTemplates()
	local list = {}
	local stored = ServerStorage:FindFirstChild(TEMPLATES_FOLDER)
	local board = workspace:FindFirstChild(BOARD_TEMPLATE_NAME) or (stored and stored:FindFirstChild(BOARD_TEMPLATE_NAME))
	if board then list[#list + 1] = board else warn("[PlotUpgrade] no " .. BOARD_TEMPLATE_NAME .. " model found; plots get no upgrade board") end
	local props = LOBBY:FindFirstChild(PROPS_FOLDER)
	if props then
		for _, c in ipairs(props:GetChildren()) do
			if c:IsA("Model") or c:IsA("BasePart") then list[#list + 1] = c end
		end
	end
	return list
end

local function SetupFixtures()
	local stored = ServerStorage:FindFirstChild(TEMPLATES_FOLDER)
	if not stored then
		stored = Instance.new("Folder")
		stored.Name = TEMPLATES_FOLDER
		stored.Parent = ServerStorage
	end
	for _, template in ipairs(CollectTemplates()) do
		local offset, reference = MeasureTemplate(template)
		if offset then
			if template.Name == BOARD_TEMPLATE_NAME then
				CollectionService:RemoveTag(template, "GymBoard") -- it was cloned from a gym board once
				template:SetAttribute("Board", "PlotUpgrade")
			end
			template.Parent = stored -- the hand-placed original leaves the map; copies stand by every plot
			Templates[#Templates + 1] = {Name = template.Name, Model = template, Offset = offset}
			print(("[PlotUpgrade] fixture %s: measured from %s, %.1f studs in from the %s side edge, %.1f studs behind the front edge"):format(
				template.Name, reference.Name, offset.FromSide, offset.Side > 0 and "+" or "-", offset.FromFront))
		end
	end
	local folder = LOBBY:FindFirstChild(FIXTURES_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FIXTURES_FOLDER
		folder.Parent = LOBBY
	end
	folder:ClearAllChildren()
	local count = 0
	for plot, info in pairs(Info) do
		local sub = Instance.new("Folder")
		sub.Name = plot.Name
		sub.Parent = folder
		info.Folder = sub
		for _, t in ipairs(Templates) do
			MakeFixture(plot, t)
			count += 1
		end
	end
	print(("[PlotUpgrade] %d fixtures stood by %d plots"):format(count, #PLOTS:GetChildren()))
end

--..Owner sync..--
local function PlotOf(player)
	for plot in pairs(Info) do
		if plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function SyncOwner(plot)
	local userId = plot:GetAttribute("Owner")
	local player = userId and Players:GetPlayerByUserId(userId)
	if not player then
		Resize(plot, 0)
		return
	end
	task.spawn(function()
		local data = DataService.WaitForData(player)
		if plot:GetAttribute("Owner") ~= userId then return end -- released while the profile loaded
		Resize(plot, data and data.PlotLevel or 0)
	end)
end

--..Buying..--
local function Buy(player)
	local now = os.clock()
	if LastBuy[player] and now - LastBuy[player] < BUY_COOLDOWN then return false, "Slow down" end
	LastBuy[player] = now
	local plot = PlotOf(player)
	if not plot then return false, "You have no plot" end
	local data = DataService.GetData(player)
	if not data then return false, "Your data is still loading" end
	local level = PlotUpgrades.Clamp(data.PlotLevel or 0)
	local cost = PlotUpgrades.Cost(level)
	if not cost then return false, "Your plot is already max size" end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local board = Info[plot].Board
	if root and board and (root.Position - board:GetPivot().Position).Magnitude > BUY_REACH then
		return false, "Walk to your plot's upgrade board"
	end
	local cash = data.Cash or 0
	if cash < cost then
		return false, ("Need %s more Cash"):format(PlotUpgrades.Format(cost - cash))
	end
	DataService.Increment(player, "Cash", -cost)
	data.PlotLevel = level + 1
	DataService.RequestSave(player)
	Resize(plot, level + 1)
	local width, depth = PlotUpgrades.Size(level + 1)
	return true, ("Plot upgraded to %d x %d!"):format(width, depth)
end

--..Start..--
--.. LobbyLayoutServer re-lays the lobby at start; measure plots and templates only after it is done
do
	local deadline = os.clock() + 5
	while not LOBBY:GetAttribute("LayoutReady") and os.clock() < deadline do task.wait(0.05) end
end
for _, plot in ipairs(PLOTS:GetChildren()) do
	if plot:IsA("BasePart") then Capture(plot) end
end
SetupFixtures() -- measure against the edit-time (max size) plots, before anything is resized
for plot in pairs(Info) do
	plot:GetAttributeChangedSignal("Owner"):Connect(function() SyncOwner(plot) end)
	SyncOwner(plot) -- level 0 for free plots, the saved level for plots PlotService already handed out
end

Action.OnServerInvoke = function(player, kind)
	if kind ~= "Buy" then return false, "Unknown action" end
	local ok, result, message = pcall(Buy, player)
	if not ok then
		warn("[PlotUpgrade] " .. tostring(result))
		return false, "Something went wrong"
	end
	return result == true, message
end
Players.PlayerRemoving:Connect(function(player) LastBuy[player] = nil end)

--..Studio dev hook..--
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("PlotUpgradeDev"):Connect(function()
		local cmd = workspace:GetAttribute("PlotUpgradeDev")
		if type(cmd) ~= "string" then return end
		local name, level = cmd:match("^(.-):(%d+)$")
		local plot = name and PLOTS:FindFirstChild(name)
		if not plot or not Info[plot] then return end
		level = PlotUpgrades.Clamp(tonumber(level))
		local userId = plot:GetAttribute("Owner")
		local player = userId and Players:GetPlayerByUserId(userId)
		local data = player and DataService.GetData(player)
		if data then
			data.PlotLevel = level
			DataService.RequestSave(player)
		end
		Resize(plot, level)
		workspace:SetAttribute("PlotUpgradeDev", nil)
	end)
end
