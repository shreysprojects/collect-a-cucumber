--!nolint
-- Rev 3 (2026-09-18): installs the 14 Toyland + Neon models into NEW MAP CUCUMBER GAME
-- (placeId 87967102884366) as spawner templates + index previews.  Unlike install_game.lua
-- (which swapped both whole folders for the 57-model set) this one ADDS 14 named slots to
-- ServerStorage.Assets.BreakableModels and ReplicatedStorage.CucumberIndexPreviews and
-- leaves the other 60 alone.  Run in Studio EDIT mode via execute_luau:
--
--   local f = loadstring(game:GetService("HttpService"):GetAsync(BASE .. "install_rev3.lua"))()
--   f.stage({...collection names...})   -- LoadAsset + restore the authored look (<= 7 per call)
--   f.build()                           -- Hitbox/Shadow adapter + per-model scale
--   f.add()                             -- clone the slots into the two live folders
--   f.verify()                          -- prove the spawner's contract on the 14
--   f.remove()                          -- revert: delete every Rev3 slot from both folders
--   f.cleanup()                         -- drop the staging folders
--
-- Everything the adapter does and why is documented at the top of install_game.lua; the
-- short version: the spawner bottom-aligns with PivotTo(point + ext.Y/2), so the pivot must
-- sit at the vertical centre of the model's box -> an invisible "Hitbox" spanning the box is
-- the PrimaryPart.  "Hitbox" / "Shadow" are also the part names the golden / diamond /
-- mutation look passes skip.
--
-- The two slices are ONE disc standing on its edge (thin along Roblox Z): the spawner's
-- LayFlatIfDisc lays them flat in the field on purpose, and the index card shows them
-- standing like the reference sheet.  verify() checks that they DO satisfy that test.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

--.. serve the cucumbers folder here first: pets-remake/serve.ps1 -Root <cucumbers> -Port 8794
--.. (a private port: another session in the same Studio uses 8765-8767 for its own transfers)
local BASE = "http://127.0.0.1:8794/"
local SOURCE = "__Rev3Source"
local BUILT = "__Rev3Templates"
local TEMPLATES = "BreakableModels"
local PREVIEWS = "CucumberIndexPreviews"
local TEMPLATE_SCALE = 0.75                  -- must match CucumberSpawner TEMPLATE_SCALE
local DISC_THIN_RATIO = 0.45                 -- must match CucumberSpawner DISC_THIN_RATIO

local function hex(h)
	local n = tonumber((tostring(h):gsub("#", "")), 16) or 0
	return Color3.fromRGB(bit32.band(bit32.rshift(n, 16), 255),
		bit32.band(bit32.rshift(n, 8), 255), bit32.band(n, 255))
end

local MATERIAL = {}
for _, m in ipairs(Enum.Material:GetEnumItems()) do MATERIAL[m.Name] = m end

local function folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function payload()
	return HttpService:JSONDecode(HttpService:GetAsync(BASE .. "install-payload.json"))
end
local function templateMap()
	return HttpService:JSONDecode(HttpService:GetAsync(BASE .. "game-template-map-rev3.json")).map
end

--.. world AABB from part CFrames (Model:GetBoundingBox reports in the pivot's frame)
local function aabb(model, skipNames)
	local lo, hi
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not (skipNames and skipNames[d.Name]) then
			local cf, s = d.CFrame, d.Size / 2
			for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
				local p = cf:PointToWorldSpace(Vector3.new(s.X * sx, s.Y * sy, s.Z * sz))
				lo = lo and Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z)) or p
				hi = hi and Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z)) or p
			end end end
		end
	end
	return lo, hi
end

-- ================================================================= stage
local function stageOne(name, info, into)
	local old = into:FindFirstChild(name)
	if old then old:Destroy() end

	local ok, container = pcall(function() return InsertService:LoadAsset(info.assetId) end)
	if not ok or not container then
		return nil, ("LoadAsset failed: %s"):format(tostring(container))
	end
	local src
	for _, ch in ipairs(container:GetChildren()) do
		if ch:IsA("Model") then src = ch break end
	end
	src = src or container

	local model = Instance.new("Model")
	model.Name = name
	for _, ch in ipairs(src:GetChildren()) do ch.Parent = model end
	container:Destroy()

	--.. the FBX importer yaws everything 180 degrees about Y and drops all colour: put both back
	local YAW = CFrame.Angles(0, math.pi, 0)
	local applied, missed = 0, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local short = d.Name:match("%.([^%.]+)$") or d.Name
			d.Name = short
			d.CFrame = YAW * d.CFrame
			local look = info.parts[short]
			if look then
				d.Color = hex(look.hex)
				d.Material = MATERIAL[look.material] or Enum.Material.SmoothPlastic
				d.Transparency = look.transparency or 0
				applied += 1
			else
				table.insert(missed, short)
			end
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CastShadow = d.Material ~= Enum.Material.Neon and (look == nil or (look.transparency or 0) < 0.3)
			d.Massless = true
		end
	end
	model.PrimaryPart = nil
	model.WorldPivot = CFrame.new()
	model:SetAttribute("NewSet", true)
	model:SetAttribute("Rev3", true)
	model:SetAttribute("AssetId", info.assetId)
	model.Parent = into
	return { name = name, applied = applied, missed = missed }
