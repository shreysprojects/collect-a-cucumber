------------------------------------------------------------------ HomeDining headless tests (DiningTable fix pass, 2026-09-24)
-- run: py tests/HomeDining/gen.py   (mock.luau + module sources + parts.json models + this file -> run.luau)

------------------------------------------------------------------ loader (os.clock / os.date are controllable)
local env = getfenv(1)
local realOs = os
MockClock = 1000
MockDate = {hour = 3, min = 30, sec = 0}
env.os = setmetatable({
	clock = function() return MockClock end,
	date = function(fmt, t) if fmt == "*t" then return table.clone(MockDate) end return realOs.date(fmt, t) end,
}, {__index = realOs})
local loaded = {}
local function load(name)
	local fn, err = loadstring(SOURCES[name], name)
	assert(fn, err)
	setfenv(fn, env)
	return fn()
end
env.require = function(m)
	local name = type(m) == "table" and m.Name or tostring(m)
	if not loaded[name] then loaded[name] = load(name) end
	return loaded[name]
end
for _, n in ipairs({"FunBuildKit", "FunAssets"}) do
	local ms = Instance.new("ModuleScript")
	ms.Name = n
	ms.Parent = MockModules
end
local Kit = require({Name = "FunBuildKit"})
local FunAssets = require({Name = "FunAssets"})

local fails, checks = 0, 0
local function check(ok, msg)
	checks += 1
	if not ok then fails += 1 print("FAIL " .. msg) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function vnear(a, b, eps) return (a - b).Magnitude <= (eps or 1e-6) end

------------------------------------------------------------------ template + placement (BuildService.MakeTemplate)
local function halfExtent(size, m, axis)
	-- m row-major 3x3: world axis `axis` row = m[axis*3+1 .. axis*3+3]
	local r = axis * 3
	return 0.5 * (math.abs(m[r + 1]) * size.X + math.abs(m[r + 2]) * size.Y + math.abs(m[r + 3]) * size.Z)
end
local function MakePlaced(key, scale, placeCF)
	local data = MODELS[key]
	local model = Instance.new("Model")
	model.Name = key
	local parts = {}
	local mn, mx = {math.huge, math.huge, math.huge}, {-math.huge, -math.huge, -math.huge}
	for _, pd in ipairs(data.Parts) do
		local p = Instance.new("Part")
		p.Name = pd.Name
		p.Size = pd.Size
		local c = pd.CF
		p.CFrame = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		p.Color = Color3.fromHex(pd.Color)
		p.Material = Enum.Material[pd.Material]
		p.Transparency = pd.T
		p.CanCollide = pd.Collide
		p.Anchored = true
		p.Parent = model
		if pd.Shape == "Ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		table.insert(parts, p)
		local m = {c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]}
		for axis = 0, 2 do
			local e = halfExtent(pd.Size, m, axis)
			mn[axis + 1] = math.min(mn[axis + 1], c[axis + 1] - e)
			mx[axis + 1] = math.max(mx[axis + 1], c[axis + 1] + e)
		end
	end
	local lo, hi = Vector3.new(mn[1], mn[2], mn[3]), Vector3.new(mx[1], mx[2], mx[3])
	local centre = (lo + hi) / 2
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (hi - lo) * scale
	hitbox.CFrame = CFrame.new(centre)
	hitbox.Transparency = 1
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	for _, p in ipairs(parts) do
		p.Size = p.Size * scale
		p.CFrame = CFrame.new(centre + (p.CFrame.Position - centre) * scale) * p.CFrame.Rotation
	end
	for k, v in pairs(data.Attrs) do model:SetAttribute(k, v) end
	model:SetAttribute("AuthoredCentre", centre)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("BuildKey", key)
	model:SetAttribute("Owner", 42)
	local delta = placeCF * hitbox.CFrame:Inverse()
	for _, p in ipairs(parts) do p.CFrame = delta * p.CFrame end
	hitbox.CFrame = delta * hitbox.CFrame
	model.Parent = workspace
	return model
end

local function Snapshot(model)
	local snap = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			snap[d] = {CFrame = d.CFrame, Color = d.Color, Material = d.Material, Transparency = d.Transparency}
		elseif d.ClassName == "SpecialMesh" then
			snap[d] = {Scale = d.Scale}
		end
	end
	return snap
