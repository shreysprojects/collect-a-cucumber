-- Walk-over time skips: each awards a random 10-60 seconds of the collector's current pet farming rate.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
local Network = ControllerLoader.GetController("Network")
local NumberController = ControllerLoader.GetController("NumberController")
local Doors = ServerController.GetDictionary("Doors").Stats
local TimeSkipTemplate = ReplicatedStorage.Assets:WaitForChild("TimeSkip")

local MAP_PICKUPS_ENABLED = false -- floating map time skips removed
local TOTAL_PICKUPS = 5
local RESPAWN_TIME = 10
local MIN_SKIP_SECONDS = 10
local MAX_SKIP_SECONDS = 60
local EDGE_MARGIN = 14

local WalkCucumberService = {}
local Container
local Slots = {}
local ZoneParts = {}
local PlayerSlots = {}

local function OwnsZone(Player, zoneName)
	local profile = ProfileService.GetUserData(Player)
	if not profile then
		return false
	end
	for _, ownedZone in ipairs(string.split(profile.DoorData or "Spawn", " # ")) do
		if ownedZone == zoneName then
			return true
		end
	end
	return zoneName == "Spawn"
end

function WalkCucumberService.RewardOf(Player, zoneName, skipSeconds)
	local seconds = math.clamp(tonumber(skipSeconds) or MIN_SKIP_SECONDS, MIN_SKIP_SECONDS, MAX_SKIP_SECONDS)
	return TimeSkipRateService.Quote(Player, seconds)
end

local function RandomGroundPoint(zonePart)
	local usableX = math.max(4, zonePart.Size.X - EDGE_MARGIN * 2)
	local usableZ = math.max(4, zonePart.Size.Z - EDGE_MARGIN * 2)

	for _ = 1, 30 do
		local localOffset = Vector3.new(
			(math.random() - 0.5) * usableX,
			0,
			(math.random() - 0.5) * usableZ
		)
		local worldPoint = zonePart.CFrame:PointToWorldSpace(localOffset)
		local filter = {Container, workspace.Zones}
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				table.insert(filter, player.Character)
			end
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = filter
		local result = workspace:Raycast(
			worldPoint + Vector3.new(0, 35, 0),
			Vector3.new(0, -70, 0),
			params
		)

		if result
			and result.Normal.Y > 0.65
			and math.abs(result.Position.Y - zonePart.Position.Y) < 8
		then
			return result.Position + Vector3.new(0, 2.2, 0)
		end
	end

	return zonePart.Position + Vector3.new(0, 2.2, 0)
end

local function StripEmbeddedScripts(model)
	-- TimeSkip is a visual asset. Marketplace/free-model scripts must never run
	-- when a pickup is first cloned or later returned from the model pool.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
end

local function BuildPickup(zoneName, position, skipSeconds, pooledModel)
	if pooledModel then
		local model = pooledModel
		StripEmbeddedScripts(model)
		local hitbox = model:FindFirstChild("Hitbox")
		local label = hitbox and hitbox:FindFirstChild("PickupLabel") and hitbox.PickupLabel:FindFirstChildOfClass("TextLabel")
		if hitbox then
			model.Name = "Time Skip"
			model:SetAttribute("Zone", zoneName)
			model.Parent = Container
			model:PivotTo(
				CFrame.new(position)
					* CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
			)
			hitbox.CanTouch = true
			if label then label.Text = tostring(skipSeconds) .. "s" end
			return model, hitbox
		end
		model:Destroy()
	end

	local model = TimeSkipTemplate:Clone()
	StripEmbeddedScripts(model)
	model.Name = "Time Skip"
	model:SetAttribute("Zone", zoneName)

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	model.Parent = Container
	model:PivotTo(
		CFrame.new(position)
			* CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	)

	local boxCFrame, boxSize = model:GetBoundingBox()
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = boxSize + Vector3.new(1.5, 1, 1.5)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = true
	hitbox.CanQuery = false
	hitbox.CFrame = boxCFrame
	hitbox.Parent = model
	model.PrimaryPart = hitbox

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(100, 220, 255)
	light.Brightness = 2
	light.Range = 11
	light.Parent = hitbox

	local highlight = Instance.new("Highlight")
	highlight.Name = "Glow"
	highlight.FillColor = Color3.fromRGB(80, 205, 255)
	highlight.FillTransparency = 0.72
	highlight.OutlineColor = Color3.fromRGB(205, 245, 255)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model

	--.. label look is designed in StarterGui.UITemplates.PickupLabel
	local billboard = game:GetService("StarterGui").UITemplates.PickupLabel:Clone()
	billboard.Enabled = true -- template ships disabled so it never renders in Studio
	billboard.StudsOffsetWorldSpace = Vector3.new(0, boxSize.Y / 2 + 0.8, 0)
	billboard.Label.Text = tostring(skipSeconds) .. "s"
	billboard.Parent = hitbox

	return model, hitbox
end

local SpawnSlot

