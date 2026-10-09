-- Offline scenario test: the real FunBuildService + FunBuildClient + the DJBooth / DanceFloor modules in a mock world.
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
	if class == "Animator" then end
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
local UserInputService = Service("UserInputService")
local ContextActionService = Service("ContextActionService")
Service("ContentProvider")
Service("SoundService")
Service("TweenService")
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
RunService.IsStudio = function() return true end

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
			if now and i.ClassName == "Sound" and i.SoundId ~= "" and not i.IsLoaded then
				task.delay(0.3, function()
					if rawget(i, "__destroyed") then return end
					i.TimeLength = 95
					i.IsLoaded = true
					i.Loaded:Fire(i.SoundId)
				end)
			end
		end
	end
end

--..Players..--
local function Character(name, pos)
	local char = InstanceLib.new("Model")
	char.Name = name
	local humanoid = InstanceLib.new("Humanoid", char)
	humanoid.MoveDirection = Vector3.zero
	humanoid.FloorMaterial = Enum.Material.Neon
	humanoid.RigType = Enum.HumanoidRigType.R15
	InstanceLib.new("Animator", humanoid)
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
local char, humanoid, root = Character("LocalGuy", Vector3.new(60, 3, 50))
char.Parent = workspace
localPlayer.Character = char
local other = InstanceLib.new("Player")
other.Name = "Visitor"
other.UserId = 2
other.Parent = Players
local otherChar, _, otherRoot = Character("Visitor", Vector3.new(0, 3, 0))
otherChar.Parent = workspace
other.Character = otherChar
Players.LocalPlayer = localPlayer
Players.PlayerRemoving = M.Signal()
Players.PlayerAdded = M.Signal()
Players.GetPlayers = function() return {localPlayer, other} end

UserInputService.KeyboardEnabled = true
local CAS = {}
ContextActionService.BindAction = function(_, name, fn, _, ...) CAS[name] = {fn = fn, keys = {...}} end
ContextActionService.UnbindAction = function(_, name) CAS[name] = nil end

local camera = InstanceLib.new("Camera", workspace)
camera.Name = "Camera"
camera.CFrame = CFrame.new(90, 20, 50)
camera.ViewportSize = M.Vector2.new(1280, 720)
workspace.CurrentCamera = camera

--..Modules..--
local cache = {}
local makeEnv
local function mrequire(ms)
	if cache[ms] ~= nil then return cache[ms] end
	local tbl = rawget(ms, "__table")
	if tbl then cache[ms] = tbl return tbl end
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
		NumberSequence = M.NumberSequence, NumberSequenceKeypoint = M.NumberSequenceKeypoint,
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
local function Module(name, parent, source, tbl)
	local ms = InstanceLib.new("ModuleScript")
	ms.Name = name
	if source then rawset(ms, "__source", source) end
	if tbl then rawset(ms, "__table", tbl) end
	ms.Parent = parent
	return ms
end
local Modules = InstanceLib.new("Folder", ReplicatedStorage)
Modules.Name = "Modules"
Module("FunBuildKit", Modules, SRC.Kit)
local funAssetsMs = Module("FunAssets", Modules, SRC.FunAssets)
local duckLog = {}
Module("MusicManager", Modules, nil, {
	SetDuck = function(tag, f, t) table.insert(duckLog, "set:" .. tag .. ":" .. f) end,
	ClearDuck = function(tag, t) table.insert(duckLog, "clear:" .. tag) end,
})
local pressed = 0
Module("ButtonFX", Modules, nil, {
	Prepare = function(gui) end,
	Press = function(b) pressed += 1 end,
})
local serverFolder = InstanceLib.new("Folder", ServerStorage)
serverFolder.Name = "FunBehaviours"
Module("DJBooth", serverFolder, SRC.DJServer)
local clientFolder = InstanceLib.new("Folder", ReplicatedStorage)
clientFolder.Name = "FunBehavioursClient"
Module("DJBooth", clientFolder, SRC.DJClient)
local floorModule = Module("DanceFloor", clientFolder, SRC.Floor)

--..Frames..--
local function Frame(dt)
	SIM.now += dt
	M.RunDue()
	RunService.Stepped:Fire(SIM.now, dt)
	RunService.RenderStepped:Fire(dt)
	RunService.Heartbeat:Fire(dt)
	for _, s in ipairs(sounds) do
		if not rawget(s, "__destroyed") and s.IsPlaying and s.TimeLength > 0 then
			s.TimePosition = (s.TimePosition + dt) % s.TimeLength
			s.PlaybackLoudness = 100 + 300 * math.abs(math.sin(SIM.now * 7))
		elseif not rawget(s, "__destroyed") then
			s.PlaybackLoudness = 0
		end
	end
