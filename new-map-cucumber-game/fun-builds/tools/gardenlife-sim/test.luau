
--========================= harness =========================--
local Kit = __modules.FunBuildKit
local v3 = Vector3.new
local FAIL = 0
local function check(cond, msg) if not cond then FAIL += 1 print("  FAIL: " .. msg) end end
local function hex(h) return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)) end
local function LookAt(from, to)
	local f = (to - from).Unit
	local r = f:Cross(Vector3.yAxis).Unit
	return CFrame.fromMatrix(from, r, r:Cross(f), -f)
end
local function angleBetween(a, b) return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1))) end
local function rotAngle(a, b) -- degrees between two CFrames' rotations
	local r = (a.Rotation:Inverse() * b.Rotation)
	local R = r._r
	return math.deg(math.acos(math.clamp((R[1] + R[5] + R[9] - 1) / 2, -1, 1)))
end

local function Place(dumpName, key, letter, scale, placeCF)
	local d = DUMPS[dumpName]
	local model = Instance.new("Model")
	model.Name = key
	local lo, hi = v3(math.huge, math.huge, math.huge), v3(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(d.Parts) do
		if not letter or p.Name:sub(1, 2) == letter .. "_" then
			local part = Instance.new(p.Class)
			part.Name = p.Name
			part.Size = v3(p.S[1], p.S[2], p.S[3])
			local pos = v3(p.P[1], p.P[2], p.P[3])
			part.CFrame = CFrame.new(pos)
			part.Color = hex(p.C)
			part.Parent = model
			local a, b = pos - part.Size / 2, pos + part.Size / 2
			lo = v3(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z))
			hi = v3(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z))
		end
	end
	local centre = (lo + hi) / 2
	for _, part in ipairs(model:GetChildren()) do
		part.CFrame = CFrame.new(centre + (part.Position - centre) * scale)
		part.Size = part.Size * scale
	end
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (hi - lo) * scale
	hitbox.CFrame = CFrame.new(centre)
	hitbox.Transparency = 1
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	model:SetAttribute("AuthoredCentre", centre)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("BuildKey", key)
	for _, pv in ipairs(d.Pivots) do model:SetAttribute(pv[1], v3(pv[2], pv[3], pv[4])) end
	model.Parent = workspace
	model:PivotTo(placeCF)
	return model
end

local Running = {}
local function NewClient(model, modName)
	local mod = __modules["client/" .. modName]
	local key = model:GetAttribute("BuildKey")
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		Player = services.Players.LocalPlayer, _insts = {}, _cleanups = {}, _steps = {}, StepRange = mod.StepRange or 180}
	function ctx:Alive() return true end
	function ctx:Connect(sig, fn) return sig:Connect(fn) end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:Step(fn) table.insert(self._steps, fn) end
	function ctx:CameraDistance() return (workspace.CurrentCamera.CFrame.Position - Kit.Hitbox(model).Position).Magnitude end
	function ctx:Sound(parent, id, props) local s = Kit.MakeSound(id, props) s.Parent = parent self:Add(s) return s end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide = true, false
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent then p.Parent = workspace.CurrentCamera end
		self:Add(p)
		return p
	end
	function ctx:Every() end
	local cleanup = mod.Client(model, ctx)
	if type(cleanup) == "function" then table.insert(ctx._cleanups, cleanup) end
	function ctx:Stop()
		for _, fn in ipairs(self._cleanups) do fn() end
		for i = #self._insts, 1, -1 do self._insts[i]:Destroy() end
		for i, c in ipairs(Running) do if c == self then table.remove(Running, i) break end end
	end
	ctx._client = true
	table.insert(Running, ctx)
	return ctx
end

