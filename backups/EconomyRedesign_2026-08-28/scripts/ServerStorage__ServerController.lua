--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)

local FastWait = ControllerLoader.GetController("FastWait")

--..Variables..--
local Dictionaries = script.Dictionaries

local ServerController = {

    ["Cached"] = {};

}
local Cached = ServerController.Cached

--..Functions..--

--.. Gets Specific Module -> Returns Module
function ServerController.GetModule(Name)
    if Name then
        if Cached[Name] then return Cached[Name] end

        local Module = script:FindFirstChild(Name)
        if Module then
            Cached[Name] = require(Module);

            return Cached[Name];
        end
    end
end

--.. Initializes All Modules That Aren't Blacklisted -> Returns nil
function ServerController.InitializeModulesWithBlacklist(Blacklist)
    do
        local Success, Error = pcall(function()
            for _,Module in next, script:GetChildren() do
                coroutine.wrap(function()
                    if Module:IsA("ModuleScript") then
                        if table.find(Blacklist, Module.Name) then else
                            ServerController.GetModule(Module.Name).Initialize()
                        end
                    end
                end)()
            end
        end)
        if not Success then
            warn("[System]: ".. Error)
        end
    end
end

--..Initializes All Modules That Are Whitelisted On Join -> Returns nil
function ServerController.PlayerJoinedWithWhitelist(Player, Whitelist)
    do
        if Player and Players:FindFirstChild(Player.Name) then
            local Success, Error = pcall(function()
                for _,Module in next, script:GetChildren() do
                    coroutine.wrap(function()
                        if Module:IsA("ModuleScript") then
                            if table.find(Whitelist, Module.Name) then
                                ServerController.GetModule(Module.Name).PlayerJoined(Player)
                            end
                        end
                    end)()
                end
            end)
        end
    end
end

--..Initializes All Modules That Are Whitelisted On Leave -> Returns nil
function ServerController.PlayerLeftWithWhitelist(Player, Whitelist)
    do
        if Player and Players:FindFirstChild(Player.Name) then
            local Success, Error = pcall(function()
                for _,Module in next, script:GetChildren() do
                    if Module:IsA("ModuleScript") then
                        if table.find(Whitelist, Module.Name) then
                            ServerController.GetModule(Module.Name).PlayerLeft(Player)
                        end
                    end
                end
            end)
            if not Success then
                warn("[System]: ".. Error)
            end
        else
            warn("[System]: Invalid Player")
        end
    end
end

--..Initializes All Modules That Are Whitelisted On Character Join -> Returns nil
function ServerController.CharacterJoinedWithWhitelist(Character, Whitelist)
    do
        FastWait(3)
        if Character and Players:FindFirstChild(Character.Name) then
            local Success, Error = pcall(function()
                for _,Module in next, script:GetChildren() do
                    if Module:IsA("ModuleScript") then
                        if table.find(Whitelist, Module.Name) then
                            ServerController.GetModule(Module.Name).CharacterJoined(Character)
                        end
                    end
                end
            end)
            if not Success then
                warn("[System]: ".. Error)
            end
        else
            warn("[System]: Invalid Player")
        end
    end
end

--.. Gets Dictionaries And Caches -> Returns Module
function ServerController.CacheDictionary(Name)
    if Cached[Name] then return Cached[Name] end

    local Module = Dictionaries:FindFirstChild(Name)

    if Module then
        Cached[Name] = require(Module);

        return Cached[Name];
    end
end

--.. Gets Dictionaries In The Dictionary Folder -> Returns Table
function ServerController.GetDictionary(Name, IsClientRequest)
    do
        if Name then

            local Dictionary = ServerController.CacheDictionary(Name)
            if Dictionary then
                if IsClientRequest then return Dictionary.Stats end

                return Dictionary
            else
                return false
            end
        end
    end
end

return ServerController
