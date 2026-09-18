--[[---------------------------------------DESCRIPTION------------------------------------------
	Builds a mountain from the shared Maps.Attachments library. Walks the shared
	grammar, then snapModule clones each piece and aligns Entrance to the previous Exit.
	Theme comes from props under Storage.Props/<MountainId>, not from unique terrain.

--------------------------------------------------------------------------------------------]]--

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local snapModule = require(ServerStorage.Modules.SnapMountainModule)
local buildMountainSnow = require(ServerStorage.Modules.BuildMountainSnow)
local placeMountainProps = require(ServerStorage.Modules.PlaceMountainProps)

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

	local seed, jobId = seedFromJobId()
	local rng = Random.new(seed)
	print("[SERVER]: Generating mountain", mountainId, "seed", seed, "jobId", jobId)

	local sequence = walkGrammar(rng, grammar, available)
	if not sequence then
		return nil
	end
	print("[SERVER]: Sequence", table.concat(sequence, " → "))

	local existing = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	if existing then
		existing:Destroy()
	end

	local mountainModel = Instance.new("Model")
	mountainModel.Name = mountainConfig.WORKSPACE_NAME
	mountainModel:SetAttribute("MountainId", mountainId)
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

	local snowPatches = buildMountainSnow(mountainModel, mountainId)
	print("[SERVER]: Snow patches", snowPatches)

	local propsPlaced = placeMountainProps(mountainModel, mountainId, seed)
	print("[SERVER]: Props placed", propsPlaced)

	-- Stamp RunLength on the mountain for the race progress bar (SERV_Snowball:GetRun).
	if sself.GetRun then
		local run = sself:GetRun()
		if run then
			print("[SERVER]: Run length", math.floor(run.Total))
		end
	end

	return mountainModel, sequence
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

