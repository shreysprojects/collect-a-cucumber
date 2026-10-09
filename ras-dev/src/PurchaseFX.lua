--[[---------------------------------------DESCRIPTION------------------------------------------
	Purchase effects, ported from the New Map Cucumber Game's ButtonFX (what plays
	when the plot or the bench press is upgraded there), so buying in RAS feels
	the same:

		Press(button)              squash-and-pop 1 -> 0.9 -> 1.07 -> 1 + "Button Pop"
		Success(button)            bigger pop (1.18) + white flash + "Cash Register"
		                           and "Magic Shimmer" together
		Fail(button)               side shake + red flash + "Error"
		Celebrate(gui, text, peak) the bought thing levels up: gui pops (peak, 1.3 by
		                           default) and a gold "UNLOCKED!" floats up out of it
		Burst(character)           a sparkle fountain off the character into the world
		WatchPlayers()             Burst on EVERY player whose owned snowballs /
		                           launchers or rebirths go up by one, so everyone near
		                           the buyer sees it (New Map: the plot level attribute)
		Confirmed(text)            a purchase the SERVER granted (Robux product / pass):
		                           success sounds, a green toast and sparkles. Fired as
		                           the client mode "PurchaseConfirmed" (never from the
		                           client-side Prompt*PurchaseFinished events, which do
		                           not confirm a grant)

	Pops drive Size, not a UIScale: HoverScale already owns each button's UIScale
	slot and two UIScales on one object do not stack. The shake drives Position.
	Both are about a centred anchor (Prepare re-anchors once, keeping the rect).
	Motion is stepped on Heartbeat, not TweenService, so it also plays in an
	unfocused Studio. The floating text is parented to the ScreenGui at the gui's
	absolute centre, so a layout or a clipping ScrollingFrame cannot adopt or cut it.
	The sounds are the New Map ids and volumes: all four are public Creator Store
	audio, so they play in this experience too. Sound objects are built here.

--------------------------------------------------------------------------------------------]]--

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Notify = require(script.Parent.Notify)

local PurchaseFX = {}

PurchaseFX.SOUND_IDS = {
	["Button Pop"] = "rbxassetid://9113263444",
	["Cash Register"] = "rbxassetid://120891770644830",
	["Magic Shimmer"] = "rbxassetid://3199238931",
	["Error"] = "rbxassetid://550209561",
}
PurchaseFX.PRESS_SOUND = { "Button Pop", 0.3 }
PurchaseFX.SUCCESS_SOUNDS = { { "Cash Register", 1.5 }, { "Magic Shimmer", 1.2 } }
PurchaseFX.FAIL_SOUND = { "Error", 1.2 }
PurchaseFX.SOUND_MIN_INTERVAL = 0.05
PurchaseFX.FLOAT_COLOR = Color3.fromRGB(255, 221, 51)
PurchaseFX.FLOAT_STROKE = Color3.fromRGB(82, 62, 10)
PurchaseFX.FLOAT_HEIGHT = 0.3 -- of the source gui's height
PurchaseFX.FLOAT_MIN_PX = 28
PurchaseFX.FLOAT_MAX_PX = 64
PurchaseFX.FLOAT_RISE = 1.25 -- label heights the text floats up
PurchaseFX.SPARK_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 120)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 221, 51)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 255, 140)),
})
PurchaseFX.SPARK_COUNT = 45
PurchaseFX.WATCH_SETTLE = 4 -- s after a player is first seen before gains count (belt and braces)
PurchaseFX.WATCHED = { "UnlockedSnowballs", "UnlockedLaunchers", "Rebirths", "Ascensions" }
PurchaseFX.CONFIRMED_TEXT = "Purchase complete!"

local templates = {}
local lastPlayed = {}
local tokens = setmetatable({}, { __mode = "k" })
local scales = setmetatable({}, { __mode = "k" })
local shakeTokens = setmetatable({}, { __mode = "k" })

local function soundTemplate(name)
	local sound = templates[name]
	if sound then
		return sound
	end
	local id = PurchaseFX.SOUND_IDS[name]
	if not id then
		return nil
	end
	sound = Instance.new("Sound")
	sound.Name = "PurchaseFX_" .. name
	sound.SoundId = id
	templates[name] = sound
	return sound
end

task.spawn(function()
	local list = {}
	for name in PurchaseFX.SOUND_IDS do
		table.insert(list, soundTemplate(name))
	end
	pcall(ContentProvider.PreloadAsync, ContentProvider, list)
end)

