--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local ProductController = ControllerLoader.GetController("ProductController")
local FastWait = ControllerLoader.GetController("FastWait")
local ZonePlus = ControllerLoader.GetController("ZonePlus")
local BoostHandler = ServerController.GetModule("BoostHandler")
--..
local Doors = ServerController.GetDictionary("Doors").Stats

--..Variables..--
local Assets = ServerStorage.Assets
local Collectables = Assets.Collectables
--..

local CollectionService = {

    PartData = {};
    ZoneGroups = {};
    PlayerZoneData = {};

}
local PartData = CollectionService.PartData
local ZoneGroups = CollectionService.ZoneGroups
local PlayerZoneData = CollectionService.PlayerZoneData

--..Functions..--

math.randomseed(tick())

local OrbsLimit = 200
local function SpawnPart(Player, Parts, PlayerZone)
	if #Parts:GetChildren() >= OrbsLimit then return end
    local Part = CollectionService.SpawnCollectable(PlayerZone)
    PartData[Player.Name][Part] = true
    Part.Parent = Parts
    if Part:IsA("Model") then else
        Part.Anchored = true
        Part.CanCollide = false
    end
end

function CollectionService.SpawnCollectable(PlayerZone)
    local intersectionVector
    local Zone

    if ZoneGroups[PlayerZone] ~= nil then
        Zone = ZoneGroups[PlayerZone]
    else
        local Group = workspace.Zones[PlayerZone]
        ZoneGroups[PlayerZone] = ZonePlus.new(Group)
        Zone = ZoneGroups[PlayerZone]
    end

    local Attempts = 0
    repeat
        Attempts += 1
        local randomVector, touchingParts = Zone:getRandomPoint()
        local rayOrigin = randomVector + Vector3.new(0, 1, 0)
        local raycastParams = RaycastParams.new()
        raycastParams.FilterDescendantsInstances = touchingParts
        raycastParams.FilterType = Enum.RaycastFilterType.Whitelist
        local raycastResult = workspace:Raycast(rayOrigin, Vector3.new(0, -2, 0), raycastParams)
        intersectionVector = (raycastResult and raycastResult.Position)
        if not intersectionVector and Attempts >= 50 then
            intersectionVector = randomVector
        end
    until intersectionVector

    local Orb = Collectables[PlayerZone]:Clone()
    Orb.CFrame = CFrame.new(intersectionVector + Vector3.new(0, 1, 0))

    Orb.CFrame = Orb.CFrame * CFrame.fromEulerAnglesXYZ(0, math.rad(math.random(-180,180)), 0)

    return Orb
end

function CollectionService.PlayerJoined(Player)
    PartData[Player.Name] = {};
    local PlayerPart = PartData[Player.Name]

    local PlayerGui = Player:FindFirstChild("PlayerGui")
    -- Must be created BY THE SERVER: the StarterGui-cloned "Parts" folder is
    -- client-owned, and server-spawned orbs inside it never replicate down
    local Parts = PlayerGui:FindFirstChild("OrbParts")
    if not Parts then
        Parts = Instance.new("Folder")
        Parts.Name = "OrbParts"
        Parts.Parent = PlayerGui
    end

    PlayerZoneData[Player.Name] = "Spawn" 

    FastWait(3)

    for i=1,50 do
        SpawnPart(Player, Parts, PlayerZoneData[Player.Name])
    end
end

function CollectionService.PlayerLeft(Player)
    local Table = PartData[Player.Name]
    if Table then
        for i,v in next, Table do
            if i and v then
                i:Destroy()
            end
        end
    end

    PartData[Player.Name] = nil
    PlayerZoneData[Player.Name] = nil
end

function CollectionService.CharacterJoined(Character)
    do
        coroutine.wrap(function()
			FastWait(2)
            local Player = Players:GetPlayerFromCharacter(Character)
			local UserData = ProfileService.GetUserData(Player)
			if not UserData then return end
            local Radius = UserData.Stats.Radius*2

            local ClonedCircle = Assets.Circle:Clone()
            ClonedCircle.Parent = Character.HumanoidRootPart
            ClonedCircle.Position = Character.HumanoidRootPart.Position - Vector3.new(0,3,0)
            ClonedCircle.Size = Vector3.new(Radius, .185, Radius)

            ClonedCircle.RegionPart.Size = Vector3.new(Radius, 10, Radius)
            ClonedCircle.RegionPart.CFrame = ClonedCircle.CFrame

            local Weld = Instance.new("WeldConstraint", ClonedCircle.RegionPart)
            Weld.Part0 = ClonedCircle.RegionPart
            Weld.Part1 = ClonedCircle

            local Weld = Instance.new("WeldConstraint", ClonedCircle)
            Weld.Part0 = ClonedCircle
            Weld.Part1 = Character.HumanoidRootPart
        end)()
    end
end

function CollectionService.CheckMagnitude(Player, Orb)
    local UserData = ProfileService.GetUserData(Player)
    local Radius = UserData.Stats.Radius

    local Magnitude = (Player.Character.HumanoidRootPart.Position - Orb.Position).Magnitude

    if Magnitude <= (Radius * 2)+5 then
        return true
    else
        return false
    end
end

function CollectionService.Collect(Player, Orb)
    local PlayerGui = Player:FindFirstChild("PlayerGui")
    local Parts = PlayerGui:WaitForChild("OrbParts")

    if Orb and Orb:IsA("BasePart") then
        if Orb:IsDescendantOf(Parts) and PartData[Player.Name][Orb] ~= nil then
            if CollectionService.CheckMagnitude(Player, Orb) then
                PartData[Player.Name][Orb] = nil -- claim immediately so a second Collect fire can't double-award
                local Zone = PlayerZoneData[Player.Name]

                delay(.1, function()
					local OrbAmount = (Doors[Zone].Orbs.Orb) * Doors[Zone].Orbs.Multi
					CurrencyHandler.AddCurrency({Player = Player; Currency = "Cucumbers"; HasTotal = true; Amount = OrbAmount;})
                end)

                Debris:AddItem(Orb, 3)

                local inc = math.random(1, 20) == 5 and 2 or 1
                for i = 1, inc do
                    SpawnPart(Player, Parts, Zone)
                end
            else
                --Player:Kick("Possible Exploiting.")
            end
        end
    end
end

function CollectionService.ChangedZones(Player, Zone)
	if Player and type(Zone) == "string" then
		if not workspace.Zones:FindFirstChild(Zone) then return end

		--.. only zones the player actually owns (doors bought)
		local UserData = ProfileService.GetUserData(Player)
		if not UserData then return end
		local Owned = false
		for _,OwnedZone in ipairs(string.split(UserData.DoorData, " # ")) do
			if OwnedZone == Zone then Owned = true break end
		end
		if not Owned then return end

		FastWait(.2)
        local PlayerGui = Player:FindFirstChild("PlayerGui")
        local Parts = PlayerGui:WaitForChild("OrbParts")
        local Table = PartData[Player.Name]

        PlayerZoneData[Player.Name] = Zone

        if not Table then PartData[Player.Name] = {} Table = PartData[Player.Name] end
        for i,v in next, Table do
            if i and v then
                i:Destroy()
            end
        end

        PartData[Player.Name] = {};

        for i=1,50 do
            SpawnPart(Player, Parts, Zone)
        end
    end
end

return CollectionService
