--[[
	CollectionTrails  (ModuleScript, ReplicatedStorage.Modules)  -- 2026-09-23
	The Index reward: one character trail per biome, earned by collecting every cucumber of that
	biome (CucumberAdventure: data.CucumberCollection.Families[zone]) and equipped / unequipped from
	the Index panel's reward button (IndexController -> Remotes.EquipCucumberCollection). Only one
	trail is worn at a time (data.CucumberCollection.Equipped = zone).

	Every trail also multiplies bench-press strength per rep, the way the headbands do, and STACKS
	with the worn headband: GymService.StrengthPerRep = 2^(bench level - 1) x headband x trail.
	Biome N's trail is (N + 1)x (Spawn 2x ... Neon 11x) -- the StrengthMult column below.

	Shared by the server (CucumberAdventure wears / clears the trail on the character, GymService
	reads StrengthMult) and the client (IndexView shows the name + multiplier).

		CollectionTrails.List()              -> the TRAILS table in biome order (read only)
		CollectionTrails.Get(zone)           -> entry or nil
		CollectionTrails.StrengthMultOf(zone)-> 1 for nil / unknown, never 0
		CollectionTrails.Wear(character, zone) -> builds the trail on HumanoidRootPart (server)
		CollectionTrails.Clear(character)    -> removes it (server)

	Look: a soft wide ribbon (Colors gradient) + a thin bright core (Core) between two attachments
	on the back of the HumanoidRootPart, plus an optional ParticleEmitter (Particles) using the
	engine's built-in particle textures, so nothing needs uploading. Everything created carries the
	attribute CollectionTrailZone = zone and a name starting with "CollectionTrail".
]]
local M = {}
local C = Color3.fromRGB

M.SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
M.SMOKE = "rbxasset://textures/particles/smoke_main.dds"
M.FIRE = "rbxasset://textures/particles/fire_main.dds"

