--!nocheck
-- Mock Roblox runtime for an offline smoke test of the TV behaviour (fun-builds, 2026-09-24)
local _G0 = {math = math, string = string, table = table, ipairs = ipairs, pairs = pairs, type = type, tostring = tostring,
	tonumber = tonumber, pcall = pcall, error = error, print = print, setmetatable = setmetatable, getmetatable = getmetatable,
	rawget = rawget, rawset = rawset, select = select, next = next, assert = assert, xpcall = xpcall, debug = debug, unpack = table.unpack}
setfenv(1, setmetatable({}, {
	__index = function(_, k)
		local v = _G0[k]
		if v == nil then error("UNKNOWN GLOBAL READ: " .. tostring(k), 2) end
		return v
	end,
	__newindex = function(_, k) error("GLOBAL WRITE: " .. tostring(k), 2) end,
}))

local fakeClock = 0
local serverNow = 1000
local os = {clock = function() return fakeClock end}
local warn = function(...) print("WARN", ...) end

--..Signals..--
local function Signal()
	local s = {_fns = {}}
	function s:Connect(fn)
		local e = {fn = fn, on = true}
		table.insert(self._fns, e)
		return {Disconnect = function() e.on = false end}
	end
	function s:Once(fn)
		local c
		c = self:Connect(function(...) c.Disconnect() fn(...) end)
		return c
	end
	function s:Fire(...)
		for _, e in ipairs(table.clone(self._fns)) do if e.on then e.fn(...) end end
	end
	return s
end

--..task..--
local deferred, delayed = {}, {}
local task = {}
function task.spawn(fn, ...) fn(...) end
function task.defer(fn, ...) table.insert(deferred, {fn, table.pack(...)}) end
function task.delay(t, fn, ...) table.insert(delayed, {at = fakeClock + t, fn = fn, args = table.pack(...)}) end
function task.wait() return 0 end
local function Flush()
	local guard = 0
	while #deferred > 0 do
		guard += 1
		assert(guard < 1000, "defer loop")
		local q = deferred
		deferred = {}
		for _, d in ipairs(q) do d[1](table.unpack(d[2], 1, d[2].n)) end
	end
end
local function Advance(dt)
	local target = fakeClock + dt
	while true do
		local bi, best
		for i, d in ipairs(delayed) do
			if d.at <= target and (not best or d.at < best.at) then bi, best = i, d end
		end
		if not best then break end
		table.remove(delayed, bi)
		serverNow += best.at - fakeClock
		fakeClock = best.at
		best.fn(table.unpack(best.args, 1, best.args.n))
		Flush()
	end
	serverNow += target - fakeClock
	fakeClock = target
	Flush()
end

--..Vector3..--
local V3, V3mt = {}, {}
local function v3(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, _v3 = true}, V3mt) end
V3mt.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		return v3(t.X / m, t.Y / m, t.Z / m)
	end
	local f = V3[k]
	if f == nil then error("Vector3 has no member " .. tostring(k), 2) end
	return f
end
V3mt.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3mt.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b) return v3(a.X / b, a.Y / b, a.Z / b) end
V3mt.__tostring = function(a) return string.format("(%.4f, %.4f, %.4f)", a.X, a.Y, a.Z) end
function V3.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3.Cross(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local Vector3 = {new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1)}

--..Vector2..--
local V2mt = {}
local function v2(x, y) return setmetatable({X = x or 0, Y = y or 0, _v2 = true}, V2mt) end
V2mt.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
	error("Vector2 has no member " .. tostring(k), 2)
end
V2mt.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
V2mt.__tostring = function(a) return string.format("(%.3f, %.3f)", a.X, a.Y) end
local Vector2 = {new = v2, zero = v2(0, 0)}

--..CFrame..--
local CF, CFmt = {}, {}
local function cfraw(p, x, y, z) return setmetatable({_p = p, _x = x, _y = y, _z = z, _cf = true}, CFmt) end
local function rot(c, v) return c._x * v.X + c._y * v.Y + c._z * v.Z end
CFmt.__index = function(c, k)
	if k == "Position" or k == "p" then return c._p end
	if k == "XVector" or k == "RightVector" then return c._x end
	if k == "YVector" or k == "UpVector" then return c._y end
	if k == "ZVector" then return c._z end
	if k == "LookVector" then return -c._z end
	if k == "Rotation" then return cfraw(v3(), c._x, c._y, c._z) end
	local f = CF[k]
	if f == nil then error("CFrame has no member " .. tostring(k), 2) end
	return f
end
CFmt.__mul = function(a, b)
	if rawget(b, "_cf") then return cfraw(a._p + rot(a, b._p), rot(a, b._x), rot(a, b._y), rot(a, b._z)) end
	return a._p + rot(a, b)
