
--..Test body (appended after prelude + modules)..--
local Kit = KitModule
local checks, fails = 0, 0
local function check(cond, msg)
	checks += 1
	if not cond then
		fails += 1
		print("FAIL: " .. msg)
	end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end
local function nearV(a, b, eps) return near(a.X, b.X, eps) and near(a.Y, b.Y, eps) and near(a.Z, b.Z, eps) end

--.. the test pins its own channel list (the real FunAssets list is exercised at the end)
local REAL_CHANNELS = FunAssetsModule.TVChannels
FunAssetsModule.TVChannels = {{Name = "Cucumber TV", Slides = {"rbxassetid://1", "rbxassetid://2"}, Seconds = 4}}

--..Model (TV at x1.45, yawed 90 deg, the ScreenSky mesh yawed 180 deg like the FBX trap)..--
local SCALE = 1.45
local model = Instance.new("Model")
model.Name = "TV"
local placed = Instance.new("Folder")
placed.Parent = workspace
model.Parent = placed
local centre = Vector3.new(0, 2.43, 0)
local hitbox = Instance.new("Part")
hitbox.Name = "Hitbox"
hitbox.CFrame = CFrame.new(100, 2 + 2.43 * SCALE, -40) * CFrame.Angles(0, math.rad(90), 0)
hitbox.Size = Vector3.new(6.4, 4.86, 1.8) * SCALE
hitbox.Parent = model
model.PrimaryPart = hitbox
model:SetAttribute("Scale", SCALE)
model:SetAttribute("AuthoredCentre", centre)
model:SetAttribute("BuildKey", "TV")
model:SetAttribute("Owner", 1)
local DUMP = {
	{"Panel", Vector3.new(0, 3.48, 0.03), Vector3.new(5, 2.76, 0.33)},
	{"RedLights", Vector3.new(-2.18, 1.92, -0.34), Vector3.new(1, 0.75, 0.42)},
	{"ScreenLand", Vector3.new(0, 3.07, -0.09), Vector3.new(4.68, 1.39, 0.01)},
	{"ScreenSky", Vector3.new(0, 3.55, -0.06), Vector3.new(4.68, 2.36, 0.06), math.pi},
	{"ScreenSun", Vector3.new(-1.07, 3.73, -0.11), Vector3.new(2.54, 1.46, 0.02)},
	{"Remote", Vector3.new(-2.48, 1.49, -0.16), Vector3.new(0.73, 0.14, 0.99)},
}
for _, row in ipairs(DUMP) do
	local p = Instance.new("MeshPart")
	p.Name = row[1]
	p.CFrame = Kit.CFrameToWorld(model, CFrame.new(row[2]) * CFrame.Angles(0, row[4] or 0, 0))
	p.Size = row[3] * SCALE
	p.Parent = model
end

--..Mini contexts (mirrors of FunBuildService / FunBuildClient NewContext)..--
local function ClientCtx(mod)
	local ctx = {Model = model, Key = "TV", Base = "TV", Scale = Kit.Scale(model), Kit = Kit, _alive = true, _conns = {}, _insts = {}, _cleanups = {}, _every = {}, StepRange = mod.StepRange or 180}
	function ctx:Alive() return self._alive and model.Parent ~= nil end
	function ctx:Connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(self._conns, c)
		return c
	end
	function ctx:Add(inst) table.insert(self._insts, inst) return inst end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn)
		local name = "Fun_" .. k
		self:Connect(model:GetAttributeChangedSignal(name), function() fn(model:GetAttribute(name)) end)
		task.spawn(fn, model:GetAttribute(name))
	end
	function ctx:CameraDistance() return (workspace.CurrentCamera.CFrame.Position - Kit.Hitbox(model).Position).Magnitude end
	function ctx:Step(fn) assert(self._step == nil, "two ctx:Step") self._step = fn end
	function ctx:Every(_, fn) table.insert(self._every, fn) end
	function ctx:Sound(parent, id, props)
		local s = Kit.MakeSound(id, props)
		s.Parent = parent
		self:Add(s)
		return s
	end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = workspace.CurrentCamera end
		self:Add(p)
		return p
	end
	return ctx
end

