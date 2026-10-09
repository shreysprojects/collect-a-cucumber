--[[
	BenchBoardClient  (LocalScript, StarterPlayerScripts)
	Fills every plot's bench upgrade board (models tagged "BenchUpgradeBoard", attribute Plot = plot
	name; PlotUpgradeService stands one by each plot. SurfaceGui "BoardGui" on the Face part:
	Bg > Title / Level / Button (Cash, Cost) / RobuxButton (Price)).
	A board shows ITS PLOT OWNER's bench level from the plot attributes GymService.SyncPlot keeps
	(BenchLevel, BenchCost = Cash to the next level or 0 at max); the Robux price comes from the
	GymBoardState remote. Only the owner can press: cash button -> ("Buy", "BenchPress"), Robux
	button -> ("Robux", "BenchPress") through GymBoardAction. Green = you can press, red = cannot (not
	your plot / cannot afford), grey = maxed; the Robux button is always green (user 2026-09-06). One
	bench level doubles strength per rep; rep speed follows GymService.REP_SPEEDS.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlotUpgrades = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlotUpgrades")) -- for Abbrev
local ButtonFX = require(ReplicatedStorage.Modules:WaitForChild("ButtonFX")) -- press / success / fail pops + level-up burst (user 2026-09-07)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StateEvent = Remotes:WaitForChild("GymBoardState")
local ActionFunction = Remotes:WaitForChild("GymBoardAction")
local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

local BOARD_TAG = "BenchUpgradeBoard"
local UPGRADE_ID = "BenchPress"
local FALLBACK_ROBUX = 625
local RED = Color3.fromRGB(228, 40, 40)
local RED_DARK = Color3.fromRGB(122, 14, 14)
local GREEN = Color3.fromRGB(58, 196, 72)
local GREEN_DARK = Color3.fromRGB(22, 104, 34)
local GREY = Color3.fromRGB(105, 105, 112)
local GREY_DARK = Color3.fromRGB(55, 55, 60)
local Notify = require(ReplicatedStorage.Modules:WaitForChild("Notify")) -- the game-wide notification style (user 2026-09-07)
local OK_COLOR = Notify.COLORS.Success
local FAIL_COLOR = Notify.COLORS.Error

local state = nil -- last GymBoardState (Cash, Bench.RobuxPrice)
local cashValue = nil
local boards = {} -- [model] = {Plot, Level, Button, Rim, Cost, Robux, RobuxRim, Price, Conns}

--..Toast: the game-wide notification style (ReplicatedStorage.Modules.Notify, user 2026-09-07)..--
local function Toast(text, color)
	Notify.Show(text, color)
end

--..Rendering..--
--.. button state colour: background + rim stroke, the label strokes inside it, and any arrow icon
--.. frames (Icon > Bar / Tip), so a green button never carries red trim
local function Paint(button, rim, color, dark)
	button.BackgroundColor3 = color
	if rim then rim.Color = dark end
	for _, d in ipairs(button:GetDescendants()) do
		if d:IsA("UIStroke") and d ~= rim and d.Parent:IsA("TextLabel") then
			d.Color = dark
		elseif d:IsA("Frame") and (d.Name == "Bar" or d.Name == "Tip") then
			d.BackgroundColor3 = color
		end
	end
end

local function Render(model)
	local info = boards[model]
	if not info then return end
	local plot = info.Plot
	local level = math.max(1, math.floor(tonumber(plot:GetAttribute("BenchLevel")) or 1))
	local cost = tonumber(plot:GetAttribute("BenchCost")) or 0
	local mine = plot:GetAttribute("Owner") == player.UserId
	local cash = cashValue and cashValue.Value or (state and state.Cash) or 0
	local canBuy = false
	if cost > 0 then
		info.Level.Text = ("Level %d > Level %d"):format(level, level + 1)
		info.Cost.Text = "$" .. PlotUpgrades.Abbrev(cost)
		canBuy = mine and cash >= cost
	else
		info.Level.Text = ("Level %d  (MAX)"):format(level)
		info.Cost.Text = "MAXED"
	end
	--.. green = you can press, red = cannot (not enough Cash / not your plot), grey = maxed (user 2026-09-06)
	local color, dark = GREY, GREY_DARK
	if cost > 0 then
		if canBuy then color, dark = GREEN, GREEN_DARK else color, dark = RED, RED_DARK end
	end
	Paint(info.Button, info.Rim, color, dark)
	info.Button.Active = cost > 0
	local price = state and state.Bench and state.Bench.RobuxPrice or FALLBACK_ROBUX
	info.Price.Text = tostring(price)
	Paint(info.Robux, info.RobuxRim, GREEN, GREEN_DARK) -- the Robux button is always green (user 2026-09-06)
	info.Robux.Active = cost > 0
end

local function RenderAll()
	for model in pairs(boards) do Render(model) end
end

local function Press(model, kind)
	local info = boards[model]
	if not info then return end
	local button = kind == "Robux" and info.Robux or info.Button
	ButtonFX.Press(button) -- squash-pop + click on every press (user 2026-09-07)
	if info.Plot:GetAttribute("Owner") ~= player.UserId then
		Toast("This is not your plot", FAIL_COLOR)
		ButtonFX.Fail(button)
		return
	end
	local ok, message = ActionFunction:InvokeServer(kind, UPGRADE_ID)
	Toast(tostring(message or (ok and "Done" or "Failed")), ok and OK_COLOR or FAIL_COLOR)
	if not ok then
		ButtonFX.Fail(button)
	elseif kind == "Buy" then
		ButtonFX.Success(button) -- a Robux press only opens the purchase prompt: no success pop yet
	end
end

local function Watch(model)
	if boards[model] then return end
	task.spawn(function()
		--.. with StreamingEnabled the model can arrive before its GUI, so wait for the pieces
		local plotName = model:GetAttribute("Plot")
		local plot = plotName and Plots:WaitForChild(plotName, 30)
		local face = model:WaitForChild("Face", 30)
		local gui = face and face:WaitForChild("BoardGui", 30)
		local bg = gui and gui:WaitForChild("Bg", 30)
		local button = bg and bg:WaitForChild("Button", 30)
		local robux = bg and bg:WaitForChild("RobuxButton", 30)
		if not (plot and button and robux) or boards[model] then return end
		local info = {
			Plot = plot,
			Level = bg:WaitForChild("Level", 10),
			Button = button,
			Rim = button:FindFirstChild("Rim"),
			Cost = button:WaitForChild("Cost", 10),
			Robux = robux,
			RobuxRim = robux:FindFirstChild("Rim"),
			Price = robux:WaitForChild("Price", 10),
			Conns = {},
		}
		if not (info.Level and info.Cost and info.Price) then return end
		boards[model] = info
		info.LastLevel = math.max(1, math.floor(tonumber(plot:GetAttribute("BenchLevel")) or 1))
		info.OwnerChangedAt = 0
		ButtonFX.Prepare(button)
		ButtonFX.Prepare(robux)
		ButtonFX.Prepare(info.Level)
		table.insert(info.Conns, button.Activated:Connect(function() Press(model, "Buy") end))
		table.insert(info.Conns, robux.Activated:Connect(function() Press(model, "Robux") end))
		table.insert(info.Conns, plot:GetAttributeChangedSignal("BenchLevel"):Connect(function()
			--.. +1 = a purchase: every client near the board sees the level-up burst (user 2026-09-07);
			--.. the jump when an owner's saved level arrives right after Owner is set is not one
			local level = math.max(1, math.floor(tonumber(plot:GetAttribute("BenchLevel")) or 1))
			local previous = info.LastLevel
			info.LastLevel = level
			if previous and level == previous + 1 and os.clock() - info.OwnerChangedAt > 3 then
				ButtonFX.Celebrate(model, info.Level, "LEVEL UP!")
			end
			Render(model)
		end))
		table.insert(info.Conns, plot:GetAttributeChangedSignal("BenchCost"):Connect(function() Render(model) end))
		table.insert(info.Conns, plot:GetAttributeChangedSignal("Owner"):Connect(function()
			info.OwnerChangedAt = os.clock()
			Render(model)
		end))
		Render(model)
	end)
end

local function Unwatch(model)
	local info = boards[model]
	if not info then return end
	for _, conn in ipairs(info.Conns) do conn:Disconnect() end
	boards[model] = nil
end

for _, model in ipairs(CollectionService:GetTagged(BOARD_TAG)) do Watch(model) end
CollectionService:GetInstanceAddedSignal(BOARD_TAG):Connect(Watch)
CollectionService:GetInstanceRemovedSignal(BOARD_TAG):Connect(Unwatch)

StateEvent.OnClientEvent:Connect(function(newState)
	state = newState
	RenderAll()
end)
task.spawn(function()
	local data = player:WaitForChild("Data", 60)
	cashValue = data and data:WaitForChild("Cash", 60)
	if cashValue then
		cashValue.Changed:Connect(RenderAll)
		RenderAll()
	end
end)
--.. ask for the state in case the profile loaded before this script
task.defer(function() pcall(function() ActionFunction:InvokeServer("State", "") end) end)
