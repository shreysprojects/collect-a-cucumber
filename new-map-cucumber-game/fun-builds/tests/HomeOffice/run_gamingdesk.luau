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

SOURCES = {}
SOURCES['FunBuildKit'] = [======[
--[[
	FunBuildKit  (ModuleScript, ReplicatedStorage.Modules)  2026-09-24
	Shared helpers for FUNCTIONAL BUILDS (user: "make all the fun stuff functional - tv could be turned on,
	trampoline bouncy, seesaw functional ..."). Used by ServerScriptService.FunBuildService, the client
	StarterPlayerScripts.FunBuildClient and every behaviour module:
	  ServerStorage.FunBehaviours.<BaseKey>              (server half, ModuleScript)
	  ReplicatedStorage.FunBehavioursClient.<BaseKey>    (client half, ModuleScript)
	A behaviour runs for every PLACED build (CollectionService tag "PlacedBuild") whose BuildKey, minus a
	variant suffix ("Lantern_A" -> "Lantern"), names the module. See fun-builds/CONTRACT.md.

	GEOMETRY. A placed build is a clone of its ReplicatedStorage.PlaceableBuilds template. BuildService
	stamps two attributes on every template: AuthoredCentre (Vector3, the bounding-box centre of the
	build's parts in the AUTHORED frame = ServerStorage.Builds source coordinates, floor centre at the
	origin, front toward -Z) and Scale (number, BuildCatalog.ScaleOf). The Hitbox (PrimaryPart) sits at
	that centre and the template was Model:ScaleTo(Scale)'d about it, so an authored point p is at
	Hitbox.CFrame * ((p - AuthoredCentre) * Scale) in the world. Pivot_<Name> / State_<Name> authoring
	attributes survive on templates (Pivot_* are authored-frame Vector3s) - Kit.Pivot converts them.
]]
local RunService = game:GetService("RunService")

local Kit = {}

Kit.PLACED_TAG = "PlacedBuild"
Kit.PROMPT_TAG = "FunBuildPrompt"       -- every prompt a behaviour makes (hidden in build mode by the client)
Kit.REMOTE = "FunBuildAction"           -- ReplicatedStorage.Remotes.<this>: RemoteEvent both ways
Kit.STATE_PREFIX = "Fun_"               -- ctx:SetState(k, v) -> model attribute Fun_<k>
Kit.SERVER_FOLDER = "FunBehaviours"     -- ServerStorage.<this>.<BaseKey>
Kit.CLIENT_FOLDER = "FunBehavioursClient" -- ReplicatedStorage.<this>.<BaseKey>
Kit.RUNTIME_FOLDER = "FunBuildRuntime"  -- workspace.<this>: helper PARTS a behaviour makes (seats, triggers) live here, never inside the build
Kit.LIE_ATTR = "Lie"                    -- a Seat with Lie = true lays its occupant flat (server turns the SeatWeld, clients straighten the joints)

--..Keys..--
function Kit.Key(model)
	return model and model:GetAttribute("BuildKey")
end

--.. "Lantern_A" -> "Lantern", "A"; "TV" -> "TV", nil
function Kit.Split(key)
	if type(key) ~= "string" then return nil, nil end
	local base, letter = key:match("^(.-)_(%u)$")
	if base and base ~= "" then return base, letter end
	return key, nil
end

--.. a variant part name: Kit.VName(model, "Light") -> "A_Light" on Lantern_A, "Light" on a plain build
function Kit.VName(model, name)
	local _, letter = Kit.Split(Kit.Key(model))
	return letter and (letter .. "_" .. name) or name
end

--..Geometry..--
function Kit.Scale(model)
	return tonumber(model:GetAttribute("Scale")) or 1
end

function Kit.Hitbox(model)
	return model.PrimaryPart or model:FindFirstChild("Hitbox")
end

function Kit.AuthoredCentre(model)
	local c = model:GetAttribute("AuthoredCentre")
	return typeof(c) == "Vector3" and c or Vector3.zero
end

--.. the world CFrame of the authored origin (floor centre, authored axes), scale included in positions via ToWorld
function Kit.Origin(model)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return model:GetPivot() end
	return hitbox.CFrame * CFrame.new(-Kit.AuthoredCentre(model) * Kit.Scale(model))
end

--.. an authored-frame point -> world
function Kit.ToWorld(model, p)
	return Kit.Origin(model):PointToWorldSpace(p * Kit.Scale(model))
end

--.. an authored-frame CFrame (position authored, rotation authored) -> world
function Kit.CFrameToWorld(model, cf)
	local s = Kit.Scale(model)
	return Kit.Origin(model) * (CFrame.new(cf.Position * s) * cf.Rotation)
end

--.. Pivot_<name> (authored Vector3) -> world Vector3, or nil. Variant builds carry Pivot_A_Light etc.; pass the full name
function Kit.Pivot(model, name)
	local v = model:GetAttribute("Pivot_" .. name)
	if typeof(v) == "Vector3" then return Kit.ToWorld(model, v) end
	return nil
end

--.. the world floor point under the build (bottom centre of the hitbox) and its up
function Kit.Floor(model)
	local hitbox = Kit.Hitbox(model)
	return hitbox.CFrame * CFrame.new(0, -hitbox.Size.Y * 0.5, 0)
end

--..Parts..--
function Kit.Part(model, name)
	local p = model:FindFirstChild(name, true)
	if p and p:IsA("BasePart") then return p end
	return nil
end

--.. every BasePart (not the Hitbox) whose Name starts with prefix, sorted by name
function Kit.Parts(model, prefix)
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Hitbox" and d.Name:sub(1, #prefix) == prefix then table.insert(list, d) end
	end
	table.sort(list, function(a, b) return a.Name < b.Name end)
	return list
end

--.. {part = relative CFrame} of parts about a pivot CFrame, for rigid animation: part.CFrame = pivot * motion * rel
function Kit.Rig(parts, pivotCF)
	local rig = {}
	for _, p in ipairs(parts) do rig[p] = pivotCF:ToObjectSpace(p.CFrame) end
	return rig
end

function Kit.PoseRig(rig, cf)
	for p, rel in pairs(rig) do
		if p.Parent then p.CFrame = cf * rel end
	end
end

--..State..--
function Kit.IsBroken(model)
	return model:GetAttribute("Broken") == true
end

function Kit.OwnerId(model)
	return model:GetAttribute("Owner")
end

function Kit.State(model, key)
	return model:GetAttribute(Kit.STATE_PREFIX .. key)
end

function Kit.Now()
	return workspace:GetServerTimeNow()
end

--..Characters..--
function Kit.CharacterParts(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid, root
end

--.. the joints of an R15/R6 character that animation drives (Motor6D or AnimationConstraint - New Map characters use
--.. AnimationConstraint since 2026-09); returns {joint = true}
function Kit.Joints(character)
	local joints = {}
	if not character then return joints end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then joints[d] = true end
	end
	return joints
end

--.. the rotation a lying occupant's root takes relative to its seat: head toward the seat's LookVector (-Z),
--.. face up (+Y), back on the seat
Kit.LIE_ROTATION = CFrame.fromMatrix(Vector3.zero, Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, -1, 0))

--..Sounds..--
--.. a Sound from ReplicatedStorage.Assets.Sounds by name, or from a raw id ("rbxassetid://..." or a number)
function Kit.MakeSound(nameOrId, props)
	local sound
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local lib = assets and assets:FindFirstChild("Sounds")
	local template = type(nameOrId) == "string" and lib and lib:FindFirstChild(nameOrId, true)
	if template and template:IsA("Sound") then
		sound = template:Clone()
	else
		sound = Instance.new("Sound")
		local id = tostring(nameOrId)
		if tonumber(id) then id = "rbxassetid://" .. id end
		sound.SoundId = id
	end
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 90
	for k, v in pairs(props or {}) do sound[k] = v end
	return sound
end

Kit.IsServer = RunService:IsServer()

return Kit
]======]
SOURCES['FunAssets'] = [======[
--[[
	FunAssets  (ModuleScript, ReplicatedStorage.Modules)  2026-09-24
	Every sound / video / picture the functional builds use, in one place. Behaviours never hard-code an id:
	they ask FunAssets.Sfx.<Name> (a value Kit.MakeSound / ctx:Sound accept: an "rbxassetid://" id OR the
	name of a Sound in ReplicatedStorage.Assets.Sounds) and read the lists below.

	Every id here was checked in this place's edit data model on 2026-09-24 (fun-builds/assets/ research):
	  * sounds: ContentProvider:PreloadAsync = Success and Sound.TimeLength > 0; the one-shots were also run
	    through an AudioAnalyzer (unwired to any output, so silent) to check the sound starts at once and is
	    not clipped
	  * videos: VideoFrame.IsLoaded = true, Resolution 1280x720 (all Roblox-created)
	  * pictures: decal -> IMAGE id via InsertService:LoadAsset, AssetTypeId 1, preload Success, thumbnail
	    looked at (family friendly)
	Sources, creators, durations: fun-builds/assets/ASSETS.md. Most sounds are Pro Sound Effects / APM /
	Roblox-created (licensed for every experience); the rest are public Creator Store uploads.
]]
local M = {}

--.. one-shots and loops. Values: "rbxassetid://<id>" (a Sound library name still works too)
M.Sfx = {
	--..Toys / outdoors..--
	Boing = "rbxassetid://6075441854",        -- trampoline bounce: cartoon spring boing (1.3 s)
	Creak = "rbxassetid://9120839174",        -- seesaw / hammock / bed: wood creak-squeak (1.4 s)
	Whee = "rbxassetid://9119197913",         -- slide ride: slide whistle (1.35 s)
	Thump = "rbxassetid://9113535217",        -- seesaw end lands: soft low body thump (1.2 s)
	Splash = "rbxassetid://9117823374",       -- hot tub / bath jump-in splash (2.3 s)
	Crickets = "rbxassetid://9112764546",     -- night crickets (36 s, loopable)
	Caw = "rbxassetid://9118067220",          -- scarecrow crow: single raven caw (0.7 s)
	Rustle = "rbxassetid://9114576499",       -- bush: leafy foliage rustle (2.2 s)
	Cheer = "rbxassetid://1841221347",        -- kids shouting "Yeah!" (APM, 2.9 s)
	Whoosh = "rbxassetid://9126229255",       -- fast airy whoosh (1.0 s)
	Zap = "rbxassetid://116624744040072",     -- electric spark zap (2.5 s)
	Sparkle = "rbxassetid://3199238931",      -- magic gem sparkle (2.1 s)
	Click = "rbxassetid://15675059323",       -- Roblox UI bright click (0.4 s)

	--..TV..--
	TVOn = "rbxassetid://9119973992",         -- tv power-on pop at 0.15 s, then (near) silence
	TVOff = "rbxassetid://78535264432518",    -- old tv switching off (0.7 s)
	TVStatic = "rbxassetid://96891705634188", -- white-noise static, starts at once (2.1 s; TV cuts it at 0.4 s)

	--..Vending / arcade..--
	Fizz = "rbxassetid://123359260762085",    -- soda can opened, psst + fizz (2.5 s)
	CanDrop = "rbxassetid://9114185361",      -- can drops into the chute, hollow bounce (1.6 s, quiet)
	Coin = "rbxassetid://16480549189",        -- token / coin insert (Roblox pinball set, 1.9 s)
	ArcadeBlip = "rbxassetid://16480580213",  -- 8-bit blip (Roblox pinball set, 0.7 s)
	ArcadeLose = "rbxassetid://190705984",    -- sad trombone (3.9 s)
	ArcadeWin = "rbxassetid://16480577565",   -- 8-bit rising win jingle (Roblox pinball set, 2.9 s)
	Burp = "rbxassetid://9113414717",         -- short silly belch (0.8 s)
	Gulp = "rbxassetid://133988388434763",    -- single swallow gulp (1.2 s)

	--..Fire / water loops..--
	FireLoop = "rbxassetid://9112780462",     -- fireplace crackle (43 s, loop)
	FireIgnite = "rbxassetid://4510176414",   -- match strike + flare (1.5 s)
	FireOut = "rbxassetid://9113702967",      -- blow-out puff (0.7 s)
	WaterLoop = "rbxassetid://9120557306",    -- fountain splashing / running water (36 s, loop)
	BubblesLoop = "rbxassetid://9112752570",  -- streams of small bubbles (13.8 s, loop)
	Flush = "rbxassetid://116759736098379",   -- toilet flush rush (4.3 s)

	--..Kitchen / appliances..--
	Sizzle = "rbxassetid://9114542867",       -- pan sizzle (40 s, loop)
	HumLoop = "rbxassetid://112948256817153", -- refrigerator hum (72 s, loop)
	FridgeHum = "rbxassetid://112948256817153",
	FridgeOpen = "rbxassetid://9118125101",   -- fridge door open, light seal squeak (1.7 s)
	FridgeClose = "rbxassetid://9118127655",  -- fridge door closes with a soft slam (1.5 s)
	MicrowaveHum = "rbxassetid://4399963971", -- microwave running hum (10.6 s, loop)
	MicrowaveBeep = "rbxassetid://3690600068", -- keypad beep (0.1 s)
	Ding = "rbxassetid://9125485591",         -- single bell ding, long ring (4.5 s)
	DoorOpen = "rbxassetid://9118124760",     -- appliance door open, light metal squeak (1.9 s)
	DoorClose = "rbxassetid://9120492567",    -- chunky appliance door clunk (2.6 s)
	WasherLoop = "rbxassetid://9118891774",   -- washing machine cycle (45 s, loop)
	DryerLoop = "rbxassetid://77493396468975", -- clothes dryer tumbling (44 s, loop)
	ToasterPop = "rbxassetid://365950085",    -- toaster pop-up (Roblox, 0.65 s)

	--..Home..--
	ClockTick = "rbxassetid://16480551554",   -- single small metal tick (Roblox, 0.36 s)
	ClockChime = "rbxassetid://16480570385",  -- single low bell strike (Roblox, 1.5 s)
	PianoNote = "rbxassetid://78413131279275", -- ONE sustained piano C4 (6 s), pitched by PlaybackSpeed
	CushionPoof = "rbxassetid://9120204520",  -- soft fabric flop (2.0 s)
}

--.. the pitch of M.Sfx.PianoNote (Hz) - PlaybackSpeed = target / root. Measured with an AudioAnalyzer:
--.. fundamental 261-262 Hz, harmonics at 522 / 1046 Hz = C4.
M.PianoRootHz = 261.63

--.. looping music for the DJ booth / jukebox-like builds: {Name = "...", Id = "rbxassetid://..."}
--.. all APM (Roblox-licensed), full-length tracks
M.Music = {
	{Name = "Funky Disco Beats", Id = "rbxassetid://9038367768"},              -- funky EDM, 3:20
	{Name = "Midnight Studio Juice", Id = "rbxassetid://9038366120"},          -- bouncy EDM, 3:22
	{Name = "Feel That Move", Id = "rbxassetid://9044944264"},                 -- 80s funk, 3:08
	{Name = "Stracciatella Galaxy", Id = "rbxassetid://9042927295"},           -- space disco funk, 3:38
	{Name = "Normalize Today", Id = "rbxassetid://9046300489"},                -- upbeat funk, 2:03
	{Name = "Floating Through Deeper Thoughts", Id = "rbxassetid://9038366820"}, -- uplifting bouncy EDM, 2:57
	{Name = "Jazz Joint", Id = "rbxassetid://9045468115"},                     -- lounge jazz organ, 2:33
	{Name = "Halves", Id = "rbxassetid://1837104550"},                         -- positive synth groove, 2:12
}

--.. pictures (IMAGE ids) shared by the slideshows below
local NATURE = {
	"rbxassetid://5717309394",  -- mountain lake
	"rbxassetid://10719452874", -- iceberg
	"rbxassetid://1908897932",  -- waterfall
	"rbxassetid://5887500272",  -- mountains and fog
	"rbxassetid://3319553125",  -- ocean sunset
	"rbxassetid://2546997593",  -- snowy valley lake
}
local SPACE = {
	"rbxassetid://6864892942",   -- earth from space
	"rbxassetid://14833944867",  -- saturn (Voyager)
	"rbxassetid://12787761154",  -- pillars of creation
	"rbxassetid://10208853991",  -- cosmic cliffs, carina nebula
	"rbxassetid://9728471648",   -- butterfly nebula
	"rbxassetid://117453845793004", -- tarantula nebula
}
local ANIMALS = {
	"rbxassetid://5484695170",  -- red panda
	"rbxassetid://12590518027", -- puppy
	"rbxassetid://404656671",   -- kitten
	"rbxassetid://2414749340",  -- sea otter
	"rbxassetid://14912788722", -- penguin
	"rbxassetid://289280641",   -- fluffy kitten
}
local FOOD = {
	"rbxassetid://4772865076",    -- pepperoni pizza
	"rbxassetid://79619558",      -- cupcakes
	"rbxassetid://105472541332250", -- fruit salad
	"rbxassetid://90082450177424",  -- pancake stack
	"rbxassetid://3397603611",    -- watermelon slices
	"rbxassetid://3290518286",    -- strawberries
}

--.. TV channels. A channel is either {Name, Video = "rbxassetid://..."} (VideoFrame, looped, WITH its sound unless
--.. Sound = false; Slides/Seconds = the fallback while the video can't play) or
--.. {Name, Slides = {"rbxassetid://<IMAGE id>", ...}, Seconds = 4, Music = "rbxassetid://..."} (a picture slideshow
--.. over an optional looped music track)
M.TVChannels = {
	{Name = "Waterfall Cam", Video = "rbxassetid://5670869502", Sound = true, Slides = NATURE, Seconds = 4},   -- Roblox, 30 s
	{Name = "Space Walk", Video = "rbxassetid://5608398904", Sound = true, Slides = SPACE, Seconds = 4},       -- Roblox, 13 s
	{Name = "Cartoon Sea", Video = "rbxassetid://5608250999", Sound = true, Slides = ANIMALS, Seconds = 4},    -- Roblox, 15 s
	{Name = "Bird Watch", Video = "rbxassetid://5608392925", Sound = true, Slides = NATURE, Seconds = 4},      -- Roblox, 15 s
	--.. 2026-09-24 (user: "make tv play with sound"): slideshows play a quiet looped APM track (Music) under the pictures
	{Name = "Nature", Slides = NATURE, Seconds = 4, Music = "rbxassetid://9038366820"},       -- Floating Through Deeper Thoughts
	{Name = "Space", Slides = SPACE, Seconds = 4, Music = "rbxassetid://9042927295"},         -- Stracciatella Galaxy
	{Name = "Cute Animals", Slides = ANIMALS, Seconds = 4, Music = "rbxassetid://9046300489"}, -- Normalize Today
	{Name = "Yummy Food", Slides = FOOD, Seconds = 4, Music = "rbxassetid://9045468115"},     -- Jazz Joint
}

--.. pictures for picture frames / screens: IMAGE ids (not decal ids) - public-domain classic paintings
M.Pictures = {
	"rbxassetid://1305342230",   -- The Starry Night, Van Gogh
	"rbxassetid://14044191899",  -- The Great Wave off Kanagawa, Hokusai
	"rbxassetid://12083554328",  -- Sunflowers, Van Gogh
	"rbxassetid://4623606213",   -- Cafe Terrace at Night, Van Gogh
	"rbxassetid://3117938916",   -- Woman with a Parasol, Monet
	"rbxassetid://925192416",    -- A Sunday on La Grande Jatte, Seurat
	"rbxassetid://4623605764",   -- Almond Blossom, Van Gogh
	"rbxassetid://91423198665435", -- Irises, Van Gogh
	"rbxassetid://15816945717",  -- Wheat Field with Cypresses, Van Gogh
	"rbxassetid://108467815321983", -- The Hay Wain, Constable
	"rbxassetid://8178605912",   -- Poppies, Monet
	"rbxassetid://11562220650",  -- Sunset on the Seine, Monet
}

return M
]======]
SOURCES['C_GamingDesk'] = [======[
--[[
	GamingDesk  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds HomeOffice
	Client half of the GAMING DESK (server half: ServerStorage.FunBehaviours.GamingDesk; notes/GamingDesk.md).
	State from the server: Fun_Player (UserId, 0 = empty, -1 = an NPC), Fun_Seed + Fun_Since (the current / last run:
	its course seed and the server time it started), Fun_Ended (server time the last run ended; a run is LIVE while
	Fun_Since > Fun_Ended), Fun_EndTick (the ended run's last sim tick as the gamer reported it; 0 = not known),
	Fun_Final (the last run's score), Fun_Best. Events: "Input" {s, c, n} (the gamer's inputs, relayed to everyone)
	and "Events" {s, c, n} (the whole list, the answer to a "Sync").

	CUKE RUN (2026-09-24, user: "make the gaming desk make u play the actual game instead of just show a video")
	  A real endless runner. Sitting in the desk chair (prompt "Game") opens a GUI for the gamer (CukeRun ScreenGui):
	  the same pixel world the monitor draws (one shared scene builder + DrawWorld), READY? / GO!, then the cucumber
	  hero runs faster and faster: JUMP (Space / W / Up / click / tap / pad A; hold = higher), DUCK (S / Down / pad B
	  or DPadDown; in the air = fall fast) under the flying drones, coins +50, distance = points, a hit = GAME OVER
	  card (score, best, desk HI, PLAY AGAIN / EXIT). While it is open the keys are sunk (ContextActionService above
	  the PlayerModule) and the PlayerModule controls are off (that also hides the touch jump button), so nothing
	  makes the avatar jump out of the chair; only EXIT / X / Backspace (or dying / losing the seat) stands them up.
	SIMULATION  deterministic and fixed-step (TICK_RATE): the course comes from Random.new(Fun_Seed) (gaps between
	  obstacles always longer than a full jump + a reaction time at the current speed), the hero from the list of
	  input events {tick, kind}. The gamer's client appends each press / release at the next tick, plays it at once
	  and sends it ("Input" {s, t, k} or {s, e = {...}}, batched at most every SEND_GAP s); the server relays the list
	  to everyone and keeps it for late joiners ("Sync" -> "Events"). Every other client re-simulates the run from
	  those events SPECTATOR_DELAY s behind real time (checkpoints every MARK_TICKS; a late event rolls back to the
	  checkpoint before it; at most SIM_BUDGET ticks per frame), so each monitor shows the ACTUAL run. The gamer's
	  own monitor draws the GUI's simulation. Both clocks are the SERVER clock (sim time = Kit.Now() - Fun_Since -
	  READY): a hitch on the gamer's client skips time (the missed ticks run at once) instead of pausing the run -
	  a paused gamer would fall behind every replay for good, so each later input would arrive after the replay
	  had passed it (rollbacks, false crashes). At the crash the client sends "Over" {s, score, seconds} (resent
	  until the server ends the run); the server checks it is plausible and sets Final / Best / EndTick / Ended, and
	  a replay of an ended run stops at EndTick (rolling back if it ran past it).
	SCREEN  each monitor panel (ScreenL / ScreenC / ScreenR) gets an invisible LOCAL part laid just in front of it and
	        its ScreenArt* picture, carrying a SurfaceGui that shows its own slice of ONE scene, so the landscape runs
	        on across the curve: sky bands, a sun (a moon while workspace.IsNight), parallax clouds and hills,
	        scrolling ground, crates / double crates / spike blocks / slimes / drones, spinning coins, the hero:
	          attract  nobody playing: the old self-playing demo, the title, "SIT TO PLAY" blinking, the desk's HI
	          ready    READY s after a run starts: "READY?" -> "GO!" (Sfx.ArcadeBlip)
	          run      the gamer's real run: SCORE, "P1 <name>", COINS, "+50" pops (Sfx.Coin), a keyboard clack
	                   (Sfx.Click) for every press, a thump (Sfx.Thump) at the crash
	          over     the crash frozen, "GAME OVER", the score and "NEW HI-SCORE!" (Sfx.ArcadeWin for a new best,
	                   else Sfx.ArcadeLose) - while the gamer stays seated, and OVER_TIME s after they get up
	        The centre screen lights the gamer with a soft SurfaceLight (brighter while playing).
	RGB     every RGB* Neon part flows through the rainbow as a wave along the desk (faster while someone plays),
	        plus one rainbow PointLight under the desk (Pivot_RGBGlow)
	CHAIR   the Swivel* parts turn about Pivot_ChairSwivel (a damped spring): round to face the desk
	        (State_ChairSitYaw) when someone sits, rocking a little while they play, and a full spin back out to
	        State_ChairIdleYaw (the shipped pose) when they get up. Every Swivel* part is authored CanCollide =
	        false (build_GamingDesk.py), so the spin can never shove / fling the character that just got up
	The screens redraw at SCREEN_FPS and the RGB at RGB_FPS; the chair poses every frame only while it moves; the GUI
	draws every frame (its own RenderStepped, like the arcade). No Instance is made per frame: obstacle / coin frames
	are pooled. Cleanup closes the GUI, puts the chair back as shipped (relative to the Hitbox) and the RGB colours.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

local LocalPlayer = Players.LocalPlayer

--..Config: monitor..--
local LOCAL_FOLDER = "FunBuildLocal"   -- client-only workspace folder for the screen + glow parts (shared with the TV)
local PANEL_NAMES = {"ScreenL", "ScreenC", "ScreenR"}
local CENTRE_PANEL = "ScreenC"
local ART_PREFIX = "ScreenArt"         -- the static picture on the panels (the local screens sit in front of it)
local PPS = 90                         -- SurfaceGui pixels per stud
local BRIGHTNESS = 1.15                -- SurfaceGui brightness (LightInfluence 0)
local GUI_MAX_DISTANCE = 220           -- studs: the SurfaceGuis stop drawing beyond this
local GAP = 0.012                      -- authored studs between the front-most layer and the local screen face
local THICK = 0.04                     -- authored thickness of the (invisible) screen parts
local SCREEN_FPS = 30
local SCREEN_RANGE = 150               -- studs (camera): the screens only redraw within this
local LIGHT_COLOR = Color3.fromRGB(165, 215, 255)
local LIGHT_RANGE, LIGHT_ANGLE = 9, 110
local LIGHT_IDLE, LIGHT_PLAY = 0.55, 1.1
local SEAT_NAME = "GamingDeskSeat"     -- the server half's Seat

--..Config: the game. TICK_RATE / READY / the speeds / the course / the points MUST match the server half's
--.. plausibility numbers (RATE = VMAX / PX_PER_POINT + COIN_POINTS / (AIR_TIME + REACT_TIME), rounded up)
--.. Units: art pixels (the hero is 6 x 10) and seconds.
local TICK_RATE = 120                  -- fixed simulation steps per second
local DT = 1 / TICK_RATE
local READY = 1.6                      -- s of "READY?" / "GO!": sim time 0 = Fun_Since + READY
local V0, VMAX = 34, 72                -- run speed (art px / s) at the start line / from RAMP_DIST on
local RAMP_DIST = 4000
local GRAVITY = 520
local JUMP_V = 91.2                    -- a tap peaks at JUMP_V^2 / 2g = 8 px
local HOLD_GRAVITY = 150               -- while JUMP is held and the hero rises, for at most HOLD_TICKS: peak ~15 px
local HOLD_TICKS = 14
local FAST_FALL = 3                    -- gravity x this while DUCK is held in the air
local BUFFER_TICKS = 12                -- a jump pressed this many ticks before landing jumps on landing
local HERO_HALF = 1.8                  -- hit box: half width (drawn 6), height standing / ducking (drawn 10 / 6)
local HERO_H, DUCK_H = 9.2, 5.4
local FIRST = 90                       -- start line -> first obstacle
local AIR_TIME, REACT_TIME = 0.5, 0.45 -- a full jump's airtime + a reaction time = the least running between two obstacles
local GAP_VAR = 0.9                    -- ... plus up to this many seconds more (random)
local DRONE_FROM, DOUBLE_FROM = 500, 1500 -- course px: drones (duck!) and double crates from here on
local DRONE_SHARE, DOUBLE_SHARE = 0.22, 0.15
local COIN_CHANCE, COIN_HIGH_SHARE = 0.65, 0.45
local COIN_LOW, COIN_HIGH = 3, 16      -- coin centre heights: run through it / jump for it
local COIN_R = 1.5
local PX_PER_POINT = 3                 -- distance points
local COIN_POINTS = 50
local MAX_SCORE = 999999
--.. obstacle kinds: drawn width, hit box half width / bottom / top (px above the ground)
local KINDS = {
	crate = {W = 5, Half = 1.9, Bottom = 0, Top = 4.6},
	spike = {W = 5, Half = 1.7, Bottom = 0, Top = 5.0},
	slime = {W = 5, Half = 2.0, Bottom = 0, Top = 3.6},
	double = {W = 10, Half = 4.4, Bottom = 0, Top = 4.6},
	drone = {W = 7, Half = 2.4, Bottom = 6.3, Top = 11},
}
local DRONE_DRAW_TOP = 11.5            -- the drone sprite's top, px above the ground
local EVENT_NAMES = {[0] = "jump", [1] = "jumpUp", [2] = "duck", [3] = "duckUp"}
local EV_JUMP, EV_JUMP_UP, EV_DUCK, EV_DUCK_UP = 0, 1, 2, 3

--.. replays (the monitor of every client that is not the gamer)
local SPECTATOR_DELAY = 0.3            -- s the monitor runs behind real time (inputs arrive before they are needed)
local MARK_TICKS = 60                  -- checkpoint every this many ticks
local MAX_MARKS = 40                   -- (20 s of rollback; older late events re-simulate from the start)
local SIM_BUDGET = 400                 -- ticks per frame at most (~1.5 ms; a late joiner fast-forwards ~100 s of run a second)
local LIVE_TICKS = 30                  -- an advance longer than this is a catch-up: no sounds
local SYNC_RETRY = 2                   -- s between "Sync" requests

--.. the old self-playing attract loop (pure function of Kit.Now())
local IDLE_SPEED = 9                   -- attract mode
local IDLE_WRAP = 3600                 -- s: the attract run restarts every hour (keeps the numbers small)
local IDLE_SPACING = 34                -- between obstacles; a coin halfway between two
local IDLE_JITTER = 5                  -- +/- per obstacle
local JUMP_LEN, JUMP_H = 20, 12        -- an attract jump: world units long (centred on the obstacle), px high
local OVER_TIME = 4                    -- s of GAME OVER after the gamer gets up
local POPUP_TIME = 0.6                 -- s a "+50" floats up

--.. the scene, in art pixels (U screen pixels each)
local ART_H = 36                       -- scene height at least (U = screen height / ART_H; the rest is more sky)
local GROUND_H = 9                     -- ground band (grass + dirt)
local BIG_Y = {idle = 2.2, other = 9}  -- art-pixel rows of the big text (the title sits above the hero's jumps)
local SMALL_Y = {idle = 10.2, other = 17.5}
local HERO_AT = 0.28                   -- hero x as a share of the centre screen
local OBSTACLE_POOL, COIN_POOL = 8, 8

local SKY_DAY = {Color3.fromRGB(92, 172, 255), Color3.fromRGB(124, 196, 255), Color3.fromRGB(166, 222, 255)}
local SKY_NIGHT = {Color3.fromRGB(16, 22, 56), Color3.fromRGB(28, 36, 82), Color3.fromRGB(46, 54, 108)}
local SUN_DAY = {Color3.fromRGB(255, 206, 60), Color3.fromRGB(255, 244, 168)}
local SUN_NIGHT = {Color3.fromRGB(214, 220, 240), Color3.fromRGB(255, 255, 255)}
local NIGHT_DIM = 0.55                 -- everything else at night
local C = {
	Cloud = Color3.fromRGB(255, 255, 255),
	HillA = Color3.fromRGB(64, 160, 118), HillB = Color3.fromRGB(88, 184, 132), HillC = Color3.fromRGB(52, 140, 104),
	Grass = Color3.fromRGB(86, 204, 64), GrassDark = Color3.fromRGB(46, 140, 46),
	Dirt = Color3.fromRGB(152, 98, 52), DirtDark = Color3.fromRGB(118, 72, 38),
	Crate = Color3.fromRGB(196, 130, 62), CrateDark = Color3.fromRGB(122, 76, 34),
	Spike = Color3.fromRGB(176, 186, 202), SpikeDark = Color3.fromRGB(112, 120, 136),
	Slime = Color3.fromRGB(226, 58, 58), Eye = Color3.fromRGB(255, 255, 255), Ink = Color3.fromRGB(24, 24, 30),
	Drone = Color3.fromRGB(128, 94, 214), DroneDark = Color3.fromRGB(74, 54, 138), DroneLight = Color3.fromRGB(255, 70, 70),
	Rotor = Color3.fromRGB(70, 74, 86),
	Coin = Color3.fromRGB(255, 208, 48), CoinShine = Color3.fromRGB(255, 246, 176),
	Hero = Color3.fromRGB(84, 194, 72), HeroDark = Color3.fromRGB(44, 128, 44), Band = Color3.fromRGB(230, 34, 34),
	Leg = Color3.fromRGB(38, 110, 40),
	Text = Color3.fromRGB(255, 255, 255), Title = Color3.fromRGB(255, 214, 64), Green = Color3.fromRGB(157, 255, 36),
	Outline = Color3.fromRGB(12, 12, 18), TitleOutline = Color3.fromRGB(170, 30, 30),
}
local HILLS = {{D = 30, Color = "HillA"}, {D = 20, Color = "HillB"}, {D = 26, Color = "HillC"}} -- art-pixel diameters
local FONT = Enum.Font.Arcade

--.. RGB
local RGB_PREFIX = "RGB"
local RGB_FPS = 20
local RGB_RATE_IDLE, RGB_RATE_PLAY = 0.1, 0.32 -- hue turns per second
local RGB_WAVE = 0.6                   -- hue spread along the desk (0..1 over its width)
local RGB_SAT = 0.85
local GLOW_RANGE, GLOW_BRIGHTNESS = 10, 1.4
local GLOW_FALLBACK = Vector3.new(0, 2.3, 1.5) -- authored, if Pivot_RGBGlow is missing
local DESK_WIDTH = 7.2                 -- authored, for the wave

--.. chair
local SWIVEL_PREFIX = "Swivel"
local SWIVEL_FALLBACK = Vector3.new(0, 0, -2) -- authored, if Pivot_ChairSwivel is missing
local DEFAULT_IDLE_YAW, DEFAULT_SIT_YAW = 32, 0
local SPRING_K, SPRING_C = 24, 7       -- turning to face the desk: a little overshoot
local ROCK_DEG, ROCK_HZ = 2.5, 0.35    -- rocking while playing
local SPIN_OUT = 360                   -- the extra turn when the gamer gets up ...
local SPIN_TIME = 1.6                  -- ... slowing to a stop over this many seconds (constant friction)
local MAX_DT = 1 / 15
local WAKE_GAP = 0.5                   -- s without a Step (camera away) -> snap, no sounds

--.. sounds
local KEYS_RANGE = 45                  -- studs (camera) for keyboard clacks / game sounds
local KEYS_VOLUME = 0.14
local GAME_VOLUME = 0.3

--..Config: the gamer's GUI (the arcade's look: CucumberCatch)..--
local GUI_NAME = "CukeRun"
local GUI_FONT = Enum.Font.FredokaOne
local PANEL = Vector2.new(940, 600)    -- design px; a UIScale fits it to the viewport
local PANEL_DROP = 18                  -- px the panel sits below centre (clear of the top bar)
local VIEW_ART = Vector2.new(88, 36)   -- the game view in art px ...
local GUI_U = 10                       -- ... at this many design px each (880 x 360)
local VIEW_X, VIEW_Y = 30, 78
local GUI_HERO_AT = 0.22
local HUD_H = 46
local CONTROLS_Y = 452
local SEND_GAP = 0.15                  -- s between "Input" sends (the framework allows 12 actions / s)
local SEND_MAX = 24                    -- events per send
local OVER_RESEND = 1.5                -- s: "Over" again while the server still has the run live
local AGAIN_RESEND = 2.5
local CARD_DELAY, CARD_READY = 0.8, 0.45
local SEAT_GRACE = 0.6                 -- s the seat may look lost (replication) before the GUI closes
local CLOSE_RANGE = 20
local ACTION = "CukeRunControls"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 100
local K = Enum.KeyCode
local JUMP_KEYS = {[K.Space] = true, [K.W] = true, [K.Up] = true, [K.ButtonA] = true, [K.DPadUp] = true}
local DUCK_KEYS = {[K.S] = true, [K.Down] = true, [K.DPadDown] = true, [K.ButtonB] = true}
local AGAIN_KEYS = {[K.Space] = true, [K.Return] = true, [K.ButtonA] = true}
local EXIT_KEYS = {[K.Backspace] = true}
local CARD_EXIT_KEYS = {[K.ButtonB] = true}
local SUNK_KEYS = {K.Space, K.W, K.A, K.S, K.D, K.Up, K.Down, K.Left, K.Right, K.Return, K.Backspace,
	K.ButtonA, K.ButtonB, K.ButtonX, K.ButtonY, K.DPadUp, K.DPadDown, K.DPadLeft, K.DPadRight, K.Thumbstick1}
local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)
local DARK = Color3.fromRGB(23, 26, 32)
local GREEN = {Top = Color3.fromRGB(157, 255, 36), Bottom = Color3.fromRGB(69, 255, 0), Highlight = Color3.fromRGB(208, 255, 106)}
local RED = {Top = Color3.fromRGB(255, 100, 100), Bottom = Color3.fromRGB(230, 30, 30), Highlight = Color3.fromRGB(255, 196, 196)}
local DESK_TOP, DESK_BOTTOM = Color3.fromRGB(46, 48, 62), Color3.fromRGB(22, 23, 31)
local DESK_TRIM = Color3.fromRGB(217, 68, 60)
local NEON_CYAN = Color3.fromRGB(77, 210, 255)
local GOLD = Color3.fromRGB(255, 214, 64)
local CUKE = "\u{1F952}"
local PARTY = "\u{1F389}"

--..Shared..--
local Active = nil      -- the open game (one at a time on this client)
local PersonalBest = 0  -- this session, any desk

local B = {}
B.Keys = {"GamingDesk"}
B.StepRange = 170

--..Helpers..--
local function New(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function Try(inst, prop, value)
	pcall(function() inst[prop] = value end)
end

local function LocalFolder()
	local folder = workspace:FindFirstChild(LOCAL_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = LOCAL_FOLDER
		folder.Archivable = false
		folder.Parent = workspace
	end
	return folder
end

local function HalfExtent(part, dir)
	local cf, s = part.CFrame, part.Size
	return 0.5 * (math.abs(cf.XVector:Dot(dir)) * s.X + math.abs(cf.YVector:Dot(dir)) * s.Y + math.abs(cf.ZVector:Dot(dir)) * s.Z)
end

local function Dim(color, k)
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

--.. a deterministic 0..1 per integer (same on every client; the attract loop)
local function Hash(k, salt)
	local v = math.sin(k * 12.9898 + salt * 78.233) * 43758.5453
	return v - math.floor(v)
end

local function Pad(n)
	return string.format("%06d", math.clamp(math.floor(n), 0, MAX_SCORE))
end

local function Finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function SetText(label, text)
	if label.Text ~= text then label.Text = text end
end

local function IsTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

--..Simulation: the course (a pure function of the seed, generated lazily in one fixed order)..--
local function Speed(x)
	return V0 + (VMAX - V0) * math.min(1, x / RAMP_DIST)
end

local function NewCourse(seed)
	return {Rng = Random.new(seed), X = {}, Kind = {}, CoinX = {}, CoinY = {}, N = 0, NextX = FIRST, NextKind = nil}
end

--.. always three draws, whatever comes out (keeps the stream in step)
local function PickKind(course, x)
	local a, b, c = course.Rng:NextNumber(), course.Rng:NextNumber(), course.Rng:NextNumber()
	if x >= DRONE_FROM and a < DRONE_SHARE then return "drone" end
	if x >= DOUBLE_FROM and b < DOUBLE_SHARE then return "double" end
	return c < 0.42 and "crate" or (c < 0.74 and "spike" or "slime")
end

--.. obstacles (and the coin in the gap after each) up to course x
local function Extend(course, uptoX)
	while course.N == 0 or course.X[course.N] < uptoX do
		local x = course.NextX
		local kind = course.NextKind or PickKind(course, x)
		local n = course.N + 1
		course.N = n
		course.X[n], course.Kind[n] = x, kind
		local nextKind = PickKind(course, x)
		local v = Speed(x)
		local gap = (KINDS[kind].W + KINDS[nextKind].W) * 0.5 + v * (AIR_TIME + REACT_TIME) + course.Rng:NextNumber() * v * GAP_VAR
		local coinRoll, coinHigh = course.Rng:NextNumber(), course.Rng:NextNumber()
		if coinRoll < COIN_CHANCE then
			course.CoinX[n], course.CoinY[n] = x + gap * 0.5, coinHigh < COIN_HIGH_SHARE and COIN_HIGH or COIN_LOW
		else
			course.CoinX[n], course.CoinY[n] = false, false
		end
		course.NextX, course.NextKind = x + gap, nextKind
	end
end

--..Simulation: the hero (fixed step; only + - * / and comparisons, so every client gets the same bits)..--
local SIM_FIELDS = {"N", "X", "Y", "VY", "Ground", "JumpHeld", "DuckHeld", "Hold", "Buffer", "Dead", "DeadTick",
	"Coins", "CoinTick", "Obs", "Coin", "Ev", "Jumps", "Presses"}

local function NewSim()
	return {N = 0, X = 0, Y = 0, VY = 0, Ground = true, JumpHeld = false, DuckHeld = false, Hold = HOLD_TICKS, Buffer = 0,
		Dead = false, DeadTick = 0, Coins = 0, CoinTick = -1e9, Obs = 1, Coin = 1, Ev = 1, Jumps = 0, Presses = 0, Got = {}}
end

local function Snapshot(s)
	local m = {}
	for _, k in ipairs(SIM_FIELDS) do m[k] = s[k] end
	return m
end

--.. s.Got (coin index -> collected) is shared, not copied: entries at or past s.Coin are rewritten when re-simulated
local function Restore(s, m)
	for _, k in ipairs(SIM_FIELDS) do s[k] = m[k] end
end

local function Score(s)
	return math.min(MAX_SCORE, math.floor(s.X / PX_PER_POINT) + COIN_POINTS * s.Coins)
end

local function Jump(s)
	s.VY, s.Ground, s.Hold, s.Buffer = JUMP_V, false, 0, 0
	s.Jumps += 1
end

local function HeroHeight(s)
	return (s.Ground and s.DuckHeld) and DUCK_H or HERO_H
end

--.. one tick: the inputs stamped with it, running, gravity, then obstacles and coins
local function StepSim(s, course, ticks, kinds)
	local n = s.N + 1
	local i = s.Ev
	while ticks[i] and ticks[i] <= n do
		local k = kinds[i]
		if k == EV_JUMP then
			s.JumpHeld = true
			s.Presses += 1
			if s.Ground then Jump(s) else s.Buffer = BUFFER_TICKS end
		elseif k == EV_JUMP_UP then
			s.JumpHeld = false
			if not s.Ground then s.Hold = HOLD_TICKS end
		elseif k == EV_DUCK then
			s.DuckHeld = true
			s.Presses += 1
		elseif k == EV_DUCK_UP then
			s.DuckHeld = false
		end
		i += 1
	end
	s.Ev = i
	s.X += Speed(s.X) * DT
	if not s.Ground then
		local g
		if s.JumpHeld and s.VY > 0 and s.Hold < HOLD_TICKS and not s.DuckHeld then
			g = HOLD_GRAVITY
			s.Hold += 1
		else
			g = s.DuckHeld and GRAVITY * FAST_FALL or GRAVITY
		end
		s.VY -= g * DT
		s.Y += s.VY * DT
		if s.Y <= 0 then
			s.Y, s.VY, s.Ground = 0, 0, true
			if s.Buffer > 0 then Jump(s) end
		end
	end
	if s.Buffer > 0 then s.Buffer -= 1 end
	s.N = n

	--.. obstacles: the first one not yet behind the hero
	local h = HeroHeight(s)
	local left, right = s.X - HERO_HALF, s.X + HERO_HALF
	Extend(course, s.X + 40)
	local j = s.Obs
	while true do
		local kind = KINDS[course.Kind[j]]
		local ox = course.X[j]
		if ox + kind.Half < left then
			j += 1
		else
			if ox - kind.Half < right and s.Y < kind.Top and s.Y + h > kind.Bottom then
				s.Dead, s.DeadTick = true, n
			end
			break
		end
	end
	s.Obs = j

	--.. coins: resolved in order (collected, or missed once behind the hero)
	local c = s.Coin
	while c <= course.N do
		local cx = course.CoinX[c]
		if not cx then
			c += 1
		elseif cx + COIN_R < left then
			s.Got[c] = false
			c += 1
		elseif cx - COIN_R < right then
			local cy = course.CoinY[c]
			if s.Y < cy + COIN_R and s.Y + h > cy - COIN_R then
				s.Got[c] = true
				s.Coins += 1
				s.CoinTick = n
				c += 1
			else
				break
			end
		else
			break
		end
	end
	s.Coin = c
end

--..Runs (a course + its event list + a simulation with checkpoints): the gamer's GUI and every monitor use them..--
local function NewRun(seed)
	return {Seed = seed, Course = NewCourse(seed), Ticks = {}, Kinds = {}, Sim = NewSim(), Marks = {}, Dirty = nil, Heard = 0, Complete = false}
end

--.. an event code from the server: tick * 4 + kind
local function AddCode(run, code)
	if not Finite(code) or code < 0 then return end
	local tick, kind = math.floor(code / 4), code % 4
	local last = run.Ticks[#run.Ticks]
	if last and tick < last then return end -- out of order (never sent by the server)
	table.insert(run.Ticks, tick)
	table.insert(run.Kinds, kind)
	if tick <= run.Sim.N then run.Dirty = math.min(run.Dirty or math.huge, tick) end
end

--.. replace the whole list ("Events"): roll back to where it first differs
local function SetCodes(run, codes)
	local oldT, oldK = run.Ticks, run.Kinds
	run.Ticks, run.Kinds = {}, {}
	local keep = run.Dirty
	for _, code in ipairs(codes) do AddCode(run, code) end
	run.Dirty = keep
	local first = nil
	local count = math.max(#oldT, #run.Ticks)
	for i = 1, count do
		if oldT[i] ~= run.Ticks[i] or oldK[i] ~= run.Kinds[i] then
			first = math.min(oldT[i] or math.huge, run.Ticks[i] or math.huge)
			break
		end
	end
	if first and first <= run.Sim.N then run.Dirty = math.min(run.Dirty or math.huge, first) end
end

--.. step the run on to `target` ticks (at most `budget` ticks now); hooks[name](run) fire for ticks never heard before
--.. while the advance is live (a small step, not a catch-up or a rollback): Press, Jump, Coin, Crash
local function Advance(run, target, budget, hooks)
	local s = run.Sim
	if run.Dirty then
		local mark = nil
		for i = #run.Marks, 1, -1 do
			if run.Marks[i].N < run.Dirty then
				mark = run.Marks[i]
				break
			end
			run.Marks[i] = nil
		end
		Restore(s, mark or Snapshot(NewSim()))
		run.Dirty = nil
	end
	local live = target - s.N <= LIVE_TICKS
	local steps = 0
	while s.N < target and not s.Dead and steps < budget do
		local presses, jumps, coins = s.Presses, s.Jumps, s.Coins
		StepSim(s, run.Course, run.Ticks, run.Kinds)
		steps += 1
		if s.N % MARK_TICKS == 0 then
			table.insert(run.Marks, Snapshot(s))
			if #run.Marks > MAX_MARKS then table.remove(run.Marks, 1) end
		end
		if hooks and live and s.N > run.Heard then
			if s.Presses > presses and hooks.Press then hooks.Press(run) end
			if s.Jumps > jumps and hooks.Jump then hooks.Jump(run) end
			if s.Coins > coins and hooks.Coin then hooks.Coin(run) end
			if s.Dead and hooks.Crash then hooks.Crash(run) end
		end
	end
	if s.N > run.Heard then run.Heard = s.N end
end

--..Screen geometry..--
--.. a panel's local screen: CFrame (LookVector = out of the screen), Size, and its "right" (the part's +X, which is the
--.. viewer's LEFT on a Front-face SurfaceGui). The face goes GAP past the front-most layer over the panel (the panel
--.. itself or a ScreenArt* part lying on it)
local function PanelGeometry(model, panel, arts, scale)
	local origin = Kit.Origin(model)
	local front, upWorld = origin.LookVector, origin.UpVector
	local cf = panel.CFrame
	local axes = {cf.XVector, cf.YVector, cf.ZVector}
	local sizes = {panel.Size.X, panel.Size.Y, panel.Size.Z}
	local ni, nBest = 1, -1
	for i = 1, 3 do
		local d = math.abs(axes[i]:Dot(front))
		if d > nBest then ni, nBest = i, d end
	end
	local ui, uBest = nil, -1
	for i = 1, 3 do
		if i ~= ni then
			local d = math.abs(axes[i]:Dot(upWorld))
			if d > uBest then ui, uBest = i, d end
		end
	end
	local wi = 6 - ni - ui
	local normal = axes[ni] * (axes[ni]:Dot(front) >= 0 and 1 or -1)
	local up = axes[ui] * (axes[ui]:Dot(upWorld) >= 0 and 1 or -1)
	local width, height = sizes[wi], sizes[ui]
	local right = up:Cross(-normal)
	local centre = panel.Position
	local lead = HalfExtent(panel, normal)
	for _, p in ipairs(arts) do
		local rel = p.Position - centre
		if math.abs(rel:Dot(right)) <= width * 0.5 + 0.02 and math.abs(rel:Dot(up)) <= height * 0.5 + 0.02 and math.abs(rel:Dot(normal)) < 0.4 * scale then
			lead = math.max(lead, rel:Dot(normal) + HalfExtent(p, normal))
		end
	end
	local thick = THICK * scale
	local position = centre + normal * (lead + GAP * scale - thick * 0.5)
	return CFrame.fromMatrix(position, right, up, -normal), Vector3.new(width, height, thick), right
end

--..Scene (the monitor makes one copy per panel - each copy is the whole scene, shifted so its panel shows its own
--.. slice; the gamer's GUI makes one). L = the layout: U (px per art px), W / H (px), AW (art px wide), groundA,
--.. heroA (art px), centreX0 / centreW (px: where the HUD goes)..--
local function NewScene(gui, L, offsetPx, withHud)
	local U = L.U
	local S = {tints = {}, sky = {}, sun = {}, clouds = {}, hills = {}, obstacles = {}, coins = {}, pose = nil}
	local function Px(a) return math.floor(a * U + 0.5) end
	local function Box(name, parent, x, y, w, h, color, z, corner)
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color or C.Ink
		f.BackgroundTransparency = color and 0 or 1
		f.Position = UDim2.fromOffset(Px(x), Px(y))
		f.Size = UDim2.fromOffset(math.max(1, Px(w)), math.max(1, Px(h)))
		f.ZIndex = z or 1
		if corner then New("UICorner", {CornerRadius = corner}, f) end
		f.Parent = parent
		return f
	end
	local function Tint(f)
		table.insert(S.tints, {f, f.BackgroundColor3})
		return f
	end
	local round = UDim.new(0.5, 0)
	local soft = UDim.new(0, math.max(1, Px(1)))

	local root = New("Frame", {
		Name = "Scene", BorderSizePixel = 0, BackgroundColor3 = SKY_DAY[3], Position = UDim2.fromOffset(-offsetPx, 0),
		Size = UDim2.fromOffset(L.W, L.H), ClipsDescendants = true, ZIndex = 1,
	}, gui)
	S.root = root
	local gA, AW = L.groundA, L.AW

	--.. sky bands + sun
	S.sky[1] = Box("Sky1", root, 0, 0, AW + 1, gA * 0.42, SKY_DAY[1], 1)
	S.sky[2] = Box("Sky2", root, 0, gA * 0.42, AW + 1, gA * 0.3, SKY_DAY[2], 1)
	S.sky[3] = Box("Sky3", root, 0, gA * 0.72, AW + 1, gA * 0.3, SKY_DAY[3], 1)
	S.sun[1] = Box("Sun", root, AW * 0.8, 3, 7, 7, SUN_DAY[1], 2, soft)
	S.sun[2] = Box("SunCore", S.sun[1], 1.5, 1.5, 4, 4, SUN_DAY[2], 1, soft)

	--.. clouds (a base + a puff), hills (big circles half under the ground)
	for i, cy in ipairs({3, 8, 5, 10}) do
		local c = Box("Cloud" .. i, root, 0, cy, 12, 5, nil, 3)
		Tint(Box("Base", c, 0, 2, 12, 3, C.Cloud, 1, soft))
		Tint(Box("Puff", c, 3, 0, 6, 3, C.Cloud, 1, soft))
		S.clouds[i] = c
	end
	for i, h in ipairs(HILLS) do
		S.hills[i] = Tint(Box("Hill" .. i, root, 0, gA - h.D * 0.42, h.D, h.D, C[h.Color], 4, round))
	end

	--.. ground: grass, its dark edge, dirt to the bottom, and a scrolling row of dirt tiles
	Tint(Box("Grass", root, 0, gA, AW + 1, 2, C.Grass, 5))
	Tint(Box("GrassEdge", root, 0, gA + 2, AW + 1, 1, C.GrassDark, 5))
	local dirt = Tint(Box("Dirt", root, 0, gA + 3, AW + 1, 1, C.Dirt, 5))
	dirt.Size = UDim2.fromOffset(L.W + U, math.max(1, L.H - Px(gA + 3)))
	S.tiles = Box("Tiles", root, 0, gA + 4, AW + 16, 5, nil, 6)
	for x = 0, AW + 16, 8 do
		Tint(Box("T", S.tiles, x, 0.5, 2, 1, C.DirtDark, 1))
		Tint(Box("T", S.tiles, x + 4, 2.5, 2, 1, C.DirtDark, 1))
	end
	--.. grass tufts scroll with the tiles
	for x = 0, AW + 16, 8 do
		Tint(Box("Tuft", S.tiles, x + 2, -4.5, 1, 1, C.Grass, 1))
	end

	--.. obstacles: every slot holds all five kinds, one shown at a time. The slot's left edge is the obstacle's
	--.. centre - 2.5 and its top 6 px above the ground (a drone slot is lifted to DRONE_DRAW_TOP)
	for i = 1, OBSTACLE_POOL do
		local slot = Box("Obstacle" .. i, root, -10, gA - 6, 5, 6, nil, 7)
		slot.Visible = false
		local crate = Box("Crate", slot, 0, 1, 5, 5, nil, 1)
		Tint(Box("Box", crate, 0, 0, 5, 5, C.Crate, 1))
		Tint(Box("Inset", crate, 1, 1, 3, 3, C.CrateDark, 1))
		Tint(Box("Plank", crate, 1, 2, 3, 1, C.Crate, 1))
		local double = Box("Double", slot, -2.5, 1, 10, 5, nil, 1)
		for d = 0, 1 do
			Tint(Box("Box" .. d, double, d * 5, 0, 5, 5, C.Crate, 1))
			Tint(Box("Inset" .. d, double, d * 5 + 1, 1, 3, 3, C.CrateDark, 1))
			Tint(Box("Plank" .. d, double, d * 5 + 1, 2, 3, 1, C.Crate, 1))
		end
		local spike = Box("Spike", slot, 0, 0, 5, 6, nil, 1)
		Tint(Box("S1", spike, 0, 4, 5, 2, C.SpikeDark, 1))
		Tint(Box("S2", spike, 1, 2, 3, 2, C.Spike, 1))
		Tint(Box("S3", spike, 2, 0, 1, 2, C.Spike, 1))
		local slime = Box("Slime", slot, 0, 2, 5, 4, nil, 1)
		Tint(Box("Body", slime, 0, 0, 5, 4, C.Slime, 1, UDim.new(0, math.max(1, Px(1.5)))))
		Box("EyeA", slime, 0.6, 1, 1, 1, C.Eye, 1)
		Box("EyeB", slime, 2.4, 1, 1, 1, C.Eye, 1)
		local drone = Box("Drone", slot, -1, 0, 7, 5, nil, 1)
		local rotor = Tint(Box("Rotor", drone, 0, 0, 7, 1, C.Rotor, 2))
		Tint(Box("Mast", drone, 3, 1, 1, 1, C.Rotor, 1))
		Tint(Box("Body", drone, 1, 2, 5, 3, C.Drone, 1, soft))
		Tint(Box("Belly", drone, 1.5, 4, 4, 1, C.DroneDark, 2))
		Box("Light", drone, 1.6, 2.7, 1.2, 1.2, C.DroneLight, 3)
		S.obstacles[i] = {slot = slot, kinds = {crate = crate, double = double, spike = spike, slime = slime, drone = drone}, kind = nil, rotor = rotor, spin = nil}
	end
	for _, o in ipairs(S.obstacles) do
		for _, g in pairs(o.kinds) do g.Visible = false end
	end

	--.. coins
	for i = 1, COIN_POOL do
		local coin = Box("Coin" .. i, root, -10, gA - 6, 3, 3, C.Coin, 7, round)
		Box("Shine", coin, 0.6, 0.6, 1, 1, C.CoinShine, 1, round)
		coin.Visible = false
		S.coins[i] = coin
	end

	--.. the hero: a cucumber in a red headband (faces right = the way it runs). Poses: Stand (running, jumping,
	--.. crashed: dizzy X eyes) and Duck (squashed low under the drones)
	local hero = Box("Hero", root, L.heroA - 3, gA - 10, 6, 10, nil, 8)
	local stand = Box("Stand", hero, 0, 0, 6, 10, nil, 1)
	S.heroTail = Box("Tail", stand, -2, 2, 2, 1, C.Band, 1)
	Box("Body", stand, 0, 0, 6, 8, C.Hero, 2, UDim.new(0, math.max(1, Px(2.5))))
	Box("StripeA", stand, 1, 2, 1, 5, C.HeroDark, 3)
	Box("StripeB", stand, 2.5, 3, 1, 4, C.HeroDark, 3)
	Box("Band", stand, 0, 1.6, 6, 1, C.Band, 4)
	S.eye = Box("Eye", stand, 3.4, 3, 2, 2, C.Eye, 4)
	S.pupil = Box("Pupil", stand, 4.4, 3.5, 1, 1, C.Ink, 5)
	Box("Mouth", stand, 4, 6, 1.4, 0.5, C.Ink, 4)
	local dizzy = Box("Dizzy", stand, 3.1, 2.7, 3, 3, nil, 5)
	for _, p in ipairs({{0, 0}, {2, 0}, {1, 1}, {0, 2}, {2, 2}}) do Box("X", dizzy, p[1], p[2], 1, 1, C.Ink, 1) end
	dizzy.Visible = false
	S.dizzy = dizzy
	S.legA = Box("LegA", stand, 1.5, 8, 1, 2, C.Leg, 1)
	S.legB = Box("LegB", stand, 3.5, 8, 1, 2, C.Leg, 1)
	local duck = Box("Duck", hero, -1, 4, 8, 6, nil, 1)
	Box("Tail", duck, -2, 1, 2, 1, C.Band, 1)
	Box("Body", duck, 0, 0, 8, 5, C.Hero, 2, UDim.new(0, math.max(1, Px(2))))
	Box("StripeA", duck, 1, 2.2, 4, 1, C.HeroDark, 3)
	Box("StripeB", duck, 1.5, 3.4, 3, 1, C.HeroDark, 3)
	Box("Band", duck, 0, 0.8, 8, 1, C.Band, 4)
	Box("Eye", duck, 5.4, 1.8, 2, 2, C.Eye, 4)
	Box("Pupil", duck, 6.4, 2.3, 1, 1, C.Ink, 5)
	Box("LegA", duck, 1.5, 5, 1, 1, C.Leg, 1)
	Box("LegB", duck, 5, 5, 1, 1, C.Leg, 1)
	duck.Visible = false
	S.stand, S.duck, S.hero = stand, duck, hero

	--.. "+50"
	S.popup = New("TextLabel", {
		Name = "Popup", BackgroundTransparency = 1, Font = FONT, Text = "+" .. COIN_POINTS, TextColor3 = C.Title,
		TextScaled = true, Size = UDim2.fromOffset(Px(10), Px(3.5)), Visible = false, ZIndex = 9,
	}, root)
	New("UIStroke", {Color = C.Outline, Thickness = 1}, S.popup)

	--.. HUD, inside the centre panel's slice (the monitor only; the GUI has its own)
	if withHud then
		local x0, w = L.centreX0, L.centreW
		local function Label(name, x, y, width, height, color, align, strokeColor, strokeThickness)
			local t = New("TextLabel", {
				Name = name, BackgroundTransparency = 1, Font = FONT, Text = "", TextColor3 = color, TextScaled = true,
				TextXAlignment = align or Enum.TextXAlignment.Center, Position = UDim2.fromOffset(math.floor(x), math.floor(y)),
				Size = UDim2.fromOffset(math.floor(width), math.floor(height)), ZIndex = 10,
			}, root)
			New("UIStroke", {Color = strokeColor or C.Outline, Thickness = strokeThickness or 1.5}, t)
			return t
		end
		S.score = Label("Score", x0 + Px(2), Px(1), w * 0.55, Px(3.6), C.Text, Enum.TextXAlignment.Left)
		S.name = Label("Name", x0 + Px(2), Px(5), w * 0.55, Px(2.8), C.Green, Enum.TextXAlignment.Left)
		S.coinCount = Label("Coins", x0 + w * 0.62, Px(1), w * 0.38 - Px(2), Px(3.6), C.Title, Enum.TextXAlignment.Right)
		S.big = Label("Big", x0 + w * 0.08, Px(9), w * 0.84, Px(7.5), C.Title, Enum.TextXAlignment.Center, C.TitleOutline, 2)
		S.small = Label("Small", x0 + w * 0.15, Px(17.5), w * 0.7, Px(3.4), C.Text)
	end
	return S
end

--.. night colours on / off for one scene copy
local function PaintScene(S, night)
	for i, f in ipairs(S.sky) do f.BackgroundColor3 = night and SKY_NIGHT[i] or SKY_DAY[i] end
	S.root.BackgroundColor3 = night and SKY_NIGHT[3] or SKY_DAY[3]
	for i, f in ipairs(S.sun) do f.BackgroundColor3 = night and SUN_NIGHT[i] or SUN_DAY[i] end
	for _, t in ipairs(S.tints) do t[1].BackgroundColor3 = night and Dim(t[2], NIGHT_DIM) or t[2] end
end

--..World views: what to draw, in course coordinates (filled into a reused table W)..--
--.. W = {CamX, HeroY, Pose ("stand" / "run" / "air" / "duck" / "dead"), Step (0 / 1), Obs = {{X, Kind, K}}, NObs,
--..      Coins = {{X, Y, J}}, NCoins, Popup (nil or 0..1 rise)}
local function NewView()
	local W = {CamX = 0, HeroY = 0, Pose = "stand", Step = 0, Obs = {}, NObs = 0, Coins = {}, NCoins = 0, Popup = nil}
	for i = 1, OBSTACLE_POOL do W.Obs[i] = {X = 0, Kind = "crate", K = 0} end
	for i = 1, COIN_POOL do W.Coins[i] = {X = 0, Y = 0, J = 0} end
	return W
end

local function PutObstacle(W, x, kind, k)
	if W.NObs >= OBSTACLE_POOL then return end
	W.NObs += 1
	local o = W.Obs[W.NObs]
	o.X, o.Kind, o.K = x, kind, k
end

local function PutCoin(W, x, y, j)
	if W.NCoins >= COIN_POOL then return end
	W.NCoins += 1
	local c = W.Coins[W.NCoins]
	c.X, c.Y, c.J = x, y, j
end

--.. the attract loop: the old self-playing run, a pure function of now (every client shows the same frame)
local function ViewAttract(W, L, now)
	local camX = IDLE_SPEED * (now % IDLE_WRAP)
	local heroA, AW = L.heroA, L.AW
	W.CamX, W.NObs, W.NCoins, W.Popup = camX, 0, 0, nil
	local lo, hi = camX - heroA - 8, camX + AW - heroA + 8
	for k = math.ceil((lo - IDLE_JITTER) / IDLE_SPACING), math.floor((hi + IDLE_JITTER) / IDLE_SPACING) do
		local x = k * IDLE_SPACING + (Hash(k, 1) * 2 - 1) * IDLE_JITTER
		if x > lo and x < hi then
			local h = Hash(k, 2)
			PutObstacle(W, x, h < 0.45 and "crate" or (h < 0.75 and "spike" or "slime"), k)
		end
	end
	for j = math.ceil(camX / IDLE_SPACING - 0.5), math.floor(hi / IDLE_SPACING - 0.5) do
		local x = (j + 0.5) * IDLE_SPACING
		if x > camX then PutCoin(W, x, 5, j) end
	end
	--.. the hero's jump: an arc JUMP_LEN long centred on each obstacle
	local jumpY = 0
	local kNear = math.floor(camX / IDLE_SPACING + 0.5)
	for k = kNear - 1, kNear + 1 do
		local x = k * IDLE_SPACING + (Hash(k, 1) * 2 - 1) * IDLE_JITTER
		local u = (camX - (x - JUMP_LEN * 0.5)) / JUMP_LEN
		if u > 0 and u < 1 then jumpY = math.max(jumpY, JUMP_H * 4 * u * (1 - u)) end
	end
	W.HeroY = jumpY
	W.Pose = jumpY > 0.4 and "air" or "run"
	W.Step = math.floor(now / 0.13) % 2
end

--.. a real run: its simulation as it stands
local function ViewRun(W, L, run)
	local s, course = run.Sim, run.Course
	local camX = s.X
	local lo, hi = camX - L.heroA - 12, camX + L.AW - L.heroA + 12
	Extend(course, hi)
	W.CamX, W.HeroY, W.NObs, W.NCoins = camX, s.Y, 0, 0
	for i = math.max(1, s.Obs - 4), course.N do
		local x = course.X[i]
		if x > hi then break end
		if x >= lo then PutObstacle(W, x, course.Kind[i], i) end
	end
	for i = math.max(1, s.Coin - 4), course.N do
		local x = course.CoinX[i]
		if x then
			if x > hi then break end
			if x >= lo and (i >= s.Coin or not s.Got[i]) then PutCoin(W, x, course.CoinY[i], i) end
		end
	end
	if s.Dead then
		W.Pose = "dead"
	elseif s.N == 0 then
		W.Pose = "stand"
	elseif not s.Ground then
		W.Pose = "air"
	elseif s.DuckHeld then
		W.Pose = "duck"
	else
		W.Pose = "run"
	end
	W.Step = math.floor(s.N / 8) % 2
	local age = s.N - s.CoinTick
	W.Popup = (age >= 0 and age < POPUP_TIME * TICK_RATE) and age / (POPUP_TIME * TICK_RATE) or nil
end

--..DrawWorld: one view into every copy of a scene (the monitor's three slices, or the GUI). hud = optional texts
--.. {Score, Name, Coins, Big, Small, BigY, SmallY} for copies that carry the pixel HUD..--
local function DrawWorld(scenes, L, W, now, hud)
	local U = L.U
	local heroA, AW, gA, camX = L.heroA, L.AW, L.groundA, W.CamX

	--.. parallax layers
	local cloudSpan, hillSpan = AW + 16, AW + 36
	local cloudUD, hillUD = {}, {}
	for i = 1, 4 do
		local x = ((i - 1) * cloudSpan / 4 - camX * 0.15) % cloudSpan - 14
		cloudUD[i] = UDim2.fromOffset(math.floor(x * U), 0)
	end
	for i = 1, #HILLS do
		local x = ((i - 1) * hillSpan / 3 + 6 - camX * 0.4) % hillSpan - 32
		hillUD[i] = UDim2.fromOffset(math.floor(x * U), math.floor((gA - HILLS[i].D * 0.42) * U))
	end
	local tilesUD = UDim2.fromOffset(math.floor(-((camX % 8) * U)), math.floor((gA + 4) * U))

	--.. the hero
	local pose = W.Pose
	local ducking = pose == "duck"
	local airborne = pose == "air"
	local heroUD = UDim2.fromOffset(math.floor((heroA - 3) * U), math.floor((gA - 10 - (ducking and 0 or W.HeroY)) * U))
	local legAY, legBY = 8, 8
	if airborne then
		legAY, legBY = 7, 7
	elseif pose == "run" then
		legAY, legBY = W.Step == 1 and 7 or 8, W.Step == 0 and 7 or 8
	end
	local legAUD = UDim2.fromOffset(math.floor(1.5 * U), math.floor(legAY * U))
	local legBUD = UDim2.fromOffset(math.floor(3.5 * U), math.floor(legBY * U))
	local tailUD = UDim2.fromOffset(math.floor(-2 * U), math.floor(((pose == "run" or airborne) and W.Step == 1 and 1.6 or 2.2) * U))

	--.. obstacles / coins
	local obsUD = {}
	for i = 1, W.NObs do
		local o = W.Obs[i]
		local sx = heroA + (o.X - camX)
		local bob = (o.Kind == "slime" or o.Kind == "drone") and (math.floor(now * 4 + o.K) % 2) or 0
		local top = o.Kind == "drone" and (gA - DRONE_DRAW_TOP + bob * 0.5) or (gA - 6 - bob * 0.5)
		obsUD[i] = UDim2.fromOffset(math.floor((sx - 2.5) * U), math.floor(top * U))
	end
	local spin = math.floor(now * 14) % 2
	local rotorPos = spin == 0 and UDim2.fromOffset(0, 0) or UDim2.fromOffset(math.floor(2 * U), 0)
	local rotorSize = UDim2.fromOffset(spin == 0 and math.floor(7 * U) or math.floor(3 * U), math.max(1, math.floor(U)))
	local coinUD, coinSize = {}, {}
	for i = 1, W.NCoins do
		local cn = W.Coins[i]
		local cspin = math.abs(math.cos(now * 5 + cn.J))
		local w = math.max(1, math.floor((1 + 2 * cspin) * U + 0.5))
		local bobY = math.sin(now * 3 + cn.J) * 0.6
		coinUD[i] = UDim2.fromOffset(math.floor((heroA + (cn.X - camX)) * U - w * 0.5), math.floor((gA - cn.Y - COIN_R + bobY) * U))
		coinSize[i] = UDim2.fromOffset(w, math.floor(3 * U))
	end
	local popupRise = W.Popup
	local popupUD = popupRise and UDim2.fromOffset(math.floor((heroA - 5) * U), math.floor((gA - 13 - W.HeroY * 0.5 - popupRise * 6) * U)) or nil
	local bigUD, smallUD
	if hud then
		bigUD = UDim2.fromOffset(math.floor(L.centreX0 + L.centreW * 0.08), math.floor(hud.BigY * U))
		smallUD = UDim2.fromOffset(math.floor(L.centreX0 + L.centreW * 0.15), math.floor(hud.SmallY * U))
	end

	for _, S in ipairs(scenes) do
		for i, c in ipairs(S.clouds) do c.Position = cloudUD[i] end
		for i, h in ipairs(S.hills) do h.Position = hillUD[i] end
		S.tiles.Position = tilesUD
		S.hero.Position = heroUD
		if S.pose ~= pose then
			S.pose = pose
			S.stand.Visible = not ducking
			S.duck.Visible = ducking
			local dead = pose == "dead"
			S.dizzy.Visible = dead
			S.eye.Visible = not dead
			S.pupil.Visible = not dead
		end
		S.legA.Position = legAUD
		S.legB.Position = legBUD
		S.heroTail.Position = tailUD
		for i, slot in ipairs(S.obstacles) do
			if i <= W.NObs then
				local kind = W.Obs[i].Kind
				slot.slot.Position = obsUD[i]
				if slot.kind ~= kind then
					if slot.kind then slot.kinds[slot.kind].Visible = false end
					slot.kind = kind
					slot.kinds[kind].Visible = true
				end
				if kind == "drone" and slot.spin ~= spin then
					slot.spin = spin
					slot.rotor.Position = rotorPos
					slot.rotor.Size = rotorSize
				end
				if not slot.slot.Visible then slot.slot.Visible = true end
			elseif slot.slot.Visible then
				slot.slot.Visible = false
			end
		end
		for i, coin in ipairs(S.coins) do
			if i <= W.NCoins then
				coin.Position = coinUD[i]
				coin.Size = coinSize[i]
				if not coin.Visible then coin.Visible = true end
			elseif coin.Visible then
				coin.Visible = false
			end
		end
		S.popup.Visible = popupRise ~= nil
		if popupRise then
			S.popup.Position = popupUD
			S.popup.TextTransparency = popupRise * 0.8
		end
		if hud and S.score then
			SetText(S.score, hud.Score)
			SetText(S.name, hud.Name)
			SetText(S.coinCount, hud.Coins)
			SetText(S.big, hud.Big)
			SetText(S.small, hud.Small)
			S.big.Position = bigUD
			S.small.Position = smallUD
		end
	end
end

--..State (read every frame; attributes are cheap)..--
local function ReadState(ctx)
	return tonumber(ctx:State("Player")) or 0, tonumber(ctx:State("Since")) or 0, tonumber(ctx:State("Ended")) or 0,
		tonumber(ctx:State("Final")) or 0, tonumber(ctx:State("Best")) or 0, tonumber(ctx:State("Seed")) or 0
end

--..GUI helpers (the arcade's look)..--
local function Corner(parent, px)
	return New("UICorner", {CornerRadius = UDim.new(0, px or 12)}, parent)
end

local function Round(parent)
	return New("UICorner", {CornerRadius = UDim.new(1, 0)}, parent)
end

--.. border = true strokes a frame's edge; otherwise (Contextual) a text object's glyphs
local function Stroke(parent, thickness, color, border)
	return New("UIStroke", {
		Color = color or DARK, Thickness = thickness or 2, LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = border and Enum.ApplyStrokeMode.Border or Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

local function Gradient(parent, top, bottom)
	return New("UIGradient", {Color = ColorSequence.new(top, bottom), Rotation = 90}, parent)
end

local function UiBox(parent, props)
	local frame = New("Frame", {BorderSizePixel = 0, BackgroundColor3 = WHITE})
	for k, v in pairs(props) do frame[k] = v end
	frame.Parent = parent
	return frame
end

--.. a FredokaOne label: white text, dark stroke (stroke = 0 for none)
local function Text(parent, props, stroke)
	local label = New("TextLabel", {BackgroundTransparency = 1, Font = GUI_FONT, TextColor3 = WHITE, TextSize = 24, Text = ""})
	for k, v in pairs(props) do label[k] = v end
	if (stroke or 2) > 0 then Stroke(label, stroke or 2) end
	label.Parent = parent
	return label
end

--.. a HUD-style button: gradient shell, dark edge, inner highlight rim, white stroked text, press pop
local function Button(parent, look, size, position, text, textSize)
	local shell = UiBox(parent, {Size = size, Position = position, AnchorPoint = Vector2.new(0.5, 0.5)})
	Corner(shell, 14)
	Gradient(shell, look.Top, look.Bottom)
	Stroke(shell, 3, DARK, true)
	local rim = UiBox(shell, {Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1})
	Corner(rim, 11)
	New("UIStroke", {Color = look.Highlight, Thickness = 2, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, rim)
	local button = New("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text or "", Font = GUI_FONT,
		TextSize = textSize or 28, TextColor3 = WHITE, AutoButtonColor = false,
	}, shell)
	Stroke(button, 2.5)
	local pop = New("UIScale", {}, shell)
	button.MouseEnter:Connect(function() pop.Scale = 1.04 end)
	button.MouseLeave:Connect(function() pop.Scale = 1 end)
	button.MouseButton1Down:Connect(function() pop.Scale = 0.93 end)
	button.MouseButton1Up:Connect(function() pop.Scale = 1 end)
	return button, shell, pop
end

--.. the layout of the GUI's scene (one copy, no pixel HUD)
local function GuiLayout()
	local L = {U = GUI_U, W = VIEW_ART.X * GUI_U, H = VIEW_ART.Y * GUI_U, AW = VIEW_ART.X}
	L.groundA = VIEW_ART.Y - GROUND_H
	L.heroA = VIEW_ART.X * GUI_HERO_AT
	L.centreX0, L.centreW = 0, L.W
	return L
end

--..Game: GUI..--
local function BuildGui(g)
	local ui = {}
	local gui = New("ScreenGui", {Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
	ui.Gui = gui
	UiBox(gui, {Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.5, Active = true})

	--..Desk panel (dark like the desk, red trim; the title plate's edge runs through the rainbow like the RGB)..--
	local panel = UiBox(gui, {Name = "Desk", Size = UDim2.fromOffset(PANEL.X, PANEL.Y), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, PANEL_DROP), Active = true})
	ui.Panel = panel
	ui.Scale = New("UIScale", {}, panel)
	Corner(panel, 28)
	Gradient(panel, DESK_TOP, DESK_BOTTOM)
	Stroke(panel, 6, DESK_TRIM, true)
	local plate = UiBox(panel, {Size = UDim2.fromOffset(470, 52), Position = UDim2.new(0.5, 0, 0, 12), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(16, 18, 26)})
	Corner(plate, 16)
	ui.PlateStroke = Stroke(plate, 3, GREEN.Top, true)
	Text(plate, {Size = UDim2.fromScale(1, 1), Text = CUKE .. " CUKE RUN " .. CUKE, TextSize = 34}, 2.5)
	ui.Close = Button(panel, RED, UDim2.fromOffset(52, 52), UDim2.new(1, -44, 0, 38), "X", 32)

	--..The game view: the pixel world (the monitor's scene) + a HUD strip; the whole view is the tap-to-jump area..--
	local L = g.L
	local view = UiBox(panel, {Name = "View", Size = UDim2.fromOffset(L.W, L.H), Position = UDim2.fromOffset(VIEW_X, VIEW_Y), BackgroundColor3 = SKY_DAY[3], ClipsDescendants = true, Active = true})
	Stroke(view, 5, DARK, true)
	ui.View = view
	g.scenes = {NewScene(view, L, 0, false)}
	local hud = UiBox(view, {Size = UDim2.fromOffset(L.W, HUD_H), BackgroundColor3 = BLACK, BackgroundTransparency = 0.55, ZIndex = 20})
	ui.Score = Text(hud, {Text = "SCORE 000000", TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(320, HUD_H), Position = UDim2.fromOffset(16, 0)}, 2.5)
	local coin = UiBox(hud, {Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0.5, -40, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.Coin})
	Round(coin)
	Stroke(coin, 2, Color3.fromRGB(150, 96, 10), true)
	ui.CoinScale = New("UIScale", {}, coin)
	ui.Coins = Text(hud, {Text = "x 0", TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(120, HUD_H), Position = UDim2.new(0.5, -20, 0, 0)}, 2.5)
	ui.Hi = Text(hud, {Text = "HI 000000", TextSize = 26, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(300, HUD_H), Position = UDim2.new(1, -16, 0, 0), AnchorPoint = Vector2.new(1, 0)}, 2.5)
	ui.Flash = UiBox(view, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 40, 40), BackgroundTransparency = 1, ZIndex = 24})
	ui.Count = Text(view, {Text = "", TextSize = 96, Size = UDim2.fromOffset(L.W, 120), Position = UDim2.fromOffset(L.W / 2, L.H * 0.4), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 25}, 4)
	ui.CountScale = New("UIScale", {}, ui.Count)
	--.. the READY hint sits right of the hero, clear of it
	local heroRight = (L.heroA + 5) * L.U
	local hint = UiBox(view, {Size = UDim2.fromOffset(L.W - heroRight - 24, 78), Position = UDim2.fromOffset(heroRight + 8, L.H * 0.64), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = BLACK, BackgroundTransparency = 0.35, ZIndex = 25})
	Corner(hint, 16)
	Text(hint, {Text = "Jump the crates, spikes and slimes - grab the coins!", TextSize = 22, Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 6)}, 2)
	Text(hint, {Text = "DUCK under the flying drones", TextSize = 21, TextColor3 = Color3.fromRGB(205, 180, 255), Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 42)}, 2)
	ui.Hint = hint
	--.. the tap-to-jump area: a clear button over the whole view (buttons always get their presses)
	ui.Tap = New("TextButton", {Name = "TapArea", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 40}, view)

	--..Controls row: big DUCK / JUMP buttons (touch, mouse) and the key help between them..--
	local rowY = CONTROLS_Y + 55
	local duck, _, duckPop = Button(panel, GREEN, UDim2.fromOffset(220, 110), UDim2.fromOffset(VIEW_X + 110, rowY), "DUCK", 38)
	local jump, _, jumpPop = Button(panel, GREEN, UDim2.fromOffset(260, 110), UDim2.fromOffset(VIEW_X + L.W - 130, rowY), "JUMP", 44)
	ui.Duck, ui.DuckPop, ui.Jump, ui.JumpPop = duck, duckPop, jump, jumpPop
	local help
	if IsTouch() then
		help = "TAP the game or JUMP to jump\nhold for a higher jump\nhold DUCK under the drones"
	else
		help = "JUMP: SPACE / W / UP / CLICK\n(hold for a higher jump)\nDUCK: S / DOWN     EXIT: BACKSPACE"
	end
	Text(panel, {Text = help, TextSize = 19, TextColor3 = Color3.fromRGB(205, 214, 235), Size = UDim2.fromOffset(350, 104), Position = UDim2.fromOffset(PANEL.X / 2, rowY), AnchorPoint = Vector2.new(0.5, 0.5), TextWrapped = true}, 2)

	--..Game over card (over the view)..--
	local card = UiBox(panel, {Size = UDim2.fromOffset(420, 340), Position = UDim2.fromOffset(VIEW_X + L.W / 2, VIEW_Y + L.H / 2), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(26, 30, 50), Visible = false, ZIndex = 30})
	Corner(card, 22)
	Stroke(card, 4, DESK_TRIM, true)
	ui.Card = card
	ui.CardScale = New("UIScale", {}, card)
	Text(card, {Text = "GAME OVER", TextSize = 50, TextColor3 = Color3.fromRGB(255, 96, 96), Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 12)}, 3)
	Text(card, {Text = "SCORE", TextSize = 22, TextColor3 = Color3.fromRGB(200, 212, 235), Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 68)}, 2)
	ui.CardScore = Text(card, {Text = "0", TextSize = 60, Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 90)}, 3)
	ui.CardBest = Text(card, {Text = "BEST 0", TextSize = 26, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 154)}, 2)
	ui.CardTag = Text(card, {Text = "", TextSize = 24, TextColor3 = Color3.fromRGB(255, 226, 90), Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 188)}, 2.5)
	ui.CardHi = Text(card, {Text = "", TextSize = 21, TextColor3 = NEON_CYAN, Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 220)}, 2)
	ui.Again = Button(card, GREEN, UDim2.fromOffset(214, 66), UDim2.new(0.5, -72, 0, 292), "PLAY AGAIN", 28)
	ui.Exit = Button(card, RED, UDim2.fromOffset(120, 66), UDim2.new(0.5, 112, 0, 292), "EXIT", 28)
	return ui
end

--..Game: sounds (2D: parented to the ScreenGui)..--
local function MakeSounds(g)
	local list = {
		Jump = "ArcadeBlip", Go = "ArcadeBlip", Duck = "Whoosh", Coin = "Coin", Crash = "Thump",
		Lose = "ArcadeLose", Win = "ArcadeWin", Click = "Click",
	}
	g.sounds = {}
	for name, sfx in pairs(list) do
		local id = type(FunAssets.Sfx) == "table" and FunAssets.Sfx[sfx] or nil
		local ok, sound = false, nil
		if id then ok, sound = pcall(Kit.MakeSound, id, {Name = "Sfx" .. name, Volume = 0.5}) end
		if ok and sound then
			sound.Parent = g.ui.Gui
			g.sounds[name] = sound
		end
	end
end

local function PlayUi(g, name, speed, volume)
	local sound = g.sounds[name]
	if not sound then return end
	pcall(function()
		sound.PlaybackSpeed = speed or 1
		sound.Volume = volume or 0.5
		sound.TimePosition = 0
		sound:Play()
	end)
end

--..Game: inputs -> the run's event list (+ the outbox to the server)..--
local function Emit(g, kind)
	local run = g.run
	if g.state ~= "play" or not run or run.Sim.Dead then return end
	--.. stamped with the tick running NOW on the server clock, never before the next one / the last event: after a
	--.. hitch the sim has not caught up yet, and an input stamped with its stale tick would reach every replay after
	--.. it had passed that tick
	local tick = math.max(run.Sim.N + 1, math.floor((Kit.Now() - g.since - READY) * TICK_RATE), run.Ticks[#run.Ticks] or 0)
	table.insert(run.Ticks, tick)
	table.insert(run.Kinds, kind)
	table.insert(g.outbox, {t = tick / TICK_RATE, k = EVENT_NAMES[kind]})
	if kind == EV_DUCK then PlayUi(g, "Duck", 1.7, 0.18) end
end

--.. a jump / duck holder (a key, "mouse", a touch) goes down / up: press / release events on the first / last one
local function Hold(g, which, key, down)
	local set = which == "jump" and g.jumpHolds or g.duckHolds
	local was = next(set) ~= nil
	set[key] = down or nil
	local now = next(set) ~= nil
	if now == was then return end
	if which == "jump" then
		Emit(g, now and EV_JUMP or EV_JUMP_UP)
		g.ui.JumpPop.Scale = now and 0.93 or 1
	else
		Emit(g, now and EV_DUCK or EV_DUCK_UP)
		g.ui.DuckPop.Scale = now and 0.93 or 1
	end
end

--.. send what is waiting (at most every SEND_GAP s unless forced)
local function Flush(g, force)
	if #g.outbox == 0 or not g.run then return end
	local now = os.clock()
	if not force and now - g.sentAt < SEND_GAP then return end
	g.sentAt = now
	local batch = g.outbox
	if #batch > SEND_MAX then
		g.outbox = table.move(batch, SEND_MAX + 1, #batch, 1, {})
		batch = table.move(batch, 1, SEND_MAX, 1, {})
	else
		g.outbox = {}
	end
	if #batch == 1 then
		g.Ctx:Send("Input", {s = g.run.Seed, t = batch[1].t, k = batch[1].k})
	else
		g.Ctx:Send("Input", {s = g.run.Seed, e = batch})
	end
end

local function SendOver(g)
	local run = g.run
	if not run then return end
	local seconds = (run.Sim.Dead and run.Sim.DeadTick or run.Sim.N) / TICK_RATE
	g.Ctx:Send("Over", {s = run.Seed, score = Score(run.Sim), seconds = seconds})
	g.overAt = os.clock()
	g.overTries += 1
end

--..Game: runs..--
local function StartLocalRun(g, seed, since)
	local run = NewRun(seed)
	run.Owned, run.Complete = true, true
	g.run = run
	g.since = since
	g.clock = Kit.Now() - since - READY -- the server clock (GameFrame); a GUI that opens late starts mid-run
	g.state = "ready"
	g.jumpHolds, g.duckHolds, g.outbox = {}, {}, {}
	g.overTries, g.overAt, g.againAt, g.deadAt = 0, 0, nil, nil
	g.cardShown, g.overReady, g.cardT, g.recordShown = false, false, nil, false
	g.countText, g.countAt = nil, 0
	g.ui.Card.Visible = false
	g.ui.Hint.Visible = true
	g.ui.Count.Visible = true
	g.ui.Count.Text = ""
	g.ui.Again.Text = "PLAY AGAIN"
	g.ui.JumpPop.Scale, g.ui.DuckPop.Scale = 1, 1
end

local function OnDeath(g)
	local run = g.run
	g.state = "dead"
	g.deadAt = os.clock()
	g.jumpHolds, g.duckHolds = {}, {}
	g.ui.JumpPop.Scale, g.ui.DuckPop.Scale = 1, 1
	Flush(g, true)
	g.score = Score(run.Sim)
	g.newBest = g.score > PersonalBest
	if g.newBest then PersonalBest = g.score end
	SendOver(g)
	g.shake, g.flash = 0.35, 1
	PlayUi(g, "Crash", 1.15, 0.7)
end

local function Again(g)
	if g.state ~= "dead" or not g.overReady then return end
	if g.againAt and os.clock() - g.againAt < AGAIN_RESEND then return end
	PlayUi(g, "Click")
	g.againAt = os.clock()
	g.ui.Again.Text = "..."
	g.Ctx:Send("Again", {s = g.run and g.run.Seed or 0})
end

local function CloseGame(g, standUp)
	if g.closed then return end
	g.closed = true
	--.. leaving mid-run: the run so far is the score (the server still checks it)
	if g.state == "play" and g.run and not g.run.Sim.Dead then
		Flush(g, true)
		SendOver(g)
	end
	for _, c in ipairs(g.conns) do c:Disconnect() end
	pcall(function() ContextActionService:UnbindAction(ACTION) end)
	if g.controls then pcall(function() g.controls:Enable() end) end
	if g.ui and g.ui.Gui then g.ui.Gui:Destroy() end
	local w = g.W
	--.. the monitor goes on showing this run: hand it over with its full event list (relays of our own run were skipped)
	if g.run then
		g.run.Owned = false
		w.Run = g.run
	end
	if w.Game == g then w.Game = nil end
	w.Declined = true -- no reopening until they sit down again
	if Active == g then Active = nil end
	if standUp and g.Ctx:Alive() then
		g.Ctx:Send("Leave")
		local humanoid = g.Ctx:LocalCharacter()
		if humanoid then
			pcall(function()
				humanoid.Sit = false
				humanoid.Jump = true
			end)
		end
	end
end

--..Game: frame..--
local function UpdateOverlay(g, dt, best, final, ended, since, seed)
	local ui = g.ui
	local run = g.run
	--.. READY? / GO!
	local text = ""
	if g.state == "ready" then
		text = (g.clock + READY) < READY * 0.62 and "READY?" or "GO!"
	elseif g.state == "play" and g.clock < 0.35 then
		text = "GO!"
	end
	if text ~= g.countText then
		g.countText, g.countAt = text, os.clock()
		ui.Count.Text = text
		if text == "READY?" then PlayUi(g, "Click", 1.2) elseif text == "GO!" then PlayUi(g, "Go", 1.4) end
	end
	local f = math.clamp((os.clock() - g.countAt) / 0.4, 0, 1)
	ui.CountScale.Scale = 1 + 0.6 * (1 - f) ^ 3
	ui.Count.TextTransparency = (g.state == "play" and g.clock > 0.15) and math.clamp((g.clock - 0.15) / 0.2, 0, 1) or 0
	ui.Hint.Visible = g.state == "ready"

	--.. HUD
	local s = run and run.Sim
	SetText(ui.Score, "SCORE " .. Pad(s and Score(s) or 0))
	SetText(ui.Coins, "x " .. tostring(s and s.Coins or 0))
	SetText(ui.Hi, "HI " .. Pad(math.max(best, PersonalBest)))
	ui.CoinScale.Scale = math.max(1, ui.CoinScale.Scale - dt * 3)
	ui.PlateStroke.Color = Color3.fromHSV((os.clock() * RGB_RATE_PLAY) % 1, RGB_SAT, 1)

	--.. crash: shake + red flash
	if (g.shake or 0) > 0 then
		g.shake = math.max(0, g.shake - dt)
		local amp = 9 * g.shake / 0.35
		ui.Panel.Position = UDim2.new(0.5, (math.random() * 2 - 1) * amp, 0.5, PANEL_DROP + (math.random() * 2 - 1) * amp)
		if g.shake <= 0 then ui.Panel.Position = UDim2.new(0.5, 0, 0.5, PANEL_DROP) end
	end
	if (g.flash or 0) > 0 then
		g.flash = math.max(0, g.flash - dt * 3)
		ui.Flash.BackgroundTransparency = 1 - 0.45 * g.flash
	end

	--.. GAME OVER card
	if g.state == "dead" then
		local t = os.clock() - g.deadAt
		if not g.cardShown and t >= CARD_DELAY then
			g.cardShown, g.cardT = true, 0
			ui.CardScore.Text = tostring(g.score)
			ui.CardBest.Text = "BEST " .. tostring(PersonalBest)
			ui.CardScale.Scale = 0.6
			ui.Card.Visible = true
			PlayUi(g, g.newBest and "Win" or "Lose", 1, g.newBest and 0.5 or 0.4)
		end
		if g.cardShown then
			if not g.overReady and t >= CARD_DELAY + CARD_READY then g.overReady = true end
			--.. the server took the score as this desk's new best
			local record = g.score > 0 and seed == run.Seed and ended > since and final == g.score and best == g.score
			if record and not g.recordShown then
				g.recordShown = true
				if not g.newBest then PlayUi(g, "Win") end
			end
			if g.recordShown then
				SetText(ui.CardTag, PARTY .. " NEW DESK RECORD! " .. PARTY)
			else
				SetText(ui.CardTag, g.newBest and "NEW BEST!" or "")
			end
			SetText(ui.CardHi, "DESK HI  " .. tostring(best))
			if g.cardT and g.cardT < 1 then
				g.cardT = math.min(1, g.cardT + dt / 0.28)
				local u = g.cardT - 1
				ui.CardScale.Scale = 0.6 + 0.4 * (1 + 2.7 * u * u * u + 1.7 * u * u) -- ease out back
			end
		end
	end
end

local function GameFrame(g, dt)
	local ctx = g.Ctx
	if not ctx:Alive() then CloseGame(g, false) return end
	local player, since, ended, final, best, seed = ReadState(ctx)

	--.. still in this desk's chair? (a moment's grace: the seat weld and the state replicate separately)
	local humanoid = ctx:LocalCharacter()
	local seated = humanoid ~= nil and humanoid.SeatPart ~= nil and humanoid.SeatPart.Name == SEAT_NAME
		and player == LocalPlayer.UserId and ctx:Near(CLOSE_RANGE)
	if seated then
		g.lostAt = nil
	elseif not g.lostAt then
		g.lostAt = os.clock()
	elseif os.clock() - g.lostAt > SEAT_GRACE then
		CloseGame(g, false)
		return
	end

	--.. a new run from the server (sitting down, PLAY AGAIN)
	local live = seed ~= 0 and since > ended
	if live and (not g.run or g.run.Seed ~= seed) then StartLocalRun(g, seed, since) end

	--.. the run: fixed steps up to the SERVER clock, the one every replay runs on. A hitch skips time (the ticks it
	--.. missed run now, at most SIM_BUDGET a frame) instead of pausing: a paused run would stay behind the replays
	--.. for good and every later input would reach them after they had passed it
	local run = g.run
	local now = Kit.Now()
	if run then
		if g.state == "ready" or g.state == "play" then
			g.clock = now - g.since - READY
			if g.clock >= 0 then
				g.state = "play"
				Advance(run, math.floor(g.clock * TICK_RATE), SIM_BUDGET, g.hooks)
				if run.Sim.Dead then OnDeath(g) end
			end
		end
		ViewRun(g.view, g.L, run)
	else
		ViewAttract(g.view, g.L, now)
	end
	local night = workspace:GetAttribute("IsNight") == true
	if night ~= g.night then
		g.night = night
		for _, S in ipairs(g.scenes) do PaintScene(S, night) end
	end
	DrawWorld(g.scenes, g.L, g.view, now, nil)
	UpdateOverlay(g, dt, best, final, ended, since, seed)
	Flush(g, false)

	--.. the server has not ended the run yet: say it again (a dropped "Over" would leave it live)
	if g.state == "dead" and run and seed == run.Seed and live and g.overTries < 4 and os.clock() - g.overAt > OVER_RESEND then
		SendOver(g)
	end
	if g.againAt and os.clock() - g.againAt > AGAIN_RESEND and g.state == "dead" then g.ui.Again.Text = "PLAY AGAIN" end
end

--..Game: input..--
local function BindInput(g)
	local ui = g.ui
	ContextActionService:BindActionAtPriority(ACTION, function(_, state, input)
		local key = input.KeyCode
		if key == K.Thumbstick1 then
			Hold(g, "duck", "stick", input.Position.Y < -0.6)
		elseif state == Enum.UserInputState.Begin then
			if EXIT_KEYS[key] then
				CloseGame(g, true)
			elseif g.state == "dead" then
				if AGAIN_KEYS[key] then
					Again(g)
				elseif CARD_EXIT_KEYS[key] and g.overReady then
					CloseGame(g, true)
				end
			elseif JUMP_KEYS[key] then
				Hold(g, "jump", key, true)
			elseif DUCK_KEYS[key] then
				Hold(g, "duck", key, true)
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			if JUMP_KEYS[key] then Hold(g, "jump", key, false) end
			if DUCK_KEYS[key] then Hold(g, "duck", key, false) end
		end
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, table.unpack(SUNK_KEYS))

	--.. mouse / touch: the game view and the JUMP button jump, the DUCK button ducks (held); one "mouse" holder
	local function Holder(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then return "mouse" end
		if input.UserInputType == Enum.UserInputType.Touch then return input end
		return nil
	end
	local function OnPress(which)
		return function(input)
			local key = Holder(input)
			if key and g.state ~= "dead" then Hold(g, which, key, true) end
		end
	end
	table.insert(g.conns, ui.Tap.InputBegan:Connect(OnPress("jump")))
	table.insert(g.conns, ui.Jump.InputBegan:Connect(OnPress("jump")))
	table.insert(g.conns, ui.Duck.InputBegan:Connect(OnPress("duck")))
	table.insert(g.conns, UserInputService.InputEnded:Connect(function(input)
		local key = Holder(input)
		if not key then return end
		Hold(g, "jump", key, false)
		Hold(g, "duck", key, false)
	end))
	table.insert(g.conns, ui.Close.Activated:Connect(function() CloseGame(g, true) end))
	table.insert(g.conns, ui.Exit.Activated:Connect(function() CloseGame(g, true) end))
	table.insert(g.conns, ui.Again.Activated:Connect(function() Again(g) end))
end

local function Fit(g)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local s = math.min((viewport.X - 24) / PANEL.X, (viewport.Y - 24 - PANEL_DROP * 2) / PANEL.Y)
	g.ui.Scale.Scale = math.clamp(s, 0.3, 1.2)
end

--.. the PlayerModule's controls (off while playing: no walking, and the touch jump button is hidden)
local function Controls()
	local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then return nil end
	local ok, controls = pcall(function() return require(module):GetControls() end)
	return ok and controls or nil
end

local function OpenGame(w)
	local g = {
		W = w, Ctx = w.Ctx, conns = {}, L = GuiLayout(), view = NewView(), run = nil, clock = 0, state = "wait",
		jumpHolds = {}, duckHolds = {}, outbox = {}, sentAt = 0, overTries = 0, overAt = 0, score = 0,
		shake = 0, flash = 0, countText = nil, countAt = 0,
	}
	g.ui = BuildGui(g)
	MakeSounds(g)
	g.hooks = {
		Jump = function() PlayUi(g, "Jump", 1.9, 0.3) end,
		Coin = function()
			PlayUi(g, "Coin", 1.1 + math.random() * 0.12, 0.45)
			g.ui.CoinScale.Scale = 1.6
		end,
		Press = function() if w.Clack then w.Clack() end end,
	}
	Fit(g)
	local camera = workspace.CurrentCamera
	if camera then table.insert(g.conns, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() Fit(g) end)) end
	BindInput(g)
	g.controls = Controls()
	if g.controls then pcall(function() g.controls:Disable() end) end
	local humanoid = w.Ctx:LocalCharacter()
	if humanoid then table.insert(g.conns, humanoid.Died:Connect(function() CloseGame(g, false) end)) end
	g.ui.Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	w.Game = g
	Active = g
	table.insert(g.conns, RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(GameFrame, g, dt)
		if not ok then
			warn("[GamingDesk] game frame: " .. tostring(err))
			CloseGame(g, true)
		end
	end))
	return g
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local scale = ctx.Scale
	local folder = LocalFolder()
	local origin = Kit.Origin(model)
	local w = {Model = model, Ctx = ctx, Game = nil, Run = nil, Fresh = {}, SyncAt = -math.huge, Declined = false}
	ctx.Desk = w

	--..Screens..--
	local arts = Kit.Parts(model, ART_PREFIX)
	local panels = {}
	for _, name in ipairs(PANEL_NAMES) do
		local p = Kit.Part(model, name)
		if p then
			local cf, size, right = PanelGeometry(model, p, arts, scale)
			table.insert(panels, {Name = name, Part = p, CFrame = cf, Size = size, Right = right})
		end
	end
	local scenes = {}
	local screenLight
	if #panels > 0 then
		--.. slices run from the viewer's left (+X authored = the panels' "right") to their right
		local ref = panels[1].Right
		for _, pn in ipairs(panels) do
			if pn.Name == CENTRE_PANEL then ref = pn.Right end
		end
		local mid = origin.Position
		table.sort(panels, function(a, b) return (a.CFrame.Position - mid):Dot(ref) > (b.CFrame.Position - mid):Dot(ref) end)
		local L = {}
		local heightPx = math.huge
		for _, pn in ipairs(panels) do heightPx = math.min(heightPx, math.floor(pn.Size.Y * PPS)) end
		L.H = math.max(ART_H * 2, heightPx)
		L.U = math.max(2, math.floor(L.H / ART_H))
		local x = 0
		local centreIndex = 1
		for i, pn in ipairs(panels) do
			pn.OffsetPx = x
			pn.WidthPx = math.floor(pn.Size.X * PPS + 0.5)
			x += pn.WidthPx
			if pn.Name == CENTRE_PANEL then centreIndex = i end
		end
		if not Kit.Part(model, CENTRE_PANEL) then --.. no centre panel: the widest one hosts the HUD
			for i, pn in ipairs(panels) do
				if pn.WidthPx > panels[centreIndex].WidthPx then centreIndex = i end
			end
		end
		L.W = x
		L.AW = L.W / L.U
		L.groundA = L.H / L.U - GROUND_H
		L.centreX0 = panels[centreIndex].OffsetPx
		L.centreW = panels[centreIndex].WidthPx
		L.heroA = (L.centreX0 + HERO_AT * L.centreW) / L.U
		for i, pn in ipairs(panels) do
			local part = ctx:Part({Name = "GamingDesk" .. pn.Name, Size = pn.Size, CFrame = pn.CFrame, Transparency = 1, Parent = folder})
			local gui = New("SurfaceGui", {
				Name = "GameScreen", Face = Enum.NormalId.Front, LightInfluence = 0, Brightness = BRIGHTNESS,
				SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = PPS,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Adornee = part,
			})
			Try(gui, "ClipsDescendants", true)
			Try(gui, "MaxDistance", GUI_MAX_DISTANCE)
			gui.Parent = part
			local S = NewScene(gui, L, pn.OffsetPx, i == centreIndex)
			S.hud = i == centreIndex
			table.insert(scenes, S)
			if i == centreIndex then
				screenLight = New("SurfaceLight", {
					Face = Enum.NormalId.Front, Range = LIGHT_RANGE * scale, Angle = LIGHT_ANGLE, Brightness = LIGHT_IDLE,
					Color = LIGHT_COLOR, Shadows = false,
				}, part)
				pn.Host = part
			end
		end
		scenes.L = L
		scenes.host = panels[centreIndex].Host
	end
	local L = scenes.L
	local view = NewView()

	--..RGB parts + the glow under the desk..--
	local rgb = {}
	for _, p in ipairs(Kit.Parts(model, RGB_PREFIX)) do
		local ax = origin:PointToObjectSpace(p.Position).X / math.max(0.01, scale)
		table.insert(rgb, {Part = p, Home = p.Color, Phase = (0.5 - ax / DESK_WIDTH) * RGB_WAVE})
	end
	local glowPos = Kit.Pivot(model, "RGBGlow") or Kit.ToWorld(model, GLOW_FALLBACK)
	local glowPart = ctx:Part({Name = "GamingDeskGlow", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(glowPos), Transparency = 1, Parent = folder})
	local glow = New("PointLight", {Range = GLOW_RANGE * scale, Brightness = GLOW_BRIGHTNESS, Shadows = false, Color = Color3.new(1, 0, 1)}, glowPart)

	--..Chair rig (relative to the sitting pose; the parts ship turned State_ChairIdleYaw)..--
	local idleYaw = tonumber(model:GetAttribute("State_ChairIdleYaw")) or DEFAULT_IDLE_YAW
	local sitYaw = tonumber(model:GetAttribute("State_ChairSitYaw")) or DEFAULT_SIT_YAW
	local swivelParts = Kit.Parts(model, SWIVEL_PREFIX)
	local swivelPos = Kit.Pivot(model, "ChairSwivel") or Kit.ToWorld(model, SWIVEL_FALLBACK)
	local pivot0 = CFrame.new(swivelPos) * origin.Rotation
	local pivotRel = hitbox.CFrame:ToObjectSpace(pivot0)
	local function Yaw(deg) return CFrame.Angles(0, math.rad(deg), 0) end
	local rig = Kit.Rig(swivelParts, pivot0 * Yaw(idleYaw))
	local home = {}
	for _, p in ipairs(swivelParts) do home[p] = hitbox.CFrame:ToObjectSpace(p.CFrame) end

	--..Sounds (3D, at the desk)..--
	local keysPos = Kit.Pivot(model, "Keys") or Kit.ToWorld(model, Vector3.new(0, 3.3, 0.7))
	local keysPart = ctx:Part({Name = "GamingDeskKeys", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(keysPos), Transparency = 1, Parent = folder})
	local function Sfx(parent, name, volume)
		local id = type(FunAssets.Sfx) == "table" and FunAssets.Sfx[name] or nil
		if not id or not parent then return nil end
		return ctx:Sound(parent, id, {Volume = volume, Looped = false, RollOffMaxDistance = 60})
	end
	local sfxHost = scenes.host or keysPart
	local sfxKeys = Sfx(keysPart, "Click", KEYS_VOLUME)
	local sfxCoin = Sfx(sfxHost, "Coin", GAME_VOLUME)
	local sfxGo = Sfx(sfxHost, "ArcadeBlip", GAME_VOLUME)
	local sfxWin = Sfx(sfxHost, "ArcadeWin", GAME_VOLUME)
	local sfxLose = Sfx(sfxHost, "ArcadeLose", GAME_VOLUME * 0.8)
	local sfxCrash = Sfx(sfxHost, "Thump", GAME_VOLUME * 1.4)
	local rng = Random.new()
	local function Play(sound, speed, volume)
		if not sound then return end
		pcall(function()
			if speed then sound.PlaybackSpeed = speed end
			if volume then sound.Volume = volume end
			sound.TimePosition = 0
			sound:Play()
		end)
	end
	local function Near() return ctx:CameraDistance() <= KEYS_RANGE end
	--.. a keyboard clack for every press of the gamer (their GUI calls it too)
	w.Clack = function()
		if Near() then Play(sfxKeys, rng:NextNumber(1.3, 1.9), KEYS_VOLUME * rng:NextNumber(0.7, 1.1)) end
	end
	local worldHooks = {
		Press = w.Clack,
		Coin = function() if Near() then Play(sfxCoin, rng:NextNumber(1.05, 1.2)) end end,
		Crash = function() if Near() then Play(sfxCrash, 1.15) end end,
	}

	--..Runs: the gamer's own (the GUI) or a replay of the relayed inputs..--
	--.. seeds that started while this client watched: their event lists are complete without a "Sync"
	local firstSeed = true
	ctx:OnState("Seed", function(v)
		local seed = tonumber(v) or 0
		if firstSeed then
			firstSeed = false
			return
		end
		if seed ~= 0 then w.Fresh[seed] = true end
	end)
	local function GetRun(seed)
		if not seed or seed == 0 then return nil end
		local g = w.Game
		if g and g.run and g.run.Seed == seed then return g.run end
		if not w.Run or w.Run.Seed ~= seed then
			w.Run = NewRun(seed)
			w.Run.Complete = w.Fresh[seed] == true
		end
		return w.Run
	end
	w.GetRun = GetRun
	local function NeedSync(run)
		if run.Owned or run.Complete or os.clock() - w.SyncAt < SYNC_RETRY then return end
		w.SyncAt = os.clock()
		ctx:Send("Sync", {s = run.Seed})
	end

	--..Night..--
	local night = nil
	local function SyncNight()
		local n = workspace:GetAttribute("IsNight") == true
		if n == night then return end
		night = n
		for _, S in ipairs(scenes) do PaintScene(S, n) end
	end
	SyncNight()
	ctx:Connect(workspace:GetAttributeChangedSignal("IsNight"), SyncNight)

	--..Names..--
	local nameCache = {}
	local function NameOf(id)
		if id == -1 then return "CPU" end
		if nameCache[id] then return nameCache[id] end
		local p = Players:GetPlayerByUserId(id)
		local n = p and p.DisplayName or "PLAYER"
		n = string.upper(n):sub(1, 12)
		nameCache[id] = n
		return n
	end

	--..The monitor: the attract loop, or the run (the gamer's own simulation, or the replay SPECTATOR_DELAY behind)..--
	local hud = {Score = "", Name = "", Coins = "", Big = "", Small = "", BigY = BIG_Y.other, SmallY = SMALL_Y.other}
	local lastMode = nil
	local function DrawScreens(now, woke)
		if not L then return "idle" end
		local player, since, ended, final, best, seed = ReadState(ctx)
		local live = seed ~= 0 and since > ended
		local mode
		if live then
			mode = now - since < READY and "ready" or "run"
		elseif seed ~= 0 and ended > 0 and (player > 0 or now - ended < OVER_TIME) then
			mode = "over"
		else
			mode = "idle"
		end
		local nearSound = not woke and Near()
		local mine = w.Game ~= nil and player == LocalPlayer.UserId -- the gamer hears their GUI instead
		local run = mode ~= "idle" and GetRun(seed) or nil
		if not run then mode = "idle" end
		local s = run and run.Sim
		if run then
			if not run.Owned then
				NeedSync(run)
				local target
				if mode == "over" then
					--.. the run's own last tick (the gamer's report); a replay that ran past it (inputs stopped, the end
					--.. not heard yet) goes back to it - no crash / coins after an EXIT that never happened
					local endTick = tonumber(ctx:State("EndTick")) or 0
					target = endTick > 0 and math.floor(endTick) or math.floor((ended - since - READY) * TICK_RATE)
					if s.N > target then run.Dirty = math.min(run.Dirty or math.huge, target + 1) end
				else
					target = math.floor((now - since - READY - SPECTATOR_DELAY) * TICK_RATE)
				end
				--.. (a replay without its full list waits for the "Events" answer instead of crashing at the first obstacle)
				if target > 0 and run.Complete then Advance(run, target, SIM_BUDGET, (nearSound and not mine) and worldHooks or nil) end
			end
			ViewRun(view, L, run)
		else
			ViewAttract(view, L, now)
		end

		--.. texts
		local blink = (now % 1) < 0.6
		if mode == "idle" then
			hud.Score = best > 0 and ("HI " .. Pad(best)) or ""
			hud.Name, hud.Coins, hud.Big = "", "", "CUKE RUN"
			hud.Small = blink and "SIT TO PLAY" or ""
		elseif mode == "ready" then
			hud.Score, hud.Name, hud.Coins = "SCORE " .. Pad(0), "P1 " .. NameOf(player), "COINS 0"
			hud.Big = (now - since) < READY * 0.62 and "READY?" or "GO!"
			hud.Small = ""
		elseif mode == "run" and not s.Dead then
			hud.Score, hud.Name, hud.Coins = "SCORE " .. Pad(Score(s)), "P1 " .. NameOf(player), "COINS " .. s.Coins
			hud.Big, hud.Small = "", ""
		else --.. the crash (seen in the replay) / GAME OVER
			local score = mode == "over" and final or Score(s)
			hud.Score = "HI " .. Pad(best)
			hud.Coins = "COINS " .. s.Coins
			hud.Big = "GAME OVER"
			hud.Small = (mode == "over" and player > 0 and (now % 2) >= 1.2) and "PLAY AGAIN?" or ("SCORE " .. Pad(score))
			hud.Name = (mode == "over" and final > 0 and final >= best and blink) and "NEW HI-SCORE!" or ""
		end
		hud.BigY = mode == "idle" and BIG_Y.idle or BIG_Y.other
		hud.SmallY = mode == "idle" and SMALL_Y.idle or SMALL_Y.other
		DrawWorld(scenes, L, view, now, hud)

		--.. stings (the gamer's GUI plays its own)
		if nearSound and not mine then
			if lastMode == "ready" and mode == "run" then Play(sfxGo, 1.4) end
			if lastMode == "run" and mode == "over" then
				if final > 0 and final >= best then Play(sfxWin) else Play(sfxLose) end
			end
		end
		lastMode = mode
		if screenLight then screenLight.Brightness = (mode == "run" or mode == "ready") and LIGHT_PLAY or LIGHT_IDLE end
		return mode
	end

	--..RGB colours..--
	local rgbPhase = (Kit.Now() * RGB_RATE_IDLE) % 1
	local function DrawRGB(dt, playing)
		rgbPhase = (rgbPhase + dt * (playing and RGB_RATE_PLAY or RGB_RATE_IDLE)) % 1
		for _, r in ipairs(rgb) do
			if r.Part.Parent then r.Part.Color = Color3.fromHSV((rgbPhase + r.Phase) % 1, RGB_SAT, 1) end
		end
		glow.Color = Color3.fromHSV(rgbPhase, RGB_SAT, 1)
	end

	--..Every frame..--
	local yaw, yawVel = idleYaw, 0
	local target = idleYaw
	local spin = nil         -- {From, To, At}: the spin-out after the gamer gets up
	local wasSeated = nil
	--.. the same pose, within half a turn of `to` (so the spring takes the short way round)
	local function NearYaw(a, to) return to + ((a - to + 180) % 360 - 180) end
	local written, writtenAt
	local lastClock = -math.huge
	local screenAcc, rgbAcc = math.huge, math.huge
	ctx:Step(function(dt, now)
		if not hitbox.Parent then return end
		local clock = os.clock()
		local woke = clock - lastClock > WAKE_GAP
		lastClock = clock
		dt = math.clamp(dt, 0, MAX_DT)
		local player, since, ended, _, _, seed = ReadState(ctx)
		local seated = player ~= 0
		local playing = seated and seed ~= 0 and since > ended and now - since >= READY

		--.. the local player sat down in this chair: open the game (once per sitting)
		if player == LocalPlayer.UserId then
			if not w.Game and not w.Declined then
				local humanoid = ctx:LocalCharacter()
				if humanoid and humanoid.SeatPart and humanoid.SeatPart.Name == SEAT_NAME then
					if Active and not Active.closed then CloseGame(Active, false) end
					OpenGame(w)
				end
			end
		else
			w.Declined = false
		end

		--.. chair: face the desk while seated (rocking while playing); a free spin back out when they get up
		if woke or wasSeated == nil then
			target = seated and sitYaw or idleYaw
			yaw, yawVel, spin = target, 0, nil
		elseif seated ~= wasSeated then
			if seated then
				target, spin = sitYaw, nil
				yaw = NearYaw(yaw, sitYaw)
			else
				target = idleYaw
				spin = {From = NearYaw(yaw, idleYaw), To = idleYaw + SPIN_OUT, At = now}
			end
		end
		wasSeated = seated
		if spin then
			--.. pushed round, slowing at a constant rate: angle = from + total * (1 - (1 - u)^2)
			local u = math.clamp((now - spin.At) / SPIN_TIME, 0, 1)
			yaw = spin.From + (spin.To - spin.From) * (1 - (1 - u) * (1 - u))
			yawVel = 0
			if u >= 1 then yaw, spin = idleYaw, nil end -- one turn on = the shipped pose
		elseif not woke then
			local goal = target
			if seated and playing then goal = sitYaw + ROCK_DEG * math.sin(now * math.pi * 2 * ROCK_HZ) end
			yawVel += (SPRING_K * (goal - yaw) - SPRING_C * yawVel) * dt
			yaw += yawVel * dt
			if not seated and math.abs(goal - yaw) < 0.01 and math.abs(yawVel) < 0.05 then yaw, yawVel = goal, 0 end
		end
		local hb = hitbox.CFrame
		if #swivelParts > 0 and (written == nil or math.abs(yaw - written) > 1e-3 or hb ~= writtenAt) then
			Kit.PoseRig(rig, hb * pivotRel * Yaw(yaw))
			written, writtenAt = yaw, hb
		end

		--.. screens at SCREEN_FPS, only when the camera is close enough to see them
		screenAcc += dt
		if L and (woke or screenAcc >= 1 / SCREEN_FPS) then
			screenAcc = 0
			if woke or ctx:CameraDistance() <= SCREEN_RANGE then
				DrawScreens(now, woke)
			end
		end

		--.. rainbow at RGB_FPS
		rgbAcc += dt
		if woke or rgbAcc >= 1 / RGB_FPS then
			DrawRGB(math.min(rgbAcc, 0.25), playing)
			rgbAcc = 0
		end
	end)

	--..Cleanup: the game closed, the chair as shipped (relative to where the build IS now), RGB colours back..--
	return function()
		if w.Game then CloseGame(w.Game, false) end
		if hitbox.Parent then
			for part, rel in pairs(home) do
				if part.Parent then part.CFrame = hitbox.CFrame * rel end
			end
		end
		for _, r in ipairs(rgb) do
			if r.Part.Parent then r.Part.Color = r.Home end
		end
	end
end

--..Server events: the gamer's inputs (relayed as they come) and whole lists (the answer to "Sync")..--
function B.OnEvent(model, action, payload, ctx)
	local w = ctx.Desk
	if not w or type(payload) ~= "table" then return end
	local seed = tonumber(payload.s)
	if not seed or seed == 0 or seed ~= (tonumber(ctx:State("Seed")) or 0) then return end
	local run = w.GetRun and w.GetRun(seed)
	if not run or run.Owned then return end -- the gamer's own run already has every event
	local codes = type(payload.c) == "table" and payload.c or {}
	local n = tonumber(payload.n) or -1 -- the server's count after this batch (-1: its list is full, just follow)
	if action == "Input" then
		if n >= 0 then
			local have = #run.Ticks
			if n <= have then return end
			if n - #codes ~= have then
				run.Complete = false -- a gap (this client arrived late): the next draw asks for the whole list
				return
			end
		end
		for _, code in ipairs(codes) do AddCode(run, code) end
	elseif action == "Events" then
		SetCodes(run, codes)
		run.Complete = true
	end
end

--.. the simulation, for headless tests (tests/HomeOffice)
B.Sim = {
	NewRun = NewRun, NewSim = NewSim, StepSim = StepSim, Advance = Advance, Snapshot = Snapshot, Restore = Restore,
	Score = Score, Extend = Extend, AddCode = AddCode, SetCodes = SetCodes, Speed = Speed, Kinds = KINDS,
	TickRate = TICK_RATE, Ready = READY, HeroHalf = HERO_HALF,
}

return B
]======]
SOURCES['S_GamingDesk'] = [======[
--[[
	GamingDesk  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds HomeOffice
	Server half of the GAMING DESK (fun-builds/notes/GamingDesk.md). The racing chair gets one invisible Seat at
	Pivot_Seat, facing the desk (authored +Z), with the prompt "Game" - anyone may play, it is a desk.
	CUKE RUN is PLAYED (2026-09-24, user: "make the gaming desk make u play the actual game instead of just show a
	video"): sitting down starts a RUN, the gamer's client plays it in a GUI and the client half of every other
	player re-simulates it on the monitor from the inputs this half relays.
	State (ReplicatedStorage.FunBehavioursClient.GamingDesk draws everything from it):
	  Fun_Player  the gamer's UserId (0 = nobody, -1 = a humanoid that is not a player: no run)
	  Fun_Seed    the current / last run's course seed (0 = none yet)
	  Fun_Since   Kit.Now() when that run started (sim time 0 = Since + READY); a run is LIVE while Since > Ended
	  Fun_Ended   Kit.Now() when the last run ended (the crash was reported, the gamer got up, or it went quiet)
	  Fun_EndTick the ended run's last sim tick, from the gamer's "Over" (0 = not known: the run ended without one).
	              Replays of the run stop there (Ended - Since is later: it includes the network delay)
	  Fun_Final   that run's score (0 = none / not plausible), Fun_Best the desk's best (survives a move / break of
	              the same build; not saved across servers)
	Runs  StartRun on sitting down and on "Again" (new seed + Since). The gamer's "Input" events (press / release,
	      stamped with their sim tick) are checked (the gamer, this seed, known kinds, ticks in order and not ahead
	      of the server clock), stored (up to MAX_EVENTS) as codes tick * 4 + kind and relayed to every client
	      (ctx:Fire "Input" {s, c, n = stored count}); "Sync" answers one client with the whole list ("Events").
	      "Over" {s, score, seconds} ends the run: the score counts only if plausible - seconds >= MIN_SECONDS, no
	      more than the server's clock allows (+ CLOCK_SLACK), score <= seconds * RATE + BONUS - then Final / Best /
	      Ended like before (NEW HI! on the monitor). EndTick = seconds in ticks whenever the time itself is
	      plausible (also for a run too short / a score too high to count). Getting up ends a live run after
	      LEAVE_GRACE (the client's "Over" usually comes first); a live run with no input for QUIET_SECONDS ends
	      without a score.
	      "Leave" stands the gamer up (the client also jumps out itself). No economy impact: the score is only drawn.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local SEAT_SIZE = Vector3.new(1.8, 0.4, 1.8) -- the invisible Seat; its TOP face sits on Pivot_Seat
local SEAT_FALLBACK = Vector3.new(0, 2.12, -1.92) -- authored, if Pivot_Seat is missing (build_GamingDesk.py)
local SEAT_NAME = "GamingDeskSeat"           -- the client half looks for this name on Humanoid.SeatPart

--.. the game (same numbers as the client half)
local TICK_RATE = 120          -- simulation ticks per second
local READY = 1.6              -- s of "READY?" / "GO!" before sim time 0
--.. plausibility: distance points <= VMAX (72) / PX_PER_POINT (3) = 24 per s; coins (50 each) at most one per
--.. obstacle gap, and a gap is at least (AIR_TIME + REACT_TIME = 0.95 s) of running = 52.7 per s -> 76.7 per s
local RATE, BONUS = 80, 150
local MIN_SECONDS = 2          -- a run shorter than this never scores (the first obstacle is ~2.5 s in)
local CLOCK_SLACK = 2          -- s of network jitter on top of the server-measured run time
local MAX_SCORE = 999999
local MAX_EVENTS = 6000        -- stored per run (~50 min of hard play); past it inputs are still relayed, not stored
local MAX_BATCH = 24           -- events per "Input"
local QUIET_SECONDS = 12       -- a live run with no input for this long ends (a run always needs a jump every few s)
local LEAVE_GRACE = 0.75       -- s after the gamer gets up before a live run is ended without a score
local AGAIN_GAP = 0.5          -- s between a run ending and "Again"
local SYNC_GAP = 1             -- s between two "Sync" answers to the same player
local KIND_CODES = {jump = 0, jumpUp = 1, duck = 2, duckUp = 3}

--..State..--
local Seeds = Random.new()
local Best = setmetatable({}, {__mode = "k"}) -- [model] = best score: survives a restart of the same build

local B = {}
B.Keys = {"GamingDesk"}
B.ActionRange = 200 -- "Sync" comes from anyone watching the monitor; the gamer's actions check the gamer

--..Helpers..--
local function Finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function StartRun(ctx)
	local d = ctx.Desk
	local seed
	repeat seed = Seeds:NextInteger(1, 2147483646) until seed ~= d.Seed
	d.Seed, d.Codes, d.LastTick, d.Full = seed, {}, 0, false
	d.Live, d.Quiet = true, os.clock()
	d.Gamer = ctx:GetState("Player")
	d.Since = Kit.Now()
	ctx:SetState("EndTick", 0) -- (set before Since / Seed: replicated in this order)
	ctx:SetState("Since", d.Since)
	ctx:SetState("Seed", seed)
end

--.. score = nil: the run ends without one (Final 0, Best unchanged); endTick = nil: its last tick is not known
local function EndRun(ctx, score, endTick)
	local d = ctx.Desk
	if not d.Live then return end
	d.Live = false
	d.EndedAt = os.clock()
	local final = score or 0
	ctx:SetState("Final", final)
	if score then
		local best = math.max(tonumber(ctx:GetState("Best")) or 0, final)
		Best[ctx.Model] = best
		ctx:SetState("Best", best)
	end
	ctx:SetState("EndTick", endTick or 0) -- (before Ended: a client that sees the end sees its tick)
	ctx:SetState("Ended", Kit.Now())
end

--..Behaviour..--
function B.Server(model, ctx)
	local top = Kit.Pivot(model, "Seat") or Kit.ToWorld(model, SEAT_FALLBACK)
	--.. the build's authored axes turned half a turn: the sitter faces the desk (authored +Z)
	local rotation = Kit.Origin(model).Rotation * CFrame.Angles(0, math.pi, 0)
	local seat = ctx:Seat(CFrame.new(top) * rotation * CFrame.new(0, -SEAT_SIZE.Y * 0.5, 0), {
		Name = SEAT_NAME,
		Size = SEAT_SIZE,
		Prompt = "Game",
		Object = "Gaming Desk",
		Distance = 8,
	})

	local d = {Seat = seat, Seed = 0, Codes = {}, LastTick = 0, Full = false, Live = false, Quiet = 0, Gamer = 0,
		Since = 0, EndedAt = 0, Synced = setmetatable({}, {__mode = "k"})}
	ctx.Desk = d
	ctx:SetState("Player", 0)
	ctx:SetState("Seed", 0)
	ctx:SetState("EndTick", 0)
	ctx:SetState("Best", Best[model] or 0)

	--.. who sits here -> Player + a new run; getting up -> Player 0 and the live run ends
	local function Sync()
		local humanoid = seat.Occupant
		local current = ctx:GetState("Player") or 0
		if humanoid then
			local player = Players:GetPlayerFromCharacter(humanoid.Parent)
			local id = player and player.UserId or -1
			if id ~= current then
				EndRun(ctx, nil)
				ctx:SetState("Player", id)
				if player then StartRun(ctx) end
			end
		elseif current ~= 0 then
			ctx:SetState("Player", 0)
			if d.Live then
				local seed = d.Seed
				task.delay(LEAVE_GRACE, function()
					if ctx:Alive() and d.Live and d.Seed == seed then EndRun(ctx, nil) end
				end)
			end
		end
	end
	ctx:Connect(seat:GetPropertyChangedSignal("Occupant"), Sync)
	Sync()

	--.. a live run that went quiet (the gamer's client stopped sending) ends
	ctx:Every(1, function()
		if d.Live and os.clock() - d.Quiet > QUIET_SECONDS then EndRun(ctx, nil) end
	end)
end

--..Actions (client -> server)..--
B.Actions = {
	--.. {s = seed, t = sim time, k = kind} or {s = seed, e = {{t, k}, ...}}: the gamer's presses / releases
	Input = function(model, player, payload, ctx)
		local d = ctx.Desk
		if not d or not d.Live or player.UserId ~= d.Gamer or type(payload) ~= "table" or payload.s ~= d.Seed then return end
		local list = type(payload.e) == "table" and payload.e or {payload}
		local maxTick = (Kit.Now() - d.Since - READY + CLOCK_SLACK) * TICK_RATE
		local out = {}
		for i = 1, math.min(#list, MAX_BATCH) do
			local e = list[i]
			local code = type(e) == "table" and KIND_CODES[e.k]
			if code and Finite(e.t) then
				local tick = math.floor(e.t * TICK_RATE + 0.5)
				if tick >= 1 and tick >= d.LastTick and tick <= maxTick then
					d.LastTick = tick
					table.insert(out, tick * 4 + code)
				end
			end
		end
		if #out == 0 then return end
		d.Quiet = os.clock()
		if not d.Full and #d.Codes + #out <= MAX_EVENTS then
			table.move(out, 1, #out, #d.Codes + 1, d.Codes)
			ctx:Fire("Input", {s = d.Seed, c = out, n = #d.Codes})
		else
			d.Full = true
			ctx:Fire("Input", {s = d.Seed, c = out, n = -1})
		end
	end,

	--.. {s = seed, score = n, seconds = sim seconds}: the crash (or the gamer left mid-run)
	Over = function(model, player, payload, ctx)
		local d = ctx.Desk
		if not d or not d.Live or player.UserId ~= d.Gamer or type(payload) ~= "table" or payload.s ~= d.Seed then return end
		local score, seconds = payload.score, payload.seconds
		if not Finite(score) or not Finite(seconds) then
			EndRun(ctx, nil)
			return
		end
		score = math.floor(score)
		local elapsed = Kit.Now() - d.Since - READY
		--.. the run's last tick, if the time is possible at all (the replays stop there)
		local endTick = (seconds > 0 and seconds <= elapsed + CLOCK_SLACK) and math.floor(seconds * TICK_RATE + 0.5) or nil
		if score < 0 or score > MAX_SCORE or seconds < MIN_SECONDS or seconds > elapsed + CLOCK_SLACK or score > seconds * RATE + BONUS then
			EndRun(ctx, nil, endTick) -- implausible (or too short): the run ends without a score
			return
		end
		EndRun(ctx, score, endTick)
	end,

	--.. PLAY AGAIN: a new run for the seated gamer
	Again = function(model, player, payload, ctx)
		local d = ctx.Desk
		if not d or d.Live or ctx:GetState("Player") ~= player.UserId then return end
		local humanoid = ctx:HumanoidOf(player)
		if not humanoid or d.Seat.Occupant ~= humanoid then return end
		if os.clock() - d.EndedAt < AGAIN_GAP then return end
		StartRun(ctx)
	end,

	--.. a client that came in late (or missed a relay) wants the whole list of this run
	Sync = function(model, player, payload, ctx)
		local d = ctx.Desk
		if not d or d.Seed == 0 or type(payload) ~= "table" or payload.s ~= d.Seed then return end
		local now = os.clock()
		if now - (d.Synced[player] or -math.huge) < SYNC_GAP then return end
		d.Synced[player] = now
		ctx:FireTo(player, "Events", {s = d.Seed, c = d.Codes, n = d.Full and -1 or #d.Codes})
	end,

	--.. EXIT: stand the gamer up
	Leave = function(model, player, payload, ctx)
		local d = ctx.Desk
		local humanoid = ctx:HumanoidOf(player)
		if not d or not humanoid or d.Seat.Occupant ~= humanoid then return end
		local weld = d.Seat:FindFirstChild("SeatWeld")
		if weld then weld:Destroy() end
	end,
}

return B
]======]
SOURCES['C_GrandfatherClock'] = [======[
--[[
	GrandfatherClock  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds HomeOffice
	Client half of the GRANDFATHER CLOCK (fun-builds/notes/GrandfatherClock.md). There is no server half: the clock
	has no prompt and no state - it reads the game's own day/night clock, ServerScriptService.DayNightCycle:
	  DAY    Lighting.ClockTime runs 11:00 -> 16:00 over the 180 s day (the loop stops just short: ~15:59.8)
	  NIGHT  workspace.IsNight = true for the 10 s night. Since the BRIGHT NIGHT (2026-09-23) ClockTime is NOT moved at
	         night (it stays at the day's last value unless DayNightCycle has a NightClockTime attribute), so the dial
	         does not read ClockTime then: while IsNight is set the clock shows MIDNIGHT, whatever ClockTime says.
	  PENDULUM  Pendulum* swing about Pivot_PendulumPivot (the build's authored Z axis), State_PendulumSwing degrees
	            either way, PERIOD 2 s, phased from Kit.Now() so every client swings in step
	  TICK      a soft tock at each end of the swing (Sfx.ClockTick, alternating pitch) while the local character is
	            within TICK_RANGE studs
	  HANDS     HourHand* / MinuteHand* turn about Pivot_FaceCentre to show that time; Moon* (the sun/moon dial in
	            the arch, about Pivot_MoonCentre) turns once a day - sun up at noon, moon up at midnight.
	            The shown time only ever moves FORWARD: when the time jumps (night falls ~16:00 -> midnight, day
	            breaks midnight -> 11:00) the hands whirr round at SPIN_RATE hours per second with fast ticking
	  CHIME     every in-game hour (each 36 s by day) the clock strikes the hour: 1..12 strikes of Sfx.ClockChime,
	            STRIKE_GAP apart; a whirr that lands on (or, as the clock keeps running while the hands spin, up to
	            SNAP_HOURS past) the hour strikes it too: midnight strikes twelve as the zombies come, daybreak
	            strikes eleven. An hour struck while the last one is still ringing out waits its turn (queued).
	A positive angle turns clockwise as seen from the front: CFrame.Angles(0, 0, rad(angle)) about the pivot; the
	shipped poses are State_HourAngle / State_MinuteAngle / State_MoonAngle (the model shows 10:10, sun up).
	Everything is posed relative to the Hitbox; cleanup puts the parts back as shipped.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

--..Config..--
local LOCAL_FOLDER = "FunBuildLocal"
local PERIOD = 2                       -- s: one full swing there and back
local DEFAULT_SWING = 6                -- degrees either way
local DEFAULT_HOUR_SHIP, DEFAULT_MINUTE_SHIP, DEFAULT_MOON_SHIP = 305, 60, 0
local FACE_FALLBACK = Vector3.new(0, 6.25, -0.93)      -- authored (build_GrandfatherClock.py), if a pivot is missing
local PENDULUM_FALLBACK = Vector3.new(0, 5.12, -0.22)
local MOON_FALLBACK = Vector3.new(0, 7.5, -0.625)
local CHIME_FALLBACK = Vector3.new(0, 6.3, 0)
local SNAP_HOURS = 0.25                -- a forward step smaller than this is just time passing
local HOLD_HOURS = 1                   -- the clock less than this BEHIND the shown time: wait for it (never run back)
local SPIN_RATE = 5                    -- hours per second while whirring forward
local SPIN_TICK = 0.07                 -- s between whirr ticks
local LAND_EPS = 1e-3                  -- hours: float slack - a whirr landing a hair UNDER the hour lands on it
local STRIKE_GAP = 1.1                 -- s between strikes
local HOUR_PAUSE = 1.1                 -- s of extra silence before a queued hour starts striking
local MAX_STRIKES = 12
local MAX_QUEUED = 2                   -- hours that may wait to strike (the one ringing + the next)
local TICK_RANGE = 22                  -- studs (local character) for the tick-tock and the whirr
local CHIME_RANGE = 120                -- studs (camera): strikes only start within this
local TICK_VOLUME, CHIME_VOLUME = 0.22, 0.45
local TICK_PITCH = {1.0, 0.86}         -- tick, tock
local MAX_DT = 1 / 15
local WAKE_GAP = 0.5                   -- s without a Step (camera away) -> snap to the time, no sounds

local B = {}
B.Keys = {"GrandfatherClock"}
B.StepRange = 160

--..Helpers..--
local function LocalFolder()
	local folder = workspace:FindFirstChild(LOCAL_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = LOCAL_FOLDER
		folder.Archivable = false
		folder.Parent = workspace
	end
	return folder
end

--.. clockwise (seen from the front) about the pivot's Z axis
local function Turn(deg)
	return CFrame.Angles(0, 0, math.rad(deg))
end

--.. 0 -> 12, 13 -> 1 ...
local function Hour12(h)
	return (h - 1) % 12 + 1
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local rotation = Kit.Origin(model).Rotation
	local function PivotFrame(name, fallback)
		local pos = Kit.Pivot(model, name) or Kit.ToWorld(model, fallback)
		local cf = CFrame.new(pos) * rotation
		return cf, hitbox.CFrame:ToObjectSpace(cf)
	end
	local function Ship(attr, default)
		return tonumber(model:GetAttribute(attr)) or default
	end

	--..Rigs (each relative to its zero pose: the shipped parts turned back by their State_* angle)..--
	local home = {} -- [part] = CFrame relative to the Hitbox, restored on cleanup
	local function MakeRig(prefix, pivotCF, shipAngle)
		local parts = Kit.Parts(model, prefix)
		for _, p in ipairs(parts) do home[p] = hitbox.CFrame:ToObjectSpace(p.CFrame) end
		return #parts > 0 and Kit.Rig(parts, pivotCF * Turn(shipAngle)) or nil
	end
	local pendCF, pendRel = PivotFrame("PendulumPivot", PENDULUM_FALLBACK)
	local faceCF, faceRel = PivotFrame("FaceCentre", FACE_FALLBACK)
	local moonCF, moonRel = PivotFrame("MoonCentre", MOON_FALLBACK)
	local swing = Ship("State_PendulumSwing", DEFAULT_SWING)
	local pendulum = MakeRig("Pendulum", pendCF, 0)
	local hourHand = MakeRig("HourHand", faceCF, Ship("State_HourAngle", DEFAULT_HOUR_SHIP))
	local minuteHand = MakeRig("MinuteHand", faceCF, Ship("State_MinuteAngle", DEFAULT_MINUTE_SHIP))
	local moon = MakeRig("Moon", moonCF, Ship("State_MoonAngle", DEFAULT_MOON_SHIP))

	--..Sounds (from the movement inside the hood)..--
	local chimePos = Kit.Pivot(model, "Chime") or Kit.ToWorld(model, CHIME_FALLBACK)
	local speaker = ctx:Part({Name = "GrandfatherClockMovement", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(chimePos), Transparency = 1, Parent = LocalFolder()})
	local function Sfx(name, volume, maxDistance)
		local id = type(FunAssets.Sfx) == "table" and FunAssets.Sfx[name] or nil
		if not id then return nil end
		return ctx:Sound(speaker, id, {Volume = volume, Looped = false, RollOffMinDistance = 6, RollOffMaxDistance = maxDistance})
	end
	local sfxTick = Sfx("ClockTick", TICK_VOLUME, 30)
	local chimes = {Sfx("ClockChime", CHIME_VOLUME, 80), Sfx("ClockChime", CHIME_VOLUME, 80)} -- two, so a strike rings on under the next
	local function Play(sound, speed)
		if not sound then return end
		pcall(function()
			sound.PlaybackSpeed = speed or 1
			sound.TimePosition = 0
			sound:Play()
		end)
	end

	--..Strikes (a queue: midnight's twelve outlast the 10 s night, so daybreak's eleven follow them)..--
	local queue = {}         -- strikes left per waiting hour, [1] = the one ringing now
	local nextStrike, strikeN = 0, 0
	local function Strike(hour, now)
		if ctx:CameraDistance() > CHIME_RANGE or #queue >= MAX_QUEUED then return end
		if #queue == 0 then nextStrike = math.max(nextStrike, now) end
		table.insert(queue, math.min(MAX_STRIKES, Hour12(hour)))
	end

	--..What turns, and by how much..--
	local shown = nil        -- the time on the dial in hours, continuous (only grows; wrapped when drawn)
	local jobs = {}          -- {Rig, Rel (pivot relative to the Hitbox), Angle = fn(now), Posed = last angle}
	local function Job(rig, rel, angle)
		if rig then table.insert(jobs, {Rig = rig, Rel = rel, Angle = angle}) end
	end
	Job(pendulum, pendRel, function(now) return swing * math.sin(now * math.pi * 2 / PERIOD) end)
	Job(hourHand, faceRel, function() return (shown % 12) * 30 end)
	Job(minuteHand, faceRel, function() return (shown % 1) * 360 end)
	Job(moon, moonRel, function() return ((shown - 12) % 24) * 15 end)

	--..Every frame..--
	local spinning = false
	local lastClock = -math.huge
	local lastSwingEnd = nil
	local lastSpinTick = 0
	local posedAt = nil      -- the Hitbox CFrame the parts were last posed against
	ctx:Step(function(dt, now)
		if not hitbox.Parent then return end
		local clock = os.clock()
		local woke = clock - lastClock > WAKE_GAP
		lastClock = clock
		dt = math.clamp(dt, 0, MAX_DT)

		--.. the shown time chases the game's time forward: Lighting.ClockTime by day, MIDNIGHT all night (the
		--.. bright night leaves ClockTime at ~15.997, so night falling reads as a whirr 16 -> 24 onto midnight)
		local target
		if workspace:GetAttribute("IsNight") == true then
			target = 0
		else
			target = (tonumber(Lighting.ClockTime) or 12) % 24
		end
		if woke or shown == nil then
			shown, spinning = target, false
			table.clear(queue)
		else
			local ahead = (target - shown) % 24
			if ahead > 24 - HOLD_HOURS then
				--.. the clock is a little behind the dial: hold
			elseif ahead <= SNAP_HOURS and not spinning then
				local before = shown
				shown += ahead
				if math.floor(shown) > math.floor(before) then Strike(math.floor(shown) % 24, now) end
			else
				spinning = true
				local step = math.min(ahead, SPIN_RATE * dt)
				shown += step
				if now - lastSpinTick >= SPIN_TICK and ctx:Near(TICK_RANGE) then
					lastSpinTick = now
					Play(sfxTick, 1.5)
				end
				if ahead - step <= 1e-6 then
					--.. landed. The clock kept running while the hands spun (daybreak lands ~11:04), so anything
					--.. up to SNAP_HOURS past an hour strikes it; a float hair under the hour lands ON it
					spinning = false
					local h = math.floor(shown + LAND_EPS)
					if h > shown then shown = h end
					if shown - h < SNAP_HOURS then Strike(h % 24, now) end
				end
			end
			if shown > 240 then shown -= 240 end -- keep the number small (a multiple of 24 and 12)
		end

		--.. the pendulum's tick at each end of its swing (angle = swing * sin(2 pi t / PERIOD))
		local swingEnd = math.floor((now - PERIOD * 0.25) / (PERIOD * 0.5))
		if lastSwingEnd and swingEnd ~= lastSwingEnd and not woke and ctx:Near(TICK_RANGE) then
			Play(sfxTick, TICK_PITCH[swingEnd % 2 + 1])
		end
		lastSwingEnd = swingEnd

		--.. strikes
		if queue[1] and now >= nextStrike then
			queue[1] -= 1
			strikeN += 1
			nextStrike = now + STRIKE_GAP
			Play(chimes[strikeN % 2 + 1], 1)
			if queue[1] <= 0 then
				table.remove(queue, 1)
				if queue[1] then nextStrike += HOUR_PAUSE end -- a beat of silence between two hours
			end
		end

		--.. pose (the pendulum every frame, the hands / moon only when they moved)
		local hb = hitbox.CFrame
		local moved = hb ~= posedAt
		posedAt = hb
		for _, j in ipairs(jobs) do
			local angle = j.Angle(now)
			if moved or j.Posed == nil or math.abs(j.Posed - angle) > 0.01 then
				Kit.PoseRig(j.Rig, hb * j.Rel * Turn(angle))
				j.Posed = angle
			end
		end
	end)

	--..Cleanup: every rigged part back as shipped, relative to where the build IS now..--
	return function()
		if not hitbox.Parent then return end
		for part, rel in pairs(home) do
			if part.Parent then part.CFrame = hitbox.CFrame * rel end
		end
	end
end

return B
]======]
MODELS = {}
MODELS['GamingDesk'] = {Min = Vector3.new(-3.6, 0.0, -3.472), Max = Vector3.new(3.6, 5.35, 3.3), Attrs = {Pivot_ChairSwivel = Vector3.new(0.0, 0.0, -2.0), Pivot_Seat = Vector3.new(0.0, 2.12, -1.92), Pivot_RGBGlow = Vector3.new(0.0, 2.3, 1.5), Pivot_Keys = Vector3.new(0.0, 3.3, 0.7), Pivot_Monitor = Vector3.new(0.0, 4.4, 2.25), State_ChairIdleYaw = 32.0, State_ChairSitYaw = 0.0, Cost = 2000.0, DisplayName = "Gaming Desk"}, Parts = {
	{Name = "DeskTop", Shape = "Block", Size = Vector3.new(7.2, 0.16, 3.4), CF = {0.0, 3.02, 1.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "RGBDeskFront", Shape = "Block", Size = Vector3.new(6.9, 0.06, 0.06), CF = {0.0, 2.91, -0.04, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ff3df0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "MatTrim", Shape = "Block", Size = Vector3.new(5.5, 0.05, 1.66), CF = {0.1, 3.12, 0.86, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "Mat", Shape = "Block", Size = Vector3.new(5.4, 0.05, 1.56), CF = {0.1, 3.135, 0.86, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "DeskFootL", Shape = "Block", Size = Vector3.new(0.38, 0.22, 3.3), CF = {3.2, 0.11, 1.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "DeskPostL", Shape = "Block", Size = Vector3.new(0.38, 0.42, 3.635), CF = {3.2, 1.525, 1.75, 1.0, 0.0, -0.0, -0.0, 0.66026, -0.75104, 0.0, 0.75104, 0.66026}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "DeskRailL", Shape = "Block", Size = Vector3.new(0.38, 0.16, 3.1), CF = {3.2, 2.86, 1.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "DeskStripeL", Shape = "Block", Size = Vector3.new(0.05, 0.14, 3.2675), CF = {3.4, 1.56, 1.76, 1.0, 0.0, -0.0, -0.0, 0.63657, -0.77122, 0.0, 0.77122, 0.63657}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "DeskFootR", Shape = "Block", Size = Vector3.new(0.38, 0.22, 3.3), CF = {-3.2, 0.11, 1.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "DeskPostR", Shape = "Block", Size = Vector3.new(0.38, 0.42, 3.635), CF = {-3.2, 1.525, 1.75, 1.0, 0.0, -0.0, -0.0, 0.66026, -0.75104, 0.0, 0.75104, 0.66026}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "DeskRailR", Shape = "Block", Size = Vector3.new(0.38, 0.16, 3.1), CF = {-3.2, 2.86, 1.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "DeskStripeR", Shape = "Block", Size = Vector3.new(0.05, 0.14, 3.2675), CF = {-3.4, 1.56, 1.76, 1.0, 0.0, -0.0, -0.0, 0.63657, -0.77122, 0.0, 0.77122, 0.63657}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "DeskBrace", Shape = "Block", Size = Vector3.new(6.02, 0.22, 0.22), CF = {0.0, 1.1, 2.2, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "MonitorC", Shape = "Block", Size = Vector3.new(2.62, 1.54, 0.14), CF = {0.0, 4.4, 2.32, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "ScreenC", Shape = "Block", Size = Vector3.new(2.56, 1.42, 0.05), CF = {0.0, 4.4, 2.245, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6fd0ff", Material = "Neon", T = 0.0, Collide = false},
	{Name = "ScreenArtGround", Shape = "Block", Size = Vector3.new(2.56, 0.34, 0.05), CF = {0.0, 3.86, 2.215, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "5fe05a", Material = "Neon", T = 0.0, Collide = false},
	{Name = "ScreenArtHero", Shape = "Ellipsoid", Size = Vector3.new(0.2, 0.36, 0.05), CF = {0.62, 4.2, 2.215, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "2f8f3a", Material = "Neon", T = 0.0, Collide = false},
	{Name = "ScreenArtCoin", Shape = "Cylinder", Size = Vector3.new(0.055, 0.14, 0.14), CF = {0.05, 4.32, 2.215, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "ffd23d", Material = "Neon", T = 0.0, Collide = false},
	{Name = "MonitorL", Shape = "Block", Size = Vector3.new(0.9, 1.54, 0.14), CF = {1.7568, 4.4, 2.16187, 0.93969, 0.0, 0.34202, 0.0, 1.0, 0.0, -0.34202, 0.0, 0.93969}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "ScreenL", Shape = "Block", Size = Vector3.new(0.85, 1.42, 0.05), CF = {1.70766, 4.4, 2.09994, 0.93969, 0.0, 0.34202, 0.0, 1.0, 0.0, -0.34202, 0.0, 0.93969}, Color = "6fd0ff", Material = "Neon", T = 0.0, Collide = false},
	{Name = "ScreenArtGroundL", Shape = "Block", Size = Vector3.new(0.85, 0.34, 0.05), CF = {1.6974, 3.86, 2.07175, 0.93969, 0.0, 0.34202, 0.0, 1.0, 0.0, -0.34202, 0.0, 0.93969}, Color = "5fe05a", Material = "Neon", T = 0.0, Collide = false},
	{Name = "MonitorR", Shape = "Block", Size = Vector3.new(0.9, 1.54, 0.14), CF = {-1.7568, 4.4, 2.16187, 0.93969, 0.0, -0.34202, 0.0, 1.0, 0.0, 0.34202, 0.0, 0.93969}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "ScreenR", Shape = "Block", Size = Vector3.new(0.85, 1.42, 0.05), CF = {-1.70766, 4.4, 2.09994, 0.93969, 0.0, -0.34202, 0.0, 1.0, 0.0, 0.34202, 0.0, 0.93969}, Color = "6fd0ff", Material = "Neon", T = 0.0, Collide = false},
	{Name = "ScreenArtGroundR", Shape = "Block", Size = Vector3.new(0.85, 0.34, 0.05), CF = {-1.6974, 3.86, 2.07175, 0.93969, 0.0, -0.34202, 0.0, 1.0, 0.0, 0.34202, 0.0, 0.93969}, Color = "5fe05a", Material = "Neon", T = 0.0, Collide = false},
	{Name = "MonitorBack", Shape = "Ellipsoid", Size = Vector3.new(2.2, 1.2, 0.42), CF = {0.0, 4.35, 2.55, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "RGBMonitorBack", Shape = "Cylinder", Size = Vector3.new(0.055, 0.84, 0.84), CF = {0.0, 4.42, 2.75, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "ff3df0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "MonitorBackCap", Shape = "Cylinder", Size = Vector3.new(0.055, 0.6, 0.6), CF = {0.0, 4.42, 2.78, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "MonitorNeck", Shape = "Block", Size = Vector3.new(0.3, 1.3, 0.16), CF = {0.0, 3.75, 2.67, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "Metal", T = 0.0, Collide = true},
	{Name = "MonitorFootL", Shape = "Block", Size = Vector3.new(0.2, 0.06, 1.063), CF = {0.4, 3.13, 2.32, 0.6585, 0.0, -0.75258, -0.0, 1.0, -0.0, 0.75258, 0.0, 0.6585}, Color = "3b4350", Material = "Metal", T = 0.0, Collide = true},
	{Name = "MonitorFootR", Shape = "Block", Size = Vector3.new(0.2, 0.06, 1.063), CF = {-0.4, 3.13, 2.32, 0.6585, 0.0, 0.75258, 0.0, 1.0, -0.0, -0.75258, 0.0, 0.6585}, Color = "3b4350", Material = "Metal", T = 0.0, Collide = true},
	{Name = "Keyboard", Shape = "Block", Size = Vector3.new(1.96, 0.1, 0.62), CF = {0.0, 3.21, 0.72, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "Keys1", Shape = "Block", Size = Vector3.new(1.76, 0.06, 0.13), CF = {0.05, 3.28, 0.57, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Keys2", Shape = "Block", Size = Vector3.new(1.76, 0.06, 0.13), CF = {0.05, 3.28, 0.74, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Keys3", Shape = "Block", Size = Vector3.new(1.56, 0.06, 0.13), CF = {0.15, 3.28, 0.9, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "RGBKeyboard", Shape = "Block", Size = Vector3.new(1.96, 0.05, 0.05), CF = {0.0, 3.18, 0.4, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ff3df0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "Mouse", Shape = "Ellipsoid", Size = Vector3.new(0.3, 0.17, 0.44), CF = {-1.4, 3.24, 0.78, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "RGBMouse", Shape = "Block", Size = Vector3.new(0.05, 0.05, 0.16), CF = {-1.4, 3.3, 0.9, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ff3df0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "SpeakerL", Shape = "Block", Size = Vector3.new(0.46, 1.04, 0.62), CF = {2.43, 3.62, 1.82, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "WooferL", Shape = "Cylinder", Size = Vector3.new(0.06, 0.36, 0.36), CF = {2.43, 3.46, 1.5, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "3b4350", Material = "Metal", T = 0.0, Collide = false},
	{Name = "TweeterL", Shape = "Cylinder", Size = Vector3.new(0.06, 0.17, 0.17), CF = {2.43, 3.9, 1.5, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "SpeakerR", Shape = "Block", Size = Vector3.new(0.46, 1.04, 0.62), CF = {-2.43, 3.62, 1.82, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "WooferR", Shape = "Cylinder", Size = Vector3.new(0.06, 0.36, 0.36), CF = {-2.43, 3.46, 1.5, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "3b4350", Material = "Metal", T = 0.0, Collide = false},
	{Name = "TweeterR", Shape = "Cylinder", Size = Vector3.new(0.06, 0.17, 0.17), CF = {-2.43, 3.9, 1.5, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "CucumberSoda", Shape = "Cylinder", Size = Vector3.new(0.43, 0.26, 0.26), CF = {3.15, 3.305, 0.95, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "5aa845", Material = "Metal", T = 0.0, Collide = false},
	{Name = "TowerTop", Shape = "Block", Size = Vector3.new(0.88, 0.1, 2.2), CF = {-3.14, 5.3, 2.05, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "TowerBottom", Shape = "Block", Size = Vector3.new(0.88, 0.12, 2.2), CF = {-3.14, 3.16, 2.05, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "TowerBack", Shape = "Block", Size = Vector3.new(0.88, 2.25, 0.08), CF = {-3.14, 4.225, 3.11, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "TowerFront", Shape = "Block", Size = Vector3.new(0.88, 2.25, 0.1), CF = {-3.14, 4.225, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "2d3139", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "TowerWall", Shape = "Block", Size = Vector3.new(0.08, 2.25, 2.2), CF = {-2.74, 4.225, 2.05, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "TowerBoard", Shape = "Block", Size = Vector3.new(0.05, 1.85, 1.8), CF = {-2.8, 4.275, 2.1, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "243a5e", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "TowerGlass", Shape = "Block", Size = Vector3.new(0.05, 2.05, 2.08), CF = {-3.55, 4.225, 2.05, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9fb8d0", Material = "Glass", T = 0.55, Collide = true},
	{Name = "TowerGpu", Shape = "Block", Size = Vector3.new(0.5, 0.24, 1.5), CF = {-3.19, 4.075, 2.17, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "Metal", T = 0.0, Collide = false},
	{Name = "RGBGpu", Shape = "Block", Size = Vector3.new(0.05, 0.07, 1.4), CF = {-3.38, 4.075, 2.17, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ff3df0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "RGBCooler", Shape = "Cylinder", Size = Vector3.new(0.06, 0.62, 0.62), CF = {-3.24, 4.725, 2.3, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0}, Color = "ff3df0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "CoolerHub", Shape = "Cylinder", Size = Vector3.new(0.06, 0.4, 0.4), CF = {-3.28, 4.725, 2.3, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "RGBRam", Shape = "Block", Size = Vector3.new(0.3, 0.5, 0.1), CF = {-3.19, 4.725, 1.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ff3df0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "RGBFan1", Shape = "Cylinder", Size = Vector3.new(0.055, 0.66, 0.66), CF = {-3.14, 4.645, 0.93, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "ff3df0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "FanHub1", Shape = "Cylinder", Size = Vector3.new(0.055, 0.44, 0.44), CF = {-3.14, 4.645, 0.9, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "RGBFan2", Shape = "Cylinder", Size = Vector3.new(0.055, 0.66, 0.66), CF = {-3.14, 3.865, 0.93, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "ff3df0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "FanHub2", Shape = "Cylinder", Size = Vector3.new(0.055, 0.44, 0.44), CF = {-3.14, 3.865, 0.9, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "RGBTowerStrip", Shape = "Block", Size = Vector3.new(0.06, 1.95, 0.06), CF = {-3.52, 4.225, 0.93, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ff3df0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "ChairBase", Shape = "Cylinder", Size = Vector3.new(0.24, 0.34, 0.34), CF = {0.0, 0.38, -2.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "ChairLeg1", Shape = "Block", Size = Vector3.new(0.16, 0.12, 1.0127), CF = {0.15451, 0.32, -1.52447, -0.95106, 0.04882, -0.30514, 0.0, 0.98744, 0.15799, 0.30902, 0.15026, -0.93911}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "ChairWheel1", Shape = "Ball", Size = Vector3.new(0.24, 0.24, 0.24), CF = {0.29975, 0.12, -1.07748, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "ChairLeg2", Shape = "Block", Size = Vector3.new(0.16, 0.12, 1.0127), CF = {0.5, 0.32, -2.0, -0.0, 0.15799, -0.98744, 0.0, 0.98744, 0.15799, 1.0, 0.0, -0.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "ChairWheel2", Shape = "Ball", Size = Vector3.new(0.24, 0.24, 0.24), CF = {0.97, 0.12, -2.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "ChairLeg3", Shape = "Block", Size = Vector3.new(0.16, 0.12, 1.0127), CF = {0.15451, 0.32, -2.47553, 0.95106, 0.04882, -0.30514, -0.0, 0.98744, 0.15799, 0.30902, -0.15026, 0.93911}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "ChairWheel3", Shape = "Ball", Size = Vector3.new(0.24, 0.24, 0.24), CF = {0.29975, 0.12, -2.92252, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "ChairLeg4", Shape = "Block", Size = Vector3.new(0.16, 0.12, 1.0127), CF = {-0.40451, 0.32, -2.29389, 0.58779, -0.12782, 0.79886, 0.0, 0.98744, 0.15799, -0.80902, -0.09286, 0.5804}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "ChairWheel4", Shape = "Ball", Size = Vector3.new(0.24, 0.24, 0.24), CF = {-0.78475, 0.12, -2.57015, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "ChairLeg5", Shape = "Block", Size = Vector3.new(0.16, 0.12, 1.0127), CF = {-0.40451, 0.32, -1.70611, -0.58779, -0.12782, 0.79886, 0.0, 0.98744, 0.15799, -0.80902, 0.09286, -0.5804}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "ChairWheel5", Shape = "Ball", Size = Vector3.new(0.24, 0.24, 0.24), CF = {-0.78475, 0.12, -1.42985, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b4350", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "ChairSleeve", Shape = "Cylinder", Size = Vector3.new(0.72, 0.2, 0.2), CF = {0.0, 0.84, -2.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "SwivelLift", Shape = "Cylinder", Size = Vector3.new(0.47, 0.12, 0.12), CF = {0.0, 1.385, -2.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "SwivelMech", Shape = "Block", Size = Vector3.new(0.8, 0.14, 0.8), CF = {0.0265, 1.66, -1.9576, 0.84805, 0.0, 0.52992, 0.0, 1.0, 0.0, -0.52992, 0.0, 0.84805}, Color = "23262c", Material = "Metal", T = 0.0, Collide = false},
	{Name = "SwivelPan", Shape = "Block", Size = Vector3.new(1.8, 0.26, 1.85), CF = {0.0265, 1.85, -1.9576, 0.84805, 0.0, 0.52992, 0.0, 1.0, 0.0, -0.52992, 0.0, 0.84805}, Color = "23262c", Material = "Leather", T = 0.0, Collide = false},
	{Name = "SwivelSeat", Shape = "Ellipsoid", Size = Vector3.new(1.3, 0.34, 1.8), CF = {0.05299, 2.0, -1.9152, 0.84805, 0.0, 0.52992, 0.0, 1.0, 0.0, -0.52992, 0.0, 0.84805}, Color = "23262c", Material = "Leather", T = 0.0, Collide = false},
	{Name = "SwivelBolsterL", Shape = "Ellipsoid", Size = Vector3.new(0.44, 0.44, 1.84), CF = {0.65299, 2.05, -2.3137, 0.84805, 0.0, 0.52992, 0.0, 1.0, 0.0, -0.52992, 0.0, 0.84805}, Color = "d9443c", Material = "Leather", T = 0.0, Collide = false},
	{Name = "SwivelBolsterR", Shape = "Ellipsoid", Size = Vector3.new(0.44, 0.44, 1.84), CF = {-0.5682, 2.05, -1.55061, 0.84805, 0.0, 0.52992, 0.0, 1.0, 0.0, -0.52992, 0.0, 0.84805}, Color = "d9443c", Material = "Leather", T = 0.0, Collide = false},
	{Name = "SwivelBack", Shape = "Block", Size = Vector3.new(1.5, 2.56, 0.34), CF = {-0.44513, 3.28, -2.71236, 0.84805, -0.09202, 0.52187, 0.0, 0.98481, 0.17365, -0.52992, -0.14726, 0.83516}, Color = "23262c", Material = "Leather", T = 0.0, Collide = false},
	{Name = "SwivelWingL", Shape = "Block", Size = Vector3.new(0.34, 2.2, 0.5), CF = {0.23522, 3.17571, -3.02002, 0.93802, -0.09202, 0.33415, 0.0361, 0.98481, 0.16985, -0.3447, -0.14726, 0.92709}, Color = "d9443c", Material = "Leather", T = 0.0, Collide = false},
	{Name = "SwivelWingR", Shape = "Block", Size = Vector3.new(0.34, 2.2, 0.5), CF = {-1.0199, 3.17571, -2.23574, 0.72101, -0.09202, 0.68678, -0.0361, 0.98481, 0.16985, -0.69198, -0.14726, 0.70674}, Color = "d9443c", Material = "Leather", T = 0.0, Collide = false},
	{Name = "SwivelHeadrest", Shape = "Ellipsoid", Size = Vector3.new(0.92, 0.46, 0.28), CF = {-0.40946, 4.16514, -2.65527, 0.84805, -0.09202, 0.52187, 0.0, 0.98481, 0.17365, -0.52992, -0.14726, 0.83516}, Color = "23262c", Material = "Leather", T = 0.0, Collide = false},
	{Name = "SwivelLumbar", Shape = "Ellipsoid", Size = Vector3.new(1.04, 0.44, 0.28), CF = {-0.27327, 2.70762, -2.43732, 0.84805, -0.09202, 0.52187, 0.0, 0.98481, 0.17365, -0.52992, -0.14726, 0.83516}, Color = "d9443c", Material = "Leather", T = 0.0, Collide = false},
	{Name = "SwivelLogo", Shape = "Ellipsoid", Size = Vector3.new(0.34, 0.74, 0.06), CF = {-0.57128, 3.59343, -2.91423, 0.84805, -0.09202, 0.52187, 0.0, 0.98481, 0.17365, -0.52992, -0.14726, 0.83516}, Color = "5aa845", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "SwivelArmPostL", Shape = "Block", Size = Vector3.new(0.14, 0.64, 0.22), CF = {0.84805, 2.1, -2.52992, 0.84805, 0.0, 0.52992, 0.0, 1.0, 0.0, -0.52992, 0.0, 0.84805}, Color = "23262c", Material = "Metal", T = 0.0, Collide = false},
	{Name = "SwivelArmPadL", Shape = "Block", Size = Vector3.new(0.24, 0.1, 0.84), CF = {0.91164, 2.46, -2.42815, 0.84805, 0.0, 0.52992, 0.0, 1.0, 0.0, -0.52992, 0.0, 0.84805}, Color = "23262c", Material = "Leather", T = 0.0, Collide = false},
	{Name = "SwivelArmPostR", Shape = "Block", Size = Vector3.new(0.14, 0.64, 0.22), CF = {-0.84805, 2.1, -1.47008, 0.84805, 0.0, 0.52992, 0.0, 1.0, 0.0, -0.52992, 0.0, 0.84805}, Color = "23262c", Material = "Metal", T = 0.0, Collide = false},
	{Name = "SwivelArmPadR", Shape = "Block", Size = Vector3.new(0.24, 0.1, 0.84), CF = {-0.78446, 2.46, -1.36831, 0.84805, 0.0, 0.52992, 0.0, 1.0, 0.0, -0.52992, 0.0, 0.84805}, Color = "23262c", Material = "Leather", T = 0.0, Collide = false},
}}
MODELS['GrandfatherClock'] = {Min = Vector3.new(-1.33, 0.0, -1.03), Max = Vector3.new(1.33, 8.5, 0.83), Attrs = {Pivot_PendulumPivot = Vector3.new(0.0, 5.12, -0.22), Pivot_FaceCentre = Vector3.new(0.0, 6.25, -0.93), Pivot_MoonCentre = Vector3.new(0.0, 7.5, -0.625), Pivot_Chime = Vector3.new(0.0, 6.3, 0.0), State_HourAngle = 305.0, State_MinuteAngle = 60.0, State_MoonAngle = 0.0, State_PendulumSwing = 6.0, Cost = 1500.0, DisplayName = "Grandfather Clock"}, Parts = {
	{Name = "Foot1", Shape = "Ellipsoid", Size = Vector3.new(0.5, 0.36, 0.5), CF = {1.02, 0.18, -0.58, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Foot2", Shape = "Ellipsoid", Size = Vector3.new(0.5, 0.36, 0.5), CF = {-1.02, 0.18, -0.58, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Foot3", Shape = "Ellipsoid", Size = Vector3.new(0.5, 0.36, 0.5), CF = {1.02, 0.18, 0.58, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Foot4", Shape = "Ellipsoid", Size = Vector3.new(0.5, 0.36, 0.5), CF = {-1.02, 0.18, 0.58, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Plinth", Shape = "Block", Size = Vector3.new(2.4, 1.24, 1.46), CF = {0.0, 0.86, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "PlinthPanel", Shape = "Block", Size = Vector3.new(1.62, 0.78, 0.06), CF = {0.0, 0.86, -0.745, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "PlinthMould", Shape = "Block", Size = Vector3.new(2.56, 0.16, 1.58), CF = {0.0, 1.53, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TrunkBack", Shape = "Block", Size = Vector3.new(2.08, 3.66, 0.12), CF = {0.0, 3.4, 0.55, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "4e311a", Material = "WoodPlanks", T = 0.0, Collide = true},
	{Name = "TrunkSideL", Shape = "Block", Size = Vector3.new(0.14, 3.66, 1.18), CF = {0.99, 3.4, -0.02, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DoorStileL", Shape = "Block", Size = Vector3.new(0.3, 3.66, 0.1), CF = {0.87, 3.4, -0.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TrunkSideR", Shape = "Block", Size = Vector3.new(0.14, 3.66, 1.18), CF = {-0.99, 3.4, -0.02, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DoorStileR", Shape = "Block", Size = Vector3.new(0.3, 3.66, 0.1), CF = {-0.87, 3.4, -0.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DoorRailTop", Shape = "Block", Size = Vector3.new(1.5, 0.34, 0.1), CF = {0.0, 5.06, -0.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DoorRailBottom", Shape = "Block", Size = Vector3.new(1.5, 0.34, 0.1), CF = {0.0, 1.77, -0.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DoorGlass", Shape = "Block", Size = Vector3.new(1.46, 2.98, 0.05), CF = {0.0, 3.41, -0.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "cfe6f2", Material = "Glass", T = 0.72, Collide = false},
	{Name = "DoorKnob", Shape = "Ball", Size = Vector3.new(0.14, 0.14, 0.14), CF = {-0.87, 3.4, -0.7, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "WaistMould", Shape = "Block", Size = Vector3.new(2.34, 0.16, 1.44), CF = {0.0, 5.3, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chain1", Shape = "Block", Size = Vector3.new(0.05, 0.73, 0.05), CF = {0.42, 4.835, 0.24, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "7d6a45", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Weight1", Shape = "Cylinder", Size = Vector3.new(0.9, 0.3, 0.3), CF = {0.42, 4.02, 0.24, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Chain2", Shape = "Block", Size = Vector3.new(0.05, 1.13, 0.05), CF = {0.0, 4.635, 0.24, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "7d6a45", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Weight2", Shape = "Cylinder", Size = Vector3.new(0.9, 0.3, 0.3), CF = {0.0, 3.62, 0.24, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Chain3", Shape = "Block", Size = Vector3.new(0.05, 0.89, 0.05), CF = {-0.42, 4.755, 0.24, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "7d6a45", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Weight3", Shape = "Cylinder", Size = Vector3.new(0.9, 0.3, 0.3), CF = {-0.42, 3.86, 0.24, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PendulumRod", Shape = "Block", Size = Vector3.new(0.07, 2.57, 0.05), CF = {0.0, 3.835, -0.22, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c9962a", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PendulumBob", Shape = "Cylinder", Size = Vector3.new(0.08, 0.74, 0.74), CF = {0.0, 2.55, -0.22, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PendulumBobFace", Shape = "Cylinder", Size = Vector3.new(0.055, 0.46, 0.46), CF = {0.0, 2.55, -0.27, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "ffd76a", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Hood", Shape = "Block", Size = Vector3.new(2.4, 2.02, 1.4), CF = {0.0, 6.35, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "ColumnL", Shape = "Cylinder", Size = Vector3.new(1.78, 0.2, 0.2), CF = {1.1, 6.35, -0.74, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "ColumnBaseL", Shape = "Block", Size = Vector3.new(0.3, 0.14, 0.3), CF = {1.1, 5.46, -0.74, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ColumnCapL", Shape = "Block", Size = Vector3.new(0.3, 0.14, 0.3), CF = {1.1, 7.26, -0.74, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ColumnR", Shape = "Cylinder", Size = Vector3.new(1.78, 0.2, 0.2), CF = {-1.1, 6.35, -0.74, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "ColumnBaseR", Shape = "Block", Size = Vector3.new(0.3, 0.14, 0.3), CF = {-1.1, 5.46, -0.74, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ColumnCapR", Shape = "Block", Size = Vector3.new(0.3, 0.14, 0.3), CF = {-1.1, 7.26, -0.74, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Cornice", Shape = "Block", Size = Vector3.new(2.66, 0.16, 1.66), CF = {0.0, 7.43, -0.02, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DialPlate", Shape = "Block", Size = Vector3.new(1.8, 1.78, 0.08), CF = {0.0, 6.35, -0.73, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "2c3e7a", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "Spandrel1", Shape = "Ball", Size = Vector3.new(0.3, 0.3, 0.3), CF = {0.7566, 7.0066, -0.77, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Spandrel2", Shape = "Ball", Size = Vector3.new(0.3, 0.3, 0.3), CF = {-0.7566, 7.0066, -0.77, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Spandrel3", Shape = "Ball", Size = Vector3.new(0.3, 0.3, 0.3), CF = {-0.7566, 5.4934, -0.77, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Spandrel4", Shape = "Ball", Size = Vector3.new(0.3, 0.3, 0.3), CF = {0.7566, 5.4934, -0.77, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "DialBezel", Shape = "Cylinder", Size = Vector3.new(0.06, 1.63, 1.63), CF = {0.0, 6.25, -0.79, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "DialFace", Shape = "Cylinder", Size = Vector3.new(0.055, 1.45, 1.45), CF = {0.0, 6.25, -0.815, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark12", Shape = "Block", Size = Vector3.new(0.09, 0.2, 0.05), CF = {0.0, 6.85, -0.84, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark01", Shape = "Block", Size = Vector3.new(0.05, 0.12, 0.05), CF = {-0.31, 6.78694, -0.84, 0.86603, -0.5, 0.0, 0.5, 0.86603, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark02", Shape = "Block", Size = Vector3.new(0.05, 0.12, 0.05), CF = {-0.53694, 6.56, -0.84, 0.5, -0.86603, 0.0, 0.86603, 0.5, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark03", Shape = "Block", Size = Vector3.new(0.09, 0.2, 0.05), CF = {-0.6, 6.25, -0.84, 0.0, -1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark04", Shape = "Block", Size = Vector3.new(0.05, 0.12, 0.05), CF = {-0.53694, 5.94, -0.84, -0.5, -0.86603, 0.0, 0.86603, -0.5, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark05", Shape = "Block", Size = Vector3.new(0.05, 0.12, 0.05), CF = {-0.31, 5.71306, -0.84, -0.86603, -0.5, 0.0, 0.5, -0.86603, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark06", Shape = "Block", Size = Vector3.new(0.09, 0.2, 0.05), CF = {-0.0, 5.65, -0.84, -1.0, -0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark07", Shape = "Block", Size = Vector3.new(0.05, 0.12, 0.05), CF = {0.31, 5.71306, -0.84, -0.86603, 0.5, 0.0, -0.5, -0.86603, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark08", Shape = "Block", Size = Vector3.new(0.05, 0.12, 0.05), CF = {0.53694, 5.94, -0.84, -0.5, 0.86603, 0.0, -0.86603, -0.5, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark09", Shape = "Block", Size = Vector3.new(0.09, 0.2, 0.05), CF = {0.6, 6.25, -0.84, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark10", Shape = "Block", Size = Vector3.new(0.05, 0.12, 0.05), CF = {0.53694, 6.56, -0.84, 0.5, 0.86603, 0.0, -0.86603, 0.5, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mark11", Shape = "Block", Size = Vector3.new(0.05, 0.12, 0.05), CF = {0.31, 6.78694, -0.84, 0.86603, 0.5, 0.0, -0.5, 0.86603, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "HourHand", Shape = "Block", Size = Vector3.new(0.07, 0.5, 0.05), CF = {0.12287, 6.33604, -0.875, 0.57358, 0.81915, 0.0, -0.81915, 0.57358, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "HourHandTip", Shape = "Ellipsoid", Size = Vector3.new(0.17, 0.19, 0.05), CF = {0.27851, 6.44502, -0.875, 0.57358, 0.81915, 0.0, -0.81915, 0.57358, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "MinuteHand", Shape = "Block", Size = Vector3.new(0.05, 0.7, 0.05), CF = {-0.21651, 6.375, -0.93, 0.5, -0.86603, 0.0, 0.86603, 0.5, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "MinuteHandTip", Shape = "Ellipsoid", Size = Vector3.new(0.12, 0.16, 0.05), CF = {-0.46765, 6.52, -0.93, 0.5, -0.86603, 0.0, 0.86603, 0.5, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "HandCap", Shape = "Ball", Size = Vector3.new(0.14, 0.14, 0.14), CF = {0.0, 6.25, -0.96, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "CrownRim", Shape = "Cylinder", Size = Vector3.new(0.2, 1.86, 1.86), CF = {0.0, 7.5, -0.36, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "c9962a", Material = "Metal", T = 0.0, Collide = true},
	{Name = "CrownArch", Shape = "Cylinder", Size = Vector3.new(1.2, 1.72, 1.72), CF = {0.0, 7.5, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "MoonDisc", Shape = "Cylinder", Size = Vector3.new(0.055, 1.24, 1.24), CF = {0.0, 7.5, -0.625, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "2c3e7a", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "MoonSun", Shape = "Cylinder", Size = Vector3.new(0.055, 0.36, 0.36), CF = {0.0, 7.87, -0.66, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "ffb530", Material = "Neon", T = 0.0, Collide = false},
	{Name = "MoonMoon", Shape = "Cylinder", Size = Vector3.new(0.055, 0.32, 0.32), CF = {-0.0, 7.13, -0.66, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "fbf1c8", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "MoonStarA", Shape = "Ball", Size = Vector3.new(0.08, 0.08, 0.08), CF = {-0.28283, 7.16294, -0.655, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "fff6d0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "MoonStarB", Shape = "Ball", Size = Vector3.new(0.08, 0.08, 0.08), CF = {0.3078, 7.15815, -0.655, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "fff6d0", Material = "Neon", T = 0.0, Collide = false},
	{Name = "FinialTop", Shape = "Ball", Size = Vector3.new(0.2, 0.2, 0.2), CF = {0.0, 8.4, -0.1, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "FinialBaseL", Shape = "Block", Size = Vector3.new(0.26, 0.14, 0.26), CF = {1.1, 7.58, -0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "FinialL", Shape = "Ball", Size = Vector3.new(0.26, 0.26, 0.26), CF = {1.1, 7.76, -0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "FinialBaseR", Shape = "Block", Size = Vector3.new(0.26, 0.14, 0.26), CF = {-1.1, 7.58, -0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "FinialR", Shape = "Ball", Size = Vector3.new(0.26, 0.26, 0.26), CF = {-1.1, 7.76, -0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
}}
--[[
	GamingDesk headless test (tests/HomeOffice, `py gen.py` runs it after tests.luau), 2026-09-24: the PLAYABLE
	CUKE RUN. It replaces the self-playing desk's block that tests.luau had. Everything runs on a mock network
	(latency both ways, the framework's 12 actions / s budget): the server half, the gamer's client (the CukeRun GUI,
	driven through its bound keys by a planning bot that uses the module's own simulation), a spectator and a late
	joiner, each with its own copy of the client module.
	  1. the simulation: fair courses, determinism, late events rolling back, the score rate vs the server's limit
	  2. end to end: GUI, relays, sync, two hitches on the gamer's client only, the crash, PLAY AGAIN, click / touch,
	     EXIT mid-run with the end heard late (the replays go back to Fun_EndTick), death, cleanup
	  3. the desk itself at x1 yaw 37 and x1.3 yaw -120: the seat, the three screen slices, the attract loop, RGB,
	     the chair's swivel, a replay with no inputs, night, a move while seated, cleanup
]]

------------------------------------------------------------------ environment (Roblox services the desk uses)
local env = getfenv(1)
local realOs = os
MockClock = 1000
os = setmetatable({clock = function() return MockClock end}, {__index = realOs})
local timers = {}
task = {
	delay = function(t, fn, ...) local a = table.pack(...) table.insert(timers, {at = MockClock + t, fn = function() fn(table.unpack(a, 1, a.n)) end}) end,
	spawn = function(fn, ...) fn(...) end,
	defer = function(fn, ...) local a = table.pack(...) table.insert(timers, {at = MockClock, fn = function() fn(table.unpack(a, 1, a.n)) end}) end,
	wait = function() end,
}
local warns = {}
warn = function(...) local t = table.concat({...}, " ") table.insert(warns, t) print("WARN " .. t) end
rawset(Enum.ContextActionPriority.High, "Value", 3000)
local RS = {IsServer = function() return false end, RenderStepped = MockSignal(), Heartbeat = MockSignal()}
local UIS = {TouchEnabled = false, KeyboardEnabled = true, InputEnded = MockSignal(), InputChanged = MockSignal()}
local CAS = {bound = {}}
function CAS:BindActionAtPriority(name, fn, _, prio, ...) self.bound[name] = {fn = fn, prio = prio, keys = {...}} end
function CAS:UnbindAction(name) self.bound[name] = nil end
local baseGame = game
game = {GetService = function(_, n)
	if n == "RunService" then return RS end
	if n == "UserInputService" then return UIS end
	if n == "ContextActionService" then return CAS end
	return baseGame:GetService(n)
end}
local PlayersSvc = baseGame:GetService("Players")

------------------------------------------------------------------ loader
local function load(name)
	local fn, err = loadstring(SOURCES[name], name)
	assert(fn, err)
	setfenv(fn, env)
	return fn()
end
local loaded = {}
env.require = function(m)
	local name = type(m) == "table" and m.Name or tostring(m)
	if not loaded[name] then loaded[name] = load(name) end
	return loaded[name]
end
for _, n in ipairs({"FunBuildKit", "FunAssets"}) do
	local ms = Instance.new("ModuleScript")
	ms.Name = n
	ms.Parent = MockModules
end
local Kit = require({Name = "FunBuildKit"})
local FunAssets = require({Name = "FunAssets"})

local fails, checks = 0, 0
local function check(ok, msg)
	checks += 1
	if not ok then fails += 1 print("FAIL " .. msg) end
end
local function info(msg) print("  " .. msg) end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function vnear(a, b, eps) return (a - b).Magnitude <= (eps or 1e-6) end

local function DeepCopy(v)
	if type(v) ~= "table" or rawget(v, "_p") then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = DeepCopy(x) end
	return t
end

------------------------------------------------------------------ JSON + GUI dumps (gen.py renders them to screens/*.png)
local function JSON(v)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "0" end
		return string.format("%.4g", v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", string.byte(c)) end) .. '"'
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local out = {}
			for _, x in ipairs(v) do table.insert(out, JSON(x)) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local out = {}
		for k, x in pairs(v) do table.insert(out, JSON(tostring(k)) .. ":" .. JSON(x)) end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

--.. walk GUI objects: UDim2 scale + offset, AnchorPoint, gradients (mean colour), border strokes, texts
local function Walk(inst, ax, ay, pw, ph, items)
	local order = {}
	for i, k in ipairs(inst:GetChildren()) do
		if k.ClassName == "Frame" or k.ClassName == "TextLabel" or k.ClassName == "TextButton" then table.insert(order, {k, i}) end
	end
	table.sort(order, function(a, b)
		if (a[1].ZIndex or 1) ~= (b[1].ZIndex or 1) then return (a[1].ZIndex or 1) < (b[1].ZIndex or 1) end
		return a[2] < b[2]
	end)
	for _, o in ipairs(order) do
		local k = o[1]
		if k.Visible ~= false then
			local sw = k.Size.X.Scale * pw + k.Size.X.Offset
			local sh = k.Size.Y.Scale * ph + k.Size.Y.Offset
			local ap = k.AnchorPoint or Vector2.new(0, 0)
			local x = ax + k.Position.X.Scale * pw + k.Position.X.Offset - ap.X * sw
			local y = ay + k.Position.Y.Scale * ph + k.Position.Y.Offset - ap.Y * sh
			local corner = k:FindFirstChildOfClass("UICorner")
			local r = corner and (corner.CornerRadius.Scale * math.min(sw, sh) + corner.CornerRadius.Offset) or 0
			local item = {x = x, y = y, w = sw, h = sh, r = r}
			if (k.BackgroundTransparency or 0) < 1 then
				local c = k.BackgroundColor3
				local g = k:FindFirstChildOfClass("UIGradient")
				if g then
					local a, b = g.Color.Keypoints[1].Value, g.Color.Keypoints[#g.Color.Keypoints].Value
					c = Color3.new((a.R + b.R) / 2, (a.G + b.G) / 2, (a.B + b.B) / 2)
				end
				item.c = {c.R, c.G, c.B}
				item.bt = k.BackgroundTransparency or 0
			end
			for _, s in ipairs(k:GetChildren()) do
				if s.ClassName == "UIStroke" and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
					item.sc = {s.Color.R, s.Color.G, s.Color.B}
					item.st = s.Thickness
				end
			end
			if item.c or item.sc then table.insert(items, item) end
			if k.ClassName ~= "Frame" and (k.Text or "") ~= "" then
				local c = k.TextColor3 or Color3.new(1, 1, 1)
				table.insert(items, {x = x, y = y, w = sw, h = sh, text = k.Text, tc = {c.R, c.G, c.B}, tt = k.TextTransparency or 0,
					ts = (not k.TextScaled) and k.TextSize or nil, align = tostring(k.TextXAlignment or "Center"):match("([%a]+)$")})
			end
			if k.ClipsDescendants then
				local sub = {}
				Walk(k, x, y, sw, sh, sub)
				for _, it in ipairs(sub) do
					--.. crude clip: drop what lies wholly outside
					if it.x < x + sw and it.x + it.w > x and it.y < y + sh and it.y + it.h > y then table.insert(items, it) end
				end
			else
				Walk(k, x, y, sw, sh, items)
			end
		end
	end
end

local function DumpGui(name, panel)
	local items = {}
	local w, h = panel.Size.X.Offset, panel.Size.Y.Offset
	local holder = {GetChildren = function() return {panel} end}
	local pos, ap = panel.Position, panel.AnchorPoint
	rawget(panel, "_p").Position = UDim2.fromOffset(0, 0)
	rawget(panel, "_p").AnchorPoint = Vector2.new(0, 0)
	Walk(holder, 0, 0, w, h, items)
	rawget(panel, "_p").Position = pos
	rawget(panel, "_p").AnchorPoint = ap
	print("GUIDUMP " .. name .. " " .. JSON({{w = w, h = h, items = items}}))
end

local function DumpMonitor(name, cctx)
	local out = {}
	local list = {}
	for _, inst in ipairs(cctx.insts) do
		if inst.ClassName == "Part" and inst.Name:sub(1, 16) == "GamingDeskScreen" then table.insert(list, inst) end
	end
	table.sort(list, function(a, b) return a.GameScreen.Scene.Position.X.Offset > b.GameScreen.Scene.Position.X.Offset end)
	for _, part in ipairs(list) do
		local items = {}
		local w, h = math.floor(part.Size.X * 90 + 0.5), math.floor(part.Size.Y * 90)
		Walk(part.GameScreen, 0, 0, w, h, items)
		table.insert(out, {w = w, h = h, items = items})
	end
	print("GUIDUMP " .. name .. " " .. JSON(out))
end

------------------------------------------------------------------ the desk, placed (BuildService: scale about the bbox centre)
local function MakePlaced(key, scale, placeCF)
	local data = MODELS[key]
	local model = Instance.new("Model")
	model.Name = key
	local centre = (data.Min + data.Max) / 2
	local parts = {}
	for _, pd in ipairs(data.Parts) do
		local c = pd.CF
		local cf = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		local p = Instance.new("Part")
		p.Name = pd.Name
		p.Size = pd.Size * scale
		p.CFrame = CFrame.new(centre + (cf.Position - centre) * scale) * cf.Rotation
		p.Color = Color3.fromHex(pd.Color)
		p.Transparency = pd.T
		p.CanCollide = pd.Collide
		p.Anchored = true
		p.Parent = model
		table.insert(parts, p)
	end
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (data.Max - data.Min) * scale
	hitbox.CFrame = CFrame.new(centre)
	hitbox.Transparency = 1
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	for k, v in pairs(data.Attrs) do model:SetAttribute(k, v) end
	model:SetAttribute("AuthoredCentre", centre)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("BuildKey", key)
	local delta = placeCF * hitbox.CFrame:Inverse()
	for _, p in ipairs(parts) do p.CFrame = delta * p.CFrame end
	hitbox.CFrame = delta * hitbox.CFrame
	model.Parent = workspace
	return model
end

--.. every part (and the hitbox) moved by `delta` (a build MOVE)
local function MoveBuild(model, delta)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
	end
end

------------------------------------------------------------------ network (latency both ways, the framework's 12 actions / s budget)
local LAT = 0.08
local net = {}
local function Deliver(fn, lat) table.insert(net, {at = MockNow + (lat or LAT), fn = fn}) end
local clients = {}
local server = {mod = nil, ctx = nil, model = nil, dropped = 0, budget = {}, actions = {}}
local function ClientEvent(c, action, payload)
	if not c.alive or type(c.mod.OnEvent) ~= "function" then return end
	local ok, err = pcall(c.mod.OnEvent, server.model, action, payload, c.ctx)
	check(ok, "OnEvent " .. tostring(action) .. ": " .. tostring(err))
end
local function ServerAction(player, action, payload)
	local b = server.budget[player]
	if not b or MockClock - b.t >= 1 then b = {t = MockClock, n = 0} server.budget[player] = b end
	b.n += 1
	server.actions[action] = (server.actions[action] or 0) + 1
	if b.n > 12 then server.dropped += 1 return end
	local handler = server.mod.Actions[action]
	if not handler then return end
	local ok, err = pcall(handler, server.model, player, payload, server.ctx)
	check(ok, "server action " .. action .. ": " .. tostring(err))
end

local function MakeServerCtx(model)
	local ctx = {Model = model, Key = "GamingDesk", Base = "GamingDesk", Scale = Kit.Scale(model), _alive = true, everys = {}, seats = {}}
	function ctx:Alive() return self._alive end
	function ctx:Connect(sig, fn) return sig:Connect(fn) end
	function ctx:Add(i) return i end
	function ctx:OnCleanup() end
	function ctx:SetState(k, v) model:SetAttribute("Fun_" .. k, v) end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:Fire(action, payload)
		local p = DeepCopy(payload)
		for _, c in ipairs(clients) do
			local cc = c
			Deliver(function() ClientEvent(cc, action, DeepCopy(p)) end)
		end
	end
	function ctx:FireTo(player, action, payload)
		local p = DeepCopy(payload)
		for _, c in ipairs(clients) do
			if c.player == player then
				local cc = c
				Deliver(function() ClientEvent(cc, action, p) end)
			end
		end
	end
	function ctx:Every(sec, fn) table.insert(self.everys, {sec = sec, fn = fn, next = MockClock + sec}) end
	function ctx:Heartbeat() end
	function ctx:HumanoidOf(player)
		local ch = player.Character
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then return h, ch:FindFirstChild("HumanoidRootPart") end
		return nil
	end
	function ctx:Near() return true end
	function ctx:IsOwner() return true end
	function ctx:Seat(cframe, opts)
		local seat = Instance.new("Seat")
		seat.Name = opts.Name or "FunSeat"
		seat.Size = opts.Size or Vector3.new(2, 0.4, 2)
		seat.CFrame = cframe
		seat.Anchored = true
		table.insert(self.seats, {Seat = seat, Opts = opts})
		return seat
	end
	return ctx
end

local function MakeClientCtx(model, mod, player, hum, root)
	local ctx = {Model = model, Key = "GamingDesk", Base = "GamingDesk", Scale = Kit.Scale(model), Player = player, _alive = true,
		steps = {}, insts = {}, cleanups = {}, StepRange = mod.StepRange or 180}
	function ctx:Alive() return self._alive end
	function ctx:Connect(sig, fn) return sig:Connect(fn) end
	function ctx:Add(i) table.insert(self.insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self.cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn)
		local name = "Fun_" .. k
		model:GetAttributeChangedSignal(name):Connect(function() fn(model:GetAttribute(name)) end)
		fn(model:GetAttribute(name))
	end
	function ctx:Send(action, payload)
		local p = DeepCopy(payload)
		Deliver(function() ServerAction(player, action, p) end)
	end
	function ctx:CameraDistance() return 12 end
	function ctx:Step(fn) table.insert(self.steps, fn) end
	function ctx:Every() end
	function ctx:Sound(parent, id, props) local s = Kit.MakeSound(id, props) s.Parent = parent table.insert(self.insts, s) return s end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = workspace.CurrentCamera end
		table.insert(self.insts, p)
		return p
	end
	function ctx:LocalCharacter()
		if hum.Health > 0 then return hum, root, player.Character end
		return nil
	end
	function ctx:Near() return true end
	function ctx:IsOwner() return true end
	return ctx
end

local function MakePlayer(id, name)
	local p = Instance.new("Player")
	p.Name = name
	p.UserId = id
	p.DisplayName = name
	local gui = Instance.new("Folder")
	gui.Name = "PlayerGui"
	gui.Parent = p
	local char = Instance.new("Model")
	char.Name = name
	char.Parent = workspace
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	p.Character = char
	table.insert(MockPlayers, p)
	return p, hum, root
end

--.. a client: its own copy of the client module (LocalPlayer is read at load)
local function AddClient(model, player, hum, root)
	rawget(PlayersSvc, "_p").LocalPlayer = player
	local mod = load("C_GamingDesk")
	local ctx = MakeClientCtx(model, mod, player, hum, root)
	local c = {mod = mod, ctx = ctx, player = player, hum = hum, alive = true}
	table.insert(clients, c)
	local ok, res = pcall(mod.Client, model, ctx)
	check(ok, "Client() errored: " .. tostring(res))
	if ok and type(res) == "function" then table.insert(ctx.cleanups, res) end
	return c
end

--.. sit down / get up (PhysicsTick below unseats a humanoid whose Sit went false, like the engine does)
local function Sit(seat, hum)
	local weld = Instance.new("Weld")
	weld.Name = "SeatWeld"
	weld.Parent = seat
	hum.SeatPart, hum.Sit = seat, true
	seat.Occupant = hum
end

------------------------------------------------------------------ the frame loop
local BotHook = nil
local PreStep = nil                  -- after the network delivered, before any client runs
local Hitch = {left = 0, dt = 0}     -- the GAMER's client frozen (a hitch): no GUI frame, no Step, no bot
local function PhysicsTick()
	for _, rec in ipairs(server.ctx and server.ctx.seats or {}) do
		local seat = rec.Seat
		local hum = seat.Occupant
		if hum and (not seat:FindFirstChild("SeatWeld") or hum.Jump == true or hum.Sit == false) then
			local w = seat:FindFirstChild("SeatWeld")
			if w then w:Destroy() end
			hum.SeatPart = nil
			hum.Sit = false
			hum.Jump = false
			seat.Occupant = nil
		end
	end
end
local function Frame(dt)
	dt = dt or 1 / 60
	MockNow += dt
	MockClock += dt
	local due = {}
	local i = 1
	while i <= #net do
		if net[i].at <= MockNow then table.insert(due, table.remove(net, i)) else i += 1 end
	end
	for _, m in ipairs(due) do m.fn() end
	i = 1
	while i <= #timers do
		if timers[i].at <= MockClock then local t = table.remove(timers, i) t.fn() else i += 1 end
	end
	if server.ctx then
		for _, e in ipairs(server.ctx.everys) do
			if MockClock >= e.next then e.next += e.sec e.fn() end
		end
	end
	PhysicsTick()
	if PreStep then PreStep() end
	if Hitch.left <= 0 and BotHook then BotHook() end -- (the bot may start a hitch)
	local frozen = Hitch.left > 0
	if frozen then
		Hitch.left -= dt
		Hitch.dt += dt
	else
		RS.RenderStepped:Fire(Hitch.dt + dt) -- the frame after a hitch is as long as the hitch
		Hitch.dt = 0
	end
	for _, c in ipairs(clients) do
		if c.alive and not (frozen and c.gamer) then
			for _, fn in ipairs(c.ctx.steps) do
				local ok, err = pcall(fn, dt, MockNow)
				if not ok then check(false, "Step errored: " .. tostring(err)) end
			end
		end
	end
end
local function Run(seconds, dt)
	dt = dt or 1 / 60
	for _ = 1, math.floor(seconds / dt + 0.5) do Frame(dt) end
end

--.. a fresh world for the next section (the earlier clients are stopped by then)
local function ResetWorld()
	for _, c in ipairs(clients) do
		c.alive = false
		c.ctx._alive = false
	end
	table.clear(clients)
	table.clear(net)
	table.clear(timers)
	server.ctx, server.model = nil, nil
	server.budget = {}
	BotHook, PreStep = nil, nil
	Hitch.left, Hitch.dt = 0, 0
	LAT = 0.08
end

--.. sounds: count plays by SoundId
local plays = {}
local function WrapSounds(list)
	for _, inst in ipairs(list) do
		if inst.ClassName == "Sound" and not rawget(inst, "_wrapped") then
			rawset(inst, "_wrapped", true)
			local id = inst.SoundId
			rawset(inst, "Play", function(self)
				plays[id] = (plays[id] or 0) + 1
				rawget(self, "_p").IsPlaying = true
			end)
		end
	end
end
local function Plays(name) return plays[FunAssets.Sfx[name]] or 0 end

------------------------------------------------------------------ a planning bot (uses the module's own simulation)
local SimMod = load("C_GamingDesk")
local Sim = SimMod.Sim
local K = Enum.KeyCode

--.. simulate a copy of the run with extra events until x passes untilX and the hero has landed
local function Simulate(run, extraTicks, extraKinds, untilX)
	local s0 = run.Sim
	local c = Sim.NewSim()
	Sim.Restore(c, Sim.Snapshot(s0))
	c.Got = {}
	local ticks, kinds = {}, {}
	for i = s0.Ev, #run.Ticks do table.insert(ticks, run.Ticks[i]) table.insert(kinds, run.Kinds[i]) end
	for i = 1, #extraTicks do table.insert(ticks, extraTicks[i]) table.insert(kinds, extraKinds[i]) end
	c.Ev = 1
	local n = 0
	while (c.X < untilX or not c.Ground) and not c.Dead and n < 4000 do
		Sim.StepSim(c, run.Course, ticks, kinds)
		n += 1
	end
	return not c.Dead, c
end

--.. decide this frame: returns a list of "jump" / "jumpUp" / "duck" / "duckUp"
local function BotDecide(bot, run)
	local s = run.Sim
	local out = {}
	local nextTick = s.N + 1
	if bot.jumpHeld and nextTick >= bot.releaseAt then
		table.insert(out, "jumpUp")
		bot.jumpHeld = false
	end
	if bot.duckHeld and s.Obs > bot.duckObs then
		table.insert(out, "duckUp")
		bot.duckHeld = false
	end
	if s.X > (bot.stopAtX or math.huge) or bot.jumpHeld or bot.duckHeld then return out end
	local course = run.Course
	Sim.Extend(course, s.X + 200)
	local j = s.Obs
	local kind = course.Kind[j]
	local spec = Sim.Kinds[kind]
	local ox = course.X[j]
	if kind == "drone" then
		if ox - spec.Half - (s.X + Sim.HeroHalf) < 3 + Sim.Speed(s.X) * 0.04 then
			table.insert(out, "duck")
			bot.duckHeld, bot.duckObs = true, j
		end
		return out
	end
	if not s.Ground or ox - s.X > 70 then return out end
	local untilX = ox + spec.Half + Sim.HeroHalf + 0.5
	for _, h in ipairs(bot.holds or {1, 6, 10, 14, 24}) do
		if Simulate(run, {nextTick, nextTick + h + 1}, {0, 1}, untilX) and Simulate(run, {nextTick, nextTick + h + 2}, {0, 1}, untilX) then
			table.insert(out, "jump")
			bot.jumpHeld, bot.releaseAt = true, nextTick + h + 1
			bot.lastHold = h
			return out
		end
	end
	return out
end

local CODES = {jump = 0, jumpUp = 1, duck = 2, duckUp = 3}

--.. sim only: a bot plays seed for up to `seconds` at 60 fps (2 ticks a frame), like the GUI does
local function PlaySim(seed, seconds, bot)
	local run = Sim.NewRun(seed)
	bot = bot or {}
	local frames = math.floor(seconds * 60)
	for f = 1, frames do
		for _, k in ipairs(BotDecide(bot, run)) do
			table.insert(run.Ticks, run.Sim.N + 1)
			table.insert(run.Kinds, CODES[k])
		end
		Sim.Advance(run, f * 2, 900, nil)
		if run.Sim.Dead then break end
	end
	return run
end

------------------------------------------------------------------ 1. the simulation: fair courses, determinism, score rate
do
	print("== simulation")
	local survived, total, bestRate, deaths = 0, 0, 0, {}
	local drones, doubles, coinsSeen = 0, 0, 0
	for seed = 1, 24 do
		local run = PlaySim(seed * 7919, 150)
		total += 1
		local s = run.Sim
		local secs = s.N / 120
		bestRate = math.max(bestRate, Sim.Score(s) / math.max(secs, 1))
		if not s.Dead then
			survived += 1
		else
			local j = s.Obs
			table.insert(deaths, ("seed %d died at %.1fs x=%.0f v=%.1f obstacle %d %s (prev %s gap %.1f)"):format(seed * 7919, secs, s.X, Sim.Speed(s.X), j,
				tostring(run.Course.Kind[j]), tostring(run.Course.Kind[j - 1]), run.Course.X[j] - (run.Course.X[j - 1] or 0)))
		end
		for i = 1, run.Course.N do
			if run.Course.Kind[i] == "drone" then drones += 1 elseif run.Course.Kind[i] == "double" then doubles += 1 end
			if run.Course.CoinX[i] then coinsSeen += 1 end
		end
		check(Sim.Score(s) <= secs * 80 + 150, ("seed %d: score %d within the server's plausibility (%.1f s)"):format(seed, Sim.Score(s), secs))
	end
	for _, d in ipairs(deaths) do print("  " .. d) end
	info(("bot survived %d / %d runs of 150 s; drones %d, doubles %d, coins %d; best points/s %.1f"):format(survived, total, drones, doubles, coinsSeen, bestRate))
	check(survived == total, "a planning bot survives every 150 s course (gaps always jumpable)")

	--.. determinism: the same seed + events -> the same bits; a replay fed in pieces (with rollbacks) ends identical
	local a = PlaySim(4242, 60)
	local b = Sim.NewRun(4242)
	for i = 1, #a.Ticks do table.insert(b.Ticks, a.Ticks[i]) table.insert(b.Kinds, a.Kinds[i]) end
	Sim.Advance(b, a.Sim.N, 100000, nil)
	check(b.Sim.X == a.Sim.X and b.Sim.Y == a.Sim.Y and b.Sim.Coins == a.Sim.Coins and b.Sim.Dead == a.Sim.Dead, "replay from the full list is bit-identical")
	local r = Sim.NewRun(4242)
	local fed = 0
	local rng = Random.new(5)
	local target = 0
	while target < a.Sim.N do
		target = math.min(a.Sim.N, target + 4)
		--.. events arrive late and in bunches: up to 40 ticks after they happened
		while fed < #a.Ticks and a.Ticks[fed + 1] <= target - rng:NextInteger(0, 40) do
			fed += 1
			Sim.AddCode(r, a.Ticks[fed] * 4 + a.Kinds[fed])
		end
		Sim.Advance(r, target, 900, nil)
	end
	while fed < #a.Ticks do fed += 1 Sim.AddCode(r, a.Ticks[fed] * 4 + a.Kinds[fed]) end
	Sim.Advance(r, a.Sim.N, 100000, nil)
	check(r.Sim.X == a.Sim.X and r.Sim.Y == a.Sim.Y and r.Sim.Coins == a.Sim.Coins and r.Sim.N == a.Sim.N, "late events roll back and the replay ends identical")
	--.. no input: the hero hits the first obstacle ~2.5 s in (MIN_SECONDS 2 on the server)
	local idle = Sim.NewRun(99)
	Sim.Advance(idle, 120 * 30, 100000, nil)
	check(idle.Sim.Dead and idle.Sim.DeadTick / 120 > 2, ("no input crashes at the first obstacle after 2 s (%.2f s)"):format(idle.Sim.DeadTick / 120))
	--.. a tap is lower than a held jump
	local function Peak(hold)
		local run = Sim.NewRun(1)
		table.insert(run.Ticks, 10) table.insert(run.Kinds, 0)
		table.insert(run.Ticks, 10 + hold) table.insert(run.Kinds, 1)
		local peak = 0
		for t = 1, 100 do Sim.Advance(run, t, 10, nil) peak = math.max(peak, run.Sim.Y) end
		return peak
	end
	local tap, full = Peak(1), Peak(60)
	info(("jump peaks: tap %.1f px, held %.1f px"):format(tap, full))
	check(tap > 7 and tap < 9.5 and full > 14 and full < 16.5, "tap ~8 px, held ~15 px")
end

------------------------------------------------------------------ 2. end to end: the server, the gamer's GUI, a spectator, a late joiner
local Begin, End = Enum.UserInputState.Begin, Enum.UserInputState.End
local function KeyInput(key, state)
	local b = CAS.bound.CukeRunControls
	if not b then return false end
	b.fn("CukeRunControls", state, {KeyCode = key, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.new(0, 0, 0)})
	return true
end
local function MonitorText(c, name)
	for _, inst in ipairs(c.ctx.insts) do
		if inst.ClassName == "Part" and inst.Name == "GamingDeskScreenC" then
			local l = inst.GameScreen.Scene:FindFirstChild(name)
			return l and l.Text
		end
	end
	return nil
end
local function Same(a, b) return a.X == b.X and a.Y == b.Y and a.Coins == b.Coins and a.Dead == b.Dead end

do
	print("== end to end")
	server.mod = load("S_GamingDesk")
	local model = MakePlaced("GamingDesk", 1, CFrame.new(40, 3, -20) * CFrame.Angles(0, math.rad(25), 0))
	server.model = model
	server.ctx = MakeServerCtx(model)
	local ok, err = pcall(server.mod.Server, model, server.ctx)
	check(ok, "Server(): " .. tostring(err))
	local seat = server.ctx.seats[1].Seat
	check(seat.Name == "GamingDeskSeat" and server.ctx.seats[1].Opts.Prompt == "Game", "the Game seat")
	local gp, gh, groot = MakePlayer(101, "CukeMaster9000")
	local sp, sh, sroot = MakePlayer(202, "Watcher")
	local lp, lh, lroot = MakePlayer(303, "LateJoiner")
	local gamer = AddClient(model, gp, gh, groot)
	gamer.gamer = true
	local spect = AddClient(model, sp, sh, sroot)
	WrapSounds(gamer.ctx.insts)
	WrapSounds(spect.ctx.insts)
	Run(1)
	check(MonitorText(spect, "Big") == "CUKE RUN", "attract title (" .. tostring(MonitorText(spect, "Big")) .. ")")
	DumpMonitor("desk_attract", spect.ctx)

	--.. sit down
	Sit(seat, gh)
	local seed1 = model:GetAttribute("Fun_Seed")
	check(model:GetAttribute("Fun_Player") == 101 and (seed1 or 0) ~= 0, "server: Player + Seed on sit")
	Run(0.05)
	local g = gamer.ctx.Desk.Game
	check(g ~= nil and gp.PlayerGui:FindFirstChild("CukeRun") ~= nil, "the gamer's CukeRun GUI opened")
	check(spect.ctx.Desk.Game == nil and sp.PlayerGui:FindFirstChild("CukeRun") == nil, "no GUI for the spectator")
	local b = CAS.bound.CukeRunControls
	check(b ~= nil and b.prio > 3000 and table.find(b.keys, K.Space) ~= nil and table.find(b.keys, K.ButtonA) ~= nil, "Space / pad A sunk above the PlayerModule")
	if not g then print("FAIL no game, stopping") return end
	WrapSounds(g.ui.Gui:GetChildren())
	--.. Space during READY: sunk, no event, still seated
	KeyInput(K.Space, Begin)
	KeyInput(K.Space, End)
	Run(0.5)
	check(g.state == "ready" and #g.run.Ticks == 0 and seat.Occupant == gh, "READY: Space does nothing (" .. g.state .. ")")
	check(g.ui.Count.Text == "READY?", "READY? on the GUI (" .. g.ui.Count.Text .. ")")
	check(MonitorText(spect, "Big") == "READY?" and MonitorText(spect, "Name") == "P1 CUKEMASTER90", "READY? + P1 name on the monitor")
	DumpGui("gui_ready", g.ui.Panel)
	DumpMonitor("desk_ready", spect.ctx)
	Run(1.1)
	check(g.state == "play", "GO -> play")

	--.. the bot plays; the gamer's sim is recorded to compare the spectators with. Two hitches on the gamer's client
	--.. ONLY (its GUI, Step and bot frozen while the server and the spectators run on): 0.6 s from ~26 s and 1.0 s
	--.. from ~31 s, each started where the next obstacle is far enough away to survive it
	local bot = {}
	local rec = {}
	local seedNow = seed1
	local droneDumped = false
	local hitchArm, hitches = nil, {}
	BotHook = function()
		local game_ = gamer.ctx.Desk.Game
		if not game_ or not game_.run or game_.state ~= "play" or game_.run.Sim.Dead then return end
		if game_.run.Seed ~= seedNow then seedNow, bot, rec = game_.run.Seed, {}, {} end
		local s = game_.run.Sim
		rec[s.N] = {X = s.X, Y = s.Y, Coins = s.Coins, Dead = s.Dead}
		if hitchArm and s.Ground and not bot.jumpHeld and not bot.duckHeld then
			local course = game_.run.Course
			Sim.Extend(course, s.X + 400)
			local j = s.Obs
			local clear = course.X[j] - Sim.Kinds[course.Kind[j]].Half - (s.X + Sim.HeroHalf)
			if clear > Sim.Speed(s.X) * (hitchArm + 0.4) + 6 then
				Hitch.left = hitchArm
				table.insert(hitches, {At = s.N, Len = hitchArm, Since = game_.since})
				hitchArm = nil
				return
			end
		end
		for _, k in ipairs(BotDecide(bot, game_.run)) do
			if k == "jump" then KeyInput(K.Space, Begin)
			elseif k == "jumpUp" then KeyInput(K.Space, End)
			elseif k == "duck" then KeyInput(K.S, Begin)
			else KeyInput(K.S, End) end
		end
		if not droneDumped and s.DuckHeld and s.Ground then
			droneDumped = true
			DumpGui("gui_duck", game_.ui.Panel)
		end
	end
	--.. rollbacks on the spectator: a relayed input that reached it after its replay passed that tick
	local rollbacks, lastDirty = 0, nil
	PreStep = function()
		local r = spect.ctx.Desk.Run
		local d = r and r.Dirty
		if d and d ~= lastDirty then rollbacks += 1 end
		lastDirty = d
	end
	local matched, compared, afterMatched, afterCompared, falseDead = 0, 0, 0, 0, 0
	local late = nil
	for f = 1, 60 * 45 do
		Frame()
		local r = spect.ctx.Desk.Run
		if r and r.Seed == seedNow and rec[r.Sim.N] then
			compared += 1
			local same = Same(r.Sim, rec[r.Sim.N])
			if same then matched += 1 end
			if hitches[1] and r.Sim.N > hitches[1].At then
				afterCompared += 1
				if same then afterMatched += 1 end
			end
		end
		if r and r.Seed == seedNow and r.Sim.Dead and not g.run.Sim.Dead then falseDead += 1 end
		if f == 60 * 20 then
			late = AddClient(model, lp, lh, lroot)
			info("late joiner added at 20 s")
		end
		if f == 60 * 12 then
			DumpMonitor("desk_run", spect.ctx)
			DumpGui("gui_run", g.ui.Panel)
		end
		if f == 60 * 26 then hitchArm = 0.6 end
		if f == 60 * 31 then hitchArm = 1.0 end
	end
	PreStep = nil
	local gs = g.run.Sim
	info(("after 45 s: x=%.0f v=%.1f score %d coins %d, events %d, spectator matched %d / %d sampled ticks"):format(gs.X, Sim.Speed(gs.X), Sim.Score(gs), gs.Coins, #g.run.Ticks, matched, compared))
	check(not gs.Dead and gs.X > 1500, "the bot is still running after 45 s")
	check(compared > 1000 and matched == compared, "the spectator's monitor replays the actual run")
	--.. the hitches: the gamer's run follows the server clock through them (it skips, it never falls behind), so
	--.. the spectator (0.3 s behind real time) gets every later input in time: no rollback, no false crash
	local hitchText = {}
	for _, h in ipairs(hitches) do table.insert(hitchText, ("%.1f s at %.1f s"):format(h.Len, h.At / 120)) end
	info(("gamer-only hitches: %s; after them the spectator matched %d / %d; rollbacks %d, false-crash frames %d"):format(
		table.concat(hitchText, ", "), afterMatched, afterCompared, rollbacks, falseDead))
	check(#hitches == 2, "both hitches happened (" .. #hitches .. ")")
	check(afterCompared > 300 and afterMatched == afterCompared, "after a hitch the spectator still replays the actual run")
	check(rollbacks == 0, "no input reached the spectator after its replay passed it (" .. rollbacks .. " rollbacks)")
	check(falseDead == 0, "the spectator never showed a crash the gamer did not have (" .. falseDead .. " frames)")
	check(near(g.clock, MockNow - g.since - 1.6, 1e-9), ("the gamer's clock is the server clock after the hitches (%.3f vs %.3f)"):format(g.clock, MockNow - g.since - 1.6))
	check(math.abs(gs.N - math.floor((MockNow - g.since - 1.6) * 120)) <= 1, "the gamer's sim is not behind the server clock")
	check(MonitorText(spect, "Name") == "P1 CUKEMASTER90", "monitor name (" .. tostring(MonitorText(spect, "Name")) .. ")")
	check((MonitorText(spect, "Score") or ""):match("^SCORE %d+$") ~= nil, "monitor score")
	check(Plays("ArcadeBlip") > 5, "jump blips in the GUI (" .. Plays("ArcadeBlip") .. ")")
	check(Plays("Click") > 5, "keyboard clacks (" .. Plays("Click") .. ")")
	check(Plays("Coin") > 3, "coin sounds (" .. Plays("Coin") .. ")")
	check(droneDumped, "ducked under a drone")
	local lr = late and late.ctx.Desk.Run
	check(lr ~= nil and lr.Complete and #lr.Ticks >= #g.run.Ticks - 3 and #lr.Ticks <= #server.ctx.Desk.Codes, "the late joiner synced the list (" .. tostring(lr and #lr.Ticks) .. " / " .. #g.run.Ticks .. ", server " .. #server.ctx.Desk.Codes .. ")")

	--.. crash on purpose
	bot.stopAtX = gs.X + 5
	Run(3)
	check(gs.Dead and g.state == "dead", "crashed")
	local score = Sim.Score(gs)
	check(model:GetAttribute("Fun_Final") == score and model:GetAttribute("Fun_Best") == score, ("server: Final / Best = %d (%s / %s)"):format(score, tostring(model:GetAttribute("Fun_Final")), tostring(model:GetAttribute("Fun_Best"))))
	check((model:GetAttribute("Fun_Ended") or 0) > model:GetAttribute("Fun_Since"), "server: run ended")
	check(model:GetAttribute("Fun_EndTick") == gs.DeadTick, ("server: EndTick = the crash tick (%s vs %d)"):format(tostring(model:GetAttribute("Fun_EndTick")), gs.DeadTick))
	check(Plays("Thump") >= 1, "crash thump")
	local sr = spect.ctx.Desk.Run
	check(sr.Sim.Dead and sr.Sim.DeadTick == gs.DeadTick and Sim.Score(sr.Sim) == score, ("the spectator saw the same crash (tick %s vs %d)"):format(tostring(sr.Sim.DeadTick), gs.DeadTick))
	check(lr ~= nil and lr.Sim.Dead and lr.Sim.DeadTick == gs.DeadTick, "the late joiner saw the same crash")
	check(MonitorText(spect, "Big") == "GAME OVER", "monitor GAME OVER (" .. tostring(MonitorText(spect, "Big")) .. ")")
	check(g.ui.Card.Visible and g.ui.CardScore.Text == tostring(score), "the GUI card shows the score")
	check(g.ui.CardTag.Text:find("NEW DESK RECORD") ~= nil, "new desk record tag (" .. g.ui.CardTag.Text .. ")")
	DumpGui("gui_over", g.ui.Panel)
	DumpMonitor("desk_over", spect.ctx)
	Run(3)
	check(MonitorText(spect, "Big") == "GAME OVER" and seat.Occupant == gh, "still seated: GAME OVER stays on the monitor")

	--.. PLAY AGAIN (Space on the card)
	KeyInput(K.Space, Begin)
	KeyInput(K.Space, End)
	Run(0.5)
	local seed2 = model:GetAttribute("Fun_Seed")
	check(seed2 ~= seed1 and g.run.Seed == seed2 and g.state == "ready" and not g.ui.Card.Visible, "PLAY AGAIN: a new run")
	check(model:GetAttribute("Fun_EndTick") == 0, "a new run clears EndTick")
	Run(10)
	check(g.state == "play" and not g.run.Sim.Dead, "second run going")
	--.. a click on the game view = jump press, the mouse release = jump release (one each)
	local before = #g.run.Ticks
	g.ui.Tap.InputBegan:Fire({UserInputType = Enum.UserInputType.MouseButton1})
	g.ui.Jump.InputBegan:Fire({UserInputType = Enum.UserInputType.MouseButton1}) -- same mouse: no second press
	check(#g.run.Ticks == before + 1 and g.run.Kinds[#g.run.Kinds] == 0, "click on the view = one jump press")
	UIS.InputEnded:Fire({UserInputType = Enum.UserInputType.MouseButton1})
	check(#g.run.Ticks == before + 2 and g.run.Kinds[#g.run.Kinds] == 1, "mouse up = jump release")
	local touch = {UserInputType = Enum.UserInputType.Touch}
	g.ui.Duck.InputBegan:Fire(touch)
	UIS.InputEnded:Fire(touch)
	check(#g.run.Ticks == before + 4 and g.run.Kinds[#g.run.Kinds - 1] == 2 and g.run.Kinds[#g.run.Kinds] == 3, "touch DUCK press / release")
	Run(0.4)
	check(g.state == "play" and not g.run.Sim.Dead, "still running after the extra inputs")
	local forfeit = Sim.Score(g.run.Sim)
	local exitN, exitCoins = g.run.Sim.N, g.run.Sim.Coins
	local run2 = g.run

	--.. EXIT mid-run (Backspace) while the network is slow (0.45 s each way): the score so far counts, they stand up,
	--.. everything unbinds. The spectator's replay (0.3 s behind) runs past the exit before the "Over" is heard, then
	--.. goes back to the run's own last tick (Fun_EndTick): no crash / coins after the exit
	LAT = 0.45
	KeyInput(K.Backspace, Begin)
	local specMax, lateMax = 0, 0
	for _ = 1, 60 do
		Frame()
		local r1, r2 = spect.ctx.Desk.Run, late.ctx.Desk.Run
		if r1 and r1.Seed == seed2 then specMax = math.max(specMax, r1.Sim.N) end
		if r2 and r2.Seed == seed2 then lateMax = math.max(lateMax, r2.Sim.N) end
	end
	LAT = 0.08
	check(gamer.ctx.Desk.Game == nil and gp.PlayerGui:FindFirstChild("CukeRun") == nil, "GUI closed")
	check(CAS.bound.CukeRunControls == nil, "keys unbound")
	check(seat.Occupant == nil and model:GetAttribute("Fun_Player") == 0, "stood up")
	local final2 = model:GetAttribute("Fun_Final")
	check(final2 == forfeit, ("forfeit score counted (%s vs %d)"):format(tostring(final2), forfeit))
	check(model:GetAttribute("Fun_Best") == math.max(score, final2), "best kept")
	check(model:GetAttribute("Fun_EndTick") == exitN, ("server: EndTick = the exit tick (%s vs %d)"):format(tostring(model:GetAttribute("Fun_EndTick")), exitN))
	local s1, s2 = spect.ctx.Desk.Run, late.ctx.Desk.Run
	info(("EXIT at tick %d: the replays reached %d / %d before the end was heard"):format(exitN, specMax, lateMax))
	check(specMax > exitN, "(the slow end made the spectator's replay run past the exit)")
	check(s1.Seed == seed2 and s1.Sim.N == exitN and not s1.Sim.Dead and s1.Sim.Coins == exitCoins,
		("the spectator's replay went back to the exit tick (%d vs %d, dead %s, coins %d vs %d)"):format(s1.Sim.N, exitN, tostring(s1.Sim.Dead), s1.Sim.Coins, exitCoins))
	check(s2.Seed == seed2 and s2.Sim.N == exitN and not s2.Sim.Dead, "the late joiner's replay stops at the exit tick too")
	check(gamer.ctx.Desk.Run == run2 and run2.Sim.N == exitN and not run2.Sim.Dead, "the gamer's own monitor keeps its run, stopped at the exit")
	check(MonitorText(spect, "Big") == "GAME OVER" and MonitorText(spect, "Coins") == "COINS " .. exitCoins, "over after getting up, COINS as at the exit (" .. tostring(MonitorText(spect, "Coins")) .. ")")
	Run(5)
	check(MonitorText(spect, "Big") == "CUKE RUN" and MonitorText(spect, "Score") == "HI " .. string.format("%06d", model:GetAttribute("Fun_Best")), "attract with the HI (" .. tostring(MonitorText(spect, "Score")) .. ")")
	Run(1)
	check(gamer.ctx.Desk.Game == nil, "no reopen after standing up")

	--.. sit again: a fresh GUI; an idle run crashes by itself and reports
	Sit(seat, gh)
	BotHook = nil
	Run(8)
	local g3 = gamer.ctx.Desk.Game
	check(g3 ~= nil and g3.state == "dead", "sat again: GUI reopened, an idle run crashes")
	check(model:GetAttribute("Fun_Ended") > model:GetAttribute("Fun_Since"), "the idle crash ended the run")
	--.. PLAY AGAIN by the button, then the character dies mid-run: the GUI closes, the seat empties, the run ends
	g3.ui.Again.Activated:Fire()
	Run(2.5)
	check(g3.state == "play", "PLAY AGAIN button -> playing (" .. tostring(g3.state) .. ")")
	gh.Health = 0
	gh.Died:Fire()
	seat.Occupant = nil
	Run(1.5)
	check(gamer.ctx.Desk.Game == nil and CAS.bound.CukeRunControls == nil, "death closes the GUI and unbinds")
	check(model:GetAttribute("Fun_Player") == 0 and model:GetAttribute("Fun_Ended") > model:GetAttribute("Fun_Since"), "death ends the run")
	gh.Health = 100

	--.. the build stops (sold / moved): the GUI closes, nothing errors
	for _, c in ipairs(clients) do
		for _, fn in ipairs(c.ctx.cleanups) do
			local okc, e = pcall(fn)
			check(okc, "cleanup: " .. tostring(e))
		end
		c.ctx._alive = false
		c.alive = false
	end
	check(gamer.ctx.Desk.Game == nil and CAS.bound.CukeRunControls == nil, "cleanup closes the GUI")
	info(("server actions: %s; dropped by the 12/s budget: %d"):format(JSON(server.actions), server.dropped))
	check(server.dropped == 0, "no action dropped by the framework's rate limit")
end

------------------------------------------------------------------ 3. the desk itself (x1 yaw 37, x1.3 yaw -120)
local function Screens(c)
	local list = {}
	for _, inst in ipairs(c.ctx.insts) do
		if inst.ClassName == "Part" and inst.Name:sub(1, 16) == "GamingDeskScreen" then
			local gui = inst:FindFirstChild("GameScreen")
			table.insert(list, {Part = inst, Gui = gui, Root = gui and gui:FindFirstChild("Scene")})
		end
	end
	table.sort(list, function(a, b) return a.Root.Position.X.Offset > b.Root.Position.X.Offset end)
	return list
end
local function HudRoot(c)
	for _, s in ipairs(Screens(c)) do
		if s.Root:FindFirstChild("Big") then return s.Root end
	end
	return nil
end
--.. absolute rects of a frame's visible, painted descendants (in the scene root's space)
local function Rects(frame, ax, ay, out)
	out = out or {}
	for _, k in ipairs(frame:GetChildren()) do
		if k.ClassName == "Frame" and k.Visible ~= false then
			local x, y = ax + k.Position.X.Offset, ay + k.Position.Y.Offset
			if (k.BackgroundTransparency or 0) < 1 then table.insert(out, {x, y, x + k.Size.X.Offset, y + k.Size.Y.Offset, k.Name}) end
			Rects(k, x, y, out)
		end
	end
	return out
end
local function Overlap(a, b) return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] end
local function Authored(model, world) return Kit.Origin(model):PointToObjectSpace(world) / Kit.Scale(model) end
local function YawOff(pan, origin) return math.deg(math.acos(math.clamp(pan.CFrame.LookVector:Dot(origin.LookVector), -1, 1))) end

do
	print("== the desk itself")
	for index, spec in ipairs({{1, 37}, {1.3, -120}}) do
		local scale, yawDeg = spec[1], spec[2]
		local tag = ("x%.1f yaw %d: "):format(scale, yawDeg)
		ResetWorld()
		table.clear(plays)
		server.mod = load("S_GamingDesk")
		local model = MakePlaced("GamingDesk", scale, CFrame.new(60, 4, -25) * CFrame.Angles(0, math.rad(yawDeg), 0))
		local origin = Kit.Origin(model)
		server.model = model
		server.ctx = MakeServerCtx(model)

		--..server: the seat..--
		local ok, err = pcall(server.mod.Server, model, server.ctx)
		check(ok, tag .. "Server() errored: " .. tostring(err))
		local rec = server.ctx.seats[1]
		check(rec ~= nil and #server.ctx.seats == 1, tag .. "one seat")
		local seat = rec.Seat
		check(rec.Opts.Prompt == "Game" and rec.Opts.Object == "Gaming Desk", tag .. "prompt 'Game' on 'Gaming Desk'")
		check(seat.CFrame.LookVector:Dot(-origin.LookVector) > 0.9999, tag .. "the sitter faces the desk (authored +Z)")
		local top = seat.CFrame * Vector3.new(0, seat.Size.Y * 0.5, 0)
		check(vnear(top, Kit.Pivot(model, "Seat"), 1e-4), tag .. "seat top on Pivot_Seat")
		check(model:GetAttribute("Fun_Player") == 0 and model:GetAttribute("Fun_Best") == 0 and model:GetAttribute("Fun_Seed") == 0
			and model:GetAttribute("Fun_EndTick") == 0, tag .. "initial state")

		--..the parts the client drives..--
		local swivel = Kit.Parts(model, "Swivel")
		local base = Kit.Parts(model, "ChairLeg")
		local homeSw, homeBase = {}, {}
		for _, p in ipairs(swivel) do homeSw[p] = p.CFrame end
		for _, p in ipairs(base) do homeBase[p] = p.CFrame end
		local rgb = Kit.Parts(model, "RGB")
		local rgbHome = {}
		for _, p in ipairs(rgb) do rgbHome[p] = p.Color end
		check(#swivel >= 15 and #rgb >= 10, tag .. "swivel + RGB parts found (" .. #swivel .. ", " .. #rgb .. ")")
		--.. the client swings the Swivel* parts (anchored) through where the gamer stands: none may collide (fling),
		--.. while the five-star base keeps the chair solid underfoot
		local solidSwivel = {}
		for _, p in ipairs(swivel) do if p.CanCollide then table.insert(solidSwivel, p.Name) end end
		check(#solidSwivel == 0, tag .. "no Swivel* part collides (" .. table.concat(solidSwivel, ", ") .. ")")
		local baseSolid = #base == 5
		for _, p in ipairs(base) do baseSolid = baseSolid and p.CanCollide end
		local chairBase, sleeve = Kit.Part(model, "ChairBase"), Kit.Part(model, "ChairSleeve")
		check(baseSolid and chairBase and chairBase.CanCollide and sleeve and sleeve.CanCollide, tag .. "the chair's base, legs and sleeve still collide")

		--..a watcher's client (the sitter below has none: nobody sends inputs)..--
		local wp, wh, wroot = MakePlayer(500 + index, "Viewer" .. index)
		local sitterP, sitterH = MakePlayer(4200 + index, "CukeMaster9000")
		local watch = AddClient(model, wp, wh, wroot)
		WrapSounds(watch.ctx.insts)
		local screens = Screens(watch)
		check(#screens == 3, tag .. "three screens (got " .. #screens .. ")")
		if #screens == 3 then
			check(screens[1].Part.Name == "GamingDeskScreenL" and screens[2].Part.Name == "GamingDeskScreenC" and screens[3].Part.Name == "GamingDeskScreenR",
				tag .. "slices run L, C, R from the viewer's left")
			local x = 0
			for _, s in ipairs(screens) do
				check(s.Root.Position.X.Offset == -x, tag .. s.Part.Name .. " slice offset " .. x)
				x += math.floor(s.Part.Size.X * 90 + 0.5)
				check(s.Gui.Adornee == s.Part and s.Gui.Face == Enum.NormalId.Front, tag .. s.Part.Name .. " gui on its front face")
				--.. the local screen faces the player and sits in front of its panel + art
				local panel = Kit.Part(model, s.Part.Name:sub(11))
				check(s.Part.CFrame.LookVector:Dot(origin.LookVector) > 0.9, tag .. s.Part.Name .. " faces the front")
				local face = s.Part.CFrame * Vector3.new(0, 0, -s.Part.Size.Z * 0.5)
				local lead = (face - panel.Position):Dot(s.Part.CFrame.LookVector)
				check(lead > 0.025 * scale + 0.01 * scale and lead < 0.1 * scale, tag .. s.Part.Name .. " face just in front of the art (" .. lead .. ")")
				check(near(s.Part.Size.X, panel.Size.X, 1e-6) and near(s.Part.Size.Y, panel.Size.Y, 1e-6), tag .. s.Part.Name .. " covers its panel")
			end
		end

		--..attract mode..--
		Run(1)
		check(MonitorText(watch, "Big") == "CUKE RUN", tag .. "attract title (" .. tostring(MonitorText(watch, "Big")) .. ")")
		check(MonitorText(watch, "Small") == "SIT TO PLAY" or MonitorText(watch, "Small") == "", tag .. "SIT TO PLAY blinks")
		local idleOk = true
		for p, cf in pairs(homeSw) do idleOk = idleOk and vnear(p.CFrame.Position, cf.Position, 1e-4) end
		check(idleOk, tag .. "idle chair stays shipped")
		local changed = false
		for p, c in pairs(rgbHome) do if not (p.Color == c) then changed = true end end
		check(changed, tag .. "RGB colours cycle")
		--.. the attract hero never touches an obstacle (sampled at 30 fps)
		local root = HudRoot(watch)
		local hits = 0
		for _ = 1, 12 * 30 do
			Frame(1 / 30)
			local hero = root:FindFirstChild("Hero")
			local hx, hy = hero.Position.X.Offset, hero.Position.Y.Offset
			local heroRects = Rects(hero, hx, hy)
			for i = 1, 8 do
				local slot = root:FindFirstChild("Obstacle" .. i)
				if slot and slot.Visible then
					for _, r in ipairs(Rects(slot, slot.Position.X.Offset, slot.Position.Y.Offset)) do
						for _, hr in ipairs(heroRects) do
							if hr[5] ~= "Tail" and Overlap(r, hr) then hits += 1 end
						end
					end
				end
			end
		end
		check(hits == 0, tag .. "attract: the hero overlapped an obstacle on " .. hits .. " rect pairs")

		--..sit: the chair swivels to the desk, READY? GO! and the run..--
		Sit(seat, sitterH)
		check(model:GetAttribute("Fun_Player") == sitterP.UserId and near(model:GetAttribute("Fun_Since"), MockNow, 1e-9), tag .. "server: Player + Since on sit")
		Run(20 / 60)
		check(MonitorText(watch, "Big") == "READY?", tag .. "READY? (" .. tostring(MonitorText(watch, "Big")) .. ")")
		check(MonitorText(watch, "Name") == "P1 CUKEMASTER90", tag .. "player name (" .. tostring(MonitorText(watch, "Name")) .. ")")
		Run(50 / 60)
		check(MonitorText(watch, "Big") == "GO!", tag .. "GO! (" .. tostring(MonitorText(watch, "Big")) .. ")")
		Run(1)
		check(Plays("ArcadeBlip") >= 1, tag .. "GO blip played")
		check(MonitorText(watch, "Big") == "", tag .. "big text cleared while running")
		local pan = Kit.Part(model, "SwivelPan")
		check(YawOff(pan, origin) < 3.2, tag .. "chair faces the desk while seated (" .. YawOff(pan, origin) .. " deg off)")
		local seatAt = Authored(model, Kit.Part(model, "SwivelSeat").Position)
		local pivot = model:GetAttribute("Pivot_Seat")
		check(math.abs(seatAt.X - pivot.X) < 0.2 and math.abs(seatAt.Z - pivot.Z) < 0.25, tag .. "seat cushion under the sitter")
		local legsOk = true
		for p, cf in pairs(homeBase) do legsOk = legsOk and vnear(p.CFrame.Position, cf.Position, 1e-6) end
		check(legsOk, tag .. "base legs never move")
		--.. nobody presses anything: the replay shows the hero crashing at the first obstacle while the run is live
		Run(3.5)
		check(MonitorText(watch, "Big") == "GAME OVER" and model:GetAttribute("Fun_Since") > (model:GetAttribute("Fun_Ended") or 0),
			tag .. "a run with no inputs crashes on the monitor (" .. tostring(MonitorText(watch, "Big")) .. ")")
		check(Plays("Thump") >= 1, tag .. "crash thump from the replay")

		--..stand up: the run ends without a score (no "Over" from anyone), GAME OVER, the chair spins back out..--
		sitterH.Sit = false
		local maxYaw = 0
		for _ = 1, 60 do
			Frame(1 / 60)
			maxYaw = math.max(maxYaw, YawOff(pan, origin))
		end
		check(model:GetAttribute("Fun_Player") == 0 and model:GetAttribute("Fun_Final") == 0 and model:GetAttribute("Fun_EndTick") == 0
			and model:GetAttribute("Fun_Ended") > model:GetAttribute("Fun_Since"), tag .. "server: the run ended after the leave grace, no score, no EndTick")
		check(MonitorText(watch, "Big") == "GAME OVER", tag .. "GAME OVER (" .. tostring(MonitorText(watch, "Big")) .. ")")
		check(Plays("ArcadeLose") >= 1, tag .. "no score -> lose sting")
		for _ = 1, 60 do
			Frame(1 / 30)
			maxYaw = math.max(maxYaw, YawOff(pan, origin))
		end
		check(maxYaw > 150, tag .. "the chair spins round when they get up (max " .. maxYaw .. " deg)")
		Run(4)
		check(MonitorText(watch, "Big") == "CUKE RUN", tag .. "back to attract")
		local worst = 0
		for p, cf in pairs(homeSw) do worst = math.max(worst, (p.CFrame.Position - cf.Position).Magnitude) end
		check(worst < 2e-3, tag .. "chair settles exactly on its shipped pose (" .. worst .. ")")

		--..night screen..--
		workspace:SetAttribute("IsNight", true)
		Run(10 / 60)
		if scale == 1 then DumpMonitor("desk_night", watch.ctx) end
		workspace:SetAttribute("IsNight", false)
		Run(2 / 60)

		--..moved while seated: poses follow the hitbox; cleanup restores everything relative to where it IS..--
		Sit(seat, sitterH)
		Run(2)
		local oldHitbox = Kit.Hitbox(model).CFrame
		local hb = Kit.Hitbox(model).CFrame
		MoveBuild(model, CFrame.new(hb.Position + Vector3.new(10, 0, 5)) * CFrame.Angles(0, math.rad(30), 0) * CFrame.new(-hb.Position))
		Run(5 / 60)
		local newHitbox = Kit.Hitbox(model).CFrame
		local panRel = newHitbox:ToObjectSpace(pan.CFrame)
		local sitRel = newHitbox:ToObjectSpace(Kit.Origin(model))
		check(math.deg(math.acos(math.clamp(panRel.LookVector:Dot(sitRel.LookVector), -1, 1))) < 3.2, tag .. "moved: the chair still faces the desk")
		for _, fn in ipairs(watch.ctx.cleanups) do
			local okc, e = pcall(fn)
			check(okc, tag .. "cleanup: " .. tostring(e))
		end
		watch.alive, watch.ctx._alive = false, false
		local worstMove = 0
		for p, cf in pairs(homeSw) do
			local want = newHitbox * oldHitbox:ToObjectSpace(cf)
			worstMove = math.max(worstMove, (p.CFrame.Position - want.Position).Magnitude, (p.CFrame.LookVector - want.LookVector).Magnitude)
		end
		check(worstMove < 1e-4, tag .. "cleanup after a move: chair shipped relative to the new spot (" .. worstMove .. ")")
		local okHome = true
		for p, c in pairs(rgbHome) do if not (p.Color == c) then okHome = false end end
		check(okHome, tag .. "cleanup restores RGB colours")
		sitterH.Sit = false
		Run(0.1)
	end
end

check(#warns == 0, "no warnings (" .. #warns .. ")")
print(("GamingDesk: %d checks, %d failed"):format(checks, fails))
if fails > 0 then print("FAIL") end
