--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)

local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")
local ProfileService = ServerController.GetModule("ProfileService")
local CollectionService = ServerController.GetModule("CollectionService")
local DoorService = ServerController.GetModule("DoorService")
local TeleportService = ServerController.GetModule("TeleportService")
local ServerHandler = ServerController.GetModule("ServerHandler")
local PickaxeService = ServerController.GetModule("PickaxeService")
local UpgradeService = ServerController.GetModule("UpgradeService")
local PetService = ServerController.GetModule("PetService")
local OfflineService = ServerController.GetModule("OfflineService")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
local ProductController = ControllerLoader.GetController("ProductController")
local EggService = require(script.Parent.PetService.EggService)
local HoverboardService = require(script.Parent.HoverboardService)

--..Variables..--


local module = {

    Debounce = {};

}
local Debounce = module.Debounce

--..Functions..--

function module.Initialize()

    Network:BindFunctions({
        --.. Retrieves Server Data
        GetData = function(Player, Type, InfoTable)
            if Player and Type then
                if Type == "Dictionary" then
                    local Successful = ServerController.GetDictionary(InfoTable.Name, true)
                    if Successful then
                        return Successful
                    else
                        warn("[System]: An error occured when retrieving data")
                        return false
                    end
                end
            else
                warn("[System]: An error occured when retrieving data")
            end
        end,

        --.. Every store card uses the same centralized pickaxe + pet quote as every other Time Skip.
        GetTimeSkips = function(Player)
            local out = {}
            if Player and ProductController.Products.TimeSkips then
                for name, v in next, ProductController.Products.TimeSkips do
                    local seconds = v.Seconds or v.Amount or 0
                    local ok, amount = pcall(TimeSkipRateService.Quote, Player, seconds)
                    out[name] = (ok and amount) or math.max(1, seconds)
                end
            end
            return out
        end,

        GetPetStats = function(...)
            return PetService.GetPetStats(...)
        end,

        GetUserData = function(Player)
            return ProfileService.GetUserData(Player)
        end,

        --.. One-time Starter Pack offer. The first time a player asks, we stamp a
        --.. real-time expiry (now + 30 min) into their saved profile. It therefore
        --.. keeps ticking down while they're offline and, once it passes (or the pack
        --.. is purchased -> StarterOfferExpiry = 0), it never shows again.
        GetStarterOffer = function(Player)
            --.. profiles load asynchronously; right at join the data isn't ready yet, so
            --.. wait for it rather than answering "no offer" (which the client won't retry).
            local profile = ProfileService.GetUserData(Player)
            local waited = 0
            while not profile and waited < 15 do
                task.wait(0.5)
                waited += 0.5
                profile = ProfileService.GetUserData(Player)
            end
            if not profile then return { show = false } end

            local DURATION = 30 * 60
            if profile.StarterOfferExpiry == nil then
                profile.StarterOfferExpiry = os.time() + DURATION
                --.. conversion visibility (2026-08-22): Shown fires once per player at
                --.. first stamp; ProductHandler logs StarterPackPurchased at the burn
                pcall(function()
                    game:GetService("AnalyticsService"):LogCustomEvent(Player, "StarterPackShown", 1)
                end)
            end

            local remaining = profile.StarterOfferExpiry - os.time()
            if remaining <= 0 then
                return { show = false }
            end
            return { show = true, remaining = remaining }
        end,

        PurchasePickaxe = function(...)
            return PickaxeService.FunctionButton(...)
        end,

        --.. ranks retired 2026-07-19: no-op stub so stale clients invoking it don't error
        PurchaseRank = function() return false end,

        PurchaseUpgrade = function(...)
            return UpgradeService.FunctionButton(...)
        end,

        EquipPet = function(...)
            return PetService.EquipPet(...)
        end,

        --.. pet locking + deleting retired 2026-08-04: both features were long gone
        --.. from the UI (only a dead backup module still referenced them, since deleted).
        --.. The endpoints are removed rather than stubbed because
        --.. DeletePet was client-reachable and carried a data-loss bug: it aborted
        --.. mid-batch on a locked pet AFTER already deleting earlier pets and BEFORE
        --.. persisting, and had no type guard, so the id "Unlocked" wiped the Pet Index.
        --.. Selling pets goes through SellVendorServer's own validated handler instead.

        OpenEgg = function(...)
            local res = PetService.OpenEgg(...)
            return res
        end,

        UnequipAll = function(...)
            return PetService.UnequipAll(...)
        end,

        EquipBest = function(...)
            return PetService.EquipBest(...)
        end,

        EvolvePet = function(...)
            return PetService.EvolvePet(...)
        end,

        GetVault = function(Player)
            return OfflineService.GetVault(Player)
        end,

        ClaimVault = function(Player)
            return OfflineService.ClaimVault(Player)
        end,
    })
    --.. carrying a cucumber pins you in place: every teleport path (the BUY /
    --.. BIOME / SELL row, event travel popups, exploit-fired remotes) rejects
    --.. until it's dropped. CarryClient swaps the row for the DROP button too.
    local function BlockedByCarry(Player)
        local CarryService = ServerController.GetModule("CarryService")
        if Player and CarryService and CarryService.Get(Player) then
            Network:FireClient(Player, "Notif", {Message = "\u{1F952} CAN'T TELEPORT WHILE CARRYING!"; Type = "Error";})
            return true
        end
        return false
    end
    Network:BindEvents({
        -- Collect/ChangedZones retired: walk-over orbs were replaced by the
        -- click-to-smash breakables (BreakablesService); kept bound as no-ops
        -- so stale clients firing them don't queue forever
        Collect = function() end,
        ChangedZones = function() end,
        PurchaseDoor = function(Player, DoorName)
            DoorService.PurchaseDoor({Player = Player; DoorName = DoorName})
        end,
        Teleport = function(Player, ...)
            if BlockedByCarry(Player) then return end
            TeleportService.Teleport(Player, ...)
        end,
        TeleportToSell = function(Player)
            if BlockedByCarry(Player) then return end
            ServerHandler.TeleportToSell(Player)
        end,
        TeleportToShop = function(Player)
            if BlockedByCarry(Player) then return end
            ServerHandler.TeleportToShop(Player)
        end,
        --.. HUD VAULT pill (the BIOME button flipped outside the bank)
        TeleportToVault = function(Player)
            if BlockedByCarry(Player) then return end
            local VaultService = ServerController.GetModule("VaultService")
            if VaultService and VaultService.TeleportToStall then
                VaultService.TeleportToStall(Player)
            end
        end,
        --.. left-rail hoverboard button: mounts the board, or dismounts it if
        --.. the player is already riding
        ToggleHoverboard = function(Player)
            HoverboardService.Toggle(Player)
        end,
        --.. right-rail Sprint pass: flip the speed buff on/off for owners and
        --.. recompute walkspeed immediately so it applies without a respawn.
        ToggleSprint = function(Player)
            if not ProductController.CheckGamepass(Player, "Sprint") then return end
            Player:SetAttribute("OwnsSprint", true)
            local currentlyOn = Player:GetAttribute("SprintEnabled") ~= false
            Player:SetAttribute("SprintEnabled", not currentlyOn)
            local Upgrades = ServerController.GetDictionary("Upgrades")
            if Upgrades and Upgrades.SetWalkSpeed then Upgrades.SetWalkSpeed(Player) end
        end,
        Tutorial = function(Player, Skipped)
            local UserData = ProfileService.GetUserData(Player)
            local Stats = UserData and UserData.Stats
            local DoneValue = Player:FindFirstChild("PlayerData") and Player.PlayerData:FindFirstChild("DoneTutorial")
            if not Stats then
                --.. profile already released (quit / session moved): nothing can
                --.. be saved this session. The gift servers' replay top-up keeps
                --.. the next session's forced replay from grind-walling.
                warn(("[ServerNetwork] Tutorial completion from %s arrived after their profile was released; not saved"):format(Player.Name))
                return
            end

            --.. onboarding funnel bookend: 7 = finished every step. Skips are a
            --.. custom event instead, so the dashboard funnel shows real drop-off
            --.. (the client also logs WHICH step the skip happened on via
            --.. TutorialProgressServer).
            pcall(function()
                local AnalyticsService = game:GetService("AnalyticsService")
                if Skipped == true then
                    AnalyticsService:LogCustomEvent(Player, "TutorialSkipped", 1)
                else
                    -- step 11 since the TP-home step joined (2026-08-27)
                    -- (7 StoredInVault, 8 UpgradedCucumber, 9 LockedVault, 10 ReturnedHome)
                    AnalyticsService:LogOnboardingFunnelStepEvent(Player, 11, "TutorialCompleted")
                end
            end)

            -- ClaimedTutorialPet is the one-time reward gate. DoneTutorial predates
            -- this reward, so legacy completers and forced tutorial replays may be
            -- DoneTutorial=true while still legitimately owed Lil Pickle.
            if Stats.ClaimedTutorialPet == true then
                Stats.DoneTutorial = true
                if DoneValue then DoneValue.Value = true end
                return
            end

            --.. Commit completion BEFORE the pet grant: no yields separate this
            --.. from the GetUserData above, so the profile is still live and the
            --.. write lands in the final save even if the player quits right now.
            --.. It used to be written only AFTER the grant (which yields), so a
            --.. profile release mid-grant silently lost the whole completion.
            Stats.DoneTutorial = true
            Stats.TutorialStep = 7
            if DoneValue then DoneValue.Value = true end

            Stats.ClaimedTutorialPet = true
            local PetId = PetService.AddPetToPlayer({Player = Player; Pet = "Lil Pickle"})
            if not PetId then
                Stats.ClaimedTutorialPet = false
                return
            end

            --.. finishing every step (not skipping) pays a small one-time coin
            --.. bonus on top of the pet, so completion feels rewarded without
            --.. punishing veterans who skip. Flat onto leaderstats, same as the
            --.. gift servers, so income multipliers can't inflate it. Sits behind
            --.. the one-time ClaimedTutorialPet gate above, so it can't be farmed.
            if Skipped ~= true then
                local leaderstats = Player:FindFirstChild("leaderstats")
                local coins = leaderstats and leaderstats:FindFirstChild("Coins")
                if coins then coins.Value += 250 end
            end

            Network:FireClient(Player, "TutorialPetReward", "Lil Pickle", "[for completing the tutorial]")
		end,
		ValidateSetting = function(Player, res, hash)
			if type(hash) ~= "string" or type(res) ~= "table" then return end
			if EggService.PendingClaims[hash] ~= Player then return end
			EggService.Claimables[hash] = {
				AutoDeleteCommon = not not res.AutoDeleteCommon;
				AutoDeleteUncommon = not not res.AutoDeleteUncommon;
				AutoDeleteRare = not not res.AutoDeleteRare;
			}
		end,
		--.. quests retired 2026-07-19: kept bound as a no-op so stale clients don't queue
		ClaimQuestReward = function() end,
    })

end

return module

--[[

Network:BindFunctions(functions) 
Network:BindEvents(events)
Network:FireClient(client,name,params)
Network:FireAllClients(name,params)
Network:FireOtherClients(ignoreclient,name,params)
Network:FireOtherClientsWithinDistance(ignoreclient,name,distance,params)
Network:FireAllClientsWithinDistance(name,distance,position,params)
Network:LogTraffic(duration)

--]]
