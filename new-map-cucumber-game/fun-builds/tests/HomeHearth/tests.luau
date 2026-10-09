------------------------------------------------------------------ HomeHearth headless tests (Fireplace + FloorLamp)
-- run: py tests/HomeHearth/gen.py   (mock.luau + module sources + parts.json models + this file -> run.luau)

------------------------------------------------------------------ loader (os.clock is controllable; os.date must not be used)
local env = getfenv(1)
local realOs = os
MockClock = 1000
local osDateCalls = 0
env.os = setmetatable({
	clock = function() return MockClock end,
	date = function(...) osDateCalls += 1 return realOs.date(...) end,
}, {__index = realOs})
local function SetClockTime(t) rawget(MockLighting, "_p").ClockTime = t end
SetClockTime(15.5) -- 15:30 game time -> the mantel clock shows 3:30
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
		_insts = {folder}, _conns = {}, _states = {}, _fired = {}}
	function ctx:Fire(action, payload) table.insert(self._fired, {Action = action, Payload = payload}) end
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

--========================================================================== FIREPLACE (client)
do
	local C = require({Name = "C_Fireplace"})
	local scale = 1.2
	local place = CFrame.new(40, 4.2, -12) * CFrame.Angles(0, math.rad(90), 0)
	local model = MakePlaced("Fireplace", scale, place)
	local hitbox = Kit.Hitbox(model)
	local origin = Kit.Origin(model)
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 5, -14)))
	local snap = Snapshot(model)
	local ctx = Run(C, model)

	local fires = FindAll(ctx._insts, "Fire")
	check(#fires == 2, "fireplace: 2 Fire instances (got " .. #fires .. ")")
	for _, f in ipairs(fires) do check(f.Enabled == false, "fireplace: fire starts off") end
	local light = FindIn(ctx._insts, "PointLight")
	check(light ~= nil and light.Enabled == false, "fireplace: light exists and starts off")
	check(light and light.Range == math.min(60, 20 * scale), "fireplace: light range 20 x scale")
	check(light and light.Shadows == true, "fireplace: light casts shadows")
	local host = FindIn(ctx._insts, "Part", "FireplaceFire")
	check(host and vnear(host.Position, Kit.Pivot(model, "Fire"), 1e-5), "fireplace: fire host at Pivot_Fire")
	check(light and vnear(light.Parent.WorldPosition, Kit.Pivot(model, "Light"), 1e-5), "fireplace: light at Pivot_Light")
	local chim = FindIn(ctx._insts, "Part", "FireplaceChimney")
	check(chim and vnear(chim.Position, Kit.Pivot(model, "Chimney"), 1e-5), "fireplace: chimney host at Pivot_Chimney")
	local flames = Kit.Parts(model, "CandleFlame")
	local embers = Kit.Parts(model, "Ember")
	check(#flames == 3, "fireplace: 3 candle flames")
	check(#embers == 8, "fireplace: 8 ember parts (got " .. #embers .. ")")
	for _, p in ipairs(flames) do check(p.Transparency == 1, "fireplace: candle " .. p.Name .. " starts out") end
	local sparks = FindIn(ctx._insts, "ParticleEmitter", "Sparks")
	local puff = FindIn(ctx._insts, "ParticleEmitter", "Puff")
	local smoke = FindIn(ctx._insts, "ParticleEmitter", "ChimneySmoke")
	local ignite = FindIn(ctx._insts, "Sound", "Ignite")
	local douse = FindIn(ctx._insts, "Sound", "Douse")
	local crackle = FindIn(ctx._insts, "Sound", "Crackle")
	check(sparks and puff and smoke and ignite and douse and crackle, "fireplace: emitters + sounds exist")
	check(#FindAll(ctx._insts, "PointLight") + #FindAll(ctx._insts, "SpotLight") <= 2, "fireplace: <= 2 lights")

	--.. a cold frame changes nothing on the embers
	Everys(ctx)
	Frames(ctx, 0.1)
	for _, p in ipairs(embers) do check(p.Material == snap[p].Material, "fireplace: cold ember " .. p.Name .. " untouched") end

	--.. clock hands show the game's 15:30 as 3:30 (hour 105 deg, minute 180 deg clockwise seen from the front)
	local function HandAngle(name)
		local part = Kit.Part(model, name)
		local up = origin.Rotation:Inverse() * part.CFrame.UpVector -- authored axes
		return math.deg(math.atan2(-up.X, up.Y)) % 360, up.Z
	end
	local h, hz = HandAngle("ClockHour")
	local mnt, mz = HandAngle("ClockMinute")
	check(near(h, 105, 0.01) and near(hz, 0, 1e-6), ("fireplace: hour hand at 105 deg (got %.3f)"):format(h))
	check(near(mnt, 180, 0.01) and near(mz, 0, 1e-6), ("fireplace: minute hand at 180 deg (got %.3f)"):format(mnt))
	--.. the hand still pivots about the face centre (its distance to the centre is unchanged)
	local centre = Kit.Pivot(model, "ClockCentre")
	local hourPart = Kit.Part(model, "ClockHour")
	check(near((hourPart.Position - centre).Magnitude, (snap[hourPart].CFrame.Position - centre).Magnitude, 1e-5), "fireplace: hour hand turns about the clock centre")
	check(osDateCalls == 0, "fireplace: clock does not read the viewer's local time (os.date)")
	--.. the hands follow Lighting.ClockTime within CLOCK_RATE (9:15 -> hour 277.5, minute 90)
	SetClockTime(9.25)
	Frames(ctx, 0.12)
	h = HandAngle("ClockHour")
	mnt = HandAngle("ClockMinute")
	check(near(h, 277.5, 0.01) and near(mnt, 90, 0.01), ("fireplace: hands follow ClockTime 9.25 (got %.3f / %.3f)"):format(h, mnt))
	--.. night jump 16:00 -> 0:00: the mantel clock snaps to 12:00
	SetClockTime(0)
	Frames(ctx, 0.12)
	h = HandAngle("ClockHour")
	mnt = HandAngle("ClockMinute")
	check(near(h, 0, 0.01) or near(h, 360, 0.01), ("fireplace: midnight hour hand at 0 (got %.3f)"):format(h))
	check(near(mnt, 0, 0.01) or near(mnt, 360, 0.01), ("fireplace: midnight minute hand at 0 (got %.3f)"):format(mnt))
	SetClockTime(15.5)
	Frames(ctx, 0.12)

	--.. light it (camera near: live)
	model:SetAttribute("Fun_Lit", true)
	check(ignite.IsPlaying == true, "fireplace: ignite sound on lighting")
	check((rawget(sparks, "_emitted") or 0) == 18, "fireplace: spark burst on lighting")
	for _, f in ipairs(fires) do check(f.Enabled == true, "fireplace: fire on once lit") end
	check(sparks.Enabled == true, "fireplace: sparks on once lit")
	check(crackle.IsPlaying == true, "fireplace: crackle plays near")
	Frames(ctx, 0.5)
	check(flames[1].Transparency == 0, "fireplace: first candle lit after 0.5 s")
	check(flames[3].Transparency == 1, "fireplace: third candle not yet lit after 0.5 s")
	check(light.Enabled and light.Brightness > 0.3 and light.Brightness < 2.2, "fireplace: light fading in")
	Frames(ctx, 1.5)
	for _, p in ipairs(flames) do check(p.Transparency == 0, "fireplace: candle " .. p.Name .. " lit after 2 s") end
	check(light.Brightness > 1.5 and light.Brightness < 3.2, ("fireplace: light at full flicker (%.2f)"):format(light.Brightness))
	check(light.Range <= 60 and light.Range > 15, "fireplace: range sane")
	check(smoke.Enabled == true, "fireplace: chimney smoke while burning")
	check(crackle.Volume > 0.45, "fireplace: crackle at volume")
	for _, p in ipairs(embers) do
		check(p.Material == Enum.Material.Neon, "fireplace: ember " .. p.Name .. " Neon while lit")
		check(p.Color.R > 0.85 and p.Color.B < 0.2, "fireplace: ember " .. p.Name .. " glows orange " .. tostring(p.Color))
	end
	local mesh = flames[1]:FindFirstChildOfClass("SpecialMesh")
	check(mesh and not vnear(mesh.Scale, Vector3.one, 1e-4), "fireplace: candle flame flickers (mesh scale)")

	--.. put it out
	MockClock += 0.1
	model:SetAttribute("Fun_Lit", false)
	check(douse.IsPlaying == true, "fireplace: douse sound on putting out")
	check((rawget(puff, "_emitted") or 0) == 14, "fireplace: smoke puff on putting out")
	for _, f in ipairs(fires) do check(f.Enabled == false, "fireplace: fire off when put out") end
	Frames(ctx, 0.05)
	for _, p in ipairs(flames) do check(p.Transparency == 1, "fireplace: candle " .. p.Name .. " out with the fire") end
	Frames(ctx, 1)
	check(embers[1].Material == Enum.Material.Neon, "fireplace: embers still glow 1 s after putting out")
	check(light.Enabled, "fireplace: light still dying down 1 s after")
	Frames(ctx, 3)
	check(light.Enabled == false, "fireplace: light off once cold")
	check(smoke.Enabled == false, "fireplace: no chimney smoke once cold")
	for _, p in ipairs(embers) do
		check(p.Material == snap[p].Material and p.Color == snap[p].Color, "fireplace: ember " .. p.Name .. " back to charcoal")
	end
	Everys(ctx)
	check(crackle.IsPlaying == false, "fireplace: crackle stops")
	for _, f in ipairs(fires) do check(f.Size == 2, ("fireplace: cold fire shrunk to the 2 floor (%.2f)"):format(f.Size)) end

	--.. relit while this viewer is far away: heat snaps to 1, and so must the flame size
	CameraAt(hitbox.Position + Vector3.new(0, 0, 150))
	model:SetAttribute("Fun_Lit", true)
	local want = {math.clamp(3.2 * scale, 2, 30), math.clamp(2.2 * scale, 2, 30)}
	table.sort(want)
	local got = {fires[1].Size, fires[2].Size}
	table.sort(got)
	check(near(got[1], want[1], 1e-6) and near(got[2], want[2], 1e-6),
		("fireplace: fires at full size after a far-away relight (%.2f / %.2f, want %.2f / %.2f)"):format(got[1], got[2], want[1], want[2]))
	model:SetAttribute("Fun_Lit", false)
	for _, f in ipairs(fires) do check(f.Size == 2, "fireplace: far-away put-out snaps the flames small") end
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 5, -14)))

	--.. relight and stop while lit: every part back as authored
	model:SetAttribute("Fun_Lit", true)
	Frames(ctx, 2)
	Stop(ctx)
	SameAsSnapshot(model, snap, "fireplace cleanup")
	for _, i in ipairs(ctx._insts) do check(rawget(i, "_destroyed") == true, "fireplace: " .. i.Name .. " destroyed on cleanup") end

	--.. streamed in while already lit, camera far: straight to the blaze, no fanfare
	CameraAt(hitbox.Position + Vector3.new(0, 0, 150))
	local ctx2 = Run(C, model)
	local ignite2 = FindIn(ctx2._insts, "Sound", "Ignite")
	check(ignite2.IsPlaying == false, "fireplace: no ignite sound when streamed in lit")
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 5, -14)))
	Everys(ctx2)
	Frames(ctx2, 1 / 60)
	local light2 = FindIn(ctx2._insts, "PointLight")
	check(light2.Enabled and light2.Brightness > 1.5, "fireplace: streamed-in lit fire is at full blaze at once")
	for _, p in ipairs(flames) do check(p.Transparency == 0, "fireplace: streamed-in candles already lit") end
	Stop(ctx2)
	SameAsSnapshot(model, snap, "fireplace cleanup 2")

	--.. a picture from FunAssets.Pictures replaces the painted landscape; broken cleanup keeps the fade
	FunAssets.Pictures = {"rbxassetid://123456"}
	model:SetAttribute("Fun_Lit", false)
	local ctx3 = Run(C, model)
	local decal = FindIn(ctx3._insts, "Decal")
	check(decal and decal.Texture == "rbxassetid://123456" and decal.Parent == Kit.Part(model, "PicCanvas"), "fireplace: picture decal on the canvas")
	check(Kit.Part(model, "PicHill").Transparency == 1 and Kit.Part(model, "PicSun").Transparency == 1, "fireplace: painted scene hidden under the picture")
	model:SetAttribute("Broken", true)
	Stop(ctx3)
	check(Kit.Part(model, "PicHill").Transparency == 0.65, "fireplace: broken cleanup leaves the hill at the broken fade")
	model:SetAttribute("Broken", nil)
	FunAssets.Pictures = {}
	model.Parent = nil
