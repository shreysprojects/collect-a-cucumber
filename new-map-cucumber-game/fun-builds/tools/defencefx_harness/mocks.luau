--!nocheck
-- Roblox mocks for the DefenceFX offline harness (copied from vend_harness: real CFrame/Vector3 maths; signals,
-- coroutine scheduler and instances extended here).
local M = {}

local function typeOf(v)
	local mt = getmetatable(v)
	if type(mt) == "table" and rawget(mt, "__type") then return mt.__type end
	return type(v)
end
M.typeof = typeOf

--==================================================================== Vector3
local V3 = {}
V3.__type = "Vector3"
V3.__index = function(v, k)
	if k == "X" then return rawget(v, "x") elseif k == "Y" then return rawget(v, "y") elseif k == "Z" then return rawget(v, "z") end
	if k == "Magnitude" then return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
	if k == "Unit" then local m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) return M.Vector3.new(v.x / m, v.y / m, v.z / m) end
	return V3[k]
end
local function v3(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, V3) end
V3.__add = function(a, b) return v3(a.x + b.x, a.y + b.y, a.z + b.z) end
V3.__sub = function(a, b) return v3(a.x - b.x, a.y - b.y, a.z - b.z) end
V3.__unm = function(a) return v3(-a.x, -a.y, -a.z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return v3(b.x * a, b.y * a, b.z * a) end
	if type(b) == "number" then return v3(a.x * b, a.y * b, a.z * b) end
	return v3(a.x * b.x, a.y * b.y, a.z * b.z)
end
V3.__div = function(a, b)
	if type(b) == "number" then return v3(a.x / b, a.y / b, a.z / b) end
	return v3(a.x / b.x, a.y / b.y, a.z / b.z)
end
V3.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
V3.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.x, a.y, a.z) end
function V3.Dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function V3.Cross(a, b) return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
function V3.Lerp(a, b, t) return a + (b - a) * t end
M.Vector3 = {new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1)}

--==================================================================== CFrame (position + 3x3, row-major r[i][j])
local CF = {}
CF.__type = "CFrame"
local function cf(p, r) return setmetatable({p = p, r = r}, CF) end
local IDR = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
local function matmul(a, b)
	local o = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}}
	for i = 1, 3 do for j = 1, 3 do o[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end end
	return o
end
local function matvec(a, v) return v3(a[1][1] * v.x + a[1][2] * v.y + a[1][3] * v.z, a[2][1] * v.x + a[2][2] * v.y + a[2][3] * v.z, a[3][1] * v.x + a[3][2] * v.y + a[3][3] * v.z) end
local function transpose(a) return {{a[1][1], a[2][1], a[3][1]}, {a[1][2], a[2][2], a[3][2]}, {a[1][3], a[2][3], a[3][3]}} end
local function rx(t) local c, s = math.cos(t), math.sin(t) return {{1, 0, 0}, {0, c, -s}, {0, s, c}} end
local function ry(t) local c, s = math.cos(t), math.sin(t) return {{c, 0, s}, {0, 1, 0}, {-s, 0, c}} end
local function rz(t) local c, s = math.cos(t), math.sin(t) return {{c, -s, 0}, {s, c, 0}, {0, 0, 1}} end
local function quatToMat(x, y, z, w)
	local n = math.sqrt(x * x + y * y + z * z + w * w)
	x, y, z, w = x / n, y / n, z / n, w / n
	return {
		{1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)},
		{2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)},
		{2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)},
	}
end
local function matToQuat(m)
	local tr = m[1][1] + m[2][2] + m[3][3]
	local x, y, z, w
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		w = 0.25 * s x = (m[3][2] - m[2][3]) / s y = (m[1][3] - m[3][1]) / s z = (m[2][1] - m[1][2]) / s
	elseif m[1][1] > m[2][2] and m[1][1] > m[3][3] then
		local s = math.sqrt(1 + m[1][1] - m[2][2] - m[3][3]) * 2
		w = (m[3][2] - m[2][3]) / s x = 0.25 * s y = (m[1][2] + m[2][1]) / s z = (m[1][3] + m[3][1]) / s
	elseif m[2][2] > m[3][3] then
		local s = math.sqrt(1 + m[2][2] - m[1][1] - m[3][3]) * 2
		w = (m[1][3] - m[3][1]) / s x = (m[1][2] + m[2][1]) / s y = 0.25 * s z = (m[2][3] + m[3][2]) / s
	else
		local s = math.sqrt(1 + m[3][3] - m[1][1] - m[2][2]) * 2
		w = (m[2][1] - m[1][2]) / s x = (m[1][3] + m[3][1]) / s y = (m[2][3] + m[3][2]) / s z = 0.25 * s
	end
	return x, y, z, w
