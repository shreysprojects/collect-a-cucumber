
--..Test scene..--
KitScript.Module = KitModule
AssetsScript.Module = AssetsModule
local Kit = KitModule
local S = 1.5
local FLOOR_Y = 5
local hitboxCF = CFrame.new(100, FLOOR_Y + 0.81 * S, 50) * CFrame.Angles(0, math.rad(30), 0)
local model = new("Model", {Name = "Trampoline", Parent = workspace})
model:SetAttribute("Scale", S)
model:SetAttribute("AuthoredCentre", Vector3.new(0, 0.81, 0))
model:SetAttribute("Pivot_MatCentre", Vector3.new(0, 0.68, 0))
model:SetAttribute("State_Bottom", -0.5)
model:SetAttribute("BuildKey", "Trampoline")
local hitbox = new("Part", {Name = "Hitbox", CFrame = hitboxCF, Parent = model})
model.PrimaryPart = hitbox
local origin = hitboxCF * CFrame.new(Vector3.new(0, -0.81, 0) * S)
local mat = new("MeshPart", {Name = "MatSurface", CFrame = origin * CFrame.new(0, 0.90 * S, 0), Size = Vector3.new(5.9 * S, 0.61 * S, 5.9 * S), Material = "Material.Rubber", Parent = model})
local springs = new("MeshPart", {Name = "Springs", CFrame = origin * CFrame.new(0, 1.25 * S, 0), Size = Vector3.new(6.73 * S, 0.31 * S, 6.73 * S), Material = "Material.Metal", Parent = model})
new("MeshPart", {Name = "Pad", CFrame = origin * CFrame.new(0, 1.45 * S, 0), Size = Vector3.new(8 * S, 0.34 * S, 8 * S), Parent = model})
local MAT_REST, SPRINGS_REST = mat.CFrame, springs.CFrame
local MAT_TOP_REST = MAT_REST.Y + mat.Size.Y / 2
local floorCentre = origin.Position
print("origin", origin.Position, "mat top rest", MAT_TOP_REST)

--..Characters..--
local function MakeChar(name, pos)
	local char = new("Model", {Name = name, Parent = workspace})
	local root = new("Part", {Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1), CFrame = CFrame.new(pos), AssemblyLinearVelocity = Vector3.new(), Anchored = false, Parent = char})
	local hum = new("Humanoid", {Name = "Humanoid", HipHeight = 2, RigType = "HumanoidRigType.R15", Health = 100, WalkSpeed = 16, UseJumpPower = false, JumpHeight = 7.2, JumpPower = 50, FloorMaterial = "Material.Air", Sit = false, PlatformStand = false, Jump = false, State = "HumanoidStateType.Freefall", Parent = char})
	local lt = new("Part", {Name = "LowerTorso", Size = Vector3.new(2, 0.4, 1), CFrame = CFrame.new(pos + Vector3.new(0, -1, 0)), Parent = char})
	local motor = new("Motor6D", {Name = "Root", Part0 = root, Part1 = lt, C0 = CFrame.new(0, -1, 0), C1 = CFrame.new(), Transform = CFrame.new(), Parent = lt})
	-- a carried prop jointed to the root must NOT be picked as the flip joint
	local prop = new("Part", {Name = "CarriedCucumber", Parent = char})
	new("Motor6D", {Name = "CarryJoint", Part0 = root, Part1 = prop, C0 = CFrame.new(0, 2, 0), Transform = CFrame.new(), Parent = prop})
	return char, root, hum, motor
end
local me = {Name = "me", UserId = 1}
local char, root, hum, motor = MakeChar("me", floorCentre + Vector3.new(0, 1.2 + 3 + 4, 0))
me.Character = char
local other = {Name = "other", UserId = 2}
local ochar, oroot, ohum = MakeChar("other", floorCentre + Vector3.new(40, 3, 0))
other.Character = ochar
table.insert(PlayersList, me)
table.insert(PlayersList, other)

