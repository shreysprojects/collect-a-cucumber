--[[
	PlotUpgradeClient  (LocalScript, StarterPlayerScripts)
	Fills every PlotUpgrade board (models tagged "PlotUpgradeBoard", attribute Plot = plot name,
	SurfaceGui "BoardGui" on their Face part: Bg > Title / Level / Button > Cost) from the plot's
	replicated attributes (PlotLevel, Owner) and this player's Cash, and sends BUY presses through
	ReplicatedStorage.Remotes.PlotUpgradeAction. The board text is edited locally, so every player
	sees their own cash check on the button (green = can buy, red = cannot afford / not yours, grey =
	maxed -- user 2026-09-06).
	Levels / sizes / costs come from ReplicatedStorage.Modules.PlotUpgrades.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlotUpgrades = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlotUpgrades"))
local ButtonFX = require(ReplicatedStorage.Modules:WaitForChild("ButtonFX")) -- press / success / fail pops + level-up burst (user 2026-09-07)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = Remotes:WaitForChild("PlotUpgradeAction")
local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

local BOARD_TAG = "PlotUpgradeBoard"
local RED = Color3.fromRGB(228, 40, 40)
local RED_DARK = Color3.fromRGB(122, 14, 14)
local GREEN = Color3.fromRGB(58, 196, 72)
local GREEN_DARK = Color3.fromRGB(22, 104, 34)
local GREY = Color3.fromRGB(105, 105, 112)
local GREY_DARK = Color3.fromRGB(55, 55, 60)
local Notify = require(ReplicatedStorage.Modules:WaitForChild("Notify")) -- the game-wide notification style (user 2026-09-07)
local OK_COLOR = Notify.COLORS.Success
local FAIL_COLOR = Notify.COLORS.Error

local boards = {} -- [model] = {Plot, Level, Button, Rim, Cost, Conns}
local cashValue = nil

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
	local level = PlotUpgrades.Clamp(plot:GetAttribute("PlotLevel") or 0)
	local cost = PlotUpgrades.Cost(level)
	local mine = plot:GetAttribute("Owner") == player.UserId
	local cash = cashValue and cashValue.Value or 0
	local canBuy = false
	if cost then
		info.Level.Text = ("Level %d > Level %d"):format(level, level + 1)
		info.Cost.Text = "$" .. PlotUpgrades.Abbrev(cost)
		canBuy = mine and cash >= cost
	else
		info.Level.Text = ("Level %d  (MAX)"):format(level)
		info.Cost.Text = "MAXED"
	end
	--.. green = you can press, red = cannot (not enough Cash / not your plot), grey = maxed (user 2026-09-06)
	local color, dark = GREY, GREY_DARK
	if cost then
		if canBuy then color, dark = GREEN, GREEN_DARK else color, dark = RED, RED_DARK end
	end
	Paint(info.Button, info.Rim, color, dark)
	info.Button.Active = cost ~= nil
end

local function RenderAll()
	for model in pairs(boards) do Render(model) end
end

local function Press(model)
	local info = boards[model]
	if not info then return end
	ButtonFX.Press(info.Button) -- squash-pop + click on every press (user 2026-09-07)
	if info.Plot:GetAttribute("Owner") ~= player.UserId then
		Toast("This is not your plot", FAIL_COLOR)
		ButtonFX.Fail(info.Button)
		return
	end
	local ok, message = Action:InvokeServer("Buy")
	Toast(tostring(message or (ok and "Done" or "Failed")), ok and OK_COLOR or FAIL_COLOR)
	if ok then ButtonFX.Success(info.Button) else ButtonFX.Fail(info.Button) end
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
		if not (plot and button) or boards[model] then return end
		local info = {
			Plot = plot,
			Level = bg:WaitForChild("Level", 10),
			Button = button,
			Rim = button:FindFirstChild("Rim"),
			Cost = button:WaitForChild("Cost", 10),
			Conns = {},
		}
		if not (info.Level and info.Cost) then return end
		boards[model] = info
		info.LastLevel = PlotUpgrades.Clamp(plot:GetAttribute("PlotLevel") or 0)
		info.OwnerChangedAt = 0
		ButtonFX.Prepare(button)
		ButtonFX.Prepare(info.Level)
		table.insert(info.Conns, button.Activated:Connect(function() Press(model) end))
		table.insert(info.Conns, plot:GetAttributeChangedSignal("PlotLevel"):Connect(function()
			--.. +1 = a purchase: every client near the board sees the level-up burst (user 2026-09-07);
			--.. the jump when an owner's saved level arrives right after Owner is set is not one
			local level = PlotUpgrades.Clamp(plot:GetAttribute("PlotLevel") or 0)
			local previous = info.LastLevel
			info.LastLevel = level
			if previous and level == previous + 1 and os.clock() - info.OwnerChangedAt > 3 then
				ButtonFX.Celebrate(model, info.Level, "LEVEL UP!")
			end
			Render(model)
		end))
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

--.. cash drive the button colour
task.spawn(function()
	local data = player:WaitForChild("Data", 60)
	cashValue = data and data:WaitForChild("Cash", 60)
	if cashValue then
		cashValue.Changed:Connect(RenderAll)
		RenderAll()
	end
end)
