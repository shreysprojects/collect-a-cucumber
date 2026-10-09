--[[
	CucumberCarry  (Script, ServerScriptService)
	Proximity-prompt pickup, shoulder carry and plot placement for the cucumbers
	CucumberSpawner spawns. Port of the Zombie Cucumber Game's CarryService (armful
	model welded to the LEFT SHOULDER + an IKControl steadying hand) wired to this
	place's conventions (ReplicatedStorage.Remotes, EggPlacement's plot rules).

	  * every spawned cucumber (CollectionService tag "Breakable") gets a "Lift"
	    ProximityPrompt on its root part and a WeightKg attribute
	    (ReplicatedStorage.Modules.CucumberLift: 3 kg for a Spawn slice .. 1T kg for
	    a Neon slice; 1 kg asks for 1 Strength)
	  * THE LIFT (2026-09-16, user: "delete the current pickup system entirely; a long
	    bar with the strength icon drifting left, every click pushes it right; all the
	    way right = picked up, all the way left = the pickup fails; strength-based -- lots
	    of strength = 2-3 clicks, not enough = the icon always wins"): a Lift press locks
	    the cucumber (CollectingBy, prompt off, Busy) and sends {Kind = "Start"} through
	    Remotes.CucumberLift to every client with the bar's numbers for THIS player
	    (CucumberLift.Params(strength / kg)). CucumberLiftClient walks the player up,
	    frames the camera, runs the bar and the pose (the Blender CucumberLift clip
	    scrubbed by progress), and answers {Kind = "Result", Result = "done" | "fail" |
	    "cancel"}. A "done" is believed only when strength >= kg and the bar has been up
	    at least MinClicks / MAX_CPS seconds; then {Kind = "Hoist"} goes out, HOIST_LEN
	    later Grab() swaps the field cucumber for the shoulder copy (re-checking life /
	    reach / hands). "fail" / "cancel" / a bar older than MAX_TIME release everything
	    ({Kind = "Fail"} / {Kind = "Cancel"} to every client). Progress ticks from the
	    lifter are relayed to the other clients so they see the pose too.
	  * once it is on the shoulder it stays there: no heavy carries, no slips, no falls
	    (the old bands / grip / stumble / carry modes are gone). Player attributes
	    CarryingCucumber (display name) / CarryingCucumberZone / CarryingCucumberGolden /
	    CarryingCucumberMaterial / CarryingCucumberMutations / CarryingCucumberSize /
	    CarryingCucumberTrait / CarryingCucumberKg / CucumberCarrySafe (inside the lobby).
	    CarryClient draws the billboard + DROP button.
	  * LOBBY: once a carrier's root is inside the lobby box (inner faces of
	    Map.Borders."Lobby Border" walls, read at start) the carry counts as secured:
	    CucumberCarrySafe = true (GuardianService banks it, CucumberAdventure records it)
	    and, on the way in, the owner gets CarryFX {Kind = "LobbyReached"} (camera bounce
	    + sound).
	  * DROP RULE (2026-09-07, user): inside ANY biome (Map.Biomes floor slabs, BiomeAt) a
	    dropped cucumber lands on the spot you are on, whatever field it came from;
	    outside the biomes (the lobby, off the map) it flies home to a fresh spot in its
	    own field (SpawnCarried with no point, FlyHome cue).
	  * Remotes.requestCucumberPlacement(cframe) -> true/false, reason: EggPlacement's
	    contract -- only the client's X/Z + yaw are trusted, you must stand at YOUR
	    plot, the footprint must stay inside it and must not overlap plot.Placed. The
	    carried model is anchored onto the plot in its natural resting pose
	    (attributes Owner / CucumberName / Zone / TypeName / Golden, tag
	    "PlacedCucumber") and shows NO prompt (user call 2026-09-05). BaseSaveService
	    saves / restores them (RestorePlaced / ClearPlaced in ServerStorage.CucumberCarryAPI).
	  * FULL-SIZE ON THE PLOT (2026-09-08): the shoulder copy is shrunk to an armful, but
	    BuildCarryModel records the rest pose at FIELD scale and a PlaceScale factor, and
	    Place() grows the model back by it. Giants (SizeTier / SizeScale) ride a little
	    bigger on the shoulder (CARRY_GIANT_BONUS) and keep their size through drops.
	  * prompts use Style = Custom: CucumberPromptClient draws the key badge + the name,
	    "Lift" and the weight; the default Roblox panel never shows
	  * Remotes.CarryFX (server -> client): {Kind = Pickup | Replant | FlyHome | Placed |
	    Refused | LobbyReached, ...} cues for CarryClient
	  * ServerStorage.CucumberCarryAPI: DropForNight (DayNightCycle), TakeCarried
	    (GuardianService), RestorePlaced / ClearPlaced (BaseSaveService)
	  * Studio dev hook: workspace:SetAttribute("CarryDev", "collect:<Name>" (the nearest
	    cucumber, starts the bar) | "win:<Name>" | "lose:<Name>" (settle the running bar)
	    | "drop:<Name>" | "pickup:<Name>")
	  * CUCUMBER ID + PET BUFFS (2026-09-22, pet-system polish): every placed cucumber carries a stable
	    CucumberId attribute (a fresh GUID in Place, the saved record.Id in RestorePlaced - record
	    repair stays with BaseSave / the migration), set with the other attributes BEFORE the tag.
	    RestorePlaced also stamps the record's unexpired PetBuffs back onto the model
	    (ServerStorage.PetBuffService.StampFromRecord, absolute expiry). PickUp clears the buffs
	    (PetBuffService.ClearCucumber "PickUp") and the id before it untags. PetBuffService is
	    optional (resolved lazily): without it ids are still minted and nothing else changes.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService") -- 2026-09-22: CucumberId
local function Lazy(name) -- 2026-09-22: pet-system modules are optional until their stage is installed
	local cache
	return function()
		if cache then return cache end
		local module = ServerStorage:FindFirstChild(name)
		if not module then return nil end
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then cache = result end
		return cache
	end
end
local PetBuffs = Lazy("PetBuffService") -- StampFromRecord / ClearCucumber

--..Config..--
local CARRY_LONGEST_AXIS = 2.8 -- studs: an armful, whatever the field model's size
--.. a giant (CucumberMutations.SIZES) rides this much bigger per extra size step, so you can see
--.. what you are hauling without it eating the screen: x2 -> 3.8, x3 -> 4.8, x4 -> 5.7 studs
local CARRY_GIANT_BONUS = 0.35
local PROMPT_DISTANCE = 10
local PROMPT_HOLD = 0
local REACH = 16 -- server-side distance check for a Lift / Pick up trigger
local PLACE_COOLDOWN = 0.2
local COLLISION_SHRINK = 0.96 -- keep in step with EggPlacement / CucumberPlacementClient
local BOUNDS_EPSILON = 0.05
local AT_BASE_MARGIN = 6 -- keep in step with CucumberPlacementClient
local PROGRESS_RELAY_HZ = 12 -- the lifter's progress ticks are relayed to the other clients at most this often
--.. rest it ON the left shoulder like a carried log: leaned into the neck, nose up a touch
local SHOULDER_OFFSET = CFrame.new(-1.05, 1.05, 0.05) * CFrame.Angles(math.rad(-10), 0, math.rad(8))
local PLOTS = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

