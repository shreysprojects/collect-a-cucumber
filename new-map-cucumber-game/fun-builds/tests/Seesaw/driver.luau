--..Driver (appended after Kit / FunAssets / Server / Client sources)..--
local Kit = KitMod
local S = 1.8
local AC = v3(0, 1.5925, 0)
local HB = CFrame.new(100, 5, -40) * CFrame.Angles(0, math.rad(37), 0)
local function W(p) return HB * ((p - AC) * S) end
local function A(w, hb) return (hb or HB):PointToObjectSpace(w) / S + AC end

--.. the dump (authored, scale 1): name, pos, size
local DUMP = {
	{"Bearing", v3(0, 1.27, 0), v3(0.60, 0.43, 1.60)},
	{"Bumpers", v3(0, 0.37, 0), v3(7.90, 0.73, 1.05)},
	{"Frame", v3(0, 0.59, 0), v3(2.72, 1.18, 1.44)},
	{"FrameChevron", v3(0, 0.92, -0.67), v3(0.60, 0.43, 0.09)},
	{"PlankBeamBlue", v3(-1.83, 1.88, 0), v3(3.75, 1.03, 0.92)},
	{"PlankBeamRed", v3(1.89, 1.09, 0), v3(3.75, 1.03, 0.92)},
	{"PlankHandles", v3(0.09, 2.08, 0), v3(4.57, 2.21, 1.09)},
	{"PlankPivotStrap", v3(0.03, 1.51, 0), v3(0.77, 0.46, 1.24)},
	{"PlankSeats", v3(0.09, 1.80, 0), v3(6.33, 1.69, 1.04)},
}
local hitbox = Part("Hitbox", "Part", HB, v3(7.9, 3.2, 1.6) * S)
local kids = {hitbox}
local byName = {}
for _, d in ipairs(DUMP) do
	local p = Part(d[1], "MeshPart", CFrame.new(W(d[2])) * HB.Rotation, d[3] * S)
	table.insert(kids, p)
	byName[d[1]] = p
end
local original = {}
for _, p in ipairs(kids) do original[p] = p.CFrame end

local attrSignals = {}
local model = {_isInstance = true, Name = "Seesaw", Parent = true, PrimaryPart = hitbox, _attrs = {
	BuildKey = "Seesaw", Owner = 7, Scale = S, AuthoredCentre = AC, Pivot_PlankPivot = v3(0, 1.35, 0),
	State_RedDown = 12, State_Level = 0, State_BlueDown = -12,
}}
function model:GetAttribute(k) return self._attrs[k] end
function model:SetAttribute(k, v)
	self._attrs[k] = v
	if attrSignals[k] then attrSignals[k]:Fire() end
end
function model:GetAttributeChangedSignal(k)
	attrSignals[k] = attrSignals[k] or Signal()
	return attrSignals[k]
end
function model:FindFirstChild(name)
	for _, c in ipairs(kids) do if c.Name == name then return c end end
	return nil
end
function model:GetDescendants() return kids end
function model:GetPivot() return hitbox.CFrame end

--..Server ctx..--
local seatsMade = {}
local sctx = {Model = model, Scale = S, Folder = {Name = "Folder"}}
function sctx:Alive() return true end
function sctx:SetState(k, v) model:SetAttribute("Fun_" .. k, v) end
function sctx:GetState(k) return model:GetAttribute("Fun_" .. k) end
function sctx:Connect(sig, fn) return sig:Connect(fn) end
function sctx:Seat(cframe, opts)
	local s = Part(opts.Name, "Seat", cframe, opts.Size)
	s.Occupant = nil
	s.Opts = opts
	table.insert(seatsMade, s)
	return s
end

--..Client ctx..--
local log = {}
local cctx = {Model = model, Scale = S}
function cctx:Alive() return true end
function cctx:State(k) return model:GetAttribute("Fun_" .. k) end
function cctx:OnState(k, fn)
	local name = "Fun_" .. k
	model:GetAttributeChangedSignal(name):Connect(function() fn(model:GetAttribute(name)) end)
	fn(model:GetAttribute(name))
end
function cctx:Connect(sig, fn) return sig:Connect(fn) end
function cctx:Step(fn) self._step = fn end
function cctx:Sound(parent, id, props)
	local s = {Parent = parent, Id = id, Volume = 1, PlaybackSpeed = 1}
	for k, v in pairs(props or {}) do s[k] = v end
	function s:Play() table.insert(log, string.format("  t=%.3f  %-7s on %-15s vol %.2f", SIM_T - 0, tostring(self.Id), self.Parent.Name, self.Volume)) end
	return s
