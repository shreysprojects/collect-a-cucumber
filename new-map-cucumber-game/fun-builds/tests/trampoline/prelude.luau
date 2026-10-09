-- Minimal Roblox mocks for an offline run of the Trampoline behaviour (scratch harness).
local SIM = {t = 1000, held = false, raycasts = 0}
local realOs = os
local os = setmetatable({clock = function() return SIM.t end}, {__index = realOs})
local function warn(...) print("WARN", ...) end

--..Vector3..--
local V3 = {}
local Vector3 = {}
local function vnew(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, _t = "Vector3"}, V3) end
Vector3.new = vnew
Vector3.zero = vnew(0, 0, 0)
Vector3.yAxis = vnew(0, 1, 0)
V3.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) return vnew(v.X / m, v.Y / m, v.Z / m) end
	return rawget(V3, k)
end
V3.__add = function(a, b) return vnew(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return vnew(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a) return vnew(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return vnew(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return vnew(a.X * b, a.Y * b, a.Z * b) end
	return vnew(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b) return vnew(a.X / b, a.Y / b, a.Z / b) end
V3.__tostring = function(v) return string.format("(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z) end
V3.Dot = function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end

--..CFrame (R row-major 1..9)..--
local CF = {}
local CFrame = {}
local function cfraw(p, R) return setmetatable({p = p, R = R, _t = "CFrame"}, CF) end
local I3 = {1, 0, 0, 0, 1, 0, 0, 0, 1}
local function matmul(A, B)
	local C = {}
	for i = 0, 2 do
		for j = 1, 3 do
			C[i * 3 + j] = A[i * 3 + 1] * B[j] + A[i * 3 + 2] * B[3 + j] + A[i * 3 + 3] * B[6 + j]
		end
	end
	return C
end
local function matvec(A, v)
	return vnew(A[1] * v.X + A[2] * v.Y + A[3] * v.Z, A[4] * v.X + A[5] * v.Y + A[6] * v.Z, A[7] * v.X + A[8] * v.Y + A[9] * v.Z)
end
local function transpose(A) return {A[1], A[4], A[7], A[2], A[5], A[8], A[3], A[6], A[9]} end
CFrame.new = function(a, b, c)
	if a == nil then return cfraw(vnew(), I3) end
	if type(a) == "table" then return cfraw(a, I3) end
	return cfraw(vnew(a, b, c), I3)
end
CFrame.identity = CFrame.new()
CFrame.fromMatrix = function(p, x, y, z)
	return cfraw(p, {x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z})
end
CFrame.Angles = function(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local Rx = {1, 0, 0, 0, cx, -sx, 0, sx, cx}
	local Ry = {cy, 0, sy, 0, 1, 0, -sy, 0, cy}
	local Rz = {cz, -sz, 0, sz, cz, 0, 0, 0, 1}
	return cfraw(vnew(), matmul(matmul(Rx, Ry), Rz))
end
CF.__index = function(cf, k)
	local R = cf.R
	if k == "Position" then return cf.p end
	if k == "Rotation" then return cfraw(vnew(), R) end
	if k == "RightVector" then return vnew(R[1], R[4], R[7]) end
	if k == "UpVector" then return vnew(R[2], R[5], R[8]) end
	if k == "LookVector" then return vnew(-R[3], -R[6], -R[9]) end
	if k == "X" then return cf.p.X end
	if k == "Y" then return cf.p.Y end
	if k == "Z" then return cf.p.Z end
	return rawget(CF, k)
end
CF.__mul = function(a, b)
	if b._t == "Vector3" then return a.p + matvec(a.R, b) end
	return cfraw(a.p + matvec(a.R, b.p), matmul(a.R, b.R))
end
CF.__add = function(a, v) return cfraw(a.p + v, a.R) end
CF.Inverse = function(a)
	local Rt = transpose(a.R)
	return cfraw(-matvec(Rt, a.p), Rt)
end
CF.ToObjectSpace = function(a, b) return a:Inverse() * b end
CF.PointToWorldSpace = function(a, v) return a * v end
CF.PointToObjectSpace = function(a, v) return a:Inverse() * v end
CF.__tostring = function(a) return "CF" .. tostring(a.p) end

--..Misc value types..--
local function box(t) return function(...) return {_t = t, ...} end end
local ColorSequence = {new = box("ColorSequence")}
local NumberSequence = {new = box("NumberSequence")}
local NumberSequenceKeypoint = {new = box("NumberSequenceKeypoint")}
local NumberRange = {new = box("NumberRange")}
local Vector2 = {new = box("Vector2")}
local Color3 = {fromRGB = box("Color3")}
local RaycastParams = {new = function() return {} end}
local function typeof(v)
	if type(v) == "table" and v._t then return v._t end
	if type(v) == "table" and v._isInst then return "Instance" end
	return type(v)
end

--..Enum..--
local Enum = setmetatable({}, {__index = function(_, cat)
	return setmetatable({}, {__index = function(_, item) return cat .. "." .. item end})
end})

--..Signals..--
local function Signal()
	local s = {handlers = {}}
	function s:Connect(fn)
		local c = {fn = fn, on = true}
		table.insert(s.handlers, c)
		function c:Disconnect() c.on = false end
		return c
	end
	function s:Fire(...)
		for _, c in ipairs(s.handlers) do if c.on then c.fn(...) end end
	end
	function s:Count() local n = 0 for _, c in ipairs(s.handlers) do if c.on then n += 1 end end return n end
	return s
end

--..Instances..--
local Inst = {}
local InstMT = {}
local ISA = {
	Part = {BasePart = true}, MeshPart = {BasePart = true},
}
local function new(class, props)
	local o = setmetatable({_isInst = true, _class = class, _p = {Name = class}, _children = {}, _attrs = {}}, InstMT)
	for k, v in pairs(props or {}) do o[k] = v end
	return o
end
InstMT.__index = function(self, k)
	local p = rawget(self, "_p")
	if k == "Position" and p.CFrame then return p.CFrame.Position end
	if k == "ClassName" then return rawget(self, "_class") end
	if p[k] ~= nil then return p[k] end
	if Inst[k] then return Inst[k] end
	for _, c in ipairs(rawget(self, "_children")) do if c.Name == k then return c end end
	return nil
end
InstMT.__newindex = function(self, k, v)
	local p = rawget(self, "_p")
	if k == "Parent" then
		local old = p.Parent
		if old then
			for i, c in ipairs(rawget(old, "_children")) do if c == self then table.remove(rawget(old, "_children"), i) break end end
		end
		p.Parent = v
		if v then table.insert(rawget(v, "_children"), self) end
		return
	end
	if k == "Position" then p.CFrame = CFrame.new(v) * (p.CFrame and p.CFrame.Rotation or CFrame.new()) return end
	if rawget(self, "_class") == "Sound" and k == "SoundId" then p[k] = v return end
	p[k] = v
end
function Inst:IsA(c) return rawget(self, "_class") == c or (ISA[rawget(self, "_class")] or {})[c] == true end
function Inst:FindFirstChild(name, rec)
	for _, c in ipairs(rawget(self, "_children")) do
		if c.Name == name then return c end
		if rec then local r = c:FindFirstChild(name, true) if r then return r end end
	end
	return nil
end
function Inst:WaitForChild(name) return self:FindFirstChild(name) end
function Inst:FindFirstChildOfClass(cls)
	for _, c in ipairs(rawget(self, "_children")) do if rawget(c, "_class") == cls then return c end end
	return nil
end
function Inst:GetChildren() return table.clone(rawget(self, "_children")) end
function Inst:GetDescendants()
	local out = {}
	local function walk(o) for _, c in ipairs(rawget(o, "_children")) do table.insert(out, c) walk(c) end end
	walk(self)
	return out
end
function Inst:GetAttribute(k) return rawget(self, "_attrs")[k] end
function Inst:SetAttribute(k, v) rawget(self, "_attrs")[k] = v end
function Inst:GetFullName() return self.Name end
function Inst:Destroy() self.Parent = nil rawget(self, "_p").Destroyed = true end
function Inst:Play() rawget(self, "_p").Plays = (rawget(self, "_p").Plays or 0) + 1 table.insert(SIM.sounds, {name = self.Name, speed = self.PlaybackSpeed, t = SIM.t}) end
function Inst:Emit(n) rawget(self, "_p").Emitted = (rawget(self, "_p").Emitted or 0) + n end
-- Humanoid
function Inst:GetState() return rawget(self, "_p").State or "HumanoidStateType.Running" end
function Inst:GetStateEnabled() return true end
function Inst:ChangeState(s) rawget(self, "_p").PendingState = s end
local Instance = {new = function(class) return new(class) end}

--..Services / world..--
local workspace = new("Workspace", {Gravity = 196.2})
workspace.CurrentCamera = new("Camera", {Parent = workspace, CFrame = CFrame.new(0, 0, 0)})
function workspace:GetServerTimeNow() return SIM.t end
local RAYCAST = nil -- set by the test
function workspace:Raycast(origin, dir, params)
	SIM.raycasts += 1
	return RAYCAST(origin, dir, params)
end
local RunService = {Stepped = Signal(), RenderStepped = Signal(), Heartbeat = Signal()}
function RunService:IsServer() return false end
local UserInputService = {TouchEnabled = false, KeyboardEnabled = true}
function UserInputService:GetFocusedTextBox() return nil end
function UserInputService:IsKeyDown(k) return SIM.held and k == "KeyCode.Space" end
function UserInputService:IsGamepadButtonDown() return false end
local ReplicatedStorage = new("ReplicatedStorage")
local Modules = new("Folder", {Name = "Modules", Parent = ReplicatedStorage})
local KitScript = new("ModuleScript", {Name = "FunBuildKit", Parent = Modules})
local AssetsScript = new("ModuleScript", {Name = "FunAssets", Parent = Modules})
local PlayersList = {}
local Players = {}
function Players:GetPlayers() return table.clone(PlayersList) end
local services = {Players = Players, ReplicatedStorage = ReplicatedStorage, RunService = RunService, UserInputService = UserInputService, Workspace = workspace}
local game = {}
function game:GetService(n) return services[n] end
local function require(m) return rawget(m, "_p").Module end
SIM.sounds = {}
