local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local ServerController = require(ServerStorage:WaitForChild("ServerController"))
local BreakablesService = ServerController.GetModule("BreakablesService")

local NukeService = {}
local PRODUCT_ID = 3610280695
local TRAVEL_TIME = 5
local Queue = {}
local Running = false

local remote = ReplicatedStorage:FindFirstChild("NukeEvent")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "NukeEvent"
	remote.Parent = ReplicatedStorage
end

local function playGlobalSound(assetId, name, volume)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. tostring(assetId)
	sound.Volume = volume or 1
	sound.RollOffMode = Enum.RollOffMode.Inverse
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		if sound.Parent then sound:Destroy() end
	end)
	Debris:AddItem(sound, 30)
end

local function effectFolder()
	local folder = workspace:FindFirstChild("NukeEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "NukeEffects"
		folder.Parent = workspace
	end
	return folder
end

local function effectPart(name, shape, color, material, cframe, size)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Color = color
	part.Material = material
	part.CFrame = cframe
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

local function makeEmitter(parent, texture, color, lifetime, speed, size, transparency, spread)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Color = color
	emitter.Lifetime = lifetime
	emitter.Speed = speed
	emitter.Size = size
	emitter.Transparency = transparency
	emitter.SpreadAngle = spread
	emitter.Rate = 0
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = parent
	return emitter
end

local function createMissile(area, index)
	local template = ReplicatedStorage:FindFirstChild("Missle")
	if not template or not template:IsA("Model") then
		warn("[NukeService] ReplicatedStorage.Missle model is missing")
		return
	end

	local model = template:Clone()
	model.Name = "NukeMissile_" .. area.Name

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		elseif descendant:IsA("LuaSourceContainer") then
			descendant.Enabled = false
		end
	end

	local tip = model:FindFirstChild("Tip", true)
	local base = model:FindFirstChild("Base", true)
	local sourcePivot = model:GetPivot()
	local sourceDirection = sourcePivot.LookVector
	if tip and tip:IsA("BasePart") and base and base:IsA("BasePart") then
		sourceDirection = (tip.Position - base.Position).Unit
	end

	local desiredDirection = Vector3.new(0, -1, 0)
	local dot = math.clamp(sourceDirection:Dot(desiredDirection), -1, 1)
	local alignment = CFrame.new()
	if dot < 0.9999 then
		local axis = sourceDirection:Cross(desiredDirection)
		if axis.Magnitude < 0.001 then
			axis = sourceDirection:Cross(Vector3.xAxis)
			if axis.Magnitude < 0.001 then
				axis = sourceDirection:Cross(Vector3.zAxis)
			end
		end
		alignment = CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
	end
	local alignedRotation = alignment.Rotation * sourcePivot.Rotation

	local target = area.Position + Vector3.new(0, 4, 0)
	local tipOffset = Vector3.zero
	if tip and tip:IsA("BasePart") then
		local localTipPosition = sourcePivot:PointToObjectSpace(tip.Position)
		tipOffset = alignedRotation:VectorToWorldSpace(localTipPosition)
	end
	local targetPivot = CFrame.new(target - tipOffset) * alignedRotation
	local startHeight = 270 + index * 6
	local initialPivot = targetPivot + Vector3.new(0, startHeight, 0)
	model:PivotTo(initialPivot)
	model.Parent = effectFolder()

	if base and base:IsA("BasePart") then
		local fire = base:FindFirstChildOfClass("Fire")
		if fire then
			fire.Enabled = true
			fire.Heat = math.max(fire.Heat, 18)
			fire.Size = math.max(fire.Size, 12)
		end
		local smoke = base:FindFirstChildOfClass("Smoke")
		if smoke then
			smoke.Enabled = true
			smoke.Opacity = math.max(smoke.Opacity, 0.45)
			smoke.RiseVelocity = math.max(smoke.RiseVelocity, 14)
			smoke.Size = math.max(smoke.Size, 10)
		end
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 125, 30)
		light.Brightness = 5
		light.Range = 28
		light.Parent = base
	end

	local driver = Instance.new("CFrameValue")
	driver.Value = initialPivot
	local changed = driver:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			model:PivotTo(driver.Value)
		end
	end)
	local tween = TweenService:Create(driver, TweenInfo.new(TRAVEL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Value = targetPivot,
	})
	tween:Play()
	tween.Completed:Connect(function()
		changed:Disconnect()
		driver:Destroy()
		if model.Parent then
			model:Destroy()
		end
	end)
	Debris:AddItem(model, TRAVEL_TIME + 2)