end

--..Helpers..--
local function PlankAngle()
	local r = HB.Rotation:Inverse() * byName.PlankBeamRed.CFrame.Rotation
	return 12 - math.deg(math.atan2(r.m[4], r.m[1]))
end
local function MaxErr(a, b)
	local e = (a.p - b.p).Magnitude
	for i = 1, 9 do e = math.max(e, math.abs(a.m[i] - b.m[i])) end
	return e
end
local function Check(label, ok) print((ok and "PASS " or "FAIL ") .. label) end
local function Flush() for _, l in ipairs(log) do print(l) end log = {} end

--..Run..--
ServerB.Server(model, sctx)
print(string.format("server made %d seats; Fun_Id=%s", #seatsMade, tostring(model:GetAttribute("Fun_Id"))))
local seatBy = {}
for _, s in ipairs(seatsMade) do
	seatBy[s:GetAttribute("SeesawSide")] = s
	local top = s.CFrame * v3(0, s.Size.Y / 2, 0)
	print(string.format("  %s side %d: top (authored) %s  look (authored) %s  offset %s", s.Name, s:GetAttribute("SeesawSide"),
		tostring(A(top)), tostring(HB.Rotation:Inverse() * s.CFrame.LookVector), tostring(s:GetAttribute("SeesawOffset"))))
end
--.. hand check: red pad top at the shipped pose. Level pad point (x, 0.40 + lift/S) about the pivot, dropped by 12 deg
local function PadTop(side, deg, x)
	local a = math.rad(deg)
	local lx, ly = side * x, 0.40 + 0.03 / S
	return v3(lx * math.cos(a) + ly * math.sin(a), 1.35 - lx * math.sin(a) + ly * math.cos(a), 0)
end
local xs = (3.06 * S - 0.6) / S
for side, s in pairs(seatBy) do
	local top = A(s.CFrame * v3(0, s.Size.Y / 2, 0))
	Check(string.format("server seat %d sits on its pad at the shipped pose (err %.5f)", side, (top - PadTop(side, 12, xs)).Magnitude), (top - PadTop(side, 12, xs)).Magnitude < 1e-4)
end

local cleanup = ClientB.Client(model, cctx)
local function run(seconds, fps, quiet)
	local dt = 1 / (fps or 60)
	local lo, hi = math.huge, -math.huge
	local t0, prev, jump, level = SIM_T, PlankAngle(), 0, nil
	for _ = 1, math.floor(seconds / dt + 0.5) do
		SIM_T += dt
		NOW += dt
		cctx._step(dt, NOW)
		local a = PlankAngle()
		lo, hi = math.min(lo, a), math.max(hi, a)
		jump = math.max(jump, math.abs(a - prev))
		if not level and prev * a <= 0 and prev ~= a then level = SIM_T - t0 end
		prev = a
	end
	if not quiet then print(string.format("  [run %.2fs] max step %.3f deg/frame, passes level after %s s", seconds, jump, level and string.format("%.3f", level) or "-")) end
	return lo, hi
end
local function SeatCheck(label)
	local ang = PlankAngle()
	local worst = 0
	for side, s in pairs(seatBy) do
		local top = A(s.CFrame * v3(0, s.Size.Y / 2, 0))
		worst = math.max(worst, (top - PadTop(side, ang, xs)).Magnitude)
	end
	Check(string.format("%s: seats follow the plank at %.2f deg (err %.5f)", label, ang, worst), worst < 1e-3)
end

run(1)
local e = 0
for p, c in pairs(original) do e = math.max(e, MaxErr(p.CFrame, c)) end
Check(string.format("rest: nothing moved (max err %.6f), angle %.3f", e, PlankAngle()), e < 1e-5)

--.. level pose check through the real rig: pose the plank at 0 by hand via the Kit
local pivot0 = CFrame.new(Kit.Pivot(model, "PlankPivot")) * Kit.Origin(model).Rotation
local rig = Kit.Rig({byName.PlankBeamRed, byName.PlankBeamBlue}, pivot0 * CFrame.Angles(0, 0, -math.rad(12)))
local save = {byName.PlankBeamRed.CFrame, byName.PlankBeamBlue.CFrame}
Kit.PoseRig(rig, pivot0)
print("  level pose: PlankBeamRed centre (authored) " .. tostring(A(byName.PlankBeamRed.CFrame.Position)) .. "  expect (1.90, 1.49, 0)")
print("  level pose: PlankBeamBlue centre (authored) " .. tostring(A(byName.PlankBeamBlue.CFrame.Position)) .. "  expect (-1.90, 1.49, 0)")
Check("level pose of the red beam matches the Blender geometry", (A(byName.PlankBeamRed.CFrame.Position) - v3(1.9, 1.49, 0)).Magnitude < 0.02)
Check("level pose of the blue beam matches the Blender geometry", (A(byName.PlankBeamBlue.CFrame.Position) - v3(-1.9, 1.49, 0)).Magnitude < 0.02)
byName.PlankBeamRed.CFrame, byName.PlankBeamBlue.CFrame = save[1], save[2]

--.. blue rider
local function Sit(side, userId)
	local s = seatBy[side]
	s.Occupant = userId and {Parent = {_player = {UserId = userId}}} or nil
	s:GetPropertyChangedSignal("Occupant"):Fire()
end
print("-- blue sits (t=" .. SIM_T .. ")")
Sit(-1, 222)
local lo, hi = run(2.5)
print(string.format("  angle range %.2f..%.2f, now %.2f", lo, hi, PlankAngle()))
Flush()
SeatCheck("hold blue")
Check("hold blue ends BlueDown", math.abs(PlankAngle() + 12) < 1e-3)

print("-- red sits -> ride (t=" .. SIM_T .. ")  Lead=" .. tostring(model:GetAttribute("Fun_Lead")))
Sit(1, 111)
lo, hi = run(1.1)
SeatCheck("ride 1.1 s")
lo, hi = run(5.5)
print(string.format("  angle range %.2f..%.2f", lo, hi))
SeatCheck("ride 6.6 s")
Flush()
Check("ride stays between the stops", lo >= -12.0001 and hi <= 12.0001)

print("-- red jumps off -> hold blue (t=" .. SIM_T .. ")")
Sit(1, nil)
run(2)
Flush()
Check("hold blue again ends BlueDown", math.abs(PlankAngle() + 12) < 1e-3)

print("-- blue jumps off -> rest (t=" .. SIM_T .. ")")
Sit(-1, nil)
run(5)
Flush()
Check("rest ends RedDown", math.abs(PlankAngle() - 12) < 1e-3)

print("-- blue sits, red sits 0.3 s later (t=" .. SIM_T .. ")")
Sit(-1, 31)
run(0.3)
Sit(1, 32)
print("  Lead=" .. tostring(model:GetAttribute("Fun_Lead")) .. " (expect 1: the plank is still nearer red)")
Check("quick double sit leads from red", model:GetAttribute("Fun_Lead") == 1)
run(2.2)
Flush()
Sit(1, nil)
Sit(-1, nil)
run(4)
Flush()
print("-- blue sits, red sits 1.2 s later")
Sit(-1, 41)
run(1.2)
Sit(1, 42)
Check("late double sit leads from blue", model:GetAttribute("Fun_Lead") == -1)
run(1)
Flush()
Sit(1, nil)
Sit(-1, nil)
run(4)
Flush()

--.. wake from a far camera mid-ride: snap
print("-- both sit, camera away 3 s, then back")
Sit(-1, 5)
Sit(1, 6)
run(0.5)
SIM_T += 3
NOW += 3
run(0.2)
Flush()
SeatCheck("after wake")

--.. the build is MOVED mid-ride: the server moves all parts (as shipped) and the hitbox
print("-- moved")
local HB2 = CFrame.new(-30, 5, 12) * CFrame.Angles(0, math.rad(-70), 0)
local delta = HB2 * HB:Inverse()
for _, p in ipairs(kids) do p.CFrame = delta * original[p] end
run(0.1)
local worstRel = 0
for p in pairs(original) do
	if p.Name:sub(1, 5) ~= "Plank" then worstRel = math.max(worstRel, MaxErr(p.CFrame, delta * original[p])) end
end
Check(string.format("moved: non-plank parts untouched (err %.6f)", worstRel), worstRel < 1e-5)
local oldHB = HB
HB = HB2
Check(string.format("moved: plank posed about the new pivot, angle %.2f", PlankAngle()), PlankAngle() >= -12.001 and PlankAngle() <= 12.001)
HB = oldHB

cleanup()
local worst = 0
for p in pairs(original) do worst = math.max(worst, MaxErr(p.CFrame, delta * original[p])) end
Check(string.format("cleanup: every part back as shipped at the new spot (err %.6f)", worst), worst < 1e-5)