end
CFmt.__add = function(a, v) return cfraw(a._p + v, a._x, a._y, a._z) end
CFmt.__tostring = function(c) return "CF" .. tostring(c._p) .. " look " .. tostring(-c._z) end
local function inv(c)
	local x, y, z = c._x, c._y, c._z
	local r = cfraw(v3(), v3(x.X, y.X, z.X), v3(x.Y, y.Y, z.Y), v3(x.Z, y.Z, z.Z))
	return cfraw(-rot(r, c._p), r._x, r._y, r._z)
end
function CF.Inverse(c) return inv(c) end
function CF.PointToWorldSpace(c, v) return c._p + rot(c, v) end
function CF.PointToObjectSpace(c, v) return inv(c) * v end
function CF.ToObjectSpace(c, o) return inv(c) * o end
function CF.ToWorldSpace(c, o) return c * o end
local CFrame = {}
function CFrame.new(a, b, c)
	if a == nil then return cfraw(v3(), v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)) end
	if type(a) == "table" then return cfraw(a, v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)) end
	return cfraw(v3(a, b, c), v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1))
end
function CFrame.fromMatrix(p, x, y, z) return cfraw(p, x, y, z or x:Cross(y)) end
function CFrame.Angles(ax, ay, az)
	local cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
	local rx = cfraw(v3(), v3(1, 0, 0), v3(0, cx, sx), v3(0, -sx, cx))
	local ry = cfraw(v3(), v3(cy, 0, -sy), v3(0, 1, 0), v3(sy, 0, cy))
	local rz = cfraw(v3(), v3(cz, sz, 0), v3(-sz, cz, 0), v3(0, 0, 1))
	return rx * ry * rz
end
CFrame.identity = CFrame.new()

--..Misc value types..--
local UDim = {new = function(s, o) return {Scale = s, Offset = o} end}
local UDim2 = {
	new = function(xs, xo, ys, yo) return {X = UDim.new(xs, xo), Y = UDim.new(ys, yo), _udim2 = true} end,
}
UDim2.fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end
UDim2.fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end
local function udimstr(u) return string.format("{%.3f,%d},{%.3f,%d}", u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset) end
local Color3 = {
	new = function(r, g, b) return {R = r, G = g, B = b} end,
	fromRGB = function(r, g, b) return {R = r / 255, G = g / 255, B = b / 255} end,
}
local ColorSequence = {new = function(...) return {...} end}
local ColorSequenceKeypoint = {new = function(t, c) return {Time = t, Value = c} end}
local NumberSequence = {new = function(...) return {...} end}
local NumberSequenceKeypoint = {new = function(t, v) return {Time = t, Value = v} end}
local TweenInfo = {new = function(...) return {...} end}
local Enum = setmetatable({}, {__index = function(t, k)
	local sub = setmetatable({}, {__index = function(s, n)
		local item = {Name = n, EnumType = k}
		rawset(s, n, item)
		return item
	end})
	rawset(t, k, sub)
	return sub
end})

--..Instances..--
local Methods, InstMT = {}, {}
local DEFAULTS = {
	Part = {Transparency = 0, Anchored = false, CanCollide = true, Material = "Plastic"},
	MeshPart = {Transparency = 0},
	VideoFrame = {Playing = false, IsLoaded = false, TimeLength = 0, TimePosition = 0, Volume = 1, Visible = true},
	Sound = {Playing = false, TimePosition = 0, Volume = 0.5},
	Frame = {Visible = true, BackgroundTransparency = 0},
	TextLabel = {Visible = true},
	ImageLabel = {Visible = true, ImageTransparency = 0},
	ProximityPrompt = {Enabled = true},
}
local BASEPARTS = {Part = true, MeshPart = true, Seat = true}
local function Inst(className)
	local props = {ClassName = className, Name = className}
	for k, v in pairs(DEFAULTS[className] or {}) do props[k] = v end
	if BASEPARTS[className] then
		props.CFrame = CFrame.new()
		props.Size = v3(4, 1, 2)
	end
	local o = setmetatable({_inst = true, _props = props, _children = {}, _attrs = {}, _attrSig = {}, _propSig = {}}, InstMT)
	if className == "ProximityPrompt" then props.Triggered = Signal() end
	return o
end
InstMT.__index = function(o, k)
	local m = Methods[k]
	if m then return m end
	local p = o._props[k]
	if p ~= nil then return p end
	for _, c in ipairs(o._children) do if c._props.Name == k then return c end end
	if k == "Position" and o._props.CFrame then return o._props.CFrame.Position end
	return nil