end
local function SameAsSnapshot(model, snap, label)
	for inst, s in pairs(snap) do
		if s.Scale then
			check(vnear(inst.Scale, s.Scale, 1e-6), label .. ": mesh scale of " .. inst.Parent.Name .. " restored")
		else
			check(vnear(inst.CFrame.Position, s.CFrame.Position, 1e-5) and vnear(inst.CFrame.UpVector, s.CFrame.UpVector, 1e-5)
				and vnear(inst.CFrame.LookVector, s.CFrame.LookVector, 1e-5), label .. ": CFrame of " .. inst.Name .. " restored")
			check(inst.Color == s.Color, label .. ": Color of " .. inst.Name .. " restored")
			check(inst.Material == s.Material, label .. ": Material of " .. inst.Name .. " restored")
			check(inst.Transparency == s.Transparency, label .. ": Transparency of " .. inst.Name .. " restored (" .. tostring(inst.Transparency) .. ")")
		end
	end
end

------------------------------------------------------------------ client ctx (FunBuildClient.NewContext)
local function MakeCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		_insts = {}, _cleanups = {}, _steps = {}, _everys = {}, _conns = {}, StepRange = 180}
	function ctx:Alive() return true end
	function ctx:Connect(sig, fn) local c = sig:Connect(fn) table.insert(self._conns, c) return c end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn)
		self:Connect(model:GetAttributeChangedSignal("Fun_" .. k), function() fn(model:GetAttribute("Fun_" .. k)) end)
		fn(model:GetAttribute("Fun_" .. k))
	end
	function ctx:Send() end
	function ctx:CameraDistance() return (workspace.CurrentCamera.CFrame.Position - Kit.Hitbox(model).Position).Magnitude end
	function ctx:Step(fn) table.insert(self._steps, fn) end
	function ctx:Every(_, fn) table.insert(self._everys, fn) end
	function ctx:Sound(parent, id, props) local s = Kit.MakeSound(id, props) s.Parent = parent self:Add(s) return s end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = workspace.CurrentCamera end
		self:Add(p)
		return p
	end
	function ctx:LocalCharacter() return nil end
	function ctx:Near() return false end
	function ctx:IsOwner() return true end
	return ctx
end

local function Run(mod, model)
	local ctx = MakeCtx(model)
	local ok, res = pcall(mod.Client, model, ctx)
	check(ok, "Client() errored: " .. tostring(res))
	if ok and type(res) == "function" then ctx:OnCleanup(res) end
	return ctx
end
local function Frames(ctx, seconds, dt)
	dt = dt or 1 / 60
	check(#ctx._steps <= 1, "at most one ctx:Step per build")
	local n = math.floor(seconds / dt + 0.5)
	for _ = 1, n do
		MockNow += dt
		MockClock += dt
		for _, fn in ipairs(ctx._steps) do
			local ok, err = pcall(fn, dt, MockNow)
			if not ok then check(false, "Step errored: " .. tostring(err)) return end
		end
	end
end
local function Everys(ctx)
	for _, fn in ipairs(ctx._everys) do
		local ok, err = pcall(fn)
		check(ok, "Every errored: " .. tostring(err))
	end
end
local function Stop(ctx)
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		check(ok, "cleanup errored: " .. tostring(err))
	end
	for _, c in ipairs(ctx._conns) do c.Disconnect() end
	for i = #ctx._insts, 1, -1 do ctx._insts[i]:Destroy() end
end
local function FindIn(insts, className, name)
	for _, i in ipairs(insts) do
		if i.ClassName == className and (not name or i.Name == name) then return i end
		for _, d in ipairs(i:GetDescendants()) do
			if d.ClassName == className and (not name or d.Name == name) then return d end
		end
	end
	return nil
end
local function FindAll(insts, className)
	local out = {}
	for _, i in ipairs(insts) do
		if i.ClassName == className then table.insert(out, i) end
		for _, d in ipairs(i:GetDescendants()) do if d.ClassName == className then table.insert(out, d) end end
	end
	return out
end
local function CameraAt(p) rawget(workspace.CurrentCamera, "_p").CFrame = CFrame.new(p) end

------------------------------------------------------------------ server ctx (FunBuildService.NewContext)
local function MakeServerCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local folder = Instance.new("Folder")
	folder.Parent = workspace
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit, Folder = folder,
		_insts = {folder}, _conns = {}, _states = {}}
	function ctx:Alive() return true end
	function ctx:Connect(sig, fn) local c = sig:Connect(fn) table.insert(self._conns, c) return c end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup() end
	function ctx:SetState(k, v) self._states[k] = true model:SetAttribute("Fun_" .. k, v) end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:HumanoidOf(player) if player and player.Alive then return {Health = 100}, {Position = Vector3.zero} end return nil end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent then p.Parent = folder end
		self:Add(p)
		return p
	end
	function ctx:Prompt(part, opts)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = opts.Name or "FunPrompt"
		prompt.ObjectText = opts.Object or base
		prompt.ActionText = opts.Action or "Use"
		prompt.MaxActivationDistance = opts.Distance or 10
		prompt.Parent = part
		self:Add(prompt)
		return prompt
	end
	return ctx
