-- Six field cucumbers per biome at dawn (2 sliced + 4 regular).
-- DayNightCycle owns clearing and reseeding. Collected cucumbers stay gone until dawn.
-- Every server rolls the SAME morning (2026-09-06): BeginDay seeds the dice with the shared
-- day number (DayNightCycle's real-time calendar), so types, spots, colours, materials and
-- mutations match on every server, and only MUTATED_PER_DAY (0..4) cucumbers across ALL
-- biomes carry mutations each day.
-- GIANTS (2026-09-08): the same morning roll also picks 0..3 cucumbers across ALL biomes to grow
-- to 2x / 3x / 4x their size (CucumberMutations.SIZES / GIANT_CHANCE) -- a third mutation axis
-- beside Material and Mutations. They keep their size when dropped, when they slip and on the plot.
-- LANDMARKS (2026-09-23): the biome's "T" type (the last card of its Index page) is no longer kept
-- standing every day. Every regular roll has a 1-in-LANDMARK_ODDS[zone] chance of being it (one
-- standing per biome at most), and every type def carries its per-roll odds (Odds, "1 in X") plus
-- Landmark = true on that one, which CucumberAdventure.SetCatalog hands to the Index cards.
-- Biome tracking and carry/drop API remain available for streaming and collection.

--..Services..--
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local CucumberMutations = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CucumberMutations"))
local CucumberLift = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CucumberLift")) -- kg -> visual size (WeightScale, 2026-09-17)

--..Config (same numbers as the live BreakablesService)..--
local ZONES = {"Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek", "Toyland", "Neon"}
local CUCUMBERS_PER_BIOME = 10 -- 2026-09-23 economy: was 6 (SLICED_PER_BIOME of them are slices = 2 slices + 8 others per biome, 100 a day)
local SLICED_PER_BIOME = 2
local POPULATION_PLAN_TICK = 0.5
local ZONE_UNLOAD_GRACE = 8
local SPAWN_AREA_PADDING = 4
local MIN_CUCUMBER_DISTANCE = 6 -- minimum horizontal center-to-center spacing
local TEMPLATE_SCALE = 0.75 -- all non-boss, non-sliced breakables are 75% of their authored size
local GOLDEN_CHANCE = 0.04
local GOLDEN_COLOR = Color3.fromRGB(255, 200, 30)
--.. how many of the day's cucumbers (all biomes together) carry mutations: index = count, value = chance
local MUTATED_PER_DAY = {[0] = 0.15, [1] = 0.35, [2] = 0.28, [3] = 0.15, [4] = 0.07}
-- "inside a biome" = standing on its slab. Uses workspace.Zones.ZoneParts.<zone> when
-- that exists (live-game layout); otherwise the slab is derived from the SpawnArea part:
local SLAB_HALF_X = 70 -- floor slabs are 140 x 112 studs, centred on the SpawnArea part
local SLAB_HALF_Z = 56
local SLAB_MARGIN = 6

--.. shared pool for zones without hand-modelled sets (the live TYPES table). Since 2026-09-18 every
--.. zone has a RAW pool (Toyland + Neon were the last two), so no zone rolls from this any more; it
--.. stays as the catalogue fallback for a zone RAW does not list
local TYPES = {
	{Name = "Cucumber", Weight = 35, Scale = 3},
	{Name = "Giant Cucumber", Weight = 22, Scale = 5.5},
	{Name = "Sliced Cucumber", Weight = 25, Sliced = true},
	{Name = "Cucumber Tree", Weight = 8, Tree = true, Template = "Cucumber Tree"},
}
--.. exclusive hand-modelled pools (name, weight, S = sliced / T = tree); Template = "<Zone> <Name>"
local RAW = {
	Spawn = {{"Sliced Cucumber", 25, "S"}, {"Cucumber", 61}, {"Slice Stack", 24}, {"Vined Cucumber", 10}, {"Flowered Cucumber", 4}, {"Cucumber Tree", 2, "T"}},
	Desert = {{"Sun-Dried Slice", 25, "S"}, {"Prickly Cucumber", 46}, {"Sliced Cucumber", 25}, {"Sun-Baked Cucumber", 14}, {"Wrapped Cucumber", 7}, {"Cactus Cucumber", 4}, {"Desert Palm", 2}, {"Sandstone Tree", 1, "T"}},
	Samurai = {{"Sliced Cucumber", 25, "S"}, {"Katana Cucumber", 53}, {"Bamboo Cucumber", 25}, {"Lantern Cucumber", 12}, {"Bamboo Grove", 6}, {"Torii Gate", 3}, {"Sakura Tree", 1, "T"}},
	Farm = {{"Cucumber Basket", 25, "S"}, {"Muddy Cucumber", 61}, {"Crate Cucumber", 24}, {"Windmill Plant", 10}, {"Hay Bale", 4}, {"Cucumber Tree", 2, "T"}},
	Snow = {{"Frozen Slice", 25, "S"}, {"Snowcap Cucumber", 46}, {"Snowball Slice", 25}, {"Crystal Cucumber", 14}, {"Frozen Cucumber", 7}, {"Snow Tree", 4}, {"Icicle Tree", 2}, {"Frozen Tree", 1, "T"}},
	Underwater = {{"Bubble Slice", 25, "S"}, {"Seaweed Cucumber", 46}, {"Shell Slice", 25}, {"Coral Cucumber", 14}, {"Pearl Cucumber", 7}, {"Kelp Tree", 4}, {"Bubble Tree", 2}, {"Coral Tree", 1, "T"}},
	Volcano = {{"Molten Slice", 25, "S"}, {"Charred Cucumber", 53}, {"Molten Cucumber", 25}, {"Flame Cucumber", 12}, {"Obsidian Tree", 6}, {"Volcano Cucumber", 3}, {"Magma Tree", 1, "T"}},
	Narmek = {{"Moon Slice", 25, "S"}, {"Meteor Cucumber", 46}, {"Planet Slice", 25}, {"Astronaut Cucumber", 14}, {"Neon Alien Cucumber", 7}, {"Moon Tree", 4}, {"Alien Tree", 2}, {"Galaxy Tree", 1, "T"}},
	--.. 2026-09-18: hand-modelled sets replace the generic pool in the last two biomes (the user's
	--.. reference sheet, common -> rare left to right; the rarest is the daily landmark "T")
	Toyland = {{"Toy Slice", 25, "S"}, {"Lego Cucumber", 53}, {"Jack-in-the-Box Cucumber", 25}, {"Toy Rocket Cucumber", 12}, {"Pinwheel Plant", 6}, {"Building Block Tree", 3}, {"Toy Train Cucumber", 1, "T"}},
	Neon = {{"Neon Slice", 25, "S"}, {"Electro Cucumber", 53}, {"Neon Grid Cucumber", 25}, {"Hologram Cucumber", 12}, {"Neon Palm", 6}, {"Neon Tree", 3}, {"Cyber Cucumber", 1, "T"}},
}
--.. a cucumber SAVED under a name its zone no longer has (plot saves from before 2026-09-18, when
--.. Toyland / Neon still spawned the generic pool) comes back as the new type closest in value
--.. (CucumberValues: 3 -> 3, 8 -> 8, 45 -> 37, 140 -> 173). TypeByName only; nothing rolls these.
local LEGACY_TYPES = {
	Toyland = {["Sliced Cucumber"] = "Toy Slice", ["Cucumber"] = "Lego Cucumber", ["Giant Cucumber"] = "Toy Rocket Cucumber", ["Cucumber Tree"] = "Building Block Tree"},
	Neon = {["Sliced Cucumber"] = "Neon Slice", ["Cucumber"] = "Electro Cucumber", ["Giant Cucumber"] = "Hologram Cucumber", ["Cucumber Tree"] = "Neon Tree"},
}
local ZONE_EXCLUSIVE_TYPES = {}
for zone, list in pairs(RAW) do
	local pool = {}
	for _, r in ipairs(list) do
		pool[#pool + 1] = {Name = r[1], Weight = r[2], Sliced = r[3] == "S" or nil, Tree = r[3] == "T" or nil, Template = zone .. " " .. r[1]}
	end
	ZONE_EXCLUSIVE_TYPES[zone] = pool
end
--.. tint / material / glow for the procedural (generic-pool) biomes -- unreachable since 2026-09-18
--.. (Toyland / Neon have their own models now); kept with the procedural builders below
local ZONE_COLOR = {Toyland = Color3.fromRGB(170, 90, 240), Neon = Color3.fromRGB(0, 255, 255)}
local ZONE_MATERIAL = {Neon = Enum.Material.Neon}
local ZONE_GLOW = {Neon = Color3.fromRGB(0, 255, 255)}

--..Instances..--
local Templates = ServerStorage:WaitForChild("Assets"):WaitForChild("BreakableModels")
local SpawnAreaFolder = workspace:WaitForChild("SpawnArea")
--.. mutated spawns are announced in chat by MutationChatClient (2026-09-06)
local RemotesFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
if not RemotesFolder then RemotesFolder = Instance.new("Folder") RemotesFolder.Name = "Remotes" RemotesFolder.Parent = game:GetService("ReplicatedStorage") end
local AnnounceRemote = RemotesFolder:FindFirstChild("MutationAnnounce")
if not AnnounceRemote then AnnounceRemote = Instance.new("RemoteEvent") AnnounceRemote.Name = "MutationAnnounce" AnnounceRemote.Parent = RemotesFolder end

local Adventure = require(ServerStorage:WaitForChild("CucumberAdventure"))

--.. a type whose template model is missing can never spawn: flag it once at startup so
--.. no roll ever picks it (2026-09-06: "Desert Desert Palm" was missing and the morning
--.. assert below killed the whole DayNightCycle -> CyclePhase stuck at PreparingDay)
for zone, pool in pairs(ZONE_EXCLUSIVE_TYPES) do
	for _, t in ipairs(pool) do
		if t.Template and not Templates:FindFirstChild(t.Template) then
			t.Missing = true
			warn(("[CucumberSpawner] %s: no template '%s' in BreakableModels; '%s' will not spawn"):format(zone, t.Template, t.Name))
		end
	end
end
for _, t in ipairs(TYPES) do
	if t.Template and not Templates:FindFirstChild(t.Template) then
		t.Missing = true
		warn(("[CucumberSpawner] generic pool: no template '%s'; '%s' will not spawn"):format(t.Template, t.Name))
	end
end
--.. a pool name CucumberValues has no reward for silently prices at DEFAULT_REWARD, weighs the
--.. same as its neighbours and scrambles the index order (2026-09-18): say so at startup
do
	local Values = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CucumberValues"))
	for zone, pool in pairs(ZONE_EXCLUSIVE_TYPES) do
		local rewards = Values.REWARDS[zone]
		for _, t in ipairs(pool) do
			if not (rewards and rewards[t.Name]) then
				warn(("[CucumberSpawner] %s: no CucumberValues.REWARDS entry for '%s'"):format(zone, t.Name))
			end
		end
	end
end

-- All biome cucumbers stay replicated to every player, regardless of distance/device.
local Container = workspace:FindFirstChild("Breakables")
if Container and not Container:IsA("Model") then
 local previous = Container
 Container = Instance.new("Model")
 Container.Name = "Breakables"
 Container.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
 for name,value in pairs(previous:GetAttributes()) do Container:SetAttribute(name,value) end
 for _,child in ipairs(previous:GetChildren()) do child.Parent = Container end
 previous:Destroy()
 Container.Parent = workspace
end
if not Container then
 Container = Instance.new("Model")
 Container.Name = "Breakables"
 Container.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
 Container.Parent = workspace
end
Container.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
local ZoneFolders = {}
for _, zone in ipairs(ZONES) do
	local f = Container:FindFirstChild(zone)
	if not f then
		f = Instance.new("Folder")
		f.Name = zone
		f.Parent = Container
	end
	ZoneFolders[zone] = f
end

--..State..--
local Live = {} -- [holder] = {Zone, Type, Golden}
local Population = {} -- [zone] = {Sliced, Other}
local LastActiveAt = {} -- [zone] = os.clock()
local LastInhabitedIndex = {} -- [player] = ZONES index of the biome they last stood inside
local FieldsOpen = false
local CurrentDay = 0
--.. the day's dice: seeded with the day number by BeginDay so every server rolls the same morning
--.. (types, spots, yaw, colours, materials, mutations); nil outside the morning spawn = math.random
local Rng = nil
local function rand()
	return Rng and Rng:NextNumber() or math.random()
end
local function randint(a, b)
	return Rng and Rng:NextInteger(a, b) or math.random(a, b)
end

--..Population bookkeeping..--
local function PopulationOf(zone)
	local p = Population[zone]
	if not p then
		p = {Sliced = 0, Other = 0}
		Population[zone] = p
	end
	return p
end

local function TrackAdded(zone, typeDef)
	local p = PopulationOf(zone)
	if typeDef.Sliced then p.Sliced += 1 else p.Other += 1 end
end

local function TrackRemoved(zone, typeDef)
	local p = PopulationOf(zone)
	if typeDef.Sliced then p.Sliced = math.max(0, p.Sliced - 1) else p.Other = math.max(0, p.Other - 1) end
end

local function CountZonePopulation(zone)
	local p = PopulationOf(zone)
	return p.Sliced, p.Other
end

local function Register(holder, zone, typeDef, golden, material, mutations, sizeTier)
	Live[holder] = {Zone = zone, Type = typeDef, Golden = golden, Material = material, Mutations = mutations, SizeTier = sizeTier}
	TrackAdded(zone, typeDef)
	holder:SetAttribute("SpawnDay", CurrentDay)
	holder:SetAttribute("TypeName", typeDef.Name)
	holder:SetAttribute("Zone", zone)
	holder:SetAttribute("Sliced", typeDef.Sliced == true)
	holder:SetAttribute("Golden", golden == true)
	holder:SetAttribute("Material", material) -- "Golden" | "Diamond" | nil (CucumberMutations)
	holder:SetAttribute("Mutations", CucumberMutations.Join(mutations or {})) -- "NEON,FROZEN" | ""
	holder:SetAttribute("SizeTier", sizeTier) -- "HUGE" | "MASSIVE" | "COLOSSAL" | nil (CucumberMutations.SIZES)
	holder:SetAttribute("SizeScale", CucumberMutations.ScaleOf(sizeTier)) -- 2 | 3 | 4 | 1: what its size was multiplied by
	holder:SetAttribute("Tree", typeDef.Tree == true) -- landmark trees weigh more (CucumberStrength)
	if typeDef.Template then holder:SetAttribute("Template", typeDef.Template) end
	CollectionService:AddTag(holder, "Breakable")
	--.. anything that destroys or unparents a cucumber (future smash code) frees its slot
	holder.AncestryChanged:Connect(function()
		if Live[holder] and not holder:IsDescendantOf(workspace) then
			Live[holder] = nil
			TrackRemoved(zone, typeDef)
		end
	end)
end

--..Type pools..--
local function EffectiveTypes(zone)
	return ZONE_EXCLUSIVE_TYPES[zone] or TYPES
end

--.. 2026-09-23: the landmark ("T" type, the biome's last Index card) is a rare roll instead of a
--.. daily fixture: every regular (non-sliced) roll has a 1-in-N chance of being it, N per biome
--.. below, one standing per biome at most (HasStandingTree). Its RAW weight is ignored. The other
--.. regular types share the remaining (1 - 1/N) by RAW weight. Sliced types fill the two fixed
--.. sliced slots of the morning and never roll here. Four regular rolls per biome per day, and
--.. the day's dice are shared, so a landmark day is the same day on every server.
local LANDMARK_ODDS = {Spawn = 100, Desert = 150, Samurai = 200, Farm = 250, Snow = 300, Underwater = 400, Volcano = 500, Narmek = 650, Toyland = 800, Neon = 1000}
local LANDMARK_ODDS_DEFAULT = 500
local function LandmarkOddsOf(zone)
	return LANDMARK_ODDS[zone] or LANDMARK_ODDS_DEFAULT
end

--.. "1 in Odds" per regular roll, stamped on every type def for the Index (Odds nil = a sliced or
--.. missing type: no chance shown); the landmark also gets Landmark = true (the gold card)
local function StampOdds(zone)
	local pool, total, landmark = {}, 0, nil
	for _, t in ipairs(EffectiveTypes(zone)) do
		t.Odds, t.Landmark = nil, nil
		if not t.Sliced and not t.Missing then
			if t.Tree then
				landmark = landmark or t
			else
				pool[#pool + 1] = t
				total += t.Weight
			end
		end
	end
	local rest = landmark and (1 - 1 / LandmarkOddsOf(zone)) or 1
	for _, t in ipairs(pool) do
		if total > 0 and t.Weight > 0 then t.Odds = total / (t.Weight * rest) end
	end
	if landmark then landmark.Odds, landmark.Landmark = LandmarkOddsOf(zone), true end
end
for _, zone in ipairs(ZONES) do StampOdds(zone) end

Adventure.SetCatalog(ZONES, EffectiveTypes)

local function SlicedTypeFor(zone)
	for _, t in ipairs(EffectiveTypes(zone)) do
		if t.Sliced and not t.Missing then return t end
	end
	return nil
end

local function TreeTypeFor(zone)
	for _, t in ipairs(EffectiveTypes(zone)) do
		if t.Tree and not t.Missing then return t end
	end
	return nil
end

local function HasStandingTree(zone)
	for holder, data in pairs(Live) do
		if data.Zone == zone and data.Type.Tree and holder.Parent then return true end
	end
	return false
end

local function PickType(zone)
	local pool, landmark = {}, nil
	for _, t in ipairs(EffectiveTypes(zone)) do
		if not t.Sliced and not t.Missing then
			if t.Tree then landmark = landmark or t else pool[#pool + 1] = t end
		end
	end
	--.. 2026-09-23: the landmark roll comes first (1 in LANDMARK_ODDS), never a second one while
	--.. one stands; everything else shares the rest by weight
	if landmark and not HasStandingTree(zone) and randint(1, LandmarkOddsOf(zone)) == 1 then return landmark end
	if #pool == 0 then return landmark end
	local total = 0
	for _, t in ipairs(pool) do total += t.Weight end
	local roll, counter = randint(1, total), 0
	for _, t in ipairs(pool) do
		counter += t.Weight
		if roll <= counter then return t end
	end
	return pool[1]
end

--..Spawn points..--
-- Measure horizontal separation so tall cucumbers cannot bypass the rule.
local function IsClearOfBreakables(zone, point, clearRadius)
 local myRadius=clearRadius or 0
 for _,holder in ipairs(ZoneFolders[zone]:GetChildren()) do
  local position,otherRadius
  if holder:IsA("Model") then
   position=holder:GetPivot().Position
   local size=holder:GetExtentsSize()
   otherRadius=math.max(size.X,size.Z)*.5
  elseif holder:IsA("BasePart") then
   position=holder.Position
   otherRadius=math.max(holder.Size.X,holder.Size.Z)*.5
  end
  if position then
   local difference=Vector3.new(point.X-position.X,0,point.Z-position.Z)
   local minimum=math.max(MIN_CUCUMBER_DISTANCE,myRadius+otherRadius)
   if difference.Magnitude<minimum then return false end
  end
 end
 return true
end

--.. anywhere = true (CucumberCarry drops / slips inside ANY biome, 2026-09-07): a preferred
--.. point outside the zone's field (or on an occupied spot) is used as is, rested on the
--.. ground under it -- no field bounds, no spacing check
--.. edgeInset (2026-09-08) pulls the sampling rectangle in by that many studs, so a giant's
--.. BODY stays inside the field instead of hanging over the biome boundary. nil for normal
--.. cucumbers, so their layouts are unchanged.
local function GetZonePoint(zone,index,clearRadius,preferredPoint,anywhere,edgeInset)
 local region=SpawnAreaFolder:FindFirstChild(tostring(index))
 if not (region and region:IsA("BasePart")) then
  warn(("[CucumberSpawner] workspace.SpawnArea.%d missing for %s"):format(index,zone))
  return nil
 end
 local halfX=math.max(0,region.Size.X*.5-SPAWN_AREA_PADDING)
 local halfZ=math.max(0,region.Size.Z*.5-SPAWN_AREA_PADDING)
 --.. a giant asks the sampling rectangle to pull in by its own half-extent so its BODY stays inside
 --.. the field. The fields are 120 x 44, so on the SHORT axis that would collapse the rectangle to
 --.. a single line and leave nowhere to dodge a neighbour: never take more of an axis than leaves
 --.. MIN_CUCUMBER_DISTANCE of play. A giant may then overhang a little; it will not lose its slot.
 if edgeInset and edgeInset>0 then
  halfX=math.max(halfX-edgeInset,math.min(halfX,MIN_CUCUMBER_DISTANCE))
  halfZ=math.max(halfZ-edgeInset,math.min(halfZ,MIN_CUCUMBER_DISTANCE))
 end
 local params=RaycastParams.new()
 params.FilterType=Enum.RaycastFilterType.Exclude
 params.RespectCanCollide=true
 local exclude={SpawnAreaFolder,Container}
 for _,player in ipairs(Players:GetPlayers()) do
  if player.Character then table.insert(exclude,player.Character) end
 end
 params.FilterDescendantsInstances=exclude

 local function tryLocalPoint(x,z)
  local point=region.CFrame:PointToWorldSpace(Vector3.new(x,region.Size.Y*.5,z))
  local hit=workspace:Raycast(point+Vector3.new(0,4,0),Vector3.new(0,-120,0),params)
  if hit then point=Vector3.new(point.X,hit.Position.Y,point.Z) end
  if IsClearOfBreakables(zone,point,clearRadius) then return point end
  return nil
 end

 -- Drops get the same validation as random spawns; an occupied drop moves to a free spot.
 if typeof(preferredPoint)=="Vector3" then
  local relative=region.CFrame:PointToObjectSpace(preferredPoint)
  if math.abs(relative.X)<=halfX and math.abs(relative.Z)<=halfZ then
   local point=tryLocalPoint(relative.X,relative.Z)
   if point then return point end
  end
  if anywhere then
   local hit=workspace:Raycast(preferredPoint+Vector3.new(0,4,0),Vector3.new(0,-120,0),params)
   return hit and Vector3.new(preferredPoint.X,hit.Position.Y,preferredPoint.Z) or preferredPoint
  end
 end
 for _=1,100 do
  local point=tryLocalPoint(rand()*halfX*2-halfX,rand()*halfZ*2-halfZ)
  if point then return point end
 end
 -- Deterministic search if random attempts are unlucky. Never return an invalid position.
 for x=-halfX,halfX,MIN_CUCUMBER_DISTANCE*.5 do
  for z=-halfZ,halfZ,MIN_CUCUMBER_DISTANCE*.5 do
   local point=tryLocalPoint(x,z)
   if point then return point end
  end
 end
 warn("[CucumberSpawner] No safely spaced spawn position in "..zone)
 return nil
end

--..Visual builders (verbatim from the live game)..--
local function ApplyGoldenLook(holder)
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Shadow" then
			d.Color = GOLDEN_COLOR
			if d.Name ~= "Hitbox" then d.Material = Enum.Material.Foil end
		end
	end
	if holder:IsA("BasePart") then holder.Color = GOLDEN_COLOR end
end

--..Materials + mutations (CucumberMutations, 2026-09-06)..--
local function ApplyDiamondLook(holder)
	local color = CucumberMutations.MATERIALS.Diamond.Color
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Shadow" then
			d.Color = color
			if d.Name ~= "Hitbox" then d.Material = Enum.Material.Glass end
		end
	end
	if holder:IsA("BasePart") then holder.Color = color holder.Material = Enum.Material.Glass end
	local root = holder:IsA("BasePart") and holder or holder.PrimaryPart or holder:FindFirstChildWhichIsA("BasePart", true)
	if root and not root:FindFirstChild("DiamondSparkle") then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "DiamondSparkle"
		sparkle.Color = ColorSequence.new(Color3.fromRGB(230, 250, 255))
		sparkle.LightEmission = 1
		sparkle.Rate = 6
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0)})
		sparkle.Parent = root
		local glow = Instance.new("PointLight")
		glow.Name = "DiamondLight"
		glow.Color = color
		glow.Range = 12
		glow.Brightness = 0.9
		glow.Parent = root
	end
end

--.. material look (Diamond; Golden is handled by BuildCucumber / ApplyGoldenLook) + one
--.. colour-coded particle emitter per mutation, the first mutation tints the body when
--.. there is no material, PRISMATIC cycles the rainbow
local function ApplyModifierLooks(holder, material, mutations, sizeScale)
	mutations = mutations or {}
	sizeScale = math.clamp(tonumber(sizeScale) or 1, 1, 4)
	local root = holder:IsA("BasePart") and holder or holder.PrimaryPart or holder:FindFirstChildWhichIsA("BasePart", true)
	if not root then return end
	if material == "Diamond" then ApplyDiamondLook(holder) end
	local first = mutations[1] and CucumberMutations.Get(mutations[1])
	if first and not material then
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Shadow" and d.Name ~= "Hitbox" then d.Color = first.Color end
		end
		if holder:IsA("BasePart") then holder.Color = first.Color end
	end
	for _, name in ipairs(mutations) do
		local m = CucumberMutations.Get(name)
		if m then
			local e = Instance.new("ParticleEmitter")
			e.Name = "Mutation_" .. name
			e.Color = ColorSequence.new(m.Color)
			e.LightEmission = 0.8
			e.Rate = 5
			e.Lifetime = NumberRange.new(0.9, 1.6)
			e.Speed = NumberRange.new(0.6, 1.8)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0)})
			e.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
			e.Parent = root
		end
	end
	if first and not root:FindFirstChildOfClass("PointLight") then
		local light = Instance.new("PointLight")
		light.Name = "MutationLight"
		light.Color = first.Color
		light.Range = 12
		light.Brightness = 0.9
		light.Parent = root
	end
	--.. Model:ScaleTo scales neither emitters nor lights, so a giant's sparkles would be pinpricks
	--.. and its glow would not reach its own ends: grow every look this pass just added (2026-09-08)
	if sizeScale > 1 then
		for _, d in ipairs(root:GetChildren()) do
			if d:IsA("ParticleEmitter") then
				local keys = {}
				for _, k in ipairs(d.Size.Keypoints) do keys[#keys + 1] = NumberSequenceKeypoint.new(k.Time, k.Value * sizeScale) end
				d.Size = NumberSequence.new(keys)
				d.Rate *= sizeScale
			elseif d:IsA("PointLight") then
				d.Range = math.min(d.Range * sizeScale, 40)
			end
		end
	end
	if table.find(mutations, "PRISMATIC") then
		task.spawn(function()
			local parts = {}
			for _, d in ipairs(holder:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "Shadow" and d.Name ~= "Hitbox" then parts[#parts + 1] = d end
			end
			if holder:IsA("BasePart") then parts[#parts + 1] = holder end
			local t = 0
			while holder.Parent do
				t += 0.15
				local c = Color3.fromHSV((t * 0.12) % 1, 0.65, 1)
				for _, p in ipairs(parts) do if p.Parent then p.Color = c end end
				task.wait(0.15)
			end
		end)
	end
end

--.. "NEON + FROZEN Golden Vined Cucumber spawned in Desert!" for every client (fresh
--.. rolls only -- a re-planted drop is not news, unless the dev hook asks)
local function AnnounceSpawn(holder, zone, typeDef, material, mutations, fixed, sizeTier)
	--.. mutated cucumbers are always news; among giants only the rare tiers are (a HUGE turns up
	--.. often enough that a chat line for every one would just be noise)
	if (not mutations or #mutations == 0) and not CucumberMutations.ShouldAnnounce(sizeTier) then return end
	if fixed and not fixed.Announce then return end
	AnnounceRemote:FireAllClients({Zone = zone, TypeName = typeDef.Name, Material = material, Mutations = CucumberMutations.Join(mutations or {}), Size = sizeTier, Name = holder.Name})
end

local function AddShadow(part, diameter, groundY)
	local shadow = Instance.new("Part")
	shadow.Name = "Shadow"
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Size = Vector3.new(0.08, diameter, diameter)
	shadow.Color = Color3.fromRGB(20, 30, 15)
	shadow.Transparency = 0.74
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CFrame = CFrame.new(part.Position.X, groundY + 0.06, part.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	shadow.Parent = part
end

local function BuildCucumber(zoneColor, scale, golden, overrideColor, overrideMaterial, glowColor)
	local dia, len = 0.78 * scale, 2.35 * scale
	local h, s, v = (overrideColor or zoneColor):ToHSV()
	local bodyColor = golden and Color3.fromRGB(255, 200, 30) or Color3.fromHSV(h, math.clamp(s * 1.1, 0, 1), math.clamp(v * (0.9 + rand() * 0.25), 0, 1))
	local ridgeColor = golden and Color3.fromRGB(255, 224, 96) or Color3.fromHSV(h, math.clamp(s * 0.72, 0, 1), math.clamp(v * 1.25, 0, 1))
	local material = golden and Enum.Material.Foil or (overrideMaterial or Enum.Material.SmoothPlastic)

	local body = Instance.new("Part")
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(len, dia, dia)
	body.Color = bodyColor
	body.Material = material
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = true
	body.CastShadow = true

	local function weldTo(inst)
		inst.Anchored = false
		inst.CanCollide = false
		inst.CanTouch = false
		inst.CanQuery = true
		inst.CastShadow = true
		inst.Parent = body
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = inst
		w.Parent = inst
	end

	for side = -1, 1, 2 do
		local cap = Instance.new("Part")
		cap.Name = "Cap"
		cap.Shape = Enum.PartType.Ball
		cap.Size = Vector3.new(dia * 0.96, dia * 0.96, dia * 0.96)
		cap.Color = bodyColor
		cap.Material = material
		cap.CFrame = body.CFrame * CFrame.new(side * len / 2 * 0.94, 0, 0)
		weldTo(cap)
	end
	for i = 0, 5 do
		local theta = math.rad(i * 60 + 30)
		local ridge = Instance.new("Part")
		ridge.Name = "Ridge"
		ridge.Size = Vector3.new(len * 0.62, dia * 0.07, dia * 0.2)
		ridge.Color = ridgeColor
		ridge.Material = material
		ridge.CFrame = body.CFrame * CFrame.Angles(theta, 0, 0) * CFrame.new(0, dia * 0.485, 0)
		weldTo(ridge)
	end
	local stem = Instance.new("Part")
	stem.Name = "Stem"
	stem.Shape = Enum.PartType.Cylinder
	stem.Size = Vector3.new(dia * 0.4, dia * 0.22, dia * 0.22)
	stem.Color = Color3.fromRGB(94, 92, 44)
	stem.Material = Enum.Material.SmoothPlastic
	stem.CFrame = body.CFrame * CFrame.new(len / 2 * 1.02, dia * 0.05, 0)
	weldTo(stem)
	for i = 1, 3 do
		local curl = Instance.new("Part")
		curl.Name = "Vine"
		curl.Shape = Enum.PartType.Ball
		local cs = dia * (0.18 - i * 0.035)
		curl.Size = Vector3.new(cs, cs, cs)
		curl.Color = Color3.fromRGB(70, 140, 52)
		curl.Material = Enum.Material.SmoothPlastic
		curl.CFrame = body.CFrame * CFrame.new(len / 2 * 1.02 + dia * 0.1 * i, dia * (0.1 + 0.16 * i), dia * 0.08 * i * (i % 2 == 0 and 1 or -1))
		weldTo(curl)
	end
	local leaf = Instance.new("Part")
	leaf.Name = "Leaf"
	leaf.Shape = Enum.PartType.Ball
	leaf.Size = Vector3.new(dia * 0.7, dia * 0.16, dia * 0.5)
	leaf.Color = Color3.fromRGB(52, 118, 40)
	leaf.Material = Enum.Material.Grass
	leaf.CFrame = body.CFrame * CFrame.new(len / 2 * 0.86, dia * 0.5, 0) * CFrame.Angles(0, 0, math.rad(-18))
	weldTo(leaf)

	if golden then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "GoldSparkle"
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90))
		sparkle.LightEmission = 1
		sparkle.Rate = 4
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0)})
		sparkle.Parent = body
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 214, 90)
		glow.Range = 12
		glow.Brightness = 0.8
		glow.Parent = body
	end
	if glowColor then
		local glow = Instance.new("PointLight")
		glow.Color = glowColor
		glow.Range = 13
		glow.Brightness = 1.1
		glow.Parent = body
	end
	return body