local function Collect(slot, model, body, hit)
	if slot.Model ~= model or slot.Collected then
		return
	end

	local character = hit and hit:FindFirstAncestorOfClass("Model")
	local Player = character and Players:GetPlayerFromCharacter(character)
	if not Player or not OwnsZone(Player, slot.Zone) then
		return
	end

	slot.Collected = true
	body.CanTouch = false
	slot.Model = nil

	local awardedAmount = TimeSkipRateService.Grant(Player, slot.Seconds)
	Network:FireClient(Player, "Notif", {
		Message = ("⏱ +%s — %ds TIME SKIP!"):format(NumberController.SuffixNumber(awardedAmount), slot.Seconds);
		Type = "Success";
	})

	-- One hierarchy removal replaces 40 individual transparency writes plus a
	-- destroy/reclone cycle. The same server model is reactivated after the delay.
	slot.PooledModel = model
	model.Parent = nil

	task.delay(RESPAWN_TIME, function()
		SpawnSlot(slot)
	end)
end

SpawnSlot = function(slot, keepCurrentZone)
	if not Container or not Container.Parent or slot.Active == false then
		return
	end

	if not keepCurrentZone or not slot.ZonePart then
		local candidates = {}
		for _, zonePart in ipairs(ZoneParts) do
			if zonePart.Name ~= slot.Zone then
				table.insert(candidates, zonePart)
			end
		end

		local zonePart = candidates[math.random(1, #candidates)]
		slot.Zone = zonePart.Name
		slot.ZonePart = zonePart
	end

	slot.Collected = false
	slot.Seconds = math.random(MIN_SKIP_SECONDS, MAX_SKIP_SECONDS)
	local position = RandomGroundPoint(slot.ZonePart)
	local model, body = BuildPickup(slot.Zone, position, slot.Seconds, slot.PooledModel)
	slot.PooledModel = nil
	if slot.Owner then
		model:SetAttribute("PlayerBonusFor", slot.Owner.UserId)
	else
		model:SetAttribute("PlayerBonusFor", nil)
	end
	slot.Model = model
	if not body:GetAttribute("PickupTouchBound") then
		body:SetAttribute("PickupTouchBound", true)
		body.Touched:Connect(function(hit)
			Collect(slot, model, body, hit)
		end)
	end
end
local function AddPlayerSlot(Player)
	if PlayerSlots[Player.UserId] or #ZoneParts == 0 then
		return
	end

	local slot = {
		Owner = Player;
		Active = true;
		Collected = false;
		Index = "Player-" .. Player.UserId;
	}
	PlayerSlots[Player.UserId] = slot
	table.insert(Slots, slot)
	SpawnSlot(slot)
end

local function RemovePlayerSlot(Player)
	local slot = PlayerSlots[Player.UserId]
	if not slot then
		return
	end

	PlayerSlots[Player.UserId] = nil
	slot.Active = false
	if slot.Model then
		slot.Model:Destroy()
		slot.Model = nil
	end
	if slot.PooledModel then
		slot.PooledModel:Destroy()
		slot.PooledModel = nil
	end

	local index = table.find(Slots, slot)
	if index then
		table.remove(Slots, index)
	end
end

function WalkCucumberService.Initialize()
	local oldCucumbers = workspace:FindFirstChild("WalkCucumbers")
	if oldCucumbers then
		oldCucumbers:Destroy()
	end

	Container = workspace:FindFirstChild("TimeSkips")
	if Container then
		Container:Destroy()
	end
	Container = nil

	if not MAP_PICKUPS_ENABLED then
		print("[WalkCucumberService] floating map time skips disabled")
		return
	end

	Container = Instance.new("Folder")
	Container.Name = "TimeSkips"
	Container.Parent = workspace

	table.clear(Slots)
	table.clear(ZoneParts)
	table.clear(PlayerSlots)

	local zonePartsFolder = workspace:WaitForChild("Zones"):WaitForChild("ZoneParts")
	for _, zonePart in ipairs(zonePartsFolder:GetChildren()) do
		if zonePart:IsA("BasePart") and Doors[zonePart.Name] then
			table.insert(ZoneParts, zonePart)
		end
	end

	-- Spread the first five across different areas. Respawns choose a new
	-- random area that is never the area where that pickup was collected.
	for index = #ZoneParts, 2, -1 do
		local swapIndex = math.random(1, index)
		ZoneParts[index], ZoneParts[swapIndex] = ZoneParts[swapIndex], ZoneParts[index]
	end

	for index = 1, math.min(TOTAL_PICKUPS, #ZoneParts) do
		local zonePart = ZoneParts[index]
		local slot = {
			Zone = zonePart.Name;
			ZonePart = zonePart;
			Index = index;
			Active = true;
			Collected = false;
		}
		table.insert(Slots, slot)
		SpawnSlot(slot, true)
	end

	Players.PlayerAdded:Connect(AddPlayerSlot)
	Players.PlayerRemoving:Connect(RemovePlayerSlot)
	for _, Player in ipairs(Players:GetPlayers()) do
		AddPlayerSlot(Player)
	end

	print(("[WalkCucumberService] spawned %d base time skips + 1 per player"):format(TOTAL_PICKUPS))
end

return WalkCucumberService
