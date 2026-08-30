--..Modules
local Coins = require(script.Coins)
local Orbs = require(script.Orbs)
local Breaks = require(script.Breaks)
local Time = require(script.Time)

local module = {}

local Timer = script.Timer

local function Update()
    Coins:Update()
    Orbs:Update()
    Breaks:Update()
	Time:Update()
end

function module.GetUserHighestRank(plr)
	local HighestRank = 4000
	for _, board in ipairs(game.Workspace.Leaderboards:GetChildren()) do
		for _, v in ipairs(board.Board.SurfaceGui.Top100.ScrollingFrame:GetChildren()) do
			if v:IsA'Frame' and v.plrName.Text == plr.Name then
				local ThisRank = tonumber(v.Rank.Text:match('%d+'))
				HighestRank = (ThisRank < HighestRank and ThisRank) or HighestRank
				break
			end
		end
	end
	
	if HighestRank > 100 then
		return
	end
	
	return '#' .. HighestRank
end

function module.Initialize()
    coroutine.wrap(function()
        wait(5)
        Update()
        while wait(1) do
            if Timer.Value == 0 then
                Update()
                wait(1)
                Timer.Value = 90
            else
                Timer.Value = Timer.Value - 1
            end
        end
    end)()
end

return module
