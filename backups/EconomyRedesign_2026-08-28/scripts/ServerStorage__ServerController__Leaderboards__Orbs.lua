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
local board = workspace.Leaderboards.TotalOrbs.Board

local Top3 = board.SurfaceGui.Top100.Top3
local template = board.SurfaceGui.Top100.ScrollingFrame.Template:Clone()
board.SurfaceGui.Top100.ScrollingFrame.Template:Destroy()
--..
local DSS = DataStoreService:GetOrderedDataStore(ProfileService.GetKey().. " Orbs")

local module = {

    Colors = {
        Gold = Color3.fromRGB(255, 213, 0);
        Silver = Color3.fromRGB(141, 141, 141);
        Bronze = Color3.fromRGB(185, 102, 0);
        White = Color3.fromRGB(255,255,255);
    };

}

--..Functions..--

--.. cache usernames + top-3 thumbnails so a refresh doesn't fire up to ~100 yielding
--.. web calls (GetNameFromUserIdAsync / GetUserThumbnailAsync) every ~90s -- that was
--.. the real cost (and hit rate limits). Also REUSE the row Frames instead of
--.. destroy+cloning ~100 replicated SurfaceGui rows every refresh (that churned the board).
local NameCache = {}   -- [userid] = username
local ThumbCache = {}  -- [userid] = headshot image
local Rows = {}        -- [rank] = row Frame, reused across refreshes

local function cachedName(userid)
    local cached = NameCache[userid]
    if cached ~= nil then return cached end
    local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userid) end)
    if ok and name then
        NameCache[userid] = name
        return name
    end
    return nil
end

local function cachedThumb(userid)
    local cached = ThumbCache[userid]
    if cached then return cached end
    local ok, content = pcall(function()
        return (Players:GetUserThumbnailAsync(userid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420))
    end)
    if ok and content then
        ThumbCache[userid] = content
        return content
    end
    return nil
end

function module:Refresh(Code)
    local Success, Result = pcall(function()
        local page = DSS:GetSortedAsync(false, 100):GetCurrentPage()

        --.. drop excluded accounts and renumber, so the ranks stay contiguous (#1, #2, #3 ...)
        local Ranked = {}
        for _,entry in ipairs(page) do
            if not Excluded[tonumber(entry.key)] then
                table.insert(Ranked, entry)
            end
        end

        local ScrollingFrame = board.SurfaceGui.Top100.ScrollingFrame
        local shown = 0
        for _,plrData in ipairs(Ranked) do
            local userid = plrData.key
            local Player = cachedName(userid)

            if Player then
                local v = plrData.value
                local retrievedValue = v ~= 0 and (1.0000001^v) or 0
                v = NumberController.RoundNumber(retrievedValue, 1)

                shown += 1
                local new = Rows[shown]
                if not new or not new.Parent then
                    new = template:Clone()
                    new.Parent = ScrollingFrame
                    Rows[shown] = new
                end
                new.plrName.Text = Player
                new.Rank.Text = "#"..shown
                new.plrValue.Text = NumberController.SuffixNumber(v)
                new.LayoutOrder = shown

                if shown == 1 then
                    local content = cachedThumb(userid)
                    if content then Top3["1st"].Icon.Image = content end
                    new.Rank.TextColor3 = module.Colors.Gold
                elseif shown == 2 then
                    local content = cachedThumb(userid)
                    if content then Top3["2nd"].Icon.Image = content end
                    new.Rank.TextColor3 = module.Colors.Silver
                elseif shown == 3 then
                    local content = cachedThumb(userid)
                    if content then Top3["3rd"].Icon.Image = content end
                    new.Rank.TextColor3 = module.Colors.Bronze
                else
                    new.Rank.TextColor3 = module.Colors.White
                end
            end
        end

        --.. remove leftover rows from a previous, longer board
        for rank, frame in pairs(Rows) do
            if rank > shown then
                frame:Destroy()
                Rows[rank] = nil
            end
        end
    end)
end

function module:Update()
    self:Refresh()
    coroutine.wrap(function()
        for _,plr in next, Players:GetPlayers() do
			local UserData = ProfileService.GetUserData(plr)
			if not UserData then continue end
            local value = UserData["TotalStats"]["TotalCucumbers"]

            local storedValue = value ~= 0 and math.floor(math.log(value) / math.log(1.0000001)) or 0

            --.. Excluded accounts never post a score. Without this the board rewrites their
            --.. entry within ~90s of them playing, so deleting the entry alone never sticks.
            if not Excluded[plr.UserId] then
                DSS:SetAsync(plr.UserId, storedValue)
            end
            wait()
        end
    end)()
end

script.Parent.Timer.Changed:Connect(function()
    if script.Parent.Timer.Value == 0 then
        workspace.Leaderboards.TotalOrbs.Timer.SurfaceGui.Timer.Text = "UPDATING..."
    else
        workspace.Leaderboards.TotalOrbs.Timer.SurfaceGui.Timer.Text = "UPDATING IN"..NumberController.ToMS(script.Parent.Timer.Value)
    end
end)

return module
