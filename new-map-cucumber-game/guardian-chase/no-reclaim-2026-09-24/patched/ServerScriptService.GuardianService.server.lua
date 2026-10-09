--[[
	GuardianService  (ServerScriptService)  2026-09-15   -- Phase 3, the guardian chase

	One guardian per biome sits on its seat, asleep, eyes dark.  Steal a cucumber out of
	its field and it wakes up and comes after you.

	EACH GUARDIAN HAS A SET WALKSPEED, and it climbs with the biome ladder: Strawman 24
	at Spawn, Scan 96 at Neon (GuardianCatalog.GUARDIANS.<name>.speed). A new player can
	outrun the scarecrow; nobody outruns the sentinel. Heat runs them a little harder and
	a burst/rest cycle keeps the gap breathing, but the base number is fixed.

	RULES
	  * Wakes on the first field pickup in its own biome. Targets whoever is carrying one
	    of ITS cucumbers, nearest first. Someone carrying nothing is invisible to it.
	  * Sprint bursts with rests, and one of two or three OPENINGS picked per wake
	    (charge straight / cut off the exit / feint back toward the seat) so a chase never
	    plays the same way twice.
	  * THE LOBBY is the finish line. It follows you out of its own biome and only
	    breaks off once you are inside the lobby walls. The biome fence now only keeps a
	    LURKING guardian in its own patch.
	  * Caught: the zombie knockback (ZombieRaidService's 10-stud client-side parabola,
	    fired on the same remote so its client does the flight) and the cucumber FALLS WHERE
	    YOU STAND (CucumberCarryAPI.DropAtFeet). 2026-09-24 (user: "cucumber just drops but
	    the guardian doesn't take it back or put it back where it originally was"): the
	    guardian goes home EMPTY-HANDED and never reclaims what it knocked loose - the holder
	    is stamped GuardianDropped and the catch's own carry-clear is not a decoy.
	  * A cucumber you DROP yourself in the biome is a DECOY: it breaks off and reclaims that
	    first (takes it home and plants it at its seat).
	  * HEAT is server-wide: +1 per successful theft, reset at dawn. Heat wakes them
	    faster, runs them harder and lengthens their reach.
	  * The bat works on them. GuardianCatalog.STUN_HITS blows knock one out for 60 s, and
	    beating a HIGH-HEAT guardian drops a rare mutated cucumber where it fell.
	  * They sleep at night, when the fields are shut. The night wall passes through them:
	    every guardian part is in the "Guardians" collision group, which does not collide
	    with DayNightCycle's "NightBarrier" group (2026-09-18).

	DEV HOOK  workspace:SetAttribute("GuardianDev", "<verb>:<biome|all>")
	    wake:Spawn   sleep:all   stun:Farm   heat:5   home:Neon   list
	  (two writes in the same frame collapse to the last one - task.wait between them)

	Reads, and does not modify: CucumberSpawner (zones, SpawnCarried), CucumberCarry
	(the Carrying* player attributes, TakeCarried), DayNightCycle (CyclePhase),
	ZombieRaidService (its client remote, for the knockback).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Catalog = require(Modules:WaitForChild("GuardianCatalog"))
local GuardianAudio = require(Modules:WaitForChild("GuardianAudio"))
local CucumberMutations = require(Modules:WaitForChild("CucumberMutations"))
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))
local CucumberLift = require(Modules:WaitForChild("CucumberLift")) -- 2026-09-17: the biome weight ladder = the guardian's strength

local ZONES = {"Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano",
               "Narmek", "Toyland", "Neon"}

--..Collision groups..--
--.. 2026-09-18: every guardian part lives in the "Guardians" collision group, which does not
--.. collide with DayNightCycle's "NightBarrier" group (the night wall). Without it the wall,
--.. rising through the biome floor at nightfall, carried the seated guardians up on its top
--.. for the whole night, and a server started mid-night spawned them INSIDE the solid wall:
--.. physics ejected them downward past seat Y - 40 and the fell-off-the-world catch in
--.. TickOne re-seated them inside the wall again, twice a second, all night. The group is
--.. set on the clone in Spawn (and on anything parented under the model later, such as a
--.. held cucumber), so it survives re-seating, a rebuild and everything TickOne does; the
--.. ground probes below cast with the same group, so they see through the wall as well.
--.. Both scripts register both groups and the rule, so load order does not matter.
local GUARDIAN_GROUP, BARRIER_GROUP = "Guardians", "NightBarrier"
for _, group in ipairs({GUARDIAN_GROUP, BARRIER_GROUP}) do
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, group)
	end
end
pcall(PhysicsService.CollisionGroupSetCollidable, PhysicsService, GUARDIAN_GROUP, BARRIER_GROUP, false)

--..Remotes..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local Remote = Remotes:FindFirstChild(Catalog.REMOTE)
if not Remote then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = Catalog.REMOTE
	Remote.Parent = Remotes
end

--.. the zombie remote, purely to borrow its knockback: its client flies the character
--.. Distance studs along Direction on a parabola, which is exactly what we want.
local ZombieRemote
task.spawn(function()
	local ok, catalog = pcall(function()
		return require(Modules:WaitForChild("ZombieCatalog", 60))
	end)
	if ok and catalog then
		ZombieRemote = Remotes:WaitForChild(catalog.REMOTE, 60)
	end
end)

--.. CucumberCarry / CucumberSpawner publish their APIs at runtime
local SpawnCarried, TakeCarried, DropAtFeet
task.spawn(function()
	local api = ServerStorage:WaitForChild("CucumberSpawnerAPI", 120)
	SpawnCarried = api and api:WaitForChild("SpawnCarried", 30)
end)
task.spawn(function()
	local api = ServerStorage:WaitForChild("CucumberCarryAPI", 120)
	TakeCarried = api and api:WaitForChild("TakeCarried", 60)
	DropAtFeet = api and api:WaitForChild("DropAtFeet", 60) -- 2026-09-17: a caught cucumber drops at the player's feet
end)

--..State..--
local Guardians = {}        -- [name] = entry
local Heat = 0
local LastBank = {}         -- [player] = os.clock(), so one bank cannot double-count
local Live = false

local function rand(range)
	return range[1] + math.random() * (range[2] - range[1])
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function now()
	return os.clock()
end

--================================================================ the biome box
--.. workspace.Zones.ZoneParts.<zone> is the biome slab; workspace.SpawnArea.<index> is
--.. the field inside it. The SLAB is the finish line.
local function SlabOf(zone)
	local zones = Workspace:FindFirstChild("Zones")
	local parts = zones and zones:FindFirstChild("ZoneParts")
	return parts and parts:FindFirstChild(zone)
end

local function FieldOf(zone)
	local index = table.find(ZONES, zone)
	local area = Workspace:FindFirstChild("SpawnArea")
	return index and area and area:FindFirstChild(tostring(index))
end

local function InZone(zone, position, margin)
	local slab = SlabOf(zone) or FieldOf(zone)
	if not slab then return true end          -- no geometry: never fence it in
	local lp = slab.CFrame:PointToObjectSpace(position)
	margin = margin or 0
	return math.abs(lp.X) <= slab.Size.X * 0.5 + margin
	   and math.abs(lp.Z) <= slab.Size.Z * 0.5 + margin
	   and lp.Y >= -20 and lp.Y <= 160
