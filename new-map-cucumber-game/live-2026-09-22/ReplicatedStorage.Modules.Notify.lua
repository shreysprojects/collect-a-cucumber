--[[
	Notify  (ModuleScript, ReplicatedStorage.Modules; used by LocalScripts only)
	THE one notification style for the whole game (user 2026-09-07, from a reference
	screenshot of "Not enough money": big bold red text with a dark outline that pops up
	near the bottom of the screen, above the hotbar). Every script that used to own its own
	small dark toast panel (EggShopClient, CarryClient, GymBoardsClient, PlotUpgradeClient,
	BenchBoardClient) routes through Notify.Show, so the look lives in one place.

	  Notify.Show(text, color?, seconds?)   red (COLORS.Error) unless a colour is given; the
	                                        outline is a darkened copy of the text colour
	  Notify.Error / Warn / Success / Info(text, seconds?)   the palette shortcuts

	STACK (2026-09-11, user: "make notifications stack up to 3"): up to MAX_STACK messages
	show at once. The newest sits at POSITION (50 % across, 66 % down = just above a bottom
	hotbar); older ones are pushed UP by their rendered height + STACK_GAP (a two-line message
	takes two lines of room). A fourth message throws the oldest out at once. Each message
	holds its own `seconds` (default HOLD), then fades over FADE and the rest slide back
	together (SHIFT_TIME).

	Layout: one ScreenGui "GameNotify" (IgnoreGuiInset, DisplayOrder 2000) holding one
	TextLabel per live message, WIDTH x HEIGHT of the screen (HEIGHT leaves room for two
	wrapped lines), TextScaled with the text height capped at TEXT_HEIGHT of the screen (and
	MAX_TEXT_PX), so a short message is one big line and a long one wraps to two lines of the
	same size; FredokaOne; a UIStroke outline STROKE_RATIO of the text height (STROKE_MIN..MAX
	px); a UIScale that pops POP_FROM -> 1 (Back easing) on every message. Everything is
	refitted whenever the screen resizes. GOTCHA: under TextScaled `label.TextSize` is
	meaningless - heights come from TextBounds (with the cap as the floor).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local M = {}

--..Look (from the reference screenshot)..--
M.COLORS = {
	Error = Color3.fromRGB(240, 58, 58), -- the "Not enough money" red
	Warn = Color3.fromRGB(255, 160, 60),
	Success = Color3.fromRGB(92, 225, 92),
	Info = Color3.fromRGB(255, 226, 120),
}
M.FONT = Enum.Font.FredokaOne
M.POSITION = UDim2.fromScale(0.5, 0.66) -- centre of the NEWEST message: 66 % down the screen (above a bottom hotbar)
M.WIDTH = 0.92 -- of the screen; long messages wrap onto a second line
M.HEIGHT = 0.15 -- of the screen: the label (room for two lines); the TEXT is capped separately
M.TEXT_HEIGHT = 0.075 -- of the screen: the text height of a one-line message (like the reference)
M.MAX_TEXT_PX = 64 -- absolute cap on very tall screens
M.STROKE_RATIO = 0.1 -- outline thickness as a fraction of the text height (the reference outline is chunky)
M.STROKE_MIN = 2
M.STROKE_MAX = 6
M.OUTLINE_DARKEN = 0.22 -- outline colour = text colour x this (near-black with a tint of the text)
M.HOLD = 2.0 -- seconds on screen before the fade
M.FADE = 0.35
M.POP_FROM = 0.7 -- UIScale at the start of the pop
M.POP_TIME = 0.16
M.DISPLAY_ORDER = 2000
M.MAX_STACK = 3 -- messages on screen at once; a new one throws the oldest out
M.STACK_GAP = 0.012 -- of the screen height, between stacked messages
M.SHIFT_TIME = 0.12 -- seconds a message takes to slide to its new row

local gui
local entries = {} -- oldest .. newest: {Label, Stroke, Limit, Scale, Tweens, Placed}
local serial = 0

local function textPx()
	return math.clamp(gui.AbsoluteSize.Y * M.TEXT_HEIGHT, 12, M.MAX_TEXT_PX)
end

--.. text cap and outline thickness from the screen height
local function fitEntry(e)
	local px = textPx()
	e.Limit.MaxTextSize = math.floor(px + 0.5)
	e.Stroke.Thickness = math.clamp(px * M.STROKE_RATIO, M.STROKE_MIN, M.STROKE_MAX)
end

--.. rendered height of a message (one or two lines); the cap is the floor while TextBounds is still 0
local function heightOf(e)
	local px = textPx()
	local bounds = e.Label.TextBounds
	return math.max(px, bounds.Y)
end

--.. the newest message at POSITION, older ones stacked upward by their own heights
local function layout(animate)
	if not gui then return end
	local h = gui.AbsoluteSize.Y
	local anchorY = M.POSITION.Y.Scale * h + M.POSITION.Y.Offset
	local gap = M.STACK_GAP * h
	local y = anchorY
	local prevHalf
	for i = #entries, 1, -1 do
		local e = entries[i]
		local half = heightOf(e) * 0.5
		if prevHalf then y -= prevHalf + gap + half end
		prevHalf = half
		local target = UDim2.new(M.POSITION.X.Scale, M.POSITION.X.Offset, 0, y)
		if animate and e.Placed then
			local tween = TweenService:Create(e.Label, TweenInfo.new(M.SHIFT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = target})
			table.insert(e.Tweens, tween)
			tween:Play()
		else
			e.Label.Position = target
		end
		e.Placed = true
	end
end

local function build()
	if gui and gui.Parent then return true end
	local player = Players.LocalPlayer
	if not player then return false end
	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if not playerGui then return false end
	gui = Instance.new("ScreenGui")
	gui.Name = "GameNotify"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = M.DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		for _, e in ipairs(entries) do fitEntry(e) end
		layout(false)
	end)
	return true
end

local function darken(color)
	local k = M.OUTLINE_DARKEN
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

local function makeEntry()
	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = M.POSITION
	label.Size = UDim2.fromScale(M.WIDTH, M.HEIGHT)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = M.FONT
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = M.COLORS.Error
	label.Text = ""

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 12
	limit.MaxTextSize = M.MAX_TEXT_PX
	limit.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(53, 13, 13)
	stroke.Parent = label

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "Pop"
	uiScale.Parent = label

	return {Label = label, Stroke = stroke, Limit = limit, Scale = uiScale, Tweens = {}, Placed = false}
end

local function remove(e)
	local i = table.find(entries, e)
	if i then table.remove(entries, i) end
	for _, t in ipairs(e.Tweens) do t:Cancel() end
	e.Label:Destroy()
end

--.. Show `text` in `color` (default COLORS.Error) for `seconds` (default HOLD). Client only.
function M.Show(text, color, seconds)
	if not RunService:IsClient() then return end
	if not build() then return end
	color = typeof(color) == "Color3" and color or M.COLORS.Error
	while #entries >= M.MAX_STACK do remove(entries[1]) end
	serial += 1
	local e = makeEntry()
	e.Serial = serial
	e.Label.Text = tostring(text)
	e.Label.TextColor3 = color
	e.Stroke.Color = darken(color)
	e.Label.Parent = gui
	fitEntry(e)
	table.insert(entries, e)
	e.Scale.Scale = M.POP_FROM
	local pop = TweenService:Create(e.Scale, TweenInfo.new(M.POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	table.insert(e.Tweens, pop)
	pop:Play()
	layout(true)
	task.defer(function() if table.find(entries, e) then layout(true) end end) -- TextBounds lands after the first render
	task.delay(tonumber(seconds) or M.HOLD, function()
		if not table.find(entries, e) then return end
		local fadeText = TweenService:Create(e.Label, TweenInfo.new(M.FADE), {TextTransparency = 1})
		local fadeStroke = TweenService:Create(e.Stroke, TweenInfo.new(M.FADE), {Transparency = 1})
		table.insert(e.Tweens, fadeText)
		table.insert(e.Tweens, fadeStroke)
		fadeText:Play()
		fadeStroke:Play()
		task.delay(M.FADE + 0.05, function()
			if table.find(entries, e) then
				remove(e)
				layout(true)
			end
		end)
	end)
end

function M.Error(text, seconds) M.Show(text, M.COLORS.Error, seconds) end
function M.Warn(text, seconds) M.Show(text, M.COLORS.Warn, seconds) end
function M.Success(text, seconds) M.Show(text, M.COLORS.Success, seconds) end
function M.Info(text, seconds) M.Show(text, M.COLORS.Info, seconds) end

--.. the newest label (layout checks / tests); nil while nothing is on screen
function M.Label()
	local e = entries[#entries]
	return e and e.Label or nil
end

--.. every live label, oldest first (tests)
function M.Labels()
	local list = {}
	for _, e in ipairs(entries) do table.insert(list, e.Label) end
	return list
end

return M
