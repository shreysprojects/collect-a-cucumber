-- Floating bench multiplier circles; BenchServer owns rarity, expiry, and single-use rewards.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BenchBonusPopup")
local SoundController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundController"))
local random = Random.new()
local COLORS = {
	[3] = Color3.fromRGB(0, 218, 163),
	[5] = Color3.fromRGB(44, 189, 255),
	[10] = Color3.fromRGB(181, 104, 255),
	[20] = Color3.fromRGB(255, 204, 55),
}
local POP_VARIANTS = {"Bottle Pop", "Bottle Pop 2"} -- existing balloon-pop audio
local function PlayPop(key, pitch)
	SoundController.PlayFX("Bottle Pop", {Variants = POP_VARIANTS, Pitch = pitch, Key = key, MinInterval = 0.15})
end

local gui = Instance.new("ScreenGui")
gui.Name = "BenchBonusGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 30
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Name = "BonusButton"
button.Text = ""
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.AnchorPoint = Vector2.new(0.5, 0.5)
button.Size = UDim2.fromScale(0.16, 0.16)
button.Visible = false
button.Parent = gui
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 1
aspect.DominantAxis = Enum.DominantAxis.Height
aspect.Parent = button
local bounds = Instance.new("UISizeConstraint")
bounds.MinSize = Vector2.new(72, 72)
bounds.MaxSize = Vector2.new(108, 108)
bounds.Parent = button
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = button
local outline = Instance.new("UIStroke")
outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
outline.Color = Color3.fromRGB(12, 18, 21)
outline.Thickness = 3
outline.Parent = button
local scale = Instance.new("UIScale")
scale.Parent = button

local label = Instance.new("TextLabel")
label.Name = "Multiplier"
label.BackgroundTransparency = 1
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.49)
label.Size = UDim2.fromScale(0.84, 0.64)
label.Font = Enum.Font.FredokaOne
label.TextScaled = true
label.TextColor3 = Color3.new(1, 1, 1)
label.ZIndex = button.ZIndex + 1
label.Parent = button
local textOutline = Instance.new("UIStroke")
textOutline.Color = Color3.fromRGB(12, 18, 21)
textOutline.Thickness = 3
textOutline.Parent = label


-- Click effects share one render loop and never change the awarded strength.
local effects, pendingClaims = {}, {}
local function Burst(origin, diameter, color)
	local root = Instance.new("Frame")
	root.Name = "CircleBurst"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(0, 0)
	root.Position = UDim2.fromOffset(origin.X, origin.Y)
	root.ZIndex = 10
	root.Parent = gui
	local ring = Instance.new("Frame")
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.ZIndex = 10
	ring.Parent = root
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = ring
	local rim = Instance.new("UIStroke")
	rim.Color = color:Lerp(Color3.new(1, 1, 1), 0.45)
	rim.Thickness = 5
	rim.Parent = ring
	local fragments = {}
	for i = 1, 12 do
		local angle = i / 12 * math.pi * 2
		local shard = Instance.new("Frame")
		shard.Name = "Spark"
		shard.BorderSizePixel = 0
		shard.BackgroundColor3 = i % 3 == 0 and Color3.new(1, 1, 1) or color
		shard.AnchorPoint = Vector2.new(0.5, 0.5)
		shard.Rotation = math.deg(angle) + 90
		shard.ZIndex = 11
		shard.Parent = root
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = shard
		table.insert(fragments, {Part = shard, Direction = Vector2.new(math.cos(angle), math.sin(angle))})
	end
	local began = os.clock()
	table.insert(effects, function(now)
		local t = (now - began) / 0.42
		if t >= 1 or not root.Parent then root:Destroy() return false end
		local spread = 1 - (1 - t) ^ 3
		local ringSize = diameter * (0.8 + 0.85 * spread)
		ring.Size = UDim2.fromOffset(ringSize, ringSize)
		rim.Transparency = t
		rim.Thickness = 5 * (1 - t) + 1
		for _,fragment in ipairs(fragments) do
			local p = fragment.Direction * diameter * (0.3 + 0.65 * spread)
			fragment.Part.Position = UDim2.fromOffset(p.X, p.Y)
			fragment.Part.Size = UDim2.fromOffset(6 * (1 - t) + 1, 16 * (1 - t) + 2)
			fragment.Part.BackgroundTransparency = t
		end
		return true
	end)