--..Raycast against the included parts (upright boxes, disc footprint)..--
RAYCAST = function(o, d, params)
	for _, p in ipairs(params.FilterDescendantsInstances) do
		local top = p.CFrame.Y + p.Size.Y / 2
		local dx, dz = o.X - p.CFrame.X, o.Z - p.CFrame.Z
		if math.sqrt(dx * dx + dz * dz) <= p.Size.X / 2 and o.Y >= top and o.Y + d.Y <= top then
			return {Instance = p, Position = Vector3.new(o.X, top, o.Z)}
		end
	end
	return nil
end

--..ctx..--
local stepFn, cleanups = nil, {}
local ctx = {Model = model, Key = "Trampoline", Base = "Trampoline", Scale = S, Player = me, Kit = Kit}
function ctx:Alive() return true end
function ctx:Connect(sig, fn) return sig:Connect(fn) end
function ctx:Add(i) return i end
function ctx:OnCleanup(fn) table.insert(cleanups, fn) end
function ctx:Step(fn) stepFn = fn end
function ctx:Sound(parent, id, props) local s = Kit.MakeSound(id, props) s.Parent = parent return s end
function ctx:Part(props) local p = Instance.new("Part") for k, v in pairs(props) do p[k] = v end p.Parent = workspace.CurrentCamera return p end
function ctx:LocalCharacter()
	if hum.Health > 0 then return hum, root, char end
	return nil
end

