-- guardians/install.lua - Studio-side installer for the ten biome guardians.
--
-- Served by  pets-remake/serve.ps1 -Root guardians -Port 8771  and run from an
-- edit-mode execute_luau:
--
--   local f = loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8771/install.lua"))()
--   f.install({"Strawman"})     -- 3 or 4 guardians per call: LoadAsset is slow
--   f.verify()                  -- counts, colours, motors, pivots
--   f.display(Vector3.new(0, 0, -60))
--   f.clear()
--
-- What it does to each guardian:
--   * LoadAsset, then YAW THE WHOLE MODEL 180 degrees about Y. The importer lands a
--     Blender point at (-bx, bz, by); after this correction it is at (bx, bz, -by) and
--     the authored +Y front faces Roblox -Z, which is the model's LookVector.
--   * renames every part from `Guardian_Part_Role` to just `Part` and puts the role in a
--     Role attribute - animation Poses are keyed by part name, so short names matter.
--   * re-applies colour / material / transparency from the payload. The FBX import loses
--     all of it: every part arrives grey SmoothPlastic, so this is not optional.
--   * builds the Motor6D tree FROM ATTACHMENT PAIRS, the way the zombie rigs are built:
--     an Attachment in each of Part0 and Part1 at the joint, and a Motor6D whose C0/C1
--     are those attachment CFrames. The pivot comes from the payload, already converted.
--   * adds a Humanoid + HumanoidRootPart (the invisible Root part) so Phase 3 can use
--     MoveTo and Animator, and sets HipHeight from the real distance to the floor.
--   * parks the result at ServerStorage.Assets.Guardians.<Name>, with its seat model and
--     any extras inside it.
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local InsertService = game:GetService("InsertService")

local BASE = "http://127.0.0.1:8771"
local FOLDER = "Guardians"

local API = {}
local _payload = nil

local function payload()
	if not _payload then
		_payload = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "/install-payload.json"))
	end
	return _payload
end

local function colour(hex)
	return Color3.fromHex(hex)
end

local function material(name)
	local ok, m = pcall(function() return Enum.Material[name] end)
	return ok and m or Enum.Material.SmoothPlastic
end

