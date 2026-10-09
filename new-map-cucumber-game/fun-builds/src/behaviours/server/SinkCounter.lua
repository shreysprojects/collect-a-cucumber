--[[
	SinkCounter  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the WORKING KITCHEN COUNTER (client half: ReplicatedStorage.FunBehavioursClient.SinkCounter;
	fun-builds/CONTRACT.md; model = fun-builds/models/build_SinkCounter.py). Two prompts, two states:
	  * "Tap on" / "Tap off" in front of the faucet (Pivot_Tap) toggles state Tap (Fun_Tap). A tap left running
	    turns itself off after TAP_AUTO_OFF seconds (nobody has to hear it forever).
	  * "Make toast" over the toaster (Pivot_Toaster) sets state ToastAt (Fun_ToastAt) = the server time the toast
	    pops (now + TOAST_DELAY). Clients animate the whole cycle from that one number: lever down + slots glow
	    while toasting, the Toast* slices pop up 0.8 stud at ToastAt with ToasterPop + Ding, hold POP_HOLD
	    seconds, then slide back down. The prompt reads "Toasting..." (and presses are ignored) until the cycle
    is over. It is never disabled from here: the framework owns Enabled (it hides prompts in build mode).
	Anyone may use both (nothing to grief). No economy, no physics, no build parts touched on the server.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local TAP_FALLBACK = Vector3.new(0, 4.1, 0.55)          -- authored prompt spots (Pivot_Tap / Pivot_Toaster)
local TOASTER_FALLBACK = Vector3.new(-2.75, 5.31, 0.05)
local PROMPT_DISTANCE = 8                               -- studs at scale 1
local TOGGLE_DEBOUNCE = 0.4                             -- seconds between two tap toggles
local TAP_AUTO_OFF = 120                                -- seconds a tap runs before it shuts itself off
local TOAST_DELAY = 4                                   -- seconds from "Make toast" to the pop
local POP_HOLD = 5                                      -- seconds the toast stays up
local SLIDE_TIME = 0.6                                  -- seconds it takes to slide back down
-- (TOAST_DELAY / POP_HOLD / SLIDE_TIME are repeated in the client half: keep them the same)
local IDLE_TEXT = "Make toast"                          -- toaster prompt text, idle / during a cycle
local BUSY_TEXT = "Toasting..."

local B = {}
B.ActionRange = 30

--..Helpers..--
local function PromptAt(model, ctx, pivot, fallback, opts)
	local hitbox = Kit.Hitbox(model)
	local at = Kit.Pivot(model, pivot) or Kit.ToWorld(model, fallback)
	opts.Offset = hitbox.CFrame:PointToObjectSpace(at)
	opts.Distance = math.max(PROMPT_DISTANCE, PROMPT_DISTANCE * ctx.Scale)
	return ctx:Prompt(hitbox, opts)
end

--..Behaviour..--
function B.Server(model, ctx)
	if not Kit.Hitbox(model) then return end
	ctx:SetState("Tap", false)
	ctx:SetState("ToastAt", 0)

	--..Tap..--
	local tap = PromptAt(model, ctx, "Tap", TAP_FALLBACK, {Action = "Tap on", Object = "Kitchen sink", Name = "TapPrompt"})
	local lastTap, tapRun = 0, 0
	local function SetTap(on)
		ctx:SetState("Tap", on)
		tap.ActionText = on and "Tap off" or "Tap on"
		tapRun += 1
		if on then
			local run = tapRun
			task.delay(TAP_AUTO_OFF, function()
				if ctx:Alive() and tapRun == run and ctx:GetState("Tap") == true then SetTap(false) end
			end)
		end
	end
	ctx:Connect(tap.Triggered, function(player)
		local now = os.clock()
		if now - lastTap < TOGGLE_DEBOUNCE or not ctx:HumanoidOf(player) then return end
		lastTap = now
		SetTap(ctx:GetState("Tap") ~= true)
	end)

	--..Toaster..--
	local toast = PromptAt(model, ctx, "Toaster", TOASTER_FALLBACK, {Action = IDLE_TEXT, Object = "Toaster", Name = "ToastPrompt"})
	ctx:Connect(toast.Triggered, function(player)
		if not ctx:HumanoidOf(player) then return end
		local now = Kit.Now()
		local popAt = tonumber(ctx:GetState("ToastAt")) or 0
		if now < popAt + POP_HOLD + SLIDE_TIME then return end -- still toasting / popped / sliding back
		local cycle = now + TOAST_DELAY
		ctx:SetState("ToastAt", cycle)
		--.. feedback through the text only: never write toast.Enabled here (the framework's client hides every
		--.. FunBuildPrompt in build mode by flipping Enabled locally; a server write would override that)
		toast.ActionText = BUSY_TEXT
		task.delay(TOAST_DELAY + POP_HOLD + SLIDE_TIME, function()
			if ctx:Alive() and ctx:GetState("ToastAt") == cycle then toast.ActionText = IDLE_TEXT end
		end)
	end)
end

return B
