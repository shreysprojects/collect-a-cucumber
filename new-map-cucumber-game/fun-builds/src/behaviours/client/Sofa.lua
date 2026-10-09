--[[
	Sofa  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds HomeLiving
	Client half of the Sofa / Armchair (one module serves both keys). While Fun_Seat<i> (set by the server
	half) is non-zero, seat cushion Cushion<i> sits squashed - a little lower and a little wider - and the back
	cushion BackCushion<i> gives a touch toward the back. Both ride one springy value per seat, so sitting
	down plops the cushion past its rest squash and it wobbles back, and getting up over-puffs it for a moment.
	A real change (not the state found when the build streams in) also puffs a few soft fabric wisps off the
	cushion and plays a muffled poof.
	The squash goes through the cushion's SpecialMesh (Scale + Offset: the part itself never moves, so its
	collisions, the placement overlap test and the broken fade are untouched). A cushion without a
	SpecialMesh (a MeshPart from the merged-mesh route, models/export_mesh.py) is resized locally and placed
	from the Hitbox (hitbox CFrame * its authored offset * the squash shift), never nudged from its own
	CFrame, so a move while someone sits can't leave it off by the old squash. The held face (the bottom of a
	seat puff, the back of a back cushion) is found per part from the authored direction, so a MeshPart the
	importer yawed 180 degrees still flattens toward the back. Everything is restored in the cleanup.
	The seat pivots sit on the SQUASHED cushion top (couchlib.py REST_SQUASH = SQUASH_Y here): keep them equal.
	Parts / pivots: Cushion<i>, BackCushion<i> (fun-builds/models/couchlib.py); state Fun_Seat<i>.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

--..Config..--
local MAX_SEATS = 6
local SQUASH_Y = 0.3            -- the seat puff loses this share of its height at rest squash (x = 1) = couchlib REST_SQUASH
local BULGE_XZ = 0.05           -- ... and spreads this share sideways
local BACK_GIVE = 0.3           -- the back cushion's puff flattens this share of its depth (toward the back)
local SPRING_K = 170            -- spring stiffness (1/s^2)
local SPRING_C = 11             -- damping (1/s); critical is ~26, so it wobbles a couple of times
local SIT_KICK = 5              -- extra squash speed on sitting down (the plop past rest)
local STAND_KICK = -3.5         -- extra rebound speed on getting up (the over-puff)
local X_MIN, X_MAX = -0.6, 1.7  -- clamp on the spring value (x < 0 = puffed up taller than rest)
local SUBSTEP = 1 / 120
local POOF_SIT = 9              -- wisps on sitting down
local POOF_STAND = 4            -- wisps on getting up
local POOF_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local POOF_SOUND = FunAssets.Sfx.CushionPoof or FunAssets.Sfx.Whoosh
local POOF_VOLUME = 0.4

local BOTTOM = Vector3.new(0, -1, 0) -- held faces, AUTHORED directions: a seat puff keeps its bottom ...
local BACK = Vector3.new(0, 0, 1)    -- ... a back cushion its back (front = -Z)

local B = {}
B.Keys = {"Sofa", "Armchair"}
B.StepRange = 140

--..Squashable parts..--
--.. the part's local unit axis (+-X / Y / Z) nearest a world direction. A Parts-route cushion is a Block + SpecialMesh
--.. in its authored axes (the back cushion tilted 12 degrees); a merged-mesh MeshPart comes in axis-aligned and maybe
--.. yawed 180 degrees by the importer - so the held face is looked up, not assumed
local function NearestAxis(part, worldDir)
	local l = part.CFrame:VectorToObjectSpace(worldDir)
	local ax, ay, az = math.abs(l.X), math.abs(l.Y), math.abs(l.Z)
	if ax >= ay and ax >= az then return Vector3.new(l.X >= 0 and 1 or -1, 0, 0) end
	if ay >= az then return Vector3.new(0, l.Y >= 0 and 1 or -1, 0) end
	return Vector3.new(0, 0, l.Z >= 0 and 1 or -1)
end

--.. remember how a part looks now so it can be squashed along one local axis and restored exactly.
--.. `held` = the AUTHORED direction of the face that stays put
local function Squashable(model, part, held)
	if not part then return nil end
	local hitbox = Kit.Hitbox(model)
	local anchor = NearestAxis(part, Kit.Origin(model):VectorToWorldSpace(held))
	local s = {
		Part = part,
		Anchor = anchor,                                                  -- local unit axis of the held face
		Axis = Vector3.new(math.abs(anchor.X), math.abs(anchor.Y), math.abs(anchor.Z)), -- the squashed axis
		Size = part.Size,
		Mesh = part:FindFirstChildOfClass("SpecialMesh"),
	}
	if s.Mesh then
		s.Scale = s.Mesh.Scale
		s.Offset = s.Mesh.Offset
		s.Visual = part.Size * s.Mesh.Scale -- a Sphere / Brick SpecialMesh renders at Size * Scale
	else
		s.Visual = part.Size
		--.. the part's offset from the Hitbox: the server sets the Hitbox (moves included) and this client never nudges
		--.. it, so hitbox * Rel is always the part's true un-squashed place, even right after a move mid-squash
		s.Hitbox = hitbox
		s.Rel = hitbox and hitbox.CFrame:ToObjectSpace(part.CFrame) or part.CFrame
	end
	return s
end