end

------------------------------------------------------------------ authored-frame helpers
local function PartData(key, name)
	for _, pd in ipairs(MODELS[key].Parts) do if pd.Name == name then return pd end end
	return nil
end
-- distance along an authored horizontal ray to an axis-aligned authored part box (math.huge when missed)
local function RayToBox(key, name, from, dir)
	local pd = PartData(key, name)
	if not pd then return math.huge end
	local c = Vector3.new(pd.CF[1], pd.CF[2], pd.CF[3])
	local lo, hi = c - pd.Size / 2, c + pd.Size / 2
	local tmin, tmax = -math.huge, math.huge
	for _, axis in ipairs({"X", "Y", "Z"}) do
		local o, d = from[axis], dir[axis]
		if math.abs(d) < 1e-9 then
			if o < lo[axis] or o > hi[axis] then return math.huge end
		else
			local t1, t2 = (lo[axis] - o) / d, (hi[axis] - o) / d
			tmin = math.max(tmin, math.min(t1, t2))
			tmax = math.min(tmax, math.max(t1, t2))
		end
	end
	if tmax < math.max(tmin, 0) then return math.huge end
	return math.max(tmin, 0)
end

--========================================================================== DINING TABLE (server seats)
do
	local S = require({Name = "S_DiningTable"})
	local scale = 1.3
	local place = CFrame.new(12, 3, -30) * CFrame.Angles(0, math.rad(37), 0)
	local model = MakePlaced("DiningTable", scale, place)
	local ctx = MakeServerCtx(model)
	local seats = {}
	function ctx:Seat(cf, opts) table.insert(seats, {CF = cf, Opts = opts}) return Instance.new("Part") end
	local ok, err = pcall(S.Server, model, ctx)
	check(ok, "dining server errored: " .. tostring(err))
	check(#seats == 4, "dining: 4 seats (got " .. #seats .. ")")
	local origin = Kit.Origin(model)
	local inv = origin:Inverse()
	local names = {}
	for i, s in ipairs(seats) do
		names[s.Opts.Name] = true
		local authored = model:GetAttribute("Pivot_Seat" .. i)
		local face = model:GetAttribute("Pivot_Seat" .. i .. "Face")
		check(typeof(authored) == "Vector3" and typeof(face) == "Vector3", "dining: seat " .. i .. " pivots authored")
		local top = s.CF.Position + s.CF.UpVector * (s.Opts.Size.Y * 0.5)
		check(vnear(top, Kit.ToWorld(model, authored), 1e-4), "dining: seat " .. i .. " top on Pivot_Seat" .. i)
		check(near(s.CF.UpVector:Dot(origin.UpVector), 1, 1e-6), "dining: seat " .. i .. " level")
		local lookA = inv:VectorToWorldSpace(s.CF.LookVector)
		local want = (face - authored)
		want = Vector3.new(want.X, 0, want.Z).Unit
		check(vnear(lookA, want, 1e-4), "dining: seat " .. i .. " looks where Pivot_Seat" .. i .. "Face says " .. tostring(lookA))
		-- the sitter looks at the table: the look ray at table height hits the top
		local hit = RayToBox("DiningTable", "TableTop", Vector3.new(authored.X, 3.1, authored.Z), want)
		check(hit < math.huge, "dining: seat " .. i .. " faces the table")
		-- torso (~1 deep, centred on the seat) clears the table edge + runner flap by >= 0.1 (seat centre >= 0.6 out)
		local edge = math.min(hit, RayToBox("DiningTable", "RunnerFlapL", Vector3.new(authored.X, 3.0, authored.Z), want),
			RayToBox("DiningTable", "RunnerFlapR", Vector3.new(authored.X, 3.0, authored.Z), want))
		check(edge >= 0.6, string.format("dining: seat %d centre %.2f from the table edge / flap (>= 0.6)", i, edge))
		-- knees (~1.5 forward of the hips, thigh top ~3.1) never reach the apron
		local apron = RayToBox("DiningTable", "TableApron", Vector3.new(authored.X, 2.9, authored.Z), want)
		check(apron >= 1.7, string.format("dining: seat %d apron %.2f ahead (>= 1.7, clear of the knees)", i, apron))
		-- nor the table legs (legs of a sitter span +/-1 sideways)
		for l = 1, 4 do
			local pd = PartData("DiningTable", "TableLeg" .. l)
			local rel = Vector3.new(pd.CF[1] - authored.X, 0, pd.CF[3] - authored.Z)
			local along = rel:Dot(want)
			local side = math.abs(rel:Dot(Vector3.new(-want.Z, 0, want.X)))
			check(not (along > 0 and along < 1.9 and side < 1.0 + 0.22), "dining: seat " .. i .. " knees clear TableLeg" .. l)
		end
	end
	check(names.DiningSeat1 and names.DiningSeat2 and names.DiningSeat3 and names.DiningSeat4, "dining: seats named DiningSeat1..4")
	-- no two sitters shoulder to shoulder (arms ~4.2 wide at physique 6.1)
	for a = 1, 4 do
		for b = a + 1, 4 do
			local pa, pb = model:GetAttribute("Pivot_Seat" .. a), model:GetAttribute("Pivot_Seat" .. b)
			local d = Vector3.new(pa.X - pb.X, 0, pa.Z - pb.Z).Magnitude
			check(d >= 4.2, string.format("dining: seats %d/%d %.2f apart (>= 4.2)", a, b, d))
		end
	end
	print(string.format("dining server: %d seats checked", #seats))
end

--========================================================================== DINING TABLE (client candle)
do
	local C = require({Name = "C_DiningTable"})
	check(MockNow > 1e9, "dining: the mock clock is epoch-sized (the case that froze the flame)")
	local scale = 1.3
	local place = CFrame.new(12, 3, -30) * CFrame.Angles(0, math.rad(37), 0)
	local model = MakePlaced("DiningTable", scale, place)
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 5, -12)))
	local flame = model:FindFirstChild("CandleFlame")
	check(flame ~= nil, "dining: CandleFlame exists")
	local restSize = flame.Size
	local restFoot = flame.CFrame * CFrame.new(0, -restSize.Y / 2, 0)
	local snap = Snapshot(model)
	local ctx = Run(C, model)
	local light = FindIn(ctx._insts, "PointLight", "CandleGlow")
	check(light ~= nil and light.Parent == flame, "dining: CandleGlow PointLight inside the flame")
	check(#FindAll(ctx._insts, "PointLight") <= 2, "dining: <= 2 lights")
	local ys, bs, seen, seenB = {}, {}, {}, {}
	local distinct, distinctB = 0, 0
	local footDrift = 0
	for _ = 1, 30 do
		Frames(ctx, 1 / 60)
		local y = math.floor(flame.Size.Y * 1e5 + 0.5)
		if not seen[y] then seen[y] = true distinct += 1 end
		local b = math.floor(light.Brightness * 1e5 + 0.5)
		if not seenB[b] then seenB[b] = true distinctB += 1 end
		table.insert(ys, flame.Size.Y)
		table.insert(bs, light.Brightness)
		local foot = flame.CFrame * CFrame.new(0, -flame.Size.Y / 2, 0)
		footDrift = math.max(footDrift, (foot.Position - restFoot.Position).Magnitude)
	end
	local ymin, ymax = math.min(table.unpack(ys)), math.max(table.unpack(ys))
	local bmin, bmax = math.min(table.unpack(bs)), math.max(table.unpack(bs))
	check(distinct >= 25, "dining: flame height changes every frame (" .. distinct .. " distinct of 30)")
	check(distinctB >= 25, "dining: light brightness changes every frame (" .. distinctB .. " distinct of 30)")
	check((ymax - ymin) / restSize.Y > 0.05, string.format("dining: flame height swings %.1f%% in 0.5 s", (ymax - ymin) / restSize.Y * 100))
	check(bmax - bmin > 0.05, string.format("dining: brightness swings %.3f in 0.5 s", bmax - bmin))
	check(footDrift < 1e-4, string.format("dining: the flame stays on the wick (foot drift %.5f)", footDrift))
	print(string.format("dining client: flame Y %.3f..%.3f (rest %.3f), brightness %.3f..%.3f", ymin, ymax, restSize.Y, bmin, bmax))
	Stop(ctx)
	SameAsSnapshot(model, snap, "dining cleanup")
	check(vnear(flame.Size, restSize, 1e-6), "dining: flame size restored")
end

print(string.format("HomeDining: %d checks, %d failed", checks, fails))
