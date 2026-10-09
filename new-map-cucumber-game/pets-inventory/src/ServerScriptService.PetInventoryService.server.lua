--[[
	PetInventoryService  (Script, ServerScriptService)  2026-09-23
	Inactive (reserve) pets live in the player's INVENTORY - the hotbar along the bottom of the
	screen (HotbarClient) - as Tools, one per reserve pet (user: "make it so inactive pets are just
	in ur inventory"). The Pets menu is gone; this is how a pet goes in and out of the base now:
	  * OUT: the player clicks a pet tool (PetInventoryClient -> Remotes.PetInventory Equip) ->
	    PetService.Equip spawns it on the plot; its tool disappears.
	  * IN:  the pet info frame's "PUT IN INVENTORY" (PetInfoClient -> Unequip) -> PetService.Unequip
	    despawns it; a tool appears in the hotbar again.
	PetService stays the only owner of records / roster; this script only mirrors "owned but not in
	the roster" into Backpack tools and forwards the two roster actions.

	  Tool (RequiresHandle false, CanBeDropped false, tag "PetTool"): Name = display name,
	    attributes PetTool = true, PetId, Pet (species key), DisplayName, Rarity, Material,
	    Mutations (comma string), Income (cash/s), ToolTip "Let it out in your base"
	  Reconcile (every RECONCILE s per player, on profile load / reset, on respawn): reserve = owned -
	    roster, best income first, at most MAX_TOOLS tools; missing ones are created in the Backpack,
	    tools whose pet is no longer reserve (equipped, sold) are destroyed. Tools never carry state.
	  Remotes.PetInventory (RemoteFunction) {Action = "Equip" | "Unequip", PetId, Spot?} -> {Ok, Name?, Error?}
	    (PetService error codes: NotLoaded Closing CombatLocked NotOwned SlotsFull Unavailable NoPlot; here:
	    NoSpace = the Spot overlaps something placed, OffPlot = the Spot is not on the player's plot)
	  Spot (2026-09-23, placement ghost): a world point on the player's plot top. Checked here like a cucumber
	    placement - inside the plot (the pet's fitted footprint kept in), no overlap with plot.Placed - then
	    handed to PetService.Equip(player, id, spot), which spawns the pet there. No Spot = the old behaviour
	    (PetService picks the saved / a free spot).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PetsCatalog = require(Modules:WaitForChild("PetsCatalog"))
local PetStats = require(Modules:WaitForChild("PetStats"))
local DataService = require(ServerStorage:WaitForChild("DataService"))
local okBalance, PetBalance = pcall(function() return require(Modules:WaitForChild("PetBalance", 5)) end)
if not okBalance then PetBalance = nil end

local TAG = "PetTool"
local PLACED_HOLDER = "Placed" -- plot.Placed: cucumbers, builds, eggs (their hitboxes are CanQuery)
local PET_FIT = PetBalance and type(PetBalance.PET) == "table" and tonumber(PetBalance.PET.FIT) or 5
local EDGE_INSET = 1 -- studs a placed pet keeps from the plot edge (the client uses the same)
local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
local RECONCILE = 1.5 -- s between passes per player
local MAX_TOOLS = 40 -- reserve pets shown as tools (best income first); the rest wait until room frees
local REQUEST_PER_SECOND, REQUEST_BURST = 2, 4

--..PetService (installed by the pet system; looked up lazily)..--
local PetServiceCache = nil
local function PetServiceOf()
	if PetServiceCache ~= nil then return PetServiceCache or nil end
	local module = ServerStorage:FindFirstChild("PetService")
	if not module then return nil end
	local ok, result = pcall(require, module)
	PetServiceCache = ok and type(result) == "table" and result or false
	return PetServiceCache or nil
end
local function PetsReady()
	local pets = PetServiceOf()
	if not pets or type(pets.IsStarted) ~= "function" then return nil end
	local ok, started = pcall(pets.IsStarted)
	return (ok and started == true) and pets or nil
end

--..Remote..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local remote = Remotes:FindFirstChild("PetInventory")
if remote and not remote:IsA("RemoteFunction") then remote = nil end
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "PetInventory"
	remote.Parent = Remotes
end

--..Helpers..--
local function Finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function ValidId(id)
	return type(id) == "string" and #id >= 1 and #id <= 64
end

local StatsCache = {} -- [record] = stats (records are stable tables inside the profile)
local function StatsOf(record)
	local stats = StatsCache[record]
	if not stats then
		local ok, result = pcall(PetStats.Calculate, record)
		stats = ok and type(result) == "table" and result or {Valid = false, DisplayName = tostring(record.Pet), Rarity = "Common", Income = 0}
		StatsCache[record] = stats
	end
	return stats
end

local function MutationText(list)
	if type(list) == "string" then return list end
	local ok, text = pcall(PetStats.MutationString, list)
	return ok and type(text) == "string" and text or ""
end

--.. owned records that are not in the roster, best income first
local function ReserveOf(data)
	local base = type(data) == "table" and data.Base
	if type(base) ~= "table" or type(base.Pets) ~= "table" then return nil end
	local roster = {}
	for _, id in ipairs(type(base.PetRoster) == "table" and base.PetRoster or {}) do
		if type(id) == "string" then roster[id] = true end
	end
	local out, seen = {}, {}
	for _, rec in ipairs(base.Pets) do
		if type(rec) == "table" and ValidId(rec.Id) and not roster[rec.Id] and not seen[rec.Id] then
			seen[rec.Id] = true
			table.insert(out, rec)
		end
	end
	table.sort(out, function(a, b)
		local ia, ib = StatsOf(a).Income or 0, StatsOf(b).Income or 0
		if ia ~= ib then return ia > ib end
		return a.Id < b.Id
	end)
	return out
end

local function ToolsOf(player)
	local tools = {}
	local function scan(container)
		if not container then return end
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("PetTool") == true then
				local id = tool:GetAttribute("PetId")
				if ValidId(id) and not tools[id] then tools[id] = tool else tool:Destroy() end -- a duplicate never stays
			end
		end
	end
	scan(player:FindFirstChild("Backpack"))
	scan(player.Character)
	return tools
end

local function BuildTool(record)
	local stats = StatsOf(record)
	local entry = PetsCatalog.PETS[record.Pet]
	--.. 2026-09-23: the stats name carries the inherited traits ("Golden VOID NEON Tabby"); the catalog word is the fallback
	local display = (stats.Valid and type(stats.DisplayName) == "string" and stats.DisplayName ~= "" and stats.DisplayName)
		or (type(entry) == "table" and entry.DisplayName) or tostring(record.Pet)
	local tool = Instance.new("Tool")
	tool.Name = tostring(display)
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "Let it out in your base"
	tool:SetAttribute("PetTool", true)
	tool:SetAttribute("PetId", record.Id)
	tool:SetAttribute("Pet", tostring(record.Pet))
	tool:SetAttribute("DisplayName", tostring(display))
	tool:SetAttribute("Rarity", tostring(stats.Rarity or (type(entry) == "table" and entry.Rarity) or "Common"))
	tool:SetAttribute("Material", type(record.Material) == "string" and record.Material or "")
	tool:SetAttribute("Mutations", MutationText(record.Mutations))
	tool:SetAttribute("Income", Finite(stats.Income) and stats.Income or 0)
	CollectionService:AddTag(tool, TAG)
	return tool
end

local function Reconcile(player)
	if player.Parent ~= Players then return end
	if not DataService.IsLoaded(player) or DataService.IsClosing(player) then return end
	local data = DataService.GetData(player)
	local reserve = ReserveOf(data)
	if not reserve then return end
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end
	local tools = ToolsOf(player)
	local wanted = {}
	for i, rec in ipairs(reserve) do
		if i > MAX_TOOLS then break end
		wanted[rec.Id] = true
		local tool = tools[rec.Id]
		if not tool then
			BuildTool(rec).Parent = backpack
		elseif tool:GetAttribute("Income") ~= (StatsOf(rec).Income or 0) then
			tool:SetAttribute("Income", StatsOf(rec).Income or 0)
		end
	end
	for id, tool in pairs(tools) do
		if not wanted[id] then tool:Destroy() end
	end
end

local function SafeReconcile(player)
	local ok, err = pcall(Reconcile, player)
	if not ok then warn("[PetInventoryService] reconcile failed for " .. player.Name .. ": " .. tostring(err)) end
end

--..Requests..--
local Limiter = {}
local function TakeToken(player)
	local now = os.clock()
	local l = Limiter[player]
	if not l then
		l = {Tokens = REQUEST_BURST, Last = now}
		Limiter[player] = l
	end
	l.Tokens = math.min(REQUEST_BURST, l.Tokens + (now - l.Last) * REQUEST_PER_SECOND)
	l.Last = now
	if l.Tokens < 1 then return false end
	l.Tokens -= 1
	return true
end

--..Placement (the Spot of an Equip)..--
local function PlotOf(player)
	for _, plot in ipairs(Plots:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local FitCache = {} -- [pet key] = fitted bounding size (Vector3)
local function FittedSize(petKey)
	local cached = FitCache[petKey]
	if cached then return cached end
	local ok, size = pcall(function()
		local model = PetsCatalog.ModelOf(petKey)
		local _, raw = model:GetBoundingBox()
		local factor = math.min(1, PET_FIT / raw.X, PET_FIT / raw.Y, PET_FIT / raw.Z)
		return raw * factor
	end)
	local out = (ok and typeof(size) == "Vector3") and size or Vector3.new(PET_FIT, PET_FIT, PET_FIT)
	FitCache[petKey] = out
	return out
end

--.. a world point on the player's plot -> ok, spotOnPlotTop | false, code
local function ValidateSpot(player, petKey, spot)
	if typeof(spot) ~= "Vector3" or spot ~= spot or spot.Magnitude == math.huge then return false, "BadRequest" end
	local plot = PlotOf(player)
	if not plot then return false, "NoPlot" end
	local size = FittedSize(petKey)
	local lp = plot.CFrame:PointToObjectSpace(spot)
	if math.abs(lp.X) > plot.Size.X * 0.5 or math.abs(lp.Z) > plot.Size.Z * 0.5 then return false, "OffPlot" end
	local halfX = math.max(0, plot.Size.X * 0.5 - size.X * 0.5 - EDGE_INSET)
	local halfZ = math.max(0, plot.Size.Z * 0.5 - size.Z * 0.5 - EDGE_INSET)
	local x, z = math.clamp(lp.X, -halfX, halfX), math.clamp(lp.Z, -halfZ, halfZ)
	local top = plot.Size.Y * 0.5
	local holder = plot:FindFirstChild(PLACED_HOLDER)
	if holder then
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {holder}
		if #workspace:GetPartBoundsInBox(plot.CFrame * CFrame.new(x, top + size.Y * 0.5, z), size, overlap) > 0 then return false, "NoSpace" end
	end
	return true, (plot.CFrame * CFrame.new(x, top, z)).Position
end

local function PetKeyOf(player, petId)
	local data = DataService.GetData(player)
	local base = data and data.Base
	for _, rec in ipairs(type(base) == "table" and type(base.Pets) == "table" and base.Pets or {}) do
		if type(rec) == "table" and rec.Id == petId then return rec.Pet end
	end
	return nil
end

local function NameOf(player, petId)
	local data = DataService.GetData(player)
	local base = data and data.Base
	for _, rec in ipairs(type(base) == "table" and type(base.Pets) == "table" and base.Pets or {}) do
		if type(rec) == "table" and rec.Id == petId then
			local stats = StatsOf(rec)
			if stats.Valid and type(stats.DisplayName) == "string" and stats.DisplayName ~= "" then return stats.DisplayName end -- 2026-09-23: with its traits
			local entry = PetsCatalog.PETS[rec.Pet]
			return (type(entry) == "table" and entry.DisplayName) or tostring(rec.Pet)
		end
	end
	return "pet"
end

remote.OnServerInvoke = function(player, request)
	if typeof(player) ~= "Instance" or player.Parent ~= Players then return {Ok = false, Error = "BadRequest"} end
	if not TakeToken(player) then return {Ok = false, Error = "RateLimited"} end
	if type(request) ~= "table" or not ValidId(request.PetId) then return {Ok = false, Error = "BadRequest"} end
	local pets = PetsReady()
	if not pets then return {Ok = false, Error = "Unavailable"} end
	local action = request.Action
	local fn = action == "Equip" and pets.Equip or action == "Unequip" and pets.Unequip or nil
	if not fn then return {Ok = false, Error = "BadRequest"} end
	local name = NameOf(player, request.PetId)
	local spot = nil
	if action == "Equip" and request.Spot ~= nil then
		local petKey = PetKeyOf(player, request.PetId)
		if type(petKey) ~= "string" then return {Ok = false, Error = "NotOwned", Name = name} end
		local okSpot, result = ValidateSpot(player, petKey, request.Spot)
		if not okSpot then return {Ok = false, Error = result, Name = name} end
		spot = result
	end
	local ok, done, err = pcall(fn, player, request.PetId, spot)
	if not ok then
		warn("[PetInventoryService] PetService." .. action .. " failed: " .. tostring(done))
		return {Ok = false, Error = "Unavailable"}
	end
	if done ~= true then return {Ok = false, Error = err or "Unavailable", Name = name} end
	if action == "Equip" then
		local tools = ToolsOf(player)
		local tool = tools[request.PetId]
		if tool then tool:Destroy() end
	end
	task.defer(SafeReconcile, player)
	print(("[PetInventoryService] %s: %s %s"):format(player.Name, action == "Equip" and "let out" or "put away", tostring(name)))
	return {Ok = true, Name = name}
end

--..Lifecycle..--
local function Bind(player)
	player.CharacterAdded:Connect(function()
		task.delay(0.5, SafeReconcile, player) -- a respawn hands the player a fresh Backpack
	end)
end
for _, player in ipairs(Players:GetPlayers()) do Bind(player) end
Players.PlayerAdded:Connect(Bind)
Players.PlayerRemoving:Connect(function(player) Limiter[player] = nil end)
DataService.OnProfileLoaded(function(player) task.delay(1, SafeReconcile, player) end)
if type(DataService.OnProfileReset) == "function" then
	DataService.OnProfileReset(function(player) task.defer(SafeReconcile, player) end)
end

task.spawn(function()
	while true do
		task.wait(RECONCILE)
		if PetsReady() then
			for _, player in ipairs(Players:GetPlayers()) do SafeReconcile(player) end
		end
	end
end)

print(("[PetInventoryService] ready: reserve pets become hotbar tools (max %d, best income first), Remotes.PetInventory Equip / Unequip"):format(MAX_TOOLS))
