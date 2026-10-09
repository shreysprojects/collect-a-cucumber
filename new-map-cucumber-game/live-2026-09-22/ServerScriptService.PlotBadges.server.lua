--[[
	PlotBadges  (Script, ServerScriptService)
	Floating owner badge above every claimed plot: the owner's circular headshot (white outer ring,
	dark inner ring, light disc behind the head) with the display name underneath in heavy white
	text with a dark outline, like the reference screenshot.

	PlotService marks ownership with the plot attributes Owner (UserId) / OwnerName; this script
	only watches those, so it never touches PlotService's state. The badge is a BillboardGui on an
	invisible anchor part (plot.PlotBadge) above the CENTRE of the plot, BADGE_HEIGHT studs over the
	plot surface. Plots grow at runtime (PlotUpgradeService), so the anchor follows the plot's
	Size / CFrame. The gui is sized in STUDS (scale units) with a scale-only layout, so it shrinks
	with distance like any world object instead of staying a fixed number of pixels.
]]
local Players = game:GetService("Players")

--..Config..--
local PLOTS_FOLDER = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
local BADGE_HEIGHT = 33 -- studs above the plot surface (was 27; user 2026-09-19: 6 studs higher)
local MAX_DISTANCE = 600
local BADGE_W, BADGE_H = 17.58, 12.89 -- studs (the first 9 x 6.6, enlarged 25% three times; the last x1.25 user 2026-09-19)
local AVATAR_FRACTION = 0.62 -- avatar circle diameter as a fraction of BADGE_H (~8 studs)
local RING_COLOR = Color3.fromRGB(26, 26, 40)
local DISC_COLOR = Color3.fromRGB(218, 218, 224)
local NAME_STROKE = Color3.fromRGB(12, 12, 18)

--..Geometry..--
local function CentreTop(plot)
	return Vector3.new(plot.Position.X, plot.Position.Y + plot.Size.Y * 0.5, plot.Position.Z)
end

local function AnchorFor(plot)
	local anchor = plot:FindFirstChild("PlotBadge")
	if not anchor then
		anchor = Instance.new("Part")
		anchor.Name = "PlotBadge"
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Parent = plot
	end
	anchor.CFrame = CFrame.new(CentreTop(plot) + Vector3.new(0, BADGE_HEIGHT, 0))
	return anchor
end

--..Gui..--
local function Circle(parent, name, color, fraction)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(fraction, fraction)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	return f
end

local function BuildGui(userId, displayName)
	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerBadge"
	gui.Size = UDim2.fromScale(BADGE_W, BADGE_H) -- scale = studs: shrinks with distance
	gui.AlwaysOnTop = true
	gui.MaxDistance = MAX_DISTANCE
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	--.. white outer ring (a circle sized by height, kept round by the aspect constraint)
	local outer = Instance.new("Frame")
	outer.Name = "Avatar"
	outer.AnchorPoint = Vector2.new(0.5, 0)
	outer.Position = UDim2.fromScale(0.5, 0)
	outer.Size = UDim2.fromScale(0, AVATAR_FRACTION)
	outer.BackgroundColor3 = Color3.new(1, 1, 1)
	outer.BorderSizePixel = 0
	outer.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = outer
	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = UDim.new(1, 0)
	outerCorner.Parent = outer

	--.. dark inner ring, then the headshot disc (all proportional, so the rings scale with distance too)
	local ring = Circle(outer, "Ring", RING_COLOR, 0.9)
	local head = Instance.new("ImageLabel")
	head.Name = "Head"
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.5, 0.5)
	head.Size = UDim2.fromScale(0.9, 0.9)
	head.BackgroundColor3 = DISC_COLOR
	head.BorderSizePixel = 0
	head.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
	head.ScaleType = Enum.ScaleType.Fit
	head.Parent = ring
	local headCorner = Instance.new("UICorner")
	headCorner.CornerRadius = UDim.new(1, 0)
	headCorner.Parent = head

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromScale(0.5, AVATAR_FRACTION + 0.05)
	name.Size = UDim2.fromScale(1, 1 - AVATAR_FRACTION - 0.08)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = displayName
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = NAME_STROKE
	stroke.Transparency = 0.1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = name
	return gui
end

--..Per plot..--
local function Refresh(plot)
	local owner = plot:GetAttribute("Owner")
	local existing = plot:FindFirstChild("PlotBadge")
	if type(owner) ~= "number" then
		if existing then existing:Destroy() end
		return
	end
	local anchor = AnchorFor(plot)
	local gui = anchor:FindFirstChild("OwnerBadge")
	if gui and gui:GetAttribute("UserId") == owner then return end
	if gui then gui:Destroy() end
	local player = Players:GetPlayerByUserId(owner)
	local displayName = player and player.DisplayName or plot:GetAttribute("OwnerName") or "Player"
	gui = BuildGui(owner, displayName)
	gui:SetAttribute("UserId", owner)
	gui.Parent = anchor
end

local function Watch(plot)
	if not plot:IsA("BasePart") then return end
	plot:GetAttributeChangedSignal("Owner"):Connect(function() Refresh(plot) end)
	local pending = false
	local function reposition()
		if pending then return end
		pending = true
		task.defer(function()
			pending = false
			if plot:FindFirstChild("PlotBadge") then AnchorFor(plot) end
		end)
	end
	plot:GetPropertyChangedSignal("Size"):Connect(reposition)
	plot:GetPropertyChangedSignal("CFrame"):Connect(reposition)
	Refresh(plot)
end

for _, plot in ipairs(PLOTS_FOLDER:GetChildren()) do Watch(plot) end
PLOTS_FOLDER.ChildAdded:Connect(Watch)
