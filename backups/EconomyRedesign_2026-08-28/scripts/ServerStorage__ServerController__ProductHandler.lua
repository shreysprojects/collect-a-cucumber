--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)

local PetService = ServerController.GetModule("PetService")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local GamepassHandler = ServerController.GetModule("GamepassHandler")
local BoostHandler = ServerController.GetModule("BoostHandler")
local ProfileService = ServerController.GetModule("ProfileService")
local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
local NukeService = ServerController.GetModule("NukeService")
local BreakablesService = ServerController.GetModule("BreakablesService")
local PortalUnlockService = require(ServerStorage:WaitForChild("PortalUnlockService"))

local ProductController = ControllerLoader.GetController("ProductController")

--..Variables..--
local purchaseHistoryStore = DataStoreService:GetDataStore("PurchaseHistory")

local module = {

    ProductFunctions = {};

}
local ProductFunctions = module.ProductFunctions

--..Functions..--

function module.Gamepasses()
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(Player, Id, HasPurchased)
        if HasPurchased then
            -- Creator Hub display names can differ from our internal keys (for
            -- example "+75 Pets Storage" vs "+75 Pet Storage"). Resolve by the
            -- purchased pass ID so the correct bonus always applies immediately.
            for Name, Pass in pairs(ProductController.Gamepasses) do
                if Pass.Id == Id then
                    GamepassHandler.CommitGamepass({Player = Player; Name = Name;})
                    break
                end
            end
        end
    end)
end

