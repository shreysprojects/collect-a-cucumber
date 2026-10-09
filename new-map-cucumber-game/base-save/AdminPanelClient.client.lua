--[[
	AdminPanelClient  (LocalScript, StarterGui.AdminPanel)
	The admin panel (user, 2026-09-12): an "ADMIN" button at the top right opens a panel with
	START DAY / START NIGHT, CASH [box] SET, STRENGTH [box] SET and RESET DATA (press twice within
	5 s). Every press goes to Remotes.AdminAction (AdminService), which answers ok, message; the
	message lands in the panel's Status line and as a Notify toast. Only the players in ADMINS see
	the panel (the ScreenGui destroys itself for anyone else); the server checks the same list.
	Sized in pixels under one UIScale (Root.Fit, 720 px tall = 1.0, clamped 0.7 .. 1.2).
	Dev hook: the ScreenGui attribute AdminDev = "toggle" | "day" | "night" | "cash:<n>" |
	"strength:<n>" | "reset" (two writes arm + fire, like the button).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ADMINS = {[140977250] = true} -- awesomeotheraccount (keep in step with AdminService)
local RESET_WINDOW = 5 -- seconds the second RESET press must come within
local OK_COLOR = Color3.fromRGB(150, 235, 120)
local BAD_COLOR = Color3.fromRGB(255, 120, 120)
local IDLE_COLOR = Color3.fromRGB(200, 205, 220)

local player = Players.LocalPlayer
local gui = script.Parent
if not ADMINS[player.UserId] then
	gui:Destroy()
	return
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ButtonFX = require(Modules:WaitForChild("ButtonFX"))
local Notify = require(Modules:WaitForChild("Notify"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AdminAction", 60)

local root = gui:WaitForChild("Root")
local fit = root:WaitForChild("Fit")
local toggle = root:WaitForChild("Toggle")
local panel = root:WaitForChild("Panel")
local status = panel:WaitForChild("Status")
local resetButton = panel:WaitForChild("ResetButton")
local resetLabel = resetButton:WaitForChild("Label")

local function Fit()
	fit.Scale = math.clamp(gui.AbsoluteSize.Y / 720, 0.7, 1.2)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(Fit)
Fit()

for _, name in ipairs({"DayButton", "NightButton", "CashSet", "StrengthSet", "ResetButton"}) do
	ButtonFX.Prepare(panel:WaitForChild(name))
end
ButtonFX.Prepare(toggle)

local busy = false
local function Call(button, action, value)
	if busy then return false end
	if not remote then
		status.Text = "AdminService is not running"
		status.TextColor3 = BAD_COLOR
		return false
	end
	busy = true
	ButtonFX.Press(button)
	local ok, result, message = pcall(remote.InvokeServer, remote, action, value)
	busy = false
	if not ok then result, message = false, "No answer from the server" end
	message = tostring(message or (result and "Done" or "Failed"))
	status.Text = message
	status.TextColor3 = result and OK_COLOR or BAD_COLOR
	if result then
		ButtonFX.Success(button)
		Notify.Success(message)
	else
		ButtonFX.Fail(button)
		Notify.Error(message)
	end
	return result == true
end

local function SetVisible(on)
	panel.Visible = on
	if on then
		status.Text = ""
		status.TextColor3 = IDLE_COLOR
	end
end

toggle.Press.Activated:Connect(function()
	ButtonFX.Press(toggle)
	SetVisible(not panel.Visible)
end)
panel.Close.Press.Activated:Connect(function() SetVisible(false) end)

panel.DayButton.Press.Activated:Connect(function() Call(panel.DayButton, "day") end)
panel.NightButton.Press.Activated:Connect(function() Call(panel.NightButton, "night") end)

local function SetNumber(action, box, button)
	Call(button, action, box.Text)
end
panel.CashSet.Press.Activated:Connect(function() SetNumber("cash", panel.CashBox, panel.CashSet) end)
panel.StrengthSet.Press.Activated:Connect(function() SetNumber("strength", panel.StrengthBox, panel.StrengthSet) end)
panel.CashBox.FocusLost:Connect(function(enter) if enter then SetNumber("cash", panel.CashBox, panel.CashSet) end end)
panel.StrengthBox.FocusLost:Connect(function(enter) if enter then SetNumber("strength", panel.StrengthBox, panel.StrengthSet) end end)

--.. reset: arm on the first press, fire on the second within RESET_WINDOW
local armedUntil = 0
local function Disarm()
	armedUntil = 0
	resetLabel.Text = "RESET DATA"
end
local function PressReset()
	local now = os.clock()
	if now < armedUntil then
		Disarm()
		Call(resetButton, "reset")
		return
	end
	armedUntil = now + RESET_WINDOW
	resetLabel.Text = "SURE? PRESS AGAIN"
	status.Text = "Press RESET again within 5 s to wipe cash, strength, plot level, base and pets"
	status.TextColor3 = BAD_COLOR
	ButtonFX.Press(resetButton)
	task.delay(RESET_WINDOW, function()
		if os.clock() >= armedUntil and armedUntil ~= 0 then Disarm() end
	end)
end
resetButton.Press.Activated:Connect(PressReset)

--..Studio dev hook..--
gui:GetAttributeChangedSignal("AdminDev"):Connect(function()
	local cmd = gui:GetAttribute("AdminDev")
	if type(cmd) ~= "string" or cmd == "" then return end
	gui:SetAttribute("AdminDev", nil)
	if cmd == "toggle" then SetVisible(not panel.Visible)
	elseif cmd == "day" then Call(panel.DayButton, "day")
	elseif cmd == "night" then Call(panel.NightButton, "night")
	elseif cmd:sub(1, 6) == "cash:" then panel.CashBox.Text = cmd:sub(7) SetNumber("cash", panel.CashBox, panel.CashSet)
	elseif cmd:sub(1, 9) == "strength:" then panel.StrengthBox.Text = cmd:sub(10) SetNumber("strength", panel.StrengthBox, panel.StrengthSet)
	elseif cmd == "reset" then PressReset()
	end
end)
