--[[
	HomeOffice headless test: the GrandfatherClock (`py gen.py`). The GamingDesk has its own file, gamingdesk.luau
	(2026-09-24: the playable CUKE RUN needs a mock network, a GUI and a bot), run by gen.py in a second Luau process.
]]

------------------------------------------------------------------ loader
local env = getfenv(1)
local loaded = {}
local function load(name)
	local fn, err = loadstring(SOURCES[name], name)
	assert(fn, err)
	setfenv(fn, env)
	return fn()
end
env.require = function(m)
	local name = type(m) == "table" and m.Name or tostring(m)
	if not loaded[name] then loaded[name] = load(name) end
	return loaded[name]
end
for _, n in ipairs({"FunBuildKit", "FunAssets"}) do
	local ms = Instance.new("ModuleScript")
	ms.Name = n
	ms.Parent = MockModules
end
local Kit = require({Name = "FunBuildKit"})

local fails, checks = 0, 0
local function check(ok, msg)
	checks += 1
	if not ok then fails += 1 print("FAIL " .. msg) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

------------------------------------------------------------------ template + placement (BuildService: scale about the bbox centre)
local function MakePlaced(key, scale, placeCF)
	local data = MODELS[key]
	local model = Instance.new("Model")
	model.Name = key
	local centre = (data.Min + data.Max) / 2
	local parts = {}
	for _, pd in ipairs(data.Parts) do
		local c = pd.CF
		local cf = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		local p = Instance.new("Part")
		p.Name = pd.Name
		p.Size = pd.Size * scale
		p.CFrame = CFrame.new(centre + (cf.Position - centre) * scale) * cf.Rotation
		p.Color = Color3.fromHex(pd.Color)
		p.Transparency = pd.T
		p.CanCollide = pd.Collide
		p.Anchored = true
		p.Parent = model
		table.insert(parts, p)
	end
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (data.Max - data.Min) * scale
	hitbox.CFrame = CFrame.new(centre)
	hitbox.Transparency = 1
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	for k, v in pairs(data.Attrs) do model:SetAttribute(k, v) end
	model:SetAttribute("AuthoredCentre", centre)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("BuildKey", key)
	local delta = placeCF * hitbox.CFrame:Inverse()
	for _, p in ipairs(parts) do p.CFrame = delta * p.CFrame end
	hitbox.CFrame = delta * hitbox.CFrame
	model.Parent = workspace
	return model
end

------------------------------------------------------------------ client ctx (FunBuildClient.NewContext)
local NEAR = true
local function MakeCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		_insts = {}, _cleanups = {}, _steps = {}, _everys = {}, StepRange = 180}
	function ctx:Alive() return true end
	function ctx:Connect(signal, fn) return signal:Connect(fn) end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn) fn(self:State(k)) end
	function ctx:Send() end
	function ctx:CameraDistance() return (workspace.CurrentCamera.CFrame.Position - Kit.Hitbox(model).Position).Magnitude end
	function ctx:Step(fn) table.insert(self._steps, fn) end
	function ctx:Every(_, fn) table.insert(self._everys, fn) end
	function ctx:Sound(parent, id, props) local s = Kit.MakeSound(id, props) s.Parent = parent self:Add(s) return s end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = workspace.CurrentCamera end
		self:Add(p)
		return p
	end
	function ctx:LocalCharacter() return nil end
	function ctx:Near() return NEAR end
	function ctx:IsOwner() return true end
	return ctx
end

local function Run(mod, model)
	local ctx = MakeCtx(model)
	local ok, res = pcall(mod.Client, model, ctx)
	check(ok, "Client() errored: " .. tostring(res))
	if ok and type(res) == "function" then ctx:OnCleanup(res) end
	return ctx
