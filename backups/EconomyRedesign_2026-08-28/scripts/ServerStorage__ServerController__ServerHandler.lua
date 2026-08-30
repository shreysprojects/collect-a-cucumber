--..Services..--
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)

local Network = ControllerLoader.GetController("Network")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local FastWait = ControllerLoader.GetController("FastWait")

--..Variables..--
local Sell = Workspace.Points.Sell
--.. The old walk-over Shop pad (Workspace.Points.Shop) was replaced by the
--.. Shopkeeper NPC at Workspace.ShopNew (see ServerScriptService.ShopVendorServer)
local Evolving = Workspace.Points.Evolving

local module = {

    Debounce = {};

}
local Debounce = module.Debounce

--..Functions..--

--.. Returns a spot Distance studs in front of a vendor NPC, at his feet, facing him
local function FrontOfVendor(Vendor, Distance)
    local Pivot = Vendor:GetPivot()
    local Look = Vector3.new(Pivot.LookVector.X, 0, Pivot.LookVector.Z).Unit
    local Target = Pivot.Position + Look * Distance + Vector3.new(0,1,0)
    return CFrame.lookAt(Target, Vector3.new(Pivot.Position.X, Target.Y, Pivot.Position.Z))
end

function module.TeleportToSell(Player)
    --.. Land in front of the cucumber vendor's booth (booth counter reaches ~6 studs out)
    local Character = Player.Character

    if Character then
        local Target = FrontOfVendor(Sell.Vendor, 8)
        Network:FireClient(Player, "AlignCamera", Target.LookVector) -- camera turns first, then the move lands
        Character:PivotTo(Target)
    end
end

function module.TeleportToShop(Player)
    --.. Land in front of the pickaxe shop booth (booth structure reaches ~10 studs out)
    local Character = Player.Character

    if Character then
        local Target = FrontOfVendor(Workspace.ShopNew.Vendor, 12)
        Network:FireClient(Player, "AlignCamera", Target.LookVector) -- camera turns first, then the move lands
        Character:PivotTo(Target)
    end
end

function module.Initialize()

    if game.ServerStorage:FindFirstChild'Zones' then
        game.ServerStorage.Zones.Parent = Workspace
    end

    --.. Walk-over selling replaced by the vendor NPC (see ServerScriptService.SellVendorServer)

    coroutine.wrap(function()
        local HitParts = {
            [Evolving.PrimaryPart] = {20, 'Evolving'}
        }

		local UserHasUIOpen = {}
		while true do
			for _, v in ipairs(game.Players:GetPlayers()) do
				pcall(function()
					--if v.Character and v.Character:FindFirstChild'Humanoid' then
					local Character = v.Character
					local Root = Character and Character:FindFirstChild("HumanoidRootPart")
					if not Root then return end
					for k, c in pairs(HitParts) do
						if (Root.Position-k.Position).Magnitude < c[1] then
							Network:FireClient(v, "TriggerFrame", c[2], nil, nil, {true})
							UserHasUIOpen[v] = c[2]
						elseif UserHasUIOpen[v] and UserHasUIOpen[v] == c[2] then
							Network:FireClient(v, "TriggerFrame", UserHasUIOpen[v], nil, nil, {false})
							UserHasUIOpen[v] = nil
						end
					end
					--end
				end)
			end
			task.wait(.05)
		end
    end)()

	--[[
	Shop.PrimaryPart.Touched:Connect(function(hit)
		if hit.Parent:FindFirstChild("Humanoid") then
			local Player = Players:GetPlayerFromCharacter(hit.Parent)
			--if Debounce[Player] == nil then
				Debounce[Player] = tick()

				Network:FireClient(Player, "TriggerFrame", "Shop", nil, true)
				
				--FastWait(1)
				--Debounce[Player] = nil
			--end
		end
	end)
	
	Shop.PrimaryPart.TouchEnded:Connect(function(hit)
		if hit.Parent:FindFirstChild("Humanoid") then
			local Player = Players:GetPlayerFromCharacter(hit.Parent)
			if Debounce[Player] and tick()-Debounce[Player] >= .2 then
				Network:FireClient(Player, "TriggerFrame", "Shop", nil, nil, true)
				Debounce[Player] = nil
			end
		end
	end)
	
	Evolving.PrimaryPart.Touched:Connect(function(hit)
		if hit.Parent:FindFirstChild("Humanoid") then
			local Player = Players:GetPlayerFromCharacter(hit.Parent)

			if Debounce[Player] == nil then
				Debounce[Player] = true

				Network:FireClient(Player, "TriggerFrame", "Evolving", nil, true)

				FastWait(1)
				Debounce[Player] = nil
			end
		end
	end)
	]]
end

return module
