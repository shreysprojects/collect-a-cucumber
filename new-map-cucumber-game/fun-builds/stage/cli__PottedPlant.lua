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
