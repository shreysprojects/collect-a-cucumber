--[[
	Tree  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLife
	Client-only behaviour for the three garden trees (no server half: nothing is shared but the clock).
	  Tree_A Oak (x1.6)   Tree_B Pine (x1.6)   Tree_C Sapling (x1.5)
	  * WIND SWAY: the crown parts (A_CrownBody / A_CrownSun, B_CanopyDark / B_CanopyBlue, C_CrownBody /
	    C_CrownSun / C_Fruit) lean and rock a degree or two about the foot of the trunk (the authored trunk axis:
	    A x=10, B x=0, C x=-9.5, all on y=0 z=0). The trunk and the roots never move. One wind for the whole map
	    (WIND): every tree leans the same way, its gust period (3-5 s) and phase come from where it stands, and the
	    pose is a pure function of the SERVER clock (Kit.Now), so every client sees the same sway.
	  * FALLING LEAVES (Oak, Sapling - the Pine keeps its needles): every few seconds a flat oval leaf drops out of
	    the underside of the crown, flutters down on the wind, lies on the grass a moment and fades. Local parts
	    (ctx:Part, under the camera) recycled from a pool of LEAF_POOL; crown colours plus a few autumn ones.
	Cheap: one ctx:Step; the crown is posed with one BulkMoveTo, every frame near the camera, at FAR_HZ beyond NEAR,
	not at all while the tree is off screen, and the Step sleeps past StepRange. New leaves only within LEAF_RANGE.
	Cleanup puts every crown part back at rest relative to the build's CURRENT hitbox (so a move that raced the
	sway still ends with the crown on the trunk).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local WIND = Vector3.new(0.83, 0, 0.56).Unit      -- the way the wind blows (world); Sunflower / Bush use the same
local WIND_AXIS = Vector3.yAxis:Cross(WIND).Unit  -- turning +Y about this by a positive angle leans it downwind
local NEAR = 90                  -- studs camera -> tree: posed every frame closer than this ...
local FAR_HZ = 20                -- ... and this often farther away
local CLOSE = 40                 -- always posed this close (the on-screen test is for the crown centre only)
local LEAF_RANGE = 110           -- no new leaves while the camera is farther than this
local LEAF_POOL = 5
local LEAF_LIE, LEAF_FADE = 1.4, 1.0 -- seconds a landed leaf lies on the grass, then fades out
local AUTUMN = {Color3.fromRGB(226, 178, 58), Color3.fromRGB(214, 118, 44)}
local FOLIAGE = {"Crown", "Canopy", "Fruit", "Leaves", "Foliage"} -- part names (after the variant prefix) that sway
local MAIN = {"CrownBody", "Canopy", "Crown"}                      -- the big crown mass the leaves fall out of

--.. per variant: Foot = trunk foot (AUTHORED), Amp = sway degrees, Leaf = falling leaves (nil = none).
--.. Leaf.Size is AUTHORED studs (x ctx.Scale), Every = seconds between leaves, Fall = studs/s
local TREES = {
	A = {Foot = Vector3.new(10, 0, 0), Amp = 1.6,
		Leaf = {Size = Vector3.new(0.3, 0.03, 0.2), Every = {1.6, 4.2}, Fall = {1.5, 2.3}}},
	B = {Foot = Vector3.new(0, 0, 0), Amp = 0.9},
	C = {Foot = Vector3.new(-9.5, 0, 0), Amp = 2.4,
		Leaf = {Size = Vector3.new(0.26, 0.03, 0.17), Every = {3, 6.5}, Fall = {1.4, 2.1}}},
}
local DEFAULT_TREE = {Amp = 1.4}

local B = {}
B.StepRange = 170

--..Helpers..--
--.. 32-bit multiply without losing precision in doubles
local function Mul32(a, b)
	local hi, lo = math.floor(a / 65536), a % 65536
	return ((hi * b) % 65536 * 65536 + lo * b) % 4294967296
end

--.. integer hash -> 0..1, identical on every client
local function Hash(k, salt)
	local x = (math.floor(k) * 2 + salt * 40503 + 1) % 4294967296
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = Mul32(x, 0x45D9F3B)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = Mul32(x, 0x45D9F3B)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x / 4294967296
end

--.. 0..1 from a world position (per-build phase / period)
local function PlaceHash(p, salt)
	return Hash((math.floor(p.X * 8) % 65536) * 65536 + math.floor(p.Z * 8) % 65536, salt)
end

local function HasWord(name, words)
	for _, word in ipairs(words) do
		if name:find(word, 1, true) then return true end
	end
	return false
end

local function SameCFrame(a, b)
	return (a.Position - b.Position).Magnitude < 1e-3 and a.LookVector:Dot(b.LookVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
end

--.. is a world point on screen (margin = extra fraction of the viewport around it)?
local function OnScreen(point, margin)
	local cam = workspace.CurrentCamera
	if not cam then return false end
	local v = cam:WorldToViewportPoint(point)
	if v.Z <= 0 then return false end
	local size = cam.ViewportSize
	local mx, my = size.X * margin, size.Y * margin
	return v.X >= -mx and v.X <= size.X + mx and v.Y >= -my and v.Y <= size.Y + my
end

--.. BulkMoveTo the first n entries (the tables are reused frame to frame)
local function Move(list, cfs, n)
	for i = #list, n + 1, -1 do
		list[i] = nil
		cfs[i] = nil
	end
	if n > 0 then workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
end

--..Falling leaves (same shape as Bush's)..--
--.. a pool of flat oval leaves (a Part + SpecialMesh Sphere), hidden until Launch
local function MakeLeaves(ctx, count, size, at)
	local pool = {}
	for i = 1, count do
		local part = ctx:Part({Name = "FunLeaf", Size = size, Transparency = 1, Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(at)})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		pool[i] = {Part = part, Alive = false}
	end
	return pool
end

local function FreeLeaf(pool)
	for _, leaf in ipairs(pool) do
		if not leaf.Alive then return leaf end
	end
	return nil
end

--.. opts: Fall {min, max} studs/s, Up (studs it pops up first), Drift (studs/s Vector3), Sway (studs), Colors
local function Launch(leaf, from, rng, opts)
	leaf.Alive, leaf.Landed = true, nil
	leaf.T0 = os.clock()
	leaf.From = from
	leaf.Fall = rng:NextNumber(opts.Fall[1], opts.Fall[2])
	leaf.Up = opts.Up or 0
	local a = rng:NextNumber(0, 2 * math.pi)
	leaf.Side = Vector3.new(math.cos(a), 0, math.sin(a))
	leaf.Sway = rng:NextNumber(0.5, 1) * (opts.Sway or 0.7)
	leaf.Freq = rng:NextNumber(2.4, 3.6)
	leaf.Phase = rng:NextNumber(0, 2 * math.pi)
	leaf.Spin = rng:NextNumber(-2.2, 2.2)
	leaf.Drift = opts.Drift or WIND * 0.7
	leaf.Part.Color = opts.Colors[rng:NextInteger(1, #opts.Colors)]
	leaf.Part.Transparency = 0
end

--.. the CFrame to give a falling leaf at clock time c, or nil when it needs none (lying / faded)
local function LeafStep(leaf, c, groundY)
	if leaf.Landed then
		local lying = c - leaf.Landed
		if lying >= LEAF_LIE + LEAF_FADE then
			leaf.Alive = false
			leaf.Part.Transparency = 1
		elseif lying > LEAF_LIE then
			leaf.Part.Transparency = (lying - LEAF_LIE) / LEAF_FADE
		end
		return nil
	end
	local age = c - leaf.T0
	local swing = math.sin(leaf.Freq * age + leaf.Phase)
	local flat = leaf.From + leaf.Drift * age + leaf.Side * (leaf.Sway * swing)
	local y = leaf.From.Y + leaf.Up * (1 - math.exp(-age / 0.18)) - leaf.Fall * age
	local spin = CFrame.Angles(0, leaf.Spin * age, 0)
	if y <= groundY then
		leaf.Landed = c
		return CFrame.new(flat.X, groundY, flat.Z) * spin
	end
	--.. a falling leaf swings like a pendulum and tips toward the end of each swing
	return CFrame.new(flat.X, y, flat.Z) * spin * CFrame.Angles(0.45 * math.cos(leaf.Freq * age + leaf.Phase), 0, 0.6 * swing)
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	local cfg = TREES[ctx.Variant or ""] or DEFAULT_TREE
	local prefix = ctx.Variant and (ctx.Variant .. "_") or ""
	local scale = ctx.Scale

	--..Parts: the crown sways, the rest stays..--
	local crown, rel = {}, {}
	local home = hitbox.CFrame
	local main, mainVolume = nil, -1
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= hitbox and part.Name:sub(1, #prefix) == prefix then
			local name = part.Name:sub(#prefix + 1)
			if HasWord(name, FOLIAGE) then
				table.insert(crown, part)
				table.insert(rel, home:ToObjectSpace(part.CFrame))
				local volume = part.Size.X * part.Size.Y * part.Size.Z
				if HasWord(name, MAIN) and volume > mainVolume then main, mainVolume = part, volume end
			end
		end
	end
	if #crown == 0 then return end
	main = main or crown[1]
	local rest = {}
	for i, r in ipairs(rel) do rest[i] = home * r end

	--..Wind: per-tree period and phase from its position..--
	local footAuthored = cfg.Foot
	if not footAuthored then
		local c = Kit.AuthoredCentre(model)
		footAuthored = Vector3.new(c.X, 0, c.Z)
	end
	local foot = Kit.ToWorld(model, footAuthored)
	local where = home.Position
	local period = 3 + 2 * PlaceHash(where, 1)
	local phase = -where:Dot(WIND) * 0.07 + PlaceHash(where, 2) * 2 * math.pi -- the gust rolls downwind
	local w = 2 * math.pi / period
	local amp = math.rad(cfg.Amp)
	local function Pose(t)
		local lean = amp * (0.35 + 0.65 * (0.7 * math.sin(w * t + phase) + 0.3 * math.sin(2.37 * w * t + 1.7 * phase)))
		local roll = amp * 0.3 * math.sin(0.61 * w * t + 2.3 * phase)
		return CFrame.new(foot) * CFrame.fromAxisAngle(WIND_AXIS, lean) * CFrame.fromAxisAngle(WIND, roll) * CFrame.new(-foot)
	end
	local crownCentre = main.Position

	--..Falling leaves..--
	local leafCfg = cfg.Leaf
	local rng = Random.new()
	local pool, leafOpts, groundY
	if leafCfg then
		local size = leafCfg.Size * scale
		pool = MakeLeaves(ctx, LEAF_POOL, size, crownCentre)
		local colors = {}
		for _, part in ipairs(crown) do
			if not part.Name:find("Fruit", 1, true) then table.insert(colors, part.Color) end
		end
		table.insert(colors, main.Color) -- the main crown colour twice as often
		for _, c in ipairs(AUTUMN) do table.insert(colors, c) end
		leafOpts = {Fall = leafCfg.Fall, Sway = 0.45 * scale, Colors = colors}
		groundY = Kit.Floor(model).Position.Y + size.Y * 0.5 + 0.02
	end
	--.. a point inside the lower part of the (swayed) crown mass: the leaf falls out of its underside
	local function CrownPoint()
		local cf, size = main.CFrame, main.Size
		return cf:PointToWorldSpace(Vector3.new(rng:NextNumber(-0.38, 0.38) * size.X, rng:NextNumber(-0.42, 0.05) * size.Y,
			rng:NextNumber(-0.38, 0.38) * size.Z))
	end
	local nextLeaf = os.clock() + (leafCfg and rng:NextNumber(0.3, leafCfg.Every[2]) or math.huge)

	--..Step..--
	local list, cfs = {}, {}
	local lastPose, posed = -math.huge, false
	ctx:Step(function(_, now)
		if not (hitbox.Parent and SameCFrame(hitbox.CFrame, home)) then return end -- moved: the restart is on its way
		local c = os.clock()
		local dist = ctx:CameraDistance()
		local n = 0
		if (dist <= NEAR or c - lastPose >= 1 / FAR_HZ) and (dist <= CLOSE or OnScreen(crownCentre, 0.3)) then
			lastPose, posed = c, true
			local pose = Pose(now)
			for i, part in ipairs(crown) do
				n += 1
				list[n] = part
				cfs[n] = pose * rest[i]
			end
		end
		if pool then
			if c >= nextLeaf then
				nextLeaf = c + rng:NextNumber(leafCfg.Every[1], leafCfg.Every[2])
				local leaf = dist <= LEAF_RANGE and FreeLeaf(pool)
				if leaf then Launch(leaf, CrownPoint(), rng, leafOpts) end
			end
			for _, leaf in ipairs(pool) do
				if leaf.Alive then
					local cf = LeafStep(leaf, c, groundY)
					if cf then
						n += 1
						list[n] = leaf.Part
						cfs[n] = cf
					end
				end
			end
		end
		Move(list, cfs, n)
	end)

	--..Cleanup: the crown back on its trunk (relative to wherever the hitbox is now)..--
	return function()
		if not (posed and model:IsDescendantOf(workspace) and hitbox.Parent) then return end
		local now = hitbox.CFrame
		for i, part in ipairs(crown) do
			if part.Parent then part.CFrame = now * rel[i] end
		end
	end
end

return B
