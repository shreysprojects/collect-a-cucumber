--[[---------------------------------------DESCRIPTION------------------------------------------
	Local cosmetic motion for the 24 launch helpers. Poses are recomputed from
	the cached rest transform each frame. Root and Trigger stay put. No uploaded
	animation clips and no authored sound ids beyond the game's existing set.

--------------------------------------------------------------------------------------------]]--

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local launchCatalog = require(ReplicatedStorage.Assets.Modules.Shared.LaunchPropCatalog)
local Audio = require(ReplicatedStorage.Assets.Modules.Client.Audio)

-- helper model name -> Launch / Bounce / Dash, from the catalog's per-mountain sets
local helperKind = {}
for _, set in pairs(launchCatalog.Mountains or {}) do
	if type(set) == "table" then
		for kind, modelName in pairs(set) do
			helperKind[modelName] = kind
		end
	end
end

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local LaunchPropAnimations = {}

local caches = setmetatable({}, { __mode = "k" })
local active = {}
local loopConn = nil
local fxFolder = nil

local WHITE = Color3.new(1, 1, 1)
local MINT = Color3.fromRGB(150, 255, 214)
local GOLD = Color3.fromRGB(255, 196, 64)
local RED = Color3.fromRGB(255, 72, 72)
local ORANGE = Color3.fromRGB(255, 140, 40)
local CYAN = Color3.fromRGB(90, 240, 255)
local VIOLET = Color3.fromRGB(170, 120, 255)
local PASTEL = Color3.fromRGB(255, 170, 214)
local TAN = Color3.fromRGB(214, 186, 140)

local function folder()
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "LocalLaunchPropFX"
	fxFolder.Parent = workspace
	return fxFolder
end

local function clamp01(t)
	return math.clamp(t, 0, 1)
end

local function recoilDistance(t)
	if t < 0.08 then
		return 0.6 * (t / 0.08)
	end
	if t < 0.30 then
		return 0.6 * (1 - (t - 0.08) / 0.22)
	end
	return 0
end

local function bounceLift(t)
	if t < 0.05 then
		return -0.3 * (t / 0.05)
	end
	if t < 0.15 then
		return -0.3 + 0.9 * ((t - 0.05) / 0.10)
	end
	if t < 0.32 then
		return 0.6 * (1 - (t - 0.15) / 0.17)
	end
	return 0
end

local function pop(t, height, rise, settle)
	if t < rise then
		return height * (t / rise)
	end
	local endAt = rise + settle
	if t < endAt then
		return height * (1 - (t - rise) / settle)
	end
	return 0
end

local function envelope(t, a, b)
	if t <= a or t >= b then
		return 0
	end
	local u = (t - a) / (b - a)
	return math.sin(u * math.pi)
end

local function partNamed(cache, name)
	return cache.parts[name]
end

local function restOf(cache, part)
	return part and cache.rest[part]
end

local function remember(model)
	local cache = caches[model]
	if cache then
		return cache
	end
	local parts = {}
	local rest = {}
	local moving = {}
	local movingModel = nil
	local visual = model:FindFirstChild("Visual")
	if visual then
		local movingFolder = visual:FindFirstChild("Moving")
		if movingFolder and movingFolder:IsA("Model") then
			movingModel = movingFolder
		end
	end
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name ~= "Root" and desc.Name ~= "Trigger" then
			parts[desc.Name] = desc
			rest[desc] = {
				CFrame = desc.CFrame,
				Size = desc.Size,
				Color = desc.Color,
				Transparency = desc.Transparency,
			}
			if movingModel and desc:IsDescendantOf(movingModel) then
				table.insert(moving, desc)
			end
		end
	end
	local pivotPart = partNamed({ parts = parts }, "MovingPivot")
	local restPivot = if pivotPart then pivotPart.CFrame else nil
	if restPivot then
		for _, part in moving do
			rest[part].Rel = restPivot:ToObjectSpace(part.CFrame)
		end
	end
	local launchLook = Vector3.new(0, 0, -1)
	local root = model:FindFirstChild("Root")
	local launch = root and root:FindFirstChild("LaunchPoint")
	if launch and launch:IsA("Attachment") then
		local look = launch.WorldCFrame.LookVector
		if look.Magnitude > 0.05 then
			launchLook = look.Unit
		end
	elseif root and root:IsA("BasePart") then
		launchLook = root.CFrame.LookVector
	end
	cache = {
		parts = parts,
		rest = rest,
		moving = moving,
		restPivot = restPivot,
		launchLook = launchLook,
		token = 0,
		up = if restPivot then restPivot.UpVector else Vector3.yAxis,
		ahead = if root and root:IsA("BasePart") then root.CFrame.LookVector else Vector3.new(0, 0, -1),
	}
	caches[model] = cache
	return cache
