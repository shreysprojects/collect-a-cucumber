--[[
	Piano  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds HomePiano
	Client half of the playable grand piano (fun-builds/CONTRACT.md, package HomePiano; model
	fun-builds/models/build_Piano.py). The server half seats one pianist on the bench (prompt "Play piano") and
	publishes Fun_Player = the pianist's UserId (0 = nobody).
	  * GUI: while Fun_Player is the LOCAL player (and they are still seated, within GUI_RANGE studs) a piano opens at
	    the bottom of the screen (above the hotbar): two octaves - 24 keys, C4..B5 at octave shift 0 - drawn as white
	    and black keys, played by click / touch (multi-touch; drag the mouse for a glissando) and by keyboard: white
	    keys A S D F G H J K L ; ' and black keys W E T Y U O P (the first 18 keys), Z / X shift the octave down / up
	    (OCTAVE_MIN..OCTAVE_MAX). Keys light up green while held. The red close button stands the player up (Jump);
	    standing up any other way (Space, death, the build moved / broken / sold) closes it too
	  * notes: a key plays AT ONCE on a local 2D Sound pool (FunAssets.Sfx.PianoNote, recorded at
	    FunAssets.PianoRootHz: PlaybackSpeed = 2^((n - root) / 12), n = the MIDI number) and goes to the server with
	    ctx:Send("Note", n | {n, ...}) - keys pressed within SEND_INTERVAL share one send (chords), which keeps a fast
	    player under the server's 12 sends/s. The server checks the sender sits at this piano and fires
	    "Note" {n | {n, ...}, userId} to everyone; every OTHER client plays it at Pivot_Sound (3D, InverseTapered,
	    RollOffMax ROLLOFF_MAX) on a small per-piano pool
	  * music notes: every note, local or remote, floats a coloured note glyph (BillboardGui) up out of the open case
	    from Pivot_Notes, swaying and fading (a pool of FLOAT_POOL, the oldest recycled first)
	  * pianist pose: while someone sits at the bench, every client leans them in over the keys - body forward, arms
	    reaching to the keyboard, head down - by writing the R15 joint Transforms after the Animator (RunService.Stepped,
	    like FunBuildClient's lying seats; Motor6D or AnimationConstraint). Each note swings the hand that plays it
	    (low half = left hand) toward its key and dips it. POSE_ENABLED = false turns this off
	One Stepped connection per piano drives the floats and the pose (asleep beyond STEP_RANGE studs of the camera)
	and watches the open GUI. Everything is made through ctx (or the GUI, destroyed on close) and cleaned up by it.
	Parts / pivots: Pivot_Sound, Pivot_Notes (authored fallbacks below); state Fun_Player; the pianist's SeatPart is
	named SEAT_NAME by the server half.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))
local ButtonFX = nil -- the HUD's press pop, required when the GUI is first built

local player = Players.LocalPlayer

--..Config..--
local SEAT_NAME = "PianoBench"             -- server half's Seat name
local NOTE_SOUND = FunAssets.Sfx.PianoNote or FunAssets.Sfx.ArcadeBlip
local ROOT_MIDI = 69 + 12 * math.log((tonumber(FunAssets.PianoRootHz) or 261.63) / 440, 2)
local FIRST_MIDI = 60                      -- C4: the GUI's first key at octave shift 0
local KEY_COUNT = 24                       -- two octaves on screen
local OCTAVE_MIN, OCTAVE_MAX = -2, 1       -- the GUI's octave shift: C2..B3 up to C5..B6
local LOCAL_POOL, REMOTE_POOL = 10, 8      -- Sounds per pool (round robin)
local LOCAL_VOLUME, REMOTE_VOLUME = 0.6, 0.8
local ROLLOFF_MIN, ROLLOFF_MAX = 10, 80    -- studs (other players' notes, 3D)
local REMOTE_HEAR = 95                     -- studs camera -> piano: remote notes beyond this are not played at all
local SEND_INTERVAL = 0.1                  -- s: at most ~10 Note sends a second (the framework allows 12 actions/s in all)
local MAX_CHORD = 6
local GUI_RANGE = 20                       -- studs: the GUI closes if the local player is farther than this
local STEP_RANGE = 160                     -- studs camera -> piano: floats + pose sleep beyond this
local SOUND_FALLBACK = Vector3.new(-0.3, 3.85, 1.6) -- authored Pivot_Sound / Pivot_Notes (build_Piano.py)
local NOTES_FALLBACK = Vector3.new(-0.7, 4.2, 1.9)
local LOCAL_FOLDER = "FunBuildLocal"       -- client-only workspace folder (shared with the TV) for helper parts

--..Floating notes..--
local FLOAT_POOL = 10
local FLOAT_LIFE = 1.9                     -- s
local FLOAT_RISE = 4.6                     -- authored studs risen over a life
local FLOAT_SWAY = 0.35                    -- authored studs side to side
local FLOAT_SIZE = 1.25                    -- studs
local FLOAT_GAP = 0.07                     -- s between two floats (a chord makes one)
local FLOAT_SPREAD_X, FLOAT_SPREAD_Z = 1.7, 1.3 -- authored studs around Pivot_Notes
local FLOAT_MAX_DISTANCE = 140
local FLOAT_GLYPHS = {"\u{266A}", "\u{266B}", "\u{266A}"} -- ♪ ♫ ♪
local FLOAT_COLORS = {
	Color3.fromHex("f2c13d"), Color3.fromHex("3f79d4"), Color3.fromHex("d9443c"), Color3.fromRGB(105, 255, 30),
	Color3.fromRGB(255, 120, 200),
}

--..Pianist pose (degrees)..--
local POSE_ENABLED = true
local POSE = {Waist = -8, Neck = -14, Shoulder = 40, Elbow = 38, Wrist = -20}
local PRESS_DIP = {Neck = -3, Shoulder = -4, Elbow = -10, Wrist = -16}
local HAND_YAW_OUT, HAND_YAW_IN = 22, 6    -- a hand's yaw from its outer end (lowest / highest key) to the middle
local PRESS_DECAY = 12                     -- 1/s
local YAW_FOLLOW = 14                      -- 1/s
local SIDES = {"Left", "Right"}

--..GUI look (the HUD's)..--
local FONT = Enum.Font.FredokaOne
local OUTLINE = Color3.fromRGB(22, 24, 30)
local GREEN = ColorSequence.new(Color3.fromRGB(69, 255, 0), Color3.fromRGB(157, 255, 36))
local RED = ColorSequence.new(Color3.fromRGB(230, 30, 30), Color3.fromRGB(255, 84, 60))
local PANEL_BG = Color3.fromRGB(31, 33, 42)
local KEYBED_BG = Color3.fromRGB(14, 15, 19)
local FELT = Color3.fromRGB(170, 32, 42)
local WHITE_KEY = Color3.fromRGB(250, 248, 242)
local BLACK_KEY = Color3.fromRGB(40, 42, 50)
local WHITE_LIT = Color3.fromRGB(140, 240, 60)
local BLACK_LIT = Color3.fromRGB(88, 205, 20)
local WHITE_W, WHITE_H = 50, 176           -- px before the UIScale
local BLACK_W, BLACK_H = 32, 108
local PAD, HEADER_H, GAP, HINT_H = 14, 50, 8, 24
local KEYBOARD_W = WHITE_W * 14
local PANEL_W = KEYBOARD_W + PAD * 2
local PANEL_H = PAD + HEADER_H + GAP + WHITE_H + HINT_H + PAD
local HOTBAR_BOTTOM, HOTBAR_GAP = 10, 14   -- HotbarClient: bar 10 px off the bottom, slots clamp(7.5 % of height, 44, 64)
local TOP_RESERVE = 70
local PRESS_SHIFT = 3                      -- px a held key sinks
local RELEASE_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ACTION = "FunPianoKeys"

local NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local IS_BLACK = {[1] = true, [3] = true, [6] = true, [8] = true, [10] = true} -- pitch classes
local KEY_SEMITONES = {
	[Enum.KeyCode.A] = 0, [Enum.KeyCode.W] = 1, [Enum.KeyCode.S] = 2, [Enum.KeyCode.E] = 3, [Enum.KeyCode.D] = 4,
	[Enum.KeyCode.F] = 5, [Enum.KeyCode.T] = 6, [Enum.KeyCode.G] = 7, [Enum.KeyCode.Y] = 8, [Enum.KeyCode.H] = 9,
	[Enum.KeyCode.U] = 10, [Enum.KeyCode.J] = 11, [Enum.KeyCode.K] = 12, [Enum.KeyCode.O] = 13, [Enum.KeyCode.L] = 14,
	[Enum.KeyCode.P] = 15, [Enum.KeyCode.Semicolon] = 16, [Enum.KeyCode.Quote] = 17,
}
local KEY_LETTERS = {} -- [semitone] = "A" ...
for code, s in pairs(KEY_SEMITONES) do
	KEY_LETTERS[s] = (code == Enum.KeyCode.Semicolon and ";") or (code == Enum.KeyCode.Quote and "'") or code.Name
end

local B = {}
B.Keys = {"Piano"}
B.StepRange = STEP_RANGE

--..Helpers..--
local function New(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function Corner(parent, px)
	return New("UICorner", {CornerRadius = UDim.new(0, px or 8)}, parent)
end

local function Stroke(parent, thickness, border)
	return New("UIStroke", {
		Color = OUTLINE, Thickness = thickness or 2,
		ApplyStrokeMode = border and Enum.ApplyStrokeMode.Border or Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

local function LocalFolder()
	local folder = workspace:FindFirstChild(LOCAL_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = LOCAL_FOLDER
		folder.Archivable = false
		folder.Parent = workspace
	end
	return folder
end

local function NoteName(midi)
	return NAMES[midi % 12 + 1] .. tostring(math.floor(midi / 12) - 1)
end

local function Speed(n)
	return 2 ^ ((n - ROOT_MIDI) / 12)
end

local function Lerp(a, b, t)
	return a + (b - a) * t
end

--..Sounds..--
local function MakePool(ctx, parent, count, props)
	local pool = {}
	for i = 1, count do
		local ok, sound = pcall(ctx.Sound, ctx, parent, NOTE_SOUND, props)
		if ok and sound then pool[i] = sound end
	end
	return pool
end

--.. next Sound of a pool (round robin), pitched to MIDI note n
local function PlayOn(pool, st, cursorKey, n, volume)
	if #pool == 0 then return end
	local i = (st[cursorKey] or 0) % #pool + 1
	st[cursorKey] = i
	local sound = pool[i]
	if not sound or not sound.Parent then return end
	sound.PlaybackSpeed = Speed(n)
	sound.Volume = volume
	sound.TimePosition = 0
	sound:Play()
end

--..Floating notes..--
local function MakeFloats(st, holder)
	for i = 1, FLOAT_POOL do
		local gui = New("BillboardGui", {
			Name = "PianoNoteFloat", Size = UDim2.fromScale(FLOAT_SIZE * st.Scale, FLOAT_SIZE * st.Scale), LightInfluence = 0,
			MaxDistance = FLOAT_MAX_DISTANCE, AlwaysOnTop = false, Enabled = false,
		})
		local label = New("TextLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT, Text = FLOAT_GLYPHS[1], TextScaled = true,
			TextColor3 = FLOAT_COLORS[1],
		}, gui)
		local stroke = Stroke(label, 2)
		gui.Parent = holder
		st.Floats[i] = {Gui = gui, Label = label, Stroke = stroke, Born = -1, Offset = Vector3.zero, Phase = 0}
	end
end

local function SpawnFloat(st)
	local now = os.clock()
	if now - st.LastFloat < FLOAT_GAP then return end
	st.LastFloat = now
	local pick, oldest = nil, math.huge
	for _, f in ipairs(st.Floats) do
		if f.Born < 0 then
			pick = f
			break
		end
		if f.Born < oldest then oldest, pick = f.Born, f end
	end
	if not pick or not pick.Gui.Parent then return end
	local s = st.Scale
	local dx = (math.random() * 2 - 1) * FLOAT_SPREAD_X
	local dz = (math.random() * 2 - 1) * FLOAT_SPREAD_Z
	pick.Offset = st.Right * (dx * s) + st.Back * (dz * s)
	pick.Phase = math.random() * math.pi * 2
	pick.Born = now
	pick.Label.Text = FLOAT_GLYPHS[math.random(1, #FLOAT_GLYPHS)]
	pick.Label.TextColor3 = FLOAT_COLORS[math.random(1, #FLOAT_COLORS)]
	pick.Label.TextTransparency = 1
	pick.Stroke.Transparency = 1
	pick.Gui.StudsOffsetWorldSpace = pick.Offset
	pick.Gui.Enabled = true
end

local function UpdateFloats(st)
	local now = os.clock()
	local s = st.Scale
	for _, f in ipairs(st.Floats) do
		if f.Born >= 0 then
			local t = (now - f.Born) / FLOAT_LIFE
			if t >= 1 then
				f.Born = -1
				f.Gui.Enabled = false
			else
				local sway = math.sin(f.Phase + t * 7) * FLOAT_SWAY * s
				f.Gui.StudsOffsetWorldSpace = f.Offset + Vector3.new(0, t * FLOAT_RISE * s, 0) + st.Right * sway
				local fade = t < 0.12 and 1 - t / 0.12 or math.max(0, (t - 0.55) / 0.45)
				f.Label.TextTransparency = fade
				f.Stroke.Transparency = fade
				f.Label.Rotation = math.sin(f.Phase + t * 5) * 14
				local grow = FLOAT_SIZE * s * (0.55 + 0.45 * math.min(1, t / 0.18))
				f.Gui.Size = UDim2.fromScale(grow, grow)
			end
		end
	end
end

--..Pianist pose..--
local function JointMap(character)
	local map = {}
	for joint in pairs(Kit.Joints(character)) do map[joint.Name] = joint end
	return map
end

local function SetJoint(joint, cf)
	if joint and joint.Parent then joint.Transform = cf end
end

--.. a note n on a keyboard whose first key is `first`: swing the hand that plays it toward it and dip it
local function Gesture(st, n, first)
	local u = math.clamp((n - first) / (KEY_COUNT - 1), 0, 1)
	local hand
	if u < 0.5 then
		hand = st.Hands.Left
		hand.Target = Lerp(HAND_YAW_OUT, -HAND_YAW_IN, u / 0.5)   -- + yaw = toward the pianist's left (the low end)
	else
		hand = st.Hands.Right
		hand.Target = Lerp(HAND_YAW_IN, -HAND_YAW_OUT, (u - 0.5) / 0.5)
	end
	hand.Press = 1
end

local function UpdatePose(st, dt)
	if not POSE_ENABLED then return end
	local uid = st.Occupant
	if type(uid) ~= "number" or uid <= 0 then
		st.PoseCharacter = nil
		return
	end
	local pianist = Players:GetPlayerByUserId(uid)
	local character = pianist and pianist.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local seatPart = humanoid.SeatPart
	if not seatPart or seatPart.Name ~= SEAT_NAME then return end
	if st.PoseCharacter ~= character or (not st.Joints.LeftShoulder and os.clock() - st.JointsAt > 1) then
		st.PoseCharacter = character
		st.Joints = JointMap(character)
		st.JointsAt = os.clock()
	end
	local j = st.Joints
	local rad = math.rad
	local press = 0
	for _, side in ipairs(SIDES) do
		local hand = st.Hands[side]
		hand.Yaw += (hand.Target - hand.Yaw) * math.min(1, dt * YAW_FOLLOW)
		hand.Press *= math.exp(-dt * PRESS_DECAY)
		press = math.max(press, hand.Press)
		SetJoint(j[side .. "Shoulder"], CFrame.Angles(0, rad(hand.Yaw), 0) * CFrame.Angles(rad(POSE.Shoulder + PRESS_DIP.Shoulder * hand.Press), 0, 0))
		SetJoint(j[side .. "Elbow"], CFrame.Angles(rad(POSE.Elbow + PRESS_DIP.Elbow * hand.Press), 0, 0))
		SetJoint(j[side .. "Wrist"], CFrame.Angles(rad(POSE.Wrist + PRESS_DIP.Wrist * hand.Press), 0, 0))
	end
	SetJoint(j.Waist, CFrame.Angles(rad(POSE.Waist), 0, 0))
	SetJoint(j.Neck, CFrame.Angles(rad(POSE.Neck + PRESS_DIP.Neck * press), 0, 0))
end

--.. one frame of a piano on screen
local function Step(st, dt)
	UpdateFloats(st)
	UpdatePose(st, dt)
end

--..Notes (the local player's own + other players')..--
local function PlayLocalNote(st, n, first)
	if not st.Local then
		st.Local = MakePool(st.Ctx, SoundService, LOCAL_POOL, {Name = "PianoNoteLocal", Volume = LOCAL_VOLUME})
	end
	PlayOn(st.Local, st, "LocalNext", n, LOCAL_VOLUME)
	Gesture(st, n, first)
	SpawnFloat(st)
end

local function PlayRemoteNote(st, n)
	if not st.Remote then
		st.Remote = MakePool(st.Ctx, st.SoundAt, REMOTE_POOL, {
			Name = "PianoNote", Volume = REMOTE_VOLUME, RollOffMode = Enum.RollOffMode.InverseTapered,
			RollOffMinDistance = ROLLOFF_MIN, RollOffMaxDistance = ROLLOFF_MAX,
		})
	end
	PlayOn(st.Remote, st, "RemoteNext", n, REMOTE_VOLUME)
end

--..The piano GUI (one per client: the local player plays one piano at a time)..--
local G = {
	Ctx = nil,           -- the piano ctx whose GUI is open
	Screen = nil, Holder = nil, Scale = nil, RangeLabel = nil,
	Keys = {},           -- [semitone 0..23] = {Frame, Black, Pos, NoteLabel}
	Held = {},           -- [source] = semitone (source: a KeyCode, "mouse" or a touch InputObject)
	Count = {},          -- [semitone] = sources holding it
	Conns = {},
	Octave = 0,
	Pending = {}, LastSend = -math.huge, FlushQueued = false,
	OpenedAt = 0, SeenSeated = false,
}

local Close -- (forward)

local function FirstMidi()
	return FIRST_MIDI + 12 * G.Octave
end

local function Light(s, on)
	local key = G.Keys[s]
	if not key or not key.Frame.Parent then return end
	if key.Tween then
		key.Tween:Cancel()
		key.Tween = nil
	end
	if on then
		key.Frame.BackgroundColor3 = key.Black and BLACK_LIT or WHITE_LIT
		key.Frame.Position = key.Pos + UDim2.fromOffset(0, PRESS_SHIFT)
	else
		key.Frame.Position = key.Pos
		key.Tween = TweenService:Create(key.Frame, RELEASE_TWEEN, {BackgroundColor3 = key.Black and BLACK_KEY or WHITE_KEY})
		key.Tween:Play()
	end
end

local function Flush()
	G.FlushQueued = false
	local ctx = G.Ctx
	if #G.Pending == 0 or not ctx or not ctx:Alive() then
		table.clear(G.Pending)
		return
	end
	local payload = #G.Pending == 1 and G.Pending[1] or table.clone(G.Pending)
	table.clear(G.Pending)
	G.LastSend = os.clock()
	ctx:Send("Note", payload)
end

local function Queue(n)
	if #G.Pending < MAX_CHORD then table.insert(G.Pending, n) end
	local wait = SEND_INTERVAL - (os.clock() - G.LastSend)
	if wait <= 0 then
		Flush()
	elseif not G.FlushQueued then
		G.FlushQueued = true
		task.delay(wait, Flush)
	end
end

local function ReleaseSource(source)
	local s = G.Held[source]
	if s == nil then return end
	G.Held[source] = nil
	G.Count[s] = math.max(0, (G.Count[s] or 1) - 1)
	if G.Count[s] == 0 then Light(s, false) end
end

local function PressKey(s, source)
	local ctx = G.Ctx
	local st = ctx and ctx.Piano
	if not st or not ctx:Alive() then return end
	if G.Held[source] ~= nil then ReleaseSource(source) end
	G.Held[source] = s
	G.Count[s] = (G.Count[s] or 0) + 1
	Light(s, true)
	local first = FirstMidi()
	local n = first + s
	PlayLocalNote(st, n, first)
	Queue(n)
end

local function RefreshLabels()
	local first = FirstMidi()
	if G.RangeLabel then G.RangeLabel.Text = NoteName(first) .. "  -  " .. NoteName(first + KEY_COUNT - 1) end
	for s, key in pairs(G.Keys) do
		if key.NoteLabel then key.NoteLabel.Text = NoteName(first + s) end
	end
end

local function ShiftOctave(delta)
	local octave = math.clamp(G.Octave + delta, OCTAVE_MIN, OCTAVE_MAX)
	if octave == G.Octave then return end
	G.Octave = octave
	RefreshLabels()
end

local function StandUp()
	local humanoid = G.Ctx and G.Ctx:LocalCharacter()
	if humanoid and humanoid.SeatPart then
		humanoid.Sit = false
		humanoid.Jump = true
	end
end

local function Layout()
	if not G.Holder then return end
	local camera = workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local slot = math.clamp(math.floor(size.Y * 0.075), 44, 64)
	local bottom = HOTBAR_BOTTOM + slot + HOTBAR_GAP
	local fit = math.min(size.X * 0.97 / PANEL_W, math.max(120, size.Y - bottom - TOP_RESERVE) / PANEL_H)
	local base = math.clamp(math.min(size.X / 1400, size.Y / 820), 0.6, 1.3)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	G.Scale.Scale = math.max(0.35, touchOnly and math.min(fit, 1.3) or math.min(base, fit))
	G.Holder.Position = UDim2.new(0.5, 0, 1, -bottom)
end

--.. a HUD-style button (gradient, dark outline, white outlined text), with an optional keyboard hint in its corner
local function HudButton(parent, name, text, gradient, size, position, anchor, hint)
	local button = New("TextButton", {
		Name = name, Size = size, Position = position, AnchorPoint = anchor, BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false, Text = "", ZIndex = 3,
	}, parent)
	Corner(button, 12)
	Stroke(button, 2.5, true)
	New("UIGradient", {Rotation = 90, Color = gradient}, button)
	local label = New("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT, Text = text, TextSize = 28,
		TextColor3 = Color3.new(1, 1, 1), ZIndex = 4,
	}, button)
	Stroke(label, 2.5)
	if hint and UserInputService.KeyboardEnabled then
		local key = New("TextLabel", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 2), Size = UDim2.fromOffset(16, 14),
			BackgroundTransparency = 1, Font = FONT, Text = hint, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), ZIndex = 4,
		}, button)
		Stroke(key, 1.5)
	end
	if ButtonFX then pcall(ButtonFX.Prepare, button) end
	return button
end

--.. an invisible hit area for key s (white keys get two, so no hit area overlaps a black key)
local function HitArea(parent, s, x, y, w, h)
	local hit = New("TextButton", {
		Name = "Hit" .. s, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1,
		AutoButtonColor = false, Text = "", ZIndex = 8, Selectable = false,
	}, parent)
	hit.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 then
			PressKey(s, "mouse")
		elseif kind == Enum.UserInputType.Touch then
			PressKey(s, input)
		end
	end)
	--.. drag the held mouse across the keys: a glissando
	hit.MouseEnter:Connect(function()
		local held = G.Held.mouse
		if held ~= nil and held ~= s and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			PressKey(s, "mouse")
		end
	end)
	return hit
end

local function BuildGui()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return false end
	if not ButtonFX then
		local fxModule = Modules:FindFirstChild("ButtonFX")
		if fxModule then
			local ok, mod = pcall(require, fxModule)
			if ok and type(mod) == "table" then ButtonFX = mod end
		end
	end

	local screen = New("ScreenGui", {
		Name = "FunPianoGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local holder = New("Frame", {
		Name = "Holder", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(PANEL_W, PANEL_H), BackgroundTransparency = 1,
	}, screen)
	local scale = New("UIScale", {}, holder)
	local panel = New("Frame", {
		Name = "Panel", Size = UDim2.fromScale(1, 1), BackgroundColor3 = PANEL_BG, BackgroundTransparency = 0.04, ZIndex = 1,
	}, holder)
	Corner(panel, 18)
	Stroke(panel, 3, true)
	New("UIGradient", {
		Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 180)),
	}, panel)

	--.. header: title, octave shift, close
	local midY = PAD + HEADER_H / 2
	local title = New("TextLabel", {
		Name = "Title", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(PAD + 4, midY), Size = UDim2.fromOffset(200, HEADER_H),
		BackgroundTransparency = 1, Font = FONT, Text = "\u{266B} PIANO", TextSize = 32, TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
	}, panel)
	Stroke(title, 3)
	local down = HudButton(panel, "OctaveDown", "-", GREEN, UDim2.fromOffset(56, 42), UDim2.new(0.5, -122, 0, midY), Vector2.new(0.5, 0.5), "Z")
	local range = New("TextLabel", {
		Name = "Range", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, midY), Size = UDim2.fromOffset(170, 42),
		BackgroundColor3 = KEYBED_BG, BackgroundTransparency = 0.2, Font = FONT, Text = "", TextSize = 24,
		TextColor3 = Color3.new(1, 1, 1), ZIndex = 3,
	}, panel)
	Corner(range, 12)
	Stroke(range, 2)
	local up = HudButton(panel, "OctaveUp", "+", GREEN, UDim2.fromOffset(56, 42), UDim2.new(0.5, 122, 0, midY), Vector2.new(0.5, 0.5), "X")
	local close = HudButton(panel, "Close", "X", RED, UDim2.fromOffset(52, 42), UDim2.new(1, -PAD, 0, midY), Vector2.new(1, 0.5), nil)
	down.Activated:Connect(function()
		if ButtonFX then pcall(ButtonFX.Press, down) end
		ShiftOctave(-1)
	end)
	up.Activated:Connect(function()
		if ButtonFX then pcall(ButtonFX.Press, up) end
		ShiftOctave(1)
	end)
	close.Activated:Connect(function()
		local ctx = G.Ctx
		StandUp()
		if Close then Close() end
		--.. still seated a moment later (the jump did not take): bring the piano back
		task.delay(1, function()
			if ctx and ctx:Alive() and G.Ctx == nil and ctx:State("Player") == player.UserId then
				local humanoid = ctx:LocalCharacter()
				if humanoid and humanoid.SeatPart and ctx.Piano and ctx.Piano.Open then ctx.Piano.Open() end
			end
		end)
	end)

	--.. the keyboard
	local keyboard = New("Frame", {
		Name = "Keyboard", Position = UDim2.fromOffset(PAD, PAD + HEADER_H + GAP), Size = UDim2.fromOffset(KEYBOARD_W, WHITE_H),
		BackgroundColor3 = KEYBED_BG, ZIndex = 2, ClipsDescendants = false,
	}, panel)
	Corner(keyboard, 10)
	Stroke(keyboard, 2.5, true)
	local keys = {}
	local whiteIndex = -1
	local showLetters = UserInputService.KeyboardEnabled
	for s = 0, KEY_COUNT - 1 do
		local pc = s % 12
		if not IS_BLACK[pc] then
			whiteIndex += 1
			local x = whiteIndex * WHITE_W
			local pos = UDim2.fromOffset(x + 2, 0)
			local frame = New("Frame", {
				Name = "White" .. s, Position = pos, Size = UDim2.fromOffset(WHITE_W - 4, WHITE_H - 3),
				BackgroundColor3 = WHITE_KEY, BorderSizePixel = 0, ZIndex = 3,
			}, keyboard)
			Corner(frame, 8)
			New("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(214, 214, 220))}, frame)
			local key = {Frame = frame, Black = false, Pos = pos}
			if pc == 0 then
				key.NoteLabel = New("TextLabel", {
					Name = "Note", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, showLetters and -30 or -8),
					Size = UDim2.fromOffset(WHITE_W - 6, 16), BackgroundTransparency = 1, Font = FONT, Text = "", TextSize = 14,
					TextColor3 = Color3.fromRGB(150, 152, 165), ZIndex = 4,
				}, frame)
			end
			if showLetters and KEY_LETTERS[s] then
				New("TextLabel", {
					Name = "Letter", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8),
					Size = UDim2.fromOffset(WHITE_W - 6, 20), BackgroundTransparency = 1, Font = FONT, Text = KEY_LETTERS[s],
					TextSize = 19, TextColor3 = Color3.fromRGB(96, 100, 114), ZIndex = 4,
				}, frame)
			end
			keys[s] = key
			--.. hit areas: the full-width lower part + the upper part between the neighbouring black keys
			local left = (s > 0 and IS_BLACK[(pc + 11) % 12]) and BLACK_W / 2 or 0
			local right = (s < KEY_COUNT - 1 and IS_BLACK[(pc + 1) % 12]) and BLACK_W / 2 or 0
			HitArea(keyboard, s, x, BLACK_H, WHITE_W, WHITE_H - BLACK_H)
			HitArea(keyboard, s, x + left, 0, WHITE_W - left - right, BLACK_H)
		end
	end
	whiteIndex = -1
	for s = 0, KEY_COUNT - 1 do
		local pc = s % 12
		if IS_BLACK[pc] then
			local x = (whiteIndex + 1) * WHITE_W - BLACK_W / 2
			local pos = UDim2.fromOffset(x, 0)
			local frame = New("Frame", {
				Name = "Black" .. s, Position = pos, Size = UDim2.fromOffset(BLACK_W, BLACK_H),
				BackgroundColor3 = BLACK_KEY, BorderSizePixel = 0, ZIndex = 6,
			}, keyboard)
			Corner(frame, 6)
			New("UIStroke", {Color = Color3.new(0, 0, 0), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, frame)
			New("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 160))}, frame)
			if showLetters and KEY_LETTERS[s] then
				local letter = New("TextLabel", {
					Name = "Letter", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6),
					Size = UDim2.fromOffset(BLACK_W, 16), BackgroundTransparency = 1, Font = FONT, Text = KEY_LETTERS[s],
					TextSize = 15, TextColor3 = Color3.new(1, 1, 1), ZIndex = 7,
				}, frame)
				Stroke(letter, 1.2)
			end
			keys[s] = {Frame = frame, Black = true, Pos = pos}
			HitArea(keyboard, s, x, 0, BLACK_W, BLACK_H)
		else
			whiteIndex += 1
		end
	end
	--.. the red key felt along the back of the keys
	New("Frame", {
		Name = "Felt", Position = UDim2.fromOffset(0, -2), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = FELT,
		BorderSizePixel = 0, ZIndex = 7,
	}, keyboard)

	--.. hint
	local hint = New("TextLabel", {
		Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -PAD + 4), Size = UDim2.new(1, -PAD * 2, 0, HINT_H - 2),
		BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = Color3.fromRGB(215, 220, 230), ZIndex = 3,
		Text = showLetters and "White keys A - '   Black keys W - P   Z / X change octave   Space stands up"
			or "Tap the keys to play   Jump to stand up",
	}, panel)
	Stroke(hint, 1.5)

	G.Screen, G.Holder, G.Scale, G.RangeLabel, G.Keys = screen, holder, scale, range, keys
	RefreshLabels()
	Layout()
	screen.Parent = playerGui
	return true
end

local function OnKey(_, state, input)
	local code = input.KeyCode
	if state == Enum.UserInputState.Begin then
		if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		local s = KEY_SEMITONES[code]
		if s then
			PressKey(s, code)
		elseif code == Enum.KeyCode.Z then
			ShiftOctave(-1)
		elseif code == Enum.KeyCode.X then
			ShiftOctave(1)
		end
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if KEY_SEMITONES[code] then ReleaseSource(code) end
	end
	return Enum.ContextActionResult.Sink
end

local function Open(ctx)
	if G.Ctx == ctx then return end
	if G.Ctx then Close() end
	G.Ctx = ctx
	G.OpenedAt, G.SeenSeated = os.clock(), false
	if not BuildGui() then
		G.Ctx = nil
		return
	end
	local codes = {Enum.KeyCode.Z, Enum.KeyCode.X}
	for code in pairs(KEY_SEMITONES) do table.insert(codes, code) end
	ContextActionService:BindActionAtPriority(ACTION, OnKey, false, Enum.ContextActionPriority.High.Value, table.unpack(codes))
	table.insert(G.Conns, UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 then
			ReleaseSource("mouse")
		elseif kind == Enum.UserInputType.Touch then
			ReleaseSource(input)
			--.. and any other finger whose touch has ended (in case the engine hands out a fresh InputObject)
			for source in pairs(G.Held) do
				if typeof(source) == "Instance" and source:IsA("InputObject") and source.UserInputState ~= Enum.UserInputState.Begin
					and source.UserInputState ~= Enum.UserInputState.Change then
					ReleaseSource(source)
				end
			end
		end
	end))
	local camera = workspace.CurrentCamera
	if camera then table.insert(G.Conns, camera:GetPropertyChangedSignal("ViewportSize"):Connect(Layout)) end