end

--.. keep a point inside the slab, used to turn a cut-off aim into a legal destination
local function ClampToZone(zone, position, inset)
	local slab = SlabOf(zone) or FieldOf(zone)
	if not slab then return position end
	inset = inset or 4
	local lp = slab.CFrame:PointToObjectSpace(position)
	local hx = math.max(1, slab.Size.X * 0.5 - inset)
	local hz = math.max(1, slab.Size.Z * 0.5 - inset)
	return slab.CFrame:PointToWorldSpace(
		Vector3.new(math.clamp(lp.X, -hx, hx), lp.Y, math.clamp(lp.Z, -hz, hz)))
end

--.. TRUE distance from the bottom of the root to the lowest visible geometry.
--.. Every imported part carries the FBX importer's axis rotation, so a part's LOCAL Y is
--.. not world down - measuring with p.Size.Y/2 (which install.lua did) gave Ember a hip of
--.. 5.14 when the real drop is 2.2, and it spawned floating 4 studs over its own field.
--.. Project each part's three world axes instead, exactly like install.lua's boxify.
local function FootDrop(model, root)
	local lowest = math.huge
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.99 then
			local cf, sz = p.CFrame, p.Size
			local half = math.abs(cf.RightVector.Y) * sz.X * 0.5
				+ math.abs(cf.UpVector.Y) * sz.Y * 0.5
				+ math.abs(cf.LookVector.Y) * sz.Z * 0.5
			lowest = math.min(lowest, p.Position.Y - half)
		end
	end
	if lowest == math.huge then return 0 end
	return (root.Position.Y - root.Size.Y * 0.5) - lowest
end

local function GroundAt(position, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {Workspace:FindFirstChild("Breakables")}
	for _, g in pairs(Guardians) do
		if g.Model then table.insert(exclude, g.Model) end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(exclude, p.Character) end
	end
	if ignore then table.insert(exclude, ignore) end
	params.FilterDescendantsInstances = exclude
	params.CollisionGroup = GUARDIAN_GROUP       -- sees through the night wall, like the body
	local hit = Workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -260, 0), params)
	return hit and hit.Position or position
end

--.. Where a guardian sits: just INSIDE the back edge of its own field, on the field's own
--.. floor, facing in across it.
--.. It has to be ON THE FIELD FLOOR, and that is not the same as "the ground behind the
--.. field": the Spawn field sits at y -229 while the ledge 7 studs behind it is at -209,
--.. so the first version parked Strawman 20 studs up a wall where it could watch its
--.. field but never reach anyone in it. So: sample the ground from just above the field's
--.. own height, and if what we find is more than SEAT_MAX_RISE above the field, step the
--.. seat inside the field instead of behind it.
local function SeatSpot(zone)
	local field = FieldOf(zone)
	if not field then return nil, nil end
	local function groundNear(p)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local exclude = {Workspace:FindFirstChild("Breakables"), Workspace:FindFirstChild(Catalog.FOLDER)}
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then table.insert(exclude, pl.Character) end
		end
		params.FilterDescendantsInstances = exclude
		params.CollisionGroup = GUARDIAN_GROUP
		local from = Vector3.new(p.X, field.Position.Y + field.Size.Y * 0.5 + 12, p.Z)
		local hit = Workspace:Raycast(from, Vector3.new(0, -160, 0), params)
		return hit and hit.Position or Vector3.new(p.X, field.Position.Y, p.Z)
	end

	local behind = field.CFrame:PointToWorldSpace(
		Vector3.new(0, 0, -(field.Size.Z * 0.5 + Catalog.SEAT_BEHIND)))
	local spot = groundNear(behind)
	if spot.Y - field.Position.Y > Catalog.SEAT_MAX_RISE then
		--.. behind the field is a wall or a ledge: sit inside the field's own back edge
		local inside = field.CFrame:PointToWorldSpace(
			Vector3.new(0, 0, -(field.Size.Z * 0.5 - Catalog.SEAT_INSIDE)))
		spot = groundNear(inside)
	end
	local look = flat(field.Position - spot)
	if look.Magnitude < 0.1 then look = Vector3.new(0, 0, 1) end
	return spot, CFrame.lookAt(spot, spot + look.Unit)
end

--.. a random spot inside the biome to prowl to (well inside the fence, on the ground)
local function LurkPoint(entry)
	local field = FieldOf(entry.Zone)
	if not field then return entry.Home end
	local mx = field.Size.X * 0.5 + Catalog.FENCE_MARGIN - Catalog.LURK_INSET
	local mz = field.Size.Z * 0.5 + Catalog.FENCE_MARGIN - Catalog.LURK_INSET
	for _ = 1, 6 do
		local p = field.CFrame:PointToWorldSpace(Vector3.new(
			(math.random() * 2 - 1) * math.max(4, mx),
			0,
			(math.random() * 2 - 1) * math.max(4, mz)))
		local ground = GroundAt(p)
		--.. never wander up a ledge: the biome floor is the field's floor
		if math.abs(ground.Y - field.Position.Y) <= Catalog.SEAT_MAX_RISE + 4 then
			return ground
		end
	end
	return entry.Home
end

--.. THE LOBBY IS THE FINISH LINE. A guardian follows you out of its own biome now and
--.. only gives up once you are inside the lobby walls. Same box CucumberCarry uses:
--.. workspace.Map.Borders["Lobby Border"], whose wall bands are rotated, so classify
--.. them by WORLD extents rather than by Size.X/Size.Z.
local LobbyBox
local function ComputeLobbyBox()
	local borders = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Borders")
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
	if not (minX and maxX and minZ and maxZ) then return nil end
	if minX > maxX then minX, maxX = maxX, minX end
	if minZ > maxZ then minZ, maxZ = maxZ, minZ end
	return {MinX = minX, MaxX = maxX, MinZ = minZ, MaxZ = maxZ}
end

local function InLobby(position)
	if not LobbyBox then
		LobbyBox = ComputeLobbyBox()
		if not LobbyBox then return false end
	end
	return position.X >= LobbyBox.MinX and position.X <= LobbyBox.MaxX
	   and position.Z >= LobbyBox.MinZ and position.Z <= LobbyBox.MaxZ
end

--.. has this player got their cucumber home?
local function Safe(player)
	if player:GetAttribute("CucumberCarrySafe") then return true end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root ~= nil and InLobby(root.Position)
end

