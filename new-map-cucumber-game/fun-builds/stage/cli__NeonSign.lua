--[[
	NeonSign  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GlassCase
	Client half of the three NEON SIGNS (x1.5; server half ServerStorage.FunBehaviours.NeonSign = the power switch).
	Everything below is driven by Kit.Now() (server time), so every client shows the same frame of the show.
	  * A OpenSign: the pink OPEN letters (A_Text) glow with a realistic occasional flicker - per 5.5 s window a
	    seeded burst of 2-6 off/on stutters, sometimes followed by a sag that climbs back - plus a faint shimmer;
	    each burst gives one very quiet Zap buzz. The cyan border tube (A_Border) flickers far more rarely.
	    While the camera is out of StepRange (the Step sleeps) a 0.5 s check keeps letters, border and light fully
	    lit, so a stutter can never freeze the sign dark for far viewers
	  * B ArrowSign: the arrow is ONE merged mesh (B_Arrow), so the sweep toward its tip is built around it: two
	    runtime neon chevrons, one behind the arrow and one past its tip, light up cumulatively tail -> arrow ->
	    tip every 1.2 s (the sign's own arrow only dims between sweeps). The 10 perimeter bulbs (one merged mesh,
	    B_Bulbs) are covered by runtime Neon balls that chase column by column toward the tip side
	  * C Marquee: the 12 border bulbs (one merged mesh, C_Bulbs) are covered by runtime Neon balls: every third
	    bulb lit, stepping round the sign clockwise (as the viewer sees it), and a flash-all show every 15 s
	  * one PointLight per sign in front of the glass (brighter at night, workspace CyclePhase == "Night")
	  * state Fun_On (default on). Off = every neon part of the sign goes SmoothPlastic, darkened toward the panel
	    colour, the overlays go unlit and the light goes out; on = a short warm-up stutter. A Click on each switch
	  * the owner-only switch prompt gets MaxActivationDistance 0 on everyone else's client
	The bulb / chevron positions come from props/build_neon_sign.py (B.Layout, authored Roblox frame: Blender
	(x, y, z) -> (x, z, -y)); they are checked against the merged bulbs mesh's real centre (a small offset is
	absorbed, a large one skips the overlays and pulses the whole mesh instead). The sign's own parts only ever
	get Material / Color changes (never Transparency: BuildHealthService fades that) and get them back on cleanup.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

--..Config..--
local DARK = Color3.fromRGB(35, 38, 44)   -- the backing panels' near-black (23262c)
local OFF_TINT = 0.72                     -- an unlit tube: its colour this far toward DARK, SmoothPlastic
local BULB_OFF_TINT = 0.5                 -- an unlit overlay bulb (reads as a dull amber bulb)
local DIM_TINT = 0.8                      -- a lit tube at level L: Neon, its colour (1 - L) * DIM_TINT toward DARK
local LEVELS = 24                         -- brightness steps: a part is only written when its step changes
local WARM_STEP = 0.06                    -- seconds per entry of WARM_PATTERN (the switch-on stutter)
local WARM_PATTERN = {0, 0.8, 0, 0, 0.5, 1, 0.15, 1}
local NIGHT_BOOST = 1.6
local SWITCH_PROMPT = "NeonSwitchPrompt"
local BULB = Color3.fromRGB(255, 225, 77) -- ffe14d, the signs' bulb amber
local ARROW = Color3.fromRGB(255, 138, 61) -- ff8a3d, B_Arrow
--.. one PointLight per sign: colour, AUTHORED position (in front of the sign), AUTHORED range, brightness
local LIGHT = {
	A = {Color = Color3.fromRGB(255, 79, 163), At = Vector3.new(9.8, 1.45, -1), Range = 7, Brightness = 1},
	B = {Color = Color3.fromRGB(255, 150, 70), At = Vector3.new(2.3, 2.75, -1), Range = 7, Brightness = 1},
	C = {Color = Color3.fromRGB(255, 225, 90), At = Vector3.new(-7.4, 3.95, -1.1), Range = 9, Brightness = 0.9},
}
--.. A: per window of Window seconds a burst happens with probability Chance: MinSegs..MaxSegs off/on stutters,
--.. then (SagChance) a sag that climbs back to full
local TEXT_FLICKER = {Window = 5.5, Chance = 0.55, MinSegs = 2, MaxSegs = 6, SagChance = 0.3}
local BORDER_FLICKER = {Window = 7.3, Chance = 0.16, MinSegs = 1, MaxSegs = 3, SagChance = 0}
local ZAP_VOLUME = 0.07
--.. B: the arrow sweep and the bulb chase
local ARROW_PERIOD = 1.2
local ARROW_ON = {0.12, 0.34, 0.56} -- phase the tail chevron / the sign's arrow / the tip chevron light at
local ARROW_OFF = 0.86              -- phase all three drop back
local ARROW_DIM = 0.3               -- the sign's own arrow between sweeps
local B_STEP = 0.13                 -- seconds per bulb-column step (4 columns, then a rest)
--.. C: the marquee chase and the flash-all show at the end of every SHOW_PERIOD
local C_STEP = 0.2
local SHOW_PERIOD, SHOW_LEN, SHOW_BLINK = 15, 1.8, 0.15
--.. the runtime chevrons (AUTHORED studs): arm run L along +X from the tip, half-height H, square-ish tube
local MINI = {L = 0.3, H = 0.3, Stroke = 0.14, Depth = 0.18}

local B = {}
B.Keys = {"NeonSign"}
B.StepRange = 200

--..Layout (plain data, AUTHORED Roblox frame of ServerStorage.Builds.Fun.NeonSign, scale 1)..--
--.. a ">"-style chevron whose tip points -X (the arrow's direction = the viewer's right)
local function Chevron(tx, y, z)
	local tip = Vector3.new(tx, y, z)
	local arms = {}
	for _, sign in ipairs({1, -1}) do
		local e = Vector3.new(tx + MINI.L, y + sign * MINI.H, z)
		local d = e - tip
		table.insert(arms, {
			CF = CFrame.new((tip + e) / 2) * CFrame.Angles(0, 0, math.atan2(d.Y, d.X)),
			Size = Vector3.new(d.Magnitude + MINI.Stroke, MINI.Stroke, MINI.Depth),
		})
	end
	return {Arms = arms}
end

--.. overlays of variant letter: {Part (the merged bulbs mesh), PartCentre (its authored bbox centre), Balls = {{Pos, D,
--.. Group}}, Chevrons = {{Arms = {{CF, Size}}}}}. From props/build_neon_sign.py (_bulb: cylinders y 0.10-0.30 /
--.. 0.12-0.34 off the panel = Roblox z -0.10..-0.30 / -0.12..-0.34; each ball swallows its bulb)
function B.Layout(letter)
	if letter == "B" then
		local lane, z = 2.3, -0.21
		local cols = {1.76, 0.59, -0.59, -1.76} -- tail side (+X) first: the chase runs toward the tip side (-X)
		local balls = {}
		for _, y in ipairs({4.56, 1.84}) do
			for c, bx in ipairs(cols) do
				table.insert(balls, {Pos = Vector3.new(lane + bx, y, z), D = 0.3, Group = c})
			end
		end
		table.insert(balls, {Pos = Vector3.new(lane + 1.76, 3.2, z), D = 0.3, Group = 1})
		table.insert(balls, {Pos = Vector3.new(lane - 1.76, 3.2, z), D = 0.3, Group = 4})
		--.. the sign's arrow spans x 1.605 (tip) .. 2.995 at y 2.51: one chevron behind it, one past its tip
		return {
			Part = "B_Bulbs", PartCentre = Vector3.new(2.3, 3.2, -0.2), Balls = balls,
			Chevrons = {Chevron(lane + 1.04, 2.51, z), Chevron(lane - 1.34, 2.51, z)},
		}
	elseif letter == "C" then
		local lane, z = -7.4, -0.25
		local balls = {}
		local function add(bx, y)
			table.insert(balls, {Pos = Vector3.new(lane + bx, y, z), D = 0.32, Group = #balls + 1})
		end
		--.. clockwise as the viewer sees it (+X is the viewer's LEFT): top row left -> right, the right end,
		--.. bottom row right -> left, the left end
		for _, bx in ipairs({3, 1.5, 0, -1.5, -3}) do add(bx, 4.7) end
		add(-3.72, 3.95)
		for _, bx in ipairs({-3, -1.5, 0, 1.5, 3}) do add(bx, 3.2) end
		add(3.72, 3.95)
		return {Part = "C_Bulbs", PartCentre = Vector3.new(-7.4, 3.95, -0.23), Balls = balls, Chevrons = {}}
	end
	return nil
end

--..Flicker (A)..--
local function Plan(cfg, seed, w)
	local rng = Random.new(seed + w * 7919)
	if rng:NextNumber() > cfg.Chance then return false end
	local start = rng:NextNumber(0.2, cfg.Window * 0.6)
	local segs, t = {}, 0
	for _ = 1, rng:NextInteger(cfg.MinSegs, cfg.MaxSegs) do
		local off = rng:NextNumber(0.035, 0.12)
		local residual = rng:NextNumber() < 0.6 and 0 or rng:NextNumber(0.15, 0.4)
		table.insert(segs, {t, t + off, residual})
		t += off + rng:NextNumber(0.03, 0.2)
	end
	local sag = nil
	if rng:NextNumber() < cfg.SagChance then sag = {Len = rng:NextNumber(0.4, 1.1), Level = rng:NextNumber(0.4, 0.65)} end
	return {Start = start, Len = t, Segs = segs, Sag = sag}
end

--.. brightness 0..1 of a plan at t seconds into its window
local function PlanLevel(plan, t)
	if not plan then return 1 end
	local u = t - plan.Start
	if u < 0 then return 1 end
	if u < plan.Len then
		for _, s in ipairs(plan.Segs) do
			if u >= s[1] and u < s[2] then return s[3] end
		end
		return 1
	end
	local sag = plan.Sag
	if sag and u - plan.Len < sag.Len then
		local k = (u - plan.Len) / sag.Len
		return sag.Level + (1 - sag.Level) * k * k
	end
	return 1
end

--.. fn(now) -> level, burst window id (while a burst of the current window is running)
local function Flicker(cfg, seed)
	local plans = {}
	return function(now)
		local w = math.floor(now / cfg.Window)
		if plans[w] == nil then
			local prev = plans[w - 1]
			if prev == nil then prev = Plan(cfg, seed, w - 1) end
			plans = {[w] = Plan(cfg, seed, w), [w - 1] = prev}
		end
		local t = now - w * cfg.Window
		local plan = plans[w]
		local level = math.min(PlanLevel(plan, t), PlanLevel(plans[w - 1], t + cfg.Window))
		local burst = (plan and t >= plan.Start and t < plan.Start + plan.Len) and w or nil
		return level, burst
	end
end

--..Behaviour..--
function B.Client(model, ctx)
	local scale = ctx.Scale
	local letter = ctx.Variant
	if not letter then
		for _, l in ipairs({"A", "B", "C"}) do
			if Kit.Part(model, l .. "_Panel") then
				letter = l
				break
			end
		end
	end
	if not letter or not LIGHT[letter] then return end

	--..The sign's own neon parts (Material / Color restored on cleanup)..--
	local neon, recs = {}, {}
	for _, part in ipairs(Kit.Parts(model, letter .. "_")) do
		if part.Material == Enum.Material.Neon then
			local rec = {Part = part, Color = part.Color, Material = part.Material, Q = -1}
			neon[part.Name] = rec
			table.insert(recs, rec)
		end
	end
	if #recs == 0 then return end

	local function SetLevel(rec, level)
		local q = math.clamp(math.floor(level * LEVELS + 0.5), 0, LEVELS)
		if rec.Q == q then return end
		rec.Q = q
		local part = rec.Part
		if q == 0 then
			part.Material = Enum.Material.SmoothPlastic
			part.Color = rec.Color:Lerp(DARK, rec.OffTint or OFF_TINT)
		else
			part.Material = Enum.Material.Neon
			part.Color = rec.Color:Lerp(DARK, (1 - q / LEVELS) * DIM_TINT)
		end
	end

	--..A client-only folder for everything we make..--
	local folder = Instance.new("Folder")
	folder.Name = "FunFX_" .. tostring(ctx.Key)
	folder.Parent = workspace
	ctx:Add(folder)

	local function NewPart(shape, props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape == "Ball" then p.Shape = Enum.PartType.Ball end
		for k, v in pairs(props) do p[k] = v end
		p.Parent = folder
		ctx:Add(p)
		return p
	end

	--..Owner-only switch: out of reach on everyone else's client..--
	if not ctx:IsOwner() then
		local function hide(d)
			if d:IsA("ProximityPrompt") and d.Name == SWITCH_PROMPT then d.MaxActivationDistance = 0 end
		end
		for _, d in ipairs(model:GetDescendants()) do hide(d) end
		ctx:Connect(model.DescendantAdded, hide)
	end

	--..Overlays: bulbs that can chase, chevrons that sweep..--
	local balls, chevrons = {}, {}
	local layout = B.Layout(letter)
	local host = layout and neon[layout.Part] or nil -- the merged bulbs mesh the balls cover
	if layout and host then
		local shift = host.Part.Position - Kit.ToWorld(model, layout.PartCentre)
		if shift.Magnitude <= 1.5 * scale then
			for _, b in ipairs(layout.Balls) do
				local p = NewPart("Ball", {
					Name = "NeonBulb", Size = Vector3.one * b.D * scale,
					CFrame = CFrame.new(Kit.ToWorld(model, b.Pos) + shift),
				})
				table.insert(balls, {Rec = {Part = p, Color = BULB, OffTint = BULB_OFF_TINT, Q = -1}, Group = b.Group})
			end
			local arrowColor = neon.B_Arrow and neon.B_Arrow.Color or ARROW
			for i, chevron in ipairs(layout.Chevrons) do
				local arms = {}
				for _, arm in ipairs(chevron.Arms) do
					local p = NewPart(nil, {Name = "NeonChevron", Size = arm.Size * scale, CFrame = Kit.CFrameToWorld(model, arm.CF) + shift})
					table.insert(arms, {Part = p, Color = arrowColor, Q = -1})
				end
				chevrons[i] = arms
			end
			host.Covered = true
		else
			warn(("[NeonSign] %s: %s sits %.2f studs off its authored spot - bulb overlays skipped"):format(tostring(ctx.Key), layout.Part, shift.Magnitude))
		end
	end

	--..Light + sounds..--
	local cfg = LIGHT[letter]
	local glowPart = NewPart(nil, {
		Name = "NeonGlow", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(Kit.ToWorld(model, cfg.At)),
	})
	local light = Instance.new("PointLight")
	light.Color = cfg.Color
	light.Range = math.min(60, cfg.Range * scale)
	light.Brightness = cfg.Brightness
	light.Shadows = false
	light.Parent = glowPart
	local zap = letter == "A" and ctx:Sound(glowPart, FunAssets.Sfx.Zap, {
		Name = "Buzz", Volume = ZAP_VOLUME, RollOffMinDistance = 4, RollOffMaxDistance = 40,
	}) or nil
	local click = ctx:Sound(glowPart, FunAssets.Sfx.Click, {Name = "Switch", Volume = 0.5})

	local night = 1
	local function ReadNight()
		night = workspace:GetAttribute("CyclePhase") == "Night" and NIGHT_BOOST or 1
	end
	ReadNight()
	ctx:Connect(workspace:GetAttributeChangedSignal("CyclePhase"), ReadNight)

	local function SetLight(level)
		local b = cfg.Brightness * level * night
		if math.abs(light.Brightness - b) > 0.02 then light.Brightness = b end
	end

	--..The show, per variant: StepSign(now, warm) writes every neon part (writes are cached per level)..--
	local seed = ((tonumber(Kit.OwnerId(model)) or 0) % 100003) * 17
		+ math.floor((tonumber(model:GetAttribute("PlotX")) or 0) * 13 + (tonumber(model:GetAttribute("PlotZ")) or 0) * 7)
	local driven = {} -- recs a variant animates itself; the rest glow steady
	local StepSign
	local RestSign = nil -- optional: the look a variant settles on while the Step sleeps (camera out of StepRange)

	if letter == "A" then
		local text, border = neon.A_Text, neon.A_Border
		if text then driven[text] = true end
		if border then driven[border] = true end
		local textFlicker = Flicker(TEXT_FLICKER, seed)
		local borderFlicker = Flicker(BORDER_FLICKER, seed + 7)
		local lastBurst = nil
		StepSign = function(now, warm)
			local level, burst = textFlicker(now)
			level *= (0.96 + 0.04 * math.noise((now % 1000) * 3.1, seed % 89 + 0.5)) * warm -- (small input: noise precision)
			if text then SetLevel(text, level) end
			if border then SetLevel(border, (borderFlicker(now)) * warm) end
			SetLight(level)
			if burst and burst ~= lastBurst then
				lastBurst = burst
				if zap and warm >= 1 then
					zap.PlaybackSpeed = 0.85 + math.random() * 0.4
					zap.TimePosition = 0
					zap:Play()
				end
			end
		end
		--.. a stutter frozen at level 0 would leave the letters dark for far viewers: rest fully lit
		RestSign = function()
			if text then SetLevel(text, 1) end
			if border then SetLevel(border, 1) end
			SetLight(1)
		end
	elseif letter == "B" then
		local arrow = neon.B_Arrow
		if arrow then driven[arrow] = true end
		if host then driven[host] = true end
		StepSign = function(now, warm)
			local p = (now % ARROW_PERIOD) / ARROW_PERIOD
			local function lit(i)
				return p >= ARROW_ON[i] and p < ARROW_OFF
			end
			for i, arms in pairs(chevrons) do
				local level = lit(i == 1 and 1 or 3) and 1 or 0
				for _, r in ipairs(arms) do SetLevel(r, level * warm) end
			end
			if arrow then SetLevel(arrow, (lit(2) and 1 or ARROW_DIM) * warm) end
			local head = math.floor(now / B_STEP) % 5 -- column 0..3 lit, 4 = a rest
			for _, b in ipairs(balls) do
				local c = b.Group - 1
				SetLevel(b.Rec, ((c == head) and 1 or (c == head - 1) and 0.35 or 0) * warm)
			end
			if host then
				--.. covered by the balls: dark underneath; with no overlays the whole mesh pulses instead
				SetLevel(host, host.Covered and 0 or (0.55 + 0.45 * math.cos(p * math.pi * 2)) * warm)
			end
			SetLight((lit(2) and 1 or 0.55) * warm)
		end
	else
		if host then driven[host] = true end
		StepSign = function(now, warm)
			local tw = now % SHOW_PERIOD
			local show = tw >= SHOW_PERIOD - SHOW_LEN
			local all = show and math.floor((tw - (SHOW_PERIOD - SHOW_LEN)) / SHOW_BLINK) % 2 == 0
			local step = math.floor(now / C_STEP)
			for _, b in ipairs(balls) do
				local level
				if show then
					level = all and 1 or 0
				else
					level = ((b.Group - step) % 3 == 0) and 1 or 0
				end
				SetLevel(b.Rec, level * warm)
			end
			if host then
				SetLevel(host, host.Covered and 0 or (show and (all and 1 or 0.2) or (0.6 + 0.4 * ((step % 2 == 0) and 1 or 0))) * warm)
			end
			SetLight((show and (all and 1.15 or 0.5) or 0.85) * warm)
		end
	end

	local steady = {}
	for _, rec in ipairs(recs) do
		if not driven[rec] then table.insert(steady, rec) end
	end

	--..On / off..--
	local on, started = true, false
	local onSince = -math.huge
	local function Warm()
		local i = math.floor((os.clock() - onSince) / WARM_STEP) + 1
		return WARM_PATTERN[i] or 1
	end
	local function Frame(now)
		local warm = Warm()
		for _, rec in ipairs(steady) do SetLevel(rec, warm) end
		StepSign(now, warm)
	end
	local function AllOff()
		for _, rec in ipairs(recs) do SetLevel(rec, 0) end
		for _, b in ipairs(balls) do SetLevel(b.Rec, 0) end
		for _, arms in pairs(chevrons) do
			for _, r in ipairs(arms) do SetLevel(r, 0) end
		end
		light.Enabled = false
	end

	ctx:OnState("On", function(value)
		--.. nil = the server behaviour is between a stop and a restart (a move / break): keep the current look
		if value == nil and started then return end
		local nowOn = value ~= false
		if started and nowOn ~= on then
			click.TimePosition = 0
			click:Play()
		end
		local switchedOn = started and nowOn and not on
		on = nowOn
		if on then
			light.Enabled = true
			if switchedOn then
				onSince = os.clock()
				--.. the Step may be asleep (camera far): finish the warm-up here too
				task.delay(#WARM_PATTERN * WARM_STEP + 0.05, function()
					if ctx:Alive() and on then Frame(Kit.Now()) end
				end)
			end
			Frame(Kit.Now())
		else
			AllOff()
		end
		started = true
	end)

	ctx:Step(function(_, now)
		if on then Frame(now) end
	end)

	--.. the Step sleeps past StepRange and would freeze whatever frame was showing (B / C mid-chase is fine)
	if RestSign then
		ctx:Every(0.5, function()
			if on and ctx:CameraDistance() > ctx.StepRange then RestSign() end
		end)
	end

	return function()
		for _, rec in ipairs(recs) do
			if rec.Part.Parent then
				rec.Part.Material = rec.Material
				rec.Part.Color = rec.Color
			end
		end
	end
end

return B
