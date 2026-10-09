--[[
	Scarecrow  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLife
	The crow on the scarecrow's arm comes alive (Scarecrow x1.35). The authored Crow / CrowBeak meshes are hidden
	locally and a little part-built crow takes their place on Pivot_CrowPerch (the body centre of the authored one):
	body, head, tail and two hinged wings (SpecialMesh spheres), a wedge beak and two eye glints - 8 local parts
	(ctx:Part, under the camera), ~1.3 studs long in game.
	  * PERCHED: breathes (a small bob), and in SLOT s slots picked from the server clock + a per-build seed (so
	    every client shows the same bird doing the same thing) it idles, looks round (and caws now and then),
	    pecks, flaps its wings (FunAssets.Sfx.Whoosh) or hops between two spots on the sleeve, turning as it lands.
	  * SCARED: the server half (ServerStorage.FunBehaviours.Scarecrow) publishes Fun_CrowLeft / Fun_CrowBack /
	    Fun_CrowDir when a player comes within 8 studs. Every client then flies the crow off on a climbing, curving
	    arc away from that player (FLY_OUT s, fading out far away), keeps it gone, and RETURN_T s before
	    Fun_CrowBack flies it back in from roughly the same side: a glide, a nose-up flare, wings folded, perched.
	    Take-off: whoosh + caw; landing: whoosh.
	  * The caw is FunAssets.Sfx.Caw - not in FunAssets yet (no verified crow sound), so the crow is silent but for
	    its wings until the integrator adds one. Sounds respect the player's SFXEnabled attribute.
	One ctx:Step (the crow is posed with one BulkMoveTo, skipped while it is off screen). Cleanup shows the
	authored crow again (only if nobody else changed its Transparency meanwhile, e.g. the broken fade).
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
local FACING = Vector3.new(-0.77, 0, -0.64).Unit -- AUTHORED heading of the perched crow: beak out along the arm, a bit to the front
local ARM_IN = Vector3.new(math.cos(math.rad(6)), -math.sin(math.rad(6)), 0) -- AUTHORED: along the 6-deg arm toward the shoulder
local HOP_STEP = 0.2             -- AUTHORED studs between the two perch spots on the sleeve
local HIDE = {"Crow", "CrowBeak"} -- the authored crow, hidden while this runs
local GHOST = {"Frame", "Burlap"} -- a build part whose LocalTransparencyModifier (build-mode move ghost) the crow copies
local SLOT = 2.4                 -- seconds per idle action slot
local HOP_T, HOP_H = 0.45, 0.3   -- hop time (s) and height (AUTHORED studs)
local LOOK_T, PECK_T, FLAP_T = 1.6, 0.9, 1.0
local HEADINGS = {0, -0.55, 0.5, 0.25} -- radians off the authored heading a hop can land on
local SETTLE_SEARCH = 16         -- slots searched back for the last hop
local CAW_CHANCE = 0.45          -- of the "look" slots
local FLY_OUT, RETURN_T = 2.6, 2.8 -- seconds; RETURN_T must match the server half's RETURN_T
local FLY_DIST, FLY_CLIMB, FLY_CURVE = 50, 18, 12 -- world studs the flight covers away / up / sideways
local FLAP_HZ = 6
local NEAR_SOUND = 80            -- no crow sounds with the camera farther than this
local CLOSE = 30                 -- always posed this close, on screen or not

--..The crow (AUTHORED studs, x ctx.Scale). Crow frame: origin = body centre (= Pivot_CrowPerch), -Z = the beak's way..--
local BLACK = Color3.fromRGB(35, 38, 44)   -- 23262c, like the authored crow
local SHEEN = Color3.fromRGB(44, 49, 61)   -- 2c313d: blue-black wings and tail, a shade off the body
local BEAK = Color3.fromRGB(242, 193, 61)  -- f2c13d, like the authored CrowBeak
local EYE = Color3.fromRGB(242, 240, 234)
local NECK = Vector3.new(0, 0.12, -0.2)    -- the head turns / pecks about this
local SPHERE, WEDGE = Enum.MeshType.Sphere, Enum.MeshType.Wedge
local CROW = {
	{Name = "Body", Mesh = SPHERE, Size = Vector3.new(0.4, 0.38, 0.62), CFrame = CFrame.new(0, 0, 0.02) * CFrame.Angles(math.rad(16), 0, 0), Color = BLACK},
	{Name = "Head", Mesh = SPHERE, Size = Vector3.new(0.3, 0.3, 0.3), CFrame = CFrame.new(0, 0.2, -0.28), Color = BLACK, Head = true},
	{Name = "Beak", Mesh = WEDGE, Size = Vector3.new(0.09, 0.08, 0.2), CFrame = CFrame.new(0, 0.18, -0.5) * CFrame.Angles(math.rad(-6), 0, 0), Color = BEAK, Head = true},
	{Name = "EyeL", Mesh = SPHERE, Size = Vector3.new(0.065, 0.065, 0.065), CFrame = CFrame.new(-0.105, 0.245, -0.38), Color = EYE, Head = true},
	{Name = "EyeR", Mesh = SPHERE, Size = Vector3.new(0.065, 0.065, 0.065), CFrame = CFrame.new(0.105, 0.245, -0.38), Color = EYE, Head = true},
	{Name = "Tail", Mesh = SPHERE, Size = Vector3.new(0.18, 0.05, 0.34), CFrame = CFrame.new(0, -0.05, 0.4) * CFrame.Angles(math.rad(12), 0, 0), Color = SHEEN},
	{Name = "WingL", Mesh = SPHERE, Size = Vector3.new(0.06, 0.24, 0.5), Color = SHEEN, Wing = -1},
	{Name = "WingR", Mesh = SPHERE, Size = Vector3.new(0.06, 0.24, 0.5), Color = SHEEN, Wing = 1},
}
--.. a spread wing: the oval's long side (Z) points out along the span, its 0.24 side (Y) is the chord
local SPREAD = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.zAxis, Vector3.xAxis)

local B = {}
B.StepRange = 150

--..Helpers..--
local function Mul32(a, b)
	local hi, lo = math.floor(a / 65536), a % 65536
	return ((hi * b) % 65536 * 65536 + lo * b) % 4294967296
end

--.. integer hash -> 0..1, identical on every client
local function Hash(k, salt)
	local x = (math.floor(k) * 2 + salt * 40503 + 1) % 4294967296
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = Mul32(x, 0x45D9F3B)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = Mul32(x, 0x45D9F3B)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x / 4294967296
end

local function PlaceHash(p, salt)
	return Hash((math.floor(p.X * 8) % 65536) * 65536 + math.floor(p.Z * 8) % 65536, salt)
end

local function SameCFrame(a, b)
	return (a.Position - b.Position).Magnitude < 1e-3 and a.LookVector:Dot(b.LookVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
end

local function OnScreen(point, margin)
	local cam = workspace.CurrentCamera
	if not cam then return false end
	local v = cam:WorldToViewportPoint(point)
	if v.Z <= 0 then return false end
	local size = cam.ViewportSize
	local mx, my = size.X * margin, size.Y * margin
	return v.X >= -mx and v.X <= size.X + mx and v.Y >= -my and v.Y <= size.Y + my
end

local function Smooth(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

--.. 0 -> 1 over `ramp` s, holds, 1 -> 0 over the last `ramp` s of a `length` s action
local function Envelope(tau, length, ramp)
	return Smooth(math.min(tau / ramp, (length - tau) / ramp))
end

local function LerpAngle(a, b, t)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

--.. a point on the flight arc, v = 0 at the perch .. 1 far away (climbs off the perch first, then speeds away)
local function Arc(from, dir, side, v)
	return from + dir * (FLY_DIST * v * v + 3 * v) + side * (FLY_CURVE * v * v)
		+ Vector3.yAxis * (FLY_CLIMB * v * v + 2.2 * math.sin(math.min(v * 3, 1) * math.pi * 0.5))
end

--.. the crow's root flying along vel (yaw blended toward yawTo by `blend`, pitch scaled by pitchScale, + extra)
local function Flying(pos, vel, yawTo, blend, pitchScale, extraPitch)
	local flat = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
	local yaw = flat > 1e-5 and math.atan2(-vel.X, -vel.Z) or yawTo
	yaw = LerpAngle(yaw, yawTo, blend)
	local pitch = math.clamp(math.atan2(vel.Y, math.max(flat, 1e-5)), -0.5, 0.6) * pitchScale + extraPitch
	return CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	local home = hitbox.CFrame
	local s = ctx.Scale
	local authored = Kit.Part(model, "Crow")
	local perch = Kit.Pivot(model, "CrowPerch") or (authored and authored.Position)
	if not perch then return end
	local origin = Kit.Origin(model)
	local facing = origin:VectorToWorldSpace(FACING)
	local baseYaw = math.atan2(-facing.X, -facing.Z)
	local spots = {[0] = perch, [1] = perch + origin:VectorToWorldSpace(ARM_IN) * (HOP_STEP * s)}

	--..Hide the authored crow (put back on cleanup)..--
	local hidden = {}
	for _, name in ipairs(HIDE) do
		local part = Kit.Part(model, name)
		if part then
			hidden[part] = part.Transparency
			part.Transparency = 1
		end
	end
	local ghost
	for _, name in ipairs(GHOST) do ghost = ghost or Kit.Part(model, name) end

	--..Build the crow..--
	local folder = ctx:Add(Instance.new("Model"))
	folder.Name = "FunCrow"
	folder.Parent = workspace.CurrentCamera
	local parts, locals, isHead, wing = {}, {}, {}, {}
	for i, def in ipairs(CROW) do
		local part = ctx:Part({Name = "Crow" .. def.Name, Size = def.Size * s, Color = def.Color,
			Material = Enum.Material.SmoothPlastic, Transparency = 1, CFrame = CFrame.new(perch), Parent = folder})
		if def.Mesh then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = def.Mesh
			mesh.Parent = part
		end
		parts[i] = part
		locals[i] = def.CFrame and (CFrame.new(def.CFrame.Position * s) * def.CFrame.Rotation) or CFrame.identity
		isHead[i] = def.Head == true
		wing[i] = def.Wing
	end
	local neckIn, neckOut = CFrame.new(NECK * s), CFrame.new(-NECK * s)
	local folded = {}
	for _, side in ipairs({-1, 1}) do
		folded[side] = CFrame.new(side * 0.17 * s, 0.04 * s, 0.1 * s) * CFrame.Angles(math.rad(14), 0, side * math.rad(12))
	end
	local function WingCF(side, alpha, flap)
		if alpha <= 0.001 then return folded[side] end
		local spread = CFrame.new(side * 0.15 * s, 0.1 * s, -0.02 * s) * CFrame.Angles(0, 0, side * flap)
			* CFrame.new(side * 0.25 * s, 0, 0) * SPREAD
		return folded[side]:Lerp(spread, math.min(alpha, 1))
	end
	local cfs = {}
	local function Pose(root, alpha, flap, headPitch, headYaw)
		local head = root * neckIn * CFrame.Angles(0, headYaw, 0) * CFrame.Angles(headPitch, 0, 0) * neckOut
		for i, part in ipairs(parts) do
			if wing[i] then
				cfs[i] = root * WingCF(wing[i], alpha, flap)
			elseif isHead[i] then
				cfs[i] = head * locals[i]
			else
				cfs[i] = root * locals[i]
			end
			if not part.Parent then return end
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local shown = -1
	local function Show(fade)
		local g = ghost and ghost.LocalTransparencyModifier or 0
		local t = 1 - (1 - fade) * (1 - g)
		if t == shown or (t > 0.005 and t < 0.995 and math.abs(t - shown) < 0.01) then return end
		shown = t
		for _, part in ipairs(parts) do part.Transparency = t end
	end

	--..Sounds..--
	local body = parts[1]
	local flapSound = ctx:Sound(body, FunAssets.Sfx.Whoosh, {Volume = 0.35})
	local cawSound = FunAssets.Sfx.Caw and ctx:Sound(body, FunAssets.Sfx.Caw, {Volume = 0.6}) or nil
	local function Play(sound, volume, speed)
		if not sound or player:GetAttribute("SFXEnabled") == false then return end
		if ctx:CameraDistance() > NEAR_SOUND then return end
		sound.Volume = volume
		sound.PlaybackSpeed = speed
		sound:Play()
	end

	--..Idle actions: slot k of the server clock (+ a per-build offset) -> one action, the same on every client..--
	local where = home.Position
	local offset = PlaceHash(where, 5)
	local seed = math.floor(PlaceHash(where, 6) * 1000000)
	local function SlotAt(t)
		local kf = t / SLOT + offset
		local k = math.floor(kf)
		return k, (kf - k) * SLOT
	end
	local function SlotStart(k) return (k - offset) * SLOT end
	local function ActionOf(k)
		local r = Hash(k + seed, 1)
		if r < 0.36 then return "idle" elseif r < 0.58 then return "look" elseif r < 0.7 then return "peck"
		elseif r < 0.84 then return "flap" end
		return "hop"
	end
	local function HopTarget(k)
		local spot = Hash(k + seed, 3) < 0.5 and 0 or 1
		return spot, HEADINGS[1 + math.floor(Hash(k + seed, 4) * #HEADINGS)]
	end
	--.. where the crow sits at the start of slot k: the landing of the last hop before it, never counting slots
	--.. that began before `since` (its last landing on the perch)
	local cacheK, cacheSince, cacheSpot, cacheHeading
	local function SettledAt(k, since)
		if k == cacheK and since == cacheSince then return cacheSpot, cacheHeading end
		local spot, heading = 0, 0
		for j = k - 1, k - SETTLE_SEARCH, -1 do
			if SlotStart(j) < since then break end
			if ActionOf(j) == "hop" then
				spot, heading = HopTarget(j)
				break
			end
		end
		cacheK, cacheSince, cacheSpot, cacheHeading = k, since, spot, heading
		return spot, heading
	end
	local function Caws(k) return Hash(k + seed, 5) < CAW_CHANCE end

	--.. the perched crow at server time t, perched since `since`:
	--.. root CFrame, wing spread 0..1, flap angle, head pitch, head yaw, slot, action, time into the slot
	local function Perched(t, since)
		local k, tau = SlotAt(t)
		local spot, heading = SettledAt(k, since)
		local action = SlotStart(k) >= since and ActionOf(k) or "idle"
		local alpha, flap, pitch, yaw = 0, 0, 0, 0
		local bob = Vector3.yAxis * (0.012 * s * math.sin(t * 5.1 + offset * 20))
		local root
		if action == "hop" then
			local spot2, heading2 = HopTarget(k)
			if tau < HOP_T then
				local u = tau / HOP_T
				local e = Smooth(u)
				local pos = spots[spot]:Lerp(spots[spot2], e) + Vector3.yAxis * (HOP_H * s * math.sin(math.pi * u))
				root = CFrame.new(pos) * CFrame.Angles(0, baseYaw + heading + (heading2 - heading) * e, 0)
				alpha = 0.55 * math.sin(math.pi * u)
				flap = math.rad(30) * math.sin(u * 4 * math.pi)
			else
				root = CFrame.new(spots[spot2] + bob) * CFrame.Angles(0, baseYaw + heading2, 0)
			end
		else
			root = CFrame.new(spots[spot] + bob) * CFrame.Angles(0, baseYaw + heading, 0)
			if action == "look" and tau < LOOK_T then
				local side = Hash(k + seed, 2) < 0.5 and -1 or 1
				yaw = side * math.rad(42) * Envelope(tau, LOOK_T, 0.15)
				if Caws(k) and tau > 0.2 and tau < 0.6 then pitch = math.rad(18) * Envelope(tau - 0.2, 0.4, 0.1) end
			elseif action == "peck" and tau < PECK_T then
				pitch = -math.rad(38) * math.abs(math.sin(math.pi * tau / (PECK_T / 2)))
			elseif action == "flap" and tau < FLAP_T then
				alpha = Envelope(tau, FLAP_T, 0.12)
				flap = math.rad(10) + math.rad(32) * math.sin(2 * math.pi * 4 * tau)
				root = root + Vector3.yAxis * (0.05 * s * alpha)
			end
		end
		return root, alpha, flap, pitch, yaw, k, action, tau
	end

	--..Update: pick the phase from the server's state, pose, sounds..--
	local perchedSince = 0              -- the last Fun_CrowBack seen while perched (the landing before a take-off)
	local tripLeft, tripStart, tripYaw, tripDir, tripSide
	local homeBack, homeDir, homeSide
	local soundSlot, cawSlot, soundLeft, soundBack = nil, nil, nil, nil
	local function Update(now)
		local left = tonumber(ctx:State("CrowLeft")) or 0
		local back = tonumber(ctx:State("CrowBack")) or 0
		local dirAng = tonumber(ctx:State("CrowDir")) or 0
		local root, alpha, flap, pitch, yaw, fade = nil, 0, 0, 0, 0, 0
		if now < left + FLY_OUT then
			--..Flying off..--
			if tripLeft ~= left then
				tripLeft = left
				local start = Perched(left, perchedSince)
				tripStart = start.Position
				local _, ry = start:ToOrientation()
				tripYaw = ry
				tripDir = Vector3.new(math.sin(dirAng), 0, math.cos(dirAng))
				tripSide = Vector3.new(tripDir.Z, 0, -tripDir.X) * (Hash(math.floor(left * 10), 7) < 0.5 and -1 or 1)
			end
			local u = math.max(now - left, 0) / FLY_OUT
			local pos = Arc(tripStart, tripDir, tripSide, u)
			root = Flying(pos, Arc(tripStart, tripDir, tripSide, u + 0.01) - pos, tripYaw, 1 - Smooth(u / 0.2), math.min(u / 0.06, 1), 0)
			alpha = math.min(1, u / 0.04)
			flap = math.rad(6) + math.rad(38) * math.sin(2 * math.pi * FLAP_HZ * (now - left))
			fade = math.clamp((u - 0.72) / 0.28, 0, 1)
			if soundLeft ~= left then
				soundLeft = left
				if now - left < 0.4 then
					Play(flapSound, 0.55, 1.1)
					Play(cawSound, 0.6, 1)
				end
			end
		elseif now < back - RETURN_T then
			--..Gone..--
			Show(1)
			return
		elseif now < back then
			--..Flying home, landing on spot 0 with the authored heading..--
			if homeBack ~= back then
				homeBack = back
				local from = dirAng + (Hash(math.floor(back * 10), 8) - 0.5) * 2.2
				homeDir = Vector3.new(math.sin(from), 0, math.cos(from))
				homeSide = Vector3.new(homeDir.Z, 0, -homeDir.X) * (Hash(math.floor(back * 10), 9) < 0.5 and -1 or 1)
			end
			local u = math.clamp((now - (back - RETURN_T)) / RETURN_T, 0, 1)
			local v = 1 - u
			local pos = Arc(spots[0], homeDir, homeSide, v)
			local vel = Arc(spots[0], homeDir, homeSide, math.max(v - 0.01, 0)) - pos
			local landing = Smooth((u - 0.8) / 0.2)
			local flare = 0.45 * math.sin(math.pi * math.clamp((u - 0.8) / 0.2, 0, 1))
			root = Flying(pos, vel, baseYaw, landing, 1 - landing, flare)
			local glide = math.clamp((u - 0.7) / 0.12, 0, 1)
			alpha = u < 0.95 and 1 or (1 - u) / 0.05
			flap = (math.rad(6) + math.rad(38) * math.sin(2 * math.pi * FLAP_HZ * now)) * (1 - glide) + math.rad(14) * glide
			fade = math.clamp(1 - u / 0.22, 0, 1)
			if u >= 0.86 and soundBack ~= back then
				soundBack = back
				Play(flapSound, 0.45, 1.25)
			end
		else
			--..Perched..--
			perchedSince = back
			local k, action, tau
			root, alpha, flap, pitch, yaw, k, action, tau = Perched(now, back)
			if action == "flap" and soundSlot ~= k and tau < 0.3 then
				soundSlot = k
				Play(flapSound, 0.3, 1.35)
			elseif action == "look" and cawSlot ~= k and Caws(k) and tau >= 0.2 and tau < 0.5 then
				cawSlot = k
				Play(cawSound, 0.5, 0.95 + Hash(k + seed, 6) * 0.15)
			end
		end
		Show(fade)
		if ctx:CameraDistance() > CLOSE and not OnScreen(root.Position, 0.2) then return end
		Pose(root, alpha, flap, pitch, yaw)
	end

	ctx:Step(function(_, now)
		if not (hitbox.Parent and SameCFrame(hitbox.CFrame, home)) then return end -- moved: the restart is on its way
		Update(now)
	end)
	--.. seat it on the perch right away (the Step may be asleep if the camera is far)
	local ok, err = pcall(Update, Kit.Now())
	if not ok then warn("[Scarecrow] first pose: " .. tostring(err)) end

	--..Cleanup: the authored crow comes back (unless the server changed it meanwhile, e.g. the broken fade)..--
	return function()
		for part, transparency in pairs(hidden) do
			if part.Parent and part.Transparency == 1 then part.Transparency = transparency end
		end
	end
end

return B
