--[[
	Sunflower  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds package GardenLife
	Client-only behaviour for the three sunflowers (no server half: the sun and the clock are the same everywhere).
	  Sunflower_A Tall   Sunflower_B Medium (bud on a side shoot)   Sunflower_C Clump (three heads, one mound); all x1.5
	  * NOD: the head parts (<V>_Disc(s), <V>_PetalsYellow, <V>_PetalsOrange) nod a few degrees about the neck
	    (Pivot_A_Neck / Pivot_B_Neck; the Clump's three heads are ONE merged mesh, so they nod about the middle of
	    Pivot_C_Neck1..3, and only a little).
	  * SUN: the plant turns toward Lighting:GetSunDirection() - a slow turntable yaw of the whole plant about its
	    stem foot (so the leaves, the side-shoot bud and the Clump's three stems stay attached) plus a lift of the
	    head about the neck toward the sun's height; together never more than 25 degrees (YAW 22 + PITCH 8). A sun
	    behind the flower fades the yaw back to zero instead of flipping side to side. At night (sun under the
	    horizon or workspace CyclePhase == "Night") the flower faces front and the head droops.
	    The turn is eased (TURN_TAU) so it creeps; a flower that was off screen / asleep snaps to its target.
	  * WIND: the same map-wide wind as the trees rocks the whole plant a degree or two (server clock -> in sync).
	  The Clump's mound never moves. Everything is posed with one BulkMoveTo from one ctx:Step, every frame near the
	  camera, at FAR_HZ beyond NEAR, not while off screen. Cleanup puts every part back at rest relative to the
	  build's CURRENT hitbox.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local WIND = Vector3.new(0.83, 0, 0.56).Unit      -- the map-wide wind (same as Tree / Bush)
local WIND_AXIS = Vector3.yAxis:Cross(WIND).Unit
local NEAR = 70                  -- studs camera -> flower: posed every frame closer than this ...
local FAR_HZ = 15                -- ... and this often farther away
local CLOSE = 25                 -- always posed this close
local TURN_TAU = 5               -- seconds: how lazily the flower follows the sun
local SNAP_GAP = 1.5             -- not posed for this long (asleep / off screen): jump straight to the sun target
local HEAD = {"Disc", "Petals"}  -- part names (after the variant prefix) that nod about the neck
local STATIC = {"Mound"}         -- never move

--.. per variant: Base = stem foot (AUTHORED, the turntable axis), Necks = pivot names averaged into the nod pivot,
--.. degrees: Yaw / Pitch = max sun turn / lift, Droop = night hang, Nod = nod amplitude, Sway = wind lean
local FLOWERS = {
	A = {Base = Vector3.new(5, 0, 0), Necks = {"A_Neck"}, Yaw = 22, Pitch = 8, Droop = 9, Nod = 3.5, Sway = 1.8},
	B = {Base = Vector3.new(0, 0, 0), Necks = {"B_Neck"}, Yaw = 22, Pitch = 8, Droop = 9, Nod = 3.5, Sway = 2},
	C = {Base = Vector3.new(-5.4, 0, 0), Necks = {"C_Neck1", "C_Neck2", "C_Neck3"}, Yaw = 22, Pitch = 4, Droop = 4,
		Nod = 2, Sway = 1.2},
}
local DEFAULT_FLOWER = {Necks = {"Neck"}, Yaw = 22, Pitch = 6, Droop = 6, Nod = 3, Sway = 1.5}

local B = {}
B.StepRange = 140

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

local function HasWord(name, words)
	for _, word in ipairs(words) do
		if name:find(word, 1, true) then return true end
	end
	return false
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

local function IsNight()
	return workspace:GetAttribute("CyclePhase") == "Night"
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	local cfg = FLOWERS[ctx.Variant or ""] or DEFAULT_FLOWER
	local prefix = ctx.Variant and (ctx.Variant .. "_") or ""
	local home = hitbox.CFrame

	--..Parts: head parts nod on the plant, the rest turns with the plant, the mound stays..--
	local parts, rel, isHead = {}, {}, {}
	local headSum, headCount = Vector3.zero, 0
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= hitbox and part.Name:sub(1, #prefix) == prefix then
			local name = part.Name:sub(#prefix + 1)
			if not HasWord(name, STATIC) then
				table.insert(parts, part)
				table.insert(rel, home:ToObjectSpace(part.CFrame))
				local head = HasWord(name, HEAD)
				table.insert(isHead, head)
				if head then
					headSum += part.Position
					headCount += 1
				end
			end
		end
	end
	if #parts == 0 then return end
	local rest = {}
	for i, r in ipairs(rel) do rest[i] = home * r end

	--..Pivots..--
	local origin = Kit.Origin(model)
	local frame = origin.Rotation       -- the build's own axes: front = LookVector (authored -Z)
	local right = origin.RightVector    -- the nod / lift axis
	local baseAuthored = cfg.Base
	if not baseAuthored then
		local c = Kit.AuthoredCentre(model)
		baseAuthored = Vector3.new(c.X, 0, c.Z)
	end
	local base = Kit.ToWorld(model, baseAuthored)
	local neckSum, neckCount = Vector3.zero, 0
	for _, name in ipairs(cfg.Necks) do
		local p = Kit.Pivot(model, name)
		if p then
			neckSum += p
			neckCount += 1
		end
	end
	local neck
	if neckCount > 0 then
		neck = neckSum / neckCount
	elseif headCount > 0 then
		neck = headSum / headCount - Vector3.yAxis * (0.15 * ctx.Scale)
	else
		neck = base
	end
	local centre = headCount > 0 and headSum / headCount or neck

	--..Motion constants (per build, from where it stands)..--
	local where = home.Position
	local swayW = 2 * math.pi / (3 + 2 * PlaceHash(where, 1))
	local swayPhase = -where:Dot(WIND) * 0.07 + PlaceHash(where, 2) * 2 * math.pi
	local nodW = 2 * math.pi / (2.6 + PlaceHash(where, 3))
	local nodPhase = PlaceHash(where, 4) * 2 * math.pi
	local maxYaw, maxPitch = math.rad(cfg.Yaw), math.rad(cfg.Pitch)
	local droop, nodAmp, swayAmp = math.rad(cfg.Droop), math.rad(cfg.Nod), math.rad(cfg.Sway)
	local FADE_FROM, FADE_SPAN = math.rad(150), math.rad(60)

	--.. where the sun asks the flower to look: yaw (about the stem foot) and lift (about the neck), radians
	local function SunTarget()
		local sun = frame:VectorToObjectSpace(Lighting:GetSunDirection())
		local day = IsNight() and 0 or math.clamp((sun.Y + 0.05) / 0.15, 0, 1) -- 0 below the horizon .. 1 once it is up
		if day <= 0 then return 0, -droop end
		local flat = math.sqrt(sun.X * sun.X + sun.Z * sun.Z)
		local psi = flat > 1e-4 and math.atan2(-sun.X, -sun.Z) or 0 -- 0 = the sun straight in front
		local behind = math.clamp((FADE_FROM - math.abs(psi)) / FADE_SPAN, 0, 1) -- a sun behind: no flip-flopping
		local high = math.clamp(flat / 0.35, 0, 1) -- a sun near the zenith has no side to turn to
		local yaw = math.clamp(psi, -maxYaw, maxYaw) * behind * high
		local lift = math.clamp(math.atan2(sun.Y, flat) * 0.45, 0, maxPitch)
		return yaw * day, lift * day - droop * (1 - day)
	end

	--..Step..--
	local yaw, lift = 0, 0
	local lastPose, posed = -math.huge, false
	local list, cfs = table.clone(parts), {}
	ctx:Step(function(_, now)
		if not (hitbox.Parent and SameCFrame(hitbox.CFrame, home)) then return end -- moved: the restart is on its way
		local c = os.clock()
		local dist = ctx:CameraDistance()
		local gap = c - lastPose
		if dist > NEAR and gap < 1 / FAR_HZ then return end
		if dist > CLOSE and not OnScreen(centre, 0.25) then return end
		lastPose, posed = c, true

		--.. ease toward the sun (snap after a long gap: nobody watched it turn)
		local yawT, liftT = SunTarget()
		local k = gap > SNAP_GAP and 1 or 1 - math.exp(-gap / TURN_TAU)
		yaw += (yawT - yaw) * k
		lift += (liftT - lift) * k

		local lean = swayAmp * (0.35 + 0.65 * (0.7 * math.sin(swayW * now + swayPhase) + 0.3 * math.sin(2.37 * swayW * now + 1.7 * swayPhase)))
		local nod = nodAmp * math.sin(nodW * now + nodPhase)
		local plant = CFrame.new(base) * CFrame.fromAxisAngle(WIND_AXIS, lean) * CFrame.fromAxisAngle(Vector3.yAxis, yaw)
			* CFrame.new(-base)
		local head = plant * CFrame.new(neck) * CFrame.fromAxisAngle(right, lift + nod) * CFrame.new(-neck)
		for i in ipairs(parts) do
			cfs[i] = (isHead[i] and head or plant) * rest[i]
		end
		workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)

	--..Cleanup: back at rest (relative to wherever the hitbox is now)..--
	return function()
		if not (posed and model:IsDescendantOf(workspace) and hitbox.Parent) then return end
		local now = hitbox.CFrame
		for i, part in ipairs(parts) do
			if part.Parent then part.CFrame = now * rel[i] end
		end
	end
end

return B