end

-- ================================================================= build
local function buildSlot(source, slotName, target, into)
	local old = into:FindFirstChild(slotName)
	if old then old:Destroy() end

	local model = source:Clone()
	model.Name = slotName
	model:SetAttribute("NewSet", true)
	model:SetAttribute("Rev3", true)
	model:SetAttribute("SourceModel", source.Name)

	local lo, hi = aabb(model, nil)
	if not lo then return nil, "no parts" end
	local size = hi - lo
	local centre = (lo + hi) / 2

	local shadow = Instance.new("Part")
	shadow.Name = "Shadow"
	shadow.Size = Vector3.new(math.max(0.4, size.X * 0.86), 0.08, math.max(0.4, size.Z * 0.86))
	shadow.CFrame = CFrame.new(centre.X, lo.Y + 0.04, centre.Z)
	shadow.Color = hex("141e0f")
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Transparency = 0.62
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CastShadow = false
	shadow.Massless = true
	shadow.TopSurface = Enum.SurfaceType.Smooth
	shadow.BottomSurface = Enum.SurfaceType.Smooth
	shadow.Parent = model

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = size
	hitbox.CFrame = CFrame.new(centre)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = true
	hitbox.CanTouch = false
	hitbox.CastShadow = false
	hitbox.Material = Enum.Material.Plastic
	hitbox.Massless = true
	hitbox.TopSurface = Enum.SurfaceType.Smooth
	hitbox.BottomSurface = Enum.SurfaceType.Smooth
	hitbox.Parent = model
	model.PrimaryPart = hitbox

	local dominant = math.max(size.X, size.Y, size.Z)
	local k = target / (TEMPLATE_SCALE * math.max(dominant, 0.01))
	model:ScaleTo(k)

	model.Parent = into
	return { slot = slotName, source = source.Name, scale = k, authored = size, field = size * k * TEMPLATE_SCALE }
end

-- ================================================================= API
local API = {}

