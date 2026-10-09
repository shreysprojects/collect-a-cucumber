--[[
	CucumberPromptClient  (LocalScript, StarterPlayerScripts)
	Custom ProximityPrompt look for every prompt with Style = Custom (the cucumber
	"Collect" prompts from CucumberCarry): no dark panel -- a translucent rounded key
	badge on the left ("E", the gamepad button, or TAP on touch) and, to its right,
	the ObjectText in small white text above the ActionText in large bold white,
	both with a dark outline. Pops in / out; while the key is held a green fill
	rises from the bottom of the badge over the prompt's HoldDuration (clipped to
	the rounded corners by a CanvasGroup), and the badge itself is a button so
	touch / mouse can hold it (InputHoldBegin / End).
	The strength requirement is HIDDEN (user, 2026-09-06): the prompt shows only the
	cucumber's name (material / mutation words coloured by CucumberMutations) and
	"Collect" -- no number, no colour hint, no "Too heavy!" preview. You find out by
	trying (CucumberCarry answers with a tug + toast, a struggle, or a clean lift).
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local CucumberStrength = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CucumberStrength"))
local playerGui = player:WaitForChild("PlayerGui")
local CucumberMutations = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CucumberMutations"))

--..Look..--
local BADGE = 46 -- px, the rounded key square
local WIDTH, HEIGHT = 270, 86
local OBJECT_SIZE, ACTION_SIZE = 17, 27
local OUTLINE = Color3.fromRGB(22, 24, 30)
local BADGE_FILL = Color3.fromRGB(28, 30, 36)
local BADGE_HELD = Color3.fromRGB(96, 200, 90)
local FONT_OBJECT = Enum.Font.GothamMedium
local FONT_ACTION = Enum.Font.FredokaOne

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

--.. a giant cucumber is tall enough that riding its true top edge throws the badge off the top of
--.. the screen: above this many studs of half-height the lift is measured in studs instead (2026-09-08)
local PROMPT_LIFT_CAP = 8

local Active = {} -- [prompt] = {Gui, Scale, Conns}

local function build(prompt, inputType)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CustomPrompt"
	gui.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	gui.AlwaysOnTop = true
	gui.Active = true
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = false
	gui.Adornee = prompt.Parent
	--.. just above the part's top edge (extents = half-size units), plus the prompt's own px offset
	local adornee = prompt.Parent
	local halfUp = (adornee and adornee:IsA("BasePart")) and adornee.Size.Y * 0.5 or 0
	if halfUp > PROMPT_LIFT_CAP then
		gui.ExtentsOffsetWorldSpace = Vector3.zero
		gui.StudsOffsetWorldSpace = Vector3.new(0, PROMPT_LIFT_CAP + 0.9, 0)
	else
		gui.ExtentsOffsetWorldSpace = Vector3.new(0, 1, 0)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 0.9, 0)
	end
	gui.SizeOffset = Vector2.new(prompt.UIOffset.X / WIDTH, -prompt.UIOffset.Y / HEIGHT)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = root

	local badge = Instance.new("TextButton")
	badge.Name = "Badge"
	badge.AutoButtonColor = false
	badge.Text = ""
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, 4, 0.5, 0)
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
	object.Position = UDim2.fromOffset(BADGE + 14, 4)
	object.Size = UDim2.new(1, -(BADGE + 14), 0, OBJECT_SIZE + 4)
	object.Font = FONT_OBJECT
	object.TextSize = OBJECT_SIZE
	object.TextColor3 = Color3.fromRGB(255, 255, 255)
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextYAlignment = Enum.TextYAlignment.Bottom
	object.Text = prompt.ObjectText
	object.Parent = root
	outlined(object, 1.6)

	local action = Instance.new("TextLabel")
	action.Name = "ActionText"
	action.BackgroundTransparency = 1
	action.Position = UDim2.fromOffset(BADGE + 14, OBJECT_SIZE + 6)
	action.Size = UDim2.new(1, -(BADGE + 14), 0, ACTION_SIZE + 6)
	action.Font = FONT_ACTION
	action.TextSize = ACTION_SIZE
	action.TextColor3 = Color3.fromRGB(255, 255, 255)
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.TextYAlignment = Enum.TextYAlignment.Top
	action.Text = prompt.ActionText
	action.Parent = root
	outlined(action, 2.2)

	--.. live text updates (a prompt can change its labels while shown); the name gets its
	--.. material / mutation colours, nothing about strength is shown (hidden requirement)
 local progress=Instance.new("TextLabel")
 progress.Name,progress.Position,progress.Size="NextTier",UDim2.fromOffset(BADGE+14,62),UDim2.new(1,-(BADGE+14),0,20)
 progress.BackgroundTransparency,progress.Font,progress.TextSize=1,Enum.Font.FredokaOne,15
 progress.TextColor3,progress.TextXAlignment=Color3.fromRGB(255,239,166),Enum.TextXAlignment.Left
 progress.Text="" -- default "Label" must never show (2026-09-11: it did on the Build prompt)
 progress.Parent=root
 outlined(progress,1.5)
	local conns = {}
	object.RichText = true
	object.TextTruncate = Enum.TextTruncate.None -- the whole name shows ("Diamond NEON FROZEN Sun-Baked Cucumber"): the billboard widens to fit
	local function refreshText()
		object.Text = CucumberMutations.ColorizeName(prompt.ObjectText)
		local holder = prompt.Parent
		while holder and holder ~= workspace and holder:GetAttribute("StrengthRequired") == nil do holder = holder.Parent end
		if holder and holder ~= workspace then
			local data = player:FindFirstChild("Data")
			local strength = data and data:FindFirstChild("Strength")
			local band = CucumberStrength.BandFor(CucumberStrength.Ratio(strength and tonumber(strength.Value) or 0, CucumberStrength.Required(holder)))
			local display = CucumberStrength.BAND_LABELS[band.Name]
			action.Text = "Pick up · " .. display.Text
			action.TextColor3 = display.Color
   local trait=holder:GetAttribute("CarryTrait") or "Normal"
   local nextTier,needed=CucumberStrength.NextTier(strength and tonumber(strength.Value) or 0,CucumberStrength.Required(holder))
   local prefix=trait~="Normal" and trait.." · " or ""
   progress.Text=prefix..(nextTier and (CucumberStrength.Format(math.ceil(needed)).." more strength to "..nextTier) or "Comfortable carry!")
   if holder:GetAttribute("RescueOwner")==player.UserId and (holder:GetAttribute("RescueUntil") or 0)>workspace:GetServerTimeNow() then
    action.Text="Rescue pickup!"
    action.TextColor3=Color3.fromRGB(100,235,255)
   end
		else
			--.. not a cucumber (the Build prompt on the plot board, ...): plain labels, no strength row
			action.Text = prompt.ActionText
			action.TextColor3 = Color3.fromRGB(255, 255, 255)
			progress.Text = ""
		end
	end
	--.. width to fit the longer of the two labels (TextBounds settles once the gui is on screen);
	--.. the billboard stays centred on the part, so the badge + text block just grows to the right
	local function fitWidth()
		local needed = BADGE + 14 + math.max(object.TextBounds.X, action.TextBounds.X, progress.TextBounds.X) + 12
		gui.Size = UDim2.fromOffset(math.max(WIDTH, math.ceil(needed)), HEIGHT)
	end
 local refreshAt=0
 table.insert(conns,game:GetService("RunService").Heartbeat:Connect(function(dt)
  refreshAt+=dt
  if refreshAt>=.2 then refreshAt=0 refreshText() end
 end))
 table.insert(conns,progress:GetPropertyChangedSignal("TextBounds"):Connect(fitWidth))
	refreshText()
	local data = player:FindFirstChild("Data")
	local strength = data and data:FindFirstChild("Strength")
	if strength then table.insert(conns, strength.Changed:Connect(refreshText)) end
	table.insert(conns, player.DescendantAdded:Connect(function(value)
		if value.Name == "Strength" and value.Parent.Name == "Data" then
			table.insert(conns, value.Changed:Connect(refreshText))
			refreshText()
		end
	end))
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
	--.. badge shrinks a touch; letting go drains it back down
	local fillTween
	table.insert(conns, prompt.PromptButtonHoldBegan:Connect(function()
		if fillTween then fillTween:Cancel() end
		fill.Size = UDim2.fromScale(1, 0)
		fillTween = TweenService:Create(fill, TweenInfo.new(math.max(0.05, prompt.HoldDuration), Enum.EasingStyle.Linear), {Size = UDim2.fromScale(1, 1)})
		fillTween:Play()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.92}):Play()
	end))
	table.insert(conns, prompt.PromptButtonHoldEnded:Connect(function()
		if fillTween then fillTween:Cancel() end
		fillTween = TweenService:Create(fill, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromScale(1, 0)})
		fillTween:Play()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	end))
	table.insert(conns, prompt.Triggered:Connect(function()
		if fillTween then fillTween:Cancel() end
		fill.Size = UDim2.fromScale(1, 1)
		TweenService:Create(scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.15}):Play()
	end))

	gui.Parent = playerGui
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	return {Gui = gui, Scale = scale, Conns = conns}
end

local function hide(prompt)
	local entry = Active[prompt]
	if not entry then return end
	Active[prompt] = nil
	for _, c in ipairs(entry.Conns) do c:Disconnect() end
	local gui = entry.Gui
	local tween = TweenService:Create(entry.Scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.7})
	tween.Completed:Once(function() gui:Destroy() end)
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