end

local function snapRest(cache)
	for part, info in cache.rest do
		if part.Parent then
			part.CFrame = info.CFrame
			part.Size = info.Size
			part.Color = info.Color
			part.Transparency = info.Transparency
		end
	end
end

local function offsetMoving(cache, worldOffset, rot)
	if not cache.restPivot then
		return
	end
	local moved = CFrame.new(worldOffset) * cache.restPivot * (rot or CFrame.identity)
	for _, part in cache.moving do
		local info = cache.rest[part]
		if info and info.Rel and part.Parent then
			part.CFrame = moved * info.Rel
		end
	end
end

local function shiftPart(cache, name, worldOffset, rot)
	local part = cache.parts[name]
	local info = restOf(cache, part)
	if not info or not part.Parent then
		return
	end
	part.CFrame = CFrame.new(worldOffset) * info.CFrame * (rot or CFrame.identity)
end

local function tint(cache, name, color, amount)
	local part = cache.parts[name]
	local info = restOf(cache, part)
	if not info or not part.Parent then
		return
	end
	part.Color = info.Color:Lerp(color, amount)
end

local function eachNamed(cache, prefix, fn)
	local i = 1
	while i < 24 do
		local name = prefix .. string.format("%02d", i)
		local part = cache.parts[name]
		if not part then
			break
		end
		fn(part, i)
		i += 1
	end
end

local function burst(position, color, count, texture, life)
	count = math.clamp(math.floor(count), 1, 12)
	local host = Instance.new("Part")
	host.Name = "LaunchPuff"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(position)
	host.Parent = folder()
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture or SPARKLE
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.55
	emitter.Lifetime = NumberRange.new(life or 0.35)
	emitter.Speed = NumberRange.new(3, 9)
	emitter.Size = NumberSequence.new(0.55, 0)
	emitter.Rate = 0
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Parent = host
	emitter:Emit(count)
	Debris:AddItem(host, (life or 0.35) + 0.45)
end

-- One sound per helper kind (SOUNDS.Library HelperLaunch / HelperBounce / HelperDash),
-- 3D at the prop, through the Audio module.
local function playKindSound(position, profile)
	local kind = helperKind[profile]
	local key = if kind == "Bounce" then "HelperBounce" elseif kind == "Dash" then "HelperDash" else "HelperLaunch"
	Audio.PlayAt(key, position)
end

local function ghostPart(cframe, size, color, transparency)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0.4
	part.Size = size
	part.CFrame = cframe
	part.Parent = folder()
	return part
end

local function muzzlePosition(cache, fallback)
	local pivot = cache.parts.MovingPivot
	local muzzle = pivot and pivot:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return fallback
end

local function arrowSweep(cache, t)
	local forward, bright
	if t < 0.20 then
		forward = t / 0.20
		bright = forward
	elseif t < 0.45 then
		forward = 1 - (t - 0.20) / 0.25
		bright = forward
	else
		forward, bright = 0, 0
	end
	local shift = cache.ahead * (2.4 * forward)
	eachNamed(cache, "ArrowL_", function(part)
		local info = cache.rest[part]
		part.CFrame = info.CFrame + shift
		part.Color = info.Color:Lerp(WHITE, bright * 0.7)
	end)
	eachNamed(cache, "ArrowR_", function(part)
		local info = cache.rest[part]
		part.CFrame = info.CFrame + shift
		part.Color = info.Color:Lerp(WHITE, bright * 0.7)
	end)
end

