--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local Network = ControllerLoader.GetController("Network")

local PickaxeStats = ServerController.GetDictionary("Pickaxes").Stats

--..Variables..--
local Tools = ReplicatedStorage.Assets.Pickaxes
local Busy = {}

local PickaxeService = {
    PartData = {};
}

--..Functions..--
local function OwnsPickaxe(OwnedString, ItemName)
    if type(OwnedString) ~= "string" or type(ItemName) ~= "string" then
        return false
    end
    local Haystack = " # " .. OwnedString .. " # "
    return string.find(Haystack, " # " .. ItemName .. " # ", 1, true) ~= nil
end

local function ClearWeapon(Player, Character)
    Character = Character or (Player and Player.Character)
    if not Character then return end
    --.. Pickaxes are Tools now: an unequipped one sits in the Backpack (the
    --.. Humanoid auto-swaps it there when another Tool equips), so sweep both.
    local Backpack = Player and Player:FindFirstChildOfClass("Backpack")
    for _, Container in ipairs({Character, Backpack}) do
        if Container then
            for _, Object in ipairs(Container:GetChildren()) do
                if PickaxeStats[Object.Name] ~= nil then
                    Object:Destroy()
                end
            end
        end
    end
end

local function UpdateRange(Character, Range)
    local Root = Character and Character:FindFirstChild("HumanoidRootPart")
    local Circle = Root and Root:FindFirstChild("Circle")
    if not Circle then return end

    Circle.Size = Vector3.new(Range * 2, Circle.Size.Y, Range * 2)
    local RegionPart = Circle:FindFirstChild("RegionPart")
    if RegionPart then
        RegionPart.Size = Vector3.new(Range * 2, RegionPart.Size.Y, Range * 2)
    end
end

local function EquipOnCurrentCharacter(Player, ItemName, ItemTable)
    local Character = Player.Character
    if not Character or not Character.Parent then return false end
    if not Character:FindFirstChild("RightHand") then return false end

    local Source = Tools:FindFirstChild(ItemName)
    if not Source or Player.Character ~= Character then return false end

    ClearWeapon(Player, Character)
    if Player.Character ~= Character or not Character.Parent then return false end

    local Tool = Source:Clone()
    local Success, Error = pcall(ItemTable.EquipFunction, Tool, Character)
    if not Success then
        Tool:Destroy()
        warn("[PickaxeService] Equip failed for " .. Player.Name .. ": " .. tostring(Error))
        return false
    end

    UpdateRange(Character, ItemTable.Stats.Range)
    return true
end

