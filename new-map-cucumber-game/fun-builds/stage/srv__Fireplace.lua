--[[
	Fireplace  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package HomeHearth
	Server half of the WORKING FIREPLACE (fun-builds/CONTRACT.md; model = models/build_Fireplace.py, Home, Cost 1500).
	  * one prompt over the hearth (Pivot_Prompt): "Light fire" while the fireplace is cold, "Put out" while it
	    burns. Anyone may use it (a fire is nothing to grief); a short debounce stops two people pressing at the
	    same moment from flickering it on and off
	  * state Fun_Lit (true / false). The client half draws everything from it: the Fire, sparks, the warm
	    flickering light, glowing embers, the mantel candles, chimney smoke and the crackle
	  * the fire starts OUT whenever this behaviour (re)starts - placed, moved, mended after a zombie raid, server
	    start. It never lights itself (not even at night): someone has to light it
	No economy, no damage: the fire is cosmetic (no Touched, nothing burns, nobody gets hurt).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local PROMPT_DISTANCE = 10                          -- studs (x the build's scale when it is scaled up)
local TOGGLE_DEBOUNCE = 0.6                         -- seconds between two toggles
local PROMPT_FALLBACK = Vector3.new(0, 1.9, -1.95)  -- authored, used when Pivot_Prompt is missing

local B = {}
B.Keys = {"Fireplace"}

--..Behaviour..--
function B.Server(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end

	--..Prompt on an invisible helper over the hearth..--
	local spot = Kit.Pivot(model, "Prompt") or Kit.ToWorld(model, PROMPT_FALLBACK)
	local anchor = ctx:Part({
		Name = "FireplacePromptSpot",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CFrame = CFrame.new(spot) * hitbox.CFrame.Rotation,
	})
	local prompt = ctx:Prompt(anchor, {
		Action = "Light fire",
		Object = "Fireplace",
		Distance = PROMPT_DISTANCE * math.max(1, ctx.Scale),
		Name = "FirePrompt",
	})

	--..State..--
	local function Apply(lit)
		ctx:SetState("Lit", lit)
		prompt.ActionText = lit and "Put out" or "Light fire"
	end
	Apply(false)

	local last = 0
	ctx:Connect(prompt.Triggered, function(player)
		if not ctx:Alive() or not ctx:HumanoidOf(player) then return end
		local now = os.clock()
		if now - last < TOGGLE_DEBOUNCE then return end
		last = now
		Apply(ctx:GetState("Lit") ~= true)
	end)
end

return B
