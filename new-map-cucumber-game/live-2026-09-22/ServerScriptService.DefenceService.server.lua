--[[
	DefenceService  (Script, ServerScriptService)  2026-09-10, set 2 added 2026-09-16
	Makes the Defences builds work against the night raid. Every placed build (tag "PlacedBuild",
	attribute BuildKey) of these kinds is registered when it appears in a plot's Placed folder and
	forgotten when it goes (sold, moved = re-based, smashed):

	  Turret      parts Head* yaw about the vertical axis through BasePlinth, Barrel* pitch about the
	              HeadTrunnion (the Blender rig data of defenses/build_turret.py). Tracks the nearest
	              zombie within RANGE, turns at TURN_RATE, and once on target fires every INTERVAL: a
	              neon tracer + muzzle flash from the alternating muzzle of BarrelMuzzleGlow, DAMAGE
	              through ServerStorage.ZombieAPI.Damage. Eases back to rest when nothing is in range.
	  SpikeTrap   the Spikes* parts stop colliding so zombies walk onto the bed; any zombie standing
	              inside the 8 x 8 plate takes DAMAGE every INTERVAL and is slowed (ZombieAPI.Slow).
	  Catapult    the Arm* parts swing about ArmPivot (0, 2.30, 1.30) in the prop's own frame (derived
	              from the Wheels part), a boulder flies a parabola to the target zombie's predicted
	              position in FLIGHT seconds and lands with RADIUS splash damage.

	SET 2 (2026-09-16, defenses/BRIEF-2026-09-16.md: Blender props with Pivot_* attributes on the
	SOURCE model in ServerStorage.Builds.Defences - the placeable template drops them, so a defence
	reads its rig from the source, and its authored origin from the Hitbox: origin = Hitbox.CFrame x
	(-source bounding-box centre)):
	  Mortar      Mount* yaws toward the target (an aim cone like the turret's), Tube* keeps its built
	              55-degree elevation. Every INTERVAL a shell leaves MuzzleTip on a HIGH arc (FLIGHT s)
	              to the target's predicted spot and bursts: RADIUS splash, full damage at the centre,
	              half at the edge. Slow, long range, never closer than MinRange.
	  TeslaCoil   every INTERVAL: the nearest zombie in RANGE is zapped, then the bolt CHAINS to the
	              nearest not-yet-hit zombie within CHAIN_RANGE of the last, up to CHAIN hops, each hop
	              worth CHAIN_FALLOFF of the one before. Jagged neon bolts OrbCentre -> zombie ->
	              zombie, a flash, "Zap". Idle arcs orb -> prong tips; the orb turns.
	  FreezeTower every TICK every zombie within RADIUS (flat, from the tower) is slowed for SLOW_FOR s
	              (ZombieAPI.Slow keeps it slowed as long as it stays inside) and chilled for CHILL
	              damage; frost puffs on the zombie, snow off the orb (the translucent aura disc on the
	              ground is OFF since 2026-09-18 -- FROST.ShowAura -- user: "get rid of this visible range"), snow off
	              the orb. FREEZE PULSE (the upgrade the user mentioned, off by default): a placed
	              model with attribute FreezePulse = true also stuns everything in the aura for
	              PULSE_STUN s every PULSE_EVERY s (ZombieAPI.Stun) with a burst.
	  Minigun     Head* yaws, Spin* rolls about BarrelAxis. Locks the nearest zombie in RANGE and
	              KEEPS it while it lives and stays in range (single target). The barrels spin up over
	              SPINUP s before the first shot and spin down over SPINDOWN s after the target is
	              gone; while spun up it fires every INTERVAL: DAMAGE per shot, thin tracer, flash.
	  LaserGate   no target: the four Beam parts span the gap between the pillars; every TICK any
	              zombie whose root is inside the gate volume (x within HALF_WIDTH of the gate's centre,
	              y 0..HEIGHT, z within HALF_DEPTH) takes DPS x TICK (continuous damage while crossing),
	              the beams flicker and spark where it stands. The beams never collide (installer).

	BoostPad has no behaviour (it is not a weapon). Everything here reads the live zombie list from
	ZombieRaidService's ZombieAPI, so the defences idle while there are no zombies.
	A defence whose model carries Broken = true (BuildHealthService: bashed to 0 by a zombie) does
	nothing - no tracking, no fire, no spikes, no beams - until it mends through the day (2026-09-12).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

--..Modules..--
local SoundController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundController"))
local ZombieCatalog = require(ReplicatedStorage.Modules:WaitForChild("ZombieCatalog"))

--..Config..--
local BUILD_TAG = "PlacedBuild"
local TICK = 0.05
local TURRET = {Range = 45, Interval = 0.45, Damage = 12, TurnRate = math.rad(540), Cone = math.rad(8), MaxPitch = math.rad(45), MinPitch = math.rad(-25), RestAfter = 2}
local TRAP = {Interval = 0.4, Damage = 7, Slow = 0.6, Half = 4, Height = 6}
local CATAPULT = {Range = 60, MinRange = 8, Interval = 4.5, Damage = 45, Radius = 9, Flight = 1.3, Arc = 14, ArmFired = math.rad(-92), SwingTime = 0.12, HoldTime = 0.3, ResetTime = 1.0}
local CATAPULT_WHEELS_OFFSET = Vector3.new(0, 0.96, -0.275) -- Wheels part centre in the prop's authored frame
local CATAPULT_PIVOT = Vector3.new(0, 2.30, 1.30)           -- ArmPivot in that frame (props/README.md)
--.. set 2
local MORTAR = {Range = 75, MinRange = 12, Interval = 3.6, Damage = 60, Radius = 10, Flight = 1.7, Arc = 24, TurnRate = math.rad(240), Cone = math.rad(10), RestAfter = 3}
local TESLA = {Range = 28, Interval = 1.5, Damage = 18, Chain = 3, ChainRange = 12, ChainFalloff = 0.75, IdleArcEvery = 0.7, OrbSpin = math.rad(60)}
local FROST = {Radius = 24, Tick = 0.5, SlowFor = 0.8, Chill = 2, PulseEvery = 10, PulseStun = 1.5, OrbSpin = math.rad(35), AuraPulse = 0.06, ShowAura = false} -- ShowAura: the range disc on the ground (off, user 2026-09-18)
local MINIGUN = {Range = 42, Interval = 0.08, Damage = 4, TurnRate = math.rad(420), Cone = math.rad(6), Spinup = 1.2, Spindown = 1.6, SpinRate = math.rad(1440), RestAfter = 2.5, ShotSoundEvery = 3}
local LASER = {Tick = 0.1, DPS = 25, HalfWidth = 1.95, Height = 5.5, HalfDepth = 1.25, SparkEvery = 0.35} -- 2.5 studs deep: a walking zombie takes ~0.3 s to cross = ~8 damage, a slowed one ~20, one stuck at the pillars the full 25 per second
local DEFENCES_FOLDER = "Defences" -- ServerStorage.Builds/<this>/<Source>: where a set-2 rig reads its Pivot_* attributes from

--..Instances..--
local API = ServerStorage:WaitForChild(ZombieCatalog.API, 60)
if not API then
	warn("[DefenceService] ServerStorage." .. ZombieCatalog.API .. " never appeared (ZombieRaidService missing?)")
	return
end
local DamageAPI = API:WaitForChild("Damage")
local ZombiesAPI = API:WaitForChild("Zombies")
local SlowAPI = API:WaitForChild("Slow")
local StunAPI = API:WaitForChild("Stun")
local Sources = ServerStorage:WaitForChild("Builds", 30)
Sources = Sources and Sources:FindFirstChild(DEFENCES_FOLDER)

--..State..--
local Defences = {} -- [model] = def
local KINDS = {Turret = true, SpikeTrap = true, Catapult = true, Mortar = true, TeslaCoil = true, FreezeTower = true, Minigun = true, LaserGate = true}
local BoxCentres = {} -- [source name] = Vector3: the source model's bounding-box centre in its authored frame

--..Helpers..--
local function shortestAngle(from, to)
	local d = (to - from + math.pi) % (2 * math.pi) - math.pi
	return d
end

local function rootOf(zombie)
	return zombie:FindFirstChild("HumanoidRootPart")
end

local function nearestZombie(zombies, from, range, minRange, skip)
	local best, bestDist
	for _, zombie in ipairs(zombies) do
		local root = rootOf(zombie)
		if root and not (skip and skip[zombie]) then
			local d = (root.Position - from).Magnitude
			if d <= range and d >= (minRange or 0) and (not bestDist or d < bestDist) then best, bestDist = zombie, d end
		end
	end
	return best, bestDist
end

local function alive(zombie)
	local hum = zombie and zombie:FindFirstChildOfClass("Humanoid")
	return zombie and zombie.Parent and hum and hum.Health > 0 and zombie:GetAttribute("Dead") ~= true
end

local function sourceOf(model)
	if not Sources then return nil end
	return Sources:FindFirstChild(model:GetAttribute("Source") or model:GetAttribute("BuildKey") or "")
end

--.. the authored origin of a set-2 prop in the world: the Hitbox sits at the source's bounding-box
--.. centre (BuildService.MakeTemplate) and rides the placement rotation
local function originOf(model, hitbox)
	local source = sourceOf(model)
	if not source then return nil end
	local centre = BoxCentres[source.Name]
	if not centre then
		local cf = source:GetBoundingBox()
		centre = cf.Position
		BoxCentres[source.Name] = centre
	end
	return hitbox.CFrame * CFrame.new(-centre), source
end

local function pivotOf(source, name, fallback)
	local v = source and source:GetAttribute("Pivot_" .. name)
	if typeof(v) == "Vector3" then return v end
	return fallback
end

local function groupParts(def, model, prefixes)
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "Hitbox" then
			for group, prefix in pairs(prefixes) do
				if p.Name:sub(1, #prefix) == prefix then
					def.Parts[p] = {Group = group, Rel = def.Origin:ToObjectSpace(p.CFrame)}
				end
			end
		end
	end
end

local function pointLight(parent, color, range, brightness, life)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = parent
	if life then Debris:AddItem(light, life) end
	return light
end

local function neonPart(name, size, cframe, color, life)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = workspace
	if life then Debris:AddItem(part, life) end
	return part
end

local function puff(position, color, count, size, speed, life)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(color)
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 2.5)})
	pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
	pe.Lifetime = NumberRange.new(life * 0.6, life)
	pe.Speed = NumberRange.new(speed * 0.5, speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(count)
	Debris:AddItem(att, life + 1)
end

--..Registration..--
local function Register(model)
	if Defences[model] then return end
	local key = model:GetAttribute("BuildKey")
	if not KINDS[key] then return end
	local hitbox = model.PrimaryPart
	if not hitbox then return end
	local rot = hitbox.CFrame.Rotation
	local def = {Model = model, Kind = key, Owner = model:GetAttribute("Owner"), NextFire = 0, Yaw = 0, Pitch = 0, Parts = {}, HitboxCF = hitbox.CFrame, LastTarget = 0}
	if key == "Turret" then
		local plinth = model:FindFirstChild("BasePlinth")
		local trunnion = model:FindFirstChild("HeadTrunnion")
		if not (plinth and trunnion) then return end
		def.Origin = CFrame.new(plinth.Position) * rot
		def.Trunnion = def.Origin:PointToObjectSpace(trunnion.Position)
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") then
				if p.Name:sub(1, 4) == "Head" then
					def.Parts[p] = {Group = "Head", Rel = def.Origin:ToObjectSpace(p.CFrame)}
				elseif p.Name:sub(1, 6) == "Barrel" then
					def.Parts[p] = {Group = "Barrel", Rel = def.Origin:ToObjectSpace(p.CFrame)}
				end
			end
		end
		def.Muzzle = model:FindFirstChild("BarrelMuzzleGlow")
		def.Side = 1
	elseif key == "SpikeTrap" then
		for _, p in ipairs(model:GetChildren()) do
			--.. only the 0.45-stud BasePlate keeps colliding: the kerb + pit + spikes read as a ladder to a Humanoid (it went into Climbing on the kerb)
			if p:IsA("BasePart") and p.Name ~= "BasePlate" and p.Name ~= "Hitbox" then p.CanCollide = false end
		end
		def.Plate = model:FindFirstChild("BasePlate") or hitbox
	elseif key == "Catapult" then
		local wheels = model:FindFirstChild("Wheels")
		if not wheels then return end
		def.Origin = CFrame.new(wheels.Position - rot:VectorToWorldSpace(CATAPULT_WHEELS_OFFSET)) * rot
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") and p.Name:sub(1, 3) == "Arm" then
				def.Parts[p] = {Group = "Arm", Rel = def.Origin:ToObjectSpace(p.CFrame)}
			end
		end
		def.Bucket = model:FindFirstChild("ArmBucket")
		def.Angle = 0
	else
		--.. set 2: the origin from the Hitbox + the source's box centre, the rig from the source's Pivot_* attributes
		local origin, source = originOf(model, hitbox)
		if not origin then
			warn("[DefenceService] " .. key .. ": no source model in ServerStorage.Builds." .. DEFENCES_FOLDER)
			return
		end
		def.Origin = origin
		def.Source = source
		if key == "Mortar" then
			def.PitchPivot = pivotOf(source, "PitchPivot", Vector3.new(0, 4, 0))
			def.MuzzleTip = pivotOf(source, "MuzzleTip", Vector3.new(0, 6.9, -2))
			groupParts(def, model, {Mount = "Mount", Tube = "Tube"})
		elseif key == "Minigun" then
			def.Axis = pivotOf(source, "BarrelAxis", Vector3.new(0.45, 4.1, 0))
			def.MuzzleTip = pivotOf(source, "MuzzleTip", Vector3.new(0.45, 4.1, -4.3))
			groupParts(def, model, {Head = "Head", Spin = "Spin"})
			def.Spin, def.Roll = 0, 0
		elseif key == "TeslaCoil" then
			def.OrbCentre = pivotOf(source, "OrbCentre", Vector3.new(0, 8.95, 0))
			def.Tips = {}
			for i = 1, 4 do
				local tip = pivotOf(source, "ProngTip" .. i)
				if tip then table.insert(def.Tips, tip) end
			end
			def.Orb = model:FindFirstChild("Orb")
			if def.Orb then def.OrbRel = def.Origin:ToObjectSpace(def.Orb.CFrame) end
			def.NextIdle = 0
			def.Light = pointLight(def.Orb or hitbox, Color3.fromRGB(80, 170, 255), 14, 1.2)
		elseif key == "FreezeTower" then
			def.OrbCentre = pivotOf(source, "OrbCentre", Vector3.new(0, 8.55, 0))
			def.Orb = model:FindFirstChild("Orb")
			if def.Orb then def.OrbRel = def.Origin:ToObjectSpace(def.Orb.CFrame) end
			def.NextPulse = os.clock() + FROST.PulseEvery
			def.Light = pointLight(def.Orb or hitbox, Color3.fromRGB(170, 220, 255), 16, 1.0)
			--.. the aura: a translucent ice disc on the ground, pulsing gently -- OFF by default (2026-09-18, user:
			--.. "get rid of this visible range around one of the towers in my base"); FROST.ShowAura = true brings it back
			if FROST.ShowAura then
				local aura = Instance.new("Part")
				aura.Name = "FrostAura"
				aura.Shape = Enum.PartType.Cylinder
				aura.Size = Vector3.new(0.12, FROST.Radius * 2, FROST.Radius * 2)
				aura.CFrame = def.Origin * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90))
				aura.Color = Color3.fromRGB(160, 215, 255)
				aura.Material = Enum.Material.Neon
				aura.Transparency = 0.86
				aura.Anchored = true
				aura.CanCollide = false
				aura.CanQuery = false
				aura.CanTouch = false
				aura.CastShadow = false
				aura.Parent = model
				def.Aura = aura
			end
			if def.Orb then
				local att = Instance.new("Attachment")
				att.Parent = def.Orb
				local snow = Instance.new("ParticleEmitter")
				snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				snow.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
				snow.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.1)})
				snow.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1)})
				snow.Lifetime = NumberRange.new(1.6, 2.6)
				snow.Speed = NumberRange.new(2, 4)
				snow.SpreadAngle = Vector2.new(180, 180)
				snow.Acceleration = Vector3.new(0, -3, 0)
				snow.Rate = 10
				snow.Parent = att
				def.Snow = snow
			end
		elseif key == "LaserGate" then
			def.Beams = {}
			for i = 1, 4 do
				local beam = model:FindFirstChild("Beam" .. i)
				if beam then
					beam.CanCollide = false
					beam.CanQuery = false
					table.insert(def.Beams, beam)
					pointLight(beam, Color3.fromRGB(255, 60, 60), 6, 0.8)
				end
			end
			def.LastSpark = {}
		end
	end
	Defences[model] = def
	--.. moved (requestBuildMove pivots the whole model): carry the origin along
	def.MoveConn = hitbox:GetPropertyChangedSignal("CFrame"):Connect(function()
		if not Defences[model] then return end
		local delta = hitbox.CFrame * def.HitboxCF:Inverse()
		def.HitboxCF = hitbox.CFrame
		if def.Origin then def.Origin = delta * def.Origin end
		if def.Aura then def.Aura.CFrame = delta * def.Aura.CFrame end
	end)
