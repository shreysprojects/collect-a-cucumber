--[[
	GamingDesk  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds HomeOffice
	Client half of the GAMING DESK (server half: ServerStorage.FunBehaviours.GamingDesk; notes/GamingDesk.md).
	State from the server: Fun_Player (UserId, 0 = empty, -1 = an NPC), Fun_Seed + Fun_Since (the current / last run:
	its course seed and the server time it started), Fun_Ended (server time the last run ended; a run is LIVE while
	Fun_Since > Fun_Ended), Fun_EndTick (the ended run's last sim tick as the gamer reported it; 0 = not known),
	Fun_Final (the last run's score), Fun_Best. Events: "Input" {s, c, n} (the gamer's inputs, relayed to everyone)
	and "Events" {s, c, n} (the whole list, the answer to a "Sync").

	CUKE RUN (2026-09-24, user: "make the gaming desk make u play the actual game instead of just show a video")
	  A real endless runner. Sitting in the desk chair (prompt "Game") opens a GUI for the gamer (CukeRun ScreenGui):
	  the same pixel world the monitor draws (one shared scene builder + DrawWorld), READY? / GO!, then the cucumber
	  hero runs faster and faster: JUMP (Space / W / Up / click / tap / pad A; hold = higher), DUCK (S / Down / pad B
	  or DPadDown; in the air = fall fast) under the flying drones, coins +50, distance = points, a hit = GAME OVER
	  card (score, best, desk HI, PLAY AGAIN / EXIT). While it is open the keys are sunk (ContextActionService above
	  the PlayerModule) and the PlayerModule controls are off (that also hides the touch jump button), so nothing
	  makes the avatar jump out of the chair; only EXIT / X / Backspace (or dying / losing the seat) stands them up.
	SIMULATION  deterministic and fixed-step (TICK_RATE): the course comes from Random.new(Fun_Seed) (gaps between
	  obstacles always longer than a full jump + a reaction time at the current speed), the hero from the list of
	  input events {tick, kind}. The gamer's client appends each press / release at the next tick, plays it at once
	  and sends it ("Input" {s, t, k} or {s, e = {...}}, batched at most every SEND_GAP s); the server relays the list
	  to everyone and keeps it for late joiners ("Sync" -> "Events"). Every other client re-simulates the run from
	  those events SPECTATOR_DELAY s behind real time (checkpoints every MARK_TICKS; a late event rolls back to the
	  checkpoint before it; at most SIM_BUDGET ticks per frame), so each monitor shows the ACTUAL run. The gamer's
	  own monitor draws the GUI's simulation. Both clocks are the SERVER clock (sim time = Kit.Now() - Fun_Since -
	  READY): a hitch on the gamer's client skips time (the missed ticks run at once) instead of pausing the run -
	  a paused gamer would fall behind every replay for good, so each later input would arrive after the replay
	  had passed it (rollbacks, false crashes). At the crash the client sends "Over" {s, score, seconds} (resent
	  until the server ends the run); the server checks it is plausible and sets Final / Best / EndTick / Ended, and
	  a replay of an ended run stops at EndTick (rolling back if it ran past it).
	SCREEN  each monitor panel (ScreenL / ScreenC / ScreenR) gets an invisible LOCAL part laid just in front of it and
	        its ScreenArt* picture, carrying a SurfaceGui that shows its own slice of ONE scene, so the landscape runs
	        on across the curve: sky bands, a sun (a moon while workspace.IsNight), parallax clouds and hills,
	        scrolling ground, crates / double crates / spike blocks / slimes / drones, spinning coins, the hero:
	          attract  nobody playing: the old self-playing demo, the title, "SIT TO PLAY" blinking, the desk's HI
	          ready    READY s after a run starts: "READY?" -> "GO!" (Sfx.ArcadeBlip)
	          run      the gamer's real run: SCORE, "P1 <name>", COINS, "+50" pops (Sfx.Coin), a keyboard clack
	                   (Sfx.Click) for every press, a thump (Sfx.Thump) at the crash
	          over     the crash frozen, "GAME OVER", the score and "NEW HI-SCORE!" (Sfx.ArcadeWin for a new best,
	                   else Sfx.ArcadeLose) - while the gamer stays seated, and OVER_TIME s after they get up
	        The centre screen lights the gamer with a soft SurfaceLight (brighter while playing).
	RGB     every RGB* Neon part flows through the rainbow as a wave along the desk (faster while someone plays),
	        plus one rainbow PointLight under the desk (Pivot_RGBGlow)
	CHAIR   the Swivel* parts turn about Pivot_ChairSwivel (a damped spring): round to face the desk
	        (State_ChairSitYaw) when someone sits, rocking a little while they play, and a full spin back out to
	        State_ChairIdleYaw (the shipped pose) when they get up. Every Swivel* part is authored CanCollide =
	        false (build_GamingDesk.py), so the spin can never shove / fling the character that just got up
	The screens redraw at SCREEN_FPS and the RGB at RGB_FPS; the chair poses every frame only while it moves; the GUI
	draws every frame (its own RenderStepped, like the arcade). No Instance is made per frame: obstacle / coin frames
	are pooled. Cleanup closes the GUI, puts the chair back as shipped (relative to the Hitbox) and the RGB colours.
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

local LocalPlayer = Players.LocalPlayer

--..Config: monitor..--
local LOCAL_FOLDER = "FunBuildLocal"   -- client-only workspace folder for the screen + glow parts (shared with the TV)
local PANEL_NAMES = {"ScreenL", "ScreenC", "ScreenR"}
local CENTRE_PANEL = "ScreenC"
local ART_PREFIX = "ScreenArt"         -- the static picture on the panels (the local screens sit in front of it)
local PPS = 90                         -- SurfaceGui pixels per stud
local BRIGHTNESS = 1.15                -- SurfaceGui brightness (LightInfluence 0)
local GUI_MAX_DISTANCE = 220           -- studs: the SurfaceGuis stop drawing beyond this
local GAP = 0.012                      -- authored studs between the front-most layer and the local screen face
local THICK = 0.04                     -- authored thickness of the (invisible) screen parts
local SCREEN_FPS = 30
local SCREEN_RANGE = 150               -- studs (camera): the screens only redraw within this
local LIGHT_COLOR = Color3.fromRGB(165, 215, 255)
local LIGHT_RANGE, LIGHT_ANGLE = 9, 110
local LIGHT_IDLE, LIGHT_PLAY = 0.55, 1.1
local SEAT_NAME = "GamingDeskSeat"     -- the server half's Seat

--..Config: the game. TICK_RATE / READY / the speeds / the course / the points MUST match the server half's
--.. plausibility numbers (RATE = VMAX / PX_PER_POINT + COIN_POINTS / (AIR_TIME + REACT_TIME), rounded up)
--.. Units: art pixels (the hero is 6 x 10) and seconds.
local TICK_RATE = 120                  -- fixed simulation steps per second
local DT = 1 / TICK_RATE
local READY = 1.6                      -- s of "READY?" / "GO!": sim time 0 = Fun_Since + READY
local V0, VMAX = 34, 72                -- run speed (art px / s) at the start line / from RAMP_DIST on
local RAMP_DIST = 4000
local GRAVITY = 520
local JUMP_V = 91.2                    -- a tap peaks at JUMP_V^2 / 2g = 8 px
local HOLD_GRAVITY = 150               -- while JUMP is held and the hero rises, for at most HOLD_TICKS: peak ~15 px
local HOLD_TICKS = 14
local FAST_FALL = 3                    -- gravity x this while DUCK is held in the air
local BUFFER_TICKS = 12                -- a jump pressed this many ticks before landing jumps on landing
local HERO_HALF = 1.8                  -- hit box: half width (drawn 6), height standing / ducking (drawn 10 / 6)
local HERO_H, DUCK_H = 9.2, 5.4
local FIRST = 90                       -- start line -> first obstacle
local AIR_TIME, REACT_TIME = 0.5, 0.45 -- a full jump's airtime + a reaction time = the least running between two obstacles
local GAP_VAR = 0.9                    -- ... plus up to this many seconds more (random)
local DRONE_FROM, DOUBLE_FROM = 500, 1500 -- course px: drones (duck!) and double crates from here on
local DRONE_SHARE, DOUBLE_SHARE = 0.22, 0.15
local COIN_CHANCE, COIN_HIGH_SHARE = 0.65, 0.45
local COIN_LOW, COIN_HIGH = 3, 16      -- coin centre heights: run through it / jump for it
local COIN_R = 1.5
local PX_PER_POINT = 3                 -- distance points
local COIN_POINTS = 50
local MAX_SCORE = 999999
--.. obstacle kinds: drawn width, hit box half width / bottom / top (px above the ground)
local KINDS = {
	crate = {W = 5, Half = 1.9, Bottom = 0, Top = 4.6},
	spike = {W = 5, Half = 1.7, Bottom = 0, Top = 5.0},
	slime = {W = 5, Half = 2.0, Bottom = 0, Top = 3.6},
	double = {W = 10, Half = 4.4, Bottom = 0, Top = 4.6},
	drone = {W = 7, Half = 2.4, Bottom = 6.3, Top = 11},
}
local DRONE_DRAW_TOP = 11.5            -- the drone sprite's top, px above the ground
local EVENT_NAMES = {[0] = "jump", [1] = "jumpUp", [2] = "duck", [3] = "duckUp"}
local EV_JUMP, EV_JUMP_UP, EV_DUCK, EV_DUCK_UP = 0, 1, 2, 3

--.. replays (the monitor of every client that is not the gamer)
local SPECTATOR_DELAY = 0.3            -- s the monitor runs behind real time (inputs arrive before they are needed)
local MARK_TICKS = 60                  -- checkpoint every this many ticks
local MAX_MARKS = 40                   -- (20 s of rollback; older late events re-simulate from the start)
local SIM_BUDGET = 400                 -- ticks per frame at most (~1.5 ms; a late joiner fast-forwards ~100 s of run a second)
local LIVE_TICKS = 30                  -- an advance longer than this is a catch-up: no sounds
local SYNC_RETRY = 2                   -- s between "Sync" requests

--.. the old self-playing attract loop (pure function of Kit.Now())
local IDLE_SPEED = 9                   -- attract mode
local IDLE_WRAP = 3600                 -- s: the attract run restarts every hour (keeps the numbers small)
local IDLE_SPACING = 34                -- between obstacles; a coin halfway between two
local IDLE_JITTER = 5                  -- +/- per obstacle
local JUMP_LEN, JUMP_H = 20, 12        -- an attract jump: world units long (centred on the obstacle), px high
local OVER_TIME = 4                    -- s of GAME OVER after the gamer gets up
local POPUP_TIME = 0.6                 -- s a "+50" floats up

--.. the scene, in art pixels (U screen pixels each)
local ART_H = 36                       -- scene height at least (U = screen height / ART_H; the rest is more sky)
local GROUND_H = 9                     -- ground band (grass + dirt)
local BIG_Y = {idle = 2.2, other = 9}  -- art-pixel rows of the big text (the title sits above the hero's jumps)
local SMALL_Y = {idle = 10.2, other = 17.5}
local HERO_AT = 0.28                   -- hero x as a share of the centre screen
local OBSTACLE_POOL, COIN_POOL = 8, 8

local SKY_DAY = {Color3.fromRGB(92, 172, 255), Color3.fromRGB(124, 196, 255), Color3.fromRGB(166, 222, 255)}
local SKY_NIGHT = {Color3.fromRGB(16, 22, 56), Color3.fromRGB(28, 36, 82), Color3.fromRGB(46, 54, 108)}
local SUN_DAY = {Color3.fromRGB(255, 206, 60), Color3.fromRGB(255, 244, 168)}
local SUN_NIGHT = {Color3.fromRGB(214, 220, 240), Color3.fromRGB(255, 255, 255)}
local NIGHT_DIM = 0.55                 -- everything else at night
local C = {
	Cloud = Color3.fromRGB(255, 255, 255),
	HillA = Color3.fromRGB(64, 160, 118), HillB = Color3.fromRGB(88, 184, 132), HillC = Color3.fromRGB(52, 140, 104),
	Grass = Color3.fromRGB(86, 204, 64), GrassDark = Color3.fromRGB(46, 140, 46),
	Dirt = Color3.fromRGB(152, 98, 52), DirtDark = Color3.fromRGB(118, 72, 38),
	Crate = Color3.fromRGB(196, 130, 62), CrateDark = Color3.fromRGB(122, 76, 34),
	Spike = Color3.fromRGB(176, 186, 202), SpikeDark = Color3.fromRGB(112, 120, 136),
	Slime = Color3.fromRGB(226, 58, 58), Eye = Color3.fromRGB(255, 255, 255), Ink = Color3.fromRGB(24, 24, 30),
	Drone = Color3.fromRGB(128, 94, 214), DroneDark = Color3.fromRGB(74, 54, 138), DroneLight = Color3.fromRGB(255, 70, 70),
	Rotor = Color3.fromRGB(70, 74, 86),
	Coin = Color3.fromRGB(255, 208, 48), CoinShine = Color3.fromRGB(255, 246, 176),
	Hero = Color3.fromRGB(84, 194, 72), HeroDark = Color3.fromRGB(44, 128, 44), Band = Color3.fromRGB(230, 34, 34),
	Leg = Color3.fromRGB(38, 110, 40),
	Text = Color3.fromRGB(255, 255, 255), Title = Color3.fromRGB(255, 214, 64), Green = Color3.fromRGB(157, 255, 36),
	Outline = Color3.fromRGB(12, 12, 18), TitleOutline = Color3.fromRGB(170, 30, 30),
}
local HILLS = {{D = 30, Color = "HillA"}, {D = 20, Color = "HillB"}, {D = 26, Color = "HillC"}} -- art-pixel diameters
local FONT = Enum.Font.Arcade

--.. RGB
local LOOK = {} -- 2026-09-24: look / layout constants folded into one table (Studio allows 200 top-level locals)
LOOK.RGB_PREFIX = "RGB"
LOOK.RGB_FPS = 20
LOOK.RGB_RATE_IDLE, LOOK.RGB_RATE_PLAY = 0.1, 0.32 -- hue turns per second
LOOK.RGB_WAVE = 0.6                   -- hue spread along the desk (0..1 over its width)
LOOK.RGB_SAT = 0.85
LOOK.GLOW_RANGE, LOOK.GLOW_BRIGHTNESS = 10, 1.4
LOOK.GLOW_FALLBACK = Vector3.new(0, 2.3, 1.5) -- authored, if Pivot_RGBGlow is missing
local DESK_WIDTH = 7.2                 -- authored, for the wave

--.. chair
LOOK.SWIVEL_PREFIX = "Swivel"
LOOK.SWIVEL_FALLBACK = Vector3.new(0, 0, -2) -- authored, if Pivot_ChairSwivel is missing
LOOK.DEFAULT_IDLE_YAW, LOOK.DEFAULT_SIT_YAW = 32, 0
LOOK.SPRING_K, LOOK.SPRING_C = 24, 7       -- turning to face the desk: a little overshoot
LOOK.ROCK_DEG, LOOK.ROCK_HZ = 2.5, 0.35    -- rocking while playing
LOOK.SPIN_OUT = 360                   -- the extra turn when the gamer gets up ...
LOOK.SPIN_TIME = 1.6                  -- ... slowing to a stop over this many seconds (constant friction)
local MAX_DT = 1 / 15
local WAKE_GAP = 0.5                   -- s without a Step (camera away) -> snap, no sounds

--.. sounds
local KEYS_RANGE = 45                  -- studs (camera) for keyboard clacks / game sounds
local KEYS_VOLUME = 0.14
local GAME_VOLUME = 0.3

--..Config: the gamer's GUI (the arcade's look: CucumberCatch)..--
LOOK.GUI_NAME = "CukeRun"
LOOK.GUI_FONT = Enum.Font.FredokaOne
LOOK.PANEL = Vector2.new(940, 600)    -- design px; a UIScale fits it to the viewport
LOOK.PANEL_DROP = 18                  -- px the panel sits below centre (clear of the top bar)
LOOK.VIEW_ART = Vector2.new(88, 36)   -- the game view in art px ...
LOOK.GUI_U = 10                       -- ... at this many design px each (880 x 360)
LOOK.VIEW_X, LOOK.VIEW_Y = 30, 78
LOOK.GUI_HERO_AT = 0.22
LOOK.HUD_H = 46
LOOK.CONTROLS_Y = 452
local SEND_GAP = 0.15                  -- s between "Input" sends (the framework allows 12 actions / s)
local SEND_MAX = 24                    -- events per send
local OVER_RESEND = 1.5                -- s: "Over" again while the server still has the run live
local AGAIN_RESEND = 2.5
local CARD_DELAY, CARD_READY = 0.8, 0.45
local SEAT_GRACE = 0.6                 -- s the seat may look lost (replication) before the GUI closes
local CLOSE_RANGE = 20
local ACTION = "CukeRunControls"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 100
local K = Enum.KeyCode
local JUMP_KEYS = {[K.Space] = true, [K.W] = true, [K.Up] = true, [K.ButtonA] = true, [K.DPadUp] = true}
local DUCK_KEYS = {[K.S] = true, [K.Down] = true, [K.DPadDown] = true, [K.ButtonB] = true}
local AGAIN_KEYS = {[K.Space] = true, [K.Return] = true, [K.ButtonA] = true}
local EXIT_KEYS = {[K.Backspace] = true}
local CARD_EXIT_KEYS = {[K.ButtonB] = true}
local SUNK_KEYS = {K.Space, K.W, K.A, K.S, K.D, K.Up, K.Down, K.Left, K.Right, K.Return, K.Backspace,
	K.ButtonA, K.ButtonB, K.ButtonX, K.ButtonY, K.DPadUp, K.DPadDown, K.DPadLeft, K.DPadRight, K.Thumbstick1}
LOOK.WHITE = Color3.fromRGB(255, 255, 255)
LOOK.BLACK = Color3.fromRGB(0, 0, 0)
LOOK.DARK = Color3.fromRGB(23, 26, 32)
LOOK.GREEN = {Top = Color3.fromRGB(157, 255, 36), Bottom = Color3.fromRGB(69, 255, 0), Highlight = Color3.fromRGB(208, 255, 106)}
LOOK.RED = {Top = Color3.fromRGB(255, 100, 100), Bottom = Color3.fromRGB(230, 30, 30), Highlight = Color3.fromRGB(255, 196, 196)}
LOOK.DESK_TOP, LOOK.DESK_BOTTOM = Color3.fromRGB(46, 48, 62), Color3.fromRGB(22, 23, 31)
LOOK.DESK_TRIM = Color3.fromRGB(217, 68, 60)
LOOK.NEON_CYAN = Color3.fromRGB(77, 210, 255)
LOOK.GOLD = Color3.fromRGB(255, 214, 64)
LOOK.CUKE = "\u{1F952}"
LOOK.PARTY = "\u{1F389}"

--..Shared..--
local Active = nil      -- the open game (one at a time on this client)
local PersonalBest = 0  -- this session, any desk

local B = {}
B.Keys = {"GamingDesk"}
B.StepRange = 170

--..Helpers..--
local function New(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function Try(inst, prop, value)
	pcall(function() inst[prop] = value end)
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

local function HalfExtent(part, dir)
	local cf, s = part.CFrame, part.Size
	return 0.5 * (math.abs(cf.XVector:Dot(dir)) * s.X + math.abs(cf.YVector:Dot(dir)) * s.Y + math.abs(cf.ZVector:Dot(dir)) * s.Z)
end

local function Dim(color, k)
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

--.. a deterministic 0..1 per integer (same on every client; the attract loop)
local function Hash(k, salt)
	local v = math.sin(k * 12.9898 + salt * 78.233) * 43758.5453
	return v - math.floor(v)
end

local function Pad(n)
	return string.format("%06d", math.clamp(math.floor(n), 0, MAX_SCORE))
end

local function Finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function SetText(label, text)
	if label.Text ~= text then label.Text = text end
end

local function IsTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

--..Simulation: the course (a pure function of the seed, generated lazily in one fixed order)..--
local function Speed(x)
	return V0 + (VMAX - V0) * math.min(1, x / RAMP_DIST)
end

local function NewCourse(seed)
	return {Rng = Random.new(seed), X = {}, Kind = {}, CoinX = {}, CoinY = {}, N = 0, NextX = FIRST, NextKind = nil}
end

--.. always three draws, whatever comes out (keeps the stream in step)
local function PickKind(course, x)
	local a, b, c = course.Rng:NextNumber(), course.Rng:NextNumber(), course.Rng:NextNumber()
	if x >= DRONE_FROM and a < DRONE_SHARE then return "drone" end
	if x >= DOUBLE_FROM and b < DOUBLE_SHARE then return "double" end
	return c < 0.42 and "crate" or (c < 0.74 and "spike" or "slime")
end

--.. obstacles (and the coin in the gap after each) up to course x
local function Extend(course, uptoX)
	while course.N == 0 or course.X[course.N] < uptoX do
		local x = course.NextX
		local kind = course.NextKind or PickKind(course, x)
		local n = course.N + 1
		course.N = n
		course.X[n], course.Kind[n] = x, kind
		local nextKind = PickKind(course, x)
		local v = Speed(x)
		local gap = (KINDS[kind].W + KINDS[nextKind].W) * 0.5 + v * (AIR_TIME + REACT_TIME) + course.Rng:NextNumber() * v * GAP_VAR
		local coinRoll, coinHigh = course.Rng:NextNumber(), course.Rng:NextNumber()
		if coinRoll < COIN_CHANCE then
			course.CoinX[n], course.CoinY[n] = x + gap * 0.5, coinHigh < COIN_HIGH_SHARE and COIN_HIGH or COIN_LOW
		else
			course.CoinX[n], course.CoinY[n] = false, false
		end
		course.NextX, course.NextKind = x + gap, nextKind
	end
end

--..Simulation: the hero (fixed step; only + - * / and comparisons, so every client gets the same bits)..--
local SIM_FIELDS = {"N", "X", "Y", "VY", "Ground", "JumpHeld", "DuckHeld", "Hold", "Buffer", "Dead", "DeadTick",
	"Coins", "CoinTick", "Obs", "Coin", "Ev", "Jumps", "Presses"}

local function NewSim()
	return {N = 0, X = 0, Y = 0, VY = 0, Ground = true, JumpHeld = false, DuckHeld = false, Hold = HOLD_TICKS, Buffer = 0,
		Dead = false, DeadTick = 0, Coins = 0, CoinTick = -1e9, Obs = 1, Coin = 1, Ev = 1, Jumps = 0, Presses = 0, Got = {}}
end

local function Snapshot(s)
	local m = {}
	for _, k in ipairs(SIM_FIELDS) do m[k] = s[k] end
	return m
end

--.. s.Got (coin index -> collected) is shared, not copied: entries at or past s.Coin are rewritten when re-simulated
local function Restore(s, m)
	for _, k in ipairs(SIM_FIELDS) do s[k] = m[k] end
end

local function Score(s)
	return math.min(MAX_SCORE, math.floor(s.X / PX_PER_POINT) + COIN_POINTS * s.Coins)
end

local function Jump(s)
	s.VY, s.Ground, s.Hold, s.Buffer = JUMP_V, false, 0, 0
	s.Jumps += 1
end

local function HeroHeight(s)
	return (s.Ground and s.DuckHeld) and DUCK_H or HERO_H
end

--.. one tick: the inputs stamped with it, running, gravity, then obstacles and coins
local function StepSim(s, course, ticks, kinds)
	local n = s.N + 1
	local i = s.Ev
	while ticks[i] and ticks[i] <= n do
		local k = kinds[i]
		if k == EV_JUMP then
			s.JumpHeld = true
			s.Presses += 1
			if s.Ground then Jump(s) else s.Buffer = BUFFER_TICKS end
		elseif k == EV_JUMP_UP then
			s.JumpHeld = false
			if not s.Ground then s.Hold = HOLD_TICKS end
		elseif k == EV_DUCK then
			s.DuckHeld = true
			s.Presses += 1
		elseif k == EV_DUCK_UP then
			s.DuckHeld = false
		end
		i += 1
	end
	s.Ev = i
	s.X += Speed(s.X) * DT
	if not s.Ground then
		local g
		if s.JumpHeld and s.VY > 0 and s.Hold < HOLD_TICKS and not s.DuckHeld then
			g = HOLD_GRAVITY
			s.Hold += 1
		else
			g = s.DuckHeld and GRAVITY * FAST_FALL or GRAVITY
		end
		s.VY -= g * DT
		s.Y += s.VY * DT
		if s.Y <= 0 then
			s.Y, s.VY, s.Ground = 0, 0, true
			if s.Buffer > 0 then Jump(s) end
		end
	end
	if s.Buffer > 0 then s.Buffer -= 1 end
	s.N = n

	--.. obstacles: the first one not yet behind the hero
	local h = HeroHeight(s)
	local left, right = s.X - HERO_HALF, s.X + HERO_HALF
	Extend(course, s.X + 40)
	local j = s.Obs
	while true do
		local kind = KINDS[course.Kind[j]]
		local ox = course.X[j]
		if ox + kind.Half < left then
			j += 1
		else
			if ox - kind.Half < right and s.Y < kind.Top and s.Y + h > kind.Bottom then
				s.Dead, s.DeadTick = true, n
			end
			break
		end
	end
	s.Obs = j

	--.. coins: resolved in order (collected, or missed once behind the hero)
	local c = s.Coin
	while c <= course.N do
		local cx = course.CoinX[c]
		if not cx then
			c += 1
		elseif cx + COIN_R < left then
			s.Got[c] = false
			c += 1
		elseif cx - COIN_R < right then
			local cy = course.CoinY[c]
			if s.Y < cy + COIN_R and s.Y + h > cy - COIN_R then
				s.Got[c] = true
				s.Coins += 1
				s.CoinTick = n
				c += 1
			else
				break
			end
		else
			break
		end
	end
	s.Coin = c
end

--..Runs (a course + its event list + a simulation with checkpoints): the gamer's GUI and every monitor use them..--
local function NewRun(seed)
	return {Seed = seed, Course = NewCourse(seed), Ticks = {}, Kinds = {}, Sim = NewSim(), Marks = {}, Dirty = nil, Heard = 0, Complete = false}
end

--.. an event code from the server: tick * 4 + kind
local function AddCode(run, code)
	if not Finite(code) or code < 0 then return end
	local tick, kind = math.floor(code / 4), code % 4
	local last = run.Ticks[#run.Ticks]
	if last and tick < last then return end -- out of order (never sent by the server)
	table.insert(run.Ticks, tick)
	table.insert(run.Kinds, kind)
	if tick <= run.Sim.N then run.Dirty = math.min(run.Dirty or math.huge, tick) end
end

--.. replace the whole list ("Events"): roll back to where it first differs
local function SetCodes(run, codes)
	local oldT, oldK = run.Ticks, run.Kinds
	run.Ticks, run.Kinds = {}, {}
	local keep = run.Dirty
	for _, code in ipairs(codes) do AddCode(run, code) end
	run.Dirty = keep
	local first = nil
	local count = math.max(#oldT, #run.Ticks)
	for i = 1, count do
		if oldT[i] ~= run.Ticks[i] or oldK[i] ~= run.Kinds[i] then
			first = math.min(oldT[i] or math.huge, run.Ticks[i] or math.huge)
			break
		end
	end
	if first and first <= run.Sim.N then run.Dirty = math.min(run.Dirty or math.huge, first) end
end

--.. step the run on to `target` ticks (at most `budget` ticks now); hooks[name](run) fire for ticks never heard before
--.. while the advance is live (a small step, not a catch-up or a rollback): Press, Jump, Coin, Crash
local function Advance(run, target, budget, hooks)
	local s = run.Sim
	if run.Dirty then
		local mark = nil
		for i = #run.Marks, 1, -1 do
			if run.Marks[i].N < run.Dirty then
				mark = run.Marks[i]
				break
			end
			run.Marks[i] = nil
		end
		Restore(s, mark or Snapshot(NewSim()))
		run.Dirty = nil
	end
	local live = target - s.N <= LIVE_TICKS
	local steps = 0
	while s.N < target and not s.Dead and steps < budget do
		local presses, jumps, coins = s.Presses, s.Jumps, s.Coins
		StepSim(s, run.Course, run.Ticks, run.Kinds)
		steps += 1
		if s.N % MARK_TICKS == 0 then
			table.insert(run.Marks, Snapshot(s))
			if #run.Marks > MAX_MARKS then table.remove(run.Marks, 1) end
		end
		if hooks and live and s.N > run.Heard then
			if s.Presses > presses and hooks.Press then hooks.Press(run) end
			if s.Jumps > jumps and hooks.Jump then hooks.Jump(run) end
			if s.Coins > coins and hooks.Coin then hooks.Coin(run) end
			if s.Dead and hooks.Crash then hooks.Crash(run) end
		end
	end
	if s.N > run.Heard then run.Heard = s.N end
end

--..Screen geometry..--
--.. a panel's local screen: CFrame (LookVector = out of the screen), Size, and its "right" (the part's +X, which is the
--.. viewer's LEFT on a Front-face SurfaceGui). The face goes GAP past the front-most layer over the panel (the panel
--.. itself or a ScreenArt* part lying on it)
local function PanelGeometry(model, panel, arts, scale)
	local origin = Kit.Origin(model)
	local front, upWorld = origin.LookVector, origin.UpVector
	local cf = panel.CFrame
	local axes = {cf.XVector, cf.YVector, cf.ZVector}
	local sizes = {panel.Size.X, panel.Size.Y, panel.Size.Z}
	local ni, nBest = 1, -1
	for i = 1, 3 do
		local d = math.abs(axes[i]:Dot(front))
		if d > nBest then ni, nBest = i, d end
	end
	local ui, uBest = nil, -1
	for i = 1, 3 do
		if i ~= ni then
			local d = math.abs(axes[i]:Dot(upWorld))
			if d > uBest then ui, uBest = i, d end
		end
	end
	local wi = 6 - ni - ui
	local normal = axes[ni] * (axes[ni]:Dot(front) >= 0 and 1 or -1)
	local up = axes[ui] * (axes[ui]:Dot(upWorld) >= 0 and 1 or -1)
	local width, height = sizes[wi], sizes[ui]
	local right = up:Cross(-normal)
	local centre = panel.Position
	local lead = HalfExtent(panel, normal)
	for _, p in ipairs(arts) do
		local rel = p.Position - centre
		if math.abs(rel:Dot(right)) <= width * 0.5 + 0.02 and math.abs(rel:Dot(up)) <= height * 0.5 + 0.02 and math.abs(rel:Dot(normal)) < 0.4 * scale then
			lead = math.max(lead, rel:Dot(normal) + HalfExtent(p, normal))
		end
	end
	local thick = THICK * scale
	local position = centre + normal * (lead + GAP * scale - thick * 0.5)
	return CFrame.fromMatrix(position, right, up, -normal), Vector3.new(width, height, thick), right
end

--..Scene (the monitor makes one copy per panel - each copy is the whole scene, shifted so its panel shows its own
--.. slice; the gamer's GUI makes one). L = the layout: U (px per art px), W / H (px), AW (art px wide), groundA,
--.. heroA (art px), centreX0 / centreW (px: where the HUD goes)..--
local function NewScene(gui, L, offsetPx, withHud)
	local U = L.U
	local S = {tints = {}, sky = {}, sun = {}, clouds = {}, hills = {}, obstacles = {}, coins = {}, pose = nil}
	local function Px(a) return math.floor(a * U + 0.5) end
	local function Box(name, parent, x, y, w, h, color, z, corner)
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color or C.Ink
		f.BackgroundTransparency = color and 0 or 1
		f.Position = UDim2.fromOffset(Px(x), Px(y))
		f.Size = UDim2.fromOffset(math.max(1, Px(w)), math.max(1, Px(h)))
		f.ZIndex = z or 1
		if corner then New("UICorner", {CornerRadius = corner}, f) end
		f.Parent = parent
		return f
	end
	local function Tint(f)
		table.insert(S.tints, {f, f.BackgroundColor3})
		return f
	end
	local round = UDim.new(0.5, 0)
	local soft = UDim.new(0, math.max(1, Px(1)))

	local root = New("Frame", {
		Name = "Scene", BorderSizePixel = 0, BackgroundColor3 = SKY_DAY[3], Position = UDim2.fromOffset(-offsetPx, 0),
		Size = UDim2.fromOffset(L.W, L.H), ClipsDescendants = true, ZIndex = 1,
	}, gui)
	S.root = root
	local gA, AW = L.groundA, L.AW

	--.. sky bands + sun
	S.sky[1] = Box("Sky1", root, 0, 0, AW + 1, gA * 0.42, SKY_DAY[1], 1)
	S.sky[2] = Box("Sky2", root, 0, gA * 0.42, AW + 1, gA * 0.3, SKY_DAY[2], 1)
	S.sky[3] = Box("Sky3", root, 0, gA * 0.72, AW + 1, gA * 0.3, SKY_DAY[3], 1)
	S.sun[1] = Box("Sun", root, AW * 0.8, 3, 7, 7, SUN_DAY[1], 2, soft)
	S.sun[2] = Box("SunCore", S.sun[1], 1.5, 1.5, 4, 4, SUN_DAY[2], 1, soft)

	--.. clouds (a base + a puff), hills (big circles half under the ground)
	for i, cy in ipairs({3, 8, 5, 10}) do
		local c = Box("Cloud" .. i, root, 0, cy, 12, 5, nil, 3)
		Tint(Box("Base", c, 0, 2, 12, 3, C.Cloud, 1, soft))
		Tint(Box("Puff", c, 3, 0, 6, 3, C.Cloud, 1, soft))
		S.clouds[i] = c
	end
	for i, h in ipairs(HILLS) do
		S.hills[i] = Tint(Box("Hill" .. i, root, 0, gA - h.D * 0.42, h.D, h.D, C[h.Color], 4, round))
	end

	--.. ground: grass, its dark edge, dirt to the bottom, and a scrolling row of dirt tiles
	Tint(Box("Grass", root, 0, gA, AW + 1, 2, C.Grass, 5))
	Tint(Box("GrassEdge", root, 0, gA + 2, AW + 1, 1, C.GrassDark, 5))
	local dirt = Tint(Box("Dirt", root, 0, gA + 3, AW + 1, 1, C.Dirt, 5))
	dirt.Size = UDim2.fromOffset(L.W + U, math.max(1, L.H - Px(gA + 3)))
	S.tiles = Box("Tiles", root, 0, gA + 4, AW + 16, 5, nil, 6)
	for x = 0, AW + 16, 8 do
		Tint(Box("T", S.tiles, x, 0.5, 2, 1, C.DirtDark, 1))
		Tint(Box("T", S.tiles, x + 4, 2.5, 2, 1, C.DirtDark, 1))
	end
	--.. grass tufts scroll with the tiles
	for x = 0, AW + 16, 8 do
		Tint(Box("Tuft", S.tiles, x + 2, -4.5, 1, 1, C.Grass, 1))
	end

	--.. obstacles: every slot holds all five kinds, one shown at a time. The slot's left edge is the obstacle's
	--.. centre - 2.5 and its top 6 px above the ground (a drone slot is lifted to DRONE_DRAW_TOP)
	for i = 1, OBSTACLE_POOL do
		local slot = Box("Obstacle" .. i, root, -10, gA - 6, 5, 6, nil, 7)
		slot.Visible = false
		local crate = Box("Crate", slot, 0, 1, 5, 5, nil, 1)
		Tint(Box("Box", crate, 0, 0, 5, 5, C.Crate, 1))
		Tint(Box("Inset", crate, 1, 1, 3, 3, C.CrateDark, 1))
		Tint(Box("Plank", crate, 1, 2, 3, 1, C.Crate, 1))
		local double = Box("Double", slot, -2.5, 1, 10, 5, nil, 1)
		for d = 0, 1 do
			Tint(Box("Box" .. d, double, d * 5, 0, 5, 5, C.Crate, 1))
			Tint(Box("Inset" .. d, double, d * 5 + 1, 1, 3, 3, C.CrateDark, 1))
			Tint(Box("Plank" .. d, double, d * 5 + 1, 2, 3, 1, C.Crate, 1))
		end
		local spike = Box("Spike", slot, 0, 0, 5, 6, nil, 1)
		Tint(Box("S1", spike, 0, 4, 5, 2, C.SpikeDark, 1))
		Tint(Box("S2", spike, 1, 2, 3, 2, C.Spike, 1))
		Tint(Box("S3", spike, 2, 0, 1, 2, C.Spike, 1))
		local slime = Box("Slime", slot, 0, 2, 5, 4, nil, 1)
		Tint(Box("Body", slime, 0, 0, 5, 4, C.Slime, 1, UDim.new(0, math.max(1, Px(1.5)))))
		Box("EyeA", slime, 0.6, 1, 1, 1, C.Eye, 1)
		Box("EyeB", slime, 2.4, 1, 1, 1, C.Eye, 1)
		local drone = Box("Drone", slot, -1, 0, 7, 5, nil, 1)
		local rotor = Tint(Box("Rotor", drone, 0, 0, 7, 1, C.Rotor, 2))
		Tint(Box("Mast", drone, 3, 1, 1, 1, C.Rotor, 1))
		Tint(Box("Body", drone, 1, 2, 5, 3, C.Drone, 1, soft))
		Tint(Box("Belly", drone, 1.5, 4, 4, 1, C.DroneDark, 2))
		Box("Light", drone, 1.6, 2.7, 1.2, 1.2, C.DroneLight, 3)
		S.obstacles[i] = {slot = slot, kinds = {crate = crate, double = double, spike = spike, slime = slime, drone = drone}, kind = nil, rotor = rotor, spin = nil}
	end
	for _, o in ipairs(S.obstacles) do
		for _, g in pairs(o.kinds) do g.Visible = false end
	end

	--.. coins
	for i = 1, COIN_POOL do
		local coin = Box("Coin" .. i, root, -10, gA - 6, 3, 3, C.Coin, 7, round)
		Box("Shine", coin, 0.6, 0.6, 1, 1, C.CoinShine, 1, round)
		coin.Visible = false
		S.coins[i] = coin
	end

	--.. the hero: a cucumber in a red headband (faces right = the way it runs). Poses: Stand (running, jumping,
	--.. crashed: dizzy X eyes) and Duck (squashed low under the drones)
	local hero = Box("Hero", root, L.heroA - 3, gA - 10, 6, 10, nil, 8)
	local stand = Box("Stand", hero, 0, 0, 6, 10, nil, 1)
	S.heroTail = Box("Tail", stand, -2, 2, 2, 1, C.Band, 1)
	Box("Body", stand, 0, 0, 6, 8, C.Hero, 2, UDim.new(0, math.max(1, Px(2.5))))
	Box("StripeA", stand, 1, 2, 1, 5, C.HeroDark, 3)
	Box("StripeB", stand, 2.5, 3, 1, 4, C.HeroDark, 3)
	Box("Band", stand, 0, 1.6, 6, 1, C.Band, 4)
	S.eye = Box("Eye", stand, 3.4, 3, 2, 2, C.Eye, 4)
	S.pupil = Box("Pupil", stand, 4.4, 3.5, 1, 1, C.Ink, 5)
	Box("Mouth", stand, 4, 6, 1.4, 0.5, C.Ink, 4)
	local dizzy = Box("Dizzy", stand, 3.1, 2.7, 3, 3, nil, 5)
	for _, p in ipairs({{0, 0}, {2, 0}, {1, 1}, {0, 2}, {2, 2}}) do Box("X", dizzy, p[1], p[2], 1, 1, C.Ink, 1) end
	dizzy.Visible = false
	S.dizzy = dizzy
	S.legA = Box("LegA", stand, 1.5, 8, 1, 2, C.Leg, 1)
	S.legB = Box("LegB", stand, 3.5, 8, 1, 2, C.Leg, 1)
	local duck = Box("Duck", hero, -1, 4, 8, 6, nil, 1)
	Box("Tail", duck, -2, 1, 2, 1, C.Band, 1)
	Box("Body", duck, 0, 0, 8, 5, C.Hero, 2, UDim.new(0, math.max(1, Px(2))))
	Box("StripeA", duck, 1, 2.2, 4, 1, C.HeroDark, 3)
	Box("StripeB", duck, 1.5, 3.4, 3, 1, C.HeroDark, 3)
	Box("Band", duck, 0, 0.8, 8, 1, C.Band, 4)
	Box("Eye", duck, 5.4, 1.8, 2, 2, C.Eye, 4)
	Box("Pupil", duck, 6.4, 2.3, 1, 1, C.Ink, 5)
	Box("LegA", duck, 1.5, 5, 1, 1, C.Leg, 1)
	Box("LegB", duck, 5, 5, 1, 1, C.Leg, 1)
	duck.Visible = false
	S.stand, S.duck, S.hero = stand, duck, hero

	--.. "+50"
	S.popup = New("TextLabel", {
		Name = "Popup", BackgroundTransparency = 1, Font = FONT, Text = "+" .. COIN_POINTS, TextColor3 = C.Title,
		TextScaled = true, Size = UDim2.fromOffset(Px(10), Px(3.5)), Visible = false, ZIndex = 9,
	}, root)
	New("UIStroke", {Color = C.Outline, Thickness = 1}, S.popup)

	--.. HUD, inside the centre panel's slice (the monitor only; the GUI has its own)
	if withHud then
		local x0, w = L.centreX0, L.centreW
		local function Label(name, x, y, width, height, color, align, strokeColor, strokeThickness)
			local t = New("TextLabel", {
				Name = name, BackgroundTransparency = 1, Font = FONT, Text = "", TextColor3 = color, TextScaled = true,
				TextXAlignment = align or Enum.TextXAlignment.Center, Position = UDim2.fromOffset(math.floor(x), math.floor(y)),
				Size = UDim2.fromOffset(math.floor(width), math.floor(height)), ZIndex = 10,
			}, root)
			New("UIStroke", {Color = strokeColor or C.Outline, Thickness = strokeThickness or 1.5}, t)
			return t
		end
		S.score = Label("Score", x0 + Px(2), Px(1), w * 0.55, Px(3.6), C.Text, Enum.TextXAlignment.Left)
		S.name = Label("Name", x0 + Px(2), Px(5), w * 0.55, Px(2.8), C.Green, Enum.TextXAlignment.Left)
		S.coinCount = Label("Coins", x0 + w * 0.62, Px(1), w * 0.38 - Px(2), Px(3.6), C.Title, Enum.TextXAlignment.Right)
		S.big = Label("Big", x0 + w * 0.08, Px(9), w * 0.84, Px(7.5), C.Title, Enum.TextXAlignment.Center, C.TitleOutline, 2)
		S.small = Label("Small", x0 + w * 0.15, Px(17.5), w * 0.7, Px(3.4), C.Text)
	end
	return S
end

--.. night colours on / off for one scene copy
local function PaintScene(S, night)
	for i, f in ipairs(S.sky) do f.BackgroundColor3 = night and SKY_NIGHT[i] or SKY_DAY[i] end
	S.root.BackgroundColor3 = night and SKY_NIGHT[3] or SKY_DAY[3]
	for i, f in ipairs(S.sun) do f.BackgroundColor3 = night and SUN_NIGHT[i] or SUN_DAY[i] end
	for _, t in ipairs(S.tints) do t[1].BackgroundColor3 = night and Dim(t[2], NIGHT_DIM) or t[2] end
end

--..World views: what to draw, in course coordinates (filled into a reused table W)..--
--.. W = {CamX, HeroY, Pose ("stand" / "run" / "air" / "duck" / "dead"), Step (0 / 1), Obs = {{X, Kind, K}}, NObs,
--..      Coins = {{X, Y, J}}, NCoins, Popup (nil or 0..1 rise)}
local function NewView()
	local W = {CamX = 0, HeroY = 0, Pose = "stand", Step = 0, Obs = {}, NObs = 0, Coins = {}, NCoins = 0, Popup = nil}
	for i = 1, OBSTACLE_POOL do W.Obs[i] = {X = 0, Kind = "crate", K = 0} end
	for i = 1, COIN_POOL do W.Coins[i] = {X = 0, Y = 0, J = 0} end
	return W
end

local function PutObstacle(W, x, kind, k)
	if W.NObs >= OBSTACLE_POOL then return end
	W.NObs += 1
	local o = W.Obs[W.NObs]
	o.X, o.Kind, o.K = x, kind, k
end

local function PutCoin(W, x, y, j)
	if W.NCoins >= COIN_POOL then return end
	W.NCoins += 1
	local c = W.Coins[W.NCoins]
	c.X, c.Y, c.J = x, y, j
end

--.. the attract loop: the old self-playing run, a pure function of now (every client shows the same frame)
local function ViewAttract(W, L, now)
	local camX = IDLE_SPEED * (now % IDLE_WRAP)
	local heroA, AW = L.heroA, L.AW
	W.CamX, W.NObs, W.NCoins, W.Popup = camX, 0, 0, nil
	local lo, hi = camX - heroA - 8, camX + AW - heroA + 8
	for k = math.ceil((lo - IDLE_JITTER) / IDLE_SPACING), math.floor((hi + IDLE_JITTER) / IDLE_SPACING) do
		local x = k * IDLE_SPACING + (Hash(k, 1) * 2 - 1) * IDLE_JITTER
		if x > lo and x < hi then
			local h = Hash(k, 2)
			PutObstacle(W, x, h < 0.45 and "crate" or (h < 0.75 and "spike" or "slime"), k)
		end
	end
	for j = math.ceil(camX / IDLE_SPACING - 0.5), math.floor(hi / IDLE_SPACING - 0.5) do
		local x = (j + 0.5) * IDLE_SPACING
		if x > camX then PutCoin(W, x, 5, j) end
	end
	--.. the hero's jump: an arc JUMP_LEN long centred on each obstacle
	local jumpY = 0
	local kNear = math.floor(camX / IDLE_SPACING + 0.5)
	for k = kNear - 1, kNear + 1 do
		local x = k * IDLE_SPACING + (Hash(k, 1) * 2 - 1) * IDLE_JITTER
		local u = (camX - (x - JUMP_LEN * 0.5)) / JUMP_LEN
		if u > 0 and u < 1 then jumpY = math.max(jumpY, JUMP_H * 4 * u * (1 - u)) end
	end
	W.HeroY = jumpY
	W.Pose = jumpY > 0.4 and "air" or "run"
	W.Step = math.floor(now / 0.13) % 2
end

--.. a real run: its simulation as it stands
local function ViewRun(W, L, run)
	local s, course = run.Sim, run.Course
	local camX = s.X
	local lo, hi = camX - L.heroA - 12, camX + L.AW - L.heroA + 12
	Extend(course, hi)
	W.CamX, W.HeroY, W.NObs, W.NCoins = camX, s.Y, 0, 0
	for i = math.max(1, s.Obs - 4), course.N do
		local x = course.X[i]
		if x > hi then break end
		if x >= lo then PutObstacle(W, x, course.Kind[i], i) end
	end
	for i = math.max(1, s.Coin - 4), course.N do
		local x = course.CoinX[i]
		if x then
			if x > hi then break end
			if x >= lo and (i >= s.Coin or not s.Got[i]) then PutCoin(W, x, course.CoinY[i], i) end
		end
	end
	if s.Dead then
		W.Pose = "dead"
	elseif s.N == 0 then
		W.Pose = "stand"
	elseif not s.Ground then
		W.Pose = "air"
	elseif s.DuckHeld then
		W.Pose = "duck"
	else
		W.Pose = "run"
	end
	W.Step = math.floor(s.N / 8) % 2
	local age = s.N - s.CoinTick
	W.Popup = (age >= 0 and age < POPUP_TIME * TICK_RATE) and age / (POPUP_TIME * TICK_RATE) or nil
end

--..DrawWorld: one view into every copy of a scene (the monitor's three slices, or the GUI). hud = optional texts
--.. {Score, Name, Coins, Big, Small, BigY, SmallY} for copies that carry the pixel HUD..--
local function DrawWorld(scenes, L, W, now, hud)
	local U = L.U
	local heroA, AW, gA, camX = L.heroA, L.AW, L.groundA, W.CamX

	--.. parallax layers
	local cloudSpan, hillSpan = AW + 16, AW + 36
	local cloudUD, hillUD = {}, {}
	for i = 1, 4 do
		local x = ((i - 1) * cloudSpan / 4 - camX * 0.15) % cloudSpan - 14
		cloudUD[i] = UDim2.fromOffset(math.floor(x * U), 0)
	end
	for i = 1, #HILLS do
		local x = ((i - 1) * hillSpan / 3 + 6 - camX * 0.4) % hillSpan - 32
		hillUD[i] = UDim2.fromOffset(math.floor(x * U), math.floor((gA - HILLS[i].D * 0.42) * U))
	end
	local tilesUD = UDim2.fromOffset(math.floor(-((camX % 8) * U)), math.floor((gA + 4) * U))

	--.. the hero
	local pose = W.Pose
	local ducking = pose == "duck"
	local airborne = pose == "air"
	local heroUD = UDim2.fromOffset(math.floor((heroA - 3) * U), math.floor((gA - 10 - (ducking and 0 or W.HeroY)) * U))
	local legAY, legBY = 8, 8
	if airborne then
		legAY, legBY = 7, 7
	elseif pose == "run" then
		legAY, legBY = W.Step == 1 and 7 or 8, W.Step == 0 and 7 or 8
	end
	local legAUD = UDim2.fromOffset(math.floor(1.5 * U), math.floor(legAY * U))
	local legBUD = UDim2.fromOffset(math.floor(3.5 * U), math.floor(legBY * U))
	local tailUD = UDim2.fromOffset(math.floor(-2 * U), math.floor(((pose == "run" or airborne) and W.Step == 1 and 1.6 or 2.2) * U))

	--.. obstacles / coins
	local obsUD = {}
	for i = 1, W.NObs do
		local o = W.Obs[i]
		local sx = heroA + (o.X - camX)
		local bob = (o.Kind == "slime" or o.Kind == "drone") and (math.floor(now * 4 + o.K) % 2) or 0
		local top = o.Kind == "drone" and (gA - DRONE_DRAW_TOP + bob * 0.5) or (gA - 6 - bob * 0.5)
		obsUD[i] = UDim2.fromOffset(math.floor((sx - 2.5) * U), math.floor(top * U))
	end
	local spin = math.floor(now * 14) % 2
	local rotorPos = spin == 0 and UDim2.fromOffset(0, 0) or UDim2.fromOffset(math.floor(2 * U), 0)
	local rotorSize = UDim2.fromOffset(spin == 0 and math.floor(7 * U) or math.floor(3 * U), math.max(1, math.floor(U)))
	local coinUD, coinSize = {}, {}
	for i = 1, W.NCoins do
		local cn = W.Coins[i]
		local cspin = math.abs(math.cos(now * 5 + cn.J))
		local w = math.max(1, math.floor((1 + 2 * cspin) * U + 0.5))
		local bobY = math.sin(now * 3 + cn.J) * 0.6
		coinUD[i] = UDim2.fromOffset(math.floor((heroA + (cn.X - camX)) * U - w * 0.5), math.floor((gA - cn.Y - COIN_R + bobY) * U))
		coinSize[i] = UDim2.fromOffset(w, math.floor(3 * U))
	end
	local popupRise = W.Popup
	local popupUD = popupRise and UDim2.fromOffset(math.floor((heroA - 5) * U), math.floor((gA - 13 - W.HeroY * 0.5 - popupRise * 6) * U)) or nil
	local bigUD, smallUD
	if hud then
		bigUD = UDim2.fromOffset(math.floor(L.centreX0 + L.centreW * 0.08), math.floor(hud.BigY * U))
		smallUD = UDim2.fromOffset(math.floor(L.centreX0 + L.centreW * 0.15), math.floor(hud.SmallY * U))
	end

	for _, S in ipairs(scenes) do
		for i, c in ipairs(S.clouds) do c.Position = cloudUD[i] end
		for i, h in ipairs(S.hills) do h.Position = hillUD[i] end
		S.tiles.Position = tilesUD
		S.hero.Position = heroUD
		if S.pose ~= pose then
			S.pose = pose
			S.stand.Visible = not ducking
			S.duck.Visible = ducking
			local dead = pose == "dead"
			S.dizzy.Visible = dead
			S.eye.Visible = not dead
			S.pupil.Visible = not dead
		end
		S.legA.Position = legAUD
		S.legB.Position = legBUD
		S.heroTail.Position = tailUD
		for i, slot in ipairs(S.obstacles) do
			if i <= W.NObs then
				local kind = W.Obs[i].Kind
				slot.slot.Position = obsUD[i]
				if slot.kind ~= kind then
					if slot.kind then slot.kinds[slot.kind].Visible = false end
					slot.kind = kind
					slot.kinds[kind].Visible = true
				end
				if kind == "drone" and slot.spin ~= spin then
					slot.spin = spin
					slot.rotor.Position = rotorPos
					slot.rotor.Size = rotorSize
				end
				if not slot.slot.Visible then slot.slot.Visible = true end
			elseif slot.slot.Visible then
				slot.slot.Visible = false
			end
		end
		for i, coin in ipairs(S.coins) do
			if i <= W.NCoins then
				coin.Position = coinUD[i]
				coin.Size = coinSize[i]
				if not coin.Visible then coin.Visible = true end
			elseif coin.Visible then
				coin.Visible = false
			end
		end
		S.popup.Visible = popupRise ~= nil
		if popupRise then
			S.popup.Position = popupUD
			S.popup.TextTransparency = popupRise * 0.8
		end
		if hud and S.score then
			SetText(S.score, hud.Score)
			SetText(S.name, hud.Name)
			SetText(S.coinCount, hud.Coins)
			SetText(S.big, hud.Big)
			SetText(S.small, hud.Small)
			S.big.Position = bigUD
			S.small.Position = smallUD
		end
	end
end

--..State (read every frame; attributes are cheap)..--
local function ReadState(ctx)
	return tonumber(ctx:State("Player")) or 0, tonumber(ctx:State("Since")) or 0, tonumber(ctx:State("Ended")) or 0,
		tonumber(ctx:State("Final")) or 0, tonumber(ctx:State("Best")) or 0, tonumber(ctx:State("Seed")) or 0
end

--..GUI helpers (the arcade's look)..--
local function Corner(parent, px)
	return New("UICorner", {CornerRadius = UDim.new(0, px or 12)}, parent)
end

local function Round(parent)
	return New("UICorner", {CornerRadius = UDim.new(1, 0)}, parent)
end

--.. border = true strokes a frame's edge; otherwise (Contextual) a text object's glyphs
local function Stroke(parent, thickness, color, border)
	return New("UIStroke", {
		Color = color or LOOK.DARK, Thickness = thickness or 2, LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = border and Enum.ApplyStrokeMode.Border or Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

local function Gradient(parent, top, bottom)
	return New("UIGradient", {Color = ColorSequence.new(top, bottom), Rotation = 90}, parent)
end

local function UiBox(parent, props)
	local frame = New("Frame", {BorderSizePixel = 0, BackgroundColor3 = LOOK.WHITE})
	for k, v in pairs(props) do frame[k] = v end
	frame.Parent = parent
	return frame
end

--.. a FredokaOne label: white text, dark stroke (stroke = 0 for none)
local function Text(parent, props, stroke)
	local label = New("TextLabel", {BackgroundTransparency = 1, Font = LOOK.GUI_FONT, TextColor3 = LOOK.WHITE, TextSize = 24, Text = ""})
	for k, v in pairs(props) do label[k] = v end
	if (stroke or 2) > 0 then Stroke(label, stroke or 2) end
	label.Parent = parent
	return label
end

--.. a HUD-style button: gradient shell, dark edge, inner highlight rim, white stroked text, press pop
local function Button(parent, look, size, position, text, textSize)
	local shell = UiBox(parent, {Size = size, Position = position, AnchorPoint = Vector2.new(0.5, 0.5)})
	Corner(shell, 14)
	Gradient(shell, look.Top, look.Bottom)
	Stroke(shell, 3, LOOK.DARK, true)
	local rim = UiBox(shell, {Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1})
	Corner(rim, 11)
	New("UIStroke", {Color = look.Highlight, Thickness = 2, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, rim)
	local button = New("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text or "", Font = LOOK.GUI_FONT,
		TextSize = textSize or 28, TextColor3 = LOOK.WHITE, AutoButtonColor = false,
	}, shell)
	Stroke(button, 2.5)
	local pop = New("UIScale", {}, shell)
	button.MouseEnter:Connect(function() pop.Scale = 1.04 end)
	button.MouseLeave:Connect(function() pop.Scale = 1 end)
	button.MouseButton1Down:Connect(function() pop.Scale = 0.93 end)
	button.MouseButton1Up:Connect(function() pop.Scale = 1 end)
	return button, shell, pop
end

--.. the layout of the GUI's scene (one copy, no pixel HUD)
local function GuiLayout()
	local L = {U = LOOK.GUI_U, W = LOOK.VIEW_ART.X * LOOK.GUI_U, H = LOOK.VIEW_ART.Y * LOOK.GUI_U, AW = LOOK.VIEW_ART.X}
	L.groundA = LOOK.VIEW_ART.Y - GROUND_H
	L.heroA = LOOK.VIEW_ART.X * LOOK.GUI_HERO_AT
	L.centreX0, L.centreW = 0, L.W
	return L
end

--..Game: GUI..--
local function BuildGui(g)
	local ui = {}
	local gui = New("ScreenGui", {Name = LOOK.GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
	ui.Gui = gui
	UiBox(gui, {Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = LOOK.BLACK, BackgroundTransparency = 0.5, Active = true})

	--..Desk panel (dark like the desk, red trim; the title plate's edge runs through the rainbow like the RGB)..--
	local panel = UiBox(gui, {Name = "Desk", Size = UDim2.fromOffset(LOOK.PANEL.X, LOOK.PANEL.Y), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, LOOK.PANEL_DROP), Active = true})
	ui.Panel = panel
	ui.Scale = New("UIScale", {}, panel)
	Corner(panel, 28)
	Gradient(panel, LOOK.DESK_TOP, LOOK.DESK_BOTTOM)
	Stroke(panel, 6, LOOK.DESK_TRIM, true)
	local plate = UiBox(panel, {Size = UDim2.fromOffset(470, 52), Position = UDim2.new(0.5, 0, 0, 12), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(16, 18, 26)})
	Corner(plate, 16)
	ui.PlateStroke = Stroke(plate, 3, LOOK.GREEN.Top, true)
	Text(plate, {Size = UDim2.fromScale(1, 1), Text = LOOK.CUKE .. " CUKE RUN " .. LOOK.CUKE, TextSize = 34}, 2.5)
	ui.Close = Button(panel, LOOK.RED, UDim2.fromOffset(52, 52), UDim2.new(1, -44, 0, 38), "X", 32)

	--..The game view: the pixel world (the monitor's scene) + a HUD strip; the whole view is the tap-to-jump area..--
	local L = g.L
	local view = UiBox(panel, {Name = "View", Size = UDim2.fromOffset(L.W, L.H), Position = UDim2.fromOffset(LOOK.VIEW_X, LOOK.VIEW_Y), BackgroundColor3 = SKY_DAY[3], ClipsDescendants = true, Active = true})
	Stroke(view, 5, LOOK.DARK, true)
	ui.View = view
	g.scenes = {NewScene(view, L, 0, false)}
	local hud = UiBox(view, {Size = UDim2.fromOffset(L.W, LOOK.HUD_H), BackgroundColor3 = LOOK.BLACK, BackgroundTransparency = 0.55, ZIndex = 20})
	ui.Score = Text(hud, {Text = "SCORE 000000", TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(320, LOOK.HUD_H), Position = UDim2.fromOffset(16, 0)}, 2.5)
	local coin = UiBox(hud, {Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0.5, -40, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.Coin})
	Round(coin)
	Stroke(coin, 2, Color3.fromRGB(150, 96, 10), true)
	ui.CoinScale = New("UIScale", {}, coin)
	ui.Coins = Text(hud, {Text = "x 0", TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(120, LOOK.HUD_H), Position = UDim2.new(0.5, -20, 0, 0)}, 2.5)
	ui.Hi = Text(hud, {Text = "HI 000000", TextSize = 26, TextColor3 = LOOK.GOLD, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(300, LOOK.HUD_H), Position = UDim2.new(1, -16, 0, 0), AnchorPoint = Vector2.new(1, 0)}, 2.5)
	ui.Flash = UiBox(view, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 40, 40), BackgroundTransparency = 1, ZIndex = 24})
	ui.Count = Text(view, {Text = "", TextSize = 96, Size = UDim2.fromOffset(L.W, 120), Position = UDim2.fromOffset(L.W / 2, L.H * 0.4), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 25}, 4)
	ui.CountScale = New("UIScale", {}, ui.Count)
	--.. the READY hint sits right of the hero, clear of it
	local heroRight = (L.heroA + 5) * L.U
	local hint = UiBox(view, {Size = UDim2.fromOffset(L.W - heroRight - 24, 78), Position = UDim2.fromOffset(heroRight + 8, L.H * 0.64), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = LOOK.BLACK, BackgroundTransparency = 0.35, ZIndex = 25})
	Corner(hint, 16)
	Text(hint, {Text = "Jump the crates, spikes and slimes - grab the coins!", TextSize = 22, Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 6)}, 2)
	Text(hint, {Text = "DUCK under the flying drones", TextSize = 21, TextColor3 = Color3.fromRGB(205, 180, 255), Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 42)}, 2)
	ui.Hint = hint
	--.. the tap-to-jump area: a clear button over the whole view (buttons always get their presses)
	ui.Tap = New("TextButton", {Name = "TapArea", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 40}, view)

	--..Controls row: big DUCK / JUMP buttons (touch, mouse) and the key help between them..--
	local rowY = LOOK.CONTROLS_Y + 55
	local duck, _, duckPop = Button(panel, LOOK.GREEN, UDim2.fromOffset(220, 110), UDim2.fromOffset(LOOK.VIEW_X + 110, rowY), "DUCK", 38)
	local jump, _, jumpPop = Button(panel, LOOK.GREEN, UDim2.fromOffset(260, 110), UDim2.fromOffset(LOOK.VIEW_X + L.W - 130, rowY), "JUMP", 44)
	ui.Duck, ui.DuckPop, ui.Jump, ui.JumpPop = duck, duckPop, jump, jumpPop
	local help
	if IsTouch() then
		help = "TAP the game or JUMP to jump\nhold for a higher jump\nhold DUCK under the drones"
	else
		help = "JUMP: SPACE / W / UP / CLICK\n(hold for a higher jump)\nDUCK: S / DOWN     EXIT: BACKSPACE"
	end
	Text(panel, {Text = help, TextSize = 19, TextColor3 = Color3.fromRGB(205, 214, 235), Size = UDim2.fromOffset(350, 104), Position = UDim2.fromOffset(LOOK.PANEL.X / 2, rowY), AnchorPoint = Vector2.new(0.5, 0.5), TextWrapped = true}, 2)

	--..Game over card (over the view)..--
	local card = UiBox(panel, {Size = UDim2.fromOffset(420, 340), Position = UDim2.fromOffset(LOOK.VIEW_X + L.W / 2, LOOK.VIEW_Y + L.H / 2), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(26, 30, 50), Visible = false, ZIndex = 30})
	Corner(card, 22)
	Stroke(card, 4, LOOK.DESK_TRIM, true)
	ui.Card = card
	ui.CardScale = New("UIScale", {}, card)
	Text(card, {Text = "GAME OVER", TextSize = 50, TextColor3 = Color3.fromRGB(255, 96, 96), Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 12)}, 3)
	Text(card, {Text = "SCORE", TextSize = 22, TextColor3 = Color3.fromRGB(200, 212, 235), Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 68)}, 2)
	ui.CardScore = Text(card, {Text = "0", TextSize = 60, Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 90)}, 3)
	ui.CardBest = Text(card, {Text = "BEST 0", TextSize = 26, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 154)}, 2)
	ui.CardTag = Text(card, {Text = "", TextSize = 24, TextColor3 = Color3.fromRGB(255, 226, 90), Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 188)}, 2.5)
	ui.CardHi = Text(card, {Text = "", TextSize = 21, TextColor3 = LOOK.NEON_CYAN, Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 220)}, 2)
	ui.Again = Button(card, LOOK.GREEN, UDim2.fromOffset(214, 66), UDim2.new(0.5, -72, 0, 292), "PLAY AGAIN", 28)
	ui.Exit = Button(card, LOOK.RED, UDim2.fromOffset(120, 66), UDim2.new(0.5, 112, 0, 292), "EXIT", 28)
	return ui
end

--..Game: sounds (2D: parented to the ScreenGui)..--
local function MakeSounds(g)
	local list = {
		Jump = "ArcadeBlip", Go = "ArcadeBlip", Duck = "Whoosh", Coin = "Coin", Crash = "Thump",
		Lose = "ArcadeLose", Win = "ArcadeWin", Click = "Click",
	}
	g.sounds = {}
	for name, sfx in pairs(list) do
		local id = type(FunAssets.Sfx) == "table" and FunAssets.Sfx[sfx] or nil
		local ok, sound = false, nil
		if id then ok, sound = pcall(Kit.MakeSound, id, {Name = "Sfx" .. name, Volume = 0.5}) end
		if ok and sound then
			sound.Parent = g.ui.Gui
			g.sounds[name] = sound
		end
	end
end

local function PlayUi(g, name, speed, volume)
	local sound = g.sounds[name]
	if not sound then return end
	pcall(function()
		sound.PlaybackSpeed = speed or 1
		sound.Volume = volume or 0.5
		sound.TimePosition = 0
		sound:Play()
	end)
end

--..Game: inputs -> the run's event list (+ the outbox to the server)..--
local function Emit(g, kind)
	local run = g.run
	if g.state ~= "play" or not run or run.Sim.Dead then return end
	--.. stamped with the tick running NOW on the server clock, never before the next one / the last event: after a
	--.. hitch the sim has not caught up yet, and an input stamped with its stale tick would reach every replay after
	--.. it had passed that tick
	local tick = math.max(run.Sim.N + 1, math.floor((Kit.Now() - g.since - READY) * TICK_RATE), run.Ticks[#run.Ticks] or 0)
	table.insert(run.Ticks, tick)
	table.insert(run.Kinds, kind)
	table.insert(g.outbox, {t = tick / TICK_RATE, k = EVENT_NAMES[kind]})
	if kind == EV_DUCK then PlayUi(g, "Duck", 1.7, 0.18) end
end

--.. a jump / duck holder (a key, "mouse", a touch) goes down / up: press / release events on the first / last one
local function Hold(g, which, key, down)
	local set = which == "jump" and g.jumpHolds or g.duckHolds
	local was = next(set) ~= nil
	set[key] = down or nil
	local now = next(set) ~= nil
	if now == was then return end
	if which == "jump" then
		Emit(g, now and EV_JUMP or EV_JUMP_UP)
		g.ui.JumpPop.Scale = now and 0.93 or 1
	else
		Emit(g, now and EV_DUCK or EV_DUCK_UP)
		g.ui.DuckPop.Scale = now and 0.93 or 1
	end
end

--.. send what is waiting (at most every SEND_GAP s unless forced)
local function Flush(g, force)
	if #g.outbox == 0 or not g.run then return end
	local now = os.clock()
	if not force and now - g.sentAt < SEND_GAP then return end
	g.sentAt = now
	local batch = g.outbox
	if #batch > SEND_MAX then
		g.outbox = table.move(batch, SEND_MAX + 1, #batch, 1, {})
		batch = table.move(batch, 1, SEND_MAX, 1, {})
	else
		g.outbox = {}
	end
	if #batch == 1 then
		g.Ctx:Send("Input", {s = g.run.Seed, t = batch[1].t, k = batch[1].k})
	else
		g.Ctx:Send("Input", {s = g.run.Seed, e = batch})
	end
end

local function SendOver(g)
	local run = g.run
	if not run then return end
	local seconds = (run.Sim.Dead and run.Sim.DeadTick or run.Sim.N) / TICK_RATE
	g.Ctx:Send("Over", {s = run.Seed, score = Score(run.Sim), seconds = seconds})
	g.overAt = os.clock()
	g.overTries += 1
end

--..Game: runs..--
local function StartLocalRun(g, seed, since)
	local run = NewRun(seed)
	run.Owned, run.Complete = true, true
	g.run = run
	g.since = since
	g.clock = Kit.Now() - since - READY -- the server clock (GameFrame); a GUI that opens late starts mid-run
	g.state = "ready"
	g.jumpHolds, g.duckHolds, g.outbox = {}, {}, {}
	g.overTries, g.overAt, g.againAt, g.deadAt = 0, 0, nil, nil
	g.cardShown, g.overReady, g.cardT, g.recordShown = false, false, nil, false
	g.countText, g.countAt = nil, 0
	g.ui.Card.Visible = false
	g.ui.Hint.Visible = true
	g.ui.Count.Visible = true
	g.ui.Count.Text = ""
	g.ui.Again.Text = "PLAY AGAIN"
	g.ui.JumpPop.Scale, g.ui.DuckPop.Scale = 1, 1
end

local function OnDeath(g)
	local run = g.run
	g.state = "dead"
	g.deadAt = os.clock()
	g.jumpHolds, g.duckHolds = {}, {}
	g.ui.JumpPop.Scale, g.ui.DuckPop.Scale = 1, 1
	Flush(g, true)
	g.score = Score(run.Sim)
	g.newBest = g.score > PersonalBest
	if g.newBest then PersonalBest = g.score end
	SendOver(g)
	g.shake, g.flash = 0.35, 1
	PlayUi(g, "Crash", 1.15, 0.7)
end

local function Again(g)
	if g.state ~= "dead" or not g.overReady then return end
	if g.againAt and os.clock() - g.againAt < AGAIN_RESEND then return end
	PlayUi(g, "Click")
	g.againAt = os.clock()
	g.ui.Again.Text = "..."
	g.Ctx:Send("Again", {s = g.run and g.run.Seed or 0})
end

local function CloseGame(g, standUp)
	if g.closed then return end
	g.closed = true
	--.. leaving mid-run: the run so far is the score (the server still checks it)
	if g.state == "play" and g.run and not g.run.Sim.Dead then
		Flush(g, true)
		SendOver(g)
	end
	for _, c in ipairs(g.conns) do c:Disconnect() end
	pcall(function() ContextActionService:UnbindAction(ACTION) end)
	if g.controls then pcall(function() g.controls:Enable() end) end
	if g.ui and g.ui.Gui then g.ui.Gui:Destroy() end
	local w = g.W
	--.. the monitor goes on showing this run: hand it over with its full event list (relays of our own run were skipped)
	if g.run then
		g.run.Owned = false
		w.Run = g.run
	end
	if w.Game == g then w.Game = nil end
	w.Declined = true -- no reopening until they sit down again
	if Active == g then Active = nil end
	if standUp and g.Ctx:Alive() then
		g.Ctx:Send("Leave")
		local humanoid = g.Ctx:LocalCharacter()
		if humanoid then
			pcall(function()
				humanoid.Sit = false
				humanoid.Jump = true
			end)
		end
	end
end

--..Game: frame..--
local function UpdateOverlay(g, dt, best, final, ended, since, seed)
	local ui = g.ui
	local run = g.run
	--.. READY? / GO!
	local text = ""
	if g.state == "ready" then
		text = (g.clock + READY) < READY * 0.62 and "READY?" or "GO!"
	elseif g.state == "play" and g.clock < 0.35 then
		text = "GO!"
	end
	if text ~= g.countText then
		g.countText, g.countAt = text, os.clock()
		ui.Count.Text = text
		if text == "READY?" then PlayUi(g, "Click", 1.2) elseif text == "GO!" then PlayUi(g, "Go", 1.4) end
	end
	local f = math.clamp((os.clock() - g.countAt) / 0.4, 0, 1)
	ui.CountScale.Scale = 1 + 0.6 * (1 - f) ^ 3
	ui.Count.TextTransparency = (g.state == "play" and g.clock > 0.15) and math.clamp((g.clock - 0.15) / 0.2, 0, 1) or 0
	ui.Hint.Visible = g.state == "ready"

	--.. HUD
	local s = run and run.Sim
	SetText(ui.Score, "SCORE " .. Pad(s and Score(s) or 0))
	SetText(ui.Coins, "x " .. tostring(s and s.Coins or 0))
	SetText(ui.Hi, "HI " .. Pad(math.max(best, PersonalBest)))
	ui.CoinScale.Scale = math.max(1, ui.CoinScale.Scale - dt * 3)
	ui.PlateStroke.Color = Color3.fromHSV((os.clock() * LOOK.RGB_RATE_PLAY) % 1, LOOK.RGB_SAT, 1)

	--.. crash: shake + red flash
	if (g.shake or 0) > 0 then
		g.shake = math.max(0, g.shake - dt)
		local amp = 9 * g.shake / 0.35
		ui.Panel.Position = UDim2.new(0.5, (math.random() * 2 - 1) * amp, 0.5, LOOK.PANEL_DROP + (math.random() * 2 - 1) * amp)
		if g.shake <= 0 then ui.Panel.Position = UDim2.new(0.5, 0, 0.5, LOOK.PANEL_DROP) end
	end
	if (g.flash or 0) > 0 then
		g.flash = math.max(0, g.flash - dt * 3)
		ui.Flash.BackgroundTransparency = 1 - 0.45 * g.flash
	end

	--.. GAME OVER card
	if g.state == "dead" then
		local t = os.clock() - g.deadAt
		if not g.cardShown and t >= CARD_DELAY then
			g.cardShown, g.cardT = true, 0
			ui.CardScore.Text = tostring(g.score)
			ui.CardBest.Text = "BEST " .. tostring(PersonalBest)
			ui.CardScale.Scale = 0.6
			ui.Card.Visible = true
			PlayUi(g, g.newBest and "Win" or "Lose", 1, g.newBest and 0.5 or 0.4)
		end
		if g.cardShown then
			if not g.overReady and t >= CARD_DELAY + CARD_READY then g.overReady = true end
			--.. the server took the score as this desk's new best
			local record = g.score > 0 and seed == run.Seed and ended > since and final == g.score and best == g.score
			if record and not g.recordShown then
				g.recordShown = true
				if not g.newBest then PlayUi(g, "Win") end
			end
			if g.recordShown then
				SetText(ui.CardTag, LOOK.PARTY .. " NEW DESK RECORD! " .. LOOK.PARTY)
			else
				SetText(ui.CardTag, g.newBest and "NEW BEST!" or "")
			end
			SetText(ui.CardHi, "DESK HI  " .. tostring(best))
			if g.cardT and g.cardT < 1 then
				g.cardT = math.min(1, g.cardT + dt / 0.28)
				local u = g.cardT - 1
				ui.CardScale.Scale = 0.6 + 0.4 * (1 + 2.7 * u * u * u + 1.7 * u * u) -- ease out back
			end
		end
	end
end

local function GameFrame(g, dt)
	local ctx = g.Ctx
	if not ctx:Alive() then CloseGame(g, false) return end
	local player, since, ended, final, best, seed = ReadState(ctx)

	--.. still in this desk's chair? (a moment's grace: the seat weld and the state replicate separately)
	local humanoid = ctx:LocalCharacter()
	local seated = humanoid ~= nil and humanoid.SeatPart ~= nil and humanoid.SeatPart.Name == SEAT_NAME
		and player == LocalPlayer.UserId and ctx:Near(CLOSE_RANGE)
	if seated then
		g.lostAt = nil
	elseif not g.lostAt then
		g.lostAt = os.clock()
	elseif os.clock() - g.lostAt > SEAT_GRACE then
		CloseGame(g, false)
		return
	end

	--.. a new run from the server (sitting down, PLAY AGAIN)
	local live = seed ~= 0 and since > ended
	if live and (not g.run or g.run.Seed ~= seed) then StartLocalRun(g, seed, since) end

	--.. the run: fixed steps up to the SERVER clock, the one every replay runs on. A hitch skips time (the ticks it
	--.. missed run now, at most SIM_BUDGET a frame) instead of pausing: a paused run would stay behind the replays
	--.. for good and every later input would reach them after they had passed it
	local run = g.run
	local now = Kit.Now()
	if run then
		if g.state == "ready" or g.state == "play" then
			g.clock = now - g.since - READY
			if g.clock >= 0 then
				g.state = "play"
				Advance(run, math.floor(g.clock * TICK_RATE), SIM_BUDGET, g.hooks)
				if run.Sim.Dead then OnDeath(g) end
			end
		end
		ViewRun(g.view, g.L, run)
	else
		ViewAttract(g.view, g.L, now)
	end
	local night = workspace:GetAttribute("IsNight") == true
	if night ~= g.night then
		g.night = night
		for _, S in ipairs(g.scenes) do PaintScene(S, night) end
	end
	DrawWorld(g.scenes, g.L, g.view, now, nil)
	UpdateOverlay(g, dt, best, final, ended, since, seed)
	Flush(g, false)

	--.. the server has not ended the run yet: say it again (a dropped "Over" would leave it live)
	if g.state == "dead" and run and seed == run.Seed and live and g.overTries < 4 and os.clock() - g.overAt > OVER_RESEND then
		SendOver(g)
	end
	if g.againAt and os.clock() - g.againAt > AGAIN_RESEND and g.state == "dead" then g.ui.Again.Text = "PLAY AGAIN" end
end

--..Game: input..--
local function BindInput(g)
	local ui = g.ui
	ContextActionService:BindActionAtPriority(ACTION, function(_, state, input)
		local key = input.KeyCode
		if key == K.Thumbstick1 then
			Hold(g, "duck", "stick", input.Position.Y < -0.6)
		elseif state == Enum.UserInputState.Begin then
			if EXIT_KEYS[key] then
				CloseGame(g, true)
			elseif g.state == "dead" then
				if AGAIN_KEYS[key] then
					Again(g)
				elseif CARD_EXIT_KEYS[key] and g.overReady then
					CloseGame(g, true)
				end
			elseif JUMP_KEYS[key] then
				Hold(g, "jump", key, true)
			elseif DUCK_KEYS[key] then
				Hold(g, "duck", key, true)
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			if JUMP_KEYS[key] then Hold(g, "jump", key, false) end
			if DUCK_KEYS[key] then Hold(g, "duck", key, false) end
		end
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, table.unpack(SUNK_KEYS))

	--.. mouse / touch: the game view and the JUMP button jump, the DUCK button ducks (held); one "mouse" holder
	local function Holder(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then return "mouse" end
		if input.UserInputType == Enum.UserInputType.Touch then return input end
		return nil
	end
	local function OnPress(which)
		return function(input)
			local key = Holder(input)
			if key and g.state ~= "dead" then Hold(g, which, key, true) end
		end
	end
	table.insert(g.conns, ui.Tap.InputBegan:Connect(OnPress("jump")))
	table.insert(g.conns, ui.Jump.InputBegan:Connect(OnPress("jump")))
	table.insert(g.conns, ui.Duck.InputBegan:Connect(OnPress("duck")))
	table.insert(g.conns, UserInputService.InputEnded:Connect(function(input)
		local key = Holder(input)
		if not key then return end
		Hold(g, "jump", key, false)
		Hold(g, "duck", key, false)
	end))
	table.insert(g.conns, ui.Close.Activated:Connect(function() CloseGame(g, true) end))
	table.insert(g.conns, ui.Exit.Activated:Connect(function() CloseGame(g, true) end))
	table.insert(g.conns, ui.Again.Activated:Connect(function() Again(g) end))
end

local function Fit(g)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local s = math.min((viewport.X - 24) / LOOK.PANEL.X, (viewport.Y - 24 - LOOK.PANEL_DROP * 2) / LOOK.PANEL.Y)
	g.ui.Scale.Scale = math.clamp(s, 0.3, 1.2)
end

--.. the PlayerModule's controls (off while playing: no walking, and the touch jump button is hidden)
local function Controls()
	local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then return nil end
	local ok, controls = pcall(function() return require(module):GetControls() end)
	return ok and controls or nil
end

local function OpenGame(w)
	local g = {
		W = w, Ctx = w.Ctx, conns = {}, L = GuiLayout(), view = NewView(), run = nil, clock = 0, state = "wait",
		jumpHolds = {}, duckHolds = {}, outbox = {}, sentAt = 0, overTries = 0, overAt = 0, score = 0,
		shake = 0, flash = 0, countText = nil, countAt = 0,
	}
	g.ui = BuildGui(g)
	MakeSounds(g)
	g.hooks = {
		Jump = function() PlayUi(g, "Jump", 1.9, 0.3) end,
		Coin = function()
			PlayUi(g, "Coin", 1.1 + math.random() * 0.12, 0.45)
			g.ui.CoinScale.Scale = 1.6
		end,
		Press = function() if w.Clack then w.Clack() end end,
	}
	Fit(g)
	local camera = workspace.CurrentCamera
	if camera then table.insert(g.conns, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() Fit(g) end)) end
	BindInput(g)
	g.controls = Controls()
	if g.controls then pcall(function() g.controls:Disable() end) end
	local humanoid = w.Ctx:LocalCharacter()
	if humanoid then table.insert(g.conns, humanoid.Died:Connect(function() CloseGame(g, false) end)) end
	g.ui.Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	w.Game = g
	Active = g
	table.insert(g.conns, RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(GameFrame, g, dt)
		if not ok then
			warn("[GamingDesk] game frame: " .. tostring(err))
			CloseGame(g, true)
		end
	end))
	return g
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local scale = ctx.Scale
	local folder = LocalFolder()
	local origin = Kit.Origin(model)
	local w = {Model = model, Ctx = ctx, Game = nil, Run = nil, Fresh = {}, SyncAt = -math.huge, Declined = false}
	ctx.Desk = w

	--..Screens..--
	local arts = Kit.Parts(model, ART_PREFIX)
	local panels = {}
	for _, name in ipairs(PANEL_NAMES) do
		local p = Kit.Part(model, name)
		if p then
			local cf, size, right = PanelGeometry(model, p, arts, scale)
			table.insert(panels, {Name = name, Part = p, CFrame = cf, Size = size, Right = right})
		end
	end
	local scenes = {}
	local screenLight
	if #panels > 0 then
		--.. slices run from the viewer's left (+X authored = the panels' "right") to their right
		local ref = panels[1].Right
		for _, pn in ipairs(panels) do
			if pn.Name == CENTRE_PANEL then ref = pn.Right end
		end
		local mid = origin.Position
		table.sort(panels, function(a, b) return (a.CFrame.Position - mid):Dot(ref) > (b.CFrame.Position - mid):Dot(ref) end)
		local L = {}
		local heightPx = math.huge
		for _, pn in ipairs(panels) do heightPx = math.min(heightPx, math.floor(pn.Size.Y * PPS)) end
		L.H = math.max(ART_H * 2, heightPx)
		L.U = math.max(2, math.floor(L.H / ART_H))
		local x = 0
		local centreIndex = 1
		for i, pn in ipairs(panels) do
			pn.OffsetPx = x
			pn.WidthPx = math.floor(pn.Size.X * PPS + 0.5)
			x += pn.WidthPx
			if pn.Name == CENTRE_PANEL then centreIndex = i end
		end
		if not Kit.Part(model, CENTRE_PANEL) then --.. no centre panel: the widest one hosts the HUD
			for i, pn in ipairs(panels) do
				if pn.WidthPx > panels[centreIndex].WidthPx then centreIndex = i end
			end
		end
		L.W = x
		L.AW = L.W / L.U
		L.groundA = L.H / L.U - GROUND_H
		L.centreX0 = panels[centreIndex].OffsetPx
		L.centreW = panels[centreIndex].WidthPx
		L.heroA = (L.centreX0 + HERO_AT * L.centreW) / L.U
		for i, pn in ipairs(panels) do
			local part = ctx:Part({Name = "GamingDesk" .. pn.Name, Size = pn.Size, CFrame = pn.CFrame, Transparency = 1, Parent = folder})
			local gui = New("SurfaceGui", {
				Name = "GameScreen", Face = Enum.NormalId.Front, LightInfluence = 0, Brightness = BRIGHTNESS,
				SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = PPS,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Adornee = part,
			})
			Try(gui, "ClipsDescendants", true)
			Try(gui, "MaxDistance", GUI_MAX_DISTANCE)
			gui.Parent = part
			local S = NewScene(gui, L, pn.OffsetPx, i == centreIndex)
			S.hud = i == centreIndex
			table.insert(scenes, S)
			if i == centreIndex then
				screenLight = New("SurfaceLight", {
					Face = Enum.NormalId.Front, Range = LIGHT_RANGE * scale, Angle = LIGHT_ANGLE, Brightness = LIGHT_IDLE,
					Color = LIGHT_COLOR, Shadows = false,
				}, part)
				pn.Host = part
			end
		end
		scenes.L = L
		scenes.host = panels[centreIndex].Host
	end
	local L = scenes.L
	local view = NewView()

	--..RGB parts + the glow under the desk..--
	local rgb = {}
	for _, p in ipairs(Kit.Parts(model, LOOK.RGB_PREFIX)) do
		local ax = origin:PointToObjectSpace(p.Position).X / math.max(0.01, scale)
		table.insert(rgb, {Part = p, Home = p.Color, Phase = (0.5 - ax / DESK_WIDTH) * LOOK.RGB_WAVE})
	end
	local glowPos = Kit.Pivot(model, "RGBGlow") or Kit.ToWorld(model, LOOK.GLOW_FALLBACK)
	local glowPart = ctx:Part({Name = "GamingDeskGlow", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(glowPos), Transparency = 1, Parent = folder})
	local glow = New("PointLight", {Range = LOOK.GLOW_RANGE * scale, Brightness = LOOK.GLOW_BRIGHTNESS, Shadows = false, Color = Color3.new(1, 0, 1)}, glowPart)

	--..Chair rig (relative to the sitting pose; the parts ship turned State_ChairIdleYaw)..--
	local idleYaw = tonumber(model:GetAttribute("State_ChairIdleYaw")) or LOOK.DEFAULT_IDLE_YAW
	local sitYaw = tonumber(model:GetAttribute("State_ChairSitYaw")) or LOOK.DEFAULT_SIT_YAW
	local swivelParts = Kit.Parts(model, LOOK.SWIVEL_PREFIX)
	local swivelPos = Kit.Pivot(model, "ChairSwivel") or Kit.ToWorld(model, LOOK.SWIVEL_FALLBACK)
	local pivot0 = CFrame.new(swivelPos) * origin.Rotation
	local pivotRel = hitbox.CFrame:ToObjectSpace(pivot0)
	local function Yaw(deg) return CFrame.Angles(0, math.rad(deg), 0) end
	local rig = Kit.Rig(swivelParts, pivot0 * Yaw(idleYaw))
	local home = {}
	for _, p in ipairs(swivelParts) do home[p] = hitbox.CFrame:ToObjectSpace(p.CFrame) end

	--..Sounds (3D, at the desk)..--
	local keysPos = Kit.Pivot(model, "Keys") or Kit.ToWorld(model, Vector3.new(0, 3.3, 0.7))
	local keysPart = ctx:Part({Name = "GamingDeskKeys", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(keysPos), Transparency = 1, Parent = folder})
	local function Sfx(parent, name, volume)
		local id = type(FunAssets.Sfx) == "table" and FunAssets.Sfx[name] or nil
		if not id or not parent then return nil end
		return ctx:Sound(parent, id, {Volume = volume, Looped = false, RollOffMaxDistance = 60})
	end
	local sfxHost = scenes.host or keysPart
	local sfxKeys = Sfx(keysPart, "Click", KEYS_VOLUME)
	local sfxCoin = Sfx(sfxHost, "Coin", GAME_VOLUME)
	local sfxGo = Sfx(sfxHost, "ArcadeBlip", GAME_VOLUME)
	local sfxWin = Sfx(sfxHost, "ArcadeWin", GAME_VOLUME)
	local sfxLose = Sfx(sfxHost, "ArcadeLose", GAME_VOLUME * 0.8)
	local sfxCrash = Sfx(sfxHost, "Thump", GAME_VOLUME * 1.4)
	local rng = Random.new()
	local function Play(sound, speed, volume)
		if not sound then return end
		pcall(function()
			if speed then sound.PlaybackSpeed = speed end
			if volume then sound.Volume = volume end
			sound.TimePosition = 0
			sound:Play()
		end)
	end
	local function Near() return ctx:CameraDistance() <= KEYS_RANGE end
	--.. a keyboard clack for every press of the gamer (their GUI calls it too)
	w.Clack = function()
		if Near() then Play(sfxKeys, rng:NextNumber(1.3, 1.9), KEYS_VOLUME * rng:NextNumber(0.7, 1.1)) end
	end
	local worldHooks = {
		Press = w.Clack,
		Coin = function() if Near() then Play(sfxCoin, rng:NextNumber(1.05, 1.2)) end end,
		Crash = function() if Near() then Play(sfxCrash, 1.15) end end,
	}

	--..Runs: the gamer's own (the GUI) or a replay of the relayed inputs..--
	--.. seeds that started while this client watched: their event lists are complete without a "Sync"
	local firstSeed = true
	ctx:OnState("Seed", function(v)
		local seed = tonumber(v) or 0
		if firstSeed then
			firstSeed = false
			return
		end
		if seed ~= 0 then w.Fresh[seed] = true end
	end)
	local function GetRun(seed)
		if not seed or seed == 0 then return nil end
		local g = w.Game
		if g and g.run and g.run.Seed == seed then return g.run end
		if not w.Run or w.Run.Seed ~= seed then
			w.Run = NewRun(seed)
			w.Run.Complete = w.Fresh[seed] == true
		end
		return w.Run
	end
	w.GetRun = GetRun
	local function NeedSync(run)
		if run.Owned or run.Complete or os.clock() - w.SyncAt < SYNC_RETRY then return end
		w.SyncAt = os.clock()
		ctx:Send("Sync", {s = run.Seed})
	end

	--..Night..--
	local night = nil
	local function SyncNight()
		local n = workspace:GetAttribute("IsNight") == true
		if n == night then return end
		night = n
		for _, S in ipairs(scenes) do PaintScene(S, n) end
	end
	SyncNight()
	ctx:Connect(workspace:GetAttributeChangedSignal("IsNight"), SyncNight)

	--..Names..--
	local nameCache = {}
	local function NameOf(id)
		if id == -1 then return "CPU" end
		if nameCache[id] then return nameCache[id] end
		local p = Players:GetPlayerByUserId(id)
		local n = p and p.DisplayName or "PLAYER"
		n = string.upper(n):sub(1, 12)
		nameCache[id] = n
		return n
	end

	--..The monitor: the attract loop, or the run (the gamer's own simulation, or the replay SPECTATOR_DELAY behind)..--
	local hud = {Score = "", Name = "", Coins = "", Big = "", Small = "", BigY = BIG_Y.other, SmallY = SMALL_Y.other}
	local lastMode = nil
	local function DrawScreens(now, woke)
		if not L then return "idle" end
		local player, since, ended, final, best, seed = ReadState(ctx)
		local live = seed ~= 0 and since > ended
		local mode
		if live then
			mode = now - since < READY and "ready" or "run"
		elseif seed ~= 0 and ended > 0 and (player > 0 or now - ended < OVER_TIME) then
			mode = "over"
		else
			mode = "idle"
		end
		local nearSound = not woke and Near()
		local mine = w.Game ~= nil and player == LocalPlayer.UserId -- the gamer hears their GUI instead
		local run = mode ~= "idle" and GetRun(seed) or nil
		if not run then mode = "idle" end
		local s = run and run.Sim
		if run then
			if not run.Owned then
				NeedSync(run)
				local target
				if mode == "over" then
					--.. the run's own last tick (the gamer's report); a replay that ran past it (inputs stopped, the end
					--.. not heard yet) goes back to it - no crash / coins after an EXIT that never happened
					local endTick = tonumber(ctx:State("EndTick")) or 0
					target = endTick > 0 and math.floor(endTick) or math.floor((ended - since - READY) * TICK_RATE)
					if s.N > target then run.Dirty = math.min(run.Dirty or math.huge, target + 1) end
				else
					target = math.floor((now - since - READY - SPECTATOR_DELAY) * TICK_RATE)
				end
				--.. (a replay without its full list waits for the "Events" answer instead of crashing at the first obstacle)
				if target > 0 and run.Complete then Advance(run, target, SIM_BUDGET, (nearSound and not mine) and worldHooks or nil) end
			end
			ViewRun(view, L, run)
		else
			ViewAttract(view, L, now)
		end

		--.. texts
		local blink = (now % 1) < 0.6
		if mode == "idle" then
			hud.Score = best > 0 and ("HI " .. Pad(best)) or ""
			hud.Name, hud.Coins, hud.Big = "", "", "CUKE RUN"
			hud.Small = blink and "SIT TO PLAY" or ""
		elseif mode == "ready" then
			hud.Score, hud.Name, hud.Coins = "SCORE " .. Pad(0), "P1 " .. NameOf(player), "COINS 0"
			hud.Big = (now - since) < READY * 0.62 and "READY?" or "GO!"
			hud.Small = ""
		elseif mode == "run" and not s.Dead then
			hud.Score, hud.Name, hud.Coins = "SCORE " .. Pad(Score(s)), "P1 " .. NameOf(player), "COINS " .. s.Coins
			hud.Big, hud.Small = "", ""
		else --.. the crash (seen in the replay) / GAME OVER
			local score = mode == "over" and final or Score(s)
			hud.Score = "HI " .. Pad(best)
			hud.Coins = "COINS " .. s.Coins
			hud.Big = "GAME OVER"
			hud.Small = (mode == "over" and player > 0 and (now % 2) >= 1.2) and "PLAY AGAIN?" or ("SCORE " .. Pad(score))
			hud.Name = (mode == "over" and final > 0 and final >= best and blink) and "NEW HI-SCORE!" or ""
		end
		hud.BigY = mode == "idle" and BIG_Y.idle or BIG_Y.other
		hud.SmallY = mode == "idle" and SMALL_Y.idle or SMALL_Y.other
		DrawWorld(scenes, L, view, now, hud)

		--.. stings (the gamer's GUI plays its own)
		if nearSound and not mine then
			if lastMode == "ready" and mode == "run" then Play(sfxGo, 1.4) end
			if lastMode == "run" and mode == "over" then
				if final > 0 and final >= best then Play(sfxWin) else Play(sfxLose) end
			end
		end
		lastMode = mode
		if screenLight then screenLight.Brightness = (mode == "run" or mode == "ready") and LIGHT_PLAY or LIGHT_IDLE end
		return mode
	end

	--..RGB colours..--
	local rgbPhase = (Kit.Now() * LOOK.RGB_RATE_IDLE) % 1
	local function DrawRGB(dt, playing)
		rgbPhase = (rgbPhase + dt * (playing and LOOK.RGB_RATE_PLAY or LOOK.RGB_RATE_IDLE)) % 1
		for _, r in ipairs(rgb) do
			if r.Part.Parent then r.Part.Color = Color3.fromHSV((rgbPhase + r.Phase) % 1, LOOK.RGB_SAT, 1) end
		end
		glow.Color = Color3.fromHSV(rgbPhase, LOOK.RGB_SAT, 1)
	end

	--..Every frame..--
	local yaw, yawVel = idleYaw, 0
	local target = idleYaw
	local spin = nil         -- {From, To, At}: the spin-out after the gamer gets up
	local wasSeated = nil
	--.. the same pose, within half a turn of `to` (so the spring takes the short way round)
	local function NearYaw(a, to) return to + ((a - to + 180) % 360 - 180) end
	local written, writtenAt
	local lastClock = -math.huge
	local screenAcc, rgbAcc = math.huge, math.huge
	ctx:Step(function(dt, now)
		if not hitbox.Parent then return end
		local clock = os.clock()
		local woke = clock - lastClock > WAKE_GAP
		lastClock = clock
		dt = math.clamp(dt, 0, MAX_DT)
		local player, since, ended, _, _, seed = ReadState(ctx)
		local seated = player ~= 0
		local playing = seated and seed ~= 0 and since > ended and now - since >= READY

		--.. the local player sat down in this chair: open the game (once per sitting)
		if player == LocalPlayer.UserId then
			if not w.Game and not w.Declined then
				local humanoid = ctx:LocalCharacter()
				if humanoid and humanoid.SeatPart and humanoid.SeatPart.Name == SEAT_NAME then
					if Active and not Active.closed then CloseGame(Active, false) end
					OpenGame(w)
				end
			end
		else
			w.Declined = false
		end

		--.. chair: face the desk while seated (rocking while playing); a free spin back out when they get up
		if woke or wasSeated == nil then
			target = seated and sitYaw or idleYaw
			yaw, yawVel, spin = target, 0, nil
		elseif seated ~= wasSeated then
			if seated then
				target, spin = sitYaw, nil
				yaw = NearYaw(yaw, sitYaw)
			else
				target = idleYaw
				spin = {From = NearYaw(yaw, idleYaw), To = idleYaw + LOOK.SPIN_OUT, At = now}
			end
		end
		wasSeated = seated
		if spin then
			--.. pushed round, slowing at a constant rate: angle = from + total * (1 - (1 - u)^2)
			local u = math.clamp((now - spin.At) / LOOK.SPIN_TIME, 0, 1)
			yaw = spin.From + (spin.To - spin.From) * (1 - (1 - u) * (1 - u))
			yawVel = 0
			if u >= 1 then yaw, spin = idleYaw, nil end -- one turn on = the shipped pose
		elseif not woke then
			local goal = target
			if seated and playing then goal = sitYaw + LOOK.ROCK_DEG * math.sin(now * math.pi * 2 * LOOK.ROCK_HZ) end
			yawVel += (LOOK.SPRING_K * (goal - yaw) - LOOK.SPRING_C * yawVel) * dt
			yaw += yawVel * dt
			if not seated and math.abs(goal - yaw) < 0.01 and math.abs(yawVel) < 0.05 then yaw, yawVel = goal, 0 end
		end
		local hb = hitbox.CFrame
		if #swivelParts > 0 and (written == nil or math.abs(yaw - written) > 1e-3 or hb ~= writtenAt) then
			Kit.PoseRig(rig, hb * pivotRel * Yaw(yaw))
			written, writtenAt = yaw, hb
		end

		--.. screens at SCREEN_FPS, only when the camera is close enough to see them
		screenAcc += dt
		if L and (woke or screenAcc >= 1 / SCREEN_FPS) then
			screenAcc = 0
			if woke or ctx:CameraDistance() <= SCREEN_RANGE then
				DrawScreens(now, woke)
			end
		end

		--.. rainbow at RGB_FPS
		rgbAcc += dt
		if woke or rgbAcc >= 1 / LOOK.RGB_FPS then
			DrawRGB(math.min(rgbAcc, 0.25), playing)
			rgbAcc = 0
		end
	end)

	--..Cleanup: the game closed, the chair as shipped (relative to where the build IS now), RGB colours back..--
	return function()
		if w.Game then CloseGame(w.Game, false) end
		if hitbox.Parent then
			for part, rel in pairs(home) do
				if part.Parent then part.CFrame = hitbox.CFrame * rel end
			end
		end
		for _, r in ipairs(rgb) do
			if r.Part.Parent then r.Part.Color = r.Home end
		end
	end
end

--..Server events: the gamer's inputs (relayed as they come) and whole lists (the answer to "Sync")..--
function B.OnEvent(model, action, payload, ctx)
	local w = ctx.Desk
	if not w or type(payload) ~= "table" then return end
	local seed = tonumber(payload.s)
	if not seed or seed == 0 or seed ~= (tonumber(ctx:State("Seed")) or 0) then return end
	local run = w.GetRun and w.GetRun(seed)
	if not run or run.Owned then return end -- the gamer's own run already has every event
	local codes = type(payload.c) == "table" and payload.c or {}
	local n = tonumber(payload.n) or -1 -- the server's count after this batch (-1: its list is full, just follow)
	if action == "Input" then
		if n >= 0 then
			local have = #run.Ticks
			if n <= have then return end
			if n - #codes ~= have then
				run.Complete = false -- a gap (this client arrived late): the next draw asks for the whole list
				return
			end
		end
		for _, code in ipairs(codes) do AddCode(run, code) end
	elseif action == "Events" then
		SetCodes(run, codes)
		run.Complete = true
	end
end

--.. the simulation, for headless tests (tests/HomeOffice)
B.Sim = {
	NewRun = NewRun, NewSim = NewSim, StepSim = StepSim, Advance = Advance, Snapshot = Snapshot, Restore = Restore,
	Score = Score, Extend = Extend, AddCode = AddCode, SetCodes = SetCodes, Speed = Speed, Kinds = KINDS,
	TickRate = TICK_RATE, Ready = READY, HeroHalf = HERO_HALF,
}

return B
