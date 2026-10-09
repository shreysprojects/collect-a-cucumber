--!nocheck
-- Minimal Roblox mock for running fun-build behaviours headless (Vector3/Vector2/CFrame maths real, Instances as
-- property bags). Copied from tests/GardenLights/mock.luau (2026-09-24) and extended for the HomeHearth package:
-- Color3 with Lerp / fromHex, 12-number CFrame.new, SpotLight / Decal / ProximityPrompt, attribute-changed signals.
-- HomeOffice (2026-09-24): + UDim / UDim2, GUI classes (SurfaceGui, Frame, TextLabel, UICorner, UIStroke, SurfaceLight),
-- CFrame X/Y/ZVector, Color3.fromHSV, property-changed signals, Players:GetPlayerByUserId.
-- Playable CUKE RUN (2026-09-24): Random is a seeded xorshift (Random.new(seed) repeats, as the course needs), +
-- TextButton / ScreenGui with input signals, Humanoid Died / Sit / Jump, UIScale, Active / TextWrapped /
-- LineJoinMode; a Part is only made for BasePart classes.

------------------------------------------------------------------ Vector3
local V3 = {}
local V3m = {}
local function v3(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, __v3 = true}, V3) end
V3.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) return v3(t.X / m, t.Y / m, t.Z / m) end
	return V3m[k]
end
V3.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z) end
function V3m.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3m.Cross(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
Vector3 = {new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1)}

------------------------------------------------------------------ Vector2
local V2 = {}
local V2m = {}
local function v2(x, y) return setmetatable({X = x or 0, Y = y or 0, __v2 = true}, V2) end
V2.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
	return V2m[k]
end
V2.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
V2.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
V2.__mul = function(a, b)
	if type(a) == "number" then return v2(a * b.X, a * b.Y) end
	if type(b) == "number" then return v2(a.X * b, a.Y * b) end
	return v2(a.X * b.X, a.Y * b.Y)
end
function V2m.Dot(a, b) return a.X * b.X + a.Y * b.Y end
Vector2 = {new = v2, zero = v2(0, 0), one = v2(1, 1)}

------------------------------------------------------------------ CFrame (3x3 rows + position)
local CF = {}
local CFm = {}
local function cf(p, m) return setmetatable({p = p, m = m, __cf = true}, CF) end
local I3 = {1, 0, 0, 0, 1, 0, 0, 0, 1}
local function mm(a, b)
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
local function mv(m, v) return v3(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z) end
local function tr(m) return {m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9]} end
CF.__index = function(t, k)
	if k == "Position" then return t.p end
	if k == "Rotation" then return cf(v3(0, 0, 0), t.m) end
	if k == "LookVector" then return v3(-t.m[3], -t.m[6], -t.m[9]) end
	if k == "UpVector" then return v3(t.m[2], t.m[5], t.m[8]) end
	if k == "RightVector" or k == "XVector" then return v3(t.m[1], t.m[4], t.m[7]) end
	if k == "YVector" then return v3(t.m[2], t.m[5], t.m[8]) end
	if k == "ZVector" then return v3(t.m[3], t.m[6], t.m[9]) end
	if k == "X" then return t.p.X end
	if k == "Y" then return t.p.Y end
	if k == "Z" then return t.p.Z end
	return CFm[k]
end
CF.__mul = function(a, b)
	if b.__cf then return cf(a.p + mv(a.m, b.p), mm(a.m, b.m)) end
	return a.p + mv(a.m, b)