local function spinAround(part, info, origin, axis, angle)
	local rot = CFrame.fromAxisAngle(axis, angle)
	local offset = info.CFrame.Position - origin
	local pos = origin + rot:VectorToWorldSpace(offset)
	local rotation = info.CFrame - info.CFrame.Position
	part.CFrame = CFrame.new(pos) * (rot * rotation)
end

local function fanPairs(cache)
	if cache.fanPairs then
		return cache.fanPairs
	end
	local hubs = {}
	eachNamed(cache, "FanHub_", function(part)
		table.insert(hubs, part)
	end)
	local pairs = {}
	eachNamed(cache, "FanBlade_", function(part)
		local info = cache.rest[part]
		local best, bestDist = nil, math.huge
		for _, hub in hubs do
			local hubInfo = cache.rest[hub]
			local dist = (info.CFrame.Position - hubInfo.CFrame.Position).Magnitude
			if dist < bestDist then
				best, bestDist = hub, dist
			end
		end
		if best then
			table.insert(pairs, { blade = part, hub = best })
		end
	end)
	cache.fanPairs = pairs
	return pairs
end

local function coffinSign(cache)
	if cache.coffinSign then
		return cache.coffinSign
	end
	local lid = cache.parts.Lid
	local info = restOf(cache, lid)
	if not info or not cache.restPivot or not info.Rel then
		cache.coffinSign = 1
		return 1
	end
	local function height(angle)
		local moved = cache.restPivot * CFrame.Angles(angle, 0, 0)
		return (moved * info.Rel).Position.Y
	end
	cache.coffinSign = if height(math.rad(18)) >= height(math.rad(-18)) then 1 else -1
	return cache.coffinSign
end

local function scaleFromBottom(part, info, yScale, xzScale)
	local size = Vector3.new(info.Size.X * xzScale, info.Size.Y * yScale, info.Size.Z * xzScale)
	part.Size = size
	part.CFrame = info.CFrame * CFrame.new(0, (size.Y - info.Size.Y) * 0.5, 0)
end

local profiles = {}

profiles.SnowCannon = function(cache, t, anim)
	offsetMoving(cache, -cache.launchLook * recoilDistance(t))
	if not anim.burst then
		anim.burst = true
		burst(muzzlePosition(cache, anim.position), WHITE, 8, SMOKE, 0.4)
	end
end

profiles.SnowSpring = function(cache, t, anim)
	local lift = bounceLift(t)
	offsetMoving(cache, cache.up * lift)
	eachNamed(cache, "SpringRing_", function(part)
		local info = cache.rest[part]
		part.CFrame = info.CFrame + cache.up * lift * 0.85
	end)
	if not anim.burst then
		anim.burst = true
		burst(anim.position + cache.up * 1.5, WHITE, 6, SMOKE, 0.3)
	end
end

profiles.BlizzardFans = function(cache, t)
	arrowSweep(cache, t)
	local angle = math.rad(540) * clamp01(t / 0.5)
	for _, pair in fanPairs(cache) do
		local hubInfo = cache.rest[pair.hub]
		local bladeInfo = cache.rest[pair.blade]
		local axis = hubInfo.CFrame:VectorToWorldSpace(Vector3.zAxis)
		spinAround(pair.blade, bladeInfo, hubInfo.CFrame.Position, axis, angle)
	end
end

profiles.PresentPopper = function(cache, t, anim)
	offsetMoving(cache, -cache.launchLook * recoilDistance(t))
	local tilt = math.rad(8) * envelope(t, 0, 0.28)
	local bowL = cache.parts.BowLeft
	local bowR = cache.parts.BowRight
	if bowL and cache.rest[bowL] then
		bowL.CFrame = bowL.CFrame * CFrame.Angles(0, 0, tilt)
	end
	if bowR and cache.rest[bowR] then
		bowR.CFrame = bowR.CFrame * CFrame.Angles(0, 0, -tilt)
	end
	if not anim.burst then
		anim.burst = true
		burst(muzzlePosition(cache, anim.position), RED, 4, SPARKLE, 0.35)
		burst(muzzlePosition(cache, anim.position), GOLD, 4, SPARKLE, 0.35)
	end
end

