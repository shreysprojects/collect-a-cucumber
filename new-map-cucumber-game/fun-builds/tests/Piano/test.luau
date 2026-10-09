-- Offline scenario test (fun-builds HomePiano): the real FunBuildService + FunBuildClient + the Piano modules in the
-- shared mock world (tests/DJBooth/mock.luau). Assembled by build_test.py into run_test.luau.
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

--..What the piano needs on top of the shared mock..--
local UD2MT = {}
UD2MT.__add = function(a, b)
	return M.UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UD2MT.__eq = function(a, b)
	return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset
end
M.UDim2.new = function(xs, xo, ys, yo)
	return setmetatable({X = {Scale = xs or 0, Offset = xo or 0}, Y = {Scale = ys or 0, Offset = yo or 0}, __kind = "UDim2"}, UD2MT)
end
local TweenInfo = {new = function(...) return {...} end}
local EXTRA_EVENTS = {TextButton = {"InputBegan", "InputEnded", "MouseEnter", "MouseLeave"}}

--..DataModel..--
local sounds = {}
local InstanceLib = {new = function(class, parent)
	local i = M.NewInstance(class)
	for _, e in ipairs(EXTRA_EVENTS[class] or {}) do rawget(i, "__events")[e] = M.Signal() end
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
local UserInputService = Service("UserInputService")
local ContextActionService = Service("ContextActionService")
Service("ContentProvider")
local SoundService = Service("SoundService")
local TweenService = Service("TweenService")
Service("ServerScriptService")
game.GetService = function(_, name) return services[name] or error("no service " .. name) end
game.Workspace = workspace

--..RemoteEvent methods (every server -> client event is logged)..--
local localPlayer
local fired = {}
M.Methods.FireAllClients = function(self, model, action, payload)
	table.insert(fired, {model = model, action = action, payload = payload})
	self.OnClientEvent:Fire(model, action, payload)
end
M.Methods.FireClient = function(self, _, ...) self.OnClientEvent:Fire(...) end
M.Methods.FireServer = function(self, ...) self.OnServerEvent:Fire(localPlayer, ...) end

--..RunService..--
RunService.RenderStepped = M.Signal()
RunService.Heartbeat = M.Signal()
RunService.Stepped = M.Signal()
RunService.IsServer = function() return true end
RunService.IsClient = function() return true end
RunService.IsStudio = function() return true end

--..TweenService (applies the goal at once)..--
local tweens = 0
TweenService.Create = function(_, inst, _, goals)
	local tw = {Cancelled = false}
	function tw:Play()
		tweens += 1
		if not self.Cancelled then for k, v in pairs(goals) do inst[k] = v end end
	end
	function tw:Cancel() self.Cancelled = true end
	return tw
end

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

--..Players (R15 joints as Motor6Ds)..--
local JOINTS = {"Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftWrist", "RightWrist"}
local function Character(name, pos)
	local char = InstanceLib.new("Model")
	char.Name = name
	local humanoid = InstanceLib.new("Humanoid", char)
	humanoid.MoveDirection = Vector3.zero
	humanoid.RigType = Enum.HumanoidRigType.R15
	InstanceLib.new("Animator", humanoid)
	local root = InstanceLib.new("Part", char)
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(pos)
	local torso = InstanceLib.new("Part", char)
	torso.Name = "UpperTorso"
	for _, jn in ipairs(JOINTS) do
		local j = InstanceLib.new("Motor6D", torso)
		j.Name = jn
		j.Transform = CFrame.identity
	end
	return char, humanoid, root
end
localPlayer = InstanceLib.new("Player")
localPlayer.Name = "LocalGuy"
localPlayer.UserId = 1
localPlayer.Parent = Players
local playerGui = InstanceLib.new("PlayerGui", localPlayer)
playerGui.Name = "PlayerGui"
local char, humanoid, root = Character("LocalGuy", Vector3.new(0, 3, 0))
char.Parent = workspace
localPlayer.Character = char
local other = InstanceLib.new("Player")
other.Name = "Visitor"
other.UserId = 2
other.Parent = Players
local otherChar, otherHumanoid, otherRoot = Character("Visitor", Vector3.new(0, 3, 0))
otherChar.Parent = workspace
other.Character = otherChar
Players.LocalPlayer = localPlayer
Players.PlayerRemoving = M.Signal()
Players.PlayerAdded = M.Signal()
Players.GetPlayers = function() return {localPlayer, other} end
Players.GetPlayerByUserId = function(_, id)
	for _, p in ipairs({localPlayer, other}) do if p.UserId == id then return p end end
	return nil
end
Players.GetPlayerFromCharacter = function(_, c)
	for _, p in ipairs({localPlayer, other}) do if p.Character == c then return p end end
	return nil
end

--..Input..--
local mouseDown = false
UserInputService.KeyboardEnabled = true
UserInputService.TouchEnabled = false
UserInputService.InputBegan = M.Signal()
UserInputService.InputEnded = M.Signal()
UserInputService.GetFocusedTextBox = function() return nil end
UserInputService.IsMouseButtonPressed = function() return mouseDown end
local CAS = {}
ContextActionService.BindAction = function(_, name, fn, _, ...) CAS[name] = {fn = fn, keys = {...}} end
ContextActionService.BindActionAtPriority = function(_, name, fn, _, _, ...) CAS[name] = {fn = fn, keys = {...}} end
ContextActionService.UnbindAction = function(_, name) CAS[name] = nil end

local camera = InstanceLib.new("Camera", workspace)
camera.Name = "Camera"
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
		ColorSequence = M.ColorSequence, ColorSequenceKeypoint = M.ColorSequenceKeypoint, Enum = Enum, TweenInfo = TweenInfo,
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
Module("FunAssets", Modules, SRC.FunAssets)
local pressed = 0
Module("ButtonFX", Modules, nil, {Prepare = function() end, Press = function() pressed += 1 end})
local serverFolder = InstanceLib.new("Folder", ServerStorage)
serverFolder.Name = "FunBehaviours"
Module("Piano", serverFolder, SRC.PianoServer)
local clientFolder = InstanceLib.new("Folder", ReplicatedStorage)
clientFolder.Name = "FunBehavioursClient"
Module("Piano", clientFolder, SRC.PianoClient)

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

--..The piano (x1.2, yaw 90)..--
local map = InstanceLib.new("Folder", workspace)
map.Name = "Map"
local placed = InstanceLib.new("Folder", map)
placed.Name = "Placed"
local function V(t) return Vector3.new(t[1], t[2], t[3]) end
local SCALE = 1.2
local pianoCF = CFrame.new(40, 0, 20) * CFrame.Angles(0, math.rad(90), 0)
local function BuildModel(key, dump, scale, placeCF)
	local model = InstanceLib.new("Model")
	model.Name = key
	local lo, hi = V(dump.min), V(dump.max)
	local centre = (lo + hi) * 0.5
	local hitbox = InstanceLib.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (hi - lo) * scale
	hitbox.Transparency = 1
	hitbox.CFrame = placeCF * CFrame.new(centre * scale)
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	for _, p in ipairs(dump.parts) do
		local part = InstanceLib.new("Part")
		part.Name = p.name
		part.Size = V(p.size) * scale
		part.CFrame = placeCF * CFrame.new(V(p.pos) * scale)
		part.Parent = model
	end
	for k, v in pairs(dump.attrs) do model:SetAttribute(k, type(v) == "table" and V(v) or v) end
	model:SetAttribute("BuildKey", key)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("AuthoredCentre", centre)
	model:SetAttribute("Owner", 2)
	model.Parent = placed
	CollectionService:AddTag(model, "PlacedBuild")
	return model
end
local function At(p) return pianoCF * (p * SCALE) end -- authored point -> world

root.CFrame = CFrame.new(At(Vector3.new(0, 3, -7)))
otherRoot.CFrame = CFrame.new(At(Vector3.new(3, 3, -7)))
camera.CFrame = CFrame.new(At(Vector3.new(0, 12, -22)))

print("== place the piano")
local piano = BuildModel("Piano", DUMP.Piano, SCALE, pianoCF)
Run(0.5)
local runtime = workspace:FindFirstChild("FunBuildRuntime")
local seat = runtime and runtime:FindFirstChild("PianoBench", true)
check(seat ~= nil and seat.ClassName == "Seat", "bench Seat in the runtime folder")
local top = seat.CFrame * Vector3.new(0, seat.Size.Y / 2, 0)
check((top - At(Vector3.new(0, 2.2, -4.5))).Magnitude < 1e-6, "seat top on Pivot_Bench: " .. tostring(top))
local look = pianoCF:VectorToObjectSpace(seat.CFrame.LookVector)
check(look.Z > 0.999, "seat faces authored +Z (the keyboard): " .. tostring(look))
local sitPrompt = seat:FindFirstChild("FunPromptAt") and seat.FunPromptAt:FindFirstChild("SitPrompt") or seat:FindFirstChild("SitPrompt")
check(sitPrompt ~= nil and sitPrompt.ActionText == "Play piano" and sitPrompt.ObjectText == "Piano", "prompt Play piano / Piano")
check(piano:GetAttribute("Fun_Player") == 0, "Fun_Player = 0")
local fx = workspace:FindFirstChild("FunBuildLocal") and workspace.FunBuildLocal:FindFirstChild("PianoFX")
check(fx ~= nil and (fx.Position - At(Vector3.new(-0.7, 4.2, 1.9))).Magnitude < 1e-6, "float anchor on Pivot_Notes")
local soundAt = fx and fx:FindFirstChild("PianoSound")
check(soundAt ~= nil and (soundAt.WorldPosition - At(Vector3.new(-0.3, 3.85, 1.6))).Magnitude < 1e-6, "sound attachment on Pivot_Sound")
local floats = 0
for _, d in ipairs(fx:GetChildren()) do if d.ClassName == "BillboardGui" then floats += 1 end end
check(floats == 10, "10 float billboards pooled: " .. floats)
check(playerGui:FindFirstChild("FunPianoGui") == nil, "no GUI before sitting")

print("== the local player sits down")
-- (the mock's Seat:Sit method shadows Humanoid.Sit, so ctx:Seat's prompt handler bails out here: seat directly)
seat:Sit(humanoid)
humanoid.SeatPart = seat
humanoid.Sit = true
Run(0.2)
check(seat.Occupant == humanoid and piano:GetAttribute("Fun_Player") == 1, "seated, Fun_Player = 1")
check(sitPrompt.Enabled == false, "sit prompt hidden while taken")
local gui = playerGui:FindFirstChild("FunPianoGui")
check(gui ~= nil and gui.IgnoreGuiInset == true and gui.ResetOnSpawn == false, "piano GUI open (IgnoreGuiInset, no reset)")
check(CAS.FunPianoKeys ~= nil and #CAS.FunPianoKeys.keys == 20, "20 keys bound (18 notes + Z/X)")
local rangeLabel = gui:FindFirstChild("Range", true)
check(rangeLabel and rangeLabel.Text == "C4  -  B5", "range label C4 - B5: " .. tostring(rangeLabel and rangeLabel.Text))
local whites, blacks, hits = 0, 0, 0
for _, d in ipairs(gui:GetDescendants()) do
	if d.Name:match("^White%d+$") then whites += 1 end
	if d.Name:match("^Black%d+$") then blacks += 1 end
	if d.Name:match("^Hit%d+$") then hits += 1 end
end
check(whites == 14 and blacks == 10 and hits == 38, ("14 white / 10 black keys, 38 hit areas (%d/%d/%d)"):format(whites, blacks, hits))
local holder = gui:FindFirstChild("Holder")
local uiScale = holder and holder:FindFirstChildOfClass("UIScale")
check(uiScale and uiScale.Scale > 0.6 and uiScale.Scale <= 1.3, "UIScale from the viewport: " .. tostring(uiScale and uiScale.Scale))

local keyFn = CAS.FunPianoKeys.fn
local function Key(code, state) return keyFn("FunPianoKeys", state, {KeyCode = code, UserInputType = Enum.UserInputType.Keyboard}) end
local function LocalSounds()
	local list = {}
	for _, s in ipairs(SoundService:GetChildren()) do if s.Name == "PianoNoteLocal" then table.insert(list, s) end end
	return list
end
local WHITE_LIT, WHITE = Color3.fromRGB(140, 240, 60), Color3.fromRGB(250, 248, 242)

print("== A plays C4 at once, lights up, and goes to the server")
local before = #fired
check(Key(Enum.KeyCode.A, Enum.UserInputState.Begin) == Enum.ContextActionResult.Sink, "key sunk")
local ls = LocalSounds()
check(#ls == 10, "local 2D pool of 10 in SoundService: " .. #ls)
check(ls[1].IsPlaying and math.abs(ls[1].PlaybackSpeed - 1) < 1e-4, "C4 (root) plays at speed 1: " .. tostring(ls[1].PlaybackSpeed))
local f = fired[#fired]
check(#fired == before + 1 and f.action == "Note" and f.payload[1] == 60 and f.payload[2] == 1, "server fired Note {60, 1}")
local white0 = gui:FindFirstChild("White0", true)
check(white0.BackgroundColor3 == WHITE_LIT, "C4 key lit")
Key(Enum.KeyCode.A, Enum.UserInputState.End)
check(white0.BackgroundColor3 == WHITE, "C4 key released")
local remotePlaying = 0
for _, s in ipairs(sounds) do if s.Name == "PianoNote" and s.IsPlaying then remotePlaying += 1 end end
check(remotePlaying == 0, "own note not replayed by the echo")

print("== a chord (S + D + G in one frame) is ONE send")
Run(0.02)
before = #fired
Key(Enum.KeyCode.S, Enum.UserInputState.Begin)
Key(Enum.KeyCode.D, Enum.UserInputState.Begin)
Key(Enum.KeyCode.G, Enum.UserInputState.Begin)
check(#fired == before, "held back inside SEND_INTERVAL")
Run(0.15)
f = fired[#fired]
check(#fired == before + 1 and type(f.payload[1]) == "table" and f.payload[1][1] == 62 and f.payload[1][2] == 64 and f.payload[1][3] == 67,
	"one Note {{62, 64, 67}, 1}")
local playing = 0
for _, s in ipairs(ls) do if s.IsPlaying then playing += 1 end end
check(playing == 4, "4 local voices sounding: " .. playing)
Key(Enum.KeyCode.S, Enum.UserInputState.End)
Key(Enum.KeyCode.D, Enum.UserInputState.End)
Key(Enum.KeyCode.G, Enum.UserInputState.End)

print("== floats + pianist pose")
local lit = 0
for _, d in ipairs(fx:GetChildren()) do if d.ClassName == "BillboardGui" and d.Enabled then lit += 1 end end
check(lit >= 1, "note floats up: " .. lit)
local shoulder = char:FindFirstChild("LeftShoulder", true)
local neck = char:FindFirstChild("Neck", true)
check(shoulder.Transform ~= CFrame.identity and neck.Transform ~= CFrame.identity, "pianist leans in (joint Transforms written)")
local arm = -shoulder.Transform.UpVector -- the upper arm hangs along the joint's -Y
check(arm.Z < -0.5 and arm.Y < 0, "upper arm swung forward (-Z) and still down: " .. tostring(arm))
Run(2.5)
lit = 0
for _, d in ipairs(fx:GetChildren()) do if d.ClassName == "BillboardGui" and d.Enabled then lit += 1 end end
check(lit == 0, "floats fade out")

print("== octave shift")
Key(Enum.KeyCode.Z, Enum.UserInputState.Begin)
check(rangeLabel.Text == "C3  -  B4", "Z -> C3 - B4: " .. rangeLabel.Text)
Run(0.2)
Key(Enum.KeyCode.A, Enum.UserInputState.Begin)
Key(Enum.KeyCode.A, Enum.UserInputState.End)
check(fired[#fired].payload[1] == 48, "A = C3 (48)")
local newest
for _, s in ipairs(ls) do if s.IsPlaying and math.abs(s.PlaybackSpeed - 0.5) < 1e-4 then newest = s end end
check(newest ~= nil, "C3 plays at speed 0.5")
for _ = 1, 4 do Key(Enum.KeyCode.X, Enum.UserInputState.Begin) end
check(rangeLabel.Text == "C5  -  B6", "X x4 clamps at C5 - B6: " .. rangeLabel.Text)
for _ = 1, 5 do Key(Enum.KeyCode.Z, Enum.UserInputState.Begin) end
check(rangeLabel.Text == "C2  -  B3", "Z x5 clamps at C2 - B3: " .. rangeLabel.Text)
Key(Enum.KeyCode.X, Enum.UserInputState.Begin)
Key(Enum.KeyCode.X, Enum.UserInputState.Begin)
check(rangeLabel.Text == "C4  -  B5", "back to C4 - B5")
local cLabel = gui:FindFirstChild("White12", true):FindFirstChild("Note")
check(cLabel and cLabel.Text == "C5", "the second C key is labelled C5")

print("== touch + mouse on the GUI keys")
Run(0.2)
local blackHit
for _, d in ipairs(gui:GetDescendants()) do if d.Name == "Hit1" then blackHit = d end end
local touch = M.NewInstance("InputObject")
touch.UserInputType = Enum.UserInputType.Touch
touch.UserInputState = Enum.UserInputState.Begin
blackHit.InputBegan:Fire(touch)
local black1 = gui:FindFirstChild("Black1", true)
check(black1.BackgroundColor3 == Color3.fromRGB(88, 205, 20), "touch lights C#4")
check(fired[#fired].payload[1] == 61, "C#4 = 61 sent")
touch.UserInputState = Enum.UserInputState.End
UserInputService.InputEnded:Fire(touch)
check(black1.BackgroundColor3 == Color3.fromRGB(40, 42, 50), "touch end releases it")
local lowerC, upperD
for _, d in ipairs(gui:GetDescendants()) do
	if d.Name == "Hit0" and d.Position.Y.Offset > 0 then lowerC = d end
	if d.Name == "Hit2" and d.Position.Y.Offset == 0 then upperD = d end
end
local click = {UserInputType = Enum.UserInputType.MouseButton1}
lowerC.InputBegan:Fire(click)
mouseDown = true
upperD.MouseEnter:Fire()
check(white0.BackgroundColor3 == WHITE and gui:FindFirstChild("White2", true).BackgroundColor3 == WHITE_LIT, "mouse drag: C released, D lit (glissando)")
mouseDown = false
UserInputService.InputEnded:Fire(click)
check(gui:FindFirstChild("White2", true).BackgroundColor3 == WHITE, "mouse up releases D")
check(pressed == 0, "(no header button pressed yet)")

print("== other players' notes")
Run(0.5)
local remote = fired[1].model and piano
local Remote = ReplicatedStorage.Remotes.FunBuildAction
Remote.OnClientEvent:Fire(piano, "Note", {{64, 67}, 2})
local rs = {}
for _, s in ipairs(soundAt:GetChildren()) do if s.ClassName == "Sound" then table.insert(rs, s) end end
check(#rs == 8, "3D pool of 8 on the Pivot_Sound attachment: " .. #rs)
check(rs[1].IsPlaying and math.abs(rs[1].PlaybackSpeed - 2 ^ (4 / 12)) < 1e-4 and rs[2].IsPlaying and math.abs(rs[2].PlaybackSpeed - 2 ^ (7 / 12)) < 1e-4,
	"E4 + G4 play in 3D")
check(rs[1].RollOffMaxDistance == 80 and rs[1].RollOffMode == Enum.RollOffMode.InverseTapered, "rolloff InverseTapered, max 80")
camera.CFrame = CFrame.new(At(Vector3.new(0, 12, -400)))
rs[3].IsPlaying = false
Remote.OnClientEvent:Fire(piano, "Note", {72, 2})
check(not rs[3].IsPlaying, "a far camera does not play remote notes")
camera.CFrame = CFrame.new(At(Vector3.new(0, 12, -22)))
Remote.OnClientEvent:Fire(piano, "Note", {"junk", 2})
Remote.OnClientEvent:Fire(piano, "Note", "junk")
Remote.OnClientEvent:Fire(piano, "Note", {{1, 2, "x"}, 2})

print("== server validation")
Run(1.1)
before = #fired
Remote.OnServerEvent:Fire(other, piano, "Note", 60)
check(#fired == before, "a player NOT seated here is ignored")
for _, bad in ipairs({60.5, "60", 1000, 0 / 0, {200}, {}, math.huge}) do
	Remote:FireServer(piano, "Note", bad)
end
check(#fired == before, "bad payloads ignored")
Run(1.1)
Remote:FireServer(piano, "Note", {60, 64, 67, 70, 72, 76, 79, 84})
f = fired[#fired]
check(#fired == before + 1 and #f.payload[1] == 6, "a chord is capped at 6 notes")
Run(1.1)
before = #fired
for i = 1, 20 do Remote:FireServer(piano, "Note", 60 + i % 12) end
check(#fired - before <= 12 and #fired - before >= 10, "rate limited to 12 sends/s: " .. (#fired - before))

print("== close button stands the player up (and the GUI comes back if the jump did not take)")
Run(1.1)
local close = gui:FindFirstChild("Close", true)
close.Activated:Fire()
check(humanoid.Jump == true and rawget(humanoid, "__props").Sit == false, "Jump requested")
check(playerGui:FindFirstChild("FunPianoGui") == nil and CAS.FunPianoKeys == nil, "GUI closed + keys unbound")
Run(1.2)
gui = playerGui:FindFirstChild("FunPianoGui")
check(gui ~= nil, "still seated a second later -> piano back")

print("== walking away > 20 studs closes it")
root.CFrame = CFrame.new(At(Vector3.new(0, 3, -40)))
Run(0.1)
check(playerGui:FindFirstChild("FunPianoGui") == nil, "far -> closed")
root.CFrame = CFrame.new(At(Vector3.new(0, 3, -7)))

print("== standing up closes it; someone else plays")
seat.Occupant = nil
humanoid.SeatPart = nil
humanoid.Sit = false
Run(0.2)
check(piano:GetAttribute("Fun_Player") == 0 and sitPrompt.Enabled == true, "bench free again")
seat:Sit(otherHumanoid)
otherHumanoid.SeatPart = seat
Run(0.2)
check(piano:GetAttribute("Fun_Player") == 2, "Fun_Player = 2")
check(playerGui:FindFirstChild("FunPianoGui") == nil, "no GUI for the local player")
Remote.OnClientEvent:Fire(piano, "Note", {50, 2})
Run(0.05)
local oshoulder = otherChar:FindFirstChild("LeftShoulder", true)
check(oshoulder.Transform ~= CFrame.identity, "the other pianist is posed on this client")

print("== re-sit, then sold while playing")
seat.Occupant = nil
otherHumanoid.SeatPart = nil
Run(0.2)
seat:Sit(humanoid)
humanoid.SeatPart = seat
Run(0.2)
check(playerGui:FindFirstChild("FunPianoGui") ~= nil, "GUI open again")
Key = function(code, state) return CAS.FunPianoKeys and CAS.FunPianoKeys.fn("FunPianoKeys", state, {KeyCode = code}) end
Key(Enum.KeyCode.H, Enum.UserInputState.Begin)
piano:Destroy()
Run(0.5)
check(playerGui:FindFirstChild("FunPianoGui") == nil and CAS.FunPianoKeys == nil, "GUI closed when the piano is sold")
check(#LocalSounds() == 0, "local sound pool cleaned up")
check(workspace.FunBuildLocal:FindFirstChild("PianoFX") == nil, "float anchor cleaned up")
check(#runtime:GetChildren() == 0, "runtime folder empty")

print(("\n== RESULT: %d failed checks, %d runtime errors, %d warnings, %d tweens"):format(fails, SIM.errors, #SIM.warns, tweens))
local unknown = {}
for k in pairs(SIM.unknownReads) do table.insert(unknown, k) end
table.sort(unknown)
print("unknown/nil property reads: " .. table.concat(unknown, ", "))
