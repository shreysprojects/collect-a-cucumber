--[[
	ArcadeCabinet  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the playable ARCADE CABINET - "CUCUMBER CATCH" (fun-builds/CONTRACT.md, notes/ArcadeCabinet.md).
	Server state: Fun_HiScore / Fun_HiName (the cabinet's best), Fun_Player (arcade name of whoever is playing,
	nil = nobody), Fun_Stick (-1 / 0 / 1, that player's joystick). Server events: "Open" (only to the player who
	pressed Play) and "NewHigh" {Score, Name, UserId} (everyone).

	WORLD (every client near the cabinet; animated from Kit.Now() so everyone sees the same frame)
	  Screen    a local part laid in the raked CRT opening (authored screen plane from props/build_arcade_cabinet.py:
	            centre line y 3.84 / z -0.30, rake 11.6 deg, opening 1.52 x 1.14, face in front of the neon pixel
	            art, inside the 0.30-deep bezel) carrying a pixel-style SurfaceGui (Font Arcade):
	              ATTRACT   bouncing 🥒, blinking "PRESS E TO PLAY" ("TAP TO PLAY" on touch), "HI <score> <name>"
	              PLAYING   the local player's own game: "PLAYING", live score and hearts
	              WATCHING  someone else plays: "NOW PLAYING <name>" over falling mini cucumbers
	  Marquee   a local SurfaceGui panel on Pivot_MarqueeCentre, inside the white MarqueePanel border (the neon
	            "ARCADE" MarqueeText is hidden locally with LocalTransparencyModifier while it shows): chase bulbs,
	            "CUCUMBER CATCH", "HI-SCORE <n> <name>". NewHigh -> confetti out of the marquee (4 colour emitters,
	            SquareParticle) + Sfx.Cheer + a flashing "NEW HIGH SCORE!" for CELEBRATE_TIME.
	  Joystick  the stick ball is merged into RedControls (with the 3 front buttons) and its shaft into Metalwork
	            (with the coin door), so while anyone plays both parts are hidden locally and replaced by look-alike
	            parts built from the same authored numbers (colour / material copied from the originals); the ball
	            and shaft tilt about Pivot_JoystickPivot - the local player's own input, or State Stick for
	            onlookers - and the front buttons blink down on catches / hits. The originals come back when nobody
	            plays and on cleanup. BuildMenuClient resets LocalTransparencyModifier to 0 after a cancelled move,
	            so hidden parts are re-asserted every HIDE_CHECK s.
	GAME (after "Open"; one game at a time on this client)
	  A ScreenGui styled like the cabinet (blue body, orange T-molding stroke, pink marquee title), a CRT playfield,
	  two big side rails with green buttons (touch / mouse hold) and a red close X. 3-2-1-GO, then items fall:
	  🥒 +1, golden cucumber +5 (at most one per GOLDEN_COOLDOWN), 🧟 zombie heads (wobble sideways later on) and
	  rotten cucumbers (buzzing fly, fall faster) cost a life - 3 lives, a short invulnerable blink after a hit.
	  Difficulty ramps over RAMP_SECONDS (drop rate, fall speed, hazard share) and the fall speed keeps creeping up
	  after that; "SPEED UP!" every LEVEL_SECONDS. Pixel sparks + pop text on catches, shake + red flash on hits.
	  Controls: A/D, arrow keys, gamepad stick / d-pad, the side rails, or drag on the playfield. While open the
	  PlayerModule controls are disabled and the movement / jump / camera keys are sunk (ContextActionService
	  above the PlayerModule), so the avatar stays put.
	  GAME OVER card: score, personal best (this session), the cabinet's HI, PLAY AGAIN (Space / Enter / pad A),
	  EXIT (Backspace / pad B). The score goes to the server ("Score" {Score, Seconds}, Seconds = game time).
	  Max scoring rate by design ~2.5 / s (drops >= 0.36 s apart, >= 42 % hazards at full speed, golden <= 1 per
	  3.5 s) - always inside the server's plausibility rule (<= 3 / s + 10).
	  Closes on EXIT / X, walking > CLOSE_RANGE studs from the cabinet, death, or the build's behaviour stopping.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

local player = Players.LocalPlayer
local C = Color3.fromRGB

--..Config: world..--
local LOCAL_FOLDER = "FunBuildLocal"    -- client-only workspace folder for local parts (shared with the TV behaviour)
local CLOSE_RANGE = 20                  -- studs from the cabinet: farther closes the game
local HIDE_CHECK = 0.5                  -- s: re-hide the parts this behaviour hides (see header)
local SCREEN_FPS, MARQUEE_FPS = 30, 10  -- SurfaceGui update rates
local GUI_MAX_DISTANCE = 150            -- studs: the SurfaceGuis stop drawing beyond this
local CELEBRATE_TIME = 5                -- s of "NEW HIGH SCORE!" on the marquee
local RAKE = math.rad(11.6)             -- screen rake off vertical (top leans back)
local SCREEN_Y, SCREEN_Z = 3.84, -0.30  -- authored centre of the screen plane's reference line (d = 0)
local SCREEN_D = -0.15                  -- authored depth of the display part along the screen normal (pixels end at -0.17, bezel face at 0)
local SCREEN_SIZE = Vector2.new(1.50, 1.12) -- authored: just inside the 1.52 x 1.14 bezel opening
local SCREEN_THICK = 0.02
local SCREEN_CANVAS = Vector2.new(300, 224)
local MARQUEE_FALLBACK = Vector3.new(0, 5.675, -0.62) -- authored Pivot_MarqueeCentre (the panel's face centre)
local MARQUEE_SIZE = Vector2.new(2.04, 0.55)          -- authored: inside the 2.18 x 0.65 white panel
local MARQUEE_DEPTH, MARQUEE_PROUD = 0.04, 0.025      -- the display's front face stands PROUD in front of the panel face
local MARQUEE_CANVAS = Vector2.new(600, 162)
local JOYSTICK_FALLBACK = Vector3.new(0.62, 2.74, -1.06) -- authored Pivot_JoystickPivot (ball-top swivel on the deck)
local DECK_NORMAL = Vector3.new(0, 0.9648, -0.2631)   -- authored: up the stick, square to the raked control deck
local STICK_TILT = math.rad(22)
local STICK_RATE = 14                   -- 1/s: tilt smoothing
local PRESS_TIME, PRESS_DEPTH = 0.14, 0.035
local CYL_UP = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder part's axis (X) turned onto the stick's Y
local CONFETTI = {C(255, 214, 64), C(255, 79, 163), C(77, 210, 255), C(157, 255, 77)}
local CONFETTI_TEXTURE = "rbxasset://textures/particles/SquareParticle.png"
local CONFETTI_EACH = 14

--.. the look-alike joystick and everything else merged into RedControls / Metalwork (build_arcade_cabinet.py
--.. sections 8 + 9). Deck parts: At = (u - 0.62, h, -(t - 0.5) * 0.9121) in the STICK frame (origin at the
--.. pivot, X = authored X, Y up the stick); Cyl = a cylinder along the stick. Authored = plain authored position.
local RIG_PARTS = {
	{Name = "Ball", From = "RedControls", Shape = "Ball", Diameter = 0.30, At = Vector3.new(0, 0.46, 0), Tilt = true},
	{Name = "Shaft", From = "Metalwork", Shape = "Cyl", Length = 0.34, Diameter = 0.11, At = Vector3.new(0, 0.27, 0), Tilt = true},
	{Name = "Washer", From = "Metalwork", Shape = "Cyl", Length = 0.09, Diameter = 0.26, At = Vector3.new(0, 0.075, 0)},
	{Name = "Plate", From = "Metalwork", Shape = "Cyl", Length = 0.07, Diameter = 0.52, At = Vector3.new(0, 0.015, 0)},
	{Name = "Button1", From = "RedControls", Shape = "Cyl", Length = 0.085, Diameter = 0.22, At = Vector3.new(-0.88, 0.0125, -0.146), Press = 1},
	{Name = "Button2", From = "RedControls", Shape = "Cyl", Length = 0.085, Diameter = 0.22, At = Vector3.new(-1.16, 0.0125, -0.146), Press = 2},
	{Name = "Button3", From = "RedControls", Shape = "Cyl", Length = 0.085, Diameter = 0.22, At = Vector3.new(-1.44, 0.0125, -0.146), Press = 3},
	{Name = "CoinDoor", From = "Metalwork", Shape = "Block", Size = Vector3.new(1.36, 0.90, 0.08), Authored = Vector3.new(0, 1.25, -0.80)},
	{Name = "ReturnLip", From = "Metalwork", Shape = "Block", Size = Vector3.new(0.42, 0.14, 0.18), Authored = Vector3.new(-0.37, 0.79, -0.85)},
}

--..Config: game..--
local GUI_NAME = "CucumberCatch"
local FONT = Enum.Font.FredokaOne
local PIXEL = Enum.Font.Arcade
local PANEL = Vector2.new(780, 620)     -- design px; a UIScale fits it to the viewport
local PANEL_DROP = 18                   -- px the panel sits below centre (clear of the top bar)
local PW, PH = 484, 528                 -- playfield
local FIELD_X, FIELD_Y = 148, 76
local RAIL_W = 120
local HUD_H = 46
local GROUND = 34
local BASKET_W, BASKET_H = 100, 52
local ITEM = 50
local LIVES = 3
local COUNTDOWN = {"3", "2", "1", "GO!"}
local COUNT_STEP = 0.55
local RAMP_SECONDS = 60                 -- difficulty 0 -> 1
local SPAWN_EVERY = {1.0, 0.42}         -- s between drops at difficulty 0 / 1 (x 0.85 .. 1.15 jitter)
local FALL = {0.30, 0.78}               -- playfield heights per second at difficulty 0 / 1
local OVERTIME = 0.006                  -- fall speed +0.6 % per second past RAMP_SECONDS
local HAZARD = {0.18, 0.42}             -- share of drops that are hazards at difficulty 0 / 1
local ZOMBIE_SHARE = 0.55               -- of the hazards (the rest are rotten cucumbers)
local ROTTEN_FALL, GOLD_FALL = 1.15, 1.1
local GOLDEN_CHANCE, GOLDEN_COOLDOWN = 0.09, 3.5
local BASKET_SPEED = 1.35               -- playfield widths per second (keys / rails / pad)
local DRAG_SPEED = 2.6                  -- ... following a drag
local BASKET_ACCEL = 16
local INVULNERABLE = 0.9
local LEVEL_SECONDS = 12
local STICK_SEND_EVERY = 0.2            -- s between "Stick" sends (only on change)
local ALIVE_EVERY = 4                   -- s between "Alive" pings
local MAX_DT = 1 / 20
local MAX_SPARKS = 90
local GRAVITY = 900                     -- px/s^2 for sparks
local ACTION = "CucumberCatchControls"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 100
local K = Enum.KeyCode
local LEFT_KEYS = {[K.A] = true, [K.Left] = true, [K.DPadLeft] = true}
local RIGHT_KEYS = {[K.D] = true, [K.Right] = true, [K.DPadRight] = true}
local AGAIN_KEYS = {[K.Space] = true, [K.Return] = true, [K.ButtonA] = true}
local EXIT_KEYS = {[K.Backspace] = true, [K.ButtonB] = true}
local SUNK_KEYS = {K.A, K.D, K.Left, K.Right, K.W, K.S, K.Up, K.Down, K.Space, K.Return, K.Backspace,
	K.DPadLeft, K.DPadRight, K.DPadUp, K.DPadDown, K.ButtonA, K.ButtonB, K.Thumbstick1}

--..Look..--
local WHITE = C(255, 255, 255)
local BLACK = C(0, 0, 0)
local DARK = C(23, 26, 32)
local GREEN = {Top = C(157, 255, 36), Bottom = C(69, 255, 0), Highlight = C(208, 255, 106)}
local RED = {Top = C(255, 100, 100), Bottom = C(230, 30, 30), Highlight = C(255, 196, 196)}
local CAB_BLUE, CAB_BLUE_DARK = C(63, 121, 212), C(36, 74, 146)
local TMOLD = C(255, 138, 61)
local NEON_PINK, NEON_CYAN, NEON_LIME = C(255, 79, 163), C(77, 210, 255), C(157, 255, 77)
local YELLOW = C(242, 193, 61)
local SPARK_CUKE = {C(120, 255, 90), C(60, 200, 60), C(210, 255, 170)}
local SPARK_GOLD = {C(255, 230, 90), C(255, 186, 30), C(255, 255, 220)}
local SPARK_HIT = {C(255, 70, 70), C(170, 60, 210), C(255, 150, 60)}
local SPARK_MISS = {C(140, 150, 165), C(100, 110, 125)}
local CUKE = "\u{1F952}"
local ZOMBIE = "\u{1F9DF}"
local HEART = "\u{2764}\u{FE0F}"
local HEART_LOST = "\u{1F5A4}"
local SPARKLE = "\u{2728}"
local PARTY = "\u{1F389}"

--..Shared..--
local Active = nil      -- the open game (one at a time on this client)
local PersonalBest = 0  -- this session, any cabinet

local B = {}
B.Keys = {"ArcadeCabinet"}
B.StepRange = 140

--..Helpers..--
local function New(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function Try(inst, prop, value)
	pcall(function() inst[prop] = value end)
end

local function Corner(parent, px)
	return New("UICorner", {CornerRadius = UDim.new(0, px or 12)}, parent)
end

local function Round(parent)
	return New("UICorner", {CornerRadius = UDim.new(1, 0)}, parent)
end

--.. border = true strokes a frame's edge; otherwise (Contextual) a text object's glyphs
local function Stroke(parent, thickness, color, border)
	return New("UIStroke", {
		Color = color or DARK, Thickness = thickness or 2, LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = border and Enum.ApplyStrokeMode.Border or Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

local function Gradient(parent, top, bottom, rotation)
	return New("UIGradient", {Color = ColorSequence.new(top, bottom), Rotation = rotation or 90}, parent)
end

local function Box(parent, props)
	local frame = New("Frame", {BorderSizePixel = 0, BackgroundColor3 = WHITE})
	for k, v in pairs(props) do frame[k] = v end
	frame.Parent = parent
	return frame
end

--.. a FredokaOne label: white text, dark stroke (stroke = 0 for none)
local function Text(parent, props, stroke)
	local label = New("TextLabel", {BackgroundTransparency = 1, Font = FONT, TextColor3 = WHITE, TextSize = 24, Text = ""})
	for k, v in pairs(props) do label[k] = v end
	if (stroke or 2) > 0 then Stroke(label, stroke or 2) end
	label.Parent = parent
	return label
end

--.. a pixel-font label for the in-world screens (fills its box)
local function Pixel(parent, text, y, h, color)
	return New("TextLabel", {
		BackgroundTransparency = 1, Font = PIXEL, Text = text, TextScaled = true, TextColor3 = color or WHITE,
		Size = UDim2.new(1, -16, 0, h), Position = UDim2.new(0.5, 0, 0, y), AnchorPoint = Vector2.new(0.5, 0),
	}, parent)
end

--.. a HUD-style button: gradient shell, dark edge, inner highlight rim, white stroked text, press pop
local function Button(parent, look, size, position, text, textSize)
	local shell = Box(parent, {Size = size, Position = position, AnchorPoint = Vector2.new(0.5, 0.5)})
	Corner(shell, 14)
	Gradient(shell, look.Top, look.Bottom)
	Stroke(shell, 3, DARK, true)
	local rim = Box(shell, {Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1})
	Corner(rim, 11)
	New("UIStroke", {Color = look.Highlight, Thickness = 2, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, rim)
	local button = New("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text or "", Font = FONT,
		TextSize = textSize or 28, TextColor3 = WHITE, AutoButtonColor = false,
	}, shell)
	Stroke(button, 2.5)
	local pop = New("UIScale", {}, shell)
	button.MouseEnter:Connect(function() pop.Scale = 1.04 end)
	button.MouseLeave:Connect(function() pop.Scale = 1 end)
	button.MouseButton1Down:Connect(function() pop.Scale = 0.93 end)
	button.MouseButton1Up:Connect(function() pop.Scale = 1 end)
	return button, shell
end

--.. a chunky chevron: dir -1 = "<", 1 = ">" (two rounded bars meeting at the tip)
local function Chevron(parent, dir, size, color)
	local holder = Box(parent, {Size = UDim2.fromOffset(size, size), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1})
	for i = -1, 1, 2 do
		local bar = Box(holder, {
			Size = UDim2.fromOffset(size * 0.62, size * 0.2), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(size * (0.5 - 0.1 * dir), size * (0.5 + i * 0.19)),
			Rotation = -i * dir * 40, BackgroundColor3 = color,
		})
		Round(bar)
	end
	return holder
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

local function AuthoredPivot(model, name, fallback)
	local v = model:GetAttribute("Pivot_" .. name)
	return typeof(v) == "Vector3" and v or fallback
end

local function Lerp(a, b, t)
	return a + (b - a) * t
end

--.. 0 -> 1 -> 0 triangle wave
local function Tri(t, period)
	local x = (t / period) % 2
	return x < 1 and x or 2 - x
end

local function IsTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function SetText(label, text)
	if label.Text ~= text then label.Text = text end
end

local function HiText(w)
	if w.Hi and w.Hi > 0 then
		return tostring(w.Hi) .. "  " .. (w.HiName or "???")
	end
	return nil
end

--..World: hidden originals..--
--.. hide / show one of the build's own parts on this client only (restored on cleanup)
local function SetHidden(w, part, hidden)
	if not part then return end
	if hidden then
		w.Hide[part] = true
		part.LocalTransparencyModifier = 1
	else
		w.Hide[part] = nil
		if part.Parent then part.LocalTransparencyModifier = 0 end
	end
end

--.. BuildMenuClient puts LocalTransparencyModifier back to 0 after a cancelled move: hide those parts again
--.. (a ghost value like 0.85 during a move is left alone)
local function Reassert(w)
	for part in pairs(w.Hide) do
		if part.Parent and part.LocalTransparencyModifier == 0 then part.LocalTransparencyModifier = 1 end
	end
end

--..World: screen..--
--.. the display's authored CFrame: in the raked screen plane, Front face (LookVector) out of the screen
local function ScreenCFrame()
	local s, c = math.sin(RAKE), math.cos(RAKE)
	local position = Vector3.new(0, SCREEN_Y + SCREEN_D * s, SCREEN_Z - SCREEN_D * c)
	return CFrame.fromMatrix(position, Vector3.xAxis, Vector3.new(0, c, s))
end

local function SurfaceGui(part, canvas, brightness)
	local gui = New("SurfaceGui", {
		Name = "ArcadeGui", Face = Enum.NormalId.Front, LightInfluence = 0, Brightness = brightness,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, CanvasSize = canvas,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Adornee = part,
	})
	Try(gui, "ClipsDescendants", true)
	Try(gui, "MaxDistance", GUI_MAX_DISTANCE)
	gui.Parent = part
	return gui
end

local function BuildScreen(w, folder)
	local scale = w.Scale
	local part = w.Ctx:Part({
		Name = "ArcadeScreen", Size = Vector3.new(SCREEN_SIZE.X, SCREEN_SIZE.Y, SCREEN_THICK) * scale,
		CFrame = Kit.CFrameToWorld(w.Model, ScreenCFrame()), Color = C(8, 12, 20), Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local gui = SurfaceGui(part, SCREEN_CANVAS, 1.4)
	local root = Box(gui, {Size = UDim2.fromScale(1, 1)})
	Gradient(root, C(16, 24, 48), C(5, 7, 16))
	for i = 0, 13 do -- CRT scanlines
		Box(root, {Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromOffset(0, 7 + i * 16), BackgroundColor3 = BLACK, BackgroundTransparency = 0.72, ZIndex = 5})
	end
	local sc = {Part = part}

	--.. attract loop
	local attract = Box(root, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1})
	Pixel(attract, "CUCUMBER CATCH", 10, 26, NEON_LIME)
	sc.Bouncer = New("TextLabel", {BackgroundTransparency = 1, Font = FONT, Text = CUKE, TextSize = 40, Size = UDim2.fromOffset(48, 48)}, attract)
	sc.Press = Pixel(attract, IsTouch() and "TAP TO PLAY" or "PRESS E TO PLAY", 160, 22, YELLOW)
	sc.Hi = Pixel(attract, "HI ---", 192, 20, NEON_CYAN)
	sc.Attract = attract

	--.. the local player's own game
	local playing = Box(root, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false})
	sc.PlayingTitle = Pixel(playing, "PLAYING", 30, 44, NEON_LIME)
	sc.Score = Pixel(playing, "SCORE 0", 100, 30, WHITE)
	sc.Hearts = New("TextLabel", {BackgroundTransparency = 1, Font = FONT, Text = "", TextSize = 30, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 148)}, playing)
	sc.Playing = playing

	--.. someone else's game
	local watching = Box(root, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false})
	sc.Minis = {}
	for i = 1, 3 do
		sc.Minis[i] = New("TextLabel", {BackgroundTransparency = 1, Font = FONT, Text = CUKE, TextSize = 24, Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(0.5, 0.5)}, watching)
	end
	Pixel(watching, "NOW PLAYING", 18, 28, YELLOW)
	sc.Name = Pixel(watching, "", 56, 34, WHITE)
	sc.Watching = watching
	w.Screen = sc
end

local function RefreshScreenHi(w)
	local hi = HiText(w)
	SetText(w.Screen.Hi, hi and ("HI " .. hi) or "HI ---")
end

local function UpdateScreen(w, now)
	local sc = w.Screen
	local g = w.Game
	local mode = g and "play" or (w.PlayerName and "watch" or "attract")
	sc.Attract.Visible = mode == "attract"
	sc.Playing.Visible = mode == "play"
	sc.Watching.Visible = mode == "watch"
	if mode == "attract" then
		local xSpan, ySpan = SCREEN_CANVAS.X - 16 - 48, 104 - 44
		sc.Bouncer.Position = UDim2.fromOffset(8 + Tri(now, 4.3) * xSpan, 44 + Tri(now, 1.7) * ySpan)
		sc.Bouncer.Rotation = ((now / 4.3) % 2 < 1) and 14 or -14
		sc.Press.Visible = now % 1 < 0.62
	elseif mode == "play" then
		sc.PlayingTitle.Visible = now % 0.8 < 0.55
		SetText(sc.Score, "SCORE " .. tostring(g.score))
		SetText(sc.Hearts, string.rep(HEART, math.max(0, g.lives)) .. string.rep(HEART_LOST, math.max(0, LIVES - g.lives)))
	else
		SetText(sc.Name, w.PlayerName or "")
		for i, mini in ipairs(sc.Minis) do
			local f = (now * 0.6 + i * 0.37) % 1
			mini.Position = UDim2.fromOffset(SCREEN_CANVAS.X * (0.2 + 0.3 * (i - 1)), 110 + f * 104)
			mini.Rotation = f * 360
		end
	end
end

--..World: marquee..--
local function BuildMarquee(w, folder)
	local scale = w.Scale
	local pivot = AuthoredPivot(w.Model, "MarqueeCentre", MARQUEE_FALLBACK)
	local centre = pivot + Vector3.new(0, 0, MARQUEE_DEPTH * 0.5 - MARQUEE_PROUD)
	local part = w.Ctx:Part({
		Name = "ArcadeMarquee", Size = Vector3.new(MARQUEE_SIZE.X, MARQUEE_SIZE.Y, MARQUEE_DEPTH) * scale,
		CFrame = Kit.CFrameToWorld(w.Model, CFrame.new(centre)), Color = C(20, 6, 28), Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local gui = SurfaceGui(part, MARQUEE_CANVAS, 1.5)
	local root = Box(gui, {Size = UDim2.fromScale(1, 1)})
	Gradient(root, C(40, 10, 54), C(14, 4, 22))
	local mq = {Part = part, Bulbs = {}}
	local count = 18
	for row = 0, 1 do
		for i = 0, count - 1 do
			local bulb = Box(root, {
				Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(20 + i * (MARQUEE_CANVAS.X - 40) / (count - 1), row == 0 and 11 or MARQUEE_CANVAS.Y - 11),
			})
			Round(bulb)
			table.insert(mq.Bulbs, bulb)
		end
	end
	local title = Pixel(root, "CUCUMBER CATCH", 24, 62, NEON_PINK)
	New("UIStroke", {Color = C(255, 200, 230), Thickness = 2, Transparency = 0.45}, title)
	mq.Hi = Pixel(root, "HI-SCORE ---", 94, 44, YELLOW)
	w.Marquee = mq
	w.Ctx:OnCleanup(function() SetHidden(w, Kit.Part(w.Model, "MarqueeText"), false) end)
	SetHidden(w, Kit.Part(w.Model, "MarqueeText"), true)
end

local BULB_DIM = C(92, 58, 30)
local BULB_LIT = C(255, 232, 130)
local function UpdateMarquee(w, now)
	local mq = w.Marquee
	local party = w.CelebrateUntil and os.clock() < w.CelebrateUntil
	local step = math.floor(now * (party and 14 or 6))
	for i, bulb in ipairs(mq.Bulbs) do
		local lit = (i + step) % 3 == 0
		local color
		if party then
			color = lit and CONFETTI[(i + step) % #CONFETTI + 1] or BULB_DIM
		else
			color = lit and BULB_LIT or BULB_DIM
		end
		if bulb.BackgroundColor3 ~= color then bulb.BackgroundColor3 = color end
	end
	local hi = HiText(w)
	local text
	if party and now % 0.8 < 0.4 then
		text = "NEW HIGH SCORE!"
	elseif hi then
		text = party and hi or ("HI-SCORE " .. hi)
	else
		text = "HI-SCORE ---  PLAY NOW!"
	end
	SetText(mq.Hi, text)
	local color = (party and now % 0.8 < 0.4) and WHITE or YELLOW
	if mq.Hi.TextColor3 ~= color then mq.Hi.TextColor3 = color end
end

--..World: confetti..--
local function BuildConfetti(w, folder)
	local scale = w.Scale
	local pivot = AuthoredPivot(w.Model, "MarqueeCentre", MARQUEE_FALLBACK)
	local cf = CFrame.new(pivot + Vector3.new(0, 0, -0.3)) * CFrame.Angles(math.rad(35), 0, 0) -- aimed out and up
	local part = w.Ctx:Part({
		Name = "ArcadeConfetti", Size = Vector3.new(2.0, 0.5, 0.2) * scale, CFrame = Kit.CFrameToWorld(w.Model, cf),
		Transparency = 1, Parent = folder,
	})
	w.Emitters = {}
	for _, color in ipairs(CONFETTI) do
		local emitter = New("ParticleEmitter", {
			Texture = CONFETTI_TEXTURE, Color = ColorSequence.new(color), Enabled = false, Rate = 0,
			Lifetime = NumberRange.new(1.6, 2.6), Speed = NumberRange.new(16, 26), SpreadAngle = Vector2.new(38, 38),
			EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(0, -28, 0), Drag = 1.2,
			Size = NumberSequence.new(0.26 * scale), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-360, 360),
			Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1)}),
			LightEmission = 0.2,
		}, part)
		table.insert(w.Emitters, emitter)
	end
	if FunAssets.Sfx.Cheer then w.Cheer = w.Ctx:Sound(part, FunAssets.Sfx.Cheer, {Volume = 0.8}) end
end

--..World: joystick rig..--
local function BuildRig(w)
	local model, scale = w.Model, w.Scale
	local pivot = AuthoredPivot(model, "JoystickPivot", JOYSTICK_FALLBACK)
	local rig = {Stick = Kit.CFrameToWorld(model, CFrame.fromMatrix(pivot, Vector3.xAxis, DECK_NORMAL)), Parts = {}, Sources = {}}
	local folder = LocalFolder()
	for _, spec in ipairs(RIG_PARTS) do
		local source = Kit.Part(model, spec.From)
		if source then
			rig.Sources[source] = true
			local part = w.Ctx:Part({Name = "Arcade" .. spec.Name, Color = source.Color, Material = source.Material, Transparency = 1, CastShadow = true, Parent = folder})
			local size
			if spec.Shape == "Ball" then
				part.Shape = Enum.PartType.Ball
				size = Vector3.one * spec.Diameter
			elseif spec.Shape == "Cyl" then
				part.Shape = Enum.PartType.Cylinder
				size = Vector3.new(spec.Length, spec.Diameter, spec.Diameter)
			else
				size = spec.Size
			end
			part.Size = size * scale
			local entry = {Part = part, Spec = spec}
			if spec.Authored then
				entry.Home = Kit.CFrameToWorld(model, CFrame.new(spec.Authored))
			else
				entry.Rel = CFrame.new(spec.At * scale) * (spec.Shape == "Cyl" and CYL_UP or CFrame.identity)
				entry.Home = rig.Stick * entry.Rel
			end
			part.CFrame = entry.Home
			table.insert(rig.Parts, entry)
		end
	end
	return rig
end

local function SetRig(w, on)
	if on == (w.RigOn == true) then return end
	if on and not w.Rig then w.Rig = BuildRig(w) end
	w.RigOn = on
	if not w.Rig then return end
	for _, entry in ipairs(w.Rig.Parts) do entry.Part.Transparency = on and 0 or 1 end
	for source in pairs(w.Rig.Sources) do SetHidden(w, source, on) end
	if not on then w.Tilt = 0 end
end

local function PoseRig(w, force)
	local rig = w.Rig
	local now = os.clock()
	local tiltCF = CFrame.Angles(0, 0, w.Tilt)
	for _, entry in ipairs(rig.Parts) do
		local spec = entry.Spec
		if spec.Tilt then
			if force or entry.Posed ~= w.Tilt then
				entry.Posed = w.Tilt
				entry.Part.CFrame = rig.Stick * tiltCF * entry.Rel
			end
		elseif spec.Press then
			local down = (w.Presses[spec.Press] or 0) > now
			if force or entry.Down ~= down then
				entry.Down = down
				entry.Part.CFrame = down and entry.Home * CFrame.new(-PRESS_DEPTH * w.Scale, 0, 0) or entry.Home
			end
		end
	end
end

local function UpdateRig(w, dt)
	SetRig(w, w.Game ~= nil or w.PlayerName ~= nil)
	if not w.RigOn then return end
	local target = (w.Game and w.Game.stickInput or w.Stick or 0) * STICK_TILT
	local tilt = w.Tilt + (target - w.Tilt) * (1 - math.exp(-STICK_RATE * dt))
	if math.abs(tilt - target) < 1e-3 then tilt = target end
	w.Tilt = tilt
	PoseRig(w, false)
end

local function PressButton(w, index)
	w.Presses[index] = os.clock() + PRESS_TIME
end

--..World: celebration..--
local function CelebrateWorld(w)
	for _, emitter in ipairs(w.Emitters or {}) do emitter:Emit(CONFETTI_EACH) end
	if w.Cheer then
		w.Cheer.TimePosition = 0
		w.Cheer:Play()
	end
	w.CelebrateUntil = os.clock() + CELEBRATE_TIME
end

--..Game: GUI..--
--.. a side rail: the whole column is the hit area, a round green button with a chevron sits low on it
local function Rail(panel, dir, x)
	local rail = New("TextButton", {
		Name = dir < 0 and "LeftRail" or "RightRail", Size = UDim2.fromOffset(RAIL_W, PH), Position = UDim2.fromOffset(x, FIELD_Y),
		BackgroundColor3 = C(18, 28, 58), BackgroundTransparency = 0.3, BorderSizePixel = 0, Text = "", AutoButtonColor = false,
	}, panel)
	Corner(rail, 18)
	Stroke(rail, 3, DARK, true)
	local knob = Box(rail, {Size = UDim2.fromOffset(104, 104), Position = UDim2.new(0.5, 0, 1, -80), AnchorPoint = Vector2.new(0.5, 0.5)})
	Round(knob)
	Gradient(knob, GREEN.Top, GREEN.Bottom)
	Stroke(knob, 3, DARK, true)
	local rim = Box(knob, {Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1})
	Round(rim)
	New("UIStroke", {Color = GREEN.Highlight, Thickness = 2, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, rim)
	Chevron(knob, dir, 52, WHITE)
	local pop = New("UIScale", {}, knob)
	if not IsTouch() then
		Text(rail, {Text = dir < 0 and "A" or "D", TextSize = 30, Size = UDim2.fromOffset(RAIL_W, 36), Position = UDim2.new(0, 0, 1, -170)}, 2)
	end
	return rail, pop
end

--.. the drawn items (emoji where the brief allows, drawn capsules for the golden / rotten cucumbers)
local function Capsule(parent, top, bottom, edge, rotation)
	local body = Box(parent, {Size = UDim2.fromOffset(46, 22), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = rotation})
	Round(body)
	Gradient(body, top, bottom)
	Stroke(body, 2, edge, true)
	return body
end

local function MakeItem(g, kind)
	local holder = Box(g.ui.Items, {Size = UDim2.fromOffset(ITEM, ITEM), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Position = UDim2.fromOffset(-100, -100)})
	local parts = {}
	if kind == "cuke" or kind == "zombie" then
		Text(holder, {Size = UDim2.fromScale(1, 1), Text = kind == "cuke" and CUKE or ZOMBIE, TextSize = 44}, 0)
	elseif kind == "gold" then
		parts.Glow = Box(holder, {Size = UDim2.fromOffset(62, 62), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C(255, 214, 64), BackgroundTransparency = 0.6})
		Round(parts.Glow)
		local body = Capsule(holder, C(255, 246, 160), C(236, 158, 14), C(140, 84, 0), -35)
		for i = 1, 3 do
			local bump = Box(body, {Size = UDim2.fromOffset(5, 5), Position = UDim2.fromScale(0.25 + i * 0.13, 0.32), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C(255, 255, 215), BackgroundTransparency = 0.2})
			Round(bump)
		end
		Box(body, {Size = UDim2.fromOffset(7, 8), Position = UDim2.new(0, -3, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C(110, 150, 20)})
		parts.Sparkle = Text(holder, {Text = SPARKLE, TextSize = 18, Size = UDim2.fromOffset(20, 20), Position = UDim2.fromScale(0.82, 0.14), AnchorPoint = Vector2.new(0.5, 0.5)}, 0)
	else -- rotten
		local aura = Box(holder, {Size = UDim2.fromOffset(58, 58), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C(120, 170, 40), BackgroundTransparency = 0.8})
		Round(aura)
		local body = Capsule(holder, C(142, 132, 52), C(84, 72, 26), C(44, 34, 10), 30)
		for _, spot in ipairs({{0.3, 0.45, 7}, {0.55, 0.3, 5}, {0.75, 0.6, 8}}) do
			local dot = Box(body, {Size = UDim2.fromOffset(spot[3], spot[3]), Position = UDim2.fromScale(spot[1], spot[2]), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C(64, 48, 18)})
			Round(dot)
		end
		Box(body, {Size = UDim2.fromOffset(7, 8), Position = UDim2.new(1, 3, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C(90, 60, 24)})
		local fly = Box(holder, {Size = UDim2.fromOffset(16, 12), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1})
		for side = -1, 1, 2 do
			local wing = Box(fly, {Size = UDim2.fromOffset(8, 6), Position = UDim2.new(0.5, side * 4, 0.5, -4), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, Rotation = side * 25})
			Round(wing)
		end
		local bug = Box(fly, {Size = UDim2.fromOffset(8, 8), Position = UDim2.fromScale(0.5, 0.6), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C(20, 20, 24)})
		Round(bug)
		parts.Fly = fly
	end
	return holder, parts
end

local function BuildGui(g)
	local ui = {}
	local gui = New("ScreenGui", {Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
	ui.Gui = gui
	Box(gui, {Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.5, Active = true})

	--..Cabinet panel..--
	local panel = Box(gui, {Name = "Cabinet", Size = UDim2.fromOffset(PANEL.X, PANEL.Y), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, PANEL_DROP), Active = true})
	ui.Panel = panel
	ui.Scale = New("UIScale", {}, panel)
	Corner(panel, 28)
	Gradient(panel, CAB_BLUE, CAB_BLUE_DARK)
	Stroke(panel, 6, TMOLD, true)
	local plate = Box(panel, {Size = UDim2.fromOffset(470, 52), Position = UDim2.new(0.5, 0, 0, 12), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = C(34, 12, 44)})
	Corner(plate, 16)
	Stroke(plate, 3, NEON_PINK, true)
	Text(plate, {Size = UDim2.fromScale(1, 1), Text = CUKE .. " CUCUMBER CATCH " .. CUKE, TextSize = 34}, 2.5)
	ui.Close = Button(panel, RED, UDim2.fromOffset(52, 52), UDim2.new(1, -44, 0, 38), "X", 32)
	ui.LeftRail, ui.LeftPop = Rail(panel, -1, 16)
	ui.RightRail, ui.RightPop = Rail(panel, 1, PANEL.X - 16 - RAIL_W)

	--..Playfield..--
	local field = Box(panel, {Name = "Field", Size = UDim2.fromOffset(PW, PH), Position = UDim2.fromOffset(FIELD_X, FIELD_Y), ClipsDescendants = true, Active = true})
	ui.Field = field
	Corner(field, 18)
	Gradient(field, C(22, 30, 60), C(8, 10, 24))
	Stroke(field, 6, DARK, true)
	local rng = Random.new(7)
	for _ = 1, 16 do -- stars
		local star = Box(field, {Size = UDim2.fromOffset(3, 3), Position = UDim2.fromOffset(rng:NextInteger(8, PW - 8), rng:NextInteger(HUD_H + 6, PH - GROUND - 70)), BackgroundColor3 = WHITE, BackgroundTransparency = rng:NextNumber(0.3, 0.75)})
		Round(star)
	end
	local ground = Box(field, {Size = UDim2.fromOffset(PW, GROUND), Position = UDim2.fromOffset(0, PH - GROUND), BackgroundColor3 = WHITE, ZIndex = 2})
	Gradient(ground, C(96, 214, 70), C(44, 140, 44))
	Box(ground, {Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = C(160, 255, 110)})
	ui.Items = Box(field, {Name = "Items", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3})

	--.. the basket
	local basket = Box(field, {Name = "Basket", Size = UDim2.fromOffset(BASKET_W, BASKET_H), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(PW / 2, PH - GROUND + 6), BackgroundTransparency = 1, ZIndex = 4})
	ui.Basket = basket
	ui.BasketScale = New("UIScale", {}, basket)
	local body = Box(basket, {Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0.5, 0, 1, 0), AnchorPoint = Vector2.new(0.5, 1)})
	Corner(body, 14)
	Gradient(body, C(196, 132, 62), C(122, 72, 30))
	Stroke(body, 3, C(70, 40, 14), true)
	for i = 1, 2 do
		Box(body, {Size = UDim2.new(1, -10, 0, 4), Position = UDim2.new(0.5, 0, 0, 8 + i * 11), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = C(222, 168, 92), BackgroundTransparency = 0.25})
	end
	for i = 1, 3 do
		Box(body, {Size = UDim2.new(0, 3, 1, -8), Position = UDim2.new(i / 4, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = C(110, 64, 26), BackgroundTransparency = 0.35})
	end
	local rim = Box(basket, {Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 2), BackgroundColor3 = WHITE})
	Round(rim)
	Gradient(rim, C(232, 164, 84), C(168, 102, 44))
	Stroke(rim, 3, C(70, 40, 14), true)

	ui.Sparks = Box(field, {Name = "Sparks", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6})
	for i = 0, math.floor(PH / 22) do -- scanlines over everything in the tube
		Box(field, {Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromOffset(0, i * 22), BackgroundColor3 = BLACK, BackgroundTransparency = 0.86, ZIndex = 7})
	end

	--.. HUD strip
	local hud = Box(field, {Size = UDim2.fromOffset(PW, HUD_H), BackgroundColor3 = BLACK, BackgroundTransparency = 0.45, ZIndex = 8})
	ui.Score = Text(hud, {Text = CUKE .. " 0", TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(200, HUD_H), Position = UDim2.fromOffset(14, 0)}, 2.5)
	ui.Level = Text(hud, {Text = "LEVEL 1", TextSize = 22, TextColor3 = C(255, 226, 120), Size = UDim2.fromOffset(140, HUD_H), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0)}, 2)
	ui.Hearts = {}
	for i = 1, LIVES do
		local heart = Text(hud, {Text = HEART, TextSize = 28, Size = UDim2.fromOffset(36, HUD_H), Position = UDim2.new(1, -14 - (LIVES - i) * 38, 0, 0), AnchorPoint = Vector2.new(1, 0)}, 0)
		ui.Hearts[i] = {Label = heart, Scale = New("UIScale", {}, heart)}
	end

	--.. banner / flash / countdown / hint
	ui.Banner = Text(field, {Text = "", TextSize = 34, TextColor3 = C(255, 236, 120), Size = UDim2.fromOffset(PW, 44), Position = UDim2.fromOffset(PW / 2, HUD_H + 40), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 9, Visible = false}, 3)
	ui.BannerScale = New("UIScale", {}, ui.Banner)
	ui.Flash = Box(field, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = C(255, 40, 40), BackgroundTransparency = 1, ZIndex = 10})
	ui.Count = Text(field, {Text = "", TextSize = 110, Size = UDim2.fromOffset(PW, 140), Position = UDim2.fromOffset(PW / 2, PH * 0.38), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 11}, 4)
	ui.CountScale = New("UIScale", {}, ui.Count)
	local hint = Box(field, {Size = UDim2.fromOffset(PW - 60, 96), Position = UDim2.fromOffset(PW / 2, PH * 0.66), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = BLACK, BackgroundTransparency = 0.35, ZIndex = 11})
	Corner(hint, 16)
	Text(hint, {Text = "Catch " .. CUKE .. " +1   golden +5!", TextSize = 26, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 8)}, 2)
	Text(hint, {Text = "Dodge " .. ZOMBIE .. " zombies and rotten ones", TextSize = 22, TextColor3 = C(255, 170, 170), Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 42)}, 2)
	Text(hint, {Text = IsTouch() and "Hold the side buttons or drag" or "A / D, arrows, drag or the side buttons", TextSize = 17, TextColor3 = C(200, 214, 240), Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 70)}, 1.5)
	ui.Hint = hint

	--.. game over card
	local card = Box(field, {Size = UDim2.fromOffset(400, 380), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C(26, 30, 50), Visible = false, ZIndex = 12})
	Corner(card, 22)
	Stroke(card, 4, TMOLD, true)
	ui.Card = card
	ui.CardScale = New("UIScale", {}, card)
	Text(card, {Text = "GAME OVER", TextSize = 50, TextColor3 = C(255, 96, 96), Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 14)}, 3)
	Text(card, {Text = "SCORE", TextSize = 22, TextColor3 = C(200, 212, 235), Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 74)}, 2)
	ui.CardScore = Text(card, {Text = "0", TextSize = 64, Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 96)}, 3)
	ui.CardBest = Text(card, {Text = "BEST 0", TextSize = 26, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 164)}, 2)
	ui.CardTag = Text(card, {Text = "", TextSize = 24, TextColor3 = C(255, 226, 90), Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 198)}, 2.5)
	ui.CardHi = Text(card, {Text = "", TextSize = 21, TextColor3 = NEON_CYAN, Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 232)}, 2)
	ui.Again = Button(card, GREEN, UDim2.fromOffset(214, 66), UDim2.new(0.5, -72, 0, 316), "PLAY AGAIN", 28)
	ui.Exit = Button(card, RED, UDim2.fromOffset(120, 66), UDim2.new(0.5, 112, 0, 316), "EXIT", 28)
	return ui
