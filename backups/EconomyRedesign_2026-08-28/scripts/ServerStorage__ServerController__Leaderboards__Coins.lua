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
local board = workspace.Leaderboards.TotalCoins.Board

local Top3 = board.SurfaceGui.Top100.Top3
local template = board.SurfaceGui.Top100.ScrollingFrame.Template:Clone()
board.SurfaceGui.Top100.ScrollingFrame.Template:Destroy()
--..
local DSS = DataStoreService:GetOrderedDataStore(ProfileService.GetKey().. " Coins")

local module = {

    Colors = {
        Gold = Color3.fromRGB(255, 213, 0);
        Silver = Color3.fromRGB(141, 141, 141);
        Bronze = Color3.fromRGB(185, 102, 0);
        White = Color3.fromRGB(255,255,255);
    };

}

--..Functions..--

function module:Refresh(Code)
    for _,child in next, board.SurfaceGui.Top100.ScrollingFrame:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    local Success, Result = pcall(function()
        local page = DSS:GetSortedAsync(false, 100):GetCurrentPage()

        --.. drop excluded accounts and renumber, so the ranks stay contiguous (#1, #2, #3 ...)
        local Ranked = {}
        for _,entry in ipairs(page) do
            if not Excluded[tonumber(entry.key)] then
                table.insert(Ranked, entry)
            end
        end

        for Rank,plrData in ipairs(Ranked) do
            local userid = plrData.key
            local Cash = plrData

            local Player = Players:GetNameFromUserIdAsync(userid)

            if Player then
                local v = Cash.value
                local retrievedValue = v ~= 0 and (1.0000001^v) or 0

                v = NumberController.RoundNumber(retrievedValue, 1)
                local new = template:Clone()
                new.plrName.Text = Player

                new.Rank.Text = "#"..Rank
                new.plrValue.Text = NumberController.SuffixNumber(v)
                new.LayoutOrder = Rank
                new.Parent = board.SurfaceGui.Top100.ScrollingFrame
                if Rank == 1 then

                    --ChangeCharacter(userid)

                    local thumbType = Enum.ThumbnailType.HeadShot
                    local thumbSize = Enum.ThumbnailSize.Size420x420
                    local content, IsReady = Players:GetUserThumbnailAsync(userid, thumbType, thumbSize)

                    Top3["1st"].Icon.Image = content
                    new.Rank.TextColor3 = module.Colors.Gold

                elseif Rank == 2 then

                    local thumbType = Enum.ThumbnailType.HeadShot
                    local thumbSize = Enum.ThumbnailSize.Size420x420
                    local content, IsReady = Players:GetUserThumbnailAsync(userid, thumbType, thumbSize)

                    Top3["2nd"].Icon.Image = content

                    new.Rank.TextColor3 = module.Colors.Silver
                elseif Rank == 3 then

                    local thumbType = Enum.ThumbnailType.HeadShot
                    local thumbSize = Enum.ThumbnailSize.Size420x420
                    local content, IsReady = Players:GetUserThumbnailAsync(userid, thumbType, thumbSize)

                    Top3["3rd"].Icon.Image = content

                    new.Rank.TextColor3 = module.Colors.Bronze
                else
                    new.Rank.TextColor3 = module.Colors.White
                end
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
            local value = UserData["TotalStats"]["TotalCoins"]

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
        workspace.Leaderboards.TotalCoins.Timer.SurfaceGui.Timer.Text = "UPDATING..."
    else
        workspace.Leaderboards.TotalCoins.Timer.SurfaceGui.Timer.Text = "UPDATING IN"..NumberController.ToMS(script.Parent.Timer.Value)
    end
end)

return module