-- entry = { name, volume }
function PurchaseFX.Sound(entry)
	if not entry or Players.LocalPlayer:GetAttribute("SFXEnabled") == false then
		return
	end
	local template = soundTemplate(entry[1])
	if not template then
		return
	end
	local now = os.clock()
	if lastPlayed[entry[1]] and now - lastPlayed[entry[1]] < PurchaseFX.SOUND_MIN_INTERVAL then
		return
	end
	lastPlayed[entry[1]] = now

	local sound = template:Clone()
	sound.Volume = entry[2] or 0.5
	sound.SoundGroup = SoundService:FindFirstChild("SFX") -- the Audio module's mix group
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	sound:Play()
end

local function animate(duration, style, direction, fn, alive)
	local t = 0
	while t < 1 do
		local dt = RunService.Heartbeat:Wait()
		if alive and not alive() then
			return false
		end
		t = math.min(t + dt / duration, 1)
		fn(TweenService:GetValue(t, style, direction))
	end
	return true
end
PurchaseFX.Animate = animate

local function layoutManaged(gui)
	local parent = gui.Parent
	return parent ~= nil and parent:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

-- One-time: centre the anchor (same on-screen rect) and remember the rest Size / Position.
function PurchaseFX.Prepare(gui)
	if gui:GetAttribute("FXBaseSize") then
		return
	end
	local anchor = gui.AnchorPoint
	if not layoutManaged(gui) and (anchor.X ~= 0.5 or anchor.Y ~= 0.5) then
		local dx, dy = 0.5 - anchor.X, 0.5 - anchor.Y
		local size, position = gui.Size, gui.Position
		gui.Position = UDim2.new(
			position.X.Scale + size.X.Scale * dx,
			position.X.Offset + size.X.Offset * dx,
			position.Y.Scale + size.Y.Scale * dy,
			position.Y.Offset + size.Y.Offset * dy
		)
		gui.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	gui:SetAttribute("FXBaseSize", gui.Size)
	gui:SetAttribute("FXBasePosition", gui.Position)
end

local function scaledSize(base, k)
	return UDim2.new(base.X.Scale * k, base.X.Offset * k, base.Y.Scale * k, base.Y.Offset * k)
end

-- steps = { { scale, seconds, style?, direction? }, ... }; a newer sequence cancels the running one.
function PurchaseFX.PopSequence(gui, steps)
	if not (gui and gui:IsA("GuiObject")) then
		return
	end
	PurchaseFX.Prepare(gui)
	local base = gui:GetAttribute("FXBaseSize")
	local token = (tokens[gui] or 0) + 1
	tokens[gui] = token
	local function alive()
		return gui.Parent ~= nil and tokens[gui] == token
	end
	task.spawn(function()
		for _, step in steps do
			local from = scales[gui] or 1
			local finished = animate(step[2], step[3] or Enum.EasingStyle.Quad, step[4] or Enum.EasingDirection.Out, function(a)
				local k = from + (step[1] - from) * a
				scales[gui] = k
				gui.Size = scaledSize(base, k)
			end, alive)
			if not finished then
				return
			end
		end
		scales[gui] = 1
		gui.Size = base
	end)
end

-- A coloured sheet over the gui that fades out (keeps its rounded corners).
function PurchaseFX.Flash(gui, color, peakTransparency, duration)
	if not (gui and gui:IsA("GuiObject") and gui.Parent) then
		return
	end
	local sheet = Instance.new("Frame")
	sheet.Name = "FXFlash"
	sheet.BackgroundColor3 = color
	sheet.BackgroundTransparency = peakTransparency
	sheet.BorderSizePixel = 0
	sheet.Size = UDim2.fromScale(1, 1)
	sheet.ZIndex = gui.ZIndex + 5
	local corner = gui:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = sheet
	end
	sheet.Parent = gui
	task.spawn(function()
		animate(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			sheet.BackgroundTransparency = peakTransparency + (1 - peakTransparency) * a
		end, function()
			return sheet.Parent ~= nil
		end)
		sheet:Destroy()
	end)
end

function PurchaseFX.Press(button)
	PurchaseFX.Sound(PurchaseFX.PRESS_SOUND)
	PurchaseFX.PopSequence(button, {
		{ 0.9, 0.05 },
		{ 1.07, 0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out },
		{ 1, 0.1 },
	})
end

function PurchaseFX.Success(button)
	for _, entry in PurchaseFX.SUCCESS_SOUNDS do
		PurchaseFX.Sound(entry)
	end
	PurchaseFX.Flash(button, Color3.new(1, 1, 1), 0.15, 0.4)
	PurchaseFX.PopSequence(button, {
		{ 1.18, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out },
		{ 1, 0.2 },
	})
end

