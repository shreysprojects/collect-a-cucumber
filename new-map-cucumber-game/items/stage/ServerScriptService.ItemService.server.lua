--[[
	ItemService  (Script, ServerScriptService)  2026-09-23
	The drop items (user: "potions/items ... boosts for a duration (2x speed, 2x strength, 2x coins),
	teleports like an enderpearl, special cucumbers, special pets, redemption tokens ... stored and
	saved in the bottom inventory. they drop on zombie deaths"). Definitions = RS.Modules.ItemsCatalog.

	  SAVED   Data.Items[<Key>] = count (DataService template key), Data.LostCucumbers = {record, ...}
	          (the cucumbers zombies stole, newest last; a Redemption Token brings the newest back).
	  TOOLS   every owned item is ONE Tool in the Backpack (stack), attributes ItemTool = true, ItemKey,
	          Count, DisplayName, Rarity, Kind, Description, Boost; tag "ItemTool". The Handle is an
	          invisible cube at the model's centre with the item's parts (RS.Assets.Items/<Key>) welded
	          on, so the item sits in the hand when equipped and the hotbar pictures the same parts.
	          Reconciled after every change, on load / reset / respawn and every RECONCILE seconds.
	  USE     Remotes.ItemUse (RemoteFunction) {Key, Direction?} -> {Ok, Error?, ...}: the player must
	          hold that tool in hand (Tool.Activated on the client) and own at least one.
	            Drink  -> player attribute <Boost>Until = max(now, current) + Duration (server time);
	                      Speed = SpeedBoostUntil (StrengthProgressionServer doubles WalkSpeed),
	                      Strength = StrengthBoostUntil (GymService.AwardRep x2), Cash = CashBoostUntil
	                      (IncomeService.Credit x2)
	            Throw  -> a server-simulated ball flies where the camera looks; where it lands:
	                      WarpPearl teleports the thrower there, HolyWater damages + stuns every zombie
	                      within HOLY_WATER.Radius (ZombieAPI.Damage / Stun)
	            Use    -> GoldenSeed / VoidSeed: a Golden / VOID field cucumber of the player's best biome
	                      sprouts 4 studs ahead (CucumberSpawnerAPI.SpawnCarried, Anywhere + Force);
	                      RedemptionToken: the newest LostCucumbers record sprouts the same way;
	                      ZombieEgg: PetService.GrantFromEgg of a SHADOW pet (2 % Gregory)
	  DROPS   ServerStorage.ItemAPI.Drop(position, level) (ZombieRaidService.Kill calls it): the
	          ItemsCatalog roll -> a model clone under workspace.ItemDrops (tag ItemDrop, attrs ItemKey /
	          DisplayName / Rarity); any player within PICKUP_RADIUS picks it up (Give + "Picked");
	          gone after DROP_LIFETIME. ItemAPI.Give(player, key, n) / Count(player, key) /
	          RecordLoss(player, record) (ZombieRaidService.Escape) for other scripts.
	  EVENTS  Remotes.ItemEvent (RemoteEvent) -> clients {Kind = "Gained" | "Picked" | "Drink" | "Throw" |
	          "Warp" | "Splash" | "Planted" | "Redeemed" | "Hatched" | "Toast", ...} (ItemClient: FX + toasts)
	  STUDIO  workspace attribute ItemDev = "give:<Key>[:<n>]" | "drop:<Key>" | "roll:<level>" |
	          "use:<Key>" | "lose" | "clear" (first player; RunService:IsStudio only)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Catalog = require(Modules:WaitForChild("ItemsCatalog"))
local DataService = require(ServerStorage:WaitForChild("DataService"))
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))
local okSound, SoundController = pcall(function() return require(Modules:WaitForChild("SoundController", 5)) end)
if not okSound then SoundController = nil end
local okPetsCatalog, PetsCatalog = pcall(function() return require(Modules:WaitForChild("PetsCatalog", 5)) end)
if not okPetsCatalog then PetsCatalog = nil end

local TAG = "ItemTool"
local DROP_TAG = "ItemDrop"
local RECONCILE = 3
local PICK_TICK = 0.25
local rng = Random.new()

--..Lazy ServerStorage modules / APIs (installed by other systems)..--
local function Lazy(name)
	local cache
	return function()
		if cache ~= nil then return cache or nil end
		local module = ServerStorage:FindFirstChild(name)
		if not module then return nil end
		local ok, result = pcall(require, module)
		cache = ok and type(result) == "table" and result or false
		return cache or nil
	end
end
local PetServiceOf = Lazy("PetService")
local function Api(folderName, fnName)
	local folder = ServerStorage:FindFirstChild(folderName)
	local fn = folder and folder:FindFirstChild(fnName)
	return fn and fn:IsA("BindableFunction") and fn or nil
end

--..Remotes / folders..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local function Remote(name, class)
	local r = Remotes:FindFirstChild(name)
	if r and not r:IsA(class) then r:Destroy() r = nil end
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
local UseRemote = Remote("ItemUse", "RemoteFunction")
local Event = Remote("ItemEvent", "RemoteEvent")

local Assets = ReplicatedStorage:FindFirstChild("Assets")
local ItemsFolder = Assets and Assets:FindFirstChild("Items")
if not ItemsFolder then warn("[ItemService] ReplicatedStorage.Assets.Items is missing - run items/install_items.lua; tools will have no model") end

local DropsFolder = workspace:FindFirstChild("ItemDrops")
if not DropsFolder then
	DropsFolder = Instance.new("Folder")
	DropsFolder.Name = "ItemDrops"
	DropsFolder.Parent = workspace
end

--..Helpers..--
local function Finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function Alive(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then return root, humanoid, character end
	return nil
end

local function Toast(player, text, kind)
	Event:FireClient(player, {Kind = "Toast", Text = text, Style = kind or "Info"})
end

local function PlayAt(name, position, volume)
	if not SoundController then return end
	pcall(SoundController.PlayFXAt, name, position, {Volume = volume or 0.8, RollOff = 60})
end

--..Saved inventory..--
local function ItemsOf(player)
	local data = DataService.GetData(player)
	if not data then return nil end
	if type(data.Items) ~= "table" then data.Items = {} end
	if type(data.LostCucumbers) ~= "table" then data.LostCucumbers = {} end
	return data.Items, data
end

local function CountOf(player, key)
	local items = ItemsOf(player)
	return items and tonumber(items[key]) or 0
end

local Reconcile -- defined below

local function Give(player, key, n)
	local def = Catalog.Get(key)
	local items = ItemsOf(player)
	if not (def and items) then return false end
	n = math.floor(tonumber(n) or 1)
	local count = math.clamp((tonumber(items[key]) or 0) + n, 0, Catalog.MAX_STACK)
	items[key] = count > 0 and count or nil
	DataService.RequestSave(player)
	Reconcile(player)
	return true, count
end

local function Take(player, key, n)
	if CountOf(player, key) < (n or 1) then return false end
	return Give(player, key, -(n or 1))
end

--..Tools (one stack per item)..--
local function TemplateOf(key)
	return ItemsFolder and ItemsFolder:FindFirstChild(key) or nil
end

local function BuildTool(def, count)
	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.CanBeDropped = false
	tool.ToolTip = def.Description
	tool:SetAttribute("ItemTool", true)
	tool:SetAttribute("ItemKey", def.Key)
	tool:SetAttribute("Count", count)
	tool:SetAttribute("DisplayName", def.Name)
	tool:SetAttribute("Rarity", def.Rarity)
	tool:SetAttribute("Kind", def.Kind)
	tool:SetAttribute("Description", def.Description)
	tool:SetAttribute("Boost", def.Boost or "")
	tool:SetAttribute("Duration", def.Duration or 0)
	local template = TemplateOf(def.Key)
	if template then
		tool.RequiresHandle = true
		local cf = template:GetBoundingBox()
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.4, 0.4, 0.4)
		handle.Transparency = 1
		handle.CanCollide = false
		handle.CanQuery = false
		handle.CanTouch = false
		handle.Massless = true
		handle.CFrame = cf
		handle.Parent = tool
		for _, p in ipairs(template:GetChildren()) do
			if p:IsA("BasePart") then
				local c = p:Clone()
				c.Anchored = false
				c.Massless = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.Parent = tool
				local w = Instance.new("WeldConstraint")
				w.Part0 = handle
				w.Part1 = c
				w.Parent = handle
			end
		end
		--.. the item hangs a little below the fist, tipped forward so its front shows
		tool.Grip = CFrame.new(0, -0.35, 0) * CFrame.Angles(math.rad(-12), 0, 0)
		--.. HotbarClient waits for this many parts before it draws the picture (a Tool replicates before its children)
		local parts = 0
		for _, c in ipairs(tool:GetChildren()) do if c:IsA("BasePart") then parts += 1 end end
		tool:SetAttribute("PartCount", parts)
	else
		tool.RequiresHandle = false
	end
	CollectionService:AddTag(tool, TAG)
	return tool
end

local function ToolsOf(player)
	local tools = {}
	local function scan(container)
		if not container then return end
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("ItemTool") == true then
				local key = tool:GetAttribute("ItemKey")
				if type(key) == "string" and Catalog.Get(key) and not tools[key] then tools[key] = tool else tool:Destroy() end
			end
		end
	end
	scan(player:FindFirstChild("Backpack"))
	scan(player.Character)
	return tools
end

Reconcile = function(player)
	if player.Parent ~= Players then return end
	if not DataService.IsLoaded(player) then return end
	if type(DataService.IsClosing) == "function" and DataService.IsClosing(player) then return end
	local items = ItemsOf(player)
	if not items then return end
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end
	local tools = ToolsOf(player)
	local wanted = {}
	for _, def in ipairs(Catalog.ITEMS) do
		local n = math.floor(tonumber(items[def.Key]) or 0)
		if n > 0 then
			wanted[def.Key] = true
			local tool = tools[def.Key]
			if not tool then
				BuildTool(def, n).Parent = backpack
			else
				if tool:GetAttribute("Count") ~= n then tool:SetAttribute("Count", n) end
				--.. a catalog text / kind change reaches tools that already exist (the Warp Pearl rework, 2026-09-23)
				if tool:GetAttribute("Description") ~= def.Description then
					tool:SetAttribute("Description", def.Description)
					tool.ToolTip = def.Description
				end
				if tool:GetAttribute("Kind") ~= def.Kind then tool:SetAttribute("Kind", def.Kind) end
			end
		end
	end
	for key, tool in pairs(tools) do
		if not wanted[key] then tool:Destroy() end
	end
end

local function SafeReconcile(player)
	local ok, err = pcall(Reconcile, player)
	if not ok then warn("[ItemService] reconcile failed for " .. player.Name .. ": " .. tostring(err)) end
end

--..World helpers..--
local MapFolder = workspace:FindFirstChild("Map")
local function GroundBelow(position, exclude)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = {DropsFolder}
	if exclude then for _, e in ipairs(exclude) do table.insert(list, e) end end
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position or nil
end

local function PlantSpot(player, root, character)
	local ahead = root.Position + root.CFrame.LookVector * 4
	local ground = GroundBelow(ahead, {character})
	return ground or Vector3.new(ahead.X, root.Position.Y - 3, ahead.Z)
end

--.. the lobby box = inner faces of the "Lobby Border" walls (the CucumberCarry rule; LobbyLayout moves them, so read
--.. late and only once). Used by the Warp Pearl at night: the night wall is never warped across.
local LobbyBox = nil -- {MinX, MaxX, MinZ, MaxZ} | false = unknown
local function ComputeLobbyBox()
	local borders = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Borders")
	local border = borders and borders:FindFirstChild("Lobby Border")
	local minX, maxX, minZ, maxZ
	for _, p in ipairs(border and border:GetChildren() or {}) do
		if p:IsA("BasePart") and p.Size.Y < 20 then
			local hx, hz = p.Size.X * 0.5, p.Size.Z * 0.5
			local r, l = p.CFrame.RightVector, p.CFrame.LookVector
			local ex = math.abs(r.X) * hx + math.abs(l.X) * hz
			local ez = math.abs(r.Z) * hx + math.abs(l.Z) * hz
			if ex <= 5 and ez > 10 then
				minX = math.min(minX or math.huge, p.Position.X + ex)
				maxX = math.max(maxX or -math.huge, p.Position.X - ex)
			elseif ez <= 5 and ex > 10 then
				minZ = math.min(minZ or math.huge, p.Position.Z + ez)
				maxZ = math.max(maxZ or -math.huge, p.Position.Z - ez)
			end
		end
	end
	if minX and maxX and minZ and maxZ and maxX > minX and maxZ > minZ then
		return {MinX = minX, MaxX = maxX, MinZ = minZ, MaxZ = maxZ}
	end
	return false
end
local function InLobby(position)
	if LobbyBox == nil then LobbyBox = ComputeLobbyBox() end
	if not LobbyBox then return false end
	return position.X >= LobbyBox.MinX and position.X <= LobbyBox.MaxX and position.Z >= LobbyBox.MinZ and position.Z <= LobbyBox.MaxZ
end

--.. Warp bounds (2026-09-23, user: "avoid the top border, i keep teleporting outside the border"): a warp may only
--.. land on the playable ground = inside a biome's Floor rectangle or the lobby box, both inset BOUNDS_INSET studs so
--.. a border wall's top (it straddles the floor edge) never counts, and no higher than BOUNDS_HEIGHT above that
--.. floor. Computed from the map once (after LobbyLayout has run) and published to clients as the JSON attribute
--.. Remotes.WarpBounds so ItemClient can show a red ring on a bad spot before the click.
local BOUNDS_INSET = 1.5
local BOUNDS_HEIGHT = 12
local WarpRects = nil
local function PartsAabb(inst)
	local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local n = 0
	for _, p in ipairs(inst:IsA("BasePart") and {inst} or inst:GetDescendants()) do
		if p:IsA("BasePart") then
			n += 1
			local cf, s = p.CFrame, p.Size * 0.5
			local ex = Vector3.new(
				math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z,
				math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z,
				math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z)
			minV = Vector3.new(math.min(minV.X, cf.Position.X - ex.X), math.min(minV.Y, cf.Position.Y - ex.Y), math.min(minV.Z, cf.Position.Z - ex.Z))
			maxV = Vector3.new(math.max(maxV.X, cf.Position.X + ex.X), math.max(maxV.Y, cf.Position.Y + ex.Y), math.max(maxV.Z, cf.Position.Z + ex.Z))
		end
	end
	if n == 0 then return nil end
	return minV, maxV
end
local function ComputeWarpRects()
	local rects = {}
	local biomes = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Biomes")
	for _, biome in ipairs(biomes and biomes:GetChildren() or {}) do
		local floor = biome:FindFirstChild("Floor")
		local a, b
		if floor then a, b = PartsAabb(floor) end -- (never `floor and PartsAabb(floor)`: `and` keeps only the first return)
		if a and b and (b.X - a.X) > 2 * BOUNDS_INSET and (b.Z - a.Z) > 2 * BOUNDS_INSET then
			--.. the far (Z) edges follow the biome's own walls where it has them: the Volcano floor runs past its walls
			local minZ, maxZ = a.Z, b.Z
			local walls = biome:FindFirstChild("Walls")
			local wa, wb
			if walls then wa, wb = PartsAabb(walls) end
			if wa and wb and (wb.Z - wa.Z) > 2 * BOUNDS_INSET then
				minZ, maxZ = math.max(minZ, wa.Z), math.min(maxZ, wb.Z)
			end
			table.insert(rects, {Name = biome.Name, MinX = a.X + BOUNDS_INSET, MaxX = b.X - BOUNDS_INSET, MinZ = minZ + BOUNDS_INSET, MaxZ = maxZ - BOUNDS_INSET, TopY = b.Y})
		end
	end
	if LobbyBox == nil then LobbyBox = ComputeLobbyBox() end
	if LobbyBox then
		local plots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Lobby") and workspace.Map.Lobby:FindFirstChild("Plots")
		local _, b
		if plots then _, b = PartsAabb(plots) end
		table.insert(rects, {Name = "Lobby", MinX = LobbyBox.MinX + BOUNDS_INSET, MaxX = LobbyBox.MaxX - BOUNDS_INSET, MinZ = LobbyBox.MinZ + BOUNDS_INSET, MaxZ = LobbyBox.MaxZ - BOUNDS_INSET, TopY = b and b.Y or -211})
	end
	return rects
end
local function WarpRectsOf()
	if WarpRects == nil then
		WarpRects = ComputeWarpRects()
		pcall(function() Remotes:SetAttribute("WarpBounds", game:GetService("HttpService"):JSONEncode(WarpRects)) end)
	end
	return WarpRects
end
local function InsideWarpBounds(position)
	for _, r in ipairs(WarpRectsOf()) do
		if position.X >= r.MinX and position.X <= r.MaxX and position.Z >= r.MinZ and position.Z <= r.MaxZ and position.Y <= r.TopY + BOUNDS_HEIGHT then
			return true, r.Name
		end
	end
	return false
end
task.delay(3, WarpRectsOf) -- publish for the clients once LobbyLayout has placed the walls

--.. field cucumbers can only be collected by day (CucumberCarry), so seeds / tokens only work by day; the Warp
--.. Pearl reads the phase too (the lobby wall rule)
local function Daytime()
	return workspace:GetAttribute("CyclePhase") == "Day"
end
local NIGHT_MESSAGE = "Wait for daylight - cucumbers can't be collected at night."

--.. the best biome the player has reached: where they stand now, or the best zone of their placed cucumbers
local function BestZone(player)
	local best = math.clamp(math.floor(tonumber(player:GetAttribute("BiomeIndex")) or 1), 1, #CucumberValues.ZONES)
	for _, model in ipairs(CollectionService:GetTagged("PlacedCucumber")) do
		if model:GetAttribute("Owner") == player.UserId then
			local tier = CucumberValues.TierOf(model:GetAttribute("Zone"))
			if tier > best then best = tier end
		end
	end
	return CucumberValues.ZONES[best] or "Spawn"
end

--..Boosts (potions)..--
local function Drink(player, def)
	local boost = Catalog.BOOSTS[def.Boost]
	if not boost then return {Ok = false, Error = "BadItem"} end
	local now = workspace:GetServerTimeNow()
	local current = tonumber(player:GetAttribute(boost.Attr)) or 0
	local untilTime = math.max(now, current) + (def.Duration or 60)
	if not Take(player, def.Key, 1) then return {Ok = false, Error = "None"} end
	player:SetAttribute(boost.Attr, untilTime)
	local root = Alive(player)
	Event:FireAllClients({Kind = "Drink", Key = def.Key, Player = player, Boost = def.Boost, Until = untilTime, Position = root and root.Position or nil})
	return {Ok = true, Until = untilTime, Boost = def.Boost}
end

--..Throwables..--
local function Land(player, def, landed)
	if def.Key == "HolyWater" then
		local zombies = Api("ZombieAPI", "Zombies")
		local damage = Api("ZombieAPI", "Damage")
		local stun = Api("ZombieAPI", "Stun")
		local hits = 0
		if zombies and damage then
			local ok, list = pcall(zombies.Invoke, zombies)
			if ok and type(list) == "table" then
				for _, model in ipairs(list) do
					local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
					if root and (root.Position - landed.Position).Magnitude <= Catalog.HOLY_WATER.Radius then
						local okD = pcall(damage.Invoke, damage, model, Catalog.HOLY_WATER.Damage, "HolyWater", player)
						if okD then hits += 1 end
						if stun then pcall(stun.Invoke, stun, model, Catalog.HOLY_WATER.Stun) end
					end
				end
			end
		end
		Event:FireAllClients({Kind = "Splash", Player = player, Position = landed.Position, Hits = hits, Radius = Catalog.HOLY_WATER.Radius})
		PlayAt("Water Splash", landed.Position, 1)
	end
end

local function Throw(player, def, direction)
	local root, _, character = Alive(player)
	if not root then return {Ok = false, Error = "NoCharacter"} end
	if typeof(direction) ~= "Vector3" or not (Finite(direction.X) and Finite(direction.Y) and Finite(direction.Z)) or direction.Magnitude < 0.01 then
		direction = root.CFrame.LookVector
	end
	direction = direction.Unit
	if not Take(player, def.Key, 1) then return {Ok = false, Error = "None"} end
	local origin = root.Position + direction * 2 + Vector3.new(0, 1.2, 0)
	local ball = Instance.new("Part")
	ball.Name = def.Key .. "Projectile"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.7, 0.7, 0.7)
	ball.Color = def.Color
	ball.Material = Enum.Material.Neon
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CFrame = CFrame.new(origin)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.3, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.3, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(def.Color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.35
	trail.LightEmission = 0.6
	trail.Parent = ball
	ball.Parent = DropsFolder
	ball.AssemblyLinearVelocity = direction * Catalog.THROW.Speed + Vector3.new(0, Catalog.THROW.Lift, 0)
	pcall(ball.SetNetworkOwner, ball, nil)
	Event:FireAllClients({Kind = "Throw", Key = def.Key, Player = player, Position = origin})
	PlayAt("Whoosh", origin, 0.7)
	task.spawn(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {character, DropsFolder}
		local last, landed = origin, nil
		local t0 = os.clock()
		while os.clock() - t0 < Catalog.THROW.MaxSeconds do
			RunService.Heartbeat:Wait()
			if not ball.Parent then break end
			local pos = ball.Position
			local delta = pos - last
			if delta.Magnitude > 0 then
				local hit = workspace:Raycast(last, delta, params)
				if hit then
					landed = {Position = hit.Position, Normal = hit.Normal, Instance = hit.Instance}
					break
				end
			end
			if (pos - origin).Magnitude > Catalog.THROW.MaxRange or pos.Y < origin.Y - 250 then break end
			last = pos
		end
		if not landed then
			local pos = ball.Parent and ball.Position or last
			local ground = GroundBelow(pos, {character})
			landed = {Position = ground or pos, Normal = Vector3.yAxis}
		end
		ball:Destroy()
		local ok, err = pcall(Land, player, def, landed)
		if not ok then warn("[ItemService] landing " .. def.Key .. ": " .. tostring(err)) end
	end)
	return {Ok = true}
end

--..Warp Pearl (Kind "Aim", 2026-09-23, user: "click anywhere ... teleports u there, even if u have a cucumber")..--
--.. target = the world point under the client's mouse (ItemClient's ray hit). The server stands the player on the
--.. ground under that point (never inside geometry), keeps their facing, and refuses: mid-minigame, seated, nowhere
--.. to stand, farther than WARP.MaxRange, or across the lobby wall at night. A shoulder cucumber is welded to the
--.. torso, so it comes along; CucumberCarry's lobby watch handles a carrier landing in the lobby by itself.
local function Warp(player, def, target)
	if player:GetAttribute("InPortalMinigame") == true then return {Ok = false, Error = "Minigame", Message = "Not inside a minigame."} end
	local root, humanoid, character = Alive(player)
	if not root then return {Ok = false, Error = "NoCharacter"} end
	if humanoid.SeatPart or humanoid.Sit then return {Ok = false, Error = "Seated", Message = "Stand up first."} end
	if typeof(target) ~= "Vector3" or not (Finite(target.X) and Finite(target.Y) and Finite(target.Z)) then
		return {Ok = false, Error = "BadTarget", Message = "Point somewhere to warp."}
	end
	local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
	if flat.Magnitude > Catalog.WARP.MaxRange then return {Ok = false, Error = "TooFar", Message = "Too far to warp."} end
	local exclude = {character}
	local zombies = Api("ZombieAPI", "Zombies")
	if zombies then
		local ok, list = pcall(zombies.Invoke, zombies)
		if ok and type(list) == "table" then for _, z in ipairs(list) do table.insert(exclude, z) end end
	end
	for _, other in ipairs(Players:GetPlayers()) do if other.Character then table.insert(exclude, other.Character) end end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	table.insert(exclude, DropsFolder)
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(target + Vector3.new(0, 6, 0), Vector3.new(0, -80, 0), params)
	if not hit then return {Ok = false, Error = "NoGround", Message = "Nowhere to stand there."} end
	local land = hit.Position
	if not InsideWarpBounds(land) then
		return {Ok = false, Error = "OutOfBounds", Message = "Pick a spot on the ground inside the map."}
	end
	if not Daytime() and InLobby(root.Position) and not InLobby(land) then
		return {Ok = false, Error = "NightWall", Message = "The night wall blocks the way - stay in the lobby until morning."}
	end
	if not Take(player, def.Key, 1) then return {Ok = false, Error = "None"} end
	local from = root.Position
	local hip = (humanoid.HipHeight > 0 and humanoid.HipHeight or 2) + root.Size.Y * 0.5 + 0.3
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.new(land + Vector3.new(0, hip, 0)) * (root.CFrame - root.CFrame.Position)
	Event:FireAllClients({Kind = "Warp", Player = player, From = from, To = land + Vector3.new(0, hip, 0)})
	PlayAt("Magic Zoom", land, 0.9)
	return {Ok = true}
end

--..One-shot items..--
local function SpawnCucumber(player, record, point)
	local spawn = Api("CucumberSpawnerAPI", "SpawnCarried")
	if not spawn then return nil, "no spawner" end
	local ok, holder = pcall(spawn.Invoke, spawn, record.Zone or "Spawn", record.Type, record.Golden == true, point,
		{Anywhere = true, Force = true, Material = record.Material, Mutations = record.Mutations, SizeTier = record.SizeTier})
	if not ok then return nil, tostring(holder) end
	if not holder then return nil, "spawn refused" end
	--.. out of the zone folder: CucumberSpawner.ClearFields wipes those at every dusk and dawn, and a planted
	--.. cucumber must wait for its owner. Breakables.Planted is still under workspace.Breakables, so the
	--.. Lift prompt (CucumberCarry.AttachCollectPrompt) and the collect path keep working.
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

local function PlantSeed(player, def)
	if player:GetAttribute("InPortalMinigame") == true then return {Ok = false, Error = "Minigame", Message = "Not inside a minigame."} end
	if not Daytime() then return {Ok = false, Error = "Night", Message = NIGHT_MESSAGE} end
	local root, _, character = Alive(player)
	if not root then return {Ok = false, Error = "NoCharacter"} end
	local pick = Api("CucumberSpawnerAPI", "PickTypeName")
	local zone = BestZone(player)
	local okPick, typeName = pcall(function() return pick and pick:Invoke(zone) end)
	if not (okPick and type(typeName) == "string") then return {Ok = false, Error = "NoType", Message = "The fields are not ready - try again in a moment."} end
	local void = def.Key == "VoidSeed"
	local point = PlantSpot(player, root, character)
	local holder, err = SpawnCucumber(player, {Zone = zone, Type = typeName, Golden = not void, Material = (not void) and "Golden" or nil, Mutations = void and "VOID" or nil}, point)
	if not holder then
		warn("[ItemService] seed spawn failed: " .. tostring(err))
		return {Ok = false, Error = "SpawnFailed", Message = "Nothing sprouted - try again in a moment."}
	end
	Take(player, def.Key, 1)
	Event:FireAllClients({Kind = "Planted", Key = def.Key, Player = player, Position = point, Name = holder.Name, Void = void})
	PlayAt("Magic Shimmer", point, 0.9)
	return {Ok = true, Name = holder.Name}
end

local function Redeem(player, def)
	if player:GetAttribute("InPortalMinigame") == true then return {Ok = false, Error = "Minigame", Message = "Not inside a minigame."} end
	if not Daytime() then return {Ok = false, Error = "Night", Message = NIGHT_MESSAGE} end
	local items, data = ItemsOf(player)
	if not items then return {Ok = false, Error = "NotLoaded"} end
	local lost = data.LostCucumbers
	if #lost == 0 then return {Ok = false, Error = "NothingLost", Message = "The zombies haven't stolen anything from you."} end
	local root, _, character = Alive(player)
	if not root then return {Ok = false, Error = "NoCharacter"} end
	local record = table.remove(lost)
	if type(record) ~= "table" or type(record.Type) ~= "string" then
		DataService.RequestSave(player)
		return {Ok = false, Error = "BadRecord", Message = "That cucumber is gone for good."}
	end
	local point = PlantSpot(player, root, character)
	local holder, err = SpawnCucumber(player, record, point)
	if not holder then
		table.insert(lost, record) -- keep it for a better moment
		warn("[ItemService] redeem spawn failed: " .. tostring(err))
		return {Ok = false, Error = "SpawnFailed", Message = "Couldn't bring it back right now - try again in a moment."}
	end
	Take(player, def.Key, 1) -- saves (the LostCucumbers change rides along)
	Event:FireAllClients({Kind = "Redeemed", Player = player, Position = point, Name = record.Name or holder.Name, Left = #lost})
	PlayAt("Magic Shimmer", point, 0.9)
	return {Ok = true, Name = record.Name or holder.Name}
end

local function PickZombiePet()
	if not PetsCatalog then return nil end
	if rng:NextNumber() < Catalog.ZOMBIE_EGG.GregoryChance and PetsCatalog.PETS["Gregory"] then return "Gregory", true end
	local byRarity = {}
	for key, entry in pairs(PetsCatalog.PETS) do
		if key ~= "Gregory" and type(entry) == "table" then
			local rarity = entry.Rarity or "Common"
			byRarity[rarity] = byRarity[rarity] or {}
			table.insert(byRarity[rarity], key)
		end
	end
	local rarities, weights, total = {}, {}, 0
	for rarity, list in pairs(byRarity) do
		local w = Catalog.ZOMBIE_EGG.RarityWeights[rarity] or 0
		if w > 0 and #list > 0 then
			table.insert(rarities, list)
			table.insert(weights, w)
			total += w
		end
	end
	if total <= 0 then return nil end
	local pick = rng:NextNumber() * total
	for i, list in ipairs(rarities) do
		pick -= weights[i]
		if pick <= 0 then return list[rng:NextInteger(1, #list)], false end
	end
	local last = rarities[#rarities]
	return last[rng:NextInteger(1, #last)], false
end

local function CrackEgg(player, def)
	local pets = PetServiceOf()
	if not (pets and type(pets.GrantFromEgg) == "function" and (type(pets.IsStarted) ~= "function" or pets.IsStarted())) then
		return {Ok = false, Error = "NoPets", Message = "Pets are not ready yet."}
	end
	local petKey, secret = PickZombiePet()
	if not petKey then return {Ok = false, Error = "NoPool"} end
	local okG, record, info = pcall(pets.GrantFromEgg, player, {Mutations = Catalog.ZOMBIE_EGG.Mutations}, petKey)
	if not okG then
		warn("[ItemService] GrantFromEgg failed: " .. tostring(record))
		return {Ok = false, Error = "GrantFailed", Message = "The egg wouldn't crack - try again."}
	end
	if not record then
		local code = type(info) == "table" and info.Error or "Unknown"
		if code == "InventoryFull" then return {Ok = false, Error = code, Message = "Your pet inventory is full."} end
		return {Ok = false, Error = code, Message = "The egg wouldn't crack - try again."}
	end
	Take(player, def.Key, 1)
	local display = (PetsCatalog and type(PetsCatalog.DisplayNameOf) == "function" and PetsCatalog.DisplayNameOf(petKey)) or petKey
	local rarity = (PetsCatalog and type(PetsCatalog.RarityOf) == "function" and PetsCatalog.RarityOf(petKey)) or "Common"
	if type(pets.FinishPresentation) == "function" then
		local root = Alive(player)
		pcall(pets.FinishPresentation, player, record.Id, root and (root.Position + root.CFrame.LookVector * 4) or nil)
	end
	Event:FireAllClients({Kind = "Hatched", Player = player, Pet = petKey, Name = display, Rarity = rarity, Secret = secret == true,
		Equipped = type(info) == "table" and info.Equipped == true})
	local root = Alive(player)
	if root then PlayAt("EggPop", root.Position, 1) end
	return {Ok = true, Pet = petKey, Name = display}
end

local USE_HANDLERS = {GoldenSeed = PlantSeed, VoidSeed = PlantSeed, RedemptionToken = Redeem, ZombieEgg = CrackEgg}

--..The use request..--
local LastUse = {}
local function HoldsTool(player, key)
	local character = player.Character
	if not character then return false end
	for _, tool in ipairs(character:GetChildren()) do
		if tool:IsA("Tool") and tool:GetAttribute("ItemKey") == key then return true end
	end
	return false
end

UseRemote.OnServerInvoke = function(player, request)
	if typeof(player) ~= "Instance" or player.Parent ~= Players then return {Ok = false, Error = "BadRequest"} end
	if type(request) ~= "table" then return {Ok = false, Error = "BadRequest"} end
	local def = Catalog.Get(request.Key)
	if not def then return {Ok = false, Error = "BadItem"} end
	local now = os.clock()
	if LastUse[player] and now - LastUse[player] < Catalog.USE_COOLDOWN then return {Ok = false, Error = "Cooldown"} end
	LastUse[player] = now
	if not DataService.IsLoaded(player) then return {Ok = false, Error = "NotLoaded"} end
	if CountOf(player, def.Key) < 1 then
		Reconcile(player)
		return {Ok = false, Error = "None", Message = "You have no " .. def.Name .. " left."}
	end
	if not HoldsTool(player, def.Key) then return {Ok = false, Error = "NotHeld", Message = "Take the " .. def.Name .. " in hand first."} end
	if not Alive(player) then return {Ok = false, Error = "NoCharacter"} end
	local ok, result
	if def.Kind == "Drink" then
		ok, result = pcall(Drink, player, def)
	elseif def.Kind == "Throw" then
		ok, result = pcall(Throw, player, def, request.Direction)
	elseif def.Kind == "Aim" then
		ok, result = pcall(Warp, player, def, request.Target)
	else
		local handler = USE_HANDLERS[def.Key]
		if not handler then return {Ok = false, Error = "NoHandler"} end
		ok, result = pcall(handler, player, def)
	end
	if not ok then
		warn("[ItemService] " .. def.Key .. " failed for " .. player.Name .. ": " .. tostring(result))
		return {Ok = false, Error = "Failed", Message = "Something went wrong - try again."}
	end
	return result
end

--..Drops..--
local Drops = {} -- [model] = {Def, SpawnAt}
local function SpawnDrop(def, position)
	local template = TemplateOf(def.Key)
	if not template then return nil end
	local model = template:Clone()
	model.Name = def.Name
	model:SetAttribute("ItemKey", def.Key)
	model:SetAttribute("DisplayName", def.Name)
	model:SetAttribute("Rarity", def.Rarity)
	model:SetAttribute("SpawnAt", workspace:GetServerTimeNow())
	local exclude = {}
	local zombies = Api("ZombieAPI", "Zombies")
	if zombies then
		local ok, list = pcall(zombies.Invoke, zombies)
		if ok and type(list) == "table" then for _, z in ipairs(list) do table.insert(exclude, z) end end
	end
	for _, player in ipairs(Players:GetPlayers()) do if player.Character then table.insert(exclude, player.Character) end end
	local ground = GroundBelow(position, exclude) or (position - Vector3.new(0, 2.5, 0))
	model:PivotTo(CFrame.new(ground + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0))
	CollectionService:AddTag(model, DROP_TAG)
	model.Parent = DropsFolder
	Drops[model] = {Def = def, SpawnAt = os.clock()}
	return model
end

local function DropRoll(position, level)
	if typeof(position) ~= "Vector3" then return nil end
	local def = Catalog.RollDrop(level, rng)
	if not def then return nil end
	local model = SpawnDrop(def, position)
	if model then print(("[ItemService] %s dropped (zombie level %s)"):format(def.Name, tostring(level))) end
	return model
end

local function PickTick()
	for model, info in pairs(Drops) do
		if not model.Parent then
			Drops[model] = nil
		elseif os.clock() - info.SpawnAt > Catalog.DROP_LIFETIME then
			Drops[model] = nil
			model:Destroy()
		else
			local at = model:GetPivot().Position
			local best, bestDist = nil, Catalog.PICKUP_RADIUS
			for _, player in ipairs(Players:GetPlayers()) do
				local root = Alive(player)
				if root and DataService.IsLoaded(player) then
					local d = (root.Position - at).Magnitude
					if d <= bestDist then best, bestDist = player, d end
				end
			end
			if best then
				Drops[model] = nil
				model:Destroy()
				local ok, count = Give(best, info.Def.Key, 1)
				if ok then
					Event:FireClient(best, {Kind = "Picked", Key = info.Def.Key, Name = info.Def.Name, Count = count, Position = at})
					Event:FireAllClients({Kind = "PickedFX", Key = info.Def.Key, Position = at, Player = best})
					PlayAt("Collect", at, 0.8)
				end
			end
		end
	end
end

--..Lost cucumbers (ZombieRaidService.Escape reports them)..--
local MAX_LOST = 20
local function RecordLoss(player, record)
	if typeof(player) ~= "Instance" or type(record) ~= "table" then return false end
	local items, data = ItemsOf(player)
	if not items then return false end
	local lost = data.LostCucumbers
	table.insert(lost, {
		Name = type(record.Name) == "string" and record.Name or nil,
		Zone = type(record.Zone) == "string" and record.Zone or "Spawn",
		Type = type(record.Type) == "string" and record.Type or nil,
		Golden = record.Golden == true,
		Material = type(record.Material) == "string" and record.Material or nil,
		Mutations = type(record.Mutations) == "string" and record.Mutations or nil,
		SizeTier = type(record.SizeTier) == "string" and record.SizeTier or nil,
		At = os.time(),
	})
	while #lost > MAX_LOST do table.remove(lost, 1) end
	DataService.RequestSave(player)
	return true
end

--..ServerStorage.ItemAPI..--
do
	local api = ServerStorage:FindFirstChild("ItemAPI")
	if api then api:Destroy() end
	api = Instance.new("Folder")
	api.Name = "ItemAPI"
	local function bindable(name, fn)
		local b = Instance.new("BindableFunction")
		b.Name = name
		b.OnInvoke = fn
		b.Parent = api
	end
	bindable("Drop", DropRoll)
	bindable("DropItem", function(key, position)
		local def = Catalog.Get(key)
		return def and typeof(position) == "Vector3" and SpawnDrop(def, position) or nil
	end)
	bindable("Give", function(player, key, n) return Give(player, key, n) end)
	bindable("Count", function(player, key) return CountOf(player, key) end)
	bindable("RecordLoss", RecordLoss)
	api.Parent = ServerStorage
end

--..One-time gifts (2026-09-23, user: "give me like 20 warp portals"): claimed once per PROFILE the first time that
--..player's data loads with this script running (Data.ItemGifts[id] = true), so a live session lock can never
--..swallow an edit-mode DataStore write. Add a row, never edit a claimed one..--
local GIFTS = {
	{Id = "pearls-2026-09-23", UserIds = {140977250}, Items = {WarpPearl = 20}, Toast = "20 Warp Pearls landed in your inventory!"},
}
local function ClaimGifts(player)
	local items, data = ItemsOf(player)
	if not items then return end
	if type(data.ItemGifts) ~= "table" then data.ItemGifts = {} end
	for _, gift in ipairs(GIFTS) do
		if not data.ItemGifts[gift.Id] and table.find(gift.UserIds, player.UserId) then
			data.ItemGifts[gift.Id] = true
			for key, n in pairs(gift.Items) do Give(player, key, n) end
			DataService.RequestSave(player)
			if gift.Toast then task.delay(2, Toast, player, gift.Toast, "Success") end
			print(("[ItemService] gift %s claimed by %s"):format(gift.Id, player.Name))
		end
	end
end

--..Players..--
local function OnCharacter(player)
	task.delay(0.5, function() SafeReconcile(player) end)
end

local function OnLoaded(player)
	SafeReconcile(player)
	local ok, err = pcall(ClaimGifts, player)
	if not ok then warn("[ItemService] gifts for " .. player.Name .. ": " .. tostring(err)) end
end

local function OnPlayer(player)
	player.CharacterAdded:Connect(function() OnCharacter(player) end)
	if player.Character then OnCharacter(player) end
	task.spawn(function()
		DataService.WaitForData(player, 60)
		OnLoaded(player)
	end)
end
Players.PlayerAdded:Connect(OnPlayer)
for _, player in ipairs(Players:GetPlayers()) do OnPlayer(player) end
Players.PlayerRemoving:Connect(function(player) LastUse[player] = nil end)
if type(DataService.OnProfileLoaded) == "function" then
	DataService.OnProfileLoaded(function(player) task.defer(OnLoaded, player) end)
end

task.spawn(function()
	local nextReconcile = os.clock() + RECONCILE
	while true do
		task.wait(PICK_TICK)
		local ok, err = pcall(PickTick)
		if not ok then warn("[ItemService] pick tick: " .. tostring(err)) end
		if os.clock() >= nextReconcile then
			nextReconcile = os.clock() + RECONCILE
			for _, player in ipairs(Players:GetPlayers()) do SafeReconcile(player) end
		end
	end
end)

--..Studio hooks..--
if RunService:IsStudio() then
	workspace:SetAttribute("ItemDev", nil)
	workspace:GetAttributeChangedSignal("ItemDev"):Connect(function()
		local cmd = workspace:GetAttribute("ItemDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		workspace:SetAttribute("ItemDev", nil)
		local player = Players:GetPlayers()[1]
		if not player then return end
		local key, n = cmd:match("^give:(%w+):?(%d*)$")
		if key then
			local ok, count = Give(player, key, tonumber(n) or 1)
			print(("[ItemService] dev give %s -> %s (%s)"):format(key, tostring(ok), tostring(count)))
			return
		end
		key = cmd:match("^drop:(%w+)$")
		if key then
			local root = Alive(player)
			local def = Catalog.Get(key)
			local model = def and root and SpawnDrop(def, root.Position + root.CFrame.LookVector * 6)
			print("[ItemService] dev drop " .. key .. " -> " .. tostring(model))
			return
		end
		local level = cmd:match("^roll:(%d+)$")
		if level then
			local root = Alive(player)
			local model = root and DropRoll(root.Position + root.CFrame.LookVector * 6, tonumber(level))
			print("[ItemService] dev roll level " .. level .. " -> " .. tostring(model and model.Name))
			return
		end
		key = cmd:match("^use:(%w+)$")
		if key then
			local def = Catalog.Get(key)
			if not def then return end
			local result
			if def.Kind == "Drink" then result = Drink(player, def)
			elseif def.Kind == "Throw" then
				local root = Alive(player)
				result = Throw(player, def, root and root.CFrame.LookVector or Vector3.zAxis)
			elseif def.Kind == "Aim" then
				local root = Alive(player)
				result = Warp(player, def, root and (root.Position + root.CFrame.LookVector * 30) or nil)
			else result = USE_HANDLERS[key](player, def) end
			print("[ItemService] dev use " .. key .. " -> " .. game:GetService("HttpService"):JSONEncode(result))
			return
		end
		if cmd == "lose" then
			local ok = RecordLoss(player, {Name = "Dev Cucumber", Zone = "Spawn", Type = "Cucumber", Golden = false})
			print("[ItemService] dev lose -> " .. tostring(ok))
			return
		end
		if cmd == "clear" then
			local items, data = ItemsOf(player)
			if items then
				for k in pairs(items) do items[k] = nil end
				data.LostCucumbers = {}
				DataService.RequestSave(player)
				Reconcile(player)
			end
			for model in pairs(Drops) do model:Destroy() end
			print("[ItemService] dev clear")
		end
	end)
end

print("[ItemService] " .. #Catalog.ITEMS .. " drop items ready (Remotes.ItemUse / ItemEvent, ServerStorage.ItemAPI, workspace.ItemDrops)")
