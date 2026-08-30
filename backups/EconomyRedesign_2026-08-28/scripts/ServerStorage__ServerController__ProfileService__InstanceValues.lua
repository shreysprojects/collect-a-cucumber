--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local NumberController = ControllerLoader.GetController("NumberController")

--..Variables..--


local module = {}

--..Functions..--

function module.SetValues(Player, UserData)
    local Success, Result = pcall(function()

        do

            local leaderstats = Instance.new("Folder")
            leaderstats.Name = "leaderstats"

            local PlayerData = Instance.new("Folder")
            PlayerData.Name = "PlayerData"
            PlayerData.Parent = Player

            local Rebirths = Instance.new("NumberValue")
            Rebirths.Name = "Rebirths"
            Rebirths.Parent = leaderstats
            Rebirths.Value = UserData.Rebirths or 0

            local Coins = Instance.new("NumberValue")
            Coins.Name = "Coins"
            Coins.Parent = leaderstats
            Coins.Value = UserData.Stats.Coins

            local Orbs = Instance.new("NumberValue")
            Orbs.Name = "Cukes"
            Orbs.Parent = leaderstats
            Orbs.Value = UserData.Stats.Cucumbers

            leaderstats.Parent = Player

            --.. leaderstats is the SOURCE OF TRUTH for displayed stats: whenever a
            --.. visible stat changes, mirror it straight into the saved profile.
            Orbs.Changed:Connect(function()
                UserData.Stats.Cucumbers = Orbs.Value
            end)
            Coins.Changed:Connect(function()
                UserData.Stats.Coins = Coins.Value
            end)
            Rebirths.Changed:Connect(function()
                UserData.Rebirths = Rebirths.Value
            end)

            local DoneTutorial = Instance.new("BoolValue")
            DoneTutorial.Name = "DoneTutorial"
            DoneTutorial.Parent = PlayerData
            DoneTutorial.Value = UserData.Stats.DoneTutorial

            local Scale = Instance.new("NumberValue")
            Scale.Name = "Scale"
            Scale.Parent = PlayerData
            Scale.Value = UserData.Stats.Scale

            local Doors = Instance.new("Configuration")
            Doors.Parent = PlayerData
            Doors.Name = "Doors"

            local DoorsOwned = Instance.new("StringValue")
            DoorsOwned.Parent = Doors
            DoorsOwned.Name = "OwnedString"
			DoorsOwned.Value = UserData.DoorData
			
			local FastHatch = Instance.new('NumberValue')
			FastHatch.Parent = PlayerData
			FastHatch.Value = 1
			FastHatch.Name = 'FastHatch'

			--.. live farm target (set by BreakablesService); clients read it to
			--.. swarm the owner's pets around whatever is being auto-collected
			local AutoTarget = Instance.new('ObjectValue')
			AutoTarget.Parent = PlayerData
			AutoTarget.Name = 'AutoTarget'

            --..
            do
                local Pickaxes = Instance.new("Configuration")
                Pickaxes.Parent = PlayerData
                Pickaxes.Name = "Pickaxes"

                local PickaxesOwned = Instance.new("StringValue")
                PickaxesOwned.Parent = Pickaxes
                PickaxesOwned.Name = "Owned"
                PickaxesOwned.Value = UserData.ToolData.Owned

                local PickaxesEquipped = Instance.new("StringValue")
                PickaxesEquipped.Parent = Pickaxes
                PickaxesEquipped.Name = "Equipped"
                PickaxesEquipped.Value = UserData.ToolData.Equipped

                local BuyAmount = Instance.new("IntValue")
                BuyAmount.Parent = Pickaxes
                BuyAmount.Name = "BuyAmount"
                BuyAmount.Value = UserData.ToolData.BuyAmount
            end

            --..
            do
                local Pets = Instance.new("Configuration")
                Pets.Parent = PlayerData
                Pets.Name = "Pets"

                local Equipped = Instance.new("IntValue")
                Equipped.Parent = Pets
                Equipped.Name = "Equipped"
                Equipped.Value = 0

                local MaxEquipped = Instance.new("IntValue")
                MaxEquipped.Parent = Pets
                MaxEquipped.Name = "MaxEquipped"
				MaxEquipped.Value = 4
					+ (tonumber(UserData.MaxEquipIncrement) or 0)
					+ math.clamp(tonumber(UserData.Upgrades and UserData.Upgrades["Pet equips"]) or 0, 0, 6)

                local Inventory = Instance.new("IntValue")
                Inventory.Parent = Pets
                Inventory.Name = "Inventory"
                Inventory.Value = 0

                local MaxInventory = Instance.new("IntValue")
                MaxInventory.Parent = Pets
                MaxInventory.Name = "MaxInventory"
				MaxInventory.Value = 30 + UserData.MaxPetInventoryIncrement

                local Unlocked = Instance.new("StringValue")
                Unlocked.Name = "Unlocked"
                Unlocked.Value = UserData.PetData.Unlocked
                Unlocked.Parent = Pets

                local Multi1 = Instance.new("NumberValue")
                Multi1.Name = "Multi1"
                Multi1.Value = 1;
                Multi1.Parent = Pets

                local Multi2 = Instance.new("NumberValue")
                Multi2.Name = "Multi2"
                Multi2.Value = 1;
                Multi2.Parent = Pets

                --.. summed damage of equipped pets (EquipService maintains it)
                local Damage = Instance.new("NumberValue")
                Damage.Name = "Damage"
                Damage.Value = 0;
                Damage.Parent = Pets
            end

            --..
            do
                local Upgrades = Instance.new("Configuration")
                Upgrades.Name = "Upgrades"
                Upgrades.Parent = PlayerData

                for Index, Value in next, UserData.Upgrades do
                    if Index ~= "Owned" then
                        local IntValue = Instance.new("IntValue")
                        IntValue.Name = Index
                        IntValue.Value = Value
                        IntValue.Parent = Upgrades
                    end
                end
            end
        end

    end)
end

return module
