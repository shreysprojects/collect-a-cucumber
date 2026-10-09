--!nocheck
-- Minimal Roblox mock for running fun-build behaviours headless (Vector3/Vector2/CFrame maths real, Instances as
-- property bags). Only what the GardenLights modules + FunBuildKit touch.

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
function CFrame.new(x, y, z)
	if x == nil then return cf(v3(0, 0, 0), I3) end
	if type(x) == "table" then return cf(x, I3) end
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
Color3 = {fromRGB = function(r, g, b) return {R = r / 255, G = g / 255, B = b / 255} end, new = function(r, g, b) return {R = r, G = g, B = b} end}
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
	if a.R then return {Keypoints = {{Time = 0, Value = a}, {Time = 1, Value = b or a}}} end
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
	local old = props[k]
	props[k] = v
	if old ~= v then
		-- GetPropertyChangedSignal: fired immediately (the harder case for handlers that write back)
		local list = rawget(t, "_s")[k]
		if list then
			MockSignalDepth = (MockSignalDepth or 0) + 1
			assert(MockSignalDepth < 20, "property signal loop on " .. tostring(k))
			for _, c in ipairs(table.clone(list)) do
				if c.Connected then c.Fn() end
			end
			MockSignalDepth -= 1
		end
	end
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
function InstM.GetPropertyChangedSignal(self, k)
	return {Connect = function(_, fn)
		local s = rawget(self, "_s")
		s[k] = s[k] or {}
		local c = {Connected = true, Fn = fn}
		function c.Disconnect() c.Connected = false end
		table.insert(s[k], c)
		return c
	end}
