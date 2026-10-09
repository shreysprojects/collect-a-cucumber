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

------------------------------------------------------------------ models (install_models.lua + BuildService.MakeTemplate)
local function Build(key, scale, hitboxCF)
	local data = MODELS[key]
	local model = Instance.new("Model")
	model.Name = key
	local centre = (data.Min + data.Max) / 2
	local parts = {}
	for _, pd in ipairs(data.Parts) do
		local c = pd.CF
		local cf = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		local p = Instance.new("Part")
		p.Name = pd.Name
		if pd.Shape == "Cylinder" then p.Shape = Enum.PartType.Cylinder elseif pd.Shape == "Ball" then p.Shape = Enum.PartType.Ball end
		p.Size = pd.Size * scale
		p.CFrame = CFrame.new(centre + (cf.Position - centre) * scale) * cf.Rotation
		p.Color = Color3.fromHex(pd.Color)
		p.Material = Enum.Material[pd.Material]
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
	model:SetAttribute("Category", "Home")
	local delta = hitboxCF * hitbox.CFrame:Inverse()
	for _, p in ipairs(parts) do p.CFrame = delta * p.CFrame end
	hitbox.CFrame = delta * hitbox.CFrame
	return model
end

local PlaceableBuilds = Instance.new("Folder")
PlaceableBuilds.Name = "PlaceableBuilds"
PlaceableBuilds.Parent = game:GetService("ReplicatedStorage")
local HomeFolder = Instance.new("Folder")
HomeFolder.Name = "Home"
HomeFolder.Parent = PlaceableBuilds
local YAW = CFrame.Angles(0, math.rad(37), 0)

local function Place(key, scale)
	local old = HomeFolder:FindFirstChild(key)
	if old then old:Destroy() end
	local template = Build(key, scale, CFrame.new(0, 500, 0))
	template.Parent = HomeFolder
	local model = Build(key, scale, CFrame.new(60, 3, -20) * YAW)
	model.Parent = workspace
	return model, template
end

------------------------------------------------------------------ server ctx (FunBuildService.NewContext)
local function MakeServerCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		_alive = true, _insts = {}, _cleanups = {}, _states = {}}
	function ctx:Alive() return self._alive end
	function ctx:Connect(sig, fn) return sig:Connect(function(...) if self._alive then fn(...) end end) end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:SetState(k, v) self._states[k] = true model:SetAttribute("Fun_" .. k, v) end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:Fire() end
	function ctx:HumanoidOf(player)
		if not player or player.Dead then return nil end
		return {Health = 100}, {Position = Vector3.new()}
	end
	function ctx:Prompt(part, opts)
		opts = opts or {}
		local parent = part
		if opts.Offset then
			local att = Instance.new("Attachment")
			att.Name = "FunPromptAt"
			att.Position = opts.Offset
			att.Parent = part
			self:Add(att)
			parent = att
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = opts.Name or "FunPrompt"
		prompt.ObjectText = opts.Object or base
		prompt.ActionText = opts.Action or "Use"
		prompt.HoldDuration = opts.Hold or 0
		prompt.MaxActivationDistance = opts.Distance or 10
		prompt.Parent = parent
		self:Add(prompt)
		return prompt
	end
	return ctx
end

local function StopServer(ctx)
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		check(ok, "server cleanup errored: " .. tostring(err))
	end
	for i = #ctx._insts, 1, -1 do ctx._insts[i]:Destroy() end
	for k in pairs(ctx._states) do ctx.Model:SetAttribute("Fun_" .. k, nil) end
end

local function Advance(sec)
	local steps = math.max(1, math.ceil(sec / 0.05))
	for _ = 1, steps do
		MockNow += sec / steps
		MockRunTasks()
	end
end

