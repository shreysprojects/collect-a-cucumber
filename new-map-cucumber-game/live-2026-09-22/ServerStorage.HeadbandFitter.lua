-- Fits the authored headband ring (origin centred, Y axis, front -Z) to a head.
-- Only worn clones are resized. Templates and shop previews keep their authored dimensions.
local Fitter = {}
local INNER_DIAMETER = 1.26
local REFERENCE_HEIGHT = 1.2
local SAMPLES = 64
local AssetService = game:GetService("AssetService")
local MeshCache, CacheOrder = {}, {}
local FailedMeshes = {}

local function positive(v)
	return Vector3.new(math.max(math.abs(v.X), 0.01), math.max(math.abs(v.Y), 0.01), math.max(math.abs(v.Z), 0.01))
end

function Fitter.Measure(head)
	local size = head.Size
	local offset = Vector3.zero
	local shape = "Mesh"
	local mesh = head:FindFirstChildWhichIsA("DataModelMesh")
	if head:IsA("Part") then
		shape = head.Shape == Enum.PartType.Ball and "Round" or "Box"
	end
	if mesh then
		offset = mesh.Offset
		if mesh:IsA("SpecialMesh") and mesh.MeshType == Enum.MeshType.Head then
			-- Legacy Head meshes use nonstandard visual bounds; calibrate against the classic
			-- 2x1x1 head with a 1.25 mesh scale. MeshPart heads use their actual Size above.
			size = size * Vector3.new(0.6, 1.2, 1.2) * mesh.Scale / 1.25
			shape = "Round"
		else
			size = size * mesh.Scale
			shape = mesh:IsA("SpecialMesh") and mesh.MeshType == Enum.MeshType.Sphere and "Round" or "Box"
		end
	end
	-- Optional visual bounds for custom legacy FileMesh heads whose render bounds differ
	-- from the physical Part. Standard avatar MeshParts do not need these attributes.
	local override = head:GetAttribute("HeadbandBoundsSize")
	if typeof(override) == "Vector3" then size = override end
	local centre = head:GetAttribute("HeadbandBoundsOffset")
	if typeof(centre) == "Vector3" then offset = centre end
	size = positive(size)
	local lift = size.Y * 0.15
	local clearance = math.max(math.min(size.X, size.Z) * 0.025, 0.008)
	local envelope = shape == "Box" and math.sqrt(2) or 1
	local radii = {}
	for i = 0, SAMPLES - 1 do
		local angle = i * math.pi * 2 / SAMPLES
		local x, z = math.abs(math.cos(angle)), math.abs(math.sin(angle))
		local radius
		if shape == "Round" then
			radius = 1 / math.sqrt((x / (size.X / 2))^2 + (z / (size.Z / 2))^2)
		else
			radius = 1 / math.max(x / (size.X / 2), z / (size.Z / 2))
		end
		radii[i + 1] = radius
	end

	if shape == "Mesh" and head:IsDescendantOf(workspace) then
		-- The collision surface catches square corners/asymmetric heads that a size-only
		-- ellipse would cut through. Probe the whole band height, in head-local space.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {head}
		params.IgnoreWater = true
		local radius = size.Magnitude * 2
		local hits = 0
		local sampled = {}
		for _, y in {lift - size.Y * 0.14, lift, lift + size.Y * 0.14} do
			local origin = offset + Vector3.new(0, y, 0)
			for i = 0, SAMPLES - 1 do
				local angle = i * math.pi * 2 / SAMPLES
				local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local start = head.CFrame:PointToWorldSpace(origin + direction * radius)
				local ray = head.CFrame:VectorToWorldSpace(-direction * radius)
				local hit = workspace:Raycast(start, ray, params)
				if hit then
					hits += 1
					local p = head.CFrame:PointToObjectSpace(hit.Position) - offset
					envelope = math.max(envelope, math.sqrt((p.X / (size.X / 2))^2 + (p.Z / (size.Z / 2))^2))
					sampled[i + 1] = math.max(sampled[i + 1] or 0, Vector2.new(p.X, p.Z).Magnitude)
				end
			end
		end
		-- CanQuery=false or an unavailable collision mesh: enclose the bounding box.
		if hits == 0 then envelope = math.sqrt(2) end
		for i, radius in sampled do radii[i] = radius end
	end

	return {
		Size = size,
		Shape = shape,
		Offset = offset + Vector3.new(0, lift, 0),
		Diameter = Vector3.new(size.X * envelope + clearance * 2, 0, size.Z * envelope + clearance * 2),
		HeightScale = size.Y / REFERENCE_HEIGHT,
		Envelope = envelope,
		Clearance = clearance,
		Radii = radii,
	}
