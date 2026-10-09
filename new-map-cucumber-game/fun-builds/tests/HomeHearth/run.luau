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
SOURCES['C_Fireplace'] = [======[
--[[
	Fireplace  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package HomeHearth
	Client half of the WORKING FIREPLACE (server half: ServerStorage.FunBehaviours.Fireplace; fun-builds/CONTRACT.md).
	Everything is drawn from state Fun_Lit (true / false) through one "heat" value (0 cold .. 1 blazing) that
	rises over FADE_IN s when the fire is lit and sinks over FADE_OUT s when it is put out, so the embers and the
	light die down slowly instead of snapping off:
	  * Fire instances on the log pile (Pivot_Fire) + a spark emitter; on while lit
	  * one warm PointLight just in front of the opening (Pivot_Light, Range ~20, shadows on) whose Brightness
	    flickers every frame and Range at 10 Hz (a flame wobble from Kit.Now(), the same on every client)
	  * the Ember* parts (coal bed + seams on the logs) turn Neon and flicker orange / deep red with the heat
	  * the three mantel candles (CandleFlame1..3, authored invisible) light one after another, flames flicker
	    (their SpecialMesh Scale); they go out with the fire
	  * a thin plume of smoke rises from the chimney crown (Pivot_Chimney) while it burns
	  * FunAssets.Sfx.FireLoop crackles (looped, volume follows the heat) while the camera is within NEAR_SOUND
	  * lighting it: Sfx.FireIgnite (match strike + flare) + a burst of sparks; putting it out: Sfx.FireOut (blow-out
	    puff) + a puff of smoke (both fall back to Sfx.Whoosh if the ids are ever removed)
	  * always: the mantel clock's hands (ClockHour / ClockMinute, about Pivot_ClockCentre) show the game's time
	    (Lighting.ClockTime, the same clock the GrandfatherClock reads, so every clock on a plot and every player
	    agree; it snaps when the day / night cycle jumps); the picture frame shows one of FunAssets.Pictures (if
	    any) instead of its painted landscape
	Every build part it touches (Ember* Color + Material, CandleFlame* Transparency + mesh Scale, the clock hands'
	CFrame, PicHill / PicSun Transparency) is put back on cleanup. Particle textures are engine built-ins.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local TEX_GLOW = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- soft round dot (sparks)
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRES = { -- Fire instances on the log pile: AUTHORED offset from Pivot_Fire, Size / Heat at scale 1
	{Offset = Vector3.new(0.1, 0, 0), Size = 3.2, Heat = 7},
	{Offset = Vector3.new(-0.55, -0.1, 0.12), Size = 2.2, Heat = 5},
}
local FIRE_COLOR = Color3.fromRGB(255, 140, 40)
local FIRE_SECONDARY = Color3.fromRGB(255, 70, 15)
local LIGHT_COLOR = Color3.fromRGB(255, 150, 70)
local LIGHT_BRIGHTNESS = 2.2
local LIGHT_RANGE = 20       -- studs at scale 1
local MAX_RANGE = 60         -- PointLight.Range engine cap
local FADE_IN = 1.2          -- seconds cold -> full blaze
local FADE_OUT = 3.5         -- seconds full -> cold after "Put out" (the embers glow on a while)
local EMBER_HOT = Color3.fromRGB(255, 128, 36)
local EMBER_DEEP = Color3.fromRGB(226, 52, 18)
local CANDLE_DELAY = 0.35    -- seconds after lighting before the first candle catches
local CANDLE_STAGGER = 0.3   -- seconds between candles
local CANDLE_FLICKER = 0.16  -- flame height wobble (fraction)
local CRACKLE_VOLUME = 0.5
local NEAR_SOUND = 55        -- studs camera <-> fireplace for the crackle loop
local AWAKE_RANGE = 170      -- studs camera <-> fireplace for fire / particles
local SNAP_RANGE = 120       -- a change seen from farther than this snaps (no sounds, no burst)
local BROKEN_FADE = 0.65     -- BuildHealthService's broken transparency (kept on cleanup while Broken)
local FALLBACK = {           -- authored points when a Pivot_* is missing (older template)
	Fire = Vector3.new(0, 0.95, -0.2),
	Light = Vector3.new(0, 1.7, -1.55),
	Chimney = Vector3.new(0, 7.0, 0.25),
}
local CLOCK_HOUR_DEG, CLOCK_MINUTE_DEG = 305, 60 -- the hands' AUTHORED angles (10:10), clockwise from 12 seen from the front
local CLOCK_RATE = 0.1       -- seconds between hand updates (a game minute passes every ~0.6 s by day)

local B = {}
B.StepRange = 180

--..Helpers..--
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
	pcall(function() -- whole-box volume emission where the host part has a size (engine shape API)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end)
	e.Parent = parent
	return e
end

--.. a smooth flame wobble around 1: slow noise + a quicker shimmer (t = server time, same on every client)
local function Flicker(t, seed, amount)
	return 1 + amount * (math.noise(t * 2.3, seed, 0.5) * 1.4 + 0.45 * math.sin(t * 7.3 + seed))
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local s = ctx.Scale
	local rotation = Kit.Origin(model).Rotation
	local seed = (hitbox.Position.X * 0.371 + hitbox.Position.Z * 0.713) % 97
	local function Point(name)
		return Kit.Pivot(model, name) or Kit.ToWorld(model, FALLBACK[name])
	end

	--..Build parts we animate (restored on cleanup)..--
	local embers = Kit.Parts(model, "Ember")
	local flames = Kit.Parts(model, "CandleFlame")
	local emberBase, flameBase = {}, {}
	for _, part in ipairs(embers) do emberBase[part] = {Color = part.Color, Material = part.Material} end
	for i, part in ipairs(flames) do
		local mesh = part:FindFirstChildOfClass("SpecialMesh")
		flameBase[part] = {Transparency = part.Transparency, Mesh = mesh, Scale = mesh and mesh.Scale, Seed = seed + i * 3.1}
	end
	local embersHot = false
	local function RestoreEmbers()
		for part, b in pairs(emberBase) do
			if part.Parent then
				part.Color = b.Color
				part.Material = b.Material
			end
		end
	end
	local function CandleOut(part)
		local b = flameBase[part]
		part.Transparency = b.Transparency
		if b.Mesh and b.Scale then b.Mesh.Scale = b.Scale end
	end

	--..Effect hosts: invisible local parts (fire + sparks on the logs, smoke on the chimney)..--
	local firePoint = Point("Fire")
	local host = ctx:Part({
		Name = "FireplaceFire",
		Transparency = 1,
		Size = Vector3.new(2.2, 0.3, 0.8) * s,
		CFrame = CFrame.new(firePoint) * rotation,
	})
	local fires = {}
	for i, f in ipairs(FIRES) do
		local fireHost = ctx:Part({
			Name = "FireplaceFlame" .. i,
			Transparency = 1,
			Size = Vector3.new(0.2, 0.2, 0.2),
			CFrame = host.CFrame * CFrame.new(f.Offset * s),
		})
		local fire = Instance.new("Fire")
		fire.Color = FIRE_COLOR
		fire.SecondaryColor = FIRE_SECONDARY
		fire.Size = math.clamp(f.Size * s, 2, 30)
		fire.Heat = math.clamp(f.Heat * s, 0, 25)
		fire.Enabled = false
		fire.Parent = fireHost
		table.insert(fires, {Fire = fire, Size = f.Size * s})
	end
	--.. flame size follows the heat (half size when cold, full at a blaze); called whenever heat changes or snaps
	local function SizeFires(heat)
		for _, f in ipairs(fires) do f.Fire.Size = math.clamp(f.Size * (0.5 + 0.5 * heat), 2, 30) end
	end
	local sparks = Emitter(host, {
		Name = "Sparks",
		Texture = TEX_GLOW,
		Color = ColorSequence.new(Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 96, 30)),
		Size = Seq(0, 0.13 * s, 0.6, 0.09 * s, 1, 0),
		Transparency = Seq(0, 0, 0.7, 0.2, 1, 1),
		Lifetime = NumberRange.new(0.6, 1.3),
		Rate = 9,
		Speed = NumberRange.new(1.2 * s, 2.6 * s),
		SpreadAngle = Vector2.new(18, 18),
		Acceleration = Vector3.new(0, 0.8 * s, 0),
		Drag = 1.2,
		LightEmission = 1,
		LightInfluence = 0,
		ZOffset = 0.5,
		EmissionDirection = Enum.NormalId.Top,
	})
	local puff = Emitter(host, {
		Name = "Puff",
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(150, 146, 140), Color3.fromRGB(200, 198, 194)),
		Size = Seq(0, 0.7 * s, 1, 2.2 * s),
		Transparency = Seq(0, 0.35, 0.5, 0.55, 1, 1),
		Lifetime = NumberRange.new(1.2, 2),
		Rate = 0,
		Speed = NumberRange.new(1 * s, 2.4 * s),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, 0.6 * s, 0),
		Drag = 0.8,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		LightInfluence = 0.8,
		ZOffset = 0.4,
		EmissionDirection = Enum.NormalId.Top,
	})
	puff.Enabled = true -- Rate 0: bursts only (puff:Emit)

	local chimney = ctx:Part({
		Name = "FireplaceChimney",
		Transparency = 1,
		Size = Vector3.new(1.2, 0.2, 0.8) * s,
		CFrame = CFrame.new(Point("Chimney")) * rotation,
	})
	local smoke = Emitter(chimney, {
		Name = "ChimneySmoke",
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(128, 124, 120), Color3.fromRGB(190, 188, 185)),
		Size = Seq(0, 0.6 * s, 1, 2.6 * s),
		Transparency = Seq(0, 0.55, 0.3, 0.62, 1, 1),
		Lifetime = NumberRange.new(3, 5),
		Rate = 3,
		Speed = NumberRange.new(1.4 * s, 2.2 * s),
		SpreadAngle = Vector2.new(12, 12),
		Acceleration = Vector3.new(0.25, 0.35, 0) * s,
		Drag = 0.4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-15, 15),
		LightInfluence = 0.8,
		WindAffectsDrag = true,
		EmissionDirection = Enum.NormalId.Top,
	})

	--..Light: just in front of the opening, so it spills out into the room..--
	local lightAt = Instance.new("Attachment")
	lightAt.Name = "FireplaceLight"
	lightAt.Position = host.CFrame:PointToObjectSpace(Point("Light"))
	lightAt.Parent = host
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Brightness = 0
	light.Range = math.min(MAX_RANGE, LIGHT_RANGE * s)
	light.Shadows = true
	light.Enabled = false
	light.Parent = lightAt

	--..Sounds..--
	local crackle = ctx:Sound(host, FunAssets.Sfx.FireLoop, {Name = "Crackle", Looped = true, Volume = 0, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND})
	local ignite = ctx:Sound(host, FunAssets.Sfx.FireIgnite or FunAssets.Sfx.Whoosh, {Name = "Ignite", Volume = 0.55, PlaybackSpeed = FunAssets.Sfx.FireIgnite and 1 or 1.1, RollOffMaxDistance = 60})
	local douse = ctx:Sound(host, FunAssets.Sfx.FireOut or FunAssets.Sfx.Whoosh, {Name = "Douse", Volume = 0.45, PlaybackSpeed = FunAssets.Sfx.FireOut and 1 or 0.6, RollOffMaxDistance = 60})

	--..Clock hands: turned about the face centre to the game's time (Lighting.ClockTime)..--
	local hands = {}
	local centre = model:GetAttribute("Pivot_ClockCentre")
	local clockCF = typeof(centre) == "Vector3" and Kit.CFrameToWorld(model, CFrame.new(centre)) or nil
	if clockCF then
		for _, h in ipairs({{"ClockHour", CLOCK_HOUR_DEG, 30}, {"ClockMinute", CLOCK_MINUTE_DEG, 6}}) do
			local part = Kit.Part(model, h[1])
			if part then
				table.insert(hands, {
					Part = part, Deg = h[2], PerUnit = h[3], Hour = h[1] == "ClockHour",
					Rel = clockCF:ToObjectSpace(part.CFrame),   -- about the clock centre (for turning)
					Rest = hitbox.CFrame:ToObjectSpace(part.CFrame), -- about the hitbox (for putting back after a move)
				})
			end
		end
	end
	local shownTime = nil
	local function SetClock()
		local clockTime = tonumber(Lighting.ClockTime) or 12
		if clockTime == shownTime then return end
		shownTime = clockTime
		local hour = clockTime % 12
		local minute = (clockTime * 60) % 60
		for _, h in ipairs(hands) do
			local deg = (h.Hour and hour or minute) * h.PerUnit
			h.Part.CFrame = clockCF * CFrame.Angles(0, 0, math.rad(deg - h.Deg)) * h.Rel
		end
	end

	--..Picture: one of FunAssets.Pictures on the canvas, if there are any..--
	local hidden = {} -- [part] = authored Transparency
	local pictures = type(FunAssets.Pictures) == "table" and FunAssets.Pictures or {}
	local canvas = Kit.Part(model, "PicCanvas")
	if canvas and #pictures > 0 then
		local pick = math.floor(math.abs(hitbox.Position.X) * 7 + math.abs(hitbox.Position.Z) * 13) % #pictures + 1
		local image = pictures[pick]
		if type(image) == "table" then image = image.Id or image.Image end
		if type(image) == "string" or type(image) == "number" then
			local id = tostring(image)
			if tonumber(id) then id = "rbxassetid://" .. id end
			pcall(function()
				local decal = Instance.new("Decal")
				decal.Name = "FireplacePicture"
				decal.Face = Enum.NormalId.Front
				decal.Texture = id
				decal.Parent = canvas
				ctx:Add(decal)
			end)
			for _, name in ipairs({"PicHill", "PicSun"}) do
				local part = Kit.Part(model, name)
				if part then
					hidden[part] = part.Transparency
					part.Transparency = 1
				end
			end
		end
	end

	--..Cleanup: every build part back as authored..--
	ctx:OnCleanup(function()
		RestoreEmbers()
		for part in pairs(flameBase) do
			if part.Parent then CandleOut(part) end
		end
		for _, h in ipairs(hands) do
			if h.Part.Parent and hitbox.Parent then h.Part.CFrame = hitbox.CFrame * h.Rest end
		end
		local broken = Kit.IsBroken(model)
		for part, t in pairs(hidden) do
			if part.Parent then part.Transparency = (broken and t < 1) and math.max(t, BROKEN_FADE) or t end
		end
	end)

	--..State..--
	local lit, heat, awake, first = false, 0, true, true
	local litAt = -math.huge -- os.clock() when it was lit (candles catch one by one after it)
	local function Apply()
		for _, f in ipairs(fires) do f.Fire.Enabled = lit and awake end
		sparks.Enabled = lit and awake
		local wantSound = lit and awake and ctx:CameraDistance() <= NEAR_SOUND
		if wantSound and not crackle.IsPlaying then
			crackle:Play()
		elseif not wantSound and crackle.IsPlaying then
			crackle:Stop()
		end
	end
	ctx:OnState("Lit", function(value)
		local on = value == true
		if on == lit and not first then return end
		local live = not first and ctx:CameraDistance() <= SNAP_RANGE
		first = false
		lit = on
		if live then
			litAt = os.clock()
			if on then
				ignite.TimePosition = 0
				ignite:Play()
				sparks:Emit(18)
			else
				douse.TimePosition = 0
				douse:Play()
				puff:Emit(14)
			end
		else
			heat = on and 1 or 0 -- streamed in / far away: straight to the state, no fanfare
			litAt = -math.huge
			SizeFires(heat)
		end
		Apply()
	end)
	ctx:Every(0.5, function()
		awake = ctx:CameraDistance() <= AWAKE_RANGE
		Apply()
	end)

	--..Per frame: heat, light flicker, embers, candles, clock..--
	local rangeClock, clockClock = 1, 1
	local smokeOn = false
	ctx:Step(function(dt, now)
		--.. heat follows the state
		local target = lit and 1 or 0
		if heat ~= target then
			local step = dt / (lit and FADE_IN or FADE_OUT)
			heat = (target > heat) and math.min(target, heat + step) or math.max(target, heat - step)
			SizeFires(heat)
		end
		if crackle.IsPlaying then crackle.Volume = CRACKLE_VOLUME * heat end

		--.. light (idle while cold)
		if heat > 0.01 then
			local f = Flicker(now, seed, 0.12)
			if not light.Enabled then light.Enabled = true end
			light.Brightness = LIGHT_BRIGHTNESS * heat * f
			rangeClock += dt
			if rangeClock >= 0.1 then
				rangeClock = 0
				light.Range = math.min(MAX_RANGE, LIGHT_RANGE * s * (0.75 + 0.25 * heat) * (1 + (f - 1) * 0.3))
			end
		elseif light.Enabled then
			light.Enabled = false
			light.Brightness = 0
		end

		--.. chimney smoke while it really burns
		local wantSmoke = awake and heat > 0.3
		if wantSmoke ~= smokeOn then
			smokeOn = wantSmoke
			smoke.Enabled = wantSmoke
		end

		--.. embers glow with the heat (Neon from dark charcoal to flickering orange)
		if heat > 0.005 then
			embersHot = true
			for i, part in ipairs(embers) do
				local b = emberBase[part]
				local pulse = 0.5 + 0.5 * math.noise(now * 1.7, seed + i * 1.37, 0.3) * 1.6
				local glow = EMBER_DEEP:Lerp(EMBER_HOT, math.clamp(pulse, 0, 1))
				if part.Material ~= Enum.Material.Neon then part.Material = Enum.Material.Neon end
				part.Color = b.Color:Lerp(glow, math.clamp(heat * 1.15, 0, 1))
			end
		elseif embersHot then
			embersHot = false
			RestoreEmbers()
		end

		--.. candles catch one by one after lighting, and go out with the fire
		local since = os.clock() - litAt
		for i, part in ipairs(flames) do
			local b = flameBase[part]
			local on = lit and since >= CANDLE_DELAY + (i - 1) * CANDLE_STAGGER
			if on then
				if part.Transparency ~= 0 then part.Transparency = 0 end
				if b.Mesh and b.Scale then
					local w = math.noise(now * 3.1, b.Seed, 0.7)
					local h = 1 + CANDLE_FLICKER * (math.noise(now * 4.3, b.Seed, 1.9) * 1.3 + 0.35 * math.sin(now * 11 + b.Seed))
					b.Mesh.Scale = Vector3.new(b.Scale.X * (1 + 0.08 * w), b.Scale.Y * h, b.Scale.Z * (1 + 0.08 * w))
				end
			elseif part.Transparency ~= b.Transparency then
				CandleOut(part)
			end
		end

		--.. the clock (CLOCK_RATE; SetClock skips when the game time hasn't moved)
		if clockCF then
			clockClock += dt
			if clockClock >= CLOCK_RATE then
				clockClock = 0
				SetClock()
			end
		end
	end)
end

return B
]======]
SOURCES['S_Fireplace'] = [======[
--[[
	Fireplace  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package HomeHearth
	Server half of the WORKING FIREPLACE (fun-builds/CONTRACT.md; model = models/build_Fireplace.py, Home, Cost 1500).
	  * one prompt over the hearth (Pivot_Prompt): "Light fire" while the fireplace is cold, "Put out" while it
	    burns. Anyone may use it (a fire is nothing to grief); a short debounce stops two people pressing at the
	    same moment from flickering it on and off
	  * state Fun_Lit (true / false). The client half draws everything from it: the Fire, sparks, the warm
	    flickering light, glowing embers, the mantel candles, chimney smoke and the crackle
	  * the fire starts OUT whenever this behaviour (re)starts - placed, moved, mended after a zombie raid, server
	    start. It never lights itself (not even at night): someone has to light it
	No economy, no damage: the fire is cosmetic (no Touched, nothing burns, nobody gets hurt).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local PROMPT_DISTANCE = 10                          -- studs (x the build's scale when it is scaled up)
local TOGGLE_DEBOUNCE = 0.6                         -- seconds between two toggles
local PROMPT_FALLBACK = Vector3.new(0, 1.9, -1.95)  -- authored, used when Pivot_Prompt is missing

local B = {}
B.Keys = {"Fireplace"}

--..Behaviour..--
function B.Server(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end

	--..Prompt on an invisible helper over the hearth..--
	local spot = Kit.Pivot(model, "Prompt") or Kit.ToWorld(model, PROMPT_FALLBACK)
	local anchor = ctx:Part({
		Name = "FireplacePromptSpot",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CFrame = CFrame.new(spot) * hitbox.CFrame.Rotation,
	})
	local prompt = ctx:Prompt(anchor, {
		Action = "Light fire",
		Object = "Fireplace",
		Distance = PROMPT_DISTANCE * math.max(1, ctx.Scale),
		Name = "FirePrompt",
	})

	--..State..--
	local function Apply(lit)
		ctx:SetState("Lit", lit)
		prompt.ActionText = lit and "Put out" or "Light fire"
	end
	Apply(false)

	local last = 0
	ctx:Connect(prompt.Triggered, function(player)
		if not ctx:Alive() or not ctx:HumanoidOf(player) then return end
		local now = os.clock()
		if now - last < TOGGLE_DEBOUNCE then return end
		last = now
		Apply(ctx:GetState("Lit") ~= true)
	end)
end

return B
]======]
SOURCES['C_FloorLamp'] = [======[
--[[
	FloorLamp  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package HomeHearth
	Client half of the READING FLOOR LAMP (server half: ServerStorage.FunBehaviours.FloorLamp; fun-builds/CONTRACT.md).
	Drawn from state Fun_On (true / false; the server turns it on at dusk, off at dawn, and anyone flips it by
	the pull-chain) through one "glow" value that eases in over WARM_UP s and out over COOL_DOWN s:
	  * a warm PointLight at the bulb (Pivot_Light, no shadows: it sits inside the shade) and a SpotLight inside
	    the shade just over its open bottom (Pivot_Spot) shining DOWN through the opening with shadows on, so
	    the lamp throws a round pool of light on the floor round its base (2 lights, the contract's cap)
	  * the shade glows from inside: the fabric panels (ShadePanel01..16) turn a soft warm cream Neon, so the lamp
	    reads as on from every side even in the game's bright daytime lighting; the diffuser disc on top
	    (ShadeGlowTop) and the Bulb (seen through the open bottom) turn Neon too. SHADE_NEON = false would only
	    tint the panels instead
	  * a hand switch (the server's "Tug" event, fired only from the prompt - never by the dusk / dawn switch)
	    tugs the pull-chain (PullChain + PullBead) down and back and clicks; the state change only eases the glow
	Every build part it touches (Color, Material, the chain's CFrame) is put back on cleanup.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets", 15))

--..Config..--
local LIGHT_COLOR = Color3.fromRGB(255, 214, 150)
local POINT_BRIGHTNESS, POINT_RANGE = 1.3, 14           -- range in studs at scale 1
local SPOT_BRIGHTNESS, SPOT_RANGE, SPOT_ANGLE = 2.6, 16, 110
local MAX_RANGE = 60
local GLOW_COLOR = Color3.fromRGB(255, 226, 166)       -- diffuser disc while on (Neon)
local BULB_COLOR = Color3.fromRGB(255, 241, 204)       -- bulb while on (Neon)
local SHADE_LIT = Color3.fromRGB(255, 247, 226)        -- fabric panels while on
local SHADE_NEON_COLOR = Color3.fromRGB(255, 228, 175) -- fabric panels while on when SHADE_NEON (soft warm cream Neon)
local SHADE_NEON = true                                -- the whole shade glows while on (false: panels only tint)
local WARM_UP, COOL_DOWN = 0.25, 0.4                   -- seconds
local TUG_DEPTH, TUG_TIME = 0.22, 0.32                 -- AUTHORED studs down / seconds for the pull-chain tug
local SNAP_RANGE = 120                                 -- a change seen from farther than this snaps; no tug / click past it
local FALLBACK = {                                     -- authored points when a Pivot_* is missing (older template)
	Light = Vector3.new(0, 6.1, 0),
	Spot = Vector3.new(0, 5.75, -0.36),
	ChainTop = Vector3.new(0.3, 5.7, -0.3),
}

local B = {}
B.StepRange = 180

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local s = ctx.Scale
	local rotation = Kit.Origin(model).Rotation
	local function Point(name)
		return Kit.Pivot(model, name) or Kit.ToWorld(model, FALLBACK[name])
	end

	--..Build parts we recolour (restored on cleanup)..--
	local base = {} -- [part] = {Color, Material}
	local function Track(part)
		if part and not base[part] then base[part] = {Color = part.Color, Material = part.Material} end
		return part
	end
	local glowTop = Track(Kit.Part(model, "ShadeGlowTop"))
	local bulb = Track(Kit.Part(model, "Bulb"))
	local panels = Kit.Parts(model, "ShadePanel")
	for _, part in ipairs(panels) do Track(part) end

	--..Pull-chain rig (tugged about its top)..--
	local chainParts = {}
	for _, name in ipairs({"PullChain", "PullBead"}) do
		local part = Kit.Part(model, name)
		if part then table.insert(chainParts, part) end
	end
	local chainTopCF = CFrame.new(Point("ChainTop")) * rotation
	local rig = #chainParts > 0 and Kit.Rig(chainParts, chainTopCF) or nil
	local chainRest = {} -- about the hitbox, for putting back after a move
	for _, part in ipairs(chainParts) do chainRest[part] = hitbox.CFrame:ToObjectSpace(part.CFrame) end

	ctx:OnCleanup(function()
		for part, b in pairs(base) do
			if part.Parent then
				part.Color = b.Color
				part.Material = b.Material
			end
		end
		for part, rel in pairs(chainRest) do
			if part.Parent and hitbox.Parent then part.CFrame = hitbox.CFrame * rel end
		end
	end)

	--..Lights: two invisible local hosts (the PointLight at the bulb, the SpotLight over the open bottom)..--
	local pointHost = ctx:Part({Name = "FloorLampBulb", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(Point("Light")) * rotation})
	local point = Instance.new("PointLight")
	point.Color = LIGHT_COLOR
	point.Range = math.min(MAX_RANGE, POINT_RANGE * s)
	point.Brightness = 0
	point.Shadows = false -- inside the shade: a shadowed light would be swallowed by the panels
	point.Enabled = false
	point.Parent = pointHost
	local spotHost = ctx:Part({Name = "FloorLampSpot", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(Point("Spot")) * rotation})
	local spot = Instance.new("SpotLight")
	spot.Color = LIGHT_COLOR
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = SPOT_ANGLE
	spot.Range = math.min(MAX_RANGE, SPOT_RANGE * s)
	spot.Brightness = 0
	spot.Shadows = true -- the shade's rim cuts a round pool of light on the floor
	spot.Enabled = false
	spot.Parent = spotHost

	local click = ctx:Sound(spotHost, FunAssets.Sfx.Click, {Name = "Click", Volume = 0.45, RollOffMaxDistance = 40})

	--..Look for a given glow (0 off .. 1 on)..--
	local shown = -1
	local function Show(g)
		if g == shown or (math.abs(g - shown) < 0.002 and g > 0 and g < 1) then return end -- the ends always land exactly
		shown = g
		local on = g > 0.02
		point.Enabled = on
		spot.Enabled = on
		point.Brightness = POINT_BRIGHTNESS * g
		spot.Brightness = SPOT_BRIGHTNESS * g
		for part, b in pairs(base) do
			if part.Parent then
				local lit, neon
				if part == glowTop then
					lit, neon = GLOW_COLOR, true
				elseif part == bulb then
					lit, neon = BULB_COLOR, true
				else
					lit, neon = SHADE_NEON and SHADE_NEON_COLOR or SHADE_LIT, SHADE_NEON
				end
				part.Material = (neon and on) and Enum.Material.Neon or b.Material
				part.Color = b.Color:Lerp(lit, g)
			end
		end
	end

	--..State: only eases the glow (a dusk / dawn switch changes it too, with no hand on the chain)..--
	local wantOn, glow, first = false, 0, true
	ctx:OnState("On", function(value)
		local on = value == true
		if on == wantOn and not first then return end
		local live = not first and ctx:CameraDistance() <= SNAP_RANGE
		first = false
		wantOn = on
		if not live then
			glow = on and 1 or 0
			Show(glow)
		end
	end)
	Show(glow)

	--..Hand switch (B.OnEvent "Tug"): tug the chain and click..--
	local tugAt = -math.huge
	ctx.FloorLampTug = function()
		if not ctx:Alive() or ctx:CameraDistance() > SNAP_RANGE then return end
		tugAt = os.clock()
		click.TimePosition = 0
		click:Play()
	end

	--..Per frame: ease the glow, tug the chain (both idle once settled)..--
	local tugging = false
	ctx:Step(function(dt)
		local target = wantOn and 1 or 0
		if glow ~= target then
			local step = dt / (wantOn and WARM_UP or COOL_DOWN)
			glow = (target > glow) and math.min(target, glow + step) or math.max(target, glow - step)
			Show(glow)
		end
		if rig then
			local t = (os.clock() - tugAt) / TUG_TIME
			if t < 1 then
				tugging = true
				Kit.PoseRig(rig, chainTopCF * CFrame.new(0, -TUG_DEPTH * s * math.sin(math.pi * t), 0))
			elseif tugging then
				tugging = false
				Kit.PoseRig(rig, chainTopCF)
			end
		end
	end)
end

--..Server events: "Tug" = someone pulled the chain (the prompt), not the day / night switch..--
function B.OnEvent(_model, action, _payload, ctx)
	if action == "Tug" and ctx.FloorLampTug then ctx.FloorLampTug() end
end

return B
]======]
SOURCES['S_FloorLamp'] = [======[
--[[
	FloorLamp  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package HomeHearth
	Server half of the READING FLOOR LAMP (fun-builds/CONTRACT.md; model = models/build_FloorLamp.py, Home, Cost 300).
	  * one prompt at the pull-chain bead (Pivot_Switch): "Lamp on" while off, "Lamp off" while on. Anyone may
	    flip it (nothing to grief); a short debounce stops a double press flickering it
	  * state Fun_On (true / false). The client half draws the light (PointLight in the shade + a SpotLight
	    shining down through its open bottom) and the glowing Neon shade / diffuser / bulb from it
	  * event "Tug" (ctx:Fire, all clients) only when a PLAYER pulls the chain: the client tugs the chain and
	    clicks. The dusk / dawn switch changes the state alone, so a plot's lamps don't all click at nightfall
	  * DAY / NIGHT: the lamp starts ON at night and OFF by day (placed, moved, mended, server start), and every
	    dusk switches it on and every dawn switches it off - read from DayNightCycle's workspace attributes
	    IsNight (bool) / CyclePhase ("Night"). In between, people may flip it whenever they like
	No economy.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local PROMPT_DISTANCE = 8                            -- studs (x the build's scale when it is scaled up)
local TOGGLE_DEBOUNCE = 0.4                          -- seconds between two toggles
local SWITCH_FALLBACK = Vector3.new(0.3, 4.64, -0.3) -- authored, used when Pivot_Switch is missing

local B = {}
B.Keys = {"FloorLamp"}

--..Helpers..--
local function IsNight()
	local flag = workspace:GetAttribute("IsNight")
	if type(flag) == "boolean" then return flag end
	return workspace:GetAttribute("CyclePhase") == "Night"
end

--..Behaviour..--
function B.Server(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end

	--..Prompt on an invisible helper at the pull-chain bead..--
	local spot = Kit.Pivot(model, "Switch") or Kit.ToWorld(model, SWITCH_FALLBACK)
	local anchor = ctx:Part({
		Name = "FloorLampSwitch",
		Size = Vector3.new(0.6, 0.6, 0.6),
		Transparency = 1,
		CFrame = CFrame.new(spot) * hitbox.CFrame.Rotation,
	})
	local prompt = ctx:Prompt(anchor, {
		Action = "Lamp on",
		Object = "Floor Lamp",
		Distance = PROMPT_DISTANCE * math.max(1, ctx.Scale),
		Name = "LampPrompt",
	})

	--..State..--
	local function Apply(on)
		ctx:SetState("On", on)
		prompt.ActionText = on and "Lamp off" or "Lamp on"
	end

	--.. dusk on, dawn off (only on a real change: IsNight and CyclePhase both fire around a phase change)
	local night = IsNight()
	Apply(night)
	local function OnCycle()
		local now = IsNight()
		if now == night then return end
		night = now
		Apply(now)
	end
	ctx:Connect(workspace:GetAttributeChangedSignal("IsNight"), OnCycle)
	ctx:Connect(workspace:GetAttributeChangedSignal("CyclePhase"), OnCycle)

	--.. anyone flips it by hand
	local last = 0
	ctx:Connect(prompt.Triggered, function(player)
		if not ctx:Alive() or not ctx:HumanoidOf(player) then return end
		local now = os.clock()
		if now - last < TOGGLE_DEBOUNCE then return end
		last = now
		Apply(ctx:GetState("On") ~= true)
		ctx:Fire("Tug")
	end)
end

return B
]======]
MODELS = {}
MODELS['Fireplace'] = {Attrs = {Pivot_ClockCentre = Vector3.new(0.0, 5.175, -1.47), Pivot_Fire = Vector3.new(0.0, 0.95, -0.2), Pivot_Light = Vector3.new(0.0, 1.7, -1.55), Pivot_Chimney = Vector3.new(0.0, 7.0, 0.25), Pivot_Prompt = Vector3.new(0.0, 1.9, -1.95), Cost = 1500.0, DisplayName = "Fireplace"}, Parts = {
	{Name = "Plinth", Shape = "Block", Size = Vector3.new(7.1, 0.45, 2.35), CF = {0.0, 0.225, 0.125, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "a9a397", Material = "Slate", T = 0.0, Collide = true},
	{Name = "Hearth", Shape = "Block", Size = Vector3.new(6.6, 0.45, 1.0), CF = {0.0, 0.225, -1.55, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "a9a397", Material = "Slate", T = 0.0, Collide = true},
	{Name = "HearthEdge", Shape = "Cylinder", Size = Vector3.new(6.6, 0.45, 0.45), CF = {0.0, 0.225, -2.05, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "a9a397", Material = "Slate", T = 0.0, Collide = true},
	{Name = "PierL", Shape = "Block", Size = Vector3.new(1.75, 3.62, 2.25), CF = {2.625, 2.24, 0.125, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "b4553d", Material = "Brick", T = 0.0, Collide = true},
	{Name = "PierR", Shape = "Block", Size = Vector3.new(1.75, 3.62, 2.25), CF = {-2.625, 2.24, 0.125, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "b4553d", Material = "Brick", T = 0.0, Collide = true},
	{Name = "Lintel", Shape = "Block", Size = Vector3.new(3.6, 0.8, 2.25), CF = {0.0, 3.65, 0.125, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "b4553d", Material = "Brick", T = 0.0, Collide = true},
	{Name = "BackSkin", Shape = "Block", Size = Vector3.new(3.6, 2.87, 0.3), CF = {0.0, 1.865, 1.1, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "b4553d", Material = "Brick", T = 0.0, Collide = true},
	{Name = "FireboxBack", Shape = "Block", Size = Vector3.new(2.6, 2.83, 0.57), CF = {0.0, 1.865, 0.685, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "2b2624", Material = "Slate", T = 0.0, Collide = true},
	{Name = "FireboxSideL", Shape = "Block", Size = Vector3.new(0.08, 2.83, 1.5055), CF = {1.49, 1.865, -0.27, -0.94324, 0.0, 0.33213, 0.0, 1.0, -0.0, -0.33213, 0.0, -0.94324}, Color = "2b2624", Material = "Slate", T = 0.0, Collide = true},
	{Name = "FireboxSideR", Shape = "Block", Size = Vector3.new(0.08, 2.83, 1.5055), CF = {-1.49, 1.865, -0.27, -0.94324, 0.0, -0.33213, 0.0, 1.0, -0.0, 0.33213, -0.0, -0.94324}, Color = "2b2624", Material = "Slate", T = 0.0, Collide = true},
	{Name = "FireboxFloor", Shape = "Block", Size = Vector3.new(3.5, 0.06, 1.5), CF = {0.0, 0.47, -0.22, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "2b2624", Material = "Slate", T = 0.0, Collide = true},
	{Name = "Ash", Shape = "Block", Size = Vector3.new(2.9, 0.05, 1.2), CF = {0.0, 0.515, -0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8c8580", Material = "Slate", T = 0.0, Collide = false},
	{Name = "SurroundL", Shape = "Block", Size = Vector3.new(0.6, 2.8, 0.18), CF = {2.04, 1.85, -1.07, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9d2c3", Material = "Limestone", T = 0.0, Collide = true},
	{Name = "SurroundR", Shape = "Block", Size = Vector3.new(0.6, 2.8, 0.18), CF = {-2.04, 1.85, -1.07, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9d2c3", Material = "Limestone", T = 0.0, Collide = true},
	{Name = "SurroundTop", Shape = "Block", Size = Vector3.new(4.68, 0.58, 0.18), CF = {0.0, 3.51, -1.07, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9d2c3", Material = "Limestone", T = 0.0, Collide = true},
	{Name = "Keystone", Shape = "Block", Size = Vector3.new(0.56, 0.7, 0.28), CF = {0.0, 3.51, -1.12, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "e8e1d2", Material = "Limestone", T = 0.0, Collide = true},
	{Name = "MantelShelf", Shape = "Block", Size = Vector3.new(7.6, 0.35, 1.15), CF = {0.0, 4.2, -1.025, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "MantelEdge", Shape = "Cylinder", Size = Vector3.new(7.6, 0.35, 0.35), CF = {0.0, 4.2, -1.6, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "MantelCove", Shape = "Block", Size = Vector3.new(7.2, 0.14, 0.62), CF = {0.0, 3.97, -1.27, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "CorbelL", Shape = "Block", Size = Vector3.new(0.42, 0.56, 0.49), CF = {3.05, 3.62, -1.215, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "CorbelFootL", Shape = "Wedge", Size = Vector3.new(0.42, 0.5, 0.49), CF = {3.05, 3.1, -1.215, -1.0, -0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "CorbelR", Shape = "Block", Size = Vector3.new(0.42, 0.56, 0.49), CF = {-3.05, 3.62, -1.215, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "CorbelFootR", Shape = "Wedge", Size = Vector3.new(0.42, 0.5, 0.49), CF = {-3.05, 3.1, -1.215, -1.0, -0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Breast", Shape = "Block", Size = Vector3.new(5.4, 2.6, 1.95), CF = {0.0, 5.33, 0.275, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "b4553d", Material = "Brick", T = 0.0, Collide = true},
	{Name = "ShoulderL", Shape = "Wedge", Size = Vector3.new(1.95, 0.75, 0.84), CF = {3.09, 4.4, 0.275, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, Color = "b4553d", Material = "Brick", T = 0.0, Collide = true},
	{Name = "ShoulderR", Shape = "Wedge", Size = Vector3.new(1.95, 0.75, 0.84), CF = {-3.09, 4.4, 0.275, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, Color = "b4553d", Material = "Brick", T = 0.0, Collide = true},
	{Name = "Crown", Shape = "Block", Size = Vector3.new(5.8, 0.2, 2.2), CF = {0.0, 6.72, 0.2, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "d9d2c3", Material = "Limestone", T = 0.0, Collide = true},
	{Name = "CrownCap", Shape = "Block", Size = Vector3.new(5.4, 0.2, 1.9), CF = {0.0, 6.9, 0.25, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "a9a397", Material = "Slate", T = 0.0, Collide = true},
	{Name = "AndironBarL", Shape = "Block", Size = Vector3.new(0.13, 0.16, 1.32), CF = {0.95, 0.58, -0.27, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = true},
	{Name = "AndironPostL", Shape = "Cylinder", Size = Vector3.new(0.71, 0.15, 0.15), CF = {0.95, 0.845, -0.86, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = true},
	{Name = "AndironKnobL", Shape = "Ball", Size = Vector3.new(0.24, 0.24, 0.24), CF = {0.95, 1.24, -0.86, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "AndironBarR", Shape = "Block", Size = Vector3.new(0.13, 0.16, 1.32), CF = {-0.95, 0.58, -0.27, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = true},
	{Name = "AndironPostR", Shape = "Cylinder", Size = Vector3.new(0.71, 0.15, 0.15), CF = {-0.95, 0.845, -0.86, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = true},
	{Name = "AndironKnobR", Shape = "Ball", Size = Vector3.new(0.24, 0.24, 0.24), CF = {-0.95, 1.24, -0.86, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Log1", Shape = "Cylinder", Size = Vector3.new(2.5, 0.5, 0.5), CF = {0.05, 0.91, -0.45, 0.99756, 0.0, 0.06976, 0.0, 1.0, 0.0, -0.06976, 0.0, 0.99756}, Color = "5e3b1f", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Log1CapA", Shape = "Cylinder", Size = Vector3.new(0.06, 0.4, 0.4), CF = {1.29695, 0.91, -0.5372, 0.99756, 0.0, 0.06976, 0.0, 1.0, -0.0, -0.06976, 0.0, 0.99756}, Color = "d8b077", Material = "Wood", T = 0.0, Collide = false},
	{Name = "Log1CapB", Shape = "Cylinder", Size = Vector3.new(0.06, 0.4, 0.4), CF = {-1.19696, 0.91, -0.3628, 0.99756, 0.0, 0.06976, 0.0, 1.0, -0.0, -0.06976, 0.0, 0.99756}, Color = "d8b077", Material = "Wood", T = 0.0, Collide = false},
	{Name = "Log2", Shape = "Cylinder", Size = Vector3.new(2.4, 0.54, 0.54), CF = {-0.05, 0.93, 0.1, 0.99863, 0.0, -0.05234, 0.0, 1.0, 0.0, 0.05234, 0.0, 0.99863}, Color = "5e3b1f", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Log3", Shape = "Cylinder", Size = Vector3.new(2.2, 0.46, 0.46), CF = {0.0, 1.31, -0.17, 0.9703, 0.0, -0.24192, 0.0, 1.0, 0.0, 0.24192, 0.0, 0.9703}, Color = "5e3b1f", Material = "Wood", T = 0.0, Collide = true},
	{Name = "Log3CapA", Shape = "Cylinder", Size = Vector3.new(0.06, 0.36, 0.36), CF = {1.06733, 1.31, 0.09611, 0.9703, 0.0, -0.24192, 0.0, 1.0, 0.0, 0.24192, -0.0, 0.9703}, Color = "d8b077", Material = "Wood", T = 0.0, Collide = false},
	{Name = "Log3CapB", Shape = "Cylinder", Size = Vector3.new(0.06, 0.36, 0.36), CF = {-1.06733, 1.31, -0.43611, 0.9703, 0.0, -0.24192, 0.0, 1.0, 0.0, 0.24192, -0.0, 0.9703}, Color = "d8b077", Material = "Wood", T = 0.0, Collide = false},
	{Name = "Ember1", Shape = "Ball", Size = Vector3.new(0.36, 0.36, 0.36), CF = {0.42, 0.57, -0.8, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3a2f2a", Material = "Slate", T = 0.0, Collide = false},
	{Name = "Ember2", Shape = "Ball", Size = Vector3.new(0.32, 0.32, 0.32), CF = {-0.4, 0.56, -0.82, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3a2f2a", Material = "Slate", T = 0.0, Collide = false},
	{Name = "Ember3", Shape = "Block", Size = Vector3.new(0.42, 0.16, 0.3), CF = {0.02, 0.56, -0.86, 0.90631, 0.0, 0.42262, 0.0, 1.0, 0.0, -0.42262, 0.0, 0.90631}, Color = "3a2f2a", Material = "Slate", T = 0.0, Collide = false},
	{Name = "Ember4", Shape = "Ball", Size = Vector3.new(0.36, 0.36, 0.36), CF = {-0.68, 0.58, -0.7, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "3a2f2a", Material = "Slate", T = 0.0, Collide = false},
	{Name = "Ember5", Shape = "Block", Size = Vector3.new(0.36, 0.15, 0.28), CF = {0.72, 0.56, -0.66, 0.93969, 0.0, -0.34202, 0.0, 1.0, 0.0, 0.34202, 0.0, 0.93969}, Color = "3a2f2a", Material = "Slate", T = 0.0, Collide = false},
	{Name = "EmberSeam1", Shape = "Block", Size = Vector3.new(1.7, 0.07, 0.09), CF = {0.05, 0.74, -0.62, 0.99756, 0.0, 0.06976, 0.04933, 0.70711, -0.70538, -0.04933, 0.70711, 0.70538}, Color = "3a2f2a", Material = "Slate", T = 0.0, Collide = false},
	{Name = "EmberSeam2", Shape = "Block", Size = Vector3.new(1.1, 0.07, 0.05), CF = {0.02, 0.93, -0.695, 0.99756, 0.0, 0.06976, 0.0, 1.0, 0.0, -0.06976, 0.0, 0.99756}, Color = "3a2f2a", Material = "Slate", T = 0.0, Collide = false},
	{Name = "EmberSeam3", Shape = "Block", Size = Vector3.new(1.2, 0.07, 0.05), CF = {0.0, 1.23, -0.385, 0.9703, 0.0, -0.24192, 0.0, 1.0, 0.0, 0.24192, 0.0, 0.9703}, Color = "3a2f2a", Material = "Slate", T = 0.0, Collide = false},
	{Name = "ClockBase", Shape = "Block", Size = Vector3.new(1.4, 0.1, 0.62), CF = {0.0, 4.415, -1.1, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = false},
	{Name = "ClockBody", Shape = "Block", Size = Vector3.new(1.2, 0.85, 0.5), CF = {0.0, 4.89, -1.1, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = false},
	{Name = "ClockArch", Shape = "Cylinder", Size = Vector3.new(0.5, 1.2, 1.2), CF = {0.0, 5.315, -1.1, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = false},
	{Name = "ClockFinial", Shape = "Ball", Size = Vector3.new(0.16, 0.16, 0.16), CF = {0.0, 5.935, -1.1, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ClockBezel", Shape = "Cylinder", Size = Vector3.new(0.08, 0.92, 0.92), CF = {0.0, 5.175, -1.37, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ClockFace", Shape = "Cylinder", Size = Vector3.new(0.06, 0.76, 0.76), CF = {0.0, 5.175, -1.41, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "ClockHour", Shape = "Block", Size = Vector3.new(0.07, 0.24, 0.05), CF = {0.07372, 5.22662, -1.445, 0.57358, 0.81915, 0.0, -0.81915, 0.57358, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "ClockMinute", Shape = "Block", Size = Vector3.new(0.05, 0.34, 0.05), CF = {-0.12124, 5.245, -1.455, 0.5, -0.86603, 0.0, 0.86603, 0.5, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "ClockPin", Shape = "Ball", Size = Vector3.new(0.09, 0.09, 0.09), CF = {0.0, 5.175, -1.47, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PicFrame", Shape = "Block", Size = Vector3.new(1.35, 1.1, 0.1), CF = {-1.55, 4.899, -0.865, 1.0, 0.0, 0.0, 0.0, 0.97815, -0.20791, 0.0, 0.20791, 0.97815}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = false},
	{Name = "PicCanvas", Shape = "Block", Size = Vector3.new(1.07, 0.82, 0.08), CF = {-1.55, 4.90524, -0.89434, 1.0, 0.0, 0.0, 0.0, 0.97815, -0.20791, 0.0, 0.20791, 0.97815}, Color = "9fd4e6", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PicHill", Shape = "Ellipsoid", Size = Vector3.new(1.05, 0.5, 0.05), CF = {-1.43, 4.56142, -1.00832, 1.0, 0.0, 0.0, 0.0, 0.97815, -0.20791, 0.0, 0.20791, 0.97815}, Color = "5aa845", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "PicSun", Shape = "Cylinder", Size = Vector3.new(0.06, 0.24, 0.24), CF = {-1.85, 5.11022, -0.89678, 0.0, 0.0, -1.0, -0.20792, 0.97815, 0.0, 0.97815, 0.20792, 0.0}, Color = "f2c13d", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Candle1Saucer", Shape = "Cylinder", Size = Vector3.new(0.08, 0.46, 0.46), CF = {2.95, 4.395, -1.2, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Candle1Holder", Shape = "Cylinder", Size = Vector3.new(0.15, 0.28, 0.28), CF = {2.95, 4.5, -1.2, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Candle1", Shape = "Cylinder", Size = Vector3.new(0.95, 0.2, 0.2), CF = {2.95, 5.03, -1.2, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CandleFlame1", Shape = "Ellipsoid", Size = Vector3.new(0.15, 0.3, 0.15), CF = {2.95, 5.645, -1.2, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ffb347", Material = "Neon", T = 1.0, Collide = false},
	{Name = "Candle2Saucer", Shape = "Cylinder", Size = Vector3.new(0.08, 0.46, 0.46), CF = {2.35, 4.395, -1.3, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Candle2Holder", Shape = "Cylinder", Size = Vector3.new(0.15, 0.28, 0.28), CF = {2.35, 4.5, -1.3, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Candle2", Shape = "Cylinder", Size = Vector3.new(0.6, 0.2, 0.2), CF = {2.35, 4.855, -1.3, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CandleFlame2", Shape = "Ellipsoid", Size = Vector3.new(0.15, 0.3, 0.15), CF = {2.35, 5.295, -1.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ffb347", Material = "Neon", T = 1.0, Collide = false},
	{Name = "Candle3Saucer", Shape = "Cylinder", Size = Vector3.new(0.08, 0.46, 0.46), CF = {-2.95, 4.395, -1.2, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Candle3Holder", Shape = "Cylinder", Size = Vector3.new(0.15, 0.28, 0.28), CF = {-2.95, 4.5, -1.2, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Candle3", Shape = "Cylinder", Size = Vector3.new(0.95, 0.2, 0.2), CF = {-2.95, 5.03, -1.2, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "CandleFlame3", Shape = "Ellipsoid", Size = Vector3.new(0.15, 0.3, 0.15), CF = {-2.95, 5.645, -1.2, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "ffb347", Material = "Neon", T = 1.0, Collide = false},
	{Name = "CukeStand", Shape = "Block", Size = Vector3.new(0.62, 0.12, 0.34), CF = {1.4, 4.425, -1.2, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "6b4423", Material = "Wood", T = 0.0, Collide = false},
	{Name = "GoldenCuke", Shape = "Ellipsoid", Size = Vector3.new(0.78, 0.28, 0.28), CF = {1.4, 4.605, -1.2, 0.9418, -0.13236, -0.30902, 0.13917, 0.99027, 0.0, 0.30601, -0.04301, 0.95106}, Color = "f2c13d", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ToolBase", Shape = "Cylinder", Size = Vector3.new(0.08, 0.6, 0.6), CF = {-2.85, 0.48, -1.55, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ToolPole", Shape = "Cylinder", Size = Vector3.new(1.95, 0.1, 0.1), CF = {-2.85, 1.475, -1.55, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ToolKnob", Shape = "Ball", Size = Vector3.new(0.2, 0.2, 0.2), CF = {-2.85, 2.51, -1.55, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ToolBar", Shape = "Block", Size = Vector3.new(0.62, 0.06, 0.06), CF = {-2.85, 2.3, -1.55, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ToolPoker", Shape = "Cylinder", Size = Vector3.new(1.52, 0.06, 0.06), CF = {-2.57, 1.56, -1.55, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ToolPokerHook", Shape = "Block", Size = Vector3.new(0.14, 0.05, 0.05), CF = {-2.51, 0.87, -1.55, 0.81915, -0.57358, 0.0, 0.57358, 0.81915, 0.0, 0.0, 0.0, 1.0}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ToolShovel", Shape = "Cylinder", Size = Vector3.new(1.32, 0.06, 0.06), CF = {-3.13, 1.66, -1.55, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = false},
	{Name = "ToolShovelBlade", Shape = "Block", Size = Vector3.new(0.3, 0.32, 0.05), CF = {-3.13, 0.85, -1.57, 1.0, 0.0, 0.0, 0.0, 0.99027, -0.13917, 0.0, 0.13917, 0.99027}, Color = "2f3640", Material = "Metal", T = 0.0, Collide = false},
	{Name = "SpareLog1", Shape = "Cylinder", Size = Vector3.new(0.8, 0.44, 0.44), CF = {2.52, 0.67, -1.58, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "5e3b1f", Material = "Wood", T = 0.0, Collide = false},
	{Name = "SpareLog1Cap", Shape = "Cylinder", Size = Vector3.new(0.06, 0.34, 0.34), CF = {2.52, 0.67, -1.98, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "d8b077", Material = "Wood", T = 0.0, Collide = false},
	{Name = "SpareLog2", Shape = "Cylinder", Size = Vector3.new(0.8, 0.42, 0.42), CF = {2.98, 0.66, -1.58, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "5e3b1f", Material = "Wood", T = 0.0, Collide = false},
	{Name = "SpareLog2Cap", Shape = "Cylinder", Size = Vector3.new(0.06, 0.32, 0.32), CF = {2.98, 0.66, -1.98, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "d8b077", Material = "Wood", T = 0.0, Collide = false},
	{Name = "SpareLog3", Shape = "Cylinder", Size = Vector3.new(0.8, 0.42, 0.42), CF = {2.75, 1.05, -1.58, 0.0, 0.0, 1.0, 0.0, 1.0, -0.0, -1.0, 0.0, 0.0}, Color = "5e3b1f", Material = "Wood", T = 0.0, Collide = false},
	{Name = "SpareLog3Cap", Shape = "Cylinder", Size = Vector3.new(0.06, 0.32, 0.32), CF = {2.75, 1.05, -1.98, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "d8b077", Material = "Wood", T = 0.0, Collide = false},
}}
MODELS['FloorLamp'] = {Attrs = {Pivot_Light = Vector3.new(0.0, 6.1, 0.0), Pivot_Spot = Vector3.new(0.0, 5.75, -0.36), Pivot_Switch = Vector3.new(0.3, 4.64, -0.3), Pivot_ChainTop = Vector3.new(0.3, 5.7, -0.3), Cost = 300.0, DisplayName = "Floor Lamp"}, Parts = {
	{Name = "BaseFoot", Shape = "Cylinder", Size = Vector3.new(0.16, 2.0, 2.0), CF = {0.0, 0.08, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "BaseWeight", Shape = "Ellipsoid", Size = Vector3.new(1.76, 0.56, 1.76), CF = {0.0, 0.28, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "23262c", Material = "Metal", T = 0.0, Collide = true},
	{Name = "BaseTrim", Shape = "Cylinder", Size = Vector3.new(0.07, 1.86, 1.86), CF = {0.0, 0.17, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "BaseCollar", Shape = "Cylinder", Size = Vector3.new(0.26, 0.36, 0.36), CF = {0.0, 0.53, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = true},
	{Name = "Pole", Shape = "Cylinder", Size = Vector3.new(5.15, 0.2, 0.2), CF = {0.0, 3.075, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = true},
	{Name = "Collar1", Shape = "Cylinder", Size = Vector3.new(0.16, 0.3, 0.3), CF = {0.0, 2.08, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "a8841c", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Collar2", Shape = "Cylinder", Size = Vector3.new(0.16, 0.3, 0.3), CF = {0.0, 4.43, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "a8841c", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Tray", Shape = "Cylinder", Size = Vector3.new(0.08, 1.5, 1.5), CF = {0.0, 3.05, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "8a5a2b", Material = "Wood", T = 0.0, Collide = true},
	{Name = "TrayRim", Shape = "Cylinder", Size = Vector3.new(0.1, 1.58, 1.58), CF = {0.0, 3.02, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "TrayHub", Shape = "Cylinder", Size = Vector3.new(0.18, 0.32, 0.32), CF = {0.0, 2.94, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "a8841c", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Book", Shape = "Block", Size = Vector3.new(0.5, 0.12, 0.38), CF = {-0.38, 3.14, 0.2, 0.97815, 0.0, 0.20791, 0.0, 1.0, 0.0, -0.20791, 0.0, 0.97815}, Color = "d9443c", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "BookPages", Shape = "Block", Size = Vector3.new(0.46, 0.08, 0.42), CF = {-0.38, 3.14, 0.2, 0.97815, 0.0, 0.20791, 0.0, 1.0, 0.0, -0.20791, 0.0, 0.97815}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Mug", Shape = "Cylinder", Size = Vector3.new(0.31, 0.26, 0.26), CF = {0.3, 3.235, -0.22, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "MugHandle", Shape = "Cylinder", Size = Vector3.new(0.06, 0.16, 0.16), CF = {0.46, 3.24, -0.22, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, Color = "f2f0ea", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "MugCoffee", Shape = "Cylinder", Size = Vector3.new(0.06, 0.2, 0.2), CF = {0.3, 3.37, -0.22, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "6b4423", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "Socket", Shape = "Cylinder", Size = Vector3.new(0.4, 0.3, 0.3), CF = {0.0, 5.65, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "3b4350", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Bulb", Shape = "Ball", Size = Vector3.new(0.6, 0.6, 0.6), CF = {0.0, 6.1, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "f4efe0", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "ShadePanel01", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {0.23411, 6.425, 1.17694, 0.98079, -0.0536, 0.18758, 0.0, 0.96152, 0.27472, -0.19509, -0.26944, 0.94305}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim01", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {0.27913, 5.61731, 1.40328, 0.98079, -0.0536, 0.18758, 0.0, 0.96152, 0.27472, -0.19509, -0.26944, 0.94305}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel02", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {0.66668, 6.425, 0.99776, 0.83147, -0.15263, 0.53419, 0.0, 0.96152, 0.27472, -0.55557, -0.22842, 0.79948}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim02", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {0.79489, 5.61731, 1.18964, 0.83147, -0.15263, 0.53419, 0.0, 0.96152, 0.27472, -0.55557, -0.22842, 0.79948}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel03", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {0.99776, 6.425, 0.66668, 0.55557, -0.22842, 0.79948, 0.0, 0.96152, 0.27472, -0.83147, -0.15263, 0.53419}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim03", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {1.18964, 5.61731, 0.79489, 0.55557, -0.22842, 0.79948, 0.0, 0.96152, 0.27472, -0.83147, -0.15263, 0.53419}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel04", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {1.17694, 6.425, 0.23411, 0.19509, -0.26944, 0.94305, 0.0, 0.96152, 0.27472, -0.98079, -0.0536, 0.18758}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim04", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {1.40328, 5.61731, 0.27913, 0.19509, -0.26944, 0.94305, 0.0, 0.96152, 0.27472, -0.98079, -0.0536, 0.18758}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel05", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {1.17694, 6.425, -0.23411, -0.19509, -0.26944, 0.94305, 0.0, 0.96152, 0.27472, -0.98079, 0.0536, -0.18758}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim05", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {1.40328, 5.61731, -0.27913, -0.19509, -0.26944, 0.94305, 0.0, 0.96152, 0.27472, -0.98079, 0.0536, -0.18758}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel06", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {0.99776, 6.425, -0.66668, -0.55557, -0.22842, 0.79948, 0.0, 0.96152, 0.27472, -0.83147, 0.15263, -0.53419}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim06", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {1.18964, 5.61731, -0.79489, -0.55557, -0.22842, 0.79948, 0.0, 0.96152, 0.27472, -0.83147, 0.15263, -0.53419}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel07", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {0.66668, 6.425, -0.99776, -0.83147, -0.15263, 0.53419, 0.0, 0.96152, 0.27472, -0.55557, 0.22842, -0.79948}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim07", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {0.79489, 5.61731, -1.18964, -0.83147, -0.15263, 0.53419, 0.0, 0.96152, 0.27472, -0.55557, 0.22842, -0.79948}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel08", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {0.23411, 6.425, -1.17694, -0.98079, -0.0536, 0.18758, 0.0, 0.96152, 0.27472, -0.19509, 0.26944, -0.94305}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim08", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {0.27913, 5.61731, -1.40328, -0.98079, -0.0536, 0.18758, 0.0, 0.96152, 0.27472, -0.19509, 0.26944, -0.94305}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel09", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {-0.23411, 6.425, -1.17694, -0.98079, 0.0536, -0.18758, 0.0, 0.96152, 0.27472, 0.19509, 0.26944, -0.94305}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim09", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {-0.27913, 5.61731, -1.40328, -0.98079, 0.0536, -0.18758, 0.0, 0.96152, 0.27472, 0.19509, 0.26944, -0.94305}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel10", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {-0.66668, 6.425, -0.99776, -0.83147, 0.15263, -0.53419, 0.0, 0.96152, 0.27472, 0.55557, 0.22842, -0.79948}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim10", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {-0.79489, 5.61731, -1.18964, -0.83147, 0.15263, -0.53419, 0.0, 0.96152, 0.27472, 0.55557, 0.22842, -0.79948}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel11", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {-0.99776, 6.425, -0.66668, -0.55557, 0.22842, -0.79948, 0.0, 0.96152, 0.27472, 0.83147, 0.15263, -0.53419}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim11", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {-1.18964, 5.61731, -0.79489, -0.55557, 0.22842, -0.79948, 0.0, 0.96152, 0.27472, 0.83147, 0.15263, -0.53419}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel12", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {-1.17694, 6.425, -0.23411, -0.19509, 0.26944, -0.94305, 0.0, 0.96152, 0.27472, 0.98079, 0.0536, -0.18758}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim12", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {-1.40328, 5.61731, -0.27913, -0.19509, 0.26944, -0.94305, 0.0, 0.96152, 0.27472, 0.98079, 0.0536, -0.18758}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel13", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {-1.17694, 6.425, 0.23411, 0.19509, 0.26944, -0.94305, 0.0, 0.96152, 0.27472, 0.98079, -0.0536, 0.18758}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim13", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {-1.40328, 5.61731, 0.27913, 0.19509, 0.26944, -0.94305, 0.0, 0.96152, 0.27472, 0.98079, -0.0536, 0.18758}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel14", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {-0.99776, 6.425, 0.66668, 0.55557, 0.22842, -0.79948, 0.0, 0.96152, 0.27472, 0.83147, -0.15263, 0.53419}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim14", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {-1.18964, 5.61731, 0.79489, 0.55557, 0.22842, -0.79948, 0.0, 0.96152, 0.27472, 0.83147, -0.15263, 0.53419}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel15", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {-0.66668, 6.425, 0.99776, 0.83147, 0.15263, -0.53419, 0.0, 0.96152, 0.27472, 0.55557, -0.22842, 0.79948}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim15", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {-0.79489, 5.61731, 1.18964, 0.83147, 0.15263, -0.53419, 0.0, 0.96152, 0.27472, 0.55557, -0.22842, 0.79948}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadePanel16", Shape = "Block", Size = Vector3.new(0.5868, 1.82, 0.06), CF = {-0.23411, 6.425, 1.17694, 0.98079, 0.0536, -0.18758, 0.0, 0.96152, 0.27472, 0.19509, -0.26944, 0.94305}, Color = "f3e7cc", Material = "Fabric", T = 0.0, Collide = true},
	{Name = "ShadeTrim16", Shape = "Block", Size = Vector3.new(0.6068, 0.14, 0.1), CF = {-0.27913, 5.61731, 1.40328, 0.98079, 0.0536, -0.18758, 0.0, 0.96152, 0.27472, 0.19509, -0.26944, 0.94305}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadeRim", Shape = "Cylinder", Size = Vector3.new(0.22, 2.17, 2.17), CF = {0.0, 7.23, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Fabric", T = 0.0, Collide = false},
	{Name = "ShadeGlowTop", Shape = "Cylinder", Size = Vector3.new(0.06, 1.8, 1.8), CF = {0.0, 7.35, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "e9dcbd", Material = "SmoothPlastic", T = 0.0, Collide = false},
	{Name = "FinialStem", Shape = "Cylinder", Size = Vector3.new(0.15, 0.08, 0.08), CF = {0.0, 7.425, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "Finial", Shape = "Ball", Size = Vector3.new(0.2, 0.2, 0.2), CF = {0.0, 7.56, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PullChain", Shape = "Cylinder", Size = Vector3.new(1.0, 0.05, 0.05), CF = {0.3, 5.2, -0.3, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "PullBead", Shape = "Ball", Size = Vector3.new(0.16, 0.16, 0.16), CF = {0.3, 4.64, -0.3, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, Color = "c9a227", Material = "Metal", T = 0.0, Collide = false},
	{Name = "SwitchArm", Shape = "Cylinder", Size = Vector3.new(0.3536, 0.09, 0.09), CF = {0.205, 5.72, -0.205, 0.70711, 0.0, 0.70711, 0.0, 1.0, -0.0, -0.70711, 0.0, 0.70711}, Color = "a8841c", Material = "Metal", T = 0.0, Collide = false},
}}
------------------------------------------------------------------ HomeHearth headless tests (Fireplace + FloorLamp)
-- run: py tests/HomeHearth/gen.py   (mock.luau + module sources + parts.json models + this file -> run.luau)

------------------------------------------------------------------ loader (os.clock is controllable; os.date must not be used)
local env = getfenv(1)
local realOs = os
MockClock = 1000
local osDateCalls = 0
env.os = setmetatable({
	clock = function() return MockClock end,
	date = function(...) osDateCalls += 1 return realOs.date(...) end,
}, {__index = realOs})
local function SetClockTime(t) rawget(MockLighting, "_p").ClockTime = t end
SetClockTime(15.5) -- 15:30 game time -> the mantel clock shows 3:30
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
		_insts = {folder}, _conns = {}, _states = {}, _fired = {}}
	function ctx:Fire(action, payload) table.insert(self._fired, {Action = action, Payload = payload}) end
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

--========================================================================== FIREPLACE (client)
do
	local C = require({Name = "C_Fireplace"})
	local scale = 1.2
	local place = CFrame.new(40, 4.2, -12) * CFrame.Angles(0, math.rad(90), 0)
	local model = MakePlaced("Fireplace", scale, place)
	local hitbox = Kit.Hitbox(model)
	local origin = Kit.Origin(model)
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 5, -14)))
	local snap = Snapshot(model)
	local ctx = Run(C, model)

	local fires = FindAll(ctx._insts, "Fire")
	check(#fires == 2, "fireplace: 2 Fire instances (got " .. #fires .. ")")
	for _, f in ipairs(fires) do check(f.Enabled == false, "fireplace: fire starts off") end
	local light = FindIn(ctx._insts, "PointLight")
	check(light ~= nil and light.Enabled == false, "fireplace: light exists and starts off")
	check(light and light.Range == math.min(60, 20 * scale), "fireplace: light range 20 x scale")
	check(light and light.Shadows == true, "fireplace: light casts shadows")
	local host = FindIn(ctx._insts, "Part", "FireplaceFire")
	check(host and vnear(host.Position, Kit.Pivot(model, "Fire"), 1e-5), "fireplace: fire host at Pivot_Fire")
	check(light and vnear(light.Parent.WorldPosition, Kit.Pivot(model, "Light"), 1e-5), "fireplace: light at Pivot_Light")
	local chim = FindIn(ctx._insts, "Part", "FireplaceChimney")
	check(chim and vnear(chim.Position, Kit.Pivot(model, "Chimney"), 1e-5), "fireplace: chimney host at Pivot_Chimney")
	local flames = Kit.Parts(model, "CandleFlame")
	local embers = Kit.Parts(model, "Ember")
	check(#flames == 3, "fireplace: 3 candle flames")
	check(#embers == 8, "fireplace: 8 ember parts (got " .. #embers .. ")")
	for _, p in ipairs(flames) do check(p.Transparency == 1, "fireplace: candle " .. p.Name .. " starts out") end
	local sparks = FindIn(ctx._insts, "ParticleEmitter", "Sparks")
	local puff = FindIn(ctx._insts, "ParticleEmitter", "Puff")
	local smoke = FindIn(ctx._insts, "ParticleEmitter", "ChimneySmoke")
	local ignite = FindIn(ctx._insts, "Sound", "Ignite")
	local douse = FindIn(ctx._insts, "Sound", "Douse")
	local crackle = FindIn(ctx._insts, "Sound", "Crackle")
	check(sparks and puff and smoke and ignite and douse and crackle, "fireplace: emitters + sounds exist")
	check(#FindAll(ctx._insts, "PointLight") + #FindAll(ctx._insts, "SpotLight") <= 2, "fireplace: <= 2 lights")

	--.. a cold frame changes nothing on the embers
	Everys(ctx)
	Frames(ctx, 0.1)
	for _, p in ipairs(embers) do check(p.Material == snap[p].Material, "fireplace: cold ember " .. p.Name .. " untouched") end

	--.. clock hands show the game's 15:30 as 3:30 (hour 105 deg, minute 180 deg clockwise seen from the front)
	local function HandAngle(name)
		local part = Kit.Part(model, name)
		local up = origin.Rotation:Inverse() * part.CFrame.UpVector -- authored axes
		return math.deg(math.atan2(-up.X, up.Y)) % 360, up.Z
	end
	local h, hz = HandAngle("ClockHour")
	local mnt, mz = HandAngle("ClockMinute")
	check(near(h, 105, 0.01) and near(hz, 0, 1e-6), ("fireplace: hour hand at 105 deg (got %.3f)"):format(h))
	check(near(mnt, 180, 0.01) and near(mz, 0, 1e-6), ("fireplace: minute hand at 180 deg (got %.3f)"):format(mnt))
	--.. the hand still pivots about the face centre (its distance to the centre is unchanged)
	local centre = Kit.Pivot(model, "ClockCentre")
	local hourPart = Kit.Part(model, "ClockHour")
	check(near((hourPart.Position - centre).Magnitude, (snap[hourPart].CFrame.Position - centre).Magnitude, 1e-5), "fireplace: hour hand turns about the clock centre")
	check(osDateCalls == 0, "fireplace: clock does not read the viewer's local time (os.date)")
	--.. the hands follow Lighting.ClockTime within CLOCK_RATE (9:15 -> hour 277.5, minute 90)
	SetClockTime(9.25)
	Frames(ctx, 0.12)
	h = HandAngle("ClockHour")
	mnt = HandAngle("ClockMinute")
	check(near(h, 277.5, 0.01) and near(mnt, 90, 0.01), ("fireplace: hands follow ClockTime 9.25 (got %.3f / %.3f)"):format(h, mnt))
	--.. night jump 16:00 -> 0:00: the mantel clock snaps to 12:00
	SetClockTime(0)
	Frames(ctx, 0.12)
	h = HandAngle("ClockHour")
	mnt = HandAngle("ClockMinute")
	check(near(h, 0, 0.01) or near(h, 360, 0.01), ("fireplace: midnight hour hand at 0 (got %.3f)"):format(h))
	check(near(mnt, 0, 0.01) or near(mnt, 360, 0.01), ("fireplace: midnight minute hand at 0 (got %.3f)"):format(mnt))
	SetClockTime(15.5)
	Frames(ctx, 0.12)

	--.. light it (camera near: live)
	model:SetAttribute("Fun_Lit", true)
	check(ignite.IsPlaying == true, "fireplace: ignite sound on lighting")
	check((rawget(sparks, "_emitted") or 0) == 18, "fireplace: spark burst on lighting")
	for _, f in ipairs(fires) do check(f.Enabled == true, "fireplace: fire on once lit") end
	check(sparks.Enabled == true, "fireplace: sparks on once lit")
	check(crackle.IsPlaying == true, "fireplace: crackle plays near")
	Frames(ctx, 0.5)
	check(flames[1].Transparency == 0, "fireplace: first candle lit after 0.5 s")
	check(flames[3].Transparency == 1, "fireplace: third candle not yet lit after 0.5 s")
	check(light.Enabled and light.Brightness > 0.3 and light.Brightness < 2.2, "fireplace: light fading in")
	Frames(ctx, 1.5)
	for _, p in ipairs(flames) do check(p.Transparency == 0, "fireplace: candle " .. p.Name .. " lit after 2 s") end
	check(light.Brightness > 1.5 and light.Brightness < 3.2, ("fireplace: light at full flicker (%.2f)"):format(light.Brightness))
	check(light.Range <= 60 and light.Range > 15, "fireplace: range sane")
	check(smoke.Enabled == true, "fireplace: chimney smoke while burning")
	check(crackle.Volume > 0.45, "fireplace: crackle at volume")
	for _, p in ipairs(embers) do
		check(p.Material == Enum.Material.Neon, "fireplace: ember " .. p.Name .. " Neon while lit")
		check(p.Color.R > 0.85 and p.Color.B < 0.2, "fireplace: ember " .. p.Name .. " glows orange " .. tostring(p.Color))
	end
	local mesh = flames[1]:FindFirstChildOfClass("SpecialMesh")
	check(mesh and not vnear(mesh.Scale, Vector3.one, 1e-4), "fireplace: candle flame flickers (mesh scale)")

	--.. put it out
	MockClock += 0.1
	model:SetAttribute("Fun_Lit", false)
	check(douse.IsPlaying == true, "fireplace: douse sound on putting out")
	check((rawget(puff, "_emitted") or 0) == 14, "fireplace: smoke puff on putting out")
	for _, f in ipairs(fires) do check(f.Enabled == false, "fireplace: fire off when put out") end
	Frames(ctx, 0.05)
	for _, p in ipairs(flames) do check(p.Transparency == 1, "fireplace: candle " .. p.Name .. " out with the fire") end
	Frames(ctx, 1)
	check(embers[1].Material == Enum.Material.Neon, "fireplace: embers still glow 1 s after putting out")
	check(light.Enabled, "fireplace: light still dying down 1 s after")
	Frames(ctx, 3)
	check(light.Enabled == false, "fireplace: light off once cold")
	check(smoke.Enabled == false, "fireplace: no chimney smoke once cold")
	for _, p in ipairs(embers) do
		check(p.Material == snap[p].Material and p.Color == snap[p].Color, "fireplace: ember " .. p.Name .. " back to charcoal")
	end
	Everys(ctx)
	check(crackle.IsPlaying == false, "fireplace: crackle stops")
	for _, f in ipairs(fires) do check(f.Size == 2, ("fireplace: cold fire shrunk to the 2 floor (%.2f)"):format(f.Size)) end

	--.. relit while this viewer is far away: heat snaps to 1, and so must the flame size
	CameraAt(hitbox.Position + Vector3.new(0, 0, 150))
	model:SetAttribute("Fun_Lit", true)
	local want = {math.clamp(3.2 * scale, 2, 30), math.clamp(2.2 * scale, 2, 30)}
	table.sort(want)
	local got = {fires[1].Size, fires[2].Size}
	table.sort(got)
	check(near(got[1], want[1], 1e-6) and near(got[2], want[2], 1e-6),
		("fireplace: fires at full size after a far-away relight (%.2f / %.2f, want %.2f / %.2f)"):format(got[1], got[2], want[1], want[2]))
	model:SetAttribute("Fun_Lit", false)
	for _, f in ipairs(fires) do check(f.Size == 2, "fireplace: far-away put-out snaps the flames small") end
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 5, -14)))

	--.. relight and stop while lit: every part back as authored
	model:SetAttribute("Fun_Lit", true)
	Frames(ctx, 2)
	Stop(ctx)
	SameAsSnapshot(model, snap, "fireplace cleanup")
	for _, i in ipairs(ctx._insts) do check(rawget(i, "_destroyed") == true, "fireplace: " .. i.Name .. " destroyed on cleanup") end

	--.. streamed in while already lit, camera far: straight to the blaze, no fanfare
	CameraAt(hitbox.Position + Vector3.new(0, 0, 150))
	local ctx2 = Run(C, model)
	local ignite2 = FindIn(ctx2._insts, "Sound", "Ignite")
	check(ignite2.IsPlaying == false, "fireplace: no ignite sound when streamed in lit")
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 5, -14)))
	Everys(ctx2)
	Frames(ctx2, 1 / 60)
	local light2 = FindIn(ctx2._insts, "PointLight")
	check(light2.Enabled and light2.Brightness > 1.5, "fireplace: streamed-in lit fire is at full blaze at once")
	for _, p in ipairs(flames) do check(p.Transparency == 0, "fireplace: streamed-in candles already lit") end
	Stop(ctx2)
	SameAsSnapshot(model, snap, "fireplace cleanup 2")

	--.. a picture from FunAssets.Pictures replaces the painted landscape; broken cleanup keeps the fade
	FunAssets.Pictures = {"rbxassetid://123456"}
	model:SetAttribute("Fun_Lit", false)
	local ctx3 = Run(C, model)
	local decal = FindIn(ctx3._insts, "Decal")
	check(decal and decal.Texture == "rbxassetid://123456" and decal.Parent == Kit.Part(model, "PicCanvas"), "fireplace: picture decal on the canvas")
	check(Kit.Part(model, "PicHill").Transparency == 1 and Kit.Part(model, "PicSun").Transparency == 1, "fireplace: painted scene hidden under the picture")
	model:SetAttribute("Broken", true)
	Stop(ctx3)
	check(Kit.Part(model, "PicHill").Transparency == 0.65, "fireplace: broken cleanup leaves the hill at the broken fade")
	model:SetAttribute("Broken", nil)
	FunAssets.Pictures = {}
	model.Parent = nil
end

--========================================================================== FIREPLACE (server)
do
	local S = require({Name = "S_Fireplace"})
	local model = MakePlaced("Fireplace", 1, CFrame.new(0, 3.5, 0))
	local ctx = MakeServerCtx(model)
	local ok, err = pcall(S.Server, model, ctx)
	check(ok, "fireplace server errored: " .. tostring(err))
	local prompt = FindIn(ctx._insts, "ProximityPrompt")
	check(prompt ~= nil, "fireplace server: prompt")
	check(prompt.ActionText == "Light fire" and prompt.ObjectText == "Fireplace", "fireplace server: prompt text")
	check(vnear(prompt.Parent.Position, Kit.Pivot(model, "Prompt"), 1e-5), "fireplace server: prompt at Pivot_Prompt")
	check(model:GetAttribute("Fun_Lit") == false, "fireplace server: starts out")
	local player = {Alive = true, UserId = 7}
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_Lit") == true and prompt.ActionText == "Put out", "fireplace server: lit by the prompt")
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_Lit") == true, "fireplace server: debounce holds a double press")
	MockClock += 1
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_Lit") == false and prompt.ActionText == "Light fire", "fireplace server: put out by the prompt")
	MockClock += 1
	prompt.Triggered:Fire({Alive = false})
	check(model:GetAttribute("Fun_Lit") == false, "fireplace server: a dead player can't light it")
	--.. night does not light it
	workspace:SetAttribute("IsNight", true)
	check(model:GetAttribute("Fun_Lit") == false, "fireplace server: night does not light it")
	workspace:SetAttribute("IsNight", false)
	model.Parent = nil
end

--========================================================================== FLOOR LAMP (client)
do
	local C = require({Name = "C_FloorLamp"})
	local place = CFrame.new(-20, 3.9, 8) * CFrame.Angles(0, math.rad(30), 0)
	local model = MakePlaced("FloorLamp", 1, place)
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 6, -12)))
	local snap = Snapshot(model)
	local ctx = Run(C, model)
	local point = FindIn(ctx._insts, "PointLight")
	local spot = FindIn(ctx._insts, "SpotLight")
	check(point and spot, "lamp: point + spot lights")
	check(#FindAll(ctx._insts, "PointLight") + #FindAll(ctx._insts, "SpotLight") == 2, "lamp: exactly 2 lights")
	check(point.Enabled == false and spot.Enabled == false, "lamp: starts off (Fun_On unset)")
	check(spot.Face == Enum.NormalId.Bottom and spot.Shadows == true, "lamp: spot faces down, shadows on")
	check(vnear(spot.Parent.CFrame.UpVector, Vector3.new(0, 1, 0), 1e-6), "lamp: spot host upright (Bottom face = down)")
	check(vnear(point.Parent.Position, Kit.Pivot(model, "Light"), 1e-5), "lamp: point light at Pivot_Light")
	check(vnear(spot.Parent.Position, Kit.Pivot(model, "Spot"), 1e-5), "lamp: spot light at Pivot_Spot")
	local glowTop, bulb = Kit.Part(model, "ShadeGlowTop"), Kit.Part(model, "Bulb")
	local panels = Kit.Parts(model, "ShadePanel")
	check(glowTop and bulb and #panels == 16, "lamp: glow parts found")
	local bead = Kit.Part(model, "PullBead")
	local beadRest = bead.Position
	local click = FindIn(ctx._insts, "Sound", "Click")

	--.. the dusk switch (state alone, no Tug event): the glow eases in, no click, no tug
	model:SetAttribute("Fun_On", true)
	check(click.IsPlaying == false, "lamp: no click from the dusk switch")
	Frames(ctx, 0.12)
	check(vnear(bead.Position, beadRest, 1e-6), "lamp: no chain tug from the dusk switch")
	check(point.Enabled and point.Brightness < 1.3, "lamp: dusk switch warms up")
	Frames(ctx, 0.5)
	check(point.Enabled and near(point.Brightness, 1.3, 1e-6), "lamp: on after the dusk switch")
	model:SetAttribute("Fun_On", false)
	Frames(ctx, 0.6)
	check(point.Enabled == false, "lamp: off after the dawn switch")

	--.. switch on by hand (live): state + the server's Tug event
	model:SetAttribute("Fun_On", true)
	C.OnEvent(model, "Tug", nil, ctx)
	check(click.IsPlaying == true, "lamp: click on a hand switch")
	Frames(ctx, 0.12)
	check(bead.Position.Y < beadRest.Y - 0.1, ("lamp: chain tugged down (dy %.3f)"):format(bead.Position.Y - beadRest.Y))
	check(point.Enabled and point.Brightness < 1.3, "lamp: warming up")
	Frames(ctx, 0.5)
	check(vnear(bead.Position, beadRest, 1e-6), "lamp: chain back at rest after the tug")
	check(point.Enabled and near(point.Brightness, 1.3, 1e-6) and spot.Enabled and near(spot.Brightness, 2.6, 1e-6), "lamp: full brightness when on")
	check(glowTop.Material == Enum.Material.Neon and bulb.Material == Enum.Material.Neon, "lamp: diffuser + bulb Neon when on")
	check(glowTop.Color == Color3.fromRGB(255, 226, 166), "lamp: diffuser lit colour")
	for _, p in ipairs(panels) do
		check(p.Material == Enum.Material.Neon and p.Color == Color3.fromRGB(255, 228, 175), "lamp: shade panel " .. p.Name .. " glows warm cream Neon when on")
	end

	--.. off
	model:SetAttribute("Fun_On", false)
	Frames(ctx, 0.6)
	check(point.Enabled == false and spot.Enabled == false, "lamp: lights off")
	check(glowTop.Material == snap[glowTop].Material and glowTop.Color == snap[glowTop].Color, "lamp: diffuser back when off")
	check(panels[5].Color == snap[panels[5]].Color and panels[5].Material == snap[panels[5]].Material, "lamp: panels back to Fabric when off")
	--.. a Tug seen from far away: no click, no tug
	click:Stop()
	CameraAt(Kit.Hitbox(model).Position + Vector3.new(0, 0, 150))
	C.OnEvent(model, "Tug", nil, ctx)
	check(click.IsPlaying == false, "lamp: no click for a far-away Tug")
	CameraAt(Kit.ToWorld(model, Vector3.new(0, 6, -12)))
	Frames(ctx, 0.1)
	check(vnear(bead.Position, beadRest, 1e-6), "lamp: no tug for a far-away Tug")
	local okOther = pcall(C.OnEvent, model, "Other", nil, ctx)
	local okEarly = pcall(C.OnEvent, model, "Tug", nil, {}) -- a ctx whose Client never ran (not streamed in yet)
	check(okOther and okEarly, "lamp: OnEvent ignores other actions and a not-yet-running ctx")

	--.. on + stop mid-tug: every part back
	model:SetAttribute("Fun_On", true)
	C.OnEvent(model, "Tug", nil, ctx)
	Frames(ctx, 0.1)
	check(bead.Position.Y < beadRest.Y - 0.05, "lamp: mid-tug before the stop")
	Stop(ctx)
	SameAsSnapshot(model, snap, "lamp cleanup")

	--.. streamed in while on: lit at once, no click, no tug
	CameraAt(Kit.Hitbox(model).Position + Vector3.new(0, 0, 150))
	local ctx2 = Run(C, model)
	check(FindIn(ctx2._insts, "Sound", "Click").IsPlaying == false, "lamp: no click when streamed in on")
	local point2 = FindIn(ctx2._insts, "PointLight")
	check(point2.Enabled and near(point2.Brightness, 1.3, 1e-6), "lamp: streamed-in lamp already on")
	Frames(ctx2, 0.1)
	check(vnear(bead.Position, beadRest, 1e-6), "lamp: no tug when streamed in")
	Stop(ctx2)
	SameAsSnapshot(model, snap, "lamp cleanup 2")
	model.Parent = nil
end

--========================================================================== FLOOR LAMP (server)
do
	local S = require({Name = "S_FloorLamp"})
	workspace:SetAttribute("IsNight", false)
	workspace:SetAttribute("CyclePhase", "Day")
	local model = MakePlaced("FloorLamp", 1, CFrame.new(5, 3.9, 5))
	local ctx = MakeServerCtx(model)
	local ok, err = pcall(S.Server, model, ctx)
	check(ok, "lamp server errored: " .. tostring(err))
	local prompt = FindIn(ctx._insts, "ProximityPrompt")
	check(prompt and prompt.ActionText == "Lamp on" and prompt.ObjectText == "Floor Lamp", "lamp server: prompt")
	check(vnear(prompt.Parent.Position, Kit.Pivot(model, "Switch"), 1e-5), "lamp server: prompt at the pull-chain bead")
	check(model:GetAttribute("Fun_On") == false, "lamp server: off by day")
	workspace:SetAttribute("CyclePhase", "Night")
	workspace:SetAttribute("IsNight", true)
	check(model:GetAttribute("Fun_On") == true and prompt.ActionText == "Lamp off", "lamp server: on at dusk")
	check(#ctx._fired == 0, "lamp server: no Tug event from the start state or the dusk switch")
	local player = {Alive = true, UserId = 9}
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_On") == false and prompt.ActionText == "Lamp on", "lamp server: switched off by hand at night")
	check(#ctx._fired == 1 and ctx._fired[1].Action == "Tug", "lamp server: a hand switch fires Tug")
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_On") == false, "lamp server: debounce")
	check(#ctx._fired == 1, "lamp server: no Tug for a debounced press")
	workspace:SetAttribute("CyclePhase", "Night") -- same value: no signal
	check(model:GetAttribute("Fun_On") == false, "lamp server: stays off by hand through the night")
	MockClock += 1
	prompt.Triggered:Fire(player)
	check(model:GetAttribute("Fun_On") == true, "lamp server: back on by hand")
	workspace:SetAttribute("CyclePhase", "PreparingDay")
	workspace:SetAttribute("IsNight", false)
	check(model:GetAttribute("Fun_On") == false, "lamp server: off at dawn")
	check(#ctx._fired == 2, ("lamp server: dawn fired no Tug (%d events)"):format(#ctx._fired))
	MockClock += 1
	prompt.Triggered:Fire({Alive = false})
	check(#ctx._fired == 2, "lamp server: a dead player's press fires nothing")
	--.. a lamp placed at night starts on
	local model2 = MakePlaced("FloorLamp", 1, CFrame.new(15, 3.9, 5))
	workspace:SetAttribute("IsNight", true)
	local ctx2 = MakeServerCtx(model2)
	S.Server(model2, ctx2)
	check(model2:GetAttribute("Fun_On") == true, "lamp server: placed at night -> on")
	--.. no IsNight attribute: CyclePhase decides
	workspace:SetAttribute("CyclePhase", "Night")
	workspace:SetAttribute("IsNight", nil)
	check(model2:GetAttribute("Fun_On") == true, "lamp server: CyclePhase fallback -> night on")
	workspace:SetAttribute("CyclePhase", "Day")
	check(model2:GetAttribute("Fun_On") == false, "lamp server: CyclePhase fallback -> day off")
end

print(("%d checks, %d failed"):format(checks, fails))
if fails > 0 then error("TESTS FAILED") end
