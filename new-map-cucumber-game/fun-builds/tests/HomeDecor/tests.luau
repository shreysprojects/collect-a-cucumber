
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
local function vnear(a, b, eps) return (a - b).Magnitude <= (eps or 1e-6) end
local function cfnear(a, b, eps)
	eps = eps or 1e-5
	return vnear(a.Position, b.Position, eps) and vnear(a.LookVector, b.LookVector, eps) and vnear(a.UpVector, b.UpVector, eps)
end

------------------------------------------------------------------ template + placement (BuildService.MakeTemplate + a placed clone)
local function MakePlaced(key, scale, placeCF)
	local data = MODELS[key]
	local model = Instance.new("Model")
	model.Name = key
	local parts = {}
	local centre = (data.Min + data.Max) / 2
	for _, pd in ipairs(data.Parts) do
		local cls = pd.Shape == "Wedge" and "WedgePart" or (pd.Shape == "CornerWedge" and "CornerWedgePart" or "Part")
		local p = Instance.new(cls)
		p.Name = pd.Name
		local c = pd.CF
		local authored = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		p.Size = pd.Size * scale
		p.CFrame = CFrame.new(centre + (authored.Position - centre) * scale) * authored.Rotation
		p.Transparency = pd.T
		p.CanCollide = pd.Collide
		p.Anchored = true
		p.Parent = model
		table.insert(parts, p)
	end
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (data.Max - data.Min) * scale
	hitbox.CFrame = CFrame.new(centre)
	hitbox.Transparency = 1
	hitbox.Parent = model
	model.PrimaryPart = hitbox
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
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit, Player = MockLocalPlayer,
		_insts = {}, _cleanups = {}, _steps = {}, _everys = {}, _states = {}, StepRange = 180}
	function ctx:Alive() return true end
	function ctx:Connect() return {Disconnect = function() end} end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn)
		self._states[k] = self._states[k] or {}
		table.insert(self._states[k], fn)
		fn(self:State(k))
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
--.. the server sets a state: every running client's OnState handlers fire
local function SetState(model, ctxs, k, v)
	model:SetAttribute("Fun_" .. k, v)
	for _, ctx in ipairs(ctxs) do
		for _, fn in ipairs(ctx._states[k] or {}) do fn(v) end
	end
end

local function Run(mod, model)
	local ctx = MakeCtx(model)
	local before = #MockAll
	local ok, res = pcall(mod.Client, model, ctx)
	check(ok, "Client() errored: " .. tostring(res))
	if ok and type(res) == "function" then ctx:OnCleanup(res) end
	ctx._made = #MockAll - before
	return ctx
end
--.. step every ctx in lockstep; after(t) is called once per tick
local function Frames(ctxs, n, dt, after)
	dt = dt or 1 / 60
	for _ = 1, n do
		MockNow += dt
		for _, ctx in ipairs(ctxs) do
			check(#ctx._steps <= 1, "at most one ctx:Step per build")
			for _, fn in ipairs(ctx._steps) do
				local ok, err = pcall(fn, dt, MockNow)
				if not ok then check(false, "Step errored: " .. tostring(err)) return end
			end
		end
		if after then after() end
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
	for i = #ctx._insts, 1, -1 do ctx._insts[i]:Destroy() end
end
--.. instances a ctx made (and their descendants), by class / name
local function Mine(ctx, className, name)
	local out, seen = {}, {}
	local function take(inst)
		if seen[inst] then return end
		seen[inst] = true
		if inst.ClassName == className and (not name or inst.Name == name) then table.insert(out, inst) end
	end
	for _, inst in ipairs(ctx._insts) do
		take(inst)
		for _, d in ipairs(inst:GetDescendants()) do take(d) end
	end
	return out
end
local camera = workspace.CurrentCamera
local function SetCamera(model, dist) rawget(camera, "_p").CFrame = CFrame.new(Kit.Hitbox(model).Position + Vector3.new(0, 4, dist)) end
local function Authored(model, world) return Kit.Origin(model):PointToObjectSpace(world) / Kit.Scale(model) end
local function AngleBetween(a, b) return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1))) end