------------------------------------------------------------------ client ctx (FunBuildClient.NewContext)
local camera = workspace.CurrentCamera
local function MakeCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		_alive = true, _insts = {}, _cleanups = {}, _steps = {}, _everys = {}, StepRange = 180}
	function ctx:Alive() return self._alive end
	function ctx:Connect(sig, fn) return sig:Connect(function(...) if self._alive then fn(...) end end) end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn)
		model:GetAttributeChangedSignal("Fun_" .. k):Connect(function()
			if self._alive then fn(model:GetAttribute("Fun_" .. k)) end
		end)
		fn(model:GetAttribute("Fun_" .. k))
	end
	function ctx:Send() end
	function ctx:CameraDistance() return (camera.CFrame.Position - Kit.Hitbox(model).Position).Magnitude end
	function ctx:Step(fn) table.insert(self._steps, fn) end
	function ctx:Every(_, fn) table.insert(self._everys, fn) end
	function ctx:Sound(parent, id, props) local s = Kit.MakeSound(id, props) s.Parent = parent self:Add(s) return s end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = camera end
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
	check(#ctx._steps <= 1, "at most one ctx:Step per build")
	return ctx
end
local function Everys(ctx)
	for _, fn in ipairs(ctx._everys) do
		local ok, err = pcall(fn)
		check(ok, "Every errored: " .. tostring(err))
	end
end
local frameNo = 0
local function Frames(ctx, n, dt)
	dt = dt or 1 / 60
	for _ = 1, n do
		MockNow += dt
		frameNo += 1
		if frameNo % 30 == 0 then Everys(ctx) end
		for _, fn in ipairs(ctx._steps) do
			local ok, err = pcall(fn, dt, MockNow)
			if not ok then check(false, "Step errored: " .. tostring(err)) return end
		end
		MockRunTasks()
	end
end
local function Stop(ctx)
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		check(ok, "cleanup errored: " .. tostring(err))
	end
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
local function SetCamera(model, dist) rawget(camera, "_p").CFrame = CFrame.new(Kit.Hitbox(model).Position + Vector3.new(0, 0, dist)) end
local NEON, SMOOTH, GLASS = Enum.Material.Neon, Enum.Material.SmoothPlastic, Enum.Material.Glass

------------------------------------------------------------------ Stove: server
do
	local S = load("S_Stove")
	for _, scale in ipairs({1, 1.4}) do
		local model = Place("Stove", scale)
		local sctx = MakeServerCtx(model)
		local ok, err = pcall(S.Server, model, sctx)
		check(ok, "Stove Server() errored: " .. tostring(err))
		check(model:GetAttribute("Fun_On") == false, "Stove Fun_On starts false")
		local prompt = Find(model, "ProximityPrompt", "StovePrompt")
		check(prompt ~= nil, "StovePrompt exists")
		if prompt then
			check(vnear(prompt.Parent.WorldPosition, Kit.Pivot(model, "Controls"), 1e-4), "Stove prompt sits at Pivot_Controls (scale " .. scale .. ")")
			check(prompt.ActionText == "Turn on" and prompt.ObjectText == "Stove", "Stove prompt text")
			check(prompt.MaxActivationDistance >= 10 * scale - 1e-6, "Stove prompt reach grows with scale")
			local plr = {Name = "P1"}
			prompt.Triggered:Fire(plr)
			check(model:GetAttribute("Fun_On") == true and prompt.ActionText == "Turn off", "Stove toggles on")
			Advance(0.1)
			prompt.Triggered:Fire(plr)
			check(model:GetAttribute("Fun_On") == true, "Stove toggle debounced")
			Advance(0.5)
			prompt.Triggered:Fire(plr)
			check(model:GetAttribute("Fun_On") == false and prompt.ActionText == "Turn on", "Stove toggles off")
			Advance(0.5)
			prompt.Triggered:Fire({Dead = true})
			check(model:GetAttribute("Fun_On") == false, "Stove ignores a dead player")
		end
		StopServer(sctx)
		check(model:GetAttribute("Fun_On") == nil, "Stove state cleared on stop")
		model:Destroy()
	end
end

------------------------------------------------------------------ Stove: client
do
	local C = load("C_Stove")
	local scale = 1.4
	local model = Place("Stove", scale)
	SetCamera(model, 20)
	local coils = Kit.Parts(model, "Burner")
	check(#coils == 8, "Stove has 8 coil parts, got " .. #coils)
	local baseColor, baseMat = coils[1].Color, coils[1].Material
	local window, power = Kit.Part(model, "OvenWindow"), Kit.Part(model, "PowerLight")
	local windowColor = window.Color
	local positions = {}
	for _, p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") then positions[p] = p.CFrame end end
	model:SetAttribute("Fun_On", false)
	local ctx = Run(C, model)
	Frames(ctx, 60)
	check(coils[1].Material == baseMat and coils[1].Color == baseColor, "cold coils untouched")
	check(Find(camera, "Part", "StoveFX") ~= nil, "StoveFX host part in the camera")
	local shimmers = FindAll(camera, "ParticleEmitter", "HeatShimmer")
	check(#shimmers == 2, "2 heat-shimmer emitters (the free back burners), got " .. #shimmers)
	local origin = Kit.Origin(model)
	for _, e in ipairs(shimmers) do
		local att = e.Parent
		check(att.Name == "ShimmerBurnerBL" or att.Name == "ShimmerBurnerBR", "shimmer on a free burner: " .. att.Name)
		local coil = Kit.Part(model, att.Name:sub(8))
		if coil then
			local rel = origin:PointToObjectSpace(att.WorldPosition) - origin:PointToObjectSpace(coil.Position)
			check(math.abs(rel.X) < 1e-4 and math.abs(rel.Z) < 1e-4 and rel.Y > 0, "shimmer centred over its coil")
		end
		check(e.Enabled == false, "shimmer off while cold")
	end
	local steam = Find(camera, "ParticleEmitter", "Steam")
	check(steam ~= nil, "kettle steam emitter")
	if steam then
		check(vnear(steam.Parent.WorldPosition, Kit.Pivot(model, "SpoutTip"), 1e-4), "steam at Pivot_SpoutTip")
		local dir = origin:VectorToObjectSpace(steam.Parent.WorldCFrame.UpVector)
		check(dir.X < -0.5 and dir.Y > 0.4 and math.abs(dir.Z) < 1e-4, "steam blows along the spout " .. tostring(dir))
	end
	local pops = Find(camera, "ParticleEmitter", "OilPops")
	local panPart = Find(camera, "Part", "StovePanFX")
	check(pops ~= nil and panPart ~= nil, "pan effects")
	if panPart then check(vnear(panPart.Position, Kit.ToWorld(model, model:GetAttribute("Pivot_PanTop") + Vector3.new(0, 0.06, 0)), 1e-4), "pan fx over Pivot_PanTop") end
	local sizzle = Find(camera, "Sound", "Sizzle")
	check(sizzle ~= nil and sizzle.Looped == true, "looped sizzle sound")
	local lights = FindAll(camera, "PointLight")
	check(#lights == 2, "exactly 2 lights, got " .. #lights)

	--.. on
	model:SetAttribute("Fun_On", true)
	Frames(ctx, 12)
	check(coils[1].Material ~= NEON, "coils still warming at 0.2 s")
	Frames(ctx, 168) -- 3 s on
	for _, c in ipairs(coils) do check(c.Material == NEON, "coil Neon when hot: " .. c.Name) end
	local c = coils[1].Color
	check(c.R > 0.85 and c.G < 0.45 and c.B < 0.25, "coil red-orange " .. tostring(c))
	check(window.Material == NEON and window.Color.R > 0.8, "oven window glows " .. tostring(window.Color))
	check(power.Material == NEON and power.Color.R > 0.9, "power light red")
	for _, e in ipairs(shimmers) do check(e.Enabled, "shimmer on when hot") end
	check(pops and pops.Enabled, "oil pops on")
	check(sizzle and sizzle.IsPlaying, "sizzle plays near a hot pan")
	for _, l in ipairs(lights) do check(l.Enabled and l.Brightness > 0.5, "light on " .. l.Parent.Name) end
	check(steam and steam.Enabled == false, "kettle not steaming yet at 3 s")
	Frames(ctx, 300) -- 8 s on
	check(steam and steam.Enabled, "kettle steams after ~7 s")
	local click = Find(camera, "Sound", "Click")
	check(click and click.IsPlaying, "click on switch")

	--.. far away: asleep
	SetCamera(model, 220)
	Everys(ctx)
	check(pops and not pops.Enabled and sizzle and not sizzle.IsPlaying, "particles + sizzle asleep far away")
	for _, l in ipairs(lights) do check(not l.Enabled, "lights off far away") end
	SetCamera(model, 20)
	Everys(ctx)
	Frames(ctx, 2)
	check(pops and pops.Enabled and sizzle and sizzle.IsPlaying, "awake again near")

	--.. off: cools down
	model:SetAttribute("Fun_On", false)
	Frames(ctx, 60)
	check(coils[1].Material == NEON, "coils still cooling 1 s after off")
	check(power.Material == SMOOTH, "power light off at once")
	Frames(ctx, 200)
	for _, cc in ipairs(coils) do check(cc.Material == baseMat and cc.Color == baseColor, "cooled coil restored: " .. cc.Name) end
	check(window.Material == GLASS and window.Color == windowColor, "window restored")
	check(sizzle and not sizzle.IsPlaying, "sizzle stopped")
	for _, l in ipairs(lights) do check(not l.Enabled, "light off when cold") end
	for _, e in ipairs(shimmers) do check(not e.Enabled, "shimmer off when cold") end

	--.. streamed in while on: hot at once; cleanup restores
	model:SetAttribute("Fun_On", true)
	Frames(ctx, 200)
	Stop(ctx)
	check(coils[1].Material == baseMat and coils[1].Color == baseColor, "cleanup restores the coils")
	check(window.Material == GLASS and power.Material == SMOOTH, "cleanup restores window + power light")
	check(Find(camera, "Part", "StoveFX") == nil and Find(camera, "Part", "StovePanFX") == nil, "fx parts gone after cleanup")
	local ctx2 = Run(C, model)
	Frames(ctx2, 1)
	check(coils[1].Material == NEON and coils[1].Color.R > 0.85, "streams in already hot")
	check(power.Material == NEON, "streams in with the power light on")
	Stop(ctx2)
	local moved = 0
	for p, cf in pairs(positions) do if p.Parent and not vnear(p.CFrame.Position, cf.Position, 1e-9) then moved += 1 end end
	check(moved == 0, "the stove never moves a part")
	print(("Stove client: %d coils, %d shimmers, lights %d"):format(#coils, #shimmers, #lights))
	model:Destroy()
end

------------------------------------------------------------------ SinkCounter: server
do
	local S = load("S_SinkCounter")
	local model = Place("SinkCounter", 1)
	local sctx = MakeServerCtx(model)
	local ok, err = pcall(S.Server, model, sctx)
	check(ok, "SinkCounter Server() errored: " .. tostring(err))
	check(model:GetAttribute("Fun_Tap") == false and model:GetAttribute("Fun_ToastAt") == 0, "sink states start idle")
	local tap = Find(model, "ProximityPrompt", "TapPrompt")
	local toast = Find(model, "ProximityPrompt", "ToastPrompt")
	check(tap ~= nil and toast ~= nil, "both prompts exist")
	if tap and toast then
		check(vnear(tap.Parent.WorldPosition, Kit.Pivot(model, "Tap"), 1e-4), "tap prompt at Pivot_Tap")
		check(vnear(toast.Parent.WorldPosition, Kit.Pivot(model, "Toaster"), 1e-4), "toast prompt at Pivot_Toaster")
		check(tap.ActionText == "Tap on" and toast.ActionText == "Make toast", "prompt texts")
		local plr = {Name = "P1"}
		tap.Triggered:Fire(plr)
		check(model:GetAttribute("Fun_Tap") == true and tap.ActionText == "Tap off", "tap on")
		Advance(60)
		check(model:GetAttribute("Fun_Tap") == true, "tap still running at 60 s")
		Advance(61)
		check(model:GetAttribute("Fun_Tap") == false and tap.ActionText == "Tap on", "tap shuts itself off after 120 s")
		--.. on, off, on: the first run's auto-off must not cut the second run short
		tap.Triggered:Fire(plr)
		Advance(100)
		tap.Triggered:Fire(plr)
		Advance(1)
		tap.Triggered:Fire(plr)
		check(model:GetAttribute("Fun_Tap") == true, "tap on again")
		Advance(25)
		check(model:GetAttribute("Fun_Tap") == true, "old auto-off ignored")
		Advance(100)
		check(model:GetAttribute("Fun_Tap") == false, "new auto-off after 120 s")

		local t0 = MockNow
		toast.Triggered:Fire(plr)
		check(near(model:GetAttribute("Fun_ToastAt"), t0 + 4, 1e-6), "ToastAt = now + 4")
		check(toast.Enabled == true and toast.ActionText == "Toasting...", "toast prompt reads Toasting... and is never disabled")
		Advance(2)
		toast.Triggered:Fire(plr)
		check(near(model:GetAttribute("Fun_ToastAt"), t0 + 4, 1e-6), "a press while toasting is ignored")
		check(toast.ActionText == "Toasting...", "still Toasting... mid-cycle")
		Advance(5)
		check(toast.Enabled == true and toast.ActionText == "Toasting...", "still Toasting... while the toast is up")
		Advance(2.8)
		check(toast.Enabled == true and toast.ActionText == "Make toast", "toast prompt text back after the cycle")
		toast.Triggered:Fire(plr)
		check(near(model:GetAttribute("Fun_ToastAt"), MockNow + 4, 1e-6), "a new cycle starts")
		--.. a new cycle that starts before the old reset task runs must keep "Toasting..." (stale reset ignored)
		local t1 = MockNow
		MockNow = t1 + 9.65 -- past the guard, but the cycle's reset task (due t1 + 9.6) has not run yet
		toast.Triggered:Fire(plr)
		check(near(model:GetAttribute("Fun_ToastAt"), MockNow + 4, 1e-6), "back-to-back cycle starts")
		MockRunTasks() -- now the first cycle's reset runs: it must see a different ToastAt and do nothing
		check(toast.ActionText == "Toasting...", "a stale reset does not relabel a running cycle")
		Advance(9.7)
		check(toast.ActionText == "Make toast", "the second cycle's own reset relabels it")
		check(toast.Enabled == true, "the server never touched Enabled")
		toast.Triggered:Fire({Dead = true})
	end
	StopServer(sctx)
	check(model:GetAttribute("Fun_Tap") == nil and model:GetAttribute("Fun_ToastAt") == nil, "sink states cleared on stop")
	Advance(20) -- a pending re-enable must not error after stop
	model:Destroy()
end

------------------------------------------------------------------ SinkCounter: client
do
	local C = load("C_SinkCounter")
	local scale = 1.25
	local model, template = Place("SinkCounter", scale)
	SetCamera(model, 20)
	model:SetAttribute("Fun_Tap", false)
	model:SetAttribute("Fun_ToastAt", 0)
	local origin = Kit.Origin(model)
	local up = origin.UpVector
	local hitbox, th = Kit.Hitbox(model), Kit.Hitbox(template)
	local function TemplateRest(name)
		return hitbox.CFrame * th.CFrame:ToObjectSpace(template:FindFirstChild(name).CFrame)
	end
	local toast1, crust2, lever = Kit.Part(model, "Toast1"), Kit.Part(model, "Toast2Crust"), Kit.Part(model, "PopLever")
	local slot = Kit.Part(model, "PopSlot1")
	local breadColor, slotColor = toast1.Color, slot.Color
	local rest1, restC2, restLever = TemplateRest("Toast1"), TemplateRest("Toast2Crust"), TemplateRest("PopLever")
	check(vnear(rest1.Position, toast1.Position, 1e-6), "template rest == placed rest")
	toast1.CFrame = rest1 + Vector3.new(0, 0.5, 0) -- a stale pose some earlier run left behind
	local ctx = Run(C, model)
	check(vnear(toast1.Position, rest1.Position, 1e-5), "the run starts from the template pose")
	Frames(ctx, 10)
	local stream, pool = Find(camera, "Part", "SinkStream"), Find(camera, "Part", "SinkPool")
	check(stream ~= nil and pool ~= nil, "stream + pool parts")
	check(stream.Transparency == 1 and pool.Transparency == 1, "no water while the tap is off")

	--.. tap on
	local spout, floor = Kit.Pivot(model, "Spout"), Kit.Pivot(model, "SinkFloor")
	model:SetAttribute("Fun_Tap", true)
	Frames(ctx, 30)
	check(stream.Transparency < 0.5, "stream visible")
	local axis = stream.CFrame.RightVector
	local top = stream.Position - axis * (stream.Size.X / 2)
	local bottom = stream.Position + axis * (stream.Size.X / 2)
	check(vnear(top, spout, 1e-3), "stream starts at Pivot_Spout")
	local drop = (bottom - floor):Dot(up)
	check(drop >= -1e-3 and drop <= 0.2 * scale + 1e-3, ("stream ends on the water (%.3f over the floor)"):format(drop))
	local side = (bottom - floor) - up * drop
	check(side.Magnitude < 1e-3, "stream lands under the spout")
	check(near(stream.Size.Y, 0.13 * scale, 0.02 * scale), "stream width " .. stream.Size.Y)
	Frames(ctx, 420) -- 7.5 s
	check(near(pool.Size.Y, 0.2 * scale, 1e-3), "pool full: " .. pool.Size.Y)
	local poolTop = (pool.Position + up * (pool.Size.Y / 2) - floor):Dot(up)
	check(near(poolTop, 0.2 * scale, 1e-3), "pool surface 0.2 over the floor")
	local a, b = Kit.Pivot(model, "PoolA"), Kit.Pivot(model, "PoolB")
	local mid = (a + b) / 2
	check(near((pool.Position - mid):Dot(origin.RightVector), 0, 1e-3) and near((pool.Position - mid):Dot(origin.LookVector), 0, 1e-3), "pool centred in the basin")
	check(near(pool.Size.X, math.abs(origin:PointToObjectSpace(a).X - origin:PointToObjectSpace(b).X), 1e-3), "pool width = basin")
	bottom = stream.Position + stream.CFrame.RightVector * (stream.Size.X / 2)
	check(near((bottom - floor):Dot(up), 0.2 * scale, 1e-3), "stream now ends on the pool surface")
	local spray = Find(camera, "ParticleEmitter", "Spray")
	local loop = Find(camera, "Sound", "WaterLoop")
	check(spray and spray.Enabled, "splash on")
	check(spray and near((spray.Parent.WorldPosition - floor):Dot(up), (0.2 + 0.02) * scale, 1e-3), "splash rides the pool surface")
	check(loop and loop.IsPlaying and loop.Looped, "water loop playing near")
	SetCamera(model, 200)
	Everys(ctx)
	check(loop and not loop.IsPlaying and spray and not spray.Enabled, "water asleep far away")
	SetCamera(model, 20)
	Everys(ctx)

	--.. tap off
	model:SetAttribute("Fun_Tap", false)
	Frames(ctx, 30)
	check(stream.Transparency == 1, "stream gone 0.5 s after the tap closes")
	Frames(ctx, 240)
	check(pool.Transparency == 1, "pool drained")
	check(loop and not loop.IsPlaying and spray and not spray.Enabled, "splash + loop off")

	--.. toast cycle
	local popAt = MockNow + 4
	model:SetAttribute("Fun_ToastAt", popAt)
	local click = Find(camera, "Sound", "Click")
	check(click and click.IsPlaying, "lever click")
	Frames(ctx, 30) -- 0.5 s in
	local function Off(part, restCF) return (part.Position - restCF.Position):Dot(up) / scale end
	check(near(Off(lever, restLever), -0.3, 1e-3), "lever down 0.3: " .. Off(lever, restLever))
	check(near(Off(toast1, rest1), -0.14, 1e-3), "toast sinks 0.14: " .. Off(toast1, rest1))
	Frames(ctx, 90) -- 2 s in
	check(slot.Material == NEON, "slots glow while toasting")
	local smoke = Find(camera, "ParticleEmitter", "ToastSmoke")
	check(smoke and smoke.Enabled, "toast smoke near the end")
	local pop, ding = Find(camera, "Sound", "ToasterPop"), Find(camera, "Sound", "Ding")
	check(pop and not pop.IsPlaying, "no pop before the time")
	while MockNow < popAt + 0.5 do Frames(ctx, 1) end
	check(pop and pop.IsPlaying and ding and ding.IsPlaying, "pop + ding at ToastAt")
	check(near(Off(toast1, rest1), 0.8, 1e-3) and near(Off(crust2, restC2), 0.8, 1e-3), "toast up 0.8: " .. Off(toast1, rest1))
	check(near(Off(lever, restLever), 0, 1e-3), "lever back up")
	check(toast1.Color.R < breadColor.R - 0.05, "toast is golden")
	local maxOff = 0
	while MockNow < popAt + 5.8 do
		Frames(ctx, 1)
		maxOff = math.max(maxOff, Off(toast1, rest1))
	end
	check(maxOff <= 0.8 + 1e-3, "no overshoot after settling")
	check(near(Off(toast1, rest1), 0, 1e-3), "toast back down after 5 s")
	while MockNow < popAt + 8 do Frames(ctx, 1) end
	check(vnear(toast1.Position, rest1.Position, 1e-5) and toast1.Color == breadColor, "toast at rest, bread colour again")
	check(slot.Material ~= NEON and slot.Color == slotColor, "slots cold again")

	--.. streamed in mid-pop: posed at once, no late sounds; cleanup mid-pop restores
	Stop(ctx)
	model:SetAttribute("Fun_ToastAt", MockNow - 1)
	local ctx2 = Run(C, model)
	Frames(ctx2, 3)
	local pop2 = Find(camera, "Sound", "ToasterPop")
	check(near(Off(toast1, rest1), 0.8, 1e-3), "late joiner sees the toast up")
	check(pop2 and not pop2.IsPlaying, "late joiner hears no pop")
	Stop(ctx2)
	check(vnear(toast1.Position, rest1.Position, 1e-5) and toast1.Color == breadColor, "cleanup mid-pop restores the toast")
	check(vnear(lever.Position, restLever.Position, 1e-5), "cleanup restores the lever")
	check(Find(camera, "Part", "SinkStream") == nil and Find(camera, "Part", "SinkFX") == nil, "local parts gone after cleanup")

	--.. streamed in with the tap running: full stream + pool at once
	model:SetAttribute("Fun_Tap", true)
	model:SetAttribute("Fun_ToastAt", 0)
	local ctx3 = Run(C, model)
	Frames(ctx3, 1)
	local stream3, pool3 = Find(camera, "Part", "SinkStream"), Find(camera, "Part", "SinkPool")
	check(stream3 and stream3.Transparency < 0.5 and pool3 and near(pool3.Size.Y, 0.2 * scale, 1e-3), "streams in with water running")
	Stop(ctx3)
	model:Destroy()
end

print(("HomeKitchenB tests: %d checks, %d failed"):format(checks, fails))
