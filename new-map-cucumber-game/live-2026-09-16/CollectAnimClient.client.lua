--[[
	CollectAnimClient  (LocalScript, StarterPlayerScripts)
	Plays the cucumber-collect choreography that CucumberCarry (server) schedules
	through Remotes.CollectAnim (server -> ALL clients):

	  {Kind = "Collect", Player, Holder, Struggle = seconds}
	      our own character: walk up to the cucumber (APPROACH), loop the
	      CucumberStruggle clip for Struggle seconds (0 = none), then play the
	      CucumberPickUp clip; the server swaps the field cucumber for the shoulder copy
	      GRAB_T into the pick-up. Player input is frozen meanwhile (PlayerModule
	      controls). A stud-sized "PULLING..." bar sits over the cucumber while tugging
	      (no numbers: the strength requirement is hidden, user 2026-09-06).
	      every client: the cucumber rocks with each tug and rides the hands up to the
	      chest during the lift (local pivots only; the server never moves it).
	  {Kind = "Tug", Player, Holder, Duration}             too heavy: one short tug
	  {Kind = "Cancel", Player, Holder}                    stop and restore everything
	  {Kind = "Fall", Player, Landing, Home}               heavy / weak carry stumble: the
	      load has just left the shoulder (FallDrop follows, or Home = it flew back to its
	      field); our own character freezes and, FALL_AFTER_DROP later, trips: the
	      CucumberFall clip from FALL_CLIP_START (its carry-pose lead-in is skipped) to the
	      end (user 2026-09-07: "drop the cucumber first, then fall"; no fling); every
	      client hears the thud at FALL_AFTER_DROP + FALL_PLANT_T - FALL_CLIP_START
	  {Kind = "FallDrop", Player, Holder, From}            the server has re-spawned the
	      load as a field cucumber at the slip spot; every client tumbles it there from
	      the shoulder (From) over FALL_FLIGHT, then it rests

	HEAVY CARRY SLOWDOWN (2026-09-06; per band since 2026-09-07): while the server stamps
	CarryingCucumberSpeed on us (the band's multiplier from CucumberStrength.BANDS: sturdy
	x0.8, shaky x0.6, hopeless x0.5) the walk runs at that fraction of the base speed. The
	base is the StrengthWalkSpeed attribute StrengthProgressionServer stamps (it also
	writes Humanoid.WalkSpeed itself, so any WalkSpeed change that is not ours is taken
	as a new base and re-scaled). Easy carries, and carries the lobby settled, are never slowed.

	Animations live in ReplicatedStorage.Assets.Animations as Animation instances
	(CucumberPickUp, CucumberStruggle, CucumberFall). While an AnimationId is still empty
	(not published yet) Studio falls back to the KeyframeSequence stored next to it
	(<Name>Sequence) through KeyframeSequenceProvider:RegisterKeyframeSequence, which
	only works in Studio. Timeline constants: ReplicatedStorage.Modules.CucumberStrength.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local CucumberStrength = require(Modules:WaitForChild("CucumberStrength"))
local SoundController = require(Modules:WaitForChild("SoundController"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AnimRemote = Remotes:WaitForChild("CollectAnim")
local CancelPickup = Remotes:WaitForChild("CancelCucumberPickup")
local Input = game:GetService("UserInputService")
local Actions = game:GetService("ContextActionService")
local AnimFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations")

local APPROACH = CucumberStrength.APPROACH
local GRAB_T = CucumberStrength.GRAB_T
local PICKUP_LENGTH = CucumberStrength.PICKUP_LENGTH
local LOOP = CucumberStrength.STRUGGLE_LOOP
local FALL_LENGTH = CucumberStrength.FALL_LENGTH
local FALL_FLIGHT = CucumberStrength.FALL_FLIGHT
local FALL_CLIP_START = CucumberStrength.FALL_CLIP_START or 0 -- seconds into CucumberFall the trip starts (lead-in skipped)
local FALL_AFTER_DROP = CucumberStrength.FALL_AFTER_DROP or 0 -- seconds between the load leaving the shoulder and the trip
local FALL_PLANT_T = 0.733 -- seconds into CucumberFall: face meets floor (clip key)
local RIDE_START = 0.7 -- seconds into the pick-up clip: the grip closes, the cucumber starts riding the hands
local PULL_PEAK = 0.35 -- where in the struggle loop the pull-back peaks (clip key at 0.333 s)
local FONT = Enum.Font.FredokaOne

--..Input freeze + heavy-carry slowdown..--
--.. With the PlayerModule present its controls are disabled for the whole choreography
--.. (Humanoid:MoveTo keeps working). This place's PlayerScripts has NO PlayerModule
--.. (checked 2026-09-06), so the fallback zeroes WalkSpeed / jump instead -- and only
--.. AFTER the walk-up, because a zero WalkSpeed would stop MoveTo as well.
local controls
task.spawn(function()
	local ok, pm = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10))
	end)
	if ok and type(pm) == "table" and pm.GetControls then
		local ok2, c = pcall(pm.GetControls, pm)
		if ok2 then controls = c end
	end
end)

local frozen = false -- choreography running (fallback mode: WalkSpeed 0, no jump)
local savedJump -- {JumpPower, JumpHeight} while frozen
local ourSpeed -- the WalkSpeed we wrote last (nil = the server's value stands)
local seenBase -- last WalkSpeed that was not ours

local function humanoidOf()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

--.. the band's WalkSpeed multiplier while carrying, nil when nothing slows us
local function speedMult()
	local m = tonumber(player:GetAttribute("CarryingCucumberSpeed"))
	if m and m > 0 and m ~= 1 then return m end
	return nil
end

local function baseWalkSpeed(hum)
	local v = tonumber(player:GetAttribute("StrengthWalkSpeed"))
	if v and v > 0 then return v end
	if seenBase and seenBase > 0 then return seenBase end
	return hum.WalkSpeed > 0 and hum.WalkSpeed or 16
end

--.. what WE want the WalkSpeed to be, or nil when the server's value should stand
local function desiredSpeed(hum)
	if frozen and not controls then return 0 end
	local m = speedMult()
	if m then return math.min(120, baseWalkSpeed(hum) * m) end
	return nil
end

local function applySpeed()
	local hum = humanoidOf()
	if not hum then return end
	if frozen and not controls then
		if not savedJump then savedJump = {JumpPower = hum.JumpPower, JumpHeight = hum.JumpHeight} end
		hum.JumpPower = 0
		hum.JumpHeight = 0
	elseif savedJump then
		hum.JumpPower = savedJump.JumpPower
		hum.JumpHeight = savedJump.JumpHeight
		savedJump = nil
	end
	local target = desiredSpeed(hum)
	if target == nil then
		if ourSpeed ~= nil then
			ourSpeed = nil
			hum.WalkSpeed = baseWalkSpeed(hum)
		end
		return
	end
	ourSpeed = target
	if math.abs(hum.WalkSpeed - target) > 1e-3 then hum.WalkSpeed = target end
end

local function watchHumanoid(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		local v = hum.WalkSpeed
		if ourSpeed ~= nil and math.abs(v - ourSpeed) < 1e-3 then return end
		--.. somebody else (StrengthProgressionServer) set a new base: re-scale it
		seenBase = v
		if desiredSpeed(hum) ~= nil then applySpeed() end
	end)
end
if player.Character then task.spawn(watchHumanoid, player.Character) end
player.CharacterAdded:Connect(function(char)
	frozen = false
	savedJump = nil
	ourSpeed = nil
	watchHumanoid(char)
	task.defer(applySpeed)
end)
player:GetAttributeChangedSignal("CarryingCucumberSpeed"):Connect(applySpeed)
player:GetAttributeChangedSignal("StrengthWalkSpeed"):Connect(applySpeed)

local function freezeInput()
	if controls then controls:Disable() end
end
local function freezeBody(on)
	frozen = on
	if not on and controls then controls:Enable() end
	applySpeed()
end

--..Animations..--
local fallbackAnims = {}
local function animationFor(name)
	local anim = AnimFolder:FindFirstChild(name)
	if not (anim and anim:IsA("Animation")) then return nil end
	if anim.AnimationId ~= "" then return anim end
	if fallbackAnims[name] then return fallbackAnims[name] end
	if not RunService:IsStudio() then return nil end
	--.. not published yet: Studio can register the KeyframeSequence kept next to it
	local kfs = AnimFolder:FindFirstChild(name .. "Sequence")
	if not kfs then return nil end
	local ok, id = pcall(KeyframeSequenceProvider.RegisterKeyframeSequence, KeyframeSequenceProvider, kfs)
	if not ok or not id then
		warn("[CollectAnim] " .. name .. " has no AnimationId and RegisterKeyframeSequence failed: " .. tostring(id))
		return nil
	end
	local temp = Instance.new("Animation")
	temp.Name = name
	temp.AnimationId = id
	fallbackAnims[name] = temp
	return temp
end

local tracks = {} -- [character] = {[name] = AnimationTrack}
local function trackFor(char, name)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 3)
	if not animator then return nil end
	local perChar = tracks[char]
	if not perChar then
		perChar = {}
		tracks[char] = perChar
	end
	if perChar[name] then return perChar[name] end
	local anim = animationFor(name)
	if not anim then return nil end
	local ok, track = pcall(animator.LoadAnimation, animator, anim)
	if not ok then
		warn("[CollectAnim] LoadAnimation " .. name .. ": " .. tostring(track))
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = (name == "CucumberStruggle")
	perChar[name] = track
	return track
end
player.CharacterRemoving:Connect(function(char)
	tracks[char] = nil
end)

--..Holder helpers..--
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

--..Cucumber visuals (every client): rock with each tug, then ride the hands up..--
local Visual = {} -- [holder] = state

local function stopVisual(holder, restore)
	local st = Visual[holder]
	if not st then return end
	Visual[holder] = nil
	if st.Conn then st.Conn:Disconnect() end
	if restore ~= false and holder.Parent then pcall(holder.PivotTo, holder, st.Base) end
end

local function startVisual(holder, who, struggle, doPickup)
	stopVisual(holder)
	local base = holder:GetPivot()
	local st = {Base = base, T0 = os.clock(), Ride = 1}
	--.. a giant (CucumberMutations.SIZES, 2026-09-08) cannot play the normal choreography: riding
	--.. a 50-stud cucumber into the character's hands fills the screen and sinks it through the
	--.. ground, and tilting it about its middle sweeps its bottom half through the floor. So it
	--.. travels only part of the way, and it rocks about its BASE like a real toppling thing.
	local sizeScale = math.max(tonumber(holder:GetAttribute("SizeScale")) or 1, 1)
	if sizeScale > 1 then
		--.. the true underside comes from the bounding box, not the pivot: on a template model
		--.. the pivot is the Hitbox centre, which is not always the centre of the body
		local box, extents = boundsOf(holder)
		st.Ride = math.clamp(1 / sizeScale, 0.25, 1)
		st.RockPivot = Vector3.new(base.Position.X, box.Position.Y - extents.Y * 0.5, base.Position.Z)
		st.RockLift = 0.15 * sizeScale
	end
	Visual[holder] = st
	st.Conn = RunService.Heartbeat:Connect(function()
		if not holder.Parent then
			stopVisual(holder, false)
			return
		end
		local t = os.clock() - st.T0 - APPROACH
		if t < 0 then return end
		local char = who.Character
		if t < struggle then
			--.. tug: tip toward the puller, lift a touch, tremble at the peak
			local phase = (t % LOOP) / LOOP
			local pull = phase < 0.75 and math.sin(math.pi * phase / 0.75) or 0
			local axis = Vector3.xAxis
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local dir = Vector3.new(root.Position.X - base.Position.X, 0, root.Position.Z - base.Position.Z)
				if dir.Magnitude > 0.05 then axis = Vector3.yAxis:Cross(dir.Unit) end
			end
			local angle = math.rad((8 + math.sin(t * 55) * 1.5) * pull)
			if st.RockPivot then
				--.. rotate about the cucumber's foot, not its centre
				local lifted = CFrame.new(base.Position + Vector3.new(0, st.RockLift * pull, 0)) * base.Rotation
				local foot = st.RockPivot
				holder:PivotTo(CFrame.new(foot) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-foot) * lifted)
			else
				holder:PivotTo(CFrame.new(base.Position + Vector3.new(0, 0.15 * pull, 0)) * CFrame.fromAxisAngle(axis, angle) * base.Rotation)
			end
			st.Shaken = true
			local loopIndex = math.floor(t / LOOP)
			if phase >= PULL_PEAK and st.PulledLoop ~= loopIndex then
				st.PulledLoop = loopIndex
				pcall(SoundController.PlayFXAt, "Dirt Dig", base.Position, {Volume = 0.25, MaxLife = 0.5})
			end
			return
		end
		if not doPickup then
			stopVisual(holder)
			return
		end
		local tp = t - struggle -- time into the pick-up clip
		if tp < RIDE_START then
			if st.Shaken then
				st.Shaken = false
				holder:PivotTo(base)
			end
			return
		end
		if not st.Whooshed then
			st.Whooshed = true
			pcall(SoundController.PlayFXAt, "Whoosh", base.Position, {Volume = 0.35})
		end
		local mid = handsMidpoint(char)
		if mid then
			local alpha = math.clamp((tp - RIDE_START) / (GRAB_T - RIDE_START), 0, 1)
			alpha = alpha * alpha * (3 - 2 * alpha)
			holder:PivotTo(base:Lerp(CFrame.new(mid) * base.Rotation, alpha * st.Ride))
		end
		--.. the server swaps it for the shoulder copy at GRAB_T; if that never came, let go
		if tp > PICKUP_LENGTH + 0.5 then stopVisual(holder) end
	end)
