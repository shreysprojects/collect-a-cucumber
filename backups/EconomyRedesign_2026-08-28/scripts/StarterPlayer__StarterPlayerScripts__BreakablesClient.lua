--[[
	BreakablesClient
	All the game-feel for the click-to-smash cucumbers:
	- idle bob + slow spin on every breakable
	- hover glow so they read as clickable
	- squash & stretch punch, damage numbers, character swing on click
	- pet attack bolts flying from YOUR pets to your target
	- chunk explosion + camera kick on break
	Server logic: ServerStorage.ServerController.BreakablesService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local UserInterfaceLoader = require(ReplicatedStorage.Modules.UserInterfaceLoader)
local Network = ControllerLoader.GetController("Network")
local SoundController = ControllerLoader.GetController("SoundController")
local SettingsController = ControllerLoader.GetController("SettingsController")
local HapticUtil = require(ReplicatedStorage.Modules.HapticUtil)
local Notifications = UserInterfaceLoader.CacheModule("Notifications")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera
local Sounds = ReplicatedStorage.Assets:WaitForChild("Sounds")
local Particles = ReplicatedStorage.Assets:WaitForChild("Particles")

local rng = Random.new()

-- Persistent cucumber mutation visuals are client-local and distance-budgeted.
-- Server tags carry only gameplay-safe descriptors, so streamed or distant jackpots
-- do not leave dozens of permanent dynamic lights running on a phone.
local MUTATION_VISUAL_TAG = "CucumberMutationVisual"
local LOCAL_SPARKLES_NAME = "LocalMutationSparkles"
local LOCAL_LIGHT_NAME = "LocalMutationLight"
local lowGraphics = UserInputService.TouchEnabled
pcall(function()
	local saved = UserSettings():GetService("UserGameSettings").SavedQualityLevel
	if saved ~= Enum.SavedQualitySetting.Automatic and saved.Value <= 3 then
		lowGraphics = true
	end
end)
local MAX_MUTATION_SPARKLES = lowGraphics and 8 or 20
local MAX_MUTATION_LIGHTS = lowGraphics and 4 or 10
local MUTATION_VISUAL_DISTANCE = lowGraphics and 120 or 180

local function removeLocalMutationVisual(part)
	if not part then return end
	local sparkle = part:FindFirstChild(LOCAL_SPARKLES_NAME)
	if sparkle then sparkle:Destroy() end
	local light = part:FindFirstChild(LOCAL_LIGHT_NAME)
	if light then light:Destroy() end
end

local function setLocalMutationVisual(part, wantSparkles, wantLight)
	if not part:IsA("BasePart") then return end
	local color = part:GetAttribute("MutationVisualColor")
	if typeof(color) ~= "Color3" then color = Color3.fromRGB(170, 230, 255) end

	local sparkle = part:FindFirstChild(LOCAL_SPARKLES_NAME)
	if wantSparkles then
		if not sparkle then
			sparkle = Instance.new("Sparkles")
			sparkle.Name = LOCAL_SPARKLES_NAME
			sparkle.Parent = part
		end
		sparkle.SparkleColor = color
	elseif sparkle then
		sparkle:Destroy()
	end

	local light = part:FindFirstChild(LOCAL_LIGHT_NAME)
	if wantLight then
		if not light then
			light = Instance.new("PointLight")
			light.Name = LOCAL_LIGHT_NAME
			light.Shadows = false
			light.Parent = part
		end
		light.Color = color
		light.Range = tonumber(part:GetAttribute("MutationVisualRange")) or 14
		light.Brightness = tonumber(part:GetAttribute("MutationVisualBrightness")) or 1.4
	elseif light then
		light:Destroy()
	end
end

local function refreshMutationVisuals()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local nearby = {}
	for _, tagged in ipairs(CollectionService:GetTagged(MUTATION_VISUAL_TAG)) do
		if tagged:IsA("BasePart") and tagged:IsDescendantOf(workspace) then
			local distance = (tagged.Position - hrp.Position).Magnitude
			if distance <= MUTATION_VISUAL_DISTANCE then
				nearby[#nearby + 1] = { Part = tagged, Distance = distance }
			else
				removeLocalMutationVisual(tagged)
			end
		end
	end
	table.sort(nearby, function(a, b) return a.Distance < b.Distance end)
	for index, item in ipairs(nearby) do
		setLocalMutationVisual(item.Part, index <= MAX_MUTATION_SPARKLES, index <= MAX_MUTATION_LIGHTS)
	end
end

CollectionService:GetInstanceRemovedSignal(MUTATION_VISUAL_TAG):Connect(removeLocalMutationVisual)
task.spawn(function()
	while true do
		refreshMutationVisuals()
		task.wait(1)
	end
end)

-- Effect billboards (damage numbers / combo popups / click cooldown) are
-- designed in StarterGui.UITemplates and cloned per use.
local UITemplates = game:GetService("StarterGui"):WaitForChild("UITemplates")

-- Client quality scales automatically for touch devices and can be downgraded
-- later by PerformanceClient if sustained frame rate is low.
local function lowQuality()
	return UserInputService.TouchEnabled or player:GetAttribute("ClientPerformanceTier") == "Low"
end
local animationAccumulator = 0

----------------------------------------------------------------------
-- Registry + idle animation (bob & spin, like PS99 pickups)
----------------------------------------------------------------------
local Base = {} -- [part] = {CFrame, Size, Phase}
local Billboards = {} -- [BillboardGui] = its breakable root part
local committedTarget = nil -- forward-declared: your committed target (set on BreakableTargeted below; the bob loop freezes its spin)

-- Restore a part's original size/offsets when it (re)registers. Pooled cucumbers
-- reuse the same instances and the server repositions but never re-sizes them, so
-- any size drift (e.g. an interrupted hit tween) would persist across reuses. Each
-- part's original size (and a decoration's original offset) is captured once as
-- attributes that ride along on the instance, then restored on every later
-- registration. Tree models are fresh clones each spawn, so they have nothing to undo.
local function normalizeAssembly(rootPart, visualParts, isModel)
	if isModel then return end
	local rootOrig = rootPart:GetAttribute("BC_OSize")
	if not rootOrig then
		rootPart:SetAttribute("BC_OSize", rootPart.Size)
	else
		rootPart.Size = rootOrig
	end
	local rootCF = rootPart.CFrame
	for _, d in ipairs(visualParts) do
		if d.Parent and d.Name ~= "Shadow" then
			local oSize = d:GetAttribute("BC_OSize")
			local oRel = d:GetAttribute("BC_ORel")
			if oSize and oRel then
				local weld = d:FindFirstChildWhichIsA("WeldConstraint")
				if weld then weld.Enabled = false end
				d.Size = oSize
				d.CFrame = rootCF * oRel
				if weld then weld.Enabled = true end
			else
				d:SetAttribute("BC_OSize", d.Size)
				d:SetAttribute("BC_ORel", rootCF:ToObjectSpace(d.CFrame))
			end
		end
	end
end

local function register(item)
	task.wait() -- let the server finish positioning
	if not item.Parent then return end
	local part = item:IsA("BasePart") and item
		or (item:IsA("Model") and (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)))
	if not part then
		-- With streaming, a Model container can arrive before its PrimaryPart. Retry
		-- registration on the first streamed BasePart instead of permanently missing it.
		if item:IsA("Model") then
			local retryConnection
			retryConnection = item.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("BasePart") then
					retryConnection:Disconnect()
					task.spawn(register, item)
				end
			end)
		end
		return
	end

	local visualParts = {}
	local lights = {}
	for _, descendant in ipairs(item:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= part then
			table.insert(visualParts, descendant)
		elseif descendant:IsA("Light") or descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") then
			table.insert(lights, descendant)
		end
	end

	-- Restore this part's original size before caching its baseline (pooled parts
	-- are reused as the same instances, so any size drift would persist otherwise).
	normalizeAssembly(part, visualParts, item:IsA("Model"))

	local billboard = item:FindFirstChild("HPBar", true)
	if billboard then
		Billboards[billboard] = part
		--.. the authored template ships MaxDistance 300, but a bar built before that
		--.. change (or carried in on a pooled part) can still hold the old 90, which
		--.. the ENGINE enforces regardless of .Enabled -- normalize it on registration
		if billboard.MaxDistance < 300 then billboard.MaxDistance = 300 end
	end

	local entry = {
		CFrame = part.CFrame;
		Size = part.Size;
		Phase = rng:NextNumber(0, math.pi * 2);
		Root = item;
		VisualParts = visualParts;
		Lights = lights;
		Billboard = billboard;
		Animate = item:IsA("BasePart");
	}
	Base[part] = entry

	-- Atomic/non-atomic streamed models may receive visual descendants after their
	-- root registered. Track those arrivals so an off-biome cucumber cannot leave
	-- late-streamed mesh pieces, shadows, effects, or its HP bar visible.
	item.DescendantAdded:Connect(function(descendant)
		if Base[part] ~= entry then return end
		if descendant:IsA("BasePart") and descendant ~= part then
			descendant.LocalTransparencyModifier = 1
			table.insert(entry.VisualParts, descendant)
		elseif descendant:IsA("Light") or descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") then
			descendant.Enabled = false
			table.insert(entry.Lights, descendant)
		elseif descendant:IsA("BillboardGui") and descendant.Name == "HPBar" then
			descendant.Enabled = false
			Billboards[descendant] = part
			entry.Billboard = descendant
		end
	end)
end

task.spawn(function()
	local container = workspace:WaitForChild("Breakables", 30)
	if not container then return end
	for _,zoneFolder in ipairs(container:GetChildren()) do
		for _,part in ipairs(zoneFolder:GetChildren()) do
			task.spawn(register, part)
		end
		zoneFolder.ChildAdded:Connect(function(part) task.spawn(register, part) end)
	end
	container.ChildAdded:Connect(function(zoneFolder)
		zoneFolder.ChildAdded:Connect(function(part) task.spawn(register, part) end)
	end)
	-- Track every health bar directly too, including bars nested inside tree models.
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BillboardGui") and descendant.Name == "HPBar" and descendant.Parent:IsA("BasePart") then
			Billboards[descendant] = descendant.Parent
		end
	end
	container.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BillboardGui") and descendant.Name == "HPBar" and descendant.Parent:IsA("BasePart") then
			Billboards[descendant] = descendant.Parent
		end
	end)
end)

-- Only your single committed target bobs. This previously walked the ENTIRE Base
-- table (every cucumber in every loaded zone) 20-30x/sec just to animate one part
-- and lazily clean dead entries; now it touches only committedTarget. Dead-entry
-- cleanup moved to the 0.45s LOD pass below (which already iterates Base).
local lastAnimatedPart = nil -- part we last applied a bob offset to (so we can restore it)
RunService.Heartbeat:Connect(function(dt)
	animationAccumulator += dt
	local interval = lowQuality() and (1 / 20) or (1 / 30)
	if animationAccumulator < interval then return end
	animationAccumulator %= interval

	local target = committedTarget
	local base = target and Base[target]

	-- Restore the previously-bobbed part once the target changes or clears.
	if lastAnimatedPart and lastAnimatedPart ~= target then
		local prev = Base[lastAnimatedPart]
		if prev and lastAnimatedPart.Parent then
			lastAnimatedPart.CFrame = prev.CFrame
		end
		lastAnimatedPart = nil
	end

	if target and target.Parent and base and base.Animate then
		-- upward-only bob: rest pose now touches the ground, so never dip below it
		local bob = (math.sin(os.clock() * 1.6 + base.Phase) + 1) * 0.45
		target.CFrame = base.CFrame * CFrame.new(0, bob, 0)
		lastAnimatedPart = target
	end
end)