end
local function Run(seconds) for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do Frame(1 / 60) end end

--..Scripts..--
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

--..Builds..--
local map = InstanceLib.new("Folder", workspace)
map.Name = "Map"
local placed = InstanceLib.new("Folder", map)
placed.Name = "Placed"
local function V(t) return Vector3.new(t[1], t[2], t[3]) end
local function BuildModel(key, dump, scale, placeCF)
	local model = InstanceLib.new("Model")
	model.Name = key
	local lo, hi
	for _, p in ipairs(dump.parts) do
		local a, b = V(p.pos) - V(p.size) * 0.5, V(p.pos) + V(p.size) * 0.5
		lo = lo and Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) or a
		hi = hi and Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) or b
	end
	local centre = (lo + hi) * 0.5
	local hitbox = InstanceLib.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (hi - lo) * scale
	hitbox.Transparency = 1
	hitbox.CFrame = placeCF * CFrame.new(centre * scale)
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	for _, p in ipairs(dump.parts) do
		local part = InstanceLib.new("MeshPart")
		part.Name = p.name
		part.Size = V(p.size) * scale
		part.CFrame = placeCF * CFrame.new(V(p.pos) * scale)
		part.Material = Enum.Material[p.mat]
		part.Color = Color3.fromHex(p.color)
		part.Transparency = p.t
		part.Parent = model
	end
	for k, v in pairs(dump.attrs) do model:SetAttribute(k, type(v) == "table" and V(v) or v) end
	model:SetAttribute("BuildKey", key)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("AuthoredCentre", centre)
	model:SetAttribute("Owner", 1)
	model.Parent = placed
	CollectionService:AddTag(model, "PlacedBuild")
	return model
end

print("== place the booth (x1.3, yaw 90) and a dance floor (x1.5) in front of it")
local boothCF = CFrame.new(100, 0, 50) * CFrame.Angles(0, math.rad(90), 0)
local booth = BuildModel("DJBooth", DUMP.DJBooth, 1.3, boothCF)
local floorCF = CFrame.new(84, 0, 50)
local floor = BuildModel("DanceFloor", DUMP.DanceFloor, 1.5, floorCF)
Run(1)

local runtime = workspace:FindFirstChild("FunBuildRuntime")
check(runtime ~= nil, "runtime folder exists")
local playPrompt = runtime and runtime:FindFirstChild("DJPlayPrompt", true)
check(playPrompt ~= nil and playPrompt.ActionText == "Play music", "play prompt present, says Play music")
check(runtime:FindFirstChild("DJNextPrompt", true) == nil, "next prompt parked while stopped")
local anchor = playPrompt and playPrompt.Parent
if anchor then
	local lp = boothCF:PointToObjectSpace(anchor.Position) / 1.3
	check(math.abs(lp.X) < 1e-6 and math.abs(lp.Y - 2.95) < 1e-6 and math.abs(lp.Z - 0.45) < 1e-6, "prompt anchor at authored (0, 2.95, 0.45): " .. tostring(lp))
