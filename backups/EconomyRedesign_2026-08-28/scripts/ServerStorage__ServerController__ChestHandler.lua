--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
--..
local ChestStats = ServerController.GetDictionary("Chests").Stats
--..
local ProfileService = ServerController.GetModule("ProfileService")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")

--..Variables..--


local ChestHandler = {
    Debounce = {};
}
local Debounce = ChestHandler.Debounce

--..Functions..--

function ChestHandler.CollectChest(Player, ChestName)
    local Table = ChestStats[ChestName]
    if not Table then return end

    for i,v in next, Table.Currency do
        --.. WasPurchase = flat: the chest pays exactly the number on its billboard,
        --.. not billboard x pet/rank/boost multipliers
        CurrencyHandler.AddCurrency({Player = Player; Currency = i; HasTotal = true; Amount = v; WasPurchase = true;})
    end

    --.. quest board hook (2026-08-27): QuestBoardService counts collections
    local questEvt = ServerStorage:FindFirstChild("QuestChestCollected")
    if questEvt then questEvt:Fire(Player) end


end

--.. Formats a number with thousands separators (7500 -> "7,500")
local function FormatNumber(Amount)
	local Formatted = tostring(math.floor(Amount))
	while true do
		local Replaced
		Formatted, Replaced = Formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if Replaced == 0 then break end
	end
	return Formatted
end

--.. Builds the reward line for a chest from its currency table.
local function BuildRewardText(Table)
	local Parts = {}
	for Currency, Amount in next, Table.Currency do
		table.insert(Parts, FormatNumber(Amount) .. " " .. Currency)
	end
	return table.concat(Parts, " + ")
end

--.. Adds a "Reward" line to every chest billboard so players see what they get
function ChestHandler.SetupRewardDisplays()
	for ChestName, Table in next, ChestStats do
		local Timer = Table.Timer
		local Frame = Timer and Timer.Parent
		if not Frame then continue end

		local TitleLabel = Frame:FindFirstChild("Title")

		--.. reuse the Reward label if it already exists, else clone the Title for matching style
		local Reward = Frame:FindFirstChild("Reward")
		if not Reward then
			Reward = (TitleLabel or Timer):Clone()
			Reward.Name = "Reward"
			for _, Child in next, Reward:GetChildren() do
				Child:Destroy() --.. drop any inherited gradient so the reward color is clean
			end
			Reward.Parent = Frame
		end

		Reward.Text = BuildRewardText(Table)
		Reward.TextColor3 = Color3.fromRGB(90, 235, 255)
		Reward.TextTransparency = 0
		Reward.Visible = true
		Reward.Position = UDim2.new(0, 0, 0.34, 0)
		Reward.Size = UDim2.new(1, 0, 0.32, 0)

		--.. re-stack the three lines (name / reward / timer) so none overlap
		if TitleLabel then
			TitleLabel.Position = UDim2.new(0, 0, 0, 0)
			TitleLabel.Size = UDim2.new(1, 0, 0.32, 0)
		end
		Timer.Position = UDim2.new(0, 0, 0.68, 0)
		Timer.Size = UDim2.new(1, 0, 0.30, 0)
	end
end

function ChestHandler.PlayerJoined(Player)
    -- Profile loading is asynchronous. Poll without recursive calls, and stop
    -- immediately if the player leaves so a failed load cannot leak a task.
    local UserData
    for _ = 1, 30 do
        if not Player:IsDescendantOf(Players) then return end
        UserData = ProfileService.GetUserData(Player)
        if UserData then break end
        FastWait(1)
    end

    if not UserData then
        warn("[ChestHandler] Profile was unavailable after 30 seconds for", Player.Name)
        return
    end

    local Chests = UserData.Chests
    if type(Chests) ~= "table" then return end
    for ChestName in next, ChestStats do
        local ChestData = Chests[ChestName]
        if ChestData and ChestData.TimeRemaining and ChestData.OsTime then
            Network:FireClient(Player, "ChestTime", {
                TimeLeft = ChestData.TimeRemaining - (os.time() - ChestData.OsTime);
                ChestName = ChestName;
            })
        end
    end