end

--========================================================================== FIREPLACE (server)
do
	local S = require({Name = "S_Fireplace"})
	local model = MakePlaced("Fireplace", 1, CFrame.new(0, 3.5, 0))
	local ctx = MakeServerCtx(model)
	local ok, err = pcall(S.Server, model, ctx)
	check(ok, "fireplace server errored: " .. tostring(err))
	local prompt = FindIn(ctx._insts, "ProximityPrompt")
	check(prompt ~= nil, "fireplace server: prompt")
	check(prompt.ActionText == "Light fire" and prompt.ObjectText == "Fireplace", "fireplace server: prompt text")
	check(vnear(prompt.Parent.Position, Kit.Pivot(model, "Prompt"), 1e-5), "fireplace server: prompt at Pivot_Prompt")
	check(model:GetAttribute("Fun_Lit") == false, "fireplace server: starts out")
	local player = {Alive = true, UserId = 7}
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_Lit") == true and prompt.ActionText == "Put out", "fireplace server: lit by the prompt")
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_Lit") == true, "fireplace server: debounce holds a double press")
	MockClock += 1
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_Lit") == false and prompt.ActionText == "Light fire", "fireplace server: put out by the prompt")
	MockClock += 1
	prompt.Triggered:Fire({Alive = false})
	check(model:GetAttribute("Fun_Lit") == false, "fireplace server: a dead player can't light it")
	--.. night does not light it
	workspace:SetAttribute("IsNight", true)
	check(model:GetAttribute("Fun_Lit") == false, "fireplace server: night does not light it")
	workspace:SetAttribute("IsNight", false)
	model.Parent = nil