end

local function BuildSlice(scale)
	scale = scale or 1 -- giants (CucumberMutations.SIZES) grow the whole disc
	--.. layered cucumber slice: dark-green rind, pale flesh and five visible seeds
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.42, 2.5, 2.5) * scale
	part.Color = Color3.fromRGB(72, 132, 60)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = true
	local function weldSliceDetail(detail)
		detail.Anchored = false
		detail.CanCollide = false
		detail.CanTouch = false
		detail.CanQuery = false
		detail.CastShadow = true
		detail.Parent = part
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = detail
		weld.Parent = detail
	end
	local flesh = Instance.new("Part")
	flesh.Name = "Flesh"
	flesh.Shape = Enum.PartType.Cylinder
	flesh.Size = Vector3.new(0.46, 2.08, 2.08) * scale
	flesh.Color = Color3.fromRGB(190, 224, 132)
	flesh.Material = Enum.Material.SmoothPlastic
	flesh.CFrame = part.CFrame
	weldSliceDetail(flesh)
	local seedPositions = {Vector2.new(0, 0.06), Vector2.new(0.38, 0.28), Vector2.new(-0.38, 0.28), Vector2.new(0.3, -0.38), Vector2.new(-0.3, -0.38)}
	for index, offset in ipairs(seedPositions) do
		local seed = Instance.new("Part")
		seed.Name = "Seed"
		seed.Shape = Enum.PartType.Ball
		seed.Size = Vector3.new(0.11, 0.2, 0.46) * scale
		seed.Color = Color3.fromRGB(244, 238, 176)
		seed.Material = Enum.Material.SmoothPlastic
		seed.CFrame = part.CFrame * CFrame.new(Vector3.new(0.27, offset.X, offset.Y) * scale) * CFrame.Angles(math.rad(12), 0, math.rad((index - 3) * 12))
		weldSliceDetail(seed)
	end
	return part