M.TRAILS = {
	{Zone = "Spawn", Name = "Sprout Trail", StrengthMult = 2,
		Colors = {C(125, 255, 95), C(38, 168, 58)}, Core = C(230, 255, 200), Light = 0.35,
		Particles = {Texture = M.SPARKLE, Colors = {C(170, 255, 120), C(90, 220, 80)}, Size = 0.28, Rate = 5, Speed = {1, 2}, Accel = Vector3.new(0, -2, 0)}},
	{Zone = "Desert", Name = "Dune Trail", StrengthMult = 3,
		Colors = {C(255, 199, 85), C(214, 124, 40)}, Core = C(255, 240, 190), Light = 0.25,
		Particles = {Texture = M.SMOKE, Colors = {C(232, 196, 130), C(190, 140, 80)}, Size = 0.9, Rate = 6, Speed = {0.5, 1.5}, Transparency = 0.55, Light = 0, Accel = Vector3.new(0, 1, 0)}},
	{Zone = "Samurai", Name = "Sakura Trail", StrengthMult = 4,
		Colors = {C(255, 135, 188), C(255, 214, 236)}, Core = C(255, 240, 248), Light = 0.35,
		Particles = {Texture = M.SPARKLE, Colors = {C(255, 150, 200), C(255, 220, 235)}, Size = 0.32, Rate = 10, Speed = {1, 2}, Accel = Vector3.new(0, -2.5, 0), Spin = 120}},
	{Zone = "Farm", Name = "Harvest Trail", StrengthMult = 5,
		Colors = {C(250, 226, 97), C(214, 142, 40)}, Core = C(255, 250, 210), Light = 0.3,
		Particles = {Texture = M.SPARKLE, Colors = {C(255, 230, 120), C(240, 170, 60)}, Size = 0.26, Rate = 6, Speed = {1, 2}, Accel = Vector3.new(0, -1.5, 0)}},
	{Zone = "Snow", Name = "Frost Trail", StrengthMult = 6,
		Colors = {C(158, 231, 255), C(255, 255, 255)}, Core = C(255, 255, 255), Light = 0.5,
		Particles = {Texture = M.SPARKLE, Colors = {C(255, 255, 255), C(170, 235, 255)}, Size = 0.24, Rate = 12, Speed = {0.5, 1.5}, Accel = Vector3.new(0, -1.2, 0), Spin = 60}},
	{Zone = "Underwater", Name = "Tide Trail", StrengthMult = 7,
		Colors = {C(60, 210, 232), C(20, 80, 200)}, Core = C(200, 255, 255), Light = 0.45,
		Particles = {Texture = M.SMOKE, Colors = {C(225, 250, 255), C(120, 220, 255)}, Size = 0.3, Rate = 10, Speed = {1, 2}, Transparency = 0.3, Accel = Vector3.new(0, 6, 0)}},
	{Zone = "Volcano", Name = "Ember Trail", StrengthMult = 8,
		Colors = {C(255, 110, 62), C(180, 20, 10)}, Core = C(255, 230, 120), Light = 0.9,
		Particles = {Texture = M.FIRE, Colors = {C(255, 200, 80), C(255, 90, 30), C(120, 20, 10)}, Size = 0.45, Rate = 12, Speed = {1.5, 3}, Accel = Vector3.new(0, 5, 0), Light = 1}},
	{Zone = "Narmek", Name = "Galaxy Trail", StrengthMult = 9,
		Colors = {C(176, 117, 255), C(255, 80, 200), C(40, 10, 120)}, Core = C(240, 220, 255), Light = 0.8,
		Particles = {Texture = M.SPARKLE, Colors = {C(255, 255, 255), C(200, 140, 255), C(255, 100, 220)}, Size = 0.3, Rate = 12, Speed = {0.5, 2}, Spin = 180, Light = 1}},
	{Zone = "Toyland", Name = "Confetti Trail", StrengthMult = 10,
		Colors = {C(255, 80, 80), C(255, 220, 60), C(80, 230, 90), C(70, 200, 255), C(120, 90, 255), C(255, 120, 235)}, Core = C(255, 255, 255), Light = 0.5,
		Particles = {Texture = M.SPARKLE, Colors = {C(255, 80, 80), C(255, 220, 60), C(80, 230, 90), C(70, 200, 255), C(255, 120, 235)}, Size = 0.34, Rate = 14, Speed = {1, 3}, Accel = Vector3.new(0, -4, 0), Spin = 240}},
	{Zone = "Neon", Name = "Cyber Trail", StrengthMult = 11,
		Colors = {C(58, 255, 207), C(255, 60, 220)}, Core = C(255, 255, 255), Light = 1,
		Particles = {Texture = M.SPARKLE, Colors = {C(58, 255, 207), C(255, 60, 220)}, Size = 0.3, Rate = 10, Speed = {1, 2.5}, Light = 1, Spin = 300}},
}

local BY_ZONE = {}
for _, entry in ipairs(M.TRAILS) do BY_ZONE[entry.Zone] = entry end

function M.List()
	return M.TRAILS
end

function M.Get(zone)
	if type(zone) ~= "string" then return nil end
	return BY_ZONE[zone]
end

--.. the per-rep multiplier the equipped trail gives (GymService.TrailMultiplier); 1 for none / unknown
function M.StrengthMultOf(zone)
	local entry = M.Get(zone)
	local mult = entry and tonumber(entry.StrengthMult)
	if mult and mult > 0 then return mult end
	return 1
end

--.. display helpers for the Index panel
function M.NameOf(zone)
	local entry = M.Get(zone)
	return entry and entry.Name or (tostring(zone) .. " Trail")
end

local function sequence(colors)
	if #colors == 1 then return ColorSequence.new(colors[1]) end
	local keys = {}
	for i, color in ipairs(colors) do
		keys[i] = ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color)
	end
	return ColorSequence.new(keys)
end

