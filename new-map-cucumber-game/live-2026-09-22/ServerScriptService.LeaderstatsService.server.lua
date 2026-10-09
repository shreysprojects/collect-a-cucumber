--[[
	LeaderstatsService  (Script, ServerScriptService)
	The playerlist columns + the plot income numbers (2026-09-06), and the income itself (2026-09-12).
	  * player.leaderstats (Folder) holds STRING mirrors "Strength" and "Cash/s", abbreviated by
	    ReplicatedStorage.Modules.NumberAbbrev (1.2M, 5.4T, 3Vg ...) -- the core playerlist's own
	    number formatting hard-stops at B. The REAL numbers stay in player.Data: DataService's
	    saved Strength, plus CashPerSec (added here, derived, never saved).
	  * Cash/s = the sum of the Rate of every cucumber standing on the player's plot (tag
	    "PlacedCucumber" + attribute Owner = UserId, placed by CucumberCarry). Every placed cucumber
	    gets a replicated "Rate" attribute here (CucumberValues.RateOf: biome x8 ladder, golden x12)
	    that PlacedCucumberCardClient prints on its overhead card.
	  * recomputed on profile load, placed cucumber added / removed, plot Owner changes.
	  * INCOME (user, 2026-09-12): every INCOME_TICK seconds each placed cucumber pays Rate x tick
	    into its owner's Cash (DataService.Increment, quiet -> player.Data.Cash, the HUD wallet
	    follows; the cash ride the next save instead of a DataStore write per second), for owners
	    who are in the server with a loaded profile. The same tick fires
	    Remotes.CucumberIncome (RemoteEvent, all clients) with the cucumbers that paid and their
	    amounts, so PlacedCucumberCardClient floats "+X" up from every card at the moment the cash land.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local DataService = require(ServerStorage:WaitForChild("DataService"))
local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local PLACED_TAG = "PlacedCucumber"
local RATE_ATTRIBUTE = "Rate"
local CASH_KEY = "Cash" -- the DataService key the income lands in
local INCOME_TICK = 1 -- seconds between payouts (a Rate is cash per second)
local INCOME_REMOTE = "CucumberIncome" -- RemoteEvent -> all clients: (models, amounts) each tick

local Stats = {} -- [player] = {Strength = StringValue, Rate = StringValue, RawRate = NumberValue, StrengthValue = NumberValue}

local incomeRemote = Remotes:FindFirstChild(INCOME_REMOTE)
if not incomeRemote then
	incomeRemote = Instance.new("RemoteEvent")
	incomeRemote.Name = INCOME_REMOTE
	incomeRemote.Parent = Remotes
end

--..Placed cucumbers..--
local function StampRate(model)
	local rate = CucumberValues.RateOfInstance(model)
	if model:GetAttribute(RATE_ATTRIBUTE) ~= rate then model:SetAttribute(RATE_ATTRIBUTE, rate) end
	return rate
end

--.. the player's placed cucumbers that earn: standing in the workspace, Owner = the player
local function EarningFor(player, callback)
	for _, model in ipairs(CollectionService:GetTagged(PLACED_TAG)) do
		if model:GetAttribute("Owner") == player.UserId and model:IsDescendantOf(workspace) then
			callback(model, tonumber(model:GetAttribute(RATE_ATTRIBUTE)) or StampRate(model))
		end
	end
end

local function IncomeOf(player)
	local total = 0
	EarningFor(player, function(_, rate) total += rate end)
	return total
end

--..Display..--
local function RefreshStrength(player)
	local s = Stats[player]
	if s and s.StrengthValue then s.Strength.Value = NumberAbbrev.Abbrev(s.StrengthValue.Value) end
end

local function RefreshIncome(player)
	local s = Stats[player]
	if not s then return end
	local income = IncomeOf(player)
	s.RawRate.Value = income
	s.Rate.Value = NumberAbbrev.Abbrev(income)
end

local pending = false
local function RefreshAllIncome()
	if pending then return end
	pending = true
	task.defer(function()
		pending = false
		for player in pairs(Stats) do RefreshIncome(player) end
	end)
end

--..Income: once a tick every placed cucumber pays its Rate into its owner's Cash, and every client
--..hears which cucumbers paid what (the "+X" popups over the cards)..--
local function PayIncome()
	local paidModels, paidAmounts = {}, {}
	for player in pairs(Stats) do
		if player.Parent == Players and DataService.IsLoaded(player) then
			local total = 0
			EarningFor(player, function(model, rate)
				local amount = rate * INCOME_TICK
				if amount > 0 then
					total += amount
					table.insert(paidModels, model)
					table.insert(paidAmounts, amount)
				end
			end)
			--.. quiet: the cash land in the profile + player.Data.Cash now and ride the next save (the
			--.. 60 s autosave, another key's write, or leaving) - not a DataStore write every second
			if total > 0 then DataService.Increment(player, CASH_KEY, total, true) end
		end
	end
	if #paidModels > 0 then incomeRemote:FireAllClients(paidModels, paidAmounts) end
end

task.spawn(function()
	while true do
		task.wait(INCOME_TICK)
		local ok, err = pcall(PayIncome)
		if not ok then warn("[LeaderstatsService] income tick: " .. tostring(err)) end
	end
end)

--..Per player, once the profile is in (DataService parents player.Data before its callbacks run)..--
local function Setup(player)
	if Stats[player] or player.Parent ~= Players then return end
	local data = player:WaitForChild("Data", 10)
	if not data then return end
	local strengthValue = data:WaitForChild("Strength", 10)
	local raw = data:FindFirstChild("CashPerSec")
	if not raw then
		raw = Instance.new("NumberValue")
		raw.Name = "CashPerSec"
		raw.Parent = data
	end
	local folder = player:FindFirstChild("leaderstats") or Instance.new("Folder")
	folder.Name = "leaderstats"
	local strength = folder:FindFirstChild("Strength") or Instance.new("StringValue")
	strength.Name = "Strength"
	strength.Parent = folder
	local rate = folder:FindFirstChild("Cash/s") or Instance.new("StringValue")
	rate.Name = "Cash/s"
	rate.Parent = folder
	Stats[player] = {Strength = strength, Rate = rate, RawRate = raw, StrengthValue = strengthValue}
	if strengthValue then
		strengthValue.Changed:Connect(function() RefreshStrength(player) end)
	end
	RefreshStrength(player)
	RefreshIncome(player)
	folder.Parent = player -- parented last: the playerlist sees both columns at once, in this order
end

--..Wiring..--
DataService.OnProfileLoaded(function(player) Setup(player) end)
Players.PlayerRemoving:Connect(function(player) Stats[player] = nil end)

for _, model in ipairs(CollectionService:GetTagged(PLACED_TAG)) do StampRate(model) end
CollectionService:GetInstanceAddedSignal(PLACED_TAG):Connect(function(model)
	StampRate(model)
	RefreshAllIncome()
end)
CollectionService:GetInstanceRemovedSignal(PLACED_TAG):Connect(RefreshAllIncome)

--.. plots change hands (PlotService): the income follows the Owner attributes
task.spawn(function()
	local plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
	local function watch(plot)
		plot:GetAttributeChangedSignal("Owner"):Connect(RefreshAllIncome)
	end
	for _, plot in ipairs(plots:GetChildren()) do watch(plot) end
	plots.ChildAdded:Connect(watch)
end)

print(("[LeaderstatsService] leaderstats (Strength, Cash/s) + placed cucumber rates ready; income every %ds -> Cash + %s"):format(INCOME_TICK, INCOME_REMOTE))
