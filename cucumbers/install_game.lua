--!nolint
-- Installs the new 57-model cucumber set into NEW MAP CUCUMBER GAME (placeId 87967102884366),
-- replacing the 59 templates in ServerStorage.Assets.BreakableModels and the 59 preview models
-- in ReplicatedStorage.CucumberIndexPreviews.  Run in Studio EDIT mode via execute_luau:
--
--   local f = loadstring(HttpService:GetAsync(BASE .. "install_game.lua"))()
--   f.stage({...names...})   -- LoadAsset + colour the source models (8 per call)
--   f.build()                -- adapt them into the 60 named template slots
--   f.swap()                 -- back up the old sets and swap both folders
--   f.verify()               -- prove the spawner's contract holds
--
-- ===================================================================================
-- WHY THE ADAPTER EXISTS
-- ===================================================================================
-- CucumberSpawner bottom-aligns a spawned cucumber with
--     model:PivotTo(CFrame.new(point + Vector3.new(0, ext.Y / 2, 0)) * yaw)
-- which is only correct if Model:GetPivot() sits at the VERTICAL CENTRE of the model's
-- bounding box.  The old templates got that for free: each had PrimaryPart = an invisible
-- Part named "Hitbox" sized to the whole model and centred on it, and a Model's pivot
-- follows its PrimaryPart.  The new models pivot at their BASE (y = 0), so dropped in
-- as-is every one of them would float ext.Y/2 above the ground - about 1.5 studs for a
-- cucumber and 4.3 for a tree.
--
-- So each template gets:
--   * a "Hitbox"  - invisible Part spanning the visible bbox exactly, set as PrimaryPart.
--                   Fixes the float, and is also what the collect ProximityPrompt, the
--                   ShoulderWeld, the CarryGrip attachment, the carry billboard and the
--                   mutation VFX all anchor to.  The name matters twice over: CucumberSpawner
--                   and CucumberMutations both SKIP parts named "Hitbox" when they overwrite
--                   Color/Material for Golden / Diamond / mutation looks.
--   * a "Shadow"  - thin dark slab at the base.  Also name-skipped by the look passes, and
--                   excluded from ExtentsWithoutShadow, matching the old set.
--   * a Model scale chosen so that after the spawner's TEMPLATE_SCALE = 0.75 the cucumber
--     reads at a sensible size in the field (see TARGET below).
--
-- Type names, zone assignment and the RAW / REWARDS tables are all left ALONE, so
-- CucumberValues rewards, CucumberStrength factors and CucumberAdventure's
-- "<Zone>:<TypeName>" collection keys keep working untouched.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local BASE = "http://127.0.0.1:8765/"
local SOURCE = "__NewCucumberSource"          -- staged, post-processed source models
local BUILT = "__NewCucumberTemplates"        -- the 60 adapted, named template slots
local TEMPLATES = "BreakableModels"
local PREVIEWS = "CucumberIndexPreviews"
local STAMP = "_pre_newset_2026_09_13"

-- in-field target on the model's DOMINANT axis, i.e. AFTER the spawner's x0.75
local TARGET = { cuke = 5.0, slice = 3.4, tree = 8.6, gate = 9.0, prop = 4.6 }
--.. buildall.py groups models for RENDERING, which is not always the right size class here:
--.. the windmill plant is a cucumber stalk with a pinwheel on top, not a tree, and at the
--.. tree target it came out nearly twice its authored height
local ARCH_OVERRIDE = { FarmWindmillPlant = "cuke", SamuraiBambooGrove = "tree" }
local TEMPLATE_SCALE = 0.75                   -- must match CucumberSpawner line 26

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
	return HttpService:JSONDecode(HttpService:GetAsync(BASE .. "game-template-map.json"))
end

--.. world AABB from part CFrames; Model:GetBoundingBox reports in the PIVOT's frame, which
--.. is exactly what we are about to change, so never trust it here
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
--- LoadAsset the uploaded models and restore their authored appearance.  Identical to the
--- Model-testing install: the FBX import yaws everything 180 degrees about Y and drops all
--- colour, so both have to be put back by hand, by part name, from manifest.json.
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
			d.CanCollide = false      -- field cucumbers are props; the Hitbox carries queries
			d.CanTouch = false
			d.CastShadow = true
			d.Massless = true
		end
	end
	model.PrimaryPart = nil
	model.WorldPivot = CFrame.new()
	model:SetAttribute("NewSet", true)
	model.Parent = into
	return { name = name, applied = applied, missed = missed }