end

--.. Stumble drop (every client): the freshly re-spawned field cucumber tumbles from the
--.. shoulder (`from`) to its resting spot in a low arc with a spin, then settles
local function startTumble(holder, from)
	stopVisual(holder)
	local base = holder:GetPivot()
	local st = {Base = base, T0 = os.clock()}
	Visual[holder] = st
	--.. a giant leaves the shoulder from ABOVE the player rather than from inside them, arcs in
	--.. proportion to its own body and topples instead of cartwheeling (2026-09-08)
	local sizeScale = math.max(tonumber(holder:GetAttribute("SizeScale")) or 1, 1)
	local _, extents = boundsOf(holder)
	local start = sizeScale > 1 and (from + Vector3.new(0, extents.Y * 0.35, 0)) or from
	local hop = sizeScale > 1 and math.max(1.1, extents.Y * 0.12) or 1.1
	local spin = math.pi * 1.5 / sizeScale
	local travel = Vector3.new(base.Position.X - start.X, 0, base.Position.Z - start.Z)
	local axis = travel.Magnitude > 0.05 and Vector3.yAxis:Cross(travel.Unit) or Vector3.xAxis
	holder:PivotTo(CFrame.new(start) * base.Rotation)
	st.Conn = RunService.Heartbeat:Connect(function()
		if not holder.Parent then
			stopVisual(holder, false)
			return
		end
		local a = (os.clock() - st.T0) / FALL_FLIGHT
		if a >= 1 then
			stopVisual(holder) -- back to the server's resting pose
			pcall(SoundController.PlayFXAt, "Dirt Dig", base.Position, {Volume = 0.45, MaxLife = 0.6})
			return
		end
		local pos = start:Lerp(base.Position, a) + Vector3.new(0, math.sin(a * math.pi) * hop, 0)
		holder:PivotTo(CFrame.new(pos) * CFrame.fromAxisAngle(axis, a * spin) * base.Rotation)
	end)
