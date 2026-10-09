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
--.. day 1-7+; day 7 is the jackpot, then it repeats at day-7 value
local REWARDS = {300, 500, 800, 1200, 1800, 2600, 4000} -- coins

--..Variables..--
local StreakService = {}

--..Functions..--

function StreakService.PlayerJoined(Player)
	local profile
	for i = 1, 30 do
		profile = ProfileService.GetUserData(Player)
		if profile then break end
		task.wait(1)
	end
	if not profile or not profile.Streak then return end

	local today = math.floor(os.time() / 86400)
	local streak = profile.Streak

	if streak.Day == today then return end -- already claimed today

	if streak.Day == today - 1 then
		streak.Count += 1
	else
		streak.Count = 1 -- missed a day, back to the start
	end
	streak.Day = today

	local reward = REWARDS[math.min(streak.Count, #REWARDS)]
	local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
	CurrencyHandler.AddCurrency({Player = Player; Currency = "Coins"; Amount = reward; WasPurchase = true; HasTotal = true;})

	task.wait(15) -- past the loading screen AND the tutorial start so it's actually seen
	local message
	if streak.Count >= #REWARDS then
		message = ("\u{1F525} DAY %d! +%d COINS (MAX)"):format(streak.Count, reward)
	else
		message = ("\u{1F525} DAY %d! +%d COINS"):format(streak.Count, reward, REWARDS[streak.Count + 1])
	end
	Network:FireClient(Player, "Notif", {Message = message; Type = "Success";})
end

function StreakService.Initialize()
end

return StreakService
