-- Drives the real behaviour modules (SERVER_GC, CLIENT_GC, SERVER_NS, CLIENT_NS) through a lifecycle on mocks.
local OWNER, OTHER = 1001, 2002
local function hex(h) return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)) end
local failures = 0
local function check(cond, msg)
	if cond then print("  ok   " .. msg) else failures += 1; print("  FAIL " .. msg) end
end

--.. a placed build: parts of the dump (optionally only one variant prefix), hitbox, attributes, scaled + placed
local function MakeBuild(dump, key, scale, place, prefix, pivots)
	local model = Instance.new("Model")
	model.Name = key
	local lo, hi = Vector3.new(1e9, 1e9, 1e9), Vector3.new(-1e9, -1e9, -1e9)
	local rows = {}
	for _, r in ipairs(dump) do
		if not prefix or r[1]:sub(1, #prefix) == prefix then
			table.insert(rows, r)
			local c, s = Vector3.new(r[2], r[3], r[4]), Vector3.new(r[5], r[6], r[7])
			lo = Vector3.new(math.min(lo.X, c.X - s.X / 2), math.min(lo.Y, c.Y - s.Y / 2), math.min(lo.Z, c.Z - s.Z / 2))
			hi = Vector3.new(math.max(hi.X, c.X + s.X / 2), math.max(hi.Y, c.Y + s.Y / 2), math.max(hi.Z, c.Z + s.Z / 2))
		end
	end
	local centre = (lo + hi) / 2
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (hi - lo) * scale
	hitbox.CFrame = place * CFrame.new(centre * scale) -- placed so the authored origin lands on `place`
	hitbox.Parent = model
	rawset(model, "PrimaryPart", hitbox)
	for _, r in ipairs(rows) do
		local p = Instance.new("MeshPart")
		p.Name = r[1]
		p.Size = Vector3.new(r[5], r[6], r[7]) * scale
		p.CFrame = place * CFrame.new(Vector3.new(r[2], r[3], r[4]) * scale)
		p.Material = "Enum.Material." .. r[8]
		p.Color = hex(r[9])
		p.Parent = model
	end
	model:SetAttribute("BuildKey", key)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("AuthoredCentre", centre)
	model:SetAttribute("Owner", OWNER)
	model:SetAttribute("PlotX", 3)
	model:SetAttribute("PlotZ", -2)
	for k, v in pairs(pivots or {}) do model:SetAttribute("Pivot_" .. k, v) end
	model.Parent = workspace
	return model
end

local function Split(key)
	local base, letter = key:match("^(.-)_(%u)$")
	if base then return base, letter end
	return key, nil
end

local function ServerCtx(model)
	local ctx = {Model = model, Key = model:GetAttribute("BuildKey"), Scale = model:GetAttribute("Scale"), _alive = true, _conns = {}, _insts = {}, _cleanups = {}, Fired = {}}
	ctx.Base, ctx.Variant = Split(ctx.Key)
	local folder = Instance.new("Folder")
	folder.Parent = workspace
	ctx.Folder = folder
	function ctx:Alive() return self._alive and model.Parent ~= nil end
	function ctx:Connect(sig, fn) local c = sig:Connect(fn); table.insert(self._conns, c); return c end
	function ctx:Add(i) table.insert(self._insts, i); return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:SetState(k, v) model:SetAttribute("Fun_" .. k, v) end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:Fire(a, p) table.insert(self.Fired, {a, p}) end
	function ctx:IsOwner(player) return player and player.UserId == model:GetAttribute("Owner") end
	function ctx:Near() return true end
	function ctx:Prompt(part, opts)
		local p = Instance.new("ProximityPrompt")
		p.Name = opts.Name or "FunPrompt"
		p.ActionText = opts.Action
		p.ObjectText = opts.Object or "?"
		p.KeyboardKeyCode = opts.Key or "Enum.KeyCode.E"
		p.MaxActivationDistance = opts.Distance or 10
		p.Parent = part
		self:Add(p)
		return p
	end
	function ctx:Part(props)
		local p = Instance.new("Part")
		for k, v in pairs(props or {}) do p[k] = v end
		p.Parent = folder
		self:Add(p)
		return p
	end
	function ctx:Stop()
		self._alive = false
		for _, f in ipairs(self._cleanups) do f() end
		for _, c in ipairs(self._conns) do c:Disconnect() end
		for i = #self._insts, 1, -1 do self._insts[i]:Destroy() end
		folder:Destroy()
	end
	return ctx
end

local function ClientCtx(model, localUser, mod)
	local ctx = {Model = model, Key = model:GetAttribute("BuildKey"), Scale = model:GetAttribute("Scale"), _alive = true, _conns = {}, _insts = {}, _cleanups = {}, _steps = {}, _every = {}}
	ctx.Base, ctx.Variant = Split(ctx.Key)
	ctx.StepRange = mod.StepRange or 180
	function ctx:Alive() return self._alive and model.Parent ~= nil end
	function ctx:Connect(sig, fn) local c = sig:Connect(fn); table.insert(self._conns, c); return c end
	function ctx:Add(i) table.insert(self._insts, i); return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn)
		self:Connect(model:GetAttributeChangedSignal("Fun_" .. k), function() fn(model:GetAttribute("Fun_" .. k)) end)
		task.spawn(fn, model:GetAttribute("Fun_" .. k))
	end
	function ctx:Send() end
	function ctx:Step(fn) table.insert(self._steps, fn) end
	function ctx:Every(_, fn) table.insert(self._every, fn) end
	function ctx:Sound(parent, id, props)
		assert(id ~= nil, "ctx:Sound with a nil sound id")
		local s = Instance.new("Sound")
		s.SoundId = id
		for k, v in pairs(props or {}) do s[k] = v end
		s.Parent = parent
		self:Add(s)
		return s
	end
	function ctx:IsOwner() return localUser == model:GetAttribute("Owner") end
	ctx._cam = 25
	function ctx:CameraDistance() return self._cam end
	function ctx:LocalCharacter() return nil end
	function ctx:Near() return false end
	function ctx:Frames(n, dt)
		for _ = 1, n do
			NOW += dt
			if self:CameraDistance() <= self.StepRange then -- the framework's Step sleeps past StepRange
				for _, f in ipairs(self._steps) do f(dt, NOW) end
			end
		end
		for _, f in ipairs(self._every) do f() end
	end
	function ctx:Stop()
		self._alive = false
		for _, f in ipairs(self._cleanups) do f() end
		for _, c in ipairs(self._conns) do c:Disconnect() end
		for i = #self._insts, 1, -1 do self._insts[i]:Destroy() end
	end
	assert(#ctx._steps <= 1)
	return ctx
end

local function Run(mod, model, ctx, isClient)
	local result = (isClient and mod.Client or mod.Server)(model, ctx)
	if type(result) == "function" then ctx:OnCleanup(result) end
end

local function count(parent, pred)
	local n = 0
	for _, d in ipairs(parent:GetDescendants()) do if pred(d) then n += 1 end end
	return n
end
local owner, other = {UserId = OWNER, Name = "Cucumbers"}, {UserId = OTHER, Name = "Guest"}

--..GlassCase..--
print("GlassCase")
do
	local place = CFrame.new(120, 4, -60) * CFrame.Angles(0, math.rad(90), 0)
	local model = MakeBuild(PARTS.GlassCase, "GlassCase", 1.25, place, nil, {DisplayPoint = Vector3.new(0, 3.05, 0)})
	local panes = model:FindFirstChild("GlassPanes")
	local sctx = ServerCtx(model)
	Run(SERVER_GC, model, sctx, false)
	check(panes.CanCollide == false and model:FindFirstChild("LightBeam").CanCollide == false, "panes + beam non-colliding")
	check(model:GetAttribute("Fun_Design") == 1, "Design starts at 1")
	local plate = sctx.Folder:FindFirstChild("TrophyNameplate")
	local title = plate and plate:FindFirstChild("Title", true)
	check(title and title.Text == "Cucumbers' Trophy", "nameplate text: " .. tostring(title and title.Text))
	check(plate and (plate.Position - place * (Vector3.new(0, 0.53, -1.48) * 1.25)).Magnitude < 1e-6, "nameplate at the plinth front")
	local admire, change = model:FindFirstChild("AdmirePrompt", true), model:FindFirstChild("ChangeTrophyPrompt", true)
	check(admire and change, "two prompts")

	local cctx = ClientCtx(model, OTHER, CLIENT_GC)
	Run(CLIENT_GC, model, cctx, true)
	check(change.MaxActivationDistance == 0, "Change prompt out of reach for a visitor")
	check(admire.MaxActivationDistance == 10, "Admire prompt reachable for a visitor")
	check(panes.Material == "Enum.Material.SmoothPlastic", "panes drawn as SmoothPlastic on the client")
	local fx = nil
	for _, c in ipairs(workspace:GetChildren()) do if c.Name == "FunFX_GlassCase" then fx = c end end
	check(fx ~= nil, "client FX folder")
	local function trophyParts() return count(fx, function(d) return d.Name == "Trophy" and not rawget(d, "_destroyed") end) end
	check(trophyParts() == #CLIENT_GC.TrophySpecs(1), "design 1 built: " .. trophyParts() .. " parts")
	cctx:Frames(90, 1 / 60)
	--.. the trophy floats over the display point
	local display = place * (Vector3.new(0, 3.05, 0) * 1.25)
	local lowest = math.huge
	for _, d in ipairs(fx:GetDescendants()) do if d.Name == "Trophy" then lowest = math.min(lowest, d.Position.Y - display.Y) end end
	check(lowest > 0 and lowest < 0.4, ("trophy part centres start %.3f studs above the display point"):format(lowest))

	change.Triggered:Fire(other)
	check(model:GetAttribute("Fun_Design") == 1, "visitor cannot change the trophy")
	admire.Triggered:Fire(other)
	check(#sctx.Fired == 1 and sctx.Fired[1][1] == "Admire", "Admire fired to clients")
	CLIENT_GC.OnEvent(model, "Admire", sctx.Fired[1][2], cctx)
	local neonSeen = false
	for _ = 1, 40 do
		cctx:Frames(1, 1 / 60)
		for _, d in ipairs(fx:GetDescendants()) do if d.Name == "Trophy" and d.Material == "Enum.Material.Neon" then neonSeen = true end end
	end
	check(neonSeen, "shine sweep turns parts Neon")
	cctx:Frames(60, 1 / 60)
	local stillNeon = count(fx, function(d) return d.Name == "Trophy" and d.Material == "Enum.Material.Neon" end)
	check(stillNeon == 0, "shine finished, looks restored")
	admire.Triggered:Fire(other)
	check(#sctx.Fired == 1, "admire cooldown")

	for d = 2, 5 do
		change.Triggered:Fire(owner)
		check(model:GetAttribute("Fun_Design") == d, "owner changes the trophy to " .. d)
		local t0 = os.clock()
		while os.clock() - t0 < 0.5 do cctx:Frames(1, 1 / 60) end -- pop-in / pop-out run on os.clock
		check(trophyParts() == #CLIENT_GC.TrophySpecs(d), ("design %d on show alone: %d parts"):format(d, trophyParts()))
		local t1 = os.clock()
		while os.clock() - t1 < 0.4 do end -- the change cooldown is on os.clock too
	end
	change.Triggered:Fire(owner)
	check(model:GetAttribute("Fun_Design") == 1, "wraps back to 1")
	do local t0 = os.clock() while os.clock() - t0 < 0.5 do cctx:Frames(1, 1 / 60) end end
	local before = trophyParts()
	model:SetAttribute("Fun_Design", nil)
	cctx:Frames(5, 1 / 60)
	check(trophyParts() == before, "a cleared Design (server restarting) keeps the trophy on show")

	--.. fix pass: nothing piles up or sticks while the Step sleeps (camera out of StepRange)
	local function specsOf(d) return #CLIENT_GC.TrophySpecs(d) end
	local sizesFull = function()
		local ok = true
		for _, p in ipairs(fx:GetDescendants()) do
			if p.Name == "Trophy" and p.Size.Magnitude < 0.02 then ok = false end
		end
		return ok
	end
	cctx._cam = 500
	for i = 1, 60 do
		model:SetAttribute("Fun_Design", i % 5 + 1)
		cctx:Frames(1, 1 / 60)
	end
	local lastD = 60 % 5 + 1
	check(trophyParts() == specsOf(lastD), ("far: 60 changes leave one trophy (%d parts, want %d)"):format(trophyParts(), specsOf(lastD)))
	check(sizesFull(), "far: the swapped-in trophy is full size (no pop)")
	check(#cctx._insts < 20, "far: the ctx list does not grow with trophy parts (" .. #cctx._insts .. " entries)")
	cctx._cam = 25
	model:SetAttribute("Fun_Design", 1)
	model:SetAttribute("Fun_Design", 2)
	model:SetAttribute("Fun_Design", 3)
	check(trophyParts() == specsOf(3) + specsOf(2), ("near: 3 rapid changes keep 2 trophies (%d parts, want %d)"):format(trophyParts(), specsOf(3) + specsOf(2)))
	cctx:Frames(1, 1 / 60)
	cctx._cam = 500
	cctx:Frames(1, 1 / 60)
	check(trophyParts() == specsOf(3) and sizesFull(), "camera leaves mid-pop: the old trophy goes, the new one is full size")
	cctx._cam = 25
	CLIENT_GC.OnEvent(model, "Admire", {At = NOW}, cctx)
	for _ = 1, 25 do cctx:Frames(1, 1 / 60) end
	local neonMid = count(fx, function(d) return d.Name == "Trophy" and d.Material == "Enum.Material.Neon" end)
	check(neonMid > 0, "mid-shine: " .. neonMid .. " parts white Neon")
	cctx._cam = 500
	cctx:Frames(1, 1 / 60)
	local neonAfter = count(fx, function(d) return d.Name == "Trophy" and d.Material == "Enum.Material.Neon" end)
	local glowLight = fx:FindFirstChild("TrophySparkles"):FindFirstChildOfClass("PointLight")
	check(neonAfter == 0 and math.abs(glowLight.Brightness - 0.45) < 1e-6, ("camera leaves mid-shine: looks + glow restored (%d Neon, glow %.2f)"):format(neonAfter, glowLight.Brightness))
	cctx._cam = 25
	cctx:Frames(60, 1 / 60)

	local ocl = ClientCtx(model, OWNER, CLIENT_GC)
	local changeBefore = change.MaxActivationDistance
	check(changeBefore == 0, "(prompt still 0 from the visitor's client in this shared mock)")

	cctx:Stop()
	check(panes.Material == "Enum.Material.Glass", "panes Glass again after the client stops")
	check(trophyParts() == 0, "trophy parts gone")
	sctx:Stop()
	check(panes.CanCollide == true, "panes collide again after the server stops")
	local _ = ocl
end

--..NeonSign..--
for _, letter in ipairs({"A", "B", "C"}) do
	print("NeonSign_" .. letter)
	local place = CFrame.new(-40, 4, 30) * CFrame.Angles(0, math.rad(-90), 0)
	local model = MakeBuild(PARTS.NeonSign, "NeonSign_" .. letter, 1.5, place, letter .. "_")
	local sctx = ServerCtx(model)
	Run(SERVER_NS, model, sctx, false)
	check(model:GetAttribute("Fun_On") == true, "On by default")
	local prompt = model:FindFirstChild("NeonSwitchPrompt", true)
	check(prompt and prompt.Parent.Name == letter .. "_Panel", "switch prompt on the panel")
	local neonParts = {}
	for _, p in ipairs(model:GetChildren()) do
		if p.Material == "Enum.Material.Neon" then table.insert(neonParts, {p, p.Color}) end
	end
	local cctx = ClientCtx(model, OTHER, CLIENT_NS)
	Run(CLIENT_NS, model, cctx, true)
	check(prompt.MaxActivationDistance == 0, "switch out of reach for a visitor")
	local fx = nil
	for _, c in ipairs(workspace:GetChildren()) do if c.Name == "FunFX_NeonSign_" .. letter then fx = c end end
	local bulbs = count(fx, function(d) return d.Name == "NeonBulb" end)
	local chev = count(fx, function(d) return d.Name == "NeonChevron" end)
	local want = ({A = {0, 0}, B = {10, 4}, C = {12, 0}})[letter]
	check(bulbs == want[1] and chev == want[2], ("overlays: %d bulbs, %d chevron arms"):format(bulbs, chev))
	--.. run 20 s of show; record how often things change
	local lit, changes, last = {}, 0, {}
	for _ = 1, 20 * 30 do
		cctx:Frames(1, 1 / 30)
		for _, d in ipairs(fx:GetChildren()) do
			if d.Name == "NeonBulb" or d.Name == "NeonChevron" then
				if d.Material == "Enum.Material.Neon" then lit[d] = true end
				if last[d] ~= d.Material then changes += 1; last[d] = d.Material end
			end
		end
	end
	local nlit = 0
	for _ in pairs(lit) do nlit += 1 end
	if letter ~= "A" then check(nlit == bulbs + chev, ("every overlay lit at some point (%d/%d), %d material flips"):format(nlit, bulbs + chev, changes)) end
	if letter == "A" then
		local text = model:FindFirstChild("A_Text")
		local zap = fx:FindFirstChild("Buzz", true)
		check(zap and (rawget(zap, "_plays") or 0) > 0, "flicker bursts buzzed " .. tostring(zap and rawget(zap, "_plays")) .. " times in 20 s")
		check(text.Material == "Enum.Material.Neon" or text.Material == "Enum.Material.SmoothPlastic", "text material valid")
		--.. fix pass: the camera leaves during a stutter at level 0 -> the letters must not stay dark
		local dark = false
		for _ = 1, 120 * 30 do
			cctx:Frames(1, 1 / 30)
			if text.Material == "Enum.Material.SmoothPlastic" then dark = true break end
		end
		check(dark, "found a stutter frame with the OPEN letters dark")
		cctx._cam = 500
		cctx:Frames(1, 1 / 30)
		local border = model:FindFirstChild("A_Border")
		local lightA = fx:FindFirstChild("NeonGlow"):FindFirstChildOfClass("PointLight")
		check(text.Material == "Enum.Material.Neon" and border.Material == "Enum.Material.Neon" and math.abs(lightA.Brightness - 1.6) < 0.03,
			("camera leaves mid-stutter: letters + border lit, light %.2f (night)"):format(lightA.Brightness))
		local r0 = text.Color.R
		cctx:Frames(1, 1 / 30)
		check(text.Color.R == r0, "far: stays at rest")
		cctx._cam = 25
	end
	if letter == "B" then
		local host = model:FindFirstChild("B_Bulbs")
		check(host.Material == "Enum.Material.SmoothPlastic", "merged bulbs dark under the overlay balls")
		--.. the tip-side chevron sits at the -X side of the sign's arrow (in the sign's own frame)
		local arrow = model:FindFirstChild("B_Arrow")
		local xs = {}
		for _, d in ipairs(fx:GetChildren()) do
			if d.Name == "NeonChevron" then
				local rel = place:Inverse() * d.Position
				table.insert(xs, rel.X / 1.5)
			end
		end
		table.sort(xs)
		check(math.abs(xs[1] - 1.11) < 0.05 and math.abs(xs[#xs] - 3.49) < 0.05, ("chevron centres at authored x %.2f .. %.2f (arrow %.2f)"):format(xs[1], xs[#xs], (place:Inverse() * arrow.Position).X / 1.5))
	end
	--.. switch off (owner), then on
	prompt.Triggered:Fire(other)
	check(model:GetAttribute("Fun_On") == true, "visitor cannot switch it off")
	prompt.Triggered:Fire(owner)
	check(model:GetAttribute("Fun_On") == false and prompt.ActionText == "Switch on", "owner switches it off")
	local allOff = true
	for _, e in ipairs(neonParts) do if e[1].Material ~= "Enum.Material.SmoothPlastic" then allOff = false end end
	for _, d in ipairs(fx:GetChildren()) do if (d.Name == "NeonBulb" or d.Name == "NeonChevron") and d.Material ~= "Enum.Material.SmoothPlastic" then allOff = false end end
	check(allOff, "off: every neon part + overlay SmoothPlastic")
	local light = fx:FindFirstChildOfClass("Part") and fx:FindFirstChild("NeonGlow"):FindFirstChildOfClass("PointLight")
	check(light and light.Enabled == false, "off: light out")
	cctx:Frames(30, 1 / 30)
	local t1 = os.clock()
	while os.clock() - t1 < 0.35 do end
	prompt.Triggered:Fire(owner)
	check(model:GetAttribute("Fun_On") == true, "owner switches it on again")
	local t2 = os.clock()
	while os.clock() - t2 < 0.6 do cctx:Frames(1, 1 / 60) end
	local steadyOk = true
	for _, e in ipairs(neonParts) do
		local n = e[1].Name
		if n == letter .. "_Text" and letter ~= "A" and e[1].Material ~= "Enum.Material.Neon" then steadyOk = false end
	end
	check(steadyOk, "on: the text glows again after the warm-up")
	local glow = fx:FindFirstChild("NeonGlow")
	local sw = glow:FindFirstChild("Switch")
	local plays = rawget(sw, "_plays") or 0
	model:SetAttribute("Fun_On", nil)
	check((rawget(sw, "_plays") or 0) == plays and glow:FindFirstChildOfClass("PointLight").Enabled, "a cleared On (server restarting) changes nothing")
	cctx:Stop()
	local restored = true
	for _, e in ipairs(neonParts) do
		if e[1].Material ~= "Enum.Material.Neon" or e[1].Color.R ~= e[2].R or e[1].Color.G ~= e[2].G then restored = false end
	end
	check(restored, "cleanup restored every neon part's Material + Color")
	check(fx.Parent == nil, "overlays gone")
	sctx:Stop()
end

print(failures == 0 and "ALL PASSED" or ("FAILURES: " .. failures))
