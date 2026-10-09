-- Race progress: player portrait pins sit above the taller artwork strip.
-- Distance comes from the replicated player attribute "Distance" (or leaderstats), the
-- run length from the gui attribute "MaxDistance".
--
-- 2026-09-22: the bar never covers the HUD.
--   * The gui draws below the HUD and Menu ScreenGuis (LAYOUT.DisplayOrder).
--   * It slides up out of view while a HUD panel is open (PlayerGui attribute "PanelOpen")
--     and slides back when the panel closes.
--   * A UIScale on Root shrinks the whole authored bar (Track art, shadow, markers) just
--     enough that it ends above the HUD's top-centre ride labels (MainUI.DistanceRolled /
--     CoinsMade), measured live, on any screen size. Start / Finish text and the markers
--     keep a readable minimum size. The Markers frame follows the Track box.
-- Dev check: gui attributes LayoutScale / LayoutClearTop / LayoutBottom hold the result.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local HUDLayout = require(game.ReplicatedStorage.Assets.Modules.Client.UI.HUDLayout)
local gui = script.Parent
local root = gui:WaitForChild("Root")
local track = root:WaitForChild("Track")
local markers = root:WaitForChild("Markers")
local setDistance = gui:WaitForChild("SetDistance")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local preview = markers:FindFirstChild("StudioPreview")
if preview then preview:Destroy() end

local MARKER_SIZE = 64

local LAYOUT = {
	DisplayOrder = -1, -- under HUD (0) and Menu (5): HUD elements always draw over the bar
	AvoidLabels = { "DistanceRolled", "CoinsMade" }, -- labels under PlayerGui.HUD the bar must end above
	FallbackClearTop = 0.22, -- screen fraction: DistanceRolled's top edge in the Studio template
	Gap = 2, -- px kept between the bar and those labels
	MinScale = 0.25,
	MaxScale = 1, -- never larger than the authored layout
	LabelMinScale = 0.65, -- Start / Finish text renders at no less than this x its authored size
	MarkerMinPx = 20, -- headshot rings stay at least this big while the space allows
	HideMargin = 8, -- px past the bar's lowest pixel when slid out
	HideTween = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	ShowTween = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), -- no overshoot into the HUD
}

local palette = {
	Color3.fromRGB(255, 220, 48),
	Color3.fromRGB(139, 87, 255),
	Color3.fromRGB(61, 119, 255),
	Color3.fromRGB(255, 87, 171),
	Color3.fromRGB(51, 207, 135),
	Color3.fromRGB(255, 116, 50),
}

local playerConnections = {}
local markerTweens = {}
local localOverrides = {}
local markerSize = MARKER_SIZE -- pre-scale marker size (grows when LayoutScale is small)

local function restoreTopbar()
	for _ = 1, 30 do
		local ok = pcall(function()
			StarterGui:SetCore("TopbarEnabled", true)
		end)
		if ok then
			return
		end
		task.wait(0.1)
	end
end

task.spawn(restoreTopbar)

gui.DisplayOrder = LAYOUT.DisplayOrder

----------------------------------------------------------------------------------------------
-- Layout: every number below is read from the authored frames, so Studio edits to the
-- bar (height, art, label placement) carry through; only the overall scale is computed.
----------------------------------------------------------------------------------------------

local ROOT_H = root.Size.Y.Offset

-- Root hangs from the top centre so the UIScale shrinks it towards the middle.
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0, 0)
root.Size = UDim2.new(1, 0, 0, ROOT_H)

markers.AnchorPoint = track.AnchorPoint
markers.Position = track.Position
markers.Size = track.Size

-- Top and bottom of a Root child in Root's unscaled space.
local function spanY(object)
	local height = object.Size.Y.Scale * ROOT_H + object.Size.Y.Offset
	local top = object.Position.Y.Scale * ROOT_H + object.Position.Y.Offset - object.AnchorPoint.Y * height
	return top, top + height
end

local function borderStroke(object)
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if stroke and stroke.Enabled and stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
		return stroke.Thickness
	end
	return 0
end

local layoutScale = root:FindFirstChild("LayoutScale") or Instance.new("UIScale")
layoutScale.Name = "LayoutScale"
layoutScale.Parent = root