end

-- Radially deform the authored mesh around the measured outline. Preserve UVs and
-- normal sharing, and bake static DataModel content so all clients receive the same fit.
function Fitter.ContourRadius(fit, angle)
	local index = (angle % (math.pi * 2)) / (math.pi * 2) * SAMPLES
	local i = math.floor(index)
	local a, b = fit.Radii[i + 1], fit.Radii[(i + 1) % SAMPLES + 1]
	return (a + (b - a) * (index - i)) / math.cos(math.pi / SAMPLES) + fit.Clearance
end

function Fitter.WarpPoint(point, fit, inner)
	local normalized = Vector2.new(point.X / (inner.X / 2), point.Z / (inner.Z / 2))
	local radius = normalized.Magnitude
	if radius < 0.00001 then return Vector3.new(0, point.Y * fit.HeightScale, 0) end
	local angle = math.atan2(normalized.Y, normalized.X)
	if fit.Shape == "Round" or fit.Shape == "Box" then
		local direction = normalized / radius
		if fit.Shape == "Box" then direction /= math.max(math.abs(direction.X), math.abs(direction.Y)) end
		return Vector3.new(direction.X * (fit.Size.X / 2 + fit.Clearance) * radius,
			point.Y * fit.HeightScale, direction.Y * (fit.Size.Z / 2 + fit.Clearance) * radius)
	end
	angle = math.atan2(point.Z, point.X)
	local target = Fitter.ContourRadius(fit, angle) * radius
	return Vector3.new(math.cos(angle) * target, point.Y * fit.HeightScale, math.sin(angle) * target)
end