end

--..Struggle bar (own character only), sized in studs..--
local function stroke(label, thickness)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = Color3.fromRGB(20, 40, 15)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = label
end

local function showBar(s, holder, seconds)
	local host = rootOf(holder)
	if not host then return end
	local _, size = boundsOf(holder)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StruggleBar"
	--.. over a giant the true top edge is off the top of the screen: cap the lift, and grow the
	--.. bar a little so it does not read as a sticker on a 50-stud cucumber (2026-09-08)
	local barGrow = math.min(math.max(tonumber(holder:GetAttribute("SizeScale")) or 1, 1), 2)
	gui.Size = UDim2.new(4.4 * barGrow, 0, 1.0 * barGrow, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, math.min(size.Y * 0.5 + 1.6, 9), 0)
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	gui.Adornee = host
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	bg.BackgroundTransparency = 0.25
	bg.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.25, 0)
	c.Parent = bg
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.04, 0.06)
	label.Size = UDim2.fromScale(0.92, 0.5)
	label.Font = FONT
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 226, 120)
	label.Text = "PULLING..." -- no number: the requirement stays hidden
	label.Parent = bg
	stroke(label, 1.5)
	local trackBg = Instance.new("Frame")
	trackBg.Position = UDim2.fromScale(0.06, 0.64)
	trackBg.Size = UDim2.fromScale(0.88, 0.24)
	trackBg.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	trackBg.BorderSizePixel = 0
	trackBg.Parent = bg
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0.5, 0)
	tc.Parent = trackBg
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 230, 100)
	fill.BorderSizePixel = 0
	fill.Parent = trackBg
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0.5, 0)
	fc.Parent = fill
	gui.Parent = playerGui
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {Size = UDim2.fromScale(1, 1)}):Play()
	s.Bar = gui
