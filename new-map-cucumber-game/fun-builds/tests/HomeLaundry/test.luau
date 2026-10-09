-- Offline scenario test (HomeLaundry, 2026-09-24): the REAL FunBuildService + FunBuildClient + the WashingMachine /
-- Dryer modules in a mock world (world setup adapted from tests/DJBooth/test.luau), models from models/out/*.parts.json.
local SIM = M.SIM
local task = M.task
local Vector3, CFrame, Color3, Enum = M.Vector3, M.CFrame, M.Color3, M.Enum
local fails = 0
local function check(cond, msg)
	if cond then print("  ok   " .. msg) else fails += 1 print("  FAIL " .. msg) end
end

local nativeTypeof = typeof
local function mtypeof(v)
	if type(v) == "table" then
		local k = rawget(v, "__kind")
		if k then return k end
	end
	return nativeTypeof(v)
end
M.typeof = mtypeof

--..DataModel..--
local sounds = {}
local InstanceLib = {new = function(class, parent)
	local i = M.NewInstance(class)
	if class == "Sound" then table.insert(sounds, i) end
	if parent then i.Parent = parent end
	return i
end}
local game = M.NewInstance("DataModel")
game.Name = "Game"
M.SetRoot(game)
rawset(game, "__inDM", true)
local services = {}
local function Service(name, class)
	local s = InstanceLib.new(class or name)
	s.Name = name
	s.Parent = game
	services[name] = s
	return s
end
local workspace = Service("Workspace")
local Players = Service("Players")
local ReplicatedStorage = Service("ReplicatedStorage")
local ServerStorage = Service("ServerStorage")
local CollectionService = Service("CollectionService")
local RunService = Service("RunService")
Service("ServerScriptService")
game.GetService = function(_, name) return services[name] or error("no service " .. name) end
game.Workspace = workspace

--..RemoteEvent methods..--
local localPlayer
M.Methods.FireAllClients = function(self, ...) self.OnClientEvent:Fire(...) end
M.Methods.FireClient = function(self, _, ...) self.OnClientEvent:Fire(...) end
M.Methods.FireServer = function(self, ...) self.OnServerEvent:Fire(localPlayer, ...) end

--..RunService..--
RunService.RenderStepped = M.Signal()
RunService.Heartbeat = M.Signal()
RunService.Stepped = M.Signal()
RunService.IsServer = function() return true end
RunService.IsClient = function() return true end

--..CollectionService..--
local tagged = {}
local addedSig, removedSig = {}, {}
local function sigOf(tbl, tag) tbl[tag] = tbl[tag] or M.Signal() return tbl[tag] end
local function inDM(inst) return inst == game or inst:IsDescendantOf(game) end
CollectionService.AddTag = function(_, inst, tag)
	tagged[tag] = tagged[tag] or {}
	if tagged[tag][inst] then return end
	tagged[tag][inst] = true
	rawget(inst, "__tags")[tag] = true
	if inDM(inst) then sigOf(addedSig, tag):Fire(inst) end
end
CollectionService.RemoveTag = function(_, inst, tag)
	if tagged[tag] then tagged[tag][inst] = nil end
	rawget(inst, "__tags")[tag] = nil
	sigOf(removedSig, tag):Fire(inst)
end
CollectionService.HasTag = function(_, inst, tag) return tagged[tag] ~= nil and tagged[tag][inst] == true end
CollectionService.GetTagged = function(_, tag)
	local out = {}
	for inst in pairs(tagged[tag] or {}) do if inDM(inst) then table.insert(out, inst) end end
	return out
end
CollectionService.GetInstanceAddedSignal = function(_, tag) return sigOf(addedSig, tag) end
CollectionService.GetInstanceRemovedSignal = function(_, tag) return sigOf(removedSig, tag) end
M.OnParented = function(inst, parent)
	local now = parent ~= nil and inDM(parent)
	local list = {inst}
	for _, d in ipairs(inst:GetDescendants()) do table.insert(list, d) end
	for _, i in ipairs(list) do
		local was = rawget(i, "__inDM") == true
		if now ~= was then
			rawset(i, "__inDM", now)
			for tag in pairs(rawget(i, "__tags")) do
				if now then sigOf(addedSig, tag):Fire(i) else sigOf(removedSig, tag):Fire(i) end
			end
		end
	end
end

--..Players..--
local function Character(name, pos)
	local char = InstanceLib.new("Model")
	char.Name = name
	local humanoid = InstanceLib.new("Humanoid", char)
	local root = InstanceLib.new("Part", char)
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(pos)
	return char, humanoid, root
end
localPlayer = InstanceLib.new("Player")
localPlayer.Name = "LocalGuy"
localPlayer.UserId = 1
localPlayer.Parent = Players
local playerGui = InstanceLib.new("PlayerGui", localPlayer)
playerGui.Name = "PlayerGui"
local hud = InstanceLib.new("ScreenGui") -- FunBuildClient hides every fun prompt while its BuildMode attribute is true
hud.Name = "CucumberHUDDesign"
hud:SetAttribute("BuildMode", false)
hud.Parent = playerGui
local char, _, root = Character("LocalGuy", Vector3.new(40, 3, 30))
char.Parent = workspace
localPlayer.Character = char
local other = InstanceLib.new("Player")
other.Name = "Visitor"
other.UserId = 2
other.Parent = Players
local otherChar = Character("Visitor", Vector3.new(36, 3, 36))
otherChar.Parent = workspace
other.Character = otherChar
Players.LocalPlayer = localPlayer
Players.PlayerRemoving = M.Signal()
Players.PlayerAdded = M.Signal()
Players.GetPlayers = function() return {localPlayer, other} end

local camera = InstanceLib.new("Camera", workspace)
camera.Name = "Camera"
camera.CFrame = CFrame.new(40, 8, 28)
workspace.CurrentCamera = camera

--..Modules..--
local cache = {}
local makeEnv
local function mrequire(ms)
	if ms == nil then error("require(nil)") end
	if cache[ms] ~= nil then return cache[ms] end
	local src = rawget(ms, "__source") or error("module without source: " .. tostring(ms))
	local f, err = loadstring(src, "=" .. ms.Name)
	if not f then error(err) end
	setfenv(f, makeEnv(ms))
	local result = f()
	cache[ms] = result
	return result
end
local function warnf(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	local msg = table.concat(parts, " ")
	table.insert(SIM.warns, msg)
	print("  WARN " .. msg)
end
makeEnv = function(scriptInst)
	local env = {
		game = game, workspace = workspace, script = scriptInst, Instance = InstanceLib,
		Vector3 = Vector3, Vector2 = M.Vector2, CFrame = CFrame, Color3 = Color3, UDim = M.UDim, UDim2 = M.UDim2,
		NumberSequence = M.NumberSequence, NumberSequenceKeypoint = M.NumberSequenceKeypoint, NumberRange = M.NumberRange,
		ColorSequence = M.ColorSequence, ColorSequenceKeypoint = M.ColorSequenceKeypoint, Enum = Enum,
		task = task, typeof = mtypeof, type = type, warn = warnf, print = function() end, require = mrequire,
		os = {clock = function() return SIM.now end, time = function() return 1e9 + SIM.now end}, tick = function() return SIM.now end,
		math = math, string = string, table = table, pcall = pcall, xpcall = xpcall, ipairs = ipairs, pairs = pairs, next = next,
		tostring = tostring, tonumber = tonumber, select = select, error = error, assert = assert, setmetatable = setmetatable,
		getmetatable = getmetatable, rawget = rawget, rawset = rawset, rawequal = rawequal, coroutine = coroutine,
		unpack = table.unpack, debug = debug, utf8 = utf8, bit32 = bit32,
	}
	return setmetatable(env, {__index = function(_, k) error("UNKNOWN GLOBAL: " .. tostring(k), 2) end})
end
local function Module(name, parent, source)
	local ms = InstanceLib.new("ModuleScript")
	ms.Name = name
	rawset(ms, "__source", source)
	ms.Parent = parent
	return ms
end
local Modules = InstanceLib.new("Folder", ReplicatedStorage)
Modules.Name = "Modules"
local kitMs = Module("FunBuildKit", Modules, SRC.Kit)
Module("FunAssets", Modules, SRC.FunAssets)
local serverFolder = InstanceLib.new("Folder", ServerStorage)
serverFolder.Name = "FunBehaviours"
Module("WashingMachine", serverFolder, SRC.WMServer)
Module("Dryer", serverFolder, SRC.DryerServer)
local clientFolder = InstanceLib.new("Folder", ReplicatedStorage)
clientFolder.Name = "FunBehavioursClient"
Module("WashingMachine", clientFolder, SRC.WMClient)
Module("Dryer", clientFolder, SRC.DryerClient)

--..Frames..--
local function Frame(dt)
	SIM.now += dt
	M.RunDue()
	RunService.Stepped:Fire(SIM.now, dt)
	RunService.RenderStepped:Fire(dt)
	RunService.Heartbeat:Fire(dt)
end
local function Run(seconds) for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do Frame(1 / 60) end end

local function RunScript(class, name, parent, source)
	local s = InstanceLib.new(class)
	s.Name = name
	s.Parent = parent
	local f, err = loadstring(source, "=" .. name)
	if not f then error(err) end
	setfenv(f, makeEnv(s))
	task.spawn(f)
end
RunScript("Script", "FunBuildService", services.ServerScriptService, SRC.Service)
Run(0.1)
RunScript("LocalScript", "FunBuildClient", localPlayer, SRC.Client)
Run(0.1)
local Kit = mrequire(kitMs)

--..Builds (a template in ReplicatedStorage.PlaceableBuilds + placed copies)..--
local placeable = InstanceLib.new("Folder", ReplicatedStorage)
placeable.Name = "PlaceableBuilds"
local homeFolder = InstanceLib.new("Folder", placeable)
homeFolder.Name = "Home"
local map = InstanceLib.new("Folder", workspace)
map.Name = "Map"
local placed = InstanceLib.new("Folder", map)
placed.Name = "Placed"
local function V(t) return Vector3.new(t[1], t[2], t[3]) end
local function BuildModel(data, scale, placeCF, parent, tag)
	local model = InstanceLib.new("Model")
	model.Name = data.key
	local lo, hi = V(data.min), V(data.max)
	local centre = (lo + hi) * 0.5
	local hitbox = InstanceLib.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (hi - lo) * scale
	hitbox.Transparency = 1
	hitbox.CFrame = placeCF * CFrame.new(centre * scale)
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	for _, p in ipairs(data.parts) do
		local part = InstanceLib.new("Part")
		part.Name = p.name
		part.Size = V(p.size) * scale
		local cf = CFrame.new12(p.cf)
		part.CFrame = placeCF * CFrame.new(cf.Position * scale) * cf.Rotation
		part.Material = Enum.Material[p.material]
		part.Color = Color3.fromHex(p.color)
		part.Transparency = p.transparency
		part.Reflectance = p.reflectance or 0
		part.Anchored = true
		part.CanCollide = p.collide
		part.Parent = model
	end
	for k, v in pairs(data.attrs) do model:SetAttribute(k, v) end
	for k, v in pairs(data.pivots) do model:SetAttribute("Pivot_" .. k, V(v)) end
	model:SetAttribute("BuildKey", data.key)
	model:SetAttribute("Category", "Home")
	model:SetAttribute("Scale", scale)
	model:SetAttribute("AuthoredCentre", centre)
	if tag then model:SetAttribute("Owner", 1) end
	model.Parent = parent
	if tag then CollectionService:AddTag(model, "PlacedBuild") end
	return model
end

--..Helpers..--
local function RestOf(model)
	local hb = model.PrimaryPart.CFrame
	local r = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Hitbox" then r[d] = hb:ToObjectSpace(d.CFrame) end
	end
	return r
end
--.. the biggest distance (studs) a part matching `want(name)` has moved from its rest, relative to the hitbox
local function Dev(model, rest, want)
	local hb = model.PrimaryPart.CFrame
	local worst, who = 0, "-"
	for p, rel in pairs(rest) do
		if p.Parent and (not want or want(p.Name)) then
			local d = (p.CFrame.Position - (hb * rel).Position).Magnitude
			if d > worst then worst, who = d, p.Name end
		end
	end
	return worst, who
end
--.. the biggest change of a matching part's UpVector (|up - restUp|, ~radians for small turns; parts.json rotations are
--.. rounded to 5 decimals, so an untouched part reads ~1e-5), relative to the hitbox
local function DevRot(model, rest, want)
	local hb = model.PrimaryPart.CFrame
	local worst = 0
	for p, rel in pairs(rest) do
		if p.Parent and (not want or want(p.Name)) then
			local a, b = p.CFrame.UpVector, (hb * rel).UpVector
			worst = math.max(worst, (a - b).Magnitude)
		end
	end
	return worst
end
local function Starts(prefix) return function(n) return n:sub(1, #prefix) == prefix end end
local function Wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
local function PartData(data, name)
	for _, p in ipairs(data.parts) do if p.name == name then return p end end
	return nil
end
local function Fixed(n)
	return not (n:sub(1, 4) == "Drum" or n:sub(1, 4) == "Door" or n == "DialKnob" or n == "DialCap" or n == "DialPointer"
		or n == "ButtonStart" or n == "Water" or n:sub(1, 8) == "VentSlat")
end
local function FxSound(name)
	for _, s in ipairs(sounds) do
		if not rawget(s, "__destroyed") and s.Name == name and s.Parent and s.Parent.Name == "LaundryFX" then return s end
	end
	return nil
end
local function Gui()
	for _, g in ipairs(playerGui:GetChildren()) do if g.Name == "LaundryScreen" then return g end end
	return nil
end
local function GuiText(gui, name) local l = gui and gui:FindFirstChild(name, true) return l and l.Text end
local function Now() return workspace:GetServerTimeNow() end
local function SameCF(a, b)
	if (a.Position - b.Position).Magnitude > 1e-9 then return false end
	local ra, rb = M.CFrameRot(a), M.CFrameRot(b)
	for i = 1, 9 do if math.abs(ra[i] - rb[i]) > 1e-9 then return false end end
	return true
end

--..Scene..--
local WM_SCALE, WM_YAW = 1.2, 90
local wmCF = CFrame.new(40, 0, 40) * CFrame.Angles(0, math.rad(WM_YAW), 0)
BuildModel(MODELS.WashingMachine, WM_SCALE, CFrame.new(0, -500, 0), homeFolder, false) -- the template
BuildModel(MODELS.Dryer, 1, CFrame.new(20, -500, 0), homeFolder, false)
print("== place a washing machine (x1.2, yaw 90)")
local washer = BuildModel(MODELS.WashingMachine, WM_SCALE, wmCF, placed, true)
local rest = RestOf(washer)
local hitboxCF = washer.PrimaryPart.CFrame
Run(1)
local startPrompt = washer:FindFirstChild("StartPrompt", true)
local doorPrompt = washer:FindFirstChild("DoorPrompt", true)
check(startPrompt ~= nil and startPrompt.ActionText == "Start" and startPrompt.KeyboardKeyCode == Enum.KeyCode.E, "Start prompt (E)")
check(doorPrompt ~= nil and doorPrompt.ActionText == "Open door" and doorPrompt.KeyboardKeyCode == Enum.KeyCode.F, "Open door prompt (F)")
check(startPrompt and startPrompt.ObjectText == "Washing Machine", "prompt names the machine")
if startPrompt then
	local att = startPrompt.Parent
	local at = att.Parent.CFrame * att.Position
	check((at - Kit.Pivot(washer, "StartPrompt")).Magnitude < 1e-6, "start prompt floats at Pivot_StartPrompt")
end
check(washer:GetAttribute("Fun_CycleEnd") == 0 and washer:GetAttribute("Fun_Door") == false, "idle state: CycleEnd 0, Door false")
local gui = Gui()
check(gui ~= nil and gui.Adornee == washer:FindFirstChild("Screen") and gui.ResetOnSpawn == false, "screen SurfaceGui adorned to Screen")
check(GuiText(gui, "Time") == "READY" and GuiText(gui, "Phase") == "WASH", "screen idle: READY / WASH")
check(Dev(washer, rest) < 1e-9 and DevRot(washer, rest) < 1e-4, ("idle: nothing moved (%.2e)"):format(Dev(washer, rest)))
for _, key in ipairs({"WashingMachine", "Dryer"}) do
	local g = PartData(MODELS[key], "DoorGlass")
	check(g and g.material == "SmoothPlastic" and g.transparency <= 0.6 and g.reflectance > 0,
		key .. ": DoorGlass authored SmoothPlastic (Roblox Glass would hide the water behind it)")
end
check(washer:FindFirstChild("DoorGlass").Material == Enum.Material.SmoothPlastic, "placed DoorGlass left SmoothPlastic")

print("== open the door")
doorPrompt.Triggered:Fire(localPlayer)
Run(0.25)
local mid = Dev(washer, rest, Starts("Door"))
Run(2)
check(washer:GetAttribute("Fun_Door") == true and doorPrompt.ActionText == "Close door", "Door true, prompt says Close door")
local hingeW = Kit.Pivot(washer, "DoorHinge")
local origin = Kit.Origin(washer)
local hingeCF = CFrame.new(hingeW) * origin.Rotation
local handle = washer:FindFirstChild("DoorHandle")
local expected = (hingeCF * CFrame.Angles(0, math.rad(-105), 0) * hingeCF:Inverse() * (washer.PrimaryPart.CFrame * rest[handle])).Position
check((handle.Position - expected).Magnitude < 0.02, ("handle swung -105 deg about the hinge (off %.4f)"):format((handle.Position - expected).Magnitude))
local rel = origin:PointToObjectSpace(handle.Position) / WM_SCALE
check(rel.Z < -3.5 and rel.X > 1.2, ("open door sticks out to the front / +X side: authored %s"):format(tostring(rel)))
check(mid > 0.2, "door was moving after 0.25 s")
check(Dev(washer, rest, Fixed) < 1e-9, "fixed parts untouched while the door swings")

print("== a visitor presses Start with the door open")
startPrompt.Triggered:Fire(other)
Run(0.1)
local cycleEnd = washer:GetAttribute("Fun_CycleEnd")
check(washer:GetAttribute("Fun_Door") == false, "start shuts the door")
check(type(cycleEnd) == "number" and math.abs(cycleEnd - (Now() - 0.1 + 15)) < 0.05, "CycleEnd = now + 15")
check(startPrompt.ActionText == "Stop" and doorPrompt.Enabled == true and doorPrompt.ActionText == "Door locked",
	"prompt says Stop, door prompt reads Door locked (never disabled by the server)")
doorPrompt.Triggered:Fire(localPlayer)
Run(0.1)
check(washer:GetAttribute("Fun_Door") == false, "door can't be opened mid-cycle")
local click = FxSound("Click")
check(click ~= nil and click.IsPlaying, "start click played")

print("== t ~ 3 s: wash")
Run(2.8)
local t = Now() - (cycleEnd - 15)
local water = washer:FindFirstChild("Water")
check(water.Transparency == 0.42 and water.Size.Y > 0.9 * 0.74 * WM_SCALE, ("water in: T %.2f, height %.3f"):format(water.Transparency, water.Size.Y))
check(Dev(washer, rest, Starts("DrumSpoke")) > 0.05, "drum turned")
check(GuiText(gui, "Time") == string.format("0:%02d", math.ceil(15 - t)) and GuiText(gui, "Phase") == "WASH", "screen counts down: " .. tostring(GuiText(gui, "Time")) .. " " .. tostring(GuiText(gui, "Phase")))
local hum = FxSound("Hum")
check(hum ~= nil and hum.IsPlaying and hum.Looped, "hum loop playing near")
check(FxSound("Water") and not FxSound("Water").IsPlaying, "water pour loop quiet mid-wash")
check(SameCF(washer.PrimaryPart.CFrame, hitboxCF), "Hitbox never moves")
local shake, who = Dev(washer, rest, Fixed)
check(shake > 1e-4 and shake < 0.15, ("the machine jiggles a little (%.4f studs, %s)"):format(shake, who))
check(Dev(washer, rest, Starts("DialPointer")) > 0.01, "dial wound")
local led = washer:FindFirstChild("Led")
check(led.Color ~= Color3.fromHex("2d5a2a"), "LED lit")
local suds = workspace.CurrentCamera:FindFirstChild("LaundrySuds")
check(suds and suds:FindFirstChild("Suds").Enabled, "suds on the water")
local lampOn = false
for _, d in ipairs(workspace.CurrentCamera:GetDescendants()) do if d.ClassName == "PointLight" and d.Enabled and d.Brightness > 0.2 then lampOn = true end end
check(lampOn, "drum light on")

print("== clothes tumble (sampled over the wash)")
local drumW = Kit.Pivot(washer, "Drum")
local drumCF = CFrame.new(drumW) * origin.Rotation
local body = washer:FindFirstChild("Body")
--.. the drum frame as the jiggle carries it (Body only ever moves with the jiggle), so cloth radii / angles are exact
local function DrumFrame()
	return body.CFrame * (washer.PrimaryPart.CFrame * rest[body]):Inverse() * drumCF
end
local clothInfo = {}
for i = 1, 4 do
	local p = washer:FindFirstChild("DrumCloth" .. i)
	local q = drumCF:PointToObjectSpace((washer.PrimaryPart.CFrame * rest[p]).Position)
	clothInfo[i] = {Part = p, A0 = math.atan2(q.X, -q.Y), R0 = math.sqrt(q.X * q.X + q.Y * q.Y), InFall = false}
end
local maxA, minA = -10, 10
local landings, badLanding, leftDrum = 0, nil, nil
for _ = 1, 240 do
	Frame(1 / 60)
	local frame = DrumFrame()
	for i, c in ipairs(clothInfo) do
		local q = frame:PointToObjectSpace(c.Part.Position)
		local a = math.atan2(q.X, -q.Y)
		local r = math.sqrt(q.X * q.X + q.Y * q.Y)
		if i == 1 then maxA, minA = math.max(maxA, a), math.min(minA, a) end
		if r / WM_SCALE > 0.9 then leftDrum = ("DrumCloth%d r %.3f"):format(i, r / WM_SCALE) end
		--.. a fall cuts through the middle (radius drops); the frame it lands the cloth is back at its own radius
		if r < c.R0 - 0.01 then
			c.InFall = true
		elseif c.InFall and math.abs(r - c.R0) < 1e-3 then
			c.InFall = false
			landings += 1
			local off = math.abs(Wrap(a - c.A0))
			if off > 0.3 + 1e-3 then badLanding = ("DrumCloth%d landed %.2f rad from its own spot"):format(i, off) end
		end
	end
end
check(leftDrum == nil, "clothes stay in the drum" .. (leftDrum and (": " .. leftDrum) or ""))
check(maxA - minA > 1.2, ("cloth rides up and falls (angle range %.2f rad)"):format(maxA - minA))
check(landings >= 2 and badLanding == nil, ("falling clothes land back near their own authored angle, no pile-up (%d landings%s)")
	:format(landings, badLanding and (": " .. badLanding) or ""))

print("== t ~ 12.5 s: spin")
Run(12.5 - (Now() - (cycleEnd - 15)))
t = Now() - (cycleEnd - 15)
check(GuiText(gui, "Phase") == "SPIN", "phase SPIN at t=" .. string.format("%.2f", t))
check(water.Transparency == 1, "water drained")
check(hum.PlaybackSpeed > 1.2, ("hum pitched up while spinning (%.2f)"):format(hum.PlaybackSpeed))
local spinShake = Dev(washer, rest, Fixed)
check(spinShake > shake * 0.5 and spinShake < 0.2, ("spin jiggles harder (%.4f)"):format(spinShake))

print("== the end")
Run(15.3 - (Now() - (cycleEnd - 15)))
local ding = FxSound("Ding")
check(ding and ding.IsPlaying, "Ding at the end")
local spark = workspace.CurrentCamera:FindFirstChild("LaundryFX"):FindFirstChild("Sparkles", true)
check(spark and (spark.Emitted or 0) >= 16, "sparkle burst off the glass")
check(GuiText(gui, "Time") == "DONE", "screen says DONE")
check(washer:GetAttribute("Fun_CycleEnd") == 0 and startPrompt.ActionText == "Start" and doorPrompt.Enabled
	and doorPrompt.ActionText == "Open door", "server back to idle")
Run(3.5)
check(Dev(washer, rest, Fixed) < 1e-9, "settled: every fixed part exactly at rest")
local highest = 0
for _, c in ipairs(clothInfo) do
	local q = drumCF:PointToObjectSpace(c.Part.Position)
	highest = math.max(highest, math.abs(math.atan2(q.X, -q.Y)))
end
check(highest <= 1.25 + 1e-3, ("drum stopped: no cloth left high up the wall (highest %.2f rad from the bottom)"):format(highest))
check(GuiText(gui, "Time") == "READY", "screen READY again")
check(not hum.IsPlaying, "hum stopped")
check(led.Color == Color3.fromHex("2d5a2a"), "LED back to rest")
local bulk = SIM.bulkMoves or 0
Run(1)
check((SIM.bulkMoves or 0) == bulk, "idle: no per-frame part moves")

print("== stop early")
Run(0.7)
startPrompt.Triggered:Fire(localPlayer)
Run(2)
startPrompt.Triggered:Fire(localPlayer)
Run(0.1)
check(washer:GetAttribute("Fun_CycleEnd") == 0 and startPrompt.ActionText == "Start", "stopped: CycleEnd 0")
Run(4)
check(water.Transparency == 1 and not hum.IsPlaying, "stopped: water gone, hum off")
check(Dev(washer, rest, Fixed) < 1e-9, "stopped: machine still again")
check(GuiText(gui, "Time") == "READY", "stopped: READY (no DONE)")

print("== a cycle ends while the player is in build mode")
Run(0.7)
startPrompt.Triggered:Fire(localPlayer)
Run(0.5)
hud:SetAttribute("BuildMode", true)
Run(0.1)
check(not startPrompt.Enabled and not doorPrompt.Enabled, "build mode hides both prompts mid-cycle")
Run(15)
check(washer:GetAttribute("Fun_CycleEnd") == 0, "cycle over")
check(not startPrompt.Enabled and not doorPrompt.Enabled, "prompts stay hidden in build mode after the cycle ends")
hud:SetAttribute("BuildMode", false)
Run(0.1)
check(startPrompt.Enabled and doorPrompt.Enabled and doorPrompt.ActionText == "Open door", "leaving build mode shows them again")

print("== moved mid-cycle")
Run(0.7)
startPrompt.Triggered:Fire(localPlayer)
Run(2)
local offset = CFrame.new(8, 0, -4) * CFrame.Angles(0, math.rad(90), 0)
local pivot = washer.PrimaryPart.CFrame
for _, d in ipairs(washer:GetDescendants()) do
	if d:IsA("BasePart") then d.CFrame = pivot * offset * pivot:ToObjectSpace(d.CFrame) end
end
Run(1)
check(washer:GetAttribute("Fun_CycleEnd") == 0, "server restarted the behaviour (idle)")
check(Dev(washer, rest) < 1e-6, ("every part back at rest relative to the moved hitbox (%.2e)"):format(Dev(washer, rest)))
check(washer:FindFirstChild("StartPrompt", true) ~= nil, "prompt rebuilt")
startPrompt = washer:FindFirstChild("StartPrompt", true)
doorPrompt = washer:FindFirstChild("DoorPrompt", true)

print("== broken mid-cycle, then mended")
Run(0.7)
startPrompt.Triggered:Fire(localPlayer)
Run(2)
washer:SetAttribute("Broken", true)
Run(1)
check(Dev(washer, rest) < 1e-6, "broken: every part at rest")
check(washer:FindFirstChild("Water").Transparency == 1, "broken: water hidden")
check(Gui() == nil, "broken: screen gui gone")
check(washer:FindFirstChild("StartPrompt", true) == nil, "broken: no prompts")
washer:SetAttribute("Broken", nil)
Run(1)
check(washer:FindFirstChild("StartPrompt", true) ~= nil and Gui() ~= nil, "mended: prompts + screen back")

print("== a dryer (x1, yaw 0)")
local dryer = BuildModel(MODELS.Dryer, 1, CFrame.new(46, 0, 34), placed, true)
local drest = RestOf(dryer)
Run(1)
local dStart = dryer:FindFirstChild("StartPrompt", true)
check(dStart ~= nil and dStart.ObjectText == "Dryer", "dryer Start prompt")
dStart.Triggered:Fire(other)
Run(3)
local dEnd = dryer:GetAttribute("Fun_CycleEnd")
check(type(dEnd) == "number" and dEnd > Now(), "dryer running")
local vent = workspace.CurrentCamera:FindFirstChild("LaundryVent")
check(vent ~= nil and vent:FindFirstChild("Puffs").Enabled and vent:FindFirstChild("Fluff").Enabled, "lint puffs + fluff from the vent")
if vent then
	local look = CFrame.new(46, 0, 34):VectorToObjectSpace(vent.CFrame.LookVector)
	check(look.X < -0.9, "vent blows out of the -X side: " .. tostring(look))
end
check(DevRot(dryer, drest, Starts("VentSlat")) > 0.4, ("vent louvres open (%.2f)"):format(DevRot(dryer, drest, Starts("VentSlat"))))
check(Dev(dryer, drest, Starts("DrumSpoke")) > 0.05, "dryer drum turning")
check(dryer:FindFirstChild("Water") == nil, "no water in the dryer")
local dgui
for _, g in ipairs(playerGui:GetChildren()) do if g.Name == "LaundryScreen" and g.Adornee == dryer:FindFirstChild("Screen") then dgui = g end end
check(dgui and GuiText(dgui, "Phase") == "DRY", "dryer screen phase DRY")
Run(dEnd - Now() + 0.3)
check(dgui and GuiText(dgui, "Time") == "DONE", "dryer DONE")
check(not vent:FindFirstChild("Puffs").Enabled, "lint stops")
Run(3.5)
check(Dev(dryer, drest, Fixed) < 1e-9 and DevRot(dryer, drest, Starts("VentSlat")) < 1e-4, "dryer settled, louvres shut")

print("== test hook: LaundryPress")
dryer:SetAttribute("LaundryPress", "Door")
Run(0.1)
check(dryer:GetAttribute("Fun_Door") == true and dryer:GetAttribute("LaundryPress") == nil, "LaundryPress Door opens the dryer door, attribute clears")
Run(0.7)
dryer:SetAttribute("LaundryPress", "Start")
Run(0.1)
check(dryer:GetAttribute("Fun_Door") == false and (dryer:GetAttribute("Fun_CycleEnd") or 0) > Now(), "LaundryPress Start shuts the door and runs a cycle")

print("== an older install: DoorGlass still Roblox Glass")
local oldData = table.clone(MODELS.WashingMachine)
oldData.parts = {}
for _, p in ipairs(MODELS.WashingMachine.parts) do
	local q = table.clone(p)
	if q.name == "DoorGlass" then q.material, q.transparency, q.reflectance = "Glass", 0.62, 0 end
	table.insert(oldData.parts, q)
end
local oldWasher = BuildModel(oldData, WM_SCALE, CFrame.new(30, 0, 50), placed, true)
Run(1)
local oldGlass = oldWasher:FindFirstChild("DoorGlass")
check(oldGlass.Material == Enum.Material.SmoothPlastic and oldGlass.Reflectance >= 0.15, "client draws an old Glass porthole as SmoothPlastic")
oldWasher:SetAttribute("Broken", true)
Run(1)
check(oldGlass.Material == Enum.Material.Glass and oldGlass.Reflectance == 0, "cleanup restores its Glass material + reflectance")
oldWasher:SetAttribute("Broken", nil)
Run(1)
check(oldGlass.Material == Enum.Material.SmoothPlastic, "mended: SmoothPlastic again")
oldWasher:Destroy()
Run(0.5)

print("== sell the washer")
washer:Destroy()
Run(0.5)
check(Gui() ~= nil and Gui().Adornee == dryer:FindFirstChild("Screen"), "only the dryer's screen remains")

print(("\n== RESULT: %d failed checks, %d runtime errors, %d warnings"):format(fails, SIM.errors, #SIM.warns))
local unknown = {}
for k in pairs(SIM.unknownReads) do table.insert(unknown, k) end
table.sort(unknown)
print("unknown property reads: " .. table.concat(unknown, ", "))
