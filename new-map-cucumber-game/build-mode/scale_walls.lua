-- scale_walls.lua (edit-mode execute_luau, 2026-09-10, user: "extend the walls so they reach the second
-- floor - make walls 10 studs"). Stretches every wall model in ServerStorage.Builds.Walls (not the
-- Staircase / Flooring) to BuildCatalog.LEVEL_HEIGHT (10) tall IN HEIGHT ONLY: the walls stay 8 wide so
-- they keep tiling with the 8-stud grass / flooring grid (a uniform ScaleTo made them 10 wide and a wall
-- no longer fitted on one flooring tile). Each part's Size.Y and its height above the model pivot are
-- multiplied by 10 / height; the pivot sits at the base, so the walls still stand on the ground.
-- Idempotent: undoes any uniform scale first, then stretches from the authored height.
local walls = game:GetService("ServerStorage"):WaitForChild("Builds"):WaitForChild("Walls")
local TARGET = 10
local report = {}
for _, model in ipairs(walls:GetChildren()) do
	if model:IsA("Model") and model.Name ~= "Staircase" and model.Name ~= "Flooring" then
		if math.abs(model:GetScale() - 1) > 1e-4 then model:ScaleTo(1) end
		local pivot = model:GetPivot()
		local _, size = model:GetBoundingBox()
		local f = TARGET / size.Y
		if math.abs(f - 1) > 1e-4 then
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") then
					local rel = pivot:ToObjectSpace(part.CFrame)
					part.Size = Vector3.new(part.Size.X, part.Size.Y * f, part.Size.Z)
					local p = rel.Position
					part.CFrame = pivot * (CFrame.new(p.X, p.Y * f, p.Z) * rel.Rotation)
				end
			end
		end
		local _, after = model:GetBoundingBox()
		local notes = (model:GetAttribute("Notes") or ""):gsub(" %[s%a+ to [%d%.]+ tall.-second floor%]", "")
		model:SetAttribute("Notes", notes .. (" [stretched to %.1f tall (width kept) on 2026-09-10 so it reaches the second floor]"):format(after.Y))
		table.insert(report, ("%s %.2f -> %.2f x %.2f x %.2f"):format(model.Name, size.Y, after.X, after.Y, after.Z))
	end
end
print("[scale_walls] " .. table.concat(report, " | "))
