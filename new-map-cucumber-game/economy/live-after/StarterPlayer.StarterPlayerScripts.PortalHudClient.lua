--[[
	PortalHudClient  (LocalScript, StarterPlayerScripts)
	Timer and Return Home UI adapted from Zombie Cucumber Game's MinigameHudController.

	2026-09-22 (user: "hud glitches with portal hud"): the minigame HUD sat on fixed screen fractions,
	so the run timer and the map name were drawn straight over the main HUD's Strength / Cash counters
	(CucumberHUDDesign.Counters, top centre) and the Return Home button over the Hotbar's first slot
	(bottom centre). Now both stacks are laid out every frame from the real rectangles:
	  * Timer, then MapName (or the night countdown), GAP px under the counters' bottom edge
	  * the Return Home caption GAP px above the Hotbar bar, the house button on top of the caption
	The ScreenGui respects the GUI inset like CucumberHUDDesign and the Hotbar, so all three share one
	coordinate space, and its DisplayOrder is DISPLAY_ORDER (was 9000): above the HUD, under BuildMenu,
	CucumberMenus and GameNotify, so an open Shop / Index panel or a toast covers it instead of the
	timer drawing on top of them. The top stack's bottom edge is published as the MinigameHUD
	attribute StackBottom (px) for DesertHuntClient's "Rats: x / y" line.

	2026-09-22 (later, user: "hide top indicators during minigame to bring the minigame timer up"): the
	counters are hidden for the whole run and the timer starts at the counters' top edge instead of under
	them; they come back when the run ends.

	Night rules (PortalService, same day) arrive on MinigameHudRemotes.StateChanged:
	  "Blocked", text       -> Notify.Error(text)  ("Portals are blocked 1 min before night!")
	  "Reward", text        -> Notify.Success(text) ("Portal cleared! +$48K", 2026-09-23 economy: PortalService.PORTAL_REWARDS)
	  "NightWarning", left  -> Notify.Warn toast; the MapName line is also swapped for a live
	                           "Night in Ns!" countdown whenever the day has WarnBeforeNight s left
	The server brings the player home as night falls (its ReturnLead seconds early).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("MinigameHudRemotes")
local goHome = remotes:WaitForChild("GoHome")
local stateChanged = remotes:WaitForChild("StateChanged")
local Notify = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Notify"))

local GAP = 6 -- px between the minigame HUD and the main HUD pieces it stacks against
local DISPLAY_ORDER = 22 -- CucumberHUDDesign 20 < this < BuildMenu 25 < CucumberMenus 60 < GameNotify 2000
local WARN_TOAST_SECONDS = 3.5

local gui = Instance.new("ScreenGui")
gui.Name = "MinigameHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local function label(name, color, maxSize)
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.fromScale(0.5, 0)
	text.Size = UDim2.fromScale(0.72, 0.05)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = color
	text.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 26)
	stroke.Thickness = 3
	stroke.Parent = text
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize, size.MinTextSize = maxSize, 9
	size.Parent = text
	return text
end
local timer = label("Timer", Color3.new(1, 1, 1), 66)
timer.Text = "00:00.00"
local title = label("MapName", Color3.fromRGB(255, 221, 64), 30)
local nightLine = label("NightWarning", Notify.COLORS.Warn, 30)
nightLine.Visible = false

local home = Instance.new("ImageButton")
home.Name = "Home"
home.AnchorPoint = Vector2.new(0.5, 1)
home.Position = UDim2.fromScale(0.5, 0.92)
home.Size = UDim2.fromOffset(70, 70)
home.BackgroundTransparency = 1
home.Image = "rbxassetid://15403180857"
home.ScaleType = Enum.ScaleType.Fit
home.AutoButtonColor = false
home.Parent = gui
local scale = Instance.new("UIScale")
scale.Parent = home
local caption = label("ReturnHome", Color3.new(1, 1, 1), 24)
caption.AnchorPoint = Vector2.new(0.5, 1)
caption.Text = "Return Home"
local lastRequest = 0
home.Activated:Connect(function()
	if os.clock() - lastRequest < 0.3 then return end
	lastRequest = os.clock()
	goHome:FireServer()
end)
home.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.12), {Scale = 1.1}):Play() end)
home.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.12), {Scale = 1}):Play() end)

--..Layout: stacked against the real main-HUD rectangles..--
local function px(screenH, fraction, low, high)
	return math.floor(math.clamp(screenH * fraction, low, high) + 0.5)
end

