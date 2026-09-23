--[[---------------------------------------DESCRIPTION------------------------------------------
	R15 upper-body poses; degrees in standard R15 Motor6D local axes.

	Charge takes a loop phase (0 - 1) and a charge amount (0 - 1) and returns
	one CFrame per joint. Fire takes the time since release. Both read a profile
	from Profiles, so editing a profile changes the motion everywhere.

	TUNING sets how far the charge wind-up and the release swing go on top of
	each profile's base pose, sway and kick. The pad camera watches the
	character side-on from about 13 studs, so these have to be big enough to
	read at that distance: the old values (4-6 degrees of wind-up, a 20 degree
	flick over half a second) were invisible.

--------------------------------------------------------------------------------------------]]--

local Profiles = require(script.Parent.Profiles)

local Math = {}

Math.Joints = {
	"UpperTorso",
	"Head",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
}
Math.Profiles = Profiles

-- Scoop, flipper, catapult and sling throw the ball: they wind up low and
-- back, then swing up and forward. Everything else braces and recoils.
Math.TossFamilies = {
	scoop = true,
	flipper = true,
	catapult = true,
	sling = true,
}

Math.TUNING = {
	-- Charge wind-up: degrees added at 100% charge (scaled by the charge amount).
	WindupTorso = -8, -- lean back
	WindupHead = 4,
	WindupArmToss = -32, -- launcher arm: pulled low and back for a throw
	WindupArmOther = 26, -- launcher arm: raised to the aim line
	WindupElbow = 22, -- launcher elbow cocks
	WindupOffArm = 8, -- the other arm follows a little
	WindupOffElbow = 10,
	-- Charge loop sway: multiplies each profile's sway at 0% and at 100%.
	SwayIdle = 1.0, -- breathing while the launcher is just carried
	SwayFull = 2.4, -- shaking with tension at full charge
	-- Release: multiplies each profile's kick.
	KickToss = 2.6,
	KickOther = 1.8,
}

local function isToss(p)
	return Math.TossFamilies[p.family] == true
end

local function copy(base)
	local r = {}
	for i, a in ipairs(base) do
		r[i] = { a[1], a[2], a[3] }
	end
	return r
end

local function frames(r)
	local result = {}
	for i, name in ipairs(Math.Joints) do
		local a = r[i]
		result[name] = CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3]))
	end
	return result
end

local function chargeAngles(p, phase, q)
	local T = Math.TUNING
	local a = phase * 2 * math.pi
	local s, c, b = math.sin(a), math.cos(a), math.sin(2 * a)
	local amp = p.sway * (T.SwayIdle + (T.SwayFull - T.SwayIdle) * q)
	local windArm = if isToss(p) then T.WindupArmToss else T.WindupArmOther
	local r = copy(p.base)
	r[1][1] += T.WindupTorso * q + amp * 0.3 * s
	r[1][2] += amp * 0.25 * b
	r[2][1] += T.WindupHead * q - amp * 0.16 * s
	r[2][2] -= amp * 0.12 * b
	-- Launcher arm (right) and the off arm (left).
	r[3][1] += windArm * q + amp * s
	r[3][2] += amp * 0.45 * b
	r[3][3] += amp * 0.4 * c
	r[6][1] += T.WindupOffArm * q + amp * s
	r[6][2] += amp * 0.45 * b
	r[6][3] -= amp * 0.4 * c
	r[4][1] += T.WindupElbow * q + amp * 0.55 * s
	r[7][1] += T.WindupOffElbow * q + amp * 0.55 * s
	if p.family == "sling" then
		r[5][1] += amp * 2 * c
		r[5][3] += amp * 2 * s
	end
	if p.family == "bow" then
		r[7][1] += 12 * q
		r[6][2] += 8 * q
	end
	if p.family == "energy" then
		r[5][3] += amp * 0.65 * b
	end
	return r
end

function Math.Charge(p, phase, q)
	return frames(chargeAngles(p, phase % 1, math.clamp(q, 0, 1)))
end

local knots = { { 0, 0 }, { 0.09, -0.15 }, { 0.19, 0.25 }, { 0.30, 1 }, { 0.54, -0.16 }, { 0.74, 0.045 }, { 1, 0 } }

function Math.Fire(p, time, q)
	local T = Math.TUNING
	local x = math.clamp(time / p.duration, 0, 1)
	local v = 0
	for i = 1, #knots - 1 do
		local a, b = knots[i], knots[i + 1]
		if x >= a[1] and x <= b[1] then
			local t = (x - a[1]) / (b[1] - a[1])
			t = t * t * (3 - 2 * t)
			v = a[2] + (b[2] - a[2]) * t
			break
		end
	end
	local toss = isToss(p)
	local r = chargeAngles(p, 0, q)
	local k = v * p.kick * (0.4 + 0.6 * q) * (if toss then T.KickToss else T.KickOther)
	r[1][1] += k * 0.24
	r[1][2] -= k * 0.07
	r[2][1] -= k * 0.13
	r[3][1] += k * (toss and 1.25 or -0.7)
	r[4][1] += k * (toss and -0.8 or 0.7)
	r[5][1] += k * (toss and 0.7 or -0.35)
	r[6][1] += k * (toss and 0.7 or -0.55)
	r[7][1] += k * (toss and -0.4 or 0.45)
	if p.family == "sling" then
		r[1][2] += k * 0.8
		r[3][2] += k * 0.9
	end
	return frames(r)
end

return Math