end

local function Forget(model)
	local def = Defences[model]
	if not def then return end
	if def.MoveConn then def.MoveConn:Disconnect() end
	if def.Aura then def.Aura:Destroy() end
	Defences[model] = nil
end

--..Turret..--
local function PoseTurret(def)
	local Y = def.Origin * CFrame.Angles(0, def.Yaw, 0)
	local T = CFrame.new(def.Trunnion)
	local B = Y * T * CFrame.Angles(def.Pitch, 0, 0) * T:Inverse()
	for part, info in pairs(def.Parts) do
		if part.Parent then part.CFrame = (info.Group == "Head" and Y or B) * info.Rel end
	end
end

local function Tracer(from, to, color, thickness, life)
	local length = (to - from).Magnitude
	local beam = neonPart("Tracer", Vector3.new(thickness or 0.14, thickness or 0.14, length), CFrame.lookAt((from + to) * 0.5, to), color, life or 0.07)
	pointLight(beam, color, 8, 3)
	return beam
end

local function TurretTick(def, zombies, now, dt)
	local trunnionWorld = def.Origin:PointToWorldSpace(def.Trunnion)
	local target = nearestZombie(zombies, trunnionWorld, TURRET.Range)
	local yawGoal, pitchGoal = 0, 0
	if target then
		def.LastTarget = now
		local root = rootOf(target)
		local d = def.Origin:VectorToObjectSpace(root.Position - trunnionWorld)
		yawGoal = math.atan2(-d.X, -d.Z)
		pitchGoal = math.clamp(math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z)), TURRET.MinPitch, TURRET.MaxPitch)
	elseif now - def.LastTarget < TURRET.RestAfter then
		return -- hold the last pose for a moment
	end
	local step = TURRET.TurnRate * dt
	local dy = shortestAngle(def.Yaw, yawGoal)
	def.Yaw += math.clamp(dy, -step, step)
	def.Yaw = (def.Yaw + math.pi) % (2 * math.pi) - math.pi
	local dp = pitchGoal - def.Pitch
	def.Pitch += math.clamp(dp, -step, step)
	PoseTurret(def)
	if target and math.abs(dy) <= TURRET.Cone and now >= def.NextFire then
		def.NextFire = now + TURRET.Interval
		def.Side = -def.Side
		local muzzle = def.Muzzle
		local from = muzzle and (muzzle.CFrame * CFrame.new(def.Side * 0.5, 0, -0.15)).Position or trunnionWorld
		local root = rootOf(target)
		local to = root.Position + Vector3.new(0, 0.5, 0)
		Tracer(from, to, muzzle and muzzle.Color or Color3.fromRGB(77, 210, 255))
		SoundController.PlayFXAt("Zap", from, {Volume = 0.45, RollOff = 50})
		DamageAPI:Invoke(target, TURRET.Damage, "Turret")
	end