end
InstMT.__newindex = function(o, k, v)
	local props = o._props
	if k == "Parent" then
		local old = props.Parent
		if old then
			local list = old._children
			for i = #list, 1, -1 do if list[i] == o then table.remove(list, i) end end
		end
		props.Parent = v
		if v then table.insert(v._children, o) end
		return
	end
	if o._destroyed then error("set " .. k .. " on a destroyed " .. props.ClassName, 2) end
	if k == "Position" and props.CFrame then
		props.CFrame = cfraw(v, props.CFrame._x, props.CFrame._y, props.CFrame._z)
		return
	end
	props[k] = v
	local s = o._propSig[k]
	if s then s:Fire() end
end
InstMT.__tostring = function(o) return o._props.ClassName .. " " .. tostring(o._props.Name) end
function Methods.FindFirstChild(o, name, recursive)
	for _, c in ipairs(o._children) do if c._props.Name == name then return c end end
	if recursive then
		for _, c in ipairs(o._children) do
			local f = c:FindFirstChild(name, true)
			if f then return f end
		end
	end
	return nil
end
function Methods.WaitForChild(o, name) return o:FindFirstChild(name) end
function Methods.FindFirstChildOfClass(o, cls)
	for _, c in ipairs(o._children) do if c._props.ClassName == cls then return c end end
	return nil
end
function Methods.GetChildren(o) return table.clone(o._children) end
function Methods.GetDescendants(o)
	local out = {}
	local function walk(x)
		for _, c in ipairs(x._children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(o)
	return out
end
function Methods.IsA(o, cls)
	local c = o._props.ClassName
	return cls == c or cls == "Instance" or (cls == "BasePart" and BASEPARTS[c] == true)
end
function Methods.Destroy(o)
	for _, c in ipairs(table.clone(o._children)) do c:Destroy() end
	o.Parent = nil
	rawset(o, "_destroyed", true)
end
function Methods.GetAttribute(o, k) return o._attrs[k] end
function Methods.SetAttribute(o, k, v)
	o._attrs[k] = v
	local s = o._attrSig[k]
	if s then s:Fire() end
end
function Methods.GetAttributeChangedSignal(o, k)
	o._attrSig[k] = o._attrSig[k] or Signal()
	return o._attrSig[k]
end
function Methods.GetPropertyChangedSignal(o, k)
	o._propSig[k] = o._propSig[k] or Signal()
	return o._propSig[k]
end
function Methods.Play(o) o._props.Playing = true o._props.Plays = (o._props.Plays or 0) + 1 end
function Methods.Stop(o) o._props.Playing = false end
function Methods.Pause(o) o._props.Playing = false end
function Methods.IsDescendantOf(o, anc)
	local p = o._props.Parent
	while p do
		if p == anc then return true end
		p = p._props.Parent
	end
	return false
end
function Methods.GetServerTimeNow() return serverNow end
function Methods.GetPivot(o) return o._props.PrimaryPart and o._props.PrimaryPart.CFrame or CFrame.new() end

local Instance = {new = function(cls, parent)
	local o = Inst(cls)
	if parent then o.Parent = parent end
	return o
end}
local function typeof(v)
	if type(v) == "table" then
		if rawget(v, "_v3") then return "Vector3" end
		if rawget(v, "_cf") then return "CFrame" end
		if rawget(v, "_inst") then return "Instance" end
		if rawget(v, "_v2") then return "Vector2" end
	end
	return type(v)
end

--..Services / game..--
local workspace = Inst("Workspace")
workspace.Name = "Workspace"
local camera = Inst("Camera")
camera.CFrame = CFrame.new()
camera.Parent = workspace
workspace.CurrentCamera = camera
local ReplicatedStorageI = Inst("ReplicatedStorage")
local ModulesI = Inst("Folder")
ModulesI.Name = "Modules"
ModulesI.Parent = ReplicatedStorageI
local tweensMade = 0
local TweenServiceI = {Create = function(_, inst, _, props)
	tweensMade += 1
	return {
		Play = function() for k, v in pairs(props) do inst[k] = v end end,
		Cancel = function() end,
	}
end}
local ContentProviderI = {PreloadAsync = function() end}
local RunServiceI = {IsServer = function() return false end}
local CollectionServiceI = {AddTag = function() end}
local game = {GetService = function(_, name)
	if name == "ReplicatedStorage" then return ReplicatedStorageI end
	if name == "TweenService" then return TweenServiceI end
	if name == "ContentProvider" then return ContentProviderI end
	if name == "RunService" then return RunServiceI end
	if name == "CollectionService" then return CollectionServiceI end
	error("no service " .. name)
end}
local require = function(m)
	local mod = rawget(m, "_module")
	assert(mod ~= nil, "require of unknown module " .. tostring(m))
	return mod
end
local function RegisterModule(name, value)
	local m = Inst("ModuleScript")
	m.Name = name
	rawset(m, "_module", value)
	m.Parent = ModulesI
end