--================================================================ look / clips
local function SetEyes(entry, awake)
	for _, part in ipairs(entry.Model:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("AwakeHex") then
			local hex = awake and part:GetAttribute("AwakeHex") or part:GetAttribute("SleepHex")
			local mat = awake and part:GetAttribute("AwakeMaterial") or part:GetAttribute("SleepMaterial")
			if hex then
				local ok, c = pcall(Color3.fromHex, hex)
				if ok then part.Color = c end
			end
			if mat then
				local ok, m = pcall(function() return Enum.Material[mat] end)
				if ok and m then part.Material = m end
			end
		end
	end
	entry.Model:SetAttribute("Awake", awake and true or false)
end

local function Play(entry, clipName, fade, speed)
	local track = entry.Tracks[clipName]
	if not track then return nil end
	if entry.Current == track and track.IsPlaying then return track end
	for name, t in pairs(entry.Tracks) do
		if t ~= track and t.IsPlaying then t:Stop(fade or 0.2) end
	end
	track:Play(fade or 0.2)
	if speed then track:AdjustSpeed(speed) end
	entry.Current = track
	entry.CurrentName = clipName
	return track
end

local function PlayOnce(entry, clipName, fade)
	local track = entry.Tracks[clipName]
	if not track then return 0 end
	track:Play(fade or 0.1)
	return track.Length
end

--================================================================ sleeping Z's
--.. A BillboardGui of drifting z's over a guardian that is sitting down. It is built here
--.. so it replicates once, and ANIMATED on the client (GuardianClient, Heartbeat-stepped)
--.. so it costs no network traffic and keeps running with Studio unfocused - the same
--.. split the cucumber idle FX uses.
--.. Sized in STUDS, like the plot owner badge: a BillboardGui's Size scale component is
--.. studs, so it shrinks with distance the way world geometry does.
local function BuildZzz(model, root)
	local old = root:FindFirstChild("Zzz")
	if old then old:Destroy() end
	--.. sit it above the tallest visible part, not above the root
	local top = -math.huge
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.99 then
			local cf, sz = p.CFrame, p.Size
			local half = math.abs(cf.RightVector.Y) * sz.X * 0.5
				+ math.abs(cf.UpVector.Y) * sz.Y * 0.5
				+ math.abs(cf.LookVector.Y) * sz.Z * 0.5
			top = math.max(top, p.Position.Y + half)
		end
	end
	if top == -math.huge then top = root.Position.Y end

	local gui = Instance.new("BillboardGui")
	gui.Name = "Zzz"
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Size = UDim2.fromScale(Catalog.ZZZ_SIZE * 2.4, Catalog.ZZZ_SIZE * 2.4)
	gui.StudsOffsetWorldSpace = Vector3.new(0, (top - root.Position.Y) + Catalog.ZZZ_HEAD_GAP, 0)
	gui.Enabled = false
	for i = 1, Catalog.ZZZ_COUNT do
		local label = Instance.new("TextLabel")
		label.Name = "Z" .. i
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.5, 0.5)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Text = "z"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(40, 52, 78)
		stroke.Transparency = 1
		stroke.Parent = label
		label.Parent = gui
	end
	gui.Adornee = root
	gui.Parent = root
	return gui
end

--================================================================ building one
local function BuildTracks(entry)
	local hum = entry.Model:FindFirstChildOfClass("Humanoid")
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	entry.Animator = animator
	entry.Tracks = {}
	local anims = entry.Model:FindFirstChild("Anims")
	if not anims then return end
	for _, a in ipairs(anims:GetChildren()) do
		if a:IsA("Animation") then
			local ok, track = pcall(function() return animator:LoadAnimation(a) end)
			if ok and track then
				track.Priority = (a.Name == "SitIdle") and Enum.AnimationPriority.Idle
					or (a.Name == "Run") and Enum.AnimationPriority.Movement
					or Enum.AnimationPriority.Action
				track.Looped = (a.Name == "SitIdle" or a.Name == "Run" or a.Name == "Stunned")
				entry.Tracks[a.Name] = track
			end
		end
	end
end