-- Per-client visual LOD: HP bars only exist visually nearby/while targeted, and
-- expensive decorative parts/lights disappear outside the player's active area.
--
--.. YOUR CURRENT BIOME NEVER CULLS (2026-08-19, user request "cucumbers in the
--.. biome you are in all load, nothing is unloaded"). The culling below is purely
--.. RADIAL and was zone-blind, but a biome is far wider than its own thresholds:
--.. the walkable ZoneParts slabs are 142-243 studs across, so the worst-case
--.. in-biome sightline runs 160-249 studs. That blew past detailRange (105) and
--.. billboardRange (58) everywhere, and past renderRange on low tier (145) in 7
--.. of 8 biomes -- so cucumbers on the far side of YOUR OWN biome went bare, lost
--.. their name tags, and Cucumber Trees vanished outright (a tree's root is an
--.. invisible Hitbox, so every visible part of it counts as a cullable "detail").
--.. Engine streaming was NOT involved (StreamingTargetRadius is the stock 1024)
--.. and the server has no distance logic at all, so this is the only layer that
--.. needed to change. Every OTHER biome keeps exactly the culling it had before.
local ZonePartsFolder
local function nearestBiome(hrp)
	if not ZonePartsFolder or not ZonePartsFolder.Parent then
		local zones = workspace:FindFirstChild("Zones")
		ZonePartsFolder = zones and zones:FindFirstChild("ZoneParts")
		if not ZonePartsFolder then return nil end -- no folder: fall back to old behavior
	end
	local best, bestDist
	local px, pz = hrp.Position.X, hrp.Position.Z
	for _, zonePart in ipairs(ZonePartsFolder:GetChildren()) do
		if zonePart:IsA("BasePart") then
			local dx, dz = px - zonePart.Position.X, pz - zonePart.Position.Z
			local d = dx * dx + dz * dz
			if not bestDist or d < bestDist then best, bestDist = zonePart.Name, d end
		end
	end
	return best
end

--.. MUST mirror the server's commitment rule in BreakablesService.ActiveZones()
--.. (changed 2026-08-21): your biome is the one you last stood INSIDE, and that
--.. commitment HOLDS while you roam border land — the server keeps that biome
--.. populated, so the client must keep rendering it. "Inside" is tested against
--.. the named ZoneParts SLAB (the whole walkable biome: hub, egg stand,
--.. vendors), exactly like the server's SlabZoneAt — NOT the narrower SpawnArea
--.. cucumber field. The first mirror attempt mapped SpawnArea regions
--.. geometrically and silently missed Spawn (its slab center sits at the hub,
--.. outside its own field region), which hid a biome's cucumbers while standing
--.. right in it ("didn't leave the biome, just the spawn area" report
--.. 2026-08-21). Nearest remains only as the fresh-spawn fallback.
local lastInhabitedBiome
local function biomeContaining(position)
	if not ZonePartsFolder or not ZonePartsFolder.Parent then
		local zones = workspace:FindFirstChild("Zones")
		ZonePartsFolder = zones and zones:FindFirstChild("ZoneParts")
		if not ZonePartsFolder then return nil end
	end
	for _, slab in ipairs(ZonePartsFolder:GetChildren()) do
		if slab:IsA("BasePart") then
			--.. same bounds + padding as the server's SlabZoneAt
			local lp = slab.CFrame:PointToObjectSpace(position)
			if math.abs(lp.X) <= slab.Size.X * 0.5 + 6
				and math.abs(lp.Z) <= slab.Size.Z * 0.5 + 6
				and lp.Y >= -15 and lp.Y <= 150
			then
				return slab.Name
			end
		end
	end
	return nil
end

local function currentBiome(hrp)
	local inside = biomeContaining(hrp.Position)
	if inside then
		lastInhabitedBiome = inside
		return inside
	end
	return lastInhabitedBiome or nearestBiome(hrp)
end

--.. a breakable's biome is just the folder it lives in (server parents every
--.. cucumber/tree/boss straight into Breakables.<Zone>), so this costs nothing
local function biomeOf(base)
	local root = base.Root
	local folder = root and root.Parent
	return folder and folder.Name or nil
end

--.. ADJACENT-BIOME STREAM-IN (2026-08-27): on measured high-end devices
--.. (server-stamped "StreamTier" player attribute — StreamTierClient
--.. benchmarks, DeviceStreamingServer validates + stamps) the biome BEFORE
--.. and AFTER yours render in full too. The server already keeps every
--.. player's ±1 biomes fully populated (BreakablesService.ActiveZones) and
--.. RequestStreamAroundAsync's their fields for High players, so showing
--.. them here only costs render time high-end devices have. Low tier (or
--.. no report yet) = the original own-biome-only culling, unchanged.
--.. MUST mirror BreakablesService.ZONES.
local STREAM_ZONES = {"Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek"}
local function shownBiomes(myBiome)
	if not myBiome then return nil end
	local allowed = {[myBiome] = true}
	if player:GetAttribute("StreamTier") == "High" then
		local index = table.find(STREAM_ZONES, myBiome)
		if index then
			if STREAM_ZONES[index - 1] then allowed[STREAM_ZONES[index - 1]] = true end
			if STREAM_ZONES[index + 1] then allowed[STREAM_ZONES[index + 1]] = true end
		end
	end
	return allowed
end

task.spawn(function()
	while true do
		task.wait(lowQuality() and 0.75 or 0.45)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		--.. resolved once per tick (8 cheap XZ compares), not per cucumber
		local myBiome = hrp and currentBiome(hrp) or nil
		--.. your biome, plus its neighbors on high-end devices (nil = hide all)
		local shown = shownBiomes(myBiome)

		for part, base in pairs(Base) do
			if not part.Parent then
				Base[part] = nil -- dead-entry cleanup (moved here from the per-frame bob loop)
			elseif hrp then
				--.. anything standing in the biome you're standing in renders in full,
				--.. at any distance. Recomputed every tick from live parenting, so the
				--.. biome you WALK OUT OF drops straight back to normal culling (the
				--.. assignments below are unconditional, nothing can stay stuck visible),
				--.. and a pooled part reused in another biome is re-evaluated on arrival.
				local inMyBiome = shown ~= nil and shown[biomeOf(base)] == true
				--.. the intro cutscene (IntroCutsceneClient) hides every cucumber in
				--.. the world; while it is on screen this pass must not fight that —
				--.. treating everything as off-biome keeps the unconditional
				--.. assignments below, so normal culling resumes on the next tick
				--.. after the cutscene clears the attribute
				if player:GetAttribute('IntroCutsceneActive') == true then
					inMyBiome = false
				end
				-- Cucumbers outside the player's biome never render locally. Engine
				-- streaming can then discard their assemblies without an off-biome
				-- target/effect keeping them visually active.
				local hideRoot = not inMyBiome
				local hideDetails = hideRoot

				-- Hide the actual root too; previously only decorative children were
				-- culled, so the high-volume cucumber bodies still rendered globally.
				part.LocalTransparencyModifier = hideRoot and 1 or 0
				for _, visual in ipairs(base.VisualParts) do
					if visual.Parent then visual.LocalTransparencyModifier = hideDetails and 1 or 0 end
				end
				for _, effect in ipairs(base.Lights) do
					if effect.Parent then effect.Enabled = inMyBiome end
				end
			end
		end

		for billboard, rootPart in pairs(Billboards) do
			if billboard.Parent and rootPart.Parent and hrp then
				local rootBase = Base[rootPart]
				--.. name tags follow the same rule: everything in your biome keeps its bar
				local inMyBiome = shown ~= nil and rootBase ~= nil and shown[biomeOf(rootBase)] == true
				billboard.Enabled = inMyBiome
			else
				Billboards[billboard] = nil
			end
		end
	end
end)

----------------------------------------------------------------------
-- Hover highlight: the glow IS the click affordance. It only shows on
-- breakables inside your pickaxe's reach — no glow, no click.
-- (Reach mirrors the server: 20 + pickaxe Range * 3.)
-- Replaced the old white ground ring 2026-08-13 (user request): the whole
-- cucumber now glows via a Highlight, same mechanism as the tutorial's
-- WorldHighlight. One reusable instance, re-adorned per tick.
----------------------------------------------------------------------
--.. defined/assigned in the pickaxe-strike section below; forward-declared so
--.. the hover loop resolves hovered parts to their breakable root EXACTLY like
--.. clicks do, using the same folder-scoped raycast
local breakableRootOf
local breakablesRoot

--.. a POOL of highlights, one per visible part: a Highlight adorned to a bare
--.. BasePart does not cover the part's children, and most of a cucumber's body
--.. IS child parts (Flesh + Seeds on the sliced disc, stem/leaf decorations) --
--.. a single adornment lit only fragments of it. Per-part adorning also lets
--.. us skip parts that must NOT glow (ground Shadow blobs, invisible hitboxes).
local HOVER_POOL_SIZE = 16
local hoverHighlights = {}
do
	local gui = player:WaitForChild("PlayerGui")
	for i = 1, HOVER_POOL_SIZE do
		local h = Instance.new("Highlight")
		h.Name = "HoverHighlight" .. i
		h.FillColor = Color3.fromRGB(255, 255, 255)
		h.FillTransparency = 0.75
		h.OutlineColor = Color3.fromRGB(255, 255, 255)
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = nil
		h.Parent = gui
		hoverHighlights[i] = h
	end
end

--.. every visible BasePart of the whole breakable (root part or wrapping Model),
--.. skipping shadows and near-invisible utility geometry
local function collectGlowParts(root)
	local container = (root.Parent and root.Parent:IsA("Model")) and root.Parent or root
	local targets = {}
	local function consider(p)
		if p:IsA("BasePart") and p.Transparency < 0.95 and p.Name ~= "Shadow" then
			targets[#targets + 1] = p
		end
	end
	consider(container)
	for _, d in ipairs(container:GetDescendants()) do
		consider(d)
	end
	if #targets == 0 then targets[1] = root end -- never leave a hover with zero affordance
	return targets
end

--.. mobile bosses get NO ground circles (hover or commit): the rings size off the
--.. rotated body's 26-stud length, float at waist height, and stay behind when it
--.. walks — the boss's HP bar is its affordance instead
local function isMobileBossPart(part)
	local model = part and part.Parent
	return model ~= nil and model:IsA("Model") and model:GetAttribute("MobileBoss") == true
end

--.. You have to walk up to a cucumber to swing at it. Measured from the part's SURFACE,
--.. so a big boss is still hittable from its edge instead of demanding you stand inside it.
--.. MUST stay in step with PICKAXE_REACH / ReachOf in BreakablesService: the server re-checks
--.. every strike and silently drops anything it disagrees with, so a client that thinks it
--.. reaches further just produces dead clicks.
local PICKAXE_REACH = 30 -- keep in step with BreakablesService (10 -> 14 -> 30, 2026-08-23)
--.. ("Too far away!" notification removed 2026-08-13, user request: out-of-reach
--.. clicks just play the miss swoosh now)

local function myReach(part)
	local radius = part and math.max(part.Size.X, part.Size.Z) * 0.5 or 0
	return radius + PICKAXE_REACH
end

task.spawn(function()
	local hoverRayParams
	local currentHoverRoot
	while true do
		task.wait(0.08)
		--.. same Include-filtered raycast + root climber as the click path.
		--.. Raw mouse.Target let invisible utility volumes (Zones regions,
		--.. SpawnArea fillers, CanQuery=true + Transparency 1) eat the hover:
		--.. the low flat sliced discs only highlighted when the camera looked
		--.. up from UNDER the volumes. The glow must show from exactly the
		--.. angles a click would land on.
		local root
		if breakablesRoot and breakableRootOf then
			if not hoverRayParams then
				hoverRayParams = RaycastParams.new()
				hoverRayParams.FilterType = Enum.RaycastFilterType.Include
				hoverRayParams.FilterDescendantsInstances = { breakablesRoot }
			end
			local cam = workspace.CurrentCamera
			local mpos = UserInputService:GetMouseLocation()
			local unitRay = cam:ViewportPointToRay(mpos.X, mpos.Y)
			local hit = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, hoverRayParams)
			root = hit and breakableRootOf(hit.Instance) or nil
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not (root and hrp and not isMobileBossPart(root) and (hrp.Position - root.Position).Magnitude <= myReach(root)) then
			root = nil
		end
		--.. re-adorn the pool only when the hovered breakable actually changes
		if root ~= currentHoverRoot then
			currentHoverRoot = root
			local targets = root and collectGlowParts(root) or {}
			for i, h in ipairs(hoverHighlights) do
				h.Adornee = targets[i]
			end
		end
	end
end)