end

--========================================================================== FLOOR LAMP (client)
do
	local C = require({Name = "C_FloorLamp"})
	local place = CFrame.new(-20, 3.9, 8) * CFrame.Angles(0, math.rad(30), 0)
	local model = MakePlaced("FloorLamp", 1, place)
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 6, -12)))
	local snap = Snapshot(model)
	local ctx = Run(C, model)
	local point = FindIn(ctx._insts, "PointLight")
	local spot = FindIn(ctx._insts, "SpotLight")
	check(point and spot, "lamp: point + spot lights")
	check(#FindAll(ctx._insts, "PointLight") + #FindAll(ctx._insts, "SpotLight") == 2, "lamp: exactly 2 lights")
	check(point.Enabled == false and spot.Enabled == false, "lamp: starts off (Fun_On unset)")
	check(spot.Face == Enum.NormalId.Bottom and spot.Shadows == true, "lamp: spot faces down, shadows on")
	check(vnear(spot.Parent.CFrame.UpVector, Vector3.new(0, 1, 0), 1e-6), "lamp: spot host upright (Bottom face = down)")
	check(vnear(point.Parent.Position, Kit.Pivot(model, "Light"), 1e-5), "lamp: point light at Pivot_Light")
	check(vnear(spot.Parent.Position, Kit.Pivot(model, "Spot"), 1e-5), "lamp: spot light at Pivot_Spot")
	local glowTop, bulb = Kit.Part(model, "ShadeGlowTop"), Kit.Part(model, "Bulb")
	local panels = Kit.Parts(model, "ShadePanel")
	check(glowTop and bulb and #panels == 16, "lamp: glow parts found")
	local bead = Kit.Part(model, "PullBead")
	local beadRest = bead.Position
	local click = FindIn(ctx._insts, "Sound", "Click")

	--.. the dusk switch (state alone, no Tug event): the glow eases in, no click, no tug
	model:SetAttribute("Fun_On", true)
	check(click.IsPlaying == false, "lamp: no click from the dusk switch")
	Frames(ctx, 0.12)
	check(vnear(bead.Position, beadRest, 1e-6), "lamp: no chain tug from the dusk switch")
	check(point.Enabled and point.Brightness < 1.3, "lamp: dusk switch warms up")
	Frames(ctx, 0.5)
	check(point.Enabled and near(point.Brightness, 1.3, 1e-6), "lamp: on after the dusk switch")
	model:SetAttribute("Fun_On", false)
	Frames(ctx, 0.6)
	check(point.Enabled == false, "lamp: off after the dawn switch")

	--.. switch on by hand (live): state + the server's Tug event
	model:SetAttribute("Fun_On", true)
	C.OnEvent(model, "Tug", nil, ctx)
	check(click.IsPlaying == true, "lamp: click on a hand switch")
	Frames(ctx, 0.12)
	check(bead.Position.Y < beadRest.Y - 0.1, ("lamp: chain tugged down (dy %.3f)"):format(bead.Position.Y - beadRest.Y))
	check(point.Enabled and point.Brightness < 1.3, "lamp: warming up")
	Frames(ctx, 0.5)
	check(vnear(bead.Position, beadRest, 1e-6), "lamp: chain back at rest after the tug")
	check(point.Enabled and near(point.Brightness, 1.3, 1e-6) and spot.Enabled and near(spot.Brightness, 2.6, 1e-6), "lamp: full brightness when on")
	check(glowTop.Material == Enum.Material.Neon and bulb.Material == Enum.Material.Neon, "lamp: diffuser + bulb Neon when on")
	check(glowTop.Color == Color3.fromRGB(255, 226, 166), "lamp: diffuser lit colour")
	for _, p in ipairs(panels) do
		check(p.Material == Enum.Material.Neon and p.Color == Color3.fromRGB(255, 228, 175), "lamp: shade panel " .. p.Name .. " glows warm cream Neon when on")
	end

	--.. off
	model:SetAttribute("Fun_On", false)
	Frames(ctx, 0.6)
	check(point.Enabled == false and spot.Enabled == false, "lamp: lights off")
	check(glowTop.Material == snap[glowTop].Material and glowTop.Color == snap[glowTop].Color, "lamp: diffuser back when off")
	check(panels[5].Color == snap[panels[5]].Color and panels[5].Material == snap[panels[5]].Material, "lamp: panels back to Fabric when off")
	--.. a Tug seen from far away: no click, no tug
	click:Stop()
	CameraAt(Kit.Hitbox(model).Position + Vector3.new(0, 0, 150))
	C.OnEvent(model, "Tug", nil, ctx)
	check(click.IsPlaying == false, "lamp: no click for a far-away Tug")
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 6, -12)))
	Frames(ctx, 0.1)
	check(vnear(bead.Position, beadRest, 1e-6), "lamp: no tug for a far-away Tug")
	local okOther = pcall(C.OnEvent, model, "Other", nil, ctx)
	local okEarly = pcall(C.OnEvent, model, "Tug", nil, {}) -- a ctx whose Client never ran (not streamed in yet)
	check(okOther and okEarly, "lamp: OnEvent ignores other actions and a not-yet-running ctx")

	--.. on + stop mid-tug: every part back
	model:SetAttribute("Fun_On", true)
	C.OnEvent(model, "Tug", nil, ctx)
	Frames(ctx, 0.1)
	check(bead.Position.Y < beadRest.Y - 0.05, "lamp: mid-tug before the stop")
	Stop(ctx)
	SameAsSnapshot(model, snap, "lamp cleanup")

	--.. streamed in while on: lit at once, no click, no tug
	CameraAt(Kit.Hitbox(model).Position + Vector3.new(0, 0, 150))
	local ctx2 = Run(C, model)
	check(FindIn(ctx2._insts, "Sound", "Click").IsPlaying == false, "lamp: no click when streamed in on")
	local point2 = FindIn(ctx2._insts, "PointLight")
	check(point2.Enabled and near(point2.Brightness, 1.3, 1e-6), "lamp: streamed-in lamp already on")
	Frames(ctx2, 0.1)
	check(vnear(bead.Position, beadRest, 1e-6), "lamp: no tug when streamed in")
	Stop(ctx2)
	SameAsSnapshot(model, snap, "lamp cleanup 2")
	model.Parent = nil