--..Instances..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local function remote(className, name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
local DropRemote = remote("RemoteEvent", "DropCucumber")
local PlaceRemote = remote("RemoteFunction", "requestCucumberPlacement")
local FXRemote = remote("RemoteEvent", "CarryFX")
local LiftRemote = remote("RemoteEvent", "CucumberLift") -- server -> all clients: the lift cues; client -> server: Result / Progress
local Adventure = require(ServerStorage:WaitForChild("CucumberAdventure"))
local CucumberLift = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CucumberLift"))
local CucumberFootprint = require(ReplicatedStorage.Modules:WaitForChild("CucumberFootprint")) -- 2026-09-13: the (smaller) collision box of a placed cucumber

local API = ServerStorage:WaitForChild("CucumberSpawnerAPI", 30)
local SpawnCarried = API and API:WaitForChild("SpawnCarried", 10)
local InField = API and API:WaitForChild("InField", 10)
if not (SpawnCarried and InField) then
	warn("[CucumberCarry] CucumberSpawner API missing; drops will discard cucumbers")
end

--..State..--
local Carrying = {} -- [player] = {Model, Name, Zone, TypeName, Golden, Material, Mutations, PoseIK, Kg, InLobby, AncestryConn, ...}
local Busy = {} -- [player] = true during a lift / pick up
local PendingLift = {} -- [player] = attempt (see Collect)
local NextLiftToken = 0
local LastPlace = {} -- [player] = os.clock()
local LastRelay = {} -- [player] = os.clock() of the last relayed progress tick

--..Helpers..--
local function FX(player, payload)
	if player.Parent == Players then FXRemote:FireClient(player, payload) end
end

local function RootPartOf(holder)
	if holder:IsA("BasePart") then return holder end
	return holder.PrimaryPart or holder:FindFirstChildWhichIsA("BasePart", true)
end

--.. How close you must be to lift this one. The check measures to the model's CENTRE, so a
--.. giant (2026-09-08) holds its own centre well above your head -- a COLOSSAL tree's is 25 studs
--.. up, further than the flat REACH even when you are standing on its roots. It gets the same
--.. multiplier the prompt radius does, or the prompt would light up and the key would do nothing.
local function ReachFor(holder)
	return REACH * math.max(tonumber(holder:GetAttribute("SizeScale")) or 1, 1)
end

--.. Model:ScaleTo moves geometry only -- never ParticleEmitters, never Lights. A giant's sparkles
--.. and glow are authored for its FIELD size (CucumberSpawner.ApplyModifierLooks), so they have to
--.. travel with it: shrunk onto the shoulder, grown back onto the plot (2026-09-08). Without this a
--.. COLOSSAL rides around with a 40-stud light welded beside the player's head.
local function ScaleLooks(model, factor)
	if factor == 1 then return end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			local keys = {}
			for _, k in ipairs(d.Size.Keypoints) do keys[#keys + 1] = NumberSequenceKeypoint.new(k.Time, k.Value * factor) end
			d.Size = NumberSequence.new(keys)
			d.Rate *= factor
		elseif d:IsA("Light") then
			d.Range = math.clamp(d.Range * factor, 1, 60)
		end
	end
end

--.. root part, character, humanoid of a LIVING player (nil otherwise)
local function Alive(player)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0 and char.Parent) then return nil end
	return char:FindFirstChild("HumanoidRootPart"), char, humanoid
end

--..Lobby box: inner faces of the "Lobby Border" walls (LobbyLayout moves them, so read live)..--
local LobbyBox -- {MinX, MaxX, MinZ, MaxZ}
local function ComputeLobbyBox()
	local borders = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Borders")
	local border = borders and borders:FindFirstChild("Lobby Border")
	local minX, maxX, minZ, maxZ
	for _, p in ipairs(border and border:GetChildren() or {}) do
		if p:IsA("BasePart") and p.Size.Y < 20 then -- wall bands, not the roof strips
			--.. the bands are rotated (the north / south walls are Size.X-thin parts turned
			--.. 90 deg), so classify by WORLD half-extents
			local hx, hz = p.Size.X * 0.5, p.Size.Z * 0.5
			local r, l = p.CFrame.RightVector, p.CFrame.LookVector
			local ex = math.abs(r.X) * hx + math.abs(l.X) * hz
			local ez = math.abs(r.Z) * hx + math.abs(l.Z) * hz
			if ex <= 5 and ez > 10 then -- west / east walls (thin in world X)
				minX = math.min(minX or math.huge, p.Position.X + ex)
				maxX = math.max(maxX or -math.huge, p.Position.X - ex)
			elseif ez <= 5 and ex > 10 then -- north / south walls (thin in world Z)
				minZ = math.min(minZ or math.huge, p.Position.Z + ez)
				maxZ = math.max(maxZ or -math.huge, p.Position.Z - ez)
			end
		end
	end
	if minX and maxX and minZ and maxZ and maxX > minX and maxZ > minZ then
		return {MinX = minX, MaxX = maxX, MinZ = minZ, MaxZ = maxZ}
	end
	--.. no border walls: the plots row plus the walkway in front of it
	local pMinX, pMaxX, pMinZ, pMaxZ
	for _, plot in ipairs(PLOTS:GetChildren()) do
		if plot:IsA("BasePart") then
			local hx, hz = plot.Size.X * 0.5, plot.Size.Z * 0.5
			local ex = math.abs(plot.CFrame.RightVector.X) * hx + math.abs(plot.CFrame.LookVector.X) * hz
			local ez = math.abs(plot.CFrame.RightVector.Z) * hx + math.abs(plot.CFrame.LookVector.Z) * hz
			pMinX = math.min(pMinX or math.huge, plot.Position.X - ex)
			pMaxX = math.max(pMaxX or -math.huge, plot.Position.X + ex)
			pMinZ = math.min(pMinZ or math.huge, plot.Position.Z - ez)
			pMaxZ = math.max(pMaxZ or -math.huge, plot.Position.Z + ez)
		end
	end
	if pMinX then return {MinX = pMinX - 80, MaxX = pMaxX + 8, MinZ = pMinZ - 12, MaxZ = pMaxZ + 12} end
	return nil
end

--..Biomes: one XZ box per Map.Biomes."NN Name" folder from its Floor parts (built once);
--..a biome without Floor parts falls back to its SpawnArea field slab (140 x 112, like
--..CucumberSpawner.SlabIndexAt). Used by the drop rule.
local Biomes -- {{Index, Name, MinX, MaxX, MinZ, MaxZ, Center}} sorted by Index
local BIOME_MARGIN = 6
local function BuildBiomes()
	local list = {}
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Biomes")
	local spawnArea = workspace:FindFirstChild("SpawnArea")
	for _, b in ipairs(folder and folder:GetChildren() or {}) do
		local index, name = b.Name:match("^(%d+)%s+(.+)$")
		index = tonumber(index)
		if index then
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			local floor = b:FindFirstChild("Floor")
			for _, d in ipairs(floor and floor:GetDescendants() or {}) do
				if d:IsA("BasePart") then
					local cf, size = d.CFrame, d.Size
					local hx = math.abs(cf.RightVector.X) * size.X * 0.5 + math.abs(cf.UpVector.X) * size.Y * 0.5 + math.abs(cf.LookVector.X) * size.Z * 0.5
					local hz = math.abs(cf.RightVector.Z) * size.X * 0.5 + math.abs(cf.UpVector.Z) * size.Y * 0.5 + math.abs(cf.LookVector.Z) * size.Z * 0.5
					minX, maxX = math.min(minX, cf.X - hx), math.max(maxX, cf.X + hx)
					minZ, maxZ = math.min(minZ, cf.Z - hz), math.max(maxZ, cf.Z + hz)
				end
			end
			if minX == math.huge then
				local field = spawnArea and spawnArea:FindFirstChild(tostring(index))
				if field and field:IsA("BasePart") then
					minX, maxX = field.Position.X - 70, field.Position.X + 70
					minZ, maxZ = field.Position.Z - 56, field.Position.Z + 56
				end
			end
			if minX ~= math.huge then
				table.insert(list, {Index = index, Name = name, MinX = minX, MaxX = maxX, MinZ = minZ, MaxZ = maxZ, Center = Vector3.new((minX + maxX) * 0.5, 0, (minZ + maxZ) * 0.5)})
			end
		end
	end
	table.sort(list, function(a, b) return a.Index < b.Index end)
	return list
end

local InLobby -- defined below

--.. the biome entry a position is in, nil outside every biome (the lobby wins at the seam)
local function BiomeAt(position)
	if InLobby(position) then return nil end
	Biomes = Biomes or BuildBiomes()
	for _, b in ipairs(Biomes) do
		if position.X >= b.MinX - BIOME_MARGIN and position.X <= b.MaxX + BIOME_MARGIN and position.Z >= b.MinZ - BIOME_MARGIN and position.Z <= b.MaxZ + BIOME_MARGIN then
			return b
		end
	end
	return nil
end

InLobby = function(position)
	local box = LobbyBox
	if not box then
		box = ComputeLobbyBox()
		LobbyBox = box
		if not box then return false end
	end
	return position.X >= box.MinX and position.X <= box.MaxX and position.Z >= box.MinZ and position.Z <= box.MaxZ
end

--.. world-aligned bounding box of the holder's parts in its resting pose
local function WorldAABB(holder)
	local minV, maxV
	local parts = holder:IsA("BasePart") and {holder} or {}
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Shadow" then parts[#parts + 1] = d end
	end
	for _, p in ipairs(parts) do
		local cf, half = p.CFrame, p.Size * 0.5
		for _, sx in ipairs({-1, 1}) do
			for _, sy in ipairs({-1, 1}) do
				for _, sz in ipairs({-1, 1}) do
					local c = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
					minV = minV and Vector3.new(math.min(minV.X, c.X), math.min(minV.Y, c.Y), math.min(minV.Z, c.Z)) or c
					maxV = maxV and Vector3.new(math.max(maxV.X, c.X), math.max(maxV.Y, c.Y), math.max(maxV.Z, c.Z)) or c
				end
			end
		end
	end
	return minV, maxV
end

--.. Clone the field cucumber into a self-contained, welded, armful-sized model and
--.. record its natural resting pose (RestRotation / RestSize / RestLift attributes)
--.. so a plot placement can stand it up exactly the way it sat in the field.
local function BuildCarryModel(src)
	local rest = src:GetPivot()
	local minV, maxV = WorldAABB(src)
	local model
	if src:IsA("Model") then
		model = src:Clone()
	else
		local partClone = src:Clone()
		model = Instance.new("Model")
		partClone.Parent = model
		model.PrimaryPart = partClone
	end
	--.. gameplay leftovers have no place on a prop: prompts, scripts, the ground shadow
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BillboardGui") or obj:IsA("ClickDetector") or obj:IsA("ProximityPrompt")
			or obj:IsA("LuaSourceContainer") or (obj:IsA("BasePart") and obj.Name == "Shadow") then
			obj:Destroy()
		end
	end
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then model:Destroy() return nil end
	model.PrimaryPart = primary
	--.. the clone inherits the spawner's "Breakable" tag; a carried / placed copy is
	--.. NOT a field cucumber (no prompt, no population bookkeeping)
	CollectionService:RemoveTag(model, "Breakable")
	for _, obj in ipairs(model:GetDescendants()) do
		if CollectionService:HasTag(obj, "Breakable") then CollectionService:RemoveTag(obj, "Breakable") end
	end
	--.. field cucumbers are anchored with no welds; a carried copy must be one rigid body
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = false
			obj.CanCollide = false
			obj.CanQuery = false
			obj.CanTouch = false
			obj.Massless = true
			if obj ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = obj
				weld.Parent = obj
			end
		end
	end
	--.. shrink to an armful; never upscale. A giant rides a little bigger than a normal
	--.. cucumber (CARRY_GIANT_BONUS) so the haul reads on screen.
	local sizeScale = math.max(tonumber(src:GetAttribute("SizeScale")) or 1, 1)
	local target = CARRY_LONGEST_AXIS * (1 + CARRY_GIANT_BONUS * (sizeScale - 1))
	local ext = model:GetExtentsSize()
	local longest = math.max(ext.X, ext.Y, ext.Z, 0.001)
	local scale = 1
	if longest > target then
		scale = target / longest
		model:ScaleTo(model:GetScale() * scale)
	end
	ScaleLooks(model, scale)
	--.. The rest pose is recorded at FIELD scale (2026-09-08, user: "make cucumbers placed in the
	--.. users base up to scale, same size that it would be in the wild"): Place() grows the armful
	--.. back by PlaceScale before it stands the cucumber on the plot, so RestSize / RestLift --
	--.. the footprint, the bounds test, the PlotHitbox and the resting height -- all describe the
	--.. cucumber the size it was in the field.
	local size = minV and (maxV - minV) or ext
	local lift = minV and (rest.Position.Y - minV.Y) or size.Y * 0.5
	model:SetAttribute("RestRotation", rest - rest.Position)
	model:SetAttribute("RestSize", size)
	model:SetAttribute("RestLift", lift)
	model:SetAttribute("PlaceScale", 1 / scale)
	return model
end

--..Shoulder pose: the left hand reaches up to steady the load (IKControl, R15)..--
local function ApplyArmPose(player, entry)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local upperArm = char and char:FindFirstChild("LeftUpperArm")
	local hand = char and char:FindFirstChild("LeftHand")
	local primary = entry.Model and entry.Model.PrimaryPart
	if not (humanoid and upperArm and hand and primary) then return end
	local grip = Instance.new("Attachment")
	grip.Name = "CarryGrip"
	grip.Position = Vector3.new(0.15, -0.3, -0.85) -- front-underside: the palm cups it from below
	grip.Parent = primary
	local ik = Instance.new("IKControl")
	ik.Name = "CarrySteadyIK"
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = upperArm
	ik.EndEffector = hand
	ik.Target = grip
	ik.SmoothTime = 0.12
	ik.Parent = humanoid
	entry.PoseIK = ik
end

local function RestoreArmPose(entry)
	if entry and entry.PoseIK then
		entry.PoseIK:Destroy()
		entry.PoseIK = nil
	end
end

local function SetCarryAttributes(player, entry)
	if player.Parent ~= Players then return end
	player:SetAttribute("CarryingCucumber", entry and entry.Name or nil)
	player:SetAttribute("CarryingCucumberZone", entry and entry.Zone or nil)
	player:SetAttribute("CarryingCucumberGolden", entry and entry.Golden or nil)
	player:SetAttribute("CarryingCucumberMaterial", entry and entry.Material or nil)
	player:SetAttribute("CarryingCucumberMutations", entry and entry.Mutations or nil)
	player:SetAttribute("CarryingCucumberTrait", entry and entry.Trait or nil)
	player:SetAttribute("CarryingCucumberKg", entry and entry.Kg or nil) -- the REQUIREMENT it was lifted at (StrengthProgressionServer slowdown)
	player:SetAttribute("CarryingCucumberShownKg", entry and entry.ShownKg or nil) -- the weight the player SEES (CarryClient billboard; CucumberLift.Shown)
	player:SetAttribute("CucumberCarrySafe", entry and entry.InLobby or nil)
	player:SetAttribute("CarryingCucumberSize", entry and entry.SizeTier or nil) -- "HUGE" | "MASSIVE" | "COLOSSAL" | nil
end

local function ClearCarry(player)
	local entry = Carrying[player]
	if not entry then return end
	Carrying[player] = nil
	if entry.AncestryConn then entry.AncestryConn:Disconnect() end
	RestoreArmPose(entry)
	SetCarryAttributes(player, nil)
	if entry.Model and entry.Model.Parent then entry.Model:Destroy() end
end

--.. Weld `model` onto the character's left shoulder (longest axis fore-aft) and
--.. record what it is. Replaces any current carry. Returns true on success.
local function GiveCarry(player, model, meta)
	local root, char = Alive(player)
	if not root then return false end
	local mount = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or root
	ClearCarry(player)
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = false
			obj.CanQuery = false
		end
	end
	local ext = model:GetExtentsSize()
	local rot = CFrame.new()
	if ext.X >= ext.Y and ext.X >= ext.Z then
		rot = CFrame.Angles(0, math.rad(90), 0) -- longest X -> Z
	elseif ext.Y >= ext.X and ext.Y >= ext.Z then
		rot = CFrame.Angles(math.rad(90), 0, 0) -- longest Y -> Z
	end
	model:PivotTo(mount.CFrame * SHOULDER_OFFSET * rot)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "ShoulderWeld"
	weld.Part0 = mount
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	model.Name = "CarriedCucumber"
	model.Parent = char

	local entry = {Model = model, Name = meta.Name, Zone = meta.Zone, TypeName = meta.TypeName, Golden = meta.Golden == true,
		Material = meta.Material, Mutations = meta.Mutations, SizeTier = meta.SizeTier, SizeScale = meta.SizeScale}
	entry.Trait = meta.Trait or "Normal"
	entry.Kg = tonumber(meta.Kg) or 0
	entry.ShownKg = tonumber(meta.ShownKg) or CucumberLift.Shown(entry.Kg, entry.Zone, entry.TypeName)
	entry.Required = entry.Kg -- CucumberAdventure.Secured: "heaviest cucumber secured" records
	entry.JourneyId, entry.Recorded = meta.JourneyId, meta.Recorded == true
	entry.RecordedBy = meta.RecordedBy
	entry.RecoveryUsed, entry.Rescues = meta.RecoveryUsed == true, meta.Rescues or 0
	Adventure.ApplyCosmetic(player, model)
	entry.InLobby = InLobby(root.Position) -- picked up inside the lobby: no arrival cue
	Carrying[player] = entry
	SetCarryAttributes(player, entry)
	ApplyArmPose(player, entry)
	--.. death / respawn / anything that displaces the model ends the carry (lost).
	--.. Take() and ClearCarry() disconnect this first. The LIVE parent is checked
	--.. (not the signal's argument): signals are deferred, so a detach + re-attach
	--.. inside one frame (plot pick-up) would otherwise report a stale nil parent
	--.. and destroy the freshly re-carried model.
	entry.AncestryConn = model.AncestryChanged:Connect(function()
		local current = Carrying[player]
		if not current or current.Model ~= model then return end
		if model.Parent == player.Character then return end
		Carrying[player] = nil
		if current.AncestryConn then current.AncestryConn:Disconnect() end
		RestoreArmPose(current)
		SetCarryAttributes(player, nil)
		if model.Parent then task.defer(function() model:Destroy() end) end
	end)
	return true
end

--.. Detach the carried model (shoulder weld + grip off) and hand it + its meta back
local function Take(player)
	local entry = Carrying[player]
	if not entry then return nil end
	Carrying[player] = nil
	if entry.AncestryConn then entry.AncestryConn:Disconnect() end
	RestoreArmPose(entry)
	SetCarryAttributes(player, nil)
	local model = entry.Model
	if not (model and model.Parent) then return nil end
	local primary = model.PrimaryPart
	if primary then
		for _, c in ipairs(primary:GetChildren()) do
			if (c:IsA("WeldConstraint") and c.Name == "ShoulderWeld") or (c:IsA("Attachment") and c.Name == "CarryGrip") then
				c:Destroy()
			end
		end
	end
	model.Parent = nil
	return model, entry
end

--.. a carry inside the lobby is secured: CucumberCarrySafe (GuardianService banks it,
--.. CucumberAdventure records it) + the arrival cue once per entry from outside
local function MarkLobby(player, entry, root)
	if Carrying[player] ~= entry or not root or not InLobby(root.Position) then return false end
	if not entry.InLobby then
		entry.InLobby = true
		player:SetAttribute("CucumberCarrySafe", true)
		Adventure.Secured(player, entry)
		FX(player, {Kind = "LobbyReached", Name = entry.Name})
	end
	return true
end

--..Lift (field cucumber -> the bar -> shoulder)..--
local function StrengthOf(player)
	local data = player:FindFirstChild("Data")
	local value = data and data:FindFirstChild("Strength")
	return value and tonumber(value.Value) or 0
end

local function PromptOf(holder)
	local host = RootPartOf(holder)
	return host and host:FindFirstChild("CollectPrompt")
end

--.. The grab moment: swap the field cucumber for the shoulder copy. Returns true on success.
local function Grab(player, holder, host, force, kg)
	if workspace:GetAttribute("CyclePhase") ~= "Day" then return false end
	local root = Alive(player)
	if not (root and holder.Parent and holder:IsDescendantOf(workspace) and host.Parent) then return false end
	if not force and (host.Position - root.Position).Magnitude > ReachFor(holder) then return false end
	if Carrying[player] then return false end
	holder:SetAttribute("CollectingBy", nil) -- never inherited by the carried / placed copy
	local model = BuildCarryModel(holder)
	if not model then return false end
	local meta = {
		Name = holder.Name,
		Zone = holder:GetAttribute("Zone") or "Spawn",
		TypeName = holder:GetAttribute("TypeName") or holder.Name,
		Golden = holder:GetAttribute("Golden") == true,
		Material = holder:GetAttribute("Material"),
		Mutations = holder:GetAttribute("Mutations"),
		SizeTier = holder:GetAttribute("SizeTier"), -- "HUGE" | "MASSIVE" | "COLOSSAL" | nil
		SizeScale = holder:GetAttribute("SizeScale"),
		Kg = kg or CucumberLift.Of(holder),
		ShownKg = CucumberLift.ShownOf(holder),
		Trait = holder:GetAttribute("CarryTrait") or "Normal",
		JourneyId = holder:GetAttribute("JourneyId"),
		Recorded = holder:GetAttribute("JourneyRecorded") == true and holder:GetAttribute("JourneyRecordedBy") == player.UserId,
		RecordedBy = holder:GetAttribute("JourneyRecordedBy"),
		RecoveryUsed = holder:GetAttribute("JourneyRecoveryUsed"),
		Rescues = holder:GetAttribute("RescueCount") or 0,
	}
	local position = host.Position
	if GiveCarry(player, model, meta) then
		holder:Destroy() -- this field slot stays empty until the next dawn
		FX(player, {Kind = "Pickup", Name = meta.Name, Position = position})
		return true
	end
	model:Destroy()
	return false
end

--.. Everyone but `except` (the lifter already animates itself)
local function BroadcastExcept(except, payload)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= except then LiftRemote:FireClient(other, payload) end
	end
end

local function Collect(player, holder, force)
	if workspace:GetAttribute("CyclePhase") ~= "Day" then
		FX(player, {Kind = "Refused", Reason = "The fields are closed until dawn!"})
		return
	end
	if Busy[player] then return end
	if not holder or not holder:IsDescendantOf(workspace) then return end
	local root, _, humanoid = Alive(player)
	if not root then return end
	local host = RootPartOf(holder)
	if not host then return end
	if not force and (host.Position - root.Position).Magnitude > ReachFor(holder) then
		--.. never a silent no-op: the prompt can be visible from further out than this
		FX(player, {Kind = "Refused", Reason = "Get closer"})
		return
	end
	if Carrying[player] then
		FX(player, {Kind = "Refused", Reason = "Your hands are full! Drop it or place it on your plot first."})
		return
	end
	if humanoid and (humanoid.SeatPart or humanoid.Sit) then
		FX(player, {Kind = "Refused", Reason = "Stand up first!"})
		return
	end
	if holder:GetAttribute("CollectingBy") then return end -- somebody is already at it
	if humanoid then pcall(humanoid.UnequipTools, humanoid) end -- the bat would swing on every click

	--.. the bar's numbers for THIS player (CucumberLift): 1 kg asks for 1 Strength
	local kg = CucumberLift.Of(holder)
	local ratio = CucumberLift.Ratio(StrengthOf(player), kg)
	local params = CucumberLift.Params(ratio)
	local prompt = PromptOf(holder)
	NextLiftToken += 1
	local attempt = {Token = NextLiftToken, Holder = holder, Host = host, Force = force, Kg = kg, Ratio = ratio, Params = params, StartedAt = os.clock()}
	PendingLift[player] = attempt
	Busy[player] = true
	holder:SetAttribute("CollectingBy", player.UserId)
	if prompt then prompt.Enabled = false end
	local function release()
		if PendingLift[player] == attempt then PendingLift[player] = nil Busy[player] = nil end
		if holder.Parent then
			holder:SetAttribute("CollectingBy", nil)
			if prompt and prompt.Parent then prompt.Enabled = true end
		end
	end

	--.. the client's verdict (or the server's own timeout): one outcome per attempt
	attempt.Finish = function(result, trusted)
		if attempt.Settled then return end
		attempt.Settled = true
		if result == "done" then
			local elapsed = os.clock() - attempt.StartedAt
			--.. believed when strength >= kg and the claim is not faster than MinClicks at MAX_CPS could be
			--.. (half the walk-up is allowed for latency: a 2-click lift lands ~0.7 s after the press)
			local plausible = trusted or (params.Feasible and elapsed >= CucumberLift.APPROACH * 0.5 + params.MinTime)
			if not plausible then
				--.. a cancel, not a fail: the lifter's client is already hoisting and only a Cancel makes it put the cucumber back
				warn(("[CucumberCarry] %s claimed a lift of %s (%s) after %.2f s with ratio %.3g -- refused"):format(player.Name, holder.Name, CucumberLift.Format(kg), elapsed, ratio))
				result = "cancel"
			end
		end
		if result == "done" then
			LiftRemote:FireAllClients({Kind = "Hoist", Player = player, Token = attempt.Token})
			task.delay(CucumberLift.HOIST_LEN, function()
				local ok, grabbed = pcall(Grab, player, holder, host, force, kg)
				if not ok then warn("[CucumberCarry] lift failed for " .. player.Name .. ": " .. tostring(grabbed)) end
				release()
				if not (ok and grabbed) then LiftRemote:FireAllClients({Kind = "Cancel", Player = player, Token = attempt.Token}) end
			end)
		elseif result == "fail" then
			release()
			LiftRemote:FireAllClients({Kind = "Fail", Player = player, Token = attempt.Token}) -- the lifter's own client shows "Too heavy"
		else
			release()
			LiftRemote:FireAllClients({Kind = "Cancel", Player = player, Token = attempt.Token})
		end
	end
	attempt.Cancel = function() attempt.Finish("cancel") end

	LiftRemote:FireAllClients({Kind = "Start", Player = player, Holder = holder, Token = attempt.Token, Name = holder.Name,
		Kg = CucumberLift.ShownOf(holder), Start = params.Start, Gain = params.Gain, Drift = params.Drift, Band = params.Band}) -- Kg = the SHOWN weight (the bar title); the requirement never leaves the server. Band = the bar's shout (CucumberLift.DIFFICULTY)
	--.. a bar that never answers (client died, left, hung) fails on its own
	task.delay(CucumberLift.APPROACH + CucumberLift.MAX_TIME + 2, function()
		if PendingLift[player] == attempt and not attempt.Settled then attempt.Finish("fail") end
	end)
end

LiftRemote.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then return end
	local attempt = PendingLift[player]
	if not attempt or attempt.Token ~= payload.Token then return end
	if payload.Kind == "Result" then
		local result = payload.Result
		if result ~= "done" and result ~= "fail" and result ~= "cancel" then result = "cancel" end
		attempt.Finish(result)
	elseif payload.Kind == "Progress" then
		local now = os.clock()
		if now - (LastRelay[player] or 0) < 1 / PROGRESS_RELAY_HZ then return end
		LastRelay[player] = now
		local p = tonumber(payload.P)
		if not p then return end
		BroadcastExcept(player, {Kind = "Progress", Player = player, Token = attempt.Token, P = math.clamp(p, 0, 1)})
	end
end)

local function AttachCollectPrompt(holder)
	--.. only cucumbers standing in a field folder (never a shoulder / plot copy)
	local container = workspace:FindFirstChild("Breakables")
	if not (container and holder:IsDescendantOf(container)) then return end
	local host = RootPartOf(holder)
	if not host or host:FindFirstChild("CollectPrompt") then return end
	--.. how heavy it is (read by CucumberPromptClient and CucumberLift.Of)
	local kg = CucumberLift.Of(holder)
	holder:SetAttribute("WeightKg", kg)
	holder:SetAttribute("ShownKg", CucumberLift.Shown(kg, holder:GetAttribute("Zone") or "Spawn", holder:GetAttribute("TypeName") or holder.Name)) -- what the prompt shows (never the requirement)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom -- drawn by CucumberPromptClient
	prompt.ObjectText = holder.Name -- e.g. "Golden NEON Cucumber": CucumberPromptClient colours the words
	prompt.ActionText = "Lift"
	--.. the prompt hangs at the model's CENTRE, so a giant (2026-09-08) puts its own prompt out
	--.. of reach -- 25 studs up on a COLOSSAL tree. Give the radius back in proportion.
	prompt.MaxActivationDistance = PROMPT_DISTANCE * math.max(tonumber(holder:GetAttribute("SizeScale")) or 1, 1)
	prompt.HoldDuration = PROMPT_HOLD
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	CollectionService:AddTag(prompt, "CucumberPrompt")
	prompt.Triggered:Connect(function(player)
		Collect(player, holder)
	end)
	prompt.Parent = host
end

--..Drop (shoulder -> field)..--
local function Drop(player)
	if workspace:GetAttribute("CyclePhase") ~= "Day" then
		FX(player, {Kind = "Refused", Reason = "The fields reopen at dawn. You can still place this on your plot."})
		return
	end
	local entry = Carrying[player]
	if not entry then return end
	local root, char = Alive(player)
	if not root then return end
	local zone, typeName, golden, name = entry.Zone, entry.TypeName, entry.Golden, entry.Name
	if not SpawnCarried then return end
	--.. inside ANY biome it lands right at your feet (user 2026-09-07); outside the biomes
	--.. (the lobby, off the map) it flies home to a fresh spot in its own field
	local inField = BiomeAt(root.Position) ~= nil
	local groundPos
	if inField then
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = {char, workspace:FindFirstChild("Breakables") or char}
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -30, 0), rp)
		groundPos = hit and hit.Position or (root.Position - Vector3.new(0, 3, 0))
	end
	local extra = Adventure.DropMetadata(entry)
	extra.Anywhere = inField
	--.. anywhere else: it flies home to a fresh random spot in the field it came from
	local holder = SpawnCarried:Invoke(zone, typeName, golden, groundPos, extra) -- keeps its material, mutations and size; Anywhere = the exact spot even outside its own field
	if not holder then
		FX(player, {Kind = "Refused", Reason = "That field is full. Keep this cucumber or place it on your plot."})
		return
	end
	if inField then Adventure.Bounce(holder) end
	ClearCarry(player)
	local landing = holder and RootPartOf(holder)
	if inField and holder then
		FX(player, {Kind = "Replant", Position = landing and landing.Position or groundPos, Zone = zone, Name = name})
	else
		FX(player, {Kind = "FlyHome", Position = landing and landing.Position or nil, Zone = zone, Name = name})
	end
