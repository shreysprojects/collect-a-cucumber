--[[
	PetRuntimeMesh (ReplicatedStorage.Modules.PetRuntimeMesh)
	Repo copy of the module installed in the place on 2026-09-01. Source of truth is the place.

	The remade Robux pets (Red Demon / Purple Hydra / Heavenly Angel, 2026-09-01)
	were modelled in Blender in the house pet style, but Studio's publish-from-
	EditableMesh API is still gated ("CreateAssetAsync ... not available yet")
	and no Open Cloud key is configured, so their geometry ships INSIDE the place
	as data instead of as uploaded mesh assets:

	  ReplicatedStorage.Assets.PetMeshData.<Pet Name>   ModuleScript
	      Parts[<PartName>] = { V = {x,y,z,...}, T = {a,b,c,...}, Size, Offset, Color, Material }

	Each pet model keeps the normal house layout (Root + <Prefix>_<Part>_Node
	Models holding one MeshPart each, WeldConstraints from Root). Those MeshParts
	are saved EMPTY and invisible (Transparency 1) with the attribute
	    RuntimeMesh = "<Pet Name>/<PartName>"
	the pet Model carries the CollectionService tag "RuntimeMeshPet" and the
	attribute RuntimeMeshPet = "<Pet Name>".

	On every client, PetRuntimeMeshClient watches that tag and calls
	applyToModel(): the geometry is built once per part into an EditableMesh ->
	CreateMeshPartAsync source part, and copied onto each placeholder with
	MeshPart:ApplyMesh(), which also works on clones (viewport thumbnails,
	server-spawned followers, the PromotedPets stands). Clones of an already
	built part keep their geometry, so building the ReplicatedStorage templates
	at join makes later client clones instant.

	REQUIRES the experience security setting "Allow Mesh & Image APIs"
	(Game Settings > Security). Without it every EditableMesh call throws
	"EditableMesh is not accessible", so the loader FALLS BACK to the original
	toolbox-mesh models kept in ReplicatedStorage.Assets.PetMeshData.Fallback:
	their MeshParts are cloned client-side and welded onto Root at the
	Root-relative CFrames stored in their RelCFrame attribute. The pets are
	never invisible; they are just the old look until the setting is enabled
	and the place republished.

	Server side nothing is built: the server never needs the visuals.

	UPGRADE PATH: pets-remake/<Pet>.fbx next to pets.blend are the same meshes.
	Once they exist as real assets (Import 3D, or upload_asset with an Open Cloud
	key), set each placeholder's MeshId, clear the RuntimeMesh attribute and the
	Transparency, drop the tag, and this module has nothing left to do.
]]
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetRuntimeMesh = {}
PetRuntimeMesh.TAG = "RuntimeMeshPet"
PetRuntimeMesh.ATTR = "RuntimeMesh"
PetRuntimeMesh.PET_ATTR = "RuntimeMeshPet"
PetRuntimeMesh.APPLIED_ATTR = "RuntimeMeshApplied"
PetRuntimeMesh.FALLBACK_ATTR = "RuntimeMeshFallbackApplied"
PetRuntimeMesh.TRANSPARENCY_ATTR = "RuntimeMeshTransparency"

local sourceParts = {}
local pending = {}
local available = nil -- nil = not probed yet

local function dataFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("PetMeshData")
end

-- The EditableMesh API is gated by the experience's "Allow Mesh & Image APIs"
-- security setting: CreateEditableMesh() still returns an object, but the
-- first method call throws. Probe once and remember.
function PetRuntimeMesh.isAvailable()
	if available ~= nil then
		return available
	end
	local ok, err = pcall(function()
		local em = AssetService:CreateEditableMesh()
		em:AddVertex(Vector3.zero)
		em:Destroy()
	end)
	available = ok
	if not ok then
		warn("[PetRuntimeMesh] EditableMesh unavailable (" .. tostring(err) .. ") -- showing the fallback pet models. Enable Game Settings > Security > Allow Mesh & Image APIs and republish to get the remade pets.")
	end
	return available
end