function module.Products()


    --.. 2x Cucumbers Boost
    do
        coroutine.wrap(function()
            for i,v in next, ProductController.Products.Boosts["2x Cucumbers"] do
                ProductFunctions[v.Id] = function(receipt, Player)

                    BoostHandler.AddBoost(Player, "2x Cucumbers", v.Time)

                    return true
                end
            end
        end)()
    end


    --.. Pets
    do
        coroutine.wrap(function()
            for i,v in next, ProductController.Products.Pets do
                ProductFunctions[v.Id] = function(receipt, Player)

                    PetService.AddPetToPlayer({Player = Player; Pet = v.PetName})

                    return true
                end
            end
        end)()
    end

    --.. Packs
    do
        coroutine.wrap(function()
            for i,v in next, ProductController.Products.Offers.Packs do
                ProductFunctions[v.Id] = function(receipt, Player)
                    local Items = v.Items

                    if Items.Coins ~= nil then
                        CurrencyHandler.AddCurrency({Player = Player; Currency = "Coins"; HasTotal = true; Amount = Items.Coins; WasPurchase = true})
                    end
                    if Items.Pets ~= nil then
                        for _, Pet in next, Items.Pets do
                            PetService.AddPetToPlayer({Player = Player; Pet = Pet})
                        end
                    end

                    --.. burn the one-time Starter Pack offer so its timer never returns
                    if i == "Starter Pack" then
                        local profile = ProfileService.GetUserData(Player)
                        if profile then profile.StarterOfferExpiry = 0 end
                        --.. pairs with StarterPackShown (ServerNetwork) for the conversion rate
                        pcall(function()
                            game:GetService("AnalyticsService"):LogCustomEvent(Player, "StarterPackPurchased", 1)
                        end)
                    end

                    return true
                end
            end
        end)()
	end
	
	--.. Time Skip products: snapshot the unified server farming quote at receipt time.
	--.. WasPurchase grants that already-final amount flat, matching the live shop card without
	--.. applying multipliers twice. Skips Id 0 placeholders until the products exist.
	do
		coroutine.wrap(function()
			for i,v in next, ProductController.Products.TimeSkips do
				if v.Id and v.Id ~= 0 then
					ProductFunctions[v.Id] = function(receipt, Player)
						--.. Snapshot the same authoritative farming quote shown on the card.
						--.. Receipt processing is server-side, and the flat purchase grant avoids re-multiplying.
						local final = TimeSkipRateService.Grant(Player, v.Seconds or v.Amount or 0)
						return true
					end
				end
			end
		end)()
	end

	--.. VAULT Time Skip products (the second skip mechanic): fast-forward the
	--.. coins the buyer's stored vault cucumbers print. Same flat-grant contract
	--.. as the farming skips; Id 0 placeholders are skipped until the dashboard
	--.. products exist (ids live in ProductController.Products.VaultTimeSkips).
	do
		coroutine.wrap(function()
			local VaultTimeSkipService = ServerController.GetModule("VaultTimeSkipService")
			for i,v in next, ProductController.Products.VaultTimeSkips do
				if v.Id and v.Id ~= 0 then
					ProductFunctions[v.Id] = function(receipt, Player)
						VaultTimeSkipService.Grant(Player, v.Seconds or v.Amount or 0)
						return true
					end
				end
			end
		end)()
	end

	--.. Keyed off ProductController rather than a literal id. These two were hardcoded to the
	--.. old kit-owned products, so when those ids were replaced the receipt handlers silently
	--.. kept listening on the dead ids and a real purchase would have granted nothing.
	ProductFunctions[ProductController.Products["+10 Pet Inventory"].Id] = function(receipt, Player)
		-- +10 pet inventory
		Player.PlayerData.Pets.MaxInventory.Value += 10
		ProfileService.SetStatToProfile(Player, "MaxPetInventoryIncrement", nil, ProfileService.GetUserData(Player).MaxPetInventoryIncrement + 10)
		return true
	end
	
	ProductFunctions[ProductController.Products["+2 Pets Equip"].Id] = function(receipt, Player)
		-- Legacy developer-product slots stack with board levels and permanent passes.
		local UserData = ProfileService.GetUserData(Player)
		if not UserData then return false end
		local NewIncrement = math.min((tonumber(UserData.MaxEquipIncrement) or 0) + 2, 6)
		ProfileService.SetStatToProfile(Player, "MaxEquipIncrement", nil, NewIncrement)
		local Upgrades = ServerController.GetDictionary("Upgrades")
		if Upgrades and Upgrades.SetPetEquips then
			Upgrades.SetPetEquips(Player)
		end
		return true
	end

	-- Boss/event requirement skip: only the receipt handler grants the effect.
	-- The biome was server-validated immediately before the purchase prompt.
	ProductFunctions[ProductController.Products["Skip Boss/Event Requirement"].Id] = function(receipt, Player)
		return BreakablesService.GrantRequirementSkip(Player)
	end

	-- Paid portal unlock: the requested portal was validated and persisted before
	-- the purchase prompt, so a retried receipt can safely grant it after a rejoin.
	ProductFunctions[ProductController.Products["Unlock Portal Now!"].Id] = function(receipt, Player)
		return PortalUnlockService.GrantPending(Player)
	end

	-- Nuke Server developer product: queue the cinematic immediately, then grant the
	-- receipt so Roblox never double-delivers the same PurchaseId.
	ProductFunctions[NukeService.ProductId] = function(receipt, Player)
		return NukeService.Launch(Player)
	end
end

function module.Initialize()
    do
        module.Gamepasses()
        module.Products()
    end

    do
        local function processReceipt(receiptInfo)

            local playerProductKey = receiptInfo.PlayerId .. "_" .. receiptInfo.PurchaseId
            local purchased = false
            local success, errorMessage = pcall(function()
                purchased = purchaseHistoryStore:GetAsync(playerProductKey)
            end)
            if success and purchased then
                return Enum.ProductPurchaseDecision.PurchaseGranted
            elseif not success then
                error("Data store error:" .. errorMessage)
            end

            local player = Players:GetPlayerByUserId(receiptInfo.PlayerId, 10)
            if not player then
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            local handler = ProductFunctions[receiptInfo.ProductId]

            local success, result = pcall(handler, receiptInfo, player)
            if not success or not result then
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            local success, errorMessage = pcall(function()
                purchaseHistoryStore:SetAsync(playerProductKey, true)
            end)
            if not success then
                error("Cannot save purchase data: " .. errorMessage)
            end

            return Enum.ProductPurchaseDecision.PurchaseGranted
        end

        MarketplaceService.ProcessReceipt = processReceipt
    end
end

return module