end

--.. GuardianService (2026-09-17, user: "when a guardian hits you the cucumber falls to where you are
--.. instead of disappearing"): the load leaves the shoulder and lands at the player's feet as a real
--.. field cucumber again, wherever they are (Anywhere: outside its own field too), with the replant
--.. cue. Returns the new holder (nil when the field is full / closed - the player keeps it).
local function DropAtFeet(player)
	local entry = Carrying[player]
	if not entry or not SpawnCarried then return nil end
	local root, char = Alive(player)
	if not root then return nil end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {char, workspace:FindFirstChild("Breakables") or char, workspace:FindFirstChild("Guardians") or char}
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -30, 0), rp)
	local groundPos = hit and hit.Position or (root.Position - Vector3.new(0, 3, 0))
	local extra = Adventure.DropMetadata(entry)
	extra.Anywhere = true
	local holder = SpawnCarried:Invoke(entry.Zone, entry.TypeName, entry.Golden, groundPos, extra)
	if not holder then return nil end
	local name, zone = entry.Name, entry.Zone
	ClearCarry(player)
	local landing = RootPartOf(holder)
	FX(player, {Kind = "Replant", Position = landing and landing.Position or groundPos, Zone = zone, Name = name})
	return holder
end

--.. anything that takes the cucumber away mid-lift settles the bar first
local function CancelPending(player)
	local attempt = PendingLift[player]
	if attempt and not attempt.Settled then attempt.Cancel() end
	PendingLift[player] = nil
	Busy[player] = nil
