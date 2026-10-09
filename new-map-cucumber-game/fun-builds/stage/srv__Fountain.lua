--[[
	Fountain  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package GardenLights
	Server half of the RUNNING FOUNTAIN (client half: ReplicatedStorage.FunBehavioursClient.Fountain draws the
	jets, splash rings, mist and sound). The prop's author asked for the see-through water to be walk-through:
	"make them non-collidable in Roblox and let players walk into the basin" - so while the behaviour runs, the
	WaterSurface (basin + bowl sheets), WaterBed, Jets and Foam parts are CanCollide = false. People then wade in
	to the basin floor (the BasinWall mesh's raised floor, 0.40 authored) and the client draws ripples round them.
	Done on the server so every client, the zombies and the server's own physics agree.
	Cleanup restores each part's ORIGINAL CanCollide, remembered in a part attribute the first time this ever
	runs (so re-runs after a move / mend never mistake our own false for the original) - except while the build
	is Broken: BuildHealthService owns collisions then, and on mend it restores what it recorded before we re-run.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local WALK_THROUGH = {"WaterSurface", "WaterBed", "Jets", "Foam"}
local ORIGINAL_ATTR = "FunCollideOriginal"

local B = {}

--..Behaviour..--
function B.Server(model, ctx)
	local touched = {}
	for _, name in ipairs(WALK_THROUGH) do
		local part = Kit.Part(model, name)
		if part then
			if type(part:GetAttribute(ORIGINAL_ATTR)) ~= "boolean" then part:SetAttribute(ORIGINAL_ATTR, part.CanCollide) end
			part.CanCollide = false
			table.insert(touched, part)
		end
	end

	return function()
		if Kit.IsBroken(model) then return end -- BuildHealthService faded + de-collided everything; it restores on mend
		for _, part in ipairs(touched) do
			local original = part:GetAttribute(ORIGINAL_ATTR)
			if part.Parent and type(original) == "boolean" then part.CanCollide = original end
		end
	end
end

return B