function API.stage(names)
	local data = payload()
	local into = folder(ServerStorage, SOURCE)
	local out = {}
	for _, n in ipairs(names) do
		local info = data.models[n]
		if not info then
			table.insert(out, ("%-28s NO PAYLOAD ENTRY"):format(n))
		else
			local res, err = stageOne(n, info, into)
			if not res then
				table.insert(out, ("%-28s FAILED %s"):format(n, err))
			else
				table.insert(out, ("%-28s %2d parts coloured%s"):format(n, res.applied,
					#res.missed > 0 and ("  MISSING:" .. table.concat(res.missed, ",")) or ""))
			end
		end
	end
	return ("staged %d (source folder now %d)\n%s"):format(#names, #into:GetChildren(), table.concat(out, "\n"))
end

function API.build()
	local map = templateMap()
	local src = ServerStorage:FindFirstChild(SOURCE)
	if not src then return "nothing staged - run stage() first" end
	local into = folder(ServerStorage, BUILT)
	for _, c in ipairs(into:GetChildren()) do c:Destroy() end
	local rows, made, problems = {}, 0, {}
	for sourceName, entry in pairs(map) do
		local source = src:FindFirstChild(sourceName)
		if not source then
			table.insert(problems, "not staged: " .. sourceName)
		else
			for _, slotName in ipairs(entry.slots) do
				local res, err = buildSlot(source, slotName, entry.target, into)
				if not res then
					table.insert(problems, ("%s -> %s: %s"):format(sourceName, slotName, err))
				else
					made += 1
					table.insert(rows, ("%-34s <- %-28s x%.3f  field %.1f x %.1f x %.1f")
						:format(res.slot, res.source, res.scale, res.field.X, res.field.Y, res.field.Z))
				end
			end
		end
	end
	table.sort(rows)
	return ("built %d slots%s\n%s"):format(made,
		#problems > 0 and ("\nPROBLEMS: " .. table.concat(problems, "; ")) or "", table.concat(rows, "\n"))
end

--- Clone every built slot into the live folders (replacing a same-named one).
function API.add()
	local built = ServerStorage:FindFirstChild(BUILT)
	if not built then return "nothing built - run build() first" end
	local T = ServerStorage:WaitForChild("Assets"):WaitForChild(TEMPLATES)
	local P = ReplicatedStorage:WaitForChild(PREVIEWS)
	local t, p = 0, 0
	for _, m in ipairs(built:GetChildren()) do
		local old = T:FindFirstChild(m.Name)
		if old then old:Destroy() end
		m:Clone().Parent = T
		t += 1

		local oldP = P:FindFirstChild(m.Name)
		if oldP then oldP:Destroy() end
		local pv = m:Clone()
		pv.PrimaryPart = nil
		local h = pv:FindFirstChild("Hitbox")
		if h then h:Destroy() end
		local s = pv:FindFirstChild("Shadow")
		if s then s:Destroy() end
		pv.WorldPivot = CFrame.new()
		pv.Parent = P
		p += 1
	end
	return ("added %d templates to ServerStorage.Assets.%s (now %d) and %d previews to ReplicatedStorage.%s (now %d)")
		:format(t, TEMPLATES, #T:GetChildren(), p, PREVIEWS, #P:GetChildren())
end

function API.verify()
	local map = templateMap()
	local T = ServerStorage.Assets:FindFirstChild(TEMPLATES)
	local P = ReplicatedStorage:FindFirstChild(PREVIEWS)
	local bad, rows = {}, {}
	for _, entry in pairs(map) do
		for _, n in ipairs(entry.slots) do
			local m = T and T:FindFirstChild(n)
			local pv = P and P:FindFirstChild(n)
			if not m then table.insert(bad, "missing template " .. n) end
			if not pv then table.insert(bad, "missing preview " .. n) end
			if m then
				local ext = m:GetExtentsSize()
				local lo = select(1, aabb(m, nil))
				local drop = (m:GetPivot().Position.Y - lo.Y) - ext.Y / 2
				if math.abs(drop) > 0.02 then table.insert(bad, ("%s: pivot off centre %+.3f"):format(n, drop)) end
				if not (m.PrimaryPart and m.PrimaryPart.Name == "Hitbox") then table.insert(bad, n .. ": PrimaryPart not Hitbox") end
				if not m:FindFirstChild("Shadow") then table.insert(bad, n .. ": no Shadow") end
				local parts, grey = 0, 0
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						parts += 1
						if d.Name ~= "Hitbox" and d.Name ~= "Shadow" and d.Material == Enum.Material.Plastic
							and math.abs(d.Color.R - 0.639) < 0.01 then grey += 1 end
						if not d.Anchored then table.insert(bad, n .. ": unanchored " .. d.Name) end
					end
				end
				if grey > 0 then table.insert(bad, ("%s: %d parts still import-grey"):format(n, grey)) end
				local lay = ""
				if n:find("Slice", 1, true) then
					--.. a Rev3 slice is ONE upright disc: it MUST satisfy LayFlatIfDisc's thin test
					local vis = select(1, (function()
						local a, b = aabb(m, { Shadow = true, Hitbox = true })
						return b - a
					end)())
					local thin = vis.Z < DISC_THIN_RATIO * math.min(vis.X, vis.Y)
					lay = thin and "  lays flat in the field (ok)" or "  WILL STAND (not thin enough)"
					if not thin then table.insert(bad, n .. ": slice not thin enough to be laid flat") end
				end
				table.insert(rows, ("%-34s %2d parts  ext %.1f x %.1f x %.1f  scale %.3f%s")
					:format(n, parts, ext.X, ext.Y, ext.Z, m:GetScale(), lay))
			end
			if pv and (pv:FindFirstChild("Hitbox") or pv:FindFirstChild("Shadow")) then
				table.insert(bad, "preview " .. n .. " keeps a Hitbox/Shadow")
			end
		end
	end
	table.sort(rows)
	table.sort(bad)
	return ("%s\n\n%s"):format(table.concat(rows, "\n"),
		#bad > 0 and ("PROBLEMS:\n  " .. table.concat(bad, "\n  ")) or "NO PROBLEMS")
end

--- Revert: remove every Rev3 slot from both live folders.
function API.remove()
	local n = 0
	for _, f in ipairs({ ServerStorage.Assets:FindFirstChild(TEMPLATES), ReplicatedStorage:FindFirstChild(PREVIEWS) }) do
		for _, m in ipairs(f and f:GetChildren() or {}) do
			if m:GetAttribute("Rev3") then m:Destroy() n += 1 end
		end
	end
	return ("removed %d Rev3 models"):format(n)
end

function API.cleanup()
	for _, n in ipairs({ SOURCE, BUILT }) do
		local f = ServerStorage:FindFirstChild(n)
		if f then f:Destroy() end
	end
	return "removed the staging folders"
end

return API
