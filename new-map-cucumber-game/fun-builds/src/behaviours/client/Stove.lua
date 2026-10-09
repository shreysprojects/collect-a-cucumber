--[[
	Stove  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the WORKING STOVE (server half: ServerStorage.FunBehaviours.Stove; fun-builds/CONTRACT.md;
	model = fun-builds/models/build_Stove.py). Everything here is local and cosmetic, driven by state Fun_On:
	  * the coils (every Burner* part) heat up over ~2 s: they darken to a dull red, turn Neon and ramp up to a
	    red-orange glow with a faint flicker; switched off they cool down over ~3.5 s
	  * a warm haze (heat shimmer particles) rises off every burner that has nothing standing on it
	  * the pan (Pivot_PanTop) spits little oil pops and a wisp of smoke, and FunAssets.Sfx.Sizzle loops while the
	    camera is within NEAR_SOUND studs
	  * the kettle (Pivot_KettleBase -> Pivot_SpoutTip) starts steaming from its spout after ~7 s on
	  * the OvenWindow warms to a glowing orange (the rack + roast silhouettes stay dark in front of it), the
	    PowerLight turns red, and two lights (<= 2 per build) fade in: one over the cooktop, one at the oven door
	  * a click (Sfx.Click) on every switch
	A stove that streams in while already on starts hot, no ramp. (A placed or moved stove always starts OFF:
	the server half re-runs from scratch and resets Fun_On to false.)
	Every build part it recolours (Burner*, OvenWindow, PowerLight: Color + Material) is restored on cleanup
	from the template. Particle textures are the engine's built-in rbxasset:// ones (no asset ids).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local HEAT_UP = 1.8            -- seconds for the coils to go from cold to full glow
local COOL_DOWN = 3.5          -- seconds for coils / oven to fade out
local OVEN_UP = 3.0            -- the oven window warms a little slower
local KETTLE_UP = 7.0          -- seconds on before the kettle steams
local GLOW_SWITCH = 0.12       -- heat at which a glowing part turns Neon (below: its own material, colour darkens to warm)
local COIL_WARM = Color3.fromRGB(96, 30, 20)
local COIL_HOT = Color3.fromRGB(255, 86, 30)
local OVEN_WARM = Color3.fromRGB(74, 34, 16)
local OVEN_HOT = Color3.fromRGB(240, 132, 52)
local POWER_ON = Color3.fromRGB(255, 56, 44)
local COOK_LIGHT = Color3.fromRGB(255, 124, 60)
local OVEN_LIGHT = Color3.fromRGB(255, 150, 72)
local NEAR_SOUND = 45          -- camera studs for the sizzle loop
local AWAKE_RANGE = 140        -- camera studs for any particles / lights
local COVER_RADIUS = 0.5       -- authored studs: a burner this close under the pan / kettle gets no shimmer
local FALLBACK = {             -- authored points (build_Stove.py) if a Pivot_* attribute is missing
	PanTop = Vector3.new(0.95, 3.935, -0.62),
	OvenWindow = Vector3.new(0, 2.0, -1.61),
	Controls = Vector3.new(0, 4.3, 0.855),
}

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

local function Light(parent, color, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = 0
	l.Shadows = false
	l.Enabled = false
	l.Parent = parent
	return l
end

local function SetEnabled(list, on)
	for _, e in ipairs(list) do
		if e.Enabled ~= on then e.Enabled = on end
	end
end

--..Behaviour..--
function B.Client(model, ctx)
	local s = ctx.Scale
	local origin = Kit.Origin(model) -- authored origin, authored axes (positions below are authored * s)

	local function AuthoredPivot(name)
		local v = model:GetAttribute("Pivot_" .. name)
		if typeof(v) == "Vector3" then return v end
		return FALLBACK[name]
	end

	--..Build parts we recolour (restored on cleanup)..--
	local coils = Kit.Parts(model, "Burner")
	local window = Kit.Part(model, "OvenWindow")
	local power = Kit.Part(model, "PowerLight")
	local base = {}
	local function Remember(part)
		if not part or base[part] then return end
		local source = TemplatePart(model, part.Name) or part
		base[part] = {Color = source.Color, Material = source.Material}
	end
	for _, p in ipairs(coils) do Remember(p) end
	Remember(window)
	Remember(power)
	local function Restore(part)
		local b = base[part]
		if b and part.Parent then
			part.Color = b.Color
			part.Material = b.Material
		end
	end
	local function RestoreAll()
		for part in pairs(base) do Restore(part) end
	end
	RestoreAll() -- start from the template look, whatever an earlier run left behind
	ctx:OnCleanup(RestoreAll)
	local windowList = window and {window} or {}

	--..Effects host: an invisible local part at the authored origin..--
	local fx = ctx:Part({Name = "StoveFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = origin})

	--.. heat shimmer: a faint warm haze off every burner nothing stands on
	local panAt, kettleAt, spoutAt = AuthoredPivot("PanTop"), AuthoredPivot("KettleBase"), AuthoredPivot("SpoutTip")
	local shimmers = {}
	for _, coil in ipairs(coils) do
		if coil.Name:sub(-2) ~= "In" then -- the outer coil of each burner (BurnerFL, not BurnerFLIn)
			local centre = origin:PointToObjectSpace(coil.Position) / s -- authored
			local covered = false
			for _, c in ipairs({panAt, kettleAt}) do
				if c and Vector2.new(centre.X - c.X, centre.Z - c.Z).Magnitude < COVER_RADIUS then covered = true end
			end
			if not covered then
				local d = math.max(coil.Size.Y, coil.Size.Z) -- a flat cylinder: axis along X, diameter in Y/Z
				local at = Attach(fx, "Shimmer" .. coil.Name, CFrame.new((centre + Vector3.new(0, 0.06, 0)) * s))
				table.insert(shimmers, Emitter(at, {
					Name = "HeatShimmer",
					Texture = TEX_SMOKE,
					Color = ColorSequence.new(Color3.fromRGB(255, 196, 160)),
					Size = Seq(0, 0.45 * d, 1, 1.1 * d),
					Transparency = Seq(0, 1, 0.25, 0.86, 0.7, 0.92, 1, 1),
					Lifetime = NumberRange.new(0.7, 1.1),
					Rate = 5,
					Speed = NumberRange.new(1.4 * s, 2.2 * s),
					SpreadAngle = Vector2.new(10, 10),
					Acceleration = Vector3.new(0, 0.8 * s, 0),
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-60, 60),
					LightEmission = 0.35,
					LightInfluence = 0.3,
					EmissionDirection = Enum.NormalId.Top,
				}))
			end
		end
	end

	--.. the pan: oil pops + a wisp of smoke from the whole inside, and the sizzle loop
	local panFx, sizzle = {}, nil
	if panAt then
		local panPart = ctx:Part({
			Name = "StovePanFX",
			Transparency = 1,
			Size = Vector3.new(0.72 * s, 0.05, 0.72 * s),
			CFrame = origin * CFrame.new((panAt + Vector3.new(0, 0.06, 0)) * s),
		})
		table.insert(panFx, Emitter(panPart, {
			Name = "OilPops",
			Texture = TEX_SPARK,
			Color = ColorSequence.new(Color3.fromRGB(255, 246, 205)),
			Size = Seq(0, 0.16 * s, 1, 0.05 * s),
			Transparency = Seq(0, 0.05, 0.8, 0.4, 1, 1),
			Lifetime = NumberRange.new(0.25, 0.45),
			Rate = 9,
			Speed = NumberRange.new(3 * s, 5.5 * s),
			SpreadAngle = Vector2.new(38, 38),
			Acceleration = Vector3.new(0, -32, 0),
			LightEmission = 0.8,
			LightInfluence = 0.2,
			EmissionDirection = Enum.NormalId.Top,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		}))
		table.insert(panFx, Emitter(panPart, {
			Name = "PanSmoke",
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(245, 245, 245)),
			Size = Seq(0, 0.3 * s, 1, 1.2 * s),
			Transparency = Seq(0, 1, 0.2, 0.78, 1, 1),
			Lifetime = NumberRange.new(1.0, 1.6),
			Rate = 3,
			Speed = NumberRange.new(0.8 * s, 1.4 * s),
			SpreadAngle = Vector2.new(15, 15),
			Acceleration = Vector3.new(0, 0.6 * s, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-30, 30),
			LightInfluence = 0.8,
			EmissionDirection = Enum.NormalId.Top,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		}))
		sizzle = ctx:Sound(panPart, FunAssets.Sfx.Sizzle, {Name = "Sizzle", Looped = true, Volume = 0.3, RollOffMinDistance = 5, RollOffMaxDistance = NEAR_SOUND})
	end

	--.. the kettle: steam out of the spout (base -> tip is the spout's direction)
	local steam
	if kettleAt and spoutAt and (spoutAt - kettleAt).Magnitude > 0.05 then
		local dir = (spoutAt - kettleAt).Unit
		local right = Vector3.zAxis:Cross(dir)
		if right.Magnitude < 0.1 then right = Vector3.xAxis:Cross(dir) end
		local at = Attach(fx, "KettleSteam", CFrame.fromMatrix(spoutAt * s, right.Unit, dir))
		steam = Emitter(at, {
			Name = "Steam",
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(250, 252, 255)),
			Size = Seq(0, 0.15 * s, 0.5, 0.5 * s, 1, 0.9 * s),
			Transparency = Seq(0, 0.45, 0.6, 0.75, 1, 1),
			Lifetime = NumberRange.new(0.9, 1.4),
			Rate = 6,
			Speed = NumberRange.new(2.2 * s, 3.2 * s),
			SpreadAngle = Vector2.new(8, 8),
			Acceleration = Vector3.new(0, 1.4 * s, 0),
			Drag = 1.2,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
			LightInfluence = 0.8,
			EmissionDirection = Enum.NormalId.Top,
		})
	end

	--.. two lights: over the cooktop (the burners' middle) and in front of the oven window
	local mid = Vector3.new(0, 3.6 * s, 0)
	if #coils > 0 then
		mid = Vector3.zero
		for _, coil in ipairs(coils) do mid += origin:PointToObjectSpace(coil.Position) end
		mid /= #coils
	end
	local cookLight = Light(Attach(fx, "CookLight", CFrame.new(mid + Vector3.new(0, 0.9 * s, 0))), COOK_LIGHT, 7 * s)
	local windowAt = AuthoredPivot("OvenWindow")
	local ovenLight = Light(Attach(fx, "OvenLight", CFrame.new((windowAt + Vector3.new(0, 0, -0.7)) * s)), OVEN_LIGHT, 6 * s)

	local click = ctx:Sound(Attach(fx, "Controls", CFrame.new(AuthoredPivot("Controls") * s)), FunAssets.Sfx.Click, {Name = "Click", Volume = 0.45, RollOffMaxDistance = 40})

	--..State..--
	local on, first = false, true
	local heat, oven, kettle = 0, 0, 0
	local awake, near, sizzling = true, false, false
	local coilsLit, windowLit = false, false

	--.. emitters, lights and the sizzle from the current heat (every frame while awake, and twice a second)
	local function Apply()
		SetEnabled(shimmers, awake and heat > 0.55)
		SetEnabled(panFx, awake and heat > 0.45)
		if steam then
			local want = awake and kettle >= 1
			if steam.Enabled ~= want then steam.Enabled = want end
		end
		cookLight.Enabled = awake and heat > 0.02
		ovenLight.Enabled = awake and oven > 0.02
		if sizzle then
			local want = on and heat > 0.4 and near
			if want ~= sizzling then
				sizzling = want
				if want then sizzle:Play() else sizzle:Stop() end
			end
			if want then sizzle.Volume = 0.3 * math.clamp((heat - 0.4) / 0.4, 0.25, 1) end
		end
	end

	ctx:OnState("On", function(value)
		local now = value == true
		if first then
			first = false
			if now then heat, oven, kettle = 1, 1, 1 end -- streamed in while on: already hot
		elseif now ~= on and ctx:CameraDistance() <= 60 then
			click:Play()
		end
		on = now
		if power then
			if on then
				power.Material = Enum.Material.Neon
				power.Color = POWER_ON
			else
				Restore(power)
			end
		end
		Apply()
	end)

	ctx:Every(0.5, function()
		local d = ctx:CameraDistance()
		awake = d <= AWAKE_RANGE
		near = d <= NEAR_SOUND
		Apply()
	end)

	--.. glow a list of parts: below GLOW_SWITCH their own material darkening toward warm, then Neon warm -> hot
	local function Glow(parts, level, warm, hot, flicker)
		for _, p in ipairs(parts) do
			local b = base[p]
			if level < GLOW_SWITCH then
				p.Material = b.Material
				p.Color = b.Color:Lerp(warm, level / GLOW_SWITCH)
			else
				p.Material = Enum.Material.Neon
				p.Color = warm:Lerp(hot, math.clamp(((level - GLOW_SWITCH) / (1 - GLOW_SWITCH)) ^ 1.3 * flicker, 0, 1))
			end
		end
	end

	--..Per frame: heat ramps, glow, light brightness..--
	local t = 0
	ctx:Step(function(dt)
		t += dt
		if on then
			heat = math.min(1, heat + dt / HEAT_UP)
			oven = math.min(1, oven + dt / OVEN_UP)
			kettle = math.min(1, kettle + dt / KETTLE_UP)
		else
			heat = math.max(0, heat - dt / COOL_DOWN)
			oven = math.max(0, oven - dt / COOL_DOWN)
			kettle = math.max(0, kettle - dt / 2)
		end
		local flicker = 1 + 0.04 * math.sin(t * 7.3) + 0.025 * math.sin(t * 12.9 + 1.3)
		if heat > 0 then
			Glow(coils, heat, COIL_WARM, COIL_HOT, flicker)
			coilsLit = true
		elseif coilsLit then
			coilsLit = false
			for _, p in ipairs(coils) do Restore(p) end
		end
		if window then
			if oven > 0 then
				Glow(windowList, oven, OVEN_WARM, OVEN_HOT, 1 + 0.03 * math.sin(t * 5.1))
				windowLit = true
			elseif windowLit then
				windowLit = false
				Restore(window)
			end
		end
		cookLight.Brightness = 1.1 * heat * flicker
		ovenLight.Brightness = 0.9 * oven
		Apply()
	end)
end

return B