--.. squash by `amount` (share of the size) along the held axis, that face held still, and spread by `spread` along the
--.. other two axes; amount < 0 puffs it up instead. Apply(s, 0, 0) = exactly as authored
local function Apply(s, amount, spread)
	if not s or not s.Part.Parent then return end
	local f = Vector3.one - s.Axis * amount + (Vector3.one - s.Axis) * spread
	local shift = s.Visual * s.Anchor * (amount * 0.5)
	if s.Mesh then
		s.Mesh.Scale = s.Scale * f
		s.Mesh.Offset = s.Offset + shift
	else
		s.Part.Size = s.Size * f
		s.Part.CFrame = (s.Hitbox and s.Hitbox.CFrame * s.Rel or s.Rel) * CFrame.new(shift)
	end
end

local function Restore(s)
	if s then Apply(s, 0, 0) end
end

--..Wisps + poof sound..--
local function MakePoof(ctx, puff)
	local scale = ctx.Scale
	local size = puff.Size
	local holder = ctx:Part({
		Name = "SofaPoof",
		Size = Vector3.new(math.max(size.X * 0.8, 0.2), 0.2, math.max(size.Z * 0.7, 0.2)),
		CFrame = puff.CFrame * CFrame.new(0, size.Y * 0.25, 0),
		Transparency = 1,
	})
	local e = Instance.new("ParticleEmitter")
	e.Name = "Wisps"
	e.Texture = POOF_TEXTURE
	e.Enabled = false -- burst only (Emit)
	e.Rate = 0
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Top
	e.Lifetime = NumberRange.new(0.45, 0.85)
	e.Speed = NumberRange.new(2.5 * scale, 5 * scale)
	e.SpreadAngle = Vector2.new(75, 75)
	e.Drag = 5
	e.Acceleration = Vector3.new(0, 1.5 * scale, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35 * scale), NumberSequenceKeypoint.new(1, 1.1 * scale)})
	e.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.6, 0.6), NumberSequenceKeypoint.new(1, 1)})
	e.Color = ColorSequence.new(puff.Color:Lerp(Color3.new(1, 1, 1), 0.7))
	e.LightEmission = 0.05
	e.ZOffset = 0.4
	e.Parent = holder
	local sound = ctx:Sound(holder, POOF_SOUND, {Name = "Poof", Volume = POOF_VOLUME, RollOffMaxDistance = 60})
	return e, sound
end

--..Behaviour..--
function B.Client(model, ctx)
	local seats = {}
	for i = 1, MAX_SEATS do
		local puff = Kit.Part(model, "Cushion" .. i)
		if not puff then break end
		local seat = {
			Index = i,
			Puff = Squashable(model, puff, BOTTOM),
			Back = Squashable(model, Kit.Part(model, "BackCushion" .. i), BACK),
			X = 0, V = 0, Target = 0, Moving = false, Seen = false,
		}
		seat.Emitter, seat.Sound = MakePoof(ctx, puff)
		seats[i] = seat
	end
	if #seats == 0 then return end

	local function Pose(seat)
		local x = seat.X
		Apply(seat.Puff, SQUASH_Y * x, BULGE_XZ * x)
		if seat.Back then
			local give = math.max(x, 0) * BACK_GIVE
			Apply(seat.Back, give, give * 0.15)
		end
	end

	local function Poof(seat, sitting)
		local emitter, sound = seat.Emitter, seat.Sound
		if emitter and emitter.Parent then
			pcall(emitter.Emit, emitter, sitting and POOF_SIT or POOF_STAND)
		end
		if sound and sound.Parent then
			sound.PlaybackSpeed = (sitting and 0.6 or 0.8) * (0.95 + math.random() * 0.1)
			sound.Volume = sitting and POOF_VOLUME or POOF_VOLUME * 0.6
			sound.TimePosition = 0
			sound:Play()
		end
	end

	for _, seat in ipairs(seats) do
		ctx:OnState("Seat" .. seat.Index, function(value)
			if not ctx:Alive() then return end
			local taken = type(value) == "number" and value ~= 0
			local target = taken and 1 or 0
			local first = not seat.Seen
			seat.Seen = true
			if target == seat.Target and not first then return end
			seat.Target = target
			if first or ctx:CameraDistance() > B.StepRange then
				--.. found this way on stream-in (or nobody near enough to watch): just be there
				seat.X, seat.V, seat.Moving = target, 0, false
				Pose(seat)
				return
			end
			seat.V += taken and SIT_KICK or STAND_KICK
			seat.Moving = true
			Poof(seat, taken)
		end)
	end

	--.. one Step for every cushion; only springs still settling do any work
	ctx:Step(function(dt)
		dt = math.min(dt, 1 / 20)
		local steps = math.max(1, math.ceil(dt / SUBSTEP))
		local h = dt / steps
		for _, seat in ipairs(seats) do
			if seat.Moving then
				local x, v = seat.X, seat.V
				for _ = 1, steps do
					v += (SPRING_K * (seat.Target - x) - SPRING_C * v) * h
					x = math.clamp(x + v * h, X_MIN, X_MAX)
				end
				if math.abs(x - seat.Target) < 0.002 and math.abs(v) < 0.02 then
					x, v, seat.Moving = seat.Target, 0, false
				end
				seat.X, seat.V = x, v
				Pose(seat)
			end
		end
	end)

	return function()
		for _, seat in ipairs(seats) do
			Restore(seat.Puff)
			Restore(seat.Back)
		end
	end
end

return B