end

--..Flat slices..--
--.. The hand-modelled slice discs (Spawn / Desert / Samurai Sliced Cucumber, Sun-Dried Slice,
--.. Moon Slice, Planet Slice) are authored standing on their edge: thin along the model's Z with
--.. the seed face toward +Z. User (2026-09-06): they lie flat instead. FLAT_ROTATION turns the
--.. model's +Z (seed face) up; LayFlatIfDisc measures the disc (Shadow excluded) and answers
--.. {Size = flat extents, Lift = pivot height over the lowest point} or nil for anything that is
--.. not a standing disc (Slice Stack, Frozen Slice cube, Molten Slice already lies flat, ...).
local FLAT_ROTATION = CFrame.Angles(math.rad(-90), 0, 0)
local DISC_THIN_RATIO = 0.45 -- Z extent under this fraction of the face extents = a standing disc

local function ExtentsWithoutShadow(model)
	local minV, maxV
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Shadow" then
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
	end
	if not minV then return nil end
	return maxV - minV, minV, maxV
end

local function LayFlatIfDisc(model, typeDef)
	if not (typeDef.Sliced or string.find(typeDef.Name, "Slice", 1, true)) then return nil end
	local size = ExtentsWithoutShadow(model)
	if not size or size.Z >= DISC_THIN_RATIO * math.min(size.X, size.Y) then return nil end
	local pivot = model:GetPivot()
	model:PivotTo(pivot * FLAT_ROTATION)
	local flatSize, minV = ExtentsWithoutShadow(model)
	return {Size = flatSize, Lift = pivot.Position.Y - minV.Y + 0.02}
