--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local BoostHandler = ServerController.GetModule("BoostHandler")
local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")
local ProductController = ControllerLoader.GetController("ProductController")
local NumberController = ControllerLoader.GetController("NumberController")

--..Variables..--


local CurrencyHandler = {}

--.. Cucumbers are DISPLAYED as "Cukes" in leaderstats (renamed 2026-07-30), but the
--.. currency id and the saved-data key both stay "Cucumbers" so no player balance is
--.. lost. This maps a currency id to the visible leaderstat instance name for lookups.
local STAT_NAME = { Cucumbers = "Cukes" }
local function statInstanceName(Currency)
	return STAT_NAME[Currency] or Currency
end

--..Functions..--

--.. Economy dashboard source aggregation (2026-08-23): see AddCurrency. One event
--.. per player+currency per minute keeps us far inside the analytics rate limits.
CurrencyHandler.PendingSource = {}
task.spawn(function()
    local Players = game:GetService("Players")
    local AnalyticsService = game:GetService("AnalyticsService")
    local function flush(plr)
        local bucket = CurrencyHandler.PendingSource[plr]
        if not bucket then return end
        CurrencyHandler.PendingSource[plr] = nil
        if plr.Parent ~= Players then return end
        for currency, amt in pairs(bucket) do
            if amt > 0 then
                pcall(function()
                    local ls = plr:FindFirstChild("leaderstats")
                    local statName = currency == "Cucumbers" and "Cukes" or currency
                    local v = ls and ls:FindFirstChild(statName)
                    local balance = v and math.max(0, math.floor(v.Value)) or 0
                    AnalyticsService:LogEconomyEvent(plr,
                        Enum.AnalyticsEconomyFlowType.Source, currency,
                        math.floor(amt), balance, "Gameplay")
                end)
            end
        end
    end
    Players.PlayerRemoving:Connect(flush)
    while true do
        task.wait(60)
        for plr in pairs(CurrencyHandler.PendingSource) do
            flush(plr)
        end
    end
end)

function CurrencyHandler.GetMulipliers(InfoTable)
    local Player = InfoTable.Player
    local Currency = InfoTable.Currency
    local Amount = InfoTable.Amount
    local WasPurchase = InfoTable.WasPurchase

    if WasPurchase or InfoTable.MultipliersApplied then return Amount end

    --.. rebirth boosts ONLY the farm loop: cucumbers from breaks and coins
    --.. from selling (applied inside those branches below)
    local RebirthService = ServerController.GetModule("RebirthService")
    local rebirthMult = (RebirthService and RebirthService.Multiplier(Player)) or 1

    if Currency == "Cucumbers" then
        Amount *= rebirthMult
        if ProductController.CheckGamepassCached(Player, "2x Cucumbers") then
            Amount *= 2
        end
        Amount *= Player.PlayerData.Pets.Multi1.Value
        if BoostHandler.ValidateBoosts(Player, "2x Cucumbers") then
            Amount *= 2
        end
        --.. GROUP FRENZY members earn +50% cucumbers FOREVER, for free.
        --.. membership is cached to an attribute on join (single IsInGroup call)
        --.. so this hot path never yields -- see GroupOfferService / ChestHandler
        if Player:GetAttribute("InGroupFrenzy") then
            Amount *= 1.5
        end
    elseif Currency == "Coins" then
        Amount *= rebirthMult
        --.. NO rank multiplier and NO pet multi here: the cucumber balance
        --.. already carries both, so stacking them again at the vendor made
        --.. selling wildly overpowered. Rebirth is THE sell-value lever.
        --.. (Pets' coin stat still boosts DIRECT coin drops in Break().)
    end

    return NumberController.RoundNumber(Amount, 1)
end 

function CurrencyHandler.AddCurrency(InfoTable)
    local Player = InfoTable.Player
    local Currency = InfoTable.Currency
    local HasTotal = InfoTable.HasTotal
    local Amount = InfoTable.Amount
    local WasPurchase = InfoTable.WasPurchase

    Amount = CurrencyHandler.GetMulipliers(InfoTable)

    do
        if Player then
            local leaderstats = Player:FindFirstChild("leaderstats")
            local PlayerData = Player:FindFirstChild("PlayerData")

            if leaderstats and PlayerData then
                if Currency == "Cucumbers" then
                    do
                        local Orbs = leaderstats:FindFirstChild("Cukes")
                        if Orbs then
                            Orbs.Value += Amount
                        end
                    end
                elseif Currency == "Coins" then
                    do
                        local Coins = leaderstats:FindFirstChild("Coins")
                        if Coins then
                            Coins.Value += Amount
                        end
                    end
                end

                do
                    --.. balance is persisted via the leaderstats->profile mirror (see InstanceValues);
                    --.. the += to leaderstats above already updated the saved profile.

                    if not WasPurchase then
                        local SeasonService = ServerController.GetModule("SeasonService")
                        if SeasonService then
                            SeasonService.AddSeasonStat(Player, Currency, Amount)
                        end
                        local OfflineService = ServerController.GetModule("OfflineService")
                        if OfflineService then
                            OfflineService.NoteEarnings(Player, Currency, Amount)
                        end
                        --.. VaultService.Skim doesn't exist yet (currency-skim/robbery draft; the module
                        --.. only stores carried cucumbers) -- guard on the function or every break errors
                        --.. here and skips Indicate + telemetry + TotalStats below.
                        local VaultService = ServerController.GetModule("VaultService")
                        if VaultService and VaultService.Skim then
                            VaultService.Skim(Player, Currency, Amount)
                        end
                    end

					if Amount > 0 and not InfoTable.Hide then
                        Network:FireClient(Player, "Indicate", {Currency = Currency; Amount = Amount})
                    end

                    --.. Economy dashboard SOURCE (2026-08-23): income is high-frequency (every
                    --.. break), so it accumulates here and a once-a-minute flusher (bottom of
                    --.. this module) sends ONE aggregated Gameplay event per player+currency.
                    if Amount > 0 then
                        local bucket = CurrencyHandler.PendingSource[Player]
                        if not bucket then bucket = {} CurrencyHandler.PendingSource[Player] = bucket end
                        bucket[Currency] = (bucket[Currency] or 0) + Amount
                    end

                    if HasTotal then
                        ProfileService.AddStatToProfile(Player, "Total"..Currency, "TotalStats", Amount)
                    end
                end
            end
        end
    end
    return Amount