end

local function createExplosion(area)
	local center = area.Position + Vector3.new(0, 7, 0)
	local diameter = math.max(area.Size.X, area.Size.Z) * 1.35
	local folder = effectFolder()

	local core = effectPart(
		"NuclearFireball",
		Enum.PartType.Ball,
		Color3.fromRGB(255, 245, 155),
		Enum.Material.Neon,
		CFrame.new(center),
		Vector3.one * 4
	)
	core.Transparency = 0.05
	core.Parent = folder
	TweenService:Create(core, TweenInfo.new(1.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * diameter,
		Transparency = 1,
		Color = Color3.fromRGB(255, 65, 10),
	}):Play()
	Debris:AddItem(core, 1.4)

	local shockwave = effectPart(
		"NuclearShockwave",
		Enum.PartType.Cylinder,
		Color3.fromRGB(255, 225, 125),
		Enum.Material.Neon,
		CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(1.2, 8, 8)
	)
	shockwave.Transparency = 0.12
	shockwave.Parent = folder
	TweenService:Create(shockwave, TweenInfo.new(1.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = Vector3.new(1.2, diameter * 1.65, diameter * 1.65),
		Transparency = 1,
	}):Play()
	Debris:AddItem(shockwave, 1.6)

	local burst = effectPart(
		"NuclearBurst",
		Enum.PartType.Ball,
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		CFrame.new(center),
		Vector3.one
	)
	burst.Transparency = 1
	burst.Parent = folder

	local fire = makeEmitter(
		burst,
		"rbxasset://textures/particles/explosion01_implosion_main.dds",
		ColorSequence.new(Color3.fromRGB(255, 255, 210), Color3.fromRGB(255, 65, 5)),
		NumberRange.new(0.65, 1.15),
		NumberRange.new(45, 90),
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 8),
			NumberSequenceKeypoint.new(0.55, 20),
			NumberSequenceKeypoint.new(1, 0),
		}),
		NumberSequence.new(0.02, 1),
		Vector2.new(180, 180)
	)
	fire:Emit(140)

	local smoke = makeEmitter(
		burst,
		"rbxasset://textures/particles/smoke_main.dds",
		ColorSequence.new(Color3.fromRGB(100, 85, 70), Color3.fromRGB(20, 20, 25)),
		NumberRange.new(2.5, 4),
		NumberRange.new(18, 42),
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 12),
			NumberSequenceKeypoint.new(0.5, 28),
			NumberSequenceKeypoint.new(1, 42),
		}),
		NumberSequence.new(0.18, 1),
		Vector2.new(180, 180)
	)
	smoke.Drag = 1.5
	smoke.Acceleration = Vector3.new(0, 18, 0)
	smoke:Emit(95)

	local sparks = makeEmitter(
		burst,
		"rbxasset://textures/particles/sparkles_main.dds",
		ColorSequence.new(Color3.fromRGB(255, 245, 160), Color3.fromRGB(255, 75, 10)),
		NumberRange.new(0.8, 1.7),
		NumberRange.new(65, 130),
		NumberSequence.new(1.1, 0),
		NumberSequence.new(0, 1),
		Vector2.new(180, 180)
	)
	sparks:Emit(180)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 65)
	light.Brightness = 18
	light.Range = diameter
	light.Shadows = true
	light.Parent = burst
	TweenService:Create(light, TweenInfo.new(1.1), {Brightness = 0; Range = diameter * 1.5;}):Play()

	local explosion = Instance.new("Explosion")
	explosion.Position = center
	explosion.BlastRadius = 0
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Visible = false
	explosion.Parent = workspace

	remote:FireAllClients("Impact", {Position = center; Radius = diameter; Area = area.Name;})
	Debris:AddItem(burst, 4.5)
end

local function isInsideArea(position, area)
	local localPosition = area.CFrame:PointToObjectSpace(position)
	return math.abs(localPosition.X) <= area.Size.X * 0.5
		and math.abs(localPosition.Z) <= area.Size.Z * 0.5
		and localPosition.Y >= -25
		and localPosition.Y <= 150
