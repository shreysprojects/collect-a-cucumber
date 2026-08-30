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
local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")

local DoorStats = ServerController.GetDictionary("Doors").Stats

--..Variables..--
local Doors = workspace.Doors
local Locations = Doors:FindFirstChild("Locations")

local DoorService = {
    Debounce = {};
}
local Debounce = DoorService.Debounce

--..Functions..--

function DoorService.PlayerJoined(Player)
    -- The loading screen waits for this server-authoritative signal. Set it before
    -- doing any join work so even a very fast client cannot uncover the spawn pad.
    Player:SetAttribute("InitialAreaTeleportComplete", false)

    local ok, err = pcall(function()
        if not Player:IsDescendantOf(Players) then return end

        local UserData = ProfileService.GetUserData(Player)
        local deadline = os.clock() + 15
        while not UserData and Player:IsDescendantOf(Players) and os.clock() < deadline do
            task.wait(.1)
            UserData = ProfileService.GetUserData(Player)
        end
        if not UserData then return end

        local DoorData = UserData.DoorData
        if not DoorData then return end

        local BestZone = "Spawn"
        local BestOrder = 0
        local MaxOwnedOrder = 0
        for _, Door in ipairs(string.split(DoorData, " # ")) do
            Network:FireClient(Player, "RemoveDoor", Door)

            local DoorInfo = DoorStats[Door]
            local Order = DoorInfo and DoorInfo.ClientSided and DoorInfo.ClientSided.Order or 0
            if Order > MaxOwnedOrder then MaxOwnedOrder = Order end
            if Locations and Locations:FindFirstChild(Door) and Order > BestOrder then
                BestZone = Door
                BestOrder = Order
            end
        end

        --.. owning a later area implies every area behind it. This self-heals
        --.. saves that skipped ahead (bought a far door before the purchase
        --.. cascade below existed) on every join.
        local Backfilled = false
        for Name, Info in pairs(DoorStats) do
            local Order = Info.ClientSided and Info.ClientSided.Order or 0
            if Order > 0 and Order < MaxOwnedOrder and not DoorData:find(Info.Index) then
                DoorData = DoorData .. " # " .. Name
                Network:FireClient(Player, "RemoveDoor", Name)
                Backfilled = true
            end
        end
        if Backfilled then
            ProfileService.SetStatToProfile(Player, "DoorData", nil, DoorData)
            local pd = Player:FindFirstChild("PlayerData")
            local DoorsFolder = pd and pd:FindFirstChild("Doors")
            if DoorsFolder and DoorsFolder:FindFirstChild("OwnedString") then
                DoorsFolder.OwnedString.Value = DoorData
            end
        end

        -- This runs only on initial join; ordinary respawns keep their existing behavior.
        local Character = Player.Character or Player.CharacterAdded:Wait()
        local HumanoidRootPart = Character and Character:WaitForChild("HumanoidRootPart", 10)
        local Location = Locations and Locations:FindFirstChild(BestZone)

        --.. Finished-tutorial players join at their vault stall instead of the
        --.. furthest-biome pad; the pad stays the fallback (fresh players, no
        --.. stall assigned, bank mid-rebuild). Forced tutorial replays keep the
        --.. pad so the tutorial's catch-first opening still lines up.
        local StallCFrame, StallLook
        if UserData.Stats and UserData.Stats.DoneTutorial == true
            and Player:GetAttribute("ForceTutorialOnJoin") ~= true then
            local VaultService = ServerController.GetModule("VaultService")
            local retryUntil = os.clock() + 3
            while Player:IsDescendantOf(Players) do
                StallCFrame, StallLook = VaultService.StallSpawnCFrame(Player)
                if StallCFrame or os.clock() > retryUntil then break end
                task.wait(0.1)
            end
        end

        if Character and HumanoidRootPart and StallCFrame then
            -- Stream the destination while it is still hidden by the loading cover.
            pcall(function()
                Player:RequestStreamAroundAsync(StallCFrame.Position, 3)
            end)
            Character:PivotTo(StallCFrame)
            Network:FireClient(Player, "AlignCamera", StallLook)
        elseif Character and HumanoidRootPart and Location then
            -- Stream the destination while it is still hidden by the loading cover.
            pcall(function()
                Player:RequestStreamAroundAsync(Location.Position, 3)
            end)
            Character:PivotTo(Location.CFrame + Vector3.new(0, 3, 0))
            Network:FireClient(Player, "AlignCamera", Location.CFrame.LookVector)
        end
    end)

    if not ok then
        warn("[DoorService] initial area teleport failed: " .. tostring(err))
    end
    if Player:IsDescendantOf(Players) then
        Player:SetAttribute("InitialAreaTeleportComplete", true)
    end
end