end
CF.__index = function(c, k)
	if k == "Position" then return c.p end
	if k == "X" then return c.p.x elseif k == "Y" then return c.p.y elseif k == "Z" then return c.p.z end
	if k == "Rotation" then return cf(v3(0, 0, 0), c.r) end
	if k == "LookVector" then return v3(-c.r[1][3], -c.r[2][3], -c.r[3][3]) end
	if k == "UpVector" then return v3(c.r[1][2], c.r[2][2], c.r[3][2]) end
	if k == "RightVector" then return v3(c.r[1][1], c.r[2][1], c.r[3][1]) end
	return CF[k]
end
CF.__mul = function(a, b)
	if typeOf(b) == "Vector3" then return a.p + matvec(a.r, b) end
	return cf(a.p + matvec(a.r, b.p), matmul(a.r, b.r))
end
CF.__add = function(a, v) return cf(a.p + v, a.r) end
CF.__sub = function(a, v) return cf(a.p - v, a.r) end
function CF.Inverse(c) local rt = transpose(c.r) return cf(-matvec(rt, c.p), rt) end
function CF.ToObjectSpace(a, b) return a:Inverse() * b end
function CF.ToWorldSpace(a, b) return a * b end
function CF.PointToObjectSpace(a, v) return a:Inverse() * v end
function CF.PointToWorldSpace(a, v) return a * v end
function CF.VectorToWorldSpace(a, v) return matvec(a.r, v) end
function CF.VectorToObjectSpace(a, v) return matvec(transpose(a.r), v) end
function CF.Lerp(a, b, t)
	local ax, ay, az, aw = matToQuat(a.r)
	local bx, by, bz, bw = matToQuat(b.r)
	local d = ax * bx + ay * by + az * bz + aw * bw
	if d < 0 then bx, by, bz, bw, d = -bx, -by, -bz, -bw, -d end
	local x, y, z, w
	if d > 0.9995 then
		x, y, z, w = ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t, aw + (bw - aw) * t
	else
		local th = math.acos(d)
		local s0, s1 = math.sin((1 - t) * th) / math.sin(th), math.sin(t * th) / math.sin(th)
		x, y, z, w = ax * s0 + bx * s1, ay * s0 + by * s1, az * s0 + bz * s1, aw * s0 + bw * s1
	end
	return cf(a.p:Lerp(b.p, t), quatToMat(x, y, z, w))
end
function CF.FuzzyEq(a, b, eps)
	if (a.p - b.p).Magnitude > eps then return false end
	for i = 1, 3 do for j = 1, 3 do if math.abs(a.r[i][j] - b.r[i][j]) > eps then return false end end end
	return true
end
function CF.GetComponents(c) return c.p.x, c.p.y, c.p.z end
CF.__tostring = function(c) return "CF" .. tostring(c.p) end
M.CFrame = {
	new = function(...)
		local n = select("#", ...)
		local a = {...}
		if n == 0 then return cf(v3(0, 0, 0), IDR) end
		if n == 1 then return cf(a[1], IDR) end
		if n == 3 then return cf(v3(a[1], a[2], a[3]), IDR) end
		if n == 7 then return cf(v3(a[1], a[2], a[3]), quatToMat(a[4], a[5], a[6], a[7])) end
		if n == 12 then return cf(v3(a[1], a[2], a[3]), {{a[4], a[5], a[6]}, {a[7], a[8], a[9]}, {a[10], a[11], a[12]}}) end
		error("CFrame.new with " .. n .. " args")
	end,
	Angles = function(x, y, z) return cf(v3(0, 0, 0), matmul(matmul(rx(x), ry(y)), rz(z))) end,
	fromAxisAngle = function(axis, ang)
		local u = axis.Unit
		local s = math.sin(ang / 2)
		return cf(v3(0, 0, 0), quatToMat(u.x * s, u.y * s, u.z * s, math.cos(ang / 2)))
	end,
	identity = cf(v3(0, 0, 0), IDR),
	fromMatrix = function(pos, x, y, z)
		z = z or x:Cross(y)
		return cf(pos, {{x.x, y.x, z.x}, {x.y, y.y, z.y}, {x.z, y.z, z.z}})
	end,
}
M.cfRot = function(c) return c.r end