local function Spawn(name)
	local source = ServerStorage:FindFirstChild("Assets")
	source = source and source:FindFirstChild("Guardians")
	source = source and source:FindFirstChild(name)
	if not source then
		warn("[GuardianService] no model for " .. name)
		return nil
	end
	local def = Catalog.Of(name)
	local seat, seatCF = SeatSpot(def.zone)
	if not seat then
		warn("[GuardianService] no field for " .. def.zone .. " - not spawning " .. name)
		return nil
	end

	local folder = Workspace:FindFirstChild(Catalog.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Catalog.FOLDER
		folder.Parent = Workspace
	end

	local model = source:Clone()
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CollisionGroup = GUARDIAN_GROUP        -- never touched by the night wall
		end
	end
	root.CanCollide = true                       -- the one part that stands on the ground
	model.PrimaryPart = root
	--.. anything parented under the guardian later (a held cucumber) joins the group too
	model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then d.CollisionGroup = GUARDIAN_GROUP end
	end)

	--.. the seat prop is scenery: anchored, parked, and left behind when it gets up
	local props = model:FindFirstChild("Props")
	local seatModel = props and props:FindFirstChild("Seat")
	if seatModel then
		seatModel.Parent = folder
		for _, p in ipairs(seatModel:GetDescendants()) do
			--.. NOT collidable: a lurking guardian walking back to its seat would jam
			--.. against its own hay bale / pedestal / rock nook and stop dead there.
			if p:IsA("BasePart") then
				p.Anchored = true; p.CanCollide = false; p.CollisionGroup = GUARDIAN_GROUP
			end
		end
		seatModel:PivotTo(seatCF)
		seatModel.Name = name .. "_Seat"
	end
	if props then props:Destroy() end

	--.. Recompute the hip from the real geometry, then CORRECT IT FROM THE RESULT.
	--.. HipHeight's exact meaning depends on Humanoid.RigType, and a custom Motor6D rig
	--.. is neither a stock R6 nor R15 - guessing left Ember hovering 3.4 studs over its
	--.. own field and Strawman buried 1.1 into it. So: set R15, place it, let physics
	--.. settle one beat, measure the real gap between its lowest visible geometry and the
	--.. floor, and push that error straight back into HipHeight. It converges in one pass
	--.. because HipHeight moves the body one-for-one.
	hum.RigType = Enum.HumanoidRigType.R15
	local hip = FootDrop(model, root)
	if hip <= 0.05 then hip = model:GetAttribute("BaseHipHeight") or hum.HipHeight end
	hum.HipHeight = hip
	model:SetAttribute("BaseHipHeight", hip)
	model:PivotTo(seatCF + Vector3.new(0, hip + root.Size.Y * 0.5, 0))
	model.Name = name
	model.Parent = folder

	local entry = {
		Name = name, Def = def, Zone = def.zone, Model = model, Humanoid = hum, Root = root,
		Seat = seatCF, SeatPos = seat, Home = seatCF.Position,
		State = "Asleep", Target = nil, Behaviour = nil, Tracks = {},
		WakeAt = 0, ChaseStartedAt = 0, NextRetarget = 0, NextBurst = 0, Bursting = false,
		BurstUntil = 0, StunUntil = 0, Hits = 0, LastHitAt = 0, NextSignature = 0,
		CatchCooldown = 0, Decoy = nil, DecoyUntil = 0, Carrying = nil, NextBlink = 0,
		SpeedNow = 0, Started = 0,
	}
	BuildTracks(entry)
	BuildZzz(model, root)
	SetEyes(entry, false)
	Play(entry, "SitIdle", 0)

	--.. NOTE on standing height, because it looks like a bug and is not one.
	--.. The invariant is "feet on the floor WHEN STANDING". A guardian that is asleep is
	--.. SITTING, and its SitIdle clip lifts its feet on purpose (Brisket lies down, Ember
	--.. folds into a heap, Strawman's POSE_LOC drops it 1.02 onto its bale), so measuring
	--.. the ground gap while it sleeps reports 3 studs of "float" that is the pose, not the
	--.. placement. Verify this awake. HipHeight comes straight from the model geometry -
	--.. checked against all ten source models: root-bottom-to-lowest-part == BaseHipHeight
	--.. exactly, every time.

	model:SetAttribute("Guardian", name)
	model:SetAttribute("Zone", def.zone)
	model:SetAttribute("State", "Asleep")
	GuardianAudio.Bind(model)
	return entry
end

--================================================================ the chase speed
--.. A SET WalkSpeed per guardian, climbing with the biome ladder (Catalog.GUARDIANS
--.. .speed, 24 at Spawn to 96 at Neon). Heat runs them a little harder, a burst/rest
--.. cycle keeps the gap breathing, and a slow starter takes a moment to wind up - but
--.. the base number is fixed, not solved from whoever it is chasing.
local function ChaseSpeed(entry)
	local speed = entry.Def.speed * (1 + Heat * Catalog.HEAT_SPEED_BONUS)
	if entry.Resting and not entry.Def.relentless then speed *= Catalog.REST_SPEED end
	if entry.Def.slowStart then
		speed *= math.clamp((now() - entry.Started) / entry.Def.slowStart, 0.35, 1)
	end
	return math.clamp(speed, Catalog.SPEED_MIN, Catalog.SPEED_MAX)
end

--================================================================ targeting
--.. 2026-09-23 (plan section 6, user: "chase on pickup"): TWO player attributes make somebody a guardian's
--.. business, both written by CucumberCarry:
--..   LiftingCucumberZone   the moment the lift bar opens; cleared when the lift is cancelled, fails or
--..                         times out, and again once it completes;
--..   CarryingCucumberZone  when the lift completes and the cucumber is on the shoulder (as before).
--.. A guardian WAKES and TARGETS on either, so the chase starts while you are still pumping the bar (a
--.. 4-click lift is over before it closes in; a 12 s one is a race). It only CATCHES a carrier: reaching
--.. a lifter it stays on them until the bar is won (the grab lands) or given up (Lifting clears, the
--.. chase ends on the next retarget like a drop - the cucumber never left the field, so no decoy).
local function CandidateZone(player)
	local lifting = player:GetAttribute("LiftingCucumberZone")
	if lifting then return lifting end
	if player:GetAttribute("CarryingCucumber") then return player:GetAttribute("CarryingCucumberZone") end
	return nil
end

local function Carriers(zone)
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if CandidateZone(player) == zone then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				table.insert(out, {Player = player, Root = root, Humanoid = hum})
			end
		end
	end
	return out
end

local function Nearest(entry, list)
	local best, bestD = nil, math.huge
	for _, c in ipairs(list) do
		local d = (flat(c.Root.Position) - flat(entry.Root.Position)).Magnitude
		if d < bestD then best, bestD = c, d end
	end
	return best, bestD
end

--================================================================ the openings
--.. where the guardian actually walks to this tick, given its chosen behaviour
local function AimPoint(entry, target)
	local me = entry.Root.Position
	local them = target.Root.Position
	local behaviour = entry.Behaviour

	if behaviour == "cutoff" then
		--.. aim where they will be, not where they are: lead them by their own velocity,
		--.. and bias toward the nearest biome EXIT so it gets between them and the edge
		local vel = flat(target.Root.AssemblyLinearVelocity)
		local lead = vel.Magnitude > 2 and vel.Unit * math.min(vel.Magnitude * 0.9, 26) or Vector3.zero
		--.. 2026-09-17 (user: "guardians don't leave their biome when chasing - they should while the
		--.. player still holds their cucumber"): no zone clamp on the aim while chasing; a Chasing
		--.. target is by definition a carrier of this guardian's cucumber, and the lobby (Safe) ends it
		return them + lead
	elseif behaviour == "feint" then
		--.. the first beat it drifts BACK toward its seat, then breaks for them
		if now() - entry.ChaseStartedAt < (entry.FeintFor or 1.5) then
			return entry.Home
		end
		return them
	end
	return them                                    -- charge: straight at them
end

--================================================================ effects
local function Toast(player, text, kind, seconds)
	Remote:FireClient(player, {Kind = "Toast", Text = text, Tone = kind, Seconds = seconds})
end

local function Broadcast(text, kind, seconds)
	Remote:FireAllClients({Kind = "Toast", Text = text, Tone = kind, Seconds = seconds})
end

local function Knockback(entry, player, direction, distance, seconds)
	if not ZombieRemote then return end
	ZombieRemote:FireClient(player, {
		Kind = "Hit", Zombie = entry.Name, Direction = direction, Silent = true, -- 2026-09-18: no "knocked you back!" toast
		Distance = distance or Catalog.KNOCKBACK_DISTANCE, Seconds = seconds or Catalog.KNOCKBACK_TIME, Damage = 0,
	})
end

--.. how far the catch throws you (2026-09-17, user: "knockback depends on the user's strength; really strong
--.. against the guardian = ~3 studs"): a guardian is as strong as Catalog.STRENGTH_MULT x its biome's
--.. lightest cucumber (CucumberLift.ZONE_BASE, the sign ladder); your Strength against that, on a
--.. log2 scale between KNOCKBACK_LOG_LOW and KNOCKBACK_LOG_HIGH, runs the throw from KNOCKBACK_MAX
--.. (a quarter as strong or weaker) down to KNOCKBACK_MIN (four times as strong or stronger)
local function KnockbackFor(entry, player)
	local data = player:FindFirstChild("Data")
	local value = data and data:FindFirstChild("Strength")
	local strength = value and tonumber(value.Value) or 0
	local guardian = (CucumberLift.ZONE_BASE[entry.Zone] or CucumberLift.ZONE_BASE.Spawn) * Catalog.STRENGTH_MULT
	local ratio = strength / math.max(guardian, 1)
	local t = math.clamp((math.log(math.max(ratio, 1e-9), 2) - Catalog.KNOCKBACK_LOG_LOW) / (Catalog.KNOCKBACK_LOG_HIGH - Catalog.KNOCKBACK_LOG_LOW), 0, 1)
	--.. 2026-09-18 (user: "I want the player flung"): the air time rides the same curve, so the weak
	--.. fly far AND high (the client's arc peaks at gravity x seconds^2 / 8) and the strong just hop
	local distance = Catalog.KNOCKBACK_MAX - (Catalog.KNOCKBACK_MAX - Catalog.KNOCKBACK_MIN) * t
	local timeMax = Catalog.KNOCKBACK_TIME_MAX or Catalog.KNOCKBACK_TIME
	local timeMin = Catalog.KNOCKBACK_TIME_MIN or Catalog.KNOCKBACK_TIME
	local seconds = timeMax - (timeMax - timeMin) * t
	return distance, seconds, ratio
end

--================================================================ carrying the prize
--.. attach a taken cucumber model to the guardian, and later plant it at the seat
local function HoldCucumber(entry, model)
	if not model then return end
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not primary then return end
	model.Parent = entry.Model
	--.. the decoy is a clone of a field cucumber: a template model whose parts are only ANCHORED
	--.. together, with no welds (2026-09-18) - weld every part to the root before unanchoring, or
	--.. everything but the root falls off the guardian on the way home
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Name = "GuardianCarryPart"
			w.Part0 = primary
			w.Part1 = p
			w.Parent = p
		end
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.Massless = true
		end
	end
	local anchorPart = entry.Model:FindFirstChild("Head") or entry.Root
	local _, size = model:GetBoundingBox()
	model:PivotTo(anchorPart.CFrame * CFrame.new(0, size.Y * 0.5 + 1.2, -1.4))
	local weld = Instance.new("WeldConstraint")
	weld.Name = "GuardianCarry"
	weld.Part0 = anchorPart
	weld.Part1 = primary
	weld.Parent = primary
	entry.Carrying = model
end

--.. put what it took back where it grows, unchanged
local function PlantAtSeat(entry)
	local model = entry.Carrying
	entry.Carrying = nil
	if not (model and model.Parent) then return end
	local meta = entry.CarryMeta or {}
	model:Destroy()
	if not SpawnCarried then return end

	--.. It goes back exactly as it was - same type, same material, same mutations, same
	--.. size. There is no mark and no bonus: the guardian standing over it is the point.
	local spot = entry.Seat * CFrame.new(0, 0, 3.2)
	local point = GroundAt(spot.Position)
	return SpawnCarried:Invoke(entry.Zone, meta.TypeName, meta.Golden, point, {
		Anywhere = true, Force = true,
		Material = meta.Material,
		Mutations = meta.Mutations,
		SizeTier = meta.SizeTier,
	})
end

--================================================================ state changes
local function SetState(entry, state)
	if entry.State == state then return end
	entry.State = state
	entry.Model:SetAttribute("State", state)
end

local function GoHome(entry, why)
	if entry.State == "Asleep" or entry.State == "Returning" then return end
	SetState(entry, "Returning")
	entry.Target = nil
	entry.Decoy = nil
	entry.ReturnReason = why
	entry.Model:SetAttribute("Reason", why)   -- visible in the explorer while tuning
	PlayOnce(entry, "ReturnToSeat", 0.2)
	Play(entry, "Run", 0.25)
end

local function Sleep(entry)
	SetState(entry, "Asleep")
	entry.Target = nil
	entry.Decoy = nil
	entry.SleepUntil = nil
	entry.AwakeUntil = nil
	entry.Model:SetAttribute("SleepUntil", nil)
	entry.Model:SetAttribute("AwakeUntil", nil)
	entry.Humanoid.WalkSpeed = 0
	entry.Humanoid:MoveTo(entry.Root.Position)
	local hip = entry.Model:GetAttribute("BaseHipHeight") or entry.Humanoid.HipHeight
	entry.Model:PivotTo(entry.Seat + Vector3.new(0, hip + entry.Root.Size.Y * 0.5, 0))
	SetEyes(entry, false)
	Play(entry, "SitIdle", 0.35)
end

--.. 2026-09-23 (user): the DAY-TIME NAP. A real sleep (nothing wakes it) with a clock: SleepUntil on the model is
--.. the server time it wakes, so GuardianClient can count down over its head.
local function Nap(entry)
	Sleep(entry)
	local seconds = rand(Catalog.SLEEP_SECONDS)
	entry.SleepUntil = now() + seconds
	entry.Model:SetAttribute("SleepUntil", Workspace:GetServerTimeNow() + seconds)
end

--.. sit down on the seat for a while (day-time rest, not night sleep)
local function Rest(entry)
	SetState(entry, "Resting")
	entry.Target = nil
	entry.Decoy = nil
	entry.Humanoid.WalkSpeed = 0
	entry.Humanoid:MoveTo(entry.Root.Position)
	local hip = entry.Model:GetAttribute("BaseHipHeight") or entry.Humanoid.HipHeight
	entry.Model:PivotTo(entry.Seat + Vector3.new(0, hip + entry.Root.Size.Y * 0.5, 0))
	SetEyes(entry, true) -- 2026-09-23: a resting guardian is AWAKE (eyes lit); only a nap darkens them
	Play(entry, "SitIdle", 0.35)
	entry.RestUntil = now() + rand(Catalog.REST_SECONDS)
end

--.. get up and prowl the biome
local function Lurk(entry, fresh)
	SetState(entry, "Lurking")
	entry.Target = nil
	SetEyes(entry, true) -- 2026-09-23: awake = eyes lit, so the player can read it from a distance
	if fresh then
		entry.StopsLeft = math.random(Catalog.REST_AFTER_STOPS[1], Catalog.REST_AFTER_STOPS[2])
	end
	entry.LurkAt = LurkPoint(entry)
	entry.LurkUntil = now() + Catalog.LURK_TIMEOUT
	entry.LurkPauseUntil = 0
	Play(entry, "Run", 0.3, 0.75)
end

--.. 2026-09-23: the first time one comes for you (this session) it tells you how to shake it off
local HintShown = setmetatable({}, {__mode = "k"})

local function Wake(entry, target)
	if entry.State ~= "Asleep" and entry.State ~= "Resting" and entry.State ~= "Lurking" then
		return
	end
	local fromLurk = entry.State == "Lurking"
	if now() < entry.StunUntil then return end
	SetState(entry, "Waking")
	entry.Target = target
	entry.Started = now()
	entry.ChaseStartedAt = now()
	local heat = math.clamp(1 - Heat * Catalog.HEAT_WAKE_FASTER, 0.3, 1)
	--.. already prowling? it does not have to stand up first
	entry.WakeAt = now() + rand(Catalog.WAKE_DELAY) * heat
		* (fromLurk and Catalog.WAKE_FROM_LURK or 1)
	if target.Player and not HintShown[target.Player] and Catalog.HINT then
		HintShown[target.Player] = true
		Toast(target.Player, Catalog.HINT, "Info", 4)
	end
	entry.SkipWakeClip = fromLurk
	local list = entry.Def.behaviours
	entry.Behaviour = list[math.random(1, #list)]
	entry.Model:SetAttribute("Behaviour", entry.Behaviour)  -- which opening it picked
	entry.FeintFor = rand({1.1, 2.0})
	entry.NextSignature = now() + rand(entry.Def.shakeEvery or {5, 9})
	entry.NextBlink = now() + (entry.Def.blink and rand(entry.Def.blink.every) or 999)
	entry.Resting = false
	entry.BurstUntil = now() + rand(Catalog.BURST_SECONDS)
	SetEyes(entry, true)
end

--.. 2026-09-23: the nap is over. Awake for AWAKE_SECONDS (AwakeUntil on the model for the label), and anyone
--.. still lifting or carrying in the biome is chased at once - the risk of lifting late in the countdown.
local function WakeUp(entry)
	local seconds = rand(Catalog.AWAKE_SECONDS)
	entry.SleepUntil = nil
	entry.AwakeUntil = now() + seconds
	entry.Model:SetAttribute("SleepUntil", nil)
	entry.Model:SetAttribute("AwakeUntil", Workspace:GetServerTimeNow() + seconds)
	Lurk(entry, true)
	local target = Nearest(entry, Carriers(entry.Zone))
	if target then Wake(entry, target) end
end

--================================================================ the tick
local function TickOne(entry, dt)
	local t = now()
	local model, hum, root = entry.Model, entry.Humanoid, entry.Root
	if not model.Parent then return end

	--.. FELL OFF THE WORLD. Now that a chase follows you out of the biome, a guardian can
	--.. run off an edge, and anything below workspace.FallenPartsDestroyHeight is DESTROYED
	--.. - which is how a whole set of them was reduced to a Humanoid and an Anims folder.
	--.. Catch it long before that and put it back on its seat.
	--.. (2026-09-18: a server started mid-night used to trip this too - the guardians spawned
	--.. inside the raised night wall and were ejected downward; the collision groups stop that.)
	local floorY = entry.SeatPos and entry.SeatPos.Y or entry.Home.Y
	if root.Position.Y < floorY - 40 then
		if entry.Carrying then
			entry.Carrying:Destroy()
			entry.Carrying = nil
		end
		local hip = model:GetAttribute("BaseHipHeight") or hum.HipHeight
		model:PivotTo(entry.Seat + Vector3.new(0, hip + root.Size.Y * 0.5, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		Nap(entry)
		warn(("[GuardianService] %s fell off the world and was put back"):format(entry.Name))
		return
	end

	--.. stunned: down and out, nothing else happens
	if t < entry.StunUntil then
		if entry.State ~= "Stunned" then
			SetState(entry, "Stunned")
			hum.WalkSpeed = 0
			hum:MoveTo(root.Position)
			SetEyes(entry, false)
			Play(entry, "Stunned", 0.25)
		end
		return
	elseif entry.State == "Stunned" then
		entry.Hits = 0
		GoHome(entry, "stun over")
	end

	--.. night, or the fields are shut: everyone goes back to bed
	local phase = Workspace:GetAttribute("CyclePhase")
	if phase ~= "Day" then
		if entry.State ~= "Asleep" then
			if entry.Carrying then PlantAtSeat(entry) end
			Sleep(entry)
		end
		return
	end

	--.. day (2026-09-23, user): the NAP CYCLE. Asleep from the night starts the day with a nap (SleepUntil set
	--.. here); a nap ends on its clock, then it is awake for AWAKE_SECONDS and lies down again. While it naps
	--.. nothing wakes it (OnCarryChanged ignores Asleep): that is the window to lift.
	if entry.State == "Asleep" then
		if not entry.SleepUntil then Nap(entry) return end
		if t < entry.SleepUntil then return end
		WakeUp(entry)
		return
	end
	if entry.State == "Resting" or entry.State == "Lurking" then
		if not entry.AwakeUntil then -- up without a clock (a dev wake, a fall): give it one
			local seconds = rand(Catalog.AWAKE_SECONDS)
			entry.AwakeUntil = t + seconds
			model:SetAttribute("AwakeUntil", Workspace:GetServerTimeNow() + seconds)
		elseif t >= entry.AwakeUntil then
			Nap(entry)
			return
		end
	end

	--.. sitting on the seat between patrols
	if entry.State == "Resting" then
		if t >= (entry.RestUntil or 0) then Lurk(entry, true) end
		return
	end

	--.. prowling the biome, eyes still dark
	if entry.State == "Lurking" then
		if t < (entry.LurkPauseUntil or 0) then
			hum.WalkSpeed = 0
			return
		end
		local to = entry.LurkAt or entry.Home
		local d = (flat(to) - flat(root.Position)).Magnitude
		local speed = math.clamp(entry.Def.speed * Catalog.LURK_SPEED,
			Catalog.SPEED_MIN * 0.5, Catalog.SPEED_MAX)
		hum.WalkSpeed = speed
		hum:MoveTo(to)
		Play(entry, "Run", 0.3, 0.75)
		--.. jammed on a cucumber, a tree or a lip of terrain? MoveTo walks in a straight
		--.. line, so a blocked guardian would stand there grinding until the timeout.
		local since = entry.LurkCheckAt or 0
		if t - since > 2.5 then
			local moved = entry.LurkLast and (flat(root.Position) - flat(entry.LurkLast)).Magnitude or 99
			entry.LurkCheckAt = t
			entry.LurkLast = root.Position
			if moved < 2 then
				entry.LurkAt = LurkPoint(entry)
				entry.LurkUntil = t + Catalog.LURK_TIMEOUT
				entry.LurkStuck = (entry.LurkStuck or 0) + 1
			else
				entry.LurkStuck = 0
			end
		end
		if d < Catalog.LURK_REACH or t > (entry.LurkUntil or 0) then
			entry.LurkPauseUntil = t + rand(Catalog.LURK_PAUSE)
			--.. 2026-09-23 (user: "it sleeps even when it says awake"): no seat sit while awake - the sitting pose
			--.. IS the sleeping pose. It prowls stop after stop until AwakeUntil, then naps.
			entry.LurkAt = LurkPoint(entry)
			entry.LurkUntil = t + Catalog.LURK_TIMEOUT
		end
		--.. wandering out of its own biome turns it round like anything else
		if not InZone(entry.Zone, root.Position, Catalog.FENCE_MARGIN) then
			entry.LurkAt = entry.Home
			entry.LurkUntil = t + Catalog.LURK_TIMEOUT
		end
		return
	end

	--.. waking: hold the Wake clip before it starts moving
	if entry.State == "Waking" then
		if t < entry.WakeAt then return end
		if entry.WakeClipUntil == nil then
			--.. already on its feet: no stand-up, it just turns and goes
			local len = entry.SkipWakeClip and 0 or PlayOnce(entry, "Wake", 0.15)
			entry.WakeClipUntil = t + math.min(len, 1.2) * Catalog.WAKE_CLIP_HOLD
			return
		end
		if t < entry.WakeClipUntil then return end
		entry.WakeClipUntil = nil
		SetState(entry, "Chasing")
		entry.ChaseStartedAt = t
		Play(entry, "Run", 0.25)
	end


	--.. going home
	if entry.State == "Returning" then
		local d = (flat(root.Position) - flat(entry.Home)).Magnitude
		hum.WalkSpeed = math.clamp(entry.Def.speed, Catalog.SPEED_MIN, Catalog.SPEED_MAX)
		hum:MoveTo(entry.Home)
		if d < 4 then
			if entry.Carrying then PlantAtSeat(entry) end
			--.. 2026-09-23: back on its feet if its awake window is still running, else straight into the nap
			if entry.AwakeUntil and t < entry.AwakeUntil then Lurk(entry, true) else Nap(entry) end
		end
		return
	end

	--.. reclaiming a decoy
	if entry.State == "Reclaiming" then
		local decoy = entry.Decoy
		if not (decoy and decoy.Parent) or t > entry.DecoyUntil then
			entry.Decoy = nil
			SetState(entry, "Chasing")
		else
			local part = decoy.PrimaryPart or decoy:FindFirstChildWhichIsA("BasePart")
			local to = part and part.Position or entry.Home
			hum.WalkSpeed = math.clamp(entry.Def.speed, Catalog.SPEED_MIN, Catalog.SPEED_MAX)
			hum:MoveTo(to)
			if part and (flat(to) - flat(root.Position)).Magnitude < Catalog.DECOY_REACH then
				--.. it has the decoy: take it home and sit on it
				entry.CarryMeta = {
					TypeName = decoy:GetAttribute("TypeName") or decoy.Name,
					Golden = decoy:GetAttribute("Golden"),
					Material = decoy:GetAttribute("Material"),
					Mutations = decoy:GetAttribute("Mutations"),
					SizeTier = decoy:GetAttribute("SizeTier"),
				}
				local clone = decoy:Clone()
				decoy:Destroy()
				entry.Decoy = nil
				PlayOnce(entry, "Grab", 0.1)
				HoldCucumber(entry, clone)
				GoHome(entry, "took the decoy")
			end
			return
		end
	end

	--.. chasing
	if entry.State ~= "Chasing" then return end

	if t > entry.ChaseStartedAt + Catalog.GIVE_UP_SECONDS then
		GoHome(entry, "gave up")
		return
	end

	--.. re-pick the nearest carrier of one of MY cucumbers
	if t >= entry.NextRetarget then
		entry.NextRetarget = t + Catalog.RETARGET_SECONDS
		local list = Carriers(entry.Zone)
		if #list == 0 then
			GoHome(entry, "nobody is carrying")
			return
		end
		local best, d = Nearest(entry, list)
		if not best or d > Catalog.LOSE_DISTANCE then
			GoHome(entry, "too far")
			return
		end
		entry.Target = best
	end

	local target = entry.Target
	if not (target and target.Root and target.Root.Parent
		and CandidateZone(target.Player) == entry.Zone) then -- 2026-09-23: lifting OR carrying one of mine
		entry.NextRetarget = 0
		return
	end

	--.. they made it to the lobby: the cucumber is theirs, go home
	if Safe(target.Player) then
		GoHome(entry, "they reached the lobby")
		return
	end

	--.. sprint bursts with rests
	if not entry.Def.relentless and t >= entry.BurstUntil then
		entry.Resting = not entry.Resting
		entry.BurstUntil = t + rand(entry.Resting and Catalog.REST_SECONDS_CHASE
			or Catalog.BURST_SECONDS)
		if entry.Def.windDown and entry.Resting then
			PlayOnce(entry, entry.Def.signature, 0.15)   -- Tick literally rewinds itself
		end
	end

	--.. the signature move, on its own clock
	if t >= entry.NextSignature and entry.Tracks[entry.Def.signature] then
		entry.NextSignature = t + rand(entry.Def.shakeEvery or {6, 11})
		PlayOnce(entry, entry.Def.signature, 0.15)
	end

	--.. blink: Orbit and Scan close the gap instead of running it
	if entry.Def.blink and t >= entry.NextBlink then
		entry.NextBlink = t + rand(entry.Def.blink.every)
		local to = target.Root.Position
		local dir = flat(to - root.Position)
		if dir.Magnitude > 6 then
			local step = math.min(entry.Def.blink.studs, dir.Magnitude - 4)
			local dest = root.Position + dir.Unit * step -- 2026-09-17: blinks follow the thief out of the biome too
			PlayOnce(entry, entry.Def.signature, 0.1)
			local hip = model:GetAttribute("BaseHipHeight") or hum.HipHeight
			model:PivotTo(CFrame.lookAt(Vector3.new(dest.X, GroundAt(dest).Y + hip + 0.3, dest.Z),
				Vector3.new(to.X, GroundAt(dest).Y + hip + 0.3, to.Z)))
		end
	end

	local speed = ChaseSpeed(entry)
	entry.SpeedNow = speed
	hum.WalkSpeed = speed
	hum:MoveTo(AimPoint(entry, target))
	Play(entry, "Run", 0.2, math.clamp(speed / 30, 0.6, 1.9))

	--.. the catch: it needs the CARRY (a target still pumping the lift bar is hovered, never grabbed, and the
	--.. cooldown is not spent, so the grab lands the tick the lift completes). 2026-09-17: the throw scales with
	--.. your Strength and the cucumber FALLS WHERE YOU STAND (CucumberCarryAPI.DropAtFeet); 2026-09-18: no catch
	--.. toast, Silent knockback. 2026-09-23: the delayed-arrival / grace / wind-up experiment is gone (user:
	--.. "delay in attacking, sometimes doesn't attack at all") - the nap cycle is the mercy now.
	local gap = (flat(target.Root.Position) - flat(root.Position)).Magnitude
	local reach = Catalog.REACH * entry.Def.reach + Heat * Catalog.HEAT_REACH_BONUS
	if gap <= reach and t >= entry.CatchCooldown then
		local player = target.Player
		if player:GetAttribute("CarryingCucumber") and DropAtFeet then
			entry.CatchCooldown = t + Catalog.CATCH_COOLDOWN
			local dir = flat(target.Root.Position - root.Position)
			dir = dir.Magnitude > 0.1 and dir.Unit or root.CFrame.LookVector
			PlayOnce(entry, "Grab", 0.1)
			local distance, seconds = KnockbackFor(entry, player)
			Knockback(entry, player, dir, distance, seconds)
			--.. 2026-09-24: the knocked-loose cucumber stays where it fell; this guardian never reclaims it
			local holder = DropAtFeet:Invoke(player)
			if typeof(holder) == "Instance" then holder:SetAttribute("GuardianDropped", true) end
			entry.CaughtDropAt = t
			GoHome(entry, "caught them")
		end
	end
end

--================================================================ heat
local function SetHeat(value)
	Heat = math.clamp(value, 0, Catalog.HEAT_MAX)
	Workspace:SetAttribute(Catalog.HEAT_ATTRIBUTE, Heat)
end

local function AddHeat(n)
	SetHeat(Heat + (n or 1))
end

--================================================================ the bat
--.. 2026-09-18 (user: "get rid of being able to hit and knock out guardians"): the bat no longer
--.. touches guardians. The whole stun system (hit counter, 60 s knockout, the high-heat mutated
--.. drop and its toasts / broadcast) is retired; the old body is in
--.. backups/NewMap_GuardianService+AdventureClient_before-no-stun_2026-09-18.rbxm. The API stays
--.. for anything that still asks, and always says no.
local function DamageGuardian(model, damage, source, attacker)
	return false
end

--================================================================ watching players
--.. a lift starting (or a pickup) in a biome wakes that biome's guardian - see CandidateZone
local function OnCarryChanged(player)
	local zone = CandidateZone(player)
	if not zone then return end
	local name = Catalog.BY_ZONE[zone]
	local entry = name and Guardians[name]
	if not entry then return end
	if Workspace:GetAttribute("CyclePhase") ~= "Day" then return end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	--.. 2026-09-23 (user): a NAPPING guardian (Asleep) is not woken by a lift or a pickup - that is the window.
	--.. When the nap ends, WakeUp goes for anyone still lifting or carrying. Awake (Resting / Lurking) = at once.
	local idle = entry.State == "Resting" or entry.State == "Lurking"
	if idle and now() >= entry.StunUntil then
		local hum = char:FindFirstChildOfClass("Humanoid")
		Wake(entry, {Player = player, Root = root, Humanoid = hum}) -- 2026-09-18 (user): no "is waking up!" toast
		GuardianAudio.StolenFrom(entry.Model) -- 2026-09-23 (user): the sfx only when it actually wakes; a napping guardian is silent
	end
end

--.. a cucumber dropped inside a biome is a decoy the guardian will break off for
local function OnCarryCleared(player, zone)
	local name = zone and Catalog.BY_ZONE[zone]
	local entry = name and Guardians[name]
	if not (entry and (entry.State == "Chasing" or entry.State == "Waking"
		or entry.State == "Lurking")) then return end
	--.. 2026-09-24: a carry that clears right after this guardian's catch IS the catch (DropAtFeet): no decoy
	if entry.CaughtDropAt and now() - entry.CaughtDropAt < 1.5 then return end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	--.. find the field cucumber that just landed near them
	task.delay(0.35, function()
		if entry.State ~= "Chasing" and entry.State ~= "Waking"
			and entry.State ~= "Lurking" then return end
		local breakables = Workspace:FindFirstChild("Breakables")
		local folder = breakables and breakables:FindFirstChild(zone)
		if not folder then return end
		local best, bestD = nil, Catalog.DECOY_RADIUS
		for _, holder in ipairs(folder:GetChildren()) do
			local part = holder:IsA("Model") and (holder.PrimaryPart or holder:FindFirstChildWhichIsA("BasePart"))
				or (holder:IsA("BasePart") and holder)
			if part and holder:GetAttribute("GuardianDropped") then part = nil end -- 2026-09-24: knocked loose by a catch: never a decoy
			if part then
				local d = (flat(part.Position) - flat(root.Position)).Magnitude
				if d < bestD then best, bestD = holder, d end
			end
		end
		if best then
			entry.Decoy = best
			entry.DecoyUntil = now() + Catalog.DECOY_SECONDS
			SetState(entry, "Reclaiming")
		end
	end)
end

--.. banking a biome cucumber in the lobby is a successful theft: heat, and the callout
local function OnBanked(player)
	local t = now()
	if LastBank[player] and t - LastBank[player] < 1 then return end
	LastBank[player] = t
	local zone = player:GetAttribute("CarryingCucumberZone")
	local size = player:GetAttribute("CarryingCucumberSize")
	local name = zone and Catalog.BY_ZONE[zone]
	local entry = name and Guardians[name]
	AddHeat(1)
	--.. 2026-09-18 (user): no guardian toasts at all - the "escaped <guardian> with a <size> <cucumber>!"
	--.. server-wide callout is gone with the rest
end

local function Watch(player)
	--.. 2026-09-23: the lift bar opening is the wake cue. A LiftingCucumberZone that clears with no carry
	--.. behind it is a given-up lift: the cucumber never left the field, so there is nothing to reclaim and
	--.. the chase ends on the next retarget (Carriers finds nobody); a completed lift hands over to the
	--.. CarryingCucumber signal below.
	player:GetAttributeChangedSignal("LiftingCucumberZone"):Connect(function()
		if player:GetAttribute("LiftingCucumberZone") then OnCarryChanged(player) end
	end)
	player:GetAttributeChangedSignal("CarryingCucumber"):Connect(function()
		if player:GetAttribute("CarryingCucumber") then
			OnCarryChanged(player)
			player:SetAttribute("GuardianLastZone", player:GetAttribute("CarryingCucumberZone"))
		else
			OnCarryCleared(player, player:GetAttribute("GuardianLastZone"))
		end
	end)
	player:GetAttributeChangedSignal("CucumberCarrySafe"):Connect(function()
		if player:GetAttribute("CucumberCarrySafe") then OnBanked(player) end
	end)
end

--================================================================ dev hook
local function Dev(command)
	if not command or command == "" then return end
	local verb, which = command:match("^(%a+):?(.*)$")
	verb = (verb or ""):lower()
	which = which ~= "" and which or "all"
	local function each(fn)
		for name, entry in pairs(Guardians) do
			if which == "all" or which == name or which == entry.Zone then fn(entry) end
		end
	end
	if verb == "wake" then
		each(function(e)
			local list = Carriers(e.Zone)
			local target = list[1] or (Players:GetPlayers()[1] and {
				Player = Players:GetPlayers()[1],
				Root = Players:GetPlayers()[1].Character
					and Players:GetPlayers()[1].Character:FindFirstChild("HumanoidRootPart"),
			})
			if target and target.Root then
				e.StunUntil = 0
				Wake(e, target)
			end
		end)
	elseif verb == "sleep" then
		each(function(e) if e.Carrying then PlantAtSeat(e) end Sleep(e) end)
	elseif verb == "stun" then
		each(function(e) e.StunUntil = now() + Catalog.STUN_SECONDS end)
	elseif verb == "heat" then
		SetHeat(tonumber(which) or 0)
	elseif verb == "home" then
		each(function(e) GoHome(e, "dev") end)
	elseif verb == "list" then
		local rows = {}
		for _, name in ipairs(Catalog.ORDER) do
			local e = Guardians[name]
			if e then
				table.insert(rows, ("%s[%s] %s speed %.1f%s"):format(name, e.Zone, e.State,
					e.SpeedNow, e.Carrying and " CARRYING" or ""))
			end
		end
		print("[GuardianService] heat " .. Heat .. " | " .. table.concat(rows, " | "))
	end
	Workspace:SetAttribute(Catalog.DEV_ATTRIBUTE, nil)
end

--================================================================ boot
local function Boot()
	for _, name in ipairs(Catalog.ORDER) do
		local entry = Spawn(name)
		if entry then Guardians[name] = entry end
	end
	Live = true

	--.. the API the bat calls
	local api = ServerStorage:FindFirstChild("GuardianAPI") or Instance.new("Folder")
	api.Name = "GuardianAPI"
	api.Parent = ServerStorage
	local list = api:FindFirstChild("Guardians") or Instance.new("BindableFunction")
	list.Name = "Guardians"
	list.OnInvoke = function()
		local out = {}
		for _, e in pairs(Guardians) do
			if e.Model.Parent and e.State ~= "Asleep" then table.insert(out, e.Model) end
		end
		return out
	end
	list.Parent = api
	local damage = api:FindFirstChild("Damage") or Instance.new("BindableFunction")
	damage.Name = "Damage"
	damage.OnInvoke = function(model, amount, source, attacker)
		return DamageGuardian(model, amount, source, attacker)
	end
	damage.Parent = api

	for _, player in ipairs(Players:GetPlayers()) do Watch(player) end
	Players.PlayerAdded:Connect(Watch)
	Players.PlayerRemoving:Connect(function(p) LastBank[p] = nil end)

	--.. heat resets at dawn
	Workspace:GetAttributeChangedSignal("CyclePhase"):Connect(function()
		local phase = Workspace:GetAttribute("CyclePhase")
		if phase == "Day" then
			SetHeat(0)
		elseif phase == "Night" then
			for _, e in pairs(Guardians) do
				if e.Carrying then PlantAtSeat(e) end
				Sleep(e)
			end
		end
	end)

	Workspace:GetAttributeChangedSignal(Catalog.DEV_ATTRIBUTE):Connect(function()
		local v = Workspace:GetAttribute(Catalog.DEV_ATTRIBUTE)
		if v then task.spawn(Dev, tostring(v)) end
	end)

	SetHeat(0)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not Live then return end
		acc += dt
		if acc < 0.08 then return end          -- ~12 Hz is plenty for a chase
		local step = acc
		acc = 0
		for _, entry in pairs(Guardians) do
			local ok, err = pcall(TickOne, entry, step)
			if not ok then warn("[GuardianService] " .. entry.Name .. ": " .. tostring(err)) end
		end
	end)

	print(("[GuardianService] %d guardians on their seats"):format(#Catalog.ORDER))
end

task.spawn(function()
	--.. the fields have to exist before a seat can be placed on one
	local tries = 0
	while not Workspace:FindFirstChild("SpawnArea") and tries < 120 do
		task.wait(0.5)
		tries += 1
	end
	task.wait(1)
	Boot()
end)
