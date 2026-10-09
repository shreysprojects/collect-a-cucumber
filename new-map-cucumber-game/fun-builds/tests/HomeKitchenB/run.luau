--!nocheck
-- Minimal Roblox mock for running fun-build behaviours headless (Vector3/Vector2/CFrame maths real, Instances as
-- property bags). Copied from tests/GardenLights/mock.luau (2026-09-24) and extended for the HomeHearth package:
-- Color3 with Lerp / fromHex, 12-number CFrame.new, SpotLight / Decal / ProximityPrompt, attribute-changed signals.
-- HomeKitchenB copy (2026-09-24) adds: Vector3.xAxis/yAxis/zAxis, CFrame:VectorToObjectSpace, a task scheduler on
-- the mock clock (task.delay / spawn / defer, MockRunTasks) and os.clock() = MockNow (one timeline for everything).

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
Vector3 = {new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1)}

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
	if k == "RightVector" then return v3(t.m[1], t.m[4], t.m[7]) end
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
function CFm.VectorToObjectSpace(a, v) return mv(tr(a.m), v) end
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
	local r = {}
	function r:NextNumber(a, b) a = a or 0 b = b or 1 return a + math.random() * (b - a) end
	function r:NextInteger(a, b) return math.random(a, b) end
	return r
end}
local enumMeta
enumMeta = {__index = function(t, k) local v = setmetatable({__path = t.__path .. "." .. k}, enumMeta) rawset(t, k, v) return v end,
	__tostring = function(t) return t.__path end}
Enum = setmetatable({__path = "Enum"}, enumMeta)

------------------------------------------------------------------ Instances
local CLASS_IS = {
	Part = {BasePart = true, Part = true}, WedgePart = {BasePart = true, WedgePart = true}, MeshPart = {BasePart = true, MeshPart = true},
	Seat = {BasePart = true, Seat = true, Part = true},
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
	Folder = {Name = 1, Parent = 1}, Model = {Name = 1, Parent = 1, PrimaryPart = 1}, Camera = {Name = 1, Parent = 1},
}
local Inst = {}
local InstM = {}
local function isA(self, c)
	if self.ClassName == c or c == "Instance" then return true end
	local t = CLASS_IS[self.ClassName]
	return t ~= nil and t[c] == true
end
local function allowed(self, k)
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
	props[k] = v
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
	if CLASS_IS[className] then
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
	end
	return type(v)
end

------------------------------------------------------------------ task + clock (HomeKitchenB)
local realOs = os
os = setmetatable({clock = function() return MockNow end}, {__index = realOs})
local queue = {}
task = {}
function task.delay(t, fn, ...)
	local args = table.pack(...)
	table.insert(queue, {due = MockNow + (t or 0), fn = function() fn(table.unpack(args, 1, args.n)) end})
end
function task.spawn(fn, ...) fn(...) end
function task.defer(fn, ...) task.delay(0, fn, ...) end
function task.wait() error("task.wait not mocked") end
--.. run every queued task whose time has come (in due order)
function MockRunTasks()
	while true do
		local best, bi = nil, nil
		for i, q in ipairs(queue) do
			if q.due <= MockNow + 1e-9 and (not best or q.due < best.due) then best, bi = q, i end
		end
		if not best then return end
		table.remove(queue, bi)
		best.fn()
	end
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

