--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
--..
local ProfileService = ServerController.GetModule("ProfileService")
local Network = ControllerLoader.GetController("Network")
--..
local PetStats = ServerController.GetDictionary("Pets").Stats

--..Variables..--
local Assets = ReplicatedStorage.Assets
local Particles = Assets.Particles

local EquipService = {}

--..Functions..--

--.. PET SIZE CAP (2026-08-27): ReplicatedStorage.petsize (a reference Part
--.. placed in Studio) is the bounding cube every equipped pet must fit
--.. inside. A pet whose bounding box exceeds it on ANY axis is uniformly
--.. shrunk (proportions kept) until it fits; smaller pets are untouched.
--.. Resolved per call so resizing the reference part in Studio just works.
local function ApplySizeCap(Pet)
	local cap = ReplicatedStorage:FindFirstChild("petsize")
	if not (cap and cap:IsA("BasePart") and Pet:IsA("Model")) then return end
	local ok, _, size = pcall(Pet.GetBoundingBox, Pet)
	if not ok or not size or size.X <= 0 or size.Y <= 0 or size.Z <= 0 then return end
	local factor = math.min(1, cap.Size.X / size.X, cap.Size.Y / size.Y, cap.Size.Z / size.Z)
	if factor < 1 then
		pcall(Pet.ScaleTo, Pet, Pet:GetScale() * factor)
	end
end

local function Mulitpliers(Player, PetStats, Equipped)
    do
        if Player and PetStats then
            local PlayerData = Player:WaitForChild("PlayerData")
            local Pets = PlayerData:WaitForChild("Pets")
            local Multi1 = Pets.Multi1
            local Multi2 = Pets.Multi2
            local Damage = Pets:FindFirstChild("Damage")

            --.. legacy pets hatched before the Damage stat existed: derive a
            --.. deterministic value from Multi1 so equip/unequip stay symmetric
            local dmg = PetStats.Damage or math.max(1, math.ceil((PetStats.Multi1 or 1) / 2))

            if Equipped then
                Multi1.Value += PetStats.Multi1
                Multi2.Value += PetStats.Multi2
                if Damage then Damage.Value += dmg end
            else
                Multi1.Value -= PetStats.Multi1
                Multi2.Value -= PetStats.Multi2
                if Damage then Damage.Value -= dmg end
            end
        end
    end
end

local function Varients(Player, PetTable, PetModel)
    do
        if Player and PetTable and PetModel then
            if PetTable.Craft == "Golden" then
                for _,v in next, PetModel:GetDescendants() do
                    if v:IsA("BasePart") then
                        if v.Color ~= Color3.fromRGB(17,17,17) then
                            v.Color = Color3.fromRGB(239, 184, 56)
                        end
                    end
                end

                for _,v in next, Particles.Golden:GetChildren() do
                    v:Clone().Parent = PetModel.PrimaryPart
                end
            end
        end
    end
end

local function Error(Player)
    warn("[EquipService]: Error Occured When Equipping Pet For ".. Player.Name)
end

