--[[
	WP-MENU_hud_tuck.lua  (2026-09-22, review #12) - the paw's tuck motion in the patched BaseHUDController.
	Run from an edit-peer execute_luau:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-MENU_hud_tuck.lua"))()
	The paw (LeftMenu.Pets) is authored Size (1, 0, 0.455, 0) with a Square FitWithinMaxSize constraint, so it
	draws 0.455H = 0.389W wide. Checks the pure Controller.DrawnShare / Controller.Pose against (a) hand numbers,
	(b) the engine's own layout of every FitWithinMaxSize element in the live StarterGui (read-only), (c) the
	builder's real Square constraint on an UNPARENTED HUD clone, and (d) the tuck path with the live LeftMenu size:
	it travels 42 % of the paw's OWN width, shrinks about its own centre and barely reaches the slot-1 button.
	Unconstrained buttons keep the old pose exactly. Nothing enters the DataModel.
	Returns "WP-MENU hud tuck: PASS n / FAIL m: <first failures>".
]]
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local pass, fail, failures = 0, 0, {}
local function check(name, condition, detail)
	if condition then
		pass += 1
	else
		fail += 1
		if #failures < 14 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function fetch(port, file) return HttpService:GetAsync(("http://127.0.0.1:%d/%s"):format(port, file)) end

-- the module's own constants (the test fails loudly if they drift from these)
local SLIDE, SHRINK, FADE_END = 0.42, 0.82, 0.85
local FIT = {AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize}
local PAW_SIZE, PAW_POS = UDim2.new(1, 0, 0.455, 0), UDim2.new(1.07, 0, 0, 0)

local chunk, compileError = loadstring(fetch(8794, "StarterGui.CucumberHUDDesign.BaseHUDController.lua"))
check("patched BaseHUDController compiles", chunk ~= nil, compileError)
local hudClone
local ok, err = pcall(function()
	local Controller = chunk()
	local DrawnShare, Pose = Controller.DrawnShare, Controller.Pose
	check("DrawnShare / Pose exported", type(DrawnShare) == "function" and type(Pose) == "function")

	--..(a) DrawnShare by hand..--
	local sx, sy = DrawnShare(PAW_SIZE, Vector2.new(121.558434, 104), nil)
	check("no constraint = the box", sx == 1 and sy == 1)
	sx, sy = DrawnShare(PAW_SIZE, Vector2.new(121.558434, 104), {AspectRatio = 1, AspectType = Enum.AspectType.ScaleWithParentSize})
	check("other aspect type = the box", sx == 1 and sy == 1)
	sx, sy = DrawnShare(PAW_SIZE, Vector2.new(121.558434, 104), FIT)
	check("paw draws 0.389 of its box width, full height", near(sx, 0.455 * 104 / 121.558434, 1e-6) and sy == 1, ("%.4f %.4f"):format(sx, sy))
	sx, sy = DrawnShare(UDim2.new(0.2, 0, 1, 0), Vector2.new(100, 100), FIT)
	check("width-limited box keeps its width", sx == 1 and near(sy, 0.2), ("%.4f %.4f"):format(sx, sy))
	sx, sy = DrawnShare(UDim2.new(0, 50, 0, 20), Vector2.new(0, 0), FIT)
	check("offset box (50x20, square)", near(sx, 0.4) and sy == 1, ("%.4f %.4f"):format(sx, sy))
	sx, sy = DrawnShare(UDim2.new(0.5, 0, 0.5, 0), Vector2.new(200, 100), {AspectRatio = 2, AspectType = Enum.AspectType.FitWithinMaxSize})
	check("ratio 2 in a 100x50 box fits exactly", near(sx, 1) and near(sy, 1), ("%.4f %.4f"):format(sx, sy))
	sx, sy = DrawnShare(PAW_SIZE, Vector2.new(0, 0), FIT)
	check("not laid out (unparented) = the box", sx == 1 and sy == 1)
	sx, sy = DrawnShare(PAW_SIZE, Vector2.new(121, 104), {AspectRatio = 0 / 0, AspectType = Enum.AspectType.FitWithinMaxSize})
	check("NaN ratio = the box", sx == 1 and sy == 1)
	sx, sy = DrawnShare(PAW_SIZE, Vector2.new(0 / 0, 104), FIT)
	check("NaN parent size = the box", sx == 1 and sy == 1)

	--..(b) the engine agrees: every laid-out FitWithinMaxSize element in the live StarterGui (read-only)..--
	local agreed, measured = 0, 0
	for _, c in StarterGui:GetDescendants() do
		if c:IsA("UIAspectRatioConstraint") and c.AspectType == Enum.AspectType.FitWithinMaxSize then
			local g, p = c.Parent, c.Parent and c.Parent.Parent
			if g and g:IsA("GuiObject") and p and p:IsA("GuiBase2d") and p.AbsoluteSize.X > 1 and g.AbsoluteSize.X > 0
				and not g:FindFirstChildOfClass("UISizeConstraint") and not g:FindFirstChildOfClass("UITextSizeConstraint")
				and g.AutomaticSize == Enum.AutomaticSize.None and not p:FindFirstChildWhichIsA("UIGridStyleLayout") then
				local ps = p.AbsoluteSize
				local bw = g.Size.X.Scale * ps.X + g.Size.X.Offset
				local bh = g.Size.Y.Scale * ps.Y + g.Size.Y.Offset
				if bw > 0 and bh > 0 then
					measured += 1
					local ex, ey = DrawnShare(g.Size, ps, c)
					if math.abs(ex * bw - g.AbsoluteSize.X) < 1.5 and math.abs(ey * bh - g.AbsoluteSize.Y) < 1.5 then agreed += 1 end
				end
			end
		end
	end
	check("engine layout matches DrawnShare", measured > 0 and agreed == measured, ("%d/%d"):format(agreed, measured))

	--..(c) the builder's real Square constraint, on an unparented clone..--
	local Builder = loadstring(loadstring(fetch(8795, "WP-MENU_builder_embed.lua"))())({Mode = "module"})
	hudClone = StarterGui.CucumberHUDDesign:Clone()
	Builder.BuildOpener(hudClone)
	local paw = hudClone.LeftMenu:FindFirstChild("Pets")
	local square = paw and paw:FindFirstChildOfClass("UIAspectRatioConstraint")
	check("builder paw has its Square constraint", square ~= nil and paw.Size == PAW_SIZE and paw.Position == PAW_POS and paw.AnchorPoint == Vector2.zero)

	--..(d) the tuck path with the live LeftMenu size..--
	local liveMenu = StarterGui.CucumberHUDDesign.LeftMenu.AbsoluteSize
	local menuSize = liveMenu.X > 1 and liveMenu or Vector2.new(121.558434, 104) -- the review's measurement
	local W, H = menuSize.X, menuSize.Y
	sx, sy = DrawnShare(PAW_SIZE, menuSize, square or FIT)
	local drawnW = sx * W -- the paw's own width in px at rest
	check("paw is a square at rest", near(drawnW, 0.455 * H * sy, 1e-3), ("%.2f vs %.2f"):format(drawnW, 0.455 * H))
	local restSize, restPos = Pose(PAW_POS, PAW_SIZE, 1, sx, sy)
	check("presence 1 = the authored pose", restSize == PAW_SIZE and restPos == PAW_POS, tostring(restPos))
	local restCx = 1.07 * W + drawnW * 0.5
	local restCy = 0.455 * H * 0.5
	local maxOverlap, overlapAtHalf, worstCentre, worstY = 0, 0, 0, 0
	local opacityAtFirstOverlap
	for step = 0, 40 do
		local p = step / 40
		local size, pos = Pose(PAW_POS, PAW_SIZE, p, sx, sy)
		local w = sx * size.X.Scale * W -- drawn box: FitWithinMaxSize scales with k, anchored top-left
		local h = sy * size.Y.Scale * H
		local left = pos.X.Scale * W + pos.X.Offset
		local top = pos.Y.Scale * H + pos.Y.Offset
		local wantCx = restCx - SLIDE * drawnW * (1 - p)
		worstCentre = math.max(worstCentre, math.abs(left + w * 0.5 - wantCx))
		worstY = math.max(worstY, math.abs(top + h * 0.5 - restCy))
		local k = SHRINK + (1 - SHRINK) * p
		check(("drawn size shrinks with k at p=%.3f"):format(p), near(w, drawnW * k, 1e-3))
		local overlap = math.max(0, W - left) -- slot 1 (Shop / Build) spans 0 .. W
		if overlap > 0 and p > 0.001 and not opacityAtFirstOverlap then
			opacityAtFirstOverlap = math.clamp(p / FADE_END, 0, 1)
		end
		if p > 0.001 then maxOverlap = math.max(maxOverlap, overlap) end
		if p >= 0.5 then overlapAtHalf = math.max(overlapAtHalf, overlap) end
	end
	check("travel = 42 % of the paw's OWN width, about its centre", worstCentre < 1e-3, worstCentre)
	check("shrinks about its own vertical centre", worstY < 1e-3, worstY)
	local _, tuckedPos = Pose(PAW_POS, PAW_SIZE, 0, sx, sy)
	check("fully tucked centre is 0.42 x own width left", near(restCx - (tuckedPos.X.Scale * W + drawnW * SHRINK * 0.5), SLIDE * drawnW, 1e-3))
	check("no overlap with slot 1 while >= half present", overlapAtHalf == 0, overlapAtHalf)
	check("overlap with slot 1 stays under 8 px (was ~40)", maxOverlap < 8, ("%.2f px"):format(maxOverlap))
	check("any overlap starts below 55 % opacity", opacityAtFirstOverlap == nil or opacityAtFirstOverlap < 0.55, opacityAtFirstOverlap)

	-- the old pose (the box width) for the record: it reached a third of the way across slot 1
	local oldLeft = (1.07 + 1 * ((1 - SHRINK) * 0.5 - SLIDE)) * W
	check("old pose really overlapped slot 1 (defect reproduced)", W - oldLeft > 30, ("%.1f px"):format(W - oldLeft))

	--..unconstrained buttons (Shop / Index / Build / Manage / BenchStrength) keep the old pose exactly..--
	local samples = {{UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.455, 0)}, {UDim2.new(0, 0, 0.545, 0), UDim2.new(1, 0, 0.455, 0)},
		{UDim2.new(0.1, 4, 0.2, -3), UDim2.new(0.5, 12, 0.3, 8)}}
	local same = true
	for _, sample in samples do
		local pos, size = sample[1], sample[2]
		for _, p in {0, 0.25, 0.5, 0.9, 1, 1.08} do
			local k = SHRINK + (1 - SHRINK) * p
			local oldSize = UDim2.new(size.X.Scale * k, size.X.Offset * k, size.Y.Scale * k, size.Y.Offset * k)
			local oldPos = UDim2.new(
				pos.X.Scale + size.X.Scale * ((1 - k) * 0.5 - SLIDE * (1 - p)), pos.X.Offset + size.X.Offset * (1 - k) * 0.5,
				pos.Y.Scale + size.Y.Scale * (1 - k) * 0.5, pos.Y.Offset + size.Y.Offset * (1 - k) * 0.5)
			local newSize, newPos = Pose(pos, size, p, 1, 1)
			if newSize ~= oldSize or newPos ~= oldPos then same = false end
		end
	end
	check("unconstrained pose unchanged (incl. Back overshoot)", same)
	check("Shop has no aspect constraint (share stays 1)", StarterGui.CucumberHUDDesign.LeftMenu.Shop:FindFirstChildOfClass("UIAspectRatioConstraint") == nil
		and StarterGui.CucumberHUDDesign.LeftMenu.Index:FindFirstChildOfClass("UIAspectRatioConstraint") == nil)
end)
if not ok then
	fail += 1
	table.insert(failures, 1, "ERROR " .. tostring(err))
end
if hudClone then hudClone:Destroy() end
return ("WP-MENU hud tuck: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