end

-- Server-only night drop: detach before the lobby teleport, even after fields close.
local carryAPI = ServerStorage:FindFirstChild("CucumberCarryAPI") or Instance.new("Folder")
carryAPI.Name = "CucumberCarryAPI"
carryAPI.Parent = ServerStorage
local nightDrop = carryAPI:FindFirstChild("DropForNight") or Instance.new("BindableFunction")
nightDrop.Name = "DropForNight"
nightDrop.OnInvoke = function(player)
	CancelPending(player)
	local model = Take(player)
	LiftRemote:FireAllClients({Kind = "Cancel", Player = player, CancelAll = true})
	if not model then return false end
	model.Name = "NightDroppedCucumber"
	model.Parent = workspace
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored, part.CanCollide, part.CanTouch = false, true, false
			part.Massless = false
		end
	end
	local primary = model.PrimaryPart
	if primary then
		primary:SetNetworkOwner(nil)
		primary.AssemblyLinearVelocity = Vector3.new(0, -2, 0)
		primary.AssemblyAngularVelocity = Vector3.zero
	end
	-- The normal dawn spawn replaces field cucumbers; this detached night visual expires.
	game:GetService("Debris"):AddItem(model, math.max(1, (workspace:GetAttribute("PhaseEndsAt") or (workspace:GetServerTimeNow() + 5)) - workspace:GetServerTimeNow()))
	return true