local function WarpedMesh(part, pivot, fit, inner)
	if not part:IsA("MeshPart") or FailedMeshes[part.MeshId] then return nil end
	local localCF = pivot:ToObjectSpace(part.CFrame)
	local keyParts = {fit.Shape, part.MeshId, tostring(part.Size), tostring(localCF), tostring(inner), tostring(fit.HeightScale)}
	for _, radius in fit.Radii do table.insert(keyParts, string.format("%.5f", radius)) end
	table.insert(keyParts, tostring(fit.Clearance))
	local key = table.concat(keyParts, "|")
	if MeshCache[key] then return MeshCache[key] end

	local editable
	local ok, result = pcall(function()
		editable = AssetService:CreateEditableMeshAsync(part.MeshContent)
		assert(editable, "Editable mesh memory budget reached")
		local vertices = editable:GetVertices()
		assert(#vertices > 0, "Empty headband mesh")
		local low = Vector3.new(math.huge, math.huge, math.huge)
		local high = -low
		for _, id in vertices do
			local p = editable:GetPosition(id)
			low = Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
			high = Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
		end
		local sourceCentre, sourceSize = (low + high) / 2, positive(high - low)
		local positions = {}
		low = Vector3.new(math.huge, math.huge, math.huge)
		high = -low
		for _, id in vertices do
			local p = (editable:GetPosition(id) - sourceCentre) * (part.Size / sourceSize)
			p = Fitter.WarpPoint(localCF:PointToWorldSpace(p), fit, inner)
			positions[id] = p
			low = Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
			high = Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
		end
		local centre = (low + high) / 2
		for id, position in positions do editable:SetPosition(id, position - centre) end
		local normals = {}
		for _, id in vertices do
			for _, normalId in editable:GetVertexNormals(id) do normals[normalId] = true end
		end
		for normalId in normals do editable:ResetNormal(normalId) end
		local status, content = AssetService:CreateDataModelContentAsync(Content.fromObject(editable))
		assert(status == Enum.CreateContentResult.Success, tostring(status))
		local generated = AssetService:CreateMeshPartAsync(content)
		generated.Size = positive(high - low)
		-- SurfaceAppearance children remain on the original clone when ApplyMesh runs.
		generated.TextureID = part.TextureID
		return {Part = generated, Centre = centre}
	end)
	if editable then editable:Destroy() end
	if not ok then
		-- Keep the whole band on the size-based fit if mesh editing is unavailable.
		-- A failed asset is skipped for this server; no per-frame retries or log spam.
		FailedMeshes[part.MeshId] = true
		warn("[HeadbandFitter] using size fit for " .. part.Name .. ": " .. tostring(result))
		return nil
	end
	if MeshCache[key] then
		result.Part:Destroy()
		return MeshCache[key]
	end
	MeshCache[key] = result
	table.insert(CacheOrder, key)
	if #CacheOrder > 128 then
		local oldest = table.remove(CacheOrder, 1)
		local old = MeshCache[oldest]
		if old then old.Part:Destroy() end
		MeshCache[oldest] = nil
	end
	return result
end

function Fitter.Build(template, name, head)
	assert(head and head:IsA("BasePart"), "A head BasePart is required")
	local fit = Fitter.Measure(head)
	local inner = template:GetAttribute("HeadbandInnerDiameter")
	if typeof(inner) ~= "Vector3" then inner = Vector3.new(INNER_DIAMETER, 0, INNER_DIAMETER) end
	local scale = Vector3.new(fit.Diameter.X / math.max(inner.X, 0.01), fit.HeightScale,
		fit.Diameter.Z / math.max(inner.Z, 0.01))
	local band = template:Clone()
	band.Name = "Band"
	local pivot = template:GetPivot()
	local parts = {}
	if band:IsA("BasePart") then table.insert(parts, band) end
	for _, d in band:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
			or d:IsA("BillboardGui") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	if #parts == 0 then band:Destroy() return nil end

	local warped = {}
	local conform = true
	for _, part in parts do
		local mesh = WarpedMesh(part, pivot, fit, inner)
		if not mesh then conform = false break end
		warped[part] = mesh
	end

	local accessory = Instance.new("Accessory")
	accessory.Name = "Headband_" .. name
	accessory.AccessoryType = Enum.AccessoryType.Hat
	accessory:SetAttribute("Headband", name)
	accessory:SetAttribute("HeadbandFitVersion", 2)
	accessory:SetAttribute("HeadbandConformed", conform)
	accessory:SetAttribute("HeadbandFitScale", scale)
	accessory:SetAttribute("HeadbandFitSize", fit.Size)
	accessory:SetAttribute("HeadbandFitOffset", fit.Offset)
	accessory:SetAttribute("HeadbandInnerDiameter", fit.Diameter)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.CFrame = head.CFrame * CFrame.new(fit.Offset)
	handle.Parent = accessory

	local hat = head:FindFirstChild("HatAttachment")
	if hat and hat:IsA("Attachment") then
		local attachment = Instance.new("Attachment")
		attachment.Name = "HatAttachment"
		attachment.CFrame = CFrame.new(fit.Offset):Inverse() * hat.CFrame
		attachment.Parent = handle
	end

	for _, part in parts do
		local localCF = pivot:ToObjectSpace(part.CFrame)
		local axisScale = Vector3.new((localCF.RightVector * scale).Magnitude,
			(localCF.UpVector * scale).Magnitude, (localCF.LookVector * scale).Magnitude)
		part.Size = positive(part.Size * axisScale)
		local partMesh = part:FindFirstChildWhichIsA("DataModelMesh")
		if partMesh then
			-- FileMesh geometry ignores BasePart.Size; the other built-in meshes inherit it.
			if partMesh:IsA("SpecialMesh") and partMesh.MeshType == Enum.MeshType.FileMesh then
				partMesh.Scale *= axisScale
			end
			partMesh.Offset *= axisScale
		end
		if conform then
			local generated = warped[part]
			part:ApplyMesh(generated.Part)
			part.Size = generated.Part.Size
			part.CFrame = handle.CFrame * CFrame.new(generated.Centre)
		else
			part.CFrame = handle.CFrame * CFrame.new(localCF.Position * scale) * localCF.Rotation
		end
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Name = "HeadbandWeld"
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end
	band.Parent = accessory
	-- An explicit head-local weld avoids assuming HatAttachment is 0.6 studs up,
	-- avoids rotated attachments, and avoids an extra AddAccessory auto-scale pass.
	local weld = Instance.new("Weld")
	weld.Name = "AccessoryWeld"
	weld.Part0 = head
	weld.Part1 = handle
	weld.C0 = CFrame.new(fit.Offset)
	weld.C1 = CFrame.identity
	weld.Parent = handle
	return accessory
end

return Fitter