end

-- ================================================================= build
--- Turn one staged source model into one named template slot.
local function buildSlot(source, slotName, arch, into)
	local old = into:FindFirstChild(slotName)
	if old then old:Destroy() end

	local model = source:Clone()
	model.Name = slotName
	model:SetAttribute("NewSet", true)
	model:SetAttribute("SourceModel", source.Name)

	--.. the VISIBLE box, measured before Shadow/Hitbox exist so neither can skew it
	local lo, hi = aabb(model, nil)
	if not lo then return nil, "no parts" end
	local size = hi - lo
	local centre = (lo + hi) / 2

	--.. Shadow: thin slab sitting ON the base, so it never lowers min-Y and never changes
	--.. ext.Y (which the spawner's bottom-alignment depends on)
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

	--.. Hitbox: spans the visible box exactly and becomes the PrimaryPart, which puts
	--.. Model:GetPivot() on the box centre - the whole point of this adapter
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = size
	hitbox.CFrame = CFrame.new(centre)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = true            -- the collect prompt and reach check live on this
	hitbox.CanTouch = false
	hitbox.CastShadow = false
	hitbox.Material = Enum.Material.Plastic
	hitbox.Massless = true
	hitbox.TopSurface = Enum.SurfaceType.Smooth
	hitbox.BottomSurface = Enum.SurfaceType.Smooth
	hitbox.Parent = model
	model.PrimaryPart = hitbox

	--.. scale so the DOMINANT axis hits its in-field target after the spawner's x0.75
	local dominant = math.max(size.X, size.Y, size.Z)
	local target = TARGET[arch] or TARGET.cuke
	local k = target / (TEMPLATE_SCALE * math.max(dominant, 0.01))
	model:ScaleTo(k)

	model.Parent = into
	return {
		slot = slotName, source = source.Name, arch = arch, scale = k,
		authored = size, field = size * k * TEMPLATE_SCALE,
	}
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
			table.insert(out, ("%-27s NO PAYLOAD ENTRY"):format(n))
		else
			local res, err = stageOne(n, info, into)
			if not res then
				table.insert(out, ("%-27s FAILED %s"):format(n, err))
			else
				table.insert(out, ("%-27s %2d parts coloured%s"):format(n, res.applied,
					#res.missed > 0 and ("  MISSING:" .. table.concat(res.missed, ",")) or ""))
			end
		end
	end
	return ("staged %d (source folder now %d)\n%s"):format(#names, #into:GetChildren(),
		table.concat(out, "\n"))
end

function API.build()
	local data = payload()
	local map = templateMap().map
	local src = ServerStorage:FindFirstChild(SOURCE)
	if not src then return "nothing staged - run stage() first" end
	local into = folder(ServerStorage, BUILT)
	for _, c in ipairs(into:GetChildren()) do c:Destroy() end

	local rows, made, problems = {}, 0, {}
	for sourceName, slots in pairs(map) do
		local source = src:FindFirstChild(sourceName)
		local info = data.models[sourceName]
		if not source then
			table.insert(problems, "not staged: " .. sourceName)
		else
			local arch = ARCH_OVERRIDE[sourceName] or (info and info.archetype) or "cuke"
			for _, slotName in ipairs(slots) do
				local res, err = buildSlot(source, slotName, arch, into)
				if not res then
					table.insert(problems, ("%s -> %s: %s"):format(sourceName, slotName, err))
				else
					made += 1
					table.insert(rows, ("%-27s <- %-26s %-5s x%.3f  field %.1f x %.1f x %.1f")
						:format(res.slot, res.source, res.arch, res.scale,
							res.field.X, res.field.Y, res.field.Z))
				end
			end
		end
	end
	table.sort(rows)
	return ("built %d template slots%s\n%s"):format(made,
		#problems > 0 and ("\nPROBLEMS: " .. table.concat(problems, "; ")) or "",
		table.concat(rows, "\n"))
end

function API.swap()
	local built = ServerStorage:FindFirstChild(BUILT)
	if not built then return "nothing built - run build() first" end
	local assets = ServerStorage:WaitForChild("Assets")

	--.. keep the old sets in-place rather than destroying them; an .rbxm backup already
	--.. exists on disk but an in-DataModel copy makes a revert a drag-and-drop
	local oldT = assets:FindFirstChild(TEMPLATES)
	if oldT then
		local keep = assets:FindFirstChild(TEMPLATES .. STAMP)
		if keep then keep:Destroy() end
		oldT.Name = TEMPLATES .. STAMP
		oldT.Parent = ServerStorage
	end
	local newT = Instance.new("Folder")
	newT.Name = TEMPLATES
	newT.Parent = assets

	local oldP = ReplicatedStorage:FindFirstChild(PREVIEWS)
	if oldP then
		local keep = ServerStorage:FindFirstChild(PREVIEWS .. STAMP)
		if keep then keep:Destroy() end
		oldP.Name = PREVIEWS .. STAMP
		oldP.Parent = ServerStorage
	end
	local newP = Instance.new("Folder")
	newP.Name = PREVIEWS
	newP.Parent = ReplicatedStorage

	local t, p = 0, 0
	for _, m in ipairs(built:GetChildren()) do
		local tpl = m:Clone()
		tpl.Parent = newT
		t += 1

		--.. the index frames on GetBoundingBox(), which counts invisible parts, so a preview
		--.. keeps neither the Hitbox nor the Shadow - either would zoom the card out
		local pv = m:Clone()
		pv.PrimaryPart = nil
		local h = pv:FindFirstChild("Hitbox")
		if h then h:Destroy() end
		local s = pv:FindFirstChild("Shadow")
		if s then s:Destroy() end
		pv.WorldPivot = CFrame.new()
		pv.Parent = newP
		p += 1
	end
	return ("swapped: %d templates in ServerStorage.Assets.%s, %d previews in ReplicatedStorage.%s\nold sets parked at ServerStorage.%s%s and ServerStorage.%s%s")
		:format(t, TEMPLATES, p, PREVIEWS, TEMPLATES, STAMP, PREVIEWS, STAMP)
end

--- Prove the spawner's contract on the live folders.
function API.verify()
	local RAW = {
		Spawn = {"Sliced Cucumber", "Cucumber", "Slice Stack", "Vined Cucumber", "Flowered Cucumber", "Cucumber Tree"},
		Desert = {"Sun-Dried Slice", "Prickly Cucumber", "Sliced Cucumber", "Sun-Baked Cucumber", "Wrapped Cucumber", "Cactus Cucumber", "Desert Palm", "Sandstone Tree"},
		Samurai = {"Sliced Cucumber", "Katana Cucumber", "Bamboo Cucumber", "Lantern Cucumber", "Bamboo Grove", "Torii Gate", "Sakura Tree"},
		Farm = {"Cucumber Basket", "Muddy Cucumber", "Crate Cucumber", "Windmill Plant", "Hay Bale", "Cucumber Tree"},
		Snow = {"Frozen Slice", "Snowcap Cucumber", "Snowball Slice", "Crystal Cucumber", "Frozen Cucumber", "Snow Tree", "Icicle Tree", "Frozen Tree"},
		Underwater = {"Bubble Slice", "Seaweed Cucumber", "Shell Slice", "Coral Cucumber", "Pearl Cucumber", "Kelp Tree", "Bubble Tree", "Coral Tree"},
		Volcano = {"Molten Slice", "Charred Cucumber", "Molten Cucumber", "Flame Cucumber", "Obsidian Tree", "Volcano Cucumber", "Magma Tree"},
		Narmek = {"Moon Slice", "Meteor Cucumber", "Planet Slice", "Astronaut Cucumber", "Neon Alien Cucumber", "Moon Tree", "Alien Tree", "Galaxy Tree"},
	}
	local need = { ["Cucumber Tree"] = true }
	for zone, list in pairs(RAW) do
		for _, n in ipairs(list) do need[zone .. " " .. n] = true end
	end

	local T = ServerStorage.Assets:FindFirstChild(TEMPLATES)
	local P = ReplicatedStorage:FindFirstChild(PREVIEWS)
	local bad, rows = {}, {}
	local RESERVED = { PlotHitbox = true, CollectPrompt = true }

	local haveT, haveP = {}, {}
	for _, m in ipairs(T and T:GetChildren() or {}) do haveT[m.Name] = m end
	for _, m in ipairs(P and P:GetChildren() or {}) do haveP[m.Name] = m end

	local missingT, missingP = {}, {}
	for n in pairs(need) do
		if not haveT[n] then table.insert(missingT, n) end
		if not haveP[n] then table.insert(missingP, n) end
	end

	local floatCount, worstFloat = 0, 0
	for n, m in pairs(haveT) do
		if not m:IsA("Model") then table.insert(bad, n .. ": not a Model") end
		--.. THE contract: pivot must sit at the vertical centre of the extents, because the
		--.. spawner bottom-aligns with PivotTo(point + ext.Y/2)
		local ext = m:GetExtentsSize()
		local lo = select(1, aabb(m, nil))
		local pv = m:GetPivot().Position.Y
		local drop = (pv - lo.Y) - ext.Y / 2
		if math.abs(drop) > 0.02 then
			floatCount += 1
			if math.abs(drop) > math.abs(worstFloat) then worstFloat = drop end
			table.insert(bad, ("%s: pivot off centre by %+.3f (would float/sink)"):format(n, drop))
		end
		if not m.PrimaryPart then table.insert(bad, n .. ": no PrimaryPart") end
		if m.PrimaryPart and m.PrimaryPart.Name ~= "Hitbox" then
			table.insert(bad, n .. ": PrimaryPart is " .. m.PrimaryPart.Name)
		end
		if not m:FindFirstChild("Shadow") then table.insert(bad, n .. ": no Shadow") end
		for _, d in ipairs(m:GetDescendants()) do
			if RESERVED[d.Name] then table.insert(bad, n .. ": reserved name " .. d.Name) end
		end
		--.. LayFlatIfDisc fires on name-contains-"Slice" AND extZ < 0.45*min(extX,extY);
		--.. a flat group of discs must NOT satisfy the second test or it gets pitched over
		if n:find("Slice", 1, true) then
			local thin = ext.Z < 0.45 * math.min(ext.X, ext.Y)
			table.insert(rows, ("%-27s LayFlatIfDisc would %s  (extZ %.2f vs 0.45*min %.2f)")
				:format(n, thin and "ROTATE IT -- BAD" or "leave it alone", ext.Z,
					0.45 * math.min(ext.X, ext.Y)))
			if thin then table.insert(bad, n .. ": would be pitched over by LayFlatIfDisc") end
		end
	end
	for n, m in pairs(haveP) do
		if m:FindFirstChild("Hitbox") then table.insert(bad, "preview " .. n .. ": has a Hitbox") end
		if m:FindFirstChild("Shadow") then table.insert(bad, "preview " .. n .. ": has a Shadow") end
	end

	table.sort(rows)
	table.sort(bad)
	return ("templates %d/%d  previews %d/%d\nmissing templates: %s\nmissing previews: %s\npivot off-centre: %d (worst %+.3f)\n\n%s\n\n%s")
		:format(#(T and T:GetChildren() or {}), 59, #(P and P:GetChildren() or {}), 59,
			#missingT > 0 and table.concat(missingT, ", ") or "none",
			#missingP > 0 and table.concat(missingP, ", ") or "none",
			floatCount, worstFloat,
			table.concat(rows, "\n"),
			#bad > 0 and ("PROBLEMS:\n  " .. table.concat(bad, "\n  ")) or "NO PROBLEMS")
end

--- Put the old sets back and bin the new ones.
function API.revert()
	local assets = ServerStorage:WaitForChild("Assets")
	local oldT = ServerStorage:FindFirstChild(TEMPLATES .. STAMP)
	local oldP = ServerStorage:FindFirstChild(PREVIEWS .. STAMP)
	if not (oldT or oldP) then return "no parked old sets to revert to" end
	local cur = assets:FindFirstChild(TEMPLATES)
	if cur then cur:Destroy() end
	local curP = ReplicatedStorage:FindFirstChild(PREVIEWS)
	if curP then curP:Destroy() end
	if oldT then oldT.Name = TEMPLATES oldT.Parent = assets end
	if oldP then oldP.Name = PREVIEWS oldP.Parent = ReplicatedStorage end
	return "reverted to the pre-swap sets"
end

function API.cleanup()
	for _, n in ipairs({ SOURCE, BUILT }) do
		local f = ServerStorage:FindFirstChild(n)
		if f then f:Destroy() end
	end
	return "removed the staging folders"
end

return API
