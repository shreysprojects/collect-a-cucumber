--[[
	BeanBag  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the functional bean bags (server half: ServerStorage.FunBehaviours.BeanBag) - serves
	BeanBag_A (Pouf), BeanBag_B (Slouch) and BeanBag_C (Ottoman).
	  * while someone sits (Fun_Occupied) the bag squashes: every part of the variant is scaled about the
	    floor point under the bag - Y x SQUASH_Y, X/Z x SQUASH_XZ - by resizing each part in its OWN frame
	    (the factor along each of its axes) and moving its centre by the same squash, so the bag stays in
	    one piece. Rigid bits (wooden feet, the metal zip) only move, they don't bulge
	  * a damped spring drives the squash: the bag dips a touch past the squash when someone flops in and
	    puffs up a touch past its rest shape when they get up, then settles; nothing is written while at rest
	  * a soft low "poof" (FunAssets.Sfx.Whoosh, quiet, pitched down) when someone sits
	Poses are applied relative to the build's Hitbox (a move lands cleanly); cleanup restores every part's
	exact rest Size and CFrame.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))
local FunAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunAssets"))

--..Config..--
local SQUASH_Y = 0.88    -- keep in step with the server half (it seats the hips on the squashed top)
local SQUASH_XZ = 1.05
local SPRING_K = 220     -- stiffness (1/s^2)
local SPRING_C = 15      -- damping (1/s): ~15% overshoot, settles in about half a second
local SUBSTEP = 1 / 120
local POOF_VOLUME = 0.22
local POOF_SPEED = 0.62  -- pitched down: a soft fabric "poof", not a swoosh
local RIGID = {          -- materials that move with the bag but never squash
	[Enum.Material.Wood] = true, [Enum.Material.WoodPlanks] = true, [Enum.Material.Metal] = true,
	[Enum.Material.DiamondPlate] = true, [Enum.Material.CorrodedMetal] = true, [Enum.Material.Foil] = true,
	[Enum.Material.Glass] = true, [Enum.Material.Marble] = true, [Enum.Material.Slate] = true,
}

local B = {} -- module name BeanBag = the base key: serves BeanBag_A / _B / _C
B.StepRange = 120

--..Helpers..--
--.. the stretch along a unit direction (floor frame) under the squash diag(xz, y, xz)
local function Along(v, xz, y)
	return math.sqrt((v.X * xz) ^ 2 + (v.Y * y) ^ 2 + (v.Z * xz) ^ 2)
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local parts = Kit.Parts(model, ctx.Variant and (ctx.Variant .. "_") or "")
	if #parts == 0 then return end

	--..Rest pose, in the floor frame under the bag..--
	local floorRel = hitbox.CFrame:ToObjectSpace(Kit.Floor(model))
	local floorCF = hitbox.CFrame * floorRel
	local entries = {}
	local poofParent, biggest = nil, -1
	for _, part in ipairs(parts) do
		local rel = floorCF:ToObjectSpace(part.CFrame)
		local soft = not RIGID[part.Material]
		table.insert(entries, {
			Part = part, Rel = rel, Rot = rel.Rotation, Size = part.Size, Soft = soft,
			AX = rel.RightVector, AY = rel.UpVector, AZ = rel.LookVector,
		})
		local volume = part.Size.X * part.Size.Y * part.Size.Z
		if soft and volume > biggest then poofParent, biggest = part, volume end
	end
	poofParent = poofParent or parts[1]

	local function Rest()
		if not hitbox.Parent then return end
		local base = hitbox.CFrame * floorRel
		for _, e in ipairs(entries) do
			if e.Part.Parent then
				e.Part.Size = e.Size
				e.Part.CFrame = base * e.Rel
			end
		end
	end

	--.. s = 0 rest, 1 fully squashed (the spring overshoots both ways a little)
	local function Pose(s)
		if not hitbox.Parent then return end
		local y = 1 + (SQUASH_Y - 1) * s
		local xz = 1 + (SQUASH_XZ - 1) * s
		local base = hitbox.CFrame * floorRel
		for _, e in ipairs(entries) do
			local part = e.Part
			if part.Parent then
				if e.Soft then
					part.Size = Vector3.new(e.Size.X * Along(e.AX, xz, y), e.Size.Y * Along(e.AY, xz, y), e.Size.Z * Along(e.AZ, xz, y))
				end
				local p = e.Rel.Position
				part.CFrame = base * CFrame.new(p.X * xz, p.Y * y, p.Z * xz) * e.Rot
			end
		end
	end

	local poof = ctx:Sound(poofParent, FunAssets.Sfx.Whoosh, {Volume = POOF_VOLUME, PlaybackSpeed = POOF_SPEED})

	--..State -> spring target..--
	local s, v, target = 0, 0, 0
	local moving = false
	local primed = false
	ctx:OnState("Occupied", function(value)
		local want = value == true and 1 or 0
		if not primed then
			--.. streamed in / started: jump straight to the current shape, no sound
			primed = true
			s, v, target = want, 0, want
			if want == 1 then Pose(1) end
			return
		end
		if want == target then return end
		target = want
		moving = true
		if want == 1 then poof:Play() end
	end)

	--..Every frame (only while the spring moves)..--
	ctx:Step(function(dt)
		if not moving then return end
		local left = math.min(dt, 0.1)
		while left > 1e-6 do
			local h = math.min(left, SUBSTEP)
			v += (SPRING_K * (target - s) - SPRING_C * v) * h
			s += v * h
			left -= h
		end
		if math.abs(target - s) < 0.002 and math.abs(v) < 0.02 then
			s, v, moving = target, 0, false
			if target == 0 then Rest() else Pose(1) end
			return
		end
		Pose(s)
	end)

	return Rest
end

return B