--.. TV channels. A channel is either {Name, Video = "rbxassetid://..."} (VideoFrame, looped, muted unless
--.. Sound = true; Slides/Seconds = the fallback while the video can't play) or
--.. {Name, Slides = {"rbxassetid://<IMAGE id>", ...}, Seconds = 4} (a picture slideshow)
M.TVChannels = {
	{Name = "Waterfall Cam", Video = "rbxassetid://5670869502", Slides = NATURE, Seconds = 4},   -- Roblox, 30 s
	{Name = "Space Walk", Video = "rbxassetid://5608398904", Slides = SPACE, Seconds = 4},       -- Roblox, 13 s
	{Name = "Cartoon Sea", Video = "rbxassetid://5608250999", Slides = ANIMALS, Seconds = 4},    -- Roblox, 15 s
	{Name = "Bird Watch", Video = "rbxassetid://5608392925", Slides = NATURE, Seconds = 4},      -- Roblox, 15 s
	{Name = "Nature", Slides = NATURE, Seconds = 4},
	{Name = "Space", Slides = SPACE, Seconds = 4},
	{Name = "Cute Animals", Slides = ANIMALS, Seconds = 4},
	{Name = "Yummy Food", Slides = FOOD, Seconds = 4},
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
SOURCES['C_Stove'] = [======[
--[[
	Stove  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the WORKING STOVE (server half: ServerStorage.FunBehaviours.Stove; fun-builds/CONTRACT.md;
	model = fun-builds/models/build_Stove.py). Everything here is local and cosmetic, driven by state Fun_On:
	  * the coils (every Burner* part) heat up over ~2 s: they darken to a dull red, turn Neon and ramp up to a
	    red-orange glow with a faint flicker; switched off they cool down over ~3.5 s
	  * a warm haze (heat shimmer particles) rises off every burner that has nothing standing on it
	  * the pan (Pivot_PanTop) spits little oil pops and a wisp of smoke, and FunAssets.Sfx.Sizzle loops while the
	    camera is within NEAR_SOUND studs
	  * the kettle (Pivot_KettleBase -> Pivot_SpoutTip) starts steaming from its spout after ~7 s on
	  * the OvenWindow warms to a glowing orange (the rack + roast silhouettes stay dark in front of it), the
	    PowerLight turns red, and two lights (<= 2 per build) fade in: one over the cooktop, one at the oven door
	  * a click (Sfx.Click) on every switch
	A stove that streams in while already on starts hot, no ramp. (A placed or moved stove always starts OFF:
	the server half re-runs from scratch and resets Fun_On to false.)
	Every build part it recolours (Burner*, OvenWindow, PowerLight: Color + Material) is restored on cleanup
	from the template. Particle textures are the engine's built-in rbxasset:// ones (no asset ids).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local HEAT_UP = 1.8            -- seconds for the coils to go from cold to full glow
local COOL_DOWN = 3.5          -- seconds for coils / oven to fade out
local OVEN_UP = 3.0            -- the oven window warms a little slower
local KETTLE_UP = 7.0          -- seconds on before the kettle steams
local GLOW_SWITCH = 0.12       -- heat at which a glowing part turns Neon (below: its own material, colour darkens to warm)
local COIL_WARM = Color3.fromRGB(96, 30, 20)
local COIL_HOT = Color3.fromRGB(255, 86, 30)
local OVEN_WARM = Color3.fromRGB(74, 34, 16)
local OVEN_HOT = Color3.fromRGB(240, 132, 52)
local POWER_ON = Color3.fromRGB(255, 56, 44)
local COOK_LIGHT = Color3.fromRGB(255, 124, 60)
local OVEN_LIGHT = Color3.fromRGB(255, 150, 72)
local NEAR_SOUND = 45          -- camera studs for the sizzle loop
local AWAKE_RANGE = 140        -- camera studs for any particles / lights
local COVER_RADIUS = 0.5       -- authored studs: a burner this close under the pan / kettle gets no shimmer
local FALLBACK = {             -- authored points (build_Stove.py) if a Pivot_* attribute is missing
	PanTop = Vector3.new(0.95, 3.935, -0.62),
	OvenWindow = Vector3.new(0, 2.0, -1.61),
	Controls = Vector3.new(0, 4.3, 0.855),
}

local B = {}
B.StepRange = 150

--..Helpers..--
--.. the same part on the build's template (ReplicatedStorage.PlaceableBuilds/<Category>/<Key>): authored values
local function TemplatePart(model, name)
	local root = ReplicatedStorage:FindFirstChild("PlaceableBuilds")
	if not root then return nil end
	local key = tostring(Kit.Key(model))
	local category = root:FindFirstChild(tostring(model:GetAttribute("Category")))
	local template = category and category:FindFirstChild(key)
	if not template then
		for _, c in ipairs(root:GetChildren()) do
			template = c:FindFirstChild(key)
			if template then break end
		end
	end
	local part = template and template:FindFirstChild(name, true)
	return (part and part:IsA("BasePart")) and part or nil
end

--.. Seq(t0, v0, t1, v1, ...) -> NumberSequence
local function Seq(...)
	local args = {...}
	local points = {}
	for i = 1, #args, 2 do table.insert(points, NumberSequenceKeypoint.new(args[i], args[i + 1])) end
	return NumberSequence.new(points)
end

local function Emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

local function Attach(parent, name, cf)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end

local function Light(parent, color, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = 0
	l.Shadows = false
	l.Enabled = false
	l.Parent = parent
	return l
end

local function SetEnabled(list, on)
	for _, e in ipairs(list) do
		if e.Enabled ~= on then e.Enabled = on end
	end
end

--..Behaviour..--
function B.Client(model, ctx)
	local s = ctx.Scale
	local origin = Kit.Origin(model) -- authored origin, authored axes (positions below are authored * s)

	local function AuthoredPivot(name)
		local v = model:GetAttribute("Pivot_" .. name)
		if typeof(v) == "Vector3" then return v end
		return FALLBACK[name]
	end

	--..Build parts we recolour (restored on cleanup)..--
	local coils = Kit.Parts(model, "Burner")
	local window = Kit.Part(model, "OvenWindow")
	local power = Kit.Part(model, "PowerLight")
	local base = {}
	local function Remember(part)
		if not part or base[part] then return end
		local source = TemplatePart(model, part.Name) or part
		base[part] = {Color = source.Color, Material = source.Material}
	end
	for _, p in ipairs(coils) do Remember(p) end
	Remember(window)
	Remember(power)
	local function Restore(part)
		local b = base[part]
		if b and part.Parent then
			part.Color = b.Color
			part.Material = b.Material
		end
	end
	local function RestoreAll()
		for part in pairs(base) do Restore(part) end
	end
	RestoreAll() -- start from the template look, whatever an earlier run left behind
	ctx:OnCleanup(RestoreAll)
	local windowList = window and {window} or {}

	--..Effects host: an invisible local part at the authored origin..--
	local fx = ctx:Part({Name = "StoveFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = origin})

	--.. heat shimmer: a faint warm haze off every burner nothing stands on
	local panAt, kettleAt, spoutAt = AuthoredPivot("PanTop"), AuthoredPivot("KettleBase"), AuthoredPivot("SpoutTip")
	local shimmers = {}
	for _, coil in ipairs(coils) do
		if coil.Name:sub(-2) ~= "In" then -- the outer coil of each burner (BurnerFL, not BurnerFLIn)
			local centre = origin:PointToObjectSpace(coil.Position) / s -- authored
			local covered = false
			for _, c in ipairs({panAt, kettleAt}) do
				if c and Vector2.new(centre.X - c.X, centre.Z - c.Z).Magnitude < COVER_RADIUS then covered = true end
			end
			if not covered then
				local d = math.max(coil.Size.Y, coil.Size.Z) -- a flat cylinder: axis along X, diameter in Y/Z
				local at = Attach(fx, "Shimmer" .. coil.Name, CFrame.new((centre + Vector3.new(0, 0.06, 0)) * s))
				table.insert(shimmers, Emitter(at, {
					Name = "HeatShimmer",
					Texture = TEX_SMOKE,
					Color = ColorSequence.new(Color3.fromRGB(255, 196, 160)),
					Size = Seq(0, 0.45 * d, 1, 1.1 * d),
					Transparency = Seq(0, 1, 0.25, 0.86, 0.7, 0.92, 1, 1),
					Lifetime = NumberRange.new(0.7, 1.1),
					Rate = 5,
					Speed = NumberRange.new(1.4 * s, 2.2 * s),
					SpreadAngle = Vector2.new(10, 10),
					Acceleration = Vector3.new(0, 0.8 * s, 0),
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-60, 60),
					LightEmission = 0.35,
					LightInfluence = 0.3,
					EmissionDirection = Enum.NormalId.Top,
				}))
			end
		end
	end

	--.. the pan: oil pops + a wisp of smoke from the whole inside, and the sizzle loop
	local panFx, sizzle = {}, nil
	if panAt then
		local panPart = ctx:Part({
			Name = "StovePanFX",
			Transparency = 1,
			Size = Vector3.new(0.72 * s, 0.05, 0.72 * s),
			CFrame = origin * CFrame.new((panAt + Vector3.new(0, 0.06, 0)) * s),
		})
		table.insert(panFx, Emitter(panPart, {
			Name = "OilPops",
			Texture = TEX_SPARK,
			Color = ColorSequence.new(Color3.fromRGB(255, 246, 205)),
			Size = Seq(0, 0.16 * s, 1, 0.05 * s),
			Transparency = Seq(0, 0.05, 0.8, 0.4, 1, 1),
			Lifetime = NumberRange.new(0.25, 0.45),
			Rate = 9,
			Speed = NumberRange.new(3 * s, 5.5 * s),
			SpreadAngle = Vector2.new(38, 38),
			Acceleration = Vector3.new(0, -32, 0),
			LightEmission = 0.8,
			LightInfluence = 0.2,
			EmissionDirection = Enum.NormalId.Top,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		}))
		table.insert(panFx, Emitter(panPart, {
			Name = "PanSmoke",
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(245, 245, 245)),
			Size = Seq(0, 0.3 * s, 1, 1.2 * s),
			Transparency = Seq(0, 1, 0.2, 0.78, 1, 1),
			Lifetime = NumberRange.new(1.0, 1.6),
			Rate = 3,
			Speed = NumberRange.new(0.8 * s, 1.4 * s),
			SpreadAngle = Vector2.new(15, 15),
			Acceleration = Vector3.new(0, 0.6 * s, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-30, 30),
			LightInfluence = 0.8,
			EmissionDirection = Enum.NormalId.Top,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		}))
		sizzle = ctx:Sound(panPart, FunAssets.Sfx.Sizzle, {Name = "Sizzle", Looped = true, Volume = 0.3, RollOffMinDistance = 5, RollOffMaxDistance = NEAR_SOUND})
	end

	--.. the kettle: steam out of the spout (base -> tip is the spout's direction)
	local steam
	if kettleAt and spoutAt and (spoutAt - kettleAt).Magnitude > 0.05 then
		local dir = (spoutAt - kettleAt).Unit
		local right = Vector3.zAxis:Cross(dir)
		if right.Magnitude < 0.1 then right = Vector3.xAxis:Cross(dir) end
		local at = Attach(fx, "KettleSteam", CFrame.fromMatrix(spoutAt * s, right.Unit, dir))
		steam = Emitter(at, {
			Name = "Steam",
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(250, 252, 255)),
			Size = Seq(0, 0.15 * s, 0.5, 0.5 * s, 1, 0.9 * s),
			Transparency = Seq(0, 0.45, 0.6, 0.75, 1, 1),
			Lifetime = NumberRange.new(0.9, 1.4),
			Rate = 6,
			Speed = NumberRange.new(2.2 * s, 3.2 * s),
			SpreadAngle = Vector2.new(8, 8),
			Acceleration = Vector3.new(0, 1.4 * s, 0),
			Drag = 1.2,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
			LightInfluence = 0.8,
			EmissionDirection = Enum.NormalId.Top,
		})
	end

	--.. two lights: over the cooktop (the burners' middle) and in front of the oven window
	local mid = Vector3.new(0, 3.6 * s, 0)
	if #coils > 0 then
		mid = Vector3.zero
		for _, coil in ipairs(coils) do mid += origin:PointToObjectSpace(coil.Position) end
		mid /= #coils
	end
	local cookLight = Light(Attach(fx, "CookLight", CFrame.new(mid + Vector3.new(0, 0.9 * s, 0))), COOK_LIGHT, 7 * s)
	local windowAt = AuthoredPivot("OvenWindow")
	local ovenLight = Light(Attach(fx, "OvenLight", CFrame.new((windowAt + Vector3.new(0, 0, -0.7)) * s)), OVEN_LIGHT, 6 * s)

	local click = ctx:Sound(Attach(fx, "Controls", CFrame.new(AuthoredPivot("Controls") * s)), FunAssets.Sfx.Click, {Name = "Click", Volume = 0.45, RollOffMaxDistance = 40})

	--..State..--
	local on, first = false, true
	local heat, oven, kettle = 0, 0, 0
	local awake, near, sizzling = true, false, false
	local coilsLit, windowLit = false, false

	--.. emitters, lights and the sizzle from the current heat (every frame while awake, and twice a second)
	local function Apply()
		SetEnabled(shimmers, awake and heat > 0.55)
		SetEnabled(panFx, awake and heat > 0.45)
		if steam then
			local want = awake and kettle >= 1
			if steam.Enabled ~= want then steam.Enabled = want end
		end
		cookLight.Enabled = awake and heat > 0.02
		ovenLight.Enabled = awake and oven > 0.02
		if sizzle then
			local want = on and heat > 0.4 and near
			if want ~= sizzling then
				sizzling = want
				if want then sizzle:Play() else sizzle:Stop() end
			end
			if want then sizzle.Volume = 0.3 * math.clamp((heat - 0.4) / 0.4, 0.25, 1) end
		end
	end

	ctx:OnState("On", function(value)
		local now = value == true
		if first then
			first = false
			if now then heat, oven, kettle = 1, 1, 1 end -- streamed in while on: already hot
		elseif now ~= on and ctx:CameraDistance() <= 60 then
			click:Play()
		end
		on = now
		if power then
			if on then
				power.Material = Enum.Material.Neon
				power.Color = POWER_ON
			else
				Restore(power)
			end
		end
		Apply()
	end)

	ctx:Every(0.5, function()
		local d = ctx:CameraDistance()
		awake = d <= AWAKE_RANGE
		near = d <= NEAR_SOUND
		Apply()
	end)

	--.. glow a list of parts: below GLOW_SWITCH their own material darkening toward warm, then Neon warm -> hot
	local function Glow(parts, level, warm, hot, flicker)
		for _, p in ipairs(parts) do
			local b = base[p]
			if level < GLOW_SWITCH then
				p.Material = b.Material
				p.Color = b.Color:Lerp(warm, level / GLOW_SWITCH)
			else
				p.Material = Enum.Material.Neon
				p.Color = warm:Lerp(hot, math.clamp(((level - GLOW_SWITCH) / (1 - GLOW_SWITCH)) ^ 1.3 * flicker, 0, 1))
			end
		end
	end

	--..Per frame: heat ramps, glow, light brightness..--
	local t = 0
	ctx:Step(function(dt)
		t += dt
		if on then
			heat = math.min(1, heat + dt / HEAT_UP)
			oven = math.min(1, oven + dt / OVEN_UP)
			kettle = math.min(1, kettle + dt / KETTLE_UP)
		else
			heat = math.max(0, heat - dt / COOL_DOWN)
			oven = math.max(0, oven - dt / COOL_DOWN)
			kettle = math.max(0, kettle - dt / 2)
		end
		local flicker = 1 + 0.04 * math.sin(t * 7.3) + 0.025 * math.sin(t * 12.9 + 1.3)
		if heat > 0 then
			Glow(coils, heat, COIL_WARM, COIL_HOT, flicker)
			coilsLit = true
		elseif coilsLit then
			coilsLit = false
			for _, p in ipairs(coils) do Restore(p) end
		end
		if window then
			if oven > 0 then
				Glow(windowList, oven, OVEN_WARM, OVEN_HOT, 1 + 0.03 * math.sin(t * 5.1))
				windowLit = true
			elseif windowLit then
				windowLit = false
				Restore(window)
			end
		end
		cookLight.Brightness = 1.1 * heat * flicker
		ovenLight.Brightness = 0.9 * oven
		Apply()
	end)
end

return B
]======]
SOURCES['S_Stove'] = [======[
--[[
	Stove  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the WORKING STOVE (client half: ReplicatedStorage.FunBehavioursClient.Stove;
	fun-builds/CONTRACT.md; model = fun-builds/models/build_Stove.py).
	  * one "Turn on" / "Turn off" prompt on the knob panel of the back guard (Pivot_Controls) toggles
	    state On (model attribute Fun_On). The client half does everything visible and audible: the coils
	    (Burner*) glow red-orange, heat shimmer rises, the pan sizzles and pops oil, the kettle steams, the
	    oven window glows and the power light turns red.
	Anyone may use it (nothing to grief). No economy, no physics, no build parts touched on the server.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local CONTROLS_FALLBACK = Vector3.new(0, 4.3, 0.855) -- authored knob-panel front (Pivot_Controls)
local PROMPT_DISTANCE = 10                           -- studs at scale 1 (grows with a bigger template)
local TOGGLE_DEBOUNCE = 0.4                          -- seconds between two toggles

local B = {}
B.ActionRange = 30

--..Behaviour..--
function B.Server(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	ctx:SetState("On", false)

	--..Prompt on the knob panel..--
	local at = Kit.Pivot(model, "Controls") or Kit.ToWorld(model, CONTROLS_FALLBACK)
	local prompt = ctx:Prompt(hitbox, {
		Action = "Turn on",
		Object = "Stove",
		Name = "StovePrompt",
		Distance = math.max(PROMPT_DISTANCE, PROMPT_DISTANCE * ctx.Scale),
		Offset = hitbox.CFrame:PointToObjectSpace(at),
	})
	local last = 0
	ctx:Connect(prompt.Triggered, function(player)
		local now = os.clock()
		if now - last < TOGGLE_DEBOUNCE or not ctx:HumanoidOf(player) then return end
		last = now
		local on = ctx:GetState("On") ~= true
		ctx:SetState("On", on)
		prompt.ActionText = on and "Turn off" or "Turn on"
	end)
end

return B
]======]
SOURCES['C_SinkCounter'] = [======[
--[[
	SinkCounter  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the WORKING KITCHEN COUNTER (server half: ServerStorage.FunBehaviours.SinkCounter;
	fun-builds/CONTRACT.md; model = fun-builds/models/build_SinkCounter.py). Local and cosmetic, from two states:
	  Fun_Tap (bool)
	    * a translucent water stream (a local cylinder) falls from Pivot_Spout to the water over Pivot_SinkFloor: it
	      grows down from the nozzle when the tap opens and drops away when it closes
	    * a pool of water rises in the basin (the Pivot_PoolA..PoolB box, up to POOL_MAX) and drains when it stops
	    * splash spray + ripple rings where the stream lands, FunAssets.Sfx.WaterLoop while the camera is near
	  Fun_ToastAt (server time the toast pops, 0 = idle) - the whole toaster cycle is timed from it
	    * press: the PopLever slides down, the Toast* slices sink out of sight, the PopSlot* slots glow orange
	      and a wisp of smoke curls out near the end
	    * at ToastAt the slices pop up POP_HEIGHT (0.8) with a little overshoot, golden brown, with
	      Sfx.ToasterPop + Sfx.Ding (only for clients that saw it happen, never late); the lever springs back
	    * POP_HOLD later they slide back down, and fade back to bread colour once they are in
	A counter that streams in while the tap runs starts with a full stream and pool (and one that streams in
	mid-toast jumps straight to the right toaster pose). A placed or moved counter always starts idle: the
	server half re-runs from scratch and resets Fun_Tap to false and Fun_ToastAt to 0.
	Every build part it moves or recolours (Toast*, PopLever: CFrame; Toast*, PopSlot*: Color + Material) goes
	back to its template pose / look on cleanup. Particle textures are built-in rbxasset:// ones.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local TOAST_DELAY = 4        -- = the server half's numbers
local POP_HOLD = 5
local SLIDE_TIME = 0.6
local POP_HEIGHT = 0.8       -- authored studs the toast pops up
local POP_OVERSHOOT = 0.12   -- authored studs it overshoots before settling
local SINK_DEPTH = 0.14      -- authored studs the toast sinks out of sight while toasting
local LEVER_TRAVEL = 0.3     -- authored studs the lever slides down
local PRESS_TIME = 0.25      -- seconds for lever + toast to go down
local UNTOAST_TIME = 1.5     -- seconds for the slices to fade back to bread once they are back in
local STREAM_WIDTH = 0.13    -- authored diameter of the water stream
local STREAM_SPEED = 9       -- authored studs / s the stream front falls (and its tail drops when the tap closes)
local POOL_MAX = 0.2         -- authored depth of water in the basin while the tap runs
local POOL_FILL = 6          -- seconds to fill
local POOL_DRAIN = 3.5       -- seconds to drain
local WATER = Color3.fromRGB(172, 220, 255)
local POOL = Color3.fromRGB(120, 188, 238)
local SLOT_WARM = Color3.fromRGB(90, 26, 12)
local SLOT_HOT = Color3.fromRGB(255, 104, 36)
local TOASTED = Color3.fromRGB(214, 150, 74)
local TOASTED_CRUST = Color3.fromRGB(146, 84, 36)
local NEAR_SOUND = 55        -- camera studs for the running-water loop
local AWAKE_RANGE = 140      -- camera studs for any particles
local FALLBACK = {           -- authored points (build_SinkCounter.py) if a Pivot_* attribute is missing
	Spout = Vector3.new(0, 4.3, -0.1),
	SinkFloor = Vector3.new(0, 2.92, -0.1),
	PoolA = Vector3.new(1.3, 2.92, -0.9),
	PoolB = Vector3.new(-1.3, 2.92, 0.45),
}

local B = {}
B.StepRange = 150

--..Helpers..--
--.. the build's template (ReplicatedStorage.PlaceableBuilds/<Category>/<Key>)
local function TemplateOf(model)
	local root = ReplicatedStorage:FindFirstChild("PlaceableBuilds")
	if not root then return nil end
	local key = tostring(Kit.Key(model))
	local category = root:FindFirstChild(tostring(model:GetAttribute("Category")))
	local template = category and category:FindFirstChild(key)
	if not template then
		for _, c in ipairs(root:GetChildren()) do
			template = c:FindFirstChild(key)
			if template then break end
		end
	end
	return template
end

--.. Seq(t0, v0, t1, v1, ...) -> NumberSequence
local function Seq(...)
	local args = {...}
	local points = {}
	for i = 1, #args, 2 do table.insert(points, NumberSequenceKeypoint.new(args[i], args[i + 1])) end
	return NumberSequence.new(points)
end

local function Emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

local function Attach(parent, name, cf)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end

local function Smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function EaseOut(x)
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

--..Behaviour..--
function B.Client(model, ctx)
	local s = ctx.Scale
	local origin = Kit.Origin(model) -- authored origin, authored axes (local positions below are authored * s)
	local up = origin.UpVector
	local hitbox = Kit.Hitbox(model)
	local template = TemplateOf(model)
	local templateHitbox = template and Kit.Hitbox(template)

	local function AuthoredPivot(name)
		local v = model:GetAttribute("Pivot_" .. name)
		if typeof(v) == "Vector3" then return v end
		return FALLBACK[name]
	end

	--..Build parts we move / recolour (restored on cleanup)..--
	local toastParts = Kit.Parts(model, "Toast")
	local slots = Kit.Parts(model, "PopSlot")
	local lever = Kit.Part(model, "PopLever")
	local rest, look = {}, {}
	local function Remember(part, pose)
		if not part then return end
		local source = template and template:FindFirstChild(part.Name, true)
		if not (source and source:IsA("BasePart")) then source = nil end
		if pose then
			--.. the rest pose relative to the Hitbox, from the template (safe even if a run ended mid-pop)
			rest[part] = (source and templateHitbox and hitbox) and hitbox.CFrame * templateHitbox.CFrame:ToObjectSpace(source.CFrame) or part.CFrame
		end
		look[part] = {Color = (source or part).Color, Material = (source or part).Material}
	end
	for _, p in ipairs(toastParts) do Remember(p, true) end
	for _, p in ipairs(slots) do Remember(p, false) end
	Remember(lever, true)
	local function RestoreLook(part)
		local l = look[part]
		if l and part.Parent then
			part.Color = l.Color
			part.Material = l.Material
		end
	end
	local function RestoreAll()
		for part, cf in pairs(rest) do
			if part.Parent then part.CFrame = cf end
		end
		for part in pairs(look) do RestoreLook(part) end
	end
	RestoreAll() -- start from the template pose / look, whatever an earlier run left behind
	ctx:OnCleanup(RestoreAll)

	--..Effects host: an invisible local part at the authored origin..--
	local fx = ctx:Part({Name = "SinkFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = origin})

	--..Water: stream + pool + splash..--
	local spout, basin = AuthoredPivot("Spout"), AuthoredPivot("SinkFloor")
	local cornerA, cornerB = AuthoredPivot("PoolA"), AuthoredPivot("PoolB")
	local floorY = math.min(cornerA.Y, cornerB.Y)
	local poolMid = Vector3.new((cornerA.X + cornerB.X) * 0.5, 0, (cornerA.Z + cornerB.Z) * 0.5)
	local poolW, poolD = math.abs(cornerA.X - cornerB.X), math.abs(cornerA.Z - cornerB.Z)
	local stream = ctx:Part({
		Name = "SinkStream",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.SmoothPlastic,
		Color = WATER,
		Reflectance = 0.15,
		Transparency = 1,
		Size = Vector3.new(0.1, STREAM_WIDTH * s, STREAM_WIDTH * s),
		CFrame = origin * CFrame.new(spout * s),
	})
	local pool = ctx:Part({
		Name = "SinkPool",
		Material = Enum.Material.SmoothPlastic,
		Color = POOL,
		Reflectance = 0.2,
		Transparency = 1,
		Size = Vector3.new(poolW * s, 0.05, poolD * s),
		CFrame = origin * CFrame.new(poolMid.X * s, floorY * s, poolMid.Z * s),
	})
	local splashAt = Attach(fx, "Splash", CFrame.new(basin * s))
	local splash = {
		Emitter(splashAt, {
			Name = "Spray",
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(228, 244, 255)),
			Size = Seq(0, 0.14 * s, 1, 0.05 * s),
			Transparency = Seq(0, 0.2, 0.7, 0.4, 1, 1),
			Lifetime = NumberRange.new(0.22, 0.38),
			Rate = 22,
			Speed = NumberRange.new(2.5 * s, 4.5 * s),
			SpreadAngle = Vector2.new(55, 55),
			Acceleration = Vector3.new(0, -40, 0),
			Rotation = NumberRange.new(0, 360),
			LightEmission = 0.3,
			ZOffset = 0.2,
			EmissionDirection = Enum.NormalId.Top,
		}),
		Emitter(splashAt, {
			Name = "Ripples",
			Texture = TEX_RING,
			Color = ColorSequence.new(Color3.fromRGB(240, 250, 255)),
			Size = Seq(0, 0.15 * s, 1, 0.9 * s),
			Transparency = Seq(0, 0.3, 0.6, 0.6, 1, 1),
			Lifetime = NumberRange.new(0.5, 0.75),
			Rate = 4,
			Speed = NumberRange.new(0.05, 0.08),
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular, -- lies flat on the water
			Rotation = NumberRange.new(0, 360),
			LightEmission = 0.25,
			ZOffset = 0.2,
			EmissionDirection = Enum.NormalId.Top,
		}),
	}
	local water = ctx:Sound(splashAt, FunAssets.Sfx.WaterLoop, {Name = "WaterLoop", Looped = true, Volume = 0.45, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND})

	--..Toaster: sounds + a wisp of smoke at the slots..--
	local topAt = Vector3.new(-2.75, 4.9, 0.3) * s
	if #toastParts > 0 then
		topAt = Vector3.zero
		for _, p in ipairs(toastParts) do topAt += origin:PointToObjectSpace(rest[p].Position) end
		topAt /= #toastParts
		topAt += Vector3.new(0, 0.3 * s, 0)
	end
	local toasterAt = Attach(fx, "Toaster", CFrame.new(topAt))
	local toastSmoke = Emitter(toasterAt, {
		Name = "ToastSmoke",
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(215, 215, 215)),
		Size = Seq(0, 0.2 * s, 1, 0.8 * s),
		Transparency = Seq(0, 1, 0.25, 0.75, 1, 1),
		Lifetime = NumberRange.new(1.0, 1.5),
		Rate = 3,
		Speed = NumberRange.new(0.8 * s, 1.3 * s),
		SpreadAngle = Vector2.new(12, 12),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		LightInfluence = 0.8,
		EmissionDirection = Enum.NormalId.Top,
	})
	local popSound = ctx:Sound(toasterAt, FunAssets.Sfx.ToasterPop, {Name = "ToasterPop", Volume = 0.6, RollOffMaxDistance = 50})
	local ding = ctx:Sound(toasterAt, FunAssets.Sfx.Ding, {Name = "Ding", Volume = 0.5, RollOffMaxDistance = 60})
	local click = ctx:Sound(toasterAt, FunAssets.Sfx.Click, {Name = "Click", Volume = 0.45, RollOffMaxDistance = 40})
	local tapClick = ctx:Sound(Attach(fx, "Tap", CFrame.new(spout * s)), FunAssets.Sfx.Click, {Name = "TapClick", Volume = 0.35, RollOffMaxDistance = 35})

	--..State..--
	local tapOn, firstTap = false, true
	local head, tail, level = 0, 0, 0 -- authored studs: stream front / back from the spout, pool depth
	local popAt, firstToast = 0, true
	local awake, near, running = true, false, false

	local function WaterTarget()
		local surface = basin + Vector3.new(0, level, 0)
		local v = surface - spout
		return v.Magnitude, (v.Magnitude > 1e-3 and v.Unit or -Vector3.yAxis)
	end

	ctx:OnState("Tap", function(value)
		local on = value == true
		if firstTap then
			firstTap = false
			if on then
				level = POOL_MAX
				head = WaterTarget()
			end
		elseif on ~= tapOn and ctx:CameraDistance() <= 50 then
			tapClick:Play()
		end
		if on and not tapOn then
			if tail > 0 then head, tail = 0, 0 end -- the last stream is still dropping away: start a fresh one
		end
		tapOn = on
	end)

	ctx:OnState("ToastAt", function(value)
		popAt = tonumber(value) or 0
		if firstToast then
			firstToast = false
		elseif popAt > 0 and math.abs(Kit.Now() - (popAt - TOAST_DELAY)) < 0.6 and ctx:CameraDistance() <= 60 then
			click:Play() -- the lever going down
		end
	end)

	local function Apply()
		local L = WaterTarget()
		local falling = head > 0 and tail < L - 0.02
		local landing = falling and head >= L - 0.02
		for _, e in ipairs(splash) do
			local want = awake and landing
			if e.Enabled ~= want then e.Enabled = want end
		end
		local want = near and falling
		if want ~= running then
			running = want
			if want then water:Play() else water:Stop() end
		end
	end

	ctx:Every(0.5, function()
		local d = ctx:CameraDistance()
		awake = d <= AWAKE_RANGE
		near = d <= NEAR_SOUND
		Apply()
	end)

	--.. the toaster pose at server time `now`: toast offset, lever offset, slot glow, toast tint, smoke
	local function ToasterPose(now)
		if popAt <= 0 then return nil end
		local u = now - popAt
		if u < -TOAST_DELAY - 0.1 or u > POP_HOLD + SLIDE_TIME + UNTOAST_TIME then return nil end
		if u < 0 then
			local e = Smooth((u + TOAST_DELAY) / PRESS_TIME)
			return -SINK_DEPTH * e, -LEVER_TRAVEL * e, Smooth((u + TOAST_DELAY - 0.3) / 1.2), math.clamp((u + TOAST_DELAY) / TOAST_DELAY, 0, 1), u > -2.5
		elseif u < POP_HOLD then
			local off
			if u < 0.12 then
				off = -SINK_DEPTH + (POP_HEIGHT + POP_OVERSHOOT + SINK_DEPTH) * EaseOut(u / 0.12)
			else
				off = POP_HEIGHT + POP_OVERSHOOT * (1 - Smooth((u - 0.12) / 0.23))
			end
			return off, -LEVER_TRAVEL * (1 - Smooth(u / 0.1)), 1 - Smooth(u / 0.8), 1, u < 1.2
		elseif u < POP_HOLD + SLIDE_TIME then
			return POP_HEIGHT * (1 - Smooth((u - POP_HOLD) / SLIDE_TIME)), 0, 0, 1, false
		end
		return 0, 0, 0, 1 - (u - POP_HOLD - SLIDE_TIME) / UNTOAST_TIME, false
	end

	--..Per frame: stream, pool, toaster..--
	local t, posed, prevU = 0, false, nil
	ctx:Step(function(dt, now)
		t += dt

		--..water..--
		local L, dir = WaterTarget()
		if tapOn then
			head = math.min(L, head + dt * STREAM_SPEED)
			tail = 0
			if head >= L - 0.02 then level = math.min(POOL_MAX, level + dt * POOL_MAX / POOL_FILL) end
		else
			if head > 0 then
				head = math.min(L, head + dt * STREAM_SPEED) -- what already left the nozzle keeps falling
				tail = math.min(L, tail + dt * STREAM_SPEED)
				if tail >= L - 0.02 then head, tail = 0, 0 end
			end
			level = math.max(0, level - dt * POOL_MAX / POOL_DRAIN)
		end
		L, dir = WaterTarget()
		head = math.min(head, L)
		local len = head - tail
		if len > 0.03 then
			local top = origin:PointToWorldSpace((spout + dir * tail) * s)
			local bottom = origin:PointToWorldSpace((spout + dir * head) * s)
			local axis = (bottom - top).Unit
			local side = axis:Cross(origin.RightVector)
			if side.Magnitude < 0.1 then side = axis:Cross(origin.LookVector) end
			local w = STREAM_WIDTH * s * (1 + 0.07 * math.sin(t * 21))
			stream.Size = Vector3.new(len * s, w, w)
			stream.CFrame = CFrame.fromMatrix((top + bottom) * 0.5, axis, side.Unit)
			stream.Transparency = 0.32 + 0.08 * math.sin(t * 15 + 1)
		elseif stream.Transparency < 1 then
			stream.Transparency = 1
		end
		if level > 0.004 then
			local h = math.max(0.05, level * s)
			pool.Size = Vector3.new(poolW * s, h, poolD * s)
			pool.CFrame = origin * CFrame.new(poolMid.X * s, (floorY + level) * s - h * 0.5, poolMid.Z * s)
			pool.Transparency = 0.38 + 0.04 * math.sin(t * 3)
		elseif pool.Transparency < 1 then
			pool.Transparency = 1
		end
		splashAt.CFrame = CFrame.new((basin + Vector3.new(0, level + 0.02, 0)) * s)

		--..toaster..--
		local off, leverOff, glow, tint, smoking = ToasterPose(now)
		local u = popAt > 0 and now - popAt or nil
		if prevU and u and prevU < 0 and u >= 0 and u < 0.6 and ctx:CameraDistance() <= 80 then
			popSound:Play()
			task.delay(0.15, function()
				if ctx:Alive() then ding:Play() end
			end)
		end
		prevU = u
		if off then
			posed = true
			for _, p in ipairs(toastParts) do
				p.CFrame = rest[p] + up * (off * s)
				local l = look[p]
				local target = p.Name:sub(-5) == "Crust" and TOASTED_CRUST or TOASTED
				p.Color = l.Color:Lerp(target, math.clamp(tint, 0, 1))
			end
			if lever then lever.CFrame = rest[lever] + up * (leverOff * s) end
			for _, p in ipairs(slots) do
				if glow > 0.05 then
					p.Material = Enum.Material.Neon
					p.Color = SLOT_WARM:Lerp(SLOT_HOT, glow)
				else
					RestoreLook(p)
				end
			end
			local wantSmoke = awake and smoking == true
			if toastSmoke.Enabled ~= wantSmoke then toastSmoke.Enabled = wantSmoke end
		elseif posed then
			posed = false
			RestoreAll()
			toastSmoke.Enabled = false
		end

		Apply()
	end)
end

return B
]======]
SOURCES['S_SinkCounter'] = [======[
--[[
	SinkCounter  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the WORKING KITCHEN COUNTER (client half: ReplicatedStorage.FunBehavioursClient.SinkCounter;
	fun-builds/CONTRACT.md; model = fun-builds/models/build_SinkCounter.py). Two prompts, two states:
	  * "Tap on" / "Tap off" in front of the faucet (Pivot_Tap) toggles state Tap (Fun_Tap). A tap left running
	    turns itself off after TAP_AUTO_OFF seconds (nobody has to hear it forever).
	  * "Make toast" over the toaster (Pivot_Toaster) sets state ToastAt (Fun_ToastAt) = the server time the toast
	    pops (now + TOAST_DELAY). Clients animate the whole cycle from that one number: lever down + slots glow
	    while toasting, the Toast* slices pop up 0.8 stud at ToastAt with ToasterPop + Ding, hold POP_HOLD
	    seconds, then slide back down. The prompt reads "Toasting..." (and presses are ignored) until the cycle
    is over. It is never disabled from here: the framework owns Enabled (it hides prompts in build mode).
	Anyone may use both (nothing to grief). No economy, no physics, no build parts touched on the server.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local TAP_FALLBACK = Vector3.new(0, 4.1, 0.55)          -- authored prompt spots (Pivot_Tap / Pivot_Toaster)
local TOASTER_FALLBACK = Vector3.new(-2.75, 5.31, 0.05)
local PROMPT_DISTANCE = 8                               -- studs at scale 1
local TOGGLE_DEBOUNCE = 0.4                             -- seconds between two tap toggles
local TAP_AUTO_OFF = 120                                -- seconds a tap runs before it shuts itself off
local TOAST_DELAY = 4                                   -- seconds from "Make toast" to the pop
local POP_HOLD = 5                                      -- seconds the toast stays up
local SLIDE_TIME = 0.6                                  -- seconds it takes to slide back down
-- (TOAST_DELAY / POP_HOLD / SLIDE_TIME are repeated in the client half: keep them the same)
local IDLE_TEXT = "Make toast"                          -- toaster prompt text, idle / during a cycle
local BUSY_TEXT = "Toasting..."

local B = {}
B.ActionRange = 30

--..Helpers..--
local function PromptAt(model, ctx, pivot, fallback, opts)
	local hitbox = Kit.Hitbox(model)
	local at = Kit.Pivot(model, pivot) or Kit.ToWorld(model, fallback)
	opts.Offset = hitbox.CFrame:PointToObjectSpace(at)
	opts.Distance = math.max(PROMPT_DISTANCE, PROMPT_DISTANCE * ctx.Scale)
	return ctx:Prompt(hitbox, opts)
end

--..Behaviour..--
function B.Server(model, ctx)
	if not Kit.Hitbox(model) then return end
	ctx:SetState("Tap", false)
	ctx:SetState("ToastAt", 0)

	--..Tap..--
	local tap = PromptAt(model, ctx, "Tap", TAP_FALLBACK, {Action = "Tap on", Object = "Kitchen sink", Name = "TapPrompt"})
	local lastTap, tapRun = 0, 0
	local function SetTap(on)
		ctx:SetState("Tap", on)
		tap.ActionText = on and "Tap off" or "Tap on"
		tapRun += 1
		if on then
			local run = tapRun
			task.delay(TAP_AUTO_OFF, function()
				if ctx:Alive() and tapRun == run and ctx:GetState("Tap") == true then SetTap(false) end
			end)
		end
	end
	ctx:Connect(tap.Triggered, function(player)
		local now = os.clock()
		if now - lastTap < TOGGLE_DEBOUNCE or not ctx:HumanoidOf(player) then return end
		lastTap = now
		SetTap(ctx:GetState("Tap") ~= true)
	end)

	--..Toaster..--
	local toast = PromptAt(model, ctx, "Toaster", TOASTER_FALLBACK, {Action = IDLE_TEXT, Object = "Toaster", Name = "ToastPrompt"})
	ctx:Connect(toast.Triggered, function(player)
		if not ctx:HumanoidOf(player) then return end
		local now = Kit.Now()
		local popAt = tonumber(ctx:GetState("ToastAt")) or 0
		if now < popAt + POP_HOLD + SLIDE_TIME then return end -- still toasting / popped / sliding back
		local cycle = now + TOAST_DELAY
		ctx:SetState("ToastAt", cycle)
		--.. feedback through the text only: never write toast.Enabled here (the framework's client hides every
		--.. FunBuildPrompt in build mode by flipping Enabled locally; a server write would override that)
		toast.ActionText = BUSY_TEXT
		task.delay(TOAST_DELAY + POP_HOLD + SLIDE_TIME, function()
			if ctx:Alive() and ctx:GetState("ToastAt") == cycle then toast.ActionText = IDLE_TEXT end
		end)
	end)
end

return B
]======]
MODELS = {}
MODELS['Stove'] = {Min = Vector3.new(-2.055, 0.0, -1.955), Max = Vector3.new(2.055, 4.83, 1.555), Attrs = {Pivot_Controls = Vector3.new(0.0, 4.3, 0.855), Pivot_PanTop = Vector3.new(0.95, 3.935, -0.62), Pivot_OvenWindow = Vector3.new(0.0, 2.0, -1.61), Pivot_SpoutTip = Vector3.new(-1.61, 4.185, -0.62), Pivot_KettleBase = Vector3.new(-0.95, 3.685, -0.62), Cost = 1000.0, DisplayName = "Stove"}, Parts = {
	{Name = "Foot1", Shape = "Cylinder", Size = Vector3.new(0.33, 0.42, 0.42), CF = {1.62, 0.165, -1.12, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "23262c", Material = "Rubber", T = 0.0, Collide = true},
	{Name = "Foot2", Shape = "Cylinder", Size = Vector3.new(0.33, 0.42, 0.42), CF = {-1.62, 0.165, -1.12, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "23262c", Material = "Rubber", T = 0.0, Collide = true},
	{Name = "Foot3", Shape = "Cylinder", Size = Vector3.new(0.33, 0.42, 0.42), CF = {1.62, 0.165, 1.18, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "23262c", Material = "Rubber", T = 0.0, Collide = true},
	{Name = "Foot4", Shape = "Cylinder", Size = Vector3.new(0.33, 0.42, 0.42), CF = {-1.62, 0.165, 1.18, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "23262c", Material = "Rubber", T = 0.0, Collide = true},
	{Name = "Body", Shape = "Block", Size = Vector3.new(4.0, 3.16, 2.95), CF = {0.0, 1.88, 0.025, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "KickStrip", Shape = "Block", Size = Vector3.new(3.9, 0.12, 0.05), CF = {0.0, 0.36, -1.46, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CornerTrimL", Shape = "Cylinder", Size = Vector3.new(3.15, 0.11, 0.11), CF = {2.0, 1.875, -1.43, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "CornerTrimR", Shape = "Cylinder", Size = Vector3.new(3.15, 0.11, 0.11), CF = {-2.0, 1.875, -1.43, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "BackPanel", Shape = "Block", Size = Vector3.new(3.3, 2.6, 0.05), CF = {0.0, 2.0, 1.51, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "dedbd2", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "BackVent1", Shape = "Block", Size = Vector3.new(2.4, 0.1, 0.05), CF = {0.0, 2.9, 1.53, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "BackVent2", Shape = "Block", Size = Vector3.new(2.4, 0.1, 0.05), CF = {0.0, 2.62, 1.53, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CooktopFrame", Shape = "Block", Size = Vector3.new(4.1, 0.1, 3.04), CF = {0.0, 3.48, -0.01, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = true},
	{Name = "Cooktop", Shape = "Block", Size = Vector3.new(3.92, 0.1, 2.62), CF = {0.0, 3.55, -0.16, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "Glass", T = 0.0, Collide = true},
	{Name = "DripRingFL", Shape = "Cylinder", Size = Vector3.new(0.052, 1.31, 1.31), CF = {0.95, 3.61, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "BurnerFL", Shape = "Cylinder", Size = Vector3.new(0.052, 1.15, 1.15), CF = {0.95, 3.63, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "4f545e", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CoilGapFL", Shape = "Cylinder", Size = Vector3.new(0.052, 0.759, 0.759), CF = {0.95, 3.64, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "1a1c20", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "BurnerFLIn", Shape = "Cylinder", Size = Vector3.new(0.052, 0.483, 0.483), CF = {0.95, 3.65, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "4f545e", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CoilHubFL", Shape = "Cylinder", Size = Vector3.new(0.052, 0.161, 0.161), CF = {0.95, 3.66, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "1a1c20", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "DripRingBL", Shape = "Cylinder", Size = Vector3.new(0.052, 1.01, 1.01), CF = {0.95, 3.61, 0.48, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "BurnerBL", Shape = "Cylinder", Size = Vector3.new(0.052, 0.85, 0.85), CF = {0.95, 3.63, 0.48, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "4f545e", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CoilGapBL", Shape = "Cylinder", Size = Vector3.new(0.052, 0.561, 0.561), CF = {0.95, 3.64, 0.48, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "1a1c20", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "BurnerBLIn", Shape = "Cylinder", Size = Vector3.new(0.052, 0.357, 0.357), CF = {0.95, 3.65, 0.48, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "4f545e", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CoilHubBL", Shape = "Cylinder", Size = Vector3.new(0.052, 0.119, 0.119), CF = {0.95, 3.66, 0.48, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "1a1c20", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "DripRingFR", Shape = "Cylinder", Size = Vector3.new(0.052, 1.01, 1.01), CF = {-0.95, 3.61, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "BurnerFR", Shape = "Cylinder", Size = Vector3.new(0.052, 0.85, 0.85), CF = {-0.95, 3.63, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "4f545e", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CoilGapFR", Shape = "Cylinder", Size = Vector3.new(0.052, 0.561, 0.561), CF = {-0.95, 3.64, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "1a1c20", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "BurnerFRIn", Shape = "Cylinder", Size = Vector3.new(0.052, 0.357, 0.357), CF = {-0.95, 3.65, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "4f545e", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CoilHubFR", Shape = "Cylinder", Size = Vector3.new(0.052, 0.119, 0.119), CF = {-0.95, 3.66, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "1a1c20", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "DripRingBR", Shape = "Cylinder", Size = Vector3.new(0.052, 1.31, 1.31), CF = {-0.95, 3.61, 0.48, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "BurnerBR", Shape = "Cylinder", Size = Vector3.new(0.052, 1.15, 1.15), CF = {-0.95, 3.63, 0.48, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "4f545e", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CoilGapBR", Shape = "Cylinder", Size = Vector3.new(0.052, 0.759, 0.759), CF = {-0.95, 3.64, 0.48, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "1a1c20", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "BurnerBRIn", Shape = "Cylinder", Size = Vector3.new(0.052, 0.483, 0.483), CF = {-0.95, 3.65, 0.48, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "4f545e", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CoilHubBR", Shape = "Cylinder", Size = Vector3.new(0.052, 0.161, 0.161), CF = {-0.95, 3.66, 0.48, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "1a1c20", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Backsplash", Shape = "Block", Size = Vector3.new(4.0, 1.26, 0.4), CF = {0.0, 4.12, 1.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "BacksplashCap", Shape = "Block", Size = Vector3.new(4.1, 0.1, 0.48), CF = {0.0, 4.78, 1.29, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = true},
	{Name = "ControlPanel", Shape = "Block", Size = Vector3.new(3.76, 0.66, 0.05), CF = {0.0, 4.3, 1.08, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "Glass", T = 0.0, Collide = true},
	{Name = "KnobSkirt1", Shape = "Cylinder", Size = Vector3.new(0.052, 0.46, 0.46), CF = {1.58, 4.3, 1.035, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Knob1", Shape = "Cylinder", Size = Vector3.new(0.16, 0.34, 0.34), CF = {1.58, 4.3, 0.965, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "f7f6f1", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KnobTick1", Shape = "Block", Size = Vector3.new(0.05, 0.14, 0.05), CF = {1.58, 4.38, 0.87, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KnobSkirt2", Shape = "Cylinder", Size = Vector3.new(0.052, 0.46, 0.46), CF = {1.08, 4.3, 1.035, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Knob2", Shape = "Cylinder", Size = Vector3.new(0.16, 0.34, 0.34), CF = {1.08, 4.3, 0.965, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "f7f6f1", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KnobTick2", Shape = "Block", Size = Vector3.new(0.05, 0.14, 0.05), CF = {1.08, 4.38, 0.87, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KnobSkirt3", Shape = "Cylinder", Size = Vector3.new(0.052, 0.46, 0.46), CF = {-1.08, 4.3, 1.035, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Knob3", Shape = "Cylinder", Size = Vector3.new(0.16, 0.34, 0.34), CF = {-1.08, 4.3, 0.965, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "f7f6f1", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KnobTick3", Shape = "Block", Size = Vector3.new(0.05, 0.14, 0.05), CF = {-1.08, 4.38, 0.87, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KnobSkirt4", Shape = "Cylinder", Size = Vector3.new(0.052, 0.46, 0.46), CF = {-1.58, 4.3, 1.035, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Knob4", Shape = "Cylinder", Size = Vector3.new(0.16, 0.34, 0.34), CF = {-1.58, 4.3, 0.965, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "f7f6f1", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KnobTick4", Shape = "Block", Size = Vector3.new(0.05, 0.14, 0.05), CF = {-1.58, 4.38, 0.87, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "ClockGlass", Shape = "Block", Size = Vector3.new(0.86, 0.34, 0.05), CF = {0.0, 4.27, 1.035, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "1d2a22", Material = "Glass", T = 0.0, Collide = false},
	{Name = "ClockDigitsL", Shape = "Block", Size = Vector3.new(0.26, 0.14, 0.05), CF = {0.19, 4.27, 1.01, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "69ff00", Material = "Neon", T = 0.0, Collide = false},
	{Name = "ClockDigitsR", Shape = "Block", Size = Vector3.new(0.26, 0.14, 0.05), CF = {-0.19, 4.27, 1.01, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "69ff00", Material = "Neon", T = 0.0, Collide = false},
	{Name = "ClockColon", Shape = "Block", Size = Vector3.new(0.05, 0.12, 0.05), CF = {0.0, 4.27, 1.01, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "69ff00", Material = "Neon", T = 0.0, Collide = false},
	{Name = "PowerLight", Shape = "Cylinder", Size = Vector3.new(0.052, 0.13, 0.13), CF = {0.62, 4.51, 1.035, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "5a2020", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "OvenDoor", Shape = "Block", Size = Vector3.new(3.6, 2.02, 0.12), CF = {0.0, 1.96, -1.5, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "WindowFrame", Shape = "Block", Size = Vector3.new(2.74, 1.14, 0.05), CF = {0.0, 2.0, -1.575, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "OvenWindow", Shape = "Block", Size = Vector3.new(2.46, 0.9, 0.05), CF = {0.0, 2.0, -1.59, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "2c3038", Material = "Glass", T = 0.0, Collide = false},
	{Name = "OvenRack", Shape = "Block", Size = Vector3.new(2.46, 0.05, 0.05), CF = {0.0, 1.8, -1.605, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "1a1c20", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "OvenRoast", Shape = "Ellipsoid", Size = Vector3.new(0.86, 0.3, 0.05), CF = {0.0, 1.95, -1.615, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3b2a20", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "DoorHandle", Shape = "Cylinder", Size = Vector3.new(3.0, 0.15, 0.15), CF = {0.0, 2.74, -1.82, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "HandlePostL", Shape = "Cylinder", Size = Vector3.new(0.27, 0.1, 0.1), CF = {1.3, 2.74, -1.685, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "HandlePostR", Shape = "Cylinder", Size = Vector3.new(0.27, 0.1, 0.1), CF = {-1.3, 2.74, -1.685, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "VentStrip", Shape = "Block", Size = Vector3.new(3.0, 0.12, 0.05), CF = {0.0, 3.2, -1.465, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Drawer", Shape = "Block", Size = Vector3.new(3.6, 0.52, 0.11), CF = {0.0, 0.64, -1.495, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "DrawerHandle", Shape = "Cylinder", Size = Vector3.new(1.2, 0.09, 0.09), CF = {0.0, 0.72, -1.59, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PanBody", Shape = "Cylinder", Size = Vector3.new(0.24, 1.2, 1.2), CF = {0.95, 3.805, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "3b4350", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PanInside", Shape = "Cylinder", Size = Vector3.new(0.052, 1.04, 1.04), CF = {0.95, 3.91, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "1f2227", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PanNeck", Shape = "Cylinder", Size = Vector3.new(0.3324, 0.1, 0.1), CF = {1.3803, 3.865, -1.19102, 0.59744, -0.07242, 0.79864, 0.12033, 0.99273, -0.0, -0.79283, 0.0961, 0.60182}, Color = "3b4350", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PanGrip", Shape = "Cylinder", Size = Vector3.new(0.5459, 0.17, 0.17), CF = {1.64209, 3.925, -1.53843, 0.59532, -0.0882, 0.79864, 0.14655, 0.9892, -0.0, -0.79001, 0.11704, 0.60182}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PanGripEnd", Shape = "Ball", Size = Vector3.new(0.17, 0.17, 0.17), CF = {1.80458, 3.965, -1.75406, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "EggWhite", Shape = "Ellipsoid", Size = Vector3.new(0.66, 0.07, 0.56), CF = {0.92, 3.95, -0.59, 0.96593, 0.0, 0.25882, 0.0, 1.0, 0.0, -0.25882, 0.0, 0.96593}, Color = "fbfaf5", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "EggWhite2", Shape = "Ellipsoid", Size = Vector3.new(0.42, 0.065, 0.38), CF = {1.09, 3.948, -0.76, 0.93969, 0.0, -0.34202, 0.0, 1.0, 0.0, 0.34202, 0.0, 0.93969}, Color = "fbfaf5", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "EggYolk", Shape = "Ellipsoid", Size = Vector3.new(0.27, 0.14, 0.27), CF = {0.9, 3.985, -0.58, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2a93b", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KettleBody", Shape = "Cylinder", Size = Vector3.new(0.31, 0.86, 0.86), CF = {-0.95, 3.83, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KettleDome", Shape = "Ellipsoid", Size = Vector3.new(0.86, 0.56, 0.86), CF = {-0.95, 3.985, -0.62, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KettleLid", Shape = "Cylinder", Size = Vector3.new(0.07, 0.38, 0.38), CF = {-0.95, 4.245, -0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "KettleKnob", Shape = "Ball", Size = Vector3.new(0.16, 0.16, 0.16), CF = {-0.95, 4.325, -0.62, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KettleSpout", Shape = "Cylinder", Size = Vector3.new(0.4686, 0.14, 0.14), CF = {-1.43, 4.035, -0.62, -0.76822, 0.64018, 0.0, 0.64018, 0.76822, 0.0, 0.0, 0.0, -1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "KettlePostL", Shape = "Cylinder", Size = Vector3.new(0.365, 0.07, 0.07), CF = {-0.68, 4.305, -0.62, 0.1644, -0.0, 0.98639, 0.98639, 0.0, -0.1644, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "KettlePostR", Shape = "Cylinder", Size = Vector3.new(0.365, 0.07, 0.07), CF = {-1.22, 4.305, -0.62, -0.1644, 0.0, 0.98639, 0.98639, 0.0, 0.1644, 0.0, 1.0, -0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "KettleGrip", Shape = "Cylinder", Size = Vector3.new(0.68, 0.14, 0.14), CF = {-0.95, 4.485, -0.62, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "TowelFold", Shape = "Cylinder", Size = Vector3.new(0.54, 0.26, 0.26), CF = {-0.95, 2.76, -1.82, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0}, Color = "3f79d4", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "TowelFront", Shape = "Block", Size = Vector3.new(0.54, 0.84, 0.05), CF = {-0.95, 2.34, -1.92, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3f79d4", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "TowelStripe1", Shape = "Block", Size = Vector3.new(0.55, 0.05, 0.05), CF = {-0.95, 2.08, -1.93, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f7f6f1", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "TowelStripe2", Shape = "Block", Size = Vector3.new(0.55, 0.05, 0.05), CF = {-0.95, 1.98, -1.93, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f7f6f1", Material = "Fabric", T = 0.0, Collide = false},
}}
MODELS['SinkCounter'] = {Min = Vector3.new(-4.12, 0.0, -1.55), Max = Vector3.new(4.12, 5.046, 1.57), Attrs = {Pivot_Spout = Vector3.new(0.0, 4.3, -0.1), Pivot_SinkFloor = Vector3.new(0.0, 2.92, -0.1), Pivot_PoolA = Vector3.new(1.3, 2.92, -0.9), Pivot_PoolB = Vector3.new(-1.3, 2.92, 0.45), Pivot_Tap = Vector3.new(0.0, 4.1, 0.55), Pivot_Toaster = Vector3.new(-2.75, 5.3115, 0.05), Cost = 900.0, DisplayName = "Sink Counter"}, Parts = {
	{Name = "ToeKick", Shape = "Block", Size = Vector3.new(7.8, 0.42, 2.5), CF = {0.0, 0.21, 0.2, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "Carcass", Shape = "Block", Size = Vector3.new(7.9, 2.38, 2.75), CF = {0.0, 1.59, 0.075, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "FillL", Shape = "Block", Size = Vector3.new(2.5, 0.66, 2.75), CF = {2.7, 3.1, 0.075, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "FillR", Shape = "Block", Size = Vector3.new(2.5, 0.66, 2.75), CF = {-2.7, 3.1, 0.075, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "FillF", Shape = "Block", Size = Vector3.new(2.9, 0.66, 0.3), CF = {0.0, 3.1, -1.15, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "FillB", Shape = "Block", Size = Vector3.new(2.9, 0.66, 0.9), CF = {0.0, 3.1, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TopFront", Shape = "Block", Size = Vector3.new(8.2, 0.18, 0.55), CF = {0.0, 3.51, -1.275, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ece8df", Material = "Marble", T = 0.0, Collide = true},
	{Name = "TopBack", Shape = "Block", Size = Vector3.new(8.2, 0.18, 1.0), CF = {0.0, 3.51, 1.05, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ece8df", Material = "Marble", T = 0.0, Collide = true},
	{Name = "TopL", Shape = "Block", Size = Vector3.new(2.7, 0.18, 1.55), CF = {2.75, 3.51, -0.225, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ece8df", Material = "Marble", T = 0.0, Collide = true},
	{Name = "TopR", Shape = "Block", Size = Vector3.new(2.7, 0.18, 1.55), CF = {-2.75, 3.51, -0.225, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ece8df", Material = "Marble", T = 0.0, Collide = true},
	{Name = "BackPanel", Shape = "Block", Size = Vector3.new(7.6, 2.3, 0.05), CF = {0.0, 1.6, 1.46, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = false},
	{Name = "Backsplash", Shape = "Block", Size = Vector3.new(8.2, 1.02, 0.2), CF = {0.0, 4.1, 1.45, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "a9d3ea", Material = "CeramicTiles", T = 0.0, Collide = true},
	{Name = "BacksplashCap", Shape = "Block", Size = Vector3.new(8.24, 0.1, 0.26), CF = {0.0, 4.63, 1.44, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ece8df", Material = "Marble", T = 0.0, Collide = true},
	{Name = "BasinWallF", Shape = "Block", Size = Vector3.new(2.8, 0.77, 0.1), CF = {0.0, 3.245, -0.95, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "b9c3cd", Material = "Metal", T = 0.0, Collide = true},
	{Name = "BasinWallB", Shape = "Block", Size = Vector3.new(2.8, 0.77, 0.1), CF = {0.0, 3.245, 0.5, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "b9c3cd", Material = "Metal", T = 0.0, Collide = true},
	{Name = "BasinWallL", Shape = "Block", Size = Vector3.new(0.1, 0.77, 1.37), CF = {1.35, 3.245, -0.225, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "b9c3cd", Material = "Metal", T = 0.0, Collide = true},
	{Name = "BasinWallR", Shape = "Block", Size = Vector3.new(0.1, 0.77, 1.37), CF = {-1.35, 3.245, -0.225, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "b9c3cd", Material = "Metal", T = 0.0, Collide = true},
	{Name = "BasinFloor", Shape = "Block", Size = Vector3.new(2.62, 0.12, 1.37), CF = {0.0, 2.86, -0.225, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8d98a5", Material = "Metal", T = 0.0, Collide = true},
	{Name = "Drain", Shape = "Cylinder", Size = Vector3.new(0.052, 0.34, 0.34), CF = {0.0, 2.925, -0.1, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = false},
	{Name = "FaucetBase", Shape = "Cylinder", Size = Vector3.new(0.12, 0.5, 0.5), CF = {0.0, 3.65, 0.9, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "FaucetRiser", Shape = "Cylinder", Size = Vector3.new(0.85, 0.25, 0.25), CF = {0.0, 4.075, 0.9, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "FaucetNeck1", Shape = "Cylinder", Size = Vector3.new(0.5, 0.22, 0.22), CF = {0.0, 4.71651, 0.775, 0.0, 0.0, 1.0, 0.86603, 0.5, -0.0, -0.5, 0.86603, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "FaucetNeck2", Shape = "Cylinder", Size = Vector3.new(0.5, 0.22, 0.22), CF = {0.0, 4.93301, 0.4, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "FaucetNeck3", Shape = "Cylinder", Size = Vector3.new(0.5, 0.22, 0.22), CF = {0.0, 4.71651, 0.025, 0.0, 0.0, 1.0, -0.86603, 0.5, -0.0, -0.5, -0.86603, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "FaucetJoint1", Shape = "Ball", Size = Vector3.new(0.22, 0.22, 0.22), CF = {0.0, 4.93301, 0.65, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "FaucetJoint2", Shape = "Ball", Size = Vector3.new(0.22, 0.22, 0.22), CF = {0.0, 4.93301, 0.15, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "FaucetSpout", Shape = "Cylinder", Size = Vector3.new(0.22, 0.27, 0.27), CF = {0.0, 4.41, -0.1, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "HandleHot", Shape = "Cylinder", Size = Vector3.new(0.27, 0.14, 0.14), CF = {0.46, 3.725, 0.9, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "HandleHotCap", Shape = "Ellipsoid", Size = Vector3.new(0.3, 0.16, 0.3), CF = {0.46, 3.9, 0.9, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "HandleCold", Shape = "Cylinder", Size = Vector3.new(0.27, 0.14, 0.14), CF = {-0.46, 3.725, 0.9, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "HandleColdCap", Shape = "Ellipsoid", Size = Vector3.new(0.3, 0.16, 0.3), CF = {-0.46, 3.9, 0.9, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3f79d4", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "SoapBottle", Shape = "Cylinder", Size = Vector3.new(0.53, 0.3, 0.3), CF = {0.9, 3.855, 0.9, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "5aa845", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "SoapCap", Shape = "Cylinder", Size = Vector3.new(0.11, 0.15, 0.15), CF = {0.9, 4.165, 0.9, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "SoapNozzle", Shape = "Block", Size = Vector3.new(0.05, 0.05, 0.14), CF = {0.9, 4.19, 0.8, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "SoapLabel", Shape = "Block", Size = Vector3.new(0.18, 0.22, 0.05), CF = {0.9, 3.85, 0.765, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Sponge", Shape = "Block", Size = Vector3.new(0.52, 0.16, 0.32), CF = {1.95, 3.67, -0.45, 0.9703, 0.0, 0.24192, 0.0, 1.0, 0.0, -0.24192, 0.0, 0.9703}, Color = "f2c13d", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "SpongeScrub", Shape = "Block", Size = Vector3.new(0.52, 0.06, 0.32), CF = {1.95, 3.77, -0.45, 0.9703, 0.0, 0.24192, 0.0, 1.0, 0.0, -0.24192, 0.0, 0.9703}, Color = "5aa845", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "BowlBase", Shape = "Cylinder", Size = Vector3.new(0.07, 0.5, 0.5), CF = {2.95, 3.625, 0.35, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "3f79d4", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Bowl", Shape = "Cylinder", Size = Vector3.new(0.29, 1.1, 1.1), CF = {2.95, 3.795, 0.35, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "3f79d4", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "BowlInside", Shape = "Cylinder", Size = Vector3.new(0.052, 0.94, 0.94), CF = {2.95, 3.93, 0.35, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "2f5fae", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "FruitApple1", Shape = "Ball", Size = Vector3.new(0.38, 0.38, 0.38), CF = {3.15, 4.1, 0.47, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "FruitApple2", Shape = "Ball", Size = Vector3.new(0.36, 0.36, 0.36), CF = {2.73, 4.1, 0.51, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c7372f", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "FruitOrange", Shape = "Ball", Size = Vector3.new(0.38, 0.38, 0.38), CF = {2.95, 4.1, 0.15, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f08a30", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "FruitBanana", Shape = "Ellipsoid", Size = Vector3.new(0.8, 0.16, 0.22), CF = {2.97, 4.32, 0.4, 0.8865, -0.18843, 0.42262, 0.20791, 0.97815, 0.0, -0.41338, 0.08787, 0.90631}, Color = "f2c13d", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PopBase", Shape = "Block", Size = Vector3.new(1.555, 0.14, 1.003), CF = {-2.75, 3.66, 0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PopBody", Shape = "Block", Size = Vector3.new(1.495, 0.69, 0.943), CF = {-2.75, 4.045, 0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = true},
	{Name = "PopDome", Shape = "Cylinder", Size = Vector3.new(1.485, 0.943, 0.943), CF = {-2.75, 4.39, 0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PopStripe", Shape = "Block", Size = Vector3.new(1.515, 0.07, 0.963), CF = {-2.75, 4.1025, 0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PopSlot1", Shape = "Block", Size = Vector3.new(1.15, 0.08, 0.1725), CF = {-2.75, 4.81951, 0.48205, 1.0, 0.0, 0.0, 0.0, 0.92071, -0.39024, 0.0, 0.39024, 0.92071}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PopSlot2", Shape = "Block", Size = Vector3.new(1.15, 0.08, 0.1725), CF = {-2.75, 4.81951, 0.11795, 1.0, 0.0, 0.0, 0.0, 0.92071, 0.39024, 0.0, -0.39024, 0.92071}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PopLeverSlot", Shape = "Block", Size = Vector3.new(0.05, 0.575, 0.1), CF = {-3.5075, 4.068, 0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PopLever", Shape = "Block", Size = Vector3.new(0.26, 0.1, 0.24), CF = {-3.6275, 4.2955, 0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PopDial", Shape = "Cylinder", Size = Vector3.new(0.06, 0.23, 0.23), CF = {-3.233, 3.8725, -0.1915, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Toast1", Shape = "Block", Size = Vector3.new(0.966, 1.0, 0.115), CF = {-2.75, 4.3855, 0.484, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f0d9a0", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Toast1Crust", Shape = "Ellipsoid", Size = Vector3.new(1.035, 0.322, 0.1265), CF = {-2.75, 4.8855, 0.484, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c98a45", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Toast2", Shape = "Block", Size = Vector3.new(0.966, 1.0, 0.115), CF = {-2.75, 4.3855, 0.116, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f0d9a0", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Toast2Crust", Shape = "Ellipsoid", Size = Vector3.new(1.035, 0.322, 0.1265), CF = {-2.75, 4.8855, 0.116, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c98a45", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Door1", Shape = "Block", Size = Vector3.new(1.86, 2.12, 0.12), CF = {2.97, 1.56, -1.35, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DoorPanel1", Shape = "Block", Size = Vector3.new(1.44, 1.66, 0.05), CF = {2.97, 1.54, -1.425, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9c6a38", Material = "Wood", T = 0.0, Collide = false},
	{Name = "DoorPull1", Shape = "Cylinder", Size = Vector3.new(0.5, 0.09, 0.09), CF = {2.16, 2.2, -1.45, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Door2", Shape = "Block", Size = Vector3.new(1.92, 2.12, 0.12), CF = {1.0, 1.56, -1.35, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DoorPanel2", Shape = "Block", Size = Vector3.new(1.5, 1.66, 0.05), CF = {1.0, 1.54, -1.425, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9c6a38", Material = "Wood", T = 0.0, Collide = false},
	{Name = "DoorPull2", Shape = "Cylinder", Size = Vector3.new(0.5, 0.09, 0.09), CF = {0.16, 2.2, -1.45, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Door3", Shape = "Block", Size = Vector3.new(1.92, 2.12, 0.12), CF = {-1.0, 1.56, -1.35, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DoorPanel3", Shape = "Block", Size = Vector3.new(1.5, 1.66, 0.05), CF = {-1.0, 1.54, -1.425, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9c6a38", Material = "Wood", T = 0.0, Collide = false},
	{Name = "DoorPull3", Shape = "Cylinder", Size = Vector3.new(0.5, 0.09, 0.09), CF = {-0.16, 2.2, -1.45, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Door4", Shape = "Block", Size = Vector3.new(1.86, 2.12, 0.12), CF = {-2.97, 1.56, -1.35, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DoorPanel4", Shape = "Block", Size = Vector3.new(1.44, 1.66, 0.05), CF = {-2.97, 1.54, -1.425, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "9c6a38", Material = "Wood", T = 0.0, Collide = false},
	{Name = "DoorPull4", Shape = "Cylinder", Size = Vector3.new(0.5, 0.09, 0.09), CF = {-2.16, 2.2, -1.45, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Drawer1", Shape = "Block", Size = Vector3.new(1.86, 0.68, 0.12), CF = {2.97, 3.04, -1.35, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DrawerPull1", Shape = "Cylinder", Size = Vector3.new(0.7, 0.09, 0.09), CF = {2.97, 3.04, -1.45, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Drawer2", Shape = "Block", Size = Vector3.new(1.86, 0.68, 0.12), CF = {-2.97, 3.04, -1.35, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "DrawerPull2", Shape = "Cylinder", Size = Vector3.new(0.7, 0.09, 0.09), CF = {-2.97, 3.04, -1.45, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0}, Color = "9aa7b8", Material = "Metal", T = 0.0, Collide = false},
	{Name = "SinkFront", Shape = "Block", Size = Vector3.new(3.92, 0.68, 0.12), CF = {0.0, 3.04, -1.35, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
}}
------------------------------------------------------------------ loader
local env = getfenv(1)
local loaded = {}
local function load(name)
	local fn, err = loadstring(SOURCES[name], name)
	assert(fn, err)
	setfenv(fn, env)
	return fn()
end
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

local fails, checks = 0, 0
local function check(ok, msg)
	checks += 1
	if not ok then fails += 1 print("FAIL " .. msg) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function vnear(a, b, eps) return (a - b).Magnitude <= (eps or 1e-6) end

------------------------------------------------------------------ models (install_models.lua + BuildService.MakeTemplate)
local function Build(key, scale, hitboxCF)
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
		if pd.Shape == "Cylinder" then p.Shape = Enum.PartType.Cylinder elseif pd.Shape == "Ball" then p.Shape = Enum.PartType.Ball end
		p.Size = pd.Size * scale
		p.CFrame = CFrame.new(centre + (cf.Position - centre) * scale) * cf.Rotation
		p.Color = Color3.fromHex(pd.Color)
		p.Material = Enum.Material[pd.Material]
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
	model:SetAttribute("Category", "Home")
	local delta = hitboxCF * hitbox.CFrame:Inverse()
	for _, p in ipairs(parts) do p.CFrame = delta * p.CFrame end
	hitbox.CFrame = delta * hitbox.CFrame
	return model
end

local PlaceableBuilds = Instance.new("Folder")
PlaceableBuilds.Name = "PlaceableBuilds"
PlaceableBuilds.Parent = game:GetService("ReplicatedStorage")
local HomeFolder = Instance.new("Folder")
HomeFolder.Name = "Home"
HomeFolder.Parent = PlaceableBuilds
local YAW = CFrame.Angles(0, math.rad(37), 0)

local function Place(key, scale)
	local old = HomeFolder:FindFirstChild(key)
	if old then old:Destroy() end
	local template = Build(key, scale, CFrame.new(0, 500, 0))
	template.Parent = HomeFolder
	local model = Build(key, scale, CFrame.new(60, 3, -20) * YAW)
	model.Parent = workspace
	return model, template
end

------------------------------------------------------------------ server ctx (FunBuildService.NewContext)
local function MakeServerCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		_alive = true, _insts = {}, _cleanups = {}, _states = {}}
	function ctx:Alive() return self._alive end
	function ctx:Connect(sig, fn) return sig:Connect(function(...) if self._alive then fn(...) end end) end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:SetState(k, v) self._states[k] = true model:SetAttribute("Fun_" .. k, v) end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:Fire() end
	function ctx:HumanoidOf(player)
		if not player or player.Dead then return nil end
		return {Health = 100}, {Position = Vector3.new()}
	end
	function ctx:Prompt(part, opts)
		opts = opts or {}
		local parent = part
		if opts.Offset then
			local att = Instance.new("Attachment")
			att.Name = "FunPromptAt"
			att.Position = opts.Offset
			att.Parent = part
			self:Add(att)
			parent = att
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = opts.Name or "FunPrompt"
		prompt.ObjectText = opts.Object or base
		prompt.ActionText = opts.Action or "Use"
		prompt.HoldDuration = opts.Hold or 0
		prompt.MaxActivationDistance = opts.Distance or 10
		prompt.Parent = parent
		self:Add(prompt)
		return prompt
	end
	return ctx
end

local function StopServer(ctx)
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		check(ok, "server cleanup errored: " .. tostring(err))
	end
	for i = #ctx._insts, 1, -1 do ctx._insts[i]:Destroy() end
	for k in pairs(ctx._states) do ctx.Model:SetAttribute("Fun_" .. k, nil) end
end

local function Advance(sec)
	local steps = math.max(1, math.ceil(sec / 0.05))
	for _ = 1, steps do
		MockNow += sec / steps
		MockRunTasks()
	end
end

------------------------------------------------------------------ client ctx (FunBuildClient.NewContext)
local camera = workspace.CurrentCamera
local function MakeCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		_alive = true, _insts = {}, _cleanups = {}, _steps = {}, _everys = {}, StepRange = 180}
	function ctx:Alive() return self._alive end
	function ctx:Connect(sig, fn) return sig:Connect(function(...) if self._alive then fn(...) end end) end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn)
		model:GetAttributeChangedSignal("Fun_" .. k):Connect(function()
			if self._alive then fn(model:GetAttribute("Fun_" .. k)) end
		end)
		fn(model:GetAttribute("Fun_" .. k))
	end
	function ctx:Send() end
	function ctx:CameraDistance() return (camera.CFrame.Position - Kit.Hitbox(model).Position).Magnitude end
	function ctx:Step(fn) table.insert(self._steps, fn) end
	function ctx:Every(_, fn) table.insert(self._everys, fn) end
	function ctx:Sound(parent, id, props) local s = Kit.MakeSound(id, props) s.Parent = parent self:Add(s) return s end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = camera end
		self:Add(p)
		return p
	end
	function ctx:LocalCharacter() return nil end
	function ctx:Near() return false end
	function ctx:IsOwner() return true end
	return ctx
end

local function Run(mod, model)
	local ctx = MakeCtx(model)
	local ok, res = pcall(mod.Client, model, ctx)
	check(ok, "Client() errored: " .. tostring(res))
	if ok and type(res) == "function" then ctx:OnCleanup(res) end
	check(#ctx._steps <= 1, "at most one ctx:Step per build")
	return ctx
end
local function Everys(ctx)
	for _, fn in ipairs(ctx._everys) do
		local ok, err = pcall(fn)
		check(ok, "Every errored: " .. tostring(err))
	end
end
local frameNo = 0
local function Frames(ctx, n, dt)
	dt = dt or 1 / 60
	for _ = 1, n do
		MockNow += dt
		frameNo += 1
		if frameNo % 30 == 0 then Everys(ctx) end
		for _, fn in ipairs(ctx._steps) do
			local ok, err = pcall(fn, dt, MockNow)
			if not ok then check(false, "Step errored: " .. tostring(err)) return end
		end
		MockRunTasks()
	end
end
local function Stop(ctx)
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		check(ok, "cleanup errored: " .. tostring(err))
	end
	for i = #ctx._insts, 1, -1 do ctx._insts[i]:Destroy() end
end
local function Find(root, className, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.ClassName == className and (not name or d.Name == name) then return d end
	end
	return nil
end
local function FindAll(root, className, name)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d.ClassName == className and (not name or d.Name == name) then table.insert(out, d) end
	end
	return out
end
local function SetCamera(model, dist) rawget(camera, "_p").CFrame = CFrame.new(Kit.Hitbox(model).Position + Vector3.new(0, 0, dist)) end
local NEON, SMOOTH, GLASS = Enum.Material.Neon, Enum.Material.SmoothPlastic, Enum.Material.Glass

------------------------------------------------------------------ Stove: server
do
	local S = load("S_Stove")
	for _, scale in ipairs({1, 1.4}) do
		local model = Place("Stove", scale)
		local sctx = MakeServerCtx(model)
		local ok, err = pcall(S.Server, model, sctx)
		check(ok, "Stove Server() errored: " .. tostring(err))
		check(model:GetAttribute("Fun_On") == false, "Stove Fun_On starts false")
		local prompt = Find(model, "ProximityPrompt", "StovePrompt")
		check(prompt ~= nil, "StovePrompt exists")
		if prompt then
			check(vnear(prompt.Parent.WorldPosition, Kit.Pivot(model, "Controls"), 1e-4), "Stove prompt sits at Pivot_Controls (scale " .. scale .. ")")
			check(prompt.ActionText == "Turn on" and prompt.ObjectText == "Stove", "Stove prompt text")
			check(prompt.MaxActivationDistance >= 10 * scale - 1e-6, "Stove prompt reach grows with scale")
			local plr = {Name = "P1"}
			prompt.Triggered:Fire(plr)
			check(model:GetAttribute("Fun_On") == true and prompt.ActionText == "Turn off", "Stove toggles on")
			Advance(0.1)
			prompt.Triggered:Fire(plr)
			check(model:GetAttribute("Fun_On") == true, "Stove toggle debounced")
			Advance(0.5)
			prompt.Triggered:Fire(plr)
			check(model:GetAttribute("Fun_On") == false and prompt.ActionText == "Turn on", "Stove toggles off")
			Advance(0.5)
			prompt.Triggered:Fire({Dead = true})
			check(model:GetAttribute("Fun_On") == false, "Stove ignores a dead player")
		end
		StopServer(sctx)
		check(model:GetAttribute("Fun_On") == nil, "Stove state cleared on stop")
		model:Destroy()
	end
end

------------------------------------------------------------------ Stove: client
do
	local C = load("C_Stove")
	local scale = 1.4
	local model = Place("Stove", scale)
	SetCamera(model, 20)
	local coils = Kit.Parts(model, "Burner")
	check(#coils == 8, "Stove has 8 coil parts, got " .. #coils)
	local baseColor, baseMat = coils[1].Color, coils[1].Material
	local window, power = Kit.Part(model, "OvenWindow"), Kit.Part(model, "PowerLight")
	local windowColor = window.Color
	local positions = {}
	for _, p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") then positions[p] = p.CFrame end end
	model:SetAttribute("Fun_On", false)
	local ctx = Run(C, model)
	Frames(ctx, 60)
	check(coils[1].Material == baseMat and coils[1].Color == baseColor, "cold coils untouched")
	check(Find(camera, "Part", "StoveFX") ~= nil, "StoveFX host part in the camera")
	local shimmers = FindAll(camera, "ParticleEmitter", "HeatShimmer")
	check(#shimmers == 2, "2 heat-shimmer emitters (the free back burners), got " .. #shimmers)
	local origin = Kit.Origin(model)
	for _, e in ipairs(shimmers) do
		local att = e.Parent
		check(att.Name == "ShimmerBurnerBL" or att.Name == "ShimmerBurnerBR", "shimmer on a free burner: " .. att.Name)
		local coil = Kit.Part(model, att.Name:sub(8))
		if coil then
			local rel = origin:PointToObjectSpace(att.WorldPosition) - origin:PointToObjectSpace(coil.Position)
			check(math.abs(rel.X) < 1e-4 and math.abs(rel.Z) < 1e-4 and rel.Y > 0, "shimmer centred over its coil")
		end
		check(e.Enabled == false, "shimmer off while cold")
	end
	local steam = Find(camera, "ParticleEmitter", "Steam")
	check(steam ~= nil, "kettle steam emitter")
	if steam then
		check(vnear(steam.Parent.WorldPosition, Kit.Pivot(model, "SpoutTip"), 1e-4), "steam at Pivot_SpoutTip")
		local dir = origin:VectorToObjectSpace(steam.Parent.WorldCFrame.UpVector)
		check(dir.X < -0.5 and dir.Y > 0.4 and math.abs(dir.Z) < 1e-4, "steam blows along the spout " .. tostring(dir))
	end
	local pops = Find(camera, "ParticleEmitter", "OilPops")
	local panPart = Find(camera, "Part", "StovePanFX")
	check(pops ~= nil and panPart ~= nil, "pan effects")
	if panPart then check(vnear(panPart.Position, Kit.ToWorld(model, model:GetAttribute("Pivot_PanTop") + Vector3.new(0, 0.06, 0)), 1e-4), "pan fx over Pivot_PanTop") end
	local sizzle = Find(camera, "Sound", "Sizzle")
	check(sizzle ~= nil and sizzle.Looped == true, "looped sizzle sound")
	local lights = FindAll(camera, "PointLight")
	check(#lights == 2, "exactly 2 lights, got " .. #lights)

	--.. on
	model:SetAttribute("Fun_On", true)
	Frames(ctx, 12)
	check(coils[1].Material ~= NEON, "coils still warming at 0.2 s")
	Frames(ctx, 168) -- 3 s on
	for _, c in ipairs(coils) do check(c.Material == NEON, "coil Neon when hot: " .. c.Name) end
	local c = coils[1].Color
	check(c.R > 0.85 and c.G < 0.45 and c.B < 0.25, "coil red-orange " .. tostring(c))
	check(window.Material == NEON and window.Color.R > 0.8, "oven window glows " .. tostring(window.Color))
	check(power.Material == NEON and power.Color.R > 0.9, "power light red")
	for _, e in ipairs(shimmers) do check(e.Enabled, "shimmer on when hot") end
	check(pops and pops.Enabled, "oil pops on")
	check(sizzle and sizzle.IsPlaying, "sizzle plays near a hot pan")
	for _, l in ipairs(lights) do check(l.Enabled and l.Brightness > 0.5, "light on " .. l.Parent.Name) end
	check(steam and steam.Enabled == false, "kettle not steaming yet at 3 s")
	Frames(ctx, 300) -- 8 s on
	check(steam and steam.Enabled, "kettle steams after ~7 s")
	local click = Find(camera, "Sound", "Click")
	check(click and click.IsPlaying, "click on switch")

	--.. far away: asleep
	SetCamera(model, 220)
	Everys(ctx)
	check(pops and not pops.Enabled and sizzle and not sizzle.IsPlaying, "particles + sizzle asleep far away")
	for _, l in ipairs(lights) do check(not l.Enabled, "lights off far away") end
	SetCamera(model, 20)
	Everys(ctx)
	Frames(ctx, 2)
	check(pops and pops.Enabled and sizzle and sizzle.IsPlaying, "awake again near")

	--.. off: cools down
	model:SetAttribute("Fun_On", false)
	Frames(ctx, 60)
	check(coils[1].Material == NEON, "coils still cooling 1 s after off")
	check(power.Material == SMOOTH, "power light off at once")
	Frames(ctx, 200)
	for _, cc in ipairs(coils) do check(cc.Material == baseMat and cc.Color == baseColor, "cooled coil restored: " .. cc.Name) end
	check(window.Material == GLASS and window.Color == windowColor, "window restored")
	check(sizzle and not sizzle.IsPlaying, "sizzle stopped")
	for _, l in ipairs(lights) do check(not l.Enabled, "light off when cold") end
	for _, e in ipairs(shimmers) do check(not e.Enabled, "shimmer off when cold") end

	--.. streamed in while on: hot at once; cleanup restores
	model:SetAttribute("Fun_On", true)
	Frames(ctx, 200)
	Stop(ctx)
	check(coils[1].Material == baseMat and coils[1].Color == baseColor, "cleanup restores the coils")
	check(window.Material == GLASS and power.Material == SMOOTH, "cleanup restores window + power light")
	check(Find(camera, "Part", "StoveFX") == nil and Find(camera, "Part", "StovePanFX") == nil, "fx parts gone after cleanup")
	local ctx2 = Run(C, model)
	Frames(ctx2, 1)
	check(coils[1].Material == NEON and coils[1].Color.R > 0.85, "streams in already hot")
	check(power.Material == NEON, "streams in with the power light on")
	Stop(ctx2)
	local moved = 0
	for p, cf in pairs(positions) do if p.Parent and not vnear(p.CFrame.Position, cf.Position, 1e-9) then moved += 1 end end
	check(moved == 0, "the stove never moves a part")
	print(("Stove client: %d coils, %d shimmers, lights %d"):format(#coils, #shimmers, #lights))
	model:Destroy()
end

------------------------------------------------------------------ SinkCounter: server
do
	local S = load("S_SinkCounter")
	local model = Place("SinkCounter", 1)
	local sctx = MakeServerCtx(model)
	local ok, err = pcall(S.Server, model, sctx)
	check(ok, "SinkCounter Server() errored: " .. tostring(err))
	check(model:GetAttribute("Fun_Tap") == false and model:GetAttribute("Fun_ToastAt") == 0, "sink states start idle")
	local tap = Find(model, "ProximityPrompt", "TapPrompt")
	local toast = Find(model, "ProximityPrompt", "ToastPrompt")
	check(tap ~= nil and toast ~= nil, "both prompts exist")
	if tap and toast then
		check(vnear(tap.Parent.WorldPosition, Kit.Pivot(model, "Tap"), 1e-4), "tap prompt at Pivot_Tap")
		check(vnear(toast.Parent.WorldPosition, Kit.Pivot(model, "Toaster"), 1e-4), "toast prompt at Pivot_Toaster")
		check(tap.ActionText == "Tap on" and toast.ActionText == "Make toast", "prompt texts")
		local plr = {Name = "P1"}
		tap.Triggered:Fire(plr)
		check(model:GetAttribute("Fun_Tap") == true and tap.ActionText == "Tap off", "tap on")
		Advance(60)
		check(model:GetAttribute("Fun_Tap") == true, "tap still running at 60 s")
		Advance(61)
		check(model:GetAttribute("Fun_Tap") == false and tap.ActionText == "Tap on", "tap shuts itself off after 120 s")
		--.. on, off, on: the first run's auto-off must not cut the second run short
		tap.Triggered:Fire(plr)
		Advance(100)
		tap.Triggered:Fire(plr)
		Advance(1)
		tap.Triggered:Fire(plr)
		check(model:GetAttribute("Fun_Tap") == true, "tap on again")
		Advance(25)
		check(model:GetAttribute("Fun_Tap") == true, "old auto-off ignored")
		Advance(100)
		check(model:GetAttribute("Fun_Tap") == false, "new auto-off after 120 s")

		local t0 = MockNow
		toast.Triggered:Fire(plr)
		check(near(model:GetAttribute("Fun_ToastAt"), t0 + 4, 1e-6), "ToastAt = now + 4")
		check(toast.Enabled == true and toast.ActionText == "Toasting...", "toast prompt reads Toasting... and is never disabled")
		Advance(2)
		toast.Triggered:Fire(plr)
		check(near(model:GetAttribute("Fun_ToastAt"), t0 + 4, 1e-6), "a press while toasting is ignored")
		check(toast.ActionText == "Toasting...", "still Toasting... mid-cycle")
		Advance(5)
		check(toast.Enabled == true and toast.ActionText == "Toasting...", "still Toasting... while the toast is up")
		Advance(2.8)
		check(toast.Enabled == true and toast.ActionText == "Make toast", "toast prompt text back after the cycle")
		toast.Triggered:Fire(plr)
		check(near(model:GetAttribute("Fun_ToastAt"), MockNow + 4, 1e-6), "a new cycle starts")
		--.. a new cycle that starts before the old reset task runs must keep "Toasting..." (stale reset ignored)
		local t1 = MockNow
		MockNow = t1 + 9.65 -- past the guard, but the cycle's reset task (due t1 + 9.6) has not run yet
		toast.Triggered:Fire(plr)
		check(near(model:GetAttribute("Fun_ToastAt"), MockNow + 4, 1e-6), "back-to-back cycle starts")
		MockRunTasks() -- now the first cycle's reset runs: it must see a different ToastAt and do nothing
		check(toast.ActionText == "Toasting...", "a stale reset does not relabel a running cycle")
		Advance(9.7)
		check(toast.ActionText == "Make toast", "the second cycle's own reset relabels it")
		check(toast.Enabled == true, "the server never touched Enabled")
		toast.Triggered:Fire({Dead = true})
	end
	StopServer(sctx)
	check(model:GetAttribute("Fun_Tap") == nil and model:GetAttribute("Fun_ToastAt") == nil, "sink states cleared on stop")
	Advance(20) -- a pending re-enable must not error after stop
	model:Destroy()
end

------------------------------------------------------------------ SinkCounter: client
do
	local C = load("C_SinkCounter")
	local scale = 1.25
	local model, template = Place("SinkCounter", scale)
	SetCamera(model, 20)
	model:SetAttribute("Fun_Tap", false)
	model:SetAttribute("Fun_ToastAt", 0)
	local origin = Kit.Origin(model)
	local up = origin.UpVector
	local hitbox, th = Kit.Hitbox(model), Kit.Hitbox(template)
	local function TemplateRest(name)
		return hitbox.CFrame * th.CFrame:ToObjectSpace(template:FindFirstChild(name).CFrame)
	end
	local toast1, crust2, lever = Kit.Part(model, "Toast1"), Kit.Part(model, "Toast2Crust"), Kit.Part(model, "PopLever")
	local slot = Kit.Part(model, "PopSlot1")
	local breadColor, slotColor = toast1.Color, slot.Color
	local rest1, restC2, restLever = TemplateRest("Toast1"), TemplateRest("Toast2Crust"), TemplateRest("PopLever")
	check(vnear(rest1.Position, toast1.Position, 1e-6), "template rest == placed rest")
	toast1.CFrame = rest1 + Vector3.new(0, 0.5, 0) -- a stale pose some earlier run left behind
	local ctx = Run(C, model)
	check(vnear(toast1.Position, rest1.Position, 1e-5), "the run starts from the template pose")
	Frames(ctx, 10)
	local stream, pool = Find(camera, "Part", "SinkStream"), Find(camera, "Part", "SinkPool")
	check(stream ~= nil and pool ~= nil, "stream + pool parts")
	check(stream.Transparency == 1 and pool.Transparency == 1, "no water while the tap is off")

	--.. tap on
	local spout, floor = Kit.Pivot(model, "Spout"), Kit.Pivot(model, "SinkFloor")
	model:SetAttribute("Fun_Tap", true)
	Frames(ctx, 30)
	check(stream.Transparency < 0.5, "stream visible")
	local axis = stream.CFrame.RightVector
	local top = stream.Position - axis * (stream.Size.X / 2)
	local bottom = stream.Position + axis * (stream.Size.X / 2)
	check(vnear(top, spout, 1e-3), "stream starts at Pivot_Spout")
	local drop = (bottom - floor):Dot(up)
	check(drop >= -1e-3 and drop <= 0.2 * scale + 1e-3, ("stream ends on the water (%.3f over the floor)"):format(drop))
	local side = (bottom - floor) - up * drop
	check(side.Magnitude < 1e-3, "stream lands under the spout")
	check(near(stream.Size.Y, 0.13 * scale, 0.02 * scale), "stream width " .. stream.Size.Y)
	Frames(ctx, 420) -- 7.5 s
	check(near(pool.Size.Y, 0.2 * scale, 1e-3), "pool full: " .. pool.Size.Y)
	local poolTop = (pool.Position + up * (pool.Size.Y / 2) - floor):Dot(up)
	check(near(poolTop, 0.2 * scale, 1e-3), "pool surface 0.2 over the floor")
	local a, b = Kit.Pivot(model, "PoolA"), Kit.Pivot(model, "PoolB")
	local mid = (a + b) / 2
	check(near((pool.Position - mid):Dot(origin.RightVector), 0, 1e-3) and near((pool.Position - mid):Dot(origin.LookVector), 0, 1e-3), "pool centred in the basin")
	check(near(pool.Size.X, math.abs(origin:PointToObjectSpace(a).X - origin:PointToObjectSpace(b).X), 1e-3), "pool width = basin")
	bottom = stream.Position + stream.CFrame.RightVector * (stream.Size.X / 2)
	check(near((bottom - floor):Dot(up), 0.2 * scale, 1e-3), "stream now ends on the pool surface")
	local spray = Find(camera, "ParticleEmitter", "Spray")
	local loop = Find(camera, "Sound", "WaterLoop")
	check(spray and spray.Enabled, "splash on")
	check(spray and near((spray.Parent.WorldPosition - floor):Dot(up), (0.2 + 0.02) * scale, 1e-3), "splash rides the pool surface")
	check(loop and loop.IsPlaying and loop.Looped, "water loop playing near")
	SetCamera(model, 200)
	Everys(ctx)
	check(loop and not loop.IsPlaying and spray and not spray.Enabled, "water asleep far away")
	SetCamera(model, 20)
	Everys(ctx)

	--.. tap off
	model:SetAttribute("Fun_Tap", false)
	Frames(ctx, 30)
	check(stream.Transparency == 1, "stream gone 0.5 s after the tap closes")
	Frames(ctx, 240)
	check(pool.Transparency == 1, "pool drained")
	check(loop and not loop.IsPlaying and spray and not spray.Enabled, "splash + loop off")

	--.. toast cycle
	local popAt = MockNow + 4
	model:SetAttribute("Fun_ToastAt", popAt)
	local click = Find(camera, "Sound", "Click")
	check(click and click.IsPlaying, "lever click")
	Frames(ctx, 30) -- 0.5 s in
	local function Off(part, restCF) return (part.Position - restCF.Position):Dot(up) / scale end
	check(near(Off(lever, restLever), -0.3, 1e-3), "lever down 0.3: " .. Off(lever, restLever))
	check(near(Off(toast1, rest1), -0.14, 1e-3), "toast sinks 0.14: " .. Off(toast1, rest1))
	Frames(ctx, 90) -- 2 s in
	check(slot.Material == NEON, "slots glow while toasting")
	local smoke = Find(camera, "ParticleEmitter", "ToastSmoke")
	check(smoke and smoke.Enabled, "toast smoke near the end")
	local pop, ding = Find(camera, "Sound", "ToasterPop"), Find(camera, "Sound", "Ding")
	check(pop and not pop.IsPlaying, "no pop before the time")
	while MockNow < popAt + 0.5 do Frames(ctx, 1) end
	check(pop and pop.IsPlaying and ding and ding.IsPlaying, "pop + ding at ToastAt")
	check(near(Off(toast1, rest1), 0.8, 1e-3) and near(Off(crust2, restC2), 0.8, 1e-3), "toast up 0.8: " .. Off(toast1, rest1))
	check(near(Off(lever, restLever), 0, 1e-3), "lever back up")
	check(toast1.Color.R < breadColor.R - 0.05, "toast is golden")
	local maxOff = 0
	while MockNow < popAt + 5.8 do
		Frames(ctx, 1)
		maxOff = math.max(maxOff, Off(toast1, rest1))
	end
	check(maxOff <= 0.8 + 1e-3, "no overshoot after settling")
	check(near(Off(toast1, rest1), 0, 1e-3), "toast back down after 5 s")
	while MockNow < popAt + 8 do Frames(ctx, 1) end
	check(vnear(toast1.Position, rest1.Position, 1e-5) and toast1.Color == breadColor, "toast at rest, bread colour again")
	check(slot.Material ~= NEON and slot.Color == slotColor, "slots cold again")

	--.. streamed in mid-pop: posed at once, no late sounds; cleanup mid-pop restores
	Stop(ctx)
	model:SetAttribute("Fun_ToastAt", MockNow - 1)
	local ctx2 = Run(C, model)
	Frames(ctx2, 3)
	local pop2 = Find(camera, "Sound", "ToasterPop")
	check(near(Off(toast1, rest1), 0.8, 1e-3), "late joiner sees the toast up")
	check(pop2 and not pop2.IsPlaying, "late joiner hears no pop")
	Stop(ctx2)
	check(vnear(toast1.Position, rest1.Position, 1e-5) and toast1.Color == breadColor, "cleanup mid-pop restores the toast")
	check(vnear(lever.Position, restLever.Position, 1e-5), "cleanup restores the lever")
	check(Find(camera, "Part", "SinkStream") == nil and Find(camera, "Part", "SinkFX") == nil, "local parts gone after cleanup")

	--.. streamed in with the tap running: full stream + pool at once
	model:SetAttribute("Fun_Tap", true)
	model:SetAttribute("Fun_ToastAt", 0)
	local ctx3 = Run(C, model)
	Frames(ctx3, 1)
	local stream3, pool3 = Find(camera, "Part", "SinkStream"), Find(camera, "Part", "SinkPool")
	check(stream3 and stream3.Transparency < 0.5 and pool3 and near(pool3.Size.Y, 0.2 * scale, 1e-3), "streams in with water running")
	Stop(ctx3)
	model:Destroy()
end

print(("HomeKitchenB tests: %d checks, %d failed"):format(checks, fails))