end

--..Spike trap..--
local function TrapTick(def, zombies, now)
	if now < def.NextFire then return end
	def.NextFire = now + TRAP.Interval
	local plate = def.Plate
	if not (plate and plate.Parent) then return end
	for _, zombie in ipairs(zombies) do
		local root = rootOf(zombie)
		if root then
			local p = plate.CFrame:PointToObjectSpace(root.Position)
			if math.abs(p.X) <= TRAP.Half and math.abs(p.Z) <= TRAP.Half and p.Y > -1 and p.Y < TRAP.Height then
				DamageAPI:Invoke(zombie, TRAP.Damage, "Spikes")
				SlowAPI:Invoke(zombie, TRAP.Slow)
			end
		end
	end
end

--..Catapult..--
local function PoseCatapult(def, angle)
	def.Angle = angle
	local P = CFrame.new(CATAPULT_PIVOT)
	local A = def.Origin * P * CFrame.Angles(angle, 0, 0) * P:Inverse()
	for part, info in pairs(def.Parts) do
		if part.Parent then part.CFrame = A * info.Rel end
	end
end

--.. splash damage around `position`: full at the centre, half at the edge
local function Splash(position, zombies, damage, radius, source)
	for _, zombie in ipairs(zombies) do
		local root = rootOf(zombie)
		if root then
			local d = (root.Position - position).Magnitude
			if d <= radius then
				DamageAPI:Invoke(zombie, math.floor(damage * (1 - 0.5 * d / radius) + 0.5), source)
			end
		end
	end
