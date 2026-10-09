--[[
	Slide  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the SLIDE functional build (fun-builds/CONTRACT.md; user: "make all the fun stuff
	functional"). Client half: ReplicatedStorage.FunBehavioursClient.Slide (the ride itself - the local
	character is network-owned by its client, so all the sliding happens there).

	The prop (props/build_slide.py, BuildCatalog scale x1.5) is six rigid MeshParts. Authored ROBLOX frame
	(= Blender (x, z, -y); props-dump/Slide.txt @Notes): front = -Z, the ladder is at the BACK (+Z):
	  deck walking surface  Y 4.40, Z +2.45 .. +4.18, X +/-1.70 (fenced both sides, grab hoop over the back)
	  ladder rung axis      (0, 0.12, 5.04) -> (0, 4.70, 4.32): leans 8.9 deg toward the deck, rails X +/-1.42
	  chute riding surface  Y = 0.40 + 4.00 (1 - t)^2, Z = 2.45 - 7.85 t   (t 0 = mouth at the deck, 1 = exit)
	What this half adds:
	  * LADDER: two invisible, anchored TrussParts side by side (a TrussPart's cross-section is fixed at 2 x 2,
	    length a multiple of 2) laid along the ladder, together covering it between the rails (+/-2 studs of
	    the +/-2.13 rail lines at x1.5), their climbing faces 0.25 studs proud of the rungs on the +Z side,
	    their top edges flush with the deck and their feet buried in the ground, so walking into the ladder
	    anywhere between the rails climbs it and sidestepping while climbing does not drop you off. The grab
	    hoop (1.44 authored = 2.2 studs over the deck) is too low to walk under, so the client lifts a climber
	    who nears the top over the hoop onto the deck ("mantle").
	  * "Slide!" prompt on a helper part above the deck: the server checks the player really is up there -
	    their FEET (root height - standing hip height, so it holds for every physique) at least
	    PROMPT_FEET_BELOW authored under the deck surface, i.e. on the deck or the top two rungs, not on the
	    ground beside / behind it - and tells that player's client "Start" - the ride from the chute mouth.
	  * Action "Ride" (the client sends it when any ride starts): everyone else hears that rider's "whee".
	No economy impact, no speed boost: the ride exists only on the slide.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Geometry (authored frame, scale 1)..--
local DECK_Y = 4.40                           -- deck walking surface
local DECK_Z0, DECK_Z1 = 2.45, 4.18           -- deck front (chute mouth) / back edge
local LADDER_FOOT = Vector3.new(0, 0.12, 5.04) -- rung axis at the pads
local LADDER_TOP = Vector3.new(0, 4.70, 4.32)  -- rung axis at the top of the rails
local LADDER_RAIL_X = 1.42                     -- |X| of the ladder rails' centre lines (radius 0.14)

--..Config..--
local TRUSS_FACE_OUT = 0.25   -- studs (world) the climbing face stands proud of the rung axis (rungs are 0.17 thick at x1.5)
local TRUSS_WIDTH = 2         -- a TrussPart's cross-section is fixed at 2 x 2
local TRUSS_TOP_DROP = 0.05   -- studs the truss top sits under the deck surface (no invisible lip on the deck)
local PROMPT_HEIGHT = 2.0     -- authored studs above the deck (about a standing root)
local PROMPT_DISTANCE = 4     -- authored studs (x Scale): the deck and the top rungs
--.. authored: the player's feet must be at most this far under the deck surface to start (the top two rungs,
--.. 3.38 / 4.24, pass; the ground never does, whatever the physique)
local PROMPT_FEET_BELOW = 1.5
local START_COOLDOWN = 1.2    -- s between two prompt starts per player
local WHEE_COOLDOWN = 1.0     -- s between two "whee" broadcasts per player

--..Variables..--
local LastWhee = setmetatable({}, {__mode = "k"}) -- [player] = os.clock(), every slide

local B = {}
B.ActionRange = 40

--..Ladder trusses..--
--.. two trusses side by side: one 2-stud truss in the middle left only the central 2 of the ladder's ~4.3 studs
--.. climbable (the humanoid's climb probe looks ahead of the character's centre, so an off-centre walk-in or a
--.. sidestep met the rails and rungs instead)
local function MakeTrusses(model, ctx)
	local s = ctx.Scale
	local origin = Kit.Origin(model)
	local up = (LADDER_TOP - LADDER_FOOT).Unit       -- authored, up the ladder
	local back = Vector3.new(0, -up.Z, up.Y)         -- authored, out of the ladder toward the climber (+Z)
	local upW = origin:VectorToWorldSpace(up)
	local backW = origin:VectorToWorldSpace(back)
	local rightW = upW:Cross(backW)                  -- across the ladder (authored +X)
	--.. the point on the rung axis where the climbing face's top edge lands just under the deck surface
	local topY = (DECK_Y * s - TRUSS_TOP_DROP - back.Y * TRUSS_FACE_OUT) / s
	local axisTop = LADDER_FOOT + up * ((topY - LADDER_FOOT.Y) / up.Y)
	local faceTop = origin:PointToWorldSpace(axisTop * s) + backW * TRUSS_FACE_OUT
	--.. long enough to reach from the deck into the ground
	local length = math.max(2, 2 * math.ceil((DECK_Y * s + 0.6) / up.Y / 2))
	local centre = faceTop - backW * (TRUSS_WIDTH * 0.5) - upW * (length * 0.5)
	--.. each truss's centre this far either side of the ladder's centre line: 1 stud at x1.5 (they meet in the
	--.. middle and span +/-2 inside the +/-2.13 rail lines); less on a smaller slide, so they overlap instead of
	--.. standing out past the rails
	local side = math.clamp(LADDER_RAIL_X * s - TRUSS_WIDTH * 0.5, 0, TRUSS_WIDTH * 0.5)
	local trusses = {}
	for i, dx in ipairs({-1, 1}) do
		local truss = Instance.new("TrussPart")
		truss.Name = "SlideLadderTruss" .. i
		truss.Style = Enum.Style.NoSupports
		truss.Size = Vector3.new(TRUSS_WIDTH, length, TRUSS_WIDTH)
		truss.CFrame = CFrame.fromMatrix(centre + rightW * (dx * side), rightW, upW, backW)
		truss.Transparency = 1
		truss.Anchored = true
		truss.CanCollide = true
		truss.CanTouch = false
		truss.CastShadow = false
		truss.Parent = ctx.Folder
		ctx:Add(truss)
		trusses[i] = truss
	end
	return trusses
end

--.. a character's standing root height over its feet (R15 physique bodies scale HipHeight and the root)
local function StandLift(humanoid, root)
	if humanoid.RigType == Enum.HumanoidRigType.R6 then return 3 end
	return humanoid.HipHeight + root.Size.Y * 0.5
end

--..Behaviour..--
function B.Server(model, ctx)
	local s = ctx.Scale
	MakeTrusses(model, ctx)

	--.. the "Slide!" prompt, above the middle of the deck
	local deckMid = (DECK_Z0 + DECK_Z1) * 0.5
	local top = ctx:Part({
		Name = "SlideTop",
		Size = Vector3.new(0.4, 0.4, 0.4),
		Transparency = 1,
		CFrame = Kit.CFrameToWorld(model, CFrame.new(0, DECK_Y + PROMPT_HEIGHT, deckMid)),
	})
	local prompt = ctx:Prompt(top, {Action = "Slide!", Object = "Slide", Distance = PROMPT_DISTANCE * s, Name = "SlidePrompt"})
	local lastStart = setmetatable({}, {__mode = "k"})
	ctx:Connect(prompt.Triggered, function(player)
		local now = os.clock()
		if lastStart[player] and now - lastStart[player] < START_COOLDOWN then return end
		local humanoid, root = ctx:HumanoidOf(player)
		if not humanoid or humanoid.SeatPart then return end
		--.. gate on the FEET, not the root: a Muscular+ body's root stands 5+ studs over the ground, higher than a
		--.. default climber's on the top rungs, and the prompt's range reaches the ground behind / beside the deck
		local feet = (Kit.Origin(model):PointToObjectSpace(root.Position).Y - StandLift(humanoid, root)) / s
		if feet < DECK_Y - PROMPT_FEET_BELOW then return end -- on the ground: climb up first
		lastStart[player] = now
		ctx:FireTo(player, "Start", true)
	end)
end

B.Actions = {
	--.. a ride started on this player's client: everyone plays the whee at that rider
	Ride = function(_model, player, _payload, ctx)
		local now = os.clock()
		if LastWhee[player] and now - LastWhee[player] < WHEE_COOLDOWN then return end
		LastWhee[player] = now
		ctx:Fire("Whee", player.UserId)
	end,
}

return B
