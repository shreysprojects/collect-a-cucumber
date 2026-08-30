--..Services..--
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
local ServerController = require(ServerStorage.ServerController)

local FastWait = ControllerLoader.GetController("FastWait")
local Network = ControllerLoader.GetController("Network")

--..Variables..--
local ProcessedCharacters = setmetatable({}, {__mode = "k"});
local ResetBusy = setmetatable({}, {__mode = "k"});

local ResetRequest = ReplicatedStorage:FindFirstChild("CharacterResetRequest") or Instance.new("RemoteEvent")
ResetRequest.Name = "CharacterResetRequest"
ResetRequest.Parent = ReplicatedStorage

local BIOMES = {"Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek"}

local function FindCurrentBiome(Player)
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local zones = workspace:FindFirstChild("Zones")
    if root and zones then
        for _, zoneName in ipairs(BIOMES) do
            local folder = zones:FindFirstChild(zoneName)
            if folder then
                for _, part in ipairs(folder:GetChildren()) do
                    if part:IsA("BasePart") then
                        local offset = part.CFrame:PointToObjectSpace(root.Position)
                        if math.abs(offset.X) <= part.Size.X * 0.5
                            and math.abs(offset.Z) <= part.Size.Z * 0.5
                            and math.abs(offset.Y) <= 60 then
                            return zoneName
                        end
                    end
                end
            end
        end
    end
    local sticky = Player:GetAttribute("CurrentBiome")
    return table.find(BIOMES, sticky) and sticky or "Spawn"
end

local function CleanResetCharacter(Player)
    if ResetBusy[Player] or not Player:IsDescendantOf(Players) then return end
    ResetBusy[Player] = true
    local biome = FindCurrentBiome(Player)
    Player:SetAttribute("CurrentBiome", biome)
    Player:SetAttribute("CleanResetInProgress", true)

    local oldCharacter = Player.Character
    local oldHumanoid = oldCharacter and oldCharacter:FindFirstChildOfClass("Humanoid")
    if oldHumanoid then
        oldHumanoid.BreakJointsOnDeath = false
        oldHumanoid.RequiresNeck = false
    end
    -- Destroy the intact model directly; never set Health to zero or break joints.
    if oldCharacter then oldCharacter:Destroy() end

    local ok, err = pcall(function()
        Player:LoadCharacter()
        local character = Player.Character
        if not character or not character.Parent or character == oldCharacter then
            character = Player.CharacterAdded:Wait()
        end
        local root = character:WaitForChild("HumanoidRootPart", 10)
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.BreakJointsOnDeath = false
            humanoid.Health = humanoid.MaxHealth
        end

        -- SpawnArea pads sit safely inside each biome; door locations are on
        -- biome boundaries and can immediately reclassify the player as the prior zone.
        local biomeIndex = table.find(BIOMES, biome)
        local spawnAreas = workspace:FindFirstChild("SpawnArea")
        local location = spawnAreas and biomeIndex and spawnAreas:FindFirstChild(tostring(biomeIndex))
        if not location then
            local locations = workspace:FindFirstChild("Doors")
            locations = locations and locations:FindFirstChild("Locations")
            location = locations and locations:FindFirstChild(biome)
        end
        if root and location then
            pcall(function()
                Player:RequestStreamAroundAsync(location.Position, 3)
            end)
            character:PivotTo(location.CFrame + Vector3.new(0, 3, 0))
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            Player:SetAttribute("CurrentBiome", biome)
            Network:FireClient(Player, "AlignCamera", location.CFrame.LookVector)
        end
    end)
    if not ok then
        warn(("[CleanReset] %s reset failed: %s"):format(Player.Name, tostring(err)))
    end
    if Player:IsDescendantOf(Players) then
        Player:SetAttribute("CleanResetInProgress", nil)
    end
    ResetBusy[Player] = nil
end

ResetRequest.OnServerEvent:Connect(CleanResetCharacter)

--..Functions..--

--.. Initialize
coroutine.wrap(function()
    ServerController.InitializeModulesWithBlacklist({"ProfileService", "CharacterModule", "GamepassHandler", "CollectionService", "PickaxeService", "TeleportService", "UpgradeService"})
end)()

--.. Player Added
local function PlayerAdded(Player)
    do
        coroutine.wrap(function()
            FastWait(.5)
            ServerController.PlayerJoinedWithWhitelist(Player, {"ProfileService", "GamepassHandler", "DoorService", "BoostHandler", "PetService", "ChestHandler", "UpgradeService", "SeasonService", "OfflineService", "PlaytimeRewards", "StreakService", "GoalService", "VaultService", "GroupOfferService", "FavoritePromptService"})
        end)()
    end	
end

--.. PlayerLeft
local function PlayerLeft(Player)
    do
        ServerController.PlayerLeftWithWhitelist(Player, {"ProfileService"})
    end
end

--.. Character Added
local function CharacterAdded(Player, Character)
    do
        if ProcessedCharacters[Character] then
            return
        end
        ProcessedCharacters[Character] = true
        --.. UpgradeService added 2026-08-05: LoadCharacter() builds a fresh Humanoid at
        --.. StarterPlayer's walkspeed, so its CharacterJoined re-applies the stacked
        --.. speed multipliers (Sprint/hoverboard/events) that a death or rebirth
        --.. would otherwise drop for the rest of the session.
        ServerController.CharacterJoinedWithWhitelist(Character, {"CharacterModule", "GamepassHandler", "PickaxeService", "PetService", "SeasonService", "RebirthService", "UpgradeService"})
    end
end

--.. Events
--[[for _, Player in pairs(Players:GetPlayers()) do
	PlayerAdded(Player)

	CharacterAdded(Player.Character or Player.CharacterAdded:Wait())
end]]


Players.PlayerAdded:Connect(function(Player)
    PlayerAdded(Player)

    CharacterAdded(Player, Player.Character or Player.CharacterAdded:Wait())

    Player.CharacterAdded:Connect(function(Character)
        CharacterAdded(Player, Character)
    end)
end)

Players.PlayerRemoving:Connect(function(Player)
    PlayerLeft(Player)
end)

if game:GetService("RunService"):IsStudio() then else
    game:BindToClose(function()
        for _, Player in ipairs(Players:GetPlayers()) do
            PlayerLeft(Player)
        end
    end)
end