M.CFrame.lookAt = function(pos, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - pos).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then right = look:Cross(v3(1, 0, 0)) end
	right = right.Unit
	local up2 = right:Cross(look)
	return M.CFrame.fromMatrix(pos, right, up2, -look)
end

--==================================================================== small value types
local function valueType(name, fields)
	local mt = {__type = name}
	mt.__index = mt
	return {new = function(...) local t = {...} local o = {} for i, f in ipairs(fields) do o[f] = t[i] end o._args = t return setmetatable(o, mt) end}
end
M.Color3 = {
	new = function(r, g, b) return setmetatable({R = r or 0, G = g or 0, B = b or 0}, {__type = "Color3"}) end,
	fromRGB = function(r, g, b) return setmetatable({R = r / 255, G = g / 255, B = b / 255}, {__type = "Color3"}) end,
}
M.Vector2 = valueType("Vector2", {"X", "Y"})
M.Vector2.zero = M.Vector2.new(0, 0)
M.NumberRange = valueType("NumberRange", {"Min", "Max"})
M.NumberSequence = valueType("NumberSequence", {"Keypoints"})
M.NumberSequenceKeypoint = valueType("NumberSequenceKeypoint", {"Time", "Value"})
M.ColorSequence = valueType("ColorSequence", {"C0", "C1"})
M.TweenInfo = valueType("TweenInfo", {"Time"})
M.Enum = setmetatable({}, {__index = function(_, a) return setmetatable({}, {__index = function(_, b) return "Enum." .. a .. "." .. b end}) end})

--==================================================================== scheduler (coroutines: task.wait really waits for M.clock)
M.clock = 0
local jobs = {}
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then error(debug.traceback(co, tostring(err)), 0) end
end
M.task = {}
function M.task.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(co, ...)
	return co
end
function M.task.delay(t, fn, ...)
	table.insert(jobs, {at = M.clock + (t or 0), fn = fn, args = table.pack(...)})
end
function M.task.defer(fn, ...) M.task.delay(0, fn, ...) end
function M.task.wait(t)
	if not coroutine.isyieldable() then return 0 end
	table.insert(jobs, {at = M.clock + (t or 0), co = coroutine.running()})
	coroutine.yield()
	return t or 0
end
function M.runDue()
	local ran = true
	while ran do
		ran = false
		for i, job in ipairs(jobs) do
			if job.at <= M.clock then
				table.remove(jobs, i)
				if job.co then resume(job.co) else M.task.spawn(job.fn, table.unpack(job.args, 1, job.args.n)) end
				ran = true
				break
			end
		end
	end
end

--==================================================================== signals (handlers run in their own coroutine, like Roblox)
local function Signal()
	local s = {_list = {}}
	function s:Connect(fn)
		local c = {Connected = true}
		table.insert(s._list, {c = c, fn = fn})
		function c:Disconnect() c.Connected = false end
		return c
	end
	function s:Once(fn)
		local c
		c = s:Connect(function(...) c:Disconnect() fn(...) end)
		return c
	end
	s._waiting = {}
	function s:Fire(...)
		local waiting = s._waiting
		s._waiting = {}
		for _, co in ipairs(waiting) do resume(co, ...) end
		for _, e in ipairs(table.clone(s._list)) do
			if e.c.Connected then M.task.spawn(e.fn, ...) end
		end
	end
	function s:Wait() -- yields until the next Fire (Heartbeat:Wait() loops advance with the clock)
		if not coroutine.isyieldable() then return 0 end
		table.insert(s._waiting, coroutine.running())
		return coroutine.yield()
	end
	return s
end
M.Signal = Signal

