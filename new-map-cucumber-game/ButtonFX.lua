--[[
	ButtonFX  (ModuleScript, ReplicatedStorage.Modules)
	Client-side "juice" for the upgrade boards (2026-09-07, user: "pop effects on the upgrade buttons
	when clicking them and when the plot / bench press upgrades"). Used by PlotUpgradeClient and
	BenchBoardClient; everything here is local to the viewing client.

	  Prepare(gui)                  one-time: re-anchors the element on its centre (a UIScale scales
	                                about the AnchorPoint) and adds the FXScale UIScale it drives
	  Press(button)                 squash-and-pop (scale 1 -> 0.9 -> 1.07 -> 1) + "Button Pop" click
	  Success(button)               bigger pop + white flash + "Cash Register" / "Magic Shimmer"
	  Fail(button)                  side shake + red flash + "Error"
	  Celebrate(board, levelLabel, text)
	                                the board itself levels up: the level label pops, a gold
	                                "LEVEL UP!" floats up out of it, and a burst of sparkles fires off
	                                the board's Face part into the world. The clients fire it from
	                                the plot attribute change (PlotLevel / BenchLevel +1), so every
	                                player near the board sees it, not only the buyer.
	Animations are stepped on Heartbeat (not TweenService) so they also run in an unfocused Studio.
	Sounds go through SoundController.PlayFX (templates in ReplicatedStorage.Assets.Sounds).
]]
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundController"))

local M = {}
--.. volumes from measured PlaybackLoudness peaks (Button Pop 493, Cash Register 97, Magic Shimmer 88,
--.. Error 89): heard = peak x Volume, aimed at ~100-150 like the Collect / Whoosh cues
M.PRESS_SOUND = {"Button Pop", 0.3}
M.SUCCESS_SOUNDS = {{"Cash Register", 1.5}, {"Magic Shimmer", 1.2}}
M.FAIL_SOUND = {"Error", 1.2}
M.LEVEL_UP_COLOR = Color3.fromRGB(255, 221, 51)
M.LEVEL_UP_STROKE = Color3.fromRGB(82, 62, 10)
M.SPARK_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 120));
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 221, 51));
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 255, 140));
})
M.SPARK_COUNT = 45
M.FLOAT_RISE = 70 -- px the "LEVEL UP!" text floats up (board canvas is 800 x 600)

local function Sound(entry)
	if not entry then return end
	pcall(SoundController.PlayFX, entry[1], {Volume = entry[2], Key = "ButtonFX:" .. entry[1], MinInterval = 0.05})
end
M.Sound = Sound

--.. Heartbeat-stepped ease: fn(alpha) every frame until done, or until alive() says stop
local function Animate(duration, style, direction, fn, alive)
	local t = 0
	while t < 1 do
		local dt = RunService.Heartbeat:Wait()
		if alive and not alive() then return false end
		t = math.min(t + dt / duration, 1)
		fn(TweenService:GetValue(t, style, direction))
	end
	return true
end
M.Animate = Animate

--.. one-time: re-anchor on the centre (so the pop grows from the middle) + the UIScale to drive
function M.Prepare(gui)
	local scale = gui:FindFirstChild("FXScale")
	if scale then return scale end
	local anchor = gui.AnchorPoint
	local shift = Vector2.new(0.5, 0.5) - anchor
	local size, pos = gui.Size, gui.Position
	gui.Position = UDim2.new(
		pos.X.Scale + size.X.Scale * shift.X, pos.X.Offset + size.X.Offset * shift.X,
		pos.Y.Scale + size.Y.Scale * shift.Y, pos.Y.Offset + size.Y.Offset * shift.Y)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui:SetAttribute("FXBasePosition", gui.Position)
	scale = Instance.new("UIScale")
	scale.Name = "FXScale"
	scale.Parent = gui
	return scale
end

--.. steps = {{targetScale, seconds, style?, direction?}, ...}; a newer sequence cancels the running one
local function PopSequence(gui, steps)
	local scale = M.Prepare(gui)
	local token = (gui:GetAttribute("FXToken") or 0) + 1
	gui:SetAttribute("FXToken", token)
	local function alive() return gui.Parent ~= nil and gui:GetAttribute("FXToken") == token end
	task.spawn(function()
		for _, step in ipairs(steps) do
			local from = scale.Scale
			local finished = Animate(step[2], step[3] or Enum.EasingStyle.Quad, step[4] or Enum.EasingDirection.Out, function(a)
				scale.Scale = from + (step[1] - from) * a
			end, alive)
			if not finished then return end
		end
		scale.Scale = 1
	end)
