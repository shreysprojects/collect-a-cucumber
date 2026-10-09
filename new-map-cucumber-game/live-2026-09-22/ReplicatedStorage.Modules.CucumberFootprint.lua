--[[
	CucumberFootprint  (ModuleScript, ReplicatedStorage.Modules)  2026-09-13
	The COLLISION box of a placed cucumber - the one every "is that spot free?" test uses and the one
	its invisible PlotHitbox is laid with - as a function of its RestSize (the full bounding box at plot
	scale). User: "bigger/massive cucumbers are really sensitive about placement and are hard to place
	- its impossible to place them near anything. make this less sensitive."
	The full box of a tree or a giant is mostly canopy, so two of them could never stand near each
	other and nothing could go under their leaves. The footprint now shrinks with width: anything up to
	TARGET studs wide keeps (SHRINK x) its whole box, wider ones keep TARGET studs of it, down to MIN of
	the box for the widest. Height keeps the old SHRINK. Used by CucumberCarry (Place, RestorePlaced),
	CucumberPlacementClient, CucumberMoveServer and BuildMenuClient (moving), so the ghost, the server
	check and the standing hitbox always agree.
	  Factor(size) -> the X / Z factor      Box(size) -> Vector3 the tests / hitbox use
]]
local M = {}

M.SHRINK = 0.96 -- the all-round shrink every box had before (keeps neighbours from touching)
M.TARGET = 6    -- studs: a cucumber this wide (or narrower) keeps its whole box as footprint
M.MIN = 0.5     -- the widest cucumbers keep at least half their box

function M.Factor(size)
	local w = math.max(size.X, size.Z)
	if w <= 0 then return M.SHRINK end
	return math.clamp(M.TARGET / w, M.MIN, M.SHRINK)
end

function M.Box(size)
	local f = M.Factor(size)
	return Vector3.new(size.X * f, size.Y * M.SHRINK, size.Z * f)
end

return M