function EquipService.EquipPet(InfoTable, IsEquipBest)
    do
        if InfoTable then
            local Player = InfoTable.Player
            local PetId = InfoTable.PetId
            local OnJoin = InfoTable.OnJoin
            if Player and PetId then

                local PlayerData = Player:WaitForChild("PlayerData", 30)
                local Pets = PlayerData and PlayerData:WaitForChild("Pets", 10)
                local Equipped = Pets and Pets:WaitForChild("Equipped", 10)
                local MaxEquipped = Pets and Pets:WaitForChild("MaxEquipped", 10)
                local Inventory = Pets and Pets:WaitForChild("Inventory", 10)
                local MaxInventory = Pets and Pets:WaitForChild("MaxInventory", 10)
                if not (Equipped and MaxEquipped and Inventory and MaxInventory) then
                    warn("[EquipService] PlayerData was unavailable for", Player.Name)
                    return false
                end

                local UserData = ProfileService.GetUserData(Player)
                if UserData then
                    local PetData = UserData.PetData
                    if PetData then
                        if PetData[PetId] == nil then return false end

                        if PetData[PetId].Equipped and OnJoin == nil then
                            local PetTable = PetData[PetId]
                            if PetTable then
                                local SpecificPetStats = PetStats[PetTable.Name]
                                if SpecificPetStats then
                                    local Character = Player.Character
                                    local PetsFolder = Character and Character:FindFirstChild("Pets")
                                    local Pet
                                    if PetsFolder then
                                        for _,v in next, PetsFolder:GetChildren() do
                                            if v:IsA("Model") then
                                                local Id = v:FindFirstChild("PetId")
                                                if Id and Id.Value == PetId then
                                                    Pet = v
                                                    break
                                                end
                                            end
                                        end
                                    end
                                    --.. The model can be legitimately gone: it lives in
                                    --.. Character.Pets, so it died with the character. The DATA
                                    --.. still says equipped, so unequip must always do its
                                    --.. bookkeeping -- returning false here used to leave
                                    --.. Equipped stuck true with no way to toggle until rejoin.
                                    PetTable.Equipped = false;
                                    if Pet then Pet:Destroy() end

                                    Equipped.Value -= 1
                                    Mulitpliers(Player, PetTable.Stats, false)

                                    return "Unequipped"
                                end
                            end
                        else
                            if Equipped.Value + 1 <= math.min(MaxEquipped.Value, 10) then else
                                if IsEquipBest == nil then
                                    Network:FireClient(Player, "Notif", {Message = "MAX PETS EQUIPPED"; Type = "Error";})
                                end
                                return false end

                            local PetTable = PetData[PetId]
                            if PetTable then
                                local SpecificPetStats = PetStats[PetTable.Name]
                                if SpecificPetStats and SpecificPetStats.Model then
                                    local Character = Player.Character
                                    local CharacterRoot = Character and Character:FindFirstChild("HumanoidRootPart")
                                    local PetsFolder = Character and Character:FindFirstChild("Pets")
                                    if not (CharacterRoot and PetsFolder) then
                                        warn("[EquipService] Character or Pets folder unavailable for", Player.Name)
                                        return false
                                    end

                                    local Pet = SpecificPetStats.Model:Clone()
                                    ApplySizeCap(Pet)
                                    Pet.Parent = PetsFolder
                                    Pet:PivotTo(CharacterRoot.CFrame)

                                    local Id = Instance.new("StringValue", Pet)
                                    Id.Name = "PetId"
                                    Id.Value = PetId

                                    if Pet.Parent ~= nil then
                                        PetTable.Equipped = true;

                                        for _,v in next, Pet:GetDescendants() do
                                            if v:IsA("BasePart") then
                                                v:SetNetworkOwner(Player)
                                            end
                                        end

                                        Equipped.Value += 1
                                        Mulitpliers(Player, PetTable.Stats, true)
                                        Varients(Player, PetTable, Pet)

                                        return "Equipped"
                                    end
                                end
                            else
                                Error(Player)
                            end
                        end
                    end
                end
            end
        end
    end
end

--.. Death/respawn: pet models live in Character.Pets, so they are destroyed
--.. with the character -- but the save (PetTable.Equipped), Equipped.Value and
--.. the Multi1/Multi2/Damage stats all live on the Player and survive. So on
--.. every respawn we re-clone ONLY the missing models and never touch the
--.. stats (re-applying them here would double-count every equipped pet).
--.. Gated on EquippedPetsLoaded so the join-time OnJoin equip pass in
--.. PetService.PlayerJoined stays the single owner of the FIRST spawn.
function EquipService.RestoreEquippedPets(Player, Character)
    if Player:GetAttribute("EquippedPetsLoaded") ~= true then return end
    Character = Character or Player.Character
    if not Character then return end

    local UserData = ProfileService.GetUserData(Player)
    local PetData = UserData and UserData.PetData
    if not PetData then return end

    local PetsFolder = Character:FindFirstChild("Pets") or Character:WaitForChild("Pets", 10)
    --.. bail if the player died again while we waited; the newer spawn's
    --.. CharacterJoined runs its own restore
    if not PetsFolder or Player.Character ~= Character then return end

    --.. clones sit at the TEMPLATE's authored CFrame until repositioned, and
    --.. CharacterJoined can run before the character has a PrimaryPart -- a
    --.. nil-guarded reposition here silently left the whole swarm ~100 studs
    --.. away walking home after every respawn. Wait for the root first.
    local Root = Character.PrimaryPart or Character:WaitForChild("HumanoidRootPart", 10)
    if Player.Character ~= Character then return end

    local Existing = {}
    for _,v in next, PetsFolder:GetChildren() do
        if v:IsA("Model") then
            local Id = v:FindFirstChild("PetId")
            if Id then Existing[Id.Value] = true end
        end
    end

    for PetId, PetTable in next, PetData do
        if PetId ~= "Unlocked" and type(PetTable) == "table" and PetTable.Equipped and not Existing[PetId] then
            local SpecificPetStats = PetStats[PetTable.Name]
            if SpecificPetStats then
                local Pet = SpecificPetStats.Model:Clone()
                ApplySizeCap(Pet)

                local Id = Instance.new("StringValue")
                Id.Name = "PetId"
                Id.Value = PetId
                Id.Parent = Pet

                Pet.Parent = PetsFolder
                if Root then
                    Pet:PivotTo(Root.CFrame)
                end

                for _,v in next, Pet:GetDescendants() do
                    if v:IsA("BasePart") then
                        pcall(v.SetNetworkOwner, v, Player)
                    end
                end

                Varients(Player, PetTable, Pet)
            end
        end
    end
end

return EquipService