end
M.PopSequence = PopSequence

--.. a coloured sheet over the element that fades out (keeps the element's rounded corners)
local function Flash(gui, color, peakTransparency, duration)
	local sheet = Instance.new("Frame")
	sheet.Name = "FXFlash"
	sheet.BackgroundColor3 = color
	sheet.BackgroundTransparency = peakTransparency
	sheet.BorderSizePixel = 0
	sheet.Size = UDim2.fromScale(1, 1)
	sheet.ZIndex = gui.ZIndex + 5
	local corner = gui:FindFirstChildOfClass("UICorner")
	if corner then corner:Clone().Parent = sheet end
	sheet.Parent = gui
	task.spawn(function()
		Animate(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			sheet.BackgroundTransparency = peakTransparency + (1 - peakTransparency) * a
		end)
		sheet:Destroy()
	end)
end
M.Flash = Flash

function M.Press(button)
	Sound(M.PRESS_SOUND)
	PopSequence(button, {
		{0.9, 0.05};
		{1.07, 0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out};
		{1, 0.1};
	})
end

function M.Success(button)
	for _, entry in ipairs(M.SUCCESS_SOUNDS) do Sound(entry) end
	Flash(button, Color3.new(1, 1, 1), 0.15, 0.4)
	PopSequence(button, {
		{1.18, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out};
		{1, 0.2};
	})
end

function M.Fail(button)
	Sound(M.FAIL_SOUND)
	Flash(button, Color3.fromRGB(255, 70, 70), 0.55, 0.35)
	M.Prepare(button)
	local base = button:GetAttribute("FXBasePosition") or button.Position
	local token = (button:GetAttribute("FXShake") or 0) + 1
	button:SetAttribute("FXShake", token)
	task.spawn(function()
		Animate(0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, function(a)
			local amplitude = 7 * (1 - a)
			button.Position = base + UDim2.fromOffset(math.sin(a * math.pi * 6) * amplitude, 0)
		end, function() return button.Parent ~= nil and button:GetAttribute("FXShake") == token end)
		if button:GetAttribute("FXShake") == token then button.Position = base end
	end)
end

--.. sparkles off the board's Face part, into the world, in the direction the SurfaceGui faces
local function WorldBurst(board)
	local face = board and board:FindFirstChild("Face")
	if not face or not face:IsA("BasePart") then return end
	local gui = face:FindFirstChildOfClass("SurfaceGui")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FXSparks"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = M.SPARK_COLOR
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0
	emitter.EmissionDirection = gui and gui.Face or Enum.NormalId.Front
	emitter.Speed = NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.Drag = 2
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.6, 0.45), NumberSequenceKeypoint.new(1, 0)})
	emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1)})
	emitter.Enabled = false
	emitter.Parent = face
	emitter:Emit(M.SPARK_COUNT)
	task.delay(2.5, function() emitter:Destroy() end)
end
M.WorldBurst = WorldBurst

--.. gold text that pops out of the level label and floats up while fading
local function FloatText(levelLabel, text)
	local bg = levelLabel.Parent
	if not bg then return end
	local label = Instance.new("TextLabel")
	label.Name = "FXLevelUp"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = levelLabel:GetAttribute("FXBasePosition") or levelLabel.Position
	label.Size = UDim2.new(0.6, 0, 0, 56)
	label.Rotation = -6
	label.ZIndex = levelLabel.ZIndex + 8
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text or "LEVEL UP!"
	label.TextColor3 = M.LEVEL_UP_COLOR
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = M.LEVEL_UP_STROKE
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	label.Parent = bg
	local base = label.Position
	task.spawn(function()
		Animate(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
			scale.Scale = 0.4 + 0.75 * a
		end)
		Animate(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			scale.Scale = 1.15 - 0.15 * a
			label.Position = base - UDim2.fromOffset(0, M.FLOAT_RISE * a)
			local fade = a * a
			label.TextTransparency = fade
			stroke.Transparency = fade
		end)
		label:Destroy()
	end)
end
M.FloatText = FloatText

function M.Celebrate(board, levelLabel, text)
	if levelLabel then
		M.Prepare(levelLabel)
		PopSequence(levelLabel, {
			{1.3, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out};
			{1, 0.22};
		})
		FloatText(levelLabel, text)
	end
	WorldBurst(board)
end

return M
