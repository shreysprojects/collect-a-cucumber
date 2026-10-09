--[[---------------------------------------DESCRIPTION------------------------------------------
	Short on-screen feedback ("Need $120 more", "Coal unlocked!"). Ported from the
	New Map Cucumber Game's Notify: big bold text with a darkened outline of the
	same colour that pops in, holds, then fades.

		Notify.Show(text, color?, seconds?)   red unless a colour is given
		Notify.Error / Success / Info(text, seconds?)

	Up to MAX_STACK messages show at once. The newest sits at POSITION and older
	ones are pushed up by their rendered height; a new one past the cap throws the
	oldest out. POSITION is 91.5 % down: below the Shop / Rebirth panels (their
	Background spans ~19 %..84 % of the screen at any size, it is height-bound by
	its 1.5 aspect), where MainUI's level bar is hidden while a panel is open.

	Notify.AvoidAbove(guiObject) keeps the stack above a HUD element while it shows:
	the HUD registers its bottom dock (the level bar), ClientMain the Stop button and
	ChargeHint its "HOLD TO LAUNCH" label, so a toast never covers them. With all of
	them hidden (a panel is open) the stack falls back to POSITION, below the panels.

	One ScreenGui "PurchaseNotify" (IgnoreGuiInset, DisplayOrder 2000: above the
	launch buttons and race bar at 1000). Text is TextScaled and capped at
	TEXT_HEIGHT of the screen (MAX_TEXT_PX), so a short message is one big line and
	a long one wraps to two lines. Under TextScaled TextSize is meaningless, so the
	stack reads TextBounds. Everything refits when the screen resizes.

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Audio = require(game:GetService("ReplicatedStorage").Assets.Modules.Client.Audio)

local Notify = {}

Notify.COLORS = {
	Error = Color3.fromRGB(240, 58, 58),
	Success = Color3.fromRGB(92, 225, 92),
	Info = Color3.fromRGB(255, 226, 120),
}
Notify.FONT = Enum.Font.FredokaOne
Notify.POSITION = UDim2.fromScale(0.5, 0.915)
Notify.WIDTH = 0.92 -- of the screen; long messages wrap onto a second line
Notify.HEIGHT = 0.15 -- of the screen: room for two lines; the text itself is capped below
Notify.TEXT_HEIGHT = 0.06 -- of the screen: one line of text
Notify.MAX_TEXT_PX = 56
Notify.STROKE_RATIO = 0.1 -- outline thickness as a fraction of the text height
Notify.STROKE_MIN = 2
Notify.STROKE_MAX = 5
Notify.OUTLINE_DARKEN = 0.22
Notify.HOLD = 2
Notify.FADE = 0.35
Notify.POP_FROM = 0.7
Notify.POP_TIME = 0.16
Notify.DISPLAY_ORDER = 2000
Notify.MAX_STACK = 3
Notify.STACK_GAP = 0.012 -- of the screen height
Notify.SHIFT_TIME = 0.12
Notify.AVOID_GAP = 0.012 -- of the screen height between the newest toast and the HUD element it stays above

local gui = nil
local entries = {} -- oldest .. newest: { Label, Stroke, Limit, Scale, Tweens, Placed }
local avoids = {} -- [GuiObject] = connections: HUD elements the stack stays above while they show

local function textPx()
	return math.clamp(gui.AbsoluteSize.Y * Notify.TEXT_HEIGHT, 12, Notify.MAX_TEXT_PX)
end

local function fitEntry(entry)
	local px = textPx()
	entry.Limit.MaxTextSize = math.floor(px + 0.5)
	entry.Stroke.Thickness = math.clamp(px * Notify.STROKE_RATIO, Notify.STROKE_MIN, Notify.STROKE_MAX)
end

-- TextBounds is 0 until the first render; the one-line cap is the floor.
local function heightOf(entry)
	return math.max(textPx(), entry.Label.TextBounds.Y)
end

-- Visible through every GuiObject ancestor, inside an enabled LayerCollector.
local function isShown(object)
	local node = object
	while node do
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return false
end

-- The lowest centre y (this gui's space) the newest toast may take: AVOID_GAP above the
-- highest registered HUD element that shows right now, or nil when none does.
local function avoidLimit(newestHalf)
	local top = nil
	for object in avoids do
		if object.Parent and isShown(object) then
			local objectTop = object.AbsolutePosition.Y - gui.AbsolutePosition.Y
			if not top or objectTop < top then
				top = objectTop
			end
		end
	end
	if not top then
		return nil
	end
	return top - Notify.AVOID_GAP * gui.AbsoluteSize.Y - newestHalf
end

local function layout(animate)
	if not gui then
		return
	end
	local screenHeight = gui.AbsoluteSize.Y
	local gap = Notify.STACK_GAP * screenHeight
	local y = Notify.POSITION.Y.Scale * screenHeight + Notify.POSITION.Y.Offset
	local newest = entries[#entries]
	if newest then
		local limit = avoidLimit(heightOf(newest) * 0.5)
		if limit and limit < y then
			y = limit
		end
	end
	local previousHalf = nil
	for index = #entries, 1, -1 do
		local entry = entries[index]
		local half = heightOf(entry) * 0.5
		if previousHalf then
			y -= previousHalf + gap + half
		end
		previousHalf = half
		local target = UDim2.new(Notify.POSITION.X.Scale, Notify.POSITION.X.Offset, 0, y)
		if animate and entry.Placed then
			local tween = TweenService:Create(entry.Label, TweenInfo.new(Notify.SHIFT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target })
			table.insert(entry.Tweens, tween)
			tween:Play()
		else
			entry.Label.Position = target
		end
		entry.Placed = true
	end
end

local function build()
	if gui and gui.Parent then
		return true
	end
	local player = Players.LocalPlayer
	local playerGui = player and (player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10))
	if not playerGui then
		return false
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "PurchaseNotify"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = Notify.DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		for _, entry in entries do
			fitEntry(entry)
		end
		layout(false)
	end)
	return true
end

local function darken(color)
	local k = Notify.OUTLINE_DARKEN
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

local function makeEntry()
	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = Notify.POSITION
	label.Size = UDim2.fromScale(Notify.WIDTH, Notify.HEIGHT)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Notify.FONT
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = Notify.COLORS.Error
	label.Text = ""

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 12
	limit.MaxTextSize = Notify.MAX_TEXT_PX
	limit.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Thickness = 4
	stroke.Parent = label

	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = label

	return { Label = label, Stroke = stroke, Limit = limit, Scale = scale, Tweens = {}, Placed = false }
end

local function remove(entry)
	local index = table.find(entries, entry)
	if index then
		table.remove(entries, index)
	end
	for _, tween in entry.Tweens do
		tween:Cancel()
	end
	entry.Label:Destroy()
end

function Notify.Show(text, color, seconds)
	if not RunService:IsClient() or not build() then
		return
	end
	color = if typeof(color) == "Color3" then color else Notify.COLORS.Error
	while #entries >= Notify.MAX_STACK do
		remove(entries[1])
	end

	-- one chime per toast kind (SOUNDS.Library UIError / UISuccess / UIInfo)
	if color == Notify.COLORS.Error then
		Audio.Play("UIError")
	elseif color == Notify.COLORS.Success then
		Audio.Play("UISuccess")
	else
		Audio.Play("UIInfo")
	end

	local entry = makeEntry()
	entry.Label.Text = tostring(text)
	entry.Label.TextColor3 = color
	entry.Stroke.Color = darken(color)
	entry.Label.Parent = gui
	fitEntry(entry)
	table.insert(entries, entry)

	entry.Scale.Scale = Notify.POP_FROM
	local pop = TweenService:Create(entry.Scale, TweenInfo.new(Notify.POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	table.insert(entry.Tweens, pop)
	pop:Play()
	layout(true)
	task.defer(function()
		if table.find(entries, entry) then
			layout(true)
		end
	end)

	task.delay(tonumber(seconds) or Notify.HOLD, function()
		if not table.find(entries, entry) then
			return
		end
		local fadeText = TweenService:Create(entry.Label, TweenInfo.new(Notify.FADE), { TextTransparency = 1 })
		local fadeStroke = TweenService:Create(entry.Stroke, TweenInfo.new(Notify.FADE), { Transparency = 1 })
		table.insert(entry.Tweens, fadeText)
		table.insert(entry.Tweens, fadeStroke)
		fadeText:Play()
		fadeStroke:Play()
		task.delay(Notify.FADE + 0.05, function()
			if table.find(entries, entry) then
				remove(entry)
				layout(true)
			end
		end)
	end)
end

function Notify.Error(text, seconds)
	Notify.Show(text, Notify.COLORS.Error, seconds)
end

function Notify.Success(text, seconds)
	Notify.Show(text, Notify.COLORS.Success, seconds)
end

function Notify.Info(text, seconds)
	Notify.Show(text, Notify.COLORS.Info, seconds)
end

-- Keep the stack above this GuiObject whenever it (and every ancestor) is visible: the level
-- bar, the Stop button, the launch hint. The stack re-lays out as it shows, hides or moves.
function Notify.AvoidAbove(object)
	if not (object and object:IsA("GuiObject")) or avoids[object] then
		return
	end
	local connections = {}
	avoids[object] = connections
	local function relayout()
		if gui then
			layout(true)
		end
	end
	local node = object
	while node and not node:IsA("LayerCollector") do
		if node:IsA("GuiObject") then
			table.insert(connections, node:GetPropertyChangedSignal("Visible"):Connect(relayout))
		end
		node = node.Parent
	end
	table.insert(connections, object:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if gui then
			layout(false)
		end
	end))
	table.insert(connections, object.AncestryChanged:Connect(function()
		if not object:IsDescendantOf(Players.LocalPlayer) then
			Notify.StopAvoiding(object)
		end
	end))
end

function Notify.StopAvoiding(object)
	local connections = avoids[object]
	if not connections then
		return
	end
	avoids[object] = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	if gui then
		layout(true)
	end
end

-- The newest label, for layout checks. nil while nothing is on screen.
function Notify.Label()
	local entry = entries[#entries]
	return entry and entry.Label or nil
end

return Notify
