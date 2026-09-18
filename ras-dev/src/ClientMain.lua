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

print("[CLIENT]: You're in:", placeInfo.Index)

func.GUIFramework:SetupUIs()

local function styleButton(button, text, background, strokeColor)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -40)
	button.Size = UDim2.fromOffset(260, 80)
	button.BackgroundColor3 = background
	button.BorderSizePixel = 0
	button.Font = Enum.Font.SourceSansBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(28, 48, 72)
	button.TextSize = 32
	button.ZIndex = 10
	button.Active = true

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

-- Launching is hold-to-charge now (CLIENT_Snowball.SetupChargeLaunch); only Stop stays.
local stopButton = Instance.new("TextButton")
stopButton.Name = "Stop"
stopButton.Visible = false
stopButton.Parent = gui
styleButton(stopButton, "Stop", Color3.fromRGB(255, 214, 214), Color3.fromRGB(200, 110, 110))

stopButton.MouseButton1Click:Connect(function()
	func:StopRide()
end)

vars.LaunchGui = gui
vars.StopButton = stopButton
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