end

--..Own character choreography..--
local session

local function finish(s, cancelled)
	if s.Done then return end
	s.Done = true
	if session == s then session = nil end
	if s.CancelConnections then for _, connection in ipairs(s.CancelConnections) do connection:Disconnect() end end
	if s.CancelAction then Actions:UnbindAction("CancelCucumberLift") end
	if s.DiedConn then s.DiedConn:Disconnect() end
	if s.Struggle and s.Struggle.IsPlaying then s.Struggle:Stop(0.15) end
	if cancelled and s.Clip and s.Clip.IsPlaying then s.Clip:Stop(0.15) end
	if s.Bar then
		s.Bar:Destroy()
		s.Bar = nil
	end
	freezeBody(false)
end

local function runOwn(payload, struggle)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local holder = payload.Holder
	if not (hum and root and holder and holder.Parent) then return end
	if session then finish(session, true) end
	local s = {Holder = holder, Char = char, Token = payload.Token, CancelConnections = {}}
	session = s
	local cancelUntil = os.clock() + APPROACH + struggle + GRAB_T
	local function cancelLift()
		if s.Done or not s.Token or os.clock() >= cancelUntil then return end
		CancelPickup:FireServer(s.Token)
		stopVisual(holder)
		finish(s, true)
	end
	if s.Token then
		s.CancelAction = true
		Actions:BindAction("CancelCucumberLift", function(_, state)
			if state == Enum.UserInputState.Begin then cancelLift() end
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.X, Enum.KeyCode.ButtonB)
		Actions:SetTitle("CancelCucumberLift", "Cancel")
		Actions:SetPosition("CancelCucumberLift", UDim2.fromScale(.72, .5))
		table.insert(s.CancelConnections, Input.InputBegan:Connect(function(input)
			if Input:GetFocusedTextBox() then return end
			if table.find({Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space}, input.KeyCode) then cancelLift() end
		end))
		table.insert(s.CancelConnections, Input.InputChanged:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > .25 then cancelLift() end
		end))
		table.insert(s.CancelConnections, Input.TouchMoved:Connect(function(input)
			local camera = workspace.CurrentCamera
			if camera and input.Position.X < camera.ViewportSize.X * .4 and input.Delta.Magnitude > 5 then cancelLift() end
		end))
	end
	freezeInput()
	s.DiedConn = hum.Died:Connect(function()
		finish(s, true)
	end)
	task.spawn(function()
		--.. walk up to the cucumber and face it
		local cf, size = boundsOf(holder)
		local center = cf.Position
		local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
		local dir = flat.Magnitude > 0.05 and flat.Unit or -Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		--.. the 4.5-stud ceiling was written when every field model was small; a GIANT (2026-09-08)
		--.. would swallow the character and the camera, so it stands outside the body instead.
		--.. Normal cucumbers keep the old ceiling exactly -- several of them (the Katana, the big
		--.. trees) already sit against it, and moving them would change every ordinary pick-up.
		local halfWide = math.max(size.X, size.Z) * 0.5
		local sizeScale = math.max(tonumber(holder:GetAttribute("SizeScale")) or 1, 1)
		local ceiling = sizeScale > 1 and math.max(4.5, halfWide + 2) or 4.5
		local standDist = math.clamp(halfWide * 0.55 + 1.3, 1.6, ceiling)
		local stand = Vector3.new(center.X, root.Position.Y, center.Z) + dir * standDist
		local t0 = os.clock()
		--.. Humanoid:Move per frame (what the control scripts do) -- MoveTo crawled on the
		--.. physique-scaled characters here (3.6 studs in 0.6 s at WalkSpeed 116); the move
		--.. vector shrinks over the last 3 studs so a fast character does not overshoot
		local deadline = t0 + APPROACH - 0.08
		while os.clock() < deadline and not s.Done do
			local flat = Vector3.new(stand.X - root.Position.X, 0, stand.Z - root.Position.Z)
			local dist = flat.Magnitude
			if dist < 0.5 then break end
			hum:Move(flat.Unit * math.clamp(dist / 3, 0.2, 1), false)
			RunService.Heartbeat:Wait()
		end
		hum:Move(Vector3.zero, false)
		if s.Done then return end
		local look = Vector3.new(center.X, root.Position.Y, center.Z)
		if (look - root.Position).Magnitude > 0.05 then
			root.CFrame = CFrame.lookAt(root.Position, look)
		end
		freezeBody(true)
		local remaining = APPROACH - (os.clock() - t0)
		if remaining > 0 then task.wait(remaining) end
		if s.Done then return end
		--.. tug
		if struggle > 0 then
			s.Struggle = trackFor(char, "CucumberStruggle")
			if s.Struggle then s.Struggle:Play(0.15) end
			showBar(s, holder, struggle)
			local tEnd = os.clock() + struggle
			while os.clock() < tEnd and not s.Done do
				RunService.Heartbeat:Wait()
			end
			if s.Struggle then s.Struggle:Stop(0.15) end
			if s.Bar then
				s.Bar:Destroy()
				s.Bar = nil
			end
			if s.Done then return end
		end
		if payload.Kind == "Tug" then
			finish(s)
			return
		end
		--.. bend, grip, lift, stand up (the server swaps the cucumber GRAB_T in)
		s.Clip = trackFor(char, "CucumberPickUp")
		if s.Clip then s.Clip:Play(0.1) end
		local tEnd = os.clock() + PICKUP_LENGTH
		while os.clock() < tEnd and not s.Done do
			RunService.Heartbeat:Wait()
		end
		finish(s)
	end)
