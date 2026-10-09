--!nocheck
return function(env)
	local game, workspace, Instance, Vector3, CFrame, Color3, Vector2, UDim2, NumberRange, NumberSequence, NumberSequenceKeypoint, ColorSequence, Enum, typeof, task, require, warn, os = env.game, env.workspace, env.Instance, env.Vector3, env.CFrame, env.Color3, env.Vector2, env.UDim2, env.NumberRange, env.NumberSequence, env.NumberSequenceKeypoint, env.ColorSequence, env.Enum, env.typeof, env.task, env.require, env.warn, env.os
--[[
	Fridge  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the working FRIDGE (fun-builds/CONTRACT.md, package HomeKitchenA; model =
	fun-builds/models/build_Fridge.py). Anyone may use it (nothing to grief).
	  * two prompts, both on the static SkinL cabinet part (the doors only move on clients) at the authored
	    Pivot_PromptDoor / Pivot_PromptFreezer spots in front of each handle:
	      fridge door   "Open" / "Close"  E / ButtonX   ObjectText "Fridge"
	      freezer door  "Open" / "Close"  R / ButtonY   ObjectText "Freezer"  (a second key, so both badges show
	                                                                             at once - OnePerButton would hide
	                                                                             the farther one)
	  * state (model attributes, replicated) - ONE signed number per door, so a client never sees the open flag
	    and its timestamp arrive in different frames:
	      Fun_Door     > 0 = opened at that server time (Kit.Now()), < 0 = closed at -value, 0 = shut
	      Fun_Freezer  the same for the freezer door
	    The client half swings the Door* / FreezerDoor* groups from it (eased, synced by server time), lights the
	    compartment, spills cold mist and plays the sounds.
	  * a door left open swings shut by itself after AUTO_CLOSE seconds (the light / mist stop with it)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local PROMPT_DISTANCE = 9     -- studs from the prompt spot (the freezer spot is ~6.4 up at scale 1)
local TOGGLE_COOLDOWN = 0.65  -- s per door; the client swing takes 0.6 s
local AUTO_CLOSE = 40         -- s a door may stay open before it closes itself
local ANCHOR_PARTS = {"SkinL", "WallL", "SkinTop"} -- static parts that carry the prompts (first found, else the Hitbox)

local DOORS = {
	{State = "Door", Pivot = "PromptDoor", Object = "Fridge", Name = "FridgeDoorPrompt",
		Key = Enum.KeyCode.E, Gamepad = Enum.KeyCode.ButtonX, Fallback = Vector3.new(1.62, 4.2, -1.95)},
	{State = "Freezer", Pivot = "PromptFreezer", Object = "Freezer", Name = "FreezerDoorPrompt",
		Key = Enum.KeyCode.R, Gamepad = Enum.KeyCode.ButtonY, Fallback = Vector3.new(1.62, 6.4, -1.95)},
}

local B = {}
B.Keys = {"Fridge"}
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

	for _, d in ipairs(DOORS) do
		ctx:SetState(d.State, 0)

		--.. the prompt spot (authored, in front of the handle) in the anchor part's space
		local spot = model:GetAttribute("Pivot_" .. d.Pivot)
		if typeof(spot) ~= "Vector3" then spot = d.Fallback end
		local prompt = ctx:Prompt(anchor, {
			Name = d.Name,
			Action = "Open",
			Object = d.Object,
			Key = d.Key,
			Gamepad = d.Gamepad,
			Distance = PROMPT_DISTANCE,
			Offset = anchor.CFrame:PointToObjectSpace(Kit.ToWorld(model, spot)),
		})

		local last = -math.huge
		local token = 0
		local function IsOpen()
			return (tonumber(ctx:GetState(d.State)) or 0) > 0
		end
		local function Set(open)
			token += 1
			local now = Kit.Now()
			ctx:SetState(d.State, open and now or -now)
			prompt.ActionText = open and "Close" or "Open"
			if open then
				--.. nobody closes it: it swings shut on its own
				local mine = token
				task.delay(AUTO_CLOSE, function()
					if ctx:Alive() and token == mine and IsOpen() then Set(false) end
				end)
			end
		end

		ctx:Connect(prompt.Triggered, function(player)
			if not ctx:HumanoidOf(player) then return end
			local t = os.clock()
			if t - last < TOGGLE_COOLDOWN then return end
			last = t
			Set(not IsOpen())
		end)
	end
end

return B

end
