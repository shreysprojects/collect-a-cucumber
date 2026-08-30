--[[
	RebirthArrowClient - the Arrow authored INSIDE the HUD Rebirth button
	(HUD.LeftRail["Group 300"].Rebirth.Arrow) bops side-to-side toward the
	button whenever the player can afford the next rebirth, and hides
	otherwise. Re-arms after every rebirth (cost goes up -> re-fetch).

	The arrow is a child of the button, so it follows the button and its
	ButtonScale/HudScaler scaling for free - no per-frame repositioning
	(the old version chased the retired Display rail with RenderStepped).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Network = require(ReplicatedStorage.Modules.ControllerLoader).GetController("Network")

local pg = player:WaitForChild("PlayerGui")
local hud = pg:WaitForChild("HUD", 20)
if not hud then
	warn("[RebirthArrowClient] HUD was not replicated; hint disabled")
	return
end
local button = hud:WaitForChild("LeftRail"):WaitForChild("Group 300"):WaitForChild("Rebirth")
local arrow = button:WaitForChild("Arrow")

local leaderstats = player:WaitForChild("leaderstats", 30)
local cukes = leaderstats and leaderstats:WaitForChild("Cukes")
local rebirthStat = leaderstats and leaderstats:FindFirstChild("Rebirths")

arrow.Visible = false -- saved visible so it can be edited in Studio

--== bop tween: slide toward the button and back, forever while visible =======
local HOME = arrow.Position
local BOP = UDim2.new(HOME.X.Scale, HOME.X.Offset - 14, HOME.Y.Scale, HOME.Y.Offset)
local tween = TweenService:Create(
	arrow,
	TweenInfo.new(0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Position = BOP }
)

local function setVisible(on)
	if arrow.Visible == on then return end
	arrow.Visible = on
	if on then
		arrow.Position = HOME
		tween:Play()
	else
		tween:Cancel() -- don't tween while hidden (perf) and restart clean next time
		arrow.Position = HOME
	end
end

--== affordability ============================================================
local nextCost = nil

local function fetch()
	local ok, info = pcall(function() return Network:InvokeServer("GetRebirthInfo") end)
	if ok and info then
		nextCost = info.Cost
		setVisible(info.CanAfford == true)
	end
end

--.. cheap live check between fetches: compare the Cukes stat to the known cost
if cukes then
	cukes.Changed:Connect(function(v)
		if nextCost then setVisible(v >= nextCost) end
	end)
end

--.. the cost jumps right after a rebirth; re-fetch instead of waiting the poll out
if rebirthStat then
	rebirthStat.Changed:Connect(function()
		task.defer(fetch)
	end)
end

task.spawn(function()
	while true do
		fetch()
		task.wait(12)
	end
end)
