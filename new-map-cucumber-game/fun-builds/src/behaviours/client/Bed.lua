--[[
	Bed  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the functional Bed (server half: ServerStorage.FunBehaviours.Bed).
	  * "Z z z": while someone sleeps in a side (Fun_Sleeper1 / Fun_Sleeper2 = their UserId), a BillboardGui
	    over their head floats three "Z"s up from the head - each one grows, wobbles, tilts and fades as it
	    rises, one after another. The letters are timed from the server clock (Kit.Now), so every client shows
	    the same Zs. If the sleeper's head can't be found (streamed out, loading) they float over the pillow
	  * night-light: while ANYONE sleeps, the crescent moon on the headboard (NightLight) and the star dots
	    (NightStar*) turn Neon and a dim warm PointLight in the moon fades in (and out again after everyone
	    gets up), with a soft sparkle
	  * the sleeper's pillow (Pillow1 / Pillow2, an Ellipsoid) squashes a little under their head - only its
	    SpecialMesh Scale/Offset change, the part itself never moves
	  * a low creak when someone lies down
	Cleanup puts every build part back as it was (Night* material/colour, pillow meshes).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))
local FunAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunAssets"))

--..Config..--
local SLOTS = 2                               -- sides of the bed (server: Fun_Sleeper<i>, parts Pillow<i>)
local PILLOW_FALLBACK = {Vector3.new(1.9, 2.34, 3.25), Vector3.new(-1.9, 2.34, 3.25)} -- authored, if Pivot_Pillow<i> is missing
local Z_PERIOD = 2.7                          -- seconds for one Z to float from the head to the top
local Z_COUNT = 3
local Z_BOARD = Vector2.new(3.2, 4.2)         -- billboard size in studs
local Z_ABOVE = 2.5                           -- studs from the head centre up to the billboard centre
local Z_COLOR = Color3.fromRGB(226, 238, 255)
local Z_STROKE = Color3.fromRGB(35, 38, 44)
local Z_MAX_DISTANCE = 90
local HEAD_RETRY = 1                          -- seconds between looks for a sleeper's head
local NEON_COLOR = Color3.fromRGB(255, 231, 160)
local GLOW_COLOR = Color3.fromRGB(255, 222, 150)
local GLOW_BRIGHTNESS = 0.7                   -- dim: a night-light, not a lamp
local GLOW_RANGE = 12
local GLOW_FADE = 1.2
local PILLOW_SQUASH = 0.8                     -- pillow height (x) while a head rests on it
local PILLOW_SPREAD = 0.1                     -- ... and how much it widens
local PILLOW_RATE = 7                         -- 1/s ease
local CREAK_VOLUME = 0.3
local CHIME_VOLUME = 0.18

local B = {}
B.StepRange = 140