end

local function FlyReward(claim, amount)
	local hud = player.PlayerGui:FindFirstChild("CucumberHUDDesign")
	local counters = hud and hud:FindFirstChild("Counters")
	local target = counters and counters:FindFirstChild("StrengthIcon")
	local root = Instance.new("Frame")
	root.Name = "BonusStrengthFlight"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	local height = math.clamp(gui.AbsoluteSize.Y * 0.075, 34, 54)
	root.Size = UDim2.fromOffset(height * 4.2, height)
	root.ZIndex = 12
	root:SetAttribute("Amount", amount)
	root:SetAttribute("OfferId", claim.Token)
	root.Parent = gui
	local icon = Instance.new("ImageLabel")
	icon.Name = "StrengthIcon"
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://15403007921"
	icon.Size = UDim2.fromScale(0.23, 1)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 12
	icon.Parent = root
	local text = Instance.new("TextLabel")
	text.Name = "Amount"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromScale(0.25, 0)
	text.Size = UDim2.fromScale(0.75, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = Color3.fromRGB(255, 222, 92)
	text.Text = "+" .. tostring(amount)
	text.ZIndex = 12
	text.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(30, 30, 40)
	stroke.Thickness = 2.5
	stroke.Parent = text
	local size = Instance.new("UIScale")
	size.Parent = root
	local began = os.clock()
	local direction = claim.Position.X > 0.5 and 1 or -1
	local function Update(now)
		local elapsed = now - began
		if elapsed >= 1.25 or not root.Parent or player.Character ~= claim.Character then
			root:Destroy()
			return false
		end
		-- Both ScreenGuis respect the core UI inset; use actual HUD bounds every frame.
		local origin = claim.Position * gui.AbsoluteSize
		local destination = target and target:IsDescendantOf(player.PlayerGui)
			and (target.AbsolutePosition + target.AbsoluteSize * 0.5)
			or origin - Vector2.new(0, 100)
		local travel = math.clamp((elapsed - 0.16) / 1.09, 0, 1)
		local u = travel * travel * (3 - 2 * travel)
		local control = origin:Lerp(destination, 0.5) + Vector2.new(direction * 70, -55)
		local position = origin * (1 - u) ^ 2 + control * (2 * (1 - u) * u) + destination * u ^ 2
		root.Position = UDim2.fromOffset(position.X, position.Y)
		local arrive = math.clamp((travel - 0.65) / 0.35, 0, 1)
		size.Scale = math.min(1, 0.6 + elapsed * 4) * (1 - arrive * 0.8)
		root.Rotation = direction * 7 * math.sin(travel * math.pi)
		local fade = math.clamp((travel - 0.87) / 0.13, 0, 1)
		text.TextTransparency, icon.ImageTransparency, stroke.Transparency = fade, fade, fade
		return true
	end
	Update(began)
	table.insert(effects, Update)
end

local token, activeSeat, expiresAt, startedAt
local startX, endX, startY, endY, sway
local function Hide()
	token, activeSeat, expiresAt, startedAt = nil, nil, nil, nil
	button.Visible = false
	button.Active = false
	button:SetAttribute("OfferId", nil)
	button:SetAttribute("Multiplier", nil)
end

local function OnBench(seat)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.Health > 0 and seat ~= nil and humanoid.SeatPart == seat
		and seat:IsDescendantOf(workspace)
end

remote.OnClientEvent:Connect(function(action, offerId, seat, deadline, multiplier)
	if action == "Claimed" then
		local claim = pendingClaims[offerId]
		pendingClaims[offerId] = nil
		local amount = seat -- server acknowledgement: ("Claimed", token, awardedStrength)
		if claim and player.Character == claim.Character and typeof(amount) == "number"
			and amount > 0 and amount < math.huge then FlyReward(claim, amount) end
		return
	end
	if action == "Hide" then
		if offerId == nil or offerId == token then Hide() end
		return
	end
	if action ~= "Show" or typeof(offerId) ~= "string" or typeof(deadline) ~= "number"
		or not COLORS[multiplier] or not OnBench(seat) or deadline <= workspace:GetServerTimeNow() then return end
	Hide()
	token, activeSeat, expiresAt = offerId, seat, deadline
	startedAt = workspace:GetServerTimeNow()
	-- Central lanes avoid side menus, the top counters, and mobile movement controls.
	startX = random:NextNumber(0.25, 0.78)
	endX = math.clamp(startX + random:NextNumber(-0.16, 0.16), 0.23, 0.8)
	startY, endY = random:NextNumber(0.72, 0.8), random:NextNumber(0.2, 0.27)
	sway = random:NextNumber(-0.025, 0.025)
	button.Position = UDim2.fromScale(startX, startY)
	button.Rotation = 0
	button.BackgroundColor3 = COLORS[multiplier]
	button.BackgroundTransparency = 0
	outline.Transparency, label.TextTransparency, textOutline.Transparency = 0, 0, 0
	label.Text = tostring(multiplier) .. "X"
	button:SetAttribute("OfferId", offerId)
	button:SetAttribute("Multiplier", multiplier)
	button.Visible = true
	button.Active = true
	scale.Scale = 0.35
	PlayPop("BenchCircleAppear", 0.06)
end)

button.Activated:Connect(function()
	local claim = token
	if not claim then return end
	local valid = OnBench(activeSeat) and workspace:GetServerTimeNow() < expiresAt
	local origin = button.AbsolutePosition + button.AbsoluteSize * 0.5
	local diameter, color = button.AbsoluteSize.X, button.BackgroundColor3
	Hide() -- consume locally once for mouse, touch, and controller
	if valid then
		pendingClaims[claim] = {
			Token = claim, Position = origin / gui.AbsoluteSize,
			Character = player.Character, CreatedAt = os.clock(),
		}
		Burst(origin, diameter, color)
		PlayPop("BenchCircleClaim", 0.12)
		remote:FireServer(claim)
	end
end)

RunService.RenderStepped:Connect(function()
	local clock = os.clock()
	for index = #effects, 1, -1 do
		if not effects[index](clock) then
			effects[index] = effects[#effects]
			effects[#effects] = nil
		end
	end
	for id,claim in pairs(pendingClaims) do
		if clock - claim.CreatedAt > 8 then pendingClaims[id] = nil end
	end
	if not token then return end
	local now = workspace:GetServerTimeNow()
	if not OnBench(activeSeat) or now >= expiresAt then Hide() return end
	local age = now - startedAt
	local progress = math.clamp(age / math.max(0.01, expiresAt - startedAt), 0, 1)
	local x = startX + (endX - startX) * progress + math.sin(progress * math.pi * 2) * sway
	button.Position = UDim2.fromScale(x, startY + (endY - startY) * progress)
	button.Rotation = math.sin(progress * math.pi * 2) * 7
	-- Quick arrival pop; float at a steady speed and fade through the final quarter.
	local pop = math.clamp(age / 0.28, 0, 1)
	scale.Scale = pop < 0.7 and (0.35 + 0.8 * pop / 0.7) or (1.15 - 0.15 * (pop - 0.7) / 0.3)
	local fade = math.clamp((progress - 0.75) / 0.25, 0, 1)
	button.BackgroundTransparency = fade
	outline.Transparency, label.TextTransparency, textOutline.Transparency = fade, fade, fade
end)
player.CharacterRemoving:Connect(function()
	Hide()
	table.clear(pendingClaims)
end)
script.Destroying:Connect(function() gui:Destroy() end)
