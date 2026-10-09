--[[
	ManageService  (Script, ServerScriptService)  2026-09-23
	The server behind the MANAGE panel (StarterGui.CucumberMenus.ManagePanel, opened by the left
	menu's Manage button inside the base). Numbers: ReplicatedStorage.Modules.ManageConfig.

	  Remotes.ManageRequest (RemoteFunction)  client -> server, one table, one reply table:
	    {Action = "GetState"}                  -> {Ok = true, ServerTime, PlotLevel, Pets, Cucumbers, Zombies, OfflineToast?}
	    {Action = "SellPet", Id = <pet id>}    -> {Ok = true, Cash, Name} | {Ok = false, Error = <code>}
	    {Action = "SellCucumber", Id = <CucumberId>} -> same shape
	    Pets      = {Capacity, Count, Items = {{Id, Pet, DisplayName, Rarity, Material, Mutations = {...},
	                 Status, Income, SellValue}}}          -- the ACTIVE roster (what roams the base)
	    Cucumbers = {Capacity, Count, Items = {{Id, Name, TypeName, Zone, Golden, Material, Mutations,
	                 SizeTier, Rate, SellValue}}}         -- every PlacedCucumber of the plot (value desc)
	    Zombies   = {Level, Days, RequiredDays, Unlocked, OfflineRate, Multiplier, MaxSeconds, LastPayout?}
	    OfflineToast = {Cash, Seconds, Level} once, on the first GetState after a paid join
	  Remotes.ManageState (RemoteEvent) server -> owner {Kind = "Refresh", Reason} whenever something the
	    panel shows changed behind its back (a raid result, a cucumber the raid took, offline pay).

	  SELL PET       PetService.Sell(player, id) (the 2026-09-23 API: roster out, record deleted, model
	                 despawned, producer settled, delta with Removed) then Cash += ManageConfig.PetSellValue(Income).
	  SELL CUCUMBER  one of the player's own tagged PlacedCucumber models on their plot, not held by a
	                 zombie (StolenBy), never at night / during a raid: PetBuffService.ClearCucumber, the
	                 model is destroyed (IncomeService settles it on the tag removal, BaseSave forgets it on
	                 its next Collect) and Cash += ManageConfig.CucumberSellValue(model).
	  ZOMBIES        ZombieAPI.ThreatLevel (BindableFunction, ZombieRaidService 2026-09-23) gives the level a
	                 raid would be right now; ZombieAPI.RaidResult (BindableEvent) reports every night raid's
	                 end - "Survived" adds one day to Data.Defense.Survived["<level>"].
	  OFFLINE        Data.Defense = {Survived = {["1"] = n}, LastSeen, OfflineRate, Level, LastPayout?} - stamped
	                 every STAMP_PERIOD s while online and once more in DataService.OnBeforeClose (order 15,
	                 before IncomeService's flush at 20). On load: unlocked at the stamped level -> pay
	                 ManageConfig.OfflineEarnings(rate, now - LastSeen), remember it for the toast.
	  Studio hook: workspace attribute ManageDev = "survive" (add a survived day at the first player's
	  current level) | "reset" (clear their Defense record) | "offline:<seconds>" (pretend the first player
	  was away that long and pay it now) - edge-triggered, cleared after it runs.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ManageConfig = require(Modules:WaitForChild("ManageConfig"))
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))
local DataService = require(ServerStorage:WaitForChild("DataService"))

local PLACED_TAG = "PlacedCucumber"
local STAMP_PERIOD = 60 -- s between Defense stamps (LastSeen / OfflineRate / Level) while online
local TOAST_TTL = 600 -- s a paid-but-unshown offline toast waits for the client's first GetState

--..Optional modules (installed by other stages; looked up lazily, never required at load)..--
local Cache = {}
local function Lazy(name)
	return function()
		local cached = Cache[name]
		if cached ~= nil then return cached or nil end
		local module = ServerStorage:FindFirstChild(name)
		if not module then return nil end
		local ok, result = pcall(require, module)
		Cache[name] = ok and type(result) == "table" and result or false
		return Cache[name] or nil
	end
end
local PetServiceOf = Lazy("PetService")
local IncomeServiceOf = Lazy("IncomeService")
local PetBuffsOf = Lazy("PetBuffService")

local function Started(module)
	return module ~= nil and type(module.IsStarted) == "function" and select(2, pcall(module.IsStarted)) == true
end

--..Remotes..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local function remote(className, name)
	local r = Remotes:FindFirstChild(name)
	if r and not r:IsA(className) then
		warn(("[ManageService] Remotes.%s is a %s, expected a %s"):format(name, r.ClassName, className))
		r = nil
	end
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
local ManageRequest = remote("RemoteFunction", ManageConfig.REMOTE)
local ManageState = remote("RemoteEvent", ManageConfig.STATE_REMOTE)

local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

--..Helpers..--
local function Finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function PlotOf(player)
	for _, plot in ipairs(Plots:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function PlotLevelOf(player)
	local level = DataService.Get(player, "PlotLevel")
	if not Finite(level) then
		local plot = PlotOf(player)
		level = plot and plot:GetAttribute("PlotLevel") or 0
	end
	return Finite(level) and math.floor(level) or 0
end

local function PlacedOf(player)
	local list = {}
	local plot = PlotOf(player)
	local holder = plot and plot:FindFirstChild("Placed")
	if not holder then return list, plot end
	for _, model in ipairs(holder:GetChildren()) do
		if model:IsA("Model") and CollectionService:HasTag(model, PLACED_TAG) and model:GetAttribute("Owner") == player.UserId then
			table.insert(list, model)
		end
	end
	return list, plot
end

local function DefenseOf(data)
	if type(data) ~= "table" then return nil end
	local d = data.Defense
	if type(d) ~= "table" then
		d = {}
		data.Defense = d
	end
	if type(d.Survived) ~= "table" then d.Survived = {} end
	if not Finite(d.LastSeen) then d.LastSeen = 0 end
	if not Finite(d.OfflineRate) then d.OfflineRate = 0 end
	if not Finite(d.Level) then d.Level = 1 end
	return d
end

local function DaysAt(defense, level)
	local n = defense and defense.Survived[tostring(level)]
	return Finite(n) and math.max(0, math.floor(n)) or 0
end

local function ZombieAPI()
	local api = ServerStorage:FindFirstChild("ZombieAPI")
	return api
end

--.. the level a raid on this plot would be right now (ZombieRaidService's ThreatOf); nil when unknown
local function LiveThreat(player)
	local api = ZombieAPI()
	local fn = api and api:FindFirstChild("ThreatLevel")
	if not (fn and fn:IsA("BindableFunction")) then return nil end
	local ok, level, score, count = pcall(fn.Invoke, fn, player)
	if ok and Finite(level) then return math.floor(level), score, count end
	return nil
end

local function ThreatLevelOf(player, defense)
	local level = LiveThreat(player)
	if level then return level end
	return defense and Finite(defense.Level) and math.max(1, math.floor(defense.Level)) or 1
end

--.. the unboosted cucumber cash/s (the raid threat input) - what an absence pays on
local function OfflineRateOf(player)
	local income = IncomeServiceOf()
	if Started(income) then
		local ok, rate = pcall(income.GetThreatIncome, player)
		if ok and Finite(rate) and rate >= 0 then return rate end
	end
	local values = player:FindFirstChild("Data")
	local raw = values and values:FindFirstChild("CashPerSec")
	local v = raw and raw.Value
	return Finite(v) and math.max(0, v) or 0
end

local function IsCombatLocked(player)
	if workspace:GetAttribute("CyclePhase") == "Night" then return true end
	return player:GetAttribute("RaidLive") == true
end

local function Push(player, reason)
	if player.Parent == Players then ManageState:FireClient(player, {Kind = "Refresh", Reason = reason}) end
end

--..State..--
local PendingToast = {} -- [player] = {Cash, Seconds, Level, At}
local Limiter = {} -- [player] = {Tokens, Last}

local function TakeToken(player)
	local now = os.clock()
	local l = Limiter[player]
	if not l then
		l = {Tokens = ManageConfig.REQUEST_BURST, Last = now}
		Limiter[player] = l
	end
	l.Tokens = math.min(ManageConfig.REQUEST_BURST, l.Tokens + (now - l.Last) * ManageConfig.REQUEST_PER_SECOND)
	l.Last = now
	if l.Tokens < 1 then return false end
	l.Tokens -= 1
	return true
end

local function PetsState(player)
	local level = PlotLevelOf(player)
	local out = {Capacity = ManageConfig.PetCapacity(level), Count = 0, Items = {}}
	local pets = PetServiceOf()
	if not Started(pets) then return out end
	local ok, full = pcall(pets.GetFullState, player)
	if not ok or type(full) ~= "table" then return out end
	local equipped = {}
	for order, id in ipairs(type(full.EquippedIds) == "table" and full.EquippedIds or {}) do equipped[id] = order end
	out.Count = #(type(full.EquippedIds) == "table" and full.EquippedIds or {})
	for _, view in ipairs(type(full.Pets) == "table" and full.Pets or {}) do
		local order = type(view) == "table" and equipped[view.Id]
		if order then
			local stats = type(view.Stats) == "table" and view.Stats or {}
			table.insert(out.Items, {
				Id = view.Id, Pet = view.Pet, DisplayName = view.DisplayName or tostring(view.Pet), Rarity = view.Rarity or "Common",
				Material = type(view.Material) == "string" and view.Material or "", Mutations = type(view.Mutations) == "table" and view.Mutations or {},
				Status = view.Status, Income = Finite(stats.Income) and stats.Income or 0,
				SellValue = ManageConfig.PetSellValue(stats.Income), Order = order,
			})
		end
	end
	table.sort(out.Items, function(a, b) return a.Order < b.Order end)
	return out
end

local function CucumbersState(player)
	local level = PlotLevelOf(player)
	local out = {Capacity = ManageConfig.CucumberCapacity(level), Count = 0, Items = {}}
	local placed = PlacedOf(player)
	out.Count = #placed
	for _, model in ipairs(placed) do
		local rate = model:GetAttribute("BaseRate")
		if not Finite(rate) then
			local ok, v = pcall(CucumberValues.RateOfInstance, model)
			rate = ok and Finite(v) and v or 0
		end
		table.insert(out.Items, {
			Id = model:GetAttribute("CucumberId"), Name = model:GetAttribute("CucumberName") or model.Name,
			TypeName = model:GetAttribute("TypeName") or model.Name, Zone = model:GetAttribute("Zone") or "Spawn",
			Golden = model:GetAttribute("Golden") == true, Material = model:GetAttribute("Material"),
			Mutations = model:GetAttribute("Mutations") or "", SizeTier = model:GetAttribute("SizeTier"),
			Rate = rate, SellValue = ManageConfig.CucumberSellValue(model),
			Busy = model:GetAttribute("StolenBy") ~= nil,
		})
	end
	table.sort(out.Items, function(a, b)
		if a.SellValue ~= b.SellValue then return a.SellValue > b.SellValue end
		return tostring(a.Id) < tostring(b.Id)
	end)
	return out
end

local function ZombiesState(player, data)
	local defense = DefenseOf(data)
	local level = ThreatLevelOf(player, defense)
	local days = DaysAt(defense, level)
	return {
		Level = level, Days = days, RequiredDays = ManageConfig.OFFLINE.RequiredDays,
		Unlocked = days >= ManageConfig.OFFLINE.RequiredDays,
		OfflineRate = OfflineRateOf(player), Multiplier = ManageConfig.OFFLINE.Multiplier, MaxSeconds = ManageConfig.OFFLINE.MaxSeconds,
		LastPayout = type(defense.LastPayout) == "table" and defense.LastPayout or nil,
	}
end

local function GetState(player, data)
	local reply = {
		Ok = true, ServerTime = workspace:GetServerTimeNow(), PlotLevel = PlotLevelOf(player),
		Pets = PetsState(player), Cucumbers = CucumbersState(player), Zombies = ZombiesState(player, data),
	}
	local toast = PendingToast[player]
	if toast then
		PendingToast[player] = nil
		if os.clock() - toast.At <= TOAST_TTL then reply.OfflineToast = {Cash = toast.Cash, Seconds = toast.Seconds, Level = toast.Level} end
	end
	return reply
end

--..Actions..--
local function SellPet(player, id)
	if type(id) ~= "string" or #id < 1 or #id > 64 then return {Ok = false, Error = "BadRequest"} end
	local pets = PetServiceOf()
	if not Started(pets) or type(pets.Sell) ~= "function" then return {Ok = false, Error = "Unavailable"} end
	if IsCombatLocked(player) then return {Ok = false, Error = "CombatLocked"} end
	local ok, done, err, record, stats = pcall(pets.Sell, player, id)
	if not ok then
		warn("[ManageService] PetService.Sell failed: " .. tostring(done))
		return {Ok = false, Error = "Unavailable"}
	end
	if done ~= true then return {Ok = false, Error = err or "Unavailable"} end
	local value = ManageConfig.PetSellValue(type(stats) == "table" and stats.Income or 0)
	local name = type(stats) == "table" and stats.DisplayName or (type(record) == "table" and record.Pet) or "pet"
	if not DataService.Increment(player, "Cash", value) then
		warn(("[ManageService] %s sold pet %s but Cash could not be credited (%d)"):format(player.Name, tostring(id), value))
		return {Ok = false, Error = "NotLoaded"}
	end
	print(("[ManageService] %s sold pet %s (%s) for $%d"):format(player.Name, tostring(name), tostring(id), value))
	return {Ok = true, Cash = value, Name = tostring(name)}
end

local function SellCucumber(player, id)
	if type(id) ~= "string" or #id < 1 or #id > 64 then return {Ok = false, Error = "BadRequest"} end
	if not DataService.IsLoaded(player) then return {Ok = false, Error = "NotLoaded"} end
	if DataService.IsClosing(player) then return {Ok = false, Error = "Closing"} end
	if IsCombatLocked(player) then return {Ok = false, Error = "CombatLocked"} end
	local placed, plot = PlacedOf(player)
	if not plot then return {Ok = false, Error = "NoPlot"} end
	local model
	for _, m in ipairs(placed) do
		if m:GetAttribute("CucumberId") == id then model = m break end
	end
	if not model then return {Ok = false, Error = "NotFound"} end
	if model:GetAttribute("StolenBy") ~= nil or model:GetAttribute("CollectingBy") ~= nil then return {Ok = false, Error = "Busy"} end
	local value = ManageConfig.CucumberSellValue(model)
	local name = model:GetAttribute("CucumberName") or model.Name
	local buffs = PetBuffsOf()
	if buffs and type(buffs.ClearCucumber) == "function" then pcall(buffs.ClearCucumber, model, "Sold") end
	CollectionService:RemoveTag(model, PLACED_TAG) -- IncomeService settles what it earned up to now
	model:Destroy()
	if not DataService.Increment(player, "Cash", value) then
		warn(("[ManageService] %s sold %s but Cash could not be credited (%d)"):format(player.Name, tostring(name), value))
		return {Ok = false, Error = "NotLoaded"}
	end
	print(("[ManageService] %s sold %s (%s) for $%d"):format(player.Name, tostring(name), id, value))
	return {Ok = true, Cash = value, Name = tostring(name)}
end

ManageRequest.OnServerInvoke = function(player, request)
	if typeof(player) ~= "Instance" or player.Parent ~= Players then return {Ok = false, Error = "BadRequest"} end
	if not TakeToken(player) then return {Ok = false, Error = "RateLimited"} end
	if type(request) ~= "table" then return {Ok = false, Error = "BadRequest"} end
	local action = request.Action
	local data = DataService.GetData(player)
	if not data then return {Ok = false, Error = "NotLoaded"} end
	if action == "GetState" then
		local ok, reply = pcall(GetState, player, data)
		if ok then return reply end
		warn("[ManageService] GetState failed for " .. player.Name .. ": " .. tostring(reply))
		return {Ok = false, Error = "Unavailable"}
	elseif action == "SellPet" then
		return SellPet(player, request.Id)
	elseif action == "SellCucumber" then
		return SellCucumber(player, request.Id)
	end
	return {Ok = false, Error = "BadRequest"}
end

--..Zombie defence: days survived per threat level..--
local function AddSurvivedDay(player, level)
	local data = DataService.GetData(player)
	local defense = DefenseOf(data)
	if not defense then return end
	level = Finite(level) and math.max(1, math.floor(level)) or 1
	local key = tostring(level)
	defense.Survived[key] = DaysAt(defense, level) + 1
	defense.Level = level
	DataService.RequestSave(player)
	print(("[ManageService] %s survived a night at threat level %d (%d so far)"):format(player.Name, level, defense.Survived[key]))
	Push(player, "Survived")
end

local RaidResultConn = nil
local function BindZombieAPI()
	local api = ZombieAPI()
	local ev = api and api:FindFirstChild("RaidResult")
	if RaidResultConn then
		RaidResultConn:Disconnect()
		RaidResultConn = nil
	end
	if ev and ev:IsA("BindableEvent") then
		RaidResultConn = ev.Event:Connect(function(player, info)
			if typeof(player) ~= "Instance" or type(info) ~= "table" then return end
			if info.Result == "Survived" then
				AddSurvivedDay(player, info.Level)
			else
				Push(player, "RaidEnd")
			end
		end)
	end
end
BindZombieAPI()
ServerStorage.ChildAdded:Connect(function(child)
	if child.Name == "ZombieAPI" then
		task.defer(BindZombieAPI) -- ZombieRaidService rebuilds the folder when it starts
	end
end)

--..Offline earnings..--
local function Stamp(player, data)
	local defense = DefenseOf(data)
	if not defense then return end
	defense.LastSeen = os.time()
	defense.OfflineRate = OfflineRateOf(player)
	defense.Level = ThreatLevelOf(player, defense)
end

local function PayOffline(player, data, awaySeconds, source)
	local defense = DefenseOf(data)
	if not defense then return 0 end
	local level = Finite(defense.Level) and math.max(1, math.floor(defense.Level)) or 1
	local days = DaysAt(defense, level)
	if days < ManageConfig.OFFLINE.RequiredDays then return 0 end
	local cash, counted = ManageConfig.OfflineEarnings(defense.OfflineRate, awaySeconds)
	if cash < 1 then return 0 end
	if not DataService.Increment(player, "Cash", cash) then return 0 end
	defense.LastPayout = {Cash = cash, Seconds = counted, Level = level, At = os.time()}
	PendingToast[player] = {Cash = cash, Seconds = counted, Level = level, At = os.clock()}
	print(("[ManageService] %s earned $%d offline (%s away, threat level %d, %s)"):format(player.Name, cash, ManageConfig.FormatDuration(counted), level, source))
	Push(player, "Offline")
	return cash
end

DataService.OnProfileLoaded(function(player)
	local data = DataService.GetData(player)
	local defense = DefenseOf(data)
	if not defense then return end
	local away = defense.LastSeen > 0 and (os.time() - defense.LastSeen) or 0
	if away >= ManageConfig.OFFLINE.MinSeconds then PayOffline(player, data, away, "join") end
	Stamp(player, data)
end)

DataService.OnBeforeClose(function(player)
	local data = DataService.GetData(player)
	if data then Stamp(player, data) end
end, 15)

task.spawn(function()
	while true do
		task.wait(STAMP_PERIOD)
		for _, player in ipairs(Players:GetPlayers()) do
			if DataService.IsLoaded(player) and not DataService.IsClosing(player) then
				local data = DataService.GetData(player)
				if data then pcall(Stamp, player, data) end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	PendingToast[player] = nil
	Limiter[player] = nil
end)

--..Studio hook..--
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("ManageDev"):Connect(function()
		local cmd = workspace:GetAttribute("ManageDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		workspace:SetAttribute("ManageDev", nil)
		local kind, arg = cmd:match("^(%w+):?(.*)$")
		local player = Players:GetPlayers()[1]
		local data = player and DataService.GetData(player)
		if not data then return end
		if kind == "survive" then
			AddSurvivedDay(player, tonumber(arg) or ThreatLevelOf(player, DefenseOf(data)))
		elseif kind == "reset" then
			data.Defense = nil
			DefenseOf(data)
			DataService.RequestSave(player)
			Push(player, "Reset")
			print("[ManageService] dev: Defense record reset for " .. player.Name)
		elseif kind == "offline" then
			Stamp(player, data)
			local paid = PayOffline(player, data, tonumber(arg) or 3600, "dev")
			print(("[ManageService] dev: offline test paid $%d"):format(paid))
		end
	end)
end

print(("[ManageService] ready: pets %d..%d, cucumbers %d..%d per base, sell = %ds of income, offline x%.2f up to %s after %d survived day(s)"):format(
	ManageConfig.PetCapacity(0), ManageConfig.PetCapacity(ManageConfig.PLOT_MAX_LEVEL), ManageConfig.CucumberCapacity(0), ManageConfig.CucumberCapacity(ManageConfig.PLOT_MAX_LEVEL),
	ManageConfig.SELL_SECONDS, ManageConfig.OFFLINE.Multiplier, ManageConfig.FormatDuration(ManageConfig.OFFLINE.MaxSeconds), ManageConfig.OFFLINE.RequiredDays))
