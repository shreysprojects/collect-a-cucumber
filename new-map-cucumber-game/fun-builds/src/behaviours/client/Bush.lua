--[[
	Bush  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLife
	Client-only behaviour for the three bushes (Bush x1.25; no server half - every client sees the same characters).
	  Bush_A Shrub   Bush_B Hedge   Bush_C Flowering Bush
	  RUSTLE: when a character (any player, or a zombie - CollectionService tag "Zombie") walks into the bush's
	  footprint (its hitbox's X/Z box + MARGIN, since the bush itself is solid and people brush its edge), or keeps
	  pushing through it, the foliage shakes - a quick decaying shiver about the bush's foot, leaning the way the
	  character moves (the Hedge only rocks front / back) - and 2-3 leaves (petals on the Flowering Bush) pop out of
	  the top and flutter down around it. A soft rustle sound (FunAssets.Sfx.Rustle when the integrator adds one,
	  FunAssets.Sfx.Whoosh until then, quiet and pitched up; respects the player's SFXEnabled attribute).
	  Shaking parts: everything but the ground pieces (<V>_Soil, _Litter, _Shade, _Base) and the Shrub's woody stems.
	Cheap: one ctx:Step; characters are checked CHECK_HZ times a second, the bush is only posed while it shakes,
	leaves are local parts (ctx:Part) from a small pool. Cleanup puts every part back at rest relative to the
	build's CURRENT hitbox.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

local player = Players.LocalPlayer

--..Config..--
local WIND = Vector3.new(0.83, 0, 0.56).Unit -- the map-wide wind (same as Tree / Sunflower)
local ZOMBIE_TAG = "Zombie"      -- ZombieCatalog.TAG
local MARGIN = 1.3               -- studs around the footprint that still count (a character brushing the bush)
local ABOVE = 4.5                -- studs above the bush top a root may be (standing on it)
local CHECK_HZ = 12
local COOLDOWN = 0.4             -- s between rustles while somebody keeps pushing through
local REENTER = 0.15             -- s: stepping back in right away doesn't count as a new entry
local MOVING = 2.5               -- studs/s: faster than this inside the footprint keeps it rustling
local SHAKE_TAU = 0.3            -- s: the shiver's decay
local SHAKE_HZ = 6.5
local LEAF_POOL = 6
local LEAF_LIE, LEAF_FADE = 1.2, 0.9
local SOUND_RANGE = 70
local STATIC = {"Soil", "Litter", "Shade", "Base", "Stems"} -- part names (after the variant prefix) that never move
local LEAFY = {"Canopy", "Highlight", "Body", "Top", "Blooms"} -- parts whose colours the leaves take
--.. per variant: Foot = AUTHORED foot of the bush (pivot of the shake), Amp = degrees, Rock = rocks front/back only
local BUSHES = {
	A = {Foot = Vector3.new(7, 0, 0), Amp = 6},
	B = {Foot = Vector3.new(0, 0, 0), Amp = 3.5, Rock = true},
	C = {Foot = Vector3.new(-7, 0, 0), Amp = 6},
}
local DEFAULT_BUSH = {Amp = 5}
local LEAF_SIZE = Vector3.new(0.22, 0.025, 0.15) -- AUTHORED (x ctx.Scale)

local B = {}
B.StepRange = 110

--..Helpers..--
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

local function Flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or Vector3.zero
end

--.. BulkMoveTo the first n entries (the tables are reused frame to frame)
local function Move(list, cfs, n)
	for i = #list, n + 1, -1 do
		list[i] = nil
		cfs[i] = nil
	end
	if n > 0 then workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
end

--..Falling leaves (same shape as Tree's)..--
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
	return CFrame.new(flat.X, y, flat.Z) * spin * CFrame.Angles(0.45 * math.cos(leaf.Freq * age + leaf.Phase), 0, 0.6 * swing)
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	local cfg = BUSHES[ctx.Variant or ""] or DEFAULT_BUSH
	local prefix = ctx.Variant and (ctx.Variant .. "_") or ""
	local scale = ctx.Scale
	local home = hitbox.CFrame

	--..Parts: foliage shakes, the ground pieces stay..--
	local parts, rel, colors = {}, {}, {}
	local main, mainVolume = nil, -1
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= hitbox and part.Name:sub(1, #prefix) == prefix then
			local name = part.Name:sub(#prefix + 1)
			if not HasWord(name, STATIC) then
				table.insert(parts, part)
				table.insert(rel, home:ToObjectSpace(part.CFrame))
				if HasWord(name, LEAFY) then table.insert(colors, part.Color) end
				local volume = part.Size.X * part.Size.Y * part.Size.Z
				if volume > mainVolume then main, mainVolume = part, volume end
			end
		end
	end
	if #parts == 0 then return end
	if #colors == 0 then colors = {main.Color} end
	local rest = {}
	for i, r in ipairs(rel) do rest[i] = home * r end

	--..Geometry..--
	local footAuthored = cfg.Foot
	if not footAuthored then
		local c = Kit.AuthoredCentre(model)
		footAuthored = Vector3.new(c.X, 0, c.Z)
	end
	local foot = Kit.ToWorld(model, footAuthored)
	local right = Kit.Origin(model).RightVector
	local half = hitbox.Size * 0.5
	local reachX, reachZ = half.X + MARGIN, half.Z + MARGIN
	local amp = math.rad(cfg.Amp)
	local groundY = Kit.Floor(model).Position.Y + LEAF_SIZE.Y * scale * 0.5 + 0.02

	--..Leaves + sound..--
	local rng = Random.new()
	local pool = MakeLeaves(ctx, LEAF_POOL, LEAF_SIZE * scale, main.Position)
	local anchor = ctx:Part({Name = "FunBushSound", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(main.Position)})
	local sound = ctx:Sound(anchor, FunAssets.Sfx.Rustle or FunAssets.Sfx.Whoosh, {Volume = 0.22})

	--..Shake state..--
	local energy, shakeT0, lastRustle = 0, 0, -math.huge
	local axis, axis2 = right, Vector3.zAxis
	local shaking = false

	--.. a burst of leaves out of the top of the bush, flying outward
	local function Burst(count)
		for _ = 1, count do
			local leaf = FreeLeaf(pool)
			if not leaf then return end
			local cf, size = main.CFrame, main.Size
			local from = cf:PointToWorldSpace(Vector3.new(rng:NextNumber(-0.4, 0.4) * size.X, rng:NextNumber(0.05, 0.42) * size.Y,
				rng:NextNumber(-0.4, 0.4) * size.Z))
			local out = Flat(from - foot)
			if out == Vector3.zero then out = Flat(Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))) end
			Launch(leaf, from, rng, {Fall = {1.3, 1.9}, Up = 1.0 * scale, Drift = out * 0.9 + WIND * 0.3, Sway = 0.35 * scale,
				Colors = colors})
		end
	end

	--.. somebody at `pos` moving with flat velocity `vel` rustles it (strength ~0.45..1.2)
	local function Rustle(c, strength, pos, vel)
		local lean = vel.Magnitude > 1 and vel.Unit or Flat(foot - pos) -- leans the way they push
		if lean == Vector3.zero then lean = Flat(home.LookVector) end
		local ax = Vector3.yAxis:Cross(lean)
		if cfg.Rock then
			--.. the hedge rocks front / back only: about its long (X) axis, away from the side they're on
			local side = ax:Dot(right)
			if math.abs(side) < 0.3 then side = Vector3.yAxis:Cross(Flat(foot - pos)):Dot(right) end
			ax = right * (side >= 0 and 1 or -1)
		end
		axis = ax.Magnitude > 1e-3 and ax.Unit or right
		axis2 = axis:Cross(Vector3.yAxis)
		energy = math.max(strength, energy * math.exp(-(c - shakeT0) / SHAKE_TAU))
		shakeT0 = c
		shaking = true
		lastRustle = c
		Burst(strength > 0.8 and 3 or 2)
		if ctx:CameraDistance() <= SOUND_RANGE and player:GetAttribute("SFXEnabled") ~= false then
			sound.PlaybackSpeed = rng:NextNumber(1.35, 1.75)
			sound.Volume = 0.14 + 0.1 * math.min(strength, 1)
			sound:Play()
		end
	end

	--..Who is in the footprint?..--
	local inside = {} -- [root] = the scan it was last seen inside in
	local lastEntry = {} -- [root] = clock when it last came in
	local scan = 0
	local function Check(root, c)
		local p = home:PointToObjectSpace(root.Position)
		if math.abs(p.X) > reachX or math.abs(p.Z) > reachZ or p.Y < -half.Y - 1 or p.Y > half.Y + ABOVE then return end
		local v = root.AssemblyLinearVelocity
		local vel = Vector3.new(v.X, 0, v.Z)
		local speed = vel.Magnitude
		local strength = math.clamp(0.45 + speed / 22, 0.45, 1.2)
		if not inside[root] then
			if c - (lastEntry[root] or -math.huge) > REENTER and c - lastRustle > REENTER then Rustle(c, strength, root.Position, vel) end
			lastEntry[root] = c
		elseif speed > MOVING and c - lastRustle >= COOLDOWN then
			Rustle(c, strength, root.Position, vel)
		end
		inside[root] = scan
	end
	local function Scan(c)
		scan += 1
		for _, other in ipairs(Players:GetPlayers()) do
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then Check(root, c) end
		end
		for _, zombie in ipairs(CollectionService:GetTagged(ZOMBIE_TAG)) do
			local root = zombie:IsA("Model") and (zombie.PrimaryPart or zombie:FindFirstChild("HumanoidRootPart"))
			if root and root:IsA("BasePart") then Check(root, c) end
		end
		for root, seen in pairs(inside) do
			if seen ~= scan then inside[root] = nil end
		end
		for root, t in pairs(lastEntry) do
			if c - t > 5 and not inside[root] then lastEntry[root] = nil end
		end
	end

	--..Step..--
	local list, cfs = {}, {}
	local lastScan, posed = -math.huge, false
	ctx:Step(function()
		if not (hitbox.Parent and SameCFrame(hitbox.CFrame, home)) then return end -- moved: the restart is on its way
		local c = os.clock()
		if c - lastScan >= 1 / CHECK_HZ then
			lastScan = c
			Scan(c)
		end
		local n = 0
		if shaking then
			posed = true
			local tau = c - shakeT0
			local env = energy * math.exp(-tau / SHAKE_TAU)
			local pose
			if env < 0.02 then
				shaking, energy = false, 0
				pose = CFrame.identity -- one last frame at rest
			else
				local a = amp * env * math.sin(2 * math.pi * SHAKE_HZ * tau)
				local b = amp * 0.35 * env * math.sin(2 * math.pi * SHAKE_HZ * 1.37 * tau + 1.1)
				pose = CFrame.new(foot) * CFrame.fromAxisAngle(axis, a) * CFrame.fromAxisAngle(axis2, b) * CFrame.new(-foot)
			end
			for i, part in ipairs(parts) do
				n += 1
				list[n] = part
				cfs[n] = pose * rest[i]
			end
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
		Move(list, cfs, n)
	end)

	--..Cleanup: back at rest (relative to wherever the hitbox is now)..--
	return function()
		if not (posed and model:IsDescendantOf(workspace) and hitbox.Parent) then return end
		local now = hitbox.CFrame
		for i, part in ipairs(parts) do
			if part.Parent then part.CFrame = now * rel[i] end
		end
	end
end

return B