--==================================================================== Instances
local CLASSES = {
	Part = {"BasePart", "PVInstance", "Instance"}, WedgePart = {"BasePart", "PVInstance", "Instance"},
	MeshPart = {"BasePart", "PVInstance", "Instance"}, Seat = {"BasePart", "PVInstance", "Instance"},
	Terrain = {"BasePart", "PVInstance", "Instance"},
	Model = {"PVInstance", "Instance"}, Workspace = {"Model", "PVInstance", "Instance"}, Folder = {"Instance"},
	Weld = {"JointInstance", "Instance"}, WeldConstraint = {"Instance"}, Motor6D = {"JointInstance", "Instance"},
	AnimationConstraint = {"Constraint", "Instance"}, Sound = {"Instance"}, Attachment = {"Instance"},
	ParticleEmitter = {"Instance"}, Highlight = {"Instance"}, PointLight = {"Light", "Instance"}, SpecialMesh = {"Instance"},
	ProximityPrompt = {"Instance"}, Humanoid = {"Instance"}, Player = {"Instance"}, Camera = {"Instance"},
	ModuleScript = {"LuaSourceContainer", "Instance"}, LocalScript = {"LuaSourceContainer", "Instance"}, Script = {"LuaSourceContainer", "Instance"},
	RemoteEvent = {"Instance"}, BindableFunction = {"Instance"},
}
local EVENTS = {Triggered = true, ChildAdded = true, ChildRemoved = true, AncestryChanged = true, DescendantAdded = true,
	DescendantRemoving = true, Destroying = true, OnClientEvent = true, OnServerEvent = true, Died = true, Ended = true}
local Inst = {}
Inst.__type = "Instance"
local DEFAULTS = {
	BasePart = function(o)
		o._p.CFrame = M.CFrame.identity o._p.Size = v3(1, 1, 1) o._p.Transparency = 0 o._p.LocalTransparencyModifier = 0
		o._p.Anchored = false o._p.CanCollide = true
	end,
}
local function event(o, k)
	local ev = rawget(o, "_ev")
	if not ev[k] then ev[k] = Signal() end
	return ev[k]
end
local function propSignal(o, k)
	local ps = rawget(o, "_ps")
	return ps[k]
end
Inst.__index = function(o, k)
	local p = rawget(o, "_p")
	if k == "Position" and p.CFrame then return p.CFrame.p end
	if k == "Parent" then return p.Parent end
	if p[k] ~= nil then return p[k] end
	local m = Inst[k]
	if m then return m end
	if EVENTS[k] then return event(o, k) end
	for _, c in ipairs(rawget(o, "_kids")) do if rawget(c, "_p").Name == k then return c end end -- inst.ChildName
	return nil
end
local function descendantsOf(x, out)
	out = out or {}
	for _, c in ipairs(rawget(x, "_kids")) do table.insert(out, c) descendantsOf(c, out) end
	return out
end
Inst.__newindex = function(o, k, v)
	local p = rawget(o, "_p")
	if k == "Parent" then
		local old = p.Parent
		if old == v then return end
		if old then
			local kids = rawget(old, "_kids")
			for i, c in ipairs(kids) do if c == o then table.remove(kids, i) break end end
		end
		p.Parent = v
		if v then table.insert(rawget(v, "_kids"), o) end
		local moved = {o}
		for _, d in ipairs(descendantsOf(o)) do table.insert(moved, d) end
		for _, d in ipairs(moved) do
			local ev = rawget(d, "_ev").AncestryChanged
			if ev then ev:Fire(o, v) end
		end
		if v then
			local ev = rawget(v, "_ev").ChildAdded
			if ev then ev:Fire(o) end
			local a = v
			while a do
				local da = rawget(a, "_ev").DescendantAdded
				if da then for _, d in ipairs(moved) do da:Fire(d) end end
				a = rawget(a, "_p").Parent
			end
		end
		return
	end
	if k == "Position" and p.CFrame then k, v = "CFrame", cf(v, p.CFrame.r) end
	local changed = p[k] ~= v
	p[k] = v
	if changed then
		local s = propSignal(o, k)
		if s then s:Fire() end
	end
end
Inst.__tostring = function(o) return o.Name end
function M.new(class, parent)
	local o = setmetatable({_p = {_class = class, ClassName = class, Name = class, _attrs = {}}, _kids = {}, _ev = {}, _ps = {}, _as = {}}, Inst)
	for _, base in ipairs(CLASSES[class] or {"Instance"}) do if DEFAULTS[base] then DEFAULTS[base](o) end end
	if class == "Humanoid" then o._p.Health = 100 o._p.MaxHealth = 100 o._p.HipHeight = 2 end
	if class == "ParticleEmitter" then o._p.Enabled = true end
	if parent then o.Parent = parent end
	return o
