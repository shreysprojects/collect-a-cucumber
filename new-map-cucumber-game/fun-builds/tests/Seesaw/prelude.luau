--!nolint
-- Seesaw offline harness: stubs (Vector3 / CFrame / Instances / services) so the REAL module sources run in the luau CLI
local SIM_T = 0
local NOW = 1000
local os = {clock = function() return SIM_T end, time = function() return 0 end}

--..Vector3..--
local V3 = {}
local V3m = {}
local function v3(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, V3) end
V3.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		return v3(t.X / m, t.Y / m, t.Z / m)
	end
	return V3m[k]
end
V3.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b) return v3(a.X / b, a.Y / b, a.Z / b) end
V3.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(a) return string.format("(%.4f, %.4f, %.4f)", a.X, a.Y, a.Z) end
function V3m.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3m.Cross(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local Vector3 = {new = v3, zero = v3(0, 0, 0), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1), one = v3(1, 1, 1)}

--..CFrame (row-major 3x3 + position)..--
local CF = {}
local CFm = {}
local function cf(p, m) return setmetatable({p = p, m = m}, CF) end
local ID = {1, 0, 0, 0, 1, 0, 0, 0, 1}
local function mulm(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local s = 0
			for k = 0, 2 do s += a[i * 3 + k + 1] * b[k * 3 + j + 1] end
			r[i * 3 + j + 1] = s
		end
	end
	return r
end
local function mulv(m, v) return v3(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z) end
local function tr(m) return {m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9]} end
CF.__index = function(t, k)
	if k == "Position" then return t.p end
	if k == "Rotation" then return cf(v3(0, 0, 0), t.m) end
	if k == "RightVector" or k == "XVector" then return v3(t.m[1], t.m[4], t.m[7]) end
	if k == "UpVector" or k == "YVector" then return v3(t.m[2], t.m[5], t.m[8]) end
	if k == "ZVector" then return v3(t.m[3], t.m[6], t.m[9]) end
	if k == "LookVector" then return v3(-t.m[3], -t.m[6], -t.m[9]) end
	return CFm[k]
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then return a.p + mulv(a.m, b) end
	return cf(a.p + mulv(a.m, b.p), mulm(a.m, b.m))
end
CF.__eq = function(a, b)
	if not (a.p == b.p) then return false end
	for i = 1, 9 do if a.m[i] ~= b.m[i] then return false end end
	return true
end
function CFm.Inverse(a) local mt = tr(a.m) return cf(-mulv(mt, a.p), mt) end
function CFm.ToObjectSpace(a, b) return a:Inverse() * b end
function CFm.PointToWorldSpace(a, v) return a * v end
function CFm.PointToObjectSpace(a, v) return a:Inverse() * v end
function CFm.VectorToWorldSpace(a, v) return mulv(a.m, v) end
function CFm.VectorToObjectSpace(a, v) return mulv(tr(a.m), v) end
local CFrame = {}
function CFrame.new(x, y, z)
	if x == nil then return cf(v3(), ID) end
	if type(x) == "table" then return cf(x, ID) end
	return cf(v3(x, y, z), ID)
end
local function rx(a) local c, s = math.cos(a), math.sin(a) return {1, 0, 0, 0, c, -s, 0, s, c} end
local function ry(a) local c, s = math.cos(a), math.sin(a) return {c, 0, s, 0, 1, 0, -s, 0, c} end
local function rz(a) local c, s = math.cos(a), math.sin(a) return {c, -s, 0, s, c, 0, 0, 0, 1} end
function CFrame.Angles(a, b, c) return cf(v3(), mulm(mulm(rx(a), ry(b)), rz(c))) end
function CFrame.fromMatrix(p, x, y, z)
	z = z or x:Cross(y).Unit
	return cf(p, {x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z})
end
function CFrame.lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up).Unit
	local up2 = right:Cross(look)
	return CFrame.fromMatrix(at, right, up2, -look)
end
CFrame.identity = CFrame.new()

local function typeof(x)
	local mt = getmetatable(x)
	if mt == V3 then return "Vector3" end
	if mt == CF then return "CFrame" end
	if type(x) == "table" and rawget(x, "_isInstance") then return "Instance" end
	return type(x)
end

local Random = {new = function() return {NextNumber = function(_, a, b) return (a + b) / 2 end} end}

--..Signals / instances..--
local function Signal()
	local s = {_fns = {}}
	function s:Connect(fn)
		table.insert(self._fns, fn)
		local c = {}
		function c.Disconnect() end
		return c
	end
	function s:Fire(...) for _, f in ipairs(self._fns) do f(...) end end
	return s
end

local function Part(name, class, cframe, size)
	local p = {_isInstance = true, Name = name, ClassName = class or "MeshPart", CFrame = cframe, Size = size or v3(1, 1, 1), Parent = true, _attrs = {}, AttributeChanged = Signal(), _props = {}}
	function p:IsA(c) return c == "BasePart" or c == self.ClassName end
	function p:GetAttribute(k) return self._attrs[k] end
	function p:SetAttribute(k, v) self._attrs[k] = v self.AttributeChanged:Fire(k) end
	function p:GetPropertyChangedSignal(prop)
		self._props[prop] = self._props[prop] or Signal()
		return self._props[prop]
	end
	return p
end

--..Services..--
local Tags = {}
local TagAdded = {}
local CollectionService = {}
function CollectionService:AddTag(inst, tag)
	Tags[tag] = Tags[tag] or {}
	table.insert(Tags[tag], inst)
	if TagAdded[tag] then TagAdded[tag]:Fire(inst) end
end
function CollectionService:GetTagged(tag) return Tags[tag] or {} end
function CollectionService:GetInstanceAddedSignal(tag)
	TagAdded[tag] = TagAdded[tag] or Signal()
	return TagAdded[tag]
end
local Players = {}
function Players:GetPlayerFromCharacter(char) return char and char._player end
local RunService = {}
function RunService:IsServer() return true end
local Modules = {FunBuildKit = {}, FunAssets = {}}
function Modules:WaitForChild(n) return self[n] end
local ReplicatedStorage = {Modules = Modules}
function ReplicatedStorage:WaitForChild(n) return self[n] end
function ReplicatedStorage:FindFirstChild(n) return nil end
local game = {}
function game:GetService(n)
	if n == "CollectionService" then return CollectionService end
	if n == "Players" then return Players end
	if n == "RunService" then return RunService end
	if n == "ReplicatedStorage" then return ReplicatedStorage end
	error("no service " .. n)
end
local workspace = {}
function workspace:GetServerTimeNow() return NOW end
local require = function(x) return x.__module end
