--!nocheck
-- Minimal Roblox mock for running GardenLife behaviours in the Luau CLI (test only).
local SIM = {Now = 1790000000, Clock = 1000, Sun = nil, Plays = {}, Tags = {}}

--..Vector3..--
local V3mt = {__type = "Vector3"}
local function v3(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, V3mt) end
local Vector3 = {new = v3}
local function isV(v) return getmetatable(v) == V3mt end
V3mt.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif k == "Dot" then return function(a, b) assert(isV(b), "Dot arg") return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
	elseif k == "Cross" then return function(a, b) assert(isV(b), "Cross arg") return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
	elseif k == "Lerp" then return function(a, b, t) return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
	end
	error("Vector3 has no member " .. tostring(k), 2)
end
V3mt.__add = function(a, b) assert(isV(a) and isV(b), "V3 add: " .. typeof(a) .. "+" .. typeof(b)) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) assert(isV(a) and isV(b), "V3 sub") return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__mul = function(a, b)
	if type(a) == "number" then return v3(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	assert(isV(a) and isV(b), "V3 mul")
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z) end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

--..CFrame (position + row-major 3x3)..--
local CFmt = {__type = "CFrame"}
local function isCF(c) return getmetatable(c) == CFmt end
local function mkcf(p, r) return setmetatable({_p = p, _r = r or {1, 0, 0, 0, 1, 0, 0, 0, 1}}, CFmt) end
local function mulR(A, B)
	local C = {}
	for i = 0, 2 do
		for j = 0, 2 do
			C[i * 3 + j + 1] = A[i * 3 + 1] * B[j + 1] + A[i * 3 + 2] * B[3 + j + 1] + A[i * 3 + 3] * B[6 + j + 1]
		end
	end
	return C
end
local function mulRV(R, v) return v3(R[1] * v.X + R[2] * v.Y + R[3] * v.Z, R[4] * v.X + R[5] * v.Y + R[6] * v.Z, R[7] * v.X + R[8] * v.Y + R[9] * v.Z) end
local function tr(R) return {R[1], R[4], R[7], R[2], R[5], R[8], R[3], R[6], R[9]} end
local function Rx(t) local c, s = math.cos(t), math.sin(t) return {1, 0, 0, 0, c, -s, 0, s, c} end
local function Ry(t) local c, s = math.cos(t), math.sin(t) return {c, 0, s, 0, 1, 0, -s, 0, c} end
local function Rz(t) local c, s = math.cos(t), math.sin(t) return {c, -s, 0, s, c, 0, 0, 0, 1} end
local CFrame = {}
CFrame.new = function(a, b, c, ...)
	if a == nil then return mkcf(v3()) end
	if isV(a) then assert(b == nil, "CFrame.new(pos, look) not mocked") return mkcf(v3(a.X, a.Y, a.Z)) end
	assert(type(a) == "number" and type(b) == "number" and type(c) == "number", "CFrame.new args")
	return mkcf(v3(a, b, c))
end
CFrame.Angles = function(x, y, z) return mkcf(v3(), mulR(mulR(Rx(x), Ry(y)), Rz(z))) end
CFrame.fromOrientation = function(x, y, z) return mkcf(v3(), mulR(mulR(Ry(y), Rx(x)), Rz(z))) end
CFrame.fromAxisAngle = function(axis, t)
	assert(isV(axis) and type(t) == "number", "fromAxisAngle args")
	local u = axis.Unit
	local c, s, C = math.cos(t), math.sin(t), 1 - math.cos(t)
	local x, y, z = u.X, u.Y, u.Z
	return mkcf(v3(), {c + x * x * C, x * y * C - z * s, x * z * C + y * s,
		y * x * C + z * s, c + y * y * C, y * z * C - x * s,
		z * x * C - y * s, z * y * C + x * s, c + z * z * C})
