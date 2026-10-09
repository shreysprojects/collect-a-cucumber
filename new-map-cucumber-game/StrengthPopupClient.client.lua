--[[
	StrengthPopupClient  (LocalScript, StarterPlayerScripts)
	Draws the "+N" overhead popup when the StrengthPopup remote fires for a character
	(BenchServer, one per bench-press rep): a BillboardGui above the head with the
	strength icon on the left and "+N" on the right. Each popup pops in, then FLIES OUT
	in an arc: launched sideways (alternating left / right on screen, random speed) and
	upward, pulled back down by GRAVITY, tilting toward its travel, fading out over the
	last part of DURATION, then removes itself. StudsOffset is camera-relative, so the
	arcs always spread left / right on screen whatever way the bench faces. Shown on
	every client, so everyone sees other players' reps too.
	Sized in STUDS (scale units) with a scale-only layout, like PlotBadges' owner badge
	(user, 2026-09-06): the popup shrinks with distance like a world object instead of
	staying a fixed number of pixels that reads bigger the farther you stand.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ICON = "rbxassetid://15403007921"
local POPUP_W, POPUP_H = 3.6, 1.15 -- studs (scale = studs on a BillboardGui; was 150 x 48 px)
local ICON_FRAC = 0.83 -- icon height as a fraction of the popup height (was 40 of 48 px)
local TEXT_FRAC = 0.92 -- "+N" line height as a fraction of the popup height (was 44 of 48 px)
local START_HEIGHT = 1.6 -- studs above the head at launch
local DURATION = 1.3 -- seconds a popup lives
local SIDE_SPEED = {2.2, 4.6} -- studs/s sideways launch speed, random in this range, side alternates
local UP_SPEED = {5.2, 6.8} -- studs/s upward launch speed, random in this range
local GRAVITY = 7.5 -- studs/s^2 pulling the popup back down
local POP_TIME = 0.18 -- seconds for the scale pop (0.3 -> 1.15 -> 1)
local TILT = {6, 16} -- degrees the popup leans toward its travel, random in this range
local FADE_FROM = 0.6 -- fraction of DURATION where the fade-out starts

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StrengthPopup")
local side = 1 -- alternates so consecutive reps spray both ways

local function Rand(range)
	return range[1] + math.random() * (range[2] - range[1])
end

local function Show(character, amount)
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	amount = tonumber(amount) or 1

	local gui = Instance.new("BillboardGui")
	gui.Name = "StrengthPopup"
	gui.Size = UDim2.fromScale(POPUP_W, POPUP_H) -- scale = studs: shrinks with distance
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.StudsOffset = Vector3.new(0, START_HEIGHT, 0)
	gui.ResetOnSpawn = false
	gui.Adornee = head

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.04, 0) -- a fraction of the popup width, so the gap rides the stud sizing too
	layout.Parent = frame

	--.. icon: a fraction of the popup height, kept square by an aspect constraint driven by that height
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0, ICON_FRAC)
	icon.Image = ICON
	icon.ScaleType = Enum.ScaleType.Fit
	icon.LayoutOrder = 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = icon
	icon.Parent = frame

	--.. "+N": scaled text from its fractional height, auto-widened to fit
	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, TEXT_FRAC)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "+" .. amount
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = 2
	label.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(30, 30, 40)
	stroke.Thickness = 2.5
	stroke.Parent = label

	gui.Parent = head

	--.. launch: sideways (alternating), upward, gravity; pop in; lean; fade out
	side = -side
	local vx = side * Rand(SIDE_SPEED)
	local vy = Rand(UP_SPEED)
	local tilt = side * Rand(TILT)
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t >= DURATION or not gui.Parent then
			conn:Disconnect()
			if gui.Parent then gui:Destroy() end
			return
		end
		gui.StudsOffset = Vector3.new(vx * t, START_HEIGHT + vy * t - 0.5 * GRAVITY * t * t, 0)
		local s = 1
		if t < POP_TIME then
			local k = t / POP_TIME
			if k < 0.7 then
				s = 0.3 + 0.85 * (k / 0.7)
			else
				s = 1.15 - 0.15 * ((k - 0.7) / 0.3)
			end
		end
		scale.Scale = s
		frame.Rotation = tilt * math.min(1, t / (DURATION * 0.5))
		local f = math.clamp((t / DURATION - FADE_FROM) / (1 - FADE_FROM), 0, 1)
		icon.ImageTransparency = f
		label.TextTransparency = f
		stroke.Transparency = f
	end)
end

remote.OnClientEvent:Connect(Show)