end

--.. the template's shadow was drawn under the standing disc: lay it under the flat one
local function FlattenShadow(model, groundY, size)
	local shadow = model:FindFirstChild("Shadow", true)
	if not (shadow and shadow:IsA("BasePart")) then return end
	local d = math.max(size.X, size.Z) * 0.92
	shadow.Size = Vector3.new(0.08, d, d)
	local pivot = model:GetPivot()
	shadow.CFrame = CFrame.new(pivot.Position.X, groundY + 0.04, pivot.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
end

--..Spawning..--
--.. fixed = {Type = typeDef, Golden = bool, Point = Vector3?, SizeTier = string?}: re-plant a
--.. SPECIFIC cucumber (CucumberCarry drops / slips) instead of rolling one, at the size it already
--.. had; nil Point = fresh field spot. sizeTier = the giant tier BeginDay picked for this slot.
local function SpawnBreakable(zone, forceSliced, fixed, mutate, sizeTier)
	if not FieldsOpen and not (fixed and fixed.Force == true) then return nil end -- Force: BaseSaveService restoring a plot, night included
	local index = table.find(ZONES, zone)
	local typeDef = (fixed and fixed.Type) or (forceSliced and SlicedTypeFor(zone) or PickType(zone))
	if not typeDef then return end
	--.. 2026-09-23: no forced daily tree any more -- the landmark is PickType's rare 1-in-N roll
	--.. material (Golden / Diamond, one at most) on every fresh roll; 1..4 stacking mutations only on
	--.. the cucumbers BeginDay picked for the day (mutate = true, MUTATED_PER_DAY); a re-plant keeps
	--.. what the cucumber already had
	local material, mutations
	if fixed then
		material = fixed.Material or (fixed.Golden == true and "Golden" or nil)
		mutations = CucumberMutations.Parse(fixed.Mutations)
	else
		material = CucumberMutations.RollMaterial(rand)
		mutations = mutate and CucumberMutations.RollMutations(rand, CucumberMutations.RollCountAtLeastOne(rand)) or {}
	end
	--.. size: a re-plant keeps what it already had, a fresh spawn takes the day's giant slot
	if fixed then sizeTier = fixed.SizeTier end
	if sizeTier and not CucumberMutations.GetSize(sizeTier) then sizeTier = nil end
	local sizeScale = CucumberMutations.ScaleOf(sizeTier) -- 1 unless this one is a giant
	local weightScale = CucumberLift.WeightScale(zone, typeDef.Name, material, mutations) -- heavier types / biomes are slightly bigger (2026-09-17, user)
	local golden = material == "Golden"
	local displayName = CucumberMutations.DisplayName(typeDef.Name, material, mutations, sizeTier)
	local fixedPoint = fixed and fixed.Point or nil
	local anywhere = fixed and fixed.Anywhere == true or false

	if typeDef.Template then
		local tpl = Templates:FindFirstChild(typeDef.Template)
		if not tpl then
			warn("[CucumberSpawner] missing template " .. typeDef.Template)
			return
		end
		local model = tpl:Clone()
		model.Name = displayName
		model:ScaleTo(model:GetScale() * TEMPLATE_SCALE * sizeScale * weightScale)
		local flat = LayFlatIfDisc(model, typeDef) -- edge-standing slice discs lie flat, seeds up
		local ext = flat and flat.Size or model:GetExtentsSize()
		--.. a giant is kept clear of the field edge AND of its neighbours, both of which the
		--.. field may simply be too small for: rather than lose the slot for the whole day, fall
		--.. back to the room a normal one of its type would ask for
		local radius = math.max(ext.X, ext.Z) * 0.5
		local point = GetZonePoint(zone, index, radius, fixedPoint, anywhere, sizeScale > 1 and radius or nil)
		--.. nowhere with BOTH the edge inset and its full spacing: give up the inset first (it only
		--.. costs a little overhang) and the spacing only as a last resort (it costs an overlap) --
		--.. either beats losing the slot for the whole day
		if not point and sizeScale * weightScale > 1 then point = GetZonePoint(zone, index, radius, fixedPoint, anywhere) end
		if not point and sizeScale * weightScale > 1 then point = GetZonePoint(zone, index, radius / (sizeScale * weightScale), fixedPoint, anywhere) end
		if not point then model:Destroy() return end
		local yaw = CFrame.Angles(0, math.rad(randint(-180, 180)), 0)
		if flat then
			model:PivotTo(CFrame.new(point + Vector3.new(0, flat.Lift, 0)) * yaw * FLAT_ROTATION)
			FlattenShadow(model, point.Y, flat.Size)
		else
			model:PivotTo(CFrame.new(point + Vector3.new(0, ext.Y / 2, 0)) * yaw)
		end
		if golden then ApplyGoldenLook(model) end
		Register(model, zone, typeDef, golden, material, mutations, sizeTier)
		ApplyModifierLooks(model, material, mutations, sizeScale)
		Adventure.Decorate(model, fixed, rand)
		model.Parent = ZoneFolders[zone]
		AnnounceSpawn(model, zone, typeDef, material, mutations, fixed, sizeTier)
		return model
	end

	local part
	if typeDef.Sliced then
		part = BuildSlice(sizeScale * weightScale)
		if golden then ApplyGoldenLook(part) end
	else
		part = BuildCucumber(ZONE_COLOR[zone] or Color3.fromRGB(62, 128, 38), typeDef.Scale * TEMPLATE_SCALE * sizeScale * weightScale, golden, nil, ZONE_MATERIAL[zone], ZONE_GLOW[zone])
	end
	part.Name = displayName
	local radius = math.max(part.Size.X, part.Size.Z) * 0.5
	local point = GetZonePoint(zone, index, radius, fixedPoint, anywhere, sizeScale > 1 and radius or nil)
	if not point and sizeScale > 1 then point = GetZonePoint(zone, index, radius, fixedPoint, anywhere) end
	if not point and sizeScale > 1 then point = GetZonePoint(zone, index, radius / sizeScale, fixedPoint, anywhere) end
	if not point then part:Destroy() return end
	local newRoot
	if typeDef.Sliced then
		--.. lie mostly flat (cylinder axis X tipped 75 degrees toward vertical); 0.53 = lowest point of the tipped disc
		newRoot = CFrame.new(point + Vector3.new(0, 0.53 * sizeScale, 0)) * CFrame.fromEulerAnglesXYZ(0, math.rad(randint(-180, 180)), math.rad(75))
	else
		--.. rest the body ON the ground: lowest point of the 8-degree tipped cylinder
		local tilt = math.rad(8)
		local lift = part.Size.Y * 0.5 * math.cos(tilt) + part.Size.X * 0.5 * math.sin(tilt) + 0.05
		newRoot = CFrame.new(point + Vector3.new(0, lift, 0)) * CFrame.fromEulerAnglesXYZ(0, math.rad(randint(-180, 180)), tilt)
	end
	part.CFrame = newRoot
	for _, c in ipairs(part:GetChildren()) do -- fresh builds hold origin-space offsets
		if c:IsA("BasePart") then c.CFrame = newRoot * c.CFrame end
	end
	AddShadow(part, typeDef.Sliced and 3.2 * sizeScale or part.Size.X * 0.72, point.Y)
	Register(part, zone, typeDef, golden, material, mutations, sizeTier)
	ApplyModifierLooks(part, material, mutations, sizeScale)
	Adventure.Decorate(part, fixed, rand)
	part.Parent = ZoneFolders[zone]
	AnnounceSpawn(part, zone, typeDef, material, mutations, fixed, sizeTier)
	return part
end

--..Server API for CucumberCarry (BindableFunctions in ServerStorage.CucumberSpawnerAPI)..--
local API = ServerStorage:FindFirstChild("CucumberSpawnerAPI")
if not API then
	API = Instance.new("Folder")
	API.Name = "CucumberSpawnerAPI"
	API.Parent = ServerStorage
end
local function bindable(name, fn)
	local b = API:FindFirstChild(name)
	if not b then
		b = Instance.new("BindableFunction")
		b.Name = name
		b.Parent = API
	end
	b.OnInvoke = fn
	return b
end
local function TypeByName(zone, typeName)
	for _, t in ipairs(EffectiveTypes(zone)) do
		if t.Name == typeName then return t end
	end
	--.. a name this zone no longer has (a pre-2026-09-18 Toyland / Neon plot save): its replacement.
	--.. The holder then carries the NEW TypeName, which is how CucumberCarry.RestorePlaced spots it
	local renamed = LEGACY_TYPES[zone] and LEGACY_TYPES[zone][typeName]
	if renamed then
		for _, t in ipairs(EffectiveTypes(zone)) do
			if t.Name == renamed and not t.Missing then return t end
		end
	end
	return nil
end
--.. SpawnCarried(zone, typeName, golden, point?, extra?) -> holder: put a specific cucumber
--.. back into the world (at point, or a fresh random spot in its field when nil). extra =
--.. {Material, Mutations, Anywhere}: Anywhere keeps the point even outside the zone's field
--.. (drops / slips in another biome, 2026-09-07); without it an out-of-field point is
--.. ignored and the cucumber lands on a fresh field spot. SizeTier keeps a giant giant
--.. (2026-09-08) -- a dropped COLOSSAL is still COLOSSAL when it hits the ground.
bindable("SpawnCarried", function(zone, typeName, golden, point, extra)
	--.. Force (BaseSaveService restoring a saved plot, 2026-09-12): spawn even while the fields are closed for
	--.. the night or the biome is full - the copy is taken off the field again at once
	local ex = type(extra) == "table" and extra or {}
	local force = ex.Force == true
	if (not FieldsOpen and not force) or not table.find(ZONES, zone) then return nil end
	if not force then
		local sliced, other = CountZonePopulation(zone)
		if sliced + other >= CUCUMBERS_PER_BIOME then return nil end
	end
	local typeDef = TypeByName(zone, typeName)
	if not typeDef then return nil end
	return SpawnBreakable(zone, false, {Type = typeDef, Golden = golden == true, Point = typeof(point) == "Vector3" and point or nil, Material = ex.Material, Mutations = ex.Mutations, Anywhere = ex.Anywhere == true, Force = force, SizeTier = ex.SizeTier, Trait=ex.Trait, JourneyId=ex.JourneyId, Recorded=ex.Recorded, RecordedBy=ex.RecordedBy, RecoveryUsed=ex.RecoveryUsed, Rescues=ex.Rescues})
end)
--.. InField(zone, position) -> bool: is that position inside the biome's cucumber field
bindable("InField", function(zone, position)
	local index = table.find(ZONES, zone)
	local region = index and SpawnAreaFolder:FindFirstChild(tostring(index))
	if not (region and region:IsA("BasePart")) or typeof(position) ~= "Vector3" then return false end
	local lp = region.CFrame:PointToObjectSpace(position)
	return math.abs(lp.X) <= region.Size.X * 0.5 + 6 and math.abs(lp.Z) <= region.Size.Z * 0.5 + 6 and lp.Y >= -12 and lp.Y <= 60
end)
bindable("Zones", function() return table.clone(ZONES) end)
--.. 2026-09-23 (items): a random non-sliced type name of the zone (the Golden / Void Seed items plant one)
bindable("PickTypeName", function(zone)
	if not table.find(ZONES, zone) then return nil end
	local t = PickType(zone)
	return t and t.Name or nil
end)

--.. index of the biome whose slab the position is on, or nil while outside every biome
local function SlabIndexAt(position)
	local zones = workspace:FindFirstChild("Zones")
	local zoneParts = zones and zones:FindFirstChild("ZoneParts")
	for index, zone in ipairs(ZONES) do
		local slab = zoneParts and zoneParts:FindFirstChild(zone)
		local halfX, halfZ
		if slab and slab:IsA("BasePart") then
			halfX, halfZ = slab.Size.X * 0.5, slab.Size.Z * 0.5
		else
			slab = SpawnAreaFolder:FindFirstChild(tostring(index))
			halfX, halfZ = SLAB_HALF_X, SLAB_HALF_Z
		end
		if slab and slab:IsA("BasePart") then
			local lp = slab.CFrame:PointToObjectSpace(position)
			if math.abs(lp.X) <= halfX + SLAB_MARGIN and math.abs(lp.Z) <= halfZ + SLAB_MARGIN and lp.Y >= -15 and lp.Y <= 150 then
				return index
			end
		end
	end
	return nil
end

local function NearestIndex(position)
	local best, bestDistance = nil, math.huge
	for index in ipairs(ZONES) do
		local region = SpawnAreaFolder:FindFirstChild(tostring(index))
		if region and region:IsA("BasePart") then
			local d = (Vector2.new(position.X, position.Z) - Vector2.new(region.Position.X, region.Position.Z)).Magnitude
			if d < bestDistance then bestDistance, best = d, index end
		end
	end
	return best
end

local function ActiveZones()
	local active = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			--.. standing inside a biome commits to it; outside every biome the previous commitment holds
			local anchorIndex = SlabIndexAt(root.Position)
			if anchorIndex then
				LastInhabitedIndex[player] = anchorIndex
			else
				anchorIndex = LastInhabitedIndex[player] or NearestIndex(root.Position)
			end
			--.. replicated anchor: DeviceStreamingServer's neighbour stream-in and the
			--.. client culling (CucumberStreamClient) key off this
			if anchorIndex and player:GetAttribute("BiomeIndex") ~= anchorIndex then
				player:SetAttribute("BiomeIndex", anchorIndex)
			end
			--.. populate the current area and its immediate neighbours before the player enters
			if anchorIndex then
				for index = math.max(1, anchorIndex - 1), math.min(#ZONES, anchorIndex + 1) do
					active[ZONES[index]] = true
				end
			end
		end
	end
	--.. hysteresis: a biome stays warm for ZONE_UNLOAD_GRACE after its last player leaves
	local now = os.clock()
	for _, zone in ipairs(ZONES) do
		if active[zone] then
			LastActiveAt[zone] = now
		elseif LastActiveAt[zone] and now - LastActiveAt[zone] <= ZONE_UNLOAD_GRACE then
			active[zone] = true
		end
	end
	return active
end


-- Only field holders are cleared. Shoulder and plot cucumbers are outside these folders.
local function ClearFields()
 FieldsOpen = false
 for _, folder in pairs(ZoneFolders) do folder:ClearAllChildren() end
 table.clear(Live)
 table.clear(Population)
 for _, folder in pairs(ZoneFolders) do
  folder:SetAttribute("Sliced", 0)
  folder:SetAttribute("Other", 0)
  folder:SetAttribute("Active", false)
 end
end

bindable("BeginNight", function()
 ClearFields()
 return true
end)

--.. 0..4 mutated cucumbers for the whole day, MUTATED_PER_DAY weighted (rolled with the day's dice)
local function RollMutatedPerDay()
	local total = 0
	for count = 0, 4 do total += MUTATED_PER_DAY[count] or 0 end
	local r = rand() * total
	for count = 0, 4 do
		r -= MUTATED_PER_DAY[count] or 0
		if r < 0 then return count end
	end
	return 0
end

bindable("BeginDay", function(dayNumber)
 ClearFields()
 CurrentDay = dayNumber
 FieldsOpen = true
 --.. same dice on every server: the shared day number seeds them (DayNightCycle)
 local seed = math.floor(tonumber(dayNumber) or 0)
 Rng = Random.new(seed)
 --.. which 0..4 of the day's cucumbers (all biomes together, slot = zone x 6 + n) are mutated
 local slots = #ZONES * CUCUMBERS_PER_BIOME
 local mutatedSlots, wanted, picked = {}, RollMutatedPerDay(), 0
 while picked < math.min(wanted, slots) do
  local i = Rng:NextInteger(1, slots)
  if not mutatedSlots[i] then mutatedSlots[i] = true picked += 1 end
 end
 --.. and which of them are GIANTS (2026-09-08): every slot rolls CucumberMutations.GIANT_CHANCE
 --.. (5 %), so a 60-cucumber reset grows ~3 somewhere across the ten biomes; the SIZES weights
 --.. decide how big each one is (HUGE x2 mostly, MASSIVE x3 a treat, COLOSSAL x4 the chase) and
 --.. the per-tier Cap keeps a reset from ever fielding a crowd of quadruples -- an over-cap roll
 --.. steps DOWN a tier. Rolled with the day's dice, so every server grows the same giants in the
 --.. same spots. In Studio, script:SetAttribute("ForceGiant", true) puts one in every biome.
 local giantSlots, giantCounts = {}, {}
 local forceGiant = game:GetService("RunService"):IsStudio() and script:GetAttribute("ForceGiant") == true
 for slot = 1, slots do
  if CucumberMutations.RollGiant(rand) or (forceGiant and slot % CUCUMBERS_PER_BIOME == 3) then
   local size = CucumberMutations.RollSize(rand)
   while size and (giantCounts[size] or 0) >= CucumberMutations.CapOf(size) do
    size = CucumberMutations.DemoteSize(size)
   end
   if size then
    giantSlots[slot] = size
    giantCounts[size] = (giantCounts[size] or 0) + 1
   end
  end
 end
 local total, mutated, giants = 0, 0, 0
 for zoneIndex, zone in ipairs(ZONES) do
  for slot = 1, CUCUMBERS_PER_BIOME do
   local slotIndex = (zoneIndex - 1) * CUCUMBERS_PER_BIOME + slot
   local holder = SpawnBreakable(zone, slot <= SLICED_PER_BIOME, nil, mutatedSlots[slotIndex] == true, giantSlots[slotIndex])
   if not holder then
    --.. never let one bad slot kill the day (this runs inside DayNightCycle's loop)
    warn(("[CucumberSpawner] could not spawn morning cucumber %d in %s"):format(slot, zone))
   else
    total += 1
    if holder:GetAttribute("Mutations") ~= "" then mutated += 1 end
    if holder:GetAttribute("SizeTier") then giants += 1 end
   end
  end
  local sliced, other = CountZonePopulation(zone)
  ZoneFolders[zone]:SetAttribute("Sliced", sliced)
  ZoneFolders[zone]:SetAttribute("Other", other)
  ZoneFolders[zone]:SetAttribute("Active", true)
 end
 Rng = nil
 print(("[CucumberSpawner] Day %d: %d cucumbers, %d per biome, %d mutated, %d giant (seed %d)"):format(CurrentDay, total, CUCUMBERS_PER_BIOME, mutated, giants, seed))
 return total
end)

Players.PlayerRemoving:Connect(function(player)
 LastInhabitedIndex[player] = nil
end)

-- Keep streaming's BiomeIndex current without replenishing or pruning fields.
task.spawn(function()
 while true do
  ActiveZones()
  for zone, folder in pairs(ZoneFolders) do
   local sliced, other = CountZonePopulation(zone)
   folder:SetAttribute("Sliced", sliced)
   folder:SetAttribute("Other", other)
  end
  task.wait(POPULATION_PLAN_TICK)
 end
end)
--..Studio dev hook: workspace:SetAttribute("MutationDev", "<zone>:<MUT1,MUT2>:<Golden|Diamond|->") spawns one in front of the first player..--
if game:GetService("RunService"):IsStudio() then
	workspace:GetAttributeChangedSignal("MutationDev"):Connect(function()
		local cmd = workspace:GetAttribute("MutationDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		workspace:SetAttribute("MutationDev", nil)
		local zone, muts, mat = cmd:match("^([^:]+):([^:]*):?(.*)$")
		if not (zone and table.find(ZONES, zone)) then return end
		local player = Players:GetPlayers()[1]
		local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local typeDef
		for _, t in ipairs(EffectiveTypes(zone)) do
			if not t.Sliced and not t.Tree and not t.Missing then typeDef = t break end
		end
		if not typeDef then return end
		local holder = SpawnBreakable(zone, false, {Type = typeDef, Material = (mat ~= "" and mat ~= "-") and mat or nil, Mutations = CucumberMutations.Parse(muts), Point = root and (root.Position + root.CFrame.LookVector * 6) or nil, Announce = true})
		print("[CucumberSpawner] MutationDev -> " .. tostring(holder and holder:GetFullName()))
	end)
end
--..Studio dev hook: workspace:SetAttribute("GiantDev", "<zone>:<HUGE|MASSIVE|COLOSSAL>") grows one
--..giant right in front of the first player (the size defaults to COLOSSAL)..--
if game:GetService("RunService"):IsStudio() then
	workspace:GetAttributeChangedSignal("GiantDev"):Connect(function()
		local cmd = workspace:GetAttribute("GiantDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		workspace:SetAttribute("GiantDev", nil)
		local zone, size = cmd:match("^([^:]+):?(.*)$")
		if not (zone and table.find(ZONES, zone)) then return end
		if not CucumberMutations.GetSize(size) then size = "COLOSSAL" end
		local player = Players:GetPlayers()[1]
		local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local typeDef
		for _, t in ipairs(EffectiveTypes(zone)) do
			if not t.Sliced and not t.Tree and not t.Missing then typeDef = t break end
		end
		if not typeDef then return end
		local holder = SpawnBreakable(zone, false, {Type = typeDef, SizeTier = size, Point = root and (root.Position + root.CFrame.LookVector * 16) or nil, Anywhere = true, Announce = true})
		print(("[CucumberSpawner] GiantDev %s -> %s"):format(size, tostring(holder and holder:GetFullName())))
	end)
end
API:SetAttribute("Ready", true)