end
function InstM.GetAttribute(self, k) return rawget(self, "_a")[k] end
function InstM.SetAttribute(self, k, v) rawget(self, "_a")[k] = v end
function InstM.Destroy(self) if self.Parent then self.Parent = nil end rawset(self, "_destroyed", true) end
function InstM.IsDescendantOf(self, other) local p = self.Parent while p do if p == other then return true end p = p.Parent end return false end
function InstM.Emit(self, n) rawset(self, "_emitted", (rawget(self, "_emitted") or 0) + n) end
function InstM.Play(self) rawget(self, "_p").IsPlaying = true end
function InstM.Stop(self) rawget(self, "_p").IsPlaying = false end
function InstM.Clone(self) error("Clone not mocked") end
function InstM.GetBoundingBox(self) error("not mocked") end
local ALL = {}
local function newInst(className)
	local t = setmetatable({_p = {ClassName = className, Name = className}, _c = {}, _a = {}, _s = {}}, Inst)
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
SOURCES['C_Lantern'] = [======[
--[[
	Lantern  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLights
	Client-only behaviour for the three garden lanterns (no server half: nothing is shared but the clock).
	  Lantern_A PostLantern (x2.1)   Lantern_B PaperLantern (x1.7)   Lantern_C GardenLantern (x1.5)
	  * a warm PointLight (255,190,120, no shadows - it sits inside the glass / paper) on a runtime Attachment at
	    Pivot_<V>_Light, parented to the build part nearest that point (A_Glass / B_Paper / C_Glass), with a
	    gentle flame flicker of Brightness (every frame) and Range (10 Hz)
	  * NIGHT = workspace CyclePhase == "Night" (DayNightCycle) or Lighting.ClockTime < 6.5 / > 18: brighter and a
	    longer range, eased in / out over ~1.5 s; the post lamp (A) also lets a few fireflies drift around its head
	  * the paper lantern (B) sways about Pivot_B_Hang: +/-4 deg over 2.8 s plus a small cross sway, posed every
	    frame from Kit.Now() so every client swings in step; the light rides along on B_Paper
	The swung parts (B_Paper, B_Brass, B_Core, B_CoreTip, B_Tassel) are put back at rest on cleanup, relative to
	the build's CURRENT hitbox (a move re-runs this; a broken build never has its CFrames touched by the server).
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local LIGHT_COLOR = Color3.fromRGB(255, 190, 120)
local NIGHT_EASE = 1.5           -- seconds to blend day <-> night
local MAX_RANGE = 60             -- PointLight.Range engine cap
local SWAY_DEG, SWAY_PERIOD = 4, 2.8
local CROSS_DEG, CROSS_PERIOD = 1.2, 4.3
local TEX_DOT = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- soft round glow (engine built-in)
--.. per variant. Ranges are AUTHORED studs (x ctx.Scale); Brightness is absolute
local VARIANTS = {
	A = {DayBrightness = 1.2, NightBrightness = 2.6, DayRange = 5, NightRange = 9.5, Flicker = 0.06, Fireflies = true},
	B = {DayBrightness = 1.0, NightBrightness = 2.2, DayRange = 5, NightRange = 8.5, Flicker = 0.07,
		Hang = "Hang", Swing = {"Brass", "Paper", "Core", "CoreTip", "Tassel"}},
	C = {DayBrightness = 0.9, NightBrightness = 2.0, DayRange = 4, NightRange = 7.5, Flicker = 0.06},
}
--.. the fireflies' drift box around the post lamp head, AUTHORED studs (x ctx.Scale)
local FIREFLY_BOX = Vector3.new(2.2, 1.8, 2.2)

local B = {}
B.StepRange = 200

--..Helpers..--
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

local function Lerp(a, b, t) return a + (b - a) * t end

local function IsNight()
	if workspace:GetAttribute("CyclePhase") == "Night" then return true end
	local clock = Lighting.ClockTime
	return clock < 6.5 or clock > 18
end

--.. a smooth -1..1-ish flame wobble: slow noise + a quicker shimmer (t = server time, same on every client).
--.. math.noise loses precision on ~1e9 inputs (server time), so it gets the time folded into a short cycle
local function Flicker(t, seed, amount)
	local tt = t % 997
	return 1 + amount * (math.noise(tt * 2.3, seed, 0.5) * 1.4 + 0.45 * math.sin(tt * 7.3 + seed))
end

--.. the build part (of this variant) whose centre is nearest a world point
local function NearestPart(model, prefix, point)
	local best, bestDistance
	for _, part in ipairs(Kit.Parts(model, prefix)) do
		local d = (part.Position - point).Magnitude
		if not bestDistance or d < bestDistance then best, bestDistance = part, d end
	end
	return best
end

--.. Pivot_<V>_Light missing (an older template): the flame part, else the hitbox centre
local function FallbackLightPoint(model, prefix)
	for _, name in ipairs({"Flame", "Core"}) do
		local part = Kit.Part(model, prefix .. name)
		if part then return part.Position end
	end
	return Kit.Hitbox(model).Position
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local cfg = VARIANTS[ctx.Variant or "A"] or VARIANTS.A
	local prefix = ctx.Variant and (ctx.Variant .. "_") or ""
	local scale = ctx.Scale
	local seed = (hitbox.Position.X * 0.371 + hitbox.Position.Z * 0.713) % 97

	--..Light..--
	local lightPoint = Kit.Pivot(model, Kit.VName(model, "Light")) or FallbackLightPoint(model, prefix)
	local host = NearestPart(model, prefix, lightPoint)
	if not host then return end
	local lightAt = ctx:Add(Instance.new("Attachment"))
	lightAt.Name = "FunLanternLight"
	lightAt.Position = host.CFrame:PointToObjectSpace(lightPoint)
	lightAt.Parent = host
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Shadows = false -- it sits inside the glass / paper shell, which would swallow a shadowed light
	light.Brightness = cfg.DayBrightness
	light.Range = cfg.DayRange * scale
	light.Parent = lightAt

	--..Fireflies (post lamp, night only)..--
	local fireflies
	if cfg.Fireflies then
		local box = ctx:Part({
			Name = "FunFireflies", Transparency = 1, Size = FIREFLY_BOX * scale,
			CFrame = CFrame.new(lightPoint) * Kit.Origin(model).Rotation,
		})
		fireflies = Instance.new("ParticleEmitter")
		fireflies.Name = "Fireflies"
		fireflies.Texture = TEX_DOT
		fireflies.Rate = 3
		fireflies.Lifetime = NumberRange.new(3, 5)
		fireflies.Speed = NumberRange.new(0.12 * scale, 0.35 * scale)
		fireflies.SpreadAngle = Vector2.new(180, 180)
		fireflies.Acceleration = Vector3.new(0, 0.04 * scale, 0)
		fireflies.Drag = 0.6
		fireflies.RotSpeed = NumberRange.new(0)
		local s = 0.085 * scale -- a firefly pulses twice in its life
		fireflies.Size = NumberSequence.new({kp(0, 0), kp(0.15, s), kp(0.35, s * 0.3), kp(0.55, s * 1.1), kp(0.8, s * 0.4), kp(1, 0)})
		fireflies.Transparency = NumberSequence.new(0.05)
		fireflies.Color = ColorSequence.new(Color3.fromRGB(215, 255, 110), Color3.fromRGB(255, 214, 110))
		fireflies.LightEmission = 1
		fireflies.LightInfluence = 0
		fireflies.Enabled = false
		pcall(function() -- whole-box volume emission (engine shape API); without it they start on the box faces
			fireflies.Shape = Enum.ParticleEmitterShape.Box
			fireflies.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		end)
		fireflies.Parent = box
	end

	--..Paper lantern sway rig..--
	local rig, hangRel
	if cfg.Swing then
		local hang = model:GetAttribute("Pivot_" .. Kit.VName(model, cfg.Hang))
		local parts = {}
		for _, name in ipairs(cfg.Swing) do
			local part = Kit.Part(model, prefix .. name)
			if part then table.insert(parts, part) end
		end
		if typeof(hang) == "Vector3" and #parts > 0 then
			local origin = Kit.Origin(model)
			local hangCF = CFrame.new(origin:PointToWorldSpace(hang * scale)) * origin.Rotation
			hangRel = hitbox.CFrame:ToObjectSpace(hangCF) -- the hang point rides with the hitbox (moves re-run anyway)
			rig = Kit.Rig(parts, hangCF)
		end
	end

	--..Every frame: flicker, night blend, sway..--
	local night = IsNight() and 1 or 0
	local rangeClock = 1
	ctx:Step(function(dt, now)
		local target = IsNight() and 1 or 0
		night += (target - night) * math.min(1, dt * 3 / NIGHT_EASE)
		local f = Flicker(now, seed, cfg.Flicker)
		light.Brightness = Lerp(cfg.DayBrightness, cfg.NightBrightness, night) * f
		rangeClock += dt
		if rangeClock >= 0.1 then
			rangeClock = 0
			light.Range = math.min(MAX_RANGE, Lerp(cfg.DayRange, cfg.NightRange, night) * scale * (1 + (f - 1) * 0.4))
		end
		if fireflies then
			local on = night > 0.5
			if fireflies.Enabled ~= on then fireflies.Enabled = on end
		end
		if rig then
			local swing = math.rad(SWAY_DEG) * math.sin(now * 2 * math.pi / SWAY_PERIOD + seed)
			local cross = math.rad(CROSS_DEG) * math.sin(now * 2 * math.pi / CROSS_PERIOD + seed * 1.7)
			Kit.PoseRig(rig, hitbox.CFrame * hangRel * CFrame.Angles(cross, 0, swing))
		end
	end)

	--..Cleanup: the swung ball back at rest where the build is now..--
	return function()
		if rig and hitbox.Parent then Kit.PoseRig(rig, hitbox.CFrame * hangRel) end
	end
end

return B
]======]
SOURCES['C_TikiTorch'] = [======[
--[[
	TikiTorch  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLights
	Client-only behaviour for the three torches (no server half: nothing is shared but the clock).
	  TikiTorch_A BambooTorch (x1.5)   TikiTorch_B TikiHead (x1.5)   TikiTorch_C Brazier (x1.4)
	At Pivot_<V>_FlameAnchor (the Blender author's "hang a PointLight / Fire here" point) one local, invisible
	anchor part carries:
	  * a Fire, small, Size / Heat tuned per variant (the brazier burns lower and wider)
	  * a warm PointLight (no shadows: the neon flame meshes around it would block it) that flickers like a
	    real flame - Brightness every frame, Range at 10 Hz - and burns brighter / farther at NIGHT
	    (workspace CyclePhase == "Night" or Lighting.ClockTime < 6.5 / > 18, eased over ~1.5 s)
	  * rising embers (built-in soft glow texture, modest rate)
	  * a quiet crackle loop (FunAssets.Sfx.FireLoop) that only plays while the camera is within NEAR_SOUND studs
	Nothing on the build itself is touched, so there is nothing to restore.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = {Sfx = {}}
pcall(function() FunAssets = require(Modules:WaitForChild("FunAssets", 15)) end)

--..Config..--
local LIGHT_COLOR = Color3.fromRGB(255, 160, 80)
local FIRE_COLOR = Color3.fromRGB(255, 150, 60)
local FIRE_SECONDARY = Color3.fromRGB(224, 74, 31) -- the flame meshes' e04a1f tip
local NIGHT_EASE = 1.5          -- seconds to blend day <-> night
local MAX_RANGE = 60
local NEAR_SOUND = 40           -- studs camera <-> torch: the crackle plays inside this ...
local FAR_SOUND = 46            -- ... and stops beyond this (hysteresis)
local SOUND_VOLUME = 0.22
local TEX_DOT = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- soft round glow (engine built-in)
--.. per variant. FireSize / Range / ember speeds are AUTHORED studs (x ctx.Scale); Fire.Size is clamped to 2..30
local VARIANTS = {
	A = {FireSize = 1.5, Heat = 5, Embers = 6, DayBrightness = 1.4, NightBrightness = 2.4, DayRange = 5.5, NightRange = 9},
	B = {FireSize = 1.5, Heat = 6, Embers = 6, DayBrightness = 1.4, NightBrightness = 2.4, DayRange = 5.5, NightRange = 9},
	C = {FireSize = 2.0, Heat = 4, Embers = 9, DayBrightness = 1.6, NightBrightness = 2.7, DayRange = 5, NightRange = 8.5},
}
local FLICKER = 0.16            -- brightness wobble (fraction)

local B = {}
B.StepRange = 200

--..Helpers..--
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

local function Lerp(a, b, t) return a + (b - a) * t end

local function IsNight()
	if workspace:GetAttribute("CyclePhase") == "Night" then return true end
	local clock = Lighting.ClockTime
	return clock < 6.5 or clock > 18
end

--.. a lively flame wobble from server time (math.noise needs the ~1e9 clock folded into a short cycle)
local function Flicker(t, seed)
	local tt = t % 997
	return 1 + FLICKER * (math.noise(tt * 4.1, seed, 0.5) * 1.5 + 0.35 * math.sin(tt * 13.7 + seed) + 0.2 * math.sin(tt * 23.1 + seed * 2))
end

--.. Pivot_<V>_FlameAnchor missing (an older template): above the variant's flame core, else the hitbox top
local function FallbackAnchor(model, prefix)
	local core = Kit.Part(model, prefix .. "FlameCore")
	if core then return core.Position end
	local hitbox = Kit.Hitbox(model)
	return hitbox.Position + Vector3.new(0, hitbox.Size.Y * 0.4, 0)
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local cfg = VARIANTS[ctx.Variant or "A"] or VARIANTS.A
	local prefix = ctx.Variant and (ctx.Variant .. "_") or ""
	local scale = ctx.Scale
	local seed = (hitbox.Position.X * 0.529 + hitbox.Position.Z * 0.917) % 89

	--..Anchor (local, invisible) at the flame..--
	local point = Kit.Pivot(model, Kit.VName(model, "FlameAnchor")) or FallbackAnchor(model, prefix)
	local anchor = ctx:Part({
		Name = "FunTorchFlame", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(point) * Kit.Origin(model).Rotation,
	})

	--..Fire..--
	local fire = Instance.new("Fire")
	fire.Size = math.clamp(cfg.FireSize * scale, 2, 30)
	fire.Heat = cfg.Heat
	fire.Color = FIRE_COLOR
	fire.SecondaryColor = FIRE_SECONDARY
	fire.Parent = anchor

	--..Light..--
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Shadows = false
	light.Brightness = cfg.DayBrightness
	light.Range = cfg.DayRange * scale
	light.Parent = anchor

	--..Embers..--
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Texture = TEX_DOT
	embers.Rate = cfg.Embers
	embers.Lifetime = NumberRange.new(0.9, 1.7)
	embers.Speed = NumberRange.new(1.4 * scale, 2.8 * scale)
	embers.SpreadAngle = Vector2.new(22, 22)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Acceleration = Vector3.new(0, 0.8 * scale, 0)
	embers.Drag = 1.4
	embers.Size = NumberSequence.new({kp(0, 0.07 * scale), kp(0.6, 0.05 * scale), kp(1, 0)})
	embers.Transparency = NumberSequence.new({kp(0, 0), kp(0.7, 0.2), kp(1, 1)})
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 130)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 140, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 60, 20)),
	})
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Parent = anchor

	--..Crackle (near only)..--
	local crackle
	if FunAssets.Sfx.FireLoop then
		local ok, sound = pcall(function()
			return ctx:Sound(anchor, FunAssets.Sfx.FireLoop, {
				Name = "FunCrackle", Looped = true, Volume = SOUND_VOLUME, RollOffMinDistance = 5, RollOffMaxDistance = NEAR_SOUND,
			})
		end)
		if ok then crackle = sound end
	end
	if crackle then
		local function SyncSound()
			local d = ctx:CameraDistance()
			if d <= NEAR_SOUND and not crackle.IsPlaying then
				if crackle.TimeLength > 0 then crackle.TimePosition = (seed * 0.37) % crackle.TimeLength end -- torches out of step
				crackle:Play()
			elseif d > FAR_SOUND and crackle.IsPlaying then
				crackle:Stop()
			end
		end
		SyncSound()
		ctx:Every(0.5, SyncSound)
	end

	--..Every frame: flicker + night blend..--
	local night = IsNight() and 1 or 0
	local rangeClock = 1
	ctx:Step(function(dt, now)
		local target = IsNight() and 1 or 0
		night += (target - night) * math.min(1, dt * 3 / NIGHT_EASE)
		local f = Flicker(now, seed)
		light.Brightness = Lerp(cfg.DayBrightness, cfg.NightBrightness, night) * f
		rangeClock += dt
		if rangeClock >= 0.1 then
			rangeClock = 0
			light.Range = math.min(MAX_RANGE, Lerp(cfg.DayRange, cfg.NightRange, night) * scale * (1 + (f - 1) * 0.35))
		end
	end)
end

return B
]======]
SOURCES['C_Fountain'] = [======[
--[[
	Fountain  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLights
	Client half of the RUNNING FOUNTAIN (server half: ServerStorage.FunBehaviours.Fountain makes the water, jets
	and foam parts non-colliding so people can wade into the basin). Everything here is local VFX on one invisible
	anchor part at the build's authored origin, so no build part is touched and nothing needs restoring:
	  * the PLUME: droplets shoot up from Pivot_JetOrigin to just over Pivot_JetTop and fall back into the upper
	    bowl (Pivot_BowlWaterTop) - speed / lifetime solved from those pivots and one gravity G, so they land on
	    the water whatever the build's scale
	  * the five STREAMS: droplets ride the Jets mesh's five parabolas from the bowl lip down into the basin
	    (the curves of props/build_fountain.py _arc_points, re-solved here with the same gravity)
	  * SPLASH RINGS: flat expanding rings (built-in shockwave texture, lying on the water) where the streams hit
	    the basin water (Pivot_BasinWaterTop) and where the plume falls back into the bowl, a droplet kicked up
	    with each basin splash, and every PUFF_EVERY s a soft mist puff over a splash; a faint mist hangs over the
	    bowl all the time
	  * anyone walking through the basin water leaves ripple rings (checked every 0.3 s for every character)
	  * a looping water sound (FunAssets.Sfx.WaterLoop) only while the camera is within NEAR_SOUND studs
	Blender -> Roblox authored frame: (x, y, z) -> (x, z, -y); a stream at Blender angle a leaves along
	(cos a, 0, -sin a).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = {Sfx = {}}
pcall(function() FunAssets = require(Modules:WaitForChild("FunAssets", 15)) end)

--..Config..--
local G = 26                     -- AUTHORED studs/s^2 for every droplet (x ctx.Scale in the world; flight times are scale-free)
local PLUME_RATE = 12            -- droplets / s up the central plume
local PLUME_SPREAD = 11          -- degrees: the plume opens into an umbrella landing ~0.6 out from the finial
local PLUME_OVERSHOOT = 1.05     -- peak a hair over Pivot_JetTop
local STREAM_RATE = 2            -- droplets / s down EACH of the five streams
local DROP_SIZE = 0.13           -- AUTHORED studs
local BASIN_RING_EVERY = 0.4     -- s between splash rings where the streams land
local BOWL_RING_EVERY = 0.45     -- s between rings where the plume falls back
local PUFF_EVERY = 1.8           -- s between mist puffs over a basin splash
local RING_LIFT = 0.03           -- AUTHORED studs above the water plane
local BOWL_RING_R = {0.45, 0.72} -- AUTHORED radius band of the plume's splash rings (the finial is ~0.35 wide there)
local WADE_R = {1.15, 2.55}      -- AUTHORED radius band of basin water a character can wade in (pedestal .. wall)
local WADE_SPEED = 1.5           -- studs/s a character must move to leave ripples
local NEAR_SOUND = 40            -- studs camera <-> fountain: the water loop plays inside this ...
local FAR_SOUND = 46             -- ... and stops beyond this
local SOUND_VOLUME = 0.3
local WATER_COLOR = ColorSequence.new(Color3.fromRGB(228, 246, 255), Color3.fromRGB(160, 215, 250))
local RING_COLOR = Color3.fromRGB(230, 247, 255)
local MIST_COLOR = Color3.fromRGB(225, 240, 255)
local TEX_OVERRIDE = type(FunAssets.Textures) == "table" and FunAssets.Textures or {} -- the integrator may add verified images
local TEX = {
	Drop = TEX_OVERRIDE.Droplet or "rbxasset://textures/particles/explosion01_implosion_main.dds", -- soft round dot
	Ring = TEX_OVERRIDE.Ripple or "rbxasset://textures/particles/explosion01_shockwave_main.dds",  -- soft ring
	Mist = TEX_OVERRIDE.Mist or "rbxasset://textures/particles/smoke_main.dds",
}
--.. authored fallbacks when a template lacks the Pivot_* attributes
local DEFAULT_PIVOTS = {
	JetOrigin = Vector3.new(0, 3.62, 0), JetTop = Vector3.new(0, 4.20, 0),
	BowlWaterTop = Vector3.new(0, 2.50, 0), BasinWaterTop = Vector3.new(0, 0.72, 0),
}
--.. the five streams of the Jets mesh (build_fountain.py: JET_ANGLES, _arc_points; stream 4 is thrown shorter / flatter)
local JETS = {
	{Angle = 54, R0 = 1.50, DR = 0.88, Z0 = 2.52, Rise = 0.32, Z1 = 0.74},
	{Angle = 126, R0 = 1.50, DR = 0.88, Z0 = 2.52, Rise = 0.32, Z1 = 0.74},
	{Angle = 198, R0 = 1.50, DR = 0.88, Z0 = 2.52, Rise = 0.32, Z1 = 0.74},
	{Angle = 278, R0 = 1.50, DR = 0.70, Z0 = 2.52, Rise = 0.17, Z1 = 0.74},
	{Angle = 342, R0 = 1.50, DR = 0.88, Z0 = 2.52, Rise = 0.32, Z1 = 0.74},
}

local B = {}
B.StepRange = 180

--..Helpers..--
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

local function AuthoredPivot(model, name)
	local v = model:GetAttribute("Pivot_" .. name)
	return typeof(v) == "Vector3" and v or DEFAULT_PIVOTS[name]
end

--.. a stream's parabola (r = R0 + DR t, z = Z0 + v t - g t^2, through Z1 at t = 1 with its crest Rise over Z0)
--.. played in real time so its gravity is G: -> outward speed, upward speed (authored studs/s), flight time (s)
local function JetLaunch(jet)
	local d = jet.Z1 - jet.Z0
	local tc = (jet.Rise - math.sqrt(jet.Rise * jet.Rise - d * jet.Rise)) / d
	local v = 2 * jet.Rise / tc
	local g = jet.Rise / (tc * tc)
	local flight = math.sqrt(2 * g / G)
	return jet.DR / flight, v / flight, flight
end

local function Attach(parent, name, cf)
	local att = Instance.new("Attachment")
	att.Name = name
	att.CFrame = cf
	att.Parent = parent
	return att
end

--.. water droplets: stretched along their flight, falling at G. o = {Rate, Speed (world), Spread, Life, Direction, Size}
local function Droplets(parent, scale, o)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = o.Name or "FunDroplets"
	pe.Texture = TEX.Drop
	pe.Rate = o.Rate
	pe.Lifetime = NumberRange.new(o.Life * 0.94, o.Life)
	pe.Speed = NumberRange.new(o.Speed * 0.96, o.Speed * 1.03)
	pe.SpreadAngle = Vector2.new(o.Spread, o.Spread)
	pe.EmissionDirection = o.Direction or Enum.NormalId.Front
	pe.Acceleration = Vector3.new(0, -G * scale, 0)
	pe.Drag = 0
	local s = (o.Size or DROP_SIZE) * scale
	pe.Size = NumberSequence.new({kp(0, s * 0.8), kp(0.5, s), kp(1, s * 0.7)})
	pe.Transparency = NumberSequence.new({kp(0, 0.2), kp(0.8, 0.25), kp(1, 0.75)})
	pe.Color = WATER_COLOR
	pe.LightEmission = 0.35
	pe.LightInfluence = 0.6
	pe.Orientation = Enum.ParticleOrientation.VelocityParallel
	pcall(function() pe.Squash = NumberSequence.new(0.6) end) -- streaks along the flight (newer engine property)
	pe.Parent = parent
	return pe
end

--.. flat rings lying on the water (VelocityPerpendicular + a tiny upward speed), emitted by hand with :Emit
local function Rings(parent, scale, size0, size1, life, alpha)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "FunRings"
	pe.Texture = TEX.Ring
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(life * 0.9, life * 1.1)
	pe.Speed = NumberRange.new(0.02)
	pe.SpreadAngle = Vector2.zero
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	pe.Rotation = NumberRange.new(0, 360)
	pe.Size = NumberSequence.new({kp(0, size0 * scale), kp(1, size1 * scale)})
	pe.Transparency = NumberSequence.new({kp(0, alpha), kp(0.6, (1 + alpha) * 0.5 + 0.1), kp(1, 1)})
	pe.Color = ColorSequence.new(RING_COLOR)
	pe.LightEmission = 0.3
	pe.LightInfluence = 0.7
	pe.Parent = parent
	return pe
end

--.. soft mist: slow, big, almost clear puffs
local function Mist(parent, scale, rate)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "FunMist"
	pe.Texture = TEX.Mist
	pe.Rate = rate
	pe.Lifetime = NumberRange.new(2.2, 3.2)
	pe.Speed = NumberRange.new(0.3 * scale, 0.7 * scale)
	pe.SpreadAngle = Vector2.new(70, 70)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Acceleration = Vector3.new(0, 0.2 * scale, 0)
	pe.Drag = 0.8
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-20, 20)
	pe.Size = NumberSequence.new({kp(0, 0.7 * scale), kp(1, 2.0 * scale)})
	pe.Transparency = NumberSequence.new({kp(0, 1), kp(0.25, 0.86), kp(1, 1)})
	pe.Color = ColorSequence.new(MIST_COLOR)
	pe.LightEmission = 0.15
	pe.LightInfluence = 0.8
	pe.Parent = parent
	return pe
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local scale = ctx.Scale
	local jetOrigin = AuthoredPivot(model, "JetOrigin")
	local jetTop = AuthoredPivot(model, "JetTop")
	local bowlTop = AuthoredPivot(model, "BowlWaterTop")
	local basinTop = AuthoredPivot(model, "BasinWaterTop")

	--.. every effect hangs off one invisible local part at the authored origin: attachment positions = authored * scale
	local anchor = ctx:Part({Name = "FunFountainFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = Kit.Origin(model)})

	--..Plume..--
	local rise = math.max(0.2, (jetTop.Y - jetOrigin.Y) * PLUME_OVERSHOOT)
	local fall = rise + math.max(0, jetOrigin.Y - bowlTop.Y)
	local plumeLife = math.sqrt(2 * rise / G) + math.sqrt(2 * fall / G)
	local plumeAt = Attach(anchor, "Plume", CFrame.new(Vector3.new(0, jetOrigin.Y, 0) * scale))
	Droplets(plumeAt, scale, {
		Name = "Plume", Rate = PLUME_RATE, Speed = math.sqrt(2 * G * rise) * scale, Spread = PLUME_SPREAD,
		Life = plumeLife, Direction = Enum.NormalId.Top,
	})

	--..Streams (bowl lip -> basin) + where they land..--
	local landings = {} -- authored points on the basin water
	for i, jet in ipairs(JETS) do
		local out, up, flight = JetLaunch(jet)
		local a = math.rad(jet.Angle)
		local radial = Vector3.new(math.cos(a), 0, -math.sin(a))
		local lip = (radial * jet.R0 + Vector3.new(0, jet.Z0, 0)) * scale
		local velocity = radial * out + Vector3.new(0, up, 0)
		local at = Attach(anchor, "Stream" .. i, CFrame.lookAt(lip, lip + velocity.Unit))
		Droplets(at, scale, {Name = "Stream", Rate = STREAM_RATE, Speed = velocity.Magnitude * scale, Spread = 2.5, Life = flight})
		table.insert(landings, radial * (jet.R0 + jet.DR - 0.08))
	end

	--..Splash rings, kicks, mist..--
	local basinY = basinTop.Y + RING_LIFT
	local bowlY = bowlTop.Y + RING_LIFT
	local basinAt = Attach(anchor, "BasinSplash", CFrame.new(Vector3.new(landings[1].X, basinY, landings[1].Z) * scale))
	local basinRing = Rings(basinAt, scale, 0.22, 1.15, 0.8, 0.3)
	local kick = Droplets(basinAt, scale, {Name = "Kick", Rate = 0, Speed = 2.4 * scale, Spread = 30, Life = 0.34, Direction = Enum.NormalId.Top, Size = 0.1})
	local puff = Mist(basinAt, scale, 0)
	local bowlAt = Attach(anchor, "BowlSplash", CFrame.new(Vector3.new(BOWL_RING_R[1], bowlY, 0) * scale))
	local bowlRing = Rings(bowlAt, scale, 0.14, 0.62, 0.6, 0.35)
	local mistAt = Attach(anchor, "Mist", CFrame.new(Vector3.new(0, bowlTop.Y + 0.35, 0) * scale))
	Mist(mistAt, scale, 1.2)

	--..Water sound (near only)..--
	local soundAt = Attach(anchor, "Sound", CFrame.new(Vector3.new(0, bowlTop.Y * 0.6, 0) * scale))
	local water
	if FunAssets.Sfx.WaterLoop then
		local ok, sound = pcall(function()
			return ctx:Sound(soundAt, FunAssets.Sfx.WaterLoop, {
				Name = "FunWater", Looped = true, Volume = SOUND_VOLUME, RollOffMinDistance = 6, RollOffMaxDistance = NEAR_SOUND,
			})
		end)
		if ok then water = sound end
	end
	if water then
		local function SyncSound()
			local d = ctx:CameraDistance()
			if d <= NEAR_SOUND and not water.IsPlaying then
				water:Play()
			elseif d > FAR_SOUND and water.IsPlaying then
				water:Stop()
			end
		end
		SyncSound()
		ctx:Every(0.5, SyncSound)
	end

	--..Every frame: splash timers (asleep far away with the rest of ctx:Step)..--
	local rng = Random.new()
	local basinClock, bowlClock, puffClock = 0, BOWL_RING_EVERY * 0.5, 0
	local jetIndex = 0
	ctx:Step(function(dt)
		basinClock += dt
		bowlClock += dt
		puffClock += dt
		if basinClock >= BASIN_RING_EVERY then
			basinClock = 0
			jetIndex = (jetIndex + rng:NextInteger(1, #landings - 1)) % #landings -- a different stream every time
			local p = landings[jetIndex + 1]
			local jx, jz = rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.08, 0.08)
			basinAt.Position = Vector3.new(p.X + jx, basinY, p.Z + jz) * scale
			basinRing:Emit(1)
			kick:Emit(1)
			if puffClock >= PUFF_EVERY then
				puffClock = 0
				puff:Emit(1)
			end
		end
		if bowlClock >= BOWL_RING_EVERY then
			bowlClock = 0
			local a = rng:NextNumber(0, 2 * math.pi)
			local r = rng:NextNumber(BOWL_RING_R[1], BOWL_RING_R[2])
			bowlAt.Position = Vector3.new(math.cos(a) * r, bowlY, math.sin(a) * r) * scale
			bowlRing:Emit(1)
		end
	end)

	--..Wading ripples: anyone moving through the basin water..--
	local lastRipple = {} -- [player] = os.clock()
	ctx:Every(0.3, function()
		if ctx:CameraDistance() > B.StepRange then return end
		local origin = Kit.Origin(model)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and now - (lastRipple[player] or 0) > 0.35 then
				local p = origin:PointToObjectSpace(root.Position) / scale
				local r = math.sqrt(p.X * p.X + p.Z * p.Z)
				local v = root.AssemblyLinearVelocity
				if r > WADE_R[1] and r < WADE_R[2] and p.Y > basinTop.Y and p.Y < basinTop.Y + 5 / scale
					and Vector3.new(v.X, 0, v.Z).Magnitude > WADE_SPEED then
					lastRipple[player] = now
					basinAt.Position = Vector3.new(p.X, basinY, p.Z) * scale
					basinRing:Emit(1)
				end
			end
		end
		for player in pairs(lastRipple) do
			if player.Parent == nil then lastRipple[player] = nil end
		end
	end)
end

return B
]======]
SOURCES['C_Pond'] = [======[
--[[
	Pond  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLights
	Client-only behaviour for the koi pond (no server half: nothing is shared but the clock, Kit.Now()).
	  * three KOI built from local parts (ellipsoid body + eyes + koi-pattern spots + pectoral paddles + dorsal fin
	    + a forked two-wedge tail that wags faster when the fish speeds up; 10 parts each, local only) swim lazy
	    loops just under Pivot_WaterSurface, one loop near each of the Fish1..3 pivots. The loops were fitted
	    offline to the real waterline (the 9-point shore of props/build_pond.py: 0.2+ authored studs of clearance
	    for nose and tail, loops kept apart); speed glides in and out, fish bank into their turns, and Fish1's tall
	    dorsal fin cuts the surface like the authored one did.
	    The static Fish1..3 / FishEyes / FishMarks meshes are hidden LOCALLY (LocalTransparencyModifier, so the
	    server's Transparency - and BuildHealthService's broken fade / mend - is never touched) and shown again on
	    cleanup. BuildMenuClient's move ghost writes LocalTransparencyModifier on every build part (0.85 while the
	    build is on the mouse, back to 0 when the move ends) and a cancelled / same-spot move doesn't restart this
	    behaviour, so the static koi are re-hidden whenever anything lowers it; the swimming koi copy the ghost
	    value from the Bank so they fade with the rest of the pond during a move.
	  * RIPPLES: flat expanding rings (built-in shockwave texture lying on the water) now and then in open water,
	    where a koi noses the surface, a small wake behind Fish1's fin, and under anyone walking on the pond
	  * the lily pads (+ their lotus flowers) BOB: LilyPads and LilyLotus are one merged mesh each, so the whole
	    set rises / falls / drifts a few hundredths together; restored on cleanup relative to the current hitbox
	The Water part stays COLLIDABLE: it is the pond's surface (a zero-thickness sheet 0.34 above the bed), the
	water is only ~0.45 studs deep in the world, and letting people sink to the bed would only put their feet
	through the koi and the lily pads - so people walk ON the pond and leave ripples instead.
	Authored frame here = the Roblox one: Blender (x, y, z) -> (x, z, -y).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local WATER_Y = 0.50             -- authored fallback for Pivot_WaterSurface
local HIDE = {"Fish1", "Fish2", "Fish3", "FishEyes", "FishMarks"} -- the static koi the swimming ones replace
local GHOST = {"Bank", "Water", "Bed"} -- a build part whose LocalTransparencyModifier (build-mode move ghost) the koi copy
local ORANGE = Color3.fromRGB(255, 138, 61)  -- accent_orange ff8a3d (the authored koi)
local WHITE = Color3.fromRGB(242, 239, 228)  -- flower_white f2efe4
local EYE = Color3.fromRGB(35, 38, 44)       -- plastic_black 23262c
local FIN_ORANGE = Color3.fromRGB(255, 172, 112)
local FIN_WHITE = Color3.fromRGB(250, 247, 238)
local FIN_ALPHA = 0.15
local TAIL_WAG = math.rad(22)    -- tail swing each side
local TAIL_ROOT = 0.46           -- body-local z of the tail root (x fish size)
local TAIL_W, TAIL_L = 0.22, 0.34 -- each tail half: width across, length back (x fish size)
local TAIL_FORK = math.rad(8)    -- each tail lobe splays outward this much (the forked koi tail)
local PECTORAL_SWEEP = math.rad(35) -- pectoral fins swept back
local BANK = 0.25                -- roll per rad/s of turning (clamped to BANK_MAX)
local BANK_MAX = 0.2
--.. the koi. Centre/RX/RZ/Rot: an ellipse in the authored XZ plane (fitted to the shoreline offline); Period s per
--.. loop, Dir +1/-1; Glide/GlidePeriod: a time warp so they speed up and glide (Glide * 2pi/GlidePeriod < 2pi/Period);
--.. Under: studs below the water surface; Size: the authored fish scale; Beats: tail beats per loop
local FISH = {
	{Name = "Fish1", Centre = Vector2.new(1.60, -0.20), RX = 1.30, RZ = 0.90, Rot = -20, Period = 13.0, Dir = 1,
		Glide = 0.35, GlidePeriod = 5.3, Phase = 0.0, Under = 0.15, Size = 1.00, Koi = "Orange", Sail = 0.145, Beats = 24, Wake = true},
	{Name = "Fish2", Centre = Vector2.new(-0.70, 0.90), RX = 0.62, RZ = 0.50, Rot = 35, Period = 11.0, Dir = -1,
		Glide = 0.30, GlidePeriod = 4.1, Phase = 2.1, Under = 0.17, Size = 0.94, Koi = "White", Sail = 0.09, Beats = 16},
	{Name = "Fish3", Centre = Vector2.new(-1.62, -0.95), RX = 0.60, RZ = 0.70, Rot = 25, Period = 9.5, Dir = 1,
		Glide = 0.30, GlidePeriod = 3.7, Phase = 4.0, Under = 0.16, Size = 0.84, Koi = "Orange", Sail = 0.09, Beats = 16},
}
--.. koi-pattern spots, body-local (x fish size): white saddles on the orange koi, red-orange patches on the white one
local SPOTS = {
	Orange = {
		{Pos = Vector3.new(0, 0.112, -0.16), Size = Vector3.new(0.16, 0.06, 0.26)},
		{Pos = Vector3.new(0, 0.114, 0.14), Size = Vector3.new(0.13, 0.05, 0.20)},
	},
	White = {
		{Pos = Vector3.new(0, 0.105, -0.24), Size = Vector3.new(0.20, 0.06, 0.30)},
		{Pos = Vector3.new(0.02, 0.112, 0.10), Size = Vector3.new(0.16, 0.055, 0.26)},
	},
}
--.. the open waterline (authored XZ, inner shore x 1.008 of build_pond.py's ring) and the lily pads (x, z, radius)
local SHORE = {
	Vector2.new(3.785, -0.488), Vector2.new(2.912, -2.326), Vector2.new(0.603, -1.860), Vector2.new(-1.016, -2.620),
	Vector2.new(-3.261, -1.660), Vector2.new(-2.534, 0.856), Vector2.new(-0.982, 2.055), Vector2.new(1.788, 2.361),
	Vector2.new(3.132, 0.556),
}
local PADS = {
	Vector3.new(-2.00, -1.20, 0.68), Vector3.new(-0.55, -1.76, 0.46), Vector3.new(2.25, -0.92, 0.52),
	Vector3.new(0.65, 1.53, 0.58), Vector3.new(-2.10, 0.45, 0.40),
}
--.. ripples
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds" -- engine built-in soft ring
local RING_COLOR = Color3.fromRGB(222, 242, 255)
local RING_LIFT = 0.025          -- authored studs above the water
local RANDOM_RIPPLE = {1.4, 3.2} -- s between open-water ripples
local KISS_RIPPLE = {3.0, 6.0}   -- s between "a koi noses the surface" ripples
local WAKE_EVERY = 0.7           -- s between Fish1 fin-wake rings
local SHORE_MARGIN = 0.45        -- authored studs a random ripple keeps from the waterline
local WALK_SPEED = 1.5           -- studs/s a character on the pond must move to leave ripples
--.. lily pad bob (authored studs / degrees)
local BOB_AMP, BOB_PERIOD = 0.03, 3.1
local BOB_TILT, BOB_YAW = 0.6, 1.5

local B = {}
B.StepRange = 150

--..Helpers..--
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

--.. a local-only part of any class (ctx:Part only makes Parts; the tail and fins are WedgeParts)
local function LocalPart(ctx, className, props)
	local p = Instance.new(className)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = workspace.CurrentCamera
	ctx:Add(p)
	return p
end

local function Ellipsoid(ctx, size, color, name)
	local p = LocalPart(ctx, "Part", {Name = name, Size = size, Color = color})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function InsideShore(x, z)
	local inside = false
	local n = #SHORE
	for i = 1, n do
		local a, b = SHORE[i], SHORE[i % n + 1]
		if (a.Y > z) ~= (b.Y > z) and x < (b.X - a.X) * (z - a.Y) / (b.Y - a.Y) + a.X then inside = not inside end
	end
	return inside
end

local function ShoreDistance(x, z)
	local best = math.huge
	local n = #SHORE
	for i = 1, n do
		local a, b = SHORE[i], SHORE[i % n + 1]
		local d = b - a
		local t = math.clamp(((x - a.X) * d.X + (z - a.Y) * d.Y) / d:Dot(d), 0, 1)
		best = math.min(best, (Vector2.new(x, z) - (a + d * t)).Magnitude)
	end
	return best
end

--.. a random open-water point (authored XZ) clear of the shore and the pads, or nil
local function RandomOpenWater(rng)
	for _ = 1, 12 do
		local x, z = rng:NextNumber(-3.2, 3.7), rng:NextNumber(-2.6, 2.3)
		if InsideShore(x, z) and ShoreDistance(x, z) > SHORE_MARGIN then
			local clear = true
			for _, pad in ipairs(PADS) do
				if (Vector2.new(x, z) - Vector2.new(pad.X, pad.Y)).Magnitude < pad.Z + 0.2 then clear = false break end
			end
			if clear then return x, z end
		end
	end
	return nil
end

--.. builds one koi: {Spec, K, Body = {{part, offset}}, Tail = {{part, offset from the tail root}}}
local function BuildKoi(ctx, spec, scale)
	local k = spec.Size * scale
	local main = spec.Koi == "White" and WHITE or ORANGE
	local accent = spec.Koi == "White" and ORANGE or WHITE
	local finColor = spec.Koi == "White" and FIN_WHITE or FIN_ORANGE
	local koi = {Spec = spec, K = k, Body = {}, Tail = {}}
	--.. body: an ellipsoid 0.37 x 0.25 x 1.04 (the authored koi's proportions), nose toward -Z
	table.insert(koi.Body, {Ellipsoid(ctx, Vector3.new(0.374, 0.254, 1.04) * k, main, "KoiBody"), CFrame.identity})
	for _, side in ipairs({-1, 1}) do
		local eye = LocalPart(ctx, "Part", {Name = "KoiEye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.09 * k, Color = EYE})
		table.insert(koi.Body, {eye, CFrame.new(side * 0.135 * k, 0.05 * k, -0.35 * k)})
		--.. pectoral fin: a flat paddle behind the head, swept back
		local pec = Ellipsoid(ctx, Vector3.new(0.22, 0.025, 0.12) * k, finColor, "KoiPectoral")
		pec.Transparency = FIN_ALPHA
		table.insert(koi.Body, {pec, CFrame.new(side * 0.2 * k, -0.035 * k, -0.15 * k) * CFrame.Angles(0, -side * PECTORAL_SWEEP, 0)})
	end
	for _, spot in ipairs(SPOTS[spec.Koi] or SPOTS.Orange) do
		table.insert(koi.Body, {Ellipsoid(ctx, spot.Size * k, accent, "KoiSpot"), CFrame.new(spot.Pos * k)})
	end
	--.. dorsal fin: a thin wedge, tall toward the back; Fish1's is tall enough to break the surface
	local fin = LocalPart(ctx, "WedgePart", {Name = "KoiFin", Size = Vector3.new(0.05, spec.Sail, 0.40) * k, Color = finColor, Transparency = FIN_ALPHA})
	table.insert(koi.Body, {fin, CFrame.new(0, (0.05 + spec.Sail * 0.5) * k, 0.02 * k)})
	--.. tail: two flat wedges fanning out behind the root (each wedge's triangle turned to lie in the XZ plane:
	--.. sharp end at the root, wide end back), each splayed TAIL_FORK outward so a notch opens between the lobes
	local half = Vector3.new(0.035, TAIL_W, TAIL_L) * k
	local right = LocalPart(ctx, "WedgePart", {Name = "KoiTail", Size = half, Color = finColor, Transparency = FIN_ALPHA})
	local left = LocalPart(ctx, "WedgePart", {Name = "KoiTail", Size = half, Color = finColor, Transparency = FIN_ALPHA})
	table.insert(koi.Tail, {right, CFrame.Angles(0, TAIL_FORK, 0) * CFrame.new(TAIL_W * 0.5 * k, 0, TAIL_L * 0.5 * k) * CFrame.Angles(0, 0, -math.pi / 2)})
	table.insert(koi.Tail, {left, CFrame.Angles(0, -TAIL_FORK, 0) * CFrame.new(-TAIL_W * 0.5 * k, 0, TAIL_L * 0.5 * k) * CFrame.Angles(0, 0, math.pi / 2)})
	return koi
end

--.. where a koi is at server time t: authored position, heading (authored XZ velocity), turn rate (rad/s), loop progress
local function KoiPose(spec, t, phase)
	local w, w2 = 2 * math.pi / spec.Period, 2 * math.pi / spec.GlidePeriod
	local progress = w * t + spec.Glide * math.sin(w2 * t)       -- always increasing (Glide * w2 < w)
	local rate = spec.Dir * (w + spec.Glide * w2 * math.cos(w2 * t)) -- ds/dt
	local s = spec.Dir * progress + spec.Phase + phase
	local a = math.rad(spec.Rot)
	local ca, sa = math.cos(a), math.sin(a)
	local ex, ez = spec.RX * math.cos(s), spec.RZ * math.sin(s)
	local dx, dz = -spec.RX * math.sin(s), spec.RZ * math.cos(s)  -- d/ds before rotation
	local x = spec.Centre.X + ex * ca - ez * sa
	local z = spec.Centre.Y + ex * sa + ez * ca
	local hx, hz = (dx * ca - dz * sa) * rate, (dx * sa + dz * ca) * rate
	local turn = rate * spec.RX * spec.RZ / math.max(1e-4, dx * dx + dz * dz) -- > 0 = turning to the fish's right
	return x, z, hx, hz, turn, progress
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local scale = ctx.Scale
	local surface = model:GetAttribute("Pivot_WaterSurface")
	local waterY = typeof(surface) == "Vector3" and surface.Y or WATER_Y
	local seedPhase = ((hitbox.Position.X * 0.61 + hitbox.Position.Z * 0.37) % 6.283)
	local rng = Random.new()

	--..Hide the static koi (locally)..--
	--.. BuildMenuClient sets LocalTransparencyModifier = 0.85 on every part of a build being moved and StopPlacing
	--.. puts it back to 0; a cancelled move (or a drop on the same spot) leaves the hitbox where it was, so nothing
	--.. restarts this behaviour - hide them again whenever anything lowers it. The ctx:Alive() guard matters:
	--.. FunBuildClient.Stop marks the ctx dead BEFORE running the cleanup below, which shows them again
	local hidden = {}
	for _, name in ipairs(HIDE) do
		local part = Kit.Part(model, name)
		if part then
			part.LocalTransparencyModifier = 1
			table.insert(hidden, part)
			ctx:Connect(part:GetPropertyChangedSignal("LocalTransparencyModifier"), function()
				if ctx:Alive() and part.Parent and part.LocalTransparencyModifier < 1 then part.LocalTransparencyModifier = 1 end
			end)
		end
	end

	--..Swimming koi..--
	local kois = {}
	for _, spec in ipairs(FISH) do table.insert(kois, BuildKoi(ctx, spec, scale)) end
	local moveParts, moveCFrames = {}, {}
	for _, koi in ipairs(kois) do
		for _, item in ipairs(koi.Body) do table.insert(moveParts, item[1]) end
		for _, item in ipairs(koi.Tail) do table.insert(moveParts, item[1]) end
	end

	--.. the swimming koi are local parts BuildMenuClient never sees: copy its move ghost from a build part so they
	--.. fade with the rest of the pond while it is on the mouse (and come back when the move ends)
	local ghost
	for _, name in ipairs(GHOST) do
		ghost = Kit.Part(model, name)
		if ghost then break end
	end
	if ghost then
		local function FollowGhost()
			if not ctx:Alive() then return end
			local g = ghost.LocalTransparencyModifier
			for _, part in ipairs(moveParts) do part.LocalTransparencyModifier = g end
		end
		ctx:Connect(ghost:GetPropertyChangedSignal("LocalTransparencyModifier"), FollowGhost)
		FollowGhost()
	end

	--..Lily pad bob rig..--
	local pads = Kit.Part(model, "LilyPads")
	local bobRig, bobRel
	if pads then
		local bobParts = {pads}
		local lotus = Kit.Part(model, "LilyLotus")
		if lotus then table.insert(bobParts, lotus) end
		local bobPivot = CFrame.new(pads.Position) * Kit.Origin(model).Rotation
		bobRel = hitbox.CFrame:ToObjectSpace(bobPivot)
		bobRig = Kit.Rig(bobParts, bobPivot)
	end

	--..Ripples: one movable attachment on a local anchor at the authored origin..--
	local anchor = ctx:Part({Name = "FunPondFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = Kit.Origin(model)})
	local rippleAt = Instance.new("Attachment")
	rippleAt.Name = "Ripple"
	rippleAt.Position = Vector3.new(0, waterY + RING_LIFT, 0) * scale
	rippleAt.Parent = anchor
	local function RingEmitter(size0, size1, life, alpha)
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "FunRipple"
		pe.Texture = TEX_RING
		pe.Rate = 0
		pe.Lifetime = NumberRange.new(life * 0.9, life * 1.1)
		pe.Speed = NumberRange.new(0.02)
		pe.SpreadAngle = Vector2.zero
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular -- lies flat on the water
		pe.Rotation = NumberRange.new(0, 360)
		pe.Size = NumberSequence.new({kp(0, size0 * scale), kp(1, size1 * scale)})
		pe.Transparency = NumberSequence.new({kp(0, alpha), kp(0.6, (1 + alpha) * 0.5 + 0.1), kp(1, 1)})
		pe.Color = ColorSequence.new(RING_COLOR)
		pe.LightEmission = 0.2
		pe.LightInfluence = 0.8
		pe.Parent = rippleAt
		return pe
	end
	local ripple = RingEmitter(0.25, 1.7, 1.5, 0.35)
	local wake = RingEmitter(0.12, 0.55, 0.8, 0.45)
	local function RippleAt(emitter, x, z, count)
		rippleAt.Position = Vector3.new(x, waterY + RING_LIFT, z) * scale
		emitter:Emit(count or 1)
	end

	--..Every frame: koi, pads, ripple timers..--
	local lastPose = {} -- [koi] = {x, z, hx, hz} (authored), for kisses / wakes
	for _, koi in ipairs(kois) do lastPose[koi] = {0, 0, 0, 0} end
	local nextRandom = Kit.Now() + rng:NextNumber(RANDOM_RIPPLE[1], RANDOM_RIPPLE[2])
	local nextKiss = Kit.Now() + rng:NextNumber(KISS_RIPPLE[1], KISS_RIPPLE[2])
	local nextWake = Kit.Now() + WAKE_EVERY
	ctx:Step(function(_, now)
		local origin = Kit.Origin(model)
		local n = 0
		for _, koi in ipairs(kois) do
			local spec, k = koi.Spec, koi.K
			local x, z, hx, hz, turn, progress = KoiPose(spec, now, seedPhase)
			local beat = math.sin(spec.Beats * progress)
			local wag = TAIL_WAG * beat
			local sway = 0.1 * math.sin(spec.Beats * progress - 1.2)          -- the head counter-swings the tail
			local roll = -math.clamp(turn * BANK, -BANK_MAX, BANK_MAX)
			local y = waterY - spec.Under + 0.012 * math.sin(now * 1.3 + spec.Phase * 3)
			local yaw = math.atan2(-hx, -hz)
			local fishCF = origin * CFrame.new(Vector3.new(x, y, z) * scale) * CFrame.Angles(0, yaw + sway, 0) * CFrame.Angles(0, 0, roll)
			for _, item in ipairs(koi.Body) do
				n += 1
				moveCFrames[n] = fishCF * item[2]
			end
			local tailCF = fishCF * CFrame.new(0, 0, TAIL_ROOT * k) * CFrame.Angles(0, wag, 0)
			for _, item in ipairs(koi.Tail) do
				n += 1
				moveCFrames[n] = tailCF * item[2]
			end
			local pose = lastPose[koi]
			pose[1], pose[2], pose[3], pose[4] = x, z, hx, hz
		end
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)

		if bobRig then
			local lift = BOB_AMP * scale * math.sin(now * 2 * math.pi / BOB_PERIOD)
			local tiltX = math.rad(BOB_TILT) * math.sin(now * 2 * math.pi / 3.7 + 0.5)
			local tiltZ = math.rad(BOB_TILT) * math.sin(now * 2 * math.pi / 4.9 + 2.0)
			local yaw = math.rad(BOB_YAW) * math.sin(now * 2 * math.pi / 7.3 + 1.0)
			Kit.PoseRig(bobRig, hitbox.CFrame * bobRel * CFrame.new(0, lift, 0) * CFrame.Angles(tiltX, yaw, tiltZ))
		end

		if now >= nextRandom then
			nextRandom = now + rng:NextNumber(RANDOM_RIPPLE[1], RANDOM_RIPPLE[2])
			local x, z = RandomOpenWater(rng)
			if x then RippleAt(ripple, x, z) end
		end
		if now >= nextKiss then
			nextKiss = now + rng:NextNumber(KISS_RIPPLE[1], KISS_RIPPLE[2])
			local pose = lastPose[kois[rng:NextInteger(1, #kois)]]
			if pose and (pose[3] ~= 0 or pose[4] ~= 0) then
				local speed = math.max(1e-4, math.sqrt(pose[3] * pose[3] + pose[4] * pose[4]))
				local nose = 0.4 -- authored studs ahead of the body centre
				RippleAt(ripple, pose[1] + pose[3] / speed * nose, pose[2] + pose[4] / speed * nose)
			end
		end
		if now >= nextWake then
			nextWake = now + WAKE_EVERY
			for _, koi in ipairs(kois) do
				local pose = lastPose[koi]
				if koi.Spec.Wake and (pose[3] ~= 0 or pose[4] ~= 0) then RippleAt(wake, pose[1], pose[2]) end
			end
		end
	end)

	--..Ripples under anyone walking on the pond..--
	local lastRipple = {} -- [player] = os.clock()
	ctx:Every(0.3, function()
		if ctx:CameraDistance() > B.StepRange then return end
		local origin = Kit.Origin(model)
		local clock = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and clock - (lastRipple[player] or 0) > 0.35 then
				local p = origin:PointToObjectSpace(root.Position) / scale
				local v = root.AssemblyLinearVelocity
				if p.Y > waterY - 0.2 and p.Y < waterY + 5 / scale and InsideShore(p.X, p.Z)
					and Vector3.new(v.X, 0, v.Z).Magnitude > WALK_SPEED then
					lastRipple[player] = clock
					RippleAt(ripple, p.X, p.Z)
				end
			end
		end
		for player in pairs(lastRipple) do
			if player.Parent == nil then lastRipple[player] = nil end
		end
	end)

	--..Cleanup: the static koi back, the pads at rest where the build is now..--
	return function()
		for _, part in ipairs(hidden) do
			if part.Parent then part.LocalTransparencyModifier = 0 end
		end
		if bobRig and hitbox.Parent then Kit.PoseRig(bobRig, hitbox.CFrame * bobRel) end
	end
end

return B
]======]
SOURCES['S_Fountain'] = [======[
--[[
	Fountain  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package GardenLights
	Server half of the RUNNING FOUNTAIN (client half: ReplicatedStorage.FunBehavioursClient.Fountain draws the
	jets, splash rings, mist and sound). The prop's author asked for the see-through water to be walk-through:
	"make them non-collidable in Roblox and let players walk into the basin" - so while the behaviour runs, the
	WaterSurface (basin + bowl sheets), WaterBed, Jets and Foam parts are CanCollide = false. People then wade in
	to the basin floor (the BasinWall mesh's raised floor, 0.40 authored) and the client draws ripples round them.
	Done on the server so every client, the zombies and the server's own physics agree.
	Cleanup restores each part's ORIGINAL CanCollide, remembered in a part attribute the first time this ever
	runs (so re-runs after a move / mend never mistake our own false for the original) - except while the build
	is Broken: BuildHealthService owns collisions then, and on mend it restores what it recorded before we re-run.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local WALK_THROUGH = {"WaterSurface", "WaterBed", "Jets", "Foam"}
local ORIGINAL_ATTR = "FunCollideOriginal"

local B = {}

--..Behaviour..--
function B.Server(model, ctx)
	local touched = {}
	for _, name in ipairs(WALK_THROUGH) do
		local part = Kit.Part(model, name)
		if part then
			if type(part:GetAttribute(ORIGINAL_ATTR)) ~= "boolean" then part:SetAttribute(ORIGINAL_ATTR, part.CanCollide) end
			part.CanCollide = false
			table.insert(touched, part)
		end
	end

	return function()
		if Kit.IsBroken(model) then return end -- BuildHealthService faded + de-collided everything; it restores on mend
		for _, part in ipairs(touched) do
			local original = part:GetAttribute(ORIGINAL_ATTR)
			if part.Parent and type(original) == "boolean" then part.CanCollide = original end
		end
	end
end

return B
]======]
DUMPS = {}
DUMPS['Lantern'] = {Attrs = {Pivot_A_Light = Vector3.new(-5.20, 3.46, -0.00), Pivot_B_Hang = Vector3.new(-0.30, 3.34, -0.00), Pivot_B_Light = Vector3.new(-0.30, 2.42, -0.00), Pivot_C_Light = Vector3.new(4.60, 0.64, -0.00)}, Parts = {
	{Name = 'A_Base', Pos = Vector3.new(-5.20, 0.20, 0.00), Size = Vector3.new(1.44, 0.40, 1.44), T = 0.00, Collide = true},
	{Name = 'A_Cap', Pos = Vector3.new(-5.20, 4.34, -0.00), Size = Vector3.new(1.00, 0.56, 1.00), T = 0.00, Collide = true},
	{Name = 'A_Flame', Pos = Vector3.new(-5.20, 3.31, -0.00), Size = Vector3.new(0.32, 0.40, 0.32), T = 0.00, Collide = true},
	{Name = 'A_FlameTip', Pos = Vector3.new(-5.20, 3.57, -0.00), Size = Vector3.new(0.22, 0.33, 0.19), T = 0.00, Collide = true},
	{Name = 'A_Glass', Pos = Vector3.new(-5.20, 3.45, -0.00), Size = Vector3.new(0.67, 0.78, 0.67), T = 0.58, Collide = true},
	{Name = 'A_Iron', Pos = Vector3.new(-5.33, 2.24, 0.00), Size = Vector3.new(0.99, 3.72, 0.72), T = 0.00, Collide = true},
	{Name = 'B_Base', Pos = Vector3.new(0.42, 0.10, -0.00), Size = Vector3.new(0.88, 0.20, 0.88), T = 0.00, Collide = true},
	{Name = 'B_Brass', Pos = Vector3.new(-0.30, 2.43, -0.00), Size = Vector3.new(0.54, 1.50, 0.54), T = 0.00, Collide = true},
	{Name = 'B_Core', Pos = Vector3.new(-0.30, 2.32, -0.00), Size = Vector3.new(0.42, 0.44, 0.42), T = 0.00, Collide = true},
	{Name = 'B_CoreTip', Pos = Vector3.new(-0.30, 2.61, -0.00), Size = Vector3.new(0.27, 0.38, 0.23), T = 0.00, Collide = true},
	{Name = 'B_Iron', Pos = Vector3.new(0.10, 1.88, -0.00), Size = Vector3.new(0.90, 3.51, 0.30), T = 0.00, Collide = true},
	{Name = 'B_Paper', Pos = Vector3.new(-0.30, 2.42, -0.00), Size = Vector3.new(1.00, 1.28, 1.00), T = 0.25, Collide = true},
	{Name = 'B_Tassel', Pos = Vector3.new(-0.30, 1.56, -0.00), Size = Vector3.new(0.18, 0.36, 0.16), T = 0.00, Collide = true},
	{Name = 'C_Base', Pos = Vector3.new(4.60, 0.16, -0.00), Size = Vector3.new(1.04, 0.32, 0.90), T = 0.00, Collide = true},
	{Name = 'C_Cap', Pos = Vector3.new(4.60, 1.11, -0.00), Size = Vector3.new(1.00, 0.42, 0.87), T = 0.00, Collide = true},
	{Name = 'C_Flame', Pos = Vector3.new(4.60, 0.60, -0.00), Size = Vector3.new(0.25, 0.24, 0.25), T = 0.00, Collide = true},
	{Name = 'C_FlameTip', Pos = Vector3.new(4.60, 0.75, -0.00), Size = Vector3.new(0.16, 0.17, 0.14), T = 0.00, Collide = true},
	{Name = 'C_Glass', Pos = Vector3.new(4.60, 0.64, -0.00), Size = Vector3.new(0.62, 0.44, 0.54), T = 0.58, Collide = true},
	{Name = 'C_Iron', Pos = Vector3.new(4.60, 0.62, -0.00), Size = Vector3.new(0.76, 0.64, 0.66), T = 0.00, Collide = true},
}}
DUMPS['TikiTorch'] = {Attrs = {Pivot_A_FlameAnchor = Vector3.new(5.00, 4.18, -0.00), Pivot_B_FlameAnchor = Vector3.new(0.00, 4.60, -0.00), Pivot_C_FlameAnchor = Vector3.new(-5.00, 0.90, -0.00)}, Parts = {
	{Name = 'A_Bowl', Pos = Vector3.new(5.00, 3.87, -0.00), Size = Vector3.new(1.06, 0.54, 1.06), T = 0.00, Collide = true},
	{Name = 'A_FlameCore', Pos = Vector3.new(5.00, 4.29, -0.00), Size = Vector3.new(0.24, 0.47, 0.23), T = 0.00, Collide = true},
	{Name = 'A_FlameMid', Pos = Vector3.new(5.00, 4.46, -0.00), Size = Vector3.new(0.40, 0.85, 0.34), T = 0.00, Collide = true},
	{Name = 'A_FlameTip', Pos = Vector3.new(5.00, 4.63, -0.00), Size = Vector3.new(0.50, 1.22, 0.36), T = 0.00, Collide = true},
	{Name = 'A_Lashing', Pos = Vector3.new(5.01, 2.09, -0.05), Size = Vector3.new(0.62, 2.46, 0.70), T = 0.00, Collide = true},
	{Name = 'A_Pole', Pos = Vector3.new(5.00, 1.85, -0.00), Size = Vector3.new(0.52, 3.70, 0.52), T = 0.00, Collide = true},
	{Name = 'B_Bowl', Pos = Vector3.new(-0.00, 4.36, -0.00), Size = Vector3.new(1.08, 0.32, 1.08), T = 0.00, Collide = true},
	{Name = 'B_Brow', Pos = Vector3.new(-0.00, 3.71, -0.59), Size = Vector3.new(1.40, 0.46, 0.38), T = 0.00, Collide = true},
	{Name = 'B_FlameCore', Pos = Vector3.new(-0.00, 4.67, -0.00), Size = Vector3.new(0.19, 0.39, 0.17), T = 0.00, Collide = true},
	{Name = 'B_FlameMid', Pos = Vector3.new(-0.00, 4.81, -0.00), Size = Vector3.new(0.40, 0.71, 0.39), T = 0.00, Collide = true},
	{Name = 'B_FlameTip', Pos = Vector3.new(-0.00, 4.95, -0.00), Size = Vector3.new(0.57, 1.02, 0.50), T = 0.00, Collide = true},
	{Name = 'B_Head', Pos = Vector3.new(-0.00, 2.76, -0.07), Size = Vector3.new(1.52, 3.01, 1.38), T = 0.00, Collide = true},
	{Name = 'B_Post', Pos = Vector3.new(-0.00, 2.11, -0.06), Size = Vector3.new(1.60, 4.22, 1.44), T = 0.00, Collide = true},
	{Name = 'B_TeethEyes', Pos = Vector3.new(-0.00, 2.94, -0.54), Size = Vector3.new(1.00, 0.73, 0.32), T = 0.00, Collide = true},
	{Name = 'C_Bowl', Pos = Vector3.new(-5.00, 0.58, 0.00), Size = Vector3.new(1.84, 0.64, 1.84), T = 0.00, Collide = true},
	{Name = 'C_Coals', Pos = Vector3.new(-5.00, 0.82, 0.00), Size = Vector3.new(1.18, 0.40, 1.21), T = 0.00, Collide = true},
	{Name = 'C_FlameCore', Pos = Vector3.new(-5.00, 0.94, 0.00), Size = Vector3.new(0.22, 0.35, 0.21), T = 0.00, Collide = true},
	{Name = 'C_FlameMid', Pos = Vector3.new(-5.00, 1.06, 0.00), Size = Vector3.new(0.29, 0.63, 0.22), T = 0.00, Collide = true},
	{Name = 'C_FlameTip', Pos = Vector3.new(-5.00, 1.19, 0.00), Size = Vector3.new(0.49, 0.90, 0.40), T = 0.00, Collide = true},
	{Name = 'C_Legs', Pos = Vector3.new(-5.00, 0.28, 0.13), Size = Vector3.new(1.35, 0.57, 1.26), T = 0.00, Collide = true},
}}
DUMPS['Fountain'] = {Attrs = {Pivot_BasinWaterTop = Vector3.new(0.00, 0.72, -0.00), Pivot_BowlWaterTop = Vector3.new(0.00, 2.50, -0.00), Pivot_JetOrigin = Vector3.new(0.00, 3.62, -0.00), Pivot_JetTop = Vector3.new(0.00, 4.20, -0.00)}, Parts = {
	{Name = 'BasinWall', Pos = Vector3.new(0.00, 0.47, 0.00), Size = Vector3.new(6.37, 0.66, 6.37), T = 0.00, Collide = true},
	{Name = 'BowlAndFinial', Pos = Vector3.new(-0.00, 2.88, -0.00), Size = Vector3.new(3.01, 1.76, 3.16), T = 0.00, Collide = true},
	{Name = 'Coping', Pos = Vector3.new(-0.00, 0.69, -0.01), Size = Vector3.new(6.68, 0.73, 6.69), T = 0.00, Collide = true},
	{Name = 'DarkStonework', Pos = Vector3.new(0.00, 1.81, 0.00), Size = Vector3.new(6.87, 3.62, 6.87), T = 0.00, Collide = true},
	{Name = 'Foam', Pos = Vector3.new(0.01, 1.62, 0.21), Size = Vector3.new(4.86, 1.82, 4.63), T = 0.00, Collide = true},
	{Name = 'Jets', Pos = Vector3.new(0.01, 2.46, 0.12), Size = Vector3.new(4.74, 3.48, 4.31), T = 0.35, Collide = true},
	{Name = 'Moss', Pos = Vector3.new(-0.97, 0.59, -2.45), Size = Vector3.new(4.75, 1.04, 2.44), T = 0.00, Collide = true},
	{Name = 'Pedestal', Pos = Vector3.new(-0.00, 1.28, -0.00), Size = Vector3.new(1.94, 1.88, 1.94), T = 0.00, Collide = true},
	{Name = 'WaterBed', Pos = Vector3.new(0.00, 0.56, 0.00), Size = Vector3.new(4.99, 0.29, 4.99), T = 0.12, Collide = true},
	{Name = 'WaterSurface', Pos = Vector3.new(0.00, 1.61, 0.00), Size = Vector3.new(5.15, 1.78, 5.15), T = 0.42, Collide = true},
}}
DUMPS['Pond'] = {Attrs = {Pivot_Fish1 = Vector3.new(1.42, 0.34, -0.16), Pivot_Fish2 = Vector3.new(-1.04, 0.34, 1.14), Pivot_Fish3 = Vector3.new(-2.12, 0.34, -0.16), Pivot_WaterSurface = Vector3.new(0.00, 0.50, -0.00)}, Parts = {
	{Name = 'Bank', Pos = Vector3.new(0.00, 0.44, 0.00), Size = Vector3.new(9.23, 0.89, 6.55), T = 0.00, Collide = true},
	{Name = 'Bed', Pos = Vector3.new(0.27, 0.13, -0.13), Size = Vector3.new(7.13, 0.06, 5.04), T = 0.00, Collide = true},
	{Name = 'CattailHeads', Pos = Vector3.new(-3.05, 1.55, -0.31), Size = Vector3.new(1.47, 0.93, 3.12), T = 0.00, Collide = true},
	{Name = 'Fish1', Pos = Vector3.new(1.32, 0.35, -0.01), Size = Vector3.new(0.78, 0.36, 1.09), T = 0.00, Collide = true},
	{Name = 'Fish2', Pos = Vector3.new(-0.96, 0.36, 0.99), Size = Vector3.new(0.63, 0.28, 1.07), T = 0.00, Collide = true},
	{Name = 'Fish3', Pos = Vector3.new(-1.98, 0.33, -0.11), Size = Vector3.new(1.00, 0.25, 0.49), T = 0.00, Collide = true},
	{Name = 'FishEyes', Pos = Vector3.new(-0.34, 0.39, 0.48), Size = Vector3.new(4.26, 0.17, 2.11), T = 0.00, Collide = true},
	{Name = 'FishMarks', Pos = Vector3.new(-0.37, 0.44, -0.17), Size = Vector3.new(3.92, 0.07, 0.42), T = 0.00, Collide = true},
	{Name = 'LilyLotus', Pos = Vector3.new(-0.45, 0.64, 0.22), Size = Vector3.new(3.80, 0.24, 3.77), T = 0.00, Collide = true},
	{Name = 'LilyPads', Pos = Vector3.new(0.05, 0.54, -0.05), Size = Vector3.new(5.40, 0.09, 4.30), T = 0.00, Collide = true},
	{Name = 'Reeds', Pos = Vector3.new(-3.04, 1.51, -0.30), Size = Vector3.new(1.44, 1.57, 3.11), T = 0.00, Collide = true},
	{Name = 'RimGrass', Pos = Vector3.new(-0.00, 1.04, -0.00), Size = Vector3.new(9.03, 0.81, 6.41), T = 0.00, Collide = true},
	{Name = 'RocksDark', Pos = Vector3.new(0.83, 0.97, -0.39), Size = Vector3.new(6.02, 0.71, 4.90), T = 0.00, Collide = true},
	{Name = 'RocksMid', Pos = Vector3.new(0.78, 0.97, -0.11), Size = Vector3.new(7.25, 0.91, 5.39), T = 0.00, Collide = true},
	{Name = 'Water', Pos = Vector3.new(0.26, 0.50, -0.13), Size = Vector3.new(7.05, 0.00, 4.98), T = 0.50, Collide = true},
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

------------------------------------------------------------------ template + placement (BuildService.MakeTemplate)
local function MakePlaced(dumpName, key, letter, scale, placeCF)
	local data = DUMPS[dumpName]
	local model = Instance.new("Model")
	model.Name = key
	local parts = {}
	local mn, mx
	for _, pd in ipairs(data.Parts) do
		if not letter or pd.Name:sub(1, 2) == letter .. "_" then
			local p = Instance.new("MeshPart")
			p.Name = pd.Name
			p.Size = pd.Size
			p.CFrame = CFrame.new(pd.Pos)
			p.Transparency = pd.T
			p.CanCollide = pd.Collide
			p.Anchored = true
			p.Parent = model
			table.insert(parts, p)
			local lo, hi = pd.Pos - pd.Size / 2, pd.Pos + pd.Size / 2
			mn = mn and Vector3.new(math.min(mn.X, lo.X), math.min(mn.Y, lo.Y), math.min(mn.Z, lo.Z)) or lo
			mx = mx and Vector3.new(math.max(mx.X, hi.X), math.max(mx.Y, hi.Y), math.max(mx.Z, hi.Z)) or hi
		end
	end
	local centre = (mn + mx) / 2
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = (mx - mn) * scale
	hitbox.CFrame = CFrame.new(centre)
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	for _, p in ipairs(parts) do
		p.Size = p.Size * scale
		p.CFrame = CFrame.new(centre + (p.CFrame.Position - centre) * scale)
	end
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

------------------------------------------------------------------ client ctx (FunBuildClient.NewContext)
local function MakeCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		_alive = true, _conns = {}, _insts = {}, _cleanups = {}, _steps = {}, _everys = {}, StepRange = 180}
	function ctx:Alive() return self._alive and model.Parent ~= nil end
	function ctx:Connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(self._conns, c)
		return c
	end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn) fn(self:State(k)) end
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
local function Frames(ctx, n, dt)
	dt = dt or 1 / 60
	check(#ctx._steps <= 1, "at most one ctx:Step per build")
	for _ = 1, n do
		MockNow += dt
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
local function Stop(ctx) -- FunBuildClient.Stop order: dead first, then cleanups, then disconnect + destroy
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		check(ok, "cleanup errored: " .. tostring(err))
	end
	for _, c in ipairs(ctx._conns) do c:Disconnect() end
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
local function SetCamera(model, dist) rawget(workspace.CurrentCamera, "_p").CFrame = CFrame.new(Kit.Hitbox(model).Position + Vector3.new(0, 0, dist)) end
local function Authored(model, world) return Kit.Origin(model):PointToObjectSpace(world) / Kit.Scale(model) end
local camera = workspace.CurrentCamera
local YAW = CFrame.Angles(0, math.rad(37), 0)

------------------------------------------------------------------ Lantern
do
	local mod = load("C_Lantern")
	for _, spec in ipairs({{"A", 2.1}, {"B", 1.7}, {"C", 1.5}}) do
		local letter, scale = spec[1], spec[2]
		workspace:SetAttribute("CyclePhase", "Day")
		local model = MakePlaced("Lantern", "Lantern_" .. letter, letter, scale, CFrame.new(120, 6, -40) * YAW)
		SetCamera(model, 25)
		local before = {}
		for _, p in ipairs(Kit.Parts(model, "")) do before[p] = p.CFrame end
		local ctx = Run(mod, model)
		local att = Find(model, "Attachment", "FunLanternLight")
		check(att ~= nil, letter .. " light attachment on a build part")
		if att then
			check(vnear(att.WorldPosition, Kit.Pivot(model, letter .. "_Light"), 1e-5), letter .. " light at Pivot_" .. letter .. "_Light")
			local light = Find(att, "PointLight")
			check(light ~= nil and light.Shadows == false, letter .. " PointLight")
			Frames(ctx, 120)
			local dayB = light.Brightness
			workspace:SetAttribute("CyclePhase", "Night")
			Frames(ctx, 240)
			check(light.Brightness > dayB * 1.4, letter .. (" night brighter (%.2f -> %.2f)"):format(dayB, light.Brightness))
			check(light.Range > 0 and light.Range <= 60, letter .. " range sane " .. light.Range)
			print(("Lantern_%s host %s  day %.2f night %.2f range %.1f"):format(letter, att.Parent.Name, dayB, light.Brightness, light.Range))
			local ff = Find(camera, "ParticleEmitter", "Fireflies")
			if letter == "A" then check(ff ~= nil and ff.Enabled == true, "A fireflies on at night") else check(ff == nil, letter .. " no fireflies") end
			workspace:SetAttribute("CyclePhase", "Day")
			rawget(MockLighting, "_p").ClockTime = 20
			Frames(ctx, 240)
			check(light.Brightness > dayB * 1.4, letter .. " ClockTime 20 counts as night")
			rawget(MockLighting, "_p").ClockTime = 14
			Frames(ctx, 300)
			if ff then check(ff.Enabled == false, "A fireflies off by day") end
		end
		if letter == "B" then
			local paper = Kit.Part(model, "B_Paper")
			local hang = Kit.Pivot(model, "B_Hang")
			local r0 = (before[paper].Position - hang).Magnitude
			local maxAngle = 0
			for _ = 1, 60 do
				Frames(ctx, 5)
				local r = (paper.Position - hang).Magnitude
				check(near(r, r0, 1e-4), "B paper keeps its distance to the hang point")
				local a = math.deg(math.acos(math.clamp((paper.Position - hang).Unit:Dot((before[paper].Position - hang).Unit), -1, 1)))
				maxAngle = math.max(maxAngle, a)
			end
			check(maxAngle > 2 and maxAngle < 4.4, ("B sway amplitude %.2f deg"):format(maxAngle))
			check(vnear(att.WorldPosition, paper.CFrame * att.Position, 1e-6), "B light rides on B_Paper")
			check(Kit.Part(model, "B_Iron").CFrame.Position == before[Kit.Part(model, "B_Iron")].Position, "B hook static")
			print(("Lantern_B max sway %.2f deg"):format(maxAngle))
		end
		Stop(ctx)
		for p, c in pairs(before) do
			check(vnear(p.CFrame.Position, c.Position, 1e-5) and vnear(p.CFrame.LookVector, c.LookVector, 1e-5), letter .. " part restored " .. p.Name)
		end
		check(Find(model, "Attachment", "FunLanternLight") == nil, letter .. " attachment removed on cleanup")
		model:Destroy()
	end
end

------------------------------------------------------------------ TikiTorch
do
	local mod = load("C_TikiTorch")
	for _, spec in ipairs({{"A", 1.5}, {"B", 1.5}, {"C", 1.4}}) do
		local letter, scale = spec[1], spec[2]
		local model = MakePlaced("TikiTorch", "TikiTorch_" .. letter, letter, scale, CFrame.new(-60, 4, 22) * YAW)
		SetCamera(model, 20)
		local ctx = Run(mod, model)
		local anchor = Find(camera, "Part", "FunTorchFlame")
		check(anchor ~= nil, letter .. " anchor")
		if anchor then
			check(vnear(anchor.Position, Kit.Pivot(model, letter .. "_FlameAnchor"), 1e-5), letter .. " anchor at the FlameAnchor pivot")
			local fire = Find(anchor, "Fire")
			check(fire and fire.Size >= 2 and fire.Size <= 30, letter .. " fire size")
			local sound = Find(anchor, "Sound")
			check(sound ~= nil, letter .. " crackle sound")
			Everys(ctx)
			check(sound and sound.IsPlaying, letter .. " crackle plays near")
			SetCamera(model, 60)
			Everys(ctx)
			check(sound and not sound.IsPlaying, letter .. " crackle stops far")
			Frames(ctx, 200)
			local light = Find(anchor, "PointLight")
			print(("TikiTorch_%s fire %.2f heat %d light %.2f range %.1f"):format(letter, fire.Size, fire.Heat, light.Brightness, light.Range))
		end
		Stop(ctx)
		check(Find(camera, "Part", "FunTorchFlame") == nil, letter .. " anchor removed")
		model:Destroy()
	end
end

------------------------------------------------------------------ Fountain (client + server)
do
	local G = 26
	local scale = 1.5
	local model = MakePlaced("Fountain", "Fountain", nil, scale, CFrame.new(10, 7, 80) * YAW)
	SetCamera(model, 30)
	local ctx = Run(load("C_Fountain"), model)
	local anchor = Find(camera, "Part", "FunFountainFX")
	check(anchor ~= nil, "fountain anchor")
	-- simulate one mean particle of every stream: where does it land?
	for _, att in ipairs(FindAll(anchor, "Attachment")) do
		if att.Name:match("^Stream") then
			local pe = Find(att, "ParticleEmitter")
			local wcf = att.WorldCFrame
			local v = wcf.LookVector * ((pe.Speed.Min + pe.Speed.Max) / 2)
			local life = pe.Lifetime.Max
			local p = wcf.Position + v * life + Vector3.new(0, -G * scale, 0) * (0.5 * life * life)
			local a = Authored(model, p)
			print(("%s lands at r %.2f y %.2f (life %.3f)"):format(att.Name, math.sqrt(a.X * a.X + a.Z * a.Z), a.Y, life))
			check(near(a.Y, 0.74, 0.03), att.Name .. " lands on the basin water")
			check(pe.Rate <= 30, "rate")
		end
	end
	local plume = Find(anchor, "Attachment", "Plume")
	do
		local pe = Find(plume, "ParticleEmitter")
		local v0 = (pe.Speed.Min + pe.Speed.Max) / 2
		local peak = Authored(model, plume.WorldPosition + Vector3.new(0, v0 * v0 / (2 * G * scale), 0))
		local life = pe.Lifetime.Max
		local endY = Authored(model, plume.WorldPosition + Vector3.new(0, v0 * life - 0.5 * G * scale * life * life, 0)).Y
		print(("plume peak y %.2f (JetTop 4.20), falls to y %.2f (bowl 2.50), life %.3f"):format(peak.Y, endY, life))
		check(peak.Y > 4.15 and peak.Y < 4.4, "plume peak ~ JetTop")
		check(near(endY, 2.5, 0.05), "plume falls back to the bowl water")
	end
	Frames(ctx, 600)
	local emitted = {}
	for _, pe in ipairs(FindAll(anchor, "ParticleEmitter")) do emitted[pe.Name] = (emitted[pe.Name] or 0) + (rawget(pe, "_emitted") or 0) end
	print("fountain Emit() counts over 10 s:", emitted.FunRings, emitted.Kick, emitted.FunMist)
	check((emitted.FunRings or 0) > 30, "splash rings emitted")
	local basin = Find(anchor, "Attachment", "BasinSplash")
	local a = Authored(model, basin.WorldPosition)
	check(near(a.Y, 0.75, 0.01), "basin rings sit on the basin water " .. a.Y)
	local bowl = Find(anchor, "Attachment", "BowlSplash")
	local b = Authored(model, bowl.WorldPosition)
	check(near(b.Y, 2.53, 0.01) and math.sqrt(b.X * b.X + b.Z * b.Z) <= 0.73, "bowl rings on the bowl water")
	local sound = Find(anchor, "Sound")
	Everys(ctx)
	check(sound and sound.IsPlaying, "water sound near")
	-- a wading player
	local char = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	root.CFrame = CFrame.new(Kit.ToWorld(model, Vector3.new(1.8, 2.4, 0.3)))
	rawget(root, "_p").AssemblyLinearVelocity = Vector3.new(6, 0, 2)
	table.insert(MockPlayers, {Character = char, Parent = true, Name = "Wader"})
	local ringPe = Find(basin, "ParticleEmitter", "FunRings")
	local n0 = rawget(ringPe, "_emitted") or 0
	Everys(ctx)
	check((rawget(ringPe, "_emitted") or 0) == n0 + 1, "wading ripple")
	local w = Authored(model, basin.WorldPosition)
	check(near(w.X, 1.8, 1e-4) and near(w.Z, 0.3, 1e-4), "wading ripple under the player")
	table.clear(MockPlayers)
	Stop(ctx)
	check(Find(camera, "Part", "FunFountainFX") == nil, "fountain fx removed")
	-- server half
	local S = load("S_Fountain")
	local sctx = {}
	local ok, cleanup = pcall(S.Server, model, sctx)
	check(ok, "server errored " .. tostring(cleanup))
	for _, n in ipairs({"WaterSurface", "WaterBed", "Jets", "Foam"}) do check(Kit.Part(model, n).CanCollide == false, n .. " walk-through") end
	check(Kit.Part(model, "BasinWall").CanCollide == true, "basin wall still solid")
	-- broken: BuildHealthService de-collides everything and records our false; cleanup must leave it alone
	model:SetAttribute("Broken", true)
	for _, p in ipairs(Kit.Parts(model, "")) do p.CanCollide = false end
	cleanup()
	check(Kit.Part(model, "BasinWall").CanCollide == false, "broken: cleanup leaves collisions to BuildHealthService")
	-- mend restores the record (water false, wall true), restart, then a move (cleanup restores originals)
	Kit.Part(model, "BasinWall").CanCollide = true
	model:SetAttribute("Broken", nil)
	local _, cleanup2 = pcall(S.Server, model, sctx)
	check(Kit.Part(model, "WaterSurface").CanCollide == false, "re-run after mend: water walk-through")
	cleanup2()
	for _, n in ipairs({"WaterSurface", "WaterBed", "Jets", "Foam"}) do check(Kit.Part(model, n).CanCollide == true, n .. " original restored") end
	model:Destroy()
end

------------------------------------------------------------------ Pond
do
	local scale = 1.3
	local model = MakePlaced("Pond", "Pond", nil, scale, CFrame.new(-30, 5, -70) * YAW)
	SetCamera(model, 25)
	local padsBefore = Kit.Part(model, "LilyPads").CFrame
	local lotusBefore = Kit.Part(model, "LilyLotus").CFrame
	local ctx = Run(load("C_Pond"), model)
	for _, n in ipairs({"Fish1", "Fish2", "Fish3", "FishEyes", "FishMarks"}) do check(Kit.Part(model, n).LocalTransparencyModifier == 1, n .. " hidden locally") end
	check(Kit.Part(model, "Water").CanCollide == true, "pond water stays collidable")
	local bodies = FindAll(camera, "Part", "KoiBody")
	check(#bodies == 3, "three koi")
	local fins = FindAll(camera, "WedgePart", "KoiFin")
	local tails = FindAll(camera, "WedgePart", "KoiTail")
	check(#fins == 3 and #tails == 6, "fins + tails")
	-- shore polygon for checking (authored)
	local SHORE = {{3.785, -0.488}, {2.912, -2.326}, {0.603, -1.860}, {-1.016, -2.620}, {-3.261, -1.660}, {-2.534, 0.856}, {-0.982, 2.055}, {1.788, 2.361}, {3.132, 0.556}}
	local function inside(x, z)
		local c = false
		for i = 1, #SHORE do
			local a, b = SHORE[i], SHORE[i % #SHORE + 1]
			if (a[2] > z) ~= (b[2] > z) and x < (b[1] - a[1]) * (z - a[2]) / (b[2] - a[2]) + a[1] then c = not c end
		end
		return c
	end
	local worstOut, minY, maxY, maxFinTop = 0, 99, -99, -99
	local maxTilt = 0
	local speeds = {}
	local lastPos = {}
	for step = 1, 1500 do
		Frames(ctx, 1, 0.05)
		for i, body in ipairs(bodies) do
			local a = Authored(model, body.Position)
			-- nose + tail tips
			local look = Kit.Origin(model):Inverse().Rotation * body.CFrame.LookVector -- authored frame
			local half = body.Size.Z / 2 / scale
			for _, tip in ipairs({a, a + Vector3.new(look.X, 0, look.Z) * (half + 0.2), a - Vector3.new(look.X, 0, look.Z) * (half + 0.3)}) do
				if not inside(tip.X, tip.Z) then worstOut += 1 if worstOut < 6 then print("OUT fish", i, tostring(tip), "centre", tostring(a)) end end
			end
			minY = math.min(minY, a.Y)
			maxY = math.max(maxY, a.Y)
			if lastPos[i] then
				local d = (a - lastPos[i]).Magnitude / 0.05
				speeds[i] = math.max(speeds[i] or 0, d)
				-- the fish faces where it goes
				local mv = a - lastPos[i]
				local lookA = Kit.Origin(model):Inverse().Rotation * body.CFrame.LookVector
				if mv.Magnitude > 1e-3 then
					local cosang = (Vector3.new(mv.X, 0, mv.Z).Unit):Dot(Vector3.new(lookA.X, 0, lookA.Z).Unit)
					maxTilt = math.max(maxTilt, math.deg(math.acos(math.clamp(cosang, -1, 1))))
				end
			end
			lastPos[i] = a
		end
		for _, fin in ipairs(fins) do
			local top = Authored(model, fin.CFrame * Vector3.new(0, fin.Size.Y / 2, fin.Size.Z / 2)).Y
			maxFinTop = math.max(maxFinTop, top)
		end
	end
	print(("koi: out-of-water samples %d, body y %.3f..%.3f (water 0.50), max fin top %.3f, heading error max %.1f deg, top speeds %.2f %.2f %.2f authored/s")
		:format(worstOut, minY, maxY, maxFinTop, maxTilt, speeds[1], speeds[2], speeds[3]))
	check(worstOut == 0, "koi stay in the water")
	check(maxY < 0.40 and minY > 0.28, "koi just under the surface")
	check(maxFinTop > 0.5 and maxFinTop < 0.58, "Fish1 fin breaks the surface a little")
	check(maxTilt < 25, "koi face their direction of travel (incl. the head sway)")
	-- tail: the two halves meet at the midline, wedge fan behind the body
	do
		local body = bodies[1]
		local tailPair = {}
		for _, t in ipairs(tails) do
			if (t.Position - body.Position).Magnitude < body.Size.Z then table.insert(tailPair, t) end
		end
		check(#tailPair == 2, "tail pair near body 1")
		for _, t in ipairs(tailPair) do
			local rel = body.CFrame:PointToObjectSpace(t.Position)
			check(rel.Z > body.Size.Z * 0.4, "tail behind the body (+Z) " .. tostring(rel))
			check(math.abs(t.CFrame.RightVector.Y) > 0.99, "tail wedge lies flat (thickness along Y)")
		end
	end
	-- pads bob and stay near
	local pads = Kit.Part(model, "LilyPads")
	check((pads.CFrame.Position - padsBefore.Position).Magnitude < 0.2, "pads bob in place")
	-- dump the koi parts in the pond's origin frame (world studs) for a Blender preview render
	do
		local inv = Kit.Origin(model):Inverse()
		for _, d in ipairs(camera:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:sub(1, 3) == "Koi" then
				local c = inv * d.CFrame
				local m = rawget(c, "m")
				local shape = d.ClassName == "WedgePart" and "Wedge" or (d.Shape == Enum.PartType.Ball and "Ball" or (Find(d, "SpecialMesh") and "Ellipsoid" or "Block"))
				print(("KOI %s %s %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.3f %.3f %.3f %.2f"):format(
					d.Name, shape, c.p.X, c.p.Y, c.p.Z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9],
					d.Size.X, d.Size.Y, d.Size.Z, d.Color.R, d.Color.G, d.Color.B, d.Transparency or 0))
			end
		end
	end
	-- ripples
	local rip = Find(camera, "Attachment", "Ripple")
	local total = 0
	for _, pe in ipairs(FindAll(rip, "ParticleEmitter")) do total += rawget(pe, "_emitted") or 0 end
	print("pond ripples emitted in 75 s:", total)
	check(total > 20, "ripples emitted")
	-- someone walking on the pond
	local char = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	root.CFrame = CFrame.new(Kit.ToWorld(model, Vector3.new(0.5, 2.8, 0.2)))
	rawget(root, "_p").AssemblyLinearVelocity = Vector3.new(0, 0, 8)
	table.insert(MockPlayers, {Character = char, Parent = true, Name = "Walker"})
	local big = FindAll(rip, "ParticleEmitter")[1]
	local n0 = rawget(big, "_emitted") or 0
	Everys(ctx)
	check((rawget(big, "_emitted") or 0) == n0 + 1, "walking ripple")
	table.clear(MockPlayers)
	-- BuildMenuClient move ghost (fun-builds/live/BuildMenuClient.client.lua): StartPlacing(moving) sets 0.85 on
	-- every BasePart of the build, StopPlacing sets 0 - a cancelled move / same-spot drop restarts nothing
	local STATIC = {"Fish1", "Fish2", "Fish3", "FishEyes", "FishMarks"}
	local function Ghost(v)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = v end
		end
	end
	local function StaticAll(v)
		for _, n in ipairs(STATIC) do if Kit.Part(model, n).LocalTransparencyModifier ~= v then return false end end
		return true
	end
	local function KoiAll(v)
		local n = 0
		for _, d in ipairs(camera:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:sub(1, 3) == "Koi" then
				n += 1
				if d.LocalTransparencyModifier ~= v then return false end
			end
		end
		return n == 30
	end
	check(KoiAll(0), "swimming koi start fully visible")
	Ghost(0.85)
	check(StaticAll(1), "move ghost: static koi stay hidden (no 0.85 ghost)")
	check(KoiAll(0.85), "move ghost: swimming koi fade with the pond")
	check(Kit.Part(model, "Bank").LocalTransparencyModifier == 0.85, "move ghost: the pond itself ghosts")
	Ghost(0)
	check(StaticAll(1), "cancelled move: static koi hidden again")
	check(KoiAll(0), "cancelled move: swimming koi back to full")
	Frames(ctx, 10)
	Everys(ctx)
	check(StaticAll(1), "cancelled move: static koi still hidden a moment later")
	Stop(ctx)
	for _, n in ipairs(STATIC) do check(Kit.Part(model, n).LocalTransparencyModifier == 0, n .. " shown again (cleanup not fought by the re-hide)") end
	Ghost(0.85)
	check(StaticAll(0.85), "after stop: the re-hide handlers are gone")
	Ghost(0)
	check(vnear(Kit.Part(model, "LilyPads").CFrame.Position, padsBefore.Position, 1e-5), "pads restored")
	check(vnear(Kit.Part(model, "LilyLotus").CFrame.Position, lotusBefore.Position, 1e-5), "lotus restored")
	check(#FindAll(camera, "Part", "KoiBody") == 0, "koi removed")
	-- a real move: restart while the ghost is still up, StopPlacing lands after the restart
	Ghost(0.85)
	local ctx2 = Run(load("C_Pond"), model)
	check(StaticAll(1), "restart mid-ghost: static koi hidden")
	check(KoiAll(0.85), "restart mid-ghost: new koi pick up the ghost")
	Ghost(0)
	check(StaticAll(1) and KoiAll(0), "restart then StopPlacing: static hidden, koi visible")
	Stop(ctx2)
	check(StaticAll(0), "second cleanup shows the static koi")
	model:Destroy()
end

print(("%d checks, %d failed"):format(checks, fails))
