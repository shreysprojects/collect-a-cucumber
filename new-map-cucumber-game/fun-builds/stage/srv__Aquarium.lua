--[[
	Aquarium  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package HomeDecor
	Server half of the fish tank (client half: ReplicatedStorage.FunBehavioursClient.Aquarium; fun-builds/CONTRACT.md).
	  * a "Feed fish" prompt on the tank's feed flap (FeedFlap, top front of the tank). Anyone may feed the fish
	    (it can't grief anybody); one feeding at a time: while the fish are still eating (FEED_COOLDOWN s) the
	    prompt reads "Fish are eating..." and presses are ignored
	  * Fun_FedAt (number) = the server time (Kit.Now) of the last feeding. That is the whole shared state: every
	    client computes the same show from it - the flap opening, the 12 flakes (seeded by Fun_FedAt), which fish
	    eats which flake and when - so a player streaming in half-way sees the same moment as everyone else
	Everything else (5 swimming fish, bubbles, the chest lid, swaying plants, the tank light) is client-only and
	driven by the server clock. No economy impact.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage.Modules.FunBuildKit)

--..Config..--
local PROMPT_DISTANCE = 10
local FEED_COOLDOWN = 7    -- s: the client show lasts ~6.5 s (Aquarium client FEED_TIME)
local ACTION_TEXT = "Feed fish"
local BUSY_TEXT = "Fish are eating..."

local B = {}

--..Behaviour..--
function B.Server(model, ctx)
	local flap = Kit.Part(model, "FeedFlap") or Kit.Hitbox(model)
	if not flap then return end
	local prompt = ctx:Prompt(flap, {
		Name = "FeedPrompt",
		Action = ACTION_TEXT,
		Object = tostring(model:GetAttribute("DisplayName") or "Aquarium"),
		Distance = PROMPT_DISTANCE,
	})

	local feeding = 0 -- counts feedings so a stale "busy" timer never resets a newer one
	ctx:Connect(prompt.Triggered, function(player)
		if not ctx:HumanoidOf(player) then return end
		local now = Kit.Now()
		local last = ctx:GetState("FedAt")
		if type(last) == "number" and now - last < FEED_COOLDOWN then return end
		ctx:SetState("FedAt", now)
		feeding += 1
		local mine = feeding
		prompt.ActionText = BUSY_TEXT
		task.delay(FEED_COOLDOWN, function()
			if ctx:Alive() and feeding == mine and prompt.Parent then prompt.ActionText = ACTION_TEXT end
		end)
	end)
end

return B
