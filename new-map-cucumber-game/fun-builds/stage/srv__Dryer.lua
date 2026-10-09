--[[
	Dryer  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the WORKING TUMBLE DRYER: the washing machine's engine with the dryer's name on the prompts.
	Everything (the "Start" / "Stop" prompt -> state CycleEnd, the "Open door" / "Close door" prompt -> state Door)
	lives in the sibling module ServerStorage.FunBehaviours.WashingMachine - see its header and
	fun-builds/notes/HomeLaundry.md.
]]
local Washer = require(script.Parent:WaitForChild("WashingMachine", 10))
return Washer.Make("Dryer")
