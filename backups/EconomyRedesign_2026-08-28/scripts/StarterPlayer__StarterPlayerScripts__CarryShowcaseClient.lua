--[[
	CarryShowcaseClient (2026-08-26)
	Center-screen catch showcase: "NEW CUCUMBER PICKED UP!" (FredokaOne,
	white), a spinning viewport of the cucumber now on your arm, and its
	combined luck "[1 IN X]" in gold -- X folds the cucumber's spawn share
	and its catch-on-break odds together, computed server-side in
	CarryService.TryAwardFromBreak. Replaces the old green Notif toasts for
	both fresh grabs and rarity swaps. Pops with SFX 131390520971848,
	honoring the SFX setting exactly the way SoundController does.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")
local SettingsController = ControllerLoader.GetController("SettingsController")
local SoundController = ControllerLoader.GetController("SoundController")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SFX_ID = "rbxassetid://131390520971848"
local HOLD = 3.6 -- seconds on screen before the pop-out
local GOLD = Color3.fromRGB(255, 204, 45)
local STROKE = Color3.fromRGB(25, 20, 35)
local OUTLINE_SCALE = 1.12 -- silhouette dilation = stroke thickness
local OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)

--.. ===== gui, built once =====
local gui = Instance.new("ScreenGui")
gui.Name = "CarryShowcase"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40 -- over the HUD, under the intro-cutscene cover (99)
gui.Enabled = false
gui.Parent = playerGui

local cluster = Instance.new("Frame")
cluster.Name = "Cluster"
cluster.BackgroundTransparency = 1
cluster.AnchorPoint = Vector2.new(0.5, 0.5)
cluster.Position = UDim2.fromScale(0.5, 0.42)
cluster.Size = UDim2.fromOffset(440, 320)
cluster.Parent = gui

local popScale = Instance.new("UIScale")
popScale.Name = "PopScale"
popScale.Parent = cluster

local function label(name, y, h, color)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0, y)
	t.Size = UDim2.fromOffset(440, h)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeColor3 = STROKE
	t.TextStrokeTransparency = 0.1
	t.Parent = cluster
	return t
end

local title = label("Title", 0, 50, Color3.fromRGB(255, 255, 255))
title.Text = "NEW CUCUMBER PICKED UP!"

local viewport = Instance.new("ViewportFrame")
viewport.Name = "CucumberView"
viewport.BackgroundTransparency = 1
viewport.AnchorPoint = Vector2.new(0.5, 0)
viewport.Position = UDim2.new(0.5, 0, 0, 58)
viewport.Size = UDim2.fromOffset(190, 190)
viewport.Ambient = Color3.fromRGB(200, 200, 200)
viewport.LightColor = Color3.fromRGB(255, 255, 255)
viewport.Parent = cluster

