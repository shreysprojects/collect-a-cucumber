--[[---------------------------------------DESCRIPTION------------------------------------------
	Only LocalScript. Waits for the server, loads Variables, then sets up UIs
	and routes incoming ReEvent calls.

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

repeat
	task.wait()
until ReplicatedStorage.Assets.GameInfo.ServerReady.Value

local vars = require(script.Utilities.Variables)
local func = vars.Functions
local placeInfo = vars.PlaceInfo
local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local UIUtils = require(ReplicatedStorage.Assets.Modules.Client.UI.UIUtils)

print("[CLIENT]: You're in:", placeInfo.Index)

func.GUIFramework:SetupUIs()
if func.SetupPlayerProgress then
	func:SetupPlayerProgress()
end

local BUTTON_Y = 0.86 -- above the HUD level bar (y 0.88-0.98)
local STOP_SIZE = Vector2.new(260, 80)
local STEER_SIZE = Vector2.new(100, 80)
local STEER_GAP = 16

local function styleButton(button, text, background, strokeColor, position, size, anchor, textSize)
	button.AnchorPoint = anchor or Vector2.new(0.5, 1)
	button.Position = position or UDim2.new(0.5, 0, BUTTON_Y, 0)
	button.Size = size or UDim2.fromOffset(STOP_SIZE.X, STOP_SIZE.Y)
	button.BackgroundColor3 = background
	button.BorderSizePixel = 0
	button.Font = Enum.Font.SourceSansBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(28, 48, 72)
	button.TextSize = textSize or 32
	button.ZIndex = 10
	button.Active = true
	button.AutoButtonColor = true
	button.Selectable = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = strokeColor
	stroke.Parent = button
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

-- Launching is hold-to-charge now (CLIENT_Snowball.SetupChargeLaunch).
-- Ride controls: Left / Stop / Right, created here so they sit above the HUD.
local stopButton = Instance.new("TextButton")
stopButton.Name = "Stop"
stopButton.Visible = false
stopButton.Parent = gui
styleButton(stopButton, "Stop", Color3.fromRGB(255, 214, 214), Color3.fromRGB(200, 110, 110))

local steerOffset = STOP_SIZE.X / 2 + STEER_GAP
local steerColor = Color3.fromRGB(214, 236, 255)
local steerStroke = Color3.fromRGB(90, 140, 190)

local leftButton = Instance.new("TextButton")
leftButton.Name = "Left"
leftButton.Visible = false
leftButton.Parent = gui
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
rightButton.Parent = gui
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

