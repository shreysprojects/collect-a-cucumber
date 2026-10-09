--[[
	FloorLamp  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package HomeHearth
	Client half of the READING FLOOR LAMP (server half: ServerStorage.FunBehaviours.FloorLamp; fun-builds/CONTRACT.md).
	Drawn from state Fun_On (true / false; the server turns it on at dusk, off at dawn, and anyone flips it by
	the pull-chain) through one "glow" value that eases in over WARM_UP s and out over COOL_DOWN s:
	  * a warm PointLight at the bulb (Pivot_Light, no shadows: it sits inside the shade) and a SpotLight inside
	    the shade just over its open bottom (Pivot_Spot) shining DOWN through the opening with shadows on, so
	    the lamp throws a round pool of light on the floor round its base (2 lights, the contract's cap)
	  * the shade glows from inside: the fabric panels (ShadePanel01..16) turn a soft warm cream Neon, so the lamp
	    reads as on from every side even in the game's bright daytime lighting; the diffuser disc on top
	    (ShadeGlowTop) and the Bulb (seen through the open bottom) turn Neon too. SHADE_NEON = false would only
	    tint the panels instead
	  * a hand switch (the server's "Tug" event, fired only from the prompt - never by the dusk / dawn switch)
	    tugs the pull-chain (PullChain + PullBead) down and back and clicks; the state change only eases the glow
	Every build part it touches (Color, Material, the chain's CFrame) is put back on cleanup.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local LIGHT_COLOR = Color3.fromRGB(255, 214, 150)
local POINT_BRIGHTNESS, POINT_RANGE = 1.3, 14           -- range in studs at scale 1
local SPOT_BRIGHTNESS, SPOT_RANGE, SPOT_ANGLE = 2.6, 16, 110
local MAX_RANGE = 60
local GLOW_COLOR = Color3.fromRGB(255, 226, 166)       -- diffuser disc while on (Neon)
local BULB_COLOR = Color3.fromRGB(255, 241, 204)       -- bulb while on (Neon)
local SHADE_LIT = Color3.fromRGB(255, 247, 226)        -- fabric panels while on
local SHADE_NEON_COLOR = Color3.fromRGB(255, 228, 175) -- fabric panels while on when SHADE_NEON (soft warm cream Neon)
local SHADE_NEON = true                                -- the whole shade glows while on (false: panels only tint)
local WARM_UP, COOL_DOWN = 0.25, 0.4                   -- seconds
local TUG_DEPTH, TUG_TIME = 0.22, 0.32                 -- AUTHORED studs down / seconds for the pull-chain tug
local SNAP_RANGE = 120                                 -- a change seen from farther than this snaps; no tug / click past it
local FALLBACK = {                                     -- authored points when a Pivot_* is missing (older template)
	Light = Vector3.new(0, 6.1, 0),
	Spot = Vector3.new(0, 5.75, -0.36),
	ChainTop = Vector3.new(0.3, 5.7, -0.3),
}

local B = {}
B.StepRange = 180

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local s = ctx.Scale
	local rotation = Kit.Origin(model).Rotation
	local function Point(name)
		return Kit.Pivot(model, name) or Kit.ToWorld(model, FALLBACK[name])
	end

	--..Build parts we recolour (restored on cleanup)..--
	local base = {} -- [part] = {Color, Material}
	local function Track(part)
		if part and not base[part] then base[part] = {Color = part.Color, Material = part.Material} end
		return part
	end
	local glowTop = Track(Kit.Part(model, "ShadeGlowTop"))
	local bulb = Track(Kit.Part(model, "Bulb"))
	local panels = Kit.Parts(model, "ShadePanel")
	for _, part in ipairs(panels) do Track(part) end

	--..Pull-chain rig (tugged about its top)..--
	local chainParts = {}
	for _, name in ipairs({"PullChain", "PullBead"}) do
		local part = Kit.Part(model, name)
		if part then table.insert(chainParts, part) end
	end
	local chainTopCF = CFrame.new(Point("ChainTop")) * rotation
	local rig = #chainParts > 0 and Kit.Rig(chainParts, chainTopCF) or nil
	local chainRest = {} -- about the hitbox, for putting back after a move
	for _, part in ipairs(chainParts) do chainRest[part] = hitbox.CFrame:ToObjectSpace(part.CFrame) end

	ctx:OnCleanup(function()
		for part, b in pairs(base) do
			if part.Parent then
				part.Color = b.Color
				part.Material = b.Material
			end
		end
		for part, rel in pairs(chainRest) do
			if part.Parent and hitbox.Parent then part.CFrame = hitbox.CFrame * rel end
		end
	end)

	--..Lights: two invisible local hosts (the PointLight at the bulb, the SpotLight over the open bottom)..--
	local pointHost = ctx:Part({Name = "FloorLampBulb", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(Point("Light")) * rotation})
	local point = Instance.new("PointLight")
	point.Color = LIGHT_COLOR
	point.Range = math.min(MAX_RANGE, POINT_RANGE * s)
	point.Brightness = 0
	point.Shadows = false -- inside the shade: a shadowed light would be swallowed by the panels
	point.Enabled = false
	point.Parent = pointHost
	local spotHost = ctx:Part({Name = "FloorLampSpot", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(Point("Spot")) * rotation})
	local spot = Instance.new("SpotLight")
	spot.Color = LIGHT_COLOR
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = SPOT_ANGLE
	spot.Range = math.min(MAX_RANGE, SPOT_RANGE * s)
	spot.Brightness = 0
	spot.Shadows = true -- the shade's rim cuts a round pool of light on the floor
	spot.Enabled = false
	spot.Parent = spotHost

	local click = ctx:Sound(spotHost, FunAssets.Sfx.Click, {Name = "Click", Volume = 0.45, RollOffMaxDistance = 40})

	--..Look for a given glow (0 off .. 1 on)..--
	local shown = -1
	local function Show(g)
		if g == shown or (math.abs(g - shown) < 0.002 and g > 0 and g < 1) then return end -- the ends always land exactly
		shown = g
		local on = g > 0.02
		point.Enabled = on
		spot.Enabled = on
		point.Brightness = POINT_BRIGHTNESS * g
		spot.Brightness = SPOT_BRIGHTNESS * g
		for part, b in pairs(base) do
			if part.Parent then
				local lit, neon
				if part == glowTop then
					lit, neon = GLOW_COLOR, true
				elseif part == bulb then
					lit, neon = BULB_COLOR, true
				else
					lit, neon = SHADE_NEON and SHADE_NEON_COLOR or SHADE_LIT, SHADE_NEON
				end
				part.Material = (neon and on) and Enum.Material.Neon or b.Material
				part.Color = b.Color:Lerp(lit, g)
			end
		end
	end

	--..State: only eases the glow (a dusk / dawn switch changes it too, with no hand on the chain)..--
	local wantOn, glow, first = false, 0, true
	ctx:OnState("On", function(value)
		local on = value == true
		if on == wantOn and not first then return end
		local live = not first and ctx:CameraDistance() <= SNAP_RANGE
		first = false
		wantOn = on
		if not live then
			glow = on and 1 or 0
			Show(glow)
		end
	end)
	Show(glow)

	--..Hand switch (B.OnEvent "Tug"): tug the chain and click..--
	local tugAt = -math.huge
	ctx.FloorLampTug = function()
		if not ctx:Alive() or ctx:CameraDistance() > SNAP_RANGE then return end
		tugAt = os.clock()
		click.TimePosition = 0
		click:Play()
	end

	--..Per frame: ease the glow, tug the chain (both idle once settled)..--
	local tugging = false
	ctx:Step(function(dt)
		local target = wantOn and 1 or 0
		if glow ~= target then
			local step = dt / (wantOn and WARM_UP or COOL_DOWN)
			glow = (target > glow) and math.min(target, glow + step) or math.max(target, glow - step)
			Show(glow)
		end
		if rig then
			local t = (os.clock() - tugAt) / TUG_TIME
			if t < 1 then
				tugging = true
				Kit.PoseRig(rig, chainTopCF * CFrame.new(0, -TUG_DEPTH * s * math.sin(math.pi * t), 0))
			elseif tugging then
				tugging = false
				Kit.PoseRig(rig, chainTopCF)
			end
		end
	end)
end

--..Server events: "Tug" = someone pulled the chain (the prompt), not the day / night switch..--
function B.OnEvent(_model, action, _payload, ctx)
	if action == "Tug" and ctx.FloorLampTug then ctx.FloorLampTug() end
end

return B