end
CF.__add = function(a, b) return cf(a.p + b, a.m) end
CF.__tostring = function(a) return "CF" .. tostring(a.p) end
function CFm.Inverse(a) local it = tr(a.m) return cf(-mv(it, a.p), it) end
function CFm.ToObjectSpace(a, b) return a:Inverse() * b end
function CFm.ToWorldSpace(a, b) return a * b end
function CFm.PointToObjectSpace(a, v) return mv(tr(a.m), v - a.p) end
function CFm.PointToWorldSpace(a, v) return a.p + mv(a.m, v) end
function CFm.VectorToWorldSpace(a, v) return mv(a.m, v) end
local function rx(a) local c, s = math.cos(a), math.sin(a) return {1, 0, 0, 0, c, -s, 0, s, c} end
local function ry(a) local c, s = math.cos(a), math.sin(a) return {c, 0, s, 0, 1, 0, -s, 0, c} end
local function rz(a) local c, s = math.cos(a), math.sin(a) return {c, -s, 0, s, c, 0, 0, 0, 1} end
CFrame = {}
function CFrame.new(x, y, z, ...)
	if x == nil then return cf(v3(0, 0, 0), I3) end
	if type(x) == "table" then return cf(x, I3) end
	local r = {...}
	if #r == 9 then return cf(v3(x, y, z), r) end
	return cf(v3(x, y, z), I3)
end
function CFrame.Angles(a, b, c) return cf(v3(0, 0, 0), mm(mm(rx(a), ry(b)), rz(c))) end
function CFrame.fromMatrix(p, r, u, b)
	b = b or r:Cross(u)
	return cf(p, {r.X, u.X, b.X, r.Y, u.Y, b.Y, r.Z, u.Z, b.Z})
end
function CFrame.lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up).Unit
	local up2 = right:Cross(look)
	return CFrame.fromMatrix(at, right, up2, -look)
end
CFrame.identity = CFrame.new()