local function ServerCtx()
	local ctx = {Model = model, Key = "TV", Base = "TV", Scale = Kit.Scale(model), _alive = true, _insts = {}, _conns = {}, _states = {}}
	function ctx:Alive() return self._alive end
	function ctx:Connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(self._conns, c)
		return c
	end
	function ctx:Add(inst) table.insert(self._insts, inst) return inst end
	function ctx:SetState(k, v)
		self._states[k] = true
		model:SetAttribute("Fun_" .. k, v)
	end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:Prompt(part, opts)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = opts.Name or "FunPrompt"
		prompt.ObjectText = opts.Object or "TV"
		prompt.ActionText = opts.Action or "Use"
		prompt.KeyboardKeyCode = opts.Key or Enum.KeyCode.E
		prompt.GamepadKeyCode = opts.Gamepad or Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = opts.Distance or 10
		prompt.Parent = part
		self:Add(prompt)
		return prompt
	end
	return ctx
end

local function Stop(ctx)
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups or {}) do fn() end
	for _, c in ipairs(ctx._conns) do c.Disconnect() end
	for i = #ctx._insts, 1, -1 do ctx._insts[i]:Destroy() end
end

--..Run: server first (states), then the client joins..--
local sctx = ServerCtx()
local sres = ServerB.Server(model, sctx)
check(sres == nil or type(sres) == "function", "server returns nil/cleanup")
check(model:GetAttribute("Fun_On") == false, "server: starts off")
check(model:GetAttribute("Fun_Channel") == 1, "server: channel 1")
local panel = model:FindFirstChild("Panel")
local power = panel:FindFirstChild("TVPowerPrompt")
local chanPrompt
for _, inst in ipairs(sctx._insts) do if inst.Name == "TVChannelPrompt" then chanPrompt = inst end end
check(power ~= nil and power.ActionText == "Turn on", "power prompt 'Turn on' on the Panel")
check(chanPrompt ~= nil and chanPrompt.Parent == nil, "channel prompt parked while off")
check(chanPrompt.KeyboardKeyCode == Enum.KeyCode.R and chanPrompt.GamepadKeyCode == Enum.KeyCode.ButtonY, "channel prompt keys R / ButtonY")

local cctx = ClientCtx(ClientB)
local cres = ClientB.Client(model, cctx)
if type(cres) == "function" then cctx:OnCleanup(cres) end
Flush()

local folder = workspace:FindFirstChild("FunBuildLocal")
check(folder ~= nil, "local folder made")
local screen = folder:FindFirstChild("TVScreen")
local dot = folder:FindFirstChild("TVStandby")
check(screen ~= nil and dot ~= nil, "screen + dot parts made")

--.. geometry in the authored frame
local origin = Kit.Origin(model)
local rel = origin:ToObjectSpace(screen.CFrame)
print("screen authored pos", rel.Position / SCALE, "look", rel.LookVector, "right", rel.RightVector, "size", screen.Size / SCALE)
check(nearV(rel.Position / SCALE, Vector3.new(0, 3.55, -0.114)), "screen centre at authored (0, 3.55, -0.114)")
check(nearV(rel.LookVector, Vector3.new(0, 0, -1)), "screen faces the build's front (-Z)")
check(nearV(screen.Size / SCALE, Vector3.new(4.68, 2.36, 0.04)), "screen covers the aperture")
local face = rel.Position / SCALE + rel.LookVector * 0.02
print("screen face authored z", face.Z, "(bezel front -0.13, ScreenSun front -0.12)")
local drel = origin:ToObjectSpace(dot.CFrame)
print("dot authored", drel.Position / SCALE, "axis", drel.RightVector)
check(nearV(drel.Position / SCALE, Vector3.new(-1.75, 2.23, -0.1725)), "stand-by dot position")
check(near(math.abs(drel.RightVector.Z), 1), "dot cylinder axis along the screen normal")

local gui = screen:FindFirstChild("TVScreenGui")
local tube = gui:FindFirstChild("Tube")
local inner = tube:FindFirstChild("Picture")
local light = screen:FindFirstChildOfClass("SurfaceLight")
check(gui.Face == Enum.NormalId.Front and gui.LightInfluence == 0 and gui.PixelsPerStud == 50, "SurfaceGui props")
print("canvas px", inner.Size.X.Offset, inner.Size.Y.Offset)
check(tube.Visible == false and light.Enabled == false, "initially off")