--..Helpers..--
local function Fade(p)
	if p < 0.15 then return p / 0.15 end
	if p > 0.65 then return math.max(0, 1 - (p - 0.65) / 0.35) end
	return 1
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local playerGui = ctx.Player:FindFirstChildOfClass("PlayerGui")
	local soundParent = Kit.Part(model, "Mattress") or hitbox
	local creak = ctx:Sound(soundParent, FunAssets.Sfx.Creak, {Volume = CREAK_VOLUME, PlaybackSpeed = 0.55})

	--..Night-light parts (restored on cleanup)..--
	local nightRest = {}
	for _, part in ipairs(Kit.Parts(model, "Night")) do
		nightRest[part] = {Material = part.Material, Color = part.Color}
	end
	local moon = Kit.Part(model, "NightLight")
	local light, chime
	if moon then
		light = ctx:Add(Instance.new("PointLight"))
		light.Name = "BedNightLight"
		light.Color = GLOW_COLOR
		light.Range = GLOW_RANGE * ctx.Scale
		light.Brightness = 0
		light.Shadows = false
		light.Enabled = false
		light.Parent = moon
		chime = ctx:Sound(moon, FunAssets.Sfx.Sparkle, {Volume = CHIME_VOLUME, PlaybackSpeed = 0.8})
	end

	local glowOn, glowTween = nil, nil
	local function SetGlow(on, instant)
		if glowOn == on then return end
		glowOn = on
		for part, rest in pairs(nightRest) do
			if part.Parent then
				part.Material = on and Enum.Material.Neon or rest.Material
				part.Color = on and NEON_COLOR or rest.Color
			end
		end
		if not light then return end
		if glowTween then glowTween:Cancel() glowTween = nil end
		local goal = on and GLOW_BRIGHTNESS or 0
		if instant then
			light.Brightness = goal
			light.Enabled = on
			return
		end
		light.Enabled = true
		glowTween = TweenService:Create(light, TweenInfo.new(GLOW_FADE, Enum.EasingStyle.Sine), {Brightness = goal})
		glowTween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and not glowOn and light.Parent then light.Enabled = false end
		end)
		glowTween:Play()
		if on and chime then chime:Play() end
	end

	--..Slots: one per side of the bed..--
	local slots = {}
	for i = 1, SLOTS do
		local pillow = Kit.Part(model, "Pillow" .. i)
		local mesh = pillow and pillow:FindFirstChildOfClass("SpecialMesh")
		local pillowAt = model:GetAttribute("Pivot_Pillow" .. i)
		if typeof(pillowAt) ~= "Vector3" then pillowAt = PILLOW_FALLBACK[i] end
		--.. the fallback anchor for the Zs (the pillow, where the head is), local-only
		local anchor = ctx:Part({Name = "BedZAnchor" .. i, Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1,
			CFrame = CFrame.new(Kit.ToWorld(model, pillowAt))})
		slots[i] = {
			UserId = 0, Pillow = pillow, Mesh = mesh, Anchor = anchor,
			MeshScale = mesh and mesh.Scale, MeshOffset = mesh and mesh.Offset,
			Squash = 0, Target = 0, Phase = (i - 1) * 0.37 * Z_PERIOD,
			Gui = nil, Labels = nil, Head = nil, NextLook = 0,
		}
	end

	--..The Z z z billboard..--
	local function MakeBoard(slot)
		local gui = Instance.new("BillboardGui")
		gui.Name = "BedSleepZ"
		gui.Size = UDim2.fromScale(Z_BOARD.X, Z_BOARD.Y) -- scale = studs on a BillboardGui
		gui.StudsOffsetWorldSpace = Vector3.new(0, Z_ABOVE, 0)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.MaxDistance = Z_MAX_DISTANCE
		gui.ResetOnSpawn = false
		gui.ClipsDescendants = false
		gui.Adornee = slot.Anchor
		local labels = {}
		for k = 1, Z_COUNT do
			local label = Instance.new("TextLabel")
			label.Name = "Z" .. k
			label.BackgroundTransparency = 1
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Font = Enum.Font.FredokaOne
			label.Text = "Z"
			label.TextScaled = true
			label.TextColor3 = Z_COLOR
			label.TextTransparency = 1
			local stroke = Instance.new("UIStroke")
			stroke.Color = Z_STROKE
			stroke.Thickness = 2
			stroke.Transparency = 1
			stroke.Parent = label
			label.Parent = gui
			labels[k] = {Label = label, Stroke = stroke}
		end
		gui.Parent = playerGui
		ctx:Add(gui)
		slot.Gui, slot.Labels, slot.Head, slot.NextLook = gui, labels, nil, 0
	end

	local function DropBoard(slot)
		if slot.Gui then slot.Gui:Destroy() end
		slot.Gui, slot.Labels, slot.Head = nil, nil, nil
	end

	--.. the sleeper's head, or nil
	local function FindHead(userId)
		local plr = Players:GetPlayerByUserId(userId)
		local character = plr and plr.Character
		local head = character and character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then return head end
		return nil
	end

	--..State..--
	local function AnySleeper()
		for _, slot in ipairs(slots) do
			if slot.UserId ~= 0 then return true end
		end
		return false
	end
	for i, slot in ipairs(slots) do
		local primed = false
		ctx:OnState("Sleeper" .. i, function(v)
			local id = tonumber(v) or 0
			local was = slot.UserId
			slot.UserId = id
			slot.Target = id ~= 0 and 1 or 0
			if id ~= 0 then
				if not slot.Gui or id ~= was then
					DropBoard(slot)
					if playerGui then MakeBoard(slot) end
				end
			else
				DropBoard(slot)
			end
			if not primed then
				--.. streamed in / started: show the current state at once, no sound
				primed = true
				slot.Squash = slot.Target
				SetGlow(AnySleeper(), true)
				return
			end
			if id ~= 0 and was == 0 then creak:Play() end
			SetGlow(AnySleeper(), false)
		end)
	end

	--..Pillow squash (SpecialMesh only)..--
	local function PosePillow(slot)
		local mesh, pillow = slot.Mesh, slot.Pillow
		if not mesh or not mesh.Parent or not pillow.Parent then return end
		local s = slot.Squash
		local y = 1 + (PILLOW_SQUASH - 1) * s
		local w = 1 + PILLOW_SPREAD * s
		local base = slot.MeshScale
		mesh.Scale = Vector3.new(base.X * w, base.Y * y, base.Z * (1 + PILLOW_SPREAD * 0.5 * s))
		mesh.Offset = slot.MeshOffset - Vector3.new(0, (1 - y) * 0.5 * pillow.Size.Y * base.Y, 0)
	end
	for _, slot in ipairs(slots) do PosePillow(slot) end

	--..Every frame: pillows ease, Zs float..--
	ctx:Step(function(dt, now)
		local clock = os.clock()
		for _, slot in ipairs(slots) do
			--.. pillow
			if slot.Squash ~= slot.Target then
				local step = math.min(1, dt * PILLOW_RATE)
				slot.Squash += (slot.Target - slot.Squash) * step
				if math.abs(slot.Target - slot.Squash) < 0.01 then slot.Squash = slot.Target end
				PosePillow(slot)
			end
			--.. Zs
			local gui = slot.Gui
			if gui then
				if slot.Head and not slot.Head.Parent then slot.Head = nil end
				if not slot.Head and clock >= slot.NextLook then
					slot.NextLook = clock + HEAD_RETRY
					slot.Head = FindHead(slot.UserId)
				end
				local adornee = slot.Head or slot.Anchor
				if gui.Adornee ~= adornee then gui.Adornee = adornee end
				for k, z in ipairs(slot.Labels) do
					local p = ((now + slot.Phase + (k - 1) * Z_PERIOD / Z_COUNT) % Z_PERIOD) / Z_PERIOD
					local size = 0.2 + 0.26 * p
					local a = Fade(p)
					z.Label.Position = UDim2.fromScale(0.36 + 0.3 * p + 0.08 * math.sin(p * math.pi * 2.4 + k), 0.9 - 0.8 * p)
					z.Label.Size = UDim2.fromScale(size, size * Z_BOARD.X / Z_BOARD.Y)
					z.Label.Rotation = -16 + 22 * p + 6 * math.sin(p * math.pi * 2)
					z.Label.TextTransparency = 1 - a
					z.Stroke.Transparency = 1 - a
				end
			end
		end
	end)

	--..Cleanup: the build's parts back to rest..--
	return function()
		for part, rest in pairs(nightRest) do
			if part.Parent then
				part.Material = rest.Material
				part.Color = rest.Color
			end
		end
		for _, slot in ipairs(slots) do
			if slot.Mesh and slot.Mesh.Parent then
				slot.Mesh.Scale = slot.MeshScale
				slot.Mesh.Offset = slot.MeshOffset
			end
		end
	end
end

return B
