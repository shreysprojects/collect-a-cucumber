--[[
	TV  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the working TV (fun-builds/CONTRACT.md, package TV). The server half owns the state:
	  Fun_On (bool), Fun_Channel (index into FunAssets.TVChannels), Fun_Since (Kit.Now() when the channel started)
	This half draws the picture on a LOCAL screen: an invisible Part laid just in front of the screen aperture,
	computed from the ScreenSky part's real CFrame / Size (so the build's Scale and any mesh yaw are honoured) and
	pushed out past the front-most Neon layer (ScreenSun), carrying a SurfaceGui (Front face toward the viewer,
	LightInfluence 0, PixelsPerStud):
	  OFF   a dark glossy panel with a faint reflection streak that moves with the viewer (as a reflection on glass
	        does); the stand-by dot (a local disc laid over the RedLights dot on the bezel) blinks red - in step on
	        every client (Kit.Now())
	  ON    the channel. Slides: two ImageLabels cross-fading every Seconds with a slow zoom; the slide index is
	        (Kit.Now() - Since) / Seconds, so every client shows the same slide. Video: a looped VideoFrame that
	        plays only while the camera is within VIDEO_PLAY_RANGE (volume fades with distance; muted unless the
	        channel says Sound = true, as FunAssets documents), its position synced to Since. The video sits UNDER
	        its stand-in pictures (the channel's Slides, else the first slideshow's, else colour bars), which come
	        off once it has loaded: near, "Tuning..." shows until then, and a video that has not loaded
	        VIDEO_TIMEOUT s after it was assigned shows the stand-ins + "NO SIGNAL"; from beyond VIDEO_LOAD_RANGE
	        (never downloaded there) the stand-ins show quietly. A channel with neither (or an empty channel list)
	        shows colour bars
	  far   the Step sleeps beyond StepRange but the SurfaceGui draws out to GUI_MAX_DISTANCE: a new slide list
	        draws its slide at once, and a 4 Hz ctx:Every keeps the slides turning out there
	  power on   CRT "expand from a line" under a white flash + Sfx.TVOn, then the channel OSD
	  power off  squash to a line, then to a dot, a fading afterglow + Sfx.TVOff
	  channel    STATIC_TIME of procedural static (a grid of grey cells + rolling bands) + Sfx.TVStatic, and the
	             channel number / name OSD top-left for OSD_TIME
	A SurfaceLight (soft white-blue, Range 12) glows from the screen while it is on. The build's own parts are
	never touched: the original Neon picture simply sits under the local screen.
	The screen part lives in a client-only workspace folder (LOCAL_FOLDER), not the Camera, so its SurfaceLight
	lights the room for sure; the ctx destroys it with everything else.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

--..Config..--
local LOCAL_FOLDER = "FunBuildLocal"   -- client-only folder in workspace for the screen + stand-by dot parts
local PPS = 50                         -- SurfaceGui pixels per stud
local BRIGHTNESS = 1.2                 -- SurfaceGui brightness (LightInfluence 0)
local GUI_MAX_DISTANCE = 260           -- studs: the SurfaceGui stops drawing beyond this
local SCREEN_LAYERS = {"ScreenSky", "ScreenLand", "ScreenSun"} -- the original Neon picture, back to front
local GAP = 0.014                      -- authored studs between the front-most Neon layer and the local screen face
local THICK = 0.04                     -- authored thickness of the (invisible) screen part, behind its face
local SKY_FALLBACK = {                 -- authored (props-dump/TV.txt, build_tv.py) if ScreenSky is missing
	Centre = Vector3.new(0, 3.55, -0.06), Width = 4.68, Height = 2.36, Lead = 0.06,
}
local DOT_CENTRE = Vector3.new(-1.75, 2.23, -0.1725) -- authored: build_tv.py stand-by dot (x -1.75, panel bottom + 0.13), just proud of the bezel
local DOT_DIAMETER, DOT_THICK = 0.18, 0.025          -- authored; covers the 0.075-radius Neon dot underneath
local DOT_LIT = Color3.fromRGB(255, 58, 58)
local DOT_DIM = Color3.fromRGB(62, 22, 24)
local BLINK_PERIOD, BLINK_LIT = 1.6, 0.95            -- s: the stand-by dot is lit for BLINK_LIT of every BLINK_PERIOD
local LIGHT_COLOR = Color3.fromRGB(205, 225, 255)
local LIGHT_RANGE, LIGHT_BRIGHTNESS, LIGHT_ANGLE = 12, 1.4, 120
local VIDEO_LOAD_RANGE = 150           -- studs (camera): a video channel is only assigned (downloaded) within this
local VIDEO_PLAY_RANGE = 70            -- studs (camera): the VideoFrame plays only within this
local VIDEO_FULL_RANGE = 28            -- studs (camera): full volume within this, fading to 0 at VIDEO_PLAY_RANGE
local VIDEO_VOLUME = 0.8               -- 2026-09-24 (user: "make tv play with sound"): videos are heard unless a channel says Sound = false
local MUSIC_VOLUME = 0.4               -- a slideshow channel's Music track (a 3D sound on the screen, rolls off by itself)
local MUSIC_ROLLOFF_MIN, MUSIC_ROLLOFF_MAX = 10, 75
local VIDEO_TIMEOUT = 6               -- s after assigning the video: still not loaded -> slideshow fallback + NO SIGNAL
local VIDEO_RESYNC = 1.5               -- s of drift from the shared clock before the video is re-seeked
local SLIDE_SECONDS = 4                -- default Seconds for a slideshow channel
local FADE_TIME = 0.6                  -- s: slide cross-fade
local STATIC_TIME = 0.35               -- s: channel-change static
local STATIC_COLS, STATIC_ROWS = 28, 16
local OSD_TIME = 2                     -- s: channel number / name on screen
local OSD_COLOR = Color3.fromRGB(69, 255, 0)
local FONT_TV = Enum.Font.Arcade
local OUTLINE = Color3.fromRGB(10, 10, 14)
local LINE_PX = 3                      -- px: the CRT line
local BARS = {                         -- colour bars (no channel / no fallback pictures)
	Color3.fromRGB(192, 192, 192), Color3.fromRGB(192, 192, 0), Color3.fromRGB(0, 192, 192), Color3.fromRGB(0, 192, 0),
	Color3.fromRGB(192, 0, 192), Color3.fromRGB(192, 0, 0), Color3.fromRGB(0, 0, 192),
}
local GREYS = {}
for i = 0, 9 do
	local v = math.floor(16 + i * 25)
	GREYS[i + 1] = Color3.fromRGB(v, v, v)
end

local B = {}
B.Keys = {"TV"}
B.StepRange = 180

--..Helpers..--
local function New(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

--.. set a property that may not exist on every client build
local function Try(inst, prop, value)
	pcall(function() inst[prop] = value end)
end

local function Corner(parent, radius)
	return New("UICorner", {CornerRadius = radius or UDim.new(0, 6)}, parent)
end

local function Stroke(parent, thickness)
	return New("UIStroke", {Color = OUTLINE, Thickness = thickness or 1.5}, parent)
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

--.. half a part's extent along a world direction
local function HalfExtent(part, dir)
	local cf, s = part.CFrame, part.Size
	return 0.5 * (math.abs(cf.XVector:Dot(dir)) * s.X + math.abs(cf.YVector:Dot(dir)) * s.Y + math.abs(cf.ZVector:Dot(dir)) * s.Z)
end

--.. the local screen: CFrame (LookVector = out of the screen, toward the viewer), Size, viewerRight and up.
--.. viewerRight is the VIEWER's right = the part's -X, the direction GUI +x runs on a Front-face SurfaceGui.
--.. Taken from the ScreenSky part itself: its axis nearest the build's front is the screen normal, the one
--.. nearest up is the height, the third the width; the face goes GAP past the front-most Neon layer
local function ScreenGeometry(model, scale)
	local origin = Kit.Origin(model)
	local front, upWorld = origin.LookVector, origin.UpVector
	local sky = Kit.Part(model, "ScreenSky")
	local centre, normal, up, width, height
	if sky then
		local cf = sky.CFrame
		local axes = {cf.XVector, cf.YVector, cf.ZVector}
		local sizes = {sky.Size.X, sky.Size.Y, sky.Size.Z}
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
		normal = axes[ni] * (axes[ni]:Dot(front) >= 0 and 1 or -1)
		up = axes[ui] * (axes[ui]:Dot(upWorld) >= 0 and 1 or -1)
		width, height = sizes[wi], sizes[ui]
		centre = sky.Position
	else
		normal, up = front, upWorld
		width, height = SKY_FALLBACK.Width * scale, SKY_FALLBACK.Height * scale
		centre = Kit.ToWorld(model, SKY_FALLBACK.Centre)
	end
	--.. how far the front-most layer stands out of the screen centre
	local lead
	for _, name in ipairs(SCREEN_LAYERS) do
		local p = Kit.Part(model, name)
		if p then
			local d = (p.Position - centre):Dot(normal) + HalfExtent(p, normal)
			lead = lead and math.max(lead, d) or d
		end
	end
	lead = lead or SKY_FALLBACK.Lead * scale
	local thick = THICK * scale
	local partX = up:Cross(-normal) -- the screen part's +X (the viewer's LEFT)
	local position = centre + normal * (lead + GAP * scale - thick * 0.5)
	return CFrame.fromMatrix(position, partX, up, -normal), Vector3.new(width, height, thick), -partX, up
end

--..Channels..--
local function Channels()
	return type(FunAssets.TVChannels) == "table" and FunAssets.TVChannels or {}
end

--.. the channel table at a (wrapped) index, and that index
local function ChannelAt(index)
	local list = Channels()
	if #list == 0 then return nil, 1 end
	local i = (math.floor(tonumber(index) or 1) - 1) % #list + 1
	return list[i], i
end

local function HasSlides(ch)
	return type(ch) == "table" and type(ch.Slides) == "table" and #ch.Slides > 0
end

--.. the pictures a video channel falls back to: its own Slides, else the first slideshow channel's
local function FallbackSlides(ch)
	if HasSlides(ch) then return ch.Slides, ch.Seconds end
	for _, other in ipairs(Channels()) do
		if HasSlides(other) then return other.Slides, other.Seconds end
	end
	return nil, nil
end

local Preloaded = {}
local function Preload(list)
	local todo = {}
	for _, id in ipairs(list) do
		if type(id) == "string" and not Preloaded[id] then
			Preloaded[id] = true
			table.insert(todo, id)
		end
	end
	if #todo > 0 then
		task.spawn(function() pcall(function() ContentProvider:PreloadAsync(todo) end) end)
	end
end

--..Behaviour..--
function B.Client(model, ctx)
	local scale = ctx.Scale
	local folder = LocalFolder()
	local screenCF, screenSize, viewerRight, up = ScreenGeometry(model, scale)
	local W, H = math.max(8, math.floor(screenSize.X * PPS + 0.5)), math.max(8, math.floor(screenSize.Y * PPS + 0.5))

	--..Screen part + gui..--
	local screen = ctx:Part({Name = "TVScreen", Size = screenSize, CFrame = screenCF, Transparency = 1, Parent = folder})
	--.. 2026-09-24: a slideshow channel's background music (FunAssets channel field Music), a looped 3D sound on the
	--.. screen synced to the channel clock; videos bring their own sound
	local music = ctx:Sound(screen, "", {Name = "TVMusic", Looped = true, Volume = MUSIC_VOLUME,
		RollOffMinDistance = MUSIC_ROLLOFF_MIN, RollOffMaxDistance = MUSIC_ROLLOFF_MAX})
	local musicId, musicSynced = nil, false
	local gui = New("SurfaceGui", {
		Name = "TVScreenGui",
		Face = Enum.NormalId.Front,
		LightInfluence = 0,
		Brightness = BRIGHTNESS,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PPS,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Adornee = screen,
	})
	Try(gui, "ClipsDescendants", true)
	Try(gui, "MaxDistance", GUI_MAX_DISTANCE)
	gui.Parent = screen

	local light = New("SurfaceLight", {
		Face = Enum.NormalId.Front, Range = LIGHT_RANGE, Angle = LIGHT_ANGLE, Brightness = 0,
		Color = LIGHT_COLOR, Shadows = false, Enabled = false,
	}, screen)

	--.. OFF: the dark glossy glass (always there, under the picture)
	local off = New("Frame", {Name = "Off", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 1}, gui)
	New("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 38, 47)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(16, 18, 23)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 9, 12)),
		}),
	}, off)

	--.. the tube: clips the picture during the CRT animations (the picture inside keeps its full size)
	local FULL = UDim2.fromScale(1, 1)
	local tube = New("Frame", {
		Name = "Tube", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = FULL,
		BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ClipsDescendants = true, Visible = false, ZIndex = 2,
	}, gui)
	local inner = New("Frame", {
		Name = "Picture", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H),
		BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 1,
	}, tube)
	local flash = New("Frame", {
		Name = "Flash", Size = FULL, BackgroundColor3 = Color3.fromRGB(235, 245, 255), BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 3,
	}, tube)

	--.. picture layers, bottom to top: Video 1, Bars 2, SlideBack 3, SlideFront 4, Message 5, Static 6, OSD 7.
	--.. The video sits UNDER the stand-in pictures (bars / fallback slides), which are taken away once it has
	--.. loaded, so an unloaded VideoFrame (black or not) can never hide the fallback and it keeps Visible = true

	--.. colour bars
	local bars = New("Frame", {Name = "Bars", Size = FULL, BackgroundTransparency = 1, Visible = false, ZIndex = 2}, inner)
	for i, color in ipairs(BARS) do
		New("Frame", {
			Size = UDim2.new(1 / #BARS, 1, 0.72, 0), Position = UDim2.fromScale((i - 1) / #BARS, 0),
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 1,
		}, bars)
	end
	local barsFoot = New("Frame", {Size = UDim2.fromScale(1, 0.28), Position = UDim2.fromScale(0, 0.72), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 1}, bars)
	New("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(20, 20, 24), Color3.fromRGB(235, 235, 235))}, barsFoot)

	--.. slides: back = the outgoing picture, front = the current one fading in over it
	local function Slide(name, z)
		return New("ImageLabel", {
			Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.05, 1.05),
			BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, Image = "", Visible = false, ZIndex = z,
		}, inner)
	end
	local slideBack, slideFront = Slide("SlideBack", 3), Slide("SlideFront", 4)

	--.. video
	local videoFrame
	pcall(function()
		videoFrame = New("VideoFrame", {
			Name = "Video", Size = FULL, BackgroundTransparency = 1, Looped = true, Volume = 0, Visible = false, ZIndex = 1,
		}, inner)
	end)

	--.. centre message (Tuning... / NO SIGNAL / NO CHANNELS)
	local message = New("TextLabel", {
		Name = "Message", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.2),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0, Font = FONT_TV, Text = "",
		TextColor3 = Color3.new(1, 1, 1), TextScaled = true, Visible = false, ZIndex = 5,
	}, inner)
	Corner(message)
	Stroke(message)
	New("UIPadding", {PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0)}, message)

	--.. static (cells made on the first channel change)
	local staticFrame = New("Frame", {Name = "Static", Size = FULL, BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Visible = false, ZIndex = 6}, inner)
	local staticCells, staticBands

	--.. OSD, top-left
	local osd = New("Frame", {Name = "OSD", Position = UDim2.new(0.035, 0, 0.05, 0), Size = UDim2.fromScale(0.6, 0.32), BackgroundTransparency = 1, Visible = false, ZIndex = 7}, inner)
	local osdNumber = New("TextLabel", {
		Name = "Number", Size = UDim2.fromScale(0.5, 0.56), BackgroundTransparency = 1, Font = FONT_TV, Text = "",
		TextColor3 = OSD_COLOR, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7,
	}, osd)
	Stroke(osdNumber, 2)
	local osdName = New("TextLabel", {
		Name = "ChannelName", Position = UDim2.fromScale(0, 0.6), Size = UDim2.fromScale(1, 0.34), BackgroundTransparency = 1,
		Font = FONT_TV, Text = "", TextColor3 = Color3.new(1, 1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7,
	}, osd)
	Stroke(osdName, 1.5)

	--.. the afterglow dot left behind by power off
	local afterglow = New("Frame", {
		Name = "Afterglow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Color3.fromRGB(235, 245, 255), BorderSizePixel = 0, Visible = false, ZIndex = 4,
	}, gui)
	Corner(afterglow, UDim.new(0.5, 0))

	--.. the reflection on the glass: a soft diagonal streak, strong on the dark glass, faint over a picture
	local glare = New("Frame", {Name = "Glare", Size = FULL, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 5}, gui)
	local glareGradient = New("UIGradient", {
		Rotation = 28,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.94),
			NumberSequenceKeypoint.new(0.22, 1),
			NumberSequenceKeypoint.new(0.36, 1),
			NumberSequenceKeypoint.new(0.44, 0.9),
			NumberSequenceKeypoint.new(0.5, 0.95),
			NumberSequenceKeypoint.new(0.56, 0.92),
			NumberSequenceKeypoint.new(0.66, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, glare)
	local glareOffset = Vector2.zero

	--..Stand-by dot..--
	local dot
	if Kit.Part(model, "RedLights") then
		dot = ctx:Part({
			Name = "TVStandby", Shape = Enum.PartType.Cylinder, Size = Vector3.new(DOT_THICK, DOT_DIAMETER, DOT_DIAMETER) * scale,
			CFrame = Kit.CFrameToWorld(model, CFrame.new(DOT_CENTRE) * CFrame.Angles(0, math.pi / 2, 0)),
			Material = Enum.Material.SmoothPlastic, Color = DOT_DIM, Parent = folder,
		})
	end
	local dotLit = nil

	--..Sounds..--
	local function Sfx(name, volume)
		local id = type(FunAssets.Sfx) == "table" and FunAssets.Sfx[name] or nil
		if not id then return nil end
		return ctx:Sound(screen, id, {Volume = volume, Looped = false})
	end
	local sfxOn, sfxOff, sfxStatic = Sfx("TVOn", 0.6), Sfx("TVOff", 0.6), Sfx("TVStatic", 0.35)
	local playSerial = {}
	local function Play(sound, maxTime)
		if not sound then return end
		pcall(function()
			sound.TimePosition = 0
			sound:Play()
		end)
		if maxTime then
			local my = (playSerial[sound] or 0) + 1
			playSerial[sound] = my
			task.delay(maxTime, function()
				if playSerial[sound] == my and sound.Parent then pcall(function() sound:Stop() end) end
			end)
		end
	end

	--..Tweens (a power transition cancels the last one's)..--
	local tweens = {}
	local function Tween(inst, t, props, style, direction)
		local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
		table.insert(tweens, tw)
		tw:Play()
		return tw
	end
	local function CancelTweens()
		for _, tw in ipairs(tweens) do tw:Cancel() end
		table.clear(tweens)
	end

	--..State..--
	local state = {init = false, on = false, channel = 1, since = 0}
	local mode = nil          -- "slides" | "video" | "bars" while the picture shows, nil when off
	local slides, slideSecs = nil, SLIDE_SECONDS
	local frontImage, backImage = nil, nil
	local video = nil         -- {id, sound, assigned, startedAt, loaded, fallback, preview, synced} for a video channel
	local powerToken = 0      -- bumps on every power transition: a stale animation step stops
	local osdSerial, staticSerial = 0, 0
	local lastPowerOn = -math.huge
	local lastVolume = -1     -- the VideoFrame volume last set (reset whenever the video stops)

	--..Slides (from the shared clock: per frame in the Step, 4 Hz from the Every while the Step sleeps)..--
	local function UpdateSlides(now)
		local list = slides
		if not list then return end
		local n = #list
		local t = math.max(0, now - state.since)
		local k = math.floor(t / slideSecs)
		local phase = t - k * slideSecs
		local current = list[k % n + 1]
		if frontImage ~= current then
			slideFront.Image = current
			frontImage = current
		end
		local alpha = 1
		if n > 1 and k > 0 then alpha = math.clamp(phase / FADE_TIME, 0, 1) end
		if alpha < 1 then
			local previous = list[(k - 1) % n + 1]
			if backImage ~= previous then
				slideBack.Image = previous
				backImage = previous
			end
			slideBack.Visible = true
		elseif slideBack.Visible then
			slideBack.Visible = false
		end
		slideFront.ImageTransparency = 1 - alpha
		--.. a slow zoom: through each slide, or a gentle breathe when there is only one
		local z
		if n > 1 then
			z = 1.02 + 0.05 * (phase / slideSecs)
		else
			z = 1.045 + 0.025 * math.sin(t * math.pi * 2 / 16)
		end
		slideFront.Size = UDim2.fromScale(z, z)
		slideBack.Size = UDim2.fromScale(1.07, 1.07)
	end

	--.. a new list draws its current slide AT ONCE: the Step may be asleep (camera beyond StepRange, SurfaceGui
	--.. still drawing), and ImageLabels keep the last Image, which would freeze the previous channel's picture
	local function SetSlides(list, seconds)
		slides = list
		slideSecs = math.max(0.5, tonumber(seconds) or SLIDE_SECONDS)
		frontImage, backImage = nil, nil
		local show = list ~= nil
		slideFront.Visible = show
		slideBack.Visible = false
		if show then
			Preload(list)
			UpdateSlides(Kit.Now())
		end
	end

	--.. the stand-by dot: lit for BLINK_LIT of every BLINK_PERIOD while off, dim while on
	local function UpdateDot(now)
		if not dot then return end
		local lit = not state.on and (now % BLINK_PERIOD) < BLINK_LIT
		if lit ~= dotLit then
			dotLit = lit
			dot.Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic
			dot.Color = lit and DOT_LIT or DOT_DIM
		end
	end

	local function ShowMessage(text)
		message.Text = text or ""
		message.Visible = text ~= nil
	end

	--.. the slideshow music: start (seeked to the channel clock once loaded, by the 4 Hz loop) or stop
	local function SetMusic(id)
		if id == musicId then return end
		musicId = id
		musicSynced = false
		pcall(function()
			music:Stop()
			if id then
				music.SoundId = id
				music:Play()
			end
		end)
	end

	local function StopVideo()
		video = nil
		lastVolume = -1
		if videoFrame then
			pcall(function()
				videoFrame.Playing = false
				videoFrame.Volume = 0
				videoFrame.Visible = false
				videoFrame.Video = ""
			end)
		end
	end

	--.. a video channel's stand-in pictures (over the not-yet-loaded video): its own Slides, else the first
	--.. slideshow channel's, else colour bars
	local function ShowStandIn()
		local list, seconds = FallbackSlides(ChannelAt(state.channel))
		if list then SetSlides(list, seconds) else bars.Visible = true end
	end

	--.. a video channel seen from beyond VIDEO_LOAD_RANGE (not downloaded there): its stand-in pictures, quietly
	--.. (no "Tuning..." forever on a far TV). Kept once shown, until the video has loaded
	local function ShowPreview(v)
		if v.preview then return end
		v.preview = true
		ShowMessage(nil)
		ShowStandIn()
	end

	--.. put channel `index` on the picture (no transition effects)
	local function ShowChannel(index)
		local ch = ChannelAt(index)
		StopVideo()
		SetSlides(nil)
		bars.Visible = false
		ShowMessage(nil)
		local isVideo = type(ch) == "table" and type(ch.Video) == "string" and ch.Video ~= "" and videoFrame ~= nil
		SetMusic((not isVideo and type(ch) == "table" and type(ch.Music) == "string" and ch.Music ~= "") and ch.Music or nil)
		if isVideo then
			mode = "video"
			video = {id = ch.Video, sound = ch.Sound ~= false, assigned = false, startedAt = 0, loaded = false, fallback = false, preview = false, synced = false}
			pcall(function() videoFrame.Visible = true end)
			if ctx:CameraDistance() > VIDEO_LOAD_RANGE then
				ShowPreview(video)
			else
				ShowMessage("Tuning...")
			end
		elseif HasSlides(ch) then
			mode = "slides"
			SetSlides(ch.Slides, ch.Seconds)
		else
			mode = "bars"
			bars.Visible = true
			if #Channels() == 0 then ShowMessage("NO CHANNELS") end
		end
	end

	--.. every visual the picture owns off (power off end state)
	local function ClearPicture()
		mode = nil
		SetMusic(nil)
		StopVideo()
		SetSlides(nil)
		bars.Visible = false
		ShowMessage(nil)
		staticFrame.Visible = false
		osd.Visible = false
	end

	local function ShowOsd(index)
		local ch, i = ChannelAt(index)
		osdNumber.Text = string.format("CH %02d", i)
		osdName.Text = type(ch) == "table" and tostring(ch.Name or ("Channel " .. i)) or "No channel"
		osd.Visible = true
		osdSerial += 1
		local my = osdSerial
		task.delay(OSD_TIME, function()
			if osdSerial == my and ctx:Alive() then osd.Visible = false end
		end)
	end

	local function EnsureStatic()
		if staticCells then return end
		staticCells = {}
		for r = 0, STATIC_ROWS - 1 do
			for c = 0, STATIC_COLS - 1 do
				table.insert(staticCells, New("Frame", {
					Size = UDim2.new(1 / STATIC_COLS, 1, 1 / STATIC_ROWS, 1),
					Position = UDim2.fromScale(c / STATIC_COLS, r / STATIC_ROWS),
					BackgroundColor3 = GREYS[1], BorderSizePixel = 0, ZIndex = 6,
				}, staticFrame))
			end
		end
		staticBands = {}
		for i = 1, 2 do
			staticBands[i] = New("Frame", {
				Size = UDim2.fromScale(1, 0.07 + 0.05 * i), BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = 7,
			}, staticFrame)
		end
	end

	--.. one frame of noise: every cell a random grey, the bands somewhere else, a little horizontal jitter
	local function RollStatic()
		local nGreys = #GREYS
		for _, cell in ipairs(staticCells) do cell.BackgroundColor3 = GREYS[math.random(1, nGreys)] end
		for _, band in ipairs(staticBands) do band.Position = UDim2.fromScale(0, math.random() * 0.95 - 0.05) end
		staticFrame.Position = UDim2.fromOffset(math.random(-2, 2), 0)
	end

	local function StartStatic()
		EnsureStatic()
		RollStatic() -- noise from the first frame, even while the Step sleeps (it re-rolls every other frame)
		staticFrame.Visible = true
		Play(sfxStatic, STATIC_TIME + 0.05)
		staticSerial += 1
		local my = staticSerial
		task.delay(STATIC_TIME, function()
			if staticSerial == my and ctx:Alive() then staticFrame.Visible = false end
		end)
	end

	--..Power..--
	local function PowerOn(animate)
		powerToken += 1
		local my = powerToken
		CancelTweens()
		afterglow.Visible = false
		staticFrame.Visible = false
		tube.Visible = true
		ShowChannel(state.channel)
		light.Enabled = true
		glare.BackgroundTransparency = 0.55
		if not animate then
			tube.Size = FULL
			flash.BackgroundTransparency = 1
			light.Brightness = LIGHT_BRIGHTNESS
			return
		end
		lastPowerOn = os.clock()
		Play(sfxOn)
		tube.Size = UDim2.fromOffset(LINE_PX + 1, LINE_PX)
		flash.BackgroundTransparency = 0
		light.Brightness = 0
		Tween(tube, 0.12, {Size = UDim2.new(1, 0, 0, LINE_PX)})
		task.delay(0.12, function()
			if powerToken ~= my or not ctx:Alive() then return end
			Tween(tube, 0.24, {Size = FULL}, Enum.EasingStyle.Quart)
			Tween(flash, 0.42, {BackgroundTransparency = 1})
			Tween(light, 0.35, {Brightness = LIGHT_BRIGHTNESS})
			ShowOsd(state.channel)
		end)
	end

	local function PowerOff(animate)
		powerToken += 1
		local my = powerToken
		CancelTweens()
		glare.BackgroundTransparency = 0
		local function finish()
			tube.Visible = false
			tube.Size = FULL
			flash.BackgroundTransparency = 1
			light.Enabled = false
			light.Brightness = 0
			ClearPicture()
		end
		if not animate or not tube.Visible then
			finish()
			afterglow.Visible = false
			return
		end
		Play(sfxOff)
		osd.Visible = false
		Tween(flash, 0.08, {BackgroundTransparency = 0.05})
		Tween(light, 0.22, {Brightness = 0})
		Tween(tube, 0.13, {Size = UDim2.new(1, 0, 0, LINE_PX)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.13, function()
			if powerToken ~= my or not ctx:Alive() then return end
			Tween(tube, 0.1, {Size = UDim2.fromOffset(LINE_PX + 1, LINE_PX)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.1, function()
				if powerToken ~= my or not ctx:Alive() then return end
				finish()
				afterglow.Size = UDim2.fromOffset(9, 9)
				afterglow.BackgroundTransparency = 0
				afterglow.Visible = true
				Tween(afterglow, 0.5, {Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.delay(0.5, function()
					if powerToken == my and ctx:Alive() then afterglow.Visible = false end
				end)
			end)
		end)
	end

	--..Apply the replicated state (coalesced: On / Channel / Since land together)..--
	local function Apply()
		local on = ctx:State("On") == true
		local channel = tonumber(ctx:State("Channel")) or 1
		local since = tonumber(ctx:State("Since")) or 0
		local prevOn, prevChannel, prevSince = state.on, state.channel, state.since
		state.on, state.channel, state.since = on, channel, since
		if not state.init then
			state.init = true
			if on then PowerOn(false) else PowerOff(false) end
		elseif on ~= prevOn then
			if on then PowerOn(true) else PowerOff(true) end
		elseif on and (channel ~= prevChannel or since ~= prevSince) then
			ShowChannel(channel)
			--.. a new channel number is always a channel change (even one pressed during the power-on, whose OSD
			--.. would otherwise keep naming the old channel); a bare Since trailing its power-on is not
			if channel ~= prevChannel or os.clock() - lastPowerOn > 0.6 then
				StartStatic()
				ShowOsd(channel)
			end
		end
		UpdateDot(Kit.Now())
	end
	local pending = false
	local function Queue()
		if pending then return end
		pending = true
		task.defer(function()
			pending = false
			if ctx:Alive() then Apply() end
		end)
	end
	ctx:OnState("On", Queue)
	ctx:OnState("Channel", Queue)
	ctx:OnState("Since", Queue)

	--..Per frame: static, slides, stand-by blink, glare parallax..--
	local staticFlip = false
	ctx:Step(function(_, now)
		if staticFrame.Visible and staticCells then
			staticFlip = not staticFlip
			if staticFlip then RollStatic() end
		end
		if tube.Visible then UpdateSlides(now) end
		UpdateDot(now)
		--.. the reflection moves WITH the viewer (as one on glass does), on both axes: GUI +x = viewerRight,
		--.. GUI +y = down
		local cam = workspace.CurrentCamera
		if cam then
			local rel = cam.CFrame.Position - screen.Position
			local m = rel.Magnitude
			if m > 0.01 then
				local offset = Vector2.new(math.clamp(rel:Dot(viewerRight) / m * 0.45, -0.6, 0.6), math.clamp(-rel:Dot(up) / m * 0.25, -0.3, 0.3))
				if (offset - glareOffset).Magnitude > 0.003 then
					glareOffset = offset
					glareGradient.Offset = offset
				end
			end
		end
	end)

	--..4 Hz: the far picture + the video (not per frame; runs even when the Step sleeps)..--
	local resyncTick = 0
	local stepRange = ctx.StepRange or B.StepRange
	ctx:Every(0.25, function()
		local dist = ctx:CameraDistance()
		--.. beyond StepRange the Step sleeps but the SurfaceGui still draws out to GUI_MAX_DISTANCE: keep the
		--.. slides turning (and the stand-by dot blinking) there at 4 Hz
		if dist > stepRange and dist <= GUI_MAX_DISTANCE then
			local now = Kit.Now()
			if tube.Visible then UpdateSlides(now) end
			UpdateDot(now)
		end
		--.. the slideshow music joins the channel clock once it has loaded (every client hears the same bar)
		if musicId and not musicSynced then
			pcall(function()
				local length = music.TimeLength
				if music.IsLoaded and length and length > 0 then
					music.TimePosition = (Kit.Now() - state.since) % length
					musicSynced = true
				end
			end)
		end
		--.. the video: load (near), preview (far), fall back, play / pause by camera distance
		local v = video
		if not (state.on and mode == "video" and v and videoFrame) then return end
		if not v.assigned then
			if dist > VIDEO_LOAD_RANGE then
				ShowPreview(v)
				return
			end
			v.assigned = true
			v.startedAt = os.clock()
			local ok = pcall(function()
				videoFrame.Looped = true
				videoFrame.Video = v.id
			end)
			if not ok then v.startedAt = -math.huge end -- straight to the fallback
		end
		local loaded = false
		pcall(function() loaded = videoFrame.IsLoaded == true end)
		if loaded and not v.loaded then
			--.. the stand-ins come off: the video underneath takes over
			v.loaded = true
			v.fallback = false
			v.preview = false
			SetSlides(nil)
			bars.Visible = false
			ShowMessage(nil)
		elseif not loaded and not v.fallback and os.clock() - v.startedAt > VIDEO_TIMEOUT then
			v.fallback = true
			if not v.preview then ShowStandIn() end
			ShowMessage("NO SIGNAL")
		end
		--.. play only near; seek to the shared clock whenever playback (re)starts or drifts
		local want = dist <= VIDEO_PLAY_RANGE
		pcall(function()
			local length = videoFrame.TimeLength
			local target = (length and length > 0) and (Kit.Now() - state.since) % length or nil
			if want then
				resyncTick += 1
				if loaded and target and (not v.synced or (resyncTick % 20 == 0 and math.abs(videoFrame.TimePosition - target) > VIDEO_RESYNC)) then
					videoFrame.TimePosition = target
					v.synced = true
				end
				if not videoFrame.Playing then videoFrame.Playing = true end
			elseif videoFrame.Playing then
				videoFrame.Playing = false
				v.synced = false
			end
		end)
		local volume = 0
		if v.sound and want then
			volume = VIDEO_VOLUME * math.clamp((VIDEO_PLAY_RANGE - dist) / (VIDEO_PLAY_RANGE - VIDEO_FULL_RANGE), 0, 1)
		end
		if math.abs(volume - lastVolume) > 0.01 then
			lastVolume = volume
			pcall(function() videoFrame.Volume = volume end)
		end
	end)

	return function()
		CancelTweens()
		SetMusic(nil)
		StopVideo()
	end
end

return B
