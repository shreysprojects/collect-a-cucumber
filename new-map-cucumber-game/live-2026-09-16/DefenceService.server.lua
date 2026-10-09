--[[
	DefenceService  (Script, ServerScriptService)  2026-09-10
	Makes the Defences builds work against the night raid. Every placed build (tag "PlacedBuild",
	attribute BuildKey) of these kinds is registered when it appears in a plot's Placed folder and
	forgotten when it goes (sold, moved = re-based, smashed):

	  Turret    parts Head* yaw about the vertical axis through BasePlinth, Barrel* pitch about the
	            HeadTrunnion (the Blender rig data of defenses/build_turret.py). Tracks the nearest
	            zombie within RANGE, turns at TURN_RATE, and once on target fires every INTERVAL: a
	            neon tracer + muzzle flash from the alternating muzzle of BarrelMuzzleGlow, DAMAGE
	            through ServerStorage.ZombieAPI.Damage. Eases back to rest when nothing is in range.
	  SpikeTrap the Spikes* parts stop colliding so zombies walk onto the bed; any zombie standing
	            inside the 8 x 8 plate takes DAMAGE every INTERVAL and is slowed (ZombieAPI.Slow).
	  Catapult  the Arm* parts swing about ArmPivot (0, 2.30, 1.30) in the prop's own frame (derived
	            from the Wheels part), a boulder flies a parabola to the target zombie's predicted
	            position in FLIGHT seconds and lands with RADIUS splash damage.

	BoostPad has no behaviour (it is not a weapon). Everything here reads the live zombie list from
	ZombieRaidService's ZombieAPI, so the defences idle while there are no zombies.
	A defence whose model carries Broken = true (BuildHealthService: bashed to 0 by a zombie) does
	nothing - no tracking, no fire, no spikes - until it mends through the day (2026-09-12).
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

--..Instances..--
local API = ServerStorage:WaitForChild(ZombieCatalog.API, 60)
if not API then
	warn("[DefenceService] ServerStorage." .. ZombieCatalog.API .. " never appeared (ZombieRaidService missing?)")
	return
end
local DamageAPI = API:WaitForChild("Damage")
local ZombiesAPI = API:WaitForChild("Zombies")
local SlowAPI = API:WaitForChild("Slow")

--..State..--
local Defences = {} -- [model] = def
local KINDS = {Turret = true, SpikeTrap = true, Catapult = true}

--..Helpers..--
local function shortestAngle(from, to)
	local d = (to - from + math.pi) % (2 * math.pi) - math.pi
	return d
end

local function rootOf(zombie)
	return zombie:FindFirstChild("HumanoidRootPart")
end

local function nearestZombie(zombies, from, range, minRange)
	local best, bestDist
	for _, zombie in ipairs(zombies) do
		local root = rootOf(zombie)
		if root then
			local d = (root.Position - from).Magnitude
			if d <= range and d >= (minRange or 0) and (not bestDist or d < bestDist) then best, bestDist = zombie, d end
		end
	end
	return best, bestDist
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
	end
	Defences[model] = def
	--.. moved (requestBuildMove pivots the whole model): carry the origin along
	def.MoveConn = hitbox:GetPropertyChangedSignal("CFrame"):Connect(function()
		if not Defences[model] then return end
		local delta = hitbox.CFrame * def.HitboxCF:Inverse()
		def.HitboxCF = hitbox.CFrame
		if def.Origin then def.Origin = delta * def.Origin end
	end)
end

local function Forget(model)
	local def = Defences[model]
	if not def then return end
	if def.MoveConn then def.MoveConn:Disconnect() end
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

local function Tracer(from, to, color)
	local length = (to - from).Magnitude
	local beam = Instance.new("Part")
	beam.Name = "Tracer"
	beam.Size = Vector3.new(0.14, 0.14, length)
	beam.CFrame = CFrame.lookAt((from + to) * 0.5, to)
	beam.Color = color
	beam.Material = Enum.Material.Neon
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Parent = workspace
	local flash = Instance.new("PointLight")
	flash.Color = color
	flash.Range = 8
	flash.Brightness = 3
	flash.Parent = beam
	Debris:AddItem(beam, 0.07)
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

local function Splash(position, zombies)
	for _, zombie in ipairs(zombies) do
		local root = rootOf(zombie)
		if root then
			local d = (root.Position - position).Magnitude
			if d <= CATAPULT.Radius then
				DamageAPI:Invoke(zombie, math.floor(CATAPULT.Damage * (1 - 0.5 * d / CATAPULT.Radius) + 0.5), "Catapult")
			end
		end
	end
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(150, 135, 110))
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5)})
	pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
	pe.Lifetime = NumberRange.new(0.7, 1.3)
	pe.Speed = NumberRange.new(8, 16)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(30)
	Debris:AddItem(att, 3)
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
		Splash(to, ZombiesAPI:Invoke())
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
		else
			local ok, err = pcall(function()
				if def.Kind == "Turret" then TurretTick(def, zombies, now, step)
				elseif def.Kind == "SpikeTrap" then TrapTick(def, zombies, now)
				elseif def.Kind == "Catapult" then CatapultTick(def, zombies, now) end
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
print(("[DefenceService] ready: %d defence(s) registered; turret %d dmg / %.2fs, trap %d dmg / %.1fs, catapult %d splash / %.1fs"):format(
	(function() local n = 0 for _ in pairs(Defences) do n += 1 end return n end)(), TURRET.Damage, TURRET.Interval, TRAP.Damage, TRAP.Interval, CATAPULT.Damage, CATAPULT.Interval))
