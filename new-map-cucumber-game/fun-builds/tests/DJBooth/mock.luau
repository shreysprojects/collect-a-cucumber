-- Minimal Roblox mock runtime for offline behaviour tests (fun-builds DJBooth package). SRC is injected above.
local M = {}
local SIM = {now = 0, errors = 0, warns = {}, unknownReads = {}}
M.SIM = SIM

--..Signals..--
local SignalMT = {}
SignalMT.__index = SignalMT
local function Signal()
	return setmetatable({fns = {}, __kind = "RBXScriptSignal"}, SignalMT)
end
function SignalMT:Connect(fn)
	local c = {Connected = true, fn = fn}
	function c:Disconnect() c.Connected = false end
	table.insert(self.fns, c)
	return c
end
function SignalMT:Once(fn)
	local c
	c = self:Connect(function(...) c:Disconnect() fn(...) end)
	return c
end
function SignalMT:Fire(...)
	for _, c in ipairs(table.clone(self.fns)) do
		if c.Connected then
			local ok, err = pcall(c.fn, ...)
			if not ok then SIM.errors += 1 print("!! SIGNAL HANDLER ERROR: " .. tostring(err)) end
		end
	end
end
function SignalMT:Wait() return coroutine.yield() end
M.Signal = Signal

--..Scheduler..--
local waiting = {}
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		SIM.errors += 1
		print("!! COROUTINE ERROR: " .. tostring(err))
		print(debug.traceback(co))
	end
end
local task = {}
function task.spawn(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	table.insert(waiting, {co = co, at = SIM.now, args = table.pack(...)})
	return co
end
function task.delay(t, f, ...)
	local co = coroutine.create(f)
	table.insert(waiting, {co = co, at = SIM.now + (t or 0), args = table.pack(...)})
	return co
end
function task.wait(t)
	local co = coroutine.running()
	table.insert(waiting, {co = co, at = SIM.now + (t or 0), args = table.pack()})
	coroutine.yield()
	return t or 0
end
M.task = task
function M.RunDue()
	local guard = 0
	while true do
		guard += 1
		if guard > 10000 then error("scheduler runaway") end
		local idx
		for i, w in ipairs(waiting) do
			if w.at <= SIM.now + 1e-9 and (not idx or w.at < waiting[idx].at) then idx = i end
		end
		if not idx then return end
		local w = table.remove(waiting, idx)
		if coroutine.status(w.co) == "suspended" then resume(w.co, table.unpack(w.args, 1, w.args.n)) end
	end
end

--..Vector3 / Vector2..--
local V3MT = {}
local function V3(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, __kind = "Vector3"}, V3MT) end
V3MT.__add = function(a, b) return V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3MT.__sub = function(a, b) return V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3MT.__unm = function(a) return V3(-a.X, -a.Y, -a.Z) end
V3MT.__mul = function(a, b)
	if type(a) == "number" then return V3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return V3(a.X * b, a.Y * b, a.Z * b) end
	return V3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3MT.__div = function(a, b)
	if type(b) == "number" then return V3(a.X / b, a.Y / b, a.Z / b) end
	return V3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3MT.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z) end
V3MT.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) return V3(t.X / m, t.Y / m, t.Z / m) end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
	if k == "Cross" then return function(a, b) return V3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
	if k == "Lerp" then return function(a, b, t2) return a + (b - a) * t2 end end
	error("Vector3." .. tostring(k) .. " is not a valid member")
end
local Vector3 = {new = V3, zero = V3(0, 0, 0), one = V3(1, 1, 1), xAxis = V3(1, 0, 0), yAxis = V3(0, 1, 0), zAxis = V3(0, 0, 1)}
M.Vector3 = Vector3
local Vector2 = {new = function(x, y) return {X = x or 0, Y = y or 0, __kind = "Vector2"} end}
Vector2.zero = Vector2.new(0, 0)
M.Vector2 = Vector2

--..CFrame..--
local CFMT = {}
local function CF(px, py, pz, r)
	return setmetatable({p = V3(px, py, pz), r = r or {1, 0, 0, 0, 1, 0, 0, 0, 1}, __kind = "CFrame"}, CFMT)
end
local function mulR(a, b)
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
local function rotV(r, v)
	return V3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
local function transpose(r) return {r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9]} end
CFMT.__mul = function(a, b)
	if getmetatable(b) == CFMT then
		local p = a.p + rotV(a.r, b.p)
		return CF(p.X, p.Y, p.Z, mulR(a.r, b.r))
	end
	if getmetatable(b) == V3MT then return a.p + rotV(a.r, b) end
	error("bad CFrame * operand")