end
check(booth:GetAttribute("Fun_Playing") == false and booth:GetAttribute("Fun_Track") == 1, "state Playing=false Track=1")
local fx = workspace:FindFirstChild("DJBoothFX")
check(fx ~= nil, "client fx folder exists")
local discs = {}
for _, d in ipairs(fx and fx:GetChildren() or {}) do if d.Name:match("^DJRecord") then table.insert(discs, d) end end
check(#discs == 2 and discs[1].Transparency == 1, "two runtime record discs, hidden while idle")
local tile = floor:FindFirstChild("Tile_r0_c0")
check(tile.Transparency == 0.45, "idle floor tiles are dim (State_Dim 0.45): " .. tostring(tile.Transparency))

print("== the visitor presses Play")
playPrompt.Triggered:Fire(other)
Run(1)
check(booth:GetAttribute("Fun_Playing") == true, "Fun_Playing = true")
check(type(booth:GetAttribute("Fun_StartedAt")) == "number", "Fun_StartedAt set")
check(playPrompt.ActionText == "Stop music", "prompt flips to Stop music")
local nextPrompt = runtime:FindFirstChild("DJNextPrompt", true)
check(nextPrompt ~= nil and nextPrompt.KeyboardKeyCode == Enum.KeyCode.R, "Next track prompt (R) shows while playing")
local hitbox = booth.PrimaryPart
local music = hitbox:FindFirstChild("DJBoothMusic")
check(music ~= nil and music.IsPlaying and music.Looped, "looped music Sound in the booth, playing")
check(music and music.RollOffMaxDistance == 120 and music.Volume == 0.6, "rolloff 120 / volume 0.6")
local expected = (workspace:GetServerTimeNow() - booth:GetAttribute("Fun_StartedAt")) % 95
check(music and math.abs(music.TimePosition - expected) < 0.6, ("in sync: pos %.2f vs %.2f"):format(music and music.TimePosition or -1, expected))
check(discs[1].Transparency == 0 and discs[1].Material == Enum.Material.Neon, "record discs shown (Neon)")
local beams, lights = 0, 0
for _, d in ipairs(fx:GetDescendants()) do
	if d.ClassName == "Beam" and d.Enabled then beams += 1 end
	if d.ClassName == "SpotLight" and d.Enabled then lights += 1 end
end
check(beams == 2 and lights == 2, "2 beams + 2 spotlights on (lights <= 2)")
local letters = booth:FindFirstChild("Letters")
local seenT = {}
for _ = 1, 30 do Frame(1 / 60) seenT[math.floor(letters.Transparency * 10)] = true end
local nT = 0 for _ in pairs(seenT) do nT += 1 end
check(nT >= 2 and letters.Transparency <= 0.5, "Letters pulse (transparency varies)")
check(tile.Transparency == 0, "floor tiles bright (State_On) while a booth within 60 plays")
local c1 = tile.Color
Run(0.3)
check(tile.Color ~= c1, "floor tile colour animates")
check(#duckLog > 0 and duckLog[#duckLog]:match("^set:FunDJBooth"), "lobby music ducked near the booth: " .. tostring(duckLog[#duckLog]))
local dj = mrequire(clientFolder:FindFirstChild("DJBooth"))
local live = dj.Live[booth]
check(live ~= nil and live.Pulse >= 0 and live.Pulse <= 1, "DJBooth.Live pulse shared")

print("== spot beam geometry at t = 0 (floor aim, no yaw)")
do
	local anchors = {}
	for _, d in ipairs(fx:GetChildren()) do if d.Name == "DJSpotBeam" then table.insert(anchors, d) end end
	check(#anchors == 2, "two beam anchors")
	for _, a in ipairs(anchors) do
		local look = boothCF:VectorToObjectSpace(a.CFrame.LookVector)
		check(look.Y < -0.1 and look.Z < -0.5, "beam points down and to the front (-Z authored): " .. tostring(look))
	end
end

print("== drift is corrected")
music.TimePosition = (music.TimePosition + 5) % 95
Run(0.7)
expected = (workspace:GetServerTimeNow() - booth:GetAttribute("Fun_StartedAt")) % 95
check(math.abs(music.TimePosition - expected) < 0.6, ("re-seeked: %.2f vs %.2f"):format(music.TimePosition, expected))

print("== Next track with a second track in FunAssets")
local assets = mrequire(funAssetsMs)
table.insert(assets.Music, {Name = "Second", Id = "rbxassetid://1234567"})
nextPrompt.Triggered:Fire(localPlayer)
Run(1)
check(booth:GetAttribute("Fun_Track") == 2, "Track -> 2")
local music2 = hitbox:FindFirstChild("DJBoothMusic")
check(music2 ~= nil and music2 ~= music and music2.SoundId == "rbxassetid://1234567" and music2.IsPlaying, "new track sound playing")
check(rawget(music, "__destroyed") == true, "old track sound destroyed")
check(nextPrompt.ObjectText:match("2/2") ~= nil, "next prompt names the track: " .. nextPrompt.ObjectText)
Run(0.6) -- past the next-track cooldown
nextPrompt.Triggered:Fire(localPlayer)
Run(0.2)
check(booth:GetAttribute("Fun_Track") == 1, "Track wraps -> 1")
table.remove(assets.Music, 2)

print("== dancing")
local floorTop = floorCF * Vector3.new(0.87 * 1.5, 0.34 * 1.5 + 3, 0.87 * 1.5)
root.CFrame = CFrame.new(floorTop)
Run(0.3)
local dgui = playerGui:FindFirstChild("FunDanceGui")
check(dgui ~= nil and dgui.Enabled, "Dance GUI shows on the floor")
local button = dgui and dgui:FindFirstChild("Dance", true)
local label = button and button:FindFirstChild("Label")
check(label and label.Text == "DANCE", "button says DANCE")
check(CAS.FunDanceFloorDance ~= nil, "G bound")
check(dgui.IgnoreGuiInset == true and dgui.ResetOnSpawn == false, "gui IgnoreGuiInset / ResetOnSpawn false")
button.Activated:Fire()
Run(0.1)
local t1 = SIM.lastTrack
check(t1 and t1.IsPlaying and t1.Looped and t1.AnimationId == "rbxassetid://507771019" and t1.Priority == Enum.AnimationPriority.Action, "dance 1 looping at Action priority")
check(label.Text == "STOP" and pressed >= 1, "button says STOP (+ press pop)")
humanoid.MoveDirection = Vector3.new(1, 0, 0)
Run(0.1)
check(not t1.IsPlaying and label.Text == "DANCE", "moving stops the dance")
humanoid.MoveDirection = Vector3.zero
CAS.FunDanceFloorDance.fn("FunDanceFloorDance", Enum.UserInputState.Begin)
Run(0.1)
local t2 = SIM.lastTrack
check(t2 ~= t1 and t2.IsPlaying and t2.AnimationId == "rbxassetid://507776043", "G starts dance 2 (cycles)")
humanoid.StateChanged:Fire(Enum.HumanoidStateType.Running, Enum.HumanoidStateType.Jumping)
Run(0.1)
check(not t2.IsPlaying, "jumping stops the dance")
button.Activated:Fire()
Run(0.1)
local t3 = SIM.lastTrack
check(t3.AnimationId == "rbxassetid://507777268" and t3.IsPlaying, "dance 3")
button.Activated:Fire()
Run(0.1)
check(not t3.IsPlaying, "STOP stops it")
button.Activated:Fire()
Run(0.1)
local t4 = SIM.lastTrack
check(t4.AnimationId == "rbxassetid://507771019", "cycle wraps to dance 1")
-- footstep: the tile under the character glows (lerped to white)
root.CFrame = CFrame.new(60, 3, 50) -- teleport off the floor
Run(0.3)
check(not t4.IsPlaying, "leaving the floor stops the dance")
check(not dgui.Enabled and CAS.FunDanceFloorDance == nil, "GUI hidden + G unbound off the floor")

print("== muted music pauses the local track, visuals keep going")
localPlayer:SetAttribute("MusicMuted", true)
Run(0.2)
local m = hitbox:FindFirstChild("DJBoothMusic")
check(m and not m.IsPlaying, "muted -> paused")
localPlayer:SetAttribute("MusicMuted", nil)
Run(0.2)
check(m.IsPlaying, "unmuted -> playing")

print("== camera far away: track pauses, beams come down")
camera.CFrame = CFrame.new(900, 20, 50)
Run(1)
check(not m.IsPlaying, "far camera -> paused")
local anyBeam = false
for _, d in ipairs(fx:GetDescendants()) do if d.ClassName == "Beam" and d.Enabled then anyBeam = true end end
check(not anyBeam, "beams hidden while the Step sleeps")
camera.CFrame = CFrame.new(90, 20, 50)
Run(1)
check(m.IsPlaying, "camera back -> playing")
expected = (workspace:GetServerTimeNow() - booth:GetAttribute("Fun_StartedAt")) % 95
check(math.abs(m.TimePosition - expected) < 0.6, "resumed in sync")

print("== stop")
Run(1)
playPrompt.Triggered:Fire(localPlayer)
Run(0.6)
check(booth:GetAttribute("Fun_Playing") == false, "Playing false")
check(not m.IsPlaying, "music paused")
check(letters.Transparency == 0 and letters.Color == Color3.fromHex("ff4fa3"), "Letters restored")
local led = booth:FindFirstChild("LedStrip")
check(led.Color == Color3.fromHex("4dd2ff"), "LedStrip colour restored")
check(discs[1].Transparency == 1, "discs hidden")
check(runtime:FindFirstChild("DJNextPrompt", true) == nil, "next prompt parked")
check(duckLog[#duckLog] == "clear:FunDJBooth", "duck cleared")
Run(0.3)
check(tile.Transparency == 0.45, "floor back to dim")

print("== footsteps (idle): a visitor standing on Tile_r0_c0 lights only that tile")
otherRoot.CFrame = CFrame.new(floorCF * Vector3.new(2.61 * 1.5, 0.34 * 1.5 + 3, 2.61 * 1.5))
Run(0.3)
local far = floor:FindFirstChild("Tile_r3_c3")
check(tile.Transparency == 0 and far.Transparency == 0.45, "r0_c0 on, r3_c3 still dim")
otherRoot.CFrame = CFrame.new(floorCF * Vector3.new(-2.61 * 1.5, 0.34 * 1.5 + 3, -2.61 * 1.5))
Run(0.3)
check(tile.Transparency == 0.45 and far.Transparency == 0, "moves with the visitor to r3_c3")
otherRoot.CFrame = CFrame.new(0, 3, 0)
Run(0.3)

print("== broken while playing: faded parts stay faded")
Run(1)
playPrompt.Triggered:Fire(localPlayer)
Run(0.5)
for _, d in ipairs(booth:GetDescendants()) do
	if d:IsA("BasePart") and d.Name ~= "Hitbox" then
		rawset(d, "__orig", d.Transparency)
		if d.Transparency < 1 then d.Transparency = math.max(d.Transparency, 0.65) end
	end
end
Frame(1 / 60) -- a Step may run between the fade and the Broken attribute
booth:SetAttribute("Broken", true)
Run(0.6)
check(letters.Transparency == 0.65, "Letters keep the broken fade: " .. letters.Transparency)
check(workspace:FindFirstChild("DJBoothFX") == nil, "fx gone while broken")
check(booth:GetAttribute("Fun_Playing") == nil, "server state cleared while broken")
check(hitbox:FindFirstChild("DJBoothMusic") == nil, "music gone while broken")
for _, d in ipairs(booth:GetDescendants()) do
	if d:IsA("BasePart") and d.Name ~= "Hitbox" then d.Transparency = rawget(d, "__orig") end
end
booth:SetAttribute("Broken", nil)
Run(0.6)
check(booth:GetAttribute("Fun_Playing") == false and workspace:FindFirstChild("DJBoothFX") ~= nil, "mended: behaviour back, stopped")
playPrompt = runtime:FindFirstChild("DJPlayPrompt", true)
check(playPrompt ~= nil, "new play prompt after mend")

print("== moved: everything rebuilds at the new spot")
local delta = CFrame.new(0, 0, 40)
for _, d in ipairs(booth:GetDescendants()) do
	if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
end
Run(0.6)
playPrompt = runtime:FindFirstChild("DJPlayPrompt", true)
playPrompt.Triggered:Fire(localPlayer)
Run(0.5)
fx = workspace:FindFirstChild("DJBoothFX")
local disc = fx and fx:FindFirstChild("DJRecordA")
local expectDisc = (delta * boothCF) * (Vector3.new(1.30, 3.10, 0.44) * 1.3)
check(disc ~= nil and (disc.Position - expectDisc).Magnitude < 1e-6, "disc A at the moved deck: " .. tostring(disc and disc.Position))
local dist = (hitbox.Position - floor.PrimaryPart.Position).Magnitude
check(dist < 60 and tile.Transparency == 0, ("booth still %.1f studs away -> floor stays lit"):format(dist))

print("== booth moved out of range (> 60 studs): the floor dims even though it plays")
delta = CFrame.new(0, 0, 80)
for _, d in ipairs(booth:GetDescendants()) do
	if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
end
Run(0.6)
runtime:FindFirstChild("DJPlayPrompt", true).Triggered:Fire(localPlayer)
Run(1.2)
dist = (hitbox.Position - floor.PrimaryPart.Position).Magnitude
check(booth:GetAttribute("Fun_Playing") == true and dist > 60 and tile.Transparency == 0.45, ("booth %.1f studs away, playing -> floor dim"):format(dist))

print("== sold")
floor:Destroy()
Run(0.3)
booth:Destroy()
Run(0.3)
check(not dgui.Enabled, "dance GUI hidden after the floor is sold")
check(#duckLog > 0 and duckLog[#duckLog] == "clear:FunDJBooth", "duck cleared after the booth is sold")

print(("\n== RESULT: %d failed checks, %d runtime errors, %d warnings"):format(fails, SIM.errors, #SIM.warns))
local unknown = {}
for k in pairs(SIM.unknownReads) do table.insert(unknown, k) end
table.sort(unknown)
print("unknown/nil property reads: " .. table.concat(unknown, ", "))
