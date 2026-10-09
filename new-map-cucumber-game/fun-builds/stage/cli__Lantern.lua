--[[
	Lantern  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLights
	Client-only behaviour for the three garden lanterns (no server half: nothing is shared but the clock).
	  Lantern_A PostLantern (x2.1)   Lantern_B PaperLantern (x1.7)   Lantern_C GardenLantern (x1.5)
	  * a warm PointLight (255,190,120, no shadows - it sits inside the glass / paper) on a runtime Attachment at
	    Pivot_<V>_Light, parented to the build part nearest that point (A_Glass / B_Paper / C_Glass), with a
	    gentle flame flicker of Brightness (every frame) and Range (10 Hz)
	  * NIGHT = workspace CyclePhase == "Night" (DayNightCycle) or Lighting.ClockTime < 6.5 / > 18: brighter and a
	    longer range, eased in / out over ~1.5 s; the post lamp (A) also lets a few fireflies drift around its head
	  * the paper lantern (B) sways about Pivot_B_Hang: +/-4 deg over 2.8 s plus a small cross sway, posed every
	    frame from Kit.Now() so every client swings in step; the light rides along on B_Paper
	The swung parts (B_Paper, B_Brass, B_Core, B_CoreTip, B_Tassel) are put back at rest on cleanup, relative to
	the build's CURRENT hitbox (a move re-runs this; a broken build never has its CFrames touched by the server).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local LIGHT_COLOR = Color3.fromRGB(255, 190, 120)
local NIGHT_EASE = 1.5           -- seconds to blend day <-> night
local MAX_RANGE = 60             -- PointLight.Range engine cap
local SWAY_DEG, SWAY_PERIOD = 4, 2.8
local CROSS_DEG, CROSS_PERIOD = 1.2, 4.3
local TEX_DOT = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- soft round glow (engine built-in)
--.. per variant. Ranges are AUTHORED studs (x ctx.Scale); Brightness is absolute
local VARIANTS = {
	A = {DayBrightness = 1.2, NightBrightness = 2.6, DayRange = 5, NightRange = 9.5, Flicker = 0.06, Fireflies = true},
	B = {DayBrightness = 1.0, NightBrightness = 2.2, DayRange = 5, NightRange = 8.5, Flicker = 0.07,
		Hang = "Hang", Swing = {"Brass", "Paper", "Core", "CoreTip", "Tassel"}},
	C = {DayBrightness = 0.9, NightBrightness = 2.0, DayRange = 4, NightRange = 7.5, Flicker = 0.06},
}
--.. the fireflies' drift box around the post lamp head, AUTHORED studs (x ctx.Scale)
local FIREFLY_BOX = Vector3.new(2.2, 1.8, 2.2)

local B = {}
B.StepRange = 200

--..Helpers..--
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

local function Lerp(a, b, t) return a + (b - a) * t end

local function IsNight()
	if workspace:GetAttribute("CyclePhase") == "Night" then return true end
	local clock = Lighting.ClockTime
	return clock < 6.5 or clock > 18
end

--.. a smooth -1..1-ish flame wobble: slow noise + a quicker shimmer (t = server time, same on every client).
--.. math.noise loses precision on ~1e9 inputs (server time), so it gets the time folded into a short cycle
local function Flicker(t, seed, amount)
	local tt = t % 997
	return 1 + amount * (math.noise(tt * 2.3, seed, 0.5) * 1.4 + 0.45 * math.sin(tt * 7.3 + seed))
end

--.. the build part (of this variant) whose centre is nearest a world point
local function NearestPart(model, prefix, point)
	local best, bestDistance
	for _, part in ipairs(Kit.Parts(model, prefix)) do
		local d = (part.Position - point).Magnitude
		if not bestDistance or d < bestDistance then best, bestDistance = part, d end
	end
	return best
end

--.. Pivot_<V>_Light missing (an older template): the flame part, else the hitbox centre
local function FallbackLightPoint(model, prefix)
	for _, name in ipairs({"Flame", "Core"}) do
		local part = Kit.Part(model, prefix .. name)
		if part then return part.Position end
	end
	return Kit.Hitbox(model).Position
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local cfg = VARIANTS[ctx.Variant or "A"] or VARIANTS.A
	local prefix = ctx.Variant and (ctx.Variant .. "_") or ""
	local scale = ctx.Scale
	local seed = (hitbox.Position.X * 0.371 + hitbox.Position.Z * 0.713) % 97

	--..Light..--
	local lightPoint = Kit.Pivot(model, Kit.VName(model, "Light")) or FallbackLightPoint(model, prefix)
	local host = NearestPart(model, prefix, lightPoint)
	if not host then return end
	local lightAt = ctx:Add(Instance.new("Attachment"))
	lightAt.Name = "FunLanternLight"
	lightAt.Position = host.CFrame:PointToObjectSpace(lightPoint)
	lightAt.Parent = host
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Shadows = false -- it sits inside the glass / paper shell, which would swallow a shadowed light
	light.Brightness = cfg.DayBrightness
	light.Range = cfg.DayRange * scale
	light.Parent = lightAt

	--..Fireflies (post lamp, night only)..--
	local fireflies
	if cfg.Fireflies then
		local box = ctx:Part({
			Name = "FunFireflies", Transparency = 1, Size = FIREFLY_BOX * scale,
			CFrame = CFrame.new(lightPoint) * Kit.Origin(model).Rotation,
		})
		fireflies = Instance.new("ParticleEmitter")
		fireflies.Name = "Fireflies"
		fireflies.Texture = TEX_DOT
		fireflies.Rate = 3
		fireflies.Lifetime = NumberRange.new(3, 5)
		fireflies.Speed = NumberRange.new(0.12 * scale, 0.35 * scale)
		fireflies.SpreadAngle = Vector2.new(180, 180)
		fireflies.Acceleration = Vector3.new(0, 0.04 * scale, 0)
		fireflies.Drag = 0.6
		fireflies.RotSpeed = NumberRange.new(0)
		local s = 0.085 * scale -- a firefly pulses twice in its life
		fireflies.Size = NumberSequence.new({kp(0, 0), kp(0.15, s), kp(0.35, s * 0.3), kp(0.55, s * 1.1), kp(0.8, s * 0.4), kp(1, 0)})
		fireflies.Transparency = NumberSequence.new(0.05)
		fireflies.Color = ColorSequence.new(Color3.fromRGB(215, 255, 110), Color3.fromRGB(255, 214, 110))
		fireflies.LightEmission = 1
		fireflies.LightInfluence = 0
		fireflies.Enabled = false
		pcall(function() -- whole-box volume emission (engine shape API); without it they start on the box faces
			fireflies.Shape = Enum.ParticleEmitterShape.Box
			fireflies.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		end)
		fireflies.Parent = box
	end

	--..Paper lantern sway rig..--
	local rig, hangRel
	if cfg.Swing then
		local hang = model:GetAttribute("Pivot_" .. Kit.VName(model, cfg.Hang))
		local parts = {}
		for _, name in ipairs(cfg.Swing) do
			local part = Kit.Part(model, prefix .. name)
			if part then table.insert(parts, part) end
		end
		if typeof(hang) == "Vector3" and #parts > 0 then
			local origin = Kit.Origin(model)
			local hangCF = CFrame.new(origin:PointToWorldSpace(hang * scale)) * origin.Rotation
			hangRel = hitbox.CFrame:ToObjectSpace(hangCF) -- the hang point rides with the hitbox (moves re-run anyway)
			rig = Kit.Rig(parts, hangCF)
		end
	end

	--..Every frame: flicker, night blend, sway..--
	local night = IsNight() and 1 or 0
	local rangeClock = 1
	ctx:Step(function(dt, now)
		local target = IsNight() and 1 or 0
		night += (target - night) * math.min(1, dt * 3 / NIGHT_EASE)
		local f = Flicker(now, seed, cfg.Flicker)
		light.Brightness = Lerp(cfg.DayBrightness, cfg.NightBrightness, night) * f
		rangeClock += dt
		if rangeClock >= 0.1 then
			rangeClock = 0
			light.Range = math.min(MAX_RANGE, Lerp(cfg.DayRange, cfg.NightRange, night) * scale * (1 + (f - 1) * 0.4))
		end
		if fireflies then
			local on = night > 0.5
			if fireflies.Enabled ~= on then fireflies.Enabled = on end
		end
		if rig then
			local swing = math.rad(SWAY_DEG) * math.sin(now * 2 * math.pi / SWAY_PERIOD + seed)
			local cross = math.rad(CROSS_DEG) * math.sin(now * 2 * math.pi / CROSS_PERIOD + seed * 1.7)
			Kit.PoseRig(rig, hitbox.CFrame * hangRel * CFrame.Angles(cross, 0, swing))
		end
	end)

	--..Cleanup: the swung ball back at rest where the build is now..--
	return function()
		if rig and hitbox.Parent then Kit.PoseRig(rig, hitbox.CFrame * hangRel) end
	end
end

return B
