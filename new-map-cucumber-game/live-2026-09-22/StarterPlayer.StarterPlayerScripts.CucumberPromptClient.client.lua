--[[
	CucumberPromptClient  (LocalScript, StarterPlayerScripts)
	Custom ProximityPrompt look for every prompt with Style = Custom (the cucumber
	"Lift" prompts from CucumberCarry): no panel -- a translucent rounded key badge on the
	left ("E", the gamepad button, or TAP on touch) and, to its right, two left-aligned lines
	in the default Roblox prompt's look (2026-09-18, user: "make it look like this"): the
	ObjectText small ("Cucumber") above the ActionText in bold with the cucumber's SHOWN WEIGHT
	after it -- "Lift (1.1 kg)" (user 2026-09-18: "put the X kg beside the Lift label"), the
	"(1.1 kg)" in the difficulty colour (CucumberLift.Difficulty / COLORS: green lift it, yellow
	work for it, orange extreme, red too heavy; 1 kg asks for 1 Strength). SIZED IN STUDS like the owner badge (2026-09-18, user: "doesn't scale up when
	the camera moves away, the same size no matter the position"): the px layout is HEIGHT_STUDS
	tall in the world and shrinks with distance like any object. It floats at the PLAYER'S TORSO
	HEIGHT over the cucumber (user: "bring the prompt to user torso height"). Pops in / out; while
	the key is held a green fill rises from the bottom of the badge over the prompt's HoldDuration
	(clipped to the rounded corners by a CanvasGroup), and the badge itself is a button so touch /
	mouse can hold it (InputHoldBegin / End).
	2026-09-16: the weight replaces the old hidden strength requirement (user: "list how
	much kg each cucumber is instead of how much strength it requires").
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local CucumberLift = require(Modules:WaitForChild("CucumberLift"))
local CucumberMutations = require(Modules:WaitForChild("CucumberMutations"))
local playerGui = player:WaitForChild("PlayerGui")

--..Look..--
local BADGE = 44 -- px, the rounded key square
local WIDTH, HEIGHT = 150, 66 -- the layout in px (WIDTH = the minimum: fitWidth hugs the labels); the whole thing is then sized in STUDS (below)
local PAD = 10 -- px inside the layout: left of the badge, between the badge and the text, right of the text
local OBJECT_SIZE, ACTION_SIZE = 16, 24
--.. sized in studs (2026-09-18, user: "doesn't scale up when bringing the camera further, keep it the same size no
--.. matter the position" = the owner-badge rule, overhead UIs in studs): the HEIGHT-px layout is HEIGHT_STUDS tall
--.. in the world; one UIScale maps the px layout onto the stud-sized billboard every frame (fit x the press animation)
local HEIGHT_STUDS = 2.0 -- 1.1 read tiny once the camera backed off (user 2026-09-18: "gets smaller as you go further")
local STUDS_PER_PX = HEIGHT_STUDS / HEIGHT
--.. and the on-screen height is held inside MIN_PX .. MAX_PX (px, before the press animation): far away it stops
--.. shrinking, close up it stops growing -- "the same size no matter the position" over the whole play range,
--.. still anchored to the world (and at the cucumber's scale) in between, like the plot owner badge reads
local MIN_PX, MAX_PX = 56, 120
local OUTLINE = Color3.fromRGB(22, 24, 30)
local BADGE_FILL = Color3.fromRGB(28, 30, 36)
local BADGE_HELD = Color3.fromRGB(96, 200, 90)
local FONT_OBJECT = Enum.Font.GothamMedium
local FONT_ACTION = Enum.Font.GothamBold -- the reference's bold action line and key (was FredokaOne until 2026-09-18)

local GAMEPAD_GLYPH = {
	[Enum.KeyCode.ButtonA] = "A", [Enum.KeyCode.ButtonB] = "B", [Enum.KeyCode.ButtonX] = "X", [Enum.KeyCode.ButtonY] = "Y",
	[Enum.KeyCode.ButtonL1] = "LB", [Enum.KeyCode.ButtonR1] = "RB", [Enum.KeyCode.ButtonL2] = "LT", [Enum.KeyCode.ButtonR2] = "RT",
}

local function keyLabel(prompt, inputType)
	if inputType == Enum.ProximityPromptInputType.Touch then return "TAP", 13 end
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return GAMEPAD_GLYPH[prompt.GamepadKeyCode] or "X", 20
	end
	local ok, text = pcall(UserInputService.GetStringForKeyCode, UserInputService, prompt.KeyboardKeyCode)
	text = (ok and text ~= "" and text) or prompt.KeyboardKeyCode.Name
	return text:upper(), #text > 2 and 14 or 22
end

local function outlined(label, thickness)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = OUTLINE
	s.Transparency = 0.15
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = label
	return s
end

local Active = {} -- [prompt] = {Gui, Anim, Loop, Conns}

local function strengthOf()
	local data = player:FindFirstChild("Data")
	local strength = data and data:FindFirstChild("Strength")
	return strength and tonumber(strength.Value) or 0
end

local function build(prompt, inputType)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CustomPrompt"
	gui.Size = UDim2.new(WIDTH * STUDS_PER_PX, 0, HEIGHT_STUDS, 0) -- studs
	gui.AlwaysOnTop = true
	gui.Active = true
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = false
	gui.Adornee = prompt.Parent
	--.. at the player's torso height, over the cucumber's part (2026-09-18, user: "bring the prompt to user torso
	--.. height"): the vertical offset follows the character every frame (placeAtTorso), the XZ stays on the part --
	--.. a giant's top edge no longer throws the badge off the top of the screen either
	local adornee = prompt.Parent
	gui.ExtentsOffsetWorldSpace = Vector3.zero
	gui.StudsOffsetWorldSpace = Vector3.zero
	local function placeAtTorso()
		local char = player.Character
		local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart"))
		if torso and adornee and adornee:IsA("BasePart") then
			gui.StudsOffsetWorldSpace = Vector3.new(0, torso.Position.Y - adornee.Position.Y, 0)
		end
	end
	placeAtTorso()
	gui.SizeOffset = Vector2.new(prompt.UIOffset.X / WIDTH, -prompt.UIOffset.Y / HEIGHT)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1 -- no panel behind the prompt (user 2026-09-18: "remove the background behind the prompt")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(WIDTH, HEIGHT) -- the px layout box; the UIScale below maps it onto the stud-sized billboard
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = root
	--.. one UIScale (they do not stack): the distance fit x the press / pop animation value, applied every frame
	local anim = Instance.new("NumberValue")
	anim.Name = "Anim"
	anim.Value = 0.7
	anim.Parent = root
	local loop = RunService.RenderStepped:Connect(function()
		placeAtTorso()
		local px = gui.AbsoluteSize.Y
		local fit = (px > 0 and math.clamp(px, MIN_PX, MAX_PX) or MIN_PX) / HEIGHT
		scale.Scale = anim.Value * fit
	end)

	local badge = Instance.new("TextButton")
	badge.Name = "Badge"
	badge.AutoButtonColor = false
	badge.Text = ""
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, PAD, 0.5, 0)
	badge.Size = UDim2.fromOffset(BADGE, BADGE)
	badge.BackgroundColor3 = BADGE_FILL
	badge.BackgroundTransparency = 0.35
	badge.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 11)
	corner.Parent = badge
	local ring = Instance.new("UIStroke")
	ring.Thickness = 1.5
	ring.Color = Color3.fromRGB(235, 235, 240)
	ring.Transparency = 0.45
	ring.Parent = badge

	--.. rising hold fill, clipped to the badge's rounded corners
	local clip = Instance.new("CanvasGroup")
	clip.Name = "FillClip"
	clip.BackgroundTransparency = 1
	clip.Size = UDim2.fromScale(1, 1)
	clip.ZIndex = 1
	clip.Parent = badge
	local clipCorner = Instance.new("UICorner")
	clipCorner.CornerRadius = UDim.new(0, 11)
	clipCorner.Parent = clip
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = BADGE_HELD
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = clip

	local keyText, keySize = keyLabel(prompt, inputType)
	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.BackgroundTransparency = 1
	key.Size = UDim2.fromScale(1, 1)
	key.Font = FONT_ACTION
	key.TextSize = keySize
	key.TextColor3 = Color3.fromRGB(255, 255, 255)
	key.Text = keyText
	key.ZIndex = 3
	key.Parent = badge

	local object = Instance.new("TextLabel")
	object.Name = "ObjectText"
	object.BackgroundTransparency = 1
	object.Position = UDim2.fromOffset(PAD + BADGE + PAD, 7)
	object.Size = UDim2.new(1, -(PAD + BADGE + PAD + PAD), 0, OBJECT_SIZE + 4) -- the text column: PAD in from the badge and from the right edge
	object.Font = FONT_OBJECT
	object.TextSize = OBJECT_SIZE
	object.TextColor3 = Color3.fromRGB(255, 255, 255)
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextYAlignment = Enum.TextYAlignment.Bottom
	object.Text = prompt.ObjectText
	object.Parent = root
	outlined(object, 1.2)

	local action = Instance.new("TextLabel")
	action.Name = "ActionText"
	action.BackgroundTransparency = 1
	action.Position = UDim2.fromOffset(PAD + BADGE + PAD, OBJECT_SIZE + 12)
	action.Size = UDim2.new(1, -(PAD + BADGE + PAD + PAD), 0, ACTION_SIZE + 6)
	action.Font = FONT_ACTION
	action.TextSize = ACTION_SIZE
	action.TextColor3 = Color3.fromRGB(255, 255, 255)
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.TextYAlignment = Enum.TextYAlignment.Top
	action.Text = prompt.ActionText
	action.Parent = root
	outlined(action, 1.6)

	local conns = {}
	object.RichText = true
	action.RichText = true -- "Lift (1.1 kg)": the kg span carries its own colour and a smaller size
	object.TextTruncate = Enum.TextTruncate.None -- the whole name shows ("Diamond NEON FROZEN Sun-Baked Cucumber"): the billboard widens to fit
	local function refreshText()
		object.Text = CucumberMutations.ColorizeName(prompt.ObjectText)
		local holder = prompt.Parent
		while holder and holder ~= workspace and holder:GetAttribute("WeightKg") == nil do holder = holder.Parent end
		if holder and holder ~= workspace then
			local kg = CucumberLift.Of(holder)
			local _band, color, _text, row = CucumberLift.Difficulty(CucumberLift.Ratio(strengthOf(), kg))
			action.TextColor3 = Color3.fromRGB(255, 255, 255)
			--.. "Lift (1.1 kg)" (2026-09-18, user: "put the X kg beside the Lift label"): the SHOWN weight (CucumberLift.Shown:
			--.. lower, off-curve, never the requirement -- user 2026-09-17: "mystery") after the action, a size smaller, in the
			--.. difficulty colour (CucumberLift.COLORS: green lift it, yellow work for it, orange extreme, red too heavy). The
			--.. name line is just the name -- no tags (user 2026-09-16: no "Slippery" / "Bouncy")
			action.Text = prompt.ActionText .. string.format(' <font size="%d" color="#%s">(%s)</font>', OBJECT_SIZE + 2, color:ToHex(), CucumberLift.Format(CucumberLift.ShownOf(holder)))
		else
			--.. not a cucumber (the Build prompt on the plot board, ...): plain labels
			action.Text = prompt.ActionText
			action.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end
	--.. width to fit the longest label (TextBounds settles once the gui is on screen): the px layout box and the
	--.. stud-sized billboard grow together, so the badge + text block just widens to the right
	local function fitWidth()
		local needed = math.max(WIDTH, math.ceil(PAD + BADGE + PAD + math.max(object.TextBounds.X, action.TextBounds.X) + PAD)) -- PAD, badge, PAD, the wider line, PAD
		root.Size = UDim2.fromOffset(needed, HEIGHT)
		gui.Size = UDim2.new(needed * STUDS_PER_PX, 0, HEIGHT_STUDS, 0)
	end
	local refreshAt = 0
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		refreshAt += dt
		if refreshAt >= 0.25 then
			refreshAt = 0
			refreshText()
		end
	end))
	refreshText()
	table.insert(conns, prompt:GetPropertyChangedSignal("ObjectText"):Connect(refreshText))
	table.insert(conns, prompt:GetPropertyChangedSignal("ActionText"):Connect(refreshText))
	table.insert(conns, object:GetPropertyChangedSignal("TextBounds"):Connect(fitWidth))
	table.insert(conns, action:GetPropertyChangedSignal("TextBounds"):Connect(fitWidth))

	--.. the badge doubles as the touch / mouse hold button
	local holding = false
	table.insert(conns, badge.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holding = true
			prompt:InputHoldBegin()
		end
	end))
	table.insert(conns, badge.InputEnded:Connect(function(input)
		if holding and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			holding = false
			prompt:InputHoldEnd()
		end
	end))

	--.. hold feedback: the green fill rises bottom-to-top over the hold, and the
	--.. badge shrinks a touch; letting go drains it back down (anim = the press / pop factor of the UIScale)
	local fillTween
	table.insert(conns, prompt.PromptButtonHoldBegan:Connect(function()
		if fillTween then fillTween:Cancel() end
		fill.Size = UDim2.fromScale(1, 0)
		fillTween = TweenService:Create(fill, TweenInfo.new(math.max(0.05, prompt.HoldDuration), Enum.EasingStyle.Linear), {Size = UDim2.fromScale(1, 1)})
		fillTween:Play()
		TweenService:Create(anim, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Value = 0.92}):Play()
	end))
	table.insert(conns, prompt.PromptButtonHoldEnded:Connect(function()
		if fillTween then fillTween:Cancel() end
		fillTween = TweenService:Create(fill, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromScale(1, 0)})
		fillTween:Play()
		TweenService:Create(anim, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Value = 1}):Play()
	end))
	table.insert(conns, prompt.Triggered:Connect(function()
		if fillTween then fillTween:Cancel() end
		fill.Size = UDim2.fromScale(1, 1)
		TweenService:Create(anim, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Value = 1.15}):Play()
	end))

	gui.Parent = playerGui
	TweenService:Create(anim, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Value = 1}):Play()
	return {Gui = gui, Anim = anim, Loop = loop, Conns = conns}
end

local function hide(prompt)
	local entry = Active[prompt]
	if not entry then return end
	Active[prompt] = nil
	for _, c in ipairs(entry.Conns) do c:Disconnect() end
	local gui = entry.Gui
	local tween = TweenService:Create(entry.Anim, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Value = 0.7})
	tween.Completed:Once(function()
		entry.Loop:Disconnect()
		gui:Destroy()
	end)
	tween:Play()
end

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end
	hide(prompt)
	Active[prompt] = build(prompt, inputType)
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	hide(prompt)
end)
