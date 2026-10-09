--[[
	HUDClient  (LocalScript, StarterGui.CucumberHUDDesign)  2026-09-10
	Makes the authored HUD live:
	  * Counters.StrengthValue / CashValue follow player.Data.Strength / Cash (DataService's
	    NumberValues) in the "189.9M" style (one decimal above 1000, NumberAbbrev suffixes) with a
	    pop on changes; strength bounces only when the formatted display changes
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

--.. "189.9M": one decimal above 1000 (the design's sample), plain integers below
local function Compact(n)
	n = tonumber(n) or 0
	if n ~= n then return "0" end
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	if n < 1000 then return sign .. tostring(math.floor(n + 0.5)) end
	local power = math.min(math.floor(math.log10(n) / 3), #NumberAbbrev.SUFFIXES)
	local value = n / 1000 ^ power
	local text
	if value >= 100 then
		text = string.format("%d", math.floor(value))
	else
		text = string.format("%.1f", math.floor(value * 10) / 10):gsub("%.0$", "")
	end
	return sign .. text .. NumberAbbrev.SUFFIXES[power]
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

-- Bounce all three strength elements together without moving the cash row.
local strengthItems = {strengthLabel, counters:WaitForChild("StrengthIcon"), addStrength}
local strengthRest = {}
for _, item in strengthItems do strengthRest[item] = item.Position end
-- Each formatted-number change energizes a quick, small spring oscillation.
-- New changes preserve its direction, so rapid gains never pin it at the top.
local strengthOffset, strengthVelocity = 0, 0
local strengthSpringActive, lastStrengthChange = false, 0
local strengthScale = strengthLabel:FindFirstChild("PopScale")

-- Enlarge the whole strength row at the bench while keeping the cash row unchanged.
local strengthAuthoredPositions, strengthAuthoredSizes = {}, {}
for _, item in strengthItems do
    strengthAuthoredPositions[item] = item.Position
    strengthAuthoredSizes[item] = item.Size
end
local function UpdateBenchStrengthSize()
    local factor = gui:GetAttribute("BenchMode") == true and 1.1 or 1
    local pivotY = 0.245
    for _, item in strengthItems do
        local pos, size = strengthAuthoredPositions[item], strengthAuthoredSizes[item]
        local rest = UDim2.new(pos.X.Scale * factor, pos.X.Offset * factor,
            pivotY + (pos.Y.Scale - pivotY) * factor, pos.Y.Offset * factor)
        strengthRest[item] = rest
        item.Size = UDim2.new(size.X.Scale * factor, size.X.Offset * factor,
            size.Y.Scale * factor, size.Y.Offset * factor)
        item.Position = rest + UDim2.fromScale(0, strengthOffset)
    end
end
local benchStrengthSizeConnection = gui:GetAttributeChangedSignal("BenchMode"):Connect(UpdateBenchStrengthSize)
UpdateBenchStrengthSize()
script.Destroying:Connect(function() benchStrengthSizeConnection:Disconnect() end)

local function BounceStrength()
    strengthVelocity = strengthVelocity > 0 and 4.2 or -4.2
    lastStrengthChange = os.clock()
    strengthSpringActive = true
end
local strengthSpringConnection = RunService.Heartbeat:Connect(function(dt)
    if not strengthSpringActive then return end
    local remaining = math.min(dt, 0.05)
    while remaining > 0 do
        local step = math.min(remaining, 1 / 240)
        strengthVelocity += (-4900 * strengthOffset - 30 * strengthVelocity) * step
        strengthOffset += strengthVelocity * step
        strengthOffset = math.clamp(strengthOffset, -0.065, 0.065)
        remaining -= step
    end
    if os.clock() - lastStrengthChange > 0.36 then
        strengthOffset, strengthVelocity = 0, 0
        strengthSpringActive = false
    end
    for _, item in strengthItems do
        item.Position = strengthRest[item] + UDim2.fromScale(0, strengthOffset)
    end
    if strengthScale then strengthScale.Scale = 1 + math.max(0, -strengthOffset) * 2.4 end
end)
script.Destroying:Connect(function() strengthSpringConnection:Disconnect() end)

local function Bind(valueName, label)
	local data = player:WaitForChild("Data", 60)
	local value = data and data:WaitForChild(valueName, 60)
	if not value then
		warn("[HUDClient] player.Data." .. valueName .. " never arrived")
		return
	end
	label.Text = Compact(value.Value)
    value.Changed:Connect(function()
        local nextText = Compact(value.Value)
        local displayChanged = nextText ~= label.Text
        label.Text = nextText
        if valueName == "Strength" then
            if displayChanged then
                BounceStrength()
            end
        else
            Pop(label)
        end
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

-- White radial rays spin behind the bench offer's strength icon while visible.
local benchOffer = gui.LeftMenu:WaitForChild("BenchStrength")
local rays = benchOffer:WaitForChild("RayClip"):WaitForChild("Sunburst")
local rayConnection = RunService.Heartbeat:Connect(function(dt)
    if benchOffer.Visible then rays.Rotation = (rays.Rotation + 18 * dt) % 360 end
end)
script.Destroying:Connect(function() rayConnection:Disconnect() end)
