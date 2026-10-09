--[[
	WashingMachine  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the WORKING WASHING MACHINE, and through Make() of the DRYER (ServerStorage.FunBehaviours.Dryer
	is `require(script.Parent.WashingMachine).Make("Dryer")`). fun-builds/CONTRACT.md; models =
	fun-builds/models/build_WashingMachine.py / build_Dryer.py (+ laundrylib.py), notes = fun-builds/notes/HomeLaundry.md.
	  * "Start" prompt (E) in front of the console screen (Pivot_StartPrompt): runs one CYCLE-second programme.
	    State CycleEnd = the server time (Kit.Now) the cycle ends, 0 while idle; the client half plays the whole
	    programme (drum, clothes, water / lint, shake, countdown, sounds) from it, so every client shows the same
	    moment. While a cycle runs the prompt reads "Stop" and ends it early. Starting shuts an open door first.
	  * "Open door" / "Close door" prompt (F) on the porthole (Pivot_DoorPrompt), idle only (mid-cycle it reads
	    "Door locked" and presses do nothing; it stays Enabled so build mode's hide is never undone):
	    state Door (true = open). The client swings the Door* parts about Pivot_DoorHinge.
	  * test hook: model:SetAttribute("LaundryPress", "Start" | "Door") on the server presses that prompt (a Studio
	    playtest can't fire a ProximityPrompt from Luau); the attribute clears itself.
	Anyone may use it (nothing to grief, no economy). Nothing here moves a part: the server only keeps state.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local CYCLE = 15              -- seconds; keep in step with the client half
local PRESS_DEBOUNCE = 0.6    -- seconds between two presses of one prompt
local PROMPT_DISTANCE = 9     -- studs (the framework's prompts are drawn by CucumberPromptClient)
local KINDS = {
	Washer = {Object = "Washing Machine"},
	Dryer = {Object = "Dryer"},
}

--..Helpers..--
--.. a prompt on `part`, floating at the authored pivot `pivotName` (or on the part's centre without it)
local function PromptAt(model, ctx, part, pivotName, opts)
	local at = Kit.Pivot(model, pivotName)
	if at then opts.Offset = part.CFrame:PointToObjectSpace(at) end
	return ctx:Prompt(part, opts)
end

--..Behaviour..--
local function Make(kind)
	local cfg = KINDS[kind] or KINDS.Washer
	local B = {}
	B.ActionRange = 30

	function B.Server(model, ctx)
		local hitbox = Kit.Hitbox(model)
		local panel = Kit.Part(model, "Panel") or hitbox
		local front = Kit.Part(model, "FrontTop") or panel
		ctx:SetState("CycleEnd", 0)
		ctx:SetState("Door", false)

		local startPrompt = PromptAt(model, ctx, panel, "StartPrompt", {
			Action = "Start",
			Object = cfg.Object,
			Name = "StartPrompt",
			Distance = PROMPT_DISTANCE,
		})
		local doorPrompt = PromptAt(model, ctx, front, "DoorPrompt", {
			Action = "Open door",
			Object = cfg.Object,
			Name = "DoorPrompt",
			Distance = PROMPT_DISTANCE,
			Key = Enum.KeyCode.F,
			Gamepad = Enum.KeyCode.ButtonY,
		})

		local token = 0 -- bumps on every start / stop, so a stale end-of-cycle timer does nothing
		local function Running()
			return (tonumber(ctx:GetState("CycleEnd")) or 0) > Kit.Now()
		end
		--.. never toggle a prompt's Enabled here: it replicates and would undo FunBuildClient's build-mode hide (a cycle
		--.. ending while a player is in build mode would bring the prompt back for them). PressDoor ignores presses mid-cycle.
		local function Refresh()
			local running = Running()
			startPrompt.ActionText = running and "Stop" or "Start"
			if running then
				doorPrompt.ActionText = "Door locked"
			else
				doorPrompt.ActionText = ctx:GetState("Door") == true and "Close door" or "Open door"
			end
		end
		local function Finish(my)
			if not ctx:Alive() or token ~= my then return end
			ctx:SetState("CycleEnd", 0)
			Refresh()
		end

		--..Start / Stop..--
		local lastStart, lastDoor = 0, 0
		local function PressStart()
			local now = os.clock()
			if now - lastStart < PRESS_DEBOUNCE then return end
			lastStart = now
			token += 1
			if Running() then
				ctx:SetState("CycleEnd", 0) -- stopped early (the client clicks instead of dinging)
			else
				if ctx:GetState("Door") == true then ctx:SetState("Door", false) end
				ctx:SetState("CycleEnd", Kit.Now() + CYCLE)
				task.delay(CYCLE, Finish, token)
			end
			Refresh()
		end

		--..Door (idle only)..--
		local function PressDoor()
			local now = os.clock()
			if now - lastDoor < PRESS_DEBOUNCE or Running() then return end
			lastDoor = now
			ctx:SetState("Door", ctx:GetState("Door") ~= true)
			Refresh()
		end

		ctx:Connect(startPrompt.Triggered, function(player)
			if ctx:HumanoidOf(player) then PressStart() end
		end)
		ctx:Connect(doorPrompt.Triggered, function(player)
			if ctx:HumanoidOf(player) then PressDoor() end
		end)

		--..Test hook (server-side only; clients can't set it): model:SetAttribute("LaundryPress", "Start" | "Door")..--
		ctx:Connect(model:GetAttributeChangedSignal("LaundryPress"), function()
			local what = model:GetAttribute("LaundryPress")
			if what == nil then return end
			model:SetAttribute("LaundryPress", nil)
			if what == "Start" then PressStart() elseif what == "Door" then PressDoor() end
		end)

		Refresh()
	end

	return B
end

local M = Make("Washer")
M.Make = Make
M.CYCLE = CYCLE
return M