function DoorService.PurchaseDoor(InfoTable)
    do
        if InfoTable then
            do
                local Player = InfoTable.Player
                local DoorName = InfoTable.DoorName

                if Player and DoorName then
                    local DoorTable = type(DoorName) == "string" and DoorStats[DoorName] or nil
                    if not DoorTable or not DoorTable.Stats then return false end
                    local UserData = ProfileService.GetUserData(Player)
                    if UserData then
                        local DoorData = UserData.DoorData
                        if DoorData:find(DoorTable.Index) then else
                            local Currency = DoorTable.Stats.Currency
                            local Price = DoorTable.Stats.Price

                            --.. later biomes are REBIRTH-gated: the loop is
                            --.. farm -> rebirth -> blast back with the bonus -> push deeper
                            local needStars = DoorTable.Stats.MinRebirths or 0
                            if (UserData.Rebirths or 0) < needStars then
                                Network:FireClient(Player, "Notif", {Message = ("\u{2B50} %s NEEDS %d REBIRTH%s!"):format(string.upper(DoorTable.Name), needStars, needStars > 1 and "S" or ""); Type = "Error";})
                                return false
                            end

                            if CurrencyHandler.CheckIfEnough({Player = Player; Currency = Currency; Amount = Price}) then
                                local PlayerData = Player:FindFirstChild("PlayerData")
                                local Doors = PlayerData:FindFirstChild("Doors")
                                local OwnedString = Doors:FindFirstChild("OwnedString")
                                local NewString = OwnedString.Value.." # ".. DoorName

                                --.. buying a later area also unlocks every area behind it
                                --.. for free (skipping ahead must never strand earlier doors)
                                local MyOrder = DoorTable.ClientSided and DoorTable.ClientSided.Order or 0
                                local Backfilled = {}
                                for Name, Info in pairs(DoorStats) do
                                    local Order = Info.ClientSided and Info.ClientSided.Order or 0
                                    if Order > 0 and Order < MyOrder and not NewString:find(Info.Index) then
                                        NewString = NewString .. " # " .. Name
                                        table.insert(Backfilled, Name)
                                    end
                                end

                                CurrencyHandler.RemoveCurrency(Player, Currency, Price, "Door:" .. DoorName)
                                ProfileService.SetStatToProfile(Player, "DoorData", nil, NewString)
                                OwnedString.Value = NewString

                                --.. ZoneProgression one-time funnel (2026-08-22): mid-game drop-off
                                --.. visibility. Step 3 is FirstRebirth (RebirthService logs it).
                                pcall(function()
                                    local STEP = {Desert = 1, Samurai = 2, Farm = 4, Snow = 5, Underwater = 6, Volcano = 7, Narmek = 8}
                                    local s = STEP[DoorName]
                                    if s then
                                        game:GetService("AnalyticsService"):LogFunnelStepEvent(Player, "ZoneProgression", nil, s, DoorName .. "Door")
                                    end
                                end)

                                Network:FireClient(Player, "Notif", {Message = "PURCHASED!"; Type = "Success";})
                                Network:FireClient(Player, "RemoveDoor", DoorName, true)
                                for _, Name in ipairs(Backfilled) do
                                    Network:FireClient(Player, "RemoveDoor", Name)
                                end
                                if DoorName == "Desert" or table.find(Backfilled, "Desert") then
                                    ServerController.GetModule("GoalService").RecordAction(Player, "UnlockWildWest", 1)
                                end
                                return true
							else
								--.. (removed) no longer force-opens the coin shop when the player can't afford it
                                Network:FireClient(Player, "Notif", {Message = ("NOT ENOUGH %s!"):format(string.upper(Currency)); Type = "Error";})
                            end
                        end
                    end
                end
            end
        end
    end
end

function DoorService.PromptPurchase(InfoTable)
    do
        if InfoTable then
            do
                local Player = InfoTable.Player
                local DoorTable = InfoTable.DoorTable

                if Player and DoorTable then
                    local UserData = ProfileService.GetUserData(Player)
                    if UserData then
                        local DoorData = UserData.DoorData
                        if DoorData:find(DoorTable.Index) then else
                            local needStars = DoorTable.Stats.MinRebirths or 0
                            if (UserData.Rebirths or 0) < needStars then
                                Network:FireClient(Player, "Notif", {Message = ("\u{2B50} %s UNLOCKS AT %d REBIRTH%s!"):format(string.upper(DoorTable.Name), needStars, needStars > 1 and "S" or ""); Type = "Error";})
                            else
                                Network:FireClient(Player, "PromptDoor", DoorTable.Index)
                            end
                        end
                    end
                end
            end
        end
    end
end

function DoorService.Initialize()
    do

        for _,Door in next, Doors:GetChildren() do
            if Door and Door:FindFirstChild("HitPart") then
				Door.HitPart.Touched:Connect(function(hit)
					if not hit or hit.Name == "Circle" then return end
					local Character = hit.Parent
					if Character and Character:FindFirstChildOfClass("Humanoid") then
                        if Debounce[Character] == nil then
                            Debounce[Character] = true

                            DoorService.PromptPurchase({Player = Players:GetPlayerFromCharacter(Character); DoorTable = DoorStats[Door.Name]})

                            FastWait(1)
                            Debounce[Character] = nil
                        end
                    end
                end)
            end
        end

    end
end

return DoorService