function PickaxeService.FunctionButton(Player, InfoTable)
    if not Player or type(InfoTable) ~= "table" then return false end
    if InfoTable.Function ~= "Purchase" then return false end

    local ItemName = InfoTable.ItemName
    if type(ItemName) ~= "string" or Busy[Player] then return false end

    Busy[Player] = true
    local Success, Result = xpcall(function()
        local UserData = ProfileService.GetUserData(Player)
        local ItemTable = PickaxeStats[ItemName]
        local ToolData = UserData and UserData.ToolData
        if not UserData or not ToolData or not ItemTable then return false end

        local PlayerData = Player:FindFirstChild("PlayerData")
        local Pickaxes = PlayerData and PlayerData:FindFirstChild("Pickaxes")
        local OwnedValue = Pickaxes and Pickaxes:FindFirstChild("Owned")
        local EquippedValue = Pickaxes and Pickaxes:FindFirstChild("Equipped")
        local BuyAmountValue = Pickaxes and Pickaxes:FindFirstChild("BuyAmount")
        if not OwnedValue or not EquippedValue or not BuyAmountValue then return false end

        local IsOwned = OwnsPickaxe(ToolData.Owned, ItemName)
        if IsOwned and ToolData.Equipped == ItemName then
            return true
        end

        if not IsOwned then
            -- Only the next progression slot (or an earlier valid slot) may be bought.
            if ItemTable.Order > BuyAmountValue.Value then
                return false
            end

            local Price = ItemTable.Stats.Price
            if not CurrencyHandler.CheckIfEnough({
                Player = Player;
                Currency = "Coins";
                Amount = Price;
            }) then
                Network:FireClient(Player, "Notif", {
                    Message = "NOT ENOUGH COINS!";
                    Type = "Error";
                })
                return false
            end

            CurrencyHandler.RemoveCurrency(Player, "Coins", Price, "Pickaxe:" .. ItemName)
            local NewOwned = ToolData.Owned .. " # " .. ItemName
            ProfileService.SetStatToProfile(Player, "Owned", "ToolData", NewOwned)
            ProfileService.AddStatToProfile(Player, "BuyAmount", "ToolData", 1)
            OwnedValue.Value = NewOwned
            BuyAmountValue.Value += 1
        end

        ProfileService.SetStatToProfile(Player, "Radius", "Stats", ItemTable.Stats.Range)
        ProfileService.SetStatToProfile(Player, "Equipped", "ToolData", ItemName)
        EquippedValue.Value = ItemName

        -- Saved/replicated state is authoritative. If the character disappears
        -- during the request, CharacterJoined equips the saved pickaxe on respawn.
        EquipOnCurrentCharacter(Player, ItemName, ItemTable)
        Network:FireClient(Player, "PlaySound", "Success")
        return true
    end, debug.traceback)

    Busy[Player] = nil
    if not Success then
        warn("[PickaxeService] Purchase/equip failed: " .. tostring(Result))
        return false
    end
    return Result == true
end

function PickaxeService.CharacterJoined(Character)
    local Player = Players:GetPlayerFromCharacter(Character)
    if not Player then return end

    ProfileService.GetUserDataPromise(Player):andThen(function(UserData)
        if Player.Character ~= Character or not Character.Parent then return end
        if Player:GetAttribute("InDesertHunt") then return end
        local ToolData = UserData and UserData.ToolData
        if not ToolData then return end
        local ItemName = ToolData.Equipped
        local ItemTable = ItemName and PickaxeStats[ItemName]

        --.. Self-heal a ToolData whose Equipped is unknown or not present in Owned.
        --.. This used to be repaired implicitly: RebirthService force-wrote
        --.. Equipped = Owned = "Pickaxe" on every rebirth. Rebirth now keeps pickaxes
        --.. (2026-08-05), so this is the ONLY repair path left -- without it a profile
        --.. in that state would spawn the player empty-handed on every single respawn,
        --.. silently and forever, since the old code just returned.
        if not ItemTable or not OwnsPickaxe(ToolData.Owned, ItemName) then
            warn(("[PickaxeService] ToolData desync for %s (equipped %q not in %q) - falling back to the starter pickaxe")
                :format(Player.Name, tostring(ItemName), tostring(ToolData.Owned)))

            ItemName = "Wood Pickaxe"
            ItemTable = PickaxeStats[ItemName]
            if not ItemTable then return end

            local pd = Player:FindFirstChild("PlayerData")
            local pickaxes = pd and pd:FindFirstChild("Pickaxes")

            if not OwnsPickaxe(ToolData.Owned, ItemName) then
                ProfileService.SetStatToProfile(Player, "Owned", "ToolData", ItemName)
                if pickaxes and pickaxes:FindFirstChild("Owned") then pickaxes.Owned.Value = ItemName end
            end
            ProfileService.SetStatToProfile(Player, "Equipped", "ToolData", ItemName)
            if pickaxes and pickaxes:FindFirstChild("Equipped") then pickaxes.Equipped.Value = ItemName end
        end

        EquipOnCurrentCharacter(Player, ItemName, ItemTable)
    end):catch(warn)
end

Players.PlayerRemoving:Connect(function(Player)
    Busy[Player] = nil
end)

return PickaxeService
