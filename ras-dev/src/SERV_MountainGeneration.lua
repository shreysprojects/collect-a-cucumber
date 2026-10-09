--[[---------------------------------------DESCRIPTION------------------------------------------
	Builds a mountain from the shared Maps.Attachments library. Walks the shared
	grammar, then snapModule clones each piece and aligns Entrance to the previous Exit.
	Each mountain's Length is the finish distance in meters. Piece count is chosen
	from that length, then the built course is scaled so the run lands on it.
	Theme comes from props under Storage.Props/<MountainId>, not from unique terrain.

	Once built, SetupMountainSpawn puts an invisible SpawnLocation on the launch pad
	(so respawns never start off the map) and stamps the spawn / StartPlatform box
	on GameInfo for SERV_PlayerEvents and CLIENT_SpawnGuard.

--------------------------------------------------------------------------------------------]]--

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local snapModule = require(ServerStorage.Modules.SnapMountainModule)
local buildMountainSnow = require(ServerStorage.Modules.BuildMountainSnow)
local placeMountainProps = require(ServerStorage.Modules.PlaceMountainProps)
local buildMountainBorders = require(ServerStorage.Modules.BuildMountainBorders)

local MODULE = {}
local m_api = {}
local m_sapi = {}
local sself = m_sapi

local INF = 1e9
local T = mountainConfig.Attachment

function MODULE.new(r_sapi)
	sself = r_sapi
	return m_api, m_sapi
end

local function ensureCollisionGroup(name)
	if not name or name == "" or PhysicsService:IsCollisionGroupRegistered(name) then
		return
	end
	PhysicsService:RegisterCollisionGroup(name)
end

function m_sapi:SetupMountainCollisionGroups()
	local physics = mountainConfig.PHYSICS
	ensureCollisionGroup(physics.SnowballGroup)
	ensureCollisionGroup(physics.PlayerBarrierGroup)
	PhysicsService:CollisionGroupSetCollidable(physics.SnowballGroup, physics.PlayerBarrierGroup, false)
end

