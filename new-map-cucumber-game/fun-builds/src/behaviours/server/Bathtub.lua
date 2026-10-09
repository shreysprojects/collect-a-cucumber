--[[
	Bathtub  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the BUBBLE BATH (fun-builds/CONTRACT.md; model = fun-builds/models/build_Bathtub.py).
	  * one LYING seat in the tub (ctx:Seat{Lie = true}, prompt "Take a bath", anyone may use it): its top face
	    sits at Pivot_BathSeat (the bather's pelvis) and its LookVector points at Pivot_BathHead, so the head
	    lies toward the end WITHOUT taps (-X, the bath pillow) reclined ~10 degrees, the torso at the water line
	    and the feet still inside the tub. The prompt floats over the front rim.
	  * "Bubbles" prompt (R / ButtonY) on the gold filler (Pivot_Taps) toggles state Bubbles (Fun_Bubbles);
	    switching them on also stamps Fun_BubblesAt = server time, so every client plays the same surge (the tap
	    pours, a burst of foam) once. Bubbles switch themselves off after AUTO_OFF seconds.
	  * someone getting in / out fires "Splash" {Position, Big} to every client (spray + splash sound there).
	State for the client half (ReplicatedStorage.FunBehavioursClient.Bathtub):
	  Fun_Bubbles   bool, the foam is running
	  Fun_BubblesAt server time of the last switch-on (0 = never)
	  Fun_Bathing   bool, someone is in the tub (the duck bobs harder)
	No economy, no physics on characters (the seat weld carries the bather).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local SEAT_NAME = "BathSeat"
local SEAT_THICK = 0.4                                  -- invisible seat height (its top face = Pivot_BathSeat)
local SEAT_FALLBACK = Vector3.new(-1.2, 1.8, 0)         -- authored Pivot_BathSeat of build_Bathtub.py
local HEAD_FALLBACK = Vector3.new(-3.56, 2.22, 0)       -- authored Pivot_BathHead
local TAPS_FALLBACK = Vector3.new(3.88, 3.6, 0)         -- authored Pivot_Taps
local BATH_PROMPT_AT = Vector3.new(-0.3, 3.5, -1.25)    -- authored: over the front rim, mid-tub
local BATH_PROMPT_DISTANCE = 9
local BUBBLES_PROMPT_DISTANCE = 9
local BUBBLES_DEBOUNCE = 0.8                            -- seconds between two toggles
local AUTO_OFF = 300                                    -- seconds the foam runs by itself

local B = {}

--..Helpers..--
local function Authored(model, name, fallback)
	local v = model:GetAttribute("Pivot_" .. name)
	return typeof(v) == "Vector3" and v or fallback
end

--..Behaviour..--
function B.Server(model, ctx)
	local s = ctx.Scale
	local origin = Kit.Origin(model)
	local up = origin.UpVector

	--..The lying seat..--
	local seatAt = Kit.ToWorld(model, Authored(model, "BathSeat", SEAT_FALLBACK))
	local headAt = Kit.ToWorld(model, Authored(model, "BathHead", HEAD_FALLBACK))
	local look = headAt - seatAt
	look = look.Magnitude > 0.01 and look.Unit or -origin.RightVector
	local seatCF = CFrame.lookAt(seatAt, seatAt + look, up) * CFrame.new(0, -SEAT_THICK * 0.5, 0) -- top face on the pivot
	local seat = ctx:Seat(seatCF, {
		Name = SEAT_NAME,
		Size = Vector3.new(2 * s, SEAT_THICK, 3 * s),
		Lie = true,
		Prompt = "Take a bath",
		Object = "Bathtub",
		Distance = math.max(BATH_PROMPT_DISTANCE, 7 * s),
		PromptOffset = seatCF:PointToObjectSpace(Kit.ToWorld(model, BATH_PROMPT_AT)),
	})
	ctx:SetState("Bathing", false)
	ctx:Connect(seat:GetPropertyChangedSignal("Occupant"), function()
		local bathing = seat.Occupant ~= nil
		if ctx:GetState("Bathing") == bathing then return end
		ctx:SetState("Bathing", bathing)
		ctx:Fire("Splash", {Position = seatAt + up * (0.9 * s), Big = bathing})
	end)

	--..Bubbles (the gold filler)..--
	ctx:SetState("Bubbles", false)
	ctx:SetState("BubblesAt", 0)
	local tapsAt = Kit.ToWorld(model, Authored(model, "Taps", TAPS_FALLBACK))
	local host = Kit.Part(model, "TapMixer") or Kit.Hitbox(model)
	local prompt = ctx:Prompt(host, {
		Action = "Bubbles",
		Object = "Bathtub",
		Name = "BubblesPrompt",
		Key = Enum.KeyCode.R,
		Gamepad = Enum.KeyCode.ButtonY,
		Distance = math.max(BUBBLES_PROMPT_DISTANCE, 7 * s),
		Offset = host.CFrame:PointToObjectSpace(tapsAt),
	})
	local last = 0
	local function SetBubbles(on)
		if on then ctx:SetState("BubblesAt", Kit.Now()) end
		ctx:SetState("Bubbles", on)
		prompt.ActionText = on and "Bubbles off" or "Bubbles"
	end
	ctx:Connect(prompt.Triggered, function(player)
		local now = os.clock()
		if now - last < BUBBLES_DEBOUNCE or not ctx:HumanoidOf(player) then return end
		last = now
		SetBubbles(ctx:GetState("Bubbles") ~= true)
	end)
	ctx:Every(5, function()
		if ctx:GetState("Bubbles") == true and Kit.Now() - (tonumber(ctx:GetState("BubblesAt")) or 0) > AUTO_OFF then
			SetBubbles(false)
		end
	end)
end

return B