----------------------------------------------------------------------
-- Sounds
----------------------------------------------------------------------
local SoundPools = {}
local SoundsActive = {} -- [name] = currently-playing count (per-name concurrency cap)
local function playSound(name, pitchVar, volume, parent)
	--.. SFX toggle gate (mirrors how CarryShowcaseClient honors the setting)
	if not SettingsController.ValidateSetting("SFX", false) then return end
	local template = Sounds:FindFirstChild(name)
	if not template then return end
	if (SoundsActive[name] or 0) >= 4 then return end -- spam cap per sound name
	local pool = SoundPools[name]
	if not pool then
		pool = {}
		SoundPools[name] = pool
	end
	local sound = table.remove(pool) or template:Clone()
	sound.PlaybackSpeed = 1 + rng:NextNumber(-pitchVar, pitchVar)
	sound.Volume = volume or template.Volume
	sound.TimePosition = 0
	if parent and parent.Parent then
		--.. 3D: ride the struck part so the hit pans/attenuates from where it landed
		sound.RollOffMinDistance = 8
		sound.RollOffMaxDistance = 70
		sound.Parent = parent
	else
		sound.Parent = workspace
	end
	SoundsActive[name] = (SoundsActive[name] or 0) + 1
	--.. release the concurrency slot when the AUDIO ends, not at the 3s pool
	--.. reclaim: short hit sounds held their slot for 3s each, so ~3 clicks/s
	--.. starved the 4-slot cap into silence after a few hits (user-reported
	--.. 2026-08-26). Destroying covers sounds that die with their part.
	local released = false
	local function release()
		if released then return end
		released = true
		SoundsActive[name] = math.max(0, (SoundsActive[name] or 1) - 1)
	end
	local endedConn = sound.Ended:Once(release)
	local destroyingConn = sound.Destroying:Once(release)
	sound:Play()
	task.delay(3, function()
		endedConn:Disconnect()
		destroyingConn:Disconnect()
		release()
		sound:Stop()
		--.. a sound parented to a breakable can die WITH the part (tree models are
		--.. destroyed); a destroyed sound has a locked Parent, so pcall the detach
		--.. and only reclaim sounds that made it back off the part cleanly
		local detached = pcall(function() sound.Parent = nil end)
		if detached and #pool < 4 then
			table.insert(pool, sound)
		else
			sound:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- Shared juice helpers (SFX/game-feel pass 2026-08-26)
----------------------------------------------------------------------
--.. crit vignette: one reusable white screen-edge flash. PARKED 2026-08-27
--.. (user): the crit celebration was removed -- no live callers; kept for
--.. an easy revert.
local critVignetteStroke
local function critVignettePulse()
	if not critVignetteStroke then
		local gui = Instance.new("ScreenGui")
		gui.Name = "CritVignette"
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 30
		gui.ResetOnSpawn = false
		gui.Parent = player:WaitForChild("PlayerGui")
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 26
		stroke.Transparency = 1
		stroke.Parent = frame
		critVignetteStroke = stroke
	end
	critVignetteStroke.Transparency = 0.35
	TweenService:Create(critVignetteStroke, TweenInfo.new(0.1), {Transparency = 1}):Play()
end

--.. ground shockwave ring (recipe copied from BossMotionClient.burstRing)
local function burstRing(pos, color, startDia, endDia, duration)
	local ringPart = Instance.new("Part")
	ringPart.Shape = Enum.PartType.Cylinder
	ringPart.Size = Vector3.new(0.3, startDia, startDia)
	ringPart.CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ringPart.Material = Enum.Material.Neon
	ringPart.Color = color
	ringPart.Transparency = 0.1
	ringPart.Anchored = true
	ringPart.CanCollide = false
	ringPart.CanQuery = false
	ringPart.CanTouch = false
	ringPart.CastShadow = false
	ringPart.Parent = workspace
	TweenService:Create(ringPart, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, endDia, endDia);
		Transparency = 1;
	}):Play()
	Debris:AddItem(ringPart, duration + 0.1)
end

--.. golden hits shed a couple of gold flecks (same recipe as punch()'s crumbs)
local function goldenCrumbs(part)
	if not part or not part.Parent then return end
	local crumbPart = Instance.new("Part")
	crumbPart.Name = "LocalGoldCrumbs"
	crumbPart.Anchored = true
	crumbPart.CanCollide = false
	crumbPart.CanQuery = false
	crumbPart.Transparency = 1
	crumbPart.Size = part.Size * 0.8
	crumbPart.CFrame = part.CFrame
	crumbPart.Parent = workspace
	local crumbs = Instance.new("ParticleEmitter")
	crumbs.Color = ColorSequence.new(Color3.fromRGB(255, 226, 110), Color3.fromRGB(212, 165, 30))
	crumbs.LightEmission = 0.35
	crumbs.Lifetime = NumberRange.new(0.6, 1)
	crumbs.Speed = NumberRange.new(9, 16)
	crumbs.SpreadAngle = Vector2.new(360, 360)
	crumbs.Acceleration = Vector3.new(0, -70, 0)
	crumbs.Drag = 0.5
	crumbs.Rotation = NumberRange.new(0, 360)
	crumbs.RotSpeed = NumberRange.new(-180, 180)
	crumbs.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	crumbs.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.75, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	crumbs.Parent = crumbPart
	crumbs:Emit(rng:NextInteger(2, 3))
	Debris:AddItem(crumbPart, 1)
end

--.. tiny multicolor pop for combo milestones, reusing the HUD cucumber
--.. shower template (Particles["Cucumber Particle"]) re-tinted per burst
local function comboConfetti(part)
	local template = Particles:FindFirstChild("Cucumber Particle")
	if not template or not part then return end
	local host = Instance.new("Part")
	host.Name = "ComboConfetti"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Transparency = 1
	host.Size = Vector3.one
	host.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y * 0.5 + 1, 0))
	host.Parent = workspace
	for _, tint in ipairs({Color3.fromRGB(255, 95, 95), Color3.fromRGB(255, 220, 80), Color3.fromRGB(120, 200, 255)}) do
		local e = template:Clone()
		e.Enabled = false
		e.Color = ColorSequence.new(tint)
		e.Parent = host
		e:Emit(4)
	end
	Debris:AddItem(host, 2)
end

--.. diamond break: a slow glittering fall (Cucumber Explode's Sparkles
--.. emitter when present, else the cucumber shower), slowed + pulled down
local function sparkleFall(position, sizeMag)
	local folder = Particles:FindFirstChild("Cucumber Explode")
	local template = (folder and folder:FindFirstChild("Sparkles")) or Particles:FindFirstChild("Cucumber Particle")
	if not template then return end
	local host = Instance.new("Part")
	host.Name = "DiamondSparkleFall"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Transparency = 1
	host.Size = Vector3.one
	host.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0))
	host.Parent = workspace
	local e = template:Clone()
	e.Enabled = false
	e.Color = ColorSequence.new(Color3.fromRGB(230, 250, 255), Color3.fromRGB(160, 220, 255))
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(75, 75)
	e.Acceleration = Vector3.new(0, -14, 0)
	e.Parent = host
	e:Emit(math.clamp(math.floor((sizeMag or 6) * 2), 10, 24))
	Debris:AddItem(host, 2)
end

----------------------------------------------------------------------
-- HP ghost bar: a white afterimage behind the fill that drains down to
-- the new size after each confirmed hit, plus a one-time deep crunch the
-- first time your hit drags a breakable under 15% HP.
----------------------------------------------------------------------
local GhostBars = setmetatable({}, {__mode = "k"}) -- [Bar frame] = {Ghost, Crunched}; dies with the bar
local function updateGhostBar(part)
	local billboard = part and part:FindFirstChild("HPBar")
	local barBack = billboard and billboard:FindFirstChild("BarBack")
	local bar = barBack and barBack:FindFirstChild("Bar")
	if not bar then return end
	local entry = GhostBars[bar]
	if not entry or entry.Ghost.Parent ~= barBack then
		local ghost = Instance.new("Frame")
		ghost.Name = "GhostFill"
		ghost.BackgroundColor3 = Color3.new(1, 1, 1)
		ghost.BorderSizePixel = 0
		ghost.ZIndex = 0 -- under the live fill (Bar ships at ZIndex 1)
		ghost.Size = UDim2.new(1, 0, 1, 0) -- bars start full
		local corner = Instance.new("UICorner")
		corner.Parent = ghost
		ghost.Parent = barBack
		entry = {Ghost = ghost; Crunched = false;}
		GhostBars[bar] = entry
	end
	local ghost = entry.Ghost
	local prevFrac = ghost.Size.X.Scale
	local newFrac = bar.Size.X.Scale -- the server already shrank the live fill
	if prevFrac < newFrac then
		--.. respawned/healed bar: snap the ghost, never let it "grow" a chunk
		ghost.Size = UDim2.new(newFrac, 0, 1, 0)
		entry.Crunched = newFrac < 0.15
		return
	end
	TweenService:Create(ghost, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(newFrac, 0, 1, 0);
	}):Play()
	if newFrac < 0.15 and prevFrac >= 0.15 and not entry.Crunched then
		entry.Crunched = true
		--.. "almost dead" tell, once per breakable life
		SoundController.PlayFX("Wet Crunch", {Speed = 0.6, Volume = 0.4, Parent = part})
	end
end

----------------------------------------------------------------------
-- Squash & stretch punch
----------------------------------------------------------------------
local HitTweens = {}
local HitSerial = {}

--.. Hit shake (user request 2026-08-21): a short positional rattle on every
--.. hit, layered under the squash & stretch pop. Two write paths because two
--.. different things own breakable CFrames on this client:
--..   * consolidated Parts — the idle bob loop rewrites the CURRENT target's
--..     CFrame from Base[part].CFrame every frame, so the shake perturbs that
--..     baseline (the loop composes it in) and ALSO writes the part directly
--..     for non-target parts, which have no per-frame writer;
--..   * mesh Models — nothing animates them, so jitter the pivot directly.
--.. Mobile bosses are excluded: the server walks them, and restoring a
--.. captured pivot would yank them backwards against replication. Rapid hits
--.. reuse the FIRST shake's rest pose so drift can never accumulate, and a
--.. botched restore self-heals anyway: pool reuse re-CFrames server-side.
--.. Shake bookkeeping lives ON the registration entry, never keyed by the part
--.. instance: pooled cucumbers REUSE instances, and a part-keyed origin that
--.. survived a mid-shake break teleported the part's next life back to its old
--.. position ("cucumbers disappear" user report 2026-08-21). An entry dies with
--.. re-registration, so stale state is structurally impossible now.
local SHAKE_LIFE = 0.13
local function shake(part)
	local base = Base[part]
	if not base or not part.Parent or isMobileBossPart(part) then return end
	local root = base.Root
	local model = (root and root:IsA("Model")) and root or nil

	local token = (base.ShakeSerial or 0) + 1
	base.ShakeSerial = token
	local origin = base.ShakeOrigin
	if not origin then
		origin = model and model:GetPivot() or base.CFrame
		base.ShakeOrigin = origin
	end

	local mag = math.clamp(part.Size.Magnitude * 0.02, 0.08, 0.3)
	local started = os.clock()
	while true do
		--.. a newer shake on this entry owns the restore now
		if Base[part] ~= base or base.ShakeSerial ~= token then return end
		local alive = model and model.Parent or (not model and part.Parent)
		if not alive then
			--.. broke mid-shake: clear so nothing outlives this life
			base.ShakeSerial = nil
			base.ShakeOrigin = nil
			return
		end
		local remaining = 1 - (os.clock() - started) / SHAKE_LIFE
		if remaining <= 0 then break end
		local off = CFrame.new(
			rng:NextNumber(-mag, mag) * remaining,
			rng:NextNumber(0, mag * 0.5) * remaining,
			rng:NextNumber(-mag, mag) * remaining
		) * CFrame.Angles(
			math.rad(rng:NextNumber(-1.5, 1.5)) * remaining,
			math.rad(rng:NextNumber(-3, 3)) * remaining,
			math.rad(rng:NextNumber(-1.5, 1.5)) * remaining
		)
		if model then
			model:PivotTo(origin * off)
		else
			base.CFrame = origin * off
			part.CFrame = origin * off
		end
		task.wait()
	end
	if Base[part] ~= base or base.ShakeSerial ~= token then return end
	base.ShakeSerial = nil
	base.ShakeOrigin = nil
	if model then
		if model.Parent then model:PivotTo(origin) end
	elseif part.Parent then
		base.CFrame = origin
		part.CFrame = origin
	end