end

local function BoulderSplash(position, zombies)
	Splash(position, zombies, CATAPULT.Damage, CATAPULT.Radius, "Catapult")
	puff(position, Color3.fromRGB(150, 135, 110), 30, 1.5, 16, 1.3)
	SoundController.PlayFXAt("Rock Crumble", position, {Volume = 1, RollOff = 90})
	SoundController.PlayFXAt("Big Thud", position, {Volume = 0.9, RollOff = 90})
end

local function Launch(def, from, to)
	local boulder = Instance.new("Part")
	boulder.Name = "Boulder"
	boulder.Shape = Enum.PartType.Ball
	boulder.Size = Vector3.new(1.4, 1.4, 1.4)
	boulder.Color = Color3.fromRGB(120, 116, 108)
	boulder.Material = Enum.Material.Slate
	boulder.Anchored = true
	boulder.CanCollide = false
	boulder.CanQuery = false
	boulder.CanTouch = false
	boulder.CFrame = CFrame.new(from)
	boulder.Parent = workspace
	SoundController.PlayFXAt("Whoosh", from, {Volume = 0.7, RollOff = 60})
	task.spawn(function()
		local t0 = os.clock()
		local arc = CATAPULT.Arc + (to - from).Magnitude * 0.12
		while true do
			local a = math.clamp((os.clock() - t0) / CATAPULT.Flight, 0, 1)
			boulder.CFrame = CFrame.new(from:Lerp(to, a) + Vector3.new(0, arc * 4 * a * (1 - a), 0)) * CFrame.Angles(a * 9, 0, a * 5)
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		BoulderSplash(to, ZombiesAPI:Invoke())
		Debris:AddItem(boulder, 0.6)
	end)