end
CFrame.fromMatrix = function(p, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	return mkcf(v3(p.X, p.Y, p.Z), {vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z})
end
CFrame.identity = mkcf(v3())
local function inv(c) local rt = tr(c._r) return mkcf(-mulRV(rt, c._p), rt) end
local function toQuat(R)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = table.unpack(R)
	local t = m00 + m11 + m22
	local w, x, y, z
	if t > 0 then
		local s = math.sqrt(t + 1) * 2
		w, x, y, z = 0.25 * s, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		w, x, y, z = (m21 - m12) / s, 0.25 * s, (m01 + m10) / s, (m02 + m20) / s
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		w, x, y, z = (m02 - m20) / s, (m01 + m10) / s, 0.25 * s, (m12 + m21) / s
	else
		local s = math.sqrt(1 + m22 - m00 - m11) * 2
		w, x, y, z = (m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25 * s
	end
	return w, x, y, z
end
local function fromQuat(w, x, y, z)
	local n = math.sqrt(w * w + x * x + y * y + z * z)
	w, x, y, z = w / n, x / n, y / n, z / n
	return {1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
		2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
		2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)}
end
CFmt.__index = function(c, k)
	local R = c._r
	if k == "Position" or k == "p" then return c._p
	elseif k == "Rotation" then return mkcf(v3(), R)
	elseif k == "X" then return c._p.X elseif k == "Y" then return c._p.Y elseif k == "Z" then return c._p.Z
	elseif k == "LookVector" then return v3(-R[3], -R[6], -R[9])
	elseif k == "RightVector" then return v3(R[1], R[4], R[7])
	elseif k == "UpVector" then return v3(R[2], R[5], R[8])
	elseif k == "Inverse" then return inv
	elseif k == "ToObjectSpace" then return function(a, b) return inv(a) * b end
	elseif k == "ToWorldSpace" then return function(a, b) return a * b end
	elseif k == "PointToWorldSpace" then return function(a, v) assert(isV(v)) return a * v end
	elseif k == "PointToObjectSpace" then return function(a, v) assert(isV(v)) return inv(a) * v end
	elseif k == "VectorToWorldSpace" then return function(a, v) assert(isV(v)) return mulRV(a._r, v) end
	elseif k == "VectorToObjectSpace" then return function(a, v) assert(isV(v)) return mulRV(tr(a._r), v) end
	elseif k == "ToOrientation" then
		return function(a)
			local r = a._r
			return math.asin(math.clamp(-r[6], -1, 1)), math.atan2(r[3], r[9]), math.atan2(r[4], r[5])
		end
	elseif k == "Lerp" then
		return function(a, b, t)
			local w1, x1, y1, z1 = toQuat(a._r)
			local w2, x2, y2, z2 = toQuat(b._r)
			local d = w1 * w2 + x1 * x2 + y1 * y2 + z1 * z2
			if d < 0 then w2, x2, y2, z2, d = -w2, -x2, -y2, -z2, -d end
			local w, x, y, z
			if d > 0.9995 then
				w, x, y, z = w1 + (w2 - w1) * t, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, z1 + (z2 - z1) * t
			else
				local th = math.acos(d)
				local s1, s2 = math.sin((1 - t) * th) / math.sin(th), math.sin(t * th) / math.sin(th)
				w, x, y, z = w1 * s1 + w2 * s2, x1 * s1 + x2 * s2, y1 * s1 + y2 * s2, z1 * s1 + z2 * s2
			end
			return mkcf(a._p:Lerp(b._p, t), fromQuat(w, x, y, z))
		end
	end
	error("CFrame has no member " .. tostring(k), 2)
end
CFmt.__mul = function(a, b)
	assert(isCF(a), "CFrame mul lhs")
	if isCF(b) then return mkcf(a._p + mulRV(a._r, b._p), mulR(a._r, b._r)) end
	if isV(b) then return a._p + mulRV(a._r, b) end
	error("CFrame * " .. typeof(b), 2)
end
CFmt.__add = function(a, v) assert(isCF(a) and isV(v), "CFrame + Vector3") return mkcf(a._p + v, a._r) end
CFmt.__sub = function(a, v) assert(isCF(a) and isV(v), "CFrame - Vector3") return mkcf(a._p - v, a._r) end
CFmt.__tostring = function(c) return "CF" .. tostring(c._p) end

--..Color3 / Enum / Random..--
local C3mt = {__type = "Color3"}
local Color3 = {
	fromRGB = function(r, g, b) return setmetatable({R = r / 255, G = g / 255, B = b / 255}, C3mt) end,
	new = function(r, g, b) return setmetatable({R = r, G = g, B = b}, C3mt) end,
}
local function enumNode(path)
	return setmetatable({}, {__index = function(t, k)
		local n = enumNode(path .. "." .. k)
		rawset(t, k, n)
		return n
	end, __tostring = function() return path end})
end
local Enum = enumNode("Enum")
math.randomseed(7)
local Random = {new = function()
	return {
		NextNumber = function(_, a, b) a, b = a or 0, b or 1 return a + (b - a) * math.random() end,
		NextInteger = function(_, a, b) return math.random(a, b) end,
	}
end}

--..Signals..--
local function Signal()
	local s = {_fns = {}}
	function s:Connect(fn)
		table.insert(self._fns, fn)
		return {Disconnect = function() for i, f in ipairs(s._fns) do if f == fn then table.remove(s._fns, i) break end end end}
	end
	function s:Fire(...) for _, f in ipairs(table.clone(self._fns)) do f(...) end end
	return s
end

--..Instances..--
local PARENT_CLASS = {Part = "BasePart", MeshPart = "BasePart", Seat = "BasePart", WedgePart = "BasePart",
	BasePart = "PVInstance", Model = "PVInstance", PVInstance = "Instance", Camera = "Instance", Folder = "Instance",
	Sound = "Instance", SpecialMesh = "Instance", Attachment = "Instance", ModuleScript = "Instance", Workspace = "Model",
	Humanoid = "Instance", ProximityPrompt = "Instance", Player = "Instance"}
local InstMT = {__type = "Instance"}
local Methods = {}
local function newInstance(class)
	local o = setmetatable({_class = class, _props = {Name = class}, _children = {}, _attrs = {}, _attrSig = {}, _propSig = {}}, InstMT)
	local c = class
	local isPart = false
	while c do if c == "BasePart" then isPart = true end c = PARENT_CLASS[c] end
	if isPart then
		local p = o._props
		p.CFrame, p.Size, p.Transparency, p.LocalTransparencyModifier = CFrame.identity, v3(4, 1, 2), 0, 0
		p.Color, p.AssemblyLinearVelocity, p.Anchored, p.CanCollide = Color3.fromRGB(163, 162, 165), Vector3.zero, false, true
	end
	return o
end
InstMT.__index = function(o, k)
	local m = Methods[k]
	if m then return m end
	if k == "Parent" then return rawget(o, "_parent") end
	if k == "ClassName" then return o._class end
	if k == "Position" and o._props.CFrame then return o._props.CFrame.Position end
	local v = o._props[k]
	if v ~= nil then return v end
	for _, ch in ipairs(o._children) do if ch._props.Name == k then return ch end end
	return nil
end
InstMT.__newindex = function(o, k, v)
	if k == "Parent" then
		assert(not rawget(o, "_destroyed"), "Parent of a destroyed instance")
		local old = rawget(o, "_parent")
		if old then for i, ch in ipairs(old._children) do if ch == o then table.remove(old._children, i) break end end end
		rawset(o, "_parent", v)
		if v then table.insert(v._children, o) end
		return
	end
	if k == "Position" then o._props.CFrame = CFrame.new(v) * o._props.CFrame.Rotation return end
	if k == "CFrame" then assert(isCF(v), "CFrame must be a CFrame, got " .. typeof(v)) end
	if k == "Transparency" then assert(type(v) == "number" and v == v, "Transparency NaN") end
	o._props[k] = v
	local sig = o._propSig[k]
	if sig then sig:Fire() end
end
InstMT.__tostring = function(o) return o._props.Name end
function Methods.IsA(o, cls) local c = o._class while c do if c == cls then return true end c = PARENT_CLASS[c] end return false end
function Methods.GetChildren(o) return table.clone(o._children) end
function Methods.GetDescendants(o)
	local out = {}
	local function walk(x) for _, ch in ipairs(x._children) do table.insert(out, ch) walk(ch) end end
	walk(o)
	return out
end
function Methods.FindFirstChild(o, name, rec)
	for _, ch in ipairs(o._children) do if ch._props.Name == name then return ch end end
	if rec then for _, ch in ipairs(o._children) do local f = Methods.FindFirstChild(ch, name, true) if f then return f end end end
	return nil
end
function Methods.WaitForChild(o, name) local c = Methods.FindFirstChild(o, name) assert(c, "WaitForChild " .. name) return c end
function Methods.FindFirstChildOfClass(o, cls) for _, ch in ipairs(o._children) do if ch._class == cls then return ch end end return nil end
function Methods.FindFirstChildWhichIsA(o, cls) for _, ch in ipairs(o._children) do if Methods.IsA(ch, cls) then return ch end end return nil end
function Methods.IsDescendantOf(o, anc) local p = rawget(o, "_parent") while p do if p == anc then return true end p = rawget(p, "_parent") end return false end
function Methods.GetAttribute(o, k) return o._attrs[k] end
function Methods.SetAttribute(o, k, v) o._attrs[k] = v local s = o._attrSig[k] if s then s:Fire() end end
function Methods.GetAttributes(o) return table.clone(o._attrs) end
function Methods.GetAttributeChangedSignal(o, k) o._attrSig[k] = o._attrSig[k] or Signal() return o._attrSig[k] end
function Methods.GetPropertyChangedSignal(o, k) o._propSig[k] = o._propSig[k] or Signal() return o._propSig[k] end
function Methods.Destroy(o)
	for _, ch in ipairs(table.clone(o._children)) do Methods.Destroy(ch) end
	if rawget(o, "_parent") then o.Parent = nil end
	rawset(o, "_destroyed", true)
end
function Methods.Play(o) table.insert(SIM.Plays, {Name = o._props.SoundId or o._props.Name, Volume = o._props.Volume, Speed = o._props.PlaybackSpeed, T = SIM.Now}) end
function Methods.Stop() end
function Methods.GetPivot(o) return o.PrimaryPart and o.PrimaryPart.CFrame or CFrame.identity end
function Methods.PivotTo(o, target)
	local pivot = Methods.GetPivot(o)
	local delta = target * pivot:Inverse()
	for _, d in ipairs(Methods.GetDescendants(o)) do
		if Methods.IsA(d, "BasePart") then d.CFrame = delta * d.CFrame end
	end
end
function Methods.GetServerTimeNow() return SIM.Now end
function Methods.BulkMoveTo(_, parts, cfs)
	assert(#parts == #cfs, "BulkMoveTo: " .. #parts .. " parts vs " .. #cfs .. " cframes")
	for i, p in ipairs(parts) do
		assert(Methods.IsA(p, "BasePart"), "BulkMoveTo: not a part")
		local c = cfs[i]
		assert(isCF(c), "BulkMoveTo: entry " .. i .. " is " .. typeof(c))
		local q = c.Position
		assert(q.X == q.X and q.Y == q.Y and q.Z == q.Z, "BulkMoveTo: NaN position for " .. p.Name)
		p._props.CFrame = c
	end
	SIM.Bulk = (SIM.Bulk or 0) + 1
end
function Methods.WorldToViewportPoint(cam, point)
	local l = cam.CFrame:PointToObjectSpace(point)
	local depth = -l.Z
	local vp = cam.ViewportSize
	local f = vp.Y / 2 / math.tan(math.rad(35))
	local x, y = vp.X / 2 + l.X / depth * f, vp.Y / 2 - l.Y / depth * f
	return v3(x, y, depth), depth > 0 and x >= 0 and x <= vp.X and y >= 0 and y <= vp.Y
end
function Methods.GetSunDirection() return SIM.Sun end
function Methods.GetPlayers(o) return SIM.PlayerList end
function Methods.GetTagged(_, tag) return SIM.Tags[tag] or {} end
function Methods.AddTag(_, inst, tag) SIM.Tags[tag] = SIM.Tags[tag] or {} table.insert(SIM.Tags[tag], inst) end
function Methods.IsServer() return SIM.IsServer == true end
function Methods.Sit(seat, hum) seat.Occupant = hum end

local Instance = {new = function(class, parent)
	local o = newInstance(class)
	if parent then o.Parent = parent end
	return o
end}

--..Services / game..--
local workspace = newInstance("Workspace")
workspace.Name = "Workspace"
local camera = newInstance("Camera")
camera.Name = "Camera"
camera.CFrame = CFrame.identity
camera.ViewportSize = v3(1280, 720, 0)
camera.Parent = workspace
workspace.CurrentCamera = camera
local services = {}
for _, n in ipairs({"Players", "ReplicatedStorage", "ServerStorage", "Lighting", "CollectionService", "RunService"}) do
	services[n] = newInstance(n)
	services[n].Name = n
end
services.RunService.RenderStepped = Signal()
services.RunService.Heartbeat = Signal()
local modulesFolder = newInstance("Folder")
modulesFolder.Name = "Modules"
modulesFolder.Parent = services.ReplicatedStorage
for _, n in ipairs({"FunBuildKit", "FunAssets"}) do
	local m = newInstance("ModuleScript")
	m.Name = n
	m.Parent = modulesFolder
end
local localPlayer = newInstance("Player")
localPlayer.Name = "Tester"
localPlayer.UserId = 1
services.Players.LocalPlayer = localPlayer
SIM.PlayerList = {localPlayer}
local game = {GetService = function(_, n) return assert(services[n], "service " .. n) end}
local task = {spawn = function(f, ...) f(...) end, wait = function() end, delay = function() end, defer = function(f, ...) f(...) end}
local os = setmetatable({clock = function() return SIM.Clock end}, {__index = os})
local warn = function(...) print("WARN", ...) SIM.Warns = (SIM.Warns or 0) + 1 end
local __modules = {}
local function __require(m)
	local name = typeof(m) == "table" and m.Name or m
	return assert(__modules[name], "module " .. tostring(name))
end
local function __typeof(v)
	local mt = getmetatable(v)
	if type(v) == "table" and mt and mt.__type then return mt.__type end
	return typeof(v)
end
