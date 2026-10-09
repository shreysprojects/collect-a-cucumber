--[[
	DiningTable  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the DINING TABLE (fun-builds/CONTRACT.md, package HomeDining). The centrepiece candle is lit:
	a warm PointLight sits in the Neon "CandleFlame" part and, every frame while the camera is near, the flame
	flickers - it stretches / narrows from its foot, sways a few degrees, shifts between orange and yellow -
	and the light's brightness and range breathe with it (layered math.noise on the server clock folded to
	% 1000 - raw epoch seconds are too big for math.noise's 32-bit floats - seeded per table so two tables
	never flicker in step). Purely cosmetic and local; the flame's authored CFrame / Size / Color are stored
	relative to the Hitbox and put back on cleanup (moved, sold, broken, streamed out).
	The seats are server-side (behaviours/server/DiningTable.lua).
]]

--..Config..--
local LIGHT_COLOR = Color3.fromRGB(255, 172, 92)
local LIGHT_RANGE = 10          -- studs at scale 1
local LIGHT_BRIGHTNESS = 1.3
local FLAME_HOT = Color3.fromRGB(255, 214, 110)
local FLAME_WARM = Color3.fromRGB(255, 150, 60)
local STRETCH = 0.2             -- flame height wobble (fraction)
local SWAY_DEG = 7

local B = {}
B.Keys = {"DiningTable"}
B.StepRange = 140

function B.Client(model, ctx)
	local Kit = ctx.Kit
	local flame = Kit.Part(model, "CandleFlame")
	local hitbox = Kit.Hitbox(model)
	if not (flame and hitbox) then return end

	--..Rest pose (relative to the hitbox, so a restore after a move lands in the right place)..--
	local rest = hitbox.CFrame:ToObjectSpace(flame.CFrame)
	local restSize = flame.Size
	local restColor = flame.Color
	local seed = (hitbox.Position.X * 0.173 + hitbox.Position.Z * 0.311) % 97

	--..Glow..--
	local light = Instance.new("PointLight")
	light.Name = "CandleGlow"
	light.Color = LIGHT_COLOR
	light.Brightness = LIGHT_BRIGHTNESS
	light.Range = LIGHT_RANGE * ctx.Scale
	light.Shadows = false
	light.Parent = flame
	ctx:Add(light)

	--..Flicker..--
	ctx:Step(function(_, now)
		if not (flame.Parent and hitbox.Parent) then return end
		--.. math.noise works in 32-bit floats: raw server time (~1.8e9) loses its fraction and the flame
		--.. freezes, so fold the clock into a short cycle first (one invisible jump every 1000 s)
		local t = now % 1000
		local n1 = math.clamp(math.noise(t * 7.3, seed, 0.5) * 2, -1, 1)
		local n2 = math.clamp(math.noise(t * 12.9, seed + 17.7, 0.5) * 2, -1, 1)
		local n3 = math.clamp(math.noise(t * 2.7, seed + 41.3, 0.5) * 2, -1, 1)
		local sy = 1 + STRETCH * (0.7 * n1 + 0.3 * n2)
		local sxz = 1 - 0.08 * n1 + 0.04 * n3
		local size = Vector3.new(restSize.X * sxz, restSize.Y * sy, restSize.Z * sxz)
		--.. grow from the foot of the flame (the wick), leaning a little
		local foot = hitbox.CFrame * rest * CFrame.new(0, -restSize.Y * 0.5, 0)
		local sway = CFrame.Angles(math.rad(SWAY_DEG * n3), 0, math.rad(SWAY_DEG * n2))
		flame.Size = size
		flame.CFrame = foot * sway * CFrame.new(0, size.Y * 0.5, 0)
		flame.Color = FLAME_WARM:Lerp(FLAME_HOT, math.clamp(0.55 + 0.45 * n1, 0, 1))
		light.Brightness = LIGHT_BRIGHTNESS * (1 + 0.3 * n1 + 0.12 * n2)
		light.Range = LIGHT_RANGE * ctx.Scale * (1 + 0.08 * n2)
	end)

	return function()
		if flame.Parent and hitbox.Parent then
			flame.Size = restSize
			flame.CFrame = hitbox.CFrame * rest
			flame.Color = restColor
		end
	end
end

return B
