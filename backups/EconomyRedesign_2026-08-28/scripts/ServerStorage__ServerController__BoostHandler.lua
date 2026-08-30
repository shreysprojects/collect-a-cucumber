--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")
local ProductController = ControllerLoader.GetController("ProductController")
local NumberController = ControllerLoader.GetController("NumberController")

--..Variables..--


local BoostHandler = {}

--..Functions..--

function BoostHandler.PlayerJoined(Player)
    do
        FastWait(2)
        local UserData = ProfileService.GetUserData(Player)

        if UserData then
            local Boosts = UserData.Boosts
            local BoostTotals = UserData.BoostTotals or {}
            if Boosts then
                for Index, Values in next, Boosts do
                    if Index and Values and Values > 0 then
                        local total = math.max(Values, tonumber(BoostTotals[Index]) or 0)
                        if total ~= BoostTotals[Index] then
                            ProfileService.SetStatToProfile(Player, Index, "BoostTotals", total)
                        end
                        Network:FireClient(Player, "Boosts", {
                            BoostName = Index;
                            TimeRemaining = Values;
                            TotalDuration = total;
                        })
                    end
                end
            end
        end
    end
end

function BoostHandler.ValidateBoosts(Player, BoostName)
    do
        local UserData = ProfileService.GetUserData(Player)

        if UserData then
            local Boosts = UserData.Boosts

            if Boosts then
                if Boosts[BoostName] > 0 then
                    return true
                else
                    return false
                end
            end
        end
    end
end

function BoostHandler.AddBoost(Player, BoostName, Time)
    local UserData = ProfileService.GetUserData(Player)
    if not UserData or not UserData.Boosts then return false end

    Time = math.max(0, math.floor(tonumber(Time) or 0))
    local current = math.max(0, tonumber(UserData.Boosts[BoostName]) or 0)
    local newRemaining = current + Time

    ProfileService.SetStatToProfile(Player, BoostName, "Boosts", newRemaining)
    ProfileService.SetStatToProfile(Player, BoostName, "BoostTotals", newRemaining)

    Network:FireClient(Player, "Boosts", {
        BoostName = BoostName;
        TimeRemaining = newRemaining;
        TotalDuration = newRemaining;
    })
    return true
end


function BoostHandler.Initialize()
    do
        while wait(1) do
            for _,Player in next, Players:GetPlayers() do
                if Player then
                    local UserData = ProfileService.GetUserData(Player)
                    if UserData then
                        local Boosts = UserData.Boosts
                        for Index, Value in next, Boosts do
                            if Index and Value then
                                if Value > 0 then
                                    ProfileService.AddStatToProfile(Player, Index, "Boosts", -1)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

return BoostHandler