local function isPlayerBarrier(part)
	local name = mountainConfig.PHYSICS.PlayerBarrierName
	return part.Name == name or string.sub(part.Name, 1, #name) == name
end

local function applyStartPlatformBarriers(piece)
	if not piece then
		return 0
	end

	sself:SetupMountainCollisionGroups()
	local group = mountainConfig.PHYSICS.PlayerBarrierGroup
	local count = 0
	local function consider(inst)
		if inst:IsA("BasePart") and isPlayerBarrier(inst) then
			inst.CanCollide = true
			inst.CollisionGroup = group
			count += 1
		end
	end

	consider(piece)
	for _, desc in piece:GetDescendants() do
		consider(desc)
	end
	return count
end

local function hashString(str)
	local hash = 2166136261
	for i = 1, #str do
		hash = bit32.bxor(hash, string.byte(str, i))
		hash = bit32.band(hash * 16777619, 0xFFFFFFFF)
	end
	return hash
end

local function seedFromJobId()
	local jobId = game.JobId
	if jobId == "" then
		jobId = tostring(os.time())
	end
	return hashString(jobId), jobId
end

local function hasSockets(model, entranceName, exitName)
	return snapModule.getSocket(model, entranceName) ~= nil and snapModule.getSocket(model, exitName) ~= nil
end

local function collectVariants(typeNode)
	if not typeNode then
		return {}
	end
	if typeNode:IsA("Model") then
		return { typeNode }
	end

	local variants = {}
	for _, child in typeNode:GetChildren() do
		if child:IsA("Model") then
			table.insert(variants, child)
		end
	end
	return variants
end

local function resolveAvailableTypes(mountainFolder, entranceName, exitName)
	local available = {}
	local variantsByType = {}

	for _, typeName in mountainConfig.Attachments do
		local node = mountainFolder:FindFirstChild(typeName)
		local variants = collectVariants(node)
		local valid = {}
		for _, variant in variants do
			if hasSockets(variant, entranceName, exitName) then
				table.insert(valid, variant)
			else
				warn("[SERVER]: Piece missing Entrance/Exit:", variant:GetFullName())
			end
		end
		if #valid > 0 then
			available[typeName] = true
			variantsByType[typeName] = valid
		elseif node then
			warn("[SERVER]: No valid variants for attachment type:", typeName)
		end
	end

	return available, variantsByType
end

local function filterNext(nextMap, available)
	local filtered = {}
	for from, tos in nextMap do
		local list = {}
		for _, to in tos do
			if available[to] then
				table.insert(list, to)
			end
		end
		filtered[from] = list
	end
	return filtered
end

local function computeMinMiddlesToFinish(nextMap)
	local dist = {
		[T.FinishPlatform] = 0,
	}
	local prev = {}
	for from, tos in nextMap do
		if dist[from] == nil then
			dist[from] = INF
		end
		for _, to in tos do
			if dist[to] == nil then
				dist[to] = if to == T.FinishPlatform then 0 else INF
			end
			if not prev[to] then
				prev[to] = {}
			end
			table.insert(prev[to], from)
		end
	end

	local queue = { T.FinishPlatform }
	local i = 1
	while i <= #queue do
		local node = queue[i]
		i += 1
		for _, from in prev[node] or {} do
			local candidate = if node == T.FinishPlatform then 0 else 1 + dist[node]
			if candidate < dist[from] then
				dist[from] = candidate
				table.insert(queue, from)
			end
		end
	end

	return dist
end

local function weightedPick(rng, candidates, weights)
	local total = 0
	for _, name in candidates do
		total += weights[name] or 1
	end
	if total <= 0 then
		return candidates[rng:NextInteger(1, #candidates)]
	end

	local roll = rng:NextNumber(0, total)
	local acc = 0
	for _, name in candidates do
		acc += weights[name] or 1
		if roll <= acc then
			return name
		end
	end
	return candidates[#candidates]
end

local function shuffleCopy(rng, list)
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function walkGrammar(rng, grammar, available)
	local nextMap = filterNext(grammar.Next, available)
	local dist = computeMinMiddlesToFinish(nextMap)

	if not available[T.StartPlatform] or not available[T.FinishPlatform] then
		warn("[SERVER]: Mountain is missing StartPlatform or FinishPlatform variants")
		return nil
	end
	if (dist[T.StartPlatform] or INF) >= INF then
		warn("[SERVER]: FinishPlatform is not reachable from StartPlatform with available pieces")
		return nil
	end

	local sequence = { T.StartPlatform }
	local counts = { [T.StartPlatform] = 1 }
	local middleCount = 0
	local current = T.StartPlatform
	local safety = grammar.MaxPieces + 16

	while current ~= T.FinishPlatform and safety > 0 do
		safety -= 1
		local allowed = {}

		for _, candidate in nextMap[current] or {} do
			if current == T.StartPlatform and available[T.Downhill_Steep] and candidate ~= T.Downhill_Steep then
				continue
			end
			if candidate == T.FinishPlatform then
				if middleCount >= grammar.MinPieces then
					table.insert(allowed, candidate)
				end
				continue
			end

			local maxCount = grammar.MaxCount[candidate]
			if maxCount and (counts[candidate] or 0) >= maxCount then
				continue
			end
			if middleCount + 1 > grammar.MaxPieces then
				continue
			end

			local remaining = grammar.MaxPieces - (middleCount + 1)
			if (dist[candidate] or INF) > remaining then
				continue
			end

			table.insert(allowed, candidate)
		end

		if #allowed == 0 then
			warn("[SERVER]: Grammar walk stuck at", current, "after", middleCount, "middle pieces")
			return nil
		end

		local nextType = weightedPick(rng, allowed, grammar.Weights)
		table.insert(sequence, nextType)
		counts[nextType] = (counts[nextType] or 0) + 1
		if nextType ~= T.FinishPlatform then
			middleCount += 1
		end
		current = nextType
	end

	if sequence[#sequence] ~= T.FinishPlatform then
		warn("[SERVER]: Grammar walk did not end on FinishPlatform")
		return nil
	end

	return sequence
end

local function pickTemplate(rng, variants)
	for _, variant in shuffleCopy(rng, variants) do
		if hasSockets(variant, mountainConfig.SOCKETS.Entrance, mountainConfig.SOCKETS.Exit) then
			return variant
		end
		warn("[SERVER]: Piece missing Entrance/Exit:", variant:GetFullName())
	end
	return nil
end

local function folderHasPieces(folder)
	for _, typeName in mountainConfig.Attachments do
		if folder:FindFirstChild(typeName) then
			return true
		end
	end
	return false
end

local function findMountainFolder()
	local storage = ServerStorage.Assets.Storage
	local mapsFolder = storage:FindFirstChild(mountainConfig.STORAGE_FOLDER)
	if not mapsFolder then
		return nil
	end

	local attachments = mapsFolder:FindFirstChild(mountainConfig.ATTACHMENTS_MODEL)
	if attachments and folderHasPieces(attachments) then
		return attachments
	end

	-- Pieces can sit directly in Maps while the Attachments model is being filled in.
	if folderHasPieces(mapsFolder) then
		return mapsFolder
	end

	return attachments
end

local function averagePieceSpan(variantsByType, entranceName, exitName)
	local sum, count = 0, 0
	for _, variants in variantsByType do
		for _, template in variants do
			local entrance = snapModule.getSocket(template, entranceName)
			local exit = snapModule.getSocket(template, exitName)
			if entrance and exit then
				local span = (exit.WorldPosition - entrance.WorldPosition).Magnitude
				if span > 5 then
					sum += span
					count += 1
				end
			end
		end
	end
	if count == 0 then
		return 100
	end
	return sum / count
end

-- Enough middle pieces that a uniform scale can hit Length without stretching
-- each segment by more than a little.
local function applyTargetPieces(grammar, target, span)
	local pieces = math.clamp(math.floor(target / math.max(span, 20) + 0.5), 12, 360)
	local ratio = pieces / math.max(grammar.MinPieces, 1)
	grammar.MinPieces = pieces
	grammar.MaxPieces = pieces + 12
	for name, count in grammar.MaxCount do
		grammar.MaxCount[name] = math.max(1, math.floor(count * ratio + 0.5))
	end
	return pieces
end

local function measureRun(mountainModel)
	local startPiece = nil
	for _, child in mountainModel:GetChildren() do
		if child:GetAttribute("AttachmentType") == T.StartPlatform then
			startPiece = child
			break
		end
	end
	local root = startPiece and startPiece:FindFirstChild("Root")
	if not root then
		return nil, nil
	end
	local axis = root.CFrame.LookVector
	axis = Vector3.new(axis.X, 0, axis.Z)
	if axis.Magnitude < 0.05 then
		axis = Vector3.new(0, 0, -1)
	else
		axis = axis.Unit
	end
	local total = 0
	for _, piece in mountainModel:GetChildren() do
		local pieceRoot = piece:FindFirstChild("Root")
		local exit = pieceRoot and pieceRoot:FindFirstChild("Exit")
		if exit then
			total = math.max(total, (exit.WorldPosition - root.Position):Dot(axis))
		end
	end
	return total, root.Position
end

local function scaleMountainToLength(mountainModel, target)
	local measured, origin = measureRun(mountainModel)
	if not measured or measured < 1 or typeof(origin) ~= "Vector3" then
		return measured
	end

	-- Sit inside [target, target + 1) so the meter readout is exactly Length.
	local goal = target + 0.5
	local function apply(factor)
		factor = math.clamp(factor, 0.05, 20)
		mountainModel.WorldPivot = CFrame.new(origin)
		mountainModel:ScaleTo(mountainModel:GetScale() * factor)
		local length, drifted = measureRun(mountainModel)
		if typeof(drifted) == "Vector3" and (drifted - origin).Magnitude > 0.5 then
			mountainModel:TranslateBy(origin - drifted)
			length = measureRun(mountainModel)
		end
		return length
	end

	local factor = goal / measured
	if math.abs(factor - 1) > 0.001 then
		local ok, result = pcall(apply, factor)
		if ok then
			measured = result or measured
		else
			warn("[SERVER]: Failed to scale mountain:", result)
			return measured
		end
	end
	if measured and math.floor(measured + 1e-3) ~= target then
		local ok, result = pcall(apply, goal / math.max(measured, 1))
		if ok then
			measured = result or measured
		else
			warn("[SERVER]: Failed to correct mountain length:", result)
		end
	end
	if measured and (measured < target * 0.5 or measured > target * 1.5) then
		warn("[SERVER]: Mountain length landed at", math.floor(measured), "instead of", target)
	end
	return measured
end

function m_sapi:GenerateMountain(mountainId)
	local mountain = mountainConfig:GetMountain(mountainId)
	if not mountain then
		warn("[SERVER]: Unknown mountain:", mountainId)
		return nil
	end

	local mountainFolder = findMountainFolder()
	if not mountainFolder then
		warn("[SERVER]: Shared attachment library not found:", mountainConfig.STORAGE_FOLDER, mountainConfig.ATTACHMENTS_MODEL)
		return nil
	end

	local grammar = mountainConfig:GetGrammar(mountainId)
	local entranceName = mountainConfig.SOCKETS.Entrance
	local exitName = mountainConfig.SOCKETS.Exit
	local available, variantsByType = resolveAvailableTypes(mountainFolder, entranceName, exitName)
	local targetLength = mountainConfig:GetLength(mountainId)
	if targetLength then
		local span = averagePieceSpan(variantsByType, entranceName, exitName)
		applyTargetPieces(grammar, targetLength, span)
	end

	local seed, jobId = seedFromJobId()
	local rng = Random.new(seed)
	print(
		"[SERVER]: Generating mountain",
		mountainId,
		"difficulty",
		mountain.Difficulty,
		mountain.DifficultyName,
		"pieces",
		grammar.MinPieces,
		grammar.MaxPieces,
		"length",
		targetLength,
		"seed",
		seed,
		"jobId",
		jobId
	)

	local sequence = walkGrammar(rng, grammar, available)
	if not sequence then
		return nil
	end
	print("[SERVER]: Sequence", table.concat(sequence, " → "))

	local existing = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	if existing then
		existing:Destroy()
	end
	sself:ClearMountainSpawn()

	-- Drop the previous visual border pass with the mountain. BuildMountainBorders
	-- clears this folder again before it places, including when borders are disabled.
	local borderSettings = mountainConfig:GetBorderSettings(mountainId)
	local oldBorders = workspace:FindFirstChild(borderSettings.WorkspaceFolder)
	if oldBorders then
		oldBorders:Destroy()
	end

	local mountainModel = Instance.new("Model")
	mountainModel.Name = mountainConfig.WORKSPACE_NAME
	mountainModel:SetAttribute("MountainId", mountainId)
	mountainModel:SetAttribute("Difficulty", mountain.Difficulty or 1)
	mountainModel:SetAttribute("DifficultyName", mountain.DifficultyName or "")
	mountainModel:SetAttribute("CoastResistance", mountainConfig:CoastResistance(mountainId))
	mountainModel:SetAttribute("Seed", seed)
	mountainModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	mountainModel.Parent = workspace

	local prevExit = nil
	for index, typeName in sequence do
		local variants = variantsByType[typeName]
		if not variants then
			warn("[SERVER]: No variants while placing", typeName)
			mountainModel:Destroy()
			return nil
		end

		local template = pickTemplate(rng, variants)
		if not template then
			warn("[SERVER]: Failed to pick template", typeName)
			mountainModel:Destroy()
			return nil
		end

		local target = prevExit or grammar.OriginCFrame
		local ok, piece = pcall(snapModule.snap, target, template, mountainModel)
		if not ok then
			warn("[SERVER]: Failed to snap", typeName, piece)
			mountainModel:Destroy()
			return nil
		end

		piece.Name = typeName .. "_" .. index
		piece:SetAttribute("AttachmentType", typeName)
		if piece:IsA("Model") then
			piece.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end
		prevExit = snapModule.getSocket(piece, exitName)
		if not prevExit then
			warn("[SERVER]: Snapped piece missing Exit:", piece:GetFullName())
			mountainModel:Destroy()
			return nil
		end
	end

	if targetLength then
		local measured = scaleMountainToLength(mountainModel, targetLength)
		mountainModel:SetAttribute("Length", targetLength)
		print("[SERVER]: Mountain length", targetLength, "m, measured", measured and math.floor(measured))
	end

	local snowPatches = buildMountainSnow(mountainModel, mountainId)
	print("[SERVER]: Snow patches", snowPatches)

	local startPiece = sself:GetStartPlatform()
	local barriers = applyStartPlatformBarriers(startPiece)
	print("[SERVER]: StartPlatform player barriers", barriers)

	local propsPlaced = placeMountainProps(mountainModel, mountainId, seed)
	print("[SERVER]: Props placed", propsPlaced)

	local bordersPlaced = buildMountainBorders(mountainModel, mountainId, seed)
	print("[SERVER]: Border clusters", bordersPlaced)

	-- Stamp RunLength on the mountain for the race progress bar (SERV_Snowball:GetRun).
	if sself.GetRun then
		local run = sself:GetRun()
		if run then
			print("[SERVER]: Run length", math.floor(run.Total))
		end
	end

	local spawnInfo = sself:SetupMountainSpawn()
	if spawnInfo then
		print("[SERVER]: Spawn", spawnInfo.CFrame.Position, "mountain bottom", math.floor(spawnInfo.MountainBottom))
	else
		warn("[SERVER]: No launch pad spawn on", mountainId, "- characters keep the default spawn")
	end

	return mountainModel, sequence
end

local function boxBottom(cf, size)
	local half = size * 0.5
	local bottom = math.huge
	for _, x in { -half.X, half.X } do
		for _, y in { -half.Y, half.Y } do
			for _, z in { -half.Z, half.Z } do
				bottom = math.min(bottom, (cf * Vector3.new(x, y, z)).Y)
			end
		end
	end
	return bottom
end

local function gameInfo()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("GameInfo")
end

function m_sapi:ClearMountainSpawn()
	local settings = mountainConfig.SPAWN
	sself.MountainSpawn = nil
	local old = workspace:FindFirstChild(settings.SpawnLocationName)
	if old then
		old:Destroy()
	end
	local info = gameInfo()
	if info then
		info:SetAttribute(settings.InfoSpawnCFrame, nil)
		info:SetAttribute(settings.InfoStartBoxCFrame, nil)
		info:SetAttribute(settings.InfoStartBoxSize, nil)
	end
end

-- Neutral, invisible, non-colliding SpawnLocation on the launch pad, facing the
-- same way SpawnCharacterAtStart does. Also caches the boxes the fall failsafe uses.
function m_sapi:SetupMountainSpawn()
	sself:ClearMountainSpawn()

	local settings = mountainConfig.SPAWN
	local startPiece, mountain = sself:GetStartPlatform()
	local spawnCF = sself:GetMountainSpawnCFrame()
	if not startPiece or not mountain or not spawnCF then
		return nil
	end

	local startCF, startSize = startPiece:GetBoundingBox()
	local mountainCF, mountainSize = mountain:GetBoundingBox()
	local spawnInfo = {
		CFrame = spawnCF,
		StartBoxCFrame = startCF,
		StartBoxSize = startSize,
		MountainBottom = boxBottom(mountainCF, mountainSize),
	}

	local spawnPart = Instance.new("SpawnLocation")
	spawnPart.Name = settings.SpawnLocationName
	spawnPart.Anchored = true
	spawnPart.CanCollide = false
	spawnPart.CanTouch = false
	spawnPart.CanQuery = false
	spawnPart.CastShadow = false
	spawnPart.Transparency = 1
	spawnPart.Neutral = true
	spawnPart.AllowTeamChangeOnTouch = false
	spawnPart.Duration = 0
	spawnPart.Enabled = true
	spawnPart.Size = settings.SpawnLocationSize
	-- Top face flush with the pad floor.
	spawnPart.CFrame = spawnCF * CFrame.new(0, -spawnPart.Size.Y / 2, 0)
	spawnPart.Parent = workspace

	local info = gameInfo()
	if info then
		info:SetAttribute(settings.InfoSpawnCFrame, spawnCF)
		info:SetAttribute(settings.InfoStartBoxCFrame, startCF)
		info:SetAttribute(settings.InfoStartBoxSize, startSize)
	end

	sself.MountainSpawn = spawnInfo
	return spawnInfo
end

function m_sapi:GetStartPlatform()
	local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	if not mountain then
		return nil
	end

	for _, child in mountain:GetChildren() do
		if child:IsA("Model") and (
			child:GetAttribute("AttachmentType") == T.StartPlatform
			or string.sub(child.Name, 1, #T.StartPlatform) == T.StartPlatform
		) then
			return child, mountain
		end
	end
	return nil
end

function m_sapi:GetFinishPlatform()
	local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	return mountainConfig.FindFinishPlatform(mountain), mountain
end

function m_sapi:GetLaunchPlatform()
	local startPiece, mountain = sself:GetStartPlatform()
	local root = startPiece or mountain or workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	if not root then
		return nil
	end

	local pad = mountainConfig.LAUNCH_PAD
	local model = root:FindFirstChild(pad.Model, true)
	if not model then
		return nil
	end

	local collision = model:FindFirstChild(pad.Collision, true)
	if collision and not collision:IsA("BasePart") then
		collision = collision:FindFirstChildWhichIsA("BasePart", true)
	end
	if not collision then
		collision = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not collision then
		return nil
	end

	return model, collision, startPiece, mountain
end

function m_sapi:IsPlayerOnLaunchPad(player)
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local _, collision = sself:GetLaunchPlatform()
	if not hrp or not collision then
		return false
	end
	return mountainConfig.IsOnLaunchPad(hrp.Position, collision)
end

local function surfaceFilter(root)
	local filter = {}
	for _, desc in root:GetDescendants() do
		if desc.Name == "Collision" or desc.Name == "SnowPatches" then
			table.insert(filter, desc)
		end
	end
	if #filter == 0 then
		table.insert(filter, root)
	end
	return filter
end

local function raycastSurface(origin, filter)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = filter
	return workspace:Raycast(origin, Vector3.new(0, -160, 0), params)
end

function m_sapi:GetMountainSpawnCFrame()
	local startPiece = sself:GetStartPlatform()
	if not startPiece then
		return nil
	end

	-- Spawn on the launch pad itself so the Launch button is available right away
	-- (the LaunchPoint socket sits just past the pad's front wall).
	local padModel, padCollision = sself:GetLaunchPlatform()
	if padModel and padCollision then
		local filter = {}
		for _, inst in surfaceFilter(startPiece) do
			if inst ~= padModel and not inst:IsDescendantOf(padModel) then
				table.insert(filter, inst)
			end
		end
		local hit = raycastSurface(padCollision.Position + Vector3.yAxis * 80, filter)
		local position = if hit then hit.Position else padCollision.Position - Vector3.yAxis * (padCollision.Size.Y / 2)
		local exit = snapModule.getSocket(startPiece, mountainConfig.SOCKETS.Exit)
		local look = if exit then exit.WorldCFrame.LookVector else padCollision.CFrame.LookVector
		look = Vector3.new(look.X, 0, look.Z)
		if look.Magnitude < 0.05 then
			look = Vector3.new(0, 0, -1)
		end
		return CFrame.lookAt(position, position + look.Unit)
	end

	local launch = snapModule.getSocket(startPiece, mountainConfig.SOCKETS.LaunchPoint)
		or snapModule.getSocket(startPiece, mountainConfig.SOCKETS.Entrance)
	if not launch then
		return nil
	end

	local hit = raycastSurface(launch.WorldPosition + Vector3.yAxis * 80, surfaceFilter(startPiece))
	local position = if hit then hit.Position else launch.WorldPosition
	local look = Vector3.new(launch.WorldCFrame.LookVector.X, 0, launch.WorldCFrame.LookVector.Z)
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	end

	return CFrame.lookAt(position, position + look.Unit)
end

function m_sapi:GetFinishStandCFrame()
	local finish = sself:GetFinishPlatform()
	if not finish then
		return nil
	end

	local entrance = snapModule.getSocket(finish, mountainConfig.SOCKETS.Entrance)
	if not entrance then
		return nil
	end

	-- Entrance looks downhill into the platform. Stand uphill of it, facing it.
	local look = Vector3.new(entrance.WorldCFrame.LookVector.X, 0, entrance.WorldCFrame.LookVector.Z)
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit

	local back = mountainConfig.FINISH.StandBack or 16
	local origin = entrance.WorldPosition - look * back + Vector3.yAxis * 80
	local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	local hit = raycastSurface(origin, surfaceFilter(mountain or finish))
	local position = if hit then hit.Position else entrance.WorldPosition - look * back
	return CFrame.lookAt(position, position + look)
end

function m_sapi:GetMountainLaunchCFrame()
	local startPiece, mountain = sself:GetStartPlatform()
	if not startPiece then
		return nil
	end

	local exit = snapModule.getSocket(startPiece, mountainConfig.SOCKETS.Exit)
		or snapModule.getSocket(startPiece, mountainConfig.SOCKETS.LaunchPoint)
	if not exit then
		return sself:GetMountainSpawnCFrame()
	end

	local travel = exit.WorldCFrame.LookVector
	local origin = exit.WorldPosition + travel * mountainConfig.LAUNCH.ExitOffset + Vector3.yAxis * 80
	local hit = raycastSurface(origin, surfaceFilter(mountain or startPiece))
	local position = if hit then hit.Position else exit.WorldPosition + travel * mountainConfig.LAUNCH.ExitOffset

	local look = travel
	if hit then
		local alongSlope = look - hit.Normal * look:Dot(hit.Normal)
		if alongSlope.Magnitude > 0.05 then
			look = alongSlope.Unit
		end
	elseif Vector3.new(look.X, 0, look.Z).Magnitude > 0.05 then
		look = Vector3.new(look.X, 0, look.Z).Unit
	else
		look = Vector3.new(0, 0, -1)
	end

	local up = if hit then hit.Normal else Vector3.yAxis
	return CFrame.lookAt(position, position + look, up), look
end

function m_sapi:GetPlayerLaunchCFrame(player)
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local padModel, _, startPiece, mountain = sself:GetLaunchPlatform()
	startPiece = startPiece or sself:GetStartPlatform()
	if not startPiece then
		return nil
	end

	local _, downhill = sself:GetMountainLaunchCFrame()
	local look = downhill
	if not look then
		local exit = snapModule.getSocket(startPiece, mountainConfig.SOCKETS.Exit)
			or snapModule.getSocket(startPiece, mountainConfig.SOCKETS.LaunchPoint)
		if exit then
			look = Vector3.new(exit.WorldCFrame.LookVector.X, 0, exit.WorldCFrame.LookVector.Z)
		end
	end
	if not look or look.Magnitude < 0.05 then
		look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	end
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit

	local origin = hrp.Position + look * mountainConfig.LAUNCH.ForwardOffset + Vector3.yAxis * 80
	local filter = {}
	for _, inst in surfaceFilter(mountain or startPiece) do
		if padModel and (inst == padModel or inst:IsDescendantOf(padModel)) then
			continue
		end
		table.insert(filter, inst)
	end
	local hit = raycastSurface(origin, filter)
	local position = if hit then hit.Position else hrp.Position + look * mountainConfig.LAUNCH.ForwardOffset
	local up = if hit then hit.Normal else Vector3.yAxis
	if hit then
		local alongSlope = look - hit.Normal * look:Dot(hit.Normal)
		if alongSlope.Magnitude > 0.05 then
			look = alongSlope.Unit
		end
	end

	return CFrame.lookAt(position, position + look, up), look
end

function m_sapi:PlaceCharacter(character, spawnCF)
	if not character or not character.Parent or not spawnCF then
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		return false
	end

	if humanoid.SeatPart then
		humanoid.Sit = false
	end

	local height = humanoid.HipHeight + (hrp.Size.Y / 2) + mountainConfig.SPAWN.ExtraHeight
	character:PivotTo(spawnCF + Vector3.yAxis * height)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	return true
end

function m_sapi:SpawnCharacterAtStart(character)
	local spawnCF = sself:GetMountainSpawnCFrame()
	if not spawnCF then
		return false
	end

	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not hrp or not humanoid then
		return false
	end

	-- Wait out Roblox's default spawn so it cannot overwrite this teleport.
	task.wait()
	if not character.Parent then
		return false
	end

	local height = humanoid.HipHeight + (hrp.Size.Y / 2) + mountainConfig.SPAWN.ExtraHeight
	character:PivotTo(spawnCF + Vector3.yAxis * height)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	return true
end

return MODULE

