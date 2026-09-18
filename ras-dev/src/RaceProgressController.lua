-- RaceProgressGui controller (from RAS - Maps). 2026-09-17: compact layout - the bar is
-- half the screen wide at the very top, and each player's marker is a small headshot
-- ring that rides ON the bar (the original hung a 62 px portrait + pointer above it).
-- Distance comes from the replicated player attribute "Distance" (or leaderstats), the
-- run length from the gui attribute "MaxDistance".

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local gui = script.Parent
local root = gui:WaitForChild("Root")
local markers = root:WaitForChild("Markers")
local setDistance = gui:WaitForChild("SetDistance")

local MARKER_SIZE = 44

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

local function hideTopbar()
	for _ = 1, 30 do
		local ok = pcall(function()
			StarterGui:SetCore("TopbarEnabled", false)
		end)
		if ok then
			return
		end
		task.wait(0.1)
	end
end

task.spawn(hideTopbar)

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

	local target = UDim2.new(fractionFor(player), 0, 0.5, 0)
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
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.new(fractionFor(player), 0, 0.5, 0)
	marker.Size = UDim2.fromOffset(MARKER_SIZE, MARKER_SIZE)
	marker.BackgroundTransparency = 1
	marker.BorderSizePixel = 0
	marker.ZIndex = 12
	marker:SetAttribute("PlayerName", player.Name)
	marker:SetAttribute("UserId", player.UserId)
	marker.Parent = markers

	local color = markerColor(player)

	local ring = Instance.new("Frame")
	ring.Name = "HeadshotRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundColor3 = Color3.fromRGB(29, 32, 37)
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
	portrait.Size = UDim2.new(1, -6, 1, -6)
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