end

--.. heavy / weak carry stumble: the load has just left the shoulder (the server re-spawned
--.. it; FallDrop tumbles it); freeze on the spot, wait FALL_AFTER_DROP, then trip -- the
--.. CucumberFall clip from FALL_CLIP_START to the end (no fling; user 2026-09-07)
local function runFall(payload)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if session then finish(session, true) end
	local s = {Fall = true, Char = char}
	session = s
	freezeInput()
	freezeBody(true)
	hum:Move(Vector3.zero, false)
	s.DiedConn = hum.Died:Connect(function()
		finish(s, true)
	end)
	task.spawn(function()
		local tTrip = os.clock() + FALL_AFTER_DROP
		while os.clock() < tTrip and not s.Done do
			RunService.Heartbeat:Wait()
		end
		if s.Done then return end
		s.Clip = trackFor(char, "CucumberFall")
		if s.Clip then
			s.Clip:Play(0.1)
			if FALL_CLIP_START > 0 then s.Clip.TimePosition = FALL_CLIP_START end
		end
		local tEnd = os.clock() + math.max(0.1, FALL_LENGTH - FALL_CLIP_START)
		while os.clock() < tEnd and not s.Done do
			RunService.Heartbeat:Wait()
		end
		finish(s)
	end)
end

AnimRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local holder = payload.Holder
	local who = payload.Player
	if payload.Kind == "Cancel" then
		if payload.CancelAll and who == player and session then holder = session.Holder end
		if holder then stopVisual(holder) end
		if who == player and session and session.Holder == holder then finish(session, true) end
		return
	end
	if payload.Kind == "Fall" then
		if not who then return end
		--.. everyone hears the face-plant (the clip starts FALL_AFTER_DROP after the drop)
		task.delay(FALL_AFTER_DROP + math.max(0, FALL_PLANT_T - FALL_CLIP_START), function()
			local root = who.Character and who.Character:FindFirstChild("HumanoidRootPart")
			if root then pcall(SoundController.PlayFXAt, "Big Thud", root.Position, {Volume = 0.35, MaxLife = 1.2}) end
		end)
		if who == player then runFall(payload) end
		return
	end
	if payload.Kind == "FallDrop" then
		if holder and holder.Parent and typeof(payload.From) == "Vector3" then startTumble(holder, payload.From) end
		return
	end
	if not (holder and holder.Parent and who) then return end
	local struggle = 0
	if payload.Kind == "Tug" then
		struggle = tonumber(payload.Duration) or CucumberStrength.FAIL_TUG
	else
		struggle = tonumber(payload.Struggle) or 0
	end
	startVisual(holder, who, struggle, payload.Kind == "Collect")
	if who == player then runOwn(payload, struggle) end
end)

