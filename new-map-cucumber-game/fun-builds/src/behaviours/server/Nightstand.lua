--[[
	Nightstand  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the functional Nightstand (fun-builds/CONTRACT.md, HomeBedroom package).
	  * a "Lamp on/off" prompt on the table lamp's shade (LampShade): anyone may flip it (a lamp can't grief
	    anybody); a short cooldown stops flicker spam
	  * Fun_On (bool) = the lamp is lit. The client half (ReplicatedStorage.FunBehavioursClient.Nightstand)
	    renders it: a warm PointLight in the shade, the shade's inner discs Neon, a click. It also turns the
	    alarm clock's hands to the in-game time (Lighting.ClockTime) - purely cosmetic, no server part
	The lamp starts off whenever the behaviour (re)starts: placed, moved, restored on join or mended.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage.Modules.FunBuildKit)

--..Config..--
local PROMPT_DISTANCE = 8
local TOGGLE_COOLDOWN = 0.3 -- seconds between flips

local B = {}

--..Behaviour..--
function B.Server(model, ctx)
	local shade = Kit.Part(model, "LampShade") or Kit.Hitbox(model)
	if not shade then return end
	local prompt = ctx:Prompt(shade, {
		Name = "LampPrompt",
		Action = "Lamp on/off",
		Object = tostring(model:GetAttribute("DisplayName") or "Nightstand"),
		Distance = PROMPT_DISTANCE,
	})

	ctx:SetState("On", false)
	local last = 0
	ctx:Connect(prompt.Triggered, function(player)
		if os.clock() - last < TOGGLE_COOLDOWN then return end
		if not ctx:HumanoidOf(player) then return end
		last = os.clock()
		ctx:SetState("On", ctx:GetState("On") ~= true)
	end)
end

return B