end

--========================================================================== FLOOR LAMP (server)
do
	local S = require({Name = "S_FloorLamp"})
	workspace:SetAttribute("IsNight", false)
	workspace:SetAttribute("CyclePhase", "Day")
	local model = MakePlaced("FloorLamp", 1, CFrame.new(5, 3.9, 5))
	local ctx = MakeServerCtx(model)
	local ok, err = pcall(S.Server, model, ctx)
	check(ok, "lamp server errored: " .. tostring(err))
	local prompt = FindIn(ctx._insts, "ProximityPrompt")
	check(prompt and prompt.ActionText == "Lamp on" and prompt.ObjectText == "Floor Lamp", "lamp server: prompt")
	check(vnear(prompt.Parent.Position, Kit.Pivot(model, "Switch"), 1e-5), "lamp server: prompt at the pull-chain bead")
	check(model:GetAttribute("Fun_On") == false, "lamp server: off by day")
	workspace:SetAttribute("CyclePhase", "Night")
	workspace:SetAttribute("IsNight", true)
	check(model:GetAttribute("Fun_On") == true and prompt.ActionText == "Lamp off", "lamp server: on at dusk")
	check(#ctx._fired == 0, "lamp server: no Tug event from the start state or the dusk switch")
	local player = {Alive = true, UserId = 9}
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_On") == false and prompt.ActionText == "Lamp on", "lamp server: switched off by hand at night")
	check(#ctx._fired == 1 and ctx._fired[1].Action == "Tug", "lamp server: a hand switch fires Tug")
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_On") == false, "lamp server: debounce")
	check(#ctx._fired == 1, "lamp server: no Tug for a debounced press")
	workspace:SetAttribute("CyclePhase", "Night") -- same value: no signal
	check(model:GetAttribute("Fun_On") == false, "lamp server: stays off by hand through the night")
	MockClock += 1
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_On") == true, "lamp server: back on by hand")
	workspace:SetAttribute("CyclePhase", "PreparingDay")
	workspace:SetAttribute("IsNight", false)
	check(model:GetAttribute("Fun_On") == false, "lamp server: off at dawn")
	check(#ctx._fired == 2, ("lamp server: dawn fired no Tug (%d events)"):format(#ctx._fired))
	MockClock += 1
	prompt.Triggered:Fire({Alive = false})
	check(#ctx._fired == 2, "lamp server: a dead player's press fires nothing")
	--.. a lamp placed at night starts on
	local model2 = MakePlaced("FloorLamp", 1, CFrame.new(15, 3.9, 5))
	workspace:SetAttribute("IsNight", true)
	local ctx2 = MakeServerCtx(model2)
	S.Server(model2, ctx2)
	check(model2:GetAttribute("Fun_On") == true, "lamp server: placed at night -> on")
	--.. no IsNight attribute: CyclePhase decides
	workspace:SetAttribute("CyclePhase", "Night")
	workspace:SetAttribute("IsNight", nil)
	check(model2:GetAttribute("Fun_On") == true, "lamp server: CyclePhase fallback -> night on")
	workspace:SetAttribute("CyclePhase", "Day")
	check(model2:GetAttribute("Fun_On") == false, "lamp server: CyclePhase fallback -> day off")
end

print(("%d checks, %d failed"):format(checks, fails))
if fails > 0 then error("TESTS FAILED") end
