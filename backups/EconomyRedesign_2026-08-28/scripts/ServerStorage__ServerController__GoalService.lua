--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local Network = ControllerLoader.GetController("Network")

--..Config..--
--.. Only the required action can progress the goal that is currently active.
--.. Lifetime totals are intentionally not used: old progress and unrelated rewards
--.. must never complete goals while the player is idle.
local GOALS = {
	{Name = "Smash 10 cucumbers"; Coins = 200; Action = "Break"; Target = 10};
	{Name = "Hatch your first egg"; Coins = 400; Action = "Hatch"; Target = 1};
	{Name = "Sell 2,500 cucumbers to the vendor"; Coins = 600; Action = "SellCucumbers"; Target = 2500};
	{Name = "Smash a GOLDEN cucumber"; Coins = 1000; Action = "BreakGolden"; Target = 1};
	{Name = "Unlock The Wild West"; Coins = 2000; Action = "UnlockWildWest"; Target = 1};
}

--..Variables..--
local GoalService = {}

--..Functions..--

local function Announce(Player, profile)
	local goal = GOALS[profile.GoalIndex]
	if goal then
		Network:FireClient(Player, "Notif", {Message = ("\u{1F3AF} GOAL: %s (+%d COINS)"):format(string.upper(goal.Name), goal.Coins); Type = "Success";})
	end
end

function GoalService.PlayerJoined(Player)
	local profile
	for i = 1, 30 do
		profile = ProfileService.GetUserData(Player)
		if profile then break end
		task.wait(1)
	end
	if not profile or not profile.GoalIndex then return end
	if GOALS[profile.GoalIndex] then
		task.wait(14) -- after loading + streak notif
		if Player.Parent == Players then
			Announce(Player, profile)
		end
	end
end

local function GetProgress(profile)
	local index = profile.GoalIndex
	local progress = profile.GoalProgress
	if type(progress) ~= "table" or progress.Index ~= index then
		progress = {Index = index; Amount = 0}
		profile.GoalProgress = progress
	end
	return progress
end

local function Complete(Player, profile, goal)
	profile.GoalIndex += 1
	profile.GoalProgress = {Index = profile.GoalIndex; Amount = 0}

	local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
	-- Goal rewards change the balance only. They are not sales and must not
	-- increase any lifetime earning counter used by other systems.
	CurrencyHandler.AddCurrency({
		Player = Player;
		Currency = "Coins";
		Amount = goal.Coins;
		WasPurchase = true;
		HasTotal = false;
	})
	Network:FireClient(Player, "Notif", {
		Message = ("\u{2705} %s! +%d COINS"):format(string.upper(goal.Name), goal.Coins);
		Type = "Success";
	})

	if GOALS[profile.GoalIndex] then
		task.delay(4, function()
			if Player.Parent == Players then Announce(Player, profile) end
		end)
	end
end

function GoalService.RecordAction(Player, Action, Amount)
	if not Player or Player.Parent ~= Players or type(Action) ~= "string" then return false end
	local profile = ProfileService.GetUserData(Player)
	if not profile or not profile.GoalIndex then return false end

	local goal = GOALS[profile.GoalIndex]
	if not goal or goal.Action ~= Action then return false end

	local progress = GetProgress(profile)
	local increment = tonumber(Amount) or 1
	if increment <= 0 then return false end
	progress.Amount = math.min(goal.Target, (tonumber(progress.Amount) or 0) + increment)

	if progress.Amount >= goal.Target then
		Complete(Player, profile, goal)
		return true
	end
	return false
end

function GoalService.Initialize()
	-- Progress is event-driven. Deliberately no periodic lifetime-stat polling.
end

return GoalService
