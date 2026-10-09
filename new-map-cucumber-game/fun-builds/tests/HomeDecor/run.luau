--!nocheck
-- Minimal Roblox mock for running fun-build behaviours headless (Vector3/Vector2/CFrame maths real, Instances as
-- property bags). Copied from tests/GardenLights for the HomeDecor package (Aquarium, PottedPlant) and extended:
-- Color3.fromHex, 12-number CFrame.new, a SEEDED Random (Park-Miller, so plans can be compared across "clients"),
-- Players.LocalPlayer, CornerWedgePart, task.delay (queued, run by the tests).

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
function V3m.Lerp(a, b, t) return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
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
Color3 = {fromRGB = function(r, g, b) return {R = r / 255, G = g / 255, B = b / 255} end, new = function(r, g, b) return {R = r, G = g, B = b} end,
	fromHex = function(h)
		h = h:gsub("^#", "")
		assert(#h == 6 and h:match("^%x+$"), "fromHex " .. h)
		return {R = tonumber(h:sub(1, 2), 16) / 255, G = tonumber(h:sub(3, 4), 16) / 255, B = tonumber(h:sub(5, 6), 16) / 255}
	end}
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
	local state = math.floor(tonumber(seed) or 1) % 2147483646 + 1
	local function nextU()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	local r = {}
	function r:NextNumber(a, b) a = a or 0 b = b or 1 return a + nextU() * (b - a) end
	function r:NextInteger(a, b) assert(b >= a, "NextInteger range") return a + math.min(b - a, math.floor(nextU() * (b - a + 1))) end
	return r
end}
local delayed = {}
task = {
	delay = function(t, fn, ...) table.insert(delayed, {T = t, Fn = fn, Args = {...}}) end,
	spawn = function(fn, ...) fn(...) end,
	defer = function(fn, ...) fn(...) end,
	wait = function() return 0 end,
}
MockDelayed = delayed
local enumMeta
enumMeta = {__index = function(t, k) local v = setmetatable({__path = t.__path .. "." .. k}, enumMeta) rawset(t, k, v) return v end,
	__tostring = function(t) return t.__path end}
Enum = setmetatable({__path = "Enum"}, enumMeta)