local ret = B.Client(model, ctx)
if type(ret) == "function" then table.insert(cleanups, ret) end
assert(stepFn, "no Step registered")
local fx = workspace.CurrentCamera:FindFirstChild("TrampolineFX")
print("fx part", fx ~= nil, "children", fx and #fx:GetChildren())

--..Physics + frame loop..--
local G = 196.2
local JUMP_OVERRIDE = 53.1 -- the Jumping state's own jump velocity (JumpHeight 7.2)
--.. how the Jumping state treats our launch velocity (unknown until measured in Studio - test them all):
--..   "replace" = Y := jump (the old worst case), "add" = Y += jump, "maxadd" = Y := max(Y, 0) + jump, "none"
local JUMP_MODE = "replace"
local JUMP_DELAY = 0 -- physics steps before the Jumping state applies its impulse
local PAD_TOP = FLOOR_Y + 1.62 * S
local MAT_R = 2.95 * S
local ANIMATOR_WRITES = true
local walkVel = nil -- Vector3 horizontal walk velocity (humanoid control), nil = none
local jumpWait = 0
local function Physics(dt)
	local v = root.AssemblyLinearVelocity
	local jumped = false
	if hum.PendingState == "HumanoidStateType.Jumping" and jumpWait < JUMP_DELAY then
		jumpWait += 1
	elseif hum.PendingState == "HumanoidStateType.Jumping" then
		hum.PendingState = nil
		jumpWait = 0
		if JUMP_MODE == "replace" then
			v = Vector3.new(v.X, JUMP_OVERRIDE, v.Z)
		elseif JUMP_MODE == "add" then
			v = Vector3.new(v.X, v.Y + JUMP_OVERRIDE, v.Z)
		elseif JUMP_MODE == "maxadd" then
			v = Vector3.new(v.X, math.max(v.Y, 0) + JUMP_OVERRIDE, v.Z)
		end
		hum.State = "HumanoidStateType.Jumping"
		jumped = true
	elseif hum.State == "HumanoidStateType.Running" and v.Y > 0 then
		v = Vector3.new(v.X, 0, v.Z) -- the ground controller eats a bare velocity write
	end
	if walkVel then v = Vector3.new(walkVel.X, v.Y, walkVel.Z) end
	v = Vector3.new(v.X, v.Y - G * dt, v.Z)
	local pos = root.Position + v * dt
	local dx, dz = pos.X - floorCentre.X, pos.Z - floorCentre.Z
	local flat = math.sqrt(dx * dx + dz * dz)
	local surf, material
	if flat <= MAT_R then surf, material = mat.CFrame.Y + mat.Size.Y / 2, mat.Material
	elseif flat <= 4 * S then surf, material = PAD_TOP, "Material.Fabric"
	else surf, material = FLOOR_Y, "Material.Grass" end
	if pos.Y - 3 <= surf and not (jumped) then
		pos = Vector3.new(pos.X, surf + 3, pos.Z)
		if v.Y < 0 then v = Vector3.new(v.X, 0, v.Z) end
		hum.FloorMaterial = material
		hum.State = "HumanoidStateType.Running"
	else
		hum.FloorMaterial = "Material.Air"
		if v.Y < 0 then hum.State = "HumanoidStateType.Freefall" end
	end
	root.CFrame = CFrame.new(pos)
	root.AssemblyLinearVelocity = v
end

local log = {apex = {}, matMin = 0, matMax = 0, springMin = 0, flipMaxDeg = 0, flipDone = 0}
local lastVy = 0
local function FlipAngle()
	local rel = motor.C0 * motor.Transform
	local upv = rel.UpVector
	return math.deg(math.acos(math.clamp(upv.Y, -1, 1))), upv
end
log.tilts = {}
--.. FunBuildClient runs the Step on RenderStepped AND Heartbeat whenever the two are >= 4 ms apart (slow
--.. devices, heavy physics): DOUBLE = a second Step call HB_LAG after the physics step of the same frame
local DOUBLE = false
local HB_LAG = 0.007
local onPhysics = nil -- fn(dt): remote players' replicated positions land in the physics phase
local function Frame(dt)
	SIM.t += dt
	local tiltBefore = FlipAngle()
	local nSounds = #SIM.sounds
	stepFn(dt, SIM.t)
	if ANIMATOR_WRITES then motor.Transform = CFrame.new() end
	RunService.Stepped:Fire(SIM.t, dt)
	Physics(dt)
	if onPhysics then onPhysics(dt) end
	if DOUBLE then
		SIM.t += HB_LAG
		stepFn(dt, SIM.t)
		SIM.t -= HB_LAG
	end
	for i = nSounds + 1, #SIM.sounds do
		if SIM.sounds[i].name:sub(1, 5) == "Boing" then table.insert(log.tilts, string.format("%.1f", tiltBefore)) end
	end
	local vy = root.AssemblyLinearVelocity.Y
	if lastVy > 0 and vy <= 0 then table.insert(log.apex, root.Position.Y - 3 - MAT_TOP_REST) end
	lastVy = vy
	local d = mat.CFrame.Y - MAT_REST.Y
	log.matMin = math.min(log.matMin, d)
	log.matMax = math.max(log.matMax, d)
	log.springMin = math.min(log.springMin, springs.CFrame.Y - SPRINGS_REST.Y)
	local a = FlipAngle()
	log.flipMaxDeg = math.max(log.flipMaxDeg, a)
end
local function Run(seconds, dt)
	dt = dt or 1 / 60
	for _ = 1, math.floor(seconds / dt + 0.5) do Frame(dt) end
end
local dustSeen, sparkleSeen = 0, 0
local function Flush()
	SIM.sounds = {}
	log.apex = {}
	log.tilts = {}
	log.matMin, log.matMax, log.springMin, log.flipMaxDeg = 0, 0, 0, 0
	dustSeen, sparkleSeen = fx.Dust.Emitted or 0, fx.Sparkle.Emitted or 0
end
local function Report(label, remote)
	local speeds, est = {}, {}
	for _, s in ipairs(SIM.sounds) do
		if s.name:sub(1, 5) == "Boing" then
			table.insert(speeds, string.format("%.2f", s.speed))
			-- other players: pitch = 0.95 + 0.39 * clamp((speed - 20) / 90, 0, 1) -> the speed the module estimated
			table.insert(est, string.format("%.0f", 20 + (s.speed - 0.95) / 0.39 * 90))
		end
	end
	local apex = {}
	for _, h in ipairs(log.apex) do table.insert(apex, string.format("%.1f", h)) end
	print(label)
	print("  boing pitches:", table.concat(speeds, " "))
	if remote then print("  -> estimated impact speeds (110 = clamped):", table.concat(est, " ")) end
	print("  apex heights :", table.concat(apex, " "))
	print("  root-joint tilt at each bounce:", table.concat(log.tilts, " "))
	print(string.format("  mat dip min %.3f max %.3f | springs min %.3f | flip max %.0f deg | whoosh %d | ring dust %d sparkle %d",
		log.matMin, log.matMax, log.springMin, log.flipMaxDeg, (fx.FlipWhoosh and fx.FlipWhoosh.Plays) or 0,
		(fx.Dust.Emitted or 0) - dustSeen, (fx.Sparkle.Emitted or 0) - sparkleSeen))
	Flush()
end

--.. A: drop onto the mat, no input
Run(7)
Report("A drop, 7 s, no input (expect 7.7 14.3 23.0 30.8 30.8 ...)")
print("  transform after", motor.Transform, "carry joint untouched", tostring(char.CarriedCucumber.CarryJoint.Transform))

--.. B: hold space
SIM.held = true
Run(4)
SIM.held = false
Report("B holding space (expect ~39.8 at level 4)")

--.. C: walk off the mat sideways, land on the ground, stand, walk back on
walkVel = Vector3.new(16, 0, 0)
Run(2.5)
walkVel = nil
Report("C walked off (no more bounces once off)")
print("  pos flat dist from centre", ((root.Position - floorCentre) * Vector3.new(1, 0, 1)).Magnitude, "floor", hum.FloorMaterial)
root.CFrame = CFrame.new(floorCentre + Vector3.new(0, 1.8 + 3 + 0.5, 0))
root.AssemblyLinearVelocity = Vector3.new()
Run(1.2)
Report("C2 back on the mat after a rest (expect level 1 -> pitch 0.95, apex 7.7, then 14.3)")

--.. D: animator does NOT write the root joint: the flip must not compound
ANIMATOR_WRITES = false
Run(6)
local ang = FlipAngle()
Report("D flips with no Animator writes")
print(string.format("  root-joint tilt when the run stopped %.1f deg (mid-flip is fine; the per-bounce tilts above must be 0)", ang))

--.. E: another player falls onto the mat; the local player is parked far away
root.CFrame = CFrame.new(floorCentre + Vector3.new(60, 3, 0))
root.AssemblyLinearVelocity = Vector3.new()
Run(1)
Report("E0 settle")
local oy = floorCentre.Y + 1.8 + 3 + 12
local ovy = 0
for i = 1, 90 do
	-- remote client: falls, then its own trampoline launches it at 75 just above the mat
	ovy -= G / 60
	oy += ovy / 60
	if oy - 3 <= MAT_TOP_REST + 0.3 and ovy < 0 then ovy = 75 end
	oroot.CFrame = CFrame.new(Vector3.new(floorCentre.X + 1, oy, floorCentre.Z))
	oroot.AssemblyLinearVelocity = Vector3.new(0, ovy, 0)
	Frame(1 / 60)
end
Report("E other player lands from 12 studs, then bounces at 75 (expect impact ~69 then ~75)", true)

--.. E2/E3: Step runs on RenderStepped AND Heartbeat; the remote root moves once per frame, in the physics phase.
--.. The estimate must not be diluted by the call that sees no movement.
local function RemoteDrop(label, height, replicatedVel, seconds)
	oroot.CFrame = CFrame.new(Vector3.new(floorCentre.X + 1, MAT_TOP_REST + 3 + 8, floorCentre.Z))
	oroot.AssemblyLinearVelocity = Vector3.new()
	Run(1)
	Flush()
	local ro = {y = MAT_TOP_REST + 3 + height, vy = 0}
	oroot.CFrame = CFrame.new(Vector3.new(floorCentre.X + 1, ro.y, floorCentre.Z))
	Run(0.5) -- let the watcher see it hanging there first (replication hold)
	Flush()
	onPhysics = function(dt)
		ro.vy -= G * dt
		ro.y += ro.vy * dt
		if ro.y - 3 <= MAT_TOP_REST + 0.3 and ro.vy < 0 then ro.vy = 75 end -- its own client launches it
		oroot.CFrame = CFrame.new(Vector3.new(floorCentre.X + 1, ro.y, floorCentre.Z))
		oroot.AssemblyLinearVelocity = replicatedVel and Vector3.new(0, ro.vy, 0) or Vector3.new()
	end
	Run(seconds)
	onPhysics = nil
	Report(label, true)
end
DOUBLE = true
RemoteDrop("E2 RS+HB double Step, NO replicated velocity, drop 23 studs (expect impact ~95 then ~75, ring on the first)", 23, false, 1.4)
RemoteDrop("E3 RS+HB double Step, replicated velocity, drop 30.8 studs (expect impact ~110 then ~75, BIG ring on the first)", 30.84, true, 1.6)
RemoteDrop("E4 RS+HB double Step, NO replicated velocity, drop 30.8 studs (expect ~110 / big ring from positions alone)", 30.84, false, 1.6)
DOUBLE = false
RemoteDrop("E5 single Step, NO replicated velocity, drop 30.8 studs (expect ~110 / big ring)", 30.84, false, 1.6)
oroot.CFrame = CFrame.new(floorCentre + Vector3.new(40, 3, 0))
oroot.AssemblyLinearVelocity = Vector3.new()

--.. G: standing on the pad collar never bounces; walking in from it does
root.CFrame = CFrame.new(floorCentre + Vector3.new(5.4, PAD_TOP - floorCentre.Y + 3, 0))
root.AssemblyLinearVelocity = Vector3.new()
Run(1)
Report("G0 standing on the pad collar at r 5.4 (expect no boing)")
walkVel = Vector3.new(-8, 0, 0)
Run(0.4)
walkVel = nil
Run(1.5)
Report("G1 walked in from the pad (expect 0.95 then 1.08 ...)")

--.. H: every way the Jumping state might treat our launch velocity - the apexes must stay 7.7 / 14.3 / 23.0 / 30.8
local function DropTest(label, mode, delay, dt, double)
	JUMP_MODE, JUMP_DELAY, DOUBLE = mode, delay or 0, double == true
	root.CFrame = CFrame.new(floorCentre + Vector3.new(60, 3, 0))
	root.AssemblyLinearVelocity = Vector3.new()
	hum.PendingState = nil
	Run(1.5)
	Flush()
	root.CFrame = CFrame.new(floorCentre + Vector3.new(0, 1.2 + 3 + 4, 0))
	root.AssemblyLinearVelocity = Vector3.new()
	Run(4.6, dt)
	Report(label .. " (expect 7.7 14.3 23.0 30.8 30.8)")
	JUMP_MODE, JUMP_DELAY, DOUBLE = "replace", 0, false
end
DropTest("H1 jump REPLACES Y", "replace")
DropTest("H2 jump ADDS to Y", "add")
DropTest("H3 jump = max(Y,0) + jump", "maxadd")
DropTest("H4 jump leaves Y alone", "none")
DropTest("H5 jump ADDS, one physics step late", "add", 1)
DropTest("H6 jump ADDS, 30 fps", "add", 0, 1 / 30)
DropTest("H7 jump REPLACES, 30 fps", "replace", 0, 1 / 30)
DropTest("H8 jump ADDS, Step on RS + HB", "add", 0, nil, true)

--.. F: cleanup puts the mat back
Frame(1 / 60)
for _, fn in ipairs(cleanups) do fn() end
print("F cleanup: mat at rest", (mat.CFrame.Position - MAT_REST.Position).Magnitude < 1e-6, "springs at rest", (springs.CFrame.Position - SPRINGS_REST.Position).Magnitude < 1e-6)
print("raycasts", SIM.raycasts)
