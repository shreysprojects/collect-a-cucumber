--..Services..--
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(game.ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local ProductController = ControllerLoader.GetController("ProductController")
local NumberController = ControllerLoader.GetController("NumberController")
local Excluded = require(script.Parent.Excluded)

--..Variables..--
local board = workspace.Leaderboards.TotalTime.Board

local Top3 = board.SurfaceGui.Top100.Top3
local template = board.SurfaceGui.Top100.ScrollingFrame.Template:Clone()
board.SurfaceGui.Top100.ScrollingFrame.Template:Destroy()
--..
local DSS = DataStoreService:GetOrderedDataStore(ProfileService.GetKey().. " Time")
local UserNameCache = {}
local RefreshGeneration = 0

local module = {

    Colors = {
        Gold = Color3.fromRGB(255, 213, 0);
        Silver = Color3.fromRGB(141, 141, 141);
        Bronze = Color3.fromRGB(185, 102, 0);
        White = Color3.fromRGB(255,255,255);
    };

}

--..Functions..--

function module:Refresh()
    local success, pageOrError = pcall(function()
        return DSS:GetSortedAsync(false, 100):GetCurrentPage()
    end)
    if not success then
        warn("[TotalTimeLeaderboard] failed to load leaderboard:", pageOrError)
        return
    end

    -- Only clear the current board after a fresh page was loaded successfully.
    -- A temporary DataStore outage will leave the last good board visible.
    for _, child in ipairs(board.SurfaceGui.Top100.ScrollingFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    local ranked = {}
    for _, entry in ipairs(pageOrError) do
        local userId = tonumber(entry.key)
        if userId and not Excluded[userId] then
            table.insert(ranked, {
                userId = userId,
                value = tonumber(entry.value) or 0,
            })
        end
    end

    RefreshGeneration += 1
    local thisRefresh = RefreshGeneration
    local rowsByUserId = {}

    for rank, entry in ipairs(ranked) do
        local playerName = UserNameCache[entry.userId] or ("User " .. entry.userId)

        local new = template:Clone()
        new.plrName.Text = playerName
        new.Rank.Text = "#" .. rank
        new.plrValue.Text = NumberController.ToHMS(NumberController.RoundNumber(entry.value, 1))
        new.LayoutOrder = rank
        new.Parent = board.SurfaceGui.Top100.ScrollingFrame
        rowsByUserId[entry.userId] = new

        local podiumName
        if rank == 1 then
            podiumName = "1st"
            new.Rank.TextColor3 = module.Colors.Gold
        elseif rank == 2 then
            podiumName = "2nd"
            new.Rank.TextColor3 = module.Colors.Silver
        elseif rank == 3 then
            podiumName = "3rd"
            new.Rank.TextColor3 = module.Colors.Bronze
        else
            new.Rank.TextColor3 = module.Colors.White
        end

        if podiumName then
            local thumbnailSuccess, content = pcall(
                Players.GetUserThumbnailAsync,
                Players,
                entry.userId,
                Enum.ThumbnailType.HeadShot,
                Enum.ThumbnailSize.Size420x420
            )
            if thumbnailSuccess and content then
                Top3[podiumName].Icon.Image = content
            end
        end
    end

    -- Resolve uncached names one at a time. Each successful lookup updates its
    -- existing row immediately, producing a top-to-bottom refresh effect.
    task.spawn(function()
        for _, entry in ipairs(ranked) do
            if thisRefresh ~= RefreshGeneration then
                return
            end

            if not UserNameCache[entry.userId] then
                local nameSuccess, resolvedName = pcall(
                    Players.GetNameFromUserIdAsync,
                    Players,
                    entry.userId
                )
                if nameSuccess and resolvedName then
                    UserNameCache[entry.userId] = resolvedName
                    local row = rowsByUserId[entry.userId]
                    if row and row.Parent then
                        row.plrName.Text = resolvedName
                    end
                end
                task.wait()
            end
        end
    end)
end

function module:Update()
    -- Save first so this refresh displays the current session's latest totals.
    for _, plr in ipairs(Players:GetPlayers()) do
        local userData = ProfileService.GetUserData(plr)
        local totalStats = userData and userData.TotalStats
        local storedValue = totalStats and tonumber(totalStats.TotalTime)

        if storedValue and not Excluded[plr.UserId] then
            local success, saveError = pcall(function()
                DSS:UpdateAsync(tostring(plr.UserId), function(previousValue)
                    -- Total time can only increase. This prevents an older server session
                    -- from overwriting a newer total with a stale, smaller value.
                    return math.max(tonumber(previousValue) or 0, storedValue)
                end)
            end)
            if not success then
                warn("[TotalTimeLeaderboard] failed to save", plr.UserId, saveError)
            end
        end
        task.wait()
    end

    self:Refresh()
end

script.Parent.Timer.Changed:Connect(function()
    if script.Parent.Timer.Value == 0 then
        workspace.Leaderboards.TotalTime.Timer.SurfaceGui.Timer.Text = "UPDATING..."
    else
        workspace.Leaderboards.TotalTime.Timer.SurfaceGui.Timer.Text = "UPDATING IN"..NumberController.ToMS(script.Parent.Timer.Value)
    end
end)

return module
