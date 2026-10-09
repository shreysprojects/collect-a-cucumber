--[[
	FloorLamp  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package HomeHearth
	Server half of the READING FLOOR LAMP (fun-builds/CONTRACT.md; model = models/build_FloorLamp.py, Home, Cost 300).
	  * one prompt at the pull-chain bead (Pivot_Switch): "Lamp on" while off, "Lamp off" while on. Anyone may
	    flip it (nothing to grief); a short debounce stops a double press flickering it
	  * state Fun_On (true / false). The client half draws the light (PointLight in the shade + a SpotLight
	    shining down through its open bottom) and the glowing Neon shade / diffuser / bulb from it
	  * event "Tug" (ctx:Fire, all clients) only when a PLAYER pulls the chain: the client tugs the chain and
	    clicks. The dusk / dawn switch changes the state alone, so a plot's lamps don't all click at nightfall
	  * DAY / NIGHT: the lamp starts ON at night and OFF by day (placed, moved, mended, server start), and every
	    dusk switches it on and every dawn switches it off - read from DayNightCycle's workspace attributes
	    IsNight (bool) / CyclePhase ("Night"). In between, people may flip it whenever they like
	No economy.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local PROMPT_DISTANCE = 8                            -- studs (x the build's scale when it is scaled up)
local TOGGLE_DEBOUNCE = 0.4                          -- seconds between two toggles
local SWITCH_FALLBACK = Vector3.new(0.3, 4.64, -0.3) -- authored, used when Pivot_Switch is missing

local B = {}
B.Keys = {"FloorLamp"}

--..Helpers..--
local function IsNight()
	local flag = workspace:GetAttribute("IsNight")
	if type(flag) == "boolean" then return flag end
	return workspace:GetAttribute("CyclePhase") == "Night"
end

--..Behaviour..--
function B.Server(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end

	--..Prompt on an invisible helper at the pull-chain bead..--
	local spot = Kit.Pivot(model, "Switch") or Kit.ToWorld(model, SWITCH_FALLBACK)
	local anchor = ctx:Part({
		Name = "FloorLampSwitch",
		Size = Vector3.new(0.6, 0.6, 0.6),
		Transparency = 1,
		CFrame = CFrame.new(spot) * hitbox.CFrame.Rotation,
	})
	local prompt = ctx:Prompt(anchor, {
		Action = "Lamp on",
		Object = "Floor Lamp",
		Distance = PROMPT_DISTANCE * math.max(1, ctx.Scale),
		Name = "LampPrompt",
	})

	--..State..--
	local function Apply(on)
		ctx:SetState("On", on)
		prompt.ActionText = on and "Lamp off" or "Lamp on"
	end

	--.. dusk on, dawn off (only on a real change: IsNight and CyclePhase both fire around a phase change)
	local night = IsNight()
	Apply(night)
	local function OnCycle()
		local now = IsNight()
		if now == night then return end
		night = now
		Apply(now)
	end
	ctx:Connect(workspace:GetAttributeChangedSignal("IsNight"), OnCycle)
	ctx:Connect(workspace:GetAttributeChangedSignal("CyclePhase"), OnCycle)

	--.. anyone flips it by hand
	local last = 0
	ctx:Connect(prompt.Triggered, function(player)
		if not ctx:Alive() or not ctx:HumanoidOf(player) then return end
		local now = os.clock()
		if now - last < TOGGLE_DEBOUNCE then return end
		last = now
		Apply(ctx:GetState("On") ~= true)
		ctx:Fire("Tug")
	end)
end

return B
