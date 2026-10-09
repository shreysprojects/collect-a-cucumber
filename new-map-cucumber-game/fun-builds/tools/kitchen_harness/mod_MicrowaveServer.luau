--!nocheck
return function(env)
	local game, workspace, Instance, Vector3, CFrame, Color3, Vector2, UDim2, NumberRange, NumberSequence, NumberSequenceKeypoint, ColorSequence, Enum, typeof, task, require, warn, os = env.game, env.workspace, env.Instance, env.Vector3, env.CFrame, env.Color3, env.Vector2, env.UDim2, env.NumberRange, env.NumberSequence, env.NumberSequenceKeypoint, env.ColorSequence, env.Enum, env.typeof, env.task, env.require, env.warn, env.os
--[[
	Microwave  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the working MICROWAVE on its cart (fun-builds/CONTRACT.md, package HomeKitchenA; model =
	fun-builds/models/build_Microwave.py). Anyone may use it (nothing to grief, no economy).
	  * two prompts at the keypad (Pivot_Keypad on the KeypadPanel part), the second one dropped a prompt-height
	    under the first (UIOffset, like the TV):
	      "Heat"            E / ButtonX  - shuts the door if it is open (heating starts once it has swung shut),
	                                       then runs HEAT_TIME seconds; the prompt reads "Heating..." meanwhile
	      "Open" / "Close"  R / ButtonY  - toggles the door. Opening it mid-heat stops the microwave (like a
	                                       real one): no ding
	  * state (model attributes, replicated; the client half ReplicatedStorage.FunBehavioursClient.Microwave
	    draws everything from them with Kit.Now(), so all clients agree):
	      Fun_Door   signed server time: > 0 opened at, < 0 closed at, 0 shut (one number = no split update)
	      Fun_Heat   server time the current heat starts (may be ~0.5 s ahead while the door swings shut),
	                 0 = idle. Heating while Kit.Now() is in [Heat, Heat + HEAT_TIME)
	      Fun_Done   server time of the last finished heat (the client dings, puffs steam, shows END)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local HEAT_TIME = 5            -- s; must match the client half
local CLOSE_FIRST = 0.55       -- s the door takes to swing shut before a heat starts (client SWING_TIME + a beat)
local PROMPT_DISTANCE = 9
local HEAT_COOLDOWN = 0.5
local DOOR_COOLDOWN = 0.55
local DOOR_PROMPT_DROP = 72    -- px: the door prompt sits under the heat prompt (the prompt layout is 66 px tall)
local ANCHOR_PARTS = {"KeypadPanel", "CaseR", "CaseTop"}

local B = {}
B.Keys = {"Microwave"}
B.ActionRange = 30

--..Behaviour..--
function B.Server(model, ctx)
	local anchor
	for _, name in ipairs(ANCHOR_PARTS) do
		anchor = Kit.Part(model, name)
		if anchor then break end
	end
	anchor = anchor or Kit.Hitbox(model)
	if not anchor then return end

	ctx:SetState("Door", 0)
	ctx:SetState("Heat", 0)
	ctx:SetState("Done", 0)

	local spot = model:GetAttribute("Pivot_Keypad")
	if typeof(spot) ~= "Vector3" then spot = Vector3.new(-0.85, 3.4, -1.0) end
	local offset = anchor.CFrame:PointToObjectSpace(Kit.ToWorld(model, spot))

	local heat = ctx:Prompt(anchor, {
		Name = "MicrowaveHeatPrompt",
		Action = "Heat",
		Object = "Microwave",
		Distance = PROMPT_DISTANCE,
		Offset = offset,
	})
	local door = ctx:Prompt(anchor, {
		Name = "MicrowaveDoorPrompt",
		Action = "Open",
		Object = "Microwave",
		Key = Enum.KeyCode.R,
		Gamepad = Enum.KeyCode.ButtonY,
		Distance = PROMPT_DISTANCE,
		Offset = offset,
	})
	door.UIOffset = Vector2.new(0, DOOR_PROMPT_DROP)

	--..Helpers..--
	local token = 0 -- bumps on every heat start / cancel; a finishing timer only counts if it is still current
	local lastHeat, lastDoor = -math.huge, -math.huge

	local function IsOpen()
		return (tonumber(ctx:GetState("Door")) or 0) > 0
	end
	local function IsHeating()
		local start = tonumber(ctx:GetState("Heat")) or 0
		return start > 0 and Kit.Now() < start + HEAT_TIME
	end
	local function SetDoor(open)
		local now = Kit.Now()
		ctx:SetState("Door", open and now or -now)
		door.ActionText = open and "Close" or "Open"
	end
	local function StopHeat()
		token += 1
		ctx:SetState("Heat", 0)
		heat.ActionText = "Heat"
	end

	--..Heat..--
	ctx:Connect(heat.Triggered, function(player)
		if not ctx:HumanoidOf(player) or IsHeating() then return end
		local t = os.clock()
		if t - lastHeat < HEAT_COOLDOWN then return end
		lastHeat = t
		local delay = 0
		if IsOpen() then
			SetDoor(false) -- the door swings shut, then it starts
			delay = CLOSE_FIRST
		end
		token += 1
		local mine = token
		ctx:SetState("Heat", Kit.Now() + delay)
		heat.ActionText = "Heating..."
		task.delay(delay + HEAT_TIME, function()
			if not ctx:Alive() or token ~= mine then return end
			token += 1
			ctx:SetState("Heat", 0)
			ctx:SetState("Done", Kit.Now())
			heat.ActionText = "Heat"
		end)
	end)

	--..Door..--
	ctx:Connect(door.Triggered, function(player)
		if not ctx:HumanoidOf(player) then return end
		local t = os.clock()
		if t - lastDoor < DOOR_COOLDOWN then return end
		lastDoor = t
		local open = not IsOpen()
		if open and (tonumber(ctx:GetState("Heat")) or 0) > 0 then StopHeat() end -- opened mid-heat: it stops
		SetDoor(open)
	end)
end

return B

end