end

local function CatapultTick(def, zombies, now)
	if now < def.NextFire or def.Swinging then return end
	local origin = def.Origin.Position
	local target = nearestZombie(zombies, origin, CATAPULT.Range, CATAPULT.MinRange)
	if not target then return end
	def.NextFire = now + CATAPULT.Interval
	def.Swinging = true
	local root = rootOf(target)
	local aim = root.Position + Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z) * CATAPULT.Flight * 0.6
	aim = Vector3.new(aim.X, root.Position.Y - 2.5, aim.Z)
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = math.clamp((os.clock() - t0) / CATAPULT.SwingTime, 0, 1)
			PoseCatapult(def, CATAPULT.ArmFired * a)
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		local from = def.Bucket and def.Bucket.Position + Vector3.new(0, 1, 0) or origin + Vector3.new(0, 5, 0)
		Launch(def, from, aim)
		task.wait(CATAPULT.HoldTime)
		t0 = os.clock()
		while def.Model.Parent do
			local a = math.clamp((os.clock() - t0) / CATAPULT.ResetTime, 0, 1)
			PoseCatapult(def, CATAPULT.ArmFired * (1 - a))
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		def.Swinging = false
	end)
end

--..Mortar (set 2)..--
local function PoseMortar(def)
	local Y = def.Origin * CFrame.Angles(0, def.Yaw, 0)
	local T = CFrame.new(def.PitchPivot)
	local B = Y * T * CFrame.Angles(def.Pitch, 0, 0) * T:Inverse()
	for part, info in pairs(def.Parts) do
		if part.Parent then part.CFrame = (info.Group == "Mount" and Y or B) * info.Rel end
	end
end

local function ShellBurst(position, zombies)
	Splash(position, zombies, MORTAR.Damage, MORTAR.Radius, "Mortar")
	local flash = neonPart("ShellFlash", Vector3.new(1, 1, 1), CFrame.new(position + Vector3.new(0, 1, 0)), Color3.fromRGB(255, 170, 60), 0.35)
	flash.Shape = Enum.PartType.Ball
	pointLight(flash, Color3.fromRGB(255, 160, 60), 30, 6)
	task.spawn(function()
		local t0 = os.clock()
		while flash.Parent do
			local a = math.clamp((os.clock() - t0) / 0.3, 0, 1)
			flash.Size = Vector3.new(1, 1, 1) * (1 + 9 * a)
			flash.Transparency = a
			RunService.Heartbeat:Wait()
		end
	end)
	puff(position + Vector3.new(0, 0.5, 0), Color3.fromRGB(255, 150, 70), 18, 1.6, 22, 0.6)
	puff(position + Vector3.new(0, 1, 0), Color3.fromRGB(90, 85, 80), 40, 2.2, 14, 1.8)
	SoundController.PlayFXAt("Big Break", position, {Volume = 1, RollOff = 110})
	SoundController.PlayFXAt("Big Thud", position, {Volume = 0.9, RollOff = 110})
end

