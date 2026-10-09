--!nolint
-- CucumberIdleFX - constant, purely aesthetic idle animation for the cucumber set.
--
-- Install as a Script with RunContext = Client (see bake_fx.lua).  It runs on every
-- client, animates anchored parts LOCALLY, and therefore costs zero network traffic and
-- never touches the server's copy of anything.
--
-- It is entirely attribute-driven: a model animates if and only if it carries an
-- `IdleMotion` string attribute holding a JSON spec.  Nothing is hard-coded per model, so
-- copying a model into another place carries its animation with it.
--
--   IdleMotion = {"motion":[ <entry>, ... ]}
--
-- Every entry has `kind` and `target`, where target is "model" (all parts) or an array of
-- exact part names.  Supported kinds and their fields:
--
--   bob      amp (studs), period (s), phase (0-1)            Y offset, sinusoidal
--   drift    amp, period, phase, axis ("X"|"Z")              horizontal offset
--   sway     deg, period, phase, axis ("X"|"Z")              lean, pivoting at the model base
--   rock     deg, period, phase, axis ("X"|"Y"|"Z")          rotation about the group's own centre
--   spin     speed (deg/s, may be negative), axis            continuous rotation about the group centre
--   twirl    speed (deg/s, may be negative)                   continuous rotation about the MODEL's Y axis
--   orbit    speed (deg/s)                                   revolve position about the model Y axis,
--                                                            keeping each part's own orientation
--   breathe  scale (max multiplier), period, phase           uniform Size+offset scale of the group
--   pulse    prop, from, to, period, phase                   sinusoidal property animation
--   flicker  prop, base, amp, hz                             smooth pseudo-random property walk
--
-- `pulse`/`flicker` route by property name: Transparency hits the parts themselves,
-- Brightness/Range hit Lights inside them, Rate hits ParticleEmitters, Width0/Width1 hit
-- Beams.  Amplitudes are deliberately small - this is an aesthetic, not an event.

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local TAU = math.pi * 2

local tracked = {}

local function axisVector(a)
	if a == "X" then return Vector3.xAxis end
	if a == "Z" then return Vector3.zAxis end
	return Vector3.yAxis
end

-- rotation of `deg` about `axis`, applied around the model-space point `pivot`
local function rotAbout(pivot, axis, deg)
	local r = CFrame.fromAxisAngle(axisVector(axis), math.rad(deg))
	return CFrame.new(pivot) * r * CFrame.new(-pivot)
end