local function layout()
	local origin = gui.AbsolutePosition.Y
	local screenH = gui.AbsoluteSize.Y
	if screenH <= 0 then
		local camera = workspace.CurrentCamera
		screenH = (camera and camera.ViewportSize.Y or 720) - GuiService:GetGuiInset().Y
	end
	-- top: the Strength / Cash counters are hidden during a run (see setCountersHidden), so the timer
	-- takes the counters' own top edge
	local top = 14
	local hud = playerGui:FindFirstChild("CucumberHUDDesign")
	local counters = hud and hud:FindFirstChild("Counters")
	if counters and counters.AbsoluteSize.Y > 0 then
		top = math.floor(counters.AbsolutePosition.Y - origin + 0.5)
	end
	local timerH = px(screenH, 0.09, 30, 64)
	local lineH = px(screenH, 0.045, 16, 30)
	timer.Position = UDim2.new(0.5, 0, 0, top)
	timer.Size = UDim2.new(0.72, 0, 0, timerH)
	local lineY = top + timerH + 2
	title.Position = UDim2.new(0.5, 0, 0, lineY)
	title.Size = UDim2.new(0.72, 0, 0, lineH)
	nightLine.Position = title.Position
	nightLine.Size = title.Size
	local bottom = lineY + lineH
	if gui:GetAttribute("StackBottom") ~= bottom then gui:SetAttribute("StackBottom", bottom) end
	-- bottom: the caption just above the hotbar, the house button on top of it
	local floor = screenH - GAP
	local hotbar = playerGui:FindFirstChild("Hotbar")
	local bar = hotbar and hotbar:FindFirstChild("Bar")
	if bar and bar.AbsoluteSize.Y > 0 then floor = math.floor(bar.AbsolutePosition.Y - origin - GAP + 0.5) end
	local captionH = px(screenH, 0.038, 14, 24)
	local homeH = px(screenH, 0.1, 44, 84)
	caption.Position = UDim2.new(0.5, 0, 0, floor)
	caption.Size = UDim2.new(0.72, 0, 0, captionH)
	home.Position = UDim2.new(0.5, 0, 0, floor - captionH)
	home.Size = UDim2.fromOffset(homeH, homeH)
end

--..Night countdown on the shared clock (DayNightCycle: CyclePhase / PhaseEndsAt)..--
local function secondsToNight()
	if workspace:GetAttribute("CyclePhase") ~= "Day" then return nil end
	local endsAt = workspace:GetAttribute("PhaseEndsAt")
	if typeof(endsAt) ~= "number" then return nil end
	return endsAt - workspace:GetServerTimeNow()
end
local function warnWindow()
	local value = remotes:GetAttribute("WarnBeforeNight")
	return typeof(value) == "number" and value or 30
end
local function nightText(left)
	return ("Night in %ds! You'll be sent home"):format(math.max(0, math.ceil(left)))
end

-- 2026-09-22 (user: "hide top indicators during minigame to bring the minigame timer up"): the HUD's
-- Strength / Cash counters are hidden for the run and shown again when it ends
local hiddenCounters -- the Counters frame this script hid
local function setCountersHidden(hide)
	if hide then
		local hud = playerGui:FindFirstChild("CucumberHUDDesign")
		local counters = hud and hud:FindFirstChild("Counters")
		if counters and counters.Visible then
			counters.Visible = false
			hiddenCounters = counters
		end
	elseif hiddenCounters then
		if hiddenCounters.Parent then hiddenCounters.Visible = true end
		hiddenCounters = nil
	end
end

local ticker
local function update()
	local active = player:GetAttribute("InPortalMinigame") == true
	gui.Enabled = active
	setCountersHidden(active)
	if ticker then ticker:Disconnect() ticker = nil end
	if not active then return end
	title.Text = player:GetAttribute("MinigameName") or "Minigame"
	local function tick()
		local start = player:GetAttribute("MinigameRunStart")
		local t = start and math.max(0, workspace:GetServerTimeNow() - start) or 0
		timer.Text = string.format("%02d:%02d.%02d", math.floor(t / 60), math.floor(t % 60), math.floor(t * 100) % 100)
		local left = secondsToNight()
		local warning = left ~= nil and left > 0 and left <= warnWindow()
		if warning then nightLine.Text = nightText(left) end
		nightLine.Visible = warning
		title.Visible = not warning
		layout()
	end
	tick()
	ticker = RunService.RenderStepped:Connect(tick)
end
player:GetAttributeChangedSignal("InPortalMinigame"):Connect(update)
player:GetAttributeChangedSignal("MinigameName"):Connect(update)
update()

--..Night rules from PortalService..--
stateChanged.OnClientEvent:Connect(function(kind, value)
	if kind == "Blocked" then
		Notify.Error(tostring(value or "Portals are blocked 1 min before night!"))
	elseif kind == "NightWarning" then
		Notify.Warn(nightText(tonumber(value) or warnWindow()) .. ".", WARN_TOAST_SECONDS)
	elseif kind == "Reward" then -- 2026-09-23 economy: "Portal cleared! +$48K" after a finished run (PortalService.PORTAL_REWARDS)
		Notify.Success(tostring(value or "Portal cleared!"))
	end
end)