end

Close = function()
	if not G.Ctx then return end
	G.Ctx = nil
	pcall(ContextActionService.UnbindAction, ContextActionService, ACTION)
	for _, c in ipairs(G.Conns) do c:Disconnect() end
	table.clear(G.Conns)
	table.clear(G.Held)
	table.clear(G.Count)
	table.clear(G.Pending)
	if G.Screen then G.Screen:Destroy() end
	G.Screen, G.Holder, G.Scale, G.RangeLabel = nil, nil, nil, nil
	G.Keys = {}
end

--.. the open GUI closes when its pianist is no longer seated here or has wandered off
local function Watchdog(ctx)
	local humanoid = ctx:LocalCharacter()
	local seated = humanoid ~= nil and humanoid.SeatPart ~= nil and humanoid.SeatPart.Name == SEAT_NAME
	if seated then G.SeenSeated = true end
	local far = not ctx:Near(GUI_RANGE * math.max(1, ctx.Scale))
	if far or (not seated and (G.SeenSeated or os.clock() - G.OpenedAt > 2)) then Close() end
end

--..Behaviour..--
function B.Client(model, ctx)
	local scale = ctx.Scale
	local origin = Kit.Origin(model)
	local soundPos = Kit.Pivot(model, "Sound") or Kit.ToWorld(model, SOUND_FALLBACK)
	local notesPos = Kit.Pivot(model, "Notes") or Kit.ToWorld(model, NOTES_FALLBACK)

	--.. one invisible helper part at the float spawn point; the note sounds ride an attachment at Pivot_Sound
	local holder = ctx:Part({
		Name = "PianoFX", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(notesPos), Transparency = 1, Parent = LocalFolder(),
	})
	local soundAt = Instance.new("Attachment")
	soundAt.Name = "PianoSound"
	soundAt.Parent = holder
	soundAt.WorldPosition = soundPos

	local st = {
		Ctx = ctx, Model = model, Scale = scale, Holder = holder, SoundAt = soundAt,
		Right = origin.RightVector, Back = -origin.LookVector,
		Floats = {}, LastFloat = -math.huge,
		Occupant = 0, PoseCharacter = nil, Joints = {}, JointsAt = 0,
		Hands = {Left = {Yaw = 8, Target = 8, Press = 0}, Right = {Yaw = -8, Target = -8, Press = 0}},
	}
	st.Open = function() Open(ctx) end
	ctx.Piano = st
	MakeFloats(st, holder)

	ctx:OnState("Player", function(uid)
		if not ctx:Alive() then return end
		st.Occupant = uid
		if uid == player.UserId then
			local humanoid = ctx:LocalCharacter()
			if humanoid then Open(ctx) end
		elseif G.Ctx == ctx then
			Close()
		end
	end)

	ctx:Connect(RunService.Stepped, function(_, dt)
		if G.Ctx == ctx then Watchdog(ctx) end
		if ctx:CameraDistance() > STEP_RANGE then return end
		local ok, err = pcall(Step, st, math.min(dt, 1 / 15))
		if not ok then warn("[Piano] step: " .. tostring(err)) end
	end)

	return function()
		if G.Ctx == ctx then Close() end
		ctx.Piano = nil
	end
end

--.. server -> client: another player's note(s) at this piano
function B.OnEvent(model, action, payload, ctx)
	if action ~= "Note" or type(payload) ~= "table" then return end
	local st = ctx.Piano
	if not st then return end
	local notes, uid = payload[1], payload[2]
	if uid == player.UserId then return end -- played the moment the key went down
	if type(notes) == "number" then notes = {notes} end
	if type(notes) ~= "table" then return end
	local dist = ctx:CameraDistance()
	for i = 1, math.min(#notes, MAX_CHORD) do
		local n = notes[i]
		if type(n) == "number" then
			if dist <= REMOTE_HEAR then PlayRemoteNote(st, n) end
			if dist <= STEP_RANGE then
				Gesture(st, n, n - (n - FIRST_MIDI) % KEY_COUNT)
				SpawnFloat(st)
			end
		end
	end
end

return B