end

local function punch(part)
	local base = Base[part]
	if not base or not part.Parent then return end
	task.spawn(shake, part)

	HitSerial[part] = (HitSerial[part] or 0) + 1
	local serial = HitSerial[part]
	if HitTweens[part] then HitTweens[part]:Cancel() end

	-- Client-only impact flash and cucumber-colored spark burst.
	local flash = Instance.new("Highlight")
	flash.Name = "LocalHitFlash"
	flash.Adornee = base.Root or part
	flash.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	flash.FillColor = Color3.fromRGB(185, 255, 125)
	flash.FillTransparency = 0.18
	flash.OutlineColor = Color3.fromRGB(255, 255, 255)
	flash.OutlineTransparency = 0
	flash.Parent = workspace
	TweenService:Create(flash, TweenInfo.new(0.18), {FillTransparency = 1; OutlineTransparency = 1;}):Play()
	Debris:AddItem(flash, 0.22)

	local burstPart = Instance.new("Part")
	burstPart.Name = "LocalHitBurst"
	burstPart.Anchored = true
	burstPart.CanCollide = false
	burstPart.CanQuery = false
	burstPart.Transparency = 1
	burstPart.CFrame = part.CFrame
	burstPart.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(part.Color, Color3.fromRGB(220, 255, 145))
	emitter.LightEmission = 0.8
	emitter.Lifetime = NumberRange.new(0.18, 0.35)
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 5
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.32),
		NumberSequenceKeypoint.new(0.45, 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.7, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = burstPart
	emitter:Emit(lowQuality() and 5 or 10)
	Debris:AddItem(burstPart, 0.6)

	-- Subtle crumbs: a few flecks of cucumber shed from the body and fall to the
	-- ground on every hit. Emitted across the body's volume and pulled down by
	-- gravity so they read as little bits of debris, not another outward spark.
	local crumbPart = Instance.new("Part")
	crumbPart.Name = "LocalHitCrumbs"
	crumbPart.Anchored = true
	crumbPart.CanCollide = false
	crumbPart.CanQuery = false
	crumbPart.Transparency = 1
	crumbPart.Size = part.Size * 0.8 -- spawn across the (already-shrunk) body
	crumbPart.CFrame = part.CFrame
	crumbPart.Parent = workspace
	local crumbs = Instance.new("ParticleEmitter")
	-- Push the cucumber's own hue up to full brightness WITHOUT adding a white floor,
	-- so the flecks stay a saturated green instead of blowing out to white.
	local crumbBase = part.Color
	local peak = math.max(crumbBase.R, crumbBase.G, crumbBase.B, 0.08)
	local crumbPop = Color3.new(crumbBase.R / peak, crumbBase.G / peak, crumbBase.B / peak)
	crumbs.Color = ColorSequence.new(crumbPop, crumbBase) -- vivid green core -> base tone as it falls
	crumbs.LightEmission = 0.1 -- was 0.45; the additive glow was washing the green out to white
	crumbs.Lifetime = NumberRange.new(0.6, 1)
	crumbs.Speed = NumberRange.new(9, 16) -- burst outward off the body...
	crumbs.SpreadAngle = Vector2.new(360, 360) -- ...in every direction; Acceleration then pulls them to the ground
	crumbs.Acceleration = Vector3.new(0, -70, 0) -- fall like little bits of debris
	crumbs.Drag = 0.5
	crumbs.Rotation = NumberRange.new(0, 360)
	crumbs.RotSpeed = NumberRange.new(-180, 180)
	crumbs.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.32),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	crumbs.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.75, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	crumbs.Parent = crumbPart
	crumbs:Emit(lowQuality() and 4 or 8)
	Debris:AddItem(crumbPart, 1) -- outlive the crumbs' fall so they don't pop out mid-air

	-- Hit-stop (SFX pass 2026-08-26): hold one beat at rest scale before the
	-- pop tween so the impact "bites" instead of instantly rubber-banding.
	task.wait(0.04)
	if HitSerial[part] ~= serial or not part.Parent then return end

	-- Pop outward, snap small, then spring back. New clicks cancel/restart this locally.
	local pop = TweenService:Create(part, TweenInfo.new(0.055, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = base.Size * 1.16;
	})
	HitTweens[part] = pop
	pop:Play()
	pop.Completed:Wait()
	if HitSerial[part] ~= serial or not part.Parent then return end

	local shrink = TweenService:Create(part, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = base.Size * 0.72;
	})
	HitTweens[part] = shrink
	shrink:Play()
	shrink.Completed:Wait()
	if HitSerial[part] ~= serial or not part.Parent then return end

	local restore = TweenService:Create(part, TweenInfo.new(0.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Size = base.Size;
	})
	HitTweens[part] = restore
	restore:Play()
	restore.Completed:Wait()
	if HitSerial[part] == serial then HitTweens[part] = nil end
end

----------------------------------------------------------------------
-- Damage numbers (pop in, drift up, fade)
----------------------------------------------------------------------
local function damageNumber(part, amount, golden, isMine, crit, pickaxe, hitPos)
	local bb = UITemplates.DamageNumber:Clone()
	bb.Enabled = true -- template ships disabled so it never renders in Studio
	bb.Size = UDim2.new(0, (crit or pickaxe) and 170 or (isMine and 110 or 70), 0, (crit or pickaxe) and 64 or (isMine and 44 or 28))
	if hitPos then
		--.. spawn right where the click ray struck the cucumber, then drift up
		bb.StudsOffsetWorldSpace = (hitPos - part.Position)
			+ Vector3.new(rng:NextNumber(-0.25, 0.25), 0.2, rng:NextNumber(-0.25, 0.25))
	else
		--.. pet/automatic hits have no click point; float above the cucumber
		bb.StudsOffsetWorldSpace = Vector3.new(rng:NextNumber(-1.1, 1.1), part.Size.Y / 2 + 0.3, rng:NextNumber(-0.8, 0.8))
	end

	local label = bb.Label
	label.Size = UDim2.new(0, 0, 0, 0) -- pops in
	label.Text = crit and ("CRIT! " .. amount) or (pickaxe and ("\u{26A1} " .. amount) or amount)
	label.TextColor3 = crit and Color3.fromRGB(255, 150, 20)
		or (pickaxe and Color3.fromRGB(255, 255, 255))
		or (golden and Color3.fromRGB(255, 213, 0) or (isMine and Color3.fromRGB(180, 255, 120) or Color3.fromRGB(255, 255, 255)))
	label.Rotation = rng:NextNumber(-10, 10)
	local stroke = label.UIStroke
	stroke.Thickness = (crit or pickaxe) and 4 or 3
	stroke.Color = crit and Color3.fromRGB(90, 30, 0) or (pickaxe and Color3.fromRGB(60, 20, 100)) or Color3.fromRGB(20, 60, 15)
	bb.Parent = part

	--.. pop in
	TweenService:Create(label, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 1, 0);
	}):Play()
	--.. drift up + fade
	TweenService:Create(bb, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(rng:NextNumber(-1, 1), 4, 0);
	}):Play()
	task.delay(0.35, function()
		TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1;
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.35), {Transparency = 1}):Play()
	end)
	Debris:AddItem(bb, 0.85)
end

----------------------------------------------------------------------
-- Combo popup: crit-style "Nx COMBO" on weak-point (white dot) hits
----------------------------------------------------------------------
local function comboNumber(part, combo, hitPos, milestone)
	--.. Always detach combo UI from the cucumber. On a one-shot, removal can
	--.. replicate either before or just after this callback; this local anchor
	--.. survives both orderings for the popup's complete animation.
	local popupAnchor = Instance.new("Part")
	popupAnchor.Name = "ComboPopupAnchor"
	popupAnchor.Anchored = true
	popupAnchor.CanCollide = false
	popupAnchor.CanQuery = false
	popupAnchor.CanTouch = false
	popupAnchor.CastShadow = false
	popupAnchor.Transparency = 1
	popupAnchor.Size = part.Size
	popupAnchor.Position = part.Position
	popupAnchor.Parent = workspace
	Debris:AddItem(popupAnchor, 1.05)

	local bb = UITemplates.ComboPopup:Clone()
	bb.Enabled = true -- template ships disabled so it never renders in Studio
	if milestone then
		--.. milestone popups (5/10/25) land half again bigger
		bb.Size = UDim2.new(bb.Size.X.Scale * 1.5, bb.Size.X.Offset * 1.5, bb.Size.Y.Scale * 1.5, bb.Size.Y.Offset * 1.5)
	end
	if hitPos then
		--.. sit just above the struck point so it doesn't cover the damage number
		bb.StudsOffsetWorldSpace = (hitPos - part.Position)
			+ Vector3.new(rng:NextNumber(-0.3, 0.3), 1.2, rng:NextNumber(-0.3, 0.3))
	else
		bb.StudsOffsetWorldSpace = Vector3.new(rng:NextNumber(-0.8, 0.8), part.Size.Y / 2 + 1.8, rng:NextNumber(-0.6, 0.6))
	end

	local label = bb.Label
	label.Size = UDim2.new(0, 0, 0, 0) -- pops in
	label.Text = combo .. "x COMBO"
	--.. warms from orange toward red as the streak climbs
	label.TextColor3 = Color3.fromRGB(255, math.clamp(190 - (combo - 1) * 18, 40, 190), 30)
	label.Rotation = rng:NextNumber(-8, 8)
	local stroke = label.UIStroke
	bb.Parent = popupAnchor

	TweenService:Create(label, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 1, 0);
	}):Play()
	TweenService:Create(bb, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 4.5, 0);
	}):Play()
	task.delay(0.4, function()
		TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.4), {Transparency = 1}):Play()
	end)
	Debris:AddItem(bb, 0.95)
end

----------------------------------------------------------------------
-- Character swing on click
----------------------------------------------------------------------
--.. Pickaxe swing, taken from the Place1 tool (StarterPack.Pickaxe.Animations). That tool
--.. ships a matched R6/R15 pair and picks between them off the live Humanoid.RigType, so
--.. both avatar types swing properly -- the previous single R15-only slash (522635514)
--.. had nothing to play on an R6 character.
local SWING_ANIM = {
	[Enum.HumanoidRigType.R6] = "rbxassetid://704172536",
	[Enum.HumanoidRigType.R15] = "rbxassetid://18176218561", --.. Bone Scythe chop (ChopR15)
}

local swingTrack
local function clearSwing()
	if not swingTrack then return end
	if swingTrack.IsPlaying then swingTrack:Stop(0) end
	swingTrack:Destroy()
	swingTrack = nil
end

local function loadSwing()
	clearSwing()
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	local anim = Instance.new("Animation")
	anim.AnimationId = SWING_ANIM[humanoid.RigType] or SWING_ANIM[Enum.HumanoidRigType.R15]
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	anim:Destroy()
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		swingTrack = track
	end
end
player.CharacterAdded:Connect(function()
	task.wait(1)
	loadSwing()
end)
player.CharacterRemoving:Connect(clearSwing)
task.spawn(function()
	task.wait(2)
	if not swingTrack then loadSwing() end
end)

--.. Free swing: the scythe animation + swoosh are pure feel, so they fire on any
--.. click, in range or not. Damage is still gated by reach/cooldown further down.
--.. One shared entry point with a short debounce so a click that also lands a
--.. confirmed hit does not play the swoosh twice.
local CLICK_COOLDOWN --.. the pickaxe's hit debounce, assigned further down; the swing fx shares it
-- Preserve the original asset/settings, but use the swoosh only for a real
-- miss-swing. Confirmed cucumber hits have their own impact audio.
local PICKAXE_MISS_SWING_SOUND_ENABLED = true
local lastSwingFx = 0

