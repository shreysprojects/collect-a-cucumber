local SRC = {
	Kit = [=[
--[[
	FunBuildKit  (ModuleScript, ReplicatedStorage.Modules)  2026-09-24
	Shared helpers for FUNCTIONAL BUILDS (user: "make all the fun stuff functional - tv could be turned on,
	trampoline bouncy, seesaw functional ..."). Used by ServerScriptService.FunBuildService, the client
	StarterPlayerScripts.FunBuildClient and every behaviour module:
	  ServerStorage.FunBehaviours.<BaseKey>              (server half, ModuleScript)
	  ReplicatedStorage.FunBehavioursClient.<BaseKey>    (client half, ModuleScript)
	A behaviour runs for every PLACED build (CollectionService tag "PlacedBuild") whose BuildKey, minus a
	variant suffix ("Lantern_A" -> "Lantern"), names the module. See fun-builds/CONTRACT.md.

	GEOMETRY. A placed build is a clone of its ReplicatedStorage.PlaceableBuilds template. BuildService
	stamps two attributes on every template: AuthoredCentre (Vector3, the bounding-box centre of the
	build's parts in the AUTHORED frame = ServerStorage.Builds source coordinates, floor centre at the
	origin, front toward -Z) and Scale (number, BuildCatalog.ScaleOf). The Hitbox (PrimaryPart) sits at
	that centre and the template was Model:ScaleTo(Scale)'d about it, so an authored point p is at
	Hitbox.CFrame * ((p - AuthoredCentre) * Scale) in the world. Pivot_<Name> / State_<Name> authoring
	attributes survive on templates (Pivot_* are authored-frame Vector3s) - Kit.Pivot converts them.
]]
local RunService = game:GetService("RunService")

local Kit = {}

Kit.PLACED_TAG = "PlacedBuild"
Kit.PROMPT_TAG = "FunBuildPrompt"       -- every prompt a behaviour makes (hidden in build mode by the client)
Kit.REMOTE = "FunBuildAction"           -- ReplicatedStorage.Remotes.<this>: RemoteEvent both ways
Kit.STATE_PREFIX = "Fun_"               -- ctx:SetState(k, v) -> model attribute Fun_<k>
Kit.SERVER_FOLDER = "FunBehaviours"     -- ServerStorage.<this>.<BaseKey>
Kit.CLIENT_FOLDER = "FunBehavioursClient" -- ReplicatedStorage.<this>.<BaseKey>
Kit.RUNTIME_FOLDER = "FunBuildRuntime"  -- workspace.<this>: helper PARTS a behaviour makes (seats, triggers) live here, never inside the build
Kit.LIE_ATTR = "Lie"                    -- a Seat with Lie = true lays its occupant flat (server turns the SeatWeld, clients straighten the joints)

--..Keys..--
function Kit.Key(model)
	return model and model:GetAttribute("BuildKey")
end

--.. "Lantern_A" -> "Lantern", "A"; "TV" -> "TV", nil
function Kit.Split(key)
	if type(key) ~= "string" then return nil, nil end
	local base, letter = key:match("^(.-)_(%u)$")
	if base and base ~= "" then return base, letter end
	return key, nil
end

--.. a variant part name: Kit.VName(model, "Light") -> "A_Light" on Lantern_A, "Light" on a plain build
function Kit.VName(model, name)
	local _, letter = Kit.Split(Kit.Key(model))
	return letter and (letter .. "_" .. name) or name
end

--..Geometry..--
function Kit.Scale(model)
	return tonumber(model:GetAttribute("Scale")) or 1
end

function Kit.Hitbox(model)
	return model.PrimaryPart or model:FindFirstChild("Hitbox")
end

function Kit.AuthoredCentre(model)
	local c = model:GetAttribute("AuthoredCentre")
	return typeof(c) == "Vector3" and c or Vector3.zero
end

--.. the world CFrame of the authored origin (floor centre, authored axes), scale included in positions via ToWorld
function Kit.Origin(model)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return model:GetPivot() end
	return hitbox.CFrame * CFrame.new(-Kit.AuthoredCentre(model) * Kit.Scale(model))
end

--.. an authored-frame point -> world
function Kit.ToWorld(model, p)
	return Kit.Origin(model):PointToWorldSpace(p * Kit.Scale(model))
end

--.. an authored-frame CFrame (position authored, rotation authored) -> world
function Kit.CFrameToWorld(model, cf)
	local s = Kit.Scale(model)
	return Kit.Origin(model) * (CFrame.new(cf.Position * s) * cf.Rotation)
end

--.. Pivot_<name> (authored Vector3) -> world Vector3, or nil. Variant builds carry Pivot_A_Light etc.; pass the full name
function Kit.Pivot(model, name)
	local v = model:GetAttribute("Pivot_" .. name)
	if typeof(v) == "Vector3" then return Kit.ToWorld(model, v) end
	return nil
end

--.. the world floor point under the build (bottom centre of the hitbox) and its up
function Kit.Floor(model)
	local hitbox = Kit.Hitbox(model)
	return hitbox.CFrame * CFrame.new(0, -hitbox.Size.Y * 0.5, 0)
end

--..Parts..--
function Kit.Part(model, name)
	local p = model:FindFirstChild(name, true)
	if p and p:IsA("BasePart") then return p end
	return nil
end

--.. every BasePart (not the Hitbox) whose Name starts with prefix, sorted by name
function Kit.Parts(model, prefix)
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Hitbox" and d.Name:sub(1, #prefix) == prefix then table.insert(list, d) end
	end
	table.sort(list, function(a, b) return a.Name < b.Name end)
	return list
end

--.. {part = relative CFrame} of parts about a pivot CFrame, for rigid animation: part.CFrame = pivot * motion * rel
function Kit.Rig(parts, pivotCF)
	local rig = {}
	for _, p in ipairs(parts) do rig[p] = pivotCF:ToObjectSpace(p.CFrame) end
	return rig
end

function Kit.PoseRig(rig, cf)
	for p, rel in pairs(rig) do
		if p.Parent then p.CFrame = cf * rel end
	end
end

--..State..--
function Kit.IsBroken(model)
	return model:GetAttribute("Broken") == true
end

function Kit.OwnerId(model)
	return model:GetAttribute("Owner")
end

function Kit.State(model, key)
	return model:GetAttribute(Kit.STATE_PREFIX .. key)
end

function Kit.Now()
	return workspace:GetServerTimeNow()
end

--..Characters..--
function Kit.CharacterParts(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid, root
end

--.. the joints of an R15/R6 character that animation drives (Motor6D or AnimationConstraint - New Map characters use
--.. AnimationConstraint since 2026-09); returns {joint = true}
function Kit.Joints(character)
	local joints = {}
	if not character then return joints end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then joints[d] = true end
	end
	return joints
end

--.. the rotation a lying occupant's root takes relative to its seat: head toward the seat's LookVector (-Z),
--.. face up (+Y), back on the seat
Kit.LIE_ROTATION = CFrame.fromMatrix(Vector3.zero, Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, -1, 0))

--..Sounds..--
--.. a Sound from ReplicatedStorage.Assets.Sounds by name, or from a raw id ("rbxassetid://..." or a number)
function Kit.MakeSound(nameOrId, props)
	local sound
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local lib = assets and assets:FindFirstChild("Sounds")
	local template = type(nameOrId) == "string" and lib and lib:FindFirstChild(nameOrId, true)
	if template and template:IsA("Sound") then
		sound = template:Clone()
	else
		sound = Instance.new("Sound")
		local id = tostring(nameOrId)
		if tonumber(id) then id = "rbxassetid://" .. id end
		sound.SoundId = id
	end
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 90
	for k, v in pairs(props or {}) do sound[k] = v end
	return sound
end

Kit.IsServer = RunService:IsServer()

return Kit
]=],
	FunAssets = [=[
--[[
	FunAssets  (ModuleScript, ReplicatedStorage.Modules)  2026-09-24
	Every sound / video / picture the functional builds use, in one place. Behaviours never hard-code an id:
	they ask FunAssets.Sfx.<Name> (a value Kit.MakeSound / ctx:Sound accept: an "rbxassetid://" id OR the
	name of a Sound in ReplicatedStorage.Assets.Sounds) and read the lists below.

	Every id here was checked in this place's edit data model on 2026-09-24 (fun-builds/assets/ research):
	  * sounds: ContentProvider:PreloadAsync = Success and Sound.TimeLength > 0; the one-shots were also run
	    through an AudioAnalyzer (unwired to any output, so silent) to check the sound starts at once and is
	    not clipped
	  * videos: VideoFrame.IsLoaded = true, Resolution 1280x720 (all Roblox-created)
	  * pictures: decal -> IMAGE id via InsertService:LoadAsset, AssetTypeId 1, preload Success, thumbnail
	    looked at (family friendly)
	Sources, creators, durations: fun-builds/assets/ASSETS.md. Most sounds are Pro Sound Effects / APM /
	Roblox-created (licensed for every experience); the rest are public Creator Store uploads.
]]
local M = {}

--.. one-shots and loops. Values: "rbxassetid://<id>" (a Sound library name still works too)
M.Sfx = {
	--..Toys / outdoors..--
	Boing = "rbxassetid://6075441854",        -- trampoline bounce: cartoon spring boing (1.3 s)
	Creak = "rbxassetid://9120839174",        -- seesaw / hammock / bed: wood creak-squeak (1.4 s)
	Whee = "rbxassetid://9119197913",         -- slide ride: slide whistle (1.35 s)
	Thump = "rbxassetid://9113535217",        -- seesaw end lands: soft low body thump (1.2 s)
	Splash = "rbxassetid://9117823374",       -- hot tub / bath jump-in splash (2.3 s)
	Crickets = "rbxassetid://9112764546",     -- night crickets (36 s, loopable)
	Caw = "rbxassetid://9118067220",          -- scarecrow crow: single raven caw (0.7 s)
	Rustle = "rbxassetid://9114576499",       -- bush: leafy foliage rustle (2.2 s)
	Cheer = "rbxassetid://1841221347",        -- kids shouting "Yeah!" (APM, 2.9 s)
	Whoosh = "rbxassetid://9126229255",       -- fast airy whoosh (1.0 s)
	Zap = "rbxassetid://116624744040072",     -- electric spark zap (2.5 s)
	Sparkle = "rbxassetid://3199238931",      -- magic gem sparkle (2.1 s)
	Click = "rbxassetid://15675059323",       -- Roblox UI bright click (0.4 s)

	--..TV..--
	TVOn = "rbxassetid://9119973992",         -- tv power-on pop at 0.15 s, then (near) silence
	TVOff = "rbxassetid://78535264432518",    -- old tv switching off (0.7 s)
	TVStatic = "rbxassetid://96891705634188", -- white-noise static, starts at once (2.1 s; TV cuts it at 0.4 s)

	--..Vending / arcade..--
	Fizz = "rbxassetid://123359260762085",    -- soda can opened, psst + fizz (2.5 s)
	CanDrop = "rbxassetid://9114185361",      -- can drops into the chute, hollow bounce (1.6 s, quiet)
	Coin = "rbxassetid://16480549189",        -- token / coin insert (Roblox pinball set, 1.9 s)
	ArcadeBlip = "rbxassetid://16480580213",  -- 8-bit blip (Roblox pinball set, 0.7 s)
	ArcadeLose = "rbxassetid://190705984",    -- sad trombone (3.9 s)
	ArcadeWin = "rbxassetid://16480577565",   -- 8-bit rising win jingle (Roblox pinball set, 2.9 s)
	Burp = "rbxassetid://9113414717",         -- short silly belch (0.8 s)
	Gulp = "rbxassetid://133988388434763",    -- single swallow gulp (1.2 s)

	--..Fire / water loops..--
	FireLoop = "rbxassetid://9112780462",     -- fireplace crackle (43 s, loop)
	FireIgnite = "rbxassetid://4510176414",   -- match strike + flare (1.5 s)
	FireOut = "rbxassetid://9113702967",      -- blow-out puff (0.7 s)
	WaterLoop = "rbxassetid://9120557306",    -- fountain splashing / running water (36 s, loop)
	BubblesLoop = "rbxassetid://9112752570",  -- streams of small bubbles (13.8 s, loop)
	Flush = "rbxassetid://116759736098379",   -- toilet flush rush (4.3 s)

	--..Kitchen / appliances..--
	Sizzle = "rbxassetid://9114542867",       -- pan sizzle (40 s, loop)
	HumLoop = "rbxassetid://112948256817153", -- refrigerator hum (72 s, loop)
	FridgeHum = "rbxassetid://112948256817153",
	FridgeOpen = "rbxassetid://9118125101",   -- fridge door open, light seal squeak (1.7 s)
	FridgeClose = "rbxassetid://9118127655",  -- fridge door closes with a soft slam (1.5 s)
	MicrowaveHum = "rbxassetid://4399963971", -- microwave running hum (10.6 s, loop)
	MicrowaveBeep = "rbxassetid://3690600068", -- keypad beep (0.1 s)
	Ding = "rbxassetid://9125485591",         -- single bell ding, long ring (4.5 s)
	DoorOpen = "rbxassetid://9118124760",     -- appliance door open, light metal squeak (1.9 s)
	DoorClose = "rbxassetid://9120492567",    -- chunky appliance door clunk (2.6 s)
	WasherLoop = "rbxassetid://9118891774",   -- washing machine cycle (45 s, loop)
	DryerLoop = "rbxassetid://77493396468975", -- clothes dryer tumbling (44 s, loop)
	ToasterPop = "rbxassetid://365950085",    -- toaster pop-up (Roblox, 0.65 s)

	--..Home..--
	ClockTick = "rbxassetid://16480551554",   -- single small metal tick (Roblox, 0.36 s)
	ClockChime = "rbxassetid://16480570385",  -- single low bell strike (Roblox, 1.5 s)
	PianoNote = "rbxassetid://78413131279275", -- ONE sustained piano C4 (6 s), pitched by PlaybackSpeed
	CushionPoof = "rbxassetid://9120204520",  -- soft fabric flop (2.0 s)
}

--.. the pitch of M.Sfx.PianoNote (Hz) - PlaybackSpeed = target / root. Measured with an AudioAnalyzer:
--.. fundamental 261-262 Hz, harmonics at 522 / 1046 Hz = C4.
M.PianoRootHz = 261.63

--.. looping music for the DJ booth / jukebox-like builds: {Name = "...", Id = "rbxassetid://..."}
--.. all APM (Roblox-licensed), full-length tracks
M.Music = {
	{Name = "Funky Disco Beats", Id = "rbxassetid://9038367768"},              -- funky EDM, 3:20
	{Name = "Midnight Studio Juice", Id = "rbxassetid://9038366120"},          -- bouncy EDM, 3:22
	{Name = "Feel That Move", Id = "rbxassetid://9044944264"},                 -- 80s funk, 3:08
	{Name = "Stracciatella Galaxy", Id = "rbxassetid://9042927295"},           -- space disco funk, 3:38
	{Name = "Normalize Today", Id = "rbxassetid://9046300489"},                -- upbeat funk, 2:03
	{Name = "Floating Through Deeper Thoughts", Id = "rbxassetid://9038366820"}, -- uplifting bouncy EDM, 2:57
	{Name = "Jazz Joint", Id = "rbxassetid://9045468115"},                     -- lounge jazz organ, 2:33
	{Name = "Halves", Id = "rbxassetid://1837104550"},                         -- positive synth groove, 2:12
}

--.. pictures (IMAGE ids) shared by the slideshows below
local NATURE = {
	"rbxassetid://5717309394",  -- mountain lake
	"rbxassetid://10719452874", -- iceberg
	"rbxassetid://1908897932",  -- waterfall
	"rbxassetid://5887500272",  -- mountains and fog
	"rbxassetid://3319553125",  -- ocean sunset
	"rbxassetid://2546997593",  -- snowy valley lake
}
local SPACE = {
	"rbxassetid://6864892942",   -- earth from space
	"rbxassetid://14833944867",  -- saturn (Voyager)
	"rbxassetid://12787761154",  -- pillars of creation
	"rbxassetid://10208853991",  -- cosmic cliffs, carina nebula
	"rbxassetid://9728471648",   -- butterfly nebula
	"rbxassetid://117453845793004", -- tarantula nebula
}
local ANIMALS = {
	"rbxassetid://5484695170",  -- red panda
	"rbxassetid://12590518027", -- puppy
	"rbxassetid://404656671",   -- kitten
	"rbxassetid://2414749340",  -- sea otter
	"rbxassetid://14912788722", -- penguin
	"rbxassetid://289280641",   -- fluffy kitten
}
local FOOD = {
	"rbxassetid://4772865076",    -- pepperoni pizza
	"rbxassetid://79619558",      -- cupcakes
	"rbxassetid://105472541332250", -- fruit salad
	"rbxassetid://90082450177424",  -- pancake stack
	"rbxassetid://3397603611",    -- watermelon slices
	"rbxassetid://3290518286",    -- strawberries
}

--.. TV channels. A channel is either {Name, Video = "rbxassetid://..."} (VideoFrame, looped, muted unless
--.. Sound = true; Slides/Seconds = the fallback while the video can't play) or
--.. {Name, Slides = {"rbxassetid://<IMAGE id>", ...}, Seconds = 4} (a picture slideshow)
M.TVChannels = {
	{Name = "Waterfall Cam", Video = "rbxassetid://5670869502", Slides = NATURE, Seconds = 4},   -- Roblox, 30 s
	{Name = "Space Walk", Video = "rbxassetid://5608398904", Slides = SPACE, Seconds = 4},       -- Roblox, 13 s
	{Name = "Cartoon Sea", Video = "rbxassetid://5608250999", Slides = ANIMALS, Seconds = 4},    -- Roblox, 15 s
	{Name = "Bird Watch", Video = "rbxassetid://5608392925", Slides = NATURE, Seconds = 4},      -- Roblox, 15 s
	{Name = "Nature", Slides = NATURE, Seconds = 4},
	{Name = "Space", Slides = SPACE, Seconds = 4},
	{Name = "Cute Animals", Slides = ANIMALS, Seconds = 4},
	{Name = "Yummy Food", Slides = FOOD, Seconds = 4},
}

--.. pictures for picture frames / screens: IMAGE ids (not decal ids) - public-domain classic paintings
M.Pictures = {
	"rbxassetid://1305342230",   -- The Starry Night, Van Gogh
	"rbxassetid://14044191899",  -- The Great Wave off Kanagawa, Hokusai
	"rbxassetid://12083554328",  -- Sunflowers, Van Gogh
	"rbxassetid://4623606213",   -- Cafe Terrace at Night, Van Gogh
	"rbxassetid://3117938916",   -- Woman with a Parasol, Monet
	"rbxassetid://925192416",    -- A Sunday on La Grande Jatte, Seurat
	"rbxassetid://4623605764",   -- Almond Blossom, Van Gogh
	"rbxassetid://91423198665435", -- Irises, Van Gogh
	"rbxassetid://15816945717",  -- Wheat Field with Cypresses, Van Gogh
	"rbxassetid://108467815321983", -- The Hay Wain, Constable
	"rbxassetid://8178605912",   -- Poppies, Monet
	"rbxassetid://11562220650",  -- Sunset on the Seine, Monet
}

return M
]=],
	Service = [=[
--[[
	FunBuildService  (Script, ServerScriptService)  2026-09-24
	Server half of FUNCTIONAL BUILDS (fun-builds/CONTRACT.md). Every placed build (tag "PlacedBuild" in a
	plot's Placed folder: placed, moved, restored by BaseSaveService) whose base key has a module in
	ServerStorage.FunBehaviours gets that module's Server(model, ctx) run for it. The ctx owns everything
	the behaviour makes (prompts, seats, sounds, loops, connections) and tears it all down when the build
	is sold / cleared, and re-runs the behaviour from scratch when the build is MOVED (its Hitbox turns
	up somewhere else) or when BuildHealthService breaks / mends it (a Broken build runs nothing).
	One RemoteEvent, ReplicatedStorage.Remotes.FunBuildAction, carries both ways:
	  client -> server  (model, action, payload): the module's Actions[action](model, player, payload, ctx),
	                    only for a running build within ActionRange (default 40) studs of the player,
	                    at most ACTION_RATE per player per second
	  server -> client  (model, action, payload): ctx:Fire - the client module's OnEvent
	Studio hook: workspace:SetAttribute("FunBuildDev", "list" | "restart")
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local ACTION_RATE = 12          -- actions per player per second
local DEFAULT_ACTION_RANGE = 40 -- studs from the build's hitbox
local RESTART_DEBOUNCE = 0.25   -- a move sets CFrame on every part; restart once it settles
local DEFAULT_PROMPT_DISTANCE = 10

--..Instances..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local Remote = Remotes:FindFirstChild(Kit.REMOTE)
if not Remote then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = Kit.REMOTE
	Remote.Parent = Remotes
end
local Runtime = workspace:FindFirstChild(Kit.RUNTIME_FOLDER)
if Runtime then Runtime:ClearAllChildren() else
	Runtime = Instance.new("Folder")
	Runtime.Name = Kit.RUNTIME_FOLDER
	Runtime.Parent = workspace
end

--..Behaviours..--
local Behaviours = {} -- [base key] = module table
local function LoadBehaviours()
	local folder = ServerStorage:WaitForChild(Kit.SERVER_FOLDER, 30)
	if not folder then
		warn("[FunBuildService] ServerStorage." .. Kit.SERVER_FOLDER .. " missing - no functional builds")
		return 0
	end
	local n = 0
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("ModuleScript") then
			local ok, mod = pcall(require, m)
			if ok and type(mod) == "table" and type(mod.Server) == "function" then
				for _, key in ipairs(type(mod.Keys) == "table" and mod.Keys or {m.Name}) do Behaviours[key] = mod end
				n += 1
			else
				warn("[FunBuildService] behaviour " .. m.Name .. " failed to load: " .. tostring(mod))
			end
		end
	end
	return n
end

--.. the module for a key: the exact key first ("Lantern_A"), then its base ("Lantern")
local function BehaviourOf(key)
	if type(key) ~= "string" then return nil end
	if Behaviours[key] then return Behaviours[key] end
	local base = Kit.Split(key)
	return base and Behaviours[base] or nil
end

--..Running builds..--
local Running = {} -- [model] = ctx

local function NewContext(model, mod)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {
		Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		Behaviour = mod, _alive = true, _conns = {}, _insts = {}, _cleanups = {}, _states = {},
	}
	local folder = Instance.new("Folder")
	folder.Name = tostring(key) .. "_" .. tostring(model:GetAttribute("Owner") or 0) .. "_" .. string.format("%x", math.random(0, 0xFFFFFF))
	folder.Parent = Runtime
	ctx.Folder = folder -- helper parts live here (never inside the build: the placement overlap test and the broken-fade would see them)
	table.insert(ctx._insts, folder)

	function ctx:Alive() return self._alive and model.Parent ~= nil end
	function ctx:Connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(self._conns, c)
		return c
	end
	function ctx:Add(inst)
		table.insert(self._insts, inst)
		return inst
	end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:SetState(k, v)
		self._states[k] = true
		model:SetAttribute(Kit.STATE_PREFIX .. k, v)
	end
	function ctx:GetState(k) return model:GetAttribute(Kit.STATE_PREFIX .. k) end
	function ctx:Fire(action, payload) Remote:FireAllClients(model, action, payload) end
	function ctx:FireTo(player, action, payload) Remote:FireClient(player, model, action, payload) end
	--.. run fn every `seconds` (first call after one period) until the behaviour stops
	function ctx:Every(seconds, fn)
		task.spawn(function()
			while true do
				task.wait(seconds)
				if not self:Alive() then return end
				local ok, err = pcall(fn)
				if not ok then warn("[FunBuildService] " .. tostring(key) .. " Every: " .. tostring(err)) end
			end
		end)
	end
	function ctx:Heartbeat(fn) return self:Connect(RunService.Heartbeat, fn) end
	function ctx:IsOwner(player) return player and player.UserId == model:GetAttribute("Owner") end
	function ctx:HumanoidOf(player)
		local character = player and player.Character
		local humanoid, root = Kit.CharacterParts(character)
		if humanoid and humanoid.Health > 0 and root then return humanoid, root end
		return nil
	end
	function ctx:Near(player, dist)
		local _, root = self:HumanoidOf(player)
		local hitbox = Kit.Hitbox(model)
		return root ~= nil and hitbox ~= nil and (root.Position - hitbox.Position).Magnitude <= (dist or DEFAULT_ACTION_RANGE)
	end
	--.. a Custom-style ProximityPrompt (StarterPlayerScripts.CucumberPromptClient draws it like the game's other prompts)
	--.. opts: Action, Object, Hold (s), Distance, Key (KeyCode), Name, Offset (Vector3 in the part's space), Exclusivity
	function ctx:Prompt(part, opts)
		opts = opts or {}
		local parent = part
		if opts.Offset then
			local att = Instance.new("Attachment")
			att.Name = "FunPromptAt"
			att.Position = opts.Offset
			att.Parent = part
			self:Add(att)
			parent = att
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = opts.Name or "FunPrompt"
		prompt.ObjectText = opts.Object or tostring(model:GetAttribute("DisplayName") or base)
		prompt.ActionText = opts.Action or "Use"
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.KeyboardKeyCode = opts.Key or Enum.KeyCode.E
		prompt.GamepadKeyCode = opts.Gamepad or Enum.KeyCode.ButtonX
		prompt.HoldDuration = opts.Hold or 0
		prompt.MaxActivationDistance = opts.Distance or DEFAULT_PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = opts.Exclusivity or Enum.ProximityPromptExclusivity.OnePerButton
		prompt:SetAttribute("BaseDistance", prompt.MaxActivationDistance)
		CollectionService:AddTag(prompt, Kit.PROMPT_TAG)
		prompt.Parent = parent
		self:Add(prompt)
		return prompt
	end
	--.. an invisible anchored Seat at a WORLD cframe (the occupant's hips rest on its top face), with a "Sit" prompt.
	--.. opts: Name, Size (Vector3, default 2 x 0.4 x 2), Lie (lay the occupant flat: head toward the seat's LookVector),
	--.. LieLift (studs from the seat's top face to the root's centre, default 0.55), Prompt (action text, false = none),
	--.. Object, Distance, PromptOffset
	function ctx:Seat(cframe, opts)
		opts = opts or {}
		local seat = Instance.new("Seat")
		seat.Name = opts.Name or "FunSeat"
		seat.Size = opts.Size or Vector3.new(2, 0.4, 2)
		seat.CFrame = cframe
		seat.Transparency = 1
		seat.Anchored = true
		seat.CanCollide = false
		seat.CanTouch = false -- no sitting by walking into it: the prompt (or Seat:Sit) seats people
		seat.CanQuery = false
		seat.CastShadow = false
		seat.Parent = self.Folder
		if opts.Lie then
			seat:SetAttribute(Kit.LIE_ATTR, true)
			local lift = opts.LieLift or 0.55
			self:Connect(seat.ChildAdded, function(child)
				if child:IsA("Weld") and child.Name == "SeatWeld" then
					task.defer(function()
						if child.Parent then
							child.C0 = CFrame.new(0, seat.Size.Y * 0.5 + lift, 0) * Kit.LIE_ROTATION
							child.C1 = CFrame.new()
						end
					end)
				end
			end)
		end
		if opts.Prompt ~= false then
			local prompt = self:Prompt(seat, {Action = opts.Prompt or "Sit", Object = opts.Object, Distance = opts.Distance or 8, Name = "SitPrompt", Offset = opts.PromptOffset})
			self:Connect(prompt.Triggered, function(player)
				if seat.Occupant then return end
				local humanoid = self:HumanoidOf(player)
				if not humanoid or humanoid.Sit or humanoid.SeatPart then return end
				seat:Sit(humanoid)
			end)
			--.. a taken seat hides its prompt
			self:Connect(seat:GetPropertyChangedSignal("Occupant"), function()
				prompt.Enabled = seat.Occupant == nil
			end)
		end
		self:Add(seat)
		return seat
	end
	--.. a helper Part in the runtime folder (anchored, no collide/query/touch unless opts say so)
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = self.Folder end
		self:Add(p)
		return p
	end
	function ctx:Sound(parent, nameOrId, props)
		local s = Kit.MakeSound(nameOrId, props)
		s.Parent = parent
		self:Add(s)
		return s
	end
	return ctx
end

local function Stop(model)
	local ctx = Running[model]
	if not ctx then return end
	Running[model] = nil
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		if not ok then warn("[FunBuildService] cleanup " .. tostring(ctx.Key) .. ": " .. tostring(err)) end
	end
	for _, c in ipairs(ctx._conns) do c:Disconnect() end
	for i = #ctx._insts, 1, -1 do
		local inst = ctx._insts[i]
		if typeof(inst) == "Instance" then inst:Destroy() end
	end
	if model.Parent then
		for k in pairs(ctx._states) do model:SetAttribute(Kit.STATE_PREFIX .. k, nil) end
	end
end

local function Start(model)
	if Running[model] then return end
	if not (model:IsA("Model") and model:IsDescendantOf(workspace) and CollectionService:HasTag(model, Kit.PLACED_TAG)) then return end
	if Kit.IsBroken(model) or not Kit.Hitbox(model) then return end
	local mod = BehaviourOf(Kit.Key(model))
	if not mod then return end
	local ctx = NewContext(model, mod)
	Running[model] = ctx
	local ok, result = pcall(mod.Server, model, ctx)
	if not ok then
		warn("[FunBuildService] " .. tostring(ctx.Key) .. " Server(): " .. tostring(result))
	elseif type(result) == "function" then
		ctx:OnCleanup(result)
	end
end

local function Restart(model)
	Stop(model)
	Start(model)
end

--.. watchers per build: moved (the hitbox CFrame changes; the move pivots every part) / broken / mended
local Watched = {}
local function Watch(model)
	if Watched[model] or not model:IsA("Model") then return end
	local key = Kit.Key(model)
	if not BehaviourOf(key) then return end
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local conns = {}
	Watched[model] = conns
	local pending = false
	local function queue()
		if pending then return end
		pending = true
		task.delay(RESTART_DEBOUNCE, function()
			pending = false
			if Watched[model] then Restart(model) end
		end)
	end
	table.insert(conns, hitbox:GetPropertyChangedSignal("CFrame"):Connect(queue))
	table.insert(conns, model:GetAttributeChangedSignal("Broken"):Connect(queue))
	table.insert(conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			Stop(model)
			for _, c in ipairs(conns) do c:Disconnect() end
			Watched[model] = nil
		end
	end))
	Start(model)
end

local function Unwatch(model)
	Stop(model)
	local conns = Watched[model]
	if conns then
		for _, c in ipairs(conns) do c:Disconnect() end
		Watched[model] = nil
	end
end

--..Actions from clients..--
local Budget = {} -- [player] = {t, n}
Remote.OnServerEvent:Connect(function(player, model, action, payload)
	if typeof(model) ~= "Instance" or type(action) ~= "string" or #action > 40 then return end
	local now = os.clock()
	local b = Budget[player]
	if not b or now - b.t >= 1 then b = {t = now, n = 0} Budget[player] = b end
	b.n += 1
	if b.n > ACTION_RATE then return end
	local ctx = Running[model]
	if not ctx then return end
	local mod = ctx.Behaviour
	local handler = type(mod.Actions) == "table" and mod.Actions[action]
	if type(handler) ~= "function" then return end
	if not ctx:Near(player, mod.ActionRange or DEFAULT_ACTION_RANGE) then return end
	local ok, err = pcall(handler, model, player, payload, ctx)
	if not ok then warn("[FunBuildService] " .. tostring(ctx.Key) .. " action " .. action .. ": " .. tostring(err)) end
end)
Players.PlayerRemoving:Connect(function(player) Budget[player] = nil end)

--..Setup..--
local loaded = LoadBehaviours()
CollectionService:GetInstanceAddedSignal(Kit.PLACED_TAG):Connect(function(model)
	task.defer(Watch, model) -- BuildService tags before it parents; look a frame later
end)
CollectionService:GetInstanceRemovedSignal(Kit.PLACED_TAG):Connect(Unwatch)
for _, model in ipairs(CollectionService:GetTagged(Kit.PLACED_TAG)) do task.defer(Watch, model) end

workspace:GetAttributeChangedSignal("FunBuildDev"):Connect(function()
	local cmd = workspace:GetAttribute("FunBuildDev")
	if cmd == nil or cmd == "" then return end
	workspace:SetAttribute("FunBuildDev", nil)
	if cmd == "list" then
		local rows = {}
		for model, ctx in pairs(Running) do table.insert(rows, tostring(ctx.Key) .. "@" .. model:GetFullName()) end
		print("[FunBuildService] running: " .. #rows .. "\n  " .. table.concat(rows, "\n  "))
	elseif cmd == "restart" then
		for model in pairs(Watched) do Restart(model) end
		print("[FunBuildService] restarted every functional build")
	end
end)

local names = {}
for k in pairs(Behaviours) do table.insert(names, k) end
table.sort(names)
print(("[FunBuildService] %d behaviour module(s): %s"):format(loaded, table.concat(names, ", ")))
]=],
	Client = [=[
--[[
	FunBuildClient  (LocalScript, StarterPlayerScripts)  2026-09-24
	Client half of FUNCTIONAL BUILDS (fun-builds/CONTRACT.md). Every placed build (tag "PlacedBuild") that
	streams in and has a module in ReplicatedStorage.FunBehavioursClient gets Client(model, ctx) run for
	it; the ctx tears everything down when the build streams out, is sold, moved (re-run) or broken.
	Also, for every behaviour at once:
	  * build mode: while PlayerGui.CucumberHUDDesign has BuildMode = true every FunBuildPrompt is hidden,
	    so a click in build mode selects / sells the build instead of using it (BoostPadClient does the same)
	  * lying seats: a Seat with attribute Lie = true (FunBuildService ctx:Seat{Lie = true}) straightens its
	    occupant's joints every frame (the SeatWeld already turns the body flat), so people lie instead of sit
	  * ReplicatedStorage.Remotes.FunBuildAction server -> client events go to the module's OnEvent
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Kit.REMOTE, 60)

--..Config..--
local DEFAULT_STEP_RANGE = 180 -- studs from the camera: ctx:Step callbacks sleep beyond this
local HUD_NAME = "CucumberHUDDesign"

--..Behaviours (loaded on demand, the folder can arrive late)..--
local Behaviours = {}
local folder = ReplicatedStorage:WaitForChild(Kit.CLIENT_FOLDER, 60)
local function Load(m)
	if not m:IsA("ModuleScript") then return end
	local ok, mod = pcall(require, m)
	if ok and type(mod) == "table" and type(mod.Client) == "function" then
		for _, key in ipairs(type(mod.Keys) == "table" and mod.Keys or {m.Name}) do Behaviours[key] = mod end
	else
		warn("[FunBuildClient] behaviour " .. m.Name .. " failed to load: " .. tostring(mod))
	end
end
if folder then
	for _, m in ipairs(folder:GetChildren()) do Load(m) end
end

local function BehaviourOf(key)
	if type(key) ~= "string" then return nil end
	if Behaviours[key] then return Behaviours[key] end
	local base = Kit.Split(key)
	return base and Behaviours[base] or nil
end

--..Running builds..--
local Running = {} -- [model] = ctx

local function NewContext(model, mod)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {
		Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit, Player = player,
		Behaviour = mod, _alive = true, _conns = {}, _insts = {}, _cleanups = {}, StepRange = mod.StepRange or DEFAULT_STEP_RANGE,
	}
	function ctx:Alive() return self._alive and model.Parent ~= nil end
	function ctx:Connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(self._conns, c)
		return c
	end
	function ctx:Add(inst)
		table.insert(self._insts, inst)
		return inst
	end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute(Kit.STATE_PREFIX .. k) end
	--.. fn(value) now and whenever Fun_<k> changes
	function ctx:OnState(k, fn)
		local name = Kit.STATE_PREFIX .. k
		self:Connect(model:GetAttributeChangedSignal(name), function() fn(model:GetAttribute(name)) end)
		task.spawn(fn, model:GetAttribute(name))
	end
	function ctx:Send(action, payload) Remote:FireServer(model, action, payload) end
	--.. the camera's distance to the build
	function ctx:CameraDistance()
		local hitbox = Kit.Hitbox(model)
		local cam = workspace.CurrentCamera
		if not hitbox or not cam then return math.huge end
		return (cam.CFrame.Position - hitbox.Position).Magnitude
	end
	--.. fn(dt, now) every frame (RenderStepped; Heartbeat while Studio is unfocused and render stops), asleep
	--.. while the camera is farther than ctx.StepRange from the build. now = server time
	function ctx:Step(fn)
		local last = 0
		local function run(dt)
			local t = os.clock()
			if t - last < 0.004 then return end -- RenderStepped + Heartbeat both fire: run once per frame
			last = t
			if self:CameraDistance() > self.StepRange then return end
			local ok, err = pcall(fn, dt, Kit.Now())
			if not ok then warn("[FunBuildClient] " .. tostring(key) .. " Step: " .. tostring(err)) end
		end
		self:Connect(RunService.RenderStepped, run)
		self:Connect(RunService.Heartbeat, run)
	end
	function ctx:Every(seconds, fn)
		task.spawn(function()
			while true do
				task.wait(seconds)
				if not self:Alive() then return end
				local ok, err = pcall(fn)
				if not ok then warn("[FunBuildClient] " .. tostring(key) .. " Every: " .. tostring(err)) end
			end
		end)
	end
	function ctx:Sound(parent, nameOrId, props)
		local s = Kit.MakeSound(nameOrId, props)
		s.Parent = parent
		self:Add(s)
		return s
	end
	--.. a local-only helper Part (visual effects): anchored, non-colliding, parented to workspace.CurrentCamera's sibling folder
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = workspace.CurrentCamera end
		self:Add(p)
		return p
	end
	function ctx:LocalCharacter()
		local humanoid, root = Kit.CharacterParts(player.Character)
		if humanoid and humanoid.Health > 0 and root then return humanoid, root, player.Character end
		return nil
	end
	--.. is the local character within dist studs of the build's hitbox?
	function ctx:Near(dist)
		local _, root = self:LocalCharacter()
		local hitbox = Kit.Hitbox(model)
		return root ~= nil and hitbox ~= nil and (root.Position - hitbox.Position).Magnitude <= dist
	end
	function ctx:IsOwner() return player.UserId == model:GetAttribute("Owner") end
	return ctx
end

local function Stop(model)
	local ctx = Running[model]
	if not ctx then return end
	Running[model] = nil
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		if not ok then warn("[FunBuildClient] cleanup " .. tostring(ctx.Key) .. ": " .. tostring(err)) end
	end
	for _, c in ipairs(ctx._conns) do c:Disconnect() end
	for i = #ctx._insts, 1, -1 do
		local inst = ctx._insts[i]
		if typeof(inst) == "Instance" then inst:Destroy() end
	end
end

local function Start(model)
	if Running[model] then return end
	if not (model:IsA("Model") and model:IsDescendantOf(workspace)) then return end
	if Kit.IsBroken(model) or not Kit.Hitbox(model) then return end
	local mod = BehaviourOf(Kit.Key(model))
	if not mod then return end
	local ctx = NewContext(model, mod)
	Running[model] = ctx
	local ok, result = pcall(mod.Client, model, ctx)
	if not ok then
		warn("[FunBuildClient] " .. tostring(ctx.Key) .. " Client(): " .. tostring(result))
	elseif type(result) == "function" then
		ctx:OnCleanup(result)
	end
end

local Watched = {}
local function Watch(model)
	if Watched[model] or not model:IsA("Model") then return end
	if not model:IsDescendantOf(workspace) then return end
	--.. the BuildKey attribute and the Hitbox may land a moment after the tag while streaming
	if not Kit.Key(model) or not Kit.Hitbox(model) then
		local t0 = os.clock()
		while (not Kit.Key(model) or not Kit.Hitbox(model)) and os.clock() - t0 < 10 and model.Parent do task.wait(0.1) end
	end
	if Watched[model] or not BehaviourOf(Kit.Key(model)) then return end
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local conns = {}
	Watched[model] = conns
	local pending = false
	local function queue()
		if pending then return end
		pending = true
		task.delay(0.3, function()
			pending = false
			if Watched[model] then Stop(model) Start(model) end
		end)
	end
	table.insert(conns, hitbox:GetPropertyChangedSignal("CFrame"):Connect(queue))
	table.insert(conns, model:GetAttributeChangedSignal("Broken"):Connect(queue))
	table.insert(conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			Stop(model)
			for _, c in ipairs(conns) do c:Disconnect() end
			Watched[model] = nil
		end
	end))
	Start(model)
end

local function Unwatch(model)
	Stop(model)
	local conns = Watched[model]
	if conns then
		for _, c in ipairs(conns) do c:Disconnect() end
		Watched[model] = nil
	end
end

CollectionService:GetInstanceAddedSignal(Kit.PLACED_TAG):Connect(function(model) task.spawn(Watch, model) end)
CollectionService:GetInstanceRemovedSignal(Kit.PLACED_TAG):Connect(Unwatch)
for _, model in ipairs(CollectionService:GetTagged(Kit.PLACED_TAG)) do task.spawn(Watch, model) end
if folder then
	folder.ChildAdded:Connect(function(m)
		Load(m)
		for _, model in ipairs(CollectionService:GetTagged(Kit.PLACED_TAG)) do task.spawn(Watch, model) end
	end)
end

--..Server events..--
if Remote then
	Remote.OnClientEvent:Connect(function(model, action, payload)
		local ctx = Running[model]
		if not ctx then return end
		local handler = ctx.Behaviour.OnEvent
		if type(handler) ~= "function" then return end
		local ok, err = pcall(handler, model, action, payload, ctx)
		if not ok then warn("[FunBuildClient] " .. tostring(ctx.Key) .. " OnEvent " .. tostring(action) .. ": " .. tostring(err)) end
	end)
end

--..Build mode hides every functional-build prompt..--
local function InBuildMode()
	local hud = playerGui:FindFirstChild(HUD_NAME)
	return hud ~= nil and hud:GetAttribute("BuildMode") == true
end
local function SyncPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then return end
	if InBuildMode() then
		if prompt:GetAttribute("FunHidden") ~= true and prompt.Enabled then
			prompt:SetAttribute("FunHidden", true)
			prompt.Enabled = false
		end
	elseif prompt:GetAttribute("FunHidden") == true then
		prompt:SetAttribute("FunHidden", nil)
		prompt.Enabled = true
	end
end
local function SyncAllPrompts()
	for _, prompt in ipairs(CollectionService:GetTagged(Kit.PROMPT_TAG)) do SyncPrompt(prompt) end
end
CollectionService:GetInstanceAddedSignal(Kit.PROMPT_TAG):Connect(SyncPrompt)
task.spawn(function()
	local hud = playerGui:WaitForChild(HUD_NAME, 60)
	if hud then
		hud:GetAttributeChangedSignal("BuildMode"):Connect(SyncAllPrompts)
		SyncAllPrompts()
	end
end)

--..Lying seats: straighten the occupant every frame (after the Animator has posed it)..--
local LIE_FLEX = { -- joint name -> extra pose while lying (applied as the joint Transform); everything else goes straight
	LeftShoulder = CFrame.Angles(0, 0, math.rad(-8)), RightShoulder = CFrame.Angles(0, 0, math.rad(8)),
	LeftHip = CFrame.Angles(0, 0, math.rad(3)), RightHip = CFrame.Angles(0, 0, math.rad(-3)),
	Neck = CFrame.Angles(math.rad(-12), 0, 0),
}
local LieSeats = {} -- [seat] = true
local function TrackSeat(seat)
	if seat:IsA("Seat") and seat:GetAttribute(Kit.LIE_ATTR) == true then LieSeats[seat] = true end
end
local runtime = workspace:WaitForChild(Kit.RUNTIME_FOLDER, 30)
if runtime then
	for _, d in ipairs(runtime:GetDescendants()) do TrackSeat(d) end
	runtime.DescendantAdded:Connect(TrackSeat)
	runtime.DescendantRemoving:Connect(function(d) LieSeats[d] = nil end)
end
RunService.Stepped:Connect(function()
	for seat in pairs(LieSeats) do
		if not seat.Parent then
			LieSeats[seat] = nil
		else
			local humanoid = seat.Occupant
			local character = humanoid and humanoid.Parent
			if character then
				for joint in pairs(Kit.Joints(character)) do
					local name = joint.Name
					if name ~= "Root" and name ~= "RootJoint" then
						joint.Transform = LIE_FLEX[name] or CFrame.identity
					end
				end
			end
		end
	end
end)

print("[FunBuildClient] ready")
]=],
	WMServer = [=[
--[[
	WashingMachine  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the WORKING WASHING MACHINE, and through Make() of the DRYER (ServerStorage.FunBehaviours.Dryer
	is `require(script.Parent.WashingMachine).Make("Dryer")`). fun-builds/CONTRACT.md; models =
	fun-builds/models/build_WashingMachine.py / build_Dryer.py (+ laundrylib.py), notes = fun-builds/notes/HomeLaundry.md.
	  * "Start" prompt (E) in front of the console screen (Pivot_StartPrompt): runs one CYCLE-second programme.
	    State CycleEnd = the server time (Kit.Now) the cycle ends, 0 while idle; the client half plays the whole
	    programme (drum, clothes, water / lint, shake, countdown, sounds) from it, so every client shows the same
	    moment. While a cycle runs the prompt reads "Stop" and ends it early. Starting shuts an open door first.
	  * "Open door" / "Close door" prompt (F) on the porthole (Pivot_DoorPrompt), idle only (mid-cycle it reads
	    "Door locked" and presses do nothing; it stays Enabled so build mode's hide is never undone):
	    state Door (true = open). The client swings the Door* parts about Pivot_DoorHinge.
	  * test hook: model:SetAttribute("LaundryPress", "Start" | "Door") on the server presses that prompt (a Studio
	    playtest can't fire a ProximityPrompt from Luau); the attribute clears itself.
	Anyone may use it (nothing to grief, no economy). Nothing here moves a part: the server only keeps state.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local CYCLE = 15              -- seconds; keep in step with the client half
local PRESS_DEBOUNCE = 0.6    -- seconds between two presses of one prompt
local PROMPT_DISTANCE = 9     -- studs (the framework's prompts are drawn by CucumberPromptClient)
local KINDS = {
	Washer = {Object = "Washing Machine"},
	Dryer = {Object = "Dryer"},
}

--..Helpers..--
--.. a prompt on `part`, floating at the authored pivot `pivotName` (or on the part's centre without it)
local function PromptAt(model, ctx, part, pivotName, opts)
	local at = Kit.Pivot(model, pivotName)
	if at then opts.Offset = part.CFrame:PointToObjectSpace(at) end
	return ctx:Prompt(part, opts)
end

--..Behaviour..--
local function Make(kind)
	local cfg = KINDS[kind] or KINDS.Washer
	local B = {}
	B.ActionRange = 30

	function B.Server(model, ctx)
		local hitbox = Kit.Hitbox(model)
		local panel = Kit.Part(model, "Panel") or hitbox
		local front = Kit.Part(model, "FrontTop") or panel
		ctx:SetState("CycleEnd", 0)
		ctx:SetState("Door", false)

		local startPrompt = PromptAt(model, ctx, panel, "StartPrompt", {
			Action = "Start",
			Object = cfg.Object,
			Name = "StartPrompt",
			Distance = PROMPT_DISTANCE,
		})
		local doorPrompt = PromptAt(model, ctx, front, "DoorPrompt", {
			Action = "Open door",
			Object = cfg.Object,
			Name = "DoorPrompt",
			Distance = PROMPT_DISTANCE,
			Key = Enum.KeyCode.F,
			Gamepad = Enum.KeyCode.ButtonY,
		})

		local token = 0 -- bumps on every start / stop, so a stale end-of-cycle timer does nothing
		local function Running()
			return (tonumber(ctx:GetState("CycleEnd")) or 0) > Kit.Now()
		end
		--.. never toggle a prompt's Enabled here: it replicates and would undo FunBuildClient's build-mode hide (a cycle
		--.. ending while a player is in build mode would bring the prompt back for them). PressDoor ignores presses mid-cycle.
		local function Refresh()
			local running = Running()
			startPrompt.ActionText = running and "Stop" or "Start"
			if running then
				doorPrompt.ActionText = "Door locked"
			else
				doorPrompt.ActionText = ctx:GetState("Door") == true and "Close door" or "Open door"
			end
		end
		local function Finish(my)
			if not ctx:Alive() or token ~= my then return end
			ctx:SetState("CycleEnd", 0)
			Refresh()
		end

		--..Start / Stop..--
		local lastStart, lastDoor = 0, 0
		local function PressStart()
			local now = os.clock()
			if now - lastStart < PRESS_DEBOUNCE then return end
			lastStart = now
			token += 1
			if Running() then
				ctx:SetState("CycleEnd", 0) -- stopped early (the client clicks instead of dinging)
			else
				if ctx:GetState("Door") == true then ctx:SetState("Door", false) end
				ctx:SetState("CycleEnd", Kit.Now() + CYCLE)
				task.delay(CYCLE, Finish, token)
			end
			Refresh()
		end

		--..Door (idle only)..--
		local function PressDoor()
			local now = os.clock()
			if now - lastDoor < PRESS_DEBOUNCE or Running() then return end
			lastDoor = now
			ctx:SetState("Door", ctx:GetState("Door") ~= true)
			Refresh()
		end

		ctx:Connect(startPrompt.Triggered, function(player)
			if ctx:HumanoidOf(player) then PressStart() end
		end)
		ctx:Connect(doorPrompt.Triggered, function(player)
			if ctx:HumanoidOf(player) then PressDoor() end
		end)

		--..Test hook (server-side only; clients can't set it): model:SetAttribute("LaundryPress", "Start" | "Door")..--
		ctx:Connect(model:GetAttributeChangedSignal("LaundryPress"), function()
			local what = model:GetAttribute("LaundryPress")
			if what == nil then return end
			model:SetAttribute("LaundryPress", nil)
			if what == "Start" then PressStart() elseif what == "Door" then PressDoor() end
		end)

		Refresh()
	end

	return B
end

local M = Make("Washer")
M.Make = Make
M.CYCLE = CYCLE
return M
]=],
	DryerServer = [=[
--[[
	Dryer  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the WORKING TUMBLE DRYER: the washing machine's engine with the dryer's name on the prompts.
	Everything (the "Start" / "Stop" prompt -> state CycleEnd, the "Open door" / "Close door" prompt -> state Door)
	lives in the sibling module ServerStorage.FunBehaviours.WashingMachine - see its header and
	fun-builds/notes/HomeLaundry.md.
]]
local Washer = require(script.Parent:WaitForChild("WashingMachine", 10))
return Washer.Make("Dryer")
]=],
	WMClient = [=[
--[[
	WashingMachine  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the WORKING WASHING MACHINE, and through Make() of the DRYER (ReplicatedStorage.FunBehavioursClient.Dryer
	is `require(script.Parent.WashingMachine).Make("Dryer")`). Server half: ServerStorage.FunBehaviours.WashingMachine.
	fun-builds/CONTRACT.md; models = fun-builds/models/build_WashingMachine.py / build_Dryer.py (+ laundrylib.py).
	  * state CycleEnd (server time the CYCLE-second programme ends, 0 = idle): every client plays the same moment of
	    the programme from Kit.Now()
	      washer: FILL (blue water rises behind the glass) -> WASH (the drum turns one way, stops, turns back; the clothes
	              ride up the wall and tumble down; the water sloshes; suds) -> DRAIN -> SPIN (fast, clothes pinned to
	              the wall, the machine shakes hardest) -> Ding + a sparkle burst off the glass, the screen says DONE
	      dryer:  the drum turns steadily one way, clothes tumble from high up, a warm glow inside, warm lint puffs out
	              of the side vent while its louvres flutter open -> COOL -> Ding
	    all cycle long the whole machine jiggles (tiny smoothed-noise offsets on every part about its feet - the Hitbox
	    never moves), the Screen counts down (a SurfaceGui adorned to it, in PlayerGui), the timer dial winds up and
	    runs back to zero, the LED pulses and FunAssets.Sfx.WasherLoop hums near it (pitched with the drum speed)
	  * state Door (true = open): the Door* parts swing about Pivot_DoorHinge's vertical axis with a little bounce,
	    and shut with a thunk
	Rest poses come from the build's template (ReplicatedStorage.PlaceableBuilds) relative to its Hitbox, and every part
	is posed relative to the Hitbox each frame (one BulkMoveTo), so a MOVE / sale / break / stream-out mid-cycle is safe:
	cleanup puts every part back where it belongs and restores the Water (size, transparency) and the Led colour.
	The porthole (DoorGlass) must not be Roblox Glass, which hides the Water / suds behind it: it is authored SmoothPlastic,
	and a copy still made of Glass (an older install) is drawn SmoothPlastic while the behaviour runs.
	Clothes that tumble land back near their own authored angle, and slide down when the drum stops with them high up.
	Particle textures are the engine's built-in rbxasset:// ones (no asset ids).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local CYCLE = 15                       -- seconds; keep in step with the server half
local STEP_RANGE = 150                 -- studs camera <-> machine: the per-frame work sleeps beyond this
local FX_RANGE = 120                   -- particles, the done sparkle + ding
local SHAKE_RANGE = 90                 -- the jiggle (it moves every part: only worth it up close)
local NEAR_SOUND = 55                  -- the hum / water loops only play within this
local DOOR_OPEN = math.rad(-105)       -- about the hinge's vertical axis: negative swings the door out toward the front
local DOOR_K, DOOR_C = 70, 8.5         -- door spring (stiffness, damping): a small bounce open, a thunk shut
local DIAL_WIND = math.rad(-150)       -- the timer dial winds to here at the start and runs back to 0 by the end
local BUTTON_SINK = 0.05               -- authored studs the start button sinks when pressed
local PIN_SPEED = 9                    -- rad/s: faster than this the clothes stay pinned to the drum wall
local FALL_TIME = 0.42                 -- seconds a cloth takes to tumble from high up back to the bottom
local LAND_JITTER = 0.3                -- rad: a cloth lands within this of its own authored angle
local SETTLE = 1.25                    -- rad from the bottom: higher than this when the drum stops, a cloth slides down
local SHAKE_MOVE = 0.08                -- studs (x Scale) of the jiggle at full strength (noise is about +-0.5 of it)
local SHAKE_TILT = math.rad(1.1)       -- tilt about the feet at full strength
local DONE_SHOW = 3                    -- seconds the screen blinks DONE
local WATER_SHOWN = 0.42               -- Water transparency while there is water in the drum
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local TAU = 2 * math.pi

--..Programmes (t = seconds into the cycle)..--
local function Smooth(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

--.. washer timeline
local FILL = 1.4                       -- water in over 0..FILL
local WASH0, HALF = 0.6, 2.2           -- agitation starts at WASH0; the drum reverses every HALF seconds
local WASH1 = WASH0 + 4 * HALF         -- 9.4: two back-and-forths, ends at rest
local SPIN0, SPIN_UP, SPIN1, SPIN_DOWN = 10.6, 1.2, 13.8, 0.8
local AGITATE, SPIN = 4.2, 22          -- rad/s
--.. dryer timeline
local DRY, DRY_UP, COOL0, DRY_DOWN0, DRY_DOWN1 = 4.4, 1.2, 11.5, 13.4, 14.6

local KINDS = {
	Washer = {
		Water = true,
		Screen = Color3.fromRGB(95, 225, 255),
		LedOn = Color3.fromRGB(69, 255, 0),
		Lamp = Color3.fromRGB(175, 225, 255),
		LampBrightness = 1.1,
		Sparkle = ColorSequence.new(Color3.fromRGB(200, 245, 255), Color3.fromRGB(120, 200, 255)),
		IdleWord = "WASH",
		DoneWord = "CLEAN!",
		LiftMin = 1.45, LiftMax = 1.9,  -- radians up the wall before a cloth drops
		LoopVolume = 0.34,
		LoopSfx = {"WasherLoop", "HumLoop"}, -- FunAssets.Sfx names, first one that exists
		Omega = function(t)
			if t < WASH0 then return 0 end
			if t < WASH1 then return AGITATE * math.sin(math.pi * (t - WASH0) / HALF) end
			if t < SPIN0 then return 0 end
			if t < SPIN0 + SPIN_UP then return SPIN * Smooth((t - SPIN0) / SPIN_UP) end
			if t < SPIN1 then return SPIN end
			if t < SPIN1 + SPIN_DOWN then return SPIN * (1 - Smooth((t - SPIN1) / SPIN_DOWN)) end
			return 0
		end,
		Level = function(t)
			if t < WASH1 then return Smooth(t / FILL) end
			return 1 - Smooth((t - WASH1) / (SPIN0 - WASH1))
		end,
		Pouring = function(t)
			return t < FILL or (t >= WASH1 and t < SPIN0)
		end,
		Suds = function(t)
			return t >= FILL and t < WASH1
		end,
		Phase = function(t)
			if t < WASH0 then return "FILL" elseif t < WASH1 then return "WASH" elseif t < SPIN0 then return "DRAIN" end
			return "SPIN"
		end,
		Shake = function(t, w)
			if t >= SPIN0 then return 0.2 + 0.8 * math.abs(w) / SPIN end
			return 0.3 + 0.3 * math.abs(w) / AGITATE
		end,
		Heat = function()
			return 0
		end,
		Pitch = function(w)
			return 0.8 + 0.55 * math.min(1, math.abs(w) / SPIN) + 0.08 * math.min(1, math.abs(w) / AGITATE)
		end,
	},
	Dryer = {
		Lint = true,
		Screen = Color3.fromRGB(255, 176, 70),
		LedOn = Color3.fromRGB(255, 140, 40),
		Lamp = Color3.fromRGB(255, 165, 85),
		LampBrightness = 1.4,
		Sparkle = ColorSequence.new(Color3.fromRGB(255, 240, 190), Color3.fromRGB(255, 190, 110)),
		IdleWord = "DRY",
		DoneWord = "FLUFFY!",
		LiftMin = 1.9, LiftMax = 2.45,  -- a dryer carries the clothes nearly to the top before they drop
		LoopVolume = 0.28,
		LoopSfx = {"DryerLoop", "WasherLoop"}, -- DryerLoop is a wish (notes); WasherLoop until it exists
		Omega = function(t)
			if t < DRY_UP then return DRY * Smooth(t / DRY_UP) end
			if t < DRY_DOWN0 then return DRY end
			if t < DRY_DOWN1 then return DRY * (1 - Smooth((t - DRY_DOWN0) / (DRY_DOWN1 - DRY_DOWN0))) end
			return 0
		end,
		Phase = function(t)
			return t < COOL0 and "DRY" or "COOL"
		end,
		Shake = function(_t, w)
			return 0.15 + 0.2 * math.abs(w) / DRY
		end,
		Heat = function(t) -- warm glow, lint, open louvres 0..1
			if t < COOL0 then return Smooth(t / 1.5) end
			return 1 - Smooth((t - COOL0) / 2)
		end,
		Pitch = function(w)
			return 0.7 + 0.12 * math.min(1, math.abs(w) / DRY)
		end,
	},
}

--..Helpers..--
local function Wrap(a)
	return (a + math.pi) % TAU - math.pi
end

--.. Seq(t0, v0, t1, v1, ...) -> NumberSequence
local function Seq(...)
	local args = {...}
	local points = {}
	for i = 1, #args, 2 do table.insert(points, NumberSequenceKeypoint.new(args[i], args[i + 1])) end
	return NumberSequence.new(points)
end

local function Emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

local function Attach(parent, name, cf)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end

local function Sfx(name, fallback)
	return FunAssets.Sfx[name] or FunAssets.Sfx[fallback] or "Click Sound"
end

--.. the build's template (ReplicatedStorage.PlaceableBuilds/<Category>/<Key>)
local function TemplateOf(model)
	local root = ReplicatedStorage:FindFirstChild("PlaceableBuilds")
	if not root then return nil end
	local key = tostring(Kit.Key(model))
	local category = root:FindFirstChild(tostring(model:GetAttribute("Category")))
	local template = category and category:FindFirstChild(key)
	if not template then
		for _, c in ipairs(root:GetChildren()) do
			template = c:FindFirstChild(key)
			if template then break end
		end
	end
	return template
end

--.. [part name] = {CFrame (template Hitbox space), Size, Transparency, Color} as shipped, or nil (then the placed
--.. copy's current values are used). Skipped when the template was re-scaled since this copy was placed.
local function Shipped(model)
	local template = TemplateOf(model)
	local hitbox = template and Kit.Hitbox(template)
	if not hitbox or math.abs(Kit.Scale(template) - Kit.Scale(model)) > 1e-3 then return nil end
	local map = {}
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("BasePart") and d ~= hitbox then
			map[d.Name] = {CFrame = hitbox.CFrame:ToObjectSpace(d.CFrame), Size = d.Size, Transparency = d.Transparency, Color = d.Color}
		end
	end
	return map
end

--..Screen (a SurfaceGui on the Screen part's Front face)..--
local function BuildScreen(screen, K, playerGui)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LaundryScreen"
	gui.Adornee = screen
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.MaxDistance = 80
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local bg = Instance.new("Frame")
	bg.Name = "Glass"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = K.Screen:Lerp(Color3.new(0, 0, 0), 0.9)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local function Label(name, pos, size, align)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = pos
		l.Size = size
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = K.Screen
		l.TextXAlignment = align or Enum.TextXAlignment.Center
		l.Text = ""
		l.Parent = bg
		return l
	end
	local big = Label("Time", UDim2.fromScale(0.06, 0.05), UDim2.fromScale(0.88, 0.56))
	local small = Label("Phase", UDim2.fromScale(0.07, 0.63), UDim2.fromScale(0.52, 0.3), Enum.TextXAlignment.Left)

	local barBack = Instance.new("Frame")
	barBack.Name = "Bar"
	barBack.Position = UDim2.fromScale(0.62, 0.71)
	barBack.Size = UDim2.fromScale(0.31, 0.14)
	barBack.BackgroundColor3 = K.Screen:Lerp(Color3.new(0, 0, 0), 0.7)
	barBack.BorderSizePixel = 0
	barBack.Parent = bg
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = K.Screen
	fill.BorderSizePixel = 0
	fill.Parent = barBack

	gui.Parent = playerGui
	return gui, big, small, fill
end

--..Behaviour..--
local function Make(kindName)
	local K = KINDS[kindName] or KINDS.Washer
	local B = {}
	B.StepRange = STEP_RANGE

	function B.Client(model, ctx)
		local s = ctx.Scale
		local hitbox = Kit.Hitbox(model)
		if not hitbox then return end
		local hb0 = hitbox.CFrame
		local origin = Kit.Origin(model)
		local floorH = hb0:ToObjectSpace(origin) -- the authored floor centre + axes, in Hitbox space
		local axesH = floorH.Rotation

		--..Parts + rest poses (Hitbox space)..--
		local shipped = Shipped(model)
		local parts, rest, byName, restInfo = {}, {}, {}, {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= hitbox then
				table.insert(parts, d)
				byName[d.Name] = d
				local t = shipped and shipped[d.Name]
				rest[d] = t and t.CFrame or hb0:ToObjectSpace(d.CFrame)
				restInfo[d] = {Size = t and t.Size or d.Size, Transparency = t and t.Transparency or d.Transparency, Color = t and t.Color or d.Color}
			end
		end
		if #parts == 0 then return end

		--..Pivots (Hitbox space, authored axes)..--
		local function PivotH(name)
			local p = Kit.Pivot(model, name)
			return p and hb0:ToObjectSpace(CFrame.new(p) * origin.Rotation) or nil
		end
		local drumH, hingeH, dialH = PivotH("Drum"), PivotH("DoorHinge"), PivotH("Dial")
		if not (drumH and hingeH) then
			warn("[" .. kindName .. "] " .. model:GetFullName() .. " lacks Pivot_Drum / Pivot_DoorHinge - drum or door stays still")
		end

		--..Groups..--
		local drum, door, dial, cloths, slats, light = {}, {}, {}, {}, {}, {}
		for _, p in ipairs(parts) do
			local n = p.Name
			if drumH and n:sub(1, 9) == "DrumCloth" then
				local rel = drumH:ToObjectSpace(rest[p])
				local pos = rel.Position
				local a0 = math.atan2(pos.X, -pos.Y) -- authored angle from the drum bottom
				table.insert(cloths, {
					Part = p, Rel = rel, A0 = a0, Phi = 0,
					Lift = K.LiftMin + math.random() * (K.LiftMax - K.LiftMin),
					Settle = math.max(SETTLE, math.abs(a0) + LAND_JITTER + 0.05), -- never above where it lands (no loop)
				})
			elseif drumH and n:sub(1, 4) == "Drum" then
				table.insert(drum, {Part = p, Rel = drumH:ToObjectSpace(rest[p])})
			elseif hingeH and n:sub(1, 4) == "Door" then
				table.insert(door, {Part = p, Rel = hingeH:ToObjectSpace(rest[p])})
				table.insert(light, p)
			elseif dialH and (n == "DialKnob" or n == "DialCap" or n == "DialPointer") then
				table.insert(dial, {Part = p, Rel = dialH:ToObjectSpace(rest[p])})
				table.insert(light, p)
			elseif n:sub(1, 8) == "VentSlat" then
				table.insert(slats, p)
			end
		end
		local water = K.Water and byName.Water or nil
		local led = byName.Led
		local button = byName.ButtonStart
		if button then table.insert(light, button) end
		local screen = byName.Screen

		--.. Roblox's Glass material hides every transparent part / particle behind it (the Water, the suds): the porthole
		--.. is authored SmoothPlastic; a copy installed from an older export (Glass) is drawn SmoothPlastic here instead
		local doorGlass = byName.DoorGlass
		local glassWas = doorGlass and doorGlass.Material == Enum.Material.Glass and {Reflectance = doorGlass.Reflectance} or nil
		if glassWas then
			doorGlass.Material = Enum.Material.SmoothPlastic
			doorGlass.Reflectance = math.max(glassWas.Reflectance, 0.15)
		end

		--..Cleanup: every part back where it belongs (relative to where the build IS now)..--
		ctx:OnCleanup(function()
			if glassWas and doorGlass.Parent then
				doorGlass.Material = Enum.Material.Glass
				doorGlass.Reflectance = glassWas.Reflectance
			end
			if not hitbox.Parent then return end
			local hb = hitbox.CFrame
			local list, cfs = {}, {}
			for _, p in ipairs(parts) do
				if p.Parent then
					table.insert(list, p)
					table.insert(cfs, hb * rest[p])
				end
			end
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			if water and water.Parent then
				water.Size = restInfo[water].Size
				water.Transparency = restInfo[water].Transparency -- shipped invisible (1): the broken fade leaves it alone too
			end
			if led and led.Parent then led.Color = restInfo[led].Color end
		end)

		--..Effects host: an invisible local part at the drum centre (authored axes)..--
		local fxCF = drumH and hb0 * drumH or Kit.CFrameToWorld(model, CFrame.new(0, 1.78, -0.96))
		local fx = ctx:Part({Name = "LaundryFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = fxCF})
		local lamp = Instance.new("PointLight")
		lamp.Color = K.Lamp
		lamp.Range = 3.4 * s
		lamp.Brightness = 0
		lamp.Shadows = false
		lamp.Enabled = false
		lamp.Parent = Attach(fx, "Lamp", CFrame.new(0, 0.1 * s, -0.35 * s))

		local glass = Kit.Pivot(model, "DoorCentre")
		local sparkles = Emitter(Attach(fx, "Sparkle", CFrame.new(fx.CFrame:PointToObjectSpace(glass or fx.Position))), {
			Name = "Sparkles",
			Texture = TEX_SPARKLE,
			Color = K.Sparkle,
			Size = Seq(0, 0.35 * s, 1, 0),
			Transparency = Seq(0, 0, 0.7, 0.2, 1, 1),
			Lifetime = NumberRange.new(0.6, 1.0),
			Speed = NumberRange.new(3 * s, 5.5 * s),
			SpreadAngle = Vector2.new(55, 55),
			Acceleration = Vector3.new(0, -4, 0),
			Drag = 2,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-120, 120),
			LightEmission = 1,
			EmissionDirection = Enum.NormalId.Front, -- the attachment has the authored axes: Front = out of the glass
		})

		--.. washer: suds on the water surface
		local suds
		local waterTop = K.Water and Kit.Pivot(model, "WaterTop")
		if waterTop then
			local host = ctx:Part({
				Name = "LaundrySuds", Transparency = 1,
				Size = Vector3.new(1.2 * s, 0.05, 0.8 * s), CFrame = CFrame.new(waterTop) * origin.Rotation,
			})
			suds = Emitter(host, {
				Name = "Suds",
				Texture = TEX_RING,
				Color = ColorSequence.new(Color3.fromRGB(245, 252, 255)),
				Size = Seq(0, 0.08 * s, 1, 0.2 * s),
				Transparency = Seq(0, 0.2, 0.8, 0.3, 1, 1),
				Lifetime = NumberRange.new(0.35, 0.6),
				Rate = 12,
				Speed = NumberRange.new(0.2, 0.5),
				SpreadAngle = Vector2.new(30, 30),
				LightEmission = 0.3,
				ZOffset = 0.2,
				EmissionDirection = Enum.NormalId.Top,
				Shape = Enum.ParticleEmitterShape.Box,
				ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			})
		end

		--.. dryer: warm lint puffs + fluff flecks blowing out of the side vent
		local lint = {}
		if K.Lint then
			local vent, out = Kit.Pivot(model, "Vent"), Kit.Pivot(model, "VentOut")
			if vent and out and (out - vent).Magnitude > 1e-3 then
				local host = ctx:Part({Name = "LaundryVent", Transparency = 1, Size = Vector3.new(0.3, 0.3, 0.3) * s, CFrame = CFrame.lookAt(vent, out)})
				table.insert(lint, Emitter(host, {
					Name = "Puffs",
					Texture = TEX_SMOKE,
					Color = ColorSequence.new(Color3.fromRGB(255, 244, 228), Color3.fromRGB(238, 226, 214)),
					Size = Seq(0, 0.35 * s, 0.5, 1.0 * s, 1, 1.6 * s),
					Transparency = Seq(0, 0.35, 0.5, 0.6, 1, 1),
					Lifetime = NumberRange.new(1.2, 1.9),
					Rate = 6,
					Speed = NumberRange.new(2.2 * s, 3.4 * s),
					SpreadAngle = Vector2.new(18, 18),
					Acceleration = Vector3.new(0, 1.6 * s, 0),
					Drag = 1.4,
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-40, 40),
					LightEmission = 0.15,
					LightInfluence = 0.8,
					EmissionDirection = Enum.NormalId.Front, -- the host looks along the blow direction
				}))
				table.insert(lint, Emitter(host, {
					Name = "Fluff",
					Texture = TEX_SMOKE,
					Color = ColorSequence.new(Color3.fromRGB(250, 250, 255)),
					Size = Seq(0, 0.09 * s, 1, 0.07 * s),
					Transparency = Seq(0, 0.1, 0.8, 0.3, 1, 1),
					Lifetime = NumberRange.new(1.4, 2.2),
					Rate = 7,
					Speed = NumberRange.new(2.5 * s, 4 * s),
					SpreadAngle = Vector2.new(28, 28),
					Acceleration = Vector3.new(0, -1.2, 0),
					Drag = 2.2,
					RotSpeed = NumberRange.new(-200, 200),
					LightInfluence = 0.9,
					EmissionDirection = Enum.NormalId.Front,
				}))
			end
		end

		--..Sounds..--
		local loop = ctx:Sound(fx, Sfx(K.LoopSfx[1], K.LoopSfx[2]), {Name = "Hum", Looped = true, Volume = K.LoopVolume, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND})
		local pour = K.Water and ctx:Sound(fx, Sfx("WaterLoop", "Splash"), {Name = "Water", Looped = true, Volume = 0.26, RollOffMinDistance = 6, RollOffMaxDistance = 45}) or nil
		local ding = ctx:Sound(fx, Sfx("Ding", "Click"), {Name = "Ding", Volume = 0.6, RollOffMaxDistance = 80})
		local click = ctx:Sound(fx, Sfx("Click", "Click"), {Name = "Click", Volume = 0.45, RollOffMaxDistance = 40})
		local doorOpenSound = ctx:Sound(fx, Sfx("DoorOpen", "Click"), {Name = "DoorOpen", Volume = 0.45, RollOffMaxDistance = 40})
		local doorCloseSound = ctx:Sound(fx, Sfx("DoorClose", "Click"), {Name = "DoorClose", Volume = 0.5, PlaybackSpeed = 0.85, RollOffMaxDistance = 40})
		local function Play(sound, range)
			if sound and ctx:CameraDistance() <= (range or FX_RANGE) then
				sound.TimePosition = 0
				sound:Play()
			end
		end
		local function SetPlaying(sound, on)
			if not sound then return end
			if on and not sound.IsPlaying then sound:Play() elseif not on and sound.IsPlaying then sound:Stop() end
		end

		--..Screen..--
		local gui, bigLabel, smallLabel, barFill
		if screen then
			local playerGui = ctx.Player:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				gui, bigLabel, smallLabel, barFill = BuildScreen(screen, K, playerGui)
				ctx:Add(gui)
			end
		end

		--..State..--
		local cycleEnd, doorOpen = 0, false
		local doneFor, doneUntil, pressedAt = nil, 0, -10
		local theta, omega, doorAngle, doorVel, dialAngle = 0, 0, 0, 0, 0
		local shakeK, level, lastLevel, lampK, ventOpen = 0, 0, -1, 0, 0
		local dirty, wasBusy = false, false -- dirty: one full pose pass wanted (streamed in with the door open)
		local firstCycle, firstDoor = true, true
		local shown = {}

		local function Done(forEnd)
			doneFor = forEnd
			doneUntil = os.clock() + DONE_SHOW
			if ctx:CameraDistance() <= FX_RANGE then
				Play(ding)
				sparkles:Emit(16)
			end
		end

		local function Clock(now)
			local t = now - (cycleEnd - CYCLE)
			return t, cycleEnd > 0 and t >= 0 and t < CYCLE
		end

		--.. loops + particles on / off (every few tenths of a second, not per frame)
		local function SyncAudio()
			local t, running = Clock(Kit.Now())
			local near = ctx:CameraDistance() <= NEAR_SOUND
			local inFx = ctx:CameraDistance() <= FX_RANGE
			SetPlaying(loop, running and near)
			if pour then SetPlaying(pour, running and near and K.Pouring(t)) end
			if suds then
				local on = running and inFx and K.Suds(t)
				if suds.Enabled ~= on then suds.Enabled = on end
			end
			local heat = running and K.Heat(t) or 0
			for _, e in ipairs(lint) do
				local on = heat > 0.3 and inFx
				if e.Enabled ~= on then e.Enabled = on end
			end
		end

		ctx:OnState("CycleEnd", function(value)
			local v = tonumber(value) or 0
			if not firstCycle then
				if v > 0 and v ~= cycleEnd then
					pressedAt = os.clock()
					Play(click, 45)
				elseif v == 0 and cycleEnd > 0 then
					if Kit.Now() < cycleEnd - 0.3 then
						pressedAt = os.clock()
						Play(click, 45) -- stopped early
					elseif doneFor ~= cycleEnd then
						Done(cycleEnd) -- ended while this client's per-frame step was asleep
					end
				end
			end
			firstCycle = false
			cycleEnd = v
			if v > 0 then doneUntil = 0 end
			SyncAudio()
		end)

		ctx:OnState("Door", function(value)
			local open = value == true
			if firstDoor then
				doorAngle, doorVel = open and DOOR_OPEN or 0, 0 -- streamed in: snap (one pose pass if it is open)
				dirty = open
			elseif open ~= doorOpen then
				Play(open and doorOpenSound or doorCloseSound, 50)
			end
			firstDoor = false
			doorOpen = open
		end)

		ctx:Every(0.3, SyncAudio)

		--..Screen + LED (cheap: only writes what changed)..--
		local function Set(inst, prop, value)
			local key = inst.Name .. prop
			if shown[key] ~= value then
				shown[key] = value
				inst[prop] = value
			end
		end
		local function UpdateScreen(t, running)
			if not gui then return end
			local big, small, bar, alpha
			if running then
				local left = math.clamp(math.ceil(CYCLE - t), 0, 99)
				big = string.format("%d:%02d", math.floor(left / 60), left % 60)
				small = K.Phase(t)
				bar = math.clamp(t / CYCLE, 0, 1)
				alpha = 0
			elseif os.clock() < doneUntil then
				big = "DONE"
				small = K.DoneWord
				bar = 1
				alpha = (math.floor(os.clock() * 3) % 2 == 0) and 0 or 0.6
			else
				big = doorOpen and "OPEN" or "READY"
				small = K.IdleWord
				bar = 0
				alpha = 0.4
			end
			Set(bigLabel, "Text", big)
			Set(smallLabel, "Text", small)
			Set(bigLabel, "TextTransparency", alpha)
			Set(smallLabel, "TextTransparency", math.min(1, alpha + 0.15))
			Set(barFill, "Size", UDim2.fromScale(math.floor(bar * 40 + 0.5) / 40, 1))
		end
		local ledRest = led and restInfo[led].Color
		local function UpdateLed(running)
			if not led then return end
			local c = ledRest
			if running then
				c = K.LedOn:Lerp(Color3.new(1, 1, 1), 0.3 * (0.5 + 0.5 * math.sin(os.clock() * 5)))
			elseif os.clock() < doneUntil then
				c = (math.floor(os.clock() * 4) % 2 == 0) and K.LedOn or ledRest
			end
			if led.Color ~= c then led.Color = c end
		end

		--..Per frame..--
		local cfsAll, cfsLight = {}, {}
		ctx:Step(function(dt, now)
			if not hitbox.Parent then return end
			dt = math.min(dt, 0.05)
			local t, running = Clock(now)
			if cycleEnd > 0 and now >= cycleEnd and doneFor ~= cycleEnd then Done(cycleEnd) end
			UpdateScreen(t, running)
			UpdateLed(running)

			--.. drum speed: the programme while running, a quick spin-down after a stop
			if running then
				omega = K.Omega(t)
			else
				omega -= omega * math.min(1, dt * 3)
				if math.abs(omega) < 0.02 then omega = 0 end
			end
			theta = (theta + omega * dt) % TAU
			if loop.IsPlaying then loop.PlaybackSpeed = K.Pitch(omega) end

			--.. door spring (bounces open, thunks shut against the cabinet)
			local target = doorOpen and DOOR_OPEN or 0
			local doorBusy = math.abs(target - doorAngle) > 0.002 or math.abs(doorVel) > 0.01
			if doorBusy then
				doorVel += (DOOR_K * (target - doorAngle) - DOOR_C * doorVel) * dt
				doorAngle += doorVel * dt
				if doorAngle > 0 then doorAngle, doorVel = 0, 0 end
				if math.abs(target - doorAngle) <= 0.002 and math.abs(doorVel) <= 0.01 then doorAngle, doorVel = target, 0 end
			end

			--.. dial: winds up at the start, runs back with the time left
			local dialTarget = running and DIAL_WIND * (1 - t / CYCLE) or 0
			local dialBusy = math.abs(dialTarget - dialAngle) > 0.003
			if dialBusy then dialAngle += (dialTarget - dialAngle) * math.min(1, dt * 8) end
			local pressing = os.clock() - pressedAt < 0.3

			--.. clothes: ride up the wall with the drum, drop back through the middle (pinned when it spins fast)
			local pinned = math.abs(omega) >= PIN_SPEED
			local falling = false
			for _, c in ipairs(cloths) do
				if c.Fall then
					c.Fall.T += dt
					if c.Fall.T >= FALL_TIME then
						c.Phi = c.Fall.To
						c.Fall = nil
					end
				else
					c.Phi += omega * dt
					local a = Wrap(c.A0 + c.Phi) -- the cloth's angle from the drum bottom
					c.Phi = a - c.A0
					--.. carried past its lift it drops; with the drum still, one left high up the wall slides back down
					local limit = pinned and math.huge or (omega == 0 and c.Settle or c.Lift)
					if math.abs(a) > limit then
						--.. Phi is relative to the authored angle A0: land back near its own spot, so the clothes never pile up
						c.Fall = {T = 0, From = c.Phi, To = (math.random() - 0.5) * 2 * LAND_JITTER, Turn = (math.random() - 0.5) * 3}
					end
				end
				if c.Fall then falling = true end
			end

			--.. water level, shake, glow, louvres
			if water then
				if running then level = K.Level(t) else level -= level * math.min(1, dt * 2.5) end
				if level < 0.004 then level = 0 end
			end
			local wantShake = running and K.Shake(t, omega) or 0
			shakeK += (wantShake - shakeK) * math.min(1, dt * 5)
			if wantShake == 0 and shakeK < 0.004 then shakeK = 0 end
			local heat = running and K.Heat(t) or 0
			lampK += ((running and 1 or 0) * (K.Lint and (0.35 + 0.65 * heat) or 1) - lampK) * math.min(1, dt * 3)
			if lampK < 0.01 then lampK = 0 end
			lamp.Enabled = lampK > 0
			lamp.Brightness = K.LampBrightness * lampK
			ventOpen += (heat - ventOpen) * math.min(1, dt * 4)
			if heat == 0 and ventOpen < 0.003 then ventOpen = 0 end

			local busy = running or falling or shakeK > 0 or level > 0 or omega ~= 0 or ventOpen > 0
			if not (busy or wasBusy or doorBusy or dialBusy or pressing or dirty) then return end
			local full = busy or wasBusy or dirty
			wasBusy = busy
			dirty = false

			--..Poses (Hitbox space)..--
			local pose = {}
			if drumH then
				local d = drumH * CFrame.Angles(0, 0, theta)
				for _, g in ipairs(drum) do pose[g.Part] = d * g.Rel end
				for _, c in ipairs(cloths) do
					if c.Fall then
						local u = c.Fall.T / FALL_TIME
						local a = drumH * CFrame.Angles(0, 0, c.Fall.From) * c.Rel
						local b = drumH * CFrame.Angles(0, 0, c.Fall.To) * c.Rel
						pose[c.Part] = a:Lerp(b, u * u) * CFrame.Angles(0, 0, math.sin(math.pi * u) * c.Fall.Turn)
					else
						pose[c.Part] = drumH * CFrame.Angles(0, 0, c.Phi) * c.Rel
					end
				end
			end
			if water then
				local size = restInfo[water].Size
				if level > 0 then
					--.. the level rises / falls with the bottom held still; the surface tilts with the drum (slosh)
					local h = math.max(0.05, size.Y * level)
					local slosh = 0.16 * math.clamp(omega / AGITATE, -1, 1) + 0.03 * math.sin(os.clock() * 6)
					pose[water] = rest[water] * CFrame.new(0, -(size.Y - h) * 0.5, 0) * CFrame.Angles(0, 0, slosh)
					if math.abs(level - lastLevel) > 0.002 then
						lastLevel = level
						water.Size = Vector3.new(size.X, h, size.Z)
					end
					local tr = level > 0.01 and WATER_SHOWN or restInfo[water].Transparency
					if water.Transparency ~= tr then water.Transparency = tr end
				elseif lastLevel ~= 0 then
					--.. empty (or never filled): the shipped size, pose and (invisible) transparency
					lastLevel = 0
					water.Size = size
					water.Transparency = restInfo[water].Transparency
				end
			end
			if hingeH then
				local h = hingeH * CFrame.Angles(0, doorAngle, 0)
				for _, g in ipairs(door) do pose[g.Part] = h * g.Rel end
			end
			if dialH then
				local d = dialH * CFrame.Angles(0, 0, dialAngle)
				for _, g in ipairs(dial) do pose[g.Part] = d * g.Rel end
			end
			if button then
				local sink = pressing and math.sin(math.min(1, (os.clock() - pressedAt) / 0.3) * math.pi) * BUTTON_SINK * s or 0
				pose[button] = CFrame.new(axesH:VectorToWorldSpace(Vector3.new(0, 0, sink))) * rest[button]
			end
			for i, p in ipairs(slats) do
				local a = ventOpen * (0.7 + 0.12 * math.sin(os.clock() * 21 + i * 1.9))
				pose[p] = rest[p] * CFrame.Angles(0, 0, -a) -- the bottom edge swings out
			end

			--..Jiggle about the feet (never the Hitbox)..--
			local S
			if shakeK > 0 and ctx:CameraDistance() <= SHAKE_RANGE then
				local c = os.clock() * (7 + 9 * shakeK)
				local m = SHAKE_MOVE * s * shakeK
				local r = SHAKE_TILT * shakeK
				S = floorH
					* CFrame.new(math.noise(c, 0.5) * m, math.abs(math.noise(c, 4.5)) * m * 0.6, math.noise(c, 8.5) * m)
					* CFrame.Angles(math.noise(c, 12.5) * r, math.noise(c, 16.5) * r * 0.5, math.noise(c, 20.5) * r)
					* floorH:Inverse()
			end

			--..Move (one bulk call)..--
			local hb = hitbox.CFrame
			local list, cfs = parts, cfsAll
			if not full then list, cfs = light, cfsLight end
			for i, p in ipairs(list) do
				local cf = pose[p] or rest[p]
				cfs[i] = hb * (S and S * cf or cf)
			end
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	end

	return B
end

local M = Make("Washer")
M.Make = Make
M.CYCLE = CYCLE
return M
]=],
	DryerClient = [=[
--[[
	Dryer  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the WORKING TUMBLE DRYER: the washing machine's engine with the dryer's programme - the drum turns
	steadily one way with the clothes tumbling from high up, a warm glow inside, warm lint puffs + fluff out of the side
	vent (Pivot_Vent -> Pivot_VentOut) while VentSlat1..3 flutter open, a gentle jiggle, amber countdown, Ding.
	Everything lives in the sibling module ReplicatedStorage.FunBehavioursClient.WashingMachine (KINDS.Dryer) - see its
	header and fun-builds/notes/HomeLaundry.md.
]]
local Washer = require(script.Parent:WaitForChild("WashingMachine", 10))
return Washer.Make("Dryer")
]=],
}
local MODELS = {WashingMachine = {["key"] = "WashingMachine", ["parts"] = {{["name"] = "Foot1", ["shape"] = "Cylinder", ["size"] = {0.2, 0.36, 0.36}, ["cf"] = {1.3, 0.1, -1.22, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "23262c", ["material"] = "Rubber", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Foot2", ["shape"] = "Cylinder", ["size"] = {0.2, 0.36, 0.36}, ["cf"] = {-1.3, 0.1, -1.22, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "23262c", ["material"] = "Rubber", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Foot3", ["shape"] = "Cylinder", ["size"] = {0.2, 0.36, 0.36}, ["cf"] = {1.3, 0.1, 1.25, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "23262c", ["material"] = "Rubber", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Foot4", ["shape"] = "Cylinder", ["size"] = {0.2, 0.36, 0.36}, ["cf"] = {-1.3, 0.1, 1.25, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "23262c", ["material"] = "Rubber", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Plinth", ["shape"] = "Block", ["size"] = {3.26, 0.23, 3.08}, ["cf"] = {0.0, 0.285, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3b4350", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Body", ["shape"] = "Block", ["size"] = {3.38, 3.5, 1.94}, ["cf"] = {0.0, 2.13, 0.63, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "SideL", ["shape"] = "Block", ["size"] = {0.1, 3.5, 1.3}, ["cf"] = {1.65, 2.13, -0.95, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "EdgeL", ["shape"] = "Cylinder", ["size"] = {3.5, 0.14, 0.14}, ["cf"] = {1.66, 2.13, -1.585, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "SideR", ["shape"] = "Block", ["size"] = {0.1, 3.5, 1.3}, ["cf"] = {-1.65, 2.13, -0.95, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "EdgeR", ["shape"] = "Cylinder", ["size"] = {3.5, 0.14, 0.14}, ["cf"] = {-1.66, 2.13, -1.585, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Top", ["shape"] = "Block", ["size"] = {3.46, 0.14, 3.3}, ["cf"] = {0.0, 3.93, -0.02, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "TopEdge", ["shape"] = "Cylinder", ["size"] = {3.46, 0.14, 0.14}, ["cf"] = {0.0, 3.93, -1.67, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontTop", ["shape"] = "Block", ["size"] = {3.26, 0.44, 0.12}, ["cf"] = {0.0, 2.89, -1.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontBot", ["shape"] = "Block", ["size"] = {3.26, 0.5, 0.12}, ["cf"] = {0.0, 0.63, -1.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontL", ["shape"] = "Block", ["size"] = {0.73, 1.82, 0.12}, ["cf"] = {1.265, 1.78, -1.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontR", ["shape"] = "Block", ["size"] = {0.73, 1.82, 0.12}, ["cf"] = {-1.265, 1.78, -1.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontCorner1", ["shape"] = "Wedge", ["size"] = {0.12, 0.5272, 0.5272}, ["cf"] = {0.6364, 1.1436, -1.56, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontCorner2", ["shape"] = "Wedge", ["size"] = {0.12, 0.5272, 0.5272}, ["cf"] = {0.6364, 2.4164, -1.56, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontCorner3", ["shape"] = "Wedge", ["size"] = {0.12, 0.5272, 0.5272}, ["cf"] = {-0.6364, 2.4164, -1.56, -0.0, -0.0, -1.0, 0.0, -1.0, 0.0, -1.0, 0.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontCorner4", ["shape"] = "Wedge", ["size"] = {0.12, 0.5272, 0.5272}, ["cf"] = {-0.6364, 1.1436, -1.56, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0, -1.0, 0.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Panel", ["shape"] = "Block", ["size"] = {3.26, 0.76, 0.34}, ["cf"] = {0.0, 3.48, -1.47, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "e3e7ec", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "PanelTrim", ["shape"] = "Block", ["size"] = {3.36, 0.09, 0.17}, ["cf"] = {0.0, 3.07, -1.585, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3f79d4", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Drawer", ["shape"] = "Block", ["size"] = {0.72, 0.56, 0.08}, ["cf"] = {1.15, 3.48, -1.67, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "DrawerGrip", ["shape"] = "Block", ["size"] = {0.46, 0.08, 0.05}, ["cf"] = {1.15, 3.29, -1.715, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3b4350", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "ScreenBezel", ["shape"] = "Block", ["size"] = {0.86, 0.52, 0.06}, ["cf"] = {0.2, 3.48, -1.66, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "2c5aa8", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Screen", ["shape"] = "Block", ["size"] = {0.72, 0.4, 0.06}, ["cf"] = {0.2, 3.48, -1.69, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "1b2229", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Led", ["shape"] = "Cylinder", ["size"] = {0.06, 0.11, 0.11}, ["cf"] = {-0.42, 3.68, -1.66, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "2d5a2a", ["material"] = "Neon", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "ButtonStart", ["shape"] = "Cylinder", ["size"] = {0.07, 0.22, 0.22}, ["cf"] = {-0.42, 3.38, -1.67, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "5aa845", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DialRing", ["shape"] = "Cylinder", ["size"] = {0.06, 0.62, 0.62}, ["cf"] = {-1.02, 3.49, -1.655, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DialTick", ["shape"] = "Block", ["size"] = {0.06, 0.11, 0.05}, ["cf"] = {-1.02, 3.86, -1.65, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3b4350", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "DialKnob", ["shape"] = "Cylinder", ["size"] = {0.14, 0.46, 0.46}, ["cf"] = {-1.02, 3.49, -1.72, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "3f79d4", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DialCap", ["shape"] = "Cylinder", ["size"] = {0.06, 0.3, 0.3}, ["cf"] = {-1.02, 3.49, -1.8, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DialPointer", ["shape"] = "Block", ["size"] = {0.06, 0.15, 0.05}, ["cf"] = {-1.02, 3.565, -1.825, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "23262c", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "BadgePlate", ["shape"] = "Block", ["size"] = {0.7, 0.24, 0.05}, ["cf"] = {-1.02, 0.63, -1.635, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3f79d4", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "BadgeCuke", ["shape"] = "Ellipsoid", ["size"] = {0.44, 0.13, 0.05}, ["cf"] = {-1.02, 0.63, -1.66, 0.98481, -0.17365, 0.0, 0.17365, 0.98481, 0.0, 0.0, 0.0, 1.0}, ["color"] = "5aa845", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "HingePlate", ["shape"] = "Block", ["size"] = {0.22, 0.86, 0.05}, ["cf"] = {1.38, 1.78, -1.64, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "HingePin", ["shape"] = "Cylinder", ["size"] = {0.72, 0.13, 0.13}, ["cf"] = {1.36, 1.78, -1.72, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing01", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {1.00042, 1.979, -1.79, -0.19509, 0.0, 0.98079, 0.98079, 0.0, 0.19509, 0.0, 1.0, -0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing02", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.84811, 2.34669, -1.79, -0.55557, 0.83147, 0.0, 0.83147, 0.55557, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing03", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.56669, 2.62811, -1.79, -0.83147, 0.55557, 0.0, 0.55557, 0.83147, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing04", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.199, 2.78042, -1.79, -0.98079, 0.19509, 0.0, 0.19509, 0.98079, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing05", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.199, 2.78042, -1.79, -0.98079, -0.19509, -0.0, -0.19509, 0.98079, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing06", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.56669, 2.62811, -1.79, -0.83147, -0.55557, -0.0, -0.55557, 0.83147, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing07", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.84811, 2.34669, -1.79, -0.55557, -0.83147, -0.0, -0.83147, 0.55557, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing08", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-1.00042, 1.979, -1.79, -0.19509, 0.0, -0.98079, -0.98079, 0.0, 0.19509, 0.0, 1.0, 0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing09", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-1.00042, 1.581, -1.79, 0.19509, 0.0, -0.98079, -0.98079, 0.0, -0.19509, 0.0, 1.0, 0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing10", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.84811, 1.21331, -1.79, 0.55557, 0.83147, -0.0, -0.83147, 0.55557, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing11", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.56669, 0.93189, -1.79, 0.83147, 0.55557, -0.0, -0.55557, 0.83147, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing12", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.199, 0.77958, -1.79, 0.98079, 0.19509, -0.0, -0.19509, 0.98079, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing13", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.199, 0.77958, -1.79, 0.98079, -0.19509, 0.0, 0.19509, 0.98079, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing14", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.56669, 0.93189, -1.79, 0.83147, -0.55557, 0.0, 0.55557, 0.83147, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing15", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.84811, 1.21331, -1.79, 0.55557, -0.83147, 0.0, 0.83147, 0.55557, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing16", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {1.00042, 1.581, -1.79, 0.19509, -0.0, 0.98079, 0.98079, 0.0, -0.19509, 0.0, 1.0, 0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorGlass", ["shape"] = "Ellipsoid", ["size"] = {1.92, 1.92, 0.4}, ["cf"] = {0.0, 1.78, -1.76, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "d4eeff", ["material"] = "SmoothPlastic", ["transparency"] = 0.55, ["reflectance"] = 0.15, ["collide"] = true, ["shadow"] = true}, {["name"] = "DoorShine", ["shape"] = "Ellipsoid", ["size"] = {0.11, 0.46, 0.05}, ["cf"] = {0.42, 2.2, -1.925, 0.70711, -0.70711, 0.0, 0.70711, 0.70711, 0.0, 0.0, 0.0, 1.0}, ["color"] = "ffffff", ["material"] = "SmoothPlastic", ["transparency"] = 0.25, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "DoorHandle", ["shape"] = "Block", ["size"] = {0.18, 0.66, 0.16}, ["cf"] = {-1.26, 1.78, -1.84, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3f79d4", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorArm", ["shape"] = "Block", ["size"] = {0.4, 0.44, 0.1}, ["cf"] = {1.23, 1.78, -1.72, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumBack", ["shape"] = "Cylinder", ["size"] = {0.06, 1.86, 1.86}, ["cf"] = {0.0, 1.78, -0.4, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "bcc5cf", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat01", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {0.0, 2.66, -0.96, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat02", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {-0.56565, 2.45412, -0.96, 0.76604, -0.64279, 0.0, 0.64279, 0.76604, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat03", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {-0.86663, 1.93281, -0.96, 0.17365, -0.98481, 0.0, 0.98481, 0.17365, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat04", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {-0.7621, 1.34, -0.96, -0.5, -0.86603, 0.0, 0.86603, -0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat05", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {-0.30098, 0.95307, -0.96, -0.93969, -0.34202, 0.0, 0.34202, -0.93969, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat06", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {0.30098, 0.95307, -0.96, -0.93969, 0.34202, 0.0, -0.34202, -0.93969, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat07", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {0.7621, 1.34, -0.96, -0.5, 0.86603, 0.0, -0.86603, -0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat08", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {0.86663, 1.93281, -0.96, 0.17365, 0.98481, 0.0, -0.98481, 0.17365, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat09", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {0.56565, 2.45412, -0.96, 0.76604, 0.64279, 0.0, -0.64279, 0.76604, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumBaffle1", ["shape"] = "Block", ["size"] = {0.16, 0.2, 0.98}, ["cf"] = {0.0, 2.53, -0.94, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "e9edf2", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumBaffle2", ["shape"] = "Block", ["size"] = {0.16, 0.2, 0.98}, ["cf"] = {-0.64952, 1.405, -0.94, -0.5, -0.86603, 0.0, 0.86603, -0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "e9edf2", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumBaffle3", ["shape"] = "Block", ["size"] = {0.16, 0.2, 0.98}, ["cf"] = {0.64952, 1.405, -0.94, -0.5, 0.86603, 0.0, -0.86603, -0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "e9edf2", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSpoke1", ["shape"] = "Block", ["size"] = {0.12, 0.78, 0.05}, ["cf"] = {0.38971, 2.005, -0.445, 0.5, 0.86603, 0.0, -0.86603, 0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "6e7a88", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "DrumSpoke2", ["shape"] = "Block", ["size"] = {0.12, 0.78, 0.05}, ["cf"] = {-0.38971, 2.005, -0.445, 0.5, -0.86603, 0.0, 0.86603, 0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "6e7a88", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "DrumSpoke3", ["shape"] = "Block", ["size"] = {0.12, 0.78, 0.05}, ["cf"] = {-0.0, 1.33, -0.445, -1.0, -0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "6e7a88", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "DrumCloth1", ["shape"] = "Ellipsoid", ["size"] = {0.58, 0.2, 0.3}, ["cf"] = {-0.34975, 1.22029, -0.78, 0.84805, 0.52992, 0.0, -0.52992, 0.84805, 0.0, 0.0, 0.0, 1.0}, ["color"] = "d9443c", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumCloth2", ["shape"] = "Ellipsoid", ["size"] = {0.78, 0.26, 0.58}, ["cf"] = {0.17641, 1.16479, -1.02, 0.96126, -0.27564, 0.0, 0.27564, 0.96126, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2c13d", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumCloth3", ["shape"] = "Ellipsoid", ["size"] = {0.66, 0.24, 0.5}, ["cf"] = {0.44599, 1.34931, -0.72, 0.69466, -0.71934, 0.0, 0.71934, 0.69466, 0.0, 0.0, 0.0, 1.0}, ["color"] = "8e5bd1", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumCloth4", ["shape"] = "Ellipsoid", ["size"] = {0.6, 0.22, 0.22}, ["cf"] = {-0.07317, 1.08383, -1.3, 0.99452, 0.10453, 0.0, -0.10453, 0.99452, 0.0, 0.0, 0.0, 1.0}, ["color"] = "5aa845", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "Water", ["shape"] = "Block", ["size"] = {1.8, 0.74, 1.05}, ["cf"] = {0.0, 1.25, -0.955, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "4aa8ff", ["material"] = "SmoothPlastic", ["transparency"] = 1.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "BackPlate", ["shape"] = "Block", ["size"] = {2.2, 1.9, 0.05}, ["cf"] = {0.0, 2.2, 1.62, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "e3e7ec", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "PowerCord", ["shape"] = "Cylinder", ["size"] = {2.9, 0.09, 0.09}, ["cf"] = {1.25, 1.45, 1.625, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "23262c", ["material"] = "Rubber", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "PowerPlug", ["shape"] = "Block", ["size"] = {0.2, 0.26, 0.1}, ["cf"] = {1.25, 2.95, 1.63, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3b4350", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "TapCold", ["shape"] = "Cylinder", ["size"] = {0.28, 0.18, 0.18}, ["cf"] = {0.75, 3.35, 1.72, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "3f79d4", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "TapHot", ["shape"] = "Cylinder", ["size"] = {0.28, 0.18, 0.18}, ["cf"] = {0.35, 3.35, 1.72, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "d9443c", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "TowelA", ["shape"] = "Block", ["size"] = {1.1, 0.2, 0.8}, ["cf"] = {0.78, 4.09, 0.35, 0.99756, 0.0, 0.06976, 0.0, 1.0, 0.0, -0.06976, 0.0, 0.99756}, ["color"] = "e87fa8", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "TowelA_Band", ["shape"] = "Block", ["size"] = {1.12, 0.1, 0.14}, ["cf"] = {0.78, 4.09, 0.35, 0.99756, 0.0, 0.06976, 0.0, 1.0, 0.0, -0.06976, 0.0, 0.99756}, ["color"] = "f2f0ea", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "TowelB", ["shape"] = "Block", ["size"] = {1.0, 0.18, 0.72}, ["cf"] = {0.74, 4.28, 0.33, 0.99255, 0.0, -0.12187, 0.0, 1.0, 0.0, 0.12187, 0.0, 0.99255}, ["color"] = "2f9e9e", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Jug", ["shape"] = "Block", ["size"] = {0.56, 0.8, 0.4}, ["cf"] = {-0.85, 4.4, 0.55, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f08a30", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "JugLabel", ["shape"] = "Block", ["size"] = {0.4, 0.36, 0.05}, ["cf"] = {-0.85, 4.36, 0.33, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "JugCap", ["shape"] = "Cylinder", ["size"] = {0.16, 0.24, 0.24}, ["cf"] = {-0.95, 4.86, 0.55, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "3f79d4", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "JugDrop", ["shape"] = "Ellipsoid", ["size"] = {0.14, 0.2, 0.05}, ["cf"] = {-0.85, 4.37, 0.305, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3f79d4", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}}, ["pivots"] = {["WaterTop"] = {0.0, 1.62, -0.96}, ["Drum"] = {0.0, 1.78, -0.96}, ["DoorHinge"] = {1.36, 1.78, -1.72}, ["DoorCentre"] = {0.0, 1.78, -1.97}, ["Dial"] = {-1.02, 3.49, -1.72}, ["StartPrompt"] = {0.2, 3.48, -2.0}, ["DoorPrompt"] = {0.0, 1.78, -2.2}}, ["attrs"] = {["Cost"] = 1200, ["DisplayName"] = "Washing Machine", ["Notes"] = "Front-loading washing machine (primlib parts, fun-builds/models/build_WashingMachine.py + laundrylib.py). Drum* spins about Pivot_Drum (authored Z axis), DrumCloth1..4 tumble, Water is authored invisible and filled by the client, Door* swings about Pivot_DoorHinge (vertical), Dial* turns about Pivot_Dial, Screen shows the countdown on its Front face."}, ["min"] = {-1.73, 0.0, -1.96}, ["max"] = {1.73, 4.94, 1.86}}, Dryer = {["key"] = "Dryer", ["parts"] = {{["name"] = "Foot1", ["shape"] = "Cylinder", ["size"] = {0.2, 0.36, 0.36}, ["cf"] = {1.3, 0.1, -1.22, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "23262c", ["material"] = "Rubber", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Foot2", ["shape"] = "Cylinder", ["size"] = {0.2, 0.36, 0.36}, ["cf"] = {-1.3, 0.1, -1.22, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "23262c", ["material"] = "Rubber", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Foot3", ["shape"] = "Cylinder", ["size"] = {0.2, 0.36, 0.36}, ["cf"] = {1.3, 0.1, 1.25, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "23262c", ["material"] = "Rubber", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Foot4", ["shape"] = "Cylinder", ["size"] = {0.2, 0.36, 0.36}, ["cf"] = {-1.3, 0.1, 1.25, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "23262c", ["material"] = "Rubber", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Plinth", ["shape"] = "Block", ["size"] = {3.26, 0.23, 3.08}, ["cf"] = {0.0, 0.285, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3b4350", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Body", ["shape"] = "Block", ["size"] = {3.38, 3.5, 1.94}, ["cf"] = {0.0, 2.13, 0.63, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "SideL", ["shape"] = "Block", ["size"] = {0.1, 3.5, 1.3}, ["cf"] = {1.65, 2.13, -0.95, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "EdgeL", ["shape"] = "Cylinder", ["size"] = {3.5, 0.14, 0.14}, ["cf"] = {1.66, 2.13, -1.585, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "SideR", ["shape"] = "Block", ["size"] = {0.1, 3.5, 1.3}, ["cf"] = {-1.65, 2.13, -0.95, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "EdgeR", ["shape"] = "Cylinder", ["size"] = {3.5, 0.14, 0.14}, ["cf"] = {-1.66, 2.13, -1.585, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Top", ["shape"] = "Block", ["size"] = {3.46, 0.14, 3.3}, ["cf"] = {0.0, 3.93, -0.02, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "TopEdge", ["shape"] = "Cylinder", ["size"] = {3.46, 0.14, 0.14}, ["cf"] = {0.0, 3.93, -1.67, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontTop", ["shape"] = "Block", ["size"] = {3.26, 0.44, 0.12}, ["cf"] = {0.0, 2.89, -1.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontBot", ["shape"] = "Block", ["size"] = {3.26, 0.5, 0.12}, ["cf"] = {0.0, 0.63, -1.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontL", ["shape"] = "Block", ["size"] = {0.73, 1.82, 0.12}, ["cf"] = {1.265, 1.78, -1.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontR", ["shape"] = "Block", ["size"] = {0.73, 1.82, 0.12}, ["cf"] = {-1.265, 1.78, -1.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontCorner1", ["shape"] = "Wedge", ["size"] = {0.12, 0.5272, 0.5272}, ["cf"] = {0.6364, 1.1436, -1.56, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontCorner2", ["shape"] = "Wedge", ["size"] = {0.12, 0.5272, 0.5272}, ["cf"] = {0.6364, 2.4164, -1.56, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontCorner3", ["shape"] = "Wedge", ["size"] = {0.12, 0.5272, 0.5272}, ["cf"] = {-0.6364, 2.4164, -1.56, -0.0, -0.0, -1.0, 0.0, -1.0, 0.0, -1.0, 0.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "FrontCorner4", ["shape"] = "Wedge", ["size"] = {0.12, 0.5272, 0.5272}, ["cf"] = {-0.6364, 1.1436, -1.56, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0, -1.0, 0.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Panel", ["shape"] = "Block", ["size"] = {3.26, 0.76, 0.34}, ["cf"] = {0.0, 3.48, -1.47, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "e3e7ec", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "PanelTrim", ["shape"] = "Block", ["size"] = {3.36, 0.09, 0.17}, ["cf"] = {0.0, 3.07, -1.585, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "d9443c", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "LintTrap", ["shape"] = "Block", ["size"] = {0.72, 0.5, 0.06}, ["cf"] = {1.15, 3.48, -1.665, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "LintTab", ["shape"] = "Block", ["size"] = {0.3, 0.1, 0.05}, ["cf"] = {1.15, 3.62, -1.71, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "d9443c", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "ScreenBezel", ["shape"] = "Block", ["size"] = {0.86, 0.52, 0.06}, ["cf"] = {0.2, 3.48, -1.66, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a8322c", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Screen", ["shape"] = "Block", ["size"] = {0.72, 0.4, 0.06}, ["cf"] = {0.2, 3.48, -1.69, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "1b2229", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "Led", ["shape"] = "Cylinder", ["size"] = {0.06, 0.11, 0.11}, ["cf"] = {-0.42, 3.68, -1.66, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "2d5a2a", ["material"] = "Neon", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "ButtonStart", ["shape"] = "Cylinder", ["size"] = {0.07, 0.22, 0.22}, ["cf"] = {-0.42, 3.38, -1.67, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "5aa845", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DialRing", ["shape"] = "Cylinder", ["size"] = {0.06, 0.62, 0.62}, ["cf"] = {-1.02, 3.49, -1.655, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DialTick", ["shape"] = "Block", ["size"] = {0.06, 0.11, 0.05}, ["cf"] = {-1.02, 3.86, -1.65, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3b4350", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "DialKnob", ["shape"] = "Cylinder", ["size"] = {0.14, 0.46, 0.46}, ["cf"] = {-1.02, 3.49, -1.72, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "d9443c", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DialCap", ["shape"] = "Cylinder", ["size"] = {0.06, 0.3, 0.3}, ["cf"] = {-1.02, 3.49, -1.8, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "f2f0ea", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DialPointer", ["shape"] = "Block", ["size"] = {0.06, 0.15, 0.05}, ["cf"] = {-1.02, 3.565, -1.825, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "23262c", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "BadgePlate", ["shape"] = "Block", ["size"] = {0.7, 0.24, 0.05}, ["cf"] = {-1.02, 0.63, -1.635, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "d9443c", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "BadgeCuke", ["shape"] = "Ellipsoid", ["size"] = {0.44, 0.13, 0.05}, ["cf"] = {-1.02, 0.63, -1.66, 0.98481, -0.17365, 0.0, 0.17365, 0.98481, 0.0, 0.0, 0.0, 1.0}, ["color"] = "5aa845", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "HingePlate", ["shape"] = "Block", ["size"] = {0.22, 0.86, 0.05}, ["cf"] = {1.38, 1.78, -1.64, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "HingePin", ["shape"] = "Cylinder", ["size"] = {0.72, 0.13, 0.13}, ["cf"] = {1.36, 1.78, -1.72, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing01", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {1.00042, 1.979, -1.79, -0.19509, 0.0, 0.98079, 0.98079, 0.0, 0.19509, 0.0, 1.0, -0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing02", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.84811, 2.34669, -1.79, -0.55557, 0.83147, 0.0, 0.83147, 0.55557, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing03", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.56669, 2.62811, -1.79, -0.83147, 0.55557, 0.0, 0.55557, 0.83147, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing04", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.199, 2.78042, -1.79, -0.98079, 0.19509, 0.0, 0.19509, 0.98079, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing05", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.199, 2.78042, -1.79, -0.98079, -0.19509, -0.0, -0.19509, 0.98079, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing06", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.56669, 2.62811, -1.79, -0.83147, -0.55557, -0.0, -0.55557, 0.83147, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing07", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.84811, 2.34669, -1.79, -0.55557, -0.83147, -0.0, -0.83147, 0.55557, 0.0, 0.0, 0.0, -1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing08", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-1.00042, 1.979, -1.79, -0.19509, 0.0, -0.98079, -0.98079, 0.0, 0.19509, 0.0, 1.0, 0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing09", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-1.00042, 1.581, -1.79, 0.19509, 0.0, -0.98079, -0.98079, 0.0, -0.19509, 0.0, 1.0, 0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing10", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.84811, 1.21331, -1.79, 0.55557, 0.83147, -0.0, -0.83147, 0.55557, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing11", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.56669, 0.93189, -1.79, 0.83147, 0.55557, -0.0, -0.55557, 0.83147, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing12", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {-0.199, 0.77958, -1.79, 0.98079, 0.19509, -0.0, -0.19509, 0.98079, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing13", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.199, 0.77958, -1.79, 0.98079, -0.19509, 0.0, 0.19509, 0.98079, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing14", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.56669, 0.93189, -1.79, 0.83147, -0.55557, 0.0, 0.55557, 0.83147, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing15", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {0.84811, 1.21331, -1.79, 0.55557, -0.83147, 0.0, 0.83147, 0.55557, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorRing16", ["shape"] = "Cylinder", ["size"] = {0.4658, 0.3, 0.3}, ["cf"] = {1.00042, 1.581, -1.79, 0.19509, -0.0, 0.98079, 0.98079, 0.0, -0.19509, 0.0, 1.0, 0.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorGlass", ["shape"] = "Ellipsoid", ["size"] = {1.92, 1.92, 0.4}, ["cf"] = {0.0, 1.78, -1.76, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "d4eeff", ["material"] = "SmoothPlastic", ["transparency"] = 0.55, ["reflectance"] = 0.15, ["collide"] = true, ["shadow"] = true}, {["name"] = "DoorShine", ["shape"] = "Ellipsoid", ["size"] = {0.11, 0.46, 0.05}, ["cf"] = {0.42, 2.2, -1.925, 0.70711, -0.70711, 0.0, 0.70711, 0.70711, 0.0, 0.0, 0.0, 1.0}, ["color"] = "ffffff", ["material"] = "SmoothPlastic", ["transparency"] = 0.25, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "DoorHandle", ["shape"] = "Block", ["size"] = {0.18, 0.66, 0.16}, ["cf"] = {-1.26, 1.78, -1.84, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "d9443c", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DoorArm", ["shape"] = "Block", ["size"] = {0.4, 0.44, 0.1}, ["cf"] = {1.23, 1.78, -1.72, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumBack", ["shape"] = "Cylinder", ["size"] = {0.06, 1.86, 1.86}, ["cf"] = {0.0, 1.78, -0.4, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, ["color"] = "bcc5cf", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat01", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {0.0, 2.66, -0.96, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat02", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {-0.56565, 2.45412, -0.96, 0.76604, -0.64279, 0.0, 0.64279, 0.76604, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat03", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {-0.86663, 1.93281, -0.96, 0.17365, -0.98481, 0.0, 0.98481, 0.17365, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat04", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {-0.7621, 1.34, -0.96, -0.5, -0.86603, 0.0, 0.86603, -0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat05", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {-0.30098, 0.95307, -0.96, -0.93969, -0.34202, 0.0, 0.34202, -0.93969, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat06", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {0.30098, 0.95307, -0.96, -0.93969, 0.34202, 0.0, -0.34202, -0.93969, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat07", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {0.7621, 1.34, -0.96, -0.5, 0.86603, 0.0, -0.86603, -0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat08", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {0.86663, 1.93281, -0.96, 0.17365, 0.98481, 0.0, -0.98481, 0.17365, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSlat09", ["shape"] = "Block", ["size"] = {0.6697, 0.08, 1.06}, ["cf"] = {0.56565, 2.45412, -0.96, 0.76604, 0.64279, 0.0, -0.64279, 0.76604, 0.0, 0.0, 0.0, 1.0}, ["color"] = "a9b4c0", ["material"] = "DiamondPlate", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumBaffle1", ["shape"] = "Block", ["size"] = {0.16, 0.2, 0.98}, ["cf"] = {0.0, 2.53, -0.94, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "e9edf2", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumBaffle2", ["shape"] = "Block", ["size"] = {0.16, 0.2, 0.98}, ["cf"] = {-0.64952, 1.405, -0.94, -0.5, -0.86603, 0.0, 0.86603, -0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "e9edf2", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumBaffle3", ["shape"] = "Block", ["size"] = {0.16, 0.2, 0.98}, ["cf"] = {0.64952, 1.405, -0.94, -0.5, 0.86603, 0.0, -0.86603, -0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "e9edf2", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumSpoke1", ["shape"] = "Block", ["size"] = {0.12, 0.78, 0.05}, ["cf"] = {0.38971, 2.005, -0.445, 0.5, 0.86603, 0.0, -0.86603, 0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "6e7a88", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "DrumSpoke2", ["shape"] = "Block", ["size"] = {0.12, 0.78, 0.05}, ["cf"] = {-0.38971, 2.005, -0.445, 0.5, -0.86603, 0.0, 0.86603, 0.5, 0.0, 0.0, 0.0, 1.0}, ["color"] = "6e7a88", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "DrumSpoke3", ["shape"] = "Block", ["size"] = {0.12, 0.78, 0.05}, ["cf"] = {-0.0, 1.33, -0.445, -1.0, -0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "6e7a88", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "DrumCloth1", ["shape"] = "Ellipsoid", ["size"] = {0.66, 0.24, 0.42}, ["cf"] = {-0.32, 1.22574, -0.8, 0.86603, 0.5, 0.0, -0.5, 0.86603, 0.0, 0.0, 0.0, 1.0}, ["color"] = "e87fa8", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumCloth2", ["shape"] = "Ellipsoid", ["size"] = {0.56, 0.2, 0.3}, ["cf"] = {0.20395, 1.1523, -1.06, 0.95106, -0.30902, 0.0, 0.30902, 0.95106, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumCloth3", ["shape"] = "Ellipsoid", ["size"] = {0.74, 0.24, 0.5}, ["cf"] = {0.46075, 1.36514, -0.72, 0.66913, -0.74314, 0.0, 0.74314, 0.66913, 0.0, 0.0, 0.0, 1.0}, ["color"] = "2f9e9e", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "DrumCloth4", ["shape"] = "Ellipsoid", ["size"] = {0.6, 0.22, 0.22}, ["cf"] = {-0.07317, 1.08383, -1.3, 0.99452, 0.10453, 0.0, -0.10453, 0.99452, 0.0, 0.0, 0.0, 1.0}, ["color"] = "5aa845", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "PowerCord", ["shape"] = "Cylinder", ["size"] = {2.9, 0.09, 0.09}, ["cf"] = {1.25, 1.45, 1.625, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, ["color"] = "23262c", ["material"] = "Rubber", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "PowerPlug", ["shape"] = "Block", ["size"] = {0.2, 0.26, 0.1}, ["cf"] = {1.25, 2.95, 1.63, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "3b4350", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "VentRing", ["shape"] = "Cylinder", ["size"] = {0.12, 0.84, 0.84}, ["cf"] = {-1.73, 3.05, 0.85, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "VentHole", ["shape"] = "Cylinder", ["size"] = {0.06, 0.64, 0.64}, ["cf"] = {-1.81, 3.05, 0.85, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "23262c", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "VentSlat1", ["shape"] = "Block", ["size"] = {0.05, 0.12, 0.4692}, ["cf"] = {-1.865, 3.23, 0.85, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "VentSlat2", ["shape"] = "Block", ["size"] = {0.05, 0.12, 0.58}, ["cf"] = {-1.865, 3.05, 0.85, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "VentSlat3", ["shape"] = "Block", ["size"] = {0.05, 0.12, 0.4692}, ["cf"] = {-1.865, 2.87, 0.85, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "c9d1da", ["material"] = "Metal", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}, {["name"] = "BasketFront", ["shape"] = "Block", ["size"] = {1.64, 0.6, 0.08}, ["cf"] = {0.5, 4.3, -0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2c13d", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "BasketBack", ["shape"] = "Block", ["size"] = {1.64, 0.6, 0.08}, ["cf"] = {0.5, 4.3, 0.7, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2c13d", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "BasketL", ["shape"] = "Block", ["size"] = {0.08, 0.6, 0.94}, ["cf"] = {1.28, 4.3, 0.2, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2c13d", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "BasketR", ["shape"] = "Block", ["size"] = {0.08, 0.6, 0.94}, ["cf"] = {-0.28, 4.3, 0.2, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2c13d", ["material"] = "SmoothPlastic", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = true, ["shadow"] = true}, {["name"] = "BasketLaundry", ["shape"] = "Ellipsoid", ["size"] = {1.5, 0.56, 0.94}, ["cf"] = {0.5, 4.5, 0.2, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, ["color"] = "f2f0ea", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = true}, {["name"] = "BasketSock", ["shape"] = "Ellipsoid", ["size"] = {0.18, 0.56, 0.12}, ["cf"] = {0.15, 4.5, -0.36, 0.99027, -0.13917, 0.0, 0.13613, 0.96863, 0.20791, -0.02894, -0.20589, 0.97815}, ["color"] = "3f79d4", ["material"] = "Fabric", ["transparency"] = 0.0, ["reflectance"] = 0.0, ["collide"] = false, ["shadow"] = false}}, ["pivots"] = {["Drum"] = {0.0, 1.78, -0.96}, ["DoorHinge"] = {1.36, 1.78, -1.72}, ["DoorCentre"] = {0.0, 1.78, -1.97}, ["Dial"] = {-1.02, 3.49, -1.72}, ["StartPrompt"] = {0.2, 3.48, -2.0}, ["DoorPrompt"] = {0.0, 1.78, -2.2}, ["Vent"] = {-1.93, 3.05, 0.85}, ["VentOut"] = {-2.93, 3.3, 0.85}}, ["attrs"] = {["Cost"] = 1000, ["DisplayName"] = "Dryer", ["Notes"] = "Tumble dryer matching the WashingMachine (primlib parts, fun-builds/models/build_Dryer.py + laundrylib.py). Drum* spins about Pivot_Drum (authored Z axis), DrumCloth1..4 tumble, Door* swings about Pivot_DoorHinge (vertical), Dial* turns about Pivot_Dial, Screen shows the countdown on its Front face, VentSlat1..3 flutter and lint puffs from Pivot_Vent toward Pivot_VentOut."}, ["min"] = {-1.89, 0.0, -1.96}, ["max"] = {1.73, 4.796, 1.68}}}
local M = (function()
-- Minimal Roblox mock runtime for offline behaviour tests (copied from tests/DJBooth/mock.luau for HomeLaundry, + BulkMoveTo / Emit / NumberRange / 12-number CFrame). SRC is injected above.
local M = {}
local SIM = {now = 0, errors = 0, warns = {}, unknownReads = {}}
M.SIM = SIM

--..Signals..--
local SignalMT = {}
SignalMT.__index = SignalMT
local function Signal()
	return setmetatable({fns = {}, __kind = "RBXScriptSignal"}, SignalMT)
end
function SignalMT:Connect(fn)
	local c = {Connected = true, fn = fn}
	function c:Disconnect() c.Connected = false end
	table.insert(self.fns, c)
	return c
end
function SignalMT:Once(fn)
	local c
	c = self:Connect(function(...) c:Disconnect() fn(...) end)
	return c
end
function SignalMT:Fire(...)
	for _, c in ipairs(table.clone(self.fns)) do
		if c.Connected then
			local ok, err = pcall(c.fn, ...)
			if not ok then SIM.errors += 1 print("!! SIGNAL HANDLER ERROR: " .. tostring(err)) end
		end
	end
end
function SignalMT:Wait() return coroutine.yield() end
M.Signal = Signal

--..Scheduler..--
local waiting = {}
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		SIM.errors += 1
		print("!! COROUTINE ERROR: " .. tostring(err))
		print(debug.traceback(co))
	end
end
local task = {}
function task.spawn(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	table.insert(waiting, {co = co, at = SIM.now, args = table.pack(...)})
	return co
end
function task.delay(t, f, ...)
	local co = coroutine.create(f)
	table.insert(waiting, {co = co, at = SIM.now + (t or 0), args = table.pack(...)})
	return co
end
function task.wait(t)
	local co = coroutine.running()
	table.insert(waiting, {co = co, at = SIM.now + (t or 0), args = table.pack()})
	coroutine.yield()
	return t or 0
end
M.task = task
function M.RunDue()
	local guard = 0
	while true do
		guard += 1
		if guard > 10000 then error("scheduler runaway") end
		local idx
		for i, w in ipairs(waiting) do
			if w.at <= SIM.now + 1e-9 and (not idx or w.at < waiting[idx].at) then idx = i end
		end
		if not idx then return end
		local w = table.remove(waiting, idx)
		if coroutine.status(w.co) == "suspended" then resume(w.co, table.unpack(w.args, 1, w.args.n)) end
	end
end

--..Vector3 / Vector2..--
local V3MT = {}
local function V3(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, __kind = "Vector3"}, V3MT) end
V3MT.__add = function(a, b) return V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3MT.__sub = function(a, b) return V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3MT.__unm = function(a) return V3(-a.X, -a.Y, -a.Z) end
V3MT.__mul = function(a, b)
	if type(a) == "number" then return V3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return V3(a.X * b, a.Y * b, a.Z * b) end
	return V3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3MT.__div = function(a, b)
	if type(b) == "number" then return V3(a.X / b, a.Y / b, a.Z / b) end
	return V3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3MT.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z) end
V3MT.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) return V3(t.X / m, t.Y / m, t.Z / m) end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
	if k == "Cross" then return function(a, b) return V3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
	if k == "Lerp" then return function(a, b, t2) return a + (b - a) * t2 end end
	error("Vector3." .. tostring(k) .. " is not a valid member")
end
local Vector3 = {new = V3, zero = V3(0, 0, 0), one = V3(1, 1, 1), xAxis = V3(1, 0, 0), yAxis = V3(0, 1, 0), zAxis = V3(0, 0, 1)}
M.Vector3 = Vector3
local Vector2 = {new = function(x, y) return {X = x or 0, Y = y or 0, __kind = "Vector2"} end}
Vector2.zero = Vector2.new(0, 0)
M.Vector2 = Vector2

--..CFrame..--
local CFMT = {}
local function CF(px, py, pz, r)
	return setmetatable({p = V3(px, py, pz), r = r or {1, 0, 0, 0, 1, 0, 0, 0, 1}, __kind = "CFrame"}, CFMT)
end
local function mulR(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local s = 0
			for k = 0, 2 do s += a[i * 3 + k + 1] * b[k * 3 + j + 1] end
			r[i * 3 + j + 1] = s
		end
	end
	return r
end
local function rotV(r, v)
	return V3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
local function transpose(r) return {r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9]} end
CFMT.__mul = function(a, b)
	if getmetatable(b) == CFMT then
		local p = a.p + rotV(a.r, b.p)
		return CF(p.X, p.Y, p.Z, mulR(a.r, b.r))
	end
	if getmetatable(b) == V3MT then return a.p + rotV(a.r, b) end
	error("bad CFrame * operand")
end
CFMT.__add = function(a, v) local p = a.p + v return CF(p.X, p.Y, p.Z, a.r) end
CFMT.__eq = function(a, b)
	if a.p ~= b.p then return false end
	for i = 1, 9 do if a.r[i] ~= b.r[i] then return false end end
	return true
end
local CFMethods = {}
function CFMethods.Inverse(a)
	local rt = transpose(a.r)
	local p = -rotV(rt, a.p)
	return CF(p.X, p.Y, p.Z, rt)
end
function CFMethods.ToObjectSpace(a, b) return CFMethods.Inverse(a) * b end
function CFMethods.ToWorldSpace(a, b) return a * b end
function CFMethods.PointToObjectSpace(a, v) return rotV(transpose(a.r), v - a.p) end
function CFMethods.PointToWorldSpace(a, v) return a * v end
function CFMethods.VectorToWorldSpace(a, v) return rotV(a.r, v) end
function CFMethods.VectorToObjectSpace(a, v) return rotV(transpose(a.r), v) end
function CFMethods.Lerp(a, b, t) local p = a.p:Lerp(b.p, t) return CF(p.X, p.Y, p.Z, t < 0.5 and a.r or b.r) end
CFMT.__index = function(t, k)
	if CFMethods[k] then return CFMethods[k] end
	if k == "Position" then return t.p end
	if k == "Rotation" then return CF(0, 0, 0, t.r) end
	if k == "X" then return t.p.X elseif k == "Y" then return t.p.Y elseif k == "Z" then return t.p.Z end
	if k == "RightVector" then return V3(t.r[1], t.r[4], t.r[7]) end
	if k == "UpVector" then return V3(t.r[2], t.r[5], t.r[8]) end
	if k == "LookVector" then return V3(-t.r[3], -t.r[6], -t.r[9]) end
	error("CFrame." .. tostring(k) .. " is not a valid member")
end
CFMT.__tostring = function(a) return "CF" .. tostring(a.p) end
local function Rx(a) local c, s = math.cos(a), math.sin(a) return {1, 0, 0, 0, c, -s, 0, s, c} end
local function Ry(a) local c, s = math.cos(a), math.sin(a) return {c, 0, s, 0, 1, 0, -s, 0, c} end
local function Rz(a) local c, s = math.cos(a), math.sin(a) return {c, -s, 0, s, c, 0, 0, 0, 1} end
local CFrame = {}
function CFrame.new(x, y, z)
	if x == nil then return CF(0, 0, 0) end
	if type(x) == "table" then return CF(x.X, x.Y, x.Z) end
	return CF(x, y, z)
end
function CFrame.Angles(rx, ry, rz) return CF(0, 0, 0, mulR(mulR(Rx(rx), Ry(ry)), Rz(rz))) end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.lookAt(at, target, up)
	up = up or V3(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up).Unit
	local up2 = right:Cross(look)
	return CF(at.X, at.Y, at.Z, {right.X, up2.X, -look.X, right.Y, up2.Y, -look.Y, right.Z, up2.Z, -look.Z})
end
function CFrame.fromMatrix(pos, rx, ry, rz)
	rz = rz or rx:Cross(ry)
	return CF(pos.X, pos.Y, pos.Z, {rx.X, ry.X, rz.X, rx.Y, ry.Y, rz.Y, rx.Z, ry.Z, rz.Z})
end
CFrame.identity = CF(0, 0, 0)
--.. CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
function CFrame.new12(c)
	return CF(c[1], c[2], c[3], {c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]})
end
M.CFrameRot = function(cf) return cf.r end
M.CFrame = CFrame
M.IsCFrame = function(v) return getmetatable(v) == CFMT end

--..Color3..--
local C3MT = {}
local function C3(r, g, b) return setmetatable({R = r, G = g, B = b, __kind = "Color3"}, C3MT) end
C3MT.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
C3MT.__index = function(t, k)
	if k == "Lerp" then return function(a, b, x) return C3(a.R + (b.R - a.R) * x, a.G + (b.G - a.G) * x, a.B + (b.B - a.B) * x) end end
	if k == "ToHSV" then return function() return 0, 0, 0 end end
	error("Color3." .. tostring(k) .. " is not a valid member")
end
C3MT.__tostring = function(c) return string.format("C3(%d,%d,%d)", c.R * 255, c.G * 255, c.B * 255) end
local Color3 = {}
function Color3.new(r, g, b) return C3(r or 0, g or 0, b or 0) end
function Color3.fromRGB(r, g, b) return C3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHex(h)
	h = h:gsub("#", "")
	assert(#h == 6, "bad hex " .. h)
	return C3(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255)
end
function Color3.fromHSV(h, s, v)
	assert(h >= 0 and h <= 1 and s >= 0 and s <= 1 and v >= 0 and v <= 1, ("fromHSV out of range %s %s %s"):format(h, s, v))
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then return C3(v, t, p) elseif i == 1 then return C3(q, v, p) elseif i == 2 then return C3(p, v, t)
	elseif i == 3 then return C3(p, q, v) elseif i == 4 then return C3(t, p, v) end
	return C3(v, p, q)
end
M.Color3 = Color3

--..Small value types..--
M.UDim = {new = function(s, o) return {Scale = s, Offset = o, __kind = "UDim"} end}
M.UDim2 = {
	new = function(xs, xo, ys, yo) return {X = {Scale = xs or 0, Offset = xo or 0}, Y = {Scale = ys or 0, Offset = yo or 0}, __kind = "UDim2"} end,
}
M.UDim2.fromOffset = function(x, y) return M.UDim2.new(0, x, 0, y) end
M.UDim2.fromScale = function(x, y) return M.UDim2.new(x, 0, y, 0) end
M.NumberSequenceKeypoint = {new = function(t, v) return {Time = t, Value = v} end}
M.NumberSequence = {new = function(a, b) return {Keypoints = a, __kind = "NumberSequence"} end}
M.NumberRange = {new = function(a, b) return {Min = a, Max = b or a, __kind = "NumberRange"} end}
M.ColorSequenceKeypoint = {new = function(t, c) return {Time = t, Value = c} end}
M.ColorSequence = {new = function(a, b)
	assert(a ~= nil, "ColorSequence.new(nil)")
	return {A = a, B = b, __kind = "ColorSequence"}
end}

--..Enum..--
local enumCache = {}
M.Enum = setmetatable({}, {__index = function(_, family)
	enumCache[family] = enumCache[family] or setmetatable({}, {__index = function(t, item)
		local e = {Name = item, EnumType = family, __kind = "EnumItem"}
		setmetatable(e, {__tostring = function() return "Enum." .. family .. "." .. item end})
		rawset(t, item, e)
		return e
	end})
	return enumCache[family]
end})
local Enum = M.Enum

--..Instances..--
local ISA = {
	Part = {"BasePart", "PVInstance"}, MeshPart = {"BasePart", "PVInstance"}, Seat = {"BasePart", "PVInstance"},
	Model = {"PVInstance"}, TextButton = {"GuiButton", "GuiObject", "GuiBase2d"}, TextLabel = {"GuiObject", "GuiBase2d"},
	Frame = {"GuiObject", "GuiBase2d"}, ScreenGui = {"LayerCollector", "GuiBase2d"}, SpotLight = {"Light"}, PointLight = {"Light"},
	Script = {"BaseScript", "LuaSourceContainer"}, LocalScript = {"Script", "BaseScript", "LuaSourceContainer"}, ModuleScript = {"LuaSourceContainer"},
}
local DEFAULTS = {
	All = {Archivable = true},
	BasePart = {Transparency = 0, Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, CastShadow = true,
		Material = Enum.Material.Plastic, Size = V3(4, 1, 2)},
	Sound = {IsPlaying = false, IsLoaded = false, TimeLength = 0, TimePosition = 0, Volume = 0.5, PlaybackLoudness = 0, Looped = false,
		SoundId = "", RollOffMinDistance = 10, RollOffMaxDistance = 10000, PlaybackSpeed = 1, Playing = false},
	ProximityPrompt = {Enabled = true, ActionText = "Interact", ObjectText = "", HoldDuration = 0, MaxActivationDistance = 10,
		UIOffset = Vector2.new(0, 0)},
	Humanoid = {Health = 100, HipHeight = 2, Jump = false, Sit = false},
	Beam = {Enabled = true, Brightness = 1},
	SpotLight = {Enabled = true, Brightness = 1, Range = 16, Angle = 90},
	ScreenGui = {Enabled = true},
	GuiObject = {Visible = true},
}
local InstMT = {}
local Methods = {}
local root -- the DataModel

local function isA(obj, class)
	local c = rawget(obj, "__props").ClassName
	if c == class or class == "Instance" then return true end
	for _, s in ipairs(ISA[c] or {}) do if s == class then return true end end
	return false
end

local function PropSignal(obj, name)
	local sigs = rawget(obj, "__propSignals")
	sigs[name] = sigs[name] or Signal()
	return sigs[name]
end
local function AttrSignal(obj, name)
	local sigs = rawget(obj, "__attrSignals")
	sigs[name] = sigs[name] or Signal()
	return sigs[name]
end

local EVENTS = {"Destroying", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "AttributeChanged"}
local CLASS_EVENTS = {
	ProximityPrompt = {"Triggered", "PromptShown", "PromptHidden"}, Sound = {"Loaded", "Ended", "Played"}, TextButton = {"Activated", "MouseButton1Click"},
	Humanoid = {"StateChanged", "Died"}, RemoteEvent = {"OnServerEvent", "OnClientEvent"}, Seat = {},
}

local function NewInstance(class)
	local obj = {__props = {ClassName = class, Name = class}, __children = {}, __attrs = {}, __attrSignals = {}, __propSignals = {},
		__events = {}, __kind = "Instance", __tags = {}}
	for _, e in ipairs(EVENTS) do obj.__events[e] = Signal() end
	for _, e in ipairs(CLASS_EVENTS[class] or {}) do obj.__events[e] = Signal() end
	setmetatable(obj, InstMT)
	return obj
end
M.NewInstance = NewInstance

InstMT.__index = function(t, k)
	if Methods[k] then return Methods[k] end
	local props = rawget(t, "__props")
	local v = props[k]
	if v ~= nil then return v end
	local ev = rawget(t, "__events")[k]
	if ev then return ev end
	if k == "Position" and props.CFrame then return props.CFrame.Position end
	if k == "Orientation" then return V3(0, 0, 0) end
	if k == "Parent" then return nil end
	-- children by name
	for _, c in ipairs(rawget(t, "__children")) do if rawget(c, "__props").Name == k then return c end end
	-- defaults
	local d = DEFAULTS.All[k]
	if d ~= nil then return d end
	local class = props.ClassName
	if DEFAULTS[class] and DEFAULTS[class][k] ~= nil then return DEFAULTS[class][k] end
	for _, s in ipairs(ISA[class] or {}) do
		if DEFAULTS[s] and DEFAULTS[s][k] ~= nil then return DEFAULTS[s][k] end
	end
	SIM.unknownReads[class .. "." .. tostring(k)] = true
	return nil
end

local function fireDescAdded(parent, inst)
	local p = parent
	while p do
		rawget(p, "__events").DescendantAdded:Fire(inst)
		p = rawget(p, "__props").Parent
	end
end

InstMT.__newindex = function(t, k, v)
	local props = rawget(t, "__props")
	if k == "Parent" then
		if rawget(t, "__destroyed") and v ~= nil then error("The Parent property of " .. props.Name .. " is locked") end
		local old = props.Parent
		if old == v then return end
		if old then
			local list = rawget(old, "__children")
			for i, c in ipairs(list) do if c == t then table.remove(list, i) break end end
			local p = old
			while p do rawget(p, "__events").DescendantRemoving:Fire(t) p = rawget(p, "__props").Parent end
		end
		props.Parent = v
		if v then
			table.insert(rawget(v, "__children"), t)
			rawget(v, "__events").ChildAdded:Fire(t)
			fireDescAdded(v, t)
			for _, d in ipairs(Methods.GetDescendants(t)) do fireDescAdded(v, d) end
		end
		rawget(t, "__events").AncestryChanged:Fire(t, v)
		for _, d in ipairs(Methods.GetDescendants(t)) do rawget(d, "__events").AncestryChanged:Fire(t, v) end
		if M.OnParented then M.OnParented(t, v) end
		PropSignal(t, "Parent"):Fire()
		return
	end
	if k == "Position" and (isA(t, "BasePart")) then
		local cf = props.CFrame or CFrame.new()
		k, v = "CFrame", CF(v.X, v.Y, v.Z, cf.r)
	end
	if k == "Shape" and v == Enum.PartType.Ball then
		local s = props.Size or V3(1, 1, 1)
		local m = math.min(s.X, s.Y, s.Z)
		props.Size = V3(m, m, m)
	end
	local isEqual = props[k] == v
	props[k] = v
	if not isEqual then PropSignal(t, k):Fire() end
end
InstMT.__tostring = function(t) return rawget(t, "__props").Name end

function Methods.FindFirstChild(self, name, recursive)
	for _, c in ipairs(rawget(self, "__children")) do if rawget(c, "__props").Name == name then return c end end
	if recursive then
		for _, c in ipairs(rawget(self, "__children")) do
			local f = Methods.FindFirstChild(c, name, true)
			if f then return f end
		end
	end
	return nil
end
function Methods.WaitForChild(self, name, timeout)
	local c = Methods.FindFirstChild(self, name)
	if c then return c end
	if timeout then return nil end
	error("WaitForChild would hang forever: " .. tostring(self) .. "." .. name)
end
function Methods.FindFirstChildOfClass(self, class)
	for _, c in ipairs(rawget(self, "__children")) do if rawget(c, "__props").ClassName == class then return c end end
	return nil
end
function Methods.FindFirstChildWhichIsA(self, class)
	for _, c in ipairs(rawget(self, "__children")) do if isA(c, class) then return c end end
	return nil
end
function Methods.GetChildren(self) return table.clone(rawget(self, "__children")) end
function Methods.GetDescendants(self)
	local out = {}
	local function walk(o) for _, c in ipairs(rawget(o, "__children")) do table.insert(out, c) walk(c) end end
	walk(self)
	return out
end
function Methods.IsA(self, class) return isA(self, class) end
function Methods.IsDescendantOf(self, anc)
	local p = rawget(self, "__props").Parent
	while p do if p == anc then return true end p = rawget(p, "__props").Parent end
	return false
end
function Methods.Destroy(self)
	if rawget(self, "__destroyed") then return end
	rawget(self, "__events").Destroying:Fire()
	for _, c in ipairs(Methods.GetChildren(self)) do Methods.Destroy(c) end
	self.Parent = nil
	rawset(self, "__destroyed", true)
	if M.OnDestroyed then M.OnDestroyed(self) end
end
function Methods.ClearAllChildren(self) for _, c in ipairs(Methods.GetChildren(self)) do Methods.Destroy(c) end end
function Methods.GetAttribute(self, name) return rawget(self, "__attrs")[name] end
function Methods.GetAttributes(self) return table.clone(rawget(self, "__attrs")) end
function Methods.SetAttribute(self, name, value)
	local attrs = rawget(self, "__attrs")
	local t = M.typeof(value)
	if value ~= nil and not (t == "number" or t == "string" or t == "boolean" or t == "Vector3" or t == "Color3" or t == "CFrame" or t == "UDim2" or t == "Vector2") then
		error("SetAttribute: unsupported type " .. t .. " for " .. name)
	end
	if attrs[name] == value then return end
	attrs[name] = value
	AttrSignal(self, name):Fire()
	rawget(self, "__events").AttributeChanged:Fire(name)
end
function Methods.GetAttributeChangedSignal(self, name) return AttrSignal(self, name) end
function Methods.GetPropertyChangedSignal(self, name) return PropSignal(self, name) end
function Methods.GetFullName(self)
	local parts = {}
	local p = self
	while p and p ~= root do table.insert(parts, 1, rawget(p, "__props").Name) p = rawget(p, "__props").Parent end
	return table.concat(parts, ".")
end
function Methods.GetPivot(self)
	local pp = rawget(self, "__props").PrimaryPart
	return pp and pp.CFrame or CFrame.new()
end
function Methods.Clone(self) error("Clone not mocked") end
-- Sound
function Methods.Play(self) self.IsPlaying = true self.Playing = true end
function Methods.Resume(self) self.IsPlaying = true self.Playing = true end
function Methods.Pause(self) self.IsPlaying = false self.Playing = false end
function Methods.Stop(self) self.IsPlaying = false self.Playing = false self.TimePosition = 0 end
-- Seat
function Methods.Sit(self, humanoid) self.Occupant = humanoid end
-- Animator
function Methods.LoadAnimation(self, animation)
	assert(isA(self, "Animator"), "LoadAnimation on " .. rawget(self, "__props").ClassName)
	assert(type(animation.AnimationId) == "string" and animation.AnimationId:match("^rbxassetid://%d+$"), "bad AnimationId")
	local track = {IsPlaying = false, Looped = false, Priority = nil, AnimationId = animation.AnimationId, Destroyed = false}
	function track:Play(fade) self.IsPlaying = true M.SIM.lastTrack = self end
	function track:Stop(fade) self.IsPlaying = false end
	function track:Destroy() self.Destroyed = true end
	return track
end
-- workspace
function Methods.GetServerTimeNow(self) return 5000 + SIM.now end
function Methods.BulkMoveTo(self, parts, cfs, mode)
	assert(type(parts) == "table" and type(cfs) == "table", "BulkMoveTo wants two arrays")
	assert(#cfs >= #parts, ("BulkMoveTo: %d parts, %d cframes"):format(#parts, #cfs))
	assert(mode ~= nil, "BulkMoveTo mode")
	for i, p in ipairs(parts) do
		assert(isA(p, "BasePart"), "BulkMoveTo: not a BasePart")
		assert(getmetatable(cfs[i]) == CFMT, "BulkMoveTo: not a CFrame at " .. i)
		p.CFrame = cfs[i]
	end
	SIM.bulkMoves = (SIM.bulkMoves or 0) + 1
end
-- ParticleEmitter
function Methods.Emit(self, n)
	assert(rawget(self, "__props").ClassName == "ParticleEmitter", "Emit on a non-emitter")
	self.Emitted = (self.Emitted or 0) + (n or 16)
end

function M.SetRoot(r) root = r end
M.Methods = Methods
return M

end)()
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
