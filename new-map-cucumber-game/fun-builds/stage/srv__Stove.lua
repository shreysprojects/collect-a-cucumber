--[[
	Stove  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the WORKING STOVE (client half: ReplicatedStorage.FunBehavioursClient.Stove;
	fun-builds/CONTRACT.md; model = fun-builds/models/build_Stove.py).
	  * one "Turn on" / "Turn off" prompt on the knob panel of the back guard (Pivot_Controls) toggles
	    state On (model attribute Fun_On). The client half does everything visible and audible: the coils
	    (Burner*) glow red-orange, heat shimmer rises, the pan sizzles and pops oil, the kettle steams, the
	    oven window glows and the power light turns red.
	Anyone may use it (nothing to grief). No economy, no physics, no build parts touched on the server.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local CONTROLS_FALLBACK = Vector3.new(0, 4.3, 0.855) -- authored knob-panel front (Pivot_Controls)
local PROMPT_DISTANCE = 10                           -- studs at scale 1 (grows with a bigger template)
local TOGGLE_DEBOUNCE = 0.4                          -- seconds between two toggles

local B = {}
B.ActionRange = 30

--..Behaviour..--
function B.Server(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	ctx:SetState("On", false)

	--..Prompt on the knob panel..--
	local at = Kit.Pivot(model, "Controls") or Kit.ToWorld(model, CONTROLS_FALLBACK)
	local prompt = ctx:Prompt(hitbox, {
		Action = "Turn on",
		Object = "Stove",
		Name = "StovePrompt",
		Distance = math.max(PROMPT_DISTANCE, PROMPT_DISTANCE * ctx.Scale),
		Offset = hitbox.CFrame:PointToObjectSpace(at),
	})
	local last = 0
	ctx:Connect(prompt.Triggered, function(player)
		local now = os.clock()
		if now - last < TOGGLE_DEBOUNCE or not ctx:HumanoidOf(player) then return end
		last = now
		local on = ctx:GetState("On") ~= true
		ctx:SetState("On", on)
		prompt.ActionText = on and "Turn off" or "Turn on"
	end)
end

return B