end
CFMT.__add = function(a, v) local p = a.p + v return CF(p.X, p.Y, p.Z, a.r) end
CFMT.__eq = function(a, b)
	if a.p ~= b.p then return false end
	for i = 1, 9 do if a.r[i] ~= b.r[i] then return false end end
	return true
end
local CFMethods = {}
function CFMethods.Inverse(a)
	local rt = transpose(a.r)
	local p = -rotV(rt, a.p)
	return CF(p.X, p.Y, p.Z, rt)
end
function CFMethods.ToObjectSpace(a, b) return CFMethods.Inverse(a) * b end
function CFMethods.ToWorldSpace(a, b) return a * b end
function CFMethods.PointToObjectSpace(a, v) return rotV(transpose(a.r), v - a.p) end
function CFMethods.PointToWorldSpace(a, v) return a * v end
function CFMethods.VectorToWorldSpace(a, v) return rotV(a.r, v) end
function CFMethods.VectorToObjectSpace(a, v) return rotV(transpose(a.r), v) end
function CFMethods.Lerp(a, b, t) local p = a.p:Lerp(b.p, t) return CF(p.X, p.Y, p.Z, t < 0.5 and a.r or b.r) end
CFMT.__index = function(t, k)
	if CFMethods[k] then return CFMethods[k] end
	if k == "Position" then return t.p end
	if k == "Rotation" then return CF(0, 0, 0, t.r) end
	if k == "X" then return t.p.X elseif k == "Y" then return t.p.Y elseif k == "Z" then return t.p.Z end
	if k == "RightVector" then return V3(t.r[1], t.r[4], t.r[7]) end
	if k == "UpVector" then return V3(t.r[2], t.r[5], t.r[8]) end
	if k == "LookVector" then return V3(-t.r[3], -t.r[6], -t.r[9]) end
	error("CFrame." .. tostring(k) .. " is not a valid member")
end
CFMT.__tostring = function(a) return "CF" .. tostring(a.p) end
local function Rx(a) local c, s = math.cos(a), math.sin(a) return {1, 0, 0, 0, c, -s, 0, s, c} end
local function Ry(a) local c, s = math.cos(a), math.sin(a) return {c, 0, s, 0, 1, 0, -s, 0, c} end
local function Rz(a) local c, s = math.cos(a), math.sin(a) return {c, -s, 0, s, c, 0, 0, 0, 1} end
local CFrame = {}
function CFrame.new(x, y, z)
	if x == nil then return CF(0, 0, 0) end
	if type(x) == "table" then return CF(x.X, x.Y, x.Z) end
	return CF(x, y, z)
end
function CFrame.Angles(rx, ry, rz) return CF(0, 0, 0, mulR(mulR(Rx(rx), Ry(ry)), Rz(rz))) end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.lookAt(at, target, up)
	up = up or V3(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up).Unit
	local up2 = right:Cross(look)
	return CF(at.X, at.Y, at.Z, {right.X, up2.X, -look.X, right.Y, up2.Y, -look.Y, right.Z, up2.Z, -look.Z})
end
function CFrame.fromMatrix(pos, rx, ry, rz)
	rz = rz or rx:Cross(ry)
	return CF(pos.X, pos.Y, pos.Z, {rx.X, ry.X, rz.X, rx.Y, ry.Y, rz.Y, rx.Z, ry.Z, rz.Z})
end
CFrame.identity = CF(0, 0, 0)
M.CFrame = CFrame
M.IsCFrame = function(v) return getmetatable(v) == CFMT end

--..Color3..--
local C3MT = {}
local function C3(r, g, b) return setmetatable({R = r, G = g, B = b, __kind = "Color3"}, C3MT) end
C3MT.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
C3MT.__index = function(t, k)
	if k == "Lerp" then return function(a, b, x) return C3(a.R + (b.R - a.R) * x, a.G + (b.G - a.G) * x, a.B + (b.B - a.B) * x) end end
	if k == "ToHSV" then return function() return 0, 0, 0 end end
	error("Color3." .. tostring(k) .. " is not a valid member")