profiles.GiftSpring = function(cache, t)
	offsetMoving(cache, cache.up * pop(t, 0.7, 0.08, 0.24))
end

profiles.SleighBoost = function(cache, t)
	arrowSweep(cache, t)
	local rock = math.rad(8) * envelope(t, 0, 0.4)
	for _, name in { "RunnerTip_01", "RunnerTip_02" } do
		local part = cache.parts[name]
		local info = restOf(cache, part)
		if info then
			local sign = if name == "RunnerTip_01" then 1 else -1
			part.CFrame = info.CFrame * CFrame.Angles(rock * sign, 0, 0)
		end
	end
	local bright = envelope(t, 0, 0.4)
	tint(cache, "BoostGem_01", CYAN, bright)
	tint(cache, "BoostGem_02", CYAN, bright)
end

profiles.GumballCannon = function(cache, t, anim)
	offsetMoving(cache, -cache.launchLook * recoilDistance(t))
	local tank = cache.parts.GumballTank
	local info = restOf(cache, tank)
	if info then
		local squash = envelope(t, 0, 0.16)
		local yScale = 1 - 0.08 * squash
		local xz = math.sqrt(1 / math.max(yScale, 0.5))
		scaleFromBottom(tank, info, yScale, xz)
	end
	if not anim.burst then
		anim.burst = true
		burst(muzzlePosition(cache, anim.position), PASTEL, 8, SPARKLE, 0.4)
	end
end

profiles.JellyBounce = function(cache, t)
	local yScale, xzScale = 1, 1
	if t < 0.08 then
		local u = t / 0.08
		yScale = 1 + (0.7 - 1) * u
		xzScale = 1 + (1.1 - 1) * u
	elseif t < 0.18 then
		local u = (t - 0.08) / 0.10
		yScale = 0.7 + (1.15 - 0.7) * u
		xzScale = 1.1 + (1 - 1.1) * u
	elseif t < 0.36 then
		local u = (t - 0.18) / 0.18
		yScale = 1.15 + (1 - 1.15) * u
		xzScale = 1
	end
	local jelly = cache.parts.Jelly
	local info = restOf(cache, jelly)
	if not info then
		return
	end
	scaleFromBottom(jelly, info, yScale, xzScale)
	local highlight = cache.parts.JellyHighlight
	local highlightInfo = restOf(cache, highlight)
	if highlight and highlightInfo then
		local rel = info.CFrame:PointToObjectSpace(highlightInfo.CFrame.Position)
		local scaled = Vector3.new(rel.X * xzScale, rel.Y * yScale, rel.Z * xzScale)
		highlight.Size = Vector3.new(highlightInfo.Size.X * xzScale, highlightInfo.Size.Y * yScale, highlightInfo.Size.Z * xzScale)
		local relative = info.CFrame:ToObjectSpace(highlightInfo.CFrame)
		highlight.CFrame = jelly.CFrame * CFrame.new(scaled) * (relative - relative.Position)
	end
end

profiles.CandyGate = function(cache, t, anim)
	arrowSweep(cache, t)
	offsetMoving(cache, cache.up * pop(t, 0.2, 0.06, 0.16))
	eachNamed(cache, "CandyStripe_", function(part, index)
		local info = cache.rest[part]
		local bright = envelope(t, (index - 1) * 0.03, 0.12 + (index - 1) * 0.03)
		part.Color = info.Color:Lerp(PASTEL, bright)
	end)
	if not anim.burst then
		anim.burst = true
		burst(anim.position + cache.ahead * 2, PASTEL, 6, SPARKLE, 0.3)
	end
end

profiles.DeckCannon = function(cache, t, anim)
	offsetMoving(cache, -cache.launchLook * recoilDistance(t))
	local angle = 0
	if t < 0.12 then
		angle = -math.rad(12) * (t / 0.12)
	elseif t < 0.30 then
		angle = -math.rad(12) * (1 - (t - 0.12) / 0.18)
	end
	eachNamed(cache, "Wheel_", function(part)
		local info = cache.rest[part]
		part.CFrame = info.CFrame * CFrame.Angles(angle, 0, 0)
	end)
	if not anim.burst then
		anim.burst = true
		burst(muzzlePosition(cache, anim.position), WHITE, 6, SMOKE, 0.35)
	end