local function assets()
	local a = ServerStorage:FindFirstChild("Assets")
	if not a then
		a = Instance.new("Folder")
		a.Name = "Assets"
		a.Parent = ServerStorage
	end
	local f = a:FindFirstChild(FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = FOLDER
		f.Parent = a
	end
	return f
end

--.. load one asset and hand back its root Model, yawed 180 degrees about Y
local function loadModel(assetId)
	local container = InsertService:LoadAsset(tonumber(assetId))
	local root = container:GetChildren()[1]
	root.Parent = nil
	container:Destroy()
	local yaw = CFrame.Angles(0, math.pi, 0)
	for _, p in ipairs(root:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CFrame = yaw * p.CFrame
		end
	end
	return root
end

--.. rename / recolour / configure every part from the rig table; returns name -> part
local function dress(model, rig, opts)
	opts = opts or {}
	local byObject = {}
	for part, d in pairs(rig) do
		byObject[d.object] = {name = part, d = d}
	end
	local parts, unknown = {}, {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local hit = byObject[p.Name]
			if not hit then
				table.insert(unknown, p.Name)
			else
				local d = hit.d
				p.Name = hit.name
				p.Color = colour(d.hex)
				p.Material = material(d.material)
				p.Transparency = d.transparency
				p.Anchored = opts.anchored == true
				p.CanCollide = false
				p.CanQuery = (d.transparency < 0.99) or hit.name == "Hitbox"
				p.CanTouch = hit.name == "Hitbox"
				p.Massless = true
				p.CastShadow = d.transparency < 0.5
				p:SetAttribute("Role", d.role)
				if d.sleep_hex ~= "" then
					p:SetAttribute("SleepHex", d.sleep_hex)
					p:SetAttribute("SleepMaterial", d.sleep_material)
					p:SetAttribute("AwakeHex", d.hex)
					p:SetAttribute("AwakeMaterial", d.material)
				end
				parts[hit.name] = p
			end
		end
	end
	return parts, unknown
end

--.. one Motor6D, built from a fresh Attachment pair at the joint (the zombie-rig recipe)
local function joint(p0, p1, name, pivot)
	local at = CFrame.new(pivot)
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "RigAttachment"
	a0.CFrame = p0.CFrame:Inverse() * at
	a0.Parent = p0
	local a1 = Instance.new("Attachment")
	a1.Name = name .. "RigAttachment"
	a1.CFrame = p1.CFrame:Inverse() * at
	a1.Parent = p1
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = a0.CFrame
	m.C1 = a1.CFrame
	m.Parent = p1
	return m
end

local function buildRig(model, rig, parts)
	local made, skipped = 0, {}
	for part, d in pairs(rig) do
		if d.parent then
			local p1, p0 = parts[part], parts[d.parent]
			if p0 and p1 then
				joint(p0, p1, part, Vector3.new(d.pivot[1], d.pivot[2], d.pivot[3]))
				made += 1
			else
				table.insert(skipped, part)
			end
		end
	end
	return made, skipped
end

--.. Every imported part carries the FBX importer's own axis rotation in its CFrame (it
--.. maps Blender's Z-up onto Roblox's Y-up), so an imported part's LookVector points
--.. DOWN, not forward.  For a MeshPart that is invisible anyway - the mesh is rotated
--.. with it - but the ROOT must not be one: PivotTo uses PrimaryPart.CFrame as the
--.. pivot, so a root with a pitched frame lays the whole guardian on its face the first
--.. time anything moves it.  Root and Hitbox are plain boxes, so swap them for real
--.. axis-aligned Parts covering the same world volume.
local function boxify(part, name)
	local cf, sz = part.CFrame, part.Size
	local ax = cf.RightVector * sz.X
	local ay = cf.UpVector * sz.Y
	local az = cf.LookVector * sz.Z
	local ext = Vector3.new(
		math.abs(ax.X) + math.abs(ay.X) + math.abs(az.X),
		math.abs(ax.Y) + math.abs(ay.Y) + math.abs(az.Y),
		math.abs(ax.Z) + math.abs(ay.Z) + math.abs(az.Z))
	local p = Instance.new("Part")
	p.Name = name
	p.Size = ext
	p.CFrame = CFrame.new(cf.Position)          -- identity: LookVector is -Z, forward
	p.Transparency = 1
	p.Anchored = part.Anchored
	p.CanCollide = false
	p.CanQuery = part.CanQuery
	p.CanTouch = part.CanTouch
	p.Massless = true
	p.CastShadow = false
	p:SetAttribute("Role", part:GetAttribute("Role"))
	p.Parent = part.Parent
	part:Destroy()
	return p
end

--.. install ONE guardian (model + seat + extras) into ServerStorage.Assets.Guardians
local function installOne(name, data, out)
	local model = loadModel(data.asset)
	model.Name = name
	local parts, unknown = dress(model, data.rig)
	assert(parts.Root, name .. ": no Root part after dressing")
	parts.Root = boxify(parts.Root, "Root")
	if parts.Hitbox then parts.Hitbox = boxify(parts.Hitbox, "Hitbox") end
	local root = parts.Root

	local motors, skipped = buildRig(model, data.rig, parts)
	model.PrimaryPart = root

	local hum = Instance.new("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.NameDisplayDistance = 0
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.AutoRotate = true
	hum.MaxHealth = 100
	hum.Health = 100
	hum.Parent = model
	root.Name = "HumanoidRootPart"
	parts.HumanoidRootPart = root
	parts.Root = nil

	--.. HipHeight is the drop from the root's centre to the lowest geometry
	local minY = math.huge
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.99 then
			minY = math.min(minY, (p.CFrame * CFrame.new(0, -p.Size.Y / 2, 0)).Y)
		end
	end
	hum.HipHeight = root.Position.Y - root.Size.Y / 2 - minY
	model:SetAttribute("BaseHipHeight", hum.HipHeight)

	model:SetAttribute("Guardian", name)
	model:SetAttribute("Biome", data.biome)
	model:SetAttribute("Tris", data.tris)
	model:SetAttribute("Notes", data.notes)
	model:SetAttribute("StandHeight", data.spec.stand)
	model:SetAttribute("SitHeight", data.spec.sit)
	model:SetAttribute("Pace", data.spec.pace)
	model:SetAttribute("Awake", false)
	model.WorldPivot = CFrame.new(root.Position)

	--.. the seat and any extras live INSIDE the guardian model's folder, not loose
	local extras = Instance.new("Folder")
	extras.Name = "Props"
	for sname, s in pairs(data.seats or {}) do
		if s.asset ~= "" then
			local sm = loadModel(s.asset)
			sm.Name = (sname:gsub("^" .. name .. "_", ""))
			local sparts = dress(sm, s.rig, {anchored = true})
			local sroot = nil
			for pname, d in pairs(s.rig) do
				if not d.parent then sroot = sparts[pname] end
			end
			sm.PrimaryPart = sroot
			if sroot then sm.WorldPivot = CFrame.new(sroot.Position.X, 0, sroot.Position.Z) end
			sm:SetAttribute("Guardian", name)
			sm.Parent = extras
		end
	end
	extras.Parent = model

	local old = out:FindFirstChild(name)
	if old then old:Destroy() end
	model.Parent = out
	return {name = name, parts = #model:GetChildren(), motors = motors,
	        unknown = unknown, skipped = skipped, hip = hum.HipHeight,
	        props = #extras:GetChildren()}
end

-- ================================================================= public API
function API.install(names)
	local data = payload()
	local out = assets()
	local lines = {}
	for _, name in ipairs(names or {}) do
		local m = data.models[name]
		if not m then
			table.insert(lines, name .. ": NOT IN PAYLOAD")
		elseif m.asset == "" then
			table.insert(lines, name .. ": no asset id")
		else
			local ok, r = pcall(installOne, name, m, out)
			if ok then
				table.insert(lines, ("%-10s %2d motors, %d props, hip %.2f%s%s"):format(
					r.name, r.motors, r.props, r.hip,
					#r.unknown > 0 and ("  UNKNOWN PARTS: " .. table.concat(r.unknown, ",")) or "",
					#r.skipped > 0 and ("  SKIPPED JOINTS: " .. table.concat(r.skipped, ",")) or ""))
			else
				table.insert(lines, name .. ": ERROR " .. tostring(r))
			end
		end
	end
	return table.concat(lines, "\n")
end

function API.verify()
	local data = payload()
	local out = assets()
	local lines, bad = {}, 0
	for name, m in pairs(data.models) do
		local model = out:FindFirstChild(name)
		if not model then
			table.insert(lines, ("%-10s MISSING"):format(name))
			bad += 1
		else
			local parts, motors, grey, wrongMat = 0, 0, 0, 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Parent == model then
					parts += 1
					local want = m.rig[d.Name == "HumanoidRootPart" and "Root" or d.Name]
					-- Root and Hitbox are rebuilt as plain axis-aligned boxes (see
					-- boxify) and are invisible, so their colour is deliberately not
					-- stamped - checking it would fail every model for nothing.
					if want and d.Transparency < 0.99 then
						if d.Color ~= colour(want.hex) then grey += 1 end
						if d.Material ~= material(want.material) then wrongMat += 1 end
					end
				elseif d:IsA("Motor6D") then
					motors += 1
				end
			end
			local hum = model:FindFirstChildOfClass("Humanoid")
			local wantMotors = 0
			for _, d in pairs(m.rig) do if d.parent then wantMotors += 1 end end
			local ok = (parts == m.parts) and (motors == wantMotors) and grey == 0 and wrongMat == 0
			if not ok then bad += 1 end
			table.insert(lines, ("%-10s %s  parts %d/%d  motors %d/%d  colour-bad %d  mat-bad %d  hip %.2f  props %d"):format(
				name, ok and "OK  " or "FAIL", parts, m.parts, motors, wantMotors, grey, wrongMat,
				hum and hum.HipHeight or -1,
				model:FindFirstChild("Props") and #model.Props:GetChildren() or 0))
		end
	end
	table.sort(lines)
	table.insert(lines, bad == 0 and "ALL GOOD" or (bad .. " with problems"))
	return table.concat(lines, "\n")
end

--.. drop a copy of every guardian into Workspace, on its seat, for a look
function API.display(origin, gap)
	origin = origin or Vector3.new(0, 0, -70)
	gap = gap or 22
	local out = assets()
	local disp = workspace:FindFirstChild("GuardianDisplay")
	if disp then disp:Destroy() end
	disp = Instance.new("Folder")
	disp.Name = "GuardianDisplay"
	disp.Parent = workspace
	local i, made = 0, {}
	for _, model in ipairs(out:GetChildren()) do
		local c = model:Clone()
		for _, p in ipairs(c:GetDescendants()) do
			if p:IsA("BasePart") then p.Anchored = true end
		end
		local at = origin + Vector3.new((i % 5) * gap - 2 * gap, 0, math.floor(i / 5) * gap)
		c:PivotTo(CFrame.new(at))
		local props = c:FindFirstChild("Props")
		if props then
			for _, s in ipairs(props:GetChildren()) do
				s.Parent = c.Parent
			end
		end
		c.Parent = disp
		for _, s in ipairs(disp:GetChildren()) do
			if s:IsA("Model") and s:GetAttribute("Guardian") == model.Name and s ~= c then
				s:PivotTo(CFrame.new(at))
			end
		end
		table.insert(made, model.Name)
		i += 1
	end
	return ("displayed %d: %s"):format(#made, table.concat(made, ", "))
end

function API.clear()
	local a = ServerStorage:FindFirstChild("Assets")
	local f = a and a:FindFirstChild(FOLDER)
	local n = f and #f:GetChildren() or 0
	if f then f:Destroy() end
	local disp = workspace:FindFirstChild("GuardianDisplay")
	if disp then disp:Destroy() end
	return "cleared " .. n .. " guardians"
end

--.. put an Anims folder of Animation instances on every installed guardian, from the
--.. ids in anims/anim-ids.json.  Phase 3 then does animator:LoadAnimation(model.Anims.Run)
--.. and never touches an asset id itself.
function API.anims()
	local ids = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "/anim-ids.json"))
	local g = assets()
	local lines, total = {}, 0
	for _, model in ipairs(g:GetChildren()) do
		local folder = model:FindFirstChild("Anims")
		if folder then folder:Destroy() end
		folder = Instance.new("Folder")
		folder.Name = "Anims"
		local made = {}
		for key, id in pairs(ids) do
			local guardian, clip = key:match("^(.-)_(.+)$")
			if guardian == model.Name then
				local a = Instance.new("Animation")
				a.Name = clip
				a.AnimationId = "rbxassetid://" .. tostring(id)
				a.Parent = folder
				table.insert(made, clip)
				total += 1
			end
		end
		table.sort(made)
		folder.Parent = model
		table.insert(lines, ("%-10s %d: %s"):format(model.Name, #made, table.concat(made, " ")))
	end
	table.sort(lines)
	table.insert(lines, total .. " Animation instances")
	return table.concat(lines, "\n")
end

function API.names()
	local data = payload()
	local out = {}
	for n in pairs(data.models) do table.insert(out, n) end
	table.sort(out)
	return table.concat(out, ", ")
end

return API