end
C3MT.__tostring = function(c) return string.format("C3(%d,%d,%d)", c.R * 255, c.G * 255, c.B * 255) end
local Color3 = {}
function Color3.new(r, g, b) return C3(r or 0, g or 0, b or 0) end
function Color3.fromRGB(r, g, b) return C3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHex(h)
	h = h:gsub("#", "")
	assert(#h == 6, "bad hex " .. h)
	return C3(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255)
end
function Color3.fromHSV(h, s, v)
	assert(h >= 0 and h <= 1 and s >= 0 and s <= 1 and v >= 0 and v <= 1, ("fromHSV out of range %s %s %s"):format(h, s, v))
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then return C3(v, t, p) elseif i == 1 then return C3(q, v, p) elseif i == 2 then return C3(p, v, t)
	elseif i == 3 then return C3(p, q, v) elseif i == 4 then return C3(t, p, v) end
	return C3(v, p, q)
end
M.Color3 = Color3

--..Small value types..--
M.UDim = {new = function(s, o) return {Scale = s, Offset = o, __kind = "UDim"} end}
M.UDim2 = {
	new = function(xs, xo, ys, yo) return {X = {Scale = xs or 0, Offset = xo or 0}, Y = {Scale = ys or 0, Offset = yo or 0}, __kind = "UDim2"} end,
}
M.UDim2.fromOffset = function(x, y) return M.UDim2.new(0, x, 0, y) end
M.UDim2.fromScale = function(x, y) return M.UDim2.new(x, 0, y, 0) end
M.NumberSequenceKeypoint = {new = function(t, v) return {Time = t, Value = v} end}
M.NumberSequence = {new = function(a, b) return {Keypoints = a, __kind = "NumberSequence"} end}
M.ColorSequenceKeypoint = {new = function(t, c) return {Time = t, Value = c} end}
M.ColorSequence = {new = function(a, b)
	assert(a ~= nil, "ColorSequence.new(nil)")
	return {A = a, B = b, __kind = "ColorSequence"}
end}

--..Enum..--
local enumCache = {}
M.Enum = setmetatable({}, {__index = function(_, family)
	enumCache[family] = enumCache[family] or setmetatable({}, {__index = function(t, item)
		local e = {Name = item, EnumType = family, __kind = "EnumItem"}
		setmetatable(e, {__tostring = function() return "Enum." .. family .. "." .. item end})
		rawset(t, item, e)
		return e
	end})
	return enumCache[family]
end})
local Enum = M.Enum

--..Instances..--
local ISA = {
	Part = {"BasePart", "PVInstance"}, MeshPart = {"BasePart", "PVInstance"}, Seat = {"BasePart", "PVInstance"},
	Model = {"PVInstance"}, TextButton = {"GuiButton", "GuiObject", "GuiBase2d"}, TextLabel = {"GuiObject", "GuiBase2d"},
	Frame = {"GuiObject", "GuiBase2d"}, ScreenGui = {"LayerCollector", "GuiBase2d"}, SpotLight = {"Light"}, PointLight = {"Light"},
	Script = {"BaseScript", "LuaSourceContainer"}, LocalScript = {"Script", "BaseScript", "LuaSourceContainer"}, ModuleScript = {"LuaSourceContainer"},
}
local DEFAULTS = {
	All = {Archivable = true},
	BasePart = {Transparency = 0, Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, CastShadow = true,
		Material = Enum.Material.Plastic, Size = V3(4, 1, 2)},
	Sound = {IsPlaying = false, IsLoaded = false, TimeLength = 0, TimePosition = 0, Volume = 0.5, PlaybackLoudness = 0, Looped = false,
		SoundId = "", RollOffMinDistance = 10, RollOffMaxDistance = 10000, PlaybackSpeed = 1, Playing = false},
	ProximityPrompt = {Enabled = true, ActionText = "Interact", ObjectText = "", HoldDuration = 0, MaxActivationDistance = 10,
		UIOffset = Vector2.new(0, 0)},
	Humanoid = {Health = 100, HipHeight = 2, Jump = false, Sit = false},
	Beam = {Enabled = true, Brightness = 1},
	SpotLight = {Enabled = true, Brightness = 1, Range = 16, Angle = 90},
	ScreenGui = {Enabled = true},
	GuiObject = {Visible = true},
}
local InstMT = {}
local Methods = {}
local root -- the DataModel

local function isA(obj, class)
	local c = rawget(obj, "__props").ClassName
	if c == class or class == "Instance" then return true end
	for _, s in ipairs(ISA[c] or {}) do if s == class then return true end end
	return false
end

local function PropSignal(obj, name)
	local sigs = rawget(obj, "__propSignals")
	sigs[name] = sigs[name] or Signal()
	return sigs[name]
end
local function AttrSignal(obj, name)
	local sigs = rawget(obj, "__attrSignals")
	sigs[name] = sigs[name] or Signal()
	return sigs[name]
end

local EVENTS = {"Destroying", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "AttributeChanged"}
local CLASS_EVENTS = {
	ProximityPrompt = {"Triggered", "PromptShown", "PromptHidden"}, Sound = {"Loaded", "Ended", "Played"}, TextButton = {"Activated", "MouseButton1Click"},
	Humanoid = {"StateChanged", "Died"}, RemoteEvent = {"OnServerEvent", "OnClientEvent"}, Seat = {},
}

local function NewInstance(class)
	local obj = {__props = {ClassName = class, Name = class}, __children = {}, __attrs = {}, __attrSignals = {}, __propSignals = {},
		__events = {}, __kind = "Instance", __tags = {}}
	for _, e in ipairs(EVENTS) do obj.__events[e] = Signal() end
	for _, e in ipairs(CLASS_EVENTS[class] or {}) do obj.__events[e] = Signal() end
	setmetatable(obj, InstMT)
	return obj
end
M.NewInstance = NewInstance

InstMT.__index = function(t, k)
	if Methods[k] then return Methods[k] end
	local props = rawget(t, "__props")
	local v = props[k]
	if v ~= nil then return v end
	local ev = rawget(t, "__events")[k]
	if ev then return ev end
	if k == "Position" and props.CFrame then return props.CFrame.Position end
	if k == "Orientation" then return V3(0, 0, 0) end
	if k == "Parent" then return nil end
	-- children by name
	for _, c in ipairs(rawget(t, "__children")) do if rawget(c, "__props").Name == k then return c end end
	-- defaults
	local d = DEFAULTS.All[k]
	if d ~= nil then return d end
	local class = props.ClassName
	if DEFAULTS[class] and DEFAULTS[class][k] ~= nil then return DEFAULTS[class][k] end
	for _, s in ipairs(ISA[class] or {}) do
		if DEFAULTS[s] and DEFAULTS[s][k] ~= nil then return DEFAULTS[s][k] end
	end
	SIM.unknownReads[class .. "." .. tostring(k)] = true
	return nil
end

local function fireDescAdded(parent, inst)
	local p = parent
	while p do
		rawget(p, "__events").DescendantAdded:Fire(inst)
		p = rawget(p, "__props").Parent
	end
end

InstMT.__newindex = function(t, k, v)
	local props = rawget(t, "__props")
	if k == "Parent" then
		if rawget(t, "__destroyed") and v ~= nil then error("The Parent property of " .. props.Name .. " is locked") end
		local old = props.Parent
		if old == v then return end
		if old then
			local list = rawget(old, "__children")
			for i, c in ipairs(list) do if c == t then table.remove(list, i) break end end
			local p = old
			while p do rawget(p, "__events").DescendantRemoving:Fire(t) p = rawget(p, "__props").Parent end
		end
		props.Parent = v
		if v then
			table.insert(rawget(v, "__children"), t)
			rawget(v, "__events").ChildAdded:Fire(t)
			fireDescAdded(v, t)
			for _, d in ipairs(Methods.GetDescendants(t)) do fireDescAdded(v, d) end
		end
		rawget(t, "__events").AncestryChanged:Fire(t, v)
		for _, d in ipairs(Methods.GetDescendants(t)) do rawget(d, "__events").AncestryChanged:Fire(t, v) end
		if M.OnParented then M.OnParented(t, v) end
		PropSignal(t, "Parent"):Fire()
		return
	end
	if k == "Position" and (isA(t, "BasePart")) then
		local cf = props.CFrame or CFrame.new()
		k, v = "CFrame", CF(v.X, v.Y, v.Z, cf.r)
	end
	if k == "Shape" and v == Enum.PartType.Ball then
		local s = props.Size or V3(1, 1, 1)
		local m = math.min(s.X, s.Y, s.Z)
		props.Size = V3(m, m, m)
	end
	local isEqual = props[k] == v
	props[k] = v
	if not isEqual then PropSignal(t, k):Fire() end
end
InstMT.__tostring = function(t) return rawget(t, "__props").Name end

function Methods.FindFirstChild(self, name, recursive)
	for _, c in ipairs(rawget(self, "__children")) do if rawget(c, "__props").Name == name then return c end end
	if recursive then
		for _, c in ipairs(rawget(self, "__children")) do
			local f = Methods.FindFirstChild(c, name, true)
			if f then return f end
		end
	end
	return nil
end
function Methods.WaitForChild(self, name, timeout)
	local c = Methods.FindFirstChild(self, name)
	if c then return c end
	if timeout then return nil end
	error("WaitForChild would hang forever: " .. tostring(self) .. "." .. name)
end
function Methods.FindFirstChildOfClass(self, class)
	for _, c in ipairs(rawget(self, "__children")) do if rawget(c, "__props").ClassName == class then return c end end
	return nil
end
function Methods.FindFirstChildWhichIsA(self, class)
	for _, c in ipairs(rawget(self, "__children")) do if isA(c, class) then return c end end
	return nil
end
function Methods.GetChildren(self) return table.clone(rawget(self, "__children")) end
function Methods.GetDescendants(self)
	local out = {}
	local function walk(o) for _, c in ipairs(rawget(o, "__children")) do table.insert(out, c) walk(c) end end
	walk(self)
	return out
end
function Methods.IsA(self, class) return isA(self, class) end
function Methods.IsDescendantOf(self, anc)
	local p = rawget(self, "__props").Parent
	while p do if p == anc then return true end p = rawget(p, "__props").Parent end
	return false
end
function Methods.Destroy(self)
	if rawget(self, "__destroyed") then return end
	rawget(self, "__events").Destroying:Fire()
	for _, c in ipairs(Methods.GetChildren(self)) do Methods.Destroy(c) end
	self.Parent = nil
	rawset(self, "__destroyed", true)
	if M.OnDestroyed then M.OnDestroyed(self) end
end
function Methods.ClearAllChildren(self) for _, c in ipairs(Methods.GetChildren(self)) do Methods.Destroy(c) end end
function Methods.GetAttribute(self, name) return rawget(self, "__attrs")[name] end
function Methods.GetAttributes(self) return table.clone(rawget(self, "__attrs")) end
function Methods.SetAttribute(self, name, value)
	local attrs = rawget(self, "__attrs")
	local t = M.typeof(value)
	if value ~= nil and not (t == "number" or t == "string" or t == "boolean" or t == "Vector3" or t == "Color3" or t == "CFrame" or t == "UDim2" or t == "Vector2") then
		error("SetAttribute: unsupported type " .. t .. " for " .. name)
	end
	if attrs[name] == value then return end
	attrs[name] = value
	AttrSignal(self, name):Fire()
	rawget(self, "__events").AttributeChanged:Fire(name)
end
function Methods.GetAttributeChangedSignal(self, name) return AttrSignal(self, name) end
function Methods.GetPropertyChangedSignal(self, name) return PropSignal(self, name) end
function Methods.GetFullName(self)
	local parts = {}
	local p = self
	while p and p ~= root do table.insert(parts, 1, rawget(p, "__props").Name) p = rawget(p, "__props").Parent end
	return table.concat(parts, ".")
end
function Methods.GetPivot(self)
	local pp = rawget(self, "__props").PrimaryPart
	return pp and pp.CFrame or CFrame.new()
end
function Methods.Clone(self) error("Clone not mocked") end
-- Sound
function Methods.Play(self) self.IsPlaying = true self.Playing = true end
function Methods.Resume(self) self.IsPlaying = true self.Playing = true end
function Methods.Pause(self) self.IsPlaying = false self.Playing = false end
function Methods.Stop(self) self.IsPlaying = false self.Playing = false self.TimePosition = 0 end
-- Seat
function Methods.Sit(self, humanoid) self.Occupant = humanoid end
-- Animator
function Methods.LoadAnimation(self, animation)
	assert(isA(self, "Animator"), "LoadAnimation on " .. rawget(self, "__props").ClassName)
	assert(type(animation.AnimationId) == "string" and animation.AnimationId:match("^rbxassetid://%d+$"), "bad AnimationId")
	local track = {IsPlaying = false, Looped = false, Priority = nil, AnimationId = animation.AnimationId, Destroyed = false}
	function track:Play(fade) self.IsPlaying = true M.SIM.lastTrack = self end
	function track:Stop(fade) self.IsPlaying = false end
	function track:Destroy() self.Destroyed = true end
	return track
end
-- workspace
function Methods.GetServerTimeNow(self) return 5000 + SIM.now end

function M.SetRoot(r) root = r end
M.Methods = Methods
return M