------------------------------------------------------------------ Aquarium (client)
local CASTLE_MIN, CASTLE_MAX = Vector3.new(-2.40, 3.55, 0.30), Vector3.new(-0.70, 5.70, 1.02)
local function InBox(p, lo, hi, pad)
	pad = pad or 0
	return p.X > lo.X - pad and p.X < hi.X + pad and p.Y > lo.Y - pad and p.Y < hi.Y + pad and p.Z > lo.Z - pad and p.Z < hi.Z + pad
end
do
	local mod = load("C_Aquarium")
	for _, spec in ipairs({{1, CFrame.new(40, 3, -12) * CFrame.Angles(0, math.rad(90), 0)}, {1.3, CFrame.new(-60, 5, 30) * CFrame.Angles(0, math.rad(-37), 0)}}) do
		local scale, place = spec[1], spec[2]
		local tag = ("x%.1f"):format(scale)
		local model = MakePlaced("Aquarium", scale, place)
		SetCamera(model, 20)
		local tmin, tmax = model:GetAttribute("Pivot_TankMin"), model:GetAttribute("Pivot_TankMax")
		local rest = {}
		for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then rest[d] = d.CFrame end end
		local ctx = Run(mod, model)
		local bodies = Mine(ctx, "Part", "FishBody")
		check(#bodies == 5, tag .. " five fish, got " .. #bodies)
		check(#Mine(ctx, "Part", "FishFlake") == 12, tag .. " 12 flakes")
		check(#Mine(ctx, "WedgePart", "FishTail") == 10, tag .. " 10 tail halves")
		print(tag .. " instances made by Client(): " .. ctx._made)
		for _, f in ipairs(Mine(ctx, "Part", "FishFlake")) do check(f.Transparency == 1, tag .. " flakes hidden before a feeding") end
		Everys(ctx)
		local loop = Mine(ctx, "Sound", "Bubbles")[1]
		check(loop and loop.IsPlaying, tag .. " bubbling loop plays near the tank")
		check(#Mine(ctx, "Part", "AquariumFX") == 1, tag .. " one fx host")
		--.. swim 40 s: fish inside the water box, clear of the castle, heads along their path
		local worst = {wall = math.huge, castle = math.huge, top = math.huge, bottom = math.huge}
		local minPair = math.huge
		local leaf = Kit.Part(model, "Plant1Leaf1")
		local maxLeaf = 0
		local lid = Kit.Part(model, "ChestLid")
		local lidMin, lidMax = math.huge, -math.huge
		local prev = {}
		local headingBad = 0
		local burst = Mine(ctx, "ParticleEmitter", "Burst")[1]
		--.. the bubble column (Pivot_Bubbler straight up 0.7 authored studs) must never pass through the chest lid
		--.. (any pose) or the chest's other parts: bubbles would appear out of a solid face
		local bubbleFrom = Kit.ToWorld(model, model:GetAttribute("Pivot_Bubbler"))
		local chestParts = {lid}
		for _, name in ipairs({"ChestBody", "ChestBand", "ChestLock", "ChestGold"}) do table.insert(chestParts, Kit.Part(model, name)) end
		local bubbleBlocked = 0
		local function BubbleColumnClear()
			for k = 0, 35 do
				local q = bubbleFrom + Vector3.new(0, 0.02 * k * scale, 0)
				for _, part in ipairs(chestParts) do
					local o = part.CFrame:PointToObjectSpace(q)
					local h = part.Size * 0.5 + Vector3.one * (0.035 * scale)
					if math.abs(o.X) < h.X and math.abs(o.Y) < h.Y and math.abs(o.Z) < h.Z then return false end
				end
			end
			return true
		end
		local function Probe(feeding)
			local pts = {}
			for i, b in ipairs(bodies) do
				local p = Authored(model, b.Position)
				pts[i] = p
				local half = b.Size.Z / scale * 0.5
				local lv = Kit.Origin(model).Rotation:Inverse() * b.CFrame.LookVector
				local nose, tail = p + lv * half, p - lv * half
				for _, q in ipairs({nose, tail}) do
					worst.wall = math.min(worst.wall, 2.92 - math.abs(q.X), 1.22 - math.abs(q.Z))
				end
				if not feeding then
					worst.top = math.min(worst.top, tmax.Y - p.Y)
				end
				worst.bottom = math.min(worst.bottom, p.Y - tmin.Y)
				if InBox(p, CASTLE_MIN, CASTLE_MAX, 0.12) then worst.castle = 0 end
				if prev[i] and not feeding then
					local mv = p - prev[i]
					if mv.Magnitude > 1e-3 and mv.Unit:Dot(lv) < 0.5 then headingBad += 1 end
				end
				prev[i] = p
			end
			if not feeding then
				for i = 1, #pts do
					for j = i + 1, #pts do minPair = math.min(minPair, (pts[i] - pts[j]).Magnitude) end
				end
			end
			maxLeaf = math.max(maxLeaf, AngleBetween(leaf.CFrame.UpVector, rest[leaf].UpVector))
			local a = AngleBetween(lid.CFrame.LookVector, rest[lid].LookVector)
			local up = (lid.CFrame.LookVector - rest[lid].LookVector):Dot(rest[lid].UpVector) > 0 and 1 or -1
			lidMin, lidMax = math.min(lidMin, a * up), math.max(lidMax, a * up)
			if not BubbleColumnClear() then bubbleBlocked += 1 end
		end
		Frames({ctx}, 60) -- let the yaw smoothing settle
		for k in pairs(prev) do prev[k] = nil end
		Frames({ctx}, 2400, 1 / 60, function() Probe(false) end)
		print(("%s swim 40 s: wall %.3f  top %.3f  bottom %.3f  fish-pair min %.3f  heading-bad %d  leaf sway max %.1f deg  lid %.1f..%.1f deg  bursts %d")
			:format(tag, worst.wall, worst.top, worst.bottom, minPair, headingBad, maxLeaf, lidMin, lidMax, rawget(burst, "_emitted") or 0))
		check(worst.wall > 0.1, tag .. " fish noses/tails stay off the glass")
		check(worst.top > 0.2 and worst.bottom > 0.4, tag .. " fish stay in the water column")
		check(worst.castle > 0, tag .. " no fish in the castle")
		check(minPair > 0.4, tag .. " fish keep apart")
		check(headingBad < 50, tag .. " fish face where they swim (" .. headingBad .. " bad frames)")
		check(maxLeaf > 2 and maxLeaf < 8, tag .. " leaves sway a few degrees")
		check(lidMin < -18 and lidMax > 18, tag .. " chest lid shuts and pops open")
		check((rawget(burst, "_emitted") or 0) >= 9 * 4, tag .. " a bubble burst per lid pop")
		check(bubbleBlocked == 0, tag .. " bubbles rise clear of the chest lid (" .. bubbleBlocked .. " blocked frames)")
		--.. the castle flag and the rest of the build: only the animated parts moved
		for part, cf in pairs(rest) do
			local n = part.Name
			local animated = n:match("^Plant%d+Leaf%d+$") or n == "CastleFlag" or n == "ChestLid" or n == "FeedFlap" or n == "FeedFlapTab"
			if not animated then check(cfnear(part.CFrame, cf), tag .. " static part moved: " .. n) end
		end

		--.. FEEDING: a second client joins now, a third streams in 2 s late
		local ctx2 = Run(mod, model)
		Everys(ctx2)
		local t0 = MockNow
		SetState(model, {ctx, ctx2}, "FedAt", t0)
		local flap = Kit.Part(model, "FeedFlap")
		local flakes = Mine(ctx, "Part", "FishFlake")
		local flakes2 = Mine(ctx2, "Part", "FishFlake")
		local bodies2 = Mine(ctx2, "Part", "FishBody")
		local seen, gone = {}, {}
		local flapMax = 0
		local nearSurface = {}
		local mismatch = 0
		local feedPair = math.huge
		local ctx3
		local ring = Mine(ctx, "ParticleEmitter", "LandRing")[1]
		local gulp = Mine(ctx, "ParticleEmitter", "Gulp")[1]
		local bodies3, ring3
		local function Track()
			local t = MockNow - t0
			flapMax = math.max(flapMax, AngleBetween(flap.CFrame.UpVector, rest[flap].UpVector))
			for i, f in ipairs(flakes) do
				if f.Transparency < 1 then
					seen[i] = seen[i] or t
					local p = Authored(model, f.Position)
					check(math.abs(p.Y - (tmax.Y + 0.025)) < 0.5, tag .. " flake near the surface")
				elseif seen[i] and not gone[i] then
					gone[i] = t
				end
			end
			local pts = {}
			for i, b in ipairs(bodies) do
				local p = Authored(model, b.Position)
				pts[i] = p
				if tmax.Y - p.Y < 0.3 then nearSurface[i] = true end
				if not vnear(b.Position, bodies2[i].Position, 1e-6) then mismatch += 1 end
				if bodies3 and not vnear(b.Position, bodies3[i].Position, 1e-6) then mismatch += 1 end
				if InBox(p, CASTLE_MIN, CASTLE_MAX, 0.05) then check(false, tag .. " feeding fish in the castle") end
			end
			for i, f in ipairs(flakes) do
				if (f.Transparency < 1) ~= (flakes2[i].Transparency < 1) then mismatch += 1 end
			end
			for i = 1, #pts do
				for j = i + 1, #pts do feedPair = math.min(feedPair, (pts[i] - pts[j]).Magnitude) end
			end
		end
		Frames({ctx, ctx2}, 150, 1 / 60, Track)
		if scale == 1 then
			--.. DUMP lines (authored frame) for the Blender review render: tests/HomeDecor/render_dump.py
			local inv = Kit.Origin(model):Inverse()
			for _, inst in ipairs(ctx._insts) do
				if inst:IsA("BasePart") and inst.Transparency < 1 and inst.Name ~= "AquariumFX" then
					local c = inv * inst.CFrame
					local m = c.m
					local shape = inst.ClassName == "WedgePart" and "Wedge" or (inst.Shape == Enum.PartType.Ball and "Ball"
						or (inst:FindFirstChildOfClass("SpecialMesh") and "Ellipsoid" or "Block"))
					local col = inst.Color
					print(("DUMP|%s|%s|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f|%.4f,%.4f,%.4f|%s")
						:format(inst.Name, shape, inst.Size.X, inst.Size.Y, inst.Size.Z, c.p.X, c.p.Y, c.p.Z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9],
							col.R, col.G, col.B, tostring(inst.Material)))
				end
			end
			for _, name in ipairs({"FeedFlap", "FeedFlapTab", "ChestLid"}) do
				local part = Kit.Part(model, name)
				local c = inv * part.CFrame
				local m = c.m
				print(("POSE|%s|%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f"):format(name, c.p.X, c.p.Y, c.p.Z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]))
			end
		end
		ctx3 = Run(mod, model) -- streams in 2.5 s into the feeding
		bodies3 = Mine(ctx3, "Part", "FishBody")
		ring3 = Mine(ctx3, "ParticleEmitter", "LandRing")[1]
		Frames({ctx, ctx2, ctx3}, 330, 1 / 60, Track)
		local nSeen, nGone = 0, 0
		for i = 1, 12 do
			if seen[i] then nSeen += 1 end
			if gone[i] then nGone += 1 end
		end
		local nNear = 0
		for i = 1, 5 do if nearSurface[i] then nNear += 1 end end
		print(("%s feed: flap max %.1f deg, flakes seen %d eaten %d, fish at the surface %d/5, fish-pair min %.2f, client mismatches %d, rings %d (late client %d), gulps %d")
			:format(tag, flapMax, nSeen, nGone, nNear, feedPair, mismatch, rawget(ring, "_emitted") or 0, rawget(ring3, "_emitted") or 0, rawget(gulp, "_emitted") or 0))
		check(flapMax > 60 and flapMax < 75, tag .. " feed flap opens ~68 deg")
		check(cfnear(flap.CFrame, rest[flap]), tag .. " feed flap shut again")
		check(nSeen == 12 and nGone == 12, tag .. " all 12 flakes fall and get eaten")
		check(nNear == 5, tag .. " every fish rushes up to the food")
		check(mismatch == 0, tag .. " every client shows the same fish and flakes")
		check((rawget(ring, "_emitted") or 0) == 12, tag .. " a landing ring per flake")
		check((rawget(ring3, "_emitted") or 0) == 0, tag .. " a late client does not replay old landings")
		local click1 = Mine(ctx, "Sound", "Click")[1]
		local click3 = Mine(ctx3, "Sound", "Click")[1]
		check((rawget(click1, "_plays") or 0) == 2, tag .. " the flap clicks open and shut (on-time client)")
		check((rawget(click3, "_plays") or 0) == 0, tag .. " a late client does not click for a flap close long past")
		check((rawget(gulp, "_emitted") or 0) == 36, tag .. " 3 gulp bubbles per flake")
		for _, f in ipairs(flakes) do check(f.Transparency == 1, tag .. " flakes hidden after the feeding") end
		--.. the fish swim back into their loops (compare with a fresh client that never saw the feeding)
		Frames({ctx, ctx2, ctx3}, 120)
		SetState(model, {}, "FedAt", nil)
		local fresh = Run(mod, model)
		Frames({ctx, fresh}, 2)
		local freshBodies = Mine(fresh, "Part", "FishBody")
		for i, b in ipairs(bodies) do check(vnear(b.Position, freshBodies[i].Position, 1e-6), tag .. " fish " .. i .. " back on its loop") end
		--.. far camera: steps are asleep in the real framework; Every turns the loop and the light off
		rawget(camera, "_p").CFrame = CFrame.new(Kit.Hitbox(model).Position + Vector3.new(0, 0, 400))
		Everys(ctx)
		check(not loop.IsPlaying, tag .. " bubbling loop stops far away")
		check(Mine(ctx, "ParticleEmitter", "Trickle")[1].Enabled == false, tag .. " trickle off far away")
		--.. cleanup: every build part back at rest
		for _, c in ipairs({fresh, ctx3, ctx2, ctx}) do Stop(c) end
		for part, cf in pairs(rest) do check(cfnear(part.CFrame, cf), tag .. " restored: " .. part.Name) end
		check(#Mine(ctx, "Part", "FishBody") == 5 and bodies[1].Parent == nil, tag .. " fish destroyed")
		model:Destroy()
	end
end

------------------------------------------------------------------ Aquarium feeding survey: fish spacing over many feedings
do
	local mod = load("C_Aquarium")
	local model = MakePlaced("Aquarium", 1, CFrame.new(7, 3, 9))
	SetCamera(model, 20)
	local ctx = Run(mod, model)
	local bodies = Mine(ctx, "Part", "FishBody")
	local mins, all = {}, {}
	for n = 1, 24 do
		Frames({ctx}, 97 + n * 13, 1 / 30) -- a different moment of the loops every time
		local t0 = MockNow
		SetState(model, {ctx}, "FedAt", t0)
		local low = math.huge
		local lowPair = ""
		Frames({ctx}, 200, 1 / 30, function()
			for i = 1, 5 do
				for j = i + 1, 5 do
					local d = (Authored(model, bodies[i].Position) - Authored(model, bodies[j].Position)).Magnitude
					if d < low then low, lowPair = d, i .. "-" .. j .. (" @%.1fs"):format(MockNow - t0) end
				end
			end
		end)
		table.insert(mins, low)
		table.insert(all, ("%.2f(%s)"):format(low, lowPair))
		SetState(model, {ctx}, "FedAt", nil)
	end
	table.sort(mins)
	print("feeding survey, closest two fish per feeding: " .. table.concat(all, " "))
	print(("feeding survey: worst %.2f  median %.2f"):format(mins[1], mins[12]))
	check(mins[12] > 0.2, "feeding: fish mostly keep apart")
	Stop(ctx)
	model:Destroy()
end

------------------------------------------------------------------ Aquarium (server)
do
	local mod = load("S_Aquarium")
	local model = MakePlaced("Aquarium", 1, CFrame.new(0, 3, 0))
	local function Signal()
		local s = {fns = {}}
		function s:Connect(fn) table.insert(self.fns, fn) return {Disconnect = function() end} end
		function s:Fire(...) for _, fn in ipairs(self.fns) do fn(...) end end
		return s
	end
	local prompts = {}
	local ctx = {Model = model, Key = "Aquarium", Base = "Aquarium", Scale = 1}
	function ctx:Alive() return true end
	function ctx:Connect(sig, fn) return sig:Connect(fn) end
	function ctx:Prompt(part, opts)
		local p = {ActionText = opts.Action, ObjectText = opts.Object, MaxActivationDistance = opts.Distance, Part = part, Parent = part, Triggered = Signal()}
		table.insert(prompts, p)
		return p
	end
	function ctx:HumanoidOf(player) if player.Alive then return {}, {} end return nil end
	function ctx:SetState(k, v) model:SetAttribute("Fun_" .. k, v) end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	local ok, err = pcall(mod.Server, model, ctx)
	check(ok, "server Server() errored: " .. tostring(err))
	check(#prompts == 1 and prompts[1].Part.Name == "FeedFlap", "server: one prompt on the FeedFlap")
	local prompt = prompts[1]
	check(prompt.ActionText == "Feed fish" and prompt.ObjectText == "Aquarium", "server: prompt text")
	prompt.Triggered:Fire({Alive = false, UserId = 1})
	check(model:GetAttribute("Fun_FedAt") == nil, "server: a dead player can't feed")
	prompt.Triggered:Fire({Alive = true, UserId = 1})
	local t0 = model:GetAttribute("Fun_FedAt")
	check(t0 == MockNow, "server: Fun_FedAt = now")
	check(prompt.ActionText == "Fish are eating...", "server: busy text")
	MockNow += 3
	prompt.Triggered:Fire({Alive = true, UserId = 2})
	check(model:GetAttribute("Fun_FedAt") == t0, "server: no second feeding within the cooldown")
	MockNow += 4.5
	for _, d in ipairs(MockDelayed) do d.Fn(table.unpack(d.Args)) end
	table.clear(MockDelayed)
	check(prompt.ActionText == "Feed fish", "server: prompt text back after the cooldown")
	prompt.Triggered:Fire({Alive = true, UserId = 2})
	check(model:GetAttribute("Fun_FedAt") == MockNow, "server: feeding again after the cooldown")
	model:Destroy()
end

------------------------------------------------------------------ PottedPlant (client)
do
	local mod = load("C_PottedPlant")
	for _, spec in ipairs({{1, CFrame.new(10, 2, 10) * CFrame.Angles(0, math.rad(33), 0)}, {1.4, CFrame.new(-5, 0, 7)}}) do
		local scale, place = spec[1], spec[2]
		local tag = ("plant x%.1f"):format(scale)
		local model = MakePlaced("PottedPlant", scale, place)
		SetCamera(model, 15)
		local rest = {}
		for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then rest[d] = d.CFrame end end
		local ctx = Run(mod, model)
		local maxA, maxTip = 0, 0
		local bases = {}
		for n = 0, 11 do bases[n] = Kit.Pivot(model, "Frond" .. n) end
		Frames({ctx}, 1200, 1 / 60, function()
			for part, cf in pairs(rest) do
				local n = tonumber(part.Name:match("^Frond(%d+)"))
				if n then
					maxA = math.max(maxA, AngleBetween(part.CFrame.UpVector, cf.UpVector), AngleBetween(part.CFrame.LookVector, cf.LookVector))
					maxTip = math.max(maxTip, (part.Position - cf.Position).Magnitude)
					-- the stem's base stays planted: distance to its pivot is constant
					local d0 = (cf.Position - bases[n]).Magnitude
					local d1 = (part.Position - bases[n]).Magnitude
					if math.abs(d0 - d1) > 1e-4 then check(false, tag .. " frond part keeps its distance to its base: " .. part.Name) end
				elseif part.Name ~= "Hitbox" then
					if not cfnear(part.CFrame, cf) then check(false, tag .. " static part moved: " .. part.Name) end
				end
			end
		end)
		print(("%s: 20 s sway max %.2f deg, max part travel %.3f studs"):format(tag, maxA, maxTip))
		check(maxA > 1 and maxA < 4.5, tag .. " gentle sway")
		Stop(ctx)
		for part, cf in pairs(rest) do check(cfnear(part.CFrame, cf), tag .. " restored: " .. part.Name) end
		model:Destroy()
	end
end

print(("%d checks, %d failed"):format(checks, fails))