--.. silhouette outline: a second viewport UNDER CucumberView shows a slightly
--.. enlarged flat-white clone through the SAME orbiting camera -- reads as a
--.. sticker stroke around the cucumber itself (a UIStroke only outlines the
--.. frame rectangle, and Highlights don't render inside ViewportFrames)
viewport.ZIndex = 2
local outlineView = Instance.new("ViewportFrame")
outlineView.Name = "CucumberOutline"
outlineView.BackgroundTransparency = 1
outlineView.AnchorPoint = viewport.AnchorPoint
outlineView.Position = viewport.Position
outlineView.Size = viewport.Size
outlineView.ZIndex = 1
outlineView.Parent = cluster

local odds = label("Odds", 256, 44, GOLD)
odds.Text = ""

--.. ===== showcase machinery =====
local currentToken = 0
local spinConn

local function comma(n)
	local s = tostring(math.floor(math.max(1, tonumber(n) or 1)))
	s = s:reverse():gsub("(%d%d%d)", "%1,")
	s = s:reverse():gsub("^,", "")
	return s
end

local function stopSpin()
	if spinConn then
		spinConn:Disconnect()
		spinConn = nil
	end
end

--.. same centering trick as the Store's pet previews: pivot the bounding-box
--.. center onto the origin, then orbit the camera around it
local function fillViewport(model)
	stopSpin()
	viewport:ClearAllChildren()
	outlineView:ClearAllChildren()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	outlineView.CurrentCamera = camera
	model:PivotTo(CFrame.new())
	local bounds, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + -bounds.Position)
	--.. sticker outline: flat-white copy of the (now origin-centred) model,
	--.. dilated about the origin so a uniform rim shows on every side
	local outline = model:Clone()
	for _, d in ipairs(outline:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Transparency > 0.9 then
				d.Transparency = 1 -- invisible helpers (hitboxes) cast no outline
			else
				d.Transparency = 0
				d.Material = Enum.Material.Neon
				d.Color = OUTLINE_COLOR
				if d:IsA("MeshPart") then d.TextureID = "" end
				d.CFrame = d.CFrame.Rotation + d.Position * OUTLINE_SCALE
				d.Size = d.Size * OUTLINE_SCALE
			end
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
			d.VertexColor = Vector3.new(1, 1, 1)
			if d.MeshType == Enum.MeshType.FileMesh then
				d.Scale = d.Scale * OUTLINE_SCALE
			end
		elseif d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") then
			d:Destroy()
		end
	end
	outline.Parent = outlineView
	--.. frame the WORST-CASE orbit angle: the bounding box's half-DIAGONAL
	--.. (not its longest axis) is what sweeps widest as the camera circles,
	--.. and the outline adds OUTLINE_SCALE on top -- the old radius*1.6
	--.. framing cropped long cucumbers at the viewport edges. 5% margin.
	local radius = math.max(size.Magnitude * 0.5, 0.5)
	local dist = (radius * OUTLINE_SCALE * 1.05) / math.tan(math.rad(camera.FieldOfView * 0.5))
	local baseCam = CFrame.lookAt(Vector3.new(0, dist * 0.25, dist), Vector3.new(0, 0, 0))
	camera.CFrame = baseCam
	model.Parent = viewport
	local angle = 0
	spinConn = RunService.RenderStepped:Connect(function(dt)
		angle += dt * 1.2
		camera.CFrame = CFrame.Angles(0, angle, 0) * baseCam
	end)
end

--.. ===== pickup arc (SFX pass 2026-08-26): a glowing mote flies from the
--.. break point to your shoulder just before the showcase pops =====
local function bezier(p0, p1, p2, t)
	local a = p0:Lerp(p1, t)
	local b = p1:Lerp(p2, t)
	return a:Lerp(b, t)
end

local function pickupArc(fromPos)
	if typeof(fromPos) ~= "Vector3" then return end
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart"))
	if not torso then return end

	SoundController.PlayFX("Magic Zoom", {Volume = 0.5})

	local mote = Instance.new("Part")
	mote.Name = "CarryPickupMote"
	mote.Shape = Enum.PartType.Ball
	mote.Size = Vector3.new(0.7, 0.7, 0.7)
	mote.Material = Enum.Material.Neon
	mote.Color = Color3.fromRGB(120, 255, 120)
	mote.Anchored = true
	mote.CanCollide = false
	mote.CanQuery = false
	mote.CanTouch = false
	mote.CastShadow = false
	mote.CFrame = CFrame.new(fromPos)
	local a0 = Instance.new("Attachment") a0.Position = Vector3.new(0, 0.2, 0) a0.Parent = mote
	local a1 = Instance.new("Attachment") a1.Position = Vector3.new(0, -0.2, 0) a1.Parent = mote
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(150, 255, 150))
	trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1)})
	trail.Lifetime = 0.2
	trail.LightEmission = 0.7
	trail.WidthScale = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2)})
	trail.Parent = mote
	mote.Parent = workspace

	task.spawn(function()
		local DURATION = 0.35
		local t0 = os.clock()
		local mid = (fromPos + torso.Position) * 0.5 + Vector3.new(0, 9, 0)
		while true do
			local alpha = (os.clock() - t0) / DURATION
			if alpha >= 1 then break end
			local target = torso.Parent and torso.Position or fromPos
			mote.CFrame = CFrame.new(bezier(fromPos, mid, target, alpha))
			RunService.RenderStepped:Wait()
		end
		--.. arrival sparkle burst on the shoulder
		local burst = Instance.new("ParticleEmitter")
		burst.Color = ColorSequence.new(Color3.fromRGB(180, 255, 180), Color3.fromRGB(255, 255, 255))
		burst.LightEmission = 0.8
		burst.Lifetime = NumberRange.new(0.2, 0.4)
		burst.Speed = NumberRange.new(3, 7)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0)})
		burst.Parent = a0
		if torso.Parent then mote.CFrame = CFrame.new(torso.Position) end
		mote.Transparency = 1
		burst:Emit(10)
		task.wait(0.5)
		mote:Destroy()
	end)