local function NewServer(model, modName)
	local mod = __modules["server/" .. modName]
	local key = model:GetAttribute("BuildKey")
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), _every = {}, _seats = {}, _insts = {}}
	function ctx:Alive() return true end
	function ctx:SetState(k, v) model:SetAttribute("Fun_" .. k, v) end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:Every(sec, fn) table.insert(self._every, {Sec = sec, Fn = fn, Next = SIM.Now + sec}) end
	function ctx:HumanoidOf(player)
		local ch = player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root then return {Health = 100}, root end
		return nil
	end
	function ctx:Seat(cf, opts) table.insert(self._seats, {CFrame = cf, Opts = opts}) return {} end
	mod.Server(model, ctx)
	table.insert(Running, ctx)
	return ctx, mod
end

local function Tick(dt)
	SIM.Now += dt
	SIM.Clock += dt
	for _, ctx in ipairs(table.clone(Running)) do
		if ctx._client then
			if ctx:CameraDistance() <= ctx.StepRange then
				for _, fn in ipairs(ctx._steps) do fn(dt, SIM.Now) end
			end
		else
			for _, e in ipairs(ctx._every) do
				if SIM.Now >= e.Next then e.Next = SIM.Now + e.Sec e.Fn() end
			end
		end
	end
end

local function Snapshot(model)
	local s = {}
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then s[d] = d.CFrame end end
	return s
end
local function MaxDelta(model, snap)
	local worst, who = 0, nil
	for part, cf in pairs(snap) do
		local d = (part.CFrame.Position - cf.Position).Magnitude + rotAngle(part.CFrame, cf) * 0.01
		if d > worst then worst, who = d, part.Name end
	end
	return worst, who
end
local function Clear()
	for _, ctx in ipairs(table.clone(Running)) do if ctx.Stop then ctx:Stop() end end
	Running = {}
	for _, ch in ipairs(workspace:GetChildren()) do if ch:IsA("Model") then ch:Destroy() end end
	for _, ch in ipairs(workspace.CurrentCamera:GetChildren()) do ch:Destroy() end
	SIM.Plays = {}