-- Start / Finish labels get their own UIScale so their text never drops below LabelMinScale.
local labels = {}
for _, name in ipairs({ "StartLabel", "FinishLabel" }) do
	local label = root:FindFirstChild(name)
	if label and label:IsA("GuiObject") then
		local top, bottom = spanY(label)
		local scale = Instance.new("UIScale")
		scale.Name = "MinTextScale"
		scale.Parent = label
		table.insert(labels, { Top = top, Height = bottom - top, Scale = scale })
	end
end

local shown = true
local slideTween = nil
local contentBottom = 160 -- lowest on-screen pixel of the bar at rest, labels included (160 covers the unscaled bar)
local lastLayoutKey = nil
local avoidLabels = {} -- strong keys: an Instance's Luau reference can be collected from a weak table while it is still parented

local function restPosition(visible)
	if visible then
		return UDim2.new(0.5, 0, 0, HUDLayout.GetTopInset(gui.AbsoluteSize) + 6 * HUDLayout.GetScale(gui.AbsoluteSize))
	end
	return UDim2.new(0.5, 0, 0, -math.ceil(contentBottom + LAYOUT.HideMargin))
end

-- A label's box without any pop UIScale on it (CoinsMade grows while coins land).
local function restingBox(label)
	local size = label.AbsoluteSize
	local pop = label:FindFirstChildOfClass("UIScale")
	local k = if pop and pop.Scale > 0 then pop.Scale else 1
	local rest = size / k
	local center = label.AbsolutePosition + size / 2 - gui.AbsolutePosition
	return center - rest / 2, rest
end

-- Screen y the bar has to stay above: the highest HUD avoid-label overlapping it sideways.
local function clearTop(height, barLeft, barRight)
	local found = false
	local best = math.huge
	for label in avoidLabels do
		if label.Parent and label:IsDescendantOf(playerGui) and label.AbsoluteSize.Y > 0 then
			found = true
			local position, size = restingBox(label)
			if position.X < barRight and position.X + size.X > barLeft then
				best = math.min(best, position.Y)
			end
		end
	end
	if not found then
		return LAYOUT.FallbackClearTop * height
	end
	return best
end

local function applyLayout()
	local viewport = gui.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then return end
	local hudScale = HUDLayout.GetScale(viewport)
	local scale = hudScale * HUDLayout.TrackerBaseScale * HUDLayout.TrackerFactor
	local key = string.format("%.1f:%.1f:%.4f", viewport.X, viewport.Y, scale)
	if key == lastLayoutKey then return end
	lastLayoutKey = key
	layoutScale.Scale = scale
	root.Size = UDim2.fromOffset(1301 / HUDLayout.TrackerBaseScale, ROOT_H)
	local _, trackBottom = spanY(track)
	local topOffset = HUDLayout.GetTopInset(viewport) + 6 * hudScale
	contentBottom = topOffset + (trackBottom + borderStroke(track) + 3) * scale
	for _, label in labels do
		label.Scale.Scale = 1
		contentBottom = math.max(contentBottom, topOffset + (label.Top + label.Height) * scale)
	end
	markerSize = MARKER_SIZE
	for _, marker in markers:GetChildren() do
		if marker:IsA("GuiObject") then marker.Size = UDim2.fromOffset(markerSize, markerSize) end
	end
	if slideTween then slideTween:Cancel() slideTween = nil end
	root.Position = restPosition(shown)
	root.Visible = shown
	gui:SetAttribute("LayoutScale", scale)
	gui:SetAttribute("LayoutBottom", contentBottom)
end

local layoutQueued = false
local function queueLayout()
	if layoutQueued then
		return
	end
	layoutQueued = true
	task.defer(function()
		layoutQueued = false
		applyLayout()
	end)
end

local function isAvoidLabel(instance)
	return (instance:IsA("TextLabel") or instance:IsA("TextButton")) and table.find(LAYOUT.AvoidLabels, instance.Name) ~= nil
end

local function watchAvoidLabel(label)
	if avoidLabels[label] then
		return
	end
	avoidLabels[label] = true
	label:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueLayout)
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout)
	label.AncestryChanged:Connect(queueLayout)
	label.Destroying:Connect(function()
		avoidLabels[label] = nil
		queueLayout()
	end)
	queueLayout()
end

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout)
applyLayout()

