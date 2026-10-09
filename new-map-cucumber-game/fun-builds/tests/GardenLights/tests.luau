
------------------------------------------------------------------ loader
local env = getfenv(1)
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

local fails, checks = 0, 0
local function check(ok, msg)
	checks += 1
	if not ok then fails += 1 print("FAIL " .. msg) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function vnear(a, b, eps) return (a - b).Magnitude <= (eps or 1e-6) end

------------------------------------------------------------------ template + placement (BuildService.MakeTemplate)
local function MakePlaced(dumpName, key, letter, scale, placeCF)
	local data = DUMPS[dumpName]
	local model = Instance.new("Model")
	model.Name = key
	local parts = {}
	local mn, mx
	for _, pd in ipairs(data.Parts) do
		if not letter or pd.Name:sub(1, 2) == letter .. "_" then
			local p = Instance.new("MeshPart")
			p.Name = pd.Name
			p.Size = pd.Size
			p.CFrame = CFrame.new(pd.Pos)
			p.Transparency = pd.T
			p.CanCollide = pd.Collide
			p.Anchored = true
			p.Parent = model
			table.insert(parts, p)
			local lo, hi = pd.Pos - pd.Size / 2, pd.Pos + pd.Size / 2
			mn = mn and Vector3.new(math.min(mn.X, lo.X), math.min(mn.Y, lo.Y), math.min(mn.Z, lo.Z)) or lo
			mx = mx and Vector3.new(math.max(mx.X, hi.X), math.max(mx.Y, hi.Y), math.max(mx.Z, hi.Z)) or hi
		end
	end
	local centre = (mn + mx) / 2
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (mx - mn) * scale
	hitbox.CFrame = CFrame.new(centre)
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	for _, p in ipairs(parts) do
		p.Size = p.Size * scale
		p.CFrame = CFrame.new(centre + (p.CFrame.Position - centre) * scale)
	end
	for k, v in pairs(data.Attrs) do model:SetAttribute(k, v) end
	model:SetAttribute("AuthoredCentre", centre)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("BuildKey", key)
	local delta = placeCF * hitbox.CFrame:Inverse()
	for _, p in ipairs(parts) do p.CFrame = delta * p.CFrame end
	hitbox.CFrame = delta * hitbox.CFrame
	model.Parent = workspace
	return model
end

