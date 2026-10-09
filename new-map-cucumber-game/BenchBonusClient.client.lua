-- Bench bonus button: offers and rewards are owned by BenchServer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BenchBonusPopup")
local SoundController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundController"))
local random = Random.new()
-- SFX (user, 2026-09-07): a cartoon pop when the bottle pops up, a splash when it is clicked
-- (ReplicatedStorage.Assets.Sounds "Bottle Pop" / "Bottle Pop 2" = balloon pops, "Water Splash" /
-- "Water Splash 2" = short puddle splashes; Pro Sound Effects, random pick with a little pitch
-- jitter). Loudness lives in the templates' AuthoredVolume (the splash recordings are quiet, so
-- they run at 4-6x): tuned so each peaks like the Collect / Whoosh cues. The place's UI click
-- templates (Click Sound / EggClick / Cash Tick) do not load in Studio, so no click layer.
local POP_VARIANTS = {"Bottle Pop", "Bottle Pop 2"}
local SPLASH_VARIANTS = {"Water Splash", "Water Splash 2"}
local function PlayPopSfx()
	SoundController.PlayFX("Bottle Pop", {Variants = POP_VARIANTS, Pitch = 0.06, Key = "BottlePop", MinInterval = 0.2})
end
local function PlayClickSfx()
	SoundController.PlayFX("Water Splash", {Variants = SPLASH_VARIANTS, Pitch = 0.05, Key = "BottleSplash", MinInterval = 0.15})
end

local gui = Instance.new("ScreenGui")
gui.Name = "BenchBonusGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 30
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("ImageButton")
button.Name = "BonusButton"
button.Image = "rbxassetid://72623643011499"
button.BackgroundTransparency = 1
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.ScaleType = Enum.ScaleType.Fit
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
bounds.MaxSize = Vector2.new(120, 120)
bounds.Parent = button
local scale = Instance.new("UIScale")
scale.Parent = button

-- Shares the bottle's pop-in, visibility, and rotation, with no gap below its bounds.
button.ClipsDescendants = false
local caption = Instance.new("TextLabel")
caption.Name = "ClickCaption"
caption.BackgroundTransparency = 1
caption.AnchorPoint = Vector2.new(0.5, 0)
caption.Position = UDim2.new(0.5, 0, 1, -2)
caption.Size = UDim2.fromScale(1.45, 0.32)
caption.Font = Enum.Font.FredokaOne
caption.Text = "Click me!"
caption.TextScaled = true
caption.TextColor3 = Color3.fromRGB(255, 255, 255)
caption.TextYAlignment = Enum.TextYAlignment.Top
caption.ZIndex = button.ZIndex + 1
caption.Parent = button
local captionStroke = Instance.new("UIStroke")
captionStroke.Color = Color3.fromRGB(30, 30, 40)
captionStroke.Thickness = 2.5
captionStroke.Parent = caption

local token, activeSeat, expiresAt
local popTween
local function Hide()
	token, activeSeat, expiresAt = nil, nil, nil
	button.Visible = false
	button.Active = false
	button:SetAttribute("OfferId", nil)
	if popTween then popTween:Cancel() popTween = nil end
end

local function OnBench(seat)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.Health > 0 and humanoid.SeatPart == seat
		and seat and seat:IsDescendantOf(workspace)
end

remote.OnClientEvent:Connect(function(action, offerId, seat, deadline)
	if action == "Hide" then
		if offerId == nil or offerId == token then Hide() end
		return
	end
	if action ~= "Show" or typeof(offerId) ~= "string" or typeof(deadline) ~= "number"
		or not OnBench(seat) or deadline <= workspace:GetServerTimeNow() then return end
	Hide()
	token, activeSeat, expiresAt = offerId, seat, deadline
	-- Keep clear of the edge controls and bottom movement/jump area on mobile.
	button.Position = UDim2.fromScale(random:NextNumber(0.28, 0.78), random:NextNumber(0.24, 0.62))
	button.Rotation = random:NextNumber(-8, 8)
	button:SetAttribute("OfferId", offerId)
	button.Visible = true
	button.Active = true
	scale.Scale = 0.35
	popTween = TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	popTween:Play()
	PlayPopSfx()
end)

button.Activated:Connect(function()
	local claim = token
	if not claim then return end
	local valid = OnBench(activeSeat) and workspace:GetServerTimeNow() < expiresAt
	Hide() -- immediately consume locally for mouse, touch, and controller
	if valid then
		PlayClickSfx()
		remote:FireServer(claim)
	end
end)

RunService.Heartbeat:Connect(function()
	if token and (not OnBench(activeSeat) or workspace:GetServerTimeNow() >= expiresAt) then Hide() end
end)
player.CharacterRemoving:Connect(Hide)
