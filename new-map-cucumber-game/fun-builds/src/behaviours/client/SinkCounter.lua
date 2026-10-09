--[[
	SinkCounter  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the WORKING KITCHEN COUNTER (server half: ServerStorage.FunBehaviours.SinkCounter;
	fun-builds/CONTRACT.md; model = fun-builds/models/build_SinkCounter.py). Local and cosmetic, from two states:
	  Fun_Tap (bool)
	    * a translucent water stream (a local cylinder) falls from Pivot_Spout to the water over Pivot_SinkFloor: it
	      grows down from the nozzle when the tap opens and drops away when it closes
	    * a pool of water rises in the basin (the Pivot_PoolA..PoolB box, up to POOL_MAX) and drains when it stops
	    * splash spray + ripple rings where the stream lands, FunAssets.Sfx.WaterLoop while the camera is near
	  Fun_ToastAt (server time the toast pops, 0 = idle) - the whole toaster cycle is timed from it
	    * press: the PopLever slides down, the Toast* slices sink out of sight, the PopSlot* slots glow orange
	      and a wisp of smoke curls out near the end
	    * at ToastAt the slices pop up POP_HEIGHT (0.8) with a little overshoot, golden brown, with
	      Sfx.ToasterPop + Sfx.Ding (only for clients that saw it happen, never late); the lever springs back
	    * POP_HOLD later they slide back down, and fade back to bread colour once they are in
	A counter that streams in while the tap runs starts with a full stream and pool (and one that streams in
	mid-toast jumps straight to the right toaster pose). A placed or moved counter always starts idle: the
	server half re-runs from scratch and resets Fun_Tap to false and Fun_ToastAt to 0.
	Every build part it moves or recolours (Toast*, PopLever: CFrame; Toast*, PopSlot*: Color + Material) goes
	back to its template pose / look on cleanup. Particle textures are built-in rbxasset:// ones.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local TOAST_DELAY = 4        -- = the server half's numbers
local POP_HOLD = 5
local SLIDE_TIME = 0.6
local POP_HEIGHT = 0.8       -- authored studs the toast pops up
local POP_OVERSHOOT = 0.12   -- authored studs it overshoots before settling
local SINK_DEPTH = 0.14      -- authored studs the toast sinks out of sight while toasting
local LEVER_TRAVEL = 0.3     -- authored studs the lever slides down
local PRESS_TIME = 0.25      -- seconds for lever + toast to go down
local UNTOAST_TIME = 1.5     -- seconds for the slices to fade back to bread once they are back in
local STREAM_WIDTH = 0.13    -- authored diameter of the water stream
local STREAM_SPEED = 9       -- authored studs / s the stream front falls (and its tail drops when the tap closes)
local POOL_MAX = 0.2         -- authored depth of water in the basin while the tap runs
local POOL_FILL = 6          -- seconds to fill
local POOL_DRAIN = 3.5       -- seconds to drain
local WATER = Color3.fromRGB(172, 220, 255)
local POOL = Color3.fromRGB(120, 188, 238)
local SLOT_WARM = Color3.fromRGB(90, 26, 12)
local SLOT_HOT = Color3.fromRGB(255, 104, 36)
local TOASTED = Color3.fromRGB(214, 150, 74)
local TOASTED_CRUST = Color3.fromRGB(146, 84, 36)
local NEAR_SOUND = 55        -- camera studs for the running-water loop
local AWAKE_RANGE = 140      -- camera studs for any particles
local FALLBACK = {           -- authored points (build_SinkCounter.py) if a Pivot_* attribute is missing
	Spout = Vector3.new(0, 4.3, -0.1),
	SinkFloor = Vector3.new(0, 2.92, -0.1),
	PoolA = Vector3.new(1.3, 2.92, -0.9),
	PoolB = Vector3.new(-1.3, 2.92, 0.45),
}

local B = {}
B.StepRange = 150

--..Helpers..--
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

local function Smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function EaseOut(x)
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

--..Behaviour..--
function B.Client(model, ctx)
	local s = ctx.Scale
	local origin = Kit.Origin(model) -- authored origin, authored axes (local positions below are authored * s)
	local up = origin.UpVector
	local hitbox = Kit.Hitbox(model)
	local template = TemplateOf(model)
	local templateHitbox = template and Kit.Hitbox(template)

	local function AuthoredPivot(name)
		local v = model:GetAttribute("Pivot_" .. name)
		if typeof(v) == "Vector3" then return v end
		return FALLBACK[name]
	end

	--..Build parts we move / recolour (restored on cleanup)..--
	local toastParts = Kit.Parts(model, "Toast")
	local slots = Kit.Parts(model, "PopSlot")
	local lever = Kit.Part(model, "PopLever")
	local rest, look = {}, {}
	local function Remember(part, pose)
		if not part then return end
		local source = template and template:FindFirstChild(part.Name, true)
		if not (source and source:IsA("BasePart")) then source = nil end
		if pose then
			--.. the rest pose relative to the Hitbox, from the template (safe even if a run ended mid-pop)
			rest[part] = (source and templateHitbox and hitbox) and hitbox.CFrame * templateHitbox.CFrame:ToObjectSpace(source.CFrame) or part.CFrame
		end
		look[part] = {Color = (source or part).Color, Material = (source or part).Material}
	end
	for _, p in ipairs(toastParts) do Remember(p, true) end
	for _, p in ipairs(slots) do Remember(p, false) end
	Remember(lever, true)
	local function RestoreLook(part)
		local l = look[part]
		if l and part.Parent then
			part.Color = l.Color
			part.Material = l.Material
		end
	end
	local function RestoreAll()
		for part, cf in pairs(rest) do
			if part.Parent then part.CFrame = cf end
		end
		for part in pairs(look) do RestoreLook(part) end
	end
	RestoreAll() -- start from the template pose / look, whatever an earlier run left behind
	ctx:OnCleanup(RestoreAll)

	--..Effects host: an invisible local part at the authored origin..--
	local fx = ctx:Part({Name = "SinkFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = origin})

	--..Water: stream + pool + splash..--
	local spout, basin = AuthoredPivot("Spout"), AuthoredPivot("SinkFloor")
	local cornerA, cornerB = AuthoredPivot("PoolA"), AuthoredPivot("PoolB")
	local floorY = math.min(cornerA.Y, cornerB.Y)
	local poolMid = Vector3.new((cornerA.X + cornerB.X) * 0.5, 0, (cornerA.Z + cornerB.Z) * 0.5)
	local poolW, poolD = math.abs(cornerA.X - cornerB.X), math.abs(cornerA.Z - cornerB.Z)
	local stream = ctx:Part({
		Name = "SinkStream",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.SmoothPlastic,
		Color = WATER,
		Reflectance = 0.15,
		Transparency = 1,
		Size = Vector3.new(0.1, STREAM_WIDTH * s, STREAM_WIDTH * s),
		CFrame = origin * CFrame.new(spout * s),
	})
	local pool = ctx:Part({
		Name = "SinkPool",
		Material = Enum.Material.SmoothPlastic,
		Color = POOL,
		Reflectance = 0.2,
		Transparency = 1,
		Size = Vector3.new(poolW * s, 0.05, poolD * s),
		CFrame = origin * CFrame.new(poolMid.X * s, floorY * s, poolMid.Z * s),
	})
	local splashAt = Attach(fx, "Splash", CFrame.new(basin * s))
	local splash = {
		Emitter(splashAt, {
			Name = "Spray",
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(228, 244, 255)),
			Size = Seq(0, 0.14 * s, 1, 0.05 * s),
			Transparency = Seq(0, 0.2, 0.7, 0.4, 1, 1),
			Lifetime = NumberRange.new(0.22, 0.38),
			Rate = 22,
			Speed = NumberRange.new(2.5 * s, 4.5 * s),
			SpreadAngle = Vector2.new(55, 55),
			Acceleration = Vector3.new(0, -40, 0),
			Rotation = NumberRange.new(0, 360),
			LightEmission = 0.3,
			ZOffset = 0.2,
			EmissionDirection = Enum.NormalId.Top,
		}),
		Emitter(splashAt, {
			Name = "Ripples",
			Texture = TEX_RING,
			Color = ColorSequence.new(Color3.fromRGB(240, 250, 255)),
			Size = Seq(0, 0.15 * s, 1, 0.9 * s),
			Transparency = Seq(0, 0.3, 0.6, 0.6, 1, 1),
			Lifetime = NumberRange.new(0.5, 0.75),
			Rate = 4,
			Speed = NumberRange.new(0.05, 0.08),
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular, -- lies flat on the water
			Rotation = NumberRange.new(0, 360),
			LightEmission = 0.25,
			ZOffset = 0.2,
			EmissionDirection = Enum.NormalId.Top,
		}),
	}
	local water = ctx:Sound(splashAt, FunAssets.Sfx.WaterLoop, {Name = "WaterLoop", Looped = true, Volume = 0.45, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND})

	--..Toaster: sounds + a wisp of smoke at the slots..--
	local topAt = Vector3.new(-2.75, 4.9, 0.3) * s
	if #toastParts > 0 then
		topAt = Vector3.zero
		for _, p in ipairs(toastParts) do topAt += origin:PointToObjectSpace(rest[p].Position) end
		topAt /= #toastParts
		topAt += Vector3.new(0, 0.3 * s, 0)
	end
	local toasterAt = Attach(fx, "Toaster", CFrame.new(topAt))
	local toastSmoke = Emitter(toasterAt, {
		Name = "ToastSmoke",
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(215, 215, 215)),
		Size = Seq(0, 0.2 * s, 1, 0.8 * s),
		Transparency = Seq(0, 1, 0.25, 0.75, 1, 1),
		Lifetime = NumberRange.new(1.0, 1.5),
		Rate = 3,
		Speed = NumberRange.new(0.8 * s, 1.3 * s),
		SpreadAngle = Vector2.new(12, 12),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		LightInfluence = 0.8,
		EmissionDirection = Enum.NormalId.Top,
	})
	local popSound = ctx:Sound(toasterAt, FunAssets.Sfx.ToasterPop, {Name = "ToasterPop", Volume = 0.6, RollOffMaxDistance = 50})
	local ding = ctx:Sound(toasterAt, FunAssets.Sfx.Ding, {Name = "Ding", Volume = 0.5, RollOffMaxDistance = 60})
	local click = ctx:Sound(toasterAt, FunAssets.Sfx.Click, {Name = "Click", Volume = 0.45, RollOffMaxDistance = 40})
	local tapClick = ctx:Sound(Attach(fx, "Tap", CFrame.new(spout * s)), FunAssets.Sfx.Click, {Name = "TapClick", Volume = 0.35, RollOffMaxDistance = 35})

	--..State..--
	local tapOn, firstTap = false, true
	local head, tail, level = 0, 0, 0 -- authored studs: stream front / back from the spout, pool depth
	local popAt, firstToast = 0, true
	local awake, near, running = true, false, false

	local function WaterTarget()
		local surface = basin + Vector3.new(0, level, 0)
		local v = surface - spout
		return v.Magnitude, (v.Magnitude > 1e-3 and v.Unit or -Vector3.yAxis)
	end

	ctx:OnState("Tap", function(value)
		local on = value == true
		if firstTap then
			firstTap = false
			if on then
				level = POOL_MAX
				head = WaterTarget()
			end
		elseif on ~= tapOn and ctx:CameraDistance() <= 50 then
			tapClick:Play()
		end
		if on and not tapOn then
			if tail > 0 then head, tail = 0, 0 end -- the last stream is still dropping away: start a fresh one
		end
		tapOn = on
	end)

	ctx:OnState("ToastAt", function(value)
		popAt = tonumber(value) or 0
		if firstToast then
			firstToast = false
		elseif popAt > 0 and math.abs(Kit.Now() - (popAt - TOAST_DELAY)) < 0.6 and ctx:CameraDistance() <= 60 then
			click:Play() -- the lever going down
		end
	end)

	local function Apply()
		local L = WaterTarget()
		local falling = head > 0 and tail < L - 0.02
		local landing = falling and head >= L - 0.02
		for _, e in ipairs(splash) do
			local want = awake and landing
			if e.Enabled ~= want then e.Enabled = want end
		end
		local want = near and falling
		if want ~= running then
			running = want
			if want then water:Play() else water:Stop() end
		end
	end

	ctx:Every(0.5, function()
		local d = ctx:CameraDistance()
		awake = d <= AWAKE_RANGE
		near = d <= NEAR_SOUND
		Apply()
	end)

	--.. the toaster pose at server time `now`: toast offset, lever offset, slot glow, toast tint, smoke
	local function ToasterPose(now)
		if popAt <= 0 then return nil end
		local u = now - popAt
		if u < -TOAST_DELAY - 0.1 or u > POP_HOLD + SLIDE_TIME + UNTOAST_TIME then return nil end
		if u < 0 then
			local e = Smooth((u + TOAST_DELAY) / PRESS_TIME)
			return -SINK_DEPTH * e, -LEVER_TRAVEL * e, Smooth((u + TOAST_DELAY - 0.3) / 1.2), math.clamp((u + TOAST_DELAY) / TOAST_DELAY, 0, 1), u > -2.5
		elseif u < POP_HOLD then
			local off
			if u < 0.12 then
				off = -SINK_DEPTH + (POP_HEIGHT + POP_OVERSHOOT + SINK_DEPTH) * EaseOut(u / 0.12)
			else
				off = POP_HEIGHT + POP_OVERSHOOT * (1 - Smooth((u - 0.12) / 0.23))
			end
			return off, -LEVER_TRAVEL * (1 - Smooth(u / 0.1)), 1 - Smooth(u / 0.8), 1, u < 1.2
		elseif u < POP_HOLD + SLIDE_TIME then
			return POP_HEIGHT * (1 - Smooth((u - POP_HOLD) / SLIDE_TIME)), 0, 0, 1, false
		end
		return 0, 0, 0, 1 - (u - POP_HOLD - SLIDE_TIME) / UNTOAST_TIME, false
	end

	--..Per frame: stream, pool, toaster..--
	local t, posed, prevU = 0, false, nil
	ctx:Step(function(dt, now)
		t += dt

		--..water..--
		local L, dir = WaterTarget()
		if tapOn then
			head = math.min(L, head + dt * STREAM_SPEED)
			tail = 0
			if head >= L - 0.02 then level = math.min(POOL_MAX, level + dt * POOL_MAX / POOL_FILL) end
		else
			if head > 0 then
				head = math.min(L, head + dt * STREAM_SPEED) -- what already left the nozzle keeps falling
				tail = math.min(L, tail + dt * STREAM_SPEED)
				if tail >= L - 0.02 then head, tail = 0, 0 end
			end
			level = math.max(0, level - dt * POOL_MAX / POOL_DRAIN)
		end
		L, dir = WaterTarget()
		head = math.min(head, L)
		local len = head - tail
		if len > 0.03 then
			local top = origin:PointToWorldSpace((spout + dir * tail) * s)
			local bottom = origin:PointToWorldSpace((spout + dir * head) * s)
			local axis = (bottom - top).Unit
			local side = axis:Cross(origin.RightVector)
			if side.Magnitude < 0.1 then side = axis:Cross(origin.LookVector) end
			local w = STREAM_WIDTH * s * (1 + 0.07 * math.sin(t * 21))
			stream.Size = Vector3.new(len * s, w, w)
			stream.CFrame = CFrame.fromMatrix((top + bottom) * 0.5, axis, side.Unit)
			stream.Transparency = 0.32 + 0.08 * math.sin(t * 15 + 1)
		elseif stream.Transparency < 1 then
			stream.Transparency = 1
		end
		if level > 0.004 then
			local h = math.max(0.05, level * s)
			pool.Size = Vector3.new(poolW * s, h, poolD * s)
			pool.CFrame = origin * CFrame.new(poolMid.X * s, (floorY + level) * s - h * 0.5, poolMid.Z * s)
			pool.Transparency = 0.38 + 0.04 * math.sin(t * 3)
		elseif pool.Transparency < 1 then
			pool.Transparency = 1
		end
		splashAt.CFrame = CFrame.new((basin + Vector3.new(0, level + 0.02, 0)) * s)

		--..toaster..--
		local off, leverOff, glow, tint, smoking = ToasterPose(now)
		local u = popAt > 0 and now - popAt or nil
		if prevU and u and prevU < 0 and u >= 0 and u < 0.6 and ctx:CameraDistance() <= 80 then
			popSound:Play()
			task.delay(0.15, function()
				if ctx:Alive() then ding:Play() end
			end)
		end
		prevU = u
		if off then
			posed = true
			for _, p in ipairs(toastParts) do
				p.CFrame = rest[p] + up * (off * s)
				local l = look[p]
				local target = p.Name:sub(-5) == "Crust" and TOASTED_CRUST or TOASTED
				p.Color = l.Color:Lerp(target, math.clamp(tint, 0, 1))
			end
			if lever then lever.CFrame = rest[lever] + up * (leverOff * s) end
			for _, p in ipairs(slots) do
				if glow > 0.05 then
					p.Material = Enum.Material.Neon
					p.Color = SLOT_WARM:Lerp(SLOT_HOT, glow)
				else
					RestoreLook(p)
				end
			end
			local wantSmoke = awake and smoking == true
			if toastSmoke.Enabled ~= wantSmoke then toastSmoke.Enabled = wantSmoke end
		elseif posed then
			posed = false
			RestoreAll()
			toastSmoke.Enabled = false
		end

		Apply()
	end)
end

return B
