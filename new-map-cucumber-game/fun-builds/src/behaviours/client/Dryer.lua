--[[
	Dryer  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the WORKING TUMBLE DRYER: the washing machine's engine with the dryer's programme - the drum turns
	steadily one way with the clothes tumbling from high up, a warm glow inside, warm lint puffs + fluff out of the side
	vent (Pivot_Vent -> Pivot_VentOut) while VentSlat1..3 flutter open, a gentle jiggle, amber countdown, Ding.
	Everything lives in the sibling module ReplicatedStorage.FunBehavioursClient.WashingMachine (KINDS.Dryer) - see its
	header and fun-builds/notes/HomeLaundry.md.
]]
local Washer = require(script.Parent:WaitForChild("WashingMachine", 10))
return Washer.Make("Dryer")
