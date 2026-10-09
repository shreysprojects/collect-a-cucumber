--!nolint
-- Bakes the idle-FX spec into the cucumber set, in Studio EDIT mode, via execute_luau.
--
--   local f = loadstring(HttpService:GetAsync(BASE .. "bake_fx.lua"))
--   return f().bake()          -- VFX instances + IdleMotion attributes + the driver
--   return f().display()       -- rebuild Workspace.CucumberSetDisplay from the library
--   return f().clear()         -- remove every baked instance and attribute
--
-- The split that matters:
--   * VFX INSTANCES (ParticleEmitter / lights / beams / added parts) are baked as real
--     children of the models in ServerStorage, so they persist when the place is saved
--     and are visible in edit mode without anything running.
--   * MOTION is a JSON `IdleMotion` attribute read at runtime by the client-side driver
--     (idlefx.lua).  Nothing about the animation is hard-coded per model, so a model
--     carries its own animation wherever it is copied.
--
-- Every instance this creates carries the attribute IdleFXBaked = true, which is how
-- clear() and a re-bake find and remove the previous pass.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local BASE = "http://127.0.0.1:8765/"
local LIB = "CucumberSet"
local DISPLAY = "CucumberSetDisplay"
local DRIVER = "CucumberIdleFX"

local PARTICLE = {
	sparkles = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	implode = "rbxasset://textures/particles/explosion01_implode_main.dds",
	water = "rbxasset://textures/particles/water_main.dds",
	bubble = "rbxasset://textures/particles/bubble_main.dds",
	snow = "rbxasset://textures/particles/snow_main.dds",
	starfield = "rbxasset://textures/particles/starfield_main.dds",
	leaf = "rbxasset://textures/particles/leaf_main.dds",
}

local function hex(h)
	local n = tonumber((tostring(h):gsub("#", "")), 16) or 0
	return Color3.fromRGB(bit32.band(bit32.rshift(n, 16), 255),
		bit32.band(bit32.rshift(n, 8), 255), bit32.band(n, 255))
end

local function isArray(v)
	return type(v) == "table" and #v > 0
end

-- a 2-number array becomes a range; anything else is passed through
local function toRange(v)
	if isArray(v) and type(v[1]) == "number" then
		return NumberRange.new(v[1], v[2] or v[1])
	end
	return NumberRange.new(tonumber(v) or 0)
end

