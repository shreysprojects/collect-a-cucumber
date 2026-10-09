-- Wild West's original rat/revolver models and ten-target hunt, without rewards.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local assets = ServerStorage:WaitForChild("PortalHuntAssets")
local module = {}
local states = {}
local shotVisual
local RAT_COUNT, RANGE, SHOT_DELAY = 10, 500, 2

local function ragdoll(rat)
	local outline = rat:FindFirstChild("TargetOutline")
	if outline then outline:Destroy() end
	local humanoid = rat:FindFirstChildOfClass("Humanoid")
	humanoid.PlatformStand, humanoid.AutoRotate = true, false
	for _, motor in ipairs(rat:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local a, b = Instance.new("Attachment"), Instance.new("Attachment")
			a.CFrame, a.Parent = motor.C0, motor.Part0
			b.CFrame, b.Parent = motor.C1, motor.Part1
			local joint = Instance.new("BallSocketConstraint")
			joint.Attachment0, joint.Attachment1 = a, b
			joint.LimitsEnabled, joint.UpperAngle = true, 50
			joint.Parent = motor.Parent
			motor.Enabled = false
		end
	end
	for _, part in ipairs(rat:GetDescendants()) do
		if part:IsA("BasePart") then part.CanCollide = part.Name ~= "HumanoidRootPart" end
	end
	local root = rat:FindFirstChild("HumanoidRootPart")
	if root then root:ApplyImpulse(Vector3.new(0, 18, 0) * root.AssemblyMass) end
	Debris:AddItem(rat, 2)
end

function module.Cleanup(player)
	local state = states[player]
	states[player] = nil
	if state then
		state.Alive = false
		if state.Gun then state.Gun:Destroy() end
		for _, connection in ipairs(state.Connections) do connection:Disconnect() end
	end
	player:SetAttribute("DesertRatsKilled", nil)
	player:SetAttribute("DesertRatsTotal", nil)
	player:SetAttribute("DesertReloadUntil", nil)
end

function module.Equip(player)
	local state = states[player]
	if not state or not state.Alive then return end
	if state.Gun then state.Gun:Destroy() end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or humanoid.Health <= 0 or not backpack then return end
	local gun = assets.Revolver:Clone()
	gun:SetAttribute("DesertHuntWeapon", true)
	gun.CanBeDropped = false
	gun.Parent = backpack
	state.Gun = gun
	humanoid:EquipTool(gun)
end

function module.Attach(player, session, finished)
	module.Cleanup(player)
	local map, ground = session.Map, session.Map:FindFirstChild("Union")
	assert(ground and ground:IsA("BasePart"), "Wild West ground missing")
	local state = {Alive = true, Kills = 0, Connections = {}, Map = map, NextShot = 0, Session = session}
	states[player] = state
	player:SetAttribute("DesertRatsKilled", 0)
	player:SetAttribute("DesertRatsTotal", RAT_COUNT)
	local rats = Instance.new("Folder")
	rats.Name, rats.Parent = "DesertRats", map
	state.Rats = rats
	local rng = Random.new()
	local groundTop = ground.Position.Y + ground.Size.Y / 2
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = {map}
	rayParams.RespectCanCollide = true
	for index = 1, RAT_COUNT do
		local rat = assets.Rat:Clone()
		rat.Name = "Rat_" .. index
		rat:SetAttribute("DesertRat", true)
		rat:SetAttribute("OwnerUserId", player.UserId)
		local humanoid, root = rat:FindFirstChildOfClass("Humanoid"), rat:FindFirstChild("HumanoidRootPart")
		assert(humanoid and root, "Rat rig is incomplete")
		humanoid.BreakJointsOnDeath = false
		humanoid.MaxHealth, humanoid.Health, humanoid.WalkSpeed = 1, 1, 15
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		for _, part in ipairs(rat:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanQuery, part.CanTouch = true, true
				part.CollisionGroup = "Default"
			end
		end
		local angle = index / RAT_COUNT * math.pi * 2
		local radius = 24 + index % 3 * 11
		local position = ground.Position + Vector3.new(math.cos(angle) * radius, ground.Size.Y / 2 + 2.2, math.sin(angle) * radius)
		for attempt = 1, 12 do
			local hit = workspace:Raycast(Vector3.new(position.X, groundTop + 55, position.Z), Vector3.new(0, -60, 0), rayParams)
			if hit and hit.Instance == ground then break end
			angle, radius = rng:NextNumber(0, math.pi * 2), rng:NextNumber(18, 55)
			position = Vector3.new(ground.Position.X + math.cos(angle) * radius, groundTop + 2.2, ground.Position.Z + math.sin(angle) * radius)
		end
		rat:PivotTo(CFrame.lookAt(position, Vector3.new(ground.Position.X, position.Y, ground.Position.Z)))
		rat.Parent = rats
		root:SetNetworkOwner(nil)
		local outline = Instance.new("Highlight")
		outline.Name, outline.Adornee = "TargetOutline", rat
		outline.FillTransparency, outline.OutlineTransparency = 1, 0
		outline.OutlineColor = Color3.fromRGB(255, 225, 70)
		outline.DepthMode, outline.Parent = Enum.HighlightDepthMode.AlwaysOnTop, rat
		local animation = rat:FindFirstChildWhichIsA("Animation")
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animation and animator then
			local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
			if ok then track.Looped = true track:Play() end
		end
		table.insert(state.Connections, humanoid.Died:Connect(function()
			if not state.Alive or rat:GetAttribute("ShotByOwner") ~= true then return end
			ragdoll(rat)
			state.Kills += 1
			player:SetAttribute("DesertRatsKilled", state.Kills)
			if state.Kills >= RAT_COUNT then
				task.delay(.8, function() if states[player] == state and state.Alive then finished() end end)
			end
		end))
		task.spawn(function()
			task.wait(rng:NextNumber(.1, 1.2))
			while state.Alive and rat.Parent and humanoid.Health > 0 do
				local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(12, 55)
				local target = Vector3.new(ground.Position.X + math.cos(a) * r, groundTop + 2, ground.Position.Z + math.sin(a) * r)
				if root.Position.Y < groundTop - 15 then rat:PivotTo(CFrame.new(position)) end
				humanoid:MoveTo(target)
				task.wait(rng:NextNumber(2.1, 4.2))
			end
		end)
	end
	module.Equip(player)
end

function module.Fire(player, aim)
	local state = states[player]
	if not state or not state.Alive or state.Session.Busy or player:GetAttribute("PortalTransitioning")
		or player:GetAttribute("MinigameKey") ~= "DesertHunt" or typeof(aim) ~= "Vector3" then return false end
	if aim.X ~= aim.X or aim.Y ~= aim.Y or aim.Z ~= aim.Z or aim.Magnitude > 1e7 then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local gun = state.Gun
	if not gun or gun.Parent ~= character or not humanoid or humanoid.Health <= 0 or os.clock() < state.NextShot then return false end
	local handle = gun:FindFirstChild("Handle")
	local origin = handle.Position
	local delta = aim - origin
	if delta.Magnitude < .1 then return false end
	state.NextShot = os.clock() + SHOT_DELAY
	player:SetAttribute("DesertReloadUntil", workspace:GetServerTimeNow() + SHOT_DELAY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {state.Map}
	local hit = workspace:Raycast(origin, delta.Unit * RANGE, params)
	local endpoint = hit and hit.Position or origin + delta.Unit * RANGE
	local killed = false
	local rat = hit and hit.Instance:FindFirstAncestorOfClass("Model")
	if rat and rat.Parent == state.Rats and rat:GetAttribute("OwnerUserId") == player.UserId then
		local target = rat:FindFirstChildOfClass("Humanoid")
		if target and target.Health > 0 then
			rat:SetAttribute("ShotByOwner", true)
			target.Health = 0
			killed = true
		end
	end
	shotVisual:FireClient(player, origin, endpoint, killed)
	return true, killed
end

function module.Start(remotes)
	local fire = Instance.new("RemoteEvent")
	fire.Name, fire.Parent = "DesertFire", remotes
	shotVisual = Instance.new("RemoteEvent")
	shotVisual.Name, shotVisual.Parent = "DesertShot", remotes
	fire.OnServerEvent:Connect(module.Fire)
	Players.PlayerRemoving:Connect(module.Cleanup)
end

return module