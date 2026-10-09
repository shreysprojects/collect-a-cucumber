--[[
	TikiTorch  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLights
	Client-only behaviour for the three torches (no server half: nothing is shared but the clock).
	  TikiTorch_A BambooTorch (x1.5)   TikiTorch_B TikiHead (x1.5)   TikiTorch_C Brazier (x1.4)
	At Pivot_<V>_FlameAnchor (the Blender author's "hang a PointLight / Fire here" point) one local, invisible
	anchor part carries:
	  * a Fire, small, Size / Heat tuned per variant (the brazier burns lower and wider)
	  * a warm PointLight (no shadows: the neon flame meshes around it would block it) that flickers like a
	    real flame - Brightness every frame, Range at 10 Hz - and burns brighter / farther at NIGHT
	    (workspace CyclePhase == "Night" or Lighting.ClockTime < 6.5 / > 18, eased over ~1.5 s)
	  * rising embers (built-in soft glow texture, modest rate)
	  * a quiet crackle loop (FunAssets.Sfx.FireLoop) that only plays while the camera is within NEAR_SOUND studs
	Nothing on the build itself is touched, so there is nothing to restore.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = {Sfx = {}}
pcall(function() FunAssets = require(Modules:WaitForChild("FunAssets", 15)) end)

--..Config..--
local LIGHT_COLOR = Color3.fromRGB(255, 160, 80)
local FIRE_COLOR = Color3.fromRGB(255, 150, 60)
local FIRE_SECONDARY = Color3.fromRGB(224, 74, 31) -- the flame meshes' e04a1f tip
local NIGHT_EASE = 1.5          -- seconds to blend day <-> night
local MAX_RANGE = 60
local NEAR_SOUND = 40           -- studs camera <-> torch: the crackle plays inside this ...
local FAR_SOUND = 46            -- ... and stops beyond this (hysteresis)
local SOUND_VOLUME = 0.22
local TEX_DOT = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- soft round glow (engine built-in)
--.. per variant. FireSize / Range / ember speeds are AUTHORED studs (x ctx.Scale); Fire.Size is clamped to 2..30
local VARIANTS = {
	A = {FireSize = 1.5, Heat = 5, Embers = 6, DayBrightness = 1.4, NightBrightness = 2.4, DayRange = 5.5, NightRange = 9},
	B = {FireSize = 1.5, Heat = 6, Embers = 6, DayBrightness = 1.4, NightBrightness = 2.4, DayRange = 5.5, NightRange = 9},
	C = {FireSize = 2.0, Heat = 4, Embers = 9, DayBrightness = 1.6, NightBrightness = 2.7, DayRange = 5, NightRange = 8.5},
}
local FLICKER = 0.16            -- brightness wobble (fraction)

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

--.. a lively flame wobble from server time (math.noise needs the ~1e9 clock folded into a short cycle)
local function Flicker(t, seed)
	local tt = t % 997
	return 1 + FLICKER * (math.noise(tt * 4.1, seed, 0.5) * 1.5 + 0.35 * math.sin(tt * 13.7 + seed) + 0.2 * math.sin(tt * 23.1 + seed * 2))
end

--.. Pivot_<V>_FlameAnchor missing (an older template): above the variant's flame core, else the hitbox top
local function FallbackAnchor(model, prefix)
	local core = Kit.Part(model, prefix .. "FlameCore")
	if core then return core.Position end
	local hitbox = Kit.Hitbox(model)
	return hitbox.Position + Vector3.new(0, hitbox.Size.Y * 0.4, 0)
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local cfg = VARIANTS[ctx.Variant or "A"] or VARIANTS.A
	local prefix = ctx.Variant and (ctx.Variant .. "_") or ""
	local scale = ctx.Scale
	local seed = (hitbox.Position.X * 0.529 + hitbox.Position.Z * 0.917) % 89

	--..Anchor (local, invisible) at the flame..--
	local point = Kit.Pivot(model, Kit.VName(model, "FlameAnchor")) or FallbackAnchor(model, prefix)
	local anchor = ctx:Part({
		Name = "FunTorchFlame", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(point) * Kit.Origin(model).Rotation,
	})

	--..Fire..--
	local fire = Instance.new("Fire")
	fire.Size = math.clamp(cfg.FireSize * scale, 2, 30)
	fire.Heat = cfg.Heat
	fire.Color = FIRE_COLOR
	fire.SecondaryColor = FIRE_SECONDARY
	fire.Parent = anchor

	--..Light..--
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Shadows = false
	light.Brightness = cfg.DayBrightness
	light.Range = cfg.DayRange * scale
	light.Parent = anchor

	--..Embers..--
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Texture = TEX_DOT
	embers.Rate = cfg.Embers
	embers.Lifetime = NumberRange.new(0.9, 1.7)
	embers.Speed = NumberRange.new(1.4 * scale, 2.8 * scale)
	embers.SpreadAngle = Vector2.new(22, 22)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Acceleration = Vector3.new(0, 0.8 * scale, 0)
	embers.Drag = 1.4
	embers.Size = NumberSequence.new({kp(0, 0.07 * scale), kp(0.6, 0.05 * scale), kp(1, 0)})
	embers.Transparency = NumberSequence.new({kp(0, 0), kp(0.7, 0.2), kp(1, 1)})
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 130)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 140, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 60, 20)),
	})
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Parent = anchor

	--..Crackle (near only)..--
	local crackle
	if FunAssets.Sfx.FireLoop then
		local ok, sound = pcall(function()
			return ctx:Sound(anchor, FunAssets.Sfx.FireLoop, {
				Name = "FunCrackle", Looped = true, Volume = SOUND_VOLUME, RollOffMinDistance = 5, RollOffMaxDistance = NEAR_SOUND,
			})
		end)
		if ok then crackle = sound end
	end
	if crackle then
		local function SyncSound()
			local d = ctx:CameraDistance()
			if d <= NEAR_SOUND and not crackle.IsPlaying then
				if crackle.TimeLength > 0 then crackle.TimePosition = (seed * 0.37) % crackle.TimeLength end -- torches out of step
				crackle:Play()
			elseif d > FAR_SOUND and crackle.IsPlaying then
				crackle:Stop()
			end
		end
		SyncSound()
		ctx:Every(0.5, SyncSound)
	end

	--..Every frame: flicker + night blend..--
	local night = IsNight() and 1 or 0
	local rangeClock = 1
	ctx:Step(function(dt, now)
		local target = IsNight() and 1 or 0
		night += (target - night) * math.min(1, dt * 3 / NIGHT_EASE)
		local f = Flicker(now, seed)
		light.Brightness = Lerp(cfg.DayBrightness, cfg.NightBrightness, night) * f
		rangeClock += dt
		if rangeClock >= 0.1 then
			rangeClock = 0
			light.Range = math.min(MAX_RANGE, Lerp(cfg.DayRange, cfg.NightRange, night) * scale * (1 + (f - 1) * 0.35))
		end
	end)
end

return B
