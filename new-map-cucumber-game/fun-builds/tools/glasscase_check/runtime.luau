-- Mock Roblox runtime (after shim.luau): Instances, signals, Enum, task, Random, workspace, typeof.
local SHIM_VEC_MT = getmetatable(Vector3.new(0, 0, 0))
local SHIM_CF_MT = getmetatable(CFrame.new())
local SHIM_C3_MT = getmetatable(Color3.new(0, 0, 0))
typeof = function(v)
	local mt = getmetatable(v)
	if mt == SHIM_VEC_MT then return "Vector3" end
	if mt == SHIM_CF_MT then return "CFrame" end
	if mt == SHIM_C3_MT then return "Color3" end
	if type(v) == "table" and rawget(v, "__inst") then return "Instance" end
	return type(v)
end
SHIM_CF_MT.__index = function(cf, k)
	if k == "Position" then return rawget(cf, "p") end
	if k == "Rotation" then return CFrame.fromMatrix(Vector3.new(0, 0, 0), Vector3.new(rawget(cf, "r")[1][1], rawget(cf, "r")[2][1], rawget(cf, "r")[3][1]), Vector3.new(rawget(cf, "r")[1][2], rawget(cf, "r")[2][2], rawget(cf, "r")[3][2]), Vector3.new(rawget(cf, "r")[1][3], rawget(cf, "r")[2][3], rawget(cf, "r")[3][3])) end
	if k == "Inverse" then
		return function(c)
			local r, p = rawget(c, "r"), rawget(c, "p")
			local rt = {{r[1][1], r[2][1], r[3][1]}, {r[1][2], r[2][2], r[3][2]}, {r[1][3], r[2][3], r[3][3]}}
			local ip = Vector3.new(-(rt[1][1] * p.X + rt[1][2] * p.Y + rt[1][3] * p.Z), -(rt[2][1] * p.X + rt[2][2] * p.Y + rt[2][3] * p.Z), -(rt[3][1] * p.X + rt[3][2] * p.Y + rt[3][3] * p.Z))
			return CFrame.fromMatrix(ip, Vector3.new(rt[1][1], rt[2][1], rt[3][1]), Vector3.new(rt[1][2], rt[2][2], rt[3][2]), Vector3.new(rt[1][3], rt[2][3], rt[3][3]))
		end
	end
	if k == "PointToWorldSpace" then return function(c, v) return c * v end end
	if k == "LookVector" then local r = rawget(cf, "r"); return Vector3.new(-r[1][3], -r[2][3], -r[3][3]) end
	return nil
end
if not math.noise then math.noise = function() return 0 end end
warn = function(...) print("WARN", ...) end

Enum = setmetatable({}, {__index = function(_, cat)
	return setmetatable({}, {__index = function(_, item) return "Enum." .. cat .. "." .. item end})
end})

local function simple(kind) return function(...) return {__kind = kind, ...} end end
Vector2 = {new = simple("Vector2")}
UDim2 = {new = simple("UDim2"), fromScale = simple("UDim2"), fromOffset = simple("UDim2")}
UDim = {new = simple("UDim")}
NumberRange = {new = simple("NumberRange")}
NumberSequence = {new = simple("NumberSequence")}
NumberSequenceKeypoint = {new = simple("NumberSequenceKeypoint")}
ColorSequence = {new = simple("ColorSequence")}

DELAYED = {}
task = {
	spawn = function(f, ...) f(...) end,
	defer = function(f, ...) f(...) end,
	delay = function(t, f, ...) table.insert(DELAYED, {t, f, ...}) end,
	wait = function() return 0 end,
}

Random = {new = function(seed)
	local state = math.floor(seed) % 2147483647
	if state <= 0 then state += 2147483646 end
	local r = {}
	function r:NextNumber(a, b)
		state = (state * 48271) % 2147483647
		local u = state / 2147483647
		if a then return a + (b - a) * u end
		return u
	end
	function r:NextInteger(a, b) return a + math.floor(self:NextNumber() * (b - a + 1)) end
	return r
end}

function Signal()
	local s = {_fns = {}}
	function s:Connect(fn)
		table.insert(self._fns, fn)
		return {Disconnect = function()
			for i, f in ipairs(s._fns) do if f == fn then table.remove(s._fns, i) break end end
		end}
	end
	function s:Fire(...)
		for _, f in ipairs(table.clone(self._fns)) do f(...) end
	end
	return s
end

