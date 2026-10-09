--[[
	Fireplace  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package HomeHearth
	Client half of the WORKING FIREPLACE (server half: ServerStorage.FunBehaviours.Fireplace; fun-builds/CONTRACT.md).
	Everything is drawn from state Fun_Lit (true / false) through one "heat" value (0 cold .. 1 blazing) that
	rises over FADE_IN s when the fire is lit and sinks over FADE_OUT s when it is put out, so the embers and the
	light die down slowly instead of snapping off:
	  * Fire instances on the log pile (Pivot_Fire) + a spark emitter; on while lit
	  * one warm PointLight just in front of the opening (Pivot_Light, Range ~20, shadows on) whose Brightness
	    flickers every frame and Range at 10 Hz (a flame wobble from Kit.Now(), the same on every client)
	  * the Ember* parts (coal bed + seams on the logs) turn Neon and flicker orange / deep red with the heat
	  * the three mantel candles (CandleFlame1..3, authored invisible) light one after another, flames flicker
	    (their SpecialMesh Scale); they go out with the fire
	  * a thin plume of smoke rises from the chimney crown (Pivot_Chimney) while it burns
	  * FunAssets.Sfx.FireLoop crackles (looped, volume follows the heat) while the camera is within NEAR_SOUND
	  * lighting it: Sfx.FireIgnite (match strike + flare) + a burst of sparks; putting it out: Sfx.FireOut (blow-out
	    puff) + a puff of smoke (both fall back to Sfx.Whoosh if the ids are ever removed)
	  * always: the mantel clock's hands (ClockHour / ClockMinute, about Pivot_ClockCentre) show the game's time
	    (Lighting.ClockTime, the same clock the GrandfatherClock reads, so every clock on a plot and every player
	    agree; it snaps when the day / night cycle jumps); the picture frame shows one of FunAssets.Pictures (if
	    any) instead of its painted landscape
	Every build part it touches (Ember* Color + Material, CandleFlame* Transparency + mesh Scale, the clock hands'
	CFrame, PicHill / PicSun Transparency) is put back on cleanup. Particle textures are engine built-ins.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local TEX_GLOW = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- soft round dot (sparks)
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRES = { -- Fire instances on the log pile: AUTHORED offset from Pivot_Fire, Size / Heat at scale 1
	{Offset = Vector3.new(0.1, 0, 0), Size = 3.2, Heat = 7},
	{Offset = Vector3.new(-0.55, -0.1, 0.12), Size = 2.2, Heat = 5},
}
local FIRE_COLOR = Color3.fromRGB(255, 140, 40)
local FIRE_SECONDARY = Color3.fromRGB(255, 70, 15)
local LIGHT_COLOR = Color3.fromRGB(255, 150, 70)
local LIGHT_BRIGHTNESS = 2.2
local LIGHT_RANGE = 20       -- studs at scale 1
local MAX_RANGE = 60         -- PointLight.Range engine cap
local FADE_IN = 1.2          -- seconds cold -> full blaze
local FADE_OUT = 3.5         -- seconds full -> cold after "Put out" (the embers glow on a while)
local EMBER_HOT = Color3.fromRGB(255, 128, 36)
local EMBER_DEEP = Color3.fromRGB(226, 52, 18)
local CANDLE_DELAY = 0.35    -- seconds after lighting before the first candle catches
local CANDLE_STAGGER = 0.3   -- seconds between candles
local CANDLE_FLICKER = 0.16  -- flame height wobble (fraction)
local CRACKLE_VOLUME = 0.5
local NEAR_SOUND = 55        -- studs camera <-> fireplace for the crackle loop
local AWAKE_RANGE = 170      -- studs camera <-> fireplace for fire / particles
local SNAP_RANGE = 120       -- a change seen from farther than this snaps (no sounds, no burst)
local BROKEN_FADE = 0.65     -- BuildHealthService's broken transparency (kept on cleanup while Broken)
local FALLBACK = {           -- authored points when a Pivot_* is missing (older template)
	Fire = Vector3.new(0, 0.95, -0.2),
	Light = Vector3.new(0, 1.7, -1.55),
	Chimney = Vector3.new(0, 7.0, 0.25),
}
local CLOCK_HOUR_DEG, CLOCK_MINUTE_DEG = 305, 60 -- the hands' AUTHORED angles (10:10), clockwise from 12 seen from the front
local CLOCK_RATE = 0.1       -- seconds between hand updates (a game minute passes every ~0.6 s by day)

local B = {}
B.StepRange = 180

--..Helpers..--
--.. Seq(t0, v0, t1, v1, ...) -> NumberSequence
local function Seq(...)
	local args = {...}
	local points = {}
	for i = 1, #args, 2 do table.insert(points, NumberSequenceKeypoint.new(args[i], args[i + 1])) end
	return NumberSequence.new(points)
end

local function Emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in pairs(props) do e[k] = v end
	pcall(function() -- whole-box volume emission where the host part has a size (engine shape API)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end)
	e.Parent = parent
	return e
end

--.. a smooth flame wobble around 1: slow noise + a quicker shimmer (t = server time, same on every client)
local function Flicker(t, seed, amount)
	return 1 + amount * (math.noise(t * 2.3, seed, 0.5) * 1.4 + 0.45 * math.sin(t * 7.3 + seed))
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local s = ctx.Scale
	local rotation = Kit.Origin(model).Rotation
	local seed = (hitbox.Position.X * 0.371 + hitbox.Position.Z * 0.713) % 97
	local function Point(name)
		return Kit.Pivot(model, name) or Kit.ToWorld(model, FALLBACK[name])
	end

	--..Build parts we animate (restored on cleanup)..--
	local embers = Kit.Parts(model, "Ember")
	local flames = Kit.Parts(model, "CandleFlame")
	local emberBase, flameBase = {}, {}
	for _, part in ipairs(embers) do emberBase[part] = {Color = part.Color, Material = part.Material} end
	for i, part in ipairs(flames) do
		local mesh = part:FindFirstChildOfClass("SpecialMesh")
		flameBase[part] = {Transparency = part.Transparency, Mesh = mesh, Scale = mesh and mesh.Scale, Seed = seed + i * 3.1}
	end
	local embersHot = false
	local function RestoreEmbers()
		for part, b in pairs(emberBase) do
			if part.Parent then
				part.Color = b.Color
				part.Material = b.Material
			end
		end
	end
	local function CandleOut(part)
		local b = flameBase[part]
		part.Transparency = b.Transparency
		if b.Mesh and b.Scale then b.Mesh.Scale = b.Scale end
	end

	--..Effect hosts: invisible local parts (fire + sparks on the logs, smoke on the chimney)..--
	local firePoint = Point("Fire")
	local host = ctx:Part({
		Name = "FireplaceFire",
		Transparency = 1,
		Size = Vector3.new(2.2, 0.3, 0.8) * s,
		CFrame = CFrame.new(firePoint) * rotation,
	})
	local fires = {}
	for i, f in ipairs(FIRES) do
		local fireHost = ctx:Part({
			Name = "FireplaceFlame" .. i,
			Transparency = 1,
			Size = Vector3.new(0.2, 0.2, 0.2),
			CFrame = host.CFrame * CFrame.new(f.Offset * s),
		})
		local fire = Instance.new("Fire")
		fire.Color = FIRE_COLOR
		fire.SecondaryColor = FIRE_SECONDARY
		fire.Size = math.clamp(f.Size * s, 2, 30)
		fire.Heat = math.clamp(f.Heat * s, 0, 25)
		fire.Enabled = false
		fire.Parent = fireHost
		table.insert(fires, {Fire = fire, Size = f.Size * s})
	end
	--.. flame size follows the heat (half size when cold, full at a blaze); called whenever heat changes or snaps
	local function SizeFires(heat)
		for _, f in ipairs(fires) do f.Fire.Size = math.clamp(f.Size * (0.5 + 0.5 * heat), 2, 30) end
	end
	local sparks = Emitter(host, {
		Name = "Sparks",
		Texture = TEX_GLOW,
		Color = ColorSequence.new(Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 96, 30)),
		Size = Seq(0, 0.13 * s, 0.6, 0.09 * s, 1, 0),
		Transparency = Seq(0, 0, 0.7, 0.2, 1, 1),
		Lifetime = NumberRange.new(0.6, 1.3),
		Rate = 9,
		Speed = NumberRange.new(1.2 * s, 2.6 * s),
		SpreadAngle = Vector2.new(18, 18),
		Acceleration = Vector3.new(0, 0.8 * s, 0),
		Drag = 1.2,
		LightEmission = 1,
		LightInfluence = 0,
		ZOffset = 0.5,
		EmissionDirection = Enum.NormalId.Top,
	})
	local puff = Emitter(host, {
		Name = "Puff",
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(150, 146, 140), Color3.fromRGB(200, 198, 194)),
		Size = Seq(0, 0.7 * s, 1, 2.2 * s),
		Transparency = Seq(0, 0.35, 0.5, 0.55, 1, 1),
		Lifetime = NumberRange.new(1.2, 2),
		Rate = 0,
		Speed = NumberRange.new(1 * s, 2.4 * s),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, 0.6 * s, 0),
		Drag = 0.8,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		LightInfluence = 0.8,
		ZOffset = 0.4,
		EmissionDirection = Enum.NormalId.Top,
	})
	puff.Enabled = true -- Rate 0: bursts only (puff:Emit)

	local chimney = ctx:Part({
		Name = "FireplaceChimney",
		Transparency = 1,
		Size = Vector3.new(1.2, 0.2, 0.8) * s,
		CFrame = CFrame.new(Point("Chimney")) * rotation,
	})
	local smoke = Emitter(chimney, {
		Name = "ChimneySmoke",
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(128, 124, 120), Color3.fromRGB(190, 188, 185)),
		Size = Seq(0, 0.6 * s, 1, 2.6 * s),
		Transparency = Seq(0, 0.55, 0.3, 0.62, 1, 1),
		Lifetime = NumberRange.new(3, 5),
		Rate = 3,
		Speed = NumberRange.new(1.4 * s, 2.2 * s),
		SpreadAngle = Vector2.new(12, 12),
		Acceleration = Vector3.new(0.25, 0.35, 0) * s,
		Drag = 0.4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-15, 15),
		LightInfluence = 0.8,
		WindAffectsDrag = true,
		EmissionDirection = Enum.NormalId.Top,
	})

	--..Light: just in front of the opening, so it spills out into the room..--
	local lightAt = Instance.new("Attachment")
	lightAt.Name = "FireplaceLight"
	lightAt.Position = host.CFrame:PointToObjectSpace(Point("Light"))
	lightAt.Parent = host
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Brightness = 0
	light.Range = math.min(MAX_RANGE, LIGHT_RANGE * s)
	light.Shadows = true
	light.Enabled = false
	light.Parent = lightAt

	--..Sounds..--
	local crackle = ctx:Sound(host, FunAssets.Sfx.FireLoop, {Name = "Crackle", Looped = true, Volume = 0, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND})
	local ignite = ctx:Sound(host, FunAssets.Sfx.FireIgnite or FunAssets.Sfx.Whoosh, {Name = "Ignite", Volume = 0.55, PlaybackSpeed = FunAssets.Sfx.FireIgnite and 1 or 1.1, RollOffMaxDistance = 60})
	local douse = ctx:Sound(host, FunAssets.Sfx.FireOut or FunAssets.Sfx.Whoosh, {Name = "Douse", Volume = 0.45, PlaybackSpeed = FunAssets.Sfx.FireOut and 1 or 0.6, RollOffMaxDistance = 60})

	--..Clock hands: turned about the face centre to the game's time (Lighting.ClockTime)..--
	local hands = {}
	local centre = model:GetAttribute("Pivot_ClockCentre")
	local clockCF = typeof(centre) == "Vector3" and Kit.CFrameToWorld(model, CFrame.new(centre)) or nil
	if clockCF then
		for _, h in ipairs({{"ClockHour", CLOCK_HOUR_DEG, 30}, {"ClockMinute", CLOCK_MINUTE_DEG, 6}}) do
			local part = Kit.Part(model, h[1])
			if part then
				table.insert(hands, {
					Part = part, Deg = h[2], PerUnit = h[3], Hour = h[1] == "ClockHour",
					Rel = clockCF:ToObjectSpace(part.CFrame),   -- about the clock centre (for turning)
					Rest = hitbox.CFrame:ToObjectSpace(part.CFrame), -- about the hitbox (for putting back after a move)
				})
			end
		end
	end
	local shownTime = nil
	local function SetClock()
		local clockTime = tonumber(Lighting.ClockTime) or 12
		if clockTime == shownTime then return end
		shownTime = clockTime
		local hour = clockTime % 12
		local minute = (clockTime * 60) % 60
		for _, h in ipairs(hands) do
			local deg = (h.Hour and hour or minute) * h.PerUnit
			h.Part.CFrame = clockCF * CFrame.Angles(0, 0, math.rad(deg - h.Deg)) * h.Rel
		end
	end

	--..Picture: one of FunAssets.Pictures on the canvas, if there are any..--
	local hidden = {} -- [part] = authored Transparency
	local pictures = type(FunAssets.Pictures) == "table" and FunAssets.Pictures or {}
	local canvas = Kit.Part(model, "PicCanvas")
	if canvas and #pictures > 0 then
		local pick = math.floor(math.abs(hitbox.Position.X) * 7 + math.abs(hitbox.Position.Z) * 13) % #pictures + 1
		local image = pictures[pick]
		if type(image) == "table" then image = image.Id or image.Image end
		if type(image) == "string" or type(image) == "number" then
			local id = tostring(image)
			if tonumber(id) then id = "rbxassetid://" .. id end
			pcall(function()
				local decal = Instance.new("Decal")
				decal.Name = "FireplacePicture"
				decal.Face = Enum.NormalId.Front
				decal.Texture = id
				decal.Parent = canvas
				ctx:Add(decal)
			end)
			for _, name in ipairs({"PicHill", "PicSun"}) do
				local part = Kit.Part(model, name)
				if part then
					hidden[part] = part.Transparency
					part.Transparency = 1
				end
			end
		end
	end

	--..Cleanup: every build part back as authored..--
	ctx:OnCleanup(function()
		RestoreEmbers()
		for part in pairs(flameBase) do
			if part.Parent then CandleOut(part) end
		end
		for _, h in ipairs(hands) do
			if h.Part.Parent and hitbox.Parent then h.Part.CFrame = hitbox.CFrame * h.Rest end
		end
		local broken = Kit.IsBroken(model)
		for part, t in pairs(hidden) do
			if part.Parent then part.Transparency = (broken and t < 1) and math.max(t, BROKEN_FADE) or t end
		end
	end)

	--..State..--
	local lit, heat, awake, first = false, 0, true, true
	local litAt = -math.huge -- os.clock() when it was lit (candles catch one by one after it)
	local function Apply()
		for _, f in ipairs(fires) do f.Fire.Enabled = lit and awake end
		sparks.Enabled = lit and awake
		local wantSound = lit and awake and ctx:CameraDistance() <= NEAR_SOUND
		if wantSound and not crackle.IsPlaying then
			crackle:Play()
		elseif not wantSound and crackle.IsPlaying then
			crackle:Stop()
		end
	end
	ctx:OnState("Lit", function(value)
		local on = value == true
		if on == lit and not first then return end
		local live = not first and ctx:CameraDistance() <= SNAP_RANGE
		first = false
		lit = on
		if live then
			litAt = os.clock()
			if on then
				ignite.TimePosition = 0
				ignite:Play()
				sparks:Emit(18)
			else
				douse.TimePosition = 0
				douse:Play()
				puff:Emit(14)
			end
		else
			heat = on and 1 or 0 -- streamed in / far away: straight to the state, no fanfare
			litAt = -math.huge
			SizeFires(heat)
		end
		Apply()
	end)
	ctx:Every(0.5, function()
		awake = ctx:CameraDistance() <= AWAKE_RANGE
		Apply()
	end)

	--..Per frame: heat, light flicker, embers, candles, clock..--
	local rangeClock, clockClock = 1, 1
	local smokeOn = false
	ctx:Step(function(dt, now)
		--.. heat follows the state
		local target = lit and 1 or 0
		if heat ~= target then
			local step = dt / (lit and FADE_IN or FADE_OUT)
			heat = (target > heat) and math.min(target, heat + step) or math.max(target, heat - step)
			SizeFires(heat)
		end
		if crackle.IsPlaying then crackle.Volume = CRACKLE_VOLUME * heat end

		--.. light (idle while cold)
		if heat > 0.01 then
			local f = Flicker(now, seed, 0.12)
			if not light.Enabled then light.Enabled = true end
			light.Brightness = LIGHT_BRIGHTNESS * heat * f
			rangeClock += dt
			if rangeClock >= 0.1 then
				rangeClock = 0
				light.Range = math.min(MAX_RANGE, LIGHT_RANGE * s * (0.75 + 0.25 * heat) * (1 + (f - 1) * 0.3))
			end
		elseif light.Enabled then
			light.Enabled = false
			light.Brightness = 0
		end

		--.. chimney smoke while it really burns
		local wantSmoke = awake and heat > 0.3
		if wantSmoke ~= smokeOn then
			smokeOn = wantSmoke
			smoke.Enabled = wantSmoke
		end

		--.. embers glow with the heat (Neon from dark charcoal to flickering orange)
		if heat > 0.005 then
			embersHot = true
			for i, part in ipairs(embers) do
				local b = emberBase[part]
				local pulse = 0.5 + 0.5 * math.noise(now * 1.7, seed + i * 1.37, 0.3) * 1.6
				local glow = EMBER_DEEP:Lerp(EMBER_HOT, math.clamp(pulse, 0, 1))
				if part.Material ~= Enum.Material.Neon then part.Material = Enum.Material.Neon end
				part.Color = b.Color:Lerp(glow, math.clamp(heat * 1.15, 0, 1))
			end
		elseif embersHot then
			embersHot = false
			RestoreEmbers()
		end

		--.. candles catch one by one after lighting, and go out with the fire
		local since = os.clock() - litAt
		for i, part in ipairs(flames) do
			local b = flameBase[part]
			local on = lit and since >= CANDLE_DELAY + (i - 1) * CANDLE_STAGGER
			if on then
				if part.Transparency ~= 0 then part.Transparency = 0 end
				if b.Mesh and b.Scale then
					local w = math.noise(now * 3.1, b.Seed, 0.7)
					local h = 1 + CANDLE_FLICKER * (math.noise(now * 4.3, b.Seed, 1.9) * 1.3 + 0.35 * math.sin(now * 11 + b.Seed))
					b.Mesh.Scale = Vector3.new(b.Scale.X * (1 + 0.08 * w), b.Scale.Y * h, b.Scale.Z * (1 + 0.08 * w))
				end
			elseif part.Transparency ~= b.Transparency then
				CandleOut(part)
			end
		end

		--.. the clock (CLOCK_RATE; SetClock skips when the game time hasn't moved)
		if clockCF then
			clockClock += dt
			if clockClock >= CLOCK_RATE then
				clockClock = 0
				SetClock()
			end
		end
	end)
end

return B