end

--.. light full-screen gold confetti for 1-in-1000+ jackpot catches
local function goldConfetti()
	local cg = Instance.new("ScreenGui")
	cg.Name = "CarryConfetti"
	cg.IgnoreGuiInset = true
	cg.DisplayOrder = 41
	cg.ResetOnSpawn = false
	cg.Parent = playerGui
	for i = 1, 26 do
		local fleck = Instance.new("Frame")
		fleck.BorderSizePixel = 0
		fleck.BackgroundColor3 = (i % 3 == 0) and Color3.fromRGB(255, 236, 140) or GOLD
		fleck.Size = UDim2.fromOffset(math.random(6, 12), math.random(8, 16))
		fleck.Position = UDim2.new(math.random(), 0, 0, -40 - math.random(0, 120))
		fleck.Rotation = math.random(0, 359)
		fleck.Parent = cg
		TweenService:Create(fleck, TweenInfo.new(1.4 + math.random() * 0.9, Enum.EasingStyle.Linear), {
			Position = UDim2.new(math.clamp(fleck.Position.X.Scale + (math.random() - 0.5) * 0.15, 0, 1), 0, 1, 60);
			Rotation = fleck.Rotation + math.random(120, 420);
		}):Play()
	end
	task.delay(2.6, function() cg:Destroy() end)
end

local function show(payload)
	currentToken += 1
	local token = currentToken

	title.Text = payload.Upgraded and "UPGRADED!" or "NEW CUCUMBER PICKED UP!"
	odds.Text = ("[1 IN %s]"):format(comma(payload.OneIn))

	--.. the arm model may replicate a beat after the event: wait briefly,
	--.. then mirror it into the viewport (welds off, anchored -- it's a prop)
	task.spawn(function()
		local char = player.Character
		local model = char and char:WaitForChild("CarriedCucumber", 2)
		if token ~= currentToken then return end
		if model then
			local clone = model:Clone()
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
				elseif d:IsA("WeldConstraint") then
					d:Destroy()
				end
			end
			fillViewport(clone)
		else
			stopSpin()
			viewport:ClearAllChildren()
			outlineView:ClearAllChildren()
		end
	end)

	--.. the break-point mote arcs to the shoulder FIRST (0.35s); the showcase
	--.. pops right as it lands
	pickupArc(payload.Position)

	--.. 1-in-1000+ catches hold longer on screen and rain gold confetti
	local jackpot = (tonumber(payload.OneIn) or 0) >= 1000
	local hold = jackpot and (HOLD + 1.6) or HOLD

	task.delay(0.3, function()
		if token ~= currentToken then return end
		gui.Enabled = true
		popScale.Scale = 0.55
		TweenService:Create(popScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		if jackpot then goldConfetti() end

		if payload.Upgraded then
			--.. rarity swap gets its own celebratory sting instead of the pickup pop
			--.. Magic Shimmer, NOT Star Sting (2026-08-26, user): the sting is
			--.. reserved for combo milestones/crits, and this swap fires
			--.. organically mid-smash -- it read as the milestone effect at random
			SoundController.PlayFX("Magic Shimmer", {Speed = 1.2, Volume = 0.6})
		elseif SettingsController.ValidateSetting("SFX", false) then
			--.. pickup sting, gated on the user's SFX setting the same way
			--.. SoundController.PlayerSoundClient gates every other effect
			local sfx = Instance.new("Sound")
			sfx.SoundId = SFX_ID
			sfx.Volume = 0.7
			sfx.Parent = SoundService
			sfx:Play()
			sfx.Ended:Once(function() sfx:Destroy() end)
			task.delay(6, function()
				if sfx.Parent then sfx:Destroy() end
			end)
		end
	end)

	task.delay(0.3 + hold, function()
		if token ~= currentToken then return end
		local out = TweenService:Create(popScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.55})
		out.Completed:Once(function()
			if token ~= currentToken then return end
			gui.Enabled = false
			stopSpin()
			viewport:ClearAllChildren()
			outlineView:ClearAllChildren()
		end)
		out:Play()
	end)
end

Network:BindEvents({
	CarryShowcase = function(payload)
		if type(payload) ~= "table" then return end
		show(payload)
	end,
})

print("[CarryShowcaseClient] catch showcase ready.")
