--[[
	WashingMachine  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the WORKING WASHING MACHINE, and through Make() of the DRYER (ReplicatedStorage.FunBehavioursClient.Dryer
	is `require(script.Parent.WashingMachine).Make("Dryer")`). Server half: ServerStorage.FunBehaviours.WashingMachine.
	fun-builds/CONTRACT.md; models = fun-builds/models/build_WashingMachine.py / build_Dryer.py (+ laundrylib.py).
	  * state CycleEnd (server time the CYCLE-second programme ends, 0 = idle): every client plays the same moment of
	    the programme from Kit.Now()
	      washer: FILL (blue water rises behind the glass) -> WASH (the drum turns one way, stops, turns back; the clothes
	              ride up the wall and tumble down; the water sloshes; suds) -> DRAIN -> SPIN (fast, clothes pinned to
	              the wall, the machine shakes hardest) -> Ding + a sparkle burst off the glass, the screen says DONE
	      dryer:  the drum turns steadily one way, clothes tumble from high up, a warm glow inside, warm lint puffs out
	              of the side vent while its louvres flutter open -> COOL -> Ding
	    all cycle long the whole machine jiggles (tiny smoothed-noise offsets on every part about its feet - the Hitbox
	    never moves), the Screen counts down (a SurfaceGui adorned to it, in PlayerGui), the timer dial winds up and
	    runs back to zero, the LED pulses and FunAssets.Sfx.WasherLoop hums near it (pitched with the drum speed)
	  * state Door (true = open): the Door* parts swing about Pivot_DoorHinge's vertical axis with a little bounce,
	    and shut with a thunk
	Rest poses come from the build's template (ReplicatedStorage.PlaceableBuilds) relative to its Hitbox, and every part
	is posed relative to the Hitbox each frame (one BulkMoveTo), so a MOVE / sale / break / stream-out mid-cycle is safe:
	cleanup puts every part back where it belongs and restores the Water (size, transparency) and the Led colour.
	The porthole (DoorGlass) must not be Roblox Glass, which hides the Water / suds behind it: it is authored SmoothPlastic,
	and a copy still made of Glass (an older install) is drawn SmoothPlastic while the behaviour runs.
	Clothes that tumble land back near their own authored angle, and slide down when the drum stops with them high up.
	Particle textures are the engine's built-in rbxasset:// ones (no asset ids).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local CYCLE = 15                       -- seconds; keep in step with the server half
local STEP_RANGE = 150                 -- studs camera <-> machine: the per-frame work sleeps beyond this
local FX_RANGE = 120                   -- particles, the done sparkle + ding
local SHAKE_RANGE = 90                 -- the jiggle (it moves every part: only worth it up close)
local NEAR_SOUND = 55                  -- the hum / water loops only play within this
local DOOR_OPEN = math.rad(-105)       -- about the hinge's vertical axis: negative swings the door out toward the front
local DOOR_K, DOOR_C = 70, 8.5         -- door spring (stiffness, damping): a small bounce open, a thunk shut
local DIAL_WIND = math.rad(-150)       -- the timer dial winds to here at the start and runs back to 0 by the end
local BUTTON_SINK = 0.05               -- authored studs the start button sinks when pressed
local PIN_SPEED = 9                    -- rad/s: faster than this the clothes stay pinned to the drum wall
local FALL_TIME = 0.42                 -- seconds a cloth takes to tumble from high up back to the bottom
local LAND_JITTER = 0.3                -- rad: a cloth lands within this of its own authored angle
local SETTLE = 1.25                    -- rad from the bottom: higher than this when the drum stops, a cloth slides down
local SHAKE_MOVE = 0.08                -- studs (x Scale) of the jiggle at full strength (noise is about +-0.5 of it)
local SHAKE_TILT = math.rad(1.1)       -- tilt about the feet at full strength
local DONE_SHOW = 3                    -- seconds the screen blinks DONE
local WATER_SHOWN = 0.42               -- Water transparency while there is water in the drum
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local TAU = 2 * math.pi

--..Programmes (t = seconds into the cycle)..--
local function Smooth(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

--.. washer timeline
local FILL = 1.4                       -- water in over 0..FILL
local WASH0, HALF = 0.6, 2.2           -- agitation starts at WASH0; the drum reverses every HALF seconds
local WASH1 = WASH0 + 4 * HALF         -- 9.4: two back-and-forths, ends at rest
local SPIN0, SPIN_UP, SPIN1, SPIN_DOWN = 10.6, 1.2, 13.8, 0.8
local AGITATE, SPIN = 4.2, 22          -- rad/s
--.. dryer timeline
local DRY, DRY_UP, COOL0, DRY_DOWN0, DRY_DOWN1 = 4.4, 1.2, 11.5, 13.4, 14.6

local KINDS = {
	Washer = {
		Water = true,
		Screen = Color3.fromRGB(95, 225, 255),
		LedOn = Color3.fromRGB(69, 255, 0),
		Lamp = Color3.fromRGB(175, 225, 255),
		LampBrightness = 1.1,
		Sparkle = ColorSequence.new(Color3.fromRGB(200, 245, 255), Color3.fromRGB(120, 200, 255)),
		IdleWord = "WASH",
		DoneWord = "CLEAN!",
		LiftMin = 1.45, LiftMax = 1.9,  -- radians up the wall before a cloth drops
		LoopVolume = 0.34,
		LoopSfx = {"WasherLoop", "HumLoop"}, -- FunAssets.Sfx names, first one that exists
		Omega = function(t)
			if t < WASH0 then return 0 end
			if t < WASH1 then return AGITATE * math.sin(math.pi * (t - WASH0) / HALF) end
			if t < SPIN0 then return 0 end
			if t < SPIN0 + SPIN_UP then return SPIN * Smooth((t - SPIN0) / SPIN_UP) end
			if t < SPIN1 then return SPIN end
			if t < SPIN1 + SPIN_DOWN then return SPIN * (1 - Smooth((t - SPIN1) / SPIN_DOWN)) end
			return 0
		end,
		Level = function(t)
			if t < WASH1 then return Smooth(t / FILL) end
			return 1 - Smooth((t - WASH1) / (SPIN0 - WASH1))
		end,
		Pouring = function(t)
			return t < FILL or (t >= WASH1 and t < SPIN0)
		end,
		Suds = function(t)
			return t >= FILL and t < WASH1
		end,
		Phase = function(t)
			if t < WASH0 then return "FILL" elseif t < WASH1 then return "WASH" elseif t < SPIN0 then return "DRAIN" end
			return "SPIN"
		end,
		Shake = function(t, w)
			if t >= SPIN0 then return 0.2 + 0.8 * math.abs(w) / SPIN end
			return 0.3 + 0.3 * math.abs(w) / AGITATE
		end,
		Heat = function()
			return 0
		end,
		Pitch = function(w)
			return 0.8 + 0.55 * math.min(1, math.abs(w) / SPIN) + 0.08 * math.min(1, math.abs(w) / AGITATE)
		end,
	},
	Dryer = {
		Lint = true,
		Screen = Color3.fromRGB(255, 176, 70),
		LedOn = Color3.fromRGB(255, 140, 40),
		Lamp = Color3.fromRGB(255, 165, 85),
		LampBrightness = 1.4,
		Sparkle = ColorSequence.new(Color3.fromRGB(255, 240, 190), Color3.fromRGB(255, 190, 110)),
		IdleWord = "DRY",
		DoneWord = "FLUFFY!",
		LiftMin = 1.9, LiftMax = 2.45,  -- a dryer carries the clothes nearly to the top before they drop
		LoopVolume = 0.28,
		LoopSfx = {"DryerLoop", "WasherLoop"}, -- DryerLoop is a wish (notes); WasherLoop until it exists
		Omega = function(t)
			if t < DRY_UP then return DRY * Smooth(t / DRY_UP) end
			if t < DRY_DOWN0 then return DRY end
			if t < DRY_DOWN1 then return DRY * (1 - Smooth((t - DRY_DOWN0) / (DRY_DOWN1 - DRY_DOWN0))) end
			return 0
		end,
		Phase = function(t)
			return t < COOL0 and "DRY" or "COOL"
		end,
		Shake = function(_t, w)
			return 0.15 + 0.2 * math.abs(w) / DRY
		end,
		Heat = function(t) -- warm glow, lint, open louvres 0..1
			if t < COOL0 then return Smooth(t / 1.5) end
			return 1 - Smooth((t - COOL0) / 2)
		end,
		Pitch = function(w)
			return 0.7 + 0.12 * math.min(1, math.abs(w) / DRY)
		end,
	},
}

--..Helpers..--
local function Wrap(a)
	return (a + math.pi) % TAU - math.pi
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

local function Sfx(name, fallback)
	return FunAssets.Sfx[name] or FunAssets.Sfx[fallback] or "Click Sound"
end

--.. the build's template (ReplicatedStorage.PlaceableBuilds/<Category>/<Key>)
local function TemplateOf(model)
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
	return template
end

--.. [part name] = {CFrame (template Hitbox space), Size, Transparency, Color} as shipped, or nil (then the placed
--.. copy's current values are used). Skipped when the template was re-scaled since this copy was placed.
local function Shipped(model)
	local template = TemplateOf(model)
	local hitbox = template and Kit.Hitbox(template)
	if not hitbox or math.abs(Kit.Scale(template) - Kit.Scale(model)) > 1e-3 then return nil end
	local map = {}
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("BasePart") and d ~= hitbox then
			map[d.Name] = {CFrame = hitbox.CFrame:ToObjectSpace(d.CFrame), Size = d.Size, Transparency = d.Transparency, Color = d.Color}
		end
	end
	return map
end

--..Screen (a SurfaceGui on the Screen part's Front face)..--
local function BuildScreen(screen, K, playerGui)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LaundryScreen"
	gui.Adornee = screen
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.MaxDistance = 80
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local bg = Instance.new("Frame")
	bg.Name = "Glass"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = K.Screen:Lerp(Color3.new(0, 0, 0), 0.9)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local function Label(name, pos, size, align)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = pos
		l.Size = size
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = K.Screen
		l.TextXAlignment = align or Enum.TextXAlignment.Center
		l.Text = ""
		l.Parent = bg
		return l
	end
	local big = Label("Time", UDim2.fromScale(0.06, 0.05), UDim2.fromScale(0.88, 0.56))
	local small = Label("Phase", UDim2.fromScale(0.07, 0.63), UDim2.fromScale(0.52, 0.3), Enum.TextXAlignment.Left)

	local barBack = Instance.new("Frame")
	barBack.Name = "Bar"
	barBack.Position = UDim2.fromScale(0.62, 0.71)
	barBack.Size = UDim2.fromScale(0.31, 0.14)
	barBack.BackgroundColor3 = K.Screen:Lerp(Color3.new(0, 0, 0), 0.7)
	barBack.BorderSizePixel = 0
	barBack.Parent = bg
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = K.Screen
	fill.BorderSizePixel = 0
	fill.Parent = barBack

	gui.Parent = playerGui
	return gui, big, small, fill
end

--..Behaviour..--
local function Make(kindName)
	local K = KINDS[kindName] or KINDS.Washer
	local B = {}
	B.StepRange = STEP_RANGE

	function B.Client(model, ctx)
		local s = ctx.Scale
		local hitbox = Kit.Hitbox(model)
		if not hitbox then return end
		local hb0 = hitbox.CFrame
		local origin = Kit.Origin(model)
		local floorH = hb0:ToObjectSpace(origin) -- the authored floor centre + axes, in Hitbox space
		local axesH = floorH.Rotation

		--..Parts + rest poses (Hitbox space)..--
		local shipped = Shipped(model)
		local parts, rest, byName, restInfo = {}, {}, {}, {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= hitbox then
				table.insert(parts, d)
				byName[d.Name] = d
				local t = shipped and shipped[d.Name]
				rest[d] = t and t.CFrame or hb0:ToObjectSpace(d.CFrame)
				restInfo[d] = {Size = t and t.Size or d.Size, Transparency = t and t.Transparency or d.Transparency, Color = t and t.Color or d.Color}
			end
		end
		if #parts == 0 then return end

		--..Pivots (Hitbox space, authored axes)..--
		local function PivotH(name)
			local p = Kit.Pivot(model, name)
			return p and hb0:ToObjectSpace(CFrame.new(p) * origin.Rotation) or nil
		end
		local drumH, hingeH, dialH = PivotH("Drum"), PivotH("DoorHinge"), PivotH("Dial")
		if not (drumH and hingeH) then
			warn("[" .. kindName .. "] " .. model:GetFullName() .. " lacks Pivot_Drum / Pivot_DoorHinge - drum or door stays still")
		end

		--..Groups..--
		local drum, door, dial, cloths, slats, light = {}, {}, {}, {}, {}, {}
		for _, p in ipairs(parts) do
			local n = p.Name
			if drumH and n:sub(1, 9) == "DrumCloth" then
				local rel = drumH:ToObjectSpace(rest[p])
				local pos = rel.Position
				local a0 = math.atan2(pos.X, -pos.Y) -- authored angle from the drum bottom
				table.insert(cloths, {
					Part = p, Rel = rel, A0 = a0, Phi = 0,
					Lift = K.LiftMin + math.random() * (K.LiftMax - K.LiftMin),
					Settle = math.max(SETTLE, math.abs(a0) + LAND_JITTER + 0.05), -- never above where it lands (no loop)
				})
			elseif drumH and n:sub(1, 4) == "Drum" then
				table.insert(drum, {Part = p, Rel = drumH:ToObjectSpace(rest[p])})
			elseif hingeH and n:sub(1, 4) == "Door" then
				table.insert(door, {Part = p, Rel = hingeH:ToObjectSpace(rest[p])})
				table.insert(light, p)
			elseif dialH and (n == "DialKnob" or n == "DialCap" or n == "DialPointer") then
				table.insert(dial, {Part = p, Rel = dialH:ToObjectSpace(rest[p])})
				table.insert(light, p)
			elseif n:sub(1, 8) == "VentSlat" then
				table.insert(slats, p)
			end
		end
		local water = K.Water and byName.Water or nil
		local led = byName.Led
		local button = byName.ButtonStart
		if button then table.insert(light, button) end
		local screen = byName.Screen

		--.. Roblox's Glass material hides every transparent part / particle behind it (the Water, the suds): the porthole
		--.. is authored SmoothPlastic; a copy installed from an older export (Glass) is drawn SmoothPlastic here instead
		local doorGlass = byName.DoorGlass
		local glassWas = doorGlass and doorGlass.Material == Enum.Material.Glass and {Reflectance = doorGlass.Reflectance} or nil
		if glassWas then
			doorGlass.Material = Enum.Material.SmoothPlastic
			doorGlass.Reflectance = math.max(glassWas.Reflectance, 0.15)
		end

		--..Cleanup: every part back where it belongs (relative to where the build IS now)..--
		ctx:OnCleanup(function()
			if glassWas and doorGlass.Parent then
				doorGlass.Material = Enum.Material.Glass
				doorGlass.Reflectance = glassWas.Reflectance
			end
			if not hitbox.Parent then return end
			local hb = hitbox.CFrame
			local list, cfs = {}, {}
			for _, p in ipairs(parts) do
				if p.Parent then
					table.insert(list, p)
					table.insert(cfs, hb * rest[p])
				end
			end
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			if water and water.Parent then
				water.Size = restInfo[water].Size
				water.Transparency = restInfo[water].Transparency -- shipped invisible (1): the broken fade leaves it alone too
			end
			if led and led.Parent then led.Color = restInfo[led].Color end
		end)

		--..Effects host: an invisible local part at the drum centre (authored axes)..--
		local fxCF = drumH and hb0 * drumH or Kit.CFrameToWorld(model, CFrame.new(0, 1.78, -0.96))
		local fx = ctx:Part({Name = "LaundryFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = fxCF})
		local lamp = Instance.new("PointLight")
		lamp.Color = K.Lamp
		lamp.Range = 3.4 * s
		lamp.Brightness = 0
		lamp.Shadows = false
		lamp.Enabled = false
		lamp.Parent = Attach(fx, "Lamp", CFrame.new(0, 0.1 * s, -0.35 * s))

		local glass = Kit.Pivot(model, "DoorCentre")
		local sparkles = Emitter(Attach(fx, "Sparkle", CFrame.new(fx.CFrame:PointToObjectSpace(glass or fx.Position))), {
			Name = "Sparkles",
			Texture = TEX_SPARKLE,
			Color = K.Sparkle,
			Size = Seq(0, 0.35 * s, 1, 0),
			Transparency = Seq(0, 0, 0.7, 0.2, 1, 1),
			Lifetime = NumberRange.new(0.6, 1.0),
			Speed = NumberRange.new(3 * s, 5.5 * s),
			SpreadAngle = Vector2.new(55, 55),
			Acceleration = Vector3.new(0, -4, 0),
			Drag = 2,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-120, 120),
			LightEmission = 1,
			EmissionDirection = Enum.NormalId.Front, -- the attachment has the authored axes: Front = out of the glass
		})

		--.. washer: suds on the water surface
		local suds
		local waterTop = K.Water and Kit.Pivot(model, "WaterTop")
		if waterTop then
			local host = ctx:Part({
				Name = "LaundrySuds", Transparency = 1,
				Size = Vector3.new(1.2 * s, 0.05, 0.8 * s), CFrame = CFrame.new(waterTop) * origin.Rotation,
			})
			suds = Emitter(host, {
				Name = "Suds",
				Texture = TEX_RING,
				Color = ColorSequence.new(Color3.fromRGB(245, 252, 255)),
				Size = Seq(0, 0.08 * s, 1, 0.2 * s),
				Transparency = Seq(0, 0.2, 0.8, 0.3, 1, 1),
				Lifetime = NumberRange.new(0.35, 0.6),
				Rate = 12,
				Speed = NumberRange.new(0.2, 0.5),
				SpreadAngle = Vector2.new(30, 30),
				LightEmission = 0.3,
				ZOffset = 0.2,
				EmissionDirection = Enum.NormalId.Top,
				Shape = Enum.ParticleEmitterShape.Box,
				ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			})
		end

		--.. dryer: warm lint puffs + fluff flecks blowing out of the side vent
		local lint = {}
		if K.Lint then
			local vent, out = Kit.Pivot(model, "Vent"), Kit.Pivot(model, "VentOut")
			if vent and out and (out - vent).Magnitude > 1e-3 then
				local host = ctx:Part({Name = "LaundryVent", Transparency = 1, Size = Vector3.new(0.3, 0.3, 0.3) * s, CFrame = CFrame.lookAt(vent, out)})
				table.insert(lint, Emitter(host, {
					Name = "Puffs",
					Texture = TEX_SMOKE,
					Color = ColorSequence.new(Color3.fromRGB(255, 244, 228), Color3.fromRGB(238, 226, 214)),
					Size = Seq(0, 0.35 * s, 0.5, 1.0 * s, 1, 1.6 * s),
					Transparency = Seq(0, 0.35, 0.5, 0.6, 1, 1),
					Lifetime = NumberRange.new(1.2, 1.9),
					Rate = 6,
					Speed = NumberRange.new(2.2 * s, 3.4 * s),
					SpreadAngle = Vector2.new(18, 18),
					Acceleration = Vector3.new(0, 1.6 * s, 0),
					Drag = 1.4,
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-40, 40),
					LightEmission = 0.15,
					LightInfluence = 0.8,
					EmissionDirection = Enum.NormalId.Front, -- the host looks along the blow direction
				}))
				table.insert(lint, Emitter(host, {
					Name = "Fluff",
					Texture = TEX_SMOKE,
					Color = ColorSequence.new(Color3.fromRGB(250, 250, 255)),
					Size = Seq(0, 0.09 * s, 1, 0.07 * s),
					Transparency = Seq(0, 0.1, 0.8, 0.3, 1, 1),
					Lifetime = NumberRange.new(1.4, 2.2),
					Rate = 7,
					Speed = NumberRange.new(2.5 * s, 4 * s),
					SpreadAngle = Vector2.new(28, 28),
					Acceleration = Vector3.new(0, -1.2, 0),
					Drag = 2.2,
					RotSpeed = NumberRange.new(-200, 200),
					LightInfluence = 0.9,
					EmissionDirection = Enum.NormalId.Front,
				}))
			end
		end

		--..Sounds..--
		local loop = ctx:Sound(fx, Sfx(K.LoopSfx[1], K.LoopSfx[2]), {Name = "Hum", Looped = true, Volume = K.LoopVolume, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND})
		local pour = K.Water and ctx:Sound(fx, Sfx("WaterLoop", "Splash"), {Name = "Water", Looped = true, Volume = 0.26, RollOffMinDistance = 6, RollOffMaxDistance = 45}) or nil
		local ding = ctx:Sound(fx, Sfx("Ding", "Click"), {Name = "Ding", Volume = 0.6, RollOffMaxDistance = 80})
		local click = ctx:Sound(fx, Sfx("Click", "Click"), {Name = "Click", Volume = 0.45, RollOffMaxDistance = 40})
		local doorOpenSound = ctx:Sound(fx, Sfx("DoorOpen", "Click"), {Name = "DoorOpen", Volume = 0.45, RollOffMaxDistance = 40})
		local doorCloseSound = ctx:Sound(fx, Sfx("DoorClose", "Click"), {Name = "DoorClose", Volume = 0.5, PlaybackSpeed = 0.85, RollOffMaxDistance = 40})
		local function Play(sound, range)
			if sound and ctx:CameraDistance() <= (range or FX_RANGE) then
				sound.TimePosition = 0
				sound:Play()
			end
		end
		local function SetPlaying(sound, on)
			if not sound then return end
			if on and not sound.IsPlaying then sound:Play() elseif not on and sound.IsPlaying then sound:Stop() end
		end

		--..Screen..--
		local gui, bigLabel, smallLabel, barFill
		if screen then
			local playerGui = ctx.Player:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				gui, bigLabel, smallLabel, barFill = BuildScreen(screen, K, playerGui)
				ctx:Add(gui)
			end
		end

		--..State..--
		local cycleEnd, doorOpen = 0, false
		local doneFor, doneUntil, pressedAt = nil, 0, -10
		local theta, omega, doorAngle, doorVel, dialAngle = 0, 0, 0, 0, 0
		local shakeK, level, lastLevel, lampK, ventOpen = 0, 0, -1, 0, 0
		local dirty, wasBusy = false, false -- dirty: one full pose pass wanted (streamed in with the door open)
		local firstCycle, firstDoor = true, true
		local shown = {}

		local function Done(forEnd)
			doneFor = forEnd
			doneUntil = os.clock() + DONE_SHOW
			if ctx:CameraDistance() <= FX_RANGE then
				Play(ding)
				sparkles:Emit(16)
			end
		end

		local function Clock(now)
			local t = now - (cycleEnd - CYCLE)
			return t, cycleEnd > 0 and t >= 0 and t < CYCLE
		end

		--.. loops + particles on / off (every few tenths of a second, not per frame)
		local function SyncAudio()
			local t, running = Clock(Kit.Now())
			local near = ctx:CameraDistance() <= NEAR_SOUND
			local inFx = ctx:CameraDistance() <= FX_RANGE
			SetPlaying(loop, running and near)
			if pour then SetPlaying(pour, running and near and K.Pouring(t)) end
			if suds then
				local on = running and inFx and K.Suds(t)
				if suds.Enabled ~= on then suds.Enabled = on end
			end
			local heat = running and K.Heat(t) or 0
			for _, e in ipairs(lint) do
				local on = heat > 0.3 and inFx
				if e.Enabled ~= on then e.Enabled = on end
			end
		end

		ctx:OnState("CycleEnd", function(value)
			local v = tonumber(value) or 0
			if not firstCycle then
				if v > 0 and v ~= cycleEnd then
					pressedAt = os.clock()
					Play(click, 45)
				elseif v == 0 and cycleEnd > 0 then
					if Kit.Now() < cycleEnd - 0.3 then
						pressedAt = os.clock()
						Play(click, 45) -- stopped early
					elseif doneFor ~= cycleEnd then
						Done(cycleEnd) -- ended while this client's per-frame step was asleep
					end
				end
			end
			firstCycle = false
			cycleEnd = v
			if v > 0 then doneUntil = 0 end
			SyncAudio()
		end)

		ctx:OnState("Door", function(value)
			local open = value == true
			if firstDoor then
				doorAngle, doorVel = open and DOOR_OPEN or 0, 0 -- streamed in: snap (one pose pass if it is open)
				dirty = open
			elseif open ~= doorOpen then
				Play(open and doorOpenSound or doorCloseSound, 50)
			end
			firstDoor = false
			doorOpen = open
		end)

		ctx:Every(0.3, SyncAudio)

		--..Screen + LED (cheap: only writes what changed)..--
		local function Set(inst, prop, value)
			local key = inst.Name .. prop
			if shown[key] ~= value then
				shown[key] = value
				inst[prop] = value
			end
		end
		local function UpdateScreen(t, running)
			if not gui then return end
			local big, small, bar, alpha
			if running then
				local left = math.clamp(math.ceil(CYCLE - t), 0, 99)
				big = string.format("%d:%02d", math.floor(left / 60), left % 60)
				small = K.Phase(t)
				bar = math.clamp(t / CYCLE, 0, 1)
				alpha = 0
			elseif os.clock() < doneUntil then
				big = "DONE"
				small = K.DoneWord
				bar = 1
				alpha = (math.floor(os.clock() * 3) % 2 == 0) and 0 or 0.6
			else
				big = doorOpen and "OPEN" or "READY"
				small = K.IdleWord
				bar = 0
				alpha = 0.4
			end
			Set(bigLabel, "Text", big)
			Set(smallLabel, "Text", small)
			Set(bigLabel, "TextTransparency", alpha)
			Set(smallLabel, "TextTransparency", math.min(1, alpha + 0.15))
			Set(barFill, "Size", UDim2.fromScale(math.floor(bar * 40 + 0.5) / 40, 1))
		end
		local ledRest = led and restInfo[led].Color
		local function UpdateLed(running)
			if not led then return end
			local c = ledRest
			if running then
				c = K.LedOn:Lerp(Color3.new(1, 1, 1), 0.3 * (0.5 + 0.5 * math.sin(os.clock() * 5)))
			elseif os.clock() < doneUntil then
				c = (math.floor(os.clock() * 4) % 2 == 0) and K.LedOn or ledRest
			end
			if led.Color ~= c then led.Color = c end
		end

		--..Per frame..--
		local cfsAll, cfsLight = {}, {}
		ctx:Step(function(dt, now)
			if not hitbox.Parent then return end
			dt = math.min(dt, 0.05)
			local t, running = Clock(now)
			if cycleEnd > 0 and now >= cycleEnd and doneFor ~= cycleEnd then Done(cycleEnd) end
			UpdateScreen(t, running)
			UpdateLed(running)

			--.. drum speed: the programme while running, a quick spin-down after a stop
			if running then
				omega = K.Omega(t)
			else
				omega -= omega * math.min(1, dt * 3)
				if math.abs(omega) < 0.02 then omega = 0 end
			end
			theta = (theta + omega * dt) % TAU
			if loop.IsPlaying then loop.PlaybackSpeed = K.Pitch(omega) end

			--.. door spring (bounces open, thunks shut against the cabinet)
			local target = doorOpen and DOOR_OPEN or 0
			local doorBusy = math.abs(target - doorAngle) > 0.002 or math.abs(doorVel) > 0.01
			if doorBusy then
				doorVel += (DOOR_K * (target - doorAngle) - DOOR_C * doorVel) * dt
				doorAngle += doorVel * dt
				if doorAngle > 0 then doorAngle, doorVel = 0, 0 end
				if math.abs(target - doorAngle) <= 0.002 and math.abs(doorVel) <= 0.01 then doorAngle, doorVel = target, 0 end
			end

			--.. dial: winds up at the start, runs back with the time left
			local dialTarget = running and DIAL_WIND * (1 - t / CYCLE) or 0
			local dialBusy = math.abs(dialTarget - dialAngle) > 0.003
			if dialBusy then dialAngle += (dialTarget - dialAngle) * math.min(1, dt * 8) end
			local pressing = os.clock() - pressedAt < 0.3

			--.. clothes: ride up the wall with the drum, drop back through the middle (pinned when it spins fast)
			local pinned = math.abs(omega) >= PIN_SPEED
			local falling = false
			for _, c in ipairs(cloths) do
				if c.Fall then
					c.Fall.T += dt
					if c.Fall.T >= FALL_TIME then
						c.Phi = c.Fall.To
						c.Fall = nil
					end
				else
					c.Phi += omega * dt
					local a = Wrap(c.A0 + c.Phi) -- the cloth's angle from the drum bottom
					c.Phi = a - c.A0
					--.. carried past its lift it drops; with the drum still, one left high up the wall slides back down
					local limit = pinned and math.huge or (omega == 0 and c.Settle or c.Lift)
					if math.abs(a) > limit then
						--.. Phi is relative to the authored angle A0: land back near its own spot, so the clothes never pile up
						c.Fall = {T = 0, From = c.Phi, To = (math.random() - 0.5) * 2 * LAND_JITTER, Turn = (math.random() - 0.5) * 3}
					end
				end
				if c.Fall then falling = true end
			end

			--.. water level, shake, glow, louvres
			if water then
				if running then level = K.Level(t) else level -= level * math.min(1, dt * 2.5) end
				if level < 0.004 then level = 0 end
			end
			local wantShake = running and K.Shake(t, omega) or 0
			shakeK += (wantShake - shakeK) * math.min(1, dt * 5)
			if wantShake == 0 and shakeK < 0.004 then shakeK = 0 end
			local heat = running and K.Heat(t) or 0
			lampK += ((running and 1 or 0) * (K.Lint and (0.35 + 0.65 * heat) or 1) - lampK) * math.min(1, dt * 3)
			if lampK < 0.01 then lampK = 0 end
			lamp.Enabled = lampK > 0
			lamp.Brightness = K.LampBrightness * lampK
			ventOpen += (heat - ventOpen) * math.min(1, dt * 4)
			if heat == 0 and ventOpen < 0.003 then ventOpen = 0 end

			local busy = running or falling or shakeK > 0 or level > 0 or omega ~= 0 or ventOpen > 0
			if not (busy or wasBusy or doorBusy or dialBusy or pressing or dirty) then return end
			local full = busy or wasBusy or dirty
			wasBusy = busy
			dirty = false

			--..Poses (Hitbox space)..--
			local pose = {}
			if drumH then
				local d = drumH * CFrame.Angles(0, 0, theta)
				for _, g in ipairs(drum) do pose[g.Part] = d * g.Rel end
				for _, c in ipairs(cloths) do
					if c.Fall then
						local u = c.Fall.T / FALL_TIME
						local a = drumH * CFrame.Angles(0, 0, c.Fall.From) * c.Rel
						local b = drumH * CFrame.Angles(0, 0, c.Fall.To) * c.Rel
						pose[c.Part] = a:Lerp(b, u * u) * CFrame.Angles(0, 0, math.sin(math.pi * u) * c.Fall.Turn)
					else
						pose[c.Part] = drumH * CFrame.Angles(0, 0, c.Phi) * c.Rel
					end
				end
			end
			if water then
				local size = restInfo[water].Size
				if level > 0 then
					--.. the level rises / falls with the bottom held still; the surface tilts with the drum (slosh)
					local h = math.max(0.05, size.Y * level)
					local slosh = 0.16 * math.clamp(omega / AGITATE, -1, 1) + 0.03 * math.sin(os.clock() * 6)
					pose[water] = rest[water] * CFrame.new(0, -(size.Y - h) * 0.5, 0) * CFrame.Angles(0, 0, slosh)
					if math.abs(level - lastLevel) > 0.002 then
						lastLevel = level
						water.Size = Vector3.new(size.X, h, size.Z)
					end
					local tr = level > 0.01 and WATER_SHOWN or restInfo[water].Transparency
					if water.Transparency ~= tr then water.Transparency = tr end
				elseif lastLevel ~= 0 then
					--.. empty (or never filled): the shipped size, pose and (invisible) transparency
					lastLevel = 0
					water.Size = size
					water.Transparency = restInfo[water].Transparency
				end
			end
			if hingeH then
				local h = hingeH * CFrame.Angles(0, doorAngle, 0)
				for _, g in ipairs(door) do pose[g.Part] = h * g.Rel end
			end
			if dialH then
				local d = dialH * CFrame.Angles(0, 0, dialAngle)
				for _, g in ipairs(dial) do pose[g.Part] = d * g.Rel end
			end
			if button then
				local sink = pressing and math.sin(math.min(1, (os.clock() - pressedAt) / 0.3) * math.pi) * BUTTON_SINK * s or 0
				pose[button] = CFrame.new(axesH:VectorToWorldSpace(Vector3.new(0, 0, sink))) * rest[button]
			end
			for i, p in ipairs(slats) do
				local a = ventOpen * (0.7 + 0.12 * math.sin(os.clock() * 21 + i * 1.9))
				pose[p] = rest[p] * CFrame.Angles(0, 0, -a) -- the bottom edge swings out
			end

			--..Jiggle about the feet (never the Hitbox)..--
			local S
			if shakeK > 0 and ctx:CameraDistance() <= SHAKE_RANGE then
				local c = os.clock() * (7 + 9 * shakeK)
				local m = SHAKE_MOVE * s * shakeK
				local r = SHAKE_TILT * shakeK
				S = floorH
					* CFrame.new(math.noise(c, 0.5) * m, math.abs(math.noise(c, 4.5)) * m * 0.6, math.noise(c, 8.5) * m)
					* CFrame.Angles(math.noise(c, 12.5) * r, math.noise(c, 16.5) * r * 0.5, math.noise(c, 20.5) * r)
					* floorH:Inverse()
			end

			--..Move (one bulk call)..--
			local hb = hitbox.CFrame
			local list, cfs = parts, cfsAll
			if not full then list, cfs = light, cfsLight end
			for i, p in ipairs(list) do
				local cf = pose[p] or rest[p]
				cfs[i] = hb * (S and S * cf or cf)
			end
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	end

	return B
end

local M = Make("Washer")
M.Make = Make
M.CYCLE = CYCLE
return M
