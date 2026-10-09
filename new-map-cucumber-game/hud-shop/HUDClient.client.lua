--[[
	HUDClient  (LocalScript, StarterGui.CucumberHUDDesign)  2026-09-10
	Makes the authored HUD live:
	  * Counters.StrengthValue / CashValue follow player.Data.Strength / Cash (DataService's
	    NumberValues) in the "200.1M" style (always one decimal from 1000 up, NumberAbbrev suffixes) with a
	    little pop on every change
	  * NightTimer.TimeLabel counts down on the shared clock: workspace attributes CyclePhase /
	    PhaseEndsAt (DayNightCycle) against workspace:GetServerTimeNow()
	      Day   -> "in 4m 43s"   (until night)
	      Night -> "ends in 8s"
	  * Counters.AddStrength ("+") opens the shop on its Strength section: the button pops
	    (ButtonFX) and writes CucumberMenus attribute OpenRequest = "Shop:Strength#<n>", which
	    MenuController answers (RequestedTab -> ShopController scrolls there)
	Dev hook: CucumberHUDDesign attribute HUDDev = "plus" presses the + button.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))
local ButtonFX = require(Modules:WaitForChild("ButtonFX"))

local player = Players.LocalPlayer
local gui = script.Parent
local playerGui = gui.Parent
local counters = gui:WaitForChild("Counters")
local nightTimer = gui:WaitForChild("NightTimer")
local strengthLabel = counters:WaitForChild("StrengthValue")
local cashLabel = counters:WaitForChild("CashValue")
local addStrength = counters:WaitForChild("AddStrength")
local openStrengthShop = addStrength:WaitForChild("OpenStrengthShop")
local timeLabel = nightTimer:WaitForChild("TimeLabel")

local TIMER_STEP = 0.2
local POP_FROM = 1.18

--.. "200.1M": always one decimal (floored, never rounded up) from 1000 up, plain integers below
--.. (2026-09-18, user: "display the first decimal like 200.1M" - it used to drop it at 100+)
local function Compact(n)
	n = tonumber(n) or 0
	if n ~= n then return "0" end
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	if n < 1000 then return sign .. tostring(math.floor(n)) end -- floored too: 999.6 is "999", not "1000"
	local power = math.clamp(math.floor(math.log10(n) / 3), 1, #NumberAbbrev.SUFFIXES)
	local value = math.floor(n / 1000 ^ power * 10) / 10
	if value >= 1000 and power < #NumberAbbrev.SUFFIXES then -- never "1000.0K"
		power += 1
		value = math.floor(n / 1000 ^ power * 10) / 10
	end
	return sign .. string.format("%.1f", value) .. NumberAbbrev.SUFFIXES[power]
end

--.. Heartbeat-stepped (ButtonFX.Animate) so the pop also plays in an unfocused Studio
local popTokens = {}
local function Pop(label)
	local scale = label:FindFirstChild("PopScale")
	if not scale then return end
	local token = (popTokens[label] or 0) + 1
	popTokens[label] = token
	task.spawn(function()
		ButtonFX.Animate(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
			scale.Scale = POP_FROM + (1 - POP_FROM) * a
		end, function() return label.Parent ~= nil and popTokens[label] == token end)
		if popTokens[label] == token then scale.Scale = 1 end
	end)
end

local function Bind(valueName, label)
	local data = player:WaitForChild("Data", 60)
	local value = data and data:WaitForChild(valueName, 60)
	if not value then
		warn("[HUDClient] player.Data." .. valueName .. " never arrived")
		return
	end
	label.Text = Compact(value.Value)
	value.Changed:Connect(function()
		label.Text = Compact(value.Value)
		Pop(label)
	end)
end
task.spawn(Bind, "Strength", strengthLabel)
task.spawn(Bind, "Cash", cashLabel)

--..Night timer..--
local function FormatTime(seconds)
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 60 then return string.format("%dm %ds", seconds // 60, seconds % 60) end
	return string.format("%ds", seconds)
end
local function UpdateTimer()
	local phase = workspace:GetAttribute("CyclePhase")
	local endsAt = workspace:GetAttribute("PhaseEndsAt")
	local remaining = typeof(endsAt) == "number" and (endsAt - workspace:GetServerTimeNow()) or nil
	if phase == "Day" and remaining then
		timeLabel.Text = "in " .. FormatTime(remaining)
	elseif phase == "Night" and remaining then
		timeLabel.Text = "ends in " .. FormatTime(remaining)
	elseif phase == "PreparingDay" then
		timeLabel.Text = "dawn..."
	else
		timeLabel.Text = "soon"
	end
end
UpdateTimer()
local accumulator = TIMER_STEP
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < TIMER_STEP then return end
	accumulator = 0
	UpdateTimer()
end)
workspace:GetAttributeChangedSignal("CyclePhase"):Connect(UpdateTimer)

--..The "+" button -> Shop > Strength..--
local fxScale = ButtonFX.Prepare(addStrength)
local hoverInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
openStrengthShop.MouseEnter:Connect(function() TweenService:Create(fxScale, hoverInfo, {Scale = 1.08}):Play() end)
openStrengthShop.MouseLeave:Connect(function() TweenService:Create(fxScale, hoverInfo, {Scale = 1}):Play() end)

local requestCount = 0
local function OpenStrengthSection()
	ButtonFX.Press(addStrength)
	local menus = playerGui:FindFirstChild("CucumberMenus")
	if not menus then
		warn("[HUDClient] CucumberMenus is missing; cannot open the shop")
		return
	end
	requestCount += 1
	menus:SetAttribute("OpenRequest", ("Shop:Strength#%d"):format(requestCount))
end
openStrengthShop.Activated:Connect(OpenStrengthSection)

gui:GetAttributeChangedSignal("HUDDev"):Connect(function()
	local dev = gui:GetAttribute("HUDDev")
	if dev == "plus" then
		OpenStrengthSection()
		gui:SetAttribute("HUDDev", nil)
	end
end)