end

profiles.PowderPopper = function(cache, t, anim)
	offsetMoving(cache, cache.up * pop(t, 0.7, 0.08, 0.24))
	local flash = if t < 0.08 then t / 0.08 else 0
	tint(cache, "FuseTip", ORANGE, flash)
	tint(cache, "Fuse", GOLD, flash * 0.6)
	if not anim.burst then
		anim.burst = true
		burst(anim.position + cache.up * 2, TAN, 5, SMOKE, 0.35)
		burst(anim.position + cache.up * 2, WHITE, 3, SMOKE, 0.3)
	end
end

profiles.SailBoost = function(cache, t)
	arrowSweep(cache, t)
	local sail = cache.parts.Sail
	local info = restOf(cache, sail)
	if not info then
		return
	end
	local angle = math.rad(10) * envelope(t, 0, 0.42)
	local top = Vector3.new(0, info.Size.Y * 0.5, 0)
	local posed = info.CFrame * CFrame.new(top) * CFrame.Angles(angle, 0, 0) * CFrame.new(-top)
	sail.CFrame = posed
	local stripe = cache.parts.SailStripe
	local stripeInfo = restOf(cache, stripe)
	if stripeInfo then
		stripe.CFrame = posed * info.CFrame:ToObjectSpace(stripeInfo.CFrame)
	end
end

profiles.GhostCannon = function(cache, t, anim)
	offsetMoving(cache, -cache.launchLook * recoilDistance(t))
	local pulse = envelope(t, 0, 0.2)
	tint(cache, "GhostEye_01", MINT, pulse)
	tint(cache, "GhostEye_02", MINT, pulse)
	if not anim.puff then
		anim.puff = ghostPart(CFrame.new(muzzlePosition(cache, anim.position)), Vector3.new(1.4, 1.8, 1.4), MINT, 0.45)
	end
	if anim.puff then
		local u = clamp01(t / 0.4)
		anim.puff.Transparency = 0.45 + 0.55 * u
		anim.puff.CFrame = CFrame.new(muzzlePosition(cache, anim.position) + cache.up * (u * 1.2))
	end
end

profiles.CoffinSpring = function(cache, t)
	local open = 0
	if t < 0.12 then
		open = t / 0.12
	elseif t < 0.36 then
		open = 1 - (t - 0.12) / 0.24
	end
	local angle = math.rad(18) * open * coffinSign(cache)
	offsetMoving(cache, Vector3.zero, CFrame.Angles(angle, 0, 0))
	tint(cache, "GhostMark", MINT, envelope(t, 0, 0.36))
end

profiles.SpiritGate = function(cache, t, anim)
	arrowSweep(cache, t)
	local lift = pop(t, 0.4, 0.1, 0.22)
	for _, name in { "SpiritOrb_01", "SpiritOrb_02" } do
		shiftPart(cache, name, cache.up * lift)
	end
	if not anim.ring then
		anim.ring = ghostPart(CFrame.new(anim.position + cache.up * 4), Vector3.new(1.2, 0.2, 1.2), MINT, 0.35)
	end
	local u = clamp01(t / 0.35)
	anim.ring.Size = Vector3.new(1.2 + u * 8, 0.15, 1.2 + u * 8)
	anim.ring.Transparency = 0.35 + 0.65 * u
end

profiles.MagmaMortar = function(cache, t, anim)
	offsetMoving(cache, -cache.launchLook * recoilDistance(t))
	tint(cache, "HeatBand", ORANGE, envelope(t, 0, 0.28))
	if not anim.burst then
		anim.burst = true
		burst(muzzlePosition(cache, anim.position), ORANGE, 6, SPARKLE, 0.35)
	end
end

profiles.LavaGeyser = function(cache, t, anim)
	local lift = pop(t, 0.5, 0.08, 0.24)
	offsetMoving(cache, cache.up * lift)
	if not anim.jet then
		anim.jet = ghostPart(CFrame.new(anim.position + cache.up * 2), Vector3.new(1.2, 2.2, 1.2), ORANGE, 0.25)
	end
	local u = clamp01(t / 0.32)
	anim.jet.Transparency = 0.25 + 0.75 * u
	anim.jet.Size = Vector3.new(1.2, 2.2 + u * 3, 1.2)
	anim.jet.CFrame = CFrame.new(anim.position + cache.up * (2 + lift + u))
