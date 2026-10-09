--.. GymLoader (Script, ServerScriptService): boots GymService (board remotes, upgrade/quest actions,
--.. Speed upgrade walkspeed). BenchServer requires the same module for reps.
local ServerStorage = game:GetService("ServerStorage")
require(ServerStorage:WaitForChild("GymService")).Start()