end

function CurrencyHandler.RemoveCurrency(Player, Currency, Amount, Sku)
    do
        local leaderstats = Player.leaderstats
        local Value = leaderstats and leaderstats:FindFirstChild(statInstanceName(Currency))

        if Value then
            Value.Value -= Amount
        else
            local UserData = ProfileService.GetUserData(Player)
            if UserData and UserData.Stats[Currency] ~= nil then
                UserData.Stats[Currency] -= Amount
            end
        end

        --.. visible stats persist through InstanceValues; hidden currencies update profile directly.

        --.. Economy dashboard SINK (2026-08-23): spends are low-frequency (purchases
        --.. only), so each logs discretely with the item Sku the caller passes.
        pcall(function()
            local balance = Value and math.max(0, math.floor(Value.Value)) or 0
            game:GetService("AnalyticsService"):LogEconomyEvent(Player,
                Enum.AnalyticsEconomyFlowType.Sink, Currency,
                math.floor(Amount), balance, "Shop", Sku or "Unknown")
        end)
    end
end

function CurrencyHandler.SetCurrency(InfoTable)
    local Player = InfoTable.Player
    local Currency = InfoTable.Currency
    local Amount = InfoTable.Amount

    do
        if Player then
            local leaderstats = Player:FindFirstChild("leaderstats")

            if leaderstats then
                --.. visible stats mirror through InstanceValues; hidden currencies update profile directly.
                local Value = leaderstats:FindFirstChild(statInstanceName(Currency))
                if Value then
                    Value.Value = Amount
                else
                    local UserData = ProfileService.GetUserData(Player)
                    if UserData and UserData.Stats[Currency] ~= nil then
                        UserData.Stats[Currency] = Amount
                    end
                end
            end
        end
    end
end

function CurrencyHandler.CheckIfEnough(InfoTable)
    local Player = InfoTable.Player
    local Currency = InfoTable.Currency
    local Amount = InfoTable.Amount

    --.. leaderstats is the source of truth for currency (the number the player sees).
    local leaderstats = Player and Player:FindFirstChild("leaderstats")
    local Value = leaderstats and leaderstats:FindFirstChild(statInstanceName(Currency))
    if Value then
        return Value.Value >= Amount
    end

    --.. fallback (leaderstats not built yet): the saved profile mirrors leaderstats anyway.
    local UserData = ProfileService.GetUserData(Player)
    if UserData and UserData.Stats[Currency] then
        return UserData.Stats[Currency] >= Amount
    end
    return false
end

function CurrencyHandler.Initialize()
    while true do
        wait(1)
        for _,Player in next, Players:GetPlayers() do
            ProfileService.AddStatToProfile(Player, "TotalTime", "TotalStats", 1)
        end
    end
end

--[[function module.GetCurrencyWithMultipliers(Player, Currency, Amount, WasPurchase)
	if WasPurchase then return Amount end
	
	local PlayerData = Player.PlayerData
	
	return NumberController.RoundNumber(Amount, 1)
end

function module.AddCurrency(Player, Currency, Amount, WasPurchase, IsGolden, Blackhole)
	do
		local PlayerData = Player.PlayerData
		
		Amount = module.GetCurrencyWithMultipliers(Player, Currency, Amount, WasPurchase)

		if PlayerData:FindFirstChild(Currency) then
			PlayerData:FindFirstChild(Currency).Value += Amount
		end
		if Blackhole ~= true then
			ReplicatedStorage.Events.Indicate:FireClient(Player, Currency, Amount, IsGolden)
		end
		
		ProfileService:AddStatToProfile(Player, Currency, "Stats", Amount)
		ProfileService:AddStatToProfile(Player, "Total"..Currency, "TotalStats", Amount)
	end
end

function module.RemoveCurrency(Player, Currency, Amount)
	do
		local PlayerData = Player.PlayerData

		if PlayerData:FindFirstChild(Currency) then
			PlayerData:FindFirstChild(Currency).Value -= Amount
		end

		ProfileService:RemoveStatFromProfile(Player, Currency, "Stats", Amount)
	end
end

function module.SetCurrency(Player, Currency, Amount)
	do
		local PlayerData = Player.PlayerData

		if PlayerData:FindFirstChild(Currency) then
			PlayerData:FindFirstChild(Currency).Value = Amount
		end

		ProfileService:SetStatToProfile(Player, Currency, "Stats", Amount)
	end
end

function module.CheckIfEnough(Player, Currency, Amount)
	if ProfileService:GetUserData(Player).Stats[Currency] >= Amount then
		return true
	else
		return false
	end
end--]]

return CurrencyHandler