end

local function killAndReturnToArea(player, area)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not isInsideArea(root.Position, area) then
		return false
	end

	local safeX = math.random() * math.max(0, area.Size.X - 18) - math.max(0, area.Size.X - 18) * 0.5
	local safeZ = math.random() * math.max(0, area.Size.Z - 18) - math.max(0, area.Size.Z - 18) * 0.5
	local returnCFrame = area.CFrame:PointToWorldSpace(Vector3.new(safeX, 7, safeZ))
	local connection
	connection = player.CharacterAdded:Connect(function(newCharacter)
		connection:Disconnect()
		local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10)
		if not newRoot or player.Parent ~= Players then return end

		-- CharacterAdded fires before Roblox's SpawnLocation placement is always finished.
		-- Re-apply shortly afterward so the default spawn cannot overwrite the nuke return.
		local function returnPlayer()
			if player.Parent == Players and player.Character == newCharacter and newRoot.Parent then
				newCharacter:PivotTo(CFrame.new(returnCFrame))
			end
		end
		task.delay(0.25, returnPlayer)
		task.delay(0.75, returnPlayer)
	end)
	task.delay(15, function()
		if connection and connection.Connected then connection:Disconnect() end
	end)
	humanoid.Health = 0
	return true
end

local function areas()
	local folder = workspace:FindFirstChild("SpawnArea")
	if not folder then return {} end
	local result = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then table.insert(result, child) end
	end
	table.sort(result, function(a, b)
		return (tonumber(a.Name) or math.huge) < (tonumber(b.Name) or math.huge)
	end)
	return result
end

local function executeStrike(purchaser)
	local targets = areas()
	if #targets == 0 then return end

	playGlobalSound(9081625499, "NukeLaunch", 1)
	remote:FireAllClients("Warning", {
		Buyer = purchaser.DisplayName;
		BuyerUserId = purchaser.UserId;
		TravelTime = TRAVEL_TIME;
	})
	for index, area in ipairs(targets) do
		createMissile(area, index)
	end

	task.wait(TRAVEL_TIME)
	playGlobalSound(139316396351592, "NukeExplosion", 1.15)
	local killed = {}
	for _, area in ipairs(targets) do
		createExplosion(area)
		for _, player in ipairs(Players:GetPlayers()) do
			if not killed[player] and killAndReturnToArea(player, area) then
				killed[player] = true
				remote:FireAllClients("PlayerNuked", {
					Victim = player.DisplayName;
					VictimUserId = player.UserId;
					Buyer = purchaser.DisplayName;
					BuyerUserId = purchaser.UserId;
				})
			end
		end
	end

	local collected = 0
	local gained = 0
	if purchaser.Parent == Players then
		local cucumberStat = purchaser:FindFirstChild("leaderstats")
			and purchaser.leaderstats:FindFirstChild("Cukes")
		local before = cucumberStat and cucumberStat.Value or 0
		collected = BreakablesService.NukeAll(purchaser)
		gained = cucumberStat and math.max(0, cucumberStat.Value - before) or 0
	end
	remote:FireAllClients("Complete", {
		Buyer = purchaser.DisplayName;
		BuyerUserId = purchaser.UserId;
		Collected = collected;
		Gained = gained;
		Killed = (function()
			local count = 0
			for _ in pairs(killed) do count += 1 end
			return count
		end)();
	})
end

local function runQueue()
	if Running then return end
	Running = true
	while #Queue > 0 do
		local purchaser = table.remove(Queue, 1)
		if purchaser and purchaser.Parent == Players then
			local ok, err = pcall(executeStrike, purchaser)
			if not ok then warn("[NukeService] strike failed: " .. tostring(err)) end
		end
		task.wait(2)
	end
	Running = false
end

function NukeService.Launch(purchaser)
	if not purchaser or purchaser.Parent ~= Players then return false end
	table.insert(Queue, purchaser)
	task.spawn(runQueue)
	return true
end

function NukeService.Initialize()
	-- ProductHandler owns receipt registration; effects are created lazily per purchase.
end

NukeService.ProductId = PRODUCT_ID
return NukeService