------------------------------------------------------------------ small value types
local C3 = {}
local C3m = {}
C3.__index = C3m
local function c3(r, g, b) return setmetatable({R = r, G = g, B = b, __c3 = true}, C3) end
function C3m.Lerp(a, b, t)
	assert(type(t) == "number" and rawget(b, "__c3"), "Color3:Lerp(Color3, number)")
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
C3.__eq = function(a, b) return math.abs(a.R - b.R) < 1e-4 and math.abs(a.G - b.G) < 1e-4 and math.abs(a.B - b.B) < 1e-4 end
C3.__tostring = function(a) return string.format("RGB(%d, %d, %d)", a.R * 255 + 0.5, a.G * 255 + 0.5, a.B * 255 + 0.5) end
Color3 = {
	fromRGB = function(r, g, b) return c3(r / 255, g / 255, b / 255) end,
	fromHSV = function(h, s, v)
		assert(h >= 0 and h <= 1 and s >= 0 and s <= 1 and v >= 0 and v <= 1, "fromHSV range")
		local i = math.floor(h * 6) % 6
		local f = h * 6 - math.floor(h * 6)
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		local rgb = ({{v, t, p}, {q, v, p}, {p, v, t}, {p, q, v}, {t, p, v}, {v, p, q}})[i + 1]
		return c3(rgb[1], rgb[2], rgb[3])
	end,
	new = function(r, g, b) return c3(r or 0, g or 0, b or 0) end,
	fromHex = function(h)
		h = h:gsub("#", "")
		return c3(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255)
	end,
}
NumberSequenceKeypoint = {new = function(t, v) assert(type(t) == "number" and type(v) == "number", "NSK args") return {Time = t, Value = v} end}
NumberSequence = {new = function(a, b)
	if type(a) == "number" then return {Keypoints = {{Time = 0, Value = a}, {Time = 1, Value = b or a}}} end
	assert(type(a) == "table" and #a >= 2 and #a <= 20, "NumberSequence keypoints")
	assert(a[1].Time == 0 and a[#a].Time == 1, "NumberSequence must start at 0 and end at 1")
	for i = 2, #a do assert(a[i].Time > a[i - 1].Time, "NumberSequence times must increase") end
	return {Keypoints = a}
end}
ColorSequenceKeypoint = {new = function(t, c) return {Time = t, Value = c} end}
ColorSequence = {new = function(a, b)
	if rawget(a, "__c3") then return {Keypoints = {{Time = 0, Value = a}, {Time = 1, Value = b or a}}} end
	assert(a[1].Time == 0 and a[#a].Time == 1, "ColorSequence ends")
	return {Keypoints = a}
end}
NumberRange = {new = function(a, b) b = b or a assert(b >= a, "NumberRange min > max") return {Min = a, Max = b} end}
Random = {new = function(seed)
	MockAutoSeed = (MockAutoSeed or 777) + 7919
	local st = (math.floor(seed or MockAutoSeed) % 4294967291) + 1
	local r = {}
	local function nxt()
		st = bit32.bxor(st, bit32.lshift(st, 13))
		st = bit32.bxor(st, bit32.rshift(st, 17))
		st = bit32.bxor(st, bit32.lshift(st, 5))
		return st / 4294967296
	end
	function r:NextNumber(a, b) a = a or 0 b = b or 1 return a + nxt() * (b - a) end
	function r:NextInteger(a, b) return a + math.floor(nxt() * (b - a + 1)) end
	return r
end}
local UD = {}
UD.__tostring = function(u) return ("{%g, %d}"):format(u.Scale, u.Offset) end
local function udim(s, o) return setmetatable({Scale = s or 0, Offset = math.floor(o or 0), __udim = true}, UD) end
UDim = {new = udim}
local UD2 = {}
UD2.__tostring = function(u) return ("{%s, %s}"):format(tostring(u.X), tostring(u.Y)) end
local function udim2(xs, xo, ys, yo) return setmetatable({X = udim(xs, xo), Y = udim(ys, yo), __udim2 = true}, UD2) end
UDim2 = {
	new = udim2,
	fromOffset = function(x, y) assert(type(x) == "number" and type(y) == "number", "fromOffset numbers") return udim2(0, x, 0, y) end,
	fromScale = function(x, y) return udim2(x, 0, y, 0) end,
}
local enumMeta
enumMeta = {__index = function(t, k) local v = setmetatable({__path = t.__path .. "." .. k}, enumMeta) rawset(t, k, v) return v end,
	__tostring = function(t) return t.__path end}
Enum = setmetatable({__path = "Enum"}, enumMeta)

------------------------------------------------------------------ Instances
local CLASS_IS = {
	Part = {BasePart = true, Part = true}, WedgePart = {BasePart = true, WedgePart = true}, MeshPart = {BasePart = true, MeshPart = true},
	Seat = {BasePart = true, Seat = true, Part = true},
	SurfaceGui = {SurfaceGui = true, LayerCollector = true}, Frame = {Frame = true, GuiObject = true},
	TextLabel = {TextLabel = true, GuiObject = true},
	TextButton = {TextButton = true, GuiObject = true, GuiButton = true},
	ScreenGui = {ScreenGui = true, LayerCollector = true},
}
local ALLOWED = { -- properties a script may set per class (catches typos like "Shapestyle")
	BasePart = {Name = 1, Anchored = 1, CanCollide = 1, CanQuery = 1, CanTouch = 1, CastShadow = 1, TopSurface = 1, BottomSurface = 1,
		Size = 1, CFrame = 1, Position = 1, Color = 1, Material = 1, Transparency = 1, LocalTransparencyModifier = 1, Shape = 1, Parent = 1, Reflectance = 1},
	Attachment = {Name = 1, Position = 1, CFrame = 1, Parent = 1, WorldPosition = 1},
	PointLight = {Name = 1, Color = 1, Brightness = 1, Range = 1, Shadows = 1, Parent = 1, Enabled = 1},
	SpotLight = {Name = 1, Color = 1, Brightness = 1, Range = 1, Shadows = 1, Parent = 1, Enabled = 1, Angle = 1, Face = 1},
	Decal = {Name = 1, Face = 1, Texture = 1, Parent = 1, Transparency = 1, Color3 = 1},
	ProximityPrompt = {Name = 1, ObjectText = 1, ActionText = 1, Style = 1, KeyboardKeyCode = 1, GamepadKeyCode = 1,
		HoldDuration = 1, MaxActivationDistance = 1, RequiresLineOfSight = 1, Exclusivity = 1, Parent = 1, Enabled = 1},
	Fire = {Name = 1, Size = 1, Heat = 1, Color = 1, SecondaryColor = 1, Parent = 1, Enabled = 1, TimeScale = 1},
	ParticleEmitter = {Name = 1, Texture = 1, Rate = 1, Lifetime = 1, Speed = 1, SpreadAngle = 1, EmissionDirection = 1, Acceleration = 1,
		Drag = 1, Size = 1, Transparency = 1, Color = 1, LightEmission = 1, LightInfluence = 1, Orientation = 1, Squash = 1, Rotation = 1,
		RotSpeed = 1, Enabled = 1, Parent = 1, Shape = 1, ShapeStyle = 1, ZOffset = 1, LockedToPart = 1},
	SpecialMesh = {Name = 1, MeshType = 1, Scale = 1, Parent = 1},
	Sound = {Name = 1, SoundId = 1, Looped = 1, Volume = 1, RollOffMinDistance = 1, RollOffMaxDistance = 1, RollOffMode = 1, Parent = 1,
		PlaybackSpeed = 1, TimePosition = 1},
	SurfaceGui = {Name = 1, Face = 1, LightInfluence = 1, Brightness = 1, SizingMode = 1, PixelsPerStud = 1, ZIndexBehavior = 1,
		Adornee = 1, ClipsDescendants = 1, MaxDistance = 1, Parent = 1, AlwaysOnTop = 1, Enabled = 1},
	Frame = {Name = 1, BorderSizePixel = 1, BackgroundColor3 = 1, BackgroundTransparency = 1, Position = 1, Size = 1, ZIndex = 1,
		Visible = 1, Parent = 1, ClipsDescendants = 1, AnchorPoint = 1, Rotation = 1, Active = 1},
	TextLabel = {Name = 1, BorderSizePixel = 1, BackgroundColor3 = 1, BackgroundTransparency = 1, Position = 1, Size = 1, ZIndex = 1,
		Visible = 1, Parent = 1, AnchorPoint = 1, Font = 1, Text = 1, TextColor3 = 1, TextScaled = 1, TextXAlignment = 1,
		TextYAlignment = 1, TextTransparency = 1, TextSize = 1, TextStrokeTransparency = 1, TextWrapped = 1},
	UICorner = {Name = 1, CornerRadius = 1, Parent = 1},
	UIStroke = {Name = 1, Color = 1, Thickness = 1, Transparency = 1, Parent = 1, ApplyStrokeMode = 1, LineJoinMode = 1},
	SurfaceLight = {Name = 1, Face = 1, Range = 1, Angle = 1, Brightness = 1, Color = 1, Shadows = 1, Enabled = 1, Parent = 1},
	Folder = {Name = 1, Parent = 1, Archivable = 1}, Model = {Name = 1, Parent = 1, PrimaryPart = 1}, Camera = {Name = 1, Parent = 1},
}
local Inst = {}
local InstM = {}
local function isA(self, c)
	if self.ClassName == c or c == "Instance" then return true end
	local t = CLASS_IS[self.ClassName]
	return t ~= nil and t[c] == true
end
local function allowed(self, k)
	if k == "Occupant" and self.ClassName == "Seat" then return true end
	local list = ALLOWED[self.ClassName] or (isA(self, "BasePart") and ALLOWED.BasePart)
	if not list then return true end
	return list[k] ~= nil
end
Inst.__index = function(t, k)
	local props = rawget(t, "_p")
	if k == "Position" and isA(t, "BasePart") then return props.CFrame.p end
	if k == "WorldPosition" and t.ClassName == "Attachment" then return t.Parent.CFrame * props.CFrame.p end
	if k == "WorldCFrame" and t.ClassName == "Attachment" then return t.Parent.CFrame * props.CFrame end
	if k == "Position" and t.ClassName == "Attachment" then return props.CFrame.p end
	if props[k] ~= nil then return props[k] end
	if InstM[k] then return InstM[k] end
	local c = rawget(t, "_c")
	for _, child in ipairs(c) do if child.Name == k then return child end end
	return nil
end
Inst.__newindex = function(t, k, v)
	local props = rawget(t, "_p")
	assert(allowed(t, k), ("bad property %s.%s"):format(props.ClassName, tostring(k)))
	if k == "Parent" then
		local old = props.Parent
		if old then
			local oc = rawget(old, "_c")
			for i, child in ipairs(oc) do if child == t then table.remove(oc, i) break end end
		end
		props.Parent = v
		if v then table.insert(rawget(v, "_c"), t) end
		return
	end
	if k == "Position" and isA(t, "BasePart") then props.CFrame = cf(v, props.CFrame.m) return end
	if k == "Position" and t.ClassName == "Attachment" then props.CFrame = cf(v, props.CFrame.m) return end
	if k == "Size" and isA(t, "BasePart") and props.Shape == Enum.PartType.Ball then v = v3(v.X, v.X, v.X) end
	local old = props[k]
	props[k] = v
	local ps = rawget(t, "_psigs")
	if ps and ps[k] and old ~= v then ps[k]:Fire() end
end
function InstM.IsA(self, c) return isA(self, c) end
function InstM.FindFirstChild(self, name, recursive)
	for _, c in ipairs(rawget(self, "_c")) do
		if c.Name == name then return c end
		if recursive then local f = c:FindFirstChild(name, true) if f then return f end end
	end
	return nil
end
function InstM.WaitForChild(self, name) return self:FindFirstChild(name) end
function InstM.FindFirstChildOfClass(self, cls) for _, c in ipairs(rawget(self, "_c")) do if c.ClassName == cls then return c end end return nil end
function InstM.GetChildren(self) return table.clone(rawget(self, "_c")) end
function InstM.GetDescendants(self)
	local out = {}
	local function walk(x) for _, c in ipairs(rawget(x, "_c")) do table.insert(out, c) walk(c) end end
	walk(self)
	return out
end
local function newSignal()
	local sig = {fns = {}}
	function sig:Connect(fn)
		table.insert(self.fns, fn)
		return {Disconnect = function() for i, f in ipairs(sig.fns) do if f == fn then table.remove(sig.fns, i) break end end end}
	end
	function sig:Fire(...) for _, fn in ipairs(table.clone(self.fns)) do fn(...) end end
	return sig
end
MockSignal = newSignal
function InstM.GetAttribute(self, k) return rawget(self, "_a")[k] end
function InstM.GetAttributeChangedSignal(self, k)
	local sigs = rawget(self, "_sigs")
	if not sigs then sigs = {} rawset(self, "_sigs", sigs) end
	sigs[k] = sigs[k] or newSignal()
	return sigs[k]
end
function InstM.GetPropertyChangedSignal(self, k)
	local ps = rawget(self, "_psigs")
	if not ps then ps = {} rawset(self, "_psigs", ps) end
	ps[k] = ps[k] or newSignal()
	return ps[k]
end
function InstM.GetPlayerFromCharacter(_, char)
	for _, p in ipairs(MockPlayers or {}) do if p.Character == char then return p end end
	return nil
end
function InstM.GetPlayerByUserId(_, id)
	for _, p in ipairs(MockPlayers or {}) do if p.UserId == id then return p end end
	return nil
end
function InstM.SetAttribute(self, k, v)
	local old = rawget(self, "_a")[k]
	rawget(self, "_a")[k] = v
	local sigs = rawget(self, "_sigs")
	if old ~= v and sigs and sigs[k] then sigs[k]:Fire() end
end
function InstM.Destroy(self) if self.Parent then self.Parent = nil end rawset(self, "_destroyed", true) end
function InstM.IsDescendantOf(self, other) local p = self.Parent while p do if p == other then return true end p = p.Parent end return false end
function InstM.Emit(self, n) rawset(self, "_emitted", (rawget(self, "_emitted") or 0) + n) end
function InstM.Play(self) rawget(self, "_p").IsPlaying = true end
function InstM.Stop(self) rawget(self, "_p").IsPlaying = false end
function InstM.Clone(self) error("Clone not mocked") end
function InstM.GetBoundingBox(self) error("not mocked") end
local ALL = {}
local function newInst(className)
	local t = setmetatable({_p = {ClassName = className, Name = className}, _c = {}, _a = {}}, Inst)
	local p = rawget(t, "_p")
	if CLASS_IS[className] and CLASS_IS[className].BasePart then
		p.CFrame = CFrame.new()
		p.Size = v3(4, 1, 2)
		p.Transparency = 0
		p.LocalTransparencyModifier = 0
		p.CanCollide = true
		p.Anchored = false
		p.AssemblyLinearVelocity = v3(0, 0, 0)
	elseif className == "Attachment" then
		p.CFrame = CFrame.new()
	elseif className == "Sound" then
		p.IsPlaying = false
		p.TimeLength = 3.2
		p.TimePosition = 0
	elseif className == "ParticleEmitter" then
		p.Enabled = true
	elseif className == "ProximityPrompt" then
		p.Enabled = true
		p.Triggered = newSignal()
	elseif className == "Frame" or className == "TextLabel" or className == "TextButton" then
		p.InputBegan = newSignal() p.Activated = newSignal() p.MouseEnter = newSignal() p.MouseLeave = newSignal()
		p.MouseButton1Down = newSignal() p.MouseButton1Up = newSignal()
		p.Visible = true
		p.BackgroundTransparency = 0
		p.Position = udim2(0, 0, 0, 0)
		p.Size = udim2(0, 0, 0, 0)
		p.ZIndex = 1
		if className ~= "Frame" then p.Text = "" p.TextTransparency = 0 end
	elseif className == "Humanoid" then
		p.Died = newSignal() p.Health = 100 p.Sit = false p.Jump = false
	elseif className == "UIScale" then
		p.Scale = 1
	elseif className == "SpecialMesh" then
		p.Scale = v3(1, 1, 1)
	end
	table.insert(ALL, t)
	return t
end
Instance = {new = newInst}
MockAll = ALL

------------------------------------------------------------------ services
local function service(name) local s = newInst("Folder") s.Name = name return s end
local ReplicatedStorage = service("ReplicatedStorage")
local Lighting = service("Lighting")
rawget(Lighting, "_p").ClockTime = 14
local Players = service("Players")
local Workspace = service("Workspace")
local camera = newInst("Camera")
camera.Name = "Camera"
camera.Parent = Workspace
rawget(camera, "_p").CFrame = CFrame.new(0, 20, 30)
rawget(Workspace, "_p").CurrentCamera = camera
MockNow = 1790000000.25
function InstM.GetServerTimeNow() return MockNow end
function InstM.BulkMoveTo(_, parts, cfs, mode)
	assert(#parts == #cfs, ("BulkMoveTo size mismatch %d vs %d"):format(#parts, #cfs))
	for i, p in ipairs(parts) do p.CFrame = cfs[i] end
end
local playerList = {}
function InstM.GetPlayers() return playerList end
MockPlayers = playerList
workspace = Workspace
game = {GetService = function(_, n)
	if n == "ReplicatedStorage" then return ReplicatedStorage end
	if n == "Lighting" then return Lighting end
	if n == "Players" then return Players end
	if n == "RunService" then return {IsServer = function() return false end} end
	if n == "Workspace" then return Workspace end
	error("service " .. n)
end}
local mods = newInst("Folder")
mods.Name = "Modules"
mods.Parent = ReplicatedStorage
MockModules = mods
MockLighting = Lighting
typeof = function(v)
	if type(v) == "table" then
		if rawget(v, "__v3") then return "Vector3" end
		if rawget(v, "__v2") then return "Vector2" end
		if rawget(v, "__cf") then return "CFrame" end
		if rawget(v, "_p") then return "Instance" end
		if rawget(v, "__c3") then return "Color3" end
		if rawget(v, "__udim2") then return "UDim2" end
		if rawget(v, "__udim") then return "UDim" end
	end
	return type(v)
end