local IS = {
	Part = {BasePart = true}, WedgePart = {BasePart = true}, MeshPart = {BasePart = true},
	Seat = {BasePart = true}, Model = {PVInstance = true},
}
local DEFAULTS = {
	Part = {Size = Vector3.new(4, 1, 2), Transparency = 0, Reflectance = 0, Material = "Enum.Material.Plastic", CanCollide = true, Anchored = false},
	WedgePart = {Size = Vector3.new(4, 1, 2), Transparency = 0, Reflectance = 0, Material = "Enum.Material.Plastic", CanCollide = true},
	MeshPart = {Transparency = 0, Reflectance = 0, CanCollide = true},
	Sound = {Volume = 0.5, PlaybackSpeed = 1, TimePosition = 0},
	ParticleEmitter = {Enabled = true},
	PointLight = {Brightness = 1, Enabled = true, Range = 8},
	SpotLight = {Brightness = 1, Enabled = true, Range = 16},
	ProximityPrompt = {MaxActivationDistance = 10, Enabled = true, UIOffset = Vector2.new(0, 0)},
}
local LAZY_SIGNALS = {DescendantAdded = true, ChildAdded = true, AncestryChanged = true, Triggered = true, Changed = true}
local Methods = {}
local InstMT = {}
InstMT.__index = function(o, k)
	if k == "Parent" then return rawget(o, "_parent") end
	if k == "Position" then local cf = rawget(o, "CFrame"); return cf and cf.Position end
	if LAZY_SIGNALS[k] then local s = Signal(); rawset(o, k, s); return s end
	return Methods[k]
end
InstMT.__newindex = function(o, k, v)
	if rawget(o, "_destroyed") and k ~= "Parent" then error("write to destroyed " .. tostring(rawget(o, "Name")) .. "." .. k) end
	if k == "Parent" then
		local old = rawget(o, "_parent")
		if old then
			for i, c in ipairs(old._children) do if c == o then table.remove(old._children, i) break end end
		end
		rawset(o, "_parent", v)
		if v then
			table.insert(v._children, o)
			local a = v
			while a do
				local sig = rawget(a, "DescendantAdded")
				if sig then sig:Fire(o) end
				a = rawget(a, "_parent")
			end
		end
		return
	end
	if k == "Shape" and v == "Enum.PartType.Ball" then rawset(o, "_ball", true) end
	rawset(o, k, v)
	WRITES += 1
end
WRITES = 0
Instance = {new = function(class)
	local o = {__inst = true, ClassName = class, Name = class, _children = {}, _attrs = {}, _attrSig = {}}
	for k, v in pairs(DEFAULTS[class] or {}) do o[k] = v end
	return setmetatable(o, InstMT)
end}
function Methods:IsA(c) return self.ClassName == c or (IS[self.ClassName] and IS[self.ClassName][c]) or c == "Instance" end
function Methods:GetChildren() return table.clone(self._children) end
function Methods:GetDescendants()
	local out = {}
	local function walk(o) for _, c in ipairs(o._children) do table.insert(out, c); walk(c) end end
	walk(self)
	return out
end
function Methods:FindFirstChild(name, recursive)
	for _, c in ipairs(recursive and self:GetDescendants() or self._children) do if c.Name == name then return c end end
	return nil
end
function Methods:FindFirstChildOfClass(cls)
	for _, c in ipairs(self._children) do if c.ClassName == cls then return c end end
	return nil
end
function Methods:GetAttribute(k) return self._attrs[k] end
function Methods:SetAttribute(k, v)
	self._attrs[k] = v
	local s = self._attrSig[k]
	if s then s:Fire() end
end
function Methods:GetAttributeChangedSignal(k)
	self._attrSig[k] = self._attrSig[k] or Signal()
	return self._attrSig[k]
end
function Methods:GetPropertyChangedSignal() return Signal() end
function Methods:Destroy()
	self.Parent = nil
	rawset(self, "_destroyed", true)
	for _, c in ipairs(table.clone(self._children)) do c:Destroy() end
end
function Methods:Play() rawset(self, "_plays", (rawget(self, "_plays") or 0) + 1) end
function Methods:Stop() end
function Methods:Emit(n) rawset(self, "_emitted", (rawget(self, "_emitted") or 0) + n) end

workspace = Instance.new("Workspace")
NOW = 1790000000.25
rawset(workspace, "GetServerTimeNow", function() return NOW end)
rawset(workspace, "BulkMoveTo", function(_, parts, cfs)
	assert(#parts == #cfs, "BulkMoveTo length mismatch")
	for i, p in ipairs(parts) do
		assert(not rawget(p, "_destroyed"), "BulkMoveTo on a destroyed part")
		rawset(p, "CFrame", cfs[i])
	end
end)
workspace:SetAttribute("CyclePhase", "Night")

local function svc(name)
	local o = {Name = name}
	o.WaitForChild = function(_, child) return svc(child) end
	o.FindFirstChild = function() return nil end
	o.IsServer = function() return false end
	o.GetPlayerByUserId = function() return nil end
	o.GetNameFromUserIdAsync = function(_, id) return "Cucumbers" end
	return o
end
game = {GetService = function(_, name) return svc(name) end}