local function eggHatching()
	local playerGui = player:FindFirstChild("PlayerGui")
	local eggUi = playerGui and playerGui:FindFirstChild("EggUi")
	local billboard = eggUi and eggUi:FindFirstChild("BillboardGui")
	return billboard and billboard:GetAttribute("Hatching") == true
end

local function playMissSwingSound(volume)
	if not PICKAXE_MISS_SWING_SOUND_ENABLED or eggHatching() then return end
	playSound("Scythe Swing", 0.08, volume or 0.7)
end

local function doSwing(fade, speed)
	local now = os.clock()
	if now - lastSwingFx < (CLICK_COOLDOWN or 0.35) then return false end
	lastSwingFx = now
	if swingTrack then
		swingTrack:Stop(0)
		swingTrack:Play(fade or 0.1, 1, speed or 1.5)
	end
	return true
end

----------------------------------------------------------------------
-- Pet attack bolts
----------------------------------------------------------------------
local function petBolts(targetPart, golden)
	local char = player.Character
	local petsFolder = char and char:FindFirstChild("Pets")
	if not petsFolder then return end

	local count = 0
	for _,pet in ipairs(petsFolder:GetChildren()) do
		if count >= 4 then break end
		if pet:IsA("Model") then
			count += 1
			local origin = pet:GetPivot().Position
			local bolt = Instance.new("Part")
			bolt.Shape = Enum.PartType.Ball
			bolt.Size = Vector3.new(0.4, 0.4, 0.4)
			bolt.Material = Enum.Material.Neon
			bolt.Color = golden and Color3.fromRGB(255, 226, 120) or Color3.fromRGB(225, 255, 200)
			bolt.Anchored = true
			bolt.CanCollide = false
			bolt.CanQuery = false
			bolt.CFrame = CFrame.new(origin)

			--.. soft ribbon trail instead of a fat neon ball
			local a0 = Instance.new("Attachment") a0.Position = Vector3.new(0, 0.15, 0) a0.Parent = bolt
			local a1 = Instance.new("Attachment") a1.Position = Vector3.new(0, -0.15, 0) a1.Parent = bolt
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(golden and Color3.fromRGB(255, 213, 0) or Color3.fromRGB(120, 220, 90))
			trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
			trail.Lifetime = 0.18
			trail.LightEmission = 0.6
			trail.WidthScale = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2)})
			trail.Parent = bolt

			bolt.Parent = workspace

			local flight = TweenService:Create(bolt, TweenInfo.new(0.18 + rng:NextNumber(0, 0.08), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(targetPart.Position);
				Size = Vector3.new(0.2, 0.2, 0.2);
			})
			flight:Play()
			flight.Completed:Once(function() bolt:Destroy() end)
			Debris:AddItem(bolt, 0.5)
		end
	end
end

----------------------------------------------------------------------
-- Camera kick — unified through the shipped (previously unused)
-- CameraShaker module. Its RenderStep callback composes the shake ON TOP
-- of whatever the camera scripts wrote this frame, replacing the two old
-- raw per-frame CFrame jitter loops. Same cameraKick signature as before.
----------------------------------------------------------------------
local CameraShakerModule = require(ReplicatedStorage.Modules.ControllerLoader.Imported.CameraShaker)
local camShake = CameraShakerModule.new(Enum.RenderPriority.Camera.Value + 1, function(shakeCFrame)
	local cam = workspace.CurrentCamera
	if cam then cam.CFrame = cam.CFrame * shakeCFrame end
end)
camShake:Start()

local function cameraKick(strength, duration)
	--.. `strength` used to be studs of raw per-frame offset; map it onto the
	--.. shaker's magnitude (default PositionInfluence 0.15 ~= x7 to match)
	if not duration then
		--.. quick blip (cucumber break burst): sharp in, fast decay
		camShake:ShakeOnce(strength * 7, 16, 0, 0.22)
	else
		--.. sustained rumble that eases out over `duration` seconds
		camShake:ShakeOnce(strength * 5, 9, 0.02, duration)
	end
end

----------------------------------------------------------------------
-- Break explosion
----------------------------------------------------------------------
local ActiveExplosions = 0
local MAX_ACTIVE_EXPLOSIONS = 6 -- existing visual cap; pooling does not change what players see
local ChunkPool = {}
local BurstPools = {}
local PetBurstPool = {}

local function returnToPoolLater(instance, pool, lifetime, reset, maxCached)
	task.delay(lifetime, function()
		if not instance then return end
		if reset then reset(instance) end
		instance.Parent = nil
		if not maxCached or #pool < maxCached then
			table.insert(pool, instance)
		else
			instance:Destroy()
		end
	end)
end

local function scaledParticleSequence(sequence, scale)
	local keypoints = {}
	for _, keypoint in ipairs(sequence.Keypoints) do
		keypoints[#keypoints + 1] = NumberSequenceKeypoint.new(
			keypoint.Time,
			keypoint.Value * scale,
			keypoint.Envelope * scale
		)
	end
	return NumberSequence.new(keypoints)
end

local function createChunk()
	local chunk = Instance.new("Part")
	chunk.Name = "CucumberBreakChunk"
	chunk.Anchored = true
	chunk.CanCollide = false
	chunk.CanTouch = false
	chunk.CanQuery = false
	chunk.CastShadow = false
	return chunk
end

-- Port of pet sim 99's layered burst, reskinned with the HUD cucumber icon.
-- Build the emitter hierarchy once, then recolor/reposition/re-emit it on reuse.
local function createPetBurstHost()
	local explodeFolder = Particles:FindFirstChild("Cucumber Explode")
	local showerTemplate = Particles:FindFirstChild("Cucumber Particle")
	if not explodeFolder or not showerTemplate then return nil end

	local host = Instance.new("Part")
	host.Name = "PetSimDestroyVFX"
	host.Size = Vector3.one
	host.Anchored = true
	host.CanCollide = false
	host.CanTouch = false
	host.CanQuery = false
	host.CastShadow = false
	host.Transparency = 1

	local attachment = Instance.new("Attachment")
	attachment.Name = "BurstAttachment"
	attachment.Parent = host
	for _, template in ipairs(explodeFolder:GetChildren()) do
		if template:IsA("ParticleEmitter") then
			local emitter = template:Clone()
			emitter.Enabled = false
			emitter.Parent = attachment
		end
	end

	local shower = showerTemplate:Clone()
	shower.Name = "Cucumber Particle"
	shower.Enabled = false
	shower.Parent = attachment

	local petDamageTemplate = Particles:FindFirstChild("Pet Damage")
	if petDamageTemplate then
		for _ = 1, 3 do
			local impactAttachment = Instance.new("Attachment")
			impactAttachment.Name = "ImpactAttachment"
			impactAttachment.Parent = host
			local impact = petDamageTemplate:Clone()
			impact.Enabled = false
			impact.Parent = impactAttachment
		end
	end
	return host
end

local function petSimDestroyBurst(position, color, golden, sizeMag)
	local explodeFolder = Particles:FindFirstChild("Cucumber Explode")
	local showerTemplate = Particles:FindFirstChild("Cucumber Particle")
	if not explodeFolder or not showerTemplate then return end

	local host = table.remove(PetBurstPool) or createPetBurstHost()
	if not host then return end
	host.CFrame = CFrame.new(position)
	host.Parent = workspace

	local attachment = host:FindFirstChild("BurstAttachment")
	local scale = math.max(((sizeMag or 5) / 20) ^ 0.9, 1)
	local tint = golden and Color3.fromRGB(255, 220, 75) or (color or Color3.fromRGB(90, 210, 70))
	if attachment then
		for _, emitter in ipairs(attachment:GetChildren()) do
			if emitter:IsA("ParticleEmitter") then
				if emitter.Name == "Cucumber Particle" then
					emitter.Size = scaledParticleSequence(showerTemplate.Size, scale)
					emitter.Color = ColorSequence.new(tint, Color3.new(1, 1, 1))
					emitter:Emit(rng:NextInteger(10, 25))
					emitter.Rate = 120
					emitter.Enabled = true
					task.delay(rng:NextInteger(25, 40) / 120, function()
						if emitter.Parent then emitter.Enabled = false end
					end)
				else
					local template = explodeFolder:FindFirstChild(emitter.Name)
					if template and template:IsA("ParticleEmitter") then
						emitter.Size = scaledParticleSequence(template.Size, scale)
					end
					emitter.Color = ColorSequence.new(tint, Color3.new(1, 1, 1))
					emitter.Enabled = false
					emitter:Emit(emitter.Name == "Sparkles" and 15 or 2)
				end
			end
		end
	end

	local radius = math.max(1, (sizeMag or 5) * 0.18)
	for _, impactAttachment in ipairs(host:GetChildren()) do
		if impactAttachment:IsA("Attachment") and impactAttachment.Name == "ImpactAttachment" then
			impactAttachment.Position = Vector3.new(
				rng:NextNumber(-radius, radius),
				rng:NextNumber(-radius * 0.5, radius),
				rng:NextNumber(-radius, radius)
			)
			local impact = impactAttachment:FindFirstChildOfClass("ParticleEmitter")
			if impact then
				impact.Color = ColorSequence.new(tint, Color3.new(1, 1, 1))
				impact.ZOffset = radius
				impact.Enabled = false
				impact:Emit(1)
			end
		end
	end

	returnToPoolLater(host, PetBurstPool, 5, function(pooledHost)
		for _, descendant in ipairs(pooledHost:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then descendant.Enabled = false end
		end
	end, MAX_ACTIVE_EXPLOSIONS)
end

local function chunkExplosion(position, color, golden, sizeMag)
	-- Preserve the exact seven-chunk look, but reuse prebuilt parts instead of
	-- allocating and destroying seven Instances on every break.
	if not lowQuality() and ActiveExplosions < MAX_ACTIVE_EXPLOSIONS then
		ActiveExplosions += 1
		task.delay(0.8, function() ActiveExplosions -= 1 end)
		for _ = 1, 7 do
			local chunk = table.remove(ChunkPool) or createChunk()
			chunk.Size = Vector3.new(rng:NextNumber(0.4, 0.9), rng:NextNumber(0.4, 0.9), rng:NextNumber(0.6, 1.4))
			chunk.Transparency = 0
			chunk.Color = color or Color3.fromRGB(80, 170, 60)
			chunk.Material = golden and Enum.Material.Foil or Enum.Material.SmoothPlastic
			chunk.CFrame = CFrame.new(position) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			chunk.Parent = workspace
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.8, 1.6), rng:NextNumber(-1, 1))
			local goalPos = position + (dir.Magnitude > 0 and dir.Unit or Vector3.yAxis) * rng:NextNumber(5, 10)
			local goalCF = CFrame.new(goalPos) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			TweenService:Create(chunk, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1;
				Size = chunk.Size * 0.3;
				CFrame = goalCF;
			}):Play()
			returnToPoolLater(chunk, ChunkPool, 0.8, nil, MAX_ACTIVE_EXPLOSIONS * 7)
		end
	end

	local template = Particles:FindFirstChild(golden and "Golden" or "Burst") or Particles:FindFirstChild("Burst")
	if template then
		local poolKey = template.Name
		local pool = BurstPools[poolKey]
		if not pool then
			pool = {}
			BurstPools[poolKey] = pool
		end
		local burst = table.remove(pool) or template:Clone()
		burst.Anchored = true
		burst.CanCollide = false
		burst.CanTouch = false
		burst.Transparency = 1
		burst.CFrame = CFrame.new(position)
		burst.Parent = workspace
		for _, descendant in ipairs(burst:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				descendant:Emit(math.clamp(math.floor((sizeMag or 5) * 3), 15, 60))
			end
		end
		returnToPoolLater(burst, pool, 2, nil, MAX_ACTIVE_EXPLOSIONS)
	end

	-- Move secondary setup out of the network callback while retaining the same frame-visible effect.
	task.defer(petSimDestroyBurst, position, color, golden, sizeMag)
end

-- Prewarm the maximum existing visual concurrency during loading so the first
-- cucumber break does not pay the construction cost.
if not lowQuality() then
	for _ = 1, MAX_ACTIVE_EXPLOSIONS * 7 do
		table.insert(ChunkPool, createChunk())
	end
end
for _, templateName in ipairs({"Burst", "Golden"}) do
	local template = Particles:FindFirstChild(templateName)
	if template then
		BurstPools[templateName] = BurstPools[templateName] or {}
		for _ = 1, MAX_ACTIVE_EXPLOSIONS do
			table.insert(BurstPools[templateName], template:Clone())
		end
	end
end
for _ = 1, MAX_ACTIVE_EXPLOSIONS do
	local host = createPetBurstHost()
	if host then table.insert(PetBurstPool, host) end
end

----------------------------------------------------------------------
-- Server events
----------------------------------------------------------------------
----------------------------------------------------------------------
-- Committed-target ring: clicking doesn't damage anymore — it drops this
-- white circle around the target and your pets break it automatically
----------------------------------------------------------------------
local ring = Instance.new("Part")
ring.Name = "CommitRing"
ring.Shape = Enum.PartType.Cylinder
ring.Material = Enum.Material.Neon
ring.Color = Color3.fromRGB(255, 255, 255)
ring.Transparency = 1
ring.Anchored = true
ring.CanCollide = false
ring.CanQuery = false
ring.Size = Vector3.new(0.25, 8, 8)
ring.Parent = workspace

local ringTarget = nil
local ringPulse = nil

----------------------------------------------------------------------
-- Pickaxe strike: the whole cucumber is the hit target — click anywhere on
-- its body to swing. (The old white strike-point dot is gone.)
----------------------------------------------------------------------
CLICK_COOLDOWN = 0.35
local nextCucumberClick = 0

local activeCooldownPoint

local function showClickCooldown(surfacePart, worldPosition, worldNormal, duration)
	if not surfacePart or not surfacePart:IsA("BasePart") then return end
	duration = math.clamp(duration or 0, 0, CLICK_COOLDOWN)
	if duration <= 0 then return end

	-- Spam clicks update one timer at the newest click position instead of
	-- covering the cucumber in stacked countdown labels.
	if activeCooldownPoint and activeCooldownPoint.Parent then
		activeCooldownPoint:Destroy()
	end

	local point = Instance.new("Attachment")
	point.Name = "ClickCooldownPoint"
	point.Position = surfacePart.CFrame:PointToObjectSpace(worldPosition + worldNormal * 0.3)
	point.Parent = surfacePart
	activeCooldownPoint = point

	local billboard = UITemplates.ClickCooldown:Clone()
	billboard.Enabled = true -- template ships disabled so it never renders in Studio
	billboard.Adornee = point
	billboard.Parent = point

	local text = billboard.Countdown
	text.Text = string.format("%.2fs", duration)

	task.spawn(function()
		local finishAt = os.clock() + duration
		while point.Parent do
			local remaining = math.max(0, finishAt - os.clock())
			text.Text = string.format("%.2fs", remaining)
			if remaining <= 0.07 then
				local fade = 1 - remaining / 0.07
				text.TextTransparency = fade
				text.TextStrokeTransparency = fade
			end
			if remaining <= 0 then break end
			RunService.RenderStepped:Wait()
		end
		if point.Parent then point:Destroy() end
		if activeCooldownPoint == point then activeCooldownPoint = nil end
	end)
end

local function clearRing()
	ringTarget = nil
	if ringPulse then ringPulse:Cancel() ringPulse = nil end
	ring.Transparency = 1
	committedTarget = nil
end

local function markTarget(part, golden)
	if ringTarget == part then return end
	ringTarget = part
	if isMobileBossPart(part) then
		--.. no commit circle on a walking boss (see isMobileBossPart) — just hide it
		if ringPulse then ringPulse:Cancel() ringPulse = nil end
		ring.Transparency = 1
		return
	end
	local d = math.max(part.Size.X, part.Size.Z) * 0.775 -- half the old 1.55 -> circle is 2x smaller
	ring.Size = Vector3.new(0.25, d, d)
	ring.Color = golden and Color3.fromRGB(255, 230, 140) or Color3.fromRGB(160, 255, 140) -- committed = green pulse; hover = white circle
	ring.CFrame = CFrame.new(part.Position.X, part.Position.Y - part.Size.Y / 2 + 0.12, part.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.25
	if ringPulse then ringPulse:Cancel() end
	ringPulse = TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transparency = 0.6;
		Size = Vector3.new(0.25, d * 1.1, d * 1.1);
	})
	ringPulse:Play()
