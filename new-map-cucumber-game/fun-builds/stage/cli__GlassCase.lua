--[[
	GlassCase  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GlassCase
	Client half of the TROPHY CASE (GlassCase, x1.25; server half ServerStorage.FunBehaviours.GlassCase).
	  * a TROPHY built from Parts in code (B.TrophySpecs: 1 golden cucumber on a plinth, 2 crown on a cushion,
	    3 star on a stand, 4 cup, 5 diamond; 1.2-1.32 studs tall authored, x the build's Scale) floats over
	    Pivot_DisplayPoint (the brass cap ring on the column) and slowly spins + bobs. Angle and bob come from
	    Kit.Now(), so every client shows the same pose
	  * a sparkle emitter around the trophy, a soft warm SpotLight from the case's downlight and a faint gold
	    PointLight (2 lights)
	  * state Fun_Design (1-5) picks the design; a change pops the old trophy out and the new one in (Whoosh).
	    At most two trophies exist (on show + popping out). While the camera is out of StepRange (the Step
	    sleeps) a change swaps instantly with no pop, and a 1 s check finishes any pop / shine / flash that
	    was running when the camera left, so nothing piles up or stays stuck white
	  * server event "Admire" {At}: a shine band sweeps up the trophy (parts ease toward white and flash Neon),
	    a sparkle burst, a light flash, one extra twirl and the Sparkle sound - timed from At on every client
	  * the case's GlassPanes are drawn as SmoothPlastic (same colour + transparency) while this runs, because
	    Roblox's Glass material hides every transparent thing behind it (the sparkles, the diamond, LightBeam);
	    Material / Reflectance come back on cleanup (Transparency is never touched: BuildHealthService fades it)
	  * the owner-only "Change trophy" prompt gets MaxActivationDistance 0 on everyone else's client
	Every part here is local (a client-only folder in workspace) and goes away with the ctx.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

--..Config..--
local TAU = math.pi * 2
--.. the display volume above the cap ring (y 3.05) is 1.3 tall up to the downlight collar (4.39; its open ring and
--.. lens reach 4.57 near the axis): the tallest trophy (the star, 1.32, tip on the axis) peaks at 3.05 + 0.08 + 0.06 + 1.32 = 4.51
local FLOAT = 0.08             -- authored studs between the cap ring and the trophy's lowest point (bob adds 0..2*BOB)
local BOB = 0.03               -- authored studs
local BOB_PERIOD = 3.4         -- seconds
local SPIN_PERIOD = 9          -- seconds per turn
local POP_OUT, POP_IN = 0.18, 0.42
local SHINE_TIME = 0.95        -- the band's trip from the base to the top
local SHINE_BAND = 0.22        -- half-width of the band, in trophy heights
local SHINE_WHITE = 0.85
local TWIRL_TIME = 1.1         -- the admire twirl (one extra turn, eased)
local FLASH_TIME = 0.8
local LATE_EVENT = 1.5         -- an Admire event older than this (seconds of server time) is skipped
local GLOW_BRIGHTNESS, GLOW_FLASH = 0.45, 2.6
local DISPLAY_FALLBACK = Vector3.new(0, 3.05, 0)   -- = Pivot_DisplayPoint
local LAMP_POINT = Vector3.new(0, 4.5, 0.18)       -- authored: just under the downlight's lens (hood mouth at y 4.62, z 0.18)
local SPARKLE_BOX = Vector3.new(1.15, 1.35, 1.15)  -- authored studs around the trophy
local SPARKLE_MID = 0.62                           -- authored height of that box's centre above the trophy's lowest point
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds" -- engine built-in
local EMIT_FAR = 150           -- studs: the emitter idles when the camera is farther
local CHANGE_PROMPT = "ChangeTrophyPrompt"
local WHITE = Color3.new(1, 1, 1)

--.. looks: Material is a name (Enum.Material[...]) so TrophySpecs stays plain data
local LOOKS = {
	Gold = {Color = Color3.fromRGB(255, 192, 42), Material = "SmoothPlastic", Reflectance = 0.3},
	GoldDark = {Color = Color3.fromRGB(212, 146, 26), Material = "SmoothPlastic", Reflectance = 0.2},
	Marble = {Color = Color3.fromRGB(35, 38, 44), Material = "Marble"},
	Velvet = {Color = Color3.fromRGB(150, 34, 46), Material = "Fabric"},
	Ruby = {Color = Color3.fromRGB(235, 45, 70), Material = "SmoothPlastic", Reflectance = 0.35},
	Sapphire = {Color = Color3.fromRGB(60, 112, 245), Material = "SmoothPlastic", Reflectance = 0.35},
	Emerald = {Color = Color3.fromRGB(40, 205, 110), Material = "SmoothPlastic", Reflectance = 0.35},
	Ink = {Color = Color3.fromRGB(40, 30, 18), Material = "SmoothPlastic"},
	GemTop = {Color = Color3.fromRGB(200, 240, 255), Material = "SmoothPlastic", Transparency = 0.25, Reflectance = 0.45},
	GemBottom = {Color = Color3.fromRGB(135, 196, 250), Material = "SmoothPlastic", Transparency = 0.25, Reflectance = 0.45},
	GemTable = {Color = Color3.fromRGB(228, 250, 255), Material = "SmoothPlastic", Transparency = 0.2, Reflectance = 0.5},
}
local GEMS = {"Ruby", "Sapphire", "Emerald"}

local B = {}
B.Keys = {"GlassCase"}
B.StepRange = 140
B.LOOKS = LOOKS -- read by the offline render check (fun-builds/tools/preview_glasscase), not by the game

--..Trophy geometry (plain data: {Class, Shape, Size, CF, Look} in the trophy's own frame, AUTHORED studs:
--..lowest point at y = 0, centred on x / z, front = -Z)..--
local function V(x, y, z)
	return Vector3.new(x, y, z)
end

local function Add(list, class, shape, size, cf, look)
	table.insert(list, {Class = class, Shape = shape, Size = size, CF = cf, Look = look})
end

local function Block(list, pos, size, look)
	Add(list, "Part", "Block", size, CFrame.new(pos), look)
end

local function Ball(list, pos, d, look)
	Add(list, "Part", "Ball", V(d, d, d), CFrame.new(pos), look)
end

local function Ellipsoid(list, pos, size, look, rot)
	Add(list, "Part", "Ellipsoid", size, CFrame.new(pos) * (rot or CFrame.identity), look)
end

--.. an upright cylinder (Roblox cylinders run along local X)
local function Post(list, pos, height, d, look)
	Add(list, "Part", "Cylinder", V(height, d, d), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), look)
end

--.. a cylinder from a to b
local function Rod(list, a, b, d, look)
	local axis = b - a
	local x = axis.Unit
	local up = math.abs(x.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	local z = x:Cross(up).Unit
	Add(list, "Part", "Cylinder", V(axis.Magnitude, d, d), CFrame.fromMatrix((a + b) / 2, x, z:Cross(x), z), look)
end

--.. a square bar from a to b in the XY plane (ends run w/2 past a and b so a chain of bars has no gaps)
local function Bar(list, a, b, w, look)
	local axis = b - a
	Add(list, "Part", "Block", V(axis.Magnitude + w, w, w), CFrame.new((a + b) / 2) * CFrame.Angles(0, 0, math.atan2(axis.Y, axis.X)), look)
end

--.. a triangle a-b-c, `thick` studs through its plane, as two right-angled WedgeParts (split at the foot of the
--.. altitude onto the longest edge)
local function Tri(list, a, b, c, thick, look)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		a, c = c, a
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-6 then return end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local d1, d2 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
	if d1 > 1e-3 then Add(list, "WedgePart", "Wedge", V(thick, height, d1), CFrame.fromMatrix((a + b) / 2, right, up, back), look) end
	if d2 > 1e-3 then Add(list, "WedgePart", "Wedge", V(thick, height, d2), CFrame.fromMatrix((a + c) / 2, -right, up, -back), look) end
end

--.. 1: a golden cucumber - two bent segments, warts, a stem and a leaf - standing in a socket on a marble plinth
local BUMPS = { -- {t along the cucumber 0..1, angle round it}
	{0.08, 0.3}, {0.15, 5.2}, {0.22, 2.4}, {0.3, 3.7}, {0.36, 4.5}, {0.5, 1.3}, {0.62, 3.4}, {0.74, 5.6}, {0.8, 2.7}, {0.88, 0.9},
}
local function Cucumber(l)
	Block(l, V(0, 0.03, 0), V(0.7, 0.06, 0.7), "GoldDark")
	Block(l, V(0, 0.115, 0), V(0.64, 0.13, 0.64), "Marble")
	Block(l, V(0, 0.2, 0), V(0.56, 0.05, 0.56), "Gold")
	Block(l, V(0, 0.115, -0.325), V(0.34, 0.07, 0.03), "Gold")
	Post(l, V(0, 0.26, 0), 0.08, 0.28, "GoldDark")
	local r, seg = 0.15, 0.34
	local d1 = V(-math.sin(math.rad(8)), math.cos(math.rad(8)), 0)
	local d2 = V(-math.sin(math.rad(26)), math.cos(math.rad(26)), 0) -- the bend
	local p0 = V(0.06, 0.3 + r, 0)
	local p1 = p0 + d1 * seg
	local p2 = p1 + d2 * seg
	Rod(l, p0, p1, r * 2, "Gold")
	Rod(l, p1, p2, r * 2, "Gold")
	Ball(l, p0, r * 2, "Gold")
	Ball(l, p1, r * 2, "Gold")
	Ball(l, p2, r * 2, "Gold")
	local tip = p2 + d2 * r
	Rod(l, p2 + d2 * (r - 0.03), tip + d2 * 0.08, 0.07, "GoldDark")
	Ellipsoid(l, tip + V(0.07, -0.01, 0), V(0.18, 0.035, 0.09), "GoldDark", CFrame.Angles(0, 0, math.rad(-25)))
	for _, b in ipairs(BUMPS) do
		local t, a = b[1], b[2]
		local base, dir = p0 + d1 * (t / 0.5 * seg), d1
		if t >= 0.5 then base, dir = p1 + d2 * ((t - 0.5) / 0.5 * seg), d2 end
		local side = V(dir.Y, -dir.X, 0)
		Ball(l, base + (side * math.cos(a) + Vector3.zAxis * math.sin(a)) * (r - 0.012), 0.07, "GoldDark")
	end
end

--.. 2: a crown with five points, jewels and a velvet cap, on a tasselled cushion
local function Crown(l)
	Block(l, V(0, 0.08, 0), V(0.86, 0.16, 0.86), "Velvet")
	Ellipsoid(l, V(0, 0.16, 0), V(0.9, 0.2, 0.9), "Velvet")
	for _, s in ipairs({{1, 1}, {1, -1}, {-1, 1}, {-1, -1}}) do
		Ball(l, V(0.43 * s[1], 0.1, 0.43 * s[2]), 0.1, "Gold")
	end
	Post(l, V(0, 0.38, 0), 0.3, 0.74, "Gold")
	Post(l, V(0, 0.26, 0), 0.07, 0.8, "GoldDark")
	Post(l, V(0, 0.525, 0), 0.05, 0.78, "GoldDark")
	Ellipsoid(l, V(0, 0.53, 0), V(0.64, 0.56, 0.64), "Velvet")
	for k = 0, 4 do
		local a = k / 5 * TAU
		local out, side = V(math.sin(a), 0, -math.cos(a)), V(math.cos(a), 0, math.sin(a))
		Tri(l, out * 0.35 + side * 0.14 + V(0, 0.5, 0), out * 0.35 - side * 0.14 + V(0, 0.5, 0), out * 0.33 + V(0, 0.86, 0), 0.07, "Gold")
		Ball(l, out * 0.33 + V(0, 0.88, 0), 0.11, "Gold")
		local j = a + TAU / 10
		Ball(l, V(math.sin(j), 0, -math.cos(j)) * 0.372 + V(0, 0.38, 0), 0.09, GEMS[k % 3 + 1])
	end
	Ball(l, V(0, 0.88, 0), 0.16, "Gold")
	Block(l, V(0, 1.08, 0), V(0.05, 0.3, 0.05), "Gold")
	Block(l, V(0, 1.13, 0), V(0.18, 0.05, 0.05), "Gold")
end

--.. 3: a five-point star on a stem, a ruby in its heart
local function Star(l)
	Block(l, V(0, 0.07, 0), V(0.52, 0.14, 0.52), "Marble")
	Block(l, V(0, 0.16, 0), V(0.44, 0.04, 0.44), "Gold")
	Block(l, V(0, 0.07, -0.265), V(0.3, 0.07, 0.03), "Gold")
	Post(l, V(0, 0.45, 0), 0.54, 0.09, "GoldDark")
	local c, outer, inner, thick = V(0, 0.86, 0), 0.46, 0.19, 0.15
	Add(l, "Part", "Cylinder", V(thick, inner * 2, inner * 2), CFrame.new(c) * CFrame.Angles(0, math.pi / 2, 0), "Gold")
	local function at(r, ang)
		return c + V(r * math.sin(ang), r * math.cos(ang), 0)
	end
	for k = 0, 4 do
		local a = k / 5 * TAU
		Tri(l, at(outer, a), at(inner, a - TAU / 10), at(inner, a + TAU / 10), thick, "Gold")
	end
	Ball(l, c + V(0, 0, -thick / 2), 0.13, "Ruby")
	Ball(l, c + V(0, 0, thick / 2), 0.13, "Ruby")
end

--.. 4: a two-handled champion cup on a marble base
local function Cup(l)
	Block(l, V(0, 0.08, 0), V(0.56, 0.16, 0.56), "Marble")
	Block(l, V(0, 0.18, 0), V(0.48, 0.04, 0.48), "GoldDark")
	Block(l, V(0, 0.08, -0.285), V(0.3, 0.08, 0.03), "Gold")
	Post(l, V(0, 0.23, 0), 0.06, 0.36, "Gold")
	Post(l, V(0, 0.37, 0), 0.24, 0.1, "Gold")
	Ball(l, V(0, 0.36, 0), 0.17, "GoldDark")
	Ellipsoid(l, V(0, 0.8, 0), V(0.72, 0.64, 0.72), "Gold")
	Post(l, V(0, 0.98, 0), 0.34, 0.72, "Gold")
	Post(l, V(0, 1.16, 0), 0.05, 0.78, "GoldDark")
	Post(l, V(0, 1.19, 0), 0.02, 0.62, "Ink")
	for _, side in ipairs({1, -1}) do
		local centre = V(0.37 * side, 0.95, 0)
		local prev
		for i = 0, 6 do
			local a = math.rad(-90 + i * 30)
			local p = centre + V(math.cos(a) * 0.15 * side, math.sin(a) * 0.15, 0)
			if prev then Bar(l, prev, p, 0.06, "Gold") end
			prev = p
		end
	end
	Ball(l, V(0, 0.93, -0.36), 0.13, "Ruby")
end

--.. 5: a brilliant-cut diamond balanced on its point (8 pavilion facets, 16 crown facets, a flat table)
local function Diamond(l)
	local n, rg, yg, rt, yt = 8, 0.55, 0.78, 0.3, 1.2
	local function ring(r, y, k)
		local a = k / n * TAU
		return V(r * math.cos(a), y, r * math.sin(a))
	end
	local culet = V(0, 0, 0)
	for k = 0, n - 1 do
		local g0, g1 = ring(rg, yg, k), ring(rg, yg, k + 1)
		local t0, t1 = ring(rt, yt, k + 0.5), ring(rt, yt, k + 1.5)
		Tri(l, culet, g0, g1, 0.03, "GemBottom")
		Tri(l, g0, g1, t0, 0.03, "GemTop")
		Tri(l, t0, t1, g1, 0.03, "GemTop")
	end
	Post(l, V(0, yt, 0), 0.03, rt * 2, "GemTable")
end

local BUILDERS = {Cucumber, Crown, Star, Cup, Diamond}
B.DESIGN_COUNT = #BUILDERS

--.. the part list of design d (1-5; anything else = 1)
function B.TrophySpecs(d)
	local list = {}
	local builder = BUILDERS[tonumber(d) or 1] or BUILDERS[1]
	builder(list)
	return list
end

--..Behaviour..--
local function BackOut(u)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end

local function EaseInOut(u)
	return u < 0.5 and 2 * u * u or 1 - (-2 * u + 2) ^ 2 / 2
end

function B.Client(model, ctx)
	local scale = ctx.Scale
	local origin = Kit.Origin(model)
	local point = Kit.Pivot(model, "DisplayPoint") or Kit.ToWorld(model, DISPLAY_FALLBACK)
	local display = CFrame.new(point) * origin.Rotation
	local seedPhase = ((tonumber(Kit.OwnerId(model)) or 0) % 997) / 997 * TAU -- cases on one server don't spin in lockstep

	--..A client-only folder for everything we make..--
	local folder = Instance.new("Folder")
	folder.Name = "FunFX_" .. tostring(ctx.Key)
	folder.Parent = workspace
	ctx:Add(folder)

	--.. parts live in the folder, which takes them with it on cleanup (not ctx:Add'ed one by one: a swapped-out
	--.. trophy is destroyed right away and must not linger in the ctx's list)
	local function NewPart(class, shape, props)
		local p = Instance.new(class)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "Ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		for k, v in pairs(props) do p[k] = v end
		p.Parent = folder
		return p
	end

	--..Owner-only prompt: out of reach on everyone else's client..--
	if not ctx:IsOwner() then
		local function hide(d)
			if d:IsA("ProximityPrompt") and d.Name == CHANGE_PROMPT then d.MaxActivationDistance = 0 end
		end
		for _, d in ipairs(model:GetDescendants()) do hide(d) end
		ctx:Connect(model.DescendantAdded, hide)
	end

	--..Glass that shows the transparent things behind it..--
	local panes = Kit.Part(model, "GlassPanes")
	local paneMaterial, paneReflectance
	if panes and panes.Material == Enum.Material.Glass then
		paneMaterial, paneReflectance = panes.Material, panes.Reflectance
		panes.Material = Enum.Material.SmoothPlastic
		panes.Reflectance = math.max(paneReflectance, 0.12)
	end

	--..Sparkles, lights, sounds..--
	local anchor = NewPart("Part", nil, {
		Name = "TrophySparkles", Transparency = 1, Size = SPARKLE_BOX * scale,
		CFrame = display * CFrame.new(0, (FLOAT + SPARKLE_MID) * scale, 0),
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Rate = 7
	emitter.Lifetime = NumberRange.new(0.7, 1.3)
	emitter.Speed = NumberRange.new(0.15 * scale, 0.5 * scale)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.3 * scale, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.2 * scale), NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.6)})
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 236, 160), WHITE)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = anchor
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 214, 120)
	glow.Range = 5 * scale
	glow.Brightness = GLOW_BRIGHTNESS
	glow.Shadows = false
	glow.Parent = anchor
	local lamp = NewPart("Part", nil, {
		Name = "TrophyLamp", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(Kit.ToWorld(model, LAMP_POINT)) * origin.Rotation,
	})
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Color = Color3.fromRGB(255, 228, 180)
	spot.Angle = 55
	spot.Range = 5.5 * scale
	spot.Brightness = 1.3
	spot.Shadows = false
	spot.Parent = lamp
	local sparkleSound = ctx:Sound(anchor, FunAssets.Sfx.Sparkle, {Name = "Sparkle", Volume = 0.7})
	local whoosh = ctx:Sound(anchor, FunAssets.Sfx.Whoosh, {Name = "Swap", Volume = 0.3})

	--..Trophies..--
	local live = {}      -- trophies on show (the current one + one popping out)
	local current, design
	local shineAt = -math.huge

	local function Make(d)
		local specs = B.TrophySpecs(d)
		local t = {Parts = {}, RelPos = {}, RelRot = {}, Size = {}, Looks = {}, H = {}, CFs = {}, Q = {}, S = -1}
		local top = 0.05
		for _, s in ipairs(specs) do top = math.max(top, s.CF.Position.Y) end
		for i, s in ipairs(specs) do
			local look = LOOKS[s.Look] or LOOKS.Gold
			look.Enum = look.Enum or Enum.Material[look.Material]
			t.Parts[i] = NewPart(s.Class, s.Shape, {
				Name = "Trophy", Color = look.Color, Material = look.Enum,
				Reflectance = look.Reflectance or 0, Transparency = look.Transparency or 0,
				Size = s.Size * scale * 0.02, CFrame = display,
			})
			t.RelPos[i] = s.CF.Position
			t.RelRot[i] = s.CF.Rotation
			t.Size[i] = s.Size
			t.Looks[i] = look
			--.. where the shine band meets this part: mostly its height, a little of its side (a diagonal sweep)
			t.H[i] = math.clamp(s.CF.Position.Y / top * 0.8 + (s.CF.Position.X / 1.2 + 0.5) * 0.2, 0, 1)
			t.CFs[i] = display
			t.Q[i] = 0
		end
		return t
	end

	local function Resize(t, s)
		local k = scale * math.max(s, 0.02)
		for i, p in ipairs(t.Parts) do p.Size = t.Size[i] * k end
		t.S = s
	end

	local function Pose(t, root)
		local k = scale * math.max(t.S, 0.02)
		for i = 1, #t.Parts do t.CFs[i] = root * CFrame.new(t.RelPos[i] * k) * t.RelRot[i] end
		workspace:BulkMoveTo(t.Parts, t.CFs, Enum.BulkMoveMode.FireCFrameChanged)
	end

	--.. band = the shine band's centre in trophy heights, nil = no shine
	local function Shine(t, band)
		for i, p in ipairs(t.Parts) do
			local k = band and math.max(0, 1 - math.abs(t.H[i] - band) / SHINE_BAND) or 0
			local q = math.floor(k * 10 + 0.5)
			if t.Q[i] ~= q then
				t.Q[i] = q
				local look = t.Looks[i]
				p.Color = look.Color:Lerp(WHITE, SHINE_WHITE * q / 10)
				p.Material = q >= 5 and Enum.Material.Neon or look.Enum
			end
		end
	end

	--.. destroy a trophy and take it off the live list
	local function Drop(t)
		for _, p in ipairs(t.Parts) do p:Destroy() end
		local i = table.find(live, t)
		if i then table.remove(live, i) end
	end

	local function RootCF(now)
		local bob = math.sin(now / BOB_PERIOD * TAU) * BOB
		local spin = (now % SPIN_PERIOD) / SPIN_PERIOD * TAU + seedPhase
		local tw = (now - shineAt) / TWIRL_TIME
		if tw >= 0 and tw < 1 then spin += TAU * EaseInOut(tw) end
		return display * CFrame.new(0, (FLOAT + BOB + bob) * scale, 0) * CFrame.Angles(0, spin, 0)
	end

	local function Asleep()
		return ctx:CameraDistance() > ctx.StepRange
	end

	--.. the Step sleeps while the camera is out of StepRange, so nothing would finish an animation: end them all
	--.. at once (only the current trophy stays, full size, no shine, the glow back to normal)
	local function Settle()
		for i = #live, 1, -1 do
			if live[i] ~= current then Drop(live[i]) end
		end
		if current then
			if current.Born or current.S ~= 1 then
				current.Born = nil
				Resize(current, 1)
				Pose(current, RootCF(Kit.Now()))
			end
			if current.Shining then
				Shine(current, nil)
				current.Shining = false
			end
		end
		if glow.Brightness ~= GLOW_BRIGHTNESS then glow.Brightness = GLOW_BRIGHTNESS end
	end

	ctx:OnState("Design", function(value)
		--.. nil = the server behaviour is between a stop and a restart (a move / break): keep what is on show
		if value == nil and design ~= nil then return end
		local d = math.clamp(math.floor(tonumber(value) or 1), 1, #BUILDERS)
		if d == design then return end
		local first = design == nil
		design = d
		--.. at most the one on show + one popping out: a trophy still popping out from the last change goes now
		for i = #live, 1, -1 do
			if live[i].Dying then Drop(live[i]) end
		end
		local asleep = Asleep()
		if current then
			if asleep then Drop(current) else current.Dying = os.clock() end
		end
		current = Make(d)
		table.insert(live, current)
		if first or asleep then
			--.. no pop: the first trophy, or a change nobody near enough to see
			Resize(current, 1)
			Pose(current, RootCF(Kit.Now()))
			return
		end
		current.Born = os.clock()
		Resize(current, 0.02)
		Pose(current, RootCF(Kit.Now()))
		whoosh.TimePosition = 0
		whoosh:Play()
		emitter:Emit(14)
	end)

	ctx:Every(1, function()
		local dist = ctx:CameraDistance()
		emitter.Enabled = dist < EMIT_FAR
		if dist > ctx.StepRange then Settle() end
	end)

	--.. the server's Admire (see B.OnEvent)
	ctx._trophyAdmire = function(at)
		if type(at) ~= "number" or Kit.Now() - at > LATE_EVENT then return end
		shineAt = at
		emitter:Emit(20)
		sparkleSound.TimePosition = 0
		sparkleSound:Play()
	end

	ctx:Step(function(_, now)
		local root = RootCF(now)
		local clock = os.clock()
		local band = nil
		local u = (now - shineAt) / SHINE_TIME
		if u >= 0 and u < 1 then band = -SHINE_BAND + u * (1 + 2 * SHINE_BAND) end
		for i = #live, 1, -1 do
			local t = live[i]
			local s = 1
			if t.Dying then
				s = 1 - (clock - t.Dying) / POP_OUT
				if s <= 0 then
					Drop(t) -- (takes it off `live`: safe, this loop runs backwards)
					continue
				end
			elseif t.Born then
				local v = (clock - t.Born) / POP_IN
				if v >= 1 then t.Born = nil else s = BackOut(v) end
			end
			if s ~= t.S then Resize(t, s) end
			Pose(t, root)
			if t == current then
				if band then
					Shine(t, band)
					t.Shining = true
				elseif t.Shining then
					Shine(t, nil)
					t.Shining = false
				end
			end
		end
		local f = (now - shineAt) / FLASH_TIME
		local brightness = GLOW_BRIGHTNESS + ((f >= 0 and f < 1) and GLOW_FLASH * (1 - f) or 0)
		if math.abs(glow.Brightness - brightness) > 0.01 then glow.Brightness = brightness end
	end)

	return function()
		ctx._trophyAdmire = nil
		if panes and paneMaterial and panes.Parent then
			panes.Material = paneMaterial
			panes.Reflectance = paneReflectance
		end
	end
end

function B.OnEvent(_, action, payload, ctx)
	if action == "Admire" and type(payload) == "table" and ctx._trophyAdmire then
		ctx._trophyAdmire(payload.At)
	end
end

return B
