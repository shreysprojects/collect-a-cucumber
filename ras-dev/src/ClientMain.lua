--[[---------------------------------------DESCRIPTION------------------------------------------
	Only LocalScript. Waits for the server, loads Variables, then sets up UIs
	and routes incoming ReEvent calls.

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Before the ServerReady wait; a missing guard must not stop the rest of the client.
local guardOk, guardErr = pcall(function()
	require(ReplicatedStorage.Assets.Modules.Client.Functions.ClientFunctions.Modules.CLIENT_SpawnGuard):StartSpawnGuard()
end)
if not guardOk then
	warn("[CLIENT]: CLIENT_SpawnGuard not started:", guardErr)
end

repeat
	task.wait()
until ReplicatedStorage.Assets.GameInfo.ServerReady.Value

local vars = require(script.Utilities.Variables)
local func = vars.Functions
local placeInfo = vars.PlaceInfo
local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local UIUtils = require(ReplicatedStorage.Assets.Modules.Client.UI.UIUtils)
local HUDLayout = require(ReplicatedStorage.Assets.Modules.Client.UI.HUDLayout)
local Audio = require(ReplicatedStorage.Assets.Modules.Client.Audio)

print("[CLIENT]: You're in:", placeInfo.Index)

func.GUIFramework:SetupUIs()
Audio.Start(vars)
if func.SetupPlayerProgress then
	func:SetupPlayerProgress()
end

local BUTTON_Y = 1 -- bottom of the uniformly scaled ride-control group
local STOP_SIZE = Vector2.new(160, 44)
local STEER_SIZE = Vector2.new(44, 44)
local STEER_GAP = 35

local function styleButton(button, text, background, strokeColor, position, size, anchor, textSize)
	button.AnchorPoint = anchor or Vector2.new(0.5, 1)
	button.Position = position or UDim2.new(0.5, 0, BUTTON_Y, 0)
	button.Size = size or UDim2.fromOffset(STOP_SIZE.X, STOP_SIZE.Y)
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.ZIndex = 10
	button.Active = true
	button.AutoButtonColor = false
	button.Selectable = false
	for _, child in button:GetChildren() do
		if child:IsA("UICorner") or child:IsA("UIStroke") or child:IsA("UIGradient") or child.Name == "Face" or child.Name == "Label" then
			child:Destroy()
		end
	end
	if button.Name == "Stop" then
		button.Text = ""
		local face = Instance.new("Frame")
		face.Name = "Face"
		face.Size = UDim2.fromScale(1, 1)
		face.BackgroundColor3 = Color3.new(1, 1, 1)
		face.BorderSizePixel = 0
		face.ZIndex = 10
		face.Parent = button
		local corner = Instance.new("UICorner", face)
		corner.CornerRadius = UDim.new(0, 8)
		local outline = Instance.new("UIStroke", face)
		outline.Thickness = 3
		outline.Color = Color3.fromRGB(24, 24, 28)
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local gradient = Instance.new("UIGradient", face)
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(Color3.fromRGB(255, 69, 61), Color3.fromRGB(219, 14, 17))
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.Text = "STOP"
		label.TextSize = 26
		label.TextColor3 = Color3.new(1, 1, 1)
		label.ZIndex = 12
		label.Parent = button
		local textOutline = Instance.new("UIStroke", label)
		textOutline.Thickness = 2
		textOutline.Color = Color3.fromRGB(24, 24, 28)
	else
		button.Font = Enum.Font.SourceSansBold
		button.Text = text
		button.TextColor3 = Color3.fromRGB(245, 250, 252)
		button.TextSize = 44
		button.TextStrokeTransparency = 1
		local outline = Instance.new("UIStroke", button)
		outline.Thickness = 3
		outline.Color = Color3.fromRGB(39, 51, 56)
		outline.LineJoinMode = Enum.LineJoinMode.Round
	end
end

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("LaunchGui")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "LaunchGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true
gui.Parent = playerGui

local rideControls = Instance.new("Frame")
rideControls.Name = "RideControls"
rideControls.BackgroundTransparency = 1
rideControls.BorderSizePixel = 0
rideControls.Parent = gui
HUDLayout.BindRide(rideControls, gui)

-- Launching is hold-to-charge now (CLIENT_Snowball.SetupChargeLaunch).
-- Ride controls: Left / Stop / Right, created here so they sit above the HUD.
local stopButton = Instance.new("TextButton")
stopButton.Name = "Stop"
stopButton.Visible = false
stopButton.Parent = rideControls
styleButton(stopButton, "Stop", Color3.fromRGB(255, 214, 214), Color3.fromRGB(200, 110, 110))

local steerOffset = STOP_SIZE.X / 2 + STEER_GAP
local steerColor = Color3.fromRGB(214, 236, 255)
local steerStroke = Color3.fromRGB(90, 140, 190)

local leftButton = Instance.new("TextButton")
leftButton.Name = "Left"
leftButton.Visible = false
leftButton.Parent = rideControls
styleButton(
	leftButton,
	"◀",
	steerColor,
	steerStroke,
	UDim2.new(0.5, -steerOffset, BUTTON_Y, 0),
	UDim2.fromOffset(STEER_SIZE.X, STEER_SIZE.Y),
	Vector2.new(1, 1),
	40
)

local rightButton = Instance.new("TextButton")
rightButton.Name = "Right"
rightButton.Visible = false
rightButton.Parent = rideControls
styleButton(
	rightButton,
	"▶",
	steerColor,
	steerStroke,
	UDim2.new(0.5, steerOffset, BUTTON_Y, 0),
	UDim2.fromOffset(STEER_SIZE.X, STEER_SIZE.Y),
	Vector2.new(0, 1),
	40
)

stopButton.MouseButton1Click:Connect(function()
	func:StopRide()
end)

vars.LaunchGui = gui
vars.StopButton = stopButton
vars.LeftButton = leftButton
vars.RightButton = rightButton
if func.SetupSteer then
	func:SetupSteer()
end
func:WatchLaunchPad()
if func.SetupChargeLaunch then
	func:SetupChargeLaunch()
end
if func.StartLauncherObservers then
	func:StartLauncherObservers()
end
if func.StartSnowballFX then
	func:StartSnowballFX()
end
if func.SetupRaceProgress then
	func:SetupRaceProgress()
end
UIUtils.bindHoverScaleAll(playerGui, nil, true)

print("[CLIENT]: Launch controls ready")

ReplicatedStorage.ReEvent.OnClientEvent:Connect(function(mode, ...)
	if vars.Functions[mode] then
		if type(vars.Functions[mode]) == "table" then
			local args = { ... }
			local funcName = table.remove(args, 1)
			vars.Functions[mode][funcName](vars.Functions[mode], table.unpack(args))
		else
			vars.Functions[mode](vars.Functions, ...)
		end
	end
end)

print("[CLIENT]: Client finished loading")

