--[[
	LeaderstatsService  (Script, ServerScriptService)
	The playerlist columns + the plot income numbers (2026-09-06), and the income itself (2026-09-12).
	  * player.leaderstats (Folder) holds STRING mirrors "Strength" and "Cash/s", abbreviated by
	    ReplicatedStorage.Modules.NumberAbbrev (1.2M, 5.4T, 3Vg ...) -- the core playerlist's own
	    number formatting hard-stops at B. The REAL numbers stay in player.Data: DataService's
	    saved Strength, plus CashPerSec (added here, derived, never saved).
	  * Cash/s = what the player earns per second. INCOME MOVED (2026-09-22, pet system): the income
	    itself - placed cucumbers + active pets settled on one 1 s tick, the "Rate" / "BaseRate"
	    attributes on placed cucumbers, player.Data.CashPerSec, Remotes.CucumberIncome / PetIncome -
	    lives in ServerStorage.IncomeService (started by PetServer). This script mirrors its Total
	    into "Cash/s" (IncomeService.OnTotalsChanged / GetTotals) and still creates CashPerSec in Setup.
	  * LEGACY FALLBACK (2026-09-22): the old pay code (the 2026-09-12 loop: every INCOME_TICK each
	    placed cucumber pays Rate x tick into its owner's Cash, DataService.Increment quiet, then
	    Remotes.CucumberIncome (models, amounts) to all clients for the "+X" card popups) stays here,
	    dormant, behind a mode latch: "Waiting" -> "Service" for good once IncomeService.IsStarted();
	    still not started LEGACY_AFTER seconds after this script started -> "Legacy" (warns once) and
	    the old loop pays + writes CashPerSec / Cash/s itself. IsStarted() is checked first on every
	    tick, so the two never pay the same span. Only Legacy mode writes the cucumber "Rate" here.
	    While "Waiting" (IncomeService not started yet) Cash/s + CashPerSec still show the placed cucumbers'
	    sum every tick, unpaid, so the raid threat's CashPerSec fallback never reads 0 (S2 integration).
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

local function Lazy(name) -- 2026-09-22: pet-system modules are optional until their stage is installed
	local cache
	return function()
		if cache then return cache end
		local module = ServerStorage:FindFirstChild(name)
		if not module then return nil end
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then cache = result end
		return cache
	end
end
local IncomeServiceModule = Lazy("IncomeService")

local function IncomeStarted() -- 2026-09-22: IncomeService is the payer once this is true
	local income = IncomeServiceModule()
	return income ~= nil and type(income.IsStarted) == "function" and income.IsStarted() == true
end

local PLACED_TAG = "PlacedCucumber"
local RATE_ATTRIBUTE = "Rate"
local CASH_KEY = "Cash" -- the DataService key the income lands in
local INCOME_TICK = 1 -- seconds between payouts (a Rate is cash per second)
local INCOME_REMOTE = "CucumberIncome" -- RemoteEvent -> all clients: (models, amounts) each tick
local LEGACY_AFTER = 10 -- 2026-09-22: seconds after script start before the legacy loop takes over (IncomeService not started)

local Stats = {} -- [player] = {Strength = StringValue, Rate = StringValue, RawRate = NumberValue, StrengthValue = NumberValue}
local incomeMode = "Waiting" -- 2026-09-22: "Waiting" -> "Service" (IncomeService pays, permanent) | "Legacy" (the old loop pays)

--.. find-or-create, like IncomeService.Start (whichever runs first creates it; the legacy loop fires it).
--.. Keep the find and the Parent in one resumption (no yield between) or two remotes could exist.
local incomeRemote = Remotes:FindFirstChild(INCOME_REMOTE)
if not incomeRemote then
	incomeRemote = Instance.new("RemoteEvent")
	incomeRemote.Name = INCOME_REMOTE
	incomeRemote.Parent = Remotes
end

--..Placed cucumbers (LEGACY fallback only, 2026-09-22: IncomeService owns Rate / income in Service mode)..--
local function LegacyStampRate(model)
	local rate = CucumberValues.RateOfInstance(model)
	if model:GetAttribute(RATE_ATTRIBUTE) ~= rate then model:SetAttribute(RATE_ATTRIBUTE, rate) end
	return rate
end

--.. the player's placed cucumbers that earn: standing in the workspace, Owner = the player
local function LegacyEarningFor(player, callback)
	for _, model in ipairs(CollectionService:GetTagged(PLACED_TAG)) do
		if model:GetAttribute("Owner") == player.UserId and model:IsDescendantOf(workspace) then
			callback(model, tonumber(model:GetAttribute(RATE_ATTRIBUTE)) or LegacyStampRate(model))
		end
	end
end

local function LegacyIncomeOf(player)
	local total = 0
	LegacyEarningFor(player, function(_, rate) total += rate end)
	return total
end

--.. 2026-09-22 (S2 integration): the same sum while "Waiting" and IncomeService has not started - read only (no
--.. Rate stamp, nothing paid), so CashPerSec (the raid threat's fallback input) is never 0 in the first LEGACY_AFTER s
local function WaitingIncomeOf(player)
	local total = 0
	for _, model in ipairs(CollectionService:GetTagged(PLACED_TAG)) do
		if model:GetAttribute("Owner") == player.UserId and model:IsDescendantOf(workspace) then
			total += tonumber(model:GetAttribute(RATE_ATTRIBUTE)) or CucumberValues.RateOfInstance(model)
		end
	end
	return total
end

--..Display..--
local function RefreshStrength(player)
	local s = Stats[player]
	if s and s.StrengthValue then s.Strength.Value = NumberAbbrev.Abbrev(s.StrengthValue.Value) end
end

--.. 2026-09-22: Service mode shows IncomeService's Total (it writes CashPerSec itself); Legacy mode the old sum
local function RefreshIncome(player, totals)
	local s = Stats[player]
	if not s then return end
	if incomeMode == "Legacy" then
		local income = LegacyIncomeOf(player)
		s.RawRate.Value = income
		s.Rate.Value = NumberAbbrev.Abbrev(income)
		return
	end
	local income = IncomeServiceModule()
	if type(totals) ~= "table" and income and IncomeStarted() then totals = income.GetTotals(player) end
	if type(totals) == "table" then
		s.Rate.Value = NumberAbbrev.Abbrev(tonumber(totals.Total) or 0)
	elseif not IncomeStarted() then -- Waiting (2026-09-22, S2): show the placed cucumbers' income, pay nothing
		local waiting = WaitingIncomeOf(player)
		s.RawRate.Value = waiting
		s.Rate.Value = NumberAbbrev.Abbrev(waiting)
	elseif s.Rate.Value == "" then
		s.Rate.Value = NumberAbbrev.Abbrev(0)
	end
end

--..Income (LEGACY fallback, 2026-09-22): once a tick every placed cucumber pays its Rate into its owner's
--..Cash, and every client hears which cucumbers paid what (the "+X" popups over the cards)..--
local function LegacyPayIncome()
	local paidModels, paidAmounts = {}, {}
	for player in pairs(Stats) do
		if player.Parent == Players and DataService.IsLoaded(player) then
			local total = 0
			LegacyEarningFor(player, function(model, rate)
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

--..Income mode latch (2026-09-22): IncomeService pays; this loop only waits for it and runs the old pay code
--..when it never started (PetServer failed / PetServerSkipIncome). IsStarted() is checked FIRST every tick,
--..in the same synchronous step as the legacy payment, and IncomeService's producers only earn from their
--..registration time, so the two never pay the same span..--
local scriptStart = os.clock()
task.spawn(function()
	while true do
		task.wait(INCOME_TICK)
		if IncomeStarted() then
			incomeMode = "Service"
			print("[LeaderstatsService] IncomeService started - Cash/s follows its totals")
			for player in pairs(Stats) do RefreshIncome(player) end
			break
		end
		if incomeMode == "Waiting" and os.clock() - scriptStart >= LEGACY_AFTER then
			incomeMode = "Legacy"
			warn("[LeaderstatsService] IncomeService not started - legacy income loop running")
		end
		if incomeMode == "Legacy" then
			local ok, err = pcall(LegacyPayIncome)
			if not ok then warn("[LeaderstatsService] income tick: " .. tostring(err)) end
			for player in pairs(Stats) do RefreshIncome(player) end
		else
			for player in pairs(Stats) do RefreshIncome(player) end -- Waiting: Cash/s + CashPerSec stay live (not paid)
		end
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

--.. 2026-09-22: Cash/s follows IncomeService's totals (subscribed once; retried until the module exists)
task.spawn(function()
	while true do
		local income = IncomeServiceModule()
		if income and type(income.OnTotalsChanged) == "function" then
			income.OnTotalsChanged(function(player, totals)
				if incomeMode ~= "Legacy" then RefreshIncome(player, totals) end
			end)
			return
		end
		task.wait(2)
	end
end)

print(("[LeaderstatsService] leaderstats (Strength, Cash/s) ready; income = IncomeService (legacy loop -> Cash + %s if it has not started after %ds)"):format(INCOME_REMOTE, LEGACY_AFTER))