end

--..Game: effects..--
local function MakeSounds(g)
	local list = {
		Blip = FunAssets.Sfx.ArcadeBlip, Coin = FunAssets.Sfx.Coin, Zap = FunAssets.Sfx.Zap, Lose = FunAssets.Sfx.ArcadeLose,
		Win = FunAssets.Sfx.ArcadeWin, Click = FunAssets.Sfx.Click, Whoosh = FunAssets.Sfx.Whoosh,
	}
	g.sounds = {}
	for name, id in pairs(list) do
		local ok, sound = false, nil
		if id then ok, sound = pcall(Kit.MakeSound, id, {Name = "Sfx" .. name, Volume = 0.5}) end
		if ok and sound then
			sound.Parent = g.ui.Gui -- in PlayerGui: plays 2D
			g.sounds[name] = sound
		end
	end
end

local function Play(g, name, speed)
	local sound = g.sounds[name]
	if not sound then return end
	sound.PlaybackSpeed = speed or 1
	sound.TimePosition = 0
	sound:Play()
end

--.. pixel sparks: n little squares flung from (x, y), falling under GRAVITY, fading out
local function Burst(g, x, y, colors, n, power)
	power = power or 1
	for _ = 1, n do
		if #g.sparks >= MAX_SPARKS then return end
		local frame = table.remove(g.sparkPool)
		if not frame then
			frame = Box(g.ui.Sparks, {AnchorPoint = Vector2.new(0.5, 0.5)})
			Corner(frame, 2)
		end
		local size = math.random(6, 11)
		frame.Size = UDim2.fromOffset(size, size)
		frame.BackgroundColor3 = colors[math.random(1, #colors)]
		frame.BackgroundTransparency = 0
		frame.Visible = true
		local angle = math.random() * math.pi * 2
		local speed = (120 + math.random() * 220) * power
		table.insert(g.sparks, {
			Frame = frame, X = x, Y = y, VX = math.cos(angle) * speed, VY = math.sin(angle) * speed - 180 * power,
			Age = 0, Life = 0.45 + math.random() * 0.35, Rot = math.random() * 90, Spin = (math.random() * 2 - 1) * 540,
		})
	end
end

--.. pop text rising from (x, y)
local function PopText(g, x, y, text, color, size)
	local label = Text(g.ui.Sparks, {Text = text, TextSize = size or 30, TextColor3 = color or WHITE, Size = UDim2.fromOffset(160, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y)}, 2.5)
	table.insert(g.pops, {Label = label, Stroke = label:FindFirstChildOfClass("UIStroke"), Scale = New("UIScale", {}, label), X = x, Y = y, Age = 0, Life = 0.75})
end

local function Banner(g, text)
	g.ui.Banner.Text = text
	g.ui.Banner.Visible = true
	g.bannerT = 1.4
end

local function RefreshHud(g)
	g.ui.Score.Text = CUKE .. " " .. tostring(g.score)
	g.ui.Level.Text = "LEVEL " .. tostring(g.level)
	for i, heart in ipairs(g.ui.Hearts) do
		local alive = i <= g.lives
		heart.Label.Text = alive and HEART or HEART_LOST
		heart.Label.TextTransparency = alive and 0 or 0.45
	end
end

local function RefreshCardHi(g)
	local hi = HiText(g.W)
	g.ui.CardHi.Text = hi and ("CABINET HI  " .. hi) or "CABINET HI  ---"
	if g.newHigh then
		g.ui.CardTag.Text = PARTY .. " NEW HIGH SCORE! " .. PARTY
	elseif g.newBest then
		g.ui.CardTag.Text = "NEW BEST!"
	else
		g.ui.CardTag.Text = ""
	end
end

--..Game: rounds..--
local function StartRound(g)
	for _, it in ipairs(g.items) do it.Gui:Destroy() end
	g.items = {}
	g.state = "count"
	g.count = 0
	g.countIndex = 0
	g.t = 0
	g.score = 0
	g.lives = LIVES
	g.streak = 0
	g.level = 1
	g.spawnT = 0.6
	g.goldenCd = 0
	g.inv = 0
	g.newBest = false
	g.newHigh = false
	g.ui.Card.Visible = false
	g.ui.Hint.Visible = true
	g.ui.Count.Text = ""
	g.ui.Count.Visible = true
	RefreshHud(g)
end

local function Difficulty(g)
	return math.min(1, g.t / RAMP_SECONDS)
end

local function Spawn(g)
	local d = Difficulty(g)
	local kind
	if math.random() < Lerp(HAZARD[1], HAZARD[2], d) then
		kind = math.random() < ZOMBIE_SHARE and "zombie" or "rotten"
	elseif g.goldenCd <= 0 and math.random() < GOLDEN_CHANCE then
		kind = "gold"
		g.goldenCd = GOLDEN_COOLDOWN
	else
		kind = "cuke"
	end
	local speed = PH * Lerp(FALL[1], FALL[2], d) * (1 + math.max(0, g.t - RAMP_SECONDS) * OVERTIME) * (0.9 + math.random() * 0.22)
	if kind == "rotten" then speed *= ROTTEN_FALL elseif kind == "gold" then speed *= GOLD_FALL end
	local margin = ITEM * 0.6
	local x = margin + math.random() * (PW - 2 * margin)
	local gui, parts = MakeItem(g, kind)
	local it = {
		Kind = kind, X = x, BaseX = x, Y = -ITEM * 0.5, VY = speed, Gui = gui, Parts = parts, Age = 0,
		Phase = math.random() * math.pi * 2, Spin = (math.random() * 2 - 1) * 70, Rot = math.random(-25, 25),
	}
	if kind == "zombie" and d > 0.25 then
		it.Amp = 18 + 50 * d
		it.Freq = 2 + math.random() * 1.5
	end
	table.insert(g.items, it)
end

local function SendStick(g, force)
	local v = g.stickInput > 0.35 and 1 or (g.stickInput < -0.35 and -1 or 0)
	if v == g.stickSent then return end
	local now = os.clock()
	if not force and now - g.stickSentAt < STICK_SEND_EVERY then return end
	g.stickSent = v
	g.stickSentAt = now
	g.Ctx:Send("Stick", v)
end

local function GameOver(g)
	g.state = "over"
	g.overReady = false
	for _, it in ipairs(g.items) do
		Burst(g, it.X, it.Y, SPARK_MISS, 4, 0.6)
		it.Gui:Destroy()
	end
	g.items = {}
	g.stickInput = 0
	SendStick(g, true)
	if g.score > 0 then g.Ctx:Send("Score", {Score = g.score, Seconds = g.t}) end
	g.newBest = g.score > PersonalBest
	if g.newBest then PersonalBest = g.score end
	Play(g, "Lose")
	task.delay(0.8, function()
		if g.closed or g.state ~= "over" then return end
		g.ui.CardScore.Text = tostring(g.score)
		g.ui.CardBest.Text = "BEST " .. tostring(PersonalBest)
		RefreshCardHi(g)
		g.cardT = 0
		g.ui.CardScale.Scale = 0.6
		g.ui.Card.Visible = true
		if g.newBest and not g.newHigh then Play(g, "Win") end
		task.delay(0.4, function() g.overReady = true end)
	end)
end

--.. an item crossed the basket rim over the basket: true = it is used up
local function Catch(g, it, rimY)
	if it.Kind == "cuke" or it.Kind == "gold" then
		local gold = it.Kind == "gold"
		local value = gold and 5 or 1
		g.score += value
		g.streak += 1
		PopText(g, it.X, rimY - 26, "+" .. value, gold and C(255, 226, 90) or C(190, 255, 150), gold and 40 or 30)
		Burst(g, it.X, rimY, gold and SPARK_GOLD or SPARK_CUKE, gold and 18 or 10, gold and 1.25 or 1)
		Play(g, gold and "Coin" or "Blip", 1 + math.min(g.streak, 12) * 0.03)
		g.squash = 1
		PressButton(g.W, gold and 2 or 1)
		if g.streak % 10 == 0 then Banner(g, "STREAK x" .. g.streak .. "!") end
		RefreshHud(g)
		return true
	end
	if g.inv > 0 then return false end -- blinking after a hit: hazards fall through
	g.lives -= 1
	g.streak = 0
	g.inv = INVULNERABLE
	g.shake = 0.35
	g.flash = 1
	local heart = g.ui.Hearts[g.lives + 1]
	if heart then heart.Scale.Scale = 1.8 end
	PopText(g, it.X, rimY - 30, "OUCH!", C(255, 110, 110), 32)
	Burst(g, it.X, rimY, SPARK_HIT, 16, 1.1)
	Play(g, "Zap")
	PressButton(g.W, 3)
	RefreshHud(g)
	if g.lives <= 0 then GameOver(g) end
	return true
end

--.. an item reached the grass without being caught
local function Landed(g, it)
	Burst(g, it.X, PH - GROUND, SPARK_MISS, 5, 0.5)
	if it.Kind == "cuke" or it.Kind == "gold" then g.streak = 0 end
end

--..Game: frame..--
local function MoveBasket(g, dt)
	local dir = g.pad
	for _, d in pairs(g.keys) do dir += d end
	for _, hold in pairs(g.holds) do dir += hold.Dir end
	dir = math.clamp(dir, -1, 1)
	local half = BASKET_W * 0.5 + 4
	local maxSpeed = BASKET_SPEED * PW
	if g.dragX and dir == 0 then
		local field = g.ui.Field
		local want = (g.dragX - field.AbsolutePosition.X) / math.max(1, field.AbsoluteSize.X) * PW
		want = math.clamp(want, half, PW - half)
		g.basketV = math.clamp((want - g.basketX) * 14, -DRAG_SPEED * PW, DRAG_SPEED * PW)
	else
		g.basketV += (dir * maxSpeed - g.basketV) * (1 - math.exp(-BASKET_ACCEL * dt))
	end
	local x = g.basketX + g.basketV * dt
	if x < half or x > PW - half then
		x = math.clamp(x, half, PW - half)
		g.basketV = 0
	end
	g.basketX = x
	g.stickInput = math.clamp(g.basketV / maxSpeed, -1, 1)
	g.ui.LeftPop.Scale = dir < -0.2 and 0.9 or 1
	g.ui.RightPop.Scale = dir > 0.2 and 0.9 or 1
	g.ui.Basket.Position = UDim2.fromOffset(x, PH - GROUND + 6)
	g.ui.Basket.Visible = g.inv <= 0 or math.floor(g.inv * 12) % 2 == 0
	g.squash = math.max(0, (g.squash or 0) - dt * 6)
	g.ui.BasketScale.Scale = 1 + 0.14 * g.squash
end

local function UpdateItems(g, dt)
	local rimY = PH - GROUND - BASKET_H + 14
	local margin = ITEM * 0.6
	local items = g.items
	for i = #items, 1, -1 do
		local it = items[i]
		it.Age += dt
		local prevY = it.Y
		it.Y += it.VY * dt
		if it.Amp then it.X = math.clamp(it.BaseX + math.sin(it.Phase + it.Age * it.Freq) * it.Amp, margin, PW - margin) end
		local rot
		if it.Kind == "zombie" then
			rot = math.sin(it.Age * 6 + it.Phase) * 16
		else
			it.Rot += it.Spin * dt
			rot = it.Rot
		end
		it.Gui.Position = UDim2.fromOffset(it.X, it.Y)
		it.Gui.Rotation = rot
		if it.Parts.Fly then
			local a = it.Age * 9 + it.Phase
			it.Parts.Fly.Position = UDim2.fromOffset(ITEM * 0.5 + math.cos(a) * 22, ITEM * 0.5 + math.sin(a * 1.3) * 16)
		elseif it.Parts.Glow then
			it.Parts.Glow.BackgroundTransparency = 0.55 + 0.25 * math.sin(it.Age * 8)
			it.Parts.Sparkle.TextTransparency = 0.5 + 0.5 * math.sin(it.Age * 11 + 1)
		end
		local used = false
		if not it.Missed and prevY < rimY and it.Y >= rimY then
			if math.abs(it.X - g.basketX) <= BASKET_W * 0.5 + 8 then
				used = Catch(g, it, rimY)
			end
			it.Missed = not used
		end
		if g.state ~= "play" then return end -- that catch ended the game (GameOver cleared the items)
		if not used and it.Y > PH - GROUND * 0.5 then
			Landed(g, it)
			used = true
		end
		if used then
			it.Gui:Destroy()
			table.remove(items, i)
		end
	end
end

local function UpdateEffects(g, dt)
	for i = #g.sparks, 1, -1 do
		local s = g.sparks[i]
		s.Age += dt
		if s.Age >= s.Life then
			s.Frame.Visible = false
			table.insert(g.sparkPool, s.Frame)
			table.remove(g.sparks, i)
		else
			s.VY += GRAVITY * dt
			s.X += s.VX * dt
			s.Y += s.VY * dt
			s.Rot += s.Spin * dt
			s.Frame.Position = UDim2.fromOffset(s.X, s.Y)
			s.Frame.Rotation = s.Rot
			s.Frame.BackgroundTransparency = (s.Age / s.Life) ^ 2
		end
	end
	for i = #g.pops, 1, -1 do
		local p = g.pops[i]
		p.Age += dt
		local f = p.Age / p.Life
		if f >= 1 then
			p.Label:Destroy()
			table.remove(g.pops, i)
		else
			p.Label.Position = UDim2.fromOffset(p.X, p.Y - 70 * f)
			p.Scale.Scale = 1 + 0.5 * math.max(0, 1 - f * 5)
			local fade = math.max(0, f - 0.5) * 2
			p.Label.TextTransparency = fade
			if p.Stroke then p.Stroke.Transparency = fade end
		end
	end
	for _, heart in ipairs(g.ui.Hearts) do
		if heart.Scale.Scale ~= 1 then heart.Scale.Scale = math.max(1, heart.Scale.Scale - dt * 4) end
	end
	--.. shake + flash + banner + card pop
	if g.shake > 0 then
		g.shake = math.max(0, g.shake - dt)
		local amp = 9 * g.shake / 0.35
		g.ui.Panel.Position = UDim2.new(0.5, (math.random() * 2 - 1) * amp, 0.5, PANEL_DROP + (math.random() * 2 - 1) * amp)
		if g.shake <= 0 then g.ui.Panel.Position = UDim2.new(0.5, 0, 0.5, PANEL_DROP) end
	end
	if g.flash > 0 then
		g.flash = math.max(0, g.flash - dt * 3)
		g.ui.Flash.BackgroundTransparency = 1 - 0.45 * g.flash
	end
	if g.bannerT > 0 then
		g.bannerT -= dt
		g.ui.BannerScale.Scale = 1 + 0.6 * math.max(0, (g.bannerT - 1.2) / 0.2)
		g.ui.Banner.TextTransparency = math.max(0, 0.3 - g.bannerT) / 0.3
		if g.bannerT <= 0 then g.ui.Banner.Visible = false end
	end
	if g.cardT and g.cardT < 1 then
		g.cardT = math.min(1, g.cardT + dt / 0.28)
		local t = g.cardT - 1
		g.ui.CardScale.Scale = 0.6 + 0.4 * (1 + 2.7 * t * t * t + 1.7 * t * t) -- ease out back
	end
end

local function CloseGame(g, notify)
	if g.closed then return end
	g.closed = true
	for _, c in ipairs(g.conns) do c:Disconnect() end
	pcall(function() ContextActionService:UnbindAction(ACTION) end)
	if g.controls then pcall(function() g.controls:Enable() end) end
	if g.ui and g.ui.Gui then g.ui.Gui:Destroy() end
	if g.W.Game == g then g.W.Game = nil end
	if Active == g then Active = nil end
	if notify and g.Ctx:Alive() then g.Ctx:Send("Close") end
end

local function GameFrame(g, dt)
	dt = math.min(dt, MAX_DT)
	if not g.Ctx:Alive() then CloseGame(g, false) return end
	if not g.Ctx:Near(CLOSE_RANGE) then CloseGame(g, true) return end -- walked away or died
	MoveBasket(g, dt)
	if g.state == "count" then
		g.count += dt
		local index = math.floor(g.count / COUNT_STEP) + 1
		if index > #COUNTDOWN then
			g.state = "play"
			g.ui.Count.Visible = false
			g.ui.Hint.Visible = false
		else
			if index ~= g.countIndex then
				g.countIndex = index
				g.ui.Count.Text = COUNTDOWN[index]
				Play(g, index == #COUNTDOWN and "Whoosh" or "Click", index == #COUNTDOWN and 1 or 1.2)
			end
			local f = (g.count % COUNT_STEP) / COUNT_STEP
			g.ui.CountScale.Scale = 1 + 0.8 * (1 - f) ^ 3
			g.ui.Count.TextTransparency = f > 0.75 and (f - 0.75) * 4 or 0
		end
	elseif g.state == "play" then
		g.t += dt
		g.goldenCd -= dt
		g.inv = math.max(0, g.inv - dt)
		local level = 1 + math.floor(g.t / LEVEL_SECONDS)
		if level > g.level then
			g.level = level
			Banner(g, "SPEED UP!")
			Play(g, "Whoosh", 1.15)
			RefreshHud(g)
		end
		g.spawnT -= dt
		if g.spawnT <= 0 then
			Spawn(g)
			g.spawnT += Lerp(SPAWN_EVERY[1], SPAWN_EVERY[2], Difficulty(g)) * (0.85 + math.random() * 0.3)
		end
		UpdateItems(g, dt)
	end
	UpdateEffects(g, dt)
	SendStick(g, false)
	local now = os.clock()
	if now - g.aliveAt >= ALIVE_EVERY then
		g.aliveAt = now
		g.Ctx:Send("Alive")
	end
end

--..Game: input..--
local function Again(g)
	if g.state ~= "over" or not g.overReady then return end
	Play(g, "Click")
	StartRound(g)
end

local function BindInput(g)
	local ui = g.ui
	ContextActionService:BindActionAtPriority(ACTION, function(_, state, input)
		local key = input.KeyCode
		if key == K.Thumbstick1 then
			local x = input.Position.X
			g.pad = math.abs(x) > 0.2 and x or 0
		elseif state == Enum.UserInputState.Begin then
			if LEFT_KEYS[key] then
				g.keys[key] = -1
			elseif RIGHT_KEYS[key] then
				g.keys[key] = 1
			elseif AGAIN_KEYS[key] then
				Again(g)
			elseif EXIT_KEYS[key] then
				CloseGame(g, true)
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			g.keys[key] = nil
		end
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, table.unpack(SUNK_KEYS))

	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	for _, pair in ipairs({{ui.LeftRail, -1}, {ui.RightRail, 1}}) do
		table.insert(g.conns, pair[1].InputBegan:Connect(function(input)
			if isPress(input) then g.holds[input] = {Dir = pair[2], Mouse = input.UserInputType == Enum.UserInputType.MouseButton1} end
		end))
	end
	table.insert(g.conns, ui.Field.InputBegan:Connect(function(input)
		if isPress(input) then
			g.drag = input
			g.dragX = input.Position.X
		end
	end))
	table.insert(g.conns, UserInputService.InputChanged:Connect(function(input)
		if not g.drag then return end
		local mouseDrag = g.drag.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
		if input == g.drag or mouseDrag then g.dragX = input.Position.X end
	end))
	table.insert(g.conns, UserInputService.InputEnded:Connect(function(input)
		local mouse = input.UserInputType == Enum.UserInputType.MouseButton1
		g.holds[input] = nil
		if mouse then
			for key, hold in pairs(g.holds) do
				if hold.Mouse then g.holds[key] = nil end
			end
		end
		if g.drag and (input == g.drag or (mouse and g.drag.UserInputType == Enum.UserInputType.MouseButton1)) then
			g.drag = nil
			g.dragX = nil
		end
	end))
	table.insert(g.conns, ui.Close.Activated:Connect(function() CloseGame(g, true) end))
	table.insert(g.conns, ui.Exit.Activated:Connect(function() CloseGame(g, true) end))
	table.insert(g.conns, ui.Again.Activated:Connect(function() Again(g) end))
end

local function Fit(g)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local s = math.min((viewport.X - 24) / PANEL.X, (viewport.Y - 24 - PANEL_DROP * 2) / PANEL.Y)
	g.ui.Scale.Scale = math.clamp(s, 0.35, 1.2)
end

--.. the PlayerModule's controls, so the avatar can't walk off while the keys drive the basket
local function Controls()
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then return nil end
	local ok, controls = pcall(function() return require(module):GetControls() end)
	return ok and controls or nil
end

local function OpenGame(w)
	local g = {
		W = w, Ctx = w.Ctx, conns = {}, keys = {}, holds = {}, pad = 0, drag = nil, dragX = nil,
		items = {}, sparks = {}, sparkPool = {}, pops = {}, basketX = PW / 2, basketV = 0, squash = 0,
		shake = 0, flash = 0, bannerT = 0, stickInput = 0, stickSent = 0, stickSentAt = 0, aliveAt = os.clock(),
		state = "count", t = 0, score = 0, lives = LIVES, level = 1, inv = 0,
	}
	g.ui = BuildGui(g)
	MakeSounds(g)
	Fit(g)
	local camera = workspace.CurrentCamera
	if camera then table.insert(g.conns, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() Fit(g) end)) end
	BindInput(g)
	g.controls = Controls()
	if g.controls then pcall(function() g.controls:Disable() end) end
	local humanoid = w.Ctx:LocalCharacter()
	if humanoid then table.insert(g.conns, humanoid.Died:Connect(function() CloseGame(g, true) end)) end
	g.ui.Gui.Parent = player:WaitForChild("PlayerGui")
	w.Game = g
	Active = g
	StartRound(g)
	table.insert(g.conns, RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(GameFrame, g, dt)
		if not ok then
			warn("[ArcadeCabinet] game frame: " .. tostring(err))
			CloseGame(g, true)
		end
	end))
	return g
end

--..Behaviour..--
function B.Client(model, ctx)
	local w = {Model = model, Ctx = ctx, Scale = ctx.Scale, Hide = {}, Presses = {}, Tilt = 0, Stick = 0}
	ctx.Arcade = w
	local folder = LocalFolder()
	BuildScreen(w, folder)
	BuildMarquee(w, folder)
	BuildConfetti(w, folder)

	ctx:OnState("HiScore", function(v)
		w.Hi = tonumber(v)
		RefreshScreenHi(w)
		if w.Game then RefreshCardHi(w.Game) end
	end)
	ctx:OnState("HiName", function(v)
		w.HiName = type(v) == "string" and v or nil
		RefreshScreenHi(w)
		if w.Game then RefreshCardHi(w.Game) end
	end)
	ctx:OnState("Player", function(v) w.PlayerName = (type(v) == "string" and v ~= "") and v or nil end)
	ctx:OnState("Stick", function(v) w.Stick = tonumber(v) or 0 end)

	local now = Kit.Now()
	UpdateScreen(w, now)
	UpdateMarquee(w, now)
	local screenT, marqueeT, hideT = 0, 0, 0
	ctx:Step(function(dt, serverNow)
		UpdateRig(w, dt)
		screenT += dt
		if screenT >= 1 / SCREEN_FPS then
			screenT = 0
			UpdateScreen(w, serverNow)
		end
		marqueeT += dt
		if marqueeT >= 1 / MARQUEE_FPS then
			marqueeT = 0
			UpdateMarquee(w, serverNow)
		end
		hideT += dt
		if hideT >= HIDE_CHECK then
			hideT = 0
			Reassert(w)
		end
	end)

	return function()
		if w.Game then CloseGame(w.Game, false) end
		for part in pairs(w.Hide) do
			if part.Parent then part.LocalTransparencyModifier = 0 end
		end
		w.Hide = {}
	end
end

function B.OnEvent(model, action, payload, ctx)
	local w = ctx.Arcade
	if not w then return end
	if action == "Open" then
		if Active and not Active.closed then
			if Active.W == w then return end -- already playing this cabinet
			CloseGame(Active, true)
		end
		if not ctx:Near(CLOSE_RANGE) then return end
		OpenGame(w)
	elseif action == "NewHigh" then
		CelebrateWorld(w)
		local g = w.Game
		if g and type(payload) == "table" and payload.UserId == player.UserId then
			g.newHigh = true
			RefreshCardHi(g)
			Play(g, "Win")
			Burst(g, PW / 2, PH * 0.3, CONFETTI, 40, 1.5)
		end
	end
end

return B
