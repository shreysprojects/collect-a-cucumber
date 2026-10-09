--[[
	CucumberLiftClient  (LocalScript, StarterPlayerScripts)
	The click-to-lift pickup (2026-09-16), driven by CucumberCarry through Remotes.CucumberLift:

	  server -> ALL clients
	  {Kind = "Start", Player, Holder, Token, Name, Kg, Start, Gain, Drift}
	      our own character: walk up to the cucumber (APPROACH), face it, freeze, the camera
	      swings round to frame the whole body and the cucumber, and THE BAR appears at the
	      bottom of the screen: a long track, red end on the left, green end on the right, the
	      strength icon (the HUD's bicep) riding on it. Every click / tap / gamepad A pushes the
	      icon right by Gain; it drifts left Drift per second. All the way right = lifted (the
	      hoist plays, the server puts it on the shoulder), all the way left = "Too heavy".
	      every client: that character's pose follows the bar (the Blender CucumberLift clip
	      scrubbed by progress through the R15 Motor6D.Transform values -- no Animation asset,
	      so it plays whoever owns the place): the hands start on the cucumber on the ground and rise to
	      the chest as the icon crosses the bar (liftTimeFor), heaving a touch on every click; the
	      cucumber rides them the whole way (2026-09-18).
	  {Kind = "Progress", Player, Token, P}     another player's bar position (8 Hz)
	  {Kind = "Hoist", Player, Token}            they won: play the hoist (LIFT_LEN .. clip end)
	  {Kind = "Fail", Player, Token}             they lost: pose and cucumber sink back
	  {Kind = "Cancel", Player, Token?, CancelAll?}  stop and restore everything

	  client -> server  {Kind = "Result", Token, Result = "done" | "fail" | "cancel"}
	                    {Kind = "Progress", Token, P}
	Rules and tuning: ReplicatedStorage.Modules.CucumberLift. Poses: CucumberLiftPoses
	(generated from assets/anims/CucumberLift.json).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Lift = require(Modules:WaitForChild("CucumberLift"))
local Poses = require(Modules:WaitForChild("CucumberLiftPoses"))
local SoundController = require(Modules:WaitForChild("SoundController"))
local Notify = require(Modules:WaitForChild("Notify"))
local CucumberMutations = require(Modules:WaitForChild("CucumberMutations"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LiftRemote = Remotes:WaitForChild("CucumberLift")

local APPROACH = Lift.APPROACH
local LIFT_LEN = Lift.LIFT_LEN
local HOIST_LEN = Lift.HOIST_LEN
local FAIL_RELAX = Lift.FAIL_RELAX
local CLIP_LEN = Poses.Length
--.. bar progress -> clip time (2026-09-18, user: "animate the hands so they move up as the strength icon goes
--.. up the bar"): the bar's START maps to LIFT_KNEE of the lift (hands just off the ground, the cucumber already
--.. in them), the green end to LIFT_LEN (the load at the chest); below START the hands sink back to the ground
--.. as the icon slides to the red end. Each click also heaves the pose PUMP seconds ahead for a moment.
local LIFT_KNEE = 0.1
local PUMP, PUMP_DECAY = 0.05, 6
local function liftTimeFor(p)
	p = math.clamp(p, 0, 1)
	if p <= Lift.START then return LIFT_LEN * LIFT_KNEE * (p / Lift.START) end
	return LIFT_LEN * (LIFT_KNEE + (1 - LIFT_KNEE) * (p - Lift.START) / (1 - Lift.START))
end
local STRENGTH_ICON = "rbxassetid://15403007921" -- the HUD's strength icon (StarterGui.CucumberHUDDesign.Counters.StrengthIcon)
local PROGRESS_HZ = 8
local FONT = Enum.Font.FredokaOne

--==================================================================== poses
--.. decode the generated frames once: per frame a CFrame per joint (Motor6D.Transform values)
local JOINTS = Poses.Joints
local FRAMES = {}
for _, fr in ipairs(Poses.Frames) do
	local cfs = {}
	for j = 1, #JOINTS do
		local b = 2 + (j - 1) * 7 -- qw, qx, qy, qz, px, py, pz
		cfs[j] = CFrame.new(fr[b + 4], fr[b + 5], fr[b + 6], fr[b + 1], fr[b + 2], fr[b + 3], fr[b])
	end
	FRAMES[#FRAMES + 1] = {T = fr[1], CF = cfs}
end

local function poseAt(t, out)
	t = math.clamp(t, 0, CLIP_LEN)
	local i = 1
	while i < #FRAMES and FRAMES[i + 1].T <= t do i += 1 end
	local a = FRAMES[i]
	local b = FRAMES[math.min(i + 1, #FRAMES)]
	local alpha = (b.T > a.T) and math.clamp((t - a.T) / (b.T - a.T), 0, 1) or 0
	for j = 1, #JOINTS do out[j] = a.CF[j]:Lerp(b.CF[j], alpha) end
	return out
end

local function motorsOf(char)
	local map = {}
	for _, d in ipairs(char:GetDescendants()) do
		--.. 2026-09-18: R15 characters now arrive with AnimationConstraints in place of Motor6Ds (same Transform
		--.. property, same joint frame); the pose never reached the avatar until both were accepted here
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and d.Part1 then
			local j = table.find(JOINTS, d.Part1.Name)
			if j then map[j] = d end
		end
	end
	return map
end

--.. rigs under our control: [char] = {Motors, T, TargetT, Rate (nil = smooth follow), Weight, TargetWeight, Scale, Buf, Tremble}
local Rigs = {}
local function rigFor(char)
	local rig = Rigs[char]
	if rig then
		rig.Motors = motorsOf(char) -- the physique upgrades rebuild the joints: never trust a stale map
		return rig
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	rig = {Motors = motorsOf(char), T = 0, TargetT = 0, Weight = 0, TargetWeight = 1, Buf = {}, Tremble = 0,
		Scale = root and math.clamp(root.Size.Y / 2, 0.5, 2.5) or 1}
	Rigs[char] = rig
	return rig
end

local function releaseRig(char)
	local rig = Rigs[char]
	if rig then rig.TargetWeight = 0 end
end

RunService.Stepped:Connect(function(_, dt)
	for char, rig in pairs(Rigs) do
		if not char.Parent then
			Rigs[char] = nil
			continue
		end
		local step = dt / 0.15
		rig.Weight = rig.Weight + math.clamp(rig.TargetWeight - rig.Weight, -step, step)
		if rig.TargetWeight <= 0 and rig.Weight <= 0.001 then
			for _, m in pairs(rig.Motors) do m.Transform = CFrame.identity end
			Rigs[char] = nil
			continue
		end
		if rig.Rate then
			rig.T = rig.T + math.clamp(rig.TargetT - rig.T, -rig.Rate * dt, rig.Rate * dt)
		else
			rig.T = rig.T + (rig.TargetT - rig.T) * math.min(1, dt * 14)
		end
		poseAt(rig.T + rig.Tremble, rig.Buf)
		for j, m in pairs(rig.Motors) do
			local cf = rig.Buf[j]
			cf = cf.Rotation + cf.Position * rig.Scale
			m.Transform = CFrame.identity:Lerp(cf, rig.Weight)
		end
	end
end)

--==================================================================== cucumber visuals (every client)
local function rootOf(holder)
	if holder:IsA("BasePart") then return holder end
	return holder.PrimaryPart or holder:FindFirstChildWhichIsA("BasePart", true)
end

local function boundsOf(holder)
	if holder:IsA("Model") then
		local ok, cf, size = pcall(holder.GetBoundingBox, holder)
		if ok then return cf, size end
	end
	local part = rootOf(holder)
	if part then return part.CFrame, part.Size end
	return holder:GetPivot(), Vector3.new(2, 2, 2)
end

local function handsMidpoint(char)
	local l = char and char:FindFirstChild("LeftHand")
	local r = char and char:FindFirstChild("RightHand")
	if l and r then return (l.Position + r.Position) * 0.5 end
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and (root.Position + root.CFrame.LookVector * 1.5 - Vector3.new(0, 1, 0)) or nil
end

--.. [holder] = {Base, Char, Ride, P (0 = resting, 1 = at the chest), Conn}: the cucumber rides
--.. the hands up as the bar fills (local pivots only; the server never moves it)
local Visual = {}
local function stopVisual(holder, restore)
	local st = Visual[holder]
	if not st then return end
	Visual[holder] = nil
	if st.Conn then st.Conn:Disconnect() end
	if restore ~= false and holder.Parent then pcall(holder.PivotTo, holder, st.Base) end
end

local function startVisual(holder, char)
	stopVisual(holder)
	local base = holder:GetPivot()
	local st = {Base = base, Char = char, Ride = 1, P = 1, Shown = 0} -- P 1: into the hands at once (the grip pose has them on it), then it rises WITH the hands
	--.. a giant travels only part of the way (riding a 50-stud cucumber into the hands would eat the screen)
	local sizeScale = math.max(tonumber(holder:GetAttribute("SizeScale")) or 1, 1)
	if sizeScale > 1 then st.Ride = math.clamp(1 / sizeScale, 0.25, 1) end
	Visual[holder] = st
	st.Conn = RunService.Heartbeat:Connect(function(dt)
		if not holder.Parent then
			stopVisual(holder, false)
			return
		end
		st.Shown = st.Shown + (st.P - st.Shown) * math.min(1, dt * 14)
		local mid = handsMidpoint(st.Char)
		if not mid then return end
		local a = math.clamp(st.Shown, 0, 1)
		a = a * a * (3 - 2 * a)
		holder:PivotTo(base:Lerp(CFrame.new(mid) * base.Rotation, a * st.Ride))
	end)
	return st
end

--==================================================================== the bar (our own lift)
local gui = Instance.new("ScreenGui")
gui.Name = "CucumberLiftBar"
gui.ResetOnSpawn = false
gui.DisplayOrder = 900 -- above the HUD / hotbar (the catcher must get every click), under Notify (2000)
gui.Enabled = false
gui.Parent = playerGui

--.. full-screen click catcher: every click / tap anywhere counts (and nothing underneath gets it)
local catcher = Instance.new("TextButton")
catcher.Name = "Catcher"
catcher.Text = ""
catcher.BackgroundTransparency = 1
catcher.AutoButtonColor = false
catcher.Size = UDim2.fromScale(1, 1)
catcher.ZIndex = 1
catcher.Parent = gui

--.. Root = the track's box: 46 % of the screen wide, height from the reference bar's ~10:1 shape
--.. (user 2026-09-16: "same size as the original attachment, not stretched across the screen");
--.. the title and the hint hang above it
local BAR_WIDTH = 0.46
local BAR_ASPECT = 10.3
local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 1)
root.Position = UDim2.fromScale(0.5, 0.87)
root.Size = UDim2.fromScale(BAR_WIDTH, 0)
root.BackgroundTransparency = 1
root.ZIndex = 2
root.Parent = gui
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = BAR_ASPECT
aspect.AspectType = Enum.AspectType.ScaleWithParentSize
aspect.DominantAxis = Enum.DominantAxis.Width
aspect.Parent = root
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(340, 0)
sizeLimit.MaxSize = Vector2.new(820, 1000)
sizeLimit.Parent = root
local rootScale = Instance.new("UIScale")
rootScale.Parent = root

local function strokeOn(inst, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Color3.fromRGB(20, 20, 24)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = inst
	return s
end

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0, 1)
title.Position = UDim2.new(0, 0, 0, -5)
title.Size = UDim2.fromScale(0.62, 0.55)
title.Font = FONT
title.TextScaled = true
title.RichText = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = ""
title.ZIndex = 3
title.Parent = root
strokeOn(title, 2.5)

local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0.5, 1)
track.Position = UDim2.fromScale(0.5, 1)
track.Size = UDim2.fromScale(1, 1)
track.BackgroundColor3 = Color3.fromRGB(214, 214, 214)
track.BackgroundTransparency = 0.3
track.BorderSizePixel = 0
track.ZIndex = 3
track.Parent = root
local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(0, 8)
trackCorner.Parent = track
strokeOn(track, 4, Color3.fromRGB(18, 18, 20))

local ZONE = 0.05 -- the red / green ends, as a fraction of the track
local redZone = Instance.new("Frame")
redZone.Name = "RedZone"
redZone.Size = UDim2.fromScale(ZONE, 1)
redZone.BackgroundColor3 = Color3.fromRGB(205, 18, 18)
redZone.BorderSizePixel = 0
redZone.ZIndex = 4
redZone.Parent = track
local redCorner = Instance.new("UICorner")
redCorner.CornerRadius = UDim.new(0, 8)
redCorner.Parent = redZone

local greenZone = Instance.new("Frame")
greenZone.Name = "GreenZone"
greenZone.AnchorPoint = Vector2.new(1, 0)
greenZone.Position = UDim2.fromScale(1, 0)
greenZone.Size = UDim2.fromScale(ZONE, 1)
greenZone.BackgroundColor3 = Color3.fromRGB(38, 190, 66)
greenZone.BorderSizePixel = 0
greenZone.ZIndex = 4
greenZone.Parent = track
local greenCorner = Instance.new("UICorner")
greenCorner.CornerRadius = UDim.new(0, 8)
greenCorner.Parent = greenZone

local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.BackgroundTransparency = 1
icon.Image = STRENGTH_ICON
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(Lift.START, 0.5)
icon.Size = UDim2.fromScale(0, 1.4)
icon.ScaleType = Enum.ScaleType.Fit
icon.ZIndex = 6
icon.Parent = track
local iconAspect = Instance.new("UIAspectRatioConstraint")
iconAspect.AspectRatio = 1
iconAspect.AspectType = Enum.AspectType.ScaleWithParentSize
iconAspect.DominantAxis = Enum.DominantAxis.Height
iconAspect.Parent = icon
local iconScale = Instance.new("UIScale")
iconScale.Parent = icon

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.BackgroundTransparency = 1
hint.AnchorPoint = Vector2.new(1, 1)
hint.Position = UDim2.new(1, 0, 0, -5)
hint.Size = UDim2.fromScale(0.36, 0.55)
hint.Font = FONT
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(255, 236, 120)
local DEFAULT_HINT = UserInputService.TouchEnabled and "TAP! TAP! TAP!" or "CLICK! CLICK! CLICK!"
hint.Text = DEFAULT_HINT
hint.ZIndex = 3
hint.Parent = root
strokeOn(hint, 2)
local hintScale = Instance.new("UIScale")
hintScale.Parent = hint

local function iconX(p)
	--.. the icon's centre runs from the red end to the green end
	return ZONE * 0.5 + math.clamp(p, 0, 1) * (1 - ZONE)
end

--.. the shout for the lift's difficulty band (CucumberLift.DIFFICULTY row.Bar: "CLICK FAST!" / "CLICK FASTER!!" /
--.. "MASH!!!" below the weight; the plain "CLICK! CLICK! CLICK!" otherwise; touch says TAP)
local function hintFor(band)
	for _, row in ipairs(Lift.DIFFICULTY) do
		if row.Name == band and row.Bar then
			return UserInputService.TouchEnabled and (row.Bar:gsub("CLICK", "TAP"):gsub("MASH", "TAP FAST")) or row.Bar
		end
	end
	return DEFAULT_HINT
end

local showTween
local function showBar(name, kg, band)
	title.Text = CucumberMutations.ColorizeName(name) .. "  ·  " .. Lift.Format(kg)
	hint.Text = hintFor(band)
	icon.Position = UDim2.fromScale(iconX(Lift.START), 0.5)
	icon.ImageColor3 = Color3.new(1, 1, 1)
	if showTween then showTween:Cancel() end
	rootScale.Scale = 0.75
	gui.Enabled = true
	showTween = TweenService:Create(rootScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	showTween:Play()
end

local function hideBar()
	if showTween then showTween:Cancel() end
	showTween = TweenService:Create(rootScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.7})
	showTween.Completed:Once(function() if rootScale.Scale <= 0.71 then gui.Enabled = false end end)
	showTween:Play()
end

local popTween
local function popIcon()
	if popTween then popTween:Cancel() end
	iconScale.Scale = 1.28
	popTween = TweenService:Create(iconScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1})
	popTween:Play()
end

--==================================================================== camera (our own lift)
local Cam = {} -- {Saved = {CFrame, Type, Fov}, From, To, T0, Punch, Active}
local CAM_NAME = "CucumberLiftCamera"

local function frameTarget(char, holder)
	local camera = workspace.CurrentCamera
	local rootPart = char:FindFirstChild("HumanoidRootPart")
	local box, size = boundsOf(holder)
	--.. a cucumber that is not actually at the player's feet (a forced dev-hook lift from across the
	--.. map) must not drag the frame away: frame a spot just ahead of the player instead
	if (box.Position - rootPart.Position).Magnitude > 16 then
		box = CFrame.new(rootPart.Position + rootPart.CFrame.LookVector * 3 - Vector3.new(0, 2, 0))
		size = Vector3.new(2, 2, 2)
	end
	local charSize = char:GetExtentsSize()
	local bodyCentre = rootPart.Position - Vector3.new(0, 0.4, 0)
	local focus = bodyCentre * 0.6 + box.Position * 0.4
	focus = Vector3.new(focus.X, math.max(focus.Y, bodyCentre.Y - 1.5), focus.Z)
	--.. the camera sits on the cucumber's far side, looking back at the player over it
	local dir = Vector3.new(box.Position.X - rootPart.Position.X, 0, box.Position.Z - rootPart.Position.Z)
	dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
	local fov = math.rad(camera.FieldOfView)
	local aspect = camera.ViewportSize.X / math.max(camera.ViewportSize.Y, 1)
	local height = math.max(charSize.Y, size.Y) + 2.5
	local width = math.max(charSize.X, size.X, size.Z) + 3
	local dV = (height * 0.5) / math.tan(fov * 0.5)
	local dH = (width * 0.5) / (math.tan(fov * 0.5) * aspect)
	local dist = math.max(dV, dH) + (rootPart.Position - box.Position).Magnitude * 0.5 + 1
	dist = math.clamp(dist, 6, 60)
	local eye = focus + dir * dist + Vector3.new(0, dist * 0.28, 0)
	--.. do not park inside a wall
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {char, holder, workspace:FindFirstChild("Breakables") or char}
	local hit = workspace:Raycast(focus, eye - focus, rp)
	if hit then
		local d = math.max((hit.Position - focus).Magnitude * 0.9, 3)
		eye = focus + (eye - focus).Unit * d
	end
	return CFrame.lookAt(eye, focus)
end

local CAM_SNAP_DISTANCE = 20 -- the character moved this far since the lift began (the night return to the lobby, a respawn): no glide, the camera is handed straight back

local function cameraRestore(cam)
	RunService:UnbindFromRenderStep(CAM_NAME)
	cam.FieldOfView = Cam.Saved.Fov
	cam.CameraType = Cam.Saved.Type
	Cam.Active = false
	Cam.Saved = nil
	Cam.LastWrite = nil
end

--.. another controller took the camera (the night raid cutscene: Scriptable + a CFrame every Heartbeat): step aside
--.. and leave the camera exactly as it is -- putting it back to Custom here is what made the cutscene fight the
--.. default camera for its whole length (the "camera glitch" of a lift cut short by nightfall)
local function cameraYield()
	RunService:UnbindFromRenderStep(CAM_NAME)
	Cam.Active = false
	Cam.Saved = nil
	Cam.LastWrite = nil
end

local function cameraIn(char, holder)
	local camera = workspace.CurrentCamera
	if not camera then return end
	pcall(RunService.UnbindFromRenderStep, RunService, CAM_NAME)
	local root = char:FindFirstChild("HumanoidRootPart")
	--.. the way back is remembered RELATIVE to the character (2026-09-18, user: "camera glitch when picking up a
	--.. cucumber and then night happens"): nightfall cancels the lift and teleports the lifter to the lobby in the
	--.. same breath, and the camera used to glide back to its old spot in the biome and then snap to the lobby
	Cam.Saved = Cam.Saved or {Offset = root and root.CFrame:ToObjectSpace(camera.CFrame) or nil, CFrame = camera.CFrame, Type = camera.CameraType, Fov = camera.FieldOfView}
	Cam.Char = char
	Cam.RootAt = root and root.Position or camera.CFrame.Position
	Cam.From = camera.CFrame
	Cam.To = frameTarget(char, holder)
	Cam.T0 = os.clock()
	Cam.Punch = 0
	Cam.Active = true
	Cam.Out = false
	Cam.LastWrite = nil
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(CAM_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local cam = workspace.CurrentCamera
		if not cam then return end
		--.. somebody else wrote the camera since our last frame, or reset its type: it is theirs now
		if cam.CameraType ~= Enum.CameraType.Scriptable or (Cam.LastWrite and cam.CFrame ~= Cam.LastWrite) then
			cameraYield()
			return
		end
		local rootNow = Cam.Char and Cam.Char.Parent and Cam.Char:FindFirstChild("HumanoidRootPart")
		--.. the character is gone or was moved far away (night return, respawn): hand the camera straight back
		if not rootNow or (rootNow.Position - Cam.RootAt).Magnitude > CAM_SNAP_DISTANCE then
			cameraRestore(cam)
			return
		end
		local dur = Cam.Out and Lift.CAMERA_OUT or Lift.CAMERA_IN
		local a = math.clamp((os.clock() - Cam.T0) / dur, 0, 1)
		a = 1 - (1 - a) * (1 - a) -- quad out
		local to = Cam.To
		if Cam.Out and Cam.Saved.Offset then to = rootNow.CFrame * Cam.Saved.Offset end -- back to where the camera sat, relative to the character
		cam.CFrame = Cam.From:Lerp(to, a)
		Cam.LastWrite = cam.CFrame
		Cam.Punch = math.max(0, Cam.Punch - dt * 12)
		cam.FieldOfView = Cam.Saved.Fov + Cam.Punch
		if Cam.Out and a >= 1 then cameraRestore(cam) end
	end)
end

local function cameraOut()
	local camera = workspace.CurrentCamera
	if not (Cam.Active and camera) then return end
	Cam.From = camera.CFrame
	Cam.To = Cam.Saved.CFrame
	Cam.T0 = os.clock()
	Cam.Out = true
end

local function cameraPunch(amount)
	if Cam.Active then Cam.Punch = math.min(6, Cam.Punch + amount) end
end

--==================================================================== our own lift
local session -- {Holder, Token, Char, Hum, Root, State, P, Params, Kg, Name, T0, Conns, Visual, Rig}

local function humanoidOf()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local controls
pcall(function()
	local ps = player:WaitForChild("PlayerScripts", 5)
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if pm then controls = require(pm):GetControls() end
end)

local frozen = false
local savedJump
--.. the player's own input is off from the moment the lift starts (the walk-up moves the
--.. character); the body itself freezes once the bar is up (WalkSpeed 0, no jump, no turning)
local function freezeControls(on)
	if controls then pcall(on and controls.Disable or controls.Enable, controls) end
end
local function freeze(on)
	frozen = on
	local hum = humanoidOf()
	if on then
		freezeControls(true)
		if hum then
			if not savedJump then savedJump = {JumpPower = hum.JumpPower, JumpHeight = hum.JumpHeight, AutoRotate = hum.AutoRotate} end
			hum.JumpPower = 0
			hum.JumpHeight = 0
			hum.AutoRotate = false
			hum.WalkSpeed = 0
		end
	else
		freezeControls(false)
		if hum then
			if savedJump then
				hum.JumpPower = savedJump.JumpPower
				hum.JumpHeight = savedJump.JumpHeight
				hum.AutoRotate = savedJump.AutoRotate
			end
			local base = tonumber(player:GetAttribute("StrengthWalkSpeed"))
			base = (base and base > 0) and base or 16
			--.. a load heavier than our strength keeps us slow (StrengthProgressionServer applies the same rule)
			local kg = tonumber(player:GetAttribute("CarryingCucumberKg"))
			local data = player:FindFirstChild("Data")
			local strength = data and data:FindFirstChild("Strength")
			local mult = kg and strength and Lift.SpeedFor(Lift.Ratio(strength.Value, kg)) or 1
			--.. a boost pad boost still running doubles it (StrengthProgressionServer applies the same rule, 2026-09-19)
			local boostUntil = tonumber(player:GetAttribute("SpeedBoostUntil"))
			local boost = (boostUntil and boostUntil > workspace:GetServerTimeNow()) and 2 or 1
			hum.WalkSpeed = (player:GetAttribute("SlowMode") == true and 25 or base * mult) * boost -- slow mode 25 (was 16, 2026-09-22) = StrengthProgressionServer SLOW_MODE_SPEED
		end
		savedJump = nil
	end
end
--.. hold the freeze against anything that rewrites WalkSpeed meanwhile
RunService.Stepped:Connect(function()
	if not frozen then return end
	local hum = humanoidOf()
	if hum and hum.WalkSpeed ~= 0 then hum.WalkSpeed = 0 end
end)

local function send(kind, extra)
	extra = extra or {}
	extra.Kind = kind
	LiftRemote:FireServer(extra)
end

local INPUT_ACTION = "CucumberLiftInput"
local function finish(s, restoreCucumber)
	if s.Done then return end
	s.Done = true
	if session == s then session = nil end
	for _, c in ipairs(s.Conns) do c:Disconnect() end
	pcall(ContextActionService.UnbindAction, ContextActionService, INPUT_ACTION)
	hideBar()
	cameraOut()
	freeze(false)
	if s.Char then releaseRig(s.Char) end
	if s.Holder then stopVisual(s.Holder, restoreCucumber ~= false) end
end

--.. LIFTED: the hoist plays while the server checks the claim and swaps the cucumber onto the
--.. shoulder (tell = false when the SERVER decided it, e.g. the "win" dev hook)
local function win(s, tell)
	if s.State ~= "lift" then return end
	s.State = "hoist"
	if tell ~= false then send("Result", {Token = s.Token, Result = "done"}) end
	icon.Position = UDim2.fromScale(iconX(1), 0.5)
	icon.ImageColor3 = Color3.fromRGB(150, 255, 150)
	if s.Rig then
		s.Rig.TargetT = CLIP_LEN
		s.Rig.Rate = (CLIP_LEN - LIFT_LEN) / HOIST_LEN
		s.Rig.Tremble = 0
	end
	if s.Visual then s.Visual.P = 1 end
	pcall(SoundController.PlayFX, "Whoosh", {Volume = 0.4})
	task.delay(HOIST_LEN + 0.25, function()
		if session == s then finish(s, false) end
	end)
end

local function click()
	local s = session
	if not (s and s.State == "lift") then return end
	s.P = math.min(s.P + s.Params.Gain, 1.05)
	s.Clicks += 1
	s.LastClick = os.clock()
	s.Rig.Pump = PUMP -- the hands heave up a touch on every click
	popIcon()
	cameraPunch(1.6)
	pcall(SoundController.PlayFX, "Click Sound", {Volume = 0.35, Speed = 0.9 + 0.35 * math.clamp(s.P, 0, 1)})
	if s.P >= 1 then win(s, true) end
end

local function fail(s, tell)
	if s.State ~= "lift" then return end
	s.State = "fail"
	if tell ~= false then send("Result", {Token = s.Token, Result = "fail"}) end
	Notify.Show("Too heavy", Notify.COLORS.Error)
	pcall(SoundController.PlayFX, "Big Thud", {Volume = 0.45, MaxLife = 1})
	cameraPunch(3)
	icon.Position = UDim2.fromScale(iconX(0), 0.5)
	icon.ImageColor3 = Color3.fromRGB(255, 120, 120)
	if s.Rig then
		s.Rig.TargetT = 0
		s.Rig.Rate = LIFT_LEN / FAIL_RELAX
		s.Rig.Tremble = 0
	end
	if s.Visual then s.Visual.P = 0 end
	task.delay(FAIL_RELAX + 0.2, function()
		if session == s then finish(s, true) end
	end)
end

local function cancel(s, tellServer)
	if s.Done then return end
	if tellServer ~= false and s.State ~= "hoist" then send("Result", {Token = s.Token, Result = "cancel"}) end
	if s.Rig then
		s.Rig.TargetT = 0
		s.Rig.Rate = LIFT_LEN / FAIL_RELAX
	end
	finish(s, true)
end

local function startOwn(payload)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	local holder = payload.Holder
	if not (hum and rootPart and holder and holder.Parent) then
		send("Result", {Token = payload.Token, Result = "cancel"})
		return
	end
	if session then cancel(session, true) end
	local s = {Holder = holder, Token = payload.Token, Char = char, Hum = hum, Root = rootPart, State = "approach",
		P = payload.Start or Lift.START, Params = {Start = payload.Start or Lift.START, Gain = payload.Gain or 0.1, Drift = payload.Drift or 0.2},
		Kg = payload.Kg or 0, Name = payload.Name or holder.Name, Band = payload.Band, Conns = {}, Clicks = 0, LastSent = 0}
	session = s
	freezeControls(true)
	table.insert(s.Conns, hum.Died:Connect(function() cancel(s, true) end))
	table.insert(s.Conns, holder.AncestryChanged:Connect(function()
		if not holder:IsDescendantOf(workspace) and s.State ~= "hoist" then cancel(s, true) end
	end))
	--.. X / B cancels (the walk is frozen, so there is no walking away)
	table.insert(s.Conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.X or input.KeyCode == Enum.KeyCode.ButtonB then cancel(s, true) end
	end))
	task.spawn(function()
		--.. walk up to the cucumber and face it (Humanoid:Move per frame, like the control scripts)
		local cf, size = boundsOf(holder)
		local centre = cf.Position
		local flat = Vector3.new(rootPart.Position.X - centre.X, 0, rootPart.Position.Z - centre.Z)
		local dir = flat.Magnitude > 0.05 and flat.Unit or -Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
		local halfWide = math.max(size.X, size.Z) * 0.5
		local sizeScale = math.max(tonumber(holder:GetAttribute("SizeScale")) or 1, 1)
		local ceiling = sizeScale > 1 and math.max(4.5, halfWide + 2) or 4.5
		local standDist = math.clamp(halfWide * 0.55 + 1.3, 1.6, ceiling)
		local stand = Vector3.new(centre.X, rootPart.Position.Y, centre.Z) + dir * standDist
		local t0 = os.clock()
		local deadline = t0 + APPROACH - 0.08
		while os.clock() < deadline and not s.Done do
			local d = Vector3.new(stand.X - rootPart.Position.X, 0, stand.Z - rootPart.Position.Z)
			local dist = d.Magnitude
			if dist < 0.5 then break end
			hum:Move(d.Unit * math.clamp(dist / 3, 0.2, 1), false)
			RunService.Heartbeat:Wait()
		end
		hum:Move(Vector3.zero, false)
		if s.Done then return end
		local look = Vector3.new(centre.X, rootPart.Position.Y, centre.Z)
		if (look - rootPart.Position).Magnitude > 0.05 then rootPart.CFrame = CFrame.lookAt(rootPart.Position, look) end
		freeze(true)
		local remaining = APPROACH - (os.clock() - t0)
		if remaining > 0 then task.wait(remaining) end
		if s.Done then return end
		--.. THE BAR
		s.State = "lift"
		s.T0 = os.clock()
		s.LastClick = os.clock()
		s.GraceUntil = s.T0 + Lift.GRACE -- the icon waits for the camera pan before it starts sliding
		s.Rig = rigFor(char)
		s.Rig.T, s.Rig.TargetT, s.Rig.Rate = 0, 0, nil
		s.Visual = startVisual(holder, char)
		cameraIn(char, holder)
		showBar(s.Name, s.Kg, s.Band)
		table.insert(s.Conns, catcher.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then click() end
		end))
		ContextActionService:BindActionAtPriority(INPUT_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then click() end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR2)
		table.insert(s.Conns, RunService.Heartbeat:Connect(function(dt)
			if s.State ~= "lift" then return end
			local now = os.clock()
			local drifting = now >= s.GraceUntil
			if drifting then s.P -= s.Params.Drift * dt end
			local p = math.clamp(s.P, 0, 1)
			--.. the pose follows the bar (hands from the ground to the chest, a heave per click); a losing bar trembles
			s.Rig.Pump = (s.Rig.Pump or 0) * math.exp(-dt * PUMP_DECAY)
			s.Rig.TargetT = math.min(liftTimeFor(p) + s.Rig.Pump, LIFT_LEN)
			local losing = drifting and (now - (s.LastClick or 0)) > 0.25
			s.Rig.Tremble = losing and math.sin(os.clock() * 40) * 0.012 or 0
			icon.Position = UDim2.fromScale(iconX(p), 0.5)
			icon.Rotation = losing and math.sin(os.clock() * 30) * 4 or 0
			hintScale.Scale = 1 + 0.06 * math.sin(now * 9)
			if now - s.LastSent >= 1 / PROGRESS_HZ then
				s.LastSent = now
				send("Progress", {Token = s.Token, P = p})
			end
			if s.P <= 0 then
				fail(s)
			elseif now - s.T0 > Lift.MAX_TIME then
				fail(s)
			end
		end))
	end)
