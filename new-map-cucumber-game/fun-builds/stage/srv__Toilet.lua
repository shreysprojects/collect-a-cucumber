--[[
	Toilet  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the WORKING TOILET (fun-builds/CONTRACT.md; model = fun-builds/models/build_Toilet.py).
	  * one seat on the toilet seat (ctx:Seat, prompt "Sit", anyone may use it): its top face at Pivot_Seat,
	    facing the build's front (-Z), so the sitter faces out over the bath mat.
	  * "Flush" prompt (R / ButtonY) on the cistern's flush lever (FlushPlate / Pivot_Handle), usable standing
	    or sitting: stamps state FlushAt = server time (Fun_FlushAt). Every client plays the same flush from
	    that time (the lever dips, a blue swirl spins down the bowl, the flush sound). One flush per
	    FLUSH_COOLDOWN seconds per toilet.
	No economy, no physics on characters (the seat weld carries the sitter).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local SEAT_NAME = "ToiletSeat"
local SEAT_SIZE = Vector3.new(2, 0.4, 2)
local SEAT_FALLBACK = Vector3.new(0, 2.12, -0.15)   -- authored Pivot_Seat of build_Toilet.py
local HANDLE_FALLBACK = Vector3.new(0.98, 3.42, 0.6) -- authored Pivot_Handle
local SIT_PROMPT_OFFSET = Vector3.new(0, 1.4, -0.9)  -- in the seat's space (Y up, -Z = the front)
local FLUSH_PROMPT_OUT = 0.5                         -- authored studs in front of the lever pivot
local PROMPT_DISTANCE = 8
local FLUSH_COOLDOWN = 3.0

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

	--..The seat (faces the build's front)..--
	local seatTop = Kit.ToWorld(model, Authored(model, "Seat", SEAT_FALLBACK))
	local seatCF = CFrame.new(seatTop) * origin.Rotation * CFrame.new(0, -SEAT_SIZE.Y * 0.5, 0)
	ctx:Seat(seatCF, {
		Name = SEAT_NAME,
		Size = Vector3.new(SEAT_SIZE.X * s, SEAT_SIZE.Y, SEAT_SIZE.Z * s),
		Prompt = "Sit",
		Object = "Toilet",
		Distance = math.max(PROMPT_DISTANCE, 6 * s),
		PromptOffset = SIT_PROMPT_OFFSET * Vector3.new(s, 1, s),
	})

	--..Flush..--
	ctx:SetState("FlushAt", 0)
	local pivot = Authored(model, "Handle", HANDLE_FALLBACK)
	local host = Kit.Part(model, "FlushPlate") or Kit.Part(model, "Tank") or Kit.Hitbox(model)
	local at = Kit.ToWorld(model, pivot + Vector3.new(0, 0, -FLUSH_PROMPT_OUT))
	local prompt = ctx:Prompt(host, {
		Action = "Flush",
		Object = "Toilet",
		Name = "FlushPrompt",
		Key = Enum.KeyCode.R,
		Gamepad = Enum.KeyCode.ButtonY,
		Distance = math.max(PROMPT_DISTANCE, 6 * s),
		Offset = host.CFrame:PointToObjectSpace(at),
	})
	local last = -math.huge
	ctx:Connect(prompt.Triggered, function(player)
		local now = os.clock()
		if now - last < FLUSH_COOLDOWN or not ctx:HumanoidOf(player) then return end
		last = now
		ctx:SetState("FlushAt", Kit.Now())
	end)
end

return B