end

task.spawn(function()
	while true do
		task.wait(0.4)
		if ringTarget and not ringTarget.Parent then
			clearRing()
		end
	end
end)

----------------------------------------------------------------------
-- No click cooldown UI: every valid cucumber click can land immediately.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Click-to-hit: every click/tap anywhere on a cucumber fires a pickaxe
-- strike and answers NOW with local feedback (squash + soft click).
-- Damage numbers/sounds stay server-confirmed below.
----------------------------------------------------------------------
breakablesRoot = workspace:WaitForChild("Breakables", 10) -- assigns the forward-declared local (hover loop shares it)
local lastClickFeel = 0

function breakableRootOf(inst) -- assigns the forward-declared local (hover loop shares it)
	--.. climb to whatever sits directly in a zone folder (part, or model for trees/bosses)
	local node = inst
	while node and node ~= workspace do
		local parent = node.Parent
		if parent and parent.Parent == breakablesRoot then
			if node:IsA("BasePart") then return node end
			if node:IsA("Model") then return node.PrimaryPart end
			return nil
		end
		node = parent
	end
	return nil
end

local lastPickaxeHit -- {part, pos, t}: where the latest accepted pickaxe strike landed

----------------------------------------------------------------------
-- Swing-contact detection: click-anywhere hits land where the blade lands
----------------------------------------------------------------------
--.. Click-anywhere strikes follow the real pickaxe through its animated arc.
--.. Each frame sweeps every pickaxe part from its previous position to its
--.. current position, closing the gaps between frames and automatically matching
--.. normal and Super Strength character/tool scale. The server still owns reach,
--.. cooldown, and damage validation.
local SWING_CONTACT_WINDOW = 0.45
local SWING_CONTACT_LEAD = 0.1
local SWING_CONTACT_PADDING = 0.9 -- forgiveness around the visible pickaxe geometry
local swingContactToken = 0

local function cancelSwingContact()
	swingContactToken += 1
end

local function equippedPickaxeParts()
	local character = player.Character
	if not character then return nil end
	for _, tool in ipairs(character:GetChildren()) do
		--.. same marker DesertPortalService keys off: the Tool root holds IsPickaxe
		if tool:IsA("Tool") and tool:FindFirstChild("IsPickaxe") then
			local parts = {}
			for _, desc in ipairs(tool:GetDescendants()) do
				if desc:IsA("BasePart") then parts[#parts + 1] = desc end
			end
			if #parts > 0 then return parts end
		end
	end
	return nil
end

--.. thin tapered swing trail on the pickaxe head, flashed on for a beat per
--.. landing swing. Built lazily on the currently equipped tool (equips swap
--.. tools in and out, so setup-time wiring would miss re-equips).
local pickaxeTrail
local function ensurePickaxeTrail()
	local char = player.Character
	if pickaxeTrail and pickaxeTrail.Parent and char and pickaxeTrail:IsDescendantOf(char) then
		return pickaxeTrail
	end
	pickaxeTrail = nil
	local parts = equippedPickaxeParts()
	if not parts then return nil end
	--.. "head" = the biggest piece of the tool
	local head
	for _, p in ipairs(parts) do
		if not head or p.Size.Magnitude > head.Size.Magnitude then head = p end
	end
	if not head then return nil end
	local existing = head:FindFirstChild("SwingTrail")
	if existing then
		pickaxeTrail = existing
		return existing
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "SwingTrailA0"
	a0.Position = Vector3.new(0, head.Size.Y * 0.5, 0)
	a0.Parent = head
	local a1 = Instance.new("Attachment")
	a1.Name = "SwingTrailA1"
	a1.Position = Vector3.new(0, -head.Size.Y * 0.5, 0)
	a1.Parent = head
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.12
	trail.Color = ColorSequence.new(Color3.fromRGB(235, 240, 235), Color3.fromRGB(170, 200, 180)) -- steel-over-leaf, tool-ish
	trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1)})
	trail.WidthScale = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15)}) -- tapered
	trail.LightEmission = 0.3
	trail.Enabled = false
	trail.Parent = head
	pickaxeTrail = trail
	return trail
end

local trailFlashToken = 0
local function flashPickaxeTrail()
	local trail = ensurePickaxeTrail()
	if not trail then return end
	trailFlashToken += 1
	local my = trailFlashToken
	trail.Enabled = true
	task.delay(0.15, function()
		if trailFlashToken == my and trail.Parent then trail.Enabled = false end
	end)
end

--.. instant connect feel shared by all three click-accept paths: wet crunch ON
--.. the struck cucumber (3D via the upgraded playSound), a quiet 2D click
--.. underlay, the blade's air-slice + trail flash (this swing WILL contact),
--.. and a light controller rumble. Fires on input accept, before the server
--.. confirms — that instant answer is the whole point.
local function clickConnectFeel(struckPart)
	playSound("Wet Crunch", 0.12, nil, struckPart)
	playSound("Click Sound", 0.1, 0.2)
	playSound("Air Slice", 0.1, 0.35)
	flashPickaxeTrail()
	HapticUtil.Pulse(0.4, 0.08)
end

--.. returns false when no pickaxe Tool is equipped so the caller can keep the
--.. instant whiff. A contact made during cooldown is remembered and accepted
--.. later in this same swing as soon as the cooldown opens.
local function watchSwingContact(onWhiff)
	local bladeParts = equippedPickaxeParts()
	if not bladeParts or not breakablesRoot then return false end
	cancelSwingContact()
	local token = swingContactToken
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Include
	op.FilterDescendantsInstances = { breakablesRoot }

	task.spawn(function()
		local started = os.clock()
		local deadline = started + SWING_CONTACT_WINDOW
		local previousPositions = {}
		local pendingBest, pendingPosition
		local sawContact = false
		for _, part in ipairs(bladeParts) do
			if part.Parent then previousPositions[part] = part.Position end
		end

		while os.clock() < deadline do
			if token ~= swingContactToken then return end -- a newer click took over
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local scale = math.max(1, character:GetScale())
			local padding = SWING_CONTACT_PADDING * scale
			local best, bestDot, bestPosition
			local seenRoots = {}

			for _, part in ipairs(bladeParts) do
				if part.Parent and part:IsDescendantOf(character) then
					local current = part.Position
					local previous = previousPositions[part] or current
					previousPositions[part] = current
					if os.clock() - started >= SWING_CONTACT_LEAD then
						local delta = current - previous
						local distance = delta.Magnitude
						local sweepCFrame, sweepSize
						if distance > 0.02 then
							local midpoint = previous:Lerp(current, 0.5)
							local radius = math.clamp(part.Size.Magnitude * 0.3, 0.65, 2.25) + padding
							sweepCFrame = CFrame.lookAt(midpoint, midpoint + delta)
							sweepSize = Vector3.new(radius * 2, radius * 2, distance + radius * 2)
						else
							sweepCFrame = part.CFrame
							sweepSize = part.Size + Vector3.new(padding * 2, padding * 2, padding * 2)
						end

						for _, touched in ipairs(workspace:GetPartBoundsInBox(sweepCFrame, sweepSize, op)) do
							local troot = breakableRootOf(touched)
							if troot and not seenRoots[troot]
								and (hrp.Position - troot.Position).Magnitude <= myReach(troot) then
								seenRoots[troot] = true
								local to = troot.Position - hrp.Position
								local dot = to.Magnitude > 0.001 and hrp.CFrame.LookVector:Dot(to.Unit) or 1
								if not bestDot or dot > bestDot then
									best, bestDot, bestPosition = troot, dot, current
								end
							end
						end
					end
				end
			end

			if best then
				sawContact = true
				pendingBest, pendingPosition = best, bestPosition
			end

			local now = os.clock()
			if pendingBest and pendingBest.Parent and now >= nextCucumberClick
				and (hrp.Position - pendingBest.Position).Magnitude <= myReach(pendingBest) then
				nextCucumberClick = now + CLICK_COOLDOWN
				lastPickaxeHit = {part = pendingBest, pos = pendingPosition or pendingBest.Position, t = now}
				Network:FireServer("PickaxeStrike", pendingBest, true)
				task.spawn(punch, pendingBest)
				lastClickFeel = now
				clickConnectFeel(pendingBest)
				return
			end
			RunService.Heartbeat:Wait()
		end

		--.. Only a true no-contact swing gets the whiff sound. Cooldown-blocked
		--.. physical contact stays quiet instead of pretending the blade missed.
		if token == swingContactToken and not sawContact and onWhiff then onWhiff() end
	end)
	return true