end

--==================================================================== other players' lifts
local Others = {} -- [Player] = {Token, Holder, Char, Visual, Rig}
local function stopOther(who, restore)
	local st = Others[who]
	if not st then return end
	Others[who] = nil
	if st.Holder then stopVisual(st.Holder, restore ~= false) end
	if st.Char then releaseRig(st.Char) end
end

local function startOther(payload)
	local who = payload.Player
	local holder = payload.Holder
	local char = who and who.Character
	if not (holder and holder.Parent and char) then return end
	stopOther(who)
	local st = {Token = payload.Token, Holder = holder, Char = char}
	Others[who] = st
	task.delay(APPROACH, function()
		if Others[who] ~= st or not holder.Parent then return end
		st.Rig = rigFor(char)
		st.Rig.T, st.Rig.TargetT, st.Rig.Rate = 0, 0, nil
		st.Visual = startVisual(holder, char)
	end)
end

LiftRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local kind = payload.Kind
	local who = payload.Player
	if kind == "Start" then
		if who == player then startOwn(payload) else startOther(payload) end
	elseif who == player then
		--.. our own bar decides for itself; the server steps in to cancel it (night, a guardian,
		--.. a refused claim) or to settle it (the "win" / "lose" dev hooks, the MAX_TIME timeout)
		local s = session
		if not (s and (payload.CancelAll or payload.Token == nil or payload.Token == s.Token)) then return end
		if kind == "Cancel" then
			cancel(s, false)
		elseif kind == "Fail" then
			fail(s, false)
		elseif kind == "Hoist" then
			win(s, false)
		end
	else
		local st = Others[who]
		if not st or (payload.Token and st.Token ~= payload.Token and not payload.CancelAll) then return end
		if kind == "Progress" then
			local p = math.clamp(tonumber(payload.P) or 0, 0, 1)
			if st.Rig then st.Rig.TargetT = liftTimeFor(p) end -- the cucumber stays in the hands (startVisual P = 1)
		elseif kind == "Hoist" then
			if st.Rig then
				st.Rig.TargetT = CLIP_LEN
				st.Rig.Rate = (CLIP_LEN - LIFT_LEN) / HOIST_LEN
			end
			if st.Visual then st.Visual.P = 1 end
			task.delay(HOIST_LEN + 0.25, function() if Others[who] == st then stopOther(who, false) end end)
		elseif kind == "Fail" then
			if st.Rig then
				st.Rig.TargetT = 0
				st.Rig.Rate = LIFT_LEN / FAIL_RELAX
			end
			if st.Visual then st.Visual.P = 0 end
			task.delay(FAIL_RELAX + 0.2, function() if Others[who] == st then stopOther(who, true) end end)
		elseif kind == "Cancel" then
			if st.Rig then
				st.Rig.TargetT = 0
				st.Rig.Rate = LIFT_LEN / FAIL_RELAX
			end
			task.delay(FAIL_RELAX, function() if Others[who] == st then stopOther(who, true) end end)
		end
	end
end)

Players.PlayerRemoving:Connect(function(who) stopOther(who, true) end)
player.CharacterAdded:Connect(function()
	if session then finish(session, true) end
	frozen = false
	savedJump = nil
end)

--..Studio dev hook: PlayerGui attribute LiftDevCPS = N clicks the bar N times a second while it is up
--..(0 / nil = off); LiftDevState mirrors the session for evals ("lift 0.42" / "hoist" / "fail" / "idle")..--
if RunService:IsStudio() then
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local s = session
		playerGui:SetAttribute("LiftDevState", s and (s.State .. (s.State == "lift" and string.format(" %.3f", math.clamp(s.P, 0, 1)) or "")) or "idle")
		local cps = tonumber(playerGui:GetAttribute("LiftDevCPS")) or 0
		if not (s and s.State == "lift" and cps > 0) then
			acc = 0
			return
		end
		acc += dt * cps
		while acc >= 1 do
			acc -= 1
			click()
		end
	end)
end
