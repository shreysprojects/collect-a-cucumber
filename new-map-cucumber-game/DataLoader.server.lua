--.. DataLoader: boots DataService (ProfileStore sessions + player.Data values).
--.. Keep this the only place that calls Start(); every other script just requires DataService.
local ServerStorage = game:GetService("ServerStorage")
require(ServerStorage:WaitForChild("DataService")).Start()