end
local PLACE = CFrame.new(120, 3, -60) * CFrame.Angles(0, 0.8, 0)
local function Visible(name)
	local list = {}
	for _, d in ipairs(workspace.CurrentCamera:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == name and d.Transparency < 1 then table.insert(list, d) end
	end
	return list
end

--========================= TREE =========================--
print("== Tree")
SIM.Sun = v3(0.3, 0.8, -0.5).Unit
for _, L in ipairs({"A", "B", "C"}) do
	local scale = ({A = 1.6, B = 1.6, C = 1.5})[L]
	local model = Place("Tree", "Tree_" .. L, L, scale, PLACE)
	local hb = model.PrimaryPart
	workspace.CurrentCamera.CFrame = LookAt(hb.Position + v3(20, 4, 20), hb.Position)
	local rest = Snapshot(model)
	local ctx = NewClient(model, "Tree")
	local maxBy, leafMax, leafLow = {}, 0, math.huge
	local floorY = Kit.Floor(model).Position.Y
	for _ = 1, 60 * 20 do
		Tick(1 / 60)
		for part, cf in pairs(rest) do
			local d = (part.CFrame.Position - cf.Position).Magnitude
			maxBy[part.Name] = math.max(maxBy[part.Name] or 0, d)
		end
		local leaves = Visible("FunLeaf")
		leafMax = math.max(leafMax, #leaves)
		for _, l in ipairs(leaves) do leafLow = math.min(leafLow, l.Position.Y - floorY) end
	end
	local line = {}
	for n, d in pairs(maxBy) do table.insert(line, string.format("%s %.3f", n, d)) end
	table.sort(line)
	print(string.format("  Tree_%s: max move: %s | leaves at once %d, lowest leaf %.3f above floor", L, table.concat(line, ", "), leafMax, leafLow))
	for n, d in pairs(maxBy) do
		if n:find("Trunk") or n:find("Roots") or n == "Hitbox" then check(d < 1e-9, n .. " moved " .. d) end
		if n:find("Crown") or n:find("Canopy") then check(d > 0.05 and d < 0.8, n .. " sway " .. d) end
	end
	if L == "B" then check(leafMax == 0, "pine drops leaves") else check(leafMax > 0 and leafLow > -1e-6, "leaves") end
	-- the move race: server pivots the model mid-sway; the client must stop posing and restore relative to the new hitbox
	local oldHome = hb.CFrame
	local newCF = CFrame.new(140, 3, -50) * CFrame.Angles(0, -0.4, 0)
	local expected = {}
	for part, cf in pairs(rest) do expected[part] = newCF * (oldHome:Inverse() * cf) end
	model:PivotTo(newCF) -- moves the CURRENT (swayed) poses, like the server's PivotTo of the server poses
	for part in pairs(rest) do part.CFrame = expected[part] end -- replication: the server's parts were at rest
	for _ = 1, 20 do Tick(1 / 60) end
	local drift = 0
	for part, cf in pairs(expected) do drift = math.max(drift, (part.CFrame.Position - cf.Position).Magnitude) end
	check(drift < 1e-6, "posed after the move " .. drift)
	ctx:Stop()
	local err = 0
	for part, cf in pairs(expected) do err = math.max(err, (part.CFrame.Position - cf.Position).Magnitude + rotAngle(part.CFrame, cf)) end
	print(string.format("  after move + cleanup: max error %.2e", err))
	check(err < 1e-6, "restore after move")
	Clear()
	-- plain cleanup
	model = Place("Tree", "Tree_" .. L, L, scale, PLACE)
	workspace.CurrentCamera.CFrame = LookAt(model.PrimaryPart.Position + v3(20, 4, 20), model.PrimaryPart.Position)
	rest = Snapshot(model)
	ctx = NewClient(model, "Tree")
	for _ = 1, 137 do Tick(1 / 60) end
	ctx:Stop()
	local e2 = MaxDelta(model, rest)
	check(e2 < 1e-6, "restore " .. e2)
	Clear()
end

--========================= SUNFLOWER =========================--
print("== Sunflower")
local SUNS = {
	{"front-high", v3(0, 0.7, -1)}, {"left", v3(-1, 0.3, -0.2)}, {"right-low", v3(1, 0.1, 0)},
	{"behind", v3(0.05, 0.4, 1)}, {"overhead", v3(0.01, 1, 0)}, {"below", v3(0.3, -0.5, -1)},
}
for _, L in ipairs({"A", "B", "C"}) do
	for _, sun in ipairs(SUNS) do
		local model = Place("Sunflower", "Sunflower_" .. L, L, 1.5, PLACE)
		local hb = model.PrimaryPart
		workspace.CurrentCamera.CFrame = LookAt(hb.Position + v3(8, 3, 8), hb.Position)
		-- sun given in the BUILD's frame, turned to world
		SIM.Sun = Kit.Origin(model):VectorToWorldSpace(sun[2].Unit)
		local rest = Snapshot(model)
		local disc = model:FindFirstChild(L == "C" and "C_Discs" or L .. "_Disc")
		local stem = model:FindFirstChild(L == "C" and "C_Stems" or L .. "_Stem")
		local mound = model:FindFirstChild("C_Mound")
		local ctx = NewClient(model, "Sunflower")
		local maxHead, maxBud = 0, 0
		local nose = Kit.ToWorld(model, v3(0.886, 2.28, -0.077))
		local petals = model:FindFirstChild(L .. "_PetalsYellow")
		for _ = 1, 60 * 8 do
			Tick(1 / 60)
			maxHead = math.max(maxHead, rotAngle(rest[disc], disc.CFrame))
			if L == "B" then
				local a = petals.CFrame * (rest[petals]:Inverse() * nose)
				local b = stem.CFrame * (rest[stem]:Inverse() * nose)
				maxBud = math.max(maxBud, (a - b).Magnitude)
			end
		end
		local stemYaw = rotAngle(rest[stem], stem.CFrame)
		-- which way does the head face now vs the sun (flat)?
		local look0 = Kit.Origin(model).LookVector
		local turnedLook = (stem.CFrame * rest[stem]:Inverse()):VectorToWorldSpace(look0)
		local flatSun = v3(SIM.Sun.X, 0, SIM.Sun.Z)
		local toSun = flatSun.Magnitude > 1e-3 and angleBetween(v3(turnedLook.X, 0, turnedLook.Z).Unit, flatSun.Unit) or 0
		print(string.format("  Sunflower_%s sun %-10s head turned max %5.1f deg, plant now %5.1f deg, facing %5.1f deg off the sun%s", L, sun[1], maxHead, stemYaw, toSun,
			L == "B" and string.format(", bud nose gap %.3f", maxBud) or ""))
		check(maxHead < 31, "head over-rotated " .. maxHead)
		if L == "B" then check(maxBud < 0.12, "bud gap " .. maxBud) end
		if mound then check((mound.CFrame.Position - rest[mound].Position).Magnitude < 1e-9, "mound moved") end
		ctx:Stop()
		check(MaxDelta(model, rest) < 1e-6, "sunflower restore")
		Clear()
	end
end
-- slow turn: snap to one sun, then swing it 90 degrees and watch the yaw creep
do
	local model = Place("Sunflower", "Sunflower_A", "A", 1.5, PLACE)
	local hb = model.PrimaryPart
	workspace.CurrentCamera.CFrame = LookAt(hb.Position + v3(8, 3, 8), hb.Position)
	local o = Kit.Origin(model)
	SIM.Sun = o:VectorToWorldSpace(v3(-1, 0.3, -0.3).Unit)
	local stem = model.A_Stem
	local rest = stem.CFrame
	local ctx = NewClient(model, "Sunflower")
	Tick(1 / 60)
	local y0 = rotAngle(rest, stem.CFrame)
	SIM.Sun = o:VectorToWorldSpace(v3(1, 0.3, -0.3).Unit)
	local trace = {}
	for i = 1, 60 * 12 do
		Tick(1 / 60)
		if i % 120 == 0 then
			local _, ry = (rest:Inverse() * stem.CFrame):ToOrientation()
			table.insert(trace, string.format("%.1f", math.deg(ry)))
		end
	end
	print("  slow turn: start " .. string.format("%.1f", y0) .. " deg, yaw every 2 s: " .. table.concat(trace, " "))
	-- night droop
	workspace:SetAttribute("CyclePhase", "Night")
	for _ = 1, 60 * 20 do Tick(1 / 60) end
	local disc = model.A_Disc
	print(string.format("  night: plant yaw %.1f deg (-> 0), head droops: disc look.Y %.3f", math.deg(select(2, (rest:Inverse() * stem.CFrame):ToOrientation())), disc.CFrame.LookVector.Y))
	workspace:SetAttribute("CyclePhase", nil)
	ctx:Stop()
	Clear()
end

--========================= SCARECROW =========================--
print("== Scarecrow")
SIM.Sun = v3(0.3, 0.8, -0.5).Unit
do
	local model = Place("Scarecrow", "Scarecrow", nil, 1.35, PLACE)
	local hb = model.PrimaryPart
	workspace.CurrentCamera.CFrame = LookAt(hb.Position + v3(14, 5, 14), hb.Position)
	local char = Instance.new("Model")
	char.Name = "Char"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	char.Parent = workspace
	root.CFrame = CFrame.new(hb.Position + v3(60, 0, 0))
	services.Players.LocalPlayer.Character = char
	local sctx = NewServer(model, "Scarecrow")
	local cctx = NewClient(model, "Scarecrow")
	check(model.Crow.Transparency == 1 and model.CrowBeak.Transparency == 1, "authored crow hidden")
	local perch = Kit.Pivot(model, "CrowPerch")
	local body = workspace.CurrentCamera:FindFirstChild("CrowBody", true)
	check(body ~= nil, "crow body")
	print(string.format("  first pose: body %.3f from perch, transparency %.2f", (body.Position - perch).Magnitude, body.Transparency))
	-- 1) two minutes of idling
	local lastPos, maxJump, maxFar, lowest = body.Position, 0, 0, math.huge
	local actions = {}
	for _ = 1, 60 * 120 do
		Tick(1 / 60)
		local p = body.Position
		maxJump = math.max(maxJump, (p - lastPos).Magnitude)
		maxFar = math.max(maxFar, (p - perch).Magnitude)
		lastPos = p
		for _, d in ipairs(workspace.CurrentCamera:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency ~= body.Transparency then check(false, "crow parts disagree on transparency") break end
		end
	end
	print(string.format("  idle 120 s: max frame step %.3f studs, max distance from perch %.3f, sounds %d", maxJump, maxFar, #SIM.Plays))
	check(maxJump < 0.12 and maxFar < 0.75, "idle motion bounds")
	check(body.Transparency == 0, "crow visible when perched")
	-- 2) a player walks up
	local target = perch + v3(-5, -2.5, 3)
	local start = root.Position
	local trip = {}
	local phase = "walk"
	local visibleJump, t0 = 0, SIM.Now
	lastPos = body.Position
	local lastT = body.Transparency
	local left, back
	for f = 1, 60 * 130 do
		local t = SIM.Now - t0
		if t < 3 then
			root.CFrame = CFrame.new(start:Lerp(target, t / 3))
		elseif t < 60 then
			root.CFrame = CFrame.new(target) -- stands there (crow should stay away)
		elseif t < 63 then
			root.CFrame = CFrame.new(target:Lerp(start, (t - 60) / 3))
		end
		Tick(1 / 60)
		local p = body.Position
		if body.Transparency < 0.99 and lastT < 0.99 then visibleJump = math.max(visibleJump, (p - lastPos).Magnitude) end
		lastPos, lastT = p, body.Transparency
		local l, b = model:GetAttribute("Fun_CrowLeft"), model:GetAttribute("Fun_CrowBack")
		if l ~= left then left = l table.insert(trip, string.format("t=%.1f left (player %.1f studs flat)", t, (v3(root.Position.X, 0, root.Position.Z) - v3(perch.X, 0, perch.Z)).Magnitude)) end
		if b ~= back then back = b table.insert(trip, string.format("t=%.1f back set to +%.1f s", t, b - SIM.Now)) end
		if f % 60 == 0 then
			local where = body.Transparency >= 0.99 and "gone" or string.format("%.1f studs from perch, T=%.2f", (p - perch).Magnitude, body.Transparency)
			if (f / 60) % 5 == 0 then table.insert(trip, string.format("t=%.0f crow %s", t, where)) end
		end
	end
	print("  trip: " .. table.concat(trip, " | "))
	print(string.format("  flight: largest visible frame step %.3f studs; final: %.3f from perch, T=%.2f", visibleJump, (body.Position - perch).Magnitude, body.Transparency))
	check(visibleJump < 1.2, "flight continuity " .. visibleJump)
	check((body.Position - perch).Magnitude < 0.75 and body.Transparency == 0, "back on the perch")
	cctx:Stop()
	check(model.Crow.Transparency == 0 and model.CrowBeak.Transparency == 0, "authored crow restored")
	check(#workspace.CurrentCamera:GetChildren() == 0, "crow parts destroyed")
	services.Players.LocalPlayer.Character = nil
	Clear()
end

--========================= BUSH =========================--
print("== Bush")
for _, L in ipairs({"A", "B", "C"}) do
	local model = Place("Bush", "Bush_" .. L, L, 1.25, PLACE)
	local hb = model.PrimaryPart
	workspace.CurrentCamera.CFrame = LookAt(hb.Position + v3(10, 4, 10), hb.Position)
	local rest = Snapshot(model)
	local char = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	char.Parent = workspace
	services.Players.LocalPlayer.Character = char
	local o = Kit.Origin(model)
	-- walk along the build's X axis, brushing the front edge (just outside the solid footprint)
	local edgeZ = -(hb.Size.Z / 2 + 0.9)
	local a, b = o * v3(-12, 3, 0), o * v3(12, 3, 0)
	a = hb.CFrame * v3(-12, 0, edgeZ)
	b = hb.CFrame * v3(12, 0, edgeZ)
	local ctx = NewClient(model, "Bush")
	local maxMove, leafMax, leafLow, soundN = 0, 0, math.huge, 0
	local floorY = Kit.Floor(model).Position.Y
	local vel = (b - a).Unit * 14
	for f = 1, 60 * 6 do
		local t = f / 60
		root.CFrame = CFrame.new(a:Lerp(b, math.min(t / (24 / 14), 1)))
		root.AssemblyLinearVelocity = t < 24 / 14 and vel or Vector3.zero
		Tick(1 / 60)
		for part, cf in pairs(rest) do maxMove = math.max(maxMove, (part.CFrame.Position - cf.Position).Magnitude) end
		local leaves = Visible("FunLeaf")
		leafMax = math.max(leafMax, #leaves)
		for _, l in ipairs(leaves) do leafLow = math.min(leafLow, l.Position.Y - floorY) end
	end
	soundN = #SIM.Plays
	local settled = MaxDelta(model, rest)
	print(string.format("  Bush_%s: max part move %.3f, leaves at once %d (lowest %.3f), rustle sounds %d, settled error %.2e", L, maxMove, leafMax, leafLow, soundN, settled))
	check(maxMove > 0.05 and maxMove < 0.6, "shake size " .. maxMove)
	check(leafMax > 0 and leafLow > -1e-6, "bush leaves")
	check(settled < 1e-6, "bush settles at rest")
	for part, cf in pairs(rest) do
		if part.Name:find("Soil") or part.Name:find("Litter") or part.Name:find("Shade") or part.Name:find("Base") or part.Name:find("Stems") then
			check(true, "")
		end
	end
	-- a zombie wanders in
	local z = Instance.new("Model")
	local zr = Instance.new("Part")
	zr.Name = "HumanoidRootPart"
	zr.Parent = z
	z.Parent = workspace
	SIM.Tags.Zombie = {z}
	services.Players.LocalPlayer.Character = nil
	zr.CFrame = CFrame.new(hb.CFrame * v3(0, 0, -hb.Size.Z / 2 - 5))
	for _ = 1, 30 do Tick(1 / 60) end
	local before = (MaxDelta(model, rest))
	zr.CFrame = CFrame.new(hb.CFrame * v3(0, 0, edgeZ))
	zr.AssemblyLinearVelocity = v3(0, 0, 8)
	local zmove = 0
	for _ = 1, 20 do Tick(1 / 60) zmove = math.max(zmove, (MaxDelta(model, rest))) end
	print(string.format("  zombie brush: still before %.2e, moved %.3f", before, zmove))
	check(before < 1e-6 and zmove > 0.02, "zombie rustle")
	SIM.Tags.Zombie = nil
	for _ = 1, 3 do Tick(1 / 60) end
	ctx:Stop()
	check(MaxDelta(model, rest) < 1e-6, "bush restore")
	Clear()
end

--========================= HAYBALE =========================--
print("== HayBale")
do
	local mod = __modules["server/HayBale"]
	print("  keys: " .. table.concat(mod.Keys, ", "))
	for _, L in ipairs({"B", "C"}) do
		local model = Place("HayBale", "HayBale_" .. L, L, 1.3, PLACE)
		local ctx = NewServer(model, "HayBale")
		check(#ctx._seats == 1, "one seat")
		local seat = ctx._seats[1]
		local o = Kit.Origin(model)
		local local_ = o:PointToObjectSpace(seat.CFrame.Position) / 1.3
		local facing = o:VectorToObjectSpace(seat.CFrame.LookVector)
		print(string.format("  HayBale_%s seat centre (authored) %s, top face at authored y %.3f, faces %s, prompt %s", L, tostring(local_),
			local_.Y + 0.2 / 1.3, tostring(facing), tostring(seat.Opts.Prompt)))
		check(facing.Z < -0.999, "faces front")
		Clear()
	end
end

print(FAIL == 0 and "ALL CHECKS PASSED" or ("FAILURES: " .. FAIL))
print("warnings: " .. tostring(SIM.Warns or 0))