end

--.. HUD buttons that sit over the Roblox touch controls are deliberately
--.. Active=false (see HUD.TopStatusLayout) so movement/camera drags pass
--.. straight through them. A side effect is that `processed` is FALSE for a tap
--.. that lands squarely on one, so the gameProcessed guard alone would let every
--.. bottom-bar tap also swing the pickaxe. Test the hit-stack directly instead.
local function isOverGuiButton(position)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return false end
	local ok, objects = pcall(playerGui.GetGuiObjectsAtPosition, playerGui, position.X, position.Y)
	if not ok then return false end
	for _, object in ipairs(objects) do
		if object:IsA("GuiButton") then return true end
	end
	return false
end

--.. LOCKED-BIOME TARGET FILTER (2026-08-27): clicks and auto-aim never pick
--.. cucumbers in a biome the player hasn't unlocked. The server enforces the
--.. same rule in PickaxeStrike/OnClicked -- this filter is for honest feel
--.. (no swing/crunch on a hit the server will refuse).
local function ownedZoneHaystack()
	local pd = player:FindFirstChild("PlayerData")
	local doors = pd and pd:FindFirstChild("Doors")
	local owned = doors and doors:FindFirstChild("OwnedString")
	return " # " .. ((owned and owned.Value) or "Spawn") .. " # "
