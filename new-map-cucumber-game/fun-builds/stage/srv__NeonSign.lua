--[[
	NeonSign  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package GlassCase
	Server half of the three NEON SIGNS (x1.5): NeonSign_A OpenSign, NeonSign_B ArrowSign, NeonSign_C Marquee.
	All the light show is client-side (ReplicatedStorage.FunBehavioursClient.NeonSign); the server only owns
	the power switch:
	  * state On (model attribute Fun_On, default true). Remembered per placed build for the whole server
	    session, so a move or a break / mend (both re-run the behaviour) keeps it
	  * prompt "Switch off" / "Switch on" (E) on the variant's backing panel. OWNER ONLY: anyone else's trigger is
	    refused here, and the client half puts the prompt out of reach (MaxActivationDistance 0) on their clients
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local PROMPT_DISTANCE = 10
local SWITCH_COOLDOWN = 0.3 -- seconds

--..Variables..--
local Remembered = setmetatable({}, {__mode = "k"}) -- [model] = on (boolean)

local B = {}
B.Keys = {"NeonSign"}
B.ActionRange = 30

local function ActionText(on)
	return on and "Switch off" or "Switch on"
end

function B.Server(model, ctx)
	local on = Remembered[model]
	if on == nil then on = true end
	ctx:SetState("On", on)

	local panel = Kit.Part(model, Kit.VName(model, "Panel")) or Kit.Hitbox(model)
	local prompt = ctx:Prompt(panel, {
		Action = ActionText(on), Name = "NeonSwitchPrompt", Distance = PROMPT_DISTANCE,
	})
	local last = -math.huge
	ctx:Connect(prompt.Triggered, function(player)
		if not ctx:IsOwner(player) then return end
		local now = os.clock()
		if now - last < SWITCH_COOLDOWN then return end
		last = now
		on = not on
		Remembered[model] = on
		ctx:SetState("On", on)
		prompt.ActionText = ActionText(on)
	end)
end

return B