------------------------------------------------------------------ Instances
local CLASS_IS = {
	Part = {BasePart = true, Part = true}, WedgePart = {BasePart = true, WedgePart = true}, MeshPart = {BasePart = true, MeshPart = true},
	CornerWedgePart = {BasePart = true, CornerWedgePart = true},
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
function InstM.GetAttribute(self, k) return rawget(self, "_a")[k] end
function InstM.SetAttribute(self, k, v) rawget(self, "_a")[k] = v end
function InstM.Destroy(self) if self.Parent then self.Parent = nil end rawset(self, "_destroyed", true) end
function InstM.IsDescendantOf(self, other) local p = self.Parent while p do if p == other then return true end p = p.Parent end return false end
function InstM.Emit(self, n) rawset(self, "_emitted", (rawget(self, "_emitted") or 0) + n) end
function InstM.Play(self) rawget(self, "_p").IsPlaying = true rawset(self, "_plays", (rawget(self, "_plays") or 0) + 1) end
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
local localPlayer = newInst("Folder")
localPlayer.Name = "LocalPlayer"
rawget(localPlayer, "_p").UserId = 101
rawget(Players, "_p").LocalPlayer = localPlayer
MockLocalPlayer = localPlayer
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
SOURCES['C_Aquarium'] = [======[
--[[
	Aquarium  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package HomeDecor
	Client half of the fish tank (server half: ServerStorage.FunBehaviours.Aquarium; fun-builds/CONTRACT.md).
	  * FIVE FISH built from local parts (ellipsoid body, eyes with pupils, a dorsal fin, a two-wedge fan tail that
	    wags faster the faster the fish swims, plus each species' markings): a clownfish, a blue tang, a yellow
	    tang, a royal gramma and a neon tetra. Each swims its own smooth closed loop (an ellipse with a vertical
	    wave, speeding up and gliding) inside the water box Pivot_TankMin..Pivot_TankMax. The loops were fitted
	    offline to the authored tank (DESIGN_MIN/MAX): no fish touches the glass, the gravel, the castle, the chest
	    or another fish; a different box is mapped onto them linearly. Positions are a pure function of the
	    server clock (Kit.Now), so every client sees the same fish in the same place.
	  * BUBBLES trickle from the treasure chest (Pivot_Bubbler) and pop at the water surface; every LID_PERIOD s
	    the chest lid (ChestLid, hinged at Pivot_ChestHinge) pops open and lets out a burst of big bubbles
	  * the PLANTS (Plant<N>Leaf<M>) sway in the current about their clump's base (Pivot_Plant<N>), the castle
	    flag (CastleFlag, Pivot_Flag) waves, and a cool PointLight under the hood (Pivot_Light) lights the water
	  * FEEDING (state Fun_FedAt = the server time someone pressed "Feed fish"): the FeedFlap flips open, 12 food
	    flakes sprinkle onto the water under it (little rings where they land) and drift apart, and the fish rush
	    up and gobble them - 2-3 each, nearest first, nose-up while they nibble; every flake vanishes with a gulp
	    and a few bubbles - then swim back into their loops. The flakes and the plan are seeded by Fun_FedAt, so a
	    player who streams in half-way sees the same moment as everyone else.
	Sounds (FunAssets.Sfx, all skipped while the player's SFXEnabled attribute is false): BubblesLoop near the
	tank, Click for the flap, Splash when the flakes land, Gulp per flake eaten.
	Every build part it moves (leaves, flag, chest lid, feed flap) goes back to rest relative to the build's
	current hitbox on cleanup. Particle textures are the engine's built-in rbxasset:// ones.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

local player = Players.LocalPlayer

--..Config..--
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds" -- soft ring: bubbles + landing rings
local DESIGN_MIN = Vector3.new(-2.90, 3.62, -1.20) -- the water box the fish loops were fitted in (authored TankMin/Max)
local DESIGN_MAX = Vector3.new(2.90, 5.94, 1.20)
local FEED_FALLBACK = Vector3.new(0, 5.94, -0.745)
local BUBBLER_FALLBACK = Vector3.new(1.72, 4.02, -0.66)
local LIGHT_FALLBACK = Vector3.new(0, 5.97, 0.3)
local LIGHT_COLOR = Color3.fromRGB(190, 232, 255)
local LIGHT_BRIGHTNESS = 1.2
local LIGHT_RANGE = 9            -- authored studs (x Scale)
local NEAR_SOUND = 45            -- studs camera <-> tank for the bubbling loop
local TAIL_WAG = 0.38            -- rad each side
local YAW_RATE = 7               -- 1/s: how fast a fish turns toward where it is heading
local PITCH_RATE = 5
local PITCH_MAX = 0.5
local NIBBLE_PITCH = 0.45        -- nose up while nibbling a flake
local SPACING = 0.45             -- authored studs: fish centres closer than this get nudged apart (only at the food)
local WALL_MARGIN = Vector3.new(0.35, 0.3, 0.28) -- authored: fish centres keep this far inside the water box
local SURFACE_MARGIN = 0.12      -- ... and this far under the surface
--.. plants / flag / chest lid / feed flap
local SWAY_AMP = math.rad(5)
local SWAY_PERIOD = 3.6
local FLAG_AMP = 0.35
local FLAG_PERIOD = 1.3
local LID_PERIOD = 7.0           -- s between chest-lid pops (server clock)
local LID_SHUT = math.rad(-22)   -- rest: shut (the authored lid is 24 degrees ajar)
local LID_OPEN = math.rad(22)    -- popped open: 46 degrees
local LID_TIMES = {0.22, 1.1, 1.6} -- open by, start closing, shut by (s into the cycle)
local FLAP_OPEN = math.rad(68)
local FLAP_TIMES = {0.25, 1.2, 1.55} -- open by, start closing, shut by (s after Fun_FedAt)
--.. feeding (seconds after Fun_FedAt)
local N_FLAKES = 12
local DROP_FROM, DROP_TO = 0.12, 0.6 -- flakes leave the flap over this window
local DROP_HEIGHT = 0.45         -- authored studs above the water they fall from
local FALL_TIME = 0.35
local FLAKE_DRIFT_TAU = 0.9      -- s: how fast the flakes spread on the surface
local RUSH_START, RUSH_STAGGER = 0.45, 0.13
local APPROACH, NIBBLE, MOVE, LINGER, RETURN = 0.85, 0.45, 0.55, 0.25, 1.3
local FEED_TIME = 6.5            -- after this nothing of a feeding is left
local NIBBLE_DEPTH = 0.17        -- authored studs: a feeding fish's centre under its flake
local FLAKE_SIZE = Vector3.new(0.13, 0.05, 0.1) -- authored (x Scale)
local FLAKE_COLORS = {
	Color3.fromRGB(242, 120, 48), Color3.fromRGB(217, 68, 60), Color3.fromRGB(242, 193, 61),
	Color3.fromRGB(120, 190, 70), Color3.fromRGB(200, 150, 90),
}
local FLAKE_AREA_MIN = Vector3.new(-2.35, 0, -0.98) -- design box XZ the flakes may drift in (clear of the castle)
local FLAKE_AREA_MAX = Vector3.new(2.35, 0, 0.2)
local WHITE = Color3.fromRGB(247, 247, 242)
local INK = Color3.fromRGB(35, 38, 44)

--.. the fish: Loop = design-box ellipse (C centre, RX/RZ radii, Rot degrees, RY/KY/PY vertical wave, Period s per
--.. loop, Dir, Glide/GlidePeriod: a time warp that speeds up and glides, needs Glide * Period < GlidePeriod),
--.. Meals = flakes it eats per feeding (they add up to N_FLAKES), Look = authored proportions + colours
local FISH = {
	{Name = "Clown", Meals = 3,
		Loop = {C = Vector3.new(1.10, 4.55, 0.52), RX = 1.05, RZ = 0.34, Rot = 6, RY = 0.14, KY = 2, PY = 0.5,
			Period = 12.0, Dir = 1, Glide = 0.22, GlidePeriod = 4.7, Phase = 0.0},
		Look = {W = 0.24, H = 0.32, L = 0.66, Body = "ff7a1a", Fin = "ff9a3c", Tail = "ff9a3c", Stripes = {-0.2, 0.12}, Stripe = "f7f7f2"}},
	{Name = "Tang", Meals = 3,
		Loop = {C = Vector3.new(1.05, 5.00, -0.62), RX = 1.20, RZ = 0.30, Rot = 0, RY = 0.18, KY = 1, PY = 1.2,
			Period = 13.0, Dir = -1, Glide = 0.22, GlidePeriod = 5.1, Phase = 1.3},
		Look = {W = 0.20, H = 0.44, L = 0.74, Body = "2f6fe0", Fin = "1b2f73", Tail = "f2c13d", Anal = true}},
	{Name = "Yellow", Meals = 2,
		Loop = {C = Vector3.new(1.05, 5.38, 0.52), RX = 1.10, RZ = 0.32, Rot = -5, RY = 0.10, KY = 1, PY = 0.0,
			Period = 14.0, Dir = -1, Glide = 0.22, GlidePeriod = 4.3, Phase = 2.4},
		Look = {W = 0.18, H = 0.50, L = 0.66, Body = "ffd23a", Fin = "ffe066", Tail = "ffe066", Snout = true, Anal = true}},
	{Name = "Gramma", Meals = 2,
		Loop = {C = Vector3.new(-1.65, 4.72, -0.45), RX = 0.60, RZ = 0.40, Rot = -6, RY = 0.18, KY = 1, PY = 2.0,
			Period = 9.0, Dir = -1, Glide = 0.22, GlidePeriod = 3.9, Phase = 4.1},
		Look = {W = 0.18, H = 0.30, L = 0.60, Body = "a24fe0", Fin = "a24fe0", Tail = "f7cf2f", Back = "f7cf2f"}},
	{Name = "Tetra", Meals = 2,
		Loop = {C = Vector3.new(0.00, 5.66, -0.58), RX = 2.20, RZ = 0.34, Rot = 0, RY = 0.05, KY = 2, PY = 0.7,
			Period = 12.0, Dir = 1, Glide = 0.22, GlidePeriod = 5.3, Phase = 0.9},
		Look = {W = 0.13, H = 0.22, L = 0.52, Body = "b8d4ee", Fin = "d6e6f5", Tail = "d6e6f5", Neon = "2fd9ff", Belly = "e8413a"}},
}

local B = {}
B.StepRange = 140

--..Helpers..--
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

local function Smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function LerpAngle(a, b, f)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * f
end

local function SameCFrame(a, b)
	return (a.Position - b.Position).Magnitude < 1e-3 and a.LookVector:Dot(b.LookVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
end

local function SfxOn()
	return player:GetAttribute("SFXEnabled") ~= false
end

--.. a local-only part of any class (ctx:Part only makes Parts; fins and tails are WedgeParts)
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

local function Ellipsoid(ctx, size, color, name, material)
	local p = LocalPart(ctx, "Part", {Name = name, Size = size, Color = color, Material = material or Enum.Material.SmoothPlastic})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function Ball(ctx, d, color, name)
	return LocalPart(ctx, "Part", {Name = name, Shape = Enum.PartType.Ball, Size = Vector3.one * d, Color = color})
end

local function Emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_RING
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Top
	e.LightEmission = 0.3
	e.LightInfluence = 0.5
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

--..Fish..--
--.. builds one fish from local parts: {Spec, Body = {{part, offset}}, Tail = {{part, offset from the tail root}},
--.. TailRoot}; nose toward -Z, up +Y, k = studs per authored unit (Scale)
local function BuildFish(ctx, spec, k)
	local look = spec.Look
	local w0, h0, l0 = look.W, look.H, look.L
	local W, H, L = w0 * k, h0 * k, l0 * k
	local fish = {Spec = spec, Body = {}, Tail = {}, TailRoot = CFrame.new(0, 0, L * 0.42)}
	local function body(part, offset) table.insert(fish.Body, {part, offset}) end
	local bodyColor = Color3.fromHex(look.Body)
	local finColor = Color3.fromHex(look.Fin)
	body(Ellipsoid(ctx, Vector3.new(W, H, L), bodyColor, "FishBody"), CFrame.identity)
	--.. markings
	for _, z0 in ipairs(look.Stripes or {}) do
		local f = math.sqrt(math.max(0.05, 1 - (2 * z0) ^ 2)) -- the body's cross-section there
		body(Ellipsoid(ctx, Vector3.new(w0 * f + 0.03, h0 * f + 0.03, 0.07) * k, Color3.fromHex(look.Stripe), "FishStripe"),
			CFrame.new(0, 0, z0 * L))
	end
	if look.Back then -- the royal gramma's yellow back half
		body(Ellipsoid(ctx, Vector3.new(w0 + 0.012, h0 * 0.94, l0 * 0.56) * k, Color3.fromHex(look.Back), "FishBack"),
			CFrame.new(0, 0, 0.2 * L))
	end
	if look.Neon then -- the neon tetra's glowing stripe + red belly
		body(Ellipsoid(ctx, Vector3.new(w0 + 0.012, 0.05, l0 * 0.72) * k, Color3.fromHex(look.Neon), "FishNeon", Enum.Material.Neon),
			CFrame.new(0, 0.03 * k, -0.02 * L))
		body(Ellipsoid(ctx, Vector3.new(w0 + 0.006, h0 * 0.4, l0 * 0.45) * k, Color3.fromHex(look.Belly), "FishBelly"),
			CFrame.new(0, -0.045 * k, 0.14 * L))
	end
	if look.Snout then -- the yellow tang's pointed snout
		body(Ellipsoid(ctx, Vector3.new(W * 0.5, H * 0.2, L * 0.28), bodyColor, "FishSnout"), CFrame.new(0, -H * 0.05, -L * 0.48))
	end
	--.. eyes (white + pupil)
	local eye = math.max(0.09, 0.3 * h0) * k
	local ex = W * 0.35
	for _, s in ipairs({-1, 1}) do
		body(Ball(ctx, eye, WHITE, "FishEye"), CFrame.new(s * ex, H * 0.12, -L * 0.3))
		body(Ball(ctx, eye * 0.6, INK, "FishPupil"), CFrame.new(s * (ex + eye * 0.3), H * 0.12, -L * 0.3 - eye * 0.1))
	end
	--.. fins: a dorsal wedge rising toward the back (+ an anal fin under the tall ones)
	local dh, dl = H * 0.36, L * 0.46
	body(LocalPart(ctx, "WedgePart", {Name = "FishDorsal", Size = Vector3.new(0.05 * k, dh, dl), Color = finColor}),
		CFrame.new(0, H * 0.41 + dh * 0.5, 0))
	if look.Anal then
		body(LocalPart(ctx, "WedgePart", {Name = "FishAnal", Size = Vector3.new(0.05 * k, dh * 0.6, dl * 0.6), Color = finColor}),
			CFrame.new(0, -(H * 0.4 + dh * 0.3), 0.1 * L) * CFrame.Angles(0, 0, math.pi))
	end
	--.. tail: two wedges fanning out behind the root (the lower one upside down)
	local tl, th = L * 0.32, H * 0.46
	local tailColor = Color3.fromHex(look.Tail)
	table.insert(fish.Tail, {LocalPart(ctx, "WedgePart", {Name = "FishTail", Size = Vector3.new(0.05 * k, th, tl), Color = tailColor}),
		CFrame.new(0, th * 0.5, tl * 0.5)})
	table.insert(fish.Tail, {LocalPart(ctx, "WedgePart", {Name = "FishTail", Size = Vector3.new(0.05 * k, th, tl), Color = tailColor}),
		CFrame.new(0, -th * 0.5, tl * 0.5) * CFrame.Angles(0, 0, math.pi)})
	return fish
end

--.. a loop at server time t -> design-box position, velocity (design studs / s)
local function LoopAt(loop, t)
	local w, w2 = 2 * math.pi / loop.Period, 2 * math.pi / loop.GlidePeriod
	local progress = w * t + loop.Glide * math.sin(w2 * t)
	local rate = loop.Dir * (w + loop.Glide * w2 * math.cos(w2 * t))
	local s = loop.Dir * progress + loop.Phase
	local a = math.rad(loop.Rot)
	local ca, sa = math.cos(a), math.sin(a)
	local ex, ez = loop.RX * math.cos(s), loop.RZ * math.sin(s)
	local dex, dez = -loop.RX * math.sin(s), loop.RZ * math.cos(s)
	local wave = loop.KY * s + loop.PY
	local pos = Vector3.new(loop.C.X + ex * ca - ez * sa, loop.C.Y + loop.RY * math.sin(wave), loop.C.Z + ex * sa + ez * ca)
	local vel = Vector3.new(dex * ca - dez * sa, loop.RY * loop.KY * math.cos(wave), dex * sa + dez * ca) * rate
	return pos, vel
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local scale = ctx.Scale
	local home = hitbox.CFrame
	local origin = Kit.Origin(model)
	local rotation = origin.Rotation
	local timeOffset = (home.Position.X * 0.61 + home.Position.Z * 0.37) % 60 -- neighbouring tanks aren't in lockstep

	--..The water box: design box -> this build's Pivot_TankMin/Max (authored)..--
	local boxMin = model:GetAttribute("Pivot_TankMin")
	local boxMax = model:GetAttribute("Pivot_TankMax")
	if typeof(boxMin) ~= "Vector3" or typeof(boxMax) ~= "Vector3" then boxMin, boxMax = DESIGN_MIN, DESIGN_MAX end
	local boxK = (boxMax - boxMin) / (DESIGN_MAX - DESIGN_MIN)
	local function Map(p) return boxMin + (p - DESIGN_MIN) * boxK end
	local surfaceY = boxMax.Y
	local function Authored(name, fallback)
		local v = model:GetAttribute("Pivot_" .. name)
		return typeof(v) == "Vector3" and v or fallback
	end
	local feedPoint = Authored("Feed", FEED_FALLBACK)
	local bubbler = Authored("Bubbler", BUBBLER_FALLBACK)
	local areaMin, areaMax = Map(FLAKE_AREA_MIN), Map(FLAKE_AREA_MAX)
	local function World(p) return origin * CFrame.new(p * scale) end -- authored point -> world CFrame (authored axes)

	--..Build parts we animate: rest = hitbox-relative, restored on cleanup..--
	local rest = {} -- [part] = hitbox-relative CFrame
	local function Remember(part) rest[part] = home:ToObjectSpace(part.CFrame) end
	--.. a rig about an authored pivot: {Parts, Rel (pivot-relative), Pivot (world CFrame, authored axes)}
	local function Rig(parts, pivotName, fallback)
		local p = model:GetAttribute("Pivot_" .. pivotName)
		if typeof(p) ~= "Vector3" then p = fallback end
		if not p or #parts == 0 then return nil end
		local pivot = CFrame.new(Kit.ToWorld(model, p)) * rotation
		local rig = {Parts = parts, Rel = {}, Pivot = pivot}
		for i, part in ipairs(parts) do
			Remember(part)
			rig.Rel[i] = pivot:ToObjectSpace(part.CFrame)
		end
		return rig
	end

	--.. plants: one rig per clump, each leaf with its own phase
	local clumps = {}
	for _, part in ipairs(Kit.Parts(model, "Plant")) do
		local n, m = part.Name:match("^Plant(%d+)Leaf(%d+)$")
		if n then
			n, m = tonumber(n), tonumber(m)
			clumps[n] = clumps[n] or {}
			table.insert(clumps[n], {Part = part, Index = m})
		end
	end
	local leaves = {} -- {Part, Rel, Pivot, Phase}
	for n, list in pairs(clumps) do
		local parts = {}
		for _, item in ipairs(list) do table.insert(parts, item.Part) end
		local rig = Rig(parts, "Plant" .. n, nil)
		if rig then
			for i, item in ipairs(list) do
				table.insert(leaves, {Part = item.Part, Rel = rig.Rel[i], Pivot = rig.Pivot, Phase = n * 1.1 + item.Index * 0.45})
			end
		end
	end
	local flagPart = Kit.Part(model, "CastleFlag")
	local flagRig = flagPart and Rig({flagPart}, "Flag", nil)
	local lidPart = Kit.Part(model, "ChestLid")
	local lidRig = lidPart and Rig({lidPart}, "ChestHinge", nil)
	local flapParts = {}
	for _, name in ipairs({"FeedFlap", "FeedFlapTab"}) do
		local part = Kit.Part(model, name)
		if part then table.insert(flapParts, part) end
	end
	local flapRig = Rig(flapParts, "FeedHinge", nil)
	local posed = false

	--..Effects host: an invisible local part at the authored origin (attachments in authored axes)..--
	local fx = ctx:Part({Name = "AquariumFX", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = origin})
	local function Attach(name, authored)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = authored * scale
		a.Parent = fx
		return a
	end
	local rise = math.max(0.3, surfaceY - bubbler.Y) -- authored studs from the bubbler to the surface
	local bubbleAt = Attach("Bubbler", bubbler)
	local trickle = Emitter(bubbleAt, {
		Name = "Trickle",
		Color = ColorSequence.new(Color3.fromRGB(235, 250, 255)),
		Size = NumberSequence.new({kp(0, 0.07 * scale), kp(1, 0.12 * scale)}),
		Transparency = NumberSequence.new({kp(0, 0.15), kp(0.9, 0.25), kp(1, 1)}),
		Speed = NumberRange.new(1.0 * scale),
		Lifetime = NumberRange.new(rise / 1.0 * 0.97, rise / 1.0),
		SpreadAngle = Vector2.new(6, 6),
		Rate = 3,
		ZOffset = 0.5, -- draw over the translucent water they rise through
	})
	local burst = Emitter(bubbleAt, {
		Name = "Burst",
		Color = ColorSequence.new(Color3.fromRGB(240, 252, 255)),
		Size = NumberSequence.new({kp(0, 0.12 * scale), kp(1, 0.2 * scale)}),
		Transparency = NumberSequence.new({kp(0, 0.1), kp(0.9, 0.2), kp(1, 1)}),
		Speed = NumberRange.new(1.4 * scale),
		Lifetime = NumberRange.new(rise / 1.4 * 0.95, rise / 1.4),
		SpreadAngle = Vector2.new(14, 14),
		ZOffset = 0.5,
	})
	local gulpAt = Attach("Gulp", feedPoint)
	local gulp = Emitter(gulpAt, {
		Name = "Gulp",
		Color = ColorSequence.new(Color3.fromRGB(240, 252, 255)),
		Size = NumberSequence.new({kp(0, 0.05 * scale), kp(1, 0.09 * scale)}),
		Transparency = NumberSequence.new({kp(0, 0.15), kp(1, 1)}),
		Speed = NumberRange.new(0.3 * scale, 0.6 * scale),
		Lifetime = NumberRange.new(0.3, 0.45),
		SpreadAngle = Vector2.new(35, 35),
		ZOffset = 0.5,
	})
	local ringAt = Attach("Ring", feedPoint)
	local ring = Emitter(ringAt, {
		Name = "LandRing",
		Color = ColorSequence.new(Color3.fromRGB(225, 245, 255)),
		Size = NumberSequence.new({kp(0, 0.1 * scale), kp(1, 0.55 * scale)}),
		Transparency = NumberSequence.new({kp(0, 0.35), kp(1, 1)}),
		Speed = NumberRange.new(0.02),
		Lifetime = NumberRange.new(0.6, 0.8),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, -- lies flat on the water
		Rotation = NumberRange.new(0, 360),
		ZOffset = 0.3,
	})
	--.. the tank light
	local lightAt = Attach("Light", Authored("Light", LIGHT_FALLBACK))
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Brightness = LIGHT_BRIGHTNESS
	light.Range = LIGHT_RANGE * scale
	light.Shadows = false
	light.Parent = lightAt

	--..Sounds..--
	local bubbleLoop = ctx:Sound(fx, FunAssets.Sfx.BubblesLoop, {Name = "Bubbles", Looped = true, Volume = 0.14,
		RollOffMinDistance = 5, RollOffMaxDistance = NEAR_SOUND})
	local click = ctx:Sound(fx, FunAssets.Sfx.Click, {Name = "Click", Volume = 0.35, RollOffMaxDistance = 40})
	local splash = ctx:Sound(fx, FunAssets.Sfx.Splash, {Name = "Sprinkle", Volume = 0.16, PlaybackSpeed = 1.9, RollOffMaxDistance = 40})
	local gulpSound = ctx:Sound(fx, FunAssets.Sfx.Gulp, {Name = "Gulp", Volume = 0.12, RollOffMaxDistance = 35})
	local function Play(sound, pitch)
		if not SfxOn() or ctx:CameraDistance() > NEAR_SOUND then return end
		if pitch then sound.PlaybackSpeed = pitch end
		sound.TimePosition = 0
		sound:Play()
	end
	ctx:Every(0.5, function()
		local want = SfxOn() and ctx:CameraDistance() <= NEAR_SOUND
		if want and not bubbleLoop.IsPlaying then
			bubbleLoop:Play()
		elseif not want and bubbleLoop.IsPlaying then
			bubbleLoop:Stop()
		end
		local awake = ctx:CameraDistance() <= B.StepRange
		trickle.Enabled = awake
		light.Enabled = awake
	end)

	--..Fish..--
	local fishes = {}
	for _, spec in ipairs(FISH) do
		local fish = BuildFish(ctx, spec, scale)
		local _, vel = LoopAt(spec.Loop, Kit.Now() + timeOffset)
		fish.Yaw = math.atan2(-vel.X, -vel.Z)
		fish.Pitch = 0
		fish.Wag = math.random() * 6.28
		table.insert(fishes, fish)
	end
	local moveParts, moveCFrames = {}, {}

	--..Flakes: a pool of local parts, shown only during a feeding..--
	local flakeParts = {}
	for i = 1, N_FLAKES do
		flakeParts[i] = ctx:Part({Name = "FishFlake", Size = FLAKE_SIZE * scale, Transparency = 1, Material = Enum.Material.SmoothPlastic,
			CFrame = World(feedPoint)})
	end

	--..Feeding plan (pure function of Fun_FedAt: identical on every client)..--
	local feed = nil
	local function MakeFeed(t0)
		local rng = Random.new(math.floor((t0 * 1000) % 2147483000) + 1)
		local f = {T0 = t0, Flakes = {}, Plans = {}, Landed = {}, Eaten = {}, Rang = false, FlapDone = false}
		--.. every flake drifts to its own slot across the surface (shuffled, so the drop order doesn't sweep left to
		--.. right): the fish spread out along the tank instead of piling up under the flap
		local slots = {}
		for i = 1, N_FLAKES do slots[i] = i end
		for i = N_FLAKES, 2, -1 do
			local j = rng:NextInteger(1, i)
			slots[i], slots[j] = slots[j], slots[i]
		end
		for i = 1, N_FLAKES do
			local a = rng:NextNumber(0, 2 * math.pi)
			local r = rng:NextNumber(0, 0.28)
			local land = Vector3.new(feedPoint.X + math.cos(a) * r, surfaceY, feedPoint.Z + math.sin(a) * r)
			local u = (slots[i] - 0.5) / N_FLAKES
			local final = Vector3.new(
				math.clamp(areaMin.X + (areaMax.X - areaMin.X) * u + rng:NextNumber(-0.12, 0.12), areaMin.X, areaMax.X), surfaceY,
				rng:NextNumber(areaMin.Z, areaMax.Z))
			f.Flakes[i] = {
				Drop = DROP_FROM + (DROP_TO - DROP_FROM) * (i - 1) / (N_FLAKES - 1) + rng:NextNumber(-0.03, 0.03),
				Land = land, Final = final, Color = FLAKE_COLORS[rng:NextInteger(1, #FLAKE_COLORS)],
				Spin = rng:NextNumber(-4, 4), Tilt = rng:NextNumber(-0.35, 0.35), Eat = nil,
			}
		end
		--.. who eats what: the fish, ordered by where they are across the tank when the rush starts, split the flakes
		--.. (ordered by where they drift to) into side-by-side bands - Meals each - so nobody swims through anybody;
		--.. each fish eats its band nearest-first (from where it is, then from its last meal)
		local startPos, order = {}, {}
		for i, fish in ipairs(fishes) do
			f.Plans[i] = {Start = RUSH_START + RUSH_STAGGER * (i - 1), Meals = {}}
			startPos[i] = Map((LoopAt(fish.Spec.Loop, t0 + timeOffset + f.Plans[i].Start)))
			order[i] = i
		end
		table.sort(order, function(a, b) return startPos[a].X < startPos[b].X end)
		local byX = {}
		for k = 1, N_FLAKES do byX[k] = k end
		table.sort(byX, function(a, b) return f.Flakes[a].Final.X < f.Flakes[b].Final.X end)
		local nextFlake = 1
		for _, i in ipairs(order) do
			local plan = f.Plans[i]
			local band = {}
			for _ = 1, fishes[i].Spec.Meals do
				if nextFlake <= N_FLAKES then
					band[byX[nextFlake]] = true
					nextFlake += 1
				end
			end
			local from = startPos[i]
			while next(band) do
				local best, bestD = nil, math.huge
				for k in pairs(band) do
					local flake = f.Flakes[k]
					local dx, dz = flake.Final.X - from.X, flake.Final.Z - from.Z
					local dist = dx * dx + dz * dz
					if dist < bestD or (dist == bestD and k < best) then best, bestD = k, dist end
				end
				band[best] = nil
				local last = plan.Meals[#plan.Meals]
				local arrive = last and last.Eat + MOVE or plan.Start + APPROACH
				table.insert(plan.Meals, {Flake = best, Arrive = arrive, Eat = arrive + NIBBLE})
				f.Flakes[best].Eat = arrive + NIBBLE
				from = f.Flakes[best].Final
			end
		end
		for _, plan in ipairs(f.Plans) do
			local last = plan.Meals[#plan.Meals]
			plan.Leave = (last and last.Eat or plan.Start) + LINGER
		end
		for i, flake in ipairs(f.Flakes) do flakeParts[i].Color = flake.Color end
		return f
	end

	--.. where a flake is t s into the feeding (authored), eaten or not
	local function FlakeTrack(flake, t)
		if t <= flake.Drop then return flake.Land + Vector3.new(0, DROP_HEIGHT, 0) end
		local landT = flake.Drop + FALL_TIME
		if t < landT then
			local u = (t - flake.Drop) / FALL_TIME
			return (flake.Land + Vector3.new(0, DROP_HEIGHT * (1 - u * u), 0))
		end
		local p = flake.Land:Lerp(flake.Final, 1 - math.exp(-(t - landT) / FLAKE_DRIFT_TAU))
		return p + Vector3.new(0, 0.012 * math.sin(t * 3 + flake.Spin), 0)
	end

	--.. a feeding fish's target (authored), blend weight and nibbling flag at t s into the feeding
	local function FeedTarget(plan, f, t)
		local meals = plan.Meals
		if #meals == 0 or t < plan.Start or t > plan.Leave + RETURN then return nil, 0, false end
		local w
		if t < plan.Start + APPROACH then
			w = Smooth((t - plan.Start) / APPROACH)
		elseif t > plan.Leave then
			w = 1 - Smooth((t - plan.Leave) / RETURN)
		else
			w = 1
		end
		local cur = #meals
		for k = 1, #meals do
			if t < meals[k].Eat then cur = k break end
		end
		local meal = meals[cur]
		local down = Vector3.new(0, -NIBBLE_DEPTH, 0)
		local target = FlakeTrack(f.Flakes[meal.Flake], t) + down
		if cur > 1 and t < meal.Arrive then
			local prev = meals[cur - 1]
			local from = FlakeTrack(f.Flakes[prev.Flake], t) + down
			target = from:Lerp(target, Smooth((t - prev.Eat) / MOVE))
		end
		local nibbling = t >= meal.Arrive - 0.1 and t < meal.Eat + 0.05
		if nibbling then target += Vector3.new(0, 0.03 * math.sin(t * 14), 0) end
		return target, w, nibbling
	end

	--.. every fish's authored position at server time now -> out[i], nibbling -> nib[i]. Where two fish come closer
	--.. than SPACING (only ever while they crowd the food: the loops keep > 0.5 apart) they are nudged apart, then
	--.. kept inside the water. A pure function of the time and Fun_FedAt, so it is identical on every client.
	local wallMin = boxMin + Vector3.new(WALL_MARGIN.X, WALL_MARGIN.Y, WALL_MARGIN.Z)
	local wallMax = boxMax - Vector3.new(WALL_MARGIN.X, SURFACE_MARGIN, WALL_MARGIN.Z)
	local function School(now, out, nib)
		for i, fish in ipairs(fishes) do
			local pos = Map((LoopAt(fish.Spec.Loop, now + timeOffset)))
			local nibbling = false
			if feed then
				local target, w, nb = FeedTarget(feed.Plans[i], feed, now - feed.T0)
				if target and w > 0 then pos, nibbling = pos:Lerp(target, w), nb end
			end
			out[i], nib[i] = pos, nibbling
		end
		for _ = 1, 2 do
			for i = 1, #fishes do
				for j = i + 1, #fishes do
					local d = out[j] - out[i]
					local dist = d.Magnitude
					if dist < SPACING then
						local push = (dist > 1e-4 and d / dist or Vector3.xAxis) * ((SPACING - dist) * 0.5)
						out[i] -= push
						out[j] += push
					end
				end
			end
		end
		for i = 1, #fishes do
			local p = out[i]
			out[i] = Vector3.new(math.clamp(p.X, wallMin.X, wallMax.X), math.clamp(p.Y, wallMin.Y, wallMax.Y), math.clamp(p.Z, wallMin.Z, wallMax.Z))
		end
	end

	ctx:OnState("FedAt", function(t0)
		if type(t0) == "number" and Kit.Now() - t0 < FEED_TIME then
			feed = MakeFeed(t0)
			if Kit.Now() - t0 < 0.4 then Play(click, 1.1) end
		end
	end)

	--..Every frame..--
	local lastCycle = nil
	local lastGulp = 0
	local posNow, nibNow, posAhead, nibAhead = {}, {}, {}, {}
	ctx:Step(function(dt, now)
		if not (hitbox.Parent and SameCFrame(hitbox.CFrame, home)) then return end -- moved: the restart is on its way
		local n = 0
		local ease = 1 - math.exp(-YAW_RATE * dt)
		local easeP = 1 - math.exp(-PITCH_RATE * dt)

		--.. fish (velocity from where the school is 0.05 s later: follows the rush to the food as well as the loops)
		School(now, posNow, nibNow)
		School(now + 0.05, posAhead, nibAhead)
		for i, fish in ipairs(fishes) do
			local pos, nibbling = posNow[i], nibNow[i]
			local vel = (posAhead[i] - pos) / 0.05
			local flat = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
			if flat > 0.08 then fish.Yaw = LerpAngle(fish.Yaw, math.atan2(-vel.X, -vel.Z), ease) end
			local wantPitch = nibbling and NIBBLE_PITCH or math.clamp(math.atan2(vel.Y, math.max(flat, 0.05)), -PITCH_MAX, PITCH_MAX)
			fish.Pitch += (wantPitch - fish.Pitch) * easeP
			local speed = vel.Magnitude
			fish.Wag = (fish.Wag + dt * 2 * math.pi * (1.3 + 2.2 * math.min(speed, 1.6) + (nibbling and 1.5 or 0))) % (2 * math.pi)
			local wag = TAIL_WAG * math.sin(fish.Wag)
			local sway = -0.07 * math.sin(fish.Wag - 1.2) -- the head counter-swings the tail
			local cf = World(pos) * CFrame.Angles(0, fish.Yaw + sway, 0) * CFrame.Angles(fish.Pitch, 0, 0)
			for _, item in ipairs(fish.Body) do
				n += 1
				moveParts[n] = item[1]
				moveCFrames[n] = cf * item[2]
			end
			local tail = cf * fish.TailRoot * CFrame.Angles(0, wag, 0)
			for _, item in ipairs(fish.Tail) do
				n += 1
				moveParts[n] = item[1]
				moveCFrames[n] = tail * item[2]
			end
		end

		--.. plants sway in the current
		posed = true
		local w1, w2 = 2 * math.pi / SWAY_PERIOD, 2 * math.pi / (SWAY_PERIOD * 1.4)
		for _, leaf in ipairs(leaves) do
			local az = SWAY_AMP * math.sin(w1 * now + leaf.Phase)
			local ax = 0.4 * SWAY_AMP * math.sin(w2 * now + leaf.Phase * 1.7)
			n += 1
			moveParts[n] = leaf.Part
			moveCFrames[n] = leaf.Pivot * CFrame.Angles(ax, 0, az) * leaf.Rel
		end
		if flagRig then
			local a = FLAG_AMP * math.sin(2 * math.pi * now / FLAG_PERIOD) + 0.1 * math.sin(2 * math.pi * now / 0.47)
			n += 1
			moveParts[n] = flagRig.Parts[1]
			moveCFrames[n] = flagRig.Pivot * CFrame.Angles(0, a, 0) * flagRig.Rel[1]
		end

		--.. chest lid: shut, pops open every LID_PERIOD s with a burst of bubbles
		if lidRig then
			local clock = now + timeOffset
			local cycle = math.floor(clock / LID_PERIOD)
			local u = clock - cycle * LID_PERIOD
			if cycle ~= lastCycle then
				if lastCycle ~= nil and u < 0.5 and ctx:CameraDistance() <= B.StepRange then burst:Emit(9) end
				lastCycle = cycle
			end
			local open
			if u < LID_TIMES[1] then
				open = Smooth(u / LID_TIMES[1])
			elseif u < LID_TIMES[2] then
				open = 1
			else
				open = 1 - Smooth((u - LID_TIMES[2]) / (LID_TIMES[3] - LID_TIMES[2]))
			end
			n += 1
			moveParts[n] = lidRig.Parts[1]
			moveCFrames[n] = lidRig.Pivot * CFrame.Angles(LID_SHUT + (LID_OPEN - LID_SHUT) * open, 0, 0) * lidRig.Rel[1]
		end

		--.. feeding: flap, flakes, gulps
		if feed then
			local t = now - feed.T0
			if t > FEED_TIME then
				for _, part in ipairs(flakeParts) do part.Transparency = 1 end
				if flapRig and not feed.FlapDone then -- slept through the close (camera was far): shut it now
					for k, part in ipairs(flapRig.Parts) do
						n += 1
						moveParts[n] = part
						moveCFrames[n] = flapRig.Pivot * flapRig.Rel[k]
					end
				end
				feed = nil
			else
				if flapRig and not feed.FlapDone then
					local open
					if t < FLAP_TIMES[1] then
						open = Smooth(t / FLAP_TIMES[1])
					elseif t < FLAP_TIMES[2] then
						open = 1
					else
						open = 1 - Smooth((t - FLAP_TIMES[2]) / (FLAP_TIMES[3] - FLAP_TIMES[2]))
						if t >= FLAP_TIMES[3] then
							feed.FlapDone = true
							if t - FLAP_TIMES[3] < 0.3 then Play(click, 0.9) end -- not for a close long past (late / waking client)
						end
					end
					local cf = flapRig.Pivot * CFrame.Angles(FLAP_OPEN * open, 0, 0)
					for k, part in ipairs(flapRig.Parts) do
						n += 1
						moveParts[n] = part
						moveCFrames[n] = cf * flapRig.Rel[k]
					end
				end
				for i, flake in ipairs(feed.Flakes) do
					local part = flakeParts[i]
					local eaten = flake.Eat and t >= flake.Eat
					if t < flake.Drop or eaten then
						part.Transparency = 1
						if eaten and not feed.Eaten[i] then
							feed.Eaten[i] = true
							if t - flake.Eat < 0.5 then
								gulpAt.Position = FlakeTrack(flake, t) * scale
								gulp:Emit(3)
								if os.clock() - lastGulp > 0.15 then
									lastGulp = os.clock()
									Play(gulpSound, 1.6 + math.random() * 0.5)
								end
							end
						end
					else
						local p = FlakeTrack(flake, t)
						if t >= flake.Drop + FALL_TIME and not feed.Landed[i] then
							feed.Landed[i] = true
							if t - (flake.Drop + FALL_TIME) < 0.4 then -- not when catching up on a feeding already under way
								ringAt.Position = Vector3.new(p.X, surfaceY + 0.02, p.Z) * scale
								ring:Emit(1)
								if not feed.Rang then
									feed.Rang = true
									Play(splash)
								end
							end
						end
						local fade = (not flake.Eat and t > FEED_TIME - 1) and (t - (FEED_TIME - 1)) or 0
						part.Transparency = fade
						n += 1
						moveParts[n] = part
						moveCFrames[n] = World(p + Vector3.new(0, FLAKE_SIZE.Y * 0.5, 0)) * CFrame.Angles(flake.Tilt, flake.Spin * t, 0)
					end
				end
			end
		end

		for i = #moveParts, n + 1, -1 do
			moveParts[i] = nil
			moveCFrames[i] = nil
		end
		if n > 0 then workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged) end
	end)

	--..Cleanup: every moved build part back at rest where the build is now..--
	return function()
		if not (posed and model:IsDescendantOf(workspace) and hitbox.Parent) then return end
		local now = hitbox.CFrame
		for part, rel in pairs(rest) do
			if part.Parent then part.CFrame = now * rel end
		end
	end
end

return B
]======]
SOURCES['S_Aquarium'] = [======[
--[[
	Aquarium  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package HomeDecor
	Server half of the fish tank (client half: ReplicatedStorage.FunBehavioursClient.Aquarium; fun-builds/CONTRACT.md).
	  * a "Feed fish" prompt on the tank's feed flap (FeedFlap, top front of the tank). Anyone may feed the fish
	    (it can't grief anybody); one feeding at a time: while the fish are still eating (FEED_COOLDOWN s) the
	    prompt reads "Fish are eating..." and presses are ignored
	  * Fun_FedAt (number) = the server time (Kit.Now) of the last feeding. That is the whole shared state: every
	    client computes the same show from it - the flap opening, the 12 flakes (seeded by Fun_FedAt), which fish
	    eats which flake and when - so a player streaming in half-way sees the same moment as everyone else
	Everything else (5 swimming fish, bubbles, the chest lid, swaying plants, the tank light) is client-only and
	driven by the server clock. No economy impact.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage.Modules.FunBuildKit)

--..Config..--
local PROMPT_DISTANCE = 10
local FEED_COOLDOWN = 7    -- s: the client show lasts ~6.5 s (Aquarium client FEED_TIME)
local ACTION_TEXT = "Feed fish"
local BUSY_TEXT = "Fish are eating..."

local B = {}

--..Behaviour..--
function B.Server(model, ctx)
	local flap = Kit.Part(model, "FeedFlap") or Kit.Hitbox(model)
	if not flap then return end
	local prompt = ctx:Prompt(flap, {
		Name = "FeedPrompt",
		Action = ACTION_TEXT,
		Object = tostring(model:GetAttribute("DisplayName") or "Aquarium"),
		Distance = PROMPT_DISTANCE,
	})

	local feeding = 0 -- counts feedings so a stale "busy" timer never resets a newer one
	ctx:Connect(prompt.Triggered, function(player)
		if not ctx:HumanoidOf(player) then return end
		local now = Kit.Now()
		local last = ctx:GetState("FedAt")
		if type(last) == "number" and now - last < FEED_COOLDOWN then return end
		ctx:SetState("FedAt", now)
		feeding += 1
		local mine = feeding
		prompt.ActionText = BUSY_TEXT
		task.delay(FEED_COOLDOWN, function()
			if ctx:Alive() and feeding == mine and prompt.Parent then prompt.ActionText = ACTION_TEXT end
		end)
	end)
end

return B
]======]
SOURCES['C_PottedPlant'] = [======[
--[[
	PottedPlant  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package HomeDecor
	Client-only behaviour for the monstera pot plant (no server half: nothing is shared but the clock).
	  * every frond (Frond<N>Stem / LeafL / LeafR / Rib, and the rolled new leaf Frond0Spike) sways gently about
	    its stem's base in the soil (Pivot_Frond<N>): two slow sines per frond with their own phases, under a
	    breeze that swells and fades every ~11 s. Tall fronds move most at the tip (they pivot at the soil).
	    Driven by Kit.Now(), so every client sees the same sway.
	Cheap: one ctx:Step at <= 30 Hz, posed with a single BulkMoveTo, asleep beyond StepRange. Cleanup puts every
	frond back at rest relative to the build's CURRENT hitbox.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local AMP = math.rad(1.8)        -- sway each side (about the soil)
local PERIOD_A, PERIOD_B = 3.9, 5.6
local BREEZE_PERIOD = 11         -- s: the breeze swells and fades
local BREEZE = 0.45              -- how much it adds at its strongest
local HZ = 30

local B = {}
B.StepRange = 90

--..Helpers..--
local function SameCFrame(a, b)
	return (a.Position - b.Position).Magnitude < 1e-3 and a.LookVector:Dot(b.LookVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local home = hitbox.CFrame
	local rotation = Kit.Origin(model).Rotation
	local seed = (home.Position.X * 0.37 + home.Position.Z * 0.61) % 6.283

	--..Fronds: parts grouped by Frond<N>, each rigged about its Pivot_Frond<N>..--
	local groups = {}
	for _, part in ipairs(Kit.Parts(model, "Frond")) do
		local n = tonumber(part.Name:match("^Frond(%d+)"))
		if n then
			groups[n] = groups[n] or {}
			table.insert(groups[n], part)
		end
	end
	local parts, rel, pivots, phases, rest = {}, {}, {}, {}, {}
	for n, list in pairs(groups) do
		local base = Kit.Pivot(model, "Frond" .. n)
		if base then
			local pivot = CFrame.new(base) * rotation
			for _, part in ipairs(list) do
				table.insert(parts, part)
				table.insert(rel, pivot:ToObjectSpace(part.CFrame))
				table.insert(pivots, pivot)
				table.insert(phases, n * 1.37 + seed)
				rest[part] = home:ToObjectSpace(part.CFrame)
			end
		end
	end
	if #parts == 0 then return end

	--..Step..--
	local cfs = {}
	local last, posed = -math.huge, false
	local wa, wb, wz = 2 * math.pi / PERIOD_A, 2 * math.pi / PERIOD_B, 2 * math.pi / BREEZE_PERIOD
	ctx:Step(function(_, now)
		if not (hitbox.Parent and SameCFrame(hitbox.CFrame, home)) then return end -- moved: the restart is on its way
		local c = os.clock()
		if c - last < 1 / HZ then return end
		last = c
		posed = true
		local breeze = 1 + BREEZE * (0.5 + 0.5 * math.sin(wz * now + seed))
		for i, part in ipairs(parts) do
			local p = phases[i]
			local ax = AMP * breeze * math.sin(wa * now + p)
			local az = AMP * 0.7 * breeze * math.sin(wb * now + p * 1.9)
			cfs[i] = pivots[i] * CFrame.Angles(ax, 0, az) * rel[i]
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)

	--..Cleanup: at rest where the build is now..--
	return function()
		if not (posed and model:IsDescendantOf(workspace) and hitbox.Parent) then return end
		local now = hitbox.CFrame
		for part, r in pairs(rest) do
			if part.Parent then part.CFrame = now * r end
		end
	end
end

return B
]======]
MODELS = {}
MODELS['Aquarium'] = {Min = Vector3.new(-3.3, 0.0, -1.68), Max = Vector3.new(3.3, 7.38, 1.5), Attrs = {Pivot_Castle = Vector3.new(-1.55, 3.7332, 0.66), Pivot_Flag = Vector3.new(-2.08, 5.5832, 0.66), Pivot_ChestHinge = Vector3.new(1.72, 3.99, -0.13), Pivot_Bubbler = Vector3.new(1.72, 4.02, -0.66), Pivot_Plant1 = Vector3.new(2.35, 3.8165, 0.78), Pivot_Plant2 = Vector3.new(-2.55, 3.8552, 0.92), Pivot_Plant3 = Vector3.new(0.62, 3.8497, 0.9), Pivot_Plant4 = Vector3.new(-2.5, 3.57, -0.82), Pivot_Light = Vector3.new(0.0, 5.97, 0.3), Pivot_FeedHinge = Vector3.new(0.0, 6.45, -0.18), Pivot_Feed = Vector3.new(0.0, 5.94, -0.745), Pivot_TankMin = Vector3.new(-2.9, 3.62, -1.2), Pivot_TankMax = Vector3.new(2.9, 5.94, 1.2), Pivot_WaterSurface = Vector3.new(0.0, 5.94, 0.0), Cost = 1500, DisplayName = "Aquarium", Notes = "Fish tank on a wooden cabinet (primlib parts, fun-builds HomeDecor). The client swims 5 runtime fish inside Pivot_TankMin/Max, bubbles rise from the treasure chest (Pivot_Bubbler, ChestLid pops), Plant<N>Leaf<M> sway about Pivot_Plant<N>, the TankLight glows; prompt 'Feed fish' opens the FeedFlap and sprinkles flakes on the water - the fish rush up to them. Built by fun-builds/models/build_Aquarium.py."}, Parts = {
	{Name = 'Plinth', Shape = 'Block', Size = Vector3.new(6.2, 0.42, 2.7), CF = {0.0, 0.21, 0.02, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'Carcass', Shape = 'Block', Size = Vector3.new(6.4, 2.45, 2.8), CF = {0.0, 1.625, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'CabinetTop', Shape = 'Block', Size = Vector3.new(6.6, 0.2, 3.0), CF = {0.0, 2.95, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'CabinetLip', Shape = 'Cylinder', Size = Vector3.new(6.6, 0.22, 0.22), CF = {0.0, 2.95, -1.5, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'DoorL', Shape = 'Block', Size = Vector3.new(2.94, 2.06, 0.1), CF = {1.56, 1.63, -1.44, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'DoorPanelL', Shape = 'Block', Size = Vector3.new(2.3, 1.44, 0.05), CF = {1.56, 1.63, -1.495, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'KnobL', Shape = 'Ball', Size = Vector3.new(0.24, 0.24, 0.24), CF = {0.3, 1.74, -1.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'DoorR', Shape = 'Block', Size = Vector3.new(2.94, 2.06, 0.1), CF = {-1.56, 1.63, -1.44, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'DoorPanelR', Shape = 'Block', Size = Vector3.new(2.3, 1.44, 0.05), CF = {-1.56, 1.63, -1.495, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'KnobR', Shape = 'Ball', Size = Vector3.new(0.24, 0.24, 0.24), CF = {-0.3, 1.74, -1.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'TankBase', Shape = 'Block', Size = Vector3.new(6.04, 0.27, 2.64), CF = {0.0, 3.165, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'Post1', Shape = 'Block', Size = Vector3.new(0.14, 2.95, 0.14), CF = {2.95, 4.75, -1.25, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'Post2', Shape = 'Block', Size = Vector3.new(0.14, 2.95, 0.14), CF = {-2.95, 4.75, -1.25, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'Post3', Shape = 'Block', Size = Vector3.new(0.14, 2.95, 0.14), CF = {2.95, 4.75, 1.25, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'Post4', Shape = 'Block', Size = Vector3.new(0.14, 2.95, 0.14), CF = {-2.95, 4.75, 1.25, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'RimFront', Shape = 'Block', Size = Vector3.new(6.04, 0.2, 0.14), CF = {0.0, 6.32, -1.25, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'RimBack', Shape = 'Block', Size = Vector3.new(6.04, 0.2, 0.14), CF = {0.0, 6.32, 1.25, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'RimL', Shape = 'Block', Size = Vector3.new(0.14, 0.2, 2.64), CF = {2.95, 6.32, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'RimR', Shape = 'Block', Size = Vector3.new(0.14, 0.2, 2.64), CF = {-2.95, 6.32, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'GlassFront', Shape = 'Block', Size = Vector3.new(5.8, 2.94, 0.06), CF = {0.0, 4.76, -1.25, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.86, Collide = true},
	{Name = 'GlassL', Shape = 'Block', Size = Vector3.new(0.06, 2.94, 2.4), CF = {2.95, 4.76, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.86, Collide = true},
	{Name = 'GlassR', Shape = 'Block', Size = Vector3.new(0.06, 2.94, 2.4), CF = {-2.95, 4.76, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.86, Collide = true},
	{Name = 'Backdrop', Shape = 'Block', Size = Vector3.new(5.8, 2.94, 0.06), CF = {0.0, 4.76, 1.25, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'BackdropReef', Shape = 'Ellipsoid', Size = Vector3.new(5.74, 2.1, 0.06), CF = {0.0, 4.05, 1.2, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'Water', Shape = 'Block', Size = Vector3.new(5.8, 2.64, 2.4), CF = {0.0, 4.62, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.64, Collide = false},
	{Name = 'WaterTop', Shape = 'Block', Size = Vector3.new(5.78, 0.05, 2.38), CF = {0.0, 5.94, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.72, Collide = false},
	{Name = 'Gravel', Shape = 'Block', Size = Vector3.new(5.78, 0.34, 2.38), CF = {0.0, 3.45, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'GravelSlope', Shape = 'Wedge', Size = Vector3.new(5.78, 0.36, 1.3), CF = {0.0, 3.78, 0.54, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'PebblePink', Shape = 'Ball', Size = Vector3.new(0.18, 0.18, 0.18), CF = {-0.95, 3.665, -0.92, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PebbleBlue', Shape = 'Ball', Size = Vector3.new(0.16, 0.16, 0.16), CF = {0.35, 3.66, -0.78, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PebbleYellow', Shape = 'Ball', Size = Vector3.new(0.17, 0.17, 0.17), CF = {1.05, 3.6625, -1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PebbleWhite', Shape = 'Ball', Size = Vector3.new(0.15, 0.15, 0.15), CF = {-1.7, 3.6575, -0.62, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleKeep', Shape = 'Block', Size = Vector3.new(0.82, 0.9, 0.52), CF = {-1.55, 4.18323, 0.66, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleCrenel1', Shape = 'Block', Size = Vector3.new(0.17, 0.16, 0.3), CF = {-1.85, 4.70323, 0.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleCrenel2', Shape = 'Block', Size = Vector3.new(0.17, 0.16, 0.3), CF = {-1.55, 4.70323, 0.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleCrenel3', Shape = 'Block', Size = Vector3.new(0.17, 0.16, 0.3), CF = {-1.25, 4.70323, 0.56, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleTowerL', Shape = 'Block', Size = Vector3.new(0.5, 1.22, 0.5), CF = {-2.08, 4.34323, 0.66, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleRoofL1', Shape = 'CornerWedge', Size = Vector3.new(0.32, 0.44, 0.32), CF = {-2.24, 5.15323, 0.82, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleRoofL2', Shape = 'CornerWedge', Size = Vector3.new(0.32, 0.44, 0.32), CF = {-1.92, 5.15323, 0.82, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, T = 0.0, Collide = false},
	{Name = 'CastleRoofL3', Shape = 'CornerWedge', Size = Vector3.new(0.32, 0.44, 0.32), CF = {-1.92, 5.15323, 0.5, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0}, T = 0.0, Collide = false},
	{Name = 'CastleRoofL4', Shape = 'CornerWedge', Size = Vector3.new(0.32, 0.44, 0.32), CF = {-2.24, 5.15323, 0.5, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, T = 0.0, Collide = false},
	{Name = 'CastleTowerR', Shape = 'Block', Size = Vector3.new(0.44, 1.06, 0.44), CF = {-1.02, 4.26323, 0.66, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleRoofR1', Shape = 'CornerWedge', Size = Vector3.new(0.29, 0.44, 0.29), CF = {-1.165, 4.99323, 0.805, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleRoofR2', Shape = 'CornerWedge', Size = Vector3.new(0.29, 0.44, 0.29), CF = {-0.875, 4.99323, 0.805, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0}, T = 0.0, Collide = false},
	{Name = 'CastleRoofR3', Shape = 'CornerWedge', Size = Vector3.new(0.29, 0.44, 0.29), CF = {-0.875, 4.99323, 0.515, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.0, 0.0, -1.0}, T = 0.0, Collide = false},
	{Name = 'CastleRoofR4', Shape = 'CornerWedge', Size = Vector3.new(0.29, 0.44, 0.29), CF = {-1.165, 4.99323, 0.515, -0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -0.0}, T = 0.0, Collide = false},
	{Name = 'CastlePole', Shape = 'Cylinder', Size = Vector3.new(0.38, 0.05, 0.05), CF = {-2.08, 5.48323, 0.66, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = false},
	{Name = 'CastleFlag', Shape = 'Block', Size = Vector3.new(0.3, 0.17, 0.05), CF = {-1.92, 5.58323, 0.66, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleDoor', Shape = 'Block', Size = Vector3.new(0.3, 0.34, 0.05), CF = {-1.55, 4.00323, 0.39, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CastleDoorArch', Shape = 'Cylinder', Size = Vector3.new(0.06, 0.3, 0.3), CF = {-1.55, 4.17323, 0.39, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -0.0, 0.0}, T = 0.0, Collide = false},
	{Name = 'CastleWindow', Shape = 'Block', Size = Vector3.new(0.1, 0.18, 0.05), CF = {-2.08, 4.53323, 0.4, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'ChestBody', Shape = 'Block', Size = Vector3.new(0.72, 0.4, 0.46), CF = {1.72, 3.79, -0.36, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'ChestBand', Shape = 'Block', Size = Vector3.new(0.74, 0.08, 0.48), CF = {1.72, 3.86, -0.36, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'ChestLock', Shape = 'Block', Size = Vector3.new(0.12, 0.15, 0.05), CF = {1.72, 3.89, -0.61, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'ChestGold', Shape = 'Ellipsoid', Size = Vector3.new(0.6, 0.16, 0.36), CF = {1.72, 3.99, -0.36, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'ChestLid', Shape = 'Block', Size = Vector3.new(0.76, 0.14, 0.48), CF = {1.72, 4.15157, -0.32078, 1.0, 0.0, 0.0, 0.0, 0.91355, -0.40674, 0.0, 0.40674, 0.91355}, T = 0.0, Collide = false},
	{Name = 'RockBack', Shape = 'Ellipsoid', Size = Vector3.new(0.75, 0.42, 0.5), CF = {0.05, 3.82277, 0.55, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'RockFront', Shape = 'Ellipsoid', Size = Vector3.new(0.52, 0.36, 0.44), CF = {2.45, 3.7, -0.72, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'Plant1Leaf1', Shape = 'Ellipsoid', Size = Vector3.new(0.26, 2.0, 0.07), CF = {2.19962, 4.80127, 0.69318, 0.5, -0.15038, 0.85287, 0.0, 0.98481, 0.17365, -0.86603, -0.08682, 0.4924}, T = 0.0, Collide = false},
	{Name = 'Plant1Leaf2', Shape = 'Ellipsoid', Size = Vector3.new(0.24, 1.75, 0.07), CF = {2.2776, 4.66547, 0.58108, 0.93969, -0.08274, 0.33186, 0.0, 0.9703, 0.24192, -0.34202, -0.22733, 0.91178}, T = 0.0, Collide = false},
	{Name = 'Plant1Leaf3', Shape = 'Ellipsoid', Size = Vector3.new(0.26, 1.95, 0.07), CF = {2.09746, 4.75369, 0.87192, -0.34202, -0.25901, 0.90329, 0.0, 0.96126, 0.27564, -0.93969, 0.09427, -0.32877}, T = 0.0, Collide = false},
	{Name = 'Plant1Leaf4', Shape = 'Ellipsoid', Size = Vector3.new(0.24, 1.45, 0.07), CF = {2.29955, 4.53441, 0.86738, -0.86603, -0.06959, 0.49513, 0.0, 0.99027, 0.13917, -0.5, 0.12053, -0.8576}, T = 0.0, Collide = false},
	{Name = 'Plant1Leaf5', Shape = 'Ellipsoid', Size = Vector3.new(0.25, 1.6, 0.07), CF = {2.40204, 4.55821, 0.48487, 0.98481, 0.06505, -0.161, 0.0, 0.92718, 0.37461, 0.17365, -0.36892, 0.9131}, T = 0.0, Collide = false},
	{Name = 'Plant2Leaf1', Shape = 'Ellipsoid', Size = Vector3.new(0.26, 2.05, 0.07), CF = {-2.42646, 4.87026, 0.84867, 0.5, 0.12053, -0.8576, 0.0, 0.99027, 0.13917, 0.86603, -0.06959, 0.49513}, T = 0.0, Collide = false},
	{Name = 'Plant2Leaf2', Shape = 'Ellipsoid', Size = Vector3.new(0.24, 1.8, 0.07), CF = {-2.44516, 4.72037, 0.69517, 0.90631, 0.11649, -0.40625, 0.0, 0.96126, 0.27564, 0.42262, -0.24981, 0.8712}, T = 0.0, Collide = false},
	{Name = 'Plant2Leaf3', Shape = 'Ellipsoid', Size = Vector3.new(0.25, 1.6, 0.07), CF = {-2.36813, 4.63147, 0.98619, -0.34202, 0.22733, -0.91178, 0.0, 0.9703, 0.24192, 0.93969, 0.08274, -0.33186}, T = 0.0, Collide = false},
	{Name = 'Plant2Leaf4', Shape = 'Ellipsoid', Size = Vector3.new(0.24, 1.3, 0.07), CF = {-2.26939, 4.43945, 0.87052, 0.17365, 0.43171, -0.88514, 0.0, 0.89879, 0.43837, 0.98481, -0.07612, 0.15607}, T = 0.0, Collide = false},
	{Name = 'Plant3Leaf1', Shape = 'Ellipsoid', Size = Vector3.new(0.36, 1.25, 0.07), CF = {0.50926, 4.45048, 0.76803, 0.76604, -0.17718, 0.61789, 0.0, 0.96126, 0.27564, -0.64279, -0.21115, 0.73637}, T = 0.0, Collide = false},
	{Name = 'Plant3Leaf2', Shape = 'Ellipsoid', Size = Vector3.new(0.34, 1.05, 0.07), CF = {0.70978, 4.34303, 0.7445, 0.86603, 0.17101, -0.46985, 0.0, 0.93969, 0.34202, 0.5, -0.2962, 0.8138}, T = 0.0, Collide = false},
	{Name = 'Plant3Leaf3', Shape = 'Ellipsoid', Size = Vector3.new(0.36, 1.4, 0.07), CF = {0.61362, 4.54586, 0.82711, 0.99619, -0.00911, 0.08668, 0.0, 0.99452, 0.10453, -0.08716, -0.10413, 0.99074}, T = 0.0, Collide = false},
	{Name = 'Plant3Leaf4', Shape = 'Ellipsoid', Size = Vector3.new(0.32, 0.9, 0.07), CF = {0.53571, 4.26692, 1.04599, -0.86603, -0.1873, 0.46359, 0.0, 0.92718, 0.37461, -0.5, 0.32442, -0.80296}, T = 0.0, Collide = false},
	{Name = 'Plant4Leaf1', Shape = 'Ellipsoid', Size = Vector3.new(0.28, 0.72, 0.07), CF = {-2.40366, 3.91238, -0.87562, 0.5, 0.26762, -0.82364, 0.0, 0.95106, 0.30902, 0.86603, -0.15451, 0.47553}, T = 0.0, Collide = false},
	{Name = 'Plant4Leaf2', Shape = 'Ellipsoid', Size = Vector3.new(0.26, 0.6, 0.07), CF = {-2.52119, 3.84406, -0.94017, 0.98481, -0.07063, 0.15864, 0.0, 0.91355, 0.40674, -0.17365, -0.40056, 0.89967}, T = 0.0, Collide = false},
	{Name = 'Plant4Leaf3', Shape = 'Ellipsoid', Size = Vector3.new(0.26, 0.55, 0.07), CF = {-2.42108, 3.82498, -0.75378, -0.64279, 0.28697, -0.71026, 0.0, 0.92718, 0.37461, 0.76604, 0.24079, -0.59598}, T = 0.0, Collide = false},
	{Name = 'Hood', Shape = 'Block', Size = Vector3.new(6.08, 0.3, 1.41), CF = {0.0, 6.55, 0.625, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'HoodNose', Shape = 'Cylinder', Size = Vector3.new(6.08, 0.3, 0.3), CF = {0.0, 6.55, -0.08, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'HoodStripe', Shape = 'Block', Size = Vector3.new(5.74, 0.05, 0.14), CF = {0.0, 6.71, 0.5, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'TankLight', Shape = 'Block', Size = Vector3.new(5.6, 0.1, 0.3), CF = {0.0, 6.17, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'CoverL', Shape = 'Block', Size = Vector3.new(2.36, 0.05, 1.13), CF = {1.81, 6.44, -0.745, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.78, Collide = true},
	{Name = 'CoverR', Shape = 'Block', Size = Vector3.new(2.36, 0.05, 1.13), CF = {-1.81, 6.44, -0.745, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.78, Collide = true},
	{Name = 'FeedFlap', Shape = 'Block', Size = Vector3.new(1.22, 0.06, 1.13), CF = {0.0, 6.45, -0.745, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'FeedFlapTab', Shape = 'Block', Size = Vector3.new(0.36, 0.06, 0.14), CF = {0.0, 6.47, -1.36, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'FoodTub', Shape = 'Cylinder', Size = Vector3.new(0.58, 0.54, 0.54), CF = {2.25, 6.97, 0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = false},
	{Name = 'FoodLabel', Shape = 'Cylinder', Size = Vector3.new(0.26, 0.56, 0.56), CF = {2.25, 6.95, 0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = false},
	{Name = 'FoodLid', Shape = 'Cylinder', Size = Vector3.new(0.14, 0.6, 0.6), CF = {2.25, 7.31, 0.62, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = false},
}}
MODELS['PottedPlant'] = {Min = Vector3.new(-2.095, 0.0, -2.094), Max = Vector3.new(1.878, 6.226, 2.017), Attrs = {Pivot_Frond1 = Vector3.new(0.0, 2.37, -0.1), Pivot_Frond2 = Vector3.new(-0.0771, 2.37, 0.0919), Pivot_Frond3 = Vector3.new(0.1128, 2.37, 0.041), Pivot_Frond4 = Vector3.new(-0.1088, 2.37, -0.0507), Pivot_Frond5 = Vector3.new(0.0311, 2.37, 0.1159), Pivot_Frond6 = Vector3.new(0.0983, 2.37, -0.0688), Pivot_Frond7 = Vector3.new(-0.0966, 2.37, 0.0259), Pivot_Frond8 = Vector3.new(0.0707, 2.37, 0.0707), Pivot_Frond9 = Vector3.new(0.0259, 2.37, -0.0966), Pivot_Frond10 = Vector3.new(-0.0259, 2.37, 0.0966), Pivot_Frond11 = Vector3.new(-0.0574, 2.37, -0.0819), Pivot_Frond0 = Vector3.new(0.05, 2.42, 0.05), Cost = 200, DisplayName = "Potted Plant", Notes = "Monstera in a glazed pot (primlib parts, fun-builds HomeDecor). The client sways each Frond<N>* group gently about Pivot_Frond<N>. Built by fun-builds/models/build_PottedPlant.py."}, Parts = {
	{Name = 'Saucer', Shape = 'Cylinder', Size = Vector3.new(0.14, 2.0, 2.0), CF = {0.0, 0.07, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = true},
	{Name = 'SaucerLip', Shape = 'Cylinder', Size = Vector3.new(0.1, 2.08, 2.08), CF = {0.0, 0.15, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = false},
	{Name = 'PotFoot', Shape = 'Cylinder', Size = Vector3.new(0.24, 1.42, 1.42), CF = {0.0, 0.24, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = true},
	{Name = 'PotBelly', Shape = 'Ellipsoid', Size = Vector3.new(2.5, 2.0, 2.5), CF = {0.0, 1.25, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = true},
	{Name = 'PotBand', Shape = 'Cylinder', Size = Vector3.new(0.2, 2.54, 2.54), CF = {0.0, 1.25, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = false},
	{Name = 'PotBandLow', Shape = 'Cylinder', Size = Vector3.new(0.1, 2.0585, 2.0585), CF = {0.0, 0.66, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = false},
	{Name = 'PotDot1', Shape = 'Ball', Size = Vector3.new(0.18, 0.18, 0.18), CF = {0.40564, 1.78, 0.97931, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PotDot2', Shape = 'Ball', Size = Vector3.new(0.18, 0.18, 0.18), CF = {0.97931, 1.78, 0.40564, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PotDot3', Shape = 'Ball', Size = Vector3.new(0.18, 0.18, 0.18), CF = {0.97931, 1.78, -0.40564, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PotDot4', Shape = 'Ball', Size = Vector3.new(0.18, 0.18, 0.18), CF = {0.40564, 1.78, -0.97931, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PotDot5', Shape = 'Ball', Size = Vector3.new(0.18, 0.18, 0.18), CF = {-0.40564, 1.78, -0.97931, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PotDot6', Shape = 'Ball', Size = Vector3.new(0.18, 0.18, 0.18), CF = {-0.97931, 1.78, -0.40564, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PotDot7', Shape = 'Ball', Size = Vector3.new(0.18, 0.18, 0.18), CF = {-0.97931, 1.78, 0.40564, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PotDot8', Shape = 'Ball', Size = Vector3.new(0.18, 0.18, 0.18), CF = {-0.40564, 1.78, 0.97931, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'PotNeck', Shape = 'Cylinder', Size = Vector3.new(0.34, 1.9, 1.9), CF = {0.0, 2.17, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = true},
	{Name = 'PotLip', Shape = 'Cylinder', Size = Vector3.new(0.14, 2.08, 2.08), CF = {0.0, 2.37, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = true},
	{Name = 'Soil', Shape = 'Cylinder', Size = Vector3.new(0.09, 1.84, 1.84), CF = {0.0, 2.425, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0}, T = 0.0, Collide = false},
	{Name = 'SoilPebble1', Shape = 'Ellipsoid', Size = Vector3.new(0.26, 0.14, 0.2), CF = {0.52, 2.49, -0.4, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'SoilPebble2', Shape = 'Ellipsoid', Size = Vector3.new(0.22, 0.12, 0.2), CF = {-0.45, 2.49, 0.5, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}, T = 0.0, Collide = false},
	{Name = 'Frond1Stem', Shape = 'Cylinder', Size = Vector3.new(2.3195, 0.11, 0.11), CF = {0.0, 3.52, -0.25, 0.0, 0.0, 1.0, 0.9916, 0.12934, -0.0, -0.12934, 0.9916, 0.0}, T = 0.0, Collide = false},
	{Name = 'Frond1LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.9088, 0.06, 1.6), CF = {0.24309, 5.40231, -0.7316, 0.90594, -0.30902, 0.28945, 0.41075, 0.47553, -0.77792, 0.10275, 0.82364, 0.55773}, T = 0.0, Collide = false},
	{Name = 'Frond1LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.9088, 0.06, 1.6), CF = {-0.24309, 5.40231, -0.7316, 0.90594, 0.30902, -0.28945, -0.41075, 0.47553, -0.77792, -0.10275, 0.82364, 0.55773}, T = 0.0, Collide = false},
	{Name = 'Frond1Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.28), CF = {0.0, 5.26447, -0.71435, 1.0, 0.0, 0.0, 0.0, 0.5, -0.86603, 0.0, 0.86603, 0.5}, T = 0.0, Collide = false},
	{Name = 'Frond2Stem', Shape = 'Cylinder', Size = Vector3.new(2.1737, 0.11, 0.11), CF = {-0.17998, 3.445, 0.21449, -0.09463, 0.01074, 0.99545, 0.9891, -0.11226, 0.09524, 0.11277, 0.99362, -0.0}, T = 0.0, Collide = false},
	{Name = 'Frond2LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.9344, 0.06, 1.65), CF = {-0.7357, 5.24238, 0.48794, -0.65105, 0.73749, 0.17955, 0.41751, 0.5455, -0.72671, -0.63389, -0.39816, -0.66306}, T = 0.0, Collide = false},
	{Name = 'Frond2LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.9344, 0.06, 1.65), CF = {-0.35277, 5.24238, 0.80925, -0.73731, 0.26405, 0.62181, -0.41751, 0.5455, -0.72671, -0.53109, -0.79543, -0.29196}, T = 0.0, Collide = false},
	{Name = 'Frond2Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.32), CF = {-0.52516, 5.10201, 0.62587, -0.76604, 0.52654, 0.36869, 0.0, 0.57358, -0.81915, -0.64279, -0.62751, -0.43938}, T = 0.0, Collide = false},
	{Name = 'Frond3Stem', Shape = 'Cylinder', Size = Vector3.new(1.9794, 0.11, 0.11), CF = {0.27251, 3.345, 0.09919, 0.16141, -0.0095, 0.98684, 0.98514, -0.05797, -0.16169, 0.05875, 0.99827, 0.0}, T = 0.0, Collide = false},
	{Name = 'Frond3LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.9472, 0.06, 1.65), CF = {0.79013, 4.99919, 0.5601, -0.31607, -0.59769, -0.7368, 0.404, 0.61789, -0.67454, 0.85842, -0.51087, 0.04617}, T = 0.0, Collide = false},
	{Name = 'Frond3LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.9472, 0.06, 1.65), CF = {0.9653, 4.99919, 0.07883, -0.30965, -0.78623, -0.53474, -0.404, 0.61789, -0.67454, 0.86075, 0.00716, -0.50897}, T = 0.0, Collide = false},
	{Name = 'Frond3Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.32), CF = {0.83285, 4.86694, 0.30313, -0.34202, -0.71985, -0.60402, 0.0, 0.64279, -0.76604, 0.93969, -0.262, -0.21985}, T = 0.0, Collide = false},
	{Name = 'Frond4Stem', Shape = 'Cylinder', Size = Vector3.new(1.6888, 0.11, 0.11), CF = {-0.27189, 3.195, -0.12679, -0.1932, 0.88548, 0.42262, 0.97702, 0.21317, 0.0, -0.09009, 0.4129, -0.90631}, T = 0.0, Collide = false},
	{Name = 'Frond4LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.96, 0.06, 1.7), CF = {-0.8527, 4.64407, -0.68399, 0.34259, 0.46646, 0.8155, 0.3978, 0.71436, -0.57572, -0.85111, 0.52164, 0.05918}, T = 0.0, Collide = false},
	{Name = 'Frond4LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.96, 0.06, 1.7), CF = {-1.07207, 4.64407, -0.21354, 0.43177, 0.69944, 0.56953, -0.3978, 0.71436, -0.57572, -0.80952, 0.02202, 0.58667}, T = 0.0, Collide = false},
	{Name = 'Frond4Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.36), CF = {-0.90076, 4.51634, -0.42003, 0.42262, 0.60644, 0.67352, 0.0, 0.74314, -0.66913, -0.90631, 0.28279, 0.31407}, T = 0.0, Collide = false},
	{Name = 'Frond5Stem', Shape = 'Cylinder', Size = Vector3.new(1.5426, 0.11, 0.11), CF = {0.07765, 3.12, 0.28978, 0.0604, -0.25167, -0.96593, 0.97239, 0.23337, 0.0, 0.22542, -0.93925, 0.25882}, T = 0.0, Collide = false},
	{Name = 'Frond5LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.96, 0.06, 1.7), CF = {0.03504, 4.45196, 1.13355, -0.86505, 0.11307, -0.48878, 0.3934, 0.75748, -0.52101, 0.31133, -0.64299, -0.69975}, T = 0.0, Collide = false},
	{Name = 'Frond5LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.96, 0.06, 1.7), CF = {0.53643, 4.45196, 0.9992, -0.90482, -0.41942, 0.07342, -0.3934, 0.75748, -0.52101, 0.16291, -0.50031, -0.85039}, T = 0.0, Collide = false},
	{Name = 'Frond5Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.36), CF = {0.26587, 4.32928, 0.99225, -0.96593, -0.15934, -0.20395, 0.0, 0.78801, -0.61566, 0.25882, -0.59468, -0.76116}, T = 0.0, Collide = false},
	{Name = 'Frond6Stem', Shape = 'Cylinder', Size = Vector3.new(1.3544, 0.11, 0.11), CF = {0.25394, 3.02, -0.17781, 0.22983, -0.78625, 0.57358, 0.95983, 0.28057, -0.0, -0.16093, 0.55054, 0.81915}, T = 0.0, Collide = false},
	{Name = 'Frond6LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.9344, 0.06, 1.65), CF = {1.11506, 4.13756, -0.46948, 0.65119, -0.53617, -0.5371, 0.35139, 0.8403, -0.41282, 0.67267, 0.0801, 0.7356}, T = 0.0, Collide = false},
	{Name = 'Frond6LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.9344, 0.06, 1.65), CF = {0.82254, 4.13756, -0.88724, 0.40938, -0.25865, -0.87493, -0.35139, 0.8403, -0.41282, 0.84198, 0.47644, 0.25311}, T = 0.0, Collide = false},
	{Name = 'Frond6Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.32), CF = {0.89096, 4.03815, -0.62385, 0.57358, -0.40958, -0.70941, 0.0, 0.86603, -0.5, 0.81915, 0.28679, 0.49673}, T = 0.0, Collide = false},
	{Name = 'Frond7Stem', Shape = 'Cylinder', Size = Vector3.new(1.1166, 0.11, 0.11), CF = {-0.28012, 2.895, 0.07506, -0.32871, 0.90827, -0.25882, 0.94032, 0.3403, 0.0, 0.08808, -0.24337, -0.96593}, T = 0.0, Collide = false},
	{Name = 'Frond7LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.9088, 0.06, 1.6), CF = {-1.23354, 3.75172, 0.07377, -0.43933, 0.38317, 0.81251, 0.32064, 0.91178, -0.25661, -0.83915, 0.14779, -0.52343}, T = 0.0, Collide = false},
	{Name = 'Frond7LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.9088, 0.06, 1.6), CF = {-1.10517, 3.75172, 0.55288, -0.0391, 0.25794, 0.96537, -0.32064, 0.91178, -0.25661, -0.94639, -0.31957, 0.04705}, T = 0.0, Collide = false},
	{Name = 'Frond7Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.28), CF = {-1.06534, 3.67333, 0.28546, -0.25882, 0.33037, 0.90767, 0.0, 0.93969, -0.34202, -0.96593, -0.08852, -0.24321}, T = 0.0, Collide = false},
	{Name = 'Frond8Stem', Shape = 'Cylinder', Size = Vector3.new(0.9311, 0.11, 0.11), CF = {0.20506, 2.795, 0.20506, 0.28859, -0.64553, -0.70711, 0.91292, 0.40813, 0.0, 0.28859, -0.64553, 0.70711}, T = 0.0, Collide = false},
	{Name = 'Frond8LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.8832, 0.06, 1.55), CF = {0.70094, 3.40544, 1.04456, -0.47042, 0.02691, -0.88203, 0.24798, 0.96329, -0.10287, 0.84688, -0.26712, -0.45982}, T = 0.0, Collide = false},
	{Name = 'Frond8LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.8832, 0.06, 1.55), CF = {1.04456, 3.40544, 0.70095, -0.84688, -0.26712, -0.45982, -0.24798, 0.96329, -0.10287, 0.47042, 0.02691, -0.88203}, T = 0.0, Collide = false},
	{Name = 'Frond8Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.24), CF = {0.78967, 3.35767, 0.78967, -0.70711, -0.12279, -0.69636, 0.0, 0.98481, -0.17365, 0.70711, -0.12279, -0.69636}, T = 0.0, Collide = false},
	{Name = 'Frond9Stem', Shape = 'Cylinder', Size = Vector3.new(0.743, 0.11, 0.11), CF = {0.07247, 2.695, -0.27046, 0.1254, -0.22641, 0.96593, 0.87479, 0.4845, -0.0, -0.46799, 0.84498, 0.25882}, T = 0.0, Collide = false},
	{Name = 'Frond9LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.8576, 0.06, 1.5), CF = {0.5414, 3.04394, -1.10896, 0.98043, -0.19199, 0.0436, 0.18712, 0.97755, 0.09684, -0.06121, -0.08679, 0.99434}, T = 0.0, Collide = false},
	{Name = 'Frond9LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.8576, 0.06, 1.5), CF = {0.08562, 3.04394, -1.23108, 0.81847, 0.20966, -0.53493, -0.18712, 0.97755, 0.09684, 0.54322, 0.02084, 0.83933}, T = 0.0, Collide = false},
	{Name = 'Frond9Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.2), CF = {0.28224, 3.023, -1.05333, 0.96593, 0.00903, -0.25866, 0.0, 0.99939, 0.0349, 0.25882, -0.03371, 0.96534}, T = 0.0, Collide = false},
	{Name = 'Frond10Stem', Shape = 'Cylinder', Size = Vector3.new(0.6466, 0.11, 0.11), CF = {-0.06988, 2.645, 0.2608, -0.13609, 0.22015, -0.96593, 0.85059, 0.52582, 0.0, 0.50791, -0.82161, -0.25882}, T = 0.0, Collide = false},
	{Name = 'Frond10LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.832, 0.06, 1.45), CF = {-0.52254, 2.86728, 1.06579, -0.985, 0.16559, -0.0486, 0.15319, 0.96863, 0.19569, 0.07948, 0.1853, -0.97946}, T = 0.0, Collide = false},
	{Name = 'Frond10LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.832, 0.06, 1.45), CF = {-0.08036, 2.86728, 1.18427, -0.81329, -0.23606, 0.53182, -0.15319, 0.96863, 0.19569, -0.56133, 0.07768, -0.82394}, T = 0.0, Collide = false},
	{Name = 'Frond10Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.16), CF = {-0.27087, 2.86, 1.01089, -0.96593, -0.03602, 0.2563, 0.0, 0.99027, 0.13917, -0.25882, 0.13443, -0.95653}, T = 0.0, Collide = false},
	{Name = 'Frond11Stem', Shape = 'Cylinder', Size = Vector3.new(0.564, 0.11, 0.11), CF = {-0.15487, 2.595, -0.22117, -0.34577, 0.45764, 0.81915, 0.79787, 0.60283, 0.0, -0.49381, 0.65357, -0.57358}, T = 0.0, Collide = false},
	{Name = 'Frond11LeafL', Shape = 'Ellipsoid', Size = Vector3.new(0.8064, 0.06, 1.4), CF = {-0.46677, 2.69641, -1.05339, 0.56326, -0.30604, 0.76752, 0.11735, 0.94909, 0.29232, -0.81791, -0.07459, 0.5705}, T = 0.0, Collide = false},
	{Name = 'Frond11LeafR', Shape = 'Ellipsoid', Size = Vector3.new(0.8064, 0.06, 1.4), CF = {-0.83022, 2.69641, -0.7989, 0.96123, 0.03458, 0.27358, -0.11735, 0.94909, 0.29232, -0.24955, -0.31309, 0.91635}, T = 0.0, Collide = false},
	{Name = 'Frond11Rib', Shape = 'Block', Size = Vector3.new(0.06, 0.05, 1.12), CF = {-0.58309, 2.70201, -0.83274, 0.81915, -0.13876, 0.55654, 0.0, 0.9703, 0.24192, -0.57358, -0.19817, 0.79482}, T = 0.0, Collide = false},
	{Name = 'Frond0Spike', Shape = 'Ellipsoid', Size = Vector3.new(0.16, 1.8, 0.16), CF = {0.05, 3.31124, -0.07526, 0.86603, 0.0, 0.5, -0.06959, 0.99027, 0.12053, -0.49513, -0.13917, 0.8576}, T = 0.0, Collide = false},
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
local function vnear(a, b, eps) return (a - b).Magnitude <= (eps or 1e-6) end
local function cfnear(a, b, eps)
	eps = eps or 1e-5
	return vnear(a.Position, b.Position, eps) and vnear(a.LookVector, b.LookVector, eps) and vnear(a.UpVector, b.UpVector, eps)
end

------------------------------------------------------------------ template + placement (BuildService.MakeTemplate + a placed clone)
local function MakePlaced(key, scale, placeCF)
	local data = MODELS[key]
	local model = Instance.new("Model")
	model.Name = key
	local parts = {}
	local centre = (data.Min + data.Max) / 2
	for _, pd in ipairs(data.Parts) do
		local cls = pd.Shape == "Wedge" and "WedgePart" or (pd.Shape == "CornerWedge" and "CornerWedgePart" or "Part")
		local p = Instance.new(cls)
		p.Name = pd.Name
		local c = pd.CF
		local authored = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		p.Size = pd.Size * scale
		p.CFrame = CFrame.new(centre + (authored.Position - centre) * scale) * authored.Rotation
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

------------------------------------------------------------------ client ctx (FunBuildClient.NewContext)
local function MakeCtx(model)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit, Player = MockLocalPlayer,
		_insts = {}, _cleanups = {}, _steps = {}, _everys = {}, _states = {}, StepRange = 180}
	function ctx:Alive() return true end
	function ctx:Connect() return {Disconnect = function() end} end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:State(k) return model:GetAttribute("Fun_" .. k) end
	function ctx:OnState(k, fn)
		self._states[k] = self._states[k] or {}
		table.insert(self._states[k], fn)
		fn(self:State(k))
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
--.. the server sets a state: every running client's OnState handlers fire
local function SetState(model, ctxs, k, v)
	model:SetAttribute("Fun_" .. k, v)
	for _, ctx in ipairs(ctxs) do
		for _, fn in ipairs(ctx._states[k] or {}) do fn(v) end
	end
end

local function Run(mod, model)
	local ctx = MakeCtx(model)
	local before = #MockAll
	local ok, res = pcall(mod.Client, model, ctx)
	check(ok, "Client() errored: " .. tostring(res))
	if ok and type(res) == "function" then ctx:OnCleanup(res) end
	ctx._made = #MockAll - before
	return ctx
end
--.. step every ctx in lockstep; after(t) is called once per tick
local function Frames(ctxs, n, dt, after)
	dt = dt or 1 / 60
	for _ = 1, n do
		MockNow += dt
		for _, ctx in ipairs(ctxs) do
			check(#ctx._steps <= 1, "at most one ctx:Step per build")
			for _, fn in ipairs(ctx._steps) do
				local ok, err = pcall(fn, dt, MockNow)
				if not ok then check(false, "Step errored: " .. tostring(err)) return end
			end
		end
		if after then after() end
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
	for i = #ctx._insts, 1, -1 do ctx._insts[i]:Destroy() end
end
--.. instances a ctx made (and their descendants), by class / name
local function Mine(ctx, className, name)
	local out, seen = {}, {}
	local function take(inst)
		if seen[inst] then return end
		seen[inst] = true
		if inst.ClassName == className and (not name or inst.Name == name) then table.insert(out, inst) end
	end
	for _, inst in ipairs(ctx._insts) do
		take(inst)
		for _, d in ipairs(inst:GetDescendants()) do take(d) end
	end
	return out
end
local camera = workspace.CurrentCamera
local function SetCamera(model, dist) rawget(camera, "_p").CFrame = CFrame.new(Kit.Hitbox(model).Position + Vector3.new(0, 4, dist)) end
local function Authored(model, world) return Kit.Origin(model):PointToObjectSpace(world) / Kit.Scale(model) end
local function AngleBetween(a, b) return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1))) end

------------------------------------------------------------------ Aquarium (client)
local CASTLE_MIN, CASTLE_MAX = Vector3.new(-2.40, 3.55, 0.30), Vector3.new(-0.70, 5.70, 1.02)
local function InBox(p, lo, hi, pad)
	pad = pad or 0
	return p.X > lo.X - pad and p.X < hi.X + pad and p.Y > lo.Y - pad and p.Y < hi.Y + pad and p.Z > lo.Z - pad and p.Z < hi.Z + pad
end
do
	local mod = load("C_Aquarium")
	for _, spec in ipairs({{1, CFrame.new(40, 3, -12) * CFrame.Angles(0, math.rad(90), 0)}, {1.3, CFrame.new(-60, 5, 30) * CFrame.Angles(0, math.rad(-37), 0)}}) do
		local scale, place = spec[1], spec[2]
		local tag = ("x%.1f"):format(scale)
		local model = MakePlaced("Aquarium", scale, place)
		SetCamera(model, 20)
		local tmin, tmax = model:GetAttribute("Pivot_TankMin"), model:GetAttribute("Pivot_TankMax")
		local rest = {}
		for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then rest[d] = d.CFrame end end
		local ctx = Run(mod, model)
		local bodies = Mine(ctx, "Part", "FishBody")
		check(#bodies == 5, tag .. " five fish, got " .. #bodies)
		check(#Mine(ctx, "Part", "FishFlake") == 12, tag .. " 12 flakes")
		check(#Mine(ctx, "WedgePart", "FishTail") == 10, tag .. " 10 tail halves")
		print(tag .. " instances made by Client(): " .. ctx._made)
		for _, f in ipairs(Mine(ctx, "Part", "FishFlake")) do check(f.Transparency == 1, tag .. " flakes hidden before a feeding") end
		Everys(ctx)
		local loop = Mine(ctx, "Sound", "Bubbles")[1]
		check(loop and loop.IsPlaying, tag .. " bubbling loop plays near the tank")
		check(#Mine(ctx, "Part", "AquariumFX") == 1, tag .. " one fx host")
		--.. swim 40 s: fish inside the water box, clear of the castle, heads along their path
		local worst = {wall = math.huge, castle = math.huge, top = math.huge, bottom = math.huge}
		local minPair = math.huge
		local leaf = Kit.Part(model, "Plant1Leaf1")
		local maxLeaf = 0
		local lid = Kit.Part(model, "ChestLid")
		local lidMin, lidMax = math.huge, -math.huge
		local prev = {}
		local headingBad = 0
		local burst = Mine(ctx, "ParticleEmitter", "Burst")[1]
		--.. the bubble column (Pivot_Bubbler straight up 0.7 authored studs) must never pass through the chest lid
		--.. (any pose) or the chest's other parts: bubbles would appear out of a solid face
		local bubbleFrom = Kit.ToWorld(model, model:GetAttribute("Pivot_Bubbler"))
		local chestParts = {lid}
		for _, name in ipairs({"ChestBody", "ChestBand", "ChestLock", "ChestGold"}) do table.insert(chestParts, Kit.Part(model, name)) end
		local bubbleBlocked = 0
		local function BubbleColumnClear()
			for k = 0, 35 do
				local q = bubbleFrom + Vector3.new(0, 0.02 * k * scale, 0)
				for _, part in ipairs(chestParts) do
					local o = part.CFrame:PointToObjectSpace(q)
					local h = part.Size * 0.5 + Vector3.one * (0.035 * scale)
					if math.abs(o.X) < h.X and math.abs(o.Y) < h.Y and math.abs(o.Z) < h.Z then return false end
				end
			end
			return true
		end
		local function Probe(feeding)
			local pts = {}
			for i, b in ipairs(bodies) do
				local p = Authored(model, b.Position)
				pts[i] = p
				local half = b.Size.Z / scale * 0.5
				local lv = Kit.Origin(model).Rotation:Inverse() * b.CFrame.LookVector
				local nose, tail = p + lv * half, p - lv * half
				for _, q in ipairs({nose, tail}) do
					worst.wall = math.min(worst.wall, 2.92 - math.abs(q.X), 1.22 - math.abs(q.Z))
				end
				if not feeding then
					worst.top = math.min(worst.top, tmax.Y - p.Y)
				end
				worst.bottom = math.min(worst.bottom, p.Y - tmin.Y)
				if InBox(p, CASTLE_MIN, CASTLE_MAX, 0.12) then worst.castle = 0 end
				if prev[i] and not feeding then
					local mv = p - prev[i]
					if mv.Magnitude > 1e-3 and mv.Unit:Dot(lv) < 0.5 then headingBad += 1 end
				end
				prev[i] = p
			end
			if not feeding then
				for i = 1, #pts do
					for j = i + 1, #pts do minPair = math.min(minPair, (pts[i] - pts[j]).Magnitude) end
				end
			end
			maxLeaf = math.max(maxLeaf, AngleBetween(leaf.CFrame.UpVector, rest[leaf].UpVector))
			local a = AngleBetween(lid.CFrame.LookVector, rest[lid].LookVector)
			local up = (lid.CFrame.LookVector - rest[lid].LookVector):Dot(rest[lid].UpVector) > 0 and 1 or -1
			lidMin, lidMax = math.min(lidMin, a * up), math.max(lidMax, a * up)
			if not BubbleColumnClear() then bubbleBlocked += 1 end
		end
		Frames({ctx}, 60) -- let the yaw smoothing settle
		for k in pairs(prev) do prev[k] = nil end
		Frames({ctx}, 2400, 1 / 60, function() Probe(false) end)
		print(("%s swim 40 s: wall %.3f  top %.3f  bottom %.3f  fish-pair min %.3f  heading-bad %d  leaf sway max %.1f deg  lid %.1f..%.1f deg  bursts %d")
			:format(tag, worst.wall, worst.top, worst.bottom, minPair, headingBad, maxLeaf, lidMin, lidMax, rawget(burst, "_emitted") or 0))
		check(worst.wall > 0.1, tag .. " fish noses/tails stay off the glass")
		check(worst.top > 0.2 and worst.bottom > 0.4, tag .. " fish stay in the water column")
		check(worst.castle > 0, tag .. " no fish in the castle")
		check(minPair > 0.4, tag .. " fish keep apart")
		check(headingBad < 50, tag .. " fish face where they swim (" .. headingBad .. " bad frames)")
		check(maxLeaf > 2 and maxLeaf < 8, tag .. " leaves sway a few degrees")
		check(lidMin < -18 and lidMax > 18, tag .. " chest lid shuts and pops open")
		check((rawget(burst, "_emitted") or 0) >= 9 * 4, tag .. " a bubble burst per lid pop")
		check(bubbleBlocked == 0, tag .. " bubbles rise clear of the chest lid (" .. bubbleBlocked .. " blocked frames)")
		--.. the castle flag and the rest of the build: only the animated parts moved
		for part, cf in pairs(rest) do
			local n = part.Name
			local animated = n:match("^Plant%d+Leaf%d+$") or n == "CastleFlag" or n == "ChestLid" or n == "FeedFlap" or n == "FeedFlapTab"
			if not animated then check(cfnear(part.CFrame, cf), tag .. " static part moved: " .. n) end
		end

		--.. FEEDING: a second client joins now, a third streams in 2 s late
		local ctx2 = Run(mod, model)
		Everys(ctx2)
		local t0 = MockNow
		SetState(model, {ctx, ctx2}, "FedAt", t0)
		local flap = Kit.Part(model, "FeedFlap")
		local flakes = Mine(ctx, "Part", "FishFlake")
		local flakes2 = Mine(ctx2, "Part", "FishFlake")
		local bodies2 = Mine(ctx2, "Part", "FishBody")
		local seen, gone = {}, {}
		local flapMax = 0
		local nearSurface = {}
		local mismatch = 0
		local feedPair = math.huge
		local ctx3
		local ring = Mine(ctx, "ParticleEmitter", "LandRing")[1]
		local gulp = Mine(ctx, "ParticleEmitter", "Gulp")[1]
		local bodies3, ring3
		local function Track()
			local t = MockNow - t0
			flapMax = math.max(flapMax, AngleBetween(flap.CFrame.UpVector, rest[flap].UpVector))
			for i, f in ipairs(flakes) do
				if f.Transparency < 1 then
					seen[i] = seen[i] or t
					local p = Authored(model, f.Position)
					check(math.abs(p.Y - (tmax.Y + 0.025)) < 0.5, tag .. " flake near the surface")
				elseif seen[i] and not gone[i] then
					gone[i] = t
				end
			end
			local pts = {}
			for i, b in ipairs(bodies) do
				local p = Authored(model, b.Position)
				pts[i] = p
				if tmax.Y - p.Y < 0.3 then nearSurface[i] = true end
				if not vnear(b.Position, bodies2[i].Position, 1e-6) then mismatch += 1 end
				if bodies3 and not vnear(b.Position, bodies3[i].Position, 1e-6) then mismatch += 1 end
				if InBox(p, CASTLE_MIN, CASTLE_MAX, 0.05) then check(false, tag .. " feeding fish in the castle") end
			end
			for i, f in ipairs(flakes) do
				if (f.Transparency < 1) ~= (flakes2[i].Transparency < 1) then mismatch += 1 end
			end
			for i = 1, #pts do
				for j = i + 1, #pts do feedPair = math.min(feedPair, (pts[i] - pts[j]).Magnitude) end
			end
		end
		Frames({ctx, ctx2}, 150, 1 / 60, Track)
		if scale == 1 then
			--.. DUMP lines (authored frame) for the Blender review render: tests/HomeDecor/render_dump.py
			local inv = Kit.Origin(model):Inverse()
			for _, inst in ipairs(ctx._insts) do
				if inst:IsA("BasePart") and inst.Transparency < 1 and inst.Name ~= "AquariumFX" then
					local c = inv * inst.CFrame
					local m = c.m
					local shape = inst.ClassName == "WedgePart" and "Wedge" or (inst.Shape == Enum.PartType.Ball and "Ball"
						or (inst:FindFirstChildOfClass("SpecialMesh") and "Ellipsoid" or "Block"))
					local col = inst.Color
					print(("DUMP|%s|%s|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f|%.4f,%.4f,%.4f|%s")
						:format(inst.Name, shape, inst.Size.X, inst.Size.Y, inst.Size.Z, c.p.X, c.p.Y, c.p.Z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9],
							col.R, col.G, col.B, tostring(inst.Material)))
				end
			end
			for _, name in ipairs({"FeedFlap", "FeedFlapTab", "ChestLid"}) do
				local part = Kit.Part(model, name)
				local c = inv * part.CFrame
				local m = c.m
				print(("POSE|%s|%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f"):format(name, c.p.X, c.p.Y, c.p.Z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]))
			end
		end
		ctx3 = Run(mod, model) -- streams in 2.5 s into the feeding
		bodies3 = Mine(ctx3, "Part", "FishBody")
		ring3 = Mine(ctx3, "ParticleEmitter", "LandRing")[1]
		Frames({ctx, ctx2, ctx3}, 330, 1 / 60, Track)
		local nSeen, nGone = 0, 0
		for i = 1, 12 do
			if seen[i] then nSeen += 1 end
			if gone[i] then nGone += 1 end
		end
		local nNear = 0
		for i = 1, 5 do if nearSurface[i] then nNear += 1 end end
		print(("%s feed: flap max %.1f deg, flakes seen %d eaten %d, fish at the surface %d/5, fish-pair min %.2f, client mismatches %d, rings %d (late client %d), gulps %d")
			:format(tag, flapMax, nSeen, nGone, nNear, feedPair, mismatch, rawget(ring, "_emitted") or 0, rawget(ring3, "_emitted") or 0, rawget(gulp, "_emitted") or 0))
		check(flapMax > 60 and flapMax < 75, tag .. " feed flap opens ~68 deg")
		check(cfnear(flap.CFrame, rest[flap]), tag .. " feed flap shut again")
		check(nSeen == 12 and nGone == 12, tag .. " all 12 flakes fall and get eaten")
		check(nNear == 5, tag .. " every fish rushes up to the food")
		check(mismatch == 0, tag .. " every client shows the same fish and flakes")
		check((rawget(ring, "_emitted") or 0) == 12, tag .. " a landing ring per flake")
		check((rawget(ring3, "_emitted") or 0) == 0, tag .. " a late client does not replay old landings")
		local click1 = Mine(ctx, "Sound", "Click")[1]
		local click3 = Mine(ctx3, "Sound", "Click")[1]
		check((rawget(click1, "_plays") or 0) == 2, tag .. " the flap clicks open and shut (on-time client)")
		check((rawget(click3, "_plays") or 0) == 0, tag .. " a late client does not click for a flap close long past")
		check((rawget(gulp, "_emitted") or 0) == 36, tag .. " 3 gulp bubbles per flake")
		for _, f in ipairs(flakes) do check(f.Transparency == 1, tag .. " flakes hidden after the feeding") end
		--.. the fish swim back into their loops (compare with a fresh client that never saw the feeding)
		Frames({ctx, ctx2, ctx3}, 120)
		SetState(model, {}, "FedAt", nil)
		local fresh = Run(mod, model)
		Frames({ctx, fresh}, 2)
		local freshBodies = Mine(fresh, "Part", "FishBody")
		for i, b in ipairs(bodies) do check(vnear(b.Position, freshBodies[i].Position, 1e-6), tag .. " fish " .. i .. " back on its loop") end
		--.. far camera: steps are asleep in the real framework; Every turns the loop and the light off
		rawget(camera, "_p").CFrame = CFrame.new(Kit.Hitbox(model).Position + Vector3.new(0, 0, 400))
		Everys(ctx)
		check(not loop.IsPlaying, tag .. " bubbling loop stops far away")
		check(Mine(ctx, "ParticleEmitter", "Trickle")[1].Enabled == false, tag .. " trickle off far away")
		--.. cleanup: every build part back at rest
		for _, c in ipairs({fresh, ctx3, ctx2, ctx}) do Stop(c) end
		for part, cf in pairs(rest) do check(cfnear(part.CFrame, cf), tag .. " restored: " .. part.Name) end
		check(#Mine(ctx, "Part", "FishBody") == 5 and bodies[1].Parent == nil, tag .. " fish destroyed")
		model:Destroy()
	end
end

------------------------------------------------------------------ Aquarium feeding survey: fish spacing over many feedings
do
	local mod = load("C_Aquarium")
	local model = MakePlaced("Aquarium", 1, CFrame.new(7, 3, 9))
	SetCamera(model, 20)
	local ctx = Run(mod, model)
	local bodies = Mine(ctx, "Part", "FishBody")
	local mins, all = {}, {}
	for n = 1, 24 do
		Frames({ctx}, 97 + n * 13, 1 / 30) -- a different moment of the loops every time
		local t0 = MockNow
		SetState(model, {ctx}, "FedAt", t0)
		local low = math.huge
		local lowPair = ""
		Frames({ctx}, 200, 1 / 30, function()
			for i = 1, 5 do
				for j = i + 1, 5 do
					local d = (Authored(model, bodies[i].Position) - Authored(model, bodies[j].Position)).Magnitude
					if d < low then low, lowPair = d, i .. "-" .. j .. (" @%.1fs"):format(MockNow - t0) end
				end
			end
		end)
		table.insert(mins, low)
		table.insert(all, ("%.2f(%s)"):format(low, lowPair))
		SetState(model, {ctx}, "FedAt", nil)
	end
	table.sort(mins)
	print("feeding survey, closest two fish per feeding: " .. table.concat(all, " "))
	print(("feeding survey: worst %.2f  median %.2f"):format(mins[1], mins[12]))
	check(mins[12] > 0.2, "feeding: fish mostly keep apart")
	Stop(ctx)
	model:Destroy()
end

------------------------------------------------------------------ Aquarium (server)
do
	local mod = load("S_Aquarium")
	local model = MakePlaced("Aquarium", 1, CFrame.new(0, 3, 0))
	local function Signal()
		local s = {fns = {}}
		function s:Connect(fn) table.insert(self.fns, fn) return {Disconnect = function() end} end
		function s:Fire(...) for _, fn in ipairs(self.fns) do fn(...) end end
		return s
	end
	local prompts = {}
	local ctx = {Model = model, Key = "Aquarium", Base = "Aquarium", Scale = 1}
	function ctx:Alive() return true end
	function ctx:Connect(sig, fn) return sig:Connect(fn) end
	function ctx:Prompt(part, opts)
		local p = {ActionText = opts.Action, ObjectText = opts.Object, MaxActivationDistance = opts.Distance, Part = part, Parent = part, Triggered = Signal()}
		table.insert(prompts, p)
		return p
	end
	function ctx:HumanoidOf(player) if player.Alive then return {}, {} end return nil end
	function ctx:SetState(k, v) model:SetAttribute("Fun_" .. k, v) end
	function ctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
	local ok, err = pcall(mod.Server, model, ctx)
	check(ok, "server Server() errored: " .. tostring(err))
	check(#prompts == 1 and prompts[1].Part.Name == "FeedFlap", "server: one prompt on the FeedFlap")
	local prompt = prompts[1]
	check(prompt.ActionText == "Feed fish" and prompt.ObjectText == "Aquarium", "server: prompt text")
	prompt.Triggered:Fire({Alive = false, UserId = 1})
	check(model:GetAttribute("Fun_FedAt") == nil, "server: a dead player can't feed")
	prompt.Triggered:Fire({Alive = true, UserId = 1})
	local t0 = model:GetAttribute("Fun_FedAt")
	check(t0 == MockNow, "server: Fun_FedAt = now")
	check(prompt.ActionText == "Fish are eating...", "server: busy text")
	MockNow += 3
	prompt.Triggered:Fire({Alive = true, UserId = 2})
	check(model:GetAttribute("Fun_FedAt") == t0, "server: no second feeding within the cooldown")
	MockNow += 4.5
	for _, d in ipairs(MockDelayed) do d.Fn(table.unpack(d.Args)) end
	table.clear(MockDelayed)
	check(prompt.ActionText == "Feed fish", "server: prompt text back after the cooldown")
	prompt.Triggered:Fire({Alive = true, UserId = 2})
	check(model:GetAttribute("Fun_FedAt") == MockNow, "server: feeding again after the cooldown")
	model:Destroy()
end

------------------------------------------------------------------ PottedPlant (client)
do
	local mod = load("C_PottedPlant")
	for _, spec in ipairs({{1, CFrame.new(10, 2, 10) * CFrame.Angles(0, math.rad(33), 0)}, {1.4, CFrame.new(-5, 0, 7)}}) do
		local scale, place = spec[1], spec[2]
		local tag = ("plant x%.1f"):format(scale)
		local model = MakePlaced("PottedPlant", scale, place)
		SetCamera(model, 15)
		local rest = {}
		for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then rest[d] = d.CFrame end end
		local ctx = Run(mod, model)
		local maxA, maxTip = 0, 0
		local bases = {}
		for n = 0, 11 do bases[n] = Kit.Pivot(model, "Frond" .. n) end
		Frames({ctx}, 1200, 1 / 60, function()
			for part, cf in pairs(rest) do
				local n = tonumber(part.Name:match("^Frond(%d+)"))
				if n then
					maxA = math.max(maxA, AngleBetween(part.CFrame.UpVector, cf.UpVector), AngleBetween(part.CFrame.LookVector, cf.LookVector))
					maxTip = math.max(maxTip, (part.Position - cf.Position).Magnitude)
					-- the stem's base stays planted: distance to its pivot is constant
					local d0 = (cf.Position - bases[n]).Magnitude
					local d1 = (part.Position - bases[n]).Magnitude
					if math.abs(d0 - d1) > 1e-4 then check(false, tag .. " frond part keeps its distance to its base: " .. part.Name) end
				elseif part.Name ~= "Hitbox" then
					if not cfnear(part.CFrame, cf) then check(false, tag .. " static part moved: " .. part.Name) end
				end
			end
		end)
		print(("%s: 20 s sway max %.2f deg, max part travel %.3f studs"):format(tag, maxA, maxTip))
		check(maxA > 1 and maxA < 4.5, tag .. " gentle sway")
		Stop(ctx)
		for part, cf in pairs(rest) do check(cfnear(part.CFrame, cf), tag .. " restored: " .. part.Name) end
		model:Destroy()
	end
end

print(("%d checks, %d failed"):format(checks, fails))
