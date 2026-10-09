--[[
	GamingDesk headless test (tests/HomeOffice, `py gen.py` runs it after tests.luau), 2026-09-24: the PLAYABLE
	CUKE RUN. It replaces the self-playing desk's block that tests.luau had. Everything runs on a mock network
	(latency both ways, the framework's 12 actions / s budget): the server half, the gamer's client (the CukeRun GUI,
	driven through its bound keys by a planning bot that uses the module's own simulation), a spectator and a late
	joiner, each with its own copy of the client module.
	  1. the simulation: fair courses, determinism, late events rolling back, the score rate vs the server's limit
	  2. end to end: GUI, relays, sync, two hitches on the gamer's client only, the crash, PLAY AGAIN, click / touch,
	     EXIT mid-run with the end heard late (the replays go back to Fun_EndTick), death, cleanup
	  3. the desk itself at x1 yaw 37 and x1.3 yaw -120: the seat, the three screen slices, the attract loop, RGB,
	     the chair's swivel, a replay with no inputs, night, a move while seated, cleanup
]]

------------------------------------------------------------------ environment (Roblox services the desk uses)
local env = getfenv(1)
local realOs = os
MockClock = 1000
os = setmetatable({clock = function() return MockClock end}, {__index = realOs})
local timers = {}
task = {
	delay = function(t, fn, ...) local a = table.pack(...) table.insert(timers, {at = MockClock + t, fn = function() fn(table.unpack(a, 1, a.n)) end}) end,
	spawn = function(fn, ...) fn(...) end,
	defer = function(fn, ...) local a = table.pack(...) table.insert(timers, {at = MockClock, fn = function() fn(table.unpack(a, 1, a.n)) end}) end,
	wait = function() end,
}
local warns = {}
warn = function(...) local t = table.concat({...}, " ") table.insert(warns, t) print("WARN " .. t) end
rawset(Enum.ContextActionPriority.High, "Value", 3000)
local RS = {IsServer = function() return false end, RenderStepped = MockSignal(), Heartbeat = MockSignal()}
local UIS = {TouchEnabled = false, KeyboardEnabled = true, InputEnded = MockSignal(), InputChanged = MockSignal()}
local CAS = {bound = {}}
function CAS:BindActionAtPriority(name, fn, _, prio, ...) self.bound[name] = {fn = fn, prio = prio, keys = {...}} end
function CAS:UnbindAction(name) self.bound[name] = nil end
local baseGame = game
game = {GetService = function(_, n)
	if n == "RunService" then return RS end
	if n == "UserInputService" then return UIS end
	if n == "ContextActionService" then return CAS end
	return baseGame:GetService(n)
end}
local PlayersSvc = baseGame:GetService("Players")

------------------------------------------------------------------ loader
local function load(name)
	local fn, err = loadstring(SOURCES[name], name)
	assert(fn, err)
	setfenv(fn, env)
	return fn()
end
local loaded = {}
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
local FunAssets = require({Name = "FunAssets"})

local fails, checks = 0, 0
local function check(ok, msg)
	checks += 1
	if not ok then fails += 1 print("FAIL " .. msg) end
end
local function info(msg) print("  " .. msg) end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function vnear(a, b, eps) return (a - b).Magnitude <= (eps or 1e-6) end

local function DeepCopy(v)
	if type(v) ~= "table" or rawget(v, "_p") then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = DeepCopy(x) end
	return t
end

------------------------------------------------------------------ JSON + GUI dumps (gen.py renders them to screens/*.png)
local function JSON(v)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "0" end
		return string.format("%.4g", v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", string.byte(c)) end) .. '"'
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local out = {}
			for _, x in ipairs(v) do table.insert(out, JSON(x)) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local out = {}
		for k, x in pairs(v) do table.insert(out, JSON(tostring(k)) .. ":" .. JSON(x)) end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

--.. walk GUI objects: UDim2 scale + offset, AnchorPoint, gradients (mean colour), border strokes, texts
local function Walk(inst, ax, ay, pw, ph, items)
	local order = {}
	for i, k in ipairs(inst:GetChildren()) do
		if k.ClassName == "Frame" or k.ClassName == "TextLabel" or k.ClassName == "TextButton" then table.insert(order, {k, i}) end
	end
	table.sort(order, function(a, b)
		if (a[1].ZIndex or 1) ~= (b[1].ZIndex or 1) then return (a[1].ZIndex or 1) < (b[1].ZIndex or 1) end
		return a[2] < b[2]
	end)
	for _, o in ipairs(order) do
		local k = o[1]
		if k.Visible ~= false then
			local sw = k.Size.X.Scale * pw + k.Size.X.Offset
			local sh = k.Size.Y.Scale * ph + k.Size.Y.Offset
			local ap = k.AnchorPoint or Vector2.new(0, 0)
			local x = ax + k.Position.X.Scale * pw + k.Position.X.Offset - ap.X * sw
			local y = ay + k.Position.Y.Scale * ph + k.Position.Y.Offset - ap.Y * sh
			local corner = k:FindFirstChildOfClass("UICorner")
			local r = corner and (corner.CornerRadius.Scale * math.min(sw, sh) + corner.CornerRadius.Offset) or 0
			local item = {x = x, y = y, w = sw, h = sh, r = r}
			if (k.BackgroundTransparency or 0) < 1 then
				local c = k.BackgroundColor3
				local g = k:FindFirstChildOfClass("UIGradient")
				if g then
					local a, b = g.Color.Keypoints[1].Value, g.Color.Keypoints[#g.Color.Keypoints].Value
					c = Color3.new((a.R + b.R) / 2, (a.G + b.G) / 2, (a.B + b.B) / 2)
				end
				item.c = {c.R, c.G, c.B}
				item.bt = k.BackgroundTransparency or 0
			end
			for _, s in ipairs(k:GetChildren()) do
				if s.ClassName == "UIStroke" and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
					item.sc = {s.Color.R, s.Color.G, s.Color.B}
					item.st = s.Thickness
				end
			end
			if item.c or item.sc then table.insert(items, item) end
			if k.ClassName ~= "Frame" and (k.Text or "") ~= "" then
				local c = k.TextColor3 or Color3.new(1, 1, 1)
				table.insert(items, {x = x, y = y, w = sw, h = sh, text = k.Text, tc = {c.R, c.G, c.B}, tt = k.TextTransparency or 0,
					ts = (not k.TextScaled) and k.TextSize or nil, align = tostring(k.TextXAlignment or "Center"):match("([%a]+)$")})
			end
			if k.ClipsDescendants then
				local sub = {}
				Walk(k, x, y, sw, sh, sub)
				for _, it in ipairs(sub) do
					--.. crude clip: drop what lies wholly outside
					if it.x < x + sw and it.x + it.w > x and it.y < y + sh and it.y + it.h > y then table.insert(items, it) end
				end
			else
				Walk(k, x, y, sw, sh, items)
			end
		end
	end
end

local function DumpGui(name, panel)
	local items = {}
	local w, h = panel.Size.X.Offset, panel.Size.Y.Offset
	local holder = {GetChildren = function() return {panel} end}
	local pos, ap = panel.Position, panel.AnchorPoint
	rawget(panel, "_p").Position = UDim2.fromOffset(0, 0)
	rawget(panel, "_p").AnchorPoint = Vector2.new(0, 0)
	Walk(holder, 0, 0, w, h, items)
	rawget(panel, "_p").Position = pos
	rawget(panel, "_p").AnchorPoint = ap
	print("GUIDUMP " .. name .. " " .. JSON({{w = w, h = h, items = items}}))
end

local function DumpMonitor(name, cctx)
	local out = {}
	local list = {}
	for _, inst in ipairs(cctx.insts) do
		if inst.ClassName == "Part" and inst.Name:sub(1, 16) == "GamingDeskScreen" then table.insert(list, inst) end
	end
	table.sort(list, function(a, b) return a.GameScreen.Scene.Position.X.Offset > b.GameScreen.Scene.Position.X.Offset end)
	for _, part in ipairs(list) do
		local items = {}
		local w, h = math.floor(part.Size.X * 90 + 0.5), math.floor(part.Size.Y * 90)
		Walk(part.GameScreen, 0, 0, w, h, items)
		table.insert(out, {w = w, h = h, items = items})
	end
	print("GUIDUMP " .. name .. " " .. JSON(out))
end

------------------------------------------------------------------ the desk, placed (BuildService: scale about the bbox centre)
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

--.. every part (and the hitbox) moved by `delta` (a build MOVE)
local function MoveBuild(model, delta)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
	end
end

------------------------------------------------------------------ network (latency both ways, the framework's 12 actions / s budget)
local LAT = 0.08
local net = {}
local function Deliver(fn, lat) table.insert(net, {at = MockNow + (lat or LAT), fn = fn}) end
local clients = {}
local server = {mod = nil, ctx = nil, model = nil, dropped = 0, budget = {}, actions = {}}
local function ClientEvent(c, action, payload)
	if not c.alive or type(c.mod.OnEvent) ~= "function" then return end
	local ok, err = pcall(c.mod.OnEvent, server.model, action, payload, c.ctx)
	check(ok, "OnEvent " .. tostring(action) .. ": " .. tostring(err))
end
local function ServerAction(player, action, payload)
	local b = server.budget[player]
	if not b or MockClock - b.t >= 1 then b = {t = MockClock, n = 0} server.budget[player] = b end
	b.n += 1
	server.actions[action] = (server.actions[action] or 0) + 1
	if b.n > 12 then server.dropped += 1 return end
	local handler = server.mod.Actions[action]
	if not handler then return end
	local ok, err = pcall(handler, server.model, player, payload, server.ctx)
	check(ok, "server action " .. action .. ": " .. tostring(err))
end

local function MakeServerCtx(model)
	local ctx = {Model = model, Key = "GamingDesk", Base = "GamingDesk", Scale = Kit.Scale(model), _alive = true, everys = {}, seats = {}}
	function ctx:Alive() return self._alive end
	function ctx:Connect(sig, fn) return sig:Connect(fn) end
	function ctx:Add(i) return i end
	function ctx:OnCleanup() end
	function ctx:SetState(k, v) model:SetAttribute("Fun_" .. k, v) end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:Fire(action, payload)
		local p = DeepCopy(payload)
		for _, c in ipairs(clients) do
			local cc = c
			Deliver(function() ClientEvent(cc, action, DeepCopy(p)) end)
		end
	end
	function ctx:FireTo(player, action, payload)
		local p = DeepCopy(payload)
		for _, c in ipairs(clients) do
			if c.player == player then
				local cc = c
				Deliver(function() ClientEvent(cc, action, p) end)
			end
		end
	end
	function ctx:Every(sec, fn) table.insert(self.everys, {sec = sec, fn = fn, next = MockClock + sec}) end
	function ctx:Heartbeat() end
	function ctx:HumanoidOf(player)
		local ch = player.Character
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then return h, ch:FindFirstChild("HumanoidRootPart") end
		return nil
	end
	function ctx:Near() return true end
	function ctx:IsOwner() return true end
	function ctx:Seat(cframe, opts)
		local seat = Instance.new("Seat")
		seat.Name = opts.Name or "FunSeat"
		seat.Size = opts.Size or Vector3.new(2, 0.4, 2)
		seat.CFrame = cframe
		seat.Anchored = true
		table.insert(self.seats, {Seat = seat, Opts = opts})
		return seat
	end
	return ctx
end

local function MakeClientCtx(model, mod, player, hum, root)
	local ctx = {Model = model, Key = "GamingDesk", Base = "GamingDesk", Scale = Kit.Scale(model), Player = player, _alive = true,
		steps = {}, insts = {}, cleanups = {}, StepRange = mod.StepRange or 180}
	function ctx:Alive() return self._alive end
	function ctx:Connect(sig, fn) return sig:Connect(fn) end
	function ctx:Add(i) table.insert(self.insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self.cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn)
		local name = "Fun_" .. k
		model:GetAttributeChangedSignal(name):Connect(function() fn(model:GetAttribute(name)) end)
		fn(model:GetAttribute(name))
	end
	function ctx:Send(action, payload)
		local p = DeepCopy(payload)
		Deliver(function() ServerAction(player, action, p) end)
	end
	function ctx:CameraDistance() return 12 end
	function ctx:Step(fn) table.insert(self.steps, fn) end
	function ctx:Every() end
	function ctx:Sound(parent, id, props) local s = Kit.MakeSound(id, props) s.Parent = parent table.insert(self.insts, s) return s end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = workspace.CurrentCamera end
		table.insert(self.insts, p)
		return p
	end
	function ctx:LocalCharacter()
		if hum.Health > 0 then return hum, root, player.Character end
		return nil
	end
	function ctx:Near() return true end
	function ctx:IsOwner() return true end
	return ctx
end

local function MakePlayer(id, name)
	local p = Instance.new("Player")
	p.Name = name
	p.UserId = id
	p.DisplayName = name
	local gui = Instance.new("Folder")
	gui.Name = "PlayerGui"
	gui.Parent = p
	local char = Instance.new("Model")
	char.Name = name
	char.Parent = workspace
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	p.Character = char
	table.insert(MockPlayers, p)
	return p, hum, root
end

--.. a client: its own copy of the client module (LocalPlayer is read at load)
local function AddClient(model, player, hum, root)
	rawget(PlayersSvc, "_p").LocalPlayer = player
	local mod = load("C_GamingDesk")
	local ctx = MakeClientCtx(model, mod, player, hum, root)
	local c = {mod = mod, ctx = ctx, player = player, hum = hum, alive = true}
	table.insert(clients, c)
	local ok, res = pcall(mod.Client, model, ctx)
	check(ok, "Client() errored: " .. tostring(res))
	if ok and type(res) == "function" then table.insert(ctx.cleanups, res) end
	return c
end

--.. sit down / get up (PhysicsTick below unseats a humanoid whose Sit went false, like the engine does)
local function Sit(seat, hum)
	local weld = Instance.new("Weld")
	weld.Name = "SeatWeld"
	weld.Parent = seat
	hum.SeatPart, hum.Sit = seat, true
	seat.Occupant = hum
end

------------------------------------------------------------------ the frame loop
local BotHook = nil
local PreStep = nil                  -- after the network delivered, before any client runs
local Hitch = {left = 0, dt = 0}     -- the GAMER's client frozen (a hitch): no GUI frame, no Step, no bot
local function PhysicsTick()
	for _, rec in ipairs(server.ctx and server.ctx.seats or {}) do
		local seat = rec.Seat
		local hum = seat.Occupant
		if hum and (not seat:FindFirstChild("SeatWeld") or hum.Jump == true or hum.Sit == false) then
			local w = seat:FindFirstChild("SeatWeld")
			if w then w:Destroy() end
			hum.SeatPart = nil
			hum.Sit = false
			hum.Jump = false
			seat.Occupant = nil
		end
	end
end
local function Frame(dt)
	dt = dt or 1 / 60
	MockNow += dt
	MockClock += dt
	local due = {}
	local i = 1
	while i <= #net do
		if net[i].at <= MockNow then table.insert(due, table.remove(net, i)) else i += 1 end
	end
	for _, m in ipairs(due) do m.fn() end
	i = 1
	while i <= #timers do
		if timers[i].at <= MockClock then local t = table.remove(timers, i) t.fn() else i += 1 end
	end
	if server.ctx then
		for _, e in ipairs(server.ctx.everys) do
			if MockClock >= e.next then e.next += e.sec e.fn() end
		end
	end
	PhysicsTick()
	if PreStep then PreStep() end
	if Hitch.left <= 0 and BotHook then BotHook() end -- (the bot may start a hitch)
	local frozen = Hitch.left > 0
	if frozen then
		Hitch.left -= dt
		Hitch.dt += dt
	else
		RS.RenderStepped:Fire(Hitch.dt + dt) -- the frame after a hitch is as long as the hitch
		Hitch.dt = 0
	end
	for _, c in ipairs(clients) do
		if c.alive and not (frozen and c.gamer) then
			for _, fn in ipairs(c.ctx.steps) do
				local ok, err = pcall(fn, dt, MockNow)
				if not ok then check(false, "Step errored: " .. tostring(err)) end
			end
		end
	end
end
local function Run(seconds, dt)
	dt = dt or 1 / 60
	for _ = 1, math.floor(seconds / dt + 0.5) do Frame(dt) end
end

--.. a fresh world for the next section (the earlier clients are stopped by then)
local function ResetWorld()
	for _, c in ipairs(clients) do
		c.alive = false
		c.ctx._alive = false
	end
	table.clear(clients)
	table.clear(net)
	table.clear(timers)
	server.ctx, server.model = nil, nil
	server.budget = {}
	BotHook, PreStep = nil, nil
	Hitch.left, Hitch.dt = 0, 0
	LAT = 0.08
end

--.. sounds: count plays by SoundId
local plays = {}
local function WrapSounds(list)
	for _, inst in ipairs(list) do
		if inst.ClassName == "Sound" and not rawget(inst, "_wrapped") then
			rawset(inst, "_wrapped", true)
			local id = inst.SoundId
			rawset(inst, "Play", function(self)
				plays[id] = (plays[id] or 0) + 1
				rawget(self, "_p").IsPlaying = true
			end)
		end
	end
end
local function Plays(name) return plays[FunAssets.Sfx[name]] or 0 end

------------------------------------------------------------------ a planning bot (uses the module's own simulation)
local SimMod = load("C_GamingDesk")
local Sim = SimMod.Sim
local K = Enum.KeyCode

--.. simulate a copy of the run with extra events until x passes untilX and the hero has landed
local function Simulate(run, extraTicks, extraKinds, untilX)
	local s0 = run.Sim
	local c = Sim.NewSim()
	Sim.Restore(c, Sim.Snapshot(s0))
	c.Got = {}
	local ticks, kinds = {}, {}
	for i = s0.Ev, #run.Ticks do table.insert(ticks, run.Ticks[i]) table.insert(kinds, run.Kinds[i]) end
	for i = 1, #extraTicks do table.insert(ticks, extraTicks[i]) table.insert(kinds, extraKinds[i]) end
	c.Ev = 1
	local n = 0
	while (c.X < untilX or not c.Ground) and not c.Dead and n < 4000 do
		Sim.StepSim(c, run.Course, ticks, kinds)
		n += 1
	end
	return not c.Dead, c
end

--.. decide this frame: returns a list of "jump" / "jumpUp" / "duck" / "duckUp"
local function BotDecide(bot, run)
	local s = run.Sim
	local out = {}
	local nextTick = s.N + 1
	if bot.jumpHeld and nextTick >= bot.releaseAt then
		table.insert(out, "jumpUp")
		bot.jumpHeld = false
	end
	if bot.duckHeld and s.Obs > bot.duckObs then
		table.insert(out, "duckUp")
		bot.duckHeld = false
	end
	if s.X > (bot.stopAtX or math.huge) or bot.jumpHeld or bot.duckHeld then return out end
	local course = run.Course
	Sim.Extend(course, s.X + 200)
	local j = s.Obs
	local kind = course.Kind[j]
	local spec = Sim.Kinds[kind]
	local ox = course.X[j]
	if kind == "drone" then
		if ox - spec.Half - (s.X + Sim.HeroHalf) < 3 + Sim.Speed(s.X) * 0.04 then
			table.insert(out, "duck")
			bot.duckHeld, bot.duckObs = true, j
		end
		return out
	end
	if not s.Ground or ox - s.X > 70 then return out end
	local untilX = ox + spec.Half + Sim.HeroHalf + 0.5
	for _, h in ipairs(bot.holds or {1, 6, 10, 14, 24}) do
		if Simulate(run, {nextTick, nextTick + h + 1}, {0, 1}, untilX) and Simulate(run, {nextTick, nextTick + h + 2}, {0, 1}, untilX) then
			table.insert(out, "jump")
			bot.jumpHeld, bot.releaseAt = true, nextTick + h + 1
			bot.lastHold = h
			return out
		end
	end
	return out
end

local CODES = {jump = 0, jumpUp = 1, duck = 2, duckUp = 3}

--.. sim only: a bot plays seed for up to `seconds` at 60 fps (2 ticks a frame), like the GUI does
local function PlaySim(seed, seconds, bot)
	local run = Sim.NewRun(seed)
	bot = bot or {}
	local frames = math.floor(seconds * 60)
	for f = 1, frames do
		for _, k in ipairs(BotDecide(bot, run)) do
			table.insert(run.Ticks, run.Sim.N + 1)
			table.insert(run.Kinds, CODES[k])
		end
		Sim.Advance(run, f * 2, 900, nil)
		if run.Sim.Dead then break end
	end
	return run
end

------------------------------------------------------------------ 1. the simulation: fair courses, determinism, score rate
do
	print("== simulation")
	local survived, total, bestRate, deaths = 0, 0, 0, {}
	local drones, doubles, coinsSeen = 0, 0, 0
	for seed = 1, 24 do
		local run = PlaySim(seed * 7919, 150)
		total += 1
		local s = run.Sim
		local secs = s.N / 120
		bestRate = math.max(bestRate, Sim.Score(s) / math.max(secs, 1))
		if not s.Dead then
			survived += 1
		else
			local j = s.Obs
			table.insert(deaths, ("seed %d died at %.1fs x=%.0f v=%.1f obstacle %d %s (prev %s gap %.1f)"):format(seed * 7919, secs, s.X, Sim.Speed(s.X), j,
				tostring(run.Course.Kind[j]), tostring(run.Course.Kind[j - 1]), run.Course.X[j] - (run.Course.X[j - 1] or 0)))
		end
		for i = 1, run.Course.N do
			if run.Course.Kind[i] == "drone" then drones += 1 elseif run.Course.Kind[i] == "double" then doubles += 1 end
			if run.Course.CoinX[i] then coinsSeen += 1 end
		end
		check(Sim.Score(s) <= secs * 80 + 150, ("seed %d: score %d within the server's plausibility (%.1f s)"):format(seed, Sim.Score(s), secs))
	end
	for _, d in ipairs(deaths) do print("  " .. d) end
	info(("bot survived %d / %d runs of 150 s; drones %d, doubles %d, coins %d; best points/s %.1f"):format(survived, total, drones, doubles, coinsSeen, bestRate))
	check(survived == total, "a planning bot survives every 150 s course (gaps always jumpable)")

	--.. determinism: the same seed + events -> the same bits; a replay fed in pieces (with rollbacks) ends identical
	local a = PlaySim(4242, 60)
	local b = Sim.NewRun(4242)
	for i = 1, #a.Ticks do table.insert(b.Ticks, a.Ticks[i]) table.insert(b.Kinds, a.Kinds[i]) end
	Sim.Advance(b, a.Sim.N, 100000, nil)
	check(b.Sim.X == a.Sim.X and b.Sim.Y == a.Sim.Y and b.Sim.Coins == a.Sim.Coins and b.Sim.Dead == a.Sim.Dead, "replay from the full list is bit-identical")
	local r = Sim.NewRun(4242)
	local fed = 0
	local rng = Random.new(5)
	local target = 0
	while target < a.Sim.N do
		target = math.min(a.Sim.N, target + 4)
		--.. events arrive late and in bunches: up to 40 ticks after they happened
		while fed < #a.Ticks and a.Ticks[fed + 1] <= target - rng:NextInteger(0, 40) do
			fed += 1
			Sim.AddCode(r, a.Ticks[fed] * 4 + a.Kinds[fed])
		end
		Sim.Advance(r, target, 900, nil)
	end
	while fed < #a.Ticks do fed += 1 Sim.AddCode(r, a.Ticks[fed] * 4 + a.Kinds[fed]) end
	Sim.Advance(r, a.Sim.N, 100000, nil)
	check(r.Sim.X == a.Sim.X and r.Sim.Y == a.Sim.Y and r.Sim.Coins == a.Sim.Coins and r.Sim.N == a.Sim.N, "late events roll back and the replay ends identical")
	--.. no input: the hero hits the first obstacle ~2.5 s in (MIN_SECONDS 2 on the server)
	local idle = Sim.NewRun(99)
	Sim.Advance(idle, 120 * 30, 100000, nil)
	check(idle.Sim.Dead and idle.Sim.DeadTick / 120 > 2, ("no input crashes at the first obstacle after 2 s (%.2f s)"):format(idle.Sim.DeadTick / 120))
	--.. a tap is lower than a held jump
	local function Peak(hold)
		local run = Sim.NewRun(1)
		table.insert(run.Ticks, 10) table.insert(run.Kinds, 0)
		table.insert(run.Ticks, 10 + hold) table.insert(run.Kinds, 1)
		local peak = 0
		for t = 1, 100 do Sim.Advance(run, t, 10, nil) peak = math.max(peak, run.Sim.Y) end
		return peak
	end
	local tap, full = Peak(1), Peak(60)
	info(("jump peaks: tap %.1f px, held %.1f px"):format(tap, full))
	check(tap > 7 and tap < 9.5 and full > 14 and full < 16.5, "tap ~8 px, held ~15 px")
end

------------------------------------------------------------------ 2. end to end: the server, the gamer's GUI, a spectator, a late joiner
local Begin, End = Enum.UserInputState.Begin, Enum.UserInputState.End
local function KeyInput(key, state)
	local b = CAS.bound.CukeRunControls
	if not b then return false end
	b.fn("CukeRunControls", state, {KeyCode = key, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.new(0, 0, 0)})
	return true
end
local function MonitorText(c, name)
	for _, inst in ipairs(c.ctx.insts) do
		if inst.ClassName == "Part" and inst.Name == "GamingDeskScreenC" then
			local l = inst.GameScreen.Scene:FindFirstChild(name)
			return l and l.Text
		end
	end
	return nil
end
local function Same(a, b) return a.X == b.X and a.Y == b.Y and a.Coins == b.Coins and a.Dead == b.Dead end

do
	print("== end to end")
	server.mod = load("S_GamingDesk")
	local model = MakePlaced("GamingDesk", 1, CFrame.new(40, 3, -20) * CFrame.Angles(0, math.rad(25), 0))
	server.model = model
	server.ctx = MakeServerCtx(model)
	local ok, err = pcall(server.mod.Server, model, server.ctx)
	check(ok, "Server(): " .. tostring(err))
	local seat = server.ctx.seats[1].Seat
	check(seat.Name == "GamingDeskSeat" and server.ctx.seats[1].Opts.Prompt == "Game", "the Game seat")
	local gp, gh, groot = MakePlayer(101, "CukeMaster9000")
	local sp, sh, sroot = MakePlayer(202, "Watcher")
	local lp, lh, lroot = MakePlayer(303, "LateJoiner")
	local gamer = AddClient(model, gp, gh, groot)
	gamer.gamer = true
	local spect = AddClient(model, sp, sh, sroot)
	WrapSounds(gamer.ctx.insts)
	WrapSounds(spect.ctx.insts)
	Run(1)
	check(MonitorText(spect, "Big") == "CUKE RUN", "attract title (" .. tostring(MonitorText(spect, "Big")) .. ")")
	DumpMonitor("desk_attract", spect.ctx)

	--.. sit down
	Sit(seat, gh)
	local seed1 = model:GetAttribute("Fun_Seed")
	check(model:GetAttribute("Fun_Player") == 101 and (seed1 or 0) ~= 0, "server: Player + Seed on sit")
	Run(0.05)
	local g = gamer.ctx.Desk.Game
	check(g ~= nil and gp.PlayerGui:FindFirstChild("CukeRun") ~= nil, "the gamer's CukeRun GUI opened")
	check(spect.ctx.Desk.Game == nil and sp.PlayerGui:FindFirstChild("CukeRun") == nil, "no GUI for the spectator")
	local b = CAS.bound.CukeRunControls
	check(b ~= nil and b.prio > 3000 and table.find(b.keys, K.Space) ~= nil and table.find(b.keys, K.ButtonA) ~= nil, "Space / pad A sunk above the PlayerModule")
	if not g then print("FAIL no game, stopping") return end
	WrapSounds(g.ui.Gui:GetChildren())
	--.. Space during READY: sunk, no event, still seated
	KeyInput(K.Space, Begin)
	KeyInput(K.Space, End)
	Run(0.5)
	check(g.state == "ready" and #g.run.Ticks == 0 and seat.Occupant == gh, "READY: Space does nothing (" .. g.state .. ")")
	check(g.ui.Count.Text == "READY?", "READY? on the GUI (" .. g.ui.Count.Text .. ")")
	check(MonitorText(spect, "Big") == "READY?" and MonitorText(spect, "Name") == "P1 CUKEMASTER90", "READY? + P1 name on the monitor")
	DumpGui("gui_ready", g.ui.Panel)
	DumpMonitor("desk_ready", spect.ctx)
	Run(1.1)
	check(g.state == "play", "GO -> play")

	--.. the bot plays; the gamer's sim is recorded to compare the spectators with. Two hitches on the gamer's client
	--.. ONLY (its GUI, Step and bot frozen while the server and the spectators run on): 0.6 s from ~26 s and 1.0 s
	--.. from ~31 s, each started where the next obstacle is far enough away to survive it
	local bot = {}
	local rec = {}
	local seedNow = seed1
	local droneDumped = false
	local hitchArm, hitches = nil, {}
	BotHook = function()
		local game_ = gamer.ctx.Desk.Game
		if not game_ or not game_.run or game_.state ~= "play" or game_.run.Sim.Dead then return end
		if game_.run.Seed ~= seedNow then seedNow, bot, rec = game_.run.Seed, {}, {} end
		local s = game_.run.Sim
		rec[s.N] = {X = s.X, Y = s.Y, Coins = s.Coins, Dead = s.Dead}
		if hitchArm and s.Ground and not bot.jumpHeld and not bot.duckHeld then
			local course = game_.run.Course
			Sim.Extend(course, s.X + 400)
			local j = s.Obs
			local clear = course.X[j] - Sim.Kinds[course.Kind[j]].Half - (s.X + Sim.HeroHalf)
			if clear > Sim.Speed(s.X) * (hitchArm + 0.4) + 6 then
				Hitch.left = hitchArm
				table.insert(hitches, {At = s.N, Len = hitchArm, Since = game_.since})
				hitchArm = nil
				return
			end
		end
		for _, k in ipairs(BotDecide(bot, game_.run)) do
			if k == "jump" then KeyInput(K.Space, Begin)
			elseif k == "jumpUp" then KeyInput(K.Space, End)
			elseif k == "duck" then KeyInput(K.S, Begin)
			else KeyInput(K.S, End) end
		end
		if not droneDumped and s.DuckHeld and s.Ground then
			droneDumped = true
			DumpGui("gui_duck", game_.ui.Panel)
		end
	end
	--.. rollbacks on the spectator: a relayed input that reached it after its replay passed that tick
	local rollbacks, lastDirty = 0, nil
	PreStep = function()
		local r = spect.ctx.Desk.Run
		local d = r and r.Dirty
		if d and d ~= lastDirty then rollbacks += 1 end
		lastDirty = d
	end
	local matched, compared, afterMatched, afterCompared, falseDead = 0, 0, 0, 0, 0
	local late = nil
	for f = 1, 60 * 45 do
		Frame()
		local r = spect.ctx.Desk.Run
		if r and r.Seed == seedNow and rec[r.Sim.N] then
			compared += 1
			local same = Same(r.Sim, rec[r.Sim.N])
			if same then matched += 1 end
			if hitches[1] and r.Sim.N > hitches[1].At then
				afterCompared += 1
				if same then afterMatched += 1 end
			end
		end
		if r and r.Seed == seedNow and r.Sim.Dead and not g.run.Sim.Dead then falseDead += 1 end
		if f == 60 * 20 then
			late = AddClient(model, lp, lh, lroot)
			info("late joiner added at 20 s")
		end
		if f == 60 * 12 then
			DumpMonitor("desk_run", spect.ctx)
			DumpGui("gui_run", g.ui.Panel)
		end
		if f == 60 * 26 then hitchArm = 0.6 end
		if f == 60 * 31 then hitchArm = 1.0 end
	end
	PreStep = nil
	local gs = g.run.Sim
	info(("after 45 s: x=%.0f v=%.1f score %d coins %d, events %d, spectator matched %d / %d sampled ticks"):format(gs.X, Sim.Speed(gs.X), Sim.Score(gs), gs.Coins, #g.run.Ticks, matched, compared))
	check(not gs.Dead and gs.X > 1500, "the bot is still running after 45 s")
	check(compared > 1000 and matched == compared, "the spectator's monitor replays the actual run")
	--.. the hitches: the gamer's run follows the server clock through them (it skips, it never falls behind), so
	--.. the spectator (0.3 s behind real time) gets every later input in time: no rollback, no false crash
	local hitchText = {}
	for _, h in ipairs(hitches) do table.insert(hitchText, ("%.1f s at %.1f s"):format(h.Len, h.At / 120)) end
	info(("gamer-only hitches: %s; after them the spectator matched %d / %d; rollbacks %d, false-crash frames %d"):format(
		table.concat(hitchText, ", "), afterMatched, afterCompared, rollbacks, falseDead))
	check(#hitches == 2, "both hitches happened (" .. #hitches .. ")")
	check(afterCompared > 300 and afterMatched == afterCompared, "after a hitch the spectator still replays the actual run")
	check(rollbacks == 0, "no input reached the spectator after its replay passed it (" .. rollbacks .. " rollbacks)")
	check(falseDead == 0, "the spectator never showed a crash the gamer did not have (" .. falseDead .. " frames)")
	check(near(g.clock, MockNow - g.since - 1.6, 1e-9), ("the gamer's clock is the server clock after the hitches (%.3f vs %.3f)"):format(g.clock, MockNow - g.since - 1.6))
	check(math.abs(gs.N - math.floor((MockNow - g.since - 1.6) * 120)) <= 1, "the gamer's sim is not behind the server clock")
	check(MonitorText(spect, "Name") == "P1 CUKEMASTER90", "monitor name (" .. tostring(MonitorText(spect, "Name")) .. ")")
	check((MonitorText(spect, "Score") or ""):match("^SCORE %d+$") ~= nil, "monitor score")
	check(Plays("ArcadeBlip") > 5, "jump blips in the GUI (" .. Plays("ArcadeBlip") .. ")")
	check(Plays("Click") > 5, "keyboard clacks (" .. Plays("Click") .. ")")
	check(Plays("Coin") > 3, "coin sounds (" .. Plays("Coin") .. ")")
	check(droneDumped, "ducked under a drone")
	local lr = late and late.ctx.Desk.Run
	check(lr ~= nil and lr.Complete and #lr.Ticks >= #g.run.Ticks - 3 and #lr.Ticks <= #server.ctx.Desk.Codes, "the late joiner synced the list (" .. tostring(lr and #lr.Ticks) .. " / " .. #g.run.Ticks .. ", server " .. #server.ctx.Desk.Codes .. ")")

	--.. crash on purpose
	bot.stopAtX = gs.X + 5
	Run(3)
	check(gs.Dead and g.state == "dead", "crashed")
	local score = Sim.Score(gs)
	check(model:GetAttribute("Fun_Final") == score and model:GetAttribute("Fun_Best") == score, ("server: Final / Best = %d (%s / %s)"):format(score, tostring(model:GetAttribute("Fun_Final")), tostring(model:GetAttribute("Fun_Best"))))
	check((model:GetAttribute("Fun_Ended") or 0) > model:GetAttribute("Fun_Since"), "server: run ended")
	check(model:GetAttribute("Fun_EndTick") == gs.DeadTick, ("server: EndTick = the crash tick (%s vs %d)"):format(tostring(model:GetAttribute("Fun_EndTick")), gs.DeadTick))
	check(Plays("Thump") >= 1, "crash thump")
	local sr = spect.ctx.Desk.Run
	check(sr.Sim.Dead and sr.Sim.DeadTick == gs.DeadTick and Sim.Score(sr.Sim) == score, ("the spectator saw the same crash (tick %s vs %d)"):format(tostring(sr.Sim.DeadTick), gs.DeadTick))
	check(lr ~= nil and lr.Sim.Dead and lr.Sim.DeadTick == gs.DeadTick, "the late joiner saw the same crash")
	check(MonitorText(spect, "Big") == "GAME OVER", "monitor GAME OVER (" .. tostring(MonitorText(spect, "Big")) .. ")")
	check(g.ui.Card.Visible and g.ui.CardScore.Text == tostring(score), "the GUI card shows the score")
	check(g.ui.CardTag.Text:find("NEW DESK RECORD") ~= nil, "new desk record tag (" .. g.ui.CardTag.Text .. ")")
	DumpGui("gui_over", g.ui.Panel)
	DumpMonitor("desk_over", spect.ctx)
	Run(3)
	check(MonitorText(spect, "Big") == "GAME OVER" and seat.Occupant == gh, "still seated: GAME OVER stays on the monitor")

	--.. PLAY AGAIN (Space on the card)
	KeyInput(K.Space, Begin)
	KeyInput(K.Space, End)
	Run(0.5)
	local seed2 = model:GetAttribute("Fun_Seed")
	check(seed2 ~= seed1 and g.run.Seed == seed2 and g.state == "ready" and not g.ui.Card.Visible, "PLAY AGAIN: a new run")
	check(model:GetAttribute("Fun_EndTick") == 0, "a new run clears EndTick")
	Run(10)
	check(g.state == "play" and not g.run.Sim.Dead, "second run going")
	--.. a click on the game view = jump press, the mouse release = jump release (one each)
	local before = #g.run.Ticks
	g.ui.Tap.InputBegan:Fire({UserInputType = Enum.UserInputType.MouseButton1})
	g.ui.Jump.InputBegan:Fire({UserInputType = Enum.UserInputType.MouseButton1}) -- same mouse: no second press
	check(#g.run.Ticks == before + 1 and g.run.Kinds[#g.run.Kinds] == 0, "click on the view = one jump press")
	UIS.InputEnded:Fire({UserInputType = Enum.UserInputType.MouseButton1})
	check(#g.run.Ticks == before + 2 and g.run.Kinds[#g.run.Kinds] == 1, "mouse up = jump release")
	local touch = {UserInputType = Enum.UserInputType.Touch}
	g.ui.Duck.InputBegan:Fire(touch)
	UIS.InputEnded:Fire(touch)
	check(#g.run.Ticks == before + 4 and g.run.Kinds[#g.run.Kinds - 1] == 2 and g.run.Kinds[#g.run.Kinds] == 3, "touch DUCK press / release")
	Run(0.4)
	check(g.state == "play" and not g.run.Sim.Dead, "still running after the extra inputs")
	local forfeit = Sim.Score(g.run.Sim)
	local exitN, exitCoins = g.run.Sim.N, g.run.Sim.Coins
	local run2 = g.run

	--.. EXIT mid-run (Backspace) while the network is slow (0.45 s each way): the score so far counts, they stand up,
	--.. everything unbinds. The spectator's replay (0.3 s behind) runs past the exit before the "Over" is heard, then
	--.. goes back to the run's own last tick (Fun_EndTick): no crash / coins after the exit
	LAT = 0.45
	KeyInput(K.Backspace, Begin)
	local specMax, lateMax = 0, 0
	for _ = 1, 60 do
		Frame()
		local r1, r2 = spect.ctx.Desk.Run, late.ctx.Desk.Run
		if r1 and r1.Seed == seed2 then specMax = math.max(specMax, r1.Sim.N) end
		if r2 and r2.Seed == seed2 then lateMax = math.max(lateMax, r2.Sim.N) end
	end
	LAT = 0.08
	check(gamer.ctx.Desk.Game == nil and gp.PlayerGui:FindFirstChild("CukeRun") == nil, "GUI closed")
	check(CAS.bound.CukeRunControls == nil, "keys unbound")
	check(seat.Occupant == nil and model:GetAttribute("Fun_Player") == 0, "stood up")
	local final2 = model:GetAttribute("Fun_Final")
	check(final2 == forfeit, ("forfeit score counted (%s vs %d)"):format(tostring(final2), forfeit))
	check(model:GetAttribute("Fun_Best") == math.max(score, final2), "best kept")
	check(model:GetAttribute("Fun_EndTick") == exitN, ("server: EndTick = the exit tick (%s vs %d)"):format(tostring(model:GetAttribute("Fun_EndTick")), exitN))
	local s1, s2 = spect.ctx.Desk.Run, late.ctx.Desk.Run
	info(("EXIT at tick %d: the replays reached %d / %d before the end was heard"):format(exitN, specMax, lateMax))
	check(specMax > exitN, "(the slow end made the spectator's replay run past the exit)")
	check(s1.Seed == seed2 and s1.Sim.N == exitN and not s1.Sim.Dead and s1.Sim.Coins == exitCoins,
		("the spectator's replay went back to the exit tick (%d vs %d, dead %s, coins %d vs %d)"):format(s1.Sim.N, exitN, tostring(s1.Sim.Dead), s1.Sim.Coins, exitCoins))
	check(s2.Seed == seed2 and s2.Sim.N == exitN and not s2.Sim.Dead, "the late joiner's replay stops at the exit tick too")
	check(gamer.ctx.Desk.Run == run2 and run2.Sim.N == exitN and not run2.Sim.Dead, "the gamer's own monitor keeps its run, stopped at the exit")
	check(MonitorText(spect, "Big") == "GAME OVER" and MonitorText(spect, "Coins") == "COINS " .. exitCoins, "over after getting up, COINS as at the exit (" .. tostring(MonitorText(spect, "Coins")) .. ")")
	Run(5)
	check(MonitorText(spect, "Big") == "CUKE RUN" and MonitorText(spect, "Score") == "HI " .. string.format("%06d", model:GetAttribute("Fun_Best")), "attract with the HI (" .. tostring(MonitorText(spect, "Score")) .. ")")
	Run(1)
	check(gamer.ctx.Desk.Game == nil, "no reopen after standing up")

	--.. sit again: a fresh GUI; an idle run crashes by itself and reports
	Sit(seat, gh)
	BotHook = nil
	Run(8)
	local g3 = gamer.ctx.Desk.Game
	check(g3 ~= nil and g3.state == "dead", "sat again: GUI reopened, an idle run crashes")
	check(model:GetAttribute("Fun_Ended") > model:GetAttribute("Fun_Since"), "the idle crash ended the run")
	--.. PLAY AGAIN by the button, then the character dies mid-run: the GUI closes, the seat empties, the run ends
	g3.ui.Again.Activated:Fire()
	Run(2.5)
	check(g3.state == "play", "PLAY AGAIN button -> playing (" .. tostring(g3.state) .. ")")
	gh.Health = 0
	gh.Died:Fire()
	seat.Occupant = nil
	Run(1.5)
	check(gamer.ctx.Desk.Game == nil and CAS.bound.CukeRunControls == nil, "death closes the GUI and unbinds")
	check(model:GetAttribute("Fun_Player") == 0 and model:GetAttribute("Fun_Ended") > model:GetAttribute("Fun_Since"), "death ends the run")
	gh.Health = 100

	--.. the build stops (sold / moved): the GUI closes, nothing errors
	for _, c in ipairs(clients) do
		for _, fn in ipairs(c.ctx.cleanups) do
			local okc, e = pcall(fn)
			check(okc, "cleanup: " .. tostring(e))
		end
		c.ctx._alive = false
		c.alive = false
	end
	check(gamer.ctx.Desk.Game == nil and CAS.bound.CukeRunControls == nil, "cleanup closes the GUI")
	info(("server actions: %s; dropped by the 12/s budget: %d"):format(JSON(server.actions), server.dropped))
	check(server.dropped == 0, "no action dropped by the framework's rate limit")
end

------------------------------------------------------------------ 3. the desk itself (x1 yaw 37, x1.3 yaw -120)
local function Screens(c)
	local list = {}
	for _, inst in ipairs(c.ctx.insts) do
		if inst.ClassName == "Part" and inst.Name:sub(1, 16) == "GamingDeskScreen" then
			local gui = inst:FindFirstChild("GameScreen")
			table.insert(list, {Part = inst, Gui = gui, Root = gui and gui:FindFirstChild("Scene")})
		end
	end
	table.sort(list, function(a, b) return a.Root.Position.X.Offset > b.Root.Position.X.Offset end)
	return list
end
local function HudRoot(c)
	for _, s in ipairs(Screens(c)) do
		if s.Root:FindFirstChild("Big") then return s.Root end
	end
	return nil
end
--.. absolute rects of a frame's visible, painted descendants (in the scene root's space)
local function Rects(frame, ax, ay, out)
	out = out or {}
	for _, k in ipairs(frame:GetChildren()) do
		if k.ClassName == "Frame" and k.Visible ~= false then
			local x, y = ax + k.Position.X.Offset, ay + k.Position.Y.Offset
			if (k.BackgroundTransparency or 0) < 1 then table.insert(out, {x, y, x + k.Size.X.Offset, y + k.Size.Y.Offset, k.Name}) end
			Rects(k, x, y, out)
		end
	end
	return out
end
local function Overlap(a, b) return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] end
local function Authored(model, world) return Kit.Origin(model):PointToObjectSpace(world) / Kit.Scale(model) end
local function YawOff(pan, origin) return math.deg(math.acos(math.clamp(pan.CFrame.LookVector:Dot(origin.LookVector), -1, 1))) end

do
	print("== the desk itself")
	for index, spec in ipairs({{1, 37}, {1.3, -120}}) do
		local scale, yawDeg = spec[1], spec[2]
		local tag = ("x%.1f yaw %d: "):format(scale, yawDeg)
		ResetWorld()
		table.clear(plays)
		server.mod = load("S_GamingDesk")
		local model = MakePlaced("GamingDesk", scale, CFrame.new(60, 4, -25) * CFrame.Angles(0, math.rad(yawDeg), 0))
		local origin = Kit.Origin(model)
		server.model = model
		server.ctx = MakeServerCtx(model)

		--..server: the seat..--
		local ok, err = pcall(server.mod.Server, model, server.ctx)
		check(ok, tag .. "Server() errored: " .. tostring(err))
		local rec = server.ctx.seats[1]
		check(rec ~= nil and #server.ctx.seats == 1, tag .. "one seat")
		local seat = rec.Seat
		check(rec.Opts.Prompt == "Game" and rec.Opts.Object == "Gaming Desk", tag .. "prompt 'Game' on 'Gaming Desk'")
		check(seat.CFrame.LookVector:Dot(-origin.LookVector) > 0.9999, tag .. "the sitter faces the desk (authored +Z)")
		local top = seat.CFrame * Vector3.new(0, seat.Size.Y * 0.5, 0)
		check(vnear(top, Kit.Pivot(model, "Seat"), 1e-4), tag .. "seat top on Pivot_Seat")
		check(model:GetAttribute("Fun_Player") == 0 and model:GetAttribute("Fun_Best") == 0 and model:GetAttribute("Fun_Seed") == 0
			and model:GetAttribute("Fun_EndTick") == 0, tag .. "initial state")

		--..the parts the client drives..--
		local swivel = Kit.Parts(model, "Swivel")
		local base = Kit.Parts(model, "ChairLeg")
		local homeSw, homeBase = {}, {}
		for _, p in ipairs(swivel) do homeSw[p] = p.CFrame end
		for _, p in ipairs(base) do homeBase[p] = p.CFrame end
		local rgb = Kit.Parts(model, "RGB")
		local rgbHome = {}
		for _, p in ipairs(rgb) do rgbHome[p] = p.Color end
		check(#swivel >= 15 and #rgb >= 10, tag .. "swivel + RGB parts found (" .. #swivel .. ", " .. #rgb .. ")")
		--.. the client swings the Swivel* parts (anchored) through where the gamer stands: none may collide (fling),
		--.. while the five-star base keeps the chair solid underfoot
		local solidSwivel = {}
		for _, p in ipairs(swivel) do if p.CanCollide then table.insert(solidSwivel, p.Name) end end
		check(#solidSwivel == 0, tag .. "no Swivel* part collides (" .. table.concat(solidSwivel, ", ") .. ")")
		local baseSolid = #base == 5
		for _, p in ipairs(base) do baseSolid = baseSolid and p.CanCollide end
		local chairBase, sleeve = Kit.Part(model, "ChairBase"), Kit.Part(model, "ChairSleeve")
		check(baseSolid and chairBase and chairBase.CanCollide and sleeve and sleeve.CanCollide, tag .. "the chair's base, legs and sleeve still collide")

		--..a watcher's client (the sitter below has none: nobody sends inputs)..--
		local wp, wh, wroot = MakePlayer(500 + index, "Viewer" .. index)
		local sitterP, sitterH = MakePlayer(4200 + index, "CukeMaster9000")
		local watch = AddClient(model, wp, wh, wroot)
		WrapSounds(watch.ctx.insts)
		local screens = Screens(watch)
		check(#screens == 3, tag .. "three screens (got " .. #screens .. ")")
		if #screens == 3 then
			check(screens[1].Part.Name == "GamingDeskScreenL" and screens[2].Part.Name == "GamingDeskScreenC" and screens[3].Part.Name == "GamingDeskScreenR",
				tag .. "slices run L, C, R from the viewer's left")
			local x = 0
			for _, s in ipairs(screens) do
				check(s.Root.Position.X.Offset == -x, tag .. s.Part.Name .. " slice offset " .. x)
				x += math.floor(s.Part.Size.X * 90 + 0.5)
				check(s.Gui.Adornee == s.Part and s.Gui.Face == Enum.NormalId.Front, tag .. s.Part.Name .. " gui on its front face")
				--.. the local screen faces the player and sits in front of its panel + art
				local panel = Kit.Part(model, s.Part.Name:sub(11))
				check(s.Part.CFrame.LookVector:Dot(origin.LookVector) > 0.9, tag .. s.Part.Name .. " faces the front")
				local face = s.Part.CFrame * Vector3.new(0, 0, -s.Part.Size.Z * 0.5)
				local lead = (face - panel.Position):Dot(s.Part.CFrame.LookVector)
				check(lead > 0.025 * scale + 0.01 * scale and lead < 0.1 * scale, tag .. s.Part.Name .. " face just in front of the art (" .. lead .. ")")
				check(near(s.Part.Size.X, panel.Size.X, 1e-6) and near(s.Part.Size.Y, panel.Size.Y, 1e-6), tag .. s.Part.Name .. " covers its panel")
			end
		end

		--..attract mode..--
		Run(1)
		check(MonitorText(watch, "Big") == "CUKE RUN", tag .. "attract title (" .. tostring(MonitorText(watch, "Big")) .. ")")
		check(MonitorText(watch, "Small") == "SIT TO PLAY" or MonitorText(watch, "Small") == "", tag .. "SIT TO PLAY blinks")
		local idleOk = true
		for p, cf in pairs(homeSw) do idleOk = idleOk and vnear(p.CFrame.Position, cf.Position, 1e-4) end
		check(idleOk, tag .. "idle chair stays shipped")
		local changed = false
		for p, c in pairs(rgbHome) do if not (p.Color == c) then changed = true end end
		check(changed, tag .. "RGB colours cycle")
		--.. the attract hero never touches an obstacle (sampled at 30 fps)
		local root = HudRoot(watch)
		local hits = 0
		for _ = 1, 12 * 30 do
			Frame(1 / 30)
			local hero = root:FindFirstChild("Hero")
			local hx, hy = hero.Position.X.Offset, hero.Position.Y.Offset
			local heroRects = Rects(hero, hx, hy)
			for i = 1, 8 do
				local slot = root:FindFirstChild("Obstacle" .. i)
				if slot and slot.Visible then
					for _, r in ipairs(Rects(slot, slot.Position.X.Offset, slot.Position.Y.Offset)) do
						for _, hr in ipairs(heroRects) do
							if hr[5] ~= "Tail" and Overlap(r, hr) then hits += 1 end
						end
					end
				end
			end
		end
		check(hits == 0, tag .. "attract: the hero overlapped an obstacle on " .. hits .. " rect pairs")

		--..sit: the chair swivels to the desk, READY? GO! and the run..--
		Sit(seat, sitterH)
		check(model:GetAttribute("Fun_Player") == sitterP.UserId and near(model:GetAttribute("Fun_Since"), MockNow, 1e-9), tag .. "server: Player + Since on sit")
		Run(20 / 60)
		check(MonitorText(watch, "Big") == "READY?", tag .. "READY? (" .. tostring(MonitorText(watch, "Big")) .. ")")
		check(MonitorText(watch, "Name") == "P1 CUKEMASTER90", tag .. "player name (" .. tostring(MonitorText(watch, "Name")) .. ")")
		Run(50 / 60)
		check(MonitorText(watch, "Big") == "GO!", tag .. "GO! (" .. tostring(MonitorText(watch, "Big")) .. ")")
		Run(1)
		check(Plays("ArcadeBlip") >= 1, tag .. "GO blip played")
		check(MonitorText(watch, "Big") == "", tag .. "big text cleared while running")
		local pan = Kit.Part(model, "SwivelPan")
		check(YawOff(pan, origin) < 3.2, tag .. "chair faces the desk while seated (" .. YawOff(pan, origin) .. " deg off)")
		local seatAt = Authored(model, Kit.Part(model, "SwivelSeat").Position)
		local pivot = model:GetAttribute("Pivot_Seat")
		check(math.abs(seatAt.X - pivot.X) < 0.2 and math.abs(seatAt.Z - pivot.Z) < 0.25, tag .. "seat cushion under the sitter")
		local legsOk = true
		for p, cf in pairs(homeBase) do legsOk = legsOk and vnear(p.CFrame.Position, cf.Position, 1e-6) end
		check(legsOk, tag .. "base legs never move")
		--.. nobody presses anything: the replay shows the hero crashing at the first obstacle while the run is live
		Run(3.5)
		check(MonitorText(watch, "Big") == "GAME OVER" and model:GetAttribute("Fun_Since") > (model:GetAttribute("Fun_Ended") or 0),
			tag .. "a run with no inputs crashes on the monitor (" .. tostring(MonitorText(watch, "Big")) .. ")")
		check(Plays("Thump") >= 1, tag .. "crash thump from the replay")

		--..stand up: the run ends without a score (no "Over" from anyone), GAME OVER, the chair spins back out..--
		sitterH.Sit = false
		local maxYaw = 0
		for _ = 1, 60 do
			Frame(1 / 60)
			maxYaw = math.max(maxYaw, YawOff(pan, origin))
		end
		check(model:GetAttribute("Fun_Player") == 0 and model:GetAttribute("Fun_Final") == 0 and model:GetAttribute("Fun_EndTick") == 0
			and model:GetAttribute("Fun_Ended") > model:GetAttribute("Fun_Since"), tag .. "server: the run ended after the leave grace, no score, no EndTick")
		check(MonitorText(watch, "Big") == "GAME OVER", tag .. "GAME OVER (" .. tostring(MonitorText(watch, "Big")) .. ")")
		check(Plays("ArcadeLose") >= 1, tag .. "no score -> lose sting")
		for _ = 1, 60 do
			Frame(1 / 30)
			maxYaw = math.max(maxYaw, YawOff(pan, origin))
		end
		check(maxYaw > 150, tag .. "the chair spins round when they get up (max " .. maxYaw .. " deg)")
		Run(4)
		check(MonitorText(watch, "Big") == "CUKE RUN", tag .. "back to attract")
		local worst = 0
		for p, cf in pairs(homeSw) do worst = math.max(worst, (p.CFrame.Position - cf.Position).Magnitude) end
		check(worst < 2e-3, tag .. "chair settles exactly on its shipped pose (" .. worst .. ")")

		--..night screen..--
		workspace:SetAttribute("IsNight", true)
		Run(10 / 60)
		if scale == 1 then DumpMonitor("desk_night", watch.ctx) end
		workspace:SetAttribute("IsNight", false)
		Run(2 / 60)

		--..moved while seated: poses follow the hitbox; cleanup restores everything relative to where it IS..--
		Sit(seat, sitterH)
		Run(2)
		local oldHitbox = Kit.Hitbox(model).CFrame
		local hb = Kit.Hitbox(model).CFrame
		MoveBuild(model, CFrame.new(hb.Position + Vector3.new(10, 0, 5)) * CFrame.Angles(0, math.rad(30), 0) * CFrame.new(-hb.Position))
		Run(5 / 60)
		local newHitbox = Kit.Hitbox(model).CFrame
		local panRel = newHitbox:ToObjectSpace(pan.CFrame)
		local sitRel = newHitbox:ToObjectSpace(Kit.Origin(model))
		check(math.deg(math.acos(math.clamp(panRel.LookVector:Dot(sitRel.LookVector), -1, 1))) < 3.2, tag .. "moved: the chair still faces the desk")
		for _, fn in ipairs(watch.ctx.cleanups) do
			local okc, e = pcall(fn)
			check(okc, tag .. "cleanup: " .. tostring(e))
		end
		watch.alive, watch.ctx._alive = false, false
		local worstMove = 0
		for p, cf in pairs(homeSw) do
			local want = newHitbox * oldHitbox:ToObjectSpace(cf)
			worstMove = math.max(worstMove, (p.CFrame.Position - want.Position).Magnitude, (p.CFrame.LookVector - want.LookVector).Magnitude)
		end
		check(worstMove < 1e-4, tag .. "cleanup after a move: chair shipped relative to the new spot (" .. worstMove .. ")")
		local okHome = true
		for p, c in pairs(rgbHome) do if not (p.Color == c) then okHome = false end end
		check(okHome, tag .. "cleanup restores RGB colours")
		sitterH.Sit = false
		Run(0.1)
	end
end

check(#warns == 0, "no warnings (" .. #warns .. ")")
print(("GamingDesk: %d checks, %d failed"):format(checks, fails))
if fails > 0 then print("FAIL") end