-- [a, b] becomes a 2-keypoint ramp; [[t, v], ...] becomes an explicit curve
local function toNumberSequence(v)
	if isArray(v) and isArray(v[1]) then
		local kp = {}
		for _, pair in ipairs(v) do
			kp[#kp + 1] = NumberSequenceKeypoint.new(pair[1], pair[2])
		end
		return NumberSequence.new(kp)
	end
	if isArray(v) then
		return NumberSequence.new(v[1], v[2] or v[1])
	end
	return NumberSequence.new(tonumber(v) or 0)
end

local function toColorSequence(v)
	if isArray(v) and isArray(v[1]) then
		local kp = {}
		for _, pair in ipairs(v) do
			kp[#kp + 1] = ColorSequenceKeypoint.new(pair[1], hex(pair[2]))
		end
		return ColorSequence.new(kp)
	end
	if isArray(v) then
		local kp = {}
		for i, h in ipairs(v) do
			kp[#kp + 1] = ColorSequenceKeypoint.new((i - 1) / math.max(1, #v - 1), hex(h))
		end
		return ColorSequence.new(kp)
	end
	return ColorSequence.new(hex(v))
end

local function toVector3(v)
	if isArray(v) then
		return Vector3.new(v[1] or 0, v[2] or 0, v[3] or 0)
	end
	return Vector3.zero
end

-- SpreadAngle is a Vector2, not a NumberRange - the one property in this family that is.
-- Lifetime is a NumberRange on a ParticleEmitter but a plain number on a Trail, so it is
-- handled separately rather than living in here.
local RANGE_PROPS = { Speed = true, Rotation = true, RotSpeed = true }
local SEQ_PROPS = { Size = true, Transparency = true, WidthScale = true }
local V3_PROPS = { Acceleration = true, EmitterSize = true }

local function applyProps(inst, props)
	for k, v in pairs(props or {}) do
		local ok, err = pcall(function()
			if k == "Texture" and type(v) == "string" and PARTICLE[v] then
				inst.Texture = PARTICLE[v]
			elseif k == "Color" then
				if inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
					inst.Color = toColorSequence(v)
				else
					inst.Color = hex(v)
				end
			elseif k == "Size" and inst:IsA("ParticleEmitter") then
				inst.Size = toNumberSequence(v)
			elseif SEQ_PROPS[k] and (inst:IsA("ParticleEmitter") or inst:IsA("Trail")
					or inst:IsA("Beam")) then
				inst[k] = toNumberSequence(v)
			elseif k == "Lifetime" then
				-- NumberRange on an emitter, a bare number on a Trail
				inst.Lifetime = inst:IsA("ParticleEmitter") and toRange(v)
					or (isArray(v) and v[1] or tonumber(v) or 1)
			elseif k == "SpreadAngle" then
				inst.SpreadAngle = isArray(v) and Vector2.new(v[1] or 0, v[2] or v[1] or 0)
					or Vector2.new(tonumber(v) or 0, tonumber(v) or 0)
			elseif RANGE_PROPS[k] then
				inst[k] = toRange(v)
			elseif V3_PROPS[k] then
				inst[k] = toVector3(v)
			elseif k == "EmissionDirection" then
				inst.EmissionDirection = Enum.NormalId[v] or Enum.NormalId.Top
			elseif k == "Material" then
				inst.Material = Enum.Material[v] or Enum.Material.SmoothPlastic
			elseif k == "Shape" then
				-- Shape means PartType on a Part but ParticleEmitterShape on an emitter
				if inst:IsA("ParticleEmitter") then
					inst.Shape = Enum.ParticleEmitterShape[v] or Enum.ParticleEmitterShape.Box
				else
					inst.Shape = Enum.PartType[v] or Enum.PartType.Block
				end
			elseif k == "ShapeStyle" then
				inst.ShapeStyle = Enum.ParticleEmitterShapeStyle[v]
					or Enum.ParticleEmitterShapeStyle.Volume
			elseif k == "ShapeInOut" then
				inst.ShapeInOut = Enum.ParticleEmitterShapeInOut[v]
					or Enum.ParticleEmitterShapeInOut.Outward
			else
				inst[k] = v
			end
		end)
		if not ok then
			warn(("[bake_fx] %s.%s = %s -> %s"):format(inst.ClassName, k, tostring(v), tostring(err)))
		end
	end
end

local function tag(inst)
	inst:SetAttribute("IdleFXBaked", true)
	return inst
end

local function findPart(model, name)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == name then
			return d
		end
	end
	return nil
end

local function stripBaked(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:GetAttribute("IdleFXBaked") then
			d:Destroy()
			n += 1
		end
	end
	model:SetAttribute("IdleMotion", nil)
	model:SetAttribute("IdleFX", nil)
	return n
end

-- ---------------------------------------------------------------- one model
local function bakeModel(model, entry, report)
	stripBaked(model)

	local made = 0
	for _, fx in ipairs(entry.vfx or {}) do
		local host = findPart(model, fx.parent)
		if not host then
			table.insert(report, ("  %s: no part %q for %s"):format(model.Name, tostring(fx.parent), fx.class))
		elseif fx.class == "Part" then
			-- Added geometry, positioned in MODEL space.  `Offsets` (a list of 3-arrays)
			-- makes several parts that all share ONE name, so a motion entry targeting
			-- that name animates the whole swarm - which is how the orbiting mote and
			-- moonlet treatments work.
			local offs = (fx.props and fx.props.Offsets)
			if not (isArray(offs) and isArray(offs[1])) then
				offs = { (fx.props and fx.props.Offset) or { 0, 0, 0 } }
			end
			local props = {}
			for k, v in pairs(fx.props or {}) do
				if k ~= "Offset" and k ~= "Offsets" then props[k] = v end
			end
			for _, off in ipairs(offs) do
				local p = Instance.new("Part")
				p.Name = fx.name or "FXPart"
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Massless = true
				p.TopSurface = Enum.SurfaceType.Smooth
				p.BottomSurface = Enum.SurfaceType.Smooth
				local mine = {}
				for k, v in pairs(props) do mine[k] = v end
				if mine.Size and isArray(mine.Size) then
					p.Size = toVector3(mine.Size)
					mine.Size = nil
				end
				applyProps(p, mine)
				p.CFrame = model:GetPivot() * CFrame.new(toVector3(off))
				p.Parent = host
				tag(p)
				made += 1
			end
		elseif fx.class == "Beam" then
			local a0 = tag(Instance.new("Attachment"))
			local a1 = tag(Instance.new("Attachment"))
			a0.Name, a1.Name = (fx.name or "Beam") .. "A", (fx.name or "Beam") .. "B"
			local pivot = model:GetPivot()
			a0.WorldCFrame = pivot * CFrame.new(toVector3(fx.props and fx.props.From))
			a1.WorldCFrame = pivot * CFrame.new(toVector3(fx.props and fx.props.To))
			a0.Parent, a1.Parent = host, host
			local b = Instance.new("Beam")
			b.Name = fx.name or "Beam"
			b.Attachment0, b.Attachment1 = a0, a1
			local props = {}
			for k, v in pairs(fx.props or {}) do
				if k ~= "From" and k ~= "To" then props[k] = v end
			end
			applyProps(b, props)
			b.Parent = host
			tag(b)
			made += 1
		else
			local ok, inst = pcall(Instance.new, fx.class)
			if not ok or not inst then
				table.insert(report, ("  %s: cannot create %s"):format(model.Name, tostring(fx.class)))
			else
				inst.Name = fx.name or fx.class
				local props = {}
				for k, v in pairs(fx.props or {}) do
					if k ~= "Offset" and k ~= "Span" and k ~= "EmitterSize" then
						props[k] = v
					end
				end

				-- An effect with an Offset and/or EmitterSize gets its own invisible host
				-- part.  This is deliberately NOT an Attachment: a ParticleEmitter
				-- parented to a part emits throughout that part's VOLUME, which is how a
				-- canopy sheds leaves across its whole width instead of dribbling them
				-- from a single point.  (ParticleEmitter.EmitterSize does not exist in
				-- this Studio version, so a sizing part is the portable way to do it.)
				local mount = host
				local fxProps = fx.props or {}
				if fxProps.Offset or fxProps.EmitterSize then
					local hp = Instance.new("Part")
					hp.Name = (fx.name or fx.class) .. "Emitter"
					hp.Size = fxProps.EmitterSize and toVector3(fxProps.EmitterSize)
						or Vector3.new(0.2, 0.2, 0.2)
					hp.Transparency = 1
					hp.Anchored = true
					hp.CanCollide = false
					hp.CanQuery = false
					hp.CanTouch = false
					hp.CastShadow = false
					hp.Massless = true
					hp.CFrame = model:GetPivot() * CFrame.new(toVector3(fxProps.Offset))
					hp.Parent = host
					tag(hp)
					mount = hp
					made += 1
				end

				if fx.class == "Trail" then
					local span = (fx.props and fx.props.Span) or 0.12
					local a0, a1 = tag(Instance.new("Attachment")), tag(Instance.new("Attachment"))
					a0.Name, a1.Name = inst.Name .. "A", inst.Name .. "B"
					a0.Position = Vector3.new(0, span / 2, 0)
					a1.Position = Vector3.new(0, -span / 2, 0)
					a0.Parent, a1.Parent = host, host
					inst.Attachment0, inst.Attachment1 = a0, a1
				end

				applyProps(inst, props)
				inst.Parent = mount
				tag(inst)
				made += 1
			end
		end
	end

	if entry.motion and #entry.motion > 0 then
		model:SetAttribute("IdleMotion", HttpService:JSONEncode({ motion = entry.motion }))
	end
	model:SetAttribute("IdleFX", entry.treatment or "idle")
	return made
end

-- ---------------------------------------------------------------- driver
local function installDriver()
	local old = workspace:FindFirstChild(DRIVER)
	if old then
		old:Destroy()
	end
	local src = HttpService:GetAsync(BASE .. "idlefx.lua")
	local s = Instance.new("Script")
	s.Name = DRIVER
	s.RunContext = Enum.RunContext.Client
	s.Source = src
	s.Parent = workspace
	return #src
end

-- ---------------------------------------------------------------- display
local function rebuildDisplay(origin, gap, rowGap)
	origin = origin or Vector3.new(0, 0, -40)
	gap = gap or 6
	rowGap = rowGap or 18
	local lib = ServerStorage:FindFirstChild(LIB)
	if not lib then
		return "no ServerStorage." .. LIB
	end
	local old = workspace:FindFirstChild(DISPLAY)
	if old then
		old:Destroy()
	end
	local disp = Instance.new("Folder")
	disp.Name = DISPLAY
	disp.Parent = workspace

	local ORDER = { "grass", "desert", "volcano", "narmek", "samurai", "farm", "snow",
		"underwater" }
	local rows = {}
	for _, b in ipairs(ORDER) do rows[b] = {} end
	local names = {}
	for _, m in ipairs(lib:GetChildren()) do names[#names + 1] = m.Name end
	table.sort(names)
	for _, n in ipairs(names) do
		local b = lib[n]:GetAttribute("Biome") or "grass"
		rows[b] = rows[b] or {}
		table.insert(rows[b], n)
	end

	local function aabb(m)
		local lo, hi
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				local cf, s = d.CFrame, d.Size / 2
				for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
					local p = cf:PointToWorldSpace(Vector3.new(s.X * sx, s.Y * sy, s.Z * sz))
					lo = lo and Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z)) or p
					hi = hi and Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z)) or p
				end end end
			end
		end
		return lo or Vector3.zero, hi or Vector3.zero
	end

	local z, placed, lines = origin.Z, 0, {}
	for _, b in ipairs(ORDER) do
		local row = rows[b]
		if row and #row > 0 then
			local w, depth = {}, 0
			for _, n in ipairs(row) do
				local lo, hi = aabb(lib[n])
				w[n] = hi.X - lo.X
				depth = math.max(depth, hi.Z - lo.Z)
			end
			local total = 0
			for _, n in ipairs(row) do total += w[n] + gap end
			local x = origin.X - total / 2
			for _, n in ipairs(row) do
				x += w[n] / 2
				local clone = lib[n]:Clone()
				clone:PivotTo(CFrame.new(x, origin.Y, z))
				clone.Parent = disp
				placed += 1
				x += w[n] / 2 + gap
			end
			table.insert(lines, ("%-11s %d models at z %.0f"):format(b, #row, z))
			z -= depth + rowGap
		end
	end
	return ("rebuilt workspace.%s with %d models\n%s"):format(DISPLAY, placed,
		table.concat(lines, "\n"))
end

-- ---------------------------------------------------------------- API
local API = {}

function API.bake()
	local spec = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "idle-spec.json"))
	local lib = ServerStorage:FindFirstChild(LIB)
	if not lib then
		return "no ServerStorage." .. LIB
	end
	local report, done, fxTotal = {}, 0, 0
	for name, entry in pairs(spec.models or {}) do
		local m = lib:FindFirstChild(name)
		if not m then
			table.insert(report, ("  MISSING MODEL %s"):format(name))
		else
			local made = bakeModel(m, entry, report)
			fxTotal += made
			done += 1
			table.insert(report, ("  %-26s %-22s %d motion, %d vfx"):format(
				name, entry.treatment or "?", #(entry.motion or {}), made))
		end
	end
	local srcLen = installDriver()
	table.sort(report)
	return ("baked %d models, %d vfx instances; driver installed (%d bytes)\n%s")
		:format(done, fxTotal, srcLen, table.concat(report, "\n"))
end

function API.display(origin, gap, rowGap)
	return rebuildDisplay(origin, gap, rowGap)
end

function API.clear()
	local lib = ServerStorage:FindFirstChild(LIB)
	local n, m = 0, 0
	if lib then
		for _, mod in ipairs(lib:GetChildren()) do
			local k = stripBaked(mod)
			if k > 0 then m += 1 end
			n += k
		end
	end
	local d = workspace:FindFirstChild(DRIVER)
	if d then d:Destroy() end
	return ("cleared %d baked instances from %d models; driver removed"):format(n, m)
end

function API.audit()
	local lib = ServerStorage:FindFirstChild(LIB)
	local out, withFx, particles = {}, 0, 0
	for _, m in ipairs(lib:GetChildren()) do
		local fx = m:GetAttribute("IdleFX")
		if fx then
			withFx += 1
			local cnt, kinds = 0, {}
			for _, d in ipairs(m:GetDescendants()) do
				if d:GetAttribute("IdleFXBaked") then
					cnt += 1
					kinds[d.ClassName] = (kinds[d.ClassName] or 0) + 1
					if d:IsA("ParticleEmitter") then particles += d.Rate end
				end
			end
			local ks = {}
			for k, v in pairs(kinds) do ks[#ks + 1] = v .. "x" .. k end
			local mo = m:GetAttribute("IdleMotion")
			local nm = 0
			if type(mo) == "string" then
				local ok, dec = pcall(function() return HttpService:JSONDecode(mo) end)
				nm = (ok and dec and dec.motion) and #dec.motion or 0
			end
			table.insert(out, ("%-26s %-22s %d motion  %s"):format(m.Name, fx, nm,
				table.concat(ks, ", ")))
		end
	end
	table.sort(out)
	return ("%d models carry idle FX; total particle Rate across the set %.1f\n%s")
		:format(withFx, particles, table.concat(out, "\n"))
end

return API
