--[[
	HotTub  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the WORKING HOT TUB (fun-builds/CONTRACT.md; model = props/build_hot_tub.py, template x1.4).
	  * walk-in water: Water / Foam / Steam stop colliding while the behaviour runs, so people can climb the
	    steps, hop over the rim and stand in the tub. With OWN_COLLIDERS the visual meshes (Shell, staves,
	    steel) stop colliding too and invisible helper blocks in the runtime folder stand in for the rim wall,
	    the bench ring, the floor and the two steps - exact to the authored geometry whatever
	    CollisionFidelity the imported meshes got (a Hull / Box shell would fill the cavity).
	  * 4 seats over the submerged bench ring (authored top y 1.35, 0.90 under the surface y 2.25) facing the
	    centre. A sitting root rides ~1.7 over its seat's top face (CONTRACT playtest), so a seat ON the bench
	    would leave the water at the hips (root ~0.45 over the surface at x1.4): each seat is sunk (seatSink)
	    below the bench top instead, putting the root ROOT_UNDER_SURFACE under the water = chest-deep (the
	    waterline sits on the lower chest; the thighs dip into the bench slab, hidden under the water).
	    Each seat's "Hop in" prompt floats over the rim behind it with a short reach, so someone already
	    sitting only sees the jets prompt, never a neighbour's seat.
	  * "Bubbles on / off" prompt on the control panel (Pivot_PanelTop) toggles state Jets (Fun_Jets).
	  * splashes: someone sitting down, or a client reporting its character stepped into the water (checked
	    here against the character's real position, cooldown per player), fire "Splash" {Position, Big} to
	    every client (the client half plays the sound and the spray).
	Anyone may use it (nothing to grief). No economy, no physics on characters (the seat weld carries them).
	Restores every part it touched when it stops, unless the build is Broken (BuildHealthService owns the
	collisions then and gives back what it recorded on mend).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local OWN_COLLIDERS = true                       -- false = trust the meshes' own collision (see notes/HotTub.md)
local WALK_THROUGH = {"Water", "Foam", "Steam"}  -- never collide while the behaviour runs
local SHELL_PARTS = {"Shell", "StavesMid", "StavesPale", "Steel"} -- replaced by the helper colliders (OWN_COLLIDERS)
local SEAT_ANGLES = {0, 90, 180, 270}            -- degrees about the axis, plan point (cos, sin) * r: right, back, left, front (the panel is at 232)
local SEAT_RADIUS = 2.22                         -- authored: bench ring 1.98..2.58, a bit in so the back clears the 2.62 wall
local SEAT_THICK = 0.4                           -- invisible seat height (the framework default the sit offset was measured on)
local SIT_ROOT_OVER_TOP = 1.7                    -- world studs a sitting root rides over the seat's TOP face (CONTRACT: ~1.9 over a 0.4 seat's centre)
local ROOT_UNDER_SURFACE = 0.7                   -- world studs the sitting root ends up under the water: waterline ~0.7 over the root = lower chest on a default R15
local SEAT_MIN_OVER_FLOOR = 0.2                  -- world studs the sunk seat top keeps over the tub floor (a sitter's soles hang ~0.2 under the seat top)
local SEAT_PROMPT_ABOVE_RIM = 1.0                -- world studs the "Hop in" prompt floats over the rim
local JETS_DEBOUNCE = 0.4                        -- seconds between two jets toggles
local SPLASH_COOLDOWN = 1.5                      -- seconds per player between splashes
local SPLASH_GAP = 0.2                           -- seconds between any two splashes of one tub
local MAX_SPLASH_FEET = 6                        -- world studs the feet may still be over the surface when a client splash arrives
local PANEL_PROMPT_LIFT = 0.5                    -- authored studs over Pivot_PanelTop

--.. authored geometry of props/build_hot_tub.py (scale 1, Roblox authored frame: floor centre = origin, front = -Z)
local GEO = {
	WallIn = 2.62, WallOut = 3.20, RimTop = 2.56, -- cavity wall / outer edge of the coping rim / rim top (sit surface)
	BenchIn = 1.98, BenchTop = 1.35,              -- submerged bench ring
	FloorTop = 0.28,                              -- inner floor
	WaterTop = 2.25,                              -- fallback for Pivot_WaterSurface
	Segments = 12,                                -- collider blocks per ring
	Steps = {                                     -- the two treads on the front face: {min corner, max corner}
		{Vector3.new(-1.00, 0, -3.66), Vector3.new(1.00, 1.30, -2.95)},
		{Vector3.new(-1.00, 0, -4.32), Vector3.new(1.00, 0.62, -3.64)},
	},
}

local B = {}
B.ActionRange = 30

--..Helpers..--
--.. the same part on the build's template (ReplicatedStorage.PlaceableBuilds/<Category>/<Key>): its authored
--.. values, safe from whatever a break / mend cycle left on the placed copy
local function TemplatePart(model, name)
	local root = ReplicatedStorage:FindFirstChild("PlaceableBuilds")
	if not root then return nil end
	local key = tostring(Kit.Key(model))
	local category = root:FindFirstChild(tostring(model:GetAttribute("Category")))
	local template = category and category:FindFirstChild(key)
	if not template then
		for _, c in ipairs(root:GetChildren()) do
			template = c:FindFirstChild(key)
			if template then break end
		end
	end
	local part = template and template:FindFirstChild(name, true)
	return (part and part:IsA("BasePart")) and part or nil
end

--.. the water-surface centre as a world CFrame (authored axes) and the surface height (authored)
local function SurfaceOf(model)
	local p = model:GetAttribute("Pivot_WaterSurface")
	if typeof(p) ~= "Vector3" then p = Vector3.new(0, GEO.WaterTop, 0) end
	return Kit.CFrameToWorld(model, CFrame.new(p)), p.Y
end

--.. fire a splash at a world point, dropped onto the water surface
local function Splash(ctx, worldPos, big)
	local st = ctx.HotTub
	if not st then return end
	local now = os.clock()
	if now - st.LastAny < SPLASH_GAP then return end
	st.LastAny = now
	local rel = st.Surface:PointToObjectSpace(worldPos)
	ctx:Fire("Splash", {Position = st.Surface:PointToWorldSpace(Vector3.new(rel.X, 0, rel.Z)), Big = big == true})
end

--..Colliders..--
--.. invisible blocks matching the authored tub: 12 wall/rim blocks (WallIn..WallOut, floor to rim top), 12 bench
--.. blocks (BenchIn..wall, solid from the floor so nothing snags under the slab), a floor disc and the two treads
local function BuildColliders(model, ctx)
	local s = ctx.Scale
	local n = GEO.Segments
	local half = math.pi / n
	local function Block(name, authoredCF, size, shape)
		local props = {
			Name = name, CFrame = Kit.CFrameToWorld(model, authoredCF), Size = size * s,
			Transparency = 1, CanCollide = true, CanQuery = true, Material = Enum.Material.Wood,
		}
		if shape then props.Shape = shape end
		ctx:Part(props)
	end
	--.. each block is as wide as the ring's chord at its OUTER radius, so neighbours overlap inside the solid
	local wallMid, wallDepth = (GEO.WallIn + GEO.WallOut) * 0.5, GEO.WallOut - GEO.WallIn
	local wallWidth = 2 * GEO.WallOut * math.tan(half)
	local benchOut = GEO.WallIn + 0.02
	local benchMid, benchDepth = (GEO.BenchIn + benchOut) * 0.5, benchOut - GEO.BenchIn
	local benchWidth = 2 * benchOut * math.tan(half)
	for i = 0, n - 1 do
		local a = (i + 0.5) * 2 * half
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local wallAt = dir * wallMid + Vector3.new(0, GEO.RimTop * 0.5, 0)
		Block("HotTubWall" .. i, CFrame.lookAt(wallAt, Vector3.new(0, wallAt.Y, 0)), Vector3.new(wallWidth, GEO.RimTop, wallDepth))
		local benchAt = dir * benchMid + Vector3.new(0, GEO.BenchTop * 0.5, 0)
		Block("HotTubBench" .. i, CFrame.lookAt(benchAt, Vector3.new(0, benchAt.Y, 0)), Vector3.new(benchWidth, GEO.BenchTop, benchDepth))
	end
	--.. floor: a cylinder (Roblox cylinders run along X: turned upright)
	Block("HotTubFloor", CFrame.new(0, GEO.FloorTop * 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(GEO.FloorTop, benchOut * 2, benchOut * 2), Enum.PartType.Cylinder)
	for i, box in ipairs(GEO.Steps) do
		local lo, hi = box[1], box[2]
		Block("HotTubStep" .. i, CFrame.new((lo + hi) * 0.5), hi - lo)
	end
end

--..Behaviour..--
function B.Server(model, ctx)
	local s = ctx.Scale
	local surfaceCF, waterTop = SurfaceOf(model)
	local st = {Surface = surfaceCF, LastSplash = setmetatable({}, {__mode = "k"}), LastAny = 0}
	ctx.HotTub = st

	--..Walk-in water..--
	local restore = {} -- [part] = authored CanCollide
	local function NoCollide(name)
		local part = Kit.Part(model, name)
		if not part then return end
		local template = TemplatePart(model, name)
		if template then restore[part] = template.CanCollide else restore[part] = part.CanCollide end
		part.CanCollide = false
	end
	for _, name in ipairs(WALK_THROUGH) do NoCollide(name) end
	if OWN_COLLIDERS then
		for _, name in ipairs(SHELL_PARTS) do NoCollide(name) end
		BuildColliders(model, ctx)
	end

	--..Seats on the bench ring..--
	--.. sink each seat below the bench top so the sitting root lands ROOT_UNDER_SURFACE under the water
	--.. (0.44 + 0.7 = 1.14 world studs at x1.4), never so deep that the seat top reaches the tub floor
	local seatSink = math.clamp((GEO.BenchTop - waterTop) * s + SIT_ROOT_OVER_TOP + ROOT_UNDER_SURFACE,
		0, math.max(0, (GEO.BenchTop - GEO.FloorTop) * s - SEAT_MIN_OVER_FLOOR))
	local promptBack = ((GEO.WallIn + GEO.WallOut) * 0.5 - SEAT_RADIUS) * s -- behind the seat, over the rim
	local promptLift = SEAT_THICK * 0.5 + seatSink + (GEO.RimTop - GEO.BenchTop) * s + SEAT_PROMPT_ABOVE_RIM
	local promptReach = math.max(4.5, 3.6 * s) -- a seated player's neighbour prompts stay out of reach (5.55 away at x1.4)
	for i, deg in ipairs(SEAT_ANGLES) do
		local a = math.rad(deg)
		local benchPoint = Vector3.new(math.cos(a) * SEAT_RADIUS, GEO.BenchTop, math.sin(a) * SEAT_RADIUS)
		local facing = CFrame.lookAt(benchPoint, Vector3.new(0, GEO.BenchTop, 0)) -- LookVector at the centre
		local seatCF = Kit.CFrameToWorld(model, facing) * CFrame.new(0, -SEAT_THICK * 0.5 - seatSink, 0)
		local seat = ctx:Seat(seatCF, {
			Name = "HotTubSeat" .. i,
			Size = Vector3.new(2, SEAT_THICK, 2),
			Prompt = "Hop in",
			Distance = promptReach,
			PromptOffset = Vector3.new(0, promptLift, promptBack),
		})
		ctx:Connect(seat:GetPropertyChangedSignal("Occupant"), function()
			local humanoid = seat.Occupant
			if not humanoid then return end
			local player = Players:GetPlayerFromCharacter(humanoid.Parent)
			if player then st.LastSplash[player] = os.clock() end
			Splash(ctx, seat.Position, false)
		end)
	end

	--..Jets (control panel)..--
	ctx:SetState("Jets", false)
	local panel = Kit.Part(model, "Panel")
	local panelTop = model:GetAttribute("Pivot_PanelTop")
	if panel and typeof(panelTop) == "Vector3" then
		local at = Kit.ToWorld(model, panelTop + Vector3.new(0, PANEL_PROMPT_LIFT, 0))
		local prompt = ctx:Prompt(panel, {
			Action = "Bubbles on",
			Name = "JetsPrompt",
			Distance = 10,
			Offset = panel.CFrame:PointToObjectSpace(at),
		})
		local last = 0
		ctx:Connect(prompt.Triggered, function(player)
			local now = os.clock()
			if now - last < JETS_DEBOUNCE or not ctx:HumanoidOf(player) then return end
			last = now
			local on = ctx:GetState("Jets") ~= true
			ctx:SetState("Jets", on)
			prompt.ActionText = on and "Bubbles off" or "Bubbles on"
		end)
	else
		warn("[HotTub] no Panel part / Pivot_PanelTop on " .. model:GetFullName() .. " - no jets prompt")
	end

	return function()
		if Kit.IsBroken(model) then return end -- BuildHealthService recorded (and will give back) the collisions
		for part, value in pairs(restore) do
			if part.Parent then part.CanCollide = value end
		end
	end
end

--..Actions..--
B.Actions = {
	--.. the client says its character just stepped into the water; payload ignored, the position is checked here
	Splash = function(_model, player, _payload, ctx)
		local st = ctx.HotTub
		if not st then return end
		local now = os.clock()
		if now - (st.LastSplash[player] or 0) < SPLASH_COOLDOWN then return end
		local humanoid, root = ctx:HumanoidOf(player)
		if not humanoid or humanoid.SeatPart then return end
		local s = ctx.Scale
		local rel = st.Surface:PointToObjectSpace(root.Position)
		local r = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
		local feet = rel.Y - (humanoid.HipHeight + root.Size.Y * 0.5) -- feet height over the surface
		--.. over the water and in it or just dropping in: the server sees a falling character a few frames late,
		--.. so the height check is loose (a splash is only a sound + spray; the cooldown stops spam)
		if r > GEO.WallIn * s + 0.8 or feet > MAX_SPLASH_FEET or feet < -GEO.WaterTop * s - 1.5 then return end
		st.LastSplash[player] = now
		Splash(ctx, root.Position, true)
	end,
}

return B