--.. stand-by blink over time
local step = cctx._step
local every = cctx._every[1]
check(step ~= nil and every ~= nil and #cctx._every == 1, "one step + one every")
local mats = {}
for i = 1, 100 do
	Advance(1 / 30)
	step(1 / 30, Kit.Now())
	mats[dot.Material.Name] = true
end
check(mats.Neon and mats.SmoothPlastic, "stand-by dot blinks")
local glareGrad = gui:FindFirstChild("Glare"):FindFirstChildOfClass("UIGradient")
--.. the reflection moves WITH the viewer. The viewer faces +Z (authored), so their right is authored -X; on a
--.. Front-face SurfaceGui GUI +x runs along the part's -X = the viewer's right
check(nearV(origin.Rotation:Inverse() * -screen.CFrame.RightVector, Vector3.new(-1, 0, 0)), "part -X = authored -X = the viewer's right")
local function GlareFrom(authored)
	workspace.CurrentCamera.CFrame = CFrame.new(Kit.ToWorld(model, authored))
	step(1 / 30, Kit.Now())
	return glareGrad.Offset
end
local gRight, gLeft, gAbove = GlareFrom(Vector3.new(-6, 3.55, -12)), GlareFrom(Vector3.new(6, 3.55, -12)), GlareFrom(Vector3.new(0, 12, -12))
print("glare offset: viewer right", gRight, "viewer left", gLeft, "above", gAbove)
check(gRight.X > 0.1 and near(gRight.Y, 0, 0.01), "glare moves right (GUI +x) when the viewer moves right")
check(gLeft.X < -0.1, "glare moves left when the viewer moves left")
check(gAbove.Y < -0.1 and near(gAbove.X, 0, 0.01), "glare moves up (GUI -y) when the viewer moves up")
workspace.CurrentCamera.CFrame = CFrame.new(Kit.ToWorld(model, Vector3.new(6, 4, -12)))
step(1 / 30, Kit.Now())

--..Power on..--
power.Triggered:Fire({UserId = 2})
check(model:GetAttribute("Fun_On") == true and power.ActionText == "Turn off", "power prompt turns on")
check(chanPrompt.Parent == panel, "channel prompt shown while on")
print("channel prompt ObjectText:", chanPrompt.ObjectText, "UIOffset", chanPrompt.UIOffset)
Flush()
check(tube.Visible and tube.Size.Y.Offset == 3, "CRT line starts")
local sfxOn
for _, s in ipairs(screen:GetChildren()) do if s.ClassName == "Sound" and s.Plays then sfxOn = s end end
check(sfxOn ~= nil, "TVOn sound played")
Advance(0.5)
check(tube.Size.Y.Scale == 1 and tube.Size.X.Scale == 1, "CRT expanded")
check(light.Enabled and light.Brightness > 1, "light on")
local osd = inner:FindFirstChild("OSD")
check(osd.Visible and osd:FindFirstChild("Number").Text == "CH 01", "OSD shows CH 01: " .. tostring(osd:FindFirstChild("Number").Text))
step(1 / 30, Kit.Now())
local front = inner:FindFirstChild("SlideFront")
check(front.Visible and front.Image == FunAssetsModule.TVChannels[1].Slides[1], "slide shown: " .. tostring(front.Image))
Advance(2.1)
check(not osd.Visible, "OSD hides after 2 s")
check(not cctx._step(1 / 30, Kit.Now()), "step ok")

--.. power prompt cooldown
power.Triggered:Fire({UserId = 3})
Advance(0.1)
power.Triggered:Fire({UserId = 3})
check(model:GetAttribute("Fun_On") == false, "second press within cooldown ignored (off now)")
Flush()
Advance(0.5)
check(not tube.Visible and not light.Enabled, "powered off")
check(chanPrompt.Parent == nil, "channel prompt parked again")
Advance(1)
power.Triggered:Fire({UserId = 3})
Flush()
Advance(1)
check(tube.Visible, "on again")

--..Multi-slide channel + a video channel..--
table.insert(FunAssetsModule.TVChannels, {Name = "Pics", Slides = {"rbxassetid://11", "rbxassetid://22", "rbxassetid://33"}, Seconds = 3})
table.insert(FunAssetsModule.TVChannels, {Name = "Vid", Video = "rbxassetid://999"})
chanPrompt.Triggered:Fire({UserId = 2})
check(model:GetAttribute("Fun_Channel") == 2, "next channel -> 2")
Flush()
local static = inner:FindFirstChild("Static")
check(static.Visible, "static on channel change")
step(1 / 30, Kit.Now())
step(1 / 30, Kit.Now())
check(#static:GetChildren() == 28 * 16 + 2, "static grid built: " .. #static:GetChildren())
Advance(0.4)
check(not static.Visible, "static ends")
check(osd.Visible and osd:FindFirstChild("ChannelName").Text == "Pics", "OSD names the channel")
local seen = {}
local back = inner:FindFirstChild("SlideBack")
local sawFade = false
for i = 1, 300 do
	Advance(1 / 30)
	step(1 / 30, Kit.Now())
	seen[front.Image] = true
	if back.Visible and front.ImageTransparency > 0.05 and front.ImageTransparency < 0.95 then sawFade = true end
end
check(seen["rbxassetid://11"] and seen["rbxassetid://22"] and seen["rbxassetid://33"], "all 3 slides cycle")
check(sawFade, "slides cross-fade")
--.. every client shows the same slide: a second client joining now computes the same image
local t = Kit.Now() - model:GetAttribute("Fun_Since")
local expect = ({"rbxassetid://11", "rbxassetid://22", "rbxassetid://33"})[math.floor(t / 3) % 3 + 1]
check(front.Image == expect, "slide index from the shared clock")

--.. channel 3 = video
Advance(1)
chanPrompt.Triggered:Fire({UserId = 2})
Flush()
check(model:GetAttribute("Fun_Channel") == 3, "next channel -> 3")
local video = inner:FindFirstChild("Video")
local message = inner:FindFirstChild("Message")
check(video.Visible and message.Visible and message.Text == "Tuning...", "video channel tuning")
workspace.CurrentCamera.CFrame = CFrame.new(Kit.ToWorld(model, Vector3.new(0, 4, -20)))
every()
check(video.Video == "rbxassetid://999" and video.Playing == true, "video assigned + playing near")
for i = 1, 30 do Advance(0.25) every() step(1 / 30, Kit.Now()) end
check(message.Text == "NO SIGNAL" and message.Visible, "no signal after timeout")
check(front.Visible and front.Image ~= "", "fallback slides show: " .. tostring(front.Image))
video.IsLoaded = true
video.TimeLength = 10
video.Playing = false
every()
check(not message.Visible and not front.Visible, "loaded video hides the fallback")
check(video.Playing and video.TimePosition > 0, "video playing, seeked to " .. tostring(video.TimePosition))
check(video.Volume == 0, "muted (channel has no Sound = true)")
workspace.CurrentCamera.CFrame = CFrame.new(Kit.ToWorld(model, Vector3.new(0, 4, -200)))
every()
check(video.Playing == false, "video pauses far away")
FunAssetsModule.TVChannels[3].Sound = true
workspace.CurrentCamera.CFrame = CFrame.new(Kit.ToWorld(model, Vector3.new(0, 4, -10)))
Advance(0.6)
chanPrompt.Triggered:Fire({UserId = 2}) -- wraps to 1
Flush()
Advance(0.6)
chanPrompt.Triggered:Fire({UserId = 2}) -- 2
Flush()
Advance(0.6)
chanPrompt.Triggered:Fire({UserId = 2}) -- 3 (video with sound)
Flush()
check(model:GetAttribute("Fun_Channel") == 3, "wrapped round to 3")
every()
video.IsLoaded = true
video.TimeLength = 10
every()
print("video volume near", video.Volume)
check(video.Volume > 0.3, "video audible near when Sound = true")
local barsF = inner:FindFirstChild("Bars")
check(video.ZIndex < barsF.ZIndex and barsF.ZIndex < back.ZIndex and back.ZIndex < front.ZIndex and front.ZIndex < message.ZIndex,
	"z order: video under bars under slides under message")

--..A channel change during the power-on animation still gets its static + OSD (review fix 3)..--
Advance(1)
power.Triggered:Fire({UserId = 2}) -- off
Flush()
Advance(1)
power.Triggered:Fire({UserId = 2}) -- on (still channel 3)
Flush()
Advance(0.2)                       -- the power-on OSD ("CH 03") went up at +0.12
check(osd.Visible and osd:FindFirstChild("Number").Text == "CH 03", "power-on OSD names channel 3")
chanPrompt.Triggered:Fire({UserId = 2}) -- -> 1, inside the 0.6 s power-on window
Flush()
check(model:GetAttribute("Fun_Channel") == 1, "channel pressed during power-on -> 1")
check(osd.Visible and osd:FindFirstChild("Number").Text == "CH 01" and osd:FindFirstChild("ChannelName").Text == "Cucumber TV",
	"OSD names the NEW channel at once: " .. osd:FindFirstChild("Number").Text)
check(static.Visible, "static on a channel change during power-on")
Advance(1.5)
check(osd.Visible and osd:FindFirstChild("Number").Text == "CH 01", "OSD still on the new channel at +1.7 s")
Advance(1)
check(not osd.Visible, "OSD hides")
--.. a bare Since trailing a power-on (same channel) is still not a channel change
Advance(1)
power.Triggered:Fire({UserId = 2}) -- off
Flush()
Advance(1)
power.Triggered:Fire({UserId = 2}) -- on
Flush()
Advance(0.3)
model:SetAttribute("Fun_Since", Kit.Now())
Flush()
check(not static.Visible, "a trailing Since (same channel) makes no static")

--..Far: camera beyond StepRange (Step asleep) but inside the SurfaceGui's MaxDistance (review fix 1)..--
local farCF = CFrame.new(Kit.ToWorld(model, Vector3.new(0, 3.55, 0)) + origin.LookVector * 220)
workspace.CurrentCamera.CFrame = farCF
print("far camera distance", cctx:CameraDistance())
check(cctx:CameraDistance() > 180 and cctx:CameraDistance() < 260, "far camera in the 180-260 band")
Advance(1)
front.Image = "rbxassetid://STALE" -- whatever the last channel left behind
chanPrompt.Triggered:Fire({UserId = 2}) -- -> 2 "Pics", no step runs
Flush()
check(model:GetAttribute("Fun_Channel") == 2, "far: channel 2")
check(front.Visible and front.Image == "rbxassetid://11", "far: the new channel's slide drawn at once (no Step): " .. tostring(front.Image))
local greys = {}
for _, cell in ipairs(static:GetChildren()) do greys[cell.BackgroundColor3] = true end
local nGreys = 0
for _ in pairs(greys) do nGreys += 1 end
check(nGreys > 3, "far: static is noise from its first frame (" .. nGreys .. " greys)")
for i = 1, 14 do Advance(0.25) every() end -- 3.5 s, 4 Hz only
check(front.Image == "rbxassetid://22", "far: slides keep turning at 4 Hz: " .. tostring(front.Image))
--.. a video channel seen from far: its stand-in pictures quietly, no download
video.IsLoaded = false
video.TimeLength = 0
Advance(0.5)
chanPrompt.Triggered:Fire({UserId = 2}) -- -> 3 (video, no Slides of its own)
Flush()
every()
check(model:GetAttribute("Fun_Channel") == 3, "far: channel 3")
check(not message.Visible and front.Visible and front.Image == "rbxassetid://1", "far video: stand-in slides, no Tuning...: " .. tostring(front.Image))
check(video.Video == "" and not video.Playing, "far video: not downloaded")
for i = 1, 40 do Advance(0.25) every() end -- 10 s far: no NO SIGNAL (never tried)
check(not message.Visible, "far video: no NO SIGNAL while never assigned")
workspace.CurrentCamera.CFrame = CFrame.new(Kit.ToWorld(model, Vector3.new(0, 4, -10)))
every()
check(video.Video == "rbxassetid://999" and not message.Visible and front.Visible, "approach: video assigned, preview kept (no Tuning...)")
video.IsLoaded = true
video.TimeLength = 10
every()
check(not front.Visible and not message.Visible and video.Playing, "approach: loaded video takes over from the preview")

--..A late client sees the same state instantly (no animation)..--
Stop(cctx)
check(folder:FindFirstChild("TVScreen") == nil, "client stop removes the screen")
local c2 = ClientCtx(ClientB)
local r2 = ClientB.Client(model, c2)
if type(r2) == "function" then c2:OnCleanup(r2) end
Flush()
local screen2 = folder:FindFirstChild("TVScreen")
local tube2 = screen2:FindFirstChild("TVScreenGui"):FindFirstChild("Tube")
check(tube2.Visible and tube2.Size.Y.Scale == 1, "late joiner: on, full picture, no animation")

--..The REAL FunAssets channel list: every channel tunes to its picture + names itself..--
FunAssetsModule.TVChannels = REAL_CHANNELS
local inner2 = tube2:FindFirstChild("Picture")
local video2, front2, msg2, osd2 = inner2:FindFirstChild("Video"), inner2:FindFirstChild("SlideFront"), inner2:FindFirstChild("Message"), inner2:FindFirstChild("OSD")
local every2 = c2._every[1]
workspace.CurrentCamera.CFrame = CFrame.new(Kit.ToWorld(model, Vector3.new(0, 4, -10)))
local tuned = 0
for _ = 1, #REAL_CHANNELS do
	Advance(0.6)
	video2.IsLoaded = false
	video2.TimeLength = 0
	chanPrompt.Triggered:Fire({UserId = 2})
	Flush()
	every2()
	local idx = model:GetAttribute("Fun_Channel")
	local ch = REAL_CHANNELS[idx]
	local okName = osd2.Visible and osd2:FindFirstChild("ChannelName").Text == ch.Name and chanPrompt.ObjectText:find(ch.Name, 1, true) ~= nil
	local okPicture
	if ch.Video then
		okPicture = video2.Video == ch.Video and msg2.Visible and msg2.Text == "Tuning..." and video2.Playing
	else
		okPicture = front2.Visible and front2.Image == ch.Slides[1] and not msg2.Visible
	end
	if okName and okPicture then
		tuned += 1
	else
		print("real channel", idx, ch.Name, "osd", osd2:FindFirstChild("ChannelName").Text, "video", video2.Video, "msg", msg2.Text, "img", front2.Image)
	end
end
check(tuned == #REAL_CHANNELS, string.format("real list: %d of %d channels tune + name themselves", tuned, #REAL_CHANNELS))
--.. land on a video channel, then NO SIGNAL shows its own Slides
local guard = 0
repeat
	Advance(0.6)
	chanPrompt.Triggered:Fire({UserId = 2})
	Flush()
	guard += 1
until REAL_CHANNELS[model:GetAttribute("Fun_Channel")].Video or guard > #REAL_CHANNELS
local vch = REAL_CHANNELS[model:GetAttribute("Fun_Channel")]
video2.IsLoaded = false
for _ = 1, 30 do Advance(0.25) every2() end
check(vch.Video ~= nil and msg2.Text == "NO SIGNAL" and msg2.Visible and front2.Visible and table.find(vch.Slides, front2.Image) ~= nil,
	"real video channel: NO SIGNAL over its own slides (" .. tostring(vch.Name) .. ", " .. tostring(front2.Image) .. ")")
--.. and seen from far, the next video channel shows its slides quietly
workspace.CurrentCamera.CFrame = farCF
repeat
	Advance(0.6)
	chanPrompt.Triggered:Fire({UserId = 2})
	Flush()
	guard += 1
until REAL_CHANNELS[model:GetAttribute("Fun_Channel")].Video or guard > 3 * #REAL_CHANNELS
local fch = REAL_CHANNELS[model:GetAttribute("Fun_Channel")]
every2()
check(fch.Video ~= nil and not msg2.Visible and front2.Visible and front2.Image == fch.Slides[1] and video2.Video == "",
	"real far video channel: its slides, no message, no download (" .. tostring(fch.Name) .. ")")

--..Server stop..--
Stop(sctx)
check(chanPrompt._destroyed and power._destroyed, "server stop destroys both prompts")
Stop(c2)

print(string.format("%d checks, %d failed, %d tweens", checks, fails, tweensMade))
