--[[---------------------------------------DESCRIPTION------------------------------------------
	Places themed props on Decor_ / Destructible_ / LandmarkPoint sockets.
	Terrain is shared; only the prop library under Props/<MountainId> changes.

--------------------------------------------------------------------------------------------]]--

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()

local function findLibrary(settings)
	local storage = ServerStorage.Assets.Storage
	local propsFolder = storage:FindFirstChild(settings.StorageFolder)
	if not propsFolder then
		return nil
	end
	return propsFolder:FindFirstChild(settings.LibraryName)
end

local function findTemplate(library, name)
	if not library or not name then
		return nil
	end
	local direct = library:FindFirstChild(name)
	if direct and direct:IsA("Model") then
		return direct
	end
	for _, desc in library:GetDescendants() do
		if desc:IsA("Model") and desc.Name == name then
			return desc
		end
	end
	return nil
end

local function getSectionKind(section)
	local kind = section:GetAttribute("AttachmentType")
	if kind then
		return kind
	end

	local best = nil
	for _, typeName in mountainConfig.Attachments do
		if section.Name == typeName or string.sub(section.Name, 1, #typeName + 1) == typeName .. "_" then
			if not best or #typeName > #best then
				best = typeName
			end
		end
	end
	return best or section.Name
end

local function collectModules(mountain)
	local modules = {}
	if mountain:FindFirstChild("Root") and mountain:FindFirstChild("Collision") then
		table.insert(modules, mountain)
		return modules
	end
	for _, child in mountain:GetChildren() do
		if child:IsA("Model") and child:FindFirstChild("Root") and child:FindFirstChild("Collision") then
			table.insert(modules, child)
		end
	end
	table.sort(modules, function(a, b)
		return a.Name < b.Name
	end)
	return modules
end

local function collectSockets(section)
	local root = section:FindFirstChild("Root")
	if not root then
		return {}
	end

	local sockets = {}
	for _, instance in root:GetChildren() do
		if instance:IsA("Attachment")
			and (
				string.sub(instance.Name, 1, 6) == "Decor_"
				or string.sub(instance.Name, 1, 13) == "Destructible_"
				or instance.Name == "LandmarkPoint"
				or instance:GetAttribute("PropModel") ~= nil
			)
		then
			table.insert(sockets, instance)
		end
	end
	table.sort(sockets, function(a, b)
		return a.Name < b.Name
	end)
	return sockets
end

local function hashName(seed, text)
	local hash = seed
	for i = 1, #text do
		hash = (hash * 31 + string.byte(text, i)) % 2147483647
	end
	return hash
end

local function pickIndexed(list, index)
	if not list or #list == 0 then
		return nil
	end
	return list[(index - 1) % #list + 1]
end

local function chooseModel(kind, socket, index, settings, seed)
	local custom = socket:GetAttribute("PropModel")
	if typeof(custom) == "string" and custom ~= "" then
		return custom
	end
	if socket.Name == "LandmarkPoint" then
		return if settings.PlaceFinalLodge then settings.Landmark else nil
	end
	if string.sub(socket.Name, 1, 13) == "Destructible_" then
		local n = tonumber(string.match(socket.Name, "(%d+)$")) or 1
		return pickIndexed(settings.Targets, n)
	end
	if string.sub(socket.Name, 1, 6) ~= "Decor_" then
		return nil
	end

	if kind == "StartPlatform" then
		return pickIndexed(settings.Start, index)
	elseif kind == "FinishPlatform" then
		if type(settings.Finish) == "table" then
			return pickIndexed(settings.Finish, index)
		end
		return settings.Finish
	elseif kind == "JumpRamp" or kind == "Drop" then
		return settings.JumpOrDrop
	elseif string.find(kind, "Valley", 1, true) then
		return pickIndexed(settings.Valley, index)
	elseif kind == "DestructionZone" then
		return pickIndexed(settings.Trees, index)
	elseif kind == "Flat_Transition" then
		return if index == 1 then settings.FlatFirst else settings.FlatOther
	end

	local rng = Random.new(hashName(seed, kind .. socket.Name))
	if rng:NextNumber() < (settings.TreeChance or 0.7) then
		return pickIndexed(settings.Trees, rng:NextInteger(1, math.max(1, #(settings.Trees or {}))))
	end
	return pickIndexed(settings.Rocks, rng:NextInteger(1, math.max(1, #(settings.Rocks or {}))))
end

local function groundPosition(section, socket, snowHeight)
	local collision = section:FindFirstChild("Collision")
	if not collision then
		return nil
	end

	local filter = { collision }
	local visual = section:FindFirstChild("Visual")
	local snow = visual and visual:FindFirstChild("SnowPatches")
	if snow then
		table.insert(filter, snow)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(socket.WorldPosition + Vector3.new(0, 30, 0), Vector3.new(0, -100, 0), params)
	if not hit then
		return nil
	end

	local position = hit.Position
	if hit.Instance:IsDescendantOf(collision) then
		position += Vector3.new(0, snowHeight, 0)
	end
	return position
end

local function placeProp(section, socket, template, folder, position, placed)
	local forward = socket.WorldCFrame.LookVector
	forward = Vector3.new(forward.X, 0, forward.Z)
	if forward.Magnitude < 0.01 then
		forward = Vector3.new(0, 0, -1)
	end

	local yaw = math.pi
	local info = template:FindFirstChild("PropInfo")
	if info then
		local category = info:FindFirstChild("Category")
		if category and (category.Value == "Tree" or category.Value == "Rock") then
			yaw += math.rad((placed * 47) % 360)
		end
	end

	local clone = template:Clone()
	clone.Name = template.Name .. "_" .. socket.Name
	clone:PivotTo(CFrame.lookAt(position, position + forward.Unit) * CFrame.Angles(0, yaw, 0))

	local source = Instance.new("ObjectValue")
	source.Name = "SourceSocket"
	source.Value = socket
	source.Parent = clone
	clone.Parent = folder
end

local function placeMountainProps(mountainModel, mountainId, seed)
	local settings = mountainConfig:GetPropSettings(mountainId)
	if not settings.Enabled then
		return 0
	end

	local library = findLibrary(settings)
	if not library then
		warn("[SERVER]: Prop library not found:", settings.StorageFolder, settings.LibraryName)
		return 0
	end

	local snow = mountainConfig:GetSnowSettings(mountainId)
	local snowHeight = if snow.Enabled then snow.Thickness else 0
	local placed = 0

	for _, section in collectModules(mountainModel) do
		local kind = getSectionKind(section)
		local oldFolder = section:FindFirstChild(settings.DecorFolder)
		if oldFolder then
			oldFolder:Destroy()
		end

		-- Keep the launch pad clear. FinishPlatform still gets resort props.
		if kind == "StartPlatform" then
			continue
		end

		local folder = Instance.new("Folder")
		folder.Name = settings.DecorFolder
		folder.Parent = section

		for index, socket in collectSockets(section) do
			local modelName = chooseModel(kind, socket, index, settings, seed)
			if not modelName then
				continue
			end

			local template = findTemplate(library, modelName)
			if not template and kind == "FinishPlatform" then
				local finishList = if type(settings.Finish) == "table" then settings.Finish else { settings.Finish }
				for _, fallback in finishList do
					template = findTemplate(library, fallback)
					if template then
						break
					end
				end
			end
			if not template then
				warn("[SERVER]: Unknown prop:", modelName)
				continue
			end

			local position = groundPosition(section, socket, snowHeight)
			if not position then
				warn("[SERVER]: No ground under", socket:GetFullName())
				continue
			end

			placeProp(section, socket, template, folder, position, placed)
			placed += 1
		end
	end

	return placed
end

return placeMountainProps

