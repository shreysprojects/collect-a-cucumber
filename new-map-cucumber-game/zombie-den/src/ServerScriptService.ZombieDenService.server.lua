--[[
	ZombieDenService  (Script, ServerScriptService)  2026-09-24
	The server behind the ZOMBIE DEN panel (StarterGui.CucumberMenus.DenPanel, opened by walking up to
	Map.Lobby.Stations."Zombie Den "). User: "lost a cucumber? get it back by getting 3 of X cucumber and trading
	it in, 12 hours before the offer expires". Numbers + the pick rules: ReplicatedStorage.Modules.DenConfig.

	  DEALS     every theft ZombieRaidService.Escape reports lands in Data.LostCucumbers through
	            ItemService.RecordLoss ({Name, Zone, Type, Golden, Material, Mutations, SizeTier, At}); the raid
	            service then fires ServerStorage.ZombieAPI.CucumberStolen (BindableEvent, 2026-09-24) and this
	            script stamps the new record with a deal: Id (GUID) + Want = DenConfig.PickWant(lost biome, the
	            player's Strength, kinds already kept NEED-deep on the base). Records from before this script
	            get their deal on the next profile load. The Redemption Token (ItemService.Redeem) keeps working
	            on the same list: whatever it brings back simply stops being a deal.
	  EXPIRY    a deal is live for DenConfig.OFFER_SECONDS after record.At (real time); expired ones are not
	            offered (the record stays for the token). A sweep every SWEEP_SECONDS nudges the panel when a
	            deal of an online player runs out.
	  TRADE IN  {Action = "TradeIn", Id}: daytime only (CyclePhase "Day"), never while the player's raid is live,
	            the deal must be live, and the player must have NEED placed cucumbers of the wanted kind on their
	            own plot (Zone + TypeName, tagged PlacedCucumber, not held by a zombie / a collector). The lost
	            cucumber sprouts first (CucumberSpawnerAPI.SpawnCarried Anywhere + Force at the player's feet,
	            parked in workspace.Breakables.Planted like a Redemption Token's), THEN the NEED cheapest wanted
	            cucumbers leave the plot (PetBuffService.ClearCucumber "Traded", tag off so IncomeService settles
	            them, destroyed) and the record leaves Data.LostCucumbers. Nothing is consumed when the spawn fails.

	  Remotes.DenRequest (RemoteFunction)  client -> server, one table, one reply table:
	    {Action = "GetState"}      -> {Ok = true, ServerTime, Night, Locked, Need, Offers = {offer, ...}} newest first
	    {Action = "TradeIn", Id}   -> {Ok = true, Name} | {Ok = false, Error = <DenConfig.ERRORS code>, Have?}
	    offer = {Id, Name, Zone, Type, Golden, Material, Mutations, SizeTier, Rate, Want = {Zone, Type}, Need,
	             Have, ExpiresAt (workspace:GetServerTimeNow() scale), SecondsLeft}
	  Remotes.DenState (RemoteEvent) server -> player: {Kind = "Refresh", Reason} (something changed behind the
	    panel's back) | {Kind = "Offer", Name, Want, Need} (a new deal: the client toasts it) | {Kind = "Traded",
	    Name, Position} (the cucumber is back at the player's feet).
	  Studio hook: workspace attribute DenDev = "lose[:<Zone>:<Type>]" (record a theft for the first player and
	    make its deal) | "give[:<n>]" (stand n of the newest deal's wanted kind on their plot) | "expire" (age the
	    newest deal out) | "clear" (forget every loss) | "trade" (trade the newest deal in) - edge-triggered.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DenConfig = require(Modules:WaitForChild("DenConfig"))
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))
local DataService = require(ServerStorage:WaitForChild("DataService"))

local PLACED_TAG = "PlacedCucumber"
local SWEEP_SECONDS = 30 -- s between expiry sweeps
local NEED = DenConfig.NEED

local rng = Random.new()

--..Optional modules (looked up lazily, never required at load)..--
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
local PetBuffsOf = Lazy("PetBuffService")

local function Api(folderName, fnName)
	local folder = ServerStorage:FindFirstChild(folderName)
	local fn = folder and folder:FindFirstChild(fnName)
	return fn and fn:IsA("BindableFunction") and fn or nil
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
		warn(("[ZombieDen] Remotes.%s is a %s, expected a %s"):format(name, r.ClassName, className))
		r = nil
	end
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
local DenRequest = remote("RemoteFunction", DenConfig.REMOTE)
local DenState = remote("RemoteEvent", DenConfig.STATE_REMOTE)

local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

--..Helpers..--
local function Finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function IsValidId(id)
	return type(id) == "string" and #id >= 8 and #id <= 64
end

local function Daytime()
	return workspace:GetAttribute("CyclePhase") == "Day"
end

local function Alive(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then return root, humanoid, character end
	return nil
end

local function PlotOf(player)
	for _, plot in ipairs(Plots:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
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

local function RateOf(model)
	local rate = model:GetAttribute("BaseRate")
	if Finite(rate) then return rate end
	local ok, v = pcall(CucumberValues.RateOfInstance, model)
	return (ok and Finite(v)) and v or 0
end

local function IsBusy(model)
	return model:GetAttribute("StolenBy") ~= nil or model:GetAttribute("CollectingBy") ~= nil
end

--.. the player's placed cucumbers of the wanted kind, cheapest first (the ones a trade takes)
local function HaveOf(player, want)
	local list = {}
	if not DenConfig.ValidWant(want) then return list end
	for _, model in ipairs(PlacedOf(player)) do
		if (model:GetAttribute("Zone") or "Spawn") == want.Zone and (model:GetAttribute("TypeName") or model.Name) == want.Type then
			table.insert(list, model)
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = RateOf(a), RateOf(b)
		if ra ~= rb then return ra < rb end
		return tostring(a:GetAttribute("CucumberId")) < tostring(b:GetAttribute("CucumberId"))
	end)
	return list
end

--.. kinds the player already keeps NEED-deep on the base (a deal avoids them while it can)
local function KeptKinds(player)
	local counts, set = {}, {}
	for _, model in ipairs(PlacedOf(player)) do
		local key = DenConfig.Key(model:GetAttribute("Zone") or "Spawn", model:GetAttribute("TypeName") or model.Name)
		counts[key] = (counts[key] or 0) + 1
		if counts[key] >= NEED then set[key] = true end
	end
	return set
end

local function StrengthOf(player)
	local s = DataService.Get(player, "Strength")
	return Finite(s) and math.max(0, s) or 0
end

local function Push(player, reason)
	if player.Parent == Players then DenState:FireClient(player, {Kind = "Refresh", Reason = reason}) end
end

--..Deals (Data.LostCucumbers records)..--
local function LostOf(data)
	if type(data) ~= "table" then return nil end
	if type(data.LostCucumbers) ~= "table" then data.LostCucumbers = {} end
	return data.LostCucumbers
end

local function ExpiresAtOf(record) -- os.time() scale
	return (Finite(record.At) and record.At or 0) + DenConfig.OFFER_SECONDS
end

local function SecondsLeft(record)
	return ExpiresAtOf(record) - os.time()
end

local function IsRecord(record)
	return type(record) == "table" and type(record.Type) == "string" and #record.Type > 0
end

--.. every loss record gets its deal once (Id + Want + a real At); returns the number of deals made
local function EnsureOffers(player, data)
	local lost = LostOf(data)
	if not lost then return 0 end
	local made, changed = 0, false
	local strength, kept = nil, nil
	for _, record in ipairs(lost) do
		if IsRecord(record) then
			if not Finite(record.At) then
				record.At = os.time()
				changed = true
			end
			if not IsValidId(record.Id) then
				record.Id = HttpService:GenerateGUID(false)
				changed = true
			end
			if not DenConfig.ValidWant(record.Want) then
				strength = strength or StrengthOf(player)
				kept = kept or KeptKinds(player)
				local want = DenConfig.PickWant(CucumberValues.TierOf(record.Zone or "Spawn"), strength, rng, kept, CucumberValues.RewardOf(record.Zone or "Spawn", record.Type))
				record.Want = {Zone = want.Zone, Type = want.Type}
				made += 1
				changed = true
				print(("[ZombieDen] deal for %s: %s back for %s (%s)"):format(player.Name, tostring(record.Name or record.Type), DenConfig.WantText(record.Want), want.Zone))
			end
		end
	end
	if changed then DataService.RequestSave(player) end
	return made
end

local function OfferOf(player, record)
	local left = SecondsLeft(record)
	local have = #HaveOf(player, record.Want)
	return {
		Id = record.Id, Name = tostring(record.Name or record.Type), Zone = record.Zone or "Spawn", Type = record.Type,
		Golden = record.Golden == true, Material = record.Material, Mutations = record.Mutations, SizeTier = record.SizeTier,
		Rate = (function()
			local ok, v = pcall(CucumberValues.RateOf, record.Zone or "Spawn", record.Type, record.Golden == true, record.Material, record.Mutations)
			return (ok and Finite(v)) and v or 0
		end)(),
		Want = {Zone = record.Want.Zone, Type = record.Want.Type}, Need = NEED, Have = have,
		ExpiresAt = workspace:GetServerTimeNow() + left, SecondsLeft = left, At = record.At,
	}
end

local function LiveRecords(data)
	local list = {}
	local lost = LostOf(data)
	if not lost then return list end
	for i = #lost, 1, -1 do -- newest first
		local record = lost[i]
		if IsRecord(record) and DenConfig.ValidWant(record.Want) and IsValidId(record.Id) and SecondsLeft(record) > 0 then
			table.insert(list, record)
		end
	end
	return list
end

local function IsCombatLocked(player)
	return player:GetAttribute("RaidLive") == true
end

local function GetState(player, data)
	EnsureOffers(player, data)
	local offers = {}
	for _, record in ipairs(LiveRecords(data)) do table.insert(offers, OfferOf(player, record)) end
	return {Ok = true, ServerTime = workspace:GetServerTimeNow(), Night = not Daytime(), Locked = IsCombatLocked(player), Need = NEED, Offers = offers}
end

--..Handing a cucumber back (the Redemption Token's way: a field cucumber at the player's feet)..--
local function GroundBelow(position, exclude)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = {}
	local drops = workspace:FindFirstChild("ItemDrops")
	if drops then table.insert(list, drops) end
	local zombies = workspace:FindFirstChild("Zombies")
	if zombies then table.insert(list, zombies) end
	if exclude then for _, e in ipairs(exclude) do table.insert(list, e) end end
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position or nil
end

local function SproutSpot(root, character)
	local ahead = root.Position + root.CFrame.LookVector * 4
	local ground = GroundBelow(ahead, {character})
	return ground or Vector3.new(ahead.X, root.Position.Y - 3, ahead.Z)
end

local function SpawnCucumber(player, record, point)
	local spawn = Api("CucumberSpawnerAPI", "SpawnCarried")
	if not spawn then return nil, "no spawner" end
	local ok, holder = pcall(spawn.Invoke, spawn, record.Zone or "Spawn", record.Type, record.Golden == true, point,
		{Anywhere = true, Force = true, Material = record.Material, Mutations = record.Mutations, SizeTier = record.SizeTier})
	if not ok then return nil, tostring(holder) end
	if not holder then return nil, "spawn refused" end
	--.. out of the zone folder (CucumberSpawner.ClearFields wipes those at dusk and dawn); Breakables.Planted is
	--.. still under workspace.Breakables, so the Lift prompt and the collect path keep working
	local container = workspace:FindFirstChild("Breakables")
	if container then
		local planted = container:FindFirstChild("Planted")
		if not planted then
			planted = Instance.new("Folder")
			planted.Name = "Planted"
			planted.Parent = container
		end
		holder:SetAttribute("Planted", true)
		holder:SetAttribute("PlantedBy", player.UserId)
		holder.Parent = planted
	end
	return holder
end

--..Trade in..--
local function TradeIn(player, id)
	if not IsValidId(id) then return {Ok = false, Error = "BadRequest"} end
	if not DataService.IsLoaded(player) then return {Ok = false, Error = "NotLoaded"} end
	if DataService.IsClosing(player) then return {Ok = false, Error = "Closing"} end
	local data = DataService.GetData(player)
	local lost = LostOf(data)
	if not lost then return {Ok = false, Error = "NotLoaded"} end
	if not Daytime() then return {Ok = false, Error = "Night"} end
	if IsCombatLocked(player) then return {Ok = false, Error = "CombatLocked"} end
	EnsureOffers(player, data)
	local index, record
	for i, rec in ipairs(lost) do
		if IsRecord(rec) and rec.Id == id then index, record = i, rec break end
	end
	if not record then return {Ok = false, Error = "NotFound"} end
	if not DenConfig.ValidWant(record.Want) then return {Ok = false, Error = "NotFound"} end
	if SecondsLeft(record) <= 0 then
		Push(player, "Expired")
		return {Ok = false, Error = "Expired"}
	end
	local plot = PlotOf(player)
	if not plot then return {Ok = false, Error = "NoPlot"} end
	local root, _, character = Alive(player)
	if not root then return {Ok = false, Error = "NoCharacter"} end
	local have = HaveOf(player, record.Want)
	if #have < NEED then return {Ok = false, Error = "NotEnough", Have = #have} end
	local taking = {}
	for _, model in ipairs(have) do
		if not IsBusy(model) then table.insert(taking, model) end
		if #taking >= NEED then break end
	end
	if #taking < NEED then return {Ok = false, Error = "Busy", Have = #have} end
	--.. the lost cucumber comes back FIRST; nothing is consumed when that fails
	local point = SproutSpot(root, character)
	local holder, err = SpawnCucumber(player, record, point)
	if not holder then
		warn("[ZombieDen] hand-back spawn failed for " .. player.Name .. ": " .. tostring(err))
		return {Ok = false, Error = "SpawnFailed"}
	end
	local buffs = PetBuffsOf()
	local takenNames = {}
	for _, model in ipairs(taking) do
		if buffs and type(buffs.ClearCucumber) == "function" then pcall(buffs.ClearCucumber, model, "Traded") end
		CollectionService:RemoveTag(model, PLACED_TAG) -- IncomeService settles what it earned up to now
		table.insert(takenNames, tostring(model:GetAttribute("CucumberName") or model.Name))
		model:Destroy()
	end
	if lost[index] == record then table.remove(lost, index) else
		for i, rec in ipairs(lost) do
			if rec == record then table.remove(lost, i) break end
		end
	end
	DataService.RequestSave(player)
	local name = tostring(record.Name or holder.Name)
	DenState:FireClient(player, {Kind = "Traded", Name = name, Position = point})
	print(("[ZombieDen] %s traded %d x %s (%s) for their %s back"):format(player.Name, NEED, record.Want.Type, record.Want.Zone, name))
	return {Ok = true, Name = name}
end

--..Requests..--
local Limiter = {} -- [player] = {Tokens, Last}
local function TakeToken(player)
	local now = os.clock()
	local l = Limiter[player]
	if not l then
		l = {Tokens = DenConfig.REQUEST_BURST, Last = now}
		Limiter[player] = l
	end
	l.Tokens = math.min(DenConfig.REQUEST_BURST, l.Tokens + (now - l.Last) * DenConfig.REQUEST_PER_SECOND)
	l.Last = now
	if l.Tokens < 1 then return false end
	l.Tokens -= 1
	return true
end

DenRequest.OnServerInvoke = function(player, request)
	if typeof(player) ~= "Instance" or player.Parent ~= Players then return {Ok = false, Error = "BadRequest"} end
	if not TakeToken(player) then return {Ok = false, Error = "RateLimited"} end
	if type(request) ~= "table" then return {Ok = false, Error = "BadRequest"} end
	local action = request.Action
	if action == "GetState" then
		local data = DataService.GetData(player)
		if not data then return {Ok = false, Error = "NotLoaded"} end
		local ok, reply = pcall(GetState, player, data)
		if ok then return reply end
		warn("[ZombieDen] GetState failed for " .. player.Name .. ": " .. tostring(reply))
		return {Ok = false, Error = "Unavailable"}
	elseif action == "TradeIn" then
		local ok, reply = pcall(TradeIn, player, request.Id)
		if ok then return reply end
		warn("[ZombieDen] TradeIn failed for " .. player.Name .. ": " .. tostring(reply))
		return {Ok = false, Error = "Unavailable"}
	end
	return {Ok = false, Error = "BadRequest"}
end

--..A theft just happened (ZombieRaidService.Escape -> ItemService.RecordLoss -> ZombieAPI.CucumberStolen)..--
local function OnStolen(player)
	if typeof(player) ~= "Instance" or player.Parent ~= Players then return end
	local data = DataService.GetData(player)
	if not data then return end
	EnsureOffers(player, data)
	local live = LiveRecords(data)
	local newest = live[1]
	if newest then
		DenState:FireClient(player, {Kind = "Offer", Name = tostring(newest.Name or newest.Type), Want = {Zone = newest.Want.Zone, Type = newest.Want.Type}, Need = NEED})
	end
	Push(player, "Stolen")
end

local StolenConn = nil
local function BindZombieAPI()
	local api = ServerStorage:FindFirstChild("ZombieAPI")
	local ev = api and api:FindFirstChild("CucumberStolen")
	if StolenConn then
		StolenConn:Disconnect()
		StolenConn = nil
	end
	if ev and ev:IsA("BindableEvent") then
		StolenConn = ev.Event:Connect(function(player)
			local ok, err = pcall(OnStolen, player)
			if not ok then warn("[ZombieDen] stolen hook: " .. tostring(err)) end
		end)
	end
end
BindZombieAPI()
ServerStorage.ChildAdded:Connect(function(child)
	if child.Name == "ZombieAPI" then task.defer(BindZombieAPI) end -- ZombieRaidService rebuilds the folder when it starts
end)

--..Profiles + expiry..--
local LiveIds = {} -- [player] = {[id] = true} the deals the last sweep saw live
local function Sweep(player, data, notify)
	local now = {}
	for _, record in ipairs(LiveRecords(data)) do now[record.Id] = true end
	local before = LiveIds[player]
	LiveIds[player] = now
	if not (before and notify) then return end
	for id in pairs(before) do
		if not now[id] then
			Push(player, "Expired")
			return
		end
	end
end

DataService.OnProfileLoaded(function(player)
	local data = DataService.GetData(player)
	if not data then return end
	local made = EnsureOffers(player, data)
	Sweep(player, data, false)
	if made > 0 then Push(player, "Loaded") end
end)

task.spawn(function()
	while true do
		task.wait(SWEEP_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			if DataService.IsLoaded(player) and not DataService.IsClosing(player) then
				local data = DataService.GetData(player)
				if data then pcall(Sweep, player, data, true) end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	Limiter[player] = nil
	LiveIds[player] = nil
end)

--..Studio hook..--
if RunService:IsStudio() then
	--.. dev only: stand a cucumber of a kind on the player's plot at a free cell (RestorePlaced, then settle its
	--.. bottom on the plot's top surface - the record has no saved pose)
	local function DevPlace(player, want)
		local restore = Api("CucumberCarryAPI", "RestorePlaced")
		local plot = PlotOf(player)
		if not (restore and plot) then return nil, "no restore / plot" end
		local holder = plot:FindFirstChild("Placed")
		if not holder then
			holder = Instance.new("Folder")
			holder.Name = "Placed"
			holder.Parent = plot
		end
		local box = Vector3.new(4.5, 4, 4.5)
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {holder}
		local top = plot.Size.Y * 0.5
		local hx, hz = plot.Size.X * 0.5 - 4, plot.Size.Z * 0.5 - 4
		for z = -hz, hz, 5.5 do
			for x = -hx, hx, 5.5 do
				local boxCF = plot.CFrame * CFrame.new(x, top + box.Y * 0.5, z)
				if #workspace:GetPartBoundsInBox(boxCF, box, params) == 0 then
					local pivot = plot.CFrame * CFrame.new(x, top + 1.5, z)
					local record = {Zone = want.Zone, Type = want.Type, Golden = false, Name = want.Type}
					local ok, model = pcall(restore.Invoke, restore, player, plot, record, pivot, boxCF, box)
					if ok and model then
						local minY = math.huge
						for _, p in ipairs(model:GetDescendants()) do
							if p:IsA("BasePart") and p.Name ~= "PlotHitbox" then minY = math.min(minY, p.Position.Y - p.Size.Y * 0.5) end
						end
						local surfaceY = (plot.CFrame * CFrame.new(0, top, 0)).Position.Y
						if minY < math.huge then model:PivotTo(model:GetPivot() + Vector3.new(0, surfaceY - minY, 0)) end
						local hb = model:FindFirstChild("PlotHitbox")
						if hb then hb.CFrame = boxCF end
						return model
					end
					return nil, tostring(model)
				end
			end
		end
		return nil, "plot full"
	end

	workspace:GetAttributeChangedSignal("DenDev"):Connect(function()
		local cmd = workspace:GetAttribute("DenDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		workspace:SetAttribute("DenDev", nil)
		local kind, arg = cmd:match("^(%w+):?(.*)$")
		local player = Players:GetPlayers()[1]
		local data = player and DataService.GetData(player)
		if not data then
			print("[ZombieDen] dev: no player / data")
			return
		end
		if kind == "lose" then
			local zone, typeName = arg:match("^([^:]+):(.+)$")
			if not zone then
				local best = PlacedOf(player)[1]
				zone = best and best:GetAttribute("Zone") or "Spawn"
				typeName = best and best:GetAttribute("TypeName") or "Cucumber"
			end
			local recordLoss = Api("ItemAPI", "RecordLoss")
			local record = {Name = typeName, Zone = zone, Type = typeName, Golden = false}
			if recordLoss then
				pcall(recordLoss.Invoke, recordLoss, player, record)
			else
				local lost = LostOf(data)
				record.At = os.time()
				table.insert(lost, record)
			end
			OnStolen(player)
			local newest = LiveRecords(data)[1]
			print(("[ZombieDen] dev lose: %s %s -> deal wants %s"):format(zone, typeName, newest and DenConfig.WantText(newest.Want) .. " (" .. newest.Want.Zone .. ")" or "?"))
		elseif kind == "give" then
			EnsureOffers(player, data)
			local newest = LiveRecords(data)[1]
			if not newest then
				print("[ZombieDen] dev give: no live deal")
				return
			end
			local n = tonumber(arg) or NEED
			local placed = 0
			for _ = 1, n do
				local model, err = DevPlace(player, newest.Want)
				if model then placed += 1 else warn("[ZombieDen] dev give: " .. tostring(err)) end
			end
			Push(player, "Dev")
			print(("[ZombieDen] dev give: %d x %s (%s) placed"):format(placed, newest.Want.Type, newest.Want.Zone))
		elseif kind == "expire" then
			local newest = LiveRecords(data)[1]
			if newest then
				newest.At = os.time() - DenConfig.OFFER_SECONDS - 1
				DataService.RequestSave(player)
				Push(player, "Expired")
				print("[ZombieDen] dev expire: " .. tostring(newest.Name))
			end
		elseif kind == "clear" then
			data.LostCucumbers = {}
			DataService.RequestSave(player)
			Push(player, "Dev")
			print("[ZombieDen] dev clear")
		elseif kind == "trade" then
			local newest = LiveRecords(data)[1]
			local result = newest and TradeIn(player, newest.Id) or {Ok = false, Error = "NoDeal"}
			print("[ZombieDen] dev trade -> " .. HttpService:JSONEncode(result))
			Push(player, "Dev")
		end
	end)
end

print(("[ZombieDen] ready: %d x the wanted cucumber per deal, deals last %s, panel opens within %d studs"):format(NEED, DenConfig.Countdown(DenConfig.OFFER_SECONDS), DenConfig.OPEN_RADIUS))