end

function ChestHandler.Initialize()
    ChestHandler.SetupRewardDisplays()
    coroutine.wrap(function()
        for ChestName, Table in next, ChestStats do
            Table.HitBox.Touched:Connect(function(hit)
                local Character = hit and hit.Parent
                if Character and Character:FindFirstChildOfClass("Humanoid") then
                    local Player = Players:GetPlayerFromCharacter(Character)
                    --.. NPCs (vendors) have Humanoids too; without a real Player the
                    --.. Debounce[nil] write errored on every brush against a hitbox
                    if Player and Debounce[Player] == nil then
                        Debounce[Player] = true

                        do
                            local CanClaim = true;

                            if Table.Type == "Group" then
                                if Player:IsInGroup(14583228) then
                                    CanClaim = true
                                    --.. refresh the cached membership so the 1.5x cucumber boost
                                    --.. turns on for players who joined the group mid-session
                                    Player:SetAttribute("InGroupFrenzy", true)
                                else
                                    CanClaim = false
                                    --.. walk-up prompt: pop the "join GROUP FRENZY for 1.5x cucumbers"
                                    --.. offer (debounced inside the service so brushing it isn't spammy)
                                    local GroupOfferService = ServerController.GetModule("GroupOfferService")
                                    if GroupOfferService then
                                        GroupOfferService.PromptJoin(Player)
                                    end
									--.. red screen flash removed per request (was: Network:FireClient(Player, 'UnableToClaimChest'))
									FastWait(1)
									Debounce[Player] = nil
                                    return
                                end
                            elseif Table.Type == "Gamepass" then

                            elseif Table.Type == "Premium" then

                            end

                            local UserData = ProfileService.GetUserData(Player)
                            if not UserData then
                                warn("[ChestHandler] Claim ignored while profile is unavailable for", Player.Name)
                                Debounce[Player] = nil
                                return
                            end

                            if type(UserData.Chests) == "table" and CanClaim then
                                if UserData.Chests[ChestName] == nil then
                                    UserData.Chests[ChestName] = {};
                                    UserData.Chests[ChestName].OsTime = os.time();
                                    UserData.Chests[ChestName].TimeRemaining = Table.WaitTime;

                                    ProfileService.SetStatToProfile(Player, "Chests", nil, UserData.Chests)

                                    Network:FireClient(Player, 'TreasureEffect', ChestName)
                                    ChestHandler.CollectChest(Player, ChestName)

                                    Network:FireClient(Player, "Notif", {Message = "CHEST COLLECTED!"; Type = "Success";})

                                    FastWait(1)
                                    Network:FireClient(Player, "ChestTime", {TimeLeft = UserData.Chests[ChestName].TimeRemaining - (os.time() - UserData.Chests[ChestName].OsTime); ChestName = ChestName})
                                else
                                    if os.time() - UserData.Chests[ChestName].OsTime >= UserData.Chests[ChestName].TimeRemaining then
                                        UserData.Chests[ChestName].OsTime = os.time();
                                        UserData.Chests[ChestName].TimeRemaining = Table.WaitTime;

                                        Network:FireClient(Player, 'TreasureEffect', ChestName)
                                        ChestHandler.CollectChest(Player, ChestName)

                                        Network:FireClient(Player, "Notif", {Message = "CHEST COLLECTED!"; Type = "Success";})

                                        FastWait(1)
                                        Network:FireClient(Player, "ChestTime", {TimeLeft = UserData.Chests[ChestName].TimeRemaining - (os.time() - UserData.Chests[ChestName].OsTime); ChestName = ChestName})
                                    else
                                        Network:FireClient(Player, "Notif", {Message = "CHEST NOT READY!"; Type = "Error";})
                                        --.. red screen flash removed per request (was: Network:FireClient(Player, 'UnableToClaimChest'))
                                    end
                                end
                            end
                        end

                        FastWait(2)
                        Debounce[Player] = nil
                    end
                end
            end)
        end
    end)()
end

return ChestHandler