end
nightDrop.Parent = carryAPI

-- GuardianService (2026-09-15): a guardian that catches you takes the cucumber off your
-- shoulder and carries it back to its seat. Same detach as the night drop, but the model
-- and its meta are handed to the caller instead of being dropped on the floor.
local takeCarried = carryAPI:FindFirstChild("TakeCarried") or Instance.new("BindableFunction")
takeCarried.Name = "TakeCarried"
takeCarried.OnInvoke = function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return nil end
	CancelPending(player)
	LiftRemote:FireAllClients({Kind = "Cancel", Player = player, CancelAll = true})
	local model, entry = Take(player)
	if not model then return nil end
	return model, entry
end
takeCarried.Parent = carryAPI

--.. the guardian's catch since 2026-09-17: the cucumber drops where the player stands
local dropAtFeet = carryAPI:FindFirstChild("DropAtFeet") or Instance.new("BindableFunction")
dropAtFeet.Name = "DropAtFeet"
dropAtFeet.OnInvoke = function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return nil end
	CancelPending(player)
	LiftRemote:FireAllClients({Kind = "Cancel", Player = player, CancelAll = true})
	local ok, holder = pcall(DropAtFeet, player)
	if not ok then warn("[CucumberCarry] DropAtFeet failed for " .. player.Name .. ": " .. tostring(holder)) return nil end
	return holder
