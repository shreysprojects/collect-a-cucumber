--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local ProductController = ControllerLoader.GetController("ProductController")
local NumberController = ControllerLoader.GetController("NumberController")
local FastWait = ControllerLoader.GetController("FastWait")
local Network = ControllerLoader.GetController("Network")

local UpgradeStats = ServerController.GetDictionary("Upgrades").Stats

--..Variables..--
local UpgradeService = {}

--..Functions..--
local function ensureUpgradeValue(Player, UserData, ItemName)
    UserData.Upgrades[ItemName] = UserData.Upgrades[ItemName] or 0

    local PlayerData = Player:FindFirstChild("PlayerData")
    local Upgrades = PlayerData and PlayerData:FindFirstChild("Upgrades")
    if not Upgrades then return nil end

    local UpgradeAmount = Upgrades:FindFirstChild(ItemName)
    if not UpgradeAmount then
        UpgradeAmount = Instance.new("IntValue")
        UpgradeAmount.Name = ItemName
        UpgradeAmount.Value = UserData.Upgrades[ItemName]
        UpgradeAmount.Parent = Upgrades
    end

    return UpgradeAmount
end

function UpgradeService.FunctionButton(Player, ItemName)
    do
        if Player and ItemName then
            local UserData = ProfileService.GetUserData(Player)
            if UserData then
                local UpgradesData = UserData.Upgrades
                if UpgradesData then
                    local UpgradeTable = UpgradeStats[ItemName]
                    if not UpgradeTable then return false end

                    local UpgradeAmount = ensureUpgradeValue(Player, UserData, ItemName)
                    local CurrentLevel = UpgradesData[ItemName] or (UpgradeAmount and UpgradeAmount.Value) or 0
                    if CurrentLevel < UpgradeTable.Stats.MaxUpgrade then
                        local Price = NumberController.RoundNumber(UpgradeTable.Stats.Price + (UpgradeTable.Stats.Price * CurrentLevel * UpgradeTable.Stats.Increment), 100)

                        if CurrencyHandler.CheckIfEnough({Player = Player; Currency = "Coins"; Amount = Price}) then
                            Network:FireClient(Player, 'PlaySound', 'Success')

                            CurrencyHandler.RemoveCurrency(Player, "Coins", Price, "Upgrade:" .. tostring(ItemName))
                            ProfileService.AddStatToProfile(Player, ItemName, "Upgrades", 1)
                            if UpgradeAmount then
                                UpgradeAmount.Value += 1
                            end

                            UpgradeTable.Function(Player)

                            return true
                        else
                            Network:FireClient(Player, "Notif", {Message = "NOT ENOUGH COINS!"; Type = "Error";})
                            return false
                        end
                    end
                end
            end
        end
    end
end

function UpgradeService.PlayerJoined(Player)
    do
        FastWait(2)

        if Player then
            local UserData = ProfileService.GetUserData(Player)
            if UserData then
                local UpgradesData = UserData.Upgrades
                if UpgradesData then
                    --.. retired upgrades (2026-08-27): walkspeed (base is a flat 29 now)
                    --.. and hatch speed (FastHatch stays at its default 1). Scrub the
                    --.. legacy keys from saved profiles so no DataStore trace remains,
                    --.. plus the mirrored IntValues the folder build already made.
                    local PlayerData = Player:FindFirstChild("PlayerData")
                    local UpgradesFolder = PlayerData and PlayerData:FindFirstChild("Upgrades")
                    for _, LegacyName in ipairs({"Faster walkspeed", "Hatch speed"}) do
                        UpgradesData[LegacyName] = nil
                        local LegacyValue = UpgradesFolder and UpgradesFolder:FindFirstChild(LegacyName)
                        if LegacyValue then LegacyValue:Destroy() end
                    end

                    for Index, UpgradeTable in next, UpgradeStats do
                        local Value = UpgradesData[Index] or 0
                        local UpgradeAmount = ensureUpgradeValue(Player, UserData, Index)
                        if UpgradeAmount then
                            UpgradeAmount.Value = Value
                        end
                        if Value > 0 then
                            UpgradeTable.Function(Player, Value)
                        end
                    end
                end
            end
        end
    end
end

--.. Re-apply the stacked walkspeed (Sprint/hoverboard/event multipliers) on EVERY respawn.
--..
--.. Player:LoadCharacter() (death, or a rebirth) builds a fresh Humanoid at
--.. StarterPlayer.CharacterWalkSpeed and nothing puts the multipliers back on
--.. its own: without this a Sprint owner would respawn at the base 29 and stay
--.. there until they rejoined.
--..
--.. setWalkSpeed computes an absolute value and assigns it (base 29 doubled/
--.. tripled by Sprint, hoverboard, events), so it is idempotent and cannot stack.
--.. task.spawn because it calls the UNCACHED CheckGamepass, which yields on a
--.. MarketplaceService web request -- CharacterJoinedWithWhitelist runs every
--.. module in one sequential pcall, so blocking here would delay PetService's
--.. pet restore behind a network round trip.
function UpgradeService.CharacterJoined(Character)
	local Player = Players:GetPlayerFromCharacter(Character)
	if not Player then return end

	task.spawn(function()
		local Upgrades = ServerController.GetDictionary("Upgrades")
		if Upgrades and Upgrades.SetWalkSpeed then
			pcall(Upgrades.SetWalkSpeed, Player)
		end
	end)
end

return UpgradeService