-- The HUD clones MainUI in after this script starts; pick its labels up when they arrive
-- (also from a HUD ScreenGui that is added later or replaced).
local function watchHud(hud)
	hud.DescendantAdded:Connect(function(descendant)
		if isAvoidLabel(descendant) then
			watchAvoidLabel(descendant)
		end
	end)
	for _, descendant in hud:GetDescendants() do
		if isAvoidLabel(descendant) then
			watchAvoidLabel(descendant)
		end
	end
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUD" then
		watchHud(child)
	end
end)
local existingHud = playerGui:FindFirstChild("HUD")
if existingHud then
	watchHud(existingHud)
end

----------------------------------------------------------------------------------------------
-- HUD panels: slide the bar out while one is open.
----------------------------------------------------------------------------------------------

local function setShown(visible, instant)
	if slideTween then
		slideTween:Cancel()
		slideTween = nil
	end
	shown = visible
	if visible then
		root.Visible = true
	end

	local target = restPosition(visible)
	if instant then
		root.Position = target
		root.Visible = visible
		return
	end

	local tween = TweenService:Create(root, if visible then LAYOUT.ShowTween else LAYOUT.HideTween, { Position = target })
	slideTween = tween
	tween.Completed:Connect(function(state)
		if slideTween == tween then
			slideTween = nil
		end
		if state == Enum.PlaybackState.Completed and not shown then
			root.Visible = false
		end
	end)
	tween:Play()
end

local function panelOpen()
	local name = playerGui:GetAttribute("PanelOpen")
	return name ~= nil and name ~= false and name ~= ""
end

-- Deferred so a panel swap (PanelOpen nil -> next panel in one frame) never flickers the bar.
local panelQueued = false
playerGui:GetAttributeChangedSignal("PanelOpen"):Connect(function()
	if panelQueued then
		return
	end
	panelQueued = true
	task.defer(function()
		panelQueued = false
		local visible = not panelOpen()
		if visible ~= shown then
			setShown(visible, false)
		end
	end)
end)

if panelOpen() then
	setShown(false, true)
end

----------------------------------------------------------------------------------------------
-- Markers
----------------------------------------------------------------------------------------------

local function getMaxDistance()
	return math.max(1, tonumber(gui:GetAttribute("MaxDistance")) or 10000)
end

local function readDistance(player)
	if localOverrides[player.UserId] ~= nil then
		return localOverrides[player.UserId]
	end

	for _, attributeName in ipairs({ "Distance", "RaceDistance", "Meters", "ProgressDistance" }) do
		local value = player:GetAttribute(attributeName)
		if typeof(value) == "number" then
			return value
		end
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		for _, valueName in ipairs({ "Distance", "Meters", "Studs" }) do
			local valueObject = leaderstats:FindFirstChild(valueName)
			if valueObject and tonumber(valueObject.Value) then
				return tonumber(valueObject.Value)
			end
		end
	end

	return 0
end

local function fractionFor(player)
	return math.clamp(readDistance(player) / getMaxDistance(), 0, 1)
end

