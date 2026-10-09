--!nocheck
-- Minimal Roblox mock for running fun-build behaviours headless (Vector3/Vector2/CFrame maths real, Instances as
-- property bags). Copied from tests/GardenLights/mock.luau (2026-09-24) and extended for the HomeHearth package:
-- Color3 with Lerp / fromHex, 12-number CFrame.new, SpotLight / Decal / ProximityPrompt, attribute-changed signals.

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
		RotSpeed = 1, Enabled = 1, Parent = 1, Shape = 1, ShapeStyle = 1, ZOffset = 1, LockedToPart = 1, WindAffectsDrag = 1,
		TimeScale = 1, VelocityInheritance = 1},
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
SOURCES['C_DiningTable'] = [======[
--[[
	DiningTable  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the DINING TABLE (fun-builds/CONTRACT.md, package HomeDining). The centrepiece candle is lit:
	a warm PointLight sits in the Neon "CandleFlame" part and, every frame while the camera is near, the flame
	flickers - it stretches / narrows from its foot, sways a few degrees, shifts between orange and yellow -
	and the light's brightness and range breathe with it (layered math.noise on the server clock folded to
	% 1000 - raw epoch seconds are too big for math.noise's 32-bit floats - seeded per table so two tables
	never flicker in step). Purely cosmetic and local; the flame's authored CFrame / Size / Color are stored
	relative to the Hitbox and put back on cleanup (moved, sold, broken, streamed out).
	The seats are server-side (behaviours/server/DiningTable.lua).
]]

--..Config..--
local LIGHT_COLOR = Color3.fromRGB(255, 172, 92)
local LIGHT_RANGE = 10          -- studs at scale 1
local LIGHT_BRIGHTNESS = 1.3
local FLAME_HOT = Color3.fromRGB(255, 214, 110)
local FLAME_WARM = Color3.fromRGB(255, 150, 60)
local STRETCH = 0.2             -- flame height wobble (fraction)
local SWAY_DEG = 7

local B = {}
B.Keys = {"DiningTable"}
B.StepRange = 140

function B.Client(model, ctx)
	local Kit = ctx.Kit
	local flame = Kit.Part(model, "CandleFlame")
	local hitbox = Kit.Hitbox(model)
	if not (flame and hitbox) then return end

	--..Rest pose (relative to the hitbox, so a restore after a move lands in the right place)..--
	local rest = hitbox.CFrame:ToObjectSpace(flame.CFrame)
	local restSize = flame.Size
	local restColor = flame.Color
	local seed = (hitbox.Position.X * 0.173 + hitbox.Position.Z * 0.311) % 97

	--..Glow..--
	local light = Instance.new("PointLight")
	light.Name = "CandleGlow"
	light.Color = LIGHT_COLOR
	light.Brightness = LIGHT_BRIGHTNESS
	light.Range = LIGHT_RANGE * ctx.Scale
	light.Shadows = false
	light.Parent = flame
	ctx:Add(light)

	--..Flicker..--
	ctx:Step(function(_, now)
		if not (flame.Parent and hitbox.Parent) then return end
		--.. math.noise works in 32-bit floats: raw server time (~1.8e9) loses its fraction and the flame
		--.. freezes, so fold the clock into a short cycle first (one invisible jump every 1000 s)
		local t = now % 1000
		local n1 = math.clamp(math.noise(t * 7.3, seed, 0.5) * 2, -1, 1)
		local n2 = math.clamp(math.noise(t * 12.9, seed + 17.7, 0.5) * 2, -1, 1)
		local n3 = math.clamp(math.noise(t * 2.7, seed + 41.3, 0.5) * 2, -1, 1)
		local sy = 1 + STRETCH * (0.7 * n1 + 0.3 * n2)
		local sxz = 1 - 0.08 * n1 + 0.04 * n3
		local size = Vector3.new(restSize.X * sxz, restSize.Y * sy, restSize.Z * sxz)
		--.. grow from the foot of the flame (the wick), leaning a little
		local foot = hitbox.CFrame * rest * CFrame.new(0, -restSize.Y * 0.5, 0)
		local sway = CFrame.Angles(math.rad(SWAY_DEG * n3), 0, math.rad(SWAY_DEG * n2))
		flame.Size = size
		flame.CFrame = foot * sway * CFrame.new(0, size.Y * 0.5, 0)
		flame.Color = FLAME_WARM:Lerp(FLAME_HOT, math.clamp(0.55 + 0.45 * n1, 0, 1))
		light.Brightness = LIGHT_BRIGHTNESS * (1 + 0.3 * n1 + 0.12 * n2)
		light.Range = LIGHT_RANGE * ctx.Scale * (1 + 0.08 * n2)
	end)

	return function()
		if flame.Parent and hitbox.Parent then
			flame.Size = restSize
			flame.CFrame = hitbox.CFrame * rest
			flame.Color = restColor
		end
	end
end

return B
]======]
SOURCES['S_DiningTable'] = [======[
--[[
	DiningTable  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the DINING TABLE (fun-builds/CONTRACT.md, package HomeDining): a wooden dining set - a 5 x 4
	table with one chair on each side (two long sides + both ends), each pulled out far enough that a seated
	avatar's torso clears the table edge. Every chair is a real seat: an invisible Seat (ctx:Seat) sits on each
	cushion - Pivot_Seat1..4 = the top of the cushion, where the hips rest - with the usual "Sit" prompt (a taken
	seat hides its prompt). Anyone may sit (like a bench).
	Facing: the model authors where each sitter looks (Pivot_Seat<N>Face = a point straight in front of the
	seat, over the table), so the seats follow the model whatever its layout; without it a seat faces the table
	centre. The candle's flickering flame + glow are purely cosmetic and live in the client half.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local SEAT_COUNT = 4
local SEAT_SIZE = Vector3.new(1.6, 0.4, 1.6) -- X/Z scale with the build, Y stays (the hips rest on the top face)
local PROMPT_DISTANCE = 7

local B = {}
B.Keys = {"DiningTable"}

function B.Server(model, ctx)
	local origin = Kit.Origin(model)
	local up = origin.UpVector
	local scale = ctx.Scale
	local size = Vector3.new(SEAT_SIZE.X * scale, SEAT_SIZE.Y, SEAT_SIZE.Z * scale)

	for i = 1, SEAT_COUNT do
		local authored = model:GetAttribute("Pivot_Seat" .. i)
		if typeof(authored) == "Vector3" then
			local top = Kit.ToWorld(model, authored)
			--.. look where the model says (Pivot_Seat<N>Face), else at the table centre; always level
			local face = model:GetAttribute("Pivot_Seat" .. i .. "Face")
			local target = if typeof(face) == "Vector3"
				then Kit.ToWorld(model, face)
				else Kit.ToWorld(model, Vector3.new(0, authored.Y, 0))
			local look = target - top
			look -= up * look:Dot(up)
			if look.Magnitude < 1e-3 then look = origin.LookVector end
			local pos = top - up * (size.Y * 0.5)
			local cf = CFrame.lookAt(pos, pos + look.Unit, up)
			ctx:Seat(cf, {
				Name = "DiningSeat" .. i,
				Size = size,
				Object = "Dining Chair",
				Distance = PROMPT_DISTANCE,
			})
		end
	end
end

return B
]======]
MODELS = {}
MODELS['DiningTable'] = {Attrs = {Pivot_Seat1 = Vector3.new(3.2, 2.13, 0.0), Pivot_Seat1Face = Vector3.new(2.2, 2.13, -0.0), Pivot_Seat2 = Vector3.new(-3.2, 2.13, 0.0), Pivot_Seat2Face = Vector3.new(-2.2, 2.13, -0.0), Pivot_Seat3 = Vector3.new(0.0, 2.13, -3.1), Pivot_Seat3Face = Vector3.new(-0.0, 2.13, -2.1), Pivot_Seat4 = Vector3.new(0.0, 2.13, 3.1), Pivot_Seat4Face = Vector3.new(0.0, 2.13, 2.1), Pivot_Candle = Vector3.new(-0.72, 4.36, 0.0), Cost = 900.0, DisplayName = "Dining Table"}, Parts = {
	{Name = "TableTop", Shape = "Block", Size = Vector3.new(5.0, 0.22, 4.0), CF = {0.0, 3.09, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TableApron", Shape = "Block", Size = Vector3.new(2.8, 0.14, 2.2), CF = {0.0, 2.93, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TableLeg1", Shape = "Cylinder", Size = Vector3.new(2.7, 0.44, 0.44), CF = {2.0, 1.65, -1.5, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TableFoot1", Shape = "Cylinder", Size = Vector3.new(0.32, 0.58, 0.58), CF = {2.0, 0.16, -1.5, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TableLeg2", Shape = "Cylinder", Size = Vector3.new(2.7, 0.44, 0.44), CF = {-2.0, 1.65, -1.5, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TableFoot2", Shape = "Cylinder", Size = Vector3.new(0.32, 0.58, 0.58), CF = {-2.0, 0.16, -1.5, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TableLeg3", Shape = "Cylinder", Size = Vector3.new(2.7, 0.44, 0.44), CF = {2.0, 1.65, 1.5, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TableFoot3", Shape = "Cylinder", Size = Vector3.new(0.32, 0.58, 0.58), CF = {2.0, 0.16, 1.5, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TableLeg4", Shape = "Cylinder", Size = Vector3.new(2.7, 0.44, 0.44), CF = {-2.0, 1.65, 1.5, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TableFoot4", Shape = "Cylinder", Size = Vector3.new(0.32, 0.58, 0.58), CF = {-2.0, 0.16, 1.5, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Runner", Shape = "Block", Size = Vector3.new(5.04, 0.05, 1.5), CF = {0.0, 3.215, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "RunnerFlapL", Shape = "Block", Size = Vector3.new(0.05, 0.64, 1.5), CF = {2.545, 2.92, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "RunnerFlapR", Shape = "Block", Size = Vector3.new(0.05, 0.64, 1.5), CF = {-2.545, 2.92, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "RunnerStitchF", Shape = "Block", Size = Vector3.new(4.9, 0.05, 0.06), CF = {0.0, 3.25, -0.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "RunnerStitchB", Shape = "Block", Size = Vector3.new(4.9, 0.05, 0.06), CF = {0.0, 3.25, 0.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "Chair1Seat", Shape = "Block", Size = Vector3.new(1.7, 0.22, 1.6), CF = {3.2, 1.87, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair1Cushion", Shape = "Ellipsoid", Size = Vector3.new(1.5, 0.32, 1.4), CF = {3.16, 1.98, -0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "d9443c", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "Chair1LegFL", Shape = "Block", Size = Vector3.new(0.24, 1.76, 0.24), CF = {2.57, 0.88, -0.68, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair1PostL", Shape = "Block", Size = Vector3.new(0.26, 4.6, 0.26), CF = {3.86, 2.3, -0.68, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair1LegFR", Shape = "Block", Size = Vector3.new(0.24, 1.76, 0.24), CF = {2.57, 0.88, 0.68, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair1PostR", Shape = "Block", Size = Vector3.new(0.26, 4.6, 0.26), CF = {3.86, 2.3, 0.68, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair1Crest", Shape = "Cylinder", Size = Vector3.new(1.96, 0.36, 0.36), CF = {3.86, 4.52, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair1Splat", Shape = "Block", Size = Vector3.new(1.14, 1.8, 0.12), CF = {3.88, 3.46, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair2Seat", Shape = "Block", Size = Vector3.new(1.7, 0.22, 1.6), CF = {-3.2, 1.87, 0.0, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair2Cushion", Shape = "Ellipsoid", Size = Vector3.new(1.5, 0.32, 1.4), CF = {-3.16, 1.98, -0.0, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, Color = "d9443c", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "Chair2LegFL", Shape = "Block", Size = Vector3.new(0.24, 1.76, 0.24), CF = {-2.57, 0.88, 0.68, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair2PostL", Shape = "Block", Size = Vector3.new(0.26, 4.6, 0.26), CF = {-3.86, 2.3, 0.68, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair2LegFR", Shape = "Block", Size = Vector3.new(0.24, 1.76, 0.24), CF = {-2.57, 0.88, -0.68, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair2PostR", Shape = "Block", Size = Vector3.new(0.26, 4.6, 0.26), CF = {-3.86, 2.3, -0.68, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair2Crest", Shape = "Cylinder", Size = Vector3.new(1.96, 0.36, 0.36), CF = {-3.86, 4.52, 0.0, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair2Splat", Shape = "Block", Size = Vector3.new(1.14, 1.8, 0.12), CF = {-3.88, 3.46, 0.0, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair3Seat", Shape = "Block", Size = Vector3.new(1.7, 0.22, 1.6), CF = {0.0, 1.87, -3.1, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair3Cushion", Shape = "Ellipsoid", Size = Vector3.new(1.5, 0.32, 1.4), CF = {-0.0, 1.98, -3.06, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0}, Color = "d9443c", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "Chair3LegFL", Shape = "Block", Size = Vector3.new(0.24, 1.76, 0.24), CF = {-0.68, 0.88, -2.47, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair3PostL", Shape = "Block", Size = Vector3.new(0.26, 4.6, 0.26), CF = {-0.68, 2.3, -3.76, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair3LegFR", Shape = "Block", Size = Vector3.new(0.24, 1.76, 0.24), CF = {0.68, 0.88, -2.47, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair3PostR", Shape = "Block", Size = Vector3.new(0.26, 4.6, 0.26), CF = {0.68, 2.3, -3.76, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair3Crest", Shape = "Cylinder", Size = Vector3.new(1.96, 0.36, 0.36), CF = {0.0, 4.52, -3.76, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair3Splat", Shape = "Block", Size = Vector3.new(1.14, 1.8, 0.12), CF = {0.0, 3.46, -3.78, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair4Seat", Shape = "Block", Size = Vector3.new(1.7, 0.22, 1.6), CF = {0.0, 1.87, 3.1, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair4Cushion", Shape = "Ellipsoid", Size = Vector3.new(1.5, 0.32, 1.4), CF = {0.0, 1.98, 3.06, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "Chair4LegFL", Shape = "Block", Size = Vector3.new(0.24, 1.76, 0.24), CF = {0.68, 0.88, 2.47, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair4PostL", Shape = "Block", Size = Vector3.new(0.26, 4.6, 0.26), CF = {0.68, 2.3, 3.76, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair4LegFR", Shape = "Block", Size = Vector3.new(0.24, 1.76, 0.24), CF = {-0.68, 0.88, 2.47, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair4PostR", Shape = "Block", Size = Vector3.new(0.26, 4.6, 0.26), CF = {-0.68, 2.3, 3.76, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair4Crest", Shape = "Cylinder", Size = Vector3.new(1.96, 0.36, 0.36), CF = {0.0, 4.52, 3.76, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Chair4Splat", Shape = "Block", Size = Vector3.new(1.14, 1.8, 0.12), CF = {0.0, 3.46, 3.78, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "PlateRim1", Shape = "Cylinder", Size = Vector3.new(0.05, 1.1, 1.1), CF = {1.8, 3.26, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "3f79d4", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Plate1", Shape = "Cylinder", Size = Vector3.new(0.05, 0.84, 0.84), CF = {1.8, 3.27, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Cucumber1", Shape = "Ellipsoid", Size = Vector3.new(0.62, 0.2, 0.2), CF = {1.8, 3.37, 0.0, -0.57358, 0.0, 0.81915, 0.0, 1.0, 0.0, -0.81915, 0.0, -0.57358}, Color = "5aa845", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PlateRim2", Shape = "Cylinder", Size = Vector3.new(0.05, 1.1, 1.1), CF = {-1.8, 3.26, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "3f79d4", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Plate2", Shape = "Cylinder", Size = Vector3.new(0.05, 0.84, 0.84), CF = {-1.8, 3.27, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Cucumber2", Shape = "Ellipsoid", Size = Vector3.new(0.62, 0.2, 0.2), CF = {-1.8, 3.37, 0.0, 0.57358, 0.0, -0.81915, 0.0, 1.0, 0.0, 0.81915, 0.0, 0.57358}, Color = "5aa845", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PlateRim3", Shape = "Cylinder", Size = Vector3.new(0.05, 1.1, 1.1), CF = {0.0, 3.22, -1.35, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "3f79d4", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Plate3", Shape = "Cylinder", Size = Vector3.new(0.05, 0.84, 0.84), CF = {0.0, 3.23, -1.35, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Cucumber3", Shape = "Ellipsoid", Size = Vector3.new(0.62, 0.2, 0.2), CF = {0.0, 3.33, -1.35, -0.81915, 0.0, -0.57358, 0.0, 1.0, 0.0, 0.57358, 0.0, -0.81915}, Color = "5aa845", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PlateRim4", Shape = "Cylinder", Size = Vector3.new(0.05, 1.1, 1.1), CF = {0.0, 3.22, 1.35, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "3f79d4", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Plate4", Shape = "Cylinder", Size = Vector3.new(0.05, 0.84, 0.84), CF = {0.0, 3.23, 1.35, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Cucumber4", Shape = "Ellipsoid", Size = Vector3.new(0.62, 0.2, 0.2), CF = {0.0, 3.33, 1.35, 0.81915, 0.0, 0.57358, 0.0, 1.0, 0.0, -0.57358, 0.0, 0.81915}, Color = "5aa845", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CandleBase", Shape = "Cylinder", Size = Vector3.new(0.08, 0.62, 0.62), CF = {-0.72, 3.28, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "CandleStem", Shape = "Cylinder", Size = Vector3.new(0.29, 0.34, 0.34), CF = {-0.72, 3.455, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Candle", Shape = "Cylinder", Size = Vector3.new(0.78, 0.26, 0.26), CF = {-0.72, 3.97, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CandleFlame", Shape = "Ellipsoid", Size = Vector3.new(0.18, 0.34, 0.18), CF = {-0.72, 4.52, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ffb347", Material = "Neon", T = 0.0, Collide = false},
	{Name = "Vase", Shape = "Ellipsoid", Size = Vector3.new(0.7, 0.76, 0.7), CF = {0.72, 3.6, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3f79d4", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "VaseNeck", Shape = "Cylinder", Size = Vector3.new(0.35, 0.34, 0.34), CF = {0.72, 4.015, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "3f79d4", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "VaseLeafL", Shape = "Ellipsoid", Size = Vector3.new(0.14, 0.5, 0.24), CF = {0.92, 4.33, 0.02, 0.78801, 0.61566, 0.0, -0.61566, 0.78801, 0.0, 0.0, 0.0, 1.0}, Color = "3f8f3a", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "VaseLeafR", Shape = "Ellipsoid", Size = Vector3.new(0.14, 0.5, 0.24), CF = {0.52, 4.33, -0.02, 0.78801, -0.61566, 0.0, 0.61566, 0.78801, 0.0, 0.0, 0.0, 1.0}, Color = "3f8f3a", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "FlowerRed", Shape = "Ball", Size = Vector3.new(0.34, 0.34, 0.34), CF = {0.84, 4.61, 0.06, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "FlowerYellow", Shape = "Ball", Size = Vector3.new(0.3, 0.3, 0.3), CF = {0.52, 4.51, -0.08, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2c13d", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "FlowerWhite", Shape = "Ball", Size = Vector3.new(0.28, 0.28, 0.28), CF = {0.74, 4.49, -0.24, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
}}
------------------------------------------------------------------ HomeDining headless tests (DiningTable fix pass, 2026-09-24)
-- run: py tests/HomeDining/gen.py   (mock.luau + module sources + parts.json models + this file -> run.luau)

------------------------------------------------------------------ loader (os.clock / os.date are controllable)
local env = getfenv(1)
local realOs = os
MockClock = 1000
MockDate = {hour = 3, min = 30, sec = 0}
env.os = setmetatable({
	clock = function() return MockClock end,
	date = function(fmt, t) if fmt == "*t" then return table.clone(MockDate) end return realOs.date(fmt, t) end,
}, {__index = realOs})
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
local FunAssets = require({Name = "FunAssets"})

local fails, checks = 0, 0
local function check(ok, msg)
	checks += 1
	if not ok then fails += 1 print("FAIL " .. msg) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function vnear(a, b, eps) return (a - b).Magnitude <= (eps or 1e-6) end

------------------------------------------------------------------ template + placement (BuildService.MakeTemplate)
local function halfExtent(size, m, axis)
	-- m row-major 3x3: world axis `axis` row = m[axis*3+1 .. axis*3+3]
	local r = axis * 3
	return 0.5 * (math.abs(m[r + 1]) * size.X + math.abs(m[r + 2]) * size.Y + math.abs(m[r + 3]) * size.Z)
end
local function MakePlaced(key, scale, placeCF)
	local data = MODELS[key]
	local model = Instance.new("Model")
	model.Name = key
	local parts = {}
	local mn, mx = {math.huge, math.huge, math.huge}, {-math.huge, -math.huge, -math.huge}
	for _, pd in ipairs(data.Parts) do
		local p = Instance.new("Part")
		p.Name = pd.Name
		p.Size = pd.Size
		local c = pd.CF
		p.CFrame = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		p.Color = Color3.fromHex(pd.Color)
		p.Material = Enum.Material[pd.Material]
		p.Transparency = pd.T
		p.CanCollide = pd.Collide
		p.Anchored = true
		p.Parent = model
		if pd.Shape == "Ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		table.insert(parts, p)
		local m = {c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]}
		for axis = 0, 2 do
			local e = halfExtent(pd.Size, m, axis)
			mn[axis + 1] = math.min(mn[axis + 1], c[axis + 1] - e)
			mx[axis + 1] = math.max(mx[axis + 1], c[axis + 1] + e)
		end
	end
	local lo, hi = Vector3.new(mn[1], mn[2], mn[3]), Vector3.new(mx[1], mx[2], mx[3])
	local centre = (lo + hi) / 2
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (hi - lo) * scale
	hitbox.CFrame = CFrame.new(centre)
	hitbox.Transparency = 1
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	for _, p in ipairs(parts) do
		p.Size = p.Size * scale
		p.CFrame = CFrame.new(centre + (p.CFrame.Position - centre) * scale) * p.CFrame.Rotation
	end
	for k, v in pairs(data.Attrs) do model:SetAttribute(k, v) end
	model:SetAttribute("AuthoredCentre", centre)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("BuildKey", key)
	model:SetAttribute("Owner", 42)
	local delta = placeCF * hitbox.CFrame:Inverse()
	for _, p in ipairs(parts) do p.CFrame = delta * p.CFrame end
	hitbox.CFrame = delta * hitbox.CFrame
	model.Parent = workspace
	return model
end

local function Snapshot(model)
	local snap = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			snap[d] = {CFrame = d.CFrame, Color = d.Color, Material = d.Material, Transparency = d.Transparency}
		elseif d.ClassName == "SpecialMesh" then
			snap[d] = {Scale = d.Scale}
		end
	end
	return snap
end
local function SameAsSnapshot(model, snap, label)
	for inst, s in pairs(snap) do
		if s.Scale then
			check(vnear(inst.Scale, s.Scale, 1e-6), label .. ": mesh scale of " .. inst.Parent.Name .. " restored")
		else
			check(vnear(inst.CFrame.Position, s.CFrame.Position, 1e-5) and vnear(inst.CFrame.UpVector, s.CFrame.UpVector, 1e-5)
				and vnear(inst.CFrame.LookVector, s.CFrame.LookVector, 1e-5), label .. ": CFrame of " .. inst.Name .. " restored")
			check(inst.Color == s.Color, label .. ": Color of " .. inst.Name .. " restored")
			check(inst.Material == s.Material, label .. ": Material of " .. inst.Name .. " restored")
			check(inst.Transparency == s.Transparency, label .. ": Transparency of " .. inst.Name .. " restored (" .. tostring(inst.Transparency) .. ")")
		end
	end
end

------------------------------------------------------------------ client ctx (FunBuildClient.NewContext)
local function MakeCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		_insts = {}, _cleanups = {}, _steps = {}, _everys = {}, _conns = {}, StepRange = 180}
	function ctx:Alive() return true end
	function ctx:Connect(sig, fn) local c = sig:Connect(fn) table.insert(self._conns, c) return c end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn)
		self:Connect(model:GetAttributeChangedSignal("Fun_" .. k), function() fn(model:GetAttribute("Fun_" .. k)) end)
		fn(model:GetAttribute("Fun_" .. k))
	end
	function ctx:Send() end
	function ctx:CameraDistance() return (workspace.CurrentCamera.CFrame.Position - Kit.Hitbox(model).Position).Magnitude end
	function ctx:Step(fn) table.insert(self._steps, fn) end
	function ctx:Every(_, fn) table.insert(self._everys, fn) end
	function ctx:Sound(parent, id, props) local s = Kit.MakeSound(id, props) s.Parent = parent self:Add(s) return s end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = workspace.CurrentCamera end
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
	return ctx
end
local function Frames(ctx, seconds, dt)
	dt = dt or 1 / 60
	check(#ctx._steps <= 1, "at most one ctx:Step per build")
	local n = math.floor(seconds / dt + 0.5)
	for _ = 1, n do
		MockNow += dt
		MockClock += dt
		for _, fn in ipairs(ctx._steps) do
			local ok, err = pcall(fn, dt, MockNow)
			if not ok then check(false, "Step errored: " .. tostring(err)) return end
		end
	end
end
local function Everys(ctx)
	for _, fn in ipairs(ctx._everys) do
		local ok, err = pcall(fn)
		check(ok, "Every errored: " .. tostring(err))
	end
end
local function Stop(ctx)
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		check(ok, "cleanup errored: " .. tostring(err))
	end
	for _, c in ipairs(ctx._conns) do c.Disconnect() end
	for i = #ctx._insts, 1, -1 do ctx._insts[i]:Destroy() end
end
local function FindIn(insts, className, name)
	for _, i in ipairs(insts) do
		if i.ClassName == className and (not name or i.Name == name) then return i end
		for _, d in ipairs(i:GetDescendants()) do
			if d.ClassName == className and (not name or d.Name == name) then return d end
		end
	end
	return nil
end
local function FindAll(insts, className)
	local out = {}
	for _, i in ipairs(insts) do
		if i.ClassName == className then table.insert(out, i) end
		for _, d in ipairs(i:GetDescendants()) do if d.ClassName == className then table.insert(out, d) end end
	end
	return out
end
local function CameraAt(p) rawget(workspace.CurrentCamera, "_p").CFrame = CFrame.new(p) end

------------------------------------------------------------------ server ctx (FunBuildService.NewContext)
local function MakeServerCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local folder = Instance.new("Folder")
	folder.Parent = workspace
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit, Folder = folder,
		_insts = {folder}, _conns = {}, _states = {}}
	function ctx:Alive() return true end
	function ctx:Connect(sig, fn) local c = sig:Connect(fn) table.insert(self._conns, c) return c end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup() end
	function ctx:SetState(k, v) self._states[k] = true model:SetAttribute("Fun_" .. k, v) end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:HumanoidOf(player) if player and player.Alive then return {Health = 100}, {Position = Vector3.zero} end return nil end
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent then p.Parent = folder end
		self:Add(p)
		return p
	end
	function ctx:Prompt(part, opts)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = opts.Name or "FunPrompt"
		prompt.ObjectText = opts.Object or base
		prompt.ActionText = opts.Action or "Use"
		prompt.MaxActivationDistance = opts.Distance or 10
		prompt.Parent = part
		self:Add(prompt)
		return prompt
	end
	return ctx
end

------------------------------------------------------------------ authored-frame helpers
local function PartData(key, name)
	for _, pd in ipairs(MODELS[key].Parts) do if pd.Name == name then return pd end end
	return nil
end
-- distance along an authored horizontal ray to an axis-aligned authored part box (math.huge when missed)
local function RayToBox(key, name, from, dir)
	local pd = PartData(key, name)
	if not pd then return math.huge end
	local c = Vector3.new(pd.CF[1], pd.CF[2], pd.CF[3])
	local lo, hi = c - pd.Size / 2, c + pd.Size / 2
	local tmin, tmax = -math.huge, math.huge
	for _, axis in ipairs({"X", "Y", "Z"}) do
		local o, d = from[axis], dir[axis]
		if math.abs(d) < 1e-9 then
			if o < lo[axis] or o > hi[axis] then return math.huge end
		else
			local t1, t2 = (lo[axis] - o) / d, (hi[axis] - o) / d
			tmin = math.max(tmin, math.min(t1, t2))
			tmax = math.min(tmax, math.max(t1, t2))
		end
	end
	if tmax < math.max(tmin, 0) then return math.huge end
	return math.max(tmin, 0)
end

--========================================================================== DINING TABLE (server seats)
do
	local S = require({Name = "S_DiningTable"})
	local scale = 1.3
	local place = CFrame.new(12, 3, -30) * CFrame.Angles(0, math.rad(37), 0)
	local model = MakePlaced("DiningTable", scale, place)
	local ctx = MakeServerCtx(model)
	local seats = {}
	function ctx:Seat(cf, opts) table.insert(seats, {CF = cf, Opts = opts}) return Instance.new("Part") end
	local ok, err = pcall(S.Server, model, ctx)
	check(ok, "dining server errored: " .. tostring(err))
	check(#seats == 4, "dining: 4 seats (got " .. #seats .. ")")
	local origin = Kit.Origin(model)
	local inv = origin:Inverse()
	local names = {}
	for i, s in ipairs(seats) do
		names[s.Opts.Name] = true
		local authored = model:GetAttribute("Pivot_Seat" .. i)
		local face = model:GetAttribute("Pivot_Seat" .. i .. "Face")
		check(typeof(authored) == "Vector3" and typeof(face) == "Vector3", "dining: seat " .. i .. " pivots authored")
		local top = s.CF.Position + s.CF.UpVector * (s.Opts.Size.Y * 0.5)
		check(vnear(top, Kit.ToWorld(model, authored), 1e-4), "dining: seat " .. i .. " top on Pivot_Seat" .. i)
		check(near(s.CF.UpVector:Dot(origin.UpVector), 1, 1e-6), "dining: seat " .. i .. " level")
		local lookA = inv:VectorToWorldSpace(s.CF.LookVector)
		local want = (face - authored)
		want = Vector3.new(want.X, 0, want.Z).Unit
		check(vnear(lookA, want, 1e-4), "dining: seat " .. i .. " looks where Pivot_Seat" .. i .. "Face says " .. tostring(lookA))
		-- the sitter looks at the table: the look ray at table height hits the top
		local hit = RayToBox("DiningTable", "TableTop", Vector3.new(authored.X, 3.1, authored.Z), want)
		check(hit < math.huge, "dining: seat " .. i .. " faces the table")
		-- torso (~1 deep, centred on the seat) clears the table edge + runner flap by >= 0.1 (seat centre >= 0.6 out)
		local edge = math.min(hit, RayToBox("DiningTable", "RunnerFlapL", Vector3.new(authored.X, 3.0, authored.Z), want),
			RayToBox("DiningTable", "RunnerFlapR", Vector3.new(authored.X, 3.0, authored.Z), want))
		check(edge >= 0.6, string.format("dining: seat %d centre %.2f from the table edge / flap (>= 0.6)", i, edge))
		-- knees (~1.5 forward of the hips, thigh top ~3.1) never reach the apron
		local apron = RayToBox("DiningTable", "TableApron", Vector3.new(authored.X, 2.9, authored.Z), want)
		check(apron >= 1.7, string.format("dining: seat %d apron %.2f ahead (>= 1.7, clear of the knees)", i, apron))
		-- nor the table legs (legs of a sitter span +/-1 sideways)
		for l = 1, 4 do
			local pd = PartData("DiningTable", "TableLeg" .. l)
			local rel = Vector3.new(pd.CF[1] - authored.X, 0, pd.CF[3] - authored.Z)
			local along = rel:Dot(want)
			local side = math.abs(rel:Dot(Vector3.new(-want.Z, 0, want.X)))
			check(not (along > 0 and along < 1.9 and side < 1.0 + 0.22), "dining: seat " .. i .. " knees clear TableLeg" .. l)
		end
	end
	check(names.DiningSeat1 and names.DiningSeat2 and names.DiningSeat3 and names.DiningSeat4, "dining: seats named DiningSeat1..4")
	-- no two sitters shoulder to shoulder (arms ~4.2 wide at physique 6.1)
	for a = 1, 4 do
		for b = a + 1, 4 do
			local pa, pb = model:GetAttribute("Pivot_Seat" .. a), model:GetAttribute("Pivot_Seat" .. b)
			local d = Vector3.new(pa.X - pb.X, 0, pa.Z - pb.Z).Magnitude
			check(d >= 4.2, string.format("dining: seats %d/%d %.2f apart (>= 4.2)", a, b, d))
		end
	end
	print(string.format("dining server: %d seats checked", #seats))
end

--========================================================================== DINING TABLE (client candle)
do
	local C = require({Name = "C_DiningTable"})
	check(MockNow > 1e9, "dining: the mock clock is epoch-sized (the case that froze the flame)")
	local scale = 1.3
	local place = CFrame.new(12, 3, -30) * CFrame.Angles(0, math.rad(37), 0)
	local model = MakePlaced("DiningTable", scale, place)
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 5, -12)))
	local flame = model:FindFirstChild("CandleFlame")
	check(flame ~= nil, "dining: CandleFlame exists")
	local restSize = flame.Size
	local restFoot = flame.CFrame * CFrame.new(0, -restSize.Y / 2, 0)
	local snap = Snapshot(model)
	local ctx = Run(C, model)
	local light = FindIn(ctx._insts, "PointLight", "CandleGlow")
	check(light ~= nil and light.Parent == flame, "dining: CandleGlow PointLight inside the flame")
	check(#FindAll(ctx._insts, "PointLight") <= 2, "dining: <= 2 lights")
	local ys, bs, seen, seenB = {}, {}, {}, {}
	local distinct, distinctB = 0, 0
	local footDrift = 0
	for _ = 1, 30 do
		Frames(ctx, 1 / 60)
		local y = math.floor(flame.Size.Y * 1e5 + 0.5)
		if not seen[y] then seen[y] = true distinct += 1 end
		local b = math.floor(light.Brightness * 1e5 + 0.5)
		if not seenB[b] then seenB[b] = true distinctB += 1 end
		table.insert(ys, flame.Size.Y)
		table.insert(bs, light.Brightness)
		local foot = flame.CFrame * CFrame.new(0, -flame.Size.Y / 2, 0)
		footDrift = math.max(footDrift, (foot.Position - restFoot.Position).Magnitude)
	end
	local ymin, ymax = math.min(table.unpack(ys)), math.max(table.unpack(ys))
	local bmin, bmax = math.min(table.unpack(bs)), math.max(table.unpack(bs))
	check(distinct >= 25, "dining: flame height changes every frame (" .. distinct .. " distinct of 30)")
	check(distinctB >= 25, "dining: light brightness changes every frame (" .. distinctB .. " distinct of 30)")
	check((ymax - ymin) / restSize.Y > 0.05, string.format("dining: flame height swings %.1f%% in 0.5 s", (ymax - ymin) / restSize.Y * 100))
	check(bmax - bmin > 0.05, string.format("dining: brightness swings %.3f in 0.5 s", bmax - bmin))
	check(footDrift < 1e-4, string.format("dining: the flame stays on the wick (foot drift %.5f)", footDrift))
	print(string.format("dining client: flame Y %.3f..%.3f (rest %.3f), brightness %.3f..%.3f", ymin, ymax, restSize.Y, bmin, bmax))
	Stop(ctx)
	SameAsSnapshot(model, snap, "dining cleanup")
	check(vnear(flame.Size, restSize, 1e-6), "dining: flame size restored")
end

print(string.format("HomeDining: %d checks, %d failed", checks, fails))