local function collect(model, target)
	local want
	if typeof(target) == "table" then
		want = {}
		for _, n in ipairs(target) do
			want[n] = true
		end
	end
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (want == nil or want[d.Name]) then
			out[#out + 1] = d
		end
	end
	return out
end

local function centroid(parts, offsets)
	local sum = Vector3.zero
	for _, p in ipairs(parts) do
		sum += offsets[p].Position
	end
	return #parts > 0 and (sum / #parts) or Vector3.zero
end

local function descendantsOfClass(parts, class)
	local out = {}
	for _, p in ipairs(parts) do
		if p:IsA(class) then
			out[#out + 1] = p
		end
		for _, d in ipairs(p:GetDescendants()) do
			if d:IsA(class) then
				out[#out + 1] = d
			end
		end
	end
	return out
end

-- which instances a pulse/flicker property applies to
local PROP_ROUTE = {
	Transparency = function(parts) return parts end,
	Brightness = function(parts) return descendantsOfClass(parts, "Light") end,
	Range = function(parts) return descendantsOfClass(parts, "Light") end,
	Rate = function(parts) return descendantsOfClass(parts, "ParticleEmitter") end,
	Width0 = function(parts) return descendantsOfClass(parts, "Beam") end,
	Width1 = function(parts) return descendantsOfClass(parts, "Beam") end,
}

local function prepare(model)
	local raw = model:GetAttribute("IdleMotion")
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, spec = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(spec) ~= "table" or type(spec.motion) ~= "table" then
		warn("[CucumberIdleFX] bad IdleMotion on " .. model:GetFullName())
		return nil
	end

	local origin = model:GetPivot()
	local inv = origin:Inverse()
	local parts, offsets, sizes = {}, {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[#parts + 1] = d
			offsets[d] = inv * d.CFrame
			sizes[d] = d.Size
		end
	end
	if #parts == 0 then
		return nil
	end

	local entries = {}
	for _, e in ipairs(spec.motion) do
		local group = collect(model, e.target == "model" and nil or e.target)
		if #group > 0 then
			local route = e.prop and PROP_ROUTE[e.prop]
			entries[#entries + 1] = {
				kind = e.kind,
				group = group,
				inGroup = (function()
					local s = {}
					for _, p in ipairs(group) do s[p] = true end
					return s
				end)(),
				centre = centroid(group, offsets),
				targets = route and route(group) or nil,
				bases = nil,
				e = e,
			}
			-- cache the starting value of any pulsed/flickered property
			local last = entries[#entries]
			if last.targets then
				last.bases = {}
				for _, t in ipairs(last.targets) do
					local okv, v = pcall(function() return t[e.prop] end)
					last.bases[t] = okv and v or 0
				end
			end
		end
	end
	if #entries == 0 then
		return nil
	end

	return {
		model = model,
		origin = origin,
		parts = parts,
		offsets = offsets,
		sizes = sizes,
		entries = entries,
		seed = (#model.Name * 7919) % 1000 / 1000.0, -- stable per-model phase offset
	}
end

local function wave(period, phase, seed, t)
	period = (period and period > 0.01) and period or 3.0
	return math.sin(TAU * (t / period + (phase or 0) + seed))
end

-- a few incommensurate sines read as a soft random walk without needing an RNG
local function noise(t, hz, seed)
	hz = hz or 1.0
	return (math.sin(TAU * (t * hz + seed))
		+ math.sin(TAU * (t * hz * 1.713 + seed * 2.3)) * 0.6
		+ math.sin(TAU * (t * hz * 2.917 + seed * 4.1)) * 0.35) / 1.95
end

local function step(rec, t)
	-- accumulate a model-space transform per part, plus optional uniform scale
	local xf, scale = {}, {}
	for _, p in ipairs(rec.parts) do
		xf[p] = CFrame.identity
		scale[p] = nil
	end

	for _, en in ipairs(rec.entries) do
		local e = en.e
		local k = en.kind

		if k == "bob" then
			local d = wave(e.period, e.phase, rec.seed, t) * (e.amp or 0.06)
			local m = CFrame.new(0, d, 0)
			for _, p in ipairs(en.group) do xf[p] = m * xf[p] end

		elseif k == "drift" then
			local d = wave(e.period, e.phase, rec.seed, t) * (e.amp or 0.06)
			local m = (e.axis == "Z") and CFrame.new(0, 0, d) or CFrame.new(d, 0, 0)
			for _, p in ipairs(en.group) do xf[p] = m * xf[p] end

		elseif k == "sway" then
			-- pivots at the model base, so the footprint stays put
			local d = wave(e.period, e.phase, rec.seed, t) * (e.deg or 3)
			local m = rotAbout(Vector3.zero, e.axis or "X", d)
			for _, p in ipairs(en.group) do xf[p] = m * xf[p] end

		elseif k == "rock" then
			local d = wave(e.period, e.phase, rec.seed, t) * (e.deg or 3)
			local m = rotAbout(en.centre, e.axis or "Z", d)
			for _, p in ipairs(en.group) do xf[p] = m * xf[p] end

		elseif k == "spin" then
			local m = rotAbout(en.centre, e.axis or "Y", (e.speed or 15) * t)
			for _, p in ipairs(en.group) do xf[p] = m * xf[p] end

		elseif k == "twirl" then
			-- Like spin, but about the MODEL's own vertical axis instead of the group's
			-- centroid.  Use this whenever one part contains several things at different
			-- offsets - e.g. a "Discs" MeshPart holding a big disc on the mast and two
			-- smaller ones on side forks.  Spinning that about its centroid swings the
			-- whole group around a meaningless midpoint and throws the footprint out;
			-- twirling it about the mast makes the on-axis piece rotate in place and the
			-- off-axis pieces sweep around the trunk, which is what a turntable looks like.
			local m = rotAbout(Vector3.zero, "Y", (e.speed or 12) * t)
			for _, p in ipairs(en.group) do xf[p] = m * xf[p] end

		elseif k == "orbit" then
			-- position revolves about the model's Y axis; orientation is left alone
			local r = CFrame.fromAxisAngle(Vector3.yAxis, math.rad((e.speed or 15) * t))
			for _, p in ipairs(en.group) do
				local base = rec.offsets[p]
				local moved = r * base.Position
				xf[p] = CFrame.new(moved - base.Position) * xf[p]
			end

		elseif k == "breathe" then
			local s = 1 + (((e.scale or 1.04) - 1) * 0.5)
				* (1 + wave(e.period, e.phase, rec.seed, t))
			for _, p in ipairs(en.group) do
				scale[p] = (scale[p] or 1) * s
				local off = rec.offsets[p].Position - en.centre
				xf[p] = CFrame.new(off * (s - 1)) * xf[p]
			end

		elseif k == "pulse" and en.targets then
			local u = (wave(e.period, e.phase, rec.seed, t) + 1) * 0.5
			local v = (e.from or 0) + ((e.to or 1) - (e.from or 0)) * u
			for _, tgt in ipairs(en.targets) do
				pcall(function() tgt[e.prop] = v end)
			end

		elseif k == "flicker" and en.targets then
			local v = (e.base or 1) + noise(t, e.hz, rec.seed) * (e.amp or 0.2)
			if v < 0 then v = 0 end
			for _, tgt in ipairs(en.targets) do
				pcall(function() tgt[e.prop] = v end)
			end
		end
	end

	for _, p in ipairs(rec.parts) do
		local s = scale[p]
		if s then
			local want = rec.sizes[p] * s
			if (p.Size - want).Magnitude > 0.001 then
				p.Size = want
			end
		end
		p.CFrame = rec.origin * xf[p] * rec.offsets[p]
	end
end

local function rescan()
	tracked = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("IdleMotion") then
			local rec = prepare(d)
			if rec then
				tracked[#tracked + 1] = rec
			end
		end
	end
end

rescan()

-- pick up models added or removed later (a plot being built, a model dragged in)
local dirty = false
local function markDirty()
	dirty = true
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then markDirty() end
end)
workspace.DescendantRemoving:Connect(function(d)
	if d:IsA("Model") then markDirty() end
end)

local since = 0
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	since += dt
	if dirty and since > 0.5 then
		dirty, since = false, 0
		rescan()
	end
	for i = #tracked, 1, -1 do
		local rec = tracked[i]
		if rec.model.Parent == nil then
			table.remove(tracked, i)
		else
			step(rec, t)
		end
	end
end)