end
function Inst.IsA(o, name)
	if o._p._class == name then return true end
	for _, b in ipairs(CLASSES[o._p._class] or {}) do if b == name then return true end end
	return false
end
function Inst.GetChildren(o) return table.clone(rawget(o, "_kids")) end
function Inst.GetDescendants(o) return descendantsOf(o) end
function Inst.FindFirstChild(o, name, recursive)
	for _, c in ipairs(recursive and o:GetDescendants() or rawget(o, "_kids")) do if c.Name == name then return c end end
	return nil
end
function Inst.WaitForChild(o, name, timeout)
	local c = o:FindFirstChild(name)
	if c then return c end
	if timeout then return nil end
	error("WaitForChild " .. name .. " in " .. o.Name)
end
function Inst.FindFirstChildOfClass(o, cls) for _, c in ipairs(rawget(o, "_kids")) do if c._p._class == cls then return c end end return nil end
function Inst.FindFirstChildWhichIsA(o, cls) for _, c in ipairs(rawget(o, "_kids")) do if c:IsA(cls) then return c end end return nil end
function Inst.IsDescendantOf(o, anc) local p = o.Parent while p do if p == anc then return true end p = p.Parent end return false end
function Inst.Destroy(o)
	if o._p.Destroyed then return end
	local d = rawget(o, "_ev").Destroying
	if d then d:Fire() end
	for _, c in ipairs(o:GetChildren()) do c:Destroy() end
	o.Parent = nil
	o._p.Destroyed = true
end
function Inst.ClearAllChildren(o) for _, c in ipairs(o:GetChildren()) do c:Destroy() end end
function Inst.SetAttribute(o, k, v)
	local old = o._p._attrs[k]
	o._p._attrs[k] = v
	if old ~= v then
		local s = rawget(o, "_as")[k]
		if s then s:Fire() end
	end
end
function Inst.GetAttribute(o, k) return o._p._attrs[k] end
function Inst.GetAttributeChangedSignal(o, k)
	local as = rawget(o, "_as")
	if not as[k] then as[k] = Signal() end
	return as[k]
end
function Inst.GetPropertyChangedSignal(o, k)
	local ps = rawget(o, "_ps")
	if not ps[k] then ps[k] = Signal() end
	return ps[k]
end
function Inst.Play(o) o._p.Plays = (o._p.Plays or 0) + 1 end
function Inst.Emit(o, n)
	o._p.Emitted = (o._p.Emitted or 0) + n
	M.emitted[o] = (M.emitted[o] or 0) + n
	--.. where the emission point is at the call + the frame (the test's Heartbeat count): the collapse check
	local att = o.Parent
	local pos = att and (att.WorldCFrame and att.WorldCFrame.p or att.WorldPosition)
	table.insert(M.emitLog, {pe = o, n = n, att = att, pos = pos, frame = M.frame})
end
function Inst.GetPivot(o) return o.PrimaryPart and o.PrimaryPart.CFrame or M.CFrame.identity end
function Inst.Invoke(o, ...) return o.OnInvoke(...) end
function Inst.FireAllClients(o, ...) table.insert(M.fired, {o.Name, table.pack(...), M.clock}) end
function Inst.FireClient(o, player, ...) table.insert(M.fired, {o.Name, table.pack(...), M.clock, player}) end
function Inst.FireServer(o, ...) end
function Inst.GetBoundingBox(o)
	local lo, hi
	for _, d in ipairs(o:GetDescendants()) do
		if d:IsA("BasePart") then
			local p, h = d.CFrame.p, d.Size * 0.5
			local a, b = p - h, p + h
			lo = lo and v3(math.min(lo.x, a.x), math.min(lo.y, a.y), math.min(lo.z, a.z)) or a
			hi = hi and v3(math.max(hi.x, b.x), math.max(hi.y, b.y), math.max(hi.z, b.z)) or b
		end
	end
	if not lo then return M.CFrame.identity, v3(0, 0, 0) end
	return M.CFrame.new((lo + hi) * 0.5), hi - lo
end
M.emitted = {}
M.fired = {}
M.emitLog = {}
M.frame = 0
function M.reset() -- a fresh run in the same process: clock, scheduled jobs, logs
	M.clock = 0
	table.clear(jobs)
	table.clear(M.emitted)
	table.clear(M.fired)
	table.clear(M.emitLog)
	M.frame = 0
end
M.Instance = {new = M.new}
return M