end

profiles.BasaltBooster = function(cache, t, anim)
	arrowSweep(cache, t)
	local bright = envelope(t, 0, 0.4)
	tint(cache, "HeatCore_01", ORANGE, bright)
	tint(cache, "HeatCore_02", ORANGE, bright)
	if not anim.streak then
		anim.streak = true
		burst(anim.position + cache.ahead * 3 + cache.up, ORANGE, 4, SMOKE, 0.25)
		burst(anim.position + cache.ahead * 5 + cache.up, ORANGE, 4, SMOKE, 0.25)
	end
end

profiles.RailLauncher = function(cache, t, anim)
	local bright = if t < 0.06 then t / 0.06 elseif t < 0.2 then 1 - (t - 0.06) / 0.14 else 0
	tint(cache, "Rail_01", CYAN, bright)
	tint(cache, "Rail_02", CYAN, bright)
	offsetMoving(cache, -cache.launchLook * recoilDistance(math.max(0, t - 0.06)))
	if t >= 0.06 and not anim.burst then
		anim.burst = true
		burst(muzzlePosition(cache, anim.position), CYAN, 6, SPARKLE, 0.25)
	end
end

profiles.PistonPad = function(cache, t)
	local lift = bounceLift(t)
	offsetMoving(cache, cache.up * lift)
	local piston = cache.parts.Piston
	local info = restOf(cache, piston)
	if info and lift > 0 then
		piston.CFrame = info.CFrame + cache.up * lift
	end
	local pulse = envelope(t, 0, 0.28)
	tint(cache, "PlateStripe_01", CYAN, pulse)
	tint(cache, "PlateStripe_02", CYAN, pulse)
end