local function FireShell(def, from, to)
	local shell = Instance.new("Part")
	shell.Name = "MortarShell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(1.1, 1.1, 1.1)
	shell.Color = Color3.fromRGB(40, 42, 46)
	shell.Material = Enum.Material.Metal
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CFrame = CFrame.new(from)
	shell.Parent = workspace
	local att = Instance.new("Attachment")
	att.Parent = shell
	local trail = Instance.new("ParticleEmitter")
	trail.Texture = "rbxasset://textures/particles/smoke_main.dds"
	trail.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
	trail.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2)})
	trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1)})
	trail.Lifetime = NumberRange.new(0.5, 0.9)
	trail.Speed = NumberRange.new(0, 0.5)
	trail.Rate = 30
	trail.Parent = att
	puff(from, Color3.fromRGB(230, 220, 200), 14, 1.2, 10, 0.8)
	SoundController.PlayFXAt("Big Thud", from, {Volume = 0.7, RollOff = 70})
	SoundController.PlayFXAt("Whoosh", from, {Volume = 0.6, RollOff = 70})
	task.spawn(function()
		local t0 = os.clock()
		local arc = MORTAR.Arc + (to - from).Magnitude * 0.1
		while true do
			local a = math.clamp((os.clock() - t0) / MORTAR.Flight, 0, 1)
			shell.CFrame = CFrame.new(from:Lerp(to, a) + Vector3.new(0, arc * 4 * a * (1 - a), 0))
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		trail.Enabled = false
		ShellBurst(to, ZombiesAPI:Invoke())
		Debris:AddItem(shell, 0.05)
	end)
end

local function MortarTick(def, zombies, now, dt)
	local origin = def.Origin.Position
	local target = nearestZombie(zombies, origin, MORTAR.Range, MORTAR.MinRange)
	local yawGoal = 0
	if target then
		def.LastTarget = now
		local d = def.Origin:VectorToObjectSpace(rootOf(target).Position - origin)
		yawGoal = math.atan2(-d.X, -d.Z)
	elseif now - def.LastTarget < MORTAR.RestAfter then
		return
	end
	local step = MORTAR.TurnRate * dt
	local dy = shortestAngle(def.Yaw, yawGoal)
	def.Yaw += math.clamp(dy, -step, step)
	def.Yaw = (def.Yaw + math.pi) % (2 * math.pi) - math.pi
	PoseMortar(def)
	if target and math.abs(dy) <= MORTAR.Cone and now >= def.NextFire then
		def.NextFire = now + MORTAR.Interval
		local root = rootOf(target)
		local aim = root.Position + Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z) * MORTAR.Flight * 0.5
		aim = Vector3.new(aim.X, root.Position.Y - 2.5, aim.Z)
		local Y = def.Origin * CFrame.Angles(0, def.Yaw, 0)
		FireShell(def, Y:PointToWorldSpace(def.MuzzleTip), aim)
		--.. recoil: the tube dips and springs back
		task.spawn(function()
			local t0 = os.clock()
			while def.Model.Parent do
				local a = math.clamp((os.clock() - t0) / 0.5, 0, 1)
				def.Pitch = math.rad(6) * math.sin(a * math.pi) * (1 - a)
				PoseMortar(def)
				if a >= 1 then break end
				RunService.Heartbeat:Wait()
			end
			def.Pitch = 0
		end)
	end
end

--..Tesla coil (set 2)..--
--.. a jagged bolt: N segments with random side-steps, neon, gone in a blink
local function Bolt(from, to, color, thickness, life, jag)
	local n = math.clamp(math.floor((to - from).Magnitude / 3) + 2, 3, 8)
	local prev = from
	local dir = (to - from)
	local length = dir.Magnitude
	if length < 0.01 then return end
	dir = dir.Unit
	local side = dir:Cross(Vector3.yAxis)
	if side.Magnitude < 0.1 then side = dir:Cross(Vector3.xAxis) end
	side = side.Unit
	local up = side:Cross(dir)
	for i = 1, n do
		local a = i / n
		local point = from + dir * (length * a)
		if i < n then point += side * ((math.random() - 0.5) * 2 * jag) + up * ((math.random() - 0.5) * 2 * jag) end
		Tracer(prev, point, color, thickness, life)
		prev = point
	end
end