end
local function Frames(ctx, n, dt)
	dt = dt or 1 / 60
	check(#ctx._steps <= 1, "at most one ctx:Step per build")
	for _ = 1, n do
		MockNow += dt
		for _, fn in ipairs(ctx._steps) do
			local ok, err = pcall(fn, dt, MockNow)
			if not ok then check(false, "Step errored: " .. tostring(err)) return end
		end
	end
end
local function Stop(ctx)
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		check(ok, "cleanup errored: " .. tostring(err))
	end
	for i = #ctx._insts, 1, -1 do ctx._insts[i]:Destroy() end
end
local function SetCamera(model, dist)
	local origin = Kit.Origin(model)
	rawget(workspace.CurrentCamera, "_p").CFrame = CFrame.new(Kit.Hitbox(model).Position + origin.LookVector * dist + Vector3.new(0, 3, 0))
end

--.. sound play counter: wrap every Sound's Play
local plays = {}
local function CountPlays(ctx)
	for _, inst in ipairs(ctx._insts) do
		if inst.ClassName == "Sound" then
			local id = inst.SoundId
			rawset(inst, "Play", function(self)
				plays[id] = (plays[id] or 0) + 1
				rawget(self, "_p").IsPlaying = true
			end)
		end
	end
end
local function Plays(name)
	local FunAssets = require({Name = "FunAssets"})
	return plays["rbxassetid://" .. tostring(FunAssets.Sfx[name])] or plays[tostring(FunAssets.Sfx[name])] or 0
end

------------------------------------------------------------------ GrandfatherClock
do
	local mod = load("C_GrandfatherClock")
	local Lighting = MockLighting
	local function SetClock(t) rawget(Lighting, "_p").ClockTime = t end
	for _, spec in ipairs({{1, 0}, {1.25, 143}}) do
		local scale, yawDeg = spec[1], spec[2]
		local tag = ("Clock x%.2f yaw %d: "):format(scale, yawDeg)
		local model = MakePlaced("GrandfatherClock", scale, CFrame.new(-30, 2, 40) * CFrame.Angles(0, math.rad(yawDeg), 0))
		SetCamera(model, 12)
		NEAR = true
		plays = {}
		workspace:SetAttribute("IsNight", false)
		local face = Kit.Pivot(model, "FaceCentre")
		local origin = Kit.Origin(model)
		local homes = {}
		for _, p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") then homes[p] = p.CFrame end end

		--.. the direction (authored, from the face centre) a hand's tip points
		local function HandAngle(name)
			local tip = Kit.Part(model, name .. "Tip")
			local rel = origin:PointToObjectSpace(tip.Position)
			local c = origin:PointToObjectSpace(face)
			local dx, dy = rel.X - c.X, rel.Y - c.Y
			--.. clock angle: clockwise from 12 seen from the front; +X authored is the viewer's LEFT
			return math.deg(math.atan2(-dx, dy)) % 360
		end
		SetClock(14.5)
		local ctx = Run(mod, model)
		CountPlays(ctx)
		Frames(ctx, 3)
		check(near(HandAngle("MinuteHand"), 180, 0.5), tag .. "14:30 minute hand at 6 (" .. HandAngle("MinuteHand") .. ")")
		check(near(HandAngle("HourHand"), 75, 0.5), tag .. "14:30 hour hand between 2 and 3 (" .. HandAngle("HourHand") .. ")")

		--.. the pendulum swings +/- State_PendulumSwing with a 2 s period, ticking at each end
		local bob = Kit.Part(model, "PendulumBob")
		local pivot = Kit.Pivot(model, "PendulumPivot")
		local maxA, minA = -99, 99
		local ticks0 = Plays("ClockTick")
		for _ = 1, 120 do
			Frames(ctx, 1, 1 / 60)
			local rel = origin:PointToObjectSpace(bob.Position) - origin:PointToObjectSpace(pivot)
			local a = math.deg(math.atan2(rel.X, -rel.Y))
			maxA, minA = math.max(maxA, a), math.min(minA, a)
		end
		check(near(maxA, 6, 0.3) and near(minA, -6, 0.3), tag .. "pendulum swings +/-6 (" .. maxA .. ", " .. minA .. ")")
		check(Plays("ClockTick") - ticks0 == 2, tag .. "two tocks per 2 s period (" .. (Plays("ClockTick") - ticks0) .. ")")
		NEAR = false
		local ticks1 = Plays("ClockTick")
		Frames(ctx, 120)
		check(Plays("ClockTick") == ticks1, tag .. "no tick when nobody is near")
		NEAR = true

		--.. time passing across 15:00 strikes three
		local chimes0 = Plays("ClockChime")
		for i = 1, 60 do SetClock(14.5 + i * 0.01) Frames(ctx, 1, 0.1) end
		Frames(ctx, 60, 1 / 15)
		check(Plays("ClockChime") - chimes0 == 3, tag .. "15:00 strikes 3 (" .. (Plays("ClockChime") - chimes0) .. ")")

		--.. a small step back (never runs backwards)
		local before = HandAngle("MinuteHand")
		SetClock(15.05)
		Frames(ctx, 10)
		check(near(HandAngle("MinuteHand"), before, 0.5), tag .. "holds when the clock steps back a little")

		--.. the LIVE cycle (DayNightCycle, BRIGHT NIGHT 2026-09-23): the day loop stops just short of 16 (15.9972, no
		--.. 16:00 strike), then IsNight = true for 10 s while ClockTime STAYS at 15.9972. The x1.25 run plays a
		--.. NightClockTime = 0 setup instead (ClockTime tweened 16 -> 0 in 0.5 s): the dial must not care.
		local DAY_END, CLOCK_RATE, NIGHT_S = 15.9972, 5 / 180, 10
		local legacyNight = scale ~= 1
		local chimes0b = Plays("ClockChime")
		for i = 1, 60 do SetClock(15.05 + (DAY_END - 15.05) * i / 60) Frames(ctx, 1, 1 / 30) end
		Frames(ctx, 90, 1 / 30)
		check(Plays("ClockChime") == chimes0b, tag .. "the day ends at 15.9972 with no strike")

		--.. night falls: the hands whirr FORWARD 16 -> 24 (1.6 s) onto midnight, the moon comes up, twelve strikes
		local chimes1 = Plays("ClockChime")
		workspace:SetAttribute("IsNight", true)
		local nightT = 0
		for i = 1, 15 do
			if legacyNight then SetClock(DAY_END * (1 - i / 15)) end
			Frames(ctx, 1, 1 / 30)
			nightT += 1 / 30
		end
		local midWhirr = HandAngle("HourHand")
		check(midWhirr > 150 and midWhirr < 300, tag .. "night falls: the hands are whirring forward 0.5 s in (" .. midWhirr .. ")")
		for _ = 1, 45 do Frames(ctx, 1, 1 / 30) nightT += 1 / 30 end
		check(near(HandAngle("MinuteHand") % 360, 0, 0.5) or near(HandAngle("MinuteHand"), 360, 0.5), tag .. "midnight: minute hand at 12 (" .. HandAngle("MinuteHand") .. ")")
		check(near(HandAngle("HourHand") % 360, 0, 0.5) or near(HandAngle("HourHand"), 360, 0.5), tag .. "midnight: hour hand at 12 (" .. HandAngle("HourHand") .. ")")
		local moonTop = origin:PointToObjectSpace(Kit.Part(model, "MoonMoon").Position).Y > origin:PointToObjectSpace(Kit.Pivot(model, "MoonCentre")).Y + 0.3 * scale
		check(moonTop, tag .. "the moon is up at midnight")
		while nightT < NIGHT_S - 1e-9 do Frames(ctx, 1, 1 / 30) nightT += 1 / 30 end
		local nightChimes = Plays("ClockChime") - chimes1
		check(nightChimes >= 7 and nightChimes <= 12, tag .. "midnight strikes during the 10 s night (" .. nightChimes .. ")")
		check(near(HandAngle("HourHand") % 360, 0, 0.5) or near(HandAngle("HourHand"), 360, 0.5), tag .. "still midnight at the end of the night (" .. HandAngle("HourHand") .. ")")

		--.. day breaks: IsNight off, ClockTime 11.0 and RUNNING (5/180 h/s) while the hands whirr 11 h (~2.2 s):
		--.. they land ~11:04, which still strikes eleven (after midnight's last strikes); the sun comes up
		workspace:SetAttribute("IsNight", false)
		local clock = 11.0
		local function DayFrames(n)
			for _ = 1, n do
				SetClock(clock)
				Frames(ctx, 1, 1 / 30)
				clock += CLOCK_RATE / 30
			end
		end
		DayFrames(45)
		check(not near(HandAngle("HourHand"), 330, 3), tag .. "still whirring 1.5 s into an 11 h jump (" .. HandAngle("HourHand") .. ")")
		DayFrames(45)
		local want = (clock % 12) * 30
		check(near(HandAngle("HourHand"), want, 0.5), tag .. "daybreak: hour hand follows the running clock at ~11 (" .. HandAngle("HourHand") .. " vs " .. want .. ")")
		DayFrames(30 * 30)
		check(clock < 12, tag .. "(the test stays before noon: " .. clock .. ")")
		check(Plays("ClockChime") - chimes1 == 23, tag .. "night + daybreak strike twelve then eleven (" .. (Plays("ClockChime") - chimes1) .. " = 23?)")
		local sunUp = origin:PointToObjectSpace(Kit.Part(model, "MoonSun").Position).Y > origin:PointToObjectSpace(Kit.Pivot(model, "MoonCentre")).Y
		check(sunUp, tag .. "the sun is above the moon-dial centre by day")

		--.. noon strikes twelve (time passing, not a whirr), and no hour ever strikes twice
		local chimes3 = Plays("ClockChime")
		while clock < 12.1 do DayFrames(30) end
		DayFrames(20 * 30)
		check(Plays("ClockChime") - chimes3 == 12, tag .. "noon strikes twelve (" .. (Plays("ClockChime") - chimes3) .. ")")

		--.. cleanup: every part back as shipped
		Stop(ctx)
		local worst = 0
		for p, cf in pairs(homes) do
			worst = math.max(worst, (p.CFrame.Position - cf.Position).Magnitude, (p.CFrame.LookVector - cf.LookVector).Magnitude, (p.CFrame.UpVector - cf.UpVector).Magnitude)
		end
		check(worst < 1e-4, tag .. "cleanup restores the shipped pose (" .. worst .. ")")
	end
end

print(("%d checks, %d failed"):format(checks, fails))
if fails > 0 then print("FAIL") end
