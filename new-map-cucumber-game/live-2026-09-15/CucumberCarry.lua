--[[
	CucumberCarry  (Script, ServerScriptService)
	Proximity-prompt pickup, shoulder carry and plot placement for the cucumbers
	CucumberSpawner spawns. Port of the Zombie Cucumber Game's CarryService (armful
	model welded to the LEFT SHOULDER + an IKControl steadying hand) wired to this
	place's conventions (ReplicatedStorage.Remotes, EggPlacement's plot rules).

	  * every spawned cucumber (CollectionService tag "Breakable") gets a "Collect"
	    ProximityPrompt on its root part
	  * Collect is validated server-side (alive, within REACH, hands free): the field
	    cucumber is cloned into a welded armful-sized model on the shoulder, the field
	    copy is destroyed (the spawner refills the biome) and the player gets the
	    attributes CarryingCucumber (display name) / CarryingCucumberZone /
	    CarryingCucumberGolden. CarryClient draws the billboard + DROP button.
	  * STRENGTH GATE + CHOREOGRAPHY (2026-09-06): every field cucumber gets a
	    StrengthRequired attribute (ReplicatedStorage.Modules.CucumberStrength; the
	    numbers are placeholders). A Collect compares it with player.Data.Strength:
	    CucumberStrength.BANDS decide the band (easy / sturdy / shaky / hopeless: pull
	    time, walk speed, how long it stays up). The server schedules
	    it through Remotes.CollectAnim (CollectAnimClient walks up, animates, rocks the
	    cucumber) and only swaps the field cucumber for the shoulder copy at the grab
	    moment (APPROACH + struggle + GRAB_T), re-checking reach / life / hands.
	  * HEAVY CARRY + STUMBLE (2026-09-06): the requirement is HIDDEN (no numbers on
	    screen). Every band below "easy" is a heavy carry: player attributes
	    CarryingCucumberHeavy / CarryingCucumberSpeed (CollectAnimClient slows the walk
	    to the band's multiplier) / CarryingCucumberBand (CarryClient hint), and
	    CucumberStrength.FallDelay(ratio) seconds later (the band's hold)
	    Stumble() drops the load where it slipped as a real field cucumber again
	    (SpawnCarried at that point; {Kind = "FallDrop"} lets the clients tumble it
	    there) and THEN plays the CucumberFall clip for everyone ({Kind = "Fall"}: the
	    client trips FALL_AFTER_DROP later; no fling -- user 2026-09-07) -- collect it
	    again, stumble again, until it reaches the plot. Easy pick-ups never stumble.
	  * DROP / SLIP RULE (2026-09-07, user): inside ANY biome (Map.Biomes floor slabs,
	    BiomeAt) a dropped or slipped cucumber lands on the spot you are on, whatever
	    field it came from; outside the biomes (the lobby, off the map) it flies home
	    to a fresh spot in its own field (SpawnCarried with no point, FlyHome / Stumble
	    {Home = true} cues).
	  * LOBBY = SAFE (2026-09-06; every band since 2026-09-07, user: "once the player
	    is past the biomes and in the lobby don't let cucumbers slip and fall"): once a
	    carrier's root is inside the lobby box (inner faces of Map.Borders."Lobby
	    Border" walls, read at start) the carry settles for good: Heavy / Weak / Speed
	    are cleared (full speed, no more stumbles, placeable) and, on the way in, the
	    owner gets CarryFX {Kind = "LobbyReached", WasHeavy} (camera bounce + sound).
	  * WEAK LIFT (2026-09-07, user: "you can pick up any cucumber, but without the
	    strength you pretty much just fall right after pulling and picking it up"):
	    below the requirement (ratio < FLOOR_RATIO) the lift still happens
	    (CucumberStrength.WEAK_CAN_LIFT): the "shaky" band walks some steps, the
	    "hopeless" band slips as it stands up. Player attribute CarryingCucumberWeak
	    (hopeless only: the billboard hint + the Stumble cue flag), Place refuses a
	    below-requirement carry until the lobby settles it. The old "fail" tug survives
	    for WEAK_CAN_LIFT = false.
	  * Remotes.DropCucumber: inside any biome it is re-planted at your feet, outside
	    the biomes it flies home to a fresh spot in its own field
	    (CucumberSpawnerAPI.SpawnCarried, so it is a real spawned cucumber again)
	  * Remotes.requestCucumberPlacement(cframe) -> true/false, reason: EggPlacement's
	    contract -- only the client's X/Z + yaw are trusted, you must stand at YOUR
	    plot, the footprint must stay inside it and must not overlap plot.Placed. The
	    carried model is anchored onto the plot in its natural resting pose
	    (attributes Owner / CucumberName / Zone / TypeName / Golden, tag
	    "PlacedCucumber") and shows NO prompt (user call 2026-09-05). Like eggs,
	    placements are NOT saved. PickUp() survives for the Studio hook only.
	  * FULL-SIZE ON THE PLOT (2026-09-08, user: "make cucumbers placed in the users
	    base up to scale, like make it same size that it would be in the wild"): the
	    shoulder copy is still shrunk to an armful, but BuildCarryModel records the
	    rest pose at FIELD scale and a PlaceScale factor, and Place() grows the model
	    back by it -- so a tree stands on the plot as tall as it stood in its biome,
	    and a giant (attributes SizeTier / SizeScale from CucumberMutations.SIZES)
	    stands there at 2x / 3x / 4x that. Giants also ride a little bigger on the
	    shoulder (CARRY_GIANT_BONUS) and keep their size through drops and slips.
	  * prompts use Style = Custom: CucumberPromptClient draws the key badge +
	    "Cucumber" / "Collect" look; the default Roblox panel never shows
	  * Remotes.CarryFX (server -> client): {Kind = Pickup | Replant | FlyHome |
	    Placed | Refused, ...} cues for CarryClient
	  * Studio dev hook: workspace:SetAttribute("CarryDev", "collect:<Name>" |
	    "drop:<Name>" | "pickup:<Name>" | "stumble:<Name>") drives the flow without a
	    prompt press ("stumble" forces the heavy-carry fall right now)
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--..Config..--
local CARRY_LONGEST_AXIS = 2.8 -- studs: an armful, whatever the field model's size
--.. a giant (CucumberMutations.SIZES) rides this much bigger per extra size step, so you can see
--.. what you are hauling without it eating the screen: x2 -> 3.8, x3 -> 4.8, x4 -> 5.7 studs
local CARRY_GIANT_BONUS = 0.35
local PROMPT_DISTANCE = 10
local PROMPT_HOLD = 0
local REACH = 16 -- server-side distance check for a Collect / Pick up trigger
local PLACE_COOLDOWN = 0.2
local COLLISION_SHRINK = 0.96 -- keep in step with EggPlacement / CucumberPlacementClient
local BOUNDS_EPSILON = 0.05
local AT_BASE_MARGIN = 6 -- keep in step with CucumberPlacementClient
--.. rest it ON the left shoulder like a carried log: leaned into the neck, nose up a touch
local SHOULDER_OFFSET = CFrame.new(-1.05, 1.05, 0.05) * CFrame.Angles(math.rad(-10), 0, math.rad(8))
local FallRandom = Random.new() -- jitter for CucumberStrength.FallDelay
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
local SteadyRemote = remote("RemoteEvent", "SteadyCucumber")
local ModeRemote = remote("RemoteEvent", "CucumberCarryMode")
local Adventure = require(ServerStorage:WaitForChild("CucumberAdventure"))
local CancelPickupRemote = remote("RemoteEvent", "CancelCucumberPickup")
local AnimRemote = remote("RemoteEvent", "CollectAnim") -- server -> all clients: collect choreography (CollectAnimClient)
local CucumberStrength = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CucumberStrength"))
local CucumberFootprint = require(ReplicatedStorage.Modules:WaitForChild("CucumberFootprint")) -- 2026-09-13: the (smaller) collision box of a placed cucumber

local API = ServerStorage:WaitForChild("CucumberSpawnerAPI", 30)
local SpawnCarried = API and API:WaitForChild("SpawnCarried", 10)
local InField = API and API:WaitForChild("InField", 10)
if not (SpawnCarried and InField) then
	warn("[CucumberCarry] CucumberSpawner API missing; drops will discard cucumbers")
end

--..State..--
local Carrying = {} -- [player] = {Model, Name, Zone, TypeName, Golden, Material, Mutations, PoseIK, Heavy, Weak, Ratio, Falling, FallAt, InLobby, AncestryConn}
local Busy = {} -- [player] = true during a collect / pick up
local PendingCollect = {}
local NextCollectToken = 0
local LastPlace = {} -- [player] = os.clock()

--..Helpers..--
local function FX(player, payload)
	if player.Parent == Players then FXRemote:FireClient(player, payload) end
end

local function RootPartOf(holder)
	if holder:IsA("BasePart") then return holder end
	return holder.PrimaryPart or holder:FindFirstChildWhichIsA("BasePart", true)
end

--.. How close you must be to collect this one. The check measures to the model's CENTRE, so a
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
--..CucumberSpawner.SlabIndexAt). Used by the drop / slip rule.
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
	if not entry or not entry.Heavy then
		for _, key in ipairs({"CucumberGripStart", "CucumberGripEnd", "CucumberGripDuration", "CucumberRecoveryUsed", "CucumberCarryMode"}) do player:SetAttribute(key, nil) end
	end
	player:SetAttribute("CarryingCucumber", entry and entry.Name or nil)
	player:SetAttribute("CarryingCucumberZone", entry and entry.Zone or nil)
	player:SetAttribute("CarryingCucumberGolden", entry and entry.Golden or nil)
	player:SetAttribute("CarryingCucumberMaterial", entry and entry.Material or nil)
	player:SetAttribute("CarryingCucumberMutations", entry and entry.Mutations or nil)
	player:SetAttribute("CarryingCucumberTrait", entry and entry.Trait or nil)
	player:SetAttribute("CucumberCarrySafe", entry and entry.InLobby or nil)
	player:SetAttribute("CarryingCucumberSize", entry and entry.SizeTier or nil) -- "HUGE" | "MASSIVE" | "COLOSSAL" | nil
	player:SetAttribute("CarryingCucumberHeavy", (entry and entry.Heavy) and true or nil) -- a slip is coming (any band below easy, until the lobby settles it)
	player:SetAttribute("CarryingCucumberWeak", (entry and entry.Weak) and true or nil) -- hopeless band: slips as you stand up (CarryClient hint / toast)
	local speed = entry and entry.Heavy and tonumber(entry.Speed) or nil
	player:SetAttribute("CarryingCucumberSpeed", (speed and speed ~= 1) and speed or nil) -- CollectAnimClient: WalkSpeed multiplier while carrying
	player:SetAttribute("CarryingCucumberBand", (entry and entry.Heavy) and entry.Band or nil) -- CarryClient hint (CucumberStrength.BANDS name)
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

	local entry = {Model = model, Name = meta.Name, Zone = meta.Zone, TypeName = meta.TypeName, Golden = meta.Golden == true, Material = meta.Material, Mutations = meta.Mutations, SizeTier = meta.SizeTier, SizeScale = meta.SizeScale, Heavy = meta.Heavy == true, Weak = meta.Weak == true, Speed = meta.Speed, Band = meta.Band, Ratio = meta.Ratio}
 entry.BaseSpeed=meta.Speed or 1
 entry.Trait=meta.Trait or "Normal"
 entry.Required=meta.Required or 0
 entry.OriginalBand=meta.Band
 entry.JourneyId,entry.Recorded=meta.JourneyId,meta.Recorded==true
 entry.RecordedBy=meta.RecordedBy
 entry.RecoveryUsed,entry.Rescues=meta.RecoveryUsed==true,meta.Rescues or 0
 entry.RescuePickup,entry.Standout=meta.RescuePickup,meta.Standout
 Adventure.ApplyCosmetic(player,model)
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

-- Settle synchronously: a delayed slip must not beat the 0.1-second lobby watcher.
local function SettleInLobby(player, entry, root)
	if Carrying[player] ~= entry or not root or not InLobby(root.Position) then return false end
	local wasHeavy = entry.Heavy == true
	entry.Heavy, entry.Weak, entry.Speed, entry.Band, entry.FallAt = false, false, 1, "settled", nil
	if wasHeavy then SetCarryAttributes(player, entry) end
	if not entry.InLobby then
		entry.InLobby = true
		player:SetAttribute("CucumberCarrySafe",true)
		Adventure.Secured(player,entry)
		FX(player, {Kind = "LobbyReached", Name = entry.Name, WasHeavy = wasHeavy})
	end
	return true
end

--..Stumble (heavy / weak carry: the load gets dropped in front of you)..--
local ScheduleStumble

local function RetryDelay(entry)
	return CucumberStrength.RetryFor(entry.Ratio)
end

--.. Drop the load where it slipped (it becomes a field cucumber again right there, or
--.. flies home from outside the biomes), THEN play the fall for everyone: the client
--.. trips FALL_AFTER_DROP later; stay busy until the clip ends. Returns false when it
--.. cannot happen right now (busy, seated, fields closed, field full).
local function Stumble(player, entry)
	if Carrying[player] ~= entry or entry.Falling then return false end
	local root, char, humanoid = Alive(player)
	if not (root and humanoid) then return false end
	if SettleInLobby(player, entry, root) then return false end
	if Busy[player] or humanoid.SeatPart or humanoid.Sit or not SpawnCarried then return false end
	if workspace:GetAttribute("CyclePhase") ~= "Day" then return false end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.zAxis
	--.. the load lands just ahead of the player -- inside a biome. Outside the biomes it flies home.
	local ahead = root.Position + flat * CucumberStrength.FALL_LAND_AHEAD
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {char, workspace:FindFirstChild("Breakables") or char}
	local hit = workspace:Raycast(ahead + Vector3.new(0, 2, 0), Vector3.new(0, -30, 0), rp)
	local landing = hit and hit.Position or (ahead - Vector3.new(0, humanoid.HipHeight + root.Size.Y * 0.5, 0))
	local onTheSpot = BiomeAt(landing) ~= nil
	--.. the load leaves the shoulder first: re-spawn it now (nil = that field is full or
	--.. closed: keep hold of it, the caller retries later)
	local from = (entry.Model and entry.Model.Parent) and entry.Model:GetPivot().Position or root.Position
	local extra=Adventure.DropMetadata(entry) extra.Anywhere=onTheSpot
	local holder = SpawnCarried:Invoke(entry.Zone, entry.TypeName, entry.Golden, onTheSpot and landing or nil, extra)
	if not holder then return false end
	-- SpawnCarried may yield. Revalidate ownership and lobby safety before removing the shoulder copy.
	local currentRoot = Alive(player)
	if Carrying[player] ~= entry or SettleInLobby(player, entry, currentRoot) then
		holder:Destroy()
		return false
	end
	if onTheSpot then Adventure.Rescue(holder,player,entry) Adventure.Bounce(holder,CucumberStrength.FALL_FLIGHT) end
	entry.Falling = true
	Busy[player] = true
	local name, weak, zone = entry.Name, entry.Weak == true, entry.Zone
	local model = Take(player)
	if model then model:Destroy() end
	--.. everyone: the trip (FALL_AFTER_DROP later on the client) and the tumble
	AnimRemote:FireAllClients({Kind = "Fall", Player = player, Landing = onTheSpot and landing or nil, Home = not onTheSpot})
	if onTheSpot then
		AnimRemote:FireAllClients({Kind = "FallDrop", Player = player, Holder = holder, From = from})
		FX(player, {Kind = "Stumble", Name = name, Position = landing, Weak = weak})
	else
		--.. outside the biomes: it flew home (comet + toast on the owner's client only)
		local rest = RootPartOf(holder)
		FX(player, {Kind = "Stumble", Name = name, Weak = weak, Home = true, Zone = zone, Position = rest and rest.Position or nil})
	end
	task.delay(CucumberStrength.FALL_AFTER_DROP + CucumberStrength.FALL_LENGTH - CucumberStrength.FALL_CLIP_START, function()
		Busy[player] = nil
	end)
	return true
end

--.. A heavy carry slips CucumberStrength.FallDelay(ratio) seconds after the grab (the rest
--.. of the pick-up + the band's hold, CucumberStrength.BANDS) -- or `delay` seconds -- unless
--.. the load was placed / dropped / settled by the lobby meanwhile.
-- Server grip budget. Mode changes alter its drain rate, never refill it.
local function PublishGrip(player, entry, now, rate)
 local duration = entry.GripDuration
 local remaining = math.max(0,entry.GripRemaining or duration)
 local grace = math.max(0,(entry.GripGraceUntil or 0)-now)
 entry.GripEnd = now + grace + remaining / rate
 player:SetAttribute("CucumberGripEnd",entry.GripEnd)
 player:SetAttribute("CucumberGripDuration",duration / rate)
 player:SetAttribute("CucumberRecoveryUsed",entry.RecoveryUsed==true)
 player:SetAttribute("CucumberCarryMode",entry.Mode or "Normal")
end

ScheduleStumble = function(player, entry, delay)
 if Carrying[player]~=entry or not entry.Heavy then return end
 local hold=entry.GripDuration or CucumberStrength.HoldFor(entry.Ratio)
 if not hold then return end
 if not entry.GripDuration and entry.Trait=="Slippery" then hold*=.8 end
 entry.GripDuration=hold
 local now=workspace:GetServerTimeNow()
 if not entry.GripClockStarted then
  entry.GripClockStarted=true
  entry.GripRemaining=hold
  entry.GripGraceUntil=now+(entry.RescuePickup and 0 or (CucumberStrength.PICKUP_LENGTH-CucumberStrength.GRAB_T))
  entry.GripUpdatedAt=now
  entry.Mode="Normal"
  player:SetAttribute("CucumberGripStart",entry.GripGraceUntil)
 elseif delay then
  entry.GripRemaining=delay
 end
 PublishGrip(player,entry,now,entry.DrainRate or 1)
end

local function DrainGrip(entry, now)
 local last=math.max(entry.GripUpdatedAt or now,entry.GripGraceUntil or 0)
 entry.GripRemaining=math.max(0,(entry.GripRemaining or 0)-math.max(0,now-last)*(entry.DrainRate or 1))
 entry.GripUpdatedAt=now
end

local clockAccumulator=0
RunService.Heartbeat:Connect(function(dt)
 clockAccumulator+=dt
 if clockAccumulator<.1 then return end
 clockAccumulator=0
 local now=workspace:GetServerTimeNow()
 for player,entry in pairs(Carrying) do
  if not entry.Heavy or not entry.GripClockStarted or entry.Falling then continue end
  local root=Alive(player)
  if not root or SettleInLobby(player,entry,root) then continue end
  DrainGrip(entry,now)
  local mode=CucumberStrength.CARRY_MODES[entry.Mode or "Normal"]
  -- The chosen stance controls grip continuously, including while standing still.
  entry.DrainRate=mode.Drain
  PublishGrip(player,entry,now,entry.DrainRate)
  if entry.GripRemaining<=0 and now>=(entry.NextSlipTry or 0) and not entry.SlipPending then
   entry.SlipPending=true
   task.spawn(function()
    local ok,err=pcall(Stumble,player,entry)
    entry.SlipPending=false
    entry.NextSlipTry=workspace:GetServerTimeNow()+RetryDelay(entry)
    if not ok then warn("[CucumberCarry] slip failed: "..tostring(err)) end
   end)
  end
 end
end)

local lastMode={}
ModeRemote.OnServerEvent:Connect(function(player,mode)
 local entry=Carrying[player]
 if type(mode)~="string" or not CucumberStrength.CARRY_MODES[mode] or not entry or not entry.Heavy or entry.Falling then return end
 if os.clock()-(lastMode[player] or -10)<.2 then return end
 lastMode[player]=os.clock()
 local root=Alive(player)
 if not root or SettleInLobby(player,entry,root) then return end
 DrainGrip(entry,workspace:GetServerTimeNow())
 entry.Mode=mode
 local rules=CucumberStrength.CARRY_MODES[mode]
 entry.Speed=(entry.BaseSpeed or 1)*rules.Speed
 entry.DrainRate=rules.Drain
 SetCarryAttributes(player,entry)
 PublishGrip(player,entry,workspace:GetServerTimeNow(),entry.DrainRate)
end)
Players.PlayerRemoving:Connect(function(p) lastMode[p]=nil end)

SteadyRemote.OnServerEvent:Connect(function(player)
 local entry=Carrying[player]
 local root=Alive(player)
 if not entry or not root or not entry.Heavy or entry.Falling or entry.RecoveryUsed or Busy[player] then return end
 if SettleInLobby(player,entry,root) then return end
 DrainGrip(entry,workspace:GetServerTimeNow())
 local remaining=entry.GripRemaining or 0
 local duration=entry.GripDuration or 0
 if remaining<=0 or remaining>duration*CucumberStrength.RECOVERY_WINDOW then return end
 local fraction=remaining/duration
 local perfect=fraction>=CucumberStrength.PERFECT_MIN and fraction<=CucumberStrength.PERFECT_MAX
 entry.RecoveryUsed=true
 entry.GripRemaining=remaining+duration*(perfect and CucumberStrength.PERFECT_RECOVERY_FRACTION or CucumberStrength.RECOVERY_FRACTION)
 ScheduleStumble(player,entry)
 FX(player,{Kind="Steadied",Name=entry.Name,Perfect=perfect})
end)


CancelPickupRemote.OnServerEvent:Connect(function(player, token)
	local attempt = PendingCollect[player]
	if attempt and attempt.Token == token and not attempt.Grabbed then attempt.Cancel() end
end)

--..Collect (field cucumber -> shoulder)..--
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
--.. band = the CucumberStrength.BANDS entry the lift falls in (decides Heavy / Weak / Speed)
local function Grab(player, holder, host, force, band, ratio)
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
		Heavy = band ~= nil and band.Name ~= "easy", -- slowed walk + a slip on the way
		Weak = band ~= nil and band.Weak == true, -- hopeless: it slips as you stand up
		Speed = band and band.Speed or 1, -- WalkSpeed multiplier while carrying
		Band = band and band.Name or "easy",
		Ratio = ratio,
  Required = CucumberStrength.Required(holder),
  Trait = holder:GetAttribute("CarryTrait") or "Normal",
  JourneyId = holder:GetAttribute("JourneyId"),
  Recorded = holder:GetAttribute("JourneyRecorded")==true and holder:GetAttribute("JourneyRecordedBy")==player.UserId,
  RecordedBy = holder:GetAttribute("JourneyRecordedBy"),
  RecoveryUsed = holder:GetAttribute("JourneyRecoveryUsed"),
  Rescues = holder:GetAttribute("RescueCount") or 0,
  RescuePickup = holder:GetAttribute("RescueOwner")==player.UserId and (holder:GetAttribute("RescueUntil") or 0)>workspace:GetServerTimeNow(),
  Standout = holder:GetAttribute("StarFind"),
	}
	if meta.RescuePickup then meta.Rescues += 1 end
	local position = host.Position
	if GiveCarry(player, model, meta) then
		holder:Destroy() -- this field slot stays empty until the next dawn
		FX(player, {Kind = "Pickup", Name = meta.Name, Position = position})
		if meta.Heavy and Carrying[player] then ScheduleStumble(player, Carrying[player]) end
		return true
	end
	model:Destroy()
	return false
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
	if holder:GetAttribute("CollectingBy") then return end -- somebody is already tugging at it

	--.. strength gate (CucumberStrength: placeholder numbers)
	local required = CucumberStrength.Required(holder)
	local strength = StrengthOf(player)
	local verdict, struggleSeconds, band = CucumberStrength.Evaluate(strength, required)
	local prompt = PromptOf(holder)
	NextCollectToken += 1
	local attempt = {Token = NextCollectToken, Holder = holder}
	PendingCollect[player] = attempt
	Busy[player] = true
	holder:SetAttribute("CollectingBy", player.UserId)
	if prompt then prompt.Enabled = false end
	local function release()
		if PendingCollect[player] == attempt then PendingCollect[player] = nil Busy[player] = nil end
		if holder.Parent then
			holder:SetAttribute("CollectingBy", nil)
			if prompt and prompt.Parent then prompt.Enabled = true end
		end
	end

	attempt.Cancel = function()
		if attempt.Cancelled or attempt.Grabbed then return end
		attempt.Cancelled = true
		release()
		AnimRemote:FireAllClients({Kind = "Cancel", Player = player, Holder = holder, Token = attempt.Token})
	end
	local rescue=holder:GetAttribute("RescueOwner")==player.UserId and (holder:GetAttribute("RescueUntil") or 0)>workspace:GetServerTimeNow() and (holder:GetAttribute("RescueCount") or 0)<1
	if verdict == "easy" or rescue then
		local ok, grabbed = pcall(Grab, player, holder, host, force, band, CucumberStrength.Ratio(strength, required))
		release()
		if not ok then warn("[CucumberCarry] Quick pickup failed: " .. tostring(grabbed)) end
		return
	end

	if verdict == "fail" then
		--.. too heavy (CucumberStrength.WEAK_CAN_LIFT off): one short tug, then the refusal
		AnimRemote:FireAllClients({Kind = "Tug", Player = player, Holder = holder, Duration = CucumberStrength.FAIL_TUG})
		task.delay(CucumberStrength.APPROACH + CucumberStrength.FAIL_TUG, function()
			release()
			FX(player, {Kind = "Refused", Reason = "Too heavy"}) -- the number stays hidden; one line for every "can't carry it" moment
		end)
		return
	end

	task.spawn(function()
		--.. the client walks up, tugs for struggleSeconds (0 = none) and bends down;
		--.. the field cucumber becomes the shoulder copy at the grab moment
		AnimRemote:FireAllClients({Kind = "Collect", Player = player, Holder = holder, Struggle = struggleSeconds, Token = attempt.Token})
		task.wait(CucumberStrength.APPROACH + struggleSeconds + CucumberStrength.GRAB_T)
		if attempt.Cancelled or PendingCollect[player] ~= attempt then return end
		attempt.Grabbed = true
		local ok, grabbed = pcall(Grab, player, holder, host, force, band, CucumberStrength.Ratio(strength, required))
		if not ok then warn("[CucumberCarry] collect failed for " .. player.Name .. ": " .. tostring(grabbed)) end
		if ok and grabbed then
			--.. the lift finishes on the client; stay busy until the player is upright
			task.wait(CucumberStrength.PICKUP_LENGTH - CucumberStrength.GRAB_T)
			release()
		else
			release()
			AnimRemote:FireAllClients({Kind = "Cancel", Player = player, Holder = holder})
		end
	end)
end

local function AttachCollectPrompt(holder)
	--.. only cucumbers standing in a field folder (never a shoulder / plot copy)
	local container = workspace:FindFirstChild("Breakables")
	if not (container and holder:IsDescendantOf(container)) then return end
	local host = RootPartOf(holder)
	if not host or host:FindFirstChild("CollectPrompt") then return end
	--.. how strong you must be (read by CucumberPromptClient and CucumberStrength.Required)
	holder:SetAttribute("StrengthRequired", CucumberStrength.Required(holder))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom -- drawn by CucumberPromptClient
	prompt.ObjectText = holder.Name -- e.g. "Golden NEON Cucumber": CucumberPromptClient colours the words
	prompt.ActionText = "Collect"
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
	if entry.Falling then return end -- mid-stumble: it is on its way to the ground already
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
	--.. anywhere else: it flies home to a fresh random spot in the field it came from
	local holder = SpawnCarried:Invoke(zone, typeName, golden, groundPos, (function() local ex=Adventure.DropMetadata(entry) ex.Anywhere=inField return ex end)()) -- keeps its material, mutations and size; Anywhere = the exact spot even outside its own field
 if not holder then
  FX(player, {Kind = "Refused", Reason = "That field is full. Keep this cucumber or place it on your plot."})
  return
 end
 if inField then Adventure.Rescue(holder,player,entry) Adventure.Bounce(holder) end
 ClearCarry(player)
	local landing = holder and RootPartOf(holder)
	if inField and holder then
		FX(player, {Kind = "Replant", Position = landing and landing.Position or groundPos, Zone = zone, Name = name})
	else
		FX(player, {Kind = "FlyHome", Position = landing and landing.Position or nil, Zone = zone, Name = name})
	end
end

-- Server-only night drop: detach before the lobby teleport, even after fields close.
local carryAPI = ServerStorage:FindFirstChild("CucumberCarryAPI") or Instance.new("Folder")
carryAPI.Name = "CucumberCarryAPI"
carryAPI.Parent = ServerStorage
local nightDrop = carryAPI:FindFirstChild("DropForNight") or Instance.new("BindableFunction")
nightDrop.Name = "DropForNight"
nightDrop.OnInvoke = function(player)
	local attempt = PendingCollect[player]
	if attempt and not attempt.Grabbed then attempt.Cancel() end
	PendingCollect[player] = nil
	local root, character = Alive(player)
	local model = Take(player)
	Busy[player] = nil
	AnimRemote:FireAllClients({Kind = "Cancel", Player = player, CancelAll = true})
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
	if entry.Falling then return false, "stumbling" end
	SettleInLobby(player, entry, Alive(player))
	if entry.Heavy and (tonumber(entry.Ratio) or math.huge) < CucumberStrength.FLOOR_RATIO then
		--.. below the requirement and not settled by the lobby yet: never onto the plot
		FX(player, {Kind = "Refused", Reason = "Too heavy"}) -- the one line for every "can't carry it" moment (user 2026-09-07)
		return false, "too heavy"
	end
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
		SizeTier = holder:GetAttribute("SizeTier"), SizeScale = holder:GetAttribute("SizeScale"),
	}
	holder:SetAttribute("CollectingBy", nil)
	local model = BuildCarryModel(holder)
	holder:Destroy()
	if not model then return nil, "no model" end
	local placeScale = tonumber(model:GetAttribute("PlaceScale")) or 1
	if placeScale ~= 1 then
		model:ScaleTo(model:GetScale() * placeScale)
		ScaleLooks(model, placeScale)
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
	local restSize = model:GetAttribute("RestSize")
	hitbox.Size = typeof(restSize) == "Vector3" and CucumberFootprint.Box(restSize) or boxSize -- the footprint rule, not the saved (older, full) box
	hitbox.CFrame = boxCF
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Parent = model
	local name = record.Name or meta.Name
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
		}
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

--.. Lobby watch: a carry that reaches the lobby settles (Heavy / Weak / Speed off for
--.. good, whatever the band -- user 2026-09-07) and the owner gets the arrival cue once
--.. per entry from outside.
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
		warn("[CucumberCarry] lobby box unknown: heavy carries never settle")
	end
	while true do
		task.wait(0.1)
		for player, entry in pairs(Carrying) do
			local root = Alive(player)
			if root then
				if InLobby(root.Position) then
					SettleInLobby(player, entry, root)
				else
					entry.InLobby = false
					player:SetAttribute("CucumberCarrySafe",false)
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
	local attempt = PendingCollect[player]
	if attempt and not attempt.Grabbed then attempt.Cancel() end
	PendingCollect[player] = nil
	Carrying[player] = nil
	Busy[player] = nil
	LastPlace[player] = nil
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
		elseif action == "drop" then
			Drop(player)
		elseif action == "stumble" then
			local entry = Carrying[player]
			if entry then
				entry.Heavy = true
				if not Stumble(player, entry) then warn("[CucumberCarry] stumble refused (busy / seated / night)") end
			end
		elseif action == "pickup" then
			for _, placed in ipairs(CollectionService:GetTagged("PlacedCucumber")) do
				if placed:GetAttribute("Owner") == player.UserId then PickUp(player, placed, true) break end
			end
		end
	end)
end

print("[CucumberCarry] collect prompts, shoulder carry, drop and plot placement ready")