function PurchaseFX.Fail(button)
	PurchaseFX.Sound(PurchaseFX.FAIL_SOUND)
	if not (button and button:IsA("GuiObject")) then
		return
	end
	PurchaseFX.Flash(button, Color3.fromRGB(255, 70, 70), 0.55, 0.35)
	if layoutManaged(button) then
		return
	end
	PurchaseFX.Prepare(button)
	local base = button:GetAttribute("FXBasePosition") or button.Position
	local token = (shakeTokens[button] or 0) + 1
	shakeTokens[button] = token
	task.spawn(function()
		animate(0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, function(a)
			local amplitude = 7 * (1 - a)
			button.Position = base + UDim2.fromOffset(math.sin(a * math.pi * 6) * amplitude, 0)
		end, function()
			return button.Parent ~= nil and shakeTokens[button] == token
		end)
		if shakeTokens[button] == token then
			button.Position = base
		end
	end)
end

-- Gold text that pops out of the gui's centre and floats up while fading.
function PurchaseFX.FloatText(gui, text)
	local screen = gui and gui:FindFirstAncestorWhichIsA("LayerCollector")
	if not screen then
		return
	end
	local size = gui.AbsoluteSize
	local center = gui.AbsolutePosition + size * 0.5 - screen.AbsolutePosition
	local height = math.clamp(size.Y * PurchaseFX.FLOAT_HEIGHT, PurchaseFX.FLOAT_MIN_PX, PurchaseFX.FLOAT_MAX_PX)

	local label = Instance.new("TextLabel")
	label.Name = "FXFloatText"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(center.X, center.Y)
	label.Size = UDim2.fromOffset(math.max(size.X * 1.2, height * 5), height)
	label.Rotation = -6
	label.ZIndex = 60
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text or "UNLOCKED!"
	label.TextColor3 = PurchaseFX.FLOAT_COLOR
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = math.clamp(height * 0.08, 2, 5)
	stroke.Color = PurchaseFX.FLOAT_STROKE
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	label.Parent = screen

	local rise = height * PurchaseFX.FLOAT_RISE
	task.spawn(function()
		animate(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
			scale.Scale = 0.4 + 0.75 * a
		end)
		animate(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			scale.Scale = 1.15 - 0.15 * a
			label.Position = UDim2.fromOffset(center.X, center.Y - rise * a)
			local fade = a * a
			label.TextTransparency = fade
			stroke.Transparency = fade
		end)
		label:Destroy()
	end)
end

function PurchaseFX.Celebrate(gui, text, peak)
	if not (gui and gui:IsA("GuiObject") and gui.Parent) then
		return
	end
	PurchaseFX.PopSequence(gui, {
		{ peak or 1.3, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out },
		{ 1, 0.22 },
	})
	PurchaseFX.FloatText(gui, text)
end

function PurchaseFX.Burst(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PurchaseSparks"
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = PurchaseFX.SPARK_COLOR
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Speed = NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.Drag = 2
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.6, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Enabled = false
	emitter.Parent = attachment
	attachment.Parent = root
	emitter:Emit(PurchaseFX.SPARK_COUNT)
	task.delay(2.5, function()
		attachment:Destroy()
	end)
end

-- Owned names are a comma list; Rebirths is a number. nil = not replicated yet (profile loading).
local function measure(value)
	if type(value) == "number" then
		return value
	end
	if type(value) ~= "string" then
		return nil
	end
	local count = 0
	for token in string.gmatch(value, "[^,]+") do
		if string.match(token, "%S") then
			count += 1
		end
	end
	return count
end

local watching = false
local watchers = {}

local function watchPlayer(player)
	if watchers[player] then
		return
	end
	local firstSeen = os.clock()
	local seen = {}
	local connections = {}
	watchers[player] = connections
	for _, name in PurchaseFX.WATCHED do
		seen[name] = measure(player:GetAttribute(name))
		table.insert(connections, player:GetAttributeChangedSignal(name):Connect(function()
			local now = measure(player:GetAttribute(name))
			local before = seen[name]
			seen[name] = now
			-- The first value (nil -> "Classic", nil -> 1 rebirth) is the profile load, not a purchase.
			if before and now and now == before + 1 and os.clock() - firstSeen > PurchaseFX.WATCH_SETTLE then
				PurchaseFX.Burst(player.Character)
			end
		end))
	end
end

function PurchaseFX.WatchPlayers()
	if watching then
		return
	end
	watching = true
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		for _, connection in watchers[player] or {} do
			connection:Disconnect()
		end
		watchers[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

function PurchaseFX.Confirmed(text)
	for _, entry in PurchaseFX.SUCCESS_SOUNDS do
		PurchaseFX.Sound(entry)
	end
	Notify.Success(if type(text) == "string" and text ~= "" then text else PurchaseFX.CONFIRMED_TEXT)
	PurchaseFX.Burst(Players.LocalPlayer.Character)
end

return PurchaseFX