------------------------------------------------------------------ client ctx (FunBuildClient.NewContext)
local function MakeCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		_alive = true, _conns = {}, _insts = {}, _cleanups = {}, _steps = {}, _everys = {}, StepRange = 180}
	function ctx:Alive() return self._alive and model.Parent ~= nil end
	function ctx:Connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(self._conns, c)
		return c
	end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn) fn(self:State(k)) end
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
local function Frames(ctx, n, dt)
	dt = dt or 1 / 60
	check(#ctx._steps <= 1, "at most one ctx:Step per build")
	for _ = 1, n do
		MockNow += dt
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
local function Stop(ctx) -- FunBuildClient.Stop order: dead first, then cleanups, then disconnect + destroy
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		check(ok, "cleanup errored: " .. tostring(err))
	end
	for _, c in ipairs(ctx._conns) do c:Disconnect() end
	for i = #ctx._insts, 1, -1 do ctx._insts[i]:Destroy() end
end
local function Find(root, className, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.ClassName == className and (not name or d.Name == name) then return d end
	end
	return nil
end
local function FindAll(root, className, name)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d.ClassName == className and (not name or d.Name == name) then table.insert(out, d) end
	end
	return out
end
local function SetCamera(model, dist) rawget(workspace.CurrentCamera, "_p").CFrame = CFrame.new(Kit.Hitbox(model).Position + Vector3.new(0, 0, dist)) end
local function Authored(model, world) return Kit.Origin(model):PointToObjectSpace(world) / Kit.Scale(model) end
local camera = workspace.CurrentCamera
local YAW = CFrame.Angles(0, math.rad(37), 0)

------------------------------------------------------------------ Lantern
do
	local mod = load("C_Lantern")
	for _, spec in ipairs({{"A", 2.1}, {"B", 1.7}, {"C", 1.5}}) do
		local letter, scale = spec[1], spec[2]
		workspace:SetAttribute("CyclePhase", "Day")
		local model = MakePlaced("Lantern", "Lantern_" .. letter, letter, scale, CFrame.new(120, 6, -40) * YAW)
		SetCamera(model, 25)
		local before = {}
		for _, p in ipairs(Kit.Parts(model, "")) do before[p] = p.CFrame end
		local ctx = Run(mod, model)
		local att = Find(model, "Attachment", "FunLanternLight")
		check(att ~= nil, letter .. " light attachment on a build part")
		if att then
			check(vnear(att.WorldPosition, Kit.Pivot(model, letter .. "_Light"), 1e-5), letter .. " light at Pivot_" .. letter .. "_Light")
			local light = Find(att, "PointLight")
			check(light ~= nil and light.Shadows == false, letter .. " PointLight")
			Frames(ctx, 120)
			local dayB = light.Brightness
			workspace:SetAttribute("CyclePhase", "Night")
			Frames(ctx, 240)
			check(light.Brightness > dayB * 1.4, letter .. (" night brighter (%.2f -> %.2f)"):format(dayB, light.Brightness))
			check(light.Range > 0 and light.Range <= 60, letter .. " range sane " .. light.Range)
			print(("Lantern_%s host %s  day %.2f night %.2f range %.1f"):format(letter, att.Parent.Name, dayB, light.Brightness, light.Range))
			local ff = Find(camera, "ParticleEmitter", "Fireflies")
			if letter == "A" then check(ff ~= nil and ff.Enabled == true, "A fireflies on at night") else check(ff == nil, letter .. " no fireflies") end
			workspace:SetAttribute("CyclePhase", "Day")
			rawget(MockLighting, "_p").ClockTime = 20
			Frames(ctx, 240)
			check(light.Brightness > dayB * 1.4, letter .. " ClockTime 20 counts as night")
			rawget(MockLighting, "_p").ClockTime = 14
			Frames(ctx, 300)
			if ff then check(ff.Enabled == false, "A fireflies off by day") end
		end
		if letter == "B" then
			local paper = Kit.Part(model, "B_Paper")
			local hang = Kit.Pivot(model, "B_Hang")
			local r0 = (before[paper].Position - hang).Magnitude
			local maxAngle = 0
			for _ = 1, 60 do
				Frames(ctx, 5)
				local r = (paper.Position - hang).Magnitude
				check(near(r, r0, 1e-4), "B paper keeps its distance to the hang point")
				local a = math.deg(math.acos(math.clamp((paper.Position - hang).Unit:Dot((before[paper].Position - hang).Unit), -1, 1)))
				maxAngle = math.max(maxAngle, a)
			end
			check(maxAngle > 2 and maxAngle < 4.4, ("B sway amplitude %.2f deg"):format(maxAngle))
			check(vnear(att.WorldPosition, paper.CFrame * att.Position, 1e-6), "B light rides on B_Paper")
			check(Kit.Part(model, "B_Iron").CFrame.Position == before[Kit.Part(model, "B_Iron")].Position, "B hook static")
			print(("Lantern_B max sway %.2f deg"):format(maxAngle))
		end
		Stop(ctx)
		for p, c in pairs(before) do
			check(vnear(p.CFrame.Position, c.Position, 1e-5) and vnear(p.CFrame.LookVector, c.LookVector, 1e-5), letter .. " part restored " .. p.Name)
		end
		check(Find(model, "Attachment", "FunLanternLight") == nil, letter .. " attachment removed on cleanup")
		model:Destroy()
	end
end

------------------------------------------------------------------ TikiTorch
do
	local mod = load("C_TikiTorch")
	for _, spec in ipairs({{"A", 1.5}, {"B", 1.5}, {"C", 1.4}}) do
		local letter, scale = spec[1], spec[2]
		local model = MakePlaced("TikiTorch", "TikiTorch_" .. letter, letter, scale, CFrame.new(-60, 4, 22) * YAW)
		SetCamera(model, 20)
		local ctx = Run(mod, model)
		local anchor = Find(camera, "Part", "FunTorchFlame")
		check(anchor ~= nil, letter .. " anchor")
		if anchor then
			check(vnear(anchor.Position, Kit.Pivot(model, letter .. "_FlameAnchor"), 1e-5), letter .. " anchor at the FlameAnchor pivot")
			local fire = Find(anchor, "Fire")
			check(fire and fire.Size >= 2 and fire.Size <= 30, letter .. " fire size")
			local sound = Find(anchor, "Sound")
			check(sound ~= nil, letter .. " crackle sound")
			Everys(ctx)
			check(sound and sound.IsPlaying, letter .. " crackle plays near")
			SetCamera(model, 60)
			Everys(ctx)
			check(sound and not sound.IsPlaying, letter .. " crackle stops far")
			Frames(ctx, 200)
			local light = Find(anchor, "PointLight")
			print(("TikiTorch_%s fire %.2f heat %d light %.2f range %.1f"):format(letter, fire.Size, fire.Heat, light.Brightness, light.Range))
		end
		Stop(ctx)
		check(Find(camera, "Part", "FunTorchFlame") == nil, letter .. " anchor removed")
		model:Destroy()
	end
end

------------------------------------------------------------------ Fountain (client + server)
do
	local G = 26
	local scale = 1.5
	local model = MakePlaced("Fountain", "Fountain", nil, scale, CFrame.new(10, 7, 80) * YAW)
	SetCamera(model, 30)
	local ctx = Run(load("C_Fountain"), model)
	local anchor = Find(camera, "Part", "FunFountainFX")
	check(anchor ~= nil, "fountain anchor")
	-- simulate one mean particle of every stream: where does it land?
	for _, att in ipairs(FindAll(anchor, "Attachment")) do
		if att.Name:match("^Stream") then
			local pe = Find(att, "ParticleEmitter")
			local wcf = att.WorldCFrame
			local v = wcf.LookVector * ((pe.Speed.Min + pe.Speed.Max) / 2)
			local life = pe.Lifetime.Max
			local p = wcf.Position + v * life + Vector3.new(0, -G * scale, 0) * (0.5 * life * life)
			local a = Authored(model, p)
			print(("%s lands at r %.2f y %.2f (life %.3f)"):format(att.Name, math.sqrt(a.X * a.X + a.Z * a.Z), a.Y, life))
			check(near(a.Y, 0.74, 0.03), att.Name .. " lands on the basin water")
			check(pe.Rate <= 30, "rate")
		end
	end
	local plume = Find(anchor, "Attachment", "Plume")
	do
		local pe = Find(plume, "ParticleEmitter")
		local v0 = (pe.Speed.Min + pe.Speed.Max) / 2
		local peak = Authored(model, plume.WorldPosition + Vector3.new(0, v0 * v0 / (2 * G * scale), 0))
		local life = pe.Lifetime.Max
		local endY = Authored(model, plume.WorldPosition + Vector3.new(0, v0 * life - 0.5 * G * scale * life * life, 0)).Y
		print(("plume peak y %.2f (JetTop 4.20), falls to y %.2f (bowl 2.50), life %.3f"):format(peak.Y, endY, life))
		check(peak.Y > 4.15 and peak.Y < 4.4, "plume peak ~ JetTop")
		check(near(endY, 2.5, 0.05), "plume falls back to the bowl water")
	end
	Frames(ctx, 600)
	local emitted = {}
	for _, pe in ipairs(FindAll(anchor, "ParticleEmitter")) do emitted[pe.Name] = (emitted[pe.Name] or 0) + (rawget(pe, "_emitted") or 0) end
	print("fountain Emit() counts over 10 s:", emitted.FunRings, emitted.Kick, emitted.FunMist)
	check((emitted.FunRings or 0) > 30, "splash rings emitted")
	local basin = Find(anchor, "Attachment", "BasinSplash")
	local a = Authored(model, basin.WorldPosition)
	check(near(a.Y, 0.75, 0.01), "basin rings sit on the basin water " .. a.Y)
	local bowl = Find(anchor, "Attachment", "BowlSplash")
	local b = Authored(model, bowl.WorldPosition)
	check(near(b.Y, 2.53, 0.01) and math.sqrt(b.X * b.X + b.Z * b.Z) <= 0.73, "bowl rings on the bowl water")
	local sound = Find(anchor, "Sound")
	Everys(ctx)
	check(sound and sound.IsPlaying, "water sound near")
	-- a wading player
	local char = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	root.CFrame = CFrame.new(Kit.ToWorld(model, Vector3.new(1.8, 2.4, 0.3)))
	rawget(root, "_p").AssemblyLinearVelocity = Vector3.new(6, 0, 2)
	table.insert(MockPlayers, {Character = char, Parent = true, Name = "Wader"})
	local ringPe = Find(basin, "ParticleEmitter", "FunRings")
	local n0 = rawget(ringPe, "_emitted") or 0
	Everys(ctx)
	check((rawget(ringPe, "_emitted") or 0) == n0 + 1, "wading ripple")
	local w = Authored(model, basin.WorldPosition)
	check(near(w.X, 1.8, 1e-4) and near(w.Z, 0.3, 1e-4), "wading ripple under the player")
	table.clear(MockPlayers)
	Stop(ctx)
	check(Find(camera, "Part", "FunFountainFX") == nil, "fountain fx removed")
	-- server half
	local S = load("S_Fountain")
	local sctx = {}
	local ok, cleanup = pcall(S.Server, model, sctx)
	check(ok, "server errored " .. tostring(cleanup))
	for _, n in ipairs({"WaterSurface", "WaterBed", "Jets", "Foam"}) do check(Kit.Part(model, n).CanCollide == false, n .. " walk-through") end
	check(Kit.Part(model, "BasinWall").CanCollide == true, "basin wall still solid")
	-- broken: BuildHealthService de-collides everything and records our false; cleanup must leave it alone
	model:SetAttribute("Broken", true)
	for _, p in ipairs(Kit.Parts(model, "")) do p.CanCollide = false end
	cleanup()
	check(Kit.Part(model, "BasinWall").CanCollide == false, "broken: cleanup leaves collisions to BuildHealthService")
	-- mend restores the record (water false, wall true), restart, then a move (cleanup restores originals)
	Kit.Part(model, "BasinWall").CanCollide = true
	model:SetAttribute("Broken", nil)
	local _, cleanup2 = pcall(S.Server, model, sctx)
	check(Kit.Part(model, "WaterSurface").CanCollide == false, "re-run after mend: water walk-through")
	cleanup2()
	for _, n in ipairs({"WaterSurface", "WaterBed", "Jets", "Foam"}) do check(Kit.Part(model, n).CanCollide == true, n .. " original restored") end
	model:Destroy()
end

------------------------------------------------------------------ Pond
do
	local scale = 1.3
	local model = MakePlaced("Pond", "Pond", nil, scale, CFrame.new(-30, 5, -70) * YAW)
	SetCamera(model, 25)
	local padsBefore = Kit.Part(model, "LilyPads").CFrame
	local lotusBefore = Kit.Part(model, "LilyLotus").CFrame
	local ctx = Run(load("C_Pond"), model)
	for _, n in ipairs({"Fish1", "Fish2", "Fish3", "FishEyes", "FishMarks"}) do check(Kit.Part(model, n).LocalTransparencyModifier == 1, n .. " hidden locally") end
	check(Kit.Part(model, "Water").CanCollide == true, "pond water stays collidable")
	local bodies = FindAll(camera, "Part", "KoiBody")
	check(#bodies == 3, "three koi")
	local fins = FindAll(camera, "WedgePart", "KoiFin")
	local tails = FindAll(camera, "WedgePart", "KoiTail")
	check(#fins == 3 and #tails == 6, "fins + tails")
	-- shore polygon for checking (authored)
	local SHORE = {{3.785, -0.488}, {2.912, -2.326}, {0.603, -1.860}, {-1.016, -2.620}, {-3.261, -1.660}, {-2.534, 0.856}, {-0.982, 2.055}, {1.788, 2.361}, {3.132, 0.556}}
	local function inside(x, z)
		local c = false
		for i = 1, #SHORE do
			local a, b = SHORE[i], SHORE[i % #SHORE + 1]
			if (a[2] > z) ~= (b[2] > z) and x < (b[1] - a[1]) * (z - a[2]) / (b[2] - a[2]) + a[1] then c = not c end
		end
		return c
	end
	local worstOut, minY, maxY, maxFinTop = 0, 99, -99, -99
	local maxTilt = 0
	local speeds = {}
	local lastPos = {}
	for step = 1, 1500 do
		Frames(ctx, 1, 0.05)
		for i, body in ipairs(bodies) do
			local a = Authored(model, body.Position)
			-- nose + tail tips
			local look = Kit.Origin(model):Inverse().Rotation * body.CFrame.LookVector -- authored frame
			local half = body.Size.Z / 2 / scale
			for _, tip in ipairs({a, a + Vector3.new(look.X, 0, look.Z) * (half + 0.2), a - Vector3.new(look.X, 0, look.Z) * (half + 0.3)}) do
				if not inside(tip.X, tip.Z) then worstOut += 1 if worstOut < 6 then print("OUT fish", i, tostring(tip), "centre", tostring(a)) end end
			end
			minY = math.min(minY, a.Y)
			maxY = math.max(maxY, a.Y)
			if lastPos[i] then
				local d = (a - lastPos[i]).Magnitude / 0.05
				speeds[i] = math.max(speeds[i] or 0, d)
				-- the fish faces where it goes
				local mv = a - lastPos[i]
				local lookA = Kit.Origin(model):Inverse().Rotation * body.CFrame.LookVector
				if mv.Magnitude > 1e-3 then
					local cosang = (Vector3.new(mv.X, 0, mv.Z).Unit):Dot(Vector3.new(lookA.X, 0, lookA.Z).Unit)
					maxTilt = math.max(maxTilt, math.deg(math.acos(math.clamp(cosang, -1, 1))))
				end
			end
			lastPos[i] = a
		end
		for _, fin in ipairs(fins) do
			local top = Authored(model, fin.CFrame * Vector3.new(0, fin.Size.Y / 2, fin.Size.Z / 2)).Y
			maxFinTop = math.max(maxFinTop, top)
		end
	end
	print(("koi: out-of-water samples %d, body y %.3f..%.3f (water 0.50), max fin top %.3f, heading error max %.1f deg, top speeds %.2f %.2f %.2f authored/s")
		:format(worstOut, minY, maxY, maxFinTop, maxTilt, speeds[1], speeds[2], speeds[3]))
	check(worstOut == 0, "koi stay in the water")
	check(maxY < 0.40 and minY > 0.28, "koi just under the surface")
	check(maxFinTop > 0.5 and maxFinTop < 0.58, "Fish1 fin breaks the surface a little")
	check(maxTilt < 25, "koi face their direction of travel (incl. the head sway)")
	-- tail: the two halves meet at the midline, wedge fan behind the body
	do
		local body = bodies[1]
		local tailPair = {}
		for _, t in ipairs(tails) do
			if (t.Position - body.Position).Magnitude < body.Size.Z then table.insert(tailPair, t) end
		end
		check(#tailPair == 2, "tail pair near body 1")
		for _, t in ipairs(tailPair) do
			local rel = body.CFrame:PointToObjectSpace(t.Position)
			check(rel.Z > body.Size.Z * 0.4, "tail behind the body (+Z) " .. tostring(rel))
			check(math.abs(t.CFrame.RightVector.Y) > 0.99, "tail wedge lies flat (thickness along Y)")
		end
	end
	-- pads bob and stay near
	local pads = Kit.Part(model, "LilyPads")
	check((pads.CFrame.Position - padsBefore.Position).Magnitude < 0.2, "pads bob in place")
	-- dump the koi parts in the pond's origin frame (world studs) for a Blender preview render
	do
		local inv = Kit.Origin(model):Inverse()
		for _, d in ipairs(camera:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:sub(1, 3) == "Koi" then
				local c = inv * d.CFrame
				local m = rawget(c, "m")
				local shape = d.ClassName == "WedgePart" and "Wedge" or (d.Shape == Enum.PartType.Ball and "Ball" or (Find(d, "SpecialMesh") and "Ellipsoid" or "Block"))
				print(("KOI %s %s %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.3f %.3f %.3f %.2f"):format(
					d.Name, shape, c.p.X, c.p.Y, c.p.Z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9],
					d.Size.X, d.Size.Y, d.Size.Z, d.Color.R, d.Color.G, d.Color.B, d.Transparency or 0))
			end
		end
	end
	-- ripples
	local rip = Find(camera, "Attachment", "Ripple")
	local total = 0
	for _, pe in ipairs(FindAll(rip, "ParticleEmitter")) do total += rawget(pe, "_emitted") or 0 end
	print("pond ripples emitted in 75 s:", total)
	check(total > 20, "ripples emitted")
	-- someone walking on the pond
	local char = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	root.CFrame = CFrame.new(Kit.ToWorld(model, Vector3.new(0.5, 2.8, 0.2)))
	rawget(root, "_p").AssemblyLinearVelocity = Vector3.new(0, 0, 8)
	table.insert(MockPlayers, {Character = char, Parent = true, Name = "Walker"})
	local big = FindAll(rip, "ParticleEmitter")[1]
	local n0 = rawget(big, "_emitted") or 0
	Everys(ctx)
	check((rawget(big, "_emitted") or 0) == n0 + 1, "walking ripple")
	table.clear(MockPlayers)
	-- BuildMenuClient move ghost (fun-builds/live/BuildMenuClient.client.lua): StartPlacing(moving) sets 0.85 on
	-- every BasePart of the build, StopPlacing sets 0 - a cancelled move / same-spot drop restarts nothing
	local STATIC = {"Fish1", "Fish2", "Fish3", "FishEyes", "FishMarks"}
	local function Ghost(v)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = v end
		end
	end
	local function StaticAll(v)
		for _, n in ipairs(STATIC) do if Kit.Part(model, n).LocalTransparencyModifier ~= v then return false end end
		return true
	end
	local function KoiAll(v)
		local n = 0
		for _, d in ipairs(camera:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:sub(1, 3) == "Koi" then
				n += 1
				if d.LocalTransparencyModifier ~= v then return false end
			end
		end
		return n == 30
	end
	check(KoiAll(0), "swimming koi start fully visible")
	Ghost(0.85)
	check(StaticAll(1), "move ghost: static koi stay hidden (no 0.85 ghost)")
	check(KoiAll(0.85), "move ghost: swimming koi fade with the pond")
	check(Kit.Part(model, "Bank").LocalTransparencyModifier == 0.85, "move ghost: the pond itself ghosts")
	Ghost(0)
	check(StaticAll(1), "cancelled move: static koi hidden again")
	check(KoiAll(0), "cancelled move: swimming koi back to full")
	Frames(ctx, 10)
	Everys(ctx)
	check(StaticAll(1), "cancelled move: static koi still hidden a moment later")
	Stop(ctx)
	for _, n in ipairs(STATIC) do check(Kit.Part(model, n).LocalTransparencyModifier == 0, n .. " shown again (cleanup not fought by the re-hide)") end
	Ghost(0.85)
	check(StaticAll(0.85), "after stop: the re-hide handlers are gone")
	Ghost(0)
	check(vnear(Kit.Part(model, "LilyPads").CFrame.Position, padsBefore.Position, 1e-5), "pads restored")
	check(vnear(Kit.Part(model, "LilyLotus").CFrame.Position, lotusBefore.Position, 1e-5), "lotus restored")
	check(#FindAll(camera, "Part", "KoiBody") == 0, "koi removed")
	-- a real move: restart while the ghost is still up, StopPlacing lands after the restart
	Ghost(0.85)
	local ctx2 = Run(load("C_Pond"), model)
	check(StaticAll(1), "restart mid-ghost: static koi hidden")
	check(KoiAll(0.85), "restart mid-ghost: new koi pick up the ghost")
	Ghost(0)
	check(StaticAll(1) and KoiAll(0), "restart then StopPlacing: static hidden, koi visible")
	Stop(ctx2)
	check(StaticAll(0), "second cleanup shows the static koi")
	model:Destroy()
end

print(("%d checks, %d failed"):format(checks, fails))