end
local function zoneUnlocked(part, hay)
	local node = part
	while node and node.Parent do
		if node.Parent == breakablesRoot then
			if node.Name == "Spawn" then return true end
			return (hay or ownedZoneHaystack()):find(" # " .. node.Name .. " # ", 1, true) ~= nil
		end
		node = node.Parent
	end
	return true -- not under a zone folder (boss props): the server decides
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	--.. mid-cutscene clicks must not swing or strike: the intro hides every
	--.. breakable, so a hit here would smash invisible cucumbers offscreen
	if player:GetAttribute("IntroCutsceneActive") == true then return end
	--.. clicks inside the CUCUMBER BANK never swing or strike (2026-08-27,
	--.. user): the vault is a no-mining zone -- VaultPickaxeGuard parks the
	--.. pickaxe there, and an empty-handed swing next to the upgrade pills
	--.. reads as a bug. Deck slab re-resolved per click (bank regenerates);
	--.. same footprint + margins as the server guard.
	--.. ...UNLESS a heist involves this player (StealCombat attribute, set by
	--.. VaultService on thief and victim): then the deck is a battleground and
	--.. swings must go through so the pair can pickaxe each other.
	do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local bank = workspace:FindFirstChild("CucumberBank")
		local deck = bank and bank:FindFirstChild("Deck")
		local slab = deck and deck:FindFirstChild("DeckSlab")
		if hrp and slab and player:GetAttribute("StealCombat") == nil then
			local p, c, s = hrp.Position, slab.Position, slab.Size
			if math.abs(p.X - c.X) <= s.X / 2 + 4
				and math.abs(p.Z - c.Z) <= s.Z / 2 + 4
				and p.Y >= c.Y - 6 and p.Y <= c.Y + 90 then
				return
			end
		end
	end
	if isOverGuiButton(input.Position) then return end
	local swung = doSwing(0.1, 1.5) --.. animation always swings; audio is added only on a miss below
	local function playMiss()
		if swung then playMissSwingSound(0.7) end
	end
	--.. STEAL COMBAT (2026-08-27): while a heist involves this player, a click
	--.. that lands on the opponent's character fires a StealStrike instead of
	--.. a breakable hit (server re-validates pairing, range and cooldown).
	do
		local foeId = player:GetAttribute("StealCombat")
		local foe = foeId and game:GetService("Players"):GetPlayerByUserId(foeId)
		local foeChar = foe and foe.Character
		if foeChar then
			local foeRay = workspace.CurrentCamera:ScreenPointToRay(input.Position.X, input.Position.Y)
			local fp = RaycastParams.new()
			fp.FilterType = Enum.RaycastFilterType.Include
			fp.FilterDescendantsInstances = { foeChar }
			if workspace:Raycast(foeRay.Origin, foeRay.Direction * 1000, fp) then
				Network:FireServer("StealStrike")
				return
			end
		end
	end
	if not breakablesRoot then playMiss() return end
	--.. raycast from the actual click/tap position instead of mouse.Target:
	--.. exact on touch too, where the emulated mouse can lag the first tap.
	--.. (input.Position is inset-adjusted, so ScreenPointToRay is the match)
	--.. Include-filter on Breakables only: invisible utility parts (zone
	--.. markers, door regions) and your own character can never eat a click
	local cam = workspace.CurrentCamera
	local unitRay = cam:ScreenPointToRay(input.Position.X, input.Position.Y)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { breakablesRoot }
	local hit = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, rp)
	local target = hit and hit.Instance
	local root = (target and target:IsDescendantOf(breakablesRoot)) and breakableRootOf(target) or nil

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	--.. Click ANYWHERE on screen: when the aimed ray misses (or aims at a
	--.. breakable that's out of reach), the SWING becomes the weapon: whatever
	--.. breakable the pickaxe blade physically touches during this swing takes
	--.. the hit (see watchSwingContact above). The server still deals these
	--.. "indirect" hits flat base damage with NO combo -- combos stay the
	--.. reward for actually clicking the cucumber itself.
	--.. (Replaced the old cursor-dot auto-aim, 2026-08-14 user request.)
	if root and (hrp.Position - root.Position).Magnitude > myReach(root) then
		root = nil -- aimed at a breakable that's out of reach; swing contact below instead
	end
	if root and not zoneUnlocked(root) then
		root = nil -- locked biome: the auto-aim below picks an unlocked target instead
	end
	if not root then
		if eggHatching() then
			playMiss()
			return
		end
		--.. AUTO-AIM (2026-08-23, design call): clicking or tapping ANYWHERE now hits
		--.. the NEAREST cucumber in reach. No aiming at a bobbing target, no facing
		--.. requirement, no blade-contact physics -- the old swing-contact fallback
		--.. only hit what you faced and touched, which felt broken on mobile. The
		--.. server treats these as indirect strikes (flat base damage, NO combo), so
		--.. clicking the cucumber itself is still the skill reward.
		local nearest, nearestDist
		local hay = ownedZoneHaystack() -- resolved once per click, not per candidate
		for part in pairs(Base) do
			if part.Parent and zoneUnlocked(part, hay) then
				local d = (hrp.Position - part.Position).Magnitude
				if d <= myReach(part) and (not nearestDist or d < nearestDist) then
					nearest, nearestDist = part, d
				end
			end
		end
		if nearest then
			local now2 = os.clock()
			if now2 >= nextCucumberClick then
				nextCucumberClick = now2 + CLICK_COOLDOWN
				lastPickaxeHit = {part = nearest, pos = nearest.Position, t = now2}
				Network:FireServer("PickaxeStrike", nearest, true)
				task.spawn(punch, nearest)
				lastClickFeel = now2
				clickConnectFeel(nearest)
			end
		else
			playMiss() -- genuinely nothing in reach: honest whiff
		end
		return
	end

	--.. only DIRECT cucumber clicks reach here (click-anywhere returned above)
	local now = os.clock()
	if now < nextCucumberClick then
		-- Only rejected clicks show the red timer, using the real time left.
		playMiss()
		showClickCooldown(target, hit.Position, hit.Normal, nextCucumberClick - now)
		return
	end
	nextCucumberClick = now + CLICK_COOLDOWN
	cancelSwingContact() -- a landed direct hit retires any watcher from a previous swing

	-- remember exactly where this strike landed; the server's BreakableHit
	-- confirm spawns the damage/combo numbers at this spot (swing-contact
	-- hits pin theirs to the blade's contact point instead)
	lastPickaxeHit = {part = root, pos = hit.Position, t = now}

	-- Accepted clicks stay visually clean; the server owns the matching gate.
	Network:FireServer("PickaxeStrike", root, false)

	task.spawn(punch, root)
	lastClickFeel = now
	clickConnectFeel(root)
end)

local ActiveNumbers = 0 -- perf guard: a packed server fires a LOT of hits
local petHitCount = 0 -- pet-sourced hits play "Collect" at most 1-in-3 (every 10th re-accents)
local petStreakVolume = 0.5 -- decays toward 0.25 across a pet streak; any player click resets it
local feelComboCount = 0 -- client-side stand-in combo for click-anywhere hits (riser + milestone feel only)
local feelComboLast = 0

----------------------------------------------------------------------
-- Lightning strike (zone-local: the server only sends this event to players
-- standing in the struck biome, so a bolt in Desert is invisible from Snow)
----------------------------------------------------------------------
local function lightningBolt(pos, sizeMag)
	local folder = Instance.new("Folder")
	folder.Name = "LocalLightning"
	folder.Parent = workspace

	--.. jagged path from high above down to the cucumber; lateral jitter
	--.. tightens as it descends so the tip lands exactly on the target
	local top = pos + Vector3.new(rng:NextNumber(-10, 10), 85, rng:NextNumber(-10, 10))
	local points = {top}
	local SEGMENTS = 8
	for i = 1, SEGMENTS - 1 do
		local t = i / SEGMENTS
		local p = top:Lerp(pos, t)
		local sway = 7 * (1 - t)
		points[#points + 1] = p + Vector3.new(rng:NextNumber(-sway, sway), 0, rng:NextNumber(-sway, sway))
	end
	points[#points + 1] = pos

	local segs = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local seg = Instance.new("Part")
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.CastShadow = false
		seg.Material = Enum.Material.Neon
		seg.Color = Color3.fromRGB(255, 252, 200)
		seg.Size = Vector3.new(0.7, 0.7, (a - b).Magnitude + 0.5)
		seg.CFrame = CFrame.lookAt((a + b) * 0.5, b)
		seg.Parent = folder
		segs[#segs + 1] = seg
	end

	--.. impact flash + electric burst
	local impact = Instance.new("Part")
	impact.Anchored = true
	impact.CanCollide = false
	impact.CanQuery = false
	impact.Transparency = 1
	impact.Size = Vector3.new(1, 1, 1)
	impact.CFrame = CFrame.new(pos)
	impact.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 235, 255)
	light.Brightness = 6
	light.Range = 60
	light.Parent = impact
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 215, 255))
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Speed = NumberRange.new(12, 26)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 6
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Enabled = false
	emitter.Parent = impact
	local particleScale = lowGraphics and 1.5 or 3
	local particleMin = lowGraphics and 10 or 18
	local particleMax = lowGraphics and 28 or 50
	emitter:Emit(math.clamp(math.floor((sizeMag or 8) * particleScale), particleMin, particleMax))

	--.. thunder rides the impact part so it pans/attenuates in 3D. Played
	--.. manually (not playSound) because the shared pool stops sounds at 3s,
	--.. which would clip the rumble tail.
	local thunder = Sounds:FindFirstChild("Thunder")
	if thunder then
		local s = thunder:Clone()
		s.PlaybackSpeed = 1 + rng:NextNumber(-0.06, 0.06)
		s.Parent = impact
		s:Play()
	end

	--.. real lightning flickers on, half-off, then back hard. Hold that second
	--.. flash for 1.5s longer before the original 0.4s fade so the bolt is readable.
	TweenService:Create(light, TweenInfo.new(0.45), {Brightness = 0}):Play()
	task.delay(0.06, function()
		for _, seg in ipairs(segs) do
			if seg.Parent then seg.Transparency = 0.7 end
		end
	end)
	task.delay(0.12, function()
		for _, seg in ipairs(segs) do
			if seg.Parent then seg.Transparency = 0.1 end
		end
	end)
	task.delay(1.62, function()
		for _, seg in ipairs(segs) do
			if seg.Parent then
				TweenService:Create(seg, TweenInfo.new(0.4), {Transparency = 1}):Play()
			end
		end
	end)
	-- Preserve the full readable flash, then discard the eight neon geometry parts.
	-- Only the invisible impact holder remains for the thunder tail.
	task.delay(2.1, function()
		for _, seg in ipairs(segs) do
			if seg.Parent then seg:Destroy() end
		end
	end)
	Debris:AddItem(folder, 8) -- impact holder outlives the thunder tail

	--.. close strikes rattle the camera a little
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and (hrp.Position - pos).Magnitude < 130 then
		cameraKick(0.22)
	end
end

Network:BindEvents({
	BreakableHit = function(info)
		if not info or info.Attacker ~= player.Name then return end

		local reportedPart = info.Part
		local part = reportedPart
		local usedFeedbackAnchor = false
		if not part or not part.Parent then
			--.. A one-shot cucumber can replicate its removal before this reliable hit
			--.. packet is handled. Rebuild only a local invisible anchor from the
			--.. server snapshot so damage/combo feedback still gets its full lifetime.
			if typeof(info.Position) ~= "Vector3" then return end
			part = Instance.new("Part")
			part.Name = "InstantBreakFeedbackAnchor"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Transparency = 1
			part.Size = typeof(info.PartSize) == "Vector3" and info.PartSize or Vector3.one
			part.Position = info.Position
			part.Parent = workspace
			usedFeedbackAnchor = true
			Debris:AddItem(part, 1.1)
		end

		-- Hit feedback is confirmed by the server and remains entirely local to this attacker.
		--.. flat kick (2026-08-27, user): crits no longer kick harder -- the
		--.. celebration feel belongs to combo milestones ONLY; crits keep just
		--.. their "CRIT!" damage number below
		cameraKick(0.045)

		--.. your pickaxe strikes spawn their numbers at the exact struck point;
		--.. pet/automatic hits (no click ray) keep the above-the-cucumber spot
		local hitPos
		if info.Click and lastPickaxeHit and reportedPart and lastPickaxeHit.part == reportedPart and os.clock() - lastPickaxeHit.t < 1 then
			hitPos = lastPickaxeHit.pos
		elseif usedFeedbackAnchor then
			hitPos = info.Position
		end

		if ActiveNumbers < 12 or info.Crit or info.Click then
			ActiveNumbers += 1
			task.delay(0.85, function() ActiveNumbers -= 1 end)
			damageNumber(part, info.Amount, info.Golden, true, info.Crit, info.Click, hitPos)
		end
		--.. HP ghost bar + one-time low-HP crunch (needs the real live bar)
		if not usedFeedbackAnchor then
			updateGhostBar(part)
		end

		--.. mobile boss hits land heavier: meaty slowed crunch ON the body + a nudge
		if reportedPart and isMobileBossPart(reportedPart) then
			SoundController.PlayFX("Wet Crunch", {Speed = 0.7, Volume = 0.6, Parent = reportedPart})
			cameraKick(0.06)
		end

		--.. FEEL combo (2026-08-26): click-anywhere/tap hits carry no server
		--.. combo, so a client-side counter with the same 3s window stands in
		--.. for the EggClick pitch riser. 2026-08-27 (user: "I keep hearing the
		--.. sound and I haven't reached 5x combo"): the riser is ALL it drives
		--.. now -- the milestone celebration below additionally requires a REAL
		--.. server combo (info.Combo), so the burst only ever fires alongside
		--.. the visible "Nx COMBO" popup, never off this invisible counter.
		local combo
		if info.Combo then
			combo = info.Combo
			feelComboCount = info.Combo
			feelComboLast = os.clock()
		elseif info.Click then
			if os.clock() - feelComboLast > 3 then feelComboCount = 0 end
			feelComboCount += 1
			feelComboLast = os.clock()
			combo = feelComboCount
		end
		if combo then
			--.. rising ladder: every combo hit chirps ~a semitone higher (capped at
			--.. 25); the pitch resets naturally when the combo window restarts at 1
			SoundController.PlayFX("EggClick", {Speed = 2 ^ (math.min(combo, 25) / 12), Volume = 0.5})
			local milestoneIndex = (combo == 5 and 1) or (combo == 10 and 2) or (combo == 25 and 3) or nil
			if info.Combo and combo >= 2 then
				--.. popup only from 2x up: a "1x COMBO" label reads as noise
				comboNumber(part, combo, hitPos, milestoneIndex ~= nil)
			end
			if milestoneIndex and info.Combo then
				--.. milestone celebration -- REAL (visible) combos only since
				--.. 2026-08-27: info.Combo means the popup is on screen, so the
				--.. sting always has a visible 5x/10x/25x to explain it. The old
				--.. unconditional per-combo cameraKick(0.08, 1) is long GONE.
				SoundController.PlayFX("Star Sting", {Speed = 1 + milestoneIndex * 0.1})
				comboConfetti(part)
				cameraKick(0.12, 0.4)
			end
		end
		if info.Click then
			--.. crunch on EVERY confirmed pickaxe hit, combo or not: indirect
			--.. (click-anywhere) hits carry no combo but must SOUND identical
			--.. to a direct click (user-reported missing sfx) -- only the combo
			--.. popup + its extra camera kick stay combo-exclusive
			playSound("Hit Crunch", 0.08, 0.7)
		end
		if info.Click then
			--.. pickaxe strike: swing + zap
			--.. same fade/speed the Place1 pickaxe swung at (FadeTime 0.1, Speed 1.5)
			--.. (the crit EggPop/haptic/vignette burst that used to replace this
			--.. on crit clicks was removed 2026-08-27, user -- the celebration
			--.. feel is combo-milestone-exclusive now; crits keep only their
			--.. "CRIT!" damage number)
			doSwing(0.1, 1.5, 0.7)
		end

		--.. ONE rarity flavor layer max per hit: diamond > charged > mutated > golden
		if info.Diamond then
			SoundController.PlayFX("Glass Shatter", {Speed = 1.3, Volume = 0.3})
		elseif info.Charged then
			--.. user-picked charged-hit sound (2026-08-26), replaces the Zap layer
			SoundController.PlayFX("Charged Hit", {Pitch = 0.05, Volume = 0.35})
		elseif info.Mutation then
			--.. same user-picked sound as charged hits (2026-08-27) -- the old
			--.. sped-up Zap layer read as obnoxious on mutation cucumbers
			SoundController.PlayFX("Charged Hit", {Pitch = 0.05, Volume = 0.35})
		elseif info.Golden then
			SoundController.PlayFX("Coin Tick", {Speed = 1.4, Volume = 0.3})
		end
		if info.Golden then
			goldenCrumbs(part) -- gold flecks on every golden hit
		end

		-- Clicks already popped instantly on input. Pet bolts are also restricted to
		-- server-confirmed passive pet hits; a confirmed pickaxe hit must never draw
		-- shooting lines from pets that are still travelling to the target.
		if not info.Click then
			if info.Crit then
				task.delay(0.06, punch, part) -- mini hit-stop before the crit pop
			else
				task.spawn(punch, part)
			end
			petBolts(part, info.Golden)

			--.. PET SOUND SPAM (P0): pet streams play "Collect" at most 1-in-3,
			--.. with volume decaying 0.5 -> 0.25 across the streak; every 10th
			--.. pet hit re-accents at full volume with a tighter pitch.
			petHitCount += 1
			if petHitCount % 10 == 0 then
				playSound("Collect", 0.05, 0.5)
			elseif petHitCount % 3 == 0 then
				playSound("Collect", 0.18, petStreakVolume)
				petStreakVolume = math.max(0.25, petStreakVolume - 0.04)
			end
		else
			petStreakVolume = 0.5 -- any player click resets the pet-streak decay
			--.. exactly ONE base sound per click hit; the old click+collect pair sounded like double hits
			playSound("Collect", 0.18, 0.5)
		end
	end,

	BreakableTargeted = function(info)
		local part = info and info.Part
		if not part or not part.Parent then return end
		markTarget(part, info.Golden)
		committedTarget = part
		--.. NO swing here: the server fires this on EVERY pet-target commit,
		--.. including the automatic chain-retarget after pets break a cucumber
		--.. (and autofarm hops), so it made the pickaxe swing with no click.
		--.. A player-initiated commit already swings via the InputBegan handler.
	end,

	BreakableBroken = function(info)
		if not info or not info.Position then return end

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local dist = hrp and (hrp.Position - info.Position).Magnitude or math.huge
		if dist > 130 then return end -- far-away breaks: skip entirely (perf)

		local isMine = info.Breaker == player.Name
		local sizeMag = info.Size or 5

		local function boom()
			chunkExplosion(info.Position, info.Color, info.Golden, sizeMag)
			--.. ground shockwave ring, scaled to the body that just burst
			burstRing(info.Position,
				info.Golden and Color3.fromRGB(255, 220, 100) or Color3.fromRGB(235, 255, 225),
				math.max(sizeMag * 0.5, 2), math.clamp(sizeMag * 2.4, 10, 34), 0.45)
			if info.Boss then
				--.. boss deaths ring TWICE, staggered
				task.delay(0.15, function()
					burstRing(info.Position, Color3.fromRGB(255, 170, 70), 4, math.clamp(sizeMag * 3, 20, 44), 0.55)
				end)
			end
		end

		--.. hit-stop: the burst holds a beat when YOU landed the killing blow
		--.. (a big one on bosses) so the pop reads as impact, not a vanish
		local hitStop = 0
		if info.Boss then
			hitStop = 0.25
		elseif isMine and dist < 45 then
			hitStop = 0.05
		end
		if hitStop > 0 then task.delay(hitStop, boom) else boom() end

		if dist < 90 then
			if info.Golden or info.GoldJingle then
				--.. goldens, mutants and bosses share the signature break jingle
				playSound("Sell Sound", 0.1)
				playSound("Hit Crunch", 0.05, 0.8)
			else
				playSound("Cucumber Break", 0.05, 0.8) -- rbxassetid://135076986499326
			end
			--.. fought-for breaks (2+ landed hits) land with a deep thud that
			--.. grows/slows with the body; insta-breaks (Hits == 1) skip it
			if info.Hits and info.Hits > 1 then
				SoundController.PlayFXAt("Big Thud", info.Position, {
					Volume = math.clamp(0.3 + sizeMag * 0.1, 0.3, 0.8);
					Speed = math.clamp(1.1 - sizeMag * 0.03, 0.75, 1.1);
				})
			end
			--.. rarity escalation, additive over the shared jingle:
			--.. boss > diamond > charged/mutated > golden
			if info.Boss then
				SoundController.PlayFX("Boss Death Sting", {Volume = 0.8})
			elseif info.Diamond then
				SoundController.PlayFX("Glass Shatter", {Volume = 0.6})
				sparkleFall(info.Position, sizeMag)
			elseif info.Charged or info.Mutation then
				SoundController.PlayFX("Zap", {Volume = 0.5})
			end
		end
		-- Destruction VFX stay visible to nearby clients, but only the player who
		-- landed the breaking hit receives the camera shake.
		if dist < 45 and isMine then
			if info.Boss then
				cameraKick(0.3) -- sharp pop...
				cameraKick(0.12, 0.8) -- ...then a softer sustained rumble
			elseif info.Diamond then
				cameraKick(0.45)
			elseif info.Charged or info.Mutation then
				cameraKick(0.4)
			else
				cameraKick(info.Golden and 0.35 or 0.18)
			end
		end
	end,

	BossCoinCollected = function()
		--.. SoundController checks the player's SFX toggle before playing.
		SoundController.PlayerSoundClient("Boss Coin Pickup")
	end,

	LightningStrike = function(info)
		if not info or not info.Position then return end
		lightningBolt(info.Position, info.Size)
	end,
})
print("[BreakablesClient] ready (breakable FX + lightning bound).")