end
dropAtFeet.Parent = carryAPI

--..Plot placement (EggPlacement's rules, for the carried cucumber)..--
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

local function Footprint(size, yaw)
	local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
	return c * size.X + s * size.Z, s * size.X + c * size.Z
end

local PickUp -- defined below (Studio hook only: placed cucumbers show no prompt)

local function Place(player, cframe)
	local entry = Carrying[player]
	if not entry or not (entry.Model and entry.Model.Parent) then return false, "not carrying" end
	MarkLobby(player, entry, Alive(player))
	if typeof(cframe) ~= "CFrame" then return false, "bad cframe" end
	local now = os.clock()
	if LastPlace[player] and now - LastPlace[player] < PLACE_COOLDOWN then return false, "cooldown" end
	local plot = PlotOf(player)
	if not plot then return false, "no plot" end
	local root = Alive(player)
	if not root then return false, "no character" end
	--.. must be standing at the base
	local rp = plot.CFrame:PointToObjectSpace(root.Position)
	if math.abs(rp.X) > plot.Size.X * 0.5 + AT_BASE_MARGIN or math.abs(rp.Z) > plot.Size.Z * 0.5 + AT_BASE_MARGIN then
		return false, "not at base"
	end
	local model = entry.Model
	local size = model:GetAttribute("RestSize")
	local restRot = model:GetAttribute("RestRotation")
	if typeof(size) ~= "Vector3" or typeof(restRot) ~= "CFrame" then return false, "no rest pose" end
	local lift = tonumber(model:GetAttribute("RestLift")) or size.Y * 0.5

	--.. rebuild the placement from the client's X/Z + yaw only, on the plot surface
	local relative = plot.CFrame:ToObjectSpace(cframe)
	local _, yaw = relative:ToEulerAnglesYXZ()
	local box = CucumberFootprint.Box(size) -- 2026-09-13: wide cucumbers collide with a smaller box than their canopy
	local fx, fz = Footprint(box, yaw)
	local x, z = relative.Position.X, relative.Position.Z
	if math.abs(x) + fx * 0.5 > plot.Size.X * 0.5 + BOUNDS_EPSILON or math.abs(z) + fz * 0.5 > plot.Size.Z * 0.5 + BOUNDS_EPSILON then
		return false, "outside plot"
	end
	local top = plot.Size.Y * 0.5
	local boxCF = plot.CFrame * CFrame.new(x, top + size.Y * 0.5, z) * CFrame.Angles(0, yaw, 0)

	--.. occupied?
	local holder = HolderOf(plot)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {holder}
	if #workspace:GetPartBoundsInBox(boxCF, box, params) > 0 then
		return false, "occupied"
	end

	LastPlace[player] = now
	local taken, meta = Take(player)
	if not taken then return false, "not carrying" end
	--.. grow the armful back to the size it stood at in the field (2026-09-08): RestSize /
	--.. RestLift / the footprint above are already measured at that scale
	local placeScale = tonumber(taken:GetAttribute("PlaceScale")) or 1
	if placeScale ~= 1 then
		taken:ScaleTo(taken:GetScale() * placeScale)
		ScaleLooks(taken, placeScale)
	end
	--.. natural resting pose, standing on the plot surface
	taken:PivotTo(plot.CFrame * CFrame.new(x, top + lift, z) * CFrame.Angles(0, yaw, 0) * restRot)
	for _, d in ipairs(taken:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanQuery = false
		end
	end
	--.. invisible footprint box: the overlap test finds placed objects through it
	local hitbox = Instance.new("Part")
	hitbox.Name = "PlotHitbox"
	hitbox.Size = box -- the collision footprint, not the whole canopy (2026-09-13)
	hitbox.CFrame = boxCF
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Parent = taken
	taken.Name = meta.Name
	taken:SetAttribute("Owner", player.UserId)
	taken:SetAttribute("CucumberName", meta.Name)
	taken:SetAttribute("Zone", meta.Zone)
	taken:SetAttribute("TypeName", meta.TypeName)
	taken:SetAttribute("Golden", meta.Golden == true)
	taken:SetAttribute("Material", meta.Material)
	taken:SetAttribute("Mutations", meta.Mutations or "")
	taken:SetAttribute("SizeTier", meta.SizeTier) -- a giant stays a giant on the plot (value + card)
	taken:SetAttribute("SizeScale", meta.SizeScale)
	taken:SetAttribute("WeightKg", meta.Kg)
	taken:SetAttribute("ShownKg", meta.ShownKg)
	taken:SetAttribute("CucumberId", HttpService:GenerateGUID(false)) -- 2026-09-22: stable id (pet buffs / saves)
	CollectionService:AddTag(taken, "PlacedCucumber") -- attributes first: LeaderstatsService stamps Rate off this
	taken.Parent = holder
	FX(player, {Kind = "Placed", Name = meta.Name, Position = boxCF.Position})
	return true
end

--..Restore (profile -> plot): BaseSaveService stands a saved cucumber back up without the shoulder trip
--..(2026-09-12). A field cucumber of the saved kind is spawned (SpawnCarried with Force: even while the
--..fields are closed for the night or the biome is full), cloned into the self-contained model Grab()
--..makes (BuildCarryModel: rest pose, PlaceScale), the field one is destroyed at once, and the copy is
--..stood at the saved pivot with the saved footprint box - exactly where and how it stood before..--
local function RestorePlaced(player, plot, record, pivot, boxCF, boxSize)
	if not (SpawnCarried and plot and plot.Parent and type(record) == "table") then return nil, "no spawner" end
	if typeof(pivot) ~= "CFrame" or typeof(boxCF) ~= "CFrame" or typeof(boxSize) ~= "Vector3" then return nil, "bad record" end
	local holder = SpawnCarried:Invoke(record.Zone or "Spawn", record.Type, record.Golden == true, pivot.Position,
		{Anywhere = true, Force = true, Material = record.Material, Mutations = record.Mutations, SizeTier = record.SizeTier})
	if not holder then return nil, "spawn failed (" .. tostring(record.Zone) .. " / " .. tostring(record.Type) .. ")" end
	local meta = {
		Name = holder.Name, Zone = holder:GetAttribute("Zone") or "Spawn", TypeName = holder:GetAttribute("TypeName") or holder.Name,
		Golden = holder:GetAttribute("Golden") == true, Material = holder:GetAttribute("Material"), Mutations = holder:GetAttribute("Mutations"),
		SizeTier = holder:GetAttribute("SizeTier"), SizeScale = holder:GetAttribute("SizeScale"), Kg = CucumberLift.Of(holder),
	}
	meta.ShownKg = CucumberLift.Shown(meta.Kg, meta.Zone, meta.TypeName)
	holder:SetAttribute("CollectingBy", nil)
	local model = BuildCarryModel(holder)
	holder:Destroy()
	if not model then return nil, "no model" end
	local placeScale = tonumber(model:GetAttribute("PlaceScale")) or 1
	if placeScale ~= 1 then
		model:ScaleTo(model:GetScale() * placeScale)
		ScaleLooks(model, placeScale)
	end
	local restSize = model:GetAttribute("RestSize")
	--.. MIGRATED (2026-09-18): the spawner handed back a different type than the one saved (an old
	--.. generic Toyland / Neon cucumber -> its hand-modelled replacement, CucumberSpawner LEGACY_TYPES).
	--.. The saved pivot is the OLD model's centre height, so stand the new one up the way Place() does:
	--.. same spot and yaw as the saved footprint box, resting on the plot surface, kept inside the plot
	local migrated = meta.TypeName ~= record.Type
	local restRot = model:GetAttribute("RestRotation")
	if migrated and typeof(restSize) == "Vector3" and typeof(restRot) == "CFrame" then
		local lift = tonumber(model:GetAttribute("RestLift")) or restSize.Y * 0.5
		local relative = plot.CFrame:ToObjectSpace(boxCF)
		local _, yaw = relative:ToEulerAnglesYXZ()
		local fx, fz = Footprint(CucumberFootprint.Box(restSize), yaw)
		local hx, hz = math.max(0, plot.Size.X * 0.5 - fx * 0.5), math.max(0, plot.Size.Z * 0.5 - fz * 0.5)
		local x = math.clamp(relative.Position.X, -hx, hx)
		local z = math.clamp(relative.Position.Z, -hz, hz)
		local top = plot.Size.Y * 0.5
		pivot = plot.CFrame * CFrame.new(x, top + lift, z) * CFrame.Angles(0, yaw, 0) * restRot
		boxCF = plot.CFrame * CFrame.new(x, top + restSize.Y * 0.5, z) * CFrame.Angles(0, yaw, 0)
	end
	model:PivotTo(pivot)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanQuery = false
		end
	end
	local hitbox = Instance.new("Part")
	hitbox.Name = "PlotHitbox"
	hitbox.Size = typeof(restSize) == "Vector3" and CucumberFootprint.Box(restSize) or boxSize -- the footprint rule, not the saved (older, full) box
	hitbox.CFrame = boxCF
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Parent = model
	--.. a migrated cucumber takes its new display name ("Golden Cucumber" -> "Golden Lego Cucumber")
	local name = (not migrated and record.Name) or meta.Name
	model.Name = name
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("CucumberName", name)
	model:SetAttribute("Zone", meta.Zone)
	model:SetAttribute("TypeName", meta.TypeName)
	model:SetAttribute("Golden", meta.Golden)
	model:SetAttribute("Material", meta.Material)
	model:SetAttribute("Mutations", meta.Mutations or "")
	model:SetAttribute("SizeTier", meta.SizeTier)
	model:SetAttribute("SizeScale", meta.SizeScale)
	model:SetAttribute("WeightKg", meta.Kg)
	model:SetAttribute("ShownKg", meta.ShownKg)
	local id = record.Id -- 2026-09-22: the saved stable id (never written back here: BaseSave / the migration own record repair)
	model:SetAttribute("CucumberId", (type(id) == "string" and #id >= 1 and #id <= 64) and id or HttpService:GenerateGUID(false))
	local buffs = PetBuffs()
	if buffs then pcall(buffs.StampFromRecord, model, record.PetBuffs) end -- 2026-09-22: unexpired pet buffs, before the tag
	CollectionService:AddTag(model, "PlacedCucumber")
	model.Parent = HolderOf(plot)
	return model
end

local function ClearPlaced(plot)
	local holder = plot and plot:FindFirstChild("Placed")
	if not holder then return 0 end
	local n = 0
	for _, model in ipairs(holder:GetChildren()) do
		if CollectionService:HasTag(model, "PlacedCucumber") then
			CollectionService:RemoveTag(model, "PlacedCucumber")
			model:Destroy()
			n += 1
		end
	end
	return n
end

do
	local restore = carryAPI:FindFirstChild("RestorePlaced") or Instance.new("BindableFunction")
	restore.Name = "RestorePlaced"
	restore.OnInvoke = RestorePlaced
	restore.Parent = carryAPI
	local clear = carryAPI:FindFirstChild("ClearPlaced") or Instance.new("BindableFunction")
	clear.Name = "ClearPlaced"
	clear.OnInvoke = ClearPlaced
	clear.Parent = carryAPI
end

--..Pick up (plot -> shoulder) -- reachable only through the Studio dev hook..--
PickUp = function(player, placed, force)
	if Busy[player] then return end
	if not placed or not placed:IsDescendantOf(workspace) then return end
	if placed:GetAttribute("Owner") ~= player.UserId then
		FX(player, {Kind = "Refused", Reason = "That's not your cucumber!"})
		return
	end
	local root = Alive(player)
	if not root then return end
	local pivot = placed:GetPivot().Position
	if not force and (pivot - root.Position).Magnitude > ReachFor(placed) then return end
	if Carrying[player] then
		FX(player, {Kind = "Refused", Reason = "Your hands are full! Drop it or place it on your plot first."})
		return
	end
	Busy[player] = true
	local ok, err = pcall(function()
		local hb = placed:FindFirstChild("PlotHitbox")
		if hb then hb:Destroy() end
		--.. it stands at FIELD scale on the plot: shrink it back to an armful for the shoulder
		local placeScale = tonumber(placed:GetAttribute("PlaceScale")) or 1
		if placeScale ~= 1 then
			placed:ScaleTo(placed:GetScale() / placeScale)
			ScaleLooks(placed, 1 / placeScale)
		end
		local meta = {
			Recorded = true,
			Trait = placed:GetAttribute("CarryTrait"),
			Name = placed:GetAttribute("CucumberName") or placed.Name,
			Zone = placed:GetAttribute("Zone") or "Spawn",
			TypeName = placed:GetAttribute("TypeName") or placed.Name,
			Golden = placed:GetAttribute("Golden") == true,
			Material = placed:GetAttribute("Material"),
			Mutations = placed:GetAttribute("Mutations"),
			SizeTier = placed:GetAttribute("SizeTier"),
			SizeScale = placed:GetAttribute("SizeScale"),
			Kg = placed:GetAttribute("WeightKg") or CucumberLift.Of(placed),
			ShownKg = CucumberLift.ShownOf(placed),
		}
		local buffs = PetBuffs()
		if buffs then pcall(buffs.ClearCucumber, placed, "PickUp") end -- 2026-09-22: a pickup ends its pet buffs (settled while still tagged)
		placed:SetAttribute("CucumberId", nil) -- 2026-09-22: placing it again mints a fresh id
		CollectionService:RemoveTag(placed, "PlacedCucumber")
		placed:SetAttribute("Owner", nil)
		placed:SetAttribute("CucumberName", nil)
		placed.Parent = nil
		if GiveCarry(player, placed, meta) then
			FX(player, {Kind = "Pickup", Name = meta.Name, Position = pivot})
		else
			placed:Destroy()
		end
	end)
	Busy[player] = nil
	if not ok then warn("[CucumberCarry] pick up failed for " .. player.Name .. ": " .. tostring(err)) end
end

--..Wiring..--
for _, holder in ipairs(CollectionService:GetTagged("Breakable")) do
	AttachCollectPrompt(holder)
end
CollectionService:GetInstanceAddedSignal("Breakable"):Connect(function(holder)
	task.defer(AttachCollectPrompt, holder)
end)
--.. belt and braces: the tag is stamped before the holder is parented, so also
--.. watch the container itself
task.spawn(function()
	local container = workspace:WaitForChild("Breakables", 60)
	if not container then return end
	container.DescendantAdded:Connect(function(d)
		if CollectionService:HasTag(d, "Breakable") then task.defer(AttachCollectPrompt, d) end
	end)
end)

--.. Lobby watch: a carry that reaches the lobby is secured (CucumberCarrySafe) and the owner
--.. gets the arrival cue once per entry from outside.
task.spawn(function()
	local lobby = workspace.Map:FindFirstChild("Lobby")
	local deadline = os.clock() + 5
	while lobby and not lobby:GetAttribute("LayoutReady") and os.clock() < deadline do
		task.wait(0.1)
	end
	LobbyBox = ComputeLobbyBox()
	if LobbyBox then
		print(("[CucumberCarry] lobby box X %.1f..%.1f Z %.1f..%.1f"):format(LobbyBox.MinX, LobbyBox.MaxX, LobbyBox.MinZ, LobbyBox.MaxZ))
	else
		warn("[CucumberCarry] lobby box unknown: carries are never marked safe")
	end
	while true do
		task.wait(0.1)
		for player, entry in pairs(Carrying) do
			local root = Alive(player)
			if root then
				if InLobby(root.Position) then
					MarkLobby(player, entry, root)
				elseif entry.InLobby then
					entry.InLobby = false
					player:SetAttribute("CucumberCarrySafe", false)
				end
			end
		end
	end
end)

DropRemote.OnServerEvent:Connect(function(player)
	local ok, err = pcall(Drop, player)
	if not ok then warn("[CucumberCarry] drop failed for " .. player.Name .. ": " .. tostring(err)) end
end)

PlaceRemote.OnServerInvoke = function(player, cframe)
	local ok, result, reason = pcall(Place, player, cframe)
	if not ok then
		warn("[CucumberCarry] " .. tostring(result))
		return false
	end
	return result == true, reason
end

Players.PlayerRemoving:Connect(function(player)
	CancelPending(player)
	Carrying[player] = nil
	Busy[player] = nil
	LastPlace[player] = nil
	LastRelay[player] = nil
end)

--..Studio dev hook..--
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("CarryDev"):Connect(function()
		local cmd = workspace:GetAttribute("CarryDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		workspace:SetAttribute("CarryDev", nil)
		local action, name = cmd:match("^(%a+):(.+)$")
		local player = name and Players:FindFirstChild(name)
		if not (action and player) then return end
		local root = Alive(player)
		if action == "collect" and root then
			local best, bestD
			local container = workspace:FindFirstChild("Breakables")
			for _, d in ipairs(container and container:GetDescendants() or {}) do
				if CollectionService:HasTag(d, "Breakable") then
					local host = RootPartOf(d)
					local dist = host and (host.Position - root.Position).Magnitude
					if dist and (not bestD or dist < bestD) then best, bestD = d, dist end
				end
			end
			if best then Collect(player, best, true) end
		elseif action == "win" or action == "lose" then
			local attempt = PendingLift[player]
			if attempt and not attempt.Settled then
				attempt.Finish(action == "win" and "done" or "fail", true)
			else
				warn("[CucumberCarry] no lift running for " .. player.Name)
			end
		elseif action == "drop" then
			Drop(player)
		elseif action == "pickup" then
			for _, placed in ipairs(CollectionService:GetTagged("PlacedCucumber")) do
				if placed:GetAttribute("Owner") == player.UserId then PickUp(player, placed, true) break end
			end
		end
	end)
end

print("[CucumberCarry] lift prompts (click-to-lift bar), shoulder carry, drop and plot placement ready")
