--[[
	Nightstand  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the functional Nightstand (server half: ServerStorage.FunBehaviours.Nightstand).
	  * table lamp: while Fun_On is true a warm PointLight in the drum shade (LampShade) is lit (a quick
	    warm-up fade), the discs inside the shade's open ends (ShadeInnerTop / ShadeInnerBottom) turn Neon
	    and the shade fabric warms in colour; a click on every flip (none when the build streams in)
	  * alarm clock: the ClockHour / ClockMinute hands (authored at 12) turn about Pivot_ClockCentre to the
	    in-game time, Lighting.ClockTime, a few times a second while the camera is near
	Cleanup puts every build part back (shade colour, inner discs' material/colour, the hands at 12).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))
local FunAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunAssets"))

--..Config..--
local LIGHT_COLOR = Color3.fromRGB(255, 196, 128)  -- warm incandescent
local LIGHT_BRIGHTNESS = 1.4
local LIGHT_RANGE = 16
local WARM_UP = 0.18                               -- seconds for the bulb to come up
local INNER_ON = Color3.fromRGB(255, 222, 150)     -- Neon inside the shade
local SHADE_ON = Color3.fromRGB(255, 236, 196)     -- the fabric lit from inside
local CLICK_VOLUME = 0.45
local CLOCK_EVERY = 0.2                            -- seconds between hand updates
local CLOCK_MIN_TURN = math.rad(0.25)              -- skip writes smaller than this

local B = {}
B.StepRange = 110

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end

	--..Lamp..--
	local shade = Kit.Part(model, "LampShade")
	local rest = {} -- [part] = {Material, Color}
	local inner = Kit.Parts(model, "ShadeInner")
	for _, part in ipairs(inner) do rest[part] = {Material = part.Material, Color = part.Color} end
	if shade then rest[shade] = {Material = shade.Material, Color = shade.Color} end

	local light, click
	if shade then
		light = ctx:Add(Instance.new("PointLight"))
		light.Name = "LampLight"
		light.Color = LIGHT_COLOR
		light.Range = LIGHT_RANGE * math.max(ctx.Scale, 0.5)
		light.Brightness = 0
		light.Shadows = false
		light.Enabled = false
		light.Parent = shade
		click = ctx:Sound(shade, FunAssets.Sfx.Click, {Volume = CLICK_VOLUME})
	end

	local lit, tween = nil, nil
	local function SetLit(on, instant)
		if lit == on then return end
		lit = on
		for _, part in ipairs(inner) do
			if part.Parent then
				part.Material = on and Enum.Material.Neon or rest[part].Material
				part.Color = on and INNER_ON or rest[part].Color
			end
		end
		if shade and shade.Parent then shade.Color = on and SHADE_ON or rest[shade].Color end
		if not light then return end
		if tween then tween:Cancel() tween = nil end
		if instant or not on then
			light.Brightness = on and LIGHT_BRIGHTNESS or 0
			light.Enabled = on
		else
			light.Enabled = true
			light.Brightness = 0
			tween = TweenService:Create(light, TweenInfo.new(WARM_UP, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Brightness = LIGHT_BRIGHTNESS})
			tween:Play()
		end
		if not instant and click then
			click.PlaybackSpeed = on and 1.05 or 0.9
			click:Play()
		end
	end

	local primed = false
	ctx:OnState("On", function(v)
		SetLit(v == true, not primed)
		primed = true
	end)

	--..Alarm clock hands..--
	local hands = {} -- {Part, Rel (to the clock centre), Home (to the hitbox), Hour}
	local centreAt = model:GetAttribute("Pivot_ClockCentre")
	local centreRel
	if typeof(centreAt) == "Vector3" then
		local centreCF = CFrame.new(Kit.ToWorld(model, centreAt)) * Kit.Origin(model).Rotation
		centreRel = hitbox.CFrame:ToObjectSpace(centreCF)
		for _, spec in ipairs({{"ClockHour", true}, {"ClockMinute", false}}) do
			local part = Kit.Part(model, spec[1])
			if part then
				table.insert(hands, {
					Part = part, Rel = centreCF:ToObjectSpace(part.CFrame),
					Home = hitbox.CFrame:ToObjectSpace(part.CFrame), Hour = spec[2], Last = nil,
				})
			end
		end
	end

	if #hands > 0 then
		local nextTick = 0
		ctx:Step(function()
			local t = os.clock()
			if t < nextTick then return end
			nextTick = t + CLOCK_EVERY
			if not hitbox.Parent then return end
			local clock = Lighting.ClockTime
			local centre = hitbox.CFrame * centreRel
			for _, h in ipairs(hands) do
				--.. +angle about the build's +Z = clockwise as seen from the front (-Z)
				local angle = h.Hour and ((clock % 12) / 12 * 2 * math.pi) or ((clock % 1) * 2 * math.pi)
				if h.Part.Parent and (not h.Last or math.abs(angle - h.Last) >= CLOCK_MIN_TURN) then
					h.Last = angle
					h.Part.CFrame = centre * CFrame.Angles(0, 0, angle) * h.Rel
				end
			end
		end)
	end

	--..Cleanup: every build part back to rest..--
	return function()
		for part, r in pairs(rest) do
			if part.Parent then
				part.Material = r.Material
				part.Color = r.Color
			end
		end
		if hitbox.Parent then
			for _, h in ipairs(hands) do
				if h.Part.Parent then h.Part.CFrame = hitbox.CFrame * h.Home end
			end
		end
	end
end

return B