local function TeslaTick(def, zombies, now, dt)
	--.. the orb turns and the light breathes
	if def.Orb and def.Orb.Parent then
		def.Roll = (def.Roll or 0) + TESLA.OrbSpin * dt
		def.Orb.CFrame = def.Origin * CFrame.new(def.OrbCentre) * CFrame.Angles(0, def.Roll, 0) * CFrame.new(-def.OrbCentre) * def.OrbRel
	end
	if def.Light then def.Light.Brightness = 1.0 + 0.5 * math.sin(now * 3) end
	local orbWorld = def.Origin:PointToWorldSpace(def.OrbCentre)
	if now >= def.NextIdle then
		def.NextIdle = now + TESLA.IdleArcEvery * (0.6 + math.random() * 0.8)
		if #def.Tips > 0 then
			local tip = def.Origin:PointToWorldSpace(def.Tips[math.random(1, #def.Tips)])
			Bolt(orbWorld, tip, Color3.fromRGB(120, 200, 255), 0.08, 0.08, 0.35)
		end
	end
	if now < def.NextFire then return end
	local first = nearestZombie(zombies, orbWorld, TESLA.Range)
	if not first then return end
	def.NextFire = now + TESLA.Interval
	def.LastTarget = now
	local hit = {}
	local from = orbWorld
	local current, damage = first, TESLA.Damage
	for hop = 0, TESLA.Chain do
		if not current then break end
		hit[current] = true
		local root = rootOf(current)
		local to = root.Position + Vector3.new(0, 0.6, 0)
		Bolt(from, to, Color3.fromRGB(110, 190, 255), 0.16, 0.14, hop == 0 and 1.6 or 1.0)
		local flash = neonPart("TeslaHit", Vector3.new(0.6, 0.6, 0.6), CFrame.new(to), Color3.fromRGB(190, 230, 255), 0.14)
		flash.Shape = Enum.PartType.Ball
		pointLight(flash, Color3.fromRGB(120, 200, 255), 12, 4)
		DamageAPI:Invoke(current, math.floor(damage + 0.5), "Tesla")
		from = to
		damage *= TESLA.ChainFalloff
		current = nearestZombie(zombies, to, TESLA.ChainRange, 0, hit)
	end
	local flash = pointLight(def.Orb or def.Model.PrimaryPart, Color3.fromRGB(150, 220, 255), 26, 6, 0.2)
	SoundController.PlayFXAt("Zap", orbWorld, {Volume = 0.8, RollOff = 70})
	SoundController.PlayFXAt("Electric Buzz", orbWorld, {Volume = 0.5, RollOff = 60, MaxLife = 0.5})
end

--..Freeze tower (set 2)..--
local function FrostTick(def, zombies, now, dt)
	if def.Orb and def.Orb.Parent then
		def.Roll = (def.Roll or 0) + FROST.OrbSpin * dt
		def.Orb.CFrame = def.Origin * CFrame.new(def.OrbCentre) * CFrame.Angles(0, def.Roll, 0) * CFrame.new(-def.OrbCentre) * def.OrbRel
	end
	if def.Aura and def.Aura.Parent then
		local s = FROST.Radius * 2 * (1 + FROST.AuraPulse * math.sin(now * 1.5))
		def.Aura.Size = Vector3.new(0.12, s, s)
		def.Aura.Transparency = 0.84 + 0.05 * math.sin(now * 1.5 + 1)
	end
	if now < def.NextFire then return end
	def.NextFire = now + FROST.Tick
	local origin = def.Origin.Position
	local pulse = def.Model:GetAttribute("FreezePulse") == true and now >= def.NextPulse
	if pulse then def.NextPulse = now + FROST.PulseEvery end
	local any = false
	for _, zombie in ipairs(zombies) do
		local root = rootOf(zombie)
		if root then
			local flat = Vector3.new(root.Position.X - origin.X, 0, root.Position.Z - origin.Z)
			if flat.Magnitude <= FROST.Radius then
				any = true
				SlowAPI:Invoke(zombie, FROST.SlowFor)
				DamageAPI:Invoke(zombie, FROST.Chill, "Frost")
				if pulse then
					StunAPI:Invoke(zombie, FROST.PulseStun)
					puff(root.Position, Color3.fromRGB(200, 235, 255), 16, 0.9, 8, 0.9)
				elseif math.random() < 0.35 then
					puff(root.Position - Vector3.new(0, 1.5, 0), Color3.fromRGB(190, 225, 255), 4, 0.5, 3, 0.7)
				end
			end
		end
	end
	if pulse then
		local orbWorld = def.Origin:PointToWorldSpace(def.OrbCentre)
		puff(orbWorld, Color3.fromRGB(200, 235, 255), 40, 1.5, 24, 1.2)
		SoundController.PlayFXAt("Magic Zoom", orbWorld, {Volume = 0.8, RollOff = 80})
	elseif any and math.random() < 0.15 then
		SoundController.PlayFXAt("Magic Shimmer", origin, {Volume = 0.25, RollOff = 50, MaxLife = 0.8})
	end
end

--..Minigun (set 2)..--
local function PoseMinigun(def)
	local Y = def.Origin * CFrame.Angles(0, def.Yaw, 0)
	local A = CFrame.new(def.Axis)
	local R = Y * A * CFrame.Angles(0, 0, def.Roll) * A:Inverse() -- the barrels run along the prop's Z axis
	for part, info in pairs(def.Parts) do
		if part.Parent then part.CFrame = (info.Group == "Head" and Y or R) * info.Rel end
	end
end

local function MinigunTick(def, zombies, now, dt)
	local origin = def.Origin:PointToWorldSpace(def.Axis)
	--.. keep the locked target while it lives and stays in range; otherwise the nearest
	local target = def.Target
	if target and not (alive(target) and rootOf(target) and (rootOf(target).Position - origin).Magnitude <= MINIGUN.Range * 1.1) then target = nil end
	if not target then target = nearestZombie(zombies, origin, MINIGUN.Range) end
	def.Target = target
	local yawGoal = 0
	if target then
		def.LastTarget = now
		local d = def.Origin:VectorToObjectSpace(rootOf(target).Position - origin)
		yawGoal = math.atan2(-d.X, -d.Z)
		if def.Spin <= 0 then SoundController.PlayFXAt("Riser", origin, {Volume = 0.35, RollOff = 60, MaxLife = MINIGUN.Spinup}) end
		def.Spin = math.min(1, def.Spin + dt / MINIGUN.Spinup)
	else
		def.Spin = math.max(0, def.Spin - dt / MINIGUN.Spindown)
		if def.Spin <= 0 and now - def.LastTarget >= MINIGUN.RestAfter then
			if math.abs(def.Yaw) < 1e-3 then return end
		end
	end
	def.Roll += MINIGUN.SpinRate * def.Spin * dt
	local step = MINIGUN.TurnRate * dt
	local dy = shortestAngle(def.Yaw, yawGoal)
	def.Yaw += math.clamp(dy, -step, step)
	def.Yaw = (def.Yaw + math.pi) % (2 * math.pi) - math.pi
	PoseMinigun(def)
	if target and def.Spin >= 0.999 and math.abs(dy) <= MINIGUN.Cone and now >= def.NextFire then
		def.NextFire = now + MINIGUN.Interval
		def.Shots = (def.Shots or 0) + 1
		local Y = def.Origin * CFrame.Angles(0, def.Yaw, 0)
		local from = Y:PointToWorldSpace(def.MuzzleTip)
		local root = rootOf(target)
		local to = root.Position + Vector3.new((math.random() - 0.5) * 1.2, 0.3 + (math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.2)
		Tracer(from, to, Color3.fromRGB(255, 220, 120), 0.09, 0.05)
		if def.Shots % MINIGUN.ShotSoundEvery == 0 then SoundController.PlayFXAt("Zap", from, {Volume = 0.22, RollOff = 45, Speed = 1.7}) end
		DamageAPI:Invoke(target, MINIGUN.Damage, "Minigun")
	end
end

--..Laser gate (set 2)..--
local function LaserTick(def, zombies, now)
	--.. the beams shimmer all the time
	for i, beam in ipairs(def.Beams) do
		if beam.Parent then beam.Transparency = 0.05 + 0.12 * (0.5 + 0.5 * math.sin(now * 9 + i)) end
	end
	if now < def.NextFire then return end
	def.NextFire = now + LASER.Tick
	local any
	for _, zombie in ipairs(zombies) do
		local root = rootOf(zombie)
		if root then
			local p = def.Origin:PointToObjectSpace(root.Position)
			if math.abs(p.X) <= LASER.HalfWidth and math.abs(p.Z) <= LASER.HalfDepth and p.Y > -1 and p.Y <= LASER.Height then
				any = true
				DamageAPI:Invoke(zombie, LASER.DPS * LASER.Tick, "Laser")
				if now - (def.LastSpark[zombie] or 0) >= LASER.SparkEvery then
					def.LastSpark[zombie] = now
					local spark = neonPart("LaserSpark", Vector3.new(0.5, 0.5, 0.5), CFrame.new(root.Position), Color3.fromRGB(255, 90, 80), 0.12)
					spark.Shape = Enum.PartType.Ball
					pointLight(spark, Color3.fromRGB(255, 70, 60), 10, 4)
					puff(root.Position, Color3.fromRGB(255, 120, 90), 6, 0.35, 6, 0.4)
					SoundController.PlayFXAt("Electric Buzz", root.Position, {Volume = 0.45, RollOff = 50, MaxLife = 0.35})
				end
			end
		end
	end
	if any then
		for _, beam in ipairs(def.Beams) do
			if beam.Parent then beam.Transparency = 0.35 + 0.3 * math.random() end
		end
	end
end

--..Main loop..--
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < TICK then return end
	local step = acc
	acc = 0
	if next(Defences) == nil then return end
	local now = os.clock()
	local zombies = ZombiesAPI:Invoke()
	for model, def in pairs(Defences) do
		if not model.Parent then
			Forget(model)
		elseif model:GetAttribute("Broken") == true then
			def.LastTarget = 0 -- broken: idle until BuildHealthService mends it
			def.Target = nil
			if def.Kind == "Minigun" then def.Spin = 0 end
		else
			local ok, err = pcall(function()
				if def.Kind == "Turret" then TurretTick(def, zombies, now, step)
				elseif def.Kind == "SpikeTrap" then TrapTick(def, zombies, now)
				elseif def.Kind == "Catapult" then CatapultTick(def, zombies, now)
				elseif def.Kind == "Mortar" then MortarTick(def, zombies, now, step)
				elseif def.Kind == "TeslaCoil" then TeslaTick(def, zombies, now, step)
				elseif def.Kind == "FreezeTower" then FrostTick(def, zombies, now, step)
				elseif def.Kind == "Minigun" then MinigunTick(def, zombies, now, step)
				elseif def.Kind == "LaserGate" then LaserTick(def, zombies, now) end
			end)
			if not ok then warn("[DefenceService] " .. def.Kind .. ": " .. tostring(err)) end
		end
	end
end)

--..Setup..--
for _, model in ipairs(CollectionService:GetTagged(BUILD_TAG)) do Register(model) end
CollectionService:GetInstanceAddedSignal(BUILD_TAG):Connect(function(model)
	task.defer(Register, model) -- attributes + parent are set before the tag by BuildService, but be safe
end)
CollectionService:GetInstanceRemovedSignal(BUILD_TAG):Connect(Forget)
print(("[DefenceService] ready: %d defence(s) registered; turret %d dmg / %.2fs, trap %d dmg / %.1fs, catapult %d splash / %.1fs; mortar %d splash / %.1fs, tesla %d x%d chain / %.1fs, frost r%d slow + %d chill, minigun %d dmg / %.2fs (spin-up %.1fs), laser %d dps"):format(
	(function() local n = 0 for _ in pairs(Defences) do n += 1 end return n end)(), TURRET.Damage, TURRET.Interval, TRAP.Damage, TRAP.Interval, CATAPULT.Damage, CATAPULT.Interval,
	MORTAR.Damage, MORTAR.Interval, TESLA.Damage, TESLA.Chain + 1, TESLA.Interval, FROST.Radius, FROST.Chill, MINIGUN.Damage, MINIGUN.Interval, MINIGUN.Spinup, LASER.DPS))