local function buildSource(key)
	local petName, partName = key:match("^(.-)/(.+)$")
	local folder = dataFolder()
	local dataModule = folder and petName and folder:FindFirstChild(petName)
	if not dataModule then
		warn("[PetRuntimeMesh] no mesh data for", key)
		return nil
	end
	local data = require(dataModule)
	local part = data.Parts and data.Parts[partName]
	if not part then
		warn("[PetRuntimeMesh] no part data for", key)
		return nil
	end
	local em = AssetService:CreateEditableMesh()
	local V, T = part.V, part.T
	local vids = table.create(#V // 3)
	for i = 1, #V, 3 do
		vids[#vids + 1] = em:AddVertex(Vector3.new(V[i], V[i + 1], V[i + 2]))
	end
	local uv = em:AddUV(Vector2.zero)
	for i = 1, #T, 3 do
		local a, b, c = vids[T[i]], vids[T[i + 1]], vids[T[i + 2]]
		local p1, p2, p3 = em:GetPosition(a), em:GetPosition(b), em:GetPosition(c)
		local n = (p2 - p1):Cross(p3 - p1)
		if n.Magnitude > 1e-9 then
			-- flat shading: one normal per face (the house pets are faceted low-poly)
			local nid = em:AddNormal(n.Unit)
			local f = em:AddTriangle(a, b, c)
			em:SetFaceNormals(f, {nid, nid, nid})
			em:SetFaceUVs(f, {uv, uv, uv})
		end
	end
	local src = AssetService:CreateMeshPartAsync(Content.fromObject(em))
	src.Name = key
	src.Anchored = true
	src.CanCollide = false
	src.CanQuery = false
	src.CanTouch = false
	return src
end

-- One build per key; concurrent callers wait for the first build.
function PetRuntimeMesh.getSource(key)
	local existing = sourceParts[key]
	if existing then
		return existing
	end
	if pending[key] then
		table.insert(pending[key], coroutine.running())
		return coroutine.yield()
	end
	pending[key] = {}
	local ok, src = pcall(buildSource, key)
	if not ok then
		warn("[PetRuntimeMesh] build failed for", key, src)
		src = nil
	end
	sourceParts[key] = src
	local waiters = pending[key]
	pending[key] = nil
	for _, th in ipairs(waiters) do
		task.spawn(th, src)
	end
	return src
end

function PetRuntimeMesh.applyToPart(part)
	if not part:IsA("MeshPart") then
		return
	end
	local key = part:GetAttribute(PetRuntimeMesh.ATTR)
	if type(key) ~= "string" or part:GetAttribute(PetRuntimeMesh.APPLIED_ATTR) then
		return
	end
	local src = PetRuntimeMesh.getSource(key)
	if not src or not part.Parent then
		return
	end
	part:ApplyMesh(src)
	local transparency = part:GetAttribute(PetRuntimeMesh.TRANSPARENCY_ATTR)
	part.Transparency = type(transparency) == "number" and transparency or 0
	part:SetAttribute(PetRuntimeMesh.APPLIED_ATTR, true)
end

-- Old-look fallback: clone the original model's MeshParts onto Root.
function PetRuntimeMesh.applyFallback(model)
	if model:GetAttribute(PetRuntimeMesh.FALLBACK_ATTR) then
		return
	end
	local petName = model:GetAttribute(PetRuntimeMesh.PET_ATTR)
	local root = (model:IsA("Model") and model.PrimaryPart) or model:FindFirstChild("Root")
	local folder = dataFolder()
	local fallbacks = folder and folder:FindFirstChild("Fallback")
	local template = fallbacks and petName and fallbacks:FindFirstChild(petName)
	if not (root and template) then
		warn("[PetRuntimeMesh] no fallback for", tostring(petName))
		return
	end
	model:SetAttribute(PetRuntimeMesh.FALLBACK_ATTR, true)
	-- Fit the old model into the NEW model's box: EquipService scales followers
	-- from the placeholder extents (5-stud box), stands were scaled by hand, so
	-- measure the placeholders as they are right now and scale the old parts to
	-- the same largest dimension.
	local mins, maxs
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") and d:GetAttribute(PetRuntimeMesh.ATTR) then
			local cf, half = d.CFrame, d.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local p = cf:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
						mins = mins and Vector3.new(math.min(mins.X, p.X), math.min(mins.Y, p.Y), math.min(mins.Z, p.Z)) or p
						maxs = maxs and Vector3.new(math.max(maxs.X, p.X), math.max(maxs.Y, p.Y), math.max(maxs.Z, p.Z)) or p
					end
				end
			end
		end
	end
	local scale = (model:IsA("Model") and model:GetScale()) or 1
	local templateMax = template:GetAttribute("MaxExtent")
	if mins and type(templateMax) == "number" and templateMax > 0 then
		local ext = maxs - mins
		scale = math.max(ext.X, ext.Y, ext.Z) / templateMax
	end
	for _, part in ipairs(template:GetChildren()) do
		if part:IsA("BasePart") then
			local rel = part:GetAttribute("RelCFrame")
			if typeof(rel) == "CFrame" then
				local c = part:Clone()
				c.Size = part.Size * scale
				c.CFrame = root.CFrame * (CFrame.new(rel.Position * scale) * rel.Rotation)
				c.Anchored = root.Anchored
				c.Massless = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = c
				weld.Parent = c
				c.Parent = model
			end
		end
	end
end

-- Builds every placeholder under `model`, and keeps watching for late
-- descendants (replication batches, streamed-in stand parts).
function PetRuntimeMesh.applyToModel(model)
	if not PetRuntimeMesh.isAvailable() then
		return PetRuntimeMesh.applyFallback(model)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") and d:GetAttribute(PetRuntimeMesh.ATTR) then
			task.spawn(PetRuntimeMesh.applyToPart, d)
		end
	end
	if not model:GetAttribute("RuntimeMeshWatched") then
		model:SetAttribute("RuntimeMeshWatched", true)
		model.DescendantAdded:Connect(function(d)
			if d:IsA("MeshPart") and d:GetAttribute(PetRuntimeMesh.ATTR) then
				task.spawn(PetRuntimeMesh.applyToPart, d)
			end
		end)
	end
end

-- Hooks the whole DataModel: every tagged pet that exists now or appears later
-- (server-spawned followers, viewport clones, PromotedPets stands). Called once
-- by PetRuntimeMeshClient; safe to call from a Studio eval for previews.
function PetRuntimeMesh.start()
	local CollectionService = game:GetService("CollectionService")
	local function handle(inst)
		task.spawn(PetRuntimeMesh.applyToModel, inst)
	end
	for _, inst in ipairs(CollectionService:GetTagged(PetRuntimeMesh.TAG)) do
		handle(inst)
	end
	return CollectionService:GetInstanceAddedSignal(PetRuntimeMesh.TAG):Connect(handle)
end

return PetRuntimeMesh
