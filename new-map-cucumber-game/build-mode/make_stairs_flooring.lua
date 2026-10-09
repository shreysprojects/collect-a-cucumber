-- make_stairs_flooring.lua (edit-mode execute_luau, 2026-09-10, user: "in the walls section add
-- flooring and a staircase built from parts; going up the staircase lets you lay flooring on a second
-- floor 10 studs up, never on the first floor"). Two part-built models for ServerStorage.Builds.Walls:
--   Staircase: 4 wide x 14 long x 13 tall to the landing (8 block steps of 1.625 rise x 1.5 run with
--              lighter tread caps, a 2-deep landing), handrails on both sides (posts, a diagonal rail,
--              rails along the landing); the far edge of the landing is open, so the player walks off it
--              onto flooring laid beyond. Cost 600.
--   Flooring:  8 x 8 x 1 tile of four plank strips. Attribute IsFloor = true: a surface build mode lays on
--              whichever floor the player stands on - flush in the grass (top FLOOR_LIFT up) or, upstairs, its
--              top AT the level flush with the landing; builds stand on it. Cost 200.
-- Idempotent: replaces models of the same name.
local ServerStorage = game:GetService("ServerStorage")
local walls = ServerStorage:WaitForChild("Builds"):WaitForChild("Walls")
local DARK = Color3.fromRGB(107, 68, 35)
local LIGHT = Color3.fromRGB(192, 138, 79)
local MID = Color3.fromRGB(168, 118, 66)
local RAIL = Color3.fromRGB(70, 46, 26)
local W, N, RISE, RUN, LANDING = 4, 8, 13 / 8, 1.5, 2 -- landing at 13 = LEVEL_HEIGHT (12) + FLOOR_THICKNESS: flush with upstairs flooring resting on the 12-stud walls
local LENGTH = N * RUN + LANDING -- 14
local POST_H, RAIL_T = 3.2, 0.3

local function part(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.WoodPlanks
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--..Staircase..--
local old = walls:FindFirstChild("Staircase")
if old then old:Destroy() end
local stairs = Instance.new("Model")
stairs.Name = "Staircase"
local front = LENGTH * 0.5 -- the +Z end is the foot of the stairs
local topY = N * RISE
for i = 1, N do
	local top = i * RISE
	local zc = front - RUN * (i - 0.5)
	part(stairs, "Step" .. i, Vector3.new(W, top - 0.2, RUN), CFrame.new(0, (top - 0.2) * 0.5, zc), DARK)
	part(stairs, "Tread" .. i, Vector3.new(W, 0.2, RUN), CFrame.new(0, top - 0.1, zc), LIGHT)
end
local landZ = -front + LANDING * 0.5
part(stairs, "Landing", Vector3.new(W, topY - 0.2, LANDING), CFrame.new(0, (topY - 0.2) * 0.5, landZ), DARK)
part(stairs, "LandingTread", Vector3.new(W, 0.2, LANDING), CFrame.new(0, topY - 0.1, landZ), LIGHT)
for _, sx in ipairs({-1, 1}) do
	local x = sx * (W * 0.5 - RAIL_T * 0.5)
	local side = sx < 0 and "L" or "R"
	local footZ = front - RAIL_T * 0.5
	local nearZ = landZ + LANDING * 0.5 - RAIL_T * 0.5 -- where the last step meets the landing
	local farZ = landZ - LANDING * 0.5 + RAIL_T * 0.5 -- the open edge
	part(stairs, "FootPost" .. side, Vector3.new(RAIL_T, POST_H, RAIL_T), CFrame.new(x, POST_H * 0.5, footZ), RAIL, Enum.Material.Wood)
	part(stairs, "TopPost" .. side, Vector3.new(RAIL_T, POST_H, RAIL_T), CFrame.new(x, topY + POST_H * 0.5, nearZ), RAIL, Enum.Material.Wood)
	part(stairs, "BackPost" .. side, Vector3.new(RAIL_T, POST_H, RAIL_T), CFrame.new(x, topY + POST_H * 0.5, farZ), RAIL, Enum.Material.Wood)
	local a = Vector3.new(x, POST_H, footZ)
	local b = Vector3.new(x, topY + POST_H, nearZ)
	part(stairs, "Rail" .. side, Vector3.new(RAIL_T, RAIL_T, (b - a).Magnitude + RAIL_T), CFrame.lookAt((a + b) * 0.5, b), RAIL, Enum.Material.Wood)
	part(stairs, "LandingRail" .. side, Vector3.new(RAIL_T, RAIL_T, LANDING), CFrame.new(x, topY + POST_H, landZ), RAIL, Enum.Material.Wood)
end
stairs:SetAttribute("Cost", 600)
stairs:SetAttribute("IsStairs", true) -- build mode snaps the landing's open edge onto a grass-cell boundary and lets the first upstairs tile start there
stairs:SetAttribute("Notes", "Part-built (make_stairs_flooring.lua). 4 wide x 14 long, 8 steps of 1.625 up to a landing at 13 = LEVEL_HEIGHT + FLOOR_THICKNESS (flush with upstairs flooring resting on the 12-stud walls); the far (-Z) edge of the landing is open for flooring.")
stairs.Parent = walls

--..Flooring..--
local oldFloor = walls:FindFirstChild("Flooring")
if oldFloor then oldFloor:Destroy() end
local flooring = Instance.new("Model")
flooring.Name = "Flooring"
for i = 1, 4 do
	part(flooring, "Plank" .. i, Vector3.new(2, 1, 8), CFrame.new(-3 + (i - 1) * 2, 0.5, 0), i % 2 == 1 and LIGHT or MID)
end
flooring:SetAttribute("Cost", 200)

flooring:SetAttribute("IsFloor", true)
flooring:SetAttribute("Notes", "Part-built (make_stairs_flooring.lua). 8 x 8 x 1 surface tile: IsFloor = true, so build mode lays it on whichever floor the player stands on - flush in the grass on the ground (top 0.05 up), its top AT the level upstairs, flush with a staircase landing. Builds stand on it.")
flooring.Parent = walls

local _, ss = stairs:GetBoundingBox()
local _, fs = flooring:GetBoundingBox()
print(("[make_stairs_flooring] Staircase %d parts %s | Flooring %d parts %s"):format(#stairs:GetChildren(), tostring(ss), #flooring:GetChildren(), tostring(fs)))
