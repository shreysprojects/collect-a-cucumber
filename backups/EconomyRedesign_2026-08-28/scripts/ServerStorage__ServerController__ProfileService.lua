--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local ProfileService = require(script.ProfileService)
local InstanceValues = require(script.InstanceValues)
local UserData = require(script.UserData)
local Shared = ReplicatedStorage:WaitForChild("Shared")

local NumberController = ControllerLoader.GetController("NumberController")
local Promise = require(Shared.Promise)

--..Variables..--
local MainPlace = 8100069827
local TestingPlace = 8093740545

local MainKey = "CucumberData_Launch3" -- bumped to reset all player data; old data preserved under "CucumberData_Launch2"
local TestingKey = "TestingCiaxyAPI.*#$000072_6"

local Profiles = {}

local function Key()
    return MainKey
end

local GameProfileStore = ProfileService.GetProfileStore(
    Key(),
    UserData
)

--..Functions..--

function Profiles.GetKey()
    return Key()
end

function Profiles.PlayerJoined(Player)
    coroutine.wrap(function()
        local profile = GameProfileStore:LoadProfileAsync(
            "*Player{}{}_" .. Player.UserId,
            "ForceLoad"
        )

        if profile ~= nil then
            profile:Reconcile()
            --.. quests/ranks retired (2026-07-19): scrub their legacy fields from
            --.. every profile on load so the saved data is permanently deleted
            profile.Data.Quests = nil
            profile.Data.QuestTallies = nil
            profile.Data.RankData = nil
            if profile.Data.Stats then
                profile.Data.Stats.Multi = nil
                profile.Data.Stats.Scale = 1 -- rank-ups were the only thing growing Scale
            end
            profile:ListenToRelease(function()
                Profiles[Player] = nil
                Player:Kick()
            end)
            if Player:IsDescendantOf(Players) == true then
                Profiles[Player] = profile

                InstanceValues.SetValues(Player, profile.Data)
            else
                profile:Release()
            end
        else
            Player:Kick() 
        end
    end)()
end

function Profiles.PlayerLeft(Player)
    local profile = Profiles[Player]
    if profile ~= nil then
        profile:Release()
    end
end

function Profiles.AddStatToProfile(player, StatName, ParentStat, amount)
    do
        local profile = Profiles[player]

        if profile then
            if ParentStat ~= nil then
                profile.Data[ParentStat][StatName] += amount
            else
                profile.Data[StatName] += amount
            end
        end
    end
end

function Profiles.RemoveStatFromProfile(player, StatName, ParentStat, amount)
    do
        local profile = Profiles[player]

        if profile then
            if ParentStat ~= nil then
                profile.Data[ParentStat][StatName] -= amount
            else
                profile.Data[StatName] -= amount
            end
        end
    end
end

function Profiles.SetStatToProfile(player, StatName, ParentStat, new)
    do
        local profile = Profiles[player]

        if profile then
            if ParentStat ~= nil then
                profile.Data[ParentStat][StatName] = new
            else
                profile.Data[StatName] = new
            end
        end
    end
end

function Profiles.GetUserData(player)
    if player and Players:FindFirstChild(player.Name) then
        if Profiles[player] then
            return Profiles[player].Data
        end
    end
end


function Profiles.GetUserDataPromise(player)
    return Promise.new(function(resolve, reject)
        if player and Players:FindFirstChild(player.Name) then
            if Profiles[player] then
                resolve(Profiles[player].Data)
            end
        else
            reject("An error occured when retrieving the player's profile")
        end
    end)
end


--..Admin (AdminPanelService)..--
--.. Direct-DataStore operations for the admin panel: they act on the profile
--.. KEY, not the live session, so they also work for players who are not in
--.. this server. Only one ProfileStore may exist per store name, so these must
--.. live here with GameProfileStore rather than in AdminPanelService.

local function ProfileKey(userId)
    return "*Player{}{}_" .. userId
end

--.. Fully erases a user's saved profile from the DataStore. If the user is in
--.. THIS server their session is released first (ListenToRelease kicks them),
--.. so an autosave can't resurrect the data. A session in ANOTHER live server
--.. can still rewrite the key on its next autosave — rerun once they log off.
function Profiles.AdminWipeUserAsync(userId)
    local plr = Players:GetPlayerByUserId(userId)
    if plr then
        local profile = Profiles[plr]
        if profile then
            profile:Release() --.. ListenToRelease kicks them
            local t0 = os.clock()
            while profile:IsActive() and os.clock() - t0 < 15 do task.wait(0.25) end
        else
            plr:Kick("Your save data was reset by an admin. Rejoin for a fresh start!")
        end
    end
    return GameProfileStore:WipeProfileAsync(ProfileKey(userId))
end

--.. Loads an OFFLINE user's profile straight from the DataStore, hands its
--.. Data to editFn, then releases (= saves). Refuses users in this server —
--.. their live profile must be edited through the normal services instead.
--.. ForceLoad steals the session of a user in another live server (kicks them
--.. there), which is the intended admin behaviour.
function Profiles.AdminEditOfflineAsync(userId, editFn)
    if Players:GetPlayerByUserId(userId) then
        return false, "TARGET IS IN THIS SERVER"
    end
    local profile = GameProfileStore:LoadProfileAsync(ProfileKey(userId), "ForceLoad")
    if profile == nil then
        return false, "COULD NOT LOAD PROFILE (TRY AGAIN)"
    end
    profile:Reconcile()
    local ok, err = pcall(editFn, profile.Data)
    profile:Release()
    return ok, ok and nil or tostring(err)
end

--.. Read-only DataStore snapshot of a user's saved profile. Unlike
--.. AdminEditOfflineAsync this takes NO session lock and writes nothing back,
--.. so it never steals (= kicks) a session the user has in another server.
--.. A user in THIS server just gets their live data. The snapshot is not
--.. Reconciled — old profiles may lack newer fields, so callers nil-guard.
function Profiles.AdminViewOfflineAsync(userId)
    local plr = Players:GetPlayerByUserId(userId)
    if plr and Profiles[plr] then
        return Profiles[plr].Data
    end
    local ok, profile = pcall(function()
        return GameProfileStore:ViewProfileAsync(ProfileKey(userId))
    end)
    if not ok then
        return nil, "DATASTORE READ FAILED (TRY AGAIN IN A MINUTE)"
    end
    if profile == nil or profile.Data == nil then
        return nil, "NO SAVED PROFILE FOR THAT USER"
    end
    return profile.Data
end

return Profiles
