--[[
	HotTub  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the WORKING HOT TUB (server half: ServerStorage.FunBehaviours.HotTub; fun-builds/CONTRACT.md).
	  * always: the water surface shimmers (Water Transparency + Color breathe, the part never moves), the
	    Steam puffs breathe, and soft white steam rises off the water (one box emitter over the surface)
	  * Fun_Jets on: 8 jets on the submerged bench ring stream bubbles up through the water, foam rings spread
	    on the surface above them, the whole surface fizzes, the water turns paler and livelier, an underwater
	    light fades in, the panel lights pulse (dim while off), and FunAssets.Sfx.BubblesLoop plays (looped,
	    quiet, only while the camera is within NEAR_SOUND studs)
	  * "Splash" {Position, Big} from the server (someone sat down / stepped in): spray + a ring + Sfx.Splash
	  * the local character stepping into the water tells the server once per entry (ctx:Send "Splash",
	    checked and rate-limited there) - so jumping in (or bouncing about inside) splashes for everyone
	Every build part it animates (Water, Foam, Steam, PanelLights: Color + Transparency) is restored on cleanup.
	Particle textures are the engine's built-in rbxasset:// ones (no asset ids).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local TEX_STEAM = "rbxasset://textures/particles/smoke_main.dds"
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds" -- soft ring: bubbles + foam rings
local WATER_TOP = 2.25       -- authored surface height (fallback for Pivot_WaterSurface)
local WALL_IN = 2.62         -- authored cavity wall radius
local BENCH_TOP = 1.35       -- authored bench ring top
local FLOOR_TOP = 0.28       -- authored inner floor
local JETS = 8               -- bubble jets around the bench ring
local JET_RADIUS = 2.30      -- authored, on the bench ring (1.98..2.58)
local JET_TILT = math.rad(20) -- jets lean in toward the middle
local RING_RADIUS = 2.05     -- authored, foam rings on the surface just inside the jets
local STEAM_HALF = 1.80      -- authored half-side of the square the steam / fizz rise from (inside the 2.62 wall)
local NEAR_SOUND = 55        -- studs camera <-> tub for the bubbles loop
local AWAKE_RANGE = 170      -- studs camera <-> tub for any particles
local BROKEN_FADE = 0.65     -- BuildHealthService's broken transparency (kept on cleanup while Broken)
local WATER_TINT = Color3.fromRGB(175, 236, 250) -- the shimmer / aerated colour the water leans toward
local LAMP_COLOR = Color3.fromRGB(90, 215, 255)
local LAMP_BRIGHTNESS = 1.3
local PANEL_OFF = Color3.fromRGB(38, 70, 86) -- panel lights while the jets are off
local ANIMATED = {"Water", "Foam", "Steam", "PanelLights"}

local B = {}
B.StepRange = 150

--..Helpers..--
--.. the same part on the build's template (ReplicatedStorage.PlaceableBuilds/<Category>/<Key>): authored values
local function TemplatePart(model, name)
	local root = ReplicatedStorage:FindFirstChild("PlaceableBuilds")
	if not root then return nil end
	local key = tostring(Kit.Key(model))
	local category = root:FindFirstChild(tostring(model:GetAttribute("Category")))
	local template = category and category:FindFirstChild(key)
	if not template then
		for _, c in ipairs(root:GetChildren()) do
			template = c:FindFirstChild(key)
			if template then break end
		end
	end
	local part = template and template:FindFirstChild(name, true)
	return (part and part:IsA("BasePart")) and part or nil
end

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
	e.Parent = parent
	return e
end

local function Attach(parent, name, cf)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end

--..Behaviour..--
function B.Client(model, ctx)
	local s = ctx.Scale
	local authored = model:GetAttribute("Pivot_WaterSurface")
	if typeof(authored) ~= "Vector3" then authored = Vector3.new(0, WATER_TOP, 0) end
	local surfaceCF = Kit.CFrameToWorld(model, CFrame.new(authored)) -- water-surface centre, authored axes
	local depth = authored.Y                                          -- authored surface height over the floor

	--..Build parts we animate (restored on cleanup)..--
	local parts, base = {}, {}
	for _, name in ipairs(ANIMATED) do
		local part = Kit.Part(model, name)
		if part then
			local source = TemplatePart(model, name) or part
			parts[name] = part
			base[part] = {Transparency = source.Transparency, Color = source.Color}
		end
	end
	local water, foam, steamMesh, lights = parts.Water, parts.Foam, parts.Steam, parts.PanelLights
	ctx:OnCleanup(function()
		local broken = Kit.IsBroken(model)
		for part, b in pairs(base) do
			part.Color = b.Color
			if broken and b.Transparency < 1 then
				part.Transparency = math.max(b.Transparency, BROKEN_FADE)
			else
				part.Transparency = b.Transparency
			end
		end
	end)

	--..Effects host: one invisible local part lying on the water..--
	local lift = 0.08
	local fx = ctx:Part({
		Name = "HotTubFX",
		Transparency = 1,
		Size = Vector3.new(STEAM_HALF * 2 * s, 0.1, STEAM_HALF * 2 * s),
		CFrame = surfaceCF * CFrame.new(0, lift, 0),
	})
	--.. an authored point (x, y, z) -> this part's space
	local function Local(x, y, z)
		return Vector3.new(x * s, (y - depth) * s - lift, z * s)
	end

	--.. steam: always on, from the whole surface
	local steam = Emitter(fx, {
		Name = "Steam",
		Texture = TEX_STEAM,
		Color = ColorSequence.new(Color3.fromRGB(246, 250, 255)),
		Size = Seq(0, 0.5 * s, 0.4, 1.3 * s, 1, 2.2 * s),
		Transparency = Seq(0, 1, 0.2, 0.8, 0.65, 0.86, 1, 1),
		Lifetime = NumberRange.new(2.6, 3.8),
		Rate = 5,
		Speed = NumberRange.new(0.6 * s, 1.2 * s),
		SpreadAngle = Vector2.new(10, 10),
		Acceleration = Vector3.new(0, 0.5 * s, 0),
		Drag = 0.3,
		WindAffectsDrag = true,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-18, 18),
		LightEmission = 0.1,
		LightInfluence = 0.7,
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})

	--.. jets: bubbles from the bench ring, foam rings on the surface above them
	local jetEmitters = {}
	for i = 0, JETS - 1 do
		local a = (i + 0.5) * 2 * math.pi / JETS -- between the seats (0/90/180/270), never behind a sitter
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local up = Vector3.yAxis * math.cos(JET_TILT) - dir * math.sin(JET_TILT)
		local jetAt = Local(dir.X * JET_RADIUS, BENCH_TOP + 0.05, dir.Z * JET_RADIUS)
		local jet = Attach(fx, "Jet" .. i, CFrame.fromMatrix(jetAt, tangent, up))
		table.insert(jetEmitters, Emitter(jet, {
			Name = "Bubbles",
			Texture = TEX_RING,
			Color = ColorSequence.new(Color3.fromRGB(235, 250, 255)),
			Size = Seq(0, 0.09 * s, 0.6, 0.15 * s, 1, 0.2 * s),
			Transparency = Seq(0, 0.25, 0.85, 0.2, 1, 1),
			Lifetime = NumberRange.new(0.4, 0.58),
			Rate = 5,
			Speed = NumberRange.new(1.3 * s, 2.0 * s),
			SpreadAngle = Vector2.new(16, 16),
			Acceleration = Vector3.new(0, 1.2 * s, 0),
			LightEmission = 0.35,
			LightInfluence = 0.4,
			ZOffset = 0.6, -- draw over the translucent water they rise through
			EmissionDirection = Enum.NormalId.Top,
		}))
		local ring = Attach(fx, "Foam" .. i, CFrame.new(Local(dir.X * RING_RADIUS, depth, dir.Z * RING_RADIUS) + Vector3.new(0, 0.02, 0)))
		table.insert(jetEmitters, Emitter(ring, {
			Name = "FoamRings",
			Texture = TEX_RING,
			Color = ColorSequence.new(Color3.fromRGB(245, 252, 255)),
			Size = Seq(0, 0.25 * s, 1, 1.0 * s),
			Transparency = Seq(0, 0.3, 0.6, 0.55, 1, 1),
			Lifetime = NumberRange.new(0.8, 1.2),
			Rate = 2,
			Speed = NumberRange.new(0.05, 0.08),
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular, -- lies flat on the water
			Rotation = NumberRange.new(0, 360),
			LightEmission = 0.2,
			LightInfluence = 0.5,
			ZOffset = 0.3,
			EmissionDirection = Enum.NormalId.Top,
		}))
	end
	--.. fizz: tiny bubbles popping all over the surface
	table.insert(jetEmitters, Emitter(fx, {
		Name = "Fizz",
		Texture = TEX_RING,
		Color = ColorSequence.new(Color3.fromRGB(240, 252, 255)),
		Size = Seq(0, 0.06 * s, 1, 0.16 * s),
		Transparency = Seq(0, 0.35, 1, 1),
		Lifetime = NumberRange.new(0.25, 0.45),
		Rate = 18,
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(25, 25),
		LightEmission = 0.25,
		ZOffset = 0.3,
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	}))

	--.. splash: a spray + a ring, moved to wherever the splash is and burst with :Emit
	local splashAt = Attach(fx, "Splash", CFrame.new())
	local spray = Emitter(splashAt, {
		Name = "Spray",
		Texture = TEX_STEAM,
		Color = ColorSequence.new(Color3.fromRGB(225, 245, 255)),
		Size = Seq(0, 0.35 * s, 1, 0.12 * s),
		Transparency = Seq(0, 0.15, 0.7, 0.35, 1, 1),
		Lifetime = NumberRange.new(0.45, 0.75),
		Speed = NumberRange.new(7, 11),
		SpreadAngle = Vector2.new(38, 38),
		Acceleration = Vector3.new(0, -45, 0),
		Drag = 0.5,
		Rotation = NumberRange.new(0, 360),
		LightEmission = 0.2,
		ZOffset = 0.3,
		EmissionDirection = Enum.NormalId.Top,
	})
	local splashRing = Emitter(splashAt, {
		Name = "SplashRing",
		Texture = TEX_RING,
		Color = ColorSequence.new(Color3.fromRGB(245, 252, 255)),
		Size = Seq(0, 0.5 * s, 1, 2.2 * s),
		Transparency = Seq(0, 0.2, 1, 1),
		Lifetime = NumberRange.new(0.7, 0.9),
		Speed = NumberRange.new(0.05, 0.08),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Rotation = NumberRange.new(0, 360),
		LightEmission = 0.2,
		ZOffset = 0.3,
		EmissionDirection = Enum.NormalId.Top,
	})

	--.. underwater light (fades in with the jets)
	local lampAt = Attach(fx, "Lamp", CFrame.new(Local(0, FLOOR_TOP + 0.5, 0)))
	local lamp = Instance.new("PointLight")
	lamp.Color = LAMP_COLOR
	lamp.Range = 7 * s
	lamp.Brightness = 0
	lamp.Shadows = false
	lamp.Enabled = false
	lamp.Parent = lampAt

	--..Sounds..--
	local bubbles = ctx:Sound(fx, FunAssets.Sfx.BubblesLoop, {Name = "Bubbles", Looped = true, Volume = 0.28, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND})
	local splashSound = ctx:Sound(fx, FunAssets.Sfx.Splash, {Name = "Splash", Volume = 0.55, RollOffMaxDistance = 70})
	local click = ctx:Sound(fx, FunAssets.Sfx.Click, {Name = "Click", Volume = 0.4, RollOffMaxDistance = 40})
	ctx.HotTubFX = {At = splashAt, Spray = spray, Ring = splashRing, Sound = splashSound}

	--..State..--
	local jetsOn, awake, first = false, true, true
	local function Apply()
		for _, e in ipairs(jetEmitters) do e.Enabled = awake and jetsOn end
		steam.Enabled = awake
		steam.Rate = jetsOn and 9 or 5
		local wantSound = jetsOn and awake and ctx:CameraDistance() <= NEAR_SOUND
		if wantSound and not bubbles.IsPlaying then
			bubbles:Play()
		elseif not wantSound and bubbles.IsPlaying then
			bubbles:Stop()
		end
	end
	ctx:OnState("Jets", function(value)
		local on = value == true
		if not first and on ~= jetsOn and ctx:CameraDistance() <= 60 then click:Play() end
		first = false
		jetsOn = on
		Apply()
	end)
	ctx:Every(0.5, function()
		awake = ctx:CameraDistance() <= AWAKE_RANGE
		Apply()
	end)

	--..Per frame: shimmer, panel, light, stepping in..--
	local blend, phase, checkClock, inside = 0, 0, 0, false
	ctx:Step(function(dt)
		blend += ((jetsOn and 1 or 0) - blend) * math.min(1, dt * 2)
		phase += dt * (1 + 1.5 * blend)
		local wave = math.sin(phase * 1.3) * 0.6 + math.sin(phase * 3.1 + 1.7) * 0.4 -- -1..1, never regular
		if water then
			local b = base[water]
			water.Transparency = math.clamp(b.Transparency + 0.05 * wave - 0.06 * blend, 0, 1)
			water.Color = b.Color:Lerp(WATER_TINT, math.clamp(0.16 + 0.1 * wave + 0.24 * blend, 0, 1))
		end
		if foam then
			foam.Transparency = math.clamp(base[foam].Transparency - 0.2 * blend + 0.06 * wave, 0, 1)
		end
		if steamMesh then
			steamMesh.Transparency = math.clamp(base[steamMesh].Transparency + 0.04 * math.sin(phase * 0.7), 0, 0.98)
		end
		if lights then
			local pulse = 0.5 + 0.5 * math.sin(phase * 5)
			lights.Color = PANEL_OFF:Lerp(base[lights].Color, blend):Lerp(Color3.new(1, 1, 1), 0.3 * pulse * blend)
		end
		lamp.Enabled = blend > 0.02
		lamp.Brightness = LAMP_BRIGHTNESS * blend * (0.9 + 0.1 * wave)

		--.. the local character stepping into the water: one splash per entry (the server checks it)
		checkClock += dt
		if checkClock < 0.15 then return end
		checkClock = 0
		local humanoid, root = ctx:LocalCharacter()
		if not root then
			inside = false
			return
		end
		local rel = surfaceCF:PointToObjectSpace(root.Position)
		local r = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
		local feet = rel.Y - (humanoid.HipHeight + root.Size.Y * 0.5) -- feet height over the surface
		if not inside then
			if r < (WALL_IN - 0.1) * s and feet < -0.1 and feet > -(depth * s + 1) then
				inside = true
				if not humanoid.SeatPart then ctx:Send("Splash", true) end -- sitting down splashes on the server already
			end
		elseif r > WALL_IN * s + 0.6 or feet > 0.8 then
			inside = false
		end
	end)
end

--..Server events..--
function B.OnEvent(_model, action, payload, ctx)
	if action ~= "Splash" or type(payload) ~= "table" or typeof(payload.Position) ~= "Vector3" then return end
	local fx = ctx.HotTubFX
	if not fx or ctx:CameraDistance() > AWAKE_RANGE then return end
	fx.At.WorldPosition = payload.Position + Vector3.new(0, 0.05, 0)
	fx.Spray:Emit(payload.Big and 22 or 14)
	fx.Ring:Emit(payload.Big and 3 or 2)
	fx.Sound.PlaybackSpeed = 0.92 + math.random() * 0.18
	fx.Sound.TimePosition = 0
	fx.Sound:Play()
end

return B