profiles.TurboGate = function(cache, t)
	arrowSweep(cache, t)
	local panels = {}
	eachNamed(cache, "Panel_", function(part)
		table.insert(panels, part)
	end)
	table.sort(panels, function(a, b)
		return cache.rest[a].CFrame.Position.Y < cache.rest[b].CFrame.Position.Y
	end)
	local pairs = math.max(1, math.floor(#panels / 2))
	for index, part in panels do
		local info = cache.rest[part]
		local pair = math.floor((index - 1) / 2)
		local startAt = pair * (0.18 / pairs)
		local bright = envelope(t, startAt, startAt + 0.12)
		part.Color = info.Color:Lerp(CYAN, bright)
	end
end

profiles.OrbitalCannon = function(cache, t, anim)
	offsetMoving(cache, -cache.launchLook * recoilDistance(t))
	tint(cache, "Orb", VIOLET, envelope(t, 0, 0.3))
	local orbit = cache.parts.Orbit
	if orbit and orbit.Parent then
		local tilt = math.rad(12) * envelope(t, 0, 0.36)
		orbit.CFrame = orbit.CFrame * CFrame.Angles(0, 0, tilt)
	end
	if not anim.burst then
		anim.burst = true
		burst(muzzlePosition(cache, anim.position), VIOLET, 8, SPARKLE, 0.3)
	end
end

profiles.GravityPad = function(cache, t, anim)
	local lift = pop(t, 0.6, 0.12, 0.28)
	local tilt = math.rad(4) * envelope(t, 0, 0.4)
	offsetMoving(cache, cache.up * lift, CFrame.Angles(tilt, 0, 0))
	if not anim.ring then
		anim.ring = ghostPart(CFrame.new(anim.position + cache.up * 0.8), Vector3.new(2, 0.15, 2), VIOLET, 0.4)
	end
	local u = clamp01(t / 0.4)
	anim.ring.Size = Vector3.new(2 + u * 10, 0.12, 2 + u * 10)
	anim.ring.Transparency = 0.4 + 0.6 * u
end

profiles.WarpGate = function(cache, t, anim)
	arrowSweep(cache, t)
	local lights = {}
	eachNamed(cache, "PortalLight_", function(part)
		table.insert(lights, part)
	end)
	local count = math.max(#lights, 1)
	local chase = clamp01(t / 0.3)
	for index, part in lights do
		local info = cache.rest[part]
		local phase = (index - 1) / count
		local delta = math.abs(chase - phase)
		delta = math.min(delta, 1 - delta)
		local bright = math.clamp(1 - delta * count, 0, 1)
		part.Color = info.Color:Lerp(VIOLET, bright)
	end
	if not anim.ripple then
		anim.ripple = ghostPart(CFrame.new(anim.position + cache.up * 5), Vector3.new(6, 6, 0.2), VIOLET, 0.55)
	end
	local u = clamp01(t / 0.3)
	anim.ripple.Transparency = 0.55 + 0.45 * u
	local origin = anim.position + cache.up * 5 + cache.ahead * (u * 4 - 2)
	local ahead = cache.ahead
	if ahead.Magnitude > 0.05 then
		anim.ripple.CFrame = CFrame.lookAt(origin, origin + ahead)
	end
end

local DURATION = {
	SnowCannon = 0.36,
	SnowSpring = 0.36,
	BlizzardFans = 0.55,
	PresentPopper = 0.36,
	GiftSpring = 0.36,
	SleighBoost = 0.48,
	GumballCannon = 0.36,
	JellyBounce = 0.4,
	CandyGate = 0.48,
	DeckCannon = 0.36,
	PowderPopper = 0.36,
	SailBoost = 0.48,
	GhostCannon = 0.42,
	CoffinSpring = 0.4,
	SpiritGate = 0.48,
	MagmaMortar = 0.36,
	LavaGeyser = 0.36,
	BasaltBooster = 0.48,
	RailLauncher = 0.4,
	PistonPad = 0.36,
	TurboGate = 0.48,
	OrbitalCannon = 0.4,
	GravityPad = 0.45,
	WarpGate = 0.48,
}

local function clearEffects(anim)
	for _, key in { "puff", "ring", "jet", "ripple" } do
		local inst = anim[key]
		if typeof(inst) == "Instance" then
			inst:Destroy()
		end
		anim[key] = nil
	end
end

local function stepOneFixed(model, anim, now)
	if anim.token ~= anim.cache.token or not model.Parent then
		clearEffects(anim)
		active[model] = nil
		return
	end
	local t = now - anim.t0
	if t >= anim.duration then
		snapRest(anim.cache)
		clearEffects(anim)
		active[model] = nil
		if anim.onDone then
			anim.onDone(anim.propId)
		end
		return
	end
	snapRest(anim.cache)
	local fn = profiles[anim.profile]
	if not fn then
		return
	end
	local ok, err = pcall(fn, anim.cache, t, anim)
	if not ok then
		snapRest(anim.cache)
		clearEffects(anim)
		active[model] = nil
		warn("[CLIENT]: Launch prop animation failed:", anim.profile, err)
	end
end

local function ensureLoop()
	if loopConn then
		return
	end
	loopConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local any = false
		for model, anim in active do
			any = true
			stepOneFixed(model, anim, now)
		end
		if not any and loopConn then
			loopConn:Disconnect()
			loopConn = nil
		end
	end)
end

function LaunchPropAnimations.remember(model)
	if typeof(model) == "Instance" then
		remember(model)
	end
end

function LaunchPropAnimations.forget(model)
	local anim = active[model]
	if anim then
		clearEffects(anim)
		active[model] = nil
	end
	caches[model] = nil
end

function LaunchPropAnimations.play(model, profile, position, propId, onDone)
	if typeof(model) ~= "Instance" or not model.Parent then
		return
	end
	local cache = remember(model)
	cache.token += 1
	local token = cache.token
	snapRest(cache)
	local previous = active[model]
	if previous then
		clearEffects(previous)
	end
	active[model] = {
		token = token,
		cache = cache,
		t0 = os.clock(),
		duration = DURATION[profile] or 0.45,
		profile = profile,
		position = position,
		propId = propId,
		onDone = onDone,
	}
	playKindSound(position, profile)
	ensureLoop()
end

function LaunchPropAnimations.profileNames()
	local names = {}
	for name in profiles do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return LaunchPropAnimations