local function markerColor(player)
	return palette[(math.abs(player.UserId) % #palette) + 1]
end

local function updateMarker(player, instant)
	local marker = markers:FindFirstChild(tostring(player.UserId))
	if not marker then
		return
	end

	local target = UDim2.new(fractionFor(player), 0, 0, 0)
	if markerTweens[player] then
		markerTweens[player]:Cancel()
	end

	if instant then
		marker.Position = target
	else
		local tween = TweenService:Create(
			marker,
			TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = target }
		)
		markerTweens[player] = tween
		tween:Play()
	end
end

local function circle(parent)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = parent
end

local function createMarker(player)
	local marker = Instance.new("Frame")
	marker.Name = tostring(player.UserId)
	marker.AnchorPoint = Vector2.new(0.5, 1)
	marker.Position = UDim2.new(fractionFor(player), 0, 0, 0)
	marker.Size = UDim2.fromOffset(markerSize, markerSize)
	marker.BackgroundTransparency = 1
	marker.BorderSizePixel = 0
	marker.ZIndex = 12
	marker:SetAttribute("PlayerName", player.Name)
	marker:SetAttribute("UserId", player.UserId)
	marker.Parent = markers

	local color = markerColor(player)

	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Position = UDim2.fromScale(0.5, 0.735)
	pointer.Size = UDim2.fromScale(0.36, 0.36)
	pointer.Rotation = 45
	pointer.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	pointer.BorderSizePixel = 0
	pointer.ZIndex = 13
	pointer.Parent = marker
	local pointerFill = Instance.new("Frame")
	pointerFill.Name = "Color"
	pointerFill.AnchorPoint = Vector2.new(0.5, 0.5)
	pointerFill.Position = UDim2.fromScale(0.5, 0.5)
	pointerFill.Size = UDim2.fromScale(0.64, 0.64)
	pointerFill.BackgroundColor3 = color
	pointerFill.BorderSizePixel = 0
	pointerFill.ZIndex = 14
	pointerFill.Parent = pointer

	local ring = Instance.new("Frame")
	ring.Name = "HeadshotRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.42)
	ring.Size = UDim2.fromScale(0.84, 0.84)
	ring.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	ring.BorderSizePixel = 0
	ring.ZIndex = 15
	ring.Parent = marker
	circle(ring)

	local colorRing = Instance.new("Frame")
	colorRing.Name = "ColorRing"
	colorRing.AnchorPoint = Vector2.new(0.5, 0.5)
	colorRing.Position = UDim2.fromScale(0.5, 0.5)
	colorRing.Size = UDim2.new(1, -6, 1, -6)
	colorRing.BackgroundColor3 = color
	colorRing.BorderSizePixel = 0
	colorRing.ZIndex = 16
	colorRing.Parent = ring
	circle(colorRing)

	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Headshot"
	portrait.AnchorPoint = Vector2.new(0.5, 0.5)
	portrait.Position = UDim2.fromScale(0.5, 0.5)
	portrait.Size = UDim2.new(1, -8, 1, -8)
	portrait.BackgroundColor3 = Color3.fromRGB(227, 239, 231)
	portrait.BorderSizePixel = 0
	portrait.Image = ""
	portrait.ScaleType = Enum.ScaleType.Crop
	portrait.ZIndex = 17
	portrait.Parent = colorRing
	circle(portrait)

	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if ok and portrait.Parent then
			portrait.Image = image
		end
	end)

	local connections = {}
	for _, attributeName in ipairs({ "Distance", "RaceDistance", "Meters", "ProgressDistance" }) do
		table.insert(connections, player:GetAttributeChangedSignal(attributeName):Connect(function()
			localOverrides[player.UserId] = nil
			updateMarker(player, false)
		end))
	end

	local function watchLeaderstats(leaderstats)
		for _, valueName in ipairs({ "Distance", "Meters", "Studs" }) do
			local valueObject = leaderstats:FindFirstChild(valueName)
			if valueObject and valueObject:IsA("ValueBase") then
				table.insert(connections, valueObject.Changed:Connect(function()
					localOverrides[player.UserId] = nil
					updateMarker(player, false)
				end))
			end
		end
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		watchLeaderstats(leaderstats)
	end
	table.insert(connections, player.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" then
			task.defer(watchLeaderstats, child)
		end
	end))

	playerConnections[player] = connections
	updateMarker(player, true)
end

local function removeMarker(player)
	local marker = markers:FindFirstChild(tostring(player.UserId))
	if marker then
		marker:Destroy()
	end
	for _, connection in ipairs(playerConnections[player] or {}) do
		connection:Disconnect()
	end
	playerConnections[player] = nil
	localOverrides[player.UserId] = nil
	if markerTweens[player] then
		markerTweens[player]:Cancel()
		markerTweens[player] = nil
	end
end

setDistance.Event:Connect(function(playerOrUserId, distance)
	local userId
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		userId = playerOrUserId.UserId
	else
		userId = tonumber(playerOrUserId)
	end
	if not userId then
		return
	end
	localOverrides[userId] = math.clamp(tonumber(distance) or 0, 0, getMaxDistance())
	local player = Players:GetPlayerByUserId(userId)
	if player then
		updateMarker(player, false)
	end
end)

gui:GetAttributeChangedSignal("MaxDistance"):Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		updateMarker(player, false)
	end
end)

Players.PlayerAdded:Connect(createMarker)
Players.PlayerRemoving:Connect(removeMarker)

for _, player in ipairs(Players:GetPlayers()) do
	createMarker(player)
end