local function numbers(a, b)
	return NumberSequence.new({NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b)})
end

local function stamp(inst, zone)
	inst:SetAttribute("CollectionTrailZone", zone)
	return inst
end

local function attachment(root, name, position, zone)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	a.Parent = root
	return stamp(a, zone)
end

--.. everything this module put on the character's root (never touches a carried cucumber's own trail)
function M.Clear(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	for _, child in ipairs(root:GetChildren()) do
		if child:GetAttribute("CollectionTrailZone") ~= nil or child.Name:sub(1, 15) == "CollectionTrail" then child:Destroy() end
	end
end

--.. builds the zone's trail on the character; returns the ribbon Trail (nil = unknown zone / no root)
function M.Wear(character, zone)
	local def = M.Get(zone)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (def and root) then return nil end
	M.Clear(character)
	local light = def.Light or 0.4
	--.. wide soft ribbon down the back
	local top = attachment(root, "CollectionTrailTop", Vector3.new(0, 0.9, 0.45), zone)
	local bottom = attachment(root, "CollectionTrailBottom", Vector3.new(0, -0.9, 0.45), zone)
	local ribbon = Instance.new("Trail")
	ribbon.Name = "CollectionTrail"
	ribbon.Attachment0, ribbon.Attachment1 = top, bottom
	ribbon.Color = sequence(def.Colors)
	ribbon.Transparency = numbers(0.25, 1)
	ribbon.WidthScale = numbers(1, 0.2)
	ribbon.Lifetime = def.Lifetime or 0.65
	ribbon.MinLength = 0.1
	ribbon.LightEmission = light
	ribbon.LightInfluence = 0
	ribbon.Brightness = 1 + light
	ribbon.FaceCamera = false
	ribbon.Parent = root
	stamp(ribbon, zone)
	--.. thin bright core
	local coreTop = attachment(root, "CollectionTrailCoreTop", Vector3.new(0, 0.3, 0.46), zone)
	local coreBottom = attachment(root, "CollectionTrailCoreBottom", Vector3.new(0, -0.3, 0.46), zone)
	local core = Instance.new("Trail")
	core.Name = "CollectionTrailCore"
	core.Attachment0, core.Attachment1 = coreTop, coreBottom
	core.Color = ColorSequence.new(def.Core or Color3.new(1, 1, 1))
	core.Transparency = numbers(0.1, 1)
	core.WidthScale = numbers(1, 0.3)
	core.Lifetime = (def.Lifetime or 0.65) * 0.8
	core.MinLength = 0.1
	core.LightEmission = math.min(1, light + 0.4)
	core.LightInfluence = 0
	core.Brightness = 1.5 + light
	core.FaceCamera = false
	core.Parent = root
	stamp(core, zone)
	--.. optional sparkle / dust / ember / bubble emitter behind the player
	local p = def.Particles
	if p then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "CollectionTrailParticles"
		emitter.Texture = p.Texture or M.SPARKLE
		emitter.Color = sequence(p.Colors or def.Colors)
		emitter.Size = numbers(p.Size or 0.3, 0)
		emitter.Transparency = numbers(p.Transparency or 0.15, 1)
		emitter.Lifetime = NumberRange.new(0.5, 0.95)
		emitter.Rate = p.Rate or 8
		emitter.Speed = NumberRange.new((p.Speed or {1, 2})[1], (p.Speed or {1, 2})[2])
		emitter.SpreadAngle = Vector2.new(70, 70)
		emitter.EmissionDirection = Enum.NormalId.Back
		emitter.Acceleration = p.Accel or Vector3.zero
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-(p.Spin or 0), p.Spin or 0)
		emitter.LightEmission = p.Light or 0.6
		emitter.LightInfluence = 0
		emitter.Drag = 1.5
		emitter.LockedToPart = false
		emitter.Parent = root
		stamp(emitter, zone)
	end
	return ribbon
end

return M
